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
	func parts_live() -> Array:   # Boss 部件先打（op_api.nearest_enemies，docs/142b §1.0）：这里的场景没有部件
		return []

class Spy extends Node:
	func voice(_cid: String, _key: String, _queued := false, _urgent := false) -> void:
		pass
	func voice_chorus(_cid: String, _key: String, _delay := 0.0, _duck := -3.0) -> void:   # 指挥合唱（10-28，squad 缺省走这条）
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
	var beacons: Array = []
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
	check.call(squad.priority == 1 and Squad.default_priority() == 1, "default priority is mob first (1, user 10-27)")
	squad.apply_command("boss")
	check.call(squad.priority == 0, "boss command sets priority 0")
	check.call(mate.nearest_enemies(1, 600.0)[0].id == 6, "boss priority: boss in range goes first")
	var r: Array = mate.nearest_enemies(2, 600.0)
	check.call(r.size() == 2 and r[0].id == 6 and r[1].id == 1, "boss priority: boss first, then the rest by distance (elite not promoted)")
	check.call(mate.nearest_enemies(1, 400.0)[0].id == 1, "boss priority: boss outside max_dist is ignored")
	# 全队集火（10-27 用户，command/boss_rush）：队友不再因小怪贴近队长让开 Boss；队长自己仍护主
	setl.call([_e(7, 40.0), _e(1, 100.0), _e(6, 500.0, "boss")])
	check.call(mate.nearest_enemies(1, 600.0)[0].id == 6, "boss priority: mate keeps focusing boss even with a mob hugging the leader")
	check.call(leader.nearest_enemies(1, 600.0)[0].id == 7, "leader still guards itself: mob hugging the leader goes first")
	var cmd: Dictionary = preload("res://scripts/core/balance.gd").sec("command")
	var old_rush = cmd.get("boss_rush", 1)
	cmd["boss_rush"] = 0
	preload("res://scripts/core/balance.gd").clear_cache()   # 经持有的 sec 引用改值，缓存不知道（docs/199 §5）
	check.call(mate.nearest_enemies(1, 600.0)[0].id == 7, "boss_rush 0: old guard rule (mob hugging the leader overrides boss focus)")
	cmd["boss_rush"] = old_rush
	preload("res://scripts/core/balance.gd").clear_cache()
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
	# 指点（docs/196）：圆盘下半圈 移动 / 肃清 / 集火，6 格各 60°（10-30 用户「移动保留，然后增加肃清区域的选项」）
	var W = preload("res://scripts/screens/command_wheel.gd")
	var ids: Array = W._items().map(func(it): return str(it.id))
	var Bal = preload("res://scripts/core/balance.gd")
	check.call(ids == ["guard", "roam", "point", "focus"], "v2 wheel merges to escort / assault / deploy / focus (docs/209 §1.6)")
	Bal.sec("command")["v2"] = 0
	ids = W._items().map(func(it): return str(it.id))
	check.call(ids == ["guard", "roam", "recall", "point", "clear", "focus"], "wheel has move / clear / focus with target_proto on (v2 0)")
	Bal.sec("command")["v2"] = 1
	# 肃清：圈里没敌人 clear_idle 秒 → 回随行；圈里有敌人则 clear_secs 秒到点回随行；移动照旧（圈空 → 归队）
	setl.call([_e(1, 100.0)])
	check.call(squad.apply_order("clear", Vector2(1000.0, 0.0), null) and squad.order_kind == "clear", "clear order applies")
	check.call(is_equal_approx(squad.order_radius(), 220.0), "clear radius 220")
	squad._tick_order(0.6)
	check.call(squad.stance == Squad.ROAM, "clear: still out before clear_idle")
	squad._tick_order(0.6)
	check.call(squad.stance == Squad.GUARD and squad.order_kind == "", "clear: empty circle returns to follow")
	setl.call([_e(1, 1000.0)])
	squad._order_cd = 0.0
	check.call(squad.apply_order("clear", Vector2(1000.0, 0.0), null), "clear order applies again")
	squad._tick_order(5.0)
	check.call(squad.stance == Squad.ROAM, "clear: enemy in circle keeps the order")
	squad._tick_order(4.5)
	check.call(squad.stance == Squad.GUARD, "clear: times out after clear_secs and returns to follow")
	setl.call([])
	check.call(squad.apply_order("point", Vector2(500.0, 0.0), null), "move order applies")
	squad._tick_order(10.0)
	check.call(squad.stance == Squad.ROAM and squad.order_kind == "point", "move = station: stays put with nothing around (10-30)")
	check.call(is_equal_approx(squad.order_radius(), 0.0), "move is a point, not a circle")
	squad.apply_order("clear", Vector2(500.0, 0.0), null)
	check.call(squad.order_kind == "clear", "another order replaces the station")
	# 移动指到灯标附近（10-30 用户「移动可以帮忙点亮灯塔」）：落点吸附到灯标中心，守到点燃后回随行
	var bc := {"pos": Vector2(600.0, 0.0), "lit": false, "dead": false}
	game.beacons = [bc]
	squad.set_stance(Squad.GUARD)
	squad._order_cd = 0.0
	check.call(squad.apply_order("point", Vector2(640.0, 20.0), null) and squad.order_pos == bc.pos and squad.order_beacon == bc, "move near a beacon snaps onto it")
	squad._tick_order(5.0)
	check.call(squad.stance == Squad.ROAM, "beacon move: empty circle does not regroup while unlit")
	bc.lit = true
	squad._tick_order(0.1)
	check.call(squad.stance == Squad.GUARD and squad.order_beacon == null, "beacon move: lit beacon returns to follow")
	squad.set_stance(Squad.GUARD)
	check.call(squad.apply_order("point", Vector2(900.0, 0.0), null) and squad.order_beacon == null, "move far from a beacon does not snap")
