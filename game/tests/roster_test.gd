extends Node
## 干员解锁单元测试（docs/109 §12，check.py 场景回归 roster）：以 --roster=start5 启动（新玩家名册，只在内存，测试局不写存档）。
## 1. 开局 5 人、其余未解锁；2. 第一张寻访凭证必出流明，之后先补齐缺的职业（近卫 / 特种），不重复，抽完名册满；
## 3. 意向干员 3 张内保底；4. 招募券只出所选职业；5. 局终发券（撤离 1 张寻访凭证；通关 +招募券；首通难度档 +人事调度函；演练 / 非 PLAY 不发）；
## 6. 云存档：解锁名单并集、券取较大值、Cfg 往返；7. 抽取不碰全局随机数之外的局内状态（同一状态抽两次结果相同）。
const Roster = preload("res://scripts/core/roster.gd")
const Pack = preload("res://scripts/core/cloud_pack.gd")

var failures := 0


class FakeTrial:
	var active := false


class FakeG:
	enum Mode { PLAY, AUTOTEST, BALANCE }
	var mode := 0
	var trial := FakeTrial.new()
	var demo_op := ""
	var tier := 0
	var roster_new := {}


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("ROSTER: " + what)
		print("FAIL ", what)


func reset() -> void:
	Cfg.roster_unlocked = []
	Cfg.roster_tickets = {}
	Cfg.roster_spare = {}
	Cfg.roster_tiers = []
	Cfg.roster_wish = ""
	Cfg.roster_pity = 0
	Cfg.roster_draws = 0
	Cfg.roster_seed = 12345


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	check(Roster.active(), "--roster=start5 下解锁规则应生效")
	reset()
	var all := Roster.all_ids()
	check(all.size() >= 18, "名册至少 18 人，实为 %d" % all.size())
	for s in Roster.STARTERS:
		check(Roster.is_unlocked(s), "开局干员 %s 应已解锁" % s)
	var n_locked := all.size() - Roster.STARTERS.size()
	check(Roster.locked_ids().size() == n_locked, "应有 %d 人未解锁，实为 %d" % [n_locked, Roster.locked_ids().size()])
	check(not Roster.owned_classes().has("医疗") and not Roster.owned_classes().has("近卫") and not Roster.owned_classes().has("特种"), "开局缺医疗 / 近卫 / 特种")

	# 2. 寻访顺序：流明 → 补齐近卫 / 特种 → 其余；不重复
	var c0 := Roster.choose_hunt()
	check(c0 == Roster.choose_hunt(), "同一状态抽两次应相同（独立随机数，只看存档状态）")
	Cfg.roster_tickets = {"hunt": n_locked}
	var got: Array = []
	for i in n_locked:
		var cid := Roster.choose_hunt()
		check(cid != "" and not got.has(cid) and not Roster.is_unlocked(cid), "第 %d 张寻访凭证抽到 %s（应为未解锁且不重复）" % [i + 1, cid])
		Roster.redeem(Roster.T_HUNT, cid)
		got.append(cid)
		if i == 0:
			check(cid == "lumen", "第一张寻访凭证应出流明，实为 " + cid)
		if i == 2:
			var oc := Roster.owned_classes()
			check(oc.has("近卫") and oc.has("特种") and oc.has("医疗"), "前 3 张后应补齐医疗 / 近卫 / 特种：%s" % [got])
	check(Roster.locked_ids().is_empty(), "%d 张寻访凭证后名册应满" % n_locked)
	check(Roster.choose_hunt() == "", "名册满后寻访应无可抽")
	check(int(Cfg.roster_tickets.get("hunt", 0)) == 0, "券应用完")

	# 3. 定向寻访：2 张寻访凭证指定 1 名；不够 2 张时不兑换
	reset()
	Cfg.roster_tickets = {"hunt": 3}
	var rd := Roster.redeem_directed("mizuki")
	check(rd.id == "mizuki" and Roster.is_unlocked("mizuki") and int(Cfg.roster_tickets.hunt) == 1, "定向寻访用 2 张解锁水月 %s / %s" % [rd, Cfg.roster_tickets])
	check(Roster.redeem_directed("skadi").get("id", "x") == "", "只剩 1 张时不能定向")
	check(Roster.redeem_directed("mizuki").get("id", "x") == "", "已解锁的不能再定向")
	for k in 5:
		var cid := Roster.choose_class("近卫")
		check(Roster.class_of(cid) == "近卫", "按职业抽（近卫）抽到 %s" % cid)

	# 4. 表现层接口：redeem_hunt / redeem_directed 返回结果、刚解锁高亮；旧券折算
	reset()
	Cfg.roster_fresh = []
	Cfg.roster_tickets = {"hunt": 3}
	var r1 := Roster.redeem_hunt()
	check(r1.id == "lumen" and r1.new_class and r1.kind == "hunt", "redeem_hunt 结果 %s" % [r1])
	var r3 := Roster.redeem_directed("irene")
	check(r3.id == "irene" and r3.new_class and Roster.tickets().hunt == 0, "redeem_directed 结果 %s" % [r3])
	check(Roster.fresh().size() == 2, "刚解锁应记 2 人")
	Roster.mark_seen("irene")
	check(not Roster.fresh().has("irene"), "mark_seen 后清掉")
	check(Roster.redeem_hunt().get("id", "x") == "", "没有券时不兑换")
	Cfg.roster_tickets = {"hunt": 1, "cls": 1, "pick": 1}
	Roster.migrate_tickets()
	check(Roster.tickets().hunt == 4 and Roster.tickets().cls == 0 and Roster.tickets().pick == 0, "旧券折算：招募券 1 + 人事调度函 2 %s" % [Cfg.roster_tickets])

	# 5. 局终发券：撤离 3 张、通关 4 张，只有寻访凭证
	reset()
	var fg := FakeG.new()
	Roster.on_run_end(fg, false)
	check(int(Cfg.roster_tickets.get("hunt", 0)) == 3 and int(Cfg.roster_tickets.get("cls", 0)) == 0, "撤离：寻访凭证 3 张 %s" % [Cfg.roster_tickets])
	Roster.on_run_end(fg, true)
	check(int(Cfg.roster_tickets.get("hunt", 0)) == 7 and int(Cfg.roster_tickets.get("cls", 0)) == 0 and int(Cfg.roster_tickets.get("pick", 0)) == 0, "通关：寻访凭证 4 张 %s" % [Cfg.roster_tickets])
	fg.trial.active = true
	Roster.on_run_end(fg, true)
	check(int(Cfg.roster_tickets.get("hunt", 0)) == 7, "演练不发券")
	fg.trial.active = false
	fg.mode = 1
	Roster.on_run_end(fg, false)
	check(int(Cfg.roster_tickets.get("hunt", 0)) == 7, "非 PLAY 模式不发券")

	# 6. 云存档
	reset()
	Cfg.roster_unlocked = ["lumen"]
	Cfg.roster_tickets = {"hunt": 2}
	var body: Dictionary = Cfg.cloud_body()
	check(body.prog.has("ops") and body.prog.ops == ["lumen"], "cloud_body 应带 ops")
	var other: Dictionary = body.duplicate(true)
	other.prog.ops = ["skadi"]
	other.prog.opst = {"tk": {"hunt": 1, "pick": 1}, "draws": 5, "pity": 2, "wish": "mizuki", "seed": 7}
	var m: Dictionary = Pack.merge(body, other)
	check(m.prog.ops.has("lumen") and m.prog.ops.has("skadi"), "解锁名单应取并集")
	check(int(m.prog.opst.tk.hunt) == 2 and int(m.prog.opst.tk.pick) == 1, "券应按种类取较大值 %s" % [m.prog.opst])
	check(int(m.prog.opst.draws) == 5 and int(m.prog.opst.pity) == 2 and str(m.prog.opst.wish) == "mizuki" and int(m.prog.opst.seed) == 12345, "抽取状态合并 %s" % [m.prog.opst])
	Cfg.cloud_apply(m)
	check(Cfg.roster_unlocked.has("skadi") and Cfg.roster_unlocked.has("lumen") and int(Cfg.roster_tickets.pick) == 1 and Cfg.roster_draws == 5, "cloud_apply 写回名册")
	var empty_cloud: Dictionary = Pack.merge(body, {})
	check(empty_cloud.prog.ops == ["lumen"], "云端为空时保持本地")

	print("ROSTER failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
