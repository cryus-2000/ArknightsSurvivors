## 陷落雪祀（3:30）/ 空洞雪祀（7:00）：主轴与数值 docs/393 §2.3–§2.4，招式 §11.3（11-25 差异化定稿），尺寸 §12.4（威慑改数）。主轴「挡馈赠」：
## 每 15 秒画出链路 0.8 秒（雪祀 → 最近 3 只小怪，每跳 ≤110；空洞 4 只 ≤145），馈赠球沿链以 220（空洞 260）px/秒跳；
## 队长碰到球 → 链断、雪祀冻僵 2.5 秒受伤 ×1.5（二幕两条链：挡一条 1.5 秒、两条 3 秒）；没挡住，跳到的小怪 10 秒移速 ×2（封顶 140，mech_foes）。
## 空洞雪祀：场上 2 棵族树，链的最后一跳附近有树就跳树，树腐化 20 秒、每 8 秒刷 3 只躯壳。
## 移动：ai ranged 保持 220–300；队长贴近 160 内「踏雪」跳开 280（冷却 4）；每 10 秒主动换位跳 ≥320，落地溅 8 粒雪（§12.4）。寒冷：命中 +30（cold_add）。
## 招：一幕 A 寒链·弹射 ② / B 风雪·斜飘 ③ / C 霜陷·冰晶 ① / D 冰柱寒链 ④；二幕加 E 寒灾（波动雪带）/ F 踏雪·收屑 ②；空洞加 G 虚无道标 ② 三角，冷却 ×0.9。
## 持续压力「风向」：场上一直有风，每 12 秒换方向；雪祀自己的弹顺风偏 30 px/秒（B / E 的雪按风向飘）。
## 常驻弹幕（11-26，docs/392 §17）：每 2.2 秒（二幕 1.8）轮流「风雪幕」（上风侧整排雪顺风吹过队长）/「雪旋」（螺旋雪流）。
## 出招组（每幕 2）：一幕「寒链」A→C→A、「冰柱」B→D；二幕「寒灾」E→F、「踏雪」F→B→A；空洞二幕「踏雪」换「道标」G→E→A。
## 画面占位；未做：逆风 −10% 移速、冻地减速、雪带推人 30 px（要动公共移动代码，留给实装正式版时一起接）。
extends "res://scripts/enemies/bosses/sami/sami_boss.gd"


func _hol(e: Dictionary) -> bool:
	return e.type == "shaman2"


func _wind(e: Dictionary) -> Vector2:
	return Vector2.from_angle(float(e.get("wind_a", 0.0)))


func step(e: Dictionary, dt: float, dir: Vector2, dist: float, ready: bool, _mate) -> void:
	tick(e, dt)
	e.cd_k = 0.9 if _hol(e) else 1.0
	# 风向：每 12 秒换（先朝队长那边偏一点，免得一直从同一侧来）
	if g.t >= float(e.get("wind_t", 0.0)):
		e.wind_t = g.t + 12.0
		e.wind_a = (g.ppos - center(e)).angle() + PI * 0.5 + float(int(g.t) % 4) * PI * 0.5
	var wv: Vector2 = _wind(e) * 30.0 * dt
	for b in g.ebullets:
		if b.life > 0.0 and int(b.get("source_id", -1)) == int(e.id) and float(b.get("hold", 0.0)) <= 0.0:
			b.pos += wv
	_bands(e)
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
		later(e, 0.6, func(): ring(e, e.pos, 8, 140.0, 1, 0.06, [], g.t))
	# 馈赠
	if float(e.get("gift_cd", 0.0)) == 0.0:
		e.gift_cd = g.t + 6.0
	if ready and g.t >= float(e.gift_cd) and e.get("balls", []).is_empty():
		e.gift_cd = g.t + 15.0
		_gift(e)
	_balls(e, dt)
	_flurry(e)
	_group_pick(e, ready, dir, dist)


