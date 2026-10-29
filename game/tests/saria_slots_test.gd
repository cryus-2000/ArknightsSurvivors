extends Node
## 塞雷娅 S3 钙质化晶柱碰怪即碎、过一会原位重新长出（10-29）：godot --headless --path game res://tests/saria_slots_test.tscn -- --regression --balance --seed=1 --op=saria
## 全部通过时打印 "SARIA SLOTS failures=0"。

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
	var o = game.squad.get_op("saria")
	ok(o != null, "塞雷娅在编队里（--op=saria）")
	if o != null:
		test_slots(o)
	print("%d checks, %d failed" % [n, fails])
	print("SARIA SLOTS failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		fails += 1
		printerr("FAIL: ", what)


func spawn(pos: Vector2) -> Dictionary:
	var e: Dictionary = game.spawner.spawn_enemy("runner", pos)
	e.hp = 99999.0
	e.max_hp = 99999.0
	return e


func step(o, dt := 1.0 / 60.0) -> void:
	game.enemies_sys.build_grid()
	o.follow(dt, o.pos)
	o.update(dt)


func states(sa) -> Array:
	var r: Array = []
	for sl in sa.slots:
		r.append(int(sl.st))
	return r


func test_slots(o) -> void:
	for e in game.enemies:
		e.dead = true
	game.enemies = []
	game.enemies_sys.build_grid()
	o.elite = 2
	o.pos = game.ppos
	o.attack_t = 0.0
	o.sp = [-10000.0, -10000.0, -10000.0]
	o.sp[2] = o.sp_need(2)
	o.start_skill(Vector2.INF, 2)
	for i in 60:
		step(o)
	var sa = o.hw.sa
	ok(sa.slots.size() == 10, "S3：升起 10 根晶柱槽（实得 %d）" % sa.slots.size())
	for i in 40:
		step(o)
	ok(states(sa).count(1) == 10, "S3：晶柱长成立着 %s" % str(states(sa)))
	var sl: Dictionary = sa.slots[4]
	var e := spawn(sl.pos + Vector2(6, 0))
	step(o)
	ok(int(sl.st) == 2, "敌人碰到晶柱 → 碎裂（st %d）" % int(sl.st))
	ok(e.kb.length() > 60.0 and (e.pos - sl.pos).dot(e.kb) > 0.0, "碎时给触碰者一次向外的击退（kb %.0f）" % e.kb.length())
	e.dead = true
	game.enemies = []
	for i in 40:
		step(o)
	ok(int(sl.st) == 3, "碎完后空着等重新长出（st %d）" % int(sl.st))
	var left: float = float(o.skill_active_left(2))
	for i in int(maxf(0.0, 3.0 - 0.3 - 0.05) * 60.0):
		step(o)
	ok(int(sl.st) in [0, 1], "约 3 秒后原位重新长出（st %d）" % int(sl.st))
	ok(left > 3.0, "S3 仍在持续（剩余 %.1f 秒）" % left)
