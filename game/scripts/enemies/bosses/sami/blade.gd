## “邪魔的利刃”（3:30）/ “邪魔的利刃”，游荡者（7:00）：docs/392 §6.1 + docs/393 §2.1–§2.2。主轴「裂国度」：
## 它一路在身边铺国度（利刃 r 70、游荡者 r 90，每 4 秒一块；国度里的队员攻速 −50%、挨它的招 ×1.5——mech_foes.player_hit_mult）；
## 二幕起每 12 秒召 3 只染污躯壳；在国度里 / 边缘击杀让裂纹长，6 秒内碎 3 块 → 踉跄 2.5 秒、受伤 ×1.5。游荡者国度连片 220、碎一块相连的裂纹 +50%（mech_kingdom）。
## 招：一幕 A 斩击 ③ / B 投刃 ② / C 国度爆发 ① / D 回旋 ④；二幕加 E 追猎 ② / F 刃雨（图案）；游荡者再加 G 皇帝的猎杀 ①+②，整体冷却 ×0.9。
extends "res://scripts/enemies/bosses/sami/sami_boss.gd"


func _wand(e: Dictionary) -> bool:
	return e.type == "wanderer"


func _kr(e: Dictionary) -> float:
	return 90.0 if _wand(e) else 70.0


func step(e: Dictionary, dt: float, dir: Vector2, dist: float, ready: bool, _mate) -> void:
	tick(e, dt)
	e.cd_k = 0.9 if _wand(e) else 1.0
	var km = kingdoms()
	if km != null and g.t >= float(e.get("lay_t", 0.0)):
		e.lay_t = g.t + 4.0
		km.add(e.pos + Vector2.from_angle(float(int(g.t * 7.0) % 628) / 100.0) * _kr(e) * 0.5, _kr(e), "boss", e, 40.0)
	if act_i(e) >= 1 and g.t >= float(e.get("call_t", 0.0)):
		e.call_t = g.t + 12.0
		summon(e, "husk", 3, 70.0)
	pick(e, ready, dir, dist)


func moves(e: Dictionary) -> Array:
	var a: Array = [
		["斩击", 4.0, 0.0, 150.0, _a_cleave],
		["投刃", 5.0, 120.0, 520.0, _b_throw],
		["国度爆发", 9.0, 0.0, 9999.0, _c_burst],
		["回旋", 7.0, 0.0, 420.0, _d_ring],
	]
	if act_i(e) >= 1:
		a = [["追猎", 8.0, 100.0, 520.0, _e_chase], ["刃雨", 10.0, 0.0, 9999.0, _f_rain]] + a
		if _wand(e):
			a.push_front(["皇帝的猎杀", 12.0, 0.0, 9999.0, _g_hunt])
	return a


func all_moves(e: Dictionary) -> Array:
	var a: Array = [["斩击", 4.0, 0.0, 9999.0, _a_cleave], ["投刃", 5.0, 0.0, 9999.0, _b_throw], ["国度爆发", 9.0, 0.0, 9999.0, _c_burst],
		["回旋", 7.0, 0.0, 9999.0, _d_ring], ["追猎", 8.0, 0.0, 9999.0, _e_chase], ["刃雨", 10.0, 0.0, 9999.0, _f_rain]]
	if _wand(e):
		a.append(["皇帝的猎杀", 12.0, 0.0, 9999.0, _g_hunt])
	return a


## A 斩击：近身 120° 扇形 r100，预警 1.2（docs/393 §2.1 改），挥过时沿两条扇边各甩刃片
func _a_cleave(e: Dictionary, dir: Vector2, _d: float) -> float:
	var w := w_cone(e, dir.angle(), PI / 3.0, 100.0, 1.2, 0.20, "斩击", {"track": 0.4})
	w.cb = func(ww):
		for s in [-1.0, 1.0]:
			fan(e, e.pos, float(ww.ang) + s * PI / 3.0, 0.15, 3, 200.0, 0, 0.10)
	return 1.4


