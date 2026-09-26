extends Node
## 主控保护脚本测试（docs/38 §1.11、B0 验收）：godot --headless --path game res://tests/prot_test.tscn -- --balance --seed=1 --op=wisadel
## 把 game.tscn 当子节点跑起来，第 5 帧直接调用 combat 的扣血入口，逐条检查 Boss 来源的扣血截断：
##   骨血 + 灯火 20 下 Boss 单发 ≤40%；带侵蚀的招式「扣血 + 追加侵蚀」≤40%；连发 2 秒合计 ≤50%（「扣血 + 追加的侵蚀」和
##   「实际扣血，含 Boss 侵蚀结算」两种口径都成立，窗口满时追加的侵蚀也作废）；满血吃连击（含带侵蚀的、夹小怪伤害的）不死，
##   满血保护只兜这一轮连击（2 秒），不会整场都在；Boss 在场时 Boss 侵蚀 / Boss 溟痕每秒 ≤4%；
##   非 Boss 来源（小怪、自然溟痕、普通侵蚀，含流明净化之后的）不受影响。
## 永不硬控（B0-2）：Boss 存活期间预警僵直 / 冲击环 / 神经损伤溢出都换成 0.5 秒 −30% 减速，主控僵直恒为 0；没有 Boss 时照旧僵直；
##   僵直中也能冲刺（方向取按住的方向）。
## 攻速 / 移速下限（B0-3）：Boss 来源和 Boss 存活期间不写 atk_slow（预警、带 slow 的子弹、神经损伤溢出），改成等量移速减速；
##   Boss 存活期间移速倍率不低于 0.7，没有 Boss 时照旧相乘。
## 全部通过时打印 "PROT TESTS PASSED"。

const Bal = preload("res://scripts/core/balance.gd")
const Game = preload("res://scripts/game.gd")
const EPS := 0.0001

var game: Node
var c   # game.combat
var frames := 0
var n := 0
var fails := 0
var last_add := 0.0   # boss_hit 这一发追加进侵蚀池的量
var boss_e: Dictionary   # 测试期间一直在场的 Boss


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
	boss_e = b
	test_hit_cap()
	test_corrode_budget()
	test_2s_cap()
	test_combo()
	test_guard_knobs()
	test_dot_cap()
	test_non_boss()
	test_no_hard_cc()
	test_atk_slow_floor()
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
	c.loss_log.clear()
	c.dot_log.clear()
	c.guard_ready = 0.0
	c.guard_end = -INF
	c.high_t = -INF
	c.slows.clear()
	game.pstun = 0.0
	game.atk_slow = 0.0
	if bone:
		game.rfx.rules["bone_blood"] = 1
	else:
		game.rfx.rules.erase("bone_blood")


## 一发 Boss 预警（和 boss_ai._warn_damage 同样的参数）；返回这一发扣掉的生命，追加进侵蚀池的量记在 last_add
func boss_hit(dmg: float, kind := "物理", corrode := 0.0) -> float:
	var hp0: float = game.hp
	var pool0: float = game.corrode_pool
	game.dmg_src = "boss_test"
	game.in_type = ["近战", kind]
	c.enemy_hit(dmg, {"corrode": corrode, "boss": true}, false, true)
	last_add = game.corrode_pool - pool0
	return hp0 - game.hp


## 小怪一击（不受主控保护）
func minion_hit(frac: float) -> void:
	c.lose_hp(game.max_hp * frac, "contact_test")


## 逐帧推进 sec 秒的持续状态（侵蚀结算、溟痕）
func run(sec: float) -> void:
	var dt := 1.0 / 60.0
	for k in int(round(sec * 60.0)):
		game.t += dt
		game.enemies_sys.update_status(dt)


## 临时改 boss/* 旋钮（Bal.v 读的 _data），返回旧值给 restore_knobs
func set_knobs(kv: Dictionary) -> Array:
	Bal.v("boss/leader_hit_cap", 0.4)   # 确保 balance.json 已读入
	var had: bool = Bal._data.has("boss")
	var old = Bal._data.get("boss")
	var sec: Dictionary = (old as Dictionary).duplicate() if old is Dictionary else {}
	sec.merge(kv, true)
	Bal._data["boss"] = sec
	return [had, old]


