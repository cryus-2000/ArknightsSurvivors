extends Node
## 11-13 手机安全区截图（iPhone 17 B站 App 横屏：灵动岛挡左侧通知、经验条悬空）：进局打一会儿，补一条左侧通知（「维什戴尔 晋升至精英二」）
## 与一条中央横幅，经验调到 60%，截 build/<--shots-out>/<--shot-name>.png。窗口尺寸用 --winsize；触屏 --touch；
## 安全区 --safe=l,t,r,b（UI 像素，settings.gd）+ 可选 --capsule；tools/safe_area_shots.py 批量跑各比例
var g


func _shot(out: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name))
	print("SAFE AREA SHOT ", name, " vs=", get_viewport().get_visible_rect().size, " ui_k=", Cfg.ui_k, " ins=", Cfg.safe_insets(), " hud=", Cfg.hud_ins(), " cap=", Cfg.capsule_ui(), " form=", Cfg.ui_form())


func _ready() -> void:
	var od := "safe_area_shots"
	var nm := "shot.png"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots-out="):
			od = arg.get_slice("=", 1)
		elif arg.begins_with("--shot-name="):
			nm = arg.get_slice("=", 1)
	var out := ProjectSettings.globalize_path("res://../build/" + od)
	DirAccess.make_dir_recursive_absolute(out)
	Cfg.onboard_done = true   # 跳过新手引导弹窗
	Cfg.onboard = "off"
	g = load("res://game.tscn").instantiate()
	add_child(g)
	for k in 900:
		await get_tree().process_frame
		if g.state == g.S.PLAY and k > 420:
			break
	for k in 600:   # 等精英化 / 终结技切入演出过去（横幅与通知会被它们盖住）
		if g.state == g.S.PLAY and not (g.elite_moment != null and g.elite_moment.on(g)) and not g.boss_intro.active():
			break
		await get_tree().process_frame
	g.vfx._notice("维什戴尔 晋升至精英二")
	g.vfx.show_banner("危机迫近", 3)
	for k in 40:
		if g.xp_need > 0.0:
			g.xp = g.xp_need * 0.6
		await get_tree().process_frame
	await _shot(out, nm)
	get_tree().quit(0)
