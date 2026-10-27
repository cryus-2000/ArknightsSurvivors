extends Node
var g
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL ",label)
func _ready() -> void:
	g = load("res://game.tscn").instantiate()
	g.demo_op = "mizuki"
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	g.t = 100.0
	var e: Dictionary = fresh()
	g.bai.boss("knight_boss").force_move(e,"断潮劈击",Vector2.RIGHT,350.0)
	check(e.get("knight_combo_active",false),"slash starts a bounded knight combo")
	if e.get("knight_combo_active",false):
		await exercise()
		check_close_and_late_act()
		check_revision()
	print("KNIGHT COMBO failures=",failures)
	g.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if failures else 0)
func fresh(phase := 1) -> Dictionary:
	g.warns.clear()
	g.bai.finals.hazards.clear()
	g.enemies.clear()
	g.fx.clear()
	g.bai.token_owner = null
	var e: Dictionary = g.spawner.new_enemy("knight_boss",Vector2.ZERO)
	e.phase = phase
	e.age = 20.0
	e.invuln = false
	e.channel = 0.0
	e.stakes = [{"pos":Vector2(2000,2000),"born":0.0,"until":INF}]
	g.bosses = [e]
	g.boss = e
	g.final_boss = e
	g.enemies.append(e)
	g.ppos = Vector2(350,0)
	return e
func tick(e: Dictionary, dt := 0.05) -> void:
	g.t += dt
	e.wind = maxf(0,e.wind-dt)
	e.stun = maxf(0,e.stun-dt)
	e.break_t = maxf(0,e.get("break_t",0.0)-dt)
	e.kb = e.kb.move_toward(Vector2.ZERO,float(e.get("dash_decel",900.0))*dt)
	if e.kb == Vector2.ZERO: e.kb_self = false
	g.invuln = 999.0
	g.bai.boss_step(e,dt,(g.ppos-e.pos).normalized(),g.ppos.distance_to(e.pos))
	g.tele.update_warns(dt)
func exercise() -> void:
	var script = g.bai.boss("knight_boss")
	for phase in [1,2]:
		for opener in ["断潮劈击","踏冰裂阵","侧踏挑枪","冲锋","冰线","长枪连刺"] + (["掷枪"] if phase==1 else ["长枪回旋"]):
			var e: Dictionary = fresh(phase)
			e.gates_passed = 1
			script.force_move(e,opener,Vector2.RIGHT,350)
			var seen: Array = [opener]
			var prior: String = opener
			var seen_warnings: Array = g.warns.duplicate()
			var charges: int = 1 if opener=="冲锋" else 0
			var last_arc: Dictionary = {}
			for i in 400:
				if e.get("dash_t",0.0)>0: g.ppos = Vector2(90,0)
				tick(e)
				for w in g.warns:
					if not seen_warnings.any(func(old):return is_same(old,w)):
						seen_warnings.append(w)
						if w.act=="dash": charges+=1
				for h in g.bai.finals.hazards:
					if h.motion=="crescent": last_arc=h
				var name: String = e.get("move_name","")
				if name != prior:
					seen.append(name)
					prior=name
				if not e.get("knight_combo_active",false): break
			check(not e.get("knight_combo_active",false),opener+" finite combo")
			check(seen.size()>=2,opener+" actually chains")
			check(seen.size()<=4,opener+" bounded sequence")
			if opener == "断潮劈击": check(seen[1]=="冲锋","slash immediately links to charge")
			check(e.get("break_t",0.0)>0,opener+" ends in punish window")
			if opener=="长枪连刺": check(not last_arc.is_empty() and last_arc.age>=last_arc.life,"last flying slash survives until natural expiry before recovery")
			if phase==2 and opener=="冲锋": check(charges==3,"reborn charge remains exactly three dashes")
			print("COMBO ",phase," ",seen," dashes=",charges)
	# Interruptions cannot resume a queued strike.
	for cause in ["stun","break_t","invuln","dead","phase"]:
		var e: Dictionary = fresh()
		script.force_move(e,"断潮劈击",Vector2.RIGHT,350)
		if cause in ["dead","invuln"]: e[cause]=true
		elif cause=="phase": e.phase=2
		else: e[cause]=1.0
		script.combo_step(e,Vector2.RIGHT,350,false)
		check(not e.get("knight_combo_active",false),cause+" clears combo")
		check(not g.warns.any(func(w):return is_same(w.owner,e) and w.dmg>0 and not w.done),cause+" clears harmful warning")
	# A real first-phase pillar collision cancels all queued followups.
	var e: Dictionary = fresh()
	script.force_move(e,"断潮劈击",Vector2.RIGHT,350)
	e.stakes=[{"pos":e.pos,"born":0.0,"until":INF}]
	e.kb_self=true
	e.kb=Vector2(500,0)
	script._knight_stakes(e,.05)
	check(not e.get("knight_combo_active",false) and e.break_t>0,"pillar interrupts combo and exposes boss")


