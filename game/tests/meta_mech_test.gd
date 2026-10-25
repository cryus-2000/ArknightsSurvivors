extends Node
## 认知塑造质变 / 非数值节点契约（docs/109 §14 v5，check.py 场景回归 meta_mech）：
##   godot --headless --path game res://tests/meta_mech_test.tscn -- --balance --seed=1 --op=wisadel --metanodes=sh1,reg3,atk5,hp5,def4,xp4,disp1,disp2,disp3,disp4
## 把 game.tscn 当子节点跑起来，第 5 帧直接调结算入口逐条检查：
##   护盾反震（危机感）：护盾被击碎时周围敌人受伤并被击退；低血回复翻倍（生命感悟Ⅲ）；处决（攻击性Ⅴ）：普通 <15% / 精英 <8% 直接击杀、Boss 不受；
##   濒死免死（生存本能Ⅴ）：每局一次保留 1 点并无敌；静守（自我保护Ⅳ）：连续 5 秒未受伤后下一击减半；升级再升（领导欲Ⅳ）：100 次升级里有再升；
##   开局四选一（多程信息处理）只在第一次升级；行商免费刷新（自我审视）每局一次；首个藏品三选一（战利品意识）开局自动打开；
##   末节质变（docs/152）：误入奇境补给箱不会是箱形恐鱼、打开给一次藏品三选一；收藏癖Ⅲ精英 / Boss 掉源石锭；交涉Ⅲ每次进店一件藏品打折。
## 全部通过时打印 "META MECH failures=0"。

const Game = preload("res://scripts/game.gd")
const Meta = preload("res://scripts/core/meta.gd")
const Bal = preload("res://scripts/core/balance.gd")   # 质变旋钮从 balance.json meta 段读，调数值不用改测试

var game: Node
var c
var frames := 0
var n := 0
var fails := 0
var relic_seen := false


func _ready() -> void:
	game = load("res://game.tscn").instantiate()
	add_child(game)


func ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		fails += 1
		printerr("FAIL: ", what)
		print("FAIL ", what)


func _process(_d: float) -> void:
	frames += 1
	if frames < 5:
		return
	if game.state == game.S.CHOICE and game.choice_kind == "relic":
		relic_seen = true
	if frames == 5:
		c = game.combat
		test_rules()
		test_shatter()
		test_low_regen()
		test_execute()
		test_calm()
		test_double_level()
		test_first_choice()
		test_free_refresh()
		test_capstones()
		# 濒死免死：第 5 帧把生命打到负数（回复在死亡判定之前结算，0 会被回复救回），下一帧的 _process 应保留 1 点（不进 DEAD）
		game.state = game.S.PLAY
		game.hp = -5.0
	elif frames == 6:
		ok(game.state != game.S.DEAD and game.hp >= 1.0 and game.rfx.rule("last_stand") == 0, "濒死免死：保留 1 点生命并用掉（state %d hp %.1f）" % [game.state, game.hp])
		ok(game.invuln >= Bal.v("meta/last_stand_inv", 1.5) - 0.5, "濒死免死：无敌（%.2f）" % game.invuln)
		# 绝处逢生：免死用掉后再次致命，复活并回到 50% 最大生命、3 秒无敌
		game.invuln = 0.0
		game.hp = -5.0
	elif frames == 7:
		ok(game.state != game.S.DEAD and game.rfx.rule("revive") == 0 and game.hp >= game.max_hp * (Bal.v("meta/revive_hp", 0.5) - 0.05), "绝处逢生：复活并回到设定比例的最大生命（state %d hp %.1f / %.1f）" % [game.state, game.hp, game.max_hp])
		ok(game.invuln >= Bal.v("meta/revive_inv", 3.0) - 0.5, "绝处逢生：无敌（%.2f）" % game.invuln)
		game.hp = game.max_hp
	elif frames == 120:
		ok(relic_seen or game.relics.size() > 0, "战利品意识：开局 1 秒后打开首个藏品三选一（见过 %s，藏品 %d）" % [relic_seen, game.relics.size()])
		ok(game.meta_start_relic == 0, "战利品意识：触发后清零")
		print("META MECH checks=%d failures=%d" % [n, fails])
		get_tree().quit(1 if fails > 0 else 0)


func spawn(type: String, off: Vector2) -> Dictionary:
	var e: Dictionary = game.spawner.spawn_enemy(type, game.ppos + off)
	e.hp = e.maxhp
	return e


