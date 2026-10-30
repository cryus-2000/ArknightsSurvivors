## 局内按键表（arch_review_1029 P0-2）：局内「动作 → 键盘 / 手柄 / 触屏」只在这里声明一次，game.gd（键盘路由）、pad.gd（手柄注入）、
## HUD 按键提示都查它。手柄按钮在对局里先翻成表里的键盘键（pad.gd 注入合成按键），game.gd 只认键盘键。
## 两张表：ULT 开着（balance ult/on，docs/198 §2.4：Q 终结技、E 连携技）与 LEGACY（ult/on = 0 的旧手动技能路由，原样保留对照）。
## 现状订正（docs/198 §2.4 写的「Ⓨ 现在是 E、RB 沿用手动技能」不对）：旧映射里 Ⓐ / Ⓨ 都是 Q（手动技能），RB 是冲刺；
## 新映射 Ⓐ / RB = 终结技（按住瞄准），Ⓨ = 连携技，冲刺只剩 Ⓑ / RT。
## hold：手柄按住期间保持键盘键按下（瞄准类），松开才发松开事件；touch：触屏布局键名（touch_editor 布局存档里的名字，不改名不用迁移）。
## 普攻没有键（10-31 取消手动普攻）：永远自动，按住瞄准 = 鼠标左键 / 右摇杆 / 触屏瞄准键，由 doctor.aim_held 每帧直接读。
extends RefCounted

const ULT := {
	"ult": {"keys": [KEY_Q], "pad": [JOY_BUTTON_A, JOY_BUTTON_RIGHT_SHOULDER], "hold": true, "touch": "skill", "hint_key": "Q", "hint_pad": "RB/Ⓐ"},
	"combo": {"keys": [KEY_E], "pad": [JOY_BUTTON_Y], "hold": false, "touch": "skill", "hint_key": "E", "hint_pad": "Ⓨ"},
	"dash": {"keys": [KEY_SPACE, KEY_SHIFT, KEY_K], "pad": [JOY_BUTTON_B], "hold": false, "touch": "dash", "hint_key": "SPACE", "hint_pad": "Ⓑ"},
	"command": {"keys": [KEY_F], "pad": [JOY_BUTTON_LEFT_SHOULDER], "hold": false, "touch": "", "hint_key": "F", "hint_pad": "LB"},
}
const LEGACY := {
	"manual": {"keys": [KEY_Q, KEY_E, KEY_J], "pad": [JOY_BUTTON_A, JOY_BUTTON_Y, JOY_BUTTON_X], "hold": false, "touch": "skill", "hint_key": "Q/E", "hint_pad": "Ⓐ/Ⓨ"},
	"dash": {"keys": [KEY_SPACE, KEY_SHIFT, KEY_K], "pad": [JOY_BUTTON_B, JOY_BUTTON_RIGHT_SHOULDER], "hold": false, "touch": "dash", "hint_key": "SPACE", "hint_pad": "Ⓑ"},
	"command": {"keys": [KEY_F], "pad": [JOY_BUTTON_LEFT_SHOULDER], "hold": false, "touch": "", "hint_key": "F", "hint_pad": "LB"},
}


static func table(ult_on: bool) -> Dictionary:
	return ULT if ult_on else LEGACY


## 键盘键 → 动作名（不在表里返回 ""）
static func action_of(k: int, ult_on: bool) -> String:
	var t: Dictionary = table(ult_on)
	for a in t:
		if k in t[a].keys:
			return a
	return ""


## 手柄按钮 → [键盘键, 是否按住型]；不在表里返回 []
static func pad_key(b: int, ult_on: bool) -> Array:
	var t: Dictionary = table(ult_on)
	for a in t:
		if b in t[a].pad:
			return [int(t[a].keys[0]), bool(t[a].hold)]
	return []


## 按键提示（pad = 最近用的是手柄）
static func hint(action: String, ult_on: bool, pad: bool) -> String:
	var d: Dictionary = table(ult_on).get(action, {})
	return str(d.get("hint_pad" if pad else "hint_key", ""))
