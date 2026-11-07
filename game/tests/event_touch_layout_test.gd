extends Node
## 触屏事件页与桌面同一版式（11-08 用户 iPhone「事件页的排版不能跟电脑端一样吗？」）：手机横屏（--touch，844×390 比例 + 模拟灵动岛 / 胶囊安全区）下
## 事件页是「左插画 + 右竖排选项列」：选项条按桌面设计尺寸 596×100 起（触屏热区不缩）、不再整屏宽；
## 设计框整块在安全区内、只缩不放；插画右边缘在选项列左边；选项多（深蓝之心 7 个）照样能滚到「离开」
var game: Node
var frames := 0
var failures := 0
const INS := [76.0, 56.0, 76.0, 27.0]


func check(v: bool, label: String) -> void:
	if not v:
		failures += 1
		print("FAIL ", label)


func _ready() -> void:
	get_window().size = Vector2i(1688, 780)
	game = load("res://game.tscn").instantiate()
	add_child(game)


func _ins(on: bool) -> void:
	var vis: Vector2 = get_viewport().get_visible_rect().size
	Cfg._ins_key = Vector3(vis.x, vis.y, Cfg.ui_k)
	Cfg._ins = INS.duplicate() if on else [0.0, 0.0, 0.0, 0.0]


func _open(id: String) -> void:
	game.pending_levelups = 0
	game.pending_chests = 0
	game.show_queue.clear()
	game.state = game.S.PLAY
	game.ingots = 0
	game.panel.visible = false
	game.endg.open(id)


func _scroll_rect() -> Rect2:
	var sc: ScrollContainer = game.panel_scroll
	return Rect2(sc.position, sc.size * sc.scale)


func _check_layout(tag: String, ins: Array) -> void:
	var cp = game.panel_ui
	var vs: Vector2 = game.panel.size
	var safe := Rect2(ins[0], ins[1], vs.x - ins[0] - ins[2], vs.y - ins[1] - ins[3])
	var F: Dictionary = cp.ev_frame()
	var k: float = F.k
	check(Cfg.ui_form() > 0, tag + "：触屏版式（ui_form %d）" % Cfg.ui_form())
	check(k > 0.6 and k <= 1.0, tag + "：设计框只缩不放（k %.3f）" % k)
	var box := Rect2(F.o + k * Vector2(F.cx - cp.EV_CX, cp.EV_DY0), k * Vector2(cp.EV_DW, cp.EV_DH))
	check(safe.grow(1.0).encloses(box), tag + "：设计框在安全区内（%s in %s）" % [box, safe])
	var sr := _scroll_rect()
	check(safe.grow(1.0).encloses(sr), tag + "：选项列在安全区内（%s）" % sr)
	var art_r: float = F.o.x + k * (F.cx - 576.0 + 560.0)
	check(art_r <= sr.position.x, tag + "：插画在左、选项列在右（插画右缘 %.0f ≤ 选项列 %.0f）" % [art_r, sr.position.x])
	check(sr.size.x < vs.x * 0.6, tag + "：选项列不再整屏宽（%.0f / %.0f）" % [sr.size.x, vs.x])
	var cards: Array = game.panel_col.get_children().filter(func(c): return c is Button)
	check(cards.size() > 0 and cards.all(func(c): return (c as Control).size.x >= 595.0 and (c as Control).size.y >= 99.0 and not c.get_meta("phone", false)), tag + "：选项条桌面尺寸 596×100 起（触屏热区不缩）")


func _process(_dt: float) -> void:
	frames += 1
	if frames <= 4:
		_ins(true)
	if frames == 5:
		_ins(true)
		_open("opening")
	elif frames == 30:
		_ins(true)
		_check_layout("开场事件 + 安全区", INS)
		_ins(false)
		game.panel_ui.ev_place()
	elif frames == 32:
		_check_layout("开场事件 无安全区", [0.0, 0.0, 0.0, 0.0])
		_ins(true)
		_open("heart")
	elif frames == 60:
		_ins(true)
		_check_layout("深蓝之心 + 安全区", INS)
		var bar = game.panel_scroll.get_v_scroll_bar()
		check(float(bar.max_value) - float(bar.page) > 1.0, "深蓝之心 7 个选项：可滚动")
		game.kb_nav = true
		game.nav_sel = game.choices.size() - 1
	elif frames == 80:
		var last: Control = game.panel_col.get_child(game.choices.size() - 1)
		var sc: ScrollContainer = game.panel_scroll
		var top: float = last.position.y - float(sc.scroll_vertical)
		check(top >= -0.5 and top + last.size.y <= sc.size.y + 0.5, "焦点到「离开」自动滚到可见（%.0f..%.0f / %.0f）" % [top, top + last.size.y, sc.size.y])
		game.kb_nav = false
		print("EVENT TOUCH LAYOUT failures=%d" % failures)
		get_tree().quit(1 if failures else 0)
