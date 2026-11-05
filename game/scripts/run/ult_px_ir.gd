## 艾丽妮终结技「宣判」转平面画面（docs/275，开关 ult/px_plane，缺省 0 = 原画面）：只改画面，招式时间轴 / 判定 / 伤害 / 冲击帧逻辑全照 ult_moves_c._irv_*。
## 纹章用用户 10-31 认可的图案，重采样到美术像素格并压扁、只留线稿、改白色阶（11-05 用户：纹章用白、紫留给斩击；tools/ult_px_irene_bake.py → art/fx/pxp/pxp_ult_ir_seal.png）。
## 1 特效像素 = 1 美术像素（g.PX = 2 世界像素），15 fps 节拍（帧号按全局拍子），贴地层压扁 0.72；白 + 亮紫为主，深海蓝潮水作辅色（docs/272 §1）。
## 画法与 tools/ult_px_irene_art.py 一一对应（windup / seal_mod / chain / blade / thread / splash / boom / final_blade / crack / dust_wall / grain），改一边要改另一边。
## 事件由 ult_moves_c 的 _irv_* 在原来画图的位置发（IRP.ev），不抽随机数（散布按坐标哈希）；冲击帧剪影（收尾斩击 + 主裂缝）由 ult._draw_hit_frame 调 draw_hf 画。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")

const LT := [Color("#1a0c28"), Color("#3a1a58"), Color("#6a32a0"), Color("#9d58e0"), Color("#cf98ff"), Color("#f0e2ff"), Color("#ffffff")]
const TIDE := [Color("#050b1a"), Color("#0b1a38"), Color("#143062"), Color("#21508c"), Color("#3f80bc"), Color("#90c4ea"), Color("#e6f6ff")]
const COOL := [Color("#16121c"), Color("#2a2430"), Color("#423a4a")]
const DUST := [Color("#2a2a30"), Color("#3e3c44"), Color("#56545c"), Color("#6e6c74")]
const NAVY := Color("#0c1430")
const VIOLET_L := Color(0.8, 0.6, 1.0)
const SQ := 0.72
const EMIT_CAP := 240

var g
var st := {}          # 这一次终结技：{c, R(美术像素), t0 盖章, fade_t0, fin_t0, dv, pins:[{e, rim, t0, tb}], dashes:[{a, b, t0}], booms:[{p, t0, big, sd}]}
var _emit_n := 0
var _emit_frame := -1


static func on() -> bool:
	return Bal.v("ult/px_plane", 0.0) > 0.0


static func of(game):
	if game.has_meta("ult_px_ir"):
		return game.get_meta("ult_px_ir")
	var r = new()
	r.g = game
	game.set_meta("ult_px_ir", r)
	return r


static func _hsh(x: int, y: int, k: int) -> int:
	return ((x * 73856093) ^ (y * 19349663) ^ (k * 83492791)) & 0xFFFF


static func _hf(x: int, y: int, k: int) -> float:
	return float(_hsh(x, y, k)) / 65535.0


func _fr(t0: float) -> int:
	return int(floor(g.t * 15.0)) - int(floor(t0 * 15.0))


# ================================================================ 事件（ult_moves_c._irv_* 发；只记画面）

static func ev(u, kind: String, d: Dictionary) -> void:
	if not on():
		return
	of(u.g)._ev(u, kind, d)


