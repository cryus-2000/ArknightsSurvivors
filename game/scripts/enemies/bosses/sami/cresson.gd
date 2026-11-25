## 无垠回荡克雷松（结局三 自深处的一瞥）：招式按 docs/393 §11.7（18 招，淡紫 270°），范围 / 跳跃按 §12.4 / 359 §2.6。
## 整只的读法：花瓣和回声——弹是苗圃里长出来的花和打旋的花瓣；招式会隔 0.8 秒在上一个落点重放。
## 移动 = 真跳（§12.4，用户 11-25）：6 个检查点（圈半径 320）隔点跳（1→3→5→2→4→6，跨度约 554）：起跳 0.4 秒 → 空中 0.5 秒（抛物弧 + 4 残影，空中不可受击）→ 落地落击 r250（一幕 12%，二幕起 20%）。
## 落点眼纹提前 2.7 秒亮；跳的间隔 6 / 4.5 / 3.5（一 / 二 / 三幕），回荡段 3.0。
## 主轴「稳定」：3 台空间稳定设施（内移到 r250，避开维度回荡的六边形跑道），队长跑过（r40）启动，充能 1.0 秒（三幕 1.6）后放稳定场 r170，9 秒（三幕 7），设施冷却 11 秒；
## 平时受伤 ×0.5（数据 phys_taken / arts_taken），在稳定场里 ×2.5（docs/392 §15.3 A 原拟 1.5，11-26 测试台上调）。二幕被苗圃缠住的设施要 2 秒内跑过两次。
## 「回荡」段：第一条命打空后倒下 3 秒，以一半最大生命重生，招式伤害 ×1.5，设施自动轮流启动；倒下处留「花墓」。
## 招：一幕 双击 ② / 播种 ① / 花瓣风 ③ / 回荡 ④ / 萌发 ③；二幕 裂隙 ② / 无之花 ① / 回荡·双击 ② / 剪枝 ②（闪现落击 = 每次落地）；
## 三幕 阖眼 ① / 花雨 / 维度回荡 / 播种·环 ① / 眼中之园 ①；回荡段 三跳 ① / 播种·终 ① / 花墓 ③。画面全部占位。
extends "res://scripts/enemies/bosses/sami/sami_boss.gd"

const CP_R := 320.0
const DEV_R := 250.0
const LAND_R := 250.0
const ORDER := [0, 2, 4, 1, 3, 5]


func _gap(e: Dictionary) -> float:
	if e.get("echo", false):
		return 3.0
	return [6.0, 4.5, 3.5][clampi(act_i(e), 0, 2)]


func _nursery(e: Dictionary, p: Vector2, r: float, life: float) -> void:
	var km = kingdoms()
	if km != null:
		var nk: Dictionary = km.add(p, r, "nursery", e, life)
		nk.dps = 0.03


func step(e: Dictionary, dt: float, dir: Vector2, dist: float, ready: bool, _mate) -> void:
	tick(e, dt)
	ambient(e, dt, "petal")
	var c: Vector2 = center(e)
	if not e.has("cps"):
		e["cps"] = []
		for k in 6:
			e.cps.append(c + Vector2.from_angle(TAU * k / 6.0) * CP_R)
		e["devs"] = []
		for k in 3:
			e.devs.append({"pos": c + Vector2.from_angle(TAU * (2 * k + 1) / 6.0) * DEV_R, "cd": 0.0, "charge": -1.0, "field": 0.0, "taps": [], "auto": false})
		e["cp"] = 0
		e["ord_i"] = 0
		e["prev_pos"] = e.pos
		e.pos = e.cps[0]
		e.blink_t = g.t + 6.0
		e.next_cp = ORDER[1]
	_tick_jump(e)
	_tick_flowers(e)
	_tick_scissor(e)
	_tick_hex(e, dt)
	_tick_tomb(e)
	_tick_devs(e)
	if e.has("jump"):
		return   # 空中不出招
	pick(e, ready, dir, dist)


