extends Node
## 10-25 队友「平时跑动攻击、队长冲刺时一起冲」演示录像：队长向右跑，每 1.2 秒冲刺一次，队友（--squad）自己不突进；真实渲染视口逐帧存 PNG（每 2 帧一张 = 30 fps）。
## 用法：tools/probes/dash_follow_capture.py <out> [秒] [队长] [队友,…]

func _ready() -> void:
	var out_dir := "dash_follow"
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
	for k in 8:
		g.spawner.spawn_enemy("bone", g.ppos + Vector2(350.0 + 60.0 * k, -120.0 + 40.0 * (k % 4)))
	var log := []
	for frame in int(secs * 60.0):
		g.hp = g.max_hp
		g.ppos += Vector2.RIGHT * g.speed / 60.0   # 键盘输入在 _update 里每帧重读，这里直接按移速推队长（冲刺位移由游戏自己结算）
		g.facing = 1.0
		if frame % 72 == 36:
			g._try_dash()
		g.enemies_sys.build_grid()
		g._update(1.0 / 60.0)
		g.world.update_visuals(1.0 / 60.0)
		g.world.present_step()
		if frame % 6 == 0:
			var rel := {}
			for o in g.squad.ops:
				rel[o.id] = [snappedf(o.pos.x - g.ppos.x, 1.0), snappedf(o.pos.y - g.ppos.y, 1.0)]
			log.append({"frame": frame, "px": snappedf(g.ppos.x, 1.0), "dash": snappedf(g.dash_t, 0.01), "rel": rel})
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
	print("DASH FOLLOW CAPTURE done failures=0")
	get_tree().quit(0)
