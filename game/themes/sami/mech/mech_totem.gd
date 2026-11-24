extends "res://scripts/core/theme_mechanic.gd"
## 萨米主题机制 · 密文板（docs/394 §5 规则与数值、docs/411 本批范围；数据读 themes/sami/data/mechanics.json totem）。
## 布局（何时生效）+ 本因（给什么）组成一次宣告：随时按 T / 手柄 Y / 触屏「密文」键 → 暂停面板 → 选布局 → 选本因 →（自选时机）→ 两块消耗，坍缩值 −1。
## 同色或全色布局触发协语（本因按 synergy 结算）；无色空无 / 伤痕只能互配，宣告后下一个路口出结局二入口卡「木裂前兆」。
## 时机：fight（立刻 N 秒 / 精英 / Boss / 中期 Boss / 大群 / 本阶段剩余）与 cross（下一个 / 之后 / 接下来 n 个 / 剩下所有路口）。
##   战斗类本因只在 fight 时机生效，路口类只在 cross 时机生效，「经过」类在每个时机结束时结算一次。
## 本批不进掉落池：带 needs 的 6 块（依赖萨米事件 / 招募卡 / 抗干扰）；协语友军「精英干员临时加入」下批（辩论协语只结算普通版）。
## 随机数走自己的 rng（种子 = 局种子 + "totem"），不动主 rng；机器人（g.bot）不开面板，直接按策略宣告。

const Game = preload("res://scripts/game.gd")
const D = preload("res://scripts/data.gd")
const MJ := "res://themes/sami/data/mechanics.json"
const COLS := {"RED": Color(0.95, 0.42, 0.38), "GREEN": Color(0.45, 0.88, 0.5), "BLUE": Color(0.42, 0.66, 1.0), "ALL": Color(0.95, 0.85, 0.5), "NONE": Color(0.75, 0.75, 0.8)}
const CN_COL := {"RED": "红", "GREEN": "绿", "BLUE": "蓝", "ALL": "全色", "NONE": "无色"}
const CN_RAR := {"NORMAL": "普通", "RARE": "稀有", "SUPER_RARE": "超稀有"}
const PICK_DEFAULT := ["now45", "next_elite", "next_boss", "next_cross_card"]
const TIMING_CN := {"now45": "立刻 45 秒", "next_elite": "下一场精英", "next_boss": "下一个 Boss", "next_cross_card": "下一个路口的 1 张卡"}

var g: Game
var T: Dictionary = {}
var boards: Dictionary = {}      # id → 定义
var hand: Array = []             # 手里的板 id（按获得顺序）
var wins: Array = []             # 进行中 / 等待中的时机
var rng := RandomNumberGenerator.new()
var _seeded := false
var _started := false
var _ui: Dictionary = {}         # 面板进行中：{step, li, ei, picks}
var _seen_elites: Dictionary = {}
var _prev_warn := 0.0
var _prev_threat := -1
var _deals := 0
var _price_restore := 0.0        # 惊讶协语打折：下一帧还原
var _wid := 0
var _bot_t := 0.0
var _demo_done := false
var _demo_t := -1.0              # --totemdemo=<秒>（调试，录像用）：到点打开宣告面板，之前机器人不自动宣告
var drones: Array = []           # 斗志昂扬无人机 {end, t, w}
var guards: Array = []           # 友方盾卫 {pos, hp, maxhp, end, w}
var log_decl: Array = []         # [时刻, 布局, 本因, 协语]
var drops := 0
var uses: Dictionary = {}        # 板名 → 用过几次
var _shots: Array = []           # 无人机射击闪线 [目标点, 时刻]（只画）


func _init(game) -> void:
	g = game
	var f := FileAccess.open(MJ, FileAccess.READ)
	if f != null:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			T = d.get("totem", {})
	for b in T.get("boards", []):
		boards[str(b.id)] = b


func _rng() -> RandomNumberGenerator:
	if not _seeded:
		_seeded = true
		rng.seed = hash(str(g.rng.seed) + "totem")
	return rng


# ---------- 持有 / 掉落 ----------

func is_layout(bid: String) -> bool:
	return str(boards.get(bid, {}).get("pos", "")) == "LOCATION"


func layouts() -> Array:
	return hand.filter(func(b): return is_layout(b))


func effects() -> Array:
	return hand.filter(func(b): return not is_layout(b))


func give(bid: String, quiet := false) -> void:
	if not boards.has(bid):
		return
	hand.append(bid)
	drops += 1
	if not quiet:
		var b: Dictionary = boards[bid]
		g.vfx.add_text(g.ppos + Vector2(0, -96), "密文板「%s」" % b.name, COLS.get(b.color, Color.WHITE), 15)
		Sfx.play("relic", -10.0, 1.3, 0.0)


