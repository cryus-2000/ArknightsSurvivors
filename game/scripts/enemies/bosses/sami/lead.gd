## 「木裂」埃克提尔尼尔（结局二 直至冬夜降临）：docs/393 §3.2。追击型近战，一直朝队长走（spd 66）；主轴「停驻」：
## 场上 4 个停驻点，他不在泯灭时走到 30 内就停 2.5 秒、受伤 ×1.6，该点 12 秒后重亮。二幕停驻点冻住，队长先跑过点亮（5 秒有效）；三幕只剩 3 个，
## 每 6 秒的霜息会把 120 内点亮的重新冻住；末段（10% 以下）停驻点全碎，他连续短距狂奔、每段后喘息 1.5 秒受伤 ×1.4。
## 【自我泯灭】过 70% / 40% / 10% 卡点时各一次：3 段折线狂奔（② 0.6 秒 + 冲刺，20%），期间受伤 ×0.2；进出各一次寒冷脉冲（r120，8%，寒冷 +40），结束召 2 只木裂战士。
## 招：一幕 劈斩 ③ / 霜息 ① / 掷击 ② / 冬夜环 ④；二幕 踏冰三连 ② / 寒裂 / 霜刃扇 ③ / 霜锁 ①；三幕 雪崩冲 ② / 长冬 / 连息 ① / 碎冰扇 ③；末段 泯灭冲 ② / 坍缩回响 ④。
extends "res://scripts/enemies/bosses/sami/sami_boss.gd"

func step(e: Dictionary, dt: float, dir: Vector2, dist: float, ready: bool, _mate) -> void:
	tick(e, dt)
	var c: Vector2 = center(e)
	if not e.has("stops"):
		e["stops"] = []
		for k in 4:
			e.stops.append({"pos": c + Vector2.from_angle(TAU * k / 4.0 + PI / 4.0) * 230.0, "next": 0.0, "lit": 0.0, "gone": false})
	var ai: int = act_i(e)
	if ai >= 2 and e.stops.size() > 3:
		e.stops[3].gone = true
	# 停驻
	if float(e.get("annihil_t", 0.0)) <= g.t and ai < 3:
		for s in e.stops:
			if s.gone:
				continue
			if ai >= 1 and g.ppos.distance_to(s.pos) < 40.0:
				s.lit = g.t + 5.0
			var on: bool = g.t >= float(s.next) and (ai == 0 or float(s.lit) > g.t)
			if on and e.pos.distance_to(s.pos) < 30.0 + float(e.r):
				s.next = g.t + 12.0
				s.lit = 0.0
				e.channel = 2.5
				g.combat.start_break(e, 2.5)
				vuln(e, 2.5, 1.6 / maxf(0.01, Bal.v("boss/break_mult", 1.4)))
	if e.get("channel", 0.0) > 0.0:
		e.channel = maxf(0.0, e.channel - dt)
	# 霜息每 6 秒（三幕会冻住 120 内点亮的停驻点）
	if ready and g.t >= float(e.get("breath_t", 0.0)) and ai < 3:
		e.breath_t = g.t + 6.0
		_breath(e)
	pick(e, ready and float(e.get("annihil_t", 0.0)) <= g.t, dir, dist)


func moves(e: Dictionary) -> Array:
	match act_i(e):
		0:
			return [["劈斩", 3.5, 0.0, 150.0, _cleave], ["冬夜环", 8.0, 0.0, 480.0, _ring], ["掷击", 6.0, 120.0, 600.0, _throw]]
		1:
			return [["寒裂", 10.0, 0.0, 480.0, _shatter], ["踏冰三连", 9.0, 0.0, 420.0, _tri], ["霜锁", 9.0, 0.0, 9999.0, _lock], ["霜刃扇", 7.0, 0.0, 520.0, _blade_fan]]
		2:
			return [["长冬", 14.0, 0.0, 9999.0, _winter], ["雪崩冲", 10.0, 100.0, 600.0, _avalanche], ["连息", 11.0, 0.0, 200.0, _breaths], ["碎冰扇", 9.0, 0.0, 480.0, _ice_fans]]
	return [["坍缩回响", 8.0, 0.0, 9999.0, _echo], ["泯灭冲", 4.0, 0.0, 9999.0, _sprint4]]


