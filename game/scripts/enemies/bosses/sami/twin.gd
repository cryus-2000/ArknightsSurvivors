## 哈兰杜汗（khan）与路加萨尔古斯（lion）（结局四 终始，双 Boss）：docs/393 §3.4。主轴「借刀」：
## 两个王各自每 12 秒蓄一次大招（征服 / 敕令：① 大圈 r160，预警 2.5；三幕 r120）。蓄力开始时队长离施放者 <90 → 圈画在队长身上，否则画在另一个王脚下；
## 落下时另一个王在圈里 → 他晕眩 3.5 秒、受伤 ×1.6；队长在圈里一样挨 30%。一幕两王轮流（相隔 6 秒），二幕同时。
## 决胜：任一个王倒下，另一个移速 ×2、冷却 ×0.6、受伤 ×0.7，大招改瞄队长，每次大招砸完喘息 1.5 秒受伤 ×1.5。
## 卡点暂按各自生命 [0.66, 0.33]（数据 pair_gates sum 合计卡点未做）；哈兰【战意】叠层未做。
extends "res://scripts/enemies/bosses/sami/sami_boss.gd"


func _khan(e: Dictionary) -> bool:
	return e.type == "khan"


func mate_of(e: Dictionary):
	var want: String = str(D.ENEMIES[e.type].get("twin", ""))
	if e.has("twin_id"):
		var m = g.enemies_sys.by_id(int(e.twin_id))
		if m != null and not m.dead:
			return m
		return null
	for m in g.enemies:
		if not m.dead and m.type == want:
			e["twin_id"] = int(m.id)
			return m
	return null


func step(e: Dictionary, dt: float, dir: Vector2, dist: float, ready: bool, _mate) -> void:
	tick(e, dt)
	if int(e.get("fervor", 0)) > 0 and g.t - float(e.get("fervor_t", 0.0)) > 4.0:
		e.fervor = 0
	var m = mate_of(e)
	var decisive: bool = e.has("twin_id") and m == null
	if decisive and not e.get("decisive", false):
		e.decisive = true
		var dc: Dictionary = D.ENEMIES[e.type].get("decisive", {})
		e.spd *= float(dc.get("spd_k", 2.0))
		e.cd_k = float(dc.get("cd_k", 0.6))
		g.vfx.add_alert(e.pos + Vector2(0, -50), "决胜", col(e), 18)
	if not e.has("ult_t"):
		e.ult_t = g.t + (6.0 if _khan(e) else 12.0)
	if ready and g.t >= float(e.ult_t):
		e.ult_t = g.t + 12.0 * float(e.get("cd_k", 1.0))
		if act_i(e) >= 1 and m != null:
			m.ult_t = minf(float(m.get("ult_t", INF)), g.t + 0.05)   # 二幕起两王同时蓄力
		_ult(e, m)
		return
	if act_i(e) >= 1 and _khan(e) and g.t >= float(e.get("call_t", 0.0)):
		e.call_t = g.t + 20.0
		summon(e, "shadow", 4, 70.0)
	var ck: float = float(D.ENEMIES[e.type].get("decisive", {}).get("cd_k", 0.6)) if e.get("decisive", false) else 1.0
	e.cd_k = ck * (1.0 - 0.04 * float(e.get("fervor", 0)))
	pick(e, ready, dir, dist)


## 先倒下的王不掉额外奖励（docs/393 §8 第 7 条，enemies.json first_down_reward false）：另一个王还活着时清掉经验
func on_lethal(e: Dictionary) -> bool:
	if not bool(D.ENEMIES[e.type].get("first_down_reward", true)) and mate_of(e) != null:
		e.xp = 0.0
	return false


## 哈兰【战意】：每打中队长一次 +1 层（最多 10），每层出招冷却 −4%，4 秒没打中清零（mech_foes.on_player_hit 调）
func on_hit_leader(e: Dictionary) -> void:
	if not _khan(e):
		return
	e["fervor"] = mini(10, int(e.get("fervor", 0)) + 1)
	e["fervor_t"] = g.t


func base_taken(e: Dictionary) -> float:
	return float(D.ENEMIES[e.type].get("decisive", {}).get("taken", 0.7)) if e.get("decisive", false) else 1.0


