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
		_fx_cleave(e, float(ww.ang))
		for s in [-1.0, 1.0]:
			fan(e, e.pos, float(ww.ang) + s * PI / 3.0, 0.15, 3, 200.0, 0, 0.10)
	return 1.4


## B 投刃：直线 0.8 秒（半宽 24），结算时沿线放 1 枚大刃片
func _b_throw(e: Dictionary, dir: Vector2, _d: float) -> float:
	var w := w_line(e, dir.angle(), 460.0, 48.0, 0.8, 0.18, "投刃", {"track": 0.3})
	var fx = sfx()
	if fx != null:
		fx.play("blade_charge", e.pos + Vector2(0, -34), 0.0)   # 原作 smgrd_attack_01_start：暗红团 + 环内收，末段十字星正好落在出手
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
	# 叠在一起的国度只放一个圈（中心距 < 0.9 r 的并掉，docs/401 §4：3–4 个预警叠成一团读不清；并集面积几乎不变）
	var pick: Array = []
	for k in mine.slice(maxi(0, mine.size() - 8)):
		if pick.all(func(q): return (q.pos as Vector2).distance_to(k.pos) >= 0.9 * float(k.r)):
			pick.append(k)
	var i := 0
	for k in pick:
		var kp: Vector2 = k.pos
		var kr: float = k.r
		later(e, 0.15 * i, func():
			var w := w_circle(e, kp, kr, 1.1 if _wand(e) else 0.9, 0.15, "国度爆发" if i == 0 else "", {"no_fx": sfx() != null})
			w.cb = func(_ww): _fx_burst(kp, kr))
		i += 1
	return 1.2 + 0.15 * i


## D 回旋：自身为心 24 发中圆弹，2 个缺口，扩散 180，显形 0.9 秒（缺口提前画出）
func _d_ring(e: Dictionary, _dir: Vector2, _d: float) -> float:
	ring(e, e.pos, 24, 180.0, 1, 0.12, gaps_at(e.pos), 0.0, {"hold": 0.9})
	var fx = sfx()
	if fx != null:
		fx.play("blade_star", e.pos + Vector2(0, -30), 0.0, 0.8)
	return 1.2


## E 追猎：沿直线冲 300（半宽 30），沿路铺 3 块国度，冲完停 0.8 秒
func _e_chase(e: Dictionary, dir: Vector2, _d: float) -> float:
	var a: float = dir.angle()
	var from: Vector2 = e.pos
	var w := w_stab(e, a, 300.0, 60.0, 0.8, 0.22, "追猎", {"track": 0.3})
	w.cb = func(ww):
		_fx_chase(from, float(ww.ang), 300.0)
		var km = kingdoms()
		if km != null:
			for k in 3:
				km.add(from + Vector2.from_angle(float(ww.ang)) * (60.0 + 100.0 * k), _kr(e), "boss", e, 40.0)
	return 1.6


## F 刃雨：对称环 16 发米弹 ×2 层（第二层错开半格、晚 0.4 秒）+ 3 发针弹自机狙
func _f_rain(e: Dictionary, _dir: Vector2, _d: float) -> float:
	ring(e, e.pos, 16, 170.0, 0, 0.10, [], 0.0, {"hold": 0.6})
	var fx = sfx()
	if fx != null:
		fx.play("blade_star", e.pos + Vector2(0, -30), 0.0, 0.7)
		later(e, 0.4, func(): fx.play("blade_star", e.pos + Vector2(0, -30), PI / 4.0, 0.6))
	later(e, 0.4, func(): ring(e, e.pos, 16, 170.0, 0, 0.10, [], PI / 16.0, {"hold": 0.6}))
	later(e, 0.8, func(): aim(e, e.pos, 3, 0.12, 300.0, 0, 0.10))
	return 1.4


