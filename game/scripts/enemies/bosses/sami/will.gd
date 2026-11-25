## “萨米的意志”（结局一 越过群山）：招式按 docs/393 §11.5（19 招），范围按 §12.4 / 359 §2.6 威慑下限。
## 固定在场地北侧中央、不动（场地型，位移下限豁免）；主轴「借银凇」：场上 5 棵积雪银凇，冰凌从北往南落，落到银凇就停
## （银凇挡 2 次碎掉 → 意志受伤 ×1.5 持续 8 秒，平时 ×0.5「冰甲」，docs/392 §15.1；银凇原地塌落，20 秒后重新长出）。整只的读法：北边落、南边躲、银凇挡。
## 一幕：冰凌 ② / 冰凌连落 ② / 雪震 ① / 雪浪 ③ / 冰凌林（桩林）；二幕：自然涌动 / 冰凌双列 ② / 冻原 ④ / 鹿角 ② / 冰凌斜落 ②；银凇塌落（自动）；
## 三幕：暴风雪（北侧压下）/ 冰凌交叉 ② / 群山回响（回声）/ 冰峰 ①链 / 冰河 ②（弯曲）；叹息段（最后一道卡点后）：崩落 / 寒息 / 叹息（最后 3%）。
## 持续威压（不算招）：每幕开头和每次过卡点，本体阴影向南压到场地 1/3 处，1.2 秒，阴影里 10%。
## 画面全部占位（draw），正式特效交 fx-declutter。
extends "res://scripts/enemies/bosses/sami/sami_boss.gd"

const COL_W := 80.0        # 冰凌列宽（§12.4：64 → 80，冰凌实体可见半径约 24）
const TREE_R := 26.0
const SHADOW_HW := 40.0    # 银凇身后阴影半宽


func _ar(e: Dictionary) -> float:
	return float(D.ENEMIES[e.type].get("arena_r", 520.0))


func _north(e: Dictionary) -> float:
	return center(e).y - _ar(e) * 0.5


func _south(e: Dictionary) -> float:
	return center(e).y + _ar(e) * 0.95


func _trees_alive(e: Dictionary) -> Array:
	return e.get("trees", []).filter(func(t): return float(t.dead_t) < 0.0)


## 点 p 在不在某棵完好银凇身后的阴影里（北边来的东西被树挡住）
func _in_shadow(e: Dictionary, p: Vector2) -> bool:
	for t in _trees_alive(e):
		if absf(p.x - t.pos.x) < SHADOW_HW and p.y > t.pos.y:
			return true
	return false


func step(e: Dictionary, dt: float, dir: Vector2, dist: float, ready: bool, _mate) -> void:
	tick(e, dt)
	obst_tick(e)
	var c: Vector2 = center(e)
	e.pos = c + Vector2(0, -_ar(e) * 0.55)
	if not e.has("trees"):
		e["trees"] = []
		for p in [Vector2(-240, -40), Vector2(0, 70), Vector2(240, -40), Vector2(-130, 200), Vector2(130, 200)]:
			e.trees.append({"pos": c + p, "hits": 0, "dead_t": -1.0, "orig": c + p})
	for t in e.trees:
		if float(t.dead_t) > 0.0 and g.t - float(t.dead_t) > 20.0 and not e.get("fell", false):
			t.dead_t = -1.0
			t.hits = 0
	# 银凇挡雪：意志自己的弹碰到完好银凇就停
	for b in g.ebullets:
		if b.life > 0.0 and int(b.get("source_id", -1)) == int(e.id):
			for t in _trees_alive(e):
				if b.pos.distance_to(t.pos) < TREE_R:
					b.life = 0.0
					break
	# 每幕开头 / 过卡点：本体阴影南压
	if act_i(e) != int(e.get("press_act", -1)):
		e.press_act = act_i(e)
		later(e, 0.9, func(): _press(e))
	if act_i(e) >= 2 and g.t >= float(e.get("call_t", 0.0)):
		e.call_t = g.t + 20.0
		summon(e, "husk", 4, 160.0, c)
	_tick_surge(e)
	_tick_breath(e, dt)
	_tick_river(e, dt)
	if act_i(e) >= 3 and not e.get("fell", false):
		e.fell = true
		_fall(e)
	if not e.get("sighed", false) and e.hp <= e.maxhp * 0.03 and act_i(e) >= 3:
		e.sighed = true
		_sigh(e)
	pick(e, ready, dir, dist)


