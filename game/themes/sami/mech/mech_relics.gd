extends "res://scripts/core/theme_mechanic.gd"
## 萨米藏品里通用积木做不了的规则（docs/414 §2）：relic_effects.json 里 type = rule、rule 以 sami_ 开头的，由这里按持有情况结算。
## 水月不加载本脚本；通用积木（stat / squad_scale / shield_dr / on_gain …）仍由 relic_fx 处理。
##   sami_drain        每秒流失 pct 最大生命（不低于 1）                         永夜的窥视
##   sami_whet         每 every 秒随机一名队员 dur 秒内攻击力 +atk（op_atk，op:<id>） 凝冰砥石
##   sami_crowd        队长身边 r 内敌人 ≥ n：dur 秒内 stats（relic_fx 限时修正），冷却 cd   霜牡的肩甲 / 雪牝的护手
##   sami_gold         每持有 per 源石锭攻速 +step，封顶 cap                       金酒之杯
##   sami_collapse_once 获得时坍缩值 +v                                           警戒篱木
##   sami_bell         坍缩值上升时回复 pct 最大生命                               仪式铃
##   sami_staff        路口发牌时坍缩等级 ≤ lv：源石锭 +ingots                      北方拓荒者拐杖
##   sami_sprout       路口发牌时护盾 +n 层                                        芽棍
##   sami_hunter       打坍缩体伤害 +mult、停顿 stun 秒（同一敌人 cd 秒一次）        猎人的洞察
##   sami_altar        击败精英 / Boss 时 p 概率：伤害 +dmg、物理减伤 +armor（最多 cap 层） 圆石祭坛
##   sami_blade_xp     坍缩每高一级经验 +per                                       乌萨斯断刃
##   sami_fang         击败精英时 p 概率掉 1 块密文板                               伶牙，毁林者
##   sami_ode          击败精英 / Boss 时最大生命永久 +per（最多 cap 层）           米诺斯颂诗
##   sami_neutral      站在国度里的敌人移速 × spd                                  范式中和仪
##   sami_pack         寒冷消退（≥50 → <50）或冻结解除后 dur 秒内伤害 +dmg        探索者背包

const D = preload("res://scripts/data.gd")

var g
var rng := RandomNumberGenerator.new()
var _seeded := false
var _held_n := -1
var _rules: Dictionary = {}        # rule -> [[relic_id, args], …]
var _once: Dictionary = {}         # 一次性规则已结算的藏品
var _whet_t := 0.0
var _whet_until := 0.0
var _crowd_cd: Dictionary = {}
var _gold_t := 0.0
var _gold_v := -1.0
var _last_collapse := -1.0
var _bxp_lv := -1
var _cold_hi := false
var _frozen := false
var altar_n := 0
var ode_n := 0
var hunter_cd: Dictionary = {}


func _init(game) -> void:
	g = game


func _rng() -> RandomNumberGenerator:
	if not _seeded:
		_seeded = true
		rng.seed = hash(str(g.rng.seed) + "sami_relics")
	return rng


## 持有的 sami_ 规则（g.relics 只追加，按长度判断要不要重建）
func _refresh() -> void:
	if _held_n == g.relics.size():
		return
	_held_n = g.relics.size()
	_rules.clear()
	for rid in g.relics:
		var r = g.rfx.db.get_relic(str(rid))
		if r == null or not (r is Dictionary):
			continue
		for ef in r.get("effects", []):
			if str(ef.get("type", "")) == "rule" and str(ef.get("rule", "")).begins_with("sami_"):
				if not _rules.has(ef.rule):
					_rules[ef.rule] = []
				_rules[ef.rule].append([str(rid), ef.get("args", {})])


func _has(rule: String) -> bool:
	_refresh()
	return _rules.has(rule)


func _args(rule: String) -> Array:
	_refresh()
	return _rules.get(rule, [])


func _cm():
	return g.mech("collapse")


func _sync() -> void:
	if g.has_method("sync_stats"):
		g.sync_stats()


