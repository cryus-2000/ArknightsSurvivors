shader_type canvas_item;
// 全屏后期：辉光（bloom）、水下滤镜（色差 + 暗角 + 焦散光斑）、亮度、受伤红边
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float bloom = 0.0;          // 0 关；0.4 左右为标准
uniform float bloom_threshold = 0.7;
uniform float filter_on = 0.0;      // 水下滤镜开关
uniform float aberration = 1.0;     // 色差强度（像素）
uniform float vignette = 0.14;
uniform float caustics = 0.07;
uniform float brightness = 1.0;
uniform float hurt = 0.0;           // 0..1 受伤红边
uniform float time = 0.0;

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
		b += textureLod(screen_tex, uv, 2.0).rgb * 0.35;
		b += textureLod(screen_tex, uv, 3.0).rgb * 0.35;
		b += textureLod(screen_tex, uv, 4.0).rgb * 0.30;
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
	col *= brightness;
	if (hurt > 0.001) {
		float edge = smoothstep(0.12, 0.5, r2);
		col = mix(col, vec3(0.9, 0.08, 0.12), edge * hurt * 0.75);
	}
	COLOR = vec4(col, 1.0);
}
