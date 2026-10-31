extends RefCounted
## 指挥圆盘（用户 10-24：「点击指挥模式出来一个类似于圆盘的指挥系统，玩家可以选择清杂优先或者 Boss 优先」，docs/114 §13）。
## 按指挥键（键盘 F / 手柄 LB / 触屏「指挥」键）打开：上半圈是队形（随行 / 突击 / 归队，各 60°），下半圈是索敌优先级（清杂优先 / Boss 优先，各 90°）。
## 打开时局内放慢（command/wheel_slow，缺省 0.2，不全停）。
## 操作：按住键（> 0.25 秒）→ 往目标方向移鼠标（相对按下时的位置）/ 推摇杆，松开确认，没选中松开 = 取消；
##       轻点一下（< 0.25 秒）→ 圆盘留着，鼠标 / 点按直接点选项，Enter / Ⓐ 确认悬停项，Esc / 再按一次指挥键 / 点空白处取消。
## 选中的优先级只影响队友自动索敌（op_api.nearest_enemies，队长不受影响）；队形走 squad.apply_command。纯界面 + 一个时间系数，不碰随机数。

const UI = preload("res://scripts/ui.gd")
const Bal = preload("res://scripts/core/balance.gd")

## 圆盘选项：id / 名 / 说明 / 颜色。顺序 = 从左上起顺时针，中心角见 ANG、半宽见 HALF（度，0 = 向右，顺时针为正）
const ITEMS_BASE := [
	{"id": "guard", "name": "随行", "en": "ESCORT", "sub": "跟在队长身边", "col": Color(0.212, 0.886, 0.863)},
	{"id": "roam", "name": "突击", "en": "ASSAULT", "sub": "离队索敌，限时行动", "col": Color(0.957, 0.753, 0.306)},
	{"id": "recall", "name": "归队", "en": "REGROUP", "sub": "立即回到队长身边", "col": Color(0.184, 0.827, 0.627)},
	{"id": "mob", "name": "清杂优先", "en": "SWARM", "sub": "优先杂兵，向密集处开火", "col": Color(1.0, 0.62, 0.3)},
	{"id": "boss", "name": "Boss 优先", "en": "BOSS", "sub": "全队集火 Boss，突击时紧追不放", "col": Color(1.0, 0.239, 0.545)},
]
## 指点（docs/196，command/target_proto = 1）：下半圈换成「移动」「肃清」「集火」三项，替掉清杂 / Boss 优先；
## 「肃清」10-30 用户加（「移动保留，然后增加肃清区域的选项，因为移动可以帮忙点亮灯塔」），圆盘 6 格各 60°
const ITEMS_PROTO := [
	{"id": "point", "name": "移动", "en": "MOVE", "sub": "点一个位置：队友走过去驻扎", "col": Color(0.36, 0.78, 1.0)},
	{"id": "clear", "name": "肃清", "en": "CLEAR", "sub": "点一块区域：队友清掉圈内敌人，清空后回到随行", "col": Color(0.36, 0.78, 1.0)},
	{"id": "focus", "name": "集火", "en": "FOCUS", "sub": "点精英或 Boss：全队集火该目标", "col": Color(1.0, 0.239, 0.545)},
]
## 指挥 v2（docs/209 §1.6，command/v2 = 1）：合并成四项——上半圈两个姿态（随行 = 护卫阵型，队友远时先闪回集合；突击 = 职业分工），
## 下半圈两个指点（部署 = 原「移动 / 驻扎」升级成落位阻挡；集火）；「肃清」和部署重复、从圆盘移除（机器人内部仍可下）
const ITEMS_V2 := [
	{"id": "guard", "name": "随行", "en": "ESCORT", "sub": "护卫阵型：队长身边安全，队友不受伤", "col": Color(0.212, 0.886, 0.863)},
	{"id": "roam", "name": "突击", "en": "ASSAULT", "sub": "按职业分工出击：会受伤，限时行动", "col": Color(0.957, 0.753, 0.306)},
	{"id": "point", "name": "部署", "en": "DEPLOY", "sub": "点一个位置落位：重装、近卫阻挡敌人", "col": Color(0.36, 0.78, 1.0)},
	{"id": "focus", "name": "集火", "en": "FOCUS", "sub": "点精英或 Boss：全队集火该目标", "col": Color(1.0, 0.239, 0.545)},
]
var ITEMS: Array = _items()

static func _items() -> Array:
	if Bal.v("command/target_proto", 0.0) > 0.0 and Bal.v("command/v2", 1.0) > 0.0:
		return ITEMS_V2
	if Bal.v("command/target_proto", 0.0) <= 0.0:
		return ITEMS_BASE
	return ITEMS_BASE.slice(0, 3) + ITEMS_PROTO

var ANG: Array = [-135.0, -45.0, 45.0, 135.0] if ITEMS.size() == 4 else ([-150.0, -90.0, -30.0, 45.0, 135.0] if ITEMS.size() == 5 else [-150.0, -90.0, -30.0, 30.0, 90.0, 150.0])
var HALF: Array = [45.0, 45.0, 45.0, 45.0] if ITEMS.size() == 4 else ([30.0, 30.0, 30.0, 45.0, 45.0] if ITEMS.size() == 5 else [30.0, 30.0, 30.0, 30.0, 30.0, 30.0])
const TAP := 0.25          # 轻点 / 按住的分界（真实秒）
const DEAD := 30.0         # 按住模式：鼠标 / 摇杆离起点多远才算选中（像素 / 摇杆 0.5 比例见 _pad_vec）
const R_IN := 70.0
const R_OUT := 196.0

