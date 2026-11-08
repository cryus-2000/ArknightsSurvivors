extends CanvasLayer
## 标题页「上次对局异常退出」提示（core/crash_box.gd 的「上次」那份还没看过时挂上）：左下角一行字，点一下打开曲线面板（可复制 / 保存），
## 看过就不再提示（性能报告页的「复制报告」仍带着这份，直到下一次异常退出覆盖）。挂在场景树根上，同 perf_hud 在 _input 里先截点击
const CrashBox = preload("res://scripts/core/crash_box.gd")

var lb: Label
var bg: ColorRect


static func ensure(tree: SceneTree) -> void:
	if tree == null or tree.root.get_node_or_null("CrashNote") != null:
		return
	var p := CrashBox.check_prev()
	if p.is_empty() or int(p.get("seen", 0)) == 1:
		return
	var n = load("res://scripts/core/crash_note.gd").new()
	n.name = "CrashNote"
	tree.root.call_deferred("add_child", n)


func _ready() -> void:
	layer = 127
	process_mode = Node.PROCESS_MODE_ALWAYS
	bg = ColorRect.new()
	bg.color = Color(0.05, 0.02, 0.02, 0.72)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	lb = Label.new()
	lb.add_theme_font_override("font", load("res://fonts/ui.ttf"))
	lb.add_theme_color_override("font_color", Color(1.0, 0.82, 0.55))
	lb.add_theme_color_override("font_outline_color", Color.BLACK)
	lb.add_theme_constant_override("outline_size", 3)
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lb.text = CrashBox.short_line(CrashBox.prev)
	add_child(lb)
	get_viewport().size_changed.connect(_place)
	_place()


func _place() -> void:
	var k: float = 1.7 if Cfg.mobile_web() else (1.25 if Pad.touch_ui() else 1.0)
	lb.add_theme_font_size_override("font_size", int(12 * k))
	var sz: Vector2 = lb.get_combined_minimum_size()
	var vs: Vector2 = get_viewport().get_visible_rect().size
	lb.size = sz
	lb.position = Vector2(10, vs.y - sz.y - 10)
	bg.position = lb.position - Vector2(6, 4)
	bg.size = sz + Vector2(12, 8)


func _input(ev: InputEvent) -> void:
	var p := Vector2.INF
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		p = ev.position
	elif ev is InputEventScreenTouch and ev.pressed:
		p = ev.position
	if p != Vector2.INF and bg.get_global_rect().has_point(p):
		get_viewport().set_input_as_handled()
		CrashBox.open_panel(CrashBox.report_text(CrashBox.prev))
		CrashBox.ack()
		queue_free()