func _ev(u, kind: String, d: Dictionary) -> void:
	match kind:
		"start":   # 盖章前：记纹章中心与半径（世界）
			st = {"c": d.c, "R": float(d.R) * 0.5, "t0": g.t + 0.1, "fade_t0": -1.0, "fin_t0": -1.0, "dv": Vector2.RIGHT, "pins": [], "dashes": [], "booms": []}
			u.light(d.c, float(d.R) * 0.5, VIOLET_L, 2.0)   # 同原画面只留一盏 2 秒慢慢暗下去的光（用户 10-31 嫌短灯闪），改亮紫
		"pin":   # 光链：起点落在压扁的纹章椭圆边上
			if st.is_empty() or st.pins.size() >= 18:
				return
			var e: Dictionary = d.e
			var c: Vector2 = st.c
			var ta: float = atan2((e.pos.y - c.y) / SQ, e.pos.x - c.x)
			var Rw: float = float(st.R) * 2.0
			st.pins.append({"e": e, "rim": c + Vector2(cos(ta) * Rw * 0.97, sin(ta) * Rw * 0.97 * SQ), "t0": g.t + float(d.get("delay", 0.0)), "tb": -1.0, "last": e.pos})
		"dash":
			if not st.is_empty():
				st.dashes.append({"a": d.a, "b": d.b, "t0": g.t})
				if st.dashes.size() > 10:
					st.dashes.pop_front()
		"boom":   # 连环爆：链断 + 星爆
			if st.is_empty():
				return
			var e2: Dictionary = d.e
			for pn in st.pins:
				if is_same(pn.e, e2):
					pn.tb = g.t
					pn.last = d.p
			st.booms.append({"p": d.p, "t0": g.t, "big": d.get("big", false), "sd": int(e2.get("id", 0))})
			if st.booms.size() > 40:
				st.booms.pop_front()
		"final":   # 收尾斩击：斩线 + 主 / 副裂缝 + 沿线 7 爆 + 14 块碎石 + 尘墙
			if st.is_empty():
				return
			st.fin_t0 = g.t
			st.dv = d.dv
			st.fade_t0 = g.t
		"end":
			pass


# ================================================================ 绘制

func _live() -> bool:
	if st.is_empty():
		return false
	var last: float = maxf(float(st.t0), float(st.fade_t0))
	if g.t - last > 2.2 and float(st.fade_t0) >= 0.0:
		st = {}
		return false
	if float(st.fade_t0) < 0.0 and g.t - float(st.t0) > 6.0:   # 兜底：招式被打断没收尾
		st = {}
		return false
	return true


func _glow(p: Vector2, c: Color) -> void:
	if not g.optical_on:
		return
	var fr: int = Engine.get_process_frames()
	if fr != _emit_frame:
		_emit_frame = fr
		_emit_n = 0
	if _emit_n >= EMIT_CAP:
		return
	_emit_n += 1
	g.glow_next.append([p, g.PX, Color(c.r, c.g, c.b, Bal.v("fx/px_plane_emit", 0.8))])


## 一组美术像素点（[x, y, 颜色, 发光 bool / 不透明度 float]），原点 o0 对齐 2 像素格；sz = 每点边长（美术像素）
func _pts(w, o0: Vector2, lst: Array, fg = null) -> void:
	var px: float = g.PX
	var base: Vector2 = (o0 / 2.0).round() * 2.0
	for q in lst:
		var p: Vector2 = base + Vector2(roundf(float(q[0])), roundf(float(q[1]))) * px
		var c: Color = q[2]
		var v = q[3]
		var sz: float = px * (float(q[4]) if q.size() > 4 else 1.0)
		if fg != null:
			c = fg
		elif not (v is bool):
			c = Color(c.r, c.g, c.b, float(v))
		w.tb_quad(p, p + Vector2(sz, 0), p + Vector2(sz, sz), p + Vector2(0, sz), c)
		if fg == null and v is bool and v:
			_glow(p, c)


## 地面层（ult.draw_world_back）：纹章、裂缝
func draw_back(_u, w) -> void:
	if not _live():
		return
	var c: Vector2 = st.c
	var R: float = st.R
	if g.t >= float(st.t0):   # 纹章（烤好的线稿，只按 g.PX 整数放大，中心对齐 2 像素格）
		var fade = null if float(st.fade_t0) < 0.0 else g.t - float(st.fade_t0)
		var md: Color = _seal_mod(g.t - float(st.t0), fade)
		var tx: Texture2D = _seal_tex()
		if md.a > 0.0 and tx != null:
			w.tb_flush()
			var sz: Vector2 = Vector2(tx.get_width(), tx.get_height()) * g.PX
			g.draw_texture_rect(tx, Rect2(((c - sz * 0.5) / 2.0).round() * 2.0, sz), false, md)
	if float(st.fin_t0) >= 0.0:
		var age: float = g.t - float(st.fin_t0)
		var dv: Vector2 = st.dv
		var ang: float = dv.angle()
		_pts(w, c, _crack(R, ang, age, 3, 2.0))
		_pts(w, c, _crack(R, ang + PI, age, 4, 2.0))
		for k in 2:
			var side: float = -1.0 if k == 0 else 1.0
			_pts(w, c + dv * R * 2.0 * 0.25 * side, _crack(R * 0.7, ang + (PI if side < 0.0 else 0.0) + side * 0.12, age - 0.04, 9 + k, 1.8))
	w.tb_flush()


