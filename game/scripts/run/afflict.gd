extends RefCounted
## 负面状态门面（架构评审 10-29 §③ 风险 4）：神经损伤 / 侵蚀 / 侵蚀创口的累积、结算、清除都经这里，
## 为后续「侵蚀 + 溟痕并进神经损伤」做准备（合并本身没做）。字段仍挂在 g 上（g.nerve / g.nerve_lock / g.corrode_pool / g.wound，
## HUD、世界层、遥测照读），只是写入口收到这里；单发上限、2 秒合计、满血保护仍在 combat（lose_hp → _boss_clamp）。
##
## 份额记账：nerve_boss = g.nerve 里由 Boss 来源（Boss 溟痕）累积的那部分，其余算普通（自然 / 小怪溟痕、巢涌者 / 箱形恐鱼光环、命中附带）。
## 侵蚀池同理已有 combat.corrode_boss。满格那一下真伤按份额定来源：Boss 份额 ≥ AFFLICT_BOSS_SHARE 时当 Boss 来源走主控保护
## （以前没走，Boss 溟痕满条的 12% 真伤绕过 leader_hit_cap / 2 秒合计 / 满血保护）。

const Bal = preload("res://scripts/core/balance.gd")

const BOSS_SHARE := 0.5   # 神经损伤满格时 Boss 份额达到这个比例，真伤按 Boss 来源结算

const Game = preload("res://scripts/game.gd")
var g: Game
var nerve_boss := 0.0     # g.nerve 里的 Boss 份额（0..g.nerve）


func _init(game: Game) -> void:
	g = game


## ---- 神经损伤
func nerve_max() -> float:
	return Bal.v("enemy/nerve_max", 100.0)


## v > 0 累积；boss = 这笔来自 Boss 来源。满格：清零、锁 nerve_lock 秒、眩晕、一次真伤（最大生命 × nerve_burst）
func add_nerve(v: float, boss := false) -> void:
	var c = g.combat
	if v <= 0.0 or g.nerve_lock > 0.0:
		return
	g.nerve += v
	if boss:
		nerve_boss += v
	if g.nerve >= nerve_max():
		var as_boss: bool = nerve_boss >= BOSS_SHARE * g.nerve
		g.nerve = 0.0
		nerve_boss = 0.0
		g.nerve_lock = Bal.v("enemy/nerve_lock", 5.0)
		if not c.stun_as_slow():
			c.add_root(Bal.v("enemy/nerve_stun", 1.2), "眩晕")
		g.dmg_src = "nerve"
		g.in_type = ["近战", "真实"]
		c.hurt(g.max_hp * Bal.v("enemy/nerve_burst", 0.12), true, as_boss)
		Sfx.play("nerve_burst", 2.0, 1.0, 0.0)   # 神经电击 + 耳鸣（和冻结的冰、束缚的锁链区分）
		g.vfx.add_text(g.ppos + Vector2(0, -100), "神经损伤！", Color(1.0, 0.5, 0.9), 20)
		Sfx.play("skill", -4.0, 1.6)


## 每帧（enemies.update_status）：in_src = 站在溟痕里（不含流明光域）；sanct = 在流明光域里；boss_mire = 脚下只有 Boss 溟痕（没有自然溟痕、没有光环）
## mire_mult：只站在溟痕里（没有神经光环）时的累积倍率（灯火高时自然溟痕减免，docs/147；缺省 1）
func update_nerve(dt: float, in_src: bool, sanct: bool, mire_mult := 1.0, boss_mire := false) -> void:
	g.nerve_lock = maxf(0.0, g.nerve_lock - dt)
	var aura: bool = g.nerve_aura_t > 0.0 and not sanct
	g.nerve_aura_t = maxf(0.0, g.nerve_aura_t - dt)
	var aura_k: float = g.nerve_aura_k
	g.nerve_aura_k = 1.0   # 箱形恐鱼尖叫每帧重设；其他光环不带倍率
	if ((in_src and not sanct) or aura) and g.nerve_lock <= 0.0:
		g.telemetry.on_status("nerve", "" if in_src else g.telemetry.aura_type, dt)   # 溟痕 = 环境；神经光环 = 放光环的敌人
		add_nerve(Bal.v("enemy/nerve_mire", 12.0) * float(g.dmod.get("nerve_rate", 1.0)) * g.nerve_taken_mult * (aura_k if aura else mire_mult) * dt,
			boss_mire and not aura)
	else:
		var before: float = g.nerve
		g.nerve = maxf(0.0, g.nerve - Bal.v("enemy/nerve_decay", 10.0) * (2.0 if sanct else 1.0) * dt)
		_shrink_boss(before)


