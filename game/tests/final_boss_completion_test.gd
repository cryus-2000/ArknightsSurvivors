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
		for move in g.bai.finals.NAMES[kind]:
			check(seen.has(move), kind + " natural extra " + move)
		check(seen.size() >= 7, kind + " natural seven distinct attacks")
	_test_fixes()
	_test_bubble_tracking()
	_test_knight_arc()
	_test_ice_field()
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
	check(is_equal_approx(p.hp / p.maxhp, 0.8), "paranoia revive 80 percent")
	var knight: Dictionary = fresh("knight_boss")
	var script = g.bai.boss("knight_boss")
	script._knight_stakes(knight, 0.1)
	check(knight.stakes.size() == 5, "initial five pillars")
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
	check(knight.stakes.size() == 5, "exhausted batch replenishes together")
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
	check(image.get_pixel(20,20).a<0.1,"bubble center transmits the background")
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
	check(is_equal_approx(h.pos.x,92.0),"accelerated travel integrates elapsed time exactly")
	check(h.pos.y==0.0,"slash does not travel sideways")
	var test_h: Dictionary = h.duplicate()
	check(g.bai.finals._accelerated_distance(test_h,2.0)>g.bai.finals._accelerated_distance(test_h,1.0),"capped speed continues moving")

func _test_ice_field() -> void:
	var boss: Dictionary = fresh("knight_boss")
	g.ppos=Vector2.ZERO
	g.bai.finals.force_move(boss,"踏冰裂阵",Vector2.RIGHT,200)
	check(g.warns.size()==6,"ice array is two waves of three broad lanes")
	var first: Array = g.warns.filter(func(w):return w.get("ice_wave",-1)==0)
	var second: Array = g.warns.filter(func(w):return w.get("ice_wave",-1)==1)
	for w in second:
		check(w.tell_after==first[0].dur and w.dur>w.tell_after+1.0,"second ice tell starts after first release with escape time")
		check(w.track==0.0,"complementary ice lanes never retarget")
	for lane in 6:
		g.ppos=Vector2(0,375-lane*150)+Vector2(0,14)
		var a: bool = first.any(func(w):return g.tele.hits_leader(w))
		var b: bool = second.any(func(w):return g.tele.hits_leader(w))
		check(a!=b,"every lane center is safe in exactly one wave")
		check(a==(lane%2==0),"second wave covers first safe lanes")
