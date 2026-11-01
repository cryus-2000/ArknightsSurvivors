extends Control
## EA practice setup. Actual battle initialization belongs to run/boss_trial.gd.
## 版式（11-01 docs/213 P1）：原来是 Godot 默认控件 + 青色粗框；改成设置页同款——暗面板左侧一道青条、标题 + 英文代码小标、
## 每行「名称 | ‹ 选项 ›」（‹ › 与键盘 ← / → 逐项切换，点中间仍弹下拉）、「开始演练」青底主按钮、「返回」描边按钮。节点 API 不变（测试直接 select）
signal closed
const UI = preload("res://scripts/ui.gd")
const D = preload("res://scripts/data.gd")
const Character = preload("res://scripts/characters/character.gd")
const Squads = preload("res://scripts/run/practice_squads.gd")
var boss_pick: OptionButton
var squad_pick: OptionButton
var squad_ids: Array = []   # 下标 0 = 自选队长（""）
var op_pick: OptionButton
var growth_pick: OptionButton
var phase_pick: OptionButton
var safe_pick: CheckBox
var panel: PanelContainer
var scroll: ScrollContainer
var action_buttons: Array[Button] = []
var boss_groups: Array = []
var op_ids: Array = []
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	margin.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(660, 0)
	center.add_child(panel)
	resized.connect(_resize_panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.075, 0.082, 0.098, 0.97)
	style.border_color = Color(1, 1, 1, 0.14)
	style.set_border_width_all(1)
	style.border_width_left = 4
	style.border_color = UI.CYAN
	style.content_margin_left = 32
	style.content_margin_right = 28
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.add_theme_font_override("font", load("res://fonts/ui.ttf"))
	box.add_theme_color_override("font_color", UI.TEXT)
	panel.add_child(box)
	var heading := Label.new()
	var code := Label.new()
	code.text = "BOSS TRIAL  //  PRACTICE"
	code.add_theme_font_size_override("font_size", 11)
	code.add_theme_color_override("font_color", UI.CYAN)
	box.add_child(code)
	heading.text = "Boss 演练"
	heading.add_theme_font_size_override("font_size", 30)
	box.add_child(heading)
	var rule := ColorRect.new()
	rule.color = Color(1, 1, 1, 0.16)
	rule.custom_minimum_size = Vector2(0, 1)
	box.add_child(rule)
	var note := Label.new()
	note.text = "直接进入真实 Boss 战；不写入通关、难度或图鉴进度。"
	note.add_theme_font_size_override("font_size", 15)
	note.add_theme_color_override("font_color", UI.SUB)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	boss_pick = _select_row(box, "对手")
	for group in D.MID_POOL:
		_add_boss_group(group)
	for ending in D.ENDINGS.values():
		_add_boss_group([ending.boss])
	squad_pick = _select_row(box, "分队")
	squad_ids = [""]
	squad_pick.add_item("自选队长 · 成长补到打到该 Boss 时的平均水平")
	for s in Squads.list():
		squad_ids.append(s.id)
		squad_pick.add_item(s.label)
	squad_pick.item_selected.connect(func(_i): _sync_squad())
	op_pick = _select_row(box, "队长")
	op_ids = Character.list_ids()
	for id in op_ids:
		op_pick.add_item(Character.load_def(id).get("name", id))
	growth_pick = _select_row(box, "成长阶段")
	for label in ["精零 · 初始", "精英一 · 前半成长", "精英二 · 完整成长"]:
		growth_pick.add_item(label)
	growth_pick.select(2)
	phase_pick = _select_row(box, "起始形态")
	phase_pick.add_item("正常开战")
	phase_pick.add_item("直接进入第二形态（支持的 Boss）")
	safe_pick = CheckBox.new()
	safe_pick.text = "观察模式：队长不会倒下"
	safe_pick.button_pressed = true
	safe_pick.add_theme_color_override("font_color", UI.TEXT)
	safe_pick.add_theme_color_override("font_hover_color", UI.CYAN)
	safe_pick.add_theme_color_override("font_focus_color", UI.CYAN)
	safe_pick.add_theme_color_override("font_pressed_color", UI.TEXT)
	box.add_child(safe_pick)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 20)
	box.add_child(buttons)
	for label in ["开始演练", "返回"]:
		var b := Button.new()
		b.text = label
		b.custom_minimum_size = Vector2(0, 46)
		_style_btn(b, label == "开始演练")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action_buttons.append(b)
		b.pressed.connect(_start if label == "开始演练" else close)
		buttons.add_child(b)
	_resize_panel()
	_sync_squad()
	hide()


## 选了成品分队：队长与成长阶段由分队决定，两行置灰
func _sync_squad() -> void:
	var own: bool = squad_pick.selected <= 0
	op_pick.disabled = not own
	growth_pick.disabled = not own
	if not own:
		var op := str(Squads.squad(squad_ids[squad_pick.selected]).get("op", ""))
		if op_ids.has(op):
			op_pick.select(op_ids.find(op))   # 置灰的两行显示分队的开局干员与完整成长
		growth_pick.select(2)
