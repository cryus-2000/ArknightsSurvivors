extends "res://scripts/screens/title_base.gd"
## 标题界面 · 选开局干员页（docs/126 C2，10-22 由 title.gd 原样拆出；继承链见 title_base.gd）

# =====================================================================
# 选开局干员（B+，docs/58 §11，用户 10-11 定稿）：水月底 + 职业色斜带 + 巨型描边英文名 + 微型代码；
# 左职业轨、底部横向名册（触屏：左侧两列竖滚）、待机帧整数倍放大当立绘、右侧 属性 / 技能 / 编队 页签、编队条、青色出击 + 深海浪幕转场。
# 名册来自 data/characters/*.json（recruitable），新干员自动出现。排版按两张设计稿画：桌面 1280×720、触屏 740×360（概念图同尺寸），
# 再整体缩放进当前界面（op_k / op_off）；命中区都记在设计坐标里。
# 动效全是界面层：用标题页自己的真实时间 t（不是 g.t）、不碰任何随机数；「减少动态效果」（Cfg.reduce_motion）开启时
# 位移 / 缩放 / 扫入 / 浪幕直接到终态，只留 ≤ 120 ms 淡入淡出（OP_FADE），呼吸光不动
# =====================================================================
const OP_TABS := ["属性", "技能", "编队"]
const OP_TAB_EN := ["STATUS", "SKILL", "SQUAD"]
const OP_STAGE := ["招募", "精英一", "精英二"]
const OP_FADE := 0.12
## 立绘倍数（相对 @2x 像素的整数倍，最近邻）：桌面设计稿用它，手机按 0.6 倍；原定稿 5（10-11 用户：「干员大小可以缩小点」→ 4）。
## 描边英文名、外晕、脚底位置都按它和 5 的比例联动；--opartk=<k> 截图时临时覆盖（比较方案用）
const OP_ART_K := 4.0
var op_art_k := OP_ART_K
const OP_DESK := Vector2(1280, 720)
const OP_PHONE := Vector2(740, 360)
var op_filter := ""              # 职业筛选（"" = 全部）
var op_tab := 1                  # 信息页签：0 属性 / 1 技能 / 2 编队
var op_skill := 2                # 技能页展开说明的那一行
var op_rects := {}               # 命中区（设计坐标）：卡 = op_defs 下标（int），其余 "go" / "back" / "cls:<职业>" / "more_l" / "more_r"
var op_prects := {}              # 信息面板里的命中区："tab0".. / "sk0"..（面板子控件画的时候填）
var op_k := 1.0                  # 界面坐标 = op_off + 设计坐标 × op_k
var op_off := Vector2.ZERO
var op_vis := 10                 # 桌面名册一屏几张
var op_scroll := 0.0             # 名册滚动（设计像素，目标）
var op_scroll_f := 0.0           # 显示用，逐帧逼近（拖动时相等）
var op_drag_on := false          # 触屏：在名册里按下（松手时没拖动才算点选）
var op_dragging := false
var op_press_pos := Vector2.ZERO
var op_last_pos := Vector2.ZERO
var op_hover := {}               # 卡下标 → 悬停 0–1
var op_max := {}                 # 属性页量条的满值（全体干员各项上限）
var op_sw_t := -10.0             # 换干员的时刻（标题页时间 t）
var op_prev_sel := -1            # 换干员前的选中（旧卡落回 / 旧色带）
var op_open_t := -10.0           # 打开选人页（面板从右滑入）
var op_tab_t := -10.0
var op_tab_from := 1
var op_press_t := -1.0           # 按下出击
var op_wipe_t := -1.0            # 浪幕开始
var op_wipe_swapped := false
var op_go_id := ""
var op_panel: Control            # 右侧信息面板（打开时整体滑入）
var op_body: Control             # 面板正文（换干员滑入、换页签淡出）
var op_wipe_layer: Control       # 浪幕：最上层子控件，盖住选人页与难度页
var op_bg := {}                  # 背景固定几何（浪纹、触须、灯火光点；固定种子的本地 RNG，只算一次）
var op_glow_tex: Texture2D
var op_motion := -1.0            # --opmotion：动效录制开始时刻
var codex_motion := -1           # --codexmotion：已录帧数
var _cover_name_id := "~"
var _cover_name := ""
var glass_perf := -1             # --glassperf：已跑帧数
var glass_acc := [0.0, 0.0, 0, 0, 0.0, 0.0]   # 开 / 关 累计秒数与帧数、GPU 渲染毫秒
var post_fx: CanvasLayer


func _op_layers() -> void:
	op_panel = Control.new()
	op_body = Control.new()
	op_wipe_layer = Control.new()
	for c in [op_panel, op_body, op_wipe_layer]:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.visible = false
	add_child(op_panel)
	op_panel.add_child(op_body)
	add_child(op_wipe_layer)
	op_panel.draw.connect(_draw_op_panel)
	op_body.draw.connect(_draw_op_body)
	op_wipe_layer.draw.connect(_draw_op_wipe)
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1))
	gr.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = gr
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 128
	op_glow_tex = gt


func _open_op_pick(for_cover := false) -> void:
	cover_pick = for_cover
	if op_defs.is_empty():
		var lf := FileAccess.open("res://data/lore.json", FileAccess.READ)
		if lf != null:
			var ld = JSON.parse_string(lf.get_as_text())
			if ld is Dictionary:
				op_lore = ld
		for cid in Character.list_ids():
			var d: Dictionary = Character.load_def(cid)
			if not d.get("recruitable", true):
				continue
			var sp: Dictionary = d.get("sprites", {})
			var idle = sp.get("idle", "")
			var tn: String = idle if idle is String else idle.get("tex", "")
			var tx: Texture2D = A.tex_hi(tn) if tn != "" else null   # 立绘 / 名册用 @2x 精细版（10-23 用户，art.gd tex_hi）
			var frames: int = 1
			if idle is Dictionary and idle.has("frames"):
				frames = int(idle.frames)
			elif tx != null:
				frames = max(1, tx.get_width() / tx.get_height())
			if Character.strip_mirror(d, "idle"):
				tx = A.mirror_strip(tx, frames)   # 待机条画反了（docs/84）：立绘 / 编队小像用镜像副本
			var cls: String = d.get("class", "")
			var col: Color = Character.CLASS_COL.get(cls, UI.CYAN)
			var cc = d.get("col", null)
			if cc is Array and cc.size() >= 3:
				col = Color(float(cc[0]), float(cc[1]), float(cc[2]))
			var sh: Dictionary = InitialStats.sheet(cid, d)   # 选人「属性」页与图鉴「属性」页同一张表
			var elite := 0
			for n in d.get("progression", []):
				if n is Dictionary and n.get("type", "") == "elite":
					elite += 1
			op_defs.append({"id": cid, "def": d, "tex": tx, "frames": frames, "hires": A.hires_of(tx), "ds": UI.op_scale(d), "lore": op_lore.get(cid, {}).get("lore", ""),
				"sheet": sh, "name": d.get("name", cid), "en": str(d.get("en", cid.to_upper())), "cls": cls, "col": col,
				"elite": elite if elite > 0 else 2, "melee": _op_is_melee(d),
				"vals": {"hp": InitialStats.row(sh, "hp").val, "atk": InitialStats.row(sh, "atk").val, "cd": InitialStats.row(sh, "cd").val,
					"reach": InitialStats.row(sh, "reach").val, "speed": InitialStats.row(sh, "speed").val, "dps": InitialStats.row(sh, "dps").val}})
		# 原作按稀有度排；本作没有稀有度：封面干员水月在前，其余按职业顺序（docs/58 §11 概念图同序）
		op_defs.sort_custom(func(a, b):
			var ka: int = 0 if a.def.get("list_first", false) else 1   # list_first：干员 json（封面干员水月排第一）
			var kb: int = 0 if b.def.get("list_first", false) else 1
			if ka != kb:
				return ka < kb
			var ca: int = CLASS_ORDER.find(a.cls)
			var cb: int = CLASS_ORDER.find(b.cls)
			return ca < cb if ca != cb else a.id < b.id)
		for key in ["hp", "atk", "cd", "reach", "speed", "dps"]:
			var mx := 0.001
			for od in op_defs:
				mx = maxf(mx, float(od.vals[key]))
			op_max[key] = mx
	op_sel = 0
	var lst0 := _op_list()
	if not lst0.is_empty():
		op_sel = lst0[0]
	for i in lst0:
		if op_defs[i].id == (Cfg.cover_character_id if cover_pick else Cfg.character_id):
			op_sel = i
	op_filter = ""
	op_tab = 1
	op_tab_from = 1
	op_skill = _op_default_skill()
	op_hover.clear()
	op_press_t = -1.0
	op_wipe_t = -1.0
	op_scroll = 0.0
	op_pick = true
	_op_reenter()
	_op_follow(true)


## 打开 / 从难度页返回：面板滑入、色带扫入、立绘与名字重新进场
func _op_reenter() -> void:
	op_pick = true
	op_open_t = t
	op_sw_t = t
	op_tab_t = -10.0
	op_prev_sel = -1
	op_press_t = -1.0


