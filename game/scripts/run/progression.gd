extends RefCounted
## 升级与藏品发放（逻辑）：升级卡池（招募 / 干员深度 / 博士与全队被动 / 填充，docs/23 §6）、藏品候选池、选中后的结算与藏品获得。
## 选卡界面（卡片绘制、动画）在 screens/ 下。2026-09-26 从 game.gd 拆出。

const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
const Character = preload("res://scripts/characters/character.gd")
const Squad = preload("res://scripts/characters/squad.gd")
const Bal = preload("res://scripts/core/balance.gd")   # data/balance.json 数值旋钮（docs/27）
const Roster = preload("res://scripts/core/roster.gd")   # 干员解锁（docs/109 §12）：招募卡只出已解锁的干员；测试局全部解锁

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
const BuildAffinity = preload("res://scripts/run/build_affinity.gd")   # 构筑匹配（只读，docs/119 §4.3–4.5）：卡面说明行 / 招募保底 / 商人预告共用
var g: Game
var affinity: BuildAffinity
var tab_hinted := false
var heal_offer := 0   # 平衡输出：回复类卡被提供 / 被选中的张数（telemetry）
var heal_pick := 0
var low_levelups := 0        # 主控生命低于门槛时弹出的升级次数
var heal_offer_low := 0      # 其中提供的回复类卡张数
var focus_op := ""           # docs/119 §4.2 培养保底（简化版）：最近一次选中培养卡的干员 id；它还有合法成长卡时固定占第一个深度卡槽
var branch_ctx: Dictionary = {}   # 培养路线二选一（docs/119 §4.1）：{opts, kind, title, sub, sel, card, source: level / swap / free}
var branch_queue: Array = []      # 赠送推进（典训 / 博士银印）碰到分支节点、等玩家选路线的干员 id（按触发顺序排队）


## 培养保底开关（balance levelup/focus_guard，缺省 1；关 = 旧发牌，随机数消耗不变）
static func focus_on() -> bool:
	return Bal.vi("levelup/focus_guard", 1) == 1

## 回复类升级卡（1.1 用户要求：回血偏弱，出现率调高）：[kind, id]——博士被动「自愈」「坚韧」、医疗无人机、填充卡「急救补给」。
## 吸血 / 击杀回复等在藏品池（relic_pool_ids），不在这里
const HEAL_CARDS := [["growth", "regen"], ["growth", "hp"], ["weapon", "drone"], ["filler", "heal"]]


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


func _init(game: Game) -> void:
	g = game
	affinity = BuildAffinity.new(game)


## 招募卡：data/characters 里未在队、且允许招募（JSON 无 "recruitable": false）的干员
func recruit_cards() -> Array:
	var opts: Array = []
	# --norecruit（仅 --balance）：单人打满全程，测单个干员的纯个人数值（docs/27 §6）
	if g.squad.is_full() or (g.mode == g.Mode.BALANCE and Cfg.dev_args().has("--norecruit")):
		return opts
	for cid in Character.list_ids():
		if g.squad.has(cid):
			continue
		var d: Dictionary = Character.load_def(cid)
		if not d.get("recruitable", true) or not Roster.is_unlocked(cid):
			continue
		var desc: String = d.get("gallery", {}).get("desc", d.get("attack", {}).get("desc", ""))
		# 入队加成不再逐张写（用户 10-13）：统一写在三选一标题下的说明行（choice_panel.show_choices）
		opts.append({"kind": "recruit", "id": cid, "name": d.get("name", cid), "desc": desc, "cls": d.get("class", "")})
	return opts


