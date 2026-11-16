extends Control
## 设置 → 操作 →「键位设置」（11-16 用户「自由更改键位」）：盖在设置面板上（同 perf_view / touch_editor），两页：键鼠 / 手柄。
## 每个局内动作两格（主键 + 备用），点格子（或选中按 Enter / Ⓐ）进入「按下新按键」，下一次按键 / 鼠标键（手柄页：按钮 / 扳机）就是新绑定。
## 冲突：新键已被别的动作占用 → 弹「已被『X』占用，交换？」（交换 = 对方拿到这一格原来的键）。Esc 固定为暂停 / 返回不能占；
## 网页版浏览器保留键（F5 / F11 / F12 / Ctrl / Alt / 鼠标侧键）不许绑（core/play_keys.gd forbidden）。每页一个「恢复默认」。
## 绑定表在 core/play_keys.gd；改动立即生效，设置面板关闭时随 Cfg.save() 写盘、Cloud.flush 上云（docs/89）。
## 触屏设备（含 B站 App 里的 Toy）也能打开（没有键盘时点格子只是进入等待，点别处取消，不报错）；触屏按键布局另在「触屏按键布局」改。

signal closed

const UI = preload("res://scripts/ui.gd")
const PlayKeys = preload("res://scripts/core/play_keys.gd")

const LISTEN_SECS := 6.0       # 等新按键的最长时间（只有手柄、没键盘的玩家也能自然退出）
const NOTE_SECS := 3.0

var font: Font
var pad_page := false          # false = 键鼠页，true = 手柄页
var sel := 0                   # 选中行（rows() 下标）；= rows().size() 时焦点在底栏按钮
var slot := 0                  # 选中格 0 主键 / 1 备用；底栏时 0 = 恢复默认 / 1 = 返回
var listen := false            # 正在等新按键
var listen_t := 0.0
var conflict := {}             # 冲突确认：{id, slot, code, who: [动作, 格], focus: 0 交换 / 1 取消}
var note := ""
var note_t := 0.0
var scroll := 0.0
var _drag := false
var _drag_y := 0.0
var _rects := {}               # 点击区：键 → Rect2（"tab0" / "tab1" / "s<行>_<格>" / "reset" / "back" / "swap" / "cancel"）
var _body := Rect2()


func _ready() -> void:
	font = load("res://fonts/ui.ttf")
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func open(pad := false) -> void:
	pad_page = pad
	sel = 0
	slot = 0
	listen = false
	conflict = {}
	note = ""
	scroll = 0.0
	position = Vector2.ZERO
	size = (get_parent() as Control).size if get_parent() is Control else Cfg.ui_size()
	visible = true
	Sfx.play("ui_ok")
	queue_redraw()


func close() -> void:
	visible = false
	listen = false
	conflict = {}
	Cfg.save()
	Sfx.play("ui_ok")
	closed.emit()


func _tl() -> bool:
	return Pad.touch_ui()


## 当前页的行：[{id, name}]；手柄页末尾加固定项 {fixed: 摇杆名, name}
func rows() -> Array:
	var out: Array = []
	for a in PlayKeys.ACTIONS:
		if pad_page and a.pad == null:
			continue
		out.append({"id": a.id, "name": a.name})
	if pad_page:
		for f in PlayKeys.PAD_FIXED:
			out.append({"id": "", "name": f[0], "fixed": f[1]})
	return out


func set_page(pad: bool) -> void:
	if pad == pad_page:
		return
	pad_page = pad
	sel = 0
	slot = 0
	scroll = 0.0
	listen = false
	conflict = {}
	Sfx.play("ui_move")
	queue_redraw()


func _row_ok(i: int, s: int) -> bool:
	var rs := rows()
	if i < 0 or i >= rs.size():
		return false
	var r: Dictionary = rs[i]
	return str(r.id) != "" and not PlayKeys.locked(str(r.id), s)


