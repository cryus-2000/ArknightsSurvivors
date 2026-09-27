extends Node
var g
var frames := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
func _ready() -> void:
	g = load("res://game.tscn").instantiate()
	add_child(g)
func _process(_dt: float) -> void:
	frames += 1
	if frames != 5:
		return
	set_process(false)
	g.set_process(false)
	var op = g.squad.get_op("wisadel")
	check(op != null, "Wisadel initialized")
	check(g.tex.get("fx_wisadel_cannon") != null, "cannon artwork loaded")
	if op != null:
		for variant in 4:
			g.fx.clear()
			if variant < 2:
				op._impact_fx(g.ppos + Vector2(150, 0), 80.0, variant == 0)
			else:
				op._burst_fx(g.ppos + Vector2(150, 0), 110.0, variant == 2)
			var sprites: Array = g.fx.filter(func(f): return f.get("name", "") == "fx_wisadel_cannon")
			check(sprites.size() == 1, "basic/skill cannon uses one animation: %d" % variant)
			if not sprites.is_empty():
				check(sprites[0].scale <= 3.2, "cannon respects shared visual size cap")
			if variant == 3 and OS.get_cmdline_user_args().has("--capture-fx"):
				for fr in 4:
					for f in sprites:
						f.life = f.max * (1.0 - (fr + 0.1) / 4.0)
					g.queue_redraw()
					await RenderingServer.frame_post_draw
					get_viewport().get_texture().get_image().save_png("../build/wisadel_cannon_%d.png" % fr)
		# Missing art keeps the legacy fallback alive rather than dropping impact FX.
		var saved = g.tex["fx_wisadel_cannon"]
		g.tex["fx_wisadel_cannon"] = null
		g.fx.clear()
		op._burst_fx(g.ppos, 100.0)
		check(not op.pfx.is_empty(), "missing texture procedural fallback")
		g.tex["fx_wisadel_cannon"] = saved
	print("WISADEL CANNON failures=", failures)
	op = null
	g.queue_free()
	g = null
	Sfx.set_process(false)
	await get_tree().create_timer(0.25, true, false, true).timeout
	for player in Sfx.get_children():
		if player is AudioStreamPlayer:
			player.stop()
			player.stream = null
			player.queue_free()
	await get_tree().create_timer(0.2, true, false, true).timeout
	get_tree().quit(0 if failures == 0 else 1)
