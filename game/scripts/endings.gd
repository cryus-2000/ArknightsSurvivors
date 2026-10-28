## 结局与翻节点卡（docs/154，取代海嗣祭坛）：首通结局一后，3:30 / 7:00 中 Boss 全部倒下后各翻一次节点卡（路口一 / 二）。
## 结局线入口（狂徒妄念、开端）路口一必出；持某线信物时路口二必出该线后续事件；其余位置按权重随机填充。
## 结局只看信物：满足条件的结局里取 priority 最高的（原作数据 endings.priority）；最终 Boss 登场即冻结。
## 数据：data/waves.json 的 cross_deck / events / endings；进度：Cfg.endings_cleared（通关过结局一才开启翻卡）。
extends RefCounted

const BossBench = preload("res://scripts/run/boss_bench.gd")   # 录制钩子（docs/170）
const D = preload("res://scripts/data.gd")
const Bal = preload("res://scripts/core/balance.gd")
const NodeIcons = preload("res://scripts/screens/node_icons.gd")
const UM = preload("res://scripts/ui_motion.gd")

var g
var events: Array = []          # 事件表（waves.json）
var ev_by_id: Dictionary = {}
var endings: Dictionary = {}    # 结局表
var deck_cfg: Dictionary = {}   # waves.json cross_deck
var cur := "standard"           # 当前结局
var opened_id := ""             # 正在弹选项的事件
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
var shop_visit := -1            # 诡意行商：第几位商人（merchant_idx）货架 +1、首件打折
var wish_rare := false          # 得偿所愿：下一次藏品三选一稀有 / 核心加权
var elites: Array = []          # 紧急作战刷出的精英小队成员
var squad_pending: Array = []   # 精英小队里同屏上限放不下、推迟刷出的成员：[类型, 出生点]
var squad_affix := ""           # 这支小队共用的词缀（armor 甲壳 / shield 潮盾）
var squad_at := -1.0            # --squadat=秒（调试构建）：到点强制刷一支精英小队
var elite_pos := Vector2.ZERO
var _mh_n := 0                  # 事件改最大生命的次数（stats 来源名）
var route := ""                 # --route=knight|heart|memory|none|rand（机器人走哪条线；空 = 按 seed 轮换）

## 各事件通向的结局（卡背色边）
const LINE_ENDS := {"madness": ["knight"], "knight_stay": ["knight"], "opening": ["deep", "resolve"], "heart": ["deep"], "ritual": ["resolve"]}
## 结局线信物：藏品栏上限（relic/carry_cap ≥ 0 时）为它们留位
const ROUTE_RELICS := ["220", "221", "222", "223", "225", "238", "239", "240", "242"]
const FILL_TYPES := ["wish", "rest", "elite", "shop", "incident", "fog"]


func _init(game) -> void:
	g = game
	var w: Dictionary = D.Loader.load_waves()
	events = w.get("events", [])
	for ev in events:
		ev_by_id[str(ev.id)] = ev
	endings = w.get("endings", {})
	deck_cfg = w.get("cross_deck", {})
	all_unlocked = Cfg.dev_args().has("--allend")
	for a in Cfg.dev_args():
		if a.begins_with("--squadat="):
			squad_at = float(a.substr(10))   # 测试用：到这个游戏秒数强制刷一支精英小队（docs/161 帧时 / 录屏，只在调试构建读）
	for a in Cfg.dev_args():
		if a.begins_with("--route="):
			route = a.substr(8)


## 翻卡开启：玩家局要通关过结局一；测试 / 批跑缺省开（--nocross 关）
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
		enabled = _cross_on()
	if squad_at >= 0.0 and g.t >= squad_at:
		squad_at = -1.0
		_spawn_elites()
	_tick_elites()
	if frozen:
		return
	if g.final_boss != null:
		frozen = true   # 最终 Boss 登场：结局就此冻结（结算与解锁都按这时的结局）
		_log("frozen")
		return
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
	if cross_due > 0 and g.state == g.S.PLAY and g.pending_chests <= 0:
		_deal(cross_due)


