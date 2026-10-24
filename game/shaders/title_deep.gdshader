// 标题页·深海水母场景（docs/67 §13）：移植 Codex codex/ui-shell 46 版 motion.js 的片元着色器。
// 画在 1280×720 的 SubViewport 里（原图 640×360 最近邻、半个原像素的位移步长），再整屏铺开，开销与屏幕分辨率无关。
// 10-24 精修：循环 12 → 20 秒（节奏放慢）；加水母柔光（glow.png 线性取样，随形变一起走）；still = 1 时给减少动态用的静帧（无鱼群、气泡）。
shader_type canvas_item;

uniform sampler2D image : filter_nearest, repeat_disable;
uniform sampler2D glow : filter_linear, repeat_disable;
uniform float time = 0.0;
uniform float still = 0.0;
uniform float glow_k = 0.55;

const vec2 SIZE = vec2(640.0, 360.0);
const float LOOP = 20.0;

float ellipse(vec2 p, vec2 c, vec2 r) {
	return 1.0 - smoothstep(0.8, 1.35, length((p - c) / r));
}

float hash(float x) {
	return fract(sin(x * 43.132 + 5.31) * 213.41);
}

vec3 lit(vec2 q) {
	return texture(image, q / SIZE).rgb + vec3(0.47, 0.78, 0.90) * texture(glow, q / SIZE).r * glow_k;
}

