extends Node
const OB = preload("res://scripts/characters/blocks/seg_skalter.gd")
var g
var failures := 0
var checks := 0
func ok(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)
func _ready() -> void:
	g = load("res://game.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	var o = g.squad.get_op("wisadel")
	o.sp = [-10000.0, -10000.0, -10000.0]
	o.pos = g.ppos
	o.is_leader = true
	for old in g.enemies:
		old.dead = true
	g.enemies = []
	var enemies := []
	for k in 6:
		var e: Dictionary = g.spawner.spawn_enemy("runner", o.pos + Vector2(100 + k*2, 0))
		e.hp = 1000000.0
		e.max_hp = e.hp
		enemies.append(e)
	g.enemies_sys.build_grid()
	o.start_skill(Vector2.INF, 1)
	for k in 24:
		o.follow(1.0/60, o.pos)
		o.update(1.0/60)
	ok(o.s_t[1] > 7.7 and o.s_t[1] <= 8.0, "S2 starts an eight-second timer")
	ok(o.skill_active_left(1) > 0.0 and o.sq_i == 1, "HUD and native sequence persist")
	ok(o.charge_skills(0.0) == -1, "S1/S3 wait while S2 active")
	o.elite=2
	var before: float=o.sp[2]
	o.tick_sp(.1)
	ok(o.sp[2]>before,"S3 continues charging during S2")
	var wd: Dictionary = o.hw.wd
	var a: Dictionary = o.B.attack
	for rate in [1.0, 2.0, 4.0]:
		g.stats.remove_source("s2_test")
		g.stats.add(&"op_aspd", "override", rate, "s2_test", "op:wisadel")
		o.refresh_stats()
		o.s_t[1] = 2.0
		wd.s2_over = true
		wd.s2_transition = 0.0
		wd.s2_queue = []
		wd.shells = []
		o.attack_t = 0.0
		o.cd = 0.0
		OB._h4_cannon_start(o, a)
		ok(o.anim_state().kind==str(o.sq.attack),"no ordinary attack flash on S2 start")
		ok(absf(o.cd - 1.4*.8/rate) < .0001, "S2 attack interval follows ASPD")
		o.attack_t = o.attack_dur-o.attack_fire_at
		OB._h4_cannon_release(o, a)
		ok(wd.shells.size() == 1 and wd.s2_queue.size() == 3, "only first of four shells fires at release")
		for k in range(1,4):
			o.attack_t = o.attack_dur - (o.attack_fire_at+(o.attack_dur-o.attack_fire_at)*k/5.0 + .00001)
			OB._h4_s2_tick(o,a,wd,0.0)
			ok(wd.shells.size()==k+1, "one shell per recovery pose")
		ok(wd.s2_queue.is_empty() and o.acting(), "four shots complete before recovery unlock")
		var origins := {}
		for shell in wd.shells:
			origins[str(shell.from)] = true
			ok(shell.stun == 0.0 and shell.quake, "no added stun; every shell retains aftershock")
		ok(origins.size()==4, "four source weapon muzzle origins")
		# Last round keeps its four shots even if the skill timer expires mid-action.
		o.s_t[1] = 0.0
		ok(o.skill_active_left(1)>0.0, "last round completes before visual end")
	# One normal shell damages more than three enemies in its blast.
	wd.shells=[]
	wd.s2_attack_over=false
	o.atk_aim=Vector2.ZERO
	OB._h4_s2_shot(o,a,wd,0)
	ok(wd.shells.size()==1, "normal phase emits one area shell")
	OB._h4wd_tick(o,wd,.4)
	ok(enemies.all(func(e):return e.hp<1000000.0), "all six enemies in blast are damaged")
	# Real update/follow path: normal -> overload -> recovery -> idle.
	g.stats.remove_source("s2_test")
	o.refresh_stats()
	o._sq_clear()
	o.attack_t=0.0
	o.fire_t=-1.0
	wd.s2_queue=[]
	wd.ammo=0
	o.ammo[0]=3
	o.start_skill(Vector2.INF,1)
	var seen := {}
	for k in 660:
		o.follow(1.0/60,o.pos)
		o.update(1.0/60)
		seen[o.anim_state().kind]=true
		if o.s_t[1]>0.0:
			ok(o.ammo[0]==3,"S2 preserves pending S1 rounds")
	for kind in ["s2_start","s2_attack","s2_over_start","s2_over_attack","s2_over_end"]:
		ok(seen.has(kind),"live sequence includes "+kind)
	ok(o.skill_active_left(1)<=0.0 and o.sq_ph==0,"S2 ends and unlocks")
	ok(wd.s2_queue.is_empty(),"no queued shots after ending")
	# S3 last shot still owns its end animation before a ready S2 may deploy.
	o.hw.wd.ammo = 0
	o.sq_i = 2
	o.sq_ph = 3
	o.sp[1] = o.sp_need(1)
	ok(o.charge_skills(0.0) == -1, "S2 cannot interrupt S3 recovery")
	o._sq_clear()
	o.sp[1] = -10000.0
	# No targets: timer still ends and no stray queue is left.
	for e in enemies:e.dead=true
	g.enemies_sys.build_grid()
	o._sq_clear();o.attack_t=0.0;o.fire_t=-1.0
	o.start_skill(Vector2.INF,1)
	for k in 600:
		o.follow(1.0/60,o.pos);o.update(1.0/60)
	ok(o.skill_active_left(1)<=0.0 and wd.s2_queue.is_empty(),"empty field completes safely")
	print("WISADEL S2 checks=%d failures=%d" % [checks,failures])
	get_tree().quit(1 if failures else 0)
