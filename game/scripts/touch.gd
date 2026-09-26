## 触屏操作（移动端 / 网页版）：左半屏浮动虚拟摇杆（手指按下处即摇杆中心），右侧两个按钮（暂停 / 属性）。
## 技能基本全自动；主控有手动技能时冲刺键上方多一个技能键（干员契约 v2.3 / v2.4：点一下 = 自动瞄准，按住拖动 = 朝拖动方向放）。面板 / 商店 / 结算里的按钮走 Godot 的"触摸模拟鼠标"，不在这里处理。
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
## 手动技能键（主控有已解锁的手动技能时，冲刺键上方）：按下记触点，松手释放。
## 带方向的技能（JSON "aim": true）按住时拖出方向 skill_aim，场上画落点圈（hud.draw_manual_aim）；拖动不到 AIM_DEAD = 点一下 = 自动瞄准
const AIM_DEAD := 22.0
var skill_id := -1          # 正在按技能键的触点（-1 = 没按）
var skill_origin := Vector2.ZERO
var skill_aim := Vector2.ZERO
var skill_rect := Rect2()


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
			# 技能键：按下只记触点，松手才释放（以后可以改成拖动瞄准）
			if skill_rect.size.x > 0.0 and skill_id < 0 and skill_rect.grow(8.0).has_point(event.position):
				skill_id = event.index
				skill_origin = event.position
				skill_aim = Vector2.ZERO
				return true
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
			if event.index == skill_id:
				skill_id = -1
				flash["skill"] = 0.2
				if g.state == g.S.PLAY:
					# 一定要传方向：不传会读摇杆移动方向，边走边点就朝走的方向放了。没就绪时它自己飘字说原因；正在出手时记下、1 秒内放出
					g.doctor.try_manual_skill(aim_dir())
				return true
			if event.index == stick_id:
				stick_id = -1
				vec = Vector2.ZERO
				return true
	elif event is InputEventScreenDrag:
		if event.index == skill_id:
			skill_aim = event.position - skill_origin
			return true
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
		_draw_skill_button(hud, font, dc + Vector2(0, -BTN * 1.4 - 26.0))
	else:
		skill_rect = Rect2()
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


## 手动技能键：圆底 + 技能图标 + 外圈充能；就绪时青色呼吸外圈。只在主控有已解锁的手动技能时画（干员契约 v2.3：手动只对主控）
func _draw_skill_button(hud: CanvasItem, font: Font, c: Vector2) -> void:
	skill_rect = Rect2()
	var ld = g.squad.leader()
	if ld == null:
		return
	var i: int = ld.manual_index()
	if i < 0 or not ld.skill_unlocked(i):
		return
	var r := BTN * 0.7
	skill_rect = Rect2(c - Vector2(r, r), Vector2(r * 2.0, r * 2.0))
	var need: float = ld.sp_need(i)
	var frac: float = clampf(ld.sp[i] / need, 0.0, 1.0) if need > 0.0 else 1.0
	var ready: bool = g.hud_view.manual_castable(ld, i)
	var held: bool = skill_id >= 0 or flash.get("skill", 0.0) > 0.0
	hud.draw_circle(c, r, Color(0.05, 0.12, 0.16, 0.8 if ready or held else 0.5))
	var tx: Texture2D = g.tex.get(ld.skill_def(i).get("icon", ""))
	if tx != null:
		var s := r * 1.2
		hud.draw_texture_rect(tx, Rect2(c - Vector2(s, s) / 2.0, Vector2(s, s)), false, Color.WHITE if ready else Color(0.55, 0.58, 0.62))
	else:
		UI.text(hud, font, c + Vector2(-40, 7), ld.skill_def(i).get("name", "技能").substr(0, 2), 16, Color(1, 1, 1, 0.9 if ready else 0.5), HORIZONTAL_ALIGNMENT_CENTER, 80)
	hud.draw_arc(c, r, -PI / 2.0, -PI / 2.0 + TAU * frac, 40, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.95 if ready else 0.5), 3.0)
	if ready:
		var pulse: float = 0.5 + 0.5 * sin(g.t * 6.0)
		hud.draw_arc(c, r + 4.0 + 2.0 * pulse, 0.0, TAU, 40, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.35 + 0.4 * pulse), 2.0)
	UI.text(hud, font, c + Vector2(-40, r + 16), ld.skill_def(i).get("name", ""), 11, UI.TEXT if ready else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 80)
	# 按住拖动：按钮上画小摇杆（外圈 = 拖动示意范围，内圈 = 死区，拖回内圈 = 自动瞄准）
	if skill_id >= 0 and ld.manual_aims(i):
		var reach := r + 30.0
		hud.draw_arc(c, reach, 0.0, TAU, 40, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.35), 1.5)
		hud.draw_arc(c, AIM_DEAD, 0.0, TAU, 24, Color(1, 1, 1, 0.25), 1.0)
		var k: Vector2 = skill_aim.limit_length(reach)
		hud.draw_circle(c + k, 14.0, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.45 if aim_dir() != Vector2.ZERO else 0.25))
		hud.draw_arc(c + k, 14.0, 0.0, TAU, 20, Color(0.85, 1.0, 1.0, 0.9), 2.0)
