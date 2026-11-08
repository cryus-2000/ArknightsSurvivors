extends Node
## 手机商人页（11-08 用户手机截图「货架太挤」+「商人露个脸」）：手机横屏（--touch，956×440 比例 + 模拟灵动岛 / 胶囊安全区）下
## 每张货品卡都有「详情」、卡上不写说明和作用对象（说明 / 影响对象进详情）；卡片顶边让出安全区上沿；详情键在卡内、不压名字和价格条；
## 详情开着画的是完整说明 + 影响对象；点卡片其余位置仍是购买
var game: Node
var frames := 0
var failures := 0
const INS := [76.0, 56.0, 76.0, 27.0]


func check(v: bool, label: String) -> void:
	if not v:
		failures += 1
		print("FAIL ", label)


func _ready() -> void:
	get_window().size = Vector2i(1912, 880)
	game = load("res://game.tscn").instantiate()
	add_child(game)


func _ins() -> void:
	var vis: Vector2 = get_viewport().get_visible_rect().size
	Cfg._ins_key = Vector3(vis.x, vis.y, Cfg.ui_k)
	Cfg._ins = INS.duplicate()


func _cards() -> Array:
	return game.panel_box.get_children().filter(func(c): return c is Button and not c.is_queued_for_deletion())


func _process(_dt: float) -> void:
	frames += 1
	_ins()
	if frames == 5:
		game.state = game.S.PLAY
		game.pending_levelups = 0
		game.pending_chests = 0
		game.ingots = 60
		game.merchant = {"pos": game.ppos, "life": 60.0, "near": false, "purchases": 0}
		game.merchant_idx = 1
		game.shop_sys.open()
	elif frames == 40:
		var cards := _cards()
		check(Cfg.ui_form() > 0, "触屏版式（ui_form %d）" % Cfg.ui_form())
		check(cards.size() >= 4, "货架至少 4 张（%d）" % cards.size())
		check(game.panel_box.offset_top >= INS[1] + 99.0, "卡片顶边让出安全区上沿（%.0f）" % game.panel_box.offset_top)
		for c in cards:
			var it: Dictionary = c.get_meta("item")
			check(c.get_meta("phone", false) and c.get_meta("more", false), "%s：手机卡有「详情」" % it.name)
			check((c.get_meta("fit", {}) as Dictionary).is_empty(), "%s：卡上不写说明" % it.name)
			check(str(c.get_meta("full_desc", "")).begins_with(str(it.get("full", it.desc)).substr(0, 4)), "%s：详情是完整说明" % it.name)
			var dr: Rect2 = c.get_meta("detail_r", Rect2())
			check(dr.has_area() and Rect2(Vector2.ZERO, c.size).encloses(dr) and dr.end.y < 40.0, "%s：详情键在卡内右上（%s）" % [it.name, dr])
			var gr: Rect2 = c.get_global_rect()
			var vs: Vector2 = game.panel.size
			check(gr.position.x >= INS[0] - 1.0 and gr.end.x <= vs.x - INS[2] + 1.0, "%s：卡在左右安全区内（%s）" % [it.name, gr])
		# 已售出的卡也有详情（之前只有部分卡有）
		game.shop_items[0].sold = true
		game.shop_ui.build()
	elif frames == 50:
		var c: Button = _cards()[0]
		check(c.get_meta("more", false) and c.get_meta("detail_r", Rect2()).has_area(), "已售出的卡仍有「详情」")
		# 点详情外：购买第 2 张（详情不吞点击）
		var n0: int = game.ingots
		game.shop_sys.buy(1)
		check(game.ingots < n0 and game.shop_items[1].sold, "点卡片照常购买")
		game.panel_ui.detail_i = 0
		game.panel_tip.queue_redraw()
	elif frames == 60:
		print("SHOP TOUCH LAYOUT failures=%d" % failures)
		get_tree().quit(1 if failures else 0)
