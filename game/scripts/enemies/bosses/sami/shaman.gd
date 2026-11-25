## 陷落雪祀（3:30）/ 空洞雪祀（7:00）：docs/393 §2.3–§2.4。主轴「挡馈赠」：
## 每 15 秒画出链路 0.8 秒（雪祀 → 最近 3 只小怪，每跳 ≤110；空洞 4 只 ≤145），馈赠球沿链以 220（空洞 260）px/秒跳；
## 队长碰到球 → 链断、雪祀冻僵 2.5 秒受伤 ×1.5（二幕两条链：挡一条 1.5 秒、两条 3 秒）；没挡住，跳到的小怪 10 秒移速 ×2（封顶 140，mech_foes）。
## 空洞雪祀：场上 2 棵族树，链的最后一跳附近有树就跳树，树腐化 20 秒、每 8 秒刷 3 只躯壳。
## 移动：ai ranged 保持 220–300；队长贴近 160 内「踏雪」跳开 120（冷却 4）。寒冷：命中 +30（cold_add，Boss 来源封顶 90）。
## 招（docs/393 §11.3 + §12.4，11-26）：一幕 A 寒链·弹射 ② / B 风雪·斜飘 ③ / C 霜陷·冰晶 ① / D 冰柱寒链 ④；二幕加 E 寒灾（摆动雪带）/ F 踏雪·收屑 ②；空洞加 G 虚无道标（三角寒链），冷却 ×0.9；持续压力「风向」。画面占位。
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
	# 踏雪：队长贴近 160 内跳开 280；另外每 10 秒主动换位跳 ≥320，落地溅一圈雪粒 8 发（可见半径 12）（§12.4）
	if not e.has("reloc_t"):
		e.reloc_t = g.t + 10.0
	if dist < 160.0 and float(e.get("hop_t", 0.0)) <= g.t and e.get("dash_t", 0.0) <= 0.0:
		e.hop_t = g.t + 4.0
		e.kb = -dir * sqrt(1800.0 * 280.0)
		e.kb_self = true
		e.dash_decel = 900.0
	elif g.t >= float(e.reloc_t) and float(e.get("busy_t", 0.0)) <= g.t:
		e.reloc_t = g.t + 10.0
		var side: Vector2 = dir.orthogonal() * (1.0 if int(g.t) % 2 == 0 else -1.0)
		e.kb = side * sqrt(1800.0 * 320.0)
		e.kb_self = true
		e.dash_decel = 900.0
		later(e, 0.6, func(): ring(e, e.pos, 8, 150.0, 2, 0.06, [], 0.0, {"life": 1.5}))
	_tick_wind(e, dt)
	_tick_moves(e)
	# 馈赠
	if float(e.get("gift_cd", 0.0)) == 0.0:
		e.gift_cd = g.t + 6.0
	if ready and g.t >= float(e.gift_cd) and e.get("balls", []).is_empty():
		e.gift_cd = g.t + 15.0
		_gift(e)
	_balls(e, dt)
	pick(e, ready, dir, dist)


func moves(e: Dictionary) -> Array:
	var a: Array = [["冰柱寒链", 8.0, 0.0, 9999.0, _d_hex], ["霜陷·冰晶", 8.0, 0.0, 9999.0, _c_crystal], ["风雪·斜飘", 7.0, 0.0, 9999.0, _b_drift], ["寒链·弹射", 4.0, 0.0, 9999.0, _a_chain]]
	if act_i(e) >= 1:
		a = [["寒灾", 12.0, 0.0, 9999.0, _e_bands], ["踏雪·收屑", 9.0, 0.0, 9999.0, _f_hop]] + a
		if _hol(e):
			a.push_front(["虚无道标", 12.0, 0.0, 9999.0, _g_beacon])
	return a


