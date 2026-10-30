shader_type canvas_item;
// 光学观感原型（render/optical.gd，balance render/optical，缺省关；10-23 用户参照像素洞穴 + Hyper Light Drifter）。
// 一个全屏 pass 取代 post.gdshader + dof.gdshader，按顺序：
//   ① 像素格：屏幕按「1 美术像素 = cell 个窗口像素」的格子取样（格子锁在世界坐标上，镜头平移时整格跟着走 = 亚像素补偿）
//   ② 光池：队长灯火位置周围暖色、边缘柔和，光池外压暗；很亮的像素（发光体）不压
//   ③ 调色 LUT（optical_lut.png，16³ 展开 256×16）
//   ④ 辉光：只从「亮且有色」的像素散出（屏幕 mip 链 2–5 级 ≈ 1/4 到 1/32 分辨率的多级模糊），按屏幕混合叠回，不过曝
//   ⑤ 暗角 + 受伤红边 / 去色（沿用 post 的接口）
uniform sampler2D screen_px : hint_screen_texture, filter_nearest;
uniform sampler2D screen_mip : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D lut : filter_linear, repeat_disable;
uniform vec2 grid_origin = vec2(0.0);   // 世界原点在窗口里的像素坐标
uniform float cell = 2.0;               // 1 美术像素 = cell 个窗口像素
uniform float pixel_on = 1.0;
uniform vec2 lamp_px = vec2(640.0, 360.0);   // 灯火在窗口里的像素坐标
uniform float lamp_r = 300.0;           // 光池半径（窗口像素）
uniform float pool_dark = 1.0;          // 光池外的亮度（10-23 用户：原本亮度没问题，缺省 1 = 不压暗；旋钮 render/optical_pool_dark）
uniform vec3 pool_warm = vec3(1.0, 1.0, 1.0);    // 光池里的色（10-23 用户嫌发黄：改中性，暖色只留给灯火本身）
// 深海滤镜（10-23 用户：「深海的色调，清淡、不要浓稠感，画面不要太暗」）：色相往青蓝偏、再把亮度按原值拉回（只改色不改明暗）；
// 屏幕上方略深一点蓝（远处的水）；极淡的水纹焦散（缓慢流动、只在中间调上 ±2%）
uniform vec3 sea_tint = vec3(0.86, 1.0, 1.12);
uniform float sea_amt = 0.55;
uniform float sea_depth = 0.06;
uniform float caustics = 0.02;
uniform float time = 0.0;
uniform float emissive_th = 0.72;       // 亮度高于此（且偏饱和或近白）当发光体：不压暗、散辉光
uniform float glow = 0.9;
uniform vec4 dl_pos[12];               // ⑥ 特效动态照明（render/optical.gd _dyn_lights）：xy 窗口像素、z 半径（窗口像素）
uniform vec4 dl_col[12];               // rgb = 颜色 × 强度（随寿命衰减）
uniform int dl_n = 0;
// 防油腻（10-23 用户同意，特效处理第 1 步）：辉光 / 光池 / 特效照明一律 steps 阶硬边环（不平滑），在美术像素格上算；
// 以队长（灯火）为中心 local_r 窗口像素内的发光单独限量（local_budget），中心不糊
uniform float steps = 0.0;              // 0 = 平滑（旧）；3 = 三阶硬边
uniform float local_budget = 0.5;
uniform float local_r = 240.0;
uniform float glow_budget = 0.06;      // 全屏发光总量预算（屏幕平均发光度）：超出按比例压辉光与亮部（多个大招叠加不过曝，10-23 特效处理 ②）
uniform float lut_on = 1.0;
uniform float vignette = 0.12;
uniform float hurt = 0.0;
uniform float if_amt = 0.0;            // 终结技冲击帧（ult/impact_frame，post_fx 转写）：0 关、1 开
uniform vec3 if_bg = vec3(0.0);
uniform vec3 if_fg = vec3(1.0);
uniform float if_thr = 0.25;
uniform vec2 if_c = vec2(0.5);         // 局部冲击帧圆心（屏幕 uv）
uniform float if_r = 0.0;              // 0 = 整屏；> 0 局部半径（uv，按屏幕高）
uniform float desat = 0.0;
// 失色区（10-25 拉普兰德 S3「噤声」；同 post.gdshader，参数由 optical.gd 从 g.post 转来）
uniform float zone_amt = 0.0;
uniform vec2 zone_c = vec2(0.5);
uniform float zone_r = 0.0;
uniform float zone_ratio = 0.6;
uniform vec3 zone_hole = vec3(0.5, 0.5, 0.0);
uniform bool zone_mask_on = false;
uniform sampler2D zone_mask : filter_nearest, repeat_disable;
uniform float brightness = 1.0;
uniform float sat = 1.0;               // docs/139 §6 试验旋钮 render/optical_sat：LUT 之后整体饱和度（1 = 不变）

