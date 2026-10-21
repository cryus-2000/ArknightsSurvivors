extends Node
## 认知塑造单元测试（docs/109 §4，check.py 场景回归 meta）：节点数据完整（总量 550、前置存在、推荐顺序覆盖全部节点）、
## 推荐点法按预算点（前置 / 大节点门槛 / 余额）、--meta=full 点满、测试局缺省不带局外成长。
const Meta = preload("res://scripts/core/meta.gd")

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
	check(nodes.size() >= 30, "节点数 %d" % nodes.size())
	check(Meta.total_cost() == 550, "总量应为 550，实为 %d" % Meta.total_cost())
	var order: Array = Meta.data().get("order", [])
	for id in nodes:
		check(order.has(id), "推荐顺序缺 " + id)
		var nd: Dictionary = nodes[id]
		if nd.has("req"):
			check(nodes.has(str(nd.req)), "%s 的前置 %s 不存在" % [id, nd.req])
		check(nd.has("name") and nd.has("desc") and int(nd.get("cost", 0)) > 0, "%s 缺名字 / 说明 / 价格" % id)
	check(Meta.shape_for(0).is_empty(), "预算 0 不点")
	var full := Meta.shape_for(Meta.total_cost())
	check(full.size() == nodes.size() and Meta.spent(full) == 550, "满预算应点满：%d 个 / %d" % [full.size(), Meta.spent(full)])
	for b in [30, 75, 150, 220, 360, 549]:
		var sh := Meta.shape_for(b)
		check(Meta.spent(sh) <= b, "预算 %d 超支 %d" % [b, Meta.spent(sh)])
		for id in sh:
			var nd: Dictionary = nodes[id]
			if nd.has("req"):
				check(sh.has(str(nd.req)), "预算 %d：%s 没有前置 %s" % [b, id, nd.req])
	check(Meta.shape_for(30).has("sh1"), "推荐点法第一个应是危机感Ⅰ")
	check(not Meta.shape_for(199).has("survive"), "已点不足 200 不能点「为了生存」")
	check(Meta.run_shape().is_empty(), "测试局缺省不带局外成长")
	print("META failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
