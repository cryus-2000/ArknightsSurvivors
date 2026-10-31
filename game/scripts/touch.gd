## 触屏操作（移动端 / 网页版）：左半屏浮动虚拟摇杆（手指按下处即摇杆中心），右侧两个按钮（暂停 / 属性）。
## 终结技开着（g.ult != null，docs/198 §2.4）：技能键的位置换成右下大圆「终结技」键（按下 = 顿帧 + 慢动作瞄准，按住拖动选落点 / 方向，松手放出），
## 它左上一个小圆「连携」键（队友亮起时换成该队友头像，点按出手）；两键的样子由 screens/hud_ult.gd 画，这里只管位置与点按。
## 技能基本全自动；主控有手动技能时冲刺键上方多一个技能键（干员契约 v2.3 / v2.4：点一下 = 自动瞄准，按住拖动 = 朝拖动方向放）。面板 / 商店 / 结算里的按钮走 Godot 的"触摸模拟鼠标"，不在这里处理。
## 开启条件：Cfg.touch_device()（设备有触屏、网页 Android / iOS / iPad、或命令行 --touch）。
extends RefCounted

const UI = preload("res://scripts/ui.gd")
const TouchLayout = preload("res://scripts/touch_layout.gd")   # 各按键位置 / 大小（缺省 + 设置里的自定义，10-13）
const PlayClock = preload("res://scripts/run/play_clock.gd")
const TriBatch = preload("res://scripts/render/tri_batch.gd")
const Bal = preload("res://scripts/core/balance.gd")

const RADIUS := 64.0        # 摇杆最大行程
const DEAD := 10.0          # 死区
const BTN := 46.0           # 按钮直径
## 点击区最小边长（逻辑像素）：触屏缩放 1.15 后逻辑高 626，19.5:9 手机（342 pt 高）上 1 逻辑像素 ≈ 0.55 pt，84 ≈ 46 pt（触屏验收 10-01，iOS 44 pt）
const HIT := 84.0
## 摇杆起手离左边缘的死区（逻辑像素，≈ 20 pt）：iOS Safari 从左边缘右滑是「返回上一页」，贴边起手会把页面滑走（架构 10-01）
const EDGE := 36.0

var g
var active := false
var stick_id := -1          # 正在控制摇杆的触点
var stick_origin := Vector2.ZERO
var stick_pos := Vector2.ZERO
var vec := Vector2.ZERO
var btn_rects: Array = []   # [Rect2, action]
var flash := {}             # action -> 剩余高亮时间
## 手动技能键（主控有已解锁的手动技能时，冲刺键上方）：按下记触点，松手释放。
## 带方向的技能（JSON "aim": true）按住时拖出方向 skill_aim，场上画落点圈（hud.draw_manual_aim）；拖动不到 AIM_DEAD = 点一下 = 自动瞄准
const AIM_DEAD := 22.0
var skill_id := -1          # 正在按技能键的触点（-1 = 没按）
var skill_origin := Vector2.ZERO
var skill_aim := Vector2.ZERO
var skill_rect := Rect2()
## 瞄准键（10-31 取消手动普攻后的按住瞄准，冲刺键左侧；布局里可隐藏 TouchLayout.atk_hidden）：普攻永远自动，
## 按住并拖出方向写 doctor.touch_atk / touch_atk_dir，拖过 AIM_DEAD 才算按住瞄准（不拖 = 仍是自动）
var atk_id := -1
var atk_origin := Vector2.ZERO
var atk_drag := Vector2.ZERO
var atk_rect := Rect2()
## 终结技键 / 连携键（g.ult != null 时）：终结技键按下沿用 skill_id / skill_origin / skill_aim（同一个触点槽位），连携键点按即放
const ULT_AIM_REACH := 90.0   # 终结技键拖出这么远（界面像素）= 落点离队长 ULT_AIM_MAX
const ULT_AIM_MAX := 520.0    # 选落点最远（同 ult.gd _tick_ult 的夹取）
var ult_rect := Rect2()
var combo_rect := Rect2()
## 触点编号归一（10-12 手机端移动不了）：网页版 InputEventScreenTouch / Drag 的 index 就是浏览器的 Touch.identifier（Godot 按 i32 存）。
## Chrome 安卓从 0 起的小整数；iOS Safari 是全局累加的大数，超过 2^31 后变成负数——上面三个 *_id 用「≥ 0 = 正在按」判定，
## 负的触点按下后摇杆不画、move_vec 恒为零（主控走不动），技能键拖动 / 攻击键同样失灵。这里把原始 index 映射成 0 起的小槽位：
## 按下分配最小空槽，拖动查表，松手释放；没登记过的触点（按下没经过这里）返回 UNKNOWN，不会撞上任何 *_id
const UNKNOWN := -2
var _slots := {}            # 原始 index -> 槽位（0 起）
var _lay := {}              # 本帧的按键布局（TouchLayout.resolve），按帧缓存
var _lay_key: Array = []


