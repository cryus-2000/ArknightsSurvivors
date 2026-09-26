shader_type canvas_item;
// 选卡 / 商人 / 事件界面背后的「灰阶压暗带」（方案 A，仿原作局内弹窗）：
// 读取已经画好的画面（战场 + HUD），去饱和、压暗；上下边缘在 fade_px 像素内渐隐，让顶栏和底栏保持清楚。
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float desat = 0.85;
uniform float dim = 0.5;
uniform float fade_px = 34.0;
uniform vec2 rect_size = vec2(1280.0, 520.0);

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(l), desat) * dim;
	float y = UV.y * rect_size.y;
	float e = fade_px <= 0.5 ? 1.0 : clamp(min(y, rect_size.y - y) / fade_px, 0.0, 1.0);
	COLOR = vec4(c, e);
}
