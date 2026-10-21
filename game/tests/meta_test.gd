extends Node
## 认知塑造单元测试（docs/109 §4，check.py 场景回归 meta）：节点数据完整（总量 550、前置存在、推荐顺序覆盖全部节点）、
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
	check(Meta.total_cost() == 560, "总量应为 560，实为 %d" % Meta.total_cost())
	var order: Array = Meta.data().get("order", [])
	for id in nodes:
		check(order.has(id), "推荐顺序缺 " + id)
		var nd: Dictionary = nodes[id]
		if nd.has("req"):
			check(nodes.has(str(nd.req)), "%s 的前置 %s 不存在" % [id, nd.req])
		check(nd.has("name") and nd.has("desc") and int(nd.get("cost", 0)) > 0, "%s 缺名字 / 说明 / 价格" % id)
	check(Meta.shape_for(0).is_empty(), "预算 0 不点")
	var full := Meta.shape_for(Meta.total_cost())
	check(full.size() == nodes.size() and Meta.spent(full) == 560, "满预算应点满：%d 个 / %d" % [full.size(), Meta.spent(full)])
	for b in [30, 75, 150, 220, 360, 559]:
		var sh := Meta.shape_for(b)
		check(Meta.spent(sh) <= b, "预算 %d 超支 %d" % [b, Meta.spent(sh)])
		for id in sh:
			var nd: Dictionary = nodes[id]
			if nd.has("req"):
				check(sh.has(str(nd.req)), "预算 %d：%s 没有前置 %s" % [b, id, nd.req])
	check(Meta.shape_for(40).has("sh1"), "推荐点法第一个应是危机感Ⅰ")
	check(not Meta.shape_for(40).has("atk2"), "预算 40 只点危机感Ⅰ")
	check(Meta.run_shape().is_empty(), "测试局缺省不带局外成长")
	# 生机细胞（§3.1）
	Cfg.meta_earned = {}
	Cfg.meta_bounty = []
	Cfg.meta_shape = {}
	check(is_equal_approx(Meta.tide_factor(0), 1.0) and is_equal_approx(Meta.tide_factor(8), 1.4) and is_equal_approx(Meta.tide_factor(15), 1.5), "潮位系数")
	var fg := FakeG.new()
	fg.t = 400.0
	var r := Meta.run_reward(fg, false)
	check(r.base == 66 and r.cells == 8 and r.bounty == 0, "撤离 6:40 无 Boss：%s" % [r])
	fg.t = 640.0
	fg.tier = 8   # 潮位 8
	fg.bosses = [{"dead": true}, {"dead": true}, {"dead": true}]
	fg.final_boss = fg.bosses[2]
	fg.ending_new = true
	r = Meta.run_reward(fg, true)
	check(r.base == 200 and r.score == 320 and r.bounty == 13 and r.cells == 53, "Ⅷ 首通 + 新结局：%s" % [r])
	Meta.on_run_end(fg, true)
	check(Meta.earned_total() == 53 and Cfg.meta_bounty.has(8) and fg.meta_result.cells == 53, "局终记账 %s" % [Cfg.meta_earned])
	r = Meta.run_reward(fg, true)
	check(r.bounty == 0, "同一潮位第二次通关没有首通赏金")
	check(Meta.buy("sh1") and Meta.available() == 13, "点危机感Ⅰ后余额 13，实为 %d" % Meta.available())
	check(not Meta.buy("atk2"), "没点攻击性Ⅰ不能点攻击性Ⅱ")
	Meta.buy_recommended()
	check(Meta.available() >= 0 and Meta.available() < 5, "推荐点完余额 %d" % Meta.available())
	Meta.reset()
	check(Cfg.meta_shape.is_empty() and Meta.available() == 53, "重置后全部退回")
	# 云存档合并
	var a := {"earned": {"d1": 100, "d2": 30}, "bounty": [0], "shape": {"sh1": true}, "t": 10}
	var b := {"earned": {"d1": 80, "d3": 50}, "bounty": [4], "shape": {"atk1": true}, "t": 20}
	var m := Pack.merge_meta(a, b)
	check(int(m.earned.d1) == 100 and int(m.earned.d2) == 30 and int(m.earned.d3) == 50, "生机细胞逐设备取大 %s" % [m.earned])
	check(m.bounty.size() == 2 and m.shape.has("atk1") and int(m.t) == 20, "赏金并集、认知塑造取较新 %s" % [m])
	print("META failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
