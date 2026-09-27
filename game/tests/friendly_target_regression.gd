extends Node
const Character = preload("res://scripts/characters/character.gd")
var game: Node
var frames := 0
var fails := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		fails += 1
		push_error(label)
func _ready() -> void:
	game = load("res://game.tscn").instantiate()
	add_child(game)
func check_husk_healing(ally: Dictionary, hostile: Dictionary) -> void:
	var saved_enemies: Array = game.enemies.duplicate()
	var old_self_hp: float = ally.hp
	var old_hostile_hp: float = hostile.hp
	var old_hostile_max: float = hostile.maxhp
	ally.hp -= 10.0
	var valid: Array = [hostile]
	for i in 3:
		valid.append(game.spawner.spawn_enemy("bone", ally.pos + Vector2(200 + i * 20, 0)))
	for i in valid.size():
		valid[i].hp = 100.0 + i * 100.0
		valid[i].maxhp = 1000.0
	var valid_hp: Array = valid.map(func(e): return e.hp)
	# Closer invalid recipients must neither receive healing nor consume the three slots.
	var rejected: Array = []
	for type in ["tear", "bone", "bone", "carmen", "bone", "bone"]:
		var e: Dictionary = game.spawner.spawn_enemy(type, ally.pos + Vector2(60, rejected.size() * 4))
		e.hp = 100.0
		e.maxhp = 1000.0
		rejected.append(e)
	rejected[1].dead = true
	rejected[2].friendly = true
	rejected[4].pos = ally.pos + Vector2(600, 0)
	rejected[5].hp = rejected[5].maxhp
	game.spawner.spawn_chest(ally.pos + Vector2(50, 0))
	var chest: Dictionary = game.enemies[-1]
	chest.hp = 10.0
	rejected.append(chest)
	var rejected_hp: Array = rejected.map(func(e): return e.hp)
	ally.ally_attack_cd = 0.0
	game.combat.hit("援护")
	var previous_hit: Dictionary = game.hit
	game.ishar.step_ally(ally, 0.01)
	var healed := 0
	for i in valid.size():
		var e: Dictionary = valid[i]
		if e.hp > valid_hp[i]:
			healed += 1
			check(is_equal_approx(e.hp, minf(e.maxhp, valid_hp[i] + ally.dmg)), "husk heal amount equals Ishar attack stat")
	check(healed == 3 and valid[3].hp == valid_hp[3], "one first-phase action heals the three lowest-health-ratio husks")
	for i in rejected.size():
		check(rejected[i].hp == rejected_hp[i], "first phase ignores tear/dead/friendly/boss/distant/full/chest recipient " + str(i))
	check(ally.hp == old_self_hp - 10.0, "first phase cannot heal itself")
	check(game.hp == game.max_hp and game.hit == previous_hit, "husk healing neither hurts leader nor changes player damage source")
	# Only one wounded recipient remains: healing must clamp to its actual maximum.
	for e in valid:
		e.hp = e.maxhp
	valid[0].hp -= 1.0
	ally.ally_attack_cd = 0.0
	game.ishar.step_ally(ally, 0.01)
	check(valid[0].hp == valid[0].maxhp, "husk healing never exceeds maximum HP")
	game.enemies = saved_enemies
	ally.hp = old_self_hp
	hostile.hp = old_hostile_hp
	hostile.maxhp = old_hostile_max

