extends Node
## 换分辨率后战斗镜头不变（10-27 用户「调整分辨率之后会出现缩放镜头视角的问题」，docs/50 §38）：
## 局内把窗口改成几种分辨率 / 比例，再在低 / 中档之间切换，每次镜头可见世界高（game.view_size().y）都要与进局时一致；
## 带 --touch 时按手机横屏比例再测一遍（可见高 585，iPhone 横屏 1 美术像素 = 4 物理像素）。
var failures := 0
var game: Node


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("CAM RESIZE: " + what)
		print("FAIL ", what)


func _ready() -> void:
	call_deferred("run")


func frames(n := 2) -> void:
	for i in n:
		await get_tree().process_frame


func view_h() -> float:
	return game.view_size().y


func run() -> void:
	var touch: bool = Cfg.touch_device()
	var sizes: Array = [Vector2i(2532, 1170), Vector2i(1560, 720), Vector2i(1792, 828), Vector2i(2340, 1080)] if touch else \
		[Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(1366, 768), Vector2i(1600, 900)]
	get_tree().root.size = sizes[0]
	await frames(2)
	game = load("res://game.tscn").instantiate()
	add_child(game)
	await frames(6)
	for i in 400:
		if game.state == game.S.PLAY:
			break
		game.state = game.S.PLAY
		await frames(1)
	game.invuln = 999.0
	await frames(4)
	var h0: float = view_h()
	var want: float = 585.0 if touch else 1080.0 / Cfg.cam_zoom()
	check(absf(h0 - want) < 1.0, "进局可见高 %.1f，期望 %.1f" % [h0, want])
	for q in ["mid", "low", "high"]:
		Cfg.set_quality_mode(q)
		Cfg.apply()
		for sz in sizes:
			get_tree().root.size = sz
			await frames(4)
			var h: float = view_h()
			check(absf(h - h0) < 1.0, "%s 档 窗口 %s：可见高 %.1f，进局 %.1f" % [q, str(sz), h, h0])
	# 全屏 / 窗口来回切（无头 / 屏幕外窗口里全屏可能不生效，只验证切换前后一致）。--touch 时跳过：本机显示器 16:9 全屏后不再是手机比例，会按桌面算
	var mode0 := DisplayServer.window_get_mode()
	if touch:
		mode0 = -1
	if mode0 >= 0:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		await frames(6)
		check(absf(view_h() - h0) < 1.0, "全屏后可见高 %.1f，进局 %.1f" % [view_h(), h0])
		DisplayServer.window_set_mode(mode0)
		await frames(6)
		check(absf(view_h() - h0) < 1.0, "回窗口后可见高 %.1f，进局 %.1f" % [view_h(), h0])
	if touch:
		# iPhone 横屏（2532×1170 物理像素）：1 美术像素正好 4 物理像素（整数，不糊）
		Cfg.set_quality_mode("mid")
		Cfg.apply()
		get_tree().root.size = Vector2i(2532, 1170)
		await frames(4)
		var px: float = 2.0 * game.cam.zoom.x * get_viewport().get_final_transform().x.x
		check(absf(px - 4.0) < 0.02, "iPhone 横屏 1 美术像素 %.3f 物理像素，期望 4" % px)
	Cfg.set_quality_mode("auto")
	print("CAM RESIZE failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
