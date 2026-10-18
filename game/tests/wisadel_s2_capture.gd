extends Node

func _ready() -> void:
	var output := ProjectSettings.globalize_path("res://../build/wisadel_s2_capture")
	DirAccess.make_dir_recursive_absolute(output)
	var g = load("res://game.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	g.state = g.S.PLAY
	g.t = 60.0
	g.invuln = 999.0
	g.xp_need = 1000000000.0
	var center: Vector2 = g.ppos
	var evidence := []
	var o = g.squad.get_op("wisadel")
	o.pos = center
	o.is_leader = true
	o.elite = 1
	o.refresh_stats()
	o.sp = [-10000.0, -10000.0, -10000.0]
	o.cd = 0.0
	o.attack_t = 0.0
	o.fire_t = -1.0
	for k in 6:
		var enemy: Dictionary = g.spawner.spawn_enemy("stone", center + Vector2(120+k*8, (k%3-1)*16))
		enemy.hp = 1000000.0
		enemy.max_hp = 1000000.0
	g.enemies_sys.build_grid()
	o.start_skill(Vector2.INF,1)
	for frame in 210:
		for step in 3:
			g._update(1.0/60)
			g.world.update_visuals(1.0/60)
			g.world.present_step()
		g.queue_redraw()
		g.fx_add.queue_redraw()
		g.fg.queue_redraw()
		g.hud.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		if image.save_png(output.path_join("s2_%03d.png" % frame)) != OK:
			get_tree().quit(1)
			return
		evidence.append({"frame":frame,"kind":o.anim_state().kind,"pose":o.anim_state().frame,"remaining":o.skill_active_left(1),"phase":o.sq_ph,"overload":o.phases.get("index",0)>0})
	var file := FileAccess.open(output.path_join("evidence.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence));file.close()
	print("WISADEL S2 CAPTURE: 210 frames")
	for enemy in g.enemies:
		for key in ["partner", "owner", "spawned_after", "core"]:
			enemy.erase(key)
	g.world._gc_sink = null
	var hud = g.hud_view
	for section in [hud.bars, hud.relics, hud.squad, hud.banners]:
		section.h = null
	g.queue_free()
	await get_tree().process_frame
	hud._layers.clear()
	await get_tree().process_frame
	Sfx.set_process(false)
	for player in Sfx.get_children():
		if player is AudioStreamPlayer:
			player.stop()
			player.stream = null
			player.queue_free()
	await get_tree().create_timer(0.1).timeout
	get_tree().quit()