## 随机掉 1 块：稀有度按权重；手里布局 / 本因不均时 kind_balance 概率补少的那类；带 needs / only_with 的不进池
func drop_one(force_pos := "") -> void:
	var dr: Dictionary = T.get("drops", {})
	var pos := force_pos
	if pos == "":
		var nl: int = layouts().size()
		var ne: int = effects().size()
		pos = "LOCATION" if _rng().randf() < 0.5 else "EFFECT"
		if nl != ne and _rng().randf() < float(dr.get("kind_balance", 0.7)):
			pos = "LOCATION" if nl < ne else "EFFECT"
	var rw: Dictionary = dr.get("rarity_w", {"NORMAL": 60, "RARE": 32, "SUPER_RARE": 8})
	var tot := 0.0
	for k in rw:
		tot += float(rw[k])
	var u: float = _rng().randf() * tot
	var rar := "NORMAL"
	for k in rw:
		u -= float(rw[k])
		if u <= 0.0:
			rar = str(k)
			break
	var pool: Array = []
	for b in T.get("boards", []):
		if str(b.pos) == pos and str(b.rarity) == rar and _in_pool(b):
			pool.append(str(b.id))
	if pool.is_empty():
		for b in T.get("boards", []):
			if str(b.pos) == pos and _in_pool(b):
				pool.append(str(b.id))
	if not pool.is_empty():
		give(pool[_rng().randi() % pool.size()])


func _in_pool(b: Dictionary) -> bool:
	return not b.has("needs") and not (b.get("normal", {}) as Dictionary).has("only_with")


## mech_foes.on_enemy_killed 转来：精英 / 中期 Boss / 宝箱
func on_kill(e: Dictionary) -> void:
	var dr: Dictionary = T.get("drops", {})
	if e.get("chest", false):
		if _rng().randf() < float(dr.get("chest", 0.1)):
			drop_one()
		return
	if e.boss:
		if not _final_boss(e):
			for k in int(dr.get("mid_boss", 2)):
				drop_one("LOCATION" if k % 2 == 0 else "EFFECT")
		return
	if e.elite and _rng().randf() < float(dr.get("elite", 0.15)):
		drop_one()


## mech_kingdom 瓦解国度时调
func on_kingdom_break() -> void:
	if _rng().randf() < float(T.get("drops", {}).get("kingdom", 0.2)):
		drop_one()


func _final_boss(e: Dictionary) -> bool:
	var en: Dictionary = D.ENDINGS.get(g.ending, {})
	var grp: Array = en.get("boss_group", [en.get("boss", "")])
	return grp.has(str(e.type))


# ---------- 组合规则 ----------

func _kind(bid: String) -> String:
	return str(boards.get(bid, {}).get("kind", ""))


## 能不能配；返回 "" = 能，否则写原因
func why_not(lid: String, eid: String) -> String:
	var L: Dictionary = boards.get(lid, {})
	var E: Dictionary = boards.get(eid, {})
	var lw = (L.get("normal", {}) as Dictionary).get("only_with", null)
	var ew = (E.get("normal", {}) as Dictionary).get("only_with", null)
	if lw != null or ew != null:
		var ok2: bool = lw != null and ew != null and eid.ends_with(str(lw)) and lid.ends_with(str(ew))
		return "" if ok2 else "只能和「%s」组合" % _partner_name(L, E)
	var ok: Array = (T.get("compat", {}) as Dictionary).get(_kind(eid), [])
	if not ok.has(_kind(lid)):
		return "战斗类本因要配战斗时机" if _kind(eid) == "fight" else "路口类本因要配路口时机"
	return ""


func _partner_name(L: Dictionary, E: Dictionary) -> String:
	var want: String = str(L.get("normal", {}).get("only_with", E.get("normal", {}).get("only_with", "")))
	for b in T.get("boards", []):
		if str(b.id).ends_with(want) or str(b.id) == want:
			return str(b.name)
	return "?"


func synergy(lid: String, eid: String) -> bool:
	var L: Dictionary = boards.get(lid, {})
	var E: Dictionary = boards.get(eid, {})
	if E.get("synergy", null) == null:
		return false
	if bool(L.get("normal", {}).get("force_synergy", false)) or str(L.color) == "ALL":
		return true
	return str(L.color) == str(E.color) and str(L.color) != "NONE"


func pairs() -> Array:
	var out: Array = []
	for l in layouts():
		for e in effects():
			if why_not(l, e) == "":
				out.append([l, e])
	return out


# ---------- 时机 ----------

## 布局的时机展开成若干窗口说明；picks = 面板里「自选」的结果（按出现顺序）
func expand(lid: String, picks: Array) -> Array:
	var out: Array = []
	var pi := [0]
	_expand(boards[lid].get("normal", {}), out, picks, pi, 0)
	return out