## 技能页默认展开：有手动技能就展开它（主控的 Q），否则 S3
func _op_default_skill() -> int:
	if op_defs.is_empty():
		return 2
	var sks: Array = op_defs[op_sel].def.get("skills", [])
	for i in sks.size():
		if sks[i] is Dictionary and sks[i].get("mode", "auto") == "manual":
			return i
	return mini(2, maxi(0, sks.size() - 1))


## 触屏模式（同 touch.gd 的开启条件）：选人页用 740×360 手机版式、名册竖滑、不认悬停
func _touch_mode() -> bool:
	return Cfg.touch_device()


func _op_list() -> Array:
	var out: Array = []
	for i in op_defs.size():
		if (op_filter == "" or op_defs[i].cls == op_filter) and _op_ok(i):
			out.append(i)
	return out


## 名册里能不能选：选封面干员时全部可选；选开局干员时只有已解锁的（docs/109 §12）
func _op_ok(i: int) -> bool:
	return cover_pick or Roster.is_unlocked(op_defs[i].id)


func _op_classes() -> Array:
	var out: Array = [""]
	out.append_array(CLASS_ORDER)
	return out


func _op_class_count(c: String) -> int:
	var n := 0
	for i in op_defs.size():
		if (c == "" or op_defs[i].cls == c) and _op_ok(i):
			n += 1
	return n


## 界面坐标 → 设计坐标
func _op_design(p: Vector2) -> Vector2:
	return (p - op_off) / op_k


## 位移类动效进度（减少动态效果：直接 1）
func _op_p(t0: float, delay: float, dur: float) -> float:
	if Cfg.reduce_motion:
		return 1.0
	return clampf((t - t0 - delay) / dur, 0.0, 1.0)


## 透明度类动效进度（减少动态效果：从 t0 起 ≤ 120 ms 淡入）
func _op_a(t0: float, delay: float, dur: float) -> float:
	if Cfg.reduce_motion:
		return clampf((t - t0) / OP_FADE, 0.0, 1.0)
	return clampf((t - t0 - delay) / dur, 0.0, 1.0)


