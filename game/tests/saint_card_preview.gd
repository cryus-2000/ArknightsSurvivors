extends "res://tests/final_boss_fx_preview.gd"
## 圣徒出招组录像（docs/171）：每组一段 SEG 秒，正式 AI 出招 / 结算 / 弹体；只把出招组固定在这一组，玩家无敌、按固定路线移动。
## 每幕第二组的段落在第一次装填读条到 0.5 秒时调用正式 saint_interrupt，演示打断 = 在飞弹幕作废 + 破绽（不模拟冲刺路线）。
## --card-check：不截图，只跑模拟并打印每段指标（出弹数、换段次数），供回归用
const SEG := 14.0
const D = preload("res://scripts/data.gd")


func _ready() -> void:
	var check_only := "--card-check" in OS.get_cmdline_user_args()
	kind = "iberia"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--boss="): kind = arg.substr(7)
		if arg.begins_with("--shotdir="): out_dir = arg.substr(10)
		if arg.begins_with("--quality="): quality = arg.substr(10)
	if (out_dir.is_empty() and not check_only) or not kind in ["iberia", "carmen"]:
		push_error("Expected --boss=iberia|carmen and --shotdir")
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
	g.rng_enemy.seed = 271030
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
	var saint = g.bai.boss(kind)
	if "--card-measure" in OS.get_cmdline_user_args():
		for ph in 2:
			for dash in [false, true]:
				_measure(saint, ph, dash)
		g.queue_free()
		await get_tree().process_frame
		get_tree().quit()
		return
	for ph in 2:
		for ci in 2:
			fresh()
			g.enemies = [boss]
			if ph == 1:
				g.bai.setup_preview_phase2(boss)
				boss.channel = 0.0
				boss.invuln = false
			saint._card_set(boss, ph, ci)
			boss.card_hold = true   # 录这一组，补弹时不换组
			boss.reload_t = 0.0      # 跳过开场 20 秒的首轮近战段，直接看稳定循环
			var card: Dictionary = saint._card(boss)
			var fired := 0
			var peak := 0
			var interrupted := false
			var reloads := 0
			var was_channel := false
			for frame_i in int(SEG / DT):
				var elapsed: float = frame_i * DT
				g.invuln = 999.0
				g.ppos = g.ppos.move_toward(path_target(fmod(elapsed, 12.0)), 100.0 * DT)
				g.doc_pos = g.ppos + Vector2(10, 35)
				g.t += DT
				if ci == 1 and not interrupted and boss.channel > 0.0 and boss.channel < float(boss.count_max) - 0.5:
					interrupted = true
					saint.saint_interrupt(boss)
				var nb: int = g.ebullets.size()
				g.enemies_sys.build_grid()
				var nfx: int = g.fx.size()
				g.enemies_sys.update(DT)
				g.vfx.mark_enemy_fx(nfx)
				fired += maxi(0, g.ebullets.size() - nb)
				g.shots.step(DT)
				g.tele.update_warns(DT)
				g.enemies_sys.update_status(DT)
				g.ebullets = g.ebullets.filter(func(b): return b.life > 0.0)
				peak = maxi(peak, g.ebullets.size())
				if boss.channel > 0.0 and not was_channel:
					reloads += 1
				was_channel = boss.channel > 0.0
				if "--card-debug" in OS.get_cmdline_user_args() and frame_i % 15 == 0:
					print("DBG t=%.1f ammo=%d ch=%.2f wind=%.2f rl=%.2f ai=%s stun=%.2f brk=%.2f cq=%s mv=%s age=%.1f" % [elapsed, boss.ammo, boss.channel, boss.wind, boss.get("reload_t", 0.0), boss.ai, boss.stun, boss.get("break_t", 0.0), str(boss.get("cq", [])), str(boss.get("move_name", "")), boss.age])
				var st: String = "装填 %.1fs" % boss.channel if boss.channel > 0.0 else ("破绽 %.1fs" % boss.break_t if boss.get("break_t", 0.0) > 0.0 else "弹药 %d" % boss.ammo)
				title.text = "%s · %s · %s · %.1fs\n%s · %s" % [D.ENEMIES[kind].name, card.name, quality, elapsed, str(boss.get("move_name", "")), st]
				g.vfx.update(DT)
				g.fx = g.fx.filter(func(f): return f.life > 0.0)
				visual_step(DT)
				await get_tree().process_frame
				if check_only:
					continue
				await RenderingServer.frame_post_draw
				if frame_i % 2 == 0:
					if get_viewport().get_texture().get_image().save_png(out_dir.path_join("frame_%05d.png" % shot_i)) != OK:
						push_error("Could not save card frame")
						get_tree().quit(4)
						return
					shot_i += 1
			print("FX_PREVIEW_METRICS ", JSON.stringify({"move": card.name, "phase": ph + 1, "bullets_fired": fired, "bullet_peak": peak, "reloads": reloads, "interrupted": interrupted}))
	print("FX_PREVIEW_DONE boss=%s quality=%s frames=%d cards=true optical=%s" % [kind, quality, shot_i, g.optical_on])
	g.queue_free()
	await get_tree().process_frame
	get_tree().quit()


