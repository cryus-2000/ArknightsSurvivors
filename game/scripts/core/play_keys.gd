## 局内按键表（arch_review_1029 P0-2；11-16 用户「自由更改键位」）：局内「动作 → 键盘 / 鼠标 / 手柄」只在这里声明一次，
## game.gd（键盘 / 鼠标路由）、pad.gd（手柄注入）、doctor.gd（按住瞄准）、command_wheel.gd（按住圆盘）、HUD / 指南 / 引导的键名提示都查它。
##
## 每个动作两格（主键 + 备用键），键鼠一套、手柄一套；玩家在「设置 → 操作 → 键位设置」（screens/keybind_view.gd）里改，
## 存进 settings.cfg [input] keybinds，并随 B站云存档同步（settings.gd cloud_body「keybinds」，docs/89）。存档里只写和缺省不同的动作，
## 没写的动作 = 缺省，旧存档没有这项 = 全部缺省。
##
## 键码编码（一格一个 int）：0 = 空；> 0 = 键盘键码（Key）；< 0 = 鼠标键（-MouseButton，-1 左键 / -2 右键 / -3 中键 / -8 / -9 侧键）。
## 手柄格：JoyButton（Ⓐ = 0，所以手柄的空格记 -1）；扳机 LT / RT 记作 PAD_LT / PAD_RT（100 / 101）。
##
## 手柄在对局里（Pad.context == "play"）按绑定翻成「虚拟键」（VK_BASE + 动作序号，F25 起，真键盘没有）注入，game.gd 认虚拟键 = 该动作；
## 按住型动作（终结技 / 指挥圆盘）手柄按住期间保持虚拟键按下。界面导航（确认 / 返回 / 方向）不在这里，保持缺省、不开放。
##
## 固定不可改：Esc（暂停 / 返回，防止改键把自己锁死）占「暂停」主键格；手柄 START 占「暂停」主键格；左摇杆移动、右摇杆瞄准。
## 普攻没有键（10-31 取消手动普攻）：永远自动，「瞄准」= 按住朝光标打（缺省鼠标左键）。
## ult/on = 0 的旧手动技能路由：手动技能用「终结技」那一格的绑定（键盘 Q / 手柄 Ⓐ RB）。
extends RefCounted

const Loc = preload("res://scripts/core/loc.gd")

const M_LEFT := -1
const M_RIGHT := -2
const M_MIDDLE := -3
const M_X1 := -8
const M_X2 := -9
const PAD_LT := 100
const PAD_RT := 101
const SYNTH_DEVICE := 7777     # 与 pad.gd 相同：注入事件的 device
const VK_BASE := KEY_F25       # 手柄注入的虚拟键：VK_BASE + ORDER 下标

## 动作（设置页按这个顺序列）。kb / pad：缺省两格；pad 为 null = 手柄这一项固定（摇杆），不在手柄页改。
## hold：按住型（轮询 held()）；name：设置页 / 提示里的动作名（中文原文，显示时 Loc.s）
const ACTIONS := [
	{"id": "up", "name": "向上移动", "kb": [KEY_W, KEY_UP], "pad": null, "hold": true},
	{"id": "down", "name": "向下移动", "kb": [KEY_S, KEY_DOWN], "pad": null, "hold": true},
	{"id": "left", "name": "向左移动", "kb": [KEY_A, KEY_LEFT], "pad": null, "hold": true},
	{"id": "right", "name": "向右移动", "kb": [KEY_D, KEY_RIGHT], "pad": null, "hold": true},
	{"id": "dash", "name": "冲刺", "kb": [KEY_SPACE, KEY_SHIFT], "pad": [JOY_BUTTON_B, PAD_RT], "hold": false},
	{"id": "ult", "name": "终结技", "kb": [KEY_Q, 0], "pad": [JOY_BUTTON_A, JOY_BUTTON_RIGHT_SHOULDER], "hold": true},
	{"id": "aim", "name": "按住瞄准", "kb": [M_LEFT, 0], "pad": null, "hold": true},
	{"id": "command", "name": "指挥圆盘", "kb": [KEY_F, 0], "pad": [JOY_BUTTON_LEFT_SHOULDER, PAD_LT], "hold": true},
	{"id": "speed", "name": "倍速", "kb": [KEY_V, 0], "pad": [-1, -1], "hold": false},
	{"id": "stats", "name": "属性面板", "kb": [KEY_TAB, KEY_C], "pad": [JOY_BUTTON_BACK, -1], "hold": false},
	{"id": "pause", "name": "暂停", "kb": [KEY_ESCAPE, KEY_P], "pad": [JOY_BUTTON_START, -1], "hold": false, "lock0": true},
	{"id": "music", "name": "音乐开关", "kb": [KEY_M, 0], "pad": [-1, -1], "hold": false},
]
## 手柄页固定项（只显示、不能改）
const PAD_FIXED := [["移动", "左摇杆"], ["按住瞄准", "右摇杆"]]

