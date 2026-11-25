## 「木裂」埃克提尔尼尔（结局二 直至冬夜降临）：招式按 docs/393 §11.6（15 招），范围 / 位移按 §12.4 / 359 §2.6 威慑下限。
## 整只的读法：地上的刻痕和冰面——弹都从地面来（斩痕、裂纹、冰面、足迹），他狂奔时撞碎场上的冰柱。
## 追击型近战（移速 90），主轴「停驻」：场上 4 个停驻点，他走到 45 内就停 2.5 秒、「树痕之盔」落地，4 秒内受伤 ×1.5（平时 ×0.5，docs/392 §15.2 A），点 8 秒后重亮；
## 二幕停驻点冻住，队长先跑过点亮（5 秒有效）；三幕只剩 3 个，霜息会把 180 内点亮的重新冻住；末段（10% 以下）停驻点全碎。
## 【自我泯灭】过 70% / 40% / 10% 卡点时各一次（原作）：3 段折线狂奔、期间受伤 ×0.2，进出各一次寒冷脉冲，结束召 2 只木裂战士。
## 招：一幕 树痕劈 ③（含跃斩）/ 霜息 ① / 冰痕 ② / 冬夜 ④；二幕 追迹 ① / 英雄之誓 ② / 横踢冰屑 ③ / 冻土 ①；
## 三幕 树痕阵 ② / 长冬 ①+障碍 / 连息 ① / 劈山 ②；末段 泯灭冲 ②×4 / 坍缩 ①+牵引。画面全部占位，正式特效交 fx-declutter。
extends "res://scripts/enemies/bosses/sami/sami_boss.gd"

const STOP_R := 60.0


func step(e: Dictionary, dt: float, dir: Vector2, dist: float, ready: bool, _mate) -> void:
	tick(e, dt)
	obst_tick(e)
	ambient(e, dt, "shard")
	var c: Vector2 = center(e)
	if not e.has("stops"):
		e["stops"] = []
		for k in 4:
			e.stops.append({"pos": c + Vector2.from_angle(TAU * k / 4.0 + PI / 4.0) * 240.0, "next": 0.0, "lit": 0.0, "gone": false})
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
			if on and e.pos.distance_to(s.pos) < STOP_R + float(e.r):
				s.next = g.t + 6.0
				s.lit = 0.0
				e.channel = 2.5
				e["helm_until"] = g.t + 5.0
				e["brk_len"] = 5.0
				e["break_ring_until"] = g.t + 5.0
				g.combat.start_break(e, 2.5)
	if e.get("channel", 0.0) > 0.0:
		e.channel = maxf(0.0, e.channel - dt)
	# 霜息每 6 秒（三幕会冻住 180 内点亮的停驻点）
	if ready and g.t >= float(e.get("breath_t", 0.0)) and ai < 3:
		e.breath_t = g.t + 6.0
		_breath(e)
	_tick_ice(e, dt)
	_tick_winter(e)
	_tick_pull(e, dt)
	# 他撞上冰柱：撞碎，溅 4 块大冰块
	for o in e.get("obst", []).duplicate():
		if e.pos.distance_to(o.pos) < float(o.r) + float(e.r) and e.get("kb", Vector2.ZERO).length() > 200.0:
			e.obst.erase(o)
			for k in 4:
				shot(e, o.pos, TAU * k / 4.0 + PI / 4.0, 220.0, 2, 0.08, {"life": 2.5})
	pick(e, ready and float(e.get("annihil_t", 0.0)) <= g.t, dir, dist)


func moves(e: Dictionary) -> Array:
	match act_i(e):
		0:
			return [["树痕劈", 3.5, 0.0, 520.0, _cleave], ["冬夜", 8.0, 0.0, 9999.0, _winter], ["冰痕", 6.0, 120.0, 800.0, _crack]]
		1:
			return [["英雄之誓", 10.0, 0.0, 9999.0, _oath], ["追迹", 9.0, 0.0, 700.0, _track], ["冻土", 9.0, 0.0, 9999.0, _frostland], ["横踢冰屑", 7.0, 0.0, 520.0, _kick],
				["树痕劈", 3.5, 0.0, 520.0, _cleave]]
		2:
			return [["长冬", 14.0, 0.0, 9999.0, _long_winter], ["树痕阵", 12.0, 0.0, 9999.0, _totem], ["连息", 11.0, 0.0, 360.0, _breaths], ["劈山", 9.0, 0.0, 9999.0, _split],
				["树痕劈", 3.5, 0.0, 520.0, _cleave]]
	return [["坍缩", 9.0, 0.0, 9999.0, _collapse], ["泯灭冲", 4.0, 0.0, 9999.0, _sprint4]]


