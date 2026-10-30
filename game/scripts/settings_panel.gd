extends Control
## 设置面板：标题界面与暂停菜单共用。键盘 ↑↓ 选择、←→ 调整、Esc 返回；也可用鼠标点击；手柄经 Pad 翻译成同样的按键。
## 分类页（2026-09-27 用户要求）：声音 / 画面 / 游戏，Q / E（手柄 LB / RB → PageUp / PageDown）或点标签切换；
## 每页末尾一行「返回」。选项本身（ROWS 的键名、类型、存档键）不变，TABS 只按键名分组
## 触屏（手机）不列 TOUCH_HIDE 里的桌面专用项（全屏 / 窗口分辨率：手机永远全屏、分辨率由系统定）；页签 / 底部提示不画键位
## 选项列表可滚动（10-11 触屏、10-14 全设备）：标题 / 页签钉住，各行（含末尾「返回」）在裁剪子控件 list 里按 scroll_f 平移，触屏行高 88（≈ 48 pt）；
## 手指拖动 1:1 跟手、松手带惯性，拖过 TAP_SLOP 不算点选；键盘 / 手柄选到看不见的行时自动滚到可见；桌面与触屏共享左分类、右列表布局

signal closed

const UI = preload("res://scripts/ui.gd")
const Shell = preload("res://scripts/screens/settings_shell.gd")

const ROWS := [
	{"cn": "主音量", "en": "MASTER", "key": "master", "type": "vol"},
	{"cn": "音乐", "en": "MUSIC", "key": "music", "type": "vol"},
	{"cn": "音效", "en": "SFX", "key": "sfx", "type": "vol"},
	{"cn": "语音", "en": "VOICE", "key": "voice", "type": "vol"},
	{"cn": "画质", "en": "QUALITY", "key": "quality", "type": "quality"},
	{"cn": "帧率上限", "en": "FPS CAP", "key": "max_fps", "type": "fps"},
	{"cn": "全屏", "en": "FULLSCREEN", "key": "fullscreen", "type": "bool"},
	{"cn": "窗口分辨率", "en": "RESOLUTION", "key": "res_index", "type": "res"},
	{"cn": "伤害数字", "en": "DAMAGE NUMBERS", "key": "dmg_numbers", "type": "bool"},
	{"cn": "命中顿帧", "en": "HIT STOP", "key": "hitstop", "type": "bool"},
	{"cn": "Boss 登场演出", "en": "BOSS INTRO", "key": "boss_intro", "type": "bool"},
	{"cn": "减少动态效果", "en": "REDUCE MOTION", "key": "reduce_motion", "type": "bool"},
	{"cn": "Boss 轮廓光", "en": "BOSS OUTLINE", "key": "outline", "type": "bool"},
	{"cn": "景深与前景", "en": "DEPTH OF FIELD", "key": "dof", "type": "bool"},
	{"cn": "辉光", "en": "BLOOM", "key": "bloom", "type": "bool"},
	{"cn": "水下滤镜", "en": "UNDERWATER FILTER", "key": "water_filter", "type": "bool"},
	{"cn": "法线光照", "en": "NORMAL LIGHTING", "key": "normal_maps", "type": "bool", "note": "下局生效"},
	{"cn": "亮度", "en": "BRIGHTNESS", "key": "brightness", "type": "bright"},
	# 界面大小 / 战斗画面缩放（用户 10-13：手机横屏太拥挤、战斗画面放大一点）：所有设备可用，实时生效
	{"cn": "界面大小", "en": "UI SIZE", "key": "ui_size_pct", "type": "uisize"},
	{"cn": "战斗画面缩放", "en": "BATTLE ZOOM", "key": "cam_zoom_pct", "type": "zoom"},
	{"cn": "手柄震动", "en": "CONTROLLER RUMBLE", "key": "pad_rumble", "type": "bool"},
	# 自动连携 / 自动终结技（docs/198 §1.4）：缺省桌面都关、手机自动连携开（Cfg._ready）；局内即时生效（run/ult.gd 每帧读）。ult/on = 0 时不列出
	{"cn": "自动连携", "en": "AUTO CHAIN", "key": "auto_combo", "type": "bool", "note": "队友头像亮起后自动出手"},
	{"cn": "自动终结技", "en": "AUTO ULTIMATE", "key": "auto_ult", "type": "bool", "note": "充满后，敌人密集、精英靠近或生命低于 30% 时自动释放"},
	# 触屏按键布局（用户 10-13）：点「调整」进编辑页（screens/touch_editor.gd），拖动改位置、调大小；只在触屏设备列出
	{"cn": "触屏按键布局", "en": "TOUCH LAYOUT", "key": "touch_layout", "type": "touchpad"},
	# 测试版对局记录（docs/40，用户 10-10）：只在 Cfg.runs_log_enabled() 时列出（调试版 / 对内包），对外包没有这一行；
	# 点一下在系统文件管理器里选中 runs.jsonl，测试者把文件发回来
	{"cn": "对局记录", "en": "RUN LOG", "key": "runs", "type": "runs"},
	# B站云存档（docs/89）：只在 B站 Toy 环境（Cloud.supported）多出「存档」页。状态行点一下 = 立即同步；恢复 / 覆盖要点两次确认
	{"cn": "云存档", "en": "CLOUD SAVE", "key": "cloud", "type": "cloud"},
	{"cn": "从云端恢复", "en": "RESTORE", "key": "cloud_pull", "type": "cloud_pull"},
	{"cn": "以本地覆盖云端", "en": "", "key": "cloud_push", "type": "cloud_push"},
	# 性能报告（10-27 用户：真机采集用）：点「查看」打开最近一局的性能摘要与「复制报告」（screens/perf_view.gd；数据 core/perf_report.gd，只存本机）
	{"cn": "性能报告", "en": "PERF REPORT", "key": "perf", "type": "perf"},
	{"cn": "返回", "en": "BACK", "key": "", "type": "back"},
]
const RUNS_HINT := "测试版：本地记录对局摘要（不上传）"
## 分类：[中文, 英文, 该页的选项键名]（返回行每页都有）。10-22 用户定 16 行清单（Codex 界面单 §4）：
## 命中顿帧 / Boss 登场演出 / Boss 轮廓光 / 景深 / 辉光 / 水下滤镜 / 法线光照 / 战斗画面缩放 / 对局记录不再露出——
## ROWS 与存档键都保留（旧存档兼容），后期四项跟画质档走，对局记录挪到作战结算底栏
const TABS := [
	["声音", "SOUND", ["master", "music", "sfx", "voice"]],
	["画面", "DISPLAY", ["quality", "max_fps", "fullscreen", "res_index", "brightness", "ui_size_pct", "dmg_numbers", "reduce_motion", "perf"]],
	["操作", "CONTROLS", ["auto_combo", "auto_ult", "pad_rumble", "touch_layout"]],
]

