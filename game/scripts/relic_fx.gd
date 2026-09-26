## 藏品效果解释器（从 data/relic_effects.json 的 effects 数组落到 game.gd 的变量与钩子上）
## 数据：scripts/core/relic_db.gd 读取 data/relics.json + data/relic_effects.json；本文件只负责"生效"。
## 支持的 effect：
##   stat    {stat, op: add|mult|flat, value, scope?} —— 见 _apply_stat；scope 为 class:<职业> / range:近战|远程 时只对对应干员生效
##   trigger {event, if, do, args}              —— 由 game.gd 在对应时机调用 on_*()
##   status  {status: bind|stun, args.dot_mult} —— 受控敌人每秒受法术伤害
##   spawn   {every, do: spawn, args.what}      —— 周期生成（地雷）
##   rule    {rule, value, args?}               —— 开关型规则，game.gd 查询 rule()；squad_scale / lone_haste 按编队构成生效（refresh_squad）
##   on_gain {do, args}                         —— 获得时执行一次：light / ingots / heal / shield_fill / growth_pick /
##                                                 advance_class / silver_seal / extra_slot / contract / rejection / recruit_knight
## 条目字段 requires_class（docs/35）：编队里有其中任一职业时才会出现在三选一 / 商店。
extends RefCounted

const D = preload("res://scripts/data.gd")
const RelicDb = preload("res://scripts/core/relic_db.gd")
const Bal = preload("res://scripts/core/balance.gd")

var g
var db: RefCounted
var rules := {}            # rule -> value
var temps: Array = []      # 限时修正 {stat, value, until}
var timers: Array = []     # 周期生成 {every, left, what}
var mines: Array = []      # 地雷 {pos, life}
var dot_mult := 0.0        # 受控敌人每秒法术伤害（基础伤害倍数）
var _haste_last := 1.0     # 上次写入的攻速藏品倍率
var dot_tick := 0.0
var perm_dmg := 0.0        # 刻勋之手：击杀永久累加（上限 0.3）
var tulip_t := 0.0         # 黑色郁金香：技能未生效的持续时间
var no_hurt_t := 0.0       # 深蓝之树：连续未受伤时间
var stun_all_cd := 0.0
var revived := false
var king_n := 0            # 国王套装件数
var lv := {}               # id -> 等级（纯属性型藏品可叠到 3 级，每级效果递减 100% / 70% / 50%）
const LV_SCALE := [1.0, 0.7, 0.5]
# ---- docs/35 新增
var sp_budget := {}        # 按「藏品:干员」计的本秒已回复技力（每秒上限），每秒清零
var sp_budget_t := 0.0
var wrath_cd := 0.0        # 岁怒：冷却到 0 后，下一次追击引爆
var wrath_q: Array = []    # 岁怒：待引爆的位置（下一帧结算，避免在伤害结算里递归）
var shatter := 0           # 碎靶之手：术师命中叠层
var shatter_t := 0.0       # 最近一次术师命中的时间
var coin_q: Array = []     # 古高卢银币：{t, op} 技能结束时给该干员回技力
var dust_t := 0.0          # 净尘之手计时
var overheal := 0.0        # 食腐者手杖：累计溢出回复
var overheal_t := 0.0
var home_pos := Vector2.INF   # 遥乡之引：区域中心
var home_t := 0.0             # 距下次换位置
var contract_op := ""      # 生还者合约：被选中的干员
var hurt_sp_cd := 0.0      # 铁卫-无锋：受击回技力冷却
const HOME_R := 95.0
const CLASSES := ["先锋", "近卫", "重装", "狙击", "术师", "医疗", "辅助", "特种"]


func _init(game) -> void:
	g = game
	db = RelicDb.new()
	db.load_files()


## 供 game.gd 建表：id -> {name, cat, desc, rarity, tags, lanes, requires, conflicts, requires_class, shop_allowed, price_class}
func table() -> Dictionary:
	var out := {}
	for r in db.implemented():
		out[r.id] = r
	return out


func has(id: String) -> bool:
	return db.items.has(id) and db.items[id].implemented


func rule(name: String) -> int:
	return int(rules.get(name, 0))


