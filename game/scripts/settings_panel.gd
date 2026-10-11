extends Control
## 设置面板：标题界面与暂停菜单共用。键盘 ↑↓ 选择、←→ 调整、Esc 返回；也可用鼠标点击；手柄经 Pad 翻译成同样的按键。
## 分类页（2026-09-27 用户要求）：声音 / 画面 / 游戏，Q / E（手柄 LB / RB → PageUp / PageDown）或点标签切换；
## 每页末尾一行「返回」。选项本身（ROWS 的键名、类型、存档键）不变，TABS 只按键名分组
## 触屏（手机）不列 TOUCH_HIDE 里的桌面专用项（全屏 / 窗口分辨率：手机永远全屏、分辨率由系统定）；页签 / 底部提示不画键位
## 触屏选项列表可上下滑动（10-11）：标题 / 页签和「返回」钉住，中间的选项在裁剪子控件 list 里按 scroll_f 平移，行高 88（≈ 48 pt）；
## 手指拖动 1:1 跟手、松手带惯性，拖过 TAP_SLOP 不算点选；键盘 / 手柄选到看不见的行时自动滚到可见；桌面排版逐像素不变

signal closed

const UI = preload("res://scripts/ui.gd")

const ROWS := [
	{"cn": "主音量", "en": "MASTER", "key": "master", "type": "vol"},
	{"cn": "音乐", "en": "MUSIC", "key": "music", "type": "vol"},
	{"cn": "音效", "en": "SFX", "key": "sfx", "type": "vol"},
	{"cn": "语音", "en": "VOICE", "key": "voice", "type": "vol"},
	{"cn": "画质", "en": "QUALITY", "key": "quality", "type": "quality", "note": "低配机选低"},
	{"cn": "全屏", "en": "FULLSCREEN", "key": "fullscreen", "type": "bool"},
	{"cn": "窗口分辨率", "en": "RESOLUTION", "key": "res_index", "type": "res"},
	{"cn": "伤害数字", "en": "DAMAGE NUMBERS", "key": "dmg_numbers", "type": "bool"},
	{"cn": "命中顿帧", "en": "HIT STOP", "key": "hitstop", "type": "bool"},
	{"cn": "Boss 登场演出", "en": "BOSS INTRO", "key": "boss_intro", "type": "bool"},
	{"cn": "怪物轮廓光", "en": "ENEMY OUTLINE", "key": "outline", "type": "bool"},
	{"cn": "景深与前景", "en": "DEPTH OF FIELD", "key": "dof", "type": "bool"},
	{"cn": "辉光", "en": "BLOOM", "key": "bloom", "type": "bool"},
	{"cn": "水下滤镜", "en": "UNDERWATER FILTER", "key": "water_filter", "type": "bool"},
	{"cn": "法线光照", "en": "NORMAL LIGHTING", "key": "normal_maps", "type": "bool", "note": "下局生效"},
	{"cn": "亮度", "en": "BRIGHTNESS", "key": "brightness", "type": "bright"},
	{"cn": "手柄震动", "en": "CONTROLLER RUMBLE", "key": "pad_rumble", "type": "bool"},
	{"cn": "普通攻击", "en": "BASIC ATTACK", "key": "manual_attack", "type": "bool", "on": "手动", "off": "自动", "note": "下局生效"},
	# 测试版对局记录（docs/40，用户 10-10）：只在 Cfg.runs_log_enabled() 时列出（调试版 / 对内包），对外包没有这一行；
	# 点一下在系统文件管理器里选中 runs.jsonl，测试者把文件发回来
	{"cn": "对局记录", "en": "RUN LOG", "key": "runs", "type": "runs"},
	{"cn": "返回", "en": "BACK", "key": "", "type": "back"},
]
const RUNS_HINT := "测试版：本地记录对局摘要（不上传）"
## 分类：[中文, 英文, 该页的选项键名]；ROWS 里每个选项恰好出现在一页（返回行每页都有）
const TABS := [
	["声音", "SOUND", ["master", "music", "sfx", "voice"]],
	["画面", "DISPLAY", ["quality", "fullscreen", "res_index", "brightness", "bloom", "water_filter", "dof", "normal_maps"]],
	["游戏", "GAMEPLAY", ["manual_attack", "dmg_numbers", "outline", "hitstop", "boss_intro", "pad_rumble", "runs"]],
]

