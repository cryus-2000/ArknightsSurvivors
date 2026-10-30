extends SceneTree
## P0 核心模块自测：godot --headless --path game -s res://tests/test_core.gd
## 全部通过时打印 "CORE TESTS PASSED" 并以 0 退出。

const Core = preload("res://tests/core_p0/combat_core.gd")
const E = preload("res://tests/core_p0/events.gd")
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
	test_hud_arc_geometry()
	test_condensed_fonts()
	test_stat_order()
	test_bus()
	test_modifiers()
	test_db_and_profile()
	test_squad_contract()
	test_operator_contract()
	test_hoshiguma_blocks()
	test_voice()
	test_voice_interrupt()
	test_blocks_angelina()
	test_blocks_texas()
	test_skill_gate()
	test_need_enemy_data()
	test_fx_hold()
	test_operator_sheet()
	test_op_text_fill()
	test_blocks_summon_seal()
	test_blocks_summon_ext()
	test_blocks_elite1()
	test_blocks_handwritten()
	test_blocks_hw3()
	test_blocks_hw4()
	test_blocks_e5()
	print("%d checks, %d failed" % [n, fails])
	if fails == 0:
		print("CORE TESTS PASSED")
	quit(1 if fails > 0 else 0)


func test_hud_arc_geometry() -> void:
	var tris = preload("res://scripts/screens/hud_tris.gd")
	for seg in [1, 16, 48, 64]:
		for center in [Vector2.ZERO, Vector2(102, 618), Vector2(-13.21, 711.37)]:
			for radius in [0.0, 0.2, 24.5, 100.1234567]:
				var batch = tris.new()
				var points := PackedVector2Array()
				var colors := PackedColorArray()
				var indices := PackedInt32Array()
				for pass_i in 3:
					var color := Color(0.34, 0.78, 1.12, 0.3 * pass_i)
					var end := TAU if pass_i < 2 else 1.3
					var base := points.size()
					for q in seg + 1:
						var d := Vector2.from_angle(lerpf(0.0, end, float(q) / seg))
						points.append(center + d * (radius - 0.75))
						points.append(center + d * (radius + 0.75))
						colors.append(color)
						colors.append(color)
					for q in seg:
						var i: int = base + q * 2
						indices.append_array([i, i + 1, i + 3, i, i + 3, i + 2])
					batch.arc(center, radius, 0.0, end, 1.5, color, seg)
				ok(batch.pts == points and batch.cols == colors and batch.idx == indices,
					"HUD 圆环缓存：位置、颜色、连续追加及进度弧几何不变")
	for i in 300:
		var batch = tris.new()
		batch.pts.resize(i)
		batch.arc(Vector2.ZERO, i + 1.0, 0.0, TAU, 1.0, Color.WHITE, 2)
	ok(tris._full_arcs.size() <= 128 and tris._arc_indices.size() <= 256, "HUD 圆环缓存有界")
	tris._full_arcs.clear()
	tris._arc_indices.clear()


func test_condensed_fonts() -> void:
	var ui = preload("res://scripts/ui.gd")
	var a := FontFile.new()
	var b := FontFile.new()
	var regular: FontVariation = ui.cond(a)
	var italic: FontVariation = ui.cond(a, true)
	ok(ui.cond(a) == regular and ui.cond(a, true) == italic, "压缩字体重复取用同一资源")
	ok(regular != italic and ui.cond(b) != regular and ui.cond(b, true) != italic, "字体与斜体缓存互不串用")
	ok(regular.base_font == a and italic.base_font == a and ui.cond(b).base_font == b, "压缩字体保留对应基字体")
	ok(regular.variation_transform == Transform2D(Vector2(0.82, 0), Vector2(0, 1), Vector2.ZERO), "压缩字体变换不变")
	ok(italic.variation_transform == Transform2D(Vector2(0.82, 0.2), Vector2(0, 1), Vector2.ZERO), "斜体变换不变")
	ok(is_equal_approx(regular.variation_embolden, 0.35) and is_equal_approx(italic.variation_embolden, 0.35), "压缩字体加粗不变")
	ui._cond.clear()
	ui._cond_italic.clear()


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
	# 最大生命的固定加成放在倍率之后（用户 10-29「卡上写多少就加多少」，docs/199）：base × (1 + add) × mult + flat
	var h = SB.new()
	h.define(&"max_hp", 100.0, 1.0, 100000.0)
	h.add(&"max_hp", "flat", 20.0, "card")
	h.add(&"max_hp", "add", 0.3, "meta")
	h.add(&"max_hp", "mult", 1.45, "squad")
	near(h.value(&"max_hp"), 100.0 * 1.3 * 1.45 + 20.0, "max_hp：固定加成在倍率之后")
	near(h.value_with(&"max_hp", "flat", 20.0) - h.value(&"max_hp"), 20.0, "max_hp：卡面预览 +20 就是 +20")


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
	ok(cnt == 265, "读取 265 件藏品（%d）" % cnt)
	var errs: Array = c.validate()
	for e in errs:
		printerr("  数据错误: ", e)
	ok(errs.is_empty(), "效果数据校验")
	ok(c.db.implemented().size() == 265, "已实装藏品 265 件（docs/57 全部实装 + docs/74 吸血两件 + 10-23 穿甲弹，%d）" % c.db.implemented().size())
	# docs/35 藏品契约：说明非空、不再出现「援护干员」、职业门槛合法；分类只用 docs/197 的 11 个键
	var classes := ["先锋", "近卫", "重装", "狙击", "术师", "医疗", "辅助", "特种"]
	for r in c.db.implemented():
		ok(str(r.desc).strip_edges() != "", "藏品 %s 说明非空" % r.id)
		ok(not str(r.desc).contains("援护干员"), "藏品 %s 说明不含「援护干员」" % r.id)
		for cl in r.get("requires_class", []):
			ok(cl in classes, "藏品 %s 职业门槛合法（%s）" % [r.id, cl])
		ok(r.lane in ["melee", "multi", "summon", "control", "weak", "shield", "heal", "class", "general", "survival", "economy"], "藏品 %s 分类合法（%s）" % [r.id, r.lane])
	# docs/55 §4：relic_fx.gd 从数据读的触发参数必须在 relic_effects.json 里（改名 / 删键会让效果静默退回代码默认值）
	var need := {"94": ["pct", "corrode_extra"], "145": ["pct", "class", "icd"], "169": ["class", "not_boss"], "170": ["pct", "boss_pct", "icd"]}
	for id in need:
		var trig: Dictionary = {}
		for ef in c.db.get_relic(id).get("effects", []):
			if ef.get("type", "") == "trigger":
				trig = ef
				break
		ok(not trig.is_empty(), "藏品 %s 有 trigger 效果" % id)
		for k in need[id]:
			ok(trig.get("args", {}).has(k), "藏品 %s 触发参数 %s 存在" % [id, k])
	ok(c.db.get_relic("169").effects[0].get("if", {}).has("target_hp_below"), "藏品 169 处决门槛 target_hp_below 存在")
	# docs/57：第二批原语的数据契约——带参数的规则 / 触发必须在数据里给齐参数（relic_fx.gd 不写死数值）
	var rule_keys := {"hp_dmg": ["max"], "low_hp_haste": ["max", "at"], "far_dmg": ["max", "at"], "zone": ["r", "every"], "sp_pulse": ["every", "pct"],
		"medkit": ["n", "at", "heal"], "unhurt_light": ["t", "amount"], "per_relic": ["stat", "per"], "squad_scale": ["stat", "per", "count"]}
	var do_keys := {"refund": ["class", "pct"], "stack_stat": ["stat", "per", "max"], "invuln": ["dur"], "stun_near": ["min_pct", "r", "dur"],
		"damage_all": ["cd", "dmg"], "random_relic": ["n"], "levels": ["n"], "heal_flat": ["amount"]}
	var new_n := 0
	for r in c.db.implemented():
		if r.get("new_pool", false):
			new_n += 1
			ok(r.rarity in ["基础", "稀有", "核心", "升华", "遭诅古物"], "藏品 %s 稀有度合法（%s）" % [r.id, r.rarity])
		for ef in r.effects:
			var a: Dictionary = ef.get("args", {})
			if ef.get("type", "") == "rule" and rule_keys.has(ef.get("rule", "")):
				for k in rule_keys[ef.rule]:
					ok(a.has(k), "藏品 %s 规则 %s 缺参数 %s" % [r.id, ef.rule, k])
			if ef.get("type", "") in ["trigger", "on_gain"] and do_keys.has(ef.get("do", "")):
				for k in do_keys[ef.do]:
					ok(a.has(k), "藏品 %s 动作 %s 缺参数 %s" % [r.id, ef.do, k])
			if ef.get("type", "") == "trigger" and str(ef.get("event", "")) == "Tick" and a.has("class"):
				ok(a.has("every") and a.has("radius"), "藏品 %s 职业周期伤害缺 every / radius" % r.id)
	ok(new_n > 0, "第二批藏品已标记 new")
	for id in ["54", "56", "120", "121"]:
		c.gain_relic(id)
	c.gain_relic("79")
	near(c.stats.value(&"dmg"), 1.2, "藏品效果生效（79：全伤害 +20%）")
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
		ok(not elites[1].has("requires"), "精英化二不带条件（2026-09-25 用户决定）：%s" % cid)
		# 节点不许只强化还没解锁的技能（2026-09-26：六名干员的 N5 强化精二才有的三技能，选了当下没效果）。
		# 说明里「精英二后……」之后的部分是对未来的补充，不算（docs/37 §6：精一 / 精二一律写精英一 / 精英二）
		var sk_names: Array = d.get("skills", []).map(func(s): return str(s.get("name", "")))
		var unlocked := 1
		for nd in pg:
			if nd.get("type", "") == "elite":
				unlocked = int(nd.level) + 1
				continue
			var txt: String = str(nd.get("desc", "")).split("精英二后")[0]
			for si in range(unlocked, sk_names.size()):
				ok(sk_names[si] == "" or not txt.contains("「%s」" % sk_names[si]), "%s 节点「%s」强化了还没解锁的技能「%s」" % [cid, nd.get("name", ""), sk_names[si]])
	# 契约反例：缺 skill / manual 技能 / 非法节点
	ok(not Ch.validate_operator("bad", {"attack": {"mode": "auto"}}), "缺 skills 不通过")
	ok(not Ch.validate_operator("bad", {"attack": {"mode": "auto"}, "skills": [{"name": "a"}, {"name": "b"}]}), "技能不足 3 个不通过")
	# 契约 v2.2：干员最多 1 个手动技能（幽灵鲨 S2 保命）
	ok(Ch.validate_operator("ok1", {"attack": {"mode": "auto"}, "skills": [{"name": "a"}, {"name": "b", "mode": "manual"}, {"name": "c"}]}), "干员 1 个 manual 技能通过")
	ok(not Ch.validate_operator("bad", {"attack": {"mode": "auto"}, "skills": [{"name": "a", "mode": "manual"}, {"name": "b"}, {"name": "c", "mode": "manual"}]}), "干员 2 个 manual 技能不通过")
	ok(not Ch.validate_operator("bad", {"attack": {"mode": "auto"}, "skills": [{"name": "a"}, {"name": "b", "mode": "toggle"}, {"name": "c"}]}), "非法技能 mode 不通过")
	ok(not Ch.validate_operator("bad", {"attack": {}, "skills": [{"name": "a"}, {"name": "b"}, {"name": "c"}], "progression": [{"type": "elite"}]}), "elite 节点缺 level 不通过")
	# 数据干员的积木校验（docs/61 §8）：等价测试干员通过；改坏一处就不通过
	var eq: Dictionary = Ch.load_def("eqtest")
	ok(eq.has("blocks") and Ch.validate_operator("eqtest", eq), "积木等价测试干员 eqtest 通过校验")
	var bads := {
		"不认识的积木": func(d): d.blocks.skills[0].do[0]["verb"] = "lamb",
		"已登记未实现": func(d): d.blocks.skills[0].do.append({"shape": "chain", "src": "测试脉冲"}),
		"$ 引用不在 base": func(d): d.blocks.skills[0].do[0]["value"] = "$nope",
		"伤害来源没登记": func(d): d.blocks.attack["src"] = "没登记",
		"常驻积木放进触发器": func(d): d.blocks.progression.echo.do.append({"verb": "buff_self", "stat": "zone", "op": "add", "value": 0.1}),
		"permanent 不对应": func(d): d.blocks.skills[1]["dur"] = 0,
		"条件写错": func(d): d.blocks.talent[0]["cond"] = "lamp ~ 3",
		"custom 节点没积木": func(d): d.blocks.progression.erase("res"),
		"max_n 超出范围": func(d): d.blocks.progression.echo.do[0]["max_n"] = 0,
	}
	# max_n 的取舍（docs/61 §3.3）：Boss → 精英 → 其余，同档近的先、再按 id
	var cand := [{"id": 5, "pos": Vector2(10, 0), "boss": false, "elite": false}, {"id": 2, "pos": Vector2(90, 0), "boss": false, "elite": true},
		{"id": 3, "pos": Vector2(10, 0), "boss": false, "elite": false}, {"id": 9, "pos": Vector2(150, 0), "boss": true, "elite": false},
		{"id": 7, "pos": Vector2(40, 0), "boss": false, "elite": false}]
	var picked: Array = Ch.cap_targets(cand, Vector2.ZERO, 3).map(func(e): return e.id)
	ok(picked == [9, 2, 3], "max_n 取舍顺序 Boss → 精英 → 近 → id：%s" % str(picked))
	for why in bads:
		var d2: Dictionary = eq.duplicate(true)
		bads[why].call(d2)
		ok(not Ch.validate_operator("eqtest", d2), "积木校验应拒绝：" + why)


