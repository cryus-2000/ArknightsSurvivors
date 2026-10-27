extends Node
## Shared beam salvos keep one warning and one impact voice, independently.
var failures := 0


func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		print("FAIL: " + label)


func voices(name: String) -> int:
	return Sfx.players.filter(func(p): return p.playing and p.get_meta("sname", "") == name).size()


func _ready() -> void:
	run.call_deferred()


func run() -> void:
	AudioServer.set_bus_mute(0, true)
	await get_tree().process_frame
	await get_tree().process_frame
	for p in Sfx.players:
		p.stop()
	Sfx.last.clear()
	Sfx.trace_on = true
	Sfx.trace.clear()
	Sfx.play_cue("beam", "paranoia", "start")
	await get_tree().create_timer(0.08).timeout
	Sfx.play_cue("光束", "ishar", "start")
	check(voices("cue_beam_start") == 1, "salvo warning does not stack")
	Sfx.play_cue("beam", "paranoia", "hit")
	await get_tree().create_timer(0.08).timeout
	Sfx.play_cue("beam", "ishar", "hit")
	check(voices("cue_beam_hit") == 1, "salvo impact does not stack")
	check(Sfx.trace.filter(func(row): return row[1] == "cue_beam_start").size() == 2, "each warning round starts even during the previous tail")
	check(Sfx.trace.filter(func(row): return row[1] == "cue_beam_hit").size() == 2, "each firing round starts even during the previous tail")
	Sfx.play_cue("beam", "ishar", "hit")
	check(Sfx.trace.filter(func(row): return row[1] == "cue_beam_hit").size() == 2, "simultaneous beams merge within one round")
	check(voices("cue_beam_start") == 1, "impact does not cut warning")
	check(Sfx.sfx_prio("cue_beam_start") == 5 and Sfx.sfx_prio("cue_beam_hit") == 5, "beam cues retain Boss priority")
	await get_tree().create_timer(1.0).timeout
	Sfx.play_cue("beam", "paranoia", "start")
	Sfx.play_cue("beam", "paranoia", "hit")
	check(voices("cue_beam_start") == 1 and voices("cue_beam_hit") == 1, "next attack remains audible")
	var g = load("res://game.tscn").instantiate()
	add_child(g)
	g.set_process(false)
	var boss: Dictionary = g.spawner.new_enemy("paranoia", Vector2.ZERO)
	Sfx.trace.clear()
	for round_i in 3:
		await get_tree().create_timer(0.08).timeout
		for beam_i in 3:
			var w: Dictionary = g.tele.warn(boss, "line", 0.8, {"act": "beam", "name": "凝视" if round_i == 0 and beam_i == 0 else "", "dmg": 0.0})
			g.tele._resolve(w)
	check(Sfx.trace.filter(func(row): return row[1] == "cue_beam_hit").size() == 3, "three firing rounds produce three cues including unnamed follow-ups")
	await check_final_rounds(g, "ishar", "合唱齐射", 3)
	Sfx.trace_on = false
	g.queue_free()
	for p in Sfx.find_children("*", "AudioStreamPlayer", true, false):
		p.stop()
	await get_tree().create_timer(0.1).timeout
	print("BEAM AUDIO: %d failures" % failures)
	get_tree().quit(1 if failures else 0)


func check_final_rounds(g, kind: String, move: String, expected: int) -> void:
	g.warns.clear()
	var boss: Dictionary = g.spawner.new_enemy(kind, Vector2.ZERO)
	boss.phase = 2
	boss.friendly = false
	boss.invuln = false
	boss.web = [{"o": {"pos": Vector2(0, 0), "dead": false}}, {"o": {"pos": Vector2(100, 0), "dead": false}}, {"o": {"pos": Vector2(200, 0), "dead": false}}]
	check(g.bai.finals.force_move(boss, move, Vector2.RIGHT, 200.0), move + " schedules")
	check(g.warns.size() == expected, move + " round count")
	var deadlines: Array = g.warns.map(func(w): return w.dur)
	deadlines.sort()
	Sfx.trace.clear()
	var elapsed := 0.0
	for deadline in deadlines:
		await get_tree().create_timer(0.08).timeout
		g.tele.update_warns(float(deadline) + 0.001 - elapsed)
		elapsed = float(deadline) + 0.001
	check(Sfx.trace.filter(func(row): return row[1] == "cue_beam_hit").size() == expected, move + " sounds on every actual round")
	g.warns.clear()
	check(g.bai.finals.force_move(boss, move, Vector2.RIGHT, 200.0), move + " reschedules")
	boss.stun = 1.0
	Sfx.trace.clear()
	await get_tree().create_timer(0.08).timeout
	g.tele.update_warns(10.0)
	check(Sfx.trace.filter(func(row): return row[1] == "cue_beam_hit").is_empty(), move + " cancelled rounds stay silent")