## 纯属性型藏品可升到 3 级；带触发 / 规则 / 一次性效果的只有 1 级
func max_lv(id: String) -> int:
	var r: Dictionary = db.get_relic(id)
	if r.is_empty():
		return 1
	if int(r.get("max_lv", 0)) > 0:
		return int(r.max_lv)
	if r.rarity in ["升华", "遭诅古物", "结局"]:
		return 1
	for ef in r.effects:
		if ef.get("type", "stat") != "stat":
			return 1
	return 3


## 能否出现在三选一 / 商店：未拥有，或已拥有但还能升级；前置条件按拥有判断；职业门槛按当前编队判断
func can_offer(r: Dictionary, for_shop: bool) -> bool:
	if for_shop and not r.shop_allowed:
		return false
	if not for_shop and r.rarity == "遭诅古物":
		return false
	if r.rarity == "结局" or r.get("source", "any") == "event":
		return false
	if g.relics.has(r.id) and lv.get(r.id, 0) >= max_lv(r.id):
		return false
	for q in r.requirements:
		if not g.relics.has(str(q)):
			return false
	for c in r.conflicts:
		if g.relics.has(str(c)):
			return false
	var rc: Array = r.get("requires_class", [])
	if not rc.is_empty() and not g.squad.ops.any(func(o): return o.cls in rc):
		return false
	for ef in r.effects:
		match ef.get("do", ""):
			"extra_slot":
				# 编队上限类（每局最多一次）：第 4 位已解锁（藏品或事件）就不再出现
				if g.squad.extra_slot:
					return false
			"advance_class":
				# 典训：该职业里没有能推进的干员就不出（避免废卡）
				if _advance_target(str(ef.get("args", {}).get("class", ""))) == null:
					return false
	return true


func display_name(id: String) -> String:
	var r: Dictionary = db.get_relic(id)
	var cur: int = lv.get(id, 0)
	return r.name + ("  Lv.%d → %d" % [cur, cur + 1] if cur > 0 else ("  (可升级)" if max_lv(id) > 1 else ""))


func display_desc(id: String) -> String:
	var r: Dictionary = db.get_relic(id)
	var cur: int = lv.get(id, 0)
	if cur > 0:
		return "%s\n（可叠加，本级 %d%%）" % [r.desc, int(LV_SCALE[cur] * 100.0)]
	return r.desc


## ---------- 获得藏品 ----------
func apply(id: String) -> void:
	var r: Dictionary = db.get_relic(id)
	if r.is_empty():
		return
	var cur: int = lv.get(id, 0)
	if cur >= max_lv(id):
		return
	lv[id] = cur + 1
	var sc: float = LV_SCALE[cur]
	if cur > 0:
		# 升级：只重复属性型效果（按递减系数）
		for ef in r.effects:
			if ef.get("type", "stat") == "stat":
				_apply_stat(ef.stat, ef.get("op", "add"), float(ef.value) * sc if ef.get("op", "add") != "mult" else 1.0 - (1.0 - float(ef.value)) * sc, "relic:" + id, ef.get("scope", ""))
		g._add_text(g.ppos + Vector2(0, -96), "%s Lv.%d" % [r.name, cur + 1], Color(1.0, 0.9, 0.5), 16)
		return
	if r.tags.has("king"):
		king_n += 1
	var squad_dep := false
	for ef in r.effects:
		match ef.get("type", "stat"):
			"stat":
				_apply_stat(ef.stat, ef.get("op", "add"), float(ef.value), "relic:" + id, ef.get("scope", ""))
			"rule":
				rules[ef.rule] = rules.get(ef.rule, 0) + int(ef.get("value", 1))
				if ef.rule in ["squad_scale", "lone_haste"]:
					squad_dep = true
				if ef.rule == "deep_sea":
					g.lamp_cap = 70.0
					g.lamp = minf(g.lamp, g.lamp_cap)
				if ef.rule == "shield_burst":
					g.shield_burst = true
				elif ef.rule == "shield_heal":
					g.shield_heal = true
			"status":
				dot_mult = maxf(dot_mult, float(ef.get("args", {}).get("dot_mult", 0.0)))
			"spawn":
				timers.append({"every": float(ef.every), "left": float(ef.get("first", ef.every)), "what": ef.get("args", {}).get("what", "mine")})
			"on_gain":
				_on_gain(str(ef.do), ef.get("args", {}))
			"trigger":
				pass  # 触发型由 on_*() 钩子按 id 查询
	if squad_dep:
		refresh_squad()


