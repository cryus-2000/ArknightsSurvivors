extends Node
## 失焦保护回归（docs/317，web_focus.gd；11-07 Toy 实测「点出网页之后不太好操作」）：
##   godot --headless --path game res://tests/web_focus_test.tscn -- --regression --touch --focustest --focuspause --op=mizuki --squad=hoshiguma,exusiai
## 失焦（NOTIFICATION_APPLICATION_FOCUS_OUT，网页上由 JS blur / visibilitychange 计数触发同一个 lost()）之后：
##   摇杆手指、按着的移动键、鼠标左键都松开；按住 F 打开的圆盘被取消（不是松开确认，不下指令）；选点被取消；
##   对局中自动暂停；选卡等非对局状态下失焦，回到对局时补一次暂停。全部通过打印 "WEB FOCUS failures=0"
var failures := 0
var game: Node


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("WEB FOCUS: " + what)


func _ready() -> void:
	call_deferred("run")


func frames(n := 2) -> void:
	for i in n:
		await get_tree().process_frame


func play(n := 2) -> void:
	for i in n:
		game.state = game.S.PLAY
		game.pending_levelups = 0
		game.pending_chests = 0
		game.invuln = 1.0
		await get_tree().process_frame


func key(k: int, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)


func focus_out() -> void:
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await frames(2)


func run() -> void:
	get_tree().root.size = Vector2i(1560, 720)
	await frames(2)
	game = load("res://game.tscn").instantiate()
	add_child(game)
	await frames(6)
	await play(4)
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var k: Vector2 = Vector2(get_tree().root.size) / vs
	# 1. 摇杆手指按着 + 移动键按着 + 鼠标左键按着 → 失焦后全部松开、对局暂停
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.position = Vector2(vs.x * 0.25, vs.y * 0.5) * k
	t.pressed = true
	Input.parse_input_event(t)
	await frames(1)
	var d := InputEventScreenDrag.new()
	d.index = 0
	d.position = t.position + Vector2(80, 0) * k
	d.relative = Vector2(80, 0)
	Input.parse_input_event(d)
	key(KEY_D, true)
	await play(3)
	check(game.touch.stick_id >= 0, "前提：摇杆手指按着")
	check(Input.is_key_pressed(KEY_D), "前提：D 键按着")
	await focus_out()
	check(game.touch.stick_id < 0 and game.touch.move_vec() == Vector2.ZERO, "失焦后摇杆复位（stick_id=%d）" % game.touch.stick_id)
	check(not Input.is_key_pressed(KEY_D), "失焦后 D 键松开")
	check(game.state == game.S.PAUSE, "对局中失焦自动暂停（state=%d）" % game.state)
	check(game.web_focus.lost_n == 1, "失焦处理一次")
	check(game.web_focus.paused, "失焦暂停：暂停菜单写「点击继续」")
	await play(3)
	check(not game.web_focus.paused, "回到对局后收起提示")
	# 2. 按住 F 打开圆盘、悬停一项 → 失焦：圆盘取消，不下指令
	await play(4)
	var stance0 = game.squad.stance
	key(KEY_F, true)
	await play(2)
	game.wheel.open(null)   # 按住模式由按键事件判断；这里直接开，src 记成键盘
	game.wheel.src = "key"
	game.wheel.latched = false
	game.wheel.forced = 1
	await play(2)
	check(game.wheel.is_open, "前提：圆盘开着")
	await focus_out()
	check(not game.wheel.is_open, "失焦后圆盘关掉")
	check(game.squad.stance == stance0, "失焦取消圆盘、不当作松开确认（stance %s → %s）" % [stance0, game.squad.stance])
	check(not Input.is_key_pressed(KEY_F), "失焦后 F 键松开")
	# 3. 选点阶段 → 失焦取消
	await play(4)
	game.squad.stamina = 1.0
	game.pick.begin("point")
	await play(1)
	check(game.pick.active, "前提：选点中")
	await focus_out()
	check(not game.pick.active, "失焦后选点取消")
	# 4. 选卡等非对局状态下失焦：回到对局时补一次暂停
	await play(2)
	game.state = game.S.CHOICE
	await focus_out()
	check(game.state == game.S.CHOICE, "选卡中失焦不改状态")
	game.state = game.S.PLAY
	await frames(2)
	check(game.state == game.S.PAUSE, "回到对局时补一次暂停（state=%d）" % game.state)
	print("WEB FOCUS failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