## 上层（ult.draw_world，招式图形之后、冲击帧之前）：光链、穿梭斩线 / 细线 / 落点水花、连环爆 + 颗粒、收尾斩击 + 沿线爆 / 尘墙 / 碎石
func draw_front(_u, w) -> void:
	if not _live():
		return
	var c: Vector2 = st.c
	var R: float = st.R
	var px: float = g.PX
	for pn in st.pins:
		if g.t < float(pn.t0):
			continue
		var e: Dictionary = pn.e
		var ep: Vector2 = pn.last if e.get("dead", false) else e.pos
		var rim: Vector2 = pn.rim
		var tgt: Vector2 = (ep + Vector2(0, -10) - rim) / px
		var br = null if float(pn.tb) < 0.0 else g.t - float(pn.tb)
		_pts(w, rim, _chain(tgt, (g.t - float(pn.t0)) / 0.12, br))
	for d in st.dashes:
		var f: int = _fr(float(d.t0))
		if f > 5:
			continue
		var a0: Vector2 = d.a
		var b0: Vector2 = d.b
		var dv: Vector2 = (b0 - a0).normalized() if b0 != a0 else Vector2.RIGHT
		var sa: Vector2 = a0 - dv * 30.0 + Vector2(0, -20)
		var sb: Vector2 = b0 + dv * 40.0 + Vector2(0, -20)
		_pts(w, sa, _blade((sb - sa) / px, f, 4.0, 1))
		_pts(w, a0 + Vector2(0, -20), _thread((b0 - a0) / px, g.t - float(d.t0), 0.4))
		_pts(w, b0, _splash(dv, f))
	for b in st.booms:
		var age: float = g.t - float(b.t0)
		var f2: int = _fr(float(b.t0))
		if f2 > 6 and age > 1.4:
			continue
		var bp: Vector2 = b.p
		_pts(w, bp, _boom(f2, b.big))
		for q in 3:
			var gr: Array = _grain(age, int(b.sd) * 7 + q, "shard" if q < 2 else "drop")
			if not gr.is_empty():
				_pts(w, bp + Vector2(0, -8), [[gr[0], gr[1], gr[2], 1.0, gr[3]]])
	if float(st.fin_t0) >= 0.0:
		var fa: float = g.t - float(st.fin_t0)
		var dv2: Vector2 = st.dv
		var nv := Vector2(-dv2.y, dv2.x)
		var Rw: float = R * 2.0
		_pts(w, c, _final_blade(R, dv2, fa, false))
		_pts(w, c, _boom(int(floor(fa * 15.0)), true, 2.4))   # 斩点中心一记大爆亮
		for i in 7:
			var x: float = (float(i) - 3.0) / 3.0
			var bp2: Vector2 = c + dv2 * Rw * x * 0.95 + nv * (_hf(i, 1, 2) - 0.5) * 30.0
			var dl: float = 0.08 + 0.04 * absf(x) * 3.0
			_pts(w, bp2, _boom(int(floor((fa - dl) * 15.0)), true, 2.4))
			for side in [-1.0, 1.0]:
				_pts(w, bp2, _dust_wall(nv * side, fa - dl - 0.03, i * 2 + (1 if side > 0.0 else 0)))
		for q in 24:
			var x2: float = (float(q) - 11.5) / 11.5
			var gp: Vector2 = c + dv2 * Rw * x2 * 1.05
			var gr2: Array = _grain(fa - 0.03 * absf(x2) * 4.0, 100 + q, "rock")
			if not gr2.is_empty():
				_pts(w, gp, [[gr2[0], gr2[1], gr2[2], 1.0, gr2[3]]])
	w.tb_flush()


## 冲击帧剪影（ult._draw_hit_frame 在整屏底色之后调）：收尾斩击主刃 + 两条主裂缝，颜色 fg
func draw_hf(_u, w, fg: Color) -> void:
	if not _live() or float(st.fin_t0) < 0.0:
		return
	var c: Vector2 = st.c
	var R: float = st.R
	var dv: Vector2 = st.dv
	_pts(w, c, _final_blade(R, dv, 0.0, true), fg)
	_pts(w, c, _crack(R, dv.angle(), 0.05, 3, 2.0), fg)
	_pts(w, c, _crack(R, dv.angle() + PI, 0.05, 4, 2.0), fg)
	w.tb_flush()