## 「存档」页：只在 B站 Toy 环境列出（_tabs）；面板高度仍按 TABS 定（这一页行数少），其他环境排版不变。
## 云存档只留一行状态（点一下立即同步）：自动同步已按并集 / 较新合并两边（docs/89 §4），10-22 用户定去掉
## 「从云端恢复」「以本地覆盖云端」两个手动入口（ROWS 与 Cloud.pull / push 代码保留，不再列出）
const CLOUD_TAB := ["存档", "SAVE DATA", ["cloud"]]
const CLOUD_HINT := {"cloud_pull": "云端存档替换本机进度与设置", "cloud_push": "本机存档覆盖云端存档"}
const CLOUD_BTN := {"cloud_pull": ["恢复", "确认恢复"], "cloud_push": ["覆盖", "确认覆盖"]}
var confirm_key := ""        # 恢复 / 覆盖：第一次点进入确认，CONFIRM_SECS 秒内再点一次才执行
var confirm_until := 0.0
const CONFIRM_SECS := 4.0

## 触屏不显示的选项键名（手机设置页改版 10-06）
const TOUCH_HIDE := ["fullscreen", "res_index"]
## 只在触屏设备显示的选项键名
const TOUCH_ONLY := ["touch_layout"]
## 局内打开设置时由 game.gd 设（触屏按键布局编辑页等用；标题页为 null）
var game_ref: Node = null
var editor: Control = null   # 触屏按键布局编辑页（第一次打开时建）
var perf_view: Control = null   # 性能报告页（第一次打开时建）
var eat_release := false     # 编辑页在按下时关掉：同一次点击的松手不能落到设置面板上（触屏版松手才算点选，会误点下面的行）

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
const D_STEP := 76.0         # 桌面行距
const D_ROW := 68.0          # 桌面行本体高
## 标题使用完整安全区，暂停保留四周 HUD 空间；几何由 settings_shell 统一绘制。
var panel_rect := Rect2()    # 面板（本控件坐标；测试读）
var footer_rect := Rect2()
var close_rect := Rect2()    # 右上角「×」的点击区
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
	# 转屏 / 浏览器栏收起：开着的设置面板跟着撑满新的 UI 逻辑区（标题页没有 game._ui_fit 代劳）
	get_viewport().size_changed.connect(_refit)
	Cfg.view_changed.connect(_refit)   # 「界面大小」在本页里改：面板跟着撑满新的 UI 逻辑区


