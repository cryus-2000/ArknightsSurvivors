## 艾丽妮终结技「宣判」转平面画面（docs/275，开关 ult/px_plane_irene，11-06 用户点头后缺省 1；0 = 原画面）：只改画面，招式时间轴 / 判定 / 伤害 / 冲击帧逻辑全照 ult_moves_c._irv_*。
## 纹章用用户 10-31 认可的图案，重采样到美术像素格并压扁、只留线稿、改白色阶（11-05 用户：纹章用白、紫留给斩击；tools/ult_px_irene_bake.py → art/fx/pxp/pxp_ult_ir_seal.png）。
## 1 特效像素 = 1 美术像素（g.PX = 2 世界像素），15 fps 节拍（帧号按全局拍子），贴地层压扁 0.72；白 + 亮紫为主，深海蓝潮水作辅色（docs/272 §1）。
## 画法与 tools/ult_px_irene_art.py 一一对应（windup / seal_mod / chain / blade / thread / splash / boom / final_blade / crack / slab / plume / grain），改一边要改另一边。
## 事件由 ult_moves_c 的 _irv_* 在原来画图的位置发（IRP.ev），不抽随机数（散布按坐标哈希）；冲击帧剪影（收尾斩击 + 主裂缝）由 ult._draw_hit_frame 调 draw_hf 画。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const D = preload("res://scripts/data.gd")   # 怪物代表色 ecol（崩解喷散取怪物自身颜色）

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
	return Bal.v("ult/px_plane_irene", 1.0) > 0.0


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
			_monster_burst(e2, d.p, 1.0)   # 崩解：被宣判的怪整只炸成自身像素粒子（11-05 用户「我说的崩解是……怪物炸开的这个特效」）
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
func _pts(w, o0: Vector2, lst: Array, fg = null) -> void:   # 第 3 项颜色可带透明度（第 4 项是 bool 时照用）
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
func draw_front(u, w) -> void:
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
		_pts(w, bp + Vector2(0, -8), _cloud(age, int(b.sd) * 3 + 1, 48.0 if b.big else 40.0, 60))   # 连环爆粒子云（11-05 用户「原本路上爆炸是有粒子效果的，这里换成烟雾了」）
		for q in 3:
			var gr: Array = _grain(age, int(b.sd) * 7 + q, "shard" if q < 2 else "drop")
			if not gr.is_empty():
				_pts(w, bp + Vector2(0, -8), [[gr[0], gr[1], gr[2], 1.0, gr[3]]])
	_draw_sprays(w)
	if float(st.fin_t0) >= 0.0:
		var fa: float = g.t - float(st.fin_t0)
		var dv2: Vector2 = st.dv
		var nv := Vector2(-dv2.y, dv2.x)
		var Rw: float = R * 2.0
		_pts(w, c, _final_blade(R, dv2, fa, false))
		_draw_blast(u, w, c, R, fa)   # 收尾大爆：预备 → 亮核 + 照地灯 + 轻震 + 顿帧 → 冲击环（11-05 用户「缺少最后的爆炸的冲击力」）
		for i in 7:
			var x: float = (float(i) - 3.0) / 3.0
			var bp2: Vector2 = c + dv2 * Rw * x * 0.95 + nv * (_hf(i, 1, 2) - 0.5) * 30.0
			var dl: float = 0.08 + 0.04 * absf(x) * 3.0
			_pts(w, bp2, _boom(int(floor((fa - dl) * 15.0)), true, 2.4))
			_pts(w, bp2 + Vector2(0, -8), _cloud(fa - dl, 500 + i, 50.0, 60))   # 斩线上每一爆也是粒子云（不用烟）
		# 地面碎石（配角）；棕灰尘墙已删（11-05 用户嫌「换成烟雾了」）
		for q in SLAB_N:
			var side2: float = 1.0 if q % 2 == 1 else -1.0
			var x4: float = (float(q / 2) - (SLAB_N / 2 - 1) / 2.0) / ((SLAB_N / 2 - 1) / 2.0)
			_pts(w, c + dv2 * Rw * x4 * 0.95 + nv * side2 * 6.0, _slab(fa - _shock_at(R, absf(x4) * 0.95 * R), 200 + q, nv * side2))   # 冲击环推到哪儿哪儿掀起
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