func _init(game) -> void:
	g = game
	active = Cfg.touch_device()


func move_vec() -> Vector2:
	return vec if stick_id >= 0 else Vector2.ZERO


## 返回 true 表示事件已消费
func handle(event: InputEvent) -> bool:
	if not active or g.tour.active:   # 聚光框引导期间按键只是画给人看的，输入归 tour.gd
		return false
	var p := Vector2.ZERO   # 触点的 UI 坐标（界面层放大 Cfg.ui_k 后视口坐标要除回去）
	var fid := UNKNOWN   # 本事件的触点槽位（_finger 归一后的 index，见 _slots）
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		p = event.position / Cfg.ui_k
		fid = _finger(event)
	if event is InputEventScreenTouch:
		var vs: Vector2 = g.hud.size
		if event.pressed:
			if atk_rect.size.x > 0.0 and atk_id < 0 and _hit(atk_rect).has_point(p):
				atk_id = fid
				atk_origin = p
				atk_drag = Vector2.ZERO
				g.doctor.touch_atk = true
				g.doctor.touch_atk_dir = Vector2.ZERO
				return true
			# 终结技 / 连携键（ult/on）：两键点击区挨着，同时落在两个区里时取中心近的
			if g.ult != null and g.state == g.S.PLAY:
				var ur: Rect2 = _hit(ult_rect) if ult_rect.has_area() else Rect2()
				var cr: Rect2 = _hit(combo_rect) if combo_rect.has_area() else Rect2()
				var in_u: bool = ur.has_point(p) and skill_id < 0
				var in_c: bool = cr.has_point(p)
				if in_u and in_c:
					in_c = p.distance_to(combo_rect.get_center()) < p.distance_to(ult_rect.get_center())
					in_u = not in_c
				if in_c:
					g.ult.press_e()
					flash["combo"] = 0.2
					return true
				if in_u:
					skill_id = fid
					skill_origin = p
					skill_aim = Vector2.ZERO
					g.ult.press_q()   # 能量没满时什么也不发生；仍占住这个触点，拖动不会落到摇杆上
					return true
			# 技能键：按下只记触点，松手才释放（以后可以改成拖动瞄准）
			if skill_rect.size.x > 0.0 and skill_id < 0 and _hit(skill_rect).has_point(p):
				skill_id = fid
				skill_origin = p
				skill_aim = Vector2.ZERO
				return true
			# 按钮优先；点击区互相挨着时取中心最近的那个
			var hit_b: Array = []
			var hit_d := INF
			for b in btn_rects:
				if _hit(b[0]).has_point(p) and (b[0] as Rect2).get_center().distance_to(p) < hit_d:
					hit_d = (b[0] as Rect2).get_center().distance_to(p)
					hit_b = b
			if not hit_b.is_empty():
				_do(hit_b[1])
				flash[hit_b[1]] = 0.2
				return true
			# 属性面板：点图标 = 看效果（不消费，触摸模拟的鼠标移过去，悬停提示照常出）；点别处关闭
			if g.state == g.S.STATS:
				for c in g.stats_cells:
					if c[1] == "tab" and _hit(c[0]).has_point(p):
						# 触屏版属性面板的页签（属性 / 技能 / 编队）
						if g.stats_page != c[2]:
							g.stats_page = c[2]
							Sfx.play("ui_move")
						return true
				for c in g.stats_cells:
					if c[0].has_point(p):
						return false
				g.state = g.S.PLAY
				return true
			if g.state == g.S.PLAY and stick_id < 0 and _stick_zone(p, vs):
				stick_id = fid
				stick_origin = p
				stick_pos = p
				vec = Vector2.ZERO
				# 摇杆位置改过（设置 → 触屏按键布局）：按在摇杆圈内时以摇杆圈为中心（固定摇杆手感），圈外仍是按下处为中心
				var st: Dictionary = layout(vs).stick
				if st.custom and p.distance_to(st.c) <= stick_r() * 1.25:
					stick_origin = st.c
					_stick_move(p)
				return true
		else:
			if fid == atk_id:
				_atk_release()
				return true
			if fid == skill_id and g.ult != null:
				_ult_aim()
				skill_id = -1
				skill_aim = Vector2.ZERO
				flash["skill"] = 0.2
				g.ult.release_q()
				return true
			if fid == skill_id:
				skill_id = -1
				flash["skill"] = 0.2
				if g.state == g.S.PLAY:
					# 一定要传方向：不传会读摇杆移动方向，边走边点就朝走的方向放了。没就绪时它自己飘字说原因；正在出手时记下、1 秒内放出
					g.doctor.try_manual_skill(aim_dir())
				skill_aim = Vector2.ZERO   # 松手清掉拖动量：选落点圈读它（验收 P2：松手后圈停在旧位置）
				return true
			if fid == stick_id:
				stick_id = -1
				vec = Vector2.ZERO
				return true
	elif event is InputEventScreenDrag:
		if fid == atk_id:
			atk_drag = p - atk_origin
			g.doctor.touch_atk_dir = atk_drag if atk_drag.length() >= AIM_DEAD else Vector2.ZERO
			return true
		if fid == skill_id:
			skill_aim = p - skill_origin
			_ult_aim()
			return true
		if fid == stick_id:
			_stick_move(p)
			return true
	return false


