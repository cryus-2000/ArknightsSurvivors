## 藏品效果解释器（从 data/relic_effects.json 的 effects 数组落到 game.gd 的变量与钩子上）
## 数据：scripts/core/relic_db.gd 读取 data/relics.json + data/relic_effects.json；本文件只负责"生效"。
## 支持的 effect：
##   stat    {stat, op: add|mult|flat, value}   —— 见 _apply_stat 的映射表
##   trigger {event, if, do, args}              —— 由 game.gd 在对应时机调用 on_*()
##   status  {status: bind|stun, args.dot_mult} —— 受控敌人每秒受法术伤害
##   spawn   {every, do: spawn, args.what}      —— 周期生成（地雷）
##   rule    {rule, value}                      —— 开关型规则，game.gd 查询 rule()
##   on_gain {do: light|ingots, args.amount}    —— 获得时执行一次
extends RefCounted

const D = preload("res://scripts/data.gd")
const RelicDb = preload("res://scripts/core/relic_db.gd")

var g
var db: RefCounted
var rules := {}            # rule -> value
var temps: Array = []      # 限时修正 {stat, value, until}
var timers: Array = []     # 周期生成 {every, left, what}
var mines: Array = []      # 地雷 {pos, life}
var dot_mult := 0.0        # 受控敌人每秒法术伤害（伞击伤害倍数）
var dot_tick := 0.0
var perm_dmg := 0.0        # 刻勋之手：击杀永久累加（上限 0.3）
var tulip_t := 0.0         # 黑色郁金香：技能未生效的持续时间
var no_hurt_t := 0.0       # 深蓝之树：连续未受伤时间
var stun_all_cd := 0.0
var revived := false
var king_n := 0            # 国王套装件数
var lv := {}               # id -> 等级（纯属性型藏品可叠到 3 级，每级效果递减 100% / 70% / 50%）
const LV_SCALE := [1.0, 0.7, 0.5]


func _init(game) -> void:
	g = game
	db = RelicDb.new()
	db.load_files()


## 供 game.gd 建表：id -> {name, cat, desc, rarity, tags, requires, conflicts, shop_allowed, price_class}
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
	if r.is_empty() or r.rarity in ["升华", "遭诅古物"]:
		return 1
	for ef in r.effects:
		if ef.get("type", "stat") != "stat":
			return 1
	return 3


## 能否出现在三选一 / 商店：未拥有，或已拥有但还能升级；前置条件按拥有判断
func can_offer(r: Dictionary, for_shop: bool) -> bool:
	if for_shop and not r.shop_allowed:
		return false
	if not for_shop and r.rarity == "遭诅古物":
		return false
	if g.relics.has(r.id) and lv.get(r.id, 0) >= max_lv(r.id):
		return false
	for q in r.requirements:
		if not g.relics.has(str(q)):
			return false
	for c in r.conflicts:
		if g.relics.has(str(c)):
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
		return "%s\n（本级效果为 %d%%，可叠加）" % [r.desc, int(LV_SCALE[cur] * 100.0)]
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
				_apply_stat(ef.stat, ef.get("op", "add"), float(ef.value) * sc if ef.get("op", "add") != "mult" else 1.0 - (1.0 - float(ef.value)) * sc)
		g._add_text(g.ppos + Vector2(0, -96), "%s Lv.%d" % [r.name, cur + 1], Color(1.0, 0.9, 0.5), 16)
		return
	if r.tags.has("king"):
		king_n += 1
	for ef in r.effects:
		match ef.get("type", "stat"):
			"stat":
				_apply_stat(ef.stat, ef.get("op", "add"), float(ef.value))
			"rule":
				rules[ef.rule] = rules.get(ef.rule, 0) + int(ef.get("value", 1))
				if ef.rule == "shield_burst":
					g.shield_burst = true
				elif ef.rule == "shield_heal":
					g.shield_heal = true
			"status":
				dot_mult = maxf(dot_mult, float(ef.get("args", {}).get("dot_mult", 0.0)))
			"spawn":
				timers.append({"every": float(ef.every), "left": float(ef.get("first", ef.every)), "what": ef.get("args", {}).get("what", "mine")})
			"on_gain":
				var amt: float = float(ef.get("args", {}).get("amount", 0))
				match ef.do:
					"light":
						g.lamp = clampf(g.lamp + amt, 0.0, 100.0)
						g._add_text(g.ppos + Vector2(0, -90), "灯火 %+d" % int(amt), Color(1.0, 0.8, 0.45), 16)
					"ingots":
						g.ingots += int(amt)
						g._add_text(g.ppos + Vector2(0, -90), "源石锭 +%d" % int(amt), Color(1.0, 0.85, 0.4), 16)
			"trigger":
				pass  # 触发型由 on_*() 钩子按 id 查询


