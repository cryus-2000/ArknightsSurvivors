extends Control
## B站 Toy「支持作者」浮层（docs/313，core/toy_support.gd）：标题页 / 结算页 / 寻访页的「支持作者」入口打开（只在 Toy 版）。
## 11-08 用户：关注作者、三连视频两张卡并排，各自一枚「领取」按钮，点了查 SDK（tools/web/support.js → window.__sySupport.check），满足就记账发奖；
## 三连没配视频（TS.triple_open() 为假）时照样画出来、置灰、按钮写「PV 发布后开放」。
## 键盘：Esc 关闭、Enter 把能领的都查一遍。版式跟意见反馈浮层（feedback_view）一致。
## 桌面 / 测试（非网页）：--toysim=follow:yes,triple:no:coin 模拟 SDK 返回（结果：yes / no / unsupported / login / err，triple 的 no 可带缺项）

signal closed

const UI = preload("res://scripts/ui.gd")
const TS = preload("res://scripts/core/toy_support.gd")
const ShareCard = preload("res://scripts/screens/share_card.gd")
const RunStatsScreen = preload("res://scripts/screens/run_stats_screen.gd")


## 分享卡预览用的最小宿主（ShareCard 只用 g.font 与 g.run_stats.fmt_n）
class PreviewHost:
	var font: Font
	var run_stats = RunStatsScreen

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
var _sc: RefCounted = null   # 边框预览用的分享卡画法（复用 share_card.gd 的相框，不另画）
var _pv := {}                # 相框 id -> 样张数据
var granted := 0             # 本次打开期间发的凭证（测试读）
var _zoom := ""              # 放大查看的相框预览（奖励项 id；11-14 用户：分享卡样张要能点开放大）


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
	_zoom = ""
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
	if _zoom != "":   # 放大图开着：任意确认 / 返回键先收起
		if kc in [KEY_ESCAPE, KEY_BACKSPACE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			_zoom = ""
			Sfx.play("ui_ok")
			return true
		return false
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
		if _zoom != "":   # 放大图：点哪儿都收起
			_zoom = ""
			Sfx.play("ui_ok")
			accept_event()
			return
		var h := _hit(event.position)
		if h.begins_with("pv_"):
			_zoom = h.substr(3)
			hover = ""
			Sfx.play("ui_ok")
		elif h.begins_with("go_"):
			check(h.substr(3))
		elif h == "close" or not _panel().has_point(event.position):
			close()
		accept_event()


## 样张数据：队长 + 空藏品的一局胜利，只为让相框里有东西
func _preview_data(fr: String) -> Dictionary:
	if not _pv.has(fr):
		_pv[fr] = {"won": true, "result": "探索完成", "result_en": "OPERATION COMPLETE", "ending": "", "tier": "", "t": 1500.0, "hi_label": "总伤害", "hi": "0",
			"kills": 0, "level": 1, "relic_n": 0, "grade": "S", "relics": [], "frame": fr, "date": "", "name": "博士", "avatar": null, "qr": null,
			"ops": [{"key": "exusiai", "name": "", "en": "", "elite": 0, "leader": true, "col": UI.CYAN, "art": {}}, {"key": "angelina", "name": "", "en": "", "elite": 0, "leader": false, "col": UI.CYAN, "art": {}}]}
	return _pv[fr]


## 在 box 里画一张缩小的带相框分享卡（box 内居中、等比），dim < 1 时压暗
func _frame_preview(fr: String, box: Rect2, dim: float) -> Rect2:
	if _sc == null:
		var h := PreviewHost.new()
		h.font = font
		_sc = ShareCard.new(h)
	var os: Vector2 = ShareCard.outer_size(fr)
	var k: float = minf(box.size.x / os.x, box.size.y / os.y)
	var pos: Vector2 = (box.position + (box.size - os * k) * 0.5).round()
	_sc.draw(self, _preview_data(fr), pos, k, 0.0, false)
	if dim < 1.0:
		draw_rect(Rect2(pos, os * k), Color(0.02, 0.03, 0.04, 1.0 - dim))
	return Rect2(pos, os * k)


## 预览右下角的放大镜角标（提示可点开）
func _zoom_badge(r: Rect2, hov: bool) -> void:
	var s: float = 22.0 if Pad.touch_ui() else 18.0
	var b := Rect2(r.end - Vector2(s, s) - Vector2(4, 4), Vector2(s, s))
	draw_rect(b, Color(0.02, 0.03, 0.04, 0.85))
	draw_rect(b, UI.CYAN if hov else UI.CYAN_DIM, false, 1.0)
	var c: Vector2 = b.position + Vector2(s * 0.44, s * 0.44)
	var rad: float = s * 0.22
	var col: Color = UI.CYAN if hov else UI.TEXT
	draw_arc(c, rad, 0.0, TAU, 20, col, 1.5, true)
	draw_line(c + Vector2(rad, rad) * 0.72, b.end - Vector2(s, s) * 0.2, col, 2.0, true)


## 放大查看一张相框样张：盖住浮层，点任意处 / Esc 收起
func _draw_zoom() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.02, 0.03, 0.9))
	var sr: Rect2 = Cfg.touch_safe_rect(size)
	var tl: bool = Pad.touch_ui()
	var cap_h: float = 56.0
	var box := Rect2(sr.position + Vector2(16, 16), sr.size - Vector2(32, 32 + cap_h))
	var r := _frame_preview(str(TS.FRAME_OF[_zoom]), box, 1.0)
	var fl := UI.Loc.s("专属分享卡边框「%s」" % TS.frame_name(_zoom))
	var fs := 20 if tl else 18
	UI.text(self, font, Vector2(sr.position.x, r.end.y + 30.0), fl, fs, UI.CYAN, HORIZONTAL_ALIGNMENT_CENTER, sr.size.x)
	UI.text(self, font, Vector2(sr.position.x, r.end.y + 52.0), "点击任意处返回", 14 if tl else 13, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, sr.size.x)


