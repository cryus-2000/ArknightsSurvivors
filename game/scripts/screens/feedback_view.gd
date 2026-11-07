extends Control
## 反馈浮层（docs/311，core/feedback.gd）：结算底栏「反馈」与标题页设置「反馈」共用。
## 打开时（玩家点按里）就把反馈码复制进剪贴板，浮层上写出反馈码、一句说明和「打开问卷」/「前往视频评论区」（Toy）主按钮；
## 主按钮在点按处理里直接跳转（浏览器 / Toy 都要用户手势）。网页剪贴板 1 秒内没成功：DOM 里盖一个只读输入框，长按 / 全选复制。
## own_input：设置面板里自己收键盘（同 perf_view）；结算里由 game.gd 让开输入（见 game.gd 的 feedback_view 判断）

signal closed

const UI = preload("res://scripts/ui.gd")
const FB = preload("res://scripts/core/feedback.gd")

var font: Font
var fb_code := ""
var run := false             # 带本局摘要（结算）/ 只有版本（标题页）
var note := ""
var note_ok := false
var btns := {}               # 动作 -> Rect2
var hover := ""
var _copy_wait := -1.0
var _t := 0.0


func _ready() -> void:
	font = load("res://fonts/ui.ttf")
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


## summary 为空 = 标题页（只带版本）
func open(summary := {}) -> void:
	run = not summary.is_empty()
	fb_code = FB.code(summary)
	position = Vector2.ZERO
	size = (get_parent() as Control).size if get_parent() is Control and (get_parent() as Control).size.x > 0.0 else Cfg.ui_size()
	visible = true
	_t = 0.0
	hover = ""
	_copy()
	Sfx.play("ui_ok")
	queue_redraw()


func close() -> void:
	if not visible:
		return
	visible = false
	_dom_close()
	Sfx.play("ui_ok")
	closed.emit()


func _copy() -> void:
	note = "正在复制……"
	note_ok = false
	if FB.copy(fb_code):
		_copied()
	elif OS.has_feature("web"):
		_copy_wait = 0.0
	else:
		note = "没能自动复制，请手动抄下反馈码"


func _copied() -> void:
	note = "反馈码已复制到剪贴板"
	note_ok = true
	queue_redraw()


func _dom_close() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("var e=document.getElementById('sy-fb-copy');if(e)e.remove();", true)


## 网页剪贴板不可用：盖一个只读输入框（DOM），长按 / 全选复制
func _dom_fallback() -> void:
	note = "没能自动复制：已打开文本框，长按或全选后复制" if Pad.touch_ui() else "没能自动复制：已打开文本框，全选（Ctrl+A）后复制"
	note_ok = false
	if not OS.has_feature("web"):
		return
	var js := """(function(t){var o=document.getElementById('sy-fb-copy');if(o)o.remove();
o=document.createElement('div');o.id='sy-fb-copy';
o.style.cssText='position:fixed;left:50%;top:12%;transform:translateX(-50%);width:min(90%,520px);z-index:99999;background:#0d1419;border:1px solid #3fd2e6;padding:12px;box-sizing:border-box;display:flex;gap:8px';
var a=document.createElement('input');a.value=t;a.readOnly=true;
a.style.cssText='flex:1;min-width:0;font-size:18px;letter-spacing:1px;color:#e6eef2;background:#05090c;border:1px solid #2a3a44;padding:8px';
var b=document.createElement('button');b.textContent='关闭';
b.style.cssText='font-size:17px;padding:0 16px;color:#0d1419;background:#3fd2e6;border:0';
b.onclick=function(){o.remove()};o.appendChild(a);o.appendChild(b);document.body.appendChild(o);
setTimeout(function(){a.focus();a.select();a.setSelectionRange(0,t.length)},50)})(%s)""" % JSON.stringify(fb_code)
	JavaScriptBridge.eval(js, true)


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if _copy_wait >= 0.0:
		_copy_wait += delta
		var st = JavaScriptBridge.eval("window.__syFbCopy", true) if OS.has_feature("web") else 0
		if st != null and int(st) == 1:
			_copy_wait = -1.0
			_copied()
		elif (st != null and int(st) == 0) or _copy_wait > 1.0:
			_copy_wait = -1.0
			_dom_fallback()
			queue_redraw()


## 键盘（设置面板里由 _input 调，结算里由 game.gd 转来）：Esc 关、Enter 去反馈、C 再复制一次
func key(kc: int) -> bool:
	match kc:
		KEY_ESCAPE, KEY_BACKSPACE:
			close()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_go()
		KEY_C:
			_copy()
			queue_redraw()
		_:
			return false
	return true


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		key(Pad.kc(event))
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := _hit(event.position)
		if h != hover:
			hover = h
			queue_redraw()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var h := _hit(event.position)
		if h == "go":
			_go()
		elif h == "copy":
			_copy()
			queue_redraw()
		elif h == "close" or not _panel().has_point(event.position):
			close()
		accept_event()


