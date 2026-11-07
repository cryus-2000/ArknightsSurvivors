extends Node
## 事件页版式截图（11-08 用户 iPhone「事件页的排版不能跟电脑端一样吗？」）：依次打开几件事件各截一张 build/<--shots-out>/ev_<id>.png。
## 窗口尺寸用 --resolution；触屏加 --touch；--ins=l,t,r,b 模拟安全区（界面坐标，灵动岛 / B站胶囊）；--ids=a,b 换事件
var IDS: Array = ["opening", "heart"]
var g
var out := ""
var ins: Array = []


func _wait(sec: float) -> void:
	for k in int(sec * 60.0):
		await get_tree().process_frame


func _fake_ins() -> void:
	if ins.size() == 4:
		var vis: Vector2 = get_viewport().get_visible_rect().size
		Cfg._ins_key = Vector3(vis.x, vis.y, Cfg.ui_k)
		Cfg._ins = ins.duplicate()


func _ready() -> void:
	var od := "event_layout_shots"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots-out="):
			od = arg.get_slice("=", 1)
		elif arg.begins_with("--ids="):
			IDS = Array(arg.get_slice("=", 1).split(","))
		elif arg.begins_with("--ins="):
			ins = Array(arg.get_slice("=", 1).split(",")).map(func(x): return float(x))
	out = ProjectSettings.globalize_path("res://../build/" + od)
	DirAccess.make_dir_recursive_absolute(out)
	g = load("res://game.tscn").instantiate()
	add_child(g)
	await _wait(1.5)
	g.state = g.S.PLAY
	g.pending_levelups = 0
	g.pending_chests = 0
	for id in IDS:
		_fake_ins()
		g.ingots = 0 if id == "heart" else 30
		g.endg.open(id)
		for k in 50:
			_fake_ins()
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("ev_%s.png" % id))
		print("EVENT SHOT ", id, " panel=", g.panel.size, " ins=", Cfg.safe_insets(), " form=", Cfg.ui_form())
		g.panel.visible = false
		g.state = g.S.PLAY
		await _wait(0.2)
	get_tree().quit(0)