func _op_input(event: InputEvent) -> void:
	if op_press_t >= 0.0:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match Pad.kc(event):
			KEY_LEFT, KEY_A:
				_op_step(-1)
			KEY_RIGHT, KEY_D:
				_op_step(1)
			KEY_UP, KEY_W:
				_op_set_tab(op_tab - 1)
			KEY_DOWN, KEY_S:
				_op_set_tab(op_tab + 1)
			KEY_PAGEUP, KEY_Q:
				_op_filter_step(-1)
			KEY_PAGEDOWN, KEY_E:
				_op_filter_step(1)
			KEY_TAB, KEY_Z:
				_op_skill_step(1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_op_go()
			KEY_ESCAPE, KEY_BACKSPACE:
				_op_back()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_op_step(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var p := _op_design(make_input_local(event).position)
		if event.pressed:
			op_press_pos = p
			op_last_pos = p
			op_dragging = false
			op_drag_on = _touch_mode() and _op_in_roster(p)
			if not op_drag_on:
				_op_tap(p)
		else:
			if op_drag_on and not op_dragging:
				_op_tap(op_press_pos)
			op_drag_on = false
			op_dragging = false
	elif event is InputEventMouseMotion and op_drag_on and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		# 触屏拖动名册：1:1 跟手（手机竖滑、桌面触屏横滑），拖过 12 像素不再算点选
		var p := _op_design(make_input_local(event).position)
		var d := p - op_last_pos
		op_last_pos = p
		if (p - op_press_pos).length() > 12.0:
			op_dragging = true
		op_scroll = clampf(op_scroll - d.y, 0.0, _op_scroll_max())
		op_scroll_f = op_scroll


## 名册区（设计坐标）：手机是左侧两列，触屏宽屏同桌面是底部一排
func _op_in_roster(p: Vector2) -> bool:
	return Rect2(0, 34, 146, 326).has_point(p)


func _op_tap(p: Vector2) -> void:
	for k in op_prects:
		if op_prects[k].has_point(p):
			if k.begins_with("tab"):
				_op_set_tab(int(k.substr(3)))
			elif k.begins_with("sk"):
				if op_skill != int(k.substr(2)):
					op_skill = int(k.substr(2))
					Sfx.play("ui_move")
			return
	for k in op_rects:
		if op_rects[k].has_point(p):
			if k is int:
				if op_sel == k:
					_op_go()
				else:
					_op_select(k)
			elif k == "go":
				_op_go()
			elif k == "back":
				_op_back()
			elif k.begins_with("cls:"):
				_op_set_filter(k.substr(4))
			elif k == "more_r" or k == "more_l":
				_op_page(1 if k == "more_r" else -1)
			return


func _op_step(d: int) -> void:
	var lst := _op_list()
	if lst.is_empty():
		return
	var j := lst.find(op_sel)
	_op_select(lst[clampi(j + d, 0, lst.size() - 1)] if j >= 0 else lst[0])


func _op_select(n: int) -> void:
	if n == op_sel or n < 0 or n >= op_defs.size():
		return
	op_prev_sel = op_sel
	op_sel = n
	op_sw_t = t
	op_skill = _op_default_skill()
	Sfx.play("ui_move")
	_op_follow()


func _op_set_tab(i: int) -> void:
	i = posmod(i, OP_TABS.size())
	if i == op_tab:
		return
	op_tab_from = op_tab
	op_tab = i
	op_tab_t = t
	Sfx.play("ui_move")


func _op_skill_step(d: int) -> void:
	if op_tab != 1:
		_op_set_tab(1)
		return
	op_skill = posmod(op_skill + d, 3)
	Sfx.play("ui_move")


func _op_set_filter(c: String) -> void:
	if c == op_filter or _op_class_count(c) == 0:
		return
	op_filter = c
	Sfx.play("ui_move")
	var lst := _op_list()
	if not lst.has(op_sel) and not lst.is_empty():
		op_prev_sel = op_sel
		op_sel = lst[0]
		op_sw_t = t
		op_skill = _op_default_skill()
	op_scroll = 0.0
	_op_follow()


## 职业筛选前后切（跳过没有干员的职业）
func _op_filter_step(d: int) -> void:
	var cs := _op_classes()
	var i := cs.find(op_filter)
	for k in cs.size():
		i = posmod(i + d, cs.size())
		if _op_class_count(cs[i]) > 0:
			_op_set_filter(cs[i])
			return


## 名册滚动上限（设计像素）
func _op_scroll_max() -> float:
	var n := _op_list().size()
	if _touch_mode():
		return maxf(0.0, (ceili(n / 2.0) - 3) * 100.0)
	return maxf(0.0, (n - op_vis) * 90.0)


## 选中项滚进可视区
func _op_follow(instant := false) -> void:
	var lst := _op_list()
	var j := maxi(0, lst.find(op_sel))
	var ph := _touch_mode()
	var step := 100.0 if ph else 90.0
	var pos: float = float(j / 2) if ph else float(j)
	var vis: int = 3 if ph else op_vis
	var s := op_scroll / step
	if pos < s:
		s = pos
	elif pos > s + vis - 1:
		s = pos - vis + 1
	op_scroll = clampf(s * step, 0.0, _op_scroll_max())
	if instant:
		op_scroll_f = op_scroll


func _op_page(d: int) -> void:
	var ph := _touch_mode()
	op_scroll = clampf(op_scroll + d * (2.0 * 100.0 if ph else (op_vis - 1) * 90.0), 0.0, _op_scroll_max())
	Sfx.play("ui_move")


func _op_back() -> void:
	if transition.busy:
		return
	transition.switch_page(func(): op_pick = false)
	Sfx.play("ui_move")


func _op_go() -> void:
	if transition.busy or op_defs.is_empty() or op_press_t >= 0.0:
		return
	var cid: String = op_defs[op_sel].id
	Sfx.play("ui_ok")
	if cover_pick:
		transition.switch_page(func():
			Cfg.cover_character_id = cid
			Cfg.save()
			if title_bg.has_method("reload_guest"):
				title_bg.reload_guest()   # 旧沙滩封面；深海水母版不画封面干员（10-24）
			op_pick = false)
	else:
		# 出击：按钮下沉 + 闪白 160 ms，140 ms 起深海浪幕 700 ms，过半换到难度页（浪幕期间锁输入，同页面切换）
		op_go_id = cid
		op_press_t = t
		op_wipe_t = t + (0.0 if Cfg.reduce_motion else 0.14)
		op_wipe_swapped = false
		transition._lock()


## 每帧：排版缩放、悬停、平滑滚动、子层位置 / 透明度、浪幕进度（_process 调）
func _op_tick(delta: float) -> void:
	var vs := size
	var ph := _touch_mode()
	var dsz := OP_PHONE if ph else OP_DESK
	op_k = minf(vs.x / dsz.x, vs.y / dsz.y)
	op_off = ((vs - dsz * op_k) / 2.0).round()
	if not op_dragging:
		op_scroll_f = op_scroll if Cfg.reduce_motion else lerpf(op_scroll_f, op_scroll, 1.0 - exp(-14.0 * delta))
		if absf(op_scroll_f - op_scroll) < 0.2:
			op_scroll_f = op_scroll
	# 悬停：120 ms 抬 4 px（触屏不认悬停）
	var hov := -1
	if op_pick and not ph and op_press_t < 0.0:
		var mp := _op_design(get_local_mouse_position())
		for k in op_rects:
			if k is int and op_rects[k].has_point(mp):
				hov = k
	for i in op_defs.size():
		var target := 1.0 if (i == hov and i != op_sel) else 0.0
		var cur: float = op_hover.get(i, 0.0)
		if cur != target:
			op_hover[i] = target if Cfg.reduce_motion else move_toward(cur, target, delta / 0.12)
	# 子层：信息面板（打开时从右 340 px 滑入）+ 正文（换干员 60 px 滑入、换页签淡出）
	op_panel.visible = op_pick
	op_body.visible = op_pick
	if op_pick:
		var op_open := UI.ease_out(_op_p(op_open_t, 0.0, 0.3))
		op_panel.position = op_off + Vector2(340.0 * (1.0 - op_open) * op_k, 0.0)
		op_panel.scale = Vector2(op_k, op_k)
		op_panel.modulate.a = _op_a(op_open_t, 0.0, OP_FADE) if Cfg.reduce_motion else minf(1.0, op_open * 2.0)
		var m := _op_body_motion()
		op_body.position = Vector2(m.dx, 0.0)
		op_body.modulate.a = m.alpha
		op_panel.queue_redraw()
		op_body.queue_redraw()
	# 浪幕：过半换到难度页，结束解锁
	op_wipe_layer.visible = op_wipe_t >= 0.0 and t >= op_wipe_t
	if op_wipe_t >= 0.0 and t >= op_wipe_t:
		var e := (t - op_wipe_t) / _op_wipe_len()
		if e >= 0.5 and not op_wipe_swapped:
			op_wipe_swapped = true
			Cfg.character_id = op_go_id
			Cfg.save()
			op_pick = false
			diff_pick = true
			diff_sel = clampi(Cfg.difficulty, 0, Cfg.diff_unlocked)
		if e >= 1.0:
			op_wipe_t = -1.0
			op_press_t = -1.0
			op_wipe_layer.visible = false
			transition._unlock()
		op_wipe_layer.queue_redraw()


func _op_wipe_len() -> float:
	return OP_FADE * 2.0 if Cfg.reduce_motion else 0.7


func _draw_op_wipe() -> void:
	if op_wipe_t < 0.0:
		return
	var e := clampf((t - op_wipe_t) / _op_wipe_len(), 0.0, 1.0)
	if Cfg.reduce_motion:
		# 减少动态效果：不画浪，只做 120 ms 压暗 → 换页 → 120 ms 亮回
		op_wipe_layer.draw_rect(Rect2(Vector2.ZERO, size), Color(0.039, 0.102, 0.173, 1.0 - absf(e - 0.5) * 2.0))
		return
	UI.wave_wipe(op_wipe_layer, size, UI.ease_io(e))


## 面板正文的动效状态：最近一次是换页签 → 旧页 100 ms 淡出、新页三行错开 60 ms 从右 40 px 滑入；否则按换干员（120 ms 后 260 ms 滑入 60 px）
func _op_body_motion() -> Dictionary:
	var m := {"tab": op_tab, "tabpos": float(op_tab), "dx": 0.0, "alpha": 1.0, "rows": [1.0, 1.0, 1.0], "cnt": 1.0}
	if op_tab_t > op_sw_t:
		var q := op_tab_t
		m.tabpos = lerpf(float(op_tab_from), float(op_tab), UI.ease_out(_op_p(q, 0.0, 0.2)))
		if not Cfg.reduce_motion and t - q < 0.1:
			m.tab = op_tab_from
			m.alpha = 1.0 - (t - q) / 0.1
		else:
			m.alpha = _op_a(q, 0.0, 0.0) if Cfg.reduce_motion else 1.0
			m.rows = [_op_p(q, 0.1, 0.25), _op_p(q, 0.16, 0.25), _op_p(q, 0.22, 0.25)]
			m.cnt = UI.ease_out(_op_p(q, 0.1, 0.4))
	else:
		var s := op_sw_t
		var pp := _op_p(s, 0.12, 0.26)
		m.dx = 60.0 * (1.0 - UI.ease_out(pp))
		m.alpha = _op_a(s, 0.0, 0.0) if Cfg.reduce_motion else minf(1.0, pp * 1.5)
		m.rows = [_op_p(s, 0.12, 0.26), _op_p(s, 0.18, 0.26), _op_p(s, 0.24, 0.26)]
		m.cnt = UI.ease_out(_op_p(s, 0.12, 0.45))
	return m


## 名册卡抬起：选中 220 ms ease-out back，旧选中 160 ms 落回
func _op_lift(i: int) -> float:
	if i == op_sel:
		return 1.0 if Cfg.reduce_motion else UI.ease_back((t - op_sw_t) / 0.22)
	if i == op_prev_sel:
		return 0.0 if Cfg.reduce_motion else 1.0 - UI.ease_out((t - op_sw_t) / 0.16)
	return 0.0


## 帧内非透明区（各待机帧的并集，立绘按它对齐、不抖）+ 白色剪影（立绘外晕用）；第一次画到时算，读不到图（无头）就用整帧
func _op_art(od: Dictionary) -> void:
	if od.has("bb"):
		return
	var tx: Texture2D = od.tex
	od.sil = null
	if tx == null:
		od.bb = Rect2()
		return
	var fw: int = tx.get_width() / int(od.frames)
	od.bb = Rect2(0, 0, fw, tx.get_height())
	var img := tx.get_image()
	if img == null or img.is_empty():
		return
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var u := Rect2i()
	for f in int(od.frames):
		var r := img.get_region(Rect2i(f * fw, 0, fw, img.get_height())).get_used_rect()
		if r.size.x > 0:
			u = r if u.size.x == 0 else u.merge(r)
	if u.size.x > 0:
		od.bb = Rect2(u)
	var white := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	var sil := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	sil.blit_rect_mask(white, img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
	od.sil = ImageTexture.create_from_image(sil)


## 选人页（B+）：背景铺满界面，其余按设计稿坐标画（draw_set_transform 缩放）
func _draw_op_pick(vs: Vector2) -> void:
	if op_defs.is_empty():
		return
	_op_backdrop(vs)
	draw_set_transform(op_off, 0.0, Vector2(op_k, op_k))
	op_rects.clear()
	var od: Dictionary = op_defs[op_sel]
	_op_art(od)
	if _touch_mode():
		_op_draw_phone(od)
	else:
		_op_draw_desk(od)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 背景：深海青 → 深紫斜向渐变 + 青色柔光 + 下方浪纹 + 两侧触须剪影 + 灯火暖光点（docs/58 §7 B）
func _op_backdrop(vs: Vector2) -> void:
	if op_bg.get("vs", Vector2.ZERO) != vs:
		_op_bg_build(vs)
	var c0 := Color(6 / 255.0, 30 / 255.0, 40 / 255.0)
	var c1 := Color(30 / 255.0, 14 / 255.0, 52 / 255.0)
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(vs.x, 0), vs, Vector2(0, vs.y)]),
		PackedColorArray([c0.lerp(c1, 0.45), c1, c0.lerp(c1, 0.55), c0]))
	var gc := Vector2(vs.x * 0.62, vs.y * 0.45)
	var gr := vs.y * 0.7
	draw_texture_rect(op_glow_tex, Rect2(gc - Vector2(gr, gr), Vector2(gr, gr) * 2.0), false, Color(90 / 255.0, 200 / 255.0, 220 / 255.0, 0.3))
	var ph := 0.0 if Cfg.reduce_motion else t * 0.4
	for k in 9:
		var yb := vs.y * 0.55 + k * 26.0
		var pts := PackedVector2Array()
		var x := 0.0
		while x <= vs.x + 10.0:
			pts.append(Vector2(x, yb + 6.0 * sin(x / 70.0 + k * 1.3 + ph)))
			x += 10.0
		draw_polyline(pts, Color(140 / 255.0, 230 / 255.0, 240 / 255.0, (14.0 + k) / 255.0), 1.0, true)
	for sg in op_bg.tent:
		draw_line(sg[0], sg[1], Color(120 / 255.0, 80 / 255.0, 200 / 255.0, 0.1), sg[2])
	var drift := 0.0 if Cfg.reduce_motion else t * 6.0
	for mo in op_bg.motes:
		var p: Vector2 = mo[0]
		p.y = fposmod(p.y - drift * mo[3], vs.y + 20.0) - 10.0
		draw_circle(p, mo[1], Color(1.0, 220 / 255.0, 150 / 255.0, mo[2]))


