extends Node
var failures := 0
const D = preload("res://scripts/data.gd")
const Squads = preload("res://scripts/run/practice_squads.gd")
const Meta = preload("res://scripts/core/meta.gd")

func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("BOSS TRIAL: " + what)

func _ready() -> void:
	call_deferred("run")

func trial_game(group: Array, phase := 1, safe := true):
	Cfg.boss_trial_request = {"group": group, "operator": "wisadel", "growth": 2, "phase": phase, "safe": safe}
	var game = load("res://game.tscn").instantiate()
	add_child(game)
	game.set_process(false)
	return game

func run() -> void:
	var saved_character: String = Cfg.character_id
	var saved_unlocked: int = Cfg.diff_unlocked
	var saved_endings: Array = Cfg.endings_cleared.duplicate()
	var g = trial_game(["ishar"], 2)
	check(g.trial.active and Cfg.practice_active and Cfg.boss_trial_request.is_empty(), "consume transient request once")
	check(g.ch.id == "wisadel" and Cfg.character_id == saved_character, "trial operator does not replace deploy choice")
	check(g.ch.elite == 2 and g.state == g.S.PLAY, "growth applied and no opening/promotion modal")
	check(g.bosses.size() == 1 and g.final_boss.phase == 2, "actual transformed boss spawned")
	check(g.final_boss.has("transform_started"), "phase two retains transformation animation")
	check(g.final_boss.pos.distance_to(g.zone_c) < g.zone_r - g.final_boss.r, "boss starts within arena")
	var original_count: int = g.enemies.size()
	g.hp = -1.0
	for i in 12:
		g._update(1.0 / 60.0)
	check(g.hp > 0 and g.state == g.S.PLAY, "observe mode survives lethal HP")
	check(g.enemies.size() == original_count and g.merchant.is_empty(), "no timed waves or merchant")
	check(g.gems.is_empty() and g.pending_chests == 0 and g.pending_levelups == 0, "no rewards or choice modals")
	# Real scheduler: speed affects simulation and Doctor follow, pause remains frozen.
	var saved_speed: float = Cfg.play_speed
	var saved_hitstop: bool = Cfg.hitstop
	Cfg.play_speed = 1.5   # 10-22 起只有 1× / 1.5×
	Cfg.hitstop = false
	var tick0: float = g.t
	g._process(1.0 / 30.0)
	check(is_equal_approx(g.t - tick0, 1.5 / 30.0), "game process runs 1.5x simulation")
	g.state = g.S.PAUSE
	tick0 = g.t
	g._process(0.05)
	check(g.t == tick0, "pause does not advance simulation")
	g.state = g.S.PLAY
	g.enemies.clear()
	var key := InputEventKey.new()
	key.keycode = KEY_D
	key.pressed = true
	Input.parse_input_event(key)
	for i in 300:
		g._process(1.0 / 60.0)
	key = key.duplicate()
	key.pressed = false
	Input.parse_input_event(key)
	check(g.doc_pos.distance_to(g.ppos) < 180.0, "Doctor follows 1.5x running without falling behind")
	Cfg.play_speed = saved_speed
	Cfg.hitstop = saved_hitstop
	g.final_boss.dead = true
	g._update(0.01)
	check(g.victory.active and g.state == g.S.PLAY, "death begins cinematic before results")
	var bt: float = g.final_boss.bt
	g.victory.step(0.85)
	check(g.state == g.S.PLAY and g.final_boss.bt == bt, "cinematic freezes combat for display")
	g.victory.step(0.86)
	check(g.state == g.S.WIN and not g.victory.active, "cinematic completes into trial results")
	check(Cfg.diff_unlocked == saved_unlocked and Cfg.endings_cleared == saved_endings, "trial victory never unlocks progress")
	g.trial.retry()
	check(Cfg.boss_trial_request.group == ["ishar"] and Cfg.boss_trial_request.phase == 2, "retry retains chosen scenario")
	Cfg.seen_shows.append("test-trial-only")
	g.queue_free()
	await get_tree().process_frame
	check(not Cfg.practice_active and not Cfg.seen_shows.has("test-trial-only"), "exit restores in-memory progress")
	g = trial_game(["bishop", "archon"])
	check(g.trial.targets.size() == 2 and is_same(g.trial.targets[0].partner, g.trial.targets[1]), "paired Boss partners linked")
	g.trial.targets[0].dead = true
	check(not g.trial.won(), "one half cannot prematurely finish encounter")
	g.trial.targets[1].dead = true
	check(g.trial.won(), "all targets required")
	g.queue_free()
	await get_tree().process_frame
	g = trial_game(["knight_boss"], 2, false)
	check(g.final_boss.phase == 2 and g.final_boss.hp == g.final_boss.maxhp * 0.5, "knight phase two matches real rebirth HP")
	g.hp = -1.0
	g._update(0.01)
	check(g.state == g.S.DEAD, "real combat mode can fail")
	g.queue_free()
	await get_tree().process_frame
	Cfg.boss_trial_request.clear()
	# 成品分队（docs/170 测试台到场快照，用户 10-28）：队伍按快照重放成长、认知按分队那一档；自选队长补到到场平均水平
	var sq: Array = Squads.list()
	check(sq.size() >= 6, "practice squads shipped with the game data")
	if not sq.is_empty():
		var sid: String = str(sq[sq.size() - 1].id)
		var snap: Dictionary = Squads.snap_for(sid, ["paranoia"])
		Cfg.boss_trial_request = {"group": ["paranoia"], "operator": "mizuki", "growth": 0, "phase": 1, "safe": true, "squad": sid}
		g = load("res://game.tscn").instantiate()
		add_child(g)
		g.set_process(false)
		check(g.trial.active and g.squad.ops.size() == snap.fp.squad.size(), "squad members rebuilt from snapshot")
		check(g.level == int(snap.fp.level) and g.relics.size() == snap.fp.relics.size(), "squad level and relics from snapshot")
		check(str(g.ch.id) == str(snap.leader), "snapshot leader leads the practice")
		check(Meta.practice_budget == int(Squads.squad(sid).meta), "squad cognition tier applied")
		check(g.state == g.S.PLAY and g.hp == g.max_hp and g.bosses.size() == 1, "squad practice starts in play at full HP")
		g.queue_free()
		await get_tree().process_frame
		check(Meta.practice_budget == -1, "squad cognition tier cleared on exit")
		g = trial_game(["paranoia"])
		var av: Dictionary = Squads.data().get("avg", {}).get("3", {})
		check(g.level >= int(av.get("level", 1)) and g.max_hp >= float(av.get("max_hp", 0.0)) - 0.5, "custom leader lifted to arrival average")
		g.queue_free()
		await get_tree().process_frame
	Cfg.boss_trial_request.clear()
	# Invalid requests safely fall back; no practice/save lock is left behind.
	g = trial_game(["bone", "not_a_boss"])
	check(not g.trial.active and not Cfg.practice_active, "non-Boss request rejected")
	g.queue_free()
	await get_tree().process_frame
	Cfg.boss_trial_request.clear()
	# Normal victory records at the start, so leaving during the cinematic cannot lose unlocks.
	g = load("res://game.tscn").instantiate()
	add_child(g)
	g.set_process(false)
	g.mode = g.Mode.PLAY   # 演练按正式模式跑（不记自测 / 批跑）
	Cfg.endings_cleared = []
	Cfg.diff_unlocked = 0
	g.tier = 0
	g.victory.begin()
	check(g.victory.active and Cfg.endings_cleared.size() == 1 and Cfg.diff_unlocked == 1, "normal win recorded before cinematic ends")
	check(g.telemetry.record().win, "win telemetry agrees during cinematic")
	g.victory.begin()
	check(Cfg.endings_cleared.size() == 1, "victory commit is idempotent")
	g.queue_free()
	await get_tree().process_frame
	Cfg.endings_cleared = saved_endings
	Cfg.diff_unlocked = saved_unlocked
	Sfx.set_process(false)
	await get_tree().create_timer(0.25, true, false, true).timeout
	for player in Sfx.get_children():
		if player is AudioStreamPlayer:
			player.stop()
			player.stream = null
			player.queue_free()
	await get_tree().create_timer(0.2, true, false, true).timeout
	print("boss_trial_test: %d failures" % failures)
	get_tree().quit(1 if failures else 0)
