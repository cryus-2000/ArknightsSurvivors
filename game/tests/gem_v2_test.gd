extends Node
const Bal = preload("res://scripts/core/balance.gd")
const Game = preload("res://scripts/game.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func _ready() -> void:
	var g = Game.new()
	var r: Dictionary = Bal.sec("render")
	r.gem_cap_n = 3
	for i in 3:
		g.pickups.drop(Vector2(i * 100, 0), "xp", 1.0 if i == 0 else 5.0)
		g.gems[-1].z = 0.0
		g.gems[-1].vz = 0.0
	var before: float = g.pickups.xp_on_ground()
	r.gem_cap = 1
	g.pickups.drop(Vector2.ZERO, "xp", 2.0)
	check(g.gems.size() == 3, "cap merges without new object")
	check(g.gems[1].val == 7.0 and g.gems[0].val == 1.0, "nearest eligible large XP preferred")
	check(g.pickups.xp_on_ground() == before + 2.0 and g.pickups.xp_dropped == before + 2.0, "XP conservation")
	g.gems[1].mag = true
	g.pickups.drop(Vector2.ZERO, "xp", 3.0)
	check(g.gems[2].val == 8.0, "never merge into magnetic XP")
	for item in g.gems:
		item.mag = true
	g.pickups.drop(Vector2.ZERO, "xp", 4.0)
	check(g.gems.size() == 4, "all in flight keeps normal drop")
	r.gem_cap = 0
	g.pickups.drop(Vector2.ZERO, "xp", 2.0)
	check(g.gems.size() == 5, "off retains normal drop")
	check(g.pickups.xp_on_ground() == g.pickups.xp_dropped, "total conserved after all cases")
	g.gems.clear()
	r.gem_cap = 1
	for i in 3:
		g.pickups.drop(Vector2(i * 100, 0), "xp", 1.0)
		g.gems[-1].z = 0.0
		g.gems[-1].vz = 0.0
	g.pickups.drop(Vector2(95, 0), "xp", 2.0)
	check(g.gems.size() == 3 and g.gems[1].val == 3.0, "no large XP promotes nearest small XP")
	g.gems[0].dead = true
	g.pickups.dead_n += 1 # Same invalidation used by collection and recall.
	g.pickups.drop(Vector2.ZERO, "xp", 1.0)
	check(g.gems.size() == 4, "dead XP does not count toward cap")
	# A nearby small gem wins over a large gem beyond the configured radius.
	g.gems.clear()
	g.t += 0.01
	r.gem_cap = 0
	r.gem_cap_radius = 400.0
	for point in [Vector2(401, 0), Vector2(60, 0), Vector2(30, 0)]:
		g.pickups.drop(point, "xp", 10.0 if point.x > 400 else 1.0)
		g.gems[-1].z = 0.0
		g.gems[-1].vz = 0.0
	r.gem_cap = 1
	g.pickups.drop(Vector2.ZERO, "xp", 2.0)
	check(g.gems.size() == 3 and g.gems[2].val == 3.0 and g.gems[0].val == 10.0, "nearest local small beats out-of-radius large")
	g.pickups.drop(Vector2(2000, 0), "xp", 2.0)
	check(g.gems.size() == 4, "no target in radius falls back to normal drop")
	g.gems[0].pos = Vector2(400, 0)
	g.pickups.drop(Vector2.ZERO, "xp", 2.0)
	check(g.gems[0].val == 12.0, "radius boundary inclusive and eligible large preferred")
	check(g.pickups.xp_on_ground() == 18.0, "bounded merges preserve all fixture XP")
	var previous := 0.0
	for value in [1.0, 2.0, 5.0, 20.0]:
		var bright: Color = g.world._gem_v2_color(value, false)
		var dark: Color = g.world._gem_v2_color(value, true)
		var luminance: float = bright.r * 0.2126 + bright.g * 0.7152 + bright.b * 0.0722
		check(luminance > previous, "higher value brighter")
		check(dark.g < bright.g and dark.a == 1.0, "rest dims RGB without fading silhouette")
		previous = luminance
	g.free()
	print("GEM_V2 failures=", failures)
	get_tree().quit(1 if failures else 0)
