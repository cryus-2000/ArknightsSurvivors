extends Node
## 寻访各屏截图 + 滚动 / 不出框检查（10-25）：入口 / 选职业 / 指定干员（含滚动后）/ 揭示 / 本次寻访。
## 用法：tools/godot_runner.py 静音离屏启动，参数 --roster=start5 --shotdir=<已存在目录>（手机加 --touch，分辨率 1480×720）

var host


func _shot(name: String, out: String) -> void:
	host.hh._tr = ""
	host.hh._mode_t0 = -99.0
	for i in 14:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + name + ".png")


func _ready() -> void:
	host = preload("res://scripts/screens/hunt_host.gd").new()
	add_child(host)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Cfg.roster_tickets = {"hunt": 9}
	var out := ""
	var internal := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shotdir="):
			out = arg.substr(10)
		if arg == "--internal10":
			internal = true
	assert(out != "")
	var Roster = preload("res://scripts/core/roster.gd")
	if internal:
		Cfg.roster_unlocked = Roster.STARTERS + ["lumen", "skadi", "specter_unchained", "siege", "ulpianus"]   # 旧对内包开局 10 人
	host.hh.browse = false
	var t0 := Time.get_ticks_usec()
	host.open()
	var first_ms := (Time.get_ticks_usec() - t0) / 1000.0
	host.show()
	await _shot("entry", out)
	print("HHSHOT open_ms=%.1f locked=%d" % [first_ms, Roster.locked_ids().size()])
	host.hh._act("directed")
	await _shot("class", out)
	# 选人最多的职业
	var best := ""
	var cnt := 0
	for cls in host.hh.CLASS_ORDER:
		var n: int = Roster.locked_in_class(cls).size()
		if n > cnt:
			cnt = n
			best = cls
	host.hh.sel = host.hh.choices.find(best)
	host.hh._act("ok")
	assert(host.hh.mode == "pick")
	await _shot("pick", out)
	var cap: int = host.hh._pick_geom().cap
	print("HHSHOT pick best=%s n=%d cap=%d" % [best, cnt, cap])
	if cnt > cap:
		host.hh._pick_step(1)
		assert(host.hh.pick_scroll == 1)
		await _shot("pick_scrolled", out)
		host.hh.sel = host.hh.choices.size() - 1
		host.hh._pick_scroll_to(host.hh.sel)
		await _shot("pick_last", out)
	# 点最后一张可见卡（斜卡真实截面）
	var vis_i: int = mini(host.hh.choices.size() - 1, host.hh.pick_scroll + cap - 1)
	var entry = host.hh.rects.filter(func(r): return r[1] is int and r[1] == vis_i)[0]
	var box: Rect2 = entry[0]
	var pos := Vector2(box.position.x + (box.end.y - 40.0) * 0.18 + 40.0, box.end.y - 40.0)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = (pos * host.hh._k + host.hh._off) * Cfg.ui_k
	var before: int = Roster.tickets()
	host.hh.input(ev)
	if host.hh.mode == "pick":   # 拖动模式：松手才算点选
		var up := InputEventMouseButton.new()
		up.button_index = MOUSE_BUTTON_LEFT
		up.pressed = false
		up.position = ev.position
		host.hh.input(up)
	assert(host.hh.results.size() == 1 and Roster.tickets() == before - 2)
	host.hh._tr = ""
	host.hh._op(0)
	host.hh.t0 = host.hh._now() - 3.0
	await _shot("reveal", out)
	host.hh._summary()
	host.hh.t0 = host.hh._now() - 3.0
	await _shot("summary", out)
	print("HHSHOT PASS")
	get_tree().quit()
