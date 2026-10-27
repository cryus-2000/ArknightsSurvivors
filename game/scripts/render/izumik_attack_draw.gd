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

const DEEP := Color(0.04, 0.12, 0.26)
const SEA := Color(0.16, 0.36, 0.72)
const CREST := Color(0.55, 0.78, 1.0)
const LAMP := Color(1.0, 0.82, 0.45)

static func _ease(k: float) -> float:
	return 1.0 - pow(1.0 - clampf(k, 0.0, 1.0), 2.4)

## 震撼 / 分享·全场结算：从本体推开的一圈海浪（深色浪身 + 亮浪尖 + 断续泡沫），浪后留一层渐淡的水膜；点亮灯柱外沿亮一圈暖光
static func shock(g, f: Dictionary) -> void:
	var r = g.world
	var e = f.get("owner")
	var c: Vector2 = f.pos
	var gy: float = g.combat.GROUND_Y
	var k: float = 1.0 - float(f.life) / maxf(0.01, float(f.max))
	var rad: float = 50.0 + 950.0 * _ease(k)
	var fade: float = 1.0 - k * k
	var n: int = clampi(int(rad / 6.0), 24, 200)
	var body: float = 34.0 + 30.0 * (1.0 - k)
	for i in n:
		var a: float = TAU * float(i) / n
		var b: float = TAU * float(i + 1) / n
		var wa: float = sin(a * 9.0 + k * 20.0) * 7.0 + sin(a * 23.0) * 3.0
		var wb: float = sin(b * 9.0 + k * 20.0) * 7.0 + sin(b * 23.0) * 3.0
		var va := Vector2(cos(a), sin(a) * gy)
		var vb := Vector2(cos(b), sin(b) * gy)
		r.tb_quad(c + va * maxf(0.0, rad - body * 3.0), c + va * (rad - body), c + vb * (rad - body), c + vb * maxf(0.0, rad - body * 3.0), Color(SEA.r, SEA.g, SEA.b, 0.10 * fade))
		r.tb_quad(c + va * (rad - body), c + va * (rad + wa), c + vb * (rad + wb), c + vb * (rad - body), Color(DEEP.r, DEEP.g, DEEP.b, 0.55 * fade))
		r.tb_quad(c + va * (rad - body * 0.55), c + va * (rad + wa - 4.0), c + vb * (rad + wb - 4.0), c + vb * (rad - body * 0.55), Color(SEA.r, SEA.g, SEA.b, 0.6 * fade))
		_seg(r, c + va * (rad + wa) + Vector2(0, -6), c + vb * (rad + wb) + Vector2(0, -6), 4.0, Color(CREST.r, CREST.g, CREST.b, 0.9 * fade))
		if _n(i, 11) > 0.55:
			_dot(r, c + va * (rad + wa + 6.0 + 10.0 * _n(i, 12)) + Vector2(0, -10.0 * _n(i, 13)), Color(0.85, 0.95, 1.0, 0.85 * fade))
		if _n(i, 14) > 0.7:
			_dot(r, c + va * (rad - body * (0.6 + _n(i, 15))), Color(CREST.r, CREST.g, CREST.b, 0.5 * fade))
	if e is Dictionary:
		var lr: float = float(e.get("lamp_r", 120.0))
		for l in e.get("lamps", []):
			if not (l.get("lit", false) or l.get("out", false)): continue
			var d: float = g.combat.ground_d(l.pos, c)
			var near: float = 1.0 - clampf(absf(d - rad) / 160.0, 0.0, 1.0)
			if near <= 0.0: continue
			for q in 36:
				var a: float = TAU * q / 36.0
				var a2: float = a + TAU / 36.0
				_seg(r, l.pos + Vector2(cos(a), sin(a) * gy) * lr, l.pos + Vector2(cos(a2), sin(a2) * gy) * lr, 4.0, Color(LAMP.r, LAMP.g, LAMP.b, 0.85 * near))
				if _n(q, 21) > 0.6:
					_dot(r, l.pos + Vector2(cos(a), sin(a) * gy) * (lr + 4.0 + 10.0 * near) + Vector2(0, -6.0 * near), Color(1.0, 0.9, 0.6, near))

