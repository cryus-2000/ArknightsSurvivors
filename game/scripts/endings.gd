## 结局与翻节点卡（docs/154，取代海嗣祭坛；docs/184 事件改版）：3:30 / 7:00 中 Boss 全部倒下后各翻一次节点卡（路口一 / 二），另有 1:20 / 6:00 两次途中路口。
## 结局线入口（狂徒妄念、开端）路口一必出；持某线信物时路口二必出该线后续事件；其余位置按权重随机填充。
## 结局只看信物：满足条件的结局里取 priority 最高的（原作数据 endings.priority）；最终 Boss 登场即冻结。
## 数据：data/waves.json 的 cross_deck / events / endings + data/events_v2.json；进度：Cfg.endings_cleared（通关过结局一才出结局线入口卡）。
extends RefCounted

const BossBench = preload("res://scripts/run/boss_bench.gd")   # 录制钩子（docs/170）
const D = preload("res://scripts/data.gd")
const BuildGuide = preload("res://scripts/run/build_guide.gd")   # 构筑引导：主流派等保底 / 加权规则
const Bal = preload("res://scripts/core/balance.gd")
const NodeIcons = preload("res://scripts/screens/node_icons.gd")
const UM = preload("res://scripts/ui_motion.gd")
const EventBook = preload("res://scripts/core/event_book.gd")   # 事件图鉴记录（docs/184 §11）

var g
var events: Array = []          # 事件表（waves.json）
var ev_by_id: Dictionary = {}
var endings: Dictionary = {}    # 结局表
var deck_cfg: Dictionary = {}   # waves.json cross_deck
var cur := "standard"           # 当前结局
var opened_id := ""             # 正在弹选项的事件
var shown_id := ""              # 面板上正显示的事件（插画键用它：opened_id 在 pick 开头就清空，面板若没关掉会读空；10-29 用户卡死空面板）
var warned_final := false
var all_unlocked := false       # --allend：无视通关进度
var frozen := false             # 最终 Boss 已刷出：结局冻结
var enabled := false            # 本局开启翻卡（_cross_on，第一次 update 时定）
var _checked := false
var cross_done := 0             # 已发过几个路口（0 / 1 / 2）
var cross_due := 0              # 到点待弹的路口（0 = 无）
var boss_seen := false          # 本路口窗口里见过活着的中 Boss
var clear_t := -1.0             # 本批中 Boss 全部倒下的时刻
var deck: Array = []            # 当前路口的卡：{type, event?, must, ends}
var flipped := -1               # 翻开的那张（-1 = 还没选）
var flip_t := 0.0               # 翻开的时刻（界面时钟 UM.now()，录屏 --fixed-fps 下按帧走）
var used_common: Array = []     # 本局出过的普通不期而遇
var searched: Array = []        # 深蓝之心搜过的房间（"heart:i"）
var last_type := ""             # 上一个路口翻开的卡种
var picks: Array = []           # 作战记录：[路口, 卡种, 事件 id]
var incidents := 0              # 不期而遇次数（作战记录）
var wish_rare := false          # 得偿所愿：下一次藏品三选一稀有 / 核心加权
var elites: Array = []          # 紧急作战刷出的精英小队成员
var squad_pending: Array = []   # 精英小队里同屏上限放不下、推迟刷出的成员：[类型, 出生点]
var squad_affix := ""           # 这支小队共用的词缀（armor 甲壳 / shield 潮盾）
var squad_at := -1.0            # --squadat=秒（调试构建）：到点强制刷一支精英小队
var elite_pos := Vector2.ZERO
var _mh_n := 0                  # 事件改最大生命的次数（stats 来源名）
var route := ""                 # --route=knight|heart|memory|none|rand（机器人走哪条线；空 = 按 seed 轮换）
# ---- 事件改版（docs/184）
var lines_on := false           # 结局线入口卡开不开（通关结局一后；测试 / 批跑缺省开）
var mid_done := 0               # 途中路口已发几次（0 / 1 / 2）
var c1_deal_t := -1.0           # 路口一发牌时刻（晚于途中二最早时刻时取消途中二）
var slot := ""                  # 当前摊牌：m1 / c1 / m2 / c2（作战记录）
var lane_bias := ""             # 下一次藏品三选一：2 件出这个流派（主流派加权，progression.open_relic_choice 读后清掉）
var chal: Dictionary = {}       # 进行中的委托：{kind, name, end_t, win, squad, ...}
var away: Array = []            # 暂离的队友：[{id, prog, route, back_t, reward}]
var sub_ctx: Dictionary = {}    # 事件选项里要再选一次的（选干员 / 交藏品）：{queue, promoted, offer}
var trouble := false            # 敬奉火焰「火焰拯救不了这片大地」：下一个路口必出紧急作战，全灭掉两个宝箱
var squad_reward := ""          # 精英小队全灭的奖励："" 宝箱 + 源石锭（--squadat 调试刷的小队）；lane 主流派三选一宝箱；double 两个宝箱；chal 交给委托结算
var _ev_n := 0                  # 事件改属性的次数（stats 来源名）
const MELEE_CLS := BuildGuide.MELEE_CLS

## 各事件通向的结局（卡背色边）
const LINE_ENDS := {"madness": ["knight"], "knight_stay": ["knight"], "opening": ["deep", "resolve"], "heart": ["deep"], "ritual": ["resolve"]}
## 结局线信物：藏品栏上限（relic/carry_cap ≥ 0 时）为它们留位
const ROUTE_RELICS := ["220", "221", "222", "223", "225", "238", "239", "240", "242"]
const FILL_TYPES := ["wish", "rest", "elite", "shop", "incident", "fog"]


func _init(game) -> void:
	g = game
	var w: Dictionary = D.Loader.load_waves()
	events = (w.get("events", []) as Array).duplicate(true)
	endings = w.get("endings", {})
	deck_cfg = (w.get("cross_deck", {}) as Dictionary).duplicate(true)
	_merge_v2()
	for ev in events:
		ev_by_id[str(ev.id)] = ev
	all_unlocked = Cfg.dev_args().has("--allend")
	for a in Cfg.dev_args():
		if a.begins_with("--squadat="):
			squad_at = float(a.substr(10))   # 测试用：到这个游戏秒数强制刷一支精英小队（docs/161 帧时 / 录屏，只在调试构建读）
	for a in Cfg.dev_args():
		if a.begins_with("--route="):
			route = a.substr(8)


## 事件改版数据（data/events_v2.json）：cross 并进 cross_deck、events 追加在 waves.json 事件之后
func _merge_v2() -> void:
	var f := FileAccess.open("res://data/events_v2.json", FileAccess.READ)
	if f == null:
		return
	var v2 = JSON.parse_string(f.get_as_text())
	if not (v2 is Dictionary):
		return
	for k in v2.get("cross", {}):
		deck_cfg[k] = v2.cross[k]
	events.append_array(v2.get("events", []))


## 结局线入口开不开：玩家局要通关过结局一；测试 / 批跑缺省开（--nocross 关）。
## 翻卡本身一直开（--nocross 才关），它只管结局入口卡（docs/184 §5.1）
func _cross_on() -> bool:
	if Cfg.dev_args().has("--nocross"):
		return false
	if all_unlocked or g.mode != g.Mode.PLAY:
		return true
	return Cfg.endings_cleared.has("standard")


## ---------- 路口调度 ----------
func update(_dt: float) -> void:
	if not _checked:
		_checked = true
		lines_on = _cross_on()
		enabled = not Cfg.dev_args().has("--nocross")
	if squad_at >= 0.0 and g.t >= squad_at:
		squad_at = -1.0
		_spawn_elites()
	_tick_elites()
	_tick_chal()
	_tick_away()
	if frozen:
		return
	if g.final_boss != null:
		frozen = true   # 最终 Boss 登场：结局就此冻结（结算与解锁都按这时的结局）
		_log("frozen")
		return
	if enabled:
		_tick_mid()
	if not enabled or cross_done >= 2:
		return
	if cross_due == 0:
		var win: Array = deck_cfg.get("t1" if cross_done == 0 else "t2", [210, 390])
		if g.t >= float(win[0]):
			if g.spawner.boss_alive():
				boss_seen = true
				clear_t = -1.0
			elif boss_seen and clear_t < 0.0:
				clear_t = g.t
			# 中 Boss 全部倒下 delay 秒后弹；最晚 win[1]，到点还没打完也弹（同升级面板，暂停战斗）
			if (clear_t >= 0.0 and g.t >= clear_t + float(deck_cfg.get("delay", 2.0))) or g.t >= float(win[1]):
				cross_due = cross_done + 1
	if cross_due > 0 and g.state == g.S.PLAY and g.pending_chests <= 0 and not _ult_busy():
		_deal(cross_due)


## 发牌：必出卡 + 随机填充到 n 张，按 g.rng 洗牌（同 seed 可复现）
func _deal(n: int) -> void:
	cross_due = 0
	cross_done = n
	boss_seen = false
	clear_t = -1.0
	slot = "c%d" % n
	if n == 1:
		c1_deal_t = g.t
	deck = build_deck(n)
	_show_deck("深入海洋 · 路口%s" % ["一", "二"][n - 1])