func _op_bg_build(vs: Vector2) -> void:
	var rng := RandomNumberGenerator.new()   # 界面装饰：固定种子的本地 RNG（不是 g.rng）
	rng.seed = 3
	var tent: Array = []
	for side in 2:
		for i in 4:
			var x: float = rng.randf_range(-40, 160) if side == 0 else vs.x - rng.randf_range(-40, 160)
			var ang: float = -PI / 2.0 + (0.35 if side == 0 else -0.35) + rng.randf_range(-0.3, 0.3)
			var wdt: float = rng.randf_range(14, 22)
			var length: float = rng.randf_range(260, 460)
			var phs: float = rng.randf_range(0, 6)
			var prev := Vector2(x, vs.y + 20.0)
			var s := 0.0
			while s < length:
				var a: float = ang + 0.5 * sin(s / 60.0 + phs) * (s / length)
				var nx := prev + Vector2.from_angle(a) * 6.0
				tent.append([prev, nx, maxf(1.0, wdt * (1.0 - s / length))])
				prev = nx
				s += 6.0
	var motes: Array = []
	for i in 60:
		motes.append([Vector2(rng.randf_range(0, vs.x), rng.randf_range(0, vs.y)), [1.0, 1.0, 2.0][rng.randi_range(0, 2)], rng.randf_range(30, 90) / 255.0, rng.randf_range(0.5, 1.5)])
	op_bg = {"vs": vs, "tent": tent, "motes": motes}


## 立绘：待机帧（帧内非透明区并集）整数倍最近邻放大，底部 28 % 渐隐；换干员 60 ms 后 300 ms 缩放 0.92 → 1、右移 24 → 0、淡入，青白外晕随透明度出现
## foot = 脚底中点（ci 的坐标），k2 = 相对 @2x 像素的整数倍（_op_fit 算）
## clip = 舞台框：每一次贴图都裁进框里（缩放进入 / 右移 24 px / 外晕都不会画出框，兜底）
func _op_char(ci: CanvasItem, od: Dictionary, foot: Vector2, k2: float, clip: Rect2) -> void:
	var tx: Texture2D = od.tex
	if tx == null:
		return
	var c := UI.ease_out(_op_p(op_sw_t, 0.06, 0.3))
	var a := _op_a(op_sw_t, 0.06, 0.3) if Cfg.reduce_motion else c
	if a <= 0.0:
		return
	var bb: Rect2 = od.bb
	var fw: float = tx.get_width() / float(od.frames)
	var fr: int = int(t * 4.0) % int(od.frames)
	var k: float = k2 * 2.0 / float(od.hires) * float(od.get("ds", 1.0)) * (0.92 + 0.08 * c)
	var sz := bb.size * k
	var pos := UI.foot_pos(foot, bb, fw, tx.get_height(), float(od.hires), k) + Vector2(24.0 * (1.0 - c), 0.0)   # 脚底点对齐（10-21 水月）
	var src := Rect2(fw * fr + bb.position.x, bb.position.y, bb.size.x, bb.size.y)
	var cut := floorf(bb.size.y * 0.72)
	if od.sil != null:
		var gsrc := Rect2(src.position, Vector2(src.size.x, cut))
		for ring in [4.0 * k2 / 5.0, 8.0 * k2 / 5.0, 12.0 * k2 / 5.0]:
			for d in 8:
				var dv: Vector2 = Vector2.from_angle(TAU * d / 8.0) * ring
				UI.blit_clipped(ci, od.sil, Rect2(pos + dv, Vector2(sz.x, cut * k)), gsrc, clip, Color(150 / 255.0, 220 / 255.0, 240 / 255.0, (0.03 if ring < 6.0 else 0.018) * a))
	UI.blit_clipped(ci, tx, Rect2(pos, Vector2(sz.x, cut * k)), Rect2(src.position, Vector2(src.size.x, cut)), clip, Color(1, 1, 1, a))
	var rows: int = int(bb.size.y - cut)
	for y in rows:
		var f := 1.0 - (y + 0.5) / float(rows)
		UI.blit_clipped(ci, tx, Rect2(pos + Vector2(0, (cut + y) * k), Vector2(sz.x, k)), Rect2(src.position + Vector2(0, cut + y), Vector2(src.size.x, 1)), clip, Color(1, 1, 1, a * f))


## 换干员：新色带从左扫入盖住旧色带（380 ms）；减少动态效果时两带 120 ms 交叉淡化
func _op_band(h: float, ox: float, sc: float, col: Color) -> void:
	var prev := Color(0, 0, 0, 0)
	if op_prev_sel >= 0 and op_prev_sel < op_defs.size():
		prev = op_defs[op_prev_sel].col
	if Cfg.reduce_motion:
		var f := _op_a(op_sw_t, 0.0, 0.0)
		if f < 1.0 and prev.a > 0.0:
			UI.class_band(self, h, ox, sc, prev, Color(0, 0, 0, 0), 1.0, 0.35, true, 1.0 - f)
		UI.class_band(self, h, ox, sc, col, Color(0, 0, 0, 0), 1.0, 0.35, true, f)
		return
	UI.class_band(self, h, ox, sc, col, prev, _op_p(op_sw_t, 0.0, 0.38))


## 英文名打字机（换干员 80 ms 后 420 ms 逐字）与中文名淡入
func _op_name_frac() -> float:
	return _op_p(op_sw_t, 0.08, 0.42)


func _op_name_alpha() -> float:
	return _op_a(op_sw_t, 0.0, 0.0) if Cfg.reduce_motion else minf(1.0, _op_name_frac() * 1.6)


## 渐隐的紫色横线（顶栏底、名册带顶）
func _op_hline(y: float, w: float) -> void:
	var cl := Color(UI.PURPLE.r, UI.PURPLE.g, UI.PURPLE.b, 0.0)
	draw_polyline_colors(PackedVector2Array([Vector2(0, y), Vector2(w / 2.0, y), Vector2(w, y)]), PackedColorArray([cl, Color(cl.r, cl.g, cl.b, 0.43), cl]), 1.0)


func _op_btn(r: Rect2, s: String, size := 12) -> void:
	var hot := r.has_point(_op_design(get_local_mouse_position())) and not _touch_mode()
	UI.bpanel(self, r, false, hot, 1.0, UI.CYAN)
	UI.text_at(self, font, r.get_center(), s, size, UI.TEXT, "mm")


func _op_deploy(r: Rect2, size: int, sub: String) -> void:
	var br := 0.5 if Cfg.reduce_motion else 0.5 + 0.5 * sin(t * TAU / 1.6)
	var p := 0.0
	if op_press_t >= 0.0:
		p = clampf((t - op_press_t) / (OP_FADE if Cfg.reduce_motion else 0.16), 0.0, 1.0)
	UI.deploy_button(self, font, r, "更换  ›" if cover_pick else "出击  ›", sub, br, p, size, 1.0, 0.0 if Cfg.reduce_motion else 3.0)
	op_rects["go"] = r.grow(6.0)


