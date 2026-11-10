extends Control
## 设置 → 画面 →「性能报告」（10-27 用户，core/perf_report.gd 采集）：盖在设置面板上，显示最近一局的性能摘要和更早几局各一行；
## 「复制报告」把最近一局的精简纯文本放进剪贴板。网页先走浏览器剪贴板 API（navigator.clipboard，异步，iOS 上不在点击手势里时常被拒），
## 1 秒内没成功就在网页上盖一个可全选的文本框（DOM textarea，长按全选复制）；桌面复制失败时显示引擎文本框（可全选）。
## 父节点是设置面板（标题页与局内暂停共用）；输入走触摸模拟的鼠标事件（_gui_input），Esc / 返回键关闭，Enter 复制

signal closed

const UI = preload("res://scripts/ui.gd")
const PerfReport = preload("res://scripts/core/perf_report.gd")
const CrashBox = preload("res://scripts/core/crash_box.gd")

var scroll := ScrollContainer.new()
var rows := VBoxContainer.new()
var font: Font
var recs: Array = []
var previous_crash: Dictionary = {}
var btn_rects := {}       # 动作 -> Rect2
var note := ""            # 复制结果提示
var note_t := 0.0
var _copy_wait := -1.0    # 网页：等浏览器剪贴板回话（秒，< 0 = 没在等）
var box: TextEdit = null  # 复制失败时的文本框（桌面）
var _taps: Array = []     # 连点标题 5 次（3 秒内）切换性能自检浮层（core/perf_hud.gd）


func _ready() -> void:
	font = load("res://fonts/ui.ttf")
	mouse_filter = Control.MOUSE_FILTER_STOP
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(rows)
	resized.connect(_layout_body)
	visible = false


func open() -> void:
	recs = PerfReport.load_all()
	previous_crash = CrashBox.check_prev()
	note = ""
	_copy_wait = -1.0
	position = Vector2.ZERO
	size = (get_parent() as Control).size if get_parent() is Control else Cfg.ui_size()
	if box != null:
		box.visible = false
	visible = true
	scroll.show()
	_layout_body()
	_fill_rows()
	scroll.scroll_vertical = 0
	Sfx.play("ui_ok")
	queue_redraw()


func close() -> void:
	visible = false
	if box != null:
		box.visible = false
		box.text = ""
	if OS.has_feature("web"):
		JavaScriptBridge.eval("var e=document.getElementById('sy-perf-copy');if(e)e.remove();", true)
	Sfx.play("ui_ok")
	closed.emit()


func _tl() -> bool:
	return Pad.touch_ui()


## 复制出去的全文：最近一局报告 + 上次异常退出前的曲线
func _full() -> String:
	var parts := PackedStringArray()
	if not recs.is_empty():
		parts.append(PerfReport.report_text(recs[0]))
	if not previous_crash.is_empty():
		parts.append(CrashBox.report_text(previous_crash))
	return "\n\n".join(parts)


