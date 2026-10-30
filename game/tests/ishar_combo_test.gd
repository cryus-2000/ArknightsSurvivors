extends Node
## 伊莎玛拉二阶段连段（docs/170）：每幕两组轮换、每组 ≤4 段、结束给破绽；打断 / 转幕清队列；
## 合唱环颂从连线海嗣发射、击杀源取消；泪雨大泪碎成小弹；抚愈之歌治疗连线海嗣、眩晕打断；同输入逐帧复现。
var g
var failures := 0
const DT := 0.05
const Bal = preload("res://scripts/core/balance.gd")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAIL ", label)

func _ready() -> void:
	# 图案 / 连段逻辑按原密度验：docs/201 §7 的加密旋钮（每波弹数 / 节奏 / 弹速倍率）在本测试里钉回 1
	Bal.v("boss/count_k_ishar", 1.0)
	for k in ["count_k_ishar", "tempo_k_ishar", "spd_all_k_ishar", "ishar_dense_k", "ishar_fast_k"]:
		Bal._data["boss"][k] = 1.0
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
	check(notes == 9 * 6, "killed source cancels its rings (%d notes)" % notes)
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
	check(g.ebullets.size() == 9 and nearest > 0.4, "first ring leaves the player's line between two bullets (%.2f)" % nearest)
	for i in 42:
		g.t += DT
		cards._emit_step(e)
	check(g.ebullets.size() == 18, "empty web falls back to two body rings (%d)" % g.ebullets.size())
	# 2b. 缺口按幕递进：二幕缺口每圈转动；三幕先停后射；第三次环颂最后一圈是整墙
	e = fresh(1)
	for sl in e.web:
		if sl.o != null: sl.o.dead = true
	g.ebullets.clear()
	cards.play(e, "合唱环颂", Vector2.RIGHT, 300.0)
	check(e.ishar_emits.size() == 2 and not is_equal_approx(float(e.ishar_emits[0].gc), float(e.ishar_emits[1].gc)), "act two gap rotates between rings")
	e = fresh(2)
	for sl in e.web:
		if sl.o != null: sl.o.dead = true
	g.ebullets.clear()
	cards.play(e, "合唱环颂", Vector2.RIGHT, 300.0)
	for i in 18:
		g.t += DT
		cards._emit_step(e)
	check(g.ebullets.size() == 10 and g.ebullets.all(func(b): return b.vel == Vector2.ZERO), "act three ring hangs before firing (%d)" % g.ebullets.size())
	for i in 14:
		g.t += DT
		cards._emit_step(e)
	check(g.ebullets.all(func(b): return b.vel.length() > 90.0), "held ring releases together")
	e.ishar_emits.clear()
	cards.play(e, "合唱环颂", Vector2.RIGHT, 300.0)
	e.ishar_emits.clear()
	cards.play(e, "合唱环颂", Vector2.RIGHT, 300.0)
	check(int(e.ishar_emits[-1].n) == 20 and int(e.ishar_emits[-1].gap) == 0, "every third chorus ends in a dash-through wall")
	# 3. 泪雨：大泪按时碎成 6 枚快弹
	e = fresh(1)
	g.ebullets.clear()
	cards.play(e, "泪雨", Vector2.RIGHT, 300.0)
	for i in 30:
		g.t += DT
		cards._emit_step(e)
	var big: int = g.ebullets.filter(func(b): return b.kind == "ishar_tear" and b.life > 0.0).size()
	check(big == 6 + e.eyes.size(), "body fan plus one drop per song eye (%d)" % big)
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
	check(beam.size() == 1 and float(beam[0].wid) >= 40.0 and beam[0].dur - beam[0].track >= 0.3, "big beam is wide and locks before firing")
	check(e.ishar_emits.filter(func(d): return d.kind == "sweep").size() == 1, "big beam hands over to a chasing sweep")
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
	check(is_equal_approx(g.combat.song_heal_mult(), 1.0 - preload("res://scripts/core/balance.gd").v("boss/ishar_song_heal_cut", 0.5)), "song zone cuts healing while inside")
	g.ppos = e.ishar_zones[0].pos + Vector2(0, 1500)
	g.t += 0.2
	cards._zone_step(e)
	check(g.combat.song_heal_mult() == 1.0, "healing recovers on leaving the zone")
	g.t += preload("res://scripts/core/balance.gd").v("boss/ishar_zone_linger", 4.0) + 1.0
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
	check(not e.ishar_sweep.is_empty(), "big beam is sweeping after its charge")
	# 追扫转速有上限：队长瞬移到正对面，一秒内光束最多转 boss/ishar_sweep_max
	var a0: float = float(e.ishar_sweep.ang)
	g.ppos = e.pos - Vector2.from_angle(a0) * 250.0
	for i in int(1.0 / DT):
		tick(e)
	var turned: float = absf(angle_difference(a0, float(e.ishar_sweep.ang)))
	check(turned > 0.05 and turned <= preload("res://scripts/core/balance.gd").v("boss/ishar_sweep_max", 0.5) + 0.01, "sweep chases the leader with a capped turn rate (%.2f)" % turned)
	for i in int(1.6 / DT):
		tick(e)
	check(e.ishar_sweep.is_empty() and g.fx.any(func(f): return f.kind == "ishar_beam_fade"), "big beam dissolves after the sweep")
	# 4. 抚愈之歌：歌声结束治疗连线海嗣；眩晕打断取消治疗
	e = fresh(0)
	var mob: Dictionary = e.web[0].o
	mob.hp = mob.maxhp * 0.3
	cards.force(e, "抚愈连段")
	tick_until(e, func(): return e.ishar_emits.any(func(d): return d.kind == "heal"))
	tick_n(e, int(3.0 / DT))
	check(mob.hp >= mob.maxhp, "heal song restores linked sea-born")
	e = fresh(0)
	mob = e.web[0].o
	mob.hp = mob.maxhp * 0.3
	cards.force(e, "抚愈连段")
	tick_until(e, func(): return e.ishar_emits.any(func(d): return d.kind == "heal"))
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
	# 连线护盾：每只连线海嗣一层；打空一层会碎、5 秒后回来；杀掉海嗣那层不回来
	tick_n(e, 2)
	var per: float = e.maxhp * Bal.v("boss/ishar_web_layer", 0.025)
	check(e.web_layers.size() == 3 and is_equal_approx(e.shield_hp, per * 3.0), "each linked sea-born adds one shield layer (%d, %.0f)" % [e.web_layers.size(), e.shield_hp])
	var hp_before: float = e.hp
	g.combat.hit("真实")
	g.combat.damage(e, per * 0.5)
	g.combat.damage(e, per * 0.7)
	tick_n(e, 1)
	check(e.web_sh_up == 2 and is_equal_approx(e.hp, hp_before), "shield absorbs damage and the top layer breaks first (%d)" % e.web_sh_up)
	tick_n(e, int(Bal.v("boss/ishar_layer_regen", 5.0) / DT) + 2)
	check(e.web_sh_up == 3, "a broken layer regrows while its sea-born stays linked")
	e.web[0].o.dead = true
	tick_n(e, 2)
	check(e.web_layers.size() == 2 and e.shield_hp <= per * 2.0 + 0.01, "killing a linked sea-born removes its layer")
	var wm: Dictionary = g.bai.boss("ishar")._web_mob(e, Vector2(200, 0), 0)
	check(not wm.has("web_of") and float(wm.shield_hp) < wm.maxhp * Bal.v("boss/ishar_web_shield", 0.4), "a walking sea-born is not linked and has no web shield yet")
	g.bai.boss("ishar")._web_link(e, wm)
	check(float(wm.shield_hp) >= wm.maxhp * Bal.v("boss/ishar_web_shield", 0.4) - 0.01, "linked sea-born carry a shield")
	# 10-31：空位补海嗣先在远处刷出、走到空位才连线（路上不给护盾层）
	e.web[0].o = null
	e.web[0].next = g.t
	e.eyes = [{"dead": false, "pos": e.pos, "id": -99}]
	e.reso_next = INF
	var sp0: Vector2 = e.pos
	tick_n(e, 1)
	var cm = e.web[0].get("come")
	check(cm is Dictionary and e.web[0].o == null and cm.pos.distance_to(sp0) > 300.0, "a refill spawns far away and walks in (not linked on spawn)")
	var lay0: int = e.web_layers.size()
	var d0: float = cm.pos.distance_to(g.bai.boss("ishar")._slot_pos(e, 0, int(e.web_cap)))
	tick_n(e, int((d0 / Bal.v("boss/ishar_web_walk", 170.0) + 0.5) / DT))
	check(e.web[0].get("come") == null and e.web[0].o is Dictionary and e.web_layers.size() > lay0, "it links (and adds a shield layer) only on reaching its slot (%.0f px walk)" % d0)
	e.eyes = []
	# 8. 三幕方案新招（docs/170b）：潮涡两臂螺旋并反向；侵蚀之泪先追后直；双束两条追扫在队长两侧、中间留缝
	e = fresh(1)
	g.ebullets.clear()
	cards.play(e, "潮涡", Vector2.RIGHT, 300.0)
	for i in int(3.6 / DT):
		g.t += DT
		cards._emit_step(e)
	check(g.ebullets.size() == 50, "vortex fires two arms for three seconds (%d)" % g.ebullets.size())
	e = fresh(2)
	g.ebullets.clear()
	cards.play(e, "侵蚀之泪", Vector2.RIGHT, 300.0)
	for i in int(1.6 / DT):
		g.t += DT
		cards._emit_step(e)
	check(g.ebullets.size() == 5 and g.ebullets.all(func(bl): return bl.home), "five seeking tears home in at first")
	for i in int(2.2 / DT):
		g.t += DT
		cards._emit_step(e)
	check(g.ebullets.all(func(bl): return not bl.home), "seeking tears stop homing and fly straight")
	e = fresh(2)
	g.warns.clear()
	cards.play(e, "大群之声·双束", Vector2.RIGHT, 300.0)
	tick_n(e, int(1.7 / DT))
	check(not e.ishar_sweep.is_empty() and not e.ishar_sweep2.is_empty(), "twin beam starts two sweeps")
	tick_n(e, int(2.0 / DT))
	var pa: float = (g.ppos - e.pos).angle()
	if not e.ishar_sweep.is_empty() and not e.ishar_sweep2.is_empty():
		var d1: float = angle_difference(pa, float(e.ishar_sweep.ang))
		var d2: float = angle_difference(pa, float(e.ishar_sweep2.ang))
		check(signf(d1) != signf(d2) and absf(d1) > 0.15 and absf(d2) > 0.15, "twin beams close in from both sides and leave a lane (%.2f, %.2f)" % [d1, d2])
	# 7. 判定点（enemy/bullet_core_hit，10-29）
	core_checks(cards)
	# 6. 同输入复现
	var a: Array = trace()
	var b: Array = trace()
	check(a == b and a.size() > 20, "identical input reproduces identical events (%d)" % a.size())
	print("ISHAR COMBO failures=", failures)
	g.queue_free()
	g = null
	await get_tree().process_frame
	get_tree().quit(0 if failures == 0 else 1)

