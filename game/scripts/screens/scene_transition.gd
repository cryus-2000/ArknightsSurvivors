extends Control
## 页面切换的短潮色遮罩；只管理展示与输入锁，不持有玩法状态。
const UI = preload("res://scripts/ui.gd")
var busy := false
var opacity := 0.0
var tween: Tween
var slash := -1.0   # 斜切黑带进度 0–1（图鉴 C4' 打开，docs/58 §11.2）；< 0 = 不在斜切
## 扫线切换（11-05 用户「页面切换可以加一下」；同日嫌快门「有点奇怪」，选「轻量扫线」）：旧页压暗 0.1 秒 → 换页 →
## 一道白细线带淡青拖尾从左扫到右（0.32 秒，缓出），扫过的地方暗幕退去、没扫到的仍暗着。
## shut：压暗段 0–1 = 暗幕浓度；opening 段 shut 1 → 0 = 扫线还剩多少没走（1 = 刚开始）。减少动态效果退回原来的短压暗
var shut := -1.0
var opening := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(false)

func switch_page(change: Callable) -> void:
	if busy:
		return
	_lock()
	if not Cfg.reduce_motion:
		opening = false
		tween = create_tween()
		tween.tween_method(_set_shut, 0.0, 1.0, 0.1).set_trans(Tween.TRANS_SINE)
		tween.tween_callback(change)
		tween.tween_callback(func(): opening = true)
		tween.tween_method(_set_shut, 1.0, 0.0, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_callback(func():
			shut = -1.0
			opening = false
			queue_redraw()
			_unlock())
		return
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
	if not Cfg.reduce_motion:   # 只打开段（从合拢处分开）
		opening = true
		_set_shut(1.0)
		tween = create_tween()
		tween.tween_method(_set_shut, 1.0, 0.0, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_callback(func():
			shut = -1.0
			opening = false
			queue_redraw()
			_unlock())
		return
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

func _set_shut(v: float) -> void:
	shut = v
	queue_redraw()


func _set_opacity(value: float) -> void:
	opacity = value
	queue_redraw()

func _draw() -> void:
	if slash >= 0.0:
		_draw_slash()
		return
	if shut >= 0.0:
		_draw_shutter()
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


func _draw_shutter() -> void:
	var w := size.x
	var h := size.y
	var ink: Color = UI.BG2
	if not opening:   # 压暗段
		draw_rect(Rect2(Vector2.ZERO, size), Color(ink, 0.82 * shut))
		return
	var e: float = 1.0 - shut   # 扫线走了多少（0 → 1）
	var x: float = w * e
	draw_rect(Rect2(x, 0, w - x, h), Color(ink, 0.82))   # 没扫到的仍暗
	draw_rect(Rect2(0, 0, x, h), Color(ink, 0.82 * clampf(1.0 - e * 2.5, 0.0, 1.0)))   # 扫过的很快退去
	if e > 0.0 and e < 1.0:
		var cyan: Color = UI.CYAN
		draw_rect(Rect2(x - 48.0, 0, 48.0, h), Color(cyan, 0.06))   # 淡青拖尾
		draw_rect(Rect2(x - 14.0, 0, 14.0, h), Color(cyan, 0.08))
		draw_rect(Rect2(x - 1.0, 0, 1.0, h), Color(1, 1, 1, 0.85))   # 白细线