## 触屏不显示的选项键名（手机设置页改版 10-06）
const TOUCH_HIDE := ["fullscreen", "res_index"]

var font: Font
var tab := 0
var cur: Array = []          # 当前页的 ROWS 下标（最后一个是返回）
var tab_rects: Array = []
var sel := 0
var st := 0.0
var row_rects: Array = []
var pending_res := -1        # 分辨率：←→ 只选择，Enter / 点击「应用」才生效
## 触屏滚动（只在 Cfg.touch_device() 时用）
const T_STEP := 92.0         # 触屏行距
const T_ROW := 88.0          # 触屏行本体高（≈ 48 pt）
const T_BACK := 64.0         # 钉在底部的「返回」行高
const TAP_SLOP := 12.0       # 手指移动超过这个距离算拖动，不算点选
var list: Control            # 裁剪用的子控件：选项行画在它里面
var view := Rect2()          # 列表可视区（本控件坐标）
var scroll := 0.0            # 目标滚动量（像素）
var scroll_f := 0.0          # 显示用滚动量，逐帧逼近 scroll（键盘跳行时平滑，拖动时相等）
var scroll_max := 0.0
var drag_on := false         # 手指按着
var drag_moved := false      # 本次按下已经拖过 TAP_SLOP
var drag_vel := 0.0          # 松手惯性（像素 / 秒）
var press_pos := Vector2.ZERO
var follow_pending := false  # 排版前就要求滚到选中行（--settingssel）


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = load("res://fonts/ui.ttf")
	visible = false


func open() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	position = Vector2.ZERO
	size = get_viewport_rect().size
	if Cfg.ui_k != 1.0:
		Cfg.ui_fill(self)   # 触屏界面层放大：撑满 UI 逻辑区而不是视口
	sel = 0
	_set_tab(0)
	pending_res = Cfg.res_index
	if Cfg.touch_device() and list == null:
		list = Control.new()
		list.clip_contents = true
		list.mouse_filter = Control.MOUSE_FILTER_IGNORE
		list.draw.connect(_draw_list)
		add_child(list)
	visible = true
	queue_redraw()


## 滚到让第 si 行完整可见（触屏；返回行钉在底部不用滚）
func _follow() -> void:
	if list == null or sel >= cur.size() - 1:
		return
	if view.size.y <= 0.0:
		follow_pending = true   # 还没排过版：下一帧 _layout_touch 里再算
		return
	var y0: float = sel * T_STEP
	if y0 < scroll:
		scroll = y0
	elif y0 + T_ROW > scroll + view.size.y:
		scroll = y0 + T_ROW - view.size.y
	scroll = clampf(scroll, 0.0, scroll_max)
	drag_vel = 0.0


func set_scroll(v: float, instant := true) -> void:
	scroll = maxf(v, 0.0)   # 上限在 _layout_touch 里截
	drag_vel = 0.0
	if instant:
		scroll_f = scroll


func _set_tab(t: int) -> void:
	tab = (t + TABS.size()) % TABS.size()
	cur.clear()
	var touch: bool = Cfg.touch_device()
	for key in TABS[tab][2]:
		if touch and key in TOUCH_HIDE:
			continue
		if key == "runs" and not Cfg.runs_log_enabled():
			continue   # 对外包不记录，也不显示这一行
		for i in ROWS.size():
			if ROWS[i].key == key:
				cur.append(i)
	cur.append(ROWS.size() - 1)   # 返回
	sel = clampi(sel, 0, cur.size() - 1)
	scroll = 0.0
	scroll_f = 0.0
	drag_vel = 0.0


