extends SceneTree
## 藏品卡说明放不放得下（10-28 用户截图：赶车夫的长鞭说明被截成「已持有…」）：
##   godot --headless --path game --script res://tests/card_desc_fit_test.gd
## 按选卡面板电脑版的排法（screens/choice_panel.gd：卡宽 272 − 40，先 60 高 13 / 12 号，放不下切紧凑 108 高 13 / 12 / 11 号）
## 量每件藏品的说明（不含构筑提示行），列出紧凑布局仍要截断的。可见成长 7 件（docs/163）必须放得下；其余只报告。
## 全部通过时打印 "CARD DESC FIT failures=0"。

const UI = preload("res://scripts/ui.gd")
const RelicDb = preload("res://scripts/core/relic_db.gd")
const MUST := ["56", "58", "59", "63", "64", "129", "130"]


func _init() -> void:
	var font: Font = load("res://fonts/ui.ttf")
	var db = RelicDb.new()
	db.load_files()
	var w := 272.0 - 40.0
	var fails := 0
	var cut := 0
	for id in db.implemented():
		var r: Dictionary = db.get_relic(str(id))
		var d: String = str(r.get("desc", ""))
		var f0 := UI.fit(font, d, w, 60.0, [13, 12])
		if f0.fit:
			continue
		var f1 := UI.fit(font, d, w, 108.0, [13, 12, 11])
		if f1.fit:
			continue
		cut += 1
		var bad: bool = str(id) in MUST
		if bad:
			fails += 1
		print("%s #%s %s：%d 行 > %d（%s）" % ["FAIL" if bad else "截断", id, r.get("name", ""), UI._wrap_lines(font, d, 11, w).size(), f1.n, d.substr(0, 24)])
	print("CARD DESC FIT cut=%d failures=%d" % [cut, fails])
	quit(1 if fails > 0 else 0)
