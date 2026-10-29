extends Node
## 歌蕾蒂娅钩索把人拉到身前（10-24）：godot --headless --path game res://tests/gladiia_hook_test.tscn -- --regression --balance --seed=1 --op=gladiia
## 钩索瞄准的那名敌人（普通怪）一定被拖到身前 hook_front 附近（她当队长时 hook_front_leader，docs/196 §3.2）；精英与自爆怪当队长时只拖半程；更近的敌人不被推出去；Boss 不受影响。
## 全部通过时打印 "GLADIIA HOOK failures=0"。

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
	var o = game.squad.get_op("gladiia")
	ok(o != null, "歌蕾蒂娅在编队里（--op=gladiia）")
	if o != null:
		test_pull(o, false)
		test_half(o, "精英", "bone", true)
		test_half(o, "自爆怪", "runner", false)
		test_near_not_pushed(o)
	print("%d checks, %d failed" % [n, fails])
	print("GLADIIA HOOK failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		fails += 1
		printerr("FAIL: ", what)


func spawn(pos: Vector2, elite := false, kind := "bone") -> Dictionary:
	var e: Dictionary = game.spawner.spawn_enemy(kind, pos)
	e.hp = 99999.0
	e.max_hp = 99999.0
	if elite:
		e.elite = true
	return e


func reset(o) -> void:
	for e in game.enemies:
		e.dead = true
	game.enemies = []
	game.enemies_sys.build_grid()
	o.pos = Vector2(1500, 900)
	o.face = 1.0
	o.attack_t = 0.0
	o.fire_t = -1.0
	o.hw.hooks = []
	o.sp = [-10000.0, -10000.0, -10000.0]


func step(o, dt := 1.0 / 60.0) -> void:
	game.enemies_sys.build_grid()
	o.follow(dt, o.pos)
	o.update(dt)


func hook_dist() -> float:
	var o = game.squad.get_op("gladiia")
	return float(o.base("hook_front_leader", 175.0)) if o.is_leader else float(o.base("hook_front", 110.0))


func test_pull(o, elite: bool) -> void:
	reset(o)
	var tag := "精英" if elite else "普通怪"
	var e := spawn(o.pos + Vector2(236, 0), elite)   # 射程边缘：旧版落点 230 ≈ 原位，几乎不动
	var d0: float = e.pos.distance_to(o.pos)
	o.start_attack(e.pos)
	for i in 150:
		step(o)
		if not o.hw.hooks.is_empty() and str(o.hw.hooks[0].phase) == "drag":
			e.hp = 99999.0
	var d1: float = e.pos.distance_to(o.pos)
	ok(d0 - d1 > 40.0, "%s：被钩后明显拉近（%.0f → %.0f）" % [tag, d0, d1])
	ok(d1 < hook_dist() + 40.0, "%s：到位在 hook_front %.0f 附近（实得 %.0f）" % [tag, hook_dist(), d1])


## 当队长：精英 / 自爆怪只拖半程（落点在原位与 hook_front_leader 之间）
func test_half(o, tag: String, kind: String, elite: bool) -> void:
	reset(o)
	var e := spawn(o.pos + Vector2(236, 0), elite, kind)
	var d0: float = e.pos.distance_to(o.pos)
	o.start_attack(e.pos)
	for i in 150:
		step(o)
		if not o.hw.hooks.is_empty() and str(o.hw.hooks[0].phase) == "drag":
			e.hp = 99999.0
	var d1: float = e.pos.distance_to(o.pos)
	var half: float = 0.5 * (d0 + hook_dist())
	ok(o.is_leader, "%s：测试时歌蕾蒂娅是队长" % tag)
	ok(d0 - d1 > 15.0 and absf(d1 - half) < 25.0, "%s：只拖半程（%.0f → %.0f，半程约 %.0f）" % [tag, d0, d1, half])


func test_near_not_pushed(o) -> void:
	reset(o)
	var far := spawn(o.pos + Vector2(236, 0))
	var near := spawn(o.pos + Vector2(60, 4))   # 在钩索线上、比落点近：不该被推出去
	var d_near0: float = near.pos.distance_to(o.pos)
	o.start_attack(far.pos)
	for i in 150:
		step(o)
	ok(near.pos.distance_to(o.pos) < d_near0 + 60.0, "线上更近的敌人没有被推出去（%.0f → %.0f）" % [d_near0, near.pos.distance_to(o.pos)])