## ---- 常驻压力（11-26 协调人：弹幕密度要高于水月中期 Boss；收拢要从原作长出来，不做四面圆弹收拢）：每 2.2 秒（二幕 1.8）轮流放
## 「风雪幕」：上风侧 360 处横着铺一排 11 片雪（间距 46，空洞 40），整排顺风吹过队长（160/秒）——只从风来的那一面来，躲法是顺着排找缝或绕到排尾；
## 「雪旋」：雪祀身边甩出三股螺旋雪流（每股 5 片、每片晚 0.08 秒、转 25°，空洞四股），出手后照样被风带偏。中弹 7%
func _flurry(e: Dictionary) -> void:
	if e.get("coma", false):
		return
	if not e.has("fl_t"):
		e.fl_t = g.t + 2.5
	if g.t < float(e.fl_t):
		return
	e.fl_t = g.t + (1.8 if act_i(e) >= 1 else 2.2)
	e.fl_n = int(e.get("fl_n", 0)) + 1
	var wv: Vector2 = _wind(e)
	if int(e.fl_n) % 2 == 1:
		var gap: float = 40.0 if _hol(e) else 46.0
		var base: Vector2 = g.ppos - wv * 360.0
		var side: Vector2 = wv.orthogonal()
		var off: float = fmod(float(e.fl_n) * 17.0, gap)
		for k in range(-5, 6):
			shot(e, base + side * (float(k) * gap + off), wv.angle(), 160.0, 0, 0.07, {"hold": 0.5, "life": 3.2})
	else:
		var arms: int = 4 if _hol(e) else 3
		var a0: float = (g.ppos - e.pos).angle() + PI / float(arms)
		for j in 5:
			later(e, 0.08 * j, func():
				for arm in arms:
					shot(e, e.pos, a0 + TAU * arm / float(arms) + deg_to_rad(25.0) * j, 170.0, 1, 0.07, {"life": 2.4}))


## 跳步：按击退写法自推 ln（初速 √(1800·ln)，900/s² 减速）
func _hop(e: Dictionary, d: Vector2, ln: float) -> void:
	e.kb = d.normalized() * sqrt(1800.0 * ln)
	e.kb_self = true
	e.dash_decel = 900.0


## ---- 招式表 [名, 冷却, 最近, 最远, 函数]
func _a() -> Array:
	return ["寒链·弹射", 4.0, 0.0, 9999.0, _a_chain]


func _b() -> Array:
	return ["风雪·斜飘", 7.0, 0.0, 600.0, _b_drift]


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
	var a: Array = [_a(), _b(), _c(), _d()]
	if act_i(e) >= 1:
		a = [_e(), _f()] + a
		if _hol(e):
			a.push_front(_g())
	return a


func all_moves(e: Dictionary) -> Array:
	var a: Array = [_a(), _b(), _c(), _d(), _e(), _f()]
	if _hol(e):
		a.append(_g())
	return a.map(func(m): return [m[0], m[1], 0.0, 9999.0, m[4]])


## 出招组：每 9 秒（空洞 ×0.9）起一组，组里按顺序放（跳过放不出的），组外照常按表挑（同利刃）
func _groups(e: Dictionary) -> Array:
	if act_i(e) < 1:
		return [[_a(), _c(), _a()], [_b(), _d()]]
	return [[_e(), _f()], [_g(), _e(), _a()] if _hol(e) else [_f(), _b(), _a()]]


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