func _expand(t: Dictionary, out: Array, picks: Array, pi: Array, skip: int) -> void:
	match str(t.get("timing", "")):
		"now":
			out.append({"t": "now", "dur": float(t.get("dur", 45))})
		"now45":
			out.append({"t": "now", "dur": 45.0})
		"next_elite":
			out.append({"t": "elite"})
		"next_boss":
			out.append({"t": "boss"})
		"next_mid_boss":
			out.append({"t": "mid"})
		"next_elites":
			for k in int(t.get("n", 1)):
				out.append({"t": "elite"})
		"next_hordes":
			for k in int(t.get("n", 1)):
				out.append({"t": "horde", "cap": float(t.get("dur_cap", 30))})
		"stage_rest":
			out.append({"t": "stage", "min": float(t.get("min", 60)), "plus": str(t.get("plus", ""))})
		"next_cross":
			out.append({"t": "cross", "skip": skip, "cards": str(t.get("cards", "pick")), "n": int(t.get("n", 1))})
		"next_cross_card":
			out.append({"t": "cross", "skip": skip, "cards": "pick", "n": 1})
		"later_cross":
			for k in int(t.get("n", 1)):
				out.append({"t": "cross", "skip": 1 + k, "cards": str(t.get("cards", "random_noncombat")), "n": 1})
		"next_crosses":
			for k in int(t.get("n", 1)):
				out.append({"t": "cross", "skip": k, "cards": str(t.get("cards", "random_noncombat")), "n": 1})
		"all_crosses":
			out.append({"t": "cross_all", "cards": str(t.get("cards", "all_noncombat"))})
		"random":
			var opts: Array = PICK_DEFAULT.duplicate()
			for k in mini(int(t.get("n", 1)), opts.size()):
				var j: int = _rng().randi() % opts.size()
				_expand({"timing": opts[j]}, out, picks, pi, skip)
				opts.remove_at(j)
		"pick":
			var of: Array = t.get("of", PICK_DEFAULT)
			var ch: String = str(picks[pi[0]]) if pi[0] < picks.size() else str(of[0])
			pi[0] += 1
			_expand({"timing": ch}, out, picks, pi, skip)
		"multi":
			for s in t.get("of", []):
				_expand(s, out, picks, pi, skip)


## 布局里要自选的次数与每次的选项
func pick_specs(lid: String) -> Array:
	var out: Array = []
	_pick_specs(boards[lid].get("normal", {}), out)
	return out


func _pick_specs(t: Dictionary, out: Array) -> void:
	if str(t.get("timing", "")) == "pick":
		out.append(t.get("of", PICK_DEFAULT))
	elif str(t.get("timing", "")) == "multi":
		for s in t.get("of", []):
			_pick_specs(s, out)


func timing_text(lid: String) -> String:
	return _ttext(boards[lid].get("normal", {}))


func _ttext(t: Dictionary) -> String:
	var tm: Dictionary = T.get("timings", {})
	match str(t.get("timing", "")):
		"now":
			return "立刻 %d 秒" % int(t.get("dur", 45))
		"next_elites":
			return "接下来 %d 场精英" % int(t.get("n", 1))
		"next_hordes":
			return "接下来 %d 次大群" % int(t.get("n", 1))
		"next_crosses":
			return "接下来 %d 个路口" % int(t.get("n", 1))
		"random":
			return "随机 %d 个时机" % int(t.get("n", 1))
		"stage_rest":
			return "本阶段剩余（至少 %d 秒）+ 本阶段的 Boss" % int(t.get("min", 60))
		"pick":
			return "自选：" + " / ".join((t.get("of", PICK_DEFAULT) as Array).map(func(x): return TIMING_CN.get(str(x), str(x))))
		"multi":
			return " + ".join((t.get("of", []) as Array).map(func(x): return _ttext(x)))
		"next_cross":
			var c: String = {"first": "第 1 张卡", "pick_noncombat": "1 张非战斗卡", "all": "全部卡", "pick": "1 张卡", "encounter": "不期而遇卡"}.get(str(t.get("cards", "")), "")
			return "下一个路口" + (" · " + c if c != "" else "")
		"later_cross":
			return "之后的路口随机 %d 张非战斗卡" % int(t.get("n", 1))
	return str(tm.get(str(t.get("timing", "")), t.get("timing", "")))


## 本因效果文字（syn = 协语版）
func effect_text(eid: String, syn: bool) -> String:
	var E: Dictionary = boards[eid]
	var ef = E.get("synergy" if syn else "normal", {})
	if ef == null:
		return ""
	var s: Array = []
	for k in ef:
		var v = ef[k]
		match str(k):
			"atk_spd": s.append("全队攻速 +%d%%" % int(round(float(v) * 100.0)))
			"maxhp": s.append("最大生命 +%d%%" % int(round(float(v) * 100.0)))
			"sp_regen": s.append("技力回复 +%d%%" % int(round(float(v) * 100.0)))
			"ally": s.append({"drone": "斗志昂扬无人机助战", "guard": "友方盾卫助战", "operator": "精英干员临时加入（协语效果暂未开放）"}.get(str(v), str(v)))
			"heal_end": s.append("时机结束时回复 %d%% 生命" % int(round(float(v) * 100.0)))
			"maxhp_perm": s.append("最大生命 +%d%%（永久）" % int(round(float(v) * 100.0)))
			"ingots_end": s.append("时机结束时源石锭 +%d" % int(v))
			"relic": s.append("得到 1 件藏品")
			"heal_per_target": s.append("每个时机立即回复 %d%%" % int(round(float(v) * 100.0)))
			"ingots_per_target": s.append("每个时机立即源石锭 +%d" % int(v))
			"ingot_mult": s.append("时机内拾取的源石锭 ×%d" % int(v))
			"heal_mult": s.append("时机内回复 ×%d" % int(v))
			"shield": s.append("护盾 +%d 层" % int(v))
			"card": s.append({"shop": "那张卡变诡意行商", "emergency": "那张卡变紧急作战", "rest": "那张卡变安全的角落", "ending2_omen": "那张卡变「木裂前兆」", "sacrifice": "那张卡变失与得", "encounter": "那张卡变不期而遇", "wish": "那张卡变得偿所愿", "ahead": "那张卡变先行一步"}.get(str(v), str(v)))
			"shop_price": s.append("售价 −%d%%" % int(round(-float(v) * 100.0)))
			"reveal": s.append("那个路口的卡全部翻开")
			"declare_collapse": s.append("这次宣告坍缩值 %d" % int(v))
	return "，".join(s)


