extends Node

class Sys extends RefCounted:   # prio_order 的护主检查（boss_rush 0 / 队长）要查队长身边最近的敌人
	var gm
	func nearest(n: int, r: float, origin: Vector2) -> Array:
		var es: Array = gm.enemies.filter(func(e): return not e.dead and e.pos.distance_to(origin) < r)
		es.sort_custom(func(a,b): return a.pos.distance_to(origin) < b.pos.distance_to(origin))
		return es.slice(0,n)

class TestGame extends RefCounted:
	var enemies_sys := Sys.new()
	var frame_n := 0
	func _init() -> void:
		enemies_sys.gm = self
	var ppos := Vector2.ZERO
	var squad = {"lead_dir": Vector2.RIGHT, "priority": 0}   # priority：指挥圆盘索敌优先级（docs/114 §13），0 = 原逻辑
	var enemies: Array = []
	var rng := RandomNumberGenerator.new()
	var stats = preload("res://scripts/core/stat_block.gd").new()
	var hit_src := {}
	var opt_old := 0
	var t := 0.0
	var map = null

class Obstacle extends RefCounted:
	func segment_blocked(a: Vector2, b: Vector2) -> bool:
		return Geometry2D.get_closest_point_to_segment(Vector2(100,0),a,b).distance_to(Vector2(100,0)) < 30
	func push_out(p: Vector2, _r: float) -> Vector2:
		return p

class Probe extends "res://scripts/characters/character.gd":
	func cmd_reach() -> float:
		return 120.0 if cls == "狙击" else 30.0
	func cmd_attack_range() -> float:
		return 200.0 if cls == "狙击" else 80.0
	func query_ids(_p: Vector2, _r: float) -> Array:
		return range(g.enemies.size())
	func nearest_enemies(n: int, r: float, origin: Vector2 = Vector2.INF) -> Array:
		var es: Array = g.enemies.filter(func(e): return not e.dead and e.pos.distance_to(origin) < r)
		es.sort_custom(func(a,b): return a.pos.distance_to(origin) < b.pos.distance_to(origin))
		return es.slice(0,n)

class DataProbe extends "res://scripts/characters/data_operator.gd":
	func stat(_name: StringName) -> float:
		return 1.0

var failures := 0
var checks := 0
func check(v: bool, message: String) -> void:
	checks += 1
	if not v:
		failures += 1
		printerr("FAIL: ", message)

var _eid := 0
func enemy(p: Vector2) -> Dictionary:
	_eid += 1
	return {"id": _eid, "pos": p, "r": 12.0, "dead": false, "boss": false, "elite": false}

