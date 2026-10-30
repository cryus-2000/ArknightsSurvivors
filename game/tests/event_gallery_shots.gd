extends Node
## 图鉴「事件」页截图（docs/184 §11）：填一份示例记录（不存盘），打开图鉴切到事件页，
## 截 选中已遇到的事件（见过的选项 / 打勾）与 选中未遇到的事件 两张到 build/event_gallery/<前缀>_*.png。手机版加 --touch
var title
var out := ""


func _wait(sec: float) -> void:
	for k in int(sec * 60.0):
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))


func _ready() -> void:
	out = ProjectSettings.globalize_path("res://../build/event_gallery")
	DirAccess.make_dir_recursive_absolute(out)
	var pre := "touch" if Cfg.dev_args().has("--touch") else "desk"
	Cfg.unlock_all = false
	Cfg.event_log = {"seen": {"madness": 2, "glimmer": 1, "dream": 1, "task": 1, "boxes": 3, "feeding": 1, "opening": 1},
		"opt": {"madness:0": true, "madness:1": true, "madness:2": true, "madness:3": true, "glimmer:0": true, "glimmer:1": true, "glimmer:2": true,
			"dream:0": true, "dream:1": true, "dream:2": true, "dream:3": true, "task:0": true, "task:1": true, "task:2": true, "task:3": true,
			"boxes:0": true, "boxes:1": true, "boxes:2": true, "boxes:3": true, "boxes:4": true, "feeding:0": true, "feeding:1": true,
			"feeding_2:0": true, "feeding_2:1": true, "feeding_2:2": true, "feeding_2:3": true, "opening:0": true, "opening:3": true},
		"pick": {"madness:0": 1, "madness:2": 1, "glimmer:1": 1, "dream:1": 1, "task:0": 1, "boxes:3": 2, "boxes:0": 1, "feeding:0": 1, "feeding_2:3": 1, "feeding_2:2": 1, "opening:3": 1}}
	title = load("res://main.tscn").instantiate()
	add_child(title)
	await _wait(1.0)
	var gal = title.gallery
	gal.open()
	gal._set_tab(gal.TAB_EVENT)
	await _wait(0.5)
	for i in gal.entries.size():
		if str(gal.entries[i].get("id", "")) == "boxes":
			gal._set_sel(i)
	await _wait(1.2)
	await _shot(pre + "_1_met")
	for i in gal.entries.size():
		if str(gal.entries[i].get("id", "")) == "feeding":
			gal._set_sel(i)
	await _wait(1.2)
	await _shot(pre + "_2_feeding")
	for i in gal.entries.size():
		if gal.entries[i].get("locked", false):
			gal._set_sel(i)
			break
	await _wait(1.2)
	await _shot(pre + "_3_locked")
	get_tree().quit(0)
