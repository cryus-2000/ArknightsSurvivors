extends RefCounted
## 干员解锁（局外成长 P1，docs/109 §12，用户 10-22 定）：开局 5 人，其余靠「寻访凭证 / 招募券 / 人事调度函」解锁。
## 数据在 Cfg（[roster] 存档段，settings.gd）；这里只放规则。抽取用独立的 RandomNumberGenerator（种子来自存档的 roster_seed + 已抽次数），
## 不碰局内 g.rng：同 seed 的对局结果与解锁无关。
## 测试局（任何 -- 启动参数）缺省「全部解锁」，招募池 / 选人页与改动前完全相同；--roster=start5 才按新玩家的名册跑（也不写存档）。
## 调试版 / 对内包的「全部解锁」（Cfg.unlock_all）同样视为全部解锁，存档里的真实名册不动。

const Character = preload("res://scripts/characters/character.gd")

## 开局固定的 5 人（用户 10-22：德克萨斯 / 星熊 / 艾雅法拉 / 铃兰 / 能天使 = 先锋 / 重装 / 术师 / 辅助 / 狙击）
const STARTERS := ["texas", "hoshiguma", "eyjafjalla", "suzuran", "exusiai"]
## 第一张寻访凭证必出的干员（开局没有医疗）
const FIRST_DRAW := "lumen"
## 同职业里先出「上手快」的那位：权重 2（其余 1）
const PRIORITY := {"lumen": 2, "skadi": 2, "specter_unchained": 2}
## 意向干员保底：连续 PITY - 1 张没出，第 PITY 张必出
const PITY := 3
## 三种券：寻访凭证（随机）/ 招募券（选职业）/ 人事调度函（指定）
const T_HUNT := "hunt"
const T_CLASS := "cls"
const T_PICK := "pick"
const TICKET_NAME := {"hunt": "寻访凭证", "cls": "招募券", "pick": "人事调度函"}


## 名册里所有可解锁的干员（data/characters 里允许招募的，按 id 排序，结果与目录遍历顺序无关）
static func all_ids() -> Array:
	var out: Array = []
	for cid in Character.list_ids():
		if Character.load_def(cid).get("recruitable", true):
			out.append(cid)
	out.sort()
	return out


## 测试局：有 -- 参数且没写 --roster= → 全部解锁（与改动前一致）
static func _test_all() -> bool:
	var any := false
	for a in Cfg.dev_args():
		if a.begins_with("--roster="):
			return false
		if a.begins_with("--"):
			any = true
	return any


## 解锁规则是否生效（false = 视为全部解锁：全部解锁开关、测试局）
static func active() -> bool:
	return not (Cfg.unlock_all or _test_all())


static func is_unlocked(cid: String) -> bool:
	if not active():
		return true
	return STARTERS.has(cid) or Cfg.roster_unlocked.has(cid)


static func locked_ids() -> Array:
	if not active():
		return []
	return all_ids().filter(func(c): return not is_unlocked(c))


static func class_of(cid: String) -> String:
	return str(Character.load_def(cid).get("class", ""))


## 已解锁干员覆盖的职业
static func owned_classes() -> Array:
	var out: Array = []
	for cid in all_ids():
		if is_unlocked(cid):
			var c := class_of(cid)
			if c != "" and not out.has(c):
				out.append(c)
	return out


## 还有未解锁干员的职业（招募券可选）
static func locked_classes() -> Array:
	var out: Array = []
	for cid in locked_ids():
		var c := class_of(cid)
		if c != "" and not out.has(c):
			out.append(c)
	return out


static func pending_total() -> int:
	var n := 0
	for k in [T_HUNT, T_CLASS, T_PICK]:
		n += int(Cfg.roster_tickets.get(k, 0))
	return n


static func _rng() -> RandomNumberGenerator:
	if Cfg.roster_seed == 0:
		var r0 := RandomNumberGenerator.new()
		r0.randomize()
		Cfg.roster_seed = maxi(1, r0.randi())
	var r := RandomNumberGenerator.new()
	r.seed = hash([Cfg.roster_seed, Cfg.roster_draws])
	return r


