extends RefCounted
## 构筑引导（docs/arch_review_1029 §1.4 / 风险 8）：升级三选一、藏品三选一、商店、事件、机器人用到的保底与加权规则只在这里。
## 第一步是门面：规则从 progression / build_affinity / endings / shop / relic_fx 原样搬来，调用次序与随机数消耗不变
## （同 seed TRACE 逐行相同）。各开关「关掉时随机数消耗不变」的承诺照旧。
##
## 规则清单：
##   培养保底 focus_on / order_deep · 落后补偿 catchup_* · 回复卡加权 card_weight · 强制招募 must_recruit / forced_recruit_order
##   第二张深度卡 second_deep · 招募 / 换人概率 recruit_chance · 藏品池加权 relic_pool_ids（稀有度、主流派、生存随时间、
##   犹疑、得偿所愿、护盾保底、已有减半、后期降权）· 核心延后 core_locked · 宝箱补偿 chest_open / chest_extra
##   主流派 main_lane（全游戏唯一口径，docs/184 §2.2 → docs/197 §4）与对口重排 lane_front · 首位商人保底 merchant_link_pick

const Bal = preload("res://scripts/core/balance.gd")
const RelicDb = preload("res://scripts/core/relic_db.gd")   # 藏品分类常量（docs/197）
const Squad = preload("res://scripts/characters/squad.gd")

const MELEE_CLS := ["近卫", "重装", "先锋", "特种"]
## 回复类升级卡（1.1 用户要求：回血偏弱，出现率调高）：[kind, id]——博士被动「自愈」「坚韧」、医疗无人机、填充卡「急救补给」。
## 吸血 / 击杀回复等在藏品池（relic_pool_ids），不在这里
const HEAL_CARDS := [["growth", "regen"], ["growth", "hp"], ["weapon", "drone"], ["filler", "heal"]]

var g


func _init(game) -> void:
	g = game


## ================================================================ 升级三选一

## 培养保底开关（balance levelup/focus_guard，缺省 1；关 = 旧发牌，随机数消耗不变）
static func focus_on() -> bool:
	return Bal.vi("levelup/focus_guard", 1) == 1

## 精英化落后补偿开关（balance levelup/catchup，缺省 1；0 = 旧发牌：均匀洗牌 + 保底只看最近培养对象，随机数消耗同改前）
static func catchup_on() -> bool:
	return Bal.vi("levelup/catchup", 1) == 1


## 落后补偿权重：比编队里培养进度最高者落后 gap 个精英阶段（每阶段 = 3 个节点，prog 0–6）→ ×catchup_mult^gap，封顶 catchup_cap
func catchup_weight(op_prog: int, top: int) -> float:
	var gap: float = maxf(0.0, float(top - op_prog)) / 3.0
	return minf(pow(Bal.v("levelup/catchup_mult", 1.8), gap), Bal.v("levelup/catchup_cap", 3.0))


## 深度卡按落后补偿加权排序（同 weighted_order 的取法，用 g.rng）：总卡数、每次给几张深度卡都不变，只改哪名干员排在前面
func catchup_order(deep: Array) -> Array:
	var top := 0
	for c in deep:
		var o = g.squad.get_op(str(c.get("op", "")))
		if o != null:
			top = maxi(top, o.prog)
	var keyed: Array = []
	for c in deep:
		var o = g.squad.get_op(str(c.get("op", "")))
		var w: float = catchup_weight(o.prog, top) if o != null else 1.0
		keyed.append([-log(g.rng.randf() + 0.0001) / w, c])
	keyed.sort_custom(func(a, b): return a[0] < b[0])
	return keyed.map(func(x): return x[1])


## 培养保底的对象（落后补偿开时）：最近培养对象比本次有成长卡的最落后队友领先 ≥ catchup_focus_gap 个节点 → 保底让给最落后的那位
## （同样落后时取 deep 里排在前面的）；否则仍是最近培养对象。不多取随机数
func catchup_focus(deep: Array, cur: String) -> String:
	var fo = g.squad.get_op(cur)
	if fo == null:
		return cur
	var low_id := ""
	var low := 99
	for c in deep:
		var o = g.squad.get_op(str(c.get("op", "")))
		if o != null and o.prog < low:
			low = o.prog
			low_id = o.id
	if low_id != "" and fo.prog - low >= Bal.vi("levelup/catchup_focus_gap", 5):
		return low_id
	return cur