func all_moves(e: Dictionary) -> Array:
	var a: Array = [["寒链·弹射", 4.0, 0.0, 9999.0, _a_chain], ["风雪·斜飘", 7.0, 0.0, 9999.0, _b_drift], ["霜陷·冰晶", 8.0, 0.0, 9999.0, _c_crystal], ["冰柱寒链", 8.0, 0.0, 9999.0, _d_hex],
		["寒灾", 12.0, 0.0, 9999.0, _e_bands], ["踏雪·收屑", 9.0, 0.0, 9999.0, _f_hop]]
	if _hol(e):
		a.append(["虚无道标", 12.0, 0.0, 9999.0, _g_beacon])
	return a


## ---- 持续压力「风向」：每 12 秒换方向；雪祀自己的雪弹顺风偏 30 px/秒；队长逆风走 −10% 移速
func _wind(e: Dictionary) -> Vector2:
	if g.t >= float(e.get("wdir_t", 0.0)):
		e.wdir_t = g.t + 12.0
		e.wdir = Vector2.from_angle(float(int(g.t * 37.0) % 8) * PI / 4.0)
	return e.get("wdir", Vector2.RIGHT)


func _tick_wind(e: Dictionary, dt: float) -> void:
	var w: Vector2 = _wind(e)
	for b in g.ebullets:
		if b.life > 0.0 and int(b.get("source_id", -1)) == int(e.id) and b.get("mc", false):
			b.pos += w * 30.0 * dt
	if g.pvel.length() > 20.0 and g.pvel.normalized().dot(w) < -0.5:
		g.combat.slow_leader("shaman_wind", 0.2, 0.9)
	# 冻地减速（霜陷·冰晶）
	if e.has("icy"):
		e.icy = e.icy.filter(func(x): return float(x[2]) > g.t)
		for x in e.icy:
			if g.ppos.distance_to(x[0]) < float(x[1]):
				g.combat.slow_leader("shaman_icy", 0.3, 0.75)
				break


