extends RefCounted
## 构筑匹配（只读，docs/119 §4.3 / §4.4 / §4.5）：给定干员与藏品，回答「这件藏品靠这名干员的哪个来源生效、现在能不能生效、
## 还差什么条件」。选卡界面（招募 / 换人 / 藏品 / 商品卡的说明行）、强制招募保底和首位商人预告都读同一个结果，不各自判断。
##
## 首版只认三条链（docs/119 §4.4），别的藏品一律返回「无匹配」，不显示：
##   控制伤害   #97 凯旋号角（延长眩晕 / 减速）、#95 悬丝傀儡 / #96 童趣玩偶（受控敌人每秒法术伤害，取高）
##   追击循环   #130 衍生者终端-超级改、#171 炸裂之手（追击命中回技力）、#234 岁怒（追击引爆）
##   技能循环   #85 古高卢银币（技能结束回技力）、#110 绿叶菜罐头 / #111 叙拉古人的愤怒（技能开启后的伤害窗口）
## 判定依据是干员 JSON 里实际的数据，不是名字或职业：
##   控制  = blocks 里写了 st: stun / st: slow 的状态，或手写段读的 stun / slow 字段（run/enemies.add_cc 的两个入口）；
##           浮空（airborne）/ 失重（weightless）/ 寒冷等不算（#95 的持续伤害只看 e.stun / e.slow，docs/119 §4.4）
##   追击  = hit_sources 里带 follow_up / aftershock / detonation / entity 标签的来源（combat.FOLLOWUP_TAGS），且 blocks 里有地方真的打出它
##   技能  = skills 里 sp > 0 且非 permanent 的技能（永久技能只在充能那一次触发 SkillStarted / SkillEnded，不算循环）
## 每个来源记一个「需要的成长节点数」need（0 = 入队即有；技能 i 按精英 i 所在节点；blocks/progression/<节点 id> 按该节点）：
## op.prog >= need 就是「现在可用」，否则是「培养后」。不认识的 progression 键（别的会话新加的分支段）按「培养后」处理，不写成确定匹配。

const Character = preload("res://scripts/characters/character.gd")
const Bal = preload("res://scripts/core/balance.gd")

const FOLLOWUP_TAGS := ["follow_up", "aftershock", "detonation", "entity"]
const CHAINS := {"control": ["97", "95", "96"], "followup": ["130", "171", "234"], "skill": ["85", "110", "111"]}
## 卡面上的触发条件补充（技术手册口吻，docs/76 §1.1）：藏品说明本身已写明触发时机（命中 / 开启 / 每 8 秒……），这里只补说明里
## 没有、判定上容易误会的一句；没有补充的不写（卡面空间有限，10-21 桌面 / 手机截图实测三行说明 + 三行受益就会截断）
const COND := {
	"97": "浮空 / 失重不算",
	"95": "浮空 / 失重不算",
	"96": "浮空 / 失重不算",
	"85": "永久技能只在充能那一次",
}
## 与已持有的相近藏品的关系（只列三条链内核实过的：95 / 96 取 dot_mult 较高者；其余各自结算、同时生效）
const STACK := {
	"95": {"96": "取高", "97": "叠加"}, "96": {"95": "取高", "97": "叠加"},
	"97": {"95": "叠加", "96": "叠加"},
	"130": {"171": "叠加", "234": "叠加"}, "171": {"130": "叠加", "234": "叠加"}, "234": {"130": "叠加", "171": "叠加"},
	"110": {"111": "叠加", "85": "叠加"}, "111": {"110": "叠加", "85": "叠加"}, "85": {"110": "叠加", "111": "叠加"},
}
const UNKNOWN_NODE := 99   # 不认识的成长键：按「培养后」处理

var g
static var _cache := {}   # cid -> profile（干员数据是静态的，跨局复用）


func _init(game) -> void:
	g = game


