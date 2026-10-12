shader_type canvas_item;
// 白色保护（render/look_white_lift > 0 时挂在 game 节点上，scripts/render/look.gd）：
// 只有 RGB 为负的绘制（Look.op_mod 给干员本体打的标记）走这里的逐像素受光封顶，其余绘制原样（COLOR = 顶点色 × 贴图）。
// 中间调：屏幕倍率 M（ambient + 灯色 × 能量 × 衰减，× 亮度）的最大通道按 actor_knee / actor_cap 软膝封顶——和 Look.actor_mod 同一条曲线；
// 近白、低饱和的贴图像素：改按「像素亮度 × M」过高光软肩（white_sh 起弯，趋近 1.0），白色读得出白、又不硬截。
uniform sampler2D lamp_tex : filter_linear, repeat_disable;
uniform vec2 lamp_pos = vec2(0.0);
uniform float lamp_scale = 1.0;
uniform float lamp_energy = 1.0;
uniform float lamp_h = 90.0;
uniform vec3 lamp_col = vec3(1.0);
uniform vec3 amb = vec3(0.2);
uniform float br = 1.0;
uniform float knee = 0.9;
uniform float cap = 1.12;
uniform float white_lift = 1.0;
uniform float white_sh = 0.8;
uniform float white_gain = 1.0;
uniform float use_nm = 0.0;
uniform float lamp_on = 0.0;

varying float actor;
varying vec2 wpos;

void vertex() {
	actor = 0.0;
	if (COLOR.r < 0.0 || COLOR.g < 0.0 || COLOR.b < 0.0) {
		actor = 1.0;
		COLOR.rgb = abs(COLOR.rgb);
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float knee_scale(float mx) {
	if (cap <= 0.0 || mx <= knee) {
		return 1.0;
	}
	float room = max(cap - knee, 0.001);
	return (knee + room * (1.0 - exp(-(mx - knee) / room))) / mx;
}

void fragment() {
	if (actor > 0.5 && lamp_on > 0.5) {
		vec4 tx = texture(TEXTURE, UV);
		vec2 rel = wpos - lamp_pos;
		vec2 luv = vec2(0.5) + rel / (max(lamp_scale, 0.001) * 128.0);
		float a = 0.0;
		if (luv.x > 0.0 && luv.x < 1.0 && luv.y > 0.0 && luv.y < 1.0) {
			vec4 lt = texture(lamp_tex, luv);
			a = lt.a * lt.r * lamp_energy;
		}
		if (use_nm > 0.5) {
			float d = length(rel);
			a *= lamp_h / sqrt(d * d + lamp_h * lamp_h);
		}
		vec3 m = (amb + lamp_col * a) * br;
		float mm = max(m.r, max(m.g, m.b));
		float s = knee_scale(mm);
		vec3 alb = COLOR.rgb;
		// 近白：贴图像素最小通道 ≥ ~0.7、饱和度低（银发、白衣；肤色 / 金属彩色高光不算）
		float tmx = max(tx.r, max(tx.g, tx.b));
		float tmn = min(tx.r, min(tx.g, tx.b));
		float tsat = tmx > 0.001 ? (tmx - tmn) / tmx : 0.0;
		float wt = white_lift * smoothstep(0.62, 0.80, tmn) * (1.0 - smoothstep(0.10, 0.22, tsat));
		if (wt > 0.0) {
			float v = max(alb.r, max(alb.g, alb.b));
			float y = v * mm * white_gain;
			float sh = white_sh;
			float wy = y <= sh ? y : sh + (1.0 - sh) * (1.0 - exp(-(y - sh) / max(1.0 - sh, 0.001)));
			float sw = wy / max(v * mm, 0.0001);
			s = mix(s, max(s, sw), clamp(wt, 0.0, 1.0));
		}
		COLOR.rgb = alb * s;
	}
}
