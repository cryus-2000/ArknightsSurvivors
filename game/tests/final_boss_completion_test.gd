extends Node
var g
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAIL ", label)

func fresh(kind: String) -> Dictionary:
	g.warns.clear()
	g.enemies.clear()
	g.fx.clear()
	g.ebullets.clear()
	g.bai.finals.hazards.clear()
	g.bai.token_owner = null
	var e: Dictionary = g.spawner.new_enemy(kind, Vector2.ZERO)
	e.age = 20.0
	g.enemies.append(e)
	g.bosses = [e]
	g.boss = e
	g.final_boss = e
	g.ppos = Vector2(220, 0)
	if kind in ["ishar", "izumik"]:
		g.bai.setup_preview_phase2(e)
		g.t += 2.0
		e.wind = 0.0
	return e

func _ready() -> void:
	g = load("res://game.tscn").instantiate()
	g.demo_op = "mizuki"
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	# 自然流程里的招式表验 Codex 版轮转；偏执泡影 / 伊莎玛拉的连段版（boss/paranoia_combos、ishar_combos，10-27）各有自己的测试，这里关掉
	var Bal = preload("res://scripts/core/balance.gd")
	Bal.v("boss/paranoia_combos", 1.0)
	Bal._data["boss"]["paranoia_combos"] = 0
	Bal._data["boss"]["ishar_combos"] = 0
	g.t = 100.0
	g.zone_frozen = true
	g.zone_state = 3
	g.zone_c = Vector2.ZERO
	g.zone_next_c = Vector2.ZERO
	g.zone_r = 650.0
	g.zone_next_r = 650.0
	for kind in ["paranoia", "knight_boss", "ishar", "izumik"]:
		var e: Dictionary = fresh(kind)
		var script = g.bai.boss(kind)
		check(script.demo_moves(e).size() >= 7, kind + " seven distinct active moves exposed")
		for move in g.bai.finals.NAMES[kind]:
			g.warns.clear()
			g.bai.finals.hazards.clear()
			e.wind = 0.0
			e.invuln = false
			e.stun = 0.0
			e.break_t = 0.0
			check(script.force_move(e, move, Vector2.RIGHT, 220.0), kind + " force " + move)
			check(not g.warns.is_empty(), move + " actual warning")
			for w in g.warns:
				check(w.dur - w.track >= 0.399, move + " lock window")
			var resolved := false
			for tick in 80:
				g.t += 0.05
				g.invuln = 100.0
				g.tele.update_warns(0.05)
				g.bai.finals.update(e, 0.05)
				resolved = resolved or not g.fx.is_empty() or not g.bai.finals.hazards.is_empty()
			check(resolved, move + " resolves effects or moving attack")
			g.fx.clear()
			# Dead source must not produce delayed damage or retained hazards.
			g.warns.clear()
			script.force_move(e, move, Vector2.RIGHT, 220.0)
			e.dead = true
			g.tele.update_warns(10.0)
			g.bai.finals.update(e, 0.1)
			check(g.bai.finals.hazards.is_empty(), move + " death cancellation")
			e.dead = false
		# No force_move: vary range and phase as a player does, with no inherited ordinary mobs.
		e = fresh(kind)
		var seen := {}
		for tick in 2400:
			var dt := 0.1
			g.t += dt
			e.wind = maxf(0.0, e.wind - dt)
			e.cdt = maxf(0.0, e.cdt - dt)
			e.break_t = maxf(0.0, e.get("break_t", 0.0) - dt)
			e.stun = 0.0
			e.kb = Vector2.ZERO
			g.invuln = 100.0
			var dist: float = 110.0 if tick % 180 < 90 else 260.0
			g.ppos = e.pos + Vector2.from_angle(tick * 0.013) * dist
			if tick == 600:
				e.gates_passed = 1
				script.on_gate(e)
			if tick == 1200:
				e.gates_passed = 2
				script.on_gate(e)
			if tick == 1600 and kind in ["paranoia", "knight_boss"]:
				script.setup_preview_phase2(e)
			if kind == "izumik":
				e.hp = e.maxhp * (0.9 - tick / 3000.0)
			g.bai._boss_ai(e, dt, (g.ppos - e.pos).normalized(), dist)
			for w in g.warns:
				if w.name != "" and w.dmg > 0.0:
					seen[w.name] = true
			g.tele.update_warns(dt)
			g.fx.clear()
			g.ebullets.clear()
			g.shocks.clear()
		print("NATURAL ", kind, " ", seen.keys())
		for move in g.bai.finals.names_for(e):
			check(seen.has(move), kind + " natural extra " + move)
		check(seen.size() >= 7, kind + " natural seven distinct attacks")
	_test_fixes()
	_test_bubble_tracking()
	_test_knight_arc()
	_test_ice_field()
	_test_arena_ice_and_closing_walls()
	_test_ishar_pressure()
	_test_stake_cast_interruptions()
	if DisplayServer.get_name() != "headless" and Cfg.dev_args().has("--capture-ui"):
		await _capture()
	print("FINAL BOSS COMPLETION failures=", failures)
	g.bai.finals.hazards.clear()
	g.warns.clear()
	g.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures == 0 else 1)