func _probe(cards, e: Dictionary, d: float, boss := true) -> Dictionary:
	g.ebullets.clear()
	var b = cards._shot_ref(e, 0, g.ppos + Vector2(0, -14) + Vector2(d, 0), 0.0, 0.0, 8.0, 0.3, "ishar_tear", 5.0)
	b.boss = boss
	g.shots.update_ebullets(0.0)
	return b


func core_checks(cards) -> void:
	var on0: float = Bal.v("enemy/bullet_core_hit", 1.0)
	var e: Dictionary = fresh(1)
	var core: float = 8.0 * Bal.v("enemy/bullet_hit_scale", 0.6)
	Bal._data["enemy"]["bullet_core_hit"] = 0
	check(str(_probe(cards, e, core + 6.0).get("_die", "")) == "hit", "core hit off: old hitbox (r + 12) still hits at core + 6")
	Bal._data["enemy"]["bullet_core_hit"] = 1
	check(str(_probe(cards, e, core - 1.0).get("_die", "")) == "hit", "core hit on: bullet core hits the dot")
	check(str(_probe(cards, e, core + 6.0).get("_die", "")) != "hit", "core hit on: just outside the core misses")
	check(str(_probe(cards, e, core + 6.0, false).get("_die", "")) != "hit", "global rule: non-boss enemy bullets also hit only the core")
	e.dead = true
	check(str(_probe(cards, e, core + 6.0).get("_die", "")) != "hit", "global rule: applies outside boss fights too")
	e.dead = false
	Bal._data["enemy"]["bullet_core_hit"] = on0


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
