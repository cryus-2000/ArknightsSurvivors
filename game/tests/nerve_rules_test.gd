extends Node
## 神经损伤积累规则的特征测试（arch_review_1029 §1.3 / P1-4；为后续 afflict 门面重构兜底，规则改了要同步改这里）：
##   godot --headless --path game res://tests/nerve_rules_test.tscn -- --regression --balance --seed=1 --op=skadi --squad=kaltsit
## 固定的现行规则（combat.update_nerve / add_nerve、enemies.update_status）：
##   · 站在溟痕里（不在流明光域内）且没在锁定期：每秒 +enemy/nerve_mire(12) × 难度 nerve_rate × nerve_taken_mult × 倍率；否则每秒 −enemy/nerve_decay(10)（光域内 ×2）；
##   · 倍率：站在神经光环里（nerve_aura_t>0 且不在光域）用光环倍率 nerve_aura_k，不在溟痕里也累积；只站溟痕用 mire_mult（灯火退散，仅自然溟痕）；
##   · 满 nerve_max(100)：清零、锁定 enemy/nerve_lock(5) 秒（期间不累积）、队长掉 最大生命 × enemy/nerve_burst(0.12) 的真伤（hurt(…, true)，忽略护甲）；
##   · 普通怪 vs Boss：积累量本身不分来源——自然溟痕与 Boss 溟痕同速；区别只有 ① 灯火退散只对自然溟痕生效（Boss 溟痕不减），
##     ② 满条的真伤走 hurt(amount, true) 而不是 boss = true，所以不经过 Boss 主控保护截断（_boss_clamp）。
##   · 灯火档位：lamp/mire_ward_r = 0 时灯火不影响积累；现行缺省 200 / mire_ward_dmg 0.8 是开着的（x = (灯火−mire_lo)/(mire_hi−mire_lo) 夹到 0..1），自然溟痕里倍率 = 1 − mire_ward_dmg × x（灯火 ≥70 → ×0.2，≤30 → ×1）。
## 标 [已知缺陷] 的是 P1-4 要修的现状（Boss 来源的满条真伤不受 Boss 保护截断、积累没有 Boss / 普通份额记账），修复时翻转。
## 全部通过打印 "NERVE RULES failures=0"。
const Bal = preload("res://scripts/core/balance.gd")
var game: Node
var frames := 0
var n := 0
var fails := 0


func _ready() -> void:
	game = load("res://game.tscn").instantiate()
	add_child(game)


func ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		fails += 1
		printerr("FAIL: ", what)


func near(a: float, b: float, what: String) -> void:
	ok(absf(a - b) < 1e-4, "%s（实得 %.5f，应为 %.5f）" % [what, a, b])


func reset() -> void:
	var g = game
	g.nerve = 0.0
	g.nerve_lock = 0.0
	g.nerve_aura_t = 0.0
	g.nerve_aura_k = 1.0
	g.nerve_taken_mult = 1.0
	g.dmod["nerve_rate"] = 1.0