## 开关：balance.json build 段（缺省开；关掉时卡面不加说明行、强制招募与商人按原规则，随机数消耗与改前相同）
static func ui_on() -> bool:
	return Bal.vi("build/affinity_ui", 1) != 0


static func chain_of(rid: String) -> String:
	for k in CHAINS:
		if CHAINS[k].has(rid):
			return k
	return ""


## ---------------------------------------------------------------- 干员侧：来源档案

## {"control": [src], "followup": [src], "skill": [src], "perm": [技能名], "nodes": 节点数, "elite_need": [精一节点数, 精二节点数]}
## src = {"name": 来源名, "need": 需要的节点数}
static func profile(cid: String) -> Dictionary:
	if _cache.has(cid):
		return _cache[cid]
	var d: Dictionary = Character.load_def(cid)
	var p := {"control": [], "followup": [], "skill": [], "perm": [], "nodes": 0, "elite_need": [0, 0, 0], "node_names": [], "node_ids": []}
	if d.is_empty():
		_cache[cid] = p
		return p
	var prog: Array = d.get("progression", [])
	p.nodes = prog.size()
	for k in prog.size():
		var n = prog[k]
		p.node_names.append(str(n.get("name", "")) if n is Dictionary else "")
		p.node_ids.append(str(n.get("id", "")) if n is Dictionary else "")
		if n is Dictionary:
			if n.get("type", "") == "elite":
				var lv: int = clampi(int(n.get("level", 0)), 0, 2)
				p.elite_need[lv] = k + 1
	var hs: Dictionary = d.get("hit_sources", {})
	var sk: Array = d.get("skills", [])
	for i in sk.size():
		var s = sk[i]
		if not (s is Dictionary) or float(s.get("sp", 0.0)) <= 0.0:
			continue
		if s.get("permanent", false):
			p.perm.append(str(s.get("name", "")))
			continue
		p.skill.append({"name": str(s.get("name", "")), "need": p.elite_need[mini(i, 2)], "dur": float(s.get("dur", 0.0))})
	_walk(d.get("blocks", {}), "", 0, "", "", hs, prog, p, d)
	_cache[cid] = p
	return p


## 递归扫 blocks：key 是本层的键（判 skills[i] / progression/<id>），need 是到此为止需要的节点数，src 是最近的来源名，
## fb 是没有来源名时的落款（技能名 / 节点名 / 普攻），d 是整份干员定义
static func _walk(x, key: String, need: int, src: String, fb: String, hs: Dictionary, prog: Array, p: Dictionary, d: Dictionary) -> void:
	if x is Dictionary:
		var cond = x.get("cond", x.get("when", null))
		if cond is String:
			need = maxi(need, _cond_need(cond, p))
		if x.get("src", null) is String:
			src = str(x.src)
			var tags: Array = hs.get(src, {}).get("tags", [])
			if tags.any(func(t): return FOLLOWUP_TAGS.has(str(t))):
				_add(p.followup, src, need)
		var who: String = src if src != "" else (fb if fb != "" else key)
		var st: String = str(x.get("st", ""))
		if st == "stun" or st == "slow":
			_add(p.control, who, need)
		# 手写段（seg_*.gd）读的 stun / slow 字段：值为 0 / false 的不算
		for f in ["stun", "slow"]:
			if x.has(f) and not (x[f] is Dictionary) and not (x[f] is Array) and str(x[f]) not in ["0", "0.0", "false", ""]:
				_add(p.control, who, need)
		for k in x:
			var v = x[k]
			var nd := need
			var nfb := fb
			if key == "progression" and not (k is int):
				nd = maxi(nd, _node_need(str(k), prog, p))
				nfb = _node_name(str(k), prog)
			elif key == "" and str(k) == "attack":
				nfb = "普攻"
			elif key == "" and str(k) in ["talent", "trait"]:
				nfb = str(d.get("talent", {}).get("name", "天赋"))
			elif key == "" and str(k) == "summons":
				nfb = "召唤物"
			_walk(v, str(k), nd, src, nfb, hs, prog, p, d)
	elif x is Array:
		for i in x.size():
			var nd := need
			var nfb := fb
			if key == "skills":
				nd = maxi(nd, p.elite_need[mini(i, 2)])
				var sk: Array = d.get("skills", [])
				nfb = str(sk[i].get("name", "")) if i < sk.size() and sk[i] is Dictionary else fb
			_walk(x[i], key, nd, src, nfb, hs, prog, p, d)