## A 寒链·弹射：3 根寒针（空洞 4 根），先打队长，命中后在 160（空洞 200）内的目标之间弹（最多 3 / 4 跳，每跳 ×0.85）；弹回队长时再打一次
func _a_chain(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var n: int = 4 if _hol(e) else 3
	for k in n:
		later(e, 0.5 * k, _needle.bind(e, k == 0))
	return 0.5 * n + 0.4


func _needle(e: Dictionary, first: bool) -> void:
	var w := w_line(e, (g.ppos - e.pos).angle(), 560.0, 10.0, 0.7, 0.14, "寒链·弹射" if first else "", {"track": 0.2, "lock": first, "aim_extend": true})
	w.cb = func(_ww): _bounce(e)


func _bounce(e: Dictionary) -> void:
	var hop: float = 200.0 if _hol(e) else 160.0
	var hops: int = 4 if _hol(e) else 3
	var pts: Array = []
	for o in g.squad.ops:
		if not o.is_leader and o.pos != Vector2.INF:
			pts.append(o.pos)
	var cur: Vector2 = g.ppos
	var at_leader := true
	var pct := 0.14
	for i in hops:
		var best = null
		var cands: Array = pts.duplicate()
		if not at_leader:
			cands.append(g.ppos)
		for p in cands:
			var pv: Vector2 = p
			if pv.distance_to(cur) < hop and pv.distance_to(cur) > 4.0 and (best == null or pv.distance_to(cur) < (best as Vector2).distance_to(cur)):
				best = pv
		if best == null:
			return
		pct *= 0.85
		var to: Vector2 = best
		var lw := w_line(e, (to - cur).angle(), cur.distance_to(to), 6.0, 0.6, 0.0, "", {"lock": false})
		lw.pos = cur
		at_leader = to.distance_to(g.ppos) < 4.0
		if at_leader:
			var hp: float = pct
			later(e, 0.6, func(): hit_now(e, g.ppos, 1.0, hp))
		cur = to


## B 风雪·斜飘：前方 90°、r420 的扇区里原地生出一片雪片（可见半径 12），0.4 秒后整片顺风横飘（80 px/秒，0.8 秒）
func _b_drift(e: Dictionary, dir: Vector2, _d: float) -> float:
	var a: float = dir.angle()
	w_cone(e, a, PI / 4.0, 420.0, 0.8, 0.0, "风雪·斜飘", {"track": 0.3})
	later(e, 0.8, _drift_go.bind(e, a))
	return 1.8


func _drift_go(e: Dictionary, a: float) -> void:
	var w := _wind(e)
	for ri in 4:
		for ai in 5:
			var p: Vector2 = e.pos + Vector2.from_angle(a + lerpf(-PI / 4.0, PI / 4.0, ai / 4.0)) * (120.0 + 90.0 * ri)
			shot(e, p, w.angle(), 80.0, 2, 0.12, {"hold": 0.4, "life": 0.8})


## C 霜陷·冰晶：队长脚下落圈（r45，0.9 / 0.64），落地长出六角冰晶（6 根冰枝长 70、宽 16），地面冻 2 秒（减速）
func _c_crystal(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var w := w_circle(e, g.ppos, 45.0, 0.9, 0.15, "霜陷·冰晶", {"track_pos": "leader", "track": 0.26})
	w.cb = func(ww): _crystal_grow(e, ww.pos)
	return 1.2


func _crystal_grow(e: Dictionary, p: Vector2) -> void:
	for i in 6:
		var lw := w_line(e, TAU * i / 6.0, 70.0, 8.0, 0.6, 0.06, "", {"lock": false})
		lw.pos = p
	if not e.has("icy"):
		e["icy"] = []
	e.icy.append([p, 80.0, g.t + 2.0])


## D 冰柱寒链：身边 6 根冰柱 + 柱间寒链组成六边形向外扩（170 px/秒，到 660）；2 段链断开 = 出口（提前 0.9 秒标出）
func _d_hex(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var a0: float = float(int(g.t * 13.0) % 6) * PI / 3.0
	var la: float = (g.ppos - e.pos).angle()
	var k_lead: int = posmod(roundi((la - a0 - PI / 6.0) / (PI / 3.0)), 6)
	var broken: Array = [(k_lead + 2) % 6, (k_lead + 4) % 6]
	var first := true
	for k in broken:
		var w := w_line(e, a0 + PI / 3.0 * k + PI / 6.0, 660.0, 40.0, 0.9, 0.0, "冰柱寒链" if first else "", {"lock": first})
		w.pos = e.pos
		first = false
	e["hex"] = {"c": e.pos, "a0": a0, "broken": broken, "t0": g.t + 0.9, "hit": false}
	return 1.4


## E 寒灾：上风处刮进 3 道正弦摆动的雪带（宽 90、摆幅 40、90 px/秒），每道留 1 个缺口；扫到 10% 并被风推开 30
func _e_bands(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var w := _wind(e)
	var c: Vector2 = g.ppos
	var bands: Array = []
	for k in 3:
		bands.append({"s0": -520.0 - 160.0 * k, "gap": float((int(g.t * 7.0) + k * 3) % 5 - 2) * 140.0, "hit": false})
	e["bands"] = {"c": c, "w": w, "t0": g.t + 1.0, "list": bands}
	var nrm: Vector2 = w.orthogonal()
	var first := true
	for b in bands:
		var gp: Vector2 = c + nrm * float(b.gap)
		var lw := w_line(e, w.angle(), 700.0, 45.0, 1.0, 0.0, "寒灾" if first else "", {"lock": first})
		lw.pos = gp - w * 520.0
		first = false
	return 1.4


## F 踏雪·收屑：沿一条直线跳 420（半宽 30，0.8 / 0.6），留 6 个冰脚印；0.6 秒后脚印碎成冰屑全部飞回落点（200 px/秒）
func _f_hop(e: Dictionary, dir: Vector2, _d: float) -> float:
	var a: float = dir.rotated(0.25).angle()
	var from: Vector2 = e.pos
	var w := w_stab(e, a, 420.0, 30.0, 0.8, 0.16, "踏雪·收屑", {"fit_len": true})
	w.cb = func(ww): _shards(e, from, float(ww.ang))
	return 1.6


func _shards(e: Dictionary, from: Vector2, a: float) -> void:
	var land: Vector2 = from + Vector2.from_angle(a) * 420.0
	for k in 6:
		var p: Vector2 = from + Vector2.from_angle(a) * (60.0 * k + 30.0)
		later(e, 0.6, func(): shot(e, p, (land - p).angle(), 200.0, 2, 0.08, {"life": p.distance_to(land) / 200.0}))


## G 虚无道标（空洞）：从光环上抛出 3 个道标，落在离雪祀约 350 的三角上（边长约 600），道标间寒链 2 秒（宽 16）；三角里面安全
func _g_beacon(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var a0: float = (g.ppos - e.pos).angle() + PI / 3.0
	var pts: Array = []
	for k in 3:
		pts.append(g.combat.arena_clamp(e.pos + Vector2.from_angle(a0 + TAU * k / 3.0) * 350.0, 40.0))
	var first := true
	for k in 3:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[(k + 1) % 3]
		var w := w_line(e, (b - a).angle(), a.distance_to(b), 8.0, 1.0, 0.14, "虚无道标" if first else "", {"lock": first})
		w.pos = a
		first = false
	e["beacon"] = {"pts": pts, "t0": g.t + 1.0, "t1": g.t + 3.0, "hit_t": 0.0}
	return 1.6


func _tick_moves(e: Dictionary) -> void:
	var hx = e.get("hex")
	if hx is Dictionary and g.t >= float(hx.t0):
		var r: float = (g.t - float(hx.t0)) * 170.0
		hx["r"] = r
		if r > 660.0:
			e.erase("hex")
		elif not hx.hit:
			var dv: Vector2 = g.ppos - hx.c
			if absf(dv.length() - r) < 14.0:
				var side: int = posmod(floori((dv.angle() - float(hx.a0)) / (PI / 3.0)), 6)
				if not (side in hx.broken):
					hx.hit = true
					hit_now(e, g.ppos, 1.0, 0.12, {"chill": 0.5})
	var bd = e.get("bands")
	if bd is Dictionary and g.t >= float(bd.t0):
		var el: float = g.t - float(bd.t0)
		var w: Vector2 = bd.w
		var nrm: Vector2 = w.orthogonal()
		var rel: Vector2 = g.ppos - bd.c
		var along: float = rel.dot(w)
		var lat: float = rel.dot(nrm)
		var alive := false
		for b in bd.list:
			var s: float = float(b.s0) + el * 90.0
			if s < 700.0:
				alive = true
			b["s"] = s
			if b.hit:
				continue
			var off: float = 40.0 * sin(lat / 80.0 + el * 2.0)
			if absf(along - (s + off)) < 45.0 and absf(lat - float(b.gap)) > 70.0:
				b.hit = true
				hit_now(e, g.ppos, 1.0, 0.10)
				g.ppos += w * 30.0
		if not alive:
			e.erase("bands")
	var bc = e.get("beacon")
	if bc is Dictionary and g.t >= float(bc.t0):
		if g.t > float(bc.t1):
			e.erase("beacon")
		elif g.t >= float(bc.hit_t):
			for k in 3:
				var a: Vector2 = bc.pts[k]
				var b2: Vector2 = bc.pts[(k + 1) % 3]
				if Geometry2D.get_closest_point_to_segment(g.ppos, a, b2).distance_to(g.ppos) < 18.0:
					bc.hit_t = g.t + 1.0
					hit_now(e, g.ppos, 1.0, 0.14)
					break


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
