extends "res://tests/final_boss_fx_preview.gd"
## 伊祖米克连携实机录制（docs/170）：每段只强制一次起手组，之后全部走正式 AI、子代批次、弹幕与预警；玩家无敌、以 105px/s 绕行。
const SEG := 16.0
var only: Array = []   # 只录这几组（从 0 起）
var shock := false     # --shock：只录一段「震撼」，结算前 0.15 秒冲刺躲开（用户 10-28：1.5 倍速下来不来得及）

func _ready() -> void:
	kind = "izumik"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shotdir="): out_dir = arg.substr(10)
		if arg.begins_with("--quality="): quality = arg.substr(10)
		if arg.begins_with("--only="): only = Array(arg.substr(7).split(",")).map(func(x): return int(x))
		if arg == "--shock": shock = true
	if out_dir.is_empty():
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
	g.t = 100.0
	g.zone_frozen = true
	g.zone_state = 3
	g.zone_c = Vector2.ZERO
	g.zone_next_c = Vector2.ZERO
	g.zone_r = 650.0
	g.zone_next_r = 650.0
	g.invuln = 999.0
	g.rng.seed = 271027
	g.rng_enemy.seed = 271027
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
	var script = g.bai.boss(kind)
	if shock:
		await _shock_clip(script)
		names_done()
		return
	var names: Array = script.card_names()
	for si in names.size():
		if not only.is_empty() and not only.has(si):
			continue
		var act: int = si / 2
		fresh()
		g.enemies = [boss]
		boss.pos = Vector2.ZERO
		boss.lamps = []
		boss.batch_next = g.t + 0.5   # 第一批子代在起手前到场，看拦截通道
		if act > 0:
			boss.gates_passed = act
			script.on_gate(boss)
		boss.hp = boss.maxhp * [0.8, 0.55, 0.3][act]
		boss.shock_i = act   # 震撼另录，不在本段插队
		boss.izu_next = g.t + 2.0
		var metrics := {"combo": names[si], "act": act, "bullet_peak": 0, "events": []}
		var seen: Array = []
		var last_brk := 0.0
		for frame_i in int(SEG / DT):
			var elapsed: float = frame_i * DT
			g.invuln = 999.0
			g.ppos = Vector2.from_angle(PI * 0.15 + elapsed * 105.0 / 260.0) * Vector2(260.0, 220.0)
			g.doc_pos = g.ppos + Vector2(10, 35)
			g.t += DT
			if frame_i == 30:
				script.force_move(boss, names[si], (g.ppos - boss.pos).normalized(), boss.pos.distance_to(g.ppos))
			g.enemies_sys.build_grid()
			var nfx: int = g.fx.size()
			g.enemies_sys.update(DT)
			g.vfx.mark_enemy_fx(nfx)
			g.shots.step(DT)
			g.tele.update_warns(DT)
			g.enemies_sys.update_status(DT)
			for w in g.warns:
				if is_same(w.owner, boss) and w.name != "" and not seen.any(func(o): return is_same(o, w)):
					seen.append(w)
					metrics.events.append({"t": snappedf(elapsed, 0.01), "warn": str(w.name)})
			var em: Dictionary = boss.get("izu_emit", {})
			if not em.is_empty() and float(em.t0) == g.t:
				metrics.events.append({"t": snappedf(elapsed, 0.01), "bullets": str(em.kind)})
			var brk: float = float(boss.get("break_t", 0.0))
			if brk > last_brk + 0.1:
				metrics.events.append({"t": snappedf(elapsed, 0.01), "recovery": brk})
			last_brk = brk
			metrics.bullet_peak = maxi(int(metrics.bullet_peak), g.ebullets.filter(func(b): return b.life > 0.0).size())
			var status: String = ("收招 %.1fs" % brk) if brk > 0.0 else str(boss.get("move_name", ""))
			title.text = "伊祖米克 · %s · 第%s幕 · %s · %.1fs\n%s" % [names[si], ["一", "二", "三"][act], quality, elapsed, status]
			g.vfx.update(DT)
			g.fx = g.fx.filter(func(f): return f.life > 0.0)
			g.ebullets = g.ebullets.filter(func(b): return b.life > 0.0)
			visual_step(DT)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			if frame_i % 2 == 0:
				if get_viewport().get_texture().get_image().save_png(out_dir.path_join("frame_%05d.png" % shot_i)) != OK:
					push_error("Could not save frame")
					get_tree().quit(4)
					return
				shot_i += 1
		print("FX_PREVIEW_METRICS ", JSON.stringify(metrics))
	names_done()