## 收尾斩击后的崩解（11-05 用户「碎石和尘土比原版薄，少了原作那种崩解感」；同 slab() / plume()）：
## 0–0.12 裂缝爆亮长出 → 0.06 起地面块沿裂缝掀起 → 0.12 起两侧尘墙冲起翻卷 → 约 0.5 秒碎石落地、弹一下、部分碎成小块 → 0.45 秒起尘土塌下散开，0.8 秒散完
const WARM := [Color("#211d1a"), Color("#332d28"), Color("#4a423b"), Color("#655b52"), Color("#8a8076"), Color("#aea398")]
const SLAB_N := 12     # 地面块总数（两侧合计）：配角，11-05 改主角为怪物崩解后减半
const PLUME_N := 8     # 每侧尘墙团数（配角，压暗）


func _slab(age: float, seed: int, nd: Vector2) -> Array:
	var out: Array = []
	if age < 0.0 or age > 1.5:
		return out
	var w: int = 5 + int(4.0 * _hf(seed, 1, 41))
	var h: int = maxi(3, int(w * (0.55 + 0.3 * _hf(seed, 2, 42))))
	var spd: float = 14.0 + 30.0 * _hf(seed, 3, 43)
	var tang: float = -6.0 + 12.0 * _hf(seed, 4, 44)
	var vx: float = nd.x * spd - nd.y * tang
	var vy: float = (nd.y * spd + nd.x * tang) * SQ
	var vh: float = 100.0 + 60.0 * _hf(seed, 5, 45)
	var G := 320.0
	var t1: float = 2.0 * vh / G
	var vh2: float = vh * 0.28
	var t2: float = 2.0 * vh2 / G
	var al: float = 1.0 if age < 1.2 else maxf(0.0, (1.5 - age) / 0.3)
	var x: float
	var y: float
	var z: float
	if age < t1:
		x = vx * age
		y = vy * age
		z = vh * age - 0.5 * G * age * age
	elif age < t1 + t2:
		var t: float = age - t1
		x = vx * (t1 + t * 0.4)
		y = vy * (t1 + t * 0.4)
		z = vh2 * t - 0.5 * G * t * t
	else:
		x = vx * (t1 + t2 * 0.4)
		y = vy * (t1 + t2 * 0.4)
		z = 0.0
	var landed: bool = age >= t1
	if landed and seed % 3 == 0:   # 碎成 3 小块
		var tt: float = age - t1
		for q in 3:
			var a: float = q * 2.1 + _hf(seed, q, 46)
			var d: float = minf(1.0, tt / 0.25) * (3.0 + 3.0 * _hf(seed, q, 47))
			var zz: float = maxf(0.0, 8.0 * tt - 30.0 * tt * tt) if tt < 0.27 else 0.0
			var cx: float = x + cos(a) * d
			var cy: float = y + sin(a) * d * SQ - zz
			for dx in 2:
				for dy in 2:
					out.append([cx + dx, cy + dy, WARM[3] if dy == 0 else WARM[1], al])
		return out
	var rot: bool = _hf(seed, 6, 48) > 0.5
	for dx in w:
		for dy in h:
			if (dx == 0 or dx == w - 1) and (dy == 0 or dy == h - 1) and _hsh(dx, dy, seed) % 2 == 1:
				continue
			var c: Color
			if dy == 0:
				c = LT[4] if age < 0.18 else WARM[4]
			elif dx == (w - 1 if rot else 0):
				c = WARM[1]
			else:
				c = WARM[3] if dy == 1 else WARM[2]
			out.append([x - w / 2.0 + dx, y - z - h + dy, c, al])
	if not landed:
		out.append([x, y + 1.0, WARM[0], 0.6 * al])
		out.append([x + 1.0, y + 1.0, WARM[0], 0.6 * al])
	return out


func _plume(age: float, seed: int, ns: Vector2) -> Array:
	var out: Array = []
	if age < 0.0 or age > 0.8:
		return out
	var up: float = minf(1.0, age / 0.3)
	var fall: float = maxf(0.0, (age - 0.4) / 0.4)
	var fq: int = int(age * 15.0)
	for b in 6:
		var h0: float = _hf(seed, b, 51)
		var H: float = (10.0 + 18.0 * h0) * (1.0 - pow(1.0 - up, 2.0)) * (1.0 - 0.75 * fall)
		var r: float = 3.0 + 4.0 * up + 3.0 * fall + 2.0 * h0
		var curl: float = sin(age * 9.0 + b * 1.7) * (1.0 + 2.0 * up)
		var spread: float = (3.0 + 6.0 * h0) * up + 10.0 * fall
		var along: float = (b - 2.5) * 3.5
		var bx: float = ns.x * spread - ns.y * along + curl
		var by: float = (ns.y * spread + ns.x * along) * SQ - H
		var al: float = 0.5 * pow(1.0 - fall, 1.3)   # 配角：压暗，不盖住怪物崩解
		if al <= 0.03:
			continue
		var ri: int = int(ceil(r))
		for dx in range(-ri, ri + 1):
			for dy in range(-ri, ri + 1):
				var d: float = Vector2(dx, dy * 1.2).length()
				var ang8: int = int((atan2(dy, dx) + PI) / TAU * 8.0) % 8
				var rr: float = r * (0.8 + 0.35 * _hf(b * 8 + ang8, seed, 52))
				if d > rr or (d > rr * 0.7 and _hsh(dx + b, dy, seed + fq) % 4 == 0):
					continue
				var top: bool = dy < -rr * 0.45
				var c: Color
				if top and age < 0.25:
					c = LT[4] if d > rr * 0.5 else LT[5]
				elif d > rr * 0.75:
					c = WARM[2]
				elif top:
					c = WARM[5]
				else:
					c = WARM[4] if d < rr * 0.4 else WARM[3]
				out.append([bx + dx, by + dy, c, al])
	return out