func _on_gain(what: String, args: Dictionary) -> void:
	var amt: float = float(args.get("amount", 0))
	match what:
		"light":
			# 扣灯火最低降到 10，不清零
			g.lamp = clampf(g.lamp + amt, 10.0 if amt < 0.0 else 0.0, g.lamp_cap)
			g._add_text(g.ppos + Vector2(0, -90), "灯火 %+d" % int(amt), Color(1.0, 0.8, 0.45), 16)
		"rejection":
			var what2: String = g.doctor.apply_rejection()
			g._show_banner("排异反应：%s" % what2)
			g.fx.append({"kind": "rays", "pos": g.ppos, "life": 0.9, "max": 0.9, "col": Color(0.7, 0.4, 1.0)})
			Sfx.play("roar", -6.0, 1.4, 0.0)
		"recruit_knight":
			g.knight_alive = true
			g._show_banner("猎潮的骑士 加入了你的旅程")
		"ingots":
			g.ingots += int(amt)
			g._add_text(g.ppos + Vector2(0, -90), "源石锭 +%d" % int(amt), Color(1.0, 0.85, 0.4), 16)
		"heal":
			# amount = 最大生命的比例
			g._heal(g.max_hp * amt, "藏品")
			g._add_text(g.ppos + Vector2(0, -90), "生命 +%d%%" % int(amt * 100.0), Color(0.55, 1.0, 0.6), 16)
		"shield_fill":
			if g.shield_max > 0:
				g.shield = g.shield_max
		"growth_pick":
			g.pending_levelups += 1
			g._show_banner("获得一次成长三选一")
		"advance_class":
			var cls: String = str(args.get("class", ""))
			var o = _advance_target(cls)
			if o == null:
				g.pending_levelups += 1
				g._show_banner("典训：没有可推进的%s干员，改为一次成长三选一" % cls)
			else:
				o.advance("")
				g._show_banner("典训：%s 推进一个成长节点" % o.display_name())
		"silver_seal":
			_silver_seal()
		"extra_slot":
			g.squad.extra_slot = true
			g._show_banner("编队上限 +1")
		"contract":
			_contract_start()


## 典训的推进对象：该职业里下一个节点可用、进度最少的干员
func _advance_target(cls: String):
	var best = null
	for o in g.squad.ops:
		if o.cls != cls:
			continue
		var n: Dictionary = o.next_node()
		if n.is_empty() or not o.node_available(n):
			continue
		if best == null or o.prog < best.prog:
			best = o
	return best


## 博士银印：招募一名随机干员并直接推进到精一；编队已满时全队各推进 1 个节点
func _silver_seal() -> void:
	var cards: Array = g._recruit_cards()
	if not cards.is_empty():
		var c: Dictionary = cards[g.rng.randi() % cards.size()]
		var o = g.squad.add(c.id)
		if o != null:
			var guard := 0
			while o.elite < 1 and not o.next_node().is_empty() and guard < 8:
				o.advance("")
				guard += 1
			g._show_banner("博士银印：「%s」以精英一阶段加入编队" % o.display_name())
			return
	for o in g.squad.ops:
		var n: Dictionary = o.next_node()
		if not n.is_empty() and o.node_available(n):
			o.advance("")
	g._show_banner("博士银印：全队各推进一个成长节点")


## 生还者合约：随机一名干员伤害 +20%，此后每击败一个 Boss 再 +20%
func _contract_start() -> void:
	if g.squad.ops.is_empty():
		return
	var o = g.squad.ops[g.rng.randi() % g.squad.size()]
	contract_op = o.id
	g.stats.add(&"dmg", "add", 0.2, "relic:261", "op:" + o.id)
	g._sync_stats()
	g._show_banner("生还者合约：%s 伤害 +20%%" % o.display_name())


## stat 名 -> 属性块（core/stat_defs.gd）。add = 百分比加算；mult = 直接乘；flat = 直接加
## 数据里的别名："regen"（按最大生命百分比）→ regen_pct
const STAT_ALIAS := {"regen": &"regen_pct"}


