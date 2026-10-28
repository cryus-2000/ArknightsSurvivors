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
		var src: String = A._incoming_path(name + "@2x")   # 已进 game/art 索引的图走导入贴图（docs/189 §6.1）
		var image: Image = Image.load_from_file(src) if src != "" else null
		if image == null and A._packed_path(name + "@2x") != "":
			image = (load(A._packed_path(name + "@2x")) as Texture2D).get_image()
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
	# Regular enemies and elites restored; Boss size trial retained.
	var expected := {"bone": 1.0, "slider": 1.0, "stone": 1.0, "offspring": 1.0, "brood": 1.0, "spitter": 1.0, "runner": 1.0, "floater": 1.0, "reaper": 1.0, "founder": 1.0, "tracer": 1.0, "nest": 1.0, "fractal": 1.0, "tear": 1.0, "pocket": 1.0, "skimmer": 1.0, "mother": 1.0, "mimic": 1.0, "path": 1.0, "izumik": 1.0, "iberia": 1, "carmen": 1, "bishop": 1, "archon": 1, "immortal": 1, "paranoia": 1.0, "ishar": 1.0, "knight": 1.0, "knight_boss": 1.0}   # 10-23 重画：美术按目标尺寸直接画，全部 1:1 显示
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