## 进入「按下新按键」（测试也直接调）
func begin_listen(i: int, s: int) -> void:
	if not _row_ok(i, s):
		_say(PlayKeys.forbidden(KEY_ESCAPE, false) if str(rows()[clampi(i, 0, rows().size() - 1)].id) == "pause" and not pad_page else "固定")
		return
	sel = i
	slot = s
	listen = true
	listen_t = 0.0
	Sfx.play("ui_move")
	queue_redraw()


## 收到一个新键码（键盘键 / -鼠标键 / 手柄按钮）：查禁用、查冲突、绑定。返回 true = 已绑定
func try_bind(code: int) -> bool:
	listen = false
	var id: String = str(rows()[sel].id)
	var why := PlayKeys.forbidden(code, pad_page)
	if why != "":
		_say(why)
		Sfx.play("ui_move", -4.0, 0.6)
		return false
	var who: Array = PlayKeys.bind(id, pad_page, slot, code, false)
	if who.is_empty():
		_changed()
		return true
	if PlayKeys.locked(str(who[0]), int(who[1])):
		_say(PlayKeys.forbidden(code, pad_page) if PlayKeys.forbidden(code, pad_page) != "" else "该按键不能绑定")
		return false
	conflict = {"id": id, "slot": slot, "code": code, "who": who, "focus": 0}
	Sfx.play("ui_move")
	queue_redraw()
	return false


## 冲突确认：yes = 交换
func resolve_conflict(yes: bool) -> void:
	if conflict.is_empty():
		return
	if yes:
		PlayKeys.bind(str(conflict.id), pad_page, int(conflict.slot), int(conflict.code), true)
		_changed()
	else:
		Sfx.play("ui_move")
	conflict = {}
	queue_redraw()


func clear_slot() -> void:
	listen = false
	var id: String = str(rows()[sel].id)
	if id == "" or PlayKeys.locked(id, slot):
		return
	PlayKeys.set_slot(id, pad_page, slot, PlayKeys.none(pad_page))
	_changed()


func reset_page() -> void:
	PlayKeys.reset_page(pad_page)
	Cfg.keybinds_set = true
	_say("已恢复默认键位")
	Sfx.play("ui_ok")
	queue_redraw()


func _changed() -> void:
	Cfg.keybinds_set = true
	Sfx.play("ui_ok")
	queue_redraw()


