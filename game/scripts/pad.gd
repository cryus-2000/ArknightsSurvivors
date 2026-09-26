extends Node
## 手柄适配（autoload「Pad」）。
## 思路：所有界面本来就能用键盘操作，所以把手柄输入翻译成等价的键盘事件再注入（Input.parse_input_event），
## 各界面不用改就能用手柄；只有对局里的移动（左摇杆模拟量）由 game.gd 直接读 move_vec()。
##
## 映射按场景上下文（context）切换，由当前场景每帧设置：
##   "title"     标题 / 选人 / 难度 / 图鉴 / 设置：方向 = 方向键，Ⓐ = Enter，Ⓑ = Esc，START = Enter，LB / RB = 翻页，Ⓧ / Ⓨ = 切换动作
##   "play"      对局中：左摇杆 / 十字键移动（不注入方向键），Ⓐ / Ⓧ = 手动技能（J），START = 暂停（Esc），SELECT = 属性面板（Tab）
##   "game_menu" 对局里的选卡 / 商店 / 暂停 / 结算 / 指南 / 属性面板：方向 = 方向键，Ⓐ = Enter，Ⓑ = Esc，START = Esc，
##               SELECT = Tab，Ⓨ = F（商店刷新），LB / RB = PageUp / PageDown（指南翻页）
##
## using：最近一次输入来自手柄（界面据此显示手柄按键提示、隐藏鼠标、用焦点代替悬停）。

const SYNTH_DEVICE := 7777     # 注入事件的 device，用来和真实键盘区分
const STICK_ON := 0.55         # 摇杆当作方向键：按下阈值
const STICK_OFF := 0.35        # 松开阈值（滞回）
const MOVE_DEAD := 0.18        # 移动死区
const REPEAT_DELAY := 0.38
const REPEAT_RATE := 0.11

var context := "title"
var using := false
var device := 0                # 最近使用的手柄
var _dir := Vector2i.ZERO      # 当前按住的导航方向
var _dir_t := 0.0
var _stick_held := false
var _trig := {JOY_AXIS_TRIGGER_LEFT: false, JOY_AXIS_TRIGGER_RIGHT: false}
var _last_ctx := ""
var _block := false            # 切换上下文时摇杆仍按着：松开之前不导航（避免走路的推杆直接移动卡片焦点）

## 各上下文的按钮 → 键位
const MAP := {
	"title": {
		JOY_BUTTON_A: KEY_ENTER, JOY_BUTTON_B: KEY_ESCAPE, JOY_BUTTON_START: KEY_ENTER, JOY_BUTTON_BACK: KEY_ESCAPE,
		JOY_BUTTON_LEFT_SHOULDER: KEY_PAGEUP, JOY_BUTTON_RIGHT_SHOULDER: KEY_PAGEDOWN,
		JOY_BUTTON_X: KEY_Z, JOY_BUTTON_Y: KEY_X,
	},
	"play": {
		JOY_BUTTON_A: KEY_J, JOY_BUTTON_X: KEY_J, JOY_BUTTON_START: KEY_ESCAPE, JOY_BUTTON_BACK: KEY_TAB,
		JOY_BUTTON_B: KEY_K, JOY_BUTTON_RIGHT_SHOULDER: KEY_K,   # 冲刺
	},
	"game_menu": {
		JOY_BUTTON_A: KEY_ENTER, JOY_BUTTON_B: KEY_ESCAPE, JOY_BUTTON_START: KEY_ESCAPE, JOY_BUTTON_BACK: KEY_TAB,
		JOY_BUTTON_Y: KEY_F, JOY_BUTTON_LEFT_SHOULDER: KEY_PAGEUP, JOY_BUTTON_RIGHT_SHOULDER: KEY_PAGEDOWN,
	},
}
const DPAD := {JOY_BUTTON_DPAD_UP: Vector2i(0, -1), JOY_BUTTON_DPAD_DOWN: Vector2i(0, 1), JOY_BUTTON_DPAD_LEFT: Vector2i(-1, 0), JOY_BUTTON_DPAD_RIGHT: Vector2i(1, 0)}
## 扳机键当作肩键
const TRIGGER_AS := {JOY_AXIS_TRIGGER_LEFT: JOY_BUTTON_LEFT_SHOULDER, JOY_AXIS_TRIGGER_RIGHT: JOY_BUTTON_RIGHT_SHOULDER}

## 手柄提示用的按键名（Xbox 布局；PlayStation / Switch 手柄按位置对应）
const GLYPH := {"A": "Ⓐ", "B": "Ⓑ", "X": "Ⓧ", "Y": "Ⓨ", "START": "START", "SELECT": "SELECT", "LB": "LB", "RB": "RB", "STICK": "左摇杆", "DPAD": "十字键"}


var sim := false               # 测试：--padsim 时把 device 0 当作已连接（tests/pad_sim.gd 注入事件）


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.joy_connection_changed.connect(_on_joy_changed)
	if OS.get_cmdline_user_args().has("--padsim"):
		sim = true
		add_child(load("res://tests/pad_sim.gd").new())


func _pads() -> Array:
	var p: Array = Input.get_connected_joypads()
	if sim and not p.has(0):
		p.append(0)
	return p


