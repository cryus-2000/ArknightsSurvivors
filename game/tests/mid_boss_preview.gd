extends Node
## 塑路者 / 接潮组实机录像（docs/170）：每段一个幕，正式 enemies_sys.update + Boss AI + 弹幕 / 预警 / 状态，不强制出招；
## 队长无敌、绕圈跑（不是难度验收）。tools/probes/mid_boss_preview.py 调，帧写 --shotdir；--check 只跑模拟不截图
var g
var out_dir := ""
var shot_i := 0
var title: Label
const DT := 1.0 / 30.0
const SEG := 18.0
const SEGMENTS := [
	{"name": "塑路者 · 一幕 纠错", "boss": "path", "p2": false},
	{"name": "塑路者 · 二幕 订正", "boss": "path", "p2": true},
	{"name": "接潮主教 + 蔑死体 · 一幕", "boss": "bishop", "mate": "archon", "p2": false},
	{"name": "接潮主教 + 蔑死体 · 二幕 统一", "boss": "bishop", "mate": "archon", "p2": true},
	{"name": "接潮主教 + 斥亡体 · 二幕 统一", "boss": "bishop", "mate": "immortal", "p2": true},
]


func _ready() -> void:
	var check_only := "--check" in OS.get_cmdline_user_args()
	var quality := "high"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shotdir="): out_dir = arg.substr(10)
		if arg.begins_with("--quality="): quality = arg.substr(10)
	if out_dir.is_empty() and not check_only:
		push_error("Expected --shotdir")
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
	g.zone_frozen = true
	g.zone_state = 3
	g.zone_c = Vector2.ZERO
	g.zone_next_c = Vector2.ZERO
	g.zone_r = 650.0
	g.zone_next_r = 650.0
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
	for seg in SEGMENTS:
		setup(seg)
		var events := {}
		for frame_i in int(SEG / DT):
			var el: float = frame_i * DT
			g.t += DT
			g.invuln = 999.0
			var a: float = el * 110.0 / 190.0
			var c: Vector2 = Vector2(0, 0)
			g.ppos = c + Vector2(cos(a), sin(a) * 0.75) * 190.0
			g.doc_pos = g.ppos + Vector2(10, 35)
			g.enemies_sys.build_grid()
			var nfx: int = g.fx.size()
			g.enemies_sys.update(DT)
			g.vfx.mark_enemy_fx(nfx)
			g.shots.step(DT)
			g.tele.update_warns(DT)
			g.enemies_sys.update_status(DT)
			var mv := ""
			for e in g.bosses:
				if g.t - float(e.get("move_t", -9.0)) < 1.6 and str(e.get("move_name", "")) != "":
					mv = str(e.move_name)
					events[mv] = int(events.get(mv, 0)) + (1 if g.t - float(e.move_t) < DT * 0.5 else 0)
			var brk := ""
			for e in g.bosses:
				if float(e.get("break_t", 0.0)) > 0.0:
					brk = " · 破绽 %.1fs" % float(e.break_t)
			title.text = "%s · %s · %.1fs\n%s%s" % [seg.name, quality, el, mv, brk]
			g.vfx.update(DT)
			g.fx = g.fx.filter(func(f): return f.life > 0.0)
			visual_step(DT)
			await get_tree().process_frame
			if not check_only:
				await RenderingServer.frame_post_draw
				if frame_i % 2 == 0:
					if get_viewport().get_texture().get_image().save_png(out_dir.path_join("frame_%05d.png" % shot_i)) != OK:
						push_error("Could not save frame")
						get_tree().quit(4)
						return
					shot_i += 1
		print("MID_PREVIEW_METRICS ", JSON.stringify({"segment": seg.name, "moves": events}))
	print("MID_PREVIEW_DONE frames=%d" % shot_i)
	g.queue_free()
	await get_tree().process_frame
	get_tree().quit()


func setup(seg: Dictionary) -> void:
	g.t = 100.0
	g.warns.clear()
	g.enemies.clear()
	g.fx.clear()
	g.ebullets.clear()
	g.shocks.clear()
	g.lobs.clear()
	g.bai.token_owner = null
	g.rng.seed = 271027
	g.rng_enemy.seed = 271030
	g.vrng.seed = 271028
	seed(271029)
	g.ppos = Vector2(190, 0)
	var e: Dictionary = g.spawner.new_enemy(seg.boss, Vector2(-160, 0) if seg.has("mate") else Vector2(-40, 0))
	_ready_boss(e)
	g.bosses = [e]
	if seg.has("mate"):
		var m: Dictionary = g.spawner.new_enemy(seg.mate, Vector2(200, -40))
		_ready_boss(m)
		e.partner = m
		m.partner = e
		g.bosses.append(m)
	if seg.p2:
		g.bai.setup_preview_phase2(e)
		e.gates = []
	g.boss = e


func _ready_boss(e: Dictionary) -> void:
	e.age = 3.0
	e.invuln = false
	e.wind = 0.0
	e.friendly = false
	g.enemies.append(e)


func visual_step(dt: float) -> void:
	for op in g.squad.ops:
		op.pos = g.ppos if op.is_leader else g.ppos + Vector2(-45, 45)
		op.anim_t += dt
	g.world.update_visuals(dt)
	g.queue_redraw()
	g.fx_add.queue_redraw()
	g.fg.queue_redraw()
