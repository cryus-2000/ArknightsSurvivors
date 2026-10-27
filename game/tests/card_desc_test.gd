extends Node
## 卡片描述不串台的回归（用户 10-22 截图：公共成长卡「协同·广」里混进队长乌尔比安 S3 的「技力满后队长按 E 释放」）：
##   godot --headless --path game res://tests/card_desc_test.tscn -- --regression --balance --seed=1 --op=ulpianus --squad=skadi,angelina
## 第 5 帧直接查 choice_panel.option_description：公共成长 / 填充 / 支援卡描述等于原文，不含技能名与按键提示；
## 干员卡只提自己的技能；招募 / 藏品卡不带技能提示。全部通过打印 "CARD DESC failures=0"。

const Character = preload("res://scripts/characters/character.gd")
var game: Node
var frames := 0
var n := 0
var fails := 0


func _ready() -> void:
	game = load("res://game.tscn").instantiate()
	add_child(game)


func _process(_d: float) -> void:
	frames += 1
	if frames != 5:
		return
	test_card_desc_isolation()
	test_brief_all()
	print("%d checks, %d failed" % [n, fails])
	print("CARD DESC failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		fails += 1
		printerr("FAIL: ", what)


## 卡片描述不串台（用户 10-22 截图：「协同·广」里混进乌尔比安 S3 的「按 E 释放」）：队长是有手动技能的乌尔比安时，
## 公共成长卡（生存 / 机动 / 协同 / 填充 / 支援）的描述必须等于原文，不含任何技能名 / 按键提示；干员卡的提示只提自己的技能
func test_card_desc_isolation() -> void:
	ok(game.ch.id == "ulpianus" and game.ch.skill_def(2).get("mode", "auto") == "manual", "队长是乌尔比安（S3 手动技能）")
	game.ch.elite = 2   # 截图里是精二：S3 已解锁，提示才会出现（精零时 i > stage 直接跳过）
	var hints := ["释放", "技能键", "按 Q", "技力满后", "解锁后"]
	var skill_names: Array = []
	for o in game.squad.ops:
		for i in 3:
			skill_names.append(str(o.skill_def(i).get("name", "")))
	var pub: Array = game.doctor.passive_cards("doctor") + game.doctor.passive_cards("mobility") + game.doctor.passive_cards("squad") + game.doctor.filler_cards()
	pub.append({"kind": "weapon", "id": "drone", "name": "医疗无人机", "desc": "x", "wlv": 1})
	ok(pub.size() >= 8, "公共卡样本 %d 张" % pub.size())
	for c in pub:
		var d: String = game.panel_ui.option_description(c)
		ok(d == str(c.get("desc", "")), "公共卡「%s」描述等于原文（%s）" % [c.get("name", ""), d.substr(0, 40)])
		for h in hints:
			ok(not d.contains(h), "公共卡「%s」不含「%s」" % [c.get("name", ""), h])
		for sn in skill_names:
			ok(sn == "" or not d.contains(sn), "公共卡「%s」不含技能名「%s」" % [c.get("name", ""), sn])
	# 干员卡：只提自己的技能，队友写「自动释放」、不写「按 Q」
	for o in game.squad.ops:
		for c in o.deep_cards():
			var d: String = game.panel_ui.option_description(c)
			ok(not d.contains("按 Q") or o.is_leader, "干员卡「%s」（%s）队友不写按 Q" % [c.get("name", ""), o.id])
			for o2 in game.squad.ops:
				if o2 == o:
					continue
				for i in 3:
					var sn: String = str(o2.skill_def(i).get("name", ""))
					ok(sn == "" or not d.contains("「%s」" % sn), "干员卡「%s」（%s）不提别人的技能「%s」" % [c.get("name", ""), o.id, sn])
	# 招募 / 藏品卡也不带技能提示
	for c in game.progression.recruit_cards().slice(0, 3):
		var d: String = game.panel_ui.option_description(c)
		for h in hints:
			ok(not d.contains(h), "招募卡「%s」不含「%s」" % [c.get("name", ""), h])
	for rid in ["97", "130", "1"]:
		var d: String = game.panel_ui.option_description({"kind": "relic", "id": rid, "name": rid, "desc": game.rfx.display_desc(rid)})
		for h in hints:
			ok(not d.contains(h), "藏品卡 %s 不含「%s」" % [rid, h])


## 一句话版 / 全文版全量检查（10-26 用户：水月「病理性依恋·缠缚」卡上只剩「「囚徒困境」期间每秒」）：
## 全部干员的成长节点（含分支 / 路线 / 精英化选项）、全部藏品、招募卡——全文不含没替换的 {…} 占位；
## 一句话（choice_panel.brief）不以「每秒 / 期间 / 的」这类半截词结尾；全文第一句有数字时一句话也要有数字；精英化卡的「解锁N技能 · 名」带技能名
func test_brief_all() -> void:
	var CP = game.panel_ui
	var re_num := RegEx.create_from_string("[0-9]")
	var texts: Array = []   # [来源, 全文]
	for cid in Character.list_ids():
		var d: Dictionary = Character.load_def(cid)
		_collect(d.get("progression", []), cid, texts)
	for rid in game.RL.keys():
		texts.append(["藏品 %s %s" % [rid, game.RL[rid].name], game.rfx.display_desc(rid)])
	for c in game.progression.recruit_cards():
		texts.append(["招募 %s" % c.get("name", ""), CP.option_description(c)])
	ok(texts.size() > 200, "一句话检查样本 %d 条" % texts.size())
	for t in texts:
		var full: String = str(t[1])
		ok(not (full.contains("{") and full.contains("}")), "%s 全文含没替换的占位：%s" % [t[0], full])
		var b: String = CP.brief(full)
		ok(CP.brief_whole(b), "%s 一句话是半截：「%s」（全文：%s）" % [t[0], b, full])
		var first: String = full.split("\n")[0]
		for sep in ["；", "。"]:
			if first.find(sep) > 0:
				first = first.substr(0, first.find(sep))
		ok(re_num.search(first) == null or re_num.search(b) != null, "%s 一句话丢了数字：「%s」（全文：%s）" % [t[0], b, full])
	# 精英化卡：每位在队干员的精英化一句话带技能名
	for o in game.squad.ops:
		for lv in [1, 2]:
			var hl: String = CP.headline({"kind": "prog", "op": o.id, "elite": lv})
			ok(hl == "" or (hl.begins_with("解锁") and hl.length() > 8), "%s 精英%d 一句话「%s」" % [o.id, lv, hl])


func _collect(v, src: String, out: Array) -> void:
	if v is Dictionary:
		if v.get("desc") is String and str(v.desc) != "":
			out.append(["%s · %s" % [src, v.get("name", v.get("id", ""))], str(v.desc)])
		for k in v:
			if v[k] is Dictionary or v[k] is Array:
				_collect(v[k], src, out)
	elif v is Array:
		for x in v:
			_collect(x, src, out)
