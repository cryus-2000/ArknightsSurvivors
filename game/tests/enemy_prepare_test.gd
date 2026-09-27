extends Node
## Run via tools/godot_runner.py; verifies anticipation does not bypass real warning.
var game: Node
var frames := 0
var failures := 0
func _ready() -> void:
	game = load("res://game.tscn").instantiate()
	add_child(game)
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
func _process(_dt: float) -> void:
	frames += 1
	if frames != 5:
		return
	set_process(false)
	game.set_process(false)
	for kind in ["reaper", "tracer", "nest", "founder"]:
		var e: Dictionary = game.spawner.spawn_enemy(kind, game.ppos + Vector2(280, 0))
		e.dormant = false
		e.wake_t = 0.0
		game.warns.clear()
		var hp: float = game.hp
		var nerve: float = game.nerve
		game.eai.pattern(e, Vector2.LEFT, 280.0, 0.1, e.spd)
		check(e.get("attack_preparing", false), kind + " prepares before attack range")
		check(game.warns.is_empty(), kind + " no early hit warning")
		check(game.hp == hp and game.nerve == nerve, kind + " no early damage")
		game.eai.pattern(e, Vector2.LEFT, 500.0, 0.1, e.spd)
		check(not e.get("attack_preparing", false), kind + " clears pose out of perception")
		game.eai.pattern(e, Vector2.LEFT, 70.0, 0.1, e.spd)
		check(not game.warns.is_empty(), kind + " actual attack still warns")
		if not game.warns.is_empty():
			check(float(game.warns[-1].dur) >= 0.55, kind + " full reaction interval")
		if OS.get_cmdline_user_args().has("--capture-enemy"):
			e.pos = game.ppos + Vector2(115, 0)
			e.wind = 0.0
			e.atk_until = game.t + 0.19
			game.warns.clear()
			game.queue_redraw()
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("../build/enemy_attack_%s.png" % kind)
		e.dead = true
	var sleeper: Dictionary = game.spawner.spawn_enemy("reaper", game.ppos + Vector2(280, 0))
	sleeper.dormant = true
	game.eai.pattern(sleeper, Vector2.LEFT, 280.0, 0.1, sleeper.spd)
	check(not sleeper.dormant and sleeper.wake_t == 0.4, "earlier wake preserves awakening delay")
	print("ENEMY PREPARE TEST: ", failures, " failures")
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
	get_tree().quit.call_deferred(failures)
