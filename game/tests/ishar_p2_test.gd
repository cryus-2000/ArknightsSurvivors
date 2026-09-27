extends Node
## P2 is a readable deterministic rotation; P1 belongs to IsharEncounter.
var g
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAIL ", label)
func _ready() -> void:
	g = load("res://game.tscn").instantiate()
	g.demo_op = "mizuki"
	g.demo_enemy = "ishar"
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	g.t = 100.0
	g.zone_frozen = false
	g.enemies.clear()
	g.warns.clear()
	g.ebullets.clear()
	var e: Dictionary = g.spawner.new_enemy("ishar", Vector2.ZERO)
	e.age = 10.0
	e.friendly = true
	e.invuln = true
	g.enemies.append(e)
	g.bosses = [e]
	g.ppos = Vector2(350, 0)
	g.bai._boss_ai(e, 0.01, Vector2.RIGHT, 350.0)
	check(g.warns.is_empty() and g.ebullets.is_empty(), "P1 boss AI never attacks player")
	var own: Dictionary = g.spawner.new_enemy("tear", Vector2(80, 0))
	own.owner = e
	var other: Dictionary = g.spawner.new_enemy("tear", Vector2(100, 0))
	other.owner = {"id": -1}
	g.enemies.append_array([own, other])
	g.bai.transform_ishar(e)
	check(not e.friendly and not e.invuln and e.phase == 2, "transformation changes allegiance")
	check(own.dead and not other.dead, "transformation removes only own tears")
	check(e.ai == "melee", "P2 uses deliberate attack scheduler, no generic ranged insertion")
	g.warns.clear()
	g.bai._boss_ai(e, 0.1, Vector2.RIGHT, 350.0)
	check(g.warns.is_empty(), "no attack during transformation")
	for distance in [350.0, 120.0]:
		g.t += 20.0
		e.wind = 0.0
		e.cds = {}
		e.ishar_cycle = 0
		e.ishar_next_at = g.t
		g.ppos = Vector2(distance, 0)
		g.warns.clear()
		var seen: Dictionary = {}
		var names: Array = []
		for i in 1500:
			g.t += 0.04
			e.wind = maxf(0.0, e.wind - 0.04)
			g.bai._boss_ai(e, 0.04, Vector2.RIGHT, distance)
			for w in g.warns:
				seen[w.act] = true
				if w.t == 0.0:
					check(w.dur >= 0.6 and w.dur - w.track >= 0.399, "full warning and target lock")
					if w.name != "" and not w.has("pattern_id"):
						names.append(w.name)
			g.invuln = 100.0
			g.bai._update_warns(0.04)
		check(seen.has("ishar_strike") and seen.has("ishar_line") and seen.has("ishar_volley"), "three distinct ranged patterns at distance %d" % distance)
		check(seen.has("bite") or seen.has("sweep"), "near bite or far fan in rotation")
		check(names.size() >= 8 and names[0] == names[4], "complete rotation repeats rather than priority starving")
	# Warning resolution must forward true damage and the existing protection budget.
	g.t += 20.0
	g.invuln = 0.0
	g.hp = g.max_hp
	g.armor = 9999.0
	g.arts_res = 0.7
	g.shield = 0
	g.lamp = 100.0
	g.ppos = Vector2.ZERO
	var w: Dictionary = g.bai._warn(e, "circle", 0.9, {"pos": Vector2.ZERO, "act": "ishar_strike", "true": true, "dmg": 10.0, "r": 60.0})
	var before: float = g.hp
	g.bai._warn_damage(w)
	check(g.in_type[1] == "真实" and before - g.hp > 8.0, "true strike ignores armor and arts resistance")
	g.t += 20.0
	g.invuln = 0.0
	g.hp = g.max_hp
	w.dmg = g.max_hp * 100.0
	g.bai._warn_damage(w)
	check(g.hp >= g.max_hp * 0.599, "true strike retains 40 percent boss hit cap")
	# A fixed-target warning cannot continue following the player after lock.
	g.warns.clear()
	g.ppos = Vector2(350, 0)
	e.wind = 0.0
	e.ishar_cycle = 0
	e.ishar_next_at = g.t
	g.bai._boss_ai(e, 0.01, Vector2.RIGHT, 350.0)
	if not g.warns.is_empty():
		var locked: Vector2 = g.warns[0].pos
		g.ppos = Vector2(-350, 0)
		g.bai._update_warns(0.3)
		check(g.warns[0].pos == locked, "ground strike location stays locked")
	e.dead = true
	g.bai._update_warns(4.0)
	check(not g.warns.any(func(a): return not a.done), "boss death cancels queued attacks")
	# The legacy developer switch must use the same complete phase setup as trial/gallery.
	if Cfg.dev_args().has("--bosstest=ishar2"):
		g.enemies.clear()
		g.bosses.clear()
		g.state = g.S.PLAY
		g.at_frames = 19
		g.autotest_sys.step()
		var bosses: Array = g.enemies.filter(func(b): return b.type == "ishar")
		check(bosses.size() == 1, "legacy boss test creates one requested Ishar")
		if bosses.size() == 1:
			var fixture: Dictionary = bosses[0]
			check(fixture.phase == 2 and not fixture.friendly and not fixture.invuln and fixture.ai == "melee", "legacy ishar2 test starts fully hostile phase two")
			check(fixture.has("transform_until"), "legacy ishar2 test preserves transformation frames")
	# Rendering uses the mechanic's actual suppression radius and only a live owner.
	check(g.world.has_method("tear_zone_info"), "tear display exposes neutral suppression state")
	if g.world.has_method("tear_zone_info"):
		var source: Dictionary = g.spawner.new_enemy("ishar", Vector2(100, 0))
		var drop: Dictionary = g.spawner.new_enemy("tear", Vector2.ZERO)
		drop.friendly = true
		drop.owner = source
		g.ppos = Vector2(100, 0)
		var visual: Dictionary = g.world.tear_zone_info(drop)
		check(not visual.blocked and is_same(visual.owner, source) and visual.col.b > visual.col.r, "neutral tear shows approach cue and only its owner")
		g.ppos = Vector2.ZERO
		visual = g.world.tear_zone_info(drop)
		check(visual.blocked and visual.col.g > visual.col.r and visual.label == "充能已压制", "standing on tear switches to suppressed teal status")
		check(is_equal_approx(visual.r, 32.0) and is_equal_approx(visual.ground_scale, 1.0), "suppression ring matches circular gameplay radius")
		source.phase = 2
		check(g.world.tear_zone_info(drop).owner.is_empty(), "transformed owner receives no charge link")
		source.phase = 1
		source.dead = true
		check(g.world.tear_zone_info(drop).owner.is_empty(), "dead owner receives no charge link")
		drop.erase("owner")
		check(g.world.tear_zone_info(drop).owner.is_empty(), "orphan tear never links to unrelated boss")
		drop.friendly = false
		visual = g.world.tear_zone_info(drop)
		check(visual.col.r > visual.col.g and visual.label == "" and is_equal_approx(visual.r, drop.r + 14.0), "hostile tear retains existing damage warning")
	print("ISHAR P2 failures=", failures)
	g.warns.clear()
	g.enemies.clear()
	g.bosses.clear()
	e.erase("owner")
	own.erase("owner")
	other.erase("owner")
	g.queue_free()
	g = null
	Sfx.set_process(false)
	await get_tree().create_timer(0.25, true, false, true).timeout
	for player in Sfx.get_children():
		if player is AudioStreamPlayer:
			player.stop()
			player.stream = null
			player.queue_free()
	await get_tree().create_timer(0.2, true, false, true).timeout
	get_tree().quit(0 if failures == 0 else 1)
