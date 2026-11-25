## 无垠回荡克雷松（结局三 自深处的一瞥）：docs/393 §3.3。不走路、只在 6 个检查点之间闪现（间隔 6 / 6 / 4.5 秒，回荡段 3.5），下一个落点提前 1.5 秒（三幕 1.0）亮出。
## 主轴「稳定」：3 台空间稳定设施（相邻两个检查点之间），队长跑过（r40）启动，1.0 秒充能后放稳定场 r170（7 秒，三幕 5 秒），设施冷却 14 秒；
## 平时受伤 ×0.5（数据 phys_taken / arts_taken 0.5），在稳定场里 ×1.0（这里 ×2 抵掉）。二幕被苗圃缠住的设施要 2 秒内跑过两次。
## 苗圃：每次落地 1.2 秒后附近 2 处变苗圃（r60，20 秒，3%/秒，挨它的招 ×1.5——mech_kingdom nursery / mech_foes）。
## 「回荡」段：第一条命打空后倒下 3 秒，以一半最大生命重生，招式伤害 ×1.5，设施改自动轮流启动（各 5 秒）。
## 招：一幕 双击 ② / 播种 ① / 窥视 ③ / 回荡 ④；二幕 裂隙 ② / 无之花 / 闪现落击 ① / 回声狙；三幕 群苗 / 维度回荡 ④ / 空洞之眼 ② / 视界扇 ③；回荡段 无垠 / 播种·终 ①。
extends "res://scripts/enemies/bosses/sami/sami_boss.gd"


func step(e: Dictionary, dt: float, dir: Vector2, dist: float, ready: bool, _mate) -> void:
	tick(e, dt)
	var c: Vector2 = center(e)
	if not e.has("cps"):
		e["cps"] = []
		for k in 6:
			e.cps.append(c + Vector2.from_angle(TAU * k / 6.0) * 280.0)
		e["devs"] = []
		for k in 3:
			e.devs.append({"pos": c + Vector2.from_angle(TAU * (2 * k + 0.5) / 6.0) * 280.0, "cd": 0.0, "charge": -1.0, "field": 0.0, "taps": [], "auto": false})
		e["cp"] = 0
		e["prev_pos"] = e.pos
		e.pos = e.cps[0]
		e.blink_t = g.t + 6.0
		e.next_cp = 1
	var ai: int = act_i(e)
	var echo: bool = e.get("echo", false)
	var gap: float = 3.5 if echo else (4.5 if ai >= 2 else 6.0)
	var lead_t: float = 1.0 if ai >= 2 else 1.5
	# 闪现
	if g.t >= float(e.blink_t) - lead_t and not e.has("next_shown"):
		e.next_shown = true
	if g.t >= float(e.blink_t) and not e.get("coma", false):
		e.prev_pos = e.pos
		e.cp = int(e.next_cp)
		e.pos = e.cps[e.cp]
		e.next_cp = (e.cp + 1 + int(g.t) % 2) % 6
		e.blink_t = g.t + gap
		e.erase("next_shown")
		var land: Vector2 = e.pos
		later(e, 1.2, func():
			var km = kingdoms()
			if km != null:
				for k in 2:
					var nk: Dictionary = km.add(land + Vector2.from_angle(TAU * k / 2.0 + g.t) * 90.0, 60.0, "nursery", e, 20.0)
					nk.dps = 0.03)
		if ai == 1 and e.pos.distance_to(g.ppos) < 200.0:
			w_circle(e, e.pos, 80.0, 1.0, 0.20, "闪现落击")
	# 设施
	var fdur: float = 5.0 if ai >= 2 else 7.0
	for k in e.devs.size():
		var d: Dictionary = e.devs[k]
		if echo:
			if not d.auto:
				d.auto = true
			var slot: int = int(g.t / 5.0) % 3
			d.field = g.t + 0.1 if slot == k else d.field
			continue
		if float(d.charge) > 0.0 and g.t >= float(d.charge):
			d.charge = -1.0
			d.field = g.t + fdur
			d.cd = g.t + 14.0
		if g.t >= float(d.cd) and float(d.charge) < 0.0 and g.ppos.distance_to(d.pos) < 40.0:
			var tangled: bool = ai >= 1 and kingdoms() != null and kingdoms().inside(d.pos, ["nursery"])
			if tangled:
				var taps: Array = d.taps.filter(func(t): return g.t - float(t) < 2.0)
				if taps.is_empty() or g.t - float(taps[taps.size() - 1]) > 0.6:
					taps.append(g.t)
				d.taps = taps
				if taps.size() < 2:
					continue
				d.taps = []
			d.charge = g.t + 1.0
			d.cd = g.t + 99.0
	pick(e, ready, dir, dist)


