extends Node
## Fixed starting encounter, real game update and drawing, five seconds at 60 Hz.
const D = preload("res://scripts/data.gd")

func _ready() -> void:
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scale-field-output="):
			output = arg.trim_prefix("--scale-field-output=")
	if output.is_empty():
		push_error("Missing scale-field output")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var g = load("res://game.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	g.t = 180.0
	g.invuln = 999.0
	var center: Vector2 = g.ppos
	var layout := [["bone", -200, -80], ["slider", 180, -90], ["stone", -150, 120],
		["runner", 230, 100], ["pocket", -280, 40], ["mother", 270, -20],
		["reaper", -40, -220], ["bone", 100, 190], ["brood", -90, 190],
		["slider", 70, -160], ["spitter", -300, -170], ["floater", 300, 200]]
	var evidence := []
	g.spawner._norm = true
	for item in layout:
		var e: Dictionary = g.spawner.spawn_enemy(item[0], g.map.push_out(center + Vector2(item[1], item[2]), 30.0))
		e.age = 2.1
		evidence.append({"id": e.type, "radius": e.r, "base_radius": e.r0,
			"draw_scale": D.ENEMIES[e.type].get("draw_scale", 1.0)})
	g.spawner._norm = false
	for frame in 50:
		for step in 6:
			g._update(1.0 / 60.0)
			g.world.update_visuals(1.0 / 60.0)
			g.world.present_step()
		g.queue_redraw()
		g.fx_add.queue_redraw()
		g.fg.queue_redraw()
		g.hud.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		if image.is_empty() or image.save_png(output.path_join("frame_%03d.png" % frame)) != OK:
			push_error("Scale field capture failed")
			get_tree().quit(1)
			return
	var file := FileAccess.open(output.path_join("evidence.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"initial_enemies": evidence, "fps": 10, "seconds": 5,
		"scope": "Fixed initial mixed encounter at t=180; normal spawn scale, real game simulation/HUD/drawing; invulnerable observer. Not an uncontrolled run or full move acceptance."}, "\t"))
	file.close()
	print("ENEMY SCALE FIELD: 50 frames")
	for enemy in g.enemies:
		for key in ["partner", "owner", "spawned_after", "core"]:
			enemy.erase(key)
	g.world._gc_sink = null
	var hud = g.hud_view
	for section in [hud.bars, hud.relics, hud.squad, hud.banners]:
		section.h = null
	g.queue_free()
	await get_tree().process_frame
	hud._layers.clear()
	await get_tree().process_frame
	Sfx.set_process(false)
	for player in Sfx.get_children():
		if player is AudioStreamPlayer:
			player.stop()
			player.stream = null
			player.queue_free()
	await get_tree().create_timer(0.1).timeout
	get_tree().quit()