## 输出窗口探针（协调人 10-27「给干员输出的机会」）：自然流程（出招组照常轮换）MEASURE 秒，玩家无敌、绕 Boss 130 处转圈（0.6 rad/s，一直在跑）。
## dash = true：每次装填读条 0.4 秒时调用正式 saint_interrupt（模拟冲刺穿身）。指标：
##   low   Boss 在近战射程（≤180）内、她 / 他的同屏敌弹 < 20、且没有未结算的伤害预警 的时间占比
##   windows  每段装填 / 破绽（channel 或 break_t > 0）时长；dense_in_window 窗口内同屏敌弹 ≥ 20 的占比
##   blocked（卡门）玩家到 Boss 的连线被火线（缺口外）挡住的时间占比
const MEASURE := 60.0


func _measure(saint, ph: int, dash: bool) -> void:
	fresh()
	g.enemies = [boss]
	if ph == 1:
		g.bai.setup_preview_phase2(boss)
		boss.channel = 0.0
		boss.invuln = false
	boss.reload_t = 0.0
	g.ppos = boss.pos + Vector2(130, 0)
	var low := 0
	var blocked := 0
	var dense_w := 0
	var win_frames := 0
	var windows: Array = []
	var cur := 0.0
	var ch_t := 0.0
	var n := int(MEASURE / DT)
	for frame_i in n:
		g.invuln = 999.0
		var th: float = frame_i * DT * 0.6
		g.ppos = g.ppos.move_toward(boss.pos + Vector2.from_angle(th) * Vector2(130, 130 * 0.72), 150.0 * DT)
		g.doc_pos = g.ppos + Vector2(10, 35)
		g.t += DT
		if boss.channel > 0.0:
			ch_t += DT
			if dash and ch_t >= 0.4:
				saint.saint_interrupt(boss)
		else:
			ch_t = 0.0
		g.enemies_sys.build_grid()
		g.enemies_sys.update(DT)
		g.shots.step(DT)
		g.tele.update_warns(DT)
		g.enemies_sys.update_status(DT)
		g.ebullets = g.ebullets.filter(func(b): return b.life > 0.0)
		g.fx.clear()
		var own := 0
		for b in g.ebullets:
			if b.get("source_id", -1) == boss.id:
				own += 1
		var threat := false
		for w in g.warns:
			if is_same(w.owner, boss) and float(w.dmg) > 0.0 and not w.done:
				threat = true
				break
		if g.ppos.distance_to(boss.pos) <= 180.0 and own < 20 and not threat:
			low += 1
		var inwin: bool = boss.channel > 0.0 or float(boss.get("break_t", 0.0)) > 0.0
		if inwin:
			cur += DT
			win_frames += 1
			if own >= 20:
				dense_w += 1
		elif cur > 0.0:
			windows.append(snappedf(cur, 0.1))
			cur = 0.0
		for fl in boss.get("fire_lines", []):
			var ab: Vector2 = fl.b - fl.a
			var hit = Geometry2D.segment_intersects_segment(g.ppos, boss.pos, fl.a, fl.b)
			if hit != null and absf((hit - fl.a).dot(ab) / ab.length_squared() - float(fl.gap_t)) * ab.length() > float(fl.gap_len) * 0.5:
				blocked += 1
				break
	if cur > 0.0:
		windows.append(snappedf(cur, 0.1))
	print("SAINT_MEASURE ", JSON.stringify({"boss": kind, "phase": ph + 1, "dash": dash, "low": snappedf(float(low) / n, 0.01),
		"windows": windows, "dense_in_window": snappedf(float(dense_w) / maxi(1, win_frames), 0.01), "blocked": snappedf(float(blocked) / n, 0.01)}))
