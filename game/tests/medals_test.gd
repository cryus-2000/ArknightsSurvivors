extends Node
## 蚀刻章「深蓝之下」单元测试（core/medals.gd，check.py 场景回归 medals）：
## 1. 章表：9 枚、key 唯一、布局 / 章图齐全；
## 2. 海中拾遗：有效藏品 49 / 50 边界、重复获取不重复计数、无效 ID 不算；全部解锁时按真实记录判；
## 3. 结局四枚各自对应；协同晋升（只读编队精英二人数，演练 / 练习不算）；认知首次 / 全部、认知重置不收回；
## 4. 套组章：其余八枚齐了同一次判上；已获得的章在记录变少后仍保留；
## 5. 读档补录（旧存档没有 [medals] 段）；云存档 merge_med 并集 / 时刻取早 / 进度取大、Cfg 往返、未知章 key 保留、坏类型忽略。
## 只改内存里的 Cfg 字段，结束前还原（测试参数下 Cfg.save() 本来就不落盘）。
const Medals = preload("res://scripts/core/medals.gd")
const Meta = preload("res://scripts/core/meta.gd")
const Pack = preload("res://scripts/core/cloud_pack.gd")

const KEEP := ["medals", "medal_best", "seen_relics", "endings_cleared", "meta_shape", "unlock_all", "_real_progress", "practice_active"]
var failures := 0
var saved := {}


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("MEDALS: " + what)
		print("FAIL ", what)


func _ready() -> void:
	call_deferred("run")


func reset_state() -> void:
	Cfg.medals = {}
	Cfg.medal_best = {}
	Cfg.seen_relics = []
	Cfg.endings_cleared = []
	Cfg.meta_shape = {}
	Cfg.unlock_all = false
	Cfg._real_progress = {}
	Cfg.practice_active = false


