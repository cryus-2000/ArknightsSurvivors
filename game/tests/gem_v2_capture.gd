extends Node
const Bal = preload("res://scripts/core/balance.gd")
var game: Node
var out := ""
var captured := false

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--gem-review-out="):
			out = arg.trim_prefix("--gem-review-out=")
	assert(not out.is_empty())
	DirAccess.make_dir_recursive_absolute(out)
	game = load("res://game.tscn").instantiate()
	add_child(game)

func _process(_dt: float) -> void:
	if captured or game.t < 480.0:
		return
	captured = true
	game.process_mode = Node.PROCESS_MODE_DISABLED
	Engine.time_scale = 0.0
	_capture.call_deferred()

func shot(name: String) -> void:
	for i in 4:
		redraw(game)
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))

func redraw(node: Node) -> void:
	if node is CanvasItem:
		node.queue_redraw()
	for child in node.get_children():
		redraw(child)

func _capture() -> void:
	var r: Dictionary = Bal.sec("render")
	var meta := {"time": game.t, "seed": 11, "gem_cap": 0, "xp": game.pickups.xp_on_ground(), "gems": game.gems.size(), "note": "Same frozen simulation state; real render switch. Shader wall time may advance."}
	r.gem_v2 = 0
	await shot("late_off")
	r.gem_v2 = 1
	await shot("late_on")
	assert(game.pickups.xp_on_ground() == float(meta.xp))
	FileAccess.open(out.path_join("capture.json"), FileAccess.WRITE).store_string(JSON.stringify(meta, "\t"))
	# Separate, labelled rendering fixture. Never presented as a natural late-game frame.
	game.gems.clear()
	game.enemies.clear()
	game.fx.clear()
	r.gem_near_r = 1.0
	var positions := []
	for row in 2:
		for i in 4:
			var p: Vector2 = game.ppos + Vector2(-120 + i * 80, -50 + row * 100)
			game.pickups.drop(p, "xp", [1.0, 2.0, 5.0, 20.0][i])
			var item: Dictionary = game.gems[-1]
			item.z = 0.0
			item.vz = 0.0
			item.mag = row == 1
			item.mag_t = 0.0
			positions.append({"value": item.val, "mag": item.mag, "screen": str(game.get_global_transform_with_canvas() * p)})
	await shot("tiers_fixture")
	FileAccess.open(out.path_join("tiers.json"), FileAccess.WRITE).store_string(JSON.stringify(positions, "\t"))
	Engine.time_scale = 1.0
	get_tree().quit()