func close() -> void:
	visible = false
	Cfg.save()
	Sfx.play("ui_ok")
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_UP, KEY_W:
				sel = (sel + cur.size() - 1) % cur.size()
				_follow()
				Sfx.play("ui_move")
			KEY_DOWN, KEY_S:
				sel = (sel + 1) % cur.size()
				_follow()
				Sfx.play("ui_move")
			KEY_LEFT, KEY_A:
				_adjust(cur[sel], -1)
			KEY_RIGHT, KEY_D:
				_adjust(cur[sel], 1)
			KEY_Q, KEY_PAGEUP:
				_set_tab(tab - 1)
				sel = 0
				Sfx.play("ui_move")
			KEY_E, KEY_PAGEDOWN, KEY_TAB:
				_set_tab(tab + 1)
				sel = 0
				Sfx.play("ui_move")
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				if ROWS[cur[sel]].type == "res":
					_apply_res()
				else:
					_adjust(cur[sel], 1)
			KEY_ESCAPE:
				close()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var ev: InputEventMouseMotion = make_input_local(event)   # 标题页 / 界面层放大后：视口坐标 → 本控件坐标（桌面不变）
		var mp: Vector2 = ev.position
		if list != null and drag_on:
			# 触屏：按着拖动 = 滚动列表（1:1 跟手）；超过 TAP_SLOP 后松手不再算点选
			if drag_moved or press_pos.distance_to(mp) > TAP_SLOP:
				drag_moved = true
				scroll = clampf(scroll - ev.relative.y, 0.0, scroll_max)
				scroll_f = scroll
				var dt: float = maxf(get_process_delta_time(), 1.0 / 240.0)
				drag_vel = lerpf(drag_vel, -ev.relative.y / dt, 0.5)
			queue_redraw()
			return
		for i in row_rects.size():
			if row_rects[i].has_point(mp):
				sel = i
	elif event is InputEventMouseButton and list != null and event.button_index == MOUSE_BUTTON_LEFT:
		# 触屏：按下只记起点，松手没拖过才当点选（拖动滚列表时不能误触开关）
		var mp: Vector2 = make_input_local(event).position
		if event.pressed:
			drag_on = true
			drag_moved = false
			drag_vel = 0.0
			press_pos = mp
		else:
			drag_on = false
			if not drag_moved:
				_tap(mp, MOUSE_BUTTON_LEFT)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		_tap(make_input_local(event).position, event.button_index)
	queue_redraw()


## 点选 / 滚轮：mp 是本控件坐标；桌面按下即生效，触屏在松手时调用
func _tap(mp: Vector2, button: int) -> void:
	if button == MOUSE_BUTTON_LEFT:
		for t in tab_rects.size():
			if tab_rects[t].has_point(mp) and t != tab:
				_set_tab(t)
				sel = 0
				Sfx.play("ui_move")
				return   # 行矩形还是上一页的，下一帧重算
	for si in row_rects.size():
		var r: Rect2 = row_rects[si]
		var i: int = cur[si]
		if r.has_point(mp) and (list == null or si == cur.size() - 1 or view.has_point(mp)):
			var arrows: bool = ROWS[i].type in ["vol", "bright", "res"]
			var fx: float = (mp.x - r.position.x) / r.size.x
			var dir := 1
			if arrows:
				dir = -1 if fx < 0.62 else 1
			if button == MOUSE_BUTTON_LEFT:
				if ROWS[i].type == "res" and fx >= 0.62 and fx <= 0.88:
					_apply_res()
				else:
					_adjust(i, dir)
			elif button == MOUSE_BUTTON_WHEEL_UP:
				_adjust(i, 1)
			elif button == MOUSE_BUTTON_WHEEL_DOWN:
				_adjust(i, -1)
	get_viewport().set_input_as_handled()


