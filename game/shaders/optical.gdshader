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
uniform vec3 pool_warm = vec3(1.05, 1.0, 0.92);   // 光池里只偏一点暖，不提亮
uniform float emissive_th = 0.72;       // 亮度高于此（且偏饱和或近白）当发光体：不压暗、散辉光
uniform float glow = 0.9;
uniform float lut_on = 1.0;
uniform float vignette = 0.12;
uniform float hurt = 0.0;
uniform float desat = 0.0;
uniform float brightness = 1.0;

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
	// ② 光池
	float d = length(p - lamp_px) / max(lamp_r, 1.0);
	float pool = 1.0 - smoothstep(0.4, 1.3, d);
	vec3 lit = base * mix(vec3(pool_dark), pool_warm, pool);
	base = mix(lit, base, em);
	// ③ LUT
	if (lut_on > 0.5) {
		base = lut_apply(base * brightness);
	} else {
		base *= brightness;
	}
	// ④ 辉光：mip 2–5（多级模糊），只取发光部分
	vec3 g = vec3(0.0);
	vec3 m2 = textureLod(screen_mip, SCREEN_UV, 2.0).rgb;
	vec3 m3 = textureLod(screen_mip, SCREEN_UV, 3.0).rgb;
	vec3 m4 = textureLod(screen_mip, SCREEN_UV, 4.0).rgb;
	vec3 m5 = textureLod(screen_mip, SCREEN_UV, 5.0).rgb;
	g += m2 * emissive(m2) * 0.30;
	g += m3 * emissive(m3) * 0.30;
	g += m4 * emissive(m4 * 1.15) * 0.25;
	g += m5 * emissive(m5 * 1.3) * 0.25;
	g *= glow;
	base = 1.0 - (1.0 - base) * (1.0 - clamp(g, 0.0, 1.0));   // 屏幕混合：越亮越收，不会硬截成白
	// ⑤ 暗角 / 受伤 / 去色
	vec2 c = SCREEN_UV - 0.5;
	base *= 1.0 - dot(c, c) * vignette * 2.0;
	if (desat > 0.001) {
		base = mix(base, vec3(luma(base)), desat);
	}
	if (hurt > 0.001) {
		float e = smoothstep(0.25, 0.75, length(c) * 1.4);
		base = mix(base, vec3(0.6, 0.05, 0.08), e * hurt * 0.55);
	}
	COLOR = vec4(base, 1.0);
}
