extends Node
## 招募卡长简介截图验收（10-30 用户写定的 20 句 gallery.intro；不进快检）：
##   godot --path game --resolution 1280x720 res://tests/recruit_intro_capture.tscn -- --balance --seed=1 --op=angelina --shot_dir=<目录> [--per=3|5] [--touch]
## 指定的 8 名干员按 --per 张一屏依次摆出招募卡（3 张 = 卡宽 272，5 张 = 挤到最小卡宽），每屏存 recruit_<n>.png，
## 并打印每张卡说明排版：INTRO <id> w=<卡宽> fit=<是否放下> size=<字号> lines=<行数>/<可用行数> cut=<被截断>。

const IDS := ["skalter", "siege", "ulpianus", "gladiia", "lappland", "saria", "texas", "wisadel"]

var game: Node
var frames := 0
var dir := ""
var per := 3
var tag := "desktop"
var batch := 0
var wait := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot_dir="):
			dir = a.substr(11)
		elif a.begins_with("--per="):
			per = int(a.substr(6))
		elif a == "--touch":
			tag = "phone"
	DirAccess.make_dir_recursive_absolute(dir)
	game = load("res://game.tscn").instantiate()
	add_child(game)


func _show() -> void:
	var opts: Array = []
	var want: Array = IDS.slice(batch * per, batch * per + per)
	for id in want:
		for c in game.progression.recruit_cards():
			if str(c.id) == id:
				opts.append(c)
	if opts.size() < want.size():
		print("INTRO missing ", want, " got ", opts.map(func(c): return c.id))
	game.panel_ui.show_choices("招募干员", opts, "level")
	game.panel_ui.motion.skip()
	for c in game.panel_box.get_children():
		if not (c is Button) or not c.has_meta("fit"):
			continue
		var f: Dictionary = c.get_meta("fit")
		print("INTRO %s w=%d fit=%s size=%d lines=%d/%d lh=%.1f compact=%s roomy=%s" % [str(c.get_meta("full_desc", "")).substr(0, 6), int(game.panel_ui.card_w), f.fit, int(f.size), (f.lines as PackedStringArray).size(), int(f.n), float(f.lh), c.get_meta("compact", false), c.get_meta("roomy", false)])


func _process(_d: float) -> void:
	frames += 1
	if frames < 10:
		return
	for c in game.panel_box.get_children():
		c.queue_redraw()
	game.panel_fg.queue_redraw()
	game.hud.queue_redraw()
	game.panel_ui.animate_cards(1.0 / 60.0)
	if wait > 0:
		wait -= 1
		if wait == 0:
			get_viewport().get_texture().get_image().save_png(dir + "/%s_per%d_%d.png" % [tag, per, batch])
			batch += 1
		return
	if frames == 10:
		game.set_process(false)
	if batch * per >= IDS.size():
		get_tree().quit(0)
		return
	game.panel.visible = false
	_show()
	wait = 30