func moves(e: Dictionary) -> Array:
	match act_i(e):
		0:
			return [["冰凌林", 10.0, 0.0, 9999.0, _m_forest], ["冰凌连落", 9.0, 0.0, 9999.0, _m_triple], ["雪震", 8.0, 0.0, 9999.0, _m_quake],
				["雪浪", 7.0, 0.0, 9999.0, _m_wave], ["冰凌", 4.0, 0.0, 9999.0, _m_lance]]
		1:
			return [["自然涌动", 14.0, 0.0, 9999.0, _m_surge], ["鹿角", 10.0, 0.0, 9999.0, _m_antler], ["冻原", 9.0, 0.0, 9999.0, _m_tundra],
				["冰凌斜落", 8.0, 0.0, 9999.0, _m_diag], ["冰凌双列", 6.0, 0.0, 9999.0, _m_double]]
		2:
			return [["暴风雪", 16.0, 0.0, 9999.0, _m_blizzard], ["冰河", 12.0, 0.0, 9999.0, _m_river], ["冰峰", 11.0, 0.0, 9999.0, _m_peaks],
				["群山回响", 9.0, 0.0, 9999.0, _m_echo], ["冰凌交叉", 7.0, 0.0, 9999.0, _m_cross]]
	return [["崩落", 12.0, 0.0, 9999.0, _m_fall], ["寒息", 10.0, 0.0, 9999.0, _m_breath], ["冰凌", 4.0, 0.0, 9999.0, _m_lance]]


func all_moves(e: Dictionary) -> Array:
	var out: Array = []
	for a in [0, 1, 2, 3]:
		var keep: int = int(e.get("gates_passed", 0))
		e["gates_passed"] = a
		for m in moves(e):
			if not out.any(func(x): return x[0] == m[0]):
				out.append([m[0], m[1], 0.0, 9999.0, m[4]])
		e["gates_passed"] = keep
	out.append(["叹息", 99.0, 0.0, 9999.0, _m_sigh])
	return out


## 主轴收益（docs/392 §15.1 A「冰甲」）：平时受伤 ×0.5；银凇碎后 8 秒 ×1.5
func base_taken(e: Dictionary) -> float:
	return 0.25 if float(e.get("tree_vuln", 0.0)) <= g.t else 2.5


## ---- 冰凌列：以 x 为列（宽 80），从北往南每 0.2 秒落一根；碰到完好银凇 / 冰桩 / 冰峰就停，银凇记一次
func _column(e: Dictionary, x: float, nm: String, delay := 0.0, pct := 0.12, aimed := true) -> void:
	if not e.has("last_cols"):
		e["last_cols"] = []
	e.last_cols.append(x)
	if e.last_cols.size() > 4:
		e.last_cols.pop_front()
	var y0: float = _north(e)
	var y1: float = _south(e)
	var tree = null
	for t in _trees_alive(e):
		if absf(t.pos.x - x) < COL_W * 0.6 and t.pos.y > y0 and (tree == null or t.pos.y < tree.pos.y):
			tree = t
	var stop_y: float = tree.pos.y - 24.0 if tree != null else y1
	for o in e.get("obst", []):
		if absf(o.pos.x - x) < COL_W * 0.5 + float(o.r) and o.pos.y > y0 and o.pos.y - float(o.r) < stop_y:
			stop_y = o.pos.y - float(o.r)
			tree = null   # 冰桩 / 冰峰挡下的冰凌不算砸银凇（docs/392 §15.1）
	var k := 0
	var y: float = y0
	while y <= stop_y:
		later(e, delay + 0.2 * k, _lance_at.bind(e, Vector2(x, y), nm if k == 0 else "", pct))
		y += COL_W
		k += 1
	if tree != null and aimed:
		later(e, delay + 0.2 * k + 0.8, func(): _tree_hit(e, tree))   # 只有瞄队长的那一列算砸银凇（主轴靠站位，不靠运气，11-26 测试台）


func _lance_at(e: Dictionary, p: Vector2, nm: String, pct: float) -> void:
	w_circle(e, p, COL_W * 0.5, 0.8, pct, nm, {"skin": "ice_lance", "lock": nm != ""})