## 深度卡的发牌次序：落后补偿加权（关 = 均匀洗牌），再按培养保底把最近培养的干员挪到 deep[0]
## （docs/119 §4.2 简化版：只重排，不多取随机数、不加选项；离队 / 养满自然失效）
func order_deep(deep: Array) -> Array:
	if catchup_on():
		deep = catchup_order(deep)   # 精英化落后补偿（docs/184）：落后越多的干员，成长卡越靠前；只重排，不加卡
	else:
		g.shuffle(deep)
	var P = g.progression
	if focus_on() and P.focus_op != "" and not deep.is_empty():
		if not g.squad.has(P.focus_op):
			P.focus_op = ""
		var target: String = catchup_focus(deep, P.focus_op) if catchup_on() else P.focus_op
		for k in deep.size():
			if str(deep[k].get("op", "")) == target:
				if k > 0:
					var fc: Dictionary = deep[k]
					deep.remove_at(k)
					deep.insert(0, fc)
				break
	return deep


## 编队 ≥ 2 人时约一半的升级给第二张深度卡（换一名干员）；1 人时不取随机数
func second_deep() -> bool:
	return g.squad.size() >= 2 and g.rng.randf() < Bal.v("levelup/second_deep_chance", 0.5)


static func is_heal_card(c: Dictionary) -> bool:
	return HEAL_CARDS.has([str(c.get("kind", "")), str(c.get("id", ""))])


## 选卡权重：回复类 ×levelup/heal_weight；主控生命低于 levelup/heal_low_hp（比例）时再 ×levelup/heal_low_hp_mult
func card_weight(c: Dictionary) -> float:
	if str(c.get("kind", "")) == "growth" and str(c.get("id", "")).begins_with("dash_"):
		return Bal.v("levelup/dash_weight", 0.7)   # 冲刺三张（机动类，docs/83）
	if not is_heal_card(c):
		return 1.0
	var w: float = Bal.v("levelup/heal_weight", 1.5)
	if g.hp < g.max_hp * Bal.v("levelup/heal_low_hp", 0.5):
		w *= Bal.v("levelup/heal_low_hp_mult", 1.5)
	return w


## 按 card_weight 加权的随机排序（权重越大越靠前；全为 1 时等同均匀洗牌），用对局随机数 g.rng
func weighted_order(cards: Array) -> Array:
	var keyed: Array = []
	for c in cards:
		keyed.append([-log(g.rng.randf() + 0.0001) / card_weight(c), c])
	keyed.sort_custom(func(a, b): return a[0] < b[0])
	return keyed.map(func(x): return x[1])


## ---- 招募（docs/23 §6）：Lv.5 起进池；保底：Lv.6 仍只有 1 人 / Lv.12 仍不满 3 人 → 本次必出招募
func must_recruit(recruit: Array) -> bool:
	return not recruit.is_empty() and ((g.level >= Bal.vi("levelup/force_recruit_level_1", 6) and g.squad.size() <= 1) or (g.level >= Bal.vi("levelup/force_recruit_level_3", 12) and g.squad.size() < Squad.REGULAR_MAX))


## 强制招募保底（docs/119 §4.3）：先按原规则洗牌，开关开且有合格人选时把一名「与已有藏品有实际互动」的候选放进前 want 张；
## 其余顺序不动。开关关 = 只洗牌（随机数消耗与改前相同）
func forced_recruit_order(recruit: Array, want: int) -> Array:
	g.shuffle(recruit)
	if Bal.vi("build/force_recruit_match", 1) == 0 or recruit.size() <= want or want <= 0:
		return recruit
	var best_i := -1
	var best_v := 0
	for i in recruit.size():
		var v: int = g.progression.affinity.candidate_interaction(str(recruit[i].id))
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


