extends Node
## 10-24 动作审计（docs/140）实机录像：放技能 / 普攻时队长按「走 – 停」节奏来回移动，逐帧存真实渲染视口 PNG，
## 看技能循环、格挡、移动攻击叠在跑动上的观感。tools/probes/anim_move_capture.py 驱动并合成 1/3 速 gif。
## 参数：--capture-op=<id> --capture-what=<技能下标|attack> --capture-total=<帧> --capture-out=<build 下子目录>
##       --capture-adv=<精英化推进次数> --capture-skill-at=<帧> --capture-walk=<走帧>,<停帧> --capture-speed=<像素/秒>

func _ready() -> void:
	var id := "hoshiguma"
	var what := "0"
	var adv := 6
	var out_dir := "anim_move"
	var total := 300
	var skill_at := 20
	var walk := 45
	var stop := 30
	var speed := 150.0
	for arg in OS.get_cmdline_user_args():
		var v := arg.get_slice("=", 1)
		if arg.begins_with("--capture-op="): id = v
		if arg.begins_with("--capture-what="): what = v
		if arg.begins_with("--capture-adv="): adv = int(v)
		if arg.begins_with("--capture-out="): out_dir = v
		if arg.begins_with("--capture-total="): total = int(v)
		if arg.begins_with("--capture-skill-at="): skill_at = int(v)
		if arg.begins_with("--capture-walk="):
			walk = int(v.get_slice(",", 0))
			stop = int(v.get_slice(",", 1))
		if arg.begins_with("--capture-speed="): speed = float(v)
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
	g.invuln = 0.0
	g.xp_need = 1000000000.0
	var o = g.squad.get_op(id)
	assert(o != null)
	for i in adv: o.advance()
	o.sp = [-100000.0, -100000.0, -100000.0]
	var basic := what == "attack"
	o.cd = 0.0 if basic else 10000.0
	for enemy in g.enemies: enemy.dead = true
	g.enemies.clear()
	var target: Dictionary = g.spawner.spawn_enemy("stone", g.ppos + Vector2(110, 0))
	target.hp = 10000000.0
	target.max_hp = target.hp
	target.spd = 0.0
	var log := []
	var dir := 1.0
	for frame in total:
		if frame == skill_at and not basic:
			o.attack_t = 0.0
			o.fire_t = -1.0
			o.manual_pt = target.pos
			o.start_skill(target.pos, int(what))
		if not basic:
			o.sp = [-100000.0, -100000.0, -100000.0]
			if frame >= skill_at - 10: o.cd = maxf(o.cd, 0.5)
		# 走 – 停：围着靶子左右来回，靶子跟着保持在攻击距离内
		var ph := frame % (2 * (walk + stop))
		var moving := frame >= skill_at + 8 and (ph < walk or (ph >= walk + stop and ph < 2 * walk + stop))
		if frame >= skill_at + 8 and ph == walk + stop:
			dir = -dir
		if moving:
			g.ppos += Vector2(dir * speed / 60.0, 0)
		target.pos = g.ppos + Vector2(110 * dir, 0)
		target.kb = Vector2.ZERO
		g.enemies_sys.build_grid()
		g._update(1.0 / 60.0)
		g.world.update_visuals(1.0 / 60.0)
		g.world.present_step()
		var st: Dictionary = o.anim_state()
		log.append({"frame": frame, "kind": st.get("kind", ""), "pose": st.get("frame", -1), "mv": o.mv, "moving": moving, "attack_t": o.attack_t, "sq_ph": o.sq_ph})
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
	print("ANIM MOVE CAPTURE ", id, " ", what, " done failures=0")
	get_tree().quit(0)
