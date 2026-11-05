## 歌蕾蒂娅终结技（海渊漩涡）转平面叠加层（docs/263 §9，开关 ult/px_plane 或 ult/px_plane_gladiia，缺省 0 = 原画面）。
## 口径（ult_brief 第 9 条，用户 11-05 晚「剩下的把配色能改的就改了，然后有的能用 pixelfx 加强一下的也做一下」）：
##   原版的造型、节奏、体量一律保留（掷枪落涡、漩涡贴图越转越快往里收、收拢一砸、凝住、潮水爆开）；
##   ① 配色对齐到普攻 / 技能定稿那套：深海蓝 OP.gladiia（#182f51 → 白）+ 精二深渊紫点缀，原来的青白水色、白光团换掉 / 收小（颜色在 ult_moves_b._gl_* 里按 pal() 取）；
##   ② 只在最大那一下（爆开）加：冲击帧（原版就有，照旧）后的慢动作、实心小亮核 2 拍 + 满亮照地灯、压扁厚冲击环 4 拍推到判定边（推过的地面闪一下）、
##      贴地环形水爆（湿环 + 抛物线水滴，地上有影子，落地成白点）、怪物本色崩解（同 docs/275 §1.0）、轻震 3px / 0.12 秒。
## 只画：不碰判定 / 时序 / 伤害 / 随机数（散布全按坐标哈希）；慢动作挂 ult.time_scale（演出类，批跑 / TRACE 不缩）。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const D = preload("res://scripts/data.gd")   # 怪物代表色 ecol（崩解喷散取怪物自身颜色）
const UM = preload("res://scripts/ui_motion.gd")
const SY := 0.72
const C := [Color("#0d1a2e"), Color("#182f51"), Color("#294a78"), Color("#3a65a0"), Color("#4c80c7"), Color("#8bacdb"), Color("#c9d9ee"), Color("#ffffff")]
const ACC := Color("#b3a8ee")   # 精二深渊紫
const LIGHT := Color("#7fa6e0")
const CORE_T := 2.0 / 15.0      # 亮核 2 拍
const SHOCK_T := 4.0 / 15.0     # 冲击环 4 拍推到判定边
const DROPS := 30               # 贴地水爆的水滴数（docs/270 爆发档一簇 ≤ 25 的水滴 + 崩解另算；水滴是主形的一部分）
const HIT_MAX := 120
const SPRAY_N := 22
const SPRAY_MAX := 80

var g
var st := {}   # 这一次：{c, R, t0 爆开游戏时刻, rt 真实时刻, hits, sprays, lit}
var _emit_n := 0
var _emit_frame := -1


static func on() -> bool:
	return Bal.v("ult/px_plane", 0.0) > 0.0 or Bal.v("ult/px_plane_gladiia", 0.0) > 0.0


static func of(game):
	if game.has_meta("ult_px_gl"):
		return game.get_meta("ult_px_gl")
	var r = new()
	r.g = game
	game.set_meta("ult_px_gl", r)
	return r


## 配色（ult_moves_b._gl_* 按这个取；开关关时返回原版的颜色）
static func pal(u, o) -> Dictionary:
	if not on():
		var col: Color = u._col(o)
		return {"col": col, "foam": Color(0.82, 0.97, 1.0), "mote": Color(0.8, 1.0, 1.0), "cols": [Color(0.85, 1.0, 1.0), Color(0.5, 0.9, 0.95), Color(0.3, 0.75, 0.85), Color(0.7, 0.95, 1.0)],
			"flash": Color(0.9, 1.0, 1.0), "light": Color(0.5, 0.95, 1.0), "ember": Color(0.7, 0.95, 1.0), "vo": Color(1, 1, 1, 0.55), "vi": Color(1.1, 1.15, 1.15, 0.7), "px": false}
	var el: int = int(o.elite) if o != null and o.get("elite") != null else 0
	var cols := [C[6], C[5], C[4], C[3]]
	if el >= 2:
		cols.append(ACC)
	return {"col": C[4], "foam": C[6], "mote": C[6], "cols": cols, "flash": C[6], "light": LIGHT, "ember": ACC if el >= 2 else C[5],
		"vo": Color(0.72, 0.84, 1.1, 0.55), "vi": Color(0.8, 0.9, 1.15, 0.7), "px": true}