## 招募卡出现概率：编队未满约 45%；满员出「更换队友」卡，概率降为 swap_chance、7:00 后再降为 swap_chance_late（docs/162）
func recruit_chance(swap: bool) -> float:
	if not swap:
		return Bal.v("levelup/recruit_chance", 0.45)
	return Bal.v("levelup/swap_chance_late", 0.12) if g.t >= Bal.v("levelup/swap_late_t", 420.0) else Bal.v("levelup/swap_chance", 0.25)


## ================================================================ 藏品

## 核心延后（docs/191 §6）：第一只中期 Boss 被击败前（兜底 relic/core_gate_late 秒），核心 / 升华不进任何来源
func core_gated(r: Dictionary) -> bool:
	return r.rarity in ["升华", "核心"] and core_locked()


func core_locked() -> bool:
	return Bal.v("relic/core_gate", 0.0) > 0.0 and not g.mid_boss_down and g.t < Bal.v("relic/core_gate_late", 450.0)


## 可选藏品：已实装、未拥有、满足前置与职业门槛；按稀有度加权排序（基础 60 / 稀有 26 / 核心 12 / 升华 3，升华 7:00 后才出）
## 流派加权（docs/35 → docs/197 分类）：已拿过同一流派（7 条）或职业件 n 件 → ×1.3^n，封顶 ×2；通用 / 生存 / 经济不参与，
## 否则拿了生存卡就只剩生存卡。护盾反击 / 治疗转伤 / 生存三组随时间变多（3:00 前 ×0.7 → 9:00 后 ×1.0）
## 护盾保底：还没有护盾层数时，给层数的藏品 ×relic/shield_weight（缺省 4，docs/35 §护盾保底）
func relic_pool_ids(for_shop := false) -> Array:
	# docs/57：relic/new_pool = 0 时第二批实装的藏品不进池（同 seed 结果与之前一致，供云端 A/B）
	var new_ok: bool = Bal.vi("relic/new_pool", 1) != 0
	var cands: Array = g.rfx.db.implemented().filter(func(r): return (new_ok or not r.new_pool) and g.rfx.can_offer(r, for_shop) and g.progression.can_gain_relic(r.id))
	var lane_n := {}
	for rid in g.relics:
		var ln: String = str(g.RL.get(rid, {}).get("lane", ""))
		if RelicDb.WEIGHT_LANES.has(ln):
			lane_n[ln] = lane_n.get(ln, 0) + 1
	var h_w: float = lerpf(Bal.v("relic/h_early", 0.7), Bal.v("relic/h_late", 1.0), clampf((g.t - 180.0) / 360.0, 0.0, 1.0))
	var weighted: Array = []
	for r in cands:
		var w := 0.0
		match r.rarity:
			"基础": w = 60.0
			"稀有": w = 26.0
			"核心": w = 12.0
			"升华": w = 3.0 if g.t > 420.0 else 0.0
			"遭诅古物": w = 8.0 if for_shop else 0.0
		if w <= 0.0 or (g.meta_basic_pick and r.rarity != "基础"):
			continue
		var best_n: int = lane_n.get(r.lane, 0)
		if best_n > 0:
			w *= minf(pow(Bal.v("relic/lane_weight", 1.3), best_n), Bal.v("relic/lane_weight_cap", 2.0))
		if r.lane in ["shield", "heal", "survival"]:
			w *= h_w
		# 犹疑 (240)：稀有 / 核心 权重 +30%
		if g.rfx.rule("rare_weight") > 0 and r.rarity in ["稀有", "核心"]:
			w *= 1.3
		# 得偿所愿（翻节点卡，docs/154）：这一次三选一稀有 / 核心加权
		if not for_shop and g.endg.wish_rare and r.rarity in ["稀有", "核心"]:
			w *= maxf(float(g.endg.deck_cfg.get("wish_rare", 1.5)), Bal.v("relic/wish_rare", 0.0))   # relic/wish_rare：补偿用，0 = 按卡组配置
		# 护盾保底（10-21 用户：护盾常刷不到）：队长还没有护盾层数时，给层数的藏品（7 件）权重 ×relic/shield_weight；
		# 一拿到层数就恢复原权重。权重只改排序、不改随机数抽取次数
		if r.get("shield_layer", false) and g.shield_max <= 0:
			w *= Bal.v("relic/shield_weight", 4.0)
		# 已拥有的藏品升级：出现率减半
		if g.relics.has(r.id):
			w *= 0.5
		# 后期降权（relic_effects.json 的 late_weight）：一次性源石锭 / 灯火 / 回血、商品打折，6:00 后几乎没价值，少占三选一的位置
		if g.t > 360.0:
			w *= float(r.get("late_weight", 1.0))
		weighted.append([-log(g.rng.randf() + 0.0001) / w, r.id])
	weighted.sort_custom(func(a, b): return a[0] < b[0])
	return weighted.map(func(x): return x[1])


