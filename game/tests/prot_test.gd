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
## 大群混编（EA 1.1）：data/waves.json 每套 horde_mix 展开后位数、主体占比、敌人 ID 合法，编成随机抽且不连续重复。
## V8 新敌人：自爆、休眠伏兵、厚甲、神经弹、神经光环的行为冒烟。
## Boss 阶段卡点（B1 ①）：截在刻度、护盾、满时长过卡点、过卡点短暂不受伤。
## 破绽 ×1.4、韧性与眩晕钩子（白名单 Boss）、伤害预算（默认关）（B1 ③④）。
## 最终 Boss 登场时残留中期 Boss 撤场不给奖励（B1 ②）。
## 最终 Boss 场地（B1 第二批）：冻结、插值、主控离圈边 ≥100、位置约束。
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
	# 测试期间把「全局」保护旋钮按代码缺省（关）来测：balance.json 里数值打开的通用 2 秒上限 / 非 Boss 侵蚀池上限
	# 会改变 Boss 保护各用例的期望值；只在 test_any_cap 里临时打开。测完还原（数值 9/27 收口轮发现）
	var bal_bak: Dictionary = Bal._data.duplicate(true)
	Bal._data["protect"] = {}
	if Bal._data.has("enemy"):
		Bal._data["enemy"].erase("corrode_pool_cap")
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
	test_beacon_decay()
	test_xp_recall()
	test_atk_slow_floor()
	test_horde_mix()
	test_v8()
	test_gates()
	test_break_budget()
	test_retreat()
	test_final_mob_cap()
	test_ishar_close()
	test_paranoia_p2_gate()
	test_close_panic()
	test_enemy_knob()
	test_beacon_safe()
	test_saint_tiers()
	test_arena()
	test_ground()
	test_warn_style()
	test_any_cap()
	test_ailments()
	test_saria_cleanse()
	test_lore1()
	test_lore2()
	test_lore3()
	test_lore4()
	test_lore5()
	test_nerve()
	test_floater_mire()
	Bal._data = bal_bak
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
	# 骑士骨血的主控受伤 ×1.8 只在骑士在队时生效（事件验收 P1-4，relic_fx.taken_mult），测骨血时让骑士在队
	game.knight_alive = bone
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
		var own := {"type": "slider" if not is_boss else "path", "boss": is_boss}
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
			var w := {"shape": "circle", "pos": game.ppos + Vector2(0, -14), "r": 60.0, "owner": {"type": "path" if own_boss else "slider", "boss": own_boss},
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
		game.nerve_lock = 0.0
		game.root_t = 0.0
		game.root_immune = 0.0
		c.add_nerve(5.0)
		if alive:
			ok(game.pstun <= 0.0 and game.root_t <= 0.0 and c.slows.has("stun"), "%s：神经损伤满格换成减速（僵直 %.2f）" % [tag, game.pstun])
		else:
			ok(game.root_t > 0.0 and game.pstun <= 0.0, "%s：神经损伤满格眩晕 %.1f 秒（按硬控规则，冲刺可挣脱）" % [tag, game.root_t])
		game.root_t = 0.0
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
	game.nerve_lock = 0.0
	c.add_nerve(5.0)
	c.slows.erase("atk")
	ok(absf(c.move_mult(1.0) - sm) < EPS, "僵直换成的减速：移速 ×%.2f（应 ×%.2f）" % [c.move_mult(1.0), sm])
	game.nerve = 99.0
	game.nerve_lock = 0.0
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
		var w := {"shape": "circle", "pos": game.ppos + Vector2(0, -14), "r": 60.0, "owner": {"type": "slider", "boss": false},
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
		game.nerve_lock = 0.0
		game.root_immune = 0.0
		c.add_nerve(5.0)
		ok(game.atk_slow <= 0.0 and not c.slows.has("atk"), "%s：神经损伤满格不再减攻速（用户 9/29 按原作改为真伤 + 眩晕）" % tag)
		game.root_t = 0.0
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


## 大群混编（EA 1.1，data/waves.json horde_mix）：每个威胁等级的每套编成展开后刷怪位数 = n、特种不超过一半、
## 敌人 ID 都存在、位置在包围圈 0–1 之内；随机抽编成但不连续重复
func test_horde_mix() -> void:
	var D = preload("res://scripts/data.gd")
	var sp = game.spawner
	var th0: int = game.threat
	for ti in D.THREAT.size():
		game.threat = ti
		var mixes: Array = D.THREAT[ti].get("horde_mix", [])
		ok(not mixes.is_empty(), "威胁等级 %s 写了 horde_mix" % D.THREAT[ti].name)
		for m in mixes:
			for nn in [20, 44, 90]:
				var plan: Array = sp.horde_plan(m, nn)
				var body_n := 0
				var bad := ""
				for s in plan:
					if not D.ENEMIES.has(s.id):
						bad = s.id
					if float(s.u) < 0.0 or float(s.u) > 1.0:
						bad = "u=%s" % s.u
					if m.body.has(s.id) and float(s.dr) == 0.0:
						body_n += 1
				ok(plan.size() == nn and body_n >= nn - nn / 2 and bad == "", "大群「%s」n=%d：%d 个位、主体 ≥ 一半（%d）、ID / 位置合法 %s" % [m.name, nn, plan.size(), body_n, bad])
	# 随机抽编成，但不连着来两次同一套：上一次大群是某套时，这次一定换另一套
	game.threat = 1
	var hl0: Array = game.horde_log.duplicate()
	var rep := 0
	for k in 40:
		var last: String = D.THREAT[1].horde_mix[k % 2].name
		game.horde_log = [{"mix": last}]
		if sp.horde_mix().name == last:
			rep += 1
	ok(rep == 0, "大群编成不连续重复（40 次里重复 %d 次）" % rep)
	game.horde_log = hl0
	game.threat = th0


## V8 新敌人（enemy_ai.gd）：自爆、休眠伏兵、厚甲、神经弹、神经光环的行为冒烟
func test_v8() -> void:
	var sp = game.spawner
	var ai = game.eai
	var dt := 0.1
	# 壳海狂奔者：进入 blast_range 后鼓胀，blast_fuse 后自爆消失
	var ru: Dictionary = sp.spawn_enemy("runner", game.ppos + Vector2(30, 0))
	ai.pattern(ru, Vector2.LEFT, 30.0, dt, ru.spd)
	ok(ru.blast_w > 0.0 and not ru.dead, "狂奔者进入范围开始鼓胀（%.2f 秒）" % ru.blast_w)
	for k in 12:
		if not ru.dead:
			ai.pattern(ru, Vector2.LEFT, 30.0, dt, ru.spd)
	ok(ru.dead, "狂奔者鼓胀结束后自爆消失")
	# 钵海收割者：屏幕外刷出改放到主控附近休眠；主控不靠近不醒，受伤就醒
	var re: Dictionary = sp.spawn_enemy("reaper", game.ppos + Vector2(1500, 0))
	var rd: float = re.pos.distance_to(game.ppos)
	ok(re.dormant and rd >= 300.0 and rd <= 520.0, "收割者休眠伏在主控附近（%.0f）" % rd)
	ai.pattern(re, Vector2.LEFT, rd, dt, re.spd)
	ok(re.dormant, "主控在唤醒半径外：继续休眠")
	re.hp -= 1.0
	ai.pattern(re, Vector2.LEFT, rd, dt, re.spd)
	ok(not re.dormant and re.wake_t > 0.0, "受到伤害后唤醒")
	re.dead = true
	# 深溟奠基者：厚甲（def = armor）
	var fo: Dictionary = sp.spawn_enemy("founder", game.ppos + Vector2(900, 0))
	ok(absf(fo.def - 0.7) < EPS, "奠基者厚甲 def 0.7（%.2f）" % fo.def)
	fo.dead = true
	# 浮海飘航者：神经弹带神经损伤
	var fl: Dictionary = sp.spawn_enemy("floater", game.ppos + Vector2(200, 0))
	ai.shoot(fl, Vector2.LEFT)
	var lb: Dictionary = game.ebullets[game.ebullets.size() - 1]
	ok(lb.kind == "nerve" and lb.nerve > 0.0, "飘航者神经弹（nerve %.0f）" % lb.nerve)
	lb.life = 0.0
	fl.dead = true
	# 深溟巢涌者：主控在光环内累积神经损伤
	var ne: Dictionary = sp.spawn_enemy("nest", game.ppos + Vector2(60, 0))
	game.invuln = 0.0   # 狂奔者自爆打中后有无敌帧
	game.nerve_lock = 0.0   # 前面的用例打满过神经损伤，锁定期还没过
	var n0: float = game.nerve
	for k in 6:
		ai.pattern(ne, Vector2.LEFT, 60.0, dt, ne.spd)
		c.update_nerve(dt, false, false)   # 光环按「站在溟痕里」由每帧的 update_nerve 累积
	ok(game.nerve > n0, "巢涌者光环累积神经损伤（%.1f → %.1f）" % [n0, game.nerve])
	ne.dead = true
	game.nerve = 0.0
	game.warns.clear()


## B1 ① 阶段卡点与每幕最短时长（docs/38 §1.3）：伤害截在刻度上；没满最短时长升护盾、护盾期间不掉血；
## 满时长后过卡点（0.8 秒不受伤，之后能继续打）；最终 Boss 两道刻度 0.66 / 0.33、伊祖米克每幕 10 秒
func test_gates() -> void:
	var sp = game.spawner
	c.hit("test")
	var m: Dictionary = sp.spawn_enemy("path", game.ppos + Vector2(1600, 0))
	ok(m.gates == [0.5] and absf(m.act_min - Bal.v("boss/act_min_mid", 6.0)) < EPS, "中期 Boss 一道刻度 0.5（%s）、每幕 %.0f 秒" % [str(m.gates), m.act_min])
	var k := 0
	while not m.gate_hold and k < 200:
		c.damage(m, m.maxhp)
		k += 1
	ok(m.gate_hold and absf(m.hp - m.maxhp * 0.5) < 0.01, "打太快：停在 50%% 刻度升起护盾（%.1f%%）" % (100.0 * m.hp / m.maxhp))
	var h0: float = m.hp
	c.damage(m, m.maxhp)
	ok(m.hp == h0, "护盾期间不掉血")
	c.gate_update(m, m.act_min)
	ok(not m.gate_hold and m.gates.is_empty() and m.gate_inv > 0.0, "满最短时长后护盾碎、过卡点、短暂不受伤")
	c.damage(m, m.maxhp)
	ok(m.hp == h0, "过卡点后 0.8 秒内不受伤")
	c.gate_update(m, 1.0)
	k = 0
	while not m.dead and not m.gate_hold and k < 200:
		c.damage(m, m.maxhp)
		k += 1
	ok(not m.dead and m.gate_hold and absf(m.hp - m.maxhp * Bal.v("boss/last_hold", 0.03)) < 0.01, "最后一幕没满最短时长：停在剩 3%% 处升护盾")
	c.gate_update(m, m.act_min)
	ok(not m.gate_hold and m.last_done, "最后一幕满时长后护盾碎掉")
	k = 0
	while not m.dead and k < 200:
		c.damage(m, m.maxhp)
		k += 1
	ok(m.dead, "最后一幕打完正常死亡（%d 击）" % k)
	# 最终 Boss：两道刻度；这一幕已满时长则越过刻度立刻过卡点、不升护盾
	var f: Dictionary = sp.spawn_enemy("paranoia", game.ppos + Vector2(1700, 0))
	ok(f.gates == [0.66, 0.33] and absf(f.act_min - Bal.v("boss/act_min_final", 13.0)) < EPS, "最终 Boss 刻度 0.66 / 0.33、每幕 %.0f 秒" % f.act_min)
	f.act_t = 99.0
	k = 0
	while f.gates.size() == 2 and k < 200:
		c.damage(f, f.maxhp)
		k += 1
	ok(not f.gate_hold and f.gates == [0.33] and absf(f.hp - f.maxhp * 0.66) < 0.01, "满时长越过刻度：直接过卡点、截在 66%")
	f.dead = true
	var iz: Dictionary = sp.spawn_enemy("izumik", game.ppos + Vector2(1800, 0))
	ok(absf(iz.act_min - 10.0) < EPS, "伊祖米克每幕 10 秒")
	iz.dead = true
	game.warns.clear()


## B1 ③ 破绽与韧性（§1.5，临时把塑路者放进白名单）、④ 伤害预算（§1.4，临时打开）
func test_break_budget() -> void:
	var D = preload("res://scripts/data.gd")
	var sp = game.spawner
	c.hit("test")
	D.ENEMIES["path"]["tough"] = true
	var m: Dictionary = sp.spawn_enemy("path", game.ppos + Vector2(1600, 0))
	var k := 0
	while m.break_t <= 0.0 and k < 100:
		c.damage(m, m.maxhp)
		k += 1
	ok(m.break_t > 0.0 and absf(m.tough_need - Bal.v("boss/tough_first", 25.0) * 1.5) < EPS, "韧性满（打掉约 25%%）进破绽，下次需求 ×1.5（%d 击）" % k)
	var h0: float = m.hp
	c.damage(m, m.maxhp * 0.005)
	var l1: float = h0 - m.hp
	m.break_t = 0.0
	h0 = m.hp
	c.damage(m, m.maxhp * 0.005)
	var l2: float = h0 - m.hp
	ok(absf(l1 / l2 - Bal.v("boss/break_mult", 1.4)) < 0.01, "破绽期间受伤 ×%.2f" % (l1 / l2))
	var t0: float = m.tough
	m.stun = 1.0
	game.enemies_sys.update(0.001)
	ok(m.stun <= 0.0 and m.tough > t0, "白名单 Boss 的眩晕换成韧性后清零（%.1f → %.1f）" % [t0, m.tough])
	m.dead = true
	D.ENEMIES["path"].erase("tough")
	var n: Dictionary = sp.spawn_enemy("path", game.ppos + Vector2(1650, 0))
	n.stun = 1.0
	game.enemies_sys.update(0.001)
	ok(n.stun > 0.0, "不在白名单的 Boss 眩晕照旧")
	# 伤害预算：默认关（原样返回）；打开后额度内全额、超出部分 ×0.35
	ok(c.budget_clamp(n, 30.0) == 30.0, "伤害预算默认关闭")
	var bak: Dictionary = Bal._data.get("boss", {}).duplicate()
	if not Bal._data.has("boss"):
		Bal._data["boss"] = {}
	Bal._data["boss"]["budget_on"] = 1.0
	n.budget = 10.0
	ok(absf(c.budget_clamp(n, 30.0) - (10.0 + 20.0 * Bal.v("boss/budget_over", 0.35))) < EPS and n.budget == 0.0, "预算用完后超出部分 ×0.35")
	Bal._data["boss"] = bak
	n.dead = true
	game.warns.clear()


## B1 ②（用户 9/27）：最终 Boss 登场时残留的中期 Boss 撤场——直接移除、不走 kill（不计击杀、不掉落）
func test_retreat() -> void:
	var sp = game.spawner
	var keep: Array = game.bosses.duplicate()
	var m: Dictionary = sp.spawn_enemy("carmen", game.ppos + Vector2(1600, 0))
	game.bosses = [m]
	var k0: int = game.kills
	var pk0: int = game.pickups.count_items()
	sp.retreat_mid_bosses()
	ok(m.dead and m.get("retreated", false), "残留中期 Boss 撤场")
	ok(game.kills == k0 and game.pickups.count_items() == pk0, "撤场不计击杀、不掉道具")
	game.bosses = keep


## 最终 Boss 在场时的存活杂兵上限（boss/final_mob_cap，协调人 9/30）：只在最终 Boss 活着时生效；泪滴等友方、宝箱、Boss 不计数
func test_final_mob_cap() -> void:
	var sp = game.spawner
	var keep_e: Array = game.enemies
	var keep_f = game.final_boss
	var keep_b: Array = game.bosses.duplicate()
	game.bosses = []   # 前面测试留下的 Boss 会让中期上限生效
	var fb := {"dead": false, "boss": true}
	game.enemies = [fb, {"dead": false, "boss": false, "friendly": true}, {"dead": false, "boss": false, "chest": true}, {"dead": true, "boss": false}]
	for k in 5:
		game.enemies.append({"dead": false, "boss": false})
	ok(sp.mob_count() == 5, "杂兵计数不含 Boss / 友方 / 宝箱 / 死亡（%d）" % sp.mob_count())
	game.final_boss = null
	ok(sp.boss_mob_room() == sp.max_alive(), "没有最终 Boss：不限")
	game.final_boss = fb
	var cap := int(Bal.v("boss/final_mob_cap", 120.0))
	ok(sp.boss_mob_room() == cap - 5, "最终 Boss 在场：余量 = 上限 − 存活杂兵（%d）" % sp.boss_mob_room())
	fb.dead = true
	ok(sp.boss_mob_room() == sp.max_alive(), "最终 Boss 倒下后恢复不限")
	# 中期 Boss（在 g.bosses 里、不是最终 Boss）：读 boss/mid_mob_cap
	var mb := {"dead": false, "boss": true}
	game.enemies.append(mb)
	game.bosses = [mb]
	game.final_boss = null
	var mcap := int(Bal.v("boss/mid_mob_cap", 160.0))
	ok(sp.boss_mob_room() == mcap - 5, "中期 Boss 在场：余量 = mid_mob_cap − 存活杂兵（%d）" % sp.boss_mob_room())
	mb.dead = true
	ok(sp.boss_mob_room() == sp.max_alive(), "中期 Boss 倒下后恢复不限")
	game.bosses = keep_b
	game.enemies = keep_e
	game.final_boss = keep_f

## 伊莎玛拉提速（协调人 9/30）：离远了带预警冲近（潮涌迫近，② 直线），落地给破绽；人形阶段充能 ×ishar_p1_scale
func test_ishar_close() -> void:
	var keep: Array = game.bosses.duplicate()
	var e: Dictionary = game.spawner.spawn_enemy("ishar", game.ppos + Vector2(500, 0))
	game.bosses = [e]
	game.bai.transform_ishar(e)
	e.transform_until = 0.0
	e.ishar_next_at = 0.0
	var n0: int = game.warns.size()
	game.bai._ishar_phase2(e, Vector2.LEFT, 500.0)
	var w: Dictionary = game.warns.back() if game.warns.size() > n0 else {}
	ok(w.get("name", "") == "潮涌迫近" and int(w.get("style", -1)) == 2, "离主控 500：放潮涌迫近（直线预警）")
	ok(w.get("len", 0.0) > 300.0 and w.get("len", 0.0) < 420.0, "冲到主控前约 140（线长 %.0f）" % w.get("len", 0.0))
	game.warns.erase(w)
	w.done = true
	game.bai._warn_resolve(w)
	ok(absf(float(e.get("land_break", 0.0)) - Bal.v("boss/ishar_close_break", 1.0)) < 0.01, "冲刺记下落地破绽")
	e.dash_t = 0.01
	game.bai._boss_ai(e, 0.05, Vector2.LEFT, 140.0)
	ok(e.break_t > 0.0, "落地进入破绽（%.2f 秒）" % e.break_t)
	game.warns = game.warns.filter(func(x): return not is_same(x.owner, e))
	var t2: Dictionary = game.spawner.spawn_enemy("ishar", game.ppos + Vector2(200, 0))
	game.ishar.step_ally(t2, 0.01)
	ok(absf(t2.ally_charge_need - Bal.v("boss/ishar_ally_charge", 30.0) * Bal.v("boss/ishar_p1_scale", 0.6)) < 0.01, "人形阶段充能 × ishar_p1_scale（%.1f 秒）" % t2.ally_charge_need)
	e.dead = true
	t2.dead = true
	for o in game.enemies:
		if o.type == "tear":
			o.dead = true
	game.bosses = keep

## 偏执泡影过最后一道卡点落地进二阶段（boss/paranoia_p2_at_gate，数值 9/30）；第一道卡点不变；茧仍在归零时结
func test_paranoia_p2_gate() -> void:
	var keep: Array = game.bosses.duplicate()
	var e: Dictionary = game.spawner.spawn_enemy("paranoia", game.ppos + Vector2(400, 0))
	game.bosses = [e]
	e.gates = [0.66, 0.33]
	c.gate_pass(e)
	ok(e.phase == 1 and e.ai == "ranged", "过第一道卡点：仍是一阶段悬浮远程")
	c.gate_pass(e)
	ok(e.phase == 2 and e.ai == "melee" and is_equal_approx(e.spd, 70.0), "过最后一道卡点：落地二阶段（近战、移速 70）")
	ok(not e.get("cocoon_done", false), "茧还没结（归零时才结）")
	game.warns = game.warns.filter(func(x): return not is_same(x.owner, e))
	e.dead = true
	game.bosses = keep

## 远程 Boss 迫近通用函数（泡影一阶段复用伊莎玛拉那套）+ 主教慌乱（协调人 9/30）
func test_close_panic() -> void:
	var keep: Array = game.bosses.duplicate()
	var e: Dictionary = game.spawner.spawn_enemy("paranoia", game.ppos + Vector2(500, 0))
	game.bosses = [e]
	var d1: float = game.bai._close_in(e, Vector2.LEFT, 500.0, "paranoia", "泡影漂近", Color.WHITE)
	var w: Dictionary = game.warns.back() if not game.warns.is_empty() else {}
	ok(d1 >= 0.0 and w.get("name", "") == "泡影漂近" and w.get("act", "") == "dash" and int(w.get("style", -1)) == 2, "泡影离主控 500：放泡影漂近（直线预警、冲刺）")
	ok(game.bai._close_in(e, Vector2.LEFT, 500.0, "paranoia", "泡影漂近", Color.WHITE) < 0.0, "冷却内不再放")
	e.cds = {}
	ok(game.bai._close_in(e, Vector2.LEFT, 250.0, "paranoia", "泡影漂近", Color.WHITE) < 0.0, "离主控 250（< close_min）不放")
	game.warns = game.warns.filter(func(x): return not is_same(x.owner, e))
	e.dead = true
	# 主教慌乱：搭档假死时改近战、朝搭档走、停召潮；搭档复苏后恢复远程
	var b: Dictionary = game.spawner.spawn_enemy("bishop", game.ppos + Vector2(400, 0))
	var a: Dictionary = game.spawner.spawn_enemy("archon", game.ppos + Vector2(-200, 0))
	b.partner = a
	a.partner = b
	game.bosses = [b, a]
	a.coma = true
	game.bai._boss_ai(b, 0.01, Vector2.LEFT, 400.0)
	ok(b.get("panic", false) and b.ai == "melee" and b.get("aggro", Vector2.INF) == a.pos, "搭档假死：主教慌乱，改近战朝搭档走")
	var h0: float = b.hp
	c.damage(b, 10.0)
	ok(int(b.get("panic_n", 0)) == 1 and float(b.get("panic_dmg", 0.0)) > 0.0 and absf(float(b.panic_dmg) - (h0 - b.hp)) < 0.01, "遥测：慌乱次数 1、慌乱期间掉血计入 panic_dmg（%.1f）" % float(b.get("panic_dmg", 0.0)))
	a.coma = false
	game.bai._boss_ai(b, 0.01, Vector2.LEFT, 400.0)
	ok(not b.get("panic", false) and b.ai == "ranged", "搭档复苏：主教恢复远程")
	game.warns = game.warns.filter(func(x): return not is_same(x.owner, b) and not is_same(x.owner, a))
	b.dead = true
	a.dead = true
	game.bosses = keep

## 小怪控制 / 词条按难度档覆盖（数值 9/30）：dmod 里 ≥ 0 用 dmod，-1 / 没有这个键读 balance.json enemy 段
func test_enemy_knob() -> void:
	var D = preload("res://scripts/data.gd")
	var keep: Dictionary = game.dmod.duplicate()
	game.dmod["frost_max"] = -1.0
	ok(is_equal_approx(c.enemy_knob("frost_max", 3.0), Bal.v("enemy/frost_max", 3.0)), "dmod -1：读全局 enemy/frost_max")
	game.dmod["frost_max"] = 5.0
	ok(is_equal_approx(c.enemy_knob("frost_max", 3.0), 5.0), "dmod 5：按档覆盖")
	game.dmod.erase("ctrl_start")
	ok(is_equal_approx(c.enemy_knob("ctrl_start", 1.0e9), Bal.v("enemy/ctrl_start", 1.0e9)), "dmod 没这个键：读全局")
	ok(float(D.DMOD_DEFAULT.affix_max) < 0.0 and float(D.dmod_for_tier(0).get("affix_start", 0.0)) < 0.0, "缺省表与标准档为 -1（现行为不变）")
	var m: Dictionary = D.DMOD_DEFAULT.duplicate()
	ok(D.dmod_lines(m).is_empty(), "缺省表：选难度页没有说明行")
	m.ctrl_start = 420.0
	m.frost_max = 2.0
	m.affix_max = 0.5
	var lines: Array = D.dmod_lines(m)
	ok(lines.has("小怪控制提前到 7:00") and lines.has("寒霜 2 层即冻结") and lines.has("词条概率上限 50%"), "按档覆盖的说明行（%s）" % str(lines))
	m.frost_max = Bal.v("enemy/frost_max", 3.0)
	ok(not str(D.dmod_lines(m)).contains("寒霜"), "和全局相同时不显示")
	game.dmod = keep
	# 最终 Boss 在场时新刷杂兵的生命倍率（boss_fight_enemy_hp，-1 = 跟 enemy_hp）
	var keep_f = game.final_boss
	game.dmod["enemy_hp"] = 1.7
	game.dmod["boss_fight_enemy_hp"] = 1.0
	game.final_boss = null
	var s0: Dictionary = game.spawner.new_enemy("slider", game.ppos + Vector2(900, 0))
	game.final_boss = {"dead": false, "boss": true}
	var s1: Dictionary = game.spawner.new_enemy("slider", game.ppos + Vector2(900, 0))
	ok(absf(s1.maxhp / s0.maxhp - 1.0 / 1.7) < 0.01, "最终 Boss 在场：新刷杂兵生命按 boss_fight_enemy_hp（%.2f）" % (s1.maxhp / s0.maxhp))
	game.dmod["boss_fight_enemy_hp"] = -1.0
	var s2: Dictionary = game.spawner.new_enemy("slider", game.ppos + Vector2(900, 0))
	ok(absf(s2.maxhp / s0.maxhp - 1.0) < 0.01, "-1：跟 enemy_hp 走")
	game.final_boss = keep_f
	game.dmod = keep

## 灯标圈内安全（docs/49g）：缺省全关；开了以后只在读条期间、只对非 Boss 生效
func test_beacon_safe() -> void:
	var bs = game.beacon_sys
	var keep_c = bs.charging
	var bc := {"pos": game.ppos + Vector2(300, 0), "r": 70.0}
	var mob := {"boss": false, "pos": bc.pos, "r": 10.0}
	var boss := {"boss": true, "pos": bc.pos, "r": 30.0}
	bs.charging = bc
	# 发布缺省（制作人 10-01 三档全开）：吞子弹、远程暂停开，减速关
	ok(bs.bullet_eaten(bc.pos) and bs.ranged_held(mob) and is_equal_approx(bs.slow_mult(mob), 1.0), "发布缺省：safe_bullet / safe_ranged 开，safe_slow 关")
	var keep_b: Dictionary = Bal._data.get("beacon", {}).duplicate()
	var off: Dictionary = keep_b.duplicate()
	off["safe_bullet"] = 0.0
	off["safe_ranged"] = 0.0
	off["safe_slow"] = 0.0
	Bal._data["beacon"] = off
	ok(not bs.bullet_eaten(bc.pos) and not bs.ranged_held(mob) and is_equal_approx(bs.slow_mult(mob), 1.0), "三个旋钮全关：旧行为")
	var nb: Dictionary = keep_b.duplicate()
	nb["safe_bullet"] = 1.0
	nb["safe_ranged"] = 1.0
	nb["safe_slow"] = 0.4
	Bal._data["beacon"] = nb
	ok(bs.bullet_eaten(bc.pos + Vector2(40, 0)) and not bs.bullet_eaten(bc.pos + Vector2(120, 0)), "开 safe_bullet：光圈内的子弹被吞，圈外不吞")
	ok(bs.ranged_held(mob) and not bs.ranged_held(boss), "开 safe_ranged：杂兵不起远程出招，Boss 照常")
	ok(is_equal_approx(bs.slow_mult(mob), 0.6) and is_equal_approx(bs.slow_mult(boss), 1.0), "开 safe_slow 0.4：光圈附近杂兵 ×0.6，Boss 不减速")
	bs.charging = null
	ok(not bs.bullet_eaten(bc.pos) and not bs.ranged_held(mob), "不在读条（charging 为空）时全部失效")
	Bal._data["beacon"] = keep_b
	bs.charging = keep_c

## 圣徒两档（用户 10-01 按原作核对：卡门 / 伊比利亚是同一人物）：中期抽取按人物互斥；弹药按数据（卡门 3、伊比利亚 1）
func test_saint_tiers() -> void:
	var D = preload("res://scripts/data.gd")
	var sp = game.spawner
	var keep: Array = sp.mid_used.duplicate()
	var ic := -1
	var ii := -1
	for i in D.MID_POOL.size():
		if D.MID_POOL[i].has("carmen"):
			ic = i
		if D.MID_POOL[i].has("iberia"):
			ii = i
	sp.mid_used = [ic]
	ok(sp.person_used(ii) and not sp.person_used(0), "3:30 出了卡门：7:00 不再抽伊比利亚，其他照常")
	sp.mid_used = [ii]
	ok(sp.person_used(ic), "反过来也互斥")
	sp.mid_used = keep
	ok(D.MID_FIRST.has(ic) and not D.MID_FIRST.has(ii), "3:30 池是卡门（常规档），伊比利亚（强化档）只在 7:00")
	var c: Dictionary = sp.spawn_enemy("carmen", game.ppos + Vector2(900, 0))
	var b: Dictionary = sp.spawn_enemy("iberia", game.ppos + Vector2(900, 60))
	ok(int(c.ammo) == 3 and int(b.ammo) == 1, "弹药按数据：卡门 3、伊比利亚 1（%d / %d）" % [int(c.ammo), int(b.ammo)])
	c.dead = true
	b.dead = true

## B1 第二批：最终 Boss 场地（§1.7）——冻结后 3 秒插值到场地半径、主控离新圈边 ≥100、zone_next_* 同步、约束点落在圈内
func test_arena() -> void:
	var zs: Array = [game.zone_state, game.zone_c, game.zone_r, game.zone_next_c, game.zone_next_r]
	game.zone_state = 3
	game.zone_c = game.ppos + Vector2(700, 0)
	game.zone_r = 1000.0
	c.freeze_zone(520.0)
	ok(game.zone_frozen and game.zone_state == 3 and game.zone_next_r == 520.0, "场地冻结：稳定态、下一圈同步为场地")
	ok(game.ppos.distance_to(game.zone_next_c) <= 420.0 + 0.01, "主控离场地边 ≥100（%.0f）" % game.ppos.distance_to(game.zone_next_c))
	for k in 40:
		c.update_zone(0.1)
	ok(absf(game.zone_r - 520.0) < 0.01 and game.zone_c.distance_to(game.zone_next_c) < 0.01, "3 秒后圈正好是场地")
	var p: Vector2 = c.arena_clamp(game.zone_next_c + Vector2(2000, 0), 80.0)
	ok(p.distance_to(game.zone_next_c) <= 440.0 + 0.01, "约束点落在场地内、离圈边 ≥80")
	game.zone_frozen = false
	game.zone_state = zs[0]
	game.zone_c = zs[1]
	game.zone_r = zs[2]
	game.zone_next_c = zs[3]
	game.zone_next_r = zs[4]


## 画即判（docs/38 §1.9、docs/48 P0-1）：圆形预警画成纵向 ×0.72 的椭圆；8 个方向上画面边缘外 4px 的点不中、内 4px 的点中
func test_ground() -> void:
	var p0: Vector2 = game.ppos
	var w := {"shape": "circle", "pos": p0 + Vector2(300, 0), "r": 90.0}
	var bad := 0
	for k in 8:
		var d := Vector2.from_angle(TAU * k / 8.0)
		var edge: Vector2 = Vector2(d.x * 90.0, d.y * 90.0 * c.GROUND_Y)   # 画面上的椭圆边
		var n: Vector2 = Vector2(d.x * c.GROUND_Y, d.y).normalized()       # 椭圆法线方向（近似）
		game.ppos = w.pos + edge + n * 4.0
		if game.bai._warn_hit(w):
			bad += 1
		game.ppos = w.pos + edge - n * 4.0
		if not game.bai._warn_hit(w):
			bad += 1
	ok(bad == 0, "圆形预警：8 个方向边缘外 4px 不中、内 4px 中（错 %d 处）" % bad)
	game.ppos = p0


## 预警样式（docs/38 §8.11）：_warn 按形状和标记填 style，界面照 style 画；跟随施法者的伤害圈仍是 ① 落点圈
func test_warn_style() -> void:
	var e := {"boss": false, "type": "test", "pos": game.ppos, "dmg": 10.0, "r": 20.0}
	var cases := [
		["circle", {"follow": true, "act": "bite"}, 1],
		["circle", {"follow": true, "act": "frost"}, 1],
		["circle", {"act": "slam"}, 1],
		["circle", {"follow": true, "act": "bring"}, 4],
		["circle", {"gap_ang": 0.0, "act": "pattern_ring"}, 4],
		["circle", {"follow": true, "must_dash": true, "act": "izu_wave"}, 5],
		["circle", {"act": "spawn", "dmg": 0.0, "lock": false}, 0],
		["line", {"act": "beam"}, 2],
		["cone", {"act": "reap"}, 3],
		["circle", {"act": "slam", "style": 4}, 4],
	]
	var bad := PackedStringArray()
	for cs in cases:
		var w: Dictionary = game.bai._warn(e, cs[0], 0.6, cs[1])
		game.warns.erase(w)
		if int(w.style) != int(cs[2]):
			bad.append("%s/%s=%d" % [cs[0], cs[1].act, int(w.style)])
	ok(bad.is_empty(), "预警样式按形状和标记分类（错：%s）" % [", ".join(bad)])

## 后期暴毙方案 3（用户 9/27）：通用 2 秒掉血上限（protect/any_2s_cap，缺省关）与非 Boss 侵蚀池上限（enemy/corrode_pool_cap，缺省不封顶）
func test_any_cap() -> void:
	var mh: float = game.max_hp
	ok(is_equal_approx(c._any_clamp(mh), mh), "通用 2 秒上限：代码缺省为关（测试期间 protect 段已清空）")
	var bak_p: Dictionary = Bal._data.get("protect", {}).duplicate()
	var bak_e: Dictionary = Bal._data.get("enemy", {}).duplicate()
	Bal._data["protect"] = {"any_2s_cap": 0.45, "any_excess_mult": 0.4}
	c.any_log.clear()
	var a1: float = c._any_clamp(mh * 0.3)
	var a2: float = c._any_clamp(mh * 0.3)
	ok(absf(a1 - mh * 0.3) < 0.01 and absf(a2 - (mh * 0.15 + mh * 0.15 * 0.4)) < 0.01, "2 秒内超过 45%% 的部分 ×0.4（%.1f%%、%.1f%%）" % [100.0 * a1 / mh, 100.0 * a2 / mh])
	Bal._data["protect"] = bak_p
	c.any_log.clear()
	var e2: Dictionary = bak_e.duplicate()
	e2["corrode_pool_cap"] = 0.3
	Bal._data["enemy"] = e2
	var hp0: float = game.hp
	game.corrode_pool = 0.0
	c.corrode_boss = 0.0
	game.invuln = 0.0
	game.shield = 0
	game.in_type = ["近战", "物理"]
	for k in 5:
		c.enemy_hit(mh * 0.2, {"corrode": 1.0}, true, true)
	ok(game.corrode_pool <= mh * 0.3 + 0.01, "非 Boss 侵蚀池 ≤ 30%% 最大生命（%.1f%%）" % (100.0 * game.corrode_pool / mh))
	Bal._data["enemy"] = bak_e
	game.corrode_pool = 0.0
	game.hp = hp0


## 小怪控制与词条（用户 9/29）：寒霜叠层 → 冻结、Boss 在场转减速、冲刺挣脱、侵蚀创口减治疗 + 掉血、合计上限、甲壳 / 潮盾
## 塞雷娅净化（docs/49e，用户 9/30）：cleanse_ctrl 清寒冷（层数与攻速减益）与冻结 / 束缚；operators/saria/cleanse = 0 时不清；
## 选人页 / 招募卡的奶位标签按技能数据生成
func test_saria_cleanse() -> void:
	var sa = load("res://scripts/characters/character.gd").create(game, "saria")
	game.cold = 3
	game.cold_t = 2.0
	game.root_t = 0.8
	c.sync_cold()
	var did: bool = sa.cleanse_ctrl(false)
	ok(did and game.cold == 0 and game.cold_t == 0.0 and game.root_t == 0.0, "塞雷娅净化：清除寒冷与冻结 / 束缚")
	var ops: Dictionary = Bal._data.get("operators", {})
	var sbak = ops.get("saria", {}).duplicate()
	var s2: Dictionary = sbak.duplicate()
	s2["cleanse"] = 0
	ops["saria"] = s2
	Bal._data["operators"] = ops
	game.cold = 2
	game.root_t = 0.5
	ok(not sa.cleanse_ctrl(false) and game.cold == 2 and game.root_t == 0.5, "operators/saria/cleanse = 0：不净化")
	ops["saria"] = sbak
	game.cold = 0
	game.root_t = 0.0
	c.sync_cold()
	var Aff = load("res://scripts/run/affects.gd")
	var Ch = load("res://scripts/characters/character.gd")
	ok(Aff.care_labels(Ch.load_def("saria")) == ["净化：寒冷 · 束缚", "回复"], "奶位标签：塞雷娅 %s" % str(Aff.care_labels(Ch.load_def("saria"))))
	ok(Aff.care_labels(Ch.load_def("lumen")) == ["净化：侵蚀 · 神经损伤", "回复"], "奶位标签：流明 %s" % str(Aff.care_labels(Ch.load_def("lumen"))))
	ok(Aff.care_labels(Ch.load_def("kaltsit")) == ["净化：神经损伤", "回复"], "奶位标签：凯尔希")
	ok(Aff.care_labels(Ch.load_def("skadi")).is_empty(), "奶位标签：斯卡蒂没有")


func test_ailments() -> void:
	# 断言按全局 enemy 段写（寒霜 3 层等）；本机存档的难度档可能是 Ⅳ / Ⅷ，其难度表会覆盖 frost_max / ctrl_start，这里固定用标准档
	var keep_dmod: Dictionary = game.dmod
	game.dmod = preload("res://scripts/data.gd").dmod_for_tier(0)
	var bak: Dictionary = Bal._data.get("enemy", {}).duplicate()
	var e2: Dictionary = bak.duplicate()
	e2["ctrl_start"] = 0.0
	Bal._data["enemy"] = e2
	var mh: float = game.max_hp
	game.invuln = 0.0
	game.shield = 0
	game.in_type = ["近战", "物理"]
	game.cold = 0
	game.cold_immune = 0.0
	game.root_t = 0.0
	game.root_immune = 0.0
	# Boss 在场：满层冻结换成减速
	for k in 3:
		game.invuln = 0.0
		c.enemy_hit(1.0, {"type": "founder"}, true, true)
	ok(game.cold == 3 and game.root_t == 0.0 and c.slows.has("root"), "Boss 在场：寒霜满层不冻结，换成减速")
	ok(absf(c.ctrl_slow() - maxf(1.0 - 0.12 * 3, 0.55)) < EPS, "寒霜 3 层移速 ×%.2f（合计下限 0.55）" % c.ctrl_slow())
	c.slows.erase("root")
	# 没有 Boss：冻结，冲刺挣脱，之后免疫
	boss_e.dead = true
	game.cold = 0
	game.cold_immune = 0.0
	game.root_immune = 0.0
	for k in 3:
		game.invuln = 0.0
		c.enemy_hit(1.0, {"type": "founder"}, true, true)
	ok(game.root_t > 0.0 and game.root_immune > game.root_t, "寒霜满层冻结 %.1f 秒，之后免疫硬控" % game.root_t)
	game.dash_cd = 0.0
	game.dash_t = 0.0
	game._try_dash()
	ok(game.root_t == 0.0, "冲刺挣脱冻结")
	game.dash_t = 0.0
	boss_e.dead = false
	# 侵蚀创口：减受治疗、每秒掉血
	game.wound = 0
	game.invuln = 0.0
	c.enemy_hit(1.0, {"type": "reaper"}, true, true)
	c.enemy_hit(1.0, {"type": "reaper"}, true, true)
	ok(game.wound == 2, "收割者命中叠侵蚀创口（%d 层）" % game.wound)
	game.hp = mh * 0.5
	var h0: float = game.hp
	c.heal(10.0)
	var hc: float = 1.0 - Bal.v("enemy/wound_heal_cut", 0.10) * 2
	ok(absf((game.hp - h0) - 10.0 * game.heal_mult * hc) < 0.01, "2 层创口受治疗 ×%.2f" % hc)
	game.wound = 0
	game.cold = 0
	c.sync_cold()
	game.root_t = 0.0
	# 词条：打开后普通怪按概率带甲壳 / 潮盾，潮盾先扣
	e2["affix_start"] = 0.0
	e2["affix_max"] = 1.0
	e2["affix_ramp"] = 1.0
	var sp = game.spawner
	var got := {}
	for k in 20:
		var m: Dictionary = sp.spawn_enemy("bone", game.ppos + Vector2(1500 + k * 3, 0))
		got[m.affix] = true
		if m.affix == "shield" and not got.has("shield_ok"):
			var hp0: float = m.hp
			c.hit("test")
			c.damage(m, m.shield_hp * 0.5)
			got["shield_ok"] = m.hp == hp0
		m.dead = true
	ok(got.has("armor") and got.has("shield") and got.get("shield_ok", false), "词条：甲壳 / 潮盾都会出现，潮盾先扣盾")
	Bal._data["enemy"] = bak
	game.hp = mh
	game.dmod = keep_dmod


## docs/38 §8 第一批：塑路者猎核（核心部件、优先索敌、打碎破绽 / 超时回流加冲撞）与接潮假死赛跑（8 秒复苏到 50%、最多 2 次）
func test_lore1() -> void:
	var sp = game.spawner
	var bai = game.bai
	c.hit("test")
	var pa: Dictionary = sp.spawn_enemy("path", game.ppos + Vector2(1500, 0))
	pa.gates_passed = 1
	bai._path_core(pa)
	var core = pa.get("core")
	var owned := 0
	for o in game.enemies:
		if o.type == "fractal" and not o.dead and is_same(o.get("owner"), pa):
			owned += 1
	ok(core != null and core.part and core.spd == 0.0 and owned >= 3, "塑路者第二幕出核心部件（场上碎片 %d）" % owned)
	var near: Dictionary = sp.spawn_enemy("bone", game.ppos + Vector2(20, 0))
	game.enemies_sys.build_grid()   # 空间网格每帧重建；刚刷出的单位要先进网格
	var first: Array = game.enemies_sys.nearest(1, 5000.0)
	ok(not first.is_empty() and is_same(first[0], core), "部件在射程内优先被索敌")
	near.dead = true
	core.dead = true
	bai._path_core(pa)
	var left := 0
	for o in game.enemies:
		if o.type == "fractal" and not o.dead and is_same(o.get("owner"), pa):
			left += 1
	ok(pa.break_t > 0.0 and left == 0 and pa.get("core") == null, "打碎核心：碎片崩解、Boss 破绽 %.1f 秒" % pa.break_t)
	pa.core_next = 0.0
	bai._path_core(pa)
	pa.core_until = game.t - 1.0
	bai._path_core(pa)
	ok(int(pa.get("dash_bonus", 0)) >= 3, "核心超时：碎片回流，下次冲撞 +%d 段" % int(pa.get("dash_bonus", 0)))
	pa.dead = true
	# 接潮假死赛跑
	var bi: Dictionary = sp.spawn_enemy("bishop", game.ppos + Vector2(1600, 0))
	var ar: Dictionary = sp.spawn_enemy("archon", game.ppos + Vector2(1690, 0))
	bi.partner = ar
	ar.partner = bi
	ar.gates = []
	ar.last_done = true
	var k2 := 0
	while not ar.coma and not ar.dead and k2 < 200:   # 单次伤害上限（hit_cap_pct）下要多打几下
		c.damage(ar, ar.maxhp)
		k2 += 1
	ok(ar.coma and ar.get("count_max", 0.0) > 0.0, "蔑死体归零假死，挂 %.0f 秒倒计时" % ar.get("count_max", 0.0))
	bai._boss_ai(ar, Bal.v("boss/pair_race", 8.0) + 0.1, Vector2.LEFT, 500.0)
	ok(not ar.coma and ar.revives == 1 and absf(ar.hp - ar.maxhp * 0.5) < 1.0, "8 秒没打倒另一具：复苏到 50%%（第 %d 次）" % ar.revives)
	ar.revives = 2
	ar.invuln = false
	k2 = 0
	while not ar.dead and not ar.coma and k2 < 200:
		c.damage(ar, ar.maxhp)
		k2 += 1
	ok(ar.dead, "复苏满 2 次后直接倒下")
	bi.dead = true
	game.warns.clear()


## docs/38 §8 第二批：圣徒装填打断（伤害 5% / 冲刺穿身 → 5 秒破绽；没打断 → 三连瞄准）与卡门第二幕炮身近战（原换剑）
func test_lore2() -> void:
	var sp = game.spawner
	var bai = game.bai
	c.hit("test")
	var ib: Dictionary = sp.spawn_enemy("iberia", game.ppos + Vector2(1500, 0))
	ib.age = 5.0
	var go := func(e: Dictionary, dt: float) -> void:
		e.wind = 0.0
		e.stun = 0.0
		e.cds = {"judge": INF, "snipe": INF, "hop": INF, "sword": INF}   # 其他招式冷却中：出招后的站定窗口会顺延装填（这是设计），测试里只看装填本身
		e.pattern_next = INF
		bai._boss_ai(e, dt, Vector2.LEFT, 500.0)
	ib.ammo = 0
	ib.reload_t = 0.0
	go.call(ib, 0.01)
	ok(absf(ib.channel - Bal.v("boss/iberia_reload", 2.2)) < 0.05 and ib.count_max > 0.0, "伊比利亚弹药打空开始读条 %.1f 秒" % ib.channel)
	var k := 0
	while ib.channel > 0.0 and k < 100:
		c.damage(ib, ib.maxhp * 0.01)
		k += 1
	ok(ib.channel <= 0.0 and ib.break_t > 0.0 and ib.ammo == 0, "读条中打掉约 5%% 被打断：破绽 %.1f 秒" % ib.break_t)
	# 冲刺穿身打断
	ib.break_t = 0.0
	ib.reload_t = 0.0
	go.call(ib, 0.01)
	var p0: Vector2 = game.ppos
	game.ppos = ib.pos
	game.dash_t = 0.2
	go.call(ib, 0.01)
	ok(ib.channel <= 0.0 and ib.break_t > 0.0, "主控冲刺穿过身体也能打断")
	game.dash_t = 0.0
	game.ppos = p0
	# 没打断：三连瞄准
	ib.break_t = 0.0
	ib.reload_t = 0.0
	go.call(ib, 0.01)
	var nw: int = game.warns.size()
	go.call(ib, Bal.v("boss/iberia_reload", 4.0) + 0.1)
	ok(ib.ammo == 1 and game.warns.size() >= nw + 3, "读条完成：弹药补满（伊比利亚强化档 1 发）并连发三条瞄准线")
	ib.dead = true
	game.warns.clear()
	# 卡门第二幕：先炮身近战，再装填
	var cm: Dictionary = sp.spawn_enemy("carmen", game.ppos + Vector2(1600, 0))
	cm.age = 5.0
	cm.gates_passed = 1
	cm.ammo = 0
	cm.reload_t = 0.0
	go.call(cm, 0.01)
	ok(cm.get("sword_t", 0.0) > 0.0 and cm.ai == "melee" and cm.channel <= 0.0, "卡门第二幕弹药打空先炮身近战")
	go.call(cm, Bal.v("boss/carmen_sword", 8.0) + 0.1)
	go.call(cm, 0.01)
	ok(absf(cm.channel - Bal.v("boss/carmen_reload", 3.0)) < 0.05, "剑形态结束后装填 %.1f 秒" % cm.channel)
	cm.dead = true
	game.warns.clear()


## docs/38 §8 第三批：偏执泡影结茧（打破外壳 → 破绽；超时 → 凝视 +1）、认知负担光环、部件被周围击杀间接削
func test_lore3() -> void:
	var sp = game.spawner
	var bai = game.bai
	c.hit("test")
	var pa: Dictionary = sp.spawn_enemy("paranoia", game.ppos + Vector2(1500, 0))
	pa.gates = []
	pa.last_done = true
	var k := 0
	while pa.get("cocoon_t", 0.0) <= 0.0 and not pa.dead and k < 300:
		c.damage(pa, pa.maxhp)
		k += 1
	ok(pa.cocoon_t > 0.0 and pa.invuln and pa.part and pa.shell_hp > 0.0, "偏执泡影第一次归零结茧（外壳 %.0f）" % pa.shell_hp)
	var h0: float = pa.hp
	bai._paranoia_cocoon_step(pa, 0.25)
	c.damage(pa, pa.shell_max * 10.0)
	ok(pa.hp == h0 and pa.shell_hp < pa.shell_max and pa.shell_hp > 0.0, "茧期间伤害打在外壳上，而且一下打不破（受伤速度有上限）")
	var tt := 0.0
	while pa.get("cocoon_t", 0.0) > 0.0 and tt < 10.0:
		bai._paranoia_cocoon_step(pa, 0.1)
		tt += 0.1
		c.damage(pa, pa.shell_max * 10.0)
	ok(pa.phase == 2 and pa.break_t > 0.0 and absf(pa.hp - pa.maxhp * 0.4) < 1.0 and tt >= Bal.v("boss/paranoia_shell_min", 4.0) - 0.3, "输出拉满也要约 %.1f 秒打破外壳：复活到 40%% 并破绽" % tt)
	pa.dead = true
	var pb: Dictionary = sp.spawn_enemy("paranoia", game.ppos + Vector2(1600, 0))
	bai.paranoia_cocoon(pb)
	bai._paranoia_cocoon_step(pb, Bal.v("boss/paranoia_cocoon", 8.0) + 0.1)
	ok(pb.phase == 2 and int(pb.get("gaze_bonus", 0)) == 1 and pb.get("break_t", 0.0) <= 0.0, "茧没打破：同样复活，但凝视永久 +1")
	# 光环
	var a0: float = game.stats.value(&"op_aspd")
	bai._paranoia_aura(pb, 100.0)
	var a1: float = game.stats.value(&"op_aspd")
	bai._paranoia_aura(pb, 500.0)
	ok(a1 < a0 and absf(game.stats.value(&"op_aspd") - a0) < EPS, "认知负担光环：站在里面全队攻速降低，离开恢复")
	pb.dead = true
	# 部件被周围击杀间接削
	var part: Dictionary = sp.spawn_enemy("fractal", game.ppos + Vector2(1700, 0))
	part.part = true
	var ph: float = part.hp
	var mob: Dictionary = sp.spawn_enemy("bone", part.pos + Vector2(30, 0))
	c.kill(mob)
	ok(part.hp < ph, "部件附近的小怪被击杀：部件掉 %.0f%% 血" % (100.0 * (ph - part.hp) / part.maxhp))
	part.dead = true
	game.warns.clear()


## docs/38 §8 第四批：伊祖米克（固定学习期、吸收强化、灯柱、全场地波）与凋亡损伤（满条暂停技力、回落、冲刺清一部分）
func test_lore4() -> void:
	var sp = game.spawner
	var bai = game.bai
	var iz: Dictionary = sp.spawn_enemy("izumik", game.ppos + Vector2(1500, 0))
	iz.age = 5.0
	bai._boss_ai(iz, 0.01, Vector2.LEFT, 500.0)
	ok(iz.phase == 1 and iz.invuln and absf(iz.count_max - Bal.v("boss/izumik_learn", 20.0)) < EPS, "伊祖米克学习期固定 %.0f 秒" % iz.count_max)
	bai.izumik_absorb(iz)
	bai.izumik_absorb(iz)
	ok(int(iz.izu_layers) == 2, "吸收子代叠强化层（%d 层）" % int(iz.izu_layers))
	var d0: float = iz.dmg
	bai._boss_ai(iz, Bal.v("boss/izumik_learn", 20.0) + 0.1, Vector2.LEFT, 500.0)
	ok(iz.phase == 2 and not iz.invuln and absf(iz.hp - iz.maxhp) < 1.0 and iz.dmg > d0 and iz.lamps.size() == 3, "学习结束：满血、强化生效、立起 3 根灯柱")
	var l0: Dictionary = iz.lamps[0]
	var p0: Vector2 = game.ppos
	game.ppos = l0.pos
	bai._izumik_lamp_step(iz, 1.1)
	ok(l0.lit and bai.izumik_safe(iz), "主控在灯柱旁待 1 秒点亮，光圈里算安全")
	var w: Dictionary = bai._warn(iz, "circle", 2.0, {"follow": true, "r": 2400.0, "act": "izu_wave", "dmg": game.max_hp * 0.2})
	game.invuln = 0.0
	var h0: float = game.hp
	bai._warn_resolve(w)
	ok(game.hp == h0, "站在点亮的灯柱光圈里：全场地波打不到")
	game.ppos = p0 + Vector2(0, 900)
	game.invuln = 0.0
	bai._warn_resolve(w)
	ok(game.hp < h0, "光圈外吃到全场地波")
	game.ppos = p0
	game.hp = game.max_hp
	iz.dead = true
	game.warns.clear()
	# 凋亡损伤
	game.apop = 0.0
	game.apop_t = 0.0
	c.add_apop(60.0)
	c.add_apop(60.0)
	ok(game.apop_t > 0.0 and game.apop_t <= 4.0 and game.apop == 0.0, "凋亡满条：技力暂停 %.1f 秒（上限 4）" % game.apop_t)
	game.apop_t = 0.0
	c.add_apop(50.0)
	game.apop_hold = 2.0
	c.update_ailments(1.0)
	ok(game.apop < 50.0, "离开来源后凋亡回落（%.0f）" % game.apop)
	game.dash_cd = 0.0
	game.dash_t = 0.0
	var a0: float = game.apop
	game._try_dash()
	ok(game.apop < a0, "冲刺清掉一部分凋亡（%.0f → %.0f）" % [a0, game.apop])
	game.dash_t = 0.0
	game.apop = 0.0


## docs/38 §8 第五批：骑士冰枪桩（66% 后立桩、冲锋撞桩 → 5 秒破绽）、二阶段冲锋 3 次一组；伊莎玛拉过卡点后轮换加快
func test_lore5() -> void:
	var sp = game.spawner
	var bai = game.bai
	var kn: Dictionary = sp.spawn_enemy("knight_boss", game.ppos + Vector2(1500, 0))
	kn.age = 10.0
	kn.gates_passed = 1
	bai._knight_stakes(kn, 0.01)
	ok(kn.stakes.size() == int(Bal.v("boss/knight_stakes", 3.0)), "66%% 卡点后立 %d 根冰枪桩" % kn.stakes.size())
	kn.stakes[0].pos = kn.pos
	kn.kb = Vector2(900, 0)
	kn.kb_self = true
	bai._knight_stakes(kn, 0.01)
	ok(kn.break_t > 0.0 and kn.kb == Vector2.ZERO, "冲锋撞桩：长枪脱手，破绽 %.1f 秒" % kn.break_t)
	kn.break_t = 0.0
	kn.phase = 2
	kn.cds = {"frost": INF, "stab": INF, "hunt": INF, "charge": 0.0}
	kn.pattern_next = INF
	kn.wind = 0.0
	kn.stun = 0.0
	bai._boss_ai(kn, 0.01, Vector2.LEFT, 400.0)
	ok(int(kn.get("dash2", 0)) == int(Bal.v("boss/knight_p2_chain", 2.0)), "二阶段冲锋后还要再冲 %d 次（一组 3 次）" % int(kn.get("dash2", 0)))
	kn.dead = true
	game.warns.clear()
	var ish: Dictionary = sp.spawn_enemy("ishar", game.ppos + Vector2(1600, 0))
	ok(is_equal_approx(bai._ishar_haste(ish), 1.0), "伊莎玛拉卡点前轮换不变")
	ish.gates_passed = 1
	ok(bai._ishar_haste(ish) < 1.0, "过卡点后轮换恢复时间 ×%.2f" % bai._ishar_haste(ish))
	ish.dead = true


## 神经损伤（用户 9/29 按原作）：只在溟痕里累积，满格一次真伤 + 眩晕，之后清零并锁 5 秒；离开溟痕回落；流明光域不累积
func test_nerve() -> void:
	boss_e.dead = true
	game.nerve = 0.0
	game.nerve_lock = 0.0
	game.root_t = 0.0
	game.root_immune = 0.0
	game.invuln = 0.0
	c.update_nerve(1.0, true, false)
	var n1: float = game.nerve
	ok(n1 > 0.0, "站在溟痕里神经损伤累积（1 秒 %.0f）" % n1)
	c.update_nerve(1.0, false, false)
	ok(game.nerve < n1, "离开溟痕回落")
	var nb: float = game.nerve
	c.update_nerve(1.0, true, true)
	ok(game.nerve < nb or game.nerve == 0.0, "流明光域里不累积")
	var h0: float = game.hp
	game.nerve = c.nerve_max() - 1.0
	c.update_nerve(1.0, true, false)
	ok(game.nerve == 0.0 and game.nerve_lock > 0.0 and game.root_t > 0.0 and game.hp < h0, "满格：真伤 + 眩晕，清零并锁定")
	c.update_nerve(1.0, true, false)
	ok(game.nerve == 0.0, "锁定期间不再累积")
	c.enemy_hit(1.0, {"nerve": 50.0}, true, true)
	ok(game.nerve == 0.0, "命中附带的神经损伤缺省不累积（只有溟痕）")
	game.nerve_lock = 0.0
	game.root_t = 0.0
	game.hp = game.max_hp
	boss_e.dead = false


## 浮海飘航者神经弹（协调人 9/29 定 A）：命中 / 落地留下一小片溟痕（半径 30、5 秒）
func test_floater_mire() -> void:
	var fl: Dictionary = game.spawner.spawn_enemy("floater", game.ppos + Vector2(200, 0))
	var nm: int = game.mires.size()
	game.eai.shoot(fl, Vector2.LEFT)
	var b: Dictionary = game.ebullets[game.ebullets.size() - 1]
	b.life = 0.0001
	game.enemies_sys.update_ebullets(0.01)
	var ok_m := false
	if game.mires.size() > nm:
		var m: Dictionary = game.mires[game.mires.size() - 1]
		ok_m = absf(float(m.maxr) - 30.0) < EPS and absf(float(m.life) - 5.0) < 0.1
	ok(ok_m, "飘航者神经弹落地留下半径 30、5 秒的溟痕")
	fl.dead = true


## 引航灯标离开光圈后的进度回退（docs/49f ①）：缺省 = 离开就每秒退需要量的 20%；decay_delay 内不退，之后按 decay_pct 退
func test_beacon_decay() -> void:
	var had: bool = Bal._data.has("beacon")
	var old = Bal._data.get("beacon")
	var bs = game.beacon_sys
	var nb: float = bs.next_at
	bs.next_at = 1.0e9   # 不让测试期间刷新的灯标
	var zs: int = game.zone_state
	game.zone_state = 0
	var mk := func() -> Dictionary:
		var d := {"pos": game.ppos + Vector2(900, 0), "lit": false, "prog": 1.25, "need": 2.5, "lit_t": -1.0, "count_end": 0.0, "count_max": 0.0,
			"dead": false, "r": 70.0, "clear_r": 340.0, "safe_end": 0.0, "age": 0.0, "out_t": 0.0}
		game.beacons = [d]
		return d
	var step := func(sec: float) -> void:
		for k in int(round(sec * 60.0)):
			bs.update(1.0 / 60.0)
	# 缺省：离开 1 秒退 0.5 秒进度
	Bal._data["beacon"] = {}
	var b1: Dictionary = mk.call()
	step.call(1.0)
	ok(absf(b1.prog - 0.75) < 0.02, "灯标缺省：离开 1 秒进度 1.25 → 0.75（每秒 20%）")
	# decay_delay 5 / decay_pct 0.1：4 秒内不退，6 秒时退了 1 秒 × 0.25
	Bal._data["beacon"] = {"decay_delay": 5.0, "decay_pct": 0.1}
	var b2: Dictionary = mk.call()
	step.call(4.0)
	ok(absf(b2.prog - 1.25) < 0.001, "灯标 decay_delay 5：离开 4 秒进度不退")
	step.call(2.0)
	ok(absf(b2.prog - 1.0) < 0.02, "灯标 decay_pct 0.1：延迟后 1 秒退 0.25")
	game.beacons = []
	bs.next_at = nb
	game.zone_state = zs
	if had:
		Bal._data["beacon"] = old
	else:
		Bal._data.erase("beacon")


## 经验视野外回收（docs/38 §8.13 方案 A，数值 10-01）：视野外满 recall_after 秒入账且只计一次、回到视野内重新计时、
## 只回收经验结晶、兜底上限直接入账、recall_after = 0 关闭
func test_xp_recall() -> void:
	var pk = game.pickups
	var had: bool = Bal._data.has("pickup")
	var old = Bal._data.get("pickup")
	var keep_gems: Array = game.gems
	var p2: Dictionary = (old as Dictionary).duplicate() if had else {}
	p2["recall_after"] = 6.0
	p2["recall_tick"] = 1.0
	p2["recall_margin"] = 96.0
	p2["gem_overflow"] = 400.0
	Bal._data["pickup"] = p2
	var far: Vector2 = game.ppos + Vector2(2200, 0)     # 逻辑视野外
	var near: Vector2 = game.ppos + Vector2(500, 0)     # 视野内、拾取范围外
	var mk := func(kind: String, pos: Vector2, val: float) -> Dictionary:
		return {"pos": pos, "kind": kind, "val": val, "dead": false, "mag": false, "mag_t": 0.0, "z": 0.0, "vz": 0.0,
			"vel": Vector2.ZERO, "special": kind == "magnet" or kind == "heal" or kind == "chest", "landed": true, "age": 10.0, "seed": 0.0, "out_t": 0.0}
	var step := func(sec: float) -> void:
		for k in int(round(sec * 60.0)):
			pk.update(1.0 / 60.0)
	pk.recall_acc = 0.0
	# 1）视野外 3 颗共 30 经验：5 秒不回收，满 6 秒回收，正好 +30，只计一次
	var xs: Array = [mk.call("xp", far, 10.0), mk.call("xp", far + Vector2(0, 50), 10.0), mk.call("xp", far + Vector2(0, -50), 10.0)]
	game.gems = xs.duplicate()
	var r0: float = pk.xp_src.recall
	step.call(5.0)
	ok(pk.xp_src.recall - r0 < 0.01 and not xs[0].dead, "回收：视野外 5 秒还不回收")
	step.call(2.0)
	ok(absf(pk.xp_src.recall - r0 - 30.0) < 0.01 and xs.all(func(o): return o.dead), "回收：视野外满 6 秒入账 30（%.1f）" % (pk.xp_src.recall - r0))
	step.call(8.0)
	ok(absf(pk.xp_src.recall - r0 - 30.0) < 0.01, "回收：已回收的结晶不重复计")
	# 2）只回收经验：灯油 / 源石锭 / 磁铁 / 回复药剂在视野外 10 秒也不动
	var others: Array = [mk.call("oil", far, 15.0), mk.call("ingot", far, 1.0), mk.call("magnet", far, 1.0), mk.call("heal", far, 1.0)]
	game.gems = others.duplicate()
	step.call(10.0)
	ok(others.all(func(o): return not o.dead), "回收：灯油 / 源石锭 / 磁铁 / 回复药剂不回收")
	# 3）回到视野内重新计时：外 4 秒 → 内 1.5 秒 → 外 4 秒不回收；再外 3 秒才回收
	var g1: Dictionary = mk.call("xp", far, 7.0)
	game.gems = [g1]
	pk.recall_acc = 0.0
	r0 = pk.xp_src.recall
	step.call(4.0)
	g1.pos = near
	step.call(1.5)
	ok(float(g1.get("out_t", 0.0)) == 0.0, "回收：回到视野内计时清零")
	g1.pos = far
	step.call(4.0)
	ok(not g1.dead, "回收：清零后视野外 4 秒不回收")
	step.call(3.0)
	ok(g1.dead and absf(pk.xp_src.recall - r0 - 7.0) < 0.01, "回收：重新累计满 6 秒后入账")
	# 4）兜底：掉落物数超过 gem_overflow 时新掉的经验直接入账、计入回收与 recall_backstop
	game.gems = [mk.call("oil", far, 1.0), mk.call("oil", far, 1.0), mk.call("oil", far, 1.0)]
	p2["gem_overflow"] = 2.0
	r0 = pk.xp_src.recall
	var nb: int = pk.recall_backstop
	pk.drop(far, "xp", 5.0)
	ok(game.gems.size() == 3 and absf(pk.xp_src.recall - r0 - 5.0) < 0.01 and pk.recall_backstop == nb + 1, "回收：超过兜底上限，新掉的经验直接入账")
	p2["gem_overflow"] = 400.0
	# 5）recall_after = 0 关闭回收
	p2["recall_after"] = 0.0
	var g2: Dictionary = mk.call("xp", far, 4.0)
	game.gems = [g2]
	step.call(10.0)
	ok(not g2.dead, "回收：recall_after = 0 时关闭")
	game.gems = keep_gems
	pk.recall_acc = 0.0
	if had:
		Bal._data["pickup"] = old
	else:
		Bal._data.erase("pickup")