func _hit(p: Vector2) -> String:
	for k in btns:
		if (btns[k] as Rect2).grow(4.0).has_point(p):
			return str(k)
	return ""


func _panel() -> Rect2:
	var sr: Rect2 = Cfg.touch_safe_rect(size)
	var ph: bool = Cfg.phone_ui()
	var w: float = minf(sr.size.x - 32.0, 740.0 if ph else 640.0)
	var h: float = minf(sr.size.y - 32.0, 600.0 if ph else 470.0)
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
		var gb := Rect2(tx, r.end.y - bh - 14.0, tw, bh)
		# 右侧：专属边框的缩小预览（11-08 用户：两项各送一种边框；关注 = 罗德岛，三连 = 深海）
		var pvh: float = gb.position.y - 22.0 - (r.position.y + 12.0)
		var pvw: float = minf(pvh * 0.69, tw * (0.30 if UI.Loc.en() else 0.42))   # 英文文字长，预览收窄给文字让位
		var pv := Rect2(r.end.x - 14.0 - pvw, r.position.y + 12.0, pvw, pvh)
		var pvr := _frame_preview(str(TS.FRAME_OF[id]), pv, dim)
		btns["pv_" + id] = pvr
		if hover == "pv_" + id:
			draw_rect(pvr.grow(2.0), UI.CYAN, false, 1.5)
		_zoom_badge(pvr, hover == "pv_" + id)
		var twt: float = tw - pvw - 10.0
		UI.text_fit(self, font, Vector2(tx, r.position.y + (34 if ph else 30)), "关注作者" if id == "follow" else "三连视频", 21 if tl else 19, Color(UI.TEXT, dim), twt, 14)
		UI.text_fit(self, font, Vector2(tx, r.position.y + (58 if ph else 52)), "在 B站关注作者" if id == "follow" else "点赞 + 投币 + 收藏 PV", 14 if tl else 13, Color(UI.SUB, dim), twt, 10)
		UI.text_fit(self, font, Vector2(tx, r.position.y + (92 if ph else 84)), "寻访凭证 ×%d" % TS.REWARD, 20 if tl else 18, Color(UI.CYAN, dim), twt, 12)
		# 「边框名」单独一行，避免在名字中间折行
		var fl := UI.Loc.s("专属分享卡边框「%s」" % TS.frame_name(id))
		var cut: int = maxi(fl.find("「"), fl.find(" '"))
		var ffs: int = 14 if tl else 13
		var fy: float = r.position.y + (116 if ph else 106)
		if cut > 0:   # 两行时第二行别压到领取按钮（手机卡片矮）：放不下就并成一行缩字
			if fy + ffs + 7.0 > gb.position.y - 6.0:
				cut = -1
		var fcol := Color(UI.CYAN, dim * 0.8)
		if cut > 0:
			UI.text_fit(self, font, Vector2(tx, fy), fl.substr(0, cut).strip_edges(), ffs, fcol, twt, 10)
			UI.text_fit(self, font, Vector2(tx, fy + ffs + 7.0), fl.substr(cut).strip_edges(), ffs, fcol, twt, 10)
		else:
			UI.text_fit(self, font, Vector2(tx, fy), fl, ffs, fcol, twt, 10)
		var m: String = str(row_msg.get(id, ""))
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
	if _zoom != "":
		_draw_zoom()


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
