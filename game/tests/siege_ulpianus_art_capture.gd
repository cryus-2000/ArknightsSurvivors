extends Node

func _ready() -> void:
	var id := "siege"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-op="): id = arg.get_slice("=", 1)
	var output := ProjectSettings.globalize_path("res://../build/siege_ulpianus_runtime/" + id)
	DirAccess.make_dir_recursive_absolute(output)
	var g = load("res://game.tscn").instantiate()
	add_child(g)
	for i in 5: await get_tree().process_frame
	g.set_process(false)
	g.mode = g.Mode.PLAY
	g.state = g.S.PLAY
	g.sandbox = true
	g.t = 60.0
	g.invuln = 999.0
	g.xp_need = 1000000000.0
	var o = g.squad.get_op(id)
	assert(o != null)
	for i in (2 if id == "ulpianus" else 6): o.advance()
	o.sp = [-100000.0, -100000.0, -100000.0]
	o.cd = 10000.0
	var center: Vector2 = g.ppos
	for enemy in g.enemies: enemy.dead = true
	g.enemies.clear()
	var target: Dictionary = {}
	var samples := []
	var kinds := {}
	for frame in 540:
		var stage := "idle" if frame < 16 else ("run" if frame < 40 else ("attack" if frame < 160 else ("s1" if frame < 240 else ("s2" if frame < 320 else "s3"))))
		if frame == 40:
			g.ppos = center
			o.cd = 0.0
			target = g.spawner.spawn_enemy("stone", center + Vector2(100, 0))
			target.hp = 10000000.0
			target.max_hp = target.hp
			target.spd = 0.0
			g.enemies_sys.build_grid()
		if frame in [160, 240, 320]:
			if frame == 160 and id == "ulpianus":
				for i in 4: o.advance()
			o.attack_t = 0.0
			o.fire_t = -1.0
			o.cd = 0.0
			if frame == 320:
				target.pos = o.pos + Vector2(180 if id == "ulpianus" else 80, 0)
				g.enemies_sys.build_grid()
				o.manual_pt = target.pos
			o.start_skill(target.pos, 0 if frame == 160 else (1 if frame == 240 else 2))
		for step in 3:
			o.sp = [-100000.0, -100000.0, -100000.0]
			if not target.is_empty() and o.hw.get("anchor", {}).is_empty() and float(o.hw.get("sg", {}).get("leap_t", -1.0)) < 0.0:
				target.pos = o.pos + Vector2(80, 0)
				target.kb = Vector2.ZERO
				g.enemies_sys.build_grid()
			if stage == "run": g.ppos += Vector2(150.0 / 60.0, 0)
			g._update(1.0 / 60.0)
			g.world.update_visuals(1.0 / 60.0)
			g.world.present_step()
		var st: Dictionary = o.anim_state()
		assert(not st.is_empty() and st.tex != null)
		kinds[str(st.kind)] = true
		samples.append({"frame": frame, "game_t": g.t, "stage": stage, "kind": st.kind, "pose": st.frame,
			"anchor_phase": o.hw.get("anchor", {}).get("phase", ""),
			"leap": o.hw.get("sg", {}).get("leap_t", -1.0), "fire_left": o.fire_t,
			"position": [o.pos.x, o.pos.y], "target_hp": target.get("hp", 0.0)})
		if id == "ulpianus" and frame in [48, 168, 332, 333, 338, 339]:
			var fx := []
			for f in g.fx + o.pfx:
				fx.append({"kind": f.kind, "name": f.get("name", ""), "scale": f.get("scale", f.get("sc", 0)), "r": f.get("r", 0), "life": f.life})
			samples[-1]["fx"] = fx
		var selected := frame < 100 or (frame >= 155 and frame < 190) or (frame >= 235 and frame < 275) or (frame >= 315 and frame < 370) or frame >= 480
		if not selected: continue
		g.queue_redraw()
		g.fx_add.queue_redraw()
		g.fg.queue_redraw()
		g.hud.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var im := get_viewport().get_texture().get_image()
		assert(not im.is_empty() and im.save_png(output.path_join("f_%04d.png" % frame)) == OK)
	var required := ["idle", "run", "attack", "leap_native", "heavy_attack"] if id == "siege" else ["idle", "run", "attack", "attack_s2", "tether_native", "zip_native", "whirl_native"]
	var missing := []
	for kind in required:
		if not kinds.has(kind): missing.append(kind)
	var file := FileAccess.open(output.path_join("evidence.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"operator": id, "fps": 20, "frames": 540, "kinds": kinds.keys(), "samples": samples, "missing": missing}))
	file.close()
	if id == "ulpianus":
		await capture_doctor(g, output)
	print("NATIVE ART CAPTURE ", id, " kinds=", kinds.keys(), " missing=", missing, " failures=", missing.size())
	for enemy in g.enemies:
		for key in ["partner", "owner", "spawned_after", "core"]: enemy.erase(key)
	o.hw.clear()
	o.native_motion.clear()
	o.lifecycle.clear()
	o.phases.clear()
	o.pfx.clear()
	o = null
	target = {}
	g.world._gc_sink = null
	var hud = g.hud_view
	for section in [hud.bars, hud.relics, hud.squad, hud.banners]: section.h = null
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

func capture_doctor(g, output: String) -> void:
	var samples := []
	for action in ["idle", "run", "death"]:
		g.state = g.S.DEAD if action == "death" else g.S.PLAY
		g.doc_moving = action == "run"
		g.world.anim_name = ""
		for i in (20 if action == "idle" else 16):
			g.world.update_doctor_anim(0.05)
			g.queue_redraw()
			g.fx_add.queue_redraw()
			g.fg.queue_redraw()
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var im := get_viewport().get_texture().get_image()
			assert(im.save_png(output.path_join("doctor_%s_%02d.png" % [action, i])) == OK)
			samples.append({"action": action, "i": i, "frame": g.sprite.frame, "height": g.sprite.texture.get_height(), "offset": [g.sprite.offset.x, g.sprite.offset.y]})
	var file := FileAccess.open(output.path_join("doctor_evidence.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"fps": 20, "scope": "Paused scene sampling of the real Doctor renderer", "samples": samples}))
	file.close()
