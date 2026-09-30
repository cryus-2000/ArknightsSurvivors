extends Node
var g
var failures := 0
func expect(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAIL ", label)
func _ready() -> void:
	g = load("res://game.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	g.zone_state = 3
	g.zone_c = Vector2(100, 50)
	g.zone_r = 250.0
	g.zone_frozen = false
	g.ppos = Vector2(1000, 50)
	for mode in ["walk", "knockback", "charge", "transition"]:
		g.enemies.clear()
		var e: Dictionary = g.spawner.new_enemy("knight_boss", Vector2(320, 50))
		e.age = 5.0
		e.spd = 1000.0
		e.bt = -100.0
		e.cdt = 100.0
		e.kb = Vector2(1800, 0) if mode != "walk" else Vector2.ZERO
		e.kb_self = mode == "charge"
		g.zone_frozen = mode == "transition"
		g.zone_next_c = Vector2(700, 50)
		g.zone_next_r = 400.0
		g.enemies.append(e)
		g.enemies_sys.build_grid()
		g.enemies_sys.update(0.2)
		expect(e.pos.distance_to(g.zone_c) <= g.zone_r - e.r + 0.001, mode + " stays inside visible circle")
	g.enemies.clear()
	var charge: Dictionary = g.spawner.new_enemy("knight_boss", g.zone_c)
	charge.bt = -100.0
	charge.cdt = 100.0
	charge.spd = 0.0
	charge.kb = Vector2(200, 0)
	charge.kb_self = true
	g.enemies.append(charge)
	g.enemies_sys.build_grid()
	g.enemies_sys.update(0.1)
	expect(charge.pos.x > g.zone_c.x + 15.0, "legal charge retains full self propulsion")
	g.zone_state = 0
	g.enemies.clear()
	var free: Dictionary = g.spawner.new_enemy("knight_boss", Vector2(900, 50))
	free.bt = -100.0
	free.cdt = 100.0
	g.enemies.append(free)
	g.enemies_sys.build_grid()
	g.enemies_sys.update(0.01)
	expect(free.pos.x > 800.0, "no invisible constraint before tide")
	print("BOSS BOUNDARY failures=", failures)
	g.queue_free()
	g = null
	await get_tree().process_frame
	get_tree().quit.call_deferred(0 if failures == 0 else 1)
