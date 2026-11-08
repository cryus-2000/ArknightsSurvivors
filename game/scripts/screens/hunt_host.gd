extends Control
## 标题页「寻访」入口（10-22 用户）：把结算页那套寻访界面（screens/headhunt.gd）盖在标题上。
## headhunt 只用宿主的 hud（画布）/ font / kb_nav 三样，这里就是这三样；寻访自己关掉（用完凭证 / 返回）时这层跟着收起。
signal closed

const Headhunt = preload("res://scripts/screens/headhunt.gd")

var hud: Control
var font: Font
var kb_nav := false
var hh


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	hud = self
	font = load("res://fonts/ui.ttf")
	hh = Headhunt.new(self)
	hide()


## 标题页入口：没有凭证也打开（浏览模式，按钮灰显，10-24 用户）；返回是否打开了
func open() -> bool:
	kb_nav = Pad.using
	hh.open_browse()
	visible = hh.open
	return visible


func _process(_delta: float) -> void:
	if not visible:
		return
	if not hh.open:
		hide()
		closed.emit()
		return
	queue_redraw()


func _draw() -> void:
	if hh.open:
		hh.draw(size)


## 寻访页「关注作者，领寻访凭证」（11-08）：标题页的支持作者浮层
func open_support() -> void:
	if get_parent() != null and get_parent().has_method("open_support"):
		get_parent().open_support()


func _support_open() -> bool:
	var p = get_parent()
	return p != null and "sup_view" in p and p.sup_view != null and p.sup_view.visible


func _input(event: InputEvent) -> void:
	if not visible or _support_open():   # 支持作者浮层盖在上面时让开（它的点按走 _gui_input）
		return
	if event is InputEventMouseMotion:
		kb_nav = false
		if hh.input(event):   # 指定干员列表的拖动翻页要看鼠标移动
			get_viewport().set_input_as_handled()
		return
	if hh.input(event):
		get_viewport().set_input_as_handled()
