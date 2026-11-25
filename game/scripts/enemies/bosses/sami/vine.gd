## 纠缠藤蔓（3:30）/ 古老藤蔓（7:00）：docs/393 §2.5–§2.6。主轴「引火」：环境伤害让它脆弱、受伤 ×2.0（on_env，冰爆虫爆炸同样算，mech_foes.env_blast）。
## 纠缠：场上 4 个熔岩口，每 10 秒 2 个依次喷发（① r70，预警 1.2，队长 15%）；喷发时藤蔓在圈里 → 脆弱 10 秒。二幕熔岩口之间连裂缝，沿裂缝烧过去（② 半宽 24）。
## 古老：没有熔岩口；每 12 秒从场边来 3 只「高能源石虫」（占位：染污躯壳带结晶标记；二幕 5 只），死后留结晶 1.0 秒（二幕 1.5）爆开 r60，藤蔓在范围里脆弱 6 秒。
## 招（docs/393 §11.4 + §12.4，11-26）：一幕 A 抽击·荆地 ③ / B 致幻缠绕 ②（S 形路径，每 3 次攻击一次）/ C 落种·食草花 ① / D 缠绕 ④（内收藤圈）；二幕加 E 根网 / F 焚根（脆弱结束自动）；古老加 G 盘根（追踪根），冷却 ×0.9；破土位移、持续压力「藤痕」。画面占位。
extends "res://scripts/enemies/bosses/sami/sami_boss.gd"


func _old(e: Dictionary) -> bool:
	return e.type == "vine2"


func step(e: Dictionary, dt: float, dir: Vector2, dist: float, ready: bool, _mate) -> void:
	tick(e, dt)
	e.cd_k = 0.9 if _old(e) else 1.0
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
	# F 焚根：脆弱结束时（自动、不占出招）抖落燃烧的树皮，在身边落成 6 团火（r30，0.8 / 0.5）
	if e.get("burning", false) and float(e.get("vuln_until", 0.0)) <= g.t:
		e.burning = false
		if act_i(e) >= 1:
			for k in 6:
				w_circle(e, e.pos + Vector2.from_angle(TAU * k / 6.0 + g.t) * 90.0, 30.0, 0.8, 0.10, "焚根" if k == 0 else "", {"lock": false})
	_burrow(e)
	_tick_trail(e, dt)
	_tick_coil(e)
	if e.has("bur_to"):
		return
	pick(e, ready, dir, dist)


func moves(e: Dictionary) -> Array:
	var a: Array = [["抽击·荆地", 4.0, 0.0, 240.0, _a_lash], ["致幻缠绕", 10.0, 0.0, 9999.0, _b_root], ["落种·食草花", 8.0, 0.0, 9999.0, _c_seed], ["缠绕", 9.0, 0.0, 9999.0, _d_coil]]
	if act_i(e) >= 1:
		a = [["根网", 12.0, 0.0, 9999.0, _e_web]] + a
		if _old(e):
			a.push_front(["盘根", 11.0, 0.0, 9999.0, _g_coil])
	return a


func all_moves(e: Dictionary) -> Array:
	var a: Array = [["抽击·荆地", 4.0, 0.0, 9999.0, _a_lash], ["致幻缠绕", 10.0, 0.0, 9999.0, _b_root], ["落种·食草花", 8.0, 0.0, 9999.0, _c_seed], ["缠绕", 9.0, 0.0, 9999.0, _d_coil],
		["根网", 12.0, 0.0, 9999.0, _e_web]]
	if _old(e):
		a.append(["盘根", 11.0, 0.0, 9999.0, _g_coil])
	return a


func _count(e: Dictionary) -> void:
	e["atk_n"] = int(e.get("atk_n", 0)) + 1


## ---- 破土（§12.4 爆发位移，不算招）：每 12 秒钻地 1.0 秒，从队长侧面 280–360 处钻出，钻出圈 r150（1.6 / 1.6）；不选熔岩口 r70 内的落点
func _burrow(e: Dictionary) -> void:
	if not e.has("bur_t"):
		e.bur_t = g.t + 12.0
	if e.has("bur_to"):
		if g.t >= float(e.bur_at):
			e.pos = e.bur_to
			e.erase("bur_to")
			e.invuln = false
		else:
			e.invuln = true
		return
	if g.t < float(e.bur_t) or g.t < float(e.get("busy_t", 0.0)):
		return
	e.bur_t = g.t + 12.0
	var side: Vector2 = (g.ppos - e.pos).orthogonal().normalized() * (1.0 if int(g.t) % 2 == 0 else -1.0)
	var to: Vector2 = g.combat.arena_clamp(g.ppos + side * 320.0, 60.0)
	for v in e.get("vents", []):
		if to.distance_to(v) < 70.0 + 40.0:
			to = g.combat.arena_clamp(g.ppos - side * 320.0, 60.0)
	e.bur_to = to
	e.bur_at = g.t + 1.0
	e.busy_t = g.t + 1.8
	w_circle(e, to, 150.0, 1.6, 0.12, "", {"lock": false})