## 干员语音（audio/voice，tools/voice_ogg.py）：清单里每条都有 OGG、能加载、不循环、时长和母带一致；
## sfx.gd 按「干员_事件.ogg」取文件；目录里不能留没转换的 WAV（游戏只读 OGG，WAV 会被静默跳过）
## 帧条 / 动画数据契约 V1–V9（docs/108 §10）：真实数据零错误；每条规则一个坏样例，只报对应编号
func test_operator_contract() -> void:
	var Ch = load("res://scripts/characters/character.gd")
	var C = load("res://scripts/characters/operator_contract.gd")
	for cid in Ch.list_ids():
		var errs: Array = C.errors(Ch.load_def(cid))
		ok(errs.is_empty(), "数据契约零错误：%s %s" % [cid, str(errs)])
	var wd: Dictionary = Ch.load_def("wisadel")
	var sg: Dictionary = Ch.load_def("siege")
	var ir: Dictionary = Ch.load_def("irene")
	var cases := [
		["V1", wd, func(d): d.sprites.skill["attack_timing"] = {"duration": 0.5, "fire_time": 0.6, "active_ratio": 0.9, "windup_ratio": 0.45}],
		["V2", wd, func(d): d.sprites.erase("foot_exempt")],
		["V2", sg, func(d): d.sprites.heavy_attack.foot = [40, 68]],
		["V2", sg, func(d): d.sprites.size = 96],
		["V4", sg, func(d): d.native_motion.states[0].to = 99],
		["V4", sg, func(d): d.native_motion["clip"] = {}],
		["V4", ir, func(d): d.native_motion.variants[0]["perm"] = 1],   # perm 与 node 二选一
		["V4", ir, func(d): d.native_motion["yield"] = "finisher"],
		["V5", wd, func(d): d.sprites.s2_attack.muzzles.pop_back()],
		["V6", wd, func(d): d.sprites.s2_attack.muzzles[0] = [1]],
		["V7", sg, func(d): d.sprites.attack.fire_time = 0.001],   # 只破坏画面事件，不同时破坏独立的阶段时钟。
		["V8", sg, func(d): d.extra_sprites.erase("leap_native")],
		["V8", sg, func(d): d.native_motion.clips["nope"] = 0.5],
		["V9", wd, func(d): d.sprites["draw_scale"] = 0.9],
	]
	for c in cases:
		var d: Dictionary = c[1].duplicate(true)
		c[2].call(d)
		var errs: Array = C.errors(d)
		ok(not errs.is_empty() and errs.all(func(e): return str(e).begins_with(c[0] + " ")), "数据契约坏样例只报 %s：%s" % [c[0], str(errs)])


func test_voice() -> void:
	var man = JSON.parse_string(FileAccess.get_file_as_string("res://audio/voice/voice_manifest.json"))
	ok(man is Dictionary and man.get("clips", []).size() >= 91, "语音清单可读，至少 91 条（66 + 第五批 25）")
	if not man is Dictionary:
		return
	var SfxS = load("res://scripts/sfx.gd")
	var have := {}
	for c in man.clips:
		var f: String = c.file
		have[f] = true
		ok(f == "%s_%s.ogg" % [c.operator, c.event], "语音文件名 = 干员_事件.ogg：" + f)
		var path := "res://audio/voice/" + f
		var st = load(path) if ResourceLoader.exists(path) else null
		ok(st is AudioStreamOggVorbis, "语音能加载为 OGG：" + f)
		if st is AudioStreamOggVorbis:
			ok(not st.loop, "语音不循环：" + f)
			ok(absf(st.get_length() - float(c.duration_seconds)) < 0.01, "语音时长与母带一致：%s（%.3f / %.3f）" % [f, st.get_length(), float(c.duration_seconds)])
			ok(st.get_length() <= SfxS.VOICE_MAX_LEN, "语音不超过 VOICE_MAX_LEN（超长会被 sfx.gd 静默丢掉）：%s %.2f 秒" % [f, st.get_length()])
	# 第五批语音（第三批干员，art/archive/incoming_1028/voice_batch5_1012，2026-10-12）：五人 × 五个事件齐全
	for cid in ["texas", "hoshiguma", "angelina", "skalter", "exusiai"]:
		ok(man.operators.has(cid), "语音清单登记了干员：" + cid)
		for ev in ["entry", "skill_1", "skill_2", "skill_3", "battle"]:
			ok(have.has("%s_%s.ogg" % [cid, ev]), "语音齐全：%s_%s" % [cid, ev])
	for f in DirAccess.get_files_at("res://audio/voice"):
		ok(f.get_extension() != "wav", "audio/voice 里有没转换的 WAV（先跑 tools/voice_ogg.py）：" + f)


## 语音打断规则（用户 10-12「语音用1」方案 A，sfx.gd voice_can_cut）：技能语音只打断正在说的战斗台词（battle / W 笑声），
## 间隔从打断时刻起算；技能 / 部署语音互不打断，战斗台词不打断任何语音，台词播完后的静默间隔里技能语音照旧放弃。
## 这里 Sfx 不在场景树里（不真的出声），用 voice_now 拨钟只验证调度
func test_voice_interrupt() -> void:
	var S = load("res://scripts/sfx.gd").new()
	S.voice_player = AudioStreamPlayer.new()
	S.voice_fader = AudioStreamPlayer.new()
	S.voice_pools = {"_": {}}   # 只验打断调度：不走语音池（docs/190），固定读 <干员>_<事件>.ogg
	var GAP: float = S.VOICE_GAP
	var fresh := func(t: float) -> void:
		S.voice_reset()
		S.voice_end = 0.0
		S.voice_last.clear()
		S.voice_op_last.clear()
		S.voice_now = t
	var at := func(t: float, cid: String, key: String, q := false) -> void:
		S.voice_now = t
		S.voice(cid, key, q)
	var len_of := func(cid: String, key: String) -> float:
		var st = S._voice_stream(cid, key)
		return st.get_length() if st != null else -1.0
	var cur := func() -> String:
		return "%s:%s" % [S.voice_cid, S.voice_key]
	ok(len_of.call("hoshiguma", "battle") > 2.0 and len_of.call("texas", "skill_1") > 0.0, "打断测试用的语音能加载")
	# 技能打断战斗台词；被打断的那条换到 voice_fader，间隔从打断时刻起算
	fresh.call(1000.0)
	at.call(1000.0, "hoshiguma", "battle")
	ok(cur.call() == "hoshiguma:battle", "战斗台词开播：" + cur.call())
	var bst = S.voice_player.stream
	at.call(1001.0, "texas", "skill_1")
	ok(cur.call() == "texas:skill_1", "技能语音打断正在说的战斗台词：" + cur.call())
	ok(S.voice_fader.stream == bst and S.voice_player.stream != bst, "被打断的台词换到淡出播放器")
	near(S.voice_end, 1001.0 + len_of.call("texas", "skill_1") + GAP, "打断后全队间隔从打断时刻起算")
	# 技能不打断技能
	at.call(1001.3, "exusiai", "skill_3")
	ok(cur.call() == "texas:skill_1", "技能语音不打断技能语音：" + cur.call())
	# 技能不打断部署
	fresh.call(2000.0)
	at.call(2000.0, "skalter", "entry", true)
	at.call(2001.0, "hoshiguma", "skill_2")
	ok(cur.call() == "skalter:entry", "技能语音不打断部署语音：" + cur.call())
	# 战斗台词不打断台词，部署语音也不打断台词（照旧排队）
	fresh.call(3000.0)
	at.call(3000.0, "hoshiguma", "battle")
	at.call(3001.0, "texas", "battle")
	ok(cur.call() == "hoshiguma:battle", "战斗台词不打断战斗台词：" + cur.call())
	at.call(3001.5, "angelina", "entry", true)
	ok(cur.call() == "hoshiguma:battle" and S.voice_queue.size() == 1, "部署语音不打断台词、进队列：%s 队列 %d" % [cur.call(), S.voice_queue.size()])
	# 战斗台词不打断技能
	fresh.call(4000.0)
	at.call(4000.0, "texas", "skill_1")
	at.call(4000.3, "hoshiguma", "battle")
	ok(cur.call() == "texas:skill_1", "战斗台词不打断技能语音：" + cur.call())
	# 台词已经说完、还在 VOICE_GAP 静默期：技能语音照旧放弃
	fresh.call(5000.0)
	at.call(5000.0, "hoshiguma", "battle")
	at.call(5000.0 + len_of.call("hoshiguma", "battle") + 0.5, "texas", "skill_1")
	ok(cur.call() == "hoshiguma:battle", "台词播完后的静默间隔里技能语音不插播：" + cur.call())
	# W 的笑声同属战斗台词
	if len_of.call("wisadel", "w_laugh") > 0.0:
		fresh.call(6000.0)
		at.call(6000.0, "wisadel", "w_laugh")
		at.call(6000.2, "texas", "skill_1")
		ok(cur.call() == "texas:skill_1", "技能语音打断 W 的笑声：" + cur.call())
	# 终结技语音（docs/205，用户 10-30）：打断正在说的任何一句（含技能语音），说完 + VOICE_ULT_HOLD 内别人一律不开口
	fresh.call(7000.0)
	at.call(7000.0, "hoshiguma", "skill_2")
	S.voice_now = 7000.3
	S.voice("texas", "ult", false, true, "texas_skill_3")
	ok(cur.call() == "texas:ult" and S.voice_player.stream == S._voice_file("texas_skill_3"), "终结技语音打断技能语音、播指定句：" + cur.call())
	var ul: float = S._voice_file("texas_skill_3").get_length()
	at.call(7000.3 + ul + 0.2, "exusiai", "skill_1")
	ok(cur.call() == "texas:ult", "终结技语音说完 0.5 秒内别人的技能语音不播：" + cur.call())
	S.voice_lock(2.0)
	at.call(7000.3 + 1.5, "saria", "command")
	ok(cur.call() == "texas:ult", "voice_lock 延长期间指挥回应也不播：" + cur.call())
	at.call(7000.3 + maxf(ul + 0.5, 2.0) + 3.5, "exusiai", "skill_1")
	ok(cur.call() == "exusiai:skill_1", "锁定结束后照常：" + cur.call())
	S.voice_player.free()
	S.voice_fader.free()
	S.free()


## 星熊的新积木（docs/61「星熊」节，op_blocks.gd 末尾「星熊 hoshiguma」段）：校验正反例、编译结果、线段判定、格挡概率、随机数只在需要时取
func test_hoshiguma_blocks() -> void:
	var Ch = load("res://scripts/characters/character.gd")
	var OB = load("res://scripts/characters/op_blocks.gd")
	var hd: Dictionary = Ch.load_def("hoshiguma")
	ok(hd.has("blocks") and Ch.validate_operator("hoshiguma", hd), "星熊（数据干员）通过校验")
	var bads := {
		"negate_next 只能放技能 do": func(d): d.blocks.talent[0].do.append({"verb": "negate_next"}),
		"常驻 verb.dr 放进触发器": func(d): d.blocks.talent[0].do.append({"verb": "dr", "value": 0.1}),
		"on_hurt 概率超过 1": func(d): d.blocks.talent[0]["chance"] = 1.5,
		"on_hurt negate 不是布尔": func(d): d.blocks.talent[0]["negate"] = "yes",
		"shape.line 缺 len": func(d): d.blocks.skills[2].do[2].attack.erase("len"),
		"shape.line 伤害来源没登记": func(d): d.blocks.skills[2].do[2].attack["src"] = "没登记",
		"swap_attack 不是伤害形状": func(d): d.blocks.skills[2].do[2]["attack"] = {"verb": "dr", "value": 0.1},
		"verb.field 没有 do": func(d): d.blocks.trait[1].do[0].erase("do"),
		"verb.field 的 center 写错": func(d): d.blocks.trait[1].do[0]["center"] = "moon",
		"verb.dr 超出范围": func(d): d.blocks.skills[1].do[1]["value"] = 1.2,
		"negate_chance 什么都没写": func(d): d.blocks.skills[1].do[2].erase("mult"),
		"displace 缺 kb": func(d): d.blocks.talent[0].do[0].erase("kb"),
		"on_negate 里放常驻积木": func(d): d.blocks.progression.wall.do.append({"verb": "negate_chance", "add": 0.1}),
		"条件写错": func(d): d.blocks.talent[1]["cond"] = "beacon_chargin",
	}
	for why in bads:
		var d2: Dictionary = hd.duplicate(true)
		bads[why].call(d2)
		ok(not Ch.validate_operator("hoshiguma", d2), "星熊积木校验应拒绝：" + why)
	# 编译：$ 表达式解析成数字（单运算）
	var cb: Dictionary = OB.compile(hd)
	near(float(cb.talent[0].chance), float(hd.base.block_chance), "编译：战术装甲概率 = $block_chance")
	near(float(cb.skills[2].do[2].attack.kb), float(hd.base.kb) * float(hd.base.s3_kb), "编译：力之锯击退 = $kb*$s3_kb")
	near(float(cb.trait[1].do[0].do[0].mult), float(hd.base.sand_mult) * float(hd.base.sand_tick), "编译：热砂每跳 = $sand_mult*$sand_tick")
	ok(cb.talent[1].cond is Dictionary and str(cb.talent[1].cond.k) == "beacon_charging", "编译：beacon_charging 条件")
	# 线段判定：原点朝右、长 220、宽 50
	var R := Vector2.RIGHT
	ok(OB.line_contains(Vector2.ZERO, R, 220.0, 50.0, Vector2(100, 20), 8.0), "直线斩：线内")
	ok(not OB.line_contains(Vector2.ZERO, R, 220.0, 50.0, Vector2(100, 40), 8.0), "直线斩：偏出半宽 + 半径")
	ok(not OB.line_contains(Vector2.ZERO, R, 220.0, 50.0, Vector2(-20, 0), 8.0), "直线斩：身后")
	ok(OB.line_contains(Vector2.ZERO, R, 220.0, 50.0, Vector2(225, 0), 8.0), "直线斩：末端擦边")
	# 格挡概率：Boss 用 boss_chance；negate 触发器吃 add / mult，夹到 max_chance；非 negate 触发器不吃
	var t := {"chance": 0.2, "boss_chance": 0.1, "negate": true, "max_chance": 0.8}
	near(OB.hurt_chance(t, false, 0.0, 1.0), 0.2, "格挡概率：普通")
	near(OB.hurt_chance(t, true, 0.0, 1.0), 0.1, "格挡概率：Boss")
	near(OB.hurt_chance(t, false, 0.15, 2.0), 0.7, "格挡概率：灯标 +0.15、荆棘 ×2")
	near(OB.hurt_chance(t, false, 0.5, 2.0), 0.8, "格挡概率：封顶 max_chance")
	near(OB.hurt_chance({}, false, 0.5, 2.0), 1.0, "非 negate 触发器：概率恒为 1，不吃加成")
	# 随机数：概率 0 / 1 不取数（不改变 g.rng_op 序列），(0, 1) 取一次
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var fake := {"rng_op": rng}   # 积木随机走 rng_op（docs/101 B7）
	var st0: int = rng.state
	ok(OB.roll(fake, 1.0) and not OB.roll(fake, 0.0) and rng.state == st0, "roll：概率 0 / 1 不取随机数")
	OB.roll(fake, 0.5)
	ok(rng.state != st0, "roll：概率 (0, 1) 取一次随机数")