func restore_knobs(saved: Array) -> void:
	if saved[0]:
		Bal._data["boss"] = saved[1]
	else:
		Bal._data.erase("boss")


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
	# 追加的侵蚀也计入 2 秒合计（docs/38「含追加的侵蚀，超出作废」）：窗口满了，这一发带侵蚀的招式扣血和侵蚀都作废
	reset()
	boss_hit(game.max_hp)
	game.t += 0.1
	boss_hit(game.max_hp)
	game.t += 0.5
	var l3 := boss_hit(game.max_hp * 0.1, "真实", 0.5)
	ok(l3 < EPS and last_add < EPS, "2 秒窗口已满：Boss 招式扣血 %s、追加侵蚀 %s，都应作废" % [pct(l3), pct(last_add)])
	# 带侵蚀的连发，中间逐帧结算侵蚀：「扣血 + 追加的侵蚀」2 秒合计 ≤50%
	reset()
	var hits := 0.0
	var adds := 0.0
	for k in 4:
		hits += boss_hit(game.max_hp * 0.12, "真实", 0.5)
		adds += last_add
		run(0.6)
	ok(adds > 0.0 and hits + adds <= 0.5 * game.max_hp + EPS, "带侵蚀的四连发：扣血 %s + 追加侵蚀 %s，2 秒合计应 ≤50%%" % [pct(hits), pct(adds)])
	# 实际扣血口径：池里已有 40% 的旧 Boss 侵蚀（2 秒窗口外追加的），2 秒内四连发 + 逐帧侵蚀结算，实际掉血 ≤50%
	reset()
	game.corrode_pool = 0.4 * game.max_hp
	c.corrode_boss = game.corrode_pool
	hp0 = game.hp
	for k in 4:
		boss_hit(game.max_hp, "真实")
		run(0.45)   # 4 发共 1.8 秒，都在同一个 2 秒窗口里
	ok(hp0 - game.hp <= 0.5 * game.max_hp + EPS, "Boss 连发 + Boss 侵蚀结算，2 秒实际掉血 %s，应 ≤50%%" % pct(hp0 - game.hp))
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
	# 带侵蚀的连击（corrode 0.5，每发都追加侵蚀），之后 Boss 不再出手、侵蚀在 Boss 在场时流完：生命仍 ≥50%
	reset()
	for k in 4:
		boss_hit(game.max_hp * 0.12, "真实", 0.5)
		run(0.6)
	ok(c.corrode_boss > 0.0, "连击追加了 Boss 侵蚀（%s）" % pct(c.corrode_boss))
	run(20.0)
	ok(game.hp >= 0.5 * game.max_hp - EPS, "满血吃带侵蚀的连击，侵蚀流完后生命 %s，应 ≥50%%" % pct(game.hp))
	# 混合连击：Boss 一击 → 小怪补 45%（不受保护）→ Boss 再打，满血保护兜底到 10%
	reset(true, 20.0)
	boss_hit(game.max_hp * 2.0)
	minion_hit(0.45)
	game.t += 0.6
	boss_hit(game.max_hp * 2.0)
	ok(absf(game.hp - 0.1 * game.max_hp) < EPS, "满血保护：连击开始前满血，Boss 伤害最多打到剩 10%%（现在 %s）" % pct(game.hp))
	ok(c.guard_ready > game.t, "满血保护进入 30 秒冷却")
	for k in 2:   # 连击其余两发（第一发之后 1.2、1.8 秒，都还在同一个 2 秒窗口里）
		game.t += 0.6
		boss_hit(game.max_hp * 2.0)
	ok(game.hp > 0.0, "满血吃混合连击不死（剩 %s）" % pct(game.hp))
	# 混合连击 + 侵蚀：保护兜底时把池里待流出的 Boss 侵蚀算进去，侵蚀流完仍 ≥10%
	reset()
	boss_hit(game.max_hp * 0.12, "真实", 0.5)
	minion_hit(0.45)
	for k in 2:
		game.t += 0.6
		boss_hit(game.max_hp * 0.12, "真实", 0.5)
	ok(c.guard_ready > game.t, "带侵蚀的混合连击触发了满血保护")
	ok(game.hp - c.corrode_boss >= 0.1 * game.max_hp - EPS, "满血保护算上池里的 Boss 侵蚀：生命 %s − Boss 侵蚀 %s 应 ≥10%%" % [pct(game.hp), pct(c.corrode_boss)])
	run(20.0)
	ok(game.hp >= 0.1 * game.max_hp - EPS, "带侵蚀的混合连击，侵蚀流完后生命 %s，应 ≥10%%" % pct(game.hp))
	# 满血保护只兜「生命 ≥90% 之后 2 秒」这一轮连击：满血开打后 Boss 每 1.5 秒打一发 5%，21 秒后生命 30%，
	# 这时 Boss 一击 40% 不再被兜底（按字面规则：受击前生命 30%，不触发）
	reset()
	for k in 14:
		game.lamp = 100.0   # 灯火保持 ≥30，不吃 ×1.15
		boss_hit(game.max_hp * 0.05, "真实")
		game.t += 1.5
	ok(absf(game.hp - 0.3 * game.max_hp) < EPS, "14 发 5%% 后生命 %s（应 30%%）" % pct(game.hp))
	boss_hit(game.max_hp * 0.4, "真实")
	ok(game.hp <= 0.0 and c.guard_ready == 0.0, "开打时满血不等于整场免死：21 秒后这一击不触发满血保护（剩 %s）" % pct(game.hp))
	reset()