## B 投刃：直线 0.8 秒（半宽 24），结算时沿线放 1 枚大刃片
func _b_throw(e: Dictionary, dir: Vector2, _d: float) -> float:
	var w := w_line(e, dir.angle(), 460.0, 48.0, 0.8, 0.18, "投刃", {"track": 0.3})
	w.cb = func(ww): shot(e, e.pos, float(ww.ang), 340.0, 2, 0.12)
	return 1.0


## C 国度爆发：它的国度依次亮起（间隔 0.15），各自 0.9 秒（游荡者 1.1）后爆开，圈 = 国度半径
func _c_burst(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var km = kingdoms()
	if km == null:
		return -1.0
	var mine: Array = km.list.filter(func(k): return int(k.owner_id) == int(e.id))
	if mine.is_empty():
		return -1.0
	var i := 0
	for k in mine.slice(maxi(0, mine.size() - 8)):
		var kp: Vector2 = k.pos
		var kr: float = k.r
		later(e, 0.15 * i, func(): w_circle(e, kp, kr, 1.1 if _wand(e) else 0.9, 0.15, "国度爆发" if i == 0 else ""))
		i += 1
	return 1.2 + 0.15 * i


## D 回旋：自身为心 24 发中圆弹，2 个缺口，扩散 180，显形 0.9 秒（缺口提前画出）
func _d_ring(e: Dictionary, _dir: Vector2, _d: float) -> float:
	ring(e, e.pos, 24, 180.0, 1, 0.12, gaps_at(e.pos), 0.0, {"hold": 0.9})
	return 1.2


## E 追猎：沿直线冲 300（半宽 30），沿路铺 3 块国度，冲完停 0.8 秒
func _e_chase(e: Dictionary, dir: Vector2, _d: float) -> float:
	var a: float = dir.angle()
	var from: Vector2 = e.pos
	var w := w_stab(e, a, 300.0, 60.0, 0.8, 0.22, "追猎", {"track": 0.3})
	w.cb = func(ww):
		var km = kingdoms()
		if km != null:
			for k in 3:
				km.add(from + Vector2.from_angle(float(ww.ang)) * (60.0 + 100.0 * k), _kr(e), "boss", e, 40.0)
	return 1.6


## F 刃雨：对称环 16 发米弹 ×2 层（第二层错开半格、晚 0.4 秒）+ 3 发针弹自机狙
func _f_rain(e: Dictionary, _dir: Vector2, _d: float) -> float:
	ring(e, e.pos, 16, 170.0, 0, 0.10, [], 0.0, {"hold": 0.6})
	later(e, 0.4, func(): ring(e, e.pos, 16, 170.0, 0, 0.10, [], PI / 16.0, {"hold": 0.6}))
	later(e, 0.8, func(): aim(e, e.pos, 3, 0.12, 300.0, 0, 0.10))
	return 1.4


## G 皇帝的猎杀（游荡者）：队长身边依次落 3 个圈（锁定时刻位置）+ 一道直线收尾
func _g_hunt(e: Dictionary, _dir: Vector2, _d: float) -> float:
	for k in 3:
		later(e, 0.45 * k, func(): w_circle(e, g.ppos, 60.0, 0.9, 0.15, "皇帝的猎杀" if k == 0 else ""))
	later(e, 1.5, func(): w_line(e, (g.ppos - e.pos).angle(), 520.0, 40.0, 0.8, 0.20, ""))
	return 2.6


## 主轴：它的国度碎掉（mech_kingdom._break 通知）；6 秒内碎 3 块 → 踉跄 2.5 秒、受伤 ×1.5
func on_kingdom_break(e: Dictionary) -> void:
	var hist: Array = e.get("kb_hist", [])
	hist.append(g.t)
	hist = hist.filter(func(t): return g.t - float(t) <= 6.0)
	e["kb_hist"] = hist
	if hist.size() >= 3:
		e.kb_hist = []
		g.combat.start_break(e, 2.5)
		vuln(e, 2.5, 1.5 / maxf(0.01, Bal.v("boss/break_mult", 1.4)))