## 安洁莉娜段的积木（docs/61 §12）：校验接受 angelina.json、拒绝放错位置 / 参数越界；位移反解、失重倍率、悬浮高度的数学
func test_blocks_angelina() -> void:
	var Ch = load("res://scripts/characters/character.gd")
	var OB = load("res://scripts/characters/op_blocks.gd")
	var an: Dictionary = Ch.load_def("angelina")
	ok(an.has("blocks") and Ch.validate_operator("angelina", an), "安洁莉娜通过积木校验")
	var bads := {
		"落点弹放进技能 do": func(d): d.blocks.skills[2].do.append({"shape": "point_aoe", "range": 300, "r": 60, "src": "重力弹"}),
		"环带整形不在力场里": func(d): d.blocks.attack.then[0]["dir"] = "ring",
		"力场没有子项": func(d): d.blocks.skills[1].do[0]["tick"] = [],
		"where ring 但力场没写 ring": func(d): d.blocks.skills[2].do[0].tick.append({"st": "dot", "mult": 0.1, "src": "潮汐锁", "where": "ring"}),
		"持续伤害不在力场里": func(d): d.blocks.attack.on_hit.append({"st": "dot", "mult": 0.1, "src": "潮汐锁"}),
		"次数型写成永久": func(d): d.skills[0]["permanent"] = true,
		"attack_patch 不认识的键": func(d): d.blocks.skills[0].attack_patch["boom"] = 1,
		"attack_patch 只能跟 next_attacks": func(d): d.blocks.skills[2]["attack_patch"] = {"mult": 2.0},
		"主控属性不在白名单": func(d): d.blocks.skills[1].do[1]["stat"] = "armor",
		"失重倍率小于 1": func(d): d.blocks.attack.then[0].on_hit[0]["kb_mult"] = 0.5,
		"落点触发器的 do 放常驻积木": func(d): d.blocks.progression.pull2.do.append({"verb": "buff_leader", "stat": "pickup", "op": "mult", "value": 2.0}),
		"位移距离越界": func(d): d.blocks.attack.then[0]["dist"] = 999,
	}
	for why in bads:
		var d2: Dictionary = an.duplicate(true)
		bads[why].call(d2)
		ok(not Ch.validate_operator("angelina", d2), "安洁莉娜积木校验应拒绝：" + why)
	# 位移反解（enemies.gd：位移按 e.kb × m 走，e.kb 每秒衰减 900）：60 帧步进模拟，实际位移与目标差 < 3% + 2 像素（先移动后衰减，离散步多走约半帧）
	for m in [1.0, 0.3, 1.4]:
		for want in [15.0, 40.0, 80.0]:
			var kb: float = OB.kb_for(want, m)
			var moved := 0.0
			var dt := 1.0 / 60.0
			while kb > 0.0:
				moved += kb * m * dt
				kb = move_toward(kb, 0.0, OB.KB_DECAY * dt)
			ok(absf(moved - want) < 0.03 * want + 2.0, "位移反解：m=%.1f 目标 %.0f 实际 %.1f" % [m, want, moved])
	ok(OB.kb_for(10.0, 0.0) == 0.0 and OB.kb_for(0.0, 1.0) == 0.0, "位移反解：m 或距离为 0 时不推")
	# 失重：期间返回 wl_kb，过期 / 没有 = 1.0（melee_hit 乘它，老干员逐字节不变）
	ok(OB.kb_taken({}, 5.0) == 1.0, "没失重 = 1.0")
	ok(is_equal_approx(OB.kb_taken({"wl_t": 6.0, "wl_kb": 1.3}, 5.0), 1.3), "失重期间 = wl_kb")
	ok(OB.kb_taken({"wl_t": 6.0, "wl_kb": 1.3}, 6.5) == 1.0, "失重过期 = 1.0")
	# 悬浮高度：起跳 0 → 中段满高 → 落地 0
	near(OB.air_height({"t": 0.0, "dur": 1.0, "h": 30.0}), 0.0, "悬浮起点高度 0")
	near(OB.air_height({"t": 0.5, "dur": 1.0, "h": 30.0}), 30.0, "悬浮中段满高")
	near(OB.air_height({"t": 1.0, "dur": 1.0, "h": 30.0}), 0.0, "悬浮终点高度 0")


## 德克萨斯段积木（docs/61 §13，op_blocks.gd 末尾）：texas.json 通过校验；改坏一处就不通过；冲刺长度 / 宽度倍率与主控属性修正的累计
## 自动技能需要敌人（10-23 用户定全员统一；10-25 扩到所有自动技能含治疗 / 增益 / 永久类）：blocks.skills[i].need_enemy 是显式门槛（可省，省了按伤害积木半径 / 普攻射程推，见 test_skill_gate），
## 手动技能（mode manual）不写、不查门槛
func test_need_enemy_data() -> void:
	var Ch = preload("res://scripts/characters/character.gd")
	var bad: Array = []
	for id in ["angelina", "exusiai", "eyjafjalla", "gladiia", "hoshiguma", "irene", "kaltsit", "lappland", "logos", "lumen", "mizuki", "saria", "siege", "skadi", "skalter", "specter_unchained", "suzuran", "texas", "ulpianus", "wisadel"]:
		var d: Dictionary = Ch.load_def(id)
		var sk: Array = d.blocks.skills
		for i in sk.size():
			if sk[i].has("need_enemy") and str(d.skills[i].get("mode", "auto")) == "manual":
				bad.append("%s S%d" % [id, i + 1])
	ok(bad.is_empty(), "need_enemy 不给手动技能：%s" % str(bad))


## 自动技能「范围内没有敌人不放」门槛（10-25 用户）：每个干员的每个技能都能推出门槛距离（need_enemy → 伤害积木半径 → 普攻射程），且在合理范围；
## 推进之王跃空锤只在周围 s2_r 内有敌人时放（不再是泛泛 150）。GATE_TABLE=1 时打印全表
func test_skill_gate() -> void:
	var Ch = preload("res://scripts/characters/character.gd")
	var OB = preload("res://scripts/characters/op_blocks.gd")
	var table := OS.get_environment("GATE_TABLE") == "1"
	for id in Ch.list_ids():
		var d: Dictionary = Ch.load_def(id)
		if not d.has("blocks"):
			continue
		var B: Dictionary = OB.compile(d)
		for i in B.skills.size():
			if B.skills[i].get("no_gate", false):
				ok(true, "%s S%d 治疗类不加门槛（no_gate）" % [id, i + 1])
				if table:
					print("GATE ", id, " S", i + 1, " none (heal)")
				continue
			var g: float = OB.skill_gate_base(B.skills[i], B.get("attack", {}), {}, 0.0)
			if table:
				print("GATE ", id, " S", i + 1, " ", snappedf(g, 1.0), " ", "need" if B.skills[i].has("need_enemy") else "derived")
			ok(g >= 30.0 and g <= 700.0, "%s S%d 自动技能门槛距离可推出且合理（%s）" % [id, i + 1, g])
	var sg: Dictionary = OB.compile(Ch.load_def("siege"))
	near(OB.skill_gate_base(sg.skills[1], sg.attack, {}, 0.0), float(Ch.load_def("siege").base.s2_r) + 20.0, "推进之王 S2 门槛 = 跃空锤半径 + 20（原来 150）")


func test_blocks_texas() -> void:
	var Ch = preload("res://scripts/characters/character.gd")
	var OB = preload("res://scripts/characters/op_blocks.gd")
	var tx: Dictionary = Ch.load_def("texas")
	ok(tx.has("blocks") and Ch.validate_operator("texas", tx), "德克萨斯 texas.json 通过积木校验")
	var bads := {
		"冲刺 aim 写错": func(d): d.blocks.response[1].do[0]["aim"] = "random",   # 10-25 合并后 trait: 0 出手回技力 / 1-4 骤雨 / 5 精一回技力 / 6 突进多命中 / 7 次元斩 / 8 冲刺斩回技力（队友短突进与分身 tick 已删）；冲刺积木校验用响应块 response[1]
		"突进 need_target 写成字符串": func(d): d.blocks.response[1].do[0]["need_target"] = "yes",
		"骤雨 no_combo 写成字符串": func(d): d.blocks.trait[1]["no_combo"] = "yes",
		"no_combo 配了非 replace 的 every_n": func(d): d.blocks.trait[2]["no_combo"] = true,
		"冲刺缺宽度": func(d): d.blocks.response[1].do[0].erase("w"),
		"自动技能 need_enemy 超范围": func(d): d.blocks.skills[0]["need_enemy"] = 0.5,
		"主控冲刺冷却不再是可写的主控属性（10-12 自动冲刺改版）": func(d): d.blocks.skills[1].do.append({"verb": "buff_leader", "stat": "dash_cd", "op": "mult", "value": 0.8}),
		"突进不是瞬时冲刺放进常驻列表": func(d): d.blocks.talent.append({"trig": "passive", "do": [d.blocks.response[1].do[0].duplicate(true)]}),
		"瞬时冲刺放进常驻节点": func(d): d.blocks.progression["wide"] = {"shape": "dash_line", "r": 100, "w": 40, "src": "疾行斩"},
		"常驻 dash_mod 放进触发器": func(d): d.blocks.trait[0].do.append({"verb": "dash_mod", "len_add": 0.1}),
		"触发积木放进技能 do": func(d): d.blocks.skills[0].do.append({"trig": "on_dash_end", "do": []}),
		"on_dash_end 的 src 没登记": func(d): d.blocks.trait[6]["src"] = "没登记",
		"残像伤害超上限": func(d): d.blocks.progression.elite2.do[0]["mult"] = 50,
		"fx_rain 缺帧条": func(d): d.blocks.skills[0].do[2].erase("strip"),
		"fx_rain 既没 density 也没 n": func(d): d.blocks.skills[0].do[2].erase("density"),
		"fx_rain 参数名写错": func(d): d.blocks.skills[0].do[2]["fal"] = 90,
		"fx_rain 冲击帧条不是 fx_*": func(d): d.blocks.skills[0].do[2]["hit"] = "texas_hit",
		"fx_rain 层写错": func(d): d.blocks.skills[0].do[2]["layer"] = "floor",
		"fx_rain 下落时间超范围": func(d): d.blocks.skills[0].do[2]["fall_t"] = 3.0,
		"fx_rain 放进常驻节点": func(d): d.blocks.progression["wide"] = d.blocks.skills[0].do[2].duplicate(true),
	}
	for why in bads:
		var d2: Dictionary = tx.duplicate(true)
		bads[why].call(d2)
		ok(not Ch.validate_operator("texas", d2), "德克萨斯积木校验应拒绝：" + why)
	# 编译：$ 表达式解析成数字、每块编号
	var B: Dictionary = OB.compile(tx)
	# 10-23 重设计（docs/129）：队长普攻原地两连斩；队友短突进 10-25 已删；天赋定时自动冲刺已删
	ok(B.talent.size() == 2 and str(B.talent[0].get("_tag", "")) == "trig.on_dash_end" and str(B.talent[0].src) == "战术快递", "天赋只剩 on_dash_end 回技力（定时自动冲刺的两块 tick 已删）")
	var has_mate_step := false
	var has_roam_dash := false
	for tb in B.trait:
		if str(tb.get("_tag", "")) == "trig.tick" and tb.has("do") and not tb.do.is_empty() and str(tb.do[0].get("src", "")) == "突进":
			if tb.get("cond", {}) is Dictionary and str(tb.cond.get("k", "")) == "roaming":
				has_roam_dash = true
			else:
				has_mate_step = true
	ok(not has_mate_step, "队友平时短突进已删（10-25 用户：平时不自动冲锋，队友只在队长冲刺时跟随）：特性里没有无条件的 src 突进 tick 块")
	ok(has_roam_dash, "突击模式低频冲刺（10-26 用户）：特性里有 cond roaming 的 src 突进 tick 块")
	ok(str(B.trait[1].get("_tag", "")) == "trig.every_n" and int(B.trait[1].n) == 4 and bool(B.trait[1].replace) and bool(B.trait[1].no_combo) and str(B.trait[1].do[0].get("_tag", "")) == "shape.circle" and float(B.trait[1].do[0].r) == 100.0 and absf(float(B.trait[1].do[0].mult) - 0.55) < 0.0001, "骤雨第一下：每第 4 次出手 replace + no_combo，360° 圆半径 100、每下 55%")
	ok(absf(float(B.trait[2].delay) - 0.2) < 0.0001 and absf(float(B.trait[3].delay) - 0.4) < 0.0001 and absf(float(B.trait[4].delay) - 0.6) < 0.0001 and str(B.trait[2].cond) != "" and not B.trait[2].get("replace", false), "骤雨第二 / 三 / 四下：非 replace 的 every_n、delay 0.2 / 0.4 / 0.6")
	ok(float(B.skills[0].need_enemy) == 130.0 and float(B.skills[2].need_enemy) == 230.0 and not B.skills[1].has("need_enemy"), "剑雨 / 剑雨滂沱自动释放需要敌人（130 / 230），冲锋号令·γ型（永久增益）不要")
	# 响应动作（docs/118 §4.1）：队长冲刺 → 同向冲刺（aim leader_dir，来源同战术快递，精英一起）
	ok(B.has("response") and str(B.response[1].get("_tag", "")) == "trig.on_leader_dash" and str(B.response[1].do[0].aim) == "leader_dir" and str(B.response[1].do[0].src) == "战术快递", "响应：队长冲刺 → dash_line leader_dir（来源战术快递）")
	ok(str(B.response[0].do[0].aim) == "leader_dir" and str(B.response[0].do[0].src) == "冲刺斩" and str(B.response[0].get("hint", "")) == "专属冲刺", "响应：她当队长精零自己冲刺 → 专属冲刺（leader_dir，来源冲刺斩）")
	ok(str(B.attack.get("_tag", "")) == "shape.cone" and float(B.attack.r) == 112.0 and absf(float(B.attack.half) - 1.2) < 0.0001 and B.attack.combo.size() == 1 and B.attack.on_hit.size() == 2 and int(B.attack.on_hit[0].nearest_n) == 2, "普攻编译成 shape.cone（拔刀：原地宽扇形 112、半角 1.2）+ 1 段 combo（回马剑）+ 阻挡 on_hit（nearest_n 2）")
	# 常驻累计：S2 冲刺长度 +40%；不写主控属性（docs/202：节点「阔剑」已换成「居合」，宽度不再变）
	var fake := {"tx": {}}
	var want: Array = []
	OB.tx_sustain(fake, [B.skills[1].do[0], B.skills[1].do[1]], want)
	near(float(fake.tx.len), 1.4, "冲刺长度倍率 (1 + 0.4)")
	near(float(fake.tx.get("w", 1.0)), 1.0, "冲刺宽度倍率不变（节点 1 已换成居合）")
	ok(str(B.progression.wide[0].get("_tag", "")) == "trig.on_hit_n" and str(B.progression.wide[0].do[0].get("_tag", "")) == "verb.dash_cd_cut" and str(B.progression.sharp[0].do[0].get("_tag", "")) == "verb.break_windup", "docs/202：节点 1 居合 = 命中缩短冲刺冷却，节点 2 破绽 = 打断前摇")
	ok(want.is_empty(), "主控属性修正不在 tx_sustain 里写（verb.buff_leader 归共用段，data_operator._sustain 统一写）：%s" % str(want))
	fake.tx = {}
	want = []
	OB.tx_sustain(fake, [], want)
	ok(float(fake.tx.len) == 1.0 and float(fake.tx.w) == 1.0 and want.is_empty(), "没有常驻积木时倍率回到 1、不写主控属性")