## stat 名 -> game.gd 变量
func _apply_stat(stat: String, op: String, v: float) -> void:
	var m: float = (1.0 + v) if op == "add" else v   # add = 百分比累加；mult = 直接乘；flat = 直接加
	match stat:
		"dmg": g.dmg_mult *= m
		"mizuki_umbrella_dmg": g.ch.u_dmg_mult *= m
		"mizuki_tentacle_mult": g.ch.t_mult *= m
		"ally_dmg": g.ally_mult *= m
		"arts_dmg": g.arts_mult *= m
		"enemy_dmg": g.enemy_dmg_mult *= m
		"enemy_hp": g.enemy_hp_mult *= m
		"enemy_atk_speed": g.enemy_cd_mult /= m
		"enemy_low_hp_dmg_taken": g.low_hp_bonus += v
		"regen": g.regen_pct += v * 0.01
		"dodge": g.dodge += v
		"dodge_phys": g.dodge_phys += v
		"dodge_arts": g.dodge_arts += v
		"melee_dmg": g.melee_mult *= m
		"ranged_dmg": g.ranged_mult *= m
		"phys_dmg": g.phys_mult *= m
		"armor": g.armor += v
		"weak_bonus": g.weak_bonus += v
		"arts_res": g.arts_res += v
		"sp_gain": g.sp_mult *= m
		"control_dur": g.control_mult *= m
		"shop_price": g.shop_price_mult *= m
		"light_decay": g.lamp_decay *= m
		"dmg_taken": g.dmg_taken_mult *= m
		"max_hp":
			g.max_hp = maxf(20.0, g.max_hp + v)
			g.hp = minf(g.hp + maxf(v, 0.0), g.max_hp)
		"shield_max":
			if g.shield_max == 0:
				g.shield_cd = 1.0
			g.shield_max += int(v)
		"shield_interval": g.shield_every *= m
		_:
			push_warning("未知藏品属性: " + stat)


## ---------- 每帧 ----------
func tick(dt: float) -> void:
	# 限时修正过期
	if not temps.is_empty():
		temps = temps.filter(func(x): return x.until > g.t)
	# 黑色郁金香：技能未生效时累计，最多 60 秒
	if rule("black_tulip") > 0:
		if g.ch.s2_active > 0.0 or g.ch.s3_active > 0.0:
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
			var per: float = 18.0 * g.ch.u_dmg_mult * g.dmg_mult * dot_mult * 0.5
			g.out_src = "藏品"
			for e in g.enemies:
				if not e.dead and not e.chest and (e.stun > 0.0 or e.slow > 0.0) and e.pos.distance_squared_to(g.ppos) < 700.0 * 700.0:
					g._damage(e, per)


func _explode_mine(mn: Dictionary) -> void:
	mn.life = 0.0
	var r := 95.0
	g.out_src = "地雷"
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


func draw() -> void:
	for mn in mines:
		var bl: float = 0.5 + 0.5 * sin(g.t * 8.0)
		g.draw_set_transform(mn.pos, 0.0, Vector2(1.0, 0.6))
		g.draw_circle(Vector2.ZERO, 9.0, Color(0.25, 0.22, 0.2))
		g.draw_circle(Vector2.ZERO, 4.0, Color(1.0 + bl, 0.5 + bl * 0.5, 0.3, 0.8))
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


## 挥伞间隔倍率（<1 更快）：极速之手、国王的新枪、投币玩具 / 骑士戒律
func umbrella_interval_mult() -> float:
	var m := 1.0
	if g.relics.has("172") and g.allies.is_empty():
		m *= 0.625
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
	return m


## 技力回复倍率：火油与药膏、国王的枝条
func sp_extra() -> float:
	var m := 1.0
	if rule("low_light_sp") > 0 and g.lamp < 30.0:
		m *= 1.4
	if rule("king_branch") > 0 and g.hp < g.max_hp * 0.3:
		m *= 1.5
	return m


## 触手追击目标加成：无字珊瑚（低灯火）
func tentacle_targets_extra() -> int:
	return 1 if g.relics.has("246") and g.lamp < 30.0 else 0


## ---------- 事件钩子（game.gd 调用）----------
func on_dodge() -> void:
	if g.relics.has("121"):
		_temp("dmg", 1.3, 6.0)
	elif g.relics.has("120"):
		_temp("dmg", 0.7, 6.0)


func on_skill_start() -> void:
	if g.relics.has("110"):
		_temp("dmg", 0.6, 3.0)
	tulip_t = 0.0


func on_hurt(src_corrode: bool) -> void:
	no_hurt_t = 0.0
	if g.relics.has("94"):
		_gain_sp(0.03 + (0.03 if src_corrode else 0.0))
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
		g._show_banner("时光之末 —— 水月重新站了起来")
		Sfx.play("levelup", 0.0, 0.7)
		return true
	return false


func on_kill(_e: Dictionary) -> void:
	if g.relics.has("252"):
		perm_dmg = minf(0.3, perm_dmg + 0.001)


## 伞击一次只命中 1 名敌人时的倍率（荣耀绶带）
func single_hit_mult(hit_count: int) -> float:
	return 2.0 if hit_count == 1 and g.relics.has("112") else 1.0


## 触手命中：扣挠之手（当前生命百分比）、炸裂之手（回技力）
func on_tentacle_hit(e: Dictionary) -> void:
	if g.relics.has("170") and not e.dead:
		g.out_src = "真实"
		g._damage(e, e.hp * (0.01 if e.boss else 0.03))
		g.out_src = "触手"
	if g.relics.has("171"):
		_gain_sp(0.01)


## 任意命中：审判庭之火
func on_hit() -> void:
	if g.relics.has("229"):
		_gain_sp(0.002)


## 狙击命中：扼喉之手处决
func sniper_execute(e: Dictionary) -> bool:
	return g.relics.has("169") and not e.boss and e.hp < e.maxhp * 0.2


func _temp(stat: String, value: float, dur: float) -> void:
	temps.append({"stat": stat, "value": value, "until": g.t + dur})


func _gain_sp(pct: float) -> void:
	g.ch.s2_sp = minf(D.SKILL_P.s2_charge, g.ch.s2_sp + D.SKILL_P.s2_charge * pct)
	g.ch.s3_sp = minf(D.SKILL_P.s3_charge, g.ch.s3_sp + D.SKILL_P.s3_charge * pct)
