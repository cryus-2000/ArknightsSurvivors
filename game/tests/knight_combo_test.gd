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
		check_super_armor()
		check_reborn()
		check_acts()
		check_reborn3()
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
		# 重生冲锋形态只剩冲锋连段（docs/183 v2）；回旋 / 一阶段大招在 check_reborn 单独查
		for opener in (["断潮劈击","踏冰裂阵","侧踏挑枪","冲锋","冰线","长枪连刺","掷枪"] if phase==1 else ["冲锋"]):
			var e: Dictionary = fresh(phase)
			e.gates_passed = 1 if opener=="掷枪" else 0   # 每幕自己的大招组（docs/183 v2）：一幕原三招，掷枪二幕起
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
	for phase in [1]:
		var e: Dictionary = fresh(phase)
		script.force_move(e,"侧踏挑枪",Vector2.RIGHT,350)
		g.ppos = g.warns[0].destination+Vector2(50,0)
		var expected: String = "长枪连刺"
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
	check(not script.force_move(e,"断潮劈击",Vector2.RIGHT,350) and not script.force_move(e,"侧踏挑枪",Vector2.RIGHT,350),"reborn drops first-phase finals")
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

## 10-28 用户「骑士的攻击会被打断」：出招期间（预警 / 连段）干员眩晕、击退、拖拽不生效，连段不被取消；破绽期照常吃眩晕
func check_super_armor() -> void:
	var script = g.bai.boss("knight_boss")
	var e: Dictionary = fresh()
	script.force_move(e,"断潮劈击",Vector2.RIGHT,350.0)
	check(g.bai.super_armor(e),"knight casting has super armor")
	g.enemies_sys.add_cc(e,2.0,1.0)
	check(e.stun<=0.0,"operator stun ignored while casting")
	check(e.slow>0.0,"slow still applies while casting")
	var p0: Vector2 = e.pos
	g.enemies_sys.apply_kb(e,Vector2(500,0))
	g.enemies_sys.hold_at(e,Vector2(999,999))
	check(e.kb.length()<1.0 and e.pos==p0,"knockback / drag ignored while casting")
	tick(e)
	check(e.get("knight_combo_active",false),"combo survives an operator stun")
	var f: Dictionary = fresh()
	g.combat.start_break(f,2.0)
	check(not g.bai.super_armor(f),"break window has no super armor")
	g.enemies_sys.add_cc(f,1.0)
	check(f.stun>0.0,"operator stun lands during break")

## docs/183 v2 重生冲锋形态：回旋后外射冰锥 + 破绽；冲锋停下裂地；寒冷条照常涨
func check_reborn() -> void:
	var script = g.bai.boss("knight_boss")
	var e: Dictionary = fresh(2)
	g.ebullets.clear()
	script.force_move(e,"长枪回旋",Vector2.RIGHT,250)
	var cones := false
	var brk := false
	for i in 80:
		tick(e)
		cones = cones or g.ebullets.any(func(b):return b.get("knight_shard",false) and b.vel.length()>200.0)
		brk = brk or e.get("break_t",0.0)>0.0
	check(cones,"reborn spin fires fast ice cones")
	check(brk,"reborn spin ends in a break window")
	e = fresh(2)
	g.warns.clear()
	e.last_act = {"act":"dash","ang":0.0,"t":g.t}
	e.kn_dashing = true
	e.kb_self = false
	tick(e)
	check(g.warns.filter(func(w):return is_same(w.owner,e) and w.get("skin","")=="ice_lance").size()==3,"reborn charge stop cracks three ground lines")
	e = fresh(2)
	g.warns.clear()
	g.ppos = e.pos+Vector2(60,0)
	e.kcold = 0.0
	e.wind = 99.0
	tick(e)
	check(float(e.get("kcold",0.0))>0.0,"cold builds again in charge form")

