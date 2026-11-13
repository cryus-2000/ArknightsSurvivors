extends Node
## 11-13 安全区适配：ui_matrix 没有现成钩子的几屏，一次跑一屏（--which=）进局摆出来截 shot_<which>.png 到 --shotdir：
##   event 不期而遇（madness）/ elite 精英化演出 / ultaim 终结技慢动作瞄准 / runlog 对局记录（局终后打开）
## 尺寸 / 触屏 / 安全区由 ui_matrix 传（--winsize --touch --safe --capsule）
var g
var which := "event"
var out := ""


func _shot() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("shot_%s.png" % which))
	print("SAFE SCREENS SHOT ", which, " ins=", Cfg.safe_insets(), " cap=", Cfg.capsule_ui())


func _frames(n: int) -> void:
	for k in n:
		await get_tree().process_frame


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--which="):
			which = arg.get_slice("=", 1)
		elif arg.begins_with("--shotdir="):
			out = arg.get_slice("=", 1)
	if out == "":
		out = ProjectSettings.globalize_path("res://../build/safe_screens")
	DirAccess.make_dir_recursive_absolute(out)
	Cfg.onboard_done = true
	Cfg.onboard = "off"
	g = load("res://game.tscn").instantiate()
	add_child(g)
	for k in 900:
		await get_tree().process_frame
		if g.state == g.S.PLAY and k > 240:
			break
	match which:
		"event":
			g.endg.open("madness")
			await _frames(90)
		"elite":
			g.ch._elite_show(1)
			g.show_screen.open(g.show_queue.pop_front())
			await _frames(200)
		"ultaim":
			if g.ult != null:
				g.ult.energy = 100.0
				g.ult.press_q()
			await _frames(25)
		"runlog":
			g.state = g.S.DEAD
			await _frames(5)
			g.state_age = 99.0
			g.run_log.open_log()
			await _frames(60)
	await _shot()
	get_tree().quit(0)