func _say(t: String) -> void:
	note = t
	note_t = NOTE_SECS
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	if note_t > 0.0:
		note_t -= delta
		if note_t <= 0.0:
			note = ""
			queue_redraw()
	if listen:
		listen_t += delta
		if listen_t >= LISTEN_SECS:
			listen = false
			queue_redraw()
		elif int(listen_t * 4.0) != int((listen_t - delta) * 4.0):
			queue_redraw()   # 等待中的格子闪烁


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var synth: bool = event.device == Pad.SYNTH_DEVICE
	# ── 冲突确认 ──
	if not conflict.is_empty():
		if event is InputEventKey and event.pressed and not event.echo:
			match Pad.kc(event):
				KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
					resolve_conflict(int(conflict.focus) == 0)
				KEY_Y:
					resolve_conflict(true)
				KEY_ESCAPE, KEY_BACKSPACE, KEY_N:
					resolve_conflict(false)
				KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
					conflict.focus = 1 - int(conflict.focus)
					Sfx.play("ui_move")
					queue_redraw()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var mp: Vector2 = event.position
			if _rects.has("swap") and (_rects.swap as Rect2).has_point(mp):
				resolve_conflict(true)
			elif _rects.has("cancel") and (_rects.cancel as Rect2).has_point(mp):
				resolve_conflict(false)
		get_viewport().set_input_as_handled()
		return
	# ── 等新按键 ──
	if listen:
		if not pad_page:
			if event is InputEventKey and event.pressed and not event.echo and not synth:
				var k: int = Pad.kc(event)
				if k == KEY_ESCAPE:
					listen = false
					queue_redraw()
				elif k == KEY_DELETE or k == KEY_BACKSPACE:
					clear_slot()
				elif k != KEY_NONE:
					try_bind(k)
			elif event is InputEventMouseButton and event.pressed:
				if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
					_say("滚轮不能绑定")
				elif _tl() and event.device == InputEvent.DEVICE_ID_EMULATION:
					listen = false   # 触屏模拟的点按：没有键盘的设备上点别处 = 取消
					queue_redraw()
				else:
					try_bind(-int(event.button_index))
			elif event is InputEventScreenTouch and event.pressed:
				listen = false
				queue_redraw()
		else:
			if event is InputEventJoypadButton and event.pressed and not synth:
				if event.button_index in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]:
					_say("该按键不能绑定")   # 十字键在对局里是移动
				else:
					try_bind(int(event.button_index))
			elif event is InputEventJoypadMotion and not synth and event.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT] and event.axis_value > 0.6:
				try_bind(PlayKeys.PAD_LT if event.axis == JOY_AXIS_TRIGGER_LEFT else PlayKeys.PAD_RT)
			elif event is InputEventKey and event.pressed and not synth and Pad.kc(event) == KEY_ESCAPE:
				listen = false
				queue_redraw()
			elif event is InputEventMouseButton and event.pressed:
				listen = false
				queue_redraw()
		get_viewport().set_input_as_handled()   # 等待中吞掉所有输入（含 Pad 把同一个按钮翻成的导航键）
		return
	# ── 浏览 ──
	if event is InputEventKey and event.pressed:
		var n: int = rows().size()
		match Pad.kc(event):
			KEY_ESCAPE, KEY_BACKSPACE:
				if not event.echo:
					close()
			KEY_UP:
				sel = maxi(0, sel - 1)
				_follow()
				Sfx.play("ui_move")
			KEY_DOWN:
				sel = mini(n, sel + 1)
				_follow()
				Sfx.play("ui_move")
			KEY_LEFT:
				slot = 0
				Sfx.play("ui_move")
			KEY_RIGHT:
				slot = 1
				Sfx.play("ui_move")
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				if event.echo:
					pass
				elif sel >= n:
					if slot == 0:
						reset_page()
					else:
						close()
				else:
					begin_listen(sel, slot)
			KEY_Q, KEY_E, KEY_PAGEUP, KEY_PAGEDOWN, KEY_TAB:
				if not event.echo:
					set_page(not pad_page)
			KEY_DELETE:
				if sel < n:
					clear_slot()
			_:
				return
		queue_redraw()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if not visible or listen or not conflict.is_empty():
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				scroll += (-40.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 40.0)
				queue_redraw()
			accept_event()
			return
		if event.button_index != MOUSE_BUTTON_LEFT:
			accept_event()
			return
		if event.pressed:
			_drag = true
			_drag_y = event.position.y
			accept_event()
			return
		var moved: bool = absf(event.position.y - _drag_y) > 12.0
		_drag = false
		if moved:
			accept_event()
			return
		_click(event.position)
		accept_event()
	elif event is InputEventMouseMotion and _drag:
		scroll -= event.relative.y
		queue_redraw()
		accept_event()


func _click(mp: Vector2) -> void:
	for k in _rects:
		if not (_rects[k] as Rect2).has_point(mp):
			continue
		var ks := str(k)
		if ks == "tab0" or ks == "tab1":
			set_page(ks == "tab1")
		elif ks == "reset":
			reset_page()
		elif ks == "back":
			close()
		elif ks.begins_with("s"):
			var parts := ks.substr(1).split("_")
			begin_listen(int(parts[0]), int(parts[1]))
		return


func _panel_rect() -> Rect2:
	var sr: Rect2 = Cfg.touch_safe_rect(size)
	var w: float = minf(sr.size.x - 24.0, 980.0)
	var h: float = minf(sr.size.y - 24.0, 640.0)
	return Rect2((sr.get_center() - Vector2(w, h) / 2.0).round(), Vector2(w, h))


