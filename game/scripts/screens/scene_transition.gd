extends Control
## 页面切换的短潮色遮罩；只管理展示与输入锁，不持有玩法状态。
const UI = preload("res://scripts/ui.gd")
var busy := false
var opacity := 0.0
var tween: Tween

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(false)

func switch_page(change: Callable) -> void:
	if busy:
		return
	_lock()
	tween = create_tween()
	tween.tween_method(_set_opacity, 0.0, 1.0, 0.13).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(change)
	tween.tween_method(_set_opacity, 1.0, 0.0, 0.20).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(_unlock)

func reveal_page() -> void:
	if busy:
		return
	_lock()
	_set_opacity(0.65)
	tween = create_tween()
	tween.tween_method(_set_opacity, 0.65, 0.0, 0.18).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(_unlock)

func _lock() -> void:
	busy = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process_input(true)

func _unlock() -> void:
	busy = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(false)

func _input(_event: InputEvent) -> void:
	if busy:
		get_viewport().set_input_as_handled()

func _set_opacity(value: float) -> void:
	opacity = value
	queue_redraw()

func _draw() -> void:
	if opacity <= 0.0:
		return
	var ink: Color = UI.BG2
	ink.a = opacity
	draw_rect(Rect2(Vector2.ZERO, size), ink)
	var tide: Color = UI.CYAN
	tide.a = opacity * 0.25
	draw_rect(Rect2(0, size.y * 0.5, size.x * opacity, 2), tide)