func _refit() -> void:
	if visible:
		Cfg.ui_fill(self)


func open() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	position = Vector2.ZERO
	size = get_viewport_rect().size
	if Cfg.ui_k != 1.0:
		Cfg.ui_fill(self)   # 触屏界面层放大：撑满 UI 逻辑区而不是视口
	sel = 0
	_set_tab(1)
	pending_res = Cfg.res_index
	if list == null:
		list = Control.new()
		list.clip_contents = true
		list.mouse_filter = Control.MOUSE_FILTER_IGNORE
		list.draw.connect(_draw_list)
		add_child(list)
	visible = true
	queue_redraw()


func _tl() -> bool:
	return Cfg.touch_device()


func _step() -> float:
	return T_STEP if _tl() else D_STEP


func _rowh() -> float:
	return T_ROW if _tl() else D_ROW


## 滚到让选中行完整可见（键盘 / 手柄换行时）
func _follow() -> void:
	if list == null:
		return
	if view.size.y <= 0.0:
		follow_pending = true   # 还没排过版：下一帧 _layout_list 里再算
		return
	var y0: float = sel * _step()
	if y0 < scroll:
		scroll = y0
	elif y0 + _rowh() > scroll + view.size.y:
		scroll = y0 + _rowh() - view.size.y
	scroll = clampf(scroll, 0.0, scroll_max)
	drag_vel = 0.0


func set_scroll(v: float, instant := true) -> void:
	scroll = maxf(v, 0.0)   # 上限在 _layout_list 里截
	drag_vel = 0.0
	if instant:
		scroll_f = scroll


func _tabs() -> Array:
	return TABS + [CLOUD_TAB] if Cloud.supported else TABS


func _cycle_tab(dir: int) -> void:
	var order: Array = [1, 0, 2]
	if Cloud.supported:
		order.append(3)
	_set_tab(order[posmod(order.find(tab) + dir, order.size())])


