extends Control
## 页面切换的短潮色遮罩；只管理展示与输入锁，不持有玩法状态。
const UI = preload("res://scripts/ui.gd")
var busy := false
var opacity := 0.0
var tween: Tween
var slash := -1.0   # 斜切黑带进度 0–1（图鉴 C4' 打开，docs/58 §11.2）；< 0 = 不在斜切

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

## 斜切转场（图鉴 C4'）：600 ms ease-in-out，黑色平行四边形带（前缘 26 px 警示黄）从左扫过，过半那一帧换页，再扫出。
## 「减少动态效果」时退回普通的短压暗切换
func switch_slash(change: Callable) -> void:
	if busy:
		return
	if Cfg.reduce_motion:
		switch_page(change)
		return
	_lock()
	slash = 0.0
	tween = create_tween()
	tween.tween_method(_set_slash, 0.0, 0.5, 0.3)
	tween.tween_callback(change)
	tween.tween_method(_set_slash, 0.5, 1.0, 0.3)
	tween.tween_callback(func():
		slash = -1.0
		queue_redraw()
		_unlock())

func _set_slash(v: float) -> void:
	slash = v
	queue_redraw()

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
	if slash >= 0.0:
		_draw_slash()
		return
	if opacity <= 0.0:
		return
	var ink: Color = UI.BG2
	ink.a = opacity
	draw_rect(Rect2(Vector2.ZERO, size), ink)
	var tide: Color = UI.CYAN
	tide.a = opacity * 0.25
	draw_rect(Rect2(0, size.y * 0.5, size.x * opacity, 2), tide)

func _draw_slash() -> void:
	var w := size.x
	var h := size.y
	var t := UI.ease_io(slash)
	var span := w + h + 400.0
	var ink := UI.C_D_BG
	if t < 0.5:
		var lead := -h - 200.0 + span * t * 2.0
		draw_colored_polygon(PackedVector2Array([Vector2(-h - 400.0, 0), Vector2(lead + h, 0), Vector2(lead, h), Vector2(-h - 400.0, h)]), ink)
		draw_colored_polygon(PackedVector2Array([Vector2(lead + h, 0), Vector2(lead + h + 26.0, 0), Vector2(lead + 26.0, h), Vector2(lead, h)]), UI.C_ACC)
	else:
		var lead2 := -h - 200.0 + span * (t - 0.5) * 2.0
		draw_colored_polygon(PackedVector2Array([Vector2(lead2 + h, 0), Vector2(w + h + 400.0, 0), Vector2(w + h + 400.0, h), Vector2(lead2, h)]), ink)
		draw_colored_polygon(PackedVector2Array([Vector2(lead2 + h - 26.0, 0), Vector2(lead2 + h, 0), Vector2(lead2, h), Vector2(lead2 - 26.0, h)]), UI.C_ACC)
