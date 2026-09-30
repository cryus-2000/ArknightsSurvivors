extends Node
var g
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAIL ", label)
func _ready() -> void:
	g = load("res://game.tscn").instantiate()
	g.demo_op = "mizuki"
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	g.zone_frozen = false
	for kind in ["carmen", "iberia", "path", "bishop", "archon", "immortal", "paranoia", "knight_boss", "ishar", "izumik"]:
		g.t = 100.0
		g.enemies.clear()
		g.warns.clear()
		g.ebullets.clear()
		var e: Dictionary = g.spawner.new_enemy(kind, Vector2.ZERO)
		e.age = 3.0
		g.enemies.append(e)
		g.bosses = [e]
		if kind in ["ishar", "izumik"]:
			g.bai.setup_preview_phase2(e)
		g.ppos = Vector2(220, 0)
		var seen := {}
		var pending: Dictionary = {}
		for tick in 900:
			g.t += 0.1
			e.age += 0.1
			e.wind = maxf(0.0, e.wind - 0.1)
			e.cdt = maxf(0.0, e.cdt - 0.1)
			g.invuln = 100.0
			g.bai._boss_ai(e, 0.1, Vector2.RIGHT, 220.0)
			for w in g.warns:
				if w.has("pattern_id"):
					seen[w.pattern_id] = true
					pending = w.duplicate()
					check(w.dur >= 0.6 and w.dur - w.track >= 0.399, kind + " readable warning")
			g.bai._update_warns(0.1)
			g.enemies_sys.update_ebullets(0.1)
			g.ebullets = g.ebullets.filter(func(b): return b.life > 0.0)
			g.fx.clear()
		check(seen.size() >= 2, kind + " executes two distinct new attacks in real AI")
		if not pending.is_empty():
			g.warns.clear()
			pending.owner = e
			pending.done = false
			pending.t = 0.0
			g.warns.append(pending)
			e.dead = true
			var n: int = g.ebullets.size()
			g.bai._update_warns(10.0)
			check(g.ebullets.size() == n, kind + " death cancels queued attack")
	# Actual ring resolution: density, traversable gap, caps and feign cancellation.
	var ring_boss: Dictionary = g.spawner.new_enemy("paranoia", Vector2.ZERO)
	ring_boss.age = 20.0
	g.bai.setup_preview_phase2(ring_boss)
	ring_boss.pattern_next = g.t
	g.ppos = Vector2(400, 0)
	g.warns.clear()
	g.ebullets.clear()
	g.bai._boss_ai(ring_boss, 0.01, Vector2.RIGHT, 400.0)
	var rings: Array = g.warns.filter(func(w): return w.get("act", "") == "pattern_ring")
	check(rings.size() == 3, "final boss uses three offset ring waves")
	if not rings.is_empty():
		var w: Dictionary = rings[0]
		g.bai._warn_resolve(w)
		check(g.ebullets.size() >= 30, "enhanced ring actually emits dense bullets")
		for b in g.ebullets:
			check(absf(angle_difference(b.vel.angle(), w.gap_ang)) >= w.gap_half - 0.001, "gap remains empty")
			check(b.vel.length() >= 300 and b.boss, "fast bullets retain boss protections")
		var n: int = g.ebullets.size()
		ring_boss.coma = true
		g.bai._warn_resolve(w)
		check(g.ebullets.size() == n, "feigning boss cannot resolve another wave")
		ring_boss.coma = false
		g.combat.start_break(ring_boss, 3.0)
		g.bai._warn_resolve(w)
		check(g.ebullets.size() == n, "stagger break cancels queued wave")
		ring_boss.break_t = 0.0
		for repeat in 20:
			g.bai._warn_resolve(w)
		check(g.ebullets.size() <= 120, "one boss projectile cap")
		for source in 5:
			var next_boss: Dictionary = g.spawner.new_enemy("paranoia", Vector2.ZERO)
			w.owner = next_boss
			for repeat in 10:
				g.bai._warn_resolve(w)
		check(g.ebullets.size() <= 240, "total live projectile cap")
	# A distant melee Boss selects its ranged blade move rather than stalling.
	var melee: Dictionary = g.spawner.new_enemy("archon", Vector2.ZERO)
	melee.age = 20.0
	melee.pattern_next = g.t
	g.warns.clear()
	g.ebullets.clear()
	g.ppos = Vector2(500, 0)
	g.bai._boss_ai(melee, 0.01, Vector2.RIGHT, 500.0)
	check(g.warns.any(func(w): return w.get("act", "") == "pattern_fan"), "far melee uses blade volley")
	if not g.warns.is_empty():
		g.bai._warn_resolve(g.warns[0])
		check(g.ebullets.size() == 5 and g.ebullets[0].kind == "boss_blade", "blade volley has actual distinct projectiles")
	# Every grouped laser / column uses one common resolve time, including legacy attacks.
	for spec in [["paranoia", "burst", 0], ["bishop", "pillar", 0], ["bishop", "pattern_rain", 1], ["izumik", "pattern_rain", 1], ["ishar", "ishar_line", 1], ["ishar", "ishar_strike", 0]]:
		var caster: Dictionary = g.spawner.new_enemy(spec[0], Vector2.ZERO)
		caster.age = 20.0
		if caster.type == "paranoia":
			caster.phase = 2
			caster.cds = {"gaze": g.t + 100.0}
		if caster.type in ["ishar", "izumik"]:
			g.bai.setup_preview_phase2(caster)
			g.t += 2.0
			caster.wind = 0.0
		caster.pattern_next = g.t if spec[1] == "pattern_rain" else INF
		caster.pattern_cycle = spec[2]
		caster.ishar_cycle = spec[2]
		caster.ishar_next_at = g.t
		g.warns.clear()
		g.fx.clear()
		g.bai._boss_ai(caster, 0.01, Vector2.RIGHT, 220.0)
		var group: Array = g.warns.filter(func(w): return w.act == spec[1])
		check(group.size() >= 3, str(spec) + " actual grouped attack")
		if not group.is_empty():
			var time: float = group[0].dur
			check(group.all(func(w): return is_equal_approx(w.dur, time)), str(spec) + " synchronized warnings")
			g.invuln = 100.0
			g.bai._update_warns(time - 0.01)
			check(group.all(func(w): return not w.done), "none fire before shared warning")
			g.bai._update_warns(0.02)
			check(group.all(func(w): return w.done), "all fire together at shared deadline")
	# The protected human / learning phases must never schedule new hostile patterns.
	for kind in ["ishar", "izumik"]:
		var e: Dictionary = g.spawner.new_enemy(kind, Vector2.ZERO)
		e.age = 20.0
		g.warns.clear()
		g.bai._boss_ai(e, 0.01, Vector2.RIGHT, 200.0)
		check(not g.warns.any(func(w): return w.has("pattern_id")), kind + " phase one stays unchanged")
	# 原作机制转译：骑士冰线追击、接潮双体生命连接、伊莎玛拉之泪共鸣。
	g.t = 300.0
	g.warns.clear()
	g.fx.clear()
	var hunter: Dictionary = g.spawner.new_enemy("knight_boss", Vector2.ZERO)
	hunter.age = 20.0
	hunter.pattern_next = INF
	g.ppos = Vector2(260, 0)
	g.bai._boss_ai(hunter, 0.01, Vector2.RIGHT, 260.0)
	var ice_marks: Array = g.warns.filter(func(w): return w.act == "frost_track")
	check(ice_marks.size() == 1 and ice_marks[0].dur >= 0.6, "knight announces frost-track pursuit")
	if not ice_marks.is_empty():
		g.bai._warn_resolve(ice_marks[0])
		check(g.fx.any(func(f): return f.kind == "frost_track") and g.fx.any(func(f): return f.kind == "frost_step"), "knight frost track has ice art")
		g.t = float(hunter.get("hunt_follow_at", INF)) + 0.01
		hunter.wind = 0.0
		g.warns.clear()
		g.bai._boss_ai(hunter, 0.01, Vector2.RIGHT, 260.0)
		check(g.warns.any(func(w): return w.act == "dash" and w.name == "寒冷追击"), "knight follows marked track with charge")
	g.t = 400.0
	g.warns.clear()
	var priest: Dictionary = g.spawner.new_enemy("bishop", Vector2.ZERO)
	var fallen: Dictionary = g.spawner.new_enemy("archon", Vector2(240, 0))
	priest.age = 20.0
	priest.pattern_next = INF
	priest.partner = fallen
	fallen.partner = priest
	fallen.coma = true
	fallen.invuln = true
	g.ppos = Vector2(120, 0)
	g.bai._boss_ai(priest, 0.01, Vector2.RIGHT, 120.0)
	var links: Array = g.warns.filter(func(w): return w.act == "tide_link")
	check(links.size() == 1 and links[0].len > 200.0, "surviving tide boss counters along life link")
	if not links.is_empty():
		g.fx.clear()
		g.bai._warn_resolve(links[0])
		check(g.fx.any(func(f): return f.kind == "tide_link"), "life-link counter has dedicated tide art")
	g.t = 500.0
	g.warns.clear()
	var sea: Dictionary = g.spawner.new_enemy("ishar", Vector2.ZERO)
	var active_tear: Dictionary = g.spawner.new_enemy("tear", Vector2(110, 45))
	var quiet_tear: Dictionary = g.spawner.new_enemy("tear", Vector2(250, 0))
	active_tear.owner = sea
	quiet_tear.owner = sea
	g.enemies = [active_tear, quiet_tear]
	g.ppos = quiet_tear.pos
	g.bai.transform_ishar(sea)
	check(sea.get("tear_echoes", []).size() == 1 and active_tear.dead and quiet_tear.dead, "only unblocked tears leave a resonance trace")
	check(g.fx.any(func(f): return f.kind == "tide_link" and f.a == active_tear.pos), "unsuppressed tear visibly links at transformation")
	g.t += 2.0
	sea.wind = 0.0
	sea.ishar_next_at = g.t
	g.bai._ishar_phase2(sea, Vector2.RIGHT, 250.0)
	var echoes: Array = g.warns.filter(func(w): return w.act == "ishar_echo")
	check(echoes.size() == 1 and echoes[0].get("true", false), "hostile Ishar fires true-damage tear resonance")
	if not echoes.is_empty():
		g.fx.clear()
		g.bai._warn_resolve(echoes[0])
		check(g.fx.any(func(f): return f.kind == "tide_link"), "tear resonance draws linked wave")
	if DisplayServer.get_name() != "headless" and Cfg.dev_args().has("--capture-ui"):
		await capture_patterns()
	print("BOSS VARIETY failures=", failures)
	g.warns.clear()
	g.enemies.clear()
	g.bosses.clear()
	g.queue_free()
	g = null
	Sfx.set_process(false)
	await get_tree().create_timer(0.25, true, false, true).timeout
	for player in Sfx.get_children():
		if player is AudioStreamPlayer:
			player.stop()
			player.stream = null
			player.queue_free()
	await get_tree().create_timer(0.2, true, false, true).timeout
	get_tree().quit(0 if failures == 0 else 1)


