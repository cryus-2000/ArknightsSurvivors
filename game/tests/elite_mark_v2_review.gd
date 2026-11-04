extends Node
## Arranged live-renderer review: real enemies, fixed same-frame off/on comparison.
const Bal = preload("res://scripts/core/balance.gd")
var game: Node
var ticks := 0
var out := ""
var samples: Array[Dictionary] = []

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--review-dir="):
			out = a.substr(13)
	game = load("res://game.tscn").instantiate()
	add_child(game)

func _process(_dt: float) -> void:
	ticks += 1
	if ticks == 12:
		capture.call_deferred()

func capture() -> void:
	game.set_process(false)
	game.set_physics_process(false)
	# Make the freeze explicit for the optical child too; shot() maintains its
	# draw-time double buffer rather than depending on child process ordering.
	game.optical.set_process(false)
	for e in game.enemies:
		e.dead = true
	game.fx.clear()
	game.t = 4.5
	var origin: Vector2 = game.ppos
	for i in 5:
		var e: Dictionary = game.spawner.spawn_enemy("pocket" if i == 1 else "runner", origin + Vector2(-300 + i * 150, -90))
		if i >= 2:
			e["squad"] = true
			e.cross_elite = true
		e.wind = 0.0
		e.flash = 0.0
		e.wake_t = 0.0
		samples.append(e)
	game.cam.position = origin
	game.cam.offset = Vector2.ZERO
	game.cam.zoom = Vector2.ONE
	for on in [0, 1]:
		Bal.sec("render")["elite_mark_v2"] = on
		game.world.elite_mark_v2 = on == 1
		for e in samples:
			if on == 1 and (e.elite or e.get("squad", false)):
				assert(not game.world._dc_ok(e))
		await shot("off.png" if on == 0 else "on.png")
	game.t = 6.05
	await shot("squad_flash.png")
	assert(game.world.dc_checked > 0, "--dccheck did not exercise cached ordinary enemies")
	print("ELITE_MARK_REVIEW dc_checked=", game.world.dc_checked, " sample_count=", samples.size())
	get_tree().quit()

func shot(name: String) -> void:
	var emitted := 0
	var colours := {}
	for i in 3:
		if game.optical._lo_on:
			game.optical._lo_step()
		game.glow_next = []
		game.glow_tex_next = []
		game.queue_redraw()
		game.hud.queue_redraw()
		await RenderingServer.frame_post_draw
		game.glow_cur = game.glow_next
		game.glow_next = []
		game.glow_tex_cur = game.glow_tex_next
		game.glow_tex_next = []
		emitted = game.glow_cur.size()
		for point in game.glow_cur:
			colours[str(point[2])] = true
		game.optical.glow_node.queue_redraw()
		await RenderingServer.frame_post_draw
	assert(emitted > 0, "Frozen review did not forward fresh emit points")
	print("ELITE_MARK_EMIT ", name, " points=", emitted, " colours=", colours.keys())
	get_viewport().get_texture().get_image().save_png(out + "/" + name)
