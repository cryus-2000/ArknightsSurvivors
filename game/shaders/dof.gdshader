shader_type canvas_item;
// 2.5D 景深：画面上下边缘轻微虚化（上方更远、更模糊），上方叠加远景水雾，四角压暗
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float band_top = 0.24;
uniform float band_bottom = 0.14;
uniform float strength = 1.6;
uniform vec3 fog_col = vec3(0.04, 0.10, 0.16);
uniform float fog_amt = 0.22;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 col = texture(screen_tex, uv).rgb;
	float dt = clamp((band_top - uv.y) / band_top, 0.0, 1.0);
	float db = clamp((uv.y - (1.0 - band_bottom)) / band_bottom, 0.0, 1.0) * 0.7;
	float d = max(dt, db);
	if (d > 0.001) {
		vec2 px = SCREEN_PIXEL_SIZE * d * strength * 1.5;
		vec3 acc = vec3(0.0);
		for (int x = -2; x <= 2; x++) {
			for (int y = -2; y <= 2; y++) {
				acc += texture(screen_tex, uv + vec2(float(x), float(y)) * px).rgb;
			}
		}
		col = mix(col, acc / 25.0, clamp(d * 1.3, 0.0, 0.85));
	}
	float fog = smoothstep(0.5, 0.0, uv.y) * fog_amt;
	col = mix(col, fog_col, fog);
	vec2 c = uv - 0.5;
	col *= 1.0 - dot(c, c) * 0.55;
	COLOR = vec4(col, 1.0);
}