## 摇杆手指移到 p：死区内不动；行程超出最大半径时中心跟着手指"拖走"，避免手指越滑越远
func _stick_move(p: Vector2) -> void:
	stick_pos = p
	var rr: float = stick_r()
	var d: Vector2 = stick_pos - stick_origin
	var l: float = d.length()
	if l < DEAD:
		vec = Vector2.ZERO
		return
	if l > rr:
		stick_origin = stick_pos - d / l * rr
		d = stick_pos - stick_origin
	vec = d / rr
	if vec.length() > 1.0:
		vec = vec.normalized()


## 在 p 处按下会不会起摇杆（command_wheel：圆盘开着时按在摇杆区，取消圆盘的同时把这次按下交给摇杆）
func wants_stick(p: Vector2) -> bool:
	return active and g.state == g.S.PLAY and stick_id < 0 and _stick_zone(p, g.hud.size)


## 摇杆最大行程（按布局缩放）
func stick_r() -> float:
	var L: Dictionary = _lay if not _lay.is_empty() else layout(g.hud.size)
	return RADIUS * float(L.stick.s)


## 能起摇杆的区域：摇杆在左半边时是左侧 55%（离左边缘 EDGE 以内不算，见 EDGE 注释），被挪到右半边时是右侧 55%
func _stick_zone(p: Vector2, vs: Vector2) -> bool:
	var st: Dictionary = layout(vs).stick
	if st.c.x < vs.x / 2.0:
		return p.x > EDGE and p.x < vs.x * 0.55
	return p.x < vs.x - EDGE and p.x > vs.x * 0.45


## 本帧的按键布局（TouchLayout.resolve）：{键: {c, s, custom}}；视口 / 自定义布局（含瞄准键隐藏）不变时复用
func layout(vs: Vector2) -> Dictionary:
	var atk_on: bool = not TouchLayout.atk_hidden(Cfg.touch_layout)
	var ph: bool = Cfg.phone_ui()
	var key: Array = [vs, atk_on, Cfg.touch_layout.hash(), Cfg.safe_insets().hash(), ph]
	if key != _lay_key:
		_lay_key = key
		_lay = TouchLayout.resolve(vs, atk_on, Cfg.touch_layout, Cfg.touch_safe_rect(vs), ph)
	return _lay


## 倍速键的矩形（hud_relics.draw_speed_button 画，这里管点击）
func speed_rect(vs: Vector2) -> Rect2:
	var sp: Dictionary = layout(vs).speed
	var sz: Vector2 = Vector2(56.0, 34.0) * float(sp.s)
	return Rect2(sp.c - sz / 2.0, sz)


