extends Node
## Real enemy-demo AI and world drawing, with a fixed simulation clock for captures.
const D = preload("res://scripts/data.gd")
const A = preload("res://scripts/art.gd")

func _ready() -> void:
	var output := ""
	var ids: Array = D.ENEMIES.keys()
	var statuses := OS.get_cmdline_user_args().has("--enemy-animation-statuses")
	var phase_mode := 2 if OS.get_cmdline_user_args().has("--enemy-animation-phase2") else 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--enemy-animation-output="):
			output = arg.trim_prefix("--enemy-animation-output=")
		elif arg.begins_with("--enemy-animation-ids="):
			ids = Array(arg.trim_prefix("--enemy-animation-ids=").split(","))
	if output.is_empty():
		push_error("Missing enemy animation output")
		get_tree().quit(1)
		return
	for id in ids:
		if not D.ENEMIES.has(id):
			push_error("Unknown enemy: " + str(id))
			get_tree().quit(1)
			return
	var g = load("res://game.tscn").instantiate()
	g.demo_op = "mizuki"
	g.demo_enemy = str(ids[0])
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	for id in ids:
		var folder := output.path_join(str(id))
		DirAccess.make_dir_recursive_absolute(folder)
		g.demo_enemy = str(id)
		g.t = 100.0
		g.enemy_demo.configure(phase_mode)
		g.enemy_demo.reset()
		var records := []
		var state_names := ["raw", "pop", "stunned", "hit", "raw_atlas"]
		var saved_atlas = g.world.atlas
		for frame in (5 if statuses else 50):
			if statuses:
				var e: Dictionary = g.enemy_demo.subject
				e.stun = 1.0 if state_names[frame] == "stunned" else 0.0
				e.flash = 1.0 if state_names[frame] == "hit" else 0.0
				e.dcs = true
				g.world.atlas = saved_atlas if state_names[frame] == "raw_atlas" else null
			for step in 6:
				if not statuses:
					g._update(1.0 / 60.0)
				g.world.update_visuals(1.0 / 60.0)
				g.world.present_step()
			g.queue_redraw()
			g.fx_add.queue_redraw()
			g.fg.queue_redraw()
			g.hud.queue_redraw()
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var file: String = (state_names[frame] + ".png") if statuses else "frame_%03d.png" % frame
			var image := get_viewport().get_texture().get_image()
			if image.is_empty() or image.save_png(folder.path_join(file)) != OK:
				push_error("Enemy animation capture failed: " + str(id))
				get_tree().quit(1)
				return
			var e: Dictionary = g.enemy_demo.subject
			records.append({"file": file, "simulation_seconds": 0.0 if statuses else (frame + 1) / 10.0,
				"state": state_names[frame] if statuses else "natural_ai",
				"pop_applied": A.pop_wanted(e.tex), "atlas_enabled": g.world.atlas != null,
				"phase": e.phase, "move_name": e.get("move_name", ""), "wind": e.wind,
				"attack_active": g.t < float(e.get("atk_until", 0.0)),
				"position": [e.pos.x, e.pos.y], "dead": e.dead})
		var specs := {}
		for name in A.enemy_pixels:
			if g.tex.has(name):
				specs[name] = A.enemy_pixels[name]
		var f := FileAccess.open(folder.path_join("evidence.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify({"enemy": id, "phase_mode": phase_mode, "frames": records, "capture_fps": 10,
			"duration": 0.0 if statuses else 5.0, "loaded_pixel_metadata": specs, "visual_approved": false,
			"scope": "Production palette policy, stun/hit and direct/atlas rendering at the initial demo state. Pop is not forced when metadata preserves the palette." if statuses else "Actual enemy_demo initial 5 seconds, fixed 60 Hz simulation, production world/atlas and loaded textures. No forced pose, scale or texture overrides. Not every move or phase is covered."}, "\t"))
		f.close()
		g.world.atlas = saved_atlas
		# Boss/child back-references retain cached atlas textures after the demo ends.
		for enemy in g.enemies:
			enemy.erase("partner")
			enemy.erase("owner")
			enemy.erase("spawned_after")
			enemy.erase("core")
		print("ENEMY STATUS CAPTURE: " if statuses else "ENEMY ANIMATION CAPTURE: ", id, " 5 states" if statuses else " 50 frames / 5 seconds")
	# Release existing demo helper reference cycles after rendering has stopped.
	g.world._gc_sink = null
	var hud = g.hud_view
	for section in [hud.bars, hud.relics, hud.squad, hud.banners]:
		section.h = null
	g.queue_free()
	await get_tree().process_frame
	hud._layers.clear()
	await get_tree().process_frame
	get_tree().quit()
