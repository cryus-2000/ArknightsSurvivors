## 归溟幽灵鲨终结技（弹射撕裂 + 收尾巨锯，ult_fx_c.sb_*）转平面画面（docs/268 §9，ult_brief §9：配色对齐 + 最大那一下加强）。
## 开关 ult/px_plane（总开关）或 ult/px_plane_specter_unchained（她一人），缺省 0 = 原画面。只改画面：判定 / 时序 / 伤害 / 冲击帧 / 顿帧 / 震屏全照原样。
## 配色：原版的血红 / 暗红换成普攻 / 技能定稿那套（深海蓝 AB、钢、火星橙 SP、替身青 GH；新美术不用红），换色在 ult_fx_c 里按 col() 取；锯的造型、节奏、体量不动。
## 只在收尾巨锯落地那一下（冲击帧那一拍）加：
##   ① 慢动作：冲击帧顿帧（ult/sb_hitstop）过后 ult/su_px_slow_t 秒 ult/su_px_slow 倍速，再 ult/su_px_slow_ease 秒加速回原速（挂 ult.time_scale，演出类，批跑 / TRACE 不缩）；
##   ② 亮核：落点一簇白 / 冰蓝亮点（不是平涂大圆）亮 2 拍，进发光层；照地灯打满；
##   ③ 冲击环：一圈厚而亮的压扁环 4 拍推到判定边缘（终结技半径），推过的地面闪一下（暗蓝断续内圈）；
##   ④ 崩解：这一圈锯到的怪，冲击环扫到那一拍补一次引擎原有的击杀碎屑 + 一圈怪物本色像素往外喷（做法同斯卡蒂 ult_px_sd / 艾丽妮 docs/275 §1.0）。
## 散布按哈希，不抽随机数。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const D = preload("res://scripts/data.gd")   # 怪物代表色 ecol（崩解喷散取怪物自身颜色）
const UM = preload("res://scripts/ui_motion.gd")
const FPS := 15.0
const HIT_MAX := 120
const SPRAY_N := 22
const SPRAY_MAX := 80
const SHOCK_T := 4.0 / 15.0   # 冲击环 4 拍推到边
const SY := 0.72
## 定稿配色（同 fx_pxplane_su / tools/pxplane_su_art.py）
const AB := [Color("#060a15"), Color("#0d1832"), Color("#172f5e"), Color("#234d94"), Color("#3a77c2"), Color("#78afe6"), Color("#c4e2fa"), Color("#ffffff")]
const GH := [Color("#0e3846"), Color("#2a7c96"), Color("#6ccde4"), Color("#c6f4ff")]
const SP := [Color("#fff3cc"), Color("#ffd27a"), Color("#ffa04a"), Color("#e3692a"), Color("#8a3d1d")]

var g
var st := {}            # 这一次：{t0, crash_t, crash_rt, ctr, R, hits, sprays, lit}
var _emit_n := 0
var _emit_frame := -1


static func on() -> bool:
	return Bal.v("ult/px_plane", 0.0) > 0.0 or Bal.v("ult/px_plane_specter_unchained", 0.0) > 0.0


static func of(game):
	if game.has_meta("ult_px_su"):
		return game.get_meta("ult_px_su")
	var r = new()
	r.g = game
	game.set_meta("ult_px_su", r)
	return r


## 换色：开关开着用新配色，关着照原色（ult_fx_c 各处调）
static func col(orig: Color, px: Color) -> Color:
	return px if on() else orig


static func ev(u, kind: String, d: Dictionary) -> void:
	if not on():
		return
	of(u.g)._ev(u, kind, d)


func _ev(u, kind: String, d: Dictionary) -> void:
	match kind:
		"start":
			st = {"t0": g.t, "crash_t": -1.0, "hits": [], "sprays": [], "lit": true}
		"hit":   # 收尾那一圈锯到的怪：冲击环扫到它那一拍补崩解（同一只只记一次）
			if not st.is_empty() and st.hits.size() < HIT_MAX:
				var e: Dictionary = d.e
				for h in st.hits:
					if is_same(h.e, e):
						return
				st.hits.append({"e": e, "p": e.pos, "done": false})
		"crash":   # 收尾巨锯落地（冲击帧那一拍）：之后慢动作、亮核、冲击环、崩解
			if not st.is_empty():
				st.crash_t = g.t
				st["crash_rt"] = UM.now()
				st["ctr"] = d.c
				st["R"] = float(d.R)
				st["lit"] = false


func _live() -> bool:
	if st.is_empty():
		return false
	if g.t - float(st.t0) > 8.0:
		st = {}
		return false
	return true