var g
var is_open := false
var latched := false       # 轻点打开：圆盘留着，靠点选 / 再按取消
var src := ""              # 按住来源："key" 键盘 / "pad" 手柄；"" = 没按住（轻点后 / 触屏）
var t_open := 0.0          # 打开后的真实秒数
var hover := -1
var forced := -1           # 测试 / 录片：强制悬停项（autotest --wheelplan）
var origin := Vector2.ZERO # 按住模式：打开时鼠标的 UI 坐标
var mouse := Vector2.ZERO  # 鼠标当前 UI 坐标（跟着 InputEventMouseMotion 走，比轮询视口位置可靠，测试里也能合成）
var center := Vector2.ZERO
var _last_hover := -1
var sel_t := 0.0           # 悬停项换了之后的真实秒数（选中填色从内往外推）
var _ptr_a := 0.0          # 指针游标的角度（弧度，沿环滑向悬停项）
var _ptr_v := 0.0          # 指针游标的显隐（0–1）
var _out_t := -1.0         # 收起动效的真实秒数（< 0 = 不在收起）
var _out_i := -1           # 收起时确认的项（-1 = 取消）
var _plan: Array = []      # 测试：[[秒, 命令, 参数], …]（--wheelplan=open@40,sel@41:0,ok@44）
var _plan_read := false


func _init(game) -> void:
	g = game


## 局内时间系数（game._process 乘在步长上）：圆盘打开时放慢
func slow() -> float:
	return Bal.v("command/wheel_slow", 0.2) if is_open else 1.0


## 打开（from_event：触发的按键事件，用来判断是键盘还是手柄注入；触屏 / 测试传 null）
func open(from_event: InputEvent = null, touch := false) -> void:
	if is_open or g.state != g.S.PLAY or not g.squad.cmd_on() or g.demo_op != "":
		return
	is_open = true
	t_open = 0.0
	hover = -1
	forced = -1
	_last_hover = -1
	_ptr_v = 0.0
	_out_t = -1.0
	var vs: Vector2 = g.hud.size
	center = vs / 2.0
	origin = g.hud.get_local_mouse_position()
	mouse = origin
	latched = touch or from_event == null
	src = ""
	if from_event is InputEventKey:
		src = "pad" if from_event.device == Pad.SYNTH_DEVICE else "key"
	Sfx.play("ui_move", -6.0)


func close() -> void:
	if is_open:
		_out_t = 0.0
		_out_i = hover
	is_open = false
	hover = -1
	forced = -1
	src = ""
	latched = false


func cancel() -> void:
	Sfx.play("ui_move", -10.0)
	hover = -1
	close()


func confirm(i: int) -> void:
	if g.trace_every > 0.0:
		print("WHEEL confirm ", i)
	hover = i   # 收起动效留影用（触屏点选时没有悬停）
	close()
	if i < 0 or i >= ITEMS.size():
		return
	Sfx.play("ui_ok", -6.0)
	g.squad.apply_command(str(ITEMS[i].id))


## 当前生效的项（画「当前」标记）
func is_current(i: int) -> bool:
	var sq = g.squad
	match str(ITEMS[i].id):
		"guard":
			return sq.stance == sq.GUARD
		"roam":
			return sq.stance == sq.ROAM
		"recall":
			return sq.stance == sq.RECALL
		"mob":
			return sq.priority == 1
		"boss":
			return sq.priority == 0
		"point", "clear", "focus":
			return sq.order_kind == str(ITEMS[i].id)
	return false


## 方向 → 选项下标；v 离中心太近返回 -1
func _pick(v: Vector2, dead: float) -> int:
	if v.length() < dead:
		return -1
	var a: float = rad_to_deg(v.angle())
	var best := -1
	var bd := INF
	for i in ANG.size():
		var d: float = absf(wrapf(a - float(ANG[i]) + 180.0, 0.0, 360.0) - 180.0)
		if d <= float(HALF[i]) + 1.0 and d < bd:
			bd = d
			best = i
	return best


func _pad_vec() -> Vector2:
	var dev: int = Pad.device
	var v := Vector2(Input.get_joy_axis(dev, JOY_AXIS_RIGHT_X), Input.get_joy_axis(dev, JOY_AXIS_RIGHT_Y))
	if v.length() < 0.35:
		v = Vector2(Input.get_joy_axis(dev, JOY_AXIS_LEFT_X), Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y))
	return v


func _held() -> bool:
	if src == "key":
		return Input.is_key_pressed(KEY_F)
	if src == "pad":
		var dev: int = Pad.device
		return Input.is_joy_button_pressed(dev, JOY_BUTTON_LEFT_SHOULDER) or Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_LEFT) > 0.3
	return false