## ---- 跳：落点眼纹提前 2.7 秒亮（落击圈 r250），落地前 0.9 秒起跳（0.4 起跳 + 0.5 空中）
func _tick_jump(e: Dictionary) -> void:
	if e.get("coma", false):
		return
	if not e.has("land_warned") and g.t >= float(e.blink_t) - 2.7:
		e.land_warned = true
		var to: Vector2 = e.cps[int(e.next_cp)]
		var pct: float = 0.12 if act_i(e) == 0 and not e.get("echo", false) else 0.20
		w_circle(e, to, LAND_R, 2.7, pct, "闪现落击" if act_i(e) >= 1 else "", {"lock": false})
	if not e.has("jump") and g.t >= float(e.blink_t) - 0.9:
		e["jump"] = {"from": e.pos, "to": e.cps[int(e.next_cp)], "t0": g.t}
	if e.has("jump"):
		var j: Dictionary = e.jump
		var k: float = (g.t - float(j.t0) - 0.4) / 0.5
		if k >= 0.0:
			e.invuln = true
			e.pos = (j.from as Vector2).lerp(j.to, clampf(k, 0.0, 1.0))
			e["air_h"] = sin(PI * clampf(k, 0.0, 1.0)) * 120.0
		if k >= 1.0:
			_land(e)


func _land(e: Dictionary) -> void:
	var j: Dictionary = e.jump
	e.erase("jump")
	e.erase("land_warned")
	e.invuln = false
	e.air_h = 0.0
	e.prev_pos = j.from
	e.pos = j.to
	e.cp = int(e.next_cp)
	e.ord_i = (int(e.ord_i) + 1) % 6
	e.next_cp = ORDER[(int(e.ord_i) + 1) % 6]
	if e.has("tri_q") and not (e.tri_q as Array).is_empty():
		e.next_cp = int(e.tri_q.pop_front())
		e.blink_t = g.t + 1.9
	else:
		e.blink_t = g.t + _gap(e)
	var land: Vector2 = e.pos
	later(e, 1.2, func():
		for k in 2:
			_nursery(e, land + Vector2.from_angle(TAU * k / 2.0 + g.t) * 110.0, 60.0, 20.0))


## ---- 设施
func _tick_devs(e: Dictionary) -> void:
	var ai: int = act_i(e)
	var echo: bool = e.get("echo", false)
	var fdur: float = 7.0 if ai >= 2 else 9.0
	var chg: float = 1.6 if ai >= 2 else 1.0
	for k in e.devs.size():
		var d: Dictionary = e.devs[k]
		if echo:
			d.auto = true
			var slot: int = int(g.t / 5.0) % 3
			d.field = g.t + 0.1 if slot == k else d.field
			continue
		if float(d.charge) > 0.0 and g.t >= float(d.charge):
			d.charge = -1.0
			d.field = g.t + fdur
			d.cd = g.t + 11.0
		if g.t >= float(d.cd) and float(d.charge) < 0.0 and g.ppos.distance_to(d.pos) < 40.0:
			var tangled: bool = ai >= 1 and kingdoms() != null and kingdoms().inside(d.pos, ["nursery"])
			if tangled:
				var taps: Array = d.taps.filter(func(t): return g.t - float(t) < 2.0)
				if taps.is_empty() or g.t - float(taps[taps.size() - 1]) > 0.6:
					taps.append(g.t)
				d.taps = taps
				if taps.size() < 2:
					continue
				d.taps = []
			d.charge = g.t + chg
			d.cd = g.t + 99.0


func _in_field(e: Dictionary, p := Vector2.INF) -> bool:
	var q: Vector2 = e.pos if p == Vector2.INF else p
	for d in e.get("devs", []):
		if float(d.field) > g.t and q.distance_to(d.pos) < 170.0:
			return true
	return false


## 平时受伤 × phys_taken / arts_taken（0.5，combat 已乘）；在稳定场里按 stab_taken（2.5）算，这里乘回差值
func base_taken(e: Dictionary) -> float:
	var d: Dictionary = D.ENEMIES[e.type]
	return float(d.get("stab_taken", 1.5)) / maxf(0.01, float(d.get("phys_taken", 1.0))) if _in_field(e) else 1.0


