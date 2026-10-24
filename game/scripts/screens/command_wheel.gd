extends RefCounted
## 指挥圆盘（用户 10-24：「点击指挥模式出来一个类似于圆盘的指挥系统，玩家可以选择清杂优先或者 Boss 优先」，docs/114 §13）。
## 按指挥键（键盘 F / 手柄 LB / 触屏「指挥」键）打开：上半圈是队形（随行 / 突击 / 归队），下半圈是索敌优先级（清杂优先 / 就近 / Boss 优先）。
## 打开时局内放慢（command/wheel_slow，缺省 0.2，不全停）。
## 操作：按住键（> 0.25 秒）→ 往目标方向移鼠标（相对按下时的位置）/ 推摇杆，松开确认，没选中松开 = 取消；
##       轻点一下（< 0.25 秒）→ 圆盘留着，鼠标 / 点按直接点选项，Enter / Ⓐ 确认悬停项，Esc / 再按一次指挥键 / 点空白处取消。
## 选中的优先级只影响队友自动索敌（op_api.nearest_enemies，队长不受影响）；队形走 squad.apply_command。纯界面 + 一个时间系数，不碰随机数。

const UI = preload("res://scripts/ui.gd")
const Bal = preload("res://scripts/core/balance.gd")

## 圆盘选项：id / 名 / 说明 / 颜色 / 分组（0 队形，1 优先级）。顺序 = 从左上起顺时针，角度见 ANG（度，0 = 向右，顺时针为正）
const ITEMS := [
	{"id": "guard", "name": "随行", "sub": "跟在队长身边", "col": Color(0.212, 0.886, 0.863)},
	{"id": "roam", "name": "突击", "sub": "离队索敌，限时行动", "col": Color(0.957, 0.753, 0.306)},
	{"id": "recall", "name": "归队", "sub": "立即回到队长身边", "col": Color(0.184, 0.827, 0.627)},
	{"id": "mob", "name": "清杂优先", "sub": "优先杂兵，向密集处开火", "col": Color(1.0, 0.62, 0.3)},
	{"id": "near", "name": "就近", "sub": "不指定，打最近的目标", "col": Color(0.72, 0.78, 0.86)},
	{"id": "boss", "name": "Boss 优先", "sub": "优先 Boss 与精英，没有则就近", "col": Color(1.0, 0.239, 0.545)},
]
const ANG := [-150.0, -90.0, -30.0, 30.0, 90.0, 150.0]
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
	is_open = false
	hover = -1
	forced = -1
	src = ""
	latched = false


func cancel() -> void:
	Sfx.play("ui_move", -10.0)
	close()


func confirm(i: int) -> void:
	if g.trace_every > 0.0:
		print("WHEEL confirm ", i)
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
		"near":
			return sq.priority == 0
		"boss":
			return sq.priority == 2
	return false


## 方向 → 选项下标；v 离中心太近返回 -1
func _pick(v: Vector2, dead: float) -> int:
	if v.length() < dead:
		return -1
	var a: float = rad_to_deg(v.angle())
	var best := -1
	var bd := 31.0
	for i in ANG.size():
		var d: float = absf(wrapf(a - float(ANG[i]) + 180.0, 0.0, 360.0) - 180.0)
		if d < bd:
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
		return
	if g.state != g.S.PLAY:
		close()
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
	if hover != _last_hover:
		if hover >= 0:
			Sfx.play("ui_move", -14.0)
		_last_hover = hover
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
	if event is InputEventScreenTouch:
		if event.pressed:
			var p: Vector2 = event.position / Cfg.ui_k
			var i: int = _hit(p)
			if i >= 0:
				confirm(i)
			else:
				cancel()
		return true
	if event is InputEventScreenDrag:
		return true
	return false


# ---------------------------------------------------------------- 绘制