## 发牌：必出卡 + 随机填充到 n 张，按 g.rng 洗牌（同 seed 可复现）
func _deal(n: int) -> void:
	cross_due = 0
	cross_done = n
	boss_seen = false
	clear_t = -1.0
	deck = build_deck(n)
	flipped = -1
	var opts: Array = []
	for i in deck.size():
		opts.append({"kind": "node", "id": str(i), "name": NodeIcons.NAMES[deck[i].type], "desc": "", "node": deck[i]})
	_log("deal %d %s" % [n, str(deck.map(func(c): return "%s/%s" % [c.type, c.get("event", "")]))])
	g.panel_ui.show_choices("深入海洋 · 路口%s" % ["一", "二"][n - 1], opts, "cross", "选一张翻开，翻开即生效")


func build_deck(n: int) -> Array:
	var cards: Array = []
	for ev in events:
		if not ev.get("must", false) or int(ev.get("cross", 0)) != n or not _event_ok(ev):
			continue
		cards.append({"type": "incident", "event": str(ev.id), "must": true, "ends": LINE_ENDS.get(str(ev.id), [])})
	var want: int = maxi(int(deck_cfg.get("n", 3)), cards.size())
	var W: Dictionary = deck_cfg.get("weights", {})
	var cand: Array = []
	for t in FILL_TYPES:
		var w: float = float(W.get(t, 0.0)) * _fill_mult(t, cards)
		var u: float = g.rng.randf()   # 每种都抽一次（不论权重是否为 0），随机数消耗固定
		if w > 0.0:
			cand.append([-log(u + 0.0001) / w, t])
	cand.sort_custom(func(a, b): return a[0] < b[0])
	for c in cand:
		if cards.size() >= want:
			break
		var card := {"type": str(c[1]), "must": false, "ends": []}
		if c[1] == "incident":
			card.event = _pick_common()
		cards.append(card)
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
	return events.filter(func(ev): return ev.get("pool", "") == "common" and not used_common.has(str(ev.id)))


func _pick_common() -> String:
	var left := _common_left()
	if left.is_empty():
		return ""
	var id: String = str(left[g.rng.randi() % left.size()].id)
	used_common.append(id)
	return id


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
	picks.append([cross_done, last_type, str(c.get("event", ""))])
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
			wish_rare = true
			g.pending_chests += 1
		"shop":
			var mt: Array = g.MERCHANT_TIMES
			if g.merchant_idx < mt.size():
				shop_visit = g.merchant_idx + 1
				g.vfx.show_banner("诡意行商：下一位商人多带一件货，第一件 %d 折" % int(round(float(deck_cfg.get("shop_disc", 0.7)) * 10.0)))
			else:
				g.rfx.gain_ingots(int(deck_cfg.get("shop_ingots", 20)), "诡意行商 · ")
		"elite":
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
	var heal: float = float(deck_cfg.get("rest_heal", 0.4))
	var mh: float = float(deck_cfg.get("rest_maxhp", 0.05))
	var li: int = int(deck_cfg.get("rest_light", 15))
	var opts: Array = [
		{"kind": "event", "id": "rest:0", "name": "稍事休息", "desc": "回复 %d%% 最大生命，队长最大生命 +%d%%" % [int(heal * 100.0), int(mh * 100.0)], "icon": "e_event", "chips": [], "cat": "安全的角落", "col": NodeIcons.COLS.rest},
		{"kind": "event", "id": "rest:1", "name": "添加燃料", "desc": "灯火 +%d" % li, "icon": "e_event", "chips": [["灯火 +%d" % li, Color(0.95, 0.89, 0.76)]], "cat": "安全的角落", "col": NodeIcons.COLS.rest},
		{"kind": "event", "id": "rest:2", "name": "重整编制", "desc": "立即招募一名干员（编队已满时改为一次成长三选一）", "icon": "e_event", "chips": [], "cat": "安全的角落", "col": NodeIcons.COLS.rest},
	]
	g.panel_ui.show_choices("安全屋", opts, "event", "火光摇曳，食物冒着热气。好好休整，更大的浪涛还在前方。")


func _rest(k: int) -> void:
	match k:
		0:
			_max_hp(float(deck_cfg.get("rest_maxhp", 0.05)))
			g.combat.heal(g.max_hp * float(deck_cfg.get("rest_heal", 0.4)), "安全屋")
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
	g.pickups.drop(elite_pos, "chest", 1.0)
	wish_rare = true   # 这个宝箱的藏品三选一按稀有 / 核心加权（同得偿所愿，progression 读后清掉）
	g.rfx.gain_ingots(int(deck_cfg.get("squad_ingots", 20)), "紧急作战 · ")
	g.vfx.show_banner("精英小队已全灭 —— 拾取宝箱")
	elites.clear()


