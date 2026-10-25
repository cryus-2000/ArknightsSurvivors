extends Node
## 10-25 自动技能「范围内没有敌人不放」对比录像：被测干员（--probe-op=）站定，交替「空场 / 敌人从远处逼近」，
## 真实渲染视口逐帧存 PNG（每 2 帧一张），log.json 记每帧阶段与技能发动（sp 骤降），烧字幕交给 tools/probes/skill_gate_capture.py。
## 敌人只刷在被测干员「技能门槛距离」之外 / 之内两种位置，清楚展示：圈外不放、进圈才放。

func _ready() -> void:
	var who := "siege"
	var out_dir := "skill_gate"
	var secs := 36.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--probe-op="): who = arg.get_slice("=", 1)
		if arg.begins_with("--capture-out="): out_dir = arg.get_slice("=", 1)
		if arg.begins_with("--capture-secs="): secs = float(arg.get_slice("=", 1))
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
	var o = g.squad.get_op(who)
	assert(o != null)
	for e in g.enemies: e.dead = true
	g.enemies.clear()
	var dt := 1.0 / 60.0
	var prev: Array = [0.0, 0.0, 0.0]
	var log := []
	var holds: Array = []   # 阶段 B：敌人被钉在圈外一圈，用 spd=0 不让它走近
	for frame in int(secs / dt):
		var t := frame * dt
		# 0–10 空场（技力满格也不放）；10–20 敌人停在门槛圈外 +40；20+ 敌人走进圈里
		var phase: int = 0 if t < 10.0 else (1 if t < 20.0 else 2)
		g.hp = g.max_hp
		g.move_in = Vector2.ZERO
		if phase == 1 and holds.is_empty():
			var gate: float = 130.0 + 60.0
			for k in 5:
				var e: Dictionary = g.spawner.spawn_enemy("bone", g.ppos + Vector2.from_angle(TAU * k / 5.0 + 0.3) * gate)
				e.spd = 0.0
				holds.append(e)
		if phase == 2 and not holds.is_empty():
			for e in holds: e.spd = 60.0
			holds.clear()
		g.enemies_sys.build_grid()
		g._update(dt)
		var cast := 0
		for i in 3:
			var sp: float = float(o.sp[i])
			if sp < float(prev[i]) - 0.5 * maxf(1.0, float(o.sp_need(i))) and o.sp_need(i) > 0.0 and not bool(o.perm[i]):
				cast = i + 1
			prev[i] = sp
		var ne: Array = g.enemies_sys.nearest(1, 900.0, o.pos)
		log.append({"f": frame, "phase": phase, "cast": cast, "near": snappedf(o.pos.distance_to(ne[0].pos), 1.0) if not ne.is_empty() else -1.0, "sp": [snappedf(float(o.sp[0]), 0.1), snappedf(float(o.sp[1]), 0.1), snappedf(float(o.sp[2]), 0.1)]})
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
	print("SKILL GATE CAPTURE done failures=0")
	get_tree().quit(0)
