extends Node
## 伊祖米克连携（docs/170）：每幕两组、每组 ≤4 段、收招破绽、转幕 / 眩晕清队列、灯柱吞弹、拦截通道、同 seed 复现
var g
var failures := 0
const DT := 0.05

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func _ready() -> void:
	g = load("res://game.tscn").instantiate()
	g.demo_op = "mizuki"
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	g.zone_frozen = true
	g.zone_state = 3
	g.zone_c = Vector2.ZERO
	g.zone_next_c = Vector2.ZERO
	g.zone_r = 650.0
	g.zone_next_r = 650.0
	var a: Dictionary = run_cards()
	var b: Dictionary = run_cards()
	check(a.log == b.log and a.hash == b.hash, "same seed reproduces card log and bullet trace")
	check_cards(a)
	check_interrupts()
	check_patterns()
	print("IZUMIK CARD failures=", failures)
	g.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if failures else 0)

func fresh() -> Dictionary:
	g.t = 100.0
	g.rng_enemy.seed = 271027
	g.warns.clear()
	g.bai.finals.hazards.clear()
	g.enemies.clear()
	g.ebullets.clear()
	g.fx.clear()
	g.shocks.clear()
	g.bai.token_owner = null
	var e: Dictionary = g.spawner.new_enemy("izumik", Vector2.ZERO)
	e.age = 20.0
	g.enemies = [e]
	g.bosses = [e]
	g.boss = e
	g.final_boss = e
	g.bai.setup_preview_phase2(e)
	e.lamps = []
	e.batch_next = INF   # 子代批次单独测；这里只看连携节奏
	g.ppos = Vector2(260, 0)
	return e

func tick(e: Dictionary, elapsed: float) -> void:
	g.t += DT
	g.invuln = 100.0
	e.wind = maxf(0.0, e.wind - DT)
	e.cdt = maxf(0.0, e.cdt - DT)
	e.break_t = maxf(0.0, float(e.get("break_t", 0.0)) - DT)
	e.kb = Vector2.ZERO
	# 以 105px/s（基础速度 70%）绕本体走圈
	g.ppos = Vector2.from_angle(elapsed * 105.0 / 260.0) * 260.0
	g.bai._boss_ai(e, DT, (g.ppos - e.pos).normalized(), e.pos.distance_to(g.ppos))
	g.tele.update_warns(DT)
	g.shots.update_ebullets(DT)
	g.ebullets = g.ebullets.filter(func(x): return x.life > 0.0)
	g.fx.clear()

## 三幕各跑 70 秒：记录宣言、每张卡出的段、收招
func run_cards() -> Dictionary:
	var e: Dictionary = fresh()
	var out := {"log": [], "hash": 0, "cards": [], "breaks": 0, "peak": 0, "acts": []}
	var cur: Dictionary = {}
	var last_break := 0.0
	var seen_warn: Array = []
	var trace := []
	for act in 3:
		if act > 0:
			e.gates_passed = act
			g.bai.boss("izumik").on_gate(e)
		e.hp = e.maxhp * [0.8, 0.55, 0.3][act]
		var pa := {"act": act, "low": 0.0, "total": 0.0, "peak": 0, "breaks": []}
		out.acts.append(pa)
		for i in int(70.0 / DT):
			var elapsed: float = act * 70.0 + i * DT
			tick(e, elapsed)
			var nm: String = str(e.get("izu_card", ""))
			if nm != "" and float(e.get("izu_rise_t", -1.0)) == g.t:
				cur = {"name": nm, "act": act, "segs": [], "t": snappedf(elapsed, 0.01)}
				out.cards.append(cur)
				out.log.append([nm, cur.t])
			for w in g.warns:
				if is_same(w.owner, e) and w.name != "" and w.dmg > 0.0 and not seen_warn.any(func(o): return is_same(o, w)):
					seen_warn.append(w)
					if not cur.is_empty(): cur.segs.append(str(w.name))
			var em: Dictionary = e.get("izu_emit", {})
			if not em.is_empty() and float(em.t0) == g.t and not cur.is_empty():
				cur.segs.append(str(em.kind))
			var brk: float = float(e.get("break_t", 0.0))
			if brk > last_break + 0.1:
				out.breaks += 1
				pa.breaks.append(snappedf(brk, 0.01))
				out.log.append(["break", snappedf(elapsed, 0.01)])
			last_break = brk
			out.peak = maxi(out.peak, g.ebullets.size())
			# 低压可输出（docs/170 §9）：贴在本体身边（以本体为中心一屏 1280×720）同屏敌弹 < 20，且没有未结算的伊祖米克有伤预警、没有移动水墙
			var near := 0
			for b in g.ebullets:
				if b.life > 0.0 and absf(b.pos.x - e.pos.x) < 640.0 and absf(b.pos.y - e.pos.y) < 360.0: near += 1
			pa.peak = maxi(pa.peak, near)
			var busy: bool = g.warns.any(func(w): return is_same(w.owner, e) and not w.done and w.dmg > 0.0) or g.bai.finals.hazards.any(func(h): return is_same(h.owner, e))
			pa.total += DT
			if near < 20 and not busy: pa.low += DT
			if i % 10 == 0:
				var s := 0.0
				for b in g.ebullets: s += b.pos.x * 0.37 + b.pos.y
				trace.append(snappedf(s, 0.01))
	out.hash = hash(trace)
	return out

