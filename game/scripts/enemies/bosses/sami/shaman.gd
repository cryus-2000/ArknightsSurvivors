## 陷落雪祀（3:30）/ 空洞雪祀（7:00）：主轴与数值 docs/393 §2.3–§2.4，招式 §11.3（11-25 差异化定稿），尺寸 §12.4（威慑改数）。主轴「挡馈赠」：
## 每 15 秒画出链路 0.8 秒（雪祀 → 最近 3 只小怪，每跳 ≤110；空洞 4 只 ≤145），馈赠球沿链以 220（空洞 260）px/秒跳；
## 队长碰到球 → 链断、雪祀冻僵 2.5 秒受伤 ×1.5（二幕两条链：挡一条 1.5 秒、两条 3 秒）；没挡住，跳到的小怪 10 秒移速 ×2（封顶 140，mech_foes）。
## 空洞雪祀：场上 2 棵族树，链的最后一跳附近有树就跳树，树腐化 20 秒、每 8 秒刷 3 只躯壳。
## 移动：ai ranged 保持 220–300；队长贴近 160 内「踏雪」跳开 280（冷却 4）；每 10 秒主动换位跳 ≥320，落地溅 8 粒雪（§12.4）。寒冷：命中 +30（cold_add）。
## 招：一幕 A 寒链·弹射 ② / B 风雪·斜飘 ③ / C 霜陷·冰晶 ① / D 冰柱寒链 ④；二幕加 E 寒灾（波动雪带）/ F 踏雪·收屑 ②；空洞加 G 虚无道标 ② 三角，冷却 ×0.9。
## 持续压力「风向」：场上一直有风，每 12 秒换方向；雪祀自己的弹顺风偏 30 px/秒（B / E 的雪按风向飘）。
## 11-28 表现改版（docs/393 §14.5）：主要表现 = 冰链。常驻「风雪幕 / 雪旋」删掉；A 冰链在小怪之间弹跳（跳距按概念图 fm_s1 放大到 240 / 300），每个落点炸一团冰晶；
## B 风雪·斜飘删掉；D 改冰链围笼（围着队长收拢）；E 改链扫；F 冰脚印连成冰链再断；G 改四边形道标围笼；各招的弹只剩冰屑余波（_chips）。
## 出招组（每幕 2）：一幕「寒链」A→C→A、「冰柱」B→D；二幕「寒灾」E→F、「踏雪」F→B→A；空洞二幕「踏雪」换「道标」G→E→A。
## 画面占位；未做：逆风 −10% 移速、冻地减速、雪带推人 30 px（要动公共移动代码，留给实装正式版时一起接）。
extends "res://scripts/enemies/bosses/sami/sami_boss.gd"


func _hol(e: Dictionary) -> bool:
	return e.type == "shaman2"


func _wind(e: Dictionary) -> Vector2:
	return Vector2.from_angle(float(e.get("wind_a", 0.0)))


