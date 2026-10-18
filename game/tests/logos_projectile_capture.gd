extends Node
const OB = preload("res://scripts/characters/op_blocks.gd")

func _ready() -> void:
	var output := ProjectSettings.globalize_path("res://../build/logos_projectile_capture")
	DirAccess.make_dir_recursive_absolute(output)
	var g = load("res://game.tscn").instantiate()
	add_child(g)
	for i in 5:
		await get_tree().process_frame
	g.set_process(false)
	g.mode = g.Mode.PLAY
	g.state = g.S.PLAY
	g.sandbox = true
	g.t = 60.0
	g.invuln = 999.0
	g.xp_need = 1000000000.0
	var o = g.squad.get_op("logos")
	assert(o != null)
	var center: Vector2 = g.ppos
	o.pos = center
	o.sp = [-10000.0, -10000.0, -10000.0]
	o.cd = 0.0
	o.fire_t = -1.0
	for e in g.enemies:
		e.dead = true
	g.enemies.clear()
	var target: Dictionary = g.spawner.spawn_enemy("stone", center + Vector2(272, 0))
	target.hp = 1000000.0
	target.max_hp = target.hp
	target.spd = 0.0
	g.enemies_sys.build_grid()
	var evidence := []
	var variants := {}
	var start: float = g.t
	for frame in 168:
		for step in 3:
			g._update(1.0 / 60.0)
			g.world.update_visuals(1.0 / 60.0)
			g.world.present_step()
		var visible := []
		for bo in o.hw.get("bolts", []):
			if not bo.has("visual"):
				continue
			var pose := OB.hw_bolt_pose(bo)
			var v: int = bo.visual.variant
			variants[v] = true
			visible.append({"variant": v, "u": bo.visual.u, "age": bo.age,
				"x": pose[0].x, "y": pose[0].y, "angle": pose[1],
				"logical_x": bo.pos.x, "logical_y": bo.pos.y})
		evidence.append({"frame": frame, "t": g.t - start, "bolts": visible})
		g.queue_redraw()
		g.fx_add.queue_redraw()
		g.fg.queue_redraw()
		g.hud.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		assert(not image.is_empty())
		assert(image.save_png(output.path_join("f_%04d.png" % frame)) == OK)
	var file := FileAccess.open(output.path_join("evidence.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence))
	file.close()
	assert(variants.has(0) and variants.has(1))
	assert(g.tex.get("proj_logos_ink_a") != null and g.tex.get("proj_logos_ink_b") != null)
	print("LOGOS PROJECTILE CAPTURE: 168 game-rendered frames, variants A/B, failures=0")
	o.hw.word_q.clear()
	o.hw.bolts.clear()
	o = null
	target = {}
	g.world._gc_sink = null
	var hud = g.hud_view
	for section in [hud.bars, hud.relics, hud.squad, hud.banners]:
		section.h = null
	g.queue_free()
	await get_tree().process_frame
	hud._layers.clear()
	Sfx.set_process(false)
	for player in Sfx.get_children():
		if player is AudioStreamPlayer:
			player.stop()
			player.stream = null
			player.queue_free()
	await get_tree().create_timer(0.1).timeout
	get_tree().quit()