## 起手慢放（ult._draw_windup 对艾丽妮转来）：光点螺旋收进举起的提灯 + 脚下细光圈收紧
func draw_windup(_u, w, caster, wk: float) -> void:
	_pts(w, caster.pos, _windup(wk, int(floor(g.t * 15.0))))
	w.tb_flush()


# ================================================================ 画法（同 tools/ult_px_irene_art.py）

static func _star(out: Array, x: float, y: float, arm: int, c0: Color, c1: Color, c2: Color) -> void:
	out.append([x, y, c0, true])
	for i in range(1, arm + 1):
		var c: Color = c1 if i < arm else c2
		out.append([x + i, y, c, false])
		out.append([x - i, y, c, false])
		out.append([x, y + i, c, false])
		out.append([x, y - i, c, false])


func _windup(wk: float, bt: int) -> Array:
	var out: Array = []
	var lx := 10.0
	var ly := -28.0
	for i in 16:
		var h1: float = _hf(i, 3, 1)
		var h2: float = _hf(i, 5, 2)
		var k: float = clampf(wk * (1.2 + 0.6 * h2) - 0.25 * h1, 0.0, 1.0)
		if k <= 0.0 or k >= 1.0:
			continue
		var a: float = TAU * (i + h1) / 16.0 + k * 2.2
		var d: float = (36.0 + 40.0 * h2) * pow(1.0 - k, 1.6) + 2.0
		var x: float = lx + cos(a) * d
		var y: float = ly + sin(a) * d * 0.8
		out.append([x, y, LT[6] if k > 0.7 else (LT[5] if k > 0.4 else LT[4]), k > 0.7])
		if k < 0.6:
			out.append([x - cos(a + 0.6) * 2.0, y - sin(a + 0.6) * 1.6, LT[3], false])
	var r: float = 36.0 - 25.0 * (1.0 - pow(1.0 - wk, 2.0))
	var n: int = int(r * 6.6) + 8
	for q in n:
		var t: float = float(q) / float(n) * TAU
		if (q + bt) % 5 == 4:
			continue
		out.append([roundf(r * cos(t)), roundf(r * sin(t) * SQ * 0.55), LT[5] if wk > 0.6 else LT[4], 0.5 + 0.5 * wk])
	if wk > 0.5:
		_star(out, lx, ly + 3.0, 1 + int(wk * 2.5), LT[6], LT[5], LT[4])
	return out


## 同 seal_mod()：盖章头两拍提亮，之后 0.42 常亮；收尾 1.4 秒冷却淡掉（a = 0 不画）
func _seal_mod(age: float, fade) -> Color:
	if age < 0.0:
		return Color(1, 1, 1, 0)
	if fade != null:
		var u: float = minf(1.0, float(fade) / 1.4)
		if u >= 1.0:
			return Color(1, 1, 1, 0)
		var k: float = 1.0 - 0.45 * u
		return Color(k * 0.9, k * 0.85, k, 0.42 * (1.0 - u))
	if age < 2.0 / 15.0:
		return Color(1.35, 1.3, 1.35, 0.95)
	if age < 4.0 / 15.0:
		return Color(1.15, 1.1, 1.15, 0.75)
	return Color(1, 1, 1, 0.42)


var _stx = null


func _seal_tex() -> Texture2D:
	if _stx == null:
		var p: String = "res://art/fx/pxp/pxp_ult_ir_seal.png"
		_stx = load(p) if ResourceLoader.exists(p) else false
	return _stx if _stx is Texture2D else null