## 兼容旧接口（squad_v2_test 读 ULT.has("combo")）：缺省表的手柄部分
const ULT := {
	"ult": {"keys": [KEY_Q], "pad": [JOY_BUTTON_A, JOY_BUTTON_RIGHT_SHOULDER], "hold": true, "touch": "skill"},
	"dash": {"keys": [KEY_SPACE, KEY_SHIFT], "pad": [JOY_BUTTON_B], "hold": false, "touch": "dash"},
	"command": {"keys": [KEY_F], "pad": [JOY_BUTTON_LEFT_SHOULDER], "hold": true, "touch": ""},
}

static var _kb := {}           # 动作 → [格0, 格1]（当前生效）
static var _pad := {}
static var _inited := false


## 空格的编码：键鼠 0，手柄 -1（JOY_BUTTON_A = 0）
static func none(pad: bool) -> int:
	return -1 if pad else 0


static func _init_tables() -> void:
	if _inited:
		return
	_inited = true
	reset_all()


static func def_of(id: String) -> Dictionary:
	for a in ACTIONS:
		if a.id == id:
			return a
	return {}


static func ids() -> Array:
	return ACTIONS.map(func(a): return a.id)


static func pad_ids() -> Array:
	return ACTIONS.filter(func(a): return a.pad != null).map(func(a): return a.id)


static func index_of(id: String) -> int:
	for i in ACTIONS.size():
		if ACTIONS[i].id == id:
			return i
	return -1


static func reset_all() -> void:
	reset_page(false)
	reset_page(true)


## 「恢复默认」：一页（键鼠 / 手柄）全部回到缺省
static func reset_page(pad: bool) -> void:
	_inited = true
	var t := {}
	for a in ACTIONS:
		if pad and a.pad == null:
			continue
		t[a.id] = (a.pad if pad else a.kb).duplicate()
	if pad:
		_pad = t
	else:
		_kb = t


static func get_slots(id: String, pad: bool) -> Array:
	_init_tables()
	return ((_pad if pad else _kb).get(id, [none(pad), none(pad)]) as Array).duplicate()


## 格子能不能改（Esc / START 那一格锁定）
static func locked(id: String, slot: int) -> bool:
	return slot == 0 and bool(def_of(id).get("lock0", false))


static func set_slot(id: String, pad: bool, slot: int, code: int) -> void:
	_init_tables()
	var t: Dictionary = _pad if pad else _kb
	if not t.has(id) or locked(id, slot):
		return
	var s: Array = t[id]
	s[slot] = code


## 某个键码已经被哪一格占着：[动作, 格] 或 []（except_id / except_slot 排除自己）
static func owner_of(code: int, pad: bool, except_id := "", except_slot := -1) -> Array:
	_init_tables()
	if code == none(pad):
		return []
	var t: Dictionary = _pad if pad else _kb
	for a in ACTIONS:
		if not t.has(a.id):
			continue
		var s: Array = t[a.id]
		for i in 2:
			if int(s[i]) == code and not (a.id == except_id and i == except_slot):
				return [a.id, i]
	return []