## 征服 / 敕令
func _ult(e: Dictionary, m) -> void:
	var r: float = 120.0 if act_i(e) >= 2 else 160.0
	var at_leader: bool = m == null or e.pos.distance_to(g.ppos) < 90.0
	var p: Vector2 = g.ppos if at_leader else m.pos
	var nm: String = "征服" if _khan(e) else "敕令"
	if e.get("decisive", false):
		nm = "决胜·" + nm
	var w := w_circle(e, p, r, 1.8 if e.get("decisive", false) else 2.5, 0.30, nm)
	pose(e, float(w.dur))
	w.cb = func(_ww):
		var mm = mate_of(e)
		if mm != null and mm.pos.distance_to(p) < r + float(mm.r) * 0.5:
			g.combat.start_break(mm, 3.5)
			vuln(mm, 3.5, 1.6 / maxf(0.01, Bal.v("boss/break_mult", 1.4)))
		if e.get("decisive", false):
			vuln(e, 1.5, 1.5)
	e.channel = 1.0


func moves(e: Dictionary) -> Array:
	var ai: int = act_i(e)
	var a: Array = []
	if _khan(e):
		if ai >= 2:
			a.append(["鞭影", 7.0, 0.0, 160.0, _whip2])
		if ai >= 1:
			a.append(["可汗冲阵", 12.0, 100.0, 9999.0, _charge])
		a += [["鞭扫", 4.0, 0.0, 150.0, _sweep], ["鞭链", 6.0, 100.0, 480.0, _chain]]
	else:
		if ai >= 2:
			a.append(["逆历", 9.0, 0.0, 9999.0, _rev])
		if ai >= 1:
			a.append(["日晷", 11.0, 0.0, 9999.0, _dial])
		a += [["历法环", 8.0, 0.0, 9999.0, _cal_ring], ["瞬身", 8.0, 80.0, 400.0, _blink], ["王令弹幕", 10.0, 0.0, 9999.0, _edict_shots]]
	if ai >= 2:
		a.push_front(["流沙", 14.0, 0.0, 9999.0, _sand])
	return a


func all_moves(e: Dictionary) -> Array:
	var a: Array
	if _khan(e):
		a = [["鞭扫", 4.0, 0.0, 9999.0, _sweep], ["鞭链", 6.0, 0.0, 9999.0, _chain], ["可汗冲阵", 12.0, 0.0, 9999.0, _charge], ["鞭影", 7.0, 0.0, 9999.0, _whip2]]
	else:
		a = [["历法环", 8.0, 0.0, 9999.0, _cal_ring], ["瞬身", 8.0, 0.0, 9999.0, _blink], ["王令弹幕", 10.0, 0.0, 9999.0, _edict_shots], ["日晷", 11.0, 0.0, 9999.0, _dial], ["逆历", 9.0, 0.0, 9999.0, _rev]]
	a.append(["流沙", 14.0, 0.0, 9999.0, _sand])
	a.append(["征服" if _khan(e) else "敕令", 12.0, 0.0, 9999.0, func(ee, _a, _b):
		_ult(ee, mate_of(ee))
		return 2.6])
	return a


func _sweep(e: Dictionary, dir: Vector2, _d: float) -> float:
	var w := w_cone(e, dir.angle(), deg_to_rad(50.0), 120.0, 1.1, 0.16, "鞭扫", {"track": 0.4})
	pose(e, 1.1)
	w.cb = func(ww):
		_fx("whip", e.pos, float(ww.ang), deg_to_rad(50.0))
		fan(e, e.pos, float(ww.ang), deg_to_rad(50.0), 6, 200.0, 0, 0.08)
	return 1.3


func _chain(e: Dictionary, dir: Vector2, _d: float) -> float:
	var w := w_line(e, dir.angle(), 360.0, 40.0, 0.8, 0.15, "鞭链", {"track": 0.3})
	pose(e, 0.8)
	w.cb = func(ww):
		_fx("lash", e.pos, float(ww.ang), 360.0)
		ring(e, e.pos + Vector2.from_angle(float(ww.ang)) * 360.0, 8, 150.0, 0, 0.07)
	return 1.0


func _charge(e: Dictionary, _dir: Vector2, _d: float) -> float:
	for k in 3:
		later(e, 0.9 * k, func():
			var w := w_stab(e, (g.ppos - e.pos).angle(), 200.0, 60.0, 0.7, 0.18, "可汗冲阵" if k == 0 else "")
			pose(e, 0.7)
			w.cb = func(_ww): later(e, 0.3, func(): summon(e, "shadow", 2, 40.0)))
	return 2.9


func _whip2(e: Dictionary, dir: Vector2, _d: float) -> float:
	pose(e, 1.1)
	for s in [0.0, PI]:
		var w := w_cone(e, dir.angle() + s, deg_to_rad(45.0), 120.0, 1.1, 0.16, "鞭影" if s == 0.0 else "")
		w.cb = func(ww):
			_fx("whip", e.pos, float(ww.ang), deg_to_rad(45.0))
			fan(e, e.pos, float(ww.ang), deg_to_rad(45.0), 5, 200.0, 0, 0.08)
	return 1.3


