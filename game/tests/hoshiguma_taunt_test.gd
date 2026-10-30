extends Node
## 星熊 S1「战意」重斩 + 拉怪（10-30 用户定改版，docs/140；原 10-24 站定嘲讽 + 减伤 10-30 取消）：
## godot --headless --path game res://tests/hoshiguma_taunt_test.tscn -- --regression --balance --seed=1 --op=mizuki --squad=hoshiguma
## 起手即反手重斩（半径内造成伤害 + 击退 + 顿帧）、不站定不减伤（队长走开她照常跟）、半径内近战杂兵 window 秒内改追她、
## 精英只被拉 window × elite_x 秒、Boss 不吃嘲讽；s1_pull = 0 时不拉怪；结束时不再斩。全部通过时打印 "HOSHIGUMA TAUNT failures=0"。

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
	var r: float = float(o.B.skills[0].do[1].r) * o.stat(&"op_range")
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
	step(15)   # 出手帧（0.21 秒）生效
	var hit0: float = float(game.dmg_out.get("举盾反击", 0.0)) - before
	ok(hit0 > 0.0, "起手重斩（%.0f）" % hit0)
	ok(not o.taunt.is_empty(), "拉怪开始")
	ok(o.taunt_anchor() == Vector2.INF, "不再站定")
	ok(is_equal_approx(o.ext_dr, 1.0), "不再减伤（%.2f）" % o.ext_dr)
	var win: float = float(o.base("s1_window", 4.0))
	var el: Dictionary = spawn("runner", p0 + Vector2(-r * 0.5, 0))
	el.elite = true
	step(5)
	ok(o.taunt.ids.has(el.id), "精英在前半段被拉")
	var d1: Array = es.map(func(e): return e.pos.distance_to(o.pos))   # 重斩击退之后的距离
	step(40)
	ok(not o.taunt.is_empty() and o.taunt.ids.size() >= 4, "半径内的近战杂兵都被拉到（%d）" % (o.taunt.ids.size() if not o.taunt.is_empty() else -1))
	ok(not o.taunt.ids.has(bs.id), "Boss 不吃嘲讽")
	var closer := 0
	for i in es.size():
		if not es[i].dead and es[i].pos.distance_to(o.pos) < d1[i] - 4.0:
			closer += 1
	ok(closer >= 3, "被拉到的杂兵往星熊身上靠（%d / 4）" % closer)
	# 过了 window × elite_x 秒，新来的精英不再被拉，新来的杂兵照拉
	step(int((win * float(o.base("s1_elite_x", 0.5)) + 0.3) * 60.0) - 60)
	var e2: Dictionary = spawn("runner", o.pos + Vector2(r * 0.3, 40))
	var e3: Dictionary = spawn("runner", o.pos + Vector2(r * 0.3, -40))
	e3.elite = true
	step(3)
	ok(not o.taunt.is_empty() and o.taunt.ids.has(e2.id), "窗口后半段杂兵照拉")
	ok(not o.taunt.is_empty() and not o.taunt.ids.has(e3.id), "窗口后半段精英不再拉")
	step(int(win * 60.0))
	ok(o.taunt.is_empty(), "技能结束后拉怪清掉")
	var got: float = float(game.dmg_out.get("举盾反击", 0.0)) - before
	ok(absf(got - hit0) < 0.5, "结束时不再斩（总伤害仍是起手那一下：%.0f / %.0f）" % [got, hit0])
	# 开关：s1_pull = 0 不拉
	o.def.base["s1_pull"] = 0.0
	o.sp = [-10000.0, -10000.0, -10000.0]
	o.cd = 10000.0
	o.attack_t = 0.0
	o.fire_t = -1.0
	spawn("runner", o.pos + Vector2(r * 0.3, 0))
	o.start_skill(Vector2.INF, 0)
	step(15)
	ok(o.taunt.is_empty(), "s1_pull = 0 时不拉怪")
	o.def.base["s1_pull"] = 1.0
	o.taunt = {}
