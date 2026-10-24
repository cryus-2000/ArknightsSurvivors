extends Node
## 静默录帧夹具（docs/145 §4）：图鉴演示里的箱形恐鱼——现形尖叫（光环随它移动、期间不咬）→ 连咬两口。
## 用法：经 tools/godot_runner.py 启动本场景，-- --capture=<绝对目录>；每 2 个 1/30 秒步长存一帧 PNG（15 fps）
var vp: SubViewport
var g: Node
func _ready() -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(960, 540)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	g = load("res://game.tscn").instantiate()
	g.demo_op = "mizuki"
	g.demo_enemy = "mimic"
	vp.add_child(g)
	for i in 8:
		await get_tree().process_frame
	g.set_process(false)
	g.t = 100.0
	g.enemy_demo.reset()
	var e: Dictionary = g.enemy_demo.subject
	e.hp = 99999.0
	e.maxhp = 99999.0
	var dir := "res://../build/mimic_moves"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture="): dir = a.substr(10)
	DirAccess.make_dir_recursive_absolute(dir)
	var n := 0
	var nmax := 0.0
	for frame in 210:
		g.t += 1.0 / 30.0
		g.enemy_demo.step(1.0 / 30.0)
		nmax = maxf(nmax, g.nerve)
		if frame % 2 == 0:
			g.queue_redraw()
			await RenderingServer.frame_post_draw
			vp.get_texture().get_image().save_png("%s/f%03d.png" % [dir, n])
			n += 1
	print("MIMIC CAPTURE frames=%d nerve_max=%.1f screamed=%s" % [n, nmax, str(e.has("scream_t0"))])
	get_tree().quit(0)