func capture_patterns() -> void:
	g.demo_op = ""
	g.state = g.S.PLAY
	g.t = 600.0
	g.trial.active = true
	g.trial.started_at = g.t
	g.trial.saved_progress = {}
	g.ppos = Vector2(260, 100)
	g.ch.pos = g.ppos
	g.doc_pos = g.ppos + Vector2(40, 30)
	g.warns.clear()
	g.ebullets.clear()
	g.fx.clear()
	g.enemies.clear()
	var boss: Dictionary = g.spawner.new_enemy("ishar", Vector2(-130, 0))
	boss.age = 20.0
	g.enemies.append(boss)
	g.bosses = [boss]
	g.boss = boss
	g.final_boss = boss
	g.bai.setup_preview_phase2(boss)
	g.t += 2.0
	boss.wind = 0.0
	boss.pattern_next = g.t
	g.bai._boss_ai(boss, 0.01, Vector2.RIGHT, 390.0)
	var rings: Array = g.warns.duplicate()
	for i in rings.size():
		g.bai._warn_resolve(rings[i])
		g.enemies_sys.update_ebullets(0.3)
	g.world.update_visuals(0.0)
	g.cam.position = Vector2(50, 0)
	g.queue_redraw()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../build/ea_boss_dense_ring.png")
	g.warns.clear()
	g.ebullets.clear()
	g.fx.clear()
	boss.pattern_next = g.t
	boss.wind = 0.0
	g.bai._boss_ai(boss, 0.01, Vector2.RIGHT, 390.0)
	var blades: Array = g.warns.duplicate()
	for w in blades:
		g.bai._warn_resolve(w)
		g.enemies_sys.update_ebullets(0.25)
	g.queue_redraw()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../build/ea_boss_blade_volley.png")
	# 美术验收截图：真实 Boss 实体与新特效同屏。
	g.warns.clear()
	g.fx.clear()
	g.ebullets.clear()
	g.shocks.clear()
	g.lobs.clear()
	g.enemies.clear()
	var hunter: Dictionary = g.spawner.new_enemy("knight_boss", Vector2(-130, 0))
	hunter.age = 20.0
	hunter.pattern_next = INF
	g.enemies.append(hunter)
	g.bosses = [hunter]
	g.boss = hunter
	g.final_boss = hunter
	g.ppos = Vector2(230, 0)
	g.bai._boss_ai(hunter, 0.01, Vector2.RIGHT, 360.0)
	for w in g.warns.duplicate():
		if w.act == "frost_track":
			g.bai._warn_resolve(w)
	g.warns.clear()
	g.queue_redraw()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../build/ea_knight_frost_hunt.png")
	g.fx.clear()
	g.ebullets.clear()
	g.shocks.clear()
	g.lobs.clear()
	g.enemies.clear()
	var priest: Dictionary = g.spawner.new_enemy("bishop", Vector2(-130, 0))
	var fallen: Dictionary = g.spawner.new_enemy("archon", Vector2(180, 0))
	priest.age = 20.0
	priest.pattern_next = INF
	priest.partner = fallen
	fallen.partner = priest
	fallen.coma = true
	fallen.invuln = true
	g.enemies.append_array([priest, fallen])
	g.bosses = [priest, fallen]
	g.boss = priest
	g.final_boss = null
	g.ppos = Vector2(100, 0)
	g.bai._boss_ai(priest, 0.01, Vector2.RIGHT, 230.0)
	for w in g.warns.duplicate():
		if w.act == "tide_link":
			g.bai._warn_resolve(w)
	g.warns.clear()
	g.queue_redraw()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../build/ea_bishop_life_link.png")
	g.fx.clear()
	g.ebullets.clear()
	g.shocks.clear()
	g.lobs.clear()
	g.enemies.clear()
	var sea: Dictionary = g.spawner.new_enemy("ishar", Vector2(-130, 0))
	var tear: Dictionary = g.spawner.new_enemy("tear", Vector2(100, -80))
	tear.owner = sea
	g.enemies.append_array([sea, tear])
	g.bosses = [sea]
	g.boss = sea
	g.final_boss = sea
	g.ppos = Vector2(250, 0)
	g.bai.transform_ishar(sea)
	g.t += 2.0
	sea.wind = 0.0
	sea.ishar_next_at = g.t
	g.bai._ishar_phase2(sea, Vector2.RIGHT, 380.0)
	for w in g.warns.duplicate():
		if w.act == "ishar_echo":
			g.bai._warn_resolve(w)
	g.warns.clear()
	g.queue_redraw()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../build/ea_ishar_tear_echo.png")
