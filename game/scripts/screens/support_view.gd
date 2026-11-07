extends Control
## B站 Toy「支持作者」浮层（docs/313，core/toy_support.gd）：标题页底部一行「支持作者」打开（只在 Toy 版）。
## 列出奖励项（关注作者 / 三连视频）与领取状态，「检查并领取」逐项查 SDK（tools/web/support.js → window.__sySupport.check），满足就记账发奖。
## 键盘：Esc 关闭、Enter 检查并领取。版式跟意见反馈浮层（feedback_view）一致。
## 桌面 / 测试（非网页）：--toysim=follow:yes,triple:no:coin 模拟 SDK 返回（结果：yes / no / unsupported / login / err，triple 的 no 可带缺项）

signal closed

const UI = preload("res://scripts/ui.gd")
const TS = preload("res://scripts/core/toy_support.gd")

var font: Font
var btns := {}               # 动作 -> Rect2
var hover := ""
var busy := false
var note := ""
var note_ok := false
var row_msg := {}            # 奖励项 -> 最近一次查询的一句
var _queue: Array = []
var _js = null
var _cbs: Array = []         # JavaScriptBridge 回调要一直持有，不然被回收
var _sim_t := -1.0           # 模拟 SDK 的延迟计时
var _sim_id := ""
var granted := 0             # 本次打开期间发的凭证（测试读）


func _ready() -> void:
	font = load("res://fonts/ui.ttf")
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func open() -> void:
	position = Vector2.ZERO
	size = (get_parent() as Control).size if get_parent() is Control and (get_parent() as Control).size.x > 0.0 else Cfg.ui_size()
	visible = true
	hover = ""
	busy = false
	note = ""
	row_msg = {}
	granted = 0
	Sfx.play("ui_ok")
	queue_redraw()


func close() -> void:
	if not visible:
		return
	visible = false
	Sfx.play("ui_ok")
	closed.emit()


func all_claimed() -> bool:
	for id in TS.items():
		if not TS.claimed(id):
			return false
	return true


## 「检查并领取」：没领的项依次查询
func check() -> void:
	if busy or all_claimed():
		return
	busy = true
	note = "正在查询……"
	note_ok = false
	_queue = TS.items().filter(func(id): return not TS.claimed(id))
	_next()
	queue_redraw()


func _next() -> void:
	if _queue.is_empty():
		busy = false
		if note == "正在查询……":
			note = ""
		queue_redraw()
		return
	var id: String = _queue.pop_front()
	if OS.has_feature("web"):
		if _js == null:
			_js = JavaScriptBridge.get_interface("__sySupport")
		if _js == null:
			result(id, "unsupported", "")
			return
		var cb := JavaScriptBridge.create_callback(func(args: Array): result(id, str(args[0]) if args.size() > 0 else "err", str(args[1]) if args.size() > 1 else ""))
		_cbs.append(cb)
		_js.check(id, TS.bvid(), cb)
	else:
		_sim_id = id
		_sim_t = 0.0


## 一项的查询结果（support.js 回调 / 模拟 / 测试直接调）
func result(id: String, status: String, detail := "") -> void:
	var r: Dictionary = TS.apply(id, status, detail)
	granted += int(r.granted)
	row_msg[id] = str(r.msg)
	if int(r.granted) > 0:
		note = str(r.msg)
		note_ok = true
		Sfx.play("ui_ok")
	elif status in ["unsupported", "login", "err"]:
		note = str(r.msg)   # 环境问题：两项都一样，只写一次，不再查下一项
		note_ok = false
		_queue.clear()
	elif not note_ok:
		note = ""
	_next()


func _sim(id: String) -> Array:
	for a in Cfg.dev_args():
		if a.begins_with("--toysim="):
			for tok in a.substr(9).split(","):
				var ps: PackedStringArray = tok.split(":")
				if ps.size() >= 2 and ps[0] == id:
					return [ps[1], ":".join(ps.slice(2)).replace(":", ",")]
	return ["unsupported", ""]


func _process(delta: float) -> void:
	if not visible:
		return
	if _sim_t >= 0.0:
		_sim_t += delta
		if _sim_t > 0.35:
			_sim_t = -1.0
			var s: Array = _sim(_sim_id)
			result(_sim_id, s[0], s[1])
	queue_redraw()