func _in_field(e: Dictionary) -> bool:
	for d in e.get("devs", []):
		if float(d.field) > g.t and e.pos.distance_to(d.pos) < 170.0:
			return true
	return false


## 平时受伤 × phys_taken / arts_taken（0.5，combat 已乘）；在稳定场里按 stab_taken（1.0）算，这里乘回差值
func base_taken(e: Dictionary) -> float:
	var d: Dictionary = D.ENEMIES[e.type]
	return float(d.get("stab_taken", 1.0)) / maxf(0.01, float(d.get("phys_taken", 1.0))) if _in_field(e) else 1.0


## 第一条命打空：倒下 3 秒后以一半最大生命重生（回荡段）。倒下走 boss_ai 公共段的 coma 计时（假死同一套）：coma_t 从 race − 3 起算，到时调 on_revive
func on_lethal(e: Dictionary) -> bool:
	if e.get("echo", false):
		return false
	e.echo = true
	e.hp = 1.0
	e.coma = true
	e.invuln = true
	e.stun = 0.0
	e.coma_t = maxf(0.0, Bal.v("boss/pair_race", 8.0) - 3.0)
	e.revives = 0
	e.sq = []
	return true


func on_revive(e: Dictionary) -> void:
	e.maxhp *= float(D.ENEMIES[e.type].get("echo_hp_frac", 0.5))
	e.hp = e.maxhp
	e.dmg_k = float(D.ENEMIES[e.type].get("echo_dmg_k", 1.5))
	e.gates = []
	g.vfx.add_alert(e.pos + Vector2(0, -50), "回荡", col(e), 18)


func moves(e: Dictionary) -> Array:
	if e.get("echo", false):
		return [["无垠", 9.0, 0.0, 9999.0, _endless], ["播种·终", 12.0, 0.0, 9999.0, _sow_all]]
	match act_i(e):
		0:
			return [["回荡", 9.0, 0.0, 9999.0, _echo_ring], ["播种", 8.0, 0.0, 9999.0, _sow], ["窥视", 6.0, 0.0, 9999.0, _peek], ["双击", 4.0, 0.0, 9999.0, _double]]
		1:
			return [["无之花", 10.0, 0.0, 9999.0, _flower], ["裂隙", 8.0, 0.0, 9999.0, _rift], ["回声狙", 7.0, 0.0, 9999.0, _snipe]]
	return [["空洞之眼", 13.0, 0.0, 9999.0, _eye], ["群苗", 12.0, 0.0, 9999.0, _sprouts], ["维度回荡", 10.0, 0.0, 9999.0, _dim_echo], ["视界扇", 8.0, 0.0, 9999.0, _view_fan]]


func all_moves(_e: Dictionary) -> Array:
	return [["双击", 4.0, 0.0, 9999.0, _double], ["播种", 8.0, 0.0, 9999.0, _sow], ["窥视", 6.0, 0.0, 9999.0, _peek], ["回荡", 9.0, 0.0, 9999.0, _echo_ring],
		["裂隙", 8.0, 0.0, 9999.0, _rift], ["无之花", 10.0, 0.0, 9999.0, _flower], ["回声狙", 7.0, 0.0, 9999.0, _snipe],
		["群苗", 12.0, 0.0, 9999.0, _sprouts], ["维度回荡", 10.0, 0.0, 9999.0, _dim_echo], ["空洞之眼", 13.0, 0.0, 9999.0, _eye], ["视界扇", 8.0, 0.0, 9999.0, _view_fan],
		["无垠", 9.0, 0.0, 9999.0, _endless], ["播种·终", 12.0, 0.0, 9999.0, _sow_all]]


