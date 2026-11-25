extends "res://scripts/core/theme_mechanic.gd"
## 萨米主题机制 · 坍缩值与坍缩范式（docs/394 §1–§2；数值读 themes/sami/data/mechanics.json collapse / paradigms）。
## 涨：队长受击（0.15 + 2.5 × 伤害 ÷ 最大生命，每秒最多 +1）、进入第 2–6 阶段各 +3。
## 降：瓦解国度 −1（每阶段最多 −3，mech_kingdom 调 add）、击杀坍缩体精英 −0.5、中期 Boss 倒下 −2、最终 Boss 每过一道卡点 −1（mech_foes 调）。
## 等级按常规档门槛 4 / 8 / … / 32；1–4 级各新增 1 条范式（第 1 条固定实质性坍缩），5–8 级各加深 1 条；降回门槛以下随机弱化或去掉 1 条。
## 本次接上的范式：实质性坍缩（国度块数，mech_kingdom 读）、非线性移动（坍缩体生命 / 移速）、情绪实体（刷怪 5% / 10% 生命 ×2）、
## 气压异常（技力回复 −20% / −40%）、目空一些（加深版敌人生命 +10%；藏血条未做）。其余 4 条（去量化 / 泛社会悖论 / 触发性损伤 / 趋同性消耗）不进池。

const Game = preload("res://scripts/game.gd")
const D = preload("res://scripts/data.gd")
const MJ := "res://themes/sami/data/mechanics.json"
const POOL := ["chaos_3", "chaos_4", "chaos_6", "chaos_9"]   # 第 1 条固定 chaos_2，之后从这里等概率抽

var g: Game
var C: Dictionary = {}
var P: Dictionary = {}       # id → 范式定义
var value := 0.0
var level := 0
var slots: Dictionary = {}   # id → 1 普通 / 2 加深（插入顺序 = 获得顺序）
var _sec_gain := 0.0
var _sec_t := 0.0
var _stage := -1
var _stage_kingdom := 0.0    # 本阶段瓦解国度已降的坍缩值
var _gates: Dictionary = {}  # 最终 Boss id → 已结算的卡点数
var rng := RandomNumberGenerator.new()
var _seeded := false
var curve: Array = []        # 每 30 秒一格的坍缩值（遥测）
var _curve_t := 0.0


func _init(game: Game) -> void:
	g = game
	var f := FileAccess.open(MJ, FileAccess.READ)
	if f != null:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			C = d.get("collapse", {})
			for p in d.get("paradigms", []):
				P[str(p.id)] = p
	value = float(C.get("start", 0.0))


func _k(path: String, dflt: float) -> float:
	var cur = C
	for k in path.split("/"):
		if not (cur is Dictionary) or not cur.has(k):
			return dflt
		cur = cur[k]
	return float(cur) if (cur is float or cur is int) else dflt


## 范式等级：0 没有 / 1 普通 / 2 加深
func par(id: String) -> int:
	return int(slots.get(id, 0))


## 范式数值：eff 字段 [普通, 加深]，没有该范式返回 0
func eff(id: String, key: String) -> float:
	var lv: int = par(id)
	if lv <= 0:
		return 0.0
	var a = P.get(id, {}).get("eff", {}).get(key, [0.0, 0.0])
	return float(a[clampi(lv - 1, 0, a.size() - 1)]) if a is Array and not a.is_empty() else 0.0


func add(v: float, why := "") -> void:
	if why == "kingdom" and v < 0.0:
		var cap: float = _k("loss/kingdom_stage_cap", 3.0)
		v = maxf(v, -(cap - _stage_kingdom))
		if v >= 0.0:
			return
		_stage_kingdom -= v
	value = maxf(_k("floor", 0.0), value + v)
	_relevel()


## 事件 / 藏品 {"mech": {"collapse": ±n}}（docs/414）
func event_op(d: Dictionary) -> void:
	if d.has("collapse"):
		add(float(d.collapse), "event")
		g.vfx.add_text(g.ppos + Vector2(0, -110), "坍缩值 %+d" % int(d.collapse), Color(0.75, 0.6, 1.0), 15)