func _tree_hit(e: Dictionary, t: Dictionary) -> void:
	if float(t.dead_t) > 0.0:
		return
	t.hits = int(t.hits) + 1
	if t.hits >= 1:   # 11-26 测试台：挨 1 次就碎（2 次时窗口只占约 10%，会主轴拉不开）
		t.dead_t = g.t
		e["tree_vuln"] = g.t + 8.0
		e["brk_len"] = 8.0
		e["break_ring_until"] = g.t + 8.0
		_collapse_tree(e, t)


## 银凇塌落（自动，二 / 三幕）：树周 8 个小落点 r20 原地塌下
func _collapse_tree(e: Dictionary, t: Dictionary) -> void:
	g.fx.append({"kind": "ring", "pos": t.pos, "r": 40.0, "life": 0.5, "max": 0.5, "col": Color(0.85, 0.9, 1.0)})
	if act_i(e) < 1:
		return
	for i in 8:
		var p: Vector2 = t.pos + Vector2.from_angle(TAU * i / 8.0) * (34.0 + 16.0 * (i % 2))
		w_circle(e, p, 20.0, 0.8, 0.10, "银凇塌落" if i == 0 else "", {"lock": false})


## ---- 本体压迫：阴影向南压到场地 1/3 处（预警 1.2 / 锁定 1.0），阴影里 10%
func _press(e: Dictionary) -> void:
	var ln: float = _ar(e) * 0.55 + _ar(e) * 0.66
	w_line(e, PI * 0.5, ln, 120.0, 1.2, 0.10, "", {"track": 0.0, "lock": false, "skin": "mc_line"})


## ---- 一幕
func _m_lance(e: Dictionary, _dir: Vector2, _d: float) -> float:
	_column(e, g.ppos.x + g.pvel.x * 0.3, "冰凌")
	_column(e, g.ppos.x + (240.0 if int(g.t) % 2 == 0 else -240.0), "", 0.3, 0.12, false)   # 密度（11-26 用户）：旁边再落一列
	return 1.6


func _m_triple(e: Dictionary, _dir: Vector2, _d: float) -> float:
	_column(e, g.ppos.x, "冰凌连落")
	later(e, 0.6, func(): _column(e, g.ppos.x + g.pvel.x * 0.3, ""))
	later(e, 1.2, func(): _column(e, g.ppos.x + g.pvel.x * 0.3, ""))
	return 2.6


## 雪震：自身 r230（2.3）25%；同时每棵银凇抖雪 r60（1.0 / 0.8）12%
func _m_quake(e: Dictionary, _dir: Vector2, _d: float) -> float:
	w_self(e, 230.0, 2.3, 0.25, "雪震")
	for t in _trees_alive(e):
		later(e, 1.3, func(): w_circle(e, t.pos, 60.0, 1.0, 0.12, "", {"lock": false}))
	return 2.5