func on_world_tick(dt: float) -> void:
	_refresh()
	if _rules.is_empty():
		return
	for x in _args("sami_collapse_once"):
		if not _once.has(x[0]):
			_once[x[0]] = true
			var cm = _cm()
			if cm != null:
				cm.event_op({"collapse": float(x[1].get("v", -2.0))})
	for x in _args("sami_drain"):
		if g.hp > 1.0:
			g.hp = maxf(1.0, g.hp - g.max_hp * float(x[1].get("pct", 0.006)) * dt)
	_tick_whet()
	_tick_crowd()
	_tick_gold(dt)
	_tick_collapse()
	_tick_pack()


func _tick_whet() -> void:
	var a: Array = _args("sami_whet")
	if a.is_empty():
		return
	var ar: Dictionary = a[0][1]
	if _whet_until > 0.0 and g.t >= _whet_until:
		_whet_until = 0.0
		g.stats.remove_source("sami_whet")
		_sync()
	if _whet_t <= 0.0:
		_whet_t = g.t + 5.0
	if g.t >= _whet_t and not g.squad.ops.is_empty():
		_whet_t = g.t + float(ar.get("every", 60.0))
		var o = g.squad.ops[_rng().randi() % g.squad.ops.size()]
		g.stats.remove_source("sami_whet")
		g.rfx._apply_stat("op_atk", "add", float(ar.get("atk", 1.0)) * a.size(), "sami_whet", "op:" + str(o.id))
		_whet_until = g.t + float(ar.get("dur", 15.0))
		g.vfx.add_text(g.ppos + Vector2(0, -110), "凝冰砥石：%s 攻击力翻倍" % o.display_name(), Color(0.7, 0.9, 1.1), 14)


func _tick_crowd() -> void:
	for x in _args("sami_crowd"):
		var id: String = x[0]
		var ar: Dictionary = x[1]
		if g.t < float(_crowd_cd.get(id, 0.0)):
			continue
		var r: float = float(ar.get("r", 120.0))
		var n := 0
		for j in g.enemies_sys.query(g.ppos, r + 20.0):
			var e: Dictionary = g.enemies[j]
			if not e.dead and not e.get("chest", false) and not e.get("friendly", false) and e.pos.distance_to(g.ppos) < r + float(e.r):
				n += 1
		if n < int(ar.get("n", 6)):
			continue
		_crowd_cd[id] = g.t + float(ar.get("cd", 20.0))
		for st in ar.get("stats", []):
			g.rfx._temp(str(st[0]), float(st[1]), float(ar.get("dur", 10.0)), "sami_crowd" + id + str(st[0]))


func _tick_gold(dt: float) -> void:
	var a: Array = _args("sami_gold")
	if a.is_empty():
		return
	_gold_t -= dt
	if _gold_t > 0.0:
		return
	_gold_t = 0.5
	var ar: Dictionary = a[0][1]
	var v: float = minf(float(ar.get("cap", 0.3)), floorf(float(g.ingots) / maxf(1.0, float(ar.get("per", 10)))) * float(ar.get("step", 0.01))) * a.size()
	if is_equal_approx(v, _gold_v):
		return
	_gold_v = v
	g.stats.remove_source("sami_gold")
	if v > 0.0:
		g.rfx._apply_stat("op_aspd", "add", v, "sami_gold")
	else:
		_sync()


func _tick_collapse() -> void:
	var cm = _cm()
	if cm == null:
		return
	var v: float = float(cm.value)
	if _last_collapse >= 0.0 and v > _last_collapse + 0.001:
		for x in _args("sami_bell"):
			g.combat.heal(g.max_hp * float(x[1].get("pct", 0.05)), "藏品")
	_last_collapse = v
	var bx: Array = _args("sami_blade_xp")
	if not bx.is_empty() and int(cm.level) != _bxp_lv:
		_bxp_lv = int(cm.level)
		g.stats.remove_source("sami_bxp")
		if _bxp_lv > 0:
			g.rfx._apply_stat("xp_gain", "mult", 1.0 + float(bx[0][1].get("per", 0.05)) * _bxp_lv * bx.size(), "sami_bxp")
		else:
			_sync()