# ---------- 宣告 ----------

func declare(lid: String, eid: String, picks: Array = []) -> void:
	if not (hand.has(lid) and hand.has(eid)) or why_not(lid, eid) != "":
		return
	var syn: bool = synergy(lid, eid)
	var E: Dictionary = boards[eid]
	var ef: Dictionary = E.get("synergy", {}) if syn else E.get("normal", {})
	if syn and str(ef.get("ally", "")) == "operator":
		ef = E.get("normal", {})   # 精英干员临时加入下批做：协语只结算普通版（docs/411 §2.3）
	hand.erase(lid)
	hand.erase(eid)
	var specs: Array = expand(lid, picks)
	var cm = g.mech("collapse")
	if cm != null:
		cm.add(float(ef.get("declare_collapse", T.get("declare", {}).get("collapse", -1))), "totem")
	# 每个时机立即结算的（呼救 / 满足）
	if ef.has("heal_per_target"):
		g.combat.heal(g.max_hp * float(ef.heal_per_target) * specs.size(), "密文板")
	if ef.has("ingots_per_target"):
		g.rfx.gain_ingots(int(ef.ingots_per_target) * specs.size(), "密文板 · ")
	for sp in specs:
		_wid += 1
		var w: Dictionary = sp.duplicate()
		w.merge({"id": _wid, "ef": ef, "kind": _kind(eid), "st": "wait", "t0": g.t, "name": "%s · %s" % [boards[lid].name, E.name], "deals": _deals})
		wins.append(w)
	log_decl.append([snappedf(g.t, 0.1), str(boards[lid].name), str(E.name), syn])
	uses[str(boards[lid].name)] = int(uses.get(str(boards[lid].name), 0)) + 1
	uses[str(E.name)] = int(uses.get(str(E.name), 0)) + 1
	g.vfx.show_banner("宣告：%s · %s%s" % [boards[lid].name, E.name, "（柯瓦狄协语）" if syn else ""])
	Sfx.play("relic", -4.0, 0.8, 0.0)
	g.fx.append({"kind": "ring", "pos": g.ppos, "r": 140.0, "life": 0.6, "max": 0.6, "col": COLS.get(str(boards[lid].color), Color.WHITE)})
	_tick_windows(0.0)


# ---------- 每帧 ----------

func on_world_tick(dt: float) -> void:
	if not _started:
		_started = true
		_start_hand()
	if _price_restore > 0.0:
		g.shop_price_mult /= _price_restore
		_price_restore = 0.0
	_tick_windows(dt)
	_tick_allies(dt)
	if _demo_t == -1.0:
		_demo_t = INF
		for a in Cfg.dev_args():
			if a.begins_with("--totemdemo="):
				_demo_t = float(a.substr(12))
	if _demo_t < INF:
		if g.t >= _demo_t and g.state == g.S.PLAY:
			_demo_t = INF
			_demo_done = true   # 演示只开一次；之后机器人也不自动宣告，录像里只有演示这一次
			open_panel()
		return
	if _demo_done:
		return
	if g.bot != null:
		_bot_tick(dt)


func _start_hand() -> void:
	for a in Cfg.dev_args():
		if a == "--totem=boss2":
			for b in T.get("boards", []):
				if (b.get("normal", {}) as Dictionary).has("only_with"):
					give(str(b.id), true)
		elif a == "--totem=demo":
			for nm in ["猎手", "眼睛", "歌唱", "惊讶", "呼救"]:
				for b in T.get("boards", []):
					if str(b.name) == nm:
						give(str(b.id), true)
		elif a.begins_with("--totem=all"):
			for b in T.get("boards", []):
				if _in_pool(b):
					give(str(b.id), true)
	for st in T.get("drops", {}).get("start", []):
		var pool: Array = []
		var col := ""
		if not hand.is_empty():
			col = str(boards[hand[-1]].color)
		for b in T.get("boards", []):
			if str(b.pos) == str(st[0]) and str(b.rarity) == str(st[1]) and _in_pool(b) and (col == "" or str(b.color) == col):
				pool.append(str(b.id))
		if not pool.is_empty():
			give(pool[_rng().randi() % pool.size()], true)
	drops = 0