## 原始触点 index → 槽位：按下分配（同一原始 index 重复按下沿用旧槽），松手返回槽位并释放，拖动只查表。
## 松手事件被别处吞掉（设置面板开着等）会留下陈旧登记：登记超过 8 个就整表清掉重来（同时按住的手指不会这么多）
func _finger(event: InputEvent) -> int:
	var raw: int = event.index
	if event is InputEventScreenTouch:
		if event.pressed:
			if not _slots.has(raw):
				if _slots.size() >= 8:
					_slots.clear()
				var used: Array = _slots.values()
				var s := 0
				while used.has(s):
					s += 1
				_slots[raw] = s
			return _slots[raw]
		var r: int = _slots.get(raw, UNKNOWN)
		_slots.erase(raw)
		return r
	return _slots.get(raw, UNKNOWN)


## 点击区：按钮图形外扩到至少 HIT 见方（图形本身更大时外扩 8）
static func _hit(r: Rect2) -> Rect2:
	var s := Vector2(maxf(r.size.x + 16.0, HIT), maxf(r.size.y + 16.0, HIT))
	return Rect2(r.get_center() - s / 2.0, s)


func _atk_release() -> void:
	atk_id = -1
	atk_drag = Vector2.ZERO
	g.doctor.touch_atk = false
	g.doctor.touch_atk_dir = Vector2.ZERO
	flash["atk"] = 0.15


## 终结技瞄准（g.ult 在瞄准慢动作里、终结技键按住且拖过死区）：选落点 = 队长位置 + 拖动方向 × 距离（拖 ULT_AIM_REACH = 最远 520）；
## 指方向 = 拖动方向。没拖过死区不写，用 ult.gd 的默认落点 / 方向（敌人最密处 / 敌人最多的一边）
func _ult_aim() -> void:
	var u = g.ult
	if u == null or skill_id < 0 or u.phase != "aim" or u.caster == null or skill_aim.length() < AIM_DEAD:
		return
	var d: Vector2 = skill_aim.normalized()
	if u.aim_kind == "point":
		u.aim = u.caster.pos + d * minf(ULT_AIM_MAX, skill_aim.length() / ULT_AIM_REACH * ULT_AIM_MAX)
	elif u.aim_kind == "dir":
		u.aim_dir = d


## 终结技键（技能键的位置，大一号）与连携键（它左上）的中心与半径：{"c", "r"}。触屏按键布局里改「技能」键就是改这两个键
func ult_btn(vs: Vector2) -> Dictionary:
	var e: Dictionary = layout(vs).skill
	return {"c": e.c, "r": BTN * 0.85 * float(e.s)}


func combo_btn(vs: Vector2) -> Dictionary:
	var u: Dictionary = ult_btn(vs)
	var r: float = u.r
	return {"c": u.c + Vector2(-r * 1.25 - 14.0, -r * 1.1 - 10.0), "r": BTN * 0.5 * r / (BTN * 0.85)}


## 技能键此刻的瞄准方向：拖动超过死区 = 拖动方向（不用归一化），否则 Vector2.ZERO = 自动瞄准
func aim_dir() -> Vector2:
	return skill_aim if skill_aim.length() >= AIM_DEAD else Vector2.ZERO


func _do(action: String) -> void:
	match action:
		"dash":
			g._try_dash()
		"pause":
			if g.state == g.S.PLAY:
				g.state = g.S.PAUSE
				Sfx.play("ui_ok", -6.0)
			elif g.state == g.S.PAUSE:
				g.state = g.S.PLAY
		"speed":
			if g.state == g.S.PLAY:
				PlayClock.cycle()
		"cmd":
			g.wheel.open(null, true)   # 触屏：点「指挥」键弹出圆盘，点选项确认、点空白处取消（docs/114 §13）
		"stats":
			if g.state == g.S.PLAY:
				g.state = g.S.STATS
				g.tab_used = true
				g.tab_hint = 0.0
				Sfx.play("ui_ok", -6.0)
			elif g.state == g.S.STATS:
				g.state = g.S.PLAY


