extends Node
## 触屏摇杆卡死兜底的手机仿真录帧（10-26，不进快检）：手动派 InputEventScreenTouch / Drag，逐帧存 rec_<帧>.png，左上角字幕写当前场景。
##   godot --fixed-fps 30 --resolution 1560x720 --path game res://tests/touch_stuck_rec.tscn -- --touch --shotdir=<目录>
var game: Node
var shot_dir := ""
var cap: Label
var n := 0
var T
var orient_only := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			shot_dir = a.substr(10)
		elif a == "--orient":
			orient_only = true   # 只录横 → 竖 → 横（tools/web/orientation.js 通知 game._on_orient）
	call_deferred("run")


func fr(k := 1) -> void:
	for i in k:
		game.state = game.S.PLAY
		game.pending_levelups = 0
		game.pending_chests = 0
		game.invuln = 1.0
		await get_tree().process_frame
		if shot_dir != "":
			get_viewport().get_texture().get_image().save_png(shot_dir + "/rec_%04d.png" % n)
			n += 1


func tch(idx: int, pos: Vector2, pressed: bool, canceled := false) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = pos
	e.pressed = pressed
	e.canceled = canceled
	Input.parse_input_event(e)


func drg(idx: int, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = pos
	e.relative = rel
	Input.parse_input_event(e)


func say(t: String) -> void:
	cap.text = t


func stick(idx: int, p0: Vector2, dx: float) -> void:
	tch(idx, p0, true)
	await fr(1)
	drg(idx, p0 + Vector2(dx, 0), Vector2(dx, 0))
	await fr(1)


func run() -> void:
	game = load("res://game.tscn").instantiate()
	add_child(game)
	await fr(8)
	T = game.touch
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	cap = Label.new()
	cap.position = Vector2(24, 96)
	cap.add_theme_font_size_override("font_size", 26)
	cap.add_theme_color_override("font_color", Color(1, 0.95, 0.5))
	cap.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	cap.add_theme_constant_override("outline_size", 6)
	cap.add_theme_font_override("font", game.font)
	layer.add_child(cap)
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var a0 := Vector2(vs.x * 0.22, vs.y * 0.62)
	game.ppos = Vector2(1500, 900)
	if orient_only:
		await orient_phase(a0, vs)
		print("TOUCH STUCK REC done frames=%d" % n)
		get_tree().quit(0)
		return
	say("手机仿真 1560×720：按住摇杆向右 → 主控向右走")
	await stick(0, a0, 90.0)
	await fr(36)
	say("松手事件被吞掉（旧版：一直向右走停不下来）→ 现在一帧内摇杆复位")
	T.active = false
	tch(0, a0 + Vector2(90, 0), false)
	T.active = true
	await fr(40)
	say("新手指按下向左 → 能换向")
	await stick(1, a0, -90.0)
	await fr(36)
	tch(1, a0, false)
	await fr(12)
	say("touchcancel（Safari 边缘手势 / 系统手势）→ 摇杆复位")
	await stick(2, a0, 90.0)
	await fr(20)
	tch(2, a0, false, true)
	await fr(40)
	say("手指滑出画布外再松手 → 摇杆复位，再按能换向")
	await stick(3, a0, -90.0)
	await fr(14)
	drg(3, Vector2(vs.x + 300.0, vs.y + 200.0), Vector2(300, 200))
	await fr(14)
	tch(3, Vector2(vs.x + 300.0, vs.y + 200.0), false)
	await fr(24)
	await stick(4, a0, 90.0)
	await fr(24)
	tch(4, a0, false)
	await fr(10)
	say("touchend 整个丢了：摇杆触点很久没动静，新手指按下直接接管 → 换向")
	await stick(5, a0, 90.0)
	await fr(24)
	T.stick_ms -= 1000
	await stick(6, a0 + Vector2(0, 30), -90.0)
	await fr(40)
	tch(6, a0, false)
	T._down.erase(5)
	await fr(10)
	say("超过 4 秒没事件当作松手（停下）；手指再动就接回")
	await stick(7, a0, 90.0)
	await fr(20)
	T.stick_ms -= 5000
	await fr(36)
	drg(7, a0 + Vector2(0, 40), Vector2(0, 40))
	await fr(1)
	drg(7, a0 + Vector2(-90, 40), Vector2(-90, 0))
	await fr(36)
	tch(7, a0, false)
	await fr(8)
	say("切后台 / 窗口失焦 → 摇杆复位")
	await stick(8, a0, 90.0)
	await fr(24)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await fr(40)
	tch(8, a0, false)
	await fr(6)
	print("TOUCH STUCK REC done frames=%d" % n)
	get_tree().quit(0)


## 横 → 竖 → 横：浏览器里竖屏持续 0.5 秒后 orientation.js 盖上提示层并通知游戏暂停；这里用色块 + 文字示意提示层（真实 DOM 层的截图见 overlay_portrait.png）
func orient_phase(a0: Vector2, vs: Vector2) -> void:
	var cover := ColorRect.new()
	cover.color = Color(0.008, 0.024, 0.04, 1.0)
	cover.size = vs
	cover.visible = false
	var lab := Label.new()
	lab.text = "请将手机横过来
游戏已暂停，转回横屏后继续"
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.add_theme_font_size_override("font_size", 34)
	lab.add_theme_color_override("font_color", Color(0.8, 1, 0.95))
	lab.add_theme_font_override("font", game.font)
	lab.size = Vector2(vs.x, 120)
	lab.position = Vector2(0, vs.y * 0.4)
	cover.add_child(lab)
	cap.get_parent().add_child(cover)
	cap.get_parent().move_child(cap, -1)
	say("横屏：按住摇杆向右走")
	await stick(0, a0, 90.0)
	await fr(40)
	say("手机转成竖屏（持续 0.5 秒）→ 提示层盖上，游戏暂停，摇杆复位（提示层此处为示意）")
	game._on_orient(["1"])
	cover.visible = true
	await fr(50)
	tch(0, a0 + Vector2(90, 0), false)   # 竖屏期间手指抬起（事件落在提示层上，游戏收不到也无妨）
	say("转回横屏 → 提示层撤掉，游戏自动继续，主控不再自己乱走")
	game._on_orient(["0"])
	cover.visible = false
	await fr(40)
	say("再按摇杆向左 → 正常换向")
	await stick(1, a0, -90.0)
	await fr(40)
	tch(1, a0, false)
	await fr(10)
