extends SceneTree
## P0 核心模块自测：godot --headless --path game -s res://tests/test_core.gd
## 全部通过时打印 "CORE TESTS PASSED" 并以 0 退出。

const Core = preload("res://scripts/core/combat_core.gd")
const E = preload("res://scripts/core/events.gd")
const SB = preload("res://scripts/core/stat_block.gd")

var fails := 0
var n := 0


func ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		fails += 1
		printerr("FAIL: ", what)


func near(a: float, b: float, what: String) -> void:
	ok(absf(a - b) < 0.0001, "%s（期望 %s，实际 %s）" % [what, b, a])


func _init() -> void:
	test_stat_order()
	test_bus()
	test_modifiers()
	test_db_and_profile()
	print("%d checks, %d failed" % [n, fails])
	if fails == 0:
		print("CORE TESTS PASSED")
	quit(1 if fails > 0 else 0)


func test_stat_order() -> void:
	var s = SB.new()
	s.define(&"dmg", 10.0, 0.0, 100.0)
	s.add(&"dmg", "flat", 2.0, "a")        # 12
	s.add(&"dmg", "add", 0.5, "b")         # ×1.5 = 18
	s.add(&"dmg", "add", 0.5, "c")         # 加算：×2.0 = 24
	s.add(&"dmg", "mult", 1.5, "d")        # ×1.5 = 36
	near(s.value(&"dmg"), 36.0, "Base→Flat→Add→Mult")
	s.remove_source("c")
	near(s.value(&"dmg"), 27.0, "撤销来源")
	s.add(&"dmg", "override", 5.0, "e")
	near(s.value(&"dmg"), 5.0, "Override")
	s.remove_source("e")
	s.add(&"dmg", "mult", 100.0, "f")
	near(s.value(&"dmg"), 100.0, "上限")


func test_bus() -> void:
	var c = Core.new()
	var log: Array = []
	c.bus.on(E.HIT, func(ev): log.append("low"); ev.amount *= 2.0, self, 0)
	c.bus.on(E.HIT, func(ev): log.append("high"), self, 10)
	var p: Dictionary = c.bus.emit(E.HIT, {"amount": 5.0})
	ok(log == ["high", "low"], "优先级顺序")
	near(p.amount, 10.0, "监听者可改负载")
	# 递归保护
	var depth := [0]
	c.bus.on(E.DODGE, func(_ev): depth[0] += 1; c.bus.emit(E.DODGE, {}), self)
	c.bus.emit(E.DODGE, {})
	ok(depth[0] == c.bus.MAX_DEPTH, "嵌套深度上限")
	c.bus.off_owner(self)
	ok(not c.bus.has_listeners(E.HIT), "退订")
	c.dispose()