## 第一条命打空：倒下 3 秒后以一半最大生命重生（回荡段）；倒下处留「花墓」
func on_lethal(e: Dictionary) -> bool:
	if e.get("echo", false):
		return false
	e.echo = true
	e.hp = 1.0
	e.coma = true
	e.invuln = true
	e.stun = 0.0
	e.coma_t = maxf(0.0, Bal.v("boss/pair_race", 8.0) - 3.0)
	e.revives = 0
	e.sq = []
	e.erase("jump")
	e.erase("land_warned")
	e["tomb"] = {"pos": e.pos, "next": g.t + 4.5}
	return true


func on_revive(e: Dictionary) -> void:
	e.maxhp *= float(D.ENEMIES[e.type].get("echo_hp_frac", 0.5))
	e.hp = e.maxhp
	e.dmg_k = float(D.ENEMIES[e.type].get("echo_dmg_k", 1.5))
	e.gates = []
	e.invuln = false
	e.blink_t = g.t + 3.0
	g.vfx.add_alert(e.pos + Vector2(0, -50), "回荡", col(e), 18)


func moves(e: Dictionary) -> Array:
	if e.get("echo", false):
		return [["三跳", 12.0, 0.0, 9999.0, _triple], ["播种·终", 12.0, 0.0, 9999.0, _sow_all], ["双击", 4.0, 0.0, 9999.0, _double]]
	match act_i(e):
		0:
			return [["回荡", 9.0, 0.0, 9999.0, _echo_ring], ["萌发", 9.0, 0.0, 9999.0, _sprout], ["播种", 8.0, 0.0, 9999.0, _sow],
				["花瓣风", 6.0, 0.0, 9999.0, _petal_wind], ["双击", 4.0, 0.0, 9999.0, _double]]
		1:
			return [["无之花", 10.0, 0.0, 9999.0, _flower], ["裂隙", 8.0, 0.0, 9999.0, _rift], ["剪枝", 8.0, 0.0, 9999.0, _scissor],
				["回荡·双击", 7.0, 0.0, 9999.0, _echo_double], ["双击", 4.0, 0.0, 9999.0, _double]]
	return [["阖眼", 13.0, 0.0, 9999.0, _close_eye], ["花雨", 12.0, 0.0, 9999.0, _petal_rain], ["播种·环", 12.0, 0.0, 9999.0, _sow_ring],
		["维度回荡", 10.0, 0.0, 9999.0, _dim_echo], ["眼中之园", 9.0, 0.0, 9999.0, _eye_garden]]


func all_moves(e: Dictionary) -> Array:
	var out: Array = []
	var keep_a: int = int(e.get("gates_passed", 0))
	var keep_e: bool = e.get("echo", false)
	for st in [[0, false], [1, false], [2, false], [2, true]]:
		e["gates_passed"] = st[0]
		e["echo"] = st[1]
		for m in moves(e):
			if not out.any(func(x): return x[0] == m[0]):
				out.append([m[0], m[1], 0.0, 9999.0, m[4]])
	e["gates_passed"] = keep_a
	e["echo"] = keep_e
	out.append(["花墓", 99.0, 0.0, 9999.0, _m_tomb])
	return out


## ---- 一幕
## 双击：两道花刺线（长 1000、半宽 22），一道瞄队长，一道瞄最近的队友
func _double(e: Dictionary, _dir: Vector2, _d: float) -> float:
	_double_from(e, e.pos, "双击", 0.14)
	return 1.0


func _double_from(e: Dictionary, p: Vector2, nm: String, pct: float) -> void:
	var a: float = (g.ppos + g.pvel.limit_length(150.0) * 0.25 - p).angle()
	var mates: Array = g.squad.ops.filter(func(o): return not o.is_leader and o.pos != Vector2.INF)
	mates.sort_custom(func(x, y): return x.pos.distance_to(p) < y.pos.distance_to(p))
	var t2: Vector2 = mates[0].pos if not mates.is_empty() else g.ppos + Vector2.from_angle(a + 1.2) * 120.0
	var w1 := w_line(e, a, 1000.0, 22.0, 0.7, pct, nm, {"track": 0.3, "lead": 0.25})
	w1.pos = p
	var w2 := w_line(e, (t2 - p).angle(), 1000.0, 22.0, 0.7, pct, "", {"lock": false})
	w2.pos = p


