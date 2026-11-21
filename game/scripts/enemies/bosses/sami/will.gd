## “萨米的意志”（结局一 越过群山）：docs/392 §6.2 + docs/393 §3.1。固定在场地北侧中央、不动；主轴「借银凇」：
## 场上 4 棵积雪银凇，冰凌从北往南落，落到银凇就停（银凇挡 3 次碎掉 → 意志受伤 ×1.6 持续 5 秒并射出 12 发冰屑，20 秒后原处重新长出）。
## 一幕：1 冰凌 ② / 2 冰凌连落 ② / 3 震地 ①（r160，预警 1.8，393 改）/ 4 雪崩 ③；二幕：5 自然涌动（队友脚下圈，占位只画不冻）/ 6 冰凌双列 / 7 风雪环 ④ / 8 冰屑散射（银凇碎时自动）；
## 三幕：9 暴风雪（场边收拢、3 条安全缝）/ 10 冰凌交叉 / 11 群山回响 ④；收尾 12 叹息（最后 3%，全场大圆弹缺口环）。三幕起每 20 秒补 4 只躯壳。
extends "res://scripts/enemies/bosses/sami/sami_boss.gd"

const COL_W := 64.0


func step(e: Dictionary, dt: float, dir: Vector2, dist: float, ready: bool, _mate) -> void:
	tick(e, dt)
	var c: Vector2 = center(e)
	var ar: float = float(D.ENEMIES[e.type].get("arena_r", 520.0))
	e.pos = c + Vector2(0, -ar * 0.55)
	if not e.has("trees"):
		e["trees"] = []
		for p in [Vector2(-220, -40), Vector2(0, 60), Vector2(220, -40), Vector2(-110, 180), Vector2(110, 180)]:
			e.trees.append({"pos": c + p, "hits": 0, "dead_t": -1.0})
	for t in e.trees:
		if float(t.dead_t) > 0.0 and g.t - float(t.dead_t) > 20.0:
			t.dead_t = -1.0
			t.hits = 0
	if act_i(e) >= 2 and g.t >= float(e.get("call_t", 0.0)):
		e.call_t = g.t + 20.0
		summon(e, "husk", 4, 120.0, c)
	if not e.get("sighed", false) and e.hp <= e.maxhp * 0.035 and act_i(e) >= 2:
		e.sighed = true
		e.move_name = "叹息"
		e.move_t = g.t
		ring(e, e.pos, 40, 150.0, 2, 0.30, gaps_at(e.pos), 0.0, {"hold": 1.0, "life": 8.0})
	pick(e, ready, dir, dist)


func moves(e: Dictionary) -> Array:
	match act_i(e):
		0:
			return [["冰凌连落", 9.0, 0.0, 9999.0, _m2], ["震地", 8.0, 0.0, 260.0, _m3], ["雪崩", 7.0, 0.0, 9999.0, _m4], ["冰凌", 4.0, 0.0, 9999.0, _m1]]
		1:
			return [["自然涌动", 14.0, 0.0, 9999.0, _m5], ["风雪环", 8.0, 0.0, 9999.0, _m7], ["冰凌双列", 6.0, 0.0, 9999.0, _m6]]
	return [["暴风雪", 16.0, 0.0, 9999.0, _m9], ["群山回响", 9.0, 0.0, 9999.0, _m11], ["冰凌交叉", 7.0, 0.0, 9999.0, _m10]]


func all_moves(_e: Dictionary) -> Array:
	return [["冰凌", 4.0, 0.0, 9999.0, _m1], ["冰凌连落", 9.0, 0.0, 9999.0, _m2], ["震地", 8.0, 0.0, 9999.0, _m3], ["雪崩", 7.0, 0.0, 9999.0, _m4],
		["自然涌动", 14.0, 0.0, 9999.0, _m5], ["冰凌双列", 6.0, 0.0, 9999.0, _m6], ["风雪环", 8.0, 0.0, 9999.0, _m7],
		["暴风雪", 16.0, 0.0, 9999.0, _m9], ["冰凌交叉", 7.0, 0.0, 9999.0, _m10], ["群山回响", 9.0, 0.0, 9999.0, _m11]]


