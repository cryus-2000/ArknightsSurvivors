extends Node
## 10-25 攻速对比录像：队长（--op=）站定，近处摆几只不会死的敌人，攻速倍率 --rate=k（op_aspd override），录 --capture-secs 秒；
## log.json 记每次出手的时刻（attack_t 起手沿）供算实际出手频率。用法：tools/probes/atk_rate_capture.py

func _ready() -> void:
	var rate := 1.0
	var secs := 6.0
	var out_dir := "atk_rate"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rate="): rate = float(arg.get_slice("=", 1))
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
	var o = g.squad.ops[0]
	for e in g.enemies: e.dead = true
	g.enemies.clear()
	g.stats.add(&"op_aspd", "override", rate, "atk_rate_capture", "op:" + str(o.id))
	o.refresh_stats()
	var foes: Array = []
	for k in 6:
		var e: Dictionary = g.spawner.spawn_enemy("bone", g.ppos + Vector2.from_angle(TAU * k / 6.0 + 0.2) * 85.0)
		e.hp = 1.0e9
		e.maxhp = 1.0e9
		e.spd = 0.0
		foes.append(e)
	var dt := 1.0 / 60.0
	var starts: Array = []
	var was := false
	for frame in int(secs / dt):
		g.hp = g.max_hp
		g.move_in = Vector2.ZERO
		for e in foes:
			e.pos = e.pos   # 钉在原地
		g.enemies_sys.build_grid()
		g._update(dt)
		var acting: bool = o.attack_t > 0.0 and o.act_kind == "attack"
		if acting and not was: starts.append(snappedf(frame * dt, 0.001))
		was = acting
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
	file.store_string(JSON.stringify({"rate": rate, "starts": starts, "aspd": o.stat(&"op_aspd")}))
	file.close()
	print("ATK RATE CAPTURE rate=", rate, " attacks=", starts.size(), " done failures=0")
	get_tree().quit(0)
