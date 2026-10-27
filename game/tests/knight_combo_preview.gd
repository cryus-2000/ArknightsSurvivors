extends "res://tests/final_boss_fx_preview.gd"
## One forced opener per segment; follow-ups, movement and recovery use the production AI.
func _ready() -> void:
	var check_only := "--combo-check" in OS.get_cmdline_user_args()
	kind = "knight_boss"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--boss="): kind = arg.substr(7)
		if arg.begins_with("--shotdir="): out_dir = arg.substr(10)
		if arg.begins_with("--quality="): quality = arg.substr(10)
	if out_dir.is_empty() or not kind in ["paranoia", "knight_boss", "ishar", "izumik"]:
		push_error("Expected --boss and --shotdir")
		get_tree().quit(2)
		return
	Cfg.quality = quality
	Cfg.character_id = "mizuki"
	AudioServer.set_bus_mute(0, true)
	g = load("res://game.tscn").instantiate()
	add_child(g)
	g.set_process(false)
	g.state = g.S.PLAY
	g.mode = g.Mode.PLAY
	g.hud.visible = false
	g.panel.hide()
	g.t = 100.0
	g.zone_frozen = true
	g.zone_state = 3
	g.zone_c = Vector2.ZERO
	g.zone_next_c = Vector2.ZERO
	g.zone_r = 650.0
	g.zone_next_r = 650.0
	g.ppos = Vector2(180, 0)
	g.doc_pos = Vector2(190, 35)
	g.invuln = 999.0
	g.rng.seed = 271027
	g.vrng.seed = 271028
	seed(271029)
	var overlay := CanvasLayer.new()
	overlay.layer = 120
	add_child(overlay)
	title = Label.new()
	title.position = Vector2(22, 14)
	title.add_theme_font_override("font", load("res://fonts/ui.ttf"))
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_shadow_color", Color.BLACK)
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	overlay.add_child(title)
	for i in 12:
		visual_step(DT)
		await get_tree().process_frame
		if not check_only: await RenderingServer.frame_post_draw
	for scenario in [{"name":"弧斩接冲锋", "move":"断潮劈击", "phase":1}, {"name":"双冰阵连招", "move":"踏冰裂阵", "phase":1}, {"name":"二阶段弧斩追击", "move":"断潮劈击", "phase":2}]:
		fresh()
		g.enemies = [boss]
		if scenario.phase == 2:
			g.bai.setup_preview_phase2(boss)
			boss.channel = 0.0
			boss.invuln = false
		boss.wind = 0.6 # Only hold until the one forced opener; the rest is ordinary AI.
		var events: Array = []
		var watched: Array = []
		var seen_release: Array = []
		var travel := 0.0
		var previous_break := 0.0
		var current_move := "准备"
		var player_status := {"pstun_max":0.0,"root_max":0.0,"pstun_samples":0,"root_samples":0,"pstun_stages":{}}
		for frame_i in 540:
			var elapsed: float = frame_i * DT
			g.invuln = 999.0
			g.ppos = g.ppos.move_toward(path_target(fmod(elapsed, 12.0)), 100.0 * DT)
			g.doc_pos = g.ppos + Vector2(10,35)
			g.t += DT
			if frame_i == 15:
				var dir: Vector2 = (g.ppos - boss.pos).normalized()
				if not g.bai.boss(kind).force_move(boss, scenario.move, dir, boss.pos.distance_to(g.ppos)):
					push_error("Combo opener failed")
					get_tree().quit(3)
					return
			var before: Vector2 = boss.pos
			g.enemies_sys.build_grid()
			var nfx: int = g.fx.size()
			g.enemies_sys.update(DT)
			g.vfx.mark_enemy_fx(nfx)
			travel += before.distance_to(boss.pos)
			inspect_player_status(player_status,"after_enemies")
			g.shots.step(DT)
			inspect_player_status(player_status,"after_shots")
			g.tele.update_warns(DT)
			inspect_player_status(player_status,"before_status_conversion")
			g.enemies_sys.update_status(DT)
			inspect_player_status(player_status,"after_status_conversion")
			for w in g.warns:
				if not is_same(w.owner,boss) or w.dmg <= 0.0: continue
				if watched.any(func(old):return is_same(old,w)): continue
				watched.append(w)
				if not str(w.name).is_empty(): current_move = str(w.name)
				events.append({"event":"warning","name":str(w.name),"act":str(w.act),"skin":str(w.get("skin","")),"angle":float(w.get("ang",0.0)),"t":elapsed,"duration":w.dur,"frame":shot_i})
			for w in watched:
				if not w.done or seen_release.any(func(old):return is_same(old,w)): continue
				seen_release.append(w)
				events.append({"event":"release","name":str(w.name),"act":str(w.act),"skin":str(w.get("skin","")),"angle":float(w.get("ang",0.0)),"boss_pos":[boss.pos.x,boss.pos.y],"t":elapsed,"frame":shot_i})
			var brk: float = boss.get("break_t",0.0)
			if brk > previous_break + 0.1:
				events.append({"event":"recovery","name":str(boss.get("brk_label","破绽")),"t":elapsed,"duration":brk,"frame":shot_i})
			elif brk <= 0.0 and previous_break > 0.0:
				events.append({"event":"recovery_end","t":elapsed,"frame":shot_i})
			previous_break = brk
			var status: String = "破绽 %.1fs" % brk if brk > 0.0 else ("连段" if boss.get("knight_combo_active",false) else "调整")
			title.text = str(scenario.name) + " · " + quality + " · %.1fs\n" % elapsed + current_move + " · " + status
			g.vfx.update(DT)
			g.fx = g.fx.filter(func(f):return f.life > 0.0)
			visual_step(DT)
			await get_tree().process_frame
			if not check_only: await RenderingServer.frame_post_draw
			if frame_i % 2 == 0:
				var result: Error = OK if check_only else get_viewport().get_texture().get_image().save_png(out_dir.path_join("frame_%05d.png" % shot_i))
				if result != OK:
					push_error("Could not save combo frame")
					get_tree().quit(4)
					return
				shot_i += 1
		print("FX_PREVIEW_METRICS ",JSON.stringify({"move":scenario.name,"phase":scenario.phase,"forced_openers":1,"boss_travel":travel,"player_status":player_status,"events":events}))
	print("FX_PREVIEW_DONE boss=%s quality=%s frames=%d combos=true optical=%s" % [kind,quality,shot_i,g.optical_on])
	g.queue_free()
	await get_tree().process_frame
	get_tree().quit()

## Sample before and after production status conversion so a transient direct pstun write is not hidden.
func inspect_player_status(metrics: Dictionary, stage: String) -> void:
	metrics.pstun_max = maxf(float(metrics.pstun_max),g.pstun)
	metrics.root_max = maxf(float(metrics.root_max),g.root_t)
	if g.pstun > 0.0:
		metrics.pstun_samples += 1
		metrics.pstun_stages[stage] = int(metrics.pstun_stages.get(stage,0)) + 1
	if g.root_t > 0.0: metrics.root_samples += 1
