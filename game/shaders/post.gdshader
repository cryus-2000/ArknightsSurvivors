shader_type canvas_item;
// 全屏后期：辉光（bloom）、水下滤镜（色差 + 暗角 + 焦散光斑）、亮度、观感曲线（render/look，scripts/render/look.gd）、受伤红边
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float bloom = 0.0;          // 0 关；0.4 左右为标准
uniform float bloom_threshold = 0.84;
uniform float filter_on = 0.0;      // 水下滤镜开关
uniform float aberration = 1.0;     // 色差强度（像素）
uniform float vignette = 0.14;
uniform float caustics = 0.07;
uniform float brightness = 1.0;
// 观感曲线（render/look ≥ 3 / 4；缺省值 = 不改）：亮度高光软肩、黑位、暗部伽马、饱和度
uniform float shoulder = 0.0;       // >0：乘亮度后超过它的部分按指数软肩压回 1 以内（亮度 > 1 时白色不再硬截）
uniform float black_pt = 0.0;       // 黑位：减掉后重新拉伸到 0–1
uniform float toe = 1.0;            // 暗部伽马（>1 压暗部），只作用在亮度 < pivot 的像素，按亮度缩放保色相
uniform float pivot = 0.35;
uniform float sat = 0.0;            // 饱和度增量（0.1 = +10%，按鲜艳度：灰的多加、已饱和 / 高光少加）
uniform float hurt = 0.0;           // 0..1 受伤红边
uniform float if_amt = 0.0;         // 终结技冲击帧（ult/impact_frame，ult.gd 写 post_fx）：0 关、1 开
uniform vec3 if_bg = vec3(0.0);
uniform vec3 if_fg = vec3(1.0);
uniform float if_thr = 0.25;
uniform vec2 if_c = vec2(0.5);      // 局部冲击帧圆心（屏幕 uv）
uniform float if_r = 0.0;           // 0 = 整屏；> 0 局部半径（uv，按屏幕高）
uniform float desat = 0.0;          // 0..1 去色（最终 Boss 击破演出）
uniform float time = 0.0;
// 失色区（10-25 拉普兰德 S3「噤声」，ob_summon._mark_draw 写）：屏幕 uv 椭圆（x 按宽高比校正、y 按 zone_ratio 压扁）内去色；
// zone_hole = 施放者本人（uv 中心 + 半径）保留颜色
uniform float zone_amt = 0.0;
uniform vec2 zone_c = vec2(0.5);
uniform float zone_r = 0.0;
uniform float zone_ratio = 0.6;
uniform vec3 zone_hole = vec3(0.5, 0.5, 0.0);
uniform bool zone_mask_on = false;
uniform sampler2D zone_mask : filter_nearest, repeat_disable;