## ---------- 事件 ----------
func _event_ok(ev: Dictionary) -> bool:
	if ev.has("requires_relic") and not g.relics.has(str(ev.requires_relic)):
		return false
	if ev.has("forbids_relic") and g.relics.has(str(ev.forbids_relic)):
		return false
	if ev.has("requires_flag") and not g.get(ev.requires_flag):
		return false
	return true


## 弹事件选项（C 版式）
func open(ev_id: String) -> void:
	var ev: Dictionary = ev_by_id.get(ev_id, {})
	if ev.is_empty():
		_close()
		return
	opened_id = ev_id
	_log("open " + ev_id)
	var opts: Array = []
	for i in ev.options.size():
		var op: Dictionary = ev.options[i]
		var oid := "%s:%d" % [ev_id, i]
		if searched.has(oid) or not _option_ok(op):
			continue
		var icon: String = "e_event"
		var chips: Array = []
		for o in op.get("ops", []):
			if o.has("chance"):
				chips.append(["%d%%" % int(round(float(o.chance) * 100.0)), Color(0.18, 0.72, 1.0)])
			if o.has("light"):
				chips.append(["灯火 %+d" % int(o.light), Color(0.95, 0.89, 0.76)])
			if o.has("relic"):
				icon = "relic_" + str(o.relic)
				chips.append(["得到藏品", Color(0.18, 0.72, 1.0)])
			if o.has("ingots") and not o.has("chance"):
				chips.append(["源石锭 %+d" % int(o.ingots), Color(0.18, 0.83, 0.63)])
			if o.has("maxhp_pct"):
				chips.append(["最大生命 %+d%%" % int(round(float(o.maxhp_pct) * 100.0)), Color(0.55, 1.0, 0.6) if float(o.maxhp_pct) > 0.0 else Color(1.0, 0.45, 0.45)])
			if o.has("hp_pct"):
				chips.append(["生命 %+d%%" % int(round(float(o.hp_pct) * 100.0)), Color(1.0, 0.45, 0.45)])
		var opt := {"kind": "event", "id": oid, "name": op.label, "desc": op.desc, "icon": icon, "chips": chips,
			"cat": "事件  " + ev.name, "col": Color(0.55, 0.75, 1.0)}
		if int(op.get("cost", 0)) > g.ingots:
			opt.disabled = true
			opt.desc = str(op.desc) + "（源石锭不足）"
		opts.append(opt)
	if opts.is_empty():
		opts.append({"kind": "event", "id": "%s:-1" % ev_id, "name": "离开", "desc": "什么都不做", "icon": "exit", "chips": [], "cat": "事件  " + ev.name, "col": Color(0.55, 0.75, 1.0)})
	g.panel_ui.show_choices(ev.name, opts, "event", str(ev.get("text", "")))


## 选项还能不能给：给的藏品已经拥有且满级（抉择信物只有 1 级）就不出
func _option_ok(op: Dictionary) -> bool:
	for o in op.get("ops", []):
		if o.has("relic") and not g.progression.can_gain_relic(str(o.relic)):
			return false
	return true


## 选项生效。返回 true = 又弹了下一屏（深蓝之心继续搜寻 / 仪式 → 升华 / 园林 → 赞歌），调用方不要关面板
func pick(o: Dictionary) -> bool:
	var parts: PackedStringArray = str(o.id).split(":")
	opened_id = ""
	if parts[0] == "rest":
		_rest(int(parts[1]))
		return false
	var ev: Dictionary = ev_by_id.get(parts[0], {})
	var k := int(parts[1])
	if ev.is_empty() or k < 0:
		return false
	var op: Dictionary = ev.options[k]
	if picks.size() > 0 and picks[-1].size() == 3:
		picks[-1].append(k)
	_log("pick %s:%d" % [parts[0], k])
	for x in op.get("ops", []):
		if x.has("chance") and g.rng.randf() >= float(x.chance):
			g.vfx.add_text(g.ppos + Vector2(0, -90), "什么都没有发生", Color(0.7, 0.75, 0.8), 16)
			continue
		_apply_op(x)
	if ev.get("repeat", false) and not op.get("end", false):
		searched.append(str(o.id))
		open(str(ev.id))
		return true
	var nxt: String = str(op.get("next", ev.get("next", "")))
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
		g.progression.gain_relic(str(x.relic))
	if x.has("relic_choice"):
		g.pending_chests += int(x.relic_choice)


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
	if enabled and not frozen:
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
