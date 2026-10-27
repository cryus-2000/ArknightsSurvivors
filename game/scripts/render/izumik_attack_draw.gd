extends RefCounted
## 伊祖米克专属画面（docs/170）：只读攻击字典，不写模拟；颗粒 / 抖动只用确定性噪声。
## 迁徙潮预警：暗红低填充的水墙带 + 波峰材质勾边（像素点串成的浪尖），行进方向用稀疏泡沫点，不画斜线矩形与箭头框。
const DANGER := Color(0.82, 0.24, 0.43)
const DARK := Color(0.025, 0.045, 0.07)
const FOAM := Color(0.55, 0.72, 0.95)

static func _n(i: int, salt := 0) -> float:
	var k: int = (i * 73471 + salt * 19391 + 137) & 65535
	k = ((k ^ (k >> 7)) * 127) & 65535
	return float(k) / 65535.0

static func _dot(r, p: Vector2, c: Color, s := 2.0) -> void:
	var a := p.snapped(Vector2(2.0, 2.0))
	r.tb_quad(a, a + Vector2(s, 0), a + Vector2(s, s), a + Vector2(0, s), c)

static func tide_warning(g, w: Dictionary, alpha: float, progress: float) -> void:
	var r = g.world
	var p: Vector2 = w.pos
	var d := Vector2.from_angle(w.ang)
	var travel: Vector2 = w.velocity * float(w.life)
	var v: Vector2 = travel.normalized()
	var length: float = float(w.len)
	var wid: float = float(w.wid)
	var end: Vector2 = p + d * length
	# 水墙本体：低填充；前沿（朝行进方向一侧）是波峰，后沿只有暗边
	r.tb_quad(p - v * wid, end - v * wid, end + v * wid, p + v * wid, Color(0.24, 0.035, 0.085, 0.07 + progress * 0.06))
	var steps: int = clampi(int(length / 8.0), 4, 160)
	var phase: float = float(g.t) * 3.0
	for i in steps:
		var u: float = (float(i) + 0.5) / steps
		var at: Vector2 = p + d * length * u
		var crest: float = sin(u * length / 22.0 + phase) * 4.0
		_dot(r, at + v * (wid + crest) - Vector2(1, 1), Color(DARK.r, DARK.g, DARK.b, 0.8 * alpha), 4.0)
		_dot(r, at + v * (wid + crest), Color(DANGER.r, DANGER.g, DANGER.b, alpha))
		if i % 3 == 0:
			_dot(r, at - v * wid, Color(DANGER.r, DANGER.g, DANGER.b, alpha * 0.45))
	# 行进通道：稀疏泡沫点随预警推进，越到出手越密
	var lanes: int = int(lerpf(6.0, 18.0, progress))
	for j in lanes:
		var u: float = _n(j, 5)
		var s: float = fmod(_n(j, 9) + progress * 0.6, 1.0)
		_dot(r, p + d * length * u + travel * s, Color(FOAM.r, FOAM.g, FOAM.b, alpha * 0.35 * (1.0 - s)))

## 习得弹停住「学习」的 0.5 秒：每颗外面一圈收缩的细光点，告诉你它马上会转向
static func learn_marks(g, e: Dictionary) -> void:
	var r = g.world
	for b in g.ebullets:
		if b.life <= 0.0 or b.get("izu", "") != "learn" or int(b.get("source_id", -1)) != int(e.id):
			continue
		var t: float = float(b.izu_t)
		if t < 0.9 or t > 1.4:
			continue
		var k: float = (t - 0.9) / 0.5
		var rad: float = lerpf(22.0, float(b.r) + 3.0, k)
		for q in 6:
			var a: float = TAU * q / 6.0 + k * 1.5
			_dot(r, b.pos + Vector2(cos(a), sin(a)) * rad, Color(0.7, 0.85, 1.0, 0.85))

## 全场震撼 / 分享·全场：整场极低的暗红填充 + 从本体外扩的三圈浪纹点环（越到结算越密越亮），灯柱光圈由原灯柱绘制压在上面
static func field_warning(g, w: Dictionary) -> void:
	var r = g.world
	var e: Dictionary = w.owner
	var c: Vector2 = e.pos
	var gy: float = g.combat.GROUND_Y
	var k: float = clampf(float(w.t) / maxf(0.01, float(w.dur)), 0.0, 1.0)
	var reach := 900.0
	var fill := Color(0.3, 0.04, 0.1, 0.08 + 0.1 * k)
	for i in 40:
		var a: float = TAU * i / 40.0
		var b: float = TAU * (i + 1) / 40.0
		var va := Vector2(cos(a), sin(a) * gy)
		var vb := Vector2(cos(b), sin(b) * gy)
		r.tb_quad(c + va * 60.0, c + va * reach, c + vb * reach, c + vb * 60.0, fill)
	var crest := Color(1.0, 0.48, 0.57)
	for q in 3:
		var rad: float = fmod(float(w.t) * (140.0 + 120.0 * k) + q * reach / 3.0, reach)
		var fade: float = 1.0 - rad / reach
		var n: int = clampi(int(rad / 7.0), 16, 140)
		for i in n:
			if _n(i, q) < 0.3 - 0.25 * k: continue   # 断续浪纹，越到结算越连贯
			var a: float = TAU * float(i) / n
			var b: float = TAU * float(i + 1) / n
			var ra: float = rad + sin(a * 6.0 + float(w.t) * 4.0) * 6.0
			var rb: float = rad + sin(b * 6.0 + float(w.t) * 4.0) * 6.0
			var pa: Vector2 = c + Vector2(cos(a), sin(a) * gy) * ra
			var pb: Vector2 = c + Vector2(cos(b), sin(b) * gy) * rb
			_seg(r, pa, pb, 6.0, Color(DARK.r, DARK.g, DARK.b, 0.7 * fade))
			_seg(r, pa, pb, 3.0, Color(crest.r, crest.g, crest.b, (0.45 + 0.5 * k) * fade))

static func _seg(r, a: Vector2, b: Vector2, wd: float, c: Color) -> void:
	var n := (b - a).normalized().orthogonal() * wd * 0.5
	r.tb_quad((a - n).snapped(Vector2(2, 2)), (b - n).snapped(Vector2(2, 2)), (b + n).snapped(Vector2(2, 2)), (a + n).snapped(Vector2(2, 2)), c)