func _apply_stat(stat: String, op: String, v: float, source := "relic", scope := "") -> void:
	var name: StringName = STAT_ALIAS.get(stat, StringName(stat))
	if stat == "regen":
		v *= 0.01
	if not g.stats.has_stat(name):
		push_warning("未知藏品属性: " + stat)
		return
	g.stats.add(name, op, v, source, scope)
	g._sync_stats()


## 按编队构成生效的藏品（协议 / 老蒲扇 / 断杖-破解 / 支柱-援护 / 极速之手）：编队变化与获得时重算
##   squad_scale {stat, per, count: [职业…] | "distinct", classes?: [职业…], cap?}
##     n = 编队里 count 职业的人数（distinct = 不同职业数，上限 cap），效果 per × n；classes 给了就只加到这些职业的干员
##   lone_haste  {solo, value}：编队只有 1 人时全队攻速 +solo，否则 +value
func refresh_squad() -> void:
	if g.stats == null:
		return
	g.stats.remove_source("relic_squad")
	var classes: Array = g.squad.ops.map(func(o): return o.cls)
	for id in g.relics:
		var r: Dictionary = db.get_relic(id)
		for ef in r.get("effects", []):
			if ef.get("type", "") != "rule":
				continue
			var a: Dictionary = ef.get("args", {})
			match ef.rule:
				"squad_scale":
					var n := 0
					var cnt = a.get("count", [])
					if cnt is String and cnt == "distinct":
						var seen := {}
						for c in classes:
							seen[c] = true
						n = seen.size()
					else:
						for c in classes:
							if c in cnt:
								n += 1
					n = mini(n, int(a.get("cap", 99)))
					if n <= 0:
						continue
					var v: float = float(a.get("per", 0.0)) * n
					var scs: Array = a.get("classes", [])
					if scs.is_empty():
						g.stats.add(StringName(a.stat), "add", v, "relic_squad")
					else:
						for c in scs:
							g.stats.add(StringName(a.stat), "add", v, "relic_squad", "class:" + str(c))
				"lone_haste":
					var v2: float = float(a.get("solo", 0.0)) if g.squad.size() <= 1 else float(a.get("value", 0.0))
					g.stats.add(&"op_aspd", "add", v2, "relic_squad")
	g._sync_stats()