## 满血保护按字面也成立：把单发 / 2 秒上限临时调到 100%（Bal.v 旋钮），生命 ≥90% 时一击最多打到剩 10%，30 秒一次
func test_guard_knobs() -> void:
	var saved := set_knobs({"leader_hit_cap": 1.0, "leader_2s_cap": 1.0})
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
	c.loss_log.clear()
	boss_hit(game.max_hp * 5.0, "真实")
	ok(absf(game.hp - 0.1 * game.max_hp) < EPS, "冷却结束后再次保护")
	reset()
	game.hp = game.max_hp * 0.85
	boss_hit(game.max_hp * 5.0, "真实")
	ok(game.hp <= 0.0, "受击前生命 <90% 时不触发满血保护")
	restore_knobs(saved)
	# boss/fullhp_guard_combo = 0 即字面规则「受击前生命 ≥90%」：混合连击的第二发（受击前 15%）不兜底
	saved = set_knobs({"fullhp_guard_combo": 0.0})
	reset(true, 20.0)
	boss_hit(game.max_hp * 2.0)
	minion_hit(0.45)
	game.t += 0.6
	boss_hit(game.max_hp * 2.0)
	ok(game.hp < 0.1 * game.max_hp - EPS and c.guard_ready == 0.0, "fullhp_guard_combo = 0：按字面规则不触发（剩 %s）" % pct(game.hp))
	restore_knobs(saved)
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
	# 流明净化直接把侵蚀池清零（lumen.gd），之后小怪追加的侵蚀不能被当成 Boss 侵蚀（不受每秒上限、不进 2 秒合计）
	reset()
	game.corrode_pool = 0.06 * game.max_hp
	c.corrode_boss = game.corrode_pool
	game.corrode_pool = 0.0
	game.dmg_src = "contact_test"
	game.in_type = ["近战", "真实"]
	c.enemy_hit(game.max_hp * 0.05, {"corrode": 0.5}, false, true)
	ok(c.corrode_boss < EPS and game.corrode_pool > 0.0, "净化后小怪追加的侵蚀不算 Boss 的（Boss 部分 %s）" % pct(c.corrode_boss))
	pool0 = game.corrode_pool
	hp0 = game.hp
	game.enemies_sys.update_status(dt)
	tick = minf(pool0, (pool0 * 0.5 + 1.0) * dt)
	ok(absf((hp0 - game.hp) - tick) < EPS and c.loss_log.is_empty(), "净化后普通侵蚀照原公式流出、不进 Boss 的 2 秒合计")
	reset()
	game.mires.append({"pos": game.ppos, "r": 80.0, "maxr": 80.0, "life": 9.0, "seed": 0.0})
	game.enemies_sys.mire_tick = 0.0
	hp0 = game.hp
	game.enemies_sys.update_status(dt)
	ok(absf((hp0 - game.hp) - (3.0 + game.max_hp * 0.015)) < EPS, "自然溟痕照原数值结算（%s）" % pct(hp0 - game.hp))
	# 预警 / 冲击环系统精英也在用（钻地咬击、踏地震荡）：按放招的敌人是不是 Boss 决定截不截
	for is_boss in [false, true]:
		reset()
		game.invuln = 0.0
		var own := {"type": "burrower" if not is_boss else "path", "boss": is_boss}
		var w := {"shape": "circle", "pos": game.ppos + Vector2(0, -14), "r": 60.0, "owner": own, "act": "bite", "dmg": game.max_hp * 0.8, "corrode": 0.0}
		hp0 = game.hp
		game.bai._warn_damage(w)
		var lw: float = hp0 - game.hp
		ok((lw <= 0.4 * game.max_hp + EPS) == is_boss, "预警扣血（放招的%s Boss）扣 %s" % ["是" if is_boss else "不是", pct(lw)])
		reset()
		game.invuln = 0.0
		game.shocks.append({"pos": game.ppos, "r": 0.0, "maxr": 200.0, "dmg": game.max_hp * 0.8, "hit": false, "boss": is_boss})
		hp0 = game.hp
		game.enemies_sys.update_status(dt)
		var ls: float = hp0 - game.hp
		ok(ls > 0.0 and (ls <= 0.4 * game.max_hp + EPS) == is_boss, "冲击环扣血（放招的%s Boss）扣 %s" % ["是" if is_boss else "不是", pct(ls)])
	reset()


