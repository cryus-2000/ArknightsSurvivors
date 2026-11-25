## 纠缠藤蔓（3:30）/ 古老藤蔓（7:00）：docs/393 §2.5–§2.6。主轴「引火」：环境伤害让它脆弱、受伤 ×2.0（on_env，冰爆虫爆炸同样算，mech_foes.env_blast）。
## 纠缠：场上 4 个熔岩口，每 10 秒 2 个依次喷发（① r70，预警 1.2，队长 15%）；喷发时藤蔓在圈里 → 脆弱 10 秒。二幕熔岩口之间连裂缝，沿裂缝烧过去（② 半宽 24）。
## 古老：没有熔岩口；每 12 秒从场边来 3 只「高能源石虫」（占位：染污躯壳带结晶标记；二幕 5 只），死后留结晶 1.0 秒（二幕 1.5）爆开 r60，藤蔓在范围里脆弱 6 秒。
## 招：一幕 A 抽击 ③ / B 致幻缠绕 ②（每 3 次攻击一次）/ C 落种 ① / D 荆环 ④；二幕加 E 根须网（缝隙墙）/ F 焚根（脆弱结束自动放）；古老加 G 盘根，冷却 ×0.9。
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
	# F 焚根：脆弱结束自动放 12 发小圆弹
	if e.get("burning", false) and float(e.get("vuln_until", 0.0)) <= g.t:
		e.burning = false
		if act_i(e) >= 1:
			ring(e, e.pos, 12, 160.0, 0, 0.10)
	pick(e, ready, dir, dist)


func moves(e: Dictionary) -> Array:
	var a: Array = [["抽击", 4.0, 0.0, 150.0, _a_lash], ["致幻缠绕", 10.0, 0.0, 400.0, _b_root], ["落种", 8.0, 0.0, 9999.0, _c_seed], ["荆环", 9.0, 0.0, 480.0, _d_ring]]
	if act_i(e) >= 1:
		a = [["根须网", 12.0, 0.0, 9999.0, _e_web]] + a
		if _old(e):
			a.push_front(["盘根", 11.0, 0.0, 9999.0, _g_coil])
	return a


func all_moves(e: Dictionary) -> Array:
	var a: Array = [["抽击", 4.0, 0.0, 9999.0, _a_lash], ["致幻缠绕", 10.0, 0.0, 9999.0, _b_root], ["落种", 8.0, 0.0, 9999.0, _c_seed], ["荆环", 9.0, 0.0, 9999.0, _d_ring],
		["根须网", 12.0, 0.0, 9999.0, _e_web]]
	if _old(e):
		a.append(["盘根", 11.0, 0.0, 9999.0, _g_coil])
	return a


func _count(e: Dictionary) -> void:
	e["atk_n"] = int(e.get("atk_n", 0)) + 1


## A 抽击：100° 扇形 r110，预警 1.0，扇边甩 5 发米弹（荆刺）
func _a_lash(e: Dictionary, dir: Vector2, _d: float) -> float:
	_count(e)
	var w := w_cone(e, dir.angle(), deg_to_rad(50.0), 110.0, 1.0, 0.18, "抽击", {"track": 0.3})
	w.cb = func(ww): fan(e, e.pos, float(ww.ang), deg_to_rad(50.0), 5, 190.0, 0, 0.08)
	return 1.2


## B 致幻缠绕：每 3 次攻击后一次，根须沿直线钻向队长 340（半宽 26）；古老改两道 V 形（各半宽 22）
func _b_root(e: Dictionary, dir: Vector2, _d: float) -> float:
	if int(e.get("atk_n", 0)) < 3:
		return -1.0
	e.atk_n = 0
	if _old(e):
		w_line(e, dir.angle() - 0.3, 340.0, 44.0, 0.9, 0.25, "致幻缠绕", {"track": 0.3})
		w_line(e, dir.angle() + 0.3, 340.0, 44.0, 0.9, 0.25, "", {"track": 0.3})
	else:
		w_line(e, dir.angle(), 340.0, 52.0, 0.9, 0.25, "致幻缠绕", {"track": 0.3})
	return 1.1


## C 落种：朝队长附近抛 3 颗种荚（r45，1.0 秒），落地各炸 6 发小圆弹
func _c_seed(e: Dictionary, _dir: Vector2, _d: float) -> float:
	_count(e)
	for k in 3:
		var p: Vector2 = g.ppos + Vector2.from_angle(TAU * k / 3.0 + g.t) * (0.0 if k == 0 else 70.0)
		var w := w_circle(e, p, 45.0, 1.0, 0.12, "落种" if k == 0 else "")
		w.cb = func(_ww): ring(e, p, 6, 150.0, 0, 0.06)
	return 1.2


## D 荆环：22 发米弹，2 个缺口，扩散 150，显形 0.9
func _d_ring(e: Dictionary, _dir: Vector2, _d: float) -> float:
	_count(e)
	ring(e, e.pos, 22, 150.0, 0, 0.12, gaps_at(e.pos), 0.0, {"hold": 0.9})
	return 1.2


## E 根须网：4 道根须墙从四面朝队长推进，每道留 1 个缺口（错位）
func _e_web(e: Dictionary, _dir: Vector2, _d: float) -> float:
	_walls(e, 4, 0.10, 110.0)
	return 3.0


## 缝隙墙（藤蔓 E / 木裂长冬 / 双王流沙共用写法）：每道墙 = 一排小圆弹从队长四周 380 外朝队长平推，留一个缺口
func _walls(e: Dictionary, n: int, pct: float, spd: float) -> void:
	var c: Vector2 = g.ppos
	for k in n:
		var a: float = TAU * k / float(n) + 0.3
		var nrm: Vector2 = Vector2.from_angle(a)
		var gap_i: int = (k * 3 + 2) % 9
		later(e, 0.5 * k, func():
			for i in 11:
				if absi(i - gap_i - 1) <= 1:
					continue
				var p: Vector2 = c + nrm * 380.0 + nrm.orthogonal() * (float(i) - 5.0) * 40.0
				shot(e, p, (-nrm).angle(), spd, 0, pct, {"hold": 0.8, "life": 7.0}))


## G 盘根（古老）：以队长为心 6 个落点圈沿螺旋依次破土（r45，0.9 秒，间隔 0.3），最后一圈在队长当前位置
func _g_coil(e: Dictionary, _dir: Vector2, _d: float) -> float:
	for k in 6:
		later(e, 0.3 * k, func():
			var p: Vector2 = g.ppos if k == 5 else g.ppos + Vector2.from_angle(1.1 * k) * (150.0 - 25.0 * k)
			w_circle(e, p, 45.0, 0.9, 0.14, "盘根" if k == 0 else ""))
	return 2.6


## 熔岩口喷发：2 个依次（间隔 0.6），① r70 预警 1.2；二幕再沿相邻两口之间的裂缝烧一道 ②
func _erupt(e: Dictionary) -> void:
	var vs: Array = e.vents
	var i0: int = int(g.t) % vs.size()
	for k in 2:
		var p: Vector2 = vs[(i0 + k * 2) % vs.size()]
		later(e, 0.6 * k, func():
			var w := w_circle(e, p, 70.0, 1.2, 0.15, "")
			w.cb = func(_ww):
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