# ================================================================ 事件（ult_moves_b._gl_step 爆开那一刻转来；只记画面）

func ev(_u, kind: String, d: Dictionary) -> void:
	match kind:
		"burst":
			var hits: Array = []
			for e in d.get("es", []):
				if hits.size() >= HIT_MAX:
					break
				hits.append({"e": e, "p": e.pos, "done": false})
			st = {"c": d.c, "R": float(d.R), "t0": g.t, "rt": UM.now(), "hits": hits, "sprays": [], "lit": false, "sd": float(d.c.x) * 0.013 + float(d.c.y) * 0.029, "el": int(d.get("el", 0))}


func _live() -> bool:
	if st.is_empty():
		return false
	if g.t - float(st.t0) > 2.0:
		st = {}
		return false
	return true


## 爆开后的慢动作：冲击帧两拍（ult/gl_px_slow_delay）过后 ult/gl_px_slow_t 秒 ult/gl_px_slow 倍速，再 ult/gl_px_slow_ease 秒加速回原速（真实时间）
static func slow_scale(game) -> float:
	if not on() or not game.has_meta("ult_px_gl"):
		return 1.0
	var r = game.get_meta("ult_px_gl")
	if r.st.is_empty():
		return 1.0
	var t: float = UM.now() - float(r.st.rt) - Bal.v("ult/gl_px_slow_delay", 0.1)
	var lo: float = Bal.v("ult/gl_px_slow", 0.3)
	var hold: float = Bal.v("ult/gl_px_slow_t", 0.5)
	var ez: float = Bal.v("ult/gl_px_slow_ease", 0.15)
	if t < 0.0 or t >= hold + ez:
		return 1.0
	if t < hold:
		return lo
	var k: float = (t - hold) / ez
	return lerpf(lo, 1.0, k * k)


static func _h(x: float) -> float:
	return fposmod(sin(x * 12.9898 + 78.233) * 43758.5453, 1.0)


func _shock_r() -> float:
	var ac: float = g.t - float(st.t0) - CORE_T * 0.5
	var k: float = clampf(ac / SHOCK_T, 0.0, 1.0)
	return float(st.R) * (0.3 + 0.7 * (1.0 - pow(1.0 - k, 3.0)))


func _px(p: Vector2, c: Color, s := 1.0) -> void:
	g.draw_rect(Rect2((p / 2.0).round() * 2.0, Vector2(g.PX * s, g.PX * s)), c)


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
	g.glow_next.append([(p / 2.0).round() * 2.0, g.PX, Color(c.r, c.g, c.b, 0.8)])


# ================================================================ 绘制（ult.gd draw_world_back / draw_world 转来）

## 地面层：冲击环推过的地面一闪 + 压扁厚冲击环 + 贴地湿环 + 水滴影子
func draw_back(_u, w) -> void:
	if not _live():
		return
	w.tb_flush()
	var c: Vector2 = st.c
	var R: float = float(st.R)
	var age: float = g.t - float(st.t0)
	var sd: float = float(st.sd)
	var rr: float = _shock_r()
	var ac: float = age - CORE_T * 0.5
	if ac >= 0.0 and ac < SHOCK_T + 2.0 / 15.0:
		var fade: float = clampf(1.0 - (ac - SHOCK_T) / (2.0 / 15.0), 0.0, 1.0)
		var m: int = int(ceilf(rr * TAU / 2.0))
		for j in m:
			var a: float = TAU * float(j) / float(m)
			var dv := Vector2(cos(a), sin(a) * SY)
			var q: float = _h(a * 7.3 + sd)
			for k in 5:   # 厚环 5 格：外沿白 → 冰蓝 → 海蓝
				var cc: Color = C[7] if k == 0 else (C[6] if k < 2 else (C[5] if k < 4 else C[4]))
				cc.a = fade * (1.0 if q > 0.12 else 0.5)
				_px(c + dv * (rr - 2.0 * k), cc)
			if q > 0.55:   # 推过的地面一闪（环后 6–14 格，真 alpha）
				var fl: Color = C[5]
				fl.a = 0.28 * fade
				_px(c + dv * (rr - 14.0 - 16.0 * _h(a * 3.1 + sd)), fl)
			if k_glow(j):
				_glow(c + dv * rr, C[7])
	# 贴地湿环：冲击环推到哪，哪里落一圈湿印（暗海蓝，0.6 秒内按噪声散掉）
	if ac >= 0.0 and age < 1.0:
		var gone: float = clampf((age - 0.4) / 0.6, 0.0, 1.0)
		var m2: int = int(ceilf(rr * TAU / 3.0))
		for j in m2:
			var a2: float = TAU * float(j) / float(m2)
			if _h(a2 * 5.1 + sd + 3.0) < 0.35 + 0.65 * gone:
				continue
			var cw: Color = C[2]
			cw.a = 0.6
			_px(c + Vector2(cos(a2), sin(a2) * SY) * rr * (0.82 + 0.1 * _h(a2 * 9.0 + sd)), cw)
	# 水滴的影子（地上，随水滴走；落地后消失）
	for i in DROPS:
		var dp: Array = _drop(i, age, rr)
		if dp.is_empty() or not dp[2]:
			continue
		var sh: Color = C[0]
		sh.a = 0.45
		_px(dp[0], sh)


