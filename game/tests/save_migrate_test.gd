extends Node
## 存档迁移样本测试（docs/126 R1，check.py 场景回归 save_migrate）：拿各个历史版本的 settings.cfg 片段直接喂 Cfg._read_cfg，
## 断言迁移结果。只改内存里的 Cfg，不调 save()，不碰 user://settings.cfg。
## 覆盖：难度 diff_ver 1 / 2 / 3 / 4（11 级累计档 → 三档、三档原样、潮位 → 三档、当前）、旧 2× 倍速、观感 look_ver 0 的旧缺省亮度、
## 三种旧券 → 单一寻访凭证（含 spare）、没有 [roster] 段的老存档（打过的全部解锁 / 新档保持开局 5 人）。

const Roster = preload("res://scripts/core/roster.gd")
const Look = preload("res://scripts/render/look.gd")

var failures := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("SAVE MIGRATE: " + what)
		print("FAIL ", what)


## 一份存档样本：progress / roster 段按需写；roster = null 表示老存档没有 [roster] 段
func sample(diff_ver, difficulty: int, unlocked: int, roster = {}, extra := {}) -> ConfigFile:
	var c := ConfigFile.new()
	if diff_ver != null:
		c.set_value("progress", "diff_ver", diff_ver)
	c.set_value("progress", "difficulty", difficulty)
	c.set_value("progress", "diff_unlocked", unlocked)
	c.set_value("progress", "endings_cleared", [])
	c.set_value("progress", "seen_relics", [])
	if roster != null:
		c.set_value("roster", "unlocked", roster.get("unlocked", []))
		c.set_value("roster", "tickets", roster.get("tickets", {}))
		c.set_value("roster", "spare", roster.get("spare", {}))
	for k in extra:
		var sk: PackedStringArray = str(k).split("/")
		c.set_value(sk[0], sk[1], extra[k])
	return c


func load_sample(c: ConfigFile) -> void:
	Cfg.roster_unlocked = []
	Cfg.roster_tickets = {}
	Cfg.roster_spare = {}
	Cfg.endings_cleared = []
	Cfg.seen_relics = []
	Cfg._read_cfg(c)


func _ready() -> void:
	# 难度：v1（或没写）= 11 级累计档。旧解锁 0 → 0；1–4（通关过第 0 档）→ 1；≥ 5（通关过 Ⅳ）→ 2；选的难度落到所在档且不超过解锁
	for case in [[null, 0, 0, 0, 0], [1, 3, 3, 0, 1], [1, 5, 5, 1, 2], [1, 9, 9, 2, 2], [1, 9, 3, 1, 1]]:
		load_sample(sample(case[0], case[1], case[2]))
		check(Cfg.difficulty == case[3] and Cfg.diff_unlocked == case[4], "diff_ver %s：难度 %d / 解锁 %d → 应为 %d / %d，实际 %d / %d" % [str(case[0]), case[1], case[2], case[3], case[4], Cfg.difficulty, Cfg.diff_unlocked])
	# v2：三档下标，原样
	load_sample(sample(2, 1, 2))
	check(Cfg.difficulty == 1 and Cfg.diff_unlocked == 2, "diff_ver 2 三档原样（%d / %d）" % [Cfg.difficulty, Cfg.diff_unlocked])
	# v3：潮位 0–15 → < 5 标准、< 10 困难、其余极限；难度不超过解锁
	for case in [[3, 4, 0, 0], [7, 12, 1, 2], [12, 7, 1, 1]]:
		load_sample(sample(3, case[0], case[1]))
		check(Cfg.difficulty == case[2] and Cfg.diff_unlocked == case[3], "diff_ver 3 潮位 %d / %d → 应为 %d / %d，实际 %d / %d" % [case[0], case[1], case[2], case[3], Cfg.difficulty, Cfg.diff_unlocked])
	# v4（当前）与更新版本写的存档：原样
	for dv in [4, 5]:
		load_sample(sample(dv, 2, 2))
		check(Cfg.difficulty == 2 and Cfg.diff_unlocked == 2, "diff_ver %d 原样（%d / %d）" % [dv, Cfg.difficulty, Cfg.diff_unlocked])
	# 旧 2× 倍速 → 1.5×；不认识的倍速 → 1×
	load_sample(sample(4, 0, 0, {}, {"game/play_speed": 2.0}))
	check(is_equal_approx(Cfg.play_speed, 1.5), "倍速 2× → 1.5×（%.2f）" % Cfg.play_speed)
	load_sample(sample(4, 0, 0, {}, {"game/play_speed": 3.0}))
	check(is_equal_approx(Cfg.play_speed, 1.0), "倍速 3× → 1×（%.2f）" % Cfg.play_speed)
	# 观感：look_ver 0 且亮度是旧缺省 110% → 新缺省；自己调过的不动；look_ver 1 不动
	load_sample(sample(4, 0, 0, {}, {"video/brightness": 1.1, "video/look_ver": 0}))
	check(is_equal_approx(Cfg.brightness, Look.p("bright_def")), "look_ver 0 旧缺省亮度 → 新缺省（%.2f）" % Cfg.brightness)
	load_sample(sample(4, 0, 0, {}, {"video/brightness": 1.2, "video/look_ver": 0}))
	check(is_equal_approx(Cfg.brightness, 1.2), "look_ver 0 自调亮度不动（%.2f）" % Cfg.brightness)
	# 三种旧券 → 单一寻访凭证：寻访 1:1、招募 1:1、人事调度函 1:2；spare 一并折入
	load_sample(sample(4, 0, 0, {"tickets": {"hunt": 1, "cls": 2, "pick": 3}, "spare": {"hunt": 1, "pick": 1}}))
	check(int(Cfg.roster_tickets.get(Roster.T_HUNT, -1)) == 1 + 2 + 6 + 1 + 2 and Cfg.roster_spare.is_empty() and not Cfg.roster_tickets.has("cls"),
		"旧券折算（%s / spare %s）" % [str(Cfg.roster_tickets), str(Cfg.roster_spare)])
	# 没有 [roster] 段：打过的（解锁过难度）全部解锁、新档保持开局 5 人
	load_sample(sample(4, 0, 1, null))
	var others: Array = Roster.all_ids().filter(func(cid): return not Roster.STARTERS.has(cid))
	check(Cfg.roster_unlocked.size() == others.size() and not others.is_empty(), "老存档打过 → 全部解锁（%d / %d）" % [Cfg.roster_unlocked.size(), others.size()])
	load_sample(sample(4, 0, 0, null))
	check(Cfg.roster_unlocked.is_empty(), "老存档没打过 → 保持开局 5 人（%d）" % Cfg.roster_unlocked.size())
	print("SAVE MIGRATE failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
