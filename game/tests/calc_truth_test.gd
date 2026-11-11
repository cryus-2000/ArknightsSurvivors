extends Node
## 计算正确性（docs/335 §2）：说明里写的数 = 实际生效的数。逐条在干净状态下打一下 / 挨一下，和手算比：
##   godot --headless --path game res://tests/calc_truth_test.tscn -- --regression --balance --seed=1 --op=skadi --squad=kaltsit,texas
## A 属性块计算顺序（(基础 + 固定) × (1 + Σ百分比) × Π倍率；max_hp 固定加成在倍率之后）
## B 我方 → 敌人：灯火照亮 25% / 通明 40%、弱点 ×1.5、精英 / Boss 倍率、Boss 单次 4% 上限、破绽 ×1.4、终结技绕过单次上限、处决线
## C 敌人 → 我方：受伤倍率 → 物理减伤 → 护甲（至少 1）→ 法抗（封顶 70%）→ Boss 单发 40% / 2 秒 68% → 全来源 2 秒 70% 超出 ×0.6
## D 藏品「纯属性」件：数据值逐件挂进属性块（来源 relic:<id>）、二三级按 LV_SCALE 递减、卡面「本级 N%」与递减系数一致
## E 入队台阶：每名队友最大生命 ×(1 + 15%) 与回复 +0.15 / 秒，指南 / 三选一说明行的数字读同一份旋钮
## F 指南写死的数：照亮 / 通明加成、熔铸每 15 枚 +1% 上限 20%、撤回线 30%
## G 升级卡（成长被动）卡面「现值 → 选中后」：选中后再看同一张卡，「现值」必须等于刚才写的「选中后」（预览里的增量与实际挂上去的一致）
## 全部通过打印 "CALC TRUTH failures=0"。

