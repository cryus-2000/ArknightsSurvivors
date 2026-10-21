extends Node
## 构筑匹配（run/build_affinity.gd，docs/119 §4.3 / §4.4）的回归：
##   godot --headless --path game res://tests/build_affinity_test.tscn -- --regression --balance --seed=1 --op=angelina --squad=skadi,kaltsit
## 第 5 帧直接查干员档案与匹配结果：精零 / 精一 / 精二的可用性、匹配与不匹配、浮空不误算控制、永久技能不算循环、
## 招募 / 换人 / 藏品卡的说明行、强制招募保底（开关开 / 关）。全部通过打印 "BUILD AFFINITY failures=0"。

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


func names(arr: Array) -> Array:
	return arr.map(func(s): return str(s.name))


func need_of(arr: Array, nm: String) -> int:
	for s in arr:
		if str(s.name) == nm:
			return int(s.need)
	return -1


## 全员档案打印（人眼核对用，不计入检查）
func dump_profiles() -> void:
	for cid in game.Character.list_ids():
		var p: Dictionary = BA.profile(cid)
		print("PROFILE %s control=%s followup=%s skill=%s perm=%s" % [cid,
			p.control.map(func(s): return "%s@%d" % [s.name, s.need]), p.followup.map(func(s): return "%s@%d" % [s.name, s.need]),
			p.skill.map(func(s): return "%s@%d" % [s.name, s.need]), p.perm])


func test_chains() -> void:
	ok(BA.chain_of("97") == "control" and BA.chain_of("95") == "control" and BA.chain_of("96") == "control", "控制链 97 / 95 / 96")
	ok(BA.chain_of("130") == "followup" and BA.chain_of("171") == "followup" and BA.chain_of("234") == "followup", "追击链 130 / 171 / 234")
	ok(BA.chain_of("85") == "skill" and BA.chain_of("110") == "skill" and BA.chain_of("111") == "skill", "技能链 85 / 110 / 111")
	ok(BA.chain_of("1") == "" and BA.chain_of("263") == "", "其他藏品不在三条链里")


func test_profiles() -> void:
	var a: Dictionary = BA.profile("angelina")
	ok(a.elite_need[1] == 3 and a.elite_need[2] == 6, "安洁莉娜精一 / 精二在节点 3 / 6")
	ok(need_of(a.control, "秘杖·速充模式") == 0, "安洁莉娜 S1 眩晕：入队即有（%s）" % [names(a.control)])
	ok(need_of(a.control, "重力弹") == 3, "安洁莉娜普攻眩晕带 cond elite >= 1：精一后（%d）" % need_of(a.control, "重力弹"))
	ok(need_of(a.followup, "双重引力") == 4, "安洁莉娜双重引力（follow_up）在节点 4（%d）" % need_of(a.followup, "双重引力"))
	ok(not names(a.control).has("失重井"), "失重井只有浮空 / 失重，不算控制")
	var ir: Dictionary = BA.profile("irene")
	ok(ir.control.is_empty(), "艾丽妮只有抛起（launch），不算控制（%s）" % [names(ir.control)])
	ok(need_of(ir.followup, "追诉") == 6, "艾丽妮追诉（attack/pursue 带 cond elite >= 2）：精二后（%d）" % need_of(ir.followup, "追诉"))
	var k: Dictionary = BA.profile("kaltsit")
	ok(k.perm.size() == 1 and k.skill.size() == 2, "凯尔希 S2 永久不算循环：skill 2 条、perm 1 条")
	ok(need_of(k.followup, "Mon3tr") == 0, "Mon3tr（entity）入队即有")
	ok(need_of(k.control, "Mon3tr · 熔毁") == 0, "凯尔希 trait 的 stun 字段（手写段）算控制")
	var s: Dictionary = BA.profile("skadi")
	ok(s.control.is_empty() and need_of(s.followup, "反手斩") == 0 and s.skill.size() == 3, "斯卡蒂：无控制、反手斩追击入队即有、三个循环技能")
	ok(need_of(s.skill, s.skill[1].name) == 3 and need_of(s.skill, s.skill[2].name) == 6, "技能 2 / 3 的门槛 = 精一 / 精二节点")
	var w: Dictionary = BA.profile("wisadel")
	ok(need_of(w.control, "炮击") == 0 and need_of(w.followup, "殉爆") == 3, "维什戴尔：炮击灰烬眩晕入队即有、殉爆（detonation，cond elite >= 1）精一后")
	ok(not names(w.followup).has("余震"), "余震在 hit_sources 有标签但积木里没有打出它的地方：不算（未核实不显示）")
	var e: Dictionary = BA.profile("exusiai")
	ok(need_of(e.followup, "跳弹") == 5, "能天使跳弹在 progression/ricochet = 节点 5（%d）" % need_of(e.followup, "跳弹"))
	var sa: Dictionary = BA.profile("saria")
	ok(need_of(sa.control, "坚守") == 0 and need_of(sa.control, "精英二") == 6, "塞雷娅：没有来源名的 slow / stun 落款到天赋名 / 节点名")
	ok(BA.need_text("angelina", 0) == "" and BA.need_text("angelina", 3) == "精英一后" and BA.need_text("angelina", 6) == "精英二后", "条件文字：精一 / 精二")
	ok(BA.need_text("angelina", 4).begins_with("节点 4"), "条件文字：普通节点写节点号与名字（%s）" % BA.need_text("angelina", 4))
	ok(BA.need_text("angelina", 99) == "培养后", "不认识的成长键：培养后")
	ok(BA._cond_need("elite >= 2 && !skill_active:2", k) == 6 and BA._cond_need("node:twin_claw", k) == 1 and BA._cond_need("lamp < 30", k) == 0, "条件子句：elite / node:<id> / 其他")


