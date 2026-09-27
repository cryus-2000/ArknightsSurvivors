extends Node
var game: Node
var frames := 0
var fails := 0
func _ready() -> void:
	game = load("res://game.tscn").instantiate()
	add_child(game)
func check(v: bool, label: String) -> void:
	if not v:
		fails += 1
		push_error(label)
func choose(ev: String, suffix: String) -> void:
	game.endg.open(ev)
	for i in game.choices.size():
		if str(game.choices[i].id).ends_with(suffix):
			game.progression.pick(i)
			return
	check(false, "missing choice " + ev + suffix)
func _process(_dt: float) -> void:
	frames += 1
	if frames != 5:
		return
	game.set_process(false)
	game.pending_levelups = 0
	game.pending_chests = 0
	game.show_queue.clear()
	game.progression.gain_relic("222")
	choose("resolve1", ":1") # observation already owned
	choose("resolve2", ":2") # hesitation already owned
	game.endg.open("resolve3")
	check(game.choices.size() == 2, "third choice offers resolve and leave")
	choose("resolve3", ":-2")
	check(game.state == game.S.PLAY and not game.panel.visible, "leave closes event and resumes play")
	check(not game.relics.has("238") and game.pending_chests == 0, "leave grants no resolve or chest")
	check(game.endg.cur == "knight", "knight route remains without resolve")
	choose("resolve1", ":0")
	choose("resolve2", ":0")
	check(game.endg.cur == "knight", "living knight takes priority over resolve")
	game.zone_state = 2
	game.zone_c = Vector2.ZERO
	game.zone_r = 400.0
	game.ppos = Vector2.ZERO
	var b: Dictionary = game.spawner.spawn_enemy("knight_boss", Vector2(390, 0))
	b.age = 10.0
	for side in [-1.0, 1.0]:
		b.pos = Vector2(side * 390.0, 0)
		b.kb = Vector2(side * 1500.0, 0)
		b.kb_self = true
		game.enemies_sys.update(0.1)
		check(absf(b.pos.x) <= 244.0, "boss charge keeps drawn body inside tide on both sides")
		game.knight.pos = Vector2(side * 390.0, 0)
		game.knight.state = "charge"
		game.knight.st = 0.0
		game.knight.dash_dir = Vector2(side, 0)
		game.knight.update(0.1)
		check(game.knight.pos.length() <= 267.0, "ally charge stays inside tide")
	# 圈顶最大画幅角点：受击拉伸与上浮同时存在也必须在圆内。
	b.pos = Vector2(0, -390)
	b.kb = Vector2(0, -1500)
	b.kb_self = true
	b.squash = 0.14
	game.enemies_sys.update(0.1)
	for side in [-1.0, 1.0]:
		var corner := Vector2(side * (48.0 * 1.4 * 1.3 + 2.0), -(80.0 * 1.4 + 16.0))
		check((b.pos + corner).distance_to(game.zone_c) <= game.zone_r, "boss upper corner and lift remain in circle")
	game.knight.pos = Vector2(0, -390)
	game.knight.state = "charge"
	game.knight.st = 0.0
	game.knight.dash_dir = Vector2.UP
	game.knight.update(0.1)
	for side in [-1.0, 1.0]:
		var corner := Vector2(side * (48.0 * 1.4 + 2.0), -(80.0 * 1.4 + 2.0))
		check((game.knight.pos + corner).distance_to(game.zone_c) <= game.zone_r, "ally upper corner remains in circle")
	game.zone_c = Vector2(90, -60)
	game.zone_r = 210.0
	game.enemies_sys.update(0.1)
	game.knight.state = "retreat"
	game.ppos = Vector2(900, 0)
	game.knight.update(0.1)
	check(b.pos.distance_to(game.zone_c) <= 54.0, "boss follows shrinking shifted arena")
	check(game.knight.pos.distance_to(game.zone_c) <= 77.0, "ally retreat cannot follow player into tide")
	print("ROUTE KNIGHT REGRESSION: ", fails, " failures")
	game.queue_free()
	game = null
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
	get_tree().quit(fails)