func _rowh() -> float:
	return 50.0 if _tl() else 36.0


func _follow() -> void:
	var rh := _rowh()
	if sel >= rows().size():
		return
	var y0: float = sel * rh
	if y0 < scroll:
		scroll = y0
	elif y0 + rh > scroll + _body.size.y:
		scroll = y0 + rh - _body.size.y


## 一格的显示文字
func _slot_text(id: String, s: int) -> String:
	var c: int = int(PlayKeys.get_slots(id, pad_page)[s])
	if c == PlayKeys.none(pad_page):
		return "—"
	return PlayKeys.name_of(c, pad_page, true)


func _draw() -> void:
	_rects.clear()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.02, 0.03, 0.86))
	var pr := _panel_rect()
	draw_rect(pr, Color(0.035, 0.05, 0.065, 0.98))
	UI.frame(self, pr, UI.CYAN)
	var tl := _tl()
	var fs_t: int = 24 if tl else 22
	UI.text(self, font, pr.position + Vector2(24, 40), "键位设置", fs_t, UI.TEXT)
	UI.en(self, font, pr.position + Vector2(26, 58), "KEY BINDINGS", 9, UI.SUB, 1.0)
	# 页签：键鼠 / 手柄
	var tw: float = 150.0 if tl else 132.0
	var th: float = 40.0 if tl else 32.0
	for i in 2:
		var r := Rect2(pr.end.x - 24.0 - tw * (2 - i) - 8.0 * (1 - i), pr.position.y + 18.0, tw, th)
		_rects["tab%d" % i] = r
		var on: bool = (i == 1) == pad_page
		draw_rect(r, UI.CYAN if on else Color(0.04, 0.09, 0.12, 0.9))
		draw_rect(r, UI.CYAN if on else Color("3b4652"), false, 1.0)
		UI.text(self, font, Vector2(r.position.x, r.get_center().y + 6.0), ["键鼠", "手柄"][i], 16 if tl else 14, Color("131820") if on else UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	if not tl:
		UI.text(self, font, Vector2(pr.end.x - 24.0 - tw * 2.0 - 8.0 - 90.0, pr.position.y + 40.0), "Q / E" if not Pad.using else "LB / RB", 11, UI.SUB, HORIZONTAL_ALIGNMENT_RIGHT, 80)
	# 列头
	var name_w: float = clampf(pr.size.x * 0.34, 150.0, 300.0)
	var x0: float = pr.position.x + 24.0
	var sw: float = minf(220.0, (pr.size.x - 48.0 - name_w - 16.0) / 2.0)
	var sx := [x0 + name_w, x0 + name_w + sw + 16.0]
	var hy: float = pr.position.y + (82.0 if tl else 76.0)
	UI.text(self, font, Vector2(sx[0], hy), "主键", 12, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, sw)
	UI.text(self, font, Vector2(sx[1], hy), "备用", 12, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, sw)
	draw_line(Vector2(x0, hy + 8.0), Vector2(pr.end.x - 24.0, hy + 8.0), Color("3b4652"), 1.0)
	# 底栏
	var bh: float = 50.0 if tl else 38.0
	var by: float = pr.end.y - bh - 16.0
	var hint_y: float = by - (36.0 if tl else 30.0)
	_body = Rect2(x0, hy + 14.0, pr.size.x - 48.0, maxf(40.0, hint_y - (hy + 14.0) - 8.0))
	var rs := rows()
	var rh := _rowh()
	scroll = clampf(scroll, 0.0, maxf(0.0, rs.size() * rh - _body.size.y))
	var fs_r: int = 17 if tl else 14
	for i in rs.size():
		var ry: float = _body.position.y + i * rh - scroll
		if ry < _body.position.y - 1.0 or ry + rh > _body.end.y + 1.0:
			continue
		var row: Dictionary = rs[i]
		var focus_row: bool = i == sel
		if focus_row:
			draw_rect(Rect2(x0 - 8.0, ry + 2.0, pr.size.x - 32.0, rh - 4.0), Color(UI.CYAN, 0.07))
		UI.text(self, font, Vector2(x0, ry + rh / 2.0 + 6.0), str(row.name), fs_r, UI.TEXT)
		if row.has("fixed"):
			var fr := Rect2(sx[0], ry + 4.0, sw * 2.0 + 16.0, rh - 8.0)
			draw_rect(fr, Color(0.03, 0.05, 0.07, 0.6))
			UI.text(self, font, Vector2(fr.position.x, fr.get_center().y + 6.0), "%s（%s）" % [UI.Loc.s(str(row.fixed)), UI.Loc.s("固定")], fs_r - 1, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, fr.size.x)
			continue
		for s in 2:
			var r := Rect2(sx[s], ry + 4.0, sw, rh - 8.0)
			var lock: bool = PlayKeys.locked(str(row.id), s)
			var cur: bool = focus_row and slot == s
			var wait: bool = cur and listen
			if not lock:
				_rects["s%d_%d" % [i, s]] = r
			var fill := Color(0.04, 0.09, 0.12, 0.9)
			var edge := Color("3b4652")
			if wait:
				fill = Color(UI.GOLD, 0.18 if int(listen_t * 4.0) % 2 == 0 else 0.08)
				edge = UI.GOLD
			elif cur:
				fill = Color(UI.CYAN, 0.16)
				edge = UI.CYAN
			if lock:
				fill = Color(0.03, 0.05, 0.07, 0.6)
			draw_rect(r, fill)
			draw_rect(r, edge, false, 1.0)
			var txt: String = ("按下新的手柄按键…" if pad_page else "按下新按键…") if wait else _slot_text(str(row.id), s)
			if lock:
				txt = "%s（%s）" % [_slot_text(str(row.id), s), UI.Loc.s("固定")]
			var col: Color = UI.GOLD if wait else (UI.SUB if lock or txt == "—" else UI.TEXT)
			_center_text(r, txt, fs_r, col)
	# 滚动提示条
	if rs.size() * rh > _body.size.y + 1.0:
		var frac: float = _body.size.y / (rs.size() * rh)
		var bar_h: float = _body.size.y * frac
		var bar_y: float = _body.position.y + (scroll / maxf(1.0, rs.size() * rh - _body.size.y)) * (_body.size.y - bar_h)
		draw_rect(Rect2(pr.end.x - 14.0, bar_y, 3.0, bar_h), Color(UI.CYAN, 0.6))
	# 说明行
	var hint: String
	if listen:
		hint = "Esc 取消 · Delete 清空" if not pad_page else "Esc 取消"
	elif tl and not Pad.using:
		hint = "触屏按键请在「触屏按键布局」里调整"
	elif Pad.using:
		hint = "选中格子按 Ⓐ，再按新按钮"
	else:
		hint = "点格子后按下新按键"
	var extra: String = "网页版不能绑定浏览器保留键（F5、F11、F12、Ctrl、Alt 等）" if OS.has_feature("web") and not pad_page else "改键在局内立即生效"
	UI.text(self, font, Vector2(x0, hint_y + 14.0), UI.Loc.s(hint) + "  ·  " + UI.Loc.s(extra), 12 if not tl else 14, UI.SUB)
	draw_line(Vector2(pr.position.x, by - 10.0), Vector2(pr.end.x, by - 10.0), Color("3b4652"), 1.0)
	var n: int = rs.size()
	var rw: float = minf(200.0, pr.size.x * 0.3)
	var rr := Rect2(x0, by, rw, bh)
	var bw: float = minf(150.0, pr.size.x * 0.24)
	var rb := Rect2(pr.end.x - 24.0 - bw, by, bw, bh)
	_rects["reset"] = rr
	_rects["back"] = rb
	var fr0: bool = sel >= n and slot == 0
	var fr1: bool = sel >= n and slot == 1
	draw_rect(rr, Color(UI.CYAN, 0.16) if fr0 else Color(0.04, 0.09, 0.12, 0.9))
	draw_rect(rr, UI.CYAN if fr0 else UI.CYAN_DIM, false, 1.0)
	UI.text(self, font, Vector2(rr.position.x, rr.get_center().y + 6.0), "恢复默认", 17 if tl else 15, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, rr.size.x)
	draw_rect(rb, UI.CYAN if not fr1 else UI.GOLD)
	UI.text(self, font, Vector2(rb.position.x, rb.get_center().y + 6.0), UI.Loc.s("返回") + ("" if tl or Pad.using else "  Esc"), 17 if tl else 15, Color("131820"), HORIZONTAL_ALIGNMENT_CENTER, rb.size.x)
	if note != "":
		var msg := UI.fit(font, note, rb.position.x - rr.end.x - 24.0, bh, [15, 13, 12])
		UI.draw_fit(self, font, Vector2(rr.end.x + 12.0, by), msg, UI.GOLD)
	# 冲突确认框
	if not conflict.is_empty():
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45))
		var cw: float = minf(520.0, pr.size.x - 48.0)
		var ch: float = 170.0 if tl else 150.0
		var cr := Rect2(pr.get_center() - Vector2(cw, ch) / 2.0, Vector2(cw, ch))
		draw_rect(cr, Color(0.04, 0.06, 0.08, 0.99))
		UI.frame(self, cr, UI.GOLD)
		var who: Array = conflict.who
		var line: String = "已被「%s」占用，交换？" % str(PlayKeys.def_of(str(who[0])).get("name", ""))   # 显示时按模板翻（动作名再查一次表）
		var keyname: String = PlayKeys.name_of(int(conflict.code), pad_page, true)
		UI.text(self, font, Vector2(cr.position.x, cr.position.y + 40.0), keyname, 20 if tl else 18, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER, cr.size.x)
		var lf := UI.fit(font, line, cr.size.x - 40.0, 48.0, [17, 15, 13] if tl else [15, 14, 12])
		UI.draw_fit(self, font, Vector2(cr.position.x + 20.0, cr.position.y + 50.0), lf, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, cr.size.x - 40.0)
		var bw2: float = (cr.size.x - 60.0) / 2.0
		var bh2: float = 44.0 if tl else 34.0
		var r_yes := Rect2(cr.position.x + 20.0, cr.end.y - bh2 - 16.0, bw2, bh2)
		var r_no := Rect2(r_yes.end.x + 20.0, r_yes.position.y, bw2, bh2)
		_rects["swap"] = r_yes
		_rects["cancel"] = r_no
		for k in 2:
			var r: Rect2 = [r_yes, r_no][k]
			var f: bool = int(conflict.focus) == k
			draw_rect(r, UI.GOLD if f else Color(0.04, 0.09, 0.12, 0.9))
			draw_rect(r, UI.GOLD if f else Color("3b4652"), false, 1.0)
			UI.text(self, font, Vector2(r.position.x, r.get_center().y + 6.0), ["交换", "取消"][k], 16 if tl else 14, Color("131820") if f else UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


## 格子里的字：单行居中，放不下先缩字号再截断
func _center_text(r: Rect2, txt: String, size: int, col: Color) -> void:
	var fl: Array = UI.fit_line(font, txt, size, r.size.x - 10.0, 10)
	var fsz: int = int(fl[1])
	var y: float = r.position.y + (r.size.y + font.get_ascent(fsz) - font.get_descent(fsz)) / 2.0
	draw_string(font, Vector2(r.position.x + 5.0, y), str(fl[0]), HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 10.0, fsz, col)