## 每个真实帧：计时、悬停、松开判定、自动关（离开 PLAY）
func update(rd: float) -> void:
	_run_plan()
	if not is_open:
		if _out_t >= 0.0:
			_out_t += rd
			if _out_t > OUT_T:
				_out_t = -1.0
		return
	if g.state != g.S.PLAY:
		close()
		_out_t = -1.0
		return
	t_open += rd
	if forced >= 0:
		hover = forced
	elif src == "pad":
		hover = _pick(_pad_vec(), 0.5)
	elif src == "key":
		hover = _pick(mouse - origin, DEAD)
	elif latched:
		if Pad.using:
			var pv: Vector2 = _pad_vec()
			if pv.length() >= 0.5:
				hover = _pick(pv, 0.5)
		elif not (g.touch != null and g.touch.active):
			hover = _hit(mouse)
	sel_t += rd
	if hover != _last_hover:
		sel_t = 0.0
		if hover >= 0:
			Sfx.play("ui_move", -14.0)
		_last_hover = hover
	if hover >= 0:   # 指针游标：第一次出现直接到位，之后沿环滑过去（减少动态效果直接跳）
		var ta: float = deg_to_rad(float(ANG[hover]))
		if _ptr_v <= 0.0 or Cfg.reduce_motion:
			_ptr_a = ta
		else:
			_ptr_a += wrapf(ta - _ptr_a, -PI, PI) * (1.0 - exp(-rd * 28.0))
		_ptr_v = minf(1.0, _ptr_v + rd / 0.08)
	else:
		_ptr_v = maxf(0.0, _ptr_v - rd / 0.08)
	if src != "" and forced < 0 and not _held():
		if t_open < TAP:
			latched = true   # 轻点：圆盘留着
			src = ""
			origin = mouse
		else:
			confirm(hover)


## 点选用：UI 坐标落在哪个扇区（含环外一圈宽容，圆心死区 = -1）
func _hit(p: Vector2) -> int:
	var v: Vector2 = p - center
	if v.length() > R_OUT * _k() + 36.0:
		return -1
	return _pick(v, R_IN * _k() * 0.6)


func _k() -> float:
	var vs: Vector2 = g.hud.size
	return clampf(minf(vs.x, vs.y) / 600.0, 0.62, 1.1)


## 输入：打开时吞掉所有按键 / 鼠标 / 触屏（移动是轮询的，不受影响）；返回 true = 已处理
func input(event: InputEvent) -> bool:
	if not is_open:
		return false
	if event is InputEventKey:
		if not event.pressed or event.echo:
			return true
		var k: int = Pad.kc(event)
		if k == KEY_ESCAPE or k == KEY_K or (k == KEY_F and latched and src == ""):
			cancel()
		elif latched and (k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_E or k == KEY_SPACE):
			if hover >= 0:
				confirm(hover)
			else:
				cancel()
		return true
	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_RIGHT:
				cancel()
			elif event.button_index == MOUSE_BUTTON_LEFT:
				var i: int = _hit(event.position / Cfg.ui_k)
				if i >= 0:
					confirm(i)
				elif latched or src != "":
					cancel()
		return true
	if event is InputEventMouseMotion:
		mouse = event.position / Cfg.ui_k
		return false   # 悬停高亮读 mouse；别的鼠标逻辑照常
	# 触屏（10-26 iPhone 实机「点完突击之后方向键还是会被锁定」）：圆盘开着时以前把所有触点事件都吞了——按着摇杆的那根手指
	# 拖动停在旧方向、抬起也被吃掉，touch.gd 的 stick_id 一直占着，圆盘关了以后摇杆卡在旧方向、新按下也起不了摇杆。
	# 现在只吞「按下」：点到选项 = 确认，点空白 = 取消；空白处正好在摇杆区时这一下同时起摇杆（不用松手重按）。抬起 / 拖动一律放行给 touch.gd
	if event is InputEventScreenTouch:
		if not event.pressed:
			return false
		var p: Vector2 = event.position / Cfg.ui_k
		var i: int = _hit(p)
		if i >= 0:
			confirm(i)
			if g.pick.active:   # 指点原型：手指还按着，接着拖到目标点、松手确认（docs/196 §6.3）
				g.pick.finger_id = event.index
				g.pick.pointer = p
			return true
		cancel()
		return not g.touch.wants_stick(p)
	if event is InputEventScreenDrag:
		return false
	return false


# ---------------------------------------------------------------- 绘制（终末地风格，docs/144）
## 表盘式，从下往上叠：压暗 → 底盘 + 准线 → 刻度环（细刻度慢转）+ 斜纹带（慢走）→ 扇区（投影 / 内外两层 / 顶边高光 / 内沿属性色条）
## → 选中块（蓝色从内往外推 + 外沿亮带 + 外推虚框）→ 指针游标 → 中心三层圆。
## 动效一律用真实秒：打开（底盘放大淡入、刻度环顺时针画开、扇区错开推出、取景框收拢）、常驻（细刻度 / 中心刻度慢转、斜纹带走动）、
## 悬停（填色内→外、虚框外扩、指针沿环滑过去、中心名字上浮）、确认（选中块虚框外扩淡出，整盘 0.16 秒收起）。
## 减少动态效果：只留 ≤ 120 ms 淡入淡出，其余直接到终态、不转不走。整套不做明暗闪烁。
## 配色（用户 10-29：「要有 PRTS 感，指挥圆盘的配色也是」）：command/wheel_style —— 0 终末地蓝（docs/144 原样）/ 1 PRTS·警戒（黑白灰 + 警戒黄，友方蓝白）/ 2 PRTS·终端（黑白灰 + 冷白青，攻击橙红）。
## 下面是各档的缺省值（0 档）；_apply_style() 按档覆盖。选指点 / 圆盘共用同一套（command_pick.gd 读 g.wheel.C_*）
var C_ACC := Color(0.122, 0.659, 0.941)      # 终末地蓝 #1FA8F0（用户 10-24：黄换蓝）
var C_ACC_HI := Color(0.49, 0.82, 0.98)      # 选中块外沿亮带
var C_INK := Color(0.03, 0.07, 0.11)         # 选中块上的深色字
var C_PLATE := Color(0.055, 0.06, 0.068)     # 底盘 / 中心外圈
var C_FILL := Color(0.118, 0.122, 0.13)      # 扇区外层
var C_FILL_IN := Color(0.078, 0.082, 0.09)   # 扇区内层（靠圆心一圈）
var C_LINE := Color(0.62, 0.63, 0.65)
var C_TEXT := Color(0.94, 0.94, 0.93)
var C_DIAL := Color(0.86, 0.87, 0.88)
var C_FRIEND := Color(0.431, 0.776, 1.0)     # 友方 / 队形（随行、归队）
var C_WARN := Color(1.0, 0.239, 0.545)       # 攻击 / 警示（集火、无效）
var style := -1                              # 当前已套用的档（-1 = 还没套）
var prts := false                            # 档 ≥ 1：加警戒斜纹、PRTS 标签等装饰