func base_taken(e: Dictionary) -> float:
	return 1.0 if float(e.get("tree_vuln", 0.0)) <= g.t else 1.6


## 一列冰凌：以 x 为列（宽 64），从北往南每 0.2 秒落一根（预警 0.8，间距 64）；碰到完好银凇就停、银凇记一次
func _column(e: Dictionary, x: float, nm: String, delay := 0.0) -> void:
	var c: Vector2 = center(e)
	var ar: float = float(D.ENEMIES[e.type].get("arena_r", 520.0))
	var y0: float = c.y - ar * 0.45
	var y1: float = c.y + ar * 0.9
	var tree = null
	for t in e.trees:
		if float(t.dead_t) < 0.0 and absf(t.pos.x - x) < COL_W * 0.6 and t.pos.y > y0:
			if tree == null or t.pos.y < tree.pos.y:
				tree = t
	var stop_y: float = tree.pos.y - 20.0 if tree != null else y1
	var k := 0
	var y: float = y0
	while y <= stop_y:
		var p := Vector2(x, y)
		later(e, delay + 0.2 * k, func(): w_circle(e, p, COL_W * 0.5, 0.8, 0.12, nm if k == 0 else "", {"skin": "ice_lance"}))
		y += COL_W
		k += 1
	if tree != null:
		later(e, delay + 0.2 * k + 0.8, func(): _tree_hit(e, tree))


func _tree_hit(e: Dictionary, t: Dictionary) -> void:
	if float(t.dead_t) > 0.0:
		return
	t.hits = int(t.hits) + 1
	if t.hits >= 3:
		t.dead_t = g.t
		e["tree_vuln"] = g.t + 5.0
		e["brk_len"] = 5.0
		ring(e, t.pos, 12, 260.0, 0, 0.10)   # 8 冰屑散射（不占出招窗口）
		g.fx.append({"kind": "ring", "pos": t.pos, "r": 40.0, "life": 0.5, "max": 0.5, "col": Color(0.85, 0.8, 1.0)})


func _m1(e: Dictionary, _dir: Vector2, _d: float) -> float:
	_column(e, g.ppos.x, "冰凌")
	return 1.6


func _m2(e: Dictionary, _dir: Vector2, _d: float) -> float:
	_column(e, g.ppos.x, "冰凌连落")
	later(e, 0.6, func(): _column(e, g.ppos.x, ""))
	later(e, 1.2, func(): _column(e, g.ppos.x, ""))
	return 2.6


