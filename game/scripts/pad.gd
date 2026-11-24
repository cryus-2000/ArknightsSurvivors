extends Node
## 手柄适配（autoload「Pad」）。
## 思路：所有界面本来就能用键盘操作，所以把手柄输入翻译成等价的键盘事件再注入（Input.parse_input_event），
## 各界面不用改就能用手柄；只有对局里的移动（左摇杆模拟量）由 game.gd 直接读 move_vec()。
##
## 映射按场景上下文（context）切换，由当前场景每帧设置：
##   "title"     标题 / 选人 / 难度 / 图鉴 / 设置：方向 = 方向键，Ⓐ = Enter，Ⓑ = Esc，START = Enter，LB / RB = 翻页，Ⓧ / Ⓨ = 切换动作
##   "play"      对局中：左摇杆 / 十字键移动（不注入方向键），右摇杆 = 按住瞄准（doctor 每帧读）；其余按钮 / 扳机按局内按键表
##               （core/play_keys.gd，玩家可在「设置 → 操作 → 键位设置」改）翻成该动作的虚拟键注入：缺省 Ⓐ / RB 终结技（按住 = 虚拟键按住）、
##               Ⓑ / RT 冲刺、LB / LT 指挥圆盘（按住）、START 暂停、SELECT 属性面板
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
	"game_menu": {
		JOY_BUTTON_A: KEY_ENTER, JOY_BUTTON_B: KEY_ESCAPE, JOY_BUTTON_START: KEY_ESCAPE, JOY_BUTTON_BACK: KEY_TAB,
		JOY_BUTTON_Y: KEY_F, JOY_BUTTON_LEFT_SHOULDER: KEY_PAGEUP, JOY_BUTTON_RIGHT_SHOULDER: KEY_PAGEDOWN,
	},
}
## 对局里：按钮 → 动作（core/play_keys.gd，可改键）→ 注入该动作的虚拟键；按住型动作按住期间保持虚拟键按下，全部松开才发松开
const PlayKeys = preload("res://scripts/core/play_keys.gd")
const Bal = preload("res://scripts/core/balance.gd")
var _holds := {}               # 按住中的按住型动作：动作 → {按钮: true}
const DPAD := {JOY_BUTTON_DPAD_UP: Vector2i(0, -1), JOY_BUTTON_DPAD_DOWN: Vector2i(0, 1), JOY_BUTTON_DPAD_LEFT: Vector2i(-1, 0), JOY_BUTTON_DPAD_RIGHT: Vector2i(1, 0)}
## 扳机键当作肩键
const TRIGGER_AS := {JOY_AXIS_TRIGGER_LEFT: JOY_BUTTON_LEFT_SHOULDER, JOY_AXIS_TRIGGER_RIGHT: JOY_BUTTON_RIGHT_SHOULDER}

## 手柄提示用的按键名（Xbox 布局；PlayStation / Switch 手柄按位置对应）
const GLYPH := {"A": "Ⓐ", "B": "Ⓑ", "X": "Ⓧ", "Y": "Ⓨ", "START": "START", "SELECT": "SELECT", "LB": "LB", "RB": "RB", "STICK": "左摇杆", "DPAD": "十字键"}


var sim := false               # 测试：--padsim 时把 device 0 当作已连接（tests/pad_sim.gd 注入事件）
## 触屏设备（开启条件同 touch.gd）：提示文字换成点按版、不画键位牌；接上手柄后（using）仍以手柄提示为准
var touch := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.joy_connection_changed.connect(_on_joy_changed)
	touch = Cfg.touch_device()
	if Cfg.dev_args().has("--padsim"):
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
		if context == "play":
			_play_btn(event.button_index, event.pressed)
			return
		_release_holds()   # 按住终结技 / 圆盘键时离开对局（选卡弹出等）：补一个松开
		if event.pressed and not _menu_action(event.button_index, event.button_index):
			_press_button(event.button_index)
	elif event is InputEventJoypadMotion:
		if absf(event.axis_value) > 0.5:
			device = event.device
			_set_using(true)
		if TRIGGER_AS.has(event.axis):
			var was: bool = _trig[event.axis]
			track_trigger(event.axis, event.axis_value)
			var on: bool = _trig[event.axis]
			if on != was and context == "play":
				_play_btn(PlayKeys.PAD_LT if event.axis == JOY_AXIS_TRIGGER_LEFT else PlayKeys.PAD_RT, on)   # 对局里扳机按按键表（缺省 LT 圆盘 / RT 冲刺）
			elif on and not was:
				if not _menu_action(PlayKeys.PAD_LT if event.axis == JOY_AXIS_TRIGGER_LEFT else PlayKeys.PAD_RT, TRIGGER_AS[event.axis]):
					_press_button(TRIGGER_AS[event.axis])
	elif event is InputEventKey or event is InputEventScreenTouch:
		_set_using(false)
	elif event is InputEventMouseMotion:
		if event.relative.length() > 6.0:
			_set_using(false)
	elif event is InputEventMouseButton:
		_set_using(false)