func _chain(tgt: Vector2, grow: float, broken) -> Array:
	var out: Array = []
	var L: float = maxf(1.0, tgt.length())
	var d: Vector2 = tgt / L
	var nv := Vector2(-d.y, d.x)
	var n: int = int(L)
	if broken == null:
		var m: int = int(n * minf(1.0, grow))
		for i in m:
			var ph: int = i % 3
			if ph == 2:
				continue
			out.append([d.x * i, d.y * i, LT[6] if ph == 0 else LT[4], ph == 0 and i % 6 == 0])
			out.append([d.x * i + nv.x, d.y * i + nv.y, LT[5] if ph == 0 else LT[3], false])
		if grow >= 1.0:
			_star(out, tgt.x, tgt.y, 2, LT[6], LT[5], LT[4])
		return out
	var bk: float = float(broken)
	if bk > 0.3:
		return out
	var u: float = bk / 0.3
	for i in range(0, n, 3):
		var side: float = 1.0 if _hsh(i, 7, 5) % 2 == 1 else -1.0
		var sp: float = 2.0 + 6.0 * _hf(i, 7, 6)
		out.append([d.x * i + nv.x * side * sp * u, d.y * i + nv.y * side * sp * u + 14.0 * u * u * (0.5 + _hf(i, 7, 7)),
			LT[5] if u < 0.4 else (LT[3] if u < 0.75 else LT[2]), false])
	return out


func _blade(b: Vector2, f: int, w: float, hot_frames: int) -> Array:
	var L: float = maxf(1.0, b.length())
	var d: Vector2 = b / L
	var nv := Vector2(-d.y, d.x)
	if f < 0 or f > hot_frames + 3:
		return []
	var cells := {}
	if f <= hot_frames:
		var n: int = int(L * 2.0)
		for i in n + 1:
			var u: float = float(i) / float(n)
			var hw: float = w * pow(sin(PI * u), 0.6)
			var m: int = int(ceil(hw * 2.0))
			for j in range(-m, m + 1):
				var ww: float = j / 2.0
				if absf(ww) > hw + 0.25:
					continue
				var k: float = absf(ww) / maxf(0.6, hw)
				var c: Color = LT[3]
				var gl := false
				if k < 0.34 or hw < 0.9:
					c = LT[6]
					gl = true
				elif k < 0.62:
					c = LT[5]
				elif k < 0.86:
					c = LT[4]
				cells[Vector2i(roundi(d.x * L * u + nv.x * ww), roundi(d.y * L * u + nv.y * ww))] = [c, gl]
	else:
		var g2: int = f - hot_frames
		var lo: float = [0.0, 0.0, 0.4, 0.75][g2]
		for i in int(L) + 1:
			var u2: float = float(i) / L
			if u2 < lo or (g2 == 3 and i % 2 == 1):
				continue
			cells[Vector2i(roundi(d.x * i), roundi(d.y * i))] = [LT[6] if g2 == 1 else (LT[5] if g2 == 2 else LT[4]), g2 == 1]
	var out: Array = []
	for kk in cells:
		out.append([float(kk.x), float(kk.y), cells[kk][0], cells[kk][1]])
	return out


func _thread(b: Vector2, age: float, life: float) -> Array:
	var out: Array = []
	if age < 0.0 or age > life:
		return out
	var L: float = maxf(1.0, b.length())
	var u0: float = age / life
	for i in int(L) + 1:
		var u: float = float(i) / L
		if absf(u - 0.5) > 0.5 * (1.0 - u0) or i % 3 == 2:
			continue
		out.append([b.x * u, b.y * u, LT[4] if u0 < 0.5 else LT[3], 0.9 * (1.0 - u0 * 0.5)])
	return out


func _splash(dv: Vector2, f: int) -> Array:
	var out: Array = []
	if f < 0 or f > 3:
		return out
	for q in 5:
		var a: float = atan2(-dv.y, -dv.x) + (q - 2) * 0.5
		var rr: float = 3.0 + f * 2.5 + q % 2
		out.append([cos(a) * rr, sin(a) * rr * SQ - (6.0 - pow(f - 1.5, 2.0) * 2.2) - q % 2, TIDE[6] if f <= 1 else (TIDE[5] if f == 2 else TIDE[4]), false])
	if f <= 2:
		for q2 in range(-2, 3):
			out.append([float(q2), 0.0, TIDE[6] if f == 0 else TIDE[5], false])
	return out


