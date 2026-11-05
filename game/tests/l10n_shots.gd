extends Node
## 英文版界面截图（docs/276 §10 第三步验收用）：标题页（选人 / 图鉴干员档案·属性·技能·成长 / 敌人 / Boss / 设置）与局内（HUD / 招募卡 / 升级卡）各截一张。
##   godot --path game --resolution 1280x720 res://tests/l10n_shots.tscn -- --lang=en --shot_dir=<目录>（不带 --balance / --op 等开局参数，否则标题页直接开局换场景）
## 不判对错，只出图；脚本错误由调用方扫输出。--lang=zh 出中文对照。打印 "L10N SHOTS done=<张数>"
const Loc = preload("res://scripts/core/loc.gd")

var dir := "res://../build/l10n_shots"
var title: Control
var game: Node
var count := 0


func _ready() -> void:
	for a in Cfg.dev_args():
		if a.begins_with("--shot_dir="):
			dir = a.substr(11)
	DirAccess.make_dir_recursive_absolute(dir)
	call_deferred("run")


func frames(k := 8) -> void:
	for i in k:
		await get_tree().process_frame


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join("%s_%s.png" % [Loc.lang, name]))
	count += 1
	print("SHOT ", name)


func run() -> void:
	print("L10N lang=", Loc.lang)
	await title_part()
	await game_part()
	print("L10N SHOTS done=%d" % count)
	get_tree().quit(0)


func title_part() -> void:
	title = load("res://main.tscn").instantiate()
	add_child(title)
	await get_tree().process_frame
	title.intro = title.INTRO_LEN
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	title.position = Vector2.ZERO
	title.size = Vector2(1280, 720)
	await frames(6)
	await shot("01_title")
	title._open_op_pick(false)
	await frames(30)
	await shot("02_op_pick")
	title.op_pick = false
	await frames(4)
	var gl = title.gallery
	gl.open()
	await frames(10)
	for cid in ["mizuki", "skadi", "kaltsit"]:
		gl._set_tab(0)
		gl.select_id(cid)
		for it in [0, 2, 3]:
			gl.info_tab = it
			gl.row_sel = -1
			await frames(20)
			await shot("03_gallery_%s_%s" % [cid, ["lore", "stats", "skills", "growth"][it]])
	for pair in [[1, "bone"], [1, "reaper"], [2, "mimic"], [3, "izumik"], [3, "bishop"]]:
		gl._set_tab(pair[0])
		gl.select_id(pair[1])
		await frames(20)
		await shot("04_gallery_%s" % pair[1])
	gl.close()
	await frames(4)
	title.settings.open()
	await frames(10)
	await shot("05_settings")
	title.settings.close()
	title.queue_free()
	await frames(3)


func game_part() -> void:
	game = load("res://game.tscn").instantiate()
	add_child(game)
	await frames(30)
	var g = game
	g.headless_batch = false
	await frames(30)
	await shot("06_hud")
	g.set_process(false)
	var pg = g.progression
	var opts: Array = []
	for c in pg.recruit_cards():
		if ["wisadel", "suzuran", "kaltsit", "logos", "exusiai"].has(str(c.id)) and opts.size() < 3:
			opts.append(c)
	g.panel_ui.show_choices("招募干员", opts, "level")
	g.panel_ui.motion.skip()
	await _cards(g, 40)
	await shot("07_recruit_cards")
	g.panel.visible = false
	g.state = g.S.PLAY
	for i in 3:
		pg.open_levelup()
		g.panel_ui.motion.skip()
		await _cards(g, 40)
		await shot("08_levelup_%d" % i)
		g.panel.visible = false
		g.state = g.S.PLAY
	g.state = g.S.STATS
	await _cards(g, 20)
	await shot("09_stats")
	g.state = g.S.PLAY
	g.queue_free()
	await frames(2)


## 停住对局时卡片动效与重画要手推（同 build_cards_capture）
func _cards(g, k: int) -> void:
	for i in k:
		for c in g.panel_box.get_children():
			c.queue_redraw()
		g.panel_fg.queue_redraw()
		g.hud.queue_redraw()
		g.panel_ui.animate_cards(1.0 / 60.0)
		await get_tree().process_frame
