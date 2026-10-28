extends "res://tests/final_boss_fx_preview.gd"
## 四只最终 Boss 各进一次破绽的录像（用户 10-28「最终 Boss 的破绽字都不要」）：走公共 combat.start_break，
## 看头顶不出字、脚下金环 + 倒计时弧（render/break_ring）。--shotdir=<目录> 存帧；输出 FINAL_BREAK_DONE
const KINDS := ["paranoia", "knight_boss", "izumik", "ishar"]
const NAMES := {"paranoia": "偏执泡影", "knight_boss": "骑士", "izumik": "伊祖米克", "ishar": "伊莎玛拉"}
const BRK := 3.0


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
	var texts_seen := 0
	for k in KINDS:
		kind = k
		fresh()
		g.ppos = boss.pos + Vector2(110, 10)
		for i in int(5.0 / DT):
			var t: float = i * DT
			if i == int(1.0 / DT):
				var n0: int = g.texts.size()
				g.combat.start_break(boss, BRK)
				texts_seen += g.texts.size() - n0
			if boss.break_t > 0.0:
				boss.break_t = maxf(0.0, boss.break_t - DT)
			g.t += DT
			boss.age += DT
			title.text = "%s · %s" % [NAMES[k], ("破绽中 %.1f 秒" % boss.break_t) if boss.break_t > 0.0 else "常态"]
			visual_step(DT)
			await get_tree().process_frame
			if out_dir != "" and i % 2 == 0:
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(out_dir.path_join("frame_%05d.png" % shot_i))
				shot_i += 1
	print("FINAL_BREAK_DONE frames=%d popup_texts=%d" % [shot_i, texts_seen])
	get_tree().quit(0)
