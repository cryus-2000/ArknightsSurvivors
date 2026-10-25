extends Node
## 10-25 囊海爬行者「1/3 血无敌自爆」演示录像：队长站定，一只囊海爬行者走近，队伍自动输出；真实渲染视口逐帧存 PNG（每 2 帧一张 = 30 fps）。
## 用法：tools/probes/pocket_capture.py <out> [秒]

func _ready() -> void:
	var out_dir := "pocket_burst"
	var secs := 14.0
	var every := 2
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-out="): out_dir = arg.get_slice("=", 1)
		if arg.begins_with("--capture-secs="): secs = float(arg.get_slice("=", 1))
	var output := ProjectSettings.globalize_path("res://../build/" + out_dir)
	DirAccess.make_dir_recursive_absolute(output)
	var g = load("res://game.tscn").instantiate()
	add_child(g)
	for i in 5: await get_tree().process_frame
	g.set_process(false)
	g.mode = g.Mode.PLAY
	g.state = g.S.PLAY
	g.sandbox = true
	g.t = 60.0
	g.xp_need = 1000000000.0
	for enemy in g.enemies: enemy.dead = true
	g.enemies.clear()
	g.enemies_sys.build_grid()
	var pk: Dictionary = g.spawner.spawn_enemy("pocket", g.ppos + Vector2(260.0, -20.0))
	pk.maxhp = 900.0
	pk.hp = 900.0
	pk.burst_at = pk.maxhp * (2.0 / 3.0)
	pk.spd = 14.0
	var log := []
	for frame in int(secs * 60.0):
		g.hp = g.max_hp
		g.move_in = Vector2.ZERO
		g.enemies_sys.build_grid()
		g._update(1.0 / 60.0)
		g.world.update_visuals(1.0 / 60.0)
		g.world.present_step()
		if frame % 6 == 0:
			log.append({"frame": frame, "hp": snappedf(pk.hp, 0.1), "burst_w": snappedf(pk.get("burst_w", 0.0), 0.01), "dead": pk.dead})
		if frame % every != 0: continue
		g.queue_redraw()
		g.fx_add.queue_redraw()
		g.fg.queue_redraw()
		g.hud.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var im := get_viewport().get_texture().get_image()
		assert(im.save_png(output.path_join("f_%04d.png" % frame)) == OK)
	var file := FileAccess.open(output.path_join("log.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(log))
	file.close()
	print("POCKET CAPTURE done failures=0")
	get_tree().quit(0)