func update(dt: float) -> void:
	for k in flash.keys():
		flash[k] = maxf(0.0, flash[k] - dt)
	# 松手后没收到 release（浏览器切后台等）的保险：摇杆超过 8 秒没动就复位
	if stick_id >= 0 and g.state != g.S.PLAY:
		stick_id = -1
		vec = Vector2.ZERO
	if skill_id >= 0 and g.state != g.S.PLAY:
		skill_id = -1
		if g.ult != null:
			g.ult.release_q()
	_ult_aim()   # 每帧写一次：ult.gd 瞄准阶段还会按左摇杆挪落点，拖动的落点以手指为准
	if skill_id < 0:
		skill_aim = Vector2.ZERO
	if atk_id >= 0 and (g.state != g.S.PLAY or TouchLayout.atk_hidden(Cfg.touch_layout)):
		_atk_release()


func draw_hud(vs: Vector2) -> void:
	if not active:
		return
	var hud: CanvasItem = g.hud
	var font: Font = g.font
	btn_rects.clear()
	_tb = null if g.opt_old & g.OPT_TOUCHB else TriBatch.new()
	_draw_hud_body(hud, font, vs)
	_seal(hud)
	_tb = null


func _draw_hud_body(hud: CanvasItem, font: Font, vs: Vector2) -> void:
	# 位置 / 大小：缺省或玩家在「设置 → 触屏按键布局」里改过的（touch_layout.gd，夹在安全区内）
	var L: Dictionary = layout(vs)
	var sk: float = L.stick.s
	# 摇杆
	if stick_id >= 0 and g.state == g.S.PLAY:
		var rr: float = stick_r()
		_circ(hud, stick_origin, rr + 10.0 * sk, Color(0.05, 0.12, 0.16, 0.35))
		_arc(hud, stick_origin, rr + 10.0 * sk, 0.0, TAU, 40, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.5), 2.0)
		var knob: Vector2 = stick_origin + vec * rr
		_circ(hud, knob, 24.0 * sk, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.35))
		_arc(hud, knob, 24.0 * sk, 0.0, TAU, 24, Color(0.8, 1.0, 1.0, 0.8), 2.0)
	elif g.hud_live():
		# 提示：左下角淡淡的摇杆位置（改过位置时稍亮一点：那里按下就是固定摇杆）
		var c: Vector2 = L.stick.c
		var ka: float = 0.2 if L.stick.custom else 0.12
		_arc(hud, c, 40.0 * sk, 0.0, TAU, 32, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, ka), 1.5)
		_circ(hud, c, 10.0 * sk, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, ka))
	# 冲刺按钮：缺省在右下角编队区（源石锭框 + 「编队 n / m」）正上方；技能键 / 瞄准键缺省跟着冲刺键（touch_layout.default_center）
	# 手机（界面层放大后逻辑高约 481，手机端 UI 优化 r2）：右侧竖列只放暂停 / 属性，冲刺键左移到 vs.x − 134
	var ph: bool = vs.y < 520.0 or Cfg.phone_ui()
	if g.hud_live():
		var ds: float = L.dash.s
		var dc: Vector2 = L.dash.c
		var dr: float = BTN * 0.7 * ds
		var dr0 := Rect2(dc - Vector2(dr, dr), Vector2(dr * 2.0, dr * 2.0))
		btn_rects.append([dr0, "dash"])
		var ready: bool = g.dash_ready()
		_circ(hud, dc, dr, Color(0.05, 0.12, 0.16, 0.7 if ready else 0.45))
		_arc(hud, dc, dr, -PI / 2.0, -PI / 2.0 + TAU * g.dash_frac(), 40, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.9 if ready else 0.5), 3.0)
		var dfs: int = int(round(18.0 * clampf(ds, 0.85, 1.3)))
		_tx(func(): UI.text(hud, font, dc + Vector2(-40, dfs * 0.45), "冲刺", dfs, Color(1, 1, 1, 0.9 if ready else 0.5), HORIZONTAL_ALIGNMENT_CENTER, 80))
		if g.dash_max() > 1:   # 连冲：剩余次数
			_tx(func(): UI.text(hud, font, dc + Vector2(-40, dfs * 0.45 + 18.0 * clampf(ds, 0.85, 1.3)), "×%d" % g.dash_left(), int(round(12.0 * clampf(ds, 0.85, 1.3))), Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 80))
		if not TouchLayout.atk_hidden(Cfg.touch_layout):
			_draw_atk_button(hud, font, L.atk.c, L.atk.s)
		else:
			atk_rect = Rect2()
		if g.ult != null:
			skill_rect = Rect2()   # 手动技能键让给终结技键（样子在 hud_ult.gd 画）
			var ub: Dictionary = ult_btn(vs)
			var cb: Dictionary = combo_btn(vs)
			ult_rect = Rect2(ub.c - Vector2(ub.r, ub.r), Vector2(ub.r, ub.r) * 2.0)
			combo_rect = Rect2(cb.c - Vector2(cb.r, cb.r), Vector2(cb.r, cb.r) * 2.0) if Bal.vi("link/v2", 1) <= 0 else Rect2()   # 连携 v2：没有连携键
		else:
			_draw_skill_button(hud, font, L.skill.c, L.skill.s)
		btn_rects.append([speed_rect(vs), "speed"])
	else:
		skill_rect = Rect2()
		atk_rect = Rect2()
		ult_rect = Rect2()
		combo_rect = Rect2()
	# 指挥键（docs/114）：圈里写当前模式，颜色随模式（随行青 / 突击金 / 归队绿），下方标签「指挥」
	if g.hud_live() and g.squad.cmd_on():
		var ce: Dictionary = L.cmd
		var cc: Vector2 = ce.c
		var cr: float = BTN / 2.0 * float(ce.s)
		btn_rects.append([Rect2(cc - Vector2(cr, cr), Vector2(cr * 2.0, cr * 2.0)), "cmd"])
		var st: int = g.squad.stance
		var scol: Color = [UI.CYAN, UI.GOLD, UI.GREEN][st]
		var lit: bool = flash.get("cmd", 0.0) > 0.0 or st != 0
		hud.draw_circle(cc, cr, Color(0.05, 0.12, 0.16, 0.75 if lit else 0.55))
		hud.draw_arc(cc, cr, 0.0, TAU, 32, Color(scol.r, scol.g, scol.b, 0.95 if lit else 0.6), 2.0 if st == 0 else 3.0)
		# 突击耐力：键外一圈（从正上方顺时针，突击中金色、耗尽冷却灰色）
		var sq = g.squad
		var fc: Color = UI.GOLD if st == sq.ROAM else (Color(0.5, 0.52, 0.55) if sq.exhausted else UI.CYAN)
		if sq.stamina_on():
			hud.draw_arc(cc, cr + 5.0, 0.0, TAU, 32, Color(0.02, 0.03, 0.04, 0.6), 4.0)
		if sq.stamina_on() and sq.stamina > 0.0:
			hud.draw_arc(cc, cr + 5.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(sq.stamina, 0.0, 1.0), 32, fc, 4.0)
		var cfs: int = int(round(14.0 * clampf(float(ce.s), 0.8, 1.3)))
		UI.text(hud, font, cc + Vector2(-30, cfs * 0.38), g.squad.STANCE_NAMES[st], cfs, Color(scol.r, scol.g, scol.b, 1.0), HORIZONTAL_ALIGNMENT_CENTER, 60)
		UI.text(hud, font, cc + Vector2(-30, cr + 15), "指挥" if g.squad.priority == g.squad.default_priority() else g.squad.PRIO_SHORT[g.squad.priority], 13 if ph else 12, UI.SUB if g.squad.priority == g.squad.default_priority() else UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER, 60)
	# 按钮：右侧中部纵向两个（暂停 / 属性）
	if g.state == g.S.PLAY or g.state == g.S.PAUSE or g.state == g.S.STATS:
		var items := [["Ⅱ", "pause", "暂停"], ["≡", "stats", "属性"]]
		for i in items.size():
			var e: Dictionary = L[items[i][1]]
			var c: Vector2 = e.c
			var br: float = BTN / 2.0 * float(e.s)
			var r := Rect2(c - Vector2(br, br), Vector2(br * 2.0, br * 2.0))
			btn_rects.append([r, items[i][1]])
			var lit: bool = flash.get(items[i][1], 0.0) > 0.0 or (items[i][1] == "pause" and g.state == g.S.PAUSE) or (items[i][1] == "stats" and g.state == g.S.STATS)
			_circ(hud, c, br, Color(0.05, 0.12, 0.16, 0.75 if lit else 0.55))
			_arc(hud, c, br, 0.0, TAU, 32, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.9 if lit else 0.5), 2.0)
			var ifs: int = int(round(20.0 * clampf(float(e.s), 0.8, 1.3)))
			_tx(func(): UI.text(hud, font, c + Vector2(-20, ifs * 0.35), items[i][0], ifs, Color(1, 1, 1, 0.95 if lit else 0.8), HORIZONTAL_ALIGNMENT_CENTER, 40))
			_tx(func(): UI.text(hud, font, c + Vector2(-30, br + 15), items[i][2], 13 if ph else 12, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 60))
			# 开局「点「属性」查看……」提示期间，属性键跟着呼吸（提示条件同 hud.gd）
			if items[i][1] == "stats" and g.state == g.S.PLAY and (((g.t >= 6.0 and g.t < 16.0) and not g.tab_used) or g.tab_hint > 0.0):
				_seal(hud)   # 呼吸外圈压在「属性」字上（原顺序）
				var pulse: float = 0.5 + 0.5 * sin(g.t * 5.0)
				_arc(hud, c, br + 4.0 + 2.0 * pulse, 0.0, TAU, 32, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.3 + 0.5 * pulse), 2.0)