func _show_deck(title: String) -> void:
	flipped = -1
	var opts: Array = []
	for i in deck.size():
		opts.append({"kind": "node", "id": str(i), "name": NodeIcons.NAMES[deck[i].type], "desc": "", "node": deck[i]})
	_log("deal %s %s" % [slot, str(deck.map(func(c): return "%s/%s" % [c.type, c.get("event", "")]))])
	g.panel_ui.show_choices(title, opts, "cross", "选一张翻开，翻开即生效")


## 途中路口（docs/184 §2.5）：1:20 / 6:00 起等中 Boss、精英小队、委托都清场再弹，最晚到点照弹；2 张卡、没有结局卡。
## 路口一拖到途中二最早时刻之后才发，途中二取消
func _tick_mid() -> void:
	if mid_done >= 2 or cross_due > 0:
		return
	var wins: Array = deck_cfg.get("mid", [[80, 110], [360, 390]])
	var w: Array = wins[mini(mid_done, wins.size() - 1)]
	if mid_done == 0 and Bal.v("relic/mid1_shift", 35.0) != 0.0:
		var sh: float = Bal.v("relic/mid1_shift", 35.0)   # 途中一整体后移（docs/191：首件藏品推到约 2:00）
		w = [float(w[0]) + sh, float(w[1]) + sh]
	if mid_done == 1 and (c1_deal_t >= float(w[0]) or (c1_deal_t < 0.0 and g.t >= float(w[0]))):
		mid_done = 2
		return
	if g.t < float(w[0]) or g.state != g.S.PLAY or g.pending_chests > 0 or _ult_busy():
		return
	var calm: bool = not g.spawner.boss_alive() and elites.is_empty() and squad_pending.is_empty() and chal.is_empty()
	if not calm and g.t < float(w[1]):
		return
	mid_done += 1
	slot = "m%d" % mid_done
	deck = build_deck(0)
	_show_deck("深入海洋 · 途中")


## 终结技播放中（ult.playing）：路口 / 途中发牌等播完再弹
func _ult_busy() -> bool:
	return g.ult != null and g.ult.playing()


## 还有没有后面的路口（敬奉火焰「麻烦」要有下一个路口兑现）
func _later_slot() -> bool:
	return cross_done < 2 or (mid_done < 2 and cross_done < 1)


## 卡是不是交易卡（docs/184 §2.1）：得偿所愿 / 紧急作战，或不期而遇里带 trade 的事件
func _is_trade(c: Dictionary) -> bool:
	match str(c.get("type", "")):
		"wish", "elite":
			return true
		"incident":
			return bool(ev_by_id.get(str(c.get("event", "")), {}).get("trade", false))
	return false


## n = 1 / 2：路口一 / 二；n = 0：途中路口（只随机填充，mid_n 张，不出迷雾重重）
func build_deck(n: int) -> Array:
	var cards: Array = []
	for ev in events:
		if n == 0 or not lines_on or not ev.get("must", false) or int(ev.get("cross", 0)) != n or not _event_ok(ev):
			continue
		cards.append({"type": "incident", "event": str(ev.id), "must": true, "ends": LINE_ENDS.get(str(ev.id), [])})
	var want: int = maxi(int(deck_cfg.get("mid_n" if n == 0 else "n", 2 if n == 0 else 3)), cards.size())
	if trouble:
		trouble = false   # 敬奉火焰的「麻烦」：这个路口必出一张紧急作战，全灭掉两个宝箱
		cards.append({"type": "elite", "must": false, "ends": [], "double": true, "trade": true})
		want = maxi(want, cards.size())
	var W: Dictionary = deck_cfg.get("weights", {})
	var cand: Array = []
	for t in FILL_TYPES:
		var w: float = float(W.get(t, 0.0)) * _fill_mult(t, cards)
		var u: float = g.rng.randf()   # 每种都抽一次（不论权重是否为 0），随机数消耗固定
		if w > 0.0:
			cand.append([-log(u + 0.0001) / w, t])
	cand.sort_custom(func(a, b): return a[0] < b[0])
	# 同类最多 1 张、无代价卡（安全的角落 / 诡意行商）最多 1 张、最后一个空位还没有交易卡时只放交易卡；
	# 一轮放不满就放宽约束再走一轮（候选按权重顺序，不多取随机数）
	for relax in 2:
		for c in cand:
			if cards.size() >= want:
				break
			var t: String = str(c[1])
			if (n == 0 and t == "fog") or cards.any(func(x): return x.type == t and not x.must and t != "incident"):
				continue
			var fills: Array = cards.filter(func(x): return not x.must)
			var need_trade: bool = relax == 0 and cards.size() == want - 1 and not fills.any(func(x): return _is_trade(x))
			if relax == 0 and t in ["rest", "shop"] and fills.any(func(x): return x.type in ["rest", "shop"]):
				continue
			if need_trade and t in ["rest", "shop", "fog"]:
				continue
			var card := {"type": t, "must": false, "ends": []}
			if t == "incident":
				card.event = _pick_common(need_trade)
				if card.event == "":
					continue
			card.trade = _is_trade(card)
			cards.append(card)
	for c in cards:
		if not c.has("trade"):
			c.trade = not c.get("must", false) and _is_trade(c)
	for i in range(cards.size() - 1, 0, -1):
		var j: int = g.rng.randi() % (i + 1)
		var tmp = cards[i]
		cards[i] = cards[j]
		cards[j] = tmp
	return cards


## 填充卡加权（docs/154 §2.4）：只调填充卡，不碰结局卡
func _fill_mult(t: String, cards: Array) -> float:
	var m := 1.0
	var hp_k: float = g.hp / maxf(1.0, g.max_hp)
	match t:
		"wish":
			if g.t > 360.0:
				m *= 0.8
		"rest":
			if hp_k < 0.5:
				m *= 2.0
			if g.lamp < 30.0:
				m *= 1.5
		"elite":
			if g.lamp >= 70.0:
				m *= 1.5
			if hp_k < 0.35:
				m *= 0.5
		"shop":
			if g.ingots >= 30:
				m *= 1.5
			if g.relics.any(func(r): return g.RL.has(r) and g.RL[r].rarity == "遭诅古物"):
				m *= 1.3
		"incident":
			if _common_left().is_empty():
				return 0.0
			if cards.filter(func(c): return c.type == "incident").size() >= 2:
				m *= 0.5
	if t == last_type:
		m *= 0.5
	return m


func _common_left() -> Array:
	return events.filter(func(ev): return ev.get("pool", "") == "common" and not used_common.has(str(ev.id)) and _req_ok(ev))


## 事件出现条件（events_v2.json req）：mate 队友数 / ingots 源石锭 / before 秒前 / after_cross 路口一之后 / tradeable 有可交出的藏品
func _req_ok(ev: Dictionary) -> bool:
	var q: Dictionary = ev.get("req", {})
	if q.has("mate") and _mates().size() < int(q.mate):
		return false
	if q.has("ingots") and g.ingots < int(q.ingots):
		return false
	if q.has("before") and g.t >= float(q.before):
		return false
	if q.has("after_cross") and cross_done < int(q.after_cross):
		return false
	if q.has("tradeable") and _tradeable().is_empty():
		return false
	if q.has("room") and g.squad.is_full():
		return false
	return true


## 抽普通不期而遇：按主流派加权（事件 lanes 含主流派 ×lane_event_w），need_trade 时只抽交易事件
func _pick_common(need_trade := false) -> String:
	var left := _common_left()
	if need_trade:
		left = left.filter(func(ev): return ev.get("trade", false))
	if left.is_empty():
		return ""
	var ml: String = g.guide.main_lane()
	var tot := 0.0
	var ws: Array = []
	for ev in left:
		var w: float = float(deck_cfg.get("lane_event_w", 2.0)) if (ev.get("lanes", []) as Array).has(ml) else 1.0   # 事件 lanes 用 docs/197 分类键
		ws.append(w)
		tot += w
	var r: float = g.rng.randf() * tot
	var id := str(left[-1].id)
	for k in left.size():
		r -= ws[k]
		if r <= 0.0:
			id = str(left[k].id)
			break
	used_common.append(id)
	return id


## 队友（队长除外）
func _mates() -> Array:
	return g.squad.ops.filter(func(o): return not o.is_leader)


## 能交出去的藏品（守望相助）：只收纯属性藏品（效果全是 stat，交出后整组属性来源一并撤掉）；结局 / 遭诅 / 升华不收
func _tradeable() -> Array:
	var out: Array = []
	for rid in g.relics:
		var r: Dictionary = g.rfx.db.get_relic(str(rid))
		if r.is_empty() or r.get("rarity", "") in ["结局", "遭诅古物", "升华"] or ROUTE_RELICS.has(str(rid)):
			continue
		if (r.get("effects", []) as Array).all(func(ef): return ef is Dictionary and ef.get("type", "stat") == "stat"):
			out.append(str(rid))
	return out