func key(kc: int) -> bool:
	match kc:
		KEY_ESCAPE, KEY_BACKSPACE:
			close()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			check()
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
			check()
		elif h == "close" or not _panel().has_point(event.position):
			close()
		accept_event()


func _hit(p: Vector2) -> String:
	for k in btns:
		if (btns[k] as Rect2).grow(4.0).has_point(p):
			return str(k)
	return ""


func _panel() -> Rect2:
	var sr: Rect2 = Cfg.touch_safe_rect(size)
	var ph: bool = Cfg.phone_ui()
	var w: float = minf(sr.size.x - 32.0, 740.0 if ph else 640.0)
	var h: float = minf(sr.size.y - 32.0, 450.0 if ph else 400.0)
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
	UI.text(self, font, Vector2(x, y + 44), "支持作者", 26 if tl else 24, UI.TEXT)
	UI.en(self, font, Vector2(x + (114 if tl else 106), y + 42), "SUPPORT", 10, UI.CYAN_DIM, 2.0)
	var intro := "在 B站 App 里关注作者、三连视频，可以领取下面的奖励。每项只能领取一次，不影响正常游玩。"
	var fs := 15 if tl else 13
	var fi := UI.fit(font, intro, iw, 44.0, [fs, fs - 1, fs - 2])
	UI.draw_fit(self, font, Vector2(x, y + 58), fi, UI.SUB)
	# 奖励项
	var ry := y + (112.0 if ph else 104.0)
	var rh: float = 78.0 if ph else 70.0
	for id in TS.items():
		var r := Rect2(x, ry, iw, rh)
		var got: bool = TS.claimed(id)
		draw_rect(r, Color(0.02, 0.03, 0.04, 1.0))
		draw_rect(r, Color(UI.GOLD, 0.6) if got else Color(UI.CYAN, 0.35), false, 1.0)
		draw_rect(Rect2(r.position, Vector2(3, r.size.y)), UI.GOLD if got else UI.CYAN_DIM)
		var nm: String = "关注作者" if id == "follow" else "三连视频（点赞 + 投币 + 收藏）"
		var rew: String = "寻访凭证 ×%d" % TS.REWARD + ("  ·  专属结算分享卡边框" if id == "triple" else "")
		UI.text(self, font, Vector2(r.position.x + 18, r.position.y + (30 if ph else 27)), nm, 19 if tl else 17, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, iw - 170)
		UI.text(self, font, Vector2(r.position.x + 18, r.position.y + (56 if ph else 51)), rew, 15 if tl else 13, UI.CYAN, HORIZONTAL_ALIGNMENT_LEFT, iw - 170)
		var st: String = "已领取" if got else "未领取"
		var chip := Rect2(r.end.x - 110, r.position.y + 12, 96, 26)
		draw_rect(chip, Color(UI.GOLD, 0.16) if got else Color(0.05, 0.08, 0.1, 1.0))
		draw_rect(chip, UI.GOLD if got else UI.CYAN_DIM, false, 1.0)
		UI.text(self, font, Vector2(chip.position.x, chip.position.y + 18), st, 14 if tl else 13, UI.GOLD if got else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, chip.size.x)
		var m: String = str(row_msg.get(id, ""))
		if m != "" and not got:
			UI.text(self, font, Vector2(r.end.x - 250, r.position.y + (60 if ph else 55)), m, 13 if tl else 12, UI.GOLD, HORIZONTAL_ALIGNMENT_RIGHT, 236)
		ry += rh + 12.0
	# 总的一句（领取成功 / 环境提示）
	if note != "":
		UI.text(self, font, Vector2(x, ry + 18.0), note, 17 if tl else 15, UI.CYAN if note_ok else UI.GOLD)
	# 按钮
	var bh: float = 52.0 if ph else 42.0
	var by: float = pr.end.y - bh - 22.0
	var gw: float = 220.0 if ph else 190.0
	var ow: float = 150.0 if ph else 130.0
	var done: bool = all_claimed()
	btns = {"go": Rect2(pr.end.x - 28.0 - gw, by, gw, bh), "close": Rect2(pr.end.x - 28.0 - gw - 14.0 - ow, by, ow, bh)}
	var kb: bool = not (tl or Pad.using)
	_btn("go", "已全部领取" if done else ("正在查询……" if busy else "检查并领取"), "ENTER" if kb and not done else "", not done and not busy)
	_btn("close", "关闭", "ESC" if kb else "", false)


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
