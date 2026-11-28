## 纠缠藤蔓（3:30）/ 古老藤蔓（7:00）：主轴与数值 docs/393 §2.5–§2.6，招式 §11.4（11-25 差异化定稿），尺寸 §12.4（威慑改数）。
## 主轴「引火」：环境伤害让它脆弱、受伤 ×2.0（on_env，冰爆虫爆炸同样算，mech_foes.env_blast）。
## 纠缠：场上 4 个熔岩口，每 10 秒 2 个依次喷发（① r70，预警 1.2，队长 15%）；喷发时藤蔓在圈里 → 脆弱 10 秒。二幕熔岩口之间连裂缝，沿裂缝烧过去（② 半宽 24）。
## 古老：没有熔岩口；每 12 秒从场边来 3 只「高能源石虫」（占位：染污躯壳带结晶标记；二幕 5 只），死后留结晶 1.0 秒（二幕 1.5）爆开 r60，藤蔓在范围里脆弱 6 秒。
## 招：一幕 A 抽击·荆地 ③ / B 致幻缠绕 ② S 形（每 3 次攻击一次）/ C 落种·食草花 ①（接近触发）/ D 缠绕 ④（根须弧线爬向队长，留荆棘）；常驻「荆刺」地刺 / 藤鞭；
## 二幕加 E 根网（6 根蜿蜒根）/ F 焚根（脆弱结束自动放，身边 6 团火）；古老加 G 盘根（9 步追踪根），冷却 ×0.9。
## 持续压力「藤痕」：走过的路留 6 秒藤痕（每秒 2%）；熔岩口喷发时，连着喷口的藤痕一起着火 2 秒（踩上 10%）。
## 位移「破土」（§12.4）：每 12 秒钻地 1.0 秒，从队长侧面 280–360 处钻出，钻出圈 r 150（1.6 / 1.6）；不选熔岩口 r 内的落点。
## 出招组（每幕 2）：一幕「抽缠」A→B、「落种」C→D→A；二幕「根网」E→B→A、「缠绕」D→C；古老二幕「缠绕」换「盘根」G→E。
## 11-28 表现改版（docs/393 §14.6）：主要表现 = 根须钻地破土，熔岩口喷发为辅。常驻「荆刺」（地刺 / 藤鞭）删掉；B 改地下根追踪后破土；
## D 缠绕的根尖 / 荆棘弹改成往里长的地面根线；E 根网爬过熔岩口会引爆它；G 盘根改两条地下根同时追；破土点离熔岩口 ≤90 也会引爆。
## 弹只剩余波：熔岩喷发溅火星、破土崩土块、抽击 / 食草花甩几根荆刺（_chips）。
## 画面占位；未做：藤痕减速 0.85（要动公共移动代码）。
extends "res://scripts/enemies/bosses/sami/sami_boss.gd"

const LASH_R := 170.0


func _old(e: Dictionary) -> bool:
	return e.type == "vine2"


func step(e: Dictionary, dt: float, dir: Vector2, dist: float, ready: bool, _mate) -> void:
	tick(e, dt)
	e.cd_k = (0.9 if _old(e) else 1.0) * Bal.v("boss/cd_x_" + str(e.type), 1.0)   # 11-26 中期加强：出招间隔倍率
	var c: Vector2 = center(e)
	if not _old(e):
		if not e.has("vents"):
			e["vents"] = []
			for k in 4:
				e.vents.append(c + Vector2.from_angle(TAU * k / 4.0 + 0.4) * 230.0)
			e.vent_t = g.t + 5.0
		if g.t >= float(e.vent_t):
			e.vent_t = g.t + 10.0
			_erupt(e)
	else:
		if not e.has("bug_t"):
			e.bug_t = g.t + 4.0
		if g.t >= float(e.bug_t):
			e.bug_t = g.t + 12.0
			var n: int = 5 if act_i(e) >= 1 else 3
			for k in n:
				var p: Vector2 = g.ppos + Vector2.from_angle(TAU * k / float(n) + g.t) * 420.0
				var m: Dictionary = g.spawner.spawn_enemy("husk", p)
				m["crystal_of"] = int(e.id)
	# F 焚根：脆弱结束自动放（不占出招）
	if e.get("burning", false) and float(e.get("vuln_until", 0.0)) <= g.t:
		e.burning = false
		if act_i(e) >= 1:
			_f_fire(e)
	_trail(e, dt)
	_thorns(e)
	_flowers(e)
	_burrow(e, ready)
	_tick_roots(e)
	_group_pick(e, ready, dir, dist)