## 桌面版式（1280×720 设计稿 = final_select_Bplus.png）
func _op_draw_desk(od: Dictionary) -> void:
	var W := OP_DESK.x
	var H := OP_DESK.y
	var col: Color = od.col
	var d: Dictionary = od.def
	_op_band(H, 0.0, 1.0, col)
	# 立绘缩小时：脚底略上提、描边英文名同比缩小并下移，仍压在立绘上半身后面
	var ar := op_art_k / 5.0
	UI.ghost_name(self, font, Vector2(380 + (1.0 - ar) * 60.0, 78 + (1.0 - ar) * 150.0), od.en, _op_name_frac(), int(round(150 * (0.5 + 0.5 * ar))))
	_op_draw_art(od)
	# 顶栏：节点标签条式标题 + 说明 + 难度 / 封面标签 + 返回
	draw_rect(Rect2(0, 0, W, 54), Color(4 / 255.0, 8 / 255.0, 18 / 255.0, 0.55))
	_op_hline(54.5, W)
	UI.rbox(self, Rect2(16, 12, 150, 30), 3, UI.VIOLET)
	UI.en(self, font, Vector2(26, 19 + UI.cond(font, true).get_ascent(11)), "OPERATOR SELECT", 11, Color.WHITE, 2.0, true)
	UI.diamond(self, Vector2(16, 27), 5.0, UI.B_ACC)
	var tw := UI.text_at(self, font, Vector2(182, 27), "更换封面干员" if cover_pick else "选择开局干员", 20, UI.TEXT, "lm")
	var sx := 182.0 + tw + 20.0
	if cover_pick:
		UI.text_at(self, font, Vector2(sx, 14), "显示在标题页上的干员", 12, UI.B_SUB)
		UI.text_at(self, font, Vector2(sx, 30), "不改变开局编队", 11, UI.B_SUB)
	else:
		UI.text_at(self, font, Vector2(sx, 14), "队长 1 名；其余干员在探索中通过升级招募", 12, UI.B_SUB)
		UI.text_at(self, font, Vector2(sx, 30), "下一步：选择难度", 11, UI.B_SUB)
	var back := Rect2(W - 120, 14, 104, 28)
	_op_btn(back, "返回")
	UI.btn_key(self, font, back, "" if Pad.using else "ESC", UI.B_SUB, 9, 8.0)   # 10-31 TA H7：键名不夹在按钮文字里
	op_rects["back"] = back.grow(4.0)
	var px := W - 136.0
	if _cover_name_id != Cfg.cover_character_id:
		_cover_name_id = Cfg.cover_character_id   # 每帧读盘解析 JSON 只为一个名字（10-25 帧率审计）：封面干员变了才重读
		_cover_name = Character.load_def(_cover_name_id).get("name", _cover_name_id) if _cover_name_id != "" else ""
	var cover_name: String = _cover_name
	for chip in [["封面干员 " + cover_name, UI.PURPLE], ["难度 " + str(D.DIFF_PRESETS[clampi(Cfg.difficulty, 0, D.DIFF_PRESETS.size() - 1)].name), UI.STEEL]]:
		if chip[0].ends_with(" "):
			continue
		px -= UI.pill_width(font, chip[0], 11)
		UI.pill(self, font, Vector2(px, 18), chip[0], chip[1], 11)
		px -= 6.0
	# 左：职业筛选轨（全部 + 8 职业；没有干员的职业变暗、不可选）
	var cs := _op_classes()
	var rx0 := 14.0
	var ry0 := 68.0
	var step := 46.0
	UI.rbox(self, Rect2(rx0, ry0, 44, cs.size() * step + 12), 22, UI.B_FILL, UI.B_LINE)
	for i in cs.size():
		var c: String = cs[i]
		var cy := ry0 + 28.0 + i * step
		var on := c == op_filter
		var n := _op_class_count(c)
		var dim := 1.0 if n > 0 else 0.35
		if on:
			UI.rbox(self, Rect2(rx0 + 4, cy - 19, 36, 38), 18, UI.VIOLET)
		var gc := Color.WHITE if on else UI.fa(Color(200 / 255.0, 205 / 255.0, 225 / 255.0), dim)
		if c == "":
			UI.text_at(self, font, Vector2(rx0 + 22, cy), "全", 13, UI.TEXT, "mm")
		else:
			UI.class_glyph(self, c, Vector2(rx0 + 22, cy - 4), 8.0, gc)
			UI.text_at(self, font, Vector2(rx0 + 22, cy + 12), c, 9, gc if on else UI.fa(UI.B_SUB, dim), "mm")
		if n > 0:
			op_rects["cls:" + c] = Rect2(rx0, cy - 22, 44, 44)
	# 名字块：微型代码 + 中文名 + 英文名（打字机）+ 圆角标签 + 一句定位
	var na := _op_name_alpha()
	UI.code(self, font, Vector2(92, 282), "No.%02d  //  %s  //  %s" % [op_sel + 1, od.cls, "近战" if od.melee else "远程"], 9)
	if na > 0.0:
		var nf := UI.fit_line(font, od.name, 44, 470.0, 28)
		UI.text_at(self, font, Vector2(90, 296), nf[0], nf[1], UI.fa(UI.TEXT, na), "la", true)
		var en_s: String = od.en
		en_s = en_s.substr(0, int(round(en_s.length() * clampf(_op_name_frac(), 0.0, 1.0))))
		UI.en(self, font, Vector2(94, 350 + UI.cond(font, true).get_ascent(14)), en_s, 14, UI.fa(col, na), 4.0, true)
	var cx := 92.0
	cx += UI.pill(self, font, Vector2(cx, 376), od.cls, col, 12)
	for tg in d.get("gallery", {}).get("tags", []):
		if cx + UI.pill_width(font, tg, 11) > 600.0:
			break
		cx += UI.pill(self, font, Vector2(cx, 376), tg, UI.PURPLE, 11)
	var desc: String = d.get("gallery", {}).get("desc", "")
	if desc != "":
		var fl := UI.fit_line(font, desc, 12, 500.0, 10)
		UI.text_at(self, font, Vector2(92, 406), fl[0], fl[1], UI.B_SUB)
	# 编队条：主控 + 两个队友位（封面模式只画封面位）
	UI.btab(self, font, Vector2(92, 440), "封面" if cover_pick else "编队", Color(90 / 255.0, 70 / 255.0, 190 / 255.0), 9)
	for i in (1 if cover_pick else 3):
		var r := Rect2(92 + i * 94, 460, 84, 56)
		if i == 0:
			UI.bpanel(self, r, true, true, 1.0, UI.VIOLET)
			_op_mini(od, Rect2(r.position.x + 2, r.position.y + 2, 46, r.size.y - 4))
			UI.rbox(self, Rect2(r.position.x + 2, r.position.y + 2, 32, 13), 3, UI.VIOLET)
			UI.text_at(self, font, Vector2(r.position.x + 18, r.position.y + 8.5), "封面" if cover_pick else "队长", 10, Color.WHITE, "mm")
			var mf := UI.fit_line(font, od.name, 10, 42.0, 8)
			UI.text_at(self, font, Vector2(r.position.x + 62, r.position.y + 34), mf[0], mf[1], UI.TEXT, "mm")
		else:
			UI.bpanel(self, r)
			UI.text_at(self, font, Vector2(r.position.x + 42, r.position.y + 22), "队友 %d" % i, 11, UI.B_SUB, "mm")
			UI.text_at(self, font, Vector2(r.position.x + 42, r.position.y + 40), "探索中招募", 9, UI.B_SUB, "mm")
	if cover_pick:
		UI.text_at(self, font, Vector2(190, 488), "封面不改变开局编队", 11, UI.B_SUB, "lm")
	# 名册带
	var rb := H - 170.0
	draw_rect(Rect2(0, rb - 6, W, H - rb + 6), Color(4 / 255.0, 8 / 255.0, 18 / 255.0, 0.63))
	_op_hline(rb - 6, W)
	var lst := _op_list()
	UI.code(self, font, Vector2(70, rb - 1), "ROSTER  %d / %d   //   %s" % [lst.size(), op_defs.size(), "SORT: CLASS" if op_filter == "" else "CLASS: " + op_filter], 8)
	UI.text_at(self, font, Vector2(1258, rb - 2), Pad.hint("◀ ▶ / 滚轮 切换    ↑↓ 页签    Q / E 职业    Enter 下一步", "◀ ▶ 切换    ↑↓ 页签    LB / RB 职业    Ⓐ 下一步", "点卡片切换 · 再点一次出击"), 10, UI.B_SUB, "ra")
	var gx := 70.0
	var go := Rect2(1036, rb + 40, W - 22 - 1036, 72)
	op_vis = maxi(1, int((go.position.x - 24.0 - gx) / 90.0))
	var lim := gx + (op_vis - 1) * 90.0
	var first := -1
	var last := -1
	for j in lst.size():
		var i: int = lst[j]
		var x := gx + j * 90.0 - op_scroll_f
		var over := maxf(gx - x, x - lim)
		var a := clampf(1.0 - over / 60.0, 0.0, 1.0)
		if a <= 0.01:
			continue
		var o: Dictionary = op_defs[i]
		var r := Rect2(x, rb + 22, 82, 112)
		if a > 0.6:
			op_rects[i] = r
			if first < 0:
				first = j
			last = j
		var lift := _op_lift(i)
		UI.roster_card(self, font, r, o, lift, op_hover.get(i, 0.0), o.elite if i == op_sel else 0, int(t * 4.0 + i) % int(o.frames), a)
	if last >= 0 and last < lst.size() - 1:
		var mx := lim + 90.0 + 6.0
		UI.text_at(self, font, Vector2(mx, rb + 70), "▶", 16, UI.B_SUB)
		UI.text_at(self, font, Vector2(mx, rb + 92), "还有 %d 名" % (lst.size() - 1 - last), 10, UI.B_SUB)
		op_rects["more_r"] = Rect2(mx - 6, rb + 50, 60, 70)
	if first > 0:
		UI.text_at(self, font, Vector2(40, rb + 70), "◀", 16, UI.B_SUB, "ma")
		UI.text_at(self, font, Vector2(40, rb + 92), "%d 名" % first, 10, UI.B_SUB, "ma")
		op_rects["more_l"] = Rect2(14, rb + 50, 54, 70)
	_op_deploy(go, 24, ("设为封面干员" if cover_pick else Pad.hint("ENTER  ·  下一步选择难度", "手柄 Ⓐ  ·  下一步选择难度", "下一步选择难度")))