## 迁徙潮水墙：立起来的浪墙——地面浪身 + 向上卷起的浪面（高 20–34）+ 白色浪尖与脚下泡沫，沿墙长有起伏
static func tide_wall(g, w: Dictionary, alpha: float) -> void:
	var r = g.world
	var d := Vector2.from_angle(w.ang)
	var v: Vector2 = Vector2(w.get("velocity", d.orthogonal())).normalized()
	var length: float = float(w.len)
	var wid: float = float(w.wid)
	var age: float = float(w.get("age", 0.0))
	var steps: int = clampi(int(length / 8.0), 3, 140)
	for i in steps:
		var u0: float = float(i) / steps
		var u1: float = float(i + 1) / steps
		var a: Vector2 = w.pos + d * length * u0
		var b: Vector2 = w.pos + d * length * u1
		var ha: float = 26.0 + sin(u0 * length * 0.045 + age * 5.0) * 6.0 + sin(u0 * length * 0.13 - age * 7.0) * 3.0
		var hb: float = 26.0 + sin(u1 * length * 0.045 + age * 5.0) * 6.0 + sin(u1 * length * 0.13 - age * 7.0) * 3.0
		r.tb_quad(a - v * wid * 3.0, b - v * wid * 3.0, b - v * wid, a - v * wid, Color(SEA.r, SEA.g, SEA.b, 0.16 * alpha))
		r.tb_quad(a - v * wid, b - v * wid, b + v * wid, a + v * wid, Color(DEEP.r, DEEP.g, DEEP.b, 0.8 * alpha))
		var fa: Vector2 = a + v * wid
		var fb: Vector2 = b + v * wid
		r.tb_quad(fa, fb, fb + Vector2(0, -hb), fa + Vector2(0, -ha), Color(SEA.r, SEA.g, SEA.b, 0.82 * alpha))
		r.tb_quad(fa + Vector2(0, -ha * 0.55), fb + Vector2(0, -hb * 0.55), fb + Vector2(0, -hb), fa + Vector2(0, -ha), Color(0.3, 0.55, 0.9, 0.85 * alpha))
		_seg(r, fa + Vector2(0, -ha) + v * 4.0, fb + Vector2(0, -hb) + v * 4.0, 4.0, Color(CREST.r, CREST.g, CREST.b, 0.95 * alpha))
		if _n(i, 31) > 0.5:
			_dot(r, fa + Vector2(0, -ha - 4.0 - 6.0 * _n(i, 32)) + v * (6.0 + 6.0 * _n(i, 33)), Color(0.9, 0.97, 1.0, alpha))
		if _n(i, 34) > 0.45:
			_dot(r, fa + v * (3.0 + 8.0 * _n(i + int(age * 10.0), 35)), Color(0.85, 0.95, 1.0, 0.8 * alpha))

## 护群触腕预警：扇形里每个出土点先鼓起土包、裂纹慢慢张开，告诉你触手会从哪钻出来
static func tentacle_warning(g, w: Dictionary, progress: float) -> void:
	var r = g.world
	for p in _sprouts(w):
		var at: Vector2 = p[0]
		var s: float = clampf(progress * 1.4 - float(p[1]) * 0.4, 0.0, 1.0)
		if s <= 0.0: continue
		var rx: float = 6.0 + 6.0 * s
		for q in 6:
			var a: float = TAU * q / 6.0 + float(p[1]) * 3.0
			_seg(r, at, at + Vector2(cos(a), sin(a) * 0.5) * rx, 2.0, Color(0.05, 0.03, 0.05, 0.7 * s))
		r.tb_quad(at + Vector2(-8, 0), at + Vector2(0, -6.0 * s), at + Vector2(8, 0), at + Vector2(0, 3), Color(0.14, 0.12, 0.17, 0.9 * s))
		_dot(r, at + Vector2(-2, -4.0 * s), Color(0.3, 0.42, 0.6, 0.8 * s), 4.0)