## 常驻跟随帧条 hold / 进出淡入淡出 fade / if_tex / ground 层（docs/61 §5.6，10-12 浊心斯卡蒂 S3 地面漩涡接入）：校验正反例 + 淡入淡出与贴图取舍
func test_fx_hold() -> void:
	var Ch = preload("res://scripts/characters/character.gd")
	var OB = preload("res://scripts/characters/op_blocks.gd")
	var sk: Dictionary = Ch.load_def("skalter")   # S3 do[0].fx：[0] 地面漩涡 hold 帧条、[1] 程序漩涡（10-21 删了贴身两条后的下标）
	ok(sk.has("blocks") and Ch.validate_operator("skalter", sk), "浊心斯卡蒂（含 S3 地面漩涡 hold 帧条）通过校验")
	var bads := {
		"hold 帧条挂在技能发动上（瞬时）": func(d): d.blocks.skills[2].fx.append({"strip": "fx_skalter_vortex_floor", "hold": true, "layer": "ground"}),
		"ground 层不是 hold 帧条": func(d): d.blocks.skills[2].do[0].fx[0].erase("hold"),
		"hold 帧条写 every": func(d): d.blocks.skills[2].do[0].fx[0]["every"] = 1.0,
		"hold 帧条放贴身层": func(d): d.blocks.skills[2].do[0].fx[0]["layer"] = "behind",
		"hold 帧条 at = hits": func(d): d.blocks.skills[2].do[0].fx[0]["at"] = "hits",
		"hold 不是布尔": func(d): d.blocks.skills[2].do[0].fx[0]["hold"] = 1,
		"fade 超出范围": func(d): d.blocks.skills[2].do[0].fx[0]["fade"] = 9,
		"fade 写成三个数": func(d): d.blocks.skills[2].do[0].fx[0]["fade"] = [0.1, 0.2, 0.3],
		"fade 写在一次性条目上": func(d): d.blocks.skills[2].fx[0]["fade"] = 0.3,
		"if_tex 不是帧条名": func(d): d.blocks.skills[2].do[0].fx[1]["if_tex"] = "!skalter",
		"vortex 写 hold": func(d): d.blocks.skills[2].do[0].fx[1]["hold"] = true,
	}
	for why in bads:
		var d2: Dictionary = sk.duplicate(true)
		bads[why].call(d2)
		ok(not Ch.validate_operator("skalter", d2), "fx hold 校验应拒绝：" + why)
	# 淡入淡出：hold 帧条 fade 0.45 进出；缺省 贴身层 (0, 0.15)、漩涡 (0.5, 0.4)、hold (0.3, 0.3)
	var hs := {"strip": "fx_x", "hold": true, "fade": 0.45}
	near(OB.fx_hold_alpha(hs, {"el": 0.225, "fade": -1.0}), 0.5, "hold 帧条淡入一半")
	near(OB.fx_hold_alpha(hs, {"el": 3.0, "fade": -1.0}), 1.0, "hold 帧条生效中满透明度")
	near(OB.fx_hold_alpha(hs, {"el": 3.0, "fade": 0.09}), 0.2, "hold 帧条退出淡出")
	near(OB.fx_hold_alpha({"strip": "fx_x", "layer": "behind"}, {"el": 0.0, "fade": -1.0}), 1.0, "贴身层缺省不淡入")
	near(OB.fx_hold_alpha({"strip": "fx_x", "layer": "front"}, {"el": 1.0, "fade": 0.075}), 0.5, "贴身层缺省 0.15 秒淡出")
	near(OB.fx_hold_alpha({"vortex": {}}, {"el": 0.25, "fade": 0.2}), 0.25, "漩涡缺省 0.5 秒淡入 × 0.4 秒淡出")
	near(OB.fx_hold_alpha({"strip": "fx_x", "hold": true, "fade": [0.2, 0.0]}, {"el": 1.0, "fade": 0.1}), 0.0, "淡出 0 秒 = 退出即消失")
	near(OB.fx_hold_out([{"strip": "fx_x", "layer": "behind"}, {"vortex": {}}, hs]), 0.45, "记录保留 = 各条目淡出最大值")
	near(OB.fx_hold_out([{"strip": "fx_x", "layer": "behind"}]), 0.15, "只有贴身层时同原来 0.15")
	# if_tex：有贴图才画 / 缺贴图才画（程序回退）
	var fo := {"g": {"tex": {"fx_have": ImageTexture.new()}}}
	ok(OB.fx_on(fo, {"if_tex": "fx_have"}) and not OB.fx_on(fo, {"if_tex": "!fx_have"}), "if_tex：贴图在时只画正向条目")
	ok(OB.fx_on(fo, {"if_tex": "!fx_none"}) and not OB.fx_on(fo, {"if_tex": "fx_none"}), "if_tex：缺图时只画回退条目")
	# 扩散缓动 / 交叉淡入淡出 / 余波环（10-13 加，§5.6）：反例被拒、缓动曲线端点。
	# 10-29 浊心的波纹帧条全换成歌声波后 json 里没有样本了：测试自带一条（原普攻第 3 条），先确认它本身合法，再逐项改坏
	var WAVE := {"strip": "fx_skalter_wave", "if_tex": "!fx_skalter_wave_big", "max_scale": 4, "layer": "floor", "cond": "lamp >= $talent_dark", "xfade": 0.4, "ease": "out2", "grow": 0.7, "grow0": 0.1, "grow_to": "zone", "tint": [0.78, 0.95, 0.9, 0.5], "wake": {"n": 2, "w": 12, "a": 0.55, "lag": 0.09, "col": [0.55, 0.92, 1.0]}}
	var dw: Dictionary = sk.duplicate(true)
	dw.blocks.attack.fx.append(WAVE.duplicate(true))
	ok(Ch.validate_operator("skalter", dw), "fx 扩散缓动样本本身合法")
	var bad2 := {
		"ease 不认识": func(d): d.blocks.attack.fx[-1]["ease"] = "bounce",
		"grow 没配 ease": func(d): d.blocks.attack.fx[-1].erase("ease"),
		"grow_to 不是 zone": func(d): d.blocks.attack.fx[-1]["grow_to"] = "screen",
		"grow 超出范围": func(d): d.blocks.attack.fx[-1]["grow"] = 9.0,
		"wake 参数不认识": func(d): d.blocks.attack.fx[-1].wake["glow"] = 1,
		"wake.n 超出范围": func(d): d.blocks.attack.fx[-1].wake["n"] = 9,
		"xfade 没配 cond": func(d): d.blocks.attack.fx[-1].erase("cond"),
		"ease 配 hold": func(d): d.blocks.skills[2].do[0].fx[0]["ease"] = "out",
	}
	for why in bad2:
		var d3: Dictionary = sk.duplicate(true)
		d3.blocks.attack.fx.append(WAVE.duplicate(true))
		bad2[why].call(d3)
		ok(not Ch.validate_operator("skalter", d3), "fx 扩散缓动校验应拒绝：" + why)
	near(OB.fx_ease("out", 0.0), 0.0, "缓动起点 0")
	near(OB.fx_ease("out2", 1.0), 1.0, "缓动终点 1")
	near(OB.fx_ease("out2", 0.5), 0.75, "out2 先快后慢")
	near(OB.fx_ease("linear", 0.3), 0.3, "linear 匀速")


## 干员数值表（选人「属性」页 / 图鉴「属性」页共用，screens/initial_stats.gd）：每名可招募干员都有完整的 9 行 + 定位，
## 减伤保留一位小数（docs/72 §4.1 #4：0.5 档不能被截断），特殊干员的标签 / 段数说明正确
## 干员文字的数值占位（docs/61 §1.4，character.gd fill_text）：表达式求值、格式与 tools/op_text_check.py 一致；正式名单加载后不留占位
func test_op_text_fill() -> void:
	var Ch = preload("res://scripts/characters/character.gd")
	var b := {"a": 1.15, "p": 0.02, "m": 10, "h": 0.01275, "s": 0.2, "t": 0.125}
	ok(Ch.fill_line("+{$a*100-100}%、最多 +{$p*$m*100}%、{$h*100}%、{(1-$s)*100}%、{$t}", b) == "+15%、最多 +20%、1.275%、80%、0.125", "占位：加减乘除、括号、最多 3 位小数")
	ok(Ch.fill_line("{hp_per_member} {x}", b) == "{hp_per_member} {x}", "不含 $ 的花括号原样保留（指南占位另有 fill_numbers）")
	ok(Ch.fill_line("{$a*$m*13:0} / {$h*100:1}", b) == "150 / 1.3", "占位：末尾 :N 指定小数位")
	ok(Ch.text_fmt(14.999999999) == "15" and Ch.text_fmt(0.35) == "0.35" and Ch.text_fmt(8.0) == "8", "占位格式：去掉多余小数")
	for cid in Ch.list_ids():
		var d: Dictionary = Ch.load_def(cid)
		var texts: Array = [str(d.get("attack", {}).get("desc", "")), str(d.get("talent", {}).get("desc", "")), str(d.get("gallery", {}).get("desc", ""))]
		for sk in d.get("skills", []):
			texts.append(str(sk.get("desc", "")))
		for nd in d.get("progression", []):
			texts.append(str(nd.get("desc", "")))
			if nd.get("attack", null) is Dictionary:
				texts.append(str(nd.attack.get("desc", "")))
		ok(not texts.any(func(t): return "{$" in t or "{(" in t), "%s 的文字占位全部填好" % cid)


func test_operator_sheet() -> void:
	var Ch = preload("res://scripts/characters/character.gd")
	var IS = preload("res://scripts/screens/initial_stats.gd")
	var Bal = preload("res://scripts/core/balance.gd")
	ok(IS.fmt_armor(2.5) == "2.5" and IS.fmt_armor(0.5) == "0.5" and IS.fmt_armor(3.0) == "3.0" and IS.fmt_armor(4.5) == "4.5", "减伤显示保留一位小数")
	var cnt := 0
	var hpk := 1.0   # 数值表 = 开局实际值：队长生命的 ×0.9 已写进 JSON（10-29）
	var atkk: float = Bal.v("squad/op_atk_base", 1.0)
	for cid in Ch.list_ids():
		var d: Dictionary = Ch.load_def(cid)
		if not d.get("recruitable", true):
			continue
		cnt += 1
		var sh: Dictionary = IS.sheet(cid, d)
		var keys: Array = sh.rows.map(func(r): return r.key)
		ok(keys == IS.REQUIRED, "%s 数值表 9 行齐全且顺序固定：%s" % [cid, str(keys)])
		for r in sh.rows + sh.extra:
			ok(str(r.text) != "" and str(r.label) != "" and str(r.en) != "", "%s 的 %s 行有标签和数值" % [cid, r.key])
			ok(float(r.val) > 0.0 or r.key in ["armor", "arts"], "%s 的 %s 行数值为正（%s）" % [cid, r.key, str(r.val)])
		ok(not sh.tags.is_empty() and sh.note != "", "%s 有定位标签和口径说明" % cid)
		var lead: Dictionary = d.get("leader", {})
		ok(IS.row(sh, "armor").text == "%.1f" % float(lead.get("armor", 0.0)), "%s 减伤按一位小数显示（%s）" % [cid, IS.row(sh, "armor").text])
		ok(IS.row(sh, "hp").text == "%d" % int(round(float(lead.get("max_hp", 0.0)) * hpk)), "%s 生命取 leader.max_hp × 队长生命基础倍率" % cid)
		near(float(IS.row(sh, "regen").val), float(lead.get("regen", 1.0)) * Bal.v("sustain/base_regen_mult", 1.0), "%s 回复取 leader.regen × 基础回复倍率（= 局内开局值）" % cid)
	ok(cnt >= 18, "数值表覆盖全部可招募干员（%d）" % cnt)
	var sk: Dictionary = IS.sheet("skalter", Ch.load_def("skalter"))
	ok(IS.row(sk, "atk").label == "声浪伤害" and "16" in IS.value_text(IS.row(sk, "atk")), "浊心斯卡蒂：声浪伤害 × 最多 16 名")
	ok(IS.row(sk, "reach").label == "歌域半径" and not IS.row(sk, "song").is_empty(), "浊心斯卡蒂：歌域半径 + 歌域增益")
	ok(IS.row(IS.sheet("texas", Ch.load_def("texas")), "reach").label == "冲刺距离", "德克萨斯：范围标为冲刺距离")
	ok("2 段" in IS.row(IS.sheet("irene", Ch.load_def("irene")), "atk").sub, "艾丽妮：每次 2 段")
	ok("2 发" in IS.row(IS.sheet("suzuran", Ch.load_def("suzuran")), "atk").sub, "铃兰：每次 2 发")
	ok("余震" in IS.row(IS.sheet("wisadel", Ch.load_def("wisadel")), "atk").sub, "维什戴尔：附带余震")
	ok("触手" in IS.row(IS.sheet("mizuki", Ch.load_def("mizuki")), "atk").sub, "水月：附带触手")
	ok(IS.row(IS.sheet("kaltsit", Ch.load_def("kaltsit")), "atk").label == "Mon3tr 攻击", "凯尔希：攻击标为 Mon3tr")
	var ex: Dictionary = IS.sheet("exusiai", Ch.load_def("exusiai"))
	ok(IS.row(ex, "cd").text == "0.35 秒" and IS.row(ex, "pierce").is_empty(), "能天使：间隔 0.35 秒，普攻不穿透（10-23 用户定，穿透由贯穿卡 / 穿甲弹给）")
	near(float(IS.row(IS.sheet("irene", Ch.load_def("irene")), "dps").val), 24.0 * 1.03 * atkk * 2.0 / 0.8, "艾丽妮单体每秒伤害 = 攻击 × 攻击基础倍率 × 2 段 ÷ 间隔")
	var syn: Dictionary = IS.sheet("test", {"base": {"atk": 77.0, "cd": 2.5, "reach": 180}, "leader": {"max_hp": 155, "armor": 0.5}})
	ok(IS.row(syn, "hp").text == "%d" % int(round(155.0 * hpk)) and IS.row(syn, "atk").text == IS._num(77.0 * atkk) and IS.row(syn, "cd").text == "2.50 秒" and IS.row(syn, "armor").text == "0.5", "数值表跟随传入的数据")