## 手机版式（740×360 设计稿 = final_phone_select_Bplus.png）：左手拇指区两列名册（上滑翻页），右手拇指区页签 + 紧凑技能行 + 出击
func _op_draw_phone(od: Dictionary) -> void:
	var W := OP_PHONE.x
	var H := OP_PHONE.y
	var col: Color = od.col
	_op_band(H, -150.0, 0.6, col)
	var ar := op_art_k / 5.0
	UI.ghost_name(self, font, Vector2(150 + (1.0 - ar) * 40.0, 40 + (1.0 - ar) * 70.0), od.en, _op_name_frac(), int(round(90 * (0.5 + 0.5 * ar))), Color(0.745, 0.824, 1.0, 0.18), 2)
	_op_draw_art(od)
	UI.rbox(self, Rect2(8, 6, 142, 22), 3, UI.VIOLET)
	UI.text_at(self, font, Vector2(16, 17), "更换封面干员" if cover_pick else "选择开局干员", 13, Color.WHITE, "lm")
	var back := Rect2(W - 66, 6, 56, 22)
	_op_btn(back, "返回")
	op_rects["back"] = Rect2(W - 80, 0, 80, 40)
	# 职业筛选（顶栏中段一排小胶囊；点击区放大到 46×38）
	var cs := _op_classes()
	for i in cs.size():
		var c: String = cs[i]
		var x := 160.0 + i * 54.0
		var on := c == op_filter
		var n := _op_class_count(c)
		var dim := 1.0 if n > 0 else 0.35
		var r := Rect2(x, 6, 50, 22)
		UI.rbox(self, r, 11, UI.VIOLET if on else UI.B_FILL, Color(0, 0, 0, 0) if on else UI.fa(UI.B_LINE, dim))
		var gc := Color.WHITE if on else UI.fa(Color(200 / 255.0, 205 / 255.0, 225 / 255.0), dim)
		if c == "":
			UI.text_at(self, font, r.get_center(), "全部", 10, gc, "mm")
		else:
			UI.class_glyph(self, c, Vector2(x + 11, 17), 5.0, gc, 1.5)
			UI.text_at(self, font, Vector2(x + 33, 17), c, 10, gc, "mm")
		if n > 0:
			op_rects["cls:" + c] = Rect2(x - 2, 0, 54, 40)
	# 名册：两列竖排，上滑翻页
	var lst := _op_list()
	var top := 40.0
	var bot := 340.0
	var more := 0
	for j in lst.size():
		var i: int = lst[j]
		var x := 10.0 + (j % 2) * 68.0
		var y := top + (j / 2) * 100.0 - op_scroll_f
		var over := maxf(top - y, (y + 88.0) - bot)
		var a := clampf(1.0 - over / 40.0, 0.0, 1.0)
		if y + 88.0 > bot + 1.0:
			more += 1
		if a <= 0.01:
			continue
		var o: Dictionary = op_defs[i]
		var r := Rect2(x, y, 62, 88)
		if a > 0.6:
			op_rects[i] = r
		UI.roster_card(self, font, r, o, _op_lift(i), 0.0, o.elite if i == op_sel else 0, int(t * 4.0 + i) % int(o.frames), a, 12)
	if more > 0:
		UI.code(self, font, Vector2(74, H - 12), "SWIPE  +%d" % more, 7, UI.B_SUB, "ma")
	# 名字块（压在立绘左边）
	var na := _op_name_alpha()
	if na > 0.0:
		var nf := UI.fit_line(font, od.name, 30, 300.0, 20)
		UI.text_at(self, font, Vector2(152, 206), nf[0], nf[1], UI.fa(UI.TEXT, na), "la", true)
		var en_s: String = od.en
		en_s = en_s.substr(0, int(round(en_s.length() * clampf(_op_name_frac(), 0.0, 1.0))))
		UI.en(self, font, Vector2(154, 244 + UI.cond(font, true).get_ascent(10)), en_s, 10, UI.fa(col, na), 4.0, true)
	var cx := 152.0
	cx += UI.pill(self, font, Vector2(cx, 262), od.cls, col, 10)
	var tags: Array = od.def.get("gallery", {}).get("tags", [])
	if not tags.is_empty():
		UI.pill(self, font, Vector2(cx, 262), tags[0], UI.PURPLE, 10)
	_op_deploy(Rect2(W - 200, H - 62, 186, 48), 18, "")


## 编队位里的小像：@2x 像素 1:1（整数倍、不糊），头顶对齐框顶 + 2，画成半身像——超出框的下半身 / 左右裁掉，不出框
func _op_mini(od: Dictionary, box: Rect2) -> void:
	var tx: Texture2D = od.tex
	if tx == null:
		return
	_op_art(od)
	var bb: Rect2 = od.bb
	var fw: float = tx.get_width() / float(od.frames)
	var s: float = 2.0 / float(od.hires)
	var fr: int = int(t * 4.0) % int(od.frames)
	var dst := Rect2(box.get_center().x - bb.size.x * s / 2.0, box.position.y + 2.0, bb.size.x * s, bb.size.y * s)
	UI.blit_clipped(self, tx, dst, Rect2(fw * fr + bb.position.x, bb.position.y, bb.size.x, bb.size.y), box)


## 立绘舞台（设计坐标）：顶栏以下、名册带以上、信息面板以左；手机：名册列以右、信息面板以左
func _op_stage_rect() -> Rect2:
	if _touch_mode():
		return Rect2(146, 34, 462 - 146, OP_PHONE.y - 4 - 34)
	return Rect2(600, 56, 962 - 600, 544 - 56)


## 立绘适配：在舞台里（四边留 margin）取 ≤ 上限的最大整数倍，使待机帧并集区整个放得下；返回 [倍数（@2x 像素）, 脚底中点]
## 上限：桌面 op_art_k（4），手机 op_art_k × 0.6 取整（2）；中心先放在设计稿位置，放不下再往舞台里挪
func _op_fit(od: Dictionary, ph: bool) -> Array:
	_op_art(od)
	var sr := _op_stage_rect()
	var m := 8.0
	var bb: Rect2 = od.bb
	var hi: float = float(od.get("hires", 1.0))
	var w2: float = maxf(bb.size.x * 2.0 / hi, UI.CARD_REF.x)   # 全员统一参考尺寸取倍数（10-21 用户：每人一样大）；整幅仍须在舞台内（full2）
	var h2: float = UI.CARD_REF.y
	var foot_y: float = (312.0 if ph else sr.end.y - m)
	return UI.art_fit(w2, h2, sr, op_art_k * (0.6 if ph else 1.0), 380.0 if ph else 780.0, foot_y, m, bb.size.y * 2.0 / hi)   # 图鉴 C4' 同一规则


## 立绘：适配倍数 + 裁进舞台框（画在描边英文名之后、名字块之前，层次同定稿）
func _op_draw_art(od: Dictionary) -> void:
	var fit := _op_fit(od, _touch_mode())
	_op_char(self, od, fit[1], fit[0], _op_stage_rect())


## 信息面板框 + 页签（子控件 op_panel 画，设计坐标）
func _op_panel_rect() -> Rect2:
	if _touch_mode():
		return Rect2(470, 38, OP_PHONE.x - 10 - 470, OP_PHONE.y - 80 - 38)
	return Rect2(968, 68, OP_DESK.x - 16 - 968, 530 - 68)


func _draw_op_panel() -> void:
	op_prects.clear()
	if not op_pick or op_defs.is_empty():
		return
	var ci := op_panel
	var pr := _op_panel_rect()
	var m := _op_body_motion()
	UI.bpanel(ci, pr, true)
	var trs: Array
	if _touch_mode():
		trs = UI.btabs(ci, font, Rect2(pr.position.x + 2, pr.position.y + 2, pr.size.x - 4, 26), OP_TABS, m.tabpos, 12)
		for i in trs.size():
			op_prects["tab%d" % i] = Rect2(trs[i].position.x, pr.position.y - 8, trs[i].size.x, 44)
	else:
		UI.code(ci, font, pr.position + Vector2(14, 8), "OPERATOR DATA // " + OP_TAB_EN[int(m.tab)], 8)
		trs = UI.btabs(ci, font, Rect2(pr.position.x + 4, pr.position.y + 22, pr.size.x - 8, 32), OP_TABS, m.tabpos, 14)
		for i in trs.size():
			op_prects["tab%d" % i] = trs[i]


## 面板正文（子控件 op_body 画；整体位移 / 透明度由 _op_tick 设）
func _draw_op_body() -> void:
	if not op_pick or op_defs.is_empty():
		return
	var ci := op_body
	var pr := _op_panel_rect()
	var ph := _touch_mode()
	var box := Rect2(pr.position.x + 8, pr.position.y + 34, pr.size.x - 16, pr.size.y - 40) if ph else Rect2(pr.position.x + 12, pr.position.y + 66, pr.size.x - 24, pr.size.y - 76)
	var od: Dictionary = op_defs[op_sel]
	var m := _op_body_motion()
	match int(m.tab):
		0:
			_op_status(ci, box, od, m, ph)
		1:
			_op_skills(ci, box, od, m, ph)
		_:
			_op_squad(ci, box, od, m, ph)


func _op_fmt(v: float, key: String, real := 1.0) -> String:
	if real <= 0.0:
		return "—"
	if key == "cd":
		return "%.2f 秒" % v
	if key == "dps":
		return "%.1f" % v
	if key == "atk" and absf(v - roundf(v)) > 0.05:
		return "%.1f" % v
	return "%d" % int(round(v))


