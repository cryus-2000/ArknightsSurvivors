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
		o.phases.index = 1
		o.set_attack_phase(o.skill_seq(1).phases[1], false)
		o.phases.transition = 0.0
		o.phases.queue = []
		wd.shells = []
		o.attack_t = 0.0
		o.cd = 0.0
		OB._h4_cannon_start(o, a)
		ok(o.anim_state().kind==str(o.sq.attack),"no ordinary attack flash on S2 start")
		ok(absf(o.cd - 1.4*.8/rate) < .0001, "S2 attack interval follows ASPD")
		o.attack_t = o.attack_dur-o.attack_fire_at
		o._release()
		ok(wd.shells.size() == 1 and o.phases.queue.size() == 3, "only first of four shells fires at release")
		for k in range(1,4):
			o.attack_t = o.attack_dur - (o.attack_fire_at+(o.attack_dur-o.attack_fire_at)*k/5.0 + .00001)
			o.AttackPhases.tick(o,0.0)
			ok(wd.shells.size()==k+1, "one shell per recovery pose")
		ok(o.phases.get("queue", []).is_empty() and o.acting(), "four shots complete before recovery unlock")
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
	o.phases.round = o.phases.config[0].duplicate(true)
	o.phases.round["attack"] = a
	o.phases.round["anim"] = "s2_attack"
	o.atk_aim=Vector2.ZERO
	o.phase_shot(o.phases.round,0)
	ok(wd.shells.size()==1, "normal phase emits one area shell")
	OB._h4wd_tick(o,wd,.4)
	ok(enemies.all(func(e):return e.hp<1000000.0), "all six enemies in blast are damaged")
	# Real update/follow path: normal -> overload -> recovery -> idle.
	g.stats.remove_source("s2_test")
	o.refresh_stats()
	o._sq_clear()
	o.attack_t=0.0
	o.fire_t=-1.0
	o.AttackPhases.cancel(o)
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
	ok(o.phases.get("queue", []).is_empty(),"no queued shots after ending")
	# Startup must own the channel before its effect binding exists.
	o._sq_clear()
	o.attack_t = 0.0
	o.fire_t = -1.0
	o.start_skill(Vector2.INF, 2)
	o.sp[1] = o.sp_need(1)
	ok(o.skills_occupied() and not o.manual_ready(1), "S3 startup locks before load")
	o.start_skill(Vector2.INF, 1)
	ok(o.cur_skill == 2, "S2 cannot interrupt unreleased S3 startup")
	# Register the S3 capability through its real cast before testing its final recovery.
	o.cur_skill = 2
	o._release_skill()
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
	ok(o.skill_active_left(1)<=0.0 and o.phases.get("queue", []).is_empty(),"empty field completes safely")
	for slot in [1, 2]:
		o.on_leave()
		o.pos = g.ppos
		o.sp = [-10000.0, -10000.0, -10000.0]
		o.start_skill(Vector2.INF, slot)
		ok(o.acting() and o.fire_t >= 0.0, "real startup has pending release")
		o.manual_buf = 0.2
		o.manual_dir = Vector2.LEFT
		o.manual_pt = o.pos + Vector2(-50, 0)
		o.atk_aim = Vector2.LEFT
		o.manual_buf_dir = Vector2.LEFT
		o.manual_buf_pt = o.manual_pt
		o.on_leave()
		ok(o.manual_dir == Vector2.ZERO and o.manual_pt == Vector2.INF and o.atk_aim == Vector2.ZERO and o.manual_buf_dir == Vector2.ZERO and o.manual_buf_pt == Vector2.INF, "cancelled manual aim cannot leak into redeployment")
		ok(not o.acting() and o.fire_t < 0.0 and o.manual_buf == 0.0 and o.sq_ph == 0, "leave cancels unreleased action and buffer")
		o.cd = 1000.0
		for k in 90:
			o.follow(1.0/60, o.pos)
			o.update(1.0/60)
		ok(o.phases.is_empty() and o.skill_active_left(slot) == 0.0, "cancelled startup never releases on same instance")
		ok(not o.skills_occupied(), "redeployed instance has no stale skill ownership")
	print("WISADEL S2 checks=%d failures=%d" % [checks,failures])
	get_tree().quit(1 if failures else 0)