func _tick_windows(dt: float) -> void:
	var horde_start: bool = g.horde_warn > 0.0 and _prev_warn <= 0.0
	_prev_warn = g.horde_warn
	var stage_change: bool = _prev_threat >= 0 and g.threat != _prev_threat
	_prev_threat = g.threat
	var new_elites: Array = []
	for e in g.enemies:
		if e.elite and not e.dead and not e.boss and not _seen_elites.has(int(e.id)):
			_seen_elites[int(e.id)] = true
			new_elites.append(int(e.id))
	var claimed_horde := false
	for w in wins:
		if w.st == "done":
			continue
		match str(w.t):
			"now":
				if w.st == "wait":
					_open(w, g.t + float(w.dur))
			"elite":
				if w.st == "wait":
					if not new_elites.is_empty():
						w.target = new_elites.pop_front()
						_open(w, g.t + 40.0)
				else:
					var e = g.enemies_sys.by_id(int(w.target))
					if e == null or e.dead:
						w.end = g.t
			"boss", "mid":
				if w.st == "wait":
					for b in g.bosses:
						if not b.dead and (w.t == "boss" or not _final_boss(b)):
							w.target = int(b.id)
							_open(w, INF)
							break
				else:
					var b = g.enemies_sys.by_id(int(w.target))
					if b == null or b.dead:
						w.end = g.t
			"horde":
				if w.st == "wait" and horde_start and not claimed_horde:
					claimed_horde = true
					_open(w, g.t + float(w.cap))
			"stage":
				if w.st == "wait":
					_open(w, INF)
					w.stage_end = false
				else:
					if stage_change:
						w.stage_end = true
					var boss_live: bool = g.bosses.any(func(b): return not b.dead)
					var age: float = g.t - float(w.t_open)
					if (w.stage_end and age >= float(w.min) and not (str(w.plus) != "" and boss_live)) or age >= 600.0:
						w.end = g.t
		if w.st == "on" and g.t >= float(w.get("end", INF)):
			_close(w)
	wins = wins.filter(func(w): return w.st != "done")


func _open(w: Dictionary, end: float) -> void:
	w.st = "on"
	w.t_open = g.t
	w.end = end
	w.ing0 = g.ingots
	w.heal0 = _heal_sum()
	if str(w.kind) == "fight":
		var ef: Dictionary = w.ef
		var src := "totem_%d" % int(w.id)
		if ef.has("atk_spd") and g.stats.has_stat(&"op_aspd"):
			g.stats.add(&"op_aspd", "mult", 1.0 + float(ef.atk_spd), src)
		if ef.has("maxhp") and g.stats.has_stat(&"max_hp"):
			g.stats.add(&"max_hp", "mult", 1.0 + float(ef.maxhp), src)
		if ef.has("sp_regen") and g.stats.has_stat(&"op_skill_sp"):
			g.stats.add(&"op_skill_sp", "mult", 1.0 + float(ef.sp_regen), src)
		match str(ef.get("ally", "")):
			"drone":
				drones.append({"w": int(w.id), "t": 0.0, "end": minf(end, g.t + float(T.get("allies", {}).get("drone", {}).get("max_dur", 60)))})
			"guard":
				var gd: Dictionary = T.get("allies", {}).get("guard", {})
				var hp: float = g.max_hp * float(gd.get("hp_mult", 2.0))
				guards.append({"w": int(w.id), "pos": g.ppos + Vector2(40, 0), "hp": hp, "maxhp": hp, "end": minf(end, g.t + float(gd.get("max_dur", 60)))})


func _close(w: Dictionary) -> void:
	w.st = "done"
	g.stats.remove_source("totem_%d" % int(w.id))
	g.hp = minf(g.hp, g.max_hp)
	drones = drones.filter(func(d): return int(d.w) != int(w.id))
	guards = guards.filter(func(d): return int(d.w) != int(w.id))
	_settle(w)


## 「经过」类：每个时机结束时结算一次
func _settle(w: Dictionary) -> void:
	var ef: Dictionary = w.ef
	if ef.has("heal_end"):
		g.combat.heal(g.max_hp * float(ef.heal_end), "密文板")
	if ef.has("ingots_end"):
		g.rfx.gain_ingots(int(ef.ingots_end), "密文板 · ")
	if ef.has("shield"):
		g.shield += int(ef.shield)
	if ef.has("maxhp_perm"):
		g.rfx._apply_stat("max_hp", "mult", 1.0 + float(ef.maxhp_perm), "totem_perm_%d" % int(w.id), "")
	if ef.has("relic"):
		g.endg._gain_lane_relic("", [])
	if ef.has("ingot_mult") and w.has("ing0"):
		var got: int = maxi(0, g.ingots - int(w.ing0))
		if got > 0:
			g.rfx.gain_ingots(int(got * (float(ef.ingot_mult) - 1.0)), "密文板 · ")
	if ef.has("heal_mult") and w.has("heal0"):
		var hh: float = _heal_sum() - float(w.heal0)
		if hh > 0.0:
			g.combat.heal(hh * (float(ef.heal_mult) - 1.0), "密文板", "", 1)   # combat.HEAL_NO_MULT


func _heal_sum() -> float:
	var s := 0.0
	for k in g.heal_log:
		s += float(g.heal_log[k])
	return s


# ---------- 路口 ----------

