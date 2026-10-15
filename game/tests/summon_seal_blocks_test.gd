extends Node
## 召唤 / 封印 / 护盾 / 治疗光环积木（docs/61 §15）的局内单元测试：
## godot --headless --path game res://tests/summon_seal_blocks_test.tscn -- --regression --balance --seed=1 --op=sstest
## 测试专用干员 tests/data_ops/sstest.json（不进名单 / 招募池 / 图鉴）。把 game.tscn 当子节点跑起来，第 5 帧冻结主场景，直接调积木执行器逐条检查：
## 校验正反例；召唤（技能期间存在 / 永久 / 限时、cap、全编队上限、追咬 / 绕行 / 跟随 / 原地、伤害按本干员 atk / 攻速 / 技能强度、记在本干员来源下、
## 召唤物出手不碰 g.rng）；诱饵（吸引近战杂兵、挨贴身伤害、倒下 on_expire）；封印（敌人一侧的挂点：特殊招式 / 远程开火 / 词条、精英减半、
## Boss 缩短 + 免疫、Boss 不起新招）；护盾（叠加封顶、经 combat.enemy_hit 吸收、衰减、到时消失）；治疗光环；老数据干员不受影响。
## 全部通过时打印 "SUMMON SEAL BLOCKS failures=0"。