# ================================================================ 收尾大爆（11-05 用户看实机录像：「感觉缺少最后的爆炸的冲击力」）
## 冲击帧之后真正炸开的那一下（fa = 收尾斩击后的游戏秒）：
## 0–BLAST_T（2 拍）预备：光点往中心吸、周围压暗；BLAST_T 起爆点：实心亮核（白芯 + 亮紫圈，半径约判定一半）亮 2 拍 + 一盏打满的照地灯 + 轻震 3px / 0.12 秒 + 3 帧顿帧；
## 同时一圈厚亮的压扁冲击环 SHOCK_T（约 3.5 拍）内从半径一半推到判定边缘，推过的地方地面一闪；碎石 / 尘墙跟着冲击环到达的时刻往外起（_shock_at）
const BLAST_T := 2.0 / 15.0
const SHOCK_T := 3.5 / 15.0


## 冲击环推到距中心 d（美术像素）的时刻（相对收尾斩击，秒）：核心半径以内 = 起爆那一刻
func _shock_at(R: float, d: float) -> float:
	var k: float = clampf((d / R - 0.5) / 0.5, 0.0, 1.0)
	return BLAST_T + (1.0 - sqrt(1.0 - k)) * SHOCK_T   # 冲击环先快后慢（半径 = 1 − (1 − u)²），反解到达时刻


## 实心椭圆（逐行一条横跨，硬边、对齐美术像素格）：rx / ry 美术像素
func _disc(w, c: Vector2, rx: float, ry: float, col: Color) -> void:
	var px: float = g.PX
	var base: Vector2 = (c / 2.0).round() * 2.0
	var n: int = int(ceil(ry))
	for j in range(-n, n + 1):
		var u: float = float(j) / maxf(1.0, ry)
		if absf(u) > 1.0:
			continue
		var hx: float = roundf(rx * sqrt(1.0 - u * u))
		if hx < 1.0:
			continue
		var y: float = base.y + j * px
		w.tb_quad(Vector2(base.x - hx * px, y), Vector2(base.x + hx * px, y), Vector2(base.x + hx * px, y + px), Vector2(base.x - hx * px, y + px), col)