## 更换队友卡（用户 10-13 批准）：编队满员后，招募卡照常按原概率出现，选中后进「更换队友」画面（open_swap），可以「不替换」。
## 候选同 recruit_cards（未在队、允许招募），带 swap = true。levelup/swap_offer = 0 关（满员后不再出招募卡，同改前）
func swap_cards() -> Array:
	var opts: Array = []
	if not g.squad.is_full() or Bal.vi("levelup/swap_offer", 1) == 0 or (g.mode == g.Mode.BALANCE and Cfg.dev_args().has("--norecruit")):
		return opts
	if not g.squad.ops.any(func(o): return not o.is_leader):
		return opts
	for cid in Character.list_ids():
		if g.squad.has(cid):
			continue
		var d: Dictionary = Character.load_def(cid)
		if not d.get("recruitable", true) or not Roster.is_unlocked(cid):
			continue
		var desc: String = d.get("gallery", {}).get("desc", d.get("attack", {}).get("desc", ""))
		opts.append({"kind": "recruit", "swap": true, "id": cid, "name": d.get("name", cid), "desc": desc + "
编队已满：选中后挑一名队友换下，可以不替换。",
			"cls": d.get("class", ""), "cat": "更换 · %s  SWAP" % d.get("class", "")})
	return opts


func open_levelup() -> void:
	var want: int = 3 + g.rfx.rule("four_choices") + g.rfx.take_choice_extra()   # 后者：一次性「多一个选项」（docs/57 P27）
	var picks: Array = []
	# ---- 招募（docs/23 §6）：Lv.5 起进池；保底：Lv.6 仍只有 1 人 / Lv.12 仍不满 3 人 → 本次必出招募
	var recruit: Array = recruit_cards()
	var must_recruit: bool = not recruit.is_empty() and ((g.level >= Bal.vi("levelup/force_recruit_level_1", 6) and g.squad.size() <= 1) or (g.level >= Bal.vi("levelup/force_recruit_level_3", 12) and g.squad.size() < Squad.REGULAR_MAX))
	if must_recruit:
		# 保底画面（docs/119 §4.3）：有合格人选时保证一名与已持有藏品有实际互动的候选（build_affinity.forced_recruit_order；开关关 = 只洗牌）
		var n_show: int = want + g.rfx.rule("recruit_extra")   # 罗德岛战术电台：招募多一个选项
		g.panel_ui.show_choices("招募干员", affinity.forced_recruit_order(recruit, n_show).slice(0, n_show), "level")
		return
	# ---- 干员深度：Lv.2–4 只养开局干员；之后至少一张
	var deep: Array = []
	for o in g.squad.ops:
		if g.level <= 4 and o != g.ch:
			continue
		for c in o.deep_cards():
			if c.kind == "prog" and not c.get("avail", true):
				continue
			deep.append(c)
	g.shuffle(deep)
	# 培养保底（docs/119 §4.2 简化版）：最近培养的干员有合法成长卡就挪到 deep[0]（只重排，不多取随机数、不加选项）；离队 / 养满自然失效
	if focus_on() and focus_op != "" and not deep.is_empty():
		if not g.squad.has(focus_op):
			focus_op = ""
		for k in deep.size():
			if str(deep[k].get("op", "")) == focus_op:
				if k > 0:
					var fc: Dictionary = deep[k]
					deep.remove_at(k)
					deep.insert(0, fc)
				break
	if not deep.is_empty():
		picks.append(deep[0])
		# 编队 ≥ 2 人时约一半的升级给第二张深度卡（换一名干员）
		if g.squad.size() >= 2 and g.rng.randf() < Bal.v("levelup/second_deep_chance", 0.5):
			for rc in deep.slice(1):
				if rc.get("op", "") != deep[0].get("op", ""):
					picks.append(rc)
					break
	# ---- 招募卡：Lv.5 起、编队未满时约 45% 出一张
	# 编队满员：同一个概率出「更换队友」卡（swap_cards；关掉时为空，随机数消耗与改前相同）
	if recruit.is_empty():
		recruit = swap_cards()
	if g.level >= Bal.vi("levelup/recruit_from_level", 5) and not recruit.is_empty() and g.rng.randf() < Bal.v("levelup/recruit_chance", 0.45):
		picks.append(recruit[g.rng.randi() % recruit.size()])
	# ---- 生存 / 机动 / 协同被动：种类上限 生存 4、机动 levelup/mobility_kinds（3）、协同 4（docs/83）
	var passives: Array = g.doctor.passive_cards("doctor") + g.doctor.passive_cards("mobility") + g.doctor.passive_cards("squad")
	# 医疗无人机：和被动卡同池的常规选项，没满级就一直在池里（2026-09-25）；2026-09-26 起开局不带，第一张卡是 Lv.1「加入」
	var wl: int = g.weapons.get("drone", 0)
	if wl < 5:
		var W: Dictionary = D.WEAPONS.drone
		passives.append({"kind": "weapon", "id": "drone", "name": "%s  Lv.%d" % [W.name, wl + 1], "desc": W.lv[wl], "wlv": wl + 1})
	passives = weighted_order(passives)
	for c in passives:
		if picks.size() >= want:
			break
		picks.append(c)
	# ---- 深度卡补位，再不够用填充卡
	var di := 1
	while picks.size() < want and di < deep.size():
		if not picks.has(deep[di]):
			picks.append(deep[di])
		di += 1
	var fillers: Array = weighted_order(g.doctor.filler_cards())
	var fi := 0
	while picks.size() < want and fi < fillers.size():
		picks.append(fillers[fi])
		fi += 1
	g.shuffle(picks)
	var low: bool = g.hp < g.max_hp * Bal.v("levelup/heal_low_hp", 0.5)
	if low:
		low_levelups += 1
	for c in picks.slice(0, want):
		if c.kind == "prog":
			g.dbg_offer[c.op] = g.dbg_offer.get(c.op, 0) + 1
		if is_heal_card(c):
			heal_offer += 1
			if low:
				heal_offer_low += 1
	g.panel_ui.show_choices("升级！ Lv.%d" % g.level, picks.slice(0, want), "level")


