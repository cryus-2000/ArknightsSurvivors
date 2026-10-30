extends Control
## 触屏按键布局编辑页（设置 → 游戏 → 触屏按键布局，用户 10-13）：半透明网格上摆出摇杆、冲刺、技能、瞄准、暂停、属性、倍速，
## 按住拖动改位置，选中后在中间的面板里调大小（70%–150%），选中瞄准键时可隐藏 / 显示它（TouchLayout.atk_hidden）；「恢复默认」清空自定义，「完成」写进存档（Cfg.touch_layout → settings.cfg），
## 「取消」/ Esc 放弃本次改动。位置与夹紧规则全在 touch_layout.gd：拖动时整个按键（含标签）留在安全区内，
## 松手时和别的按键几乎整个叠在一起就沿连线推开，推不开退回拖动前的位置。
## 父节点是设置面板（标题页与局内暂停共用）；输入走触摸模拟的鼠标事件（_gui_input），桌面鼠标同样能用。

signal closed

const UI = preload("res://scripts/ui.gd")
const TouchLayout = preload("res://scripts/touch_layout.gd")

const PANEL_W := 470.0
const PANEL_H := 172.0
const GRID := 32.0

var font: Font
var work := {}               # 编辑中的布局（与 Cfg.touch_layout 同格式）
var sel := "dash"            # 选中的按键
var dragging := ""           # 正在拖的按键（空 = 没在拖）
var drag_off := Vector2.ZERO
var drag_prev = null         # 拖动前该键的存档条目（null = 原来是缺省位置）
var slider_drag := false
var btn_rects := {}          # 面板按钮：动作 -> Rect2
var slider_rect := Rect2()
var t := 0.0


func _ready() -> void:
	font = load("res://fonts/ui.ttf")
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func open() -> void:
	work = Cfg.touch_layout.duplicate(true)
	sel = "dash"
	dragging = ""
	slider_drag = false
	position = Vector2.ZERO
	size = (get_parent() as Control).size if get_parent() is Control else Cfg.ui_size()
	visible = true
	queue_redraw()


func shown_keys() -> Array:
	var ks: Array = ["stick", "dash", "skill", "atk", "pause", "stats", "speed"]   # 瞄准键隐藏时仍列出（画淡），选中它才能再显示
	if preload("res://scripts/characters/squad.gd").cmd_on():
		ks.append("cmd")
	return ks


func safe() -> Rect2:
	return Cfg.touch_safe_rect(size)


func lay() -> Dictionary:
	return TouchLayout.resolve(size, not atk_off(), work, safe(), Cfg.phone_ui())


func atk_off() -> bool:
	return TouchLayout.atk_hidden(work)


func panel_rect() -> Rect2:
	var sr := safe()
	return Rect2((sr.get_center() - Vector2(PANEL_W, PANEL_H) / 2.0).round(), Vector2(PANEL_W, PANEL_H))


func close(save: bool) -> void:
	if save:
		Cfg.touch_layout = TouchLayout.sanitize(work)
		Cfg.save()
	visible = false
	Sfx.play("ui_ok")
	closed.emit()


func _process(delta: float) -> void:
	if visible:
		t += delta
		if get_parent() is Control and size != (get_parent() as Control).size:
			size = (get_parent() as Control).size   # 转屏 / 浏览器栏收起：跟着父节点（设置面板撑满 UI 区）
		queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and Pad.kc(event) == KEY_ESCAPE:
		close(false)
		get_viewport().set_input_as_handled()


## 某点下的按键：外框外扩 10 后包含该点的里面取中心最近的
func key_at(p: Vector2) -> String:
	var L := lay()
	var best := ""
	var bd := INF
	for k in shown_keys():
		var e: Dictionary = L[k]
		var bx: Rect2 = TouchLayout.bounds(k, e.s)
		bx.position += e.c
		if bx.grow(10.0).has_point(p) and p.distance_to(e.c) < bd:
			bd = p.distance_to(e.c)
			best = k
	return best


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = event.position
		if event.pressed:
			_press(p)
		else:
			_release()
		accept_event()
	elif event is InputEventMouseMotion:
		if dragging != "":
			_drag_to(event.position)
		elif slider_drag:
			_slider_to(event.position.x)
		accept_event()


