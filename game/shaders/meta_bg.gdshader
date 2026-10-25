// 认知塑造背景（docs/109 §4，10-25 海底星空版）：画在像素层 SubViewport 里，一个片元 = 一个像素格（2 设计单位）。
// 从海底往上看：上方是一层很淡的海面光（波纹缓移），往下渐深；满屏发光微粒像星星（三档亮度、各自慢慢闪），
// 一条斜贯的淡星云带（微粒更密）；四周压暗。颜色按 Bayer 4×4 抖动量化成 40 档，和像素层的其他东西一个味道；still = 1（减少动态效果）时不动。
shader_type canvas_item;

uniform vec2 size = vec2(640.0, 360.0);    // 视口（像素格）
uniform vec2 cam = vec2(0.0);              // 视口左上角的世界坐标（像素格）
uniform vec2 world = vec2(640.0, 360.0);   // 世界尺寸（像素格）
uniform vec2 crown = vec2(278.0, 85.0);    // 顶部中心（像素格，世界坐标）：海面光最亮处
uniform float time = 0.0;
uniform float still = 0.0;

const float BAYER[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

vec3 quant(vec3 c, vec2 px) {
	float th = (BAYER[int(mod(px.y, 4.0)) * 4 + int(mod(px.x, 4.0))] + 0.5) / 16.0;
	return floor(clamp(c, 0.0, 1.0) * 40.0 + th) / 40.0;
}

// 星云带：从左下斜到右上的一条宽带（0–1）
float band(vec2 w) {
	vec2 q = w / world;
	float d = (q.y - 0.95 + q.x * 0.75) / 0.2;
	return exp(-d * d) * (0.55 + 0.45 * fbm(w * 0.018));
}

// 一格里的星：每 6×6 格一颗候选，位置、亮度、闪烁相位都随格子散列
float stars(vec2 w, float tm, float dens) {
	vec2 cell = floor(w / 6.0);
	float h = hash(cell);
	if (h > dens) {
		return 0.0;
	}
	vec2 sp = cell * 6.0 + floor(vec2(hash(cell + 3.1), hash(cell + 7.7)) * 6.0);
	if (any(notEqual(floor(w), sp))) {
		return 0.0;
	}
	float b = hash(cell + 11.3);
	float tw = 0.6 + 0.4 * sin(tm * (0.6 + 1.6 * hash(cell + 5.2)) + h * 40.0);
	return (b > 0.9 ? 1.0 : (b > 0.6 ? 0.55 : 0.28)) * tw;
}

void fragment() {
	vec2 px = floor(UV * size);
	vec2 w = cam + px + 0.5;
	float tm = still > 0.5 ? 0.0 : time;
	float d = clamp(w.y / world.y, 0.0, 1.2);
	// 底色：上面稍亮的深青，往下沉到近黑的藏蓝
	vec3 c = mix(vec3(0.035, 0.085, 0.14), vec3(0.012, 0.025, 0.055), smoothstep(0.0, 0.85, d));
	// 海面光：顶部一层淡光，带缓慢的波纹（焦散）
	float sf = exp(-pow(distance(w, crown + vec2(0.0, -60.0)) / (world.x * 0.45), 2.0)) * (1.0 - smoothstep(0.0, 0.45, d));
	float ca = fbm(vec2(w.x * 0.03 + tm * 0.05, w.y * 0.06 - tm * 0.03));
	c += vec3(0.05, 0.14, 0.17) * sf * (0.6 + 0.8 * smoothstep(0.5, 0.75, ca));
	// 星云带
	float bd = band(w);
	c += vec3(0.03, 0.05, 0.09) * bd + vec3(0.03, 0.02, 0.06) * bd * fbm(w * 0.035 + 9.0);
	// 星（发光微粒）：星云带里更密
	float s = stars(w, tm, 0.22 + 0.45 * bd);
	c += vec3(0.62, 0.78, 0.95) * s;
	// 四周压暗
	vec2 q = (w - world * 0.5) / world;
	c *= 1.0 - 0.45 * smoothstep(0.35, 0.8, length(q * vec2(1.0, 1.25)));
	COLOR = vec4(quant(c, px), 1.0);
}
