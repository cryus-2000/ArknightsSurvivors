extends RefCounted
## 失焦保护（11-07 用户在 Toy 预览实测「点出网页之后会出现不太好操作的情况」，docs/317）：
## 网页失焦（点到页面外、切标签、B站 App 里切出再回来）时浏览器不再发按键 / 触点抬起，Godot 里的「按住」状态就卡住了——
## 移动键（Pad.key_down 轮询 Input.is_key_pressed）继续走、摇杆手指（touch.stick_id）继续推、圆盘按住 F 的那一下回来后被当成松开确认、
## 普攻 / 技能键一直算按着。回来以后按键还送不到画布（焦点停在页面别处），要先点一下画布。
## 这里统一处理：
##   1. 失焦（网页：window blur / visibilitychange hidden / pagehide，JS 计数，0.2 秒轮询；所有平台：NOTIFICATION_APPLICATION_FOCUS_OUT /
##      WM_WINDOW_FOCUS_OUT / APPLICATION_PAUSED）→ release()：取消圆盘与选点、清触屏按住状态、给仍按着的键和鼠标键补「松开」事件；
##   2. 网页版对局中失焦 → 自动暂停（选卡 / 商店等非对局状态下失焦：回到对局时补一次暂停）；回来时看到暂停菜单，点「继续」即可；
##   3. 网页回到前台（focus / visibilitychange visible）→ 把焦点还给画布（canvas.focus()），按键不用先点画布。
## 桌面版只做 1（不自动暂停）；带调试参数运行（测试 / 录像 / 批跑）时桌面上整段不动，--focustest 例外（tests/web_focus_test）。

const POLL := 0.2
## 补「松开」的键：移动（WASD / 方向键）、冲刺、技能、终结技、圆盘、普攻等局内按住会生效的键
const KEYS := [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_SHIFT, KEY_SPACE, KEY_F, KEY_Q, KEY_E, KEY_R, KEY_J, KEY_K, KEY_L, KEY_CTRL, KEY_ALT]

var g = null
var web := false
var _seen := 0
var _t := 0.0
var _pend := false          # 失焦时不在对局里：回到对局补一次暂停
var lost_n := 0             # 失焦处理过几次（测试读）

const JS_SETUP := """(function(){if(window.__syFocus)return;var F=window.__syFocus={lost:0};
function lost(){F.lost++;}
function back(){setTimeout(function(){try{var c=document.querySelector('canvas');if(c&&document.activeElement!==c)c.focus();}catch(e){}},0);}
addEventListener('blur',lost);addEventListener('pagehide',lost);addEventListener('focus',back);
document.addEventListener('visibilitychange',function(){if(document.hidden)lost();else back();});})()"""


func setup(game) -> void:
	g = game
	web = OS.has_feature("web")
	if not web:
		return
	JavaScriptBridge.eval(JS_SETUP, true)
	_seen = int(JavaScriptBridge.eval("window.__syFocus?window.__syFocus.lost:0", true))


## game._notification 转来：所有平台的失焦通知
func notify(what: int) -> void:
	if what == Node.NOTIFICATION_APPLICATION_FOCUS_OUT or what == Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == Node.NOTIFICATION_APPLICATION_PAUSED:
		lost()


func poll(delta: float) -> void:
	if web:
		_t += delta
		if _t >= POLL:
			_t = 0.0
			var n := int(JavaScriptBridge.eval("window.__syFocus?window.__syFocus.lost:0", true))
			if n != _seen:
				_seen = n
				lost()
	if _pend and g.state == g.S.PLAY:
		_pend = false
		g.state = g.S.PAUSE


## 失焦：清掉所有按住状态；网页版对局中自动暂停
func lost() -> void:
	if g == null:
		return
	if not web and not Cfg.dev_args().is_empty() and not Cfg.dev_args().has("--focustest"):
		return   # 桌面上带调试参数（测试 / 录像 / 批跑，窗口常在后台、焦点来回切）不动：免得把计划里打开的圆盘、合成的按键清掉
	lost_n += 1
	if web or Cfg.dev_args().has("--focuspause"):   # 先暂停再补「松开」：补的松开事件不会落到对局里（比如松开 Q 放出终结技）
		if g.state == g.S.PLAY:
			g.state = g.S.PAUSE
		elif g.state != g.S.PAUSE and g.state != g.S.DEAD and g.state != g.S.WIN:
			_pend = true
	release()


## 清掉按住状态（不触发任何操作：圆盘 / 选点是取消，不是确认）
func release() -> void:
	if g.wheel != null and g.wheel.is_open:
		g.wheel.cancel()
	if g.pick != null and g.pick.active:
		g.pick.cancel()
	if g.touch != null:
		g.touch.release_all()
	for k in KEYS:
		if Input.is_key_pressed(k) or Input.is_physical_key_pressed(k):
			var e := InputEventKey.new()
			e.keycode = k
			e.physical_keycode = k
			e.pressed = false
			Input.parse_input_event(e)
	for b in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		if Input.is_mouse_button_pressed(b):
			var m := InputEventMouseButton.new()
			m.button_index = b
			m.pressed = false
			m.position = g.get_viewport().get_mouse_position() if g.is_inside_tree() else Vector2.ZERO
			Input.parse_input_event(m)
	Input.flush_buffered_events()