func _hit(p: Vector2) -> String:
	for k in btns:
		if (btns[k] as Rect2).grow(4.0).has_point(p):
			return str(k)
	return ""


func _go() -> void:
	if FB.go():
		Sfx.play("ui_ok")
		note = "已在新页面打开问卷，填写时把反馈码粘贴进去" if not FB.is_toy() else "正在前往视频，留言时可以附上反馈码"
		note_ok = true
	else:
		note = "暂时无法打开，请稍后再试"
		note_ok = false
	queue_redraw()


func _panel() -> Rect2:
	var sr: Rect2 = Cfg.touch_safe_rect(size)
	var ph: bool = Cfg.phone_ui()
	var w: float = minf(sr.size.x - 32.0, 720.0 if ph else 620.0)
	var h: float = minf(sr.size.y - 32.0, 400.0 if ph else 340.0)
	return Rect2((sr.get_center() - Vector2(w, h) / 2.0).round(), Vector2(w, h))


func _draw() -> void:
	var tl: bool = Pad.touch_ui()
	var ph: bool = Cfg.phone_ui()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.02, 0.03, 0.78))
	var pr := _panel()
	draw_rect(pr, Color(0.035, 0.05, 0.065, 0.98))
	UI.frame(self, pr, UI.CYAN)
	var x := pr.position.x + 28.0
	var iw := pr.size.x - 56.0
	var y := pr.position.y
	UI.text(self, font, Vector2(x, y + 44), "反馈", 26 if tl else 24, UI.TEXT)
	UI.en(self, font, Vector2(x + (62 if tl else 58), y + 42), "FEEDBACK", 10, UI.CYAN_DIM, 2.0)
	# 反馈码
	var cy := y + (78.0 if ph else 72.0)
	UI.text(self, font, Vector2(x, cy + 14), "反馈码" + ("（版本与本局摘要）" if run else "（版本）"), 15 if tl else 13, UI.SUB)
	var cr := Rect2(x, cy + 24, iw, 58.0 if ph else 50.0)
	draw_rect(cr, Color(0.02, 0.03, 0.04, 1.0))
	draw_rect(cr, Color(UI.CYAN, 0.45), false, 1.0)
	var cs := 26 if ph else 22
	UI.text(self, font, Vector2(cr.position.x, cr.position.y + cr.size.y * 0.5 + cs * 0.36), fb_code, cs, UI.CYAN, HORIZONTAL_ALIGNMENT_CENTER, cr.size.x)
	# 复制结果 + 说明
	var ny := cr.end.y + (28.0 if ph else 24.0)
	UI.text(self, font, Vector2(x, ny), note, 16 if tl else 14, UI.CYAN if note_ok else UI.GOLD)
	var toy: bool = FB.is_toy()
	var info := "反馈码只含版本号%s，不含任何个人信息。" % ("与本局的干员、难度、结果和用时" if run else "")
	info += "留言时可以附上它，方便定位问题。" if toy else "填写问卷时把它粘贴进去，方便定位问题。"
	var fs := 16 if tl else 14
	var fi := UI.fit(font, info, iw, 60.0, [fs, fs - 1, fs - 2])
	UI.draw_fit(self, font, Vector2(x, ny + 14), fi, UI.SUB)
	# 按钮
	var bh: float = 52.0 if ph else 42.0
	var by: float = pr.end.y - bh - 22.0
	var ck := "" if (tl or Pad.using) else "ESC"
	var gk := "" if (tl or Pad.using) else "ENTER"
	var gw: float = 240.0 if ph else 210.0
	var ow: float = 150.0 if ph else 130.0
	btns = {"go": Rect2(pr.end.x - 28.0 - gw, by, gw, bh), "close": Rect2(pr.end.x - 28.0 - gw - 14.0 - ow, by, ow, bh),
		"copy": Rect2(x, by, ow, bh)}
	_btn("go", "前往视频评论区" if toy else "打开问卷", gk, true)
	_btn("close", "关闭", ck, false)
	_btn("copy", "再复制一次", "" if (tl or Pad.using) else "C", false)


func _btn(id: String, label: String, k: String, primary: bool) -> void:
	var r: Rect2 = btns[id]
	var hov := hover == id
	var ink := Color("131820")
	if primary:
		draw_rect(r, UI.CYAN.lightened(0.15) if hov else UI.CYAN)
	else:
		draw_rect(r, Color(0.05, 0.2, 0.24, 0.9) if hov else Color(0.04, 0.09, 0.12, 0.85))
		draw_rect(r, UI.CYAN if hov else UI.CYAN_DIM, false, 1.0)
	var fs := 20 if Cfg.phone_ui() else 17
	UI.text(self, font, Vector2(r.position.x + UI.key_shift(k, 14.0), r.position.y + r.size.y * 0.5 + fs * 0.36), label, fs, ink if primary else UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	UI.btn_key(self, font, r, k, ink if primary else UI.SUB, 10, 8.0)