func all_moves(_e: Dictionary) -> Array:
	return [["树痕劈", 3.5, 0.0, 9999.0, _cleave], ["霜息", 6.0, 0.0, 9999.0, _m_breath], ["冰痕", 6.0, 0.0, 9999.0, _crack], ["冬夜", 8.0, 0.0, 9999.0, _winter],
		["追迹", 9.0, 0.0, 9999.0, _track], ["英雄之誓", 10.0, 0.0, 9999.0, _oath], ["横踢冰屑", 7.0, 0.0, 9999.0, _kick], ["冻土", 9.0, 0.0, 9999.0, _frostland],
		["树痕阵", 12.0, 0.0, 9999.0, _totem], ["长冬", 14.0, 0.0, 9999.0, _long_winter], ["连息", 11.0, 0.0, 9999.0, _breaths], ["劈山", 9.0, 0.0, 9999.0, _split],
		["泯灭冲", 4.0, 0.0, 9999.0, _sprint4], ["坍缩", 9.0, 0.0, 9999.0, _collapse], ["自我泯灭", 99.0, 0.0, 9999.0, _m_annihil]]


## 主轴收益（docs/392 §15.2 A「树痕之盔」）：平时 ×0.5，盔落地 4 秒 ×1.5；自我泯灭期间 ×0.2
func base_taken(e: Dictionary) -> float:
	if float(e.get("annihil_t", 0.0)) > g.t:
		return 0.2
	return 2.5 if float(e.get("helm_until", 0.0)) > g.t else 0.3


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
		later(e, 0.15 + 1.0 * k, func(): w_stab(e, (g.ppos - e.pos).angle(), clampf(e.pos.distance_to(g.ppos) + 80.0, 200.0, 460.0), 60.0, 0.6, 0.20, ""))
	later(e, 3.0, _annihil_end.bind(e))
	if act_i(e) >= 3:
		for s in e.stops:
			s.gone = true


func _annihil_end(e: Dictionary) -> void:
	_pulse(e)
	summon(e, "warrior", 2, 50.0)


func _cold_hit(e: Dictionary, r: float) -> void:
	if g.ppos.distance_to(e.pos) < r + 12.0:
		var c = g.mech("cold")
		if c != null:
			c.add_cold(float(D.ENEMIES[e.type].get("cold_pulse", 40.0)), true)


func _pulse(e: Dictionary) -> void:
	var w := w_self(e, 180.0, 1.9, 0.08, "")
	w.cb = func(_ww): _cold_hit(e, 180.0)


## ---- 一幕
## 霜息：自身 r180（1.9 / 1.8），8% + 寒冷；三幕冻住 180 内点亮的停驻点
func _breath(e: Dictionary) -> void:
	var w := w_self(e, 180.0, 1.9, 0.08, "霜息")
	w.cb = func(_ww):
		_cold_hit(e, 180.0)
		if act_i(e) >= 2:
			for s in e.stops:
				if s.pos.distance_to(e.pos) < 180.0:
					s.lit = 0.0


## 树痕劈：120° r200（1.9 / 1.8），劈完在扇区地面刻 3 道树痕（各到 420），0.8 秒后裂开 10%；队长离他 >260 时先跃进 240（跃斩，0.45 秒）
func _cleave(e: Dictionary, dir: Vector2, d: float) -> float:
	var lead_t := 0.0
	if d > 260.0:
		w_stab(e, dir.angle(), 240.0, 40.0, 0.45, 0.06, "", {"track": 0.1})
		lead_t = 0.55
	later(e, lead_t, _cleave_go.bind(e))
	e.channel = 2.0 + lead_t
	return 2.1 + lead_t


