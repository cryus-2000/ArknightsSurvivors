extends Node
var failures := 0
const Beam = preload("res://scripts/render/boss_beam.gd")

class Pool extends RefCounted:
	var level := 2
	var active := true
	var calls: Array = []
	func on() -> bool: return active
	func push(kind: String, pos: Vector2, direction: Vector2, color: Color, delay := 0.0, ground := INF) -> void:
		calls.append([kind, pos, direction, color, delay, ground])

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
		check_knight_ice(fx, g, pool, gameplay)
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

## 骑士冰颗粒（10-27 打磨）：冰材质、落地高度在发射点下方、不写攻击数据和玩法随机数、低画质仍发（模板 low_k 抽稀）、冰波缺口不出颗粒
func check_knight_ice(fx, g: Dictionary, pool: Pool, gameplay: RandomNumberGenerator) -> void:
	var knight := {"type": "knight_boss"}
	var state := gameplay.state
	for skin in ["ice_field", "ice_wave", "ice_thrust", "ice_lance", "ice_wall", "crescent", "spear"]:
		var shape := "line"
		if skin == "ice_wave" or skin == "ice_lance": shape = "circle"
		elif skin == "ice_field": shape = "cone"
		elif skin == "crescent": shape = "arc"
		var w := {"owner": knight, "skin": skin, "shape": shape, "pos": Vector2(400, 300), "ang": 0.2, "half": 0.6, "r": 300.0, "inner_r": 60.0,
			"wid": 24.0, "len": 400.0, "age": 0.1, "life": 1.0, "velocity": Vector2(300, 0), "col": Color(0.4, 0.8, 1)}
		var original := w.duplicate(true)
		for quality in ["high", "low"]:
			Cfg.quality = quality
			Beam._tok = 160
			Beam._tok_us = Time.get_ticks_usec()
			pool.calls.clear()
			fx.burst(g, w)
			fx.trail(g, w, 0.05)
			fx.finish(g, w)
			check(not pool.calls.is_empty(), skin + " knight ice emits at " + quality)
			check(pool.calls.all(func(c): return c[0] in ["ice", "frost_mist"]), skin + " uses the ice / cold mist materials")
			check(pool.calls.any(func(c): return c[0] == "ice"), skin + " has ice shards")
			check(pool.calls.all(func(c): return c[1].is_finite() and c[2].is_finite() and (c[0] != "ice" or c[5] >= c[1].y)), skin + " ground line at or below each shard")
		Cfg.quality = "high"
		check(w == original, skin + " knight ice leaves attack data unchanged")
	check(gameplay.state == state, "knight ice leaves gameplay RNG unchanged")
	var wave := {"owner": knight, "skin": "ice_wave", "shape": "circle", "pos": Vector2.ZERO, "r": 300.0, "inner_r": 254.0, "gap_ang": PI * 0.5, "gap_half": 0.7, "age": 0.2, "life": 1.4}
	Beam._tok = 160
	Beam._tok_us = Time.get_ticks_usec()
	pool.calls.clear()
	fx.trail(g, wave, 0.15)
	fx.finish(g, wave)
	check(not pool.calls.is_empty(), "ice wave front emits")
	check(pool.calls.all(func(c): return absf(angle_difference(c[1].angle(), wave.gap_ang)) > wave.gap_half), "ice wave chips stay out of the safe gap")
	fx.ice_off = true
	pool.calls.clear()
	fx.burst(g, wave)
	check(pool.calls.is_empty(), "--iceab off switch stops knight ice")
	fx.ice_off = false