func on_player_hit(dmg: float, _src: Dictionary) -> void:
	if dmg <= 0.0:
		return
	var gain: float = _k("gain/hit_base", 0.15) + _k("gain/hit_frac", 2.5) * dmg / maxf(1.0, g.max_hp)
	gain = minf(gain, maxf(0.0, _k("gain/hit_per_sec_cap", 1.0) - _sec_gain))
	if gain > 0.0:
		_sec_gain += gain
		add(gain, "hit")


func on_world_tick(dt: float) -> void:
	_sec_t += dt
	if _sec_t >= 1.0:
		_sec_t -= 1.0
		_sec_gain = 0.0
	_curve_t += dt
	if _curve_t >= 30.0:
		_curve_t -= 30.0
		curve.append(snappedf(value, 0.1))
	if g.threat != _stage:
		var first: bool = _stage < 0
		_stage = g.threat
		_stage_kingdom = 0.0
		if not first:
			add(_k("gain/stage", 3.0), "stage")
		var km = g.mech("kingdom")
		if km != null:
			km.on_stage()
	# 最终 Boss 过卡点：−1（docs/393 §8 第 3 条）
	var fb = g.final_boss
	if fb != null and not fb.dead:
		var gp: int = int(fb.get("gates_passed", 0))
		var done: int = int(_gates.get(fb.id, 0))
		if gp > done:
			_gates[fb.id] = gp
			add(-_k("loss/final_gate", 1.0) * float(gp - done), "gate")


func _thresholds() -> Array:
	return C.get("levels", {}).get("standard", [4, 8, 12, 16, 20, 24, 28, 32])


func _relevel() -> void:
	var th: Array = _thresholds()
	var lv := 0
	for x in th:
		if value >= float(x):
			lv += 1
	lv = mini(lv, int(_k("max_level", 8.0)))
	while lv > level:
		level += 1
		_level_up()
	while lv < level:
		level -= 1
		_level_down()


func _rng() -> RandomNumberGenerator:
	if not _seeded:
		_seeded = true
		rng.seed = hash(str(g.rng.seed) + "collapse")
	return rng


func _level_up() -> void:
	var gained := ""
	if level <= int(_k("max_slots", 4.0)):
		var id := ""
		if slots.is_empty():
			id = str(C.get("first_paradigm", "chaos_2"))
		else:
			var opts: Array = POOL.filter(func(x): return not slots.has(x))
			if opts.is_empty():
				return
			id = str(opts[_rng().randi() % opts.size()])
		slots[id] = 1
		gained = str(P.get(id, {}).get("name", id))
	else:
		var opts: Array = slots.keys().filter(func(x): return int(slots[x]) == 1)
		if opts.is_empty():
			return
		var id2: String = str(opts[_rng().randi() % opts.size()])
		slots[id2] = 2
		gained = str(P.get(id2, {}).get("deep", id2))
	g.vfx.show_banner("坍缩等级 %d：%s" % [level, gained])
	_apply()


func _level_down() -> void:
	if slots.is_empty():
		return
	var ks: Array = slots.keys()
	var id: String = str(ks[_rng().randi() % ks.size()])
	if int(slots[id]) >= 2:
		slots[id] = 1
	else:
		slots.erase(id)
	_apply()


## 范式生效：技力回复走属性块（来源 sami_chaos）；国度块数由 mech_kingdom 每帧对账
func _apply() -> void:
	g.stats.remove_source("sami_chaos")
	var sp: float = eff("chaos_6", "sp_regen")
	if sp != 0.0 and g.stats.has_stat(&"op_skill_sp"):
		g.stats.add(&"op_skill_sp", "mult", 1.0 + sp, "sami_chaos")
	var km = g.mech("kingdom")
	if km != null:
		km.on_paradigm()


## 坍缩值 / 等级 / 范式的占位显示：队长头顶一行小字（正式 HUD 等界面会话）
func draw_ground(_w) -> void:
	if level <= 0 and value < 1.0:
		return
	var names: Array = []
	for id in slots:
		names.append(str(P.get(id, {}).get("deep" if int(slots[id]) >= 2 else "name", id)))
	var s: String = "坍缩 %d · %d 级  %s" % [int(value), level, " / ".join(names)]
	var f: Font = ThemeDB.fallback_font
	g.wcv.draw_string(f, g.ppos + Vector2(-90, 46), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.8, 1.0, 0.8))