## 护群触腕结算：从扇形内侧往外一根接一根钻出地面——先崩土，触手向上伸出摆动再缩回，土坑留到消失
static func tentacles(g, f: Dictionary) -> void:
	var r = g.world
	var k: float = 1.0 - float(f.life) / maxf(0.01, float(f.max))
	for p in _sprouts(f):
		var at: Vector2 = p[0]
		var u: float = p[1]
		var t: float = clampf((k - u * 0.35) / 0.65, 0.0, 1.0)
		if t <= 0.0: continue
		var rise: float = sin(t * PI)
		for q in 8:
			var a: float = TAU * q / 8.0 + u * 5.0
			var o := Vector2(cos(a), sin(a) * 0.45) * (8.0 + 10.0 * minf(1.0, t * 3.0))
			_dot(r, at + o + Vector2(0, -12.0 * sin(minf(1.0, t * 2.5) * PI) * _n(q, int(u * 97.0))), Color(0.12, 0.1, 0.14, 0.9 * (1.0 - t * 0.5)))
		r.tb_quad(at + Vector2(-9, -2), at + Vector2(9, -2), at + Vector2(9, 3), at + Vector2(-9, 3), Color(0.02, 0.02, 0.04, 0.7 * (1.0 - t * 0.6)))
		if rise <= 0.02: continue
		var height: float = (40.0 + 34.0 * float(p[2])) * rise
		var prev: Vector2 = at
		for j in 6:
			var h: float = float(j + 1) / 6.0
			var sway: float = sin(h * 3.0 + t * 9.0 + u * 7.0) * 9.0 * h
			var nxt: Vector2 = at + Vector2(sway, -height * h)
			var wd: float = lerpf(11.0, 3.0, h)
			_seg(r, prev, nxt, wd + 2.0, Color(0.02, 0.04, 0.08, 0.9))
			_seg(r, prev, nxt, wd, Color(0.22 + 0.25 * h, 0.4 + 0.3 * h, 0.7 + 0.25 * h, 0.95))
			prev = nxt
		_dot(r, prev + Vector2(-2, -3), Color(0.8, 0.92, 1.0, 0.95), 4.0)

## 出土点：沿扇形从内到外 9 个（确定性噪声），[位置, 内外次序 0..1, 粗细]
static func _sprouts(w: Dictionary) -> Array:
	var out: Array = []
	var p: Vector2 = w.pos
	var half: float = float(w.get("half", 0.5))
	for i in 9:
		var u: float = (float(i) + 0.5) / 9.0
		var a: float = float(w.ang) + (_n(i, 41) * 2.0 - 1.0) * half * 0.8
		var d: float = float(w.r) * (0.18 + 0.78 * u)
		out.append([p + Vector2(cos(a), sin(a) * 0.72) * d, u, _n(i, 43)])
	return out


## 海流牵引预警：半径 pull_r 内一圈圈向心旋流（水色短线顺流往中心挪），中心 r 的暗红低填充圈由通用 circle 预警给出
static func current_warning(g, w: Dictionary) -> void:
	var r = g.world
	var gy: float = g.combat.GROUND_Y
	var c: Vector2 = w.pos
	var pr: float = float(w.get("pull_r", 320.0))
	var t: float = float(w.get("t", 0.0))
	var k: float = clampf(t / maxf(0.01, float(w.dur)), 0.0, 1.0)
	for i in 54:
		var lane: float = _n(i, 51)
		var phase: float = fmod(lane + t * 0.45, 1.0)
		var rad: float = lerpf(pr, float(w.r) * 0.6, phase)
		var a: float = TAU * _n(i, 52) + phase * 2.2
		var p: Vector2 = c + Vector2(cos(a), sin(a) * gy) * rad
		var tang: Vector2 = Vector2(-sin(a), cos(a) * gy).normalized()
		var inward: Vector2 = (c - p).normalized()
		var dirv: Vector2 = (inward * 0.7 + tang * 0.5).normalized()
		var alpha: float = (0.35 + 0.45 * k) * sin(phase * PI)
		_seg(r, p, p + dirv * (10.0 + 8.0 * k), 3.0, Color(SEA.r, SEA.g, SEA.b, alpha))
		_seg(r, p + dirv * 4.0, p + dirv * (10.0 + 8.0 * k), 1.5, Color(CREST.r, CREST.g, CREST.b, alpha))
	for q in 48:
		var a0: float = TAU * q / 48.0 + t * 0.6
		var a1: float = a0 + TAU / 96.0
		_seg(r, c + Vector2(cos(a0), sin(a0) * gy) * pr, c + Vector2(cos(a1), sin(a1) * gy) * pr, 2.0, Color(SEA.r, SEA.g, SEA.b, 0.35 + 0.3 * k))