func _apply_style() -> void:
	var s: int = int(Bal.v("command/wheel_style", 2.0))
	if s == style:
		return
	style = s
	prts = s >= 1
	match s:
		1:   # PRTS·警戒：碳黑 + 白 + 警戒黄（选中块 = 黄底黑字），友方蓝白，攻击橙红
			C_ACC = Color(1.0, 0.788, 0.102)       # #FFC91A
			C_ACC_HI = Color(1.0, 0.906, 0.5)
			C_INK = Color(0.043, 0.043, 0.047)
			C_PLATE = Color(0.047, 0.047, 0.051)
			C_FILL = Color(0.125, 0.125, 0.129)
			C_FILL_IN = Color(0.075, 0.075, 0.078)
			C_LINE = Color(0.55, 0.55, 0.56)
			C_TEXT = Color(0.95, 0.95, 0.94)
			C_DIAL = Color(0.85, 0.85, 0.85)
			C_FRIEND = Color(0.431, 0.776, 1.0)
			C_WARN = Color(1.0, 0.42, 0.18)
		2:   # PRTS·终端：碳黑 + 白 + 冷白青（选中块 = 白青底深字，像作战里的范围格），攻击橙
			C_ACC = Color(0.78, 0.93, 1.0)         # #C7EDFF
			C_ACC_HI = Color(1.0, 1.0, 1.0)
			C_INK = Color(0.02, 0.07, 0.1)
			C_PLATE = Color(0.047, 0.05, 0.055)
			C_FILL = Color(0.125, 0.13, 0.137)
			C_FILL_IN = Color(0.075, 0.08, 0.086)
			C_LINE = Color(0.55, 0.57, 0.6)
			C_TEXT = Color(0.95, 0.96, 0.96)
			C_DIAL = Color(0.85, 0.87, 0.89)
			C_FRIEND = Color(0.78, 0.93, 1.0)
			C_WARN = Color(1.0, 0.6, 0.18)
		_:
			C_ACC = Color(0.122, 0.659, 0.941)
			C_ACC_HI = Color(0.49, 0.82, 0.98)
			C_INK = Color(0.03, 0.07, 0.11)
			C_PLATE = Color(0.055, 0.06, 0.068)
			C_FILL = Color(0.118, 0.122, 0.13)
			C_FILL_IN = Color(0.078, 0.082, 0.09)
			C_LINE = Color(0.62, 0.63, 0.65)
			C_TEXT = Color(0.94, 0.94, 0.93)
			C_DIAL = Color(0.86, 0.87, 0.88)
			C_FRIEND = Color(0.431, 0.776, 1.0)
			C_WARN = Color(1.0, 0.239, 0.545)


## 项的识别色（内沿色条 / 说明）：0 档沿用 ITEMS 里各自的色；PRTS 档收成「友方蓝白 / 警戒黄 / 攻击橙红」三种
func item_col(it: Dictionary) -> Color:
	if not prts:
		return it.col
	match str(it.id):
		"guard", "recall":
			return C_FRIEND
		"roam", "point", "clear":
			return C_ACC if style == 1 else C_FRIEND
		"focus", "boss", "mob":
			return C_WARN
	return it.col


## 警戒斜纹块（黄 / 黑，PRTS 档的标志装饰）：斜条按宽度分段，顶点横坐标夹进 r 里
func hazard(ci: CanvasItem, r: Rect2, a: float, col := Color(0, 0, 0, 0)) -> void:
	var cy: Color = col if col.a > 0.0 else C_ACC
	ci.draw_rect(r, Color(0.03, 0.03, 0.035, a))
	var s: float = r.size.y * 0.5
	var x := -r.size.y
	while x < r.size.x:
		var p := PackedVector2Array([Vector2(x, r.size.y), Vector2(x + s, r.size.y), Vector2(x + s + r.size.y, 0), Vector2(x + r.size.y, 0)])
		for i in p.size():
			p[i] = r.position + Vector2(clampf(p[i].x, 0.0, r.size.x), p[i].y)
		ci.draw_colored_polygon(p, Color(cy.r, cy.g, cy.b, a))
		x += s * 2.0
const GAP := 2.2       # 扇区之间的缝（每边，度）
const OUT_T := 0.16    # 收起时长（秒）


## 指南插图（screens/intro.gd「指挥圆盘」页）：把当前的圆盘画法缩小画在 c 处，t 秒起每 1.4 秒轮流悬停一项
func draw_preview(c: Vector2, k: float, t: float) -> void:
	var n: int = maxi(1, ITEMS.size())
	_draw_ef(Vector2.ZERO, int(t / 1.4) % n, 0.0, c, k, t + 1.0, fmod(t, 1.4))


