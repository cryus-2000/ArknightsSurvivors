extends Node
## Shared beam salvos keep one warning and one impact voice, independently.
var failures := 0


func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		print("FAIL: " + label)


## 按真实时间等（Sfx 的同轮合并窗 MERGE_T 是真实时间）：create_timer 走游戏时间，帧时长不均 / 时间缩放时
## 两次出声可能落在同一个合并窗里、后一轮被吞（ci-5ea1da44b-r1、ci-efc593d37 的偶发红，本机也复现到第 2 轮 0 声）
func wait_real(s: float) -> void:
	var t0 := Time.get_ticks_usec()
	while (Time.get_ticks_usec() - t0) / 1000000.0 < s:
		await get_tree().process_frame


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
	await wait_real(0.08)
	Sfx.play_cue("光束", "ishar", "start")
	check(voices("cue_beam_start") == 1, "salvo warning does not stack")
	Sfx.play_cue("beam", "paranoia", "hit")
	await wait_real(0.08)
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
	# 同轮合并按真实时间（Sfx.MERGE_T = 0.05 秒）判：机器忙时一轮三发可能跨过合并窗、多出一声（ci-5ea1da44b-r1 / ci-efc593d37 偶发红）。
	# 所以逐轮判：每轮至少一声（不带名字的后续轮也要有）；这一轮三发在合并窗内结算完时必须正好一声
	var per_round: Array = []
	for round_i in 3:
		await wait_real(0.08)
		var t0 := Time.get_ticks_usec()
		var n0: int = Sfx.trace.filter(func(row): return row[1] == "cue_beam_hit").size()
		for beam_i in 3:
			var w: Dictionary = g.tele.warn(boss, "line", 0.8, {"act": "beam", "name": "凝视" if round_i == 0 and beam_i == 0 else "", "dmg": 0.0})
			g.tele._resolve(w)
		var n: int = Sfx.trace.filter(func(row): return row[1] == "cue_beam_hit").size() - n0
		var fast: bool = (Time.get_ticks_usec() - t0) / 1000000.0 < Sfx.MERGE_T * 0.8
		per_round.append(n)
		check(n >= 1 and (n == 1 or not fast), "firing round %d produces one cue (unnamed follow-ups included): %d" % [round_i, n])
	check(per_round.reduce(func(a, b): return a + b, 0) >= 3, "three firing rounds produce three cues including unnamed follow-ups")
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
		await wait_real(0.08)
		g.tele.update_warns(float(deadline) + 0.001 - elapsed)
		elapsed = float(deadline) + 0.001
	check(Sfx.trace.filter(func(row): return row[1] == "cue_beam_hit").size() == expected, move + " sounds on every actual round")
	g.warns.clear()
	check(g.bai.finals.force_move(boss, move, Vector2.RIGHT, 200.0), move + " reschedules")
	boss.stun = 1.0
	Sfx.trace.clear()
	await wait_real(0.08)
	g.tele.update_warns(10.0)
	check(Sfx.trace.filter(func(row): return row[1] == "cue_beam_hit").is_empty(), move + " cancelled rounds stay silent")
