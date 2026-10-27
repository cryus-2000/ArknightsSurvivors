extends Node
## Staged real-world rendering: actual warning/resolution/hazard code; ordinary AI paused, player invulnerable.
var g
var boss: Dictionary
var kind := "paranoia"
var out_dir := ""
var quality := "high"
var shot_i := 0
var title: Label
const DT := 1.0 / 30.0
const SLOT := 12.0

func _ready() -> void:
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
		await RenderingServer.frame_post_draw
	for move in g.bai.finals.NAMES[kind]:
		fresh()
		title.text = str(move) + "  ·  " + quality + "  ·  实机特效预览"
		var metrics := {"move":str(move), "hazard_peak":0, "bubble_pops":0, "pop_frames":[], "late_tracking_samples":0, "late_tracking_turn_samples":0, "latest_turn_age":0.0, "max_player_speed":0.0}
		var seen_pops: Array = []
		for frame_i in int(SLOT / DT):
			if frame_i == 15:
				var dir: Vector2 = (g.ppos - boss.pos).normalized()
				if not g.bai.finals.force_move(boss, str(move), dir, boss.pos.distance_to(g.ppos)):
					push_error("Preview failed to schedule " + str(move))
					get_tree().quit(3)
					return
			# A bounded continuous route changes direction after launch, including late in a bubble's life.
			var previous_player: Vector2 = g.ppos
			g.ppos = g.ppos.move_toward(path_target(frame_i * DT), 100.0 * DT)
			g.doc_pos = g.ppos + Vector2(10,35)
			metrics.max_player_speed = maxf(float(metrics.max_player_speed), g.ppos.distance_to(previous_player) / DT)
			g.t += DT
			boss.age += DT
			boss.pose = maxf(0.0, float(boss.get("pose", 0.0)) - DT)
			boss.wind = maxf(0.0, float(boss.get("wind", 0.0)) - DT)
			boss.cdt = maxf(0.0, float(boss.get("cdt", 0.0)) - DT)
			g.invuln = 999.0
			g.tele.update_warns(DT)
			var previous_hazards: Array = []
			for h in g.bai.finals.hazards:
				previous_hazards.append({"hazard":h,"velocity":h.velocity})
			g.bai.finals.update(boss, DT)
			collect_metrics(metrics, seen_pops, previous_hazards)
			g.vfx.update(DT)
			g.fx = g.fx.filter(func(f): return f.life > 0.0)
			visual_step(DT)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			if frame_i % 2 == 0:
				var result: Error = get_viewport().get_texture().get_image().save_png(out_dir.path_join("frame_%05d.png" % shot_i))
				if result != OK:
					push_error("Could not save preview frame")
					get_tree().quit(4)
					return
				shot_i += 1
		print("FX_PREVIEW_METRICS ", JSON.stringify(metrics))
		print("FX_PREVIEW_MOVE ", kind, " ", move)
	print("FX_PREVIEW_DONE boss=%s quality=%s frames=%d optical=%s" % [kind, quality, shot_i, g.optical_on])
	g.queue_free()
	await get_tree().process_frame
	get_tree().quit()

func path_target(t: float) -> Vector2:
	if t < 2.6: return Vector2(180,140)
	if t < 4.4: return Vector2(350,140)
	if t < 6.5: return Vector2(350,-80)
	if t < 8.7: return Vector2(160,-80)
	return Vector2(160,100)

func collect_metrics(metrics: Dictionary, seen_pops: Array, previous_hazards: Array) -> void:
	metrics.hazard_peak = maxi(int(metrics.hazard_peak), g.bai.finals.hazards.size())
	for f in g.fx:
		if str(f.kind) != "bubble_pop": continue
		var known := false
		for previous in seen_pops:
			if is_same(previous,f):
				known = true
				break
		if not known:
			seen_pops.append(f)
			metrics.bubble_pops += 1
			metrics.pop_frames.append(shot_i)
	for previous in previous_hazards:
		var h: Dictionary = previous.hazard
		if str(h.get("skin", "")) != "bubble" or float(h.age) < float(h.life) * 0.5: continue
		if not g.bai.finals.hazards.any(func(live): return is_same(live,h)): continue
		metrics.late_tracking_samples += 1
		var turn: float = absf(angle_difference(previous.velocity.angle(), h.velocity.angle()))
		if turn > 0.0001:
			metrics.late_tracking_turn_samples += 1
			metrics.latest_turn_age = maxf(float(metrics.latest_turn_age), float(h.age))

func fresh() -> void:
	g.ppos = Vector2(180,0)
	g.warns.clear()
	g.enemies.clear()
	g.fx.clear()
	g.ebullets.clear()
	g.bai.finals.hazards.clear()
	g.bai.token_owner = null
	boss = g.spawner.new_enemy(kind, Vector2(-120, 0))
	boss.age = 20.0
	g.enemies.append(boss)
	g.bosses = [boss]
	g.boss = boss
	g.final_boss = boss
	if kind in ["ishar", "izumik"]:
		g.bai.setup_preview_phase2(boss)
	boss.wind = 0.0
	boss.invuln = false
	boss.friendly = false
	boss.stun = 0.0
	boss.break_t = 0.0
	if kind == "ishar":
		boss.web = []
		for p in [Vector2(-130, -100), Vector2(-170, 95), Vector2(-255, 0)]:
			var eye: Dictionary = g.spawner.new_enemy("bone", p)
			g.enemies.append(eye)
			boss.web.append({"o": eye})
	for p in [Vector2(20, 180), Vector2(350, -155)]:
		g.enemies.append(g.spawner.new_enemy("bone", p))

func visual_step(dt: float) -> void:
	for op in g.squad.ops:
		op.pos = g.ppos if op.is_leader else g.ppos + Vector2(-45, 45)
		op.anim_t += dt
	g.world.update_visuals(dt)
	g.queue_redraw()
	g.fx_add.queue_redraw()
	g.fg.queue_redraw()