## endings._show_deck 发牌前调：等着这个路口的时机改卡、结算
func on_deck(deck: Array) -> void:
	_deals += 1
	for w in wins:
		if w.st != "wait":
			continue
		var t: String = str(w.t)
		if t == "cross":
			if _deals - int(w.deals) - 1 != int(w.skip):
				continue
		elif t != "cross_all":
			continue
		if str(w.kind) == "cross" or str(w.kind) == "any" or str(w.kind) == "pass":
			_apply_cards(deck, w)
		if t == "cross":
			w.st = "done"
			_settle(w)
		else:
			_settle(w)
	wins = wins.filter(func(w): return w.st != "done")


func _apply_cards(deck: Array, w: Dictionary) -> void:
	var ef: Dictionary = w.ef
	if ef.get("reveal", false):
		for c in deck:
			if str(c.type) == "fog" and not c.get("must", false):
				c.type = g.endg._fog_type()
				if c.type == "incident":
					c.event = g.endg._pick_common()
					if str(c.event) == "":
						c.type = "wish"
	var card: String = str(ef.get("card", ""))
	if card == "":
		return
	var idx: Array = []
	for i in deck.size():
		var c: Dictionary = deck[i]
		if c.get("must", false):
			continue
		var nc: bool = str(c.type) != "elite"
		match str(w.cards):
			"first":
				if i == 0:
					idx.append(i)
			"all":
				idx.append(i)
			"pick", "pick_noncombat", "random_noncombat", "all_noncombat":
				if nc or str(w.cards) == "pick":
					idx.append(i)
	if idx.is_empty():
		return
	match str(w.cards):
		"pick", "pick_noncombat", "first":
			idx = [idx[0]]
		"random_noncombat":
			idx = [idx[_rng().randi() % idx.size()]]
	for i in idx:
		var c: Dictionary = deck[i]
		match card:
			"shop":
				c.type = "shop"
			"emergency":
				c.type = "elite"
			"rest":
				c.type = "rest"
			"wish":
				c.type = "wish"
			"ending2_omen":
				c.type = "incident"
				c.event = "sami_omen_winter"   # 「木裂前兆」事件随结局线事件一批做（docs/410 §2.1）；事件表里没有时翻开即关
				c.must = true
				c.ends = ["winter"]
		c.erase("fog")
	if ef.has("shop_price") and card == "shop":
		var k: float = 1.0 + float(ef.shop_price)
		g.shop_price_mult *= k
		_price_restore = k


# ---------- 友军（协语） ----------

func _tick_allies(dt: float) -> void:
	var D0: Dictionary = T.get("allies", {}).get("drone", {})
	for d in drones:
		d.t = float(d.t) - dt
		if d.t <= 0.0:
			d.t = float(D0.get("interval", 0.8))
			var near = g.enemies_sys.nearest(1, 320.0, g.ppos)
			if not near.is_empty():
				var e = near[0]
				var dmg: float = float(D0.get("atk_base", 30.0)) * float(D0.get("atk_mult", 0.6)) * (g.stats.value(&"op_atk") if g.stats.has_stat(&"op_atk") else 1.0)
				g.combat.damage(e, dmg, g.combat.make_hit("援护"))   # 共享来源「援护」（支援、远程物理弹）
				_shots.append([e.pos, g.t])
	drones = drones.filter(func(d): return g.t < float(d.end))
	var G0: Dictionary = T.get("allies", {}).get("guard", {})
	var tr: float = float(G0.get("taunt_r", 180))
	for gd in guards:
		for j in g.enemies_sys.query(gd.pos, tr):
			var e: Dictionary = g.enemies[j]
			if e.dead or e.boss or e.pos.distance_to(gd.pos) > tr:
				continue
			var off: Vector2 = gd.pos - e.pos
			var dd: float = off.length()
			if dd > 20.0:
				e.pos += off / dd * minf(dd - 20.0, 60.0 * dt)   # 吸引：往盾卫身上靠
			else:
				gd.hp = float(gd.hp) - float(e.dmg) * dt
	guards = guards.filter(func(d): return g.t < float(d.end) and float(d.hp) > 0.0)


# ---------- 机器人 ----------

func _bot_tick(dt: float) -> void:
	_bot_t -= dt
	if _bot_t > 0.0 or g.state != g.S.PLAY:
		return
	_bot_t = 2.0
	var ps: Array = pairs()
	if ps.is_empty():
		return
	var best: Array = ps[0]
	var bs := -INF
	for p in ps:
		var s: float = 2.0 if synergy(p[0], p[1]) else 0.0
		if _kind(p[1]) == "fight":
			s += 1.0 if g.bosses.any(func(b): return not b.dead) else -0.5
		if (boards[p[0]].get("normal", {}) as Dictionary).has("only_with"):
			s += 10.0
		if s > bs:
			bs = s
			best = p
	declare(best[0], best[1], _bot_picks(best[0]))


func _bot_picks(lid: String) -> Array:
	var out: Array = []
	var boss_live: bool = g.bosses.any(func(b): return not b.dead)
	for of in pick_specs(lid):
		out.append("next_boss" if boss_live and of.has("next_boss") else str(of[0]))
	return out


