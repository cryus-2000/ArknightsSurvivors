extends Node
## 静默录帧夹具（docs/158）：一圈大群按「慢慢来」分批出发（spawner._horde_loose），看后几批会不会一直站在原地。
## 圈里 4 只半血的深溟引痕者（狂暴、身上红光）。只推进敌人 AI / 预警 / 状态，不刷怪、队长不动、无敌。
## 用法：经 tools/godot_runner.py 启动，-- --capture=<绝对目录>；每 4 个 1/30 秒步长存一帧（7.5 fps 实时），共 40 秒
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
	for k in 28:
		var kind := "tracer" if k % 7 == 0 else "bone"
		var e: Dictionary = g.spawner.spawn_enemy(kind, c0 + Vector2.from_angle(k * TAU / 28.0) * 520.0)
		e.hidden = false
		if kind == "tracer":
			e.hp = e.maxhp * 0.45
		g.spawner._horde_loose(e, true)
	var dir := "res://../build/horde_depart"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture="): dir = a.substr(10)
	DirAccess.make_dir_recursive_absolute(dir)
	var n := 0
	var dt := 1.0 / 30.0
	var still := 0
	for frame in 1200:
		g.invuln = 99.0
		g.hp = g.max_hp
		g.lamp = 50.0
		g.t += dt
		g.enemies_sys.build_grid()
		g.enemies_sys.update(dt)
		g.tele.update_warns(dt)
		g.enemies_sys.update_status(dt)
		if frame % 4 == 0:
			g.cam.position = c0
			g.cam.zoom = Vector2(0.62, 0.62)
			g.queue_redraw()
			await RenderingServer.frame_post_draw
			vp.get_texture().get_image().save_png("%s/f%04d.png" % [dir, n])
			n += 1
	for e in g.enemies:
		if not e.dead and e.pos.distance_to(c0) > 400.0:
			still += 1
	print("HORDE DEPART CAPTURE frames=%d far_after_40s=%d alive=%d" % [n, still, g.enemies.filter(func(x): return not x.dead).size()])
	get_tree().quit(0)