func _test_fixes() -> void:
	var p: Dictionary = fresh("paranoia")
	g.bai.boss("paranoia").force_move(p, "叠影", Vector2.RIGHT, 220.0)
	var stack: Array = g.warns.filter(func(w): return w.get("track_pos", "") == "leader")
	check(stack.size() >= 4, "stack four hits")
	if stack.size() >= 4:
		g.tele.update_warns(0.6)
		var first: Vector2 = stack[0].pos
		g.ppos = Vector2(350, 100)
		g.tele.update_warns(0.2)
		check(stack[0].pos == first and stack[1].pos != first, "stack individually follows moving player")
	g.bai.boss("paranoia").paranoia_hatch(p, true)
	check(is_equal_approx(p.hp / p.maxhp, preload("res://scripts/core/balance.gd").v("boss/paranoia_revive", 0.8)), "paranoia revive = boss/paranoia_revive (10-28 0.5)")
	var knight: Dictionary = fresh("knight_boss")
	var script = g.bai.boss("knight_boss")
	script._knight_stakes(knight, 0.1)
	check(knight.stakes.is_empty(), "initial pillars wait for planting action")
	_finish_stake_cast(knight)
	check(knight.stakes.size() == 5, "plant action creates five pillars")
	for a in knight.stakes:
		for b in knight.stakes:
			if not is_same(a, b):
				check(a.pos.distance_to(b.pos) >= 180.0, "pillars dispersed")
	knight.stakes[0].until = 0.0
	g.t += 100.0
	script._knight_stakes(knight, 0.1)
	check(knight.stakes.size() == 4, "no expiry or partial refill")
	knight.gates_passed = 1
	script.on_gate(knight)
	check(knight.stakes.size() == 4, "gate no partial refill")
	for s in knight.stakes:
		s.until = 0.0
	script._knight_stakes(knight, 0.1)
	g.t += 1.6
	script._knight_stakes(knight, 0.1)
	check(knight.stakes.is_empty(), "empty timer alone cannot spawn pillars")
	knight.knight_combo_active=true
	check(not script.stake_cast_step(knight,Vector2.RIGHT,true),"refill waits for combo completion")
	knight.knight_combo_active=false
	_finish_stake_cast(knight)
	check(knight.stakes.size() == 5, "throw action replenishes exhausted batch together")
	var izu: Dictionary = fresh("izumik")
	izu.pos = Vector2(570, 0)
	for k in 24:
		var edge: Vector2 = g.bai.boss("izumik")._offspring_edge(izu, TAU * k / 24.0)
		check(absf(edge.distance_to(g.zone_next_c) - 585.0) < 1.0, "child on actual edge")
		check(edge.distance_to(izu.pos) >= 380.0, "child has interception travel")
	# Annulus center really safe; renderer reads identical inner/outer radii.
	var w := {"shape": "circle", "pos": Vector2.ZERO, "r": 360.0, "inner_r": 240.0}
	g.ppos = Vector2.ZERO
	check(not g.tele.hits_leader(w), "abyss inner safe region")
	g.ppos = Vector2(300, 0)
	check(g.tele.hits_leader(w), "abyss annulus dangerous")
	# Tracking uses the intended source and target, then freezes even if both move.
	g.warns.clear()
	var source: Dictionary = g.spawner.new_enemy("bone", Vector2(-180, 60))
	var aim: Dictionary = g.tele.warn(izu, "line", 1.2, {"pos": source.pos, "source": source, "ang": 0.0,
		"len": 600.0, "wid": 10.0, "track": 0.5, "act": "final_attack", "skin": "choir"})
	g.ppos = Vector2(200, 100)
	g.tele.update_warns(0.1)
	check(aim.pos == source.pos and aim.ang > 0.0, "source-relative targeting")
	g.tele.update_warns(0.5)
	var locked: Vector2 = aim.pos
	var angle: float = aim.ang
	source.pos += Vector2(0, 200)
	g.ppos += Vector2(0, 200)
	g.tele.update_warns(0.1)
	check(aim.pos == locked and aim.ang == angle, "targeted attack freezes after lock")
	source.dead = true
	g.tele.update_warns(0.6)
	check(g.warns.is_empty(), "destroyed choir source cancels queued attack")
	var hunter: Dictionary = fresh("paranoia")
	g.t += 10.0
	g.bai.finals.force_move(hunter, "追猎泡", Vector2.RIGHT, 220.0)
	g.tele.warn_resolve(g.warns[0])
	check(not g.bai.finals.hazards.is_empty(), "pursuit enters live hazard system")
	if not g.bai.finals.hazards.is_empty():
		var hazard: Dictionary = g.bai.finals.hazards[0]
		g.demo_op = ""   # Exercise real damage, not the gallery dummy immunity.
		g.state = g.S.PLAY
		g.ppos = hazard.pos
		g.invuln = 0.0
		g.shield = 0.0
		g.hp = g.max_hp
		var before: float = g.hp
		g.bai.finals.update(hunter, 0.01)
		check(g.hp < before and hazard.hit, "moving hazard applies actual protected boss damage")
		before = g.hp
		g.invuln = 0.0
		g.bai.finals.update(hunter, 0.01)
		check(g.hp == before, "one moving hazard cannot multi-hit one player")
		hunter.break_t = 1.0
		g.bai.finals.update(hunter, 0.01)
		check(g.bai.finals.hazards.is_empty(), "break clears active pressure projectiles")