func _press(p: Vector2) -> void:
	# 面板上的按钮 / 滑块优先（面板在画面中央，一般没有按键压在上面）；拖动中的按键会画在面板之上
	for a in btn_rects:
		if (btn_rects[a] as Rect2).has_point(p):
			_action(a)
			return
	if slider_rect.grow(12.0).has_point(p):
		slider_drag = true
		_slider_to(p.x)
		return
	var k := key_at(p)
	if k == "":
		return
	sel = k
	var L := lay()
	if k == "dash":
		# 技能 / 瞄准键缺省跟着冲刺键走：开始拖冲刺键前先把它们定在当前位置，所见即所得
		for f in ["skill", "atk"]:
			if not work.has(f) and (f != "atk" or not atk_off()):
				work[f] = TouchLayout.encode(L[f].c, size, L[f].s)
	drag_prev = work.get(k)
	if drag_prev is Dictionary:
		drag_prev = (drag_prev as Dictionary).duplicate()
	dragging = k
	drag_off = p - L[k].c
	Sfx.play("ui_move", -6.0)


func _drag_to(p: Vector2) -> void:
	var s: float = lay()[dragging].s
	var c: Vector2 = TouchLayout.clamp_center(p - drag_off, dragging, s, safe())
	work[dragging] = TouchLayout.encode(c, size, s)


func _release() -> void:
	slider_drag = false
	if dragging == "":
		return
	var k := dragging
	dragging = ""
	if not _settle(k):
		# 推不开（四周都挤满）：退回拖动前
		if drag_prev is Dictionary:
			work[k] = drag_prev
		else:
			work.erase(k)
	Sfx.play("ui_ok", -8.0)


## 让 k 不和其它按键整个叠在一起：返回 false 表示推不开
func _settle(k: String) -> bool:
	var L := lay()
	var others := {}
	for o in shown_keys():
		if o != k and not (o == "atk" and atk_off()):   # 隐藏的瞄准键不占位置
			others[o] = L[o]
	var p: Vector2 = TouchLayout.separate(k, L[k].c, L[k].s, others, safe())
	if p == Vector2.INF:
		return false
	work[k] = TouchLayout.encode(p, size, L[k].s)
	return true


func _slider_to(x: float) -> void:
	var f: float = clampf((x - slider_rect.position.x) / slider_rect.size.x, 0.0, 1.0)
	_set_scale(lerpf(TouchLayout.S_MIN, TouchLayout.S_MAX, f))


func _set_scale(s: float) -> void:
	var L := lay()
	var old = work.get(sel)
	var ns: float = TouchLayout.clamp_scale(s)
	if is_equal_approx(ns, float(L[sel].s)):
		return
	work[sel] = TouchLayout.encode(L[sel].c, size, ns)
	# 放大后夹回安全区、和旁边的按键推开；推不开就不放大
	var c2: Vector2 = TouchLayout.clamp_center(L[sel].c, sel, ns, safe())
	work[sel] = TouchLayout.encode(c2, size, ns)
	if not _settle(sel):
		if old is Dictionary:
			work[sel] = old
		else:
			work.erase(sel)
		return
	Sfx.play("ui_move", -10.0)


func _action(a: String) -> void:
	match a:
		"minus":
			_set_scale(float(lay()[sel].s) - 0.1)
		"plus":
			_set_scale(float(lay()[sel].s) + 0.1)
		"reset":
			work = {}
			Sfx.play("ui_ok")
		"hide":
			if atk_off():
				work.erase("atk_off")
			else:
				work["atk_off"] = true
			Sfx.play("ui_move", -6.0)
		"cancel":
			close(false)
		"done":
			close(true)


func _draw() -> void:
	var vs := size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.0, 0.02, 0.04, 0.82))
	# 半透明网格 + 安全区边框
	var gx := 0.0
	while gx <= vs.x:
		draw_rect(Rect2(gx, 0, 1, vs.y), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.06))
		gx += GRID
	var gy := 0.0
	while gy <= vs.y:
		draw_rect(Rect2(0, gy, vs.x, 1), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.06))
		gy += GRID
	var sr := safe()
	draw_rect(sr, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.3), false, 1.0)
	var L := lay()
	var pr := panel_rect()
	# 面板（拖动时变淡，按键画在它上面）
	_draw_panel(pr, L, 0.35 if dragging != "" else 1.0)
	for k in shown_keys():
		_draw_key(k, L[k], k == sel, k == dragging)


