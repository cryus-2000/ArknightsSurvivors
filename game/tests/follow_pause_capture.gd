extends Node
## 队友跟随停顿候选录像（10-21，character.gd _follow_paused）：队长按固定节奏连续冲刺，逐帧截图。
##   godot --path game --fixed-fps 30 res://tests/follow_pause_capture.tscn -- --op=wisadel --squad=suzuran,skadi,saria --fpause=a|b|c --shot_dir=<目录>
## 不刷怪、不改存档；--fpause 缺省 = 现状（每帧 lerp）。同一冲刺脚本，四个模式各跑一次后拼对比。

const DT := 1.0 / 30.0
const DIRS := [Vector2(1, 0), Vector2(1, 0), Vector2(0.6, -0.8), Vector2(-1, 0), Vector2(-1, 0.3), Vector2(0, 1), Vector2(1, 0.2), Vector2(1, 0)]
var dir := ""
var frames := 150


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot_dir="):
			dir = a.substr(11)
		elif a.begins_with("--frames="):
			frames = int(a.substr(9))
	DirAccess.make_dir_recursive_absolute(dir)
	var g = load("res://game.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	g.state = g.S.PLAY
	g.t = 300.0
	g.invuln = 999.0
	g.xp_need = 1000000000.0
	var k := 0
	var log := []
	for f in frames:
		# 每 0.6 秒一次冲刺（不看冷却）；冲刺之间站着不动
		if f % 18 == 2:
			g.dash_dir = DIRS[k % DIRS.size()].normalized()
			g.dash_t = g.DASH_TIME
			k += 1
		g.enemies.clear()
		g._update(DT)
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
			var row := [f, g.ppos.x, g.ppos.y]
			for o in g.squad.ops:
				if not o.is_leader:
					row.append_array([o.slot, o.pos.x, o.pos.y])
			log.append(row)
	if dir != "":
		var fh := FileAccess.open(dir.path_join("pos.json"), FileAccess.WRITE)
		fh.store_string(JSON.stringify(log))
		fh.close()
	get_tree().quit()