## 成长项定义：博士 / 全队被动（doctor.PASSIVES）
func growth_def(gid: String) -> Dictionary:
	if g.doctor.PASSIVES.has(gid):
		return g.doctor.PASSIVES[gid]
	return {"name": gid, "desc": "", "max": 1}


## 全队的干员深度卡：每个干员的下一个成长节点（条件未满足的精英化卡不出）+ 子类追加卡
func deep_cards() -> Array:
	var out: Array = []
	for o in g.squad.ops:
		for c in o.deep_cards():
			if c.kind == "prog" and not c.get("avail", true):
				continue
			out.append(c)
	return out


## 可选藏品：已实装、未拥有、满足前置与职业门槛；按稀有度加权排序（基础 60 / 稀有 26 / 核心 12 / 升华 3，升华 7:00 后才出）
## docs/35：流派加权（已拿过该流派 n 件 → ×1.3^n，封顶 ×2；守护·续航不参与，否则拿了生存卡就只剩生存卡）；
## 守护·续航（H）随时间变多（3:00 前 ×0.7 → 9:00 后 ×1.0；它件数最多，×1.0 已经是最常见的流派）
## 护盾保底：还没有护盾层数时，给层数的藏品 ×relic/shield_weight（缺省 4，docs/35 §护盾保底）
func relic_pool_ids(for_shop := false) -> Array:
	# docs/57：relic/new_pool = 0 时第二批实装的藏品不进池（同 seed 结果与之前一致，供云端 A/B）
	var new_ok: bool = Bal.vi("relic/new_pool", 1) != 0
	var cands: Array = g.rfx.db.implemented().filter(func(r): return (new_ok or not r.new_pool) and g.rfx.can_offer(r, for_shop) and can_gain_relic(r.id))
	var lane_n := {}
	for rid in g.relics:
		for ln in g.RL.get(rid, {}).get("lanes", []):
			if ln != "H":
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
		var best_n := 0
		for ln in r.lanes:
			best_n = maxi(best_n, lane_n.get(ln, 0))
		if best_n > 0:
			w *= minf(pow(Bal.v("relic/lane_weight", 1.3), best_n), Bal.v("relic/lane_weight_cap", 2.0))
		if r.lanes.has("H"):
			w *= h_w
		# 犹疑 (240)：稀有 / 核心 权重 +30%
		if g.rfx.rule("rare_weight") > 0 and r.rarity in ["稀有", "核心"]:
			w *= 1.3
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


