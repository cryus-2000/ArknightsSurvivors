extends Node
## 10-23 德克萨斯普攻重设计演示录像（队长视角 / 队友视角各 8 秒）：真实渲染视口逐帧存 PNG（每 2 帧一张 = 30 fps 实时）。
## 敌人从两侧陆续走向队长；队长站着不动，只看普攻（不放技能、不冲刺）。
## 用法：tools/probes/texas_rework_capture.py <out> leader|mate

func _ready() -> void:
	var out_dir := "texas_rework"
	var secs := 8.0
	var every := 2
	var mode := "leader"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-out="): out_dir = arg.get_slice("=", 1)
		if arg.begins_with("--capture-secs="): secs = float(arg.get_slice("=", 1))
		if arg.begins_with("--capture-mode="): mode = arg.get_slice("=", 1)
	var output := ProjectSettings.globalize_path("res://../build/" + out_dir + "/texas_" + mode)
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
	var o = g.squad.get_op("texas")
	assert(o != null)
	for enemy in g.enemies: enemy.dead = true
	g.enemies.clear()
	g.enemies_sys.build_grid()
	var steps := int(secs * 60.0)
	var log := []
	var spawn_t := 0.0
	var k_spawn := 0
	for k in 3:   # 开场先放几只近的，免得前两秒空场
		g.spawner.spawn_enemy("bone", g.ppos + Vector2((150.0 + 40.0 * k) * (1.0 if k % 2 == 0 else -1.0), 10.0 * k))
	for frame in steps:
		o.sp = [-100000.0, -100000.0, -100000.0]   # 只看普攻
		g.hp = g.max_hp
		g.move_in = Vector2.ZERO
		spawn_t -= 1.0 / 60.0
		if spawn_t <= 0.0:
			spawn_t = 0.55
			var side := 1.0 if k_spawn % 2 == 0 else -1.0
			var ang := (k_spawn % 5 - 2) * 0.22
			g.spawner.spawn_enemy("bone", g.ppos + Vector2(side * 300.0, 0).rotated(ang))
			k_spawn += 1
		g.enemies_sys.build_grid()
		g._update(1.0 / 60.0)
		g.world.update_visuals(1.0 / 60.0)
		g.world.present_step()
		var st: Dictionary = o.anim_state()
		log.append({"frame": frame, "kind": st.get("kind", ""), "pose": st.get("frame", -1), "pos": [snappedf(o.pos.x, 0.1), snappedf(o.pos.y, 0.1)], "atk_n": o.atk_n})
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
	print("TEXAS REWORK CAPTURE ", mode, " done failures=0")
	get_tree().quit(0)