func _set_tab(t: int) -> void:
	var tabs := _tabs()
	tab = (t + tabs.size()) % tabs.size()
	cur.clear()
	confirm_key = ""
	var touch: bool = Cfg.touch_device()
	for key in tabs[tab][2]:
		if touch and key in TOUCH_HIDE:
			continue
		if not touch and key in TOUCH_ONLY:
			continue
		if key == "runs" and not Cfg.runs_log_enabled():
			continue   # 对外包不记录，也不显示这一行
		if (key == "auto_combo" or key == "auto_ult") and preload("res://scripts/core/balance.gd").vi("ult/on", 1) <= 0:
			continue   # 终结技总开关关着（balance ult/on = 0）：没有终结技 / 连携技，这两行不列出
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
	Cloud.flush("settings")   # B站云存档：设置面板关闭时上传（只在 B站环境生效，docs/89）
	Sfx.play("ui_ok")
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible or (editor != null and editor.visible) or (perf_view != null and perf_view.visible):
		return   # 触屏按键布局编辑页 / 性能报告页开着：输入归它
	if eat_release and event is InputEventMouseButton:
		if not event.pressed:
			eat_release = false
			get_viewport().set_input_as_handled()
			return
		eat_release = false
	if event is InputEventKey and event.pressed:
		# 按住不放的自动重复只给方向键（连续调音量 / 换行）；Enter / 空格 / Q / E / Esc 按住不连发（原来按住 Enter 开关来回翻）
		if event.echo and not (Pad.kc(event) in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_W, KEY_S, KEY_A, KEY_D]):
			get_viewport().set_input_as_handled()
			return
		match Pad.kc(event):
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
				_cycle_tab(-1)
				sel = 0
				Sfx.play("ui_move")
			KEY_E, KEY_PAGEDOWN, KEY_TAB:
				_cycle_tab(1)
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
	elif event is InputEventMouseButton and _tl() and event.button_index == MOUSE_BUTTON_LEFT:
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
	if button == MOUSE_BUTTON_WHEEL_UP or button == MOUSE_BUTTON_WHEEL_DOWN:
		# 滚轮滚列表（原来滚轮在行上 = 调数值；面板缩到 70% 后选项要滚动才看得全）
		set_scroll(clampf(scroll + (_step() if button == MOUSE_BUTTON_WHEEL_DOWN else -_step()), 0.0, scroll_max), false)
		get_viewport().set_input_as_handled()
		return
	if button == MOUSE_BUTTON_LEFT and (close_rect.has_point(mp) or footer_rect.has_point(mp)):
		close()
		get_viewport().set_input_as_handled()
		return
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
		if r.has_point(mp) and view.has_point(mp):
			var arrows: bool = ROWS[i].type in ["vol", "bright", "res", "uisize", "zoom"]
			var control_x: float = r.position.x + r.size.x - 8.0 - (252.0 if _tl() else 230.0)
			var dir := 1
			if arrows:
				# 以数值块中点分左右（◀ 在 vx − 10、▶ 在 vx + 180，vx 同 _draw_row）。原来按整行宽 62% 分：桌面行宽 580 时恰好在中点，
				# 触屏行宽约 1100（面板占满）时 ◀ 落在 77% 处被当成 ▶，点 ◀ 也是加（用户 10-13「设置大小不能减小只能放大」）
				var vx: float = control_x
				dir = -1 if mp.x < vx + 85.0 else 1
			if button == MOUSE_BUTTON_LEFT:
				if ROWS[i].type == "res" and mp.x >= control_x and mp.x <= control_x + 184.0:
					_apply_res()
				elif ROWS[i].type == "fps" and mp.x >= control_x + 16.0:
					# 三格（自动 / 60 / 30，各 56 宽、间距 4，同画质格）：点哪格选哪档
					var fv: int = Cfg.MAX_FPS_OPTS[clampi(int((mp.x - (control_x + 16.0)) / 60.0), 0, 2)]
					if fv != Cfg.max_fps:
						Cfg.max_fps = fv
						Cfg.apply()
						Sfx.play("ui_move")
				elif ROWS[i].type == "quality" and mp.x >= control_x - 40.0:
					# 四格（推荐 / 低 / 中 / 高，各 56 宽、间距 4）：点哪格选哪档
					var qi := clampi(int((mp.x - (control_x - 40.0)) / 60.0), 0, 3)
					if Cfg.QUALITY_MODES[qi] != Cfg.quality_mode:
						Cfg.set_quality_mode(Cfg.QUALITY_MODES[qi])
						Cfg.apply()
						Sfx.play("ui_move")
				else:
					_adjust(i, dir)
	get_viewport().set_input_as_handled()


func _adjust(i: int, dir: int) -> void:
	var row: Dictionary = ROWS[i]
	match row.type:
		"vol":
			Cfg.set(row.key, clamp(snappedf(Cfg.get(row.key) + dir * 0.1, 0.1), 0.0, 1.0))
		"bool":
			Cfg.set(row.key, not Cfg.get(row.key))
		"quality":
			var qm: Array = Cfg.QUALITY_MODES
			Cfg.set_quality_mode(qm[posmod(qm.find(Cfg.quality_mode) + dir, qm.size())])
		"fps":
			var fo: Array = Cfg.MAX_FPS_OPTS
			Cfg.max_fps = fo[posmod(fo.find(Cfg.max_fps) + dir, fo.size())]
		"bright":
			Cfg.brightness = clampf(snappedf(Cfg.brightness + dir * 0.05, 0.05), 0.8, 1.4)
		"uisize":
			Cfg.ui_size_pct = clampi(Cfg.ui_size_pct + dir * 5, Cfg.UI_PCT_MIN, Cfg.UI_PCT_MAX)
		"zoom":
			# 调回设备缺省（手机横屏 ZOOM_PHONE_DEF / 桌面 ZOOM_DESK_DEF）时存 -1：换设备仍按那台的缺省
			var def: int = Cfg.zoom_default_pct()
			var n: int = clampi(int(round(Cfg.cam_zoom() * 100.0)) + dir * 5, Cfg.ZOOM_PCT_MIN, Cfg.ZOOM_PCT_MAX)
			Cfg.cam_zoom_pct = -1 if n == def else n
		"res":
			var n: int = Cfg.RESOLUTIONS.size()
			pending_res = (pending_res + (1 if dir > 0 else n - 1)) % n
			Sfx.play("ui_move")
			return
		"runs":
			Cfg.show_runs_folder()
			Sfx.play("ui_ok")
			return
		"touchpad":
			open_touch_editor()
			return
		"perf":
			open_perf()
			return
		"cloud":
			Cloud.flush("manual")
			Sfx.play("ui_ok")
			return
		"cloud_pull", "cloud_push":
			if not (Cloud.can_push() if row.type == "cloud_push" else Cloud.can_manual()):
				Sfx.play("ui_move", -4.0, 0.6)
				return
			if confirm_key == row.type and st < confirm_until:
				confirm_key = ""
				if row.type == "cloud_pull":
					Cloud.pull()
				else:
					Cloud.push()
				Sfx.play("ui_ok")
			else:
				confirm_key = row.type
				confirm_until = st + CONFIRM_SECS
				Sfx.play("ui_move")
			return
		"back":
			close()
			return
	Cfg.apply()
	Sfx.play("ui_move")