func k_glow(j: int) -> bool:
	return j % 9 == 0


## 第 i 颗水滴：冲击环推到它的出发半径那一拍甩出，抛物线外甩、落地变白点 → [地面点, 空中点, 在空中]
func _drop(i: int, age: float, rr: float) -> Array:
	var c: Vector2 = st.c
	var R: float = float(st.R)
	var sd: float = float(st.sd) + float(i) * 1.37
	var a: float = TAU * (float(i) + 0.8 * _h(sd)) / float(DROPS)
	var r0: float = R * (0.45 + 0.5 * _h(sd + 1.0))
	var k0: float = clampf((r0 / R - 0.3) / 0.7, 0.0, 1.0)
	var t_start: float = CORE_T * 0.5 + SHOCK_T * (1.0 - pow(1.0 - k0, 1.0 / 3.0))
	var u: float = age - t_start
	if u < 0.0 or u > 0.95:
		return []
	var vh: float = 70.0 + 90.0 * _h(sd + 2.0)
	var vz: float = 110.0 + 120.0 * _h(sd + 3.0)
	var tl: float = 2.0 * vz / 520.0
	var tt: float = minf(u, tl)
	var gp: Vector2 = c + Vector2(cos(a), sin(a) * SY) * (r0 + vh * tt)
	var z: float = vz * tt - 260.0 * tt * tt
	return [gp, gp + Vector2(0, -z), u < tl, u]


## 上层：亮核 2 拍（小，不平涂大圆）、水滴、崩解喷散；起爆那一拍满亮照地灯 + 轻震
func draw_front(_u, w) -> void:
	if not _live():
		return
	w.tb_flush()
	var c: Vector2 = st.c
	var age: float = g.t - float(st.t0)
	if not st.lit:
		st.lit = true
		g.ult.light(c, 240.0, LIGHT, 0.6)   # docs/270 爆发档上限的满亮照地灯
		g.ult.shake(Bal.v("ult/gl_px_shake", 3.0), Bal.v("ult/gl_px_shake_t", 0.12))
	if age < CORE_T:   # 实心小亮核：白芯 + 冰蓝 + 海蓝三层，半径 7 / 11 / 15 格（判定一半以内）
		for k in 3:
			var rk: float = [30.0, 22.0, 14.0][k]
			var ck: Color = [C[4], C[6], C[7]][k]
			var n: int = int(rk)
			for y in range(-n, n + 1, 2):
				for x in range(-n, n + 1, 2):
					if Vector2(x, y / SY).length() <= rk:
						_px(c + Vector2(x, y - 10), ck)
		for q in 8:
			_glow(c + Vector2.from_angle(TAU * q / 8.0) * 10.0 + Vector2(0, -10), C[7])
	var rr: float = _shock_r()
	for i in DROPS:
		var dp: Array = _drop(i, age, rr)
		if dp.is_empty():
			continue
		var u: float = float(dp[3])
		if dp[2]:
			var cc: Color = C[7] if u < 0.07 else (C[6] if i % 3 else C[5])
			if i % 7 == 3 and int(st.get("el", 0)) >= 2:   # 精二：几颗深渊紫水滴
				cc = ACC
			_px(dp[1], cc, 2.0 if i % 2 == 0 else 1.0)
			if u < 0.12:
				_px(dp[1] + Vector2(0, 2), C[4])
		elif u - 2.0 * (110.0 + 120.0 * _h(float(st.sd) + float(i) * 1.37 + 3.0)) / 520.0 < 0.12:
			_px(dp[0], C[6])   # 落地白点
	_shatter_tick(rr)
	_draw_sprays()