## 瞄准键：圆底 + 准星图标；按住时亮、拖动时按钮上画小摇杆（同技能键），拖过死区 = 按住瞄准
func _draw_atk_button(hud: CanvasItem, font: Font, c: Vector2, sc := 1.0) -> void:
	var r := BTN * 0.62 * sc
	atk_rect = Rect2(c - Vector2(r, r), Vector2(r * 2.0, r * 2.0))
	var held: bool = atk_id >= 0 or flash.get("atk", 0.0) > 0.0
	var ac := Color(1.0, 0.72, 0.4)
	_circ(hud, c, r, Color(0.14, 0.08, 0.04, 0.8 if held else 0.55))
	_arc(hud, c, r, 0.0, TAU, 40, Color(ac.r, ac.g, ac.b, 0.95 if held else 0.6), 3.0 if held else 2.0)
	var wc := Color(1, 1, 1, 0.95 if held else 0.75)
	_arc(hud, c, 9.0 * sc, 0.0, TAU, 24, wc, 2.0)
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		_ln(hud, c + d * 5.0 * sc, c + d * 15.0 * sc, wc, 2.5)
	_circ(hud, c, 2.0 * sc, Color(ac.r, ac.g, ac.b, 0.95))
	if atk_id >= 0:
		_seal(hud)   # 拖动小摇杆压在按钮字上（原顺序）
		var reach := r + 30.0
		_arc(hud, c, reach, 0.0, TAU, 40, Color(ac.r, ac.g, ac.b, 0.35), 1.5)
		_arc(hud, c, AIM_DEAD, 0.0, TAU, 24, Color(1, 1, 1, 0.25), 1.0)
		var k: Vector2 = atk_drag.limit_length(reach)
		_circ(hud, c + k, 12.0, Color(ac.r, ac.g, ac.b, 0.45 if atk_drag.length() >= AIM_DEAD else 0.25))
		_arc(hud, c + k, 12.0, 0.0, TAU, 20, Color(1.0, 0.9, 0.75, 0.9), 2.0)


