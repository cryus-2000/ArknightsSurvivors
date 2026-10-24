extends Node
## 乌尔比安 S3「必须开辟的通路」冲锋（10-24）：godot --headless --path game res://tests/ulpianus_charge_test.tscn -- --regression --balance --seed=1 --op=ulpianus
## 掷锚咬地后本体沿锁链冲向落点：路径宽 s3_path_w 内的敌人各吃一次 s3_path_mult 伤害，落地半径 s3_r 内 ×s3_mult；
## 走廊外的敌人不受路径伤害；冲锋期间本体真的位移；S1（没写 path_w）仍然原地砸、不位移。全部通过时打印 "ULPIANUS CHARGE failures=0"。

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
	var o = game.squad.get_op("ulpianus")
	ok(o != null, "乌尔比安在编队里（--op=ulpianus）")
	if o != null:
		test_s3(o)
		test_s1_in_place(o)
	print("%d checks, %d failed" % [n, fails])
	print("ULPIANUS CHARGE failures=%d" % fails)
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


func clear_enemies() -> void:
	for e in game.enemies:
		e.dead = true
	game.enemies = []
	game.enemies_sys.build_grid()


func step(o, dt := 1.0 / 60.0) -> void:
	game.enemies_sys.build_grid()
	o.follow(dt, o.pos)
	o.update(dt)


func reset(o) -> void:
	clear_enemies()
	o.elite = 2
	o.pos = Vector2(1500, 900)
	o.face = 1.0
	if o.hw.has("anchor"):
		o.hw.anchor = {}
	o.hw.hooked = []
	o.attack_t = 0.0
	o.fire_t = -1.0
	o.sp = [-10000.0, -10000.0, -10000.0]


func test_s3(o) -> void:
	reset(o)
	var x0: float = o.pos.x
	var on1 := spawn(o.pos + Vector2(60, 0))        # 路径上，落点半径外
	var on2 := spawn(o.pos + Vector2(130, 6))       # 路径上（略偏），落点半径外
	var off := spawn(o.pos + Vector2(150, 190))     # 走廊外，也在落点半径外、普攻够不着
	var land := spawn(o.pos + Vector2(330, 70))     # 只在落地半径内（距路径 > 走廊）
	var hp := {}
	for e in [on1, on2, off, land]:
		hp[e.id] = float(e.hp)
	o.sp[2] = o.sp_need(2)
	ok(o.cast_manual(2, Vector2.ZERO, o.pos + Vector2(330, 0)), "S3：手动放出（选落点）")
	var moved_mid := false
	var was_zip := false
	var snap := {}
	for i in 200:
		step(o)
		var ph: String = str(o.hw.get("anchor", {}).get("phase", "")) if not o.hw.get("anchor", {}).is_empty() else ""
		if ph == "zip":
			was_zip = true
			if o.pos.x > x0 + 40.0:
				moved_mid = true
		elif was_zip and snap.is_empty():
			for e in [on1, on2, off, land]:   # 落地结算完那一帧：之后她的普攻 / 余波不再算进技能伤害
				snap[e.id] = float(e.hp)
	ok(moved_mid, "S3：冲锋段本体真的在位移（phase zip 期间 x 增加）")
	ok(o.pos.x > x0 + 250.0, "S3：冲到落点附近（x0 %.0f → %.0f）" % [x0, o.pos.x])
	ok(not snap.is_empty(), "S3：冲锋结束并落地")
	for e in [on1, on2, off, land]:
		if snap.has(e.id):
			e.hp = snap[e.id]
	var d_on1: float = hp[on1.id] - float(on1.hp)
	var d_on2: float = hp[on2.id] - float(on2.hp)
	var d_off: float = hp[off.id] - float(off.hp)
	var d_land: float = hp[land.id] - float(land.hp)
	ok(d_on1 > 0.0 and d_on2 > 0.0, "S3：路径上的敌人受伤（%.0f / %.0f）" % [d_on1, d_on2])
	ok(absf(d_on1 - d_on2) < 0.5, "S3：路径上每名敌人只吃一次（两名伤害一致 %.1f / %.1f）" % [d_on1, d_on2])
	ok(d_land > 0.0, "S3：落地半径内的敌人受伤（%.0f）" % d_land)
	var ratio: float = d_on1 / d_land if d_land > 0.0 else 0.0
	ok(absf(ratio - 0.6) < 0.06, "S3：沿途 120% / 落地 200% = 0.6（实得 %.2f）" % ratio)
	ok(d_off == 0.0, "S3：走廊外且落点半径外的敌人不受伤（%.0f）" % d_off)


func test_s1_in_place(o) -> void:
	reset(o)
	var x0: float = o.pos.x
	var e := spawn(o.pos + Vector2(200, 0))
	o.start_skill(Vector2.INF, 0)
	for i in 160:
		step(o)
	ok(absf(o.pos.x - x0) < 1.0, "S1：钩索技能仍然原地、本体不位移（%.1f）" % (o.pos.x - x0))