func _on_joy_changed(dev: int, connected: bool) -> void:
	if not connected and dev == device:
		_set_using(false)


func _set_using(v: bool) -> void:
	if v == using:
		return
	using = v
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if v else Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	if event.device == SYNTH_DEVICE:
		return
	if event is InputEventJoypadButton:
		device = event.device
		_set_using(true)
		# 十字键：按下立刻导航一次（快速点按可能在同一帧内松开，轮询会漏掉），长按连发交给 _process
		if DPAD.has(event.button_index):
			if _block and Vector2(Input.get_joy_axis(event.device, JOY_AXIS_LEFT_X), Input.get_joy_axis(event.device, JOY_AXIS_LEFT_Y)).length() < STICK_OFF:
				_block = false   # 摇杆已经回中，十字键不受「切换上下文时还推着摇杆」的屏蔽
			if event.pressed and context != "play" and not _block:
				var d: Vector2i = DPAD[event.button_index]
				_dir = d
				_dir_t = REPEAT_DELAY
				_nav(d)
			return
		if event.pressed:
			_press_button(event.button_index)
	elif event is InputEventJoypadMotion:
		if absf(event.axis_value) > 0.5:
			device = event.device
			_set_using(true)
		if TRIGGER_AS.has(event.axis):
			var was: bool = _trig[event.axis]
			var on: bool = event.axis_value > (0.3 if was else 0.6)
			_trig[event.axis] = on
			if on and not was:
				_press_button(TRIGGER_AS[event.axis])
	elif event is InputEventKey or event is InputEventScreenTouch:
		_set_using(false)
	elif event is InputEventMouseMotion:
		if event.relative.length() > 6.0:
			_set_using(false)
	elif event is InputEventMouseButton:
		_set_using(false)


func _press_button(b: int) -> void:
	var m: Dictionary = MAP.get(context, {})
	if m.has(b):
		tap(m[b])


## 注入一次按键（按下 + 松开）
func tap(k: int) -> void:
	var ev := InputEventKey.new()
	ev.device = SYNTH_DEVICE
	ev.keycode = k
	ev.physical_keycode = k
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)


func _process(dt: float) -> void:
	if _pads().is_empty():
		return
	# 导航：十字键 + 左摇杆（带滞回），主方向优先；对局里不注入（摇杆是移动）
	var d := Vector2i.ZERO
	for dev in _pads():
		if Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_UP): d = Vector2i(0, -1)
		elif Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_DOWN): d = Vector2i(0, 1)
		elif Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_LEFT): d = Vector2i(-1, 0)
		elif Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_RIGHT): d = Vector2i(1, 0)
		if d != Vector2i.ZERO:
			break
		var s := Vector2(Input.get_joy_axis(dev, JOY_AXIS_LEFT_X), Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y))
		var th: float = STICK_OFF if _stick_held else STICK_ON
		if s.length() > th:
			d = Vector2i(int(signf(s.x)), 0) if absf(s.x) > absf(s.y) else Vector2i(0, int(signf(s.y)))
			break
	_stick_held = d != Vector2i.ZERO
	if context != _last_ctx:
		_last_ctx = context
		_block = d != Vector2i.ZERO
	if _block:
		if d == Vector2i.ZERO:
			_block = false
		_dir = d
		return
	if context == "play":
		_dir = d
		return
	if d == Vector2i.ZERO:
		_dir = d
		return
	if d != _dir:
		_dir = d
		_dir_t = REPEAT_DELAY
		_nav(d)
	else:
		_dir_t -= dt
		if _dir_t <= 0.0:
			_dir_t = REPEAT_RATE
			_nav(d)


func _nav(d: Vector2i) -> void:
	_set_using(true)
	if d.x < 0: tap(KEY_LEFT)
	elif d.x > 0: tap(KEY_RIGHT)
	elif d.y < 0: tap(KEY_UP)
	elif d.y > 0: tap(KEY_DOWN)


## 对局移动：左摇杆（圆形死区、模拟量）+ 十字键；没有手柄返回 ZERO
func move_vec() -> Vector2:
	var best := Vector2.ZERO
	for dev in _pads():
		var s := Vector2(Input.get_joy_axis(dev, JOY_AXIS_LEFT_X), Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y))
		if s.length() > MOVE_DEAD:
			s = s.normalized() * clampf((s.length() - MOVE_DEAD) / (1.0 - MOVE_DEAD), 0.0, 1.0)
		else:
			s = Vector2.ZERO
		var dp := Vector2(float(Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_RIGHT)) - float(Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_LEFT)),
			float(Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_DOWN)) - float(Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_UP)))
		if dp != Vector2.ZERO:
			s = dp.normalized()
		if s.length() > best.length():
			best = s
	return best


## 震动（受伤、死亡等）：只在用手柄、且设置里开着时
func rumble(weak: float, strong: float, dur: float) -> void:
	if not using or not Cfg.pad_rumble:
		return
	Input.start_joy_vibration(device, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), dur)


## 提示文字：用手柄时返回 pad_text，否则 key_text
func hint(key_text: String, pad_text: String) -> String:
	return pad_text if using else key_text