## 召唤 / 封印 / 护盾 / 治疗光环段（docs/61 §15，op_blocks.gd 末尾）：测试专用干员 sstest 通过校验、改坏一处就不通过；
## 封印的时长规则（普通 / 精英减半 / Boss 缩短封顶 + 免疫 / boss: false）、护盾吸收倍率、召唤物攻击距离。局内行为见 tests/summon_seal_blocks_test
class FakeOp:
	extends RefCounted
	var g
	var id := "fake"
	var sm := {}
	var texts := 0

	func float_text(_p, _t, _c, _s := 14) -> void:
		texts += 1

	func stat(_n) -> float:
		return 1.5


func test_blocks_summon_seal() -> void:
	var Ch = preload("res://scripts/characters/character.gd")
	var OB = preload("res://scripts/characters/op_blocks.gd")
	var d: Dictionary = Ch.load_def("sstest")
	ok(d.has("blocks") and Ch.validate_operator("sstest", d), "测试专用干员 sstest（召唤 / 封印 / 护盾 / 治疗光环）通过校验")
	var bads := {
		"召唤没定义的种类": func(x): x.blocks.skills[0].do[0]["kind"] = "ghost",
		"life = skill 不在技能 do 里": func(x): x.blocks.trait[0].do[0]["life"] = "skill",
		"cap 超过 12": func(x): x.blocks.summons.wolf["cap"] = 13,
		"移动方式写错": func(x): x.blocks.summons.wolf.move["mode"] = "teleport",
		"封印放进常驻列表": func(x): x.blocks.progression["spare"] = {"st": "seal", "dur": 2},
		"Boss 免疫时间太短": func(x): x.blocks.skills[1].do[0].on_hit[0]["boss_immune"] = 1,
		"护盾放进常驻列表": func(x): x.blocks.progression["spare"] = {"verb": "shield", "pct": 0.1},
		"治疗光环比例超范围": func(x): x.blocks.progression.regen["pct"] = 0.5,
		"召唤数超范围": func(x): x.blocks.skills[0].do[0]["n"] = 20,
		"召唤物种类名不是标识符": func(x): x.blocks.summons["狼 首"] = x.blocks.summons.wolf.duplicate(true),
	}
	for why in bads:
		var d2: Dictionary = d.duplicate(true)
		bads[why].call(d2)
		ok(not Ch.validate_operator("sstest", d2), "召唤 / 封印校验应拒绝：" + why)
	ok(not ("summon" in OB.PLANNED.verb) and not ("shield" in OB.PLANNED.verb) and not ("heal" in OB.PLANNED.aura), "verb.summon / verb.shield / aura.heal 不再是「已登记未实现」")
	# 封印时长
	var o := FakeOp.new()
	o.g = {"t": 5.0, "ppos": Vector2.ZERO}
	var ids := [0]
	var mk := func(elite: bool, boss: bool) -> Dictionary:
		ids[0] += 1
		return {"id": ids[0], "dead": false, "chest": false, "elite": elite, "boss": boss, "pos": Vector2.ZERO, "r": 10.0}
	var e: Dictionary = mk.call(false, false)
	OB.apply_status(o, e, {"st": "seal", "dur": 3.0})
	near(float(e.seal_t), 8.0, "封印：普通 3 秒")
	ok(OB.sealed(e, 7.9) and not OB.sealed(e, 8.0), "封印到点解除")
	var el: Dictionary = mk.call(true, false)
	OB.apply_status(o, el, {"st": "seal", "dur": 3.0, "elite_mult": 0.4})
	near(float(el.seal_t), 6.2, "封印：精英 × elite_mult")
	var bo: Dictionary = mk.call(false, true)
	OB.apply_status(o, bo, {"st": "seal", "dur": 3.0})
	near(float(bo.seal_t), 5.9, "封印：Boss × 0.3（缺省）")
	near(float(bo.seal_imm), 5.9 + 10.0, "封印：Boss 结束后免疫 10 秒（缺省）")
	ok(o.texts == 2, "精英 / Boss 吃到封印各飘一次「封印」（普通敌人不飘）")
	o.g.t = 9.0
	OB.apply_status(o, bo, {"st": "seal", "dur": 3.0})
	OB.apply_status(o, bo, {"st": "seal", "dur": 3.0})
	ok(not OB.sealed(bo, 9.0) and o.texts == 3, "免疫期间不吃封印，「封印免疫」1.5 秒内只飘一次（%d）" % o.texts)
	var b2: Dictionary = mk.call(false, true)
	OB.apply_status(o, b2, {"st": "seal", "dur": 9.0, "boss_mult": 1.0, "boss_max": 2.0})
	near(float(b2.seal_t), 11.0, "封印：Boss 封顶 boss_max")
	var b3: Dictionary = mk.call(false, true)
	OB.apply_status(o, b3, {"st": "seal", "dur": 9.0, "boss": false})
	ok(not b3.has("seal_t"), "boss: false：Boss 不受")
	var ch: Dictionary = mk.call(false, false)
	ch.chest = true
	OB.apply_status(o, ch, {"st": "seal", "dur": 2.0})
	ok(not ch.has("seal_t"), "宝箱不吃封印")
	ok(o.sm.seal.size() == 4, "施加者记下被封印的敌人（画标记用）")
	# 护盾吸收倍率：m = 其余减伤；全吸收 0，部分吸收按比例
	o.sm.shield = 6.0
	near(OB.shield_mult(o, 0.5, 10.0), 0.0, "护盾 6 吸收 10 × 0.5 = 5：倍率 0")
	near(float(o.sm.shield), 1.0, "护盾剩 1")
	near(OB.shield_mult(o, 1.0, 10.0), 0.9, "护盾 1 吸收 1：倍率 0.9")
	near(OB.shield_mult(o, 0.7, 10.0), 0.7, "护盾空了：倍率原样")
	# 召唤物攻击距离（× op_range，FakeOp 1.5）
	near(OB.sm_reach(o, {"shape": "circle", "r": 20}), 30.0, "以自身为心的圆：半径 × op_range")
	near(OB.sm_reach(o, {"shape": "circle", "r": 20, "center": "target"}), 60.0, "以目标为心的圆：40 × op_range")
	near(OB.sm_reach(o, {"shape": "line", "len": 50}), 75.0, "直线：长度 × op_range")
	near(OB.sm_reach(o, {"shape": "cone", "r": 40, "range": 10}), 15.0, "写了 range 用 range × op_range")
	near(OB.sm_reach(o, {}), 0.0, "没有攻击 = 0")


## 召唤物扩展段（docs/61 §15.9，10-12：凯尔希 Mon3tr 迁到通用召唤积木）
class FakeMf:
	extends RefCounted
	var g
	var id := "fake"
	var sm := {}
	var mf := {}
	var taken: Array = []
	var elite := 0
	var B := {}
	var s_t: Array = [0.0, 0.0, 0.0]
	func col() -> Color:
		return Color.WHITE
	func stat(_n) -> float:
		return 1.5
	func base(k: String, d: float) -> float:
		return {"m_atk": 20.0}.get(k, d)
	func _dmg_bonus() -> float:
		return 2.0
	func skill_power() -> float:
		return 1.25
	func skill_on(_i: int) -> bool:
		return false


func test_blocks_summon_ext() -> void:
	var Ch = preload("res://scripts/characters/character.gd")
	var OB = preload("res://scripts/characters/op_blocks.gd")
	var d: Dictionary = Ch.load_def("kaltsit")
	ok(d.has("blocks") and not d.has("script") and Ch.validate_operator("kaltsit", d), "凯尔希是数据干员（blocks，无 script）并通过校验")
	var bads := {
		"随行召唤物的帧条不在 sprites 里": func(x): x.blocks.summons.mon3tr.anim["run"] = "m_fly",
		"patch 的伤害来源没登记": func(x): x.blocks.summons.mon3tr.patch[0]["src"] = "Mon3tr · 不存在",
		"patch 缺 cond": func(x): x.blocks.summons.mon3tr.patch[1].erase("cond"),
		"summon_mod 种类没定义": func(x): x.blocks.progression.elite1["kind"] = "wolf",
		"summon_mod 倍率超范围": func(x): x.blocks.progression.elite1["arc"] = 50,
		"summon_mod 放进触发器 do": func(x): x.blocks.trait[0].do.append({"verb": "summon_mod", "kind": "mon3tr", "dmg": 2}),
		"then 缺 delay": func(x): x.blocks.progression.twin_claw.then.erase("delay"),
		"verb.guard 缺 value": func(x): x.blocks.progression.s1_shell.do[0].erase("value"),
		"verb.cleanse 写错": func(x): x.blocks.skills[0].do[1]["what"] = ["poison"],
		"残影写在攻击的 fx 里": func(x): x.blocks.summons.mon3tr.attack.fx.append({"ghost": {"every": 0.1}}),
		"escort 的攻击不是锥形": func(x): x.blocks.summons.mon3tr.attack["shape"] = "circle",
		"rest 只用于 escort": func(x): x.blocks.summons.mon3tr.move["mode"] = "follow",
		"on_skill_end 的 at 种类没定义": func(x): x.blocks.trait[2]["at"] = "summon:wolf",
		"技能 aim 写错": func(x): x.blocks.skills[0]["aim"] = "enemy",
		"shape.support 多字段": func(x): x.blocks.attack["r"] = 40,
		"shape.support 的 when 看不懂": func(x): x.blocks.attack["when"] = "hurt_any &&",
		"条件 node: 后面为空": func(x): x.blocks.trait[2]["cond"] = "!node:",
		"verb.heal 的 scale 写错": func(x): x.blocks.attack.do[0]["scale"] = "atk",
		"程序 fx 条目写两种": func(x): x.blocks.summons.mon3tr.fx[2]["sparks"] = {"n": 3},
		"程序粒子 kind 写错": func(x): x.blocks.summons.mon3tr.fx[2].pfx["kind"] = "smoke",
		"节点积木数组为空": func(x): x.blocks.progression["melt_triple"] = [],
	}
	for why in bads:
		var d2: Dictionary = d.duplicate(true)
		bads[why].call(d2)
		ok(not Ch.validate_operator("kaltsit", d2), "召唤物扩展校验应拒绝：" + why)
	# 条件：node / hurt_any / &&
	var o := FakeMf.new()
	o.g = {"t": 1.0, "hp": 50.0, "max_hp": 100.0, "knight": {"alive": false, "hp": 0.0, "maxhp": 1.0}}
	var c1: Dictionary = OB.parse_cond("node:twin_claw && !hurt_any", {})
	ok(c1.k == "all" and c1.list.size() == 2, "a && b 解析成 all")
	ok(not OB.cond_true(o, c1), "没选节点：不成立")
	o.taken = ["twin_claw"]
	ok(not OB.cond_true(o, c1), "选了节点但主控没满血：!hurt_any 不成立")
	o.g.hp = 100.0
	ok(OB.cond_true(o, c1), "选了节点、主控满血、骑士不在：成立")
	o.g.knight = {"alive": true, "hp": 5.0, "maxhp": 10.0}
	ok(OB.cond_true(o, OB.parse_cond("hurt_any", {})), "hurt_any：骑士同伴没满血也算")
	ok(OB.parse_cond("node:", {}).has("err") or OB.parse_cond("node:", {}).k != "node", "node: 后面为空不算节点条件")
	# 召唤物倍率：依次乘（顺序固定），then / mirror 取第一块
	OB.mf_sustain(o, [{"_tag": "verb.summon_mod", "kind": "m", "reach": 1.2, "dmg": 1.3},
		{"_tag": "verb.summon_mod", "kind": "m", "reach": 1.3, "aspd": 1.4, "then": {"delay": 0.08, "mult": 0.6}},
		{"_tag": "verb.summon_mod", "kind": "m", "then": {"delay": 1.0, "mult": 1.0}}])
	var mods: Dictionary = OB.mf_mods(o, "m")
	near(OB.mf_reach(o, {"r": 100.0}, mods), 100.0 * 1.5 * 1.2 * 1.3, "攻击距离：r × op_range × 各 reach 依次乘")
	near(OB.mf_dmg(o, {"atk_key": "m_atk"}, mods, {}), 20.0 * 2.0 * 1.3, "伤害：base × _dmg_bonus × 各 dmg")
	near(OB.mf_dmg(o, {"atk_key": "m_atk"}, mods, {"mult": 1.6, "power": true}), 20.0 * 2.0 * 1.3 * 1.6 * 1.25, "patch：× mult × 技能强度")
	near(float(mods.then.delay), 0.08, "then 取第一块")
	ok(OB.mf_mods(o, "other").dmg.is_empty(), "别的种类没有倍率")
	# 限时减伤：同名共用计时、按积木顺序相乘
	OB.mf_exec(o, {"_tag": "verb.guard", "_uid": 9, "name": "护壳", "value": 0.35, "dur": 3.0}, Vector2.ZERO)
	OB.mf_exec(o, {"_tag": "verb.guard", "_uid": 2, "name": "庇护", "value": 0.2, "dur": 5.0}, Vector2.ZERO)
	ok(o.mf.guards.keys() == ["庇护", "护壳"], "减伤按积木顺序排（uid）")
	near(OB.mf_guard_mult(o, 1.0), 0.8 * 0.65, "两层减伤相乘")
	OB.mf_tick(o, 3.5, [0.0, 0.0, 0.0])
	near(OB.mf_guard_mult(o, 1.0), 0.8, "到时的那层不再生效")
	OB.mf_exec(o, {"_tag": "verb.guard", "_uid": 7, "name": "庇护", "value": 0.2, "dur": 5.0}, Vector2.ZERO)
	ok(o.mf.guards.size() == 2 and float(o.mf.guards["庇护"].t) == 5.0, "同名重复施加：重新计时，不叠层")


