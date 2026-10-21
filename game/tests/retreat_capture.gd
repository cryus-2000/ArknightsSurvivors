extends Node
## 共用撤退表现录像（10-21，render/retreat_fx.gd）：开局编队 → 第 20 帧换下一名队友（离队撤退）→ 第 70 帧队长倒下，逐帧截图。
##   godot --path game --fixed-fps 30 res://tests/retreat_capture.tscn -- --op=wisadel --squad=suzuran,skadi --shot_dir=<目录>
## 不刷怪、不改存档。新旧对比时在旧提交上跑同一脚本。

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
	g.t = 300.0
	g.invuln = 999.0
	g.xp_need = 1000000000.0
	for f in 120:
		if f == 20 and g.squad.ops.size() > 1:
			var old = g.squad.ops[g.squad.ops.size() - 1]
			g.squad.replace(old.id, "texas")   # 换人：被换下的队友原地撤退
		if f == 70:
			g.hp = 0.0
			g.state = g.S.DEAD   # 直接进倒下（不走伤害结算）
			g.state_age = 0.0
		g.enemies.clear()
		if g.state == g.S.PLAY:
			g._update(DT)
		elif g.state == g.S.DEAD:
			g.state_age += DT
		g.world.update_visuals(DT)
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
