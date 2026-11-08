extends Node
## 商人页版式截图（11-08 用户「商人界面要不要也想办法让商人露个脸」）：打开商人货架截一张 build/<--shots-out>/shop.png。
## 窗口尺寸用 --resolution；触屏加 --touch；--ins=l,t,r,b 模拟安全区（界面坐标，灵动岛 / B站胶囊）
var g
var ins: Array = []


func _fake_ins() -> void:
	if ins.size() == 4:
		var vis: Vector2 = get_viewport().get_visible_rect().size
		Cfg._ins_key = Vector3(vis.x, vis.y, Cfg.ui_k)
		Cfg._ins = ins.duplicate()


func _ready() -> void:
	var od := "shop_layout_shots"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots-out="):
			od = arg.get_slice("=", 1)
		elif arg.begins_with("--ins="):
			ins = Array(arg.get_slice("=", 1).split(",")).map(func(x): return float(x))
	var out := ProjectSettings.globalize_path("res://../build/" + od)
	DirAccess.make_dir_recursive_absolute(out)
	g = load("res://game.tscn").instantiate()
	add_child(g)
	for k in 90:
		await get_tree().process_frame
	g.state = g.S.PLAY
	g.pending_levelups = 0
	g.pending_chests = 0
	g.ingots = 40
	g.merchant = {"pos": g.ppos, "life": 60.0, "near": false, "purchases": 0}
	g.merchant_idx = 1
	g.shop_sys.open()
	for k in 50:
		_fake_ins()
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("shop.png"))
	print("SHOP SHOT panel=", g.panel.size, " ins=", Cfg.safe_insets(), " form=", Cfg.ui_form())
	# 第二张：第一张货品点开「详情」（手机）
	g.panel_ui.detail_i = 0
	for k in 10:
		_fake_ins()
		g.panel_tip.queue_redraw()
		for c in g.panel_box.get_children():
			c.queue_redraw()
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("shop_detail.png"))
	print("SHOP SHOT detail")
	get_tree().quit(0)
