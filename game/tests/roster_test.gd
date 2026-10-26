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
	var t := 600.0
	var roster_new := {}


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("ROSTER: " + what)
		print("FAIL ", what)


## 旧版开局（--roster=start5：开局 5 人写在名册里），下面 1–8 节按它写；新手十连见第 9 节
func reset() -> void:
	Cfg.roster_unlocked = Roster.STARTERS.duplicate()
	Cfg.roster_v = 2
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
	# 倒下时探索不足 RUN_MIN_T 秒不发（10-26：开局即倒下 / 重开刷券）；通关不受限；刚好到线照发
	fg.t = Roster.RUN_MIN_T - 1.0
	Roster.on_run_end(fg, false)
	check(Roster.tickets() == 7 and int(fg.roster_new.get("hunt", -1)) == 0 and bool(fg.roster_new.get("short", false)), "倒下时不足 %d 秒：不发（%d 张，%s）" % [int(Roster.RUN_MIN_T), Roster.tickets(), fg.roster_new])
	fg.t = 30.0
	Roster.on_run_end(fg, true)
	check(Roster.tickets() == 11, "通关不受时长限制：+4（%d）" % Roster.tickets())
	fg.t = Roster.RUN_MIN_T
	Roster.on_run_end(fg, false)
	check(Roster.tickets() == 14 and not fg.roster_new.has("short"), "倒下时刚好 %d 秒：照发 3 张（%d）" % [int(Roster.RUN_MIN_T), Roster.tickets()])
	Cfg.roster_tickets = {"hunt": 7}
	fg.t = 600.0
	Cfg.roster_unlocked = Roster.all_ids()
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
	Cfg.roster_unlocked = Roster.all_ids()
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

	# 9. 新手开局 + 新手十连（10-26 用户）：名册为空、10 张；十连从全部干员纯随机抽 10 名、不重复（不限定职业）；只在名册为空时可用；
	# 凭证不够不扣；同一存档种子结果固定；旧云档（没有 rv）补开局 5 人
	reset()
	Cfg.roster_unlocked = []
	Cfg.roster_tickets = {"hunt": Roster.FIRST_TICKETS}
	check(Roster.needs_first() and not Roster.is_unlocked("texas"), "新手开局：名册为空（旧开局 5 人不再默认解锁）")
	check(Roster.rarity("texas") == 5 and Roster.rarity("lappland") == 5 and Roster.rarity("skadi") == 6, "原作稀有度")
	var ten := Roster.redeem_ten()
	var tids := {}
	var tcls := {}
	for r in ten:
		tids[r.id] = true
		tcls[Roster.class_of(r.id)] = true
	check(ten.size() == Roster.TEN and tids.size() == Roster.TEN and Roster.tickets() == 0 and Cfg.roster_draws == Roster.TEN, "十连：10 名不同干员、10 张用完（%s）" % [tids.keys()])
	check(not Roster.needs_first() and Roster.locked_ids().size() == Roster.all_ids().size() - Roster.TEN, "十连后新手引导结束、剩 %d 人待寻访" % Roster.locked_ids().size())
	Cfg.roster_tickets = {"hunt": 10}
	check(Roster.redeem_ten().is_empty() and Roster.tickets() == 10, "名册不为空时不能再十连")
	reset()
	Cfg.roster_unlocked = []
	Cfg.roster_tickets = {"hunt": 9}
	check(Roster.redeem_ten().is_empty() and Roster.tickets() == 9 and Cfg.roster_unlocked.is_empty(), "凭证不够 10 张不十连、不扣")
	var first_ids: Array = ten.map(func(r): return r.id)
	reset()
	Cfg.roster_unlocked = []
	Cfg.roster_tickets = {"hunt": 10}
	check(Roster.redeem_ten().map(func(r): return r.id) == first_ids, "同一存档种子十连结果相同")
	# 纯随机（不补齐职业）：40 个种子里每次 10 人不重复；全体出现次数应铺开到整个池子（每名干员都被抽到过），
	# 且至少有一次没覆盖全部 8 个职业（证明不再强制补齐）
	var seen := {}
	var partial := 0
	var dup := 0
	for sd in range(1, 41):
		reset()
		Cfg.roster_seed = sd
		Cfg.roster_unlocked = []
		Cfg.roster_tickets = {"hunt": 10}
		var cs := {}
		var ids2 := {}
		for r in Roster.redeem_ten():
			cs[Roster.class_of(r.id)] = true
			ids2[r.id] = true
			seen[r.id] = true
		if ids2.size() != Roster.TEN:
			dup += 1
		if cs.size() < 8:
			partial += 1
	check(dup == 0, "40 个种子的十连都 10 人不重复（%d 次重复）" % dup)
	check(seen.size() == Roster.all_ids().size(), "纯随机铺满整个池子（抽到过 %d / %d 名）" % [seen.size(), Roster.all_ids().size()])
	check(partial > 0, "不再强制补齐职业（40 次里 %d 次没覆盖全部职业）" % partial)
	# 旧版本写的云档（没有 rv）：开局 5 人不在 ops 里，读进新设备（空名册）时补上
	reset()
	Cfg.roster_unlocked = []
	Cfg.roster_tickets = {"hunt": 10}
	var nb2: Dictionary = Cfg.cloud_body()
	check(int(nb2.prog.get("rv", 0)) == 2, "cloud_body 带 rv=2")
	var old_cloud: Dictionary = nb2.duplicate(true)
	old_cloud.prog.erase("rv")
	old_cloud.prog.ops = ["lumen"]
	old_cloud.prog.opst = {"tk": {"hunt": 1}, "draws": 3, "seed": 9}
	var mo: Dictionary = Pack.merge(nb2, old_cloud)
	Cfg.cloud_apply(mo)
	check(Cfg.roster_unlocked.has("lumen") and Roster.STARTERS.all(func(c): return Cfg.roster_unlocked.has(c)) and not Roster.needs_first(), "旧云档补开局 5 人：%s" % [Cfg.roster_unlocked])
	reset()

	print("ROSTER failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