func open_relic_choice() -> void:
	var pool: Array = []
	for rid in relic_pool_ids():
		var r: Dictionary = g.RL[rid]
		pool.append({"kind": "relic", "id": rid, "name": "【%s】%s" % [r.cat, g.rfx.display_name(rid)], "desc": g.rfx.display_desc(rid)})
	if pool.is_empty():
		# 每个待开的宝箱各补 12 源石锭
		var n: int = maxi(1, g.pending_chests)
		g.pending_chests = 0
		g.rfx.gain_ingots(12 * n, "暂无可升级藏品 · ")
		return
	# 一次性加选项（docs/57 P27）与补给箱钥匙（P17）：各多一个选项，用掉一次
	var extra: int = g.rfx.take_choice_extra()
	if g.rfx.rule("chest_keys") > 0:
		g.rfx.use_rule("chest_keys")
		extra += 1
		g.vfx.add_text(g.ppos + Vector2(0, -96), "钥匙 · 多一个选项", UI.GOLD, 15)
	var shown: Array = pool.slice(0, 3 + g.rfx.rule("four_choices") + extra)
	g.meta_basic_pick = false
	if g.mode == g.Mode.BALANCE:
		g.dbg_relic_offer.append([int(g.t), "choice", shown.map(func(c): return c.id)])
	g.panel_ui.show_choices("获得藏品", shown, "relic")


## 「更换队友」画面的上下文：{opts, kind, title, sub, sel, new}。选「不替换」时按它恢复刚才的三选一（这次选择不消耗）
var swap_ctx: Dictionary = {}
var swaps: Array = []   # 本局换人记录 [秒, 换下, 换上]（遥测 / 作战记录）


## ---- 机器人 / 自动测试的换人（bot/swap 旋钮，缺省 0 = 一律「不替换」：满员招募卡不进候选，局面与没有这张卡时一样）。
## bot/swap = 1：按评分换——干员分 = 档位（S+ 3 / S 2 / A+ 1 / 其余 0）+ 换完编队里没有医疗 / 重装时医疗或重装 +2；
## 新干员比分最低的队友高 0.5 以上才换（换掉分最低的那名）。返回要换下的队友 id，"" = 不换
func auto_swap_target(card: Dictionary) -> String:
	if Bal.vi("bot/swap", 0) == 0 or card.is_empty():
		return ""
	var tier_v := func(cid: String) -> float:
		return float({"S+": 3, "S": 2, "A+": 1}.get(str(Bal.op(cid).get("tier", "A")), 0))
	var new_cls: String = str(card.get("cls", ""))
	var best_id := ""
	var best_gain := 0.5
	for op in g.squad.ops:
		if op.is_leader:
			continue
		var rest: Array = g.squad.ops.filter(func(o): return o != op).map(func(o): return o.cls)
		var sustain_rest: bool = rest.has("医疗") or rest.has("重装")
		var v_old: float = tier_v.call(op.id) + (2.0 if not sustain_rest and op.cls in ["医疗", "重装"] else 0.0)
		var v_new: float = tier_v.call(str(card.id)) + (2.0 if not sustain_rest and new_cls in ["医疗", "重装"] else 0.0)
		if v_new - v_old > best_gain:
			best_gain = v_new - v_old
			best_id = op.id
	return best_id


## 自动选卡可选的下标：满员招募卡只在 auto_swap_target 给出人选时才算
func auto_choices() -> Array:
	var out: Array = []
	for i in g.choices.size():
		var c: Dictionary = g.choices[i]
		if c.get("kind", "") == "recruit" and c.get("swap", false) and auto_swap_target(c) == "":
			continue
		out.append(i)
	return out


## 「更换队友」画面里自动选哪一项：auto_swap_target 的那名队友，否则「不替换」
func auto_swap_pick() -> int:
	var who: String = auto_swap_target(swap_ctx.get("new", {}))
	for i in g.choices.size():
		if who != "" and str(g.choices[i].get("op", "")) == who and g.choices[i].get("kind", "") == "swap_out":
			return i
	for i in g.choices.size():
		if g.choices[i].get("kind", "") == "swap_keep":
			return i
	return 0