func _ready() -> void:
	var g := TestGame.new()
	var o := Probe.new(g, {"id":"probe", "class":"重装"})
	o.pos = Vector2(-180,0)
	g.enemies = [enemy(Vector2(-300,0))]
	var dst: Vector2 = o.roam_target(Vector2(40,14))
	check(dst.distance_to(g.enemies[0].pos) < o.cmd_attack_range(), "heavy closes to attack range instead of camping at centroid fraction")
	o.cls = "近卫"
	o.roam_tgt = null
	var rr: float = preload("res://scripts/core/balance.gd").v("command/roam_r", 840.0)
	g.enemies = [enemy(Vector2(-rr - 10,0)),enemy(Vector2(-rr - 20,0)),enemy(Vector2(-rr - 30,0)),enemy(Vector2(-rr - 40,0)),enemy(Vector2(100,0))]
	o.roam_target(Vector2(40,14))
	check(o.roam_tgt != null and o.roam_tgt.pos == Vector2(100,0), "outside-circle candidates cannot hide legal target")
	o.cls = "狙击"
	g.enemies = [enemy(Vector2(-200,0))]
	o.roam_tgt = g.enemies[0]
	o.pos = Vector2(-60,0)
	check(o.roam_target(Vector2(40,14)).is_equal_approx(o.pos), "safe ranged operator holds position without orbiting")
	o.pos = Vector2(-190,0)
	check(o.roam_target(Vector2(40,14)).distance_to(g.enemies[0].pos) > 80, "ranged operator retreats from contact")
	o.cls = "近卫"
	o.pos = Vector2(-250,0)
	o.roam_tgt = enemy(Vector2(-290,0))
	var urgent := enemy(Vector2(30,0))
	g.enemies = [o.roam_tgt, urgent]
	o.roam_target(Vector2(40,14))
	check(is_same(o.roam_tgt,urgent), "immediate leader threat overrides distant locked target")
	# 全队集火（10-27 用户，command/boss_rush）：Boss 优先 + 圈里有 Boss 时不做紧急护主，直接冲 Boss，射程外追过去（可以出屏）
	var boss := enemy(Vector2(-700,0))
	boss.boss = true
	o.roam_tgt = null
	g.enemies = [urgent, enemy(Vector2(-200,0)), boss]
	var bdst: Vector2 = o.roam_target(Vector2(40,14))
	check(is_same(o.roam_tgt,boss), "boss priority: squad focuses the boss and ignores the leader-guard threat")
	check(bdst.distance_to(boss.pos) < o.cmd_attack_range() and bdst.distance_to(g.ppos) > 640.0, "boss priority: chases the boss off-screen into attack range")
	var part := enemy(Vector2(-400,60))
	part["part"] = true
	g.enemies = [urgent, boss, part]
	o.roam_target(Vector2(40,14))
	check(is_same(o.roam_tgt,part), "boss priority: a boss part takes over from the boss")
	g.enemies = [urgent, boss]
	o.roam_tgt = null
	g.squad.priority = 1
	o.roam_target(Vector2(40,14))
	check(is_same(o.roam_tgt,urgent), "mob priority still guards the leader even with a boss on field")
	g.squad.priority = 0
	var cmd: Dictionary = preload("res://scripts/core/balance.gd").sec("command")
	cmd["boss_rush"] = 0
	o.roam_tgt = null
	o.roam_target(Vector2(40,14))
	check(is_same(o.roam_tgt,urgent), "boss_rush 0 keeps the old leader guard")
	cmd["boss_rush"] = 1
	o.roam_tgt = urgent
	o.roam_tgt.dead = true
	g.enemies = [enemy(Vector2(-140,0))]
	o.roam_target(Vector2(40,14))
	check(is_same(o.roam_tgt,g.enemies[0]), "dead target is replaced")
	g.enemies.clear()
	o.roam_tgt = null
	check(o.roam_target(Vector2(40,14)) == Vector2(40,14), "no enemies returns to formation")
	for id in ["hoshiguma","saria","mizuki","gladiia","texas","skadi","exusiai","wisadel","eyjafjalla","logos"]:
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/characters/%s.json" % id))
		var op = DataProbe.new(g,d)
		check(op.cmd_attack_range() > 0, id + " provides positive effective range")
		if id == "gladiia":
			check(op.cmd_attack_range() <= float(op.B.attack.r), "front circle uses hit radius rather than distant search range")
		check(op.cmd_role() == ("ranged" if id in ["exusiai","wisadel","eyjafjalla","logos"] else "melee"), id + " uses attack type for role")
	g.map = Obstacle.new()
	o.cls = "狙击"
	o.pos = Vector2(40,0)
	g.enemies = [enemy(Vector2(200,0))]
	o.roam_tgt = g.enemies[0]
	var firing_pos: Vector2 = o.roam_target(Vector2(40,14))
	check(firing_pos != o.pos and not g.map.segment_blocked(firing_pos,g.enemies[0].pos), "in-range but obstructed ranged operator finds clear firing position")
	o.pos = Vector2.ZERO
	check(o.has_method("_cmd_walk"), "command movement has obstacle detour")
	if o.has_method("_cmd_walk"):
		var waypoint: Vector2 = o._cmd_walk(Vector2(200,0))
		check(not g.map.segment_blocked(o.pos,waypoint) and absf(waypoint.y)>1, "blocked route chooses reachable side waypoint")
		check(o._cmd_walk(Vector2(200,0)) == waypoint, "detour side remains stable")
		check(o._cmd_walk(o.pos) == o.pos, "stationary attack does not trigger obstacle recovery")
	check(o.has_method("_cmd_progress"), "command movement detects blocked progress")
	if o.has_method("_cmd_progress"):
		g.map = null
		g.enemies = [enemy(Vector2(200,0))]
		o.roam_tgt = g.enemies[0]
		o._cmd_progress(o.pos, Vector2(150,0), 1.0)
		check(o.roam_target(Vector2(40,14)) == Vector2(40,14), "stalled enemy is temporarily skipped and formation used")
		g.t += 3.0
		o.roam_target(Vector2(40,14))
		check(o.roam_tgt != null, "blocked enemy becomes eligible again after retry delay")
		o._cmd_progress(o.pos, o.pos, 2.0)
		check(o.roam_tgt != null, "normal stationary attack or cooldown is not a stall")
	print("COMMAND_AI checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures else 0)
