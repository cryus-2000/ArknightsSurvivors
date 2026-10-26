extends Node
## 静默录帧夹具（docs/159）：紧急作战精英小队（endings._spawn_elites）从画面边缘压上来：红色描边 + 脚下红光 + 共用词缀。
## 游戏时间 5:30（中段怪池）。只推进敌人 AI / 预警 / 状态与紧急作战计时，不刷普通怪、队长不动、无敌。
## 用法：经 tools/godot_runner.py 启动，-- --capture=<绝对目录>；每 4 个 1/30 秒步长存一帧（7.5 fps 实时），共 30 秒；第 300 帧（10 秒）另存 shot.png
var vp: SubViewport
var g: Node
func _ready() -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(960, 540)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	g = load("res://game.tscn").instantiate()
	g.demo_op = "mizuki"
	vp.add_child(g)
	for i in 8:
		await get_tree().process_frame
	g.set_process(false)
	g.enemies = []
	g.warns = []
	g.fx = []
	g.mires.clear()
	g.t = 330.0
	var c0: Vector2 = g.ppos
	g.endg._spawn_elites()
	var dir := "res://../build/elite_squad"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture="): dir = a.substr(10)
	DirAccess.make_dir_recursive_absolute(dir)
	var n := 0
	var dt := 1.0 / 30.0
	for frame in 900:
		g.invuln = 99.0
		g.hp = g.max_hp
		g.lamp = 50.0
		g.t += dt
		g.enemies_sys.build_grid()
		g.enemies_sys.update(dt)
		g.tele.update_warns(dt)
		g.enemies_sys.update_status(dt)
		g.endg._tick_elites()
		if frame % 4 == 0:
			g.cam.position = c0
			g.cam.zoom = Vector2(0.75, 0.75)
			g.queue_redraw()
			await RenderingServer.frame_post_draw
			vp.get_texture().get_image().save_png("%s/f%04d.png" % [dir, n])
			if frame == 300:
				vp.get_texture().get_image().save_png("%s/shot.png" % dir)
			n += 1
	print("ELITE SQUAD CAPTURE frames=%d squad=%d pending=%d affix=%s types=%s" % [n, g.endg.elites.size(), g.endg.squad_pending.size(), g.endg.squad_affix, str(g.endg.elites.map(func(x): return x.type))])
	get_tree().quit(0)