func _double(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var a: float = (g.ppos - e.pos).angle()
	var mates: Array = g.squad.ops.filter(func(o): return not o.is_leader and o.pos != Vector2.INF)
	var t2: Vector2 = mates[0].pos if not mates.is_empty() else g.ppos + Vector2.from_angle(a) * 80.0
	w_line(e, a, 520.0, 28.0, 0.7, 0.14, "双击")
	w_line(e, (t2 - e.pos).angle(), 520.0, 28.0, 0.7, 0.14, "")
	return 1.0


func _sow(e: Dictionary, _dir: Vector2, _d: float) -> float:
	for k in 4:
		later(e, 0.5 * k, func():
			var p: Vector2 = g.ppos
			var w := w_circle(e, p, 45.0, 1.0, 0.12, "播种" if k == 0 else "")
			w.cb = func(_ww):
				var km = kingdoms()
				if km != null:
					var nk: Dictionary = km.add(p, 40.0, "nursery", e, 6.0)
					nk.dps = 0.03)
	return 2.4


func _peek(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var a: float = (g.ppos - e.pos).angle()
	w_cone(e, a, deg_to_rad(25.0), 200.0, 0.8, 0.0, "窥视")
	for k in 3:
		later(e, 0.8 + 0.3 * k, func(): fan(e, e.pos, a, deg_to_rad(25.0), 7, 280.0, 0, 0.12))
	return 1.8


func _echo_ring(e: Dictionary, _dir: Vector2, _d: float) -> float:
	ring(e, e.pos, 24, 160.0, 1, 0.13, gaps_at(e.pos), 0.0, {"hold": 0.9})
	var pp: Vector2 = e.get("prev_pos", e.pos)
	later(e, 0.8, func(): ring(e, pp, 24, 160.0, 1, 0.13, gaps_at(pp), 0.0, {"hold": 0.9}))
	return 1.8


func _rift(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var a: float = (g.ppos - e.pos).angle()
	var side: Vector2 = Vector2.from_angle(a).orthogonal()
	for k in [-1, 1]:
		w_line(e, a, 560.0, 52.0, 0.9, 0.16, "裂隙" if k == -1 else "", {"pos": e.pos + side * 90.0 * k})
	later(e, 0.3, func(): w_line(e, a, 560.0, 52.0, 0.9, 0.16, ""))
	return 1.4


func _flower(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var c: Vector2 = e.pos
	var pts: Array = []
	for i in 16:
		pts.append(c + Vector2.from_angle(TAU * i / 16.0) * 100.0)
		shot(e, c, TAU * i / 16.0, 250.0, 0, 0.11, {"life": 0.4, "hold": 0.6})
	later(e, 1.5, func():
		for i in pts.size():
			if i % 2 == 0:
				shot(e, pts[i], (g.ppos - pts[i]).angle(), 220.0, 0, 0.11))
	return 1.8


func _snipe(e: Dictionary, _dir: Vector2, _d: float) -> float:
	aim(e, e.pos, 5, 0.1, 300.0, 0, 0.12, {"hold": 0.6})
	var pp: Vector2 = e.get("prev_pos", e.pos)
	later(e, 0.8, func(): aim(e, pp, 5, 0.1, 300.0, 0, 0.12, {"hold": 0.6}))
	return 1.6


func _sprouts(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var km = kingdoms()
	if km == null:
		return -1.0
	var ns: Array = km.list.filter(func(k): return k.kind == "nursery" and int(k.owner_id) == int(e.id))
	ns = ns.slice(0, 4)
	if ns.is_empty():
		return -1.0
	e.move_name = "群苗"
	e.move_t = g.t
	for j in ns.size():
		var p: Vector2 = ns[j].pos
		var sgn: float = 1.0 if j % 2 == 0 else -1.0
		for k in 15:
			later(e, 0.6 + 0.2 * k, func(): shot(e, p, sgn * 0.45 * k, 120.0, 0, 0.09))
	return 3.6


func _dim_echo(e: Dictionary, _dir: Vector2, _d: float) -> float:
	ring(e, e.pos, 24, 150.0, 1, 0.13, gaps_at(e.pos), 0.0, {"hold": 1.0})
	var pp: Vector2 = e.get("prev_pos", e.pos)
	var ga: Array = gaps_at(pp)
	ring(e, pp, 24, 150.0, 1, 0.13, [float(ga[0]) + 0.6, float(ga[1]) + 0.6], 0.0, {"hold": 1.0})
	return 1.6


## 空洞之眼：激光蓄力 1.0（半宽 20），再横扫 60°（拆成 4 道相继的直线）
func _eye(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var a: float = (g.ppos - e.pos).angle()
	var sgn: float = 1.0 if int(g.t) % 2 == 0 else -1.0
	w_line(e, a, 700.0, 40.0, 1.0, 0.25, "空洞之眼", {"act": "beam"})
	for k in 3:
		later(e, 1.0 + 0.5 * k, func(): w_line(e, a + sgn * deg_to_rad(20.0) * (k + 1), 700.0, 40.0, 0.5, 0.25, "", {"act": "beam"}))
	return 2.8


func _view_fan(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var a: float = (g.ppos - e.pos).angle()
	w_cone(e, a, deg_to_rad(50.0), 200.0, 0.8, 0.0, "视界扇")
	later(e, 0.8, func(): fan(e, e.pos, a, deg_to_rad(50.0), 11, 240.0, 0, 0.12))
	later(e, 1.1, func(): fan(e, e.pos, a + deg_to_rad(5.0), deg_to_rad(50.0), 11, 240.0, 0, 0.12))
	return 1.6


func _endless(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var c: Vector2 = center(e)
	for k in 3:
		var p: Vector2 = e.cps[(int(e.cp) + 2 * k) % 6]
		ring(e, p, 20, 140.0, 1, 0.13, [(c - p).angle()], 0.0, {"hold": 1.0})
	e.move_name = "无垠"
	e.move_t = g.t
	return 1.6


func _sow_all(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var c: Vector2 = center(e)
	for wv in 3:
		later(e, 0.6 * wv, func():
			for k in 10:
				var p: Vector2 = c + Vector2.from_angle(TAU * k / 10.0 + wv * 0.7) * (120.0 + 60.0 * ((k + wv) % 4))
				w_circle(e, p, 45.0, 0.9, 0.15, "播种·终" if wv == 0 and k == 0 else ""))
	return 2.6


func draw(e: Dictionary, cv) -> void:
	for p in e.get("cps", []):
		cv.draw_arc(p, 16.0, 0.0, TAU, 16, Color(0.8, 0.9, 0.4, 0.3), 1.5)
	if e.has("next_shown") and e.has("cps"):
		cv.draw_circle(e.cps[int(e.next_cp)], 20.0, Color(0.8, 0.92, 0.4, 0.45))
	var fxm = g.mech("fx")
	if fxm != null:
		fxm.cresson_draw(e)   # 锚桩光柱稳定场（docs/401 §14）
		return
	for d in e.get("devs", []):
		var on: bool = float(d.field) > g.t
		cv.draw_rect(Rect2(d.pos - Vector2(10, 10), Vector2(20, 20)), Color(1.0, 0.85, 0.4, 0.9) if g.t >= float(d.cd) else Color(0.5, 0.5, 0.5, 0.7))
		if on:
			cv.draw_arc(d.pos, 170.0, 0.0, TAU, 48, Color(1.0, 0.9, 0.5, 0.5), 2.5)
		elif float(d.charge) > 0.0:
			cv.draw_arc(d.pos, 30.0, 0.0, TAU * (1.0 - (float(d.charge) - g.t)), 20, Color(1.0, 0.9, 0.5, 0.8), 3.0)


## 机器人主轴：去离他下一个（或当前）检查点最近、能启动的稳定设施；被苗圃缠住的设施来回过两次；稳定场开着时站在场里
func axis_do(e: Dictionary, p: Vector2) -> Vector2:
	if e.get("echo", false) or not e.has("devs"):
		return Vector2.INF
	var tgt: Vector2 = e.cps[int(e.get("next_cp", e.cp))] if e.has("next_shown") else e.pos
	for d in e.devs:
		if float(d.field) > g.t and tgt.distance_to(d.pos) < 170.0:
			return go_to(p, d.pos + (tgt - d.pos) * 0.4, 30.0)
	var best = null
	for d in e.devs:
		if g.t >= float(d.cd) and float(d.charge) < 0.0 and (best == null or d.pos.distance_to(tgt) < best.pos.distance_to(tgt)):
			best = d
	if best == null:
		return Vector2.INF
	if not (best.taps as Array).is_empty():
		var off: float = 70.0 if int(g.t * 2.0) % 2 == 0 else -70.0   # 缠住的设施：在点两边来回跑，0.6 秒后再踩一次
		return go_to(p, best.pos + Vector2(off, 0), 10.0)
	return go_to(p, best.pos, 12.0)


## 不理主轴：不碰稳定设施（离每台 80 以上）
func axis_ignore(e: Dictionary, p: Vector2) -> Vector2:
	for d in e.get("devs", []):
		if d.pos.distance_to(p) < 80.0:
			return (p - d.pos).normalized()
	return Vector2.INF
