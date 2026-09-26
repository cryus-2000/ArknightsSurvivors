extends Node
## 主控保护脚本测试（docs/38 §1.11、B0 验收）：godot --headless --path game res://tests/prot_test.tscn -- --balance --seed=1 --op=wisadel
## 把 game.tscn 当子节点跑起来，第 5 帧直接调用 combat 的扣血入口，逐条检查 Boss 来源的扣血截断：
##   骨血 + 灯火 20 下 Boss 单发 ≤40%；带侵蚀的招式「扣血 + 追加侵蚀」≤40%；连发 2 秒合计 ≤50%；满血吃连击不死；
##   Boss 在场时 Boss 侵蚀 / Boss 溟痕每秒 ≤4%；非 Boss 来源（小怪、自然溟痕、普通侵蚀）不受影响。
## 全部通过时打印 "PROT TESTS PASSED"。

const Bal = preload("res://scripts/core/balance.gd")
const EPS := 0.0001

var game: Node
var c   # game.combat
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
	c = game.combat
	# 放一只真的 Boss 在远处（「Boss 在场」），整个测试期间它不动：直接调结算函数，不推进游戏帧
	var b: Dictionary = game.spawner.spawn_enemy("knight_boss", game.ppos + Vector2(2000, 0))
	game.bosses.append(b)
	test_hit_cap()
	test_corrode_budget()
	test_2s_cap()
	test_combo()
	test_guard_knobs()
	test_dot_cap()
	test_non_boss()
	b.dead = true
	print("%d checks, %d failed" % [n, fails])
	if fails == 0:
		print("PROT TESTS PASSED")
	get_tree().quit(1 if fails > 0 else 0)


func ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		fails += 1
		printerr("FAIL: ", what)


func pct(v: float) -> String:
	return "%.1f%%" % (100.0 * v / game.max_hp)


## 每个用例前：满血、清空保护记账，时间往后拨 10 秒（2 秒窗口与每秒上限都清零）
func reset(bone := false, lamp := 100.0) -> void:
	game.t += 10.0
	game.hp = game.max_hp
	game.shield = 0
	game.corrode_pool = 0.0
	game.nerve = 0.0
	game.lamp = lamp
	game.mires.clear()
	game.shocks.clear()
	c.corrode_boss = 0.0
	c.boss_log.clear()
	c.dot_log.clear()
	c.guard_ready = 0.0
	if bone:
		game.rfx.rules["bone_blood"] = 1
	else:
		game.rfx.rules.erase("bone_blood")


## 一发 Boss 预警（和 boss_ai._warn_damage 同样的参数）；返回这一发扣掉的生命
func boss_hit(dmg: float, kind := "物理", corrode := 0.0) -> float:
	var hp0: float = game.hp
	game.dmg_src = "boss_test"
	game.in_type = ["近战", kind]
	c.enemy_hit(dmg, {"corrode": corrode, "boss": true}, false, true)
	return hp0 - game.hp


## 骨血（受到伤害 ×1.8）+ 灯火 20（×1.15）下，Boss 单发扣血仍 ≤40%
func test_hit_cap() -> void:
	var cap: float = 0.4 * game.max_hp
	for kind in ["物理", "法术", "真实"]:
		for mul in [0.1, 0.3, 1.0, 5.0]:
			reset(true, 20.0)
			var lost := boss_hit(game.max_hp * mul, kind)
			ok(lost <= cap + EPS, "骨血 + 灯火 20：Boss 单发（%s，面板 %d%%）扣 %s，应 ≤40%%" % [kind, int(mul * 100), pct(lost)])
	reset(true, 20.0)
	ok(absf(boss_hit(game.max_hp * 0.3) - cap) < EPS, "骨血 + 灯火 20：面板 30% 的 Boss 一击（实际约 62%）截到正好 40%")
	# 对照：同一击不是 Boss 来源时不截断
	reset(true, 20.0)
	var hp0: float = game.hp
	game.dmg_src = "contact_test"
	game.in_type = ["近战", "物理"]
	c.enemy_hit(game.max_hp * 0.3, {}, false, true)
	ok(hp0 - game.hp > cap + 1.0, "非 Boss 来源不截断（扣 %s）" % pct(hp0 - game.hp))
	reset()