func _cal_ring(e: Dictionary, _dir: Vector2, _d: float) -> float:
	pose(e, 0.0)
	_fx("flash", e.pos, 0.0, PI)
	ring(e, e.pos, 24, 160.0, 1, 0.13, gaps_at(e.pos), 0.0, {"hold": 0.9, "turn": deg_to_rad(15.0), "life": 6.0})
	return 1.2


## 瞬身：沿直线瞬移 150 穿过队长所在线，穿过处留 6 发针弹列
func _blink(e: Dictionary, dir: Vector2, _d: float) -> float:
	var a: float = dir.angle()
	var from: Vector2 = e.pos
	var w := w_line(e, a, 300.0, 60.0, 0.8, 0.18, "瞬身", {"track": 0.3})
	pose(e, 0.8)
	w.cb = func(ww):
		_fx("flash", from, float(ww.ang), 0.8)
		var to: Vector2 = from + Vector2.from_angle(float(ww.ang)) * minf(300.0, from.distance_to(g.ppos) + 150.0)
		for k in 6:
			shot(e, from.lerp(to, k / 5.0), float(ww.ang) + PI * 0.5, 140.0, 0, 0.10, {"hold": 0.4})
		e.pos = to
	return 1.1


func _edict_shots(e: Dictionary, _dir: Vector2, _d: float) -> float:
	pose(e, 0.0)
	_fx("flash", e.pos, 0.0, PI)
	ring(e, e.pos, 16, 160.0, 0, 0.11, [], 0.0, {"hold": 0.6})
	later(e, 0.6, func(): aim(e, e.pos, 3, 0.12, 300.0, 0, 0.11))
	return 1.3


func _dial(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var c: Vector2 = e.pos
	e.move_name = "日晷"
	e.move_t = g.t
	_fx("dial", c, 110.0, 0.8)
	pose(e, 0.8)
	for i in 20:
		var p: Vector2 = c + Vector2.from_angle(TAU * i / 20.0) * 110.0
		later(e, 0.8 + 0.12 * i, func(): shot(e, p, (g.ppos - p).angle(), 260.0, 0, 0.12, {"hold": 0.0}))
	return 3.4


func _rev(e: Dictionary, _dir: Vector2, _d: float) -> float:
	pose(e, 0.0)
	_fx("flash", e.pos, 0.0, PI)
	ring(e, e.pos, 24, 150.0, 1, 0.13, gaps_at(e.pos, 1), 0.0, {"hold": 1.0, "turn": deg_to_rad(20.0), "life": 6.0})
	ring(e, e.pos, 24, 120.0, 1, 0.13, gaps_at(e.pos, 1), PI / 24.0, {"hold": 1.0, "turn": -deg_to_rad(20.0), "life": 6.0})
	return 1.6


## 流沙：从自己这一侧推一道沙弹墙（小圆弹），缺口按王错开
func _sand(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var nrm: Vector2 = (e.pos - g.ppos).normalized()
	var c: Vector2 = g.ppos
	var gap_i: int = 2 if _khan(e) else 7
	e.move_name = "流沙"
	pose(e, 0.0)
	e.move_t = g.t
	for i in 11:
		if absi(i - gap_i) <= 1:
			continue
		shot(e, c + nrm * 380.0 + nrm.orthogonal() * (float(i) - 5.0) * 40.0, (-nrm).angle(), 110.0, 0, 0.13, {"hold": 1.0, "life": 7.0})
	return 2.0


## 机器人主轴：哪个王 2.5 秒内要蓄大招，就离他 140 以上（圈画到另一个王脚下）；圈落下前躲出圈交给机器人原来的躲预警
func axis_do(e: Dictionary, p: Vector2) -> Vector2:
	if not e.has("ult_t") or float(e.ult_t) - g.t > 2.5:
		return Vector2.INF
	if e.pos.distance_to(p) < 140.0:
		return (p - e.pos).normalized()
	return Vector2.INF


## 不理主轴：蓄力前贴到施放者身边（圈画在自己身上，另一个王不会被砸）
func axis_ignore(e: Dictionary, p: Vector2) -> Vector2:
	if not e.has("ult_t") or float(e.ult_t) - g.t > 2.5 or mate_of(e) == null:
		return Vector2.INF
	return go_to(p, e.pos, 60.0)
