shader_type canvas_item;
// 蚀刻章页背景（scripts/screens/medals_ui.gd，10-25）：Codex 原图 ocean_backdrop_v7 的低频形变，按标题页像素精度画。
// 画进 428×240 的 SubViewport（一个片元 = 一个美术像素，1280×720 下 3 逻辑像素一格）：原图（不压色，四周留 pad 格）按一张低频位移场取样，
// 再就近取 24 色色板（无抖动）——形变后每帧仍是干净的像素画，不另加光束 / 浮尘。位移场在噪声空间沿圆走一圈 = 24 秒一个周期，首尾相接。
// still = 1（减少动态效果）：不位移，只画静帧。最后压一层 #001020 22%（同 Codex 原型）。

uniform sampler2D src : filter_linear, repeat_disable;
uniform sampler2D pal : filter_nearest, repeat_disable;
uniform float time = 0.0;
uniform float still = 0.0;
uniform vec2 grid = vec2(428.0, 240.0);
uniform float pad = 6.0;
uniform float amp = 3.0;          // 最大位移（美术像素）
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
	vec2 d = vec2(0.0);
	if (still < 0.5) {
		float a = 6.28318531 * mod(time, period) / period;
		vec2 loop = vec2(cos(a), sin(a)) * 0.9;
		vec2 q = p / vec2(85.0, 51.0);    // 同 Codex 原型的 baseFrequency .003 / .005（布局单位）换算成美术像素
		d = (vec2(vnoise(q + loop), vnoise(q + vec2(5.2, 1.3) - loop.yx)) - 0.5) * 2.0 * amp;
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
	COLOR = vec4(mix(best, vec3(0.0, 0.063, 0.125), 0.22), 1.0);
}
