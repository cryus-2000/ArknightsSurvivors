extends Node
## 触屏判定区探针（docs/349，11-16 安卓 B站真机参数）：按 --touch --safe=… --capsule=… 的窗口，在对局里把屏幕按网格逐点按下，
## 记每点被谁接走（摇杆 / 按钮 / 编队卡 / 没人），打印一张字符图；再在左半屏中部按下拖动，查摇杆与位移。
## 例：godot --headless --path game res://tests/touch_zone_probe.tscn -- --touch --safe=80,108,0,0 --capsule=216,92 --probesize=1588x722
var game: Node


func _ready() -> void:
	call_deferred("run")


func frames(n := 2) -> void:
	for i in n:
		await get_tree().process_frame


func touch(idx: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = pos
	e.pressed = pressed
	Input.parse_input_event(e)


func hold_play(n: int) -> void:
	for i in n:
		game.state = game.S.PLAY
		game.pending_levelups = 0
		game.pending_chests = 0
		game.invuln = 1.0
		await get_tree().process_frame


func run() -> void:
	var vsz := Vector2i(1588, 722)
	for a in Cfg.dev_args():
		if a.begins_with("--probesize="):
			var q: PackedStringArray = a.substr(12).split("x")
			vsz = Vector2i(int(q[0]), int(q[1]))
	get_tree().root.size = vsz
	await frames(2)
	game = load("res://game.tscn").instantiate()
	add_child(game)
	await frames(6)
	await hold_play(4)
	var vs: Vector2 = get_viewport().get_visible_rect().size
	print("PROBE vis=%s ui_k=%.3f hud=%s ins=%s sys=%s cap=%s phone=%s" % [vs, Cfg.ui_k, game.hud.size, Cfg.safe_insets(), Cfg.hud_ins(), Cfg.capsule_ui(), Cfg.phone_ui()])
	var L: Dictionary = game.touch.layout(game.hud.size)
	for k in L:
		print("PROBE key %s c=%s s=%.2f" % [k, L[k].c, float(L[k].s)])
	# 网格：40 列 × 18 行（视口像素），S = 摇杆、B = 按钮 / 键、. = 没人接、x = 被别处吞（handle 之前）
	var cols := 40
	var rows := 18
	var idx := 100
	for r in rows:
		var line := ""
		for c in cols:
			var p := Vector2((c + 0.5) * vs.x / cols, (r + 0.5) * vs.y / rows)
			await hold_play(1)
			var s0: int = game.touch.stick_id
			touch(idx, p, true)
			await frames(1)
			var ch := "."
			if game.touch.stick_id >= 0 and s0 < 0:
				ch = "S"
			elif game.touch.skill_id >= 0 or game.touch.atk_id >= 0:
				ch = "B"
			elif game.state != game.S.PLAY or game.wheel.is_open:
				ch = "B"
			touch(idx, p, false)
			await frames(1)
			if game.wheel.is_open:
				game.wheel.cancel()
			idx += 1
			line += ch
		print("PROBE row %02d %s" % [r, line])
	# 拖动：左半屏中部、离左边 1/6 屏宽
	var p0 := Vector2(vs.x * 0.18, vs.y * 0.6)
	var x0: float = game.ppos.x
	touch(7, p0, true)
	await frames(1)
	var e := InputEventScreenDrag.new()
	e.index = 7
	e.position = p0 + Vector2(90, 0)
	e.relative = Vector2(90, 0)
	Input.parse_input_event(e)
	await hold_play(30)
	print("PROBE drag stick=%d vec=%s dx=%.1f" % [game.touch.stick_id, game.touch.move_vec(), game.ppos.x - x0])
	touch(7, p0, false)
	await frames(2)
	get_tree().quit(0)
