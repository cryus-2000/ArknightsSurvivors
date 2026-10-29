extends Node
## 10-29 用户卡死复现：路口一翻开狂徒妄念 → 选项 → 面板是否正常（窗口模式，走真实翻面计时器）。截图到 build/madness_flow/
var g
var out := ""


func _wait(sec: float) -> void:
	for k in int(sec * 60.0):
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	var btn := 0
	for c in g.panel_box.get_children():
		if c is Button and c.visible:
			btn += 1
	print("MF %s state=%s kind=%s choices=%d buttons=%d opened=%s panel=%s" % [name, g.state, g.choice_kind, g.choices.size(), btn, g.endg.opened_id, g.panel.visible])


func _ready() -> void:
	out = ProjectSettings.globalize_path("res://../build/madness_flow")
	DirAccess.make_dir_recursive_absolute(out)
	g = load("res://game.tscn").instantiate()
	add_child(g)
	await _wait(1.5)
	g.state = g.S.PLAY
	g.pending_levelups = 0
	g.pending_chests = 0
	for cid in ["skadi", "ulpianus"]:
		if not g.squad.has(cid):
			g.squad.add(cid)
	g.t = 261.0
	g.ingots = 63
	var E = g.endg
	E.lines_on = true
	E.enabled = true
	E._checked = true
	E.mid_done = 2
	var opt := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--opt="):
			opt = int(a.substr(6))
	E._deal(1)
	await _wait(1.0)
	await _shot("1_deal")
	var mi := 0
	for i in E.deck.size():
		if str(E.deck[i].get("event", "")) == "madness":
			mi = i
	g.progression.pick(mi)
	await _wait(0.5)
	await _shot("2_flipping")
	await _wait(1.5)
	await _shot("3_event")
	g.progression.pick(opt)
	await _wait(1.0)
	await _shot("4_after_pick_%d" % opt)
	get_tree().quit(0)
