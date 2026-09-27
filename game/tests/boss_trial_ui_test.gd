extends Node
## Uses the actual menu request and scene change; leaves progress untouched.
const Menu = preload("res://scripts/screens/boss_trial_menu.gd")
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("Boss trial UI: " + message)

func _ready() -> void:
	call_deferred("run")

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless" or not Cfg.dev_args().has("--capture-ui"):
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../build/" + name + ".png")

func run() -> void:
	var menu := Menu.new()
	add_child(menu)
	menu.open()
	for dims in [Vector2(1113, 626), Vector2(800, 450), Vector2(480, 320)]:
		menu.set_anchors_preset(Control.PRESET_TOP_LEFT)
		menu.size = dims
		await get_tree().process_frame
		await get_tree().process_frame
		check(menu.panel.size.x <= dims.x - 32.0, "panel width fits " + str(dims))
		check(menu.scroll.size.x <= dims.x and menu.scroll.size.y <= dims.y, "scroll viewport fits " + str(dims))
		check(menu.action_buttons.size() == 2, "start and return always available")
		for button in menu.action_buttons:
			menu.scroll.ensure_control_visible(button)
			await get_tree().process_frame
			var hit: Rect2 = menu.scroll.get_global_rect().intersection(button.get_global_rect())
			check(hit.size.y >= button.size.y - 1.0, "action button reachable " + str(dims))
		if dims == Vector2(1113, 626):
			await capture("ea_boss_menu_touch")
		elif dims == Vector2(480, 320):
			await capture("ea_boss_menu_small")
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.boss_pick.select(menu.boss_groups.find(["ishar"]))
	var initial_phase := 1 if Cfg.dev_args().has("--ishar-human") else 2
	var operator_id := "suzuran" if initial_phase == 1 else "wisadel"
	menu.op_pick.select(menu.op_ids.find(operator_id))
	menu.phase_pick.select(initial_phase - 1)
	menu.growth_pick.select(0 if initial_phase == 1 else 2)
	menu.safe_pick.button_pressed = true
	Cfg.play_speed = 1.0
	# Keep only this test harness alive while the real menu replaces current_scene.
	get_tree().current_scene = null
	menu._start()
	await get_tree().scene_changed
	var g = get_tree().current_scene
	check(g != null and g.trial.active, "menu enters actual trial scene")
	check(Cfg.boss_trial_request.is_empty(), "request consumed exactly once")
	check(g.ch.id == operator_id and g.ch.elite == (0 if initial_phase == 1 else 2), "requested operator and growth")
	check(g.bosses.size() == 1 and g.final_boss.type == "ishar" and g.final_boss.phase == initial_phase, "requested Boss and phase")
	check(is_zero_approx(g.t - g.trial.started_at), "trial clock starts at zero")
	if initial_phase == 1:
		check(g.final_boss.friendly and g.enemies.size() >= 4, "neutral practice starts with real sea monsters")
		check(g.hud_view.hostile_boss_bars().is_empty(), "neutral practice has no hostile pointer")
	menu.queue_free()
	if DisplayServer.get_name() != "headless" and Cfg.dev_args().has("--capture-ui"):
		var waited := 0
		while g.t - g.trial.started_at < 3.0 and waited < 60:
			await get_tree().create_timer(0.2).timeout
			waited += 1
		check(not g.final_boss.dead, "Boss alive for actual battle preview")
		# Capture between genuine hit flashes so the transformed body is visible.
		for frame in 120:
			if g.final_boss.flash <= 0.0:
				break
			await get_tree().process_frame
		g.set_process(false)
		g.queue_redraw()
		await capture("ea_boss_trial_ishar_human" if initial_phase == 1 else "ea_boss_trial_wisadel_ishar")
	g.set_process(false)
	g.queue_free()
	await get_tree().process_frame
	Sfx.set_process(false)
	await get_tree().create_timer(0.25, true, false, true).timeout
	for player in Sfx.get_children():
		if player is AudioStreamPlayer:
			player.stop()
			player.stream = null
			player.queue_free()
	await get_tree().create_timer(0.2, true, false, true).timeout
	print("Boss trial UI regression: %d failures" % failures)
	get_tree().quit(1 if failures else 0)