## ---- 持续压力「藤痕」：走过的路留 6 秒藤痕（减速 0.85、每秒 2%）；熔岩口喷发时相连的藤痕一起着火 2 秒（10%）
func _tick_trail(e: Dictionary, dt: float) -> void:
	if not e.has("vtrail"):
		e["vtrail"] = []
	if g.t >= float(e.get("vt_t", 0.0)):
		e.vt_t = g.t + 0.3
		e.vtrail.append({"pos": e.pos, "until": g.t + 6.0, "fire": 0.0})
	e.vtrail = e.vtrail.filter(func(x): return float(x.until) > g.t)
	for x in e.vtrail:
		if g.ppos.distance_to(x.pos) < 26.0:
			g.combat.slow_leader("vine_trail", 0.3, 0.85)
			e.tr_tick = float(e.get("tr_tick", 0.0)) - dt
			if float(x.fire) > g.t and g.t >= float(e.get("fire_hit_t", 0.0)):
				e.fire_hit_t = g.t + 1.0
				hit_now(e, g.ppos, 1.0, 0.10)
			elif float(e.tr_tick) <= 0.0:
				e.tr_tick = 0.5
				hit_now(e, g.ppos, 1.0, 0.01)
			break
	# 抽击留下的荆棘地（每 0.5 秒 2%）
	if e.has("thorns"):
		e.thorns = e.thorns.filter(func(x): return float(x.until) > g.t)
		for th in e.thorns:
			var dv: Vector2 = g.ppos - th.pos
			if dv.length() < float(th.r) and absf(angle_difference(dv.angle(), float(th.ang))) < deg_to_rad(50.0) and g.t >= float(e.get("thorn_t", 0.0)):
				e.thorn_t = g.t + 0.5
				hit_now(e, g.ppos, 1.0, 0.02)
	# 食草花
	if e.has("flowers"):
		e.flowers = e.flowers.filter(func(f): return float(f.until) > g.t)
		for f in e.flowers:
			if float(f.get("snap", 0.0)) <= 0.0 and g.ppos.distance_to(f.pos) < 50.0:
				f.snap = g.t + 0.7
				var w := w_circle(e, f.pos, 50.0, 0.7, 0.15, "", {"lock": false})
				w.cb = func(_ww): f.until = g.t


## A 抽击·荆地：100°、r170（1.6 / 1.5），扇区地面长出荆棘留 2 秒
func _a_lash(e: Dictionary, dir: Vector2, _d: float) -> float:
	_count(e)
	var w := w_cone(e, dir.angle(), deg_to_rad(50.0), 170.0, 1.6, 0.18, "抽击·荆地", {"track": 0.1})
	w.cb = func(ww):
		if not e.has("thorns"):
			e["thorns"] = []
		e.thorns.append({"pos": ww.pos, "ang": float(ww.ang), "r": 170.0, "until": g.t + 2.0})
	return 1.8


## B 致幻缠绕：每 3 次攻击后一次，根须沿预画的 S 形路径（长 620、半宽 36）钻向队长，钻出处破土
func _b_root(e: Dictionary, _dir: Vector2, _d: float) -> float:
	if int(e.get("atk_n", 0)) < 3:
		return -1.0
	e.atk_n = 0
	var tgt: Vector2 = g.ppos + g.pvel.limit_length(150.0) * 0.3
	var d: Vector2 = tgt - e.pos
	var ln: float = maxf(d.length(), 200.0)
	var fwd: Vector2 = d.normalized()
	var nrm: Vector2 = fwd.orthogonal()
	var prev: Vector2 = e.pos
	var n := 8
	for k in n:
		var u: float = float(k + 1) / float(n)
		var q: Vector2 = e.pos + fwd * minf(620.0, ln + 120.0) * u + nrm * sin(u * TAU) * 80.0
		var w := w_line(e, (q - prev).angle(), prev.distance_to(q) + 6.0, 36.0, 0.9, 0.25, "致幻缠绕" if k == 0 else "", {"lock": k == 0})
		w.pos = prev
		prev = q
	return 1.3


## C 落种·食草花：种荚落地（r50，0.9）长成一朵食草花，4 秒内队长走进去它会抖 0.7 秒再合上（15%）
func _c_seed(e: Dictionary, _dir: Vector2, _d: float) -> float:
	_count(e)
	for k in 3:
		var p: Vector2 = g.ppos + Vector2.from_angle(TAU * k / 3.0 + g.t) * (0.0 if k == 0 else 110.0)
		var w := w_circle(e, p, 50.0, 0.9, 0.0, "落种·食草花" if k == 0 else "", {"lock": k == 0})
		w.cb = func(ww):
			if not e.has("flowers"):
				e["flowers"] = []
			e.flowers.append({"pos": ww.pos, "until": g.t + 4.0, "snap": 0.0})
	return 1.2