func draw(vs: Vector2) -> void:
	if not is_open:
		return
	var hud: CanvasItem = g.hud
	var font: Font = g.font
	var k: float = _k()
	var a: float = clampf(t_open / 0.12, 0.0, 1.0)
	var e: float = 1.0 - pow(1.0 - a, 3.0)   # 展开缓动
	center = vs / 2.0
	hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.01, 0.03, 0.05, 0.42 * e))
	var r_in: float = R_IN * k * (0.8 + 0.2 * e)
	var r_out: float = R_OUT * k * (0.8 + 0.2 * e)
	for i in ITEMS.size():
		var it: Dictionary = ITEMS[i]
		var col: Color = it.col
		var sel: bool = i == hover
		var a0: float = deg_to_rad(float(ANG[i]) - 29.0)
		var a1: float = deg_to_rad(float(ANG[i]) + 29.0)
		var ro: float = r_out + (10.0 * k if sel else 0.0)
		var pts := PackedVector2Array()
		var n := 14
		for s in n + 1:
			pts.append(center + Vector2.from_angle(lerpf(a0, a1, float(s) / n)) * ro)
		for s in n + 1:
			pts.append(center + Vector2.from_angle(lerpf(a1, a0, float(s) / n)) * r_in)
		var fill: Color = Color(0.085, 0.13, 0.17, 0.93 * e)
		if sel:
			fill = Color(col.r * 0.55 + 0.04, col.g * 0.55 + 0.05, col.b * 0.55 + 0.07, 0.97 * e)
		hud.draw_colored_polygon(pts, fill)
		# 扇区之间的分隔线（沿两条半径边）
		for aa in [a0, a1]:
			hud.draw_line(center + Vector2.from_angle(aa) * r_in, center + Vector2.from_angle(aa) * ro, Color(col.r, col.g, col.b, (0.6 if sel else 0.22) * e), 1.5)
		var edge := PackedVector2Array()
		for s in n + 1:
			edge.append(center + Vector2.from_angle(lerpf(a0, a1, float(s) / n)) * ro)
		hud.draw_polyline(edge, Color(col.r, col.g, col.b, (1.0 if sel else 0.55) * e), 3.0 if sel else 1.6)
		var am: float = deg_to_rad(float(ANG[i]))
		var dirv: Vector2 = Vector2.from_angle(am)
		# 图标（程序画）、名字、说明
		var ic: Vector2 = center + dirv * (r_in + (ro - r_in) * 0.34)
		_glyph(hud, str(it.id), ic, 15.0 * k, Color(col.r, col.g, col.b, e))
		var tc: Vector2 = center + dirv * (r_in + (ro - r_in) * 0.66)
		var nfs: int = int(round(17.0 * k))
		UI.text(hud, font, tc + Vector2(-70.0 * k, 4.0 * k), str(it.name), nfs, Color(1, 1, 1, e) if sel else Color(0.92, 0.95, 0.97, 0.92 * e), HORIZONTAL_ALIGNMENT_CENTER, 140.0 * k)
		if is_current(i):
			var tag_p: Vector2 = tc + Vector2(-20.0 * k, 10.0 * k)
			hud.draw_rect(Rect2(tag_p, Vector2(40.0 * k, 14.0 * k)), Color(col.r, col.g, col.b, 0.85 * e))
			UI.text(hud, font, tag_p + Vector2(0, 11.0 * k), "当前", int(round(10.0 * k)), Color(0.03, 0.05, 0.07, e), HORIZONTAL_ALIGNMENT_CENTER, 40.0 * k)
	# 中心圆：标题、悬停项说明、操作提示
	var rc: float = r_in - 8.0 * k
	hud.draw_circle(center, rc, Color(0.03, 0.05, 0.07, 0.94 * e))
	hud.draw_arc(center, rc, 0.0, TAU, 48, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.7 * e), 2.0)
	UI.text(hud, font, center + Vector2(-50.0 * k, -rc * 0.42), "指挥", int(round(15.0 * k)), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, e), HORIZONTAL_ALIGNMENT_CENTER, 100.0 * k)
	if hover >= 0:
		var hc: Color = ITEMS[hover].col
		UI.text(hud, font, center + Vector2(-60.0 * k, 4.0 * k), str(ITEMS[hover].name), int(round(18.0 * k)), Color(hc.r, hc.g, hc.b, e), HORIZONTAL_ALIGNMENT_CENTER, 120.0 * k)
	else:
		UI.text(hud, font, center + Vector2(-60.0 * k, 4.0 * k), "选择指令", int(round(14.0 * k)), Color(0.75, 0.8, 0.85, 0.8 * e), HORIZONTAL_ALIGNMENT_CENTER, 120.0 * k)
	var sub: String = str(ITEMS[hover].sub) if hover >= 0 else ""
	if sub != "":
		UI.text(hud, font, Vector2(center.x - 160.0 * k, center.y + r_out + 34.0 * k), sub, int(round(14.0 * k)), Color(0.9, 0.94, 0.97, e), HORIZONTAL_ALIGNMENT_CENTER, 320.0 * k)
	var tip: String = _tip()
	UI.text(hud, font, Vector2(center.x - 200.0 * k, center.y + r_out + 58.0 * k), tip, int(round(12.0 * k)), Color(UI.SUB.r, UI.SUB.g, UI.SUB.b, e), HORIZONTAL_ALIGNMENT_CENTER, 400.0 * k)


