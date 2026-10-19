extends Node

func _ready() -> void:
	var id := "logos"
	var diagnostic := OS.get_cmdline_user_args().has("--diagnostic")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-op="):
			id = arg.get_slice("=", 1)
	var output := ProjectSettings.globalize_path("res://../build/three_operator_art_1019/runtime_v2/" + id)
	DirAccess.make_dir_recursive_absolute(output)
	var g = load("res://game.tscn").instantiate()
	add_child(g)
	for i in 5:
		await get_tree().process_frame
	g.set_process(false)
	g.mode = g.Mode.PLAY
	g.state = g.S.PLAY
	g.sandbox = true
	g.t = 60.0
	g.invuln = 999.0
	g.xp_need = 1000000000.0
	var o = g.squad.get_op(id)
	assert(o != null)
	o.elite = 2
	o.sp = [-100000.0, -100000.0, -100000.0]
	o.cd = 10000.0
	var center: Vector2 = g.ppos
	for enemy in g.enemies:
		enemy.dead = true
	g.enemies.clear()
	var evidence := []
	var stages := {}
	var target: Dictionary = {}
	for frame in 720:
		var stage := "idle" if frame < 16 else ("run" if frame < 40 else ("attack" if frame < 96 else ("s1" if frame < 240 else ("s2" if frame < 440 else "s3"))))
		if frame == 40:
			g.ppos = center
			o.cd = 0.0
			target = g.spawner.spawn_enemy("stone", center + Vector2(220, 0))
			target.hp = 10000000.0
			target.max_hp = target.hp
			target.spd = 0.0
			g.enemies_sys.build_grid()
		if frame in [96, 240, 440]:
			o._sq_clear()
			o.attack_t = 0.0
			o.fire_t = -1.0
			o.cd = 0.0
			o.start_skill(target.pos, 0 if frame == 96 else (1 if frame == 240 else 2))
		# 展示收势时不追加普攻；正式游戏仍保留新攻击打断非阻塞收势的规则。
		if frame == 196 or frame == (480 if id == "eyjafjalla" else 684):
			o.cd = 10000.0
		for step in 3:
			o.sp = [-100000.0, -100000.0, -100000.0]
			if stage == "run":
				g.ppos += Vector2(150.0 / 60.0, 0)
			g._update(1.0 / 60.0)
			g.world.update_visuals(1.0 / 60.0)
			g.world.present_step()
		var st: Dictionary = o.anim_state()
		assert(not st.is_empty() and st.tex != null)
		var kind: String = str(st.kind)
		stages[stage + ":" + kind] = true
		evidence.append({"frame": frame, "stage": stage, "kind": kind, "pose": st.frame,
			"phase": o.sq_ph, "attack_left": o.attack_t, "fire_left": o.fire_t,
			"s1_left": o.skill_active_left(0), "s2_left": o.skill_active_left(1), "s3_left": o.skill_active_left(2),
			"s2_permanent": o.perm[1], "target_hp": target.get("hp", 0.0)})
		var selected := frame < 109 or (frame >= 176 and frame < 224) or (frame >= 240 and frame < 265) or (frame >= 350 and frame < 376) or (frame >= 400 and frame < 465) or (id == "eyjafjalla" and frame >= 480 and frame < 536) or frame >= 680
		if diagnostic or not selected:
			continue
		g.queue_redraw()
		g.fx_add.queue_redraw()
		g.fg.queue_redraw()
		g.hud.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var im := get_viewport().get_texture().get_image()
		assert(not im.is_empty() and im.save_png(output.path_join("f_%04d.png" % frame)) == OK)
	var file := FileAccess.open(output.path_join("evidence.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"operator": id, "frames": 720, "fps": 20, "stages": stages.keys(), "samples": evidence,
		"fixture": "automatic skill recharge disabled; attacks paused before endings to inspect optional nonblocking recovery"}))
	file.close()
	print("CAPTURE STAGES ", id, " ", stages.keys())
	var missing := []
	for pair in ["idle:idle", "run:run"]:
		if not stages.has(pair): missing.append(pair)
	if id == "logos":
		for pair in ["s1:skill_s1_loop", "s1:skill_s1_end", "s2:idle_s2", "s2:attack_s2", "s3:skill_s3_loop", "s3:skill_s3_end"]:
			if not stages.has(pair): missing.append(pair)
	elif id == "eyjafjalla":
		for pair in ["s3:skill_s3_loop", "s3:skill_s3_end"]:
			if not stages.has(pair): missing.append(pair)
	print("THREE OPERATOR ART CAPTURE ", id, " missing=", missing, " failures=", missing.size())
	for enemy in g.enemies:
		for key in ["partner", "owner", "spawned_after", "core"]:
			enemy.erase(key)
	o.hw.clear()
	o.lifecycle.clear()
	o.phases.clear()
	o.pfx.clear()
	o = null
	target = {}
	g.world._gc_sink = null
	var hud = g.hud_view
	for section in [hud.bars, hud.relics, hud.squad, hud.banners]:
		section.h = null
	g.queue_free()
	await get_tree().process_frame
	hud._layers.clear()
	Sfx.set_process(false)
	for player in Sfx.get_children():
		if player is AudioStreamPlayer:
			player.stop()
			player.stream = null
			player.queue_free()
	await get_tree().create_timer(0.1).timeout
	get_tree().quit(0 if missing.is_empty() else 1)