## 带侵蚀的 Boss 招式：这一发扣的血 + 追加进侵蚀池的量 ≤40%
func test_corrode_budget() -> void:
	var cap: float = 0.4 * game.max_hp
	for bone in [false, true]:
		for mul in [0.1, 0.2, 0.3, 1.0]:
			reset(bone, 20.0 if bone else 100.0)
			var lost := boss_hit(game.max_hp * mul, "物理", 0.5)
			var added: float = game.corrode_pool
			ok(lost + added <= cap + EPS, "corrode 0.5 的 Boss 招式（骨血 %s，面板 %d%%）：扣 %s + 侵蚀 %s，应 ≤40%%" % [bone, int(mul * 100), pct(lost), pct(added)])
			ok(absf(c.corrode_boss - added) < EPS, "追加的侵蚀全部记为 Boss 来源")
	# 额度没用完时照常追加：真实伤害、灯火 100，扣血 = 面板，侵蚀 = 扣血 × 0.5 × 2
	reset()
	var lost2 := boss_hit(game.max_hp * 0.1, "真实", 0.5)
	ok(lost2 > 0.0 and absf(game.corrode_pool - lost2 * 0.5 * Bal.v("enemy/corrode_mult", 2.0) * game.corrode_taken_mult) < EPS, "额度内的侵蚀照常追加（扣 %s，侵蚀 %s）" % [pct(lost2), pct(game.corrode_pool)])
	# 池里的 Boss 侵蚀合计不超过 40%：连着几发都只扣到上限以内，侵蚀不会越攒越多
	for k in 6:
		game.t += 3.0
		boss_hit(game.max_hp * 0.1, "真实", 0.5)
	ok(c.corrode_boss <= 0.4 * game.max_hp + EPS, "池里的 Boss 侵蚀 ≤40%%（%s）" % pct(c.corrode_boss))
	reset()


## 连发：受击无敌 0.45 秒比连发间隔 0.6 秒短，每发都能打中；任意 2 秒合计 ≤50%，窗口滑过后恢复
func test_2s_cap() -> void:
	reset(true, 20.0)
	var tot := 0.0
	for k in 3:
		tot += boss_hit(game.max_hp)
		game.t += 0.6
	ok(tot <= 0.5 * game.max_hp + EPS, "三连发 2 秒合计 %s，应 ≤50%%" % pct(tot))
	ok(absf(tot - 0.5 * game.max_hp) < EPS, "三连发合计正好截到 50%%（%s）" % pct(tot))
	# 第一发之后 2.05 秒：它已滑出窗口，额度恢复 40%
	game.t += 0.25
	var l4 := boss_hit(game.max_hp)
	ok(l4 > 0.3 * game.max_hp, "窗口滑过后 Boss 伤害重新生效（%s）" % pct(l4))
	# Boss 侵蚀结算也算进 2 秒合计：窗口已满时结算作废
	reset()
	boss_hit(game.max_hp)
	game.t += 0.1
	boss_hit(game.max_hp)   # 窗口里已有 50%
	game.corrode_pool = 40.0
	c.corrode_boss = 40.0
	var hp0: float = game.hp
	for k in 30:
		game.t += 1.0 / 60.0
		game.enemies_sys.update_status(1.0 / 60.0)
	ok(absf(game.hp - hp0) < EPS, "2 秒窗口已满时 Boss 侵蚀结算作废（扣 %s）" % pct(hp0 - game.hp))
	reset()


## 满血吃脚本连击不死
func test_combo() -> void:
	# 纯 Boss 连击：0.4 秒一发，共 5 发，全部远超上限
	reset(true, 20.0)
	for k in 5:
		boss_hit(game.max_hp * 2.0, "物理", 0.5)
		game.t += 0.4
	ok(game.hp >= 0.5 * game.max_hp - EPS, "满血吃 5 连击后生命 %s，应 ≥50%%" % pct(game.hp))
	ok(c.corrode_boss <= 0.4 * game.max_hp + EPS, "连击追加的 Boss 侵蚀 ≤40%%（%s）" % pct(c.corrode_boss))
	# 接着让侵蚀在 Boss 在场时流 3 秒：任意 2 秒 Boss 来源合计仍 ≤50%，人还活着
	var hp_a: float = game.hp
	for k in 180:
		game.t += 1.0 / 60.0
		game.enemies_sys.update_status(1.0 / 60.0)
	ok(game.hp > 0.0 and hp_a - game.hp <= 0.04 * 3.0 * game.max_hp + EPS, "连击后的 Boss 侵蚀按每秒 4%% 流出（3 秒扣 %s）" % pct(hp_a - game.hp))
	# 混合连击：Boss 一击 → 小怪补 45%（不受保护）→ Boss 再打，满血保护兜底到 10%
	reset(true, 20.0)
	boss_hit(game.max_hp * 2.0)
	c.lose_hp(game.max_hp * 0.45, "contact_test")
	game.t += 0.6
	boss_hit(game.max_hp * 2.0)
	ok(absf(game.hp - 0.1 * game.max_hp) < EPS, "满血保护：连击开始前满血，Boss 伤害最多打到剩 10%%（现在 %s）" % pct(game.hp))
	ok(c.guard_ready > game.t, "满血保护进入 30 秒冷却")
	for k in 2:   # 连击其余两发（第一发之后 1.2、1.8 秒，都还在同一个 2 秒窗口里）
		game.t += 0.6
		boss_hit(game.max_hp * 2.0)
	ok(game.hp > 0.0, "满血吃混合连击不死（剩 %s）" % pct(game.hp))
	reset()