func _boom(f: int, big: bool, sc := -1.0) -> Array:
	var out: Array = []
	var cy := -8.0
	var s: float = sc if sc > 0.0 else (1.4 if big else 1.0)
	if f < 0 or f > 6:
		return out
	if f == 0:
		var r: int = int(3 * s)
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if absi(dx) + absi(dy) <= r:
					out.append([float(dx), cy + dy, LT[6] if absi(dx) + absi(dy) <= r - 1 else LT[5], true])
	if f >= 1 and f <= 2:
		var L1: int = int((10 if f == 1 else 7) * s)
		var L2: int = int((5 if f == 1 else 3) * s)
		for arm in [[1, 0, L1], [-1, 0, L1], [0, 1, L1 * 0.6], [0, -1, L1], [1, 1, L2], [-1, 1, L2], [1, -1, L2], [-1, -1, L2]]:
			var La: int = int(arm[2])
			for i in La + 1:
				var u: float = float(i) / float(maxi(1, La))
				out.append([float(arm[0]) * i, cy + float(arm[1]) * i, LT[6] if u < 0.35 else (LT[5] if u < 0.7 else LT[4]), u < 0.35])
		for dx2 in range(-2, 3):
			for dy2 in range(-2, 3):
				if absi(dx2) + absi(dy2) <= 2:
					out.append([float(dx2), cy + dy2, LT[6], true])
	if f >= 2 and f <= 5:
		for q in 10:
			var a: float = q / 10.0 * TAU + _hf(q, 3, 8)
			var rr: float = (5.0 + (f - 1) * 4.0 * (0.7 + 0.6 * _hf(q, 3, 9))) * s
			var y: float = cy + sin(a) * rr * 0.7 + pow(f - 2, 2.0) * 0.8
			out.append([cos(a) * rr, y, [LT[5], LT[4], LT[3], LT[2]][f - 2], false])
			if q % 3 == 0 and f <= 4:
				out.append([cos(a) * rr * 0.8, y + 1.0, TIDE[5], false])
	if f >= 1:
		var R2: int = int(6 * s)
		for q2 in 14:
			if _hsh(q2, 5, 10) % 3 == 0:
				continue
			var t: float = q2 / 14.0 * TAU
			out.append([roundf(R2 * cos(t)), roundf(R2 * sin(t) * SQ), LT[2] if f < 4 else LT[1], 0.8])
	return out


func _final_blade(R: float, d: Vector2, age: float, sil: bool) -> Array:
	var out: Array = []
	var nv := Vector2(-d.y, d.x)
	var L: float = R * 1.1
	if age > 0.6:
		return out
	var n: int = int(L * 4.0)
	var k_main: float = 1.0 if age < 0.1 else maxf(0.0, 1.0 - (age - 0.1) / 0.25)
	for i in n + 1:
		var u: float = float(i) / float(n)
		var s: float = -L + 2.0 * L * u
		var taper: float = pow(sin(PI * u), 0.5)
		if not sil and age < 0.45:
			var hw0: float = 10.0 * taper
			for j in range(-int(hw0), int(hw0) + 1):
				if absf(j) < 5.0 * taper * k_main:
					continue
				if (i + j) % 2 == 1 and age > 0.2:
					continue
				out.append([d.x * s + nv.x * j, d.y * s + nv.y * j, NAVY, 0.55 * (1.0 - age / 0.45)])
		var hw: float = 5.0 * taper * k_main
		if hw >= 0.3 or sil:
			if sil:
				hw = maxf(hw, 2.5 * taper)
			var m: int = int(ceil(hw * 2.0))
			for j2 in range(-m, m + 1):
				var ww: float = j2 / 2.0
				if absf(ww) > hw + 0.25:
					continue
				var kk: float = absf(ww) / maxf(0.6, hw)
				out.append([roundf(d.x * s + nv.x * ww), roundf(d.y * s + nv.y * ww), LT[6] if kk < 0.4 else (LT[5] if kk < 0.7 else LT[4]), kk < 0.4 and not sil])
		if not sil and absf(u - 0.5) < 0.47 * (1.0 - age / 0.8):
			out.append([roundf(d.x * s - nv.x * 7.0), roundf(d.y * s - nv.y * 7.0), LT[4], false])
	return out


