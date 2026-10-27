extends Node

class Sys extends RefCounted:   # prio_order 的护主检查（boss_rush 0 / 队长）要查队长身边最近的敌人
	var gm
	func nearest(n: int, r: float, origin: Vector2) -> Array:
		if origin == Vector2.INF:
			origin = gm.ppos   # 同 enemies.gd：INF = 队长位置
		var es: Array = gm.enemies.filter(func(e): return not e.dead and e.pos.distance_to(origin) < r)
		es.sort_custom(func(a,b): return a.pos.distance_to(origin) < b.pos.distance_to(origin))
		return es.slice(0,n)
	func parts_live() -> Array:
		return gm.enemies.filter(func(e): return not e.dead and e.get("part", false))

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
	var warns: Array = []
	var ebullets: Array = []

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

class RealProbe extends "res://scripts/characters/character.gd":   # 用真的 op_api.nearest_enemies（无敌不打，10-28）
	func query_ids(_p: Vector2, _r: float) -> Array:
		return range(g.enemies.size())

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
	# 闪避意识（10-27，docs/114 §16）：站在未结算的圆形预警里 → 躲到圈外；迎面敌弹 → 让开；没有危险就照原目标
	g.map = null
	g.enemies = []
	g.t = 50.0
	var ev := Probe.new(g, {"id":"ev", "class":"近卫"})
	ev.pos = Vector2(300, 0)
	check(ev._cmd_evade(Vector2(400, 0)) == Vector2(400, 0), "no danger: evade keeps the goal")
	g.warns = [{"shape": "circle", "pos": Vector2(300, 0), "r": 60.0, "done": false}]
	var ep: Vector2 = ev._cmd_evade(Vector2(300, 0))
	check(ep.distance_to(Vector2(300, 0)) >= 60.0 + 16.0, "standing in a telegraph circle: moves out of it")
	check(ev._cmd_evade(Vector2(300, 0)) == ep, "evade point is held (no flip-flop)")
	g.warns[0].done = true
	g.t += 1.0
	check(ev._cmd_evade(Vector2(300, 0)) == Vector2(300, 0), "resolved telegraph is ignored")
	g.warns = []
	g.ebullets = [{"pos": Vector2(140, 0), "vel": Vector2(400, 0), "r": 6.0, "life": 1.0}]
	ep = ev._cmd_evade(Vector2(300, 0))
	check(absf(ep.y) > 20.0, "incoming bullet on the line: sidesteps off the line")
	g.ebullets = [{"pos": Vector2(140, 0), "vel": Vector2(-400, 0), "r": 6.0, "life": 1.0}]
	g.t += 1.0
	check(ev._cmd_evade(Vector2(300, 0)) == Vector2(300, 0), "bullet flying away is ignored")
	g.ebullets = []
	var cmd2: Dictionary = preload("res://scripts/core/balance.gd").sec("command")
	cmd2["evade"] = 0
	g.warns = [{"shape": "circle", "pos": Vector2(300, 0), "r": 60.0, "done": false}]
	g.t += 1.0
	check(ev._cmd_evade(Vector2(300, 0)) == Vector2(300, 0), "evade 0: no dodge")
	cmd2["evade"] = 1
	g.warns = []
	# 走位意识：近战挑近战怪最少的一侧（目标朝队长那侧被围 → 换到另一侧），side 0 = 永远朝队长侧
	var sd := Probe.new(g, {"id":"sd", "class":"近卫"})
	g.ppos = Vector2.ZERO
	var tgt := enemy(Vector2(300, 0))
	g.enemies = [tgt, enemy(Vector2(262, -14)), enemy(Vector2(262, 14)), enemy(Vector2(250, 0))]
	sd.pos = Vector2(300, 200)
	sd.roam_tgt = tgt
	g.squad.priority = 1
	var sp: Vector2 = sd.roam_target(Vector2(40,14))
	check(is_same(sd.roam_tgt, tgt) and (sp.x > 299.0 or absf(sp.y) > 20.0), "melee avoids the crowded leader-side and stands on a free side")
	cmd2["side"] = 0
	sd._cmd_side_ang = INF
	sp = sd.roam_target(Vector2(40,14))
	check(sp.x < 300.0 and absf(sp.y) < 1.0, "side 0: old rule, leader-side of the target")
	cmd2["side"] = 1
	g.squad.priority = 0
	# 无敌不打（10-28 用户「打伊祖米克的时候刚开始都在打它，没有打水母」）：自动选敌跳过打不动的，喂食子代先打
	var rp := RealProbe.new(g, {"id":"rp", "class":"近卫"})
	rp.pos = Vector2.ZERO
	var izu := enemy(Vector2(50,0))
	izu.boss = true
	izu["invuln"] = true
	var mob := enemy(Vector2(100,0))
	var kid := enemy(Vector2(150,0))
	kid["feed"] = true
	g.enemies = [izu, mob, kid]
	var ne: Array = rp.nearest_enemies(1, 400.0)
	check(ne.size() == 1 and is_same(ne[0], kid), "invulnerable boss skipped, feeding offspring first")
	g.enemies = [izu, mob]
	ne = rp.nearest_enemies(2, 400.0)
	check(ne.size() == 2 and is_same(ne[0], mob) and is_same(ne[1], izu), "invulnerable boss goes last, mob first")
	g.squad.priority = 1
	ne = rp.nearest_enemies(1, 400.0)
	check(ne.size() == 1 and is_same(ne[0], mob), "mob priority also skips the invulnerable boss")
	g.squad.priority = 0
	izu["invuln"] = false
	g.frame_n += 1
	ne = rp.nearest_enemies(1, 400.0)
	check(ne.size() == 1 and is_same(ne[0], izu), "boss targeted again once invulnerability ends")
	izu["invuln"] = true
	g.enemies = [izu]
	ne = rp.nearest_enemies(1, 400.0)
	check(ne.size() == 1 and is_same(ne[0], izu), "only invulnerable targets in range: still returns it, no error")
	izu["gate_hold"] = true
	izu["invuln"] = false
	g.enemies = [izu, mob]
	g.frame_n += 1
	ne = rp.nearest_enemies(1, 400.0)
	check(ne.size() == 1 and is_same(ne[0], mob), "phase-shield boss (gate_hold) skipped")
	izu.erase("gate_hold")
	izu["invuln"] = true
	var ipart := enemy(Vector2(30,0))
	ipart["part"] = true
	ipart["invuln"] = true
	g.enemies = [izu, ipart, mob]
	ne = rp.nearest_enemies(1, 400.0)
	check(ne.size() == 1 and is_same(ne[0], mob), "invulnerable part not forced to the front")
	rp.roam_tgt = izu
	g.enemies = [izu, mob]
	rp.roam_target(Vector2(40,14))
	check(is_same(rp.roam_tgt, mob), "assault: drops a locked invulnerable boss for a hittable mob")
	g.enemies = [izu]
	rp.roam_tgt = null
	rp.roam_target(Vector2(40,14))
	check(is_same(rp.roam_tgt, izu), "assault: invulnerable boss alone in circle is still the target")
	# 截子代（10-28 用户定 B）：Boss 无敌 + 喂食子代 → 队友去截离本体最近的，站在子代与本体之间；Boss 解除无敌 / 子代清完就不截
	izu["invuln"] = true
	izu.pos = Vector2(0, 0)
	izu["id"] = 900
	var k1 := enemy(Vector2(500, 0))
	k1["feed"] = true
	k1["feed_to_id"] = 900
	var k2 := enemy(Vector2(-300, 0))
	k2["feed"] = true
	k2["feed_to_id"] = 900
	g.enemies = [izu, k1, k2]
	rp.slot = 0
	g.frame_n += 1
	var ic = rp._izu_intercept()
	check(ic != null and is_same(ic[0], k2), "intercept: nearest-to-boss offspring first")
	var ip: Vector2 = rp._intercept_pos(ic)
	check(ip.x > k2.pos.x and ip.x < 0.0 and absf(ip.y) < 0.01, "intercept: stands between offspring and boss")
	rp.slot = 1
	ic = rp._izu_intercept()
	check(ic != null and is_same(ic[0], k1), "intercept: second teammate takes the next offspring")
	izu["invuln"] = false
	g.frame_n += 1
	check(rp._izu_intercept() == null, "intercept: stops once the boss is no longer invulnerable")
	izu["invuln"] = true
	k1.dead = true
	k2.dead = true
	g.frame_n += 1
	check(rp._izu_intercept() == null, "intercept: stops when all offspring are cleared")
	rp.slot = 0
	# 队长自动攻击（10-28 用户）：只剩无敌目标时不出手，有能打的照常
	var lp := RealProbe.new(g, {"id":"lp", "class":"狙击"})
	lp.is_leader = true
	g.enemies = [izu]
	g.frame_n += 1
	check(lp.nearest_enemies(2, 400.0).is_empty(), "leader auto-attack holds fire on invulnerable-only targets")
	var lk := enemy(Vector2(200, 0))
	lk["feed"] = true
	g.enemies = [izu, lk]
	ne = lp.nearest_enemies(2, 400.0)
	check(ne.size() == 1 and is_same(ne[0], lk), "leader auto-attack hits the offspring, never the invulnerable boss")
	print("COMMAND_AI checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures else 0)