## docs/183 v2 每幕招式组 + 三幕寒潮 + 二幕冰棱
func check_acts() -> void:
	var script = g.bai.boss("knight_boss")
	var names: Array = []
	for act in 3:
		var e: Dictionary = fresh(1)
		e.gates_passed = act
		names.append(g.bai.finals.names_for(e))
	check(names[0] != names[1] and names[1] != names[2] and not names[2].has("断潮劈击"),"each act has its own final-move set")
	var e: Dictionary = fresh(1)
	e.gates_passed = 2
	g.ebullets.clear()
	check(script.force_move(e,"寒潮回卷",Vector2.RIGHT,300),"act three rolls the cold tide")
	var snow := 0
	var brk := false
	for i in 120:
		tick(e)
		snow = maxi(snow, g.ebullets.filter(func(b):return b.get("knight_snow",false)).size())
		brk = brk or e.get("break_t",0.0)>0.0
	check(snow>=20,"cold tide spirals snow bullets")
	check(brk,"cold tide ends in a break")
	check(g.ebullets.all(func(b):return not b.get("knight_snow",false) or g.combat.ground_d(b.pos,e.pos)>=80.0),"cold tide eye stays clear")
	e = fresh(1)
	e.gates_passed = 1
	g.ebullets.clear()
	script.force_move(e,"掷枪",Vector2.RIGHT,400)
	var bolts := false
	for i in 60:
		tick(e)
		bolts = bolts or g.ebullets.any(func(b):return b.get("knight_prism",false))
	check(bolts,"act two spear raises bursting ice prisms")
	var ej: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/enemies.json"))
	check(is_equal_approx(float(ej.enemies.knight_boss.gates[1]),0.5),"third act starts at 50 percent")

## docs/171 重生 v3：长驱冲锋撞场边眩晕、绕场巡猎掷冰枪后破绽、Z 字三连第二冲折 90°
func check_reborn3() -> void:
	var script = g.bai.boss("knight_boss")
	var zf = g.zone_frozen
	var zc = g.zone_next_c
	var zr = g.zone_next_r
	var zc2 = g.zone_c
	var zr2 = g.zone_r
	g.zone_frozen = true
	g.zone_next_c = Vector2.ZERO
	g.zone_next_r = 600.0
	g.zone_c = Vector2.ZERO
	g.zone_r = 600.0
	var e: Dictionary = fresh(2)
	check(script.force_move(e,"长驱冲锋",Vector2.RIGHT,350),"reborn drive starts")
	var stunned := false
	var moved := 0.0
	for i in 100:
		var p0: Vector2 = e.pos
		e.pos += e.kb*0.05
		tick(e)
		moved += e.pos.distance_to(p0)
		stunned = stunned or str(e.get("brk_label",""))=="眩晕"
		if stunned: break
	check(stunned and not e.has("kn_drive"),"reborn drive crashes into the arena edge and stuns")
	check(e.get("ice_strips",[]).size()>=2,"reborn drive leaves ice behind")
	e = fresh(2)
	g.ppos = Vector2(100,0)
	check(script.force_move(e,"绕场巡猎",Vector2.RIGHT,100),"reborn lap starts")
	var lances := 0
	var brk := false
	var far := 0.0
	for i in 200:
		var n0: int = g.warns.size()
		tick(e)
		far = maxf(far,e.pos.length())
		lances += g.warns.slice(n0).filter(func(w):return w.get("skin","")=="ice_lance").size()
		if e.get("break_t",0.0)>0.0: brk = true
		if brk: break
		e.pos += e.kb*0.05
	check(far>=script._rim(e)-40.0,"reborn lap runs along the arena rim")
	check(lances>=6,"reborn lap throws ice lances")
	check(brk,"reborn lap ends in a break")
	e = fresh(2)
	e.kn_z = {"k":0,"t":g.t}
	script._charge(e,Vector2.RIGHT)
	var angs: Array = []
	for i in 120:
		var n0: int = g.warns.size()
		tick(e)
		for w in g.warns.slice(n0):
			if w.act=="dash": angs.append(float(w.ang))
		if angs.size()>=1: break
	check(angs.size()>=1 and absf(absf(angle_difference(float(e.kn_z.a),float(angs[0])))-PI*0.5)<0.05,"reborn triple turns 90 degrees")
	g.zone_frozen = zf
	g.zone_next_c = zc
	g.zone_next_r = zr
	g.zone_c = zc2
	g.zone_r = zr2
