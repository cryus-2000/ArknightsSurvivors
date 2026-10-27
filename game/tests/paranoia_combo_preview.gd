extends "res://tests/final_boss_fx_preview.gd"
## 偏执泡影连携攻势录像（docs/170）：每组连段一段，从该组起手，其后全部走正式 AI / 弹幕 / 预警管线（组间按正式轮换）；玩家无敌、沿固定路线一直移动。
## --pc-check：只跑模拟不截图（回归用）。输出 FX_PREVIEW_METRICS（每段事件）与 FX_PREVIEW_DONE
const SEG_SECONDS := 16.0
const Bal = preload("res://scripts/core/balance.gd")
var skin_ab := false


func _ready() -> void:
	var check_only := "--pc-check" in OS.get_cmdline_user_args()
	skin_ab = "--skin-ab" in OS.get_cmdline_user_args()
	kind = "paranoia"
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
	for i in 6:
		visual_step(DT)
		await get_tree().process_frame
		if not check_only: await RenderingServer.frame_post_draw
	var Combos = load("res://scripts/enemies/bosses/paranoia_combos.gd")
	var scenarios: Array = []
	for a in Combos.ACT_COMBOS.size():
		for i in (Combos.ACT_COMBOS[a] as Array).size():
			if a == 3 and i == 1:
				continue   # 破茧后第二张与落地幕相同
			scenarios.append({"act": a, "idx": i, "name": Combos.ACT_COMBOS[a][i]})
	var hs = g.bai.boss(kind)
	for sc in scenarios:
		fresh()
		g.enemies = [boss]
		if sc.act == 1:
			boss.gates_passed = 1
			if not boss.get("gates", []).is_empty():
				boss.gates.pop_front()
		elif sc.act >= 2:
			g.bai.setup_preview_phase2(boss)
			if sc.act == 3:
				boss.cocoon_done = true
		boss.wind = 0.0
		hs.combos().start_act(boss, int(sc.act))
		boss.pc_idx = int(sc.idx)
		var events: Array = []
		var watched: Array = []
		var peak := 0
		var hits := 0
		var segs: Array = []
		var last_seg := ""
		var frame_ms: Array = []
		var t_prev: int = Time.get_ticks_usec()
		var ab_ms: Array = [[], []]
		var sim_ms: Array = []
		var live := 0
		for frame_i in int(SEG_SECONDS / DT):
			var elapsed: float = frame_i * DT
			if skin_ab:
				Bal.sec("render")["paranoia_bubble_skin"] = float(frame_i % 2)   # 同局逐帧轮换泡膜开 / 关
			g.invuln = 999.0
			g.ppos = g.ppos.move_toward(path_target(fmod(elapsed, 12.0)), 120.0 * DT)
			g.doc_pos = g.ppos + Vector2(10, 35)
			g.t += DT
			var t_sim0: int = Time.get_ticks_usec()
			g.enemies_sys.build_grid()
			var nfx: int = g.fx.size()
			g.enemies_sys.update(DT)
			g.vfx.mark_enemy_fx(nfx)
			g.shots.step(DT)
			g.tele.update_warns(DT)
			g.enemies_sys.update_status(DT)
			if live >= 0:
				sim_ms.append(float(Time.get_ticks_usec() - t_sim0) / 1000.0)
			for w in g.warns:
				if not is_same(w.owner, boss) or w.dmg <= 0.0 or watched.any(func(o): return is_same(o, w)):
					continue
				watched.append(w)
				events.append({"event": "warning", "name": str(w.name), "act": str(w.act), "t": snappedf(elapsed, 0.01)})
			var mv: String = str(boss.get("move_name", ""))
			if mv != last_seg:
				last_seg = mv
				segs.append([snappedf(elapsed, 0.01), mv])
			live = (boss.get("pc_buls", []) as Array).size()
			peak = maxi(peak, live)
			# 无敌玩家：数一下实弹贴身次数（只作密度参考，不代表难度）
			for b in boss.get("pc_buls", []):
				if b.life > 0.0 and b.pos.distance_to(g.ppos + Vector2(0, -14)) < b.r + 12.0:
					hits += 1
			title.text = "%s · 第%d幕 · %.1fs\n%s · 弹 %d" % [sc.name, int(sc.act) + 1, elapsed, mv, live]
			g.vfx.update(DT)
			g.fx = g.fx.filter(func(f): return f.life > 0.0)
			visual_step(DT)
			await get_tree().process_frame
			if not check_only: await RenderingServer.frame_post_draw
			var t_now: int = Time.get_ticks_usec()
			frame_ms.append([float(t_now - t_prev) / 1000.0, live])
			if skin_ab and live >= 60 and frame_i > 5:
				ab_ms[frame_i % 2].append(float(t_now - t_prev) / 1000.0)
			t_prev = t_now
			if frame_i % 2 == 0:
				if not check_only:
					var result: Error = get_viewport().get_texture().get_image().save_png(out_dir.path_join("frame_%05d.png" % shot_i))
					if result != OK:
						push_error("Could not save combo frame")
						get_tree().quit(4)
						return
				shot_i += 1
		# 帧时（本机墙钟，含模拟 + 绘制提交；不截图时才有意义）：全段均值、p95、弹数 ≥ 60 时的均值
		var all_ms: Array = frame_ms.slice(5).map(func(x): return x[0])
		all_ms.sort()
		var busy: Array = frame_ms.filter(func(x): return x[1] >= 60).map(func(x): return x[0])
		var avg := func(arr: Array) -> float: return 0.0 if arr.is_empty() else arr.reduce(func(a2, b2): return a2 + b2, 0.0) / arr.size()
		var ab := {"skin_on_busy": snappedf(avg.call(ab_ms[1]), 0.01), "skin_off_busy": snappedf(avg.call(ab_ms[0]), 0.01)} if skin_ab else {}
		var timing := {"ab": ab, "sim_ms_avg": snappedf(avg.call(sim_ms), 0.01), "ms_avg": snappedf(avg.call(all_ms), 0.01), "ms_p95": snappedf(all_ms[int(all_ms.size() * 0.95)] if not all_ms.is_empty() else 0.0, 0.01), "ms_busy_avg": snappedf(avg.call(busy), 0.01), "busy_frames": busy.size()}
		print("FX_PREVIEW_METRICS ", JSON.stringify({"timing": timing, "combo": sc.name, "act": sc.act, "segments": segs, "bullet_peak": peak, "contact_frames": hits, "events": events}))
	print("FX_PREVIEW_DONE boss=%s quality=%s frames=%d combos=%d optical=%s" % [kind, quality, shot_i, scenarios.size(), g.optical_on])
	g.queue_free()
	await get_tree().process_frame
	get_tree().quit()
