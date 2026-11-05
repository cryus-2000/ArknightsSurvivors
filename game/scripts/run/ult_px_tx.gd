## 德克萨斯终结技转平面加强（docs/257 §9，ult_brief §9：以原版为底，配色对齐 + 最大那一下加强；开关 ult/px_plane_texas，缺省 0；总开关 ult/px_plane 也开）。
## 原版的刀网 / 闪身 / 斩线齐出 / 冲击帧 / 共用冲击慢放（ult.impact，回速 ult/imp_ease）/ 烟尘 / 地面残痕一律保留，只把颜色换成她普攻 / 技能定稿的琥珀（ult_moves 里 _txg 系列）。
## 本文件只在「斩线齐出」那一下（ult_moves._tx_step 的 cut，冲击帧那一发）叠加：
##   ① 中心一小团实心亮核 + 两道十字星芒，亮 2 拍（不平涂大圆）；
##   ② 一盏打满的照地灯（半径 240，docs/270 爆发档上限）+ 轻震 3px / 0.12 秒；
##   ③ 压扁的厚冲击环：0.5 R → R，3.5 拍推到判定边缘（先快后慢），白 → 琥珀三层，到边后 2 拍淡掉；
##   ④ 中心往外喷一团 160 颗的闪烁粒子云（琥珀 / 淡琥珀 / 白，少量冷青）；
##   ⑤ 怪物崩解：被斩开的怪在冲击环推到它那一拍，补一次引擎原有的击杀碎屑（kill_burst，按贴图像素碎开）+ 一圈怪物本色像素喷散。
## 全部只画：时间按 g.t（招式游戏时间），散布按坐标哈希，不抽随机数；玩法、判定、伤害、顿帧都不碰。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const D = preload("res://scripts/data.gd")   # 怪物代表色 ecol
const AMB: Array[Color] = [Color("#120804"), Color("#2c1406"), Color("#5a2808"), Color("#9c4610"), Color("#e2781c"), Color("#ffac3c"), Color("#ffdc9c"), Color("#ffffff")]
const ACC := Color("#9fe3ff")
const SQ := 0.72
const PREP := 0.0          # 冲击帧之后直接起爆（冲击帧本身就是预备：整屏白 + 黑剪影两拍，顿帧期间 g.t 不走）
const SHOCK_T := 3.5 / 15.0
const HIT_MAX := 120
const SPRAY_N := 22
const SPRAY_MAX := 80

var g
var st := {}
var _emit_n := 0
var _emit_frame := -1


static func on() -> bool:
	return Bal.v("ult/px_plane", 0.0) > 0.0 or Bal.v("ult/px_plane_texas", 0.0) > 0.0


static func of(game):
	if game.has_meta("ult_px_tx"):
		return game.get_meta("ult_px_tx")
	var r = new()
	r.g = game
	game.set_meta("ult_px_tx", r)
	return r


## 配色对齐（ult_moves 读）：开着时斩线 / 发丝线 / 身影线 / 拖影带换成她定稿的琥珀；关着原样
static func glow() -> Color:
	return AMB[4] if on() else Color(1.0, 0.55, 0.2)


static func core(orig: Color) -> Color:
	return AMB[6] if on() else orig


static func band2(orig: Color) -> Color:
	return AMB[5] if on() else orig


static func ev(u, kind: String, d: Dictionary) -> void:
	if not on():
		return
	of(u.g)._ev(u, kind, d)


func _ev(_u, kind: String, d: Dictionary) -> void:
	match kind:
		"cut":
			var hs: Array = []
			for e in d.get("es", []):
				if e is Dictionary and hs.size() < HIT_MAX:
					hs.append({"e": e, "p": e.pos, "done": false})
			st = {"c": d.c, "R": float(d.R), "t0": g.t, "hits": hs, "sprays": [], "lit": false}


func _live() -> bool:
	if st.is_empty():
		return false
	if g.t - float(st.t0) > 2.0:
		st = {}
		return false
	return true


static func _hf(x: int, y: int, k: int) -> float:
	return float(((x * 73856093) ^ (y * 19349663) ^ (k * 83492791)) & 0xFFFF) / 65535.0


func _glow(p: Vector2, c: Color) -> void:
	if not g.optical_on:
		return
	var fr: int = Engine.get_process_frames()
	if fr != _emit_frame:
		_emit_frame = fr
		_emit_n = 0
	if _emit_n >= 160:
		return
	_emit_n += 1
	g.glow_next.append([(p / 2.0).round() * 2.0, g.PX, Color(c.r, c.g, c.b, Bal.v("fx/px_plane_emit", 0.8))])