## 选中满员时的招募卡：列出可换下的队友（队长除外）+「不替换」
func open_swap(card: Dictionary, sel: int) -> void:
	swap_ctx = {"opts": g.choices, "kind": g.choice_kind, "title": g.panel_title_text, "sub": g.panel_ui.panel_sub_text, "sel": sel, "new": card}
	var nd: Dictionary = Character.load_def(str(card.id))
	var opts: Array = []
	for op in g.squad.ops:
		if op.is_leader:
			continue
		var total: int = op.progression().size()
		var stage: String = ["", "精英一，", "精英二，"][clampi(op.elite, 0, 2)]
		var n_new: int = (nd.get("progression", []) as Array).size()
		var desc := "当前：%s成长节点 %d/%d。
「%s」接替，继承%s成长节点 %d/%d。
离队后仍可能再被招募。" % [
			stage, op.prog, total, card.name, stage, mini(op.prog, n_new), n_new]
		# docs/119 §4.3：继承后的阶段与技能、新增 / 失去的藏品受益（build_affinity，开关关为空）
		var sw: String = affinity.swap_lines(op, str(card.id))
		if sw != "":
			desc += "\n" + sw
		opts.append({"kind": "swap_out", "op": op.id, "new": str(card.id), "name": "换下 " + op.display_name(), "desc": desc,
			"cat": "队友 · %s  SWAP OUT" % op.cls})
	opts.append({"kind": "swap_keep", "name": "不替换", "desc": "保留当前编队，返回上一步重新选择。
这次升级不消耗。", "cat": "保留编队  KEEP", "col": UI.SUB})
	var sub := "「%s」（%s）加入编队，换下一名队友 · 继承其精英化阶段与成长节点 · 队长不能更换" % [card.name, card.get("cls", "")]
	g.panel_ui.show_choices("更换队友", opts, "swap", sub, true)


## 「不替换」：回到刚才的三选一，焦点留在那张招募卡上
func cancel_swap() -> void:
	var ctx := swap_ctx
	swap_ctx = {}
	g.panel_ui.show_choices(ctx.title, ctx.opts, ctx.kind, ctx.sub, true)
	g.panel_ui.motion.skip()
	g.nav_sel = int(ctx.get("sel", 0))


## ---- 培养路线二选一（docs/119 §4.1，试点 4 人：德克萨斯 / 星熊 / 艾雅法拉 / 铃兰）。
## 外层升级三选一只出一张该干员的培养卡（character.deep_cards 的 branch: true）；选中后进这一屏选路线，确认才推进节点、只扣这一次升级；
## 「返回」恢复原卡组（不重抽、不扣）。换入会继承到节点 4 及以上的试点干员时，换人确认前也走这一屏（source = swap）；
## 典训 / 博士银印等赠送推进碰到分支节点时排进 branch_queue，check_pending 时弹出（source = free：只能确认，不扣升级、不重发奖励）

## 干员定义里的分支节点（节点 4）及其下标；没有返回 [{}, -1]
static func branch_node_of(def: Dictionary) -> Array:
	if not Character.branch_on():
		return [{}, -1]
	var pg: Array = def.get("progression", [])
	for k in pg.size():
		if pg[k] is Dictionary and pg[k].get("branch", null) is Dictionary and not (pg[k].branch as Dictionary).is_empty():
			return [pg[k], k]
	return [{}, -1]


## 没有干员实例时（换人流程）的固定路线：节点 "bot" 字段，否则第一条
static func default_route(n: Dictionary) -> String:
	var alts: Dictionary = n.get("branch", {})
	var b: String = str(n.get("bot", ""))
	return b if alts.has(b) else (str(alts.keys()[0]) if not alts.is_empty() else "")


## 换入 new_id 接替 old_id 时要不要先选路线：继承的节点数覆盖到新干员的分支节点、且该节点还没选
func swap_needs_route(card: Dictionary) -> bool:
	if str(card.get("route", "")) != "":
		return false
	var old = g.squad.get_op(str(card.get("op", "")))
	if old == null:
		return false
	var bn: Array = branch_node_of(Character.load_def(str(card.get("new", ""))))
	return bn[1] >= 0 and old.prog > bn[1]


## 赠送推进遇到分支节点（character.advance 转来）：玩家局排队进路线选择画面并返回 true（本次不推进）；
## 机器人 / 测试 / 演示 / Boss 演练返回 false（advance 按 bot_route 固定选）
func branch_defer(op) -> bool:
	if g.mode != g.Mode.PLAY or g.demo_op != "" or g.trial.active or g.bot != null:
		return false
	if not branch_queue.has(op.id):
		branch_queue.append(op.id)
	return true


## 排队中的赠送推进：开路线选择（game.check_pending 调）。返回是否开了一屏
func open_branch_queued() -> bool:
	while not branch_queue.is_empty():
		var oid: String = str(branch_queue.pop_front())
		var op = g.squad.get_op(oid)
		if op != null and op.needs_route():
			open_branch({"kind": "prog", "op": oid, "choice": "", "branch": true}, 0, "free")
			return true
	return false


## 路线选项卡：source = level（升级卡）/ swap（换人确认前，card 是 swap_out 项）/ free（赠送推进，没有「返回」）
func open_branch(card: Dictionary, sel: int, source := "level") -> void:
	var n: Dictionary = {}
	var who := ""
	var col: Color = UI.CYAN
	if source == "swap":
		var nd: Dictionary = Character.load_def(str(card.get("new", "")))
		n = branch_node_of(nd)[0]
		who = str(nd.get("name", card.get("new", "")))
	else:
		var op = g.squad.get_op(str(card.get("op", "")))
		if op == null:
			return
		n = op.next_node()
		who = op.display_name()
		col = op.col()
	var rc: Dictionary = n.get("branch", {})
	if rc.is_empty():
		return
	branch_ctx = {"opts": g.choices, "kind": g.choice_kind, "title": g.panel_title_text, "sub": g.panel_ui.panel_sub_text, "sel": sel, "card": card, "source": source}
	var opts: Array = []
	for rid in rc:
		var cd: Dictionary = rc[rid]
		var item := {"kind": "branch_pick", "op": str(card.get("new", card.get("op", ""))), "route": str(rid), "name": str(cd.get("name", rid)),
			"desc": str(cd.get("desc", "")), "icon": str(cd.get("icon", n.get("icon", ""))), "cat": "路线 · %s  PATH" % who}
		if cd.has("col"):
			item["col"] = cd.col
		opts.append(item)
	if source != "free":
		opts.append({"kind": "branch_back", "name": "返回", "desc": "回到上一步重新选择。\n这次升级不消耗。", "cat": "返回  BACK", "col": UI.SUB})
	var bidx: int = branch_node_of(Character.load_def(str(card.get("new", card.get("op", "")))))[1]
	var stage: String = ("第 %d 节点" % (bidx + 1)) if bidx >= 0 else "分支节点"
	var sub := "「%s」%s：选定一条培养路线 · 之后的节点沿它强化" % [who, stage]
	match source:
		"level":
			sub += " · 只消耗这一次升级"
		"swap":
			sub += " · 换入后按此路线继承成长"
		"free":
			sub += " · 赠送的推进：选定后立即生效，不消耗升级"
	g.panel_ui.show_choices("培养路线", opts, "branch", sub, true)
	g.nav_sel = 0


## 「返回」：回到上一屏（升级三选一 / 更换队友），焦点留在原来那张卡上，不重抽、不扣升级
func cancel_branch() -> void:
	var ctx := branch_ctx
	branch_ctx = {}
	g.panel_ui.show_choices(ctx.title, ctx.opts, ctx.kind, ctx.sub, true)
	g.panel_ui.motion.skip()
	g.nav_sel = int(ctx.get("sel", 0))


## 机器人在路线屏选哪一项：固定路线（干员实例 bot_route / 换人 default_route）那张；找不到取 0
func auto_branch_pick() -> int:
	var want := ""
	var card: Dictionary = branch_ctx.get("card", {})
	if str(branch_ctx.get("source", "")) == "swap":
		want = default_route(branch_node_of(Character.load_def(str(card.get("new", ""))))[0])
	else:
		var op = g.squad.get_op(str(card.get("op", "")))
		if op != null:
			want = op.bot_route(op.next_node())
	for i in g.choices.size():
		if g.choices[i].get("kind", "") == "branch_pick" and str(g.choices[i].get("route", "")) == want:
			return i
	return 0


func pick(i: int) -> void:
	if g.state != g.S.CHOICE or i >= g.choices.size():
		return
	var o: Dictionary = g.choices[i]
	match o.kind:
		"recruit":
			if o.get("swap", false):
				open_swap(o, i)   # 不消耗：进更换画面
				Sfx.play("ui_ok", -4.0)
				return
		"swap_keep":
			cancel_swap()
			Sfx.play("ui_ok", -6.0)
			return
		"swap_out":
			if swap_needs_route(o):
				open_branch(o, i, "swap")   # 不消耗：先选换入干员的培养路线
				Sfx.play("ui_ok", -4.0)
				return
			g.choice_kind = str(swap_ctx.get("kind", "level"))   # 按原来那次三选一结算（扣升级次数）
			swap_ctx = {}
		"prog":
			if o.get("branch", false) and str(o.get("choice", "")) == "":
				open_branch(o, i, "level")   # 不消耗：进路线二选一
				Sfx.play("ui_ok", -4.0)
				return
		"branch_back":
			cancel_branch()
			Sfx.play("ui_ok", -6.0)
			return
		"branch_pick":
			var bctx := branch_ctx
			branch_ctx = {}
			var src: String = str(bctx.get("source", "level"))
			if src == "free":
				# 赠送推进：直接推进，不扣升级、不重发奖励；回到战斗再看有没有下一位排队
				var fop = g.squad.get_op(str(o.get("op", "")))
				if fop != null:
					fop.advance(str(o.route))
					g.fx.append({"kind": "ring", "pos": fop.pos, "r": 90.0, "life": 0.45, "max": 0.45, "col": Color(0.6, 0.9, 1.0)})
					g.vfx.promote_burst(fop.pos, false)
				g.panel.visible = false
				Sfx.play("ui_ok", -4.0)
				g.state = g.S.PLAY
				g.check_pending()
				return
			# 升级卡 / 换人：换成带路线的原卡，按原来那一屏结算（只扣这一次升级）
			o = (bctx.get("card", {}) as Dictionary).duplicate()
			if src == "swap":
				o["route"] = str(g.choices[i].route)
				g.choice_kind = str(swap_ctx.get("kind", "level"))
				swap_ctx = {}
			else:
				o["choice"] = str(g.choices[i].route)
				g.choice_kind = str(bctx.get("kind", "level"))
	if g.choice_kind == "level" and is_heal_card(o):
		heal_pick += 1
	match o.kind:
		"event":
			g.endg.pick(o)
		"growth":
			g.growth[o.id] = g.growth.get(o.id, 0) + 1
			if not g.doctor.apply_passive(o.id):
				var gop = g.squad.get_op(o.get("op", g.ch.id))
				if gop != null:
					gop._apply_growth(o.id)
		"filler":
			g.doctor.apply_filler(o.id)
		"prog":
			g.dbg_pick[o.op] = g.dbg_pick.get(o.op, 0) + 1
			var pop = g.squad.get_op(o.op)
			if pop != null:
				pop.advance(o.get("choice", ""))
				focus_op = str(o.op)   # 培养保底：成为「最近培养对象」
				g.fx.append({"kind": "ring", "pos": pop.pos, "r": 90.0, "life": 0.45, "max": 0.45, "col": Color(0.6, 0.9, 1.0)})
				g.vfx.promote_burst(pop.pos, o.get("elite", 0) > 0)   # docs/54 ⑥（fx/promote_burst）
				if o.get("elite", 0) > 0:
					g.vfx.show_banner("%s 晋升至精英%s" % [pop.display_name(), ["", "一", "二"][o.elite]])
		"swap_out":
			var sop = g.squad.replace(str(o.op), str(o.new), str(o.get("route", "")))
			if sop != null:
				swaps.append([int(g.t), str(o.op), str(o.new)])
				var st: String = ["", "（精英一）", "（精英二）"][clampi(sop.elite, 0, 2)]
				g.vfx.show_banner("「%s」接替「%s」加入编队%s" % [sop.display_name(), Character.load_def(str(o.op)).get("name", o.op), st])
				g.fx.append({"kind": "ring", "pos": g.ppos, "r": 120.0, "life": 0.5, "max": 0.5, "col": Color(0.55, 0.9, 0.55)})
				g.vfx.promote_burst(sop.pos, false)
		"recruit":
			var nop = g.squad.add(o.id)
			if nop != null:
				g.vfx.show_banner("「%s」加入编队" % nop.display_name())
				g.fx.append({"kind": "ring", "pos": g.ppos, "r": 120.0, "life": 0.5, "max": 0.5, "col": Color(0.55, 0.9, 0.55)})
				g.vfx.promote_burst(nop.pos, false)   # docs/54 ⑥ 入队：青色柔光 + 光尘
		"relic":
			gain_relic(o.id)
		"weapon":
			g.weapons[o.id] = o.wlv
			var W: Dictionary = D.WEAPONS[o.id]
			g.vfx.show_banner(("「%s」加入支援" % W.name) if o.wlv == 1 else ("「%s」升至 Lv.%d" % [W.name, o.wlv]))
			g.fx.append({"kind": "ring", "pos": g.ppos, "r": 110.0, "life": 0.45, "max": 0.45, "col": W.col})
	# 事件选项不占升级 / 宝箱次数（祭坛被打碎时直接弹出，没有计入 pending）
	if g.choice_kind == "relic":
		g.pending_chests -= 1
	elif g.choice_kind != "event":
		g.pending_levelups -= 1
	g.panel.visible = false
	Sfx.play("ui_ok", -4.0)
	g.state = g.S.PLAY
	if not tab_hinted and not g.tab_used:
		tab_hinted = true
		g.tab_hint = 6.0
	g.check_pending()


func apply_relic(id: String) -> void:
	g.rfx.apply(id)
	if not Cfg.seen_relics.has(id):
		Cfg.seen_relics.append(id)
		Cfg.save()


## 藏品携带上限：relic/carry_cap < 0 = 不限（缺省；用户 10-12 取消上限，爆率即软上限）。≥ 0 时恢复旧规则（含结局信物预留槽），只供对照测试
func relic_cap() -> int:
	return Bal.vi("relic/carry_cap", -1)


## 界面上的藏品数：不限上限时只写「藏品 N」；测试时设了上限才写「N/上限 · 为结局保留 k 格」
func relic_count_text() -> String:
	var cap: int = relic_cap()
	if cap < 0:
		return "藏品 %d" % g.relics.size()
	return "藏品 %d/%d · 为结局保留 %d 格" % [g.relics.size(), cap, g.endg.reserved_relic_slots()]


## 容量按不同藏品计数；升级不增加槽。不限上限时只看「已拥有且满级」。全藏品测试开关只由 Cfg.dev_args 暴露。
func can_gain_relic(id: String) -> bool:
	if not g.RL.has(id):
		return false
	if g.relics.has(id):
		return int(g.rfx.lv.get(id, 0)) < g.rfx.max_lv(id)
	if g.mode == g.Mode.BALANCE and Cfg.dev_args().has("--relics=all"):
		return true
	var cap: int = relic_cap()
	if cap < 0:
		return true
	if g.relics.size() >= cap:
		return false
	if g.endg.is_route_relic(id):
		return true
	return g.relics.size() + g.endg.reserved_relic_slots() < cap


## 获得藏品的唯一入口：登记、生效、重算结局。拒绝时不产生任何效果。
func gain_relic(id: String) -> bool:
	if not can_gain_relic(id):
		return false
	g.dbg_relic_take.append([int(g.t), id, g.squad.ops.map(func(o): return o.cls)])   # 玩家局也记（docs/40）
	if not g.relics.has(id):
		g.relics.append(id)
	apply_relic(id)
	# 先记下这件藏品触发的结局时刻，再做骑士登场 / 离队：离队会再拿 223 并重算结局，
	# 若那时深蓝（221）的时刻还没记，会先按结局一重算一次、弹出「结局一」的横幅（2026-09-27 用户报的 bug）
	g.endg.note_relic(id)
	if id == "222" and not g.knight.alive and not g.knight.fallen:
		g.knight.spawn()
	elif id == "221" and g.knight.alive:
		g.knight.leave()
	g.endg.on_relic(id)
	return true