## ---- 招式表 [名, 冷却, 最近, 最远, 函数]
func _a() -> Array:
	return ["抽击·荆地", 4.0, 0.0, 220.0, _a_lash]


func _b() -> Array:
	return ["致幻缠绕", 10.0, 0.0, 700.0, _b_root]


func _c() -> Array:
	return ["落种·食草花", 8.0, 0.0, 9999.0, _c_flower]


func _d() -> Array:
	return ["缠绕", 9.0, 0.0, 9999.0, _d_coil]


func _e() -> Array:
	return ["根网", 12.0, 0.0, 9999.0, _e_roots]


func _g() -> Array:
	return ["盘根", 11.0, 0.0, 9999.0, _g_track]


func moves(e: Dictionary) -> Array:
	var a: Array = [_a(), _b(), _c(), _d()]
	if act_i(e) >= 1:
		a = [_e()] + a
		if _old(e):
			a.push_front(_g())
	return a


func all_moves(e: Dictionary) -> Array:
	var a: Array = [_a(), ["致幻缠绕", 10.0, 0.0, 9999.0, _b_root_force], _c(), _d(), _e()]
	if _old(e):
		a.append(_g())
	return a.map(func(m): return [m[0], m[1], 0.0, 9999.0, m[4]])


## 出招组：每 9 秒（古老 ×0.9）起一组，组里按顺序放（跳过放不出的），组外照常按表挑（同利刃）
func _groups(e: Dictionary) -> Array:
	if act_i(e) < 1:
		return [[_a(), _b()], [_c(), _d(), _a()]]
	return [[_e(), _b(), _a()], [_g(), _e()] if _old(e) else [_d(), _c()]]


func _group_pick(e: Dictionary, ready: bool, dir: Vector2, dist: float) -> void:
	if not ready or g.t < float(e.get("busy_t", 0.0)) or e.get("coma", false) or e.get("under", false):
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


func _count(e: Dictionary) -> void:
	e["atk_n"] = int(e.get("atk_n", 0)) + 1


## ---- A 抽击·荆地（③）：100° 扇形 r 170（1.6 / 1.5），横抽一记；抽过的扇区长出荆棘 2 秒（每 0.5 秒站在里面 2%）
func _a_lash(e: Dictionary, dir: Vector2, _d: float) -> float:
	_count(e)
	var w := w_cone(e, dir.angle(), deg_to_rad(50.0), LASH_R, 1.6, 0.22, "抽击·荆地", {"track": 0.1})
	w.cb = func(ww):
		_chips(e, e.pos + Vector2.from_angle(float(ww.ang)) * LASH_R, float(ww.ang), 3, 0.5)   # 11-28：两扇 9 + 8 发荆刺 → 鞭梢甩 3 根
		if not e.has("thorns"):
			e["thorns"] = []
		e.thorns.append({"pos": e.pos, "ang": float(ww.ang), "until": g.t + 2.0, "next": g.t + 0.5})
	return 1.8


func _thorns(e: Dictionary) -> void:
	if not e.has("thorns") or e.thorns.is_empty():
		return
	var keep: Array = []
	for t in e.thorns:
		if float(t.until) <= g.t:
			continue
		keep.append(t)
		if g.t >= float(t.next):
			t.next = g.t + 0.5
			var d: Vector2 = g.ppos - t.pos
			if d.length() < LASH_R and absf(angle_difference(float(t.ang), d.angle())) < deg_to_rad(50.0):
				_hit_at(e, g.ppos, 20.0, 0.02)
	e.thorns = keep


func _hit_at(e: Dictionary, pos: Vector2, r: float, pct: float) -> void:
	g.tele.warn_damage({"shape": "circle", "pos": pos, "r": r, "owner": e, "dmg": pd(e, pct), "act": "lob", "corrode": 0.0, "mv": "藤痕/荆地/焚痕"})


## ---- B 致幻缠绕（11-28 改地下根）：每 3 次攻击后一次。根须钻进地里，地面隆起一条土线朝队长追（每 0.1 秒走 42、最多转 20°），
## 追到离队长 ≤50 或走满 14 步后破土：破土圈 r 60（0.9 / 锁定 0.79），队长 16%（古老 25%，两条根，开局左右各偏 25°）；破土崩 4 块土块；
## 破土点离熔岩口 ≤90 时那个口提前喷发。土线（e.mounds）只画不判
func _b_root(e: Dictionary, dir: Vector2, d: float) -> float:
	if int(e.get("atk_n", 0)) < 3:
		return -1.0
	return _b_root_force(e, dir, d)