func _cell(w, p: Vector2, sz: float, c: Color) -> void:
	var q := (p / 2.0).floor() * 2.0
	w.tb_quad(q, q + Vector2(sz, 0), q + Vector2(sz, sz), q + Vector2(0, sz), c)


## 冲击环半径（世界像素）：0.5 R → R，先快后慢
func _shock_r(tau: float) -> float:
	var k: float = clampf(tau / SHOCK_T, 0.0, 1.0)
	return float(st.R) * (0.5 + 0.5 * (1.0 - (1.0 - k) * (1.0 - k)))


## 压扁椭圆环（外半径 ro、内半径 ri，按 2 像素行扫）：一圈实色，逐行两段
func _ell_ring(w, c: Vector2, ro: float, ri: float, col: Color) -> void:
	if ro <= ri or col.a <= 0.003:
		return
	var G := 2.0
	var ry: float = ro * SQ
	var y: float = floorf((c.y - ry) / G) * G
	while y < c.y + ry:
		var dy: float = (y + G * 0.5 - c.y) / SQ
		if absf(dy) < ro:
			var ho: float = sqrt(ro * ro - dy * dy)
			if absf(dy) < ri:
				var hi: float = sqrt(ri * ri - dy * dy)
				_span(w, y, c.x - ho, c.x - hi, col)
				_span(w, y, c.x + hi, c.x + ho, col)
			else:
				_span(w, y, c.x - ho, c.x + ho, col)
		y += G


func _span(w, y: float, x0: float, x1: float, col: Color) -> void:
	var a: float = floorf(x0 / 2.0) * 2.0
	var b: float = ceilf(x1 / 2.0) * 2.0
	if b - a < 1.0:
		return
	w.tb_quad(Vector2(a, y), Vector2(b, y), Vector2(b, y + 2.0), Vector2(a, y + 2.0), col)


func draw_front(_u, w) -> void:
	if not _live():
		return
	var age: float = g.t - float(st.t0)
	var tau: float = age - PREP
	var c: Vector2 = st.c
	if tau >= 0.0 and not st.lit:   # 起爆：满亮照地灯 + 轻震
		st.lit = true
		g.ult.light(c, 240.0, Color(1.0, 0.72, 0.4), 0.85)
		g.ult.shake(Bal.v("ult/tx_px_shake", 3.0), Bal.v("ult/tx_px_shake_t", 0.12))
	if tau < 0.0:
		return
	var bf: int = int(floor(tau * 15.0))
	# ① 亮核（2 拍）：中心小实心芯 + 十字星芒，不平涂大圆
	if bf <= 1:
		var rx: float = float(st.R) * (0.07 if bf == 0 else 0.05)
		_ell_ring(w, c + Vector2(0, -24), rx, 0.0, AMB[5] if bf == 0 else AMB[4])
		_ell_ring(w, c + Vector2(0, -24), rx * 0.62, 0.0, AMB[7] if bf == 0 else AMB[6])
		var arm: float = float(st.R) * (0.42 if bf == 0 else 0.3)
		var s: float = -arm
		while s <= arm:
			var k: float = 1.0 - absf(s) / arm
			var cc: Color = AMB[7] if k > 0.6 else (AMB[6] if k > 0.3 else AMB[5])
			_cell(w, c + Vector2(s, -24), 2.0, cc)
			if absf(s) < arm * 0.45:
				_cell(w, c + Vector2(0, -24 + s * SQ), 2.0, cc)
			if k > 0.5 and int(s) % 6 == 0:
				_glow(c + Vector2(s, -24), Color.WHITE)
			s += 2.0
	# ③ 冲击环（厚 16 世界像素，三层），到边后 2 拍淡掉
	if tau < SHOCK_T + 2.0 / 15.0:
		var rr: float = _shock_r(tau)
		var fade: float = 1.0 if tau < SHOCK_T else maxf(0.0, 1.0 - (tau - SHOCK_T) / (2.0 / 15.0))
		var hot: bool = tau < SHOCK_T
		_ell_ring(w, c, rr - 10.0, rr - 16.0, Color(AMB[4], fade))
		_ell_ring(w, c, rr - 4.0, rr - 10.0, Color(AMB[6] if hot else AMB[5], fade))
		_ell_ring(w, c, rr, rr - 4.0, Color(AMB[7] if hot else AMB[6], fade))
		if hot:   # 环后地面一闪（12–28 世界像素，淡）
			_ell_ring(w, c, rr - 18.0, rr - 34.0, Color(AMB[4], 0.28))
			for i in 24:
				var a: float = TAU * float(i) / 24.0
				_glow(c + Vector2(cos(a) * rr, sin(a) * rr * SQ), AMB[6])
	# ④ 中心往外喷的粒子云（160 颗、半径 0.6 R，1.2 秒散完）
	_cloud(w, c + Vector2(0, -24), tau, 777, float(st.R) * 0.6, 160)
	# ⑤ 崩解
	_shatter_tick(tau)
	_draw_sprays(w)