## 永不硬控（docs/38 §1.11，B0-2）：Boss 存活期间三处僵直都换成减速；没有 Boss 时照旧；僵直中也能冲刺
func test_no_hard_cc() -> void:
	var st: float = Bal.v("boss/stun_as_slow_t", 0.5)
	var sm: float = Bal.v("boss/stun_as_slow_mult", 0.7)
	for alive in [true, false]:
		boss_e.dead = not alive
		var tag: String = "Boss 存活" if alive else "没有 Boss"
		# 预警僵直：Boss 放的、精英放的（钻地咬击、踏地）
		for own_boss in [true, false]:
			if not alive and own_boss:
				continue   # 没有 Boss 存活时 Boss 的预警另测（见下）
			reset()
			game.invuln = 0.0
			var w := {"shape": "circle", "pos": game.ppos + Vector2(0, -14), "r": 60.0, "owner": {"type": "path" if own_boss else "burrower", "boss": own_boss},
				"act": "pillar", "dmg": 1.0, "corrode": 0.0}
			game.bai._warn_damage(w, 0.4)
			if alive:
				ok(game.pstun <= 0.0 and c.slows.has("stun"), "%s：预警僵直（%s放的）换成减速（僵直 %.2f）" % [tag, "Boss " if own_boss else "精英", game.pstun])
			else:
				ok(absf(game.pstun - 0.4) < EPS and c.slows.is_empty(), "%s：精英的预警照旧僵直 0.4 秒（%.2f）" % [tag, game.pstun])
		# 神经损伤溢出
		reset()
		game.invuln = 0.0
		game.nerve = 99.0
		c.add_nerve(5.0)
		if alive:
			ok(game.pstun <= 0.0 and c.slows.has("stun"), "%s：神经损伤溢出换成减速（僵直 %.2f）" % [tag, game.pstun])
		else:
			ok(absf(game.pstun - 0.4) < EPS, "%s：神经损伤溢出照旧僵直 0.4 秒（%.2f）" % [tag, game.pstun])
		# 冲击环（精英的踏地震荡；Boss 存活时 Boss 的冲击环）
		reset()
		game.invuln = 0.0
		game.shocks.append({"pos": game.ppos, "r": 0.0, "maxr": 200.0, "dmg": 1.0, "hit": false, "boss": alive})
		game.enemies_sys.update_status(1.0 / 60.0)
		if alive:
			ok(game.pstun <= 0.0 and c.slows.has("stun"), "%s：冲击环换成减速（僵直 %.2f）" % [tag, game.pstun])
		else:
			ok(game.pstun > 0.4, "%s：精英冲击环照旧僵直（%.2f）" % [tag, game.pstun])
	boss_e.dead = false
	# 减速的数值与时长：0.5 秒 × 0.7，同种重复吃到只刷新不叠乘，到时自动解除
	# （神经损伤溢出在 Boss 战里还会把攻速减缓换成另一种减速 "atk"（B0-3），这里只测僵直换来的 "stun"，先把 "atk" 去掉）
	reset()
	game.invuln = 0.0
	game.nerve = 99.0
	c.add_nerve(5.0)
	c.slows.erase("atk")
	ok(absf(c.move_mult(1.0) - sm) < EPS, "僵直换成的减速：移速 ×%.2f（应 ×%.2f）" % [c.move_mult(1.0), sm])
	game.nerve = 99.0
	c.add_nerve(5.0)
	c.slows.erase("atk")
	ok(absf(c.move_mult(1.0) - sm) < EPS, "同种减速重复吃到不叠乘（×%.2f）" % c.move_mult(1.0))
	run(st + 0.05)
	ok(c.slows.is_empty() and absf(c.move_mult(1.0) - 1.0) < EPS, "%.1f 秒后减速解除" % st)
	# Boss 已死、还在扩散的 Boss 冲击环：Boss 来源也不僵直
	boss_e.dead = true
	reset()
	game.invuln = 0.0
	game.shocks.append({"pos": game.ppos, "r": 0.0, "maxr": 200.0, "dmg": 1.0, "hit": false, "boss": true})
	game.enemies_sys.update_status(1.0 / 60.0)
	ok(game.pstun <= 0.0 and c.slows.has("stun"), "Boss 刚死时它的冲击环也只减速（僵直 %.2f）" % game.pstun)
	# Boss 出现前残留的僵直：Boss 一出现就换成减速，不算违规；Boss 战中有地方直接写 g.pstun：换掉并记违规
	reset()
	game.pstun = 0.3
	c.ctrl_boss = false
	boss_e.dead = false
	var stun0: float = c.ctrl.stun_t
	game.enemies_sys.update_status(1.0 / 60.0)
	ok(game.pstun <= 0.0 and c.ctrl.stun_t == stun0, "Boss 出现前残留的僵直直接换成减速、不记违规")
	game.pstun = 0.3
	game.enemies_sys.update_status(1.0 / 60.0)
	ok(game.pstun <= 0.0 and c.ctrl.stun_t > stun0, "Boss 战中直接写的僵直被换掉并记违规（%.3f 秒）" % (c.ctrl.stun_t - stun0))
	c.ctrl.stun_t = stun0
	# 冲刺不查僵直：僵直中照样能冲，方向取按住的方向
	reset()
	var st0: int = game.state
	game.state = Game.S.PLAY
	game.pstun = 0.4
	game.dash_cd = 0.0
	game.dash_t = 0.0
	game.move_in = Vector2(0, 1)
	game._try_dash()
	ok(game.dash_t > 0.0 and game.dash_dir.is_equal_approx(Vector2(0, 1)), "僵直中能冲刺，方向取按住的方向（dash_t %.2f，方向 %s）" % [game.dash_t, str(game.dash_dir)])
	game.dash_t = 0.0
	game._try_dash()
	ok(game.dash_t <= 0.0, "冷却中不能冲刺")
	game.dash_cd = 0.0
	game.dash_t = 0.0
	game.state = st0
	reset()


