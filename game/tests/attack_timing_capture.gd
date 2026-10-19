extends Node

func _ready() -> void:
	var output := ProjectSettings.globalize_path("res://../build/three_attack_capture")
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
	for rate in [1.0, 2.0, 3.0]:
		g.stats.remove_source("timing_capture")
		for id in ["wisadel", "saria", "suzuran"]:
			g.stats.add(&"op_aspd", "override", rate, "timing_capture", "op:" + id)
			var o = g.squad.get_op(id)
			o.pos = center + Vector2(0, 20 * o.slot)
			o.sp = [-10000.0, -10000.0, -10000.0]
			o.cd = 0.0
			o.attack_t = 0.0
			o.fire_t = -1.0
			o.refresh_stats()
		var enemy: Dictionary = g.spawner.spawn_enemy("stone", center + Vector2(65, 0))
		enemy.hp = 1000000.0
		enemy.max_hp = 1000000.0
		for frame in 40:
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
			if image.is_empty() or image.save_png(output.path_join("rate%d_%03d.png" % [rate, frame])) != OK:
				push_error("Attack capture failed")
				get_tree().quit(1)
				return
			for id in ["wisadel", "saria", "suzuran"]:
				var o = g.squad.get_op(id)
				evidence.append({"rate":rate,"frame":frame,"id":id,"kind":o.anim_kind,"pose":o.anim_state().get("frame",-1),"duration":o.attack_dur,"fire":o.attack_fire_at,"aspd":o.stat(&"op_aspd")})
	for idx in range(3):
		for id in ["wisadel", "saria", "suzuran"]:
			var o = g.squad.get_op(id)
			o._sq_clear()
			o.cd = 999.0
			o.attack_t = 0.0
			o.fire_t = -1.0
			o.start_skill(Vector2.INF, idx)
		for frame in 40:
			if frame == 25 and idx == 2:
				g.squad.get_op("wisadel").hw.wd.ammo = 0
				g.squad.get_op("saria").hw.sa.calc = 0.0
				g.squad.get_op("suzuran").hw.sz.haze_t = 0.0
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
			var im := get_viewport().get_texture().get_image()
			if im.save_png(output.path_join("skill%d_%03d.png" % [idx+1, frame])) != OK:
				get_tree().quit(1)
				return
			for id in ["wisadel", "saria", "suzuran"]:
				var o = g.squad.get_op(id)
				evidence.append({"skill":idx+1,"frame":frame,"id":id,"kind":o.anim_kind,"pose":o.anim_state().get("frame",-1),"phase":o.sq_ph})
	var file := FileAccess.open(output.path_join("evidence.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence));file.close()
	print("ATTACK CAPTURE: 240 frames including skills")
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