func _adjust(i: int, dir: int) -> void:
	var row: Dictionary = ROWS[i]
	match row.type:
		"vol":
			Cfg.set(row.key, clamp(snappedf(Cfg.get(row.key) + dir * 0.1, 0.1), 0.0, 1.0))
		"bool":
			Cfg.set(row.key, not Cfg.get(row.key))
		"quality":
			Cfg.set_quality("low" if Cfg.quality == "high" else "high")
		"bright":
			Cfg.brightness = clampf(snappedf(Cfg.brightness + dir * 0.05, 0.05), 0.8, 1.4)
		"res":
			var n: int = Cfg.RESOLUTIONS.size()
			pending_res = (pending_res + (1 if dir > 0 else n - 1)) % n
			Sfx.play("ui_move")
			return
		"runs":
			Cfg.show_runs_folder()
			Sfx.play("ui_ok")
			return
		"back":
			close()
			return
	Cfg.apply()
	Sfx.play("ui_move")


func _apply_res() -> void:
	if pending_res == Cfg.res_index:
		return
	Cfg.res_index = pending_res
	Cfg.apply()
	pending_res = Cfg.res_index
	Sfx.play("ui_ok")


func _process(delta: float) -> void:
	if visible:
		st += delta
		if list != null:
			if not drag_on and absf(drag_vel) > 1.0:
				# 松手惯性：按速度继续滚，指数衰减；碰到两端停下
				scroll = clampf(scroll + drag_vel * delta, 0.0, scroll_max)
				drag_vel *= exp(-4.0 * delta)
				if scroll <= 0.0 or scroll >= scroll_max:
					drag_vel = 0.0
				scroll_f = scroll
			else:
				scroll_f = lerpf(scroll_f, scroll, 1.0 - exp(-14.0 * delta))
				if absf(scroll_f - scroll) < 0.1:
					scroll_f = scroll
			list.queue_redraw()
		queue_redraw()