static func _node_name(k: String, prog: Array) -> String:
	if k == "elite1":
		return "精英一"
	if k == "elite2":
		return "精英二"
	for n in prog:
		if n is Dictionary and str(n.get("id", "")) == k:
			return str(n.get("name", k))
	return k


static func _add(arr: Array, name: String, need: int) -> void:
	for s in arr:
		if s.name == name:
			s.need = mini(int(s.need), need)
			return
	arr.append({"name": name, "need": need})


## blocks/progression 的键 → 需要的节点数：elite1 / elite2 按精英节点；节点 id 按它在 progression 里的位置；不认识的按「培养后」
static func _node_need(k: String, prog: Array, p: Dictionary) -> int:
	if k == "elite1":
		return int(p.elite_need[1])
	if k == "elite2":
		return int(p.elite_need[2])
	for i in prog.size():
		if prog[i] is Dictionary and str(prog[i].get("id", "")) == k:
			return i + 1
	return UNKNOWN_NODE


## 积木条件里的门槛（ob_core 条件语法，可用 && 连接）：elite >= 1 / elite > 0 / elite == 2 → 精英节点；node:<id> → 该节点；
## 其他子句（skill_active / lamp / hp_pct……）不改门槛
static func _cond_need(c: String, p: Dictionary) -> int:
	var need := 0
	for raw in c.split("&&"):
		var s: String = raw.replace(" ", "")
		if s.begins_with("elite"):
			var m := -1
			if s.begins_with("elite>="):
				m = int(s.substr(7))
			elif s.begins_with("elite=="):
				m = int(s.substr(7))
			elif s.begins_with("elite>"):
				m = int(s.substr(6)) + 1
			if m >= 0:
				need = maxi(need, int(p.elite_need[clampi(m, 0, 2)]))
		elif s.begins_with("node:"):
			var nid := s.substr(5)
			var k := -1
			for i in p.node_ids.size():
				if str(p.node_ids[i]) == nid:
					k = i + 1
			need = maxi(need, k if k > 0 else UNKNOWN_NODE)
	return need


## 节点数 → 卡面上的条件文字（"" = 入队即有）
static func need_text(cid: String, need: int) -> String:
	if need <= 0:
		return ""
	var p := profile(cid)
	if need == int(p.elite_need[1]):
		return "精英一后"
	if need == int(p.elite_need[2]):
		return "精英二后"
	if need >= 1 and need <= p.node_names.size():
		return "节点 %d「%s」后" % [need, p.node_names[need - 1]]
	return "培养后"


## 短式条件（藏品卡 / 商品卡）："精一后" / "精二后" / "节点 4 后" / "培养后"
static func need_short(cid: String, need: int) -> String:
	if need <= 0:
		return ""
	var p := profile(cid)
	if need == int(p.elite_need[1]):
		return "精一后"
	if need == int(p.elite_need[2]):
		return "精二后"
	if need >= 1 and need <= p.nodes:
		return "节点 %d 后" % need
	return "培养后"


## ---------------------------------------------------------------- 匹配

## 一名干员（成长 prog 个节点时）对一件藏品：{"chain", "ok", "now": [来源名], "later": [{"name", "need"}]}
## 技能链：来源 = 非永久技能；控制链 / 追击链：来源 = 对应标签 / 状态的伤害来源
static func match_at(cid: String, rid: String, prog: int) -> Dictionary:
	var res := {"chain": chain_of(rid), "ok": false, "now": [], "later": []}
	if res.chain == "":
		return res
	var p := profile(cid)
	for s in p[res.chain]:
		if prog >= int(s.need):
			res.now.append(str(s.name))
		else:
			res.later.append({"name": str(s.name), "need": int(s.need)})
	res.later.sort_custom(func(a, b): return a.need < b.need)
	res.ok = not res.now.is_empty() or not res.later.is_empty()
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


