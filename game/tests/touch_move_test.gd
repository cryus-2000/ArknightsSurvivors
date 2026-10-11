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
	game.queue_free()
	await frames(3)
