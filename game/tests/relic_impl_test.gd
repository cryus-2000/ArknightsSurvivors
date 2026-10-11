extends Node
## 藏品第二批原语的局内测试（docs/57）：godot --headless --path game res://tests/relic_impl_test.tscn -- --regression --balance --seed=1 --op=siege --squad=saria,wisadel
## 把 game.tscn 当子节点跑起来，第 5 帧直接发藏品、调钩子，逐条检查每个新原语的数值效果（不推进整局）。
## 全部通过时打印 "RELIC IMPL failures=0"。

const Bal = preload("res://scripts/core/balance.gd")

var game: Node
var rfx
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
	rfx = game.rfx
	# 藏品携带上限（relic/carry_cap 15）对本测试不适用：一局里要发几十件
	Bal.v("relic/carry_cap", 15.0)
	if not Bal._data.has("relic"):
		Bal._data["relic"] = {}
	Bal._data["relic"]["carry_cap"] = 999
	test_batch_a()
	test_batch_b_c()
	test_batch_d_f()
	test_batch_g()
	test_batch_general()
	print("%d checks, %d failed" % [n, fails])
	print("RELIC IMPL failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		fails += 1
		printerr("FAIL: ", what)


func near(a: float, b: float, what: String, eps := 0.001) -> void:
	ok(absf(a - b) < eps, "%s（期望 %s，实际 %s）" % [what, b, a])


func grant(id: String) -> void:
	ok(game.progression.gain_relic(id), "获得藏品 %s" % id)


func op_of(cls: String):
	for o in game.squad.ops:
		if o.cls == cls:
			return o
	return null


func spawn(pos: Vector2) -> Dictionary:
	var e: Dictionary = game.spawner.spawn_enemy("runner", pos)
	game.enemies_sys.build_grid()
	return e


func reset_hp() -> void:
	game.hp = game.max_hp
	game.invuln = 0.0


## 批 A：hp_dmg / low_hp_haste / enemy_kb / boss_dmg / invuln / refund / temp 带职业 / 职业周期伤害 / 击杀回技力
func test_batch_a() -> void:
	var m0: float = rfx.dmg_extra()
	grant("124")
	reset_hp()
	near(rfx.dmg_extra() / m0, 1.3, "古乔治：满血全队伤害 ×1.3")
	game.hp = game.max_hp * 0.5
	near(rfx.dmg_extra() / m0, 1.15, "古乔治：半血 ×1.15")
	reset_hp()
	var h0: float = rfx.umbrella_interval_mult()
	grant("125")
	near(rfx.umbrella_interval_mult() / h0, 1.0, "紧急活性剂：满血不加速")
	game.hp = game.max_hp * 0.3
	near(rfx.umbrella_interval_mult() / h0, 1.0 / 1.6, "紧急活性剂：30% 生命时攻击间隔 ÷1.6")
	reset_hp()
	grant("167")
	near(game.enemy_kb_mult, 1.6, "锈刃-神力：击退倍率 1.6")
	grant("227")
	near(game.boss_mult, 1.5, "文明的存续：对 Boss 伤害 ×1.5")
	grant("166")
	game.invuln = 0.0
	rfx.on_dodge()
	ok(game.invuln >= 1.0, "可视静谧：闪避后无敌 ≥1 秒（%.2f）" % game.invuln)
	# 钝爪-熟稔：先锋技能返还 35%
	var van = op_of("先锋")
	ok(van != null, "编队里有先锋（--op=siege）")
	grant("135")
	if van != null:
		van.sp[0] = 0.0
		rfx.on_skill_start(van, 0)
		near(van.sp[0], van.sp_need(0) * 0.35, "钝爪-熟稔：先锋施放后返还 35%")
		var def = op_of("重装")
		if def != null:
			def.sp[0] = 0.0
			rfx.on_skill_start(def, 0)
			near(def.sp[0], 0.0, "钝爪-熟稔：重装不返还")
	# 铁卫-临时要塞：重装开技能 → 全队伤害 +50%、受到的伤害 -30%，5 秒后过期
	var def2 = op_of("重装")
	ok(def2 != null, "编队里有重装（saria）")
	grant("146")
	if def2 != null:
		var d0: float = rfx.dmg_extra()
		var t0: float = rfx.taken_mult()
		rfx.on_skill_start(def2, 0)
		near(rfx.dmg_extra() / d0, 1.5, "临时要塞：全队伤害 ×1.5")
		near(rfx.taken_mult() / t0, 0.7, "临时要塞：受到的伤害 ×0.7")
		game.t += 5.1
		rfx.tick(0.0)
		near(rfx.dmg_extra() / d0, 1.0, "临时要塞：5 秒后过期")
	# 尖刺之手：重装身边的敌人每秒受到法术伤害（藏品直接伤害计入 relic_out）
	grant("168")
	if def2 != null:
		var e: Dictionary = spawn(def2.pos + Vector2(40, 0))
		var hp0: float = e.hp
		rfx.tick(0.1)
		ok(e.hp < hp0, "尖刺之手：重装身边敌人掉血（%.1f → %.1f）" % [hp0, e.hp])
		e.dead = true
	# 积攒之手：先锋击杀回技力
	grant("173")
	if van != null:
		van.sp[0] = 0.0
		game.combat.hit("普攻")
		game.hit["class"] = "先锋"
		game.hit["op"] = van.id
		rfx.on_kill({"boss": false, "dead": false})
		near(van.sp[0], van.sp_need(0) * 0.03, "积攒之手：先锋击杀回 3% 技力")
	game.hit = {"src": "test", "emitter": "operator", "origin": "core", "range": "近战", "kind": "物理", "tags": [], "class": "", "op": ""}


## 批 B / C：on_gain sp + 招募回技力 / sp_pulse / stack_stat / 受击全屏真伤（冷却）/ 受重击晕眩 / 追击命中回技力
func test_batch_b_c() -> void:
	var van = op_of("先锋")
	if van == null:
		return
	var zero := func():
		for o in game.squad.ops:
			for i in 3:
				o.sp[i] = 0.0
	zero.call()
	grant("86")
	near(van.sp[0], van.sp_need(0) * 0.2, "高卢银行支票：获得时全队技力 +20%")
	zero.call()
	rfx.on_recruit(van)
	near(van.sp[0], van.sp_need(0) * 0.2, "高卢银行支票：招募入队时 +20%")
	zero.call()
	grant("91")
	rfx.tick(3.6)
	near(van.sp[0], van.sp_need(0) * 0.02, "摩根队长佳酿：3.5 秒后全队 +2% 技力")
	var sg0: float = game.stats.value(&"sp_gain")
	grant("176")
	rfx.on_skill_start(van, 0)
	rfx.on_skill_start(van, 0)
	near(game.stats.value(&"sp_gain") - sg0, 0.24, "永流之手：两次施放 +24% 技力回复")
	for k in 5:
		rfx.on_skill_start(van, 0)
	near(game.stats.value(&"sp_gain") - sg0, 0.48, "永流之手：最多 4 层")
	# 荣耀套餐：受到 ≥10% 最大生命的伤害时周围晕眩
	grant("233")
	var e: Dictionary = spawn(game.ppos + Vector2(60, 0))
	e.stun = 0.0
	rfx.on_hurt(false, game.max_hp * 0.05)
	near(e.stun, 0.0, "荣耀套餐：5%% 的伤害不触发" % [])
	rfx.on_hurt(false, game.max_hp * 0.2)
	ok(e.stun >= 3.0 * game.control_mult - 0.001, "荣耀套餐：20%% 的伤害周围晕眩 3 秒（%.2f）" % e.stun)
	# 碎片大厦的回忆：全屏真伤，30 秒冷却
	grant("232")
	e.maxhp = 100000.0
	e.hp = e.maxhp
	var hp0: float = e.hp
	rfx.on_hurt(false, 1.0)
	ok(e.hp < hp0, "碎片大厦：受击后全场真实伤害（%.1f → %.1f）" % [hp0, e.hp])
	var hp1: float = e.hp
	rfx.on_hurt(false, 1.0)
	near(e.hp, hp1, "碎片大厦：冷却内不再触发")
	game.t += 31.0
	rfx.on_hurt(false, 1.0)
	ok(e.hp < hp1, "碎片大厦：30 秒后再次触发")
	e.dead = true
	# 衍生者终端：追击命中回技力（有每秒上限）
	zero.call()
	grant("130")
	var e2: Dictionary = spawn(game.ppos + Vector2(80, 0))
	var h := {"src": "t", "emitter": "operator", "origin": "core", "range": "近战", "kind": "物理", "tags": ["follow_up"], "class": "先锋", "op": van.id}
	rfx.on_hit(e2, h)
	near(van.sp[0], van.sp_need(0) * 0.002, "衍生者终端：追击命中 +0.2% 技力")
	for k in 20:
		rfx.on_hit(e2, h)
	near(van.sp[0], van.sp_need(0) * 0.01, "衍生者终端：每秒最多 1%")
	e2.dead = true


## 批 D / F：敌人移速、按遭诅古物件数生效（per_relic 带 rarity）
func test_batch_d_f() -> void:
	grant("230")
	near(game.enemy_speed_mult, 0.85, "苦痛的快乐：敌人移速 ×0.85")
	var t0: float = game.stats.value(&"dmg_taken")
	grant("253")
	near(game.stats.value(&"dmg_taken") - t0, 0.0, "蓝卡坞安全衣：没有遭诅古物时无效果")
	grant("216")
	near(game.stats.value(&"dmg_taken") - t0, -0.08, "蓝卡坞安全衣：1 件遭诅古物 -8%")
	grant("218")
	near(game.stats.value(&"dmg_taken") - t0, -0.16, "蓝卡坞安全衣：2 件 -16%")
	var a0: float = game.stats.value(&"op_aspd")
	grant("254")
	near(game.stats.value(&"op_aspd") - a0, 0.3, "刀光剑影：2 件遭诅古物攻速 +30%")


## 批 G：距离增伤、编队人数缩放、招募事件（职业 / 一次性）、招募加选项、支援装置、急救包、按藏品数的职业加成、多次成长
func test_batch_g() -> void:
	var sn = op_of("狙击")
	ok(sn != null, "编队里有狙击（wisadel）")
	grant("104")
	if sn != null:
		var e: Dictionary = spawn(sn.pos + Vector2(600, 0))
		var h := {"src": "t", "emitter": "operator", "origin": "core", "range": "远程", "kind": "物理", "tags": [], "class": "狙击", "op": sn.id}
		near(rfx.hit_mult(h, e), 1.5, "Scout的狙击镜：600 外远程命中 ×1.5")
		e.pos = sn.pos + Vector2(150, 0)
		near(rfx.hit_mult(h, e), 1.25, "Scout的狙击镜：150 处 ×1.25")
		h.range = "近战"
		near(rfx.hit_mult(h, e), 1.0, "Scout的狙击镜：近战不加成")
		e.dead = true
	var t0: float = game.stats.value(&"dmg_taken")
	grant("180")
	near(game.stats.value(&"dmg_taken") - t0, -0.03 * game.squad.size(), "地形图：按编队人数 -3%% / 人（%d 人）" % game.squad.size())
	# 招募事件：残弩-突破只对狙击、一份演讲稿只一次、地区行动方案给源石锭、人事部密信给三选一
	grant("147")
	grant("187")
	grant("184")
	grant("186")
	var van = op_of("先锋")
	var ig0: int = game.ingots
	var pl0: int = game.pending_levelups
	var p0: int = sn.prog if sn != null else 0
	if sn != null:
		rfx.on_recruit(sn)
		ok(sn.prog == p0 + 2, "残弩-突破 + 演讲稿：狙击入队推进 2 个节点（%d → %d）" % [p0, sn.prog])
	ok(game.ingots == ig0 + 10, "地区行动方案：招募 +10 源石锭")
	ok(game.pending_levelups == pl0 + 1, "人事部密信：招募 +1 次成长三选一")
	if van != null:
		var vp: int = van.prog
		rfx.on_recruit(van)
		ok(van.prog == vp, "残弩-突破不对先锋生效、演讲稿只一次（%d → %d）" % [vp, van.prog])
	game.pending_levelups = pl0
	grant("189")
	ok(rfx.rule("recruit_extra") == 1, "罗德岛战术电台：招募加选项规则")
	grant("11")
	ok(rfx.rule("choice_extra") == 1, "源石鸢尾花：下一次三选一加选项")
	ok(rfx.take_choice_extra() == 1 and rfx.take_choice_extra() == 0, "加选项只用一次")
	# 支援装置：补给站掉药剂、轰隆隆自爆、起重机束缚精英、防暴桩减速
	var gems0: int = game.gems.size()
	grant("209")
	game.t += 60.0
	rfx.tick(60.5)
	ok(game.gems.size() > gems0, "支援补给站：60 秒后身边掉落药剂")
	grant("211")
	rfx.tick(45.5)
	ok(rfx.bombs.size() == 1, "支援轰隆隆：45 秒后派出一台")
	var e3: Dictionary = spawn(game.ppos + Vector2(60, 40))
	e3.maxhp = 100000.0
	e3.hp = e3.maxhp
	for k in 120:
		rfx.tick(1.0 / 60.0)
	ok(rfx.bombs.is_empty() and e3.hp < e3.maxhp, "支援轰隆隆：撞上敌人自爆并造成伤害（%.0f）" % (e3.maxhp - e3.hp))
	grant("212")
	e3.stun = 0.0
	e3.elite = true
	rfx.tick(30.5)
	ok(e3.stun >= 3.0 * game.control_mult - 0.001, "支援起重机：吊起精英束缚 3 秒（%.2f）" % e3.stun)
	grant("213")
	rfx.tick(30.5)
	ok(rfx.stakes.size() == 2, "支援防暴桩：放下 2 根")
	e3.dead = true
	# 急救包：低于 30% 自动用，最多 3 个
	grant("214")
	for k in 4:
		game.hp = game.max_hp * 0.2
		rfx.tick(0.1)
	near(game.hp, game.max_hp * 0.2, "支援急救包：3 个用完后不再回复")
	ok(rfx.medkits.get("214", -1) == 0, "支援急救包：剩 0 个")
	reset_hp()
	# 断杖-学识：每件藏品术师 +2%
	var n0: int = game.relics.size()
	var d0: float = game.stats.value_for(&"dmg", ["class:术师"])
	grant("256")
	near(game.stats.value_for(&"dmg", ["class:术师"]) - d0, 0.02 * (n0 + 1), "断杖-学识：%d 件藏品 → 术师 +%d%%" % [n0 + 1, 2 * (n0 + 1)])
	near(game.stats.value_for(&"dmg", ["class:先锋"]) - d0, 0.0, "断杖-学识：只对术师")
	var pl1: int = game.pending_levelups
	grant("178")
	ok(game.pending_levelups == pl1 + 2, "摸摸券：+2 次成长三选一")
	game.pending_levelups = pl1


## 通用批：旗帜区域、升级限时攻速、精英减伤、远程间隔、钥匙、灯火流失、未受伤回灯火、升级、随机藏品、排异解除 / 免疫、无视防御、击败 Boss
func test_batch_general() -> void:
	grant("117")
	rfx.tick(0.1)
	var z: Dictionary = rfx.zones.get("117", {})
	ok(not z.is_empty() and z.pos != Vector2.INF, "遗落之帜：出现旗帜")
	var d0: float = rfx.dmg_extra()
	var h0: float = rfx.umbrella_interval_mult()
	var keep: Vector2 = game.ppos
	game.ppos = z.pos
	near(rfx.dmg_extra() / d0, 1.5, "遗落之帜：旗帜旁全队伤害 ×1.5")
	near(rfx.umbrella_interval_mult() / h0, 1.0 / 1.5, "遗落之帜：旗帜旁攻击间隔 ÷1.5")
	game.ppos = keep
	near(rfx.dmg_extra() / d0, 1.0, "遗落之帜：离开后无加成")
	grant("122")
	rfx.on_levelup(1)
	near(rfx.umbrella_interval_mult() / h0, 1.0 / 1.4, "疗养体验卡：升级后攻击间隔 ÷1.4")
	game.t += 10.1
	rfx.tick(0.0)
	near(rfx.umbrella_interval_mult() / h0, 1.0, "疗养体验卡：10 秒后过期")
	grant("113")
	near(game.elite_taken_mult, 0.6, "王庭盟约：精英伤害 ×0.6")
	grant("119")
	near(game.enemy_ranged_cd_mult, 1.35, "捕鳞蓑：远程开火间隔 ×1.35")
	grant("194")
	ok(rfx.rule("chest_keys") == 3, "三钥协定：钥匙 3 把")
	ok(not game.spawner._mimic_roll(""), "三钥协定：钥匙期间不出箱形恐鱼")
	grant("249")
	near(game.lamp_loss_mult, 0.6, "凝固灯油：灯火流失 ×0.6")
	grant("247")
	game.lamp = 50.0
	rfx.tick(60.5)
	near(game.lamp, 56.0, "地底的灼痕：60 秒未受伤灯火 +6")
	rfx.on_hurt(false, 1.0)
	near(rfx.unhurt.get("247", -1.0), 0.0, "地底的灼痕：受伤后重新计时")
	var lv0: int = game.level
	var pl0: int = game.pending_levelups
	grant("76")
	ok(game.level == lv0 + 1 and game.pending_levelups == pl0 + 1, "人偶之家：立即升 1 级（%d → %d）" % [lv0, game.level])
	game.pending_levelups = pl0
	var n0: int = game.relics.size()
	grant("206")
	ok(game.relics.size() == n0 + 2, "大教堂拼图：随机多得 1 件（%d → %d）" % [n0, game.relics.size()])
	ok(game.RL[game.relics[-1]].rarity == "基础", "大教堂拼图：得到的是基础藏品（%s）" % game.RL[game.relics[-1]].name)
	# 排异：失败的标本给一次 → 达里奥的提灯解除并免疫下一次
	var rc0: int = game.doctor.rej_count
	grant("217")
	ok(game.doctor.rej_count == rc0 + 1, "失败的标本：一次排异反应")
	var had := false
	for o in game.squad.ops:
		if not o.rej.is_empty():
			had = true
	grant("201")
	var still := false
	for o in game.squad.ops:
		if not o.rej.is_empty():
			still = true
	ok(not had or not still, "达里奥的提灯：解除排异")
	ok(rfx.rule("rej_immune") == 1, "达里奥的提灯：免疫 1 次")
	ok(game.doctor.apply_rejection() == "已被抑制" and rfx.rule("rej_immune") == 0, "达里奥的提灯：下一次排异被抑制并用掉")
	grant("262")
	ok(rfx.rule("def_pierce") == 35 and rfx.rule("rej_immune") >= 99, "养育者基因种：无视防御 35%、免疫排异")
	# 击败 Boss：立体艺术装置回血、国王的水晶扣血 + 源石锭 + 三选一、判官经文布加选项
	grant("192")
	grant("251")
	grant("196")
	game.hp = game.max_hp * 0.5
	var ig0: int = game.ingots
	pl0 = game.pending_levelups
	rfx.on_kill({"boss": true, "dead": false})
	ok(game.ingots == ig0 + 15, "国王的水晶：击败 Boss +15 源石锭")
	ok(game.pending_levelups == pl0 + 1, "国王的水晶：击败 Boss 一次成长三选一")
	ok(rfx.rule("choice_extra") >= 2, "判官经文布：击败 Boss 后 2 次加选项")
	ok(game.hp > game.max_hp * 0.44 and game.hp < game.max_hp * 0.52, "立体艺术装置 + 国王的水晶：失去 20%% 当前生命再回约 10%%（%.1f%% 最大生命）" % (100.0 * game.hp / game.max_hp))
	game.pending_levelups = pl0
	reset_hp()