func test_rules() -> void:
	for r in ["shield_shatter", "low_hp_regen", "execute", "last_stand", "calm_guard", "double_level", "first_choice_extra", "shop_free_refresh", "revive", "wonder_crate", "loot_ingot", "haggle"]:
		ok(game.rfx.rule(r) > 0, "开局写进 rfx.rules：" + r)
	ok(game.shield_max == 1, "危机感：护盾上限 1（%d）" % game.shield_max)
	ok(game.meta_start_relic == 3 or relic_seen or game.relics.size() > 0, "战利品意识：开局待选 3 件（%d，t=%.2f，见过 %s）" % [game.meta_start_relic, game.t, relic_seen])
	ok(Meta.leader_atk(game) > 0.0, "队长攻击基数 > 0（%.1f）" % Meta.leader_atk(game))


func test_shatter() -> void:
	var e: Dictionary = spawn("stone", Vector2(60, 0))
	var far: Dictionary = spawn("stone", Vector2(900, 0))
	game.enemies_sys.build_grid()   # 刚生成的敌人要进网格，query 才找得到
	var hp0: float = e.hp
	var kb0: Vector2 = e.kb
	game.shield = 1
	c.shield_block()
	ok(game.shield == 0, "护盾抵挡后层数 -1")
	ok(e.hp < hp0, "护盾反震：周围敌人受伤（%.1f → %.1f）" % [hp0, e.hp])
	ok(e.kb.x > kb0.x, "护盾反震：周围敌人被击退")
	ok(is_equal_approx(far.hp, far.maxhp), "护盾反震：140 外的敌人不受影响")
	for x in [e, far]:
		x.hp = 0.0
		c.kill(x)
	game.rfx.rules["shield_shatter"] = 0
	var e2: Dictionary = spawn("stone", Vector2(60, 0))
	game.enemies_sys.build_grid()
	game.shield = 1
	c.shield_block()
	ok(is_equal_approx(e2.hp, e2.maxhp), "没点危机感时护盾抵挡不反震")
	game.rfx.rules["shield_shatter"] = 1
	e2.hp = 0.0
	c.kill(e2)


func test_low_regen() -> void:
	game.hp = game.max_hp
	var full: float = c.regen_per_sec()
	game.hp = game.max_hp * 0.2
	var low: float = c.regen_per_sec()
	ok(full > 0.0 and is_equal_approx(low, full * Bal.v("meta/low_regen_mult", 2.0)), "生命感悟Ⅲ：生命低于 35%% 时回复放大（%.2f → %.2f）" % [full, low])
	game.hp = game.max_hp * 0.5
	ok(is_equal_approx(c.regen_per_sec(), full), "生命感悟Ⅲ：生命 50% 时不翻倍")
	game.hp = game.max_hp


func test_execute() -> void:
	var hd: Dictionary = c.make_hit("test")
	var e: Dictionary = spawn("stone", Vector2(300, 0))
	e.hp = e.maxhp * Bal.v("meta/execute_pct", 0.15) * 0.9
	c.damage(e, 0.5, hd)
	ok(e.dead, "处决：普通敌人低于阈值直接击杀")
	var e2: Dictionary = spawn("stone", Vector2(300, 100))
	e2.hp = e2.maxhp * 0.5
	c.damage(e2, 0.5, hd)
	ok(not e2.dead and e2.hp > e2.maxhp * 0.4, "处决：普通敌人 50% 不处决")
	e2.hp = 0.0
	c.kill(e2)
	var el: Dictionary = spawn("stone", Vector2(300, -100))
	el.elite = true
	el.hp = el.maxhp * Bal.v("meta/execute_elite_pct", 0.08) * 1.6
	c.damage(el, 0.5, hd)
	ok(not el.dead, "处决：精英高于阈值不处决")
	el.hp = el.maxhp * Bal.v("meta/execute_elite_pct", 0.08) * 0.9
	c.damage(el, 0.5, hd)
	ok(el.dead, "处决：精英低于阈值直接击杀")
	var b: Dictionary = game.spawner.spawn_enemy("knight_boss", game.ppos + Vector2(2000, 0))
	game.bosses.append(b)
	b.hp = b.maxhp * 0.05
	var bhp: float = b.hp
	c.damage(b, 0.5, hd)
	ok(not b.dead and b.hp > bhp * 0.5, "处决：Boss 不受")
	game.bosses.erase(b)
	b.hp = 0.0
	b.dead = true


func test_calm() -> void:
	game.dmg_src = "contact_test"
	game.in_type = ["近战", "真实"]
	game.invuln = 0.0
	game.rfx.calm_t = 0.0
	game.hp = game.max_hp
	c.enemy_hit(20.0, {}, true, true)
	var lost_n: float = game.max_hp - game.hp
	ok(game.rfx.calm_t == 0.0, "静守：受击后计时归零")
	game.hp = game.max_hp
	game.rfx.calm_t = 6.0
	c.enemy_hit(20.0, {}, true, true)
	var lost_c: float = game.max_hp - game.hp
	ok(lost_n > 0.0 and lost_c < lost_n * (Bal.v("meta/calm_mult", 0.5) + 0.1), "静守：5 秒未受伤后下一击减伤（%.1f → %.1f）" % [lost_n, lost_c])
	game.hp = game.max_hp


