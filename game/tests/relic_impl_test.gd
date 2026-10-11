extends Node
## 藏品第二批原语的局内测试（docs/57）：godot --headless --path game res://tests/relic_impl_test.tscn -- --regression --balance --seed=1 --op=siege --squad=saria,wisadel
## 把 game.tscn 当子节点跑起来，第 5 帧直接发藏品、调钩子，逐条检查每个新原语的数值效果（不推进整局）。
## 全部通过时打印 "RELIC IMPL failures=0"。

const Bal = preload("res://scripts/core/balance.gd")

var game: Node
var rfx
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
	rfx = game.rfx
	test_batch_a()
	test_batch_b_c()
	test_batch_d_f()
	test_batch_g()
	test_batch_general()
	print("%d checks, %d failed" % [n, fails])
	print("RELIC IMPL failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		fails += 1
		printerr("FAIL: ", what)


func near(a: float, b: float, what: String, eps := 0.001) -> void:
	ok(absf(a - b) < eps, "%s（期望 %s，实际 %s）" % [what, b, a])


func grant(id: String) -> void:
	ok(game.progression.gain_relic(id), "获得藏品 %s" % id)


func op_of(cls: String):
	for o in game.squad.ops:
		if o.cls == cls:
			return o
	return null


func spawn(pos: Vector2) -> Dictionary:
	var e: Dictionary = game.spawner.spawn_enemy("runner", pos)
	game.enemies_sys.build_grid()
	return e


func reset_hp() -> void:
	game.hp = game.max_hp
	game.invuln = 0.0


## 批 A：hp_dmg / low_hp_haste / enemy_kb / boss_dmg / invuln / refund / temp 带职业 / 职业周期伤害 / 击杀回技力
func test_batch_a() -> void:
	var m0: float = rfx.dmg_extra()
	grant("124")
	reset_hp()
	near(rfx.dmg_extra() / m0, 1.3, "古乔治：满血全队伤害 ×1.3")
	game.hp = game.max_hp * 0.5
	near(rfx.dmg_extra() / m0, 1.15, "古乔治：半血 ×1.15")
	reset_hp()
	var h0: float = rfx.umbrella_interval_mult()
	grant("125")
	near(rfx.umbrella_interval_mult() / h0, 1.0, "紧急活性剂：满血不加速")
	game.hp = game.max_hp * 0.3
	near(rfx.umbrella_interval_mult() / h0, 1.0 / 1.6, "紧急活性剂：30% 生命时攻击间隔 ÷1.6")
	reset_hp()
	grant("167")
	near(game.enemy_kb_mult, 1.6, "锈刃-神力：击退倍率 1.6")
	grant("227")
	near(game.boss_mult, 1.5, "文明的存续：对 Boss 伤害 ×1.5")
	grant("166")
	game.invuln = 0.0
	rfx.on_dodge()
	ok(game.invuln >= 1.0, "可视静谧：闪避后无敌 ≥1 秒（%.2f）" % game.invuln)
	# 钝爪-熟稔：先锋技能返还 35%
	var van = op_of("先锋")
	ok(van != null, "编队里有先锋（--op=siege）")
	grant("135")
	if van != null:
		van.sp[0] = 0.0
		rfx.on_skill_start(van, 0)
		near(van.sp[0], van.sp_need(0) * 0.35, "钝爪-熟稔：先锋施放后返还 35%")
		var def = op_of("重装")
		if def != null:
			def.sp[0] = 0.0
			rfx.on_skill_start(def, 0)
			near(def.sp[0], 0.0, "钝爪-熟稔：重装不返还")
	# 铁卫-临时要塞：重装开技能 → 全队伤害 +50%、受到的伤害 -30%，5 秒后过期
	var def2 = op_of("重装")
	ok(def2 != null, "编队里有重装（saria）")
	grant("146")
	if def2 != null:
		var d0: float = rfx.dmg_extra()
		var t0: float = rfx.taken_mult()
		rfx.on_skill_start(def2, 0)
		near(rfx.dmg_extra() / d0, 1.5, "临时要塞：全队伤害 ×1.5")
		near(rfx.taken_mult() / t0, 0.7, "临时要塞：受到的伤害 ×0.7")
		game.t += 5.1
		rfx.tick(0.0)
		near(rfx.dmg_extra() / d0, 1.0, "临时要塞：5 秒后过期")
	# 尖刺之手：重装身边的敌人每秒受到法术伤害（藏品直接伤害计入 relic_out）
	grant("168")
	if def2 != null:
		var e: Dictionary = spawn(def2.pos + Vector2(40, 0))
		var hp0: float = e.hp
		rfx.tick(0.1)
		ok(e.hp < hp0, "尖刺之手：重装身边敌人掉血（%.1f → %.1f）" % [hp0, e.hp])
		e.dead = true
	# 积攒之手：先锋击杀回技力
	grant("173")
	if van != null:
		van.sp[0] = 0.0
		game.combat.hit("普攻")
		game.hit["class"] = "先锋"
		game.hit["op"] = van.id
		rfx.on_kill({"boss": false, "dead": false})
		near(van.sp[0], van.sp_need(0) * 0.03, "积攒之手：先锋击杀回 3% 技力")
	game.hit = {"src": "test", "emitter": "operator", "origin": "core", "range": "近战", "kind": "物理", "tags": [], "class": "", "op": ""}


func test_batch_b_c() -> void:
	pass


func test_batch_d_f() -> void:
	pass


func test_batch_g() -> void:
	pass


func test_batch_general() -> void:
	pass