func _draw() -> void:
	var vs := size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.02, 0.04, 0.8))
	var compact: bool = vs.y < 680.0
	# 触屏（手机）：面板占满、选项列表可滚动（_layout_touch，行距 92 / 行高 88、字 21–22）；桌面不变
	var touch: bool = Cfg.touch_device()
	# 面板高度按最长的一页定（各页高度一致，切页不跳）：标题 + 标签 146 + 行 46 × (n - 1) + 返回行 + 底部提示
	var most := 0
	for tb in TABS:
		most = maxi(most, tb[2].size())
	var rh: float = minf(146.0 + most * 46.0 + 44.0 + 56.0, vs.y - 8.0)
	var pw: float = 760.0 if touch else 640.0
	if touch:
		# 手机（界面层放大后逻辑约 1044×481，手机端 UI 优化 r2）：面板占满（左右各留 24），标题与分类页签同一行，
		# 不画底部提示；选项行在可滚动区里（10-11，取代 10-06 为塞下七行而压到 52 的行距）
		pw = vs.x - 48.0
		rh = vs.y - 8.0
	var r := Rect2(vs.x / 2 - pw / 2.0, vs.y / 2 - rh / 2.0, pw, rh)
	UI.panel(self, r, UI.BG2, UI.CYAN_DIM, 16.0, UI.CYAN, 81, st)
	UI.text(self, font, r.position + Vector2(40, 58 if not touch else 50), "设置", 28, UI.TEXT)
	UI.en(self, font, r.position + Vector2(112, 56 if not touch else 48), "SETTINGS", 13, UI.CYAN, 3.0)
	# 分类标签：中文 + 英文小字，当前页青色底线；两侧写切换键
	tab_rects.clear()
	var tx := r.position.x + (40.0 if not touch else 250.0)
	var ty := r.position.y + (84.0 if not touch else 18.0)
	var mp := get_local_mouse_position()
	for t in TABS.size():
		var tw: float = 112.0 if not touch else 150.0
		var tbr := Rect2(tx + t * (tw + 8.0), ty, tw, 40 if not touch else 44)
		tab_rects.append(tbr)
		var ton := t == tab
		var hov := tbr.has_point(mp)
		draw_rect(tbr, Color(0.05, 0.2, 0.24, 0.8) if ton else Color(1, 1, 1, 0.06 if hov else 0.03))
		draw_rect(Rect2(tbr.position.x, tbr.end.y - 3, tbr.size.x, 3), UI.CYAN if ton else Color(1, 1, 1, 0.12))
		UI.text(self, font, tbr.position + Vector2(0, 25 if not touch else 29), TABS[t][0], 17 if not touch else 20, UI.TEXT if ton else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, tw * 0.55)
		UI.en(self, font, tbr.position + Vector2(tw * 0.52, 24 if not touch else 28), TABS[t][1], 8, UI.CYAN if ton else UI.CYAN_DIM, 1.5)
	if not Pad.touch_ui():
		UI.keycap(self, font, Vector2(r.end.x - 118, ty + 11), Pad.hint("Q", "LB"), UI.SUB, 11)
		UI.keycap(self, font, Vector2(r.end.x - 70, ty + 11), Pad.hint("E", "RB"), UI.SUB, 11)
	UI.rule(self, Vector2(r.position.x + 30, ty + (50 if not touch else 58)), Vector2(r.end.x - 30, ty + (50 if not touch else 58)), UI.EDGE_DIM)
	row_rects.clear()
	if touch:
		_layout_touch(r)
		return
	# 行距按面板高度自适应：标题 + 标签 140 + 行 + 底部提示 40 都要放得下
	var top := r.position.y + 146.0
	var step: float = minf(40.0 if compact else 46.0, (r.end.y - 46.0 - top - 34.0) / float(maxi(1, cur.size() - 1)))
	var row_hh: float = minf(34.0, step)
	for si in cur.size():
		var back: bool = ROWS[cur[si]].type == "back"
		var rr := Rect2(r.position.x + 30, top + si * step + (10.0 if back else 0.0), r.size.x - 60, row_hh)
		row_rects.append(rr)
		_draw_row(self, rr, si, false, 24.0)
	if not touch:
		UI.text(self, font, Vector2(r.position.x, r.end.y - 18), Pad.hint("Q / E 切换分类 · ↑↓ 选择 · ←→ 调整 · Esc 返回", "LB / RB 切换分类 · 摇杆 ↑↓ 选择 · ←→ 调整 · Ⓐ 确认 · Ⓑ 返回", "点上方分类切换 · 点选项调整"), 13, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


## 触屏排版：标题 / 页签钉在顶部、「返回」钉在底部，其余行在 list 子控件里滚动（行距 T_STEP、行高 T_ROW）
func _layout_touch(r: Rect2) -> void:
	var back_rr := Rect2(r.position.x + 30, r.end.y - 14.0 - T_BACK, r.size.x - 60, T_BACK)
	view = Rect2(r.position.x + 30, r.position.y + 90.0, r.size.x - 60, back_rr.position.y - 10.0 - (r.position.y + 90.0))
	var n: int = cur.size() - 1   # 滚动区里的行数（不含返回）
	scroll_max = maxf(0.0, n * T_STEP - (T_STEP - T_ROW) - view.size.y)
	if follow_pending:
		follow_pending = false
		_follow()
		scroll_f = scroll
	scroll = clampf(scroll, 0.0, scroll_max)
	scroll_f = clampf(scroll_f, 0.0, scroll_max)
	list.position = view.position
	list.size = view.size
	for si in n:
		row_rects.append(Rect2(view.position.x, view.position.y + si * T_STEP - scroll_f, view.size.x, T_ROW))
	row_rects.append(back_rr)
	if scroll_max > 0.0:
		# 滚动条：列表右侧 4 像素细条（同选人页），上下有内容时边缘渐隐提示
		var track := Rect2(view.end.x - 4.0, view.position.y, 4.0, view.size.y)
		draw_rect(track, Color(1, 1, 1, 0.06))
		var th: float = maxf(24.0, track.size.y * view.size.y / (view.size.y + scroll_max))
		draw_rect(Rect2(track.position.x, track.position.y + (track.size.y - th) * clampf(scroll_f / scroll_max, 0.0, 1.0), 4.0, th), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.7))
		if scroll_f > 0.5:
			_vfade(Rect2(view.position.x, view.position.y, view.size.x - 8.0, 18.0), true)
		if scroll_f < scroll_max - 0.5:
			_vfade(Rect2(view.position.x, view.end.y - 18.0, view.size.x - 8.0, 18.0), false)
	# 返回行钉在底部；上方一道细线隔开
	UI.rule(self, Vector2(r.position.x + 30, back_rr.position.y - 5.0), Vector2(r.end.x - 30, back_rr.position.y - 5.0), UI.EDGE_DIM)
	_draw_row(self, back_rr, n, true, T_BACK / 2.0 + 8.0)
	list.queue_redraw()


