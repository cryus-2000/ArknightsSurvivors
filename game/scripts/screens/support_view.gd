extends Control
## B站 Toy「支持作者」浮层（docs/313，core/toy_support.gd）：标题页 / 结算页 / 寻访页的「支持作者」入口打开（只在 Toy 版）。
## 11-08 用户：关注作者、三连视频两张卡并排，各自一枚「领取」按钮，点了查 SDK（tools/web/support.js → window.__sySupport.check），满足就记账发奖；
## 三连没配视频（TS.triple_open() 为假）时照样画出来、置灰、按钮写「PV 发布后开放」。
## 键盘：Esc 关闭、Enter 把能领的都查一遍。版式跟意见反馈浮层（feedback_view）一致。
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
var _cur := ""               # 正在查询的项（卡片按钮写「正在查询……」）
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


## 还有能去领的项（没领过且已开放）
func any_claimable() -> bool:
	for id in TS.items():
		if TS.claimable(id):
			return true
	return false


## 领取：id 为空 = 能领的项依次查询（Enter），否则只查这一项（卡片上的「领取」）
func check(id := "") -> void:
	if busy or not any_claimable():
		return
	if id != "" and not TS.claimable(id):
		return
	busy = true
	note = "正在查询……"
	note_ok = false
	_queue = [id] if id != "" else TS.items().filter(func(x): return TS.claimable(x))
	_next()
	queue_redraw()


func _next() -> void:
	if _queue.is_empty():
		busy = false
		_cur = ""
		if note == "正在查询……":
			note = ""
		queue_redraw()
		return
	var id: String = _queue.pop_front()
	_cur = id
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
		if h.begins_with("go_"):
			check(h.substr(3))
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
	var h: float = minf(sr.size.y - 32.0, 470.0 if ph else 420.0)
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
	# 奖励项：两张卡并排，各自领取（11-08 用户）
	var ids: Array = TS.items()
	var gap := 16.0
	var cw: float = (iw - gap * (ids.size() - 1)) / maxf(1.0, ids.size())
	var cy := y + (112.0 if ph else 104.0)
	var bh: float = 52.0 if ph else 42.0
	var ch: float = (pr.end.y - bh - 22.0 - 18.0) - cy
	var kb: bool = not (tl or Pad.using)
	btns = {}
	for i in ids.size():
		var id: String = ids[i]
		var r := Rect2(x + i * (cw + gap), cy, cw, ch)
		var got: bool = TS.claimed(id)
		var open_: bool = id != "triple" or TS.triple_open()
		var line: Color = UI.GOLD if got else (UI.CYAN_DIM if open_ else Color(UI.SUB, 0.35))
		draw_rect(r, Color(0.02, 0.03, 0.04, 1.0))
		draw_rect(r, Color(line, 0.6), false, 1.0)
		draw_rect(Rect2(r.position, Vector2(3, r.size.y)), line)
		var tx := r.position.x + 18.0
		var tw := r.size.x - 32.0
		var dim: float = 1.0 if open_ or got else 0.45
		UI.text(self, font, Vector2(tx, r.position.y + (34 if ph else 30)), "关注作者" if id == "follow" else "三连视频", 21 if tl else 19, Color(UI.TEXT, dim), HORIZONTAL_ALIGNMENT_LEFT, tw)
		UI.text(self, font, Vector2(tx, r.position.y + (58 if ph else 52)), "在 B站关注作者" if id == "follow" else "点赞 + 投币 + 收藏 PV", 14 if tl else 13, Color(UI.SUB, dim), HORIZONTAL_ALIGNMENT_LEFT, tw)
		UI.text(self, font, Vector2(tx, r.position.y + (92 if ph else 84)), "寻访凭证 ×%d" % TS.REWARD, 20 if tl else 18, Color(UI.CYAN, dim), HORIZONTAL_ALIGNMENT_LEFT, tw)
		# 11-08 用户：两项各送一种边框（关注 = 罗德岛，三连 = 深海）
		UI.text(self, font, Vector2(tx, r.position.y + (116 if ph else 106)), "专属分享卡边框「%s」" % TS.frame_name(id), 14 if tl else 13, Color(UI.CYAN, dim * 0.8), HORIZONTAL_ALIGNMENT_LEFT, tw)
		var m: String = str(row_msg.get(id, ""))
		var gb := Rect2(tx, r.end.y - bh - 14.0, tw, bh)
		if m != "" and not got:
			UI.text(self, font, Vector2(tx, gb.position.y - 10.0), m, 14 if tl else 13, UI.GOLD, HORIZONTAL_ALIGNMENT_LEFT, tw)
		btns["go_" + id] = gb
		var lab: String = "已领取" if got else ("PV 发布后开放" if not open_ else ("正在查询……" if busy and _cur == id else "领取"))
		_btn("go_" + id, lab, "", TS.claimable(id) and not busy, not TS.claimable(id))
	# 总的一句（领取成功 / 环境提示）
	var by: float = pr.end.y - bh - 22.0
	if note != "" and note != "正在查询……":
		UI.text(self, font, Vector2(x, by + bh * 0.5 + 6.0), note, 17 if tl else 15, UI.CYAN if note_ok else UI.GOLD, HORIZONTAL_ALIGNMENT_LEFT, iw - 170.0)
	# 关闭
	var ow: float = 150.0 if ph else 130.0
	btns["close"] = Rect2(pr.end.x - 28.0 - ow, by, ow, bh)
	_btn("close", "关闭", "ESC" if kb else "", false)


func _btn(id: String, label: String, k: String, primary: bool, off := false) -> void:
	var r: Rect2 = btns[id]
	var hov := hover == id and not off
	var ink := Color("131820")
	if off:   # 已领取 / 未开放：灰掉、不响应悬停
		draw_rect(r, Color(0.04, 0.05, 0.06, 0.85))
		draw_rect(r, Color(UI.SUB, 0.3), false, 1.0)
		var f0 := 18 if Cfg.phone_ui() else 16
		UI.text(self, font, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + f0 * 0.36), label, f0, Color(UI.SUB, 0.75), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		return
	if primary:
		draw_rect(r, UI.CYAN.lightened(0.15) if hov else UI.CYAN)
	else:
		draw_rect(r, Color(0.05, 0.2, 0.24, 0.9) if hov else Color(0.04, 0.09, 0.12, 0.85))
		draw_rect(r, UI.CYAN if hov else UI.CYAN_DIM, false, 1.0)
	var fs := 20 if Cfg.phone_ui() else 17
	UI.text(self, font, Vector2(r.position.x + UI.key_shift(k, 14.0), r.position.y + r.size.y * 0.5 + fs * 0.36), label, fs, ink if primary else UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	UI.btn_key(self, font, r, k, ink if primary else UI.SUB, 10, 8.0)