static func _weighted(ids: Array) -> String:
	if ids.is_empty():
		return ""
	var tot := 0.0
	for c in ids:
		tot += float(PRIORITY.get(c, 1))
	var x := _rng().randf() * tot
	for c in ids:
		x -= float(PRIORITY.get(c, 1))
		if x < 0.0:
			return c
	return ids[ids.size() - 1]


## 寻访凭证：第一张固定流明；意向干员到保底必出；还有职业一个都没有时只从缺的职业里抽；同职业「上手快」权重 2
static func choose_hunt() -> String:
	var locked := locked_ids()
	if locked.is_empty():
		return ""
	if Cfg.roster_draws == 0 and locked.has(FIRST_DRAW):
		return FIRST_DRAW
	if Cfg.roster_wish != "" and locked.has(Cfg.roster_wish) and Cfg.roster_pity >= PITY - 1:
		return Cfg.roster_wish
	var owned := owned_classes()
	var fresh: Array = locked.filter(func(c): return not owned.has(class_of(c)))
	return _weighted(fresh if not fresh.is_empty() else locked)


## 招募券：这个职业的未解锁干员里抽（同样按「上手快」权重）
static func choose_class(cls: String) -> String:
	return _weighted(locked_ids().filter(func(c): return class_of(c) == cls))


## 用掉一张券、解锁 cid（cid 由 choose_* 或玩家指定给出）。寻访凭证推进意向保底计数
static func redeem(kind: String, cid: String) -> void:
	if int(Cfg.roster_tickets.get(kind, 0)) <= 0 or cid == "" or is_unlocked(cid):
		return
	Cfg.roster_tickets[kind] = int(Cfg.roster_tickets[kind]) - 1
	Cfg.roster_draws += 1
	if kind == T_HUNT and Cfg.roster_wish != "":
		Cfg.roster_pity = 0 if cid == Cfg.roster_wish else Cfg.roster_pity + 1
	if cid == Cfg.roster_wish:
		Cfg.roster_wish = ""
		Cfg.roster_pity = 0
	Cfg.roster_unlocked.append(cid)
	Cfg.save()


static func set_wish(cid: String) -> void:
	if cid == Cfg.roster_wish:
		return
	Cfg.roster_wish = cid
	Cfg.roster_pity = 0
	Cfg.save()


## 一次探索结束（state 进入 DEAD / WIN，game.gd _process 调一次）：发券。
## 寻访凭证每次 1 张（撤离也给）；通关 1 张招募券；首通某一难度档 1 张人事调度函。
## 不发：演练、练习、图鉴演示、非 PLAY 模式、全部解锁 / 测试局（active() 为假）。名册已满时券记进 roster_spare（P2 换生机细胞）
static func on_run_end(g, won: bool) -> void:
	if not active() or g.mode != g.Mode.PLAY or g.trial.active or g.demo_op != "" or Cfg.practice_active:
		return
	var add := {T_HUNT: 1}
	if won:
		add[T_CLASS] = 1
		if not Cfg.roster_tiers.has(int(g.tier)):
			Cfg.roster_tiers.append(int(g.tier))
			add[T_PICK] = 1
	var full := locked_ids().is_empty()
	for k in add:
		if full:
			Cfg.roster_spare[k] = int(Cfg.roster_spare.get(k, 0)) + add[k]
		else:
			Cfg.roster_tickets[k] = int(Cfg.roster_tickets.get(k, 0)) + add[k]
	g.roster_new = add.duplicate() if not full else {}
	Cfg.save()


## 名册已满后剩下的券转入 roster_spare（结算演出里遇到「已无人可解锁」时调用）
static func spill_to_spare() -> void:
	for k in [T_HUNT, T_CLASS, T_PICK]:
		var n := int(Cfg.roster_tickets.get(k, 0))
		if n > 0:
			Cfg.roster_spare[k] = int(Cfg.roster_spare.get(k, 0)) + n
			Cfg.roster_tickets[k] = 0
	Cfg.save()