## 精英化第 1 批（docs/91 §19 批 1，op_blocks.gd 末尾「精英化」段）：五名积木干员通过校验、改坏一处就不通过；叠层 / 冷却闸门 / 路径落点 / 往返弹体的数学
func test_blocks_elite1() -> void:
	var Ch = preload("res://scripts/characters/character.gd")
	var OB = preload("res://scripts/characters/op_blocks.gd")
	var defs := {}
	for id in ["texas", "exusiai", "hoshiguma", "angelina", "kaltsit", "ulpianus"]:
		defs[id] = Ch.load_def(id)
		ok(Ch.validate_operator(id, defs[id]), "精英化第 1 批：%s 通过积木校验" % id)
	var bads := [
		# 联动触发器 trig.on_mate_hook（docs/123 §2.7「钩与锚」，乌尔比安 trait 首块）
		["ulpianus", "on_mate_hook 没写 do", func(d): d.blocks.trait[0].erase("do")],
		["ulpianus", "on_mate_hook 的 knob 不是段/键", func(d): d.blocks.trait[0]["knob"] = "hook_anchor"],
		["ulpianus", "on_mate_hook 的 cd 超范围", func(d): d.blocks.trait[0]["cd"] = 99],
		["ulpianus", "on_mate_hook 放进技能 do", func(d): d.blocks.skills[0].do.append({"trig": "on_mate_hook", "do": [{"verb": "sp_team", "pct": 0.1}]})],
		["exusiai", "st.stack 放进技能 do", func(d): d.blocks.skills[1].do.append({"st": "stack", "key": "x", "per": 0.02, "max": 10, "decay": 1.5, "src": ["速射"]})],
		["exusiai", "st.stack 每层超过 100%", func(d): d.blocks.progression.elite1.do[0]["per"] = 2.0],
		["exusiai", "st.stack 来源没登记", func(d): d.blocks.progression.elite1.do[0]["src"] = ["没登记"]],
		["exusiai", "st.stack 分档帧条不是 proj_*", func(d): d.blocks.progression.elite1.do[0]["tex"] = ["fx_exusiai_hit"]],
		["exusiai", "on_mate_attack 没写 fx", func(d): d.blocks.progression.elite2[1].erase("fx")],
		["exusiai", "on_mate_attack 写了 do", func(d): d.blocks.progression.elite2[1]["do"] = [{"verb": "sp_team", "pct": 0.1}]],
		["exusiai", "at = members 挂在非光环上", func(d): d.blocks.progression.elite2[0].do[1]["fx"] = [{"strip": "fx_exusiai_halo", "hold": true, "at": "members", "layer": "over"}]],
		["exusiai", "flash 不是 fire", func(d): d.blocks.progression.elite2[0].do[0].fx[0]["flash"] = "hit"],
		["exusiai", "at = mate 挂在别处", func(d): d.blocks.progression.elite2[0].do[0]["fx"] = [{"strip": "fx_exusiai_blessed_flash", "at": "mate"}]],
		["hoshiguma", "buff_timed 缺 key", func(d): d.blocks.progression.elite1.do[0].erase("key")],
		["hoshiguma", "buff_timed 放进常驻节点", func(d): d.blocks.progression["reach"] = {"verb": "buff_timed", "key": "k", "stat": "dmg", "value": 0.2, "dur": 5}],
		["hoshiguma", "boomerang 缺回程时间", func(d): d.blocks.progression.elite2[0].do[0].erase("t_back")],
		["hoshiguma", "boomerang 来源没登记", func(d): d.blocks.progression.elite2[0].do[0]["src"] = "没登记"],
		["hoshiguma", "every_n 的 anim 不是帧条键", func(d): d.blocks.progression.elite2[0]["anim"] = "throw_x"],
		["hoshiguma", "every_n 的 anim 没配 replace", func(d): d.blocks.progression.elite2[0].erase("replace")],
		["hoshiguma", "延迟起播写在贴身层", func(d): d.blocks.progression.elite1.do[0].fx[0]["delay"] = 0.2],
		["texas", "first_only 不是布尔", func(d): d.blocks.attack.on_hit[1]["first_only"] = "yes"],   # 钉剑 10-24 起挂在拔刀阻挡的 on_hit 第二块上
		["texas", "路径落点缺 step", func(d): d.blocks.progression.elite2.do[0].on_expire[0].erase("step")],
		["texas", "fx_rain along 写错", func(d): d.blocks.progression.elite2.do[0].on_expire[2]["along"] = "line"],
		["texas", "stay 超范围", func(d): d.blocks.attack.on_hit[1].fx[0]["stay"] = 9.0],
		["texas", "on_expire 里放常驻积木", func(d): d.blocks.progression.elite2.do[0].on_expire.append({"verb": "dash_mod", "len_add": 0.1})],
		["angelina", "only 取值写错", func(d): d.blocks.attack.then[1].do[1]["only"] = ["stunned"]],
		["angelina", "失重井 cap 超范围", func(d): d.blocks.attack.then[1]["cap"] = 40],
		["kaltsit", "summon_cmd 动作写错", func(d): d.blocks.progression.elite2[1].do[0]["action"] = "teleport"],
		["kaltsit", "summon_cmd 种类没定义", func(d): d.blocks.progression.elite2[1].do[0]["kind"] = "wolf"],
		["kaltsit", "扑击缺半径", func(d): d.blocks.progression.elite1.lunge.erase("r")],
		["kaltsit", "召唤物帧条键写错", func(d): d.blocks.summons.mon3tr.anim["leap"] = "m_jump"],
	]
	for bd in bads:
		var d2: Dictionary = defs[bd[0]].duplicate(true)
		bd[2].call(d2)
		ok(not Ch.validate_operator(bd[0], d2), "精英化积木校验应拒绝（%s）：%s" % [bd[0], bd[1]])
	# 条件 buff:<key>
	var c: Dictionary = OB.parse_cond("!buff:stance", {})
	ok(str(c.get("k", "")) == "buff" and str(c.get("a", "")) == "stance" and bool(c.get("neg", false)), "条件 buff:<key> 解析（含取反）")
	# 路径落点：长 140、每 40 一柄 → ceil(3.5) = 4 柄，落在四段中点
	var pts: Array = OB.el_path_points(Vector2.ZERO, Vector2(140, 0), 40.0)
	ok(pts.size() == 4 and pts[0].is_equal_approx(Vector2(17.5, 0)) and pts[3].is_equal_approx(Vector2(122.5, 0)), "路径落点：140 / 40 → 4 柄、段中点 %s" % str(pts))
	ok(OB.el_path_points(Vector2.ZERO, Vector2(120, 0), 40.0).size() == 3, "路径落点：正好整除不多落一柄")
	# 状态闸门：first_only 只给第 0 个；cd 期间不再生效
	var fake := {"el": {}, "g": {"t": 10.0, "tex": {}}}
	ok(OB.el_status_gate(fake, {"first_only": true}, 0) and not OB.el_status_gate(fake, {"first_only": true}, 1) and not OB.el_status_gate(fake, {"first_only": true}, -1), "first_only：只给命中列表第 0 个")
	var sc := {"cd": 2.0, "_uid": 7}
	ok(OB.el_status_gate(fake, sc, 0), "cd：第一次生效")
	fake.g.t = 11.0
	ok(not OB.el_status_gate(fake, sc, 0), "cd：2 秒内不再生效")
	fake.g.t = 12.5
	ok(OB.el_status_gate(fake, sc, 0), "cd：过了冷却再生效")
	# 叠层：每层 +2%，10 层封顶；叠满那一下给满层火花；1.5 秒没打中清零
	var sb := {"st": "stack", "key": "p", "per": 0.02, "max": 10, "decay": 1.5, "src": ["速射"], "full_fx": "fx_full"}
	fake.el["stack_on"] = [sb]
	var e := {"id": 3}
	var ms: Array = []
	var full_at := -1
	for i in 12:
		fake.g.t = 20.0 + i * 0.1
		var r: Array = OB.el_stack_hit(fake, e, "速射")
		ms.append(float(r[0]))
		if str(r[1]) != "" and full_at < 0:
			full_at = i
	near(ms[0], 1.0, "叠层：第一发不加")
	near(ms[1], 1.02, "叠层：第二发 +2%")
	near(ms[10], 1.2, "叠层：封顶 +20%")
	near(ms[11], 1.2, "叠层：封顶后不再涨")
	ok(full_at == 9, "叠层：第 10 发叠满给满层火花（实际第 %d 发）" % (full_at + 1))
	ok(float(OB.el_stack_hit(fake, e, "冲锋模式")[0]) == 1.0, "叠层：不是 src 列表里的来源不加也不叠")
	fake.g.t = 25.0
	near(float(OB.el_stack_hit(fake, e, "速射")[0]), 1.0, "叠层：1.5 秒没打中清零")
	# 往返弹体：去程先快后慢到头、停 hold、回程收回到 0
	var bm := {"t": 0.3, "to": 0.3, "hold": 0.1, "tb": 0.3, "L": 220.0}
	near(float(OB._el_boom_d(bm)[0]), 220.0, "往返：去程到头")
	bm.t = 0.35
	ok(float(OB._el_boom_d(bm)[0]) == 220.0 and int(OB._el_boom_d(bm)[1]) == 0, "往返：到头停 hold（仍算去程）")
	bm.t = 0.7
	ok(absf(float(OB._el_boom_d(bm)[0])) < 0.001 and int(OB._el_boom_d(bm)[1]) == 1, "往返：回程收回到手里")
	near(OB.el_boom_total(bm), 0.7, "往返：总时长 = 去 + 停 + 回")
	# 限时增益：生效 / 过期
	fake.el["timed"] = {"stance": {"until": 30.0, "b": {}}}
	fake.g.t = 29.0
	ok(OB.el_buff_on(fake, "stance") and not OB.el_buff_on(fake, "other"), "buff:<key> 生效中")
	fake.g.t = 30.5
	ok(not OB.el_buff_on(fake, "stance"), "buff:<key> 过期")



