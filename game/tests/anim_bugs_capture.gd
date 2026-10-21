extends Node
const Look = preload("res://scripts/render/look.gd")
## 10-21 动画 bug 实机截图（艾雅法拉 S2 火焰弹 / 水月待机末帧 / 推进之王 S2 转圈）：真实渲染视口逐帧存 PNG。
## 用法：tools/probes/anim_bugs_capture.py <out> <op> <skill|idle> [advance]

func _ready() -> void:
	var id := "eyjafjalla"
	var what := "1"
	var adv := 6
	var out_dir := "anim_bugs"
	var total_arg := -1   # --capture-total=<帧数>（10-22：录 S3 这类长技能用）
	var skill_at := 10    # --capture-skill-at=<帧>（10-22：先普攻几下再放技能，例：歌蕾蒂娅 S3 落在最近一次钩中处）
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-total="): total_arg = int(arg.get_slice("=", 1))
		if arg.begins_with("--capture-skill-at="): skill_at = int(arg.get_slice("=", 1))
		if arg.begins_with("--capture-op="): id = arg.get_slice("=", 1)
		if arg.begins_with("--capture-what="): what = arg.get_slice("=", 1)
		if arg.begins_with("--capture-adv="): adv = int(arg.get_slice("=", 1))
		if arg.begins_with("--capture-out="): out_dir = arg.get_slice("=", 1)
	var output := ProjectSettings.globalize_path("res://../build/" + out_dir + "/" + id + "_" + what)
	DirAccess.make_dir_recursive_absolute(output)
	var g = load("res://game.tscn").instantiate()
	add_child(g)
	for i in 5: await get_tree().process_frame
	g.set_process(false)
	g.mode = g.Mode.PLAY
	g.state = g.S.PLAY
	g.sandbox = true
	g.t = 60.0
	g.invuln = 0.0   # 不开无敌：主控无敌闪烁 0.6 透明会被误看成虚化
	g.xp_need = 1000000000.0
	var o = g.squad.get_op(id)
	assert(o != null)
	for i in adv: o.advance()
	print("CAPTURE elite=", o.elite, " prog=", o.prog)
	o.sp = [-100000.0, -100000.0, -100000.0]
	o.cd = 10000.0
	var center: Vector2 = g.ppos
	for enemy in g.enemies: enemy.dead = true
	g.enemies.clear()
	var target: Dictionary = g.spawner.spawn_enemy("stone", center + Vector2(140, 0))
	target.hp = 10000000.0
	target.max_hp = target.hp
	target.spd = 0.0
	g.enemies_sys.build_grid()
	var idle := what == "idle"
	var basic := what == "attack"   # 10-22：只普攻（不放技能），录普攻 gif 用
	var total := 860 if idle else 150
	if total_arg > 0: total = total_arg
	var every := 6 if idle else 1
	var log := []
	for frame in total:
		if frame == skill_at and not idle and not basic:
			o.attack_t = 0.0
			o.fire_t = -1.0
			o.manual_pt = target.pos
			o.start_skill(target.pos, int(what))
		o.sp = [-100000.0, -100000.0, -100000.0]
		if idle: o.cd = 10000.0
		elif not basic and frame >= skill_at - 10: o.cd = maxf(o.cd, 0.5)
		elif frame == 0: o.cd = 0.0   # 普攻模式 / 技能前的普攻段：上面把冷却设成 10000 是为了压住技能录制里的普攻，这里放开
		target.pos = center + Vector2(140, 0)
		target.kb = Vector2.ZERO
		g.enemies_sys.build_grid()
		g._update(1.0 / 60.0)
		g.world.update_visuals(1.0 / 60.0)
		g.world.present_step()
		var st: Dictionary = o.anim_state()
		var n_b := 0
		for b in g.bullets:
			if b.get("op", "") == id: n_b += 1
		log.append({"frame": frame, "kind": st.get("kind", ""), "pose": st.get("frame", -1), "bullets": n_b, "lobs": o.hw.get("lobs", []).size() if o.hw is Dictionary else 0, "ghosts": o.ghosts.size(), "mod": str(g.sprite.modulate), "lead": o.is_leader, "opmod": str(Look.op_mod(g, o.pos, Color.WHITE)), "fx_dim": g.world.fx_dim, "cd": o.cd, "noatk": o.no_attack, "near": o.nearest_enemies(1, 400.0, o.pos).size(), "attack_t": o.attack_t})
		if frame % every != 0: continue
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
	print("ANIM BUGS CAPTURE ", id, " ", what, " done failures=0")
	get_tree().quit(0)
