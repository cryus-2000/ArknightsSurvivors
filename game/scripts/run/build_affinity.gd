extends RefCounted
## 构筑匹配（只读，docs/119 §4.3 / §4.4 / §4.5 → docs/197）：给定干员与藏品，回答「这件藏品对这名干员生不生效」。
## 选卡界面（招募 / 换人 / 藏品 / 商品卡的说明行）、强制招募保底和首位商人预告都读同一个结果，不各自判断。
##
## 10-29 起与卡底「影响」标签（run/affects.gd）同一口径（docs/197 §4，「谁受益」只此一套）：
##   只认 7 条流派的藏品（relics.json lane ∈ melee / multi / summon / control / weak / shield / heal）；
##   干员受益 = 干员 JSON 的 lanes 含这条流派（docs/181，与 affects._by_lane、character.in_lane 相同）。
##   流派是干员固有的，入队即生效，不再有「培养后」一档。职业 / 通用 / 生存 / 经济件不显示匹配。
## 旧版按出手来源推算的三条链（控制 97/95/96、追击 130/171/234、技能 85/110/111）已并入：控制 → 控场引爆，追击 → 召唤驻场；
## 技能三件归通用，不再写说明行。

const Character = preload("res://scripts/characters/character.gd")
const Bal = preload("res://scripts/core/balance.gd")

const RelicDb = preload("res://scripts/core/relic_db.gd")
## 卡面上的触发条件补充（技术手册口吻，docs/76 §1.1）：藏品说明本身已写明触发时机（命中 / 开启 / 每 8 秒……），这里只补说明里
## 没有、判定上容易误会的一句；没有补充的不写（卡面空间有限，10-21 桌面 / 手机截图实测三行说明 + 三行受益就会截断）
const COND := {
	"97": "浮空 / 失重不算",
	"95": "浮空 / 失重不算",
	"96": "浮空 / 失重不算",
}
## 与已持有的相近藏品的关系（只列核实过的：95 / 96 取 dot_mult 较高者；其余各自结算、同时生效）
const STACK := {
	"95": {"96": "取高", "97": "叠加"}, "96": {"95": "取高", "97": "叠加"},
	"97": {"95": "叠加", "96": "叠加"},
	"130": {"171": "叠加", "234": "叠加"}, "171": {"130": "叠加", "234": "叠加"}, "234": {"130": "叠加", "171": "叠加"},
}

var g
static var _cache := {}   # cid -> profile（干员数据是静态的，跨局复用）


func _init(game) -> void:
	g = game


## 开关：balance.json build 段（缺省开；关掉时卡面不加说明行、强制招募与商人按原规则，随机数消耗与改前相同）
static func ui_on() -> bool:
	return Bal.vi("build/affinity_ui", 1) != 0


## 藏品所属流派（7 条之一）；职业 / 通用 / 生存 / 经济件返回 ""
static func chain_of(rid: String) -> String:
	var ln: String = str(_lane_of(rid))
	return ln if RelicDb.LANES7.has(ln) else ""


static var _db = null

static func _lane_of(rid: String) -> String:
	if _db == null:
		_db = RelicDb.new()
		_db.load_files()
	return str(_db.get_relic(rid).get("lane", ""))


## ---------------------------------------------------------------- 干员侧：成长档案

## {"lanes": [流派], "nodes": 节点数, "elite_need": [0, 精一节点数, 精二节点数], "node_names": [], "node_ids": []}
static func profile(cid: String) -> Dictionary:
	if _cache.has(cid):
		return _cache[cid]
	var d: Dictionary = Character.load_def(cid)
	var p := {"lanes": [], "nodes": 0, "elite_need": [0, 0, 0], "node_names": [], "node_ids": []}
	if d.is_empty():
		_cache[cid] = p
		return p
	p.lanes = (d.get("lanes", []) as Array).map(func(x): return str(x))
	var prog: Array = d.get("progression", [])
	p.nodes = prog.size()
	for k in prog.size():
		var n = prog[k]
		p.node_names.append(str(n.get("name", "")) if n is Dictionary else "")
		p.node_ids.append(str(n.get("id", "")) if n is Dictionary else "")
		if n is Dictionary and n.get("type", "") == "elite":
			p.elite_need[clampi(int(n.get("level", 0)), 0, 2)] = k + 1
	_cache[cid] = p
	return p


## ---------------------------------------------------------------- 匹配