## 净化：清空 / 削去神经损伤（流明、技能、信标、武器…）
func clear_nerve() -> void:
	g.nerve = 0.0
	nerve_boss = 0.0


func cut_nerve(amount: float) -> void:
	var before: float = g.nerve
	g.nerve = maxf(0.0, g.nerve - amount)
	_shrink_boss(before)


## 总量下降后 Boss 份额按比例缩（先扣先后不分来源）
func _shrink_boss(before: float) -> void:
	if nerve_boss <= 0.0:
		return
	nerve_boss = nerve_boss * g.nerve / before if before > 0.0 and g.nerve > 0.0 else 0.0


## ---- 侵蚀（侵蚀池 g.corrode_pool；Boss 份额记在 combat.corrode_boss）
## 命中追加：dmg × 来源侵蚀系数 × corrode_mult × 难度修正；boss = Boss 来源（进主控保护的上限 / 2 秒合计 / 满血保护）；lost = 这一发实际扣的血
func add_corrode(dmg: float, k: float, boss: bool, lost: float) -> void:
	var c = g.combat
	var add: float = dmg * k * Bal.v("enemy/corrode_mult", 1.0) * g.corrode_taken_mult
	c._boss_pool()   # 池子被清空过（流明净化）时先把 Boss 部分截到池子以内，免得这次追加的普通侵蚀被当成 Boss 的
	# 非 Boss 侵蚀池上限（用户 9/27 方案 3-B，数值旋钮 enemy/corrode_pool_cap，缺省 0 = 不封顶）：池里非 Boss 部分 ≤ 最大生命 × 上限，超出的新增作废；流出速度不变
	var ncap: float = Bal.v("enemy/corrode_pool_cap", 0.3)
	if not boss and ncap > 0.0:
		add = clampf(add, 0.0, maxf(0.0, ncap * g.max_hp - (g.corrode_pool - c.corrode_boss)))
	if boss:
		# 侵蚀算进上限：追加进侵蚀池的量 ≤ 单发上限 − 这一发实际扣的血，并计入 2 秒合计（窗口满了就作废）；满血保护也管追加的侵蚀。
		# 另外池里的 Boss 侵蚀合计 ≤ boss/corrode_pool_cap：Boss 在场时它的流出被封顶，不封池子会越攒越多，Boss 一死集中流出
		var mh: float = g.max_hp
		var room: float = minf(Bal.v("boss/leader_hit_cap", 0.40) * mh - lost, Bal.v("boss/leader_2s_cap", 0.68) * mh - c._window_sum(c.boss_log, 2.0))
		room = minf(room, Bal.v("boss/corrode_pool_cap", 0.40) * mh - c.corrode_boss)
		add = c._guard(clampf(add, 0.0, maxf(0.0, room)))
		if add > 0.0:
			c.boss_log.append([g.t, add])
			c.corrode_boss += add
	g.corrode_pool += add
	if add > 0.0:
		g.telemetry.on_status("corrode", g.telemetry.hit_type, add)
		g.vfx.add_text(g.ppos + Vector2(14, -64), "侵蚀", Color(0.8, 0.5, 1.0), 13)


## 每帧结算：池子按 (池 × 0.5 + 1) × dt 流出（Boss 份额的流出与封顶在 combat.drain_corrode）
func tick_corrode(dt: float) -> void:
	if g.corrode_pool > 0.0:
		var tick: float = min(g.corrode_pool, (g.corrode_pool * 0.5 + 1.0) * dt)
		g.combat.drain_corrode(tick)


## 净化：清空侵蚀池（Boss 份额由 combat._boss_pool 惰性截到池子以内）
func clear_corrode() -> void:
	g.corrode_pool = 0.0


## ---- 侵蚀创口（g.wound 层数 + g.wound_t 剩余秒数）：减受治疗 + 每秒掉血
func add_wound(n: int) -> void:
	if n <= 0:
		return
	g.wound = mini(g.wound + n, int(Bal.v("enemy/wound_max", 3.0)))
	g.wound_t = Bal.v("enemy/wound_dur", 6.0)


func tick_wound(dt: float) -> void:
	if g.wound > 0:
		g.combat.lose_hp(g.max_hp * Bal.v("enemy/wound_dot", 0.0025) * g.wound * dt, "wound")
		g.wound_t -= dt
		if g.wound_t <= 0.0:
			g.wound = 0
			g.wound_t = 0.0


## 受治疗倍率里的创口项（combat.heal / pickups 补给共用）
func wound_heal_mult() -> float:
	return maxf(0.0, 1.0 - Bal.v("enemy/wound_heal_cut", 0.10) * g.wound)
