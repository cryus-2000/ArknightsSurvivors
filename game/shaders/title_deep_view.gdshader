// 标题页·深海水母：场景铺满屏幕后的屏幕空间压暗（docs/67 §13）——四周暗角 + 左侧菜单阅读衬底；
// 手机版式「集结出发」挪到右下，br > 0 时右下角再压一块，保证主按钮文字可读。
shader_type canvas_item;

uniform float br = 0.0;
uniform float fade = 0.0;   // 开场黑幕 0–1

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 s = SCREEN_UV;
	float vig = 0.27 * smoothstep(0.32, 0.78, length((s - 0.5) * vec2(1.0, 1.15)));
	float scrim = 0.59 * clamp((0.53 - s.x) / 0.53, 0.0, 1.0);
	float corner = br * 0.62 * (1.0 - smoothstep(0.0, 0.42, length((s - vec2(1.0, 1.0)) * vec2(1.0, 1.4))));
	float dark = max(max(vig, scrim), corner);
	vec3 col = mix(c.rgb, vec3(0.024, 0.055, 0.082), dark);
	col = mix(col, vec3(0.0, 0.005, 0.015), fade);
	COLOR = vec4(col, 1.0);
}
