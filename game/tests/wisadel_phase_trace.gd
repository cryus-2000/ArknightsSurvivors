extends Node
var events := []
var seen := []
func record(o, tick: int, part: String) -> void:
	for s in o.hw.wd.shells:
		if s in seen:
			continue
		seen.append(s)
		events.append({"tick":tick,"part":part,"from":[s.from.x,s.from.y],"to":[s.to.x,s.to.y],"dmg":s.dmg,"r":s.r,"src":s.src,"quake":s.quake,"stun":s.stun})
func _ready() -> void:
	var rate := 1.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase-rate="):rate=float(arg.get_slice("=",1))
	var g = load("res://game.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	var o = g.squad.get_op("wisadel")
	o.sp=[-10000.0,-10000.0,-10000.0]
	o.pos=g.ppos;o.is_leader=true
	g.stats.add(&"op_aspd","override",rate,"phase_trace","op:wisadel")
	o.refresh_stats()
	for old in g.enemies:old.dead=true
	g.enemies=[]
	for k in 6:
		var e: Dictionary=g.spawner.spawn_enemy("runner",o.pos+Vector2(100+k*23, k*7))
		e.hp=1000000.0;e.max_hp=e.hp
	g.enemies_sys.build_grid()
	o.start_skill(Vector2.INF,1)
	for tick in 660:
		o.follow(1.0/60,o.pos)
		record(o,tick,"follow")
		o.update(1.0/60)
		record(o,tick,"update")
	var health := []
	for e in g.enemies:health.append(e.hp)
	print("PHASE_TRACE "+JSON.stringify({"events":events,"health":health,"atk_n":o.atk_n,"rng":str(g.rng.state)},"",true,true))
	get_tree().quit()