func _process(_d: float) -> void:
	frames += 1
	if frames != 5:
		return
	var g = game
	g.set_process(false)
	Bal.v("enemy/nerve_mire", 12.0)   # 先触发载入，再覆盖旋钮
	var bal_save: Dictionary = Bal._data.duplicate(true)
	var c = g.combat
	var rate: float = Bal.v("enemy/nerve_mire", 12.0)
	var decay: float = Bal.v("enemy/nerve_decay", 10.0)
	var dt := 0.1
	g.mires.clear()
	g.enemies.clear()
	g.bosses.clear()

	# ---- 基本累积 / 衰减
	reset()
	c.update_nerve(dt, true, false)
	near(g.nerve, rate * dt, "溟痕里每秒 +nerve_mire")
	c.update_nerve(dt, false, false)
	near(g.nerve, rate * dt - decay * dt, "离开溟痕每秒 −nerve_decay")
	reset()
	g.nerve = 50.0
	c.update_nerve(1.0, false, true)
	near(g.nerve, 50.0 - decay * 2.0, "流明光域里衰减 ×2")
	reset()
	g.nerve = 30.0
	c.update_nerve(1.0, true, true)
	near(g.nerve, 30.0 - decay * 2.0, "溟痕 + 光域：不累积，按光域衰减")
	reset()
	c.update_nerve(1.0, false, false)
	near(g.nerve, 0.0, "衰减不为负")

	# ---- 倍率：难度 nerve_rate、卡片 nerve_taken_mult、溟痕倍率 mire_mult
	reset()
	g.dmod["nerve_rate"] = 1.5
	c.update_nerve(1.0, true, false)
	near(g.nerve, rate * 1.5, "难度 nerve_rate ×1.5")
	reset()
	g.nerve_taken_mult = 0.5
	c.update_nerve(1.0, true, false)
	near(g.nerve, rate * 0.5, "nerve_taken_mult ×0.5")
	reset()
	c.update_nerve(1.0, true, false, 0.25)
	near(g.nerve, rate * 0.25, "只站溟痕：mire_mult ×0.25")

	# ---- 神经光环：不在溟痕里也累积；用 aura_k，不用 mire_mult；光域内无效；每帧读后复位
	reset()
	g.nerve_aura_t = 1.0
	g.nerve_aura_k = 2.0
	c.update_nerve(1.0, false, false, 0.25)
	near(g.nerve, rate * 2.0, "光环里（不在溟痕）累积，倍率 = aura_k，不吃 mire_mult")
	near(g.nerve_aura_k, 1.0, "aura_k 读后复位为 1")
	near(g.nerve_aura_t, 0.0, "aura_t 按 dt 递减")
	reset()
	g.nerve_aura_t = 1.0
	g.nerve_aura_k = 2.0
	c.update_nerve(0.5, true, false, 0.25)
	near(g.nerve, rate * 2.0 * 0.5, "光环 + 溟痕同时：只算光环倍率一次（不叠 mire_mult）")
	reset()
	g.nerve_aura_t = 1.0
	g.nerve_aura_k = 2.0
	g.nerve = 40.0
	c.update_nerve(1.0, false, true)
	near(g.nerve, 40.0 - decay * 2.0, "光环 + 光域：光域压住光环")

	# ---- 满条：清零、锁定、真伤、锁定期不累积
	reset()
	g.hp = g.max_hp
	var burst: float = Bal.v("enemy/nerve_burst", 0.12)
	var lock_s: float = Bal.v("enemy/nerve_lock", 5.0)
	c.add_nerve(c.nerve_max() + 1.0)
	near(g.nerve, 0.0, "满条清零")
	near(g.nerve_lock, lock_s, "满条锁定 nerve_lock 秒")
	near(g.max_hp - g.hp, g.max_hp * burst, "满条真伤 = 最大生命 × nerve_burst（无 Boss）")
	var hp1: float = g.hp
	c.add_nerve(50.0)
	near(g.nerve, 0.0, "锁定期 add_nerve 无效")
	c.update_nerve(1.0, true, false)
	near(g.nerve, 0.0, "锁定期溟痕里也不累积（走衰减支路）")
	near(g.nerve_lock, lock_s - 1.0, "锁定计时递减")
	near(g.hp, hp1, "锁定期不再掉血")
	c.update_nerve(lock_s, true, false)
	c.update_nerve(1.0, true, false)
	ok(g.nerve > 0.0, "锁定结束后恢复累积")

	# ---- Boss 来源 [已知缺陷]：满条真伤不经 Boss 主控保护截断，也没有 Boss / 普通份额记账
	reset()
	Bal._data["boss"]["leader_hit_cap"] = 0.01
	var b: Dictionary = g.spawner.spawn_enemy("paranoia", g.ppos + Vector2(900, 0))
	g.bosses.append(b)
	ok(g.spawner.boss_alive(), "Boss 在场")
	g.hp = g.max_hp
	var cb0: float = c.corrode_boss
	c.add_nerve(c.nerve_max() + 1.0)
	near(g.max_hp - g.hp, g.max_hp * burst, "[已知缺陷] Boss 在场且单发上限 1%：神经损伤满条仍掉 12%（未经 _boss_clamp）")
	near(c.corrode_boss, cb0, "[已知缺陷] 满条不记 Boss 份额（corrode_boss 不变）")
	g.enemies.erase(b)
	g.bosses.erase(b)
	Bal._data = bal_save.duplicate(true)
	g.enemies.clear()
	g.bosses.clear()

	# ---- 灯火档位（经 enemies.update_status，自然溟痕 vs Boss 溟痕）
	var es = g.enemies_sys
	reset()
	var save_lamp: float = g.lamp
	g.squad.ops.size()   # 触发一次读取，保证编队存在（update_status 里问光域）
	# lamp/mire_ward_r = 0：灯火不影响积累速度
	Bal._data["lamp"]["mire_ward_r"] = 0.0
	for lv in [100.0, 50.0, 10.0]:
		reset()
		g.lamp = lv
		g.mires.clear()
		g.mires.append({"pos": g.ppos, "r": 300.0, "maxr": 300.0, "maxr0": 300.0, "life": 1.0e9})
		es.update_status(dt)
		near(g.nerve, rate * dt, "lamp/mire_ward_r = 0：灯火 %d 不改变积累速度" % int(lv))
	# 现行缺省（balance.json：mire_ward_r 200 / mire_ward_dmg 0.8 / mire_lo 30 / mire_hi 70）：自然溟痕按 1 − ward_dmg × x，Boss 溟痕不减
	Bal._data = bal_save.duplicate(true)
	var wd: float = Bal.v("lamp/mire_ward_dmg", 0.0)
	var lo: float = Bal.v("lamp/mire_lo", 30.0)
	var hi: float = Bal.v("lamp/mire_hi", 70.0)
	ok(Bal.v("lamp/mire_ward_r", 0.0) > 0.0 and wd > 0.0, "缺省灯火退散是开着的（ward_r / ward_dmg > 0）：%s / %s" % [Bal.v("lamp/mire_ward_r", 0.0), wd])
	for lv in [100.0, hi, (lo + hi) * 0.5, lo, 10.0]:
		var x := clampf((lv - lo) / maxf(1.0, hi - lo), 0.0, 1.0)
		reset()
		g.lamp = lv
		g.mires.clear()
		g.mires.append({"pos": g.ppos, "r": 300.0, "maxr": 300.0, "maxr0": 300.0, "life": 1.0e9})
		es.update_status(dt)
		near(g.nerve, rate * dt * (1.0 - wd * x), "灯火 %d（退散强度 x=%.2f）：自然溟痕积累 ×%.2f" % [int(lv), x, 1.0 - wd * x])
	reset()
	g.lamp = 100.0
	g.mires.clear()
	g.mires.append({"pos": g.ppos, "r": 300.0, "maxr": 300.0, "maxr0": 300.0, "life": 1.0e9, "boss": true})
	es.update_status(dt)
	near(g.nerve, rate * dt, "灯火 100：Boss 溟痕不吃灯火退散（×1）")
	g.mires.clear()
	g.lamp = save_lamp
	Bal._data = bal_save
	reset()
	print("%d checks, %d failed" % [n, fails])
	print("NERVE RULES failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