## 翻开第 i 张（progression.pick 在 choice_kind == "cross" 时转到这里）：先翻面，1.15 秒后兑现；批跑 / 无头立即兑现
func flip(i: int) -> void:
	if flipped >= 0 or i < 0 or i >= deck.size():
		return
	flipped = i
	flip_t = UM.now()
	var c: Dictionary = deck[i]
	if c.type == "fog":
		c.fog = true
		c.type = _fog_type()
		if c.type == "incident":
			c.event = _pick_common()
			if c.event == "":
				c.type = "wish"
	last_type = str(c.type)
	g.telemetry.nodes += 1   # 作战记录（docs/77）
	picks.append([slot, last_type, str(c.get("event", ""))])
	_log("flip %d %s %s" % [i, c.type, str(c.get("event", ""))])
	Sfx.play("relic", -4.0, 1.2, 0.0)
	if g.mode == g.Mode.BALANCE or DisplayServer.get_name() == "headless":
		_resolve()
	else:
		g.get_tree().create_timer(1.15, true, false, true).timeout.connect(_resolve)   # 起手 → 翻转 → 揭示（node_cards_ui）走完再兑现


func _fog_type() -> String:
	var W: Dictionary = deck_cfg.get("weights", {})
	var tot := 0.0
	var ws: Array = []
	for t in ["wish", "rest", "elite", "shop", "incident"]:
		var w: float = float(W.get(t, 0.0)) * (0.0 if t == "incident" and _common_left().is_empty() else 1.0)
		ws.append(w)
		tot += w
	var r: float = g.rng.randf() * tot
	for k in ws.size():
		r -= ws[k]
		if r <= 0.0:
			return ["wish", "rest", "elite", "shop", "incident"][k]
	return "wish"


## 兑现翻开的卡
func _resolve() -> void:
	if flipped < 0 or flipped >= deck.size() or g.choice_kind != "cross":
		return
	var c: Dictionary = deck[flipped]
	match str(c.type):
		"incident":
			incidents += 1
			open(str(c.event))
			return
		"rest":
			_open_rest()
			return
		"wish":
			open("wish_v2")   # 带走一件 / 付生命再拿一件（docs/184 §3）
			return
		"shop":
			g.shop_sys.open_trader()   # 原作语义：进一次商店（用户 10-28；docs/184 §3），买完关掉回战斗
			return
		"elite":
			squad_reward = "double" if c.get("double", false) else "lane"
			_spawn_elites()
	_close()


func _close() -> void:
	g.panel.visible = false
	g.state = g.S.PLAY
	g.combat.panel_grace()   # 路口卡兑现（得偿所愿 / 诡意行商 / 紧急作战）后关面板：0.8 秒保护
	g.check_pending()


## 安全的角落：「安全屋」三选一（原作安全屋的稍事休息 / 添加燃料 / 重整编制）
func _open_rest() -> void:
	opened_id = "rest"
	shown_id = "rest"
	var pk: float = Bal.v("crate/pack_pct", 0.25)   # 稍事休息改给应急补给（docs/203 §3：回血走补给这条路）
	var mh: float = float(deck_cfg.get("rest_maxhp", 0.05))
	var li: int = int(deck_cfg.get("rest_light", 15))
	var opts: Array = [
		{"kind": "event", "id": "rest:0", "name": "稍事休息", "desc": "补满护盾，身边落下 2 个应急补给（各回复 %d%% 最大生命），队长最大生命 +%d%%" % [int(pk * 100.0), int(mh * 100.0)], "icon": "e_event", "chips": [], "cat": "安全的角落", "col": NodeIcons.COLS.rest},
		{"kind": "event", "id": "rest:1", "name": "添加燃料", "desc": "灯火 +%d" % li, "icon": "e_event", "chips": [["灯火 +%d" % li, Color(0.95, 0.89, 0.76)]], "cat": "安全的角落", "col": NodeIcons.COLS.rest},
		{"kind": "event", "id": "rest:2", "name": "重整编制", "desc": "立即招募一名干员（编队已满时改为一次成长三选一）", "icon": "e_event", "chips": [], "cat": "安全的角落", "col": NodeIcons.COLS.rest},
	]
	g.panel_ui.show_choices("安全屋", opts, "event", "火光摇曳，食物冒着热气。好好休整，更大的浪涛还在前方。")


func _rest(k: int) -> void:
	match k:
		0:
			_max_hp(float(deck_cfg.get("rest_maxhp", 0.05)))
			g.shield = maxi(g.shield, g.shield_max)
			for k2 in 2:
				g.pickups.drop(g.ppos + Vector2(-36.0 + 72.0 * k2, 28.0), "pack", Bal.v("crate/pack_pct", 0.25))
		1:
			_light(float(deck_cfg.get("rest_light", 15)))
		2:
			_recruit()


## 紧急作战：精英小队（docs/161）。按阶段从 squad_pool 抽 squad_n 只高一阶的普通怪，从画面边缘同一侧成群出现；
## 生命 × squad_hp、伤害 × squad_dmg，全队共用一个词缀；e.squad 让画面画红色描边（world，开局写定、不变，不影响画法缓存签名）。
## 同屏上限（spawner.alive_cap，手机自动档第 2 级 65）放不下的成员记进 squad_pending，_tick_elites 有空位再刷。随机只用 g.rng_spawn
func _spawn_elites() -> void:
	elites.clear()
	squad_pending.clear()
	var tt: Array = deck_cfg.get("squad_t", [280, 520])
	var st: int = 0 if g.t < float(tt[0]) else (1 if g.t < float(tt[1]) else 2)
	var pools: Array = deck_cfg.get("squad_pool", [["tracer"]])
	var pool: Array = pools[mini(st, pools.size() - 1)]
	var ns: Array = deck_cfg.get("squad_n", [10])
	var n: int = int(ns[mini(st, ns.size() - 1)])
	squad_affix = "armor" if g.rng_spawn.randf() < 0.5 else "shield"
	var base: float = g.rng_spawn.randf() * TAU
	for k in n:
		var ang: float = base + g.rng_spawn.randf_range(-0.45, 0.45)
		var p: Vector2 = g.ppos + Vector2.from_angle(ang) * g.rng_spawn.randf_range(720.0, 840.0)
		squad_pending.append([str(pool[g.rng_spawn.randi() % pool.size()]), p - g.ppos])
	_squad_release()
	g.vfx.show_banner("紧急作战：精英小队来袭 · %s —— 全部击败获得宝箱与源石锭" % ("甲壳" if squad_affix == "armor" else "潮盾"))
	Sfx.play("roar", -3.0)


## 把推迟的小队成员按同屏余量放出来（出生点相对队长记，推迟后仍在画面边缘）
func _squad_release() -> void:
	if squad_pending.is_empty():
		return
	var cap: int = g.spawner.alive_cap()
	if cap <= 0:
		cap = g.spawner.max_alive()
	var room: int = cap - g.spawner.mob_count()
	if room <= 0:
		return
	g.spawner._norm = true
	while room > 0 and not squad_pending.is_empty():
		var it: Array = squad_pending.pop_front()
		var e: Dictionary = g.spawner.spawn_enemy(str(it[0]), g.ppos + it[1])
		e.cross_elite = true
		e["squad"] = true
		e.hp *= float(deck_cfg.get("squad_hp", 2.0))
		e.maxhp = e.hp
		e.dmg *= float(deck_cfg.get("squad_dmg", 1.3))
		e.dormant = false   # 收割者不休眠，直接追
		e["rush"] = float(deck_cfg.get("squad_rush", 2.2))   # 入场冲锋（同大群 rush：离队长 horde_rush_r 外 × 倍率，进圈恢复原速）；奠基者 / 巢涌者太慢，不冲要走二十多秒
		e.affix = squad_affix
		if squad_affix == "armor":
			e.def *= Bal.v("enemy/affix_armor", 0.75)
		else:
			e.shield_hp = e.maxhp * Bal.v("enemy/affix_shield", 0.30)
		elites.append(e)
		room -= 1
	g.spawner._norm = false


func _tick_elites() -> void:
	if elites.is_empty() and squad_pending.is_empty():
		return
	_squad_release()
	for e in elites:
		if not e.dead:
			elite_pos = e.pos
			return
	if not squad_pending.is_empty():
		return
	elites.clear()
	var rw := squad_reward
	squad_reward = ""
	if rw == "chal":
		chal.squad_done = true   # 委托里的小队：奖励交给委托结算（_tick_chal）
		g.vfx.show_banner("精英小队已全灭 —— 坚持到委托时间结束")
		return
	g.pickups.drop(elite_pos, "chest", 1.0, "squad")
	if rw == "double":
		g.pickups.drop(elite_pos + Vector2(36, 0), "chest", 1.0, "squad")
	wish_rare = true   # 这个宝箱的藏品三选一按稀有 / 核心加权（同得偿所愿，progression 读后清掉）
	if rw != "":
		lane_bias = g.guide.main_lane()   # 三选一里 2 件主流派（docs/184 §2.2）
	g.rfx.gain_ingots(int(deck_cfg.get("squad_ingots", 20)), "紧急作战 · ")
	g.vfx.show_banner("精英小队已全灭 —— 拾取宝箱")


## ---------- 事件 ----------
func _event_ok(ev: Dictionary) -> bool:
	if ev.has("requires_relic") and not g.relics.has(str(ev.requires_relic)):
		return false
	if ev.has("forbids_relic") and g.relics.has(str(ev.forbids_relic)):
		return false
	if ev.has("requires_flag") and not g.get(ev.requires_flag):
		return false
	if g.guide.core_locked() and _gives_core(ev):
		return false   # 选项写明给核心藏品的事件，核心解锁前不进卡组（docs/191 §6）
	return true


