extends RefCounted
## 看得见的成长节点（docs/249 §3，数值原型，开关 growth/visible_nodes，缺省 0 = 关，关时不做任何事、不读写随机数）。
## 1. 普通节点（成长线 节点 节点 精一 节点 节点 精二 里的 4 个普通节点）不再给「攻击 +6%」（character.NODE_ATK），改给本人形状流派的一项：
##      melee   范围 +range
##      multi   弹数：每次普攻 +shots 发额外弹（每发 = 普攻 × shot_mult，射向另一名敌人；复用可见成长 vis_growth 的弹体，
##              和 late_shape 的档位弹、藏品多射并在同一个累计器里，不另起一条发射）；普攻不是弹道的多弹干员改给范围
##      summon  体量：范围 +sum_range、追击与召唤物伤害 +sum_dmg
##      control 范围 +ctl_range
##    流派取法同 late_shape.lane（shape_lv/x_lane 例外表）。
## 2. 精二：本人攻击 +e2_atk、攻击速度 +e2_aspd，另给全队一条效果（vis_nodes/team，scope squad = 全局；离队时 squad.remove 撤销）。
## 与 late_shape（docs/248）的关系：late_shape 管「精英化 / 队伍等级门槛」的形状档，本块管「普通节点」与「精二」，两者来源名不同（lshape: / vnode: / ve2: / vteam:），
## 同开时各加各的；额外弹走同一个 op_summary 累计器，所以不会出两套弹体。

const Bal = preload("res://scripts/core/balance.gd")
const LateShape = preload("res://scripts/characters/blocks/late_shape.gd")
const RANGED_SHAPES := ["projectile", "shell", "bolt", "cannon", "point_aoe", "foxfire", "lantern"]


static func on(g) -> bool:
	return g != null and Bal.v("growth/visible_nodes", 0.0) > 0.0


static func kn(k: String, d: float) -> float:
	return Bal.v("vis_nodes/" + k, d)


## 本人的节点流派：melee / multi / summon / control / ""；multi 但普攻不是弹道的改按 control（给范围）
static func lane(o) -> String:
	var l: String = LateShape.lane(o)
	if l == "multi" and not ranged(o):
		return "range"
	return l


static func ranged(o) -> bool:
	if not (o.get("B") is Dictionary):
		return o.range_cls() == "远程" if o.has_method("range_cls") else false
	return str(o.B.get("attack", {}).get("shape", "")) in RANGED_SHAPES


## 普通节点推进时（character._advance，取代 NODE_ATK）：按流派挂一条属性来源
static func node_step(o) -> void:
	var g = o.g
	var src := "vnode:%s:%d" % [o.id, o.prog]
	var sc := "op:" + str(o.id)
	match lane(o):
		"melee":
			g.stats.add(&"op_range", "add", kn("range", 0.06), src, sc)
		"multi":
			pass   # 弹数在 op_shots_extra 里按 node_lv 算（vis_growth.on_release 读）
		"summon":
			g.stats.add(&"op_range", "add", kn("sum_range", 0.05), src, sc)
			g.stats.add(&"followup_dmg", "add", kn("sum_dmg", 0.05), src, sc)
		"control", "range":
			g.stats.add(&"op_range", "add", kn("ctl_range", 0.06), src, sc)
		_:
			g.stats.add(&"op_atk", "add", 0.06, src, sc)   # 无流派（不该出现）：保留旧的攻击 +6%


## 每次普攻的额外弹（multi 流派）：已拿普通节点数 × shots
static func extra_shots(o) -> float:
	if lane(o) != "multi":
		return 0.0
	return kn("shots", 0.2) * float(o.node_lv)


## 普通节点卡面末尾（取代「；攻击 +6%」）：写这一个节点带来的那一项与拿完后的累计
static func node_text(o) -> String:
	match lane(o):
		"melee":
			return "；攻击范围 +%d%%" % _pc(kn("range", 0.06))
		"multi":
			var n: float = kn("shots", 0.2) * float(o.node_lv + 1)
			return "；每 %s 次普攻多射 1 发（%d%% 普攻伤害，射向另一名敌人）" % [_n(1.0 / maxf(0.01, n)), _pc(kn("shot_mult", 0.5))]
		"summon":
			return "；攻击范围 +%d%%，追击与召唤物伤害 +%d%%" % [_pc(kn("sum_range", 0.05)), _pc(kn("sum_dmg", 0.05))]
		"control", "range":
			return "；攻击范围 +%d%%" % _pc(kn("ctl_range", 0.06))
	return "；攻击 +6%"


## 精二：本人基础属性一档 + 全队效果
static func elite2(o) -> void:
	var g = o.g
	var sc := "op:" + str(o.id)
	g.stats.add(&"op_atk", "add", kn("e2_atk", 0.12), "ve2:" + str(o.id), sc)
	g.stats.add(&"op_aspd", "add", kn("e2_aspd", 0.06), "ve2:" + str(o.id), sc)
	var t: Dictionary = team_def(o)
	var st: String = str(t.get("stat", "none"))
	if st != "none" and st != "" and g.stats.has_stat(StringName(st)):
		g.stats.add(StringName(st), str(t.get("op", "add")), float(t.get("value", 0.0)), "vteam:" + str(o.id), "squad")
	g.sync_stats()


## 开局（run_setup）：怪物强度补偿。用户 11-05 定：节点加成不收，按开关同步加强怪物（vis_nodes/enemy_hp、enemy_dmg，乘算；Boss 生命同样读 enemy_hp_mult）
static func apply_run(g) -> void:
	var h: float = kn("enemy_hp", 1.0)
	var d: float = kn("enemy_dmg", 1.0)
	if not is_equal_approx(h, 1.0):
		g.stats.add(&"enemy_hp", "mult", h, "vnodes_comp")
	if not is_equal_approx(d, 1.0):
		g.stats.add(&"enemy_dmg", "mult", d, "vnodes_comp")
	g.sync_stats()


## 离队（squad.remove）：撤销全队效果（本人作用域的来源留着也不会作用到别人）
static func on_leave(g, oid: String) -> void:
	g.stats.remove_source("vteam:" + oid)
	g.sync_stats()


static func team_def(o) -> Dictionary:
	var tb = Bal.sec("vis_nodes").get("team", {})
	if tb is Dictionary and tb.get(str(o.id), null) is Dictionary:
		return tb[str(o.id)]
	return {}


## 全队效果的一句话（横幅 / 卡面）
static func team_text(o) -> String:
	return str(team_def(o).get("txt", ""))


## 精二卡面追加：「精二：攻击 +12%，攻击速度 +6%；全队：……」
static func elite_text(o, level: int) -> String:
	if level < 2:
		return ""
	var s := "\n精英二：攻击 +%d%%，攻击速度 +%d%%" % [_pc(kn("e2_atk", 0.12)), _pc(kn("e2_aspd", 0.06))]
	if str(team_def(o).get("stat", "none")) != "none" and team_text(o) != "":
		s += "；" + team_text(o)   # 已有全队效果的（能天使、凯尔希）卡面本来就写了，不重复
	return s


static func _pc(v: float) -> int:
	return int(round(v * 100.0))


static func _n(v: float) -> String:
	var t := "%.1f" % v
	while t.ends_with("0"):
		t = t.substr(0, t.length() - 1)
	return t.trim_suffix(".")
