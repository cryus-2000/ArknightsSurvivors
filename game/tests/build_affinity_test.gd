extends Node
## 构筑匹配（run/build_affinity.gd，docs/119 §4.3 / §4.4 → docs/197 流派口径）的回归：
##   godot --headless --path game res://tests/build_affinity_test.tscn -- --regression --balance --seed=1 --op=angelina --squad=skadi,kaltsit
## 第 5 帧直接查：藏品流派、干员流派匹配与不匹配、招募 / 换人 / 藏品卡的说明行、强制招募保底（开关开 / 关）。全部通过打印 "BUILD AFFINITY failures=0"。

const Bal = preload("res://scripts/core/balance.gd")
const BA = preload("res://scripts/run/build_affinity.gd")

var game: Node
var af
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
	af = game.progression.affinity
	if not Bal._data.has("build"):
		Bal._data["build"] = {}
	Bal._data["build"]["affinity_ui"] = 1
	Bal._data["build"]["force_recruit_match"] = 1
	dump_profiles()
	test_chains()
	test_profiles()
	test_match()
	test_lines_empty()
	ok(game.progression.gain_relic("97"), "获得凯旋号角")
	test_forced_recruit()
	ok(game.progression.gain_relic("130"), "获得衍生者终端")
	test_lines()
	print("%d checks, %d failed" % [n, fails])
	print("BUILD AFFINITY failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		fails += 1
		printerr("FAIL: ", what)


## 全员档案打印（人眼核对用，不计入检查）
func dump_profiles() -> void:
	for cid in game.Character.list_ids():
		var p: Dictionary = BA.profile(cid)
		print("PROFILE %s lanes=%s nodes=%d elite=%s" % [cid, p.lanes, p.nodes, p.elite_need])


func test_chains() -> void:
	ok(BA.chain_of("97") == "control" and BA.chain_of("95") == "control" and BA.chain_of("96") == "control", "控场引爆 97 / 95 / 96")
	ok(BA.chain_of("130") == "summon" and BA.chain_of("171") == "summon" and BA.chain_of("234") == "summon", "召唤驻场 130 / 171 / 234")
	ok(BA.chain_of("85") == "" and BA.chain_of("110") == "" and BA.chain_of("111") == "", "旧技能链三件归通用（docs/197）")
	ok(BA.chain_of("1") == "" and BA.chain_of("79") == "", "通用件不匹配")
	ok(BA.chain_of("263") == "heal" and BA.chain_of("56") == "melee", "治疗转伤 / 近战扩域件")


func test_profiles() -> void:
	var a: Dictionary = BA.profile("angelina")
	ok(a.elite_need[1] == 3 and a.elite_need[2] == 6, "安洁莉娜精一 / 精二在节点 3 / 6")
	ok(a.lanes == ["control"], "安洁莉娜流派：控场引爆（%s）" % [a.lanes])
	ok(BA.profile("kaltsit").lanes == ["heal", "summon"], "凯尔希流派：治疗转伤、召唤驻场")


func test_match() -> void:
	var m := BA.match_at("angelina", "97", 0)
	ok(m.ok and m.now == ["控场引爆"] and m.later.is_empty(), "安洁莉娜 × 凯旋号角：控场引爆，入队即生效（%s）" % [m.now])
	ok(not BA.match_at("skadi", "97", 6).ok, "斯卡蒂 × 凯旋号角：不在控场引爆，不匹配")
	ok(BA.match_at("irene", "95", 0).ok, "艾丽妮 × 悬丝傀儡：艾丽妮归控场引爆（docs/181）")
	ok(BA.match_at("kaltsit", "130", 0).ok and not BA.match_at("angelina", "130", 6).ok, "衍生者终端：凯尔希匹配，安洁莉娜不匹配")
	ok(not BA.match_at("kaltsit", "85", 0).ok, "古高卢银币（通用）：无匹配")
	ok(not BA.match_at("skadi", "1", 6).ok and BA.match_at("skadi", "1", 6).chain == "", "非流派藏品：无匹配")
	var sk = game.squad.get_op("skadi")
	ok(sk != null and BA.match_op(sk, "56").ok, "在队斯卡蒂 × 老近卫军之锋：近战扩域")
	ok(af.relic_live("130") and af.relic_live("97") and not af.relic_live("85") and not af.relic_live("58"), "relic_live：130（凯尔希）、97（安洁莉娜）能触发；85 通用、58 多弹无人")
	ok(BA.inherit_prog(sk, "angelina") == mini(int(sk.prog), 6), "换入继承节点数 = min(旧, 新干员节点数)")


func test_lines_empty() -> void:
	ok(af.recruit_lines("wisadel") == "", "没持有流派藏品时招募卡无说明行")
	var x: String = af.relic_lines("97")
	ok(x == "浮空 / 失重不算", "凯旋号角藏品卡：只写补充条件，受益人看卡底标签（%s）" % x)
	ok(af.relic_lines("97", true) == x, "商品卡紧凑式：与藏品卡相同")
	ok(af.relic_lines("56") == "", "老近卫军之锋：没有补充条件、没有相近藏品，不加行")


func test_lines() -> void:
	# 持有 97 / 130
	ok(af.recruit_lines("exusiai") == "", "能天使招募卡：多弹火力，与凯旋号角 / 衍生者终端都无关")
	var rl: String = af.recruit_lines("wisadel")
	ok(rl == "入队即生效：衍生者终端-超级改（召唤驻场）", "维什戴尔招募卡：召唤驻场（%s）" % rl)
	rl = af.recruit_lines("irene")
	ok(rl == "入队即生效：凯旋号角（控场引爆）", "艾丽妮招募卡：控场引爆（%s）" % rl)
	ok(af.recruit_link_count("irene") == 1 and af.recruit_link_count("exusiai") == 0, "招募卡联动数")
	var x: String = af.relic_lines("95")
	ok(x.contains("与凯旋号角叠加") and not x.contains("取高"), "悬丝傀儡：与已持有的凯旋号角叠加（%s）" % x)
	ok(game.progression.gain_relic("95"), "获得悬丝傀儡")
	x = af.relic_lines("96")
	ok(x.contains("与凯旋号角叠加") and x.contains("与悬丝傀儡取高"), "童趣玩偶：与凯旋号角叠加、与悬丝傀儡取高（%s）" % x)
	x = af.relic_lines("171")
	ok(x == "与衍生者终端-超级改叠加", "炸裂之手：与衍生者终端叠加（%s）" % x)
	ok(af.relic_lines("1") == "" and af.relic_lines("85") == "", "非流派藏品不加行")
	# 换人卡：斯卡蒂（4 节点，精一）换人
	var sk = game.squad.get_op("skadi")
	var old_prog: int = sk.prog
	sk.prog = 4
	var sw: String = af.swap_lines(sk, "exusiai")
	ok(sw.begins_with("继承后：精英一，技能 冲锋模式 / 扫射模式") and not sw.contains("受益"), "斯卡蒂换能天使：继承精英一两技能，流派藏品无得失（%s）" % sw)
	var sw2: String = af.swap_lines(sk, "wisadel")
	ok(not sw2.contains("失去受益") and sw2.contains("新增受益：衍生者终端-超级改"), "斯卡蒂换维什戴尔：新增召唤驻场（%s）" % sw2)
	sk.prog = 0
	var sw3: String = af.swap_lines(sk, "angelina")
	ok(sw3.begins_with("继承后：精英零，技能 秘杖·速充模式") and sw3.contains("新增受益：凯旋号角、悬丝傀儡") and not sw3.contains("失去受益"), "精零斯卡蒂换安洁莉娜：新增控场引爆（%s）" % sw3)
	sk.prog = old_prog
	# 开关关：全部为空
	Bal._data["build"]["affinity_ui"] = 0
	ok(af.recruit_lines("wisadel") == "" and af.relic_lines("97") == "" and af.swap_lines(sk, "angelina") == "", "affinity_ui = 0：三种说明行都为空")
	Bal._data["build"]["affinity_ui"] = 1


## 只持有凯旋号角（控场引爆）：六名候选里只有艾丽妮归控场引爆（docs/181），其余五名不是
func test_forced_recruit() -> void:
	var pool: Array = []
	for cid in ["exusiai", "eyjafjalla", "irene", "skadi", "skalter", "wisadel"]:
		pool.append({"kind": "recruit", "id": cid, "name": cid})
	var v := {}
	for c in pool:
		v[c.id] = af.candidate_interaction(str(c.id))
	print("INTERACTION ", v)
	ok(v["irene"] == 2 and v["skadi"] == 0 and v["wisadel"] == 0 and v["exusiai"] == 0, "候选互动：艾丽妮 2，其余 0（%s）" % [v])
	ok(af.candidate_interaction("hoshiguma") == 0, "星熊（近战扩域 / 护盾反击）：与凯旋号角无互动")
	var hits := 0
	var moved := 0
	for seed in range(1, 41):
		game.rng.seed = seed
		var r: Array = af.forced_recruit_order(pool.duplicate(), 3)
		var top: Array = r.slice(0, 3).map(func(c): return str(c.id))
		if top.has("irene"):
			hits += 1
		game.rng.seed = seed
		var plain: Array = pool.duplicate()
		game.shuffle(plain)
		if plain.slice(0, 3).map(func(c): return str(c.id)) != top:
			moved += 1
		ok(r.size() == pool.size() and r.map(func(c): return str(c.id)).has("irene"), "保底后仍是同一批候选")
	ok(hits == 40, "40 个 seed 前 3 张都有艾丽妮（%d）" % hits)
	ok(moved > 0 and moved < 40, "只在洗牌没把她放进前 3 时才动（动了 %d 次）" % moved)
	# 开关关：与纯洗牌逐位相同
	Bal._data["build"]["force_recruit_match"] = 0
	var same := true
	for seed in range(1, 21):
		game.rng.seed = seed
		var r: Array = af.forced_recruit_order(pool.duplicate(), 3)
		game.rng.seed = seed
		var plain: Array = pool.duplicate()
		game.shuffle(plain)
		if r.map(func(c): return str(c.id)) != plain.map(func(c): return str(c.id)):
			same = false
	ok(same, "force_recruit_match = 0：与纯洗牌逐位相同")
	Bal._data["build"]["force_recruit_match"] = 1
	# 没有合格人选：顺序不动
	var nolink: Array = []
	for cid in ["exusiai", "eyjafjalla", "wisadel", "skadi"]:
		nolink.append({"kind": "recruit", "id": cid, "name": cid})
	game.rng.seed = 7
	var r: Array = af.forced_recruit_order(nolink.duplicate(), 3)
	game.rng.seed = 7
	var plain: Array = nolink.duplicate()
	game.shuffle(plain)
	ok(r.map(func(c): return str(c.id)) == plain.map(func(c): return str(c.id)), "没有合格人选：照原规则")
