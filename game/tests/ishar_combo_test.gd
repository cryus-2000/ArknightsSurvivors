extends Node
## 伊莎玛拉二阶段连段（docs/170）：每幕两组轮换、每组 ≤4 段、结束给破绽；打断 / 转幕清队列；
## 合唱环颂从连线海嗣发射、击杀源取消；泪雨大泪碎成小弹；抚愈之歌治疗连线海嗣、眩晕打断；同输入逐帧复现。
var g
var failures := 0
const DT := 0.05

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAIL ", label)

func _ready() -> void:
	g = load("res://game.tscn").instantiate()
	g.demo_op = "mizuki"
	g.demo_enemy = "ishar"
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	var cards = g.bai.boss("ishar").cards()
	# 1. 各幕自然流程：两组连段轮换，破绽在每组之后
	for act in 3:
		var e: Dictionary = fresh(act)
		var started: Array = []
		var segs := {}
		var breaks := 0
		var prev_brk := 0.0
		var last := ""
		for i in int(48.0 / DT):
			tick(e)
			if e.get("card_live", false) and str(e.card_name) != last:
				last = str(e.card_name)
				started.append(last)
			if e.get("card_live", false):
				segs[last] = maxi(int(segs.get(last, 0)), 0)
			var brk: float = float(e.get("break_t", 0.0))
			if brk > prev_brk + 0.5:
				breaks += 1
			prev_brk = brk
			if not e.get("card_live", false):
				last = ""
		var want: Array = cards.CARDS[act].map(func(c): return c.name)
		check(started.size() >= 3, "act %d runs at least three combos in 48s (%s)" % [act, str(started)])
		check(started.size() >= 2 and started[0] == want[0] and started[1] == want[1], "act %d alternates its two combos (%s)" % [act, str(started)])
		check(breaks >= 2, "act %d grants a break after each combo (%d)" % [act, breaks])
		for c in cards.CARDS[act]:
			check(c.seq.size() <= 4, "combo %s has at most four segments" % c.name)
		check(g.ebullets.size() <= 340, "bullet count bounded (%d)" % g.ebullets.size())
	# 2. 合唱环颂：每个合唱源各发 3 圈；击杀一个源只取消它的圈
	var e: Dictionary = fresh(0)
	g.ebullets.clear()
	cards.play(e, "合唱环颂", Vector2.RIGHT, 300.0)
	var src: Array = g.bai.finals.choir_sources(e)
	check(src.size() == 3 and not is_same(src[0], e), "chorus rings come from three linked sea-born")
	check(e.ishar_emits.size() == 9, "three sources x three rings queued (%d)" % e.ishar_emits.size())
	src[0].dead = true
	for i in 80:
		g.t += DT
		cards._emit_step(e)
	var notes: int = g.ebullets.filter(func(b): return b.kind == "ishar_note").size()
	check(notes == 10 * 6, "killed source cancels its rings (%d notes)" % notes)
	# 无网：本体两圈
	e = fresh(0)
	for sl in e.web:
		if sl.o != null: sl.o.dead = true
	g.ebullets.clear()
	cards.play(e, "合唱环颂", Vector2.RIGHT, 300.0)
	for i in 18:
		g.t += DT
		cards._emit_step(e)
	# 首圈：主控方向落在两弹之间；第二圈错开半格（逼一次小侧移）
	var aim: float = (g.ppos - e.pos).angle()
	var nearest := INF
	for b in g.ebullets:
		nearest = minf(nearest, absf(angle_difference(b.vel.angle(), aim)))
	check(g.ebullets.size() == 10 and nearest > 0.15, "first ring leaves the player's line between two bullets (%.2f)" % nearest)
	for i in 42:
		g.t += DT
		cards._emit_step(e)
	check(g.ebullets.size() == 20, "empty web falls back to two body rings (%d)" % g.ebullets.size())
	# 3. 泪雨：大泪按时碎成 6 枚快弹
	e = fresh(1)
	g.ebullets.clear()
	cards.play(e, "泪雨", Vector2.RIGHT, 300.0)
	for i in 30:
		g.t += DT
		cards._emit_step(e)
	var big: int = g.ebullets.filter(func(b): return b.kind == "ishar_tear" and b.life > 0.0).size()
	check(big == 5 + e.eyes.size(), "body fan plus one drop per song eye (%d)" % big)
	for i in 60:
		g.t += DT
		cards._emit_step(e)
	var shards: int = g.ebullets.filter(func(b): return b.kind == "ishar_shard").size()
	check(shards == big * 6, "every live drop bursts into six shards (%d)" % shards)
	check(g.ebullets.filter(func(b): return b.kind == "ishar_shard").all(func(b): return b.vel.length() > 2.0 * 72.0), "shards are the fast layer")
	# 3b. 网鸣：歌声沿连线流到节点再散开；途中击破节点，这一路歌声消散
	e = fresh(0)
	g.ebullets.clear()
	cards.play(e, "网鸣", Vector2.RIGHT, 300.0)
	var nodes: Array = e.web.map(func(sl): return sl.o)
	for i in 16:
		g.t += DT
		cards._emit_step(e)
	var pulses: Array = g.ebullets.filter(func(b): return b.kind == "ishar_tear" and b.life > 0.0)
	check(pulses.size() == 3, "one song pulse flows to each linked node (%d)" % pulses.size())
	nodes[0].dead = true
	for i in 40:
		g.t += DT
		for b in g.ebullets:
			b.pos += b.vel * DT
		cards._emit_step(e)
	var fans: int = g.ebullets.filter(func(b): return b.kind == "ishar_note").size()
	check(fans == 2 * 4, "only surviving nodes scatter their four-note fans (%d)" % fans)
	check(g.ebullets.filter(func(b): return b.kind == "ishar_tear" and b.life > 0.0).size() == 2, "later waves skip the broken node; first-wave pulses end at their nodes")
	# 3c. 大群之声：粗光束预警锁定后结算，再持续 1 秒；侧移出光束不再受伤
	e = fresh(0)
	g.warns.clear()
	cards.play(e, "大群之声", Vector2.RIGHT, 300.0)
	var beam: Array = g.warns.filter(func(w): return w.name == "大群之声")
	check(beam.size() == 1 and float(beam[0].wid) >= 40.0 and beam[0].dur - beam[0].track >= 0.6, "big beam is wide with a long locked window")
	check(e.ishar_emits.filter(func(d): return d.kind == "hold").size() == 10, "big beam sustains for one second")
	# 3d. 歌声涟漪：三处地带预警后留 3 秒，站在里面持续受伤并减速；光束结算后留消散记录
	e = fresh(0)
	g.warns.clear()
	cards.play(e, "歌声涟漪", Vector2.RIGHT, 300.0)
	check(e.ishar_zones.size() == 3 and g.warns.filter(func(w): return w.act == "ishar_strike").size() == 3, "song ripple places three telegraphed zones")
	g.invuln = 0.0
	g.hp = g.max_hp
	g.ppos = e.ishar_zones[0].pos
	var hp0: float = g.hp
	for i in int(2.6 / DT):
		g.t += DT
		g.invuln = 0.0
		cards._zone_step(e)
	check(g.hp < hp0 and g.combat.slows.has("ishar_song"), "standing in a ripple zone hurts and slows")
	g.t += 4.0
	cards._zone_step(e)
	check(e.ishar_zones.is_empty(), "ripple zones expire")
	g.invuln = 999.0
	e = fresh(0)
	g.warns.clear()
	g.fx.clear()
	cards.play(e, "大群之声", Vector2.RIGHT, 300.0)
	for i in int(1.9 / DT):
		tick(e)
	check(not g.fx.any(func(f): return f.kind == "ishar_beam_fade"), "big beam does not fade while it is still firing")
	for i in int(1.2 / DT):
		tick(e)
	check(g.fx.any(func(f): return f.kind == "ishar_beam_fade"), "big beam dissolves after its hold")
	# 4. 抚愈之歌：歌声结束治疗连线海嗣；眩晕打断取消治疗
	e = fresh(0)
	var mob: Dictionary = e.web[0].o
	mob.hp = mob.maxhp * 0.3
	cards.force(e, "抚愈连段")
	tick_until(e, func(): return e.ishar_emits.size() > 0)
	tick_n(e, int(3.0 / DT))
	check(mob.hp >= mob.maxhp, "heal song restores linked sea-born")
	e = fresh(0)
	mob = e.web[0].o
	mob.hp = mob.maxhp * 0.3
	cards.force(e, "抚愈连段")
	tick_until(e, func(): return e.ishar_emits.size() > 0)
	e.stun = 0.5
	tick_n(e, 2)
	check(not e.card_live and e.ishar_emits.is_empty(), "stun cancels the remaining combo and queued song")
	tick_n(e, int(3.0 / DT))
	check(mob.hp < mob.maxhp, "interrupted song does not heal")
	# 5. 转幕清队列
	e = fresh(0)
	cards.force(e, "锁定连段")
	tick_n(e, 4)
	e.gates_passed = 1
	g.bai.boss("ishar").on_gate(e)
	check(not e.card_live and e.card_q.is_empty(), "act change clears the queued segments")
	# 7. 10-28 拉长：人形可受伤、打到血线截住并转化；连线回血不超过本幕起点；连线海嗣带护盾
	var Bal = preload("res://scripts/core/balance.gd")
	g.enemies.clear()
	g.warns.clear()
	var p1: Dictionary = g.spawner.spawn_enemy("ishar", Vector2(100, 0))
	check(p1.ishar_p1 and not p1.friendly and not p1.invuln, "human form is damageable when boss/ishar_p1_hit is on")
	g.ishar.step_ally(p1, 0.01)
	g.combat.hit("真实")
	for i in 40:
		g.combat.damage(p1, p1.maxhp * 0.03)
	var line: float = p1.maxhp * Bal.v("boss/ishar_p1_line", 0.85)
	check(p1.phase == 1 and is_equal_approx(p1.hp, line), "human-form damage stops at the transform line (%.0f / %.0f)" % [p1.hp, line])
	g.ishar.step_ally(p1, 0.01)
	check(p1.phase == 2 and not p1.ishar_p1 and is_equal_approx(p1.act_top, Bal.v("boss/ishar_p1_line", 0.85)), "reaching the line transforms early")
	e = fresh(0)
	e.act_top = 0.9
	e.hp = e.maxhp * 0.8
	var h0: float = e.hp
	tick_n(e, int(1.0 / DT))
	check(e.hp > h0, "linked sea-born heal her over time")
	e.hp = e.maxhp * 0.8995
	tick_n(e, int(2.0 / DT))
	check(e.hp <= e.maxhp * 0.9 + 0.01, "web healing never rises above the act start")
	var wm: Dictionary = g.bai.boss("ishar")._web_mob(e, Vector2(200, 0), 0)
	check(float(wm.shield_hp) >= wm.maxhp * Bal.v("boss/ishar_web_shield", 0.4) - 0.01, "linked sea-born carry a shield")
	# 6. 同输入复现
	var a: Array = trace()
	var b: Array = trace()
	check(a == b and a.size() > 20, "identical input reproduces identical events (%d)" % a.size())
	print("ISHAR COMBO failures=", failures)
	g.queue_free()
	g = null
	await get_tree().process_frame
	get_tree().quit(0 if failures == 0 else 1)