func check_cards(r: Dictionary) -> void:
	var by_act := [{}, {}, {}]
	for i in r.cards.size():
		var c: Dictionary = r.cards[i]
		by_act[c.act][c.name] = true
		if i + 1 < r.cards.size() and r.cards[i + 1].act != c.act or i + 1 == r.cards.size():
			continue   # 每幕最后一组可能被转幕 / 测试窗口截断
		check(c.segs.size() >= 2 and c.segs.size() <= 4, "%s segments 2..4 (%s)" % [c.name, c.segs])
	for act in 3:
		check(by_act[act].size() >= 2, "act %d shows two combos %s" % [act, by_act[act].keys()])
	check(int(r.breaks) >= 6, "each finished combo grants recovery (%d)" % r.breaks)
	check(int(r.peak) <= 120, "bullet peak <= 120 (%d)" % r.peak)
	for pa in r.acts:
		var frac: float = pa.low / maxf(0.01, pa.total)
		check(frac >= 0.38, "act %d low-pressure share %.2f >= 0.38" % [pa.act, frac])
		print("IZUMIK PRESSURE act=%d low=%.2f peak_on_screen=%d breaks=%s" % [pa.act, frac, pa.peak, pa.breaks])
	print("IZUMIK CARDS ", JSON.stringify(r.cards))

func check_interrupts() -> void:
	var s = g.bai.boss("izumik")
	var e: Dictionary = fresh()
	s.force_move(e, "迁徙潮汐", Vector2.RIGHT, 260.0)
	check(e.izu_card == "迁徙潮汐" and float(e.izu_rise_t) == g.t, "forced combo starts with a wind-up")
	for i in 40: tick(e, i * DT)
	check(not g.ebullets.is_empty(), "first segment emits bullets")
	e.gates_passed = 1
	s.on_gate(e)
	check(e.izu_card == "" and e.izu_queue.is_empty() and e.izu_emit.is_empty(), "gate clears queue")
	for i in 60: tick(e, i * DT)
	check(e.izu_card in ["解读螺旋", "习得变形"], "next act starts an act-two combo (%s)" % e.izu_card)
	e.stun = 1.0
	tick(e, 0.0)
	check(e.izu_card == "" and float(e.break_t) <= 0.0, "external stun ends the combo without granting recovery")
	e.stun = 0.0