func step(e: Dictionary, dt: float, dir: Vector2, dist: float, ready: bool, _mate) -> void:
	tick(e, dt)
	e.cd_k = (0.9 if _hol(e) else 1.0) * Bal.v("boss/cd_x_" + str(e.type), 1.0)   # 11-26 中期加强：出招间隔倍率
	# 风向：每 12 秒换（先朝队长那边偏一点，免得一直从同一侧来）
	if g.t >= float(e.get("wind_t", 0.0)):
		e.wind_t = g.t + 12.0
		e.wind_a = (g.ppos - center(e)).angle() + PI * 0.5 + float(int(g.t) % 4) * PI * 0.5
	var wv: Vector2 = _wind(e) * 30.0 * dt
	for b in g.ebullets:
		if b.life > 0.0 and int(b.get("source_id", -1)) == int(e.id) and float(b.get("hold", 0.0)) <= 0.0:
			b.pos += wv
	_tick_cage(e)
	_tick_sweep(e)
	if _hol(e) and not e.has("trees"):
		var c: Vector2 = center(e)
		e["trees"] = [{"pos": c + Vector2(-260, 120), "rot": 0.0, "next": 0.0}, {"pos": c + Vector2(260, -120), "rot": 0.0, "next": 0.0}]
	for t in e.get("trees", []):
		if float(t.rot) > g.t and g.t >= float(t.next):
			t.next = g.t + 8.0
			summon(e, "husk", 3, 40.0, t.pos)
	# 踏雪：队长贴近 160 内跳开 280（§12.4）
	if dist < 160.0 and float(e.get("hop_t", 0.0)) <= g.t and e.get("dash_t", 0.0) <= 0.0:
		e.hop_t = g.t + 4.0
		_hop(e, -dir, 280.0)
	# 主动换位：每 10 秒横跳 ≥320，落地溅一圈 8 粒雪（中弹）
	if not e.has("relo_t"):
		e.relo_t = g.t + 10.0
	if g.t >= float(e.relo_t) and g.t >= float(e.get("busy_t", 0.0)) and not e.get("coma", false):
		e.relo_t = g.t + 10.0
		var side: Vector2 = dir.orthogonal() * (1.0 if int(g.t) % 2 == 0 else -1.0)
		_hop(e, side, 340.0)
		later(e, 0.6, func(): _chips(e, e.pos, dir.angle() + PI, 4, PI * 0.5))   # 11-28：落地 8 粒弹圈 → 4 片冰屑
	# 馈赠
	if float(e.get("gift_cd", 0.0)) == 0.0:
		e.gift_cd = g.t + 6.0
	if ready and g.t >= float(e.gift_cd) and e.get("balls", []).is_empty():
		e.gift_cd = g.t + 15.0
		_gift(e)
	_balls(e, dt)
	_group_pick(e, ready, dir, dist)


## ---- 余波冰屑（11-28，docs/393 §14.1）：n 片短程冰屑，沿 ang 两侧 ±spread 散开，飞约 150 就化掉；不瞄队长
func _chips(e: Dictionary, p: Vector2, ang: float, n: int, spread := 0.6) -> void:
	for i in n:
		var u: float = 0.0 if n == 1 else (float(i) / float(n - 1) * 2.0 - 1.0)
		shot(e, p, ang + u * spread, 150.0, 1, 0.05, {"life": 1.0})


## 跳步：按击退写法自推 ln（初速 √(1800·ln)，900/s² 减速）
func _hop(e: Dictionary, d: Vector2, ln: float) -> void:
	e.kb = d.normalized() * sqrt(1800.0 * ln)
	e.kb_self = true
	e.dash_decel = 900.0


## ---- 招式表 [名, 冷却, 最近, 最远, 函数]
func _a() -> Array:
	return ["寒链·弹射", 4.0, 0.0, 9999.0, _a_chain]


func _c() -> Array:
	return ["霜陷·冰晶", 8.0, 0.0, 9999.0, _c_crystal]


func _d() -> Array:
	return ["冰柱寒链", 8.0, 0.0, 9999.0, _d_hex]


func _e() -> Array:
	return ["寒灾", 12.0, 0.0, 9999.0, _e_bands]


func _f() -> Array:
	return ["踏雪·收屑", 9.0, 0.0, 700.0, _f_hop]


func _g() -> Array:
	return ["虚无道标", 12.0, 0.0, 9999.0, _g_beacon]


func moves(e: Dictionary) -> Array:
	var a: Array = [_a(), _c(), _d()]   # 11-28：B 风雪·斜飘删掉（纯弹幕）
	if act_i(e) >= 1:
		a = [_e(), _f()] + a
		if _hol(e):
			a.push_front(_g())
	return a


func all_moves(e: Dictionary) -> Array:
	var a: Array = [_a(), _c(), _d(), _e(), _f()]
	if _hol(e):
		a.append(_g())
	return a.map(func(m): return [m[0], m[1], 0.0, 9999.0, m[4]])


## 出招组：每 9 秒（空洞 ×0.9）起一组，组里按顺序放（跳过放不出的），组外照常按表挑（同利刃）
func _groups(e: Dictionary) -> Array:
	if act_i(e) < 1:
		return [[_a(), _c(), _a()], [_d(), _a()]]
	return [[_e(), _f()], [_g(), _e(), _a()] if _hol(e) else [_f(), _d(), _a()]]


