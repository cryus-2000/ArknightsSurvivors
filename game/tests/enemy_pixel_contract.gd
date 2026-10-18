extends Node
const A = preload("res://scripts/art.gd")
const D = preload("res://scripts/data.gd")

func _ready() -> void:
	A.enemy_pixel_spec("")
	var failed := 0
	if A.enemy_pixels.is_empty():
		push_error("Enemy pixel metadata is empty")
		failed += 1
	for name in A.enemy_pixels:
		var spec: Dictionary = A.enemy_pixels[name]
		var image := Image.load_from_file(A.incoming_dir().path_join(name + "@2x.png"))
		var size: Array = spec.frame_size
		if image == null or image.get_width() != int(size[0]) * int(spec.frames) or image.get_height() != int(size[1]):
			push_error("Enemy frame dimensions: " + name)
			failed += 1
		var anchor := A.enemy_pixel_anchor(name, Vector2.ZERO)
		if not anchor.is_finite() or anchor.x < 0 or anchor.x > 1 or anchor.y < 0 or anchor.y > 1:
			push_error("Enemy anchor outside canvas: " + name)
			failed += 1
		var scale := A.enemy_pixel_scale(name)
		if not is_finite(scale) or scale <= 0 or A.enemy_pixel_scale(name + "_white") != scale:
			push_error("Enemy silhouette/scale contract: " + name)
			failed += 1
		if A.enemy_pixel_anchor(name + "_white", Vector2.ZERO) != anchor or A.pop_wanted(name):
			push_error("Enemy silhouette/palette contract: " + name)
			failed += 1
	if A.enemy_pixel_anchor("unregistered", Vector2(0.5, 1)) != Vector2(0.5, 1) or A.enemy_pixel_scale("unregistered") != 1.0:
		failed += 1
	# Approved size trial: per-type draw_scale keeps shared knight textures independent.
	var expected := {"bone": 1.25, "slider": 1.25, "stone": 1.2, "offspring": 1.2, "brood": 1.25, "spitter": 1.3455, "runner": 1.25, "floater": 1.2, "reaper": 1.15, "founder": 1.12, "tracer": 1.12, "nest": 1.12, "fractal": 1.2, "tear": 1.2, "pocket": 1.2, "skimmer": 1.2, "mother": 1.15, "mimic": 1.2, "path": 1.15, "izumik": 1.12, "iberia": 1, "carmen": 1, "bishop": 1, "archon": 1, "immortal": 1, "paranoia": 1.15, "ishar": 0.68, "knight": 0.945, "knight_boss": 0.98}
	for id in expected:
		if not is_equal_approx(float(D.ENEMIES[id].get("draw_scale", 1.0)), float(expected[id])):
			printerr("FAIL: Enemy approved size: ", id)
			failed += 1
	print("ENEMY PIXEL CONTRACT: ", A.enemy_pixels.size(), " strips; failures=", failed)
	# The autoload starts menu audio even in silent tests; release playback before exit.
	await get_tree().create_timer(0.1).timeout
	Sfx.set_process(false)
	for player in Sfx.get_children():
		if player is AudioStreamPlayer:
			player.stop()
			player.stream = null
			player.queue_free()
	await get_tree().create_timer(0.1).timeout
	get_tree().quit(1 if failed else 0)