## 绑定一格（处理冲突）：code 已被别的格占 → swap = true 时两格互换（对方拿到这一格原来的键），
## 返回 [] = 已绑定；返回 [动作, 格] = 有冲突且没交换（界面先问「已被『X』占用，交换？」）
static func bind(id: String, pad: bool, slot: int, code: int, swap := false) -> Array:
	if locked(id, slot):
		return []
	var who: Array = owner_of(code, pad, id, slot)
	if not who.is_empty():
		if locked(str(who[0]), int(who[1])):
			return who   # 对方是锁定格（Esc / START）：不能换；界面在 forbidden() 里已先拦掉 Esc
		if not swap:
			return who
		var old: int = int(get_slots(id, pad)[slot])
		set_slot(str(who[0]), pad, int(who[1]), old)
	set_slot(id, pad, slot, code)
	return []


## 不许绑的键（返回原因，"" = 可以）：Esc 固定暂停 / 返回；Win / Meta 会切走窗口；滚轮没有「按住」；
## 网页版浏览器保留键（F5 刷新、F11 全屏、F12 开发者工具、Ctrl / Alt 组合会触发 Ctrl+W 关页之类、鼠标侧键 = 前进后退）
static func forbidden(code: int, pad: bool, web := OS.has_feature("web")) -> String:
	if pad:
		return "该按键固定为暂停" if code == JOY_BUTTON_START else ""
	match code:
		KEY_ESCAPE:
			return "Esc 固定为暂停 / 返回"
		KEY_META, KEY_PRINT:
			return "该按键不能绑定"
	if web:
		if code in [KEY_F1, KEY_F3, KEY_F5, KEY_F6, KEY_F7, KEY_F11, KEY_F12, KEY_CTRL, KEY_ALT, M_X1, M_X2]:
			return "浏览器保留此键，网页版不能绑定"
	return ""


## ── 存档 ──
## 和缺省不同的动作：{"kb": {动作: [a, b]}, "pad": {动作: [a, b]}}；全缺省 = {}
static func overrides() -> Dictionary:
	_init_tables()
	var out := {}
	for page in ["kb", "pad"]:
		var p: bool = page == "pad"
		var d := {}
		for a in ACTIONS:
			if p and a.pad == null:
				continue
			var cur: Array = get_slots(a.id, p)
			if cur != (a.pad if p else a.kb):
				d[a.id] = cur
		if not d.is_empty():
			out[page] = d
	return out


## 读存档 / 云存档：缺的动作用缺省；类型不对、锁定格、不许绑的键、两格重复的都丢掉（回到缺省）
static func apply(over) -> void:
	reset_all()
	if not (over is Dictionary):
		return
	for page in ["kb", "pad"]:
		var p: bool = page == "pad"
		var d = over.get(page)
		if not (d is Dictionary):
			continue
		for id in d:
			var a: Dictionary = def_of(str(id))
			if a.is_empty() or (p and a.pad == null) or not (d[id] is Array) or (d[id] as Array).size() != 2:
				continue
			var s: Array = []
			for i in 2:
				var v = d[id][i]
				s.append(int(v) if (v is int or v is float) else none(p))
				if p and s[i] < -1:
					s[i] = -1
			if locked(a.id, 0):
				s[0] = (a.pad if p else a.kb)[0]
			if s[1] != none(p) and (forbidden(s[1], p, false) != "" or s[1] == s[0]):
				s[1] = none(p)
			if not locked(a.id, 0) and s[0] != none(p) and forbidden(s[0], p, false) != "":
				s[0] = none(p)
			(_pad if p else _kb)[a.id] = s
	# 跨动作重复（手改存档 / 版本差异）：后出现的那格清空
	for p in [false, true]:
		var seen := {}
		for a in ACTIONS:
			var t: Dictionary = _pad if p else _kb
			if not t.has(a.id):
				continue
			for i in 2:
				var c: int = int(t[a.id][i])
				if c == none(p):
					continue
				if seen.has(c) and not locked(a.id, i):
					t[a.id][i] = none(p)
				else:
					seen[c] = true


