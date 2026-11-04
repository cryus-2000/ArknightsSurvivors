extends Node
## Screenshot-only frozen-state probe, launched with --balance by the shared runner.
const Bal = preload("res://scripts/core/balance.gd")
const MinionWarn = preload("res://scripts/render/minion_warn.gd")
const TeleDraw = preload("res://scripts/render/telegraph_draw.gd")
var game
var busy := false
var out := ""

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--warn-shot-dir="):
			out = arg.substr(16)
	assert(not out.is_empty())
	DirAccess.make_dir_recursive_absolute(out)
	game = load("res://game.tscn").instantiate()
	add_child(game)

func _process(_dt: float) -> void:
	if busy or game.t < 480.0:
		return
	var count := 0
	for w in game.warns:
		if MinionWarn.owns(w) and not w.done and not TeleDraw.quiet(w) and not w.get("dim", false) and game.world.view_rect(0.0).has_point(w.pos):
			count += 1
	if count == 0:
		return
	busy = true
	capture(count)

func redraw(node: Node) -> void:
	if node is CanvasItem:
		node.queue_redraw()
	for child in node.get_children():
		redraw(child)

func snap(name: String) -> void:
	redraw(game)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))

func capture(count: int) -> void:
	game.process_mode = Node.PROCESS_MODE_DISABLED
	Engine.time_scale = 0.0
	var report := {"time": game.t, "ordinary_warnings": count, "seed": 11, "warnings": []}
	for w in game.warns:
		report.warnings.append({"act": w.act, "shape": w.shape, "elite": w.owner.get("elite", false), "boss": w.owner.get("boss", false), "squad": w.owner.get("squad", false), "cross_elite": w.owner.get("cross_elite", false), "remaining": w.dur-w.t, "done": w.done})
	for enabled in [0, 1]:
		Bal.sec("render").warn_v2 = enabled
		Bal.clear_cache()
		game.world._dbg_friend = false
		game.world._dbg_foe = false
		game.world._dbg_warn = false
		await snap("warn_%d_full" % enabled)
		game.world._dbg_friend = true
		await snap("warn_%d_nofriend" % enabled)
		game.world._dbg_foe = true
		game.world._dbg_warn = true
		await snap("warn_%d_nofriend_nofoe" % enabled)
	var f := FileAccess.open(out.path_join("capture.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	print("WARN_V2_CAPTURE ", JSON.stringify(report))
	get_tree().quit()