## ---------- 每帧 ----------
func tick(dt: float) -> void:
	# 限时修正过期
	if not temps.is_empty():
		temps = temps.filter(func(x): return x.until > g.t)
	# 攻速类藏品（国王的新枪 / 投币玩具）：对全队生效，写进 op_aspd（变化时才重写，避免每帧刷新属性）
	var hm := umbrella_interval_mult()
	if absf(hm - _haste_last) > 0.001:
		_haste_last = hm
		g.stats.remove_source("relic_haste")
		if absf(hm - 1.0) > 0.001:
			g.stats.add(&"op_aspd", "mult", 1.0 / hm, "relic_haste")
		g._sync_stats()
	# 黑色郁金香：技能未生效时累计，最多 60 秒
	if rule("black_tulip") > 0:
		if g.squad.any_skill_active():
			tulip_t = 0.0
		else:
			tulip_t = minf(60.0, tulip_t + dt)
	# 深蓝之树：连续 60 秒未受伤 → 灯火 +15
	if rule("tree_light") > 0:
		no_hurt_t += dt
		if no_hurt_t >= 60.0:
			no_hurt_t = 0.0
			g.lamp = minf(100.0, g.lamp + 15.0)
			g._add_text(g.ppos + Vector2(0, -90), "深蓝之树 · 灯火 +15", Color(0.5, 0.8, 1.0), 15)
	stun_all_cd -= dt
	hurt_sp_cd -= dt
	wrath_cd -= dt
	# 每秒技力上限计量
	sp_budget_t -= dt
	if sp_budget_t <= 0.0:
		sp_budget_t = 1.0
		sp_budget.clear()
	# 岁怒：上一帧追击命中登记的引爆
	if not wrath_q.is_empty():
		var q: Array = wrath_q
		wrath_q = []
		for p in q:
			_wrath_blast(p)
	# 碎靶之手：3 秒没有术师命中就清空
	if shatter > 0 and g.t - shatter_t > 3.0:
		shatter = 0
	# 古高卢银币：技能结束时该干员回复技力
	if not coin_q.is_empty():
		var keep: Array = []
		for c in coin_q:
			if g.t >= c.t:
				if c.op != null and g.squad.ops.has(c.op):
					c.op.gain_sp(Bal.v("relic/coin_sp", 0.08))
			else:
				keep.append(c)
		coin_q = keep
	# 净尘之手：医疗干员每秒灼烧身边敌人
	if g.relics.has("174"):
		dust_t -= dt
		if dust_t <= 0.0:
			dust_t = 1.0
			_dust()
	# 食腐者手杖：溢出回复每 0.5 秒结算一次
	if overheal > 0.0:
		overheal_t -= dt
		if overheal_t <= 0.0:
			overheal_t = 0.5
			_scavenge()
	# 遥乡之引
	if g.relics.has("116"):
		_tick_home(dt)
	# 周期生成：地雷
	for tm in timers:
		tm.left -= dt
		if tm.left <= 0.0:
			tm.left = tm.every
			if tm.what == "mine":
				mines.append({"pos": g.ppos + Vector2(0, 6), "life": 40.0})
				g.fx.append({"kind": "ring", "pos": g.ppos, "r": 24.0, "life": 0.4, "max": 0.4, "col": Color(1.0, 0.7, 0.3)})
	for mn in mines:
		mn.life -= dt
		if mn.life <= 0.0:
			continue
		for j in g._query(mn.pos, 40.0):
			var e: Dictionary = g.enemies[j]
			if not e.dead and not e.chest and e.pos.distance_to(mn.pos) < e.r + 14.0:
				_explode_mine(mn)
				break
	mines = mines.filter(func(x): return x.life > 0.0)
	# 受控敌人持续法术伤害
	if dot_mult > 0.0:
		dot_tick -= dt
		if dot_tick <= 0.0:
			dot_tick = 0.5
			var per: float = 18.0 * (g.ch.u_dmg_mult if "u_dmg_mult" in g.ch else 1.0) * g.dmg_mult * dot_mult * 0.5
			g._hit("藏品")
			for e in g.enemies:
				if not e.dead and not e.chest and (e.stun > 0.0 or e.slow > 0.0) and e.pos.distance_squared_to(g.ppos) < 700.0 * 700.0:
					g._damage(e, per)


func _explode_mine(mn: Dictionary) -> void:
	mn.life = 0.0
	var r := 95.0
	g._hit("地雷")
	for j in g._query(mn.pos, r + 20.0):
		var e: Dictionary = g.enemies[j]
		if not e.dead and e.pos.distance_to(mn.pos) < r + e.r:
			g._damage(e, 60.0 * g.dmg_mult)
			if not e.boss:
				e.kb += (e.pos - mn.pos).normalized() * 360.0
	g.fx.append({"kind": "explode", "pos": mn.pos, "r": r, "life": 0.4, "max": 0.4, "col": Color(1.0, 0.6, 0.3)})
	g._sparks(mn.pos, Vector2.ZERO, Color(1.0, 0.7, 0.4), 14, 260.0)
	g._shake(0.5)
	Sfx.play("boom", -6.0, 1.0, 0.05)


## 藏品直接伤害的范围结算（岁怒 / 净尘 / 食腐）：不打宝箱，结算后恢复原描述符
func _area(src: String, p: Vector2, r: float, dmg: float) -> void:
	var keep: Dictionary = g.hit
	g._hit(src)
	for j in g._query(p, r + 24.0):
		var e: Dictionary = g.enemies[j]
		if not e.dead and not e.chest and e.pos.distance_to(p) < r + e.r:
			g._damage(e, dmg)
	g.hit = keep


## 岁怒：追击命中处引爆一次大范围法术伤害（按敌人生命的时间倍率缩放）
func _wrath_blast(p: Vector2) -> void:
	var r := 130.0
	_area("岁怒", p, r, Bal.v("relic/wrath_dmg", 30.0) * g.enemy_hp_time_mult())
	g.fx.append({"kind": "explode", "pos": p, "r": r, "life": 0.45, "max": 0.45, "col": Color(1.0, 0.45, 0.3)})
	g._sparks(p, Vector2.ZERO, Color(1.0, 0.6, 0.35), 16, 280.0)
	Sfx.play("boom", -8.0, 0.8, 0.05)


