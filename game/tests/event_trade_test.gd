extends Node
## 事件改版（docs/184 §7.2）：
## 1 同 seed 卡组相同（途中 / 路口一 / 路口二）；2 首通前（结局线关）路口里没有结局事件、途中路口 2 张；
## 3 每张桌面至少一张交易卡、最多一张无代价卡（300 seed × 3 种路口 × 结局线开 / 关）；4 选项代价与灰掉（生命 < 30%、需要队友、源石锭不足）；
## 5 主流派判定（藏品计数 ≥ 3 / 并列取最近 / 不足按队长职业）；6 委托：限时强敌到点解除并给奖励、击杀委托超时失败；
## 7 队友暂离 120 秒后原位归队并精英化一级；8 途中路口 1:20 起清场即弹、路口一晚于 6:00 时取消途中二；9 cross/redesign 开着
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


func _ids(d: Array) -> Array:
	return d.map(func(c): return "%s/%s" % [c.type, c.get("event", "")])


func _close() -> void:
	game.panel.visible = false
	game.state = game.S.PLAY


func _process(_dt: float) -> void:
	frames += 1
	if frames != 5:
		return
	game.set_process(false)
	var E = game.endg
	check(E.redesign, "cross/redesign defaults to on")
	E.enabled = true
	E._checked = true
	E.lines_on = true
	game.relics.clear()
	game.rfx.lv.clear()
	print("ET step 1")
	# 1 同 seed 同卡组
	for n in [0, 1, 2]:
		E.used_common.clear()
		game.rng.seed = 777
		var a: Array = _ids(E.build_deck(n))
		E.used_common.clear()
		game.rng.seed = 777
		var b: Array = _ids(E.build_deck(n))
		check(a == b, "same seed same deck (slot %d): %s vs %s" % [n, a, b])
	print("ET step 2")
	# 2 首通前：没有结局事件；途中 2 张
	E.lines_on = false
	var line_hits := 0
	for sd in 300:
		E.used_common.clear()
		game.rng.seed = sd + 1
		for c in E.build_deck(1) + E.build_deck(2):
			if c.get("must", false) or E.LINE_ENDS.has(str(c.get("event", ""))):
				line_hits += 1
	check(line_hits == 0, "before ending 1: no ending-line cards (%d)" % line_hits)
	E.used_common.clear()
	check(E.build_deck(0).size() == 2, "mid crossroad deals 2 cards")
	print("ET step 3")
	# 3 交易保底与无代价上限
	var bad := 0
	for lines in [false, true]:
		E.lines_on = lines
		for sd in 300:
			for n in [0, 1, 2]:
				E.used_common.clear()
				game.rng.seed = sd * 3 + n
				var d: Array = E.build_deck(n)
				var fills: Array = d.filter(func(c): return not c.get("must", false))
				var free_n: int = fills.filter(func(c): return c.type in ["rest", "shop"]).size()
				if fills.size() > 0 and (not fills.any(func(c): return E._is_trade(c)) or free_n > 1):
					bad += 1
					if bad <= 3:
						push_warning("deck %s" % [_ids(d)])
				if n == 0 and d.any(func(c): return c.type == "fog"):
					bad += 1
	check(bad == 0, "every deck has a trade card and at most one free card (%d bad)" % bad)
	E.lines_on = true
	print("ET step 4")
	# 4 选项代价与灰掉
	game.ingots = 30
	E.open("sellout")
	E.pick(game.choices[0])
	_close()
	check(game.ingots == 0 and game.relics.size() == 1 and game.RL[game.relics[0]].rarity == "核心", "sellout: all ingots -> one core relic (ingots %d, relics %s)" % [game.ingots, game.relics])
	game.hp = game.max_hp * 0.2
	E.open("sellout")
	var c1: Dictionary = game.choices.filter(func(o): return str(o.id) == "sellout:1")[0]
	check(c1.get("disabled", false), "hp cost option disabled below 30% hp")
	game.hp = game.max_hp
	_close()
	for o in game.squad.ops.duplicate():
		if not o.is_leader:
			game.squad.remove(o.id)
	E.open("expedition")
	check(game.choices[0].get("disabled", false), "expedition needs a teammate")
	_close()
	print("ET step 5")
	# 5 主流派
	game.relics.clear()
	game.rfx.lv.clear()
	var lead_lane: String = E.main_lane()
	check(lead_lane in ["A", "B", "E"], "no relics: lane from leader class (%s)" % lead_lane)
	var d_ids: Array = []
	for rid in game.RL:
		if (game.RL[rid].get("lanes", []) as Array) == ["D"] and d_ids.size() < 3:
			d_ids.append(rid)
	for rid in d_ids:
		game.relics.append(rid)
	check(d_ids.size() < 3 or E.main_lane() == "D", "three D relics -> main lane D (got %s)" % E.main_lane())
	game.relics.clear()
	print("ET step 6")
	# 6 委托
	game.t = 100.0
	var hp0: float = game.enemy_hp_mult
	E._apply_op({"threat": {"t": 90, "mult": 0.2, "name": "测试", "win": [{"ingots": 10}]}})
	check(absf(game.enemy_hp_mult - hp0 * 1.2) < 0.001, "threat raises enemy hp mult (%.3f -> %.3f)" % [hp0, game.enemy_hp_mult])
	var ing1: int = game.ingots
	game.t = 191.0
	E._tick_chal()
	check(E.chal.is_empty() and absf(game.enemy_hp_mult - hp0) < 0.001 and game.ingots > ing1, "threat ends at time, lifts and pays")
	E._apply_op({"kills": {"n": 100000, "t": 60, "name": "测试", "win": [{"ingots": 10}]}})
	var ing2: int = game.ingots
	game.t = 252.0
	E._tick_chal()
	check(E.chal.is_empty() and game.ingots == ing2, "kill contract fails on timeout without reward")
	print("ET step 7")
	# 7 暂离
	var mate = game.squad.add("lappland")
	check(mate != null, "add a teammate")
	if mate != null:
		E.sub_ctx = {"queue": [{"away": {"reward": [{"elite_up": "self"}]}}], "promoted": ""}
		E._sub_pick("away", "lappland")
		check(not game.squad.has("lappland") and E.away.size() == 1, "teammate leaves for the safe house")
		game.t += 121.0
		E._tick_away()
		var back = game.squad.get_op("lappland")
		check(back != null and back.elite >= 1, "teammate returns promoted (elite %s)" % [back.elite if back != null else -1])
	print("ET step 8")
	# 8 途中路口
	_close()
	E.mid_done = 0
	E.cross_done = 0
	E.cross_due = 0
	E.c1_deal_t = -1.0
	E.chal = {}
	E.elites.clear()
	game.bosses = []
	game.pending_chests = 0
	game.t = 70.0
	E._tick_mid()
	check(E.mid_done == 0, "no mid crossroad before 1:20")
	game.t = 81.0
	E._tick_mid()
	check(E.mid_done == 1 and game.choice_kind == "cross" and E.deck.size() == 2, "mid crossroad 1 at 1:20 when calm")
	_close()
	game.t = 365.0
	E._tick_mid()
	check(E.mid_done == 2 and game.state == game.S.PLAY, "crossroad 1 not dealt by 6:00 -> mid 2 cancelled")
	print("ET step 9")
	# 9 每件改版事件的每个选项都走一遍（含二级屏，机器人选完），之后委托 / 暂离到点结算，不报错、面板关回战斗
	var stat_rid := ""
	for rid in game.RL:
		if game.RL[rid].rarity == "基础" and (game.rfx.db.get_relic(rid).get("effects", []) as Array).all(func(ef): return ef.get("type", "stat") == "stat"):
			stat_rid = rid
			break
	var stuck := 0
	var ran := 0
	for ev in E.events:
		if not ev.get("v2", false) or ev.get("pool", "") != "common":
			continue
		for k in E._opts(ev).size():
			_close()
			E.chal = {}
			E.away.clear()
			E.searched.clear()
			E.sub_ctx = {}
			E.squad_reward = ""
			E.elites.clear()
			E.squad_pending.clear()
			game.stats.remove_source("event:threat")
			game.sync_stats()
			game.t = 200.0
			game.hp = game.max_hp
			game.ingots = 40
			game.pending_chests = 0
			game.pending_levelups = 0
			if not game.squad.has("lappland"):
				game.squad.add("lappland")
			if stat_rid != "" and not game.relics.has(stat_rid):
				game.progression.gain_relic(stat_rid)
			E.open(str(ev.id))
			var idx: int = -1
			for i in game.choices.size():
				if str(game.choices[i].id) == "%s:%d" % [ev.id, k]:
					idx = i
			if idx < 0 or game.choices[idx].get("disabled", false):
				continue
			game.progression.pick(idx)
			ran += 1
			var guard := 0
			while game.state == game.S.CHOICE and game.choice_kind == "event" and guard < 12:
				guard += 1
				game.progression.pick(maxi(0, E.bot_choice()))
			if guard >= 12:
				stuck += 1
				push_warning("stuck in %s:%d" % [ev.id, k])
			game.t += 200.0
			E._tick_chal()
			E._tick_away()
	_close()
	print("ET options run: %d" % ran)
	check(ran >= 40 and stuck == 0, "every v2 option resolves back to battle (%d stuck)" % stuck)
	print("ET step 10")
	# 10 诡意行商 = 进一次商店：地图上的商人与货架不受影响，买一件后关店回战斗
	_close()
	game.merchant = {"pos": game.ppos + Vector2(500, 0), "life": 40.0, "near": false, "purchases": 0}
	var real_items: Array = [{"kind": "oil", "id": "oil", "name": "灯油", "desc": "", "price": 5, "sold": false}]
	game.shop_items = real_items
	game.ingots = 200
	E.deck = [{"type": "shop", "must": false, "ends": []}]
	E.flipped = -1
	game.choice_kind = "cross"
	E.flip(0)
	check(game.state == game.S.SHOP and game.shop_sys.trader and game.shop_items != real_items and game.shop_items.size() >= 3, "trader card opens its own shop")
	var r0: int = game.relics.size()
	for i in game.shop_items.size():
		if game.shop_items[i].kind == "relic" and game.shop_sys.can_buy(game.shop_items[i]):
			game.shop_sys.buy(i)
			break
	check(game.relics.size() == r0 + 1 and int(game.merchant.get("purchases", 0)) == 0, "buying at the trader does not touch the map merchant")
	game.shop_sys.close()
	check(game.state == game.S.PLAY and game.shop_items == real_items and not game.merchant.is_empty(), "closing restores the map merchant and its shelf")
	game.merchant = {}
	game.shop_items = []
	print("EVENT TRADE: %d failures" % fails)
	get_tree().quit(1 if fails > 0 else 0)