static func _hf(x: int, y: int, k: int) -> float:
	return float(((x * 73856093) ^ (y * 19349663) ^ (k * 83492791)) & 0xFFFF) / 65535.0


## 慢动作（ult.time_scale 取最小）
static func slow_scale(game) -> float:
	if not on() or not game.has_meta("ult_px_su"):
		return 1.0
	var r = game.get_meta("ult_px_su")
	if r.st.is_empty() or not r.st.has("crash_rt"):
		return 1.0
	var t: float = UM.now() - float(r.st.crash_rt) - Bal.v("ult/sb_hitstop", 0.16)
	var lo: float = Bal.v("ult/su_px_slow", 0.3)
	var hold: float = Bal.v("ult/su_px_slow_t", 0.5)
	var ez: float = Bal.v("ult/su_px_slow_ease", 0.15)
	if t < 0.0 or t >= hold + ez:
		return 1.0
	if t < hold:
		return lo
	var k: float = (t - hold) / ez
	return lerpf(lo, 1.0, k * k)


func _age() -> float:
	return g.t - float(st.crash_t) if float(st.get("crash_t", -1.0)) >= 0.0 else -1.0


func _beat() -> int:
	return int(floor(g.t * FPS + 0.0001)) - int(floor(float(st.crash_t) * FPS + 0.0001))


func _shock_r(ac: float) -> float:
	var k: float = clampf(ac / SHOCK_T, 0.0, 1.0)
	var R: float = float(st.R)
	return R * (0.15 + 0.85 * (1.0 - pow(1.0 - k, 2.5)))


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
	g.glow_next.append([p, g.PX, Color(c.r, c.g, c.b, Bal.v("fx/px_plane_emit", 0.8))])


static func _snap(v: Vector2) -> Vector2:
	return (v / 2.0).round() * 2.0


# ================================================================ 绘制（ult.gd draw_back / draw_front 转来）

## 贴地：冲击环（4 拍推到边，厚 3 圈、外沿最亮、断口按哈希）+ 推过的地面闪一下（环后面一圈暗蓝断续）
func draw_back(_u, w) -> void:
	if not _live() or _age() < 0.0:
		return
	var f: int = _beat()
	if f < 0 or f > 6:
		return
	w.tb_flush()
	var ctr: Vector2 = st.ctr
	var rr: float = _shock_r(minf(_age(), SHOCK_T))
	var px: float = g.PX
	var rows: Array = []   # [半径偏移（美术像素）, 颜色]
	if f <= 3:
		rows = [[0.0, AB[7] if f <= 1 else AB[6]], [-1.0, AB[6]], [-2.0, AB[5]], [-3.0, AB[5]], [-4.0, AB[4]], [-5.0, AB[3]]]
	elif f <= 5:
		rows = [[0.0, AB[5]], [-1.0, AB[4]], [-2.0, AB[3]]]
	else:
		rows = [[0.0, AB[3]]]
	var n: int = clampi(int(TAU * rr / (px * 2.0)), 48, 720)
	for row in rows:
		var r0: float = rr + float(row[0]) * px
		var c: Color = row[1]
		var pts := PackedVector2Array()
		for i in n + 1:
			var a: float = TAU * float(i) / float(n)
			var seg: int = int(a * 6.0)
			if _hf(seg, f / 2, 17) < 0.14 and f >= 2:   # 断口（第 2 拍起）
				if pts.size() >= 2:
					g.draw_polyline(pts, c, px)
				pts = PackedVector2Array()
				continue
			pts.append(_snap(ctr + Vector2(cos(a) * r0, sin(a) * r0 * SY)))
		if pts.size() >= 2:
			g.draw_polyline(pts, c, px)
	# 推过的地面闪一下：环内侧 30% 处一圈暗蓝断续点（第 1–4 拍）
	if f >= 1 and f <= 4:
		var ri: float = rr * 0.72
		var m: int = clampi(int(TAU * ri / (px * 3.0)), 32, 480)
		for i in m:
			if (i % 3) == 2:
				continue
			var a2: float = TAU * float(i) / float(m)
			g.draw_rect(Rect2(_snap(ctr + Vector2(cos(a2) * ri, sin(a2) * ri * SY)), Vector2(px, px)), AB[4] if f <= 2 else AB[3])
	if f <= 2:   # 外沿最亮的那圈进发光层（隔点取，整帧 ≤ 160）
		for i in 80:
			var a3: float = TAU * float(i) / 80.0
			_glow(ctr + Vector2(cos(a3) * rr, sin(a3) * rr * SY), AB[6])


