extends Node
## 静默截图夹具（docs/145 §5）：深溟奠基者踏地结算瞬间——地裂、冲击环、预警轮廓应画在队长 / 怪物之下。
## 用法：经 tools/godot_runner.py 启动本场景，-- --capture=<绝对路径>；--old 把 ground 标记去掉，画出改动前的层级作对照
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
	g.shocks = []
	g.t = 10.0
	var old := "--old" in OS.get_cmdline_user_args()
	var e: Dictionary = g.spawner.spawn_enemy("founder", g.ppos + Vector2(70, 10))
	e.hidden = false
	e.stun = 0.0
	e.flash = 0.0
	g.spawner.spawn_enemy("bone", g.ppos + Vector2(-60, 30)).hidden = false
	g.fx.append({"kind": "gcrack", "pos": e.pos, "r": 140.0, "life": 0.5, "max": 0.7, "col": Color(0.62, 0.46, 0.22), "enemy": true, "ground": not old,
		"opts": {"n": 11, "w0": Vector2(5.0, 7.0)}})
	g.shocks.append({"pos": e.pos, "r": 75.0, "maxr": 140.0, "dmg": 0.0, "hit": true, "boss": false, "src_type": "founder", "ground": not old})
	g.tele.warn(e, "circle", 0.9, {"follow": true, "r": 140.0, "act": "slam", "col": Color(1.0, 0.8, 0.5), "dmg": 1.0, "ground": not old})
	g.warns[-1].t = 0.6
	g.enemies_sys.build_grid()
	g.queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := "res://../build/founder_layer_capture.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture="): path = a.substr(10)
	var result: int = vp.get_texture().get_image().save_png(path)
	print("FOUNDER LAYER CAPTURE result=%d" % result)
	get_tree().quit(result)