## 打开性能报告页（盖在设置面板上，关掉回到设置）
func open_perf() -> void:
	if perf_view == null:
		perf_view = preload("res://scripts/screens/perf_view.gd").new()
		add_child(perf_view)
		perf_view.closed.connect(func():
			eat_release = true
			drag_on = false)
	perf_view.open()


## 打开触屏按键布局编辑页（盖在设置面板上，关掉回到设置）
func open_touch_editor() -> void:
	if editor == null:
		editor = preload("res://scripts/screens/touch_editor.gd").new()
		add_child(editor)
		editor.closed.connect(func():
			eat_release = true
			drag_on = false)
	editor.open()
	Sfx.play("ui_ok")


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
	Shell.draw(self)


## 选项列表（所有设备）：标题 / 页签钉在顶部，各行（含末尾「返回」）在 list 子控件里按 scroll_f 平移；vr = 可视区
func _layout_list(vr: Rect2) -> void:
	view = vr
	var stp: float = _step()
	var n: int = cur.size()
	scroll_max = maxf(0.0, n * stp - (stp - _rowh()) - view.size.y)
	if follow_pending:
		follow_pending = false
		_follow()
		scroll_f = scroll
	scroll = clampf(scroll, 0.0, scroll_max)
	scroll_f = clampf(scroll_f, 0.0, scroll_max)
	list.position = view.position
	list.size = view.size
	for si in n:
		row_rects.append(Rect2(view.position.x, view.position.y + si * stp - scroll_f, view.size.x, _rowh()))
	if scroll_max > 0.0:
		# 滚动条：列表右侧 4 像素细条（同选人页），上下有内容时边缘渐隐提示
		var track := Rect2(view.end.x - 4.0, view.position.y, 4.0, view.size.y)
		draw_rect(track, Color(1, 1, 1, 0.06))
		var th: float = maxf(24.0, track.size.y * view.size.y / (view.size.y + scroll_max))
		draw_rect(Rect2(track.position.x, track.position.y + (track.size.y - th) * clampf(scroll_f / scroll_max, 0.0, 1.0), 4.0, th), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.7))
	list.queue_redraw()


## 可视区上 / 下边缘的暗色渐隐带：提示那头还有行（top = 靠上那条，深色在上）
func _vfade_on(ci: CanvasItem, r: Rect2, top: bool) -> void:
	var n := 6
	var h: float = r.size.y / n
	for k in n:
		var a: float = 0.5 * (1.0 - (k + 0.5) / n)
		var y: float = r.position.y + (k if top else n - 1 - k) * h
		ci.draw_rect(Rect2(r.position.x, y, r.size.x, h + 0.5), Color(0, 0.02, 0.04, a))