func all_moves(_e: Dictionary) -> Array:
	return [["劈斩", 3.5, 0.0, 9999.0, _cleave], ["霜息", 6.0, 0.0, 9999.0, _m_breath], ["掷击", 6.0, 0.0, 9999.0, _throw], ["冬夜环", 8.0, 0.0, 9999.0, _ring],
		["踏冰三连", 9.0, 0.0, 9999.0, _tri], ["寒裂", 10.0, 0.0, 9999.0, _shatter], ["霜刃扇", 7.0, 0.0, 9999.0, _blade_fan], ["霜锁", 9.0, 0.0, 9999.0, _lock],
		["雪崩冲", 10.0, 0.0, 9999.0, _avalanche], ["长冬", 14.0, 0.0, 9999.0, _winter], ["连息", 11.0, 0.0, 9999.0, _breaths], ["碎冰扇", 9.0, 0.0, 9999.0, _ice_fans],
		["泯灭冲", 4.0, 0.0, 9999.0, _sprint4], ["坍缩回响", 8.0, 0.0, 9999.0, _echo], ["自我泯灭", 99.0, 0.0, 9999.0, _m_annihil]]


func base_taken(e: Dictionary) -> float:
	return 0.2 if float(e.get("annihil_t", 0.0)) > g.t else 1.0


func _m_breath(e: Dictionary, _a: Vector2, _b: float) -> float:
	_breath(e)
	return 1.4


func _m_annihil(e: Dictionary, _a: Vector2, _b: float) -> float:
	_annihilate(e)
	return 3.2


## 过卡点 = 【自我泯灭】
func on_gate(e: Dictionary) -> void:
	_annihilate(e)


func _annihilate(e: Dictionary) -> void:
	e.annihil_t = g.t + 3.0
	e.move_name = "自我泯灭"
	e.move_t = g.t
	_pulse(e)
	for k in 3:
		later(e, 0.15 + 1.0 * k, func(): w_stab(e, (g.ppos - e.pos).angle(), clampf(e.pos.distance_to(g.ppos) + 60.0, 120.0, 260.0), 52.0, 0.6, 0.20, ""))
	later(e, 3.0, func():
		_pulse(e)
		summon(e, "warrior", 2, 50.0))
	if act_i(e) >= 3:
		for s in e.stops:
			s.gone = true


func _pulse(e: Dictionary) -> void:
	var w := w_self(e, 120.0, 1.4, 0.08, "")
	w.cb = func(_ww):
		if g.ppos.distance_to(e.pos) < 132.0:
			var c = g.mech("cold")
			if c != null:
				c.add_cold(float(D.ENEMIES[e.type].get("cold_pulse", 40.0)), true)


## 霜息：自身圈 r120（1.4 秒），8% + 寒冷，外沿溅 10 发小圆弹；三幕冻住 120 内点亮的停驻点
func _breath(e: Dictionary) -> void:
	var w := w_self(e, 120.0, 1.4, 0.08, "霜息")
	w.cb = func(_ww):
		ring(e, e.pos, 10, 130.0, 0, 0.06)
		if g.ppos.distance_to(e.pos) < 132.0:
			var c = g.mech("cold")
			if c != null:
				c.add_cold(float(D.ENEMIES[e.type].get("cold_pulse", 40.0)), true)
		if act_i(e) >= 2:
			for s in e.stops:
				if s.pos.distance_to(e.pos) < 120.0:
					s.lit = 0.0


func _cleave(e: Dictionary, dir: Vector2, _d: float) -> float:
	var w := w_cone(e, dir.angle(), PI / 3.0, 120.0, 1.2, 0.18, "劈斩", {"track": 0.4})
	w.cb = func(ww): fan(e, e.pos, float(ww.ang), PI / 3.0, 6, 200.0, 0, 0.08)
	e.channel = 1.2
	return 1.4