func _capture() -> void:
	g.demo_op = ""
	g.state = g.S.PLAY
	g.trial.active = true
	g.trial.started_at = g.t
	g.trial.saved_progress = {}
	g.cam.position = Vector2.ZERO
	g.cam.zoom = Vector2(0.7, 0.7)
	for kind in ["paranoia", "knight_boss", "ishar", "izumik"]:
		for index in 3:
			var e: Dictionary = fresh(kind)
			e.invuln = false
			e.wind = 0.0
			g.ppos = Vector2(220, 0)
			g.ch.pos = g.ppos
			g.doc_pos = g.ppos + Vector2(40, 30)
			g.bai.finals.force_move(e, g.bai.finals.NAMES[kind][index], Vector2.RIGHT, 220.0)
			g.tele.update_warns(0.45)
			g.world.update_visuals(0.0)
			g.queue_redraw()
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://../build/final_%s_%d_warn.png" % [kind, index])
			for i in 20:
				g.t += 0.06
				g.tele.update_warns(0.06)
				g.bai.finals.update(e, 0.06)
			g.world.update_visuals(0.0)
			g.queue_redraw()
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://../build/final_%s_%d_hit.png" % [kind, index])

func _test_bubble_tracking() -> void:
	for move in ["追猎泡","泡影收束"]:
		var boss: Dictionary = fresh("paranoia")
		g.bai.finals.force_move(boss,move,Vector2.RIGHT,220.0)
		for w in g.warns: g.tele.warn_resolve(w)
		g.warns.clear()
		check(g.bai.finals.hazards.all(func(h): return h.motion == "pursuit"),move+" every bubble pursues")
		for h in g.bai.finals.hazards:
			h.age = 3.5
			h.pos = Vector2.ZERO
			h.velocity = Vector2.RIGHT*h.speed
		g.ppos=Vector2(0,500)
		g.bai.finals.update(boss,0.1)
		check(g.bai.finals.hazards.all(func(h): return h.velocity.y>0),move+" turns after old tracking cutoff")
		check(g.bai.finals.hazards.all(func(h): return h.velocity.angle()<=float(h.turn_rate)*0.1+0.001),move+" bounded turning")
		g.ppos=Vector2(0,-500)
		var angles: Array = g.bai.finals.hazards.map(func(h): return h.velocity.angle())
		g.bai.finals.update(boss,0.1)
		for i in angles.size(): check(g.bai.finals.hazards[i].velocity.angle()<angles[i],move+" re-aims at new position")
		g.fx.clear()
		for h in g.bai.finals.hazards: h.age=h.life-0.01
		g.bai.finals.update(boss,0.02)
		check(g.bai.finals.hazards.is_empty(),move+" finite lifetime")
		check(g.fx.filter(func(f): return f.kind=="bubble_pop").size()==angles.size(),move+" each expiry ruptures once")
	var image = preload("res://scripts/render/paranoia_bubble.gd").make_image(0)
	check(image.get_pixel(20,20).a<0.25,"bubble center transmits the background")   # 10-27 用户「换成紫色泡泡」内填加厚 0.035 → 0.18（e1d024a4f），仍透底
	check(image.get_pixel(20,3).a>0.05 and image.get_pixel(3,20).a>0.05,"sphere uses full height and width")
	check(image.get_pixel(0,0).a==0,"transparent sphere corners")
	check(image.get_pixel(7,7).a>image.get_pixel(20,20).a,"curved reflection is stronger than transparent center")