func test_match() -> void:
	var m := BA.match_at("angelina", "97", 0)
	ok(m.ok and m.now == ["秘杖·速充模式"] and m.later.size() >= 1 and m.later[0].name == "重力弹", "精零安洁莉娜 × 凯旋号角：S1 现在可用，重力弹精一后（%s / %s）" % [m.now, m.later])
	m = BA.match_at("angelina", "95", 3)
	ok(m.now.has("重力弹") and m.now.has("秘杖·速充模式"), "精一安洁莉娜 × 悬丝傀儡：两条来源都可用")
	m = BA.match_at("angelina", "130", 0)
	ok(m.ok and m.now.is_empty() and m.later[0].need == 4, "精零安洁莉娜 × 衍生者终端：只有培养后（双重引力）")
	m = BA.match_at("angelina", "130", 6)
	ok(m.now.has("双重引力"), "精二安洁莉娜 × 衍生者终端：双重引力可用")
	ok(not BA.match_at("skadi", "97", 6).ok, "斯卡蒂 × 凯旋号角：没有控制来源，不匹配")
	ok(not BA.match_at("irene", "95", 6).ok, "艾丽妮 × 悬丝傀儡：浮空不算控制")
	m = BA.match_at("kaltsit", "85", 0)
	ok(m.now.size() == 1 and m.later.size() == 1 and m.later[0].need == 6, "精零凯尔希 × 古高卢银币：S1 现在，S3 精二后，S2 永久不计")
	ok(not BA.match_at("skadi", "1", 6).ok and BA.match_at("skadi", "1", 6).chain == "", "非链藏品：无匹配")
	var sk = game.squad.get_op("skadi")
	ok(sk != null and BA.match_op(sk, "130").now.has("反手斩"), "在队斯卡蒂 × 衍生者终端：反手斩")
	ok(af.relic_live("130") and af.relic_live("85") and af.relic_live("97"), "relic_live：130（反手斩 / Mon3tr）、85（技能）、97（安洁莉娜 S1）都能触发")
	ok(BA.inherit_prog(sk, "angelina") == mini(int(sk.prog), 6), "换入继承节点数 = min(旧, 新干员节点数)")


func test_lines_empty() -> void:
	ok(af.recruit_lines("wisadel") == "", "没持有链藏品时招募卡无说明行")
	var x: String = af.relic_lines("97")
	ok(x.begins_with("受益：安洁莉娜、凯尔希") and not x.contains("斯卡蒂") and x.contains("浮空 / 失重不算") and not x.contains("叠加"), "凯旋号角藏品卡（未持有相近）：两名受益只写名字、补充条件、无关系行（%s）" % x)
	ok(af.relic_lines("97", true) == x, "商品卡紧凑式：多人受益时与藏品卡相同")