func _throw(e: Dictionary, dir: Vector2, d: float) -> float:
	var ln: float = clampf(d + 40.0, 200.0, 520.0)
	var w := w_line(e, dir.angle(), ln, 52.0, 0.8, 0.16, "掷击", {"track": 0.3})
	w.cb = func(ww):
		var tip: Vector2 = e.pos + Vector2.from_angle(float(ww.ang)) * ln
		fan(e, tip, float(ww.ang), 0.5, 5, 260.0, 0, 0.10)
	return 1.0


func _ring(e: Dictionary, _dir: Vector2, _d: float) -> float:
	ring(e, e.pos, 24, 170.0, 1, 0.13, gaps_at(e.pos), 0.0, {"hold": 0.9})
	return 1.2


func _tri(e: Dictionary, _dir: Vector2, _d: float) -> float:
	for k in 3:
		later(e, 0.6 * k, func():
			var w := w_stab(e, (g.ppos - e.pos).angle(), 140.0, 52.0, 0.6, 0.15, "踏冰三连" if k == 0 else "")
			w.cb = func(ww): later(e, 0.25, func(): ring(e, e.pos, 8, 150.0, 0, 0.06)))
	return 2.4


func _shatter(e: Dictionary, _dir: Vector2, _d: float) -> float:
	e.move_name = "寒裂"
	e.move_t = g.t
	var pts: Array = []
	for i in 16:
		pts.append(e.pos + Vector2.from_angle(TAU * i / 16.0) * 90.0)
		shot(e, e.pos, TAU * i / 16.0, 225.0, 0, 0.12, {"life": 0.4, "hold": 0.6})
	later(e, 1.5, func():
		for p in pts:
			shot(e, p, (g.ppos - p).angle(), 230.0, 0, 0.12))
	return 1.8


func _blade_fan(e: Dictionary, dir: Vector2, _d: float) -> float:
	var a: float = dir.angle()
	w_cone(e, a, deg_to_rad(40.0), 200.0, 0.8, 0.0, "霜刃扇")
	for k in 3:
		later(e, 0.8 + 0.3 * k, func(): fan(e, e.pos, a, deg_to_rad(40.0), 7, 280.0, 0, 0.12))
	return 1.8


func _lock(e: Dictionary, _dir: Vector2, _d: float) -> float:
	for k in 3:
		later(e, 0.6 * k, func(): w_circle(e, g.ppos, 45.0, 0.9, 0.14, "霜锁" if k == 0 else "", {"track_pos": "leader", "track": 0.4}))
	return 2.2


func _avalanche(e: Dictionary, dir: Vector2, _d: float) -> float:
	w_stab(e, dir.angle(), 420.0, 60.0, 1.0, 0.25, "雪崩冲", {"track": 0.4})
	return 1.8


func _winter(e: Dictionary, _dir: Vector2, _d: float) -> float:
	e.move_name = "长冬"
	e.move_t = g.t
	_walls4(e)
	return 3.0


func _walls4(e: Dictionary) -> void:
	var c: Vector2 = g.ppos
	for k in 4:
		var nrm: Vector2 = Vector2.from_angle(TAU * k / 4.0)
		var gap_i: int = (k * 3 + 2) % 9
		later(e, 0.5 * k, func():
			for i in 11:
				if absi(i - gap_i - 1) <= 1:
					continue
				shot(e, c + nrm * 380.0 + nrm.orthogonal() * (float(i) - 5.0) * 40.0, (-nrm).angle(), 110.0, 0, 0.13, {"hold": 1.0, "life": 7.0}))