## 一名干员对一件藏品：{"chain", "ok", "now": [流派名], "later": []}。流派是固有的，later 恒为空（保留字段给调用方）
static func match_at(cid: String, rid: String, _prog: int) -> Dictionary:
	var res := {"chain": chain_of(rid), "ok": false, "now": [], "later": []}
	if res.chain == "":
		return res
	if (profile(cid).lanes as Array).has(res.chain):
		res.now.append(Character.OpDefs.LANES.get(res.chain, res.chain))
	res.ok = not res.now.is_empty()
	return res


## 在队干员按实际成长判
static func match_op(op, rid: String) -> Dictionary:
	return match_at(str(op.id), rid, int(op.prog))


## 换入继承（squad.replace：继承节点数，上限是新干员的节点数）后的成长数
static func inherit_prog(old_op, new_cid: String) -> int:
	return mini(int(old_op.prog), profile(new_cid).nodes)


## 这件藏品当前有没有在队干员能让它生效（now）；后两个参数给预览用
func relic_live(rid: String) -> bool:
	for o in g.squad.ops:
		if not match_op(o, rid).now.is_empty():
			return true
	return false


## 持有的流派藏品
func owned_chain_relics() -> Array:
	return g.relics.filter(func(r): return chain_of(str(r)) != "")


## 候选干员与已持有藏品的互动：2 = 有已持有的本流派藏品，0 = 没有（强制招募保底按 2 > 0 选；流派入队即生效，没有「培养后」的 1 档）
func candidate_interaction(cid: String) -> int:
	for rid in owned_chain_relics():
		if match_at(cid, str(rid), 0).ok:
			return 2
	return 0


## 强制招募保底（docs/119 §4.3）：先按原规则洗牌，开关开且有合格人选时把一名「与已有藏品有实际互动」的候选放进前 want 张；
## 其余顺序不动。开关关 = 只洗牌（随机数消耗与改前相同）
func forced_recruit_order(recruit: Array, want: int) -> Array:
	g.shuffle(recruit)
	if Bal.vi("build/force_recruit_match", 1) == 0 or recruit.size() <= want or want <= 0:
		return recruit
	var best_i := -1
	var best_v := 0
	for i in recruit.size():
		var v := candidate_interaction(str(recruit[i].id))
		if v > best_v:
			best_v = v
			best_i = i
			if v == 2:
				break
	if best_i < 0 or best_i < want:
		return recruit   # 没有合格人选 / 已经在前 want 张里：照原规则
	var c = recruit[best_i]
	recruit.remove_at(best_i)
	recruit.insert(g.rng.randi() % want, c)
	return recruit


## ---------------------------------------------------------------- 卡面说明行（docs/76：短句、数字、不堆标签）

## 招募卡：入队后会受益的已持有流派藏品；没有互动返回 ""
func recruit_lines(cid: String) -> String:
	if not ui_on():
		return ""
	var now: Array = []
	for rid in owned_chain_relics():
		var m := match_at(cid, str(rid), 0)
		if not m.now.is_empty():
			now.append("%s（%s）" % [g.RL[rid].name, _join(m.now)])
	var out: Array = []
	if not now.is_empty():
		out.append("入队即生效：" + "、".join(now))
	var cb := combo_line(cid)
	if cb != "":
		out.append(cb)
	return "\n".join(out)


## 招募卡的联动数（10-23 用户：正文不再写「入队即生效 / 培养后生效」，标签行只放「联动 N」，悬停提示列 recruit_lines）：
## 能被这名干员激活的已持有藏品件数 + 同队专属联动人数
func recruit_link_count(cid: String) -> int:
	if not ui_on():
		return 0
	var n := 0
	for rid in owned_chain_relics():
		var m := match_at(cid, str(rid), 0)
		if m.ok:
			n += 1
	return n + combo_partners(cid, g.squad.ops).size()


## 干员专属联动（docs/123 §2.7「钩与锚」）：干员 JSON 顶层 combo {with, name, knob, desc}，只在两人同队时出现。
## 候选 cid 入队后会和在队的哪些干员形成联动（任一方的 combo.with 指向对方即算）；knob 关掉的不写
func combo_partners(cid: String, ops: Array) -> Array:
	var out: Array = []
	var d: Dictionary = Character.load_def(cid)
	for o in ops:
		if str(o.id) == cid:
			continue
		var od: Dictionary = o.def if o.get("def") is Dictionary else Character.load_def(str(o.id))
		var c: Dictionary = {}
		if d.get("combo", null) is Dictionary and str(d.combo.get("with", "")) == str(o.id):
			c = d.combo
		elif od.get("combo", null) is Dictionary and str(od.combo.get("with", "")) == cid:
			c = od.combo
		if c.is_empty() or (str(c.get("knob", "")) != "" and Bal.vi(str(c.knob), 1) == 0):
			continue
		out.append({"op": str(o.id), "name": str(od.get("name", o.id)), "combo": str(c.get("name", "联动"))})
	return out