func copy() -> void:
	var t := _full()
	if t == "":
		return
	if OS.has_feature("web"):
		JavaScriptBridge.eval("(function(t){window.__syCopy=-1;try{navigator.clipboard.writeText(t).then(function(){window.__syCopy=1},function(){window.__syCopy=0})}catch(e){window.__syCopy=0}})(%s)" % JSON.stringify(t), true)
		_copy_wait = 0.0
		note = "正在复制……"
	else:
		DisplayServer.clipboard_set(t)
		if DisplayServer.clipboard_get() == t:
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
setTimeout(function(){a.focus();a.select();a.setSelectionRange(0,t.length)},50)})(%s)""" % JSON.stringify(_full())
		JavaScriptBridge.eval(js, true)
		return
	if box == null:
		box = TextEdit.new()
		box.editable = false
		box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		add_child(box)
	box.text = _full()
	box.add_theme_font_size_override("font_size", 17 if _tl() else 14)
	var r := _body_rect()
	box.position = r.position
	box.size = r.size
	scroll.hide()
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
			KEY_PAGEDOWN, KEY_PAGEUP:
				scroll.scroll_vertical += roundi(scroll.size.y * (0.9 if Pad.kc(event) == KEY_PAGEDOWN else -0.9))
			_:
				return
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pr := _panel_rect()
		if Rect2(pr.position, Vector2(320, 72)).has_point(event.position):
			var now := Time.get_ticks_msec()
			_taps.append(now)
			while not _taps.is_empty() and now - int(_taps[0]) > 3000:
				_taps.remove_at(0)
			if _taps.size() >= 5:
				_taps.clear()
				var on: bool = load("res://scripts/core/perf_hud.gd").toggle(get_tree())
				note = "性能自检浮层已开启（左上角），再连点 5 次关闭" if on else "性能自检浮层已关闭"
				note_t = 5.0
				Sfx.play("ui_ok")
				queue_redraw()
			accept_event()
			return
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
	var footer := 82.0 if _tl() else 64.0
	return Rect2(pr.position + Vector2(24, 64), Vector2(pr.size.x - 48, maxf(1, pr.size.y - 64 - footer)))


func _layout_body() -> void:
	var r := _body_rect()
	scroll.position = r.position
	scroll.size = r.size
	if is_instance_valid(box):
		box.position = r.position
		box.size = r.size


func _label(parent: Control, value: String, pts: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", UI.fs(pts))
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _heading(value: String) -> void:
	var line := HSeparator.new()
	line.modulate = UI.CYAN_DIM
	rows.add_child(line)
	_label(rows, value, 21 if _tl() else 17, UI.CYAN)


func _fill_rows() -> void:
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	var pts := 20 if _tl() else 16
	rows.add_theme_constant_override("separation", 7 if _tl() else 5)
	if not previous_crash.is_empty():
		_label(rows, CrashBox.short_line(previous_crash).get_slice("· 点此查看", 0).strip_edges() + " · 详见复制报告", pts, UI.GOLD)
	if recs.is_empty():
		_label(rows, "暂无对局记录。完成一局，或在开局 30 秒后退出，即可查看帧率和内存。", pts, UI.SUB)
		return
	var r: Dictionary = recs[0]
	var duration := PerfReport._mmss(float(r.get("len", 0)))
	var result := str(PerfReport.RESULT_NAME.get(str(r.get("result", "")), r.get("result", "")))
	_label(rows, "最近一局  ·  %s  %s" % [duration, result], pts, UI.CYAN)
	var stats := HBoxContainer.new()
	rows.add_child(stats)
	var lowest := float(r.get("min1s", 0))
	var values := [
		["P95 帧时", "%.1f ms" % float(r.p95) if r.has("p95") else "—"],
		["最低一秒帧率", "%.0f FPS" % lowest if lowest > 0 else "—"],
		["内存峰值", "%d MB" % int(r.mem_peak) if r.has("mem_peak") else "—"],
	]
	for stat in values:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stats.add_child(col)
		_label(col, stat[0], 17 if _tl() else 14, UI.SUB)
		_label(col, stat[1], 28 if _tl() else 23, UI.TEXT)
	_heading("帧时")
	_label(rows, "全局  ·  " + PerfReport.frame_line(r), pts, UI.TEXT)
	var late: Dictionary = r.get("late", {})
	if not late.is_empty():
		_label(rows, "7 分钟后  ·  " + PerfReport.frame_line(late), pts, UI.TEXT)
	elif float(r.get("len", 0)) < 420.0:
		_label(rows, "本局未到 7 分钟", pts, UI.SUB)
	if r.has("slow_n"):
		_label(rows, "掉帧档  ·  进档 %d 次，共 %d 秒" % [int(r.slow_n), int(r.get("slow_s", 0))], pts, UI.TEXT)
	_heading("内存")
	if r.has("mem_peak"):
		_label(rows, "%s  ·  %d MB" % [str(r.get("mem_src", "内存峰值")), int(r.mem_peak)], pts, UI.TEXT)
	var mix: Dictionary = r.get("mem_mix", {})
	if not mix.is_empty():
		_label(rows, PerfReport._mix_text(mix, " MB"), pts, UI.TEXT)
	var peak: Dictionary = r.get("web_at_peak", {})
	if peak.has("wasm_mib"):
		_label(rows, "同次采样 %s  ·  WASM 堆容量 %.1f MiB" % [PerfReport._mmss(float(peak.get("t", 0))), float(peak.wasm_mib)], pts, UI.TEXT)
	var guard := ["未触发", "只清缓存", "降画质", "分辨率缩放"][clampi(int(r.get("guard_stage", 0)), 0, 3)] as String
	if not r.has("guard_stage"):
		guard = "已触发" if r.get("guard", false) else "未触发"
	_label(rows, "内存护栏  ·  " + guard, pts, UI.SUB)
	if r.has("enemy_peak"):
		_heading("同屏敌人")
		_label(rows, "峰值 %d  ·  %s" % [int(r.enemy_peak), PerfReport._mix_text(r.get("enemy_mix", {}), "")], pts, UI.TEXT)
	var slow: Array = r.get("slow", [])
	if not slow.is_empty():
		_heading("最慢 %d 秒" % slow.size())
		for span in slow:
			_label(rows, PerfReport.slow_line(span), pts, UI.TEXT)
	_heading("运行环境")
	_label(rows, PerfReport.quality_line(r), pts, UI.TEXT)
	if r.has("q0"):
		_label(rows, "开局画质  ·  " + str(Cfg.QUALITY_NAME.get(str(r.q0), r.q0)), pts, UI.SUB)
	_label(rows, PerfReport.device_line(r.get("device", {})), pts, UI.SUB)
	_label(rows, "版本 %s（%s）  ·  %s" % [r.get("version", "—"), r.get("commit", "—"), str(r.get("time", "—")).replace("T", " ")], pts, UI.SUB)
	if recs.size() > 1:
		_heading("更早的记录")
		for r_old in recs.slice(1):
			_label(rows, PerfReport.short_line(r_old), pts, UI.SUB)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.02, 0.03, 0.82))
	var pr := _panel_rect()
	draw_rect(pr, Color(0.035, 0.05, 0.065, 0.98))
	UI.frame(self, pr, UI.CYAN)
	var tl := _tl()
	UI.text(self, font, pr.position + Vector2(24, 40), "性能报告", 26 if tl else 22, UI.TEXT)
	UI.text(self, font, pr.position + Vector2(140, 40), "本机最近 5 局", 17 if tl else 14, UI.SUB, HORIZONTAL_ALIGNMENT_RIGHT, pr.size.x - 164)
	# 按钮：复制报告 / 返回
	btn_rects.clear()
	var bh := 52.0 if tl else 40.0
	var by := pr.end.y - bh - 18.0
	var rc := Rect2(pr.position.x + 24, by, minf(180, pr.size.x * 0.34), bh)
	var bw := minf(130, pr.size.x * 0.24)
	var rb := Rect2(pr.end.x - 24 - bw, by, bw, bh)
	if not recs.is_empty() or not previous_crash.is_empty():
		btn_rects["copy"] = rc
		draw_rect(rc, UI.CYAN)
		UI.text(self, font, rc.position + Vector2(0, bh / 2.0 + 7.0), "复制报告" + ("" if tl else "  Enter"), 19 if tl else 16, Color(0.04, 0.07, 0.09), HORIZONTAL_ALIGNMENT_CENTER, rc.size.x)
	btn_rects["back"] = rb
	draw_rect(rb, Color(0.04, 0.09, 0.12, 0.9))
	draw_rect(rb, UI.CYAN_DIM, false, 1.0)
	UI.text(self, font, rb.position + Vector2(0, bh / 2.0 + 7.0), "返回" + ("" if tl else "  Esc"), 19 if tl else 16, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, rb.size.x)
	if note != "":
		var message := UI.fit(font, note, rb.position.x - rc.end.x - 24, bh, [16, 14, 13] if tl else [14, 13])
		UI.draw_fit(self, font, Vector2(rc.end.x + 12, by), message, UI.GOLD)
