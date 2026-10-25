extends Node
## 干员解锁单元测试（docs/109 §12，check.py 场景回归 roster）：以 --roster=start5 启动（新玩家名册，只在内存，测试局不写存档）。
## 1. 开局 5 人、其余未解锁；2. 随机寻访前 3 次补齐缺的职业（医疗 / 近卫 / 特种），不重复，抽完名册满；
## 3. 意向干员 3 张内保底；4. 招募券只出所选职业；5. 局终发券（撤离 1 张寻访凭证；通关 +招募券；首通难度档 +人事调度函；演练 / 非 PLAY 不发）；
## 6. 云存档：解锁名单并集、券取较大值、Cfg 往返；7. 抽取不碰全局随机数之外的局内状态（同一状态抽两次结果相同）。
const Roster = preload("res://scripts/core/roster.gd")
const Pack = preload("res://scripts/core/cloud_pack.gd")
const Meta = preload("res://scripts/core/meta.gd")

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
	Cfg.meta_earned = {}
	Cfg.meta_bought = {}
	Cfg.meta_shape = {}


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

	# 2. 随机寻访：前 3 张补齐医疗 / 近卫 / 特种（不再必出流明），不重复，抽完名册满
	var c0 := Roster.choose_hunt()
	check(c0 == Roster.choose_hunt(), "同一状态抽两次应相同（独立随机数，只看存档状态）")
	Cfg.roster_tickets = {"hunt": n_locked}
	var got: Array = []
	for i in n_locked:
		var r := Roster.redeem_random()
		var cid: String = r.get("id", "")
		check(cid != "" and not got.has(cid), "第 %d 次随机寻访抽到 %s（应为未解锁且不重复）" % [i + 1, cid])
		got.append(cid)
		if i == 2:
			var oc := Roster.owned_classes()
			check(oc.has("近卫") and oc.has("特种") and oc.has("医疗"), "前 3 次后应补齐医疗 / 近卫 / 特种：%s" % [got])
	check(Roster.locked_ids().is_empty(), "%d 次随机寻访后名册应满" % n_locked)
	check(Roster.choose_hunt() == "", "名册满后寻访应无可抽")
	check(Roster.tickets() == 0, "凭证应用完")

	# 3. 定向寻访：花 2 张，直接解锁点名的干员；凭证不够不能用
	reset()
	Cfg.roster_fresh = []
	Cfg.roster_tickets = {"hunt": 3}
	var r1 := Roster.redeem_pick("mizuki")
	check(r1.id == "mizuki" and r1.kind == "pick" and r1.new_class and Roster.is_unlocked("mizuki") and Roster.tickets() == 1, "定向寻访结果 %s，余 %d" % [r1, Roster.tickets()])
	check(Roster.redeem_pick("skadi").get("id", "x") == "" and not Roster.is_unlocked("skadi"), "只剩 1 张时不能定向")
	check(Roster.redeem_pick("texas").get("id", "x") == "", "已解锁的干员不能定向")
	var r2 := Roster.redeem_random()
	check(r2.id != "" and r2.kind == "random" and Roster.tickets() == 0, "随机寻访花 1 张 %s" % [r2])
	check(Roster.locked_in_class("近卫").all(func(c): return Roster.class_of(c) == "近卫"), "按职业列未解锁干员")
	check(Roster.fresh().size() == 2, "刚解锁应记 2 人")
	Roster.mark_seen("mizuki")
	check(not Roster.fresh().has("mizuki"), "mark_seen 后清掉")
	check(Roster.redeem_random().get("id", "x") == "", "没有凭证时不兑换")

	# 4. 旧存档三种券折算（1:1 / 1:1 / 1:2），意向与保底清空
	reset()
	Cfg.roster_tickets = {"hunt": 1, "cls": 2, "pick": 3}
	Cfg.roster_wish = "mizuki"
	Cfg.roster_pity = 2
	Roster.migrate_tickets()
	check(Roster.tickets() == 9 and not Cfg.roster_tickets.has("cls") and Cfg.roster_wish == "" and Cfg.roster_pity == 0, "旧券折算 %s" % [Cfg.roster_tickets])

	# 5. 局终发凭证：撤离 3 张、通关 4 张；演练 / 非 PLAY 不发；名册已满不发、剩下的折生机细胞
	reset()
	var fg := FakeG.new()
	Roster.on_run_end(fg, false)
	check(Roster.tickets() == 3, "撤离：3 张，实为 %d" % Roster.tickets())
	Roster.on_run_end(fg, true)
	check(Roster.tickets() == 7, "通关：再 4 张，实为 %d" % Roster.tickets())
	fg.trial.active = true
	Roster.on_run_end(fg, true)
	check(Roster.tickets() == 7, "演练不发")
	fg.trial.active = false
	fg.mode = 1
	Roster.on_run_end(fg, false)
	check(Roster.tickets() == 7, "非 PLAY 模式不发")
	fg.mode = 0
	Cfg.roster_unlocked = Roster.all_ids().filter(func(c): return not Roster.STARTERS.has(c))
	Cfg.meta_earned = {}
	Cfg.meta_dev = "dtest"
	Roster.on_run_end(fg, true)
	check(Roster.tickets() == 0 and int(Cfg.meta_earned.get("dtest", 0)) == 7 * Roster.CELLS_PER_TICKET, "名册已满：不发，剩 7 张折 %d 生机细胞（%s）" % [7 * Roster.CELLS_PER_TICKET, Cfg.meta_earned])

	# 6. 云存档
	reset()
	Cfg.roster_unlocked = ["lumen"]
	Cfg.roster_tickets = {"hunt": 2}
	var body: Dictionary = Cfg.cloud_body()
	check(body.prog.has("ops") and body.prog.ops == ["lumen"], "cloud_body 应带 ops")
	var other: Dictionary = body.duplicate(true)
	other.prog.ops = ["skadi"]
	other.prog.opst = {"tk": {"hunt": 1, "pick": 1}, "draws": 5, "seed": 7}
	var m: Dictionary = Pack.merge(body, other)
	check(m.prog.ops.has("lumen") and m.prog.ops.has("skadi"), "解锁名单应取并集")
	check(int(m.prog.opst.tk.hunt) == 2 and int(m.prog.opst.tk.pick) == 1, "券应按种类取较大值 %s" % [m.prog.opst])
	check(int(m.prog.opst.draws) == 5 and int(m.prog.opst.seed) == 12345, "抽取状态合并 %s" % [m.prog.opst])
	Cfg.cloud_apply(m)
	check(Cfg.roster_unlocked.has("skadi") and Cfg.roster_unlocked.has("lumen") and Roster.tickets() == 4 and Cfg.roster_draws == 5, "cloud_apply 写回名册（旧云档的人事调度函按 1:2 折凭证：2 + 2 = 4，实为 %d）" % Roster.tickets())
	var empty_cloud: Dictionary = Pack.merge(body, {})
	check(empty_cloud.prog.ops == ["lumen"], "云端为空时保持本地")

	# 8. 用生机细胞兑换寻访凭证（用户 10-25）：1 张 = 15 细胞，不设上限；记账进 meta_bought，余额同步减；不够不兑；满员隐藏
	reset()
	Cfg.meta_dev = "dtest"
	check(Roster.TICKET_PRICE == 15 and Roster.TICKET_PRICE > Roster.CELLS_PER_TICKET, "买价 15 高于满员折价 %d" % Roster.CELLS_PER_TICKET)
	check(Roster.exchange_visible() and Roster.exchange_short() == Roster.TICKET_PRICE, "新档：入口可见、还差 15")
	check(not Roster.exchange_ticket() and Roster.tickets() == 0 and Cfg.meta_bought.is_empty(), "细胞不够不兑换、不扣")
	Cfg.meta_earned = {"dtest": 14}
	check(Roster.exchange_short() == 1 and not Roster.exchange_ticket() and Meta.available() == 14, "14 个细胞还差 1，仍不兑换")
	Cfg.meta_earned = {"dtest": 100}
	check(Roster.exchange_ticket() and Roster.tickets() == 1 and Meta.available() == 85 and int(Cfg.meta_bought.dtest) == 15, "兑换 1 张：凭证 +1、细胞 −15（余额 %d）" % Meta.available())
	for _i in 5:
		Roster.exchange_ticket()
	check(Roster.tickets() == 6 and Meta.available() == 10 and not Roster.exchange_ticket() and Roster.tickets() == 6, "连兑到不够为止（6 张，余 10），不设购买上限")
	Cfg.meta_shape = {"sh1": true}
	check(Meta.available() == 100 - 90 - Meta.spent(Cfg.meta_shape), "认知塑造与兑换共用同一余额")
	Cfg.meta_shape = {}
	Cfg.meta_earned = {"dtest": 1000}
	Cfg.roster_unlocked = Roster.all_ids().filter(func(c): return not Roster.STARTERS.has(c))
	check(not Roster.exchange_visible() and not Roster.exchange_ticket() and Cfg.meta_bought.dtest == 90, "名册已满：入口隐藏、不兑换、不扣")
	Cfg.roster_unlocked = []
	# 存档往返 + 云存档：兑换花费逐设备取大（只增不减）
	Cfg.roster_tickets = {"hunt": 6}
	var body2: Dictionary = Cfg.cloud_body()
	check(int(body2.prog.meta.bought.dtest) == 90, "cloud_body 带 bought")
	var other2: Dictionary = body2.duplicate(true)
	other2.prog.meta.bought = {"dtest": 30, "dother": 45}
	var m2: Dictionary = Pack.merge(body2, other2)
	check(int(m2.prog.meta.bought.dtest) == 90 and int(m2.prog.meta.bought.dother) == 45, "bought 逐设备取大 %s" % [m2.prog.meta.bought])
	Cfg.meta_bought = {}
	Cfg.cloud_apply(m2)
	check(Meta.bought_total() == 135, "cloud_apply 写回兑换记账 %s" % [Cfg.meta_bought])
	Cfg.meta_bought = {}
	var nb: Dictionary = Cfg.cloud_body()
	check(not nb.prog.meta.has("bought"), "没兑换过的存档不写 bought（与旧版本往返相同）")
	reset()

	print("ROSTER failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
