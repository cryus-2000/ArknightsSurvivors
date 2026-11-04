extends Node
## 事件选项放不下时可滚动（11-05 用户「深蓝之心事件那里源石锭不够无法退出」→「把事件的做成那种可以滚动的」）：
## 深蓝之心 7 个选项（源石锭 0）在 16:9 下放不下 → 选项区可竖向滚动、卡高不压缩；焦点起在第一张能选的；
## 焦点移到「离开」时自动滚到底、「离开」整张在可见区内；选项不多的事件不需要滚，布局和原来一样
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


func _open(id: String) -> void:
	game.pending_levelups = 0
	game.pending_chests = 0
	game.show_queue.clear()
	game.state = game.S.PLAY
	game.ingots = 0
	game.endg.open(id)


func _room() -> float:
	var bar = game.panel_scroll.get_v_scroll_bar()
	return float(bar.max_value) - float(bar.page)


func _process(_dt: float) -> void:
	frames += 1
	if frames == 5:
		_open("heart")
		check(game.state == game.S.CHOICE and game.choice_kind == "event", "heart event panel opened")
		check(game.choices.size() == 7, "heart offers 7 options (%d)" % game.choices.size())
		var first_ok := -1
		for i in game.choices.size():
			if not game.choices[i].get("disabled", false):
				first_ok = i
				break
		check(game.nav_sel == first_ok, "focus starts on the first selectable option (%d vs %d)" % [game.nav_sel, first_ok])
	elif frames == 40:
		check(_room() > 1.0, "7 options overflow → the option list scrolls (room %.0f)" % _room())
		var cards: Array = game.panel_col.get_children()
		check(cards.size() == 7 and cards.all(func(c): return (c as Control).size.y >= 99.0), "bars keep full height (no squeeze)")
		check(Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(game.panel_scroll.get_global_rect()), "scroll area inside the screen (%s)" % game.panel_scroll.get_global_rect())
		game.kb_nav = true
		game.nav_sel = game.choices.size() - 1   # 方向键走到最后一张（离开）
	elif frames == 60:
		var sr: Rect2 = game.panel_scroll.get_global_rect()
		var last: Rect2 = (game.panel_col.get_child(game.choices.size() - 1) as Control).get_global_rect()
		check(game.panel_scroll.scroll_vertical > 0, "focus on the last option scrolls down (%d)" % game.panel_scroll.scroll_vertical)
		check(sr.grow(0.5).encloses(last), "离开 fully visible after scrolling (%s in %s)" % [last, sr])
		var leave: int = game.choices.map(func(o): return str(o.name)).find("离开")
		check(leave == game.choices.size() - 1 and not game.choices[leave].get("disabled", false), "离开 is the last option and selectable")
		game.kb_nav = false
		game.panel.visible = false
		_open("meeting")
	elif frames == 90:
		check(game.choices.size() <= 4, "small event (%d options)" % game.choices.size())
		check(_room() <= 1.0, "few options → no scrolling needed (room %.0f)" % _room())
		check(game.panel_scroll.scroll_vertical == 0, "small event starts at the top")
		print("EVENT FIT failures=%d" % failures)
		get_tree().quit(1 if failures else 0)
