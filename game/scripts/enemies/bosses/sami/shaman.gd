## 陷落雪祀（3:30）/ 空洞雪祀（7:00）：docs/393 §2.3–§2.4。主轴「挡馈赠」：
## 每 15 秒画出链路 0.8 秒（雪祀 → 最近 3 只小怪，每跳 ≤110；空洞 4 只 ≤145），馈赠球沿链以 220（空洞 260）px/秒跳；
## 队长碰到球 → 链断、雪祀冻僵 2.5 秒受伤 ×1.5（二幕两条链：挡一条 1.5 秒、两条 3 秒）；没挡住，跳到的小怪 10 秒移速 ×2（封顶 140，mech_foes）。
## 空洞雪祀：场上 2 棵族树，链的最后一跳附近有树就跳树，树腐化 20 秒、每 8 秒刷 3 只躯壳。
## 移动：ai ranged 保持 220–300；队长贴近 160 内「踏雪」跳开 120（冷却 4）。寒冷：命中 +30（cold_add，Boss 来源封顶 90）。
## 招：一幕 A 寒链 ② / B 雪幕 ③ / C 霜陷 ① / D 冰环 ④；二幕加 E 寒灾（正反旋臂）/ F 踏雪折返 ②；空洞加 G 虚无道标 ①+②，冷却 ×0.9。
extends "res://scripts/enemies/bosses/sami/sami_boss.gd"


func _hol(e: Dictionary) -> bool:
	return e.type == "shaman2"


func step(e: Dictionary, dt: float, dir: Vector2, dist: float, ready: bool, _mate) -> void:
	tick(e, dt)
	e.cd_k = 0.9 if _hol(e) else 1.0
	# 队长走过的点（霜陷追过去的位置）
	if g.t >= float(e.get("trail_t", 0.0)):
		e.trail_t = g.t + 0.5
		var tr: Array = e.get("trail", [])
		tr.append(g.ppos)
		if tr.size() > 4:
			tr.pop_front()
		e["trail"] = tr
	if _hol(e) and not e.has("trees"):
		var c: Vector2 = center(e)
		e["trees"] = [{"pos": c + Vector2(-260, 120), "rot": 0.0, "next": 0.0}, {"pos": c + Vector2(260, -120), "rot": 0.0, "next": 0.0}]
	for t in e.get("trees", []):
		if float(t.rot) > g.t and g.t >= float(t.next):
			t.next = g.t + 8.0
			summon(e, "husk", 3, 40.0, t.pos)
	# 踏雪：队长贴近 160 内跳开 120
	if dist < 160.0 and float(e.get("hop_t", 0.0)) <= g.t and e.get("dash_t", 0.0) <= 0.0:
		e.hop_t = g.t + 4.0
		e.kb = -dir * sqrt(1800.0 * 120.0)
		e.kb_self = true
		e.dash_decel = 900.0
	# 馈赠
	if float(e.get("gift_cd", 0.0)) == 0.0:
		e.gift_cd = g.t + 6.0
	if ready and g.t >= float(e.gift_cd) and e.get("balls", []).is_empty():
		e.gift_cd = g.t + 15.0
		_gift(e)
	_balls(e, dt)
	pick(e, ready, dir, dist)


func moves(e: Dictionary) -> Array:
	var a: Array = [["寒链", 4.0, 0.0, 9999.0, _a_chain], ["雪幕", 7.0, 0.0, 520.0, _b_veil], ["霜陷", 8.0, 0.0, 9999.0, _c_trap], ["冰环", 8.0, 0.0, 520.0, _d_ring]]
	if act_i(e) >= 1:
		a = [["寒灾", 12.0, 0.0, 9999.0, _e_spiral], ["踏雪折返", 9.0, 0.0, 520.0, _f_hop]] + a
		if _hol(e):
			a.push_front(["虚无道标", 12.0, 0.0, 9999.0, _g_beacon])
	return a


func all_moves(e: Dictionary) -> Array:
	var a: Array = [["寒链", 4.0, 0.0, 9999.0, _a_chain], ["雪幕", 7.0, 0.0, 9999.0, _b_veil], ["霜陷", 8.0, 0.0, 9999.0, _c_trap], ["冰环", 8.0, 0.0, 9999.0, _d_ring],
		["寒灾", 12.0, 0.0, 9999.0, _e_spiral], ["踏雪折返", 9.0, 0.0, 9999.0, _f_hop]]
	if _hol(e):
		a.append(["虚无道标", 12.0, 0.0, 9999.0, _g_beacon])
	return a