const Bal = preload("res://scripts/core/balance.gd")
const Sq = preload("res://scripts/characters/squad.gd")
const StatBlock = preload("res://scripts/core/stat_block.gd")
const Intro = preload("res://scripts/screens/intro.gd")

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
	test_stat_order()
	test_out_chain()
	test_in_chain()
	test_relic_stats()
	test_squad_tiers()
	test_guide_numbers()
	test_growth_preview()
	print("%d checks, %d failed" % [n, fails])
	print("CALC TRUTH failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		fails += 1
		printerr("FAIL: ", what)


func near(a: float, b: float, what: String, eps := 0.002) -> void:
	ok(absf(a - b) <= eps * maxf(1.0, absf(b)), "%s（期望 %s，实际 %s）" % [what, b, a])


# ---------------------------------------------------------------- A
func test_stat_order() -> void:
	var s = StatBlock.new()
	s.define(&"x", 10.0)
	s.add(&"x", "flat", 5.0, "a")
	s.add(&"x", "add", 0.2, "b")
	s.add(&"x", "add", 0.3, "c")
	s.add(&"x", "mult", 1.5, "d")
	s.add(&"x", "mult", 0.8, "e")
	near(s.value(&"x"), (10.0 + 5.0) * (1.0 + 0.5) * 1.2, "属性：(基础+固定)×(1+Σ百分比)×Π倍率")
	s.define(&"max_hp", 100.0)
	s.add(&"max_hp", "flat", 20.0, "a")
	s.add(&"max_hp", "add", 0.1, "b")
	s.add(&"max_hp", "mult", 1.3, "squad")
	near(s.value(&"max_hp"), 100.0 * 1.1 * 1.3 + 20.0, "最大生命：固定加成在倍率之后（卡上写多少加多少，docs/199）")
	s.remove_source("squad")
	near(s.value(&"max_hp"), 100.0 * 1.1 + 20.0, "撤掉来源后回到原值")
	s.define(&"y", 1.0, 0.0, 2.0)
	s.add(&"y", "add", 5.0, "z")
	near(s.value(&"y"), 2.0, "上下限生效")


# ---------------------------------------------------------------- B
func _enemy(far := true) -> Dictionary:
	var pos: Vector2 = game.ppos + (Vector2(2400, 0) if far else Vector2(30, 0))
	var e: Dictionary = game.spawner.spawn_enemy("runner", pos)
	e.pos = pos
	e.maxhp = 1.0e6
	e.hp = e.maxhp
	e.def = 1.0
	e.weak = ""
	e.elite = false
	e.boss = false
	e.lit = 0.0
	e.erase("aura_weak")
	e.erase("affix")
	e.shield_hp = 0.0
	return e


func _hit(kind := "物理", rng := "远程", tags: Array = []) -> Dictionary:
	return {"src": "calc_truth", "emitter": "operator", "origin": "core", "range": rng, "kind": kind, "tags": tags, "class": "", "op": ""}


func _dealt(e: Dictionary, dmg: float, h: Dictionary) -> float:
	var h0: float = e.hp
	game.combat.damage(e, dmg, h)
	var d: float = h0 - e.hp
	e.hp = e.maxhp
	return d


func test_out_chain() -> void:
	var lamp0: float = game.lamp
	var e := _enemy()
	var base_mult: float = game.rfx.dmg_extra() * game.phys_mult * game.ranged_mult
	var d0 := _dealt(e, 100.0, _hit())
	near(d0, 100.0 * base_mult, "基准：100 × 藏品伤害 × 物理 × 远程")
	# 灯火照亮（指南：圈内 +25%；通明 ≥70 时 +40%）
	var e2 := _enemy(false)
	game.lamp = 50.0
	near(_dealt(e2, 100.0, _hit()) / d0, 1.0 + Bal.v("lamp/lit_bonus", 0.25), "灯火圈内 +25%")
	game.lamp = 80.0
	near(_dealt(e2, 100.0, _hit()) / d0, 1.0 + Bal.v("lamp/lit_bonus_hi", 0.4), "灯火通明圈内 +40%")
	e2.pos = game.ppos + Vector2(2400, 0)
	game.lamp = lamp0
	# 弱点 ×1.5（+ 弱点加成），类型不对不加
	e.weak = "物理"
	near(_dealt(e, 100.0, _hit()) / d0, 1.5 + game.weak_bonus, "弱点命中 ×1.5")
	near(_dealt(e, 100.0, _hit("法术")) / (100.0 * game.rfx.dmg_extra() * game.arts_mult * game.ranged_mult), 1.0, "弱点类型不对不加成")
	e.weak = ""
	# 防御：def 0.6 → ×0.6；法术不吃防御（原作口径）
	e.def = 0.6
	near(_dealt(e, 100.0, _hit()) / d0, 0.6, "防御 ×def")
	e.def = 1.0
	# 精英 / Boss 倍率
	game.elite_mult = 1.2
	e.elite = true
	near(_dealt(e, 100.0, _hit()) / d0, 1.2, "对精英倍率")
	e.elite = false
	game.elite_mult = 1.0
	game.sync_stats()
	# Boss：对 Boss 倍率、单次 4% 上限、破绽 ×1.4、终结技不吃上限
	e.boss = true
	e["gates"] = []
	e["last_done"] = true
	e["break_t"] = 0.0
	game.boss_mult = 1.25
	near(_dealt(e, 100.0, _hit()) / d0, 1.25, "对 Boss 倍率")
	var cap: float = Bal.v("boss/hit_cap_pct", 0.04)
	near(_dealt(e, 1.0e5, _hit()), e.maxhp * cap, "Boss 单次上限 %d%% 最大生命" % int(cap * 100))
	e.break_t = 1.0
	near(_dealt(e, 100.0, _hit()) / d0, 1.25 * Bal.v("boss/break_mult", 1.4), "破绽受伤 ×1.4")
	e.break_t = 0.0
	if game.ult != null:
		var big := _dealt(e, 1.0e5, _hit("物理", "远程", ["终结技"]))
		ok(big > e.maxhp * cap * 1.5, "终结技按最大生命定档、不吃 4%% 单次上限（%.0f）" % big)
	game.boss_mult = 1.0
	game.sync_stats()
	e.boss = false
	# 处决（认知「攻击性」末节）：普通敌人低于 15% 直接击杀
	if not game.rfx.rules.has("execute"):
		game.rfx.rules["execute"] = 1
		game.rfx._rule_cache.clear()
		e.hp = e.maxhp * 0.2
		game.combat.damage(e, e.maxhp * 0.06, _hit())
		ok(e.hp <= 0.0, "处决：打到 15%% 以下直接击杀（剩 %.0f）" % e.hp)
		game.rfx.rules.erase("execute")
		game.rfx._rule_cache.clear()


# ---------------------------------------------------------------- C
func _take(amount: float, kind := "物理", boss := false, ignore_armor := false) -> float:
	game.invuln = 0.0
	game.in_type = ["近战", kind]
	game.dmg_src = "calc_truth"
	var h0: float = game.hp
	game.combat.hurt(amount, ignore_armor, boss)
	var d: float = h0 - game.hp
	game.hp = game.max_hp
	return d


func _reset_logs() -> void:
	game.combat.any_log.clear()
	game.combat.loss_log.clear()
	game.combat.boss_log.clear()
	game.combat.dot_log.clear()
	game.t += 5.0   # 窗口外


func test_in_chain() -> void:
	game.hp = game.max_hp
	var tm: float = game.rfx.taken_mult()
	var armor0: float = game.armor
	game.armor = 5.0
	_reset_logs()
	near(_take(20.0), maxf(1.0, 20.0 * tm * game.phys_taken_mult - 5.0), "物理：×受伤倍率 ×物理减伤 − 护甲")
	_reset_logs()
	near(_take(3.0), 1.0, "护甲减到不足 1 点时至少 1 点")
	_reset_logs()
	near(_take(20.0, "物理", false, true), 20.0 * tm * game.phys_taken_mult, "无视护甲的物理（冲击环）只吃物理减伤")
	game.armor = armor0
	var res0: float = game.arts_res
	game.arts_res = 0.9
	_reset_logs()
	near(_take(20.0, "法术"), 20.0 * tm * 0.3, "法抗封顶 70%")
	game.arts_res = 0.2
	_reset_logs()
	near(_take(20.0, "法术"), 20.0 * tm * 0.8, "法抗 20%")
	game.arts_res = res0
	_reset_logs()
	near(_take(20.0, "真实"), 20.0, "真实伤害不吃受伤倍率 / 护甲 / 法抗")
	# Boss 单发 40%、2 秒 68%（docs/38 §1.11）；满血保护会把这一下压到剩 5%，测试从 80% 生命起手避开它
	var mh: float = game.max_hp
	_reset_logs()
	game.combat.high_t = -100.0
	game.invuln = 0.0
	game.in_type = ["近战", "真实"]
	game.hp = mh * 0.8
	game.combat.hurt(mh * 0.9, false, true)
	near(mh * 0.8 - game.hp, mh * Bal.v("boss/leader_hit_cap", 0.4), "Boss 单发上限 40%")
	game.hp = mh * 0.8
	game.invuln = 0.0
	game.combat.hurt(mh * 0.9, false, true)
	near(mh * 0.8 - game.hp, mh * (Bal.v("boss/leader_2s_cap", 0.68) - Bal.v("boss/leader_hit_cap", 0.4)), "Boss 2 秒合计上限 68%：第二下只剩 28%")
	game.hp = mh
	# 全来源 2 秒 70%，超出部分 ×0.6
	_reset_logs()
	game.in_type = ["近战", "真实"]
	game.hp = mh * 2.0   # 只看扣血量，不让生命归零
	game.invuln = 0.0
	game.combat.hurt(mh * 0.5, false, false)
	var hp1: float = game.hp
	game.invuln = 0.0
	game.combat.hurt(mh * 0.5, false, false)
	var cap2: float = Bal.v("protect/any_2s_cap", 0.7)
	near(hp1 - game.hp, mh * (cap2 - 0.5) + mh * (1.0 - cap2) * Bal.v("protect/any_excess_mult", 0.6), "全来源 2 秒 70%，超出 ×0.6")
	game.hp = mh
	game.in_type = ["近战", "物理"]
	_reset_logs()


# ---------------------------------------------------------------- D
func test_relic_stats() -> void:
	var rfx = game.rfx
	var data: Dictionary = game.RL
	var cnt := 0
	ok(rfx.lv_scale(0) == 1.0 and rfx.lv_scale(1) < 1.0 and rfx.lv_scale(2) < rfx.lv_scale(1), "叠层单调递减 %s" % [rfx.LV_SCALE])
	for rid in data.keys():
		var r: Dictionary = rfx.db.get_relic(rid)
		var effs: Array = r.get("effects", [])
		if effs.is_empty() or not effs.all(func(x): return x is Dictionary and x.get("type", "stat") == "stat"):
			continue
		if game.relics.has(rid):
			continue
		var before: Dictionary = {}
		for ef in effs:
			before[ef.stat] = _mods_of(ef.stat, "relic:" + rid)
		rfx.apply(rid)
		cnt += 1
		for ef in effs:
			var got: Array = _mods_of(ef.stat, "relic:" + rid)
			ok(got.size() > before[ef.stat].size(), "藏品 %s：%s 挂进属性块" % [rid, ef.stat])
			if got.size() > 0:
				var m: Dictionary = got[got.size() - 1]
				near(float(m.value), float(ef.value), "藏品 %s %s 数值 = 数据" % [rid, ef.stat], 1e-6)
		# 二级：按递减系数
		if rfx.max_lv(rid) >= 2:
			var desc2: String = rfx.display_desc(rid)
			ok(desc2.contains("本级 %d%%" % int(rfx.lv_scale(1) * 100.0)), "藏品 %s 二级卡面写「本级 %d%%」：%s" % [rid, int(rfx.lv_scale(1) * 100.0), desc2.substr(desc2.length() - 20)])
			rfx.apply(rid)
			for ef in effs:
				var got2: Array = _mods_of(ef.stat, "relic:" + rid)
				var m2: Dictionary = got2[got2.size() - 1]
				var want: float = float(ef.value) * rfx.lv_scale(1) if ef.get("op", "add") != "mult" else 1.0 - (1.0 - float(ef.value)) * rfx.lv_scale(1)
				near(float(m2.value), want, "藏品 %s 二级 %s 按递减系数" % [rid, ef.stat], 1e-6)
		game.stats.remove_source("relic:" + rid)
		rfx.lv.erase(rid)
	game.sync_stats()
	ok(cnt >= 40, "纯属性藏品样本 %d 件" % cnt)


func _mods_of(stat: String, src: String) -> Array:
	var out: Array = []
	for m in game.stats._mods.get(StringName(stat), []):
		if str(m.get("source", "")) == src:
			out.append(m)
	return out


# ---------------------------------------------------------------- E
func test_squad_tiers() -> void:
	var per: float = Bal.v("squad/hp_per_member", 0.15)
	var steps: int = Sq.member_steps(game.squad.ops.size())
	ok(steps == game.squad.ops.size() - 1, "入队台阶：%d 人编队 %d 档" % [game.squad.ops.size(), steps])
	var found_mult := 0.0
	for m in game.stats._mods.get(&"max_hp", []):
		if str(m.get("source", "")) == "squad":
			found_mult = float(m.value)
	near(found_mult, 1.0 + per * steps, "最大生命入队倍率 1 + %d × %d%%" % [steps, int(per * 100)])
	var reg := 0.0
	for m in game.stats._mods.get(&"regen", []):
		if str(m.get("source", "")) == "squad":
			reg += float(m.value)
	near(reg, Sq.regen_bonus(steps), "生命回复入队加成 = 台阶合计")
	near(Sq.regen_bonus(1), Bal.v("squad/regen_per_member", 0.15), "第 1 名队友回复台阶")
	var gl: String = Intro.fill_numbers("生命 +{hp_per_member}%，回复 +{regen_per_member}")
	ok(gl.contains(str(int(round(per * 100)))) and gl.contains(Sq._num(Sq.regen_step(1))), "指南入队数字读旋钮：%s" % gl)
	# 实际每秒回复 = (回复 + 百分比 × 最大生命) × 治疗倍率（combat.regen_per_sec 同式）
	near(game.combat.regen_per_sec(), (game.regen + game.regen_pct * game.max_hp) * game.heal_mult * game.combat.song_heal_mult(), "每秒回复公式")


# ---------------------------------------------------------------- F
func test_guide_numbers() -> void:
	var gd: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/guide.json"))
	var all := ""
	for p in gd.get("pages", []):
		for k in ["lines", "more"]:
			for ln in p.get(k, []):
				all += Intro.fill_numbers(str(ln)) + "\n"
	ok(all.contains("+%d%%" % roundi(Bal.v("lamp/lit_bonus", 0.25) * 100.0)), "指南写出照亮加成 %d%%" % roundi(Bal.v("lamp/lit_bonus", 0.25) * 100.0))
	ok(all.contains("+%d%%" % roundi(Bal.v("lamp/lit_bonus_hi", 0.4) * 100.0)), "指南写出通明时照亮加成 %d%%" % roundi(Bal.v("lamp/lit_bonus_hi", 0.4) * 100.0))
	var per: int = roundi(Bal.v("relic/fuse_per", 15.0))
	var cap: int = roundi(Bal.v("relic/fuse_cap", 0.2) * 100.0)
	ok(all.contains("每 %d 枚 +%d%%" % [per, roundi(Bal.v("relic/fuse_pct", 0.01) * 100.0)]) and all.contains("上限 +%d%%" % cap), "指南熔铸写法与旋钮一致（每 %d 枚、上限 %d%%）" % [per, cap])
	ok(all.contains("低于 %d%%" % roundi(Bal.v("command/retreat_hp", 0.3) * 100.0)), "指南撤回线与 command/retreat_hp 一致")


# ---------------------------------------------------------------- G
func _nums(t: String) -> Array:
	var out: Array = []
	var re := RegEx.create_from_string("-?\\d+(?:\\.\\d+)?")
	for m in re.search_all(t):
		out.append(float(m.get_string()))
	return out


func test_growth_preview() -> void:
	var D = game.doctor
	var cnt := 0
	for pid in D.PASSIVES:
		var c: Dictionary = D.PASSIVES[pid]
		if not c.has("stat"):
			continue
		var pv0: String = D.passive_preview(pid)
		if not pv0.contains("→"):
			continue
		var a: Array = _nums(pv0.get_slice("→", 1))
		if a.is_empty():
			continue
		D.apply_passive(pid)
		var pv1: String = D.passive_preview(pid)
		var b: Array = _nums(pv1.get_slice("→", 0))
		cnt += 1
		ok(not b.is_empty() and absf(float(b[b.size() - 1]) - float(a[0])) <= 0.011 + 0.006 * absf(float(a[0])),
			"升级卡 %s：选中前写「%s」，选中后现值是「%s」" % [pid, pv0, pv1])
		game.stats.remove_source("growth:" + pid)
		game.sync_stats()
	ok(cnt >= 10, "升级卡预览样本 %d 张" % cnt)