func fresh(act: int) -> Dictionary:
	g.t = 100.0
	g.zone_frozen = false
	g.warns.clear()
	g.enemies.clear()
	g.ebullets.clear()
	g.shocks.clear()
	g.bai.finals.hazards.clear()
	g.bai.token_owner = null
	g.invuln = 999.0
	g.ppos = Vector2(320, 40)
	var e: Dictionary = g.spawner.new_enemy("ishar", Vector2.ZERO)
	e.age = 20.0
	g.enemies.append(e)
	g.bosses = [e]
	g.boss = e
	g.bai.setup_preview_phase2(e)
	g.t += 1.0
	e.gates_passed = act
	e.cds = {"ishar_close": INF}   # 迫近是机制，不在本测试范围
	e.web = []
	for k in 3:
		var o: Dictionary = g.spawner.new_enemy("bone", Vector2.from_angle(k * 2.1) * 250.0)
		o.web_of = e
		g.enemies.append(o)
		e.web.append({"o": o, "next": INF})
	e.choir_next = INF
	if act >= 1:
		g.bai.boss("ishar")._eyes_spawn(e)
	return e

func tick(e: Dictionary) -> void:
	g.t += DT
	g.invuln = 999.0
	for k in ["wind", "cdt", "stun", "break_t"]:
		e[k] = maxf(0.0, float(e.get(k, 0.0)) - DT)
	g.bai._boss_ai(e, DT, (g.ppos - e.pos).normalized(), e.pos.distance_to(g.ppos))
	g.bai._update_warns(DT)
	g.shots.step(DT)
	g.ebullets = g.ebullets.filter(func(bl): return bl.life > 0.0)

func tick_n(e: Dictionary, n: int) -> void:
	for i in n:
		tick(e)

func tick_until(e: Dictionary, cond: Callable) -> void:
	for i in 200:
		if cond.call():
			return
		tick(e)

func trace() -> Array:
	var e: Dictionary = fresh(2)
	var out: Array = []
	for i in int(30.0 / DT):
		g.ppos = Vector2(320, 40) + Vector2.from_angle(i * 0.02) * 120.0
		tick(e)
		for w in g.warns:
			if w.t == 0.0 and is_same(w.owner, e):
				out.append([snappedf(g.t, 0.01), str(w.name), snappedf(float(w.get("ang", 0.0)), 0.001)])
		out.append(g.ebullets.size())
	return out
