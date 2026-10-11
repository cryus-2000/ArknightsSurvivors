extends Node
## 致谢与声明（标题页，10-11 改滚动条）输入回归：键盘 ↑↓ / PgUp PgDn / Home End、手柄十字键 / LB RB（经 Pad 翻译）、
## 鼠标滚轮、拖正文（松手惯性）、拖滚动条、点正文不关闭、点「返回」/ 面板外 / Esc / 手柄 Ⓑ 关闭；桌面与触屏版式都查一遍。
var failures := 0
var title: Control


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("CREDITS INPUT: " + what)


func _ready() -> void:
	call_deferred("run")


func frames(n := 2) -> void:
	for i in n:
		await get_tree().process_frame


func key(k: int) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = true
	Input.parse_input_event(e)
	var u := InputEventKey.new()
	u.keycode = k
	u.pressed = false
	Input.parse_input_event(u)
	await frames()


func pad(b: int) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	var u := InputEventJoypadButton.new()
	u.button_index = b
	u.pressed = false
	Input.parse_input_event(u)
	await frames()


func vp(local: Vector2) -> Vector2:
	return title.get_global_transform() * local


func mouse(local: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = button
	mb.position = vp(local)
	mb.pressed = pressed
	if button != MOUSE_BUTTON_LEFT:
		mb.factor = 1.0
	get_viewport().push_input(mb, true)
	await get_tree().process_frame


## 按下 → 分 n 步移动 total → 松开（本地坐标）
func drag(from: Vector2, total: Vector2, n := 6) -> void:
	await mouse(from, true)
	var p := from
	var k: float = title.get_global_transform().get_scale().x
	for i in n:
		var mm := InputEventMouseMotion.new()
		p += total / n
		mm.position = vp(p)
		mm.relative = total / n * k
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		get_viewport().push_input(mm, true)
		await get_tree().process_frame
	await mouse(p, false)


func settle_scroll() -> void:
	# 键盘 / 滚轮只改目标，显示值逐帧逼近；这里只看目标值
	await frames(2)


func open() -> void:
	await key(KEY_C)
	var t0 := Time.get_ticks_msec()
	while (not title.credits or title.transition.busy) and Time.get_ticks_msec() - t0 < 4000:
		await get_tree().process_frame
	await frames(3)


func wait_closed() -> void:
	var t0 := Time.get_ticks_msec()
	while (title.credits or title.transition.busy) and Time.get_ticks_msec() - t0 < 4000:
		await get_tree().process_frame


func one_layout(tag: String) -> void:
	await open()
	check(title.credits, tag + ": C opens credits")
	check(title.cr_scroll == 0.0, tag + ": opens at top")
	check(title.cr_max > 0.0, tag + ": content taller than view (scrollable), max=%s" % title.cr_max)
	check(title.cr_view.visible and title.cr_view.clip_contents, tag + ": body clip view visible")
	# 字号：说明不再缩到 11（固定 17）
	check(title.cr_lay.rows[0].text.size >= 17, tag + ": body text >= 17")
	# 键盘
	await key(KEY_DOWN)
	check(is_equal_approx(title.cr_scroll, minf(title.CREDITS_LINE, title.cr_max)), tag + ": down scrolls one line")
	await key(KEY_UP)
	check(title.cr_scroll == 0.0, tag + ": up scrolls back")
	await key(KEY_PAGEDOWN)
	var pg: float = title.cr_scroll
	check(pg > title.CREDITS_LINE or pg == title.cr_max, tag + ": page down scrolls a page")
	await key(KEY_END)
	check(title.cr_scroll == title.cr_max, tag + ": end jumps to bottom")
	await key(KEY_DOWN)
	check(title.cr_scroll == title.cr_max, tag + ": clamps at bottom")
	await key(KEY_HOME)
	check(title.cr_scroll == 0.0, tag + ": home jumps to top")
	check(title.credits, tag + ": scroll keys don't close")
	# 手柄（十字键 → ↑↓、RB / LB → PgDn / PgUp）
	await pad(JOY_BUTTON_DPAD_DOWN)
	check(title.cr_scroll > 0.0, tag + ": gamepad dpad down scrolls")
	await pad(JOY_BUTTON_DPAD_UP)
	check(title.cr_scroll == 0.0, tag + ": gamepad dpad up scrolls back")
	await pad(JOY_BUTTON_RIGHT_SHOULDER)
	check(title.cr_scroll > title.CREDITS_LINE or title.cr_scroll == title.cr_max, tag + ": gamepad RB pages down")
	await pad(JOY_BUTTON_LEFT_SHOULDER)
	check(title.cr_scroll == 0.0, tag + ": gamepad LB pages up")
	# 滚轮
	var c: Vector2 = title.cr_vr.get_center()
	await mouse(c, true, MOUSE_BUTTON_WHEEL_DOWN)
	await settle_scroll()
	check(title.cr_scroll > 0.0, tag + ": wheel down scrolls")
	await mouse(c, true, MOUSE_BUTTON_WHEEL_UP)
	check(title.cr_scroll == 0.0, tag + ": wheel up scrolls back")
	# 拖正文：1:1 跟手，松手有惯性；点正文（不拖）不关闭
	await drag(c + Vector2(0, 60), Vector2(0, -120))
	var after: float = title.cr_scroll
	check(after >= minf(100.0, title.cr_max) - 1.0, tag + ": drag up scrolls ~1:1 (got %s)" % after)
	check(title.cr_vel > 0.0 or after == title.cr_max, tag + ": release keeps inertia")
	await frames(10)
	check(title.cr_scroll >= after, tag + ": inertia continues")
	title.cr_vel = 0.0
	await mouse(c, true)
	await mouse(c, false)
	check(title.credits, tag + ": tap on body doesn't close")
	# 拖滚动条：按到轨道底 = 最底，按到顶 = 最顶
	var bar: Rect2 = title.cr_bar
	check(bar.size.y > 0.0, tag + ": scrollbar present")
	await mouse(Vector2(bar.get_center().x, bar.end.y - 1.0), true)
	check(is_equal_approx(title.cr_scroll, title.cr_max), tag + ": press bar bottom -> bottom")
	await drag(Vector2(bar.get_center().x, bar.end.y - 1.0), Vector2(0, -(bar.size.y + 20.0)), 4)
	check(title.cr_scroll == 0.0, tag + ": drag bar to top -> top")
	check(title.credits, tag + ": scrollbar doesn't close")
	# 关闭：点「返回」
	await mouse(title.cr_back.get_center(), true)
	await mouse(title.cr_back.get_center(), false)
	await wait_closed()
	check(not title.credits, tag + ": back button closes")
	# 手柄 Ⓑ 关闭；面板外点击关闭；Esc 关闭
	await open()
	await pad(JOY_BUTTON_B)
	await wait_closed()
	check(not title.credits, tag + ": gamepad B closes")
	await open()
	var outside := Vector2(title.cr_panel.position.x - 4.0, title.cr_panel.get_center().y)
	if outside.x > 0.0:
		await mouse(outside, true)
		await mouse(outside, false)
		await wait_closed()
		check(not title.credits, tag + ": click outside panel closes")
	else:
		await key(KEY_ESCAPE)
		await wait_closed()
	await open()
	await key(KEY_ESCAPE)
	await wait_closed()
	check(not title.credits, tag + ": escape closes")


func run() -> void:
	title = load("res://main.tscn").instantiate()
	add_child(title)
	await get_tree().process_frame
	title.intro = title.INTRO_LEN
	# 无头窗口是 1280×1280，整页放得下；按真实界面尺寸排版（桌面 1280×720、手机 UI 逻辑约 1044×481）
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	title.position = Vector2.ZERO
	title.size = Vector2(1280, 720)
	await frames(3)
	await one_layout("desktop")
	Cfg._touch = 1
	title.size = Vector2(1044, 481)
	await frames(2)
	await one_layout("touch")
	Cfg._touch = -1
	title.queue_free()
	await get_tree().process_frame
	print("CREDITS INPUT: %d failures" % failures)
	get_tree().quit.call_deferred(1 if failures else 0)
