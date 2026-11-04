extends Node
## 事件选项条放得下（11-05 用户「深蓝之心事件那里源石锭不够无法退出」）：深蓝之心 7 个选项，原来 100 高的条只放得下 5 张，
## 最后的「离开」在屏幕外点不到。源石锭 0 打开深蓝之心，等排版落定，每张条（尤其「离开」）都要整张在面板里；焦点起在第一张能选的
var game: Node
var frames := 0
var failures := 0


func check(v: bool, label: String) -> void:
	if not v:
		failures += 1
		print("FAIL ", label)


func _ready() -> void:
	get_window().size = Vector2i(1280, 720)   # 无头缺省视口是 1280×1280，7 张条本来就放得下；按桌面 16:9 量
	game = load("res://game.tscn").instantiate()
	add_child(game)


func _process(_dt: float) -> void:
	frames += 1
	if frames == 5:
		game.pending_levelups = 0
		game.pending_chests = 0
		game.show_queue.clear()
		game.state = game.S.PLAY
		game.ingots = 0
		game.endg.open("heart")
		check(game.state == game.S.CHOICE and game.choice_kind == "event", "heart event panel opened")
		check(game.choices.size() == 7, "heart offers 7 options (%d)" % game.choices.size())
		var first_ok := -1
		for i in game.choices.size():
			if not game.choices[i].get("disabled", false):
				first_ok = i
				break
		check(game.nav_sel == first_ok, "focus starts on the first selectable option (%d vs %d)" % [game.nav_sel, first_ok])
	elif frames == 40:
		var panel: Rect2 = game.panel.get_global_rect()
		var cards: Array = game.panel_col.get_children().filter(func(c): return c is Control and c.visible)
		check(cards.size() == game.choices.size(), "one bar per option (%d)" % cards.size())
		for i in cards.size():
			var r: Rect2 = (cards[i] as Control).get_global_rect()
			check(r.end.y <= panel.end.y + 0.5 and r.position.y >= panel.position.y - 0.5, "bar %d inside panel (%s in %s)" % [i, r, panel])
		var leave: int = game.choices.map(func(o): return str(o.name)).find("离开")
		check(leave >= 0 and not game.choices[leave].get("disabled", false), "离开 offered and selectable")
		print("EVENT FIT failures=%d" % failures)
		get_tree().quit(1 if failures else 0)