## 清洗后的副本（云存档写出前用）
static func sanitize(over) -> Dictionary:
	var keep_kb := _kb.duplicate(true)
	var keep_pad := _pad.duplicate(true)
	apply(over)
	var out := overrides()
	_kb = keep_kb
	_pad = keep_pad
	return out


## ── 路由 ──
## 事件对应的动作（键盘 / 鼠标键 / 手柄注入的虚拟键；不在表里返回 ""）。按下 / 松开都认
static func act(event: InputEvent) -> String:
	_init_tables()
	if event is InputEventKey:
		var k: int = _kc(event)
		if k >= VK_BASE and k < VK_BASE + ACTIONS.size():
			return str(ACTIONS[k - VK_BASE].id)
		return _find(k)
	if event is InputEventMouseButton:
		return _find(-int(event.button_index))
	return ""


static func _find(code: int) -> String:
	if code == 0:
		return ""
	for a in ACTIONS:
		if code in (_kb.get(a.id, []) as Array):
			return a.id
	return ""


## 手柄按钮（含 PAD_LT / PAD_RT）→ 动作
static func pad_action(b: int) -> String:
	_init_tables()
	for a in ACTIONS:
		if _pad.has(a.id) and b in (_pad[a.id] as Array):
			return a.id
	return ""


static func vk(id: String) -> int:
	return VK_BASE + index_of(id)


static func is_hold(id: String) -> bool:
	return bool(def_of(id).get("hold", false))


## 此刻是否按着该动作：键盘键 / 鼠标键 / 手柄（注入的虚拟键 + 直接查按钮）。mouse = false 时不算鼠标键（瞄准要单独判 HUD 按钮）
static func held(id: String, mouse := true) -> bool:
	_init_tables()
	var phys: bool = _phys()
	for c in (_kb.get(id, []) as Array):
		var code: int = int(c)
		if code > 0:
			if Input.is_key_pressed(code) or (phys and Input.is_physical_key_pressed(code)):
				return true
		elif code < 0 and mouse:
			if Input.is_mouse_button_pressed(-code):
				return true
	if Input.is_key_pressed(vk(id)):
		return true
	return held_pad(id)


## 只看鼠标键那几格
static func held_mouse(id: String) -> bool:
	_init_tables()
	for c in (_kb.get(id, []) as Array):
		if int(c) < 0 and Input.is_mouse_button_pressed(-int(c)):
			return true
	return false


static func held_pad(id: String) -> bool:
	if not _pad.has(id):
		return false
	for dev in Input.get_connected_joypads():
		for c in (_pad[id] as Array):
			var b: int = int(c)
			if b == PAD_LT or b == PAD_RT:
				if Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_LEFT if b == PAD_LT else JOY_AXIS_TRIGGER_RIGHT) > 0.3:
					return true
			elif b >= 0 and Input.is_joy_button_pressed(dev, b):
				return true
	return false


## 按键事件的键（同 Pad.kc：中文输入法下 keycode = 0 时按物理键换算）
static func _kc(event: InputEventKey) -> int:
	if event.keycode != KEY_NONE:
		return event.keycode
	if event.physical_keycode == KEY_NONE:
		return KEY_NONE
	var k: int = DisplayServer.keyboard_get_keycode_from_physical(event.physical_keycode)
	return k if k != KEY_NONE else event.physical_keycode


static func _phys() -> bool:
	var ml = Engine.get_main_loop()
	var p = ml.root.get_node_or_null("Pad") if ml is SceneTree else null
	return p != null and bool(p.get("phys_keys"))


static func _pad_using() -> bool:
	var ml = Engine.get_main_loop()
	var p = ml.root.get_node_or_null("Pad") if ml is SceneTree else null
	return p != null and bool(p.get("using"))