func _process(_dt: float) -> void:
	frames += 1
	if frames != 5:
		return
	game.set_process(false)
	game.enemies.clear()
	game.ppos = Vector2.ZERO
	var ally: Dictionary = game.spawner.spawn_enemy("ishar", Vector2(12, 0))
	check(ally.get("friendly", false) and ally.invuln, "Ishar phase one spawns friendly and protected")
	# A stale grid must also exclude a unit whose allegiance changed this frame.
	ally["friendly"] = false
	game.enemies_sys.build_grid()
	ally.friendly = true
	check(game.enemies_sys.query(Vector2.ZERO, 300.0).is_empty(), "stale grid cannot return a new ally")
	var hostile: Dictionary = game.spawner.spawn_enemy("bone", Vector2(90, 0))
	hostile.hp = 100000.0
	hostile.maxhp = hostile.hp
	game.enemies_sys.build_grid()
	check(game.enemies_sys.query(Vector2.ZERO, 300.0).size() == 1, "fresh grid indexes enemies only")
	check(game.enemies_sys.densest_point(300.0) == hostile.pos, "ally does not attract density targeting")
	for cid in Character.list_ids():
		var op = Character.create(game, cid)
		op.pos = Vector2.ZERO
		var near: Array = op.nearest_enemies(1, 300.0)
		check(near.size() == 1 and is_same(near[0], hostile), cid + " chooses hostile over closer ally")
		check(op.query_ids(Vector2.ZERO, 300.0).size() == 1, cid + " area query excludes ally")
		var arc: Array = op.arc_targets(Vector2.ZERO, 0.0, PI, 300.0)
		check(arc.size() == 1 and is_same(arc[0], hostile), cid + " attack arc excludes ally")
		if cid == "wisadel":
			check(is_same(op._execute_target(300.0), hostile), "Wisadel elite priority cannot consume a shot on ally")
		if cid == "kaltsit":
			game.stats.define_all(op.stat_defs())
			op.update(0.01)
			check(is_same(op.m.tgt, hostile), "Mon3tr autonomous targeting excludes ally")
		if cid == "mizuki":
			op.mirror_pos = Vector2.ZERO
			ally.pos = Vector2(-12, 0)
			op._run_delayed({"kind": "echo", "ang": 0.0, "radius": 120.0, "half": 0.5, "dirs": 1, "dmg": 1.0})
			check(op.mirror_face == 1.0, "Mizuki mirror aims at enemy instead of nearer ally")
			ally.pos = Vector2(12, 0)
	# Friendly immunity must not depend on the ordinary invulnerability flag.
	ally.invuln = false
	var hp: float = ally.hp
	game.combat.hit("真实")
	game.combat.damage(ally, hp * 2.0)
	check(ally.hp == hp and not ally.dead and ally.hits == 0, "friendly direct damage has no side effects")
	var bullet := {"kind": "arcane", "pos": ally.pos, "vel": Vector2(120, 0), "life": 1.0, "dmg": 10.0, "r": 4.0, "home": ally}
	game.bullets = [bullet]
	game.weapons_sys.update_bullets(0.01)
	check(bullet.life > 0.0 and not bullet.get("hit", {}).has(ally.id), "stray projectile passes through ally without consuming hit")
	check(is_same(bullet.home, hostile), "homing projectile retargets a hostile")
	game.weapons_sys.bullet_hit(bullet, ally)
	check(bullet.life > 0.0 and ally.slow <= 0.0, "direct bullet callback cannot consume hit or apply slow to ally")
	var hostile_hp: float = hostile.hp
	bullet.pos = hostile.pos
	game.weapons_sys.update_bullets(0.001)
	check(hostile.hp < hostile_hp and bullet.life <= 0.0, "same projectile still damages and expires on hostile")
	# Friendly enemy-array entities delegate to the encounter, not contact/ranged AI.
	ally.invuln = true
	ally.pos = game.ppos
	ally.age = 3.0
	game.hp = game.max_hp
	game.invuln = 0.0
	game.ebullets.clear()
	hostile.pos = Vector2(180, 0)
	game.enemies_sys.update(0.01)
	check(game.hp == game.max_hp and game.ebullets.is_empty(), "friendly update skips hostile contact and shooting")
	check_husk_healing(ally, hostile)
	var tear: Dictionary = game.ishar.spawn_tear(ally)
	tear.pos = game.ppos
	game.enemies_sys.update(0.01)
	check(tear.get("friendly", false) and tear.blocked and not tear.dead, "neutral tear dispatches to blocked-charge behavior")
	check(game.hp == game.max_hp, "standing on friendly tear causes no hostile tear damage")
	# Pressing a tear removes only its bonus; baseline charging always continues.
	ally.ally_attack_cd = 100.0
	ally.ally_tear_cd = 100.0
	ally.ally_charge = 0.0
	game.ishar.step_ally(ally, 2.0)
	var pressed_gain: float = ally.ally_charge
	tear.pos = game.ppos + Vector2(100, 0)
	ally.ally_charge = 0.0
	game.ishar.step_ally(ally, 2.0)
	check(is_equal_approx(pressed_gain, 2.0) and is_equal_approx(ally.ally_charge - pressed_gain, 0.35 * 2.0), "pressing one tear removes exactly its 0.35-per-second bonus")
	tear.dead = true
	# An actual map collision fixture pushes outward beyond the visible circle margin.
	var old_big: Dictionary = game.map.theme.big_props
	var old_cache: Dictionary = game.map.big_cache
	game.map.theme.big_props = {"list": ["prop_wall"], "cell": 560.0}
	game.map.big_cache = {}
	for x in range(-1, 2):
		for y in range(-1, 2):
			game.map.big_cache[Vector2i(x, y)] = []
	game.map.big_cache[Vector2i.ZERO] = ["prop_wall", Vector2(280, 12), 0, 60.0, 20.0]
	game.zone_state = 2
	game.zone_c = Vector2.ZERO
	game.zone_r = 400.0
	game.zone_frozen = true
	game.zone_next_c = Vector2.ZERO
	game.zone_next_r = 500.0
	game.ppos = Vector2(480, 45)
	ally.pos = Vector2(289, 0)
	check(game.map.push_out(ally.pos, ally.r).length() > 290.0, "obstacle fixture really pushes beyond current safety margin")
	game.ishar.step_ally(ally, 0.1)
	check(ally.pos.distance_to(game.zone_c) <= game.zone_r - 110.0 + 0.01, "friendly final position stays safe after obstacle push")
	# Already at its follow point: a newly shrunken circle must still clamp an idle P1.
	game.ppos = ally.pos + Vector2(110, 45)
	game.zone_r = 250.0
	check(ally.pos.distance_to(game.zone_c) > game.zone_r, "idle shrink fixture starts outside the new visible circle")
	game.ishar.step_ally(ally, 0.01)
	check(ally.pos.distance_to(game.zone_c) <= game.zone_r - 110.0 + 0.01, "idle first phase is clamped even when no follow movement is needed")
	game.map.theme.big_props = old_big
	game.map.big_cache = old_cache
	game.zone_state = 0
	game.zone_frozen = false
	game.ppos = Vector2.ZERO
	# No tears: 29 seconds remains friendly, the 30th second must start transformation.
	ally.ally_charge = 0.0
	ally.ally_tear_cd = 100.0
	for second in 29:
		game.t += 1.0
		game.ishar.step_ally(ally, 1.0)
	check(ally.phase == 1 and is_equal_approx(ally.ally_charge, 29.0), "no-tear natural charge keeps the first 29 seconds friendly")
	game.t += 1.0
	game.ishar.step_ally(ally, 1.0)
	check(ally.phase == 2 and not ally.friendly and not ally.invuln, "natural 30 charge always transitions without tears")
	check(is_equal_approx(ally.transform_until - game.t, 0.9), "real transformation starts a 0.9-second protection window")
	game.enemies_sys.build_grid()
	var next: Array = game.enemies_sys.nearest(1, 300.0)
	check(next.size() == 1 and is_same(next[0], ally), "transformed hostile is targetable again")
	game.combat.damage(ally, 10.0)
	check(ally.hp == hp, "transformation begins damage-protected")
	game.t += 0.89
	game.combat.damage(ally, 10.0)
	check(ally.hp == hp, "transformation remains protected before 0.9 seconds")
	game.t += 0.02
	game.combat.damage(ally, 10.0)
	check(ally.hp < hp and not ally.invuln, "transformed hostile is damageable after protection expires")
	print("FRIENDLY TARGET REGRESSION: ", fails, " failures; operators=", Character.list_ids().size())
	game.queue_free()
	game = null
	Sfx.set_process(false)
	await get_tree().create_timer(0.25, true, false, true).timeout
	for player in Sfx.get_children():
		if player is AudioStreamPlayer:
			player.stop()
			player.stream = null
			player.queue_free()
	await get_tree().create_timer(0.2, true, false, true).timeout
	get_tree().quit(fails)
