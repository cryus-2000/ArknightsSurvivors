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
	test_hoshiguma_blocks()
	test_voice()
	test_blocks_angelina()
	test_blocks_texas()
	test_fx_hold()
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
	ok(c.db.implemented().size() == 262, "已实装藏品 262 件（docs/57：全部实装，%d）" % c.db.implemented().size())
	# docs/35 藏品契约：说明非空、不再出现「援护干员」、职业门槛合法、流派只用 A–H
	var classes := ["先锋", "近卫", "重装", "狙击", "术师", "医疗", "辅助", "特种"]
	for r in c.db.implemented():
		ok(str(r.desc).strip_edges() != "", "藏品 %s 说明非空" % r.id)
		ok(not str(r.desc).contains("援护干员"), "藏品 %s 说明不含「援护干员」" % r.id)
		for cl in r.get("requires_class", []):
			ok(cl in classes, "藏品 %s 职业门槛合法（%s）" % [r.id, cl])
		for ln in r.lanes:
			ok(ln in ["A", "B", "C", "D", "E", "F", "G", "H"], "藏品 %s 流派代号合法（%s）" % [r.id, ln])
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
	# Build Profile：拿近战藏品后，A 流派领先
	for id in ["54", "56", "120", "121"]:
		c.gain_relic(id)
	ok(c.profile.lane_scores().A > c.profile.lane_scores().B, "近战藏品提高 A 流派")
	ok(c.profile.affinity(["melee"]) > c.profile.affinity(["squad"]), "相关度")
	c.gain_relic("79")
	near(c.stats.value(&"dmg"), 1.2, "藏品效果生效（79：全伤害 +20%）")
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
func test_voice() -> void:
	var man = JSON.parse_string(FileAccess.get_file_as_string("res://audio/voice/voice_manifest.json"))
	ok(man is Dictionary and man.get("clips", []).size() >= 66, "语音清单可读，至少 66 条")
	if not man is Dictionary:
		return
	for c in man.clips:
		var f: String = c.file
		ok(f == "%s_%s.ogg" % [c.operator, c.event], "语音文件名 = 干员_事件.ogg：" + f)
		var path := "res://audio/voice/" + f
		var st = load(path) if ResourceLoader.exists(path) else null
		ok(st is AudioStreamOggVorbis, "语音能加载为 OGG：" + f)
		if st is AudioStreamOggVorbis:
			ok(not st.loop, "语音不循环：" + f)
			ok(absf(st.get_length() - float(c.duration_seconds)) < 0.01, "语音时长与母带一致：%s（%.3f / %.3f）" % [f, st.get_length(), float(c.duration_seconds)])
	for f in DirAccess.get_files_at("res://audio/voice"):
		ok(f.get_extension() != "wav", "audio/voice 里有没转换的 WAV（先跑 tools/voice_ogg.py）：" + f)


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
		"shape.line 伤害来源没登记": func(d): d.blocks.progression.elite2.do[0]["src"] = "没登记",
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
	# 随机数：概率 0 / 1 不取数（不改变 g.rng 序列），(0, 1) 取一次
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var fake := {"rng": rng}
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
func test_blocks_texas() -> void:
	var Ch = preload("res://scripts/characters/character.gd")
	var OB = preload("res://scripts/characters/op_blocks.gd")
	var tx: Dictionary = Ch.load_def("texas")
	ok(tx.has("blocks") and Ch.validate_operator("texas", tx), "德克萨斯 texas.json 通过积木校验")
	var bads := {
		"冲刺 aim 写错": func(d): d.blocks.talent[0].do[0]["aim"] = "random",
		"普攻冲刺不朝最近敌人": func(d): d.blocks.attack["aim"] = "densest",
		"冲刺缺宽度": func(d): d.blocks.attack.erase("w"),
		"主控冲刺冷却不再是可写的主控属性（10-12 自动冲刺改版）": func(d): d.blocks.skills[1].do.append({"verb": "buff_leader", "stat": "dash_cd", "op": "mult", "value": 0.8}),
		"天赋自动冲刺的间隔写错": func(d): d.blocks.talent[0]["every"] = 0.01,
		"天赋自动冲刺不是瞬时冲刺放进常驻列表": func(d): d.blocks.talent.append({"trig": "passive", "do": [d.blocks.talent[0].do[0].duplicate(true)]}),
		"瞬时冲刺放进常驻节点": func(d): d.blocks.progression["wide"] = {"shape": "dash_line", "r": 100, "w": 40, "src": "疾行斩"},
		"常驻 dash_mod 放进触发器": func(d): d.blocks.trait[0].do.append({"verb": "dash_mod", "len_add": 0.1}),
		"触发积木放进技能 do": func(d): d.blocks.skills[0].do.append({"trig": "on_dash_end", "do": []}),
		"on_skill_end 带 delay": func(d): d.blocks.trait[2]["delay"] = 0.2,
		"on_dash_end 的 src 没登记": func(d): d.blocks.trait[0]["src"] = "没登记",
		"残像伤害超上限": func(d): d.blocks.progression.elite2.do[0]["mult"] = 50,
		"fx_scatter 缺帧条": func(d): d.blocks.skills[0].do[2].erase("strip"),
	}
	for why in bads:
		var d2: Dictionary = tx.duplicate(true)
		bads[why].call(d2)
		ok(not Ch.validate_operator("texas", d2), "德克萨斯积木校验应拒绝：" + why)
	# 编译：$ 表达式解析成数字、每块编号
	var B: Dictionary = OB.compile(tx)
	# 战术快递（10-12 改自动冲刺）：两块 trig.tick 按「可靠伙伴」生效与否切换，间隔 2.5 / 2.5 × 0.8 = 2.0 秒，各冲一次 aim densest、来源「战术快递」
	near(float(B.talent[0].every), 2.5, "战术快递：自动冲刺间隔 $talent_cd = 2.5")
	near(float(B.talent[1].every), 2.0, "可靠伙伴：自动冲刺间隔 $talent_cd*$s2_cd_mult = 2.0")
	ok(str(B.talent[0].get("_tag", "")) == "trig.tick" and str(B.talent[0].do[0].aim) == "densest" and str(B.talent[0].do[0].src) == "战术快递", "战术快递是 tick → dash_line（densest，来源战术快递），不再挂主控冲刺")
	ok(B.talent[0].cond is Dictionary and str(B.talent[0].cond.k) == "skill_active" and bool(B.talent[0].cond.neg) and not bool(B.talent[1].cond.neg), "两块 tick 的条件互斥（!skill_active:1 / skill_active:1）")
	ok(str(B.attack.get("_tag", "")) == "shape.dash_line" and float(B.attack.r) == 140.0, "普攻编译成 shape.dash_line、长度 140")
	# 常驻累计：S2 冲刺长度 +40%、节点「阔剑」宽度 ×1.3；不写主控属性
	var fake := {"tx": {}}
	var want: Array = []
	OB.tx_sustain(fake, [B.skills[1].do[0], B.skills[1].do[1], B.progression.wide], want)
	near(float(fake.tx.len), 1.4, "冲刺长度倍率 (1 + 0.4)")
	near(float(fake.tx.w), 1.3, "冲刺宽度倍率 ×1.3")
	ok(want.is_empty(), "主控属性修正不在 tx_sustain 里写（verb.buff_leader 归共用段，data_operator._sustain 统一写）：%s" % str(want))
	fake.tx = {}
	want = []
	OB.tx_sustain(fake, [], want)
	ok(float(fake.tx.len) == 1.0 and float(fake.tx.w) == 1.0 and want.is_empty(), "没有常驻积木时倍率回到 1、不写主控属性")


