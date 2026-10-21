extends RefCounted
## 干员解锁（局外成长 P1，docs/109 §12，用户 10-22 定；10-22 晚改为单一「寻访凭证」）：开局 5 人，其余用寻访凭证解锁。
## 每次探索结束发 3 张（通关 4 张）；随机寻访花 1 张，定向寻访花 2 张、直接解锁玩家点名的干员。
## 还有职业一个都没解锁时，随机寻访只从这些职业里抽（开局缺医疗 / 近卫 / 特种，首局 3 张随机正好各出 1 名）。
## 数据在 Cfg（[roster] 存档段，settings.gd）；这里只放规则。抽取用独立的 RandomNumberGenerator（种子来自存档的 roster_seed + 已抽次数），
## 不碰局内 g.rng：同 seed 的对局结果与解锁无关。
## 测试局（任何 -- 启动参数）缺省「全部解锁」，招募池 / 选人页与改动前完全相同；--roster=start5 才按新玩家的名册跑（也不写存档）。
## 调试版 / 对内包的「全部解锁」（Cfg.unlock_all）同样视为全部解锁，存档里的真实名册不动。

const Character = preload("res://scripts/characters/character.gd")

## 开局固定的 5 人（用户 10-22：德克萨斯 / 星熊 / 艾雅法拉 / 铃兰 / 能天使 = 先锋 / 重装 / 术师 / 辅助 / 狙击）
const STARTERS := ["texas", "hoshiguma", "eyjafjalla", "suzuran", "exusiai"]
## 同职业里先出「上手快」的那位：权重 2（其余 1）；后加入的干员排在同职业第二人之后：权重 0.5
## （10-22 拉普兰德 近卫、歌蕾蒂娅 特种，协调人定）
const PRIORITY := {"lumen": 2.0, "skadi": 2.0, "specter_unchained": 2.0, "lappland": 0.5, "gladiia": 0.5}
## 寻访凭证（存档 Cfg.roster_tickets["hunt"]）：每次探索结束发 RUN_TICKETS 张，通关再 +WIN_BONUS
const T_HUNT := "hunt"
const RUN_TICKETS := 3
const WIN_BONUS := 1
const COST_RANDOM := 1
const COST_PICK := 2
## 名册已满时，剩下的凭证每张折成多少生机细胞（docs/109 §12.7）
const CELLS_PER_TICKET := 5


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


## 待用的寻访凭证张数
static func tickets() -> int:
	return int(Cfg.roster_tickets.get(T_HUNT, 0))


static func pending_total() -> int:
	return tickets()


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


## 随机寻访：还有职业一个都没有时只从缺的职业里抽；同职业「上手快」权重 2、后加入的 0.5
static func choose_hunt() -> String:
	var locked := locked_ids()
	if locked.is_empty():
		return ""
	var owned := owned_classes()
	var fresh: Array = locked.filter(func(c): return not owned.has(class_of(c)))
	return _weighted(fresh if not fresh.is_empty() else locked)


## 未解锁干员按职业分组（定向寻访：先选职业，再在该职业里点名）
static func locked_in_class(cls: String) -> Array:
	return locked_ids().filter(func(c): return class_of(c) == cls)


## 花 cost 张凭证、解锁 cid
static func _redeem(cid: String, cost: int) -> void:
	Cfg.roster_tickets[T_HUNT] = tickets() - cost
	Cfg.roster_draws += 1
	Cfg.roster_unlocked.append(cid)
	if not Cfg.roster_fresh.has(cid):
		Cfg.roster_fresh.append(cid)
	Cfg.save()


# ---------------------------------------------------------------- 给表现层（screens/headhunt 演出，docs/124）的接口
# 只读：tickets()（凭证张数）/ COST_RANDOM / COST_PICK / is_unlocked(id) / locked_ids() / locked_classes() / locked_in_class(cls) / class_of(id)。
# 兑换由这里执行并返回结果，表现层只负责演出：
#   {"kind": "random" | "pick", "id": 干员 id, "new_class": 是否该职业的第一名}
#   凭证不够或名册已满：{"kind": …, "id": ""}

static func _result(kind: String, cid: String, cost: int) -> Dictionary:
	if tickets() < cost or cid == "" or is_unlocked(cid):
		return {"kind": kind, "id": ""}
	var r := {"kind": kind, "id": cid, "new_class": not owned_classes().has(class_of(cid))}
	_redeem(cid, cost)
	return r


## 随机寻访（1 张）
static func redeem_random() -> Dictionary:
	return _result("random", choose_hunt(), COST_RANDOM)


## 定向寻访（2 张）：直接解锁点名的干员
static func redeem_pick(cid: String) -> Dictionary:
	return _result("pick", cid, COST_PICK)


## 「刚解锁」高亮：解锁后还没在选人页 / 图鉴里看过的干员；表现层显示一次后调 mark_seen
static func fresh() -> Array:
	return Cfg.roster_fresh.duplicate()


static func mark_seen(cid: String) -> void:
	if Cfg.roster_fresh.has(cid):
		Cfg.roster_fresh.erase(cid)
		Cfg.save()


## 一次探索结束（state 进入 DEAD / WIN，game.gd _process 调一次）：发寻访凭证 3 张（通关 4 张）。
## 不发：演练、练习、图鉴演示、非 PLAY 模式、全部解锁 / 测试局（active() 为假）。名册已满时不再发（剩下的凭证由 spill_to_cells 折成生机细胞）
static func on_run_end(g, won: bool) -> void:
	if not active() or g.mode != g.Mode.PLAY or g.trial.active or g.demo_op != "" or Cfg.practice_active:
		return
	if locked_ids().is_empty():
		g.roster_new = {}
		spill_to_cells()
		return
	var n := RUN_TICKETS + (WIN_BONUS if won else 0)
	Cfg.roster_tickets[T_HUNT] = tickets() + n
	g.roster_new = {T_HUNT: n}
	Cfg.save()


## 名册已满：剩下的凭证每张折 CELLS_PER_TICKET 个生机细胞（记在本机设备号下，同 Meta.on_run_end）
static func spill_to_cells() -> int:
	var n := tickets()
	if n <= 0:
		return 0
	if Cfg.meta_dev == "":
		var rr := RandomNumberGenerator.new()
		rr.randomize()
		Cfg.meta_dev = "d%08x" % rr.randi()
	Cfg.meta_earned[Cfg.meta_dev] = int(Cfg.meta_earned.get(Cfg.meta_dev, 0)) + n * CELLS_PER_TICKET
	Cfg.roster_tickets[T_HUNT] = 0
	Cfg.save()
	return n * CELLS_PER_TICKET


## 旧存档（三种券）→ 单一寻访凭证：寻访凭证 1:1、招募券 1:1、人事调度函 1:2；旧「意向 / 保底」清空
static func migrate_tickets() -> void:
	var t: Dictionary = Cfg.roster_tickets
	if t.has("cls") or t.has("pick"):
		Cfg.roster_tickets = {T_HUNT: int(t.get("hunt", 0)) + int(t.get("cls", 0)) + 2 * int(t.get("pick", 0))}
	var sp: Dictionary = Cfg.roster_spare
	if not sp.is_empty():
		Cfg.roster_tickets[T_HUNT] = tickets() + int(sp.get("hunt", 0)) + int(sp.get("cls", 0)) + 2 * int(sp.get("pick", 0))
		Cfg.roster_spare = {}
	Cfg.roster_wish = ""
	Cfg.roster_pity = 0
