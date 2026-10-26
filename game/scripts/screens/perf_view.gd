extends Control
## 设置 → 画面 →「性能报告」（10-27 用户，core/perf_report.gd 采集）：盖在设置面板上，显示最近一局的性能摘要和更早几局各一行；
## 「复制报告」把最近一局的精简纯文本放进剪贴板。网页先走浏览器剪贴板 API（navigator.clipboard，异步，iOS 上不在点击手势里时常被拒），
## 1 秒内没成功就在网页上盖一个可全选的文本框（DOM textarea，长按全选复制）；桌面复制失败时显示引擎文本框（可全选）。
## 父节点是设置面板（标题页与局内暂停共用）；输入走触摸模拟的鼠标事件（_gui_input），Esc / 返回键关闭，Enter 复制

signal closed

const UI = preload("res://scripts/ui.gd")
const PerfReport = preload("res://scripts/core/perf_report.gd")

var font: Font
var recs: Array = []
var text := ""
var btn_rects := {}       # 动作 -> Rect2
var note := ""            # 复制结果提示
var note_t := 0.0
var _copy_wait := -1.0    # 网页：等浏览器剪贴板回话（秒，< 0 = 没在等）
var box: TextEdit = null  # 复制失败时的文本框（桌面）


func _ready() -> void:
	font = load("res://fonts/ui.ttf")
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func open() -> void:
	recs = PerfReport.load_all()
	text = PerfReport.report_text(recs[0]) if not recs.is_empty() else ""
	note = ""
	_copy_wait = -1.0
	position = Vector2.ZERO
	size = (get_parent() as Control).size if get_parent() is Control else Cfg.ui_size()
	if box != null:
		box.visible = false
	visible = true
	Sfx.play("ui_ok")
	queue_redraw()


func close() -> void:
	visible = false
	if box != null:
		box.visible = false
	if OS.has_feature("web"):
		JavaScriptBridge.eval("var e=document.getElementById('sy-perf-copy');if(e)e.remove();", true)
	Sfx.play("ui_ok")
	closed.emit()


func _tl() -> bool:
	return Pad.touch_ui()


func copy() -> void:
	if text == "":
		return
	if OS.has_feature("web"):
		JavaScriptBridge.eval("(function(t){window.__syCopy=-1;try{navigator.clipboard.writeText(t).then(function(){window.__syCopy=1},function(){window.__syCopy=0})}catch(e){window.__syCopy=0}})(%s)" % JSON.stringify(text), true)
		_copy_wait = 0.0
		note = "正在复制……"
	else:
		DisplayServer.clipboard_set(text)
		if DisplayServer.clipboard_get() == text:
			_copied()
		else:
			_fallback()
	queue_redraw()


func _copied() -> void:
	note = "已复制到剪贴板，可以直接粘贴"
	note_t = 4.0
	Sfx.play("ui_ok")


## 剪贴板不可用：给一个能全选的文本框
func _fallback() -> void:
	note = "没能直接复制：已打开文本框，长按或拖选全部文字后复制" if _tl() else "没能直接复制：已打开文本框，全选（Ctrl+A）后复制"
	note_t = 8.0
	if OS.has_feature("web"):
		var js := """(function(t){var o=document.getElementById('sy-perf-copy');if(o)o.remove();
o=document.createElement('div');o.id='sy-perf-copy';
o.style.cssText='position:fixed;left:5%;top:8%;width:90%;height:76%;z-index:99999;background:#0d1419;border:1px solid #3fd2e6;padding:12px;box-sizing:border-box;display:flex;flex-direction:column;gap:8px';
var a=document.createElement('textarea');a.value=t;a.readOnly=true;
a.style.cssText='flex:1;width:100%;font-size:15px;line-height:1.5;color:#e6eef2;background:#05090c;border:1px solid #2a3a44;padding:8px;box-sizing:border-box';
var b=document.createElement('button');b.textContent='关闭';
b.style.cssText='height:44px;font-size:17px;color:#0d1419;background:#3fd2e6;border:0';
b.onclick=function(){o.remove()};o.appendChild(a);o.appendChild(b);document.body.appendChild(o);
setTimeout(function(){a.focus();a.select();a.setSelectionRange(0,t.length)},50)})(%s)""" % JSON.stringify(text)
		JavaScriptBridge.eval(js, true)
		return
	if box == null:
		box = TextEdit.new()
		box.editable = false
		box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		add_child(box)
	box.text = text
	box.add_theme_font_size_override("font_size", 17 if _tl() else 14)
	var r := _body_rect()
	box.position = r.position
	box.size = r.size
	box.visible = true
	box.grab_focus()
	box.select_all()


