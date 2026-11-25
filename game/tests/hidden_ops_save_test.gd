extends Node
## 暂不上线干员的老存档兜底（11-25，check.py 场景回归 hidden_ops_save）：11-20 那版 Toy 里令 / 傀影 / 史尔特尔 / 夕 / 黍 / 菲亚梅塔还可见，
## 老存档的封面 / 意向 / 名册 / 刚解锁里可能有这些 id；导出包里这 6 人整块删掉了（tools/release_slim.drop_hidden_ops）。
## 拿一份含这些 id 的存档样本喂 Cfg._read_cfg，断言：封面退回水月、意向清空、刚解锁不含、名册 id 原样留在存档里但名册 / 寻访 / 图鉴都看不到；
## Character.load_def 对读不到的 HIDDEN id 静默返回空定义。在仓库里（文件还在）和删过文件的打包副本里都要过（云端冒烟跑后者）。
## 只改内存里的 Cfg，不调 save()。

const Roster = preload("res://scripts/core/roster.gd")
const OpDefs = preload("res://scripts/characters/operator_defs.gd")
const Character = preload("res://scripts/characters/character.gd")

var failures := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("HIDDEN OPS SAVE: " + what)
		print("FAIL ", what)


func _ready() -> void:
	var hid: Array = OpDefs.HIDDEN
	var stripped := not FileAccess.file_exists("res://data/characters/%s.json" % hid[0])
	print("HIDDEN OPS SAVE: 打包副本（文件已删）=%s" % str(stripped))
	var c := ConfigFile.new()
	c.set_value("display", "cover_character", "ling")
	c.set_value("progress", "diff_ver", 4)
	c.set_value("roster", "v", 2)
	c.set_value("roster", "unlocked", ["mizuki", "ling", "phantom", "skadi", "surtr", "dusk", "shu", "fiammetta"])
	c.set_value("roster", "fresh", ["ling", "skadi", "shu"])
	c.set_value("roster", "wish", "surtr")
	c.set_value("roster", "tickets", {"hunt": 3})
	Cfg._read_cfg(c)
	check(Cfg.cover_character_id == "mizuki", "封面 ling → mizuki（%s）" % Cfg.cover_character_id)
	check(Cfg.roster_wish == "", "意向 surtr → 空（%s）" % Cfg.roster_wish)
	check(Cfg.roster_fresh == ["skadi"], "刚解锁只留 skadi（%s）" % str(Cfg.roster_fresh))
	check(Cfg.roster_unlocked.has("ling") and Cfg.roster_unlocked.has("surtr"), "名册里的 HIDDEN id 原样留在存档（以后上线还认）")
	# 用的地方：名单 / 名册 / 刚解锁 / 职业都看不到
	for cid in hid:
		check(not Character.list_ids().has(cid), "名单不含 %s" % cid)
		check(not Roster.all_ids().has(cid), "名册不含 %s" % cid)
		check(not Roster.fresh().has(cid), "刚解锁高亮不含 %s" % cid)
		check(not OpDefs.usable(cid), "usable(%s) = false" % cid)
		var d: Dictionary = Character.load_def(cid)
		if stripped:
			check(d.size() == 1 and str(d.get("id", "")) == cid, "打包副本里 load_def(%s) 静默返回空定义（%s）" % [cid, str(d.keys())])
	check(not Roster.needs_first(), "名册里有可用干员（mizuki / skadi），不当新玩家")
	var owned := Roster.owned_classes()
	check(owned.size() > 0 and not owned.has(""), "已解锁职业不出空条目（%s）" % str(owned))
	for cid in Roster.locked_ids():
		check(not hid.has(cid), "未解锁名单不含 %s" % cid)
	print("HIDDEN OPS SAVE failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
