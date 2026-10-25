shader_type canvas_item;
// 蚀刻章页背景（scripts/screens/medals_ui.gd，10-25）：Codex 原图 ocean_backdrop_v7 的低频形变 + 持续可见的水下运动，按标题页像素精度画。
// 画进 428×240 的 SubViewport（一个片元 = 一个美术像素，1280×720 下 3 逻辑像素一格）：原图（不压色，四周留 pad 格）按低频位移场取样，
// 再就近取 24 色色板（无抖动）——形变后每帧仍是干净的像素画。
// 10-25 晚用户看录像「背景应该是动态的」：形变加大加快（两层位移场），右上原图光线处加斜向光带缓缓扫过（亮度只两档，同标题页光柱），
// 再加一层缓慢下沉的海雪像素点（暗淡、不抢章面）。所有运动都按 period（24 秒）首尾相接。
// still = 1（减少动态效果）：不位移、无光带与海雪，只画静帧。最后压一层 #001020 22%（同 Codex 原型）。

uniform sampler2D src : filter_linear, repeat_disable;
uniform sampler2D pal : filter_nearest, repeat_disable;
uniform float time = 0.0;
uniform float still = 0.0;
uniform vec2 grid = vec2(428.0, 240.0);
uniform float pad = 6.0;
uniform float amp = 5.0;          // 最大位移（美术像素）
uniform float period = 24.0;
uniform int pal_n = 24;


float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 p = floor(UV * grid) + 0.5;
	float ph = TAU * mod(time, period) / period;     // 0..TAU，一周期
	vec2 d = vec2(0.0);
	if (still < 0.5) {
		// 两层位移场：大尺度慢涌（每周期绕一圈）+ 小一号的快涌（每周期两圈）
		vec2 q = p / vec2(85.0, 51.0);
		vec2 l1 = vec2(cos(ph), sin(ph)) * 1.6;
		vec2 l2 = vec2(cos(2.0 * ph + 1.3), sin(2.0 * ph + 1.3)) * 1.1;
		d = (vec2(vnoise(q + l1), vnoise(q + vec2(5.2, 1.3) - l1.yx)) - 0.5) * 2.0 * amp;
		d += (vec2(vnoise(q * 2.1 + l2 + 9.0), vnoise(q * 2.1 - l2.yx + 3.7)) - 0.5) * amp * 0.6;
		d.x += sin(ph) * 2.0;                         // 整体左右缓荡
	}
	vec3 c = texture(src, (p + pad + d) / (grid + 2.0 * pad)).rgb;
	vec3 best = c;
	float bd = 1e9;
	for (int i = 0; i < pal_n; i++) {
		vec3 k = texelFetch(pal, ivec2(i, 0), 0).rgb;
		vec3 e = c - k;
		float dd = dot(e * e, vec3(0.30, 0.59, 0.11));
		if (dd < bd) {
			bd = dd;
			best = k;
		}
	}
	vec3 col = best;
	if (still < 0.5) {
		// 光带：沿原图光线方向（右上往左下斜）的几条带，每周期整体扫过两次；只在右上原有光线的区域，往下 / 往左渐弱；亮度两档
		vec2 dir = normalize(vec2(-0.55, 1.0));
		float s = dot(p, vec2(dir.y, -dir.x));      // 垂直光线方向的坐标
		float band = sin(s * 0.075 + 2.0 * ph) * 0.6 + sin(s * 0.031 - ph + 0.8) * 0.4;
		float reg = clamp(1.0 - p.y / 200.0, 0.0, 1.0) * smoothstep(120.0, 340.0, p.x + p.y * 0.55);
		float lv = band * reg;
		float step2 = lv > 0.55 ? 2.0 : (lv > 0.28 ? 1.0 : 0.0);
		col += vec3(0.045, 0.08, 0.12) * step2;
		// 海雪：16 格一胞、每胞一粒，整片每周期下沉 192 格（12 胞，首尾相接）并带一点横摆；约四成胞有粒
		vec2 sp = p + vec2(0.0, -192.0 * mod(time, period) / period);
		vec2 cell = floor(sp / 16.0);
		float h = hash(cell + 17.0);
		if (h < 0.42) {
			vec2 at = floor(vec2(hash(cell + 3.1), hash(cell + 7.7)) * 14.0) + 1.0;
			at.x += floor(sin(ph * 2.0 + h * 40.0) * 1.5 + 0.5);
			vec2 lp = floor(sp - cell * 16.0);
			if (lp == at) {
				float bright = 0.35 + 0.4 * hash(cell + 11.0);
				col = mix(col, vec3(0.62, 0.78, 0.90), bright * (0.5 + 0.5 * clamp(1.0 - p.y / 260.0, 0.0, 1.0)));
			}
		}
	}
	COLOR = vec4(mix(col, vec3(0.0, 0.063, 0.125), 0.22), 1.0);
}
