extends Node
## 干员连携技演示录像（docs/160）：队长站定，前方一群真会移动的怪（缺省 16 只 + 1 只精英，生命近乎无限），
## 0.8 秒时 --cast= 的干员「真的放」--skill= 号技能（start_skill，不是只扣技力），--ready= 让某名队友的 S1 技力满格。
## 镜头拉近（--zoom=）；每 2 帧存一张，并把每帧的阶段（放技能 / 合击冲刺 / 命中 / 收势）和搭档、落点的屏幕坐标写进 log.json，供 tools/probes/synergy_capture.py 加字幕、标记、慢放。

func _ready() -> void:
	var cast := "texas"
	var ready := ""
	var skill := 0
	var secs := 5.0
	var out_dir := "synergy_cap"
	var n_foes := 16
	var elite := true
	var zoom := 1.4
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cast="): cast = arg.get_slice("=", 1)
		if arg.begins_with("--skill="): skill = int(arg.get_slice("=", 1))
		if arg.begins_with("--ready="): ready = arg.get_slice("=", 1)
		if arg.begins_with("--capture-secs="): secs = float(arg.get_slice("=", 1))
		if arg.begins_with("--capture-out="): out_dir = arg.get_slice("=", 1)
		if arg.begins_with("--foes="): n_foes = int(arg.get_slice("=", 1))
		if arg.begins_with("--elite="): elite = int(arg.get_slice("=", 1)) != 0
		if arg.begins_with("--zoom="): zoom = float(arg.get_slice("=", 1))
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
	g.cam.zoom = Vector2(zoom, zoom)
	var o = g.squad.get_op(cast)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# 放技能的门槛半径（自动技能「范围内有敌人才放」同一个口径）：怪群摆在门槛以内，技能才真能打到（德克萨斯 S1 是以自己为圆心的剑雨 + 眩晕，太远就落空）
	var sk: Array = o.B.get("skills", [])
	var atk: Dictionary = o.B.get("attack", {})
	var fb: float = o.ObCore.GATE_DEFAULT
	if str(atk.get("r", "")) == "zone":
		fb = o.zone_r() / maxf(0.01, o.stat(&"op_range"))
	var gate: float = o.ObCore.skill_gate_base(sk[skill], atk, {}, fb) * o.stat(&"op_range") if skill < sk.size() else 260.0
	var dist: float = clampf(gate * 0.7, 130.0, 300.0)
	var spread: float = clampf(gate * 0.35, 40.0, 80.0)
	var foes: Array = []
	for k in n_foes:   # 一团怪，在门槛以内、队长右前方，真实移动速度（不钉死）
		var at: Vector2 = g.ppos + Vector2(dist, 0.0) + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, spread)
		foes.append(g.spawner.spawn_enemy("bone", at))
	if elite:
		foes.append(g.spawner.spawn_enemy("knight", g.ppos + Vector2(dist + spread * 0.6, -spread * 0.5)))
		foes[-1].elite = true
	for e in foes:
		e.hp = 1.0e9
		e.maxhp = 1.0e9
		e.dmg = 0.0   # 怪不打人：画面不被受击红边 / 飘字干扰，只看技能和合击
	for op in g.squad.ops:   # 其余人技力清零：没点名「就绪」的搭档一律是没就绪（演示「没就绪 → 重击 / 弹幕」那一支）
		if op.id != cast:
			for si in 3:
				op.sp[si] = 0.0
	if ready != "" and g.squad.get_op(ready) != null:
		g.squad.get_op(ready).pos = g.ppos + Vector2(90.0, 10.0)   # 站进技能门槛（攻击射程）以内，演示才放得出来；技力在放技能那一帧才充满（否则她自己先放掉了）
	var dt := 1.0 / 60.0
	var cast_frame := int(0.8 / dt)
	var log := {"cast_at": 0.8, "acts": 0, "casts": {}, "frames": [], "gate": gate, "dist": dist}
	var stage_seen := false
	for frame in int(secs / dt):
		g.hp = g.max_hp
		g.move_in = Vector2.ZERO
		for e in foes:
			e.hp = 1.0e9
		if frame == cast_frame:
			var aim: Vector2 = o.ObSummon.mf_skill_aim(o, skill)
			if aim == Vector2.INF:
				var near: Array = o.nearest_enemies(1, 900.0)
				aim = near[0].pos if not near.is_empty() else o.pos + Vector2(200.0, 0.0)
			o.start_skill(aim, skill)
		if ready != "":   # 「就绪」演示：搭档的技力恰好在合击要判断「放技能还是打普通一击」的那一帧才充满（否则她自己的自动放技能先放掉了，演示不出就绪分支）
			for a in g.squad.syn.acts:
				if a.p != null and a.p.id == ready:
					var due := false
					if str(a.dr.kind) == "volley":
						due = float(a.age) + dt >= float(a.dr.get("wind", 0.0))
					elif int(a.phase) == 1:
						due = float(a.age) - float(a.t_phase) + dt >= float(a.dr.get("dur", 0.2))
					if due and a.p.sp[0] < a.p.sp_need(0):
						a.p.sp[0] = a.p.sp_need(0)
		g.enemies_sys.build_grid()
		g._update(dt)
		g.world.update_visuals(dt)
		g.world.present_step()
		if frame % 2 != 0: continue
		var stage := "pre" if frame < cast_frame else "cast"
		var marks: Array = []
		var tf: Transform2D = get_viewport().get_canvas_transform() * get_viewport().get_final_transform().affine_inverse()
		for a in g.squad.syn.acts:
			if str(a.dr.kind) == "volley":
				stage = "cast" if int(a.shots) == 0 and float(a.age) < float(a.dr.get("wind", 0.0)) else "hit"
			else:
				stage = ["cast", "dash", "hit"][clampi(int(a.phase), 0, 2)]   # 0 起手 / 1 冲刺途中 / 2 命中收势
			stage_seen = true
			if a.p != null:
				marks.append({"who": a.p.id, "p": _xy(tf * a.p.pos), "t": _xy(tf * Vector2(a.tpos)) if a.tpos != Vector2.INF else []})
		if frame > cast_frame and g.squad.syn.acts.is_empty() and stage_seen:
			stage = "after"
		log.frames.append({"f": frame, "stage": stage, "marks": marks, "casts": g.telemetry.op_casts.duplicate()})
		g.queue_redraw()
		g.fx_add.queue_redraw()
		g.fg.queue_redraw()
		g.hud.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var im := get_viewport().get_texture().get_image()
		assert(im.save_png(output.path_join("f_%04d.png" % frame)) == OK)
	log.acts = int(g.squad.syn.n)
	log.casts = g.telemetry.op_casts.duplicate()
	log["size"] = [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]
	var file := FileAccess.open(output.path_join("log.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(log))
	file.close()
	print("SYNERGY CAPTURE cast=", cast, " syn_n=", log.acts, " casts=", log.casts)
	get_tree().quit(0)


static func _xy(v: Vector2) -> Array:
	return [snappedf(v.x, 0.1), snappedf(v.y, 0.1)]