## 属性页（数值表与图鉴「属性」页同源：InitialStats.sheet）：桌面 = 五项大数字 + 量条（满值 = 全体干员该项上限）+ 两列小表 + 定位；
## 手机 = 只有两列小表（版面放不下量条）；底部一行口径说明
func _op_status(ci: CanvasItem, box: Rect2, od: Dictionary, m: Dictionary, ph: bool) -> void:
	var cnt: float = m.cnt
	var v: Dictionary = od.vals
	var sh: Dictionary = od.sheet
	var y := box.position.y
	var small: Array = []
	if ph:
		for r in sh.rows:
			small.append(r)
	else:
		var step := 46.0
		for key in ["atk", "dps", "cd", "reach", "hp"]:
			var r: Dictionary = InitialStats.row(sh, key)
			var val: float = v[key]
			var shown := val * (2.0 - cnt) if key == "cd" else val * cnt
			var lw := UI.btab(ci, font, Vector2(box.position.x, y), r.label, UI.STEEL if key == "hp" else UI.TAB_HP, 9)
			UI.code(ci, font, Vector2(box.position.x + lw + 8, y + 2), r.en, 8)
			var vw := UI.text_at(ci, font, Vector2(box.end.x, y - 4), _op_fmt(shown, key, val), 22, UI.TEXT, "ra", true)
			if str(r.sub) != "":
				UI.text_at(ci, font, Vector2(box.end.x - vw - 6, y + 4), r.sub, 10, UI.B_SUB, "ra")
			UI.gauge(ci, Rect2(box.position.x, y + 25, box.size.x - 110.0, 8), val / float(op_max[key]) * cnt, UI.TEXT if key == "hp" else UI.CYAN)
			y += step
		for r in sh.rows:
			if not r.key in ["atk", "dps", "cd", "reach", "hp"]:
				small.append(r)
		y += 2.0
	small.append_array(sh.extra)
	ci.draw_line(Vector2(box.position.x, y), Vector2(box.end.x, y), UI.B_LINE, 1.0)
	y += 6.0 if ph else 8.0
	var lh := 21.0 if ph else 22.0
	var cw := (box.size.x - 10.0) / 2.0
	for i in small.size():
		var r: Dictionary = small[i]
		var cx := box.position.x + (i % 2) * (cw + 10.0)
		var cy := y + (i / 2) * lh
		var lbl: String = r.label
		var lsz := 10 if ph else 11
		var lwid := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, lsz).x
		UI.text_at(ci, font, Vector2(cx, cy + 2), lbl, lsz, UI.B_SUB)
		var txt: String = r.text
		if ph and str(r.sub) != "" and r.key == "atk":
			txt += " " + str(r.sub)
		var fl := UI.fit_line(font, txt, 12 if ph else 13, cw - lwid - 6.0, 9)
		UI.text_at(ci, font, Vector2(cx + cw, cy), fl[0], fl[1], UI.TEXT, "ra")
		ci.draw_line(Vector2(cx, cy + lh - 3), Vector2(cx + cw, cy + lh - 3), Color(UI.B_LINE.r, UI.B_LINE.g, UI.B_LINE.b, 0.35), 1.0)
	y += ceili(small.size() / 2.0) * lh + 4.0
	var tags: Array = sh.tags
	if not tags.is_empty() and y + 22.0 < box.end.y - 12.0:
		var tx := box.position.x + UI.btab(ci, font, Vector2(box.position.x, y + 3), "定位", UI.TAB_HP, 9) + 8.0
		for c in tags:
			var pw := UI.pill_width(font, str(c), 10)
			if tx + pw > box.end.x + 6.0:
				break
			tx += UI.pill(ci, font, Vector2(tx, y), str(c), UI.PURPLE, 10)
		y += 24.0
	var desc: String = od.def.get("attack", {}).get("desc", "")
	if not ph and desc != "" and y + 42.0 < box.end.y - 12.0:
		UI.code(ci, font, Vector2(box.position.x, y), "TRAIT // 特性", 8)
		var f := UI.fit(font, desc, box.size.x, box.end.y - y - 28.0, [11, 10])
		UI.draw_fit(ci, font, Vector2(box.position.x, y + 14), f, UI.B_SUB)
	UI.text_at(ci, font, Vector2(box.position.x, box.end.y - 12), sh.note, 9, UI.B_SUB)


## 技能页：攻击 / 间隔 / 范围 / 生命小标签头 + 三行技能卡（图标 + 名字 / 英文 + SP 环 + 解锁阶段 + 手动 Q / 自动）+ 展开说明 + 天赋
func _op_skills(ci: CanvasItem, box: Rect2, od: Dictionary, m: Dictionary, ph: bool) -> void:
	var d: Dictionary = od.def
	var cnt: float = m.cnt
	var y := box.position.y
	var col: Color = od.col
	if not ph:
		var v: Dictionary = od.vals
		var stats := [[InitialStats.row(od.sheet, "atk").label, _op_fmt(v.atk * cnt, "atk", v.atk)], ["间隔", _op_fmt(v.cd * (2.0 - cnt), "cd", v.cd)],
			[InitialStats.row(od.sheet, "reach").label, _op_fmt(v.reach * cnt, "reach", v.reach)], ["生命", "队长 %d" % int(round(v.hp * cnt))]]
		var cw := box.size.x / 4.0
		for i in stats.size():
			var sx := box.position.x + 2 + i * cw
			UI.btab(ci, font, Vector2(sx, y), stats[i][0], UI.TAB_HP if i < 3 else UI.STEEL, 9)
			var fl := UI.fit_line(font, stats[i][1], 15, cw - 4.0, 11)
			UI.text_at(ci, font, Vector2(sx, y + 18), fl[0], fl[1], UI.TEXT)
		y += 46.0
		ci.draw_line(Vector2(box.position.x, y), Vector2(box.end.x, y), UI.B_LINE, 1.0)
		y += 10.0
	var sks: Array = d.get("skills", [])
	var rh := 46.0 if ph else 58.0
	var rs := 52.0 if ph else 66.0
	for i in mini(3, sks.size()):
		var rt: float = m.rows[i]
		var ra := UI.ease_out(rt)
		if ra > 0.0:
			_op_skill_row(ci, Rect2(box.position.x + 40.0 * (1.0 - ra), y, box.size.x, rh), od, i, ph, ra)
		op_prects["sk%d" % i] = Rect2(box.position.x, y, box.size.x, rh)
		y += rs
	if sks.size() > op_skill and m.rows[2] >= 1.0:
		var sk: Dictionary = sks[op_skill]
		var txt: String = ("队长按 Q 释放；作为队友自动。" if sk.get("mode", "auto") == "manual" else "") + str(sk.get("desc", ""))
		var room := (box.end.y - y) if ph else maxf(52.0, box.end.y - y - (34.0 if d.has("talent") else 4.0))
		var f := UI.fit(font, txt, box.size.x - 8.0, room, [11, 10] if not ph else [10, 9])
		UI.draw_fit(ci, font, Vector2(box.position.x + 2, y - 2), f, UI.B_SUB)
		y += maxf(54.0, f.h + 10.0)
		if not ph and d.has("talent") and y + 20.0 <= box.end.y:
			var w := UI.pill(ci, font, Vector2(box.position.x + 2, y), "天赋", col, 10)
			var tf := UI.fit_line(font, str(d.talent.get("name", "")) + "  精英一解锁", 12, box.size.x - w - 8.0, 10)
			UI.text_at(ci, font, Vector2(box.position.x + 2 + w, y + 9), tf[0], tf[1], UI.TEXT, "lm")


func _op_skill_row(ci: CanvasItem, r: Rect2, od: Dictionary, i: int, compact: bool, a: float) -> void:
	var sk: Dictionary = od.def.skills[i]
	var manual: bool = sk.get("mode", "auto") == "manual"
	var sel := i == op_skill
	var h := r.size.y
	UI.bpanel(ci, r, false, sel, a, UI.VIOLET)
	var side := 28.0 if compact else 32.0
	var ix := r.position.x + 10.0
	var ic: Texture2D = A.tex(str(sk.get("icon", ""))) if str(sk.get("icon", "")) != "" else null
	if ic != null:
		ci.draw_texture_rect(ic, Rect2(ix, r.position.y + (h - side) / 2.0, side, side), false, Color(1, 1, 1, a))
	ci.draw_rect(Rect2(ix, r.end.y - 12, 14, 10), Color(0, 0, 0, 0.78 * a))
	UI.text_at(ci, font, Vector2(ix + 7, r.end.y - 7), "S%d" % (i + 1), 9, UI.fa(UI.TEXT, a), "mm")
	var tx := ix + side + 10.0
	var rx := r.end.x - 30.0
	var tag_x := rx - (100.0 if manual else 82.0)
	var nf := UI.fit_line(font, str(sk.get("name", "")), 13 if compact else 15, tag_x - tx - 6.0, 10)
	UI.text_at(ci, font, Vector2(tx, r.position.y + 7), nf[0], nf[1], UI.fa(UI.TEXT, a))
	var es: String = str(sk.get("en", ""))
	var esz := 9
	while esz > 6 and UI.en_width(font, es, esz, 1.0) > rx - 24.0 - 64.0 - tx:
		esz -= 1
	UI.en(ci, font, Vector2(tx + 2, r.position.y + (24 if compact else 28) + UI.cond(font, true).get_ascent(esz)), es, esz, UI.fa(UI.B_SUB, a), 1.0, true)
	UI.sp_ring(ci, font, Vector2(rx, r.position.y + h / 2.0 - 2.0), 13.0, 0.72, UI.CYAN if manual else UI.TEXT, "%d" % int(sk.get("sp", 0)), a)
	if manual:
		UI.pill(ci, font, Vector2(tag_x, r.position.y + 6), Pad.hint("手动 Q", "手动 Ⓐ", "手动"), UI.CYAN, 10, true, a)
		UI.text_at(ci, font, Vector2(rx - 24, r.end.y - 16), "队友时自动", 9, UI.fa(UI.B_SUB, a), "ra")
	else:
		UI.pill(ci, font, Vector2(tag_x, r.position.y + 6), "自动", UI.B_SUB, 10, false, a)
		UI.text_at(ci, font, Vector2(rx - 24, r.end.y - 16), OP_STAGE[i], 9, UI.fa(od.col, a), "ra")