func draw(vs: Vector2) -> void:
	if is_open:
		_draw_ef(vs, hover, 0.0)
	elif _out_t >= 0.0 and _out_t < OUT_T and not Cfg.reduce_motion and g.state == g.S.PLAY:
		_draw_ef(vs, _out_i, _out_t / OUT_T)


## pc 不为 INF = 指南插图预览（docs/144：同一份画法缩小画在 pc 处；不画暗幕 / 侧标 / 说明板 / 指针 / 「当前」，选中动效由 pt / pst 驱动）
func _draw_ef(vs: Vector2, hov: int, out: float, pc := Vector2.INF, pk := 0.0, pt := 0.0, pst := 0.0) -> void:
	_apply_style()
	var prev: bool = pc != Vector2.INF
	var hud: CanvasItem = g.hud
	var font: Font = g.font
	var k: float = pk if prev else _k()
	var rm: bool = Cfg.reduce_motion
	var t: float = pt if prev else t_open
	var st: float = pst if prev else sel_t
	var pvv: float = 0.0 if prev else _ptr_v
	var e: float = clampf(t / 0.12, 0.0, 1.0) * (1.0 - _ease(out))
	var c: Vector2 = pc if prev else vs / 2.0
	if not prev:
		center = c
	var r_in: float = R_IN * k
	var r_out: float = R_OUT * k
	var r_dial: float = r_out + 16.0 * k
	var spin: float = 0.0 if rm else t
	if not prev:
		hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.01, 0.015, 0.02, 0.5 * e))
	# 底盘：0.9 → 1 放大淡入
	var pg: float = 1.0 if rm else _ease(clampf(t / 0.18, 0.0, 1.0))
	var r_plate: float = (r_dial + 10.0 * k) * lerpf(0.9, 1.0, pg)
	hud.draw_circle(c, r_plate, _ca(C_PLATE, 0.6 * e * pg))
	hud.draw_arc(c, r_plate, 0.0, TAU, 96, _ca(C_DIAL, 0.14 * e * pg), 1.0)
	hud.draw_arc(c, r_out + 4.0 * k, 0.0, TAU, 96, _ca(C_DIAL, 0.1 * e), 1.0)
	# 取景框（从外往里收拢）+ 上下准线
	var bh: float = r_dial + 26.0 * k + (0.0 if rm else (1.0 - _ease(clampf(t / 0.2, 0.0, 1.0))) * 16.0 * k)
	var bl: float = 20.0 * k
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var q: Vector2 = c + Vector2(sx, sy) * bh
			hud.draw_polyline(PackedVector2Array([q - Vector2(0, sy * bl), q, q - Vector2(sx * bl, 0)]), _ca(C_DIAL, 0.5 * e), 2.0)
		hud.draw_line(Vector2(c.x, c.y + sx * (r_plate + 4.0 * k)), Vector2(c.x, c.y + sx * (bh - 4.0 * k)), _ca(C_DIAL, 0.3 * e), 1.0)
	# 刻度环：从正上方顺时针画开（0.22 秒）；细刻度每 5° 一根、慢转（4°/秒），扇区分界（每块起始边）长刻度不动
	var sweep: float = 1.0 if rm else _ease(clampf(t / 0.22, 0.0, 1.0))
	var a_top := -PI / 2.0
	hud.draw_arc(c, r_dial, a_top, a_top + TAU * sweep, 96, _ca(C_DIAL, 0.32 * e), 1.0)
	var fine := PackedVector2Array()
	var rot: float = deg_to_rad(4.0) * spin
	for i in 72:
		var ang: float = deg_to_rad(i * 5.0 + 2.5) + rot
		if fposmod(ang - a_top, TAU) > TAU * sweep:
			continue
		var dv: Vector2 = Vector2.from_angle(ang)
		fine.append(c + dv * r_dial)
		fine.append(c + dv * (r_dial + 3.5 * k))
	if not fine.is_empty():
		hud.draw_multiline(fine, _ca(C_DIAL, 0.3 * e), 1.0)
	for i in ANG.size():   # 扇区分界：每块的起始边
		var ab: float = deg_to_rad(float(ANG[i]) - float(HALF[i]))
		if fposmod(ab - a_top, TAU) > TAU * sweep + 0.001:
			continue
		var dv: Vector2 = Vector2.from_angle(ab)
		hud.draw_line(c + dv * r_dial, c + dv * (r_dial + 9.0 * k), _ca(C_DIAL, 0.7 * e), 1.0)
	# 斜纹带（终末地的 //////）：外沿与刻度环之间，慢慢往前走；悬停项那一段描蓝
	var hatch := PackedVector2Array()
	var hatch_hi := PackedVector2Array()
	var ha: float = r_out + 6.0 * k
	var hb: float = r_dial - 3.0 * k
	var drift: float = deg_to_rad(3.0) * spin
	var hov_a: float = deg_to_rad(float(ANG[hov])) if hov >= 0 else 0.0
	for i in 120:
		var ang: float = deg_to_rad(i * 3.0) + fposmod(drift, deg_to_rad(3.0))
		var p0: Vector2 = c + Vector2.from_angle(ang) * ha
		var p1: Vector2 = c + Vector2.from_angle(ang + deg_to_rad(1.6)) * hb
		if hov >= 0 and absf(wrapf(ang - hov_a, -PI, PI)) < deg_to_rad(float(HALF[hov]) - GAP):
			hatch_hi.append(p0)
			hatch_hi.append(p1)
		else:
			hatch.append(p0)
			hatch.append(p1)
	hud.draw_multiline(hatch, _ca(C_DIAL, 0.14 * e * sweep), 1.0)
	if not hatch_hi.is_empty():
		hud.draw_multiline(hatch_hi, _ca(C_ACC, 0.85 * e), 1.4)
	# 分组线：0° / 180° 的缝里穿过，左端标上半圈「队形」、下半圈「索敌」
	for sx in [-1.0, 1.0]:
		hud.draw_line(Vector2(c.x + sx * (r_in - 4.0 * k), c.y), Vector2(c.x + sx * (r_dial + 44.0 * k), c.y), _ca(C_DIAL, 0.38 * e), 1.0)
		hud.draw_rect(Rect2(Vector2(c.x + sx * (r_dial + 44.0 * k) - 2.0 * k, c.y - 2.0 * k), Vector2(4.0, 4.0) * k), _ca(C_ACC, 0.9 * e))
	if not prev:
		var lx: float = c.x - r_dial - 104.0 * k
		UI.text(hud, font, Vector2(lx, c.y - 8.0 * k), "队形", int(round(13.0 * k)), _ca(C_DIAL, 0.9 * e), HORIZONTAL_ALIGNMENT_RIGHT, 90.0 * k)
		UI.ctext(hud, font, Vector2(lx, c.y - 25.0 * k), "FORMATION", int(round(9.0 * k)), _ca(C_DIAL, 0.5 * e), HORIZONTAL_ALIGNMENT_RIGHT, 90.0 * k)
		UI.text(hud, font, Vector2(lx, c.y + 20.0 * k), "索敌", int(round(13.0 * k)), _ca(C_DIAL, 0.9 * e), HORIZONTAL_ALIGNMENT_RIGHT, 90.0 * k)
		UI.ctext(hud, font, Vector2(lx, c.y + 33.0 * k), "TARGETING", int(round(9.0 * k)), _ca(C_DIAL, 0.5 * e), HORIZONTAL_ALIGNMENT_RIGHT, 90.0 * k)
	# 扇区
	var gap: float = deg_to_rad(GAP)
	var ch: float = 9.0 * k
	var depth: float = r_out - r_in
	for i in ITEMS.size():
		var it: Dictionary = ITEMS[i]
		var sel: bool = i == hov
		var am: float = deg_to_rad(float(ANG[i]))
		var dirv: Vector2 = Vector2.from_angle(am)
		# 展开：按顺时针序错开 0.025 秒，从里往外推 18 px + 淡入
		var si: float = 1.0 if rm else _ease(clampf((t - 0.025 * i) / 0.14, 0.0, 1.0))
		var ea: float = e * si
		var cc: Vector2 = c + dirv * ((6.0 * k if sel else 0.0) - (1.0 - si) * 18.0 * k)
		var a0: float = am - deg_to_rad(float(HALF[i])) + gap
		var a1: float = am + deg_to_rad(float(HALF[i])) - gap
		var poly: PackedVector2Array = _wedge(cc, r_in, r_out, a0, a1, ch)
		var sh := PackedVector2Array()
		for v in poly:
			sh.append(v + Vector2(0, 4.0 * k))
		hud.draw_colored_polygon(sh, Color(0, 0, 0, 0.4 * ea))   # 投影
		hud.draw_colored_polygon(poly, _ca(C_FILL, 0.94 * ea))
		hud.draw_colored_polygon(_wedge(cc, r_in, r_in + depth * 0.24, a0, a1, 0.0), _ca(C_FILL_IN, 0.96 * ea))
		hud.draw_arc(cc, r_out - 2.5 * k, a0 + ch / r_out, a1 - ch / r_out, 12, _ca(C_TEXT, 0.12 * ea), 1.0)   # 顶边高光
		if sel:
			var f: float = 1.0 if rm else _ease(clampf(st / 0.09, 0.0, 1.0))
			var ro: float = lerpf(r_in + 2.0, r_out, f)
			hud.draw_colored_polygon(_wedge(cc, r_in, ro, a0, a1, ch * f), _ca(C_ACC, ea))
			if f > 0.85:
				hud.draw_colored_polygon(_wedge(cc, r_out - depth * 0.12, ro, a0, a1, ch * f), _ca(C_ACC_HI, ea))
			# 外推虚框：选中后从扇区外沿推出 9 px（out_back），确认收起时继续外扩淡出
			var go: float = 9.0 * k if rm else 9.0 * k * _back(clampf(st / 0.16, 0.0, 1.0))
			go += 26.0 * k * _ease(out)
			var gp: PackedVector2Array = _wedge(cc + dirv * go, r_out - depth * 0.3, r_out, a0, a1, ch)
			gp.append(gp[0])
			hud.draw_polyline(gp, _ca(C_ACC, 0.6 * ea), 1.2)
		var ol: PackedVector2Array = poly.duplicate()
		ol.append(poly[0])
		hud.draw_polyline(ol, _ca(C_ACC if sel else C_LINE, (1.0 if sel else 0.45) * ea), 1.5 if sel else 1.0)
		if not sel:   # 内沿属性色条（终末地技能按钮底部的属性色）
			hud.draw_arc(cc, r_in + 3.0 * k, a0 + 0.02, a1 - 0.02, 12, _ca(item_col(it), 0.9 * ea), 3.0 * k)
		var tx: Color = C_INK if sel else C_TEXT
		var tc: Vector2 = cc + dirv * (r_in + depth * 0.52)   # 不画图标（用户 10-24），名字 + 英文行居扇区中部
		UI.text(hud, font, tc + Vector2(-70.0 * k, 1.0 * k), str(it.name), int(round(17.0 * k)), _ca(tx, ea), HORIZONTAL_ALIGNMENT_CENTER, 140.0 * k)
		UI.ctext(hud, font, tc + Vector2(-70.0 * k, 14.0 * k), "0%d // %s" % [i + 1, it.en], int(round(9.0 * k)), _ca(tx, 0.62 * ea), HORIZONTAL_ALIGNMENT_CENTER, 140.0 * k)
		if not prev and is_current(i):   # 「当前」：黑底蓝字小标签，左端一道蓝条，放在英文行下方
			var tp: Vector2 = tc + Vector2(-20.0, 19.0) * k
			hud.draw_rect(Rect2(tp, Vector2(40.0, 15.0) * k), Color(0.03, 0.035, 0.04, 0.94 * ea))
			hud.draw_rect(Rect2(tp, Vector2(3.0, 15.0) * k), _ca(C_ACC, ea))
			UI.text(hud, font, tp + Vector2(1.5 * k, 12.0 * k), "当前", int(round(10.0 * k)), _ca(C_ACC, ea), HORIZONTAL_ALIGNMENT_CENTER, 40.0 * k)
	# 指针游标：刻度环上一段蓝弧 + 外侧三角，沿环滑到悬停项
	if pvv > 0.0:
		var pv: Vector2 = Vector2.from_angle(_ptr_a)
		var pe: float = e * pvv
		hud.draw_arc(c, r_dial, _ptr_a - deg_to_rad(11.0), _ptr_a + deg_to_rad(11.0), 10, _ca(C_ACC, pe), 3.0 * k)
		var side: Vector2 = pv.orthogonal() * 6.0 * k
		var bp: Vector2 = c + pv * (r_dial + 15.0 * k)
		hud.draw_colored_polygon(PackedVector2Array([c + pv * (r_dial + 5.0 * k), bp + side, bp - side]), _ca(C_ACC, pe))
	# 中心：外圈底盘 + 反向慢转的刻度圈 + 内圆 + 朝悬停方向的一段蓝弧
	var rc: float = r_in - 8.0 * k
	var ri: float = rc * 0.8
	hud.draw_circle(c, rc, _ca(C_PLATE, 0.97 * e))
	hud.draw_arc(c, rc, 0.0, TAU, 48, _ca(C_LINE, 0.5 * e), 1.0)
	var cticks := PackedVector2Array()
	var crot: float = -deg_to_rad(8.0) * spin
	for i in 36:
		var dv: Vector2 = Vector2.from_angle(deg_to_rad(i * 10.0) + crot)
		cticks.append(c + dv * (rc - 2.0 * k))
		cticks.append(c + dv * (rc - (6.0 if i % 9 == 0 else 4.0) * k))
	hud.draw_multiline(cticks, _ca(C_DIAL, 0.35 * e), 1.0)
	hud.draw_circle(c, ri, _ca(C_FILL, 0.96 * e))
	for q in 4:
		var q0: float = q * PI / 2.0 - PI / 4.0 + 0.3
		hud.draw_arc(c, ri, q0, q0 + PI / 2.0 - 0.6, 10, _ca(C_ACC, 0.45 * e), 1.5)
	if pvv > 0.0:
		hud.draw_arc(c, ri, _ptr_a - 0.42, _ptr_a + 0.42, 12, _ca(C_ACC, e * pvv), 3.0 * k)
	UI.text(hud, font, c + Vector2(-50.0 * k, -ri * 0.42), "指挥", int(round(12.0 * k)), _ca(C_DIAL, 0.7 * e), HORIZONTAL_ALIGNMENT_CENTER, 100.0 * k)
	var nf: float = 1.0 if rm else _ease(clampf(st / 0.12, 0.0, 1.0))   # 换项时名字从下往上浮 6 px
	if hov >= 0:
		UI.text(hud, font, c + Vector2(-60.0 * k, (7.0 + 6.0 * (1.0 - nf)) * k), str(ITEMS[hov].name), int(round(18.0 * k)), _ca(C_ACC, e * nf), HORIZONTAL_ALIGNMENT_CENTER, 120.0 * k)
	else:
		UI.text(hud, font, c + Vector2(-60.0 * k, 6.0 * k), "选择指令", int(round(14.0 * k)), _ca(C_DIAL, 0.75 * e), HORIZONTAL_ALIGNMENT_CENTER, 120.0 * k)
	UI.ctext(hud, font, c + Vector2(-50.0 * k, ri * 0.66), "COMMAND", int(round(8.0 * k)), _ca(C_DIAL, 0.5 * e), HORIZONTAL_ALIGNMENT_CENTER, 100.0 * k)
	if prev:
		return
	# 说明 + 操作提示：垫一块底板（盖住开局操作提示等底部 HUD 字），左端蓝条
	var py: float = c.y + r_out + 28.0 * k
	var pw: float = 420.0 * k
	hud.draw_rect(Rect2(Vector2(c.x - pw / 2.0, py), Vector2(pw, 48.0 * k)), _ca(C_PLATE, 0.92 * e))
	if prts:
		hazard(hud, Rect2(Vector2(c.x - pw / 2.0, py), Vector2(16.0 * k, 48.0 * k)), e)   # PRTS：左端警戒斜纹
		UI.ctext(hud, font, Vector2(c.x + pw / 2.0 - 214.0 * k, py + 11.0 * k), "PRTS // COMMAND TERMINAL", int(round(8.0 * k)), _ca(C_DIAL, 0.5 * e), HORIZONTAL_ALIGNMENT_RIGHT, 206.0 * k)
	else:
		hud.draw_rect(Rect2(Vector2(c.x - pw / 2.0, py), Vector2(3.0 * k, 48.0 * k)), _ca(C_ACC, e))
	hud.draw_line(Vector2(c.x - pw / 2.0, py + 48.0 * k), Vector2(c.x + pw / 2.0, py + 48.0 * k), _ca(C_DIAL, 0.25 * e), 1.0)
	if hov >= 0:
		UI.text(hud, font, Vector2(c.x - 160.0 * k, c.y + r_out + 46.0 * k), str(ITEMS[hov].sub), int(round(14.0 * k)), _ca(C_TEXT, e * nf), HORIZONTAL_ALIGNMENT_CENTER, 320.0 * k)
	UI.text(hud, font, Vector2(c.x - 200.0 * k, c.y + r_out + 68.0 * k), _tip(), int(round(12.0 * k)), Color(UI.SUB.r, UI.SUB.g, UI.SUB.b, e), HORIZONTAL_ALIGNMENT_CENTER, 400.0 * k)