func _resize_panel() -> void:
	if is_instance_valid(panel):
		panel.custom_minimum_size.x = clampf(size.x - 64.0, 320.0, 660.0)
func _select_row(box: VBoxContainer, label: String) -> OptionButton:
	var row := HBoxContainer.new()
	var text := Label.new()
	text.text = label
	text.custom_minimum_size.x = 96
	text.add_theme_color_override("font_color", UI.SUB)
	row.add_child(text)
	var pick := OptionButton.new()
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.fit_to_longest_item = false
	pick.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	pick.custom_minimum_size.y = 38
	_style_pick(pick)
	row.add_child(_arrow("‹", pick, -1))
	row.add_child(pick)
	row.add_child(_arrow("›", pick, 1))
	pick.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventKey and ev.pressed and (Pad.kc(ev) == KEY_LEFT or Pad.kc(ev) == KEY_RIGHT):
			_step(pick, -1 if Pad.kc(ev) == KEY_LEFT else 1)
			pick.accept_event())
	box.add_child(row)
	return pick


## ‹ / › 逐项切换（置灰的行不动）；分队行切换后同步队长 / 成长两行
func _step(pick: OptionButton, d: int) -> void:
	if pick.disabled or pick.item_count == 0:
		return
	pick.select((pick.selected + d + pick.item_count) % pick.item_count)
	if pick == squad_pick:
		_sync_squad()
func _arrow(t: String, pick: OptionButton, d: int) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(38, 38)
	_style_btn(b, false)
	b.pressed.connect(func(): _step(pick, d))
	return b
func _sb(bg: Color, edge: Color, w := 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = edge
	sb.set_border_width_all(w)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	return sb
func _style_pick(pick: OptionButton) -> void:
	pick.add_theme_stylebox_override("normal", _sb(Color(0.035, 0.04, 0.05, 0.9), Color(1, 1, 1, 0.18)))
	pick.add_theme_stylebox_override("hover", _sb(Color(0.05, 0.07, 0.08, 0.95), UI.CYAN))
	pick.add_theme_stylebox_override("pressed", _sb(Color(0.05, 0.07, 0.08, 0.95), UI.CYAN))
	pick.add_theme_stylebox_override("focus", _sb(Color(0, 0, 0, 0), UI.CYAN, 2))
	pick.add_theme_stylebox_override("disabled", _sb(Color(0.035, 0.04, 0.05, 0.5), Color(1, 1, 1, 0.08)))
	pick.add_theme_color_override("font_color", UI.TEXT)
	pick.add_theme_color_override("font_hover_color", UI.TEXT)
	pick.add_theme_color_override("font_disabled_color", UI.SUB)
## 主按钮青底深字（同设置页底栏「返回」/ 难度页「确认难度」），其余暗底描边
func _style_btn(b: Button, primary: bool) -> void:
	var base: Color = UI.CYAN if primary else Color(0.035, 0.04, 0.05, 0.9)
	b.add_theme_stylebox_override("normal", _sb(base, UI.CYAN if primary else Color(1, 1, 1, 0.3)))
	b.add_theme_stylebox_override("hover", _sb(base.lightened(0.15) if primary else Color(0.05, 0.08, 0.09, 0.95), UI.CYAN))
	b.add_theme_stylebox_override("pressed", _sb(base.darkened(0.15), UI.CYAN))
	b.add_theme_stylebox_override("focus", _sb(Color(0, 0, 0, 0), Color.WHITE if primary else UI.CYAN, 2))
	var ink: Color = Color(0.03, 0.07, 0.09) if primary else UI.TEXT
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, ink)
	b.add_theme_font_size_override("font_size", 18 if primary else 16)
func _add_boss_group(group: Array) -> void:
	if boss_groups.has(group):
		return
	boss_groups.append(group.duplicate())
	var names: Array = []
	for id in group:
		names.append(D.ENEMIES[id].name)
	boss_pick.add_item(" + ".join(names))
func open() -> void:
	if not Cfg.can_boss_trial():
		return
	show()
	op_pick.select(maxi(0, op_ids.find(Cfg.character_id)))
	boss_pick.grab_focus()
func close() -> void:
	hide()
	closed.emit()
func _start() -> void:
	if not Cfg.can_boss_trial() or boss_groups.is_empty():
		return
	Cfg.boss_trial_request = {"group": boss_groups[boss_pick.selected].duplicate(), "operator": op_ids[op_pick.selected], "growth": growth_pick.selected, "phase": phase_pick.selected + 1, "safe": safe_pick.button_pressed, "squad": squad_ids[maxi(0, squad_pick.selected)]}
	get_tree().change_scene_to_file("res://game.tscn")
func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and Pad.kc(event) == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.025, 0.03, 0.9))