func _cleave_go(e: Dictionary) -> void:
	var w := w_cone(e, (g.ppos - e.pos).angle(), PI / 3.0, 200.0, 1.9, 0.18, "树痕劈", {"track": 0.1})
	w.cb = func(ww):
		for s in [-0.6, 0.0, 0.6]:
			var a: float = float(ww.ang) + s
			var m := w_line(e, a, 420.0, 14.0, 0.8, 0.10, "", {"lock": false})
			m.pos = e.pos


## 冰痕：朝队长跺脚，一道冰裂贴地向前跑 720，沿途分出 4 道支裂（宽 28）
func _crack(e: Dictionary, dir: Vector2, _d: float) -> float:
	var a: float = (g.ppos + g.pvel.limit_length(150.0) * 0.3 - e.pos).angle()
	w_line(e, a, 720.0, 14.0, 0.8, 0.16, "冰痕", {"track": 0.4})
	for k in 4:
		var p: Vector2 = e.pos + Vector2.from_angle(a) * (160.0 + 130.0 * k)
		var s: float = 1.0 if k % 2 == 0 else -1.0
		later(e, 0.15 * k, _branch.bind(e, p, a + s * 0.6, 220.0))
	return 1.2


func _branch(e: Dictionary, p: Vector2, a: float, ln: float) -> void:
	var w := w_line(e, a, ln, 14.0, 0.8, 0.16, "", {"lock": false})
	w.pos = p