func _group_pick(e: Dictionary, ready: bool, dir: Vector2, dist: float) -> void:
	if not ready or g.t < float(e.get("busy_t", 0.0)) or e.get("coma", false):
		return
	if not e.has("grp_t"):
		e.grp_t = g.t + 5.0
	var q: Array = e.get("grp", [])
	if q.is_empty() and g.t >= float(e.grp_t):
		var gs: Array = _groups(e)
		var gi: int = int(e.get("grp_i", 0))
		e.grp_i = gi + 1
		q = gs[gi % gs.size()].duplicate()
		e.grp_t = g.t + 9.0 * float(e.get("cd_k", 1.0))
	while not q.is_empty():
		var m: Array = q.pop_front()
		e.grp = q
		var busy: float = float((m[4] as Callable).call(e, dir, dist))
		if busy >= 0.0:
			_cd(e, str(m[0]), float(m[1]) * float(e.get("cd_k", 1.0)))
			e.busy_t = g.t + busy + MC.REC1
			return
	e.grp = []
	pick(e, ready, dir, dist)


## ---- A 寒链·弹射（11-28 改冰链，按概念图 fm_s1）：冰链从雪祀射出，在小怪之间弹跳——第一跳找离雪祀 ≤520 的小怪，之后每跳找
## 离上一个落点 ≤240（空洞 ≤300）、离队长最近的小怪，最多 3 跳（空洞 4 跳），最后一跳跳向队长。每个落点 0.3 秒后依次亮一个冰晶圈
## （r 70，0.9 / 锁定 0.88），到点炸开（小怪落点 12%、队长落点 16%，空洞每跳 ×0.9），炸开处崩 2 片冰屑。没有小怪就直接一跳打队长。
## 链本身是空中的弧（只画），伤人的是每个落点的冰晶；离小怪远就安全
func _a_chain(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var hop: float = 300.0 if _hol(e) else 240.0
	var jumps: int = 4 if _hol(e) else 3
	var cur: Vector2 = e.pos
	var used: Dictionary = {}
	var path: Array = [e.pos]
	for j in jumps:
		var best = null
		var bs := INF
		for m in g.enemies:
			if m.dead or m.boss or m.get("chest", false) or used.has(m.id):
				continue
			var dd: float = (m.pos as Vector2).distance_to(cur)
			if dd > (520.0 if j == 0 else hop):
				continue
			var sc: float = (m.pos as Vector2).distance_to(g.ppos)
			if sc < bs:
				bs = sc
				best = m
		if best == null:
			break
		used[best.id] = true
		cur = best.pos
		path.append(cur)
	var n: int = path.size()   # 小怪落点数 = n - 1，再加一个队长落点
	for i in range(1, n + 1):
		var last: bool = i == n
		var pct: float = (0.16 if last else 0.12) * (pow(0.9, i - 1) if _hol(e) else 1.0)
		var p: Vector2 = Vector2.INF if last else path[i]
		later(e, 0.3 * (i - 1), func():
			var q: Vector2 = g.ppos if last else p
			var w := w_circle(e, q, 70.0, 0.9, pct, "寒链·弹射" if i == 1 else "", {"lock": i == 1, "track_pos": "leader" if last else "", "track": 0.2 if last else 0.0})
			w.cb = func(ww):
				_chips(e, ww.pos, (ww.pos - e.pos).angle(), 2, 0.8))
	var full: Array = path.duplicate()
	full.append(g.ppos)
	if not e.has("links"):
		e["links"] = []
	e.links.append({"path": full, "until": g.t + 0.3 * n + 0.9, "t0": g.t})
	return 0.3 * n + 0.5


## ---- C 霜陷·冰晶（①）：队长预判位置落圈 r 45（0.9 / 0.64），落地后长出六角冰晶：6 根冰枝（长 70、半宽 8）0.6 秒长满
func _c_crystal(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var p: Vector2 = g.combat.arena_clamp(g.ppos + g.pvel.limit_length(float(g.speed) * 1.5) * 0.3, 60.0)
	var w := w_circle(e, p, 45.0, 0.9, 0.20, "霜陷·冰晶")
	w.cb = func(_ww):
		var a0: float = g.t
		for k in 6:
			w_line(e, a0 + TAU * k / 6.0, 70.0, 16.0, 0.6, 0.06, "", {"lock": false, "pos": p})
		later(e, 0.6, func():
			for k in 6:
				_chips(e, p + Vector2.from_angle(a0 + TAU * k / 6.0) * 70.0, a0 + TAU * k / 6.0, 1))   # 11-28：12 发弹圈 → 6 根冰枝末端各掉 1 片
	return 1.2


## ---- D 冰链围笼（11-28 改）：围着队长立 6 根冰柱（r 220，冰柱可见半径 24），柱间连冰链，显形 0.9 秒后 1.2 秒内收到 r 120；
## 2 段链断开 = 出口（背对雪祀一段、再偏 120° 一段，断口提前 0.9 秒标出）；链扫过队长（不在断口里）12%，一次；收到底链崩断，每段迸 2 片冰屑
const CAGE_R0 := 220.0
const CAGE_R1 := 120.0


func _d_hex(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var c: Vector2 = g.ppos
	var a0: float = (c - e.pos).angle()
	var gaps: Array = [a0, a0 + TAU / 3.0]   # 断口方向（段中点）：背对雪祀那段 + 偏 120°
	w_circle(e, c, CAGE_R0, 0.9, 0.0, "冰柱寒链", {"lock": true})
	for ga in gaps:
		w_line(e, float(ga), CAGE_R0 + 40.0, 30.0, 0.9, 0.0, "", {"lock": false, "pos": c})
	e["cage"] = {"c": c, "t0": g.t + 0.9, "a0": a0 - PI / 6.0, "gaps": gaps, "hit": false}
	return 2.3


func _cage_r(cg: Dictionary) -> float:
	return lerpf(CAGE_R0, CAGE_R1, clampf((g.t - float(cg.t0)) / 1.2, 0.0, 1.0))


func _tick_cage(e: Dictionary) -> void:
	var cg = e.get("cage")
	if not (cg is Dictionary) or g.t < float(cg.t0):
		return
	var r: float = _cage_r(cg)
	var dv: Vector2 = g.ppos - (cg.c as Vector2)
	if not cg.hit and absf(dv.length() - r) < 22.0:
		var in_gap := false
		for ga in cg.gaps:
			if absf(angle_difference(dv.angle(), float(ga))) < PI / 6.0:
				in_gap = true
		if not in_gap:
			cg.hit = true
			hit_now(e, g.ppos, 1.0, 0.12)
	if g.t - float(cg.t0) >= 1.2:
		for k in 6:
			var mid: float = float(cg.a0) + TAU * (float(k) + 0.5) / 6.0
			var broken := false
			for ga in cg.gaps:
				if absf(angle_difference(mid, float(ga))) < PI / 6.0:
					broken = true
			if not broken:
				_chips(e, (cg.c as Vector2) + Vector2.from_angle(mid) * r, mid, 2, 0.3)
		e.erase("cage")


## ---- E 寒灾（11-28 改链扫）：上风处场边立两根冰柱，柱间一根冰链（宽 30）顺风扫过（90 px/秒，扫 840），链上留 1 个断口（宽 120）；
## 一共两道，间隔 2.4 秒，断口错开；断口预先画 1.0 秒。链扫过队长（不在断口里）10%，每道一次
func _e_bands(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var wv: Vector2 = _wind(e)
	var nrm: Vector2 = wv.orthogonal()
	var c: Vector2 = g.ppos
	if not e.has("sweeps"):
		e["sweeps"] = []
	for k in 2:
		var gap_off: float = [-90.0, 110.0][k] + g.rng_enemy.randf_range(-40.0, 40.0)
		later(e, 2.4 * k, func():
			var p0: Vector2 = c - wv * 420.0
			w_line(e, wv.angle(), 840.0, 60.0, 1.0, 0.0, "寒灾" if k == 0 else "", {"lock": k == 0, "pos": p0 + nrm * gap_off})
			e.sweeps.append({"p0": p0, "w": wv, "n": nrm, "gap": gap_off, "t0": g.t + 1.0, "hit": false}))
	return 3.6


func _sweep_front(sw: Dictionary) -> float:
	return (g.t - float(sw.t0)) * 90.0


func _tick_sweep(e: Dictionary) -> void:
	if not e.has("sweeps") or e.sweeps.is_empty():
		return
	var keep: Array = []
	for sw in e.sweeps:
		if g.t < float(sw.t0):
			keep.append(sw)
			continue
		var fr: float = _sweep_front(sw)
		if fr > 840.0:
			continue
		keep.append(sw)
		if sw.hit:
			continue
		var dv: Vector2 = g.ppos - (sw.p0 as Vector2)
		if absf(dv.dot(sw.w) - fr) < 22.0 and absf(dv.dot(sw.n) - float(sw.gap)) > 60.0 and absf(dv.dot(sw.n)) < 700.0:
			sw.hit = true
			hit_now(e, g.ppos, 1.0, 0.10)
	e.sweeps = keep


## ---- F 踏雪·收屑（二幕 ②）：沿一条穿过队长身边的直线跳 420（半宽 30，0.8 / 0.6），留 6 个冰脚印；
## 11-28：脚印连成冰链（0.6 秒）再崩断，不再飞回冰屑弹
func _f_hop(e: Dictionary, dir: Vector2, _d: float) -> float:
	var a: float = dir.rotated(0.25).angle()
	var from: Vector2 = e.pos
	var w := w_stab(e, a, 420.0, 60.0, 0.8, 0.16, "踏雪·收屑")
	w.cb = func(ww):
		var dv: Vector2 = Vector2.from_angle(float(ww.ang))
		var land: Vector2 = from + dv * (float(ww.len) - float(e.r))
		var prints: Array = []
		for k in 6:
			prints.append(from + dv * (60.0 * k + 30.0) + dv.orthogonal() * (14.0 if k % 2 == 0 else -14.0))
		e["prints"] = {"pts": prints, "until": g.t + 1.2}
		# 11-28 改连链：6 个冰脚印连成一条冰链（半宽 14，0.6 / 0.6），亮完从两头往中间崩断（中点迸 2 片冰屑）；不再飞回冰屑弹
		var w2 := w_line(e, dv.angle(), from.distance_to(land), 28.0, 0.6, 0.10, "", {"lock": true, "pos": from})
		w2.cb = func(_ww): _chips(e, from.lerp(land, 0.5), dv.angle() + PI * 0.5, 2, 0.4)
	return 1.8


## ---- G 虚无道标（11-28 改四边形围笼）：4 个道标落成以队长为心、外接半径 300 的正方形（边长约 424），道标之间连冰链 2 秒；
## 四条边按顺时针每 0.5 秒亮一条结算（0.9 + 0.5k 秒，链宽 16），往还没亮的那条边外走；最后一条结算处迸 2 片冰屑
func _g_beacon(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var c: Vector2 = g.ppos
	var a0: float = (e.pos - c).angle() + PI / 4.0
	var vs: Array = []
	for k in 4:
		vs.append(c + Vector2.from_angle(a0 + TAU * k / 4.0) * 300.0)
	e["beacons"] = {"pts": vs, "until": g.t + 3.0}
	for k in 4:
		var p: Vector2 = vs[k]
		var q: Vector2 = vs[(k + 1) % 4]
		var w := w_line(e, (q - p).angle(), p.distance_to(q), 16.0, 0.9 + 0.5 * k, 0.14, "虚无道标" if k == 0 else "", {"lock": k == 0, "pos": p})
		if k == 3:
			w.cb = func(_ww): _chips(e, p.lerp(q, 0.5), (p.lerp(q, 0.5) - c).angle(), 2, 0.4)
	return 2.6


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
func _draw_gift(e: Dictionary, cv) -> void:
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


## 占位画法：馈赠 + 弹跳细链、冰脚印、道标、风向箭头（雪祀头顶）
func draw(e: Dictionary, cv) -> void:
	_draw_gift(e, cv)
	var ind := Color(0.55, 0.6, 1.0)
	for l in e.get("links", []):   # 冰链（占位）：相邻落点之间画上拱的弧，链粗 6
		if float(l.until) > g.t:
			var pts: Array = l.path
			for i in range(pts.size() - 1):
				var a: Vector2 = pts[i]
				var b: Vector2 = pts[i + 1]
				var arc := PackedVector2Array()
				for j in 9:
					var u: float = float(j) / 8.0
					arc.append(a.lerp(b, u) + Vector2(0, -sin(PI * u) * minf(90.0, a.distance_to(b) * 0.35)))
				cv.draw_polyline(arc, Color(ind.r, ind.g, ind.b, 0.85), 6.0)
	var cg = e.get("cage")
	if cg is Dictionary:
		var r: float = _cage_r(cg) if g.t >= float(cg.t0) else CAGE_R0
		for k in 6:
			var va: float = float(cg.a0) + TAU * k / 6.0
			var pa: Vector2 = (cg.c as Vector2) + Vector2.from_angle(va) * r
			var pb: Vector2 = (cg.c as Vector2) + Vector2.from_angle(va + TAU / 6.0) * r
			cv.draw_circle(pa, 24.0, Color(0.85, 0.92, 1.0, 0.85))
			var mid: float = va + PI / 6.0
			var broken := false
			for ga in cg.gaps:
				if absf(angle_difference(mid, float(ga))) < PI / 6.0:
					broken = true
			if not broken:
				cv.draw_line(pa, pb, Color(ind.r, ind.g, ind.b, 0.9), 6.0)
	for sw in e.get("sweeps", []):
		if g.t >= float(sw.t0):
			var ctr: Vector2 = (sw.p0 as Vector2) + (sw.w as Vector2) * _sweep_front(sw)
			var n: Vector2 = sw.n
			cv.draw_line(ctr - n * 700.0, ctr + n * (float(sw.gap) - 60.0), Color(ind.r, ind.g, ind.b, 0.9), 8.0)
			cv.draw_line(ctr + n * (float(sw.gap) + 60.0), ctr + n * 700.0, Color(ind.r, ind.g, ind.b, 0.9), 8.0)
	var pr = e.get("prints")
	if pr != null and float(pr.until) > g.t:
		for p in pr.pts:
			cv.draw_circle(p, 9.0, Color(0.85, 0.9, 1.0, 0.6))
	var bc = e.get("beacons")
	if bc != null and float(bc.until) > g.t:
		for p in bc.pts:
			cv.draw_circle(p, 12.0, Color(0.9, 0.92, 1.0, 0.85))
			cv.draw_arc(p, 16.0, 0.0, TAU, 16, Color(ind.r, ind.g, ind.b, 0.9), 2.0)
	var wv: Vector2 = _wind(e)
	var h: Vector2 = e.pos + Vector2(0, -float(e.r) - 34.0)
	cv.draw_line(h - wv * 14.0, h + wv * 14.0, Color(0.9, 0.95, 1.0, 0.8), 2.0)
	cv.draw_line(h + wv * 14.0, h + wv * 6.0 + wv.orthogonal() * 6.0, Color(0.9, 0.95, 1.0, 0.8), 2.0)
	cv.draw_line(h + wv * 14.0, h + wv * 6.0 - wv.orthogonal() * 6.0, Color(0.9, 0.95, 1.0, 0.8), 2.0)


## 测试台逐招对账：没有名字的后续段（第 2、3 发、回程、碎片圈…）记到最近一次有名字的招下（boss_trial.move_tag 读 mv）
func _warn(e: Dictionary, shape: String, dur: float, d: Dictionary) -> Dictionary:
	if str(d.get("name", "")) != "":
		e["cur_mv"] = str(d.name)
	elif not d.has("mv"):
		d["mv"] = str(e.get("cur_mv", ""))
	return super(e, shape, dur, d)


## 中期 Boss 的弹按自己写的 life 消失，不吃场地续飞（shot_pool._arena_fly 会给出界前的弹续 6 秒；11-26 雪祀慢雪片因此叠满 150 上限）
func shot(e: Dictionary, pos: Vector2, ang: float, spd: float, tier: int, pct: float, o := {}) -> void:
	var n0: int = g.ebullets.size()
	super(e, pos, ang, spd, tier, pct, o)
	if g.ebullets.size() > n0:
		g.ebullets[g.ebullets.size() - 1]["no_extend"] = true
