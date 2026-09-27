extends Node
var g
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAIL ", label)
func enemy(kind: String) -> Dictionary:
	var e: Dictionary = g.spawner.new_enemy(kind, Vector2.ZERO)
	e.age = 10.0
	return e
func _ready() -> void:
	g = load("res://game.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	g.zone_frozen = false
	g.t = 100.0
	var e := enemy("path")
	g.bai._cd(e, "test", 10.0)
	check(is_equal_approx(e.cds.test - g.t, 7.0), "boss cooldown reduced 30 percent")
	for entry in [["knight_boss", 145.0], ["archon", 165.0]]:
		e = enemy(entry[0])
		g.ppos = Vector2(entry[1], 0)
		e.cds = {"frost": g.t + 100.0}
		g.warns.clear()
		g.bai._boss_ai(e, 0.01, Vector2.RIGHT, entry[1])
		check(g.warns.size() > 0, entry[0] + " intermediate distance attacks")
		for w in g.warns:
			check(w.dur >= 0.6 and w.dur - w.track >= 0.399, "readable warning preserved")
	e.erase("leap")
	e = enemy("knight_boss")
	e.dash2 = true
	g.warns.clear()
	g.bai._boss_ai(e, 0.01, Vector2.RIGHT, 300.0)
	check(g.warns.size() == 1, "second charge cannot overlap another move")
	g.ppos = Vector2(0, 500)
	g.fx.clear()
	var w: Dictionary = g.bai._warn(e, "cone", 0.6, {"act": "bite", "ang": 0.0, "half": 0.8, "r": 125.0})
	g.bai._warn_resolve(w)
	var slashes: Array = g.fx.filter(func(f): return f.get("kind", "") == "bslash")
	check(not slashes.is_empty(), "resolved attack has slash feedback")
	var slash: Dictionary = slashes[0] if not slashes.is_empty() else {"ang": INF, "r": 0.0}
	check(is_equal_approx(slash.ang, 0.0), "resolved slash stays at locked direction")
	check(is_equal_approx(slash.r, 125.0), "resolved slash stays in warned radius")
	check(e.pose > 0.0 and is_equal_approx(e.pose, e.pose_max), "release restarts visible attack pose")
	print("BOSS PRESSURE failures=", failures)
	g.warns.clear()
	w.clear()
	e.clear()
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
