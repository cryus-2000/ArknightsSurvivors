extends Node
var g
var frames := 0
func _ready() -> void:
	g = load("res://game.tscn").instantiate()
	add_child(g)
func _process(_dt: float) -> void:
	frames += 1
	if frames != 5:
		return
	set_process(false)
	g.set_process(false)
	var op = g.squad.get_op("kaltsit")
	assert(op != null)
	op.m.pos = g.ppos
	var failures := 0
	for mode in [0, 1, 2]:
		for face in [1.0, -1.0]:
			g.fx.clear()
			op.m.face = face
			op.coord = mode == 1
			op.melt = 1.0 if mode == 2 else 0.0
			op._m_claw(1.0, false)
			var expected := "fx_mon3tr_melt_slash" if mode == 2 else "fx_mon3tr_claw"
			var found := false
			for f in g.fx:
				if f.get("name", "") == expected:
					found = true
					assert(f.flip == (face < 0.0))
			if not found:
				failures += 1
				print("MISSING ", expected, " mode=", mode, " face=", face)
			if OS.get_cmdline_user_args().has("--capture-fx"):
				for f in g.fx:
					if f.get("kind", "") == "sprite":
						f.life = f.max * 0.4
				g.queue_redraw()
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("../build/mon3tr_fx_%s_%s.png" % [mode, int(face)])
	print("MON3TR FX failures=", failures)
	op = null
	g.queue_free()
	g = null
	await get_tree().process_frame
	get_tree().quit(0 if failures == 0 else 1)
