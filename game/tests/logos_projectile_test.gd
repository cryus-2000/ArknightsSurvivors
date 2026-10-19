extends Node
const OB = preload("res://scripts/characters/op_blocks.gd")
const Art = preload("res://scripts/art.gd")
var fails := 0

class TileCanvas extends RefCounted:
	var draws: Array = []
	func draw_set_transform(_pos, _angle, _scale) -> void:
		pass
	func draw_texture_rect_region(_tex, dst, src, col) -> void:
		draws.append({"dst": dst, "src": src, "col": col, "end_col": col})
	func draw_colored_polygon(points, col, _uvs, _texture) -> void:
		draws.append({"dst": Rect2(points[0], points[2] - points[0]), "col": col, "end_col": col, "points": points})

class TileOperator extends RefCounted:
	var g: Dictionary
	var cv := TileCanvas.new()
	func _cv_flush() -> void:
		pass

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
	for name in b.flight_visual.variants:
		check(float(Art.V6_FRAMES[name][1]) == float(b.flight_visual.fps), "renderer and registered flight rates agree")
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
	check(Art.V6_FRAMES.has("fx_logos_s1_chain") and g.tex.get("fx_logos_s1_chain") != null, "S1 rune chain is registered and loaded")
	var rune_image: Image = g.tex.fx_logos_s1_chain.get_image()
	var no_empty_columns := true
	for x in rune_image.get_width():
		var visible_column := false
		for y in rune_image.get_height():
			visible_column = visible_column or rune_image.get_pixel(x, y).a > 0.0
		if not visible_column:
			no_empty_columns = false
			break
	check(no_empty_columns, "adjacent rune glyphs leave no transparent column, including frame seams")
	check(o.cv.has_method("draw_colored_polygon"), "real render adapter supports textured rune geometry")
	var tile := TileOperator.new()
	tile.g = {"tex": g.tex, "V6_FRAMES": Art.V6_FRAMES, "draw_off": Vector2.ZERO, "t": 0.0}
	OB._hw_draw_tiled(tile, "fx_logos_s1_chain", Vector2.ZERO, Vector2(230, 0), 2.0, 17.0, 0, Color.WHITE, 0, true)
	var draws: Array = tile.cv.draws
	check(not draws.is_empty() and draws[0].dst.position.x == 0.0, "tiled rune packet clips exactly at its start")
	check(draws[0].col.a < draws.back().end_col.a and draws[0].col.r < draws.back().end_col.r, "rune chain smoothly brightens from caster tail to target head")
	for i in range(1, draws.size()):
		check(absf(draws[i - 1].dst.end.x - draws[i].dst.position.x) < 0.0001, "gradient subdivisions do not open gaps")
		check(draws[i].col.r >= draws[i - 1].col.r and draws[i].col.r - draws[i - 1].col.r < 0.06, "gradient advances smoothly across tile seams")
	tile.cv.draws.clear()
	OB._hw_draw_tiled(tile, "fx_logos_s1_chain", Vector2.ZERO, Vector2(230, 0), 2.0, 17.0, 0, Color.WHITE, 0, true, 12.0)
	var curved: Array = tile.cv.draws
	var start: Vector2 = (curved[0].points[0] + curved[0].points[3]) * 0.5
	var end: Vector2 = (curved.back().points[1] + curved.back().points[2]) * 0.5
	check(start.distance_to(Vector2.ZERO) < 0.001 and end.distance_to(Vector2(230, 0)) < 0.001, "curved rune stream remains attached to both endpoints")
	var middle: Vector2 = (curved[curved.size() / 2].points[0] + curved[curved.size() / 2].points[3]) * 0.5
	check(middle.y < -10.0 and middle.y >= -13.51, "rune stream follows a shallow curve")
	var curve_difference := 0.0
	for i in curved.size():
		var point: Vector2 = (curved[i].points[0] + curved[i].points[3]) * 0.5
		var t: float = point.x / 230.0
		curve_difference = maxf(curve_difference, absf(point.y + 48.0 * t * (1.0 - t)))
		if i > 0:
			check(curved[i - 1].points[1].distance_to(curved[i].points[0]) < 0.001, "slightly different rune curves remain joined at their edges")
	check(curve_difference > 0.35 and curve_difference <= 1.51, "adjacent runes vary gently within one and a half world pixels of the shared curve")
	tile.cv.draws.clear()
	OB._hw_draw_tiled(tile, "fx_logos_s1_chain", Vector2.ZERO, Vector2(230, 0), 2.0, 17.0)
	for draw in tile.cv.draws:
		check(draw.col == Color.WHITE, "existing tile callers retain uniform color")
	var pulse := {"t": 5.0, "n": 0, "tick": 0.125, "b": {"tick": 0.25}}
	var early: Array = OB.hw_s1_train_pose(pulse, Vector2.ZERO, Vector2(230, 0))
	check(early[0] == Vector2.ZERO and absf(early[1].x - 115.0) < 0.001, "S1 fills from the hand towards its first damage tick")
	for tick in 20:
		pulse.n = tick + 1
		for phase in [0.0, 0.01, 0.125, 0.249]:
			pulse.tick = phase
			var train: Array = OB.hw_s1_train_pose(pulse, Vector2.ZERO, Vector2(230, 0))
			check(not train.is_empty() and train[0] == Vector2.ZERO and train[1] == Vector2(230, 0), "successive S1 attacks stay connected across every damage boundary")
			check(train.size() == 4, "S1 returns an independent moving rune offset")
	pulse.n = 1
	pulse.tick = 0.0
	var first_train: Array = OB.hw_s1_train_pose(pulse, Vector2.ZERO, Vector2(230, 0))
	pulse.n = 2
	var next_train: Array = OB.hw_s1_train_pose(pulse, Vector2.ZERO, Vector2(230, 0))
	if first_train.size() == 4 and next_train.size() == 4:
		check(absf(next_train[3] - first_train[3] + 60.0) < 0.001, "runes advance sixty pixels towards the target every quarter-second")
	tile.cv.draws.clear()
	OB._hw_draw_tiled(tile, "fx_logos_s1_chain", Vector2.ZERO, Vector2(230, 0), 2.0, -17.0)
	check(tile.cv.draws[0].dst.position.x == 0.0 and absf(tile.cv.draws.back().dst.end.x - 230.0) < 0.001, "forward scrolling never leaves a gap at either endpoint")
	pulse.t = 0.0
	check(OB.hw_s1_train_pose(pulse, Vector2.ZERO, Vector2(230, 0)).is_empty(), "expired S1 leaves no persistent rune stream")
	e.dead = false
	g.enemies_sys.build_grid()
	o.cur_skill = 0
	var lock_block: Dictionary = o.B.skills[0].do[0]
	OB.hw_lock_start(o, lock_block)
	check(h.lock.e == e and float(h.lock.t) == 5.0, "S1 locks the live target for existing five seconds")
	var first_hit := 0.0
	var last_hit := 0.0
	for tick in 20:
		var hp: float = e.hp
		OB._hw3_lock(o, 0.25)
		check(int(h.lock.n) == tick + 1, "S1 deals exactly one hit per quarter-second")
		last_hit = hp - float(e.hp)
		if tick == 0:
			first_hit = last_hit
	check(first_hit > 0.0 and last_hit > first_hit, "S1 damage still ramps on the locked target")
	var final_hp: float = e.hp
	OB._hw3_lock(o, 0.25)
	check(float(h.lock.t) <= 0.0 and e.hp == final_hp, "S1 stops after twenty hits, without an extra expiry hit")
	OB.hw_lock_start(o, lock_block)
	e.dead = true
	OB._hw3_lock(o, 0.25)
	check(float(h.lock.t) <= 0.0 and h.lock.e == null, "dead target ends unupgraded S1 immediately")
	h.lock.clear()
	o.pfx.clear()
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