func _draw_blast(u, w, c: Vector2, R: float, fa: float) -> void:
	# ① 预备（2 拍）：周围压暗 + 光点往中心吸
	if fa < BLAST_T + 0.2:
		var kd: float = clampf(fa / BLAST_T, 0.0, 1.0) * (1.0 if fa < BLAST_T else clampf(1.0 - (fa - BLAST_T) / 0.2, 0.0, 1.0))
		if kd > 0.0:
			_disc(w, c, R * 1.05, R * 1.05 * SQ, Color(0.0, 0.0, 0.02, 0.28 * kd))
	if fa < BLAST_T:
		var k: float = fa / BLAST_T
		var lst: Array = []
		for i in 20:
			var a: float = TAU * (i + _hf(i, 9, 61)) / 20.0 + k * 1.5
			var r: float = R * (0.55 + 0.25 * _hf(i, 9, 62)) * pow(1.0 - k, 1.4) + 2.0
			var x: float = cos(a) * r
			var y: float = sin(a) * r * SQ - 10.0
			lst.append([x, y, LT[6] if k > 0.5 else LT[5], k > 0.5])
			lst.append([x - cos(a) * 2.0, y - sin(a) * 2.0 * SQ, LT[4], false])
		_pts(w, c, lst)
		return
	var tau: float = fa - BLAST_T
	var bf: int = int(floor(tau * 15.0))
	# ② 起爆那一刻：照地灯打满 + 轻震 + 3 帧顿帧（一次）
	if not st.get("blasted", false):
		st["blasted"] = true
		u.light(c, 240.0, Color(1.0, 0.85, 1.25), 0.15)   # docs/270 爆发档上限附近（半径 240）
		u.shake(3.0, 0.12)   # 用户同意过的量级；ult.shake 取正在震的较大者，打击感包同时在震时不叠加
		g.vfx.stop(0.05, "ult_blast", true)
		for pn in st.pins:   # 崩解第二波：和大爆同一拍，所有被宣判的怪沿斩线往外再炸一次（更大）
			var ep: Vector2 = pn.last if pn.e.get("dead", false) else pn.e.pos
			_monster_burst(pn.e, ep, 1.6)
	# ③ 亮核（2 拍）：只留中心小一圈（白芯 + 亮紫边），体量靠冲击环和往外喷的粒子撑（11-05：平涂大椭圆像贴纸）
	_pts(w, c + Vector2(0, -6), _cloud(tau, 777, R * 0.6, 160))
	if bf <= 1:
		var rx: float = R * (0.16 if bf == 0 else 0.12)
		_disc(w, c + Vector2(0, -6), rx, rx * SQ, LT[4] if bf == 0 else LT[3])
		_disc(w, c + Vector2(0, -6), rx * 0.78, rx * 0.78 * SQ, LT[5] if bf == 0 else LT[4])
		_disc(w, c + Vector2(0, -6), rx * 0.52, rx * 0.52 * SQ, LT[6] if bf == 0 else LT[5])
		var gl: Array = []
		for i in 24:
			var a2: float = TAU * i / 24.0
			gl.append([cos(a2) * rx * 0.3, sin(a2) * rx * 0.3 * SQ - 3.0, LT[6], true])
		_pts(w, c, gl)
	# ④ 冲击环（约 3.5 拍）：厚 8 格、亮，推过的地方地面一闪
	if tau < SHOCK_T + 2.0 / 15.0:
		var us: float = clampf(tau / SHOCK_T, 0.0, 1.0)
		var rr: float = R * (0.5 + 0.5 * (1.0 - pow(1.0 - us, 2.0)))
		var fade: float = 1.0 if tau < SHOCK_T else clampf(1.0 - (tau - SHOCK_T) / (2.0 / 15.0), 0.0, 1.0)
		var ring: Array = []
		var cols: Array = [LT[6], LT[6], LT[6], LT[5], LT[5], LT[4], LT[4], LT[3]] if tau < SHOCK_T else [LT[5], LT[5], LT[4], LT[4], LT[3], LT[3], LT[2], LT[2]]
		var n: int = int(rr * 6.6) + 16
		for q in n:
			var t: float = float(q) / float(n) * TAU
			var ct := Vector2(cos(t), sin(t) * SQ)
			for j in 8:
				var cj: Color = cols[j]
				ring.append([roundf(ct.x * (rr - j)), roundf(ct.y * (rr - j)), Color(cj.r, cj.g, cj.b, fade), j == 0 and q % 3 == 0])
			if tau < SHOCK_T:   # 地面一闪：环后 6–14 格一道淡亮紫
				for j2 in range(9, 18, 2):
					if (q + j2) % 3 == 0:
						continue
					ring.append([roundf(ct.x * (rr - j2)), roundf(ct.y * (rr - j2)), LT[3], 0.45 * (1.0 - float(j2) / 18.0)])   # [x, y, 颜色, 不透明度]（原来少了第 4 项，_pts 读 q[3] 报错）
		_pts(w, c, ring)


# ================================================================ 怪物崩解（11-05 用户：「我说的崩解是原版那个粒子特效，就是怪物炸开的这个特效」）
## 主角：被宣判的怪整只炸成自身像素粒子。两层：
##   ① 引擎原有的击杀碎屑（optical_particles.kill_burst：按怪物贴图像素碎开，颜色就是怪物自身）——每次连环爆和收尾大爆各补一次（超过 ult/fx_kill_cap 静默的怪也照样碎）；
##   ② 怪物代表色（enemies.json ecol 的亮 / 本色 / 暗三阶 + 头两拍白芯）的像素喷散，沿斩线往外（离斩线越近越往法向喷），有重量、落地、停一下熄灭。
## 只画；粒子散布按坐标哈希（不抽随机数），GPU 碎屑本来就不碰模拟随机数
const SPRAY_N := 22      # 每只每波喷散颗数（docs/270 爆发档一簇 ≤ 25）
const SPRAY_MAX := 70    # 同屏喷散批数上限