## 常驻跟随帧条 hold / 进出淡入淡出 fade / if_tex / ground 层（docs/61 §5.6，10-12 浊心斯卡蒂 S3 地面漩涡接入）：校验正反例 + 淡入淡出与贴图取舍
func test_fx_hold() -> void:
	var Ch = preload("res://scripts/characters/character.gd")
	var OB = preload("res://scripts/characters/op_blocks.gd")
	var sk: Dictionary = Ch.load_def("skalter")
	ok(sk.has("blocks") and Ch.validate_operator("skalter", sk), "浊心斯卡蒂（含 S3 地面漩涡 hold 帧条）通过校验")
	var bads := {
		"hold 帧条挂在技能发动上（瞬时）": func(d): d.blocks.skills[2].fx.append({"strip": "fx_skalter_vortex_floor", "hold": true, "layer": "ground"}),
		"ground 层不是 hold 帧条": func(d): d.blocks.skills[2].do[0].fx[2].erase("hold"),
		"hold 帧条写 every": func(d): d.blocks.skills[2].do[0].fx[2]["every"] = 1.0,
		"hold 帧条放贴身层": func(d): d.blocks.skills[2].do[0].fx[2]["layer"] = "behind",
		"hold 帧条 at = hits": func(d): d.blocks.skills[2].do[0].fx[2]["at"] = "hits",
		"hold 不是布尔": func(d): d.blocks.skills[2].do[0].fx[2]["hold"] = 1,
		"fade 超出范围": func(d): d.blocks.skills[2].do[0].fx[2]["fade"] = 9,
		"fade 写成三个数": func(d): d.blocks.skills[2].do[0].fx[2]["fade"] = [0.1, 0.2, 0.3],
		"fade 写在一次性条目上": func(d): d.blocks.skills[2].fx[0]["fade"] = 0.3,
		"if_tex 不是帧条名": func(d): d.blocks.skills[2].do[0].fx[3]["if_tex"] = "!skalter",
		"vortex 写 hold": func(d): d.blocks.skills[2].do[0].fx[3]["hold"] = true,
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
