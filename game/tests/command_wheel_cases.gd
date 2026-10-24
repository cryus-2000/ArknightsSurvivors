extends RefCounted
## 指挥圆盘的索敌优先级（docs/114 §13）：队友 nearest_enemies 按 priority 重排，队长不受影响；apply_command 设 priority

const Squad = preload("res://scripts/characters/squad.gd")
const Character = preload("res://scripts/characters/character.gd")

class Sys extends RefCounted:
	var list: Array = []   # 已按离 origin 由近到远排好（测试里 origin 都在 x 轴原点附近）
	var ppos := Vector2.ZERO
	func nearest(n: int, max_dist: float, origin: Vector2 = Vector2.INF) -> Array:
		var o: Vector2 = ppos if origin == Vector2.INF else origin
		return list.filter(func(e): return e.pos.distance_to(o) < max_dist).slice(0, n)

class Spy extends Node:
	func voice(_cid: String, _key: String, _queued := false, _urgent := false) -> void:
		pass

class FakeGame extends RefCounted:
	var enemies_sys := Sys.new()
	var squad
	var sfx: Node = Spy.new()
	var t := 10.0
	var frame_n := 0
	var enemies: Array = []
	var demo_op := ""
	var trace_every := 0.0
	var ppos := Vector2.ZERO
	var stats = preload("res://scripts/core/stat_block.gd").new()
	var hit_src := {}
	func get_node_or_null(_p: String):
		return sfx
	func is_inside_tree() -> bool:
		return true

static func _e(id: int, x: float, kind := "mob") -> Dictionary:
	return {"id": id, "pos": Vector2(x, 0.0), "boss": kind == "boss", "elite": kind == "elite", "r": 10.0, "dead": false}

func run(check: Callable) -> void:
	var game := FakeGame.new()
	var squad := Squad.new(game)
	game.squad = squad
	var leader := Character.new(game, {"id": "skadi"})
	leader.is_leader = true
	var mate := Character.new(game, {"id": "texas"})
	squad.ops = [leader, mate]
	var setl := func(l: Array) -> void:
		game.enemies_sys.list = l
		game.enemies = l
		game.frame_n += 1   # _focus_bosses 按帧缓存
	# 近处一只孤立杂兵 100、精英 150、一串三只杂兵 300 / 360 / 420（相邻 60、首尾 120，中间那只周围最密）、Boss 500
	setl.call([_e(1, 100.0), _e(2, 150.0, "elite"), _e(3, 300.0), _e(4, 360.0), _e(5, 420.0), _e(6, 500.0, "boss")])
	check.call(squad.priority == 0, "default priority is Boss first (0)")
	check.call(mate.nearest_enemies(1, 600.0)[0].id == 6, "boss priority: boss in range goes first")
	var r: Array = mate.nearest_enemies(2, 600.0)
	check.call(r.size() == 2 and r[0].id == 6 and r[1].id == 1, "boss priority: boss first, then the rest by distance (elite not promoted)")
	check.call(mate.nearest_enemies(1, 400.0)[0].id == 1, "boss priority: boss outside max_dist is ignored")
	# 护主：队长 60 内有小怪贴脸时不强制 Boss
	setl.call([_e(7, 40.0), _e(1, 100.0), _e(6, 500.0, "boss")])
	check.call(mate.nearest_enemies(1, 600.0)[0].id == 7, "boss priority: mob hugging the leader overrides boss focus")
	setl.call([_e(1, 100.0), _e(2, 150.0, "elite"), _e(3, 300.0), _e(4, 360.0), _e(5, 420.0), _e(6, 500.0, "boss")])
	squad.apply_command("mob")
	check.call(squad.priority == 1, "mob command sets priority 1")
	r = mate.nearest_enemies(3, 600.0)
	check.call(r.size() == 3 and not r.any(func(e): return e.id == 2 or e.id == 6), "mob priority: no elite / boss in the first three")
	check.call(r[0].id == 4, "mob priority: densest member (middle of the cluster) picked first")
	check.call(leader.nearest_enemies(1, 600.0)[0].id == 6, "leader targeting is not affected by priority (always boss first)")
	# 没有杂兵时清杂优先退回原顺序
	setl.call([_e(2, 150.0, "elite"), _e(6, 500.0, "boss")])
	r = mate.nearest_enemies(2, 600.0)
	check.call(r.size() == 2 and r[0].id == 2, "mob priority with only elites keeps the original order")
	# 没有 Boss 时 Boss 优先 = 就近
	setl.call([_e(1, 100.0), _e(3, 300.0)])
	squad.apply_command("boss")
	check.call(squad.priority == 0, "boss command sets priority 0")
	r = mate.nearest_enemies(1, 600.0)
	check.call(r.size() == 1 and r[0].id == 1, "boss priority with no boss falls back to nearest")
	# 统一口径：走位侧（得分 = 任意值）与攻击侧用同一个 prio_order
	var cands: Array = [[_e(1, 100.0), 10.0], [_e(3, 300.0), 20.0], [_e(4, 360.0), 30.0], [_e(5, 420.0), 40.0], [_e(6, 500.0, "boss"), 50.0]]
	check.call(mate.prio_order(cands, 1)[0].id == 4, "prio_order mob: densest by count, score breaks ties")
	check.call(mate.prio_order(cands, 0)[0].id == 6, "prio_order boss: lowest-score focusable boss first")
	var coma := _e(6, 500.0, "boss")
	coma["coma"] = true
	check.call(mate.prio_order([[_e(1, 100.0), 10.0], [coma, 50.0]], 0)[0].id == 1, "prio_order boss: comatose boss is not focused")
	check.call(not "near" in Squad.PRIO_SHORT and Squad.PRIO_NAMES.size() == 2, "nearest option removed (10-24)")