func _test_knight_arc() -> void:
	var boss: Dictionary = fresh("knight_boss")
	g.bai.finals.force_move(boss,"断潮劈击",Vector2.RIGHT,220.0)
	var w: Dictionary = g.warns[0]
	check(w.shape == "arc" and 2*w.r*sin(w.half)>600,"knight slash spans over 600px")
	g.tele.update_warns(0.2)
	check(g.bai.finals.hazards.is_empty(),"forming arc cannot damage early")
	w.ang = 0.0
	var center: Vector2 = w.pos - Vector2.RIGHT*w.arc_back
	check(w.r-w.arc_back<=170 and w.r*cos(w.half)-w.arc_back>60,"entire slash forms close in front of the boss")
	for a in [-w.half*.9,0.0,w.half*.9]:
		g.ppos = center + Vector2.from_angle(a)*w.r + Vector2(0,14)
		check(g.tele.hits_leader(w),"curved blade hits across its actual surface")
	for point in [Vector2.ZERO,Vector2(-330,0),Vector2(50,0),Vector2(0,330)]:
		g.ppos = point+Vector2(0,14)
		check(not g.tele.hits_leader(w),"arc hollow/back/end gaps stay safe")
	g.ppos = Vector2(0,1500)
	g.bai.finals.resolve(w)
	var h: Dictionary = g.bai.finals.hazards[0]
	check(h.ang==w.ang and h.pos==w.pos,"release keeps forward orientation and exact warning origin")
	g.bai.finals.update(boss,0.1)
	var first: float = h.pos.x
	g.bai.finals.update(boss,0.1)
	check(h.pos.x-first>first and h.velocity.x>h.speed,"slash accelerates forward")
	check(is_equal_approx(h.pos.x,190.0),"accelerated travel integrates elapsed time exactly")
	check(h.pos.y==0.0,"slash does not travel sideways")
	var test_h: Dictionary = h.duplicate()
	check(g.bai.finals._accelerated_distance(test_h,2.0)>g.bai.finals._accelerated_distance(test_h,1.0),"capped speed continues moving")