## 扇环（外沿两角切角 ch）；ch ≈ 0 时不切
func _wedge(c: Vector2, ri: float, ro: float, a0: float, a1: float, ch: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var cut: bool = ch > 0.5
	var da: float = ch / ro if cut else 0.0
	if cut:
		pts.append(c + Vector2.from_angle(a0) * (ro - ch))
	var n := 12
	for s in n + 1:
		pts.append(c + Vector2.from_angle(lerpf(a0 + da, a1 - da, float(s) / n)) * ro)
	if cut:
		pts.append(c + Vector2.from_angle(a1) * (ro - ch))
	for s in n + 1:
		pts.append(c + Vector2.from_angle(lerpf(a1, a0, float(s) / n)) * ri)
	return pts


static func _ca(col: Color, a: float) -> Color:
	return Color(col.r, col.g, col.b, col.a * a)


static func _ease(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)


## out_back(1.4)：略冲过头再回来
static func _back(x: float) -> float:
	var s := 1.4
	var y: float = x - 1.0
	return 1.0 + (s + 1.0) * y * y * y + s * y * y


func _tip() -> String:
	if g.touch != null and g.touch.active and not Pad.using:
		return "点选指令 · 点空白处取消"
	if src != "":
		return Pad.hint("按住移动鼠标选择，松开确认 · Esc 取消", "按住 LB，推摇杆选择，松开确认 · Ⓑ 取消")
	return Pad.hint("点选指令，或 Enter 确认 · Esc / F 取消", "推摇杆选择，Ⓐ 确认 · Ⓑ 取消")


# ---------------------------------------------------------------- 测试计划（只在 autotest / 录片里用）
## --wheelplan=open@40,sel@0.5:1,sel@1.2:3,ok@2.4（open / kd 的秒数是游戏时间；之后各项是打开后的真实秒数；open 轻点式打开，sel 强制悬停项，ok 确认悬停，cancel 取消；
## kd / mv:i / ku = 真实按键通路：F 按下（按住模式）→ 鼠标挪向第 i 项 → F 松开确认，窗口模式用，验证按住选择）
func _run_plan() -> void:
	if not _plan_read:
		_plan_read = true
		for a in Cfg.dev_args():
			if a.begins_with("--wheelplan="):
				for tok in a.substr(12).split(","):
					var at: PackedStringArray = tok.split("@")
					if at.size() != 2:
						continue
					var tm: PackedStringArray = at[1].split(":")
					_plan.append([float(tm[0]), at[0], int(tm[1]) if tm.size() > 1 else -1])
	# open 之前按游戏时间；打开之后的 sel / ok / cancel 的时间是「打开后的真实秒数」（圆盘开着时局内放慢，游戏时间走得慢）
	while not _plan.is_empty() and g.state == g.S.PLAY:
		var opener: bool = str(_plan[0][1]) in ["open", "kd"]
		var due: bool = (g.t >= float(_plan[0][0]) and not is_open) if opener else (is_open and t_open >= float(_plan[0][0]))
		if not due:
			break
		var s: Array = _plan.pop_front()
		match str(s[1]):
			"open":
				open(null, true)
			"sel":
				forced = int(s[2])
				hover = forced
			"ok":
				confirm(hover)
			"cancel":
				cancel()
			"kd":   # 真实输入通路测试：F 键按下（按住模式，走 _input / _unhandled_input）
				var ev := InputEventKey.new()
				ev.keycode = KEY_F
				ev.physical_keycode = KEY_F
				ev.pressed = true
				Input.parse_input_event(ev)
			"mv":   # 把鼠标挪到「按下时位置 + 朝第 N 项方向 100 像素」（窗口模式）
				var mm := InputEventMouseMotion.new()
				mm.position = (origin + Vector2.from_angle(deg_to_rad(float(ANG[int(s[2])]))) * 100.0) * Cfg.ui_k
				mm.global_position = mm.position
				mm.relative = Vector2(1, 1)
				Input.parse_input_event(mm)
			"ku":
				var ev2 := InputEventKey.new()
				ev2.keycode = KEY_F
				ev2.physical_keycode = KEY_F
				ev2.pressed = false
				Input.parse_input_event(ev2)