func _cloud(w, at: Vector2, a: float, sd: int, size: float, n: int) -> void:
	if a < 0.0 or a > 1.2:
		return
	var fr: int = int(a * 15.0)
	var u: float = minf(1.0, a / 0.35)
	var grow: float = 1.0 - (1.0 - u) * (1.0 - u)
	for k in n:
		if a > 0.25 and (fr + k) % 3 == 0:
			continue
		if _hf(k, sd, 84) < a / 1.2:
			continue
		var ang: float = TAU * _hf(k, sd, 81)
		var r: float = size * sqrt(_hf(k, sd, 82)) * grow + a * 8.0
		var p := at + Vector2(cos(ang) * r, sin(ang) * r * SQ - a * 20.0 * _hf(k, sd, 83))
		var hc: float = _hf(k, sd, 85)
		var col: Color = AMB[7] if hc < 0.3 else (AMB[6] if hc < 0.62 else (AMB[5] if hc < 0.9 else ACC))
		if a > 0.6:
			col = AMB[6] if col == AMB[7] else (AMB[5] if col == AMB[6] else (AMB[4] if col == AMB[5] else col))
		_cell(w, p, 4.0 if k % 3 == 0 else 2.0, col)
		if col == AMB[7] and a < 0.3:
			_glow(p, Color.WHITE)


func _shatter_tick(tau: float) -> void:
	if st.hits.is_empty():
		return
	var rr: float = _shock_r(tau)
	var c: Vector2 = st.c
	for h in st.hits:
		if h.done:
			continue
		var p: Vector2 = h.e.pos if not h.e.get("dead", false) else h.p
		var rel: Vector2 = p - c
		var dist: float = Vector2(rel.x, rel.y / SQ).length()
		if dist <= rr or tau >= SHOCK_T:
			h.done = true
			if g.optical_on and g.optical != null and g.optical.particles != null and not h.e.get("boss", false):
				g.optical.particles.kill_burst(h.e)
			var col: Color = D.ENEMIES.get(str(h.e.get("type", "")), {}).get("ecol", Color(0.6, 0.9, 0.9))
			var out: Vector2 = Vector2(rel.x, rel.y / SQ).normalized() if rel.length() > 1.0 else Vector2.RIGHT
			st.sprays.append({"p": p + Vector2(0, -10), "t0": g.t, "col": col, "out": out, "sd": int(h.e.get("id", 0)) * 13 + 5})
			if st.sprays.size() > SPRAY_MAX:
				st.sprays.pop_front()


func _draw_sprays(w) -> void:
	for sp in st.sprays:
		var age: float = g.t - float(sp.t0)
		if age > 1.3 or age < 0.0:
			continue
		var col: Color = sp.col
		var cols: Array = [col.lightened(0.45), col.lightened(0.15), col, col.darkened(0.3)]
		var sd: int = int(sp.sd)
		var base: Vector2 = sp.p
		for q in SPRAY_N:
			var ang: float = (sp.out as Vector2).angle() + (_hf(q, sd, 71) - 0.5) * 2.4
			var spd: float = 15.0 + 125.0 * pow(_hf(q, sd, 72), 1.5)
			var vh: float = 30.0 + 60.0 * _hf(q, sd, 73)
			var t_land: float = 2.0 * vh / 260.0
			var t: float = minf(age, 0.9)
			var tt: float = minf(t, t_land)
			var hgt: float = maxf(0.0, vh * tt - 130.0 * tt * tt) if t < t_land else 0.0
			var off := Vector2(cos(ang) * spd * tt, sin(ang) * spd * tt * SQ - hgt)
			var cc: Color = cols[q % 4]
			var hot: bool = age < 2.0 / 15.0 and q % 3 == 0
			if hot:
				cc = Color.WHITE
			cc.a = 1.0 if age < 0.9 else maxf(0.0, (1.3 - age) / 0.4)
			_cell(w, base + off, 4.0 if q % 3 != 2 else 2.0, cc)
			if hot:
				_glow(base + off, Color.WHITE)