func _b_root_force(e: Dictionary, _dir: Vector2, _d: float) -> float:
	e.atk_n = 0
	var a: float = (g.ppos - e.pos).angle()
	if _old(e):
		_root_go(e, e.pos, a - 0.44, 0, 14, 0.25, "致幻缠绕", 20.0, 42.0)
		_root_go(e, e.pos, a + 0.44, 0, 14, 0.25, "", 20.0, 42.0)
	else:
		_root_go(e, e.pos, a, 0, 14, 0.16, "致幻缠绕", 20.0, 42.0)
	return 1.0


## 地下根往前钻一步（B / G 共用）：每步重新朝队长当前位置转（最多 turn 度），步长 stp；钻满 left 步或贴近队长就破土
func _root_go(e: Dictionary, from: Vector2, a: float, i: int, left: int, pct: float, nm: String, turn: float, stp: float) -> void:
	if e.get("dead", false):
		return
	var want: float = (g.ppos - from).angle()
	a += clampf(wrapf(want - a, -PI, PI), -deg_to_rad(turn), deg_to_rad(turn))
	var p: Vector2 = g.combat.arena_clamp(from + Vector2.from_angle(a) * stp, 40.0)
	if not e.has("mounds"):
		e["mounds"] = []
	e.mounds.append({"pos": p, "until": g.t + 1.6})
	if left <= 1 or p.distance_to(g.ppos) <= 50.0:
		_surface(e, p, 60.0, pct, nm)
		return
	later(e, 0.1, _root_go.bind(e, p, a, i + 1, left - 1, pct, nm, turn, stp))


## 破土：r 圈（锁定按公式），到点崩 4 块土块；离熔岩口 ≤90 的那个口提前喷
func _surface(e: Dictionary, p: Vector2, r: float, pct: float, nm: String) -> void:
	var w := w_circle(e, p, r, (r + 12.0) / 105.0 + 0.12, pct, nm, {"lock": nm != ""})
	w.cb = func(_ww):
		_chips(e, p, (p - e.pos).angle(), 4, PI * 0.6)
		_vent_near(e, p, 90.0)


## 点 p 附近 ≤rr 的熔岩口立刻喷一次（不打乱 10 秒一轮的节奏；同一个口 3 秒内只被引一次）
func _vent_near(e: Dictionary, p: Vector2, rr: float) -> void:
	for v in e.get("vents", []):
		if (v as Vector2).distance_to(p) <= rr:
			var key: String = "vt_%d_%d" % [int(v.x), int(v.y)]
			if g.t < float(e.get(key, 0.0)):
				continue
			e[key] = g.t + 3.0
			_erupt_one(e, v)


## 余波：n 根短程荆刺 / 土块 / 火星，沿 ang 两侧 ±spread 散开，飞约 150 就消失
func _chips(e: Dictionary, p: Vector2, ang: float, n: int, spread := 0.6) -> void:
	for i in n:
		var u: float = 0.0 if n == 1 else (float(i) / float(n - 1) * 2.0 - 1.0)
		shot(e, p, ang + u * spread, 150.0, 1, 0.05, {"life": 1.0})


func _tick_roots(e: Dictionary) -> void:
	if e.has("mounds"):
		e.mounds = e.mounds.filter(func(m): return float(m.until) > g.t)


## ---- C 落种·食草花（① 接近触发）：种荚落地（r 50 圈 0.9 秒，只画不伤）长成一朵食草花；4 秒内队长走进 r 50，它抖 0.7 秒再合上（15%）
func _c_flower(e: Dictionary, _dir: Vector2, _d: float) -> float:
	_count(e)
	var p: Vector2 = g.combat.arena_clamp(g.ppos + g.pvel.limit_length(float(g.speed) * 1.5) * 0.4, 60.0)
	var w := w_circle(e, p, 50.0, 0.9, 0.0, "落种·食草花", {"lock": true})
	w.cb = func(_ww):
		if not e.has("flowers"):
			e["flowers"] = []
		e.flowers.append({"pos": p, "until": g.t + 4.0, "armed": false})
	return 1.2


