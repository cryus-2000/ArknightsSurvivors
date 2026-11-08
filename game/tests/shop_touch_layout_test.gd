extends Node
## 手机商人页与电脑版同一版式（11-08 用户选「电脑版整页等比缩进手机」，同事件页）：手机横屏（--touch，956×440 比例 + 模拟灵动岛 / 胶囊安全区）下
## 整页（商人立绘框 + 五张货品卡 + 按钮行）是桌面版式按安全区等比缩小：只缩不放、整块在安全区内且让出顶栏 / 底栏；
## 货品卡保持桌面设计尺寸（缩放后不小于约 100 宽，触屏可点）；说明放不下的卡有「详情」；点卡照常购买
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
		var su = game.shop_ui
		var vs: Vector2 = game.panel.size
		var t0: float = maxf(INS[1], su.HUD_TOP)
		var b0: float = maxf(INS[3], vs.y * su.HUD_RES_PHONE)
		var safe := Rect2(INS[0], t0, vs.x - INS[0] - INS[2], vs.y - t0 - b0)
		var F: Dictionary = su.frame()
		check(Cfg.ui_form() > 0, "触屏版式（ui_form %d）" % Cfg.ui_form())
		check(F.k > 0.55 and F.k <= 1.0, "整页只缩不放（k %.3f）" % F.k)
		var box := Rect2(F.o + F.k * su.DBOX.position, F.k * su.DBOX.size)
		check(safe.grow(1.0).encloses(box), "整页在安全区内、让出顶栏 / 底栏（%s in %s）" % [box, safe])
		var cards := _cards()
		check(cards.size() >= 4, "货架至少 4 张（%d）" % cards.size())
		var pr: Rect2 = game.panel.get_global_rect()
		for c in cards:
			var it: Dictionary = c.get_meta("item")
			var gr: Rect2 = c.get_global_rect()
			gr.position -= pr.position
			check(absf(c.size.x - 160.0) < 1.0 and absf(c.size.y - su.CARD_H) < 1.0, "%s：桌面卡尺寸 160×%d（%s）" % [it.name, su.CARD_H, c.size])
			check(safe.grow(1.0).encloses(gr), "%s：卡在安全区内（%s）" % [it.name, gr])
			check(gr.size.x >= 100.0, "%s：缩放后仍好点（宽 %.0f）" % [it.name, gr.size.x])
			var fd: Dictionary = c.get_meta("fit", {})
			check(not fd.is_empty() and (fd.get("fit", false) or c.get_meta("more", false)), "%s：卡上有说明，放不下的有「详情」" % it.name)
		for b in game.panel.get_children():
			if b.has_meta("shopbtn") and not b.is_queued_for_deletion():
				var br: Rect2 = (b as Control).get_global_rect()
				br.position -= pr.position
				check(safe.grow(24.0).encloses(br), "按钮在安全区内（%s）" % br)
		var n0: int = game.ingots
		game.shop_sys.buy(1)
		check(game.ingots < n0 and game.shop_items[1].sold, "点卡片照常购买")
	elif frames == 50:
		print("SHOP TOUCH LAYOUT failures=%d" % failures)
		get_tree().quit(1 if failures else 0)
