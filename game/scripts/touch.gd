## 触屏操作（移动端 / 网页版）：左半屏浮动虚拟摇杆（手指按下处即摇杆中心），右侧两个按钮（暂停 / 属性）。
## 技能全自动，所以只需要移动。面板 / 商店 / 结算里的按钮走 Godot 的"触摸模拟鼠标"，不在这里处理。
## 开启条件：设备有触屏（DisplayServer.is_touchscreen_available）或命令行 --touch。
extends RefCounted

const UI = preload("res://scripts/ui.gd")

const RADIUS := 64.0        # 摇杆最大行程
const DEAD := 10.0          # 死区
const BTN := 46.0           # 按钮直径

var g
var active := false
var stick_id := -1          # 正在控制摇杆的触点
var stick_origin := Vector2.ZERO
var stick_pos := Vector2.ZERO
var vec := Vector2.ZERO
var btn_rects: Array = []   # [Rect2, action]
var flash := {}             # action -> 剩余高亮时间


func _init(game) -> void:
	g = game
	active = DisplayServer.is_touchscreen_available() or OS.get_cmdline_user_args().has("--touch") \
		or OS.has_feature("web_android") or OS.has_feature("web_ios")


func move_vec() -> Vector2:
	return vec if stick_id >= 0 else Vector2.ZERO


## 返回 true 表示事件已消费
func handle(event: InputEvent) -> bool:
	if not active:
		return false
	if event is InputEventScreenTouch:
		var vs: Vector2 = g.hud.size
		if event.pressed:
			# 按钮优先
			for b in btn_rects:
				if b[0].grow(8.0).has_point(event.position):
					_do(b[1])
					flash[b[1]] = 0.2
					return true
			# 属性面板：点任意处关闭
			if g.state == g.S.STATS:
				g.state = g.S.PLAY
				return true
			if g.state == g.S.PLAY and stick_id < 0 and event.position.x < vs.x * 0.55:
				stick_id = event.index
				stick_origin = event.position
				stick_pos = event.position
				vec = Vector2.ZERO
				return true
		else:
			if event.index == stick_id:
				stick_id = -1
				vec = Vector2.ZERO
				return true
	elif event is InputEventScreenDrag:
		if event.index == stick_id:
			stick_pos = event.position
			var d: Vector2 = stick_pos - stick_origin
			var l: float = d.length()
			if l < DEAD:
				vec = Vector2.ZERO
			else:
				# 摇杆中心跟着手指"拖走"：行程超出最大半径时把中心往手指方向挪，避免手指越滑越远
				if l > RADIUS:
					stick_origin = stick_pos - d / l * RADIUS
					d = stick_pos - stick_origin
				vec = d / RADIUS
				if vec.length() > 1.0:
					vec = vec.normalized()
			return true
	return false


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


func draw_hud(vs: Vector2) -> void:
	if not active:
		return
	var hud: CanvasItem = g.hud
	var font: Font = g.font
	btn_rects.clear()
	# 摇杆
	if stick_id >= 0 and g.state == g.S.PLAY:
		hud.draw_circle(stick_origin, RADIUS + 10.0, Color(0.05, 0.12, 0.16, 0.35))
		hud.draw_arc(stick_origin, RADIUS + 10.0, 0.0, TAU, 40, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.5), 2.0)
		var knob: Vector2 = stick_origin + vec * RADIUS
		hud.draw_circle(knob, 24.0, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.35))
		hud.draw_arc(knob, 24.0, 0.0, TAU, 24, Color(0.8, 1.0, 1.0, 0.8), 2.0)
	elif g.state == g.S.PLAY:
		# 提示：左下角淡淡的摇杆位置
		var c := Vector2(150, vs.y - 150)
		hud.draw_arc(c, 40.0, 0.0, TAU, 32, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.12), 1.5)
		hud.draw_circle(c, 10.0, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.12))
	# 冲刺按钮：右下角大圆（冷却中显示进度环）
	if g.state == g.S.PLAY:
		var dc := Vector2(vs.x - 110, vs.y - 170)
		var dr0 := Rect2(dc - Vector2(BTN * 0.7, BTN * 0.7), Vector2(BTN * 1.4, BTN * 1.4))
		btn_rects.append([dr0, "dash"])
		var ready: bool = g.dash_cd <= 0.0
		hud.draw_circle(dc, BTN * 0.7, Color(0.05, 0.12, 0.16, 0.7 if ready else 0.45))
		hud.draw_arc(dc, BTN * 0.7, -PI / 2.0, -PI / 2.0 + TAU * (1.0 - g.dash_cd / g.DASH_CD), 40, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.9 if ready else 0.5), 3.0)
		UI.text(hud, font, dc + Vector2(-40, 8), "冲刺", 18, Color(1, 1, 1, 0.9 if ready else 0.5), HORIZONTAL_ALIGNMENT_CENTER, 80)
	# 按钮：右侧中部纵向两个（暂停 / 属性）
	if g.state == g.S.PLAY or g.state == g.S.PAUSE or g.state == g.S.STATS:
		var items := [["Ⅱ", "pause", "暂停"], ["≡", "stats", "属性"]]
		for i in items.size():
			var c := Vector2(vs.x - 44, 200 + i * 70)
			var r := Rect2(c - Vector2(BTN / 2.0, BTN / 2.0), Vector2(BTN, BTN))
			btn_rects.append([r, items[i][1]])
			var lit: bool = flash.get(items[i][1], 0.0) > 0.0 or (items[i][1] == "pause" and g.state == g.S.PAUSE) or (items[i][1] == "stats" and g.state == g.S.STATS)
			hud.draw_circle(c, BTN / 2.0, Color(0.05, 0.12, 0.16, 0.75 if lit else 0.55))
			hud.draw_arc(c, BTN / 2.0, 0.0, TAU, 32, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.9 if lit else 0.5), 2.0)
			UI.text(hud, font, c + Vector2(-20, 7), items[i][0], 20, Color(1, 1, 1, 0.95 if lit else 0.8), HORIZONTAL_ALIGNMENT_CENTER, 40)
			UI.text(hud, font, c + Vector2(-30, BTN / 2.0 + 14), items[i][2], 10, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 60)