## 手写迁移段（docs/61 §17，10-14）：逻各斯 / 艾雅法拉 / 斯卡蒂 / 乌尔比安迁积木的新积木 / 参数——校验、反例、几个纯函数
func test_blocks_handwritten() -> void:
	var Ch = preload("res://scripts/characters/character.gd")
	var OB = preload("res://scripts/characters/op_blocks.gd")
	var defs := {}
	for id in ["logos", "eyjafjalla", "skadi", "ulpianus"]:
		defs[id] = Ch.load_def(id)
		ok(Ch.validate_operator(id, defs[id]), "手写迁移：%s 通过积木校验" % id)
		ok(str(defs[id].get("script", "")) == "res://scripts/characters/data_operator.gd", "手写迁移：%s 用数据干员脚本" % id)
	var bads := [
		["skadi", "basis 写错", func(d): d.blocks.talent[0].do[0]["basis"] = "swing"],
		["skadi", "basis 又写 power", func(d): d.blocks.talent[0].do[0]["power"] = true],
		["skadi", "face 条件写错", func(d): d.blocks.attack["face"] = "lamp ~ 3"],
		["skadi", "dir 写错", func(d): d.blocks.talent[0].do[0]["dir"] = "left"],
		["skadi", "aim_mult 没配 aim_r", func(d): d.blocks.attack["aim_mult"] = 1.4],
		["skadi", "连斩一段多了字段", func(d): d.blocks.attack.combo[0]["mult"] = 2],
		["skadi", "连斩缺 delay", func(d): d.blocks.attack.combo[0].erase("delay")],
		["skadi", "on_combo_end 放进技能 do", func(d): d.blocks.skills[0].do.append({"trig": "on_combo_end", "do": []})],
		["skadi", "浪墙缺速度", func(d): d.blocks.skills[1].do[2].erase("speed")],
		["skadi", "follow 缺 gap", func(d): d.blocks.follow.erase("gap")],
		["skadi", "countdown 不是布尔", func(d): d.blocks.progression.surge["countdown"] = 1],
		["eyjafjalla", "法术弹缺 aoe", func(d): d.blocks.attack.erase("aoe")],
		["eyjafjalla", "抛射 pick 写错", func(d): d.blocks.attack.on_explode[0]["pick"] = "far"],
		["eyjafjalla", "点燃放进技能 do", func(d): d.blocks.skills[1].do.append({"st": "burn", "dur": 3, "mult": 0.1, "src": "点燃"})],
		["eyjafjalla", "易伤 kind 写错", func(d): d.blocks.skills[1].do[0].on_explode[1].on_hit[2]["kind"] = "fire"],
		["eyjafjalla", "cast 写错", func(d): d.blocks.skills[0]["cast"] = "now"],
		["eyjafjalla", "pulse 没配 dur.pulses", func(d): d.blocks.skills[1]["pulse"] = {"r": 100, "do": []}],
		["eyjafjalla", "attack_patch 字段写错", func(d): d.blocks.skills[0].attack_patch["burn_x"] = true],
		["eyjafjalla", "地面池 look 写错", func(d): d.blocks.skills[2].pulse.do.filter(func(b): return b.get("shape", "") == "pool")[0]["look"] = "fire"],
		["logos", "咒文弹没写 then", func(d): d.blocks.attack.erase("then")],
		["logos", "锁定放进触发 do", func(d): d.blocks.talent[0].do.append({"verb": "lock", "dur": 5, "tick": 0.25, "mult": 0.5, "src": "提喻"})],
		["logos", "处决缺 thr", func(d): d.blocks.attack.then[0].erase("thr")],
		["logos", "咒域缺 deg", func(d): d.blocks.skills[2].do[0].erase("deg")],
		["logos", "安魂放进技能 do", func(d): d.blocks.skills[0].do.append({"st": "requiem", "dur": 5})],
		["ulpianus", "掷锚 mode 写错", func(d): d.blocks.skills[0].do[0]["mode"] = "pull"],
		["ulpianus", "叠层缺 key", func(d): d.blocks.talent[0].do[0].erase("key")],
		["ulpianus", "计时缺 dur", func(d): d.blocks.skills[2].do[0].then[0].erase("dur")],
		["ulpianus", "光环 per 写错", func(d): d.blocks.talent[1].do[0]["per"] = "kills"],
		["ulpianus", "掷锚放进触发 do", func(d): d.blocks.talent[0].do.append(d.blocks.skills[0].do[0].duplicate(true))],
		["ulpianus", "center 写错", func(d): d.blocks.attack["center"] = "ahead"],
		# 精英化第 2 批段（docs/61 §18）
		["logos", "叠层安魂缺 per", func(d): d.blocks.progression.elite1.do[0].erase("per")],
		["logos", "叠层安魂 look 不是帧条", func(d): d.blocks.progression.elite1.do[0]["look"] = ["rune"]],
		["logos", "咒文链缺 share", func(d): d.blocks.attack.then[2].erase("share")],
		["logos", "咒文链放进常驻", func(d): d.blocks.progression.elite1.do.append(d.blocks.attack.then[2].duplicate(true))],
		["eyjafjalla", "低抛缺 flight", func(d): d.blocks.attack.lob.erase("flight")],
		["eyjafjalla", "低抛 mults 不是数组", func(d): d.blocks.attack.lob["mults"] = 1.4],
		["eyjafjalla", "低抛弹体不是 proj_", func(d): d.blocks.attack.lob["tex"] = "fx_eyja_lava_pool"],
		["eyjafjalla", "熔池缺 every", func(d): d.blocks.attack.lob.pool[0].erase("every")],
		["skadi", "潮刃 fan 不是数组", func(d): d.blocks.progression.elite2[0].do[0]["fan"] = 25],
		["skadi", "潮刃 from 写错", func(d): d.blocks.progression.elite2[0].do[0]["from"] = "target"],
		["skadi", "潮刃弹体不是 proj_", func(d): d.blocks.progression.elite2[0].do[0]["proj"] = "fx_skadi_surge_hit"],
		["ulpianus", "掷锚缺 range", func(d): d.blocks.progression.elite2.do[0].erase("range")],
		["ulpianus", "掷锚 back_src 没登记", func(d): d.blocks.progression.elite2.do[0]["back_src"] = "回收"],
		["ulpianus", "掷锚 basis 写错", func(d): d.blocks.progression.elite2.do[0]["basis"] = "anchor"],
		["ulpianus", "掷锚放进常驻", func(d): d.blocks.progression.elite1 = {"trig": "passive", "do": [d.blocks.progression.elite2.do[0].duplicate(true)]}],
	]
	for bd in bads:
		var d2: Dictionary = defs[bd[0]].duplicate(true)
		bd[2].call(d2)
		ok(not Ch.validate_operator(bd[0], d2), "手写迁移积木校验应拒绝（%s）：%s" % [bd[0], bd[1]])
	# mult 数组 = 依次乘；条件 timer: / armed:
	near(OB.hw_mul(2.0, [3.0, 0.5]), 3.0, "mult 数组依次乘")
	near(OB.hw_mul(2.0, 1.5), 3.0, "mult 数字")
	var c: Dictionary = OB.parse_cond("!timer:haste", {})
	ok(str(c.get("k", "")) == "timer" and str(c.get("a", "")) == "haste" and bool(c.get("neg", false)), "条件 timer:<key> 解析（含取反）")
	c = OB.parse_cond("elite >= 2 && armed:blood", {"x": 1})
	ok(str(c.get("k", "")) == "all" and c.list.size() == 2 and str(c.list[1].k) == "armed", "条件 armed:<key> 可与 && 连用")
	# 数组里的 $ 表达式在编译时求值（mult 数组）
	var comp: Dictionary = OB.compile({"base": {"a": 2.0, "b": 0.5}, "blocks": {"talent": [{"trig": "every_n", "n": 1, "do": [{"shape": "bolt", "mult": ["$a", "$b"]}]}]}})
	var mv = comp.talent[0].do[0].mult
	ok(mv is Array and float(mv[0]) == 2.0 and float(mv[1]) == 0.5, "数组里的 $ 表达式编译成数字")
	# 法术弹后续弹 / 地面池的同组上限：只用纯数据检查（运行时行为由 blocks_eq 同 seed 对照覆盖）
	ok(OB.HW2_TAGS.has("shape.pool") and OB.HW3_TAGS.has("verb.lock") and OB.HW4_TAGS.has("verb.tether") and OB.HW_TAGS.has("trig.on_combo_end"), "手写迁移段的积木都登记了")
	ok(OB.HW5_TAGS.has("verb.requiem_stack") and OB.HW5_TAGS.has("verb.link") and OB.HW5_TAGS.has("shape.hookshot"), "精英化第 2 批段的积木都登记了")
	# 精一 / 精二形态挂在 elite1 / elite2 上：精零不生效（_trigs 只在 elite 达到时收进来）
	for id in ["skadi", "ulpianus"]:
		var pg: Dictionary = defs[id].blocks.progression
		ok(pg.has("elite1") and pg.has("elite2"), "精英化第 2 批：%s 有精一 / 精二积木" % id)
	ok(defs["logos"].blocks.progression.has("elite1") and defs["logos"].blocks.attack.then.any(func(x): return str(x.get("verb", "")) == "link" and str(x.get("cond", "")) == "elite >= 2"),
		"逻各斯精一叠层安魂、精二连缀（命中 then 里 elite >= 2）")
	ok(defs["eyjafjalla"].blocks.attack.has("lob") and str(defs["eyjafjalla"].blocks.attack.lob.get("cond", "")) == "elite >= 2", "艾雅法拉精二低抛只在精二生效")
	for id in ["logos", "eyjafjalla", "skadi", "ulpianus"]:
		for n in defs[id].progression:
			if n.get("type", "") == "elite":
				ok(n.has("attack") and str(n.attack.get("name", "")) != "" and str(n.attack.get("desc", "")) != "", "精英化第 2 批：%s 精%d 节点有普攻卡" % [id, int(n.level)])


## 手写迁移段第 3 批（docs/61 §19）：归溟幽灵鲨 / 水月 / 艾丽妮 / 流明 通过校验、用数据干员脚本；常见写错的被拒绝
func test_blocks_hw3() -> void:
	var Ch = preload("res://scripts/characters/character.gd")
	var OB = preload("res://scripts/characters/op_blocks.gd")
	var defs := {}
	for id in ["specter_unchained", "mizuki", "irene", "lumen"]:
		defs[id] = Ch.load_def(id)
		ok(Ch.validate_operator(id, defs[id]), "手写迁移第 3 批：%s 通过积木校验" % id)
		ok(str(defs[id].get("script", "")) == "res://scripts/characters/data_operator.gd", "手写迁移第 3 批：%s 用数据干员脚本" % id)
	var bads := [
		["irene", "刺击缺 len", func(d): d.blocks.attack.erase("len")],
		["irene", "刺击段多了字段", func(d): d.blocks.attack.stages[1]["delay"] = 0.2],
		["irene", "刺击段条件写错", func(d): d.blocks.attack.stages[1]["cond"] = "node~x"],
		["irene", "追诉缺 cd", func(d): d.blocks.attack.pursue.erase("cd")],
		["irene", "浮空放进技能 do", func(d): d.blocks.skills[1].do.append({"st": "launch", "dur": 1.0})],
		["irene", "斩击 aim 写错", func(d): d.blocks.skills[1].do[0]["aim"] = "far"],
		["irene", "连射缺 cannon", func(d): d.blocks.skills[2].do[1].erase("cannon")],
		["irene", "后续斩缺 delay", func(d): d.blocks.skills[1].do[1].erase("delay")],
		["irene", "补丁字段写错", func(d): d.blocks.skills[0].attack_patch["lift"] = 1.0],
		["specter_unchained", "环斩缺 r", func(d): d.blocks.attack.erase("r")],
		["specter_unchained", "替身帧条不在 sprites", func(d): d.blocks.skills[1].do[1]["anim"] = "falling"],
		["specter_unchained", "不倒放进常驻", func(d): d.blocks.talent[0].do.append({"verb": "undying"})],
		["specter_unchained", "血痕缺 src", func(d): d.blocks.attack.trail.erase("src")],
		["lumen", "荧光缺 heal", func(d): d.blocks.attack.erase("heal")],
		["lumen", "光束放进技能 do", func(d): d.blocks.skills[0].do.append({"verb": "beam", "len": 200, "tick": 0.2, "src": "灯塔光束"})],
		["lumen", "灯塔放进触发 do", func(d): d.blocks.progression.watch = {"trig": "every_n", "n": 1, "do": [{"verb": "tower", "r": 200}]}],
		["lumen", "verb.lamp 一个参数都没写", func(d): d.blocks.skills[1].do[0] = {"verb": "lamp"}],
		["mizuki", "伞击缺 tentacle", func(d): d.blocks.attack.erase("tentacle")],
		["mizuki", "专属属性 op 写错", func(d): d.blocks.progression.tentacle_a = {"verb": "buff_self", "stat": "mizuki_tentacle_targets", "op": "set", "value": 1}],
		["mizuki", "buff_self 写了没定义的属性", func(d): d.blocks.progression.tentacle_a = {"verb": "buff_self", "stat": "mizuki_nope", "op": "flat", "value": 1}],
		["mizuki", "回复放进技能 do", func(d): d.blocks.skills[1].do.append({"verb": "kill_heal", "pct": 0.01})],
		# 精英化第 3 批（docs/61 §20）
		["specter_unchained", "起手触发放进技能 do", func(d): d.blocks.skills[0]["do"] = [{"trig": "on_windup", "do": []}]],
		["specter_unchained", "替身闪现缺 r", func(d): d.blocks.progression.elite2.do[0].erase("r")],
		["specter_unchained", "替身闪现帧条不在 sprites", func(d): d.blocks.progression.elite2.do[0]["anim"] = "spin"],
		["irene", "收尾帧条不在 sprites", func(d): d.blocks.attack.finisher["anim"] = "slash2"],
		["irene", "收尾缺 every", func(d): d.blocks.attack.finisher.erase("every")],
		["irene", "挑刺不是命中状态", func(d): d.blocks.attack.stages[0]["on_first"] = [{"verb": "lamp", "add": 1}]],
		["lumen", "光柱缺 len", func(d): d.blocks.attack.beam.erase("len")],
		["lumen", "折光缺 src", func(d): d.blocks.attack.bolt.refract.erase("src")],
		["mizuki", "水母缺 src", func(d): d.blocks.attack.jelly.erase("src")],
	]
	for bd in bads:
		var d2: Dictionary = defs[bd[0]].duplicate(true)
		bd[2].call(d2)
		ok(not Ch.validate_operator(bd[0], d2), "手写迁移第 3 批积木校验应拒绝（%s）：%s" % [bd[0], bd[1]])
	for t in ["shape.thrust", "shape.cleave", "shape.saw", "shape.lantern", "shape.umbrella", "st.launch", "verb.substitute", "verb.tower"]:
		ok(OB.H3_TAGS.has(t), "第 3 批积木已登记：%s" % t)
	ok(OB.ATTACK_SHAPES.has("thrust") and OB.ATTACK_SHAPES.has("umbrella"), "第 3 批普攻形状已登记")
	ok(not defs["mizuki"].blocks.attack.has("flow"), "水月：公共起手和命中时钟")
	ok(OB.E3_TAGS.has("trig.on_windup") and OB.E3_TAGS.has("verb.doll_flash"), "精英化第 3 批积木已登记")
	for id in ["specter_unchained", "mizuki", "irene", "lumen"]:
		var pg: Dictionary = defs[id].blocks.progression
		ok(pg.has("elite1") and pg.has("elite2"), "精英化第 3 批：%s 有精一 / 精二积木" % id)
		for nd in defs[id].progression:
			if nd.get("type", "") == "elite":
				ok(nd.has("attack") and str(nd.attack.get("name", "")) != "" and str(nd.attack.get("desc", "")) != "" and not "主控" in str(nd.attack.desc) and not "主控" in str(nd.desc),
					"精英化第 3 批：%s 精%d 节点有普攻卡（不写「主控」）" % [id, int(nd.level)])
	ok(not defs["specter_unchained"].blocks.attack.has("whirl") and not defs["mizuki"].blocks.attack.tentacle.has("stake") and not defs["lumen"].blocks.attack.units.has("charge"),
		"精英化第 3 批：精二旧形态（无尽回旋 / 固着 / 强化光弹）已被取代")


