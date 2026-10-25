extends Node
## 首局聚光框引导 + 到点小提示单元测试（screens/tour.gd，check.py 场景回归 tour）。
## 1. TIPS 的 id 与 Cfg.TIP_IDS 一一对应；2. show_tip：弹一次、记进 Cfg.seen_tips、重复不再弹、第二个排队、过期后轮到队列；
## 3. force（演示用）不记存档；4. 存档往返：seen_tips 写读一致；5. 老存档（seen_intro = true、没有 seen_tips 键）读入后按「都看过」处理，
## 全新存档读入后为空；6. 没有对局（g = null）时不查触发条件。
const Tour = preload("res://scripts/screens/tour.gd")

var failures := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("TOUR: " + what)
		print("FAIL ", what)


func _ready() -> void:
	var tour = Tour.new(null)
	# 1. 文案表与存档 id 表一致
	for id in Cfg.TIP_IDS:
		check(Tour.TIPS.has(id), "TIPS 缺 " + id)
		check(Tour.TIPS.has(id) and Tour.TIPS[id].size() == 3, "TIPS[%s] 要 [标题, 英文小标, 正文]" % id)
	for id in Tour.TIPS:
		check(Cfg.TIP_IDS.has(id), "TIP_IDS 缺 " + id)
	# 2. 弹一次、记存档、排队
	Cfg.seen_tips = []
	tour.show_tip("elite")
	check(tour.tip_id == "elite", "第一次应弹出 elite")
	check(Cfg.seen_tips == ["elite"], "弹出的同时记进 seen_tips")
	tour.show_tip("elite")
	check(tour._queue.is_empty(), "重复的提示不再排队")
	tour.show_tip("lamp")
	check(tour.tip_id == "elite" and tour._queue == ["lamp"], "正在弹时第二个排队")
	tour.update(Tour.TIP_LIFE + 0.1)
	check(tour.tip_id == "" or tour.tip_id == "lamp", "过期后提示收起或轮到队列")
	tour.update(0.1)
	check(tour.tip_id == "lamp", "队列里的提示轮到：" + tour.tip_id)
	tour.update(Tour.TIP_LIFE + 0.1)
	check(tour.tip_id == "", "全部弹完后为空")
	# 3. force 不记
	var before: Array = Cfg.seen_tips.duplicate()
	tour.show_tip("boss", true)
	check(tour.tip_id == "boss" and Cfg.seen_tips == before, "force 弹出但不记存档")
	tour.show_tip("nope")
	check(not Cfg.seen_tips.has("nope"), "未知 id 不处理")
	# 4. 存档往返
	var cf := ConfigFile.new()
	cf.set_value("progress", "seen_intro", true)
	cf.set_value("progress", "seen_tips", ["boss"])
	Cfg.seen_tips = []
	Cfg._read_cfg(cf)
	check(Cfg.seen_tips == ["boss"], "seen_tips 读入：" + str(Cfg.seen_tips))
	# 5. 迁移：老存档按都看过，全新存档为空
	var old := ConfigFile.new()
	old.set_value("progress", "seen_intro", true)
	Cfg.seen_tips = []
	Cfg._read_cfg(old)
	check(Cfg.seen_tips == Cfg.TIP_IDS, "老存档（看过旧指南）不再弹小提示：" + str(Cfg.seen_tips))
	var fresh := ConfigFile.new()
	fresh.set_value("progress", "difficulty", 0)
	Cfg.seen_intro = false
	Cfg.seen_tips = []
	Cfg._read_cfg(fresh)
	check(Cfg.seen_tips.is_empty(), "全新存档读入后 seen_tips 为空：" + str(Cfg.seen_tips))
	# 6. 没有对局不查触发
	check(not tour._eligible(), "g 为空时 _eligible 为假")
	print("TOUR failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