## 面板里机器人（autotest 非批跑、录像）选哪项：布局 → 第一对能配的；本因 → 协语优先；自选 → 第一个；取消排最后
func choice_bot() -> int:
	if g.bosses.any(func(b): return not b.dead):
		for i in g.choices.size():
			if str(g.choices[i].get("id", "")) == "P:next_boss":
				return i
	for i in g.choices.size():
		if not g.choices[i].get("disabled", false) and str(g.choices[i].get("id", "")) != "back":
			return i
	return 0


# ---------- 面板（玩家） ----------

func on_key(k: int) -> bool:
	if k != KEY_T or g.state != g.S.PLAY or g.bot != null:
		return false
	open_panel()
	return true


func touch_btn() -> String:
	return "密文" if g.state == g.S.PLAY else ""


func on_touch_btn() -> void:
	if g.state == g.S.PLAY:
		open_panel()


const PAGE := 2   # 面板一行最多 4 张卡：不超过 3 块全放 +「取消」；超过 3 块每页 2 块 +「下一页」+「取消」


func open_panel() -> void:
	if layouts().is_empty():
		g.vfx.show_banner("手里没有布局密文板")
		return
	_ui = {"step": "L", "picks": [], "page": 0}
	_show_layouts()


## 同一块板合并成一张卡（名字后写 ×n）；能配的排前面
func _grouped(ids: Array, ok_fn: Callable) -> Array:
	var seen: Dictionary = {}
	var order: Array = []
	for bid in ids:
		if not seen.has(bid):
			seen[bid] = 0
			order.append(bid)
		seen[bid] = int(seen[bid]) + 1
	var good: Array = order.filter(func(b): return ok_fn.call(b))
	var bad: Array = order.filter(func(b): return not ok_fn.call(b))
	return (good + bad).map(func(b): return [b, int(seen[b])])


func _page(items: Array, opts_fn: Callable) -> Array:
	var n: int = items.size()
	var per: int = n if n <= PAGE + 1 else PAGE
	var pages: int = maxi(1, int(ceil(n / float(maxi(1, per)))))
	var p: int = int(_ui.get("page", 0)) % pages
	_ui.page = p
	var opts: Array = []
	for it in items.slice(p * per, p * per + per):
		opts.append(opts_fn.call(it))
	if pages > 1:
		opts.append({"kind": "mech", "mech": id, "id": "next", "name": "下一页", "desc": "第 %d / %d 页" % [p + 1, pages], "icon": "e_event", "chips": [], "cat": "翻页  MORE", "col": Color(0.6, 0.7, 0.8)})
	opts.append(_cancel())
	return opts


func _show_layouts() -> void:
	_ui.step = "L"
	var items: Array = _grouped(layouts(), func(lid): return effects().any(func(e): return why_not(lid, e) == ""))
	var opts: Array = _page(items, func(it):
		var lid: String = it[0]
		var b: Dictionary = boards[lid]
		var ok: bool = effects().any(func(e): return why_not(lid, e) == "")
		var o := {"kind": "mech", "mech": id, "id": "L:" + lid, "name": str(b.name) + (" ×%d" % int(it[1]) if int(it[1]) > 1 else ""), "desc": "时机：" + timing_text(lid) + ("" if ok else "（手里没有能配的本因）"),
			"icon": "e_event", "cat": "布局 · %s · %s  LAYOUT" % [CN_COL.get(str(b.color), ""), CN_RAR.get(str(b.rarity), "")], "chips": [], "col": COLS.get(str(b.color), Color.WHITE)}
		if not ok:
			o.disabled = true
		return o)
	g.panel_ui.show_choices("宣告密文板 · 选布局", opts, "mech", "布局决定何时生效 · 本因 %d 块 · 宣告后坍缩值 −1" % effects().size(), int(_ui.get("shown", 0)) > 0)
	_ui.shown = 1


func _cancel() -> Dictionary:
	return {"kind": "mech", "mech": id, "id": "back", "name": "取消", "desc": "回到战斗，不消耗密文板", "icon": "exit", "chips": [], "cat": "取消  CANCEL", "col": Color(0.6, 0.6, 0.65)}


func _effects_panel(lid: String) -> void:
	if str(_ui.get("step", "")) != "E":
		_ui.page = 0
	_ui.step = "E"
	_ui.lid = lid
	var items: Array = _grouped(effects(), func(eid): return why_not(lid, eid) == "")
	var opts: Array = _page(items, func(it):
		var eid: String = it[0]
		var b: Dictionary = boards[eid]
		var why := why_not(lid, eid)
		var syn: bool = why == "" and synergy(lid, eid)
		var txt: String = effect_text(eid, syn)
		if syn and str(b.get("synergy", {}).get("ally", "")) == "operator":
			txt = effect_text(eid, false) + "（协语效果暂未开放）"
		var chips: Array = []
		if syn:
			chips.append(["柯瓦狄协语", Color(1.0, 0.85, 0.45)])
		var o := {"kind": "mech", "mech": id, "id": "E:" + eid, "name": str(b.name) + (" ×%d" % int(it[1]) if int(it[1]) > 1 else ""), "desc": txt if why == "" else "%s（%s）" % [txt, why], "icon": "e_event", "chips": chips, "cat": "本因 · %s · %s  CAUSE" % [CN_COL.get(str(b.color), ""), CN_RAR.get(str(b.rarity), "")], "col": COLS.get(str(b.color), Color.WHITE)}
		if why != "":
			o.disabled = true
		return o)
	g.panel_ui.show_choices("宣告「%s」· 选本因" % boards[lid].name, opts, "mech", "时机：" + timing_text(lid), true)


