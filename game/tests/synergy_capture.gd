extends Node
## 干员连携技演示录像（docs/160）：队长站定，前方一小群不会死的敌人；0.8 秒时 --cast= 指定的干员放 --skill= 号技能，
## 录 --capture-secs 秒，真实渲染视口每 2 帧存一张（30 fps）。用法：tools/probes/synergy_capture.py

func _ready() -> void:
	var cast := "texas"
	var skill := 0
	var secs := 5.0
	var out_dir := "synergy_cap"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cast="): cast = arg.get_slice("=", 1)
		if arg.begins_with("--skill="): skill = int(arg.get_slice("=", 1))
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
	var o = g.squad.get_op(cast)
	var foes: Array = []
	for k in 3:
		var e: Dictionary = g.spawner.spawn_enemy("bone", g.ppos + Vector2(250.0 + 22.0 * k, -50.0 + 50.0 * k))
		e.hp = 1.0e9
		e.maxhp = 1.0e9
		e.spd = 0.0
		foes.append(e)
	var dt := 1.0 / 60.0
	var cast_frame := int(0.8 / dt)
	var log := {"cast_at": 0.8, "acts": 0}
	for frame in int(secs / dt):
		g.hp = g.max_hp
		g.move_in = Vector2.ZERO
		for e in foes:
			e.hp = 1.0e9
		if frame == cast_frame:
			o.spend_sp(skill)
			log.acts = g.squad.syn.acts.size()
		g.enemies_sys.build_grid()
		g._update(dt)
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
	file.store_string(JSON.stringify(log))
	file.close()
	print("SYNERGY CAPTURE cast=", cast, " acts=", log.acts)
	get_tree().quit(0)
