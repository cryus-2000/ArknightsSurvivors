extends Node
## 10-25 自动技能「范围内没有敌人不放」探针：队长站定，交替「空场 20 秒 / 敌人逼近 20 秒」，
## 记录目标干员（--probe-op=）每次放技能（sp 骤降）时的最近敌人距离与 radius 内敌人数，再汇总。
## 用法：godot --headless --path game res://tests/skill_gate_probe.tscn -- --regression --balance --seed=1 --op=siege --probe-op=siege

func _ready() -> void:
	var who := "siege"
	var secs := 120.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--probe-op="): who = arg.get_slice("=", 1)
		if arg.begins_with("--probe-secs="): secs = float(arg.get_slice("=", 1))
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
	var prev: Array = [0.0, 0.0, 0.0]
	var casts: Array = []
	var empty_casts := 0
	var dt := 1.0 / 60.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for frame in int(secs / dt):
		var phase: int = int(frame * dt / 20.0) % 2   # 0 空场 / 1 敌人逼近
		g.hp = g.max_hp
		g.move_in = Vector2.ZERO
		if phase == 0:
			for e in g.enemies: e.dead = true
		elif frame % 120 == 0:
			for k in 3:
				g.spawner.spawn_enemy("bone", g.ppos + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(320.0, 520.0))
		g.enemies_sys.build_grid()
		g._update(dt)
		if frame % 300 == 0: print("TICK ", frame, " wall=", Time.get_ticks_msec(), " enemies=", g.enemies.size())
		for i in 3:
			var sp: float = float(o.sp[i])
			if sp < float(prev[i]) - 0.5 * maxf(1.0, float(o.sp_need(i))) and o.sp_need(i) > 0.0 and not bool(o.perm[i]):
				var ne: Array = g.enemies_sys.nearest(1, 900.0, o.pos)
				var d: float = o.pos.distance_to(ne[0].pos) if not ne.is_empty() else -1.0
				var c150: int = g.enemies_sys.nearest(99, 150.0, o.pos).size()
				casts.append({"t": snappedf(frame * dt, 0.1), "skill": i + 1, "phase": phase, "nearest": snappedf(d, 1.0), "n150": c150})
				if d < 0.0: empty_casts += 1
			prev[i] = sp
	print("PROBE ", who, " casts=", casts.size(), " empty_field_casts=", empty_casts)
	for c in casts: print("CAST ", JSON.stringify(c))
	get_tree().quit(0)
