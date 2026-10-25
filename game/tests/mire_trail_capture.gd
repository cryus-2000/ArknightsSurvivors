extends Node
## 静默录帧夹具（docs/155）：4 只狂暴的深溟引痕者追着绕圈走的队长 60 秒，看拖痕溟痕怎么长、会不会顶满上限后停住。
## 只推进敌人 AI / 预警 / 状态（不刷怪、不升级）；队长无敌、匀速绕圈；灯火固定 50（不退散不逼近）。
## 用法：经 tools/godot_runner.py 启动，-- --capture=<绝对目录>；每 4 个 1/30 秒步长存一帧（7.5 fps 实时）
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
	g.t = 300.0
	var c0: Vector2 = g.ppos
	for k in 4:
		var e: Dictionary = g.spawner.spawn_enemy("tracer", c0 + Vector2.from_angle(k * TAU / 4.0) * 420.0)
		e.hidden = false
		e.hp = e.maxhp * 0.45
	var dir := "res://../build/mire_trail"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture="): dir = a.substr(10)
	DirAccess.make_dir_recursive_absolute(dir)
	var n := 0
	var dt := 1.0 / 30.0
	for frame in 1800:
		var ang: float = frame * dt * 0.35
		g.ppos = c0 + Vector2(cos(ang), sin(ang)) * 300.0
		g.ch.pos = g.ppos
		g.invuln = 99.0
		g.lamp = 50.0
		g.hp = g.max_hp
		g.t += dt
		g.enemies_sys.build_grid()
		g.enemies_sys.update(dt)
		g.tele.update_warns(dt)
		g.enemies_sys.update_status(dt)
		for e in g.enemies:
			e.hp = maxf(e.hp, e.maxhp * 0.45)
		if frame % 4 == 0:
			g.cam.position = c0
			g.cam.zoom = Vector2(0.62, 0.62)
			g.queue_redraw()
			await RenderingServer.frame_post_draw
			vp.get_texture().get_image().save_png("%s/f%04d.png" % [dir, n])
			n += 1
	print("MIRE TRAIL CAPTURE frames=%d mires=%d" % [n, g.mires.size()])
	get_tree().quit(0)