static func _gives_core(o) -> bool:
	if o is Dictionary:
		if str(o.get("rarity", "")) in ["核心", "升华"]:
			return true
		for v in o.values():
			if _gives_core(v):
				return true
	elif o is Array:
		for v in o:
			if _gives_core(v):
				return true
	return false


## 弹事件选项（C 版式）；count = false：同一件事件重弹下一屏（深蓝之心继续搜寻），图鉴不再记一次遇到
func open(ev_id: String, count := true) -> void:
	var ev: Dictionary = ev_by_id.get(ev_id, {})
	if ev.is_empty():
		_close()
		return
	opened_id = ev_id
	shown_id = ev_id
	_log("open " + ev_id)
	var opts: Array = []
	var ops_l: Array = _opts(ev)
	for i in ops_l.size():
		var op: Dictionary = ops_l[i]
		var oid := "%s:%d" % [ev_id, i]
		if searched.has(oid) or not _option_ok(op):
			continue
		var icon: String = "e_event"
		var chips: Array = _v2_chips(op)
		for o in op.get("ops", []):
			if o.has("chance"):
				chips.append(["%d%%" % int(round(float(o.chance) * 100.0)), Color(0.18, 0.72, 1.0)])
			if o.has("light"):
				chips.append(["灯火 %+d" % int(o.light), Color(0.95, 0.89, 0.76)])
			if o.has("relic"):
				icon = "relic_" + str(o.relic)
				chips.append(["得到藏品", Color(0.18, 0.72, 1.0)])
			if o.has("ingots") and not o.has("chance"):
				chips.append(["源石锭 %+d" % int(o.ingots), Color(0.18, 0.83, 0.63) if int(o.ingots) > 0 else Color(1.0, 0.45, 0.45)])
			if o.has("maxhp_pct"):
				chips.append(["最大生命 %+d%%" % int(round(float(o.maxhp_pct) * 100.0)), Color(0.55, 1.0, 0.6) if float(o.maxhp_pct) > 0.0 else Color(1.0, 0.45, 0.45)])
			if o.has("hp_pct"):
				chips.append(["生命 %+d%%" % int(round(float(o.hp_pct) * 100.0)), Color(1.0, 0.45, 0.45)])
		var opt := {"kind": "event", "id": oid, "name": op.label, "desc": op.desc, "icon": icon, "chips": chips,
			"cat": "事件  " + ev.name, "col": Color(0.55, 0.75, 1.0)}
		if int(op.get("cost", 0)) > g.ingots:
			opt.disabled = true
			opt.desc = str(op.desc) + "（源石锭不足）"
		else:
			var why := _blocked(op)
			if why != "":
				opt.disabled = true
				opt.desc = str(op.desc) + "（%s）" % why
		opts.append(opt)
	if opts.is_empty():
		opts.append({"kind": "event", "id": "%s:-1" % ev_id, "name": "离开", "desc": "什么都不做", "icon": "exit", "chips": [], "cat": "事件  " + ev.name, "col": Color(0.55, 0.75, 1.0)})
	EventBook.note_open(ev_id, opts.map(func(o): return str(o.id)).filter(func(x): return not x.ends_with(":-1")), count)
	if g.mode == g.Mode.PLAY:
		Cfg.save()
	g.panel_ui.show_choices(ev.name, opts, "event", str(ev.get("text", "")))


## 事件的选项
func _opts(ev: Dictionary) -> Array:
	return ev.get("options", [])


## 插画键：事件可指定 cg（敬奉火焰与引火之木共用一张），否则用事件 id
func cg_key() -> String:
	var id := opened_id if opened_id != "" else shown_id
	var ev: Dictionary = ev_by_id.get(id, {})
	return str(ev.get("cg", id)) if ev.has("cg") and str(ev.cg) != "" else id


## 兜底（10-29 用户卡死：狂徒妄念面板一个选项都没有）：事件面板显示着却没有可点的选项条时（choice_panel.check_event_panel 发现），
## 重建成只有「离开」的一屏，点了回到战斗；不重给奖励，所以就算之前某次选择只结算了一半也不会多拿
func recover_panel() -> void:
	var id := shown_id
	var ev: Dictionary = ev_by_id.get(id, {})
	var nm := str(ev.get("name", "事件"))
	push_warning("event panel had no options, rebuilt with leave only: %s" % id)
	_log("recover " + id)
	opened_id = id
	g.panel_ui.show_choices(nm, [{"kind": "event", "id": "%s:-1" % id, "name": "离开", "desc": "回到战斗", "icon": "exit", "chips": [], "cat": "事件  " + nm, "col": Color(0.55, 0.75, 1.0)}], "event", str(ev.get("text", "")), true)


## 选项灰掉的原因（docs/184 §2.1）：付生命的选项在生命 < 30% 时不可选；代价大于 20% 的（传统技术「两件都要」60%）门槛提到「代价 + 10%」，
## 付完至少留 10% 最大生命，不会直接倒下；need = 队友 / 可交藏品 / 后面还有路口
func _blocked(op: Dictionary) -> String:
	for o in op.get("ops", []):
		var cost: float = -float(o.get("hp_pct", 0.0))
		var need_k: float = maxf(0.3, cost + 0.1)
		if cost > 0.0 and g.hp < g.max_hp * need_k:
			return "生命低于 %d%% 时不可选" % int(round(need_k * 100.0))
	var nd: Dictionary = op.get("need", {})
	if nd.has("mate") and _mates().size() < int(nd.mate):
		return "需要至少 1 名队友"
	if nd.has("tradeable") and _tradeable().is_empty():
		return "没有可交出的藏品"
	if nd.has("later") and not _later_slot():
		return "之后没有路口了"
	if nd.has("room") and g.squad.is_full():
		return "编队已满"
	return ""


## 改版选项的代价 / 收益标签（红 = 代价）
const C_COST := Color(1.0, 0.45, 0.45)
const C_GAIN := Color(0.18, 0.72, 1.0)


func _v2_chips(op: Dictionary) -> Array:
	var out: Array = []
	for o in op.get("ops", []):
		if o.has("ingots_all"):
			out.append(["源石锭 -%d" % g.ingots, C_COST])
		if o.has("curse"):
			out.append(["遭诅藏品", C_COST])
		if o.has("away"):
			out.append(["队友暂离 %d 秒" % int(deck_cfg.get("away_t", 120)), C_COST])
		if o.has("leave"):
			out.append(["队友离队", C_COST])
		if o.has("threat"):
			out.append(["%d 秒强敌" % int(o.threat.get("t", 90)), C_COST])
		if o.has("kills"):
			out.append(["%d 秒内击败 %d" % [int(o.kills.get("t", 60)), int(o.kills.get("n", 150))], C_GAIN])
		if o.has("relic_lane"):
			out.append(["%s藏品" % str(o.relic_lane.get("rarity", "")), C_GAIN])
		if o.has("lane_choice"):
			out.append(["藏品三选一" + ("" if int(o.lane_choice) <= 1 else " ×%d" % int(o.lane_choice)), C_GAIN])
		if o.has("elite_up"):
			out.append(["精英化一级", C_GAIN])
		if o.has("trade"):
			out.append(["交换藏品", C_GAIN])
		if o.has("heal"):
			out.append(["回复 %d%%" % int(round(float(o.heal) * 100.0)), Color(0.55, 1.0, 0.6)])
		if o.has("stat"):
			out.append([str(o.stat.get("text", "")), C_COST if o.stat.get("cost", false) else C_GAIN])
	return out


## 选项还能不能给：给的藏品已经拥有且满级（抉择信物只有 1 级）就不出
func _option_ok(op: Dictionary) -> bool:
	for o in op.get("ops", []):
		if o.has("relic") and not g.progression.can_gain_relic(str(o.relic)):
			return false
	return true


## 选项生效。返回 true = 又弹了下一屏（深蓝之心继续搜寻 / 仪式 → 升华 / 园林 → 赞歌），调用方不要关面板
func pick(o: Dictionary) -> bool:
	var parts: PackedStringArray = str(o.id).split(":")
	var parent := opened_id
	opened_id = ""
	if parts[0] == "rest":
		_rest(int(parts[1]))
		return false
	if parts[0] == "sub":
		opened_id = parent
		_sub_pick(parts[1], parts[2] if parts.size() > 2 else "")
		if _next_sub():
			return true
		opened_id = ""
		return false
	var ev: Dictionary = ev_by_id.get(parts[0], {})
	var k := int(parts[1])
	if ev.is_empty() or k < 0:
		return false
	var op: Dictionary = _opts(ev)[k]
	if picks.size() > 0 and picks[-1].size() == 3:
		picks[-1].append(k)
	_log("pick %s:%d" % [parts[0], k])
	EventBook.note_pick("%s:%d" % [parts[0], k])
	if g.mode == g.Mode.PLAY:
		Cfg.save()
	var defer: Array = []   # 要再选一次的（选干员 / 交藏品）：其余效果先生效，再逐个弹选择屏
	for x in op.get("ops", []):
		if x.has("chance") and g.rng.randf() >= float(x.chance):
			g.vfx.add_text(g.ppos + Vector2(0, -90), "什么都没有发生", Color(0.7, 0.75, 0.8), 16)
			continue
		if x.has("away") or x.has("leave") or x.has("trade") or x.has("recruit_pick") or str(x.get("elite_up", "")) == "pick":
			defer.append(x)
			continue
		_apply_op(x)
	if not defer.is_empty():
		sub_ctx = {"queue": defer, "promoted": ""}
		opened_id = str(ev.id)
		if _next_sub():
			return true
		opened_id = ""
	if ev.get("repeat", false) and not op.get("end", false):
		searched.append(str(o.id))
		var mp: int = int(ev.get("max_picks", 0))   # 梦中之会：最多连选三项（docs/184 §4.2）
		if mp <= 0 or searched.filter(func(s): return str(s).begins_with(str(ev.id) + ":")).size() < mp:
			open(str(ev.id), false)
			return true
		return false
	var nxt: String = str(op.get("next", ev.get("next", "")))
	if nxt != "" and op.has("next_chance") and g.rng.randf() >= float(op.next_chance):
		# 设身处地「再喂喂看？」（原作 50%）：没成就到此为止；成了进的那一屏不再带这一项，只能再喂一次
		g.vfx.show_banner("它们没有再靠过来")
		return false
	if nxt != "" and ev_by_id.has(nxt):
		open(nxt)
		return true
	return false