## 3 震地：自身为心 r160，预警 1.8，圈外沿溅 12 发小圆弹（雪块）
func _m3(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var w := w_self(e, 160.0, 1.8, 0.25, "震地")
	w.cb = func(_ww): ring(e, e.pos, 12, 110.0, 0, 0.08, [], 0.0, {"life": 5.0})
	return 2.0


## 4 雪崩：朝队长 60° 扇形，3 波米弹（每波 9 发，间隔 0.3）
func _m4(e: Dictionary, dir: Vector2, _d: float) -> float:
	var a: float = dir.angle()
	w_cone(e, a, PI / 6.0, 200.0, 0.8, 0.0, "雪崩")
	for k in 3:
		later(e, 0.8 + 0.3 * k, func(): fan(e, e.pos, a, PI / 6.0, 9, 200.0, 0, 0.15))
	return 1.8


## 5 自然涌动：一名队友脚下画圈 0.8 秒（占位：只画，不冻队友；冻住 / 冲刺解冻等队友定身口径定了再接）
func _m5(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var mates: Array = g.squad.ops.filter(func(o): return not o.is_leader and o.pos != Vector2.INF)
	if mates.is_empty():
		return -1.0
	var o = mates[int(g.t) % mates.size()]
	w_circle(e, o.pos, 40.0, 0.8, 0.0, "自然涌动")
	return 1.0


## 6 冰凌双列：一列瞄队长、一列瞄最近完好银凇的东侧 64
func _m6(e: Dictionary, _dir: Vector2, _d: float) -> float:
	_column(e, g.ppos.x, "冰凌双列")
	var best = null
	for t in e.trees:
		if float(t.dead_t) < 0.0 and (best == null or t.pos.distance_to(g.ppos) < best.pos.distance_to(g.ppos)):
			best = t
	_column(e, (best.pos.x + COL_W) if best != null else g.ppos.x + 160.0, "")
	return 1.8


## 7 风雪环：32 发小圆弹（雪粒）、2 个缺口、扩散 160，环慢转 20°/秒
func _m7(e: Dictionary, _dir: Vector2, _d: float) -> float:
	ring(e, e.pos, 32, 160.0, 0, 0.13, gaps_at(e.pos), 0.0, {"hold": 0.9, "turn": deg_to_rad(20.0), "life": 6.0})
	return 1.2


## 9 暴风雪：场边一圈风雪弹 4 秒往里收 160，留 3 条安全缝（宽约 90，开场就画）
func _m9(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var c: Vector2 = center(e)
	var ar: float = float(D.ENEMIES[e.type].get("arena_r", 520.0))
	var a0: float = (g.ppos - c).angle()
	var gaps: Array = [a0, a0 + TAU / 3.0, a0 - TAU / 3.0]
	e.move_name = "暴风雪"
	e.move_t = g.t
	for i in 72:
		var a: float = TAU * i / 72.0
		var skip := false
		for ga in gaps:
			if absf(angle_difference(a, float(ga))) < 0.09:
				skip = true
		if skip:
			continue
		shot(e, c + Vector2.from_angle(a) * ar, a + PI, 40.0, 1, 0.30, {"hold": 1.2, "life": 5.2})
	return 4.5


## 10 冰凌交叉：一列竖 + 一行横（横行从东往西扫）
func _m10(e: Dictionary, _dir: Vector2, _d: float) -> float:
	_column(e, g.ppos.x, "冰凌交叉")
	var c: Vector2 = center(e)
	var ar: float = float(D.ENEMIES[e.type].get("arena_r", 520.0))
	var y: float = g.ppos.y
	var k := 0
	var x: float = c.x + ar * 0.9
	while x >= c.x - ar * 0.9:
		var p := Vector2(x, y)
		later(e, 0.2 * k, func(): w_circle(e, p, COL_W * 0.5, 0.8, 0.12, "", {"skin": "ice_lance"}))
		x -= COL_W
		k += 1
	return 2.0


## 11 群山回响：两层中圆弹缺口环，正反旋（±25°/秒），各 24 发、缺口 1 个
func _m11(e: Dictionary, _dir: Vector2, _d: float) -> float:
	ring(e, e.pos, 24, 150.0, 1, 0.13, gaps_at(e.pos, 1), 0.0, {"hold": 1.0, "turn": deg_to_rad(25.0), "life": 6.0})
	ring(e, e.pos, 24, 120.0, 1, 0.13, gaps_at(e.pos, 1), PI / 24.0, {"hold": 1.0, "turn": -deg_to_rad(25.0), "life": 6.0})
	return 1.6


func draw(e: Dictionary, cv) -> void:
	for t in e.get("trees", []):
		if float(t.dead_t) > 0.0:
			continue
		cv.draw_circle(t.pos, 24.0, Color(0.85, 0.92, 1.0, 0.75))
		for h in int(t.hits):
			cv.draw_circle(t.pos + Vector2(-10 + 10 * h, -32), 3.0, Color(0.6, 0.5, 1.0, 0.9))
