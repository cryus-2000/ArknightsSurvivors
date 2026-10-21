extends RefCounted
## 认知塑造（局外成长 P2，docs/109 §4，用户 10-22 确认 v3）：节点数据在 data/meta_tree.json，玩家已点的在 Cfg.meta_shape（{节点 id: true}）。
## 一局开局时 apply_run(g) 把已点节点写进属性块（来源 "meta"）与开局资源。
## 测试局缺省不带任何局外成长（与改动前逐局相同）；--meta=<生机细胞数> 按推荐点法点到这个数，--meta=full 点满（机器人校准用，docs/109 §5.4）。
## --meta 只在测试局读；正式游玩用存档里的 Cfg.meta_shape。

const PATH := "res://data/meta_tree.json"
static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var j = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = j if j is Dictionary else {"nodes": {}, "order": []}
	return _data


static func nodes() -> Dictionary:
	return data().get("nodes", {})


static func total_cost() -> int:
	var n := 0
	for k in nodes():
		n += int(nodes()[k].cost)
	return n


static func spent(shape: Dictionary) -> int:
	var n := 0
	for k in shape:
		if shape[k] and nodes().has(k):
			n += int(nodes()[k].cost)
	return n


## 能不能点：未点、前置已点、大节点的总量门槛已到、余额够
static func can_buy(shape: Dictionary, id: String, budget: int) -> bool:
	if not nodes().has(id) or shape.get(id, false):
		return false
	var nd: Dictionary = nodes()[id]
	if nd.has("req") and not shape.get(str(nd.req), false):
		return false
	var sp := spent(shape)
	if sp < int(nd.get("need", 0)):
		return false
	return sp + int(nd.cost) <= budget


## 推荐点法：按 order 依次点，点不了（前置 / 门槛 / 余额）先跳过，反复到不再变化
static func shape_for(budget: int) -> Dictionary:
	var shape := {}
	var changed := true
	while changed:
		changed = false
		for id in data().get("order", []):
			if can_buy(shape, str(id), budget):
				shape[str(id)] = true
				changed = true
	return shape


## 本局用哪一份局外成长：测试局只认 --meta=；正式游玩用存档
static func run_shape() -> Dictionary:
	var test := false
	for a in Cfg.dev_args():
		if a.begins_with("--meta="):
			var v := a.substr(7)
			return shape_for(total_cost() if v == "full" else int(v))
		if a.begins_with("--"):
			test = true
	return {} if test else Cfg.meta_shape


## 开局：属性写进 stats（来源 meta），开局资源与一次性规则写进 g / rfx。返回本局点了多少生机细胞（记进作战记录 / BALANCE）
static func apply_run(g) -> int:
	var shape := run_shape()
	g.meta_cells = spent(shape)
	if shape.is_empty() or g.demo_op != "":
		return 0
	for id in shape:
		if not shape[id] or not nodes().has(id):
			continue
		for ef in nodes()[id].get("effects", []):
			if ef.has("stat"):
				g.stats.add(StringName(ef.stat), str(ef.get("op", "add")), float(ef.value), "meta")
			elif ef.has("rule"):
				g.rfx.rules[ef.rule] = int(g.rfx.rules.get(ef.rule, 0)) + int(ef.get("value", 1))
			elif ef.has("start_ingots"):
				g.ingots += int(ef.start_ingots)
			elif ef.has("once_heal"):
				g.meta_once_heal = [float(ef.at), float(ef.once_heal)]
			elif ef.has("start_relic"):
				g.meta_start_relic = int(ef.start_relic)
	g.sync_stats()
	return g.meta_cells
