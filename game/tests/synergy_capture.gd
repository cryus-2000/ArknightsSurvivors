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
	var n_foes := 9
	var elite := true
	var zoom := 1.5
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
	var dist: float = clampf(gate * 0.8, 150.0, 300.0)
	var vs: float = clampf(dist * 0.42, 45.0, 100.0)    # 三个小团上下错开
	var cr: float = clampf(dist * 0.13, 14.0, 26.0)     # 每个小团的半径：团与团之间留出空地
	var centres: Array = [Vector2(dist * 0.92, -vs), Vector2(dist * 1.05, 0.0), Vector2(dist * 0.92, vs)]
	var foes: Array = []
	for k in n_foes:   # 9 只左右的杂兵分成 3 个小团（真实移动，但慢一些，团不会立刻糊在一起）
		var at: Vector2 = g.ppos + centres[k % 3] + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, cr)
		foes.append(g.spawner.spawn_enemy("bone", at))
	if elite:
		foes.append(g.spawner.spawn_enemy("knight", g.ppos + centres[1] + Vector2(cr * 0.4, 0.0)))
		foes[-1].elite = true
	for e in foes:
		e.hp = 1.0e9
		e.maxhp = 1.0e9
		e.dmg = 0.0   # 怪不打人：画面不被受击红边 / 飘字干扰，只看技能和合击
		e.spd = float(e.spd) * 0.3   # 慢慢逼近：小团散着的时间长一点，冲刺路线和落点看得清
	for op in g.squad.ops:   # 其余人技力清零：没点名「就绪」的搭档一律是没就绪（演示「没就绪 → 重击 / 弹幕」那一支）
		if op.id != cast:
			for si in 3:
				op.sp[si] = 0.0
	var dt := 1.0 / 60.0
	var cast_frame := int(0.8 / dt)
	var log := {"cast_at": 0.8, "acts": 0, "casts": {}, "frames": [], "gate": gate, "dist": dist}
	var stage_seen := false
	var cc: Vector2 = g.ppos + Vector2(dist * 0.5, 0.0)   # 镜头中心：慢慢跟向「动作中心」
	for frame in int(secs / dt):
		g.hp = g.max_hp
		g.move_in = Vector2.ZERO
		var tgt_c: Vector2 = g.ppos
		var alive: Array = foes.filter(func(e): return not e.dead)
		if not alive.is_empty():
			var fc := Vector2.ZERO
			for e in alive: fc += e.pos
			tgt_c = (g.ppos + fc / alive.size()) * 0.5
		for a in g.squad.syn.acts:
			if a.p != null and a.tpos != Vector2.INF:
				tgt_c = (a.p.pos + Vector2(a.tpos) + g.ppos) / 3.0
		cc = cc.lerp(tgt_c, 0.06)
		g.glance_pos = cc   # 借「镜头一瞥」把镜头固定在 cc（每帧重设，一直处于 hold）
		g.glance_t = g.glance_ease
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
		if not stage_seen:   # 合击开始之前，队友一律站在编队位（近战队友会自己前压到怪堆里，冲刺的路线就看不见了）
			for op in g.squad.ops:
				if not op.is_leader and op.syn_mv.is_empty():
					op.pos = g.ppos + g.squad._slot_offset(op.slot)
		g.enemies_sys.build_grid()
		g._update(dt)
		g.world.update_visuals(dt)
		g.world.present_step()
		if frame % 2 != 0: continue
		var stage := "pre" if frame < cast_frame else "cast"
		var marks: Array = []   # 世界坐标，渲染完成后（镜头已就位）再换算成屏幕坐标
		for a in g.squad.syn.acts:
			if str(a.dr.kind) == "volley":
				stage = "cast" if int(a.shots) == 0 and float(a.age) < float(a.dr.get("wind", 0.0)) else "hit"
			else:
				stage = ["cast", "dash", "hit"][clampi(int(a.phase), 0, 2)]   # 0 起手 / 1 冲刺途中 / 2 命中收势
			stage_seen = true
			if a.p != null:
				marks.append({"who": a.p.id, "p": a.p.pos, "t": Vector2(a.tpos)})
		if frame > cast_frame and g.squad.syn.acts.is_empty() and stage_seen:
			stage = "after"
		var opos := {}
		for op in g.squad.ops:
			opos[op.id] = op.pos
		var entry := {"f": frame, "stage": stage, "marks": marks, "casts": g.telemetry.op_casts.duplicate(), "ops": opos, "lead": g.squad.leader().id}
		g.queue_redraw()
		g.fx_add.queue_redraw()
		g.fg.queue_redraw()
		g.hud.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var im := get_viewport().get_texture().get_image()
		assert(im.save_png(output.path_join("f_%04d.png" % frame)) == OK)
		var tf: Transform2D = get_viewport().get_canvas_transform() * get_viewport().get_final_transform().affine_inverse()
		for m in entry.marks:
			m["p"] = _xy(tf * Vector2(m.p))
			m["t"] = _xy(tf * Vector2(m.t)) if Vector2(m.t) != Vector2.INF else []
		for k in entry.ops.keys():
			entry.ops[k] = _xy(tf * Vector2(entry.ops[k]))
		log.frames.append(entry)
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
