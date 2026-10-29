extends Node
## 乌尔比安 S3「必须开辟的通路」抡锚三连（用户 10-29）：godot --headless --path game res://tests/ulpianus_chain3_test.tscn -- --regression --balance --seed=1 --op=ulpianus
## 发动后 s3_dur 秒普攻按 横扫 → 回旋 → 猛砸 循环；本体不位移；猛砸掀飞普通敌人、精英硬直；结束后回到普通锚击。全部通过时打印 "ULPIANUS CHAIN3 failures=0"。

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
		test_chain(o)
	print("%d checks, %d failed" % [n, fails])
	print("ULPIANUS CHAIN3 failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		fails += 1
		printerr("FAIL: ", what)


func spawn(kind: String, pos: Vector2, elite := false) -> Dictionary:
	var e: Dictionary = game.spawner.spawn_enemy(kind, pos)
	e.hp = 99999.0
	e.max_hp = 99999.0
	e.spd = 0.0
	if elite:
		e.elite = true
	return e


func step(o, dt := 1.0 / 60.0) -> void:
	game.enemies_sys.build_grid()
	o.follow(dt, o.pos)
	o.update(dt)


func test_chain(o) -> void:
	for e in game.enemies:
		e.dead = true
	game.enemies = []
	o.elite = 2
	o.pos = Vector2(1500, 900)
	o.face = 1.0
	o.attack_t = 0.0
	o.fire_t = -1.0
	o.sp = [-10000.0, -10000.0, -10000.0]
	var mob := spawn("bone", o.pos + Vector2(70, 0))
	var eli := spawn("bone", o.pos + Vector2(60, 30), true)
	var far := spawn("bone", o.pos + Vector2(250, -10))   # 猛砸半径外、余震半径内
	var far_hit := false
	var x0: Vector2 = o.pos
	o.sp[2] = o.sp_need(2)
	o.start_skill(Vector2.INF, 2)
	var seen := {}
	var launched := false
	var eli_stun := false
	var max_c3 := 0
	var dur: float = o.base("s3_dur", 8.0)
	for i in int((dur + 0.5) * 60.0):
		step(o)
		max_c3 = maxi(max_c3, int(o.hw.get("c3", 0)))
		seen[int(o.hw.get("c3", 0)) % 3] = true
		for l in o.hw.get("launched", []):
			if is_same(l.e, mob):
				launched = true
		if float(eli.get("stun", 0.0)) > 0.5:
			eli_stun = true
		if float(far.hp) < 99999.0:
			far_hit = true
		far.hp = 99999.0
		far.pos = x0 + Vector2(250, -10)   # 被击退了也放回原处，下一轮余震照样够得着
		mob.hp = 99999.0
		eli.hp = 99999.0
	ok(o.pos.distance_to(x0) < 1.0, "本体不位移（%.1f）" % o.pos.distance_to(x0))
	ok(max_c3 >= 3, "技能期间至少走完一轮三连（%d 下）" % max_c3)
	ok(seen.size() == 3, "横扫 / 回旋 / 猛砸三段都出现")
	ok(launched, "猛砸掀飞普通敌人")
	ok(eli_stun, "猛砸让精英硬直（> 0.5 秒）")
	ok(far_hit, "猛砸后的余震打到猛砸半径外的敌人")
	for i in 120:
		step(o)
	ok(int(o.hw.get("c3", 0)) == 0, "技能结束后回到普通锚击（c3 归零）")
	ok(not o.is_manual(2), "三技能自动释放（不是手动）")
	# S2 永久后普攻换 attack_s2：移动中挥锚换跑动版（move_attack_s2），不再原地滑行（10-29）
	o.perm[1] = true
	o.pfx = []   # 清掉三连留下的回旋信号（whirl 粒子会把姿势换成 whirl_native）
	o.start_attack(o.pos + Vector2(60, 0))
	o.mv = 120.0
	var st: Dictionary = o.anim_state()
	ok(str(st.get("kind", "")) == "attack_s2", "S2 后普攻槽是 attack_s2（%s）" % st.get("kind", ""))
	ok(st.get("tex") != null and st.get("tex") == o.anim_tex("move_attack_s2"), "移动中 attack_s2 换成跑动版贴图")
	o.mv = 0.0
	st = o.anim_state()
	ok(st.get("tex") != o.anim_tex("move_attack_s2"), "站着时仍是原 attack_s2")
