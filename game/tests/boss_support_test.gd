extends Node
var failures := 0
func ok(value: bool, label: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + label)
func _ready() -> void:
	var g = load("res://game.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	g.bosses.clear()
	g.final_boss = null
	var mob = g.spawner.spawn_enemy("bone", Vector2(100, 100))
	var hp: float = mob.hp
	for kind in ["path", "bishop", "paranoia"]:
		var b = g.spawner.new_enemy(kind, Vector2.ZERO)
		g.bosses = [b]
		if kind == "paranoia": g.final_boss = b
		ok(g.spawner.mobs_stopped(), kind + " stops ordinary reinforcements")
		ok(not g.spawner.trickling(), kind + " does not trickle mobs")
		ok(not mob.dead and mob.hp == hp, "existing mob retained")
		b.dead = true
		ok(not g.spawner.mobs_stopped(), "ordinary waves resume after boss death")
	g.post.zone_amt = 0.8
	g.post.refresh_zone_guards(g)
	ok(g.post.zone_mask != null, "leader has a color guard")
	ok(g.post.zone_mask.size == Vector2i(g.get_viewport().get_visible_rect().size), "silhouette mask follows viewport dimensions")
	ok(Sfx.sfx_prio("op_exusiai_atk") == 2, "gunshots yield to boss cues")
	ok(Sfx.voice_group("op_exusiai_atk_b") == Sfx.voice_group("op_exusiai_atk_c"), "rotating guns share voice cap")
	ok(Sfx.voice_group("op_exusiai_big") == Sfx.voice_group("op_exusiai_s3"), "burst recordings share voice cap")
	check_ishar(g)
	check_audio()
	if DisplayServer.get_name() != "headless" and Cfg.dev_args().has("--capture-ui"):
		await capture_colors(g)
	print("BOSS SUPPORT failures=", failures)
	g.queue_free()
	get_tree().quit(0 if failures == 0 else 1)

func check_ishar(g) -> void:
	g.enemies.clear()
	g.ppos = Vector2.ZERO
	var boss: Dictionary = g.spawner.spawn_enemy("ishar", Vector2(100, 0))
	g.ishar.step_ally(boss, 0.01)
	ok(g.ishar.tears(boss).size() == 3, "three finite purification choices appear immediately")
	var mobs: Array = []
	for i in 4:
		mobs.append(g.spawner.spawn_enemy("bone", Vector2(200 + i * 20, 0)))
	var base_hp: float = mobs[0].maxhp
	var base_dmg: float = mobs[0].dmg
	var base_xp: float = mobs[0].xp
	boss.ally_attack_cd = 0.0
	g.ishar.step_ally(boss, 0.01)
	ok(mobs.filter(func(e): return e.elite).size() == 1, "one heal promotes at most one full-health mob")
	ok(is_equal_approx(mobs[0].maxhp, base_hp * 7.0) and is_equal_approx(mobs[0].dmg, base_dmg * 1.3) and is_equal_approx(mobs[0].xp, base_xp * 10.0), "promotion uses real elite HP/damage/XP multipliers")
	ok(not g.ishar.promote(boss, mobs[0]), "promotion cannot multiply an elite repeatedly")
	g.ishar.promote(boss, mobs[1])
	g.ishar.promote(boss, mobs[2])
	ok(not g.ishar.promote(boss, mobs[3]), "three active tears cap concurrent elites at three")
	mobs[0].hp = mobs[0].maxhp * 0.5
	mobs[0].dmg *= 1.2
	var first: Dictionary = g.ishar.tears(boss)[0]
	g.ppos = first.pos
	g.ishar.step_tear(first, 0.01)
	ok(first.purified and not mobs[0].elite and is_equal_approx(mobs[0].hp, base_hp * 0.5), "purification restores HP scale without healing damage")
	ok(is_equal_approx(mobs[0].dmg, base_dmg * 1.2) and is_equal_approx(mobs[0].xp, base_xp), "purification removes only its own modifiers")
	g.ppos += Vector2(300, 0)
	g.ishar.step_tear(first, 0.01)
	ok(first.purified and not g.ishar.promote(boss, mobs[3]), "purification is permanent and does not refill its promotion slot")
	g.bai.transform_ishar(boss)
	ok(first.dead and boss.eyes.size() == 2 and boss.tear_echoes.size() == 2, "uncleansed tears transfer once to hostile eyes and first-act echoes")
	for eye in boss.eyes:
		ok(not eye.friendly and not eye.invuln and eye.part and eye.xp == 0.0, "transferred eyes are damageable and cannot duplicate XP")
	var saved_enemies: Array = g.enemies
	g.enemies = [boss.eyes[0]]
	g.ppos = boss.eyes[0].pos
	g.invuln = 0.0
	var contact_hp: float = g.hp
	g.enemies_sys.update(0.1)
	ok(g.hp == contact_hp, "transferred song eye has no hidden legacy tear contact drain")
	g.enemies = saved_enemies
	g.warns.clear()
	boss.reso_next = 0.0
	g.bai.boss("ishar")._eye_step(boss)
	ok(g.warns.any(func(w): return is_same(w.get("source"), boss.eyes[0])), "resonance records its eye as cancellable source")
	boss.eyes[0].dead = true
	g.tele.update_warns(0.01)
	ok(not g.warns.any(func(w): return not w.done and is_same(w.get("source"), boss.eyes[0])), "destroying eye cancels its pending resonance")
	g.ishar.cleanup_blessings(boss)
	ok(not mobs[1].elite, "destroying a transferred eye releases its living elite")
	# Death sweep can remove an eye before the next boss gate callback.
	var last_eye: Dictionary = boss.eyes[1]
	last_eye.dead = true
	g.enemies.erase(last_eye)
	boss.gates_passed = 1
	g.bai.boss("ishar").on_gate(boss)
	ok(not mobs[2].elite, "phase gate releases already-swept dead eye before losing its reference")
	g.bai.boss("ishar").on_kill(boss)
	ok(not mobs[2].elite and boss.eyes.all(func(e): return e.dead), "boss death releases remaining promotions and removes eyes")
	# A true ordinary late-wave enemy must lose ordinary-only density/late/trim factors.
	g.t = 620.0
	var late_boss: Dictionary = g.spawner.spawn_enemy("ishar", Vector2(150, 0))
	g.ishar.spawn_tear(late_boss)
	g.spawner._norm = true
	var normal: Dictionary = g.spawner.spawn_enemy("bone", Vector2(200, 0))
	g.spawner._norm = false
	var scales: Vector3 = normal.get("normal_scale", Vector3.ONE)
	var before := Vector3(normal.maxhp, normal.dmg, normal.xp)
	var dk: float = normal.get("dk", 1.0)
	ok(g.ishar.promote(late_boss, normal), "late ordinary wave target can be converted")
	ok(is_equal_approx(normal.maxhp, before.x / scales.x * 7.0) and is_equal_approx(normal.dmg, before.y / scales.y * 1.3) and is_equal_approx(normal.xp, before.z / scales.z * 10.0), "ordinary-only scaling does not stack onto elite conversion")
	ok(normal.dk == 1.0, "elite conversion removes ordinary density drop weighting")
	g.ishar.release_blessing(g.ishar.tears(late_boss)[0])
	ok(is_equal_approx(normal.maxhp, before.x) and is_equal_approx(normal.xp, before.z) and is_equal_approx(normal.get("dk", 1.0), dk), "purification restores ordinary scales and reward weights")

func check_audio() -> void:
	for p in Sfx.players:
		p.stop()
	Sfx.ensure(["op_exusiai_atk", "op_exusiai_atk_b", "op_exusiai_atk_c", "op_exusiai_s3", "op_exusiai_big"])
	Sfx.last.clear()
	for name in ["op_exusiai_atk", "op_exusiai_atk_b", "op_exusiai_atk_c"]:
		Sfx.play(name, -20.0, 1.0, 0.0)
	ok(Sfx.players.filter(func(p): return p.playing and Sfx.voice_group(p.get_meta("sname", "")) == "exusiai_gun").size() == 2, "real rotating gun samples share two-voice cap")
	Sfx.play("op_exusiai_s3", -20.0, 1.0, 0.0)
	Sfx.play("op_exusiai_big", -20.0, 1.0, 0.0)
	ok(Sfx.players.filter(func(p): return p.playing and Sfx.voice_group(p.get_meta("sname", "")) == "exusiai_burst").size() == 1, "real burst samples share one-voice cap")
	for p in Sfx.players:
		p.stop()

func capture_colors(g) -> void:
	g.enemies.clear()
	g.bosses.clear()
	g.warns.clear()
	g.fx.clear()
	g.squad.ops.clear()
	g.state = g.S.PLAY
	g.demo_op = ""
	g.cam.position = Vector2.ZERO
	g.cam.zoom = Vector2(0.8, 0.8)
	g.knight.alive = true
	g.knight.pos = Vector2(-430, 0)
	for cid in ["lappland", "exusiai", "wisadel", "kaltsit"]:
		var op = preload("res://scripts/characters/character.gd").create(g, cid)
		op.slot = g.squad.ops.size()
		op.is_leader = op.slot == 0
		g.squad.ops.append(op)
		g.stats.define_all(op.stat_defs())
		op.pos = Vector2(-240 + op.slot * 160, 0)
		op.arrive_t = -1.0
	g.ch = g.squad.ops[0]
	g.ppos = g.ch.pos
	g.doc_pos = Vector2(-240, 60)
	g.world.update_visuals(0.0)
	g.post.zone_c = Vector2(0.5, 0.5)
	g.post.zone_r = 1.2
	for mode in [0, 1, 0]:
		g.post.zone_amt = 0.8 * mode
		g.post.refresh_zone_guards(g)
		g.queue_redraw()
		for frame in 3:
			for canvas in g.find_children("*", "CanvasItem", true, false):
				canvas.queue_redraw()
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://../build/friendly_colors_%d.png" % mode)
		if mode == 1:
			g.post.zone_mask.get_texture().get_image().save_png("res://../build/friendly_mask.png")
