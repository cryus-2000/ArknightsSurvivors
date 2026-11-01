extends Node
## 图鉴「技能」页连携一行（docs/209 §2，data/ult_text.json link_v2）：20 人都有 v2 文案、类别与 skill_link.KIND4 一致、
## 占位全部填上、link/v2 0 时退回旧 E 连携技一行；终结技一行在 ult/aim 1 时写按住瞄准。
## godot --headless --path game res://tests/link_text_test.tscn -- --regression
## 全部通过时打印 "LINK TEXT checks=N failures=0"

const Bal = preload("res://scripts/core/balance.gd")
const Ult = preload("res://scripts/run/ult.gd")
const Link = preload("res://scripts/run/skill_link.gd")
const OpDefs = preload("res://scripts/characters/operator_defs.gd")

var checks := 0
var failures := 0


func ok(v: bool, what: String) -> void:
	checks += 1
	if not v:
		failures += 1
		printerr("FAIL: ", what)


func _ready() -> void:
	var gal = load("res://scripts/gallery.gd").new()
	var ops: Dictionary = Ult.text_table().get("ops", {})
	ok(ops.size() == Link.SAMPLE.size(), "ult_text ops %d == SAMPLE %d" % [ops.size(), Link.SAMPLE.size()])
	for id in Link.SAMPLE:
		var e: Dictionary = ops.get(id, {})
		var l2: Dictionary = e.get("link_v2", {})
		ok(not l2.is_empty(), "%s 有 link_v2" % id)
		ok(str(l2.get("kind", "")) == str(Link.KIND4.get(id, "?")), "%s 类别 %s == KIND4 %s" % [id, l2.get("kind", ""), Link.KIND4.get(id, "?")])
		ok(str(l2.get("name", "")) != str(e.get("link", {}).get("name", "")), "%s v2 名称与旧 E 连携技不同" % id)
		var rows: Array = gal._skill_rows(OpDefs.load_def(id))
		var lr: Array = []
		var ur: Array = []
		for r in rows:
			if str(r[0]).begins_with("LINK"):
				lr = r
			if str(r[0]).begins_with("ULTIMATE"):
				ur = r
		ok(lr.size() > 7 and str(lr[1]) == str(l2.get("name", "")), "%s 图鉴连携行用 v2 名称" % id)
		if lr.size() > 7:
			var d := str(lr[7])
			ok(not d.contains("{") and not d.contains("$"), "%s 占位已填：%s" % [id, d])
			ok(not d.contains("按 E") and d.contains("自动出手"), "%s 连携行写自动出手、没有 E 键" % id)
			ok(d.contains(OpDefs.text_fmt(Bal.v("link/v2_gap", 60.0), 0)), "%s 写出间隔秒数" % id)
		ok(ur.size() > 7 and str(ur[7]).contains("按住"), "%s 终结技行写按住瞄准" % id)
	# 数值占位按 balance 现值
	var sk := str(gal._skill_rows(OpDefs.load_def("skalter")).filter(func(r): return str(r[0]).begins_with("LINK"))[0][7])
	ok(sk.contains("+%s%%" % OpDefs.text_fmt(Bal.v("ult/link_skalter_atk", 1.2) * 100.0 - 100.0, 0)), "浊心斯卡蒂伤害加成按现值：" + sk)
	# 旧路径
	var lsec: Dictionary = Bal.sec("link")
	var usec: Dictionary = Bal.sec("ult")
	var lv2 = lsec.get("v2", 1)
	var uaim = usec.get("aim", 1)
	lsec["v2"] = 0.0
	usec["aim"] = 0.0
	var old: Array = gal._skill_rows(OpDefs.load_def("texas")).filter(func(r): return str(r[0]).begins_with("LINK"))
	ok(old.size() == 1 and str(old[0][1]) == str(ops.texas.link.name), "link/v2 0：退回旧 E 连携技一行")
	var ou: Array = gal._skill_rows(OpDefs.load_def("texas")).filter(func(r): return str(r[0]).begins_with("ULTIMATE"))
	ok(ou.size() == 1 and not str(ou[0][7]).contains("按住"), "ult/aim 0：终结技行退回旧说明")
	lsec["v2"] = lv2
	usec["aim"] = uaim
	gal.free()
	print("LINK TEXT checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