## D 缠绕：藤从地下围着队长长出一圈（r320），1.6 秒内往里收；缺口是还没长到的生长前端（宽 50°，以 20°/秒顺着长，提前 0.9 秒标出）
func _d_coil(e: Dictionary, _dir: Vector2, _d: float) -> float:
	_count(e)
	var c: Vector2 = g.ppos
	var ga: float = (e.pos - c).angle() + PI
	var w := w_line(e, ga, 320.0, 40.0, 0.9, 0.0, "缠绕", {"lock": true})
	w.pos = c
	e["coil"] = {"c": c, "ga": ga, "t0": g.t + 0.9, "hit": false}
	return 2.6


## E 根网：6 根主根从脚下蜿蜒爬向场边（到 680，根尖路线提前 1.0 秒画出），根爬过 1 秒后两侧冒刺（宽 20）
func _e_web(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var a0: float = (g.ppos - e.pos).angle()
	for r in 6:
		var a: float = a0 + TAU * r / 6.0
		var prev: Vector2 = e.pos
		for k in 6:
			var u: float = float(k + 1) / 6.0
			var q: Vector2 = e.pos + Vector2.from_angle(a + sin(u * PI * 2.0 + r) * 0.25) * 680.0 * u
			var w := w_line(e, (q - prev).angle(), prev.distance_to(q) + 6.0, 10.0, 1.0 + 0.25 * k, 0.10, "根网" if r == 0 and k == 0 else "", {"lock": r == 0 and k == 0})
			w.pos = prev
			prev = q
	return 2.4


## G 盘根（古老）：古老根系从脚下向队长「走」过来：9 个破土点（r45，0.9 / 0.64），间隔 0.3 秒，每步最多转 30° 朝队长
func _g_coil(e: Dictionary, _dir: Vector2, _d: float) -> float:
	e["coilwalk"] = {"p": e.pos, "a": (g.ppos - e.pos).angle(), "n": 0}
	for k in 9:
		later(e, 0.3 * k, _coil_step.bind(e, k))
	return 3.0


func _coil_step(e: Dictionary, k: int) -> void:
	var cw: Dictionary = e.coilwalk
	var want: float = (g.ppos - (cw.p as Vector2)).angle()
	var da: float = clampf(angle_difference(float(cw.a), want), -deg_to_rad(30.0), deg_to_rad(30.0))
	cw.a = float(cw.a) + da
	cw.p = (cw.p as Vector2) + Vector2.from_angle(float(cw.a)) * 75.0
	w_circle(e, cw.p, 45.0, 0.9, 0.14, "盘根" if k == 0 else "", {"lock": k == 0})


func _tick_coil(e: Dictionary) -> void:
	var co = e.get("coil")
	if not (co is Dictionary) or g.t < float(co.t0):
		return
	var el: float = g.t - float(co.t0)
	if el > 1.6:
		e.erase("coil")
		return
	var r: float = 320.0 * (1.0 - el / 1.6)
	co["r"] = r
	co["gap"] = float(co.ga) + deg_to_rad(20.0) * el
	var dv: Vector2 = g.ppos - co.c
	if not co.hit and absf(dv.length() - r) < 16.0 and absf(angle_difference(dv.angle(), float(co.gap))) > deg_to_rad(25.0):
		co.hit = true
		hit_now(e, g.ppos, 1.0, 0.12)


## 熔岩口喷发：2 个依次（间隔 0.6），① r70 预警 1.2；二幕再沿相邻两口之间的裂缝烧一道 ②
func _erupt(e: Dictionary) -> void:
	var vs: Array = e.vents
	var i0: int = int(g.t) % vs.size()
	for k in 2:
		var p: Vector2 = vs[(i0 + k * 2) % vs.size()]
		later(e, 0.6 * k, func():
			var w := w_circle(e, p, 70.0, 1.2, 0.15, "")
			w.cb = func(_ww):
				for x in e.get("vtrail", []):
					if (x.pos as Vector2).distance_to(p) < 120.0:
						x.fire = g.t + 2.0   # 相连的藤痕一起着火 2 秒
				if g.foe != null:
					g.foe.env_blast(p, 70.0, 10.0))
		if act_i(e) >= 1:
			var q: Vector2 = vs[(i0 + k * 2 + 1) % vs.size()]
			later(e, 0.6 * k + 1.2, func():
				var w2 := w_line(e, (q - p).angle(), p.distance_to(q), 48.0, 1.0, 0.15, "", {"pos": p, "lock": true})
				w2.cb = func(_ww):
					if g.foe != null:
						g.foe.env_blast(p.lerp(q, 0.5), p.distance_to(q) * 0.5, 10.0))


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


func draw(e: Dictionary, cv) -> void:
	for p in e.get("vents", []):
		cv.draw_circle(p, 22.0, Color(0.9, 0.35, 0.1, 0.55))
		cv.draw_arc(p, 70.0, 0.0, TAU, 28, Color(0.9, 0.4, 0.1, 0.25), 1.5)