## 手动技能键：圆底 + 技能图标 + 外圈充能；就绪时青色呼吸外圈。只在主控有已解锁的手动技能时画（干员契约 v2.3：手动只对主控）
func _draw_skill_button(hud: CanvasItem, font: Font, c: Vector2, sc := 1.0) -> void:
	skill_rect = Rect2()
	var ld = g.squad.leader()
	if ld == null:
		return
	var i: int = ld.manual_index()
	if i < 0 or not ld.skill_unlocked(i):
		return
	var r := BTN * 0.7 * sc
	skill_rect = Rect2(c - Vector2(r, r), Vector2(r * 2.0, r * 2.0))
	var need: float = ld.sp_need(i)
	var frac: float = clampf(ld.sp[i] / need, 0.0, 1.0) if need > 0.0 else 1.0
	var ready: bool = g.hud_view.squad.manual_castable(ld, i)
	var lk: bool = ready and ld.invuln_only(i)   # 目标无敌（10-28）：图标压暗 + 锁标，仍可按
	var held: bool = skill_id >= 0 or flash.get("skill", 0.0) > 0.0
	_circ(hud, c, r, Color(0.05, 0.12, 0.16, 0.8 if ready or held else 0.5))
	var tx: Texture2D = g.tex.get(ld.skill_def(i).get("icon", ""))
	if tx != null:
		var s := r * 1.2
		_icon(hud, tx, Rect2(c - Vector2(s, s) / 2.0, Vector2(s, s)), Color.WHITE if ready and not lk else Color(0.55, 0.58, 0.62))
	else:
		_tx(func(): UI.text(hud, font, c + Vector2(-40, 7), ld.skill_def(i).get("name", "技能").substr(0, 2), 16, Color(1, 1, 1, 0.9 if ready else 0.5), HORIZONTAL_ALIGNMENT_CENTER, 80))
	_arc(hud, c, r, -PI / 2.0, -PI / 2.0 + TAU * frac, 40, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.95 if ready else 0.5), 3.0)
	if ready:
		var pulse: float = 0.5 + 0.5 * sin(g.t * 6.0)
		_arc(hud, c, r + 4.0 + 2.0 * pulse, 0.0, TAU, 40, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.35 + 0.4 * pulse), 2.0)
	_tx(func(): UI.text(hud, font, c + Vector2(-40, r + 17), ld.skill_def(i).get("name", ""), 13, UI.TEXT if ready else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 80))
	if lk:
		_seal(hud)
		var lc: Vector2 = c + Vector2(r * 0.62, r * 0.62)
		_circ(hud, lc, 11.0, Color(0.04, 0.05, 0.07, 0.85))
		_arc(hud, lc + Vector2(0, -3), 4.0, PI, TAU, 10, Color(0.92, 0.94, 0.96), 2.0)
		_circ(hud, lc + Vector2(0, 2), 5.0, Color(0.92, 0.94, 0.96))
	# 按住拖动：按钮上画小摇杆（外圈 = 拖动示意范围，内圈 = 死区，拖回内圈 = 自动瞄准）
	if skill_id >= 0 and ld.manual_aims(i):
		_seal(hud)   # 同上
		var reach := r + 30.0
		_arc(hud, c, reach, 0.0, TAU, 40, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.35), 1.5)
		_arc(hud, c, AIM_DEAD, 0.0, TAU, 24, Color(1, 1, 1, 0.25), 1.0)
		var k: Vector2 = skill_aim.limit_length(reach)
		_circ(hud, c + k, 14.0, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.45 if aim_dir() != Vector2.ZERO else 0.25))
		_arc(hud, c + k, 14.0, 0.0, TAU, 20, Color(0.85, 1.0, 1.0, 0.9), 2.0)


