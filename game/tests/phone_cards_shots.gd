extends Node
## 11-09 手机截图：①「获得藏品」三选一（「国王的水晶」等一句话只剩代价 / 条件的藏品）；②精英化演出（手机也放实机演示）。
## 存 build/<--shots-out>/relic.png、relic_detail.png、elite.png。窗口尺寸用 --resolution；触屏加 --touch；--ins=l,t,r,b 模拟安全区
var g
var ins: Array = []
var ids: Array = ["251", "106", "183"]


func _fake_ins() -> void:
	if ins.size() == 4:
		var vis: Vector2 = get_viewport().get_visible_rect().size
		Cfg._ins_key = Vector3(vis.x, vis.y, Cfg.ui_k)
		Cfg._ins = ins.duplicate()


func _wait(n: int) -> void:
	for k in n:
		_fake_ins()
		await get_tree().process_frame


func _shot(out: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name))
	print("PHONE CARDS SHOT ", name, " ins=", Cfg.safe_insets(), " form=", Cfg.ui_form())


func _ready() -> void:
	var od := "phone_cards_shots"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots-out="):
			od = arg.get_slice("=", 1)
		elif arg.begins_with("--ins="):
			ins = Array(arg.get_slice("=", 1).split(",")).map(func(x): return float(x))
		elif arg.begins_with("--relics="):
			ids = Array(arg.get_slice("=", 1).split(","))
	var out := ProjectSettings.globalize_path("res://../build/" + od)
	DirAccess.make_dir_recursive_absolute(out)
	g = load("res://game.tscn").instantiate()
	add_child(g)
	await _wait(90)
	g.state = g.S.PLAY
	g.pending_levelups = 0
	g.pending_chests = 0
	var shown: Array = []
	for rid in ids:
		shown.append({"kind": "relic", "id": rid, "name": "【%s】%s" % [g.rfx.db.lane_name(rid), g.rfx.display_name(rid)], "desc": g.rfx.display_desc(rid), "full": g.rfx.display_desc(rid, true), "brief": g.rfx.display_brief(rid) if g.rfx.has_method("display_brief") else ""})
	g.panel_ui.show_choices("获得藏品", shown, "relic")
	await _wait(60)
	await _shot(out, "relic.png")
	g.panel_ui.detail_i = 0
	g.panel_tip.queue_redraw()
	await _wait(6)
	await _shot(out, "relic_detail.png")
	g.panel_ui.detail_i = -1
	g.panel.visible = false
	g.state = g.S.PLAY
	g.ch._elite_show(1)
	g.show_screen.open(g.show_queue.pop_front())
	await _wait(200)
	await _shot(out, "elite.png")
	get_tree().quit(0)
