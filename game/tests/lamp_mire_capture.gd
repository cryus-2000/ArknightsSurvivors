extends Node
## 静默录帧夹具（docs/147）：灯火与溟痕。前半段灯火 100（身边溟痕慢慢褪去），后半段灯火 12（附近溟痕朝队长蔓延）。
## 只推进溟痕 / 状态（enemies_sys.update_status），不刷怪、不动队长。用法：经 tools/godot_runner.py 启动，-- --capture=<绝对目录>；15 fps
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
	g.t = 200.0
	g.mires.clear()
	for q in [[Vector2(-150, -40), 70.0], [Vector2(120, 60), 90.0], [Vector2(40, -150), 60.0], [Vector2(-260, 120), 80.0], [Vector2(300, -110), 75.0]]:
		g.mires.append({"pos": g.ppos + q[0], "r": q[1], "maxr": q[1], "life": 999.0, "seed": 1.7, "boss": false})
	var dir := "res://../build/lamp_mire"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture="): dir = a.substr(10)
	DirAccess.make_dir_recursive_absolute(dir)
	var n := 0
	for frame in 420:
		g.lamp = 100.0 if frame < 210 else 12.0
		g.t += 1.0 / 30.0
		g.enemies_sys.update_status(1.0 / 30.0)
		g.vfx.update(1.0 / 30.0)
		if frame % 2 == 0:
			g.queue_redraw()
			await RenderingServer.frame_post_draw
			vp.get_texture().get_image().save_png("%s/f%03d.png" % [dir, n])
			n += 1
	print("LAMP MIRE CAPTURE frames=%d mires=%d" % [n, g.mires.size()])
	get_tree().quit(0)
