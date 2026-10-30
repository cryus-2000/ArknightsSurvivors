extends RefCounted
## 触屏按键布局（用户 10-13：「冲刺键之类的也可以在设置中自己改按键大小和位置」）：摇杆、冲刺、技能、瞄准、暂停、属性、倍速
## 七个触屏控件的缺省位置、玩家自定义位置 / 大小的存取，以及夹进安全区。touch.gd（局内绘制与点击）和
## screens/touch_editor.gd（设置里的编辑页）都只经过这里算位置，两边看到的一定一致。
##
## 坐标一律是 UI 逻辑坐标（界面层放大 Cfg.ui_k 之后，vs = g.hud.size / 标题页 size）。
## 自定义位置按「相对锚点」存：横向记离左边或右边（取近的那边）多远，纵向记离上边或下边多远；
## 换一台比例不同的设备（19.5:9 手机 → 4:3 平板）时按钮仍贴着原来那条边，最后再夹进安全区，不会跑出屏幕。
## 存档：settings.cfg 的 [touch] layout = {键: {ax, ay, x, y, s}}；没有的键用缺省位置、缩放 1。
## 瞄准键（键名沿用 "atk"，旧存档不用迁移）可以隐藏：layout 里 "atk_off": true（10-31 取消手动普攻后它只是可选的按住瞄准）。

const KEYS := ["stick", "dash", "skill", "atk", "pause", "stats", "speed", "cmd"]
const NAMES := {"stick": "移动摇杆", "dash": "冲刺", "skill": "技能", "atk": "瞄准", "pause": "暂停", "stats": "属性", "speed": "倍速", "cmd": "指挥"}
const S_MIN := 0.7
const S_MAX := 1.5
const S_STEP := 0.05
const BTN := 46.0              # 与 touch.gd 的 BTN 相同：按钮基准直径
const RADIUS := 64.0           # 摇杆最大行程（touch.gd RADIUS）
const MARGIN := 8.0            # 安全区内再往里留的边
## 编队区顶边离画面底边的距离 = hud_squad.squad_top 里的 16 + 卡高 96 + 技能行 24 + 14 + 46（测试核对两边一致）
const SQUAD_TOP_UP := 196.0
## 两个控件中心至少相隔（两者半径和 × 这个比例）：允许边缘稍微叠一点，不许整个盖住另一个
const MIN_GAP := 0.75


## 控件在缩放 1 时的外形半径（圆形按钮的半径；倍速是矩形，取半宽）
static func radius(key: String) -> float:
	match key:
		"stick":
			return 40.0
		"dash", "skill":
			return BTN * 0.7
		"atk":
			return BTN * 0.62
		"pause", "stats", "cmd":
			return BTN / 2.0
		"speed":
			return 28.0
	return 24.0


## 控件（含下方的文字标签）相对中心的外框：夹进安全区、编辑页画选中框都用它
static func bounds(key: String, s: float) -> Rect2:
	var r: float = radius(key) * s
	match key:
		"pause", "stats", "cmd":
			return Rect2(-maxf(r, 30.0 * s), -r, maxf(r, 30.0 * s) * 2.0, r * 2.0 + 20.0 * s)
		"skill":
			return Rect2(-maxf(r, 40.0), -r, maxf(r, 40.0) * 2.0, r * 2.0 + 22.0)
		"speed":
			return Rect2(-28.0 * s, -17.0 * s, 56.0 * s, 34.0 * s + 18.0 * s)
	return Rect2(-r, -r, r * 2.0, r * 2.0)


## 安全区（UI 坐标）：视口去掉系统安全边距（刘海 / 灵动岛 / 底部横条，Cfg.safe_insets），再往里留 MARGIN
static func safe_rect(vs: Vector2, ins: Array = [0.0, 0.0, 0.0, 0.0]) -> Rect2:
	var l: float = float(ins[0]) + MARGIN
	var t: float = float(ins[1]) + MARGIN
	var r: float = float(ins[2]) + MARGIN
	var b: float = float(ins[3]) + MARGIN
	return Rect2(l, t, maxf(1.0, vs.x - l - r), maxf(1.0, vs.y - t - b))


## 中心点夹进安全区：控件外框（bounds）整个在 safe 里；安全区比控件还小时居中
static func clamp_center(c: Vector2, key: String, s: float, safe: Rect2) -> Vector2:
	var bx: Rect2 = bounds(key, s)
	var lo: Vector2 = safe.position - bx.position
	var hi: Vector2 = safe.end - bx.end
	var out := c
	out.x = clampf(c.x, lo.x, hi.x) if lo.x <= hi.x else (lo.x + hi.x) / 2.0
	out.y = clampf(c.y, lo.y, hi.y) if lo.y <= hi.y else (lo.y + hi.y) / 2.0
	return out


## 存档格式：离近的那条边多远（UI 像素）+ 缩放
static func encode(c: Vector2, vs: Vector2, s: float) -> Dictionary:
	var ax: int = 0 if c.x < vs.x / 2.0 else 1
	var ay: int = 0 if c.y < vs.y / 2.0 else 1
	return {"ax": ax, "ay": ay, "x": roundf(c.x if ax == 0 else vs.x - c.x), "y": roundf(c.y if ay == 0 else vs.y - c.y), "s": clamp_scale(s)}


static func decode(d: Dictionary, vs: Vector2) -> Vector2:
	var x: float = float(d.get("x", 0.0))
	var y: float = float(d.get("y", 0.0))
	return Vector2(x if int(d.get("ax", 0)) == 0 else vs.x - x, y if int(d.get("ay", 0)) == 0 else vs.y - y)


