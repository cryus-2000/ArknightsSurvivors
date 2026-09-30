extends Control
## EA practice setup. Actual battle initialization belongs to run/boss_trial.gd.
signal closed
const UI = preload("res://scripts/ui.gd")
const D = preload("res://scripts/data.gd")
const Character = preload("res://scripts/characters/character.gd")
var boss_pick: OptionButton
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
	style.bg_color = UI.BG
	style.border_color = UI.CYAN
	style.set_border_width_all(2)
	style.content_margin_left = 28
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
	heading.text = "Boss 演练 · EA"
	heading.add_theme_font_size_override("font_size", 30)
	box.add_child(heading)
	var note := Label.new()
	note.text = "直接进入真实 Boss 战；不写入通关、难度或图鉴进度。"
	note.add_theme_font_size_override("font_size", 16)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	boss_pick = _select_row(box, "对手")
	for group in D.MID_POOL:
		_add_boss_group(group)
	for ending in D.ENDINGS.values():
		_add_boss_group([ending.boss])
	op_pick = _select_row(box, "主控干员")
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
	safe_pick.text = "观察模式：主控不会倒下"
	safe_pick.button_pressed = true
	box.add_child(safe_pick)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 20)
	box.add_child(buttons)
	for label in ["开始演练", "返回"]:
		var b := Button.new()
		b.text = label
		b.custom_minimum_size = Vector2(0, 46)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action_buttons.append(b)
		b.pressed.connect(_start if label == "开始演练" else close)
		buttons.add_child(b)
	_resize_panel()
	hide()
func _resize_panel() -> void:
	if is_instance_valid(panel):
		panel.custom_minimum_size.x = clampf(size.x - 64.0, 320.0, 660.0)
func _select_row(box: VBoxContainer, label: String) -> OptionButton:
	var row := HBoxContainer.new()
	var text := Label.new()
	text.text = label
	text.custom_minimum_size.x = 96
	row.add_child(text)
	var pick := OptionButton.new()
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.fit_to_longest_item = false
	pick.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	pick.custom_minimum_size.y = 38
	row.add_child(pick)
	box.add_child(row)
	return pick
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
	Cfg.boss_trial_request = {"group": boss_groups[boss_pick.selected].duplicate(), "operator": op_ids[op_pick.selected], "growth": growth_pick.selected, "phase": phase_pick.selected + 1, "safe": safe_pick.button_pressed}
	get_tree().change_scene_to_file("res://game.tscn")
func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(UI.BG, 0.95))