## 扳机滞回（按下 > 0.6、松开 < 0.3）：更新 _trig，返回这一下是不是「刚按下」。
## 键位页（screens/keybind_view.gd）等新按键时吞掉扳机事件，也要调它，否则 _trig 没更新，之后扳机被当成新按下（docs/356 §3-3）
func track_trigger(axis: int, value: float) -> bool:
	var was: bool = _trig.get(axis, false)
	var on: bool = value > (0.3 if was else 0.6)
	_trig[axis] = on
	return on and not was


## 对局菜单里（属性面板 / 暂停）：按钮改绑到「属性面板」「暂停」上时，同一个键也能关掉面板 / 继续（docs/356 §3-4）。
## menu_of 由 game.gd 每帧设（"stats" / "pause" / ""）；菜单里这个按钮缺省是 Enter（确认）时不抢，菜单照常能用
var menu_of := ""

func _menu_action(code: int, b: int) -> bool:
	if context != "game_menu" or menu_of == "":
		return false
	if int(MAP.get(context, {}).get(b, KEY_NONE)) == KEY_ENTER:
		return false
	var id: String = PlayKeys.pad_action(code)
	if id == "" or not (id == menu_of or (menu_of == "stats" and id == "pause")):
		return false
	tap(PlayKeys.vk(id))
	return true


func _press_button(b: int) -> void:
	var m: Dictionary = MAP.get(context, {})
	if m.has(b):
		tap(m[b])


## 注入一次按键（按下 + 松开）
func tap(k: int) -> void:
	_key(k, true)
	_key(k, false)


## 注入单个按下 / 松开事件（终结技按住瞄准要分开发：game.gd 收到 Q 的松开才放出）
func _key(k: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.device = SYNTH_DEVICE
	ev.keycode = k
	ev.physical_keycode = k
	ev.pressed = down
	Input.parse_input_event(ev)


## 终结技总开关（与 game.gd 建 g.ult 的条件 Ult.on() 相同；不预载 run/ult.gd，免得手柄单例把整套终结技脚本拉进来）
static func ult_on() -> bool:
	return Bal.vi("ult/on", 1) > 0


## 对局里一个按钮（含扳机 PAD_LT / PAD_RT）按下 / 松开：按键表查动作；按住型第一个按下时发虚拟键按下、全部松开时发松开
## （两个键一起按、先后松开也只放一次）；其余按下时注入一次
func _play_btn(b: int, down: bool) -> void:
	var id: String = PlayKeys.pad_action(b)
	if id == "":
		if b == JOY_BUTTON_Y and down:
			tap(KEY_T)   # 主题机制键（萨米密文板宣告，docs/411）：Y 在对局里没绑动作时注入 T；没有这类机制的主题 T 在对局中不做事
		return
	var vk: int = PlayKeys.vk(id)
	if not PlayKeys.is_hold(id):
		if down:
			tap(vk)
		return
	var hs: Dictionary = _holds.get(id, {})
	var was: bool = not hs.is_empty()
	if down:
		hs[b] = true
	else:
		hs.erase(b)
	_holds[id] = hs
	var now: bool = not hs.is_empty()
	if now != was:
		_key(vk, now)


func _release_holds() -> void:
	for id in _holds:
		if not (_holds[id] as Dictionary).is_empty():
			_key(PlayKeys.vk(str(id)), false)
	_holds.clear()


func _process(dt: float) -> void:
	if context != "play" and not _holds.is_empty():
		_release_holds()
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


## 按键事件的键（10-14，「ESC 不起作用、键盘输入有问题」）：中文输入法开着时，网页（浏览器把 key 报成 "Process"）
## 和部分系统发来的按键 keycode = 0、只有物理键码——原来各界面 match event.keycode 一律对不上，Esc / 方向键全无反应。
## keycode 为 0 时按物理键码换算成当前键盘布局的键；同时记下「见过这种事件」，之后轮询（key_down）也认物理键。
var phys_keys := false


func kc(event: InputEventKey) -> int:
	if event.keycode != KEY_NONE:
		return event.keycode
	if event.physical_keycode == KEY_NONE:
		return KEY_NONE
	phys_keys = true
	var k: int = DisplayServer.keyboard_get_keycode_from_physical(event.physical_keycode)
	return k if k != KEY_NONE else event.physical_keycode


## 轮询按键（移动 / 冲刺 / 手动技能）：平时只认逻辑键；见过 keycode = 0 的事件后再认物理键
## （只在那之后才认，免得 AZERTY 等布局下物理键位和逻辑键打架）
func key_down(k: int) -> bool:
	return Input.is_key_pressed(k) or (phys_keys and Input.is_physical_key_pressed(k))


## 提示文字：用手柄时返回 pad_text；触屏（没在用手柄）且给了 touch_text 时返回它；否则 key_text
func hint(key_text: String, pad_text: String, touch_text: Variant = null) -> String:
	if using:
		return pad_text
	return str(touch_text) if touch and touch_text != null else key_text


## 触屏界面：不显示键盘键位（键位牌、「[ 1 ]」、「Enter」之类）
func touch_ui() -> bool:
	return touch and not using