## 满血保护按字面也成立：把单发 / 2 秒上限临时调到 100%（Bal.v 旋钮），生命 ≥90% 时一击最多打到剩 10%，30 秒一次
func test_guard_knobs() -> void:
	Bal.v("boss/leader_hit_cap", 0.4)   # 确保 balance.json 已读入
	var had: bool = Bal._data.has("boss")
	var old = Bal._data.get("boss")
	var sec: Dictionary = (old as Dictionary).duplicate() if old is Dictionary else {}
	sec["leader_hit_cap"] = 1.0
	sec["leader_2s_cap"] = 1.0
	Bal._data["boss"] = sec
	reset()
	game.hp = game.max_hp * 0.95
	boss_hit(game.max_hp * 5.0, "真实")
	ok(absf(game.hp - 0.1 * game.max_hp) < EPS, "生命 95%% 吃一记必杀，剩 %s（应为 10%%）" % pct(game.hp))
	game.t += 5.0
	game.hp = game.max_hp
	boss_hit(game.max_hp * 5.0, "真实")
	ok(game.hp <= 0.0, "30 秒冷却内不再保护")
	game.t += 30.0
	game.hp = game.max_hp
	c.boss_log.clear()
	boss_hit(game.max_hp * 5.0, "真实")
	ok(absf(game.hp - 0.1 * game.max_hp) < EPS, "冷却结束后再次保护")
	reset()
	game.hp = game.max_hp * 0.85
	boss_hit(game.max_hp * 5.0, "真实")
	ok(game.hp <= 0.0, "受击前生命 <90% 时不触发满血保护")
	if had:
		Bal._data["boss"] = old
	else:
		Bal._data.erase("boss")
	reset()


## Boss 在场时，Boss 带来的持续伤害（Boss 侵蚀 + Boss 溟痕）任意 1 秒 ≤4%
func test_dot_cap() -> void:
	var dt := 1.0 / 60.0
	var cap_s: float = 0.04 * game.max_hp
	# Boss 侵蚀：池子里放 60% 的 Boss 侵蚀，逐帧结算 3 秒，每秒扣血 ≤4%，没流出的留在池里
	reset()
	game.corrode_pool = 0.6 * game.max_hp
	c.corrode_boss = game.corrode_pool
	var worst := 0.0
	for sec in 3:
		var hp0: float = game.hp
		for k in 60:
			game.t += dt
			game.enemies_sys.update_status(dt)
		worst = maxf(worst, hp0 - game.hp)
	ok(worst <= cap_s + EPS, "Boss 侵蚀每秒最多扣 %s，应 ≤4%%" % pct(worst))
	ok(worst > cap_s * 0.9, "Boss 侵蚀按上限持续流出（每秒 %s）" % pct(worst))
	ok(game.corrode_pool > 0.4 * game.max_hp, "流不出去的侵蚀留在池里（剩 %s）" % pct(game.corrode_pool))
	# Boss 溟痕（Boss 子弹留下的）：每 0.5 秒一跳，合计每秒 ≤4%
	reset()
	game.mires.append({"pos": game.ppos, "r": 80.0, "maxr": 80.0, "life": 9.0, "seed": 0.0, "boss": true})
	game.enemies_sys.mire_tick = 0.0
	worst = 0.0
	for sec in 3:
		var hp1: float = game.hp
		for k in 60:
			game.t += dt
			game.enemies_sys.update_status(dt)
		worst = maxf(worst, hp1 - game.hp)
	ok(worst <= cap_s + EPS, "Boss 溟痕每秒最多扣 %s，应 ≤4%%" % pct(worst))
	reset()


## 非 Boss 来源不受影响：普通侵蚀照原公式流出、自然溟痕照原数值结算
func test_non_boss() -> void:
	var dt := 1.0 / 60.0
	reset()
	game.corrode_pool = 0.6 * game.max_hp
	var pool0: float = game.corrode_pool
	var hp0: float = game.hp
	game.enemies_sys.update_status(dt)
	var tick: float = minf(pool0, (pool0 * 0.5 + 1.0) * dt)
	ok(absf((hp0 - game.hp) - tick) < EPS, "普通侵蚀照原公式流出")
	reset()
	game.mires.append({"pos": game.ppos, "r": 80.0, "maxr": 80.0, "life": 9.0, "seed": 0.0})
	game.enemies_sys.mire_tick = 0.0
	hp0 = game.hp
	game.enemies_sys.update_status(dt)
	ok(absf((hp0 - game.hp) - (3.0 + game.max_hp * 0.015)) < EPS, "自然溟痕照原数值结算（%s）" % pct(hp0 - game.hp))
	reset()