func _breaths(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var rs: Array = [[80.0, 1.0], [110.0, 1.2], [150.0, 1.6]]
	for k in 3:
		var r: float = rs[k][0]
		var du: float = rs[k][1]
		later(e, 0.6 * k, func(): w_self(e, r, du, 0.10, "连息" if k == 0 else ""))
	e.channel = 2.8
	return 3.0


func _ice_fans(e: Dictionary, dir: Vector2, _d: float) -> float:
	var a: float = dir.angle()
	w_cone(e, a, PI / 3.0, 180.0, 0.8, 0.0, "碎冰扇")
	later(e, 0.8, func():
		fan(e, e.pos, a, PI / 3.0, 9, 240.0, 0, 0.12)
		fan(e, e.pos, a + PI, PI / 3.0, 9, 240.0, 0, 0.12))
	later(e, 1.1, func():
		fan(e, e.pos, a + 0.26, PI / 3.0, 9, 240.0, 0, 0.12)
		fan(e, e.pos, a + PI + 0.26, PI / 3.0, 9, 240.0, 0, 0.12))
	return 1.6


## 末段 泯灭冲：4 段短距狂奔，每段后喘息 1.5 秒受伤 ×1.4
func _sprint4(e: Dictionary, _dir: Vector2, _d: float) -> float:
	for k in 4:
		later(e, 2.1 * k, func():
			w_stab(e, (g.ppos - e.pos).angle(), clampf(e.pos.distance_to(g.ppos) + 40.0, 120.0, 240.0), 52.0, 0.6, 0.20, "泯灭冲" if k == 0 else "")
			later(e, 0.6, func(): vuln(e, 1.5, 1.4)))
	return 8.6


func _echo(e: Dictionary, _dir: Vector2, _d: float) -> float:
	ring(e, e.pos, 24, 150.0, 1, 0.13, gaps_at(e.pos, 1), 0.0, {"hold": 1.0, "turn": deg_to_rad(25.0), "life": 6.0})
	ring(e, e.pos, 24, 120.0, 1, 0.13, gaps_at(e.pos, 1), PI / 24.0, {"hold": 1.0, "turn": -deg_to_rad(25.0), "life": 6.0})
	return 1.6


func draw(e: Dictionary, cv) -> void:
	var fxm = g.mech("fx")
	if fxm != null:
		fxm.lead_draw(e)   # 墨绿剥落（docs/401 §14）
		fxm.obj_draw(e)    # 停驻点 = 要去碰的东西：金色描边 + 心跳（docs/142b §1 第 2 条，docs/401 §16）
		return
	var ai: int = act_i(e)
	for s in e.get("stops", []):
		if s.gone:
			continue
		var on: bool = g.t >= float(s.next) and (ai == 0 or float(s.lit) > g.t)
		cv.draw_circle(s.pos, 18.0, Color(1.0, 0.85, 0.4, 0.75) if on else Color(0.6, 0.7, 0.85, 0.45))
		cv.draw_arc(s.pos, 30.0, 0.0, TAU, 20, Color(1.0, 0.85, 0.4, 0.5 if on else 0.15), 2.0)


## 机器人主轴：挑一个能用的停驻点，站到「停驻点在自己和木裂连线上、点后 80」的位置让他走过去；二幕起点没亮先跑过去点亮
func axis_do(e: Dictionary, p: Vector2) -> Vector2:
	if float(e.get("annihil_t", 0.0)) > g.t or act_i(e) >= 3:
		return Vector2.INF
	var ai: int = act_i(e)
	var best = null
	var bd := INF
	for s in e.get("stops", []):
		if s.gone or g.t < float(s.next) - 2.0:
			continue
		var d: float = s.pos.distance_to(p) + s.pos.distance_to(e.pos) * 0.5
		if d < bd:
			bd = d
			best = s
	if best == null:
		return Vector2.INF
	if ai >= 1 and float(best.lit) <= g.t + 1.0:
		return go_to(p, best.pos, 20.0)
	var away: Vector2 = (best.pos - e.pos)
	if away.length() < 1.0:
		return Vector2.INF
	return go_to(p, best.pos + away.normalized() * 80.0, 20.0)


## 不理主轴：绕开停驻点（离任何一个点都保持 120 以上）
func axis_ignore(e: Dictionary, p: Vector2) -> Vector2:
	for s in e.get("stops", []):
		if not s.gone and s.pos.distance_to(p) < 120.0:
			return (p - s.pos).normalized()
	return Vector2.INF
