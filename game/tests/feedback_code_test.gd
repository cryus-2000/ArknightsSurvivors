extends Node
## 反馈码（docs/311，core/feedback.gd）：
##   godot --headless --path game res://tests/feedback_code_test.tscn -- --regression
## 没配反馈目标时入口不显示；码只用字母表字符、末位校验、长度够短；同一摘要得同一码；改一项码就变。
## 每个码打印一行 "FBCODE <码> <摘要 JSON>"，tools/feedback_decode.py --selftest 用它对照往返。全部通过打印 "FEEDBACK failures=0"

const FB = preload("res://scripts/core/feedback.gd")
var n := 0
var fails := 0


func _ready() -> void:
	ok(not FB.enabled(), "缺省（balance feedback 留空）不显示入口")
	var title := FB.code()
	emit(title, {})
	ok(title.length() <= 20, "标题页码够短：%s" % title)
	var cases: Array = [
		{"ops": ["mizuki", "skadi", "kaltsit", "texas"], "tier": 10, "result": "dead", "quit": false, "trial": false, "death_t": 742.6, "wall_s": 905.0, "cause": "boss"},
		{"ops": ["logos"], "tier": 0, "result": "win", "quit": false, "trial": false, "death_t": 0.0, "wall_s": 1520.0, "cause": ""},
		{"ops": ["angelina", "newguy"], "tier": 5, "result": "dead", "quit": true, "trial": true, "death_t": 0.0, "wall_s": 64.0, "cause": ""},
		{"ops": ["wisadel", "skalter", "specter_unchained", "ulpianus", "gladiia", "lumen"], "tier": 5, "result": "dead", "quit": false, "trial": false, "death_t": 4100.0, "wall_s": 9000.0, "cause": "env:nerve"},
	]
	var seen := {}
	for c in cases:
		var s: String = FB.code(c)
		emit(s, c)
		ok(s == FB.code(c), "同一摘要同一码")
		ok(not seen.has(s), "不同摘要不同码")
		seen[s] = true
		ok(s.length() <= 48, "局内码长度 %d：%s" % [s.length(), s])
		for ch in s.substr(3).replace("-", ""):
			ok(FB.ALPHA.contains(ch), "字符在字母表里：%s" % ch)
	var c0: Dictionary = cases[0].duplicate()
	c0.tier = 5
	ok(FB.code(c0) != FB.code(cases[0]), "改难度码就变")
	ok(FB.cause({"type": "", "env": "mire"}) == "env:mire" and FB.cause({}) == "", "倒下原因类型")
	print("%d checks, %d failed" % [n, fails])
	print("FEEDBACK failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func emit(code: String, c: Dictionary) -> void:
	print("FBCODE %s %s" % [code, JSON.stringify(c)])


func ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		fails += 1
		print("FAIL ", what)
