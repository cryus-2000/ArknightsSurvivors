extends Node
## 商人「即将离开」指示截图（10-22b：横幅取消后靠屏边指示金红快闪 + 剩余时间红弧表现）：商人放在屏外与屏内各截几帧。
##   godot --path game --fixed-fps 30 res://tests/merchant_leave_capture.tscn -- --shot_dir=<目录>
## 不刷怪、不改存档。

const DT := 1.0 / 30.0
var dir := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot_dir="):
			dir = a.substr(11)
	DirAccess.make_dir_recursive_absolute(dir)
	var g = load("res://game.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	g.state = g.S.PLAY
	g.t = 160.0
	g.invuln = 999.0
	g.xp_need = 1000000000.0
	for f in 40:
		var off := Vector2(900, -300) if f < 20 else Vector2(160, -60)
		g.merchant = {"pos": g.ppos + off, "life": 40.0 if f < 6 or (f >= 20 and f < 26) else 9.0, "near": false, "purchases": 0, "warned": true}
		g.enemies.clear()
		g.world.update_visuals(DT)
		g.world.present_step()
		g.t += DT
		g.queue_redraw()
		g.hud.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		if dir != "":
			get_viewport().get_texture().get_image().save_png(dir.path_join("f_%03d.png" % f))
	get_tree().quit()