func _apply_op(x: Dictionary) -> void:
	if x.has("light"):
		_light(float(x.light))
	if x.has("ingots"):
		if int(x.ingots) > 0:
			g.rfx.gain_ingots(int(x.ingots), "-")   # 熔铸后进熔铸池（docs/74）
		else:
			g.ingots = maxi(0, g.ingots + int(x.ingots))
	if x.has("maxhp_pct"):
		_max_hp(float(x.maxhp_pct))
	if x.has("hp_pct"):
		g.hp = maxf(1.0, g.hp + g.max_hp * float(x.hp_pct))
		g.vfx.add_text(g.ppos + Vector2(0, -70), "生命 %+d%%" % int(round(float(x.hp_pct) * 100.0)), Color(1.0, 0.45, 0.45), 16)
	if x.has("recruit"):
		_recruit()
	if x.has("gain"):
		g.rfx._on_gain(str(x.gain), x.get("args", {}))
	if x.has("relic"):
		g.progression.gain_relic(str(x.relic), "event")
	if x.has("relic_choice"):
		g.pending_chests += int(x.relic_choice)
		for k in int(x.relic_choice):
			g.chest_src.append("event")
	# ---- 事件改版（docs/184 §2.3–§2.4、§4.2）
	if x.has("heal"):
		g.combat.heal(g.max_hp * float(x.heal), "事件")
		g.vfx.add_text(g.ppos + Vector2(0, -70), "生命 +%d%%" % int(round(float(x.heal) * 100.0)), Color(0.55, 1.0, 0.6), 16)
	if x.has("ingots_all"):
		g.ingots = 0
	if x.has("relic_lane"):
		var a: Dictionary = x.relic_lane
		for k in int(a.get("n", 1)):
			_gain_lane_relic(str(a.get("rarity", "")), a.get("lanes", []))
	if x.has("lane_choice"):
		g.pending_chests += int(x.lane_choice)
		for k in int(x.lane_choice):
			g.chest_src.append("event")
		lane_bias = g.guide.main_lane()
		if x.get("rare", false):
			wish_rare = true
	if x.has("curse"):
		for k in int(x.curse):
			_gain_curse()
	if x.has("xp"):
		_ev_n += 1
		g.rfx._apply_stat("xp_gain", "mult", 1.0 + float(x.xp), "event:xp%d" % _ev_n, "")
		g.vfx.show_banner("整局经验 +%d%%" % int(round(float(x.xp) * 100.0)))
	if x.has("shield"):
		_ev_n += 1
		g.rfx._apply_stat("shield_max", "add", float(x.shield), "event:sh%d" % _ev_n, "")
		g.shield = mini(g.shield + int(x.shield), g.shield_max)
	if x.has("sp_gain"):
		_ev_n += 1
		g.rfx._apply_stat("sp_gain", "mult", 1.0 + float(x.sp_gain), "event:sp%d" % _ev_n, "")
		g.vfx.show_banner("全队技力回复 +%d%%" % int(round(float(x.sp_gain) * 100.0)))
	if x.has("stat"):
		# 通用属性改动（docs/184 §10，10-29 用户审定）：{key, mult, text, cost?, v?}；key 是 stat_defs 里的属性（elite_dmg / enemy_ranged_cd / nerve_taken …），
		# text 是卡面与横幅写法，cost = true 时标红、算代价；v = 机器人估值（V）
		var st: Dictionary = x.stat
		_ev_n += 1
		g.rfx._apply_stat(str(st.key), "mult", float(st.get("mult", 1.0)), "event:st%d" % _ev_n, "")
		g.vfx.show_banner(str(st.get("text", "")))
	if str(x.get("elite_up", "")) == "lead":
		_elite_up(g.ch)
	if x.has("threat"):
		_start_threat(x.threat)
	if x.has("kills"):
		chal = {"kind": "kills", "name": str(x.kills.get("name", "委托")), "end_t": g.t + float(x.kills.get("t", 60)), "n": int(x.kills.get("n", 150)), "k0": g.kills, "win": x.kills.get("win", [])}
		g.vfx.show_banner("委托：%s —— %d 秒内击败 %d 名敌人" % [chal.name, int(x.kills.get("t", 60)), chal.n])
	if x.has("trouble"):
		trouble = true
		g.vfx.show_banner("教士们记住了你 —— 下一个路口会有一场紧急作战")
	if x.has("squad_now"):
		squad_reward = "lane"
		_spawn_elites()


## 主流派藏品一件（docs/184 §2.2）：lanes 给定时从这些流派抽，否则主流派；rarity 限定稀有度；对口池空了退回同稀有度全池。
## 按稀有度加权（基础 60 / 稀有 39 / 核心 18，同得偿所愿 ×1.5），不出升华 / 遭诅 / 结局；随机只用 g.rng
func _gain_lane_relic(rarity: String, lanes: Array) -> void:
	var want: Array = lanes if not lanes.is_empty() else [g.guide.main_lane()]
	var base: Array = g.rfx.db.implemented().filter(func(r): return not g.relics.has(r.id) and r.rarity in ["基础", "稀有", "核心"] and (rarity == "" or r.rarity == rarity) and g.rfx.can_offer(r, false) and g.progression.can_gain_relic(r.id))
	var cands: Array = base.filter(func(r): return want.has(r.lane))
	if cands.is_empty():
		cands = base
	if cands.is_empty():
		if rarity == "核心":
			_gain_lane_relic("稀有", lanes)   # 核心还没解锁（docs/191 §6）：退一档给稀有
			return
		g.rfx.gain_ingots(12, "暂无可得藏品 · ")
		return
	var tot := 0.0
	var ws: Array = []
	for r in cands:
		var w: float = {"基础": 60.0, "稀有": 39.0, "核心": 18.0}.get(r.rarity, 10.0)
		ws.append(w)
		tot += w
	var u: float = g.rng.randf() * tot
	var pick_id: String = str(cands[-1].id)
	for k in cands.size():
		u -= ws[k]
		if u <= 0.0:
			pick_id = str(cands[k].id)
			break
	g.progression.gain_relic(pick_id, "event")
	g.vfx.show_banner("获得藏品：%s" % g.rfx.db.get_relic(pick_id).name)


## 遭诅藏品一件（三选一池不出遭诅，这里直接从遭诅池抽）
func _gain_curse() -> void:
	var cands: Array = g.rfx.db.implemented().filter(func(r): return r.rarity == "遭诅古物" and not g.relics.has(r.id) and r.get("source", "any") == "any" and g.progression.can_gain_relic(r.id))
	if cands.is_empty():
		return
	var rid: String = str(cands[g.rng.randi() % cands.size()].id)
	g.progression.gain_relic(rid, "event")
	g.vfx.show_banner("获得遭诅藏品：%s" % g.rfx.db.get_relic(rid).name)


## 一名干员立即精英化一级（docs/184 §5.2）：连推到下一个精英阶段，中间节点一并给、不看节点条件；
## 分支节点按干员的固定路线（bot_route）、精英化选项取第一项；已精英二改为两次成长三选一
func _elite_up(o) -> void:
	if o == null:
		return
	if o.elite >= 2:
		g.pending_levelups += 2
		g.vfx.show_banner("%s 已是精英二 —— 改为两次成长三选一" % o.display_name())
		return
	var target: int = o.elite + 1
	for guard in 8:
		if o.elite >= target:
			break
		var n: Dictionary = o.next_node()
		if n.is_empty():
			break
		var ch := ""
		if o.needs_route():
			ch = o.bot_route(n)
		elif n.get("type", "") == "elite":
			var chs: Dictionary = o.elite_choices(n)
			if not chs.is_empty():
				ch = str(chs.keys()[0])
		var p0: int = o.prog
		o.advance(ch)
		if o.prog == p0:
			break
	if o.elite >= target:
		g.vfx.show_banner("%s 晋升至精英%s" % [o.display_name(), ["", "一", "二"][clampi(o.elite, 0, 2)]])
		if o.pos != Vector2.INF:
			g.vfx.promote_burst(o.pos, true)
	else:
		g.pending_levelups += 1


