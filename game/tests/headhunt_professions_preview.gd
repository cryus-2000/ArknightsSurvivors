extends Node

func _ready() -> void:
	var host = preload("res://scripts/screens/hunt_host.gd").new()
	add_child(host)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Cfg.roster_tickets = {"hunt": 5}
	host.hh.open = true
	host.hh.browse = true
	host.hh.mode = "class"
	host.hh.choices = host.hh.CLASS_ORDER.duplicate()
	host.hh._mode_t0 = -99.0
	host.show()
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shotdir="):
			out = arg.substr(10)
	assert(out != "")
	for i in 5:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/classes.png")
	host.hh._act("ok")
	assert(host.hh.mode == "pick")
	host.hh._tr = ""
	host.hh._mode_t0 = -99.0
	for i in 5:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/pick.png")
	for cls in ["近卫", "特种"]:
		host.hh.mode = "class"
		host.hh.choices = host.hh.CLASS_ORDER.duplicate()
		host.hh.sel = host.hh.choices.find(cls)
		host.hh._act("ok")
		host.hh._tr = ""
		host.hh._mode_t0 = -99.0
		for i in 5:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out + ("/pick_guard.png" if cls == "近卫" else "/pick_special.png"))
	# 点第二张卡下部左边缘：位于上一张外接矩形内，但只属于第二张斜卡。
	var entry = host.hh.rects.filter(func(r): return r[1] is int and r[1] == 1)[0]
	var box: Rect2 = entry[0]
	var y := box.end.y - 30.0
	var x := box.position.x + 30.0 * 0.18 + 8.0
	var expected: String = host.hh.choices[1]
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = (Vector2(x, y) * host.hh._k + host.hh._off) * Cfg.ui_k
	host.hh.input(click)
	assert(host.hh.results.size() == 1 and host.hh.results[0].id == expected)
	assert(Cfg.roster_tickets.hunt == 3)
	print("HEADHUNT PROFESSIONS: screens and slanted-card click PASS")
	get_tree().quit()