func _tick_pack() -> void:
	var a: Array = _args("sami_pack")
	var c = g.mech("cold")
	var hi: bool = c != null and float(c.cold) >= 50.0
	var fr: bool = float(g.get("frozen_t")) > 0.0
	if not a.is_empty() and ((_cold_hi and not hi) or (_frozen and not fr)):
		var ar: Dictionary = a[0][1]
		g.rfx._temp("dmg", float(ar.get("dmg", 0.3)), float(ar.get("dur", 10.0)), "sami_pack")
	_cold_hi = hi
	_frozen = fr


## 路口发牌（endings._show_deck → theme_mechanic.on_deck）
func on_deck(_deck: Array) -> void:
	_refresh()
	var cm = _cm()
	for x in _args("sami_staff"):
		if cm == null or int(cm.level) <= int(x[1].get("lv", 1)):
			g.rfx.gain_ingots(int(x[1].get("ingots", 6)), "北方拓荒者拐杖 · ")
	for x in _args("sami_sprout"):
		if g.shield_max <= 0:
			g.rfx._apply_stat("shield_max", "flat", 1.0, "relic_sprout", "")
		g.shield = mini(g.shield + int(x[1].get("n", 1)), g.shield_max)


## mech_foes.on_enemy_killed 转来
func on_kill(e: Dictionary) -> void:
	_refresh()
	if _rules.is_empty() or e.get("chest", false):
		return
	var big: bool = e.boss or e.get("elite", false)
	if not big:
		return
	for x in _args("sami_altar"):
		if altar_n < int(x[1].get("cap", 10)) and _rng().randf() < float(x[1].get("p", 0.5)):
			altar_n += 1
			g.stats.remove_source("sami_altar")
			g.rfx._apply_stat("dmg", "add", float(x[1].get("dmg", 0.02)) * altar_n, "sami_altar")
			g.rfx._apply_stat("armor", "flat", float(x[1].get("armor", 1.0)) * altar_n, "sami_altar")
	for x in _args("sami_ode"):
		if ode_n < int(x[1].get("cap", 15)):
			ode_n += 1
			g.stats.remove_source("sami_ode")
			g.rfx._apply_stat("max_hp", "add", float(x[1].get("per", 0.03)) * ode_n, "sami_ode")
	if e.get("elite", false) and not e.boss:
		var tm = g.mech("totem")
		for x in _args("sami_fang"):
			if tm != null and _rng().randf() < float(x[1].get("p", 0.15)):
				tm.drop_one()


## relic_fx._trim_mult 经 mech_foes.hit_mult 转来：我方命中敌人 e 的伤害倍率
func hit_mult(e: Dictionary) -> float:
	var a: Array = _args("sami_hunter")
	if a.is_empty() or not D.ENEMIES.get(e.type, {}).get("collapse", false):
		return 1.0
	var ar: Dictionary = a[0][1]
	if not e.boss and g.t >= float(hunter_cd.get(int(e.id), 0.0)):
		hunter_cd[int(e.id)] = g.t + float(ar.get("cd", 3.0))
		g.enemies_sys.add_cc(e, float(ar.get("stun", 0.5)))
	return 1.0 + float(ar.get("mult", 0.5))


## mech_foes.enemy_spd 转来：站在国度里的敌人减速
func enemy_spd_mult(e: Dictionary) -> float:
	var a: Array = _args("sami_neutral")
	if a.is_empty():
		return 1.0
	var km = g.mech("kingdom")
	if km != null and km.inside(e.pos):
		return float(a[0][1].get("spd", 0.7))
	return 1.0


func report() -> Dictionary:
	_refresh()
	if _rules.is_empty():
		return {}
	return {"rules": _rules.keys(), "altar": altar_n, "ode": ode_n}
