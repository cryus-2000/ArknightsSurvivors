extends Node
## 响应动作示范录屏（docs/118）：开窗口跑，逐帧截图到 build/response_demo/<demo>/，再由脚本拼成 gif。
##   godot --path game res://tests/response_demo_capture.tscn -- --balance --seed=1 --op=<队长> --squad=<队友…> --demo=<干员 id>
## 队长由按键事件驱动：移动 = 按住方向键，冲刺 = 空格；开技能 = 把队长技力充满。只截图，不断言。
## 演示什么按 demo 的触发源：DASH 冲刺 / SKILL 开技能 / CMD 指挥（站定第 5 帧切突击、第 35 帧切归队，之后自动集合）/ 其余 = 站定（每轮移动 30 帧后站定）。

const DT := 1.0 / 60.0
const DASH := ["texas", "exusiai", "skadi", "siege", "ulpianus"]
const SKILL := ["suzuran", "logos", "skalter", "kaltsit"]
const CMD := ["mizuki", "specter_unchained", "irene", "angelina"]


func key(code: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = down
	Input.parse_input_event(ev)


func _ready() -> void:
	var demo := "texas"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--demo="): demo = arg.get_slice("=", 1)
	var output := ProjectSettings.globalize_path("res://../build/response_demo/" + demo)
	DirAccess.make_dir_recursive_absolute(output)
	var g = load("res://game.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	g.mode = g.Mode.PLAY
	g.state = g.S.PLAY
	g.t = 60.0
	g.invuln = 999.0
	g.xp_need = 1000000000.0
	for o in g.squad.ops:
		o.elite = maxi(o.elite, 1)
		o.refresh_stats()
		o.sp = [-100000.0, -100000.0, -100000.0]
	var center: Vector2 = g.ppos
	for k in 10:
		var e: Dictionary = g.spawner.spawn_enemy("stone", center + Vector2.from_angle(TAU * k / 10.0) * (110.0 + 40.0 * (k % 2)))
		e.hp = 1000000.0
		e.maxhp = 1000000.0
	g.enemies_sys.build_grid()
	var lead = g.squad.leader() if g.squad.has_method("leader") else g.ch
	var frames := 300
	for frame in frames:
		# 节奏：每 100 帧一轮，前 30 帧移动（向右 / 向左交替），之后站定；冲刺类在移动第 10 帧冲刺；开技能类在站定第 20 帧让队长开技能
		var ph := frame % 100
		var right := (frame / 100) % 2 == 0
		var kc := KEY_D if right else KEY_A
		if ph == 0:
			key(kc, true)
		if ph == 30:
			key(kc, false)
		if demo in DASH and ph == 10:
			key(KEY_SPACE, true)
		if demo in DASH and ph == 12:
			key(KEY_SPACE, false)
		if demo in CMD and (ph == 35 or ph == 65):
			g.squad.cycle_stance()
		if demo in SKILL and ph == 50 and lead != null:
			lead.sp[0] = lead.sp_need(0)
		g._update(DT)
		g.world.update_visuals(DT)
		g.world.present_step()
		g.queue_redraw()
		g.fx_add.queue_redraw()
		g.fg.queue_redraw()
		g.hud.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		if frame % 2 == 0:
			var image := get_viewport().get_texture().get_image()
			var c: Vector2 = Vector2(image.get_width(), image.get_height()) / 2.0
			image.get_region(Rect2i(Vector2i(c) - Vector2i(240, 190), Vector2i(480, 320))).save_png(output.path_join("f_%03d.png" % frame))
	print("RESPONSE DEMO %s" % demo)
	get_tree().quit()
