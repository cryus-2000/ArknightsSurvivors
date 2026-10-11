// 图鉴 C4' 右侧终端面板的磨砂玻璃（10-11 用户定）：读背后已画好的画面（BackBufferCopy），一次 17 点模糊（中心 + 两圈各 8 点，
// 外圈旋转 22.5°），再按 tint.a 混上浅色底。只用 texture()（不依赖 mipmap / textureLod），Compatibility（桌面与网页）同一写法。
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform vec4 tint : source_color = vec4(0.886, 0.894, 0.906, 0.70);
uniform float radius = 8.0;   // 屏幕像素

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * radius;
	vec3 acc = texture(screen_tex, SCREEN_UV).rgb * 0.16;
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.785398;
		vec2 d = vec2(cos(a), sin(a));
		acc += texture(screen_tex, SCREEN_UV + d * px * 0.5).rgb * 0.06;
		vec2 d2 = vec2(cos(a + 0.392699), sin(a + 0.392699));
		acc += texture(screen_tex, SCREEN_UV + d2 * px).rgb * 0.045;
	}
	COLOR = vec4(mix(acc, tint.rgb, tint.a), 1.0);
}