func run() -> void:
	for k in KEEP:
		saved[k] = Cfg.get(k).duplicate(true) if Cfg.get(k) is Dictionary or Cfg.get(k) is Array else Cfg.get(k)
	table_tests()
	relic_tests()
	ending_elite_tests()
	cognition_tests()
	set_tests()
	backfill_tests()
	cloud_tests()
	for k in KEEP:
		Cfg.set(k, saved[k])
	print("MEDALS failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func table_tests() -> void:
	var defs := Medals.defs()
	check(defs.size() == 9, "章表应为 9 枚：%d" % defs.size())
	var keys := {}
	for m in defs:
		check(not keys.has(m.key), "key 重复：%s" % m.key)
		keys[m.key] = true
		check(ResourceLoader.exists("res://art/ui/medals/medal_%d.png" % int(m.id)) and ResourceLoader.exists("res://art/ui/medals/medal_%d_slot.png" % int(m.id)), "缺章图：%d" % int(m.id))
		check(str(m.name) != "" and str(m.desc) != "", "缺名称 / 条件：%s" % m.key)
	var lay = JSON.parse_string(FileAccess.get_file_as_string("res://data/medals_layout.json"))
	var ids := {}
	for m in lay.medals:
		ids[int(m.id)] = true
	for m in defs:
		check(ids.has(int(m.id)), "布局里没有章 %d" % int(m.id))
	check(Medals.def("relic_fifty").get("max", 0) == 50, "海中拾遗阈值应为 50")


func relic_tests() -> void:
	reset_state()
	var ok: Array = Medals.valid_relics().keys()
	check(ok.size() >= 50, "有效藏品不足 50 种：%d" % ok.size())
	var m := Medals.def("relic_fifty")
	var seen: Array = ok.slice(0, 49)
	seen.append(ok[0])          # 重复获取
	seen.append(ok[3])
	seen.append("999999")       # 无效 ID
	Cfg.seen_relics = seen
	check(Medals.progress(m) == [49, 50], "49 种 + 重复 + 无效应为 49 / 50：%s" % [Medals.progress(m)])
	Medals.sync(100)
	check(not Medals.has("relic_fifty"), "49 种不应获得海中拾遗")
	Cfg.seen_relics.append(ok[49])
	check(Medals.progress(m) == [50, 50], "第 50 种应为 50 / 50")
	var got := Medals.sync(200)
	check(got.has("relic_fifty") and int(Cfg.medals.relic_fifty) == 200, "第 50 种应获得海中拾遗（时刻 200）：%s" % [got])
	Medals.sync(300)
	check(int(Cfg.medals.relic_fifty) == 200, "再次判定不改获得时刻")
	# 全部解锁：界面那份是全开，按真实记录判
	reset_state()
	Cfg.unlock_all = true
	Cfg.seen_relics = ok.duplicate()
	Cfg.endings_cleared = ["standard", "knight", "deep", "resolve"]
	Cfg._real_progress = {"seen_relics": ok.slice(0, 10), "endings_cleared": ["knight"]}
	Medals.sync(1)
	check(not Medals.has("relic_fifty") and not Medals.has("ending_standard") and Medals.has("ending_knight"), "全部解锁时应按真实记录判：%s" % [Cfg.medals])
	Cfg.note_real("seen_relics", ok[20])
	check((Cfg._real_progress.seen_relics as Array).has(ok[20]), "note_real 应记进真实进度")
	reset_state()
	Cfg.note_real("seen_relics", ok[20])
	check(Cfg._real_progress.is_empty(), "没开全部解锁时 note_real 什么都不做")


func fake_g(elites: Array, trial := false, mode := 0) -> Dictionary:
	var ops: Array = []
	for e in elites:
		ops.append({"elite": e})
	return {"mode": mode, "Mode": {"PLAY": 0, "DEMO": 1}, "trial": {"active": trial}, "demo_op": "", "squad": {"ops": ops}}


func ending_elite_tests() -> void:
	reset_state()
	Cfg.endings_cleared = ["deep"]
	Medals.sync(1)
	check(Medals.has("ending_deep") and not Medals.has("ending_standard") and not Medals.has("ending_knight") and not Medals.has("ending_resolve"), "结局三只给潮声止息：%s" % [Cfg.medals])
	Medals.note_elite(fake_g([2, 2, 1]))
	check(int(Cfg.medal_best.get("elite_three", 0)) == 2, "两人精英二应记 2")
	Medals.sync(2)
	check(not Medals.has("elite_three"), "两人精英二不应获得协同晋升")
	Medals.note_elite(fake_g([2, 2, 2], true))
	Medals.note_elite(fake_g([2, 2, 2], false, 1))
	Cfg.practice_active = true
	Medals.note_elite(fake_g([2, 2, 2]))
	Cfg.practice_active = false
	check(int(Cfg.medal_best.get("elite_three", 0)) == 2, "演练 / 非 PLAY / 练习不应计入")
	Medals.note_elite(fake_g([2, 1, 2, 2]))
	check(Medals.sync(3).has("elite_three"), "三人同时精英二应获得协同晋升")
	Medals.note_elite(fake_g([2]))
	check(int(Cfg.medal_best.elite_three) == 3, "最好进度只升不降")


func cognition_tests() -> void:
	reset_state()
	var all: Dictionary = Meta.nodes()
	check(Medals.progress(Medals.def("cognition_complete"))[1] == all.size(), "认知全部节点数按配置：%d" % all.size())
	Medals.sync(1)
	check(not Medals.has("cognition_first"), "没点节点不应获得初识深蓝")
	Cfg.meta_shape = {all.keys()[0]: true}
	Medals.sync(2)
	check(Medals.has("cognition_first") and not Medals.has("cognition_complete"), "点亮一个节点应获得初识深蓝")
	var full := {}
	for id in all:
		full[id] = true
	full.erase(all.keys()[1])
	Cfg.meta_shape = full
	Medals.sync(3)
	check(not Medals.has("cognition_complete"), "差一个节点不应获得认知深化")
	full[all.keys()[1]] = true
	full["no_such_node"] = true   # 存档里的陈旧节点不算数
	Cfg.meta_shape = full
	check(Medals.sync(4).has("cognition_complete"), "全部节点点亮应获得认知深化")
	Meta.reset()
	check(Cfg.meta_shape.is_empty() and Medals.has("cognition_first") and Medals.has("cognition_complete"), "认知重置后两枚章仍保留")
	var p := Medals.progress(Medals.def("cognition_complete"))
	check(p[0] == p[1], "已获得的章进度显示满：%s" % [p])


func set_tests() -> void:
	reset_state()
	var ok: Array = Medals.valid_relics().keys()
	Cfg.seen_relics = ok.slice(0, 50)
	Cfg.endings_cleared = ["standard", "knight", "deep", "resolve"]
	Cfg.medal_best = {"elite_three": 3}
	var full := {}
	for id in Meta.nodes():
		full[id] = true
	Cfg.meta_shape = full
	var set_m := Medals.def("set_complete")
	check(Medals.progress(set_m) == [0, 8], "开始时套组 0 / 8")
	var got := Medals.sync(9)
	check(got.size() == 9 and got[-1] == "set_complete" and Medals.earned_count() == 9, "其余八枚齐了同一次判上套组章：%s" % [got])
	# 记录变少（换设备 / 重置）不收回
	Cfg.seen_relics = []
	Cfg.endings_cleared = []
	Cfg.meta_shape = {}
	Cfg.medal_best = {}
	Medals.sync(10)
	check(Medals.earned_count() == 9, "已获得的章永久保留")
	reset_state()
	Cfg.medals = {"ending_standard": 1, "ending_knight": 1, "ending_deep": 1, "ending_resolve": 1, "elite_three": 1, "relic_fifty": 1, "cognition_first": 1}
	Medals.sync(11)
	check(not Medals.has("set_complete") and Medals.progress(set_m) == [7, 8], "七枚不给套组章")


func backfill_tests() -> void:
	reset_state()
	var c := ConfigFile.new()
	c.set_value("progress", "endings_cleared", ["knight"])
	c.set_value("meta", "shape", {Meta.nodes().keys()[0]: true})
	Cfg._read_cfg(c)
	check(Cfg.medals.is_empty(), "老存档没有 [medals] 段：读进来为空")
	Medals.sync(5)
	check(Medals.has("ending_knight") and Medals.has("cognition_first") and Medals.earned_count() == 2, "读档后补录：%s" % [Cfg.medals])
	c.set_value("medals", "got", "坏类型")
	Cfg._read_cfg(c)
	check(Cfg.medals is Dictionary and Cfg.medals.is_empty(), "[medals] 段类型不对时按空读")


func cloud_tests() -> void:
	var l := {"got": {"ending_standard": 100, "relic_fifty": 300, "future_medal": 5}, "best": {"elite_three": 2}}
	var c := {"got": {"ending_standard": 50, "cognition_first": 400, "bad": "x"}, "best": {"elite_three": 1, "other": 4}}
	var m := Pack.merge_med(l, c)
	check(m.got == {"ending_standard": 50, "relic_fifty": 300, "future_medal": 5, "cognition_first": 400}, "并集 + 时刻取早 + 坏类型丢弃：%s" % [m.got])
	check(m.best == {"elite_three": 2, "other": 4}, "进度取大：%s" % [m.best])
	check(Pack.merge_med({"got": {"a": 0}}, {"got": {"a": 70}}).got.a == 70, "时刻 0（未知）让位给有时刻的一份")
	# 整份正文合并：一边没有 med（旧版本写的云档）
	var lb := {"set": {"t": 1, "d": {}}, "prog": {"diff": 0, "gal": [], "rel": [], "end": [], "shows": [], "intro": false, "open": false, "med": l}}
	var cb := {"set": {"t": 2, "d": {}}, "prog": {"diff": 0, "gal": [], "rel": [], "end": [], "shows": [], "intro": false, "open": false}}
	var mm := Pack.merge(lb, cb)
	check(mm.prog.med.got.has("relic_fifty") and mm.prog.med.best.elite_three == 2, "云端没有 med 时保留本地")
	mm = Pack.merge(cb, lb)
	check(mm.prog.med.got.has("relic_fifty"), "本地没有 med 时采用云端")
	check(Pack.merge(cb, cb).prog.has("med") == false, "两边都没有 med 时不补（旧版本往返逐字相同）")
	# Cfg 往返
	reset_state()
	Cfg.medals = {"ending_knight": 123, "future_medal": 9}
	Cfg.medal_best = {"elite_three": 2}
	var body := Cfg.cloud_body()
	check(body.prog.med.got.ending_knight == 123, "cloud_body 带蚀刻章")
	Cfg.medals = {}
	Cfg.medal_best = {}
	Cfg.cloud_apply(Pack.normalize(JSON.parse_string(JSON.stringify(body))))
	check(int(Cfg.medals.get("ending_knight", 0)) == 123 and Cfg.medals.has("future_medal") and int(Cfg.medal_best.elite_three) == 2, "cloud_apply 往返（含本版不认识的章）：%s / %s" % [Cfg.medals, Cfg.medal_best])