## 播种：4 个追踪落点（r45，1.0 / 0.64），落地留 6 秒小苗圃
func _sow(e: Dictionary, _dir: Vector2, _d: float) -> float:
	for k in 4:
		later(e, 0.5 * k, _sow_one.bind(e, k == 0))
	return 2.4


func _sow_one(e: Dictionary, first: bool) -> void:
	var w := w_circle(e, g.ppos, 45.0, 1.0, 0.12, "播种" if first else "", {"track_pos": "leader", "track": 0.36, "lock": first})
	w.cb = func(ww): _nursery(e, ww.pos, 50.0, 6.0)


## 花瓣风：身前 90°、r480 里的苗圃花瓣被掀起，打着旋往外飘（花瓣可见半径 14 → 大弹）
func _petal_wind(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var a: float = (g.ppos - e.pos).angle()
	w_cone(e, a, PI / 4.0, 480.0, 0.8, 0.0, "花瓣风", {"track": 0.3})
	later(e, 0.8, _petal_wind_go.bind(e, a))
	return 1.6


func _petal_wind_go(e: Dictionary, a: float) -> void:
	var srcs: Array = [e.pos]
	var km = kingdoms()
	if km != null:
		for k in km.list:
			if k.kind == "nursery" and k.pos.distance_to(e.pos) < 480.0 and absf(angle_difference((k.pos - e.pos).angle(), a)) < PI / 4.0:
				srcs.append(k.pos)
	for s in srcs.slice(0, 5):
		for i in 7:
			var aa: float = a + lerpf(-PI / 4.0, PI / 4.0, i / 6.0)
			shot(e, s, aa, 170.0, 2, 0.12, {"turn": 1.2 if i % 2 == 0 else -1.2, "turn_until": 1.2, "life": 3.0})


## 回荡：花苞一圈绽开，花瓣弧外扩（150 px/秒，到 660），对着稳定设施的方向不开花 = 出口；0.8 秒后上一个落点再绽一次
func _echo_ring(e: Dictionary, _dir: Vector2, _d: float) -> float:
	_bloom(e, e.pos, "回荡")
	var pp: Vector2 = e.get("prev_pos", e.pos)
	later(e, 0.8, _bloom.bind(e, pp, ""))
	return 1.8


func _bloom(e: Dictionary, p: Vector2, nm: String) -> void:
	var gaps: Array = []
	for d in e.devs:
		gaps.append((d.pos - p).angle())
	if nm != "":
		e.move_name = nm
		e.move_t = g.t
	ring(e, p, 44, 150.0, 2, 0.13, gaps, 0.0, {"hold": 0.9, "life": 4.4})
	ring(e, p, 44, 115.0, 1, 0.10, gaps, PI / 44.0, {"hold": 1.2, "life": 5.6})   # 第二层慢一档、错半格（11-26 加密）


## 萌发：每块苗圃长出一朵紫花（10 秒），队长走到 160 内时花朝他喷一口花粉（30° 小扇，0.6 秒花抖）
func _sprout(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var km = kingdoms()
	if km == null:
		return -1.0
	var ns: Array = km.list.filter(func(k): return k.kind == "nursery").slice(0, 8)
	if ns.is_empty():
		return -1.0
	e.move_name = "萌发"
	e.move_t = g.t
	if not e.has("flowers"):
		e["flowers"] = []
	for k in ns:
		e.flowers.append({"pos": k.pos, "until": g.t + 10.0, "cd": g.t + 0.6})
	return 1.0


func _tick_flowers(e: Dictionary) -> void:
	if not e.has("flowers"):
		return
	e.flowers = e.flowers.filter(func(f): return float(f.until) > g.t)
	for f in e.flowers:
		if g.t >= float(f.cd) and f.pos.distance_to(g.ppos) < 160.0:
			f.cd = g.t + 2.5
			var w := w_cone(e, (g.ppos - f.pos).angle(), deg_to_rad(15.0), 170.0, 0.6, 0.10, "", {"lock": false})
			w.pos = f.pos
			w.follow = false


## ---- 二幕
## 裂隙：从落点到队长，地面裂开一道闪电状折线（半宽 22，0.9 / 0.5）
func _rift(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var tgt: Vector2 = g.ppos + g.pvel.limit_length(150.0) * 0.3
	var d: Vector2 = tgt - e.pos
	var n := 5
	var prev: Vector2 = e.pos
	for k in n:
		var q: Vector2 = e.pos + d * float(k + 1) / float(n) + d.orthogonal().normalized() * (60.0 if k % 2 == 0 else -60.0) * (0.0 if k == n - 1 else 1.0)
		var w := w_line(e, (q - prev).angle(), prev.distance_to(q) + 10.0, 22.0, 0.9, 0.16, "裂隙" if k == 0 else "", {"lock": k == 0})
		w.pos = prev
		prev = q
	var ext := w_line(e, d.angle(), 300.0, 22.0, 0.9, 0.16, "", {"lock": false})
	ext.pos = prev
	return 1.3


## 无之花：落点开一朵巨花（r360）：5 片花瓣是 5 个窄扇区，瓣间是安全道，按顺序凋落（0.3 秒一片）
func _flower(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var a0: float = (g.ppos - e.pos).angle() + PI / 5.0
	for k in 5:
		var w := w_cone(e, a0 + TAU * k / 5.0, deg_to_rad(18.0), 360.0, 1.0 + 0.3 * k, 0.13, "无之花" if k == 0 else "", {"lock": k == 0})
		w.follow = false
	return 2.4


## 回荡·双击：双击的两道刺线 0.8 秒后从上一个落点再射一次
func _echo_double(e: Dictionary, _dir: Vector2, _d: float) -> float:
	_double_from(e, e.pos, "回荡·双击", 0.12)
	var pp: Vector2 = e.get("prev_pos", e.pos)
	later(e, 0.8, func(): _double_from(e, pp, "", 0.12))
	return 1.8


## 剪枝：两条长刃（640、半宽 20）从队长两侧出现，绕身后 200 处的支点像剪刀一样转着合拢（60°/秒）；往远离支点的方向跑出剪口
func _scissor(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var back: Vector2 = (g.ppos - e.pos).normalized()
	var pivot: Vector2 = g.ppos + back * 200.0
	var a0: float = (g.ppos - pivot).angle()
	for s in [-1.0, 1.0]:
		var w := w_line(e, a0 + s * deg_to_rad(60.0), 640.0, 20.0, 0.9, 0.0, "剪枝" if s < 0 else "", {"lock": s < 0})
		w.pos = pivot
	e["scissor"] = {"pivot": pivot, "a0": a0, "t0": g.t + 0.9, "hit": false}
	return 2.2


func _tick_scissor(e: Dictionary) -> void:
	var sc = e.get("scissor")
	if not (sc is Dictionary) or g.t < float(sc.t0):
		return
	var el: float = g.t - float(sc.t0)
	if el > 1.0:
		e.erase("scissor")
		return
	var half: float = deg_to_rad(60.0) * (1.0 - el)
	for s in [-1.0, 1.0]:
		var a: float = float(sc.a0) + s * half
		var b: Vector2 = sc.pivot + Vector2.from_angle(a) * 640.0
		var q: Vector2 = Geometry2D.get_closest_point_to_segment(g.ppos, sc.pivot, b)
		if not sc.hit and q.distance_to(g.ppos) < 32.0:
			sc.hit = true
			hit_now(e, g.ppos, 1.0, 0.13)
	sc["half"] = half


## ---- 三幕
## 阖眼：全场苗圃同时枯萎爆开（r90，1.2 / 0.79）；稳定场里不受影响
func _close_eye(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var km = kingdoms()
	if km == null:
		return -1.0
	var ns: Array = km.list.filter(func(k): return k.kind == "nursery")
	if ns.is_empty():
		return -1.0
	var first := true
	for k in ns:
		w_circle(e, k.pos, 90.0, 1.2, 0.0, "阖眼" if first else "", {"lock": first})
		first = false
	var pts: Array = ns.map(func(k): return k.pos)
	later(e, 1.2, _close_eye_go.bind(e, pts))
	return 1.6


func _close_eye_go(e: Dictionary, pts: Array) -> void:
	if _in_field(e, g.ppos):
		return
	for p in pts:
		if g.combat.ground_d(g.ppos, p) < 90.0:
			hit_now(e, p, 90.0, 0.15)
			return


## 花雨：头顶撒下一团紫色花瓣，每片一边打旋一边往外飘（3 秒）
func _petal_rain(e: Dictionary, _dir: Vector2, _d: float) -> float:
	e.move_name = "花雨"
	e.move_t = g.t
	w_self(e, 60.0, 0.6, 0.0, "")
	for k in 40:
		later(e, 0.6 + 0.075 * k, func():
			var a: float = float((k * 97) % 360) * PI / 180.0
			shot(e, e.pos, a, 140.0, 2, 0.09, {"turn": 0.9 if k % 2 == 0 else -0.9, "life": 4.0}))
	return 3.8


## 维度回荡：6 个检查点连成的六边形上，花瓣串沿边绕圈（逆时针 120 px/秒），当前和上一个落点各一串
func _dim_echo(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var first := true
	for i in 6:
		var a: Vector2 = e.cps[i]
		var b: Vector2 = e.cps[(i + 1) % 6]
		var w := w_line(e, (b - a).angle(), a.distance_to(b), 18.0, 1.0, 0.0, "维度回荡" if first else "", {"lock": first})
		w.pos = a
		first = false
	var i0: int = int(e.cp)
	var i1: int = e.cps.find(e.get("prev_pos", e.pos))
	e["hex"] = {"t0": g.t + 1.0, "until": g.t + 7.0, "runners": [{"s": float(i0), "hit": false}, {"s": float(maxi(i1, (i0 + 3) % 6)), "hit": false}]}
	return 1.4


func _tick_hex(e: Dictionary, dt: float) -> void:
	var hx = e.get("hex")
	if not (hx is Dictionary) or g.t < float(hx.t0):
		return
	if g.t > float(hx.until):
		e.erase("hex")
		return
	var seg: float = CP_R   # 正六边形边长 = 外接圆半径
	for r in hx.runners:
		r.s = fmod(float(r.s) + 120.0 * dt / seg, 6.0)
		var i: int = int(r.s)
		var p: Vector2 = (e.cps[i] as Vector2).lerp(e.cps[(i + 1) % 6], r.s - float(i))
		r["pos"] = p
		for k in 4:
			var tail: Vector2 = p - ((e.cps[(i + 1) % 6] as Vector2) - (e.cps[i] as Vector2)).normalized() * 30.0 * k
			if g.combat.ground_d(g.ppos, tail) < 20.0 and g.t >= float(r.get("cd", 0.0)):
				r.cd = g.t + 1.0
				hit_now(e, tail, 20.0, 0.12)


## 播种·环：6 个检查点同时落圈（r60，1.0 / 0.79）并变成苗圃
func _sow_ring(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var first := true
	for p in e.cps:
		var w := w_circle(e, p, 60.0, 1.0, 0.14, "播种·环" if first else "", {"lock": first})
		w.cb = func(ww): _nursery(e, ww.pos, 60.0, 12.0)
		first = false
	return 1.4


## 眼中之园：从眼里抛出 5 团种子，沿抛物弧线依次落到队长附近（r45，0.9 / 0.64），落地变苗圃
func _eye_garden(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var tgt: Vector2 = g.ppos
	var side: Vector2 = (tgt - e.pos).orthogonal().normalized()
	for k in 5:
		var u: float = float(k) / 4.0
		var p: Vector2 = tgt + side * lerpf(-200.0, 200.0, u) + (tgt - e.pos).normalized() * (sin(PI * u) * -80.0)
		later(e, 0.25 * k, _seed_one.bind(e, p, k == 0))
	return 2.0


func _seed_one(e: Dictionary, p: Vector2, first: bool) -> void:
	var w := w_circle(e, p, 45.0, 0.9, 0.13, "眼中之园" if first else "", {"lock": first})
	w.cb = func(ww): _nursery(e, ww.pos, 50.0, 10.0)


## ---- 回荡段
## 三跳：连跳 3 个检查点（每跳都按跳跃过程，每跳落击 r250），3 个落点开始时一起亮出（标 1 / 2 / 3），每点停 1.0 秒
func _triple(e: Dictionary, _dir: Vector2, _d: float) -> float:
	if e.has("jump") or g.t > float(e.blink_t) - 3.0:
		return -1.0
	var q: Array = []
	var cur: int = int(e.cp)
	for k in 3:
		cur = (cur + 2 + k) % 6
		q.append(cur)
	e.next_cp = q[0]
	e["tri_q"] = q.slice(1)
	e.blink_t = g.t + 2.7
	e.erase("land_warned")
	e.move_name = "三跳"
	e.move_t = g.t
	for k in 2:
		w_circle(e, e.cps[int(q[k + 1])], LAND_R, 2.7 + 1.9 * (k + 1), 0.15, "", {"lock": false, "seq_no": k + 2})
	return 0.5


## 播种·终：全场 3 波落点雨（r45，0.9 / 0.64），落地全变苗圃
func _sow_all(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var c: Vector2 = center(e)
	for wv in 3:
		later(e, 0.6 * wv, func():
			for k in 10:
				var p: Vector2 = c + Vector2.from_angle(TAU * k / 10.0 + wv * 0.7) * (120.0 + 70.0 * ((k + wv) % 4))
				var w := w_circle(e, p, 45.0, 0.9, 0.15, "播种·终" if wv == 0 and k == 0 else "", {"lock": false})
				w.cb = func(ww): _nursery(e, ww.pos, 45.0, 12.0))
	return 2.6


## 花墓：第一条命倒下的地方留一朵巨花（r180），每 1.5 秒朝队长吐一片打旋的大花瓣
func _m_tomb(e: Dictionary, _dir: Vector2, _d: float) -> float:
	e["tomb"] = {"pos": e.pos, "next": g.t}
	return 0.5


func _tick_tomb(e: Dictionary) -> void:
	var tb = e.get("tomb")
	if not (tb is Dictionary) or e.get("coma", false):
		return
	if g.t >= float(tb.next):
		tb.next = g.t + 1.5
		if tb.get("named", false) == false:
			tb.named = true
			e.move_name = "花墓"
			e.move_t = g.t
		for s in [-0.35, 0.0, 0.35]:
			shot(e, tb.pos, (g.ppos - tb.pos).angle() + s, 150.0, 2, 0.12, {"turn": 0.6, "turn_until": 1.0, "life": 4.0})


func draw(e: Dictionary, cv) -> void:
	for p in e.get("cps", []):
		cv.draw_arc(p, 16.0, 0.0, TAU, 16, Color(0.75, 0.6, 0.95, 0.3), 1.5)
	if e.has("land_warned") and e.has("cps"):
		cv.draw_circle(e.cps[int(e.next_cp)], 22.0, Color(0.78, 0.6, 1.0, 0.5))
	for d in e.get("devs", []):
		var on: bool = float(d.field) > g.t
		cv.draw_rect(Rect2(d.pos - Vector2(10, 10), Vector2(20, 20)), Color(1.0, 0.85, 0.4, 0.9) if g.t >= float(d.cd) else Color(0.5, 0.5, 0.5, 0.7))
		if on:
			cv.draw_arc(d.pos, 170.0, 0.0, TAU, 48, Color(1.0, 0.9, 0.5, 0.5), 2.5)
		elif float(d.charge) > 0.0:
			cv.draw_arc(d.pos, 30.0, 0.0, TAU * clampf(1.0 - (float(d.charge) - g.t), 0.0, 1.0), 20, Color(1.0, 0.9, 0.5, 0.8), 3.0)
	var j = e.get("jump")
	if j is Dictionary:
		for k in 4:
			var u: float = clampf((g.t - float(j.t0) - 0.4) / 0.5 - 0.12 * (k + 1), 0.0, 1.0)
			var p: Vector2 = (j.from as Vector2).lerp(j.to, u) - Vector2(0, sin(PI * u) * 120.0)
			cv.draw_circle(p, 22.0, Color(0.78, 0.6, 1.0, 0.25 - 0.05 * k))
		cv.draw_circle(e.pos, 18.0, Color(0.2, 0.1, 0.3, 0.4))   # 地上投影
	for f in e.get("flowers", []):
		cv.draw_circle(f.pos, 12.0, Color(0.78, 0.55, 1.0, 0.85))
	var sc = e.get("scissor")
	if sc is Dictionary and sc.has("half"):
		for s in [-1.0, 1.0]:
			cv.draw_line(sc.pivot, sc.pivot + Vector2.from_angle(float(sc.a0) + s * float(sc.half)) * 640.0, Color(0.85, 0.7, 1.0, 0.9), 6.0)
	var hx = e.get("hex")
	if hx is Dictionary:
		for r in hx.runners:
			if r.has("pos"):
				cv.draw_circle(r.pos, 16.0, Color(0.8, 0.6, 1.0, 0.9))
	var tb = e.get("tomb")
	if tb is Dictionary:
		cv.draw_circle(tb.pos, 180.0, Color(0.7, 0.5, 0.95, 0.15))
		cv.draw_circle(tb.pos, 30.0, Color(0.8, 0.55, 1.0, 0.8))


## 机器人主轴：去离他下一个（或当前）落点最近、能启动的稳定设施；被苗圃缠住的设施来回过两次；稳定场开着时站在场里
func axis_do(e: Dictionary, p: Vector2) -> Vector2:
	if e.get("echo", false) or not e.has("devs"):
		return Vector2.INF
	# 下一个落点旁有设施、离眼纹亮起还有 0.4 秒以上：先去开稳定场（设施在落击圈里，眼纹亮了就进不去）
	var nxt: Vector2 = e.cps[int(e.get("next_cp", e.cp))]
	var until_warn: float = float(e.blink_t) - 2.7 - g.t
	for d in e.devs:
		if d.pos.distance_to(nxt) < 170.0 and until_warn > 0.4 and g.t >= float(d.cd) and float(d.charge) < 0.0 and float(d.field) < float(e.blink_t) + 1.0:
			if not (d.taps as Array).is_empty():
				return go_to(p, d.pos + Vector2(70.0 if int(g.t * 2.0) % 2 == 0 else -70.0, 0), 10.0)
			return go_to(p, d.pos, 12.0)
	var tgt: Vector2 = nxt if e.has("land_warned") else e.pos
	for d in e.devs:
		if float(d.field) > g.t and tgt.distance_to(d.pos) < 170.0:
			var q: Vector2 = d.pos + (tgt - d.pos) * 0.4
			if q.distance_to(tgt) < LAND_R + 20.0 and e.has("land_warned"):
				q = tgt + (d.pos - tgt).normalized() * (LAND_R + 30.0)   # 别站在落击圈里
			return go_to(p, q, 30.0)
	var best = null
	for d in e.devs:
		if g.t >= float(d.cd) and float(d.charge) < 0.0 and (best == null or d.pos.distance_to(tgt) < best.pos.distance_to(tgt)):
			best = d
	if best == null:
		return Vector2.INF
	if not (best.taps as Array).is_empty():
		var off: float = 70.0 if int(g.t * 2.0) % 2 == 0 else -70.0   # 缠住的设施：在点两边来回跑，0.6 秒后再踩一次
		return go_to(p, best.pos + Vector2(off, 0), 10.0)
	return go_to(p, best.pos, 12.0)


## 不理主轴：不碰稳定设施（离每台 80 以上）
func axis_ignore(e: Dictionary, p: Vector2) -> Vector2:
	for d in e.get("devs", []):
		if d.pos.distance_to(p) < 80.0:
			return (p - d.pos).normalized()
	return Vector2.INF