func _test_ice_field() -> void:
	var boss: Dictionary = fresh("knight_boss")
	g.ppos=Vector2.ZERO
	g.bai.finals.force_move(boss,"踏冰裂阵",Vector2.RIGHT,200)
	check(g.warns.size()==16,"ice array is two waves of eight radial sectors")
	g.ppos=Vector2(30,14)
	check(g.warns.all(func(w):return not g.tele.hits_leader(w)),"ice spokes retain advertised center shelter")
	var first: Array = g.warns.filter(func(w):return w.get("ice_wave",-1)==0)
	var second: Array = g.warns.filter(func(w):return w.get("ice_wave",-1)==1)
	for w in second:
		check(w.tell_after==first[0].dur and w.dur>w.tell_after+1.0,"second ice tell starts after first release with escape time")
		check(w.track==0.0 and w.pos==boss.pos,"radial array is fixed at boss")
	for spoke in 16:
		g.ppos=Vector2.from_angle(spoke*PI/8)*400+Vector2(0,14)
		var a: bool = first.any(func(w):return g.tele.hits_leader(w))
		var b: bool = second.any(func(w):return g.tele.hits_leader(w))
		check(a!=b,"each spoke center is safe in exactly one wave")
		check(a==(spoke%2==0),"second wave covers first safe sectors")
	_test_knight_ice_motion()

func _test_knight_ice_motion() -> void:
	var boss: Dictionary = fresh("knight_boss")
	boss.phase=2
	var script = g.bai.boss("knight_boss")
	script.force_move(boss,"长枪回旋",Vector2.RIGHT,220)
	g.bai.finals.resolve(g.warns[0])
	g.warns.clear()
	var ring: Dictionary = g.bai.finals.hazards[0]
	g.ppos=Vector2(45,0)
	check(not g.tele.hits_leader(ring),"inner safe area never becomes an unannounced hit")
	g.ppos=Vector2(250,0)
	check(not g.tele.hits_leader(ring),"ice ring does not hit outer radius immediately")
	g.invuln=100
	g.bai.finals.update(boss,.6)
	check(ring.hit and ring.inner_r>70,"expanding ring sweeps intermediate player position")
	g.ppos=Vector2(-290,0)
	check(not g.tele.hits_leader(ring),"expanding ice keeps rear escape gap")
	g.ppos=Vector2(0,0)
	check(not g.tele.hits_leader(ring),"spent inner ice stays harmless")
	boss=fresh("knight_boss")
	script.force_move(boss,"长枪连刺",Vector2.RIGHT,220)
	var promised_range: float = g.warns[0].len
	g.bai.finals.resolve(g.warns[0])
	g.warns.clear()
	var thrust: Dictionary=g.bai.finals.hazards[0]
	check(is_equal_approx(thrust.len+thrust.speed*thrust.life,promised_range),"ice thrust full travel fits warning range exactly")
	g.ppos=Vector2(250,14)
	check(thrust.len==90 and not g.tele.hits_leader(thrust),"ice thrust starts as short physical blade")
	g.bai.finals.update(boss,.3)
	check(thrust.hit and thrust.pos.x>200,"thrust travels and swept collision hits along path")
	for move in g.bai.finals.PHASE2_NAMES:
		boss=fresh("knight_boss")
		check(not script.force_move(boss,move,Vector2.RIGHT,220),"new phase two attack cannot appear in phase one")
		boss.phase=2
		check(script.force_move(boss,move,Vector2.RIGHT,220),move+" is executable in phase two")
		check(g.warns.all(func(w):return w.dur-w.track>=.4),move+" has full fixed warning")
		for w in g.warns: g.bai.finals.resolve(w)
		g.warns.clear()
		for i in 50: g.bai.finals.update(boss,.05)
		check(g.bai.finals.hazards.is_empty(),move+" has finite hazards")
	# Exercise the actual selector, rather than only forced preview dispatch.
	boss=fresh("knight_boss")
	boss.phase=2
	var seen: Array=[]
	for i in 5:
		boss.final_next=g.t
		boss.knight_combo_active=false
		g.warns.clear()
		check(g.bai.finals.try_attack(boss,Vector2.RIGHT,220),"phase two natural selector dispatches")
		seen.append(g.warns[0].name)
	check(seen.has("冰枪封径") and seen.has("冻潮夹击"),"both distinct phase two moves are in natural rotation")

	boss=fresh("knight_boss")
	script.force_move(boss,"长枪连刺",Vector2.RIGHT,220)
	g.bai.finals.resolve(g.warns[0])
	g.warns.clear()
	thrust=g.bai.finals.hazards[0]
	g.ppos=Vector2(399,14)
	g.invuln=100
	for i in 3: g.bai.finals.update(boss,.15)
	check(thrust.hit,"final partial frame sweeps telegraphed thrust endpoint")
	check(is_equal_approx(thrust.pos.x+thrust.len,400),"thrust reaches exact endpoint before expiring")
	check(g.bai.finals.hazards.is_empty(),"endpoint sweep still expires on time")