## ---------- 要再选一次的选项（选干员 / 交藏品，docs/184 §4.2） ----------
## 逐个弹选择屏；返回 true = 弹了一屏
func _next_sub() -> bool:
	var q: Array = sub_ctx.get("queue", [])
	while not q.is_empty():
		var x: Dictionary = q[0]
		var opts: Array = []
		var title := ""
		var sub := ""
		var cat := "事件  " + str(ev_by_id.get(opened_id, {}).get("name", ""))
		if str(x.get("elite_up", "")) == "pick":
			title = "选择精英化的干员"
			sub = "该干员立即进到下一个精英阶段。"
			var pool: Array = g.squad.ops.duplicate()
			if q.size() > 1 and q[1].has("leave") and _mates().size() == 1:
				pool = pool.filter(func(o): return o.is_leader)   # 只有一名队友且它要撤离：只能给队长
			for o in pool:
				var st: String = ["精英零", "精英一", "精英二"][clampi(o.elite, 0, 2)]
				opts.append({"kind": "event", "id": "sub:elite:" + str(o.id), "name": o.display_name(), "desc": "当前%s，成长节点 %d/%d" % [st, o.prog, o.progression().size()] + ("（已精英二：改为两次成长三选一）" if o.elite >= 2 else ""), "icon": "e_event", "chips": [], "cat": cat, "col": Color(0.55, 0.75, 1.0)})
		elif x.has("leave") or x.has("away"):
			var lv: bool = x.has("leave")
			title = "选择离队的队友" if lv else "选择运送物资的队友"
			sub = "离开编队，之后可再招募。" if lv else "离队 %d 秒，归队时精英化一级并带回一件藏品。" % int(deck_cfg.get("away_t", 120))
			for o in _mates():
				if str(o.id) == str(sub_ctx.get("promoted", "")):
					continue
				opts.append({"kind": "event", "id": "sub:%s:%s" % ["leave" if lv else "away", str(o.id)], "name": o.display_name(), "desc": "%s，成长节点 %d/%d" % [["精英零", "精英一", "精英二"][clampi(o.elite, 0, 2)], o.prog, o.progression().size()], "icon": "e_event", "chips": [], "cat": cat, "col": Color(0.55, 0.75, 1.0)})
		elif x.has("recruit_pick"):
			# 招募：recruit_pick = 2 → 随机两个职业里选（g.rng，主流派吃得到的职业先抽到的机会 ×2）；0 → 全部可招募干员里选
			title = "招募干员"
			var cards: Array = g.progression.recruit_cards()
			var nk: int = int(x.recruit_pick)
			if nk > 0 and not cards.is_empty():
				var classes: Array = []
				for c in cards:
					if not classes.has(str(c.cls)):
						classes.append(str(c.cls))
				var ml: String = g.guide.main_lane()
				var keep: Array = []
				var cw: Array = classes.map(func(cl): return 2.0 if (ml == "melee" and MELEE_CLS.has(cl)) or (ml == "multi" and not MELEE_CLS.has(cl)) else 1.0)
				for k in mini(nk, classes.size()):
					var tot := 0.0
					for w in cw:
						tot += float(w)
					var u: float = g.rng.randf() * tot
					var ci := 0
					for j in classes.size():
						u -= float(cw[j])
						if u <= 0.0:
							ci = j
							break
					keep.append(classes[ci])
					classes.remove_at(ci)
					cw.remove_at(ci)
				cards = cards.filter(func(c): return keep.has(str(c.cls)))
				sub = "职业：%s。" % " / ".join(keep)
			for c in cards:
				opts.append({"kind": "event", "id": "sub:recruit:" + str(c.id), "name": "%s  %s" % [c.name, c.cls], "desc": str(c.desc), "icon": "e_event", "chips": [], "cat": cat, "col": Color(0.55, 0.9, 0.55)})
		elif x.has("trade"):
			if sub_ctx.has("offer"):
				title = "选择换来的藏品"
				sub = "选一件带走。"
				for rid in sub_ctx.offer:
					opts.append({"kind": "event", "id": "sub:take:" + str(rid), "name": "【%s】%s" % [g.rfx.db.lane_name(rid), g.rfx.display_name(rid)], "desc": g.rfx.display_desc(rid), "icon": "relic_" + str(rid), "chips": [], "cat": cat, "col": Color(0.55, 0.75, 1.0)})
			else:
				title = "选择交出的藏品"
				sub = "只收纯属性藏品；换来的藏品稀有度不低于它。"
				for rid in _tradeable():
					opts.append({"kind": "event", "id": "sub:give:" + str(rid), "name": "【%s】%s" % [g.rfx.db.lane_name(rid), g.rfx.display_name(rid)], "desc": g.rfx.display_desc(rid), "icon": "relic_" + str(rid), "chips": [["交出", C_COST]], "cat": cat, "col": Color(0.55, 0.75, 1.0)})
		if opts.is_empty():
			q.pop_front()   # 没有可选对象（队友已不在等）：跳过这一步
			sub_ctx.erase("offer")
			continue
		g.panel_ui.show_choices(title, opts, "event", sub)
		return true
	sub_ctx = {}
	return false


func _sub_pick(what: String, arg: String) -> void:
	var q: Array = sub_ctx.get("queue", [])
	if q.is_empty():
		return
	var x: Dictionary = q[0]
	match what:
		"elite":
			sub_ctx.promoted = arg
			_elite_up(g.squad.get_op(arg))
			q.pop_front()
		"leave":
			var o = g.squad.get_op(arg)
			if o != null and not o.is_leader:
				var nm: String = o.display_name()
				g.squad.remove(arg)
				g.stats.remove_scope("op:" + arg)
				g.sync_stats()
				g.vfx.show_banner("「%s」随先遣小队撤离" % nm)
			q.pop_front()
		"away":
			var o = g.squad.get_op(arg)
			if o != null and not o.is_leader:
				var sec: float = float(deck_cfg.get("away_t", 120))
				away.append({"id": arg, "name": o.display_name(), "prog": int(o.prog), "route": str(o.route), "back_t": g.t + sec, "reward": (x.away as Dictionary).get("reward", [])})
				g.squad.remove(arg)
				g.stats.remove_scope("op:" + arg)
				g.sync_stats()
				g.vfx.show_banner("「%s」前往安全屋 —— %d 秒后归队" % [away[-1].name, int(sec)])
			q.pop_front()
		"recruit":
			var nop = g.squad.add(arg)
			if nop != null:
				g.vfx.show_banner("「%s」加入编队" % nop.display_name())
				g.vfx.promote_burst(nop.pos, false)
			q.pop_front()
		"give":
			var rk: int = ["基础", "稀有", "核心"].find(str(g.rfx.db.get_relic(arg).get("rarity", "基础")))
			_lose_relic(arg)
			sub_ctx.offer = _trade_offer(maxi(0, rk))
		"take":
			g.progression.gain_relic(arg)
			g.vfx.show_banner("获得藏品：%s" % g.rfx.db.get_relic(arg).name)
			sub_ctx.erase("offer")
			q.pop_front()


## 交出一件纯属性藏品：撤掉它的属性来源与等级（_tradeable 只收效果全是 stat 的藏品）
func _lose_relic(rid: String) -> void:
	g.relics.erase(rid)
	g.rfx.lv.erase(rid)
	g.stats.remove_source("relic:" + rid)
	g.sync_stats()
	g.rfx.refresh_relic_count()
	g.vfx.show_banner("交出藏品：%s" % g.rfx.db.get_relic(rid).name)


## 换来的三件：主流派里稀有度 ≥ 交出那件；不够 3 件用全池同条件补
func _trade_offer(min_rank: int) -> Array:
	var ranks := ["基础", "稀有", "核心"]
	var ml: String = g.guide.main_lane()
	var ok: Array = g.guide.relic_pool_ids().filter(func(rid): return ranks.find(str(g.RL[rid].rarity)) >= min_rank and not g.relics.has(rid))
	var lane: Array = ok.filter(func(rid): return str(g.RL[rid].get("lane", "")) == ml)
	var out: Array = lane.slice(0, 3)
	for rid in ok:
		if out.size() >= 3:
			break
		if not out.has(rid):
			out.append(rid)
	return out


## ---------- 委托（郁金香的委托：限时强敌 / 击杀数，docs/184 §4.2） ----------
func _start_threat(a: Dictionary) -> void:
	var m: float = 1.0 + float(a.get("mult", 0.3))
	g.stats.add(&"enemy_hp", "mult", m, "event:threat", "")
	g.stats.add(&"enemy_dmg", "mult", m, "event:threat", "")
	g.sync_stats()
	chal = {"kind": "threat", "name": str(a.get("name", "委托")), "end_t": g.t + float(a.get("t", 90)), "t": float(a.get("t", 90)), "win": a.get("win", []), "squad": bool(a.get("squad", false)), "squad_done": false}
	g.vfx.show_banner("委托：%s —— 接下来 %d 秒敌人生命与伤害 +%d%%" % [chal.name, int(a.get("t", 90)), int(round((m - 1.0) * 100.0))])
	if chal.squad:
		squad_reward = "chal"
		_spawn_elites()


func _lift_threat() -> void:
	if not chal.get("lifted", false) and chal.get("kind", "") == "threat":
		chal.lifted = true
		g.stats.remove_source("event:threat")
		g.sync_stats()