## 雪浪：60° 弧面从意志向南推进（150 px/秒），碰到银凇断开（大弹排成弧面）
func _m_wave(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var a: float = (g.ppos - e.pos).angle()
	w_cone(e, a, PI / 6.0, 520.0, 0.8, 0.0, "雪浪", {"track": 0.3})
	later(e, 0.8, _wave_go.bind(e, a))
	return 1.8


func _wave_go(e: Dictionary, a: float) -> void:
	for wv in 2:   # 两层弧面（第二层错开半格、晚 0.4 秒），11-26 加密
		for i in 21:
			var aa: float = a + lerpf(-PI / 6.0, PI / 6.0, (i + 0.5 * wv) / 20.5)
			shot(e, e.pos + Vector2.from_angle(aa) * 40.0, aa, 150.0, 2 if wv == 0 else 1, 0.15, {"life": 5.0, "hold": 0.4 * wv})


## 冰凌林：队长周围 12 根冰凌落地插成两排交错冰桩（间距 ≥80），立 5 秒：挡路、挡冰凌
func _m_forest(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var base: Vector2 = g.ppos
	var k := 0
	for row in 2:
		for i in 6:
			var p: Vector2 = base + Vector2(-250.0 + 100.0 * i + 50.0 * row, -90.0 + 180.0 * row)
			later(e, 0.08 * k, _stake.bind(e, p, k == 0))
			k += 1
	return 1.8


func _stake(e: Dictionary, p: Vector2, first: bool) -> void:
	var w := w_circle(e, p, 24.0, 0.8, 0.08, "冰凌林" if first else "", {"lock": first})
	w.cb = func(_ww): add_obst(e, p, 16.0, 5.0)


## ---- 二幕
## 自然涌动：冻住一名队友 3 秒（攻速压到 5%），队长冲刺穿过它就解冻
func _m_surge(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var mates: Array = g.squad.ops.filter(func(o): return not o.is_leader and o.pos != Vector2.INF)
	if mates.is_empty():
		return -1.0
	var o = mates[int(g.t * 3.0) % mates.size()]
	var w := w_circle(e, o.pos, 44.0, 0.8, 0.0, "自然涌动")
	w.cb = func(_ww):
		e["surge_op"] = str(o.id)
		e["surge_until"] = g.t + 3.0
		g.rfx._apply_stat("op_aspd", "mult", 0.05, "will_surge", "op:" + str(o.id))
	return 1.0


func _tick_surge(e: Dictionary) -> void:
	if str(e.get("surge_op", "")) == "":
		return
	var o = g.squad.get_op(str(e.surge_op))
	var thaw: bool = g.t >= float(e.surge_until) or o == null
	if not thaw and float(g.get("dash_t")) > 0.0 and o.pos != Vector2.INF and g.ppos.distance_to(o.pos) < 70.0:
		thaw = true
	if thaw:
		e.surge_op = ""
		g.stats.remove_source("will_surge")
		g.sync_stats()


## 冰凌双列：一列瞄队长，一列瞄最近银凇的东侧
func _m_double(e: Dictionary, _dir: Vector2, _d: float) -> float:
	_column(e, g.ppos.x, "冰凌双列")
	var best = null
	for t in _trees_alive(e):
		if best == null or t.pos.distance_to(g.ppos) < best.pos.distance_to(g.ppos):
			best = t
	_column(e, (best.pos.x + COL_W) if best != null else g.ppos.x + 180.0, "", 0.0, 0.12, false)
	return 1.8


## 冻原：冻结地面从意志脚下向南扩张（160 px/秒），推过时 10% + 寒冷 1 秒；出口 = 银凇身后的阴影（提前 1.0 秒标出）
func _m_tundra(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var first := true
	for t in _trees_alive(e):
		var w := w_line(e, PI * 0.5, _south(e) - t.pos.y, SHADOW_HW, 1.0, 0.0, "冻原" if first else "", {"lock": first})
		w.pos = t.pos
		first = false
	if first:
		w_self(e, 60.0, 1.0, 0.0, "冻原")
	e["tundra"] = {"t0": g.t + 1.0, "y0": e.pos.y, "spd": 160.0, "hit": false}
	return 1.6


## 鹿角：从两支鹿角方向长出冰枝，每根分叉两次，长到头 0.6 秒后碎（主枝 280 + 两级分叉 140，总长约 560）
func _m_antler(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var a0: float = (g.ppos - e.pos).angle()
	var first := true
	for s in [-1.0, 1.0]:
		var a: float = a0 + s * 0.35
		var p0: Vector2 = e.pos
		var p1: Vector2 = p0 + Vector2.from_angle(a) * 280.0
		_branch(e, p0, a, 280.0, 0.0, "鹿角" if first else "")
		first = false
		for s2 in [-1.0, 1.0]:
			var a2: float = a + s2 * 0.5
			var p2: Vector2 = p1 + Vector2.from_angle(a2) * 140.0
			_branch(e, p1, a2, 140.0, 0.3, "")
			for s3 in [-1.0, 1.0]:
				_branch(e, p2, a2 + s3 * 0.45, 140.0, 0.6, "")
	return 2.0


func _branch(e: Dictionary, p: Vector2, a: float, ln: float, delay: float, nm: String) -> void:
	later(e, delay, _branch_go.bind(e, p, a, ln, nm))


func _branch_go(e: Dictionary, p: Vector2, a: float, ln: float, nm: String) -> void:
	var w := w_line(e, a, ln, 24.0, 0.8, 0.13, nm, {"lock": nm != ""})
	w.pos = p


## 冰凌斜落：两道 ±30° 斜列在队长处交叉（半宽 32），冰凌从北端依次落下；银凇照样挡
func _m_diag(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var x0: Vector2 = g.ppos
	var first := true
	for s in [-1.0, 1.0]:
		var d: Vector2 = Vector2(s * 0.5, 0.866).normalized()
		var top: Vector2 = x0 - d * ((x0.y - _north(e)) / d.y)
		var k := 0
		var p: Vector2 = top
		while p.y <= _south(e):
			if _in_shadow(e, p) or obst_at(e, p):
				break
			later(e, 0.2 * k, _lance_at.bind(e, p, "冰凌斜落" if first and k == 0 else "", 0.12))
			p += d * 64.0
			k += 1
		first = false
	return 2.2


## ---- 三幕
## 暴风雪：风雪从北侧整片往南压到场地 2/3 处再退回；安全的是银凇阴影和 3 条宽 90 的缝（开场就画）
func _m_blizzard(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var c: Vector2 = center(e)
	var ar: float = _ar(e)
	var xs: Array = []
	var pick_x: Array = [c.x - ar * 0.6, c.x, c.x + ar * 0.6]
	for i in 3:
		xs.append(pick_x[i] + float((int(g.t * 7.0) + i * 3) % 5 - 2) * 40.0)
	var first := true
	for x in xs:
		var w := w_line(e, PI * 0.5, ar * 1.5, 45.0, 1.2, 0.0, "暴风雪" if first else "", {"lock": first})
		w.pos = Vector2(x, _north(e))
		first = false
	e["blizz"] = {"t0": g.t + 1.2, "gaps": xs, "stop": _north(e) + (_south(e) - _north(e)) * 0.66, "hit": false}
	return 4.0


## 冰凌交叉：一列竖 + 一行横（横行从东往西扫）
func _m_cross(e: Dictionary, _dir: Vector2, _d: float) -> float:
	_column(e, g.ppos.x, "冰凌交叉")
	var c: Vector2 = center(e)
	var ar: float = _ar(e)
	var y: float = g.ppos.y
	var k := 0
	var x: float = c.x + ar * 0.95
	while x >= c.x - ar * 0.95:
		later(e, 0.15 * k, _lance_at.bind(e, Vector2(x, y), "", 0.12))
		x -= COL_W
		k += 1
	return 2.0


## 群山回响：刚落过的冰凌列 1.2 秒后原位再落一次，并向左右各扩一列
func _m_echo(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var cols: Array = e.get("last_cols", []).duplicate()
	if cols.is_empty():
		cols = [g.ppos.x]
	var last: float = float(cols[-1])
	e.move_name = "群山回响"
	e.move_t = g.t
	for dx in [0.0, -COL_W, COL_W]:
		later(e, 1.2, func(): _column(e, last + dx, "群山回响" if dx == 0.0 else "", 0.0, 0.12, false))
	return 2.6


## 冰峰：从意志到队长，冰峰一个接一个拱起（间隔 0.3、r40、0.9 / 0.6），留 3 秒当障碍，也挡冰凌
func _m_peaks(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var tgt: Vector2 = g.ppos + g.pvel.limit_length(150.0) * 0.4
	var d: Vector2 = tgt - e.pos
	var n: int = clampi(int(d.length() / 75.0), 4, 12)
	for k in n:
		var p: Vector2 = e.pos + d * float(k + 1) / float(n)
		later(e, 0.3 * k, _peak.bind(e, p, k == 0))
	return 1.2 + 0.3 * n


func _peak(e: Dictionary, p: Vector2, first: bool) -> void:
	var w := w_circle(e, p, 40.0, 0.9, 0.14, "冰峰" if first else "", {"lock": first})
	w.cb = func(_ww): add_obst(e, p, 26.0, 3.0)


## 冰河：一条冰河从北往南蜿蜒流下（宽 90，河道先画 1.2 秒），冰块顺河道流下（碰到 13%）
func _m_river(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var x0: float = g.ppos.x
	var amp: float = 140.0
	var ph: float = float(int(g.t * 13.0) % 628) / 100.0
	var pts: Array = []
	var y: float = _north(e)
	while y <= _south(e):
		pts.append(Vector2(x0 + amp * sin(ph + (y - g.ppos.y) / 140.0) - amp * sin(ph), y))
		y += 50.0
	var first := true
	for p in pts:
		w_circle(e, p, 45.0, 1.2, 0.0, "冰河" if first else "", {"lock": first})
		first = false
	e["river"] = {"pts": pts, "t0": g.t + 1.2, "blocks": [], "next": 0.0, "until": g.t + 1.2 + 4.0}
	return 2.0


func _tick_river(e: Dictionary, dt: float) -> void:
	var rv = e.get("river")
	if not (rv is Dictionary) or g.t < float(rv.t0):
		return
	if g.t >= float(rv.until) and (rv.blocks as Array).is_empty():
		e.erase("river")
		return
	if g.t < float(rv.until) and g.t >= float(rv.next):
		rv.next = g.t + 0.45
		rv.blocks.append({"s": 0.0, "hit": false})
	var pts: Array = rv.pts
	var keep: Array = []
	for b in rv.blocks:
		b.s = float(b.s) + 260.0 * dt / 50.0
		var i: int = int(b.s)
		if i >= pts.size() - 1:
			continue
		var p: Vector2 = (pts[i] as Vector2).lerp(pts[i + 1], b.s - float(i))
		b["pos"] = p
		if not b.hit and g.combat.ground_d(g.ppos, p) < 30.0:
			b.hit = true
			hit_now(e, p, 30.0, 0.13)
		keep.append(b)
	rv.blocks = keep


## ---- 叹息段
## 崩落：银凇全部倒下（进叹息段一次 + 冷却 12）：每棵先倾斜 1 秒（倒向画出），再整棵砸向那个方向（长 160、半宽 30）
func _fall(e: Dictionary) -> void:
	_m_fall(e, Vector2.ZERO, 0.0)


func _m_fall(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var any := false
	for t in e.trees:
		var src: Vector2 = t.orig
		var a: float = (g.ppos - src).angle()
		var w := w_line(e, a, 160.0, 30.0, 1.0, 0.15, "崩落" if not any else "", {"lock": not any})
		w.pos = src
		t.dead_t = g.t
		any = true
	return 1.4


## 寒息：白雾锥从北向南 3 秒内慢慢张大（60° → 100°），雾里每秒 4% + 寒冷
func _m_breath(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var a: float = (g.ppos - e.pos).angle()
	w_cone(e, a, PI / 6.0, 600.0, 0.8, 0.0, "寒息")
	e["breath"] = {"t0": g.t + 0.8, "a": a, "tick": 0.0}
	return 1.2


func _tick_breath(e: Dictionary, dt: float) -> void:
	var br = e.get("breath")
	if br is Dictionary and g.t >= float(br.t0):
		var k: float = (g.t - float(br.t0)) / 3.0
		if k >= 1.0:
			e.erase("breath")
		else:
			br.tick = float(br.tick) - dt
			var half: float = deg_to_rad(lerpf(30.0, 50.0, k))
			var dv: Vector2 = g.ppos - e.pos
			if br.tick <= 0.0 and dv.length() < 600.0 and absf(angle_difference(dv.angle(), float(br.a))) < half:
				br.tick = 0.25
				hit_now(e, g.ppos, 1.0, 0.01, {"chill": 0.5})
	# 冻原推进
	var tu = e.get("tundra")
	if tu is Dictionary and g.t >= float(tu.t0):
		var y: float = float(tu.y0) + (g.t - float(tu.t0)) * float(tu.spd)
		if y > _south(e):
			e.erase("tundra")
		elif not tu.hit and absf(g.ppos.y - y) < 14.0 and not _in_shadow(e, g.ppos):
			tu.hit = true
			hit_now(e, g.ppos, 1.0, 0.10, {"chill": 1.0})
	# 暴风雪推进 / 退回
	var bz = e.get("blizz")
	if bz is Dictionary and g.t >= float(bz.t0):
		var el: float = g.t - float(bz.t0)
		var y2: float = _north(e) + minf(el, 2.0) / 2.0 * (float(bz.stop) - _north(e))
		if el > 3.0:
			e.erase("blizz")
		elif not bz.hit and g.ppos.y < y2 and g.ppos.y > _north(e) - 40.0 and not _in_shadow(e, g.ppos):
			var safe := false
			for x in bz.gaps:
				if absf(g.ppos.x - float(x)) < 45.0:
					safe = true
			if not safe:
				bz.hit = true
				hit_now(e, g.ppos, 1.0, 0.30)
		e["blizz_y"] = y2


func _m_sigh(e: Dictionary, _dir: Vector2, _d: float) -> float:
	_sigh(e)
	return 3.0


## 叹息（最后 3%）：全场冰凌一次性齐落（2.5 秒），只留银凇原址那几列不落
func _sigh(e: Dictionary) -> void:
	e.move_name = "叹息"
	e.move_t = g.t
	var c: Vector2 = center(e)
	var ar: float = _ar(e)
	var x: float = c.x - ar
	while x <= c.x + ar:
		var safe := false
		for t in e.trees:
			if absf(x - (t.orig as Vector2).x) < COL_W * 0.6:
				safe = true
		if not safe:
			var y: float = _north(e)
			while y <= _south(e):
				w_circle(e, Vector2(x, y), COL_W * 0.5, 2.5, 0.30, "", {"skin": "ice_lance", "lock": false})
				y += COL_W
		x += COL_W


func draw(e: Dictionary, cv) -> void:
	for t in e.get("trees", []):
		if float(t.dead_t) > 0.0:
			cv.draw_circle(t.orig, 10.0, Color(0.8, 0.9, 1.0, 0.35))
			continue
		cv.draw_circle(t.pos, TREE_R, Color(0.85, 0.92, 1.0, 0.75))
		cv.draw_line(t.pos, Vector2(t.pos.x, _south(e)), Color(0.4, 0.5, 0.7, 0.12), SHADOW_HW * 2.0)
		for h in int(t.hits):
			cv.draw_circle(t.pos + Vector2(-10 + 10 * h, -34), 3.0, Color(0.6, 0.5, 1.0, 0.9))
	for o in e.get("obst", []):
		cv.draw_circle(o.pos, float(o.r), Color(0.8, 0.92, 1.0, 0.9))
		cv.draw_arc(o.pos, float(o.r), 0.0, TAU, 16, Color(0.95, 0.98, 1.0), 2.0)
	var tu = e.get("tundra")
	if tu is Dictionary and g.t >= float(tu.t0):
		var y: float = float(tu.y0) + (g.t - float(tu.t0)) * float(tu.spd)
		var c: Vector2 = center(e)
		cv.draw_line(Vector2(c.x - _ar(e), y), Vector2(c.x + _ar(e), y), Color(0.75, 0.9, 1.0, 0.6), 6.0)
	if e.has("blizz_y") and e.get("blizz") is Dictionary:
		var c2: Vector2 = center(e)
		cv.draw_rect(Rect2(c2.x - _ar(e), _north(e), _ar(e) * 2.0, float(e.blizz_y) - _north(e)), Color(0.9, 0.95, 1.0, 0.25))
	var rv = e.get("river")
	if rv is Dictionary:
		for b in rv.blocks:
			if b.has("pos"):
				cv.draw_rect(Rect2(b.pos - Vector2(16, 16), Vector2(32, 32)), Color(0.8, 0.92, 1.0, 0.9))
	if str(e.get("surge_op", "")) != "":
		var o = g.squad.get_op(str(e.surge_op))
		if o != null and o.pos != Vector2.INF:
			cv.draw_arc(o.pos, 30.0, 0.0, TAU, 20, Color(0.7, 0.9, 1.2), 4.0)


## 机器人主轴：站到最近一棵完好银凇正南 70（冰凌瞄队长这一列落下，先砸到银凇）；队友被冻时冲过去
func axis_do(e: Dictionary, p: Vector2) -> Vector2:
	if str(e.get("surge_op", "")) != "":
		var o = g.squad.get_op(str(e.surge_op))
		if o != null and o.pos != Vector2.INF:
			return go_to(p, o.pos, 10.0)
	var best = null
	for t in _trees_alive(e):
		var sc: float = t.pos.distance_to(e.pos) + t.pos.distance_to(p) * 0.5
		if best == null or sc < best.pos.distance_to(e.pos) + best.pos.distance_to(p) * 0.5:
			best = t
	if best == null:
		return Vector2.INF
	return go_to(p, best.pos + Vector2(0, 70), 16.0)   # 离意志最近的那棵树身后（输出距离近）


## 不理主轴：离银凇所在的列远一点（站在两棵之间的空列）
func axis_ignore(e: Dictionary, p: Vector2) -> Vector2:
	for t in _trees_alive(e):
		if absf(t.pos.x - p.x) < COL_W:
			return Vector2(signf(p.x - t.pos.x + 0.01), 0.0)   # 整列都避开（站在树北边同一列，冰凌照样落到树上）
	return Vector2.INF