vec3 sample_rgb(vec2 uv) {
	return texture(screen_tex, uv).rgb;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float r2 = dot(c, c);
	vec3 col;
	if (filter_on > 0.5 && aberration > 0.01) {
		// 色差：越靠边越明显，红蓝向外偏移
		vec2 off = c * r2 * aberration * 5.0 * SCREEN_PIXEL_SIZE;
		col.r = texture(screen_tex, uv + off).r;
		col.g = texture(screen_tex, uv).g;
		col.b = texture(screen_tex, uv - off).b;
	} else {
		col = sample_rgb(uv);
	}
	if (bloom > 0.001) {
		// 用屏幕纹理的 mip 链做廉价大范围模糊，只取亮部
		vec3 b = vec3(0.0);
		// 只用较大的 mip：光晕铺得开，但不会糊在人物轮廓上
		b += textureLod(screen_tex, uv, 3.0).rgb * 0.45;
		b += textureLod(screen_tex, uv, 4.0).rgb * 0.35;
		b += textureLod(screen_tex, uv, 5.0).rgb * 0.20;
		vec3 bright = max(b - vec3(bloom_threshold), vec3(0.0)) / (1.0 - bloom_threshold);
		col += bright * bloom;
	}
	if (filter_on > 0.5) {
		// 焦散：两层缓慢流动的波纹，只在中等亮度区域微微提亮
		vec2 p = uv * vec2(9.0, 5.0);
		float w1 = sin(p.x * 1.7 + time * 0.9 + sin(p.y * 1.3 + time * 0.7) * 1.5);
		float w2 = sin(p.y * 2.1 - time * 0.8 + sin(p.x * 0.9 - time * 0.5) * 1.5);
		float ca = pow(max(0.0, (w1 + w2) * 0.5), 3.0);
		float lum = dot(col, vec3(0.3, 0.5, 0.2));
		col += vec3(0.4, 0.8, 1.0) * ca * caustics * smoothstep(0.02, 0.25, lum);
		// 暗角
		col *= 1.0 - r2 * vignette * 2.0;
	}
	if (shoulder > 0.001 && brightness > shoulder + 0.01) {
		// 软肩：x·b 在 shoulder 以下原样，以上按指数曲线压，输入 1 恰好落到 1（高光层次保留，不再整片截白）
		vec3 x = col * brightness;
		float k = 2.5 / (brightness - shoulder);
		float n = 1.0 - exp(-k * (brightness - shoulder));
		vec3 y = shoulder + (1.0 - shoulder) * (1.0 - exp(-k * max(x - shoulder, vec3(0.0)))) / n;
		col = mix(x, y, step(vec3(shoulder), x));
	} else {
		col *= brightness;
	}
	if (black_pt > 0.0001) {
		col = max(col - vec3(black_pt), vec3(0.0)) / (1.0 - black_pt);
	}
	if (toe > 1.001 || sat > 0.001 || sat < -0.001) {
		float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
		if (toe > 1.001 && l > 0.0001 && l < pivot) {
			col *= pivot * pow(l / pivot, toe) / l;
			l = dot(col, vec3(0.2126, 0.7152, 0.0722));
		}
		// 饱和度按「鲜艳度」加：本来就饱和的、接近截顶的像素少加（不把高光推到截白）
		float mx = max(col.r, max(col.g, col.b));
		float s0 = mx > 0.0001 ? (mx - min(col.r, min(col.g, col.b))) / mx : 0.0;
		float amt = sat * (1.0 - s0) * (1.0 - smoothstep(0.75, 1.0, mx));
		col = max(mix(vec3(l), col, 1.0 + amt), vec3(0.0));
	}
	if (desat > 0.001) {
		col = mix(col, vec3(dot(col, vec3(0.299, 0.587, 0.114))), desat);
	}
	if (zone_amt > 0.001 && zone_r > 0.0001) {
		float asp = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
		vec2 dz = vec2((uv.x - zone_c.x) * asp, (uv.y - zone_c.y) / zone_ratio);
		float f = 1.0 - smoothstep(zone_r * 0.9, zone_r, length(dz));
		if (zone_mask_on) {
			f *= 1.0 - texture(zone_mask, uv).a;
		}
		float l = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(col, clamp(vec3(l) * 1.35 + vec3(0.06), 0.0, 1.0) * vec3(0.84, 0.93, 1.08), f * zone_amt);   // 冷银偏蓝（用户 10-25）：去色 + 提亮 + 冷调
	}
	if (hurt > 0.001) {
		float edge = smoothstep(0.12, 0.5, r2);
		col = mix(col, vec3(0.9, 0.08, 0.12), edge * hurt * 0.75);
	}
	if (if_amt > 0.5) {   // 终结技冲击帧（ult.gd _if_*）：比周围亮的（敌人 / 主体特效）成剪影，其余压成底色；if_r > 0 只在圆里
		float l = dot(col, vec3(0.299, 0.587, 0.114));
		float lb = dot(textureLod(screen_tex, uv, 5.0).rgb, vec3(0.299, 0.587, 0.114));
		vec3 tw = mix(if_bg, if_fg, step(max(if_thr, lb * 1.15 + 0.04), l));
		float f = 1.0;
		if (if_r > 0.0001) {
			float asp = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
			f = 1.0 - smoothstep(if_r * 0.85, if_r, length(vec2((uv.x - if_c.x) * asp, uv.y - if_c.y)));
		}
		col = mix(col, tw, f);
	}
	COLOR = vec4(col, 1.0);
}