## 编队页：主控受击属性 + 编队位（主控 + 两名探索中招募的队友）+ 定位标签 + 精英二条件 + 档案摘录
func _op_squad(ci: CanvasItem, box: Rect2, od: Dictionary, m: Dictionary, ph: bool) -> void:
	var d: Dictionary = od.def
	var y := box.position.y
	var stats: Array = []
	for key in ["hp", "armor", "arts", "regen"]:
		var sr: Dictionary = InitialStats.row(od.sheet, key)
		stats.append([sr.label, sr.text])
	var cw := box.size.x / 4.0
	for i in stats.size():
		var sx := box.position.x + 2 + i * cw
		UI.btab(ci, font, Vector2(sx, y), stats[i][0], UI.VIOLET if i == 0 else UI.TAB_HP, 9)
		var fl := UI.fit_line(font, stats[i][1], 13 if ph else 15, cw - 4.0, 10)
		UI.text_at(ci, font, Vector2(sx, y + 18), fl[0], fl[1], UI.TEXT)
	y += 40.0 if ph else 46.0
	ci.draw_line(Vector2(box.position.x, y), Vector2(box.end.x, y), UI.B_LINE, 1.0)
	y += 8.0 if ph else 10.0
	var sh := 34.0 if ph else 44.0
	for i in (1 if cover_pick else 3):
		var r := Rect2(box.position.x, y, box.size.x, sh)
		var a := UI.ease_out(m.rows[i])
		if a > 0.0:
			r.position.x += 40.0 * (1.0 - a)
			UI.bpanel(ci, r, false, i == 0, a, UI.VIOLET)
			if i == 0:
				var w := UI.btab(ci, font, r.position + Vector2(8, (sh - 14.0) / 2.0), "封面" if cover_pick else "队长", UI.VIOLET, 9, a)
				var nx := r.position.x + 16 + w
				UI.text_at(ci, font, Vector2(nx, r.get_center().y), od.name, 13 if ph else 15, UI.fa(UI.TEXT, a), "lm")
				UI.text_at(ci, font, Vector2(r.end.x - 10, r.get_center().y), "与博士同行" if cover_pick else "由队长承受伤害", 10, UI.fa(UI.B_SUB, a), "rm")
			else:
				UI.text_at(ci, font, Vector2(r.position.x + 10, r.get_center().y), "队友 %d" % i, 13, UI.fa(UI.B_SUB, a), "lm")
				UI.text_at(ci, font, Vector2(r.end.x - 10, r.get_center().y), "探索中通过升级招募", 10, UI.fa(UI.B_SUB, a), "rm")
		y += sh + 6.0
	y += 4.0
	# 流派（docs/181）：流派藏品的主效果只给本流派干员
	var lanes: Array = d.get("lanes", [])
	if not lanes.is_empty() and y + 20.0 < box.end.y:
		var lx := box.position.x + UI.btab(ci, font, Vector2(box.position.x, y + 3), "流派", UI.TAB_HP, 9) + 8.0
		for l in lanes:
			lx += UI.pill(ci, font, Vector2(lx, y), Character.OpDefs.LANES.get(l, l), UI.GOLD, 10)
		y += 26.0
	var care: Array = Character.care_labels(d)
	if not care.is_empty() and y + 20.0 < box.end.y:
		var cx := box.position.x + UI.btab(ci, font, Vector2(box.position.x, y + 3), "定位", UI.TAB_HP, 9) + 8.0
		for c in care:
			cx += UI.pill(ci, font, Vector2(cx, y), c, UI.PURPLE, 10)
		y += 26.0
	for n in d.get("progression", []):
		if n is Dictionary and n.get("type", "") == "elite" and int(n.get("level", 0)) == 2 and n.has("requires"):
			var req: Dictionary = n.requires
			var parts: Array = []
			if req.has("class_in_squad"):
				parts.append("编队中有%s干员" % req.class_in_squad)
			if req.has("doctor_passive"):
				var DocS = preload("res://scripts/characters/doctor.gd")
				parts.append("%s卡「%s」" % [DocS.cat_name(req.doctor_passive), DocS.PASSIVES.get(req.doctor_passive, {"name": req.doctor_passive}).name])
			for rid in req.get("relic", []):
				parts.append("藏品 #%s" % str(rid))
			if not parts.is_empty() and y + 18.0 < box.end.y:
				var f := UI.fit(font, "精英二条件：" + "、".join(parts), box.size.x, minf(36.0, box.end.y - y), [11, 10])
				y += UI.draw_fit(ci, font, Vector2(box.position.x, y), f, Color(0.8, 0.55, 1.0)) + 6.0
	var lore: String = od.lore
	if lore != "" and not ph and y + 40.0 < box.end.y:
		UI.code(ci, font, Vector2(box.position.x, y), "ARCHIVE // 档案", 8)
		var f := UI.fit(font, lore, box.size.x, box.end.y - y - 14.0, [11])
		UI.draw_fit(ci, font, Vector2(box.position.x, y + 14), f, UI.B_SUB)


## 近战 / 远程：先看图鉴标签（凯尔希是医疗但标「近战」），没有再按职业
func _op_is_melee(d: Dictionary) -> bool:
	var tags: Array = d.get("gallery", {}).get("tags", [])
	if tags.has("近战"):
		return true
	if tags.has("远程"):
		return false
	return d.get("class", "") in Character.MELEE_CLASSES


## --opmotion：按时间表驱动选人页并逐帧存图（--fixed-fps 30 时每帧 1/30 秒，录出来是真实节奏）
const OP_MOTION_SCRIPT := [[0.9, "step"], [1.9, "step"], [2.9, "tab_status"], [3.7, "tab_skill"], [4.4, "skill_row"], [5.3, "filter"], [6.2, "all"], [6.9, "go"]]
var op_motion_frame := 0
var op_motion_done := {}


func _op_motion_tick() -> void:
	var rt := t - op_motion
	for ev in OP_MOTION_SCRIPT:
		if rt >= ev[0] and not op_motion_done.has(ev[0]):
			op_motion_done[ev[0]] = true
			match ev[1]:
				"step":
					_op_step(1)
				"tab_status":
					_op_set_tab(0)
				"tab_skill":
					_op_set_tab(1)
				"skill_row":
					_op_skill_step(1)
				"filter":
					_op_filter_step(1)
				"all":
					_op_set_filter("")
				"go":
					_op_go()
	get_viewport().get_texture().get_image().save_png(_shot_dir() + "/opmotion/f_%04d.png" % op_motion_frame)
	op_motion_frame += 1
	if rt > 8.6:
		get_tree().quit()


## --titlemotion：按帧号驱动（--fixed-fps 30），[秒, 动作]
const TITLE_MOTION_SCRIPT := [[5.6, "down"], [6.3, "right"], [7.0, "down"], [7.7, "left"], [8.4, "left"], [9.1, "up"], [9.8, "up"],
	[10.6, "enter"], [12.2, "go"], [14.4, "up"], [15.3, "up"], [16.2, "down"], [17.0, "down"], [17.8, "click1"], [18.8, "end"]]
var title_motion := -1


func _title_motion_tick() -> void:
	var rt := title_motion / 30.0
	for ev in TITLE_MOTION_SCRIPT:
		if absf(rt - ev[0]) < 0.5 / 30.0:
			match ev[1]:
				"down", "up", "left", "right", "enter":
					var e := InputEventKey.new()
					e.keycode = {"down": KEY_DOWN, "up": KEY_UP, "left": KEY_LEFT, "right": KEY_RIGHT, "enter": KEY_ENTER}[ev[1]]
					e.pressed = true
					Input.parse_input_event(e)
				"go":
					_op_go()
				"click1":
					if diff_rects.has("tier1"):
						_diff_step(1 - diff_sel)
				"end":
					get_tree().quit()
	get_viewport().get_texture().get_image().save_png(_shot_dir() + "/titlemotion/f_%04d.png" % title_motion)
	title_motion += 1


## --codexmotion：按帧号驱动（--fixed-fps 30 下一帧 = 1/30 秒），每帧存一张图
func _codex_motion_tick() -> void:
	var f := codex_motion
	var steps := {15: func(): transition.switch_slash(_codex_motion_open), 75: func(): gallery._step(1), 112: func(): gallery._step(1),
		150: func(): gallery._set_info(3), 186: func(): gallery._set_info(1), 222: func(): gallery._set_info(0),
		260: func(): gallery._set_tab(1), 305: func(): gallery._step(1), 340: func(): gallery._step(1),
		378: func(): gallery._set_tab(0)}
	if steps.has(f):
		steps[f].call()
	if f > 0:
		get_viewport().get_texture().get_image().save_png(_shot_dir() + "/codexmotion/%04d.png" % f)
	codex_motion += 1
	if codex_motion > 430:
		get_tree().quit()


func _codex_motion_open() -> void:
	gallery.open()
	gallery.select_id("wisadel")   # 打开时选维什戴尔（概念图同一位干员）
	gallery._restart_open()
