extends Node
## 10-21 结晶缩小：满地经验结晶的真实视口截图（--capture-out=子目录）。只摆掉落物，不跑玩法。

func _ready() -> void:
	var out_dir := "gem_size"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-out="): out_dir = arg.get_slice("=", 1)
	var output := ProjectSettings.globalize_path("res://../build/" + out_dir)
	DirAccess.make_dir_recursive_absolute(output)
	var g = load("res://game.tscn").instantiate()
	add_child(g)
	for i in 5: await get_tree().process_frame
	g.set_process(false)
	g.mode = g.Mode.PLAY
	g.state = g.S.PLAY
	g.sandbox = true
	g.t = 600.0
	g.xp_need = 1000000000.0
	for enemy in g.enemies: enemy.dead = true
	g.enemies.clear()
	var c: Vector2 = g.ppos
	var r := RandomNumberGenerator.new()
	r.seed = 7
	for i in 260:
		var p := c + Vector2(r.randf_range(-430.0, 430.0), r.randf_range(-240.0, 240.0))
		if p.distance_to(c) < 40.0: continue
		g.gems.append({"pos": p, "kind": "xp", "val": 5.0 if r.randf() < 0.15 else 1.0, "dead": false, "mag": false, "mag_t": 0.0,
			"z": 0.0, "vz": 0.0, "vel": Vector2.ZERO, "special": false, "landed": true, "age": 2.0, "seed": r.randf() * TAU, "out_t": 0.0})
	for frame in 3:
		g.world.update_visuals(1.0 / 60.0)
		g.world.present_step()
		g.queue_redraw()
		g.fx_add.queue_redraw()
		g.fg.queue_redraw()
		g.hud.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var im := get_viewport().get_texture().get_image()
	assert(im.save_png(output.path_join("gems.png")) == OK)
	print("GEM SIZE CAPTURE failures=0")
	get_tree().quit(0)