## 海流牵引结算：中心水柱涌起后塌落（深色水身 + 浪尖 + 四散泡沫）
static func current_burst(g, f: Dictionary) -> void:
	if not f.has("max"):
		return
	var r = g.world
	var c: Vector2 = f.pos
	var k: float = 1.0 - float(f.life) / maxf(0.01, float(f.max))
	var h: float = 70.0 * sin(minf(1.0, k * 1.6) * PI * 0.5) * (1.0 - k * 0.7)
	var wid: float = float(f.r) * (0.6 + 0.4 * k)
	r.tb_quad(c + Vector2(-wid, 0), c + Vector2(wid, 0), c + Vector2(wid * 0.4, -h), c + Vector2(-wid * 0.4, -h), Color(DEEP.r, DEEP.g, DEEP.b, 0.75 * (1.0 - k)))
	r.tb_quad(c + Vector2(-wid * 0.6, -h * 0.3), c + Vector2(wid * 0.6, -h * 0.3), c + Vector2(wid * 0.3, -h), c + Vector2(-wid * 0.3, -h), Color(SEA.r, SEA.g, SEA.b, 0.8 * (1.0 - k)))
	_seg(r, c + Vector2(-wid * 0.3, -h), c + Vector2(wid * 0.3, -h), 4.0, Color(CREST.r, CREST.g, CREST.b, 0.9 * (1.0 - k)))
	for i in 18:
		var a: float = TAU * _n(i, 61)
		var d: float = (20.0 + 60.0 * _n(i, 62)) * k
		_dot(r, c + Vector2(cos(a) * d, sin(a) * d * 0.6 - h * (1.0 - k) * _n(i, 63)), Color(0.85, 0.95, 1.0, 0.85 * (1.0 - k)))


## 分享结算：从本体向扇形喷出 16 道水流（头部亮、尾部拖水滴），随后孢子雾在扇里散开淡出，扇缘一道浪沫弧
static func share(g, f: Dictionary) -> void:
	var r = g.world
	var c: Vector2 = f.pos
	var k: float = 1.0 - float(f.life) / maxf(0.01, float(f.max))
	var half: float = float(f.half)
	var reach: float = float(f.r)
	var fade: float = 1.0 - k
	for i in 16:
		var a: float = float(f.ang) + lerpf(-half, half, (float(i) + 0.5) / 16.0) + (_n(i, 71) - 0.5) * half / 12.0
		var d := Vector2.from_angle(a)
		var head: float = reach * minf(1.0, k / 0.45) * (0.8 + 0.2 * _n(i, 72))
		var tail: float = maxf(0.0, head - 70.0 - 40.0 * _n(i, 73))
		_seg(r, c + d * tail, c + d * head, 6.0, Color(DEEP.r, DEEP.g, DEEP.b, 0.6 * fade))
		_seg(r, c + d * tail, c + d * head, 3.0, Color(SEA.r, SEA.g, SEA.b, 0.85 * fade))
		_dot(r, c + d * head, Color(CREST.r, CREST.g, CREST.b, fade), 4.0)
		for j in 3:
			var u: float = tail + (head - tail) * _n(i * 3 + j, 74)
			_dot(r, c + d * u + d.orthogonal() * (_n(i * 3 + j, 75) - 0.5) * 10.0, Color(0.85, 0.95, 1.0, 0.7 * fade))
	if k > 0.25:
		var m: float = (k - 0.25) / 0.75
		for i in 40:
			var a: float = float(f.ang) + (_n(i, 76) * 2.0 - 1.0) * half
			var dd: float = reach * (0.3 + 0.7 * _n(i, 77)) + 20.0 * m
			_dot(r, c + Vector2.from_angle(a) * dd + Vector2(0, -14.0 * m * _n(i, 78)), Color(0.55, 0.75, 1.0, 0.55 * (1.0 - m)))
	var steps := 24
	for i in steps:
		var a0: float = float(f.ang) - half + 2.0 * half * i / steps
		var a1: float = float(f.ang) - half + 2.0 * half * (i + 1) / steps
		var rr: float = reach * minf(1.0, k / 0.45)
		_seg(r, c + Vector2.from_angle(a0) * rr, c + Vector2.from_angle(a1) * rr, 3.0, Color(CREST.r, CREST.g, CREST.b, 0.6 * fade))