func _pick_panel(of: Array) -> void:
	_ui.step = "P"
	var opts: Array = []
	for t in of:
		opts.append({"kind": "mech", "mech": id, "id": "P:" + str(t), "name": TIMING_CN.get(str(t), str(t)), "desc": "这一份在%s生效" % TIMING_CN.get(str(t), str(t)), "icon": "e_event", "chips": [], "cat": "时机  TIMING", "col": Color(0.42, 0.66, 1.0)})
	opts.append(_cancel())
	g.panel_ui.show_choices("宣告「%s · %s」· 自选时机" % [boards[_ui.lid].name, boards[_ui.eid].name], opts, "mech", "这块布局要你选一次在什么时候生效", true)


## progression.pick 在 choice_kind == "mech" 时转到这里
func choice_pick(i: int) -> void:
	var o: Dictionary = g.choices[i]
	var oid: String = str(o.get("id", ""))
	if oid == "back":
		_end_panel()
		return
	if o.get("disabled", false):
		Sfx.play("ui_move", -6.0, 0.7)
		return
	Sfx.play("ui_ok", -6.0)
	if oid == "next":
		_ui.page = int(_ui.get("page", 0)) + 1
		if str(_ui.step) == "E":
			_effects_panel(str(_ui.lid))
		else:
			_show_layouts()
		return
	if oid.begins_with("L:"):
		_effects_panel(oid.substr(2))
	elif oid.begins_with("E:"):
		_ui.eid = oid.substr(2)
		_ui.specs = pick_specs(str(_ui.lid))
		_next_pick()
	elif oid.begins_with("P:"):
		_ui.picks.append(oid.substr(2))
		_next_pick()


func _next_pick() -> void:
	var done: int = (_ui.picks as Array).size()
	if done < (_ui.specs as Array).size():
		_pick_panel(_ui.specs[done])
		return
	var lid: String = _ui.lid
	var eid: String = _ui.eid
	var picks: Array = _ui.picks
	_end_panel()
	declare(lid, eid, picks)


func _end_panel() -> void:
	_ui = {}
	g.panel.visible = false
	g.state = g.S.PLAY
	g.check_pending()


# ---------- 画面（占位） ----------

func draw_ground(_w) -> void:
	var cv = g.wcv
	var f: Font = ThemeDB.fallback_font
	var nl: int = layouts().size()
	var ne: int = effects().size()
	if nl + ne > 0 or not wins.is_empty():
		var np: int = pairs().size()
		var s: String = "密文板 布局 %d · 本因 %d%s" % [nl, ne, ("  · 可宣告 %d 对 [T]" % np) if np > 0 else ""]
		cv.draw_string(f, g.ppos + Vector2(-90, 60), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.75, 0.88, 1.0, 0.85))
		var row := 0
		for w in wins:
			if w.st == "on":
				var left: float = float(w.end) - g.t
				cv.draw_string(f, g.ppos + Vector2(-90, 74 + row * 12), "%s%s" % [w.name, (" %d 秒" % int(left)) if left < 999.0 else ""], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.9, 0.6, 0.8))
				row += 1
	_shots = _shots.filter(func(x): return g.t - float(x[1]) < 0.08)
	for sh in _shots:
		cv.draw_line(g.ppos + Vector2(-26, -58), sh[0], Color(1.0, 0.85, 0.5, 0.9), 2.0)
	for d in drones:
		var p: Vector2 = g.ppos + Vector2(-26, -58) + Vector2(0, sin(g.t * 4.0) * 3.0)
		cv.draw_circle(p, 6.0, Color(1.0, 0.85, 0.5, 0.9))
		cv.draw_arc(p, 9.0, 0.0, TAU, 16, Color(1.0, 0.95, 0.8, 0.7), 1.5)
	for gd in guards:
		cv.draw_circle(gd.pos, 14.0, Color(0.42, 0.66, 1.0, 0.85))
		cv.draw_arc(gd.pos, float(T.get("allies", {}).get("guard", {}).get("taunt_r", 180)), 0.0, TAU, 48, Color(0.42, 0.66, 1.0, 0.25), 1.5)
		cv.draw_rect(Rect2(gd.pos + Vector2(-16, -24), Vector2(32.0 * float(gd.hp) / maxf(1.0, float(gd.maxhp)), 3)), Color(0.5, 1.0, 0.6, 0.9))


## 批跑遥测（telemetry 收进 BALANCE 行的 mech_totem）
func report() -> Dictionary:
	return {"decl": log_decl.size(), "syn": log_decl.filter(func(x): return x[3]).size(), "drops": drops, "held": hand.size(), "log": log_decl.duplicate(), "uses": uses.duplicate()}
