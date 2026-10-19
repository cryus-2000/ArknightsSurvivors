extends Node
# Deterministic effect trace: both revisions run this same harness.
func _ready() -> void:
	var id := "wisadel"
	var slot := 0
	var rate := 1.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--op="): id = arg.get_slice("=", 1)
		if arg.begins_with("--probe-slot="): slot = int(arg.get_slice("=", 1))
		if arg.begins_with("--probe-rate="): rate = float(arg.get_slice("=", 1))
	var g = load("res://game.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	var o = g.squad.get_op(id)
	o.sp = [-10000.0, -10000.0, -10000.0]
	o.pos = g.ppos
	o.is_leader = true
	o.elite = 2
	g.stats.add(&"op_aspd", "override", rate, "lifecycle_trace", "op:" + id)
	o.refresh_stats()
	g.hp = g.max_hp * 0.1
	for old in g.enemies: old.dead = true
	g.enemies = []
	for k in 6:
		var e: Dictionary = g.spawner.spawn_enemy("runner", o.pos + Vector2(70 + k * 11, k * 3))
		e.hp = 1000000.0
		e.max_hp = e.hp
	g.enemies_sys.build_grid()
	o.start_skill(Vector2.INF, slot)
	var records := []
	for tick in 1440:
		g.t += 1.0 / 60.0
		o.follow(1.0 / 60.0, o.pos)
		o.update(1.0 / 60.0)
		g.weapons_sys.update_bullets(1.0 / 60.0)
		var health := []
		for e in g.enemies: health.append(e.hp)
		var effect := {}
		for pair in [["wd", "ammo"], ["sa", "hot_t"], ["sa", "calc"], ["sz", "haze_t"]]:
			if o.hw.has(pair[0]): effect[pair[1]] = o.hw[pair[0]][pair[1]]
		records.append({"tick": tick, "hp": g.hp, "enemy_hp": health, "atk_n": o.atk_n, "ammo": o.ammo.duplicate(), "perm": o.perm_on.duplicate(), "effects": effect, "rng": g.rng_states(), "anim": o.anim_state().kind})
	print("LIFECYCLE_TRACE " + JSON.stringify(records, "", true, true))
	get_tree().quit()