## 持有的三条链藏品
func owned_chain_relics() -> Array:
	return g.relics.filter(func(r): return chain_of(str(r)) != "")


## 候选干员与已持有藏品的实际互动：2 = 入队即有互动，1 = 培养后才有，0 = 没有（强制招募保底按 2 > 1 > 0 选）
func candidate_interaction(cid: String) -> int:
	var best := 0
	for rid in owned_chain_relics():
		var m := match_at(cid, str(rid), 0)
		if not m.now.is_empty():
			return 2
		if not m.later.is_empty():
			best = 1
	return best


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

## 招募卡：和已持有藏品的互动，分「入队即生效」与「培养后生效」；没有互动返回 ""
func recruit_lines(cid: String) -> String:
	if not ui_on():
		return ""
	var now: Array = []
	var later: Array = []
	for rid in owned_chain_relics():
		var m := match_at(cid, str(rid), 0)
		var nm: String = g.RL[rid].name
		if not m.now.is_empty():
			now.append("%s（%s）" % [nm, _join(m.now)])
		elif not m.later.is_empty():
			later.append("%s（%s，%s）" % [nm, m.later[0].name, need_text(cid, int(m.later[0].need))])
	var out: Array = []
	if not now.is_empty():
		out.append("入队即生效：" + "、".join(now))
	if not later.is_empty():
		out.append("培养后生效：" + "、".join(later))
	return "\n".join(out)


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
	return "\n".join(out)


## 藏品卡 / 商品卡：当前受益干员与来源、培养后才受益的、触发条件、与已持有相近藏品的关系；非三条链藏品返回 ""
## compact = 商品卡（160 宽）：只写名字不写来源；已持有的升级件（说明里多一行「可叠加，本级 x%」）不加行，受益人看卡底「影响」标签。
## 藏品卡只在受益人唯一时写来源（10-21 桌面截图实测两人带来源就截断）
func relic_lines(rid: String, compact := false) -> String:
	if not ui_on() or chain_of(rid) == "":
		return ""
	if compact and g.relics.has(rid):
		return ""
	var now: Array = []
	var later: Array = []
	var ms := {}
	for o in g.squad.ops:
		var m := match_op(o, rid)
		if not m.now.is_empty():
			now.append(o)
			ms[o.id] = m
		elif not m.later.is_empty():
			later.append("%s（%s）" % [o.display_name(), need_short(str(o.id), int(m.later[0].need))])
	var with_src: bool = now.size() == 1 and not compact
	now = now.map(func(o): return "%s（%s）" % [o.display_name(), ms[o.id].now[0]] if with_src else o.display_name())
	var out: Array = []
	if not now.is_empty():
		out.append("受益：" + "、".join(now))
	if not later.is_empty():
		out.append("培养后受益：" + "、".join(later))
	if now.is_empty() and later.is_empty():
		out.append("编队里暂无能触发它的干员")
	# 补充条件与相近藏品关系并成一行（桌面藏品卡三行说明 + 两行受益后只剩一行）
	var tail: Array = []
	if COND.has(rid):
		tail.append(COND[rid])
	for other in STACK.get(rid, {}):
		if g.relics.has(other):
			tail.append("与%s%s" % [g.RL[other].name, STACK[rid][other]])
	if not tail.is_empty():
		out.append(" · ".join(tail))
	return "\n".join(out)


## 商人预告用：pool（relic_pool_ids 的顺序）里第一件「基础 / 稀有、三条链、当前有在队干员能触发」的藏品 id，没有返回 ""。
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