## 净尘之手：每名医疗干员对身边 120 内的敌人造成法术伤害（约其攻击力的 50%）
func _dust() -> void:
	for o in g.squad.ops:
		if o.cls != "医疗" or o.pos == Vector2.INF:
			continue
		var dmg: float = Bal.v("relic/dust_dmg", 10.0) * g.enemy_hp_time_mult() * o._dmg_bonus()
		_area("净尘", o.pos, 120.0, dmg)
		g.fx.append({"kind": "ring", "pos": o.pos, "r": 120.0, "life": 0.35, "max": 0.35, "col": Color(0.85, 1.0, 0.9, 0.45)})


## 溢出回复登记（game.gd _heal / 自然回复调用）
func on_overheal(v: float) -> void:
	if g.relics.has("102"):
		overheal += v


## 食腐者手杖：把累计的溢出回复转成主控身边的法术伤害
func _scavenge() -> void:
	var amt := overheal
	overheal = 0.0
	var dmg: float = amt * Bal.v("relic/scavenge_mult", 4.0) * g.enemy_hp_time_mult()
	if dmg < 1.0:
		return
	_area("食腐", g.ppos, 150.0, dmg)
	g.fx.append({"kind": "ring", "pos": g.ppos, "r": 150.0, "life": 0.3, "max": 0.3, "col": Color(0.6, 1.0, 0.55, 0.4)})


## 遥乡之引：区域每 60 秒换一次位置（主控身边 220–360，且在黑潮圈内）；站在里面每秒回复 3% 生命、技力回复 +30%
func _tick_home(dt: float) -> void:
	home_t -= dt
	if home_pos == Vector2.INF or home_t <= 0.0:
		home_t = 60.0
		var p: Vector2 = g.ppos
		for k in 8:
			p = g.ppos + Vector2.from_angle(g.rng.randf() * TAU) * g.rng.randf_range(220.0, 360.0)
			if p.distance_to(g.zone_c) < g.zone_r - HOME_R:
				break
		home_pos = p
		g.fx.append({"kind": "ring", "pos": home_pos, "r": HOME_R, "life": 0.8, "max": 0.8, "col": Color(0.5, 1.0, 0.9)})
	if in_home():
		g._heal(g.max_hp * 0.03 * dt, "遥乡")


func in_home() -> bool:
	return home_pos != Vector2.INF and g.ppos.distance_to(home_pos) < HOME_R


func draw() -> void:
	for mn in mines:
		var bl: float = 0.5 + 0.5 * sin(g.t * 8.0)
		g.draw_set_transform(mn.pos, 0.0, Vector2(1.0, 0.6))
		g.draw_circle(Vector2.ZERO, 9.0, Color(0.25, 0.22, 0.2))
		g.draw_circle(Vector2.ZERO, 4.0, Color(1.0 + bl, 0.5 + bl * 0.5, 0.3, 0.8))
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 遥乡：地面上一片淡青色的圈，呼吸光
	if home_pos != Vector2.INF and g.relics.has("116"):
		var bl2: float = 0.5 + 0.5 * sin(g.t * 2.5)
		var inside := in_home()
		g.draw_set_transform(home_pos, 0.0, Vector2(1.0, 0.55))
		g.draw_circle(Vector2.ZERO, HOME_R, Color(0.4, 1.0, 0.85, 0.07 + 0.05 * bl2 + (0.06 if inside else 0.0)))
		g.draw_arc(Vector2.ZERO, HOME_R, 0.0, TAU, 48, Color(0.55, 1.0, 0.9, 0.45 + 0.25 * bl2), 2.0)
		g.draw_arc(Vector2.ZERO, HOME_R * (0.35 + 0.6 * fmod(g.t * 0.4, 1.0)), 0.0, TAU, 40, Color(0.7, 1.0, 0.95, 0.35 * (1.0 - fmod(g.t * 0.4, 1.0))), 1.5)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## ---------- 动态倍率（每次伤害查询）----------
