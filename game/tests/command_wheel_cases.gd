extends RefCounted
## 指挥圆盘的索敌优先级（docs/114 §13）：队友 nearest_enemies 按 priority 重排，队长不受影响；apply_command 设 priority

const Squad = preload("res://scripts/characters/squad.gd")
const Character = preload("res://scripts/characters/character.gd")

class Sys extends RefCounted:
	var list: Array = []   # 已按离 origin 由近到远排好
	func nearest(n: int, _max_dist: float, _origin: Vector2 = Vector2.INF) -> Array:
		return list.slice(0, n)

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
	# 近处一只孤立杂兵 100、精英 150、一串三只杂兵 300 / 360 / 420（相邻 60、首尾 120，中间那只周围最密）、Boss 500
	game.enemies_sys.list = [_e(1, 100.0), _e(2, 150.0, "elite"), _e(3, 300.0), _e(4, 360.0), _e(5, 420.0), _e(6, 500.0, "boss")]
	squad.apply_command("near")
	check.call(squad.priority == 0, "near keeps priority 0")
	check.call(mate.nearest_enemies(1, 600.0).size() == 1 and mate.nearest_enemies(1, 600.0)[0].id == 1, "priority 0: mate takes the nearest")
	squad.apply_command("boss")
	check.call(squad.priority == 2, "boss command sets priority 2")
	var r: Array = mate.nearest_enemies(2, 600.0)
	check.call(r.size() == 2 and r[0].id == 2 and r[1].id == 6, "boss priority: elite then boss first, by distance")
	squad.apply_command("mob")
	check.call(squad.priority == 1, "mob command sets priority 1")
	r = mate.nearest_enemies(3, 600.0)
	check.call(r.size() == 3 and r[0].id in [3, 4, 5] and not r.any(func(e): return e.id == 2 or e.id == 6), "mob priority: dense cluster first, no elite / boss in the first three")
	check.call(r[0].id == 4, "mob priority: densest member (middle of the cluster) picked first")
	# 没有杂兵时清杂优先退回原顺序；没有精英 / Boss 时 Boss 优先退回原顺序
	game.enemies_sys.list = [_e(2, 150.0, "elite"), _e(6, 500.0, "boss")]
	r = mate.nearest_enemies(2, 600.0)
	check.call(r.size() == 2 and r[0].id == 2, "mob priority with only elites keeps the original order")
	game.enemies_sys.list = [_e(1, 100.0), _e(3, 300.0)]
	squad.apply_command("boss")
	r = mate.nearest_enemies(1, 600.0)
	check.call(r.size() == 1 and r[0].id == 1, "boss priority with no boss falls back to nearest")
	# 队长不受影响：同一份列表，队友按优先级拿到杂兵，队长仍走原来的顺序（Boss 在最近处时先打 Boss）
	squad.apply_command("mob")
	game.enemies_sys.list = [_e(6, 100.0, "boss"), _e(1, 200.0), _e(3, 210.0)]
	check.call(mate.nearest_enemies(1, 600.0)[0].id in [1, 3], "mate follows priority even when a boss is nearest")
	check.call(leader.nearest_enemies(1, 600.0)[0].id == 6, "leader targeting is not affected by priority")
	squad.apply_command("near")
	check.call(squad.priority == 0, "back to nearest")
