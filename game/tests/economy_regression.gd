extends Node
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
func choose(ev: String, suffix: String) -> void:
	game.endg.open(ev)
	for i in game.choices.size():
		if str(game.choices[i].id).ends_with(suffix):
			game.progression.pick(i)
			return
	check(false, "missing event choice " + ev + suffix)
func _process(_dt: float) -> void:
	frames += 1
	if frames != 5:
		return
	game.set_process(false)
	game.pending_levelups = 0
	game.pending_chests = 0
	game.show_queue.clear()
	game.endg.all_unlocked = true
	# Wave pricing and per-purchase escalation use actual purchase/stock paths.
	game.shop_price_mult = 1.0
	game.merchant = {"pos": Vector2.ZERO, "life": 60.0, "near": true, "purchases": 0}
	game.merchant_idx = 1
	check(game.shop_sys.price("heal") == 6, "first merchant retains baseline price")
	game.merchant_idx = 2
	check(game.shop_sys.price("heal") == 9, "second merchant costs 1.5x")
	game.merchant_idx = 3
	check(game.shop_sys.price("heal") == 12, "third merchant costs 2x")
	game.ingots = 100
	game.shop_sys.roll()
	game.state = game.S.SHOP
	var heal_slot: int = game.shop_items.size() - 2
	game.shop_sys.buy(heal_slot)
	check(game.ingots == 88, "charges displayed price once")
	check(game.shop_sys.price("heal") == 15, "next purchase escalates remaining stock")
	var purchases: int = game.merchant.purchases
	game.shop_sys.refresh()
	check(game.merchant.purchases == purchases, "refresh cannot reset purchase escalation")
	game.ingots = 1000
	# 缺省不限购（用户 10-11）：连买三件藏品都成交，只靠涨价与藏品栏容量软限制
	check(game.shop_sys.relic_buy_unlimited(), "relic purchases are unlimited by default")
	game.shop_sys.buy(0)
	game.shop_sys.buy(1)
	var before_third: int = game.ingots
	game.shop_sys.buy(2)
	check(game.shop_items[2].sold and game.ingots < before_third, "third relic can be purchased when unlimited")
	# 旧的硬上限仍可用旋钮打开：shop/relic_buy_limit = 2
	var Bal = preload("res://scripts/core/balance.gd")
	Bal.v("shop/relic_buy_limit", -1.0)   # 确保已加载
	Bal._data["shop"]["relic_buy_limit"] = 2.0
	check(not game.shop_sys.relic_buy_unlimited() and game.shop_sys.relic_buys_left() == 0, "knob 2 restores the two-relic limit")
	game.shop_refreshed = false
	game.shop_sys.refresh()
	check(game.shop_sys.relic_buys_left() == 0, "refresh cannot reset the two-relic limit")
	Bal._data["shop"]["relic_buy_limit"] = -1.0
	# Merchant / event positions are safe even for player standing at/outside an edge.
	game.zone_state = 2
	game.zone_c = Vector2(100, -80)
	game.zone_r = 650.0
	for angle in 12:
		game.ppos = game.zone_c + Vector2.from_angle(angle * TAU / 12.0) * 640.0
		var p: Vector2 = game.spawner.event_pos(520.0, 650.0, 110.0)
		check(p.distance_to(game.zone_c) <= 540.01, "event pos begins inside tide")
		check(p.distance_to(game.ppos) >= 519.99, "event pos begins away from player")
	game.merchant.pos = game.zone_c + Vector2(600, 0)
	game.zone_r = 300.0
	game.shop_sys.update(0.01)
	check(game.merchant.pos.distance_to(game.zone_c) <= 200.01, "merchant follows shrinking tide")
	game.zone_state = 0
	# Elite chance is nontrivial and repeatable; the combat drop function uses g.rng_drop (docs/101 B7).
	# 概率跟 relic/elite_drop_chance 走；relic/elite_drop_from 秒前不掉（docs/191），这里先测门槛后
	var t_save: float = game.t
	var pc: float = Bal.v("relic/elite_drop_chance", 0.3)
	game.t = 0.0
	game.rng_drop.seed = 1717
	var early: int = 0
	for i in 200:
		if game.combat.elite_drops_relic():
			early += 1
	check(Bal.v("relic/elite_drop_from", 0.0) <= 0.0 or early == 0, "no elite chest before relic/elite_drop_from")
	game.t = maxf(t_save, Bal.v("relic/elite_drop_from", 0.0) + 1.0)
	var outcomes: Array = []
	game.rng_drop.seed = 1717
	for i in 1000:
		outcomes.append(game.combat.elite_drops_relic())
	var count: int = outcomes.count(true)
	check(absf(count - 1000.0 * pc) < 60.0 and count < 1000, "elite relic drops near relic/elite_drop_chance, never guaranteed")
	game.rng_drop.seed = 1717
	for i in 1000:
		check(game.combat.elite_drops_relic() == outcomes[i], "elite chance repeats by seed")
	game.t = t_save
	# Front curve unchanged; later costs grow smoothly instead of a hard time gate.
	for level in 12:
		var lv := level + 1
		var old: float = 24 + lv * 8 + floor(lv * lv * 0.8)
		check(is_equal_approx(game.pickups.xp_required(lv), old), "early XP unchanged")
	check(game.pickups.xp_required(30) >= 984 * 1.64, "late XP slows growth")
	for lv in range(12, 40):
		check(game.pickups.xp_required(lv + 1) > game.pickups.xp_required(lv), "XP curve stays monotonic")
	# 藏品缺省不设上限（用户 10-12）；下面这段旧规则（15 件 + 结局信物预留槽）只在测试旋钮 relic/carry_cap = 15 时生效，照旧验证
	var file_cap: int = Bal.vi("relic/carry_cap", 999)
	check(file_cap < 0, "balance.json: relic carry cap defaults to unlimited")
	if not Bal._data.has("relic"):
		Bal._data["relic"] = {}
	Bal._data["relic"]["carry_cap"] = 15
	# Fill ordinary slots, then follow knight / resolve / deep sequence without blocking routes.
	var ordinary: Array = game.rfx.db.implemented().filter(func(r): return r.rarity != "结局" and r.get("source", "any") != "event" and r.effects.all(func(ef): return ef.get("type", "stat") == "stat"))
	# 翻节点卡（docs/154）：还没翻的路口各留 1 格给结局线信物
	game.endg.enabled = true
	game.endg._checked = true
	game.endg.lines_on = true   # 结局线入口开（docs/173：改版后翻卡一直开，结局线另算）
	check(game.endg.reserved_relic_slots() == 2, "two crossroads reserve one route slot each")
	for r in ordinary:
		game.progression.gain_relic(r.id)
	check(game.relics.size() == 13, "normal acquisitions leave two route slots")
	game.t = 250.0
	game.endg.cross_done = 1
	choose("madness", ":0")
	check(game.relics.has("222") and game.knight.alive, "full ordinary bag still admits knight")
	game.t = 450.0
	game.endg.cross_done = 2
	choose("knight_stay", ":1")
	check(game.relics.has("225") and game.endg.cur == "knight", "full bag still admits the knight follow-up")
	game.pending_chests = 0
	game.t = 561.0
	for r in ordinary:
		game.progression.gain_relic(r.id)
	check(game.relics.size() >= 14, "used crossroads release their slots (%d)" % game.relics.size())
	check(game.relics.size() <= 15, "hard collection cap")
	for rid in game.guide.relic_pool_ids(true):
		check(game.relics.has(rid), "full bag only offers upgrades")
	var new_id := ""
	for r in ordinary:
		if not game.relics.has(r.id):
			new_id = r.id
			break
	game.state = game.S.SHOP
	game.shop_items = [{"kind":"relic", "id":new_id, "sold":false, "price":5}]
	var before: int = game.ingots
	game.shop_sys.buy(0)
	check(game.ingots == before and not game.shop_items[0].sold, "stale full-bag purchase does not charge")
	for rid in game.relics:
		game.rfx.lv[rid] = game.rfx.max_lv(rid)
	game.pending_chests = 2
	game.state = game.S.PLAY
	before = game.ingots
	game.progression.open_relic_choice()
	check(game.pending_chests == 0 and game.ingots == before + 24 and game.state == game.S.PLAY, "no upgrade candidates converts rewards without empty modal")
	# 不设上限（缺省）：同一局继续拿到 40 件以上，三选一 / 商人照常出新藏品、照常成交
	Bal._data["relic"]["carry_cap"] = -1
	check(game.progression.relic_count_text() == "藏品 %d" % game.relics.size(), "uncapped count text has no slash")
	var passive: Array = game.rfx.db.implemented().filter(func(r): return r.rarity != "结局" and r.get("source", "any") == "any" and r.effects.all(func(ef): return ef.get("type", "stat") in ["stat", "rule"]))
	for r in passive:
		if game.relics.size() >= 40:
			break
		game.progression.gain_relic(r.id)
	check(game.relics.size() >= 40, "uncapped: 40 relics can be held (%d)" % game.relics.size())
	var offers: Array = game.guide.relic_pool_ids()
	check(offers.any(func(x): return not game.relics.has(x)), "uncapped: chest offers still include new relics at 40")
	check(offers.size() >= 3, "uncapped: offer pool not degraded")
	var new2 := ""
	for r in passive:
		if not game.relics.has(r.id):
			new2 = r.id
			break
	if new2 != "":
		game.state = game.S.SHOP
		game.ingots = 99
		game.shop_items = [{"kind":"relic", "id":new2, "name":game.rfx.display_name(new2), "desc":game.rfx.display_desc(new2), "sold":false, "price":5}]
		var n40: int = game.relics.size()
		game.shop_sys.buy(0)
		check(game.relics.size() == n40 + 1 and game.shop_items[0].sold, "uncapped: merchant sells a new relic at 40+")
		game.state = game.S.PLAY
	print("ECONOMY REGRESSION: ", fails, " failures; elite successes=", count)
	game.queue_free()
	game = null
	await get_tree().process_frame
	Sfx.set_process(false)
	await get_tree().create_timer(0.25, true, false, true).timeout
	for player in Sfx.get_children():
		if player is AudioStreamPlayer:
			player.stop()
			player.stream = null
			player.queue_free()
	await get_tree().create_timer(0.2, true, false, true).timeout
	get_tree().quit(fails)