## 额外伤害倍率：限时修正 + 国王的冠冕 + 黑色郁金香 + 刻勋之手
func dmg_extra() -> float:
	var m := 1.0 + perm_dmg
	for x in temps:
		if x.stat == "dmg":
			m *= 1.0 + x.value
	if rule("king_crown") > 0 and g.hp < g.max_hp * 0.3:
		m *= 2.5 if king_n >= 3 else 1.5
	if rule("black_tulip") > 0 and tulip_t > 0.0:
		m *= 1.0 + 0.6 * tulip_t / 60.0
	return m


## 追击与召唤物的额外倍率：无字珊瑚（灯火低于 30）
func followup_extra() -> float:
	return 1.0 + Bal.v("relic/coral_followup", 0.6) if g.relics.has("246") and g.lamp < 30.0 else 1.0


## 按命中描述符的倍率：碎靶之手（术师叠层）、荣耀绶带（不带范围效果的单体攻击）
func hit_mult(h: Dictionary) -> float:
	var m := 1.0
	if shatter > 0 and h.get("class", "") == "术师" and g.relics.has("175"):
		m *= 1.0 + 0.05 * shatter
	if g.relics.has("112") and not h.tags.has("area") and h.get("origin", "") != "relic":
		m *= 1.6
	return m


## 攻击间隔倍率（<1 更快）：国王的新枪、投币玩具 / 骑士戒律（极速之手改为按编队人数生效，见 refresh_squad）
func umbrella_interval_mult() -> float:
	var m := 1.0
	if rule("king_gun") > 0 and g.hp < g.max_hp * 0.3:
		m *= 0.667
	var coin: int = rule("coin_toy")
	if coin > 0:
		var cap: float = 0.3 if coin == 3 else 0.5
		m /= 1.0 + minf(cap, float(g.ingots / 5) * coin * 0.01)
	return m


## 受伤倍率：佣兵保单（低灯火）、国王的圆饼
func taken_mult() -> float:
	var m: float = g.dmg_taken_mult
	if g.relics.has("255") and g.lamp < 50.0:
		m *= 0.75
	if rule("king_cake") > 0 and g.hp < g.max_hp * 0.3:
		m *= 0.7
	if rule("bone_blood") > 0:
		m *= 1.8
	return m


## 技力回复倍率：火油与药膏、国王的枝条、遥乡之引
func sp_extra() -> float:
	var m := 1.0
	if rule("low_light_sp") > 0 and g.lamp < 30.0:
		m *= 1.4
	if rule("king_branch") > 0 and g.hp < g.max_hp * 0.3:
		m *= 1.5
	if g.relics.has("116") and in_home():
		m *= 1.3
	return m


## ---------- 事件钩子（game.gd 调用）----------
func on_dodge() -> void:
	if g.relics.has("121"):
		_temp("dmg", 1.3, 6.0)
	elif g.relics.has("120"):
		_temp("dmg", 0.7, 6.0)


## 技能开始（character.spend_sp）：o 为施放的干员，i 为技能序号
func on_skill_start(o = null, i := -1) -> void:
	if g.relics.has("110"):
		_temp("dmg", 0.6, 3.0)
	if g.relics.has("111"):
		_temp("dmg", 1.0, 1.0)
	if g.relics.has("85") and o != null and i >= 0:
		coin_q.append({"t": g.t + float(o.skill_def(i).get("dur", 0.0)), "op": o})
	tulip_t = 0.0


func on_hurt(src_corrode: bool) -> void:
	no_hurt_t = 0.0
	if g.relics.has("94"):
		_gain_sp(0.03 + (0.03 if src_corrode else 0.0))
	if g.relics.has("145") and hurt_sp_cd <= 0.0:
		hurt_sp_cd = 0.5
		for o in g.squad.ops:
			if o.cls == "重装":
				o.gain_sp(Bal.v("relic/iron_sp", 0.05))
	if g.relics.has("231") and stun_all_cd <= 0.0:
		stun_all_cd = 30.0
		for e in g.enemies:
			if not e.dead and not e.chest and not e.boss:
				e.stun = maxf(e.stun, 5.0)
		g.fx.append({"kind": "rays", "pos": g.ppos, "life": 0.7, "max": 0.7, "col": Color(1.0, 0.9, 0.6)})
		g._show_banner("小格兰法洛：全场晕眩")
		Sfx.play("skill", -2.0, 0.7)