func test_modifiers() -> void:
	var c = Core.new()
	var ctx := {"light": 100.0, "hp_ratio": 1.0, "allies": 0}
	c.mods.ctx_provider = func(): return ctx
	var healed := [0.0]
	c.mods.register_action("heal", func(args, _ev): healed[0] += args.amount)
	# stat
	c.apply_source("relic:x", [{"type": "stat", "stat": "dmg", "op": "add", "value": 0.2},
		{"type": "stat", "stat": "enemy_hp", "op": "add", "value": -0.1}], ["physical"])
	near(c.stats.value(&"dmg"), 1.2, "stat 效果")
	near(c.enemy.value(&"enemy_hp"), 0.9, "enemy_ 属性走敌人属性块")
	# trigger + temp_stat + 冷却 + 条件
	c.apply_source("relic:y", [{"type": "trigger", "event": "Dodge", "do": "temp_stat", "args": {"stat": "dmg", "op": "add", "value": 0.5, "dur": 2.0}},
		{"type": "trigger", "event": "DamageTaken", "if": {"light_below": 30}, "cooldown": 5, "do": "heal", "args": {"amount": 3.0}}])
	c.bus.emit(E.DODGE, {})
	near(c.stats.value(&"dmg"), 1.7, "闪避后临时增益")
	c.bus.emit(E.DODGE, {})
	near(c.stats.value(&"dmg"), 1.7, "默认不叠层，只刷新")
	c.tick(2.5, 100.0, 2.5)
	near(c.stats.value(&"dmg"), 1.2, "临时增益到期")
	c.bus.emit(E.DAMAGE_TAKEN, {"amount": 1.0})
	near(healed[0], 0.0, "条件不满足不触发")
	ctx.light = 20.0
	c.bus.emit(E.DAMAGE_TAKEN, {"amount": 1.0})
	c.bus.emit(E.DAMAGE_TAKEN, {"amount": 1.0})
	near(healed[0], 3.0, "条件满足触发，冷却内不重复")
	c.tick(5.1, 20.0, 7.6)
	c.bus.emit(E.DAMAGE_TAKEN, {"amount": 1.0})
	near(healed[0], 6.0, "冷却结束再次触发")
	# add_stat 上限
	c.apply_source("relic:z", [{"type": "trigger", "event": "EnemyKilled", "do": "add_stat", "args": {"stat": "dmg", "op": "add", "value": 0.1, "cap": 0.25}}])
	for i in 5:
		c.bus.emit(E.ENEMY_KILLED, {"src": "umbrella"})
	near(c.stats.value(&"dmg"), 1.45, "永久累加有上限")
	# rule / status / spawn / 移除
	var spawned := [0]
	c.mods.register_action("spawn", func(_a, _ev): spawned[0] += 1)
	c.apply_source("relic:w", [{"type": "rule", "rule": "shield_burst"}, {"type": "status", "status": "bind", "args": {"dot_mult": 0.6}},
		{"type": "spawn", "every": 1.0, "do": "spawn", "args": {}}])
	ok(c.mods.rule("shield_burst") == 1, "rule")
	ok(c.mods.status_args("bind").size() == 1, "status")
	c.tick(3.05, 20.0, 10.0)
	ok(spawned[0] == 3, "周期生成（%d）" % spawned[0])
	c.remove_source("relic:w")
	c.remove_source("relic:z")
	ok(c.mods.rule("shield_burst") == 0 and c.mods.status_args("bind").is_empty(), "移除后规则与状态清空")
	near(c.stats.value(&"dmg"), 1.2, "移除后属性恢复")
	c.dispose()


func test_db_and_profile() -> void:
	var c = Core.new()
	var cnt: int = c.load_data()
	ok(cnt == 262, "读取 262 件藏品（%d）" % cnt)
	var errs: Array = c.validate()
	for e in errs:
		printerr("  数据错误: ", e)
	ok(errs.is_empty(), "效果数据校验")
	ok(c.db.implemented().size() > 20, "已实装藏品数量")
	# Build Profile：拿伞击藏品后，A 流派领先
	for id in ["54", "56", "120", "121"]:
		c.gain_relic(id)
	ok(c.profile.lane_scores().A > c.profile.lane_scores().B, "伞击藏品提高 A 流派")
	ok(c.profile.affinity(["mizuki_umbrella"]) > c.profile.affinity(["support"]), "相关度")
	near(c.stats.value(&"mizuki_umbrella_dmg"), 1.5, "藏品效果生效")
	# 商店与 Boss 奖励
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var shop: Array = c.db.roll_shop(1, c.relics, c.profile, rng)
	ok(shop.size() == 3, "商店三件")
	for r in shop:
		ok(not c.relics.has(r.id) and r.rarity != "升华", "商店不出已拥有 / 升华")
	var b2: Array = c.db.roll_boss(1, c.relics, c.profile, rng)
	ok(b2.size() == 3, "第二个 Boss 三选一")
	ok(b2.any(func(r): return r.rarity == "升华"), "第二个 Boss 给升华")
	# 前置：没有药枚时不会出御2
	var p: Array = c.db.pool(c.relics)
	ok(not p.any(func(r): return r.id == "199"), "前置未满足不进池")
	c.gain_relic("118")
	p = c.db.pool(c.relics)
	ok(p.any(func(r): return r.id == "199"), "前置满足后进池")
	# 统计
	c.bus.emit(E.DAMAGE_DEALT, {"src": "umbrella", "amount": 30.0})
	c.bus.emit(E.DAMAGE_DEALT, {"src": "tentacle", "amount": 10.0})
	near(c.profile.dmg_share().umbrella, 0.75, "伤害来源占比")
	c.dispose()