## 一颗贴脸的敌方子弹（和 boss_ai「bring」/ enemy_ai 的字段一致），逐帧结算一次
func slow_bullet(boss: bool) -> void:
	game.ebullets.clear()
	game.ebullets.append({"pos": game.ppos + Vector2(0, -14), "vel": Vector2.ZERO, "dmg": 1.0, "slow": true, "r": 7.0, "life": 3.0,
		"corrode": 0.0, "nerve": 0.0, "true": false, "kind": "ebullet", "home": false, "boss": boss})
	game.enemies_sys.update_ebullets(1.0 / 60.0)
	game.ebullets.clear()


## 攻速（docs/38 §1.11，B0-3）：Boss 来源 / Boss 存活期间不写 atk_slow，改成等量移速减速；Boss 存活期间移速倍率 ≥0.7
func test_atk_slow_floor() -> void:
	var am: float = Bal.v("boss/atk_slow_as_slow_mult", 0.67)
	var fl: float = Bal.v("boss/move_floor", 0.7)
	for alive in [true, false]:
		boss_e.dead = not alive
		var tag: String = "Boss 存活" if alive else "没有 Boss"
		# 带减攻速的预警（泡影凝视等）：Boss 存活时连精英放的也不写
		reset()
		game.invuln = 0.0
		var w := {"shape": "circle", "pos": game.ppos + Vector2(0, -14), "r": 60.0, "owner": {"type": "burrower", "boss": false},
			"act": "gaze", "dmg": 1.0, "corrode": 0.0}
		game.bai._warn_damage(w, 0.0, true)
		if alive:
			ok(game.atk_slow <= 0.0 and c.slows.has("atk") and absf(float(c.slows["atk"][0]) - 3.0) < EPS, "%s：减攻速预警换成 3 秒移速减速（atk_slow %.2f）" % [tag, game.atk_slow])
		else:
			ok(absf(game.atk_slow - 3.0) < EPS and c.slows.is_empty(), "%s：精英的减攻速预警照旧（atk_slow %.2f）" % [tag, game.atk_slow])
		# 神经损伤溢出
		reset()
		game.invuln = 0.0
		game.nerve = 99.0
		c.add_nerve(5.0)
		if alive:
			ok(game.atk_slow <= 0.0 and c.slows.has("atk") and absf(float(c.slows["atk"][0]) - 2.5) < EPS, "%s：神经损伤溢出不写 atk_slow，换成 2.5 秒减速" % tag)
		else:
			ok(absf(game.atk_slow - 2.5) < EPS, "%s：神经损伤溢出照旧 atk_slow 2.5（%.2f）" % [tag, game.atk_slow])
		# 带 slow 的子弹：Boss 的（任何时候都不写）和不是 Boss 的
		for bb in [true, false]:
			reset()
			game.invuln = 0.0
			slow_bullet(bb)
			if alive or bb:
				ok(game.atk_slow <= 0.0 and c.slows.has("atk"), "%s：%s的减速子弹不写 atk_slow（%.2f）" % [tag, "Boss " if bb else "小怪", game.atk_slow])
			else:
				ok(absf(game.atk_slow - 3.0) < EPS, "%s：小怪的减速子弹照旧 atk_slow 3（%.2f）" % [tag, game.atk_slow])
	# 移速下限：溟痕 ×0.55、冰霜 ×0.6、僵直换来的 ×0.7、攻速减缓换来的 ×0.67 同时吃到
	var raw: float = 0.55 * 0.6
	reset()
	c.slow_leader("stun", 0.5, Bal.v("boss/stun_as_slow_mult", 0.7))
	c.slow_leader("atk", 3.0, am)
	boss_e.dead = true
	var prod: float = raw * Bal.v("boss/stun_as_slow_mult", 0.7) * am
	ok(absf(c.move_mult(raw) - prod) < EPS, "没有 Boss：减速照旧相乘（×%.3f）" % c.move_mult(raw))
	boss_e.dead = false
	ok(absf(c.move_mult(raw) - fl) < EPS, "Boss 存活：移速倍率被下限兜住（×%.3f，应 ×%.2f）" % [c.move_mult(raw), fl])
	ok(absf(c.move_mult(1.0) - fl) < EPS and absf(c.move_mult(0.9 / (Bal.v("boss/stun_as_slow_mult", 0.7) * am)) - 0.9) < EPS, "Boss 存活：高于下限时照常（×%.3f）" % c.move_mult(1.0))
	ok(c.ctrl.move_min >= fl - EPS and c.ctrl.slow_min <= prod + EPS, "验收计数：move_min %.3f ≥ %.2f，slow_min %.3f" % [c.ctrl.move_min, fl, c.ctrl.slow_min])
	# Boss 出现前残留的 atk_slow：Boss 一出现就换成减速，不算违规；Boss 战中直接写的：换掉并记违规
	reset()
	game.atk_slow = 1.5
	c.ctrl_boss = false
	var as0: float = c.ctrl.aslow_t
	game.enemies_sys.update_status(1.0 / 60.0)
	ok(game.atk_slow <= 0.0 and c.slows.has("atk") and c.ctrl.aslow_t == as0, "Boss 出现前残留的 atk_slow 换成减速、不记违规")
	game.atk_slow = 1.0
	game.enemies_sys.update_status(1.0 / 60.0)
	ok(game.atk_slow <= 0.0 and c.ctrl.aslow_t > as0, "Boss 战中直接写的 atk_slow 被换掉并记违规")
	c.ctrl.aslow_t = as0
	reset()
