extends Node2D
const Game = preload("res://scripts/game.gd")
const Art = preload("res://scripts/art.gd")
const Bal = preload("res://scripts/core/balance.gd")
var game
var out := ""

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--gem-review-out="):
			out = arg.trim_prefix("--gem-review-out=")
	game = Game.new()
	game.wcv = self
	game.optical_on = false
	game.tex["gem_small"] = Art.tex("gem_small")
	game.tex["gem_big"] = Art.tex("gem_big")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	queue_redraw()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("tiers_3x.png"))
	game.free()
	get_tree().quit()

func _draw() -> void:
	if game == null:
		return
	draw_rect(Rect2(0, 0, 1280, 720), Color("18212a"))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(35, 45), "XP tiers - production sprite renderer, 3x (without scene lighting)", HORIZONTAL_ALIGNMENT_LEFT, -1, 24)
	for row in 2:
		draw_string(font, Vector2(35, 130 + row * 240), "REST" if row == 0 else "NEAR / ATTRACTED", HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
		for i in 4:
			var value: float = [1.0, 2.0, 5.0, 20.0][i]
			var c: Color = game.world._gem_v2_color(value, row == 0)
			if row == 1:
				c *= Bal.v("render/gem_v2_near_k", 1.12)
				c.a = 1.0
			var pos := Vector2(230 + i * 265, 215 + row * 240)
			game.world._gem_sprites("gem_small" if i < 2 else "gem_big", 6.0, PackedVector2Array([pos]), PackedColorArray([c]))
			draw_string(font, pos + Vector2(-30, 90), str(value) + " XP", HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
