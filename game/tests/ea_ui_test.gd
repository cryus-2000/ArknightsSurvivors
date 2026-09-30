extends Node
## EA 标题回归：封面与开局分离、页面锁、真实属性、主控 / 队友手动技能提示。
const Title = preload("res://scripts/title.gd")
const Character = preload("res://scripts/characters/character.gd")
const InitialStats = preload("res://scripts/screens/initial_stats.gd")
var failures := 0
var title: Control

func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("EA UI: " + what)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	Cfg.character_id = "mizuki"
	Cfg.cover_character_id = "mizuki"
	title = load("res://main.tscn").instantiate()
	add_child(title)
	await get_tree().process_frame
	check(title.size == get_viewport().get_visible_rect().size, "title fills viewport")
	check(title.transition.size == title.size, "transition covers full viewport")
	title._open_op_pick(true)
	for i in title.op_defs.size():
		if title.op_defs[i].id == "siege":
			title.op_sel = i
	title._op_go()
	check(title.transition.busy, "confirm locks input")
	title._activate(0)
	await wait_for(func(): return not title.transition.busy and not title.op_pick and not title.diff_pick)
	check(Cfg.cover_character_id == "siege", "cover selection persisted in config")
	check(Cfg.character_id == "mizuki", "cover does not change opening operator")
	check(title.title_bg.guest.get("id", "") == "siege", "cover refreshes correct idle strip")
	check(not title.op_pick and not title.diff_pick, "cover confirm returns to title")
	check(not title.transition.busy, "transition unlocks")
	await capture("ea_cover_siege")
	title._activate(0)
	await wait_for(func(): return title.op_pick and not title.transition.busy)
	check(title.op_pick and not title.cover_pick, "deploy opens run selection")
	await capture("ea_operator_stats")
	title._op_go()
	await wait_for(func(): return title.diff_pick and not title.transition.busy)
	check(title.diff_pick and not title.op_pick, "run selection opens difficulty")
	title._diff_back()
	await wait_for(func(): return title.op_pick and not title.transition.busy)
	check(title.op_pick, "difficulty returns to operator selection")
	title.op_pick = false
	title._activate(2)
	await wait_for(func(): return title.boss_trial.visible and not title.transition.busy)
	check(title.boss_trial.visible, "Boss trial entry opens")
	title.boss_trial.close()
	for cid in Character.list_ids():
		var d: Dictionary = Character.load_def(cid)
		if not d.get("recruitable", true):
			continue
		var rows: Array = InitialStats.rows(cid, d)
		check(rows.size() == 6, "six initial stats for " + cid)
		check(rows[0][1] == "%.0f" % float(d.leader.max_hp), "leader HP from JSON " + cid)
	var synthetic := {"base": {"atk": 77.0, "cd": 2.5, "reach": 180}, "leader": {"max_hp": 155}}
	var dynamic_rows: Array = InitialStats.rows("test", synthetic)
	check(dynamic_rows[0][1] == "155" and dynamic_rows[1][1] == "77.0" and dynamic_rows[2][1] == "2.50 秒", "numbers respond to supplied data")
	# 实际编队对象：同一项精英化在主控提示 Q，队友明确自动。
	var game = load("res://game.tscn").instantiate()
	game.demo_op = "ulpianus"
	add_child(game)
	await get_tree().process_frame
	game.set_process(false)
	var op = game.ch
	op.is_leader = true
	var option := {"kind": "prog", "op": "ulpianus", "elite": 2, "desc": "解锁技能"}
	check("按 Q" in game.panel_ui.option_description(option), "leader growth hints Q")
	check("按 Q" in game.show_screen.skill_item(op, 2).desc, "leader elite show hints Q")
	op.is_leader = false
	check(not "按 Q" in game.panel_ui.option_description(option), "ally growth never asks Q")
	check("自动" in game.show_screen.skill_item(op, 2).desc, "ally elite show says auto")
	# 倍速按钮不与 15 件藏品覆盖；演练结算不读取剧情解锁字段。
	game.demo_op = ""
	game.trial.active = true
	game.trial.started_at = 600.0
	game.t = 673.0
	game.state = game.S.PLAY
	game.relics = game.RL.keys().slice(0, 15)
	Cfg.play_speed = 1.5
	game.hud.queue_redraw()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(game.speed_btn.size.x > 0.0, "speed button visible in play")
		for cell in game.tray_cells:
			check(not game.speed_btn.intersects(cell[0]), "speed button avoids relic cells")
		await capture("ea_hud_speed")
	game.state = game.S.WIN
	game.diff_new = true
	game.tier = game.D.DIFFICULTY_TIERS.size() - 1
	game.hud.queue_redraw()
	await capture("ea_trial_complete")
	game.state = game.S.DEAD
	game.state_age = 10.0
	game.hud.queue_redraw()
	await capture("ea_trial_ended")
	game.queue_free()
	title.queue_free()
	await get_tree().process_frame
	print("EA UI regression: %d failures" % failures)
	get_tree().quit.call_deferred(1 if failures else 0)

## 等到画面切换完成（条件成立）再断言；最多等 max_s 秒。原来固定等 0.4 秒，本机同时跑 6–7 个 Godot 时帧率低、转场没走完就断言，偶发失败（2026-09-29 Boss与怪物报告）
func wait_for(cond: Callable, max_s := 4.0) -> void:
	var t0 := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - t0 < max_s * 1000.0:
		await get_tree().process_frame


func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless" or not Cfg.dev_args().has("--capture-ui"):
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../build/" + name + ".png")
