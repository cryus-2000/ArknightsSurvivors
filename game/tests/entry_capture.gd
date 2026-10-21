extends Node
## 入场条录像（10-22，原作 Start 轨）：开场编队落地 → 第 130 帧局中招募 → 第 175 帧换人，逐帧截图。
##   godot --path game --fixed-fps 30 res://tests/entry_capture.tscn -- --op=texas --rec=eyjafjalla --swap=exusiai --shot_dir=<目录>
## 不刷怪、不改存档。

const DT := 1.0 / 30.0
var dir := ""
var rec := ""
var swap := ""
var frames := 220


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot_dir="):
			dir = a.substr(11)
		elif a.begins_with("--rec="):
			rec = a.substr(6)
		elif a.begins_with("--swap="):
			swap = a.substr(7)
		elif a.begins_with("--frames="):
			frames = int(a.substr(9))   # 只录开场：--frames=90
	DirAccess.make_dir_recursive_absolute(dir)
	var g = load("res://game.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	g.intro_screen.start_opening()
	g.invuln = 999.0
	g.xp_need = 1000000000.0
	for f in frames:
		if f == 130 and rec != "":
			g.squad.add(rec)   # 局中招募：从上方落下，着地接入场条
		if f == 175 and rec != "" and swap != "" and g.squad.has(rec):
			g.squad.replace(rec, swap)   # 换人：被换下的跳出，新干员落下接入场条
		g.enemies.clear()
		if g.state == g.S.PLAY:   # 开场由 world.update_visuals 推进（intro.update_opening）
			g._update(DT)
		g.world.update_visuals(DT if g.state == g.S.PLAY else 0.0)
		g.world.present_step()
		g.queue_redraw()
		g.fx_add.queue_redraw()
		g.fg.queue_redraw()
		g.hud.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		if dir != "":
			get_viewport().get_texture().get_image().save_png(dir.path_join("f_%03d.png" % f))
	get_tree().quit()