func _flowers(e: Dictionary) -> void:
	if not e.has("flowers") or e.flowers.is_empty():
		return
	var keep: Array = []
	for f in e.flowers:
		if float(f.until) <= g.t and not f.armed:
			continue
		if f.armed:
			if g.t >= float(f.close_t):
				continue
			keep.append(f)
			continue
		keep.append(f)
		if g.combat.ground_d(g.ppos, f.pos) < 50.0 + 10.0:
			f.armed = true
			f.close_t = g.t + 0.7
			var fw := w_circle(e, f.pos, 50.0, 0.7, 0.18, "", {"lock": false})
			var fp: Vector2 = f.pos
			fw.cb = func(_ww): _chips(e, fp, (g.ppos - fp).angle(), 3, 0.7)   # 11-28：合上时 10 发弹圈 → 3 根荆刺
	e.flowers = keep


## ---- D 缠绕（11-28 改地面根线）：队长身边 340 处 5 个地点拱起土包（0.8 秒），每处一条根须破土、沿弯线往队长原位长（4 节 × 85，
## 半宽 18，第 k 节 0.8 + 0.15k 秒结算，12%）；背离藤蔓那一侧不出根（缺口）。不再发根尖 / 荆棘弹
func _d_coil(e: Dictionary, _dir: Vector2, _d: float) -> float:
	_count(e)
	var c: Vector2 = g.ppos
	var ga: float = (c - e.pos).angle()
	var n := 0
	for i in 6:
		var a: float = ga + PI + TAU * float(i) / 6.0 + 0.25 * sin(float(i) * 2.3 + g.t)
		if absf(angle_difference(a, ga)) < deg_to_rad(40.0):
			continue
		var st: Vector2 = c + Vector2.from_angle(a) * 340.0
		w_circle(e, st, 30.0, 0.8, 0.0, "", {"lock": false})
		var sg: float = 1.0 if n % 2 == 0 else -1.0
		var prev: Vector2 = st
		for k in 4:
			var u: float = float(k + 1) / 4.0
			var q: Vector2 = st.lerp(c, u) + (c - st).orthogonal().normalized() * sin(PI * u) * 50.0 * sg
			w_line(e, (q - prev).angle(), prev.distance_to(q) + 6.0, 36.0, 0.8 + 0.15 * k, 0.12, "缠绕" if n == 0 and k == 0 else "", {"pos": prev, "lock": n == 0 and k == 0, "vseg": k, "vn": 4})   # vseg：画面按第几节收细
			prev = q
		n += 1
	return 1.6