## A 寒链：朝队长连射 3 根（空洞 4 根）针，间隔 0.6、每根重新瞄准，直线预警 0.7（半宽 10），伤害逐根 ×0.85
func _a_chain(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var n: int = 4 if _hol(e) else 3
	for k in n:
		var pct: float = 0.14 * pow(0.85, k)
		later(e, 0.6 * k, func(): w_line(e, (g.ppos - e.pos).angle(), 420.0, 20.0, 0.7, pct, "寒链" if k == 0 else ""))
	return 0.6 * n + 0.3


## B 雪幕：70° 扇形米弹 3 波，每波 9 发，间隔 0.3，弹速 210
func _b_veil(e: Dictionary, dir: Vector2, _d: float) -> float:
	var a: float = dir.angle()
	for k in 3:
		later(e, 0.8 + 0.3 * k, func(): fan(e, e.pos, a, deg_to_rad(35.0), 9, 210.0, 0, 0.12))
	w_cone(e, a, deg_to_rad(35.0), 140.0, 0.8, 0.0, "雪幕")
	return 1.8


## C 霜陷：在队长最近走过的 3 个点（空洞 4 个）依次落圈 r45（0.9 秒，间隔 0.6），落地各溅 6 发小圆弹
func _c_trap(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var pts: Array = e.get("trail", [g.ppos]).duplicate()
	pts.append(g.ppos)
	var n: int = 4 if _hol(e) else 3
	pts = pts.slice(maxi(0, pts.size() - n))
	var k := 0
	for p in pts:
		var pp: Vector2 = p
		later(e, 0.6 * k, func():
			var w := w_circle(e, pp, 45.0, 0.9, 0.15, "霜陷" if k == 0 else "")
			w.cb = func(_ww): ring(e, pp, 6, 150.0, 0, 0.06))
		k += 1
	return 0.6 * k + 0.5


## D 冰环：20 发（空洞 24）中圆弹，2 个缺口，扩散 170，显形 0.9
func _d_ring(e: Dictionary, _dir: Vector2, _d: float) -> float:
	ring(e, e.pos, 24 if _hol(e) else 20, 170.0, 1, 0.12, gaps_at(e.pos), 0.0, {"hold": 0.9})
	return 1.2


## E 寒灾：两条旋臂小圆弹，正反各一，持续 3 秒，弹速 160
func _e_spiral(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var a0: float = (g.ppos - e.pos).angle()
	for k in 15:
		later(e, 0.6 + 0.2 * k, func():
			shot(e, e.pos, a0 + 0.35 * k, 160.0, 0, 0.10)
			shot(e, e.pos, a0 + PI - 0.35 * k, 160.0, 0, 0.10))
	return 3.8


## F 踏雪折返：沿穿过队长身边的直线跳 260（半宽 30），沿路留 6 枚冰屑，0.6 秒后各炸成 3 发小圆弹
func _f_hop(e: Dictionary, dir: Vector2, _d: float) -> float:
	var a: float = dir.rotated(0.25).angle()
	var from: Vector2 = e.pos
	var w := w_stab(e, a, 260.0, 60.0, 0.8, 0.16, "踏雪折返")
	w.cb = func(ww):
		for k in 6:
			shot(e, from + Vector2.from_angle(float(ww.ang)) * (40.0 * k + 20.0), float(ww.ang) + PI * 0.5, 1.0, 0, 0.08,
				{"split": {"t": 0.6, "n": 3, "spread": 0.5, "spd": 150.0, "tier": 0}})
	return 1.5


## G 虚无道标（空洞）：雪祀到队长连线上依次立 3 个道标圈（r45，1.0 秒，间隔 0.4），立完沿连线射 12 发针弹列
func _g_beacon(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var tgt: Vector2 = g.ppos
	var from: Vector2 = e.pos
	for k in 3:
		var p: Vector2 = from.lerp(tgt, (k + 1) / 3.0)
		later(e, 0.4 * k, func(): w_circle(e, p, 45.0, 1.0, 0.14, "虚无道标" if k == 0 else ""))
	later(e, 1.4, func():
		w_line(e, (tgt - from).angle(), from.distance_to(tgt) + 200.0, 40.0, 0.8, 0.0, "")
		for k in 12:
			later(e, 0.8 + 0.06 * k, func(): shot(e, from, (tgt - from).angle(), 320.0, 0, 0.10)))
	return 3.0


## ---- 馈赠：链路 = 雪祀 → 最近的小怪（每跳 ≤ hop），球沿链跳；二幕两条（左右各一）
func _gift(e: Dictionary) -> void:
	var hop: float = 145.0 if _hol(e) else 110.0
	var n: int = 4 if _hol(e) else 3
	var chains: int = 2 if act_i(e) >= 1 else 1
	var used: Dictionary = {}
	e["balls"] = []
	e["gift_hit"] = 0
	for c in chains:
		var side: Vector2 = Vector2.from_angle((g.ppos - e.pos).angle() + (PI * 0.5 if c == 0 else -PI * 0.5)) if chains > 1 else Vector2.ZERO
		var path: Array = [e.pos]
		var cur: Vector2 = e.pos + side * 60.0
		var tgts: Array = []
		for j in n:
			var best = null
			var bd: float = hop * (2.5 if j == 0 else 1.0)
			for m in g.enemies:
				if m.dead or m.boss or m.get("chest", false) or used.has(m.id):
					continue
				var dd: float = m.pos.distance_to(cur)
				if dd < bd:
					bd = dd
					best = m
			if best == null:
				break
			used[best.id] = true
			tgts.append(best)
			cur = best.pos
			path.append(best.pos)
		var tree = null
		if _hol(e):
			for t in e.get("trees", []):
				if float(t.rot) <= g.t and (c == 1 or t.pos.distance_to(cur) < hop * 2.0):
					tree = t
					break
			if tree != null:
				path.append(tree.pos)
		if path.size() < 2:
			continue
		e.balls.append({"path": path, "tgts": tgts, "tree": tree, "seg": 0, "p": e.pos, "t0": g.t + 0.8, "dead": false})
	if not e.balls.is_empty():
		e.move_name = "反自然馈赠"
		e.move_t = g.t


func _balls(e: Dictionary, dt: float) -> void:
	var bs: Array = e.get("balls", [])
	if bs.is_empty():
		return
	var spd: float = 260.0 if _hol(e) else 220.0
	var live := 0
	for b in bs:
		if b.dead:
			continue
		live += 1
		if g.t < float(b.t0):
			continue
		var path: Array = b.path
		var nxt: int = int(b.seg) + 1
		if nxt >= path.size():
			b.dead = true
			continue
		var to: Vector2 = path[nxt]
		if nxt - 1 < b.tgts.size() and nxt >= 1 and nxt - 1 < b.tgts.size():
			var m = b.tgts[nxt - 1]
			if not m.dead:
				to = m.pos
		b.p = b.p.move_toward(to, spd * dt)
		# 队长身体（或冲刺）挡下
		if g.ppos.distance_to(b.p) < 26.0 or (g.dash_t > 0.0 and g.ppos.distance_to(b.p) < 40.0):
			b.dead = true
			e.gift_hit = int(e.gift_hit) + 1
			var two: bool = bs.size() > 1
			var t: float = (3.0 if e.gift_hit >= 2 else 1.5) if two else 2.5
			g.combat.start_break(e, t)
			vuln(e, t, 1.5 / maxf(0.01, Bal.v("boss/break_mult", 1.4)))
			g.fx.append({"kind": "ring", "pos": b.p, "r": 30.0, "life": 0.4, "max": 0.4, "col": Color(1.0, 0.85, 0.4)})
			continue
		if b.p.distance_to(to) < 2.0:
			b.seg = nxt
			if nxt - 1 < b.tgts.size():
				var m2 = b.tgts[nxt - 1]
				if not m2.dead:
					m2["gift_until"] = g.t + 10.0
					if g.foe != null:
						g.foe.gifts += 1
			elif b.tree != null:
				b.tree.rot = g.t + 20.0
				b.tree.next = g.t
	if live == 0:
		e.balls = []


## 占位画法：链路（预画 0.8 秒）、馈赠球（金描边）、族树
func draw(e: Dictionary, cv) -> void:
	for t in e.get("trees", []):
		cv.draw_circle(t.pos, 26.0, Color(0.45, 0.2, 0.5, 0.7) if float(t.rot) > g.t else Color(0.3, 0.5, 0.35, 0.7))
	for b in e.get("balls", []):
		if b.dead:
			continue
		var path: Array = b.path
		for i in range(maxi(0, int(b.seg)), path.size() - 1):
			cv.draw_line(path[i], path[i + 1], Color(1.0, 0.85, 0.4, 0.35), 2.0)
		if g.t >= float(b.t0):
			cv.draw_circle(b.p, 9.0, Color(0.6, 0.65, 1.0, 0.95))
			cv.draw_arc(b.p, 11.0, 0.0, TAU, 16, Color(1.0, 0.85, 0.4, 1.0), 2.0)
