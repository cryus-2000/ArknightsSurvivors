extends Node
## 看得见的成长节点 + 精英化时刻回归（docs/245）：
##   godot --headless --path game res://tests/vis_nodes_test.tscn -- --regression --balance --seed=1 --op=texas --squad=exusiai,kaltsit --bal=growth/visible_nodes=1 --bal=growth/elite_show=1
## 校验：普通节点不再加攻击 +6%，按流派加范围（德克萨斯）/ 弹数（能天使）/ 体量（凯尔希）；精二本人攻击 +12%、攻速 +6%，全队效果挂上、离队撤销；
## 卡面写出这一项；精英化时刻：入队、平衡模式不挡弹窗、玩家局定格挡住、定格结束放行；偏红的本人颜色调淡。全部通过时打印 "VIS NODES failures=0"

const Bal = preload("res://scripts/core/balance.gd")
const VN = preload("res://scripts/characters/blocks/vis_nodes.gd")
const EM = preload("res://scripts/run/elite_moment.gd")

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


func v(o, st: StringName) -> float:
	return game.stats.value_for(st, o.scopes())


func _process(_d: float) -> void:
	frames += 1
	if frames != 5:
		return
	set_process(false)
	game.set_process(false)
	game.pending_levelups = 0
	game.pending_chests = 0
	game.show_queue.clear()
	ok(VN.on(game) and EM.on(game), "两个开关都开着（--bal）")
	ok(is_equal_approx(game.enemy_hp_mult, VN.kn("enemy_hp", 1.0)), "怪物生命补偿已乘上（%.2f）" % game.enemy_hp_mult)
	var tx = game.squad.get_op("texas")
	var ex = game.squad.get_op("exusiai")
	var ks = game.squad.get_op("kaltsit")
	ok(tx != null and ex != null and ks != null, "编队：德克萨斯 / 能天使 / 凯尔希")
	ok(VN.lane(tx) == "melee" and VN.lane(ex) == "multi" and VN.lane(ks) == "summon", "流派：%s / %s / %s" % [VN.lane(tx), VN.lane(ex), VN.lane(ks)])
	# 节点 1：卡面写范围，不写攻击 +6%
	var c1: Array = tx.deep_cards().filter(func(c): return c.get("kind", "") == "prog")
	ok(c1.size() > 0 and "攻击范围 +6%" in str(c1[0].desc) and not "攻击 +6%" in str(c1[0].desc), "德克萨斯节点卡写攻击范围：%s" % (str(c1[0].desc) if c1.size() > 0 else ""))
	var atk0 := v(tx, &"op_atk")
	var rng0 := v(tx, &"op_range")
	tx.advance("")
	ok(is_equal_approx(v(tx, &"op_atk"), atk0), "节点不再加攻击（%.3f → %.3f）" % [atk0, v(tx, &"op_atk")])
	ok(v(tx, &"op_range") > rng0 + 0.03, "节点加范围（%.3f → %.3f）" % [rng0, v(tx, &"op_range")])
	# 能天使：两个节点后每次普攻 0.4 发额外弹
	var ce: Array = ex.deep_cards().filter(func(c): return c.get("kind", "") == "prog")
	ok(ce.size() > 0 and "多射 1 发" in str(ce[0].desc), "能天使节点卡写弹数：%s" % (str(ce[0].desc) if ce.size() > 0 else ""))
	ex.advance("")
	ex.advance("")
	ok(is_equal_approx(VN.extra_shots(ex), 0.4), "能天使 2 节点额外弹 0.4（%.2f）" % VN.extra_shots(ex))
	# 凯尔希：追击与召唤物伤害
	var f0 := v(ks, &"followup_dmg")
	ks.advance("")
	ok(v(ks, &"followup_dmg") > f0, "凯尔希节点加召唤物伤害（%.3f → %.3f）" % [f0, v(ks, &"followup_dmg")])
	# 德克萨斯推到精二：精英化时刻入队；精二本人属性 + 全队技力回复
	var sp0: float = game.stats.value_for(&"op_skill_sp", ["squad"])
	var q0: int = game.elite_moment.queue.size()
	while tx.elite < 1:
		tx.advance("")
	ok(game.elite_moment.queue.size() == q0 + 1, "精一入队精英化时刻")
	var atk1 := v(tx, &"op_atk")
	while tx.elite < 2 and not tx.next_node().is_empty():
		tx.advance("")
	ok(tx.elite == 2, "德克萨斯精二")
	ok(v(tx, &"op_atk") > atk1 + 0.05, "精二本人攻击一档（%.3f → %.3f）" % [atk1, v(tx, &"op_atk")])
	ok(game.stats.value_for(&"op_skill_sp", ["squad"]) > sp0 + 0.05, "全队技力回复（%.3f → %.3f）" % [sp0, game.stats.value_for(&"op_skill_sp", ["squad"])])
	ok(game.stats.value_for(&"op_skill_sp", ex.scopes()) > sp0 + 0.05, "全队效果作用到能天使")
	ok(VN.elite_text(tx, 2).find("全队技力回复 +8%") >= 0, "精二卡面写全队效果：%s" % VN.elite_text(tx, 2))
	ok(VN.elite_text(ex, 2).find("祝福") < 0, "能天使（已有全队效果）卡面不重复写")
	# 精英化时刻：平衡模式不挡；玩家局定格挡住、定格后放行
	game.show_queue.clear()
	var em = game.elite_moment
	ok(not em.pending(), "平衡模式：时刻不挡弹窗")
	em.queue.clear()
	em.queue.append({"op": tx, "stage": 2})
	em.cur = {}
	var m0 = game.mode
	game.mode = game.Mode.PLAY
	game.state = game.S.PLAY
	ok(em.pending() and em.freezing(), "玩家局：定格中挡住后面的弹窗")
	ok(em.flash(tx) >= 0.0 and em.flash(ex) == 0.0, "只爆亮本人")
	em.tick(0.04)
	ok(em.flash(tx) > 0.3, "爆亮上冲（%.2f）" % em.flash(tx))
	em.tick(1.0)
	ok(not em.freezing() and not em.pending(), "定格结束放行")
	game.mode = m0
	var c: Color = EM.safe_col(ex)
	ok(not ((c.h < 0.05 or c.h > 0.92) and c.s > 0.35), "能天使的红调淡（h %.2f s %.2f）" % [c.h, c.s])
	# 离队撤销全队效果
	game.squad.remove("texas")
	ok(is_equal_approx(game.stats.value_for(&"op_skill_sp", ["squad"]), sp0), "离队撤销全队效果")
	print("%d checks, %d failed" % [n, fails])
	print("VIS NODES failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
