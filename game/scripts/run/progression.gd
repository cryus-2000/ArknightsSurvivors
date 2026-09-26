extends RefCounted
## 升级与藏品发放（逻辑）：升级卡池（招募 / 干员深度 / 博士与全队被动 / 填充，docs/23 §6）、藏品候选池、选中后的结算与藏品获得。
## 选卡界面（卡片绘制、动画）在 screens/ 下。2026-09-26 从 game.gd 拆出。

const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
const Character = preload("res://scripts/characters/character.gd")
const Squad = preload("res://scripts/characters/squad.gd")
const Bal = preload("res://scripts/core/balance.gd")   # data/balance.json 数值旋钮（docs/27）

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game
var tab_hinted := false
var probe_applied := 0


func _init(game: Game) -> void:
	g = game


## 招募卡：data/characters 里未在队、且允许招募（JSON 无 "recruitable": false）的干员
func recruit_cards() -> Array:
	var opts: Array = []
	# --norecruit（仅 --balance）：单人打满全程，测单个干员的纯个人数值（docs/27 §6）
	if g.squad.is_full() or (g.balance and OS.get_cmdline_user_args().has("--norecruit")):
		return opts
	for cid in Character.list_ids():
		if g.squad.has(cid):
			continue
		var d: Dictionary = Character.load_def(cid)
		if not d.get("recruitable", true):
			continue
		opts.append({"kind": "recruit", "id": cid, "name": d.get("name", cid), "desc": d.get("gallery", {}).get("desc", d.get("attack", {}).get("desc", "")), "cls": d.get("class", "")})
	return opts


func open_recruit() -> bool:
	var opts := recruit_cards()
	if opts.is_empty():
		return false
	g._shuffle(opts)
	g.panel_ui.show_choices("招募干员", opts.slice(0, 3), "level")
	return true


func open_levelup() -> void:
	var want: int = 3 + g.rfx.rule("four_choices")
	var picks: Array = []
	# ---- 招募（docs/23 §6）：Lv.5 起进池；保底：Lv.6 仍只有 1 人 / Lv.12 仍不满 3 人 → 本次必出招募
	var recruit: Array = recruit_cards()
	var must_recruit: bool = not recruit.is_empty() and ((g.level >= Bal.vi("levelup/force_recruit_level_1", 6) and g.squad.size() <= 1) or (g.level >= Bal.vi("levelup/force_recruit_level_3", 12) and g.squad.size() < Squad.REGULAR_MAX))
	if must_recruit:
		g._shuffle(recruit)
		g.panel_ui.show_choices("招募干员", recruit.slice(0, want), "level")
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
	g._shuffle(deep)
	if not deep.is_empty():
		picks.append(deep[0])
		# 编队 ≥ 2 人时约一半的升级给第二张深度卡（换一名干员）
		if g.squad.size() >= 2 and g.rng.randf() < Bal.v("levelup/second_deep_chance", 0.5):
			for rc in deep.slice(1):
				if rc.get("op", "") != deep[0].get("op", ""):
					picks.append(rc)
					break
	# ---- 招募卡：Lv.5 起、编队未满时约 45% 出一张
	if g.level >= Bal.vi("levelup/recruit_from_level", 5) and not recruit.is_empty() and g.rng.randf() < Bal.v("levelup/recruit_chance", 0.45):
		picks.append(recruit[g.rng.randi() % recruit.size()])
	# ---- 博士被动 / 全队被动：种类各上限 4
	var passives: Array = g.doctor.passive_cards("doctor") + g.doctor.passive_cards("squad")
	# 医疗无人机：和被动卡同池的常规选项，没满级就一直在池里（2026-09-25）；2026-09-26 起开局不带，第一张卡是 Lv.1「加入」
	var wl: int = g.weapons.get("drone", 0)
	if wl < 5:
		var W: Dictionary = D.WEAPONS.drone
		passives.append({"kind": "weapon", "id": "drone", "name": "%s  Lv.%d" % [W.name, wl + 1], "desc": W.lv[wl], "wlv": wl + 1})
	g._shuffle(passives)
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
	var fillers: Array = g.doctor.filler_cards()
	g._shuffle(fillers)
	var fi := 0
	while picks.size() < want and fi < fillers.size():
		picks.append(fillers[fi])
		fi += 1
	g._shuffle(picks)
	for c in picks.slice(0, want):
		if c.kind == "prog":
			g.dbg_offer[c.op] = g.dbg_offer.get(c.op, 0) + 1
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
func relic_pool_ids(for_shop := false) -> Array:
	var cands: Array = g.rfx.db.implemented().filter(func(r): return g.rfx.can_offer(r, for_shop))
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
		if w <= 0.0:
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
		# 已拥有的藏品升级：出现率减半
		if g.relics.has(r.id):
			w *= 0.5
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
		g.ingots += 12 * n
		g.vfx.add_text(g.ppos + Vector2(0, -90), "藏品已集齐 · 源石锭 +%d" % (12 * n), UI.GOLD, 16)
		return
	var shown: Array = pool.slice(0, 3 + g.rfx.rule("four_choices"))
	if g.balance:
		g.dbg_relic_offer.append([int(g.t), "choice", shown.map(func(c): return c.id)])
	g.panel_ui.show_choices("获得藏品", shown, "relic")


func pick(i: int) -> void:
	if g.state != g.S.CHOICE or i >= g.choices.size():
		return
	var o: Dictionary = g.choices[i]
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
				g.fx.append({"kind": "ring", "pos": pop.pos, "r": 90.0, "life": 0.45, "max": 0.45, "col": Color(0.6, 0.9, 1.0)})
				if o.get("elite", 0) > 0:
					g.vfx.show_banner("%s 精英化%s" % [pop.display_name(), ["", "一", "二"][o.elite]])
		"recruit":
			var nop = g.squad.add(o.id)
			if nop != null:
				g.vfx.show_banner("「%s」加入编队" % nop.display_name())
				g.fx.append({"kind": "ring", "pos": g.ppos, "r": 120.0, "life": 0.5, "max": 0.5, "col": Color(0.55, 0.9, 0.55)})
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
	g._check_pending()


func apply_relic(id: String) -> void:
	g.rfx.apply(id)
	if not Cfg.seen_relics.has(id):
		Cfg.seen_relics.append(id)
		Cfg.save()


## 获得藏品的唯一入口：登记、生效、重算结局
func gain_relic(id: String) -> void:
	g.dbg_relic_take.append([int(g.t), id, g.squad.ops.map(func(o): return o.cls)])   # 玩家局也记（docs/40）
	if g.balance and g.RL.get(id, {}).get("rarity", "") != "结局":
		if OS.get_cmdline_user_args().has("--norelics"):
			return
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--relicmax="):
				if probe_applied >= int(a.substr(11)):
					return
				probe_applied += 1
	if not g.relics.has(id):
		g.relics.append(id)
	apply_relic(id)
	if id == "222" and not g.knight.alive and not g.knight.fallen:
		g.knight.spawn()
	elif id == "221" and g.knight.alive:
		g.knight.leave()
	g.endg.on_relic(id)
