extends RefCounted
## 蚀刻章（成就，10-25 Codex 交付「深蓝之下」九枚，art/archive/incoming_1028/achievement_ui_1024/CLAUDE_HANDOFF_1025.md）：章表在 data/medals.json。
## 纯荣誉：不给任何奖励，只读记录、不碰局内模拟（不读 / 不写 g.rng，局内钩子只数编队里的精英二人数）。
## 存档：Cfg.medals = {key: 获得时刻 Unix 秒}（获得后永久保留：认知重置、记录变少都不收回）；Cfg.medal_best = {key: 历史最好进度}（协同晋升的同时精英二人数）。
## 判定来源：结局 = 真实的 endings_cleared；藏品 = 真实的 seen_relics 里的有效藏品 ID（去重）；认知 = Cfg.meta_shape；协同晋升 = 局内钩子 note_elite。
## 「真实」= 全部解锁（调试 / 对内包）时用存档里的那份（Cfg._real_progress），不把演示用的全开算进去。
## sync() 在读档后（补录旧存档）、每次 Cfg.save() 前、打开蚀刻章页时调：按当前记录把新达成的章补上。

const PATH := "res://data/medals.json"
static var _data := {}
static var _relic_ids := {}
## 待提示队列（10-30）：新获得章 {key, t}，由 autoload MedalToast（scripts/medal_toast.gd）取出弹横幅；无界面（headless / 批跑）不入队
static var pending: Array = []
static var announce := DisplayServer.get_name() != "headless"   # 测试可以改成 true 来验队列
const PENDING_MAX := 64


static func data() -> Dictionary:
	if _data.is_empty():
		var j = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = j if j is Dictionary else {"medals": []}
	return _data


## 章表（data/medals.json 的顺序：套组章在前）
static func defs() -> Array:
	return data().get("medals", [])


static func def(key: String) -> Dictionary:
	for m in defs():
		if m.key == key:
			return m
	return {}


static func def_by_id(id: int) -> Dictionary:
	for m in defs():
		if int(m.id) == id:
			return m
	return {}


static func has(key: String) -> bool:
	return Cfg.medals.has(key)


static func earned_count() -> int:
	var n := 0
	for m in defs():
		if Cfg.medals.has(m.key):
			n += 1
	return n


# ---------------------------------------------------------------- 记录
static func _real(name: String) -> Array:
	var v = Cfg._real_progress.get(name, Cfg.get(name)) if Cfg.unlock_all else Cfg.get(name)
	return v if v is Array else []


## 有效藏品 ID（data/relics.json 里已实装的）
static func valid_relics() -> Dictionary:
	if _relic_ids.is_empty():
		var db = load("res://scripts/core/relic_db.gd").new()
		db.load_files()
		for r in db.implemented():
			_relic_ids[str(r.id)] = true
	return _relic_ids


## 累计获得的不同藏品数（按有效 ID 去重；重复获取 / 升级不重复计数）
static func relic_count(seen: Array) -> int:
	var ok := valid_relics()
	var got := {}
	for id in seen:
		var s := str(id)
		if ok.has(s):
			got[s] = true
	return got.size()


static func cog_total() -> int:
	return load("res://scripts/core/meta.gd").nodes().size()


static func cog_lit(shape: Dictionary) -> int:
	var nodes: Dictionary = load("res://scripts/core/meta.gd").nodes()
	var n := 0
	for k in shape:
		if shape[k] and nodes.has(k):
			n += 1
	return n


## 进度 [当前, 目标]（已获得的章当前值至少等于目标：记录后来变少也显示满）
static func progress(m: Dictionary) -> Array:
	var cur := 0
	var mx := 1
	match str(m.rule):
		"ending":
			cur = 1 if _real("endings_cleared").has(str(m.arg)) else 0
		"relics":
			mx = int(m.max)
			cur = relic_count(_real("seen_relics"))
		"elite":
			mx = int(m.max)
			cur = int(Cfg.medal_best.get(m.key, 0))
		"cog_first":
			cur = 1 if cog_lit(Cfg.meta_shape) > 0 else 0
		"cog_all":
			mx = maxi(1, cog_total())
			cur = cog_lit(Cfg.meta_shape)
		"set":
			mx = defs().size() - 1
			for o in defs():
				if o.key != m.key and Cfg.medals.has(o.key):
					cur += 1
	if Cfg.medals.has(m.key):
		cur = maxi(cur, mx)
	return [mini(cur, mx), mx]


## 按当前记录补上新达成的章；返回这次新获得的 key（套组章最后判，同一次里集齐也算）
static func sync(now := -1) -> Array:
	var t: int = now if now >= 0 else int(Time.get_unix_time_from_system())
	var got: Array = []
	for pass_set in [false, true]:
		for m in defs():
			if (str(m.rule) == "set") != pass_set or Cfg.medals.has(m.key):
				continue
			if str(m.rule) == "relics" and _real("seen_relics").size() < int(m.max):
				continue   # 条数都不够：不必加载藏品库（读档补录在启动时跑，省网页启动时间）
			var p := progress(m)
			if int(p[0]) >= int(p[1]):
				Cfg.medals[m.key] = t
				got.append(m.key)
				if announce and pending.size() < PENDING_MAX:
					pending.append({"key": m.key, "t": t})
	return got


# ---------------------------------------------------------------- 局内钩子（只读编队状态）
## 计入的局：同 Roster.on_run_end（演练、练习、图鉴演示、非 PLAY 模式不算）
static func counts(g) -> bool:
	return g.mode == g.Mode.PLAY and not g.trial.active and g.demo_op == "" and not Cfg.practice_active


## 有干员精英化时（character.gd 精英化节点）：数编队里同时精英二的人数，记历史最好（只在内存，局终 / 下次存档写盘）
static func note_elite(g) -> void:
	if g == null or g.get("squad") == null or not counts(g):
		return
	var n := 0
	for o in g.squad.ops:
		if int(o.elite) >= 2:
			n += 1
	record_best("elite_three", n)
	sync()   # 协同晋升章当场判定、当场入提示队列（局内小横幅；落盘仍在局终 / 下次存档）


static func record_best(key: String, n: int) -> void:
	if n > int(Cfg.medal_best.get(key, 0)):
		Cfg.medal_best[key] = n


## 一局结束（run_end.settle）：补判并写盘（协同晋升的最好进度也要落盘，没有新章也存）
static func on_run_end(g) -> void:
	if not counts(g):
		return
	sync()
	Cfg.save()
