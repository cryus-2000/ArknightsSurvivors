extends Node
## Shared hit-feedback regression. Run through tools/godot_runner.py, with --feedback-test.
var g: Node
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)

func _ready() -> void:
	g = load("res://game.tscn").instantiate()
	add_child(g)
	g.set_process(false)
	g.t = 10.0
	g.hitstop = 0.0
	g.vfx.impact_pause(2.0)
	check(is_equal_approx(g.hitstop, 0.075), "heavy pause capped")
	g.hitstop = 0.0
	g.t += 0.1
	for i in 100:
		g.vfx.impact_pause(0.075)
	check(g.hitstop == 0.0, "crowd cannot retrigger pause during cooldown")
	g.t += 0.3
	g.vfx.impact_pause(0.018)
	g.vfx.impact_pause(0.07)
	check(is_equal_approx(g.hitstop, 0.07), "same-frame heavy hit upgrades but never adds")
	var state_before: int = g.rng.state
	var e := {"pos": g.ppos + Vector2(30, 0), "r": 12.0}
	for oid in ["mizuki", "skadi", "siege", "saria", "suzuran", "eyjafjalla", "kaltsit", "wisadel", "irene", "logos", "lumen", "specter_unchained", "ulpianus"]:
		g.t += 1.0
		g.fx.clear()
		g.hitstop = 0.0
		g.vfx.contact(oid, e, g.ppos)
		check(g.fx.size() >= 2, oid + " contact visible")
		var count: int = g.fx.size()
		for i in 30:
			g.vfx.contact(oid, e, g.ppos)
		check(g.fx.size() == count, oid + " crowd particle throttle")
		if oid in ["suzuran", "eyjafjalla", "logos", "lumen"]:
			check(g.hitstop == 0.0, oid + " ranged contact does not freeze control")
	g.t += 1.0
	g.hitstop = 0.0
	g.vfx.contact("specter_unchained", e, g.ppos, "替身")
	check(g.hitstop == 0.0, "doll damage never freezes control")
	g.vfx.ground_dust(g.ppos)
	check(g.rng.state == state_before, "feedback does not consume gameplay RNG")
	print("FEEDBACK TESTS PASSED" if failures == 0 else "FEEDBACK TESTS FAILED: %d" % failures)
	g.queue_free()
	g = null
	# Muting does not release mixer-owned playbacks. Let queued starts settle,
	# then destroy the players and allow the audio thread to retire its refs.
	Sfx.set_process(false)
	await get_tree().create_timer(0.25, true, false, true).timeout
	for player in Sfx.get_children():
		if player is AudioStreamPlayer:
			player.stop()
			player.stream = null
			player.queue_free()
	await get_tree().create_timer(0.2, true, false, true).timeout
	get_tree().quit(0 if failures == 0 else 1)