## 兼容旧接口：键盘键 → 动作名（ult_on 不再区分）
static func action_of(k: int, _ult_on := true) -> String:
	_init_tables()
	return _find(k)


## 兼容旧接口：手柄按钮 → [虚拟键, 是否按住型]；不在表里返回 []
static func pad_key(b: int, _ult_on := true) -> Array:
	var id := pad_action(b)
	return [] if id == "" else [vk(id), is_hold(id)]


## ── 键名 ──
const _KEY_TILE := {KEY_SPACE: "SPACE", KEY_SHIFT: "SHIFT", KEY_TAB: "TAB", KEY_ESCAPE: "ESC", KEY_ENTER: "ENTER", KEY_KP_ENTER: "ENTER",
	KEY_CTRL: "CTRL", KEY_ALT: "ALT", KEY_BACKSPACE: "BACKSPACE", KEY_CAPSLOCK: "CAPS", KEY_UP: "↑", KEY_DOWN: "↓", KEY_LEFT: "←", KEY_RIGHT: "→",
	KEY_PAGEUP: "PGUP", KEY_PAGEDOWN: "PGDN", KEY_INSERT: "INS", KEY_DELETE: "DEL", KEY_HOME: "HOME", KEY_END: "END"}
## 正文里的写法（指南 / 引导句子里）：空格写「空格」（各语言查表），其余同键位牌但首字母大写
const _KEY_PROSE := {KEY_SPACE: "空格", KEY_SHIFT: "Shift", KEY_TAB: "Tab", KEY_ESCAPE: "Esc", KEY_ENTER: "Enter", KEY_KP_ENTER: "Enter", KEY_CTRL: "Ctrl", KEY_ALT: "Alt"}
const _MOUSE := {M_LEFT: "鼠标左键", M_RIGHT: "鼠标右键", M_MIDDLE: "鼠标中键", M_X1: "鼠标侧键 1", M_X2: "鼠标侧键 2"}
const _MOUSE_TILE := {M_LEFT: "左键", M_RIGHT: "右键", M_MIDDLE: "中键", M_X1: "侧键1", M_X2: "侧键2"}   # 键位牌里放不下「鼠标」两字
const _PAD := {JOY_BUTTON_A: "Ⓐ", JOY_BUTTON_B: "Ⓑ", JOY_BUTTON_X: "Ⓧ", JOY_BUTTON_Y: "Ⓨ", JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	PAD_LT: "LT", PAD_RT: "RT", JOY_BUTTON_BACK: "SELECT", JOY_BUTTON_START: "START", JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_GUIDE: "HOME", JOY_BUTTON_MISC1: "SHARE", JOY_BUTTON_PADDLE1: "P1", JOY_BUTTON_PADDLE2: "P2", JOY_BUTTON_PADDLE3: "P3", JOY_BUTTON_PADDLE4: "P4",
	JOY_BUTTON_TOUCHPAD: "TOUCHPAD"}


## 一格的显示名（已按当前语言翻好）。prose：句子里的写法
static func name_of(code: int, pad: bool, prose := false) -> String:
	if code == none(pad):
		return ""
	if pad:
		return str(_PAD.get(code, "#%d" % code))
	if code < 0:
		return Loc.s(str((_MOUSE if prose else _MOUSE_TILE).get(code, "鼠标键 %d" % -code)))
	if prose and _KEY_PROSE.has(code):
		return Loc.s(str(_KEY_PROSE[code]))
	if _KEY_TILE.has(code):
		return str(_KEY_TILE[code])
	var s := OS.get_keycode_string(code)
	return s.to_upper() if s.length() <= 3 else s


## 动作的主键名（键位牌 / 按键提示用；主键空就取备用；都空返回 ""）
static func primary(id: String, pad: bool, prose := false) -> String:
	for c in get_slots(id, pad):
		if int(c) != none(pad):
			return name_of(int(c), pad, prose)
	return ""