func check_close_and_late_act() -> void:
	var script = g.bai.boss("knight_boss")
	for phase in [1,2]:
		var e: Dictionary = fresh(phase)
		script.force_move(e,"侧踏挑枪",Vector2.RIGHT,350)
		g.ppos = g.warns[0].destination+Vector2(50,0)
		var expected: String = "长枪回旋" if phase==2 else "长枪连刺"
		var saw := false
		for i in 250:
			tick(e)
			saw = saw or e.get("move_name","")==expected
			if not e.get("knight_combo_active",false): break
		check(saw,"close sidestep uses phase-specific finisher")
	var e: Dictionary = fresh()
	e.gates_passed = 2
	script.force_move(e,"冲锋",Vector2.RIGHT,350)
	var count := 0
	var last := -1.0
	for i in 300:
		tick(e)
		var act: Dictionary = e.get("last_act",{})
		if act.get("act","")=="dash" and float(act.t)>last:
			last=act.t
			count+=1
		if not e.get("knight_combo_active",false): break
	check(count==2,"first-phase third-act charge stays a two-dash chain")


func check_revision() -> void:
	var script = g.bai.boss("knight_boss")
	var first: Dictionary = fresh(1)
	script.force_move(first,"冲锋",Vector2.RIGHT,350)
	var a: Dictionary = g.warns[0].duplicate()
	var reborn: Dictionary = fresh(2)
	script.force_move(reborn,"冲锋",Vector2.RIGHT,350)
	var b: Dictionary = g.warns[0]
	check(b.dur<a.dur and b.dur-b.track>=0.399,"reborn tell is faster with readable fixed lock")
	check(is_equal_approx(b.spd/a.spd,1.4),"reborn charge travels 40 percent faster")
	check(is_equal_approx(b.spd*b.spd/(2*b.dash_decel),a.spd*a.spd/(2*a.dash_decel)),"faster charge preserves warning distance")
	g.tele.warn_resolve(b)
	check(reborn.dash_decel==b.dash_decel,"release passes deceleration to movement")
	var e: Dictionary = fresh(2)
	script.force_move(e,"断潮劈击",Vector2.RIGHT,350)
	check(e.knight_combo_queue==["冲锋","再冲锋","@近身收招"],"phase two slash has turning second charge variant")
	e = fresh()
	script.force_move(e,"长枪连刺",Vector2.RIGHT,250)
	check(g.warns[0].skin=="ice_thrust" and g.warns[2].len>g.warns[0].len,"finisher threatens medium range with longer final thrust")
	e = fresh(2)
	script.force_move(e,"长枪回旋",Vector2.RIGHT,250)
	check(g.warns[0].r==560.0 and g.warns[0].motion=="expanding" and g.warns[0].gap_half>=0.7,"larger spin retains rear escape gap")

	# A vertically distant target is outside the ground ellipse, despite Euclidean proximity.
	e = fresh(2)
	g.ppos=Vector2(0,250)
	e.knight_combo_active=true
	e.knight_combo_queue=["@侧击"]
	e.knight_combo_phase=2
	e.knight_combo_until=g.t+18
	e.knight_combo_next=g.t
	script.combo_step(e,Vector2.DOWN,250,true)
	check(g.warns[0].act=="dash","vertical target outside spin ellipse gets charge instead of empty spin")