const OB = preload("res://scripts/characters/op_blocks.gd")
const Ch = preload("res://scripts/characters/character.gd")
const D = preload("res://scripts/data.gd")

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
	test_validate()
	var o = game.squad.get_op("sstest")
	ok(o != null, "测试干员在编队里（--op=sstest）")
	if o != null:
		test_summon(o)
		test_seal(o)
		test_decoy(o)
		test_shield_heal(o)
		test_caps(o)
	test_old_data_op()
	print("%d checks, %d failed" % [n, fails])
	print("SUMMON SEAL BLOCKS failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		fails += 1
		printerr("FAIL: ", what)


func near(a: float, b: float, what: String, eps := 0.001) -> void:
	ok(absf(a - b) < eps, "%s（期望 %s，实际 %s）" % [what, b, a])


func spawn(type: String, pos: Vector2, hp := 99999.0) -> Dictionary:
	var e: Dictionary = game.spawner.spawn_enemy(type, pos)
	e.hp = hp
	e.maxhp = hp
	e.spd = 0.0
	game.enemies_sys.build_grid()
	return e


func clear_enemies() -> void:
	for e in game.enemies:
		e.dead = true
	game.enemies = []
	game.warns = []
	game.ebullets = []
	game.lobs = []
	game.enemies_sys.build_grid()


func ticks(o, sec: float) -> void:
	var t := 0.0
	while t < sec:
		OB.sm_tick(o, 1.0 / 60.0)
		game.enemies_sys.build_grid()
		t += 1.0 / 60.0


func kinds(o, k: String) -> Array:
	return o.sm.get("list", []).filter(func(s): return s.kind == k)


# ---------------------------------------------------------------- 校验

func test_validate() -> void:
	var d: Dictionary = Ch.load_def("sstest")
	ok(d.has("blocks") and Ch.validate_operator("sstest", d), "测试干员 JSON 通过积木校验")
	var bads := {
		"召唤没定义的种类": func(x): x.blocks.skills[0].do[0]["kind"] = "ghost",
		"life = skill 放在触发器里": func(x): x.blocks.trait[0].do[0]["life"] = "skill",
		"cap 超过 12": func(x): x.blocks.summons.wolf["cap"] = 50,
		"移动方式写错": func(x): x.blocks.summons.wolf.move["mode"] = "fly",
		"召唤物攻击不是 circle / cone / line": func(x): x.blocks.summons.orb.attack["shape"] = "projectile",
		"封印放进技能 do": func(x): x.blocks.skills[1].do.append({"st": "seal", "dur": 2}),
		"封印时长超范围": func(x): x.blocks.skills[1].do[0].on_hit[0]["dur"] = 20,
		"on_expire 里再召唤": func(x): x.blocks.summons.decoy.on_expire.append({"verb": "summon", "kind": "wolf"}),
		"body.strip 不是帧条名": func(x): x.blocks.summons.orb.body["strip"] = "note",
		"缺 life": func(x): x.blocks.summons.hound.erase("life"),
		"无敌还写 hp": func(x): x.blocks.summons.wolf["hp"] = 50,
		"有生命却没写 hp": func(x): x.blocks.summons.decoy.erase("hp"),
		"护盾比例超范围": func(x): x.blocks.skills[2].do[0]["pct"] = 5,
		"治疗光环 scope 写错": func(x): x.blocks.progression.regen["scope"] = "squad",
		"治疗光环放进触发器 do": func(x): x.blocks.trait[0].do.append({"aura": "heal", "pct": 0.01}),
		"召唤位置写错": func(x): x.blocks.skills[0].do[0]["at"] = "moon",
		"summons 不是对象": func(x): x.blocks["summons"] = [],
		"召唤物定义多了不认识的字段": func(x): x.blocks.summons.wolf["speed"] = 3,
		"召唤物攻击来源没登记": func(x): x.blocks.summons.orb.attack["src"] = "没登记",
		"enemy_target 写错": func(x): x.blocks.summons.decoy["enemy_target"] = "always",
		"选目标写错": func(x): x.blocks.summons.wolf.move["target"] = "random",
		"圆形判定以区域为心": func(x): x.blocks.summons.wolf.attack["center"] = "zone",
		"召唤物攻击缺 every": func(x): x.blocks.summons.hound.attack.erase("every"),
		"封印 boss 不是布尔": func(x): x.blocks.skills[1].do[0].on_hit[0]["boss"] = "no",
		"$ 引用不存在": func(x): x.blocks.summons.wolf.move["speed"] = "$nope",
	}
	for why in bads:
		var d2: Dictionary = d.duplicate(true)
		bads[why].call(d2)
		ok(not Ch.validate_operator("sstest", d2), "积木校验应拒绝：" + why)
	var B: Dictionary = OB.compile(d)
	near(float(B.summons.wolf.cap), 4.0, "编译：cap = $wolf_cap")
	near(float(B.summons.wolf.attack.on_hit[0].dur), 2.0, "编译：狼首封印 = $wolf_seal")
	ok(str(B.summons.wolf.life) == "skill" and str(B.summons.orb.life) == "permanent", "编译：life 的字符串值原样保留")


# ---------------------------------------------------------------- 召唤

func test_summon(o) -> void:
	clear_enemies()
	o.pos = game.ppos + Vector2(-40, 0)
	# 1. S1：召唤 2 只狼首，绑定技能 0
	o.cur_skill = 0
	o._release_skill()
	var wolves := kinds(o, "wolf")
	ok(wolves.size() == 2 and wolves.all(func(s): return int(s.skill) == 0 and float(s.life) < 0.0), "S1 召唤 2 只狼首、随技能 0 存在（实际 %d）" % wolves.size())
	ok(wolves.all(func(s): return s.pos.distance_to(game.ppos) < 40.0), "狼首出生在主控身边（at leader，spread 30）")
	ok(o.extra_bodies().size() == 2, "召唤物参与 2.5D 排序（extra_bodies）")
	# 2. 追咬 + 封印：敌人掉血、来源记在本干员名下、带 summon 标签、被封印；全程不碰 g.rng
	var e1 := spawn("fractal", game.ppos + Vector2(160, 0))
	var hp0: float = e1.hp
	var out0: float = float(game.dmg_out.get("狼首", 0.0))
	var tag0: float = float(game.dmg_tag_out.get("summon", 0.0))
	var rng0 = game.rng_states()
	ticks(o, 2.0)
	ok(e1.hp < hp0, "狼首追上去咬到（%.0f → %.0f）" % [hp0, e1.hp])
	ok(float(game.dmg_out.get("狼首", 0.0)) > out0, "伤害记在「狼首」（本干员 hit_sources）名下")
	ok(str(game.hit_src.get("狼首", {}).get("op", "")) == "sstest", "「狼首」来源归属本干员（遥测按 op 分）")
	ok(float(game.dmg_tag_out.get("summon", 0.0)) > tag0, "召唤物伤害自动带 summon 标签")
	ok(OB.sealed(e1, game.t) and str(e1.get("seal_by", "")) == "sstest" and o.sm.seal.has(int(e1.id)), "狼首命中附带封印")
	ok(kinds(o, "wolf").all(func(s): return s.pos.distance_to(e1.pos) < 70.0), "两只狼首都贴到目标身边")
	ok(game.rng_states() == rng0, "召唤物移动 / 出手 / 封印不碰 g.rng")
	# 3. 伤害 / 攻速 / 技能强度跟着本干员走
	var a: Dictionary = o.B.summons.wolf.attack
	var d0: float = OB.sm_dmg(o, a)
	near(d0, o.base("atk", 0.0) * 0.6 * float(o.loc.dmg) * o._dmg_bonus() * o.skill_power(), "狼首伤害 = atk × mult × 局部 dmg × 通用倍率 × 技能强度（power）")
	game.stats.add(&"op_atk", "add", 1.0, "sm_test", "op:sstest")
	game.stats.add(&"op_skill_power", "add", 0.5, "sm_test", "op:sstest")
	game.stats.add(&"op_aspd", "add", 1.0, "sm_test", "op:sstest")
	o.refresh_stats()
	var k_atk: float = o.stat(&"op_atk")
	near(OB.sm_dmg(o, a) / d0, k_atk / (k_atk - 1.0) * o.skill_power() / (o.skill_power() - 0.5), "召唤物吃本干员 op_atk 与技能强度", 0.0001)
	var w: Dictionary = kinds(o, "wolf")[0]
	w.cd = 0.0
	w.tgt = e1
	w.pos = e1.pos + Vector2(12, 0)
	OB._sm_step(o, w, o.B.summons.wolf, 0, 2, 0.0)
	near(float(w.cd), 0.8 / o.stat(&"op_aspd"), "出手间隔 = every / op_aspd")
	game.stats.remove_source("sm_test")
	o.refresh_stats()
	# 4. 技能结束 → 狼首消失（life: skill）
	o.s_t[0] = 0.0
	OB.sm_tick(o, 1.0 / 60.0)
	ok(kinds(o, "wolf").is_empty(), "技能结束狼首消失")
	# 5. 绕行浮游：成长节点 trig.tick 每 5 秒放一个（cap 3），绕主控 orbit_r 转、自动打附近的敌人
	o.on_custom_node("orbs")
	for k in 5:
		o._sustain(5.0)
	ok(kinds(o, "orb").size() == 3, "浮游 cap 3（放了 5 次，实际 %d）" % kinds(o, "orb").size())
	ticks(o, 1.0)
	var orr: float = float(o.B.summons.orb.move.orbit_r)
	ok(kinds(o, "orb").all(func(s): var dd: float = s.pos.distance_to(game.ppos); return dd > orr * 0.5 and dd < orr * 1.05), "浮游在主控周围的地面椭圆上转")
	var ang0: Array = kinds(o, "orb").map(func(s): return (s.pos - game.ppos).angle())
	ticks(o, 0.3)
	var ang1: Array = kinds(o, "orb").map(func(s): return (s.pos - game.ppos).angle())
	ok(absf(angle_difference(ang0[0], ang1[0])) > 0.2, "浮游在绕行（0.3 秒转过 %.2f 弧度）" % absf(angle_difference(ang0[0], ang1[0])))
	var e2 := spawn("fractal", game.ppos + Vector2(0, 50))
	var hp2: float = e2.hp
	ticks(o, 1.5)
	ok(e2.hp < hp2 and float(game.dmg_out.get("浮游", 0.0)) > 0.0, "浮游打到身边的敌人")
	# 6. 每第 3 次脉冲放猎犬（限时 4 秒、跟随本干员）
	o.on_custom_node("hound")
	for k in 3:
		o._release()
	var hs := kinds(o, "hound")
	ok(hs.size() == 1 and is_equal_approx(float(hs[0].life), 4.0), "第 3 次脉冲放出一只限时 4 秒的猎犬")
	ticks(o, 4.2)
	ok(kinds(o, "hound").is_empty(), "猎犬 4 秒后消失")
	ok(not kinds(o, "orb").is_empty(), "永久浮游还在")
	clear_enemies()


# ---------------------------------------------------------------- 封印

func first_type(pred: Callable) -> String:
	for k in D.ENEMIES:
		if pred.call(D.ENEMIES[k]):
			return k
	return ""


func step_enemies(sec: float) -> void:
	var t := 0.0
	while t < sec:
		game.enemies_sys.update(1.0 / 60.0)
		game.enemies_sys.build_grid()
		game.t += 1.0 / 60.0   # 主场景冻结了，局内时间手动推（远程开火有 0.35 秒起手、封印按 g.t 到期）
		t += 1.0 / 60.0


func test_seal(o) -> void:
	clear_enemies()
	var t0: float = game.t
	var s4 := {"st": "seal", "dur": 4.0}
	# 1. 时长：普通 4、精英 ×0.5；不缩短更长的封印
	var e := spawn("fractal", game.ppos + Vector2(300, 0))
	OB.apply_status(o, e, s4)
	near(float(e.seal_t) - t0, 4.0, "普通敌人封印 4 秒")
	OB.apply_status(o, e, {"st": "seal", "dur": 1.0})
	near(float(e.seal_t) - t0, 4.0, "短封印不缩短已有的")
	var el := spawn("fractal", game.ppos + Vector2(320, 0))
	el.elite = true
	OB.apply_status(o, el, s4)
	near(float(el.seal_t) - t0, 2.0, "精英封印 ×0.5")
	# 2. Boss：× boss_mult 0.3、封顶 1.5，之后免疫 boss_immune 10 秒；boss: false 不受
	var bo := spawn("fractal", game.ppos + Vector2(340, 0))
	bo.boss = true
	OB.apply_status(o, bo, {"st": "seal", "dur": 4.0, "boss": false})
	ok(not OB.sealed(bo, game.t), "boss: false 的封印不作用于 Boss")
	OB.apply_status(o, bo, s4)
	near(float(bo.seal_t) - t0, 1.2, "Boss 封印 4 × 0.3 = 1.2 秒")
	near(float(bo.seal_imm) - t0, 11.2, "Boss 封印结束后免疫 10 秒")
	OB.apply_status(o, bo, {"st": "seal", "dur": 10.0})
	near(float(bo.seal_t) - t0, 1.2, "免疫期间再封印无效")
	bo.seal_imm = 0.0
	bo.seal_t = 0.0
	OB.apply_status(o, bo, {"st": "seal", "dur": 10.0})
	near(float(bo.seal_t) - t0, 1.5, "Boss 封印封顶 boss_max 1.5 秒")
	clear_enemies()
	# 3. 远程杂兵：封印期间不开火，解封后照常
	var rt := first_type(func(x): return str(x.get("ai", "")) == "ranged" and str(x.get("role", "")) == "" and not x.get("spit", false) and not x.get("lob", false))
	ok(rt != "", "找到普通远程敌人类型（%s）" % rt)
	if rt != "":
		var r := spawn(rt, game.ppos + Vector2(120, 0))
		r.cdt = 0.0
		r.spd = 1.0   # 开火条件要 spd > 0
		OB.apply_status(o, r, s4)
		step_enemies(1.5)
		ok(game.ebullets.is_empty() and game.lobs.is_empty(), "封印中的远程敌人不开火")
		r.seal_t = 0.0
		step_enemies(1.5)
		ok(not game.ebullets.is_empty() or not game.lobs.is_empty(), "解封后照常开火")
	clear_enemies()
	# 4. 特殊招式（slider 冲刺）：封印期间不起冲刺；不封印时会起
	var sl := spawn("slider", game.ppos + Vector2(150, 0))
	sl.dash_cd = 0.0
	OB.apply_status(o, sl, {"st": "seal", "dur": 10.0})
	var dashed := false
	for k in 120:
		step_enemies(1.0 / 60.0)
		dashed = dashed or float(sl.get("dash_w", 0.0)) > 0.0 or float(sl.get("dash_t", 0.0)) > 0.0
	ok(not dashed, "封印中的冲刺怪不起冲刺")
	sl.seal_t = 0.0
	for k in 120:
		step_enemies(1.0 / 60.0)
		dashed = dashed or float(sl.get("dash_w", 0.0)) > 0.0 or float(sl.get("dash_t", 0.0)) > 0.0
	ok(dashed, "解封后照常冲刺")
	ok(game.eai.busy({"dash_w": 0.3}) and not game.eai.busy({}), "已经起手的冲刺算「进行中」，封印不卡住它")
	clear_enemies()
	# 5. 词条：潮盾不挡、甲壳失效
	var es := spawn("fractal", game.ppos + Vector2(300, 0))
	es.affix = "shield"
	es.shield_hp = 1000.0
	o.log_hit("测试封印脉冲")
	o.deal_damage(es, 50.0)
	ok(float(es.shield_hp) < 1000.0 and es.hp == es.maxhp, "没封印：潮盾先挡")
	OB.apply_status(o, es, s4)
	var sh0: float = es.shield_hp
	o.log_hit("测试封印脉冲")
	o.deal_damage(es, 50.0)
	ok(float(es.shield_hp) == sh0 and es.hp < es.maxhp, "封印：潮盾不挡")
	var ea := spawn("fractal", game.ppos + Vector2(300, 40))
	ea.affix = "armor"
	ea.def = 0.75
	var h0: float = ea.hp
	o.log_hit("测试封印脉冲")
	o.deal_damage(ea, 40.0)
	var d_armor: float = h0 - ea.hp
	OB.apply_status(o, ea, s4)
	h0 = ea.hp
	o.log_hit("测试封印脉冲")
	o.deal_damage(ea, 40.0)
	var d_seal: float = h0 - ea.hp
	near(d_armor / maxf(0.001, d_seal), 0.75, "封印：甲壳词条失效（伤害比 0.75）", 0.01)
	clear_enemies()
	# 6. Boss 不起新招：真 Boss（主教）封印期间预警数不涨；解封后照常出招（对照组）
	var bt := "bishop" if D.ENEMIES.has("bishop") else first_type(func(x): return str(x.get("role", "")) == "boss")
	if bt != "":
		var b: Dictionary = game.spawner.spawn_enemy(bt, game.ppos + Vector2(200, 0))
		game.enemies_sys.build_grid()
		b.age = 10.0
		b.bt = 10.0
		b["seal_t"] = game.t + 100.0
		var w0: int = game.warns.size()
		for k in 180:
			var dv: Vector2 = game.ppos - b.pos
			game.bai._boss_ai(b, 1.0 / 60.0, dv.normalized(), dv.length())
			game.t += 1.0 / 60.0
		ok(game.warns.size() == w0, "封印中的 Boss（%s）不起新招（预警 %d → %d）" % [bt, w0, game.warns.size()])
		b.seal_t = 0.0
		for k in 600:
			var dv2: Vector2 = game.ppos - b.pos
			game.bai._boss_ai(b, 1.0 / 60.0, dv2.normalized(), dv2.length())
			game.t += 1.0 / 60.0
			if game.warns.size() > w0:
				break
		ok(game.warns.size() > w0, "解封后 Boss（%s）照常出招（对照组）" % bt)
	clear_enemies()


# ---------------------------------------------------------------- 诱饵（enemy_target: decoy）

func test_decoy(o) -> void:
	clear_enemies()
	var near_e := spawn("fractal", game.ppos + Vector2(120, 0))
	var far_e := spawn("fractal", game.ppos + Vector2(600, 0))
	o.cur_skill = 1
	o._release_skill()
	ok(OB.sealed(near_e, game.t) and not OB.sealed(far_e, game.t), "S2：主控 200 内的敌人被封印，远处的不受")
	var dc := kinds(o, "decoy")
	ok(dc.size() == 1, "S2 放下一个诱饵")
	if dc.is_empty():
		return
	var s: Dictionary = dc[0]
	OB.sm_tick(o, 1.0 / 60.0)
	ok(near_e.aggro == s.pos and far_e.aggro == Vector2.INF, "诱饵吸引 180 内的近战杂兵（e.aggro），远处的不理")
	near_e.pos = s.pos + Vector2(5, 0)
	near_e.dmg = 10.0
	game.enemies_sys.build_grid()
	OB.sm_tick(o, 1.0 / 60.0)
	near(float(s.hp), 60.0 - 10.0 * 0.5, "贴身敌人打诱饵（伤害 × hurt_mult 0.5）")
	OB.sm_tick(o, 1.0 / 60.0)
	near(float(s.hp), 55.0, "同一个敌人 1 秒一次")
	var out0: float = float(game.dmg_out.get("诱饵爆", 0.0))
	s.hp = 0.0
	OB.sm_tick(o, 1.0 / 60.0)
	ok(kinds(o, "decoy").is_empty(), "诱饵生命归零消失")
	ok(float(game.dmg_out.get("诱饵爆", 0.0)) > out0, "诱饵倒下执行 on_expire（就地爆炸）")
	# 精英击杀处放诱饵（trig.on_kill → verb.summon at target）
	o.on_kill({"pos": game.ppos + Vector2(80, 30), "elite": true, "boss": false})
	var dc2 := kinds(o, "decoy")
	ok(dc2.size() == 1 and dc2[0].pos.distance_to(game.ppos + Vector2(80, 30)) < 30.0, "精英击杀处放下诱饵")
	OB.sm_clear(o)
	ok(o.sm.list.is_empty(), "离队清掉全部召唤物")
	clear_enemies()


# ---------------------------------------------------------------- 护盾 / 治疗光环

func test_shield_heal(o) -> void:
	clear_enemies()
	var mh: float = game.max_hp
	o.cur_skill = 2
	o._release_skill()
	near(float(o.sm.shield), mh * 0.2, "S3 护盾 = 20% 最大生命")
	o._release_skill()
	near(float(o.sm.shield), mh * 0.3, "叠加封顶 cap 30%")
	near(o.dmg_taken_mult({}, 10.0), 0.0, "护盾全吸收：倍率 0（combat 按作废处理）")
	near(float(o.sm.shield), mh * 0.3 - 10.0, "吸收量从护盾里扣")
	o.sm.shield = 3.0
	near(o.dmg_taken_mult({}, 10.0), 0.7, "护盾只剩 3：吸收 3，倍率 0.7")
	near(float(o.sm.shield), 0.0, "护盾打空")
	# 经 combat.enemy_hit 走一遍：护盾吸收整下 → 不扣血
	o._release_skill()
	var hp0: float = game.hp
	game.invuln = 0.0
	game.in_type = ["近战", "物理"]
	game.combat.enemy_hit(20.0, {}, false, true)
	ok(game.hp == hp0, "enemy_hit：护盾吸收整下，主控不掉血（%.1f → %.1f）" % [hp0, game.hp])
	ok(float(o.sm.shield) < mh * 0.3, "enemy_hit 扣了护盾（受击询问传了这一下的伤害）")
	var sh: float = o.sm.shield
	OB.sm_tick(o, 1.0)
	near(float(o.sm.shield), sh * (1.0 - 0.05), "每秒按当前量衰减 5%", 0.01)
	OB.sm_tick(o, 10.0)
	near(float(o.sm.shield), 0.0, "持续时间到护盾消失")
	# 治疗光环：主控在区域内每秒回复 1% 最大生命
	o.on_custom_node("regen")
	game.hp = mh * 0.5
	o._sustain(0.5)
	o._sustain(0.6)
	near(game.hp, mh * 0.5 + mh * 0.01 * float(o.loc.heal), "治疗光环 1 秒回复 1%", 0.01)


# ---------------------------------------------------------------- 上限

func test_caps(o) -> void:
	clear_enemies()
	OB.sm_clear(o)
	var sv: Dictionary = {}
	for k in ["wolf", "orb", "hound"]:
		sv[k] = o.B.summons[k].cap
		o.B.summons[k].cap = 12
	for k in 15:
		for kind in ["wolf", "orb", "hound"]:
			OB.sm_spawn(o, {"kind": kind, "life": 5.0}, Vector2.INF)
	ok(o.sm.list.size() == OB.SM_TOTAL_CAP, "全编队召唤物上限 %d（实际 %d）" % [OB.SM_TOTAL_CAP, o.sm.list.size()])
	for k in sv:
		o.B.summons[k].cap = sv[k]
	OB.sm_clear(o)
	for k in 6:
		OB.sm_spawn(o, {"kind": "hound"}, Vector2.INF)
	ok(kinds(o, "hound").size() == 2, "同种超过 cap 时最早的先到期（猎犬 cap 2）")
	OB.sm_clear(o)


## 老数据干员（浊心斯卡蒂）不受本段影响：sm 一直是空的，没有召唤物
func test_old_data_op() -> void:
	var sk = Ch.create(game, "skalter")
	ok(sk != null, "浊心斯卡蒂能建")
	if sk != null:
		OB.sm_tick(sk, 0.1)
		ok(sk.sm.is_empty() and sk.extra_bodies().is_empty() and OB.sm_status_items(sk).is_empty(), "老数据干员用不到召唤 / 封印段")
		near(OB.shield_mult(sk, 0.8, 10.0), 0.8, "没有护盾时受击倍率原样返回")
