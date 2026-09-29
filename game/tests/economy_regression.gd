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
	game.shop_sys.buy(0)
	game.shop_sys.buy(1)
	check(game.shop_sys.relic_buys_left() == 0, "two relic purchases exhaust this visit")
	var limited_gold: int = game.ingots
	game.shop_sys.buy(2)
	check(game.ingots == limited_gold and not game.shop_items[2].sold, "third relic cannot be purchased")
	game.shop_refreshed = false
	game.shop_sys.refresh()
	check(game.shop_sys.relic_buys_left() == 0, "refresh cannot reset two-relic limit")
	# Merchant and altar positions are safe even for player standing at/outside an edge.
	game.zone_state = 2
	game.zone_c = Vector2(100, -80)
	game.zone_r = 650.0
	for angle in 12:
		game.ppos = game.zone_c + Vector2.from_angle(angle * TAU / 12.0) * 640.0
		var p: Vector2 = game.spawner.event_pos(520.0, 650.0, 110.0)
		check(p.distance_to(game.zone_c) <= 540.01, "altar begins inside tide")
		check(p.distance_to(game.ppos) >= 519.99, "altar begins away from player")
	game.merchant.pos = game.zone_c + Vector2(600, 0)
	game.zone_r = 300.0
	game.shop_sys.update(0.01)
	check(game.merchant.pos.distance_to(game.zone_c) <= 200.01, "merchant follows shrinking tide")
	game.endg._spawn_box(game.endg.events[0])
	game.zone_r = 220.0
	game.endg.update(0.01)
	for e in game.enemies:
		if e.chest and not e.dead and e.get("event", "") != "":
			check(e.pos.distance_to(game.zone_c) <= 110.01, "altar follows shrinking tide")
			e.dead = true
	game.zone_state = 0
	# Elite chance is nontrivial and repeatable; the combat drop function uses g.rng.
	var outcomes: Array = []
	game.rng.seed = 1717
	for i in 1000:
		outcomes.append(game.combat.elite_drops_relic())
	var count: int = outcomes.count(true)
	check(count > 240 and count < 360, "elite relic drops near 30%, never guaranteed")
	game.rng.seed = 1717
	for i in 1000:
		check(game.combat.elite_drops_relic() == outcomes[i], "elite chance repeats by seed")
	# Front curve unchanged; later costs grow smoothly instead of a hard time gate.
	for level in 12:
		var lv := level + 1
		var old: float = 24 + lv * 8 + floor(lv * lv * 0.8)
		check(is_equal_approx(game.pickups.xp_required(lv), old), "early XP unchanged")
	check(game.pickups.xp_required(30) >= 984 * 1.64, "late XP slows growth")
	for lv in range(12, 40):
		check(game.pickups.xp_required(lv + 1) > game.pickups.xp_required(lv), "XP curve stays monotonic")
	# Fill ordinary slots, then follow knight / resolve / deep sequence without blocking routes.
	var ordinary: Array = game.rfx.db.implemented().filter(func(r): return r.rarity != "结局" and r.get("source", "any") != "event" and r.effects.all(func(ef): return ef.get("type", "stat") == "stat"))
	check(game.endg.reserved_relic_slots() == 4, "only four core route tokens reserve slots")
	for r in ordinary:
		game.progression.gain_relic(r.id)
	check(game.relics.size() == 11, "normal acquisitions leave four core route slots")
	game.t = 160.0
	game.endg.done.append("madness")
	choose("madness", ":0")
	check(game.relics.has("222") and game.knight.alive, "full ordinary bag still admits knight")
	game.t = 245.0
	game.endg.done.append("resolve1")
	game.endg.open("resolve1")
	check(not game.choices.any(func(c): return str(c.id).ends_with(":1")), "optional observation cannot steal a core route slot")
	choose("resolve1", ":0")
	check(game.endg.cur == "knight", "knight route priority preserved")
	game.t = 370.0
	game.endg.done.append("whisper")
	choose("whisper", ":0")
	check(game.relics.has("221") and game.relics.has("223") and game.endg.cur == "deep", "reserved slots admit deep route and knight departure")
	game.t = 450.0
	game.endg.done.append("resolve2")
	choose("resolve2", ":0")
	check(game.rfx.lv.get("238", 0) == 2 and game.endg.cur == "resolve", "second resolve upgrades at capacity and unlocks third ending")
	game.t = 525.0
	game.endg.done.append("memory")
	game.endg.open("memory")
	check(not game.choices.any(func(c): return str(c.id).ends_with(":0")), "full bag hides optional memory instead of empty reward")
	choose("memory", ":1")
	game.pending_chests = 0
	game.t = 561.0
	for r in ordinary:
		game.progression.gain_relic(r.id)
	check(game.relics.size() == 15, "expired reservations release slots up to fifteen")
	check(game.relics.size() <= 15, "hard collection cap")
	for rid in game.progression.relic_pool_ids(true):
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