func _crack(R: float, ang: float, age: float, seed: int, life: float) -> Array:
	var out: Array = []
	if age < 0.0 or age > life:
		return out
	var L: float = R * 1.1 * minf(1.0, age / 0.12)
	var al: float = 1.0 if age < life - 0.6 else maxf(0.0, (life - age) / 0.6)
	var c0: Color
	var c1: Color
	if age < 0.25:
		c0 = LT[6]
		c1 = LT[5]
	elif age < 0.8:
		c0 = LT[5]
		c1 = LT[3]
	else:
		c0 = COOL[2]
		c1 = COOL[1]
	var pts: Array = []
	var p := Vector2.ZERO
	var k := 0
	while p.length() < L:
		var a: float = ang + (_hf(k, seed, 11) - 0.5) * 0.5
		p += Vector2(cos(a) * 5.0, sin(a) * 5.0 * SQ)
		pts.append(p)
		k += 1
		if k > 400:
			break
	var prev := Vector2.ZERO
	for i in pts.size():
		var q: Vector2 = pts[i]
		var m: int = int(maxf(absf(q.x - prev.x), absf(q.y - prev.y))) + 1
		for j in m:
			var pp: Vector2 = prev.lerp(q, float(j) / float(m))
			out.append([roundf(pp.x), roundf(pp.y), c0, al])
			if i < pts.size() * 0.85:
				out.append([roundf(pp.x), roundf(pp.y) + 1.0, c1, al])
		if i % 6 == 3 and i < pts.size() - 2:
			var fa: float = ang + (0.7 if _hsh(i, seed, 12) % 2 == 1 else -0.7)
			var fl: float = 6.0 + 8.0 * _hf(i, seed, 13)
			for s in int(fl):
				out.append([roundf(q.x + cos(fa) * s), roundf(q.y + sin(fa) * s * SQ), c1, al * 0.9])
		prev = q
	return out


func _dust_wall(nd: Vector2, age: float, seed: int) -> Array:
	var out: Array = []
	if age < 0.0 or age > 1.2:
		return out
	var u: float = age / 1.2
	for q in 10:
		var h: float = _hf(q, seed, 21)
		var dist: float = (8.0 + 20.0 * h) * (1.0 - pow(1.0 - u, 2.0))
		var along: float = (q - 4.5) * 4.0 + (_hf(q, seed, 22) - 0.5) * 4.0   # 沿斩线方向错开（不排成一横条）
		var x: float = nd.x * dist - nd.y * along
		var y: float = (nd.y * dist + nd.x * along) * SQ - 2.0 - 10.0 * u * (0.5 + h) - 3.0 * _hf(q, seed, 23)
		var szd: float = 3.0 if u < 0.35 else (2.0 if u < 0.7 else 1.0)
		var cd: Color = LT[4] if u < 0.12 else (DUST[3] if u < 0.45 else (DUST[2] if u < 0.75 else DUST[1]))   # 刚扬起那一下被斩光照成亮紫
		out.append([x, y, cd, 0.9 * (1.0 - u * 0.6), szd])
	return out


## 同 grain()：[x, y, 颜色, 边长]；空 = 已熄灭
func _grain(age: float, seed: int, kind: String) -> Array:
	var life: float = {"shard": 0.8, "rock": 1.0, "drop": 0.85}[kind]
	var land: float = {"shard": 0.3, "rock": 0.5, "drop": 0.4}[kind]
	if age < 0.0 or age > life + land:
		return []
	var a: float = _hf(seed, 1, 31) * TAU
	var spd: float = 20.0 + 40.0 * _hf(seed, 2, 32)
	var vh: float = 30.0 + 50.0 * _hf(seed, 3, 33)
	var G := 260.0
	var t: float = minf(age, life)
	var t_land: float = 2.0 * vh / G
	var tt: float = minf(t, t_land)
	var h: float = maxf(0.0, vh * tt - 0.5 * G * tt * tt) if t < t_land else 0.0
	var landed: bool = t >= t_land
	var c: Color
	var sz := 2.0
	match kind:
		"shard":
			c = LT[6] if age < 0.15 else (LT[5] if age < 0.4 else LT[3])
		"rock":
			c = (LT[4] if age < 0.2 else DUST[3]) if not landed else DUST[2]
			sz = 4.0 if seed % 2 == 1 else 3.0
		_:
			c = TIDE[5] if not landed else TIDE[3]
	return [cos(a) * spd * tt, sin(a) * spd * tt * SQ - h, c, sz / 2.0]