func test_lines() -> void:
	# 持有 97 / 130
	var rl: String = af.recruit_lines("exusiai")
	ok(rl.begins_with("培养后生效：") and rl.contains("衍生者终端") and rl.contains("跳弹") and not rl.contains("凯旋号角"), "能天使招募卡：跳弹节点 5 培养后；无控制（%s）" % rl)
	rl = af.recruit_lines("wisadel")
	ok(rl.contains("入队即生效：凯旋号角（炮击）") and rl.contains("培养后生效：衍生者终端-超级改（殉爆，精英一后）"), "维什戴尔招募卡：两段分开（%s）" % rl)
	rl = af.recruit_lines("irene")
	ok(rl.begins_with("培养后生效：衍生者终端") and rl.contains("精英二后") and not rl.contains("凯旋号角"), "艾丽妮招募卡：追诉精二后、浮空不算凯旋号角（%s）" % rl)
	var x: String = af.relic_lines("95")
	ok(x.contains("与凯旋号角叠加") and not x.contains("取高"), "悬丝傀儡：与已持有的凯旋号角叠加（%s）" % x)
	ok(game.progression.gain_relic("95"), "获得悬丝傀儡")
	x = af.relic_lines("96")
	ok(x.contains("与凯旋号角叠加") and x.contains("与悬丝傀儡取高"), "童趣玩偶：与凯旋号角叠加、与悬丝傀儡取高（%s）" % x)
	x = af.relic_lines("171")
	ok(x.begins_with("受益：") and x.begins_with("受益：斯卡蒂、凯尔希") and x.contains("培养后受益：安洁莉娜（节点 4 后）") and x.contains("与衍生者终端-超级改叠加"), "炸裂之手：受益斯卡蒂、安洁莉娜培养后、与衍生者终端叠加（%s）" % x)
	ok(af.relic_lines("1") == "", "非链藏品不加行")
	ok(not af.relic_lines("234").contains("触发") and af.relic_lines("85").contains("永久技能只在充能那一次"), "补充条件：岁怒无（说明已写冷却）、古高卢银币写永久技能")
	# 换人卡：斯卡蒂（4 节点，精一）换人
	var sk = game.squad.get_op("skadi")
	var old_prog: int = sk.prog
	sk.prog = 4
	var sw: String = af.swap_lines(sk, "exusiai")
	ok(sw.begins_with("继承后：精英一，技能 冲锋模式 / 扫射模式") and not sw.contains("新增受益") and sw.contains("失去受益：衍生者终端"), "斯卡蒂换能天使：继承精英一两技能、跳弹要节点 5 → 失去衍生者终端（%s）" % sw)
	var sw2: String = af.swap_lines(sk, "wisadel")
	ok(not sw2.contains("失去受益") and sw2.contains("新增受益：凯旋号角、悬丝傀儡"), "斯卡蒂换维什戴尔：殉爆继承（精一）不失去、炮击新增控制链（%s）" % sw2)
	sk.prog = 0
	var sw3: String = af.swap_lines(sk, "angelina")
	ok(sw3.begins_with("继承后：精英零，技能 秘杖·速充模式") and sw3.contains("新增受益：凯旋号角、悬丝傀儡") and sw3.contains("失去受益：衍生者终端"), "精零斯卡蒂换安洁莉娜：新增控制链、失去追击链（%s）" % sw3)
	sk.prog = old_prog
	# 开关关：全部为空
	Bal._data["build"]["affinity_ui"] = 0
	ok(af.recruit_lines("wisadel") == "" and af.relic_lines("97") == "" and af.swap_lines(sk, "angelina") == "", "affinity_ui = 0：三种说明行都为空")
	Bal._data["build"]["affinity_ui"] = 1


## 只持有凯旋号角（控制链）：六名候选里只有维什戴尔入队即有控制（炮击），其余五名没有控制来源
func test_forced_recruit() -> void:
	var pool: Array = []
	for cid in ["exusiai", "eyjafjalla", "irene", "skadi", "skalter", "wisadel"]:
		pool.append({"kind": "recruit", "id": cid, "name": cid})
	var v := {}
	for c in pool:
		v[c.id] = af.candidate_interaction(str(c.id))
	print("INTERACTION ", v)
	ok(v["wisadel"] == 2 and v["skadi"] == 0 and v["irene"] == 0 and v["exusiai"] == 0, "候选互动：维什戴尔 2，无控制的 0（%s）" % [v])
	ok(af.candidate_interaction("hoshiguma") == 1, "星熊盾墙在节点 4：培养后才互动（1）")
	var hits := 0
	var moved := 0
	for seed in range(1, 41):
		game.rng.seed = seed
		var r: Array = af.forced_recruit_order(pool.duplicate(), 3)
		var top: Array = r.slice(0, 3).map(func(c): return str(c.id))
		if top.has("wisadel"):
			hits += 1
		game.rng.seed = seed
		var plain: Array = pool.duplicate()
		game.shuffle(plain)
		if plain.slice(0, 3).map(func(c): return str(c.id)) != top:
			moved += 1
		ok(r.size() == pool.size() and r.map(func(c): return str(c.id)).has("wisadel"), "保底后仍是同一批候选")
	ok(hits == 40, "40 个 seed 前 3 张都有维什戴尔（%d）" % hits)
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
	for cid in ["exusiai", "eyjafjalla", "irene", "skadi"]:
		nolink.append({"kind": "recruit", "id": cid, "name": cid})
	game.rng.seed = 7
	var r: Array = af.forced_recruit_order(nolink.duplicate(), 3)
	game.rng.seed = 7
	var plain: Array = nolink.duplicate()
	game.shuffle(plain)
	ok(r.map(func(c): return str(c.id)) == plain.map(func(c): return str(c.id)), "没有合格人选：照原规则")