func _monster_burst(e: Dictionary, p: Vector2, k: float) -> void:
	if g.optical_on and g.optical != null and g.optical.particles != null and not e.get("boss", false):
		g.optical.particles.kill_burst(e)
	if st.is_empty():
		return
	if not st.has("sprays"):
		st["sprays"] = []
	var col: Color = D.ENEMIES.get(str(e.get("type", "")), {}).get("ecol", Color(0.6, 0.9, 0.9))
	var c: Vector2 = st.c
	var dv: Vector2 = st.dv if float(st.fin_t0) >= 0.0 else (p - c).normalized()
	var nv := Vector2(-dv.y, dv.x)
	var side: float = 1.0 if (p - c).dot(nv) >= 0.0 else -1.0
	var out: Vector2 = (nv * side * 1.4 + (p - c).normalized() * 0.6).normalized() if p != c else nv
	st.sprays.append({"p": p + Vector2(0, -10), "gy": p.y, "t0": g.t, "col": col, "out": out, "k": k, "sd": int(e.get("id", 0)) * 13 + int(k * 7.0)})
	if st.sprays.size() > SPRAY_MAX:
		st.sprays.pop_front()


func _draw_sprays(w) -> void:
	if not st.has("sprays"):
		return
	for sp in st.sprays:
		var age: float = g.t - float(sp.t0)
		if age > 1.3:
			continue
		var col: Color = sp.col
		var cols: Array = [col.lightened(0.45), col.lightened(0.15), col, col.darkened(0.3)]
		var k: float = float(sp.k)
		var lst: Array = []
		for q in int(SPRAY_N * minf(1.4, k)):
			var sd: int = int(sp.sd)
			var ang: float = (sp.out as Vector2).angle() + (_hf(q, sd, 71) - 0.5) * 2.2
			var spd: float = (30.0 + 70.0 * _hf(q, sd, 72)) * k
			var vh: float = 30.0 + 60.0 * _hf(q, sd, 73)
			var G := 260.0
			var t_land: float = 2.0 * vh / G
			var t: float = minf(age, 0.9)
			var tt: float = minf(t, t_land)
			var h: float = maxf(0.0, vh * tt - 0.5 * G * tt * tt) if t < t_land else 0.0
			var x: float = cos(ang) * spd * tt
			var y: float = sin(ang) * spd * tt * SQ - h
			var c: Color = cols[q % 4]
			if age < 2.0 / 15.0 and q % 3 == 0:
				c = Color(1, 1, 1)
			var al: float = 1.0 if age < 0.9 else maxf(0.0, (1.3 - age) / 0.4)
			lst.append([x, y, Color(c.r, c.g, c.b, al), age < 2.0 / 15.0 and q % 3 == 0, 2.0 if q % 3 != 2 else 1.0])
		_pts(w, sp.p, lst)


## 粒子云（连环爆 / 斩线上的爆 / 收尾大爆往外喷；11-05 用户：原版路上的爆炸是一大团闪烁的粒子云，不要烟）：
## 白 / 亮紫 / 淡紫 + 少量浅蓝的 1 格小亮点（每 3 颗一颗 2 格），0.35 秒内往外炸开到 size（美术像素）、之后慢慢漂上去散掉；
## 0.25 秒后逐拍闪烁（每拍三分之一不亮），越往后剩得越少，1.2 秒散完。n = 颗数（缺省按 size 定，60 封顶）。散布按坐标哈希
func _cloud(age: float, sd: int, size: float, n := -1) -> Array:
	var out: Array = []
	if age < 0.0 or age > 1.2:
		return out
	if n < 0:
		n = mini(60, int(30.0 + size * 0.6))
	var fr: int = int(age * 15.0)
	var u: float = minf(1.0, age / 0.35)
	var grow: float = 1.0 - pow(1.0 - u, 2.0)
	for k in n:
		if age > 0.25 and (fr + k) % 3 == 0:
			continue
		if _hf(k, sd, 84) < age / 1.2:
			continue
		var a: float = TAU * _hf(k, sd, 81)
		var r: float = size * sqrt(_hf(k, sd, 82)) * grow + age * 4.0   # 按面积均匀铺满（不成空心圈）
		var x: float = cos(a) * r
		var y: float = sin(a) * r * SQ - age * 10.0 * _hf(k, sd, 83)
		var hc: float = _hf(k, sd, 85)
		var c: Color = LT[6] if hc < 0.35 else (LT[5] if hc < 0.75 else (LT[4] if hc < 0.9 else TIDE[5]))
		if age > 0.6:
			c = LT[5] if c == LT[6] else (LT[4] if c == LT[5] else c)
		out.append([x, y, c, c == LT[6] and age < 0.3, 2.0 if k % 3 == 0 else 1.0])
	return out
