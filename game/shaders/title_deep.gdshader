// 标题页·深海水母 v2（docs/67 §13.3，10-24 用户：按游戏像素精度、水母要能动）。
// 画在 428×240 的 SubViewport 里（1 美术像素 = 3 逻辑像素），一个片元就是一个美术像素，所有运动都落在像素格上。
// 底图 bg（水母已拆走）+ 三只水母图层：伞体收缩 → 沿身体轴推进、松开时缓缓回落，触须按离伞远近带相位差摆动；
// 另有光柱带缓移、上升气泡、下落海雪、远处鱼群。整屏亮度不脉动，节奏都在 4 秒以上。still = 1：减少动态效果的静帧。
shader_type canvas_item;

uniform sampler2D bg : filter_nearest, repeat_disable;
uniform sampler2D j0 : filter_nearest, repeat_disable;
uniform sampler2D j1 : filter_nearest, repeat_disable;
uniform sampler2D j2 : filter_nearest, repeat_disable;
uniform sampler2D g0 : filter_linear, repeat_disable;
uniform sampler2D g1 : filter_linear, repeat_disable;
uniform sampler2D g2 : filter_linear, repeat_disable;
// 每只水母：rect = 图层在底图上的左上角 / 尺寸；pose = 伞顶锚点 xy、伞体长度、触须摆幅；axis = 伞顶 → 触须方向
uniform vec4 rect0; uniform vec4 rect1; uniform vec4 rect2;
uniform vec4 pose0; uniform vec4 pose1; uniform vec4 pose2;
uniform vec2 axis0; uniform vec2 axis1; uniform vec2 axis2;
uniform float glow_pad = 12.0;
uniform float glow_k = 0.42;
uniform float time = 0.0;
uniform float still = 0.0;

const vec2 SIZE = vec2(428.0, 240.0);

float hash(float x) {
	return fract(sin(x * 43.132 + 5.31) * 213.41);
}

// 收缩曲线：周期 per，前 22% 快收、其余慢放（0 = 舒张，1 = 收紧）
float pulse(float t, float per) {
	float u = fract(t / per);
	return u < 0.22 ? smoothstep(0.0, 1.0, u / 0.22) : 1.0 - smoothstep(0.0, 1.0, (u - 0.22) / 0.78);
}

// 输出像素 p 在水母图层里的取样位置（逆变换）：伞体段按收缩缩放，触须段跟着伞底平移、再按相位差横摆
vec2 jelly_uv(vec2 p, vec4 rect, vec4 pose, vec2 axis, vec2 drift, float c, float t, float ph) {
	vec2 perp = vec2(-axis.y, axis.x);
	float bell = pose.z;
	float sy = 1.0 - 0.11 * c;
	float sx = 1.0 + 0.07 * c;
	vec2 anchor = pose.xy + drift - axis * (2.4 * c * bell / 40.0);
	vec2 d = p - anchor;
	float A = dot(d, axis);
	float X = dot(d, perp);
	float along;
	float across;
	if (A < bell * sy) {
		along = A / sy;
		across = X / mix(sx, 1.0, smoothstep(bell * 0.7, bell, along));
	} else {
		along = A + bell * (1.0 - sy);
		float s = clamp((along - bell) / (bell * 2.2), 0.0, 1.0);
		float sway = pose.w * s * sqrt(s) * sin(t * 6.2831853 / 7.0 + ph - along * 0.11) + 0.8 * pose.w * s * c;
		across = X - sway;
	}
	vec2 q = pose.xy + axis * along + perp * across;   // 图层未变形时的位置（底图坐标）
	return q - rect.xy;
}

void layer(inout vec3 col, sampler2D tex, sampler2D gl, vec4 rect, vec2 uv) {
	vec2 g = (uv + glow_pad) / (rect.zw + 2.0 * glow_pad);
	if (g.x > 0.0 && g.y > 0.0 && g.x < 1.0 && g.y < 1.0) {
		col += vec3(0.47, 0.78, 0.92) * texture(gl, g).r * glow_k;
	}
	if (uv.x >= 0.0 && uv.y >= 0.0 && uv.x < rect.z && uv.y < rect.w) {
		vec4 j = texelFetch(tex, ivec2(floor(uv)), 0);
		col = mix(col, j.rgb, j.a);
	}
}