## 委托结算：限时强敌到点（或中 Boss / 最终 Boss 登场提前结束）按完成算；带小队的要小队全灭，到点后再给 chal_grace 秒；
## 击杀委托在时限内达标即完成。失败只是没有奖励（用户 10-27）
func _tick_chal() -> void:
	if chal.is_empty():
		return
	var boss_now: bool = g.spawner.boss_alive() or g.final_boss != null
	var ok := false
	var fail := false
	match str(chal.kind):
		"threat":
			if g.t >= float(chal.end_t) or boss_now:
				_lift_threat()
				if not chal.squad or chal.squad_done or boss_now:
					ok = true
				elif g.t >= float(chal.end_t) + float(deck_cfg.get("chal_grace", 30)):
					fail = true
		"kills":
			if g.kills - int(chal.k0) >= int(chal.n):
				ok = true
			elif g.t >= float(chal.end_t) or boss_now:
				fail = true
	if not ok and not fail:
		return
	var c := chal
	chal = {}
	if squad_reward == "chal":
		squad_reward = "lane"   # 委托结束时小队还没打完：剩下的照紧急作战给宝箱
	if ok:
		g.vfx.show_banner("委托完成：%s" % c.name)
		for x in c.get("win", []):
			_apply_op(x)
		g.check_pending()
	else:
		g.vfx.show_banner("委托未完成：%s" % c.name)


## 暂离的队友到点归队：按离队时的成长节点数重建（同换人继承，不重播精英化演出），再给归队奖励
func _tick_away() -> void:
	for a in away.duplicate():
		if g.t < float(a.back_t):
			continue
		away.erase(a)
		var o = g.squad.add(str(a.id), false)
		if o == null:
			g.vfx.show_banner("编队已满，「%s」留在安全屋 —— 物资照常送到" % a.name)
		else:
			if str(a.route) != "":
				o.route = str(a.route)
			var sq0: int = g.show_queue.size()
			for k in int(a.prog):
				var n: Dictionary = o.next_node()
				if n.is_empty():
					break
				var chs: Dictionary = o.elite_choices(n) if n.get("type", "") == "elite" else {}
				var p0: int = o.prog
				o.advance(str(chs.keys()[0]) if not chs.is_empty() else "")
				if o.prog == p0:
					break
			if g.show_queue.size() > sq0:
				g.show_queue.resize(sq0)
			g.sync_stats()
			o.arrive_t = o.ARRIVE_WAIT
			o.play_entry(o.ARRIVE_FALL)
			g.vfx.show_banner("「%s」带着物资归队" % a.name)
		for x in a.get("reward", []):
			if str(x.get("elite_up", "")) == "self":
				if o != null:
					_elite_up(o)
				else:
					g.pending_levelups += 1
			else:
				_apply_op(x)


## 状态栏（hud_bars.status_items）：委托倒计时、暂离队友
func status_items() -> Array:
	var out: Array = []
	if not chal.is_empty():
		if chal.kind == "threat":
			var left: float = maxf(0.0, float(chal.end_t) - g.t)
			out.append(["委托 · 强敌 %d 秒" % int(ceil(left)) if left > 0.0 else "委托 · 击败精英小队", Color(1.0, 0.5, 0.5), clampf(left / maxf(1.0, float(chal.t)), 0.0, 1.0)])
		else:
			out.append(["委托 · 击败 %d/%d" % [mini(g.kills - int(chal.k0), int(chal.n)), int(chal.n)], Color(1.0, 0.82, 0.4), clampf((float(chal.end_t) - g.t) / 60.0, 0.0, 1.0)])
	for a in away:
		out.append(["%s 暂离 %d 秒" % [a.name, int(ceil(float(a.back_t) - g.t))], Color(0.6, 0.85, 1.0), -1.0])
	return out


## 灯火增减：只当普通奖励用（docs/154：结局线不拿灯火当门槛 / 代价）；付灯火最低降到 10
func _light(v: float) -> void:
	g.lamp = minf(g.lamp, maxf(10.0, g.lamp + v)) if v < 0.0 else minf(g.lamp_cap, g.lamp + v)
	g.vfx.add_text(g.ppos + Vector2(0, -90), "灯火 %+d" % int(v), Color(1.0, 0.8, 0.45), 16)


## 队长最大生命按比例增减（事件来源，走 stats，叠乘）
func _max_hp(pct: float) -> void:
	BossBench.rb("maxhp", [pct])   # Boss 单场测试台录制（docs/170）
	BossBench.re()
	_mh_n += 1
	g.rfx._apply_stat("max_hp", "mult", 1.0 + pct, "event:%d" % _mh_n, "")   # 每次一个来源名，叠乘
	g.hp = minf(g.hp, g.max_hp)
	g.vfx.add_text(g.ppos + Vector2(0, -110), "最大生命 %+d%%" % int(round(pct * 100.0)), Color(0.55, 1.0, 0.6) if pct > 0.0 else Color(1.0, 0.45, 0.45), 16)


## 立即招募一名干员（随机，g.rng）；编队已满改为一次成长三选一
func _recruit() -> void:
	var cards: Array = g.progression.recruit_cards()
	if cards.is_empty():
		g.pending_levelups += 1
		g.vfx.show_banner("编队已满，改为一次成长三选一")
		return
	var o = g.squad.add(str(cards[g.rng.randi() % cards.size()].id))
	if o == null:
		g.pending_levelups += 1
		return
	g.vfx.show_banner("「%s」加入编队" % o.display_name())
	g.vfx.promote_burst(o.pos, false)


## ---------- 机器人 ----------
## 机器人走哪条线：--route 指定；否则按 seed 轮换（批跑四个结局都有样本）
func bot_route() -> String:
	if route != "" and route != "rand":
		return route
	return ["knight", "heart", "memory", "none"][absi(int(g.rng.seed)) % 4]


## 机器人在路口 / 事件面板选哪一项（不取随机数）
func bot_choice() -> int:
	var want := bot_route()
	var b := _bot_v2(want)
	if b >= 0:
		return b
	if g.choice_kind == "cross":
		var entry: String = {"knight": "madness", "heart": "opening", "memory": "opening"}.get(want, "")
		var hp_k: float = g.hp / maxf(1.0, g.max_hp)
		var order: Array = ["rest", "wish", "elite", "shop", "fog"] if hp_k < 0.5 else ["wish", "elite", "shop", "rest", "fog"]
		var best := -1
		var best_r := 99
		for i in deck.size():
			var c: Dictionary = deck[i]
			if c.get("must", false):
				if (cross_done == 1 and str(c.event) == entry) or cross_done == 2:
					return i
				continue
			var r: int = order.find(str(c.type))
			if r < 0:
				r = 50   # 普通不期而遇
			if r < best_r:
				best_r = r
				best = i
		return maxi(0, best)
	var eid: String = str(g.choices[0].id).split(":")[0] if not g.choices.is_empty() else ""
	var want_k := -1
	match eid:
		"madness":
			want_k = 0 if want == "knight" else 3
		"opening":
			want_k = 0 if want == "heart" else (1 if want == "memory" else 3)
		"knight_stay":
			want_k = 1
		"heart":
			for k in [1, 3, 5]:   # 科研区、生活区，再去园林
				if _choice_index("heart:%d" % k) >= 0 and not g.choices[_choice_index("heart:%d" % k)].get("disabled", false):
					return _choice_index("heart:%d" % k)
			want_k = 5
		"ritual":
			want_k = 0
		"ascend":
			want_k = absi(int(g.rng.seed / 4)) % 3
		"rest":
			want_k = 0 if g.hp < g.max_hp * 0.6 else (1 if g.lamp < 50.0 else 2)
	if want_k >= 0:
		var ci := _choice_index("%s:%d" % [eid, want_k])
		if ci >= 0:
			return ci
	for i in g.choices.size():
		if not g.choices[i].get("disabled", false):
			return i
	return 0


## 改版机器人（docs/184 §7.2）：按 V 口径粗估每张卡 / 每个选项的净值取最大；结局线卡与结局事件仍按 bot_route 走（返回 -1 交给旧逻辑）。
## 稳妥档（bot/event_greedy = 0）只选不带代价的选项。不取随机数
func _bot_v2(want: String) -> int:
	var greedy: bool = Bal.vi("bot/event_greedy", 1) == 1
	if g.choice_kind == "cross":
		if deck.any(func(c): return c.get("must", false)):
			return -1
		var best := 0
		var bv := -99.0
		for i in deck.size():
			var v := _card_value(deck[i], greedy)
			if v > bv:
				bv = v
				best = i
		return best
	if g.choices.is_empty():
		return -1
	var id0: String = str(g.choices[0].get("id", ""))
	var parts: PackedStringArray = id0.split(":")
	if parts[0] == "sub":
		return _bot_sub(parts[1])
	if not ev_by_id.has(parts[0]) or ev_by_id[parts[0]].get("pool", "") not in ["common", "card"]:
		return -1
	var ev: Dictionary = ev_by_id[parts[0]]
	var best_i := -1
	var bv2 := -99.0
	for i in g.choices.size():
		var c: Dictionary = g.choices[i]
		if c.get("disabled", false):
			continue
		var k: int = int(str(c.id).split(":")[1])
		if k < 0:
			continue
		var op: Dictionary = _opts(ev)[k]
		var v := _opt_value(op)
		if not greedy and _opt_cost(op):
			v -= 10.0
		if v > bv2:
			bv2 = v
			best_i = i
	return best_i


