extends "res://tests/final_boss_fx_preview.gd"
## 偏执泡影卡点泡膜硬化录像（10-28 防速杀，docs/170 §3w）：一阶段、二阶段各停在刻度上 4 秒，看硬化多面壳 + 剩余时间弧。
## --shotdir=<目录> 存帧；输出 HOLD_DONE
const HOLD := 4.0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shotdir="): out_dir = arg.substr(10)
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
	g.zone_r = 650.0
	g.zone_next_r = 650.0
	g.invuln = 999.0
	g.rng.seed = 281028
	g.vrng.seed = 281029
	var overlay := CanvasLayer.new()
	overlay.layer = 120
	add_child(overlay)
	title = Label.new()
	title.position = Vector2(22, 14)
	title.add_theme_font_override("font", load("res://fonts/ui.ttf"))
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_shadow_color", Color.BLACK)
	overlay.add_child(title)
	for ph in [1, 2]:
		kind = "paranoia"
		fresh()
		if ph == 2:
			g.bai.boss("paranoia")._paranoia_p2(boss)
		g.ppos = boss.pos + Vector2(130, 10)
		for i in int((HOLD + 1.5) / DT):
			if i == int(0.5 / DT):
				boss.gate_hold = true
				boss.act_min = HOLD
				boss.act_t = 0.0
			if boss.get("gate_hold", false):
				boss.act_t += DT
				if boss.act_t >= boss.act_min:
					boss.gate_hold = false
			g.t += DT
			boss.age += DT
			title.text = "偏执泡影 · %s阶段 · %s" % ["一" if ph == 1 else "二", ("泡膜硬化 还剩 %.1f 秒" % (boss.act_min - boss.act_t)) if boss.get("gate_hold", false) else "常态"]
			visual_step(DT)
			await get_tree().process_frame
			if out_dir != "":
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(out_dir.path_join("frame_%05d.png" % shot_i))
				shot_i += 1
	print("HOLD_DONE frames=%d" % shot_i)
	get_tree().quit(0)