func test_double_level() -> void:
	var lv0: int = game.level
	var pend0: int = game.pending_levelups
	for i in 100:
		game.pickups.gain_xp(game.xp_need - game.xp)
	var extra: int = game.level - lv0 - 100
	ok(extra > 0 and extra < 40, "领导欲Ⅳ：100 次升级里再升 %d 次（概率 0.1）" % extra)
	ok(game.pending_levelups - pend0 == 100 + extra, "领导欲Ⅳ：再升的等级也给选卡")
	game.pending_levelups = 0
	game.lvup_delay = 0.0


func test_first_choice() -> void:
	game.progression.open_levelup()
	ok(game.state == game.S.CHOICE and game.choices.size() == 4, "多程信息处理：第一次升级四选一（%d）" % game.choices.size())
	ok(game.rfx.rule("first_choice_extra") == 0, "多程信息处理：用掉一次")
	game.state = game.S.PLAY
	game.progression.open_levelup()
	ok(game.choices.size() == 3, "多程信息处理：第二次升级回到三选一（%d）" % game.choices.size())
	game.state = game.S.PLAY
	game.choices = []


func test_free_refresh() -> void:
	game.merchant_idx = 1
	game.shop_sys.roll()
	game.shop_refreshed = false
	game.ingots = 0
	game.shop_sys.refresh()
	ok(game.shop_refreshed and game.ingots == 0 and game.rfx.rule("shop_free_refresh") == 0, "自我审视：没有源石锭也能刷新一次，不扣钱、用掉")
	game.shop_refreshed = false
	game.shop_sys.refresh()
	ok(not game.shop_refreshed, "自我审视：用掉后没钱就刷不了")
	game.state = game.S.PLAY


## docs/152 末节质变
func test_capstones() -> void:
	# 误入奇境：奇境补给箱不是箱形恐鱼，打碎后待开藏品选择 +1
	game.spawner.spawn_chest(game.ppos + Vector2(200, 0), "", true)
	var w: Dictionary = game.enemies[game.enemies.size() - 1]
	ok(w.get("wonder", false) and not w.hidden, "误入奇境：奇境补给箱（wonder %s，hidden %s）" % [w.get("wonder", false), w.hidden])
	var pc0: int = game.pending_chests
	w.hp = 0.0
	c.kill(w)
	ok(game.pending_chests == pc0 + 1, "误入奇境：打开后藏品三选一 +1（%d → %d）" % [pc0, game.pending_chests])
	game.pending_chests = pc0
	ok(not game.spawner.wonder_done, "误入奇境：开局还没刷（t=%.1f）" % game.t)
	# 收藏癖Ⅲ：同一种怪开 / 关规则各杀一只，掉落源石锭之差 = 精英 loot_elite、普通怪 0
	for elite in [false, true]:
		var cnt := []
		var st: int = game.rng_drop.state   # 两次击杀用同一段随机数（精英本身掉 3–5 个），差值只来自规则
		for on in [0, 1]:
			game.rng_drop.state = st
			game.rfx.rules["loot_ingot"] = on
			var e: Dictionary = spawn("stone", Vector2(400, 0))
			e.elite = elite
			var g0: int = game.gems.filter(func(x): return x.kind == "ingot").size()
			e.hp = 0.0
			c.kill(e)
			cnt.append(game.gems.filter(func(x): return x.kind == "ingot").size() - g0)
		var want: int = int(Bal.v("meta/loot_elite", 1.0)) if elite else 0
		ok(cnt[1] - cnt[0] == want, "收藏癖Ⅲ：%s 多掉源石锭 %d（应 %d）" % ["精英" if elite else "普通怪", cnt[1] - cnt[0], want])
	game.rfx.rules["loot_ingot"] = 1
	# 交涉Ⅲ：每次进店恰好一件藏品打折，价格 = 原价 × haggle_mult；买掉别的一件后折扣仍保留
	game.merchant_idx = 1
	game.merchant = {"purchases": 0}
	game.shop_sys.roll()
	var hs: Array = game.shop_items.filter(func(it): return it.get("haggle", false))
	ok(hs.size() == 1 and hs[0].kind == "relic", "交涉Ⅲ：一件藏品打折（%d 件）" % hs.size())
	if hs.size() == 1:
		var full: int = game.rfx.db.price(hs[0].id, game.shop_sys.price_mult())
		ok(hs[0].price == game.shop_sys.haggle_price(full) and hs[0].price < full, "交涉Ⅲ：折扣价 %d（原价 %d）" % [hs[0].price, full])
	game.merchant = {}
	game.shop_items.clear()