func _tip() -> String:
	if g.touch != null and g.touch.active and not Pad.using:
		return "点选指令 · 点空白处取消"
	if src != "":
		return Pad.hint("按住移动鼠标选择，松开确认 · Esc 取消", "按住 LB，推摇杆选择，松开确认 · Ⓑ 取消")
	return Pad.hint("点选指令，或 Enter 确认 · Esc / F 取消", "推摇杆选择，Ⓐ 确认 · Ⓑ 取消")


## 选项图标（程序画，不用素材）：随行 = 队长点 + 身后两点；突击 = 向外的箭头；归队 = 向内的箭头；
## 清杂 = 一团小点；就近 = 圆环里一个点；Boss = 菱形 + 内点
func _glyph(ci: CanvasItem, id: String, c: Vector2, r: float, col: Color) -> void:
	var dim := Color(col.r, col.g, col.b, col.a * 0.55)
	match id:
		"guard":
			ci.draw_circle(c + Vector2(r * 0.5, 0), r * 0.32, col)
			ci.draw_circle(c + Vector2(-r * 0.35, -r * 0.3), r * 0.22, dim)
			ci.draw_circle(c + Vector2(-r * 0.7, r * 0.25), r * 0.18, dim)
		"roam":
			for s in [-1.0, 1.0]:
				ci.draw_polyline(PackedVector2Array([c + Vector2(r * 0.15, s * r * 0.55), c + Vector2(r * 0.7, 0), c + Vector2(r * 0.15, -s * r * 0.55)]), col, 2.4)
			ci.draw_line(c + Vector2(-r * 0.8, 0), c + Vector2(r * 0.55, 0), col, 2.4)
		"recall":
			ci.draw_line(c + Vector2(r * 0.8, 0), c + Vector2(-r * 0.5, 0), col, 2.4)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.1, r * 0.55), c + Vector2(-r * 0.65, 0), c + Vector2(-r * 0.1, -r * 0.55)]), col, 2.4)
		"mob":
			for p in [Vector2(-0.5, -0.3), Vector2(0.0, -0.55), Vector2(0.5, -0.2), Vector2(-0.2, 0.15), Vector2(0.35, 0.4), Vector2(-0.6, 0.5)]:
				ci.draw_circle(c + p * r, r * 0.2, col)
		"near":
			ci.draw_arc(c, r * 0.7, 0.0, TAU, 24, dim, 2.0)
			ci.draw_circle(c, r * 0.28, col)
		"boss":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.85), c + Vector2(r * 0.7, 0), c + Vector2(0, r * 0.85), c + Vector2(-r * 0.7, 0)]), dim)
			ci.draw_polyline(PackedVector2Array([c + Vector2(0, -r * 0.85), c + Vector2(r * 0.7, 0), c + Vector2(0, r * 0.85), c + Vector2(-r * 0.7, 0), c + Vector2(0, -r * 0.85)]), col, 2.2)
			ci.draw_circle(c, r * 0.22, col)


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