## 合批（性能 docs/50 §21，OPT_TOUCHB）：按钮的圆 / 弧 / 线进一个 TriBatch（引擎同款几何），技能图标随后、字最后按字号成组画，
## 一帧原来二三十次绘制调用压到几次。字只压在本按钮的图形上；拖动小摇杆 / 呼吸外圈这种要压在字上的，先 _seal 把前面的交掉再画（层次同原来）
var _tb: TriBatch = null
var _txt: Array[Callable] = []
var _icons: Array = []

func _circ(hud: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	if _tb != null:
		_tb.circle(c, r, col)
	else:
		hud.draw_circle(c, r, col)


func _arc(hud: CanvasItem, c: Vector2, r: float, a0: float, a1: float, n: int, col: Color, w: float) -> void:
	if _tb != null:
		_tb.arc(c, r, a0, a1, n, col, w)
	else:
		hud.draw_arc(c, r, a0, a1, n, col, w)


func _ln(hud: CanvasItem, a: Vector2, b: Vector2, col: Color, w: float) -> void:
	if _tb != null:
		_tb.line(a, b, col, w)
	else:
		hud.draw_line(a, b, col, w)


func _icon(hud: CanvasItem, tx: Texture2D, r: Rect2, col: Color) -> void:
	if _tb != null:
		_icons.append([tx, r, col])
	else:
		hud.draw_texture_rect(tx, r, false, col)


func _tx(f: Callable) -> void:
	if _tb != null:
		_txt.append(f)
	else:
		f.call()


func _seal(hud: CanvasItem) -> void:
	if _tb == null:
		return
	_tb.flush(hud)
	for it in _icons:
		hud.draw_texture_rect(it[0], it[1], false, it[2])
	_icons.clear()
	if not _txt.is_empty():
		g.hud_view.text_flush(_txt)
		_txt = []