func _process(delta: float) -> void:
	if not visible:
		return
	if note_t > 0.0:
		note_t -= delta
		if note_t <= 0.0:
			note = ""
			queue_redraw()
	if _copy_wait >= 0.0:
		_copy_wait += delta
		var st = JavaScriptBridge.eval("window.__syCopy", true) if OS.has_feature("web") else 0
		if st != null and int(st) == 1:
			_copy_wait = -1.0
			_copied()
			queue_redraw()
		elif (st != null and int(st) == 0) or _copy_wait > 1.0:
			_copy_wait = -1.0
			_fallback()
			queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match Pad.kc(event):
			KEY_ESCAPE, KEY_BACKSPACE:
				close()
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				copy()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for k in btn_rects:
			if (btn_rects[k] as Rect2).grow(6.0).has_point(event.position):
				if k == "copy":
					copy()
				else:
					close()
				accept_event()
				return
		accept_event()


func _panel_rect() -> Rect2:
	var sr: Rect2 = Cfg.touch_safe_rect(size)
	var w: float = minf(sr.size.x - 24.0, 980.0)
	var h: float = minf(sr.size.y - 24.0, 620.0)
	return Rect2((sr.get_center() - Vector2(w, h) / 2.0).round(), Vector2(w, h))


func _body_rect() -> Rect2:
	var pr := _panel_rect()
	return Rect2(pr.position + Vector2(24, 86), Vector2(pr.size.x - 48, pr.size.y - 86 - 76))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.02, 0.03, 0.82))
	var pr := _panel_rect()
	draw_rect(pr, Color(0.035, 0.05, 0.065, 0.98))
	UI.frame(self, pr, UI.CYAN)
	var tl := _tl()
	UI.text(self, font, pr.position + Vector2(24, 40), "性能报告", 26 if tl else 22, UI.TEXT)
	UI.en(self, font, pr.position + Vector2(26, 58), "PERF REPORT", 10, UI.CYAN_DIM, 2.0)
	UI.text(self, font, pr.position + Vector2(pr.size.x - 24 - 420, 40), "只存在本机，最近 5 局，不上传", 15 if tl else 13, UI.SUB, HORIZONTAL_ALIGNMENT_RIGHT, 420)
	var br := _body_rect()
	var fs := 18 if tl else 15
	var lh := fs + 10.0
	var top := br.position.y   # 当前行顶边
	if recs.is_empty():
		var fe := UI.fit(font, "还没有记录。打完或退出一局（30 秒以上）后，这里会显示那一局的帧率与内存。", br.size.x, br.size.y, [fs])
		UI.draw_fit(self, font, Vector2(br.position.x, top), fe, UI.SUB)
	elif box == null or not box.visible:
		UI.text(self, font, Vector2(br.position.x, top + fs), "最近一局", fs, UI.CYAN)
		top += lh
		var lines := text.split("
")
		for i in range(1, lines.size()):
			var fd := UI.fit(font, lines[i], br.size.x, lh * 2.2, [fs, fs - 1, fs - 2])
			top += UI.draw_fit(self, font, Vector2(br.position.x, top), fd, UI.SUB if i == 2 else UI.TEXT) + 4.0
		if recs.size() > 1:
			top += 8.0
			UI.text(self, font, Vector2(br.position.x, top + fs), "更早的记录", fs, UI.CYAN)
			top += lh
			for k in range(1, recs.size()):
				if top + lh > br.end.y:
					break
				UI.text(self, font, Vector2(br.position.x, top + fs - 1), PerfReport.short_line(recs[k]), fs - 1, UI.SUB, HORIZONTAL_ALIGNMENT_LEFT, br.size.x)
				top += lh - 2.0
	# 按钮：复制报告 / 返回
	btn_rects.clear()
	var bh := 52.0 if tl else 40.0
	var by := pr.end.y - bh - 18.0
	var rc := Rect2(pr.position.x + 24, by, 220, bh)
	var rb := Rect2(pr.end.x - 24 - 160, by, 160, bh)
	if not recs.is_empty():
		btn_rects["copy"] = rc
		draw_rect(rc, UI.CYAN)
		UI.text(self, font, rc.position + Vector2(0, bh / 2.0 + 7.0), "复制报告" + ("" if tl else "  Enter"), 19 if tl else 16, Color(0.04, 0.07, 0.09), HORIZONTAL_ALIGNMENT_CENTER, rc.size.x)
	btn_rects["back"] = rb
	draw_rect(rb, Color(0.04, 0.09, 0.12, 0.9))
	draw_rect(rb, UI.CYAN_DIM, false, 1.0)
	UI.text(self, font, rb.position + Vector2(0, bh / 2.0 + 7.0), "返回" + ("" if tl else "  Esc"), 19 if tl else 16, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, rb.size.x)
	if note != "":
		UI.text(self, font, Vector2(rc.end.x + 18, by + bh / 2.0 + 6.0), note, 16 if tl else 13, UI.GOLD, HORIZONTAL_ALIGNMENT_LEFT, rb.position.x - rc.end.x - 36.0)
