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
	verify_marks()
	game.t = 6.05
	await shot("no_flash.png")
	assert(game.world.dc_checked > 0, "--dccheck did not exercise cached ordinary enemies")
	print("ELITE_MARK_REVIEW dc_checked=", game.world.dc_checked, " sample_count=", samples.size())
	get_tree().quit()

## 等一帧画完：出图时等渲染（frame_post_draw）；快检无头没有渲染帧，改等两次 process_frame（世界层照常 _draw，--dccheck 比对得到）
func _frame() -> void:
	if out != "":
		await RenderingServer.frame_post_draw
	else:
		await get_tree().process_frame
		await get_tree().process_frame


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
		await _frame()
		game.glow_cur = game.glow_next
		game.glow_next = []
		game.glow_tex_cur = game.glow_tex_next
		game.glow_tex_next = []
		emitted = game.glow_cur.size()
		for point in game.glow_cur:
			colours[str(point[2])] = true
		game.optical.glow_node.queue_redraw()
		await _frame()
	assert(out == "" or emitted > 0, "Frozen review did not forward fresh emit points")
	print("ELITE_MARK_EMIT ", name, " points=", emitted, " colours=", colours.keys())
	if out != "":
		get_viewport().get_texture().get_image().save_png(out + "/" + name)


func verify_marks() -> void:
	# Exercise the production HUD geometry, including an elite+squad overlap.
	var saved: Array = game.enemies.duplicate()
	game.enemies.clear()
	var ct: Transform2D = game.get_canvas_transform()
	var empty_count: int = game.hud_view._elite_mark_batch(ct).pts.size()
	var e: Dictionary = samples[2].duplicate()
	e.elite = true
	game.enemies.append(e)
	var squad_batch = game.hud_view._elite_mark_batch(ct)
	assert(squad_batch.pts.size() - empty_count == 24, "Squad must contain six marker rectangles only")
	assert(squad_batch.cols.has(Color.html("b96b70")), "Squad triangle colour changed")
	e["squad"] = false
	var elite_batch = game.hud_view._elite_mark_batch(ct)
	assert(elite_batch.pts.size() - empty_count == 32, "Elite must retain two healthbar rectangles")
	assert(elite_batch.cols.has(Color(0.95, 0.97, 1.0)), "Elite white triangle lost")
	game.enemies.clear()
	game.enemies.append_array(saved)
	for on in [false, true]:
		game.world.elite_mark_v2 = on
		for squad in [false, true]:
			e["squad"] = squad
			for time in [0.0, 0.05, 0.15, 2.99, 3.0, 3.05, 6.05]:
				game.t = time
				e["ishar_blessed"] = false
				if on:
					assert(not game.world._rim_on(e), "v2 unblessed member must never flash its rim")
				elif squad:
					assert(game.world._rim_on(e), "Default-off squad rim changed")
				e["ishar_blessed"] = true
				assert(game.world._rim_on(e), "Blessing must override v2 outline suppression")
				assert(game.world._ol_col(e) == Color(3.2, 0.24, 0.3, 0.9), "Blessed special colour overridden")
	game.world.elite_mark_v2 = true
	print("ELITE_MARK_RULES PASS: squad 24 vertices, elite 32; no periodic rim; blessing priority in both toggles")