# ================================================================ 怪物崩解（同 docs/275 §1.0 / ult_px_sd）：冲击环扫到被这一招打中的怪那一拍
func _shatter_tick(rr: float) -> void:
	var c: Vector2 = st.c
	var ac: float = g.t - float(st.t0) - CORE_T * 0.5
	if ac < 0.0:
		return
	for h in st.hits:
		if h.done:
			continue
		var p: Vector2 = h.e.pos if not h.e.get("dead", false) else h.p
		var rel: Vector2 = p - c
		var dist: float = Vector2(rel.x, rel.y / SY).length()
		if dist <= rr or ac >= SHOCK_T:
			h.done = true
			_monster_burst(h.e, p, rel)


func _monster_burst(e: Dictionary, p: Vector2, rel: Vector2) -> void:
	if g.optical_on and g.optical != null and g.optical.particles != null and not e.get("boss", false):
		g.optical.particles.kill_burst(e)   # 补一次引擎原有的击杀碎屑（原有的照常、时机不动）
	var col: Color = D.ENEMIES.get(str(e.get("type", "")), {}).get("ecol", Color(0.6, 0.8, 0.9))
	var out: Vector2 = Vector2(rel.x, rel.y / SY).normalized() if rel.length() > 1.0 else Vector2.RIGHT
	st.sprays.append({"p": p + Vector2(0, -10), "t0": g.t, "col": col, "out": out, "sd": int(e.get("id", 0)) * 13 + 5})
	if st.sprays.size() > SPRAY_MAX:
		st.sprays.pop_front()


static func _hf(x: int, y: int, k: int) -> float:
	return float(((x * 73856093) ^ (y * 19349663) ^ (k * 83492791)) & 0xFFFF) / 65535.0


func _draw_sprays() -> void:
	var px: float = g.PX
	for sp in st.sprays:
		var age: float = g.t - float(sp.t0)
		if age > 1.3 or age < 0.0:
			continue
		var col: Color = sp.col
		var cols: Array = [col.lightened(0.45), col.lightened(0.15), col, col.darkened(0.3)]
		var base: Vector2 = ((sp.p as Vector2) / 2.0).round() * 2.0
		var sd: int = int(sp.sd)
		for q in SPRAY_N:
			var ang: float = (sp.out as Vector2).angle() + (_hf(q, sd, 71) - 0.5) * 1.8
			var spd: float = 40.0 + 90.0 * _hf(q, sd, 72)
			var vh: float = 30.0 + 60.0 * _hf(q, sd, 73)
			var t_land: float = 2.0 * vh / 260.0
			var t: float = minf(age, 0.9)
			var tt: float = minf(t, t_land)
			var hgt: float = maxf(0.0, vh * tt - 130.0 * tt * tt) if t < t_land else 0.0
			var off := Vector2(cos(ang) * spd * tt, sin(ang) * spd * tt * SY - hgt)
			var cc: Color = cols[q % 4]
			var hot: bool = age < 2.0 / 15.0 and q % 3 == 0
			if hot:
				cc = Color.WHITE
			cc.a = 1.0 if age < 0.9 else maxf(0.0, (1.3 - age) / 0.4)
			var sz: float = px * (2.0 if q % 3 != 2 else 1.0)
			g.draw_rect(Rect2(base + (off / 2.0).round() * 2.0, Vector2(sz, sz)), cc)
			if hot:
				_glow(base + off, Color.WHITE)