func _test_arena_ice_and_closing_walls() -> void:
	var boss: Dictionary=fresh("knight_boss")
	g.zone_frozen=true
	g.zone_next_c=Vector2(100,20)
	g.zone_next_r=700.0
	boss.pos=Vector2(-170,50)
	g.bai.finals.force_move(boss,"踏冰裂阵",Vector2.RIGHT,220)
	var w: Dictionary=g.warns[0]
	check(w.arena_radius==700.0 and w.pos==boss.pos,"ice field uses arena boundary but keeps boss origin")
	var materials=preload("res://scripts/render/final_boss_materials.gd")
	for i in 64:
		var angle: float=TAU*i/64
		var edge: Vector2=w.pos+Vector2.from_angle(angle)*materials.field_radius(w,angle)
		check(absf(edge.distance_to(g.zone_next_c)-700.0)<.01,"off-center ice reaches arena edge in every direction")
	g.ppos=Vector2(801,34)
	check(not g.tele.hits_leader(w),"ice cannot damage beyond arena boundary")
	g.zone_frozen=false
	boss=fresh("knight_boss")
	boss.phase=2
	g.bai.finals.force_move(boss,"冻潮夹击",Vector2.RIGHT,220)
	var a: Dictionary=g.warns[0]
	var b: Dictionary=g.warns[1]
	check((g.ppos-a.pos).dot(Vector2.from_angle(a.ang))+36.0+12.0 < 105.0*(a.dur+1.0),"closing wall near endpoint is reachable at seventy percent move speed")
	check(a.len==900 and a.wid==36 and a.velocity.length()==420,"closing walls are wider longer and faster")
	check((a.pos+a.velocity*a.life).distance_to(b.pos+b.velocity*b.life)<.01,"both walls meet without a permanent center gap")
	for warn in g.warns: g.bai.finals.resolve(warn)
	g.warns.clear()
	g.bai.finals.update(boss,1.0)
	check(g.bai.finals.hazards.is_empty(),"closing walls stop damaging at contact")
	var tails: Array=g.fx.filter(func(f):return f.get("retiring",false))
	check(tails.size()==2 and tails.all(func(f):return f.dmg==0.0 and f.life>0),"both walls retain harmless break animations")

	g.zone_frozen=true
	g.zone_next_c=Vector2.ZERO
	g.zone_next_r=650.0
	g.ppos=Vector2(640,0)
	boss.pos=Vector2(640,50)
	g.bai.finals.force_move(boss,"冻潮夹击",Vector2.UP,50)
	var edge_wall: Dictionary=g.warns[0]
	var escape: Vector2=g.ppos-Vector2.from_angle(edge_wall.ang)*228.0
	check(escape.distance_to(g.zone_next_c)<630.0,"wall endpoint escape turns inward near arena boundary")
	g.zone_frozen=false

func _test_ishar_pressure() -> void:
	var boss: Dictionary=fresh("ishar")
	g.bai.finals.force_move(boss,"合唱压境",Vector2.RIGHT,220)
	check(g.warns.size()==9,"single choir source launches three three-lane waves")
	for i in 3:
		check(absf(g.warns[i*3].dur-(1.35+0.8*i))<.01,"choir volleys are separated in time")
	for gates in [0,2]:
		boss=fresh("ishar")
		boss.gates_passed=gates
		g.bai.boss("ishar").force_move(boss,"大群之歌",Vector2.RIGHT,220)
		var rings: Array=g.warns.filter(func(w):return w.act=="song_ring")
		check(rings.size()==(4 if gates==2 else 3),"song gains a fourth wave in final act")
		for i in range(1,rings.size()):
			check(absf(rings[i].dur-rings[i-1].dur-1.0)<.01,"song waves retain one second travel interval")
			check(absf(angle_difference(rings[i-1].gaps[0],rings[i].gaps[0])-.28)<.01,"song gap rotates gradually")

