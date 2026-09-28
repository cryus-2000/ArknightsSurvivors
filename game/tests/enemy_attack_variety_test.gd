extends Node
## Real warning/resolve regression for data-driven ordinary and elite secondary attacks.
const D = preload("res://scripts/data.gd")
var g: Node
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func _ready() -> void:
	g = load("res://game.tscn").instantiate()
	g.demo_op = "mizuki"
	add_child(g)
	call_deferred("run_checks")
func run_checks() -> void:
	g.set_process(false)
	g.t = 100.0
	for kind in ["stone", "offspring", "spitter", "floater", "reaper", "founder", "tracer", "nest", "pocket", "skimmer", "mother", "mimic", "knight"]:
		var d: Dictionary = D.ENEMIES[kind]
		check(d.has("extra"), kind + " has secondary attack data")
		if not d.has("extra"):
			continue
		var e: Dictionary = g.spawner.new_enemy(kind, Vector2.ZERO)
		e.age = 5.0
		e.dormant = false
		e.wake_t = 0.0
		e.extra_next = 0.0
		g.warns.clear()
		g.ebullets.clear()
		g.ppos = Vector2(minf(float(d.extra.range) - 10.0, 140.0), 0.0)
		g.eai.pattern(e, Vector2.RIGHT, g.ppos.x, 0.01, e.spd)
		var warnings: Array = g.warns.filter(func(w): return w.get("secondary", false))
		check(warnings.size() == 1, kind + " creates one secondary warning")
		if warnings.is_empty():
			continue
		var w: Dictionary = warnings[0]
		check(w.owner == e and w.dur >= 0.6 and w.cancel_dead, kind + " readable cancellable warning")
		check(e.extra_next > g.t, kind + " cooldown advances")
		var count: int = g.warns.size()
		g.eai.pattern(e, Vector2.RIGHT, g.ppos.x, 0.01, e.spd)
		check(g.warns.size() == count, kind + " no immediate repeat")
		if str(d.extra.mode) == "volley":
			g.bai._warn_resolve(w)
			check(g.ebullets.size() == int(d.extra.count), kind + " volley emits configured bullets")
			if not g.ebullets.is_empty():
				check(is_equal_approx(float(g.ebullets[0].get("corrode", -1.0)), e.corrode), kind + " inherits corrosion")
		g.warns.clear()
		g.ebullets.clear()
	# Large packs must not fill the arena with simultaneous secondary warnings.
	var crowded: Dictionary = g.spawner.new_enemy("stone", Vector2.ZERO)
	crowded.age = 5.0
	crowded.extra_next = 0.0
	g.ppos = Vector2(140, 0)
	g.warns.clear()
	for i in 12:
		g.warns.append({"secondary": true})
	g.eai.pattern(crowded, Vector2.RIGHT, 140.0, 0.01, crowded.spd)
	check(g.warns.size() == 12 and crowded.extra_next == 0.0, "crowded secondary warnings wait without spending cooldown")
	g.warns.clear()
	# The third move must be reachable through the actual boss scheduler.
	for kind in ["path", "izumik", "iberia", "carmen", "bishop", "archon", "immortal", "paranoia", "ishar", "knight_boss"]:
		var d: Dictionary = D.ENEMIES[kind]
		check(d.patterns.size() >= 3, kind + " has a third boss move")
		if d.patterns.size() < 3:
			continue
		var e: Dictionary = g.spawner.new_enemy(kind, Vector2.ZERO)
		e.age = 5.0
		if kind in ["ishar", "izumik"]:
			g.bai.setup_preview_phase2(e)
		g.warns.clear()
		g.ppos = Vector2(280, 0)
		e.pattern_cycle = 2
		e.pattern_next = g.t
		check(g.bai.patterns.try_attack(e, Vector2.RIGHT, 280.0), kind + " schedules new move")
		check(g.warns.any(func(w): return w.get("pattern_id", "") == kind + ":2"), kind + " third warning visible")
		if str(d.patterns[2].mode) == "line" and not g.warns.is_empty():
			var line_warning: Dictionary = g.warns[0]
			check(line_warning.shape == "line" and g.warns[0].dur >= 0.6, kind + " line warning readable")
			g.invuln = 0.0
			g.shield = 0
			g.hp = g.max_hp
			g.demo_op = ""
			g.combat.boss_log.clear()
			g.combat.loss_log.clear()
			g.combat.any_log.clear()
			g.ppos = line_warning.pos + Vector2.from_angle(line_warning.ang) * 150.0 + Vector2(0, 14)
			g.bai._warn_resolve(g.warns[0])
			check(g.hp < g.max_hp, kind + " line move can hit")
		g.warns.clear()
	# Queued attacks must vanish with their owner, even for circle warnings.
	var fallen: Dictionary = g.spawner.new_enemy("pocket", Vector2.ZERO)
	fallen.age = 5.0
	fallen.extra_next = 0.0
	g.ppos = Vector2(70, 0)
	g.eai.pattern(fallen, Vector2.RIGHT, 70.0, 0.01, fallen.spd)
	var hp_before: float = g.hp
	fallen.dead = true
	g.bai._update_warns(2.0)
	check(is_equal_approx(g.hp, hp_before) and g.ebullets.is_empty(), "dead secondary owner cannot deal damage")
	print("ENEMY ATTACK VARIETY failures=", failures)
	g.warns.clear()
	g.enemies.clear()
	g.bosses.clear()
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