## 开宝箱前（docs/191 大时刻补偿）：relic/chest_rare 1 = 精英 / Boss / 精英小队宝箱按稀有 / 核心加权（同得偿所愿）
func chest_open(csrc: String) -> void:
	if csrc in ["elite", "boss", "squad"] and Bal.v("relic/chest_rare", 0.0) > 0.0:
		g.endg.wish_rare = true


## 宝箱多几个选项：Boss / 精英小队宝箱 +relic/big_extra，精英 / Boss / 小队宝箱再 +relic/chest_extra。只改张数，不多取随机数
func chest_extra(csrc: String) -> int:
	var extra := 0
	if csrc == "boss" or csrc == "squad":
		extra += Bal.vi("relic/big_extra", 0)
	if csrc in ["elite", "boss", "squad"]:
		extra += Bal.vi("relic/chest_extra", 0)
	return extra


## ---------- 主流派（docs/184 §2.2）：持有藏品里 7 条流派或职业件计数最多且 ≥ 3 件的（并列取最近拿到的，docs/197 §4）；
## 不足 3 件取队长的第一个流派（docs/181），队长没有流派时按职业近战 / 多弹 ----------
func main_lane() -> String:
	var cnt := {}
	var last := {}
	for i in g.relics.size():
		var ln: String = str(g.RL.get(str(g.relics[i]), {}).get("lane", ""))
		if RelicDb.WEIGHT_LANES.has(ln):
			cnt[ln] = int(cnt.get(ln, 0)) + 1
			last[ln] = i
	var best := ""
	for ln in cnt:
		if best == "" or cnt[ln] > cnt[best] or (cnt[ln] == cnt[best] and last[ln] > last[best]):
			best = ln
	if best != "" and int(cnt[best]) >= 3:
		return best
	var lead = g.ch
	if lead == null:
		return "melee"
	if not lead.lanes().is_empty():
		return str(lead.lanes()[0])
	return "melee" if MELEE_CLS.has(str(lead.cls)) else "multi"


## 对口重排（docs/184 §2.2 / §3）：藏品 id 列表里流派 = ln 的前两件挪到最前，其余照原顺序（只重排，不多取随机数）
func lane_front(ids: Array, ln: String) -> Array:
	var on_lane: Array = ids.filter(func(id): return str(g.RL[id].get("lane", "")) == ln).slice(0, 2)
	return on_lane + ids.filter(func(id): return not on_lane.has(id))


## 首位商人保底（docs/119 §4.5）：pool（relic_pool_ids 的顺序）里第一件「基础 / 稀有、流派件、编队有本流派干员」的藏品 id，没有返回 ""。
## 先找没持有的（新增一环），都没有再退到已持有件的升级（10-21 截图实测首商人货架上只剩凯旋号角 Lv.1 → 2 时也该预告）
func merchant_link_pick(pool: Array) -> String:
	var af = g.progression.affinity
	var upgrade := ""
	for rid in pool:
		var r: Dictionary = g.RL[rid]
		if r.rarity not in ["基础", "稀有"] or af.chain_of(str(rid)) == "":
			continue
		if not af.relic_live(str(rid)):
			continue
		if not g.relics.has(str(rid)):
			return str(rid)
		if upgrade == "":
			upgrade = str(rid)
	return upgrade