static func clamp_scale(s: float) -> float:
	return clampf(snappedf(s, S_STEP), S_MIN, S_MAX)


## 读档清洗：只留认识的键；字段缺失 / 类型不对的条目丢掉（回到缺省位置）；数值夹到合理范围
static func sanitize(raw) -> Dictionary:
	var out := {}
	if not (raw is Dictionary):
		return out
	for k in KEYS:
		var e = raw.get(k)
		if not (e is Dictionary):
			continue
		var ok := true
		for f in ["ax", "ay", "x", "y"]:
			if not (e.get(f) is int or e.get(f) is float):
				ok = false
		if not ok:
			continue
		var s = e.get("s", 1.0)
		out[k] = {"ax": clampi(int(e.ax), 0, 1), "ay": clampi(int(e.ay), 0, 1),
			"x": clampf(float(e.x), 0.0, 4000.0), "y": clampf(float(e.y), 0.0, 4000.0),
			"s": clamp_scale(float(s) if (s is int or s is float) else 1.0)}
	if atk_hidden(raw):
		out["atk_off"] = true
	return out


static func save_to(c: ConfigFile, layout: Dictionary) -> void:
	c.set_value("touch", "layout", sanitize(layout))


## 瞄准键是否被玩家隐藏
static func atk_hidden(layout: Dictionary) -> bool:
	return layout.get("atk_off", false) == true


static func load_from(c: ConfigFile) -> Dictionary:
	return sanitize(c.get_value("touch", "layout", {}))


## 各控件的缺省中心（缩放 1）。技能 / 攻击键跟着冲刺键走（冲刺键被挪过时，它们的缺省位置相对新位置算）
static func default_center(key: String, vs: Vector2, atk_on: bool, dash_c := Vector2.INF, phone := false) -> Vector2:
	var ph: bool = vs.y < 520.0 or phone   # 手机横屏（Cfg.phone_ui，或界面逻辑高 < 520）
	var dash := Vector2(vs.x - (134.0 if ph else 80.0), vs.y - SQUAD_TOP_UP - 14.0 - BTN * 0.7)
	if dash_c != Vector2.INF:
		dash = dash_c
	match key:
		"stick":
			return Vector2(maxf(250.0, vs.x * 0.2), vs.y - 150.0)
		"dash":
			return dash
		"skill":
			# 显示瞄准键时技能键在瞄准键正上方；瞄准键隐藏时在冲刺键左上斜方（正上方会撞「属性」键）
			return dash + (Vector2(-BTN * 1.85, -BTN * 1.85) if atk_on else Vector2(-BTN * 2.0, -BTN * 0.65))
		"atk":
			return dash + Vector2(-BTN * 1.85, -BTN * 0.05)
		"pause":
			# 手机 160（原 172）：「属性」键的标签不再压到编队区右侧的「源石锭」小字（10-13）
			return Vector2(vs.x - 46.0, 160.0 if ph else 186.0)
		"stats":
			return Vector2(vs.x - 46.0, (160.0 if ph else 186.0) + 86.0)
		"speed":
			return Vector2(vs.x - 44.0, 93.0)
		"cmd":
			# 指挥模式（docs/114）：暂停键左侧同一行——右手拇指够得到，离冲刺 / 技能键和编队区都远，不挡摇杆
			return Vector2(vs.x - 46.0 - 72.0, 160.0 if ph else 186.0)
	return vs / 2.0


## 解出全部控件的位置与缩放：{键: {"c": 中心, "s": 缩放, "custom": 是否玩家改过}}
static func resolve(vs: Vector2, atk_on: bool, custom: Dictionary, safe: Rect2, phone := false) -> Dictionary:
	var out := {}
	for k in ["dash", "stick", "skill", "atk", "pause", "stats", "speed", "cmd"]:
		var e = custom.get(k)
		var s := 1.0
		var c: Vector2
		if e is Dictionary:
			s = clamp_scale(float(e.get("s", 1.0)))
			c = decode(e, vs)
		else:
			c = default_center(k, vs, atk_on, out.dash.c if out.has("dash") else Vector2.INF, phone)
		out[k] = {"c": clamp_center(c, k, s, safe), "s": s, "custom": e is Dictionary}
	return out


## 两个控件是否「几乎整个叠在一起」（中心距 < 两者半径和 × MIN_GAP）
static func too_close(a: Vector2, ka: String, sa: float, b: Vector2, kb: String, sb: float) -> bool:
	return a.distance_to(b) < (radius(ka) * sa + radius(kb) * sb) * MIN_GAP


## 把 key 从其余控件旁边推开（编辑页松手时用）：沿连线推到刚好不算重叠，再夹回安全区；推几轮还分不开返回 Vector2.INF
static func separate(key: String, c: Vector2, s: float, others: Dictionary, safe: Rect2) -> Vector2:
	var p: Vector2 = clamp_center(c, key, s, safe)
	for it in 8:
		var moved := false
		for k in others:
			var o: Dictionary = others[k]
			if not too_close(p, key, s, o.c, k, o.s):
				continue
			var need: float = (radius(key) * s + radius(k) * o.s) * MIN_GAP + 1.0
			var d: Vector2 = p - o.c
			if d.length() < 0.01:
				d = Vector2(-1, 0) if o.c.x > safe.get_center().x else Vector2(1, 0)
			p = clamp_center(o.c + d.normalized() * need, key, s, safe)
			moved = true
		if not moved:
			return p
	for k in others:
		if too_close(p, key, s, others[k].c, k, others[k].s):
			return Vector2.INF
	return p