## 可视区上 / 下边缘的暗色渐隐带：提示那头还有行（top = 靠上那条，深色在上）
func _vfade(r: Rect2, top: bool) -> void:
	var n := 6
	var h: float = r.size.y / n
	for k in n:
		var a: float = 0.5 * (1.0 - (k + 0.5) / n)
		var y: float = r.position.y + (k if top else n - 1 - k) * h
		draw_rect(Rect2(r.position.x, y, r.size.x, h + 0.5), Color(0, 0.02, 0.04, a))


## list 子控件的绘制：各行按 scroll_f 平移，超出 view 的被裁掉
func _draw_list() -> void:
	if not visible or view.size.y <= 0.0:
		return
	var n: int = cur.size() - 1
	for si in n:
		var rr := Rect2(0.0, si * T_STEP - scroll_f, view.size.x, T_ROW)
		if rr.end.y < 0.0 or rr.position.y > view.size.y:
			continue
		_draw_row(list, rr, si, true, T_ROW / 2.0 + 8.0)


## 画一行选项：rr 是 ci 坐标里的行矩形，ty0 是行内文字基线
func _draw_row(ci: CanvasItem, rr: Rect2, si: int, touch: bool, ty0: float) -> void:
	var i: int = cur[si]
	var row: Dictionary = ROWS[i]
	var fs_cn := 21 if touch else 17   # 选项名
	var fs_v := 22 if touch else 18    # 数值 / 开关
	var fs_a := 20 if touch else 14    # ◀ ▶ 与音量数字
	var on := si == sel
	if on:
		ci.draw_rect(rr, Color(0.05, 0.2, 0.24, 0.7))
		ci.draw_rect(Rect2(rr.position, Vector2(3, rr.size.y)), UI.CYAN)
	UI.text(ci, font, rr.position + Vector2(18, ty0), row.cn, fs_cn, UI.TEXT if on else UI.SUB)
	UI.en(ci, font, rr.position + Vector2(130 if not touch else 200, ty0 - 1.0), row.en, 9 if not touch else 10, UI.CYAN_DIM, 2.0)   # 触屏字大，「Boss 登场演出」要 200 才不压到英文
	if row.has("note"):
		UI.text(ci, font, rr.position + Vector2(rr.size.x - (70.0 if not touch else 84.0), ty0), row.note, 11 if not touch else 13, UI.SUB)
	var vx := rr.position.x + rr.size.x - (230.0 if not touch else 252.0)   # 触屏数值块左移 22：音量「100」（20 号字）不压到右侧滚动条
	match row.type:
		"runs":
			# 右侧「打开记录文件夹」当按钮；说明文字放在它左边
			# （触屏：说明右对齐到按钮左边 14 像素；桌面保持原位）
			UI.text(ci, font, Vector2(vx - 14 - (230.0 if touch else 0.0), rr.position.y + ty0), RUNS_HINT, 13 if touch else 11, UI.SUB, HORIZONTAL_ALIGNMENT_RIGHT, 230)
			var bh: float = 32.0 if touch else 26.0
			var br := Rect2(vx + 10, rr.position.y + (ty0 - 15.0 - (3.0 if touch else 0.0)), 180, bh)
			ci.draw_rect(br, Color(0.05, 0.2, 0.24, 0.9) if on else Color(0.04, 0.09, 0.12, 0.8))
			ci.draw_rect(br, UI.CYAN if on else UI.CYAN_DIM, false, 1.0)
			UI.text(ci, font, br.position + Vector2(0, 18 if not touch else 22), "打开记录文件夹", 14 if not touch else 16, UI.CYAN if on else UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, br.size.x)
		"vol":
			var v: float = Cfg.get(row.key)
			UI.text(ci, font, Vector2(vx - 10, rr.position.y + ty0), "◀", fs_a, UI.CYAN if on else UI.SUB)
			for k in 10:
				var c := UI.CYAN if k < int(round(v * 10.0)) else Color(0.15, 0.22, 0.26)
				ci.draw_rect(Rect2(vx + 16 + k * 16, rr.position.y + ty0 - 13.0, 12, 13), c)
			UI.text(ci, font, Vector2(vx + 180, rr.position.y + ty0), "▶", fs_a, UI.CYAN if on else UI.SUB)
			UI.text(ci, font, Vector2(vx + 200, rr.position.y + ty0), "%d" % int(round(v * 100.0)), fs_a, UI.TEXT)
		"bool":
			var b: bool = Cfg.get(row.key)
			UI.text(ci, font, Vector2(vx, rr.position.y + ty0), str(row.get("on", "开")) if b else str(row.get("off", "关")), fs_v, UI.CYAN if b else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 200)
		"quality":
			var hq: bool = Cfg.quality != "low"
			UI.text(ci, font, Vector2(vx, rr.position.y + ty0), "高" if hq else "低", fs_v, UI.CYAN if hq else UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER, 200)
		"bright":
			UI.text(ci, font, Vector2(vx - 10, rr.position.y + ty0), "◀", fs_a, UI.CYAN if on else UI.SUB)
			UI.text(ci, font, Vector2(vx, rr.position.y + ty0), "%d%%" % int(round(Cfg.brightness * 100.0)), fs_v, UI.CYAN, HORIZONTAL_ALIGNMENT_CENTER, 200)
			UI.text(ci, font, Vector2(vx + 180, rr.position.y + ty0), "▶", fs_a, UI.CYAN if on else UI.SUB)
		"res":
			var pi: int = clampi(pending_res, 0, Cfg.RESOLUTIONS.size() - 1)
			var sz: Vector2i = Cfg.RESOLUTIONS[pi]
			var changed: bool = pi != Cfg.res_index
			var label := "%d × %d" % [sz.x, sz.y]
			if Cfg.fullscreen:
				# 全屏说明放在 ◀ 左边的小字（原来接在数值后面，140 宽放不下、压到 ◀）
				UI.text(ci, font, Vector2(vx - 196, rr.position.y + ty0 - 1.0), "全屏时按屏幕分辨率", 12, UI.SUB, HORIZONTAL_ALIGNMENT_RIGHT, 176)
			UI.text(ci, font, Vector2(vx - 10, rr.position.y + ty0), "◀", fs_a, UI.CYAN if on else UI.SUB)
			UI.text(ci, font, Vector2(vx, rr.position.y + ty0), label, fs_cn, (UI.GOLD if changed else UI.CYAN) if not Cfg.fullscreen else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 140)
			if changed:
				var br := Rect2(vx + 142, rr.position.y + ty0 - 18.0, 42, 22)
				UI.panel(ci, br, Color(0.2, 0.15, 0.05, 0.9), UI.GOLD, 4.0)
				UI.text(ci, font, br.position + Vector2(0, 16), "应用", 12, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER, br.size.x)
			UI.text(ci, font, Vector2(vx + 190, rr.position.y + ty0), "▶", fs_a, UI.CYAN if on else UI.SUB)
