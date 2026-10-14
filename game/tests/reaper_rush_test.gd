extends Node
## Reaper wound transition: one scythe pair, accelerated pursuit, bounded nerve ripple.
var g: Node
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func _ready() -> void:
	g = load("res://game.tscn").instantiate()
	add_child(g)
	call_deferred("run_checks")

func run_checks() -> void:
	g.set_process(false)
	g.t = 120.0
	g.ppos = Vector2(210, 0)
	var e: Dictionary = g.spawner.new_enemy("reaper", Vector2.ZERO)
	var base_speed: float = e.spd
	e.hp -= 1.0
	g.eai.pattern(e, Vector2.RIGHT, 210.0, 0.016, base_speed)
	check(e.enraged, "first hit activates reaper rush")
	check(e.spd > base_speed and e.spd <= base_speed * 1.6, "rush speed rises but stays bounded")
	check(e.wake_t > 0.0, "scythes unfold before rush")
	var normal: Dictionary = g.spawner.new_enemy("reaper", Vector2.ZERO)
	g.eai.pattern(normal, Vector2.RIGHT, 200.0, 0.016, normal.spd)
	check(not normal.dormant and not normal.enraged, "proximity wake does not trigger wounded rush")
	var crowded: Dictionary = g.spawner.new_enemy("reaper", Vector2.ZERO)
	crowded.dormant = false
	crowded.age = 5.0
	crowded.extra_next = 0.0
	crowded.hp -= 1.0
	g.eai.pattern(crowded, Vector2.RIGHT, 200.0, 0.016, crowded.spd)
	check(crowded.enraged, "wound transition is immediate even when secondary is ready")
	e.wake_t = 0.0
	g.ppos = Vector2(80, 0)
	g.nerve_aura_t = 0.0
	g.eai.pattern(e, Vector2.RIGHT, 80.0, 0.5, e.spd)
	check(g.nerve_aura_t > 0.0, "nearby reaper creates nerve ripple")
	g.nerve_aura_t = 0.0
	g.ppos = Vector2(160, 0)
	g.eai.pattern(e, Vector2.RIGHT, 160.0, 0.5, e.spd)
	check(g.nerve_aura_t == 0.0, "ripple does not damage outside radius")
	if failures == 0:
		print("PASS: reaper rush")
	get_tree().quit(1 if failures else 0)