void fragment() {
	vec2 p = UV * SIZE;
	if (still > 0.5) {
		COLOR = vec4(lit(p), 1.0);
	} else {
		float tm = mod(time, LOOP);
		float phase = TAU * tm / LOOP;
		vec2 q = p;
		// 主水母：伞体与细触须共用一个包络，整体漂移 + 弯曲，不分段（无断层）
		vec2 ml = p - vec2(386.0, 175.0);
		vec2 along_axis = vec2(-0.56, 0.82849);
		vec2 across_axis = vec2(0.82849, 0.56);
		float across = dot(ml, across_axis);
		float along = dot(ml, along_axis);
		float mw = 1.0 - smoothstep(1.05, 1.70, length(vec2(across / 64.0, along / 111.0)));
		mw *= smoothstep(294.0, 338.0, p.x + 0.45 * (p.y - 160.0));
		mw *= 1.0 - smoothstep(264.0, 296.0, p.y);
		float bend = smoothstep(-70.0, 110.0, along);
		vec2 drift = vec2(1.65 * sin(phase), -2.15 * sin(phase));
		vec2 flex = across_axis * (1.25 * bend * bend * sin(phase * 2.0 - bend * 2.4));
		vec2 stroke = across_axis * (across * 0.012 * sin(phase * 3.0) * (1.0 - bend));
		q -= (drift + flex + stroke) * mw;
		// 两只小水母错相
		float near_j = ellipse(p, vec2(274.0, 223.0), vec2(20.0, 27.0));
		q -= vec2(1.4 * sin(phase + 1.3), 2.1 * sin(phase + 0.4)) * near_j;
		q.x += sin(phase * 2.0 - (p.y - 209.0) * 0.13) * near_j * clamp((p.y - 211.0) / 28.0, 0.0, 1.0);
		float far_j = ellipse(p, vec2(520.0, 109.0), vec2(12.0, 20.0));
		q -= vec2(0.9 * sin(phase + 2.1), 1.4 * sin(phase + 1.7)) * far_j;
		// 光柱纹理缓慢横移（不整屏变亮）；水面波纹与悬垂物各走各的节奏
		float upper = smoothstep(337.0, 398.0, p.x) * (1.0 - smoothstep(540.0, 577.0, p.x)) * (1.0 - smoothstep(65.0, 84.0, p.y));
		q.x += 1.7 * sin(phase) * upper;
		float surface = smoothstep(320.0, 376.0, p.x) * (1.0 - smoothstep(555.0, 587.0, p.x)) * (1.0 - smoothstep(23.0, 45.0, p.y));
		q.x += 1.4 * sin(p.y * 0.17 - phase * 2.0) * surface;
		q.y += 0.55 * sin(p.x * 0.055 - phase * 2.0) * surface;
		float ropes = ellipse(p, vec2(294.0, 72.0), vec2(36.0, 54.0));
		float tip = smoothstep(30.0, 119.0, p.y);
		q.x += 0.8 * sin(phase * 2.0) * tip * tip * ropes;
		q = clamp(q, vec2(0.25), SIZE - 0.25);
		vec3 color = lit(q);
		// 水中光带缓慢迁移（局部、幅度 ≤ 2%）
		float water = smoothstep(310.0, 365.0, p.x) * (1.0 - smoothstep(555.0, 590.0, p.x)) * (1.0 - smoothstep(180.0, 266.0, p.y));
		float light = 0.012 * sin(p.x * 0.065 + p.y * 0.037 - phase) + 0.007 * sin(p.x * 0.12 + p.y * 0.046 - phase * 2.0);
		color += vec3(0.45, 0.78, 1.0) * light * water * (1.0 - 0.75 * mw);
		// 前景水草剪影
		for (int j = 0; j < 5; j++) {
			float id = float(j);
			float root_x = 550.0 + id * 13.0;
			float hgt = 28.0 + hash(id + 80.0) * 29.0;
			float h = (353.0 - p.y) / hgt;
			float sh = clamp(h, 0.0, 1.0);
			float cx = root_x - 6.0 * sh + 3.4 * sh * sh * sin(phase + id * 0.6);
			float w = mix(1.8, 0.45, sh);
			float stem = (1.0 - step(w, abs(p.x - cx))) * step(0.0, h) * (1.0 - step(1.0, h));
			float ly = fract(sh * 4.0);
			float lx = cx + sin(floor(sh * 4.0) * 2.3) * 5.0 * (1.0 - ly);
			float leaf = (1.0 - step(1.1, abs(p.x - lx))) * step(0.1, ly) * (1.0 - step(0.66, ly)) * step(0.12, h) * (1.0 - step(0.88, h));
			color = mix(color, vec3(0.021, 0.045, 0.057), max(stem, leaf));
		}
		// 远处小鱼群：单向穿行，循环边界前隐入水色
		float age = fract(tm / LOOP + 0.25);
		float sf = smoothstep(0.0, 0.18, age) * (1.0 - smoothstep(0.78, 1.0, age));
		for (int k = 0; k < 6; k++) {
			float id = float(k);
			vec2 fish = vec2(420.0 + id * 8.0 + 70.0 * age, 181.0 + mod(id, 3.0) * 4.0 + 1.7 * sin(phase * 2.0 + id));
			vec2 f = p - fish;
			float body = 1.0 - step(1.0, length(f / vec2(2.1, 0.8)));
			float tail = step(-4.0, f.x) * (1.0 - step(-1.9, f.x)) * (1.0 - step((-f.x - 1.8) * 0.55, abs(f.y)));
			color = mix(color, vec3(0.035, 0.085, 0.111), max(body, tail) * 0.65 * sf);
		}
		// 原像素气泡：固定种子，淡入淡出
		for (int i = 0; i < 20; i++) {
			float id = float(i);
			float ba = fract(tm / LOOP + hash(id + 4.0));
			vec2 b = vec2(346.0 + hash(id + 17.0) * 196.0, 188.0 + hash(id + 29.0) * 61.0 - ba * 96.0);
			b.x += 2.5 * sin(phase + id * 1.7);
			vec2 d = abs(floor(p) + 0.5 - (floor(b) + 0.5));
			float dot_px = 1.0 - step(0.6, max(d.x, d.y));
			float fade = smoothstep(0.0, 0.15, ba) * (1.0 - smoothstep(0.75, 1.0, ba));
			color = mix(color, vec3(0.43, 0.67, 0.77), dot_px * fade * 0.5);
		}
		COLOR = vec4(color, 1.0);
	}
}