func _card_value(c: Dictionary, greedy: bool) -> float:
	var hp_k: float = g.hp / maxf(1.0, g.max_hp)
	match str(c.type):
		"rest":
			return 3.0 if hp_k < 0.5 else 1.0
		"shop":
			return 0.3 + minf(float(g.ingots) / 14.0, 3.0) * 0.8   # 一次商店：值多少看手里的源石锭（藏品基价 14）
		"wish":
			return 2.2
		"elite":
			return (2.5 if hp_k > 0.6 else 0.0) if greedy else 0.5
		"fog":
			return 1.5
		"incident":
			var ev: Dictionary = ev_by_id.get(str(c.get("event", "")), {})
			var best := 0.5
			for op in _opts(ev):
				if _blocked(op) == "" and int(op.get("cost", 0)) <= g.ingots and (greedy or not _opt_cost(op)):
					best = maxf(best, _opt_value(op))
			return best
	return 0.0


## 选项有没有代价（稳妥档机器人用）
func _opt_cost(op: Dictionary) -> bool:
	for x in op.get("ops", []):
		if float(x.get("hp_pct", 0.0)) < 0.0 or float(x.get("maxhp_pct", 0.0)) < 0.0 or int(x.get("ingots", 0)) < 0:
			return true
		if x.has("stat") and x.stat.get("cost", false):
			return true
		for k in ["curse", "away", "leave", "threat", "ingots_all", "trouble", "squad_now"]:
			if x.has(k):
				return true
	return false


## V 口径（docs/184 §2.4）：1 V ≈ 基础藏品 ≈ 源石锭 10 ≈ 最大生命 5%
func _opt_value(op: Dictionary) -> float:
	var hp_k: float = g.hp / maxf(1.0, g.max_hp)
	var v := 0.0
	for x in op.get("ops", []):
		var p: float = float(x.get("chance", 1.0))
		var s := 0.0
		if x.has("ingots"):
			s += float(x.ingots) / 10.0 * (0.4 if g.merchant_idx >= g.MERCHANT_TIMES.size() else 1.0)
		if x.has("hp_pct"):
			var d: float = float(x.hp_pct)
			s += d * 2.5 if hp_k + d > 0.4 else -5.0
		if x.has("maxhp_pct"):
			s += float(x.maxhp_pct) * 20.0
		if x.has("light"):
			s += float(x.light) / 20.0
		if x.has("heal"):
			s += float(x.heal) * (4.0 if hp_k < 0.7 else 1.0)
		if x.has("relic_lane"):
			s += {"核心": 3.0, "稀有": 2.0}.get(str(x.relic_lane.get("rarity", "")), 1.5) * int(x.relic_lane.get("n", 1))
		if x.has("lane_choice"):
			s += 2.0 * int(x.lane_choice)
		if x.has("gain") and str(x.gain) == "random_relic":
			s += 1.2
		if x.has("curse"):
			s -= 1.5
		if x.has("recruit") or x.has("recruit_pick"):
			s += 1.0 if g.squad.is_full() else 3.0
		if x.has("sp_gain"):
			s += 1.5
		if x.has("stat"):
			s += float(x.stat.get("v", -1.0 if x.stat.get("cost", false) else 1.0))
		if x.has("shield"):
			s += 0.6 * float(x.shield)
		if x.has("elite_up"):
			s += 3.0
		if x.has("away"):
			s += 3.0
		if x.has("leave"):
			s -= 3.0
		if x.has("trade"):
			s += 1.5
		if x.has("xp"):
			s += 2.5 if g.t < 200.0 else 1.0
		if x.has("ingots_all"):
			s -= float(g.ingots) / 10.0
		if x.has("threat"):
			var risk: float = -1.5 * float(x.threat.get("mult", 0.3)) / 0.3
			if hp_k < 0.6:
				risk = -5.0
			var win := 0.0
			for y in x.threat.get("win", []):
				win += _opt_value({"ops": [y]})
			s += risk + 0.8 * win
		if x.has("kills"):
			var win2 := 0.0
			for y in x.kills.get("win", []):
				win2 += _opt_value({"ops": [y]})
			s += 0.8 * win2
		if x.has("trouble"):
			s += 1.5
		if x.has("squad_now"):
			s += 2.0 if hp_k > 0.6 else -3.0
		v += s * p
	return v


## 选干员 / 交藏品：精英化给进度最多的未精二干员，离队 / 暂离给进度最少的队友，交出最低稀有度的藏品、拿第一件
func _bot_sub(what: String) -> int:
	var best := 0
	var bv := -99.0
	for i in g.choices.size():
		var parts: PackedStringArray = str(g.choices[i].id).split(":")
		var arg: String = parts[2] if parts.size() > 2 else ""
		var v := 0.0
		match what:
			"elite":
				var o = g.squad.get_op(arg)
				v = (float(o.prog) - (20.0 if o.elite >= 2 else 0.0)) if o != null else -50.0
			"leave", "away":
				var o2 = g.squad.get_op(arg)
				v = -float(o2.prog) if o2 != null else -50.0
			"give":
				v = -float(["基础", "稀有", "核心"].find(str(g.RL.get(arg, {}).get("rarity", "基础"))))
			"take", "recruit":
				v = -float(i)
		if v > bv:
			bv = v
			best = i
	return best


func _choice_index(id: String) -> int:
	for i in g.choices.size():
		if str(g.choices[i].get("id", "")) == id:
			return i
	return -1


## 自动测试日志：ENDEV <动作> ...
func _log(what: String) -> void:
	if g.mode != g.Mode.PLAY:
		print("ENDEV %s t=%.1f cur=%s relics=%s" % [what, g.t, cur, str(g.relics.filter(func(r): return ROUTE_RELICS.has(str(r))))])


func is_route_relic(id: String) -> bool:
	return ROUTE_RELICS.has(id)


## 藏品栏上限开着时（relic/carry_cap ≥ 0）为结局线留位：还没翻的路口各 1 格；骑士在场（含已入潮）再留 1 格给退行的罗辛南特
func reserved_relic_slots() -> int:
	var n := 0
	if enabled and lines_on and not frozen:
		n += maxi(0, 2 - cross_done)
	if (g.knight.alive or g.knight.submerged) and not g.rfx.has_relic("rocinante"):
		n += 1
	return n


## ---------- 结局 ----------
func note_relic(_id: String) -> void:
	pass


## 获得藏品后重算结局
func on_relic(_id: String) -> void:
	recalc()


func _satisfied(e: Dictionary) -> bool:
	if not e.has("requires"):
		return false
	var req: Dictionary = e.requires
	if req.has("relic") and not g.relics.has(str(req.relic)):
		return false
	if req.has("any_relic") and not (req.any_relic as Array).any(func(r): return g.relics.has(str(r))):
		return false
	if req.has("relic_lv") and int(g.rfx.lv.get(str(req.relic_lv[0]), 0)) < int(req.relic_lv[1]):
		return false
	if req.has("flag") and not g.get(req.flag):
		return false
	for f in e.get("forbids", []):
		if g.relics.has(str(f)):
			return false
	return true


## 满足条件的结局里取 priority 最高的；都不满足 = 结局一
func judge() -> String:
	var best := "standard"
	var bp := -1
	for eid in endings:
		if _satisfied(endings[eid]) and int(endings[eid].get("priority", 0)) > bp:
			best = eid
			bp = int(endings[eid].get("priority", 0))
	return best


func recalc() -> void:
	if frozen:
		return   # 最终 Boss 登场后结局不再改写
	var best := judge()
	if best != cur:
		cur = best
		g.ending = cur
		g.vfx.show_banner("探索的走向改变了：%s" % endings[cur].name)
		Sfx.play("roar", -6.0, 0.5, 0.0)
		if warned_final:
			g.vfx.show_banner(endings[cur].get("omen", "终局将至"))


## 9:00 终局预告
func tick_final_warning() -> void:
	if not warned_final and g.t >= 540.0:
		warned_final = true
		g.vfx.show_banner(endings.get(cur, {}).get("omen", "终局将至"))
		Sfx.play("roar", -4.0, 0.6, 0.0)


func cur_name() -> String:
	return endings.get(cur, {}).get("name", "结局一")


func cur_col() -> Color:
	var c = endings.get(cur, {}).get("col", [0.8, 0.6, 1.0])
	return Color(c[0], c[1], c[2])


func ending_col(eid: String) -> Color:
	var c = endings.get(eid, {}).get("col", [0.8, 0.6, 1.0])
	return Color(c[0], c[1], c[2])


## 结算后日谈：结局四按升华选的信物分三版（docs/154 §4）
func epilogue() -> String:
	var e: Dictionary = endings.get(g.ending, {})
	var by: Dictionary = e.get("epilogue_by_relic", {})
	for rid in by:
		if g.relics.has(str(rid)):
			return str(by[rid])
	return str(e.get("gallery", {}).get("epilogue", ""))


## 通关：记录已达成结局（解锁其它结局的事件）
func on_win() -> void:
	if g.mode != g.Mode.PLAY:
		return
	if not Cfg.endings_cleared.has(cur):
		Cfg.endings_cleared.append(cur)
		g.ending_new = true
		Cfg.save()