## 手写迁移第 4 批（docs/61 §21）：推进之王 / 铃兰 / 维什戴尔 / 塞雷娅迁积木，校验通过 + 反例
func test_blocks_hw4() -> void:
	var Ch = preload("res://scripts/characters/character.gd")
	var OB = preload("res://scripts/characters/op_blocks.gd")
	var defs := {}
	for id in ["siege", "suzuran", "wisadel", "saria"]:
		defs[id] = Ch.load_def(id)
		ok(Ch.validate_operator(id, defs[id]), "手写迁移第 4 批：%s 通过积木校验" % id)
		ok(str(defs[id].get("script", "")) == "res://scripts/characters/data_operator.gd", "手写迁移第 4 批：%s 用数据干员脚本" % id)
	var bads := [
		["siege", "锤击缺 r", func(d): d.blocks.attack.erase("r")],
		["siege", "锤击缺 src", func(d): d.blocks.attack.erase("src")],
		["siege", "地裂来源没登记", func(d): d.blocks.attack.breach["src"] = "裂地"],
		["siege", "碎颅击帧条不在 sprites", func(d): d.blocks.attack.heavy["anim"] = "smash"],
		["siege", "跃空锤放进常驻", func(d): d.blocks.talent[0].do.append({"verb": "leap_slam", "r": 110, "mult": 2.2, "t": 0.42, "dist": 90, "src": "震地"})],
		["siege", "号令波缺 dur", func(d): d.blocks.skills[0].do[1].erase("dur")],
		["suzuran", "狐火缺 speed", func(d): d.blocks.attack.erase("speed")],
		["suzuran", "光域放进技能 do", func(d): d.blocks.skills[1].do.append({"verb": "foxlight", "r": 85})],
		["suzuran", "围炉来源没登记", func(d): d.blocks.trait[0].do[0].hearth["src"] = "炉火"],
		["suzuran", "儿时的舞乐缺 buff", func(d): d.blocks.skills[1].do[0].erase("buff")],
		["suzuran", "补丁字段写错", func(d): d.blocks.skills[0].attack_patch["volley"] = 5],
		["wisadel", "炮击缺 aoe", func(d): d.blocks.attack.erase("aoe")],
		["wisadel", "余震来源没登记", func(d): d.blocks.attack["quake_src"] = "余波"],
		["wisadel", "起手朝向写错", func(d): d.blocks.skills[1]["aim"] = "boss"],
		["wisadel", "魂灵之影缺 n", func(d): d.blocks.progression.elite2.do[0].erase("n")],
		["wisadel", "魂灵之影不跟随又缺 cd", func(d): d.blocks.progression.elite2.do[0].erase("follow")],
		["wisadel", "装填放进常驻", func(d): d.blocks.progression.elite2.do.append({"verb": "cannon_load", "n": 8})],
		["saria", "拳击缺 r", func(d): d.blocks.attack.erase("r")],
		["saria", "阻挡圈放进触发 do", func(d): d.blocks.progression.calc_orb = {"trig": "every_n", "n": 1, "do": [{"verb": "guard_ring", "r": 62, "every": 0.25}]}],
		["saria", "钙晶 n_by 不是数组", func(d): d.blocks.trait[0].do[1]["n_by"] = 3],
		["saria", "护服缺 seg_t", func(d): d.blocks.progression.elite2.do[0].erase("seg_t")],
		["saria", "站位 side 不是 [x, y]", func(d): d.blocks.follow["side"] = 40],
		# 精英化第 4 批（docs/61 §22）
		["siege", "粉碎缺 src", func(d): d.blocks.attack.crush.erase("src")],
		["siege", "粉碎没写 cond", func(d): d.blocks.attack.crush.erase("cond")],
		["siege", "岩刺缺 step", func(d): d.blocks.attack.breach.spikes.erase("step")],
		["suzuran", "灼印缺 value", func(d): d.blocks.attack.brand.erase("value")],
		["suzuran", "狐火拖尾来源没登记", func(d): d.blocks.attack.merge.trail["src"] = "拖尾"],
		["wisadel", "好礼缺 mult", func(d): d.blocks.attack.gift.erase("mult")],
		["wisadel", "魂炮缺 src", func(d): d.blocks.progression.elite2.do[0].fire.erase("src")],
		["saria", "钙化拳缺 pct", func(d): d.blocks.attack.calcify.erase("pct")],
		["saria", "晶柱缺 n", func(d): d.blocks.progression.elite2.do[0].pillars.erase("n")],
		["saria", "晶柱超过 16 根", func(d): d.blocks.progression.elite2.do[0].pillars["n"] = 20],
	]
	for bd in bads:
		var d2: Dictionary = defs[bd[0]].duplicate(true)
		bd[2].call(d2)
		ok(not Ch.validate_operator(bd[0], d2), "手写迁移第 4 批积木校验应拒绝（%s）：%s" % [bd[0], bd[1]])
	for t in ["shape.hammer", "verb.leap_slam", "shape.foxfire", "verb.foxlight", "shape.cannon", "verb.souls", "shape.bash", "verb.suit"]:
		ok(OB.H4_TAGS.has(t), "第 4 批积木已登记：%s" % t)
	for sh in ["hammer", "foxfire", "cannon", "bash"]:
		ok(OB.ATTACK_SHAPES.has(sh) and OB.H4_ATTACKS.has(sh), "第 4 批普攻形状已登记：%s" % sh)
	for id in ["siege", "suzuran", "wisadel", "saria"]:
		var pg: Dictionary = defs[id].blocks.progression
		ok(pg.has("elite1") and pg.has("elite2"), "精英化第 4 批：%s 有精一 / 精二积木" % id)
		for nd in defs[id].progression:
			if nd.get("type", "") == "elite":
				ok(nd.has("attack") and str(nd.attack.get("name", "")) != "" and str(nd.attack.get("desc", "")) != "" and not "主控" in str(nd.attack.desc) and not "主控" in str(nd.desc),
					"精英化第 4 批：%s 精%d 节点有普攻卡（不写「主控」）" % [id, int(nd.level)])
	ok(str(defs["siege"].progression.filter(func(n): return n.get("type", "") == "elite" and int(n.level) == 2)[0].attack.name) == "破阵"
		and str(defs["suzuran"].progression.filter(func(n): return n.get("type", "") == "elite" and int(n.level) == 2)[0].attack.name) == "九尾祈愿"
		and str(defs["wisadel"].progression.filter(func(n): return n.get("type", "") == "elite" and int(n.level) == 2)[0].attack.name) == "死魂灵的余息"
		and str(defs["saria"].progression.filter(func(n): return n.get("type", "") == "elite" and int(n.level) == 2)[0].attack.name) == "莱茵充能护服",
		"精英化第 4 批：精二原有形态（破阵 / 九尾祈愿 / 死魂灵的余息 / 莱茵充能护服）保留")


## 精英化第 5 批（docs/61 §23、docs/91 §27：浊心斯卡蒂「余音」/「远古血亲」）：校验正反例、召唤物区域半径与并集、band / among 筛选
class FakeE5:
	extends RefCounted
	var g
	var loc := {"zone": 1.0}
	var zmode := 1.0
	var sm := {}
	var e5 := {}
	var dealt: Array = []
	var pool: Array = []
	func stat(_n) -> float:
		return 1.0
	func arc_targets(c: Vector2, _a: float, _h: float, r: float) -> Array:
		return pool.filter(func(e): return e.pos.distance_to(c) <= r + float(e.r))
	func cap_targets(hits: Array, c: Vector2, k: int) -> Array:
		return preload("res://scripts/characters/character.gd").cap_targets(hits, c, k)
	func vs_elite() -> float:
		return 2.0
	func log_hit(_s, _t := []) -> void:
		pass
	func deal_damage(e: Dictionary, d: float) -> void:
		dealt.append([int(e.id), d])
	func _hit_fx(_e, _c) -> void:
		pass


func test_blocks_e5() -> void:
	var Ch = preload("res://scripts/characters/character.gd")
	var OB = preload("res://scripts/characters/op_blocks.gd")
	var sk: Dictionary = Ch.load_def("skalter")
	ok(Ch.validate_operator("skalter", sk), "精英化第 5 批：浊心斯卡蒂通过积木校验")
	var pg: Dictionary = sk.blocks.progression
	ok(pg.has("elite1") and pg.elite2 is Array, "精英化第 5 批：浊心斯卡蒂有精一 / 精二积木")
	ok(not JSON.stringify(pg.elite2).contains("\"orbit\""), "精二「溟海之声」（shape.orbit 音符）已被「远古血亲」取代")
	ok(sk.blocks.summons.ishar.has("zone") and str(sk.blocks.summons.ishar.move.mode) == "chase", "海嗣：自带区域、跟着敌群走")
	for k in ["ishar_idle", "ishar_move", "ishar_attack", "ishar_summon"]:
		ok(sk.sprites.has(k) and k in sk.get("extra_sprites", []), "海嗣帧条登记并列进 extra_sprites：" + k)
	for nd in sk.progression:
		if nd.get("type", "") == "elite":
			ok(nd.has("attack") and str(nd.attack.get("name", "")) != "" and not "主控" in str(nd.attack.desc) and not "主控" in str(nd.desc),
				"精英化第 5 批：精%d 节点有普攻卡（不写「主控」）" % int(nd.level))
	var names: Array = sk.progression.filter(func(n): return n.get("type", "") == "elite").map(func(n): return str(n.attack.name))
	ok(names == ["余音", "远古血亲"], "普攻卡：余音 / 远古血亲（%s）" % str(names))
	var bads := [
		["band 内大于外", func(d): d.blocks.progression.elite1.do[0]["band"] = [0.9, 0.5]],
		["band 不是两个数", func(d): d.blocks.progression.elite1.do[0]["band"] = 0.8],
		["among 写错", func(d): d.blocks.progression.elite1.do[0]["among"] = "all"],
		["band 和 only 同用", func(d): d.blocks.progression.elite1.do[0]["only"] = ["airborne"]],
		["召唤物区域缺 r", func(d): d.blocks.summons.ishar.zone.erase("r")],
		["召唤物区域字段写错", func(d): d.blocks.summons.ishar.zone["radius"] = 120],
		["区域帧条不是 fx_*", func(d): d.blocks.summons.ishar.zone.look["strip"] = "op_skalter_idle"],
		["区域 mode 不是布尔", func(d): d.blocks.summons.ishar.zone["mode"] = 0],
		["repick 用在非 chase", func(d): d.blocks.summons.ishar.move["mode"] = "follow"],
		["非随行召唤物的帧条键写错", func(d): d.blocks.summons.ishar.anim["walk"] = "ishar_move"],
		["帧条不在 sprites", func(d): d.blocks.summons.ishar.anim["spawn"] = "ishar_rise"],
		["写了 anim 又写 attack", func(d): d.blocks.summons.ishar["attack"] = {"shape": "circle", "center": "self", "r": 40, "every": 1.0, "src": "海嗣"}],
		["summon_cmd 动作写错", func(d): d.blocks.progression.elite2[1].do[0]["action"] = "dance"],
		["召唤物没有区域却 r: zone", func(d): d.blocks.summons.ishar.erase("zone")],
		["grow_to 指向不存在的召唤物", func(d): d.blocks.progression.elite2[1].do[0].then[0].fx[0]["grow_to"] = "summon:nope"],
		["play 写错", func(d): d.blocks.progression.elite1.do[0].fx[0]["play"] = "time"],
		["play 没配 ease", func(d): d.blocks.skills[0].fx[0]["play"] = "fps"],
	]
	for bd in bads:
		var d2: Dictionary = sk.duplicate(true)
		bd[1].call(d2)
		ok(not Ch.validate_operator("skalter", d2), "精英化第 5 批积木校验应拒绝：" + bd[0])
	var B: Dictionary = OB.compile(sk)
	ok(OB.e5_scan(B) and not OB.e5_scan(OB.compile(Ch.load_def("texas"))), "among 扫描：浊心斯卡蒂有，德克萨斯没有")
	# 召唤物区域半径：r × op_range × (1 + (区域倍率 − 1) × share)，mode: false 先除掉 verb.mode 的放大
	var o := FakeE5.new()
	var kd := {"zone": {"r": 120.0, "share": 0.5, "mode": false}}
	o.loc.zone = 1.5
	near(OB.e5_zone_r(o, kd), 150.0, "小歌域吃一半歌域扩张（×1.5 → ×1.25）")
	o.loc.zone = 3.0
	o.zmode = 2.0
	near(OB.e5_zone_r(o, kd), 150.0, "S3 的 ×2 不传给小歌域")
	kd.zone["mode"] = true
	near(OB.e5_zone_r(o, kd), 240.0, "mode: true 时技能模式的放大也算（一半）")
	near(OB.e5_zone_r(o, {}), 0.0, "没写 zone 半径为 0")
	# 并集：召唤物区域里的点算在区域内；离开就不算
	o.sm = {"list": [{"pos": Vector2(100, 0), "zr": 50.0, "gone": false}]}
	ok(OB.e5_in_zone(o, Vector2(130, 0)) and not OB.e5_in_zone(o, Vector2(200, 0)), "召唤物区域：半径内算、半径外不算")
	o.sm.list[0].gone = true
	ok(not OB.e5_in_zone(o, Vector2(130, 0)), "召唤物消失后它的区域不算")
	# band / among：只打上一次普攻命中的、外圈（80%–100%）的敌人
	o.pool = [
		{"id": 1, "pos": Vector2(50, 0), "r": 6.0, "dead": false, "elite": false, "boss": false},
		{"id": 2, "pos": Vector2(160, 0), "r": 6.0, "dead": false, "elite": false, "boss": false},
		{"id": 3, "pos": Vector2(0, 175), "r": 6.0, "dead": false, "elite": false, "boss": false},
		{"id": 4, "pos": Vector2(-185, 0), "r": 6.0, "dead": false, "elite": true, "boss": false},
		{"id": 5, "pos": Vector2(0, -150), "r": 6.0, "dead": false, "elite": false, "boss": false},
	]
	o.e5 = {"ah": {1: true, 2: true, 4: true, 5: true}}
	var hits: Array = OB.e5_area(o, {"band": [0.8, 1.0], "among": "attack"}, Vector2.ZERO, 190.0, 10.0)
	var ids: Array = hits.map(func(e): return int(e.id))
	ids.sort()
	ok(ids == [2, 4, 5], "余音：外圈（按敌人边缘 ≥ 152）且被这圈声浪打中的（%s）" % str(ids))
	ok(o.dealt.any(func(x): return x[0] == 4 and absf(x[1] - 20.0) < 0.001), "余音对精英 × vs_elite")
	o.e5 = {}
	ok(OB.e5_area(o, {"band": [0.8, 1.0], "among": "attack"}, Vector2.ZERO, 190.0, 10.0).is_empty(), "没有普攻命中表时余音不打")
	ok(OB.e5_area(o, {"band": [0.8, 1.0]}, Vector2.ZERO, 190.0, 10.0).size() == 4, "只写 band：外圈全部")
	ok(OB.e5_area(o, {"band": [0.8, 1.0], "max_n": 2}, Vector2.ZERO, 190.0, 10.0).size() == 2, "band 也认 max_n")
