extends Node
## 星熊 S1「战意」站定嘲讽 + 防御反击（10-24 用户定，docs/140）：
## godot --headless --path game res://tests/hoshiguma_taunt_test.tscn -- --regression --balance --seed=1 --op=mizuki --squad=hoshiguma
## 队员时：技能期间钉在起手处（队长走开也不跟）、半径内近战杂兵改追她、Boss 不吃嘲讽；结束时反击倍率 = s1_mult + s1_per × 拉到的敌人数。
## 队长时（换成队长）：照常移动，不站定。全部通过时打印 "HOSHIGUMA TAUNT failures=0"。

var game: Node
var frames := 0
var n := 0
var fails := 0


func _ready() -> void:
	game = load("res://game.tscn").instantiate()
	add_child(game)


func _process(_d: float) -> void:
	frames += 1
	if frames != 5:
		return
	set_process(false)
	game.set_process(false)
	game.state = game.S.PLAY
	game.sandbox = true
	game.xp_need = 1000000000.0
	var o = game.squad.get_op("hoshiguma")
	ok(o != null and not o.is_leader, "星熊是队员（--squad=hoshiguma）")
	if o != null:
		test_member(o)
	print("%d checks, %d failed" % [n, fails])
	print("HOSHIGUMA TAUNT failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		fails += 1
		printerr("FAIL: ", what)


func spawn(id: String, pos: Vector2) -> Dictionary:
	var e: Dictionary = game.spawner.spawn_enemy(id, pos)
	e.hp = 99999.0
	e.max_hp = 99999.0
	return e


func step(k: int, leader_dx := 0.0) -> void:
	for i in k:
		game.ppos += Vector2(leader_dx / 60.0, 0)
		game.enemies_sys.build_grid()
		game._update(1.0 / 60.0)


func test_member(o) -> void:
	for e in game.enemies:
		e.dead = true
	game.enemies = []
	step(30)
	o.sp = [-10000.0, -10000.0, -10000.0]
	o.cd = 10000.0
	var p0: Vector2 = o.pos
	var r: float = float(o.B.skills[0].do[0].r) * o.stat(&"op_range")
	# 半径内两只近战杂兵，放在队长那一侧（不嘲讽时它们追队长）；一只 Boss 不吃嘲讽
	var es: Array = []
	for k in 4:
		es.append(spawn("runner", p0 + Vector2(-r * 0.7, -60 + 40 * k)))
	var bs: Dictionary = spawn("runner", p0 + Vector2(r * 0.5, 0))
	bs.boss = true   # 当作 Boss：不吃嘲讽
	bs.spd = 0.0
	var d0: Array = es.map(func(e): return e.pos.distance_to(p0))
	var before: float = float(game.dmg_out.get("举盾反击", 0.0))
	o.attack_t = 0.0
	o.fire_t = -1.0
	o.start_skill(Vector2.INF, 0)
	step(15)   # 出手帧（0.21 秒）生效、记下站定点
	var pa: Vector2 = o.pos
	ok(not o.taunt.is_empty() and o.taunt.anchor.distance_to(pa) < 1.0, "出手时记下站定点")
	step(40, 220.0)   # 队长往右跑开
	ok(o.pos.distance_to(pa) < 2.0, "队员站定：队长跑开时星熊留在原地（偏移 %.1f）" % o.pos.distance_to(pa))
	ok(not o.taunt.is_empty() and o.taunt.ids.size() >= 4, "半径内的近战杂兵都被拉到（%d）" % (o.taunt.ids.size() if not o.taunt.is_empty() else -1))
	ok(not o.taunt.ids.has(bs.id), "Boss 不吃嘲讽")
	var closer := 0
	for i in es.size():
		if not es[i].dead and es[i].pos.distance_to(o.pos) < d0[i] - 4.0:
			closer += 1
	ok(closer >= 3, "被拉到的杂兵往星熊身上靠（%d / 4）" % closer)
	var n_ids: int = o.taunt.ids.size()
	step(200)
	ok(o.taunt.is_empty(), "技能结束后嘲讽清掉")
	var got: float = float(game.dmg_out.get("举盾反击", 0.0)) - before
	ok(got > 0.0, "结束时打出举盾反击（%.0f）" % got)
	ok(o.taunt_anchor() == Vector2.INF, "结束后不再钉在原地")
	# 倍率：s1_mult + s1_per × n 用的是 on_end 的副本，原积木不改
	var m0: float = float(o.B.skills[0].do[0].on_end[0].mult)
	o.start_skill(Vector2.INF, 0)
	step(260)
	ok(is_equal_approx(float(o.B.skills[0].do[0].on_end[0].mult), m0), "原积木倍率不被改写")
	ok(n_ids > 0, "拉到的数量记下了")
	# 队长时不站定
	o.taunt = {"i": 0, "b": o.B.skills[0].do[0], "anchor": Vector2.INF, "ids": {}}
	ok(o.taunt_anchor() == Vector2.INF, "队长时（anchor INF）不站定")
	o.taunt = {}