## 当前输入设备下的键名（同 Pad.hint：用手柄 → 手柄键名；触屏且给了 touch_text → 它；否则键鼠主键）。
## 手柄固定项：瞄准 = 右摇杆；没绑手柄键 = 「未绑定」
static func cur(id: String, touch_text: Variant = null, prose := false) -> String:
	var ml = Engine.get_main_loop()
	var p = ml.root.get_node_or_null("Pad") if ml is SceneTree else null
	if p != null and bool(p.get("using")):
		if def_of(id).get("pad") == null:
			return Loc.s("右摇杆") if id == "aim" else Loc.s("左摇杆")
		var pn := primary(id, true, prose)
		return pn if pn != "" else Loc.s("未绑定")
	if p != null and bool(p.get("touch")) and touch_text != null:
		return str(touch_text)
	var kn := primary(id, false, prose)
	return kn if kn != "" else Loc.s("未绑定")


## 动作两格都列（「Tab / C」）
static func both(id: String, pad: bool, prose := false) -> String:
	var out := PackedStringArray()
	for c in get_slots(id, pad):
		if int(c) != none(pad):
			out.append(name_of(int(c), pad, prose))
	return " / ".join(out)


## 按键提示（pad = 最近用的是手柄）；兼容旧接口
static func hint(action: String, _ult_on := true, pad := false) -> String:
	if action == "combo":
		return ""   # 11-05 E 键收回：连携没有键
	return primary(action, pad)


## 移动四向的写法：主键是 W A S D →「WASD」，否则四个键名连写；both = 再接备用（全是方向键 →「方向键」）
static func move_text(both_slots := false) -> String:
	var ids4 := ["up", "left", "down", "right"]
	var p := PackedStringArray()
	for id in ids4:
		p.append(name_of(int(get_slots(id, false)[0]), false, true))
	var s1 := "WASD" if Array(p) == ["W", "A", "S", "D"] else " ".join(p).strip_edges()
	if not both_slots:
		return s1
	var alt: Array = ids4.map(func(id): return int(get_slots(id, false)[1]))
	if alt == [KEY_UP, KEY_LEFT, KEY_DOWN, KEY_RIGHT]:
		return s1 + " / " + Loc.s("方向键")
	var q := PackedStringArray()
	for c in alt:
		if int(c) != 0:
			q.append(name_of(int(c), false, true))
	return s1 if q.is_empty() else s1 + " / " + " ".join(q)


## 把文案里的键名占位换成当前绑定（指南 / 引导 / 终结技说明共用）：
##   {move} {move2} {dash} {ult} {aim} {cmd} {speed} {stats} {stats2} {pause} {music}：键鼠写法（cmd = 指挥圆盘）
##   {p_dash} {p_ult} {p_cmd} {p_stats} {p_pause} {p_speed}：手柄写法（同一行里同时写键鼠和手柄时用）
## pad = true 时不带 p_ 的占位也给手柄写法（引导卡跟着最近的输入设备走）
static func fill(text: String, pad := false) -> String:
	if not text.contains("{"):
		return text
	var m := {"cmd": "command"}
	for tok in ["dash", "ult", "aim", "cmd", "speed", "stats", "pause", "music"]:
		var id: String = m.get(tok, tok)
		var usepad: bool = pad and def_of(id).get("pad") != null
		var nm := primary(id, usepad, true)
		if nm == "":
			nm = Loc.s("未绑定")
		text = text.replace("{%s}" % tok, nm)
		if text.contains("{p_%s}" % tok):
			var pn := primary(id, true, true) if def_of(id).get("pad") != null else ""
			text = text.replace("{p_%s}" % tok, pn if pn != "" else Loc.s("未绑定"))
	text = text.replace("{stats2}", both("stats", pad, true) if both("stats", pad, true) != "" else Loc.s("未绑定"))
	text = text.replace("{move2}", Loc.s("左摇杆") if pad else move_text(true))
	text = text.replace("{move}", Loc.s("左摇杆") if pad else move_text(false))
	return text
