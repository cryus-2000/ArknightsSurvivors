extends Node
## 界面立绘验收截图（10-23 用户：招募卡三张大小统一；选人 / 图鉴用 @2x 精细版，不进快检）：
##   godot --path game --resolution 1280x720 res://tests/op_ui_capture.tscn -- --balance --shot_dir=<目录> [--ops=ulpianus,skadi,mizuki]
## 有窗口（截图要画面），用 tools/godot_runner 起（窗口放屏幕外、静音）。存 1_select.png、2_codex.png；招募卡三连另用 build_cards_capture --recruit=
var dir := "res://../build/op_ui_shots"
var ops: Array = ["ulpianus", "skadi", "mizuki"]
var title: Control


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot_dir="):
			dir = a.substr(11)
		if a.begins_with("--ops="):
			ops = a.substr(6).split(",")
	DirAccess.make_dir_recursive_absolute(dir)
	call_deferred("run")


func settle(n := 30) -> void:
	for i in n:
		await get_tree().process_frame


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir + "/%s.png" % name)
	print("SHOT ", name)


func run() -> void:
	Cfg.reduce_motion = true
	Cfg._touch = 0
	Cfg.character_id = str(ops[0])
	Cfg.cover_character_id = "mizuki"
	title = load("res://main.tscn").instantiate()
	add_child(title)
	await get_tree().process_frame
	title.intro = title.INTRO_LEN
	title._open_op_pick(false)
	await settle()
	for i in title.op_defs.size():
		if title.op_defs[i].id == str(ops[0]):
			title._op_select(i)
	await settle()
	await shot("1_select_" + str(ops[0]))
	for i in title.op_defs.size():
		if title.op_defs[i].id == str(ops[1]):
			title._op_select(i)
	await settle()
	await shot("1_select_" + str(ops[1]))
	title._op_back()
	await settle()
	var gal = title.gallery
	gal.open()
	await settle()
	for i in gal.entries.size():
		if gal.entries[i].id == str(ops[2]):
			gal.sel = i
	await settle()
	await shot("2_codex_" + str(ops[2]))
	for i in gal.entries.size():
		if gal.entries[i].id == str(ops[0]):
			gal.sel = i
	await settle()
	await shot("2_codex_" + str(ops[0]))
	get_tree().quit()
