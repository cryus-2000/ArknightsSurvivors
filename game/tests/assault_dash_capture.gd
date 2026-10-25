extends Node
## 10-26 突击模式德克萨斯自冲刺录像：队长（--op=）站定，德克萨斯作为队友，前 2 秒随行，之后切「突击」；敌人不断从前方涌来（每 0.5 秒挪回弧上）。
## 用法：tools/probes/assault_dash_capture.py

func _ready() -> void:
	var secs := 14.0
	var out_dir := "assault_dash"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-secs="): secs = float(arg.get_slice("=", 1))
		if arg.begins_with("--capture-out="): out_dir = arg.get_slice("=", 1)
	var output := ProjectSettings.globalize_path("res://../build/" + out_dir)
	DirAccess.make_dir_recursive_absolute(output)
	var g = load("res://game.tscn").instantiate()
	add_child(g)
	for i in 5: await get_tree().process_frame
	g.set_process(false)
	g.mode = g.Mode.PLAY
	g.state = g.S.PLAY
	g.sandbox = true
	g.t = 60.0
	g.xp_need = 1000000000.0
	for e in g.enemies: e.dead = true
	g.enemies.clear()
	var tx = g.squad.get_op("texas")
	var foes: Array = []
	for k in 8:
		var e: Dictionary = g.spawner.spawn_enemy("bone", g.ppos + Vector2(260.0, 0.0))
		e.hp = 1.0e9
		e.maxhp = 1.0e9
		e.spd = 0.0
		foes.append(e)
	var dt := 1.0 / 60.0
	var log := []
	var was := false
	for frame in int(secs / dt):
		var t := frame * dt
		if frame == int(2.0 / dt):
			g.squad.set_stance(g.squad.ROAM)
		g.hp = g.max_hp
		g.move_in = Vector2.ZERO
		for k in foes.size():
			foes[k].hp = 1.0e9
			if frame % 30 == 0:
				foes[k].pos = g.ppos + Vector2.from_angle(-0.9 + 1.8 * float(k) / 7.0) * 270.0
		g.enemies_sys.build_grid()
		g._update(dt)
		var d: bool = tx.tx.has("dash")
		if d and not was: log.append(snappedf(t, 0.01))
		was = d
		g.world.update_visuals(dt)
		g.world.present_step()
		if frame % 2 != 0: continue
		g.queue_redraw()
		g.fx_add.queue_redraw()
		g.fg.queue_redraw()
		g.hud.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var im := get_viewport().get_texture().get_image()
		assert(im.save_png(output.path_join("f_%04d.png" % frame)) == OK)
	var file := FileAccess.open(output.path_join("log.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"dashes": log, "roam_at": 2.0}))
	file.close()
	print("ASSAULT DASH CAPTURE dashes=", log)
	get_tree().quit(0)
