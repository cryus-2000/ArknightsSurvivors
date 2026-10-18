extends Node

var game: Node
var frames := 0
var fails := 0

func _ready() -> void:
	game = load("res://game.tscn").instantiate()
	add_child(game)

func check(value: bool, message: String) -> void:
	if not value:
		fails += 1
		printerr("FAIL: ", message)

func _process(_dt: float) -> void:
	frames += 1
	if frames != 5:
		return
	set_process(false)
	game.set_process(false)
	game.doc_moving = false
	game.world.anim_name = ""
	game.world.update_doctor_anim(0.0)
	check(game.sprite.texture.get_height() == 96 and game.sprite.hframes == 4, "old idle")
	check(game.sprite.offset.y == -44.0, "idle foot 46")
	game.doc_moving = true
	game.world.update_doctor_anim(0.0)
	check(game.sprite.texture.get_height() == 128 and game.sprite.hframes == 8, "new run")
	check(game.sprite.offset.y == -56.0, "run foot 60")
	for i in 16:
		game.world.anim_t = float(i) / 10.0 + 0.001
		game.world.update_doctor_anim(0.0)
		check(game.sprite.frame == i % 8, "10 fps / 0.8 s loop frame %d" % i)
	game.doc_moving = false
	game.world.update_doctor_anim(0.0)
	check(game.sprite.hframes == 4 and game.sprite.offset.y == -44.0 and game.sprite.frame == 0, "return to idle")
	game.state = game.S.DEAD
	game.world.update_doctor_anim(2.0)
	check(game.sprite.texture.get_height() == 96 and game.sprite.frame == 3, "death stays on last frame")
	print("DOCTOR RUN failures=", fails)
	game.world._gc_sink = null
	var hud = game.hud_view
	for section in [hud.bars, hud.relics, hud.squad, hud.banners]:
		section.h = null
	game.queue_free()
	game = null
	await get_tree().process_frame
	hud._layers.clear()
	await get_tree().create_timer(0.1).timeout
	Sfx.set_process(false)
	for player in Sfx.get_children():
		if player is AudioStreamPlayer:
			player.stop()
			player.stream = null
			player.queue_free()
	await get_tree().create_timer(0.1).timeout
	get_tree().quit(1 if fails else 0)