func _draw_panel(r: Rect2, L: Dictionary, a: float) -> void:
	draw_rect(r, Color(0.03, 0.05, 0.07, 0.92 * a))
	draw_rect(r, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.6 * a), false, 1.0)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, a))
	var x0 := r.position.x + 20.0
	UI.text(self, font, Vector2(x0, r.position.y + 32), "触屏按键布局", 20, Color(UI.TEXT.r, UI.TEXT.g, UI.TEXT.b, a))
	UI.en(self, font, Vector2(x0 + 132, r.position.y + 30), "TOUCH LAYOUT", 10, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, a), 2.5)
	UI.text(self, font, Vector2(x0, r.position.y + 56), "拖动按键调整位置；选中按键后调整大小", 13, Color(UI.SUB.r, UI.SUB.g, UI.SUB.b, a))
	btn_rects.clear()
	if sel == "atk":
		# 瞄准键可隐藏：普攻永远自动，不用瞄准键也能玩
		var hr := Rect2(r.end.x - 20.0 - 96.0, r.position.y + 16.0, 96.0, 30.0)
		btn_rects["hide"] = hr
		draw_rect(hr, Color(1, 1, 1, 0.06 * a))
		draw_rect(hr, Color(1.0, 0.72, 0.4, 0.6 * a), false, 1.0)
		UI.text(self, font, hr.position + Vector2(0, 21), "显示此键" if atk_off() else "隐藏此键", 14, Color(UI.TEXT.r, UI.TEXT.g, UI.TEXT.b, a), HORIZONTAL_ALIGNMENT_CENTER, hr.size.x)
	# 大小：选中按键名 + − / 滑块 / + / 百分比
	var e: Dictionary = L[sel]
	var y := r.position.y + 76.0
	UI.text(self, font, Vector2(x0, y + 22), TouchLayout.NAMES[sel], 16, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, a))
	var bx := x0 + 92.0
	btn_rects["minus"] = Rect2(bx, y, 40, 32)
	slider_rect = Rect2(bx + 52, y + 12, 180, 8)
	btn_rects["plus"] = Rect2(bx + 244, y, 40, 32)
	for k in ["minus", "plus"]:
		var br: Rect2 = btn_rects[k]
		draw_rect(br, Color(1, 1, 1, 0.06 * a))
		draw_rect(br, Color(1, 1, 1, 0.3 * a), false, 1.0)
		# 减号 / 加号用色块画（字库子集未必有全角符号）
		var cc: Vector2 = br.get_center().round()
		draw_rect(Rect2(cc - Vector2(8, 1), Vector2(16, 2)), Color(UI.TEXT.r, UI.TEXT.g, UI.TEXT.b, a))
		if k == "plus":
			draw_rect(Rect2(cc - Vector2(1, 8), Vector2(2, 16)), Color(UI.TEXT.r, UI.TEXT.g, UI.TEXT.b, a))
	var f: float = (float(e.s) - TouchLayout.S_MIN) / (TouchLayout.S_MAX - TouchLayout.S_MIN)
	draw_rect(slider_rect, Color(0.15, 0.22, 0.26, a))
	draw_rect(Rect2(slider_rect.position, Vector2(slider_rect.size.x * f, slider_rect.size.y)), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, a))
	var kx: float = slider_rect.position.x + slider_rect.size.x * f
	draw_rect(Rect2(kx - 4, slider_rect.position.y - 7, 8, 22), Color(0.9, 1.0, 1.0, a))
	# 100% 刻度
	var f1: float = (1.0 - TouchLayout.S_MIN) / (TouchLayout.S_MAX - TouchLayout.S_MIN)
	draw_rect(Rect2(slider_rect.position.x + slider_rect.size.x * f1 - 0.5, slider_rect.end.y + 3, 1, 5), Color(1, 1, 1, 0.4 * a))
	UI.text(self, font, Vector2(bx + 292, y + 23), "%d%%" % int(round(float(e.s) * 100.0)), 16, Color(UI.TEXT.r, UI.TEXT.g, UI.TEXT.b, a))
	# 底行：恢复默认 / 取消 / 完成
	var by := r.end.y - 50.0
	var acts := [["reset", "恢复默认"], ["cancel", "取消"], ["done", "完成"]]
	var bw := (r.size.x - 40.0 - 2 * 12.0) / 3.0
	for i in acts.size():
		var br := Rect2(x0 + i * (bw + 12.0), by, bw, 38)
		btn_rects[acts[i][0]] = br
		var main: bool = acts[i][0] == "done"
		draw_rect(br, Color(0.05, 0.2, 0.24, 0.9 * a) if main else Color(1, 1, 1, 0.05 * a))
		draw_rect(br, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, (0.9 if main else 0.35) * a), false, 1.0)
		UI.text(self, font, br.position + Vector2(0, 25), acts[i][1], 16, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, a) if main else Color(UI.TEXT.r, UI.TEXT.g, UI.TEXT.b, a), HORIZONTAL_ALIGNMENT_CENTER, br.size.x)