## 生命归零：时光之末复活一次。返回 true 表示已复活
func on_death() -> bool:
	if g.relics.has("228") and not revived:
		revived = true
		g.hp = g.max_hp * 0.5
		g.invuln = 2.0
		g.fx.append({"kind": "rays", "pos": g.ppos, "life": 0.9, "max": 0.9, "col": Color(1.0, 0.85, 0.5)})
		g._show_banner("时光之末 —— 主控干员重新站了起来")
		Sfx.play("levelup", 0.0, 0.7)
		return true
	return false


func on_kill(e: Dictionary) -> void:
	if g.relics.has("252"):
		perm_dmg = minf(0.3, perm_dmg + 0.001)
	# 生还者合约：每击败一个 Boss，被选中的干员再 +20%
	if e.get("boss", false) and not e.get("dead", false) and contract_op != "" and g.relics.has("261"):
		g.stats.add(&"dmg", "add", 0.2, "relic:261", "op:" + contract_op)
		g._sync_stats()
		g._show_banner("生还者合约：伤害再 +20%")


## 旧接口（水月伞击调用）：荣耀绶带已改为按描述符生效（hit_mult），这里恒为 1，避免重复加成
func single_hit_mult(_hit_count: int) -> float:
	return 1.0


## 任意命中（带伤害描述符）。藏品自己造成的伤害（origin == relic）不再触发藏品，避免连锁
func on_hit(e: Dictionary, h: Dictionary) -> void:
	if h.get("origin", "") == "relic":
		return
	if g.relics.has("229"):
		_budget_sp("229", "", 0.002, Bal.v("relic/judge_cap", 0.03))
	var cls: String = h.get("class", "")
	if cls == "近卫" and g.relics.has("139"):
		_budget_sp("139", h.get("op", ""), 0.0025, 0.02)
	if cls == "术师" and g.relics.has("175"):
		shatter = mini(15, shatter + 1)
		shatter_t = g.t
	if not g.is_followup(h):
		return
	# 追击命中：扣挠之手（目标当前生命 2%，Boss 0.5%，每个敌人每 0.5 秒一次）
	if g.relics.has("170") and not e.dead and g.t >= float(e.get("claw_t", 0.0)):
		e["claw_t"] = g.t + 0.5
		var keep: Dictionary = g.hit
		g._hit("真实")
		g._damage(e, e.hp * (0.005 if e.boss else 0.02))
		g.hit = keep
	# 炸裂之手：造成这次追击的干员回技力（每秒最多 2.5%）
	if g.relics.has("171"):
		_budget_sp("171", h.get("op", ""), 0.005, 0.025)
	# 岁怒：冷却好了就在这次追击的目标处引爆
	if g.relics.has("234") and wrath_cd <= 0.0:
		wrath_cd = 8.0
		wrath_q.append(e.pos)


## 狙击命中：扼喉之手处决（狙击干员的任意命中）
func sniper_execute(e: Dictionary, h: Dictionary) -> bool:
	return g.relics.has("169") and h.get("class", "") == "狙击" and not e.boss and e.hp < e.maxhp * 0.2


func _temp(stat: String, value: float, dur: float) -> void:
	temps.append({"stat": stat, "value": value, "until": g.t + dur})


## 藏品回技力：全队干员按各自需求的百分比充能
func _gain_sp(pct: float) -> void:
	g.squad.gain_sp(pct)


## 带每秒上限的回技力：oid 为空时全队，否则只给该干员；上限按「藏品:干员」分别计
func _budget_sp(rid: String, oid: String, pct: float, cap: float) -> void:
	var key := rid + ":" + oid
	var used: float = sp_budget.get(key, 0.0)
	if used >= cap:
		return
	var add := minf(pct, cap - used)
	sp_budget[key] = used + add
	if oid == "":
		g.squad.gain_sp(add)
	else:
		var o = g.squad.get_op(oid)
		if o != null:
			o.gain_sp(add)