## G 皇帝的猎杀（游荡者）：队长身边依次落 3 个圈（锁定时刻位置）+ 一道直线收尾
func _g_hunt(e: Dictionary, _dir: Vector2, _d: float) -> float:
	for k in 3:
		later(e, 0.45 * k, func():
			var hp: Vector2 = g.ppos
			var w := w_circle(e, hp, 60.0, 0.9, 0.15, "皇帝的猎杀" if k == 0 else "", {"no_fx": sfx() != null})
			w.cb = func(_ww): _fx_burst(hp, 60.0))
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


## ---- 攻击特效（docs/401 §3.2；原作 smgrd：黑 + 深红，十字星 / 刀光 / 红橙速度线 / 黑烟；只画）
## 斩击：沿扇形挥出一道深红月牙刀光（smgrd_attack_02_hit：白 → 红 → 黑），扇边甩红橙火花，脚下一团黑烟
func _fx_cleave(e: Dictionary, ang: float) -> void:
	var fx = sfx()
	if fx == null:
		return
	fx.play("blade_slash", e.pos + Vector2.from_angle(ang) * 18.0 + Vector2(0, -10), ang, 1.25)
	for s in [-1.0, 1.0]:
		fx.sparks(e.pos + Vector2.from_angle(ang + s * PI / 3.0) * 70.0, ang + s * PI / 3.0, 0.35, 5, 300.0, fx.BLOOD)
	fx.smoke(e.pos + Vector2.from_angle(ang) * 40.0, 4, Color(0.0, 0.0, 0.0, 0.45), 14.0, 16.0, 0.8)


## 国度爆发 / 皇帝的猎杀落点：照原作 smgrd_attack_01_hit + buff_03_range 的结构——十字星爆闪（shizixing 黑 → 红 → 白 → 红 → 黑）→
## 红橙拉伸火花向外迸（suduxina / lizi）+ 黑 / 暗红碎石抛起落下（shitou）+ 黑烟往上拉长（smoke）。不画实心圆盘、不画圈
func _fx_burst(pos: Vector2, r: float) -> void:
	var fx = sfx()
	if fx == null:
		return
	var k: float = clampf(r / 64.0, 0.9, 1.5)
	fx.play("blade_nova", pos, 0.0, k)                                  # 红黑碎环外扩（huan_02 + shitou）
	fx.play("blade_star", pos + Vector2(0, -10), 0.0, 2.0 * k)          # 十字星爆闪（shizixing）
	fx.play("blade_pop", pos + Vector2(0, -6), 0.0, 2.2 * k)            # 白 → 红 → 黑迸散核（baoshan）
	fx.sparks(pos, 0.0, PI, 22, 440.0, fx.BLOOD, true, 0.34)            # 红橙速度线（suduxina）
	fx.embers(pos, 10, Color(0.04, 0.01, 0.01), 230.0, 380.0, 0.65, 4.0)   # 黑碎石
	fx.embers(pos, 6, Color(0.72, 0.04, 0.02), 190.0, 340.0, 0.6, 4.0)     # 暗红碎石
	for i in 6:
		fx.smoke(pos + Vector2.from_angle(TAU * float(i) / 6.0 + 0.4) * r * 0.35, 1, Color(0.0, 0.0, 0.0, 0.6), 13.0, 40.0, 0.9)
	g.vfx.shake_screen(0.3)   # 轻震（用户 10-31 同意同量级）


## 追猎：冲过的直线上留一串黑烟 + 红橙速度线（smgrd suduxina / xian_01）
func _fx_chase(from: Vector2, ang: float, ln: float) -> void:
	var fx = sfx()
	if fx == null:
		return
	var d := Vector2.from_angle(ang)
	for i in 7:
		var p: Vector2 = from + d * ln * (float(i) + 0.5) / 7.0
		fx.smoke(p, 1, Color(0.0, 0.0, 0.0, 0.5), 12.0, 10.0, 0.7)
		fx.sparks(p, ang + PI, 0.25, 2, 260.0, fx.BLOOD)
	fx.play("blade_star", from + d * ln + Vector2(0, -20), 0.0, 0.8)