## ---- E 根网（二幕）：6 根主根从藤蔓脚下蜿蜒爬向场边（爬到 680，400/秒），根尖路线提前 1.0 秒画出；
## 根爬过一段的同时那段两侧冒刺（每段一条直线，半宽 20 + 根身）
func _e_roots(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var a0: float = (g.ppos - e.pos).angle() + PI / 6.0
	var c: Vector2 = e.pos
	for r in 6:
		var a: float = a0 + TAU * r / 6.0
		var prev: Vector2 = c
		var dist := 0.0
		for k in 4:
			var na: float = a + sin(float(k) * 1.7 + float(r)) * 0.35
			var q: Vector2 = prev + Vector2.from_angle(na) * 170.0
			dist += 170.0
			var w := w_line(e, (q - prev).angle(), 172.0, 48.0, 1.0 + dist / 400.0, 0.10, "根网" if r == 0 and k == 0 else "", {"pos": prev, "lock": r == 0 and k == 0, "vseg": k, "vn": 4})
			var qq: Vector2 = q
			w.cb = func(_ww): _vent_near(e, qq, 90.0)   # 11-28：根爬过熔岩口就引爆它
			prev = q
	return 2.0


## ---- F 焚根（二幕，脆弱结束自动放）：抖落燃烧的树皮，身边落成 6 团火（r 30，0.8 / 0.5）
func _f_fire(e: Dictionary) -> void:
	for k in 6:
		var p: Vector2 = e.pos + Vector2.from_angle(TAU * k / 6.0 + g.t) * (90.0 if k % 2 == 0 else 140.0)
		w_circle(e, p, 30.0, 0.8, 0.10, "", {"lock": false})


## ---- G 盘根（古老，11-28 改）：两条古老根系同时从脚下朝队长钻过来（左右各偏 30°），每条 5 个破土点（r 45，0.9 / 0.64，14%），
## 每步 70、最多转 30°、间隔 0.25–0.35 秒随机；每个破土点崩 2 块土块，离熔岩口 ≤90 会引爆
func _g_track(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var a: float = (g.ppos - e.pos).angle()
	_g_step(e, e.pos, a - 0.52, 0, true)
	_g_step(e, e.pos, a + 0.52, 0, false)
	return 2.2


func _g_step(e: Dictionary, from: Vector2, a: float, k: int, named: bool) -> void:
	if k >= 5 or e.get("dead", false):
		return
	var want: float = (g.ppos - from).angle()
	a += clampf(wrapf(want - a, -PI, PI), -PI / 6.0, PI / 6.0)
	var p: Vector2 = g.combat.arena_clamp(from + Vector2.from_angle(a) * 70.0, 40.0)
	var w := w_circle(e, p, 45.0, 0.9, 0.14, "盘根" if named and k == 0 else "", {"lock": named and k == 0})
	w.cb = func(_ww):
		_chips(e, p, a, 2, 0.8)
		_vent_near(e, p, 90.0)
	later(e, g.rng_enemy.randf_range(0.25, 0.35), _g_step.bind(e, p, a, k + 1, named))


## ---- 持续压力「藤痕」：每 0.3 秒记一个脚印点，留 6 秒；队长踩在藤痕上（距离 <24）每秒 2%；着火的点踩上一次 10%
func _trail(e: Dictionary, dt: float) -> void:
	if not e.has("vtrail"):
		e["vtrail"] = []
	if g.t >= float(e.get("vtr_t", 0.0)) and not e.get("under", false):
		e.vtr_t = g.t + 0.3
		e.vtrail.append({"pos": e.pos, "until": g.t + 6.0, "fire": 0.0})
	e.vtrail = e.vtrail.filter(func(p): return float(p.until) > g.t)
	var on := false
	var burn := false
	for p in e.vtrail:
		if g.combat.ground_d(g.ppos, p.pos) < 24.0:
			on = true
			if float(p.fire) > g.t:
				burn = true
	if on and g.state == g.S.PLAY:
		g.combat.lose_hp(g.max_hp * 0.02 * dt, "vine_trail", true)
	if burn and float(e.get("burn_hit_t", 0.0)) <= g.t:
		e.burn_hit_t = g.t + 1.0
		_hit_at(e, g.ppos, 30.0, 0.10)


## 喷发点 p 半径 r 内的藤痕点着火 2 秒，并沿相连的点（相邻 <60）一路烧过去
func _ignite(e: Dictionary, p: Vector2, r: float) -> void:
	var tr: Array = e.get("vtrail", [])
	var lit: Dictionary = {}
	for i in tr.size():
		if tr[i].pos.distance_to(p) < r:
			lit[i] = true
	var grew := true
	while grew:
		grew = false
		for i in tr.size():
			if lit.has(i):
				continue
			if (lit.has(i - 1) and tr[i].pos.distance_to(tr[i - 1].pos) < 60.0) or (lit.has(i + 1) and tr[i].pos.distance_to(tr[i + 1].pos) < 60.0):
				lit[i] = true
				grew = true
	for i in lit:
		tr[i].fire = g.t + 2.0


## ---- 位移「破土」（§12.4）：每 12 秒钻地 1.0 秒，从队长侧面 280–360 处钻出（不落在熔岩口 r 70+40 内），钻出圈 r 150（1.6 / 1.6，16%）
func _burrow(e: Dictionary, ready: bool) -> void:
	if not e.has("bur_t"):
		e.bur_t = g.t + 12.0
	if e.get("under", false) or g.t < float(e.bur_t) or not ready or g.t < float(e.get("busy_t", 0.0)) or e.get("coma", false):
		return
	e.bur_t = g.t + 12.0
	var side: Vector2 = (g.ppos - e.pos).orthogonal().normalized() * (1.0 if int(g.t) % 2 == 0 else -1.0)
	var to: Vector2 = g.combat.arena_clamp(g.ppos + side * 320.0, 80.0)
	for v in e.get("vents", []):
		if to.distance_to(v) < 110.0:
			to = g.combat.arena_clamp(g.ppos - side * 320.0, 80.0)
			break
	e.under = true
	e.busy_t = g.t + 1.8
	var w := w_circle(e, to, 150.0, 1.6, 0.16, "", {"lock": false})
	later(e, 1.0, func(): e.pos = to)
	w.cb = func(_ww):
		e.under = false
		_chips(e, to, (g.ppos - to).angle(), 4, PI * 0.6)


## 熔岩口喷发：2 个依次（间隔 0.6），① r70 预警 1.2；二幕再沿相邻两口之间的裂缝烧一道 ②；喷发点连着的藤痕一起着火
func _erupt(e: Dictionary) -> void:
	var vs: Array = e.vents
	var i0: int = int(g.t) % vs.size()
	for k in 2:
		var p: Vector2 = vs[(i0 + k * 2) % vs.size()]
		later(e, 0.6 * k, _erupt_one.bind(e, p))
		if act_i(e) >= 1:
			var q: Vector2 = vs[(i0 + k * 2 + 1) % vs.size()]
			later(e, 0.6 * k + 1.2, func():
				var w2 := w_line(e, (q - p).angle(), p.distance_to(q), 48.0, 1.0, 0.15, "", {"pos": p, "lock": true})
				w2.cb = func(_ww):
					if g.foe != null:
						g.foe.env_blast(p.lerp(q, 0.5), p.distance_to(q) * 0.5, 10.0))


## 单个熔岩口喷发：① r70 预警 1.2；喷发溅 6 粒火星（全场唯一的火弹，短程余波），点燃相连藤痕，环境伤害（藤蔓在圈里 → 脆弱）
func _erupt_one(e: Dictionary, p: Vector2) -> void:
	var w := w_circle(e, p, 70.0, 1.2, 0.15, "")
	w.cb = func(_ww):
		_ignite(e, p, 70.0)
		_chips(e, p, (g.ppos - p).angle(), 6, PI)
		if g.foe != null:
			g.foe.env_blast(p, 70.0, 10.0)


## 环境伤害打到它：脆弱 dur 秒、受伤 ×2.0（古老的结晶 6 秒由 on_crystal 传）
func on_env(e: Dictionary, dur: float) -> void:
	vuln(e, dur if not _old(e) else minf(dur, 6.0), 2.0)
	e["burning"] = true


## 古老藤蔓的高能源石虫死了：1.0 秒（二幕 1.5）后结晶爆开 r60，队长 12%，藤蔓在范围里脆弱 6 秒
func on_crystal(e: Dictionary, pos: Vector2) -> void:
	var w := w_circle(e, pos, 60.0, 1.5 if act_i(e) >= 1 else 1.0, 0.12, "")
	w.cb = func(_ww):
		if g.foe != null:
			g.foe.env_blast(pos, 60.0, 6.0)


## 占位画法：熔岩口、藤痕（着火变橙）、荆棘地、食草花（抖动时变红）、钻地时的土包
func draw(e: Dictionary, cv) -> void:
	var fxm = g.mech("fx")
	if fxm != null:
		fxm.vine_draw(e)   # 根须钻地 / 破土坑 / 根簇 / 地面根线 / 熔岩口（11-28，fm_v1；themes/sami/mech/mech_fx.gd）
		for f in e.get("flowers", []):   # 食草花还是占位
			var shake0: float = sin(g.t * 60.0) * 3.0 if f.armed else 0.0
			cv.draw_circle(f.pos + Vector2(shake0, 0), 18.0, Color(0.85, 0.2, 0.25, 0.9) if f.armed else Color(0.5, 0.8, 0.3, 0.85))
		return
	for p in e.get("vents", []):
		cv.draw_circle(p, 22.0, Color(0.9, 0.35, 0.1, 0.55))
		cv.draw_arc(p, 70.0, 0.0, TAU, 28, Color(0.9, 0.4, 0.1, 0.25), 1.5)
	for p in e.get("vtrail", []):
		cv.draw_circle(p.pos, 8.0, Color(1.0, 0.5, 0.1, 0.7) if float(p.fire) > g.t else Color(0.3, 0.45, 0.2, 0.45))
	for t in e.get("thorns", []):
		cv.draw_arc(t.pos, LASH_R * 0.6, float(t.ang) - deg_to_rad(50.0), float(t.ang) + deg_to_rad(50.0), 16, Color(0.35, 0.55, 0.2, 0.6), LASH_R * 0.8)
	for f in e.get("flowers", []):
		var shake: float = sin(g.t * 60.0) * 3.0 if f.armed else 0.0
		cv.draw_circle(f.pos + Vector2(shake, 0), 18.0, Color(0.85, 0.2, 0.25, 0.9) if f.armed else Color(0.5, 0.8, 0.3, 0.85))
		cv.draw_arc(f.pos, 50.0, 0.0, TAU, 24, Color(0.5, 0.8, 0.3, 0.35), 1.5)
	if e.get("under", false):
		cv.draw_circle(e.pos, float(e.r), Color(0.25, 0.18, 0.1, 0.8))
	for m in e.get("mounds", []):   # 地下根拱起的土线（占位）
		cv.draw_circle(m.pos, 14.0, Color(0.35, 0.25, 0.12, 0.75 * clampf(float(m.until) - g.t, 0.0, 1.0)))


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