## 冬夜：寒冷光环外扩成冰雾前沿（170 px/秒，到 700）；停驻点方向不起雾 = 出口（提前 0.9 秒标出）
func _winter(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var gaps: Array = []
	var first := true
	for s in e.stops:
		if s.gone:
			continue
		var a: float = (s.pos - e.pos).angle()
		gaps.append(a)
		var w := w_line(e, a, 700.0, 40.0, 0.9, 0.0, "冬夜" if first else "", {"lock": first})
		w.pos = e.pos
		first = false
	if first:
		w_self(e, 80.0, 0.9, 0.0, "冬夜")
	e["winter"] = {"t0": g.t + 0.9, "c": e.pos, "gaps": gaps, "hit": false}
	return 1.4


func _tick_winter(e: Dictionary) -> void:
	var wi = e.get("winter")
	if not (wi is Dictionary) or g.t < float(wi.t0):
		return
	var r: float = (g.t - float(wi.t0)) * 170.0
	if r > 700.0:
		e.erase("winter")
		return
	wi["r"] = r
	var dv: Vector2 = g.ppos - wi.c
	if wi.hit or absf(dv.length() - r) > 14.0:
		return
	for a in wi.gaps:
		if absf(angle_difference(dv.angle(), float(a))) < atan2(50.0, maxf(40.0, r)):
			return
	wi.hit = true
	hit_now(e, g.ppos, 1.0, 0.13, {"chill": 1.0})


## ---- 二幕
## 追迹：三段突进（各 280、≥720 px/秒），每步留冰足迹；1 秒后足迹按走过的顺序冒冰刺（r30，0.9 / 0.5）
func _track(e: Dictionary, _dir: Vector2, _d: float) -> float:
	for k in 3:
		later(e, 0.75 * k, _track_step.bind(e, k))
	return 3.2


func _track_step(e: Dictionary, k: int) -> void:
	var a: float = (g.ppos + g.pvel.limit_length(150.0) * 0.3 - e.pos).angle()
	var from: Vector2 = e.pos
	var w := w_stab(e, a, 280.0, 40.0, 0.5, 0.15, "追迹" if k == 0 else "", {"track": 0.1})
	w.cb = func(ww):
		for j in 3:
			var p: Vector2 = from + Vector2.from_angle(float(ww.ang)) * (70.0 + 90.0 * j)
			later(e, 0.6 + 0.12 * j, func(): w_circle(e, p, 30.0, 0.9, 0.15, "", {"lock": false}))


## 英雄之誓：他举刃，每个停驻点向他射一道冰线（宽 24，1.0 / 0.5）
func _oath(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var first := true
	for s in e.stops:
		if s.gone:
			continue
		var w := w_line(e, (e.pos - s.pos).angle(), s.pos.distance_to(e.pos), 12.0, 1.0, 0.14, "英雄之誓" if first else "", {"lock": first})
		w.pos = s.pos
		first = false
	e.channel = 1.0
	return -1.0 if first else 1.3


## 冻土：3 个追踪落点（r45，0.9 / 0.64），落地留 3 秒冰面（减速，横踢冰屑的弹源）
func _frostland(e: Dictionary, _dir: Vector2, _d: float) -> float:
	for k in 3:
		later(e, 0.6 * k, _frost_one.bind(e, k == 0))
	return 2.2


func _frost_one(e: Dictionary, first: bool) -> void:
	var w := w_circle(e, g.ppos, 45.0, 0.9, 0.14, "冻土" if first else "", {"track_pos": "leader", "track": 0.26, "lock": first})
	w.cb = func(ww):
		if not e.has("ice"):
			e["ice"] = []
		e.ice.append({"pos": ww.pos, "r": 60.0, "until": g.t + 3.0})


func _tick_ice(e: Dictionary, _dt: float) -> void:
	if not e.has("ice"):
		return
	e.ice = e.ice.filter(func(x): return float(x.until) > g.t)
	for x in e.ice:
		if g.ppos.distance_to(x.pos) < float(x.r):
			g.combat.slow_leader("lead_ice", 0.3, 0.7)
			break


## 横踢冰屑：身前 80°、r420 里地上的冰面被踢碎，碎冰朝外溅（冰面越多弹越密，没冰面就没弹）
func _kick(e: Dictionary, dir: Vector2, _d: float) -> float:
	var a: float = dir.angle()
	var src: Array = (e.get("ice", []) as Array).filter(func(x): return x.pos.distance_to(e.pos) < 420.0 and absf(angle_difference((x.pos - e.pos).angle(), a)) < deg_to_rad(40.0))
	w_cone(e, a, deg_to_rad(40.0), 420.0, 0.8, 0.0, "横踢冰屑", {"track": 0.2})
	later(e, 0.8, _kick_go.bind(e, a, src))
	return 1.4


func _kick_go(e: Dictionary, a: float, src: Array) -> void:
	for x in src:
		e.ice.erase(x)
		for k in 8:
			shot(e, x.pos, a + lerpf(-0.6, 0.6, k / 7.0), 260.0, 2, 0.12, {"life": 2.5})


## ---- 三幕
## 树痕阵：以队长为心浮现部落图腾（三道平行刻痕 + 一道斜划，各长 560、宽 24），1.2 秒后整片一起裂开
func _totem(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var c: Vector2 = g.ppos
	var a: float = (c - e.pos).angle()
	var nrm: Vector2 = Vector2.from_angle(a).orthogonal()
	var first := true
	for k in [-1.0, 0.0, 1.0]:
		var p: Vector2 = c + nrm * 110.0 * k - Vector2.from_angle(a) * 280.0
		var w := w_line(e, a, 560.0, 12.0, 1.2, 0.14, "树痕阵" if first else "", {"lock": first})
		w.pos = p
		first = false
	var w2 := w_line(e, a + 0.9, 560.0, 12.0, 1.2, 0.14, "", {"lock": false})
	w2.pos = c - Vector2.from_angle(a + 0.9) * 280.0
	return 1.6


## 长冬：场上 8 处积雪依次冻成冰柱（r50，1.0 / 0.69），立 4 秒挡路；他狂奔撞上会撞碎、溅 4 块大冰块
func _long_winter(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var c: Vector2 = center(e)
	for k in 8:
		var p: Vector2 = c + Vector2.from_angle(TAU * k / 8.0 + 0.3) * (180.0 + 120.0 * (k % 2))
		later(e, 0.15 * k, _pillar.bind(e, p, k == 0))
	return 2.4


func _pillar(e: Dictionary, p: Vector2, first: bool) -> void:
	var w := w_circle(e, p, 50.0, 1.0, 0.13, "长冬" if first else "", {"lock": first})
	w.cb = func(_ww): add_obst(e, p, 30.0, 4.0)


## 连息：三次寒冷脉冲由小到大（r140 / 230 / 320，间隔 0.6）
func _breaths(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var rs: Array = [[140.0, 1.6], [230.0, 2.4], [320.0, 3.3]]
	for k in 3:
		var r: float = rs[k][0]
		var du: float = rs[k][1]
		later(e, 0.6 * k, func():
			var w := w_self(e, r, du, 0.10, "连息" if k == 0 else "")
			later(e, du, func(): ring(e, e.pos, 16 + 8 * k, 170.0, 1, 0.08, gaps_at(e.pos), 0.0, {"life": 3.0}))   # 脉冲外沿溅冰屑（11-26 加密）
			w.cb = func(_ww): _cold_hit(e, r))
	e.channel = 4.6
	return 4.6


## 劈山：双手一劈，前后各刻一道长树痕（各 720、半宽 36，1.0 / 0.5）
func _split(e: Dictionary, dir: Vector2, _d: float) -> float:
	var a: float = dir.angle()
	w_line(e, a, 720.0, 36.0, 1.0, 0.18, "劈山", {"track": 0.5})
	w_line(e, a + PI, 720.0, 36.0, 1.0, 0.18, "", {"track": 0.0, "lock": false})
	e.channel = 1.0
	return 1.4


## ---- 末段
## 泯灭冲：四段狂奔（每段 460、≥700 px/秒，0.7 / 0.55，半宽 30），每段落点寒冷脉冲 8%，段后喘 1.2 秒（受伤 ×1.4）
func _sprint4(e: Dictionary, _dir: Vector2, _d: float) -> float:
	for k in 4:
		later(e, 1.9 * k, _sprint_one.bind(e, k))
	return 7.8


func _sprint_one(e: Dictionary, k: int) -> void:
	var w := w_stab(e, (g.ppos - e.pos).angle(), 460.0, 30.0, 0.7, 0.20, "泯灭冲" if k == 0 else "", {"track": 0.15})
	w.cb = func(_ww):
		later(e, 0.55, func():
			w_self(e, 120.0, 0.6, 0.08, "", {"lock": false})
			ring(e, e.pos, 14, 180.0, 1, 0.08, gaps_at(e.pos), 0.0, {"hold": 0.6, "life": 3.0})
			vuln(e, 1.2, 1.4))


## 坍缩：场边 3 个坍缩点同时把队长往里吸（40 px/秒，3 秒），坍缩点本身 r60 伤人
func _collapse(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var c: Vector2 = center(e)
	var ar: float = float(D.ENEMIES[e.type].get("arena_r", 520.0))
	var pts: Array = []
	var a0: float = (g.ppos - c).angle()
	for k in 3:
		pts.append(c + Vector2.from_angle(a0 + TAU * k / 3.0 + 0.5) * ar * 0.85)
	var first := true
	for p in pts:
		w_circle(e, p, 60.0, 1.0, 0.15, "坍缩" if first else "", {"lock": first})
		first = false
	e["pull"] = {"pts": pts, "t0": g.t, "t1": g.t + 3.0}
	return 1.6


func _tick_pull(e: Dictionary, dt: float) -> void:
	var pl = e.get("pull")
	if not (pl is Dictionary):
		return
	if g.t >= float(pl.t1):
		e.erase("pull")
		return
	var best: Vector2 = pl.pts[0]
	for p in pl.pts:
		if p.distance_to(g.ppos) < best.distance_to(g.ppos):
			best = p
	if best.distance_to(g.ppos) > 70.0:
		g.ppos += (best - g.ppos).normalized() * 40.0 * dt


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
		cv.draw_arc(s.pos, STOP_R, 0.0, TAU, 24, Color(1.0, 0.85, 0.4, 0.5 if on else 0.15), 2.0)
	for x in e.get("ice", []):
		cv.draw_circle(x.pos, float(x.r), Color(0.75, 0.9, 1.0, 0.3))
	for o in e.get("obst", []):
		cv.draw_circle(o.pos, float(o.r), Color(0.8, 0.92, 1.0, 0.9))
	var wi = e.get("winter")
	if wi is Dictionary and wi.has("r"):
		cv.draw_arc(wi.c, float(wi.r), 0.0, TAU, 64, Color(0.85, 0.92, 1.0, 0.6), 8.0)
	var pl = e.get("pull")
	if pl is Dictionary:
		for p in pl.pts:
			cv.draw_circle(p, 40.0, Color(0.35, 0.25, 0.5, 0.6))
	if float(e.get("helm_until", 0.0)) > g.t:
		cv.draw_arc(e.pos, float(e.r) + 10.0, 0.0, TAU, 24, Color(1.0, 0.85, 0.4, 0.9), 3.0)


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