vec3 lut_apply(vec3 c) {
	c = clamp(c, 0.0, 1.0);
	float b = c.b * 15.0;
	float b0 = floor(b);
	float b1 = min(b0 + 1.0, 15.0);
	float fb = b - b0;
	vec2 px = vec2(1.0 / 256.0, 1.0 / 16.0);
	vec2 uv0 = vec2((b0 * 16.0 + c.r * 15.0 + 0.5) * px.x, (c.g * 15.0 + 0.5) * px.y);
	vec2 uv1 = vec2((b1 * 16.0 + c.r * 15.0 + 0.5) * px.x, uv0.y);
	return mix(texture(lut, uv0).rgb, texture(lut, uv1).rgb, fb);
}

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// 发光度：亮度过阈值的部分，按饱和度（或近白）加权
float emissive(vec3 c) {
	float l = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	float s = l > 0.001 ? (l - mn) / l : 0.0;
	float e = smoothstep(emissive_th, 1.0, l);
	return e * mix(0.55, 1.0, smoothstep(0.15, 0.5, s));
}

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 p = SCREEN_UV * res;
	vec2 uv = SCREEN_UV;
	if (pixel_on > 0.5 && cell > 1.01) {
		vec2 q = floor((p - grid_origin) / cell) * cell + grid_origin + cell * 0.5;
		uv = clamp(q, vec2(0.5), res - 0.5) * SCREEN_PIXEL_SIZE;
	}
	vec3 base = textureLod(screen_px, uv, 0.0).rgb;   // 显式取第 0 级：格子边上 uv 跳变会让自动 mip 选到高层级而发糊
	float em = emissive(base);
	// 全屏发光总量：mip 6 级上取 4×3 个点的发光度均值（≈ 屏幕平均），超预算的倍数决定压多少
	float tot = 0.0;
	for (int iy = 0; iy < 3; iy++) {
		for (int ix = 0; ix < 4; ix++) {
			tot += emissive(textureLod(screen_mip, vec2((float(ix) + 0.5) / 4.0, (float(iy) + 0.5) / 3.0), 6.0).rgb * 1.3);
		}
	}
	tot /= 12.0;
	float over = clamp(glow_budget / max(tot, 0.0001), 0.35, 1.0);
	base *= 1.0 - em * (1.0 - over) * 0.45;   // 超预算时亮部按比例压暗（最多约 30%）
	// ② 光池
	vec2 pc = p;   // 光照 / 辉光取样位置：开阶梯时吸附到美术像素格中心（硬边环落在 2 px 格上）
	if (steps > 0.5) {
		pc = floor((p - grid_origin) / max(cell, 1.0)) * max(cell, 1.0) + grid_origin + max(cell, 1.0) * 0.5;
	}
	float d = length(pc - lamp_px) / max(lamp_r, 1.0);
	float pool = 1.0 - smoothstep(0.4, 1.3, d);
	if (steps > 0.5) {
		pool = ceil(pool * steps - 0.001) / steps;
	}
	vec3 lit = base * mix(vec3(pool_dark), pool_warm, pool);
	base = mix(lit, base, em);
	// ⑥ 特效临时光：柔和半径（平方衰减），照亮已有的颜色（乘）+ 极淡的本色（加），发光体本身不再加
	vec3 dla = vec3(0.0);
	for (int i = 0; i < 12; i++) {
		if (i >= dl_n) {
			break;
		}
		float dd = length(pc - dl_pos[i].xy) / max(dl_pos[i].z, 1.0);
		float f = 1.0 - smoothstep(0.0, 1.0, dd);
		f *= f;
		if (steps > 0.5) {
			f = floor(f * steps + 0.35) / steps;   // 三阶硬边环
		}
		dla += dl_col[i].rgb * f;
	}
	dla = min(dla, vec3(1.2));
	base += base * dla * 0.9 * (1.0 - em);   // 只照亮已有颜色，不加白（防油腻 ④）
	// ③ LUT
	if (lut_on > 0.5) {
		base = lut_apply(base * brightness);
	} else {
		base *= brightness;
	}
	base = mix(vec3(luma(base)), base, sat);
	// ④ 辉光：mip 2–5（多级模糊），只取发光部分
	vec3 g = vec3(0.0);
	vec2 guv = pc * SCREEN_PIXEL_SIZE;
	vec3 m2 = textureLod(screen_mip, guv, 2.0).rgb;
	vec3 m3 = textureLod(screen_mip, guv, 3.0).rgb;
	vec3 m4 = textureLod(screen_mip, guv, 4.0).rgb;
	vec3 m5 = textureLod(screen_mip, guv, 5.0).rgb;
	g += m2 * emissive(m2) * 0.30;
	g += m3 * emissive(m3) * 0.30;
	g += m4 * emissive(m4 * 1.15) * 0.25;
	g += m5 * emissive(m5 * 1.3) * 0.25;
	g *= glow * over;
	// 局部预算：队长周围 local_r 内的发光度超过 local_budget 时按比例压（辉光与亮部都压）
	float loc_d = length(pc - lamp_px) / max(local_r, 1.0);
	if (loc_d < 1.0) {
		vec2 luv = clamp(lamp_px * SCREEN_PIXEL_SIZE, vec2(0.0), vec2(1.0));
		float eloc = emissive(textureLod(screen_mip, luv, 4.0).rgb * 1.3);
		float kl = clamp(local_budget / max(eloc, 0.0001), 0.4, 1.0);
		float w = 1.0 - smoothstep(0.7, 1.0, loc_d);
		g *= mix(1.0, kl, w);
	}
	if (steps > 0.5) {
		float gm = max(g.r, max(g.g, g.b));
		float gq = floor(gm * steps * 2.0 + 0.3) / (steps * 2.0);   // 辉光分阶（硬边环）
		g *= gm > 0.0001 ? gq / gm : 0.0;
	}	base = 1.0 - (1.0 - base) * (1.0 - clamp(g, 0.0, 1.0));   // 屏幕混合：越亮越收，不会硬截成白
	// ⑤ 深海滤镜：偏青蓝但保持亮度
	float l0 = luma(base);
	vec3 tinted = base * mix(vec3(1.0), sea_tint, sea_amt);
	float l1 = luma(tinted);
	base = tinted * (l1 > 0.0001 ? l0 / l1 : 1.0);
	base = mix(base, base * vec3(0.92, 1.0, 1.1), sea_depth * (1.0 - SCREEN_UV.y));
	if (caustics > 0.0001) {
		vec2 w = (p - grid_origin) / max(cell, 1.0) * 0.06;
		float cs = sin(w.x * 1.7 + time * 0.6) * sin(w.y * 1.3 - time * 0.45) + sin((w.x + w.y) * 0.9 + time * 0.3) * 0.5;
		float mid = smoothstep(0.08, 0.35, l0) * (1.0 - smoothstep(0.6, 0.9, l0));
		base *= 1.0 + caustics * cs * mid;
	}
	// ⑥ 暗角 / 受伤 / 去色
	vec2 c = SCREEN_UV - 0.5;
	base *= 1.0 - dot(c, c) * vignette * 2.0;
	if (desat > 0.001) {
		base = mix(base, vec3(luma(base)), desat);
	}
	if (zone_amt > 0.001 && zone_r > 0.0001) {
		float asp = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
		vec2 dz = vec2((SCREEN_UV.x - zone_c.x) * asp, (SCREEN_UV.y - zone_c.y) / zone_ratio);
		float zf = 1.0 - smoothstep(zone_r * 0.9, zone_r, length(dz));
		if (zone_mask_on) {
			zf *= 1.0 - texture(zone_mask, SCREEN_UV).a;
		}
		base = mix(base, clamp(vec3(luma(base)) * 1.35 + vec3(0.06), 0.0, 1.0) * vec3(0.84, 0.93, 1.08), zf * zone_amt);   // 冷银偏蓝（用户 10-25）
	}
	if (hurt > 0.001) {
		float e = smoothstep(0.25, 0.75, length(c) * 1.4);
		base = mix(base, vec3(0.6, 0.05, 0.08), e * hurt * 0.55);
	}
	if (if_amt > 0.5) {   // 终结技冲击帧（ult.gd _if_*）：比周围亮的（敌人 / 主体特效）成剪影，其余压成底色；if_r > 0 只在圆里
		float l = luma(base);
		float lb = luma(textureLod(screen_mip, SCREEN_UV, 5.0).rgb);
		vec3 tw = mix(if_bg, if_fg, step(max(if_thr, lb * 1.15 + 0.04), l));
		float f = 1.0;
		if (if_r > 0.0001) {
			float asp = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
			f = 1.0 - smoothstep(if_r * 0.85, if_r, length(vec2((SCREEN_UV.x - if_c.x) * asp, SCREEN_UV.y - if_c.y)));
		}
		base = mix(base, tw, f);
	}
	COLOR = vec4(base, 1.0);
}
