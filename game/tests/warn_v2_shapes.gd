extends Node2D
## Controlled fixture using production warning draws; not a simulated late-game screenshot.
const Game = preload("res://scripts/game.gd")
const Bal = preload("res://scripts/core/balance.gd")
const TeleDraw = preload("res://scripts/render/telegraph_draw.gd")
var game
var enabled := 0
var out := ""
var motion := false
var sample := 0

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--warn-motion":
			motion = true
		if arg.begins_with("--warn-shot-dir="):
			out = arg.substr(16)
	assert(not out.is_empty())
	DirAccess.make_dir_recursive_absolute(out)
	game = Game.new()
	game.wcv = self
	game.optical = preload("res://scripts/render/optical.gd").new()
	game.optical_on = true
	game.optical.fx1 = true
	for setting in [0, 1]:
		enabled = setting
		Bal.sec("render").warn_v2 = setting
		Bal.clear_cache()
		queue_redraw()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("shapes_%d.png" % setting))
	if motion:
		for frame in 90:
			sample = frame
			queue_redraw()
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out.path_join("motion_%03d.png" % frame))
	game.optical.free()
	game.free()
	get_tree().quit()

func _draw() -> void:
	if game == null:
		return
	draw_rect(Rect2(0, 0, 1280, 720), Color("17232c"))
	for row in 12:
		for col in 20:
			if (row + col) % 2 == 0:
				draw_rect(Rect2(col * 64, row * 64, 64, 64), Color("273944"))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(20, 28), ("CONTROLLED production draws | top: single | bottom: overlapping, staggered timing | elite unchanged" if motion else "Production warning fixture | render/warn_v2=%d | early / final 0.1 s | elite unchanged" % enabled), HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color.WHITE)
	for row in 2:
		for col in 4:
			var shape: String = ["line", "cone", "circle", "cone"][col]
			var pos := Vector2(col * 320 + (70 if shape in ["line", "cone"] else 160), row * 310 + 210)
			game.ppos = pos + Vector2(0, 100)
			game.t = 20.0
			var owner := {"type": "tracer", "elite": col == 3, "boss": false}
			game.warns = [{"owner": owner, "shape": shape, "pos": pos, "ang": -0.2, "r": 165.0 if shape == "cone" else 100.0,
				"half": 0.65, "len": 185.0, "wid": 24.0, "style": 2 if shape == "line" else (3 if shape == "cone" else 1),
				"t": 0.3 if row == 0 else 0.9, "dur": 1.0, "done": false, "act": "stab" if shape == "line" else "bite", "col": Color(1, 0.35, 0.45)}]
			if motion:
				game.warns[0].dur = 1.5
				game.warns[0].t = float(sample % 45) / 30.0
				if row == 1:
					var second: Dictionary = game.warns[0].duplicate(true)
					second.pos += Vector2(38, -25)
					second.t = float((sample + 12) % 45) / 30.0
					game.warns.append(second)
			# Bright and dark patches behind the boundary expose weak contrast.
			draw_rect(Rect2(pos + Vector2(20, -55), Vector2(130, 30)), Color("a5a59b"))
			draw_rect(Rect2(pos + Vector2(40, 30), Vector2(110, 25)), Color("080d15"))
			TeleDraw.draw_fills(game)
			game.world.draw_warn_outlines()
			draw_string(font, Vector2(col * 320 + 18, row * 310 + 82), ("ELITE " if col == 3 else "MINION ") + shape + (" | %.2f s left" % (1.5 - float(sample % 45) / 30.0) if motion else (" | 0.7 s left" if row == 0 else " | 0.1 s left")), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