func check_patterns() -> void:
	var s = g.bai.boss("izumik")
	# 拦截通道：子代来向落在两条水流之间
	var e: Dictionary = fresh()
	var o: Dictionary = g.spawner.spawn_enemy("offspring", Vector2(0, 520))
	e.batch = [o]
	s.force_move(e, "潮汐相位流", Vector2.RIGHT, 260.0)
	tick(e, 0.0)
	var lane: float = PI * 0.5
	for b in g.ebullets:
		check(absf(angle_difference(b.vel.angle(), lane)) > 0.5, "stream leaves the interception lane open")
	o.dead = true
	# 习得弹：停住再转向
	e = fresh()
	s.force_move(e, "习得弹", Vector2.RIGHT, 260.0)
	for i in int(1.2 / DT): tick(e, 0.0)
	var frozen: Array = g.ebullets.filter(func(b): return b.get("izu", "") == "learn" and b.izu_t > 0.95 and b.izu_t < 1.35)
	check(not frozen.is_empty() and frozen.all(func(b): return b.vel == Vector2.ZERO), "learned bullets pause")
	for i in int(0.8 / DT): tick(e, 0.0)
	check(g.ebullets.any(func(b): return b.has("izu_aim") and b.vel.length() > 50.0), "learned bullets re-aim and accelerate")
	# 层数越多弹越多
	e = fresh()
	e.izu_stacks = 4
	s.force_move(e, "习得弹", Vector2.RIGHT, 260.0)
	tick(e, 0.0)
	check(g.ebullets.size() == 12, "absorption stacks deform the learned ring (%d)" % g.ebullets.size())
	# 三幕灯柱吞弹
	e = fresh()
	e.gates_passed = 2
	e.lamp_r = 120.0
	e.lamps = [{"pos": Vector2(200, 0), "lit": true, "prog": 1.0}]
	s.force_move(e, "回流弹", Vector2.RIGHT, 260.0)
	for i in int(2.0 / DT): tick(e, 0.0)
	var inside: Array = g.ebullets.filter(func(b): return b.life > 0.0 and g.combat.ground_d(b.pos, Vector2(200, 0)) < 110.0)
	check(inside.is_empty(), "lit lamp absorbs bullets")
	# 子代共鸣从活子代发出；子代死了这一路不再发
	e = fresh()
	var c1: Dictionary = g.spawner.spawn_enemy("offspring", Vector2(-400, 0))
	var c2: Dictionary = g.spawner.spawn_enemy("offspring", Vector2(0, -400))
	e.batch = [c1, c2]
	s.force_move(e, "子代共鸣", Vector2.RIGHT, 260.0)
	c2.dead = true
	for i in int(2.0 / DT): tick(e, 0.0)
	var fans: int = g.ebullets.filter(func(b): return b.get("izu", "") == "fan").size()
	check(fans == 9, "only living offspring resonate (%d bullets)" % fans)
	# 批次子代只走路：无接触伤害、不出横扫、不放自己的孢子环
	e = fresh()
	e.batch_next = g.t
	g.bai._boss_ai(e, DT, Vector2.RIGHT, 260.0)
	check(not e.batch.is_empty() and e.batch.all(func(o): return o.dmg == 0.0 and o.extra_next == INF and o.nova_cd == INF), "batch offspring are harmless walkers")
	# 海流牵引：把人往中心拖，但慢于步行；中心结算后不再拖
	e = fresh()
	g.ppos = Vector2(200, 0)
	s.force_move(e, "海流牵引", Vector2.RIGHT, 200.0)
	var w0: Dictionary = g.warns.filter(func(w): return w.get("skin", "") == "current")[0]
	g.ppos = w0.pos + Vector2(200, 0)
	var p0: Vector2 = g.ppos
	for i in 20:
		g.t += DT
		w0.t = float(w0.t) + DT
		s._current_step(e, DT)
	var moved: float = p0.distance_to(g.ppos)
	check(moved > 10.0 and moved < 70.0 * 20 * DT + 0.01 and g.ppos.distance_to(w0.pos) < 200.0, "current pulls toward center slower than walking (%.1f px / 1 s)" % moved)
	# 潮痕：海流牵引结算后在涌起点留一块伊祖米克溟痕；受伤倍率连携期 < 1、破绽期 > 1
	g.mires.clear()
	for i in int(3.0 / DT): tick(e, 0.0)
	check(g.mires.any(func(m): return m.get("izu", false) and m.pos.distance_to(w0.pos) < 70.0), "current leaves a tide mire at its center")
	e.break_t = 0.0
	var tm0: float = s.taken_mult(e)
	e.break_t = 1.0
	check(tm0 < 1.0 and s.taken_mult(e) > 1.0, "taken mult pushes damage into breaks (%.2f / %.2f)" % [tm0, s.taken_mult(e)])
	e.break_t = 0.0