## 画一个按键：外形尽量和局内一致（touch.gd），选中时青色粗环 + 外框虚线
func _draw_key(k: String, e: Dictionary, on: bool, drag: bool) -> void:
	var c: Vector2 = e.c
	var s: float = e.s
	var r: float = TouchLayout.radius(k) * s
	var ring := Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 1.0 if on else 0.6)
	var off: bool = k == "atk" and atk_off()   # 隐藏的瞄准键画淡，标「已隐藏」
	match k:
		"stick":
			draw_arc(c, TouchLayout.RADIUS * s + 10.0 * s, 0.0, TAU, 48, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.25), 1.5)
			draw_circle(c, r, Color(0.05, 0.12, 0.16, 0.6))
			draw_arc(c, r, 0.0, TAU, 40, ring, 3.0 if on else 2.0)
			draw_circle(c, 10.0 * s, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.5))
		"speed":
			var rr := Rect2(c - Vector2(28, 17) * s, Vector2(56, 34) * s)
			draw_rect(rr, Color(0.05, 0.12, 0.16, 0.7))
			draw_rect(rr, ring, false, 2.0 if on else 1.0)
			UI.text(self, font, rr.position + Vector2(0, rr.size.y / 2.0 + 6.0), "1×", int(round(16.0 * clampf(s, 0.85, 1.3))), UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, rr.size.x)
		_:
			var fill := Color(0.14, 0.08, 0.04, 0.3 if off else 0.75) if k == "atk" else Color(0.05, 0.12, 0.16, 0.75)
			draw_circle(c, r, fill)
			draw_arc(c, r, 0.0, TAU, 40, Color(1.0, 0.72, 0.4, (1.0 if on else 0.6) * (0.5 if off else 1.0)) if k == "atk" else ring, 3.0 if on else 2.0)
			var glyph: String = {"dash": "冲刺", "skill": "技能", "atk": "瞄准", "pause": "Ⅱ", "stats": "≡", "cmd": "随行"}.get(k, "")
			var fs: int = int(round((18.0 if k in ["dash", "skill", "atk"] else (13.0 if k == "cmd" else 20.0)) * clampf(s, 0.8, 1.3)))
			UI.text(self, font, c + Vector2(-40, fs * 0.4), glyph, fs, Color(UI.TEXT.r, UI.TEXT.g, UI.TEXT.b, 0.45 if off else 1.0), HORIZONTAL_ALIGNMENT_CENTER, 80)
			if off:
				UI.text(self, font, c + Vector2(-50, r + 16.0), "已隐藏", 13, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 100)
	# 名称标签（控件下方；冲刺 / 技能 / 攻击的名字已经写在圆里）
	if k in ["stick", "pause", "stats", "speed", "cmd"]:
		var bx: Rect2 = TouchLayout.bounds(k, s)
		UI.text(self, font, c + Vector2(-50, bx.end.y + 2.0 if k != "stick" else r + 16.0), TouchLayout.NAMES[k], 13, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 100)
	if on:
		var bx2: Rect2 = TouchLayout.bounds(k, s)
		bx2.position += c
		_dashed_rect(bx2.grow(6.0), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.5 + 0.3 * sin(t * 5.0) if not drag else 0.9))


func _dashed_rect(r: Rect2, col: Color) -> void:
	var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % 4]
		var n := int(a.distance_to(b) / 8.0)
		for j in n:
			if j % 2 == 0:
				draw_line(a.lerp(b, float(j) / n), a.lerp(b, float(j + 1) / n), col, 1.0)