void fragment() {
	vec2 p = floor(UV * SIZE) + 0.5;
	float t = still > 0.5 ? 0.0 : time;
	float mv = still > 0.5 ? 0.0 : 1.0;
	vec3 col = texelFetch(bg, ivec2(p), 0).rgb;
	// 光柱：从右上斜下的几条宽带，带位置 40 秒一个来回、亮度只分两档（不闪）
	float band = sin((p.x - p.y * 0.62) * 0.05 + 0.6 * sin(t * 6.2831853 / 40.0));
	float top = 1.0 - smoothstep(20.0, 170.0, p.y);
	float zone = smoothstep(150.0, 230.0, p.x) * (1.0 - smoothstep(380.0, 420.0, p.x));
	col += vec3(0.30, 0.52, 0.66) * step(0.55, band) * 0.045 * top * zone;
	// 远处鱼群：一队从左往右穿过中景，约 46 秒一趟，进出时淡入淡出
	float age = fract(t / 46.0 + 0.3);
	float sf = mv * smoothstep(0.0, 0.12, age) * (1.0 - smoothstep(0.85, 1.0, age));
	for (int k = 0; k < 7; k++) {
		float id = float(k);
		vec2 fish = vec2(130.0 + id * 6.0 + mod(id, 2.0) * 3.0 + 190.0 * age, 118.0 + mod(id * 5.0, 7.0) * 2.0 + 1.5 * sin(t * 0.9 + id));
		vec2 f = floor(p) - floor(fish);
		float body = step(abs(f.y), 0.0) * step(-2.0, f.x) * step(f.x, 1.0);
		float tail = step(abs(f.y), 1.0) * step(f.x, -3.0) * step(-3.0, f.x);
		col = mix(col, vec3(0.05, 0.10, 0.13), max(body, tail) * 0.7 * sf);
	}
	// 三只水母（远 → 近）：各自的游泳周期与漂移
	float c2 = mv * pulse(t + 1.7, 4.6);
	vec2 d2 = mv * vec2(3.0 * sin(t * 6.2831853 / 29.0 + 1.0), 4.0 * sin(t * 6.2831853 / 19.0));
	layer(col, j2, g2, rect2, jelly_uv(p, rect2, pose2, axis2, d2, c2, t, 2.0));
	float c1 = mv * pulse(t + 0.6, 5.2);
	vec2 d1 = mv * vec2(5.0 * sin(t * 6.2831853 / 33.0 + 2.0), 6.0 * sin(t * 6.2831853 / 21.0 + 0.5));
	layer(col, j1, g1, rect1, jelly_uv(p, rect1, pose1, axis1, d1, c1, t, 1.0));
	float c0 = mv * pulse(t, 6.0);
	vec2 d0 = mv * vec2(7.0 * sin(t * 6.2831853 / 37.0), 6.0 * sin(t * 6.2831853 / 26.0 + 1.2));
	layer(col, j0, g0, rect0, jelly_uv(p, rect0, pose0, axis0, d0, c0, t, 0.0));
	// 上升气泡（1 像素，偶尔 2 像素）与下落海雪（暗、慢）
	for (int i = 0; i < 16; i++) {
		float id = float(i);
		float ba = fract(t / 16.0 + hash(id + 4.0));
		vec2 b = vec2(230.0 + hash(id + 17.0) * 140.0 + 2.0 * sin(t * 0.8 + id * 1.7), 170.0 + hash(id + 29.0) * 40.0 - ba * 110.0);
		vec2 dd = abs(floor(p) - floor(b));
		float big = step(0.8, hash(id + 51.0));
		float dot_px = step(max(dd.x, dd.y), big * 0.5 + 0.1);
		float fade = smoothstep(0.0, 0.15, ba) * (1.0 - smoothstep(0.75, 1.0, ba));
		col = mix(col, vec3(0.55, 0.78, 0.86), dot_px * fade * 0.55 * mv);
	}
	for (int i = 0; i < 26; i++) {
		float id = float(i);
		float sa = fract(t / 38.0 + hash(id + 90.0));
		vec2 s = vec2(160.0 + hash(id + 61.0) * 260.0 + 3.0 * sin(t * 0.35 + id), -4.0 + sa * 200.0);
		vec2 dd = abs(floor(p) - floor(s));
		float fade = smoothstep(0.0, 0.1, sa) * (1.0 - smoothstep(0.8, 1.0, sa));
		col = mix(col, vec3(0.32, 0.46, 0.54), step(max(dd.x, dd.y), 0.1) * fade * 0.5 * mv);
	}
	COLOR = vec4(col, 1.0);
}