## 立起：亮核（2 拍）、崩解喷散；冲击环扫到时补击杀碎屑
func draw_front(u, w) -> void:
	if not _live() or _age() < 0.0:
		return
	w.tb_flush()
	var ctr: Vector2 = st.ctr
	if not st.lit:
		st.lit = true
		u.light(ctr, float(st.R) * 0.9, Color(0.85, 0.93, 1.0), 0.6)   # 照地灯打满（docs/270 爆发档上段，冷白蓝，不发白）
		u.light(ctr, float(st.R) * 0.45, SP[1], 0.35)   # 锯磨地的橙热芯
	var f: int = _beat()
	if f >= 0 and f <= 1:   # 亮核：一簇白 / 冰蓝 / 橙亮点（黄金角散开，靠中心密），不是平涂大圆
		var px: float = g.PX
		for i in 90:
			var a: float = float(i) * 2.39996
			var r: float = 70.0 * sqrt(float(i) / 90.0) * (1.0 if f == 0 else 1.25)
			var p: Vector2 = _snap(ctr + Vector2(cos(a) * r, sin(a) * r * SY - 18.0))
			var c: Color = AB[7] if r < 34.0 else (AB[6] if i % 3 else SP[1])
			var sz: float = px * (2.0 if r < 46.0 else 1.0)
			g.draw_rect(Rect2(p, Vector2(sz, sz)), c)
			if i % 2 == 0:
				_glow(p, c)
	_shatter_tick()
	_draw_sprays()


func _shatter_tick() -> void:
	if st.hits.is_empty():
		return
	var ac: float = _age()
	var ctr: Vector2 = st.ctr
	var rr: float = _shock_r(ac)
	for h in st.hits:
		if h.done:
			continue
		var p: Vector2 = h.e.pos if not h.e.get("dead", false) else h.p
		var rel: Vector2 = p - ctr
		var dist: float = Vector2(rel.x, rel.y / SY).length()
		if dist <= rr or ac >= SHOCK_T:
			h.done = true
			_monster_burst(h.e, p, rel, 1.0 if dist <= float(st.R) else 0.7)


func _monster_burst(e: Dictionary, p: Vector2, rel: Vector2, k: float) -> void:
	if g.optical_on and g.optical != null and g.optical.particles != null and not e.get("boss", false):
		g.optical.particles.kill_burst(e)   # 引擎原有的击杀碎屑（原有那次照常、时机不动，这里补一次）
	var c: Color = D.ENEMIES.get(str(e.get("type", "")), {}).get("ecol", Color(0.6, 0.9, 0.9))
	var out: Vector2 = Vector2(rel.x, rel.y / SY).normalized() if rel.length() > 1.0 else Vector2.RIGHT
	st.sprays.append({"p": p + Vector2(0, -10), "t0": g.t, "col": c, "out": out, "k": k, "sd": int(e.get("id", 0)) * 13 + 5})
	if st.sprays.size() > SPRAY_MAX:
		st.sprays.pop_front()


func _draw_sprays() -> void:
	var px: float = g.PX
	for sp in st.sprays:
		var age: float = g.t - float(sp.t0)
		if age > 1.3 or age < 0.0:
			continue
		var c0: Color = sp.col
		var cols: Array = [c0.lightened(0.45), c0.lightened(0.15), c0, c0.darkened(0.3)]
		var k: float = float(sp.k)
		var base: Vector2 = _snap(sp.p)
		var sd: int = int(sp.sd)
		for q in int(SPRAY_N * k):
			var ang: float = (sp.out as Vector2).angle() + (_hf(q, sd, 71) - 0.5) * 1.8
			var spd: float = (40.0 + 90.0 * _hf(q, sd, 72)) * k
			var vh: float = 30.0 + 60.0 * _hf(q, sd, 73)
			var t_land: float = 2.0 * vh / 260.0
			var t: float = minf(age, 0.9)
			var tt: float = minf(t, t_land)
			var hgt: float = maxf(0.0, vh * tt - 130.0 * tt * tt) if t < t_land else 0.0
			var off := Vector2(cos(ang) * spd * tt, sin(ang) * spd * tt * SY - hgt)
			var c: Color = cols[q % 4]
			var hot: bool = age < 2.0 / 15.0 and q % 3 == 0
			if hot:
				c = Color.WHITE
			c.a = 1.0 if age < 0.9 else maxf(0.0, (1.3 - age) / 0.4)
			var sz: float = px * (2.0 if q % 3 != 2 else 1.0)
			g.draw_rect(Rect2(base + _snap(off), Vector2(sz, sz)), c)
			if hot:
				_glow(base + off, Color.WHITE)