func combo_line(cid: String) -> String:
	var ps := combo_partners(cid, g.squad.ops)
	if ps.is_empty():
		return ""
	return "联动：" + "、".join(ps.map(func(x): return "与%s「%s」" % [x.name, x.combo]))


## 换人卡（换下 old_op、换上 new_cid）：继承后的阶段与技能、新增 / 失去的藏品受益
func swap_lines(old_op, new_cid: String) -> String:
	if not ui_on():
		return ""
	var prog := inherit_prog(old_op, new_cid)
	var p := profile(new_cid)
	var nd: Dictionary = Character.load_def(new_cid)
	var elite := 0
	for lv in [1, 2]:
		if int(p.elite_need[lv]) > 0 and prog >= int(p.elite_need[lv]):
			elite = lv
	var skills: Array = []
	var sk: Array = nd.get("skills", [])
	for i in mini(sk.size(), elite + 1):
		skills.append(str(sk[i].get("name", "")))
	var out: Array = ["继承后：%s，技能 %s" % [["精英零", "精英一", "精英二"][elite], " / ".join(skills) if not skills.is_empty() else "无"]]
	var gain: Array = []
	var lose: Array = []
	for rid in owned_chain_relics():
		var was: bool = not match_op(old_op, str(rid)).now.is_empty()
		var will: bool = not match_at(new_cid, str(rid), prog).now.is_empty()
		var nm: String = g.RL[rid].name
		if will and not was:
			gain.append(nm)
		elif was and not will:
			lose.append(nm)
	if not gain.is_empty():
		out.append("新增受益：" + "、".join(gain))
	if not lose.is_empty():
		out.append("失去受益：" + "、".join(lose))
	var rest: Array = g.squad.ops.filter(func(o): return o != old_op)   # 换人后留下的队友
	var cb_gain := combo_partners(new_cid, rest)
	var cb_lose := combo_partners(str(old_op.id), rest)
	if not cb_gain.is_empty():
		out.append("新增联动：" + "、".join(cb_gain.map(func(x): return "与%s「%s」" % [x.name, x.combo])))
	if not cb_lose.is_empty():
		out.append("失去联动：" + "、".join(cb_lose.map(func(x): return "与%s「%s」" % [x.name, x.combo])))
	return "\n".join(out)


## 藏品卡 / 商品卡：触发条件与已持有相近藏品的关系（一行）；非流派藏品或没有补充时返回 ""。
## 受益人不在这里写：卡底「影响」标签（run/affects.gd）已按流派列出在队成员 / 「编队无 X 干员」，docs/197 §4 只留这一处
func relic_lines(rid: String, compact := false) -> String:
	if not ui_on() or chain_of(rid) == "":
		return ""
	if compact and g.relics.has(rid):
		return ""
	var tail: Array = []
	if COND.has(rid):
		tail.append(COND[rid])
	for other in STACK.get(rid, {}):
		if g.relics.has(other):
			tail.append("与%s%s" % [g.RL[other].name, STACK[rid][other]])
	return " · ".join(tail)


## 商人预告用：pool（relic_pool_ids 的顺序）里第一件「基础 / 稀有、流派件、编队有本流派干员」的藏品 id，没有返回 ""。
## 先找没持有的（新增一环），都没有再退到已持有件的升级（10-21 截图实测首商人货架上只剩凯旋号角 Lv.1 → 2 时也该预告）
func merchant_link_pick(pool: Array) -> String:
	var upgrade := ""
	for rid in pool:
		var r: Dictionary = g.RL[rid]
		if r.rarity not in ["基础", "稀有"] or chain_of(str(rid)) == "":
			continue
		if not relic_live(str(rid)):
			continue
		if not g.relics.has(str(rid)):
			return str(rid)
		if upgrade == "":
			upgrade = str(rid)
	return upgrade


static func _join(names: Array) -> String:
	return "、".join(names.slice(0, 2)) + ("等" if names.size() > 2 else "")
