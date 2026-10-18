extends Node
const OB = preload("res://scripts/characters/op_blocks.gd")
const Art = preload("res://scripts/art.gd")
var fails := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", label)

func _ready() -> void:
	var g = load("res://game.tscn").instantiate()
	add_child(g)
	for i in 5:
		await get_tree().process_frame
	g.set_process(false)
	var o = g.squad.get_op("logos")
	assert(o != null)
	o.pos = g.ppos
	var h: Dictionary = OB._hw3(o)
	for e in g.enemies:
		e.dead = true
	g.enemies.clear()
	g.enemies_sys.build_grid()
	var b: Dictionary = o.B.attack.duplicate(true)
	var before: Dictionary = b.duplicate(true)
	check(not OB.hw_bolt_fire(o, b, true), "no target does not attack")
	var e: Dictionary = g.spawner.spawn_enemy("stone", o.pos + Vector2(200, 0))
	e.hp = 1000000.0
	e.max_hp = e.hp
	g.enemies_sys.build_grid()
	for expected in [0, 1, 0]:
		var first: int = h.word_q.size()
		check(OB.hw_bolt_fire(o, b, true), "targeted attack succeeds")
		check(h.word_q.size() == first + 1, "one ordinary bolt queued")
		check(int(h.word_q.back().get("variant", -1)) == expected, "successful basic attacks alternate A/B")
	var extra: Dictionary = g.spawner.spawn_enemy("stone", o.pos + Vector2(220, 0))
	extra.hp = e.hp
	g.enemies_sys.build_grid()
	b.count = 2
	var first: int = h.word_q.size()
	OB.hw_bolt_fire(o, b, true)
	check(h.word_q.size() == first + 2, "extra-target attack queues both bolts")
	for q in h.word_q.slice(first):
		check(int(q.get("variant", -1)) == 1, "one attack shares one variant across extra targets")
	b.count = before.count
	check(b == before, "visual selection does not mutate shared block data")
	h.word_q.clear()
	OB.hw_bolt_fire(o, b, false)
	check(int(h.word_q.back().get("variant", -1)) == -1, "non-basic skill bolts keep their own appearance")
	check(Art.V6_FRAMES.has("proj_logos_ink_a") and Art.V6_FRAMES.has("proj_logos_ink_b"), "both frame strips are registered")
	var rng_before: Array = g.rng_states()
	for variant in [0, 1]:
		var bolt := {"pos": Vector2(100, 0), "to": Vector2(200, 0), "b": b,
			"visual": {"start": Vector2.ZERO, "u": 0.0, "variant": variant}}
		check(OB.hw_bolt_pose(bolt)[0] == Vector2.ZERO, "arc starts exactly at hand")
		bolt.visual.u = 1.0
		check(OB.hw_bolt_pose(bolt)[0] == bolt.to, "arc ends exactly at target")
		bolt.visual.u = 0.5
		var point: Vector2 = OB.hw_bolt_pose(bolt)[0]
		check(point.y < 0 if variant == 0 else point.y > 0, "A rises above, B bends below the flight axis")
		check(absf(float(OB.hw_bolt_pose(bolt)[1])) < 0.001, "apex faces along flight axis")
	check(g.rng_states() == rng_before, "visual arc does not consume gameplay RNG")
	h.word_q.clear()
	OB.hw_bolt_fire(o, b, true)
	var hand: Vector2 = OB._hw_bolt_tip(o, b)
	OB._hw3_bolts(o, 0.05)
	check(h.bolts.size() == 1 and h.bolts[0].has("visual"), "queued variant reaches live bolt")
	if not h.bolts.is_empty():
		var bolt: Dictionary = h.bolts[0]
		check(absf(bolt.pos.distance_to(hand) - float(b.speed) * 0.05) < 0.001, "logical bolt retains existing speed")
		check(bolt.hist[0] == hand and bolt.visual.hist[0] == hand, "logical and visual histories retain launch anchor")
	var next: int = h.bolt_variant
	for enemy in g.enemies:
		enemy.dead = true
	g.enemies_sys.build_grid()
	check(not OB.hw_bolt_fire(o, b, true) and h.bolt_variant == next, "no-target retry does not advance A/B")
	print("LOGOS PROJECTILES failures=", fails)
	h.word_q.clear()
	h.bolts.clear()
	o = null
	g.world._gc_sink = null
	var hud = g.hud_view
	for section in [hud.bars, hud.relics, hud.squad, hud.banners]:
		section.h = null
	g.queue_free()
	await get_tree().process_frame
	hud._layers.clear()
	get_tree().quit(1 if fails else 0)