## ---- A 寒链·弹射（②）：3 根寒针（空洞 4 根），间隔 0.6、每根重新瞄准，直线 0.7 / 锁定 0.5（半宽 10，长 560）；
## 命中队长后弹向 160（空洞 200）内最近的一名队友，最多 3 跳（空洞 4 跳），每跳 ×0.85，弹跳路线画靛色细链（离队友远就挨得少）
func _a_chain(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var n: int = 4 if _hol(e) else 3
	for k in n:
		var pct: float = 0.16 * pow(0.85, k)
		later(e, 0.6 * k, func():
			var w := w_line(e, (g.ppos - e.pos).angle(), 560.0, 20.0, 0.7, pct, "寒链·弹射" if k == 0 else "")
			w.cb = func(ww):
				var tip: Vector2 = e.pos + Vector2.from_angle(float(ww.ang)) * minf(560.0, e.pos.distance_to(g.ppos) + 60.0)
				fan(e, tip, float(ww.ang) + PI, PI / 3.0, 5, 150.0, 0, 0.05, {"life": 2.0})
				if g.tele.hits_leader(ww):
					_bounce(e, pct))
	return 0.6 * n + 0.3


func _bounce(e: Dictionary, pct: float) -> void:
	var hop: float = 200.0 if _hol(e) else 160.0
	var jumps: int = 4 if _hol(e) else 3
	var cur: Vector2 = g.ppos
	var used: Dictionary = {}
	var path: Array = [cur]
	var p: float = pct
	for j in jumps:
		var best = null
		var bd: float = hop
		for o in g.squad.ops:
			if o.is_leader or o.pos == Vector2.INF or used.has(o.id):
				continue
			var dd: float = o.pos.distance_to(cur)
			if dd < bd:
				bd = dd
				best = o
		if best == null:
			break
		used[best.id] = true
		cur = best.pos
		path.append(cur)
		p *= 0.85
		later(e, 0.12 * (j + 1), _jolt.bind(e, p))
	if path.size() > 1:
		if not e.has("links"):
			e["links"] = []
		e.links.append({"path": path, "until": g.t + 0.5})


## 弹跳打到队友 = 小队共用生命再挨一下（按队长位置判一个小圈，冲刺无敌照样躲掉）
func _jolt(e: Dictionary, pct: float) -> void:
	g.tele.warn_damage({"shape": "circle", "pos": g.ppos, "r": 40.0, "owner": e, "dmg": pd(e, pct), "act": "lob", "corrode": 0.0, "mv": "寒链·弹射"})


## ---- B 风雪·斜飘（③）：前方 90° r 420 扇区先标 0.8 秒（扇形 + 风向箭头），然后扇区里原地生出一片雪片（中弹），
## 0.4 秒后整片顺风横飘（80/秒，0.8 秒）——往逆风那侧走出扇区就躲开
func _b_drift(e: Dictionary, dir: Vector2, _d: float) -> float:
	var a: float = dir.angle()
	var c: Vector2 = e.pos
	w_cone(e, a, PI / 4.0, 420.0, 0.8, 0.0, "风雪·斜飘")
	later(e, 0.8, func():
		var wa: float = _wind(e).angle()
		var r := 70.0
		var i := 0
		while r <= 420.0:
			var n: int = maxi(2, int(PI * 0.5 * r / 64.0))
			for k in n:
				var aa: float = a + lerpf(-PI / 4.0, PI / 4.0, (float(k) + 0.5 * float(i % 2)) / float(n))
				shot(e, c + Vector2.from_angle(aa) * r, wa, 80.0, 1, 0.12, {"hold": 0.4, "life": 0.8})
			r += 64.0
			i += 1)
	return 1.6


## ---- C 霜陷·冰晶（①）：队长预判位置落圈 r 45（0.9 / 0.64），落地后长出六角冰晶：6 根冰枝（长 70、半宽 8）0.6 秒长满
func _c_crystal(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var p: Vector2 = g.combat.arena_clamp(g.ppos + g.pvel.limit_length(float(g.speed) * 1.5) * 0.3, 60.0)
	var w := w_circle(e, p, 45.0, 0.9, 0.20, "霜陷·冰晶")
	w.cb = func(_ww):
		var a0: float = g.t
		for k in 6:
			w_line(e, a0 + TAU * k / 6.0, 70.0, 16.0, 0.6, 0.06, "", {"lock": false, "pos": p})
		later(e, 0.6, func(): ring(e, p, 12, 150.0, 0, 0.05, [], a0 + PI / 12.0, {"life": 2.4}))
	return 1.2


## ---- D 冰柱寒链（④）：身边 6 根冰柱（大弹）+ 柱间寒链（小弹），组成六边形显形 0.9 秒后向外扩（170/秒，扩到 660）；
## 2 段链断开 = 出口（正对队长一段、背后偏 108° 一段，断口两侧冰柱照样在）
func _d_hex(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var c: Vector2 = e.pos
	var a0: float = (g.ppos - c).angle() - PI / 6.0   # 让一段边的中点正对队长
	var r0 := 60.0
	var life: float = 660.0 / 170.0
	var gap_a: Array = [a0 + PI / 6.0, a0 + PI / 6.0 + PI * 0.6]
	for k in 6:
		var va: float = a0 + TAU * k / 6.0
		var vb: float = a0 + TAU * (k + 1) / 6.0
		var pa: Vector2 = c + Vector2.from_angle(va) * r0
		var pb: Vector2 = c + Vector2.from_angle(vb) * r0
		shot(e, pa, va, 170.0, 2, 0.12, {"hold": 0.9, "life": life})
		var mid: float = (va + vb) * 0.5
		var broken := false
		for ga in gap_a:
			if absf(angle_difference(mid, float(ga))) < PI / 6.0:
				broken = true
		if broken:
			continue
		for j in range(1, 4):
			var q: Vector2 = pa.lerp(pb, float(j) / 4.0)
			var off: Vector2 = q - c
			shot(e, q, off.angle(), 170.0 * off.length() / r0, 0, 0.12, {"hold": 0.9, "life": life})
	return 1.2


## ---- E 寒灾（二幕，波动雪带）：从上风处场边刮进 3 道雪带（宽 90 = 两排中弹，摆幅 40、110/秒、飘 8 秒），每道留 1 个缺口（错位），
## 缺口提前 1.0 秒显形；雪带的弹每帧按正弦改速度（_bands）
func _e_bands(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var wv: Vector2 = _wind(e)
	var nrm: Vector2 = wv.orthogonal()
	var c: Vector2 = g.ppos
	if not e.has("bands"):
		e["bands"] = []
	for k in 3:
		later(e, 1.2 * k, func():
			var gap_i: int = [3, 8, 5][k]
			var ids: Array = []
			for row in 2:
				for i in 13:
					if absi(i - gap_i) <= 1:
						continue
					var p: Vector2 = c - wv * (520.0 + 45.0 * row) + nrm * (float(i) - 6.0 + 0.5 * float(row)) * 64.0
					var n0: int = g.ebullets.size()
					shot(e, p, wv.angle(), 110.0, 1, 0.10, {"hold": 1.0, "life": 8.0})
					if g.ebullets.size() > n0:
						ids.append(g.ebullets[g.ebullets.size() - 1])
			e.bands.append({"bs": ids, "t0": g.t + 1.0, "w": wv, "n": nrm}))
	return 3.6


func _bands(e: Dictionary) -> void:
	if not e.has("bands") or e.bands.is_empty():
		return
	var keep: Array = []
	for bd in e.bands:
		var el: float = g.t - float(bd.t0)
		if el > 8.0:
			continue
		keep.append(bd)
		if el < 0.0:
			continue
		var sway: float = cos(el * 2.2) * 40.0 * 2.2   # 摆幅 40、角频 2.2（约 2.9 秒一摆）
		for b in bd.bs:
			if b.life > 0.0:
				b.vel = bd.w * 110.0 + bd.n * sway
	e.bands = keep


## ---- F 踏雪·收屑（二幕 ②）：沿一条穿过队长身边的直线跳 420（半宽 30，0.8 / 0.6），留 6 个冰脚印；
## 0.6 秒后脚印碎成冰屑，全部飞回雪祀落点（200/秒，飞行线先画 0.6 秒）——别站在脚印和落点之间
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
		for p in prints:
			w_line(e, (land - p).angle(), p.distance_to(land), 20.0, 0.6, 0.0, "", {"lock": false, "pos": p})
		later(e, 0.6, func():
			for p in prints:
				var d: float = p.distance_to(land)
				if d > 8.0:
					shot(e, p, (land - p).angle(), 200.0, 1, 0.08, {"life": d / 200.0}))
	return 1.8


## ---- G 虚无道标（空洞，二幕 ② 三角）：从光环上抛出 3 个道标，落成以队长为心、外接半径 340 的三角（边长约 590），
## 道标之间连寒链：1.0 秒预警（锁定 0.4，链宽 16）后连上，2 秒内再结算一次——三角里面安全
func _g_beacon(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var c: Vector2 = g.ppos
	var a0: float = (e.pos - c).angle()
	var vs: Array = []
	for k in 3:
		vs.append(c + Vector2.from_angle(a0 + TAU * k / 3.0) * 340.0)
	e["beacons"] = {"pts": vs, "until": g.t + 3.2}
	for rep in 2:
		later(e, 1.0 * rep, func():
			for k in 3:
				var p: Vector2 = vs[k]
				var q: Vector2 = vs[(k + 1) % 3]
				w_line(e, (q - p).angle(), p.distance_to(q), 16.0, 1.0, 0.14, "虚无道标" if k == 0 and rep == 0 else "", {"lock": k == 0 and rep == 0, "pos": p}))
	return 2.4


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
	for l in e.get("links", []):
		if float(l.until) > g.t:
			cv.draw_polyline(PackedVector2Array(l.path), Color(ind.r, ind.g, ind.b, 0.8), 2.0)
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
