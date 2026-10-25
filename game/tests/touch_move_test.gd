extends Node
## 触屏移动回归（10-12「手机端现在移动不了」）：对局里左半屏按下 + 拖动（InputEventScreenTouch / ScreenDrag，走 Input.parse_input_event 全链路，
## 先过 game._input 再到 GUI），主控必须朝拖动方向走、松手后停。
## 触点 index 覆盖三种来源：桌面 / 安卓的小整数、iOS Safari 的大数、超过 2^31 后被 Godot 按 i32 截成的负数（原 bug：负 index 让摇杆失灵）。
## 版式：桌面 --touch（1280×720，ui_k 1.11）与手机比例（19.5:9，ui_k 1.3）各一遍；另查两指（摇杆 + 第二指）、全屏后期层不拦输入。
var failures := 0
var game: Node
## 网页 Touch.identifier 3000000000 经 i32 截断后的值（iOS Safari 全局累加的触点编号会走到这里）
const WRAPPED := 3000000000 - 4294967296


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("TOUCH MOVE: " + what)


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


func drag(idx: int, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = pos
	e.relative = rel
	Input.parse_input_event(e)


func run() -> void:
	check(Cfg.touch_device(), "--touch 应开启触屏")
	for vsz in [Vector2i(1280, 720), Vector2i(1560, 720)]:
		await one(vsz)
	print("TOUCH MOVE: %d failures" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func hold_play(n: int) -> void:
	for i in n:
		game.state = game.S.PLAY
		game.pending_levelups = 0
		game.pending_chests = 0
		game.invuln = 1.0
		await get_tree().process_frame


## 一次拖动：idx 按下 → 拖 dx → 保持 30 帧，查摇杆与位移；松手后查复位与停下
func stroke(tag: String, idx: int, dir: float) -> void:
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var p0 := Vector2(vs.x * 0.25, vs.y * 0.5)
	var p1 := p0 + Vector2(80.0 * dir, 0)
	var x0: float = game.ppos.x
	touch(idx, p0, true)
	await frames(1)
	drag(idx, p1, p1 - p0)
	await hold_play(30)
	var t: String = "%s idx=%d" % [tag, idx]
	check(game.touch.stick_id >= 0, t + " 按下左半屏应接管摇杆（stick_id=%d）" % game.touch.stick_id)
	check(game.touch.move_vec().x * dir > 0.5, t + " 摇杆向量应朝拖动方向（%s）" % game.touch.move_vec())
	var dx: float = (game.ppos.x - x0) * dir
	print("TOUCH MOVE %s: dx=%.1f stick=%d vec=%s" % [t, dx, game.touch.stick_id, game.touch.move_vec()])
	check(dx > 20.0, t + " 主控应朝拖动方向移动（dx=%.1f）" % dx)
	touch(idx, p1, false)
	await frames(2)
	check(game.touch.stick_id < 0 and game.touch.move_vec() == Vector2.ZERO, t + " 松手后摇杆复位")
	var x1: float = game.ppos.x
	await hold_play(10)
	check(absf(game.ppos.x - x1) < 4.0, t + " 松手后主控停下")


## 起一次摇杆：idx 按下 + 向右拖 80，等主控动起来（move_vec.x > 0.5）
func start_stick(idx: int, p0: Vector2, dx := 80.0) -> void:
	touch(idx, p0, true)
	await frames(1)
	drag(idx, p0 + Vector2(dx, 0), Vector2(dx, 0))
	await hold_play(2)


## 摇杆卡死兜底（10-26 iPhone「一直朝一个方向走、移动键没用」）：松手事件丢了 / 被吞了 / 取消 / 滑出画布 / 双指 / 失焦，摇杆都要复位，新手指都能重新换向
func stuck_cases(tag: String, a0: Vector2) -> void:
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var T = game.touch
	# 1 松手事件被早退吞掉（胜利演出 / 设置面板 / 指挥圆盘开着时 touch.handle 不会被调到）：observe 记下松开，一帧内复位
	await start_stick(WRAPPED, a0)
	check(T.stick_id >= 0 and T.move_vec().x > 0.5, tag + " [吞松手] 先起摇杆")
	T.active = false   # 模拟 touch.handle 没被调到（早退 / 被别处吞掉），observe 照常记录
	touch(WRAPPED, a0 + Vector2(80, 0), false)
	await frames(2)
	T.active = true
	check(T.stick_id < 0 and T.move_vec() == Vector2.ZERO, tag + " [吞松手] 松手事件被吞后摇杆也复位")
	await hold_play(2)
	await start_stick(5, a0, -80.0)
	check(T.move_vec().x < -0.5, tag + " [吞松手] 之后新手指能换向（%s）" % T.move_vec())
	touch(5, a0, false)
	await frames(2)
	# 2 取消（Safari 边缘手势 / 系统手势）：按松手处理，复位
	await start_stick(7, a0)
	var ce := InputEventScreenTouch.new()
	ce.index = 7
	ce.position = a0
	ce.pressed = false
	ce.canceled = true
	Input.parse_input_event(ce)
	await frames(2)
	check(T.stick_id < 0 and T.move_vec() == Vector2.ZERO, tag + " [取消] touchcancel 后摇杆复位")
	# 3 手指滑出画布再松手（位置在视口外）
	await start_stick(9, a0)
	drag(9, Vector2(vs.x + 300.0, vs.y + 200.0), Vector2(300, 200))
	await frames(1)
	touch(9, Vector2(vs.x + 300.0, vs.y + 200.0), false)
	await frames(2)
	check(T.stick_id < 0 and T.move_vec() == Vector2.ZERO, tag + " [滑出画布] 画布外松手后摇杆复位")
	# 4 松手事件整个丢了（observe 也没收到）：摇杆触点很久没动静，新手指在摇杆区按下直接接管
	await start_stick(11, a0)
	T._down.erase(11)   # 模拟 touchend 根本没到
	T.stick_ms -= 1000
	T._down[11] = true   # 保持「按着」的假象：走接管路径而不是 observe 复位路径
	touch(12, a0 + Vector2(0, 30), true)
	await frames(1)
	drag(12, a0 + Vector2(0, 30) + Vector2(-80, 0), Vector2(-80, 0))
	await hold_play(2)
	check(T.stick_id >= 0 and T.stick_raw == 12 and T.move_vec().x < -0.5, tag + " [接管] 旧摇杆触点无动静时新手指接管并能换向（raw=%d %s）" % [T.stick_raw, T.move_vec()])
	touch(12, a0, false)
	T._down.erase(11)
	await frames(2)
	# 5 超过 STICK_STALE 没事件：当作松手（停下）；那根手指再拖动就接回
	await start_stick(13, a0)
	T.stick_ms -= 5000
	await frames(2)
	check(T.stick_id < 0 and T.move_vec() == Vector2.ZERO, tag + " [超时] 太久没事件当作松手")
	drag(13, a0 + Vector2(0, 60), Vector2(0, 60))
	await frames(1)
	drag(13, a0 + Vector2(0, 60) + Vector2(80, 0), Vector2(80, 0))
	await hold_play(2)
	check(T.stick_id >= 0 and T.move_vec().x > 0.5, tag + " [超时] 同一根手指再拖动接回摇杆（%s）" % T.move_vec())
	touch(13, a0, false)
	await frames(2)
	# 6 窗口失焦 / 切后台：全部复位
	await start_stick(14, a0)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(T.stick_id < 0 and T.move_vec() == Vector2.ZERO, tag + " [失焦] 窗口失焦后摇杆复位")
	touch(14, a0, false)
	await frames(2)
	# 7 双指：摇杆手指按着时第二指在右半屏（非摇杆区）按下又松开，摇杆保持
	await start_stick(15, a0)
	touch(16, Vector2(vs.x * 0.9, vs.y * 0.5), true)
	touch(16, Vector2(vs.x * 0.9, vs.y * 0.5), false)
	await hold_play(2)
	check(T.stick_id >= 0 and T.move_vec().x > 0.5, tag + " [双指] 右半屏第二指不影响摇杆")
	touch(15, a0, false)
	await frames(2)
	check(T.stick_id < 0, tag + " [双指] 摇杆手指松手后复位")


func one(vsz: Vector2i) -> void:
	var tag := "%dx%d" % [vsz.x, vsz.y]
	get_tree().root.size = vsz
	await frames(2)
	game = load("res://game.tscn").instantiate()
	add_child(game)
	await frames(6)
	await hold_play(2)
	check(game.touch.active, tag + " 触屏摇杆应开启")
	print("TOUCH MOVE %s: visible=%s ui_k=%.2f hud=%s" % [tag, get_viewport().get_visible_rect().size, Cfg.ui_k, game.hud.size])
	# 全屏后期层只是画面：不能拦输入
	check(game.post.rect.mouse_filter == Control.MOUSE_FILTER_IGNORE, tag + " 全屏后期层 mouse_filter 应为 IGNORE")
	var dir := 1.0
	for idx in [0, 5, 2147483000, WRAPPED, -1, WRAPPED - 1]:
		await stroke(tag, idx, dir)
		dir = -dir
	# 两指：摇杆手指按住时第二指点左半屏不抢摇杆；第二指松手不影响摇杆；摇杆手指（负 index）松手才复位
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var a0 := Vector2(vs.x * 0.25, vs.y * 0.5)
	touch(WRAPPED, a0, true)
	await frames(1)
	drag(WRAPPED, a0 + Vector2(80, 0), Vector2(80, 0))
	await frames(1)
	touch(7, a0 + Vector2(0, 60), true)
	await frames(1)
	touch(7, a0 + Vector2(0, 60), false)
	await hold_play(3)
	check(game.touch.move_vec().x > 0.5, tag + " 第二指点按不打断摇杆（%s）" % game.touch.move_vec())
	drag(WRAPPED, a0 + Vector2(-80, 0), Vector2(-160, 0))
	await hold_play(2)
	check(game.touch.move_vec().x < -0.5, tag + " 摇杆手指继续拖动仍生效（%s）" % game.touch.move_vec())
	touch(WRAPPED, a0, false)
	await frames(2)
	check(game.touch.stick_id < 0, tag + " 摇杆手指松手后复位")
	# 没登记过的触点（按下被别处吞掉）只拖动 / 松手：不影响摇杆
	drag(123456, a0, Vector2(10, 0))
	touch(123456, a0, false)
	await frames(2)
	check(game.touch.stick_id < 0 and game.touch.move_vec() == Vector2.ZERO, tag + " 未登记触点不动摇杆")
	await stuck_cases(tag, a0)
	game.queue_free()
	await frames(3)
