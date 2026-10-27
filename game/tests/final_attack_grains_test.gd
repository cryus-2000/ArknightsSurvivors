extends Node
var failures := 0
const Beam = preload("res://scripts/render/boss_beam.gd")

class Pool extends RefCounted:
	var level := 2
	var active := true
	var calls: Array = []
	func on() -> bool: return active
	func push(kind: String, pos: Vector2, direction: Vector2, color: Color) -> void:
		calls.append([kind, pos, direction, color])

func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: ", label)

func _ready() -> void:
	var path := "res://scripts/render/final_attack_grains.gd"
	check(ResourceLoader.exists(path), "final attacks have material particle integration")
	if ResourceLoader.exists(path):
		var fx = load(path)
		var pool := Pool.new()
		var visual := RandomNumberGenerator.new()
		visual.seed = 91
		var gameplay := RandomNumberGenerator.new()
		gameplay.seed = 28
		var g := {"optical": {"grains": pool}, "perf_alt": false, "vrng": visual, "rng": gameplay, "combat": {"GROUND_Y": 0.62}}
		var quality: String = Cfg.quality
		Cfg.quality = "high"
		var state := gameplay.state
		for skin in ["bubble", "phantom", "ice", "ice_field", "ice_wave", "ice_thrust", "ice_lance", "ice_wall", "crescent", "step", "spear", "choir", "tentacle", "tide"]:
			var w := {"skin": skin, "shape": "circle" if skin == "bubble" else "line", "pos": Vector2(400, 300), "ang": 0.2,
				"r": 26.0, "wid": 18.0, "len": 400.0, "age": 0.1, "life": 2.0, "velocity": Vector2(50, 0), "col": Color(0.4, 0.8, 1)}
			var original := w.duplicate(true)
			Beam._tok = 160
			Beam._tok_us = Time.get_ticks_usec()
			pool.calls.clear()
			fx.burst(g, w)
			fx.trail(g, w, 0.05)
			check(not pool.calls.is_empty(), skin + " emits material particles")
			check(w == original, skin + " leaves attack data unchanged")
			check(gameplay.state == state, skin + " leaves gameplay RNG unchanged")
			check(pool.calls.all(func(p): return p[1].is_finite() and p[2].is_finite()), skin + " finite positions")
			Beam._tok = 3
			Beam._tok_us = Time.get_ticks_usec()
			pool.calls.clear()
			fx.burst(g, w)
			check(pool.calls.size() <= 4, skin + " respects shared Boss token budget")
			Cfg.quality = "low"
			pool.calls.clear()
			fx.burst(g, w)
			fx.trail(g, w, 0.2)
			check(pool.calls.is_empty(), skin + " low quality preserves particle budget")
			Cfg.quality = "high"
		check_safe_centers(fx, g, pool)
		Cfg.quality = quality
	print("FINAL ATTACK GRAINS failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func check_safe_centers(fx, g: Dictionary, pool: Pool) -> void:
	var ring := {"skin":"abyss", "shape":"circle", "pos":Vector2(250, 300), "r":240.0, "inner_r":228.0, "col":Color.CYAN}
	Beam._tok = 160
	Beam._tok_us = Time.get_ticks_usec()
	pool.calls.clear()
	fx.burst(g, ring)
	check(not pool.calls.is_empty(), "narrow annulus emits outside its safe center")
	for particle in pool.calls:
		var offset: Vector2 = particle[1] - ring.pos
		var unprojected := Vector2(offset.x, offset.y / g.combat.GROUND_Y)
		check(unprojected.length() >= 232.0 and unprojected.length() <= 240.001, "annulus uses actual ground projection and inner margin")
		var normal := Vector2(unprojected.x, unprojected.y / g.combat.GROUND_Y).normalized()
		check(normal.dot(particle[2]) > 0.99, "annular glints move outward from the safe center")
		check(particle[0] == "bfx_flash", "annular glints have no gravity toward the safe center")
	pool.calls.clear()
	fx.finish(g, ring)
	check(pool.calls.is_empty(), "annular finish creates no inner spray")
	var wall := {"skin":"tide", "shape":"line", "pos":Vector2.ZERO, "ang":0.7, "len":300.0, "wid":19.0,
		"age":0.1, "velocity":Vector2.from_angle(0.7).orthogonal() * 150, "col":Color.CYAN}
	Beam._tok = 160
	Beam._tok_us = Time.get_ticks_usec()
	fx.burst(g, wall)
	fx.trail(g, wall, 0.05)
	var axis := Vector2.from_angle(wall.ang)
	for particle in pool.calls:
		var along: float = particle[1].dot(axis)
		check(along >= 23.99 and along <= wall.len - 23.99, "tide particles leave a gap-end drift margin")
	pool.calls.clear()
	fx.finish(g, wall)
	check(pool.calls.is_empty(), "tide finish does not scatter into its gap")