func names_done() -> void:
	print("FX_PREVIEW_DONE boss=izumik quality=%s frames=%d optical=%s" % [quality, shot_i, g.optical_on])
	g.queue_free()
	await get_tree().process_frame
	get_tree().quit()


## 震撼：起手后绕行，结算前 0.15 秒（游戏时间）冲刺，冲刺期间无敌；不冲刺的话会吃满。标题显示剩余时间（游戏秒 / 1.5 倍速下真实秒）
func _shock_clip(script) -> void:
	fresh()
	g.enemies = [boss]
	boss.pos = Vector2.ZERO
	boss.lamps = []
	boss.batch_next = INF
	boss.hp = boss.maxhp * 0.8
	boss.shock_i = 3
	boss.izu_next = INF
	var dash_left := 0.0
	var dash_dir := Vector2.ZERO
	var hp0: float = g.hp
	for frame_i in int(7.0 / DT):
		var elapsed: float = frame_i * DT
		g.invuln = 0.0
		if dash_left > 0.0:
			dash_left -= DT
			g.invuln = 1.0
			g.ppos += dash_dir * g.dash_dist() / g.DASH_TIME * DT
		else:
			g.ppos = Vector2.from_angle(PI * 0.15 + elapsed * 105.0 / 260.0) * Vector2(260.0, 220.0)
		g.doc_pos = g.ppos + Vector2(10, 35)
		g.t += DT
		if frame_i == 20:
			script.force_move(boss, "震撼", (g.ppos - boss.pos).normalized(), boss.pos.distance_to(g.ppos))
			boss.izu_next = INF
		var left := -1.0
		for w in g.warns:
			if is_same(w.owner, boss) and str(w.get("act", "")) == "izu_wave" and not w.done:
				left = float(w.dur) - float(w.t)
		if left > 0.0 and left <= 0.15 and dash_left <= 0.0 and g.dash_t <= 0.0:
			dash_dir = Vector2.from_angle(PI * 0.15 + elapsed * 105.0 / 260.0 + PI * 0.5)
			dash_left = g.DASH_TIME
			g.dash_t = g.DASH_TIME
			g.fx.append({"kind": "ring", "pos": g.ppos, "r": 36.0, "life": 0.25, "max": 0.25, "col": Color(0.4, 0.9, 1.0)})
		g.dash_t = maxf(0.0, g.dash_t - DT)
		g.enemies_sys.build_grid()
		var nfx: int = g.fx.size()
		g.enemies_sys.update(DT)
		g.vfx.mark_enemy_fx(nfx)
		g.shots.step(DT)
		g.tele.update_warns(DT)
		g.enemies_sys.update_status(DT)
		var tag: String = ("震撼 预警剩余 %.2f 秒（1.5 倍速下真实 %.2f 秒）" % [left, left / 1.5]) if left > 0.0 else ("冲刺！" if dash_left > 0.0 else "")
		title.text = "伊祖米克 · 震撼 · 生命 %d / %d
%s" % [int(g.hp), int(hp0), tag]
		g.vfx.update(DT)
		g.fx = g.fx.filter(func(f): return f.life > 0.0)
		g.ebullets = g.ebullets.filter(func(b): return b.life > 0.0)
		visual_step(DT)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		if frame_i % 2 == 0 and get_viewport().get_texture().get_image().save_png(out_dir.path_join("frame_%05d.png" % shot_i)) == OK:
			shot_i += 1
	print("FX_PREVIEW_METRICS ", JSON.stringify({"combo": "震撼", "act": 1, "bullet_peak": 0, "events": [], "hp_lost": hp0 - g.hp}))
