extends Node
const Hud = preload("res://scripts/screens/hud.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var font := SystemFont.new()
	var ci := Node2D.new()
	var body := Rect2(280, 200, 40, 65)
	var rows: Array = [
		[Vector2(240, 238), "123", 22, Color.WHITE],
		[Vector2(241, 238), "456", 22, Color.WHITE],
		[Vector2(450, 170), "弱点 42", 18, Color.GOLD],
		[Vector2(480, 320), "+24", 16, Color.GREEN],
		[Vector2(80, 320), "-33", 16, Color.RED],
		[Vector2(280, 320), "眩晕", 16, Color.WHITE]]
	var original: Array = rows.duplicate(true)
	var result: Array = Hud.clear_damage_text(rows, body, Vector2(800, 600), font, ci, 12)
	assert(rows == original, "drawing must not mutate damage text state")
	assert(result.size() == 5, "coincident damage must not overlap")
	for label in ["+24", "-33", "眩晕"]:
		assert(result.any(func(r): return r[1] == label), "critical feedback lost")
	var damage_boxes: Array[Rect2] = []
	for row in result:
		if not Hud._damage_label(row[1]):
			continue
		var w: float = font.get_string_size(row[1], HORIZONTAL_ALIGNMENT_LEFT, -1, row[2]).x
		var box := Rect2(row[0].x + (Hud.FT_BOX - w) * 0.5 - 5, row[0].y - font.get_ascent(row[2]) - 5, w + 10, font.get_height(row[2]) + 10)
		assert(not box.intersects(body), "damage still covers leader")
		assert(Rect2(Vector2.ZERO, Vector2(800, 600)).encloses(box), "text moved off screen")
		for other in damage_boxes:
			assert(not box.intersects(other), "damage labels overlap")
		damage_boxes.append(box)
	var capped: Array = Hud.clear_damage_text(rows, body, Vector2(800, 600), font, ci, 1)
	assert(capped.size() == 4, "cap must spare heal, hurt and status")
	ci.free()
	print("CLARITY_TEXT_PASS: body avoidance, collision, cap, critical feedback, no mutation")
	get_tree().quit(0)
