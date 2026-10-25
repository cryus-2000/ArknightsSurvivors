// 认知塑造背景（docs/109 §4，10-25 重做）：画在像素层 SubViewport 里，一个片元 = 一个像素格（2 设计单位）。
// style 0 深蓝之树：水下，上亮下暗；树冠一团光、几道光柱缓摆（40 秒一个来回）、远近两层海床剪影、四周压暗。
// style 1 原作夜海：夜空云带缓移、地平线一道光、海面横纹（越近地平线越密）+ 从地平线中心散开的透视细线。
// 颜色都按 Bayer 4×4 抖动量化成 40 档，和像素层的其他东西一个味道；still = 1（减少动态效果）时不动。
shader_type canvas_item;

uniform float style = 0.0;
uniform vec2 size = vec2(640.0, 360.0);    // 视口（像素格）
uniform vec2 cam = vec2(0.0);              // 视口左上角的世界坐标（像素格）
uniform vec2 world = vec2(640.0, 360.0);   // 世界尺寸（像素格）
uniform vec2 crown = vec2(278.0, 85.0);    // 树冠（像素格，世界坐标）
uniform float horizon = 0.3;               // 夜海：地平线在世界高度的比例
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

vec3 deep(vec2 w, float tm) {
	float d = w.y / world.y;
	vec3 c = mix(vec3(0.065, 0.19, 0.27), vec3(0.03, 0.095, 0.155), smoothstep(0.0, 0.5, d));
	c = mix(c, vec3(0.012, 0.035, 0.068), smoothstep(0.45, 1.05, d));
	// 树冠的光：一大团冷青，往下慢慢散
	float g = exp(-pow(distance(w, crown + vec2(0.0, 18.0)) / 120.0, 2.0));
	c += vec3(0.10, 0.30, 0.36) * g * 0.55;
	// 光柱：从树冠上方斜射下来，带缓慢摆动；越深越淡
	vec2 src = crown + vec2(-36.0, -300.0);
	vec2 dv = normalize(w - src);
	float ang = atan(dv.x, dv.y);
	float sway = 0.18 * sin(tm * 6.2831853 / 40.0);
	float sh = pow(max(0.0, sin(ang * 11.0 + sway + 1.2)), 7.0) * (1.0 - smoothstep(0.05, 0.8, d));
	c += vec3(0.16, 0.34, 0.40) * sh * 0.16;
	// 海床：远处一层淡、近处一层深
	float h2 = world.y - 70.0 - 46.0 * fbm(vec2(w.x * 0.011 + 7.0, 1.7));
	if (w.y > h2) {
		c = mix(c, vec3(0.025, 0.06, 0.095), 0.55);
	}
	float h1 = world.y - 18.0 - 22.0 * fbm(vec2(w.x * 0.02, 0.3)) - 8.0 * noise(vec2(w.x * 0.09, 3.0));
	if (w.y > h1) {
		c = vec3(0.008, 0.02, 0.038) + vec3(0.02, 0.05, 0.07) * step(w.y - h1, 1.5);
	}
	// 四周压暗
	vec2 q = (w - world * 0.5) / world;
	c *= 1.0 - 0.45 * smoothstep(0.35, 0.75, length(q * vec2(1.0, 1.25)));
	return c;
}

vec3 night(vec2 w, float tm) {
	float yh = world.y * horizon;
	vec3 c;
	if (w.y < yh) {
		float k = w.y / yh;
		c = mix(vec3(0.028, 0.04, 0.07), vec3(0.075, 0.10, 0.15), k * k);
		float cl = fbm(vec2(w.x * 0.008 + tm * 0.004, w.y * 0.03));
		float cl2 = fbm(vec2(w.x * 0.02 - tm * 0.002, w.y * 0.06 + 3.0));
		c += vec3(0.06, 0.07, 0.09) * smoothstep(0.42, 0.8, cl) * (0.45 + 0.55 * k) + vec3(0.03, 0.035, 0.045) * smoothstep(0.5, 0.75, cl2);
	} else {
		float z = w.y - yh;
		c = mix(vec3(0.05, 0.07, 0.10), vec3(0.016, 0.024, 0.04), smoothstep(0.0, world.y - yh, z));
		// 海面横纹：近地平线处又细又密
		float sx = w.x * 0.03 / (1.0 + z * 0.012);
		float sy = z * 0.32 / (1.0 + z * 0.004) - tm * 0.035;
		float n = noise(vec2(sx, sy)) * 0.7 + noise(vec2(sx * 2.7, sy * 2.1)) * 0.3;
		c += vec3(0.05, 0.065, 0.08) * smoothstep(0.74, 0.9, n) * (1.0 - smoothstep(0.0, world.y - yh, z) * 0.7);
		// 海面起伏的大块明暗（像原作那种云影落在海上）
		c += vec3(0.02, 0.026, 0.034) * (fbm(vec2(w.x * 0.006, z * 0.02 + tm * 0.003)) - 0.5);
		// 透视细线：从地平线中心散开，很淡
		vec2 v = w - vec2(crown.x, yh);
		float a = atan(v.x, v.y);
		c += vec3(0.04, 0.05, 0.06) * smoothstep(0.996, 1.0, cos(a * 16.0)) * smoothstep(4.0, 80.0, z) * 0.35;
	}
	// 地平线：一道亮线 + 上下一层薄光
	float hz = abs(w.y - yh);
	c += vec3(0.12, 0.15, 0.19) * exp(-hz / 5.0) * 0.6 + vec3(0.25, 0.3, 0.36) * step(hz, 0.5) * 0.35;
	vec2 q = (w - world * 0.5) / world;
	c *= 1.0 - 0.4 * smoothstep(0.4, 0.8, length(q * vec2(1.0, 1.3)));
	return c;
}

void fragment() {
	vec2 px = floor(UV * size);
	vec2 w = cam + px + 0.5;
	float tm = still > 0.5 ? 0.0 : time;
	vec3 c = style < 0.5 ? deep(w, tm) : night(w, tm);
	COLOR = vec4(quant(c, px), 1.0);
}
