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
	test_squad_contract()
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
	c.gain_relic("79")
	near(c.stats.value(&"dmg"), 1.3, "藏品效果生效（79：全伤害 +30%）")
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


## 编队制（docs/23）：数值分层、干员契约、成长线解析
func test_squad_contract() -> void:
	# 数值分层：全局修正对所有作用域生效，class:/op: 只对命中的干员生效
	var s = SB.new()
	s.define(&"op_atk", 1.0, 0.0)
	s.add(&"op_atk", "add", 0.1, "squad_passive", "squad")
	s.add(&"op_atk", "add", 0.2, "class_relic", "class:狙击")
	s.add(&"op_atk", "add", 0.3, "prog", "op:sniper")
	near(s.value(&"op_atk"), 1.1, "全局值只含 squad 层")
	near(s.value_for(&"op_atk", ["class:狙击", "op:sniper"]), 1.6, "狙击干员：squad + class + op")
	near(s.value_for(&"op_atk", ["class:术师", "op:caster"]), 1.1, "术师干员：只有 squad 层")
	s.remove_source("prog")
	near(s.value_for(&"op_atk", ["class:狙击", "op:sniper"]), 1.3, "撤销 op 层来源后重算")
	# 干员契约：所有 data/characters/*.json 都通过校验，且每个都有 6 节点成长线
	var Ch = load("res://scripts/characters/character.gd")
	var ids: Array = Ch.list_ids()
	ok(ids.size() >= 5, "干员定义数量 ≥ 5（水月 + 四职业）")
	for cid in ids:
		var d: Dictionary = Ch.load_def(cid)
		ok(Ch.validate_operator(cid, d), "干员契约：%s" % cid)
		var pg: Array = d.get("progression", [])
		ok(pg.size() == 6, "成长线 6 节点：%s" % cid)
		var elites: Array = pg.filter(func(nd): return nd.get("type", "") == "elite")
		ok(elites.size() == 2 and int(elites[0].level) == 1 and int(elites[1].level) == 2, "两次精英化：%s" % cid)
		ok(elites[1].has("requires"), "精英化二带条件：%s" % cid)
	# 契约反例：缺 skill / manual 技能 / 非法节点
	ok(not Ch.validate_operator("bad", {"attack": {"mode": "auto"}}), "缺 skill 不通过")
	ok(not Ch.validate_operator("bad", {"attack": {"mode": "auto"}, "skill": {"mode": "manual"}}), "干员 manual 技能不通过")
	ok(not Ch.validate_operator("bad", {"attack": {}, "skill": {}, "progression": [{"type": "elite"}]}), "elite 节点缺 level 不通过")