func _finish_stake_cast(e:Dictionary) -> void:
	var script=g.bai.boss("knight_boss")
	g.warns.clear()
	e.invuln=false
	e.stun=0.0
	check(script.stake_cast_step(e,Vector2.RIGHT,true),"stake action starts")
	check(e.has("stake_cast") and e.stakes.is_empty(),"windup does not spawn pillars")
	g.t+=1.1
	g.tele.update_warns(1.1)
	script.stake_cast_step(e,Vector2.RIGHT,false)
	if e.stake_cast.throw:
		check(e.stakes.is_empty(),"flying spear does not spawn pillars early")
		g.t+=.6
		script.stake_cast_step(e,Vector2.RIGHT,false)
	check(e.stakes.size()==5 and e.stakes.all(func(s):return s.born>g.t),"landing starts five pillar warnings")
	g.t+=1.3
	g.tele.update_warns(1.3)
	script.stake_cast_step(e,Vector2.RIGHT,false)
	check(not e.has("stake_cast"),"planting releases boss after rise")

func _test_stake_cast_interruptions() -> void:
	var script=g.bai.boss("knight_boss")
	for phase in [1]:
		var e:Dictionary=fresh("knight_boss")
		e.phase=phase
		script._knight_stakes(e,.01)
		e.stakes_seeded=true
		script.stake_cast_step(e,Vector2.RIGHT,true)
		e.stake_cast.warning.t=.8
		check(g.world.knight_animation(e).frame==1,"refill holds windup until actual release")
		g.t+=1.1
		g.tele.update_warns(1.1)
		script.stake_cast_step(e,Vector2.RIGHT,false)
		check(g.world.knight_animation(e).frame==2,"refill spear flight aligns with release frame")
		check(e.stake_cast.stage=="flight","phase one releases refill spear")
		e.break_t=1.0
		script.stake_cast_step(e,Vector2.RIGHT,false)
		check(not e.has("stake_cast") and e.stakes.is_empty(),"poise break cancels flight before spawning")
	var e:Dictionary=fresh("knight_boss")
	e.stakes=[{"pos":e.pos,"born":0.0,"until":INF}]
	e.kb_self=true
	e.kb=Vector2(500,0)
	e.final_next=0.0
	g.bai.boss_step(e,.01,Vector2.RIGHT,220)
	check(e.break_t>0.0 and not g.warns.any(func(w):return w.dmg>0.0),"collision cannot dispatch an attack using stale ready state")

	var old_warn:float=g.dmod.boss_warn
	g.dmod.boss_warn=1.5
	e=fresh("knight_boss")
	e.stakes=[]
	script._place_stakes(e,5)
	check(e.stakes.all(func(st):return absf(st.born-g.t-1.5)<.01),"pillar collision waits for difficulty-adjusted warning")
	g.dmod.boss_warn=old_warn

	# Phase two removes remaining stakes and cannot reserve or directly spawn a batch.
	e=fresh("knight_boss")
	e.stakes=[{"pos":e.pos+Vector2(100,0),"born":0.0,"until":INF}]
	script.on_lethal(e)
	check(e.phase==2 and e.stakes.is_empty(),"rebirth clears remaining stakes")
	e.invuln=false
	e.stun=0.0
	e.wind=0.0
	e.stakes_empty_at=0.0
	for tick in 3:
		g.t+=10.0
		script._knight_stakes(e,.1)
		check(not script.stake_cast_step(e,Vector2.RIGHT,true),"phase two never reserves planting action")
		script._place_stakes(e,5)
		check(e.stakes.is_empty() and not e.has("stake_cast"),"phase two never regenerates stakes")
	e=fresh("knight_boss")
	script._knight_stakes(e,.1)
	script.stake_cast_step(e,Vector2.RIGHT,true)
	script.setup_preview_phase2(e)
	check(e.stakes.is_empty() and not e.has("stake_cast"),"preview phase switch cancels pending planting")