## list 子控件的绘制：各行按 scroll_f 平移，超出 view 的被裁掉
func _draw_list() -> void:
	if not visible or view.size.y <= 0.0:
		return
	var touch: bool = _tl()
	var stp: float = _step()
	var rh: float = _rowh()
	for si in cur.size():
		var rr := Rect2(0.0, si * stp - scroll_f, view.size.x - 8.0, rh)
		if rr.end.y < 0.0 or rr.position.y > view.size.y:
			continue
		_draw_row(list, rr, si, touch, rh / 2.0 + (0.0 if touch else -2.0))
	# 上下还有行时边缘渐隐（画在 list 里，跟着裁剪）
	if scroll_f > 0.5:
		_vfade_on(list, Rect2(0.0, 0.0, view.size.x - 8.0, 18.0), true)
	if scroll_f < scroll_max - 0.5:
		_vfade_on(list, Rect2(0.0, view.size.y - 18.0, view.size.x - 8.0, 18.0), false)


## 画一行选项：rr 是 ci 坐标里的行矩形，ty0 是行内文字基线
func _draw_row(ci: CanvasItem, rr: Rect2, si: int, touch: bool, ty0: float) -> void:
	var i: int = cur[si]
	var row: Dictionary = ROWS[i]
	var fs_cn := 21 if touch else 17   # 选项名
	var fs_v := 22 if touch else 18    # 数值 / 开关
	var fs_a := 20 if touch else 14    # ◀ ▶ 与音量数字
	var on := si == sel
	ci.draw_line(Vector2(rr.position.x + 18, rr.end.y - 1), Vector2(rr.end.x - 10, rr.end.y - 1), Color("303a44"), 1.0)
	if on:
		ci.draw_rect(rr, Color(0.05, 0.2, 0.24, 0.7))
		ci.draw_rect(Rect2(rr.position, Vector2(3, rr.size.y)), UI.CYAN)
	UI.text(ci, font, rr.position + Vector2(18, ty0), row.cn, fs_cn, UI.TEXT if on else UI.SUB)
	UI.en(ci, font, rr.position + Vector2(18, ty0 + 16), row.en, 9, UI.CYAN_DIM, 1.0)
	if row.has("note"):
		UI.text(ci, font, rr.position + Vector2(18, ty0 + 31), row.note, 11 if not touch else 13, UI.SUB)
	var vx := rr.position.x + rr.size.x - (230.0 if not touch else 252.0)   # 触屏数值块左移 22：音量「100」（20 号字）不压到右侧滚动条
	match row.type:
		"cloud":
			# 状态：已同步 / 同步中 / 待上传 / 未登录（仅本地保存）……；手动操作的结果短暂替换显示
			var stt: String = Cloud.msg if Cloud.msg != "" else Cloud.status_text()
			var good: bool = Cloud.msg == "" and stt == "已同步"
			UI.text(ci, font, Vector2(rr.end.x - 16.0 - 380.0, rr.position.y + ty0), stt, fs_v - 2, UI.CYAN if good else (UI.GOLD if Cloud.msg != "" else UI.TEXT), HORIZONTAL_ALIGNMENT_RIGHT, 380)
		"cloud_pull", "cloud_push":
			var can: bool = Cloud.can_push() if row.type == "cloud_push" else Cloud.can_manual()
			var conf: bool = confirm_key == row.type and st < confirm_until
			var hint: String = "再点一次确认" if conf else (CLOUD_HINT[row.type] if can else ("请更新游戏" if Cloud.st == Cloud.St.NEWER else "登录后可用"))
			UI.text(ci, font, Vector2(vx - 14 - 230.0, rr.position.y + ty0), hint, 13 if touch else 11, UI.GOLD if conf else UI.SUB, HORIZONTAL_ALIGNMENT_RIGHT, 230)
			var bh3: float = 32.0 if touch else 26.0
			var br3 := Rect2(vx + 10, rr.position.y + (ty0 - 15.0 - (3.0 if touch else 0.0)), 180, bh3)
			ci.draw_rect(br3, Color(0.2, 0.15, 0.05, 0.9) if conf else (Color(0.05, 0.2, 0.24, 0.9) if on and can else Color(0.04, 0.09, 0.12, 0.8)))
			ci.draw_rect(br3, UI.GOLD if conf else (UI.CYAN if on and can else UI.CYAN_DIM), false, 1.0)
			UI.text(ci, font, br3.position + Vector2(0, 18 if not touch else 22), CLOUD_BTN[row.type][1 if conf else 0], 14 if not touch else 16,
				UI.GOLD if conf else (UI.CYAN if on and can else (UI.TEXT if can else UI.SUB)), HORIZONTAL_ALIGNMENT_CENTER, br3.size.x)
		"runs":
			# 右侧「打开记录文件夹」当按钮；说明文字放在它左边
			# （触屏：说明右对齐到按钮左边 14 像素；桌面保持原位）
			UI.text(ci, font, Vector2(vx - 14 - (230.0 if touch else 0.0), rr.position.y + ty0), RUNS_HINT, 13 if touch else 11, UI.SUB, HORIZONTAL_ALIGNMENT_RIGHT, 230)
			var bh: float = 32.0 if touch else 26.0
			var br := Rect2(vx + 10, rr.position.y + (ty0 - 15.0 - (3.0 if touch else 0.0)), 180, bh)
			ci.draw_rect(br, Color(0.05, 0.2, 0.24, 0.9) if on else Color(0.04, 0.09, 0.12, 0.8))
			ci.draw_rect(br, UI.CYAN if on else UI.CYAN_DIM, false, 1.0)
			UI.text(ci, font, br.position + Vector2(0, 18 if not touch else 22), "打开记录文件夹", 14 if not touch else 16, UI.CYAN if on else UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, br.size.x)
		"perf":
			# 右侧「查看」按钮；左边一行最近一局摘要（没有记录写「暂无记录」）
			var pr: Array = preload("res://scripts/core/perf_report.gd").load_all()
			var ph: String = "暂无记录" if pr.is_empty() else "最近一局 P95 %.1f 毫秒 · 最低 %s 帧" % [float(pr[0].get("p95", 0)), ("%.0f" % float(pr[0].get("min1s", 0))) if float(pr[0].get("min1s", 0)) > 0.0 else "—"]
			UI.text(ci, font, Vector2(vx - 14 - 300.0, rr.position.y + ty0), ph, 13 if touch else 12, UI.SUB if pr.is_empty() else UI.CYAN_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 300)
			var bh4: float = 32.0 if touch else 26.0
			var br4 := Rect2(vx + 10, rr.position.y + (ty0 - 15.0 - (3.0 if touch else 0.0)), 180, bh4)
			ci.draw_rect(br4, Color(0.05, 0.2, 0.24, 0.9) if on else Color(0.04, 0.09, 0.12, 0.8))
			ci.draw_rect(br4, UI.CYAN if on else UI.CYAN_DIM, false, 1.0)
			UI.text(ci, font, br4.position + Vector2(0, 18 if not touch else 22), "查看", 14 if not touch else 16, UI.CYAN if on else UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, br4.size.x)
		"touchpad":
			# 右侧「调整」按钮；左边一行说明（有自定义时写「已自定义」）
			var custom: bool = not Cfg.touch_layout.is_empty()
			UI.text(ci, font, Vector2(vx - 14 - (230.0 if touch else 0.0), rr.position.y + ty0), "已自定义" if custom else "默认布局", 13 if touch else 11, UI.CYAN if custom else UI.SUB, HORIZONTAL_ALIGNMENT_RIGHT, 230)
			var bh2: float = 32.0 if touch else 26.0
			var br2 := Rect2(vx + 10, rr.position.y + (ty0 - 15.0 - (3.0 if touch else 0.0)), 180, bh2)
			ci.draw_rect(br2, Color(0.05, 0.2, 0.24, 0.9) if on else Color(0.04, 0.09, 0.12, 0.8))
			ci.draw_rect(br2, UI.CYAN if on else UI.CYAN_DIM, false, 1.0)
			UI.text(ci, font, br2.position + Vector2(0, 18 if not touch else 22), "调整", 14 if not touch else 16, UI.CYAN if on else UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, br2.size.x)
		"vol":
			var v: float = Cfg.get(row.key)
			UI.text(ci, font, Vector2(vx - 10, rr.position.y + ty0), "◀", fs_a, UI.CYAN if on else UI.SUB)
			for k in 10:
				var c := UI.CYAN if k < int(round(v * 10.0)) else Color(0.15, 0.22, 0.26)
				ci.draw_rect(Rect2(vx + 16 + k * 16, rr.position.y + ty0 - 13.0, 12, 13), c)
			UI.text(ci, font, Vector2(vx + 180, rr.position.y + ty0), "▶", fs_a, UI.CYAN if on else UI.SUB)
			UI.text(ci, font, Vector2(vx + 200, rr.position.y + ty0), "%d%%" % int(round(v * 100.0)), fs_a, UI.TEXT)
		"bool":
			var enabled: bool = Cfg.get(row.key)
			var track := Rect2(vx + 128, rr.position.y + ty0 - 21, 72, 28)
			ci.draw_rect(track, Color("174956") if enabled else Color("303a44"))
			ci.draw_rect(Rect2(track.position + Vector2(44 if enabled else 4, 4), Vector2(24, 20)), UI.CYAN if enabled else UI.SUB)
			UI.text(ci, font, Vector2(vx, rr.position.y + ty0), str(row.get("on", "开启")) if enabled else str(row.get("off", "关闭")), fs_v - 2, UI.CYAN if enabled else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 116)
		"quality":
			# 四格 推荐 / 低 / 中 / 高（10-27：「自动」改「推荐」——只在启动时按设备定档，局中不再自动降，docs/50 §36）；推荐时行尾左侧写「按设备推荐：中」
			for qi in 4:
				var m: String = Cfg.QUALITY_MODES[qi]
				var active: bool = m == Cfg.quality_mode
				var qr := Rect2(vx - 40 + qi * 60, rr.position.y + ty0 - 25, 56, 36)
				ci.draw_rect(qr, UI.CYAN if active else Color("1b252e"))
				UI.text(ci, font, qr.position + Vector2(0, 25), "推荐" if m == "auto" else Cfg.QUALITY_NAME[m], fs_v - (2 if m == "auto" else 0), Color("10151b") if active else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, qr.size.x)
			if Cfg.quality_mode == "auto":
				UI.text(ci, font, Vector2(vx - 236, rr.position.y + ty0 - 1.0), "按设备推荐：%s" % Cfg.QUALITY_NAME.get(Cfg.quality, "高"), 12 if not touch else 13, UI.CYAN_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 186)
		"fps":
			# 三格 自动 / 60 / 30（同画质格的样式，右对齐到数值块末端）
			for fi in 3:
				var fv: int = Cfg.MAX_FPS_OPTS[fi]
				var active: bool = fv == Cfg.max_fps
				var fr := Rect2(vx + 16 + fi * 60, rr.position.y + ty0 - 25, 56, 36)
				ci.draw_rect(fr, UI.CYAN if active else Color("1b252e"))
				UI.text(ci, font, fr.position + Vector2(0, 25), "自动" if fv == 0 else str(fv), fs_v - (2 if fv == 0 else 0), Color("10151b") if active else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, fr.size.x)
			if Cfg.max_fps == 0 and Cfg.fps_lock30:
				UI.text(ci, font, Vector2(vx - 236, rr.position.y + ty0 - 1.0), "已按本机锁 30", 12 if not touch else 13, UI.CYAN_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 246)
		"uisize", "zoom":
			var pv: int = Cfg.ui_size_pct if row.type == "uisize" else int(round(Cfg.cam_zoom() * 100.0))
			var dflt: bool = (Cfg.ui_size_pct == 100) if row.type == "uisize" else (Cfg.cam_zoom_pct < 0)
			var lo: float = Cfg.UI_PCT_MIN if row.type == "uisize" else Cfg.ZOOM_PCT_MIN
			var hi: float = Cfg.UI_PCT_MAX if row.type == "uisize" else Cfg.ZOOM_PCT_MAX
			var fill: float = clampf((pv - lo) / (hi - lo), 0, 1)
			for tick in 20:
				ci.draw_rect(Rect2(vx + tick * 9, rr.position.y + ty0 + 12, 6, 4), UI.CYAN if tick <= fill * 19 else Color("303a44"))
			UI.text(ci, font, Vector2(vx - 10, rr.position.y + ty0), "◀", fs_a, UI.CYAN if on else UI.SUB)
			UI.text(ci, font, Vector2(vx, rr.position.y + ty0), "%d%%" % pv, fs_v, UI.CYAN, HORIZONTAL_ALIGNMENT_CENTER, 200)
			UI.text(ci, font, Vector2(vx + 180, rr.position.y + ty0), "▶", fs_a, UI.CYAN if on else UI.SUB)
			if dflt:
				UI.text(ci, font, Vector2(vx - 196, rr.position.y + ty0 - 1.0), "默认", 12 if not touch else 13, UI.SUB, HORIZONTAL_ALIGNMENT_RIGHT, 176)
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
