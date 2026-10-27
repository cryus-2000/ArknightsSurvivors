extends Node
## 翻节点卡（docs/154 §6，取代海嗣祭坛）：
## 1 同 seed 两次卡组相同；2 路口一必出狂徒妄念与开端、路口二持信物必出对应后续卡（1000 个 seed）；3 首通前（玩家局）不开启；
## 4 互斥：路口一走了开端，路口二不出骑士仍在；5 结局判定只看信物、按优先级，灯火 0 / 100 不变；6 升华三句任意灯火都可选；
## 7 最晚时刻：中 Boss 不死时 6:30 / 8:40 照样弹，之后没有商人时诡意行商给源石锭；8 升级面板开着时到点，路口卡等它关掉再弹
var game: Node
var frames := 0
var fails := 0


func check(ok: bool, label: String) -> void:
	if not ok:
		fails += 1
		push_error(label)


func _ready() -> void:
	game = load("res://game.tscn").instantiate()
	add_child(game)


func _deck_ids(d: Array) -> Array:
	return d.map(func(c): return "%s/%s" % [c.type, c.get("event", "")])


func _reset_relics() -> void:
	game.relics.clear()
	game.rfx.lv.clear()
	game.knight_alive = false


func _process(_dt: float) -> void:
	frames += 1
	if frames != 5:
		return
	game.set_process(false)
	var E = game.endg
	E.enabled = true
	E._checked = true
	E.lines_on = true
	E.mid_done = 2   # 途中路口（docs/173）另在 event_trade_test 测
	# 1 同 seed 同卡组
	game.rng.seed = 4242
	var d1: Array = _deck_ids(E.build_deck(1))
	E.used_common.clear()
	game.rng.seed = 4242
	var d2: Array = _deck_ids(E.build_deck(1))
	check(d1 == d2, "same seed, same deck: %s vs %s" % [d1, d2])
	check(d1.size() == 3, "crossroad 1 deals 3 cards")
	# 2 必出
	_reset_relics()
	var miss1 := 0
	var miss2 := 0
	for sd in 1000:
		E.used_common.clear()
		game.rng.seed = sd + 1
		var ids: Array = _deck_ids(E.build_deck(1))
		if not (ids.has("incident/madness") and ids.has("incident/opening")):
			miss1 += 1
	check(miss1 == 0, "crossroad 1 always has madness + opening (missed %d)" % miss1)
	for line in [["220", "incident/heart"], ["242", "incident/ritual"]]:
		_reset_relics()
		game.relics.append(line[0])
		for sd in 1000:
			E.used_common.clear()
			game.rng.seed = sd + 1
			if not _deck_ids(E.build_deck(2)).has(line[1]):
				miss2 += 1
	_reset_relics()
	game.relics.append("222")
	game.knight_alive = true
	for sd in 200:
		E.used_common.clear()
		game.rng.seed = sd + 1
		if not _deck_ids(E.build_deck(2)).has("incident/knight_stay"):
			miss2 += 1
	check(miss2 == 0, "crossroad 2 always has the line follow-up (missed %d)" % miss2)
	# 3 首通前（玩家局）不开启
	var mode0 = game.mode
	var cleared0: Array = Cfg.endings_cleared.duplicate()
	game.mode = game.Mode.PLAY
	Cfg.endings_cleared.clear()
	check(not E._cross_on() or Cfg.dev_args().has("--allend"), "before clearing ending 1 the ending-line cards are off")
	Cfg.endings_cleared.append("standard")
	check(E._cross_on(), "after clearing ending 1 the ending-line cards are on")
	Cfg.endings_cleared = cleared0
	game.mode = mode0
	# 4 互斥：走了开端（持 220），路口二没有骑士仍在
	_reset_relics()
	game.relics.append("220")
	E.used_common.clear()
	game.rng.seed = 7
	var d4: Array = _deck_ids(E.build_deck(2))
	check(not d4.has("incident/knight_stay") and d4.has("incident/heart"), "deep line: no knight_stay at crossroad 2 (%s)" % [d4])
	# 5 判定只看信物
	var cases := [[[], false, "standard"], [["222"], true, "knight"], [["222"], false, "standard"], [["220", "221"], false, "deep"],
		[["242", "238"], false, "resolve"], [["242", "239"], false, "resolve"], [["242", "240"], false, "resolve"], [["222", "223"], true, "standard"]]
	for cs in cases:
		for lamp in [0.0, 100.0]:
			_reset_relics()
			for r in cs[0]:
				game.relics.append(r)
			game.knight_alive = cs[1]
			game.lamp = lamp
			check(E.judge() == cs[2], "judge %s knight=%s lamp=%d -> %s (got %s)" % [cs[0], cs[1], int(lamp), cs[2], E.judge()])
	# 6 升华三句任意灯火都可选
	_reset_relics()
	game.relics.append("242")
	for lamp in [0.0, 49.0, 90.0]:
		game.lamp = lamp
		E.open("ascend")
		var ok_n: int = game.choices.filter(func(o): return not o.get("disabled", false)).size()
		check(ok_n == 3, "ascend: all three answers selectable at lamp %d (got %d)" % [int(lamp), ok_n])
	game.panel.visible = false
	game.state = game.S.PLAY
	# 7 最晚时刻：中 Boss 一直活着，6:30 / 8:40 照样弹；8:40 时已无后续商人 → 诡意行商给源石锭
	_reset_relics()
	E.cross_done = 0
	E.cross_due = 0
	E.frozen = false
	game.final_boss = null
	game.pending_chests = 0
	var boss := {"dead": false}
	game.bosses = [boss]
	game.t = 300.0
	E.update(0.0)
	check(game.state == game.S.PLAY, "no crossroad before 3:30")
	game.t = 389.0
	E.update(0.0)
	check(game.state == game.S.PLAY, "boss alive at 6:29: still waiting")
	game.t = 390.5
	E.update(0.0)
	check(game.state == game.S.CHOICE and game.choice_kind == "cross" and E.cross_done == 1, "crossroad 1 forced at 6:30")
	game.panel.visible = false
	game.state = game.S.PLAY
	game.t = 520.5
	game.merchant_idx = 3
	E.update(0.0)
	check(game.state == game.S.CHOICE and E.cross_done == 2, "crossroad 2 forced at 8:40")
	E.deck = [{"type": "shop", "must": false, "ends": []}]
	E.flipped = -1
	var ing0: int = game.ingots
	E.flip(0)
	if E.redesign:
		game.bosses = []   # 上面造的假中 Boss 没有 type，关店横幅会读它
		# 事件改版（用户 10-28）：诡意行商 = 进一次商店，最后一位商人之后照样能开；关店回战斗
		check(game.state == game.S.SHOP and game.shop_sys.trader, "trader card opens a shop visit even after the last merchant")
		game.shop_sys.close()
		check(game.state == game.S.PLAY and not game.shop_sys.trader, "closing the trader shop returns to battle")
	else:
		check(game.ingots > ing0 and game.state == game.S.PLAY, "trader card after the last merchant gives ingots (%d -> %d)" % [ing0, game.ingots])
	# 8 升级面板开着时到点：等它关掉再弹
	E.cross_done = 0
	E.cross_due = 0
	game.state = game.S.CHOICE
	game.choice_kind = "level"
	game.t = 391.0
	E.update(0.0)
	check(game.choice_kind == "level" and E.cross_due == 1, "crossroad waits while a level-up panel is open")
	game.state = game.S.PLAY
	E.update(0.0)
	check(game.choice_kind == "cross", "crossroad opens after the panel closes")
	game.bosses = []
	print("NODE CARDS: %d failures" % fails)
	get_tree().quit(1 if fails > 0 else 0)
