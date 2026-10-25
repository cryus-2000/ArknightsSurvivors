extends Node
## 认知塑造单元测试（docs/109 §4，check.py 场景回归 meta）：节点数据完整（总量 587、前置存在、推荐顺序覆盖全部节点）、
## 推荐点法按预算点（前置 / 大节点门槛 / 余额）、--meta=full 点满、测试局缺省不带局外成长。
const Meta = preload("res://scripts/core/meta.gd")
const Pack = preload("res://scripts/core/cloud_pack.gd")


class FakeTrial:
	var active := false


class FakeG:
	enum Mode { PLAY, AUTOTEST, BALANCE }
	var mode := 0
	var trial := FakeTrial.new()
	var demo_op := ""
	var tier := 0
	var t := 0.0
	var bosses: Array = []
	var final_boss = null
	var ending_new := false
	var meta_result := {}
	var roster_new := {}

var failures := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("META: " + what)
		print("FAIL ", what)


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	var nodes := Meta.nodes()
	check(nodes.size() >= 25, "节点数 %d" % nodes.size())
	check(Meta.total_cost() == 587, "总量应为 587，实为 %d" % Meta.total_cost())
	var order: Array = Meta.data().get("order", [])
	for id in nodes:
		check(order.has(id), "推荐顺序缺 " + id)
		var nd: Dictionary = nodes[id]
		if nd.has("req"):
			check(nodes.has(str(nd.req)), "%s 的前置 %s 不存在" % [id, nd.req])
		check(nd.has("name") and nd.has("desc") and int(nd.get("cost", 0)) > 0, "%s 缺名字 / 说明 / 价格" % id)
	check(Meta.shape_for(0).is_empty(), "预算 0 不点")
	var full := Meta.shape_for(Meta.total_cost())
	check(full.size() == nodes.size() and Meta.spent(full) == 587, "满预算应点满：%d 个 / %d" % [full.size(), Meta.spent(full)])
	for b in [30, 75, 150, 220, 360, 540, 586]:
		var sh := Meta.shape_for(b)
		check(Meta.spent(sh) <= b, "预算 %d 超支 %d" % [b, Meta.spent(sh)])
		for id in sh:
			var nd: Dictionary = nodes[id]
			if nd.has("req"):
				check(sh.has(str(nd.req)), "预算 %d：%s 没有前置 %s" % [b, id, nd.req])
	check(Meta.shape_for(13).has("sh1"), "推荐点法第一个应是危机感Ⅰ（13，10-26 前置加强由 35 降价）")
	check(not Meta.shape_for(13).has("atk1"), "预算 13 只点危机感Ⅰ")
	var s18 := Meta.shape_for(18)
	check(s18.has("sh1") and s18.has("atk1") and Meta.spent(s18) == 18 and s18.size() == 2, "预算 18 = 危机感Ⅰ + 攻击性Ⅰ（--meta=18 的前置加强口径）：%s" % [s18])
	check(Meta.run_shape().is_empty(), "测试局缺省不带局外成长")
	# 生机细胞（§3.1）
	Cfg.meta_earned = {}
	Cfg.meta_bounty = []
	Cfg.meta_shape = {}
	check(is_equal_approx(Meta.tide_factor(0), 1.0) and is_equal_approx(Meta.tide_factor(8), 1.4) and is_equal_approx(Meta.tide_factor(15), 1.5), "潮位系数")
	var fg := FakeG.new()
	fg.t = 400.0
	var r := Meta.run_reward(fg, false)
	check(r.base == 66 and r.cells == 11 and r.bounty == 0, "撤离 6:40 无 Boss：%s" % [r])
	fg.t = 640.0
	fg.tier = 8   # 潮位 8
	fg.bosses = [{"dead": true}, {"dead": true}, {"dead": true}]
	fg.final_boss = fg.bosses[2]
	fg.ending_new = true
	r = Meta.run_reward(fg, true)
	check(r.base == 200 and r.score == 320 and r.bounty == 13 and r.cells == 66, "Ⅷ 首通 + 新结局：%s" % [r])
	Meta.on_run_end(fg, true)
	check(Meta.earned_total() == 66 and Cfg.meta_bounty.has(8) and fg.meta_result.cells == 66, "局终记账 %s" % [Cfg.meta_earned])
	r = Meta.run_reward(fg, true)
	check(r.bounty == 0, "同一潮位第二次通关没有首通赏金")
	check(Meta.buy("sh1") and Meta.available() == 53, "点危机感Ⅰ（13）后余额 53，实为 %d" % Meta.available())
	check(not Meta.buy("atk2"), "没点攻击性Ⅰ不能点攻击性Ⅱ")
	Meta.buy_recommended()
	check(Meta.available() >= 0 and Meta.available() < 5, "推荐点完余额 %d" % Meta.available())
	Meta.reset()
	check(Cfg.meta_shape.is_empty() and Meta.available() == 66, "重置后全部退回")
	# 云存档合并
	var a := {"earned": {"d1": 100, "d2": 30}, "bounty": [0], "shape": {"sh1": true}, "t": 10}
	var b := {"earned": {"d1": 80, "d3": 50}, "bounty": [4], "shape": {"atk1": true}, "t": 20}
	var m := Pack.merge_meta(a, b)
	check(int(m.earned.d1) == 100 and int(m.earned.d2) == 30 and int(m.earned.d3) == 50, "生机细胞逐设备取大 %s" % [m.earned])
	check(m.bounty.size() == 2 and m.shape.has("atk1") and int(m.t) == 20, "赏金并集、认知塑造取较新 %s" % [m])
	# 兑换寻访凭证的花费（Roster.exchange_ticket，用户 10-25）：预算 = 累计获得 − 兑换；认知塑造只能用剩下的
	Cfg.meta_earned = {"d1": 100}
	Cfg.meta_bought = {}
	Cfg.meta_shape = {}
	check(Meta.pay(15) and Meta.bought_total() == 15 and Meta.budget() == 85 and Meta.available() == 85, "pay(15)：预算 85")
	check(not Meta.pay(86) and Meta.bought_total() == 15, "余额不够不扣")
	check(Meta.shape_for(Meta.budget()).has("sh1") and not Meta.can_buy({}, "sh1", 12), "按预算点危机感Ⅰ（13）")
	Cfg.meta_earned = {"d1": 40}
	Cfg.meta_bought = {"d1": 15}
	check(not Meta.buy("disp1") and Meta.available() == 25, "兑换后余额 25 买不起 30 的节点（多程信息处理）")
	var ba := {"earned": {"d1": 100}, "bounty": [], "shape": {}, "t": 1, "bought": {"d1": 15, "d2": 5}}
	var bb := {"earned": {"d1": 100}, "bounty": [], "shape": {}, "t": 2, "bought": {"d1": 30}}
	var bm := Pack.merge_meta(ba, bb)
	check(int(bm.bought.d1) == 30 and int(bm.bought.d2) == 5, "bought 逐设备取大 %s" % [bm])
	check(not Pack.merge_meta({"earned": {"d1": 1}}, {"earned": {"d1": 2}}).has("bought"), "双方都没兑换过时不带 bought 字段")
	Cfg.meta_earned = {}
	Cfg.meta_bought = {}
	print("META failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
