## 接潮蔑死体（type archon，docs/38 §2.3；招式改版 docs/95 §9，10-14 第 3 批）
## Boss 行为脚本（docs/55 §6 拆分，10-10）：状态仍在敌人字典 e 上，预警 / 冷却 / 迫近经基类转给 boss_ai.gd。本文件只有这只 Boss 自己的招式与阶段逻辑。
## 4 招：A 横扫（③ 双爪 2 段）/ B 跃击（①）/ C 蚀潮吐息（② 直线，命中后 3 秒侵蚀结算 +25%）/ D 裂潮（④ 跃击落点为心的缺口刃环，第二幕，patterns manual）
## 机制不占名额：假死、复苏
## 弹幕与配合连段（docs/170）：主教指挥两具的镜像弹幕与配合连段；连段进行中本体不自己选招（pair_move 由主教调）
extends "res://scripts/enemies/bosses/boss_base.gd"

const MC = preload("res://scripts/enemies/mid_cards.gd")

const MOVES := ["横扫", "跃击", "蚀潮吐息", "裂潮"]
const COL := Color(0.6, 1.0, 0.9)
const TINT2 := Color(0.86, 1.14, 0.95)   # 第二幕常驻绿色亮边（docs/95 §9.2）


## 每帧（boss_ai._boss_ai 公共段之后）：ready = 本帧可以出招；mate = 接潮搭档（没有则 null）
func step(e: Dictionary, dt: float, dir: Vector2, dist: float, ready: bool, _mate) -> void:
	_pair_spread(e, dt)
	var p2: bool = _pair_p2(e)
	if p2:
		_tint2(e, TINT2)
	if ready and not MC.in_pair_combo(e):
		if dist < 160.0 and _cd(e, "sweep", 5.0):
			_sweep(e, dir)
		elif dist >= 100.0 and dist <= 320.0 and _cd(e, "breath", 8.0):
			_breath(e, dir)
		elif dist >= 160.0 and dist < 520.0 and float(e.get("cds", {}).get("leap", 0.0)) <= g.t:
			# 第二幕跃击带裂潮：第一次先亮「裂潮」0.6 秒（§0.2）
			if (not p2 or _first_tell(e, "rift", "裂潮")) and _cd(e, "leap", 9.0):
				_leap(e, p2)
	if e.has("leap"):
		var w2: Dictionary = e.leap
		var k := clampf(w2.t / w2.dur, 0.0, 1.0)
		e.pos = e.leap_from.lerp(w2.pos, k)
		e.air = sin(k * PI) * 150.0
		# 裂潮缺口：前 0.5 秒跟着「落点 → 主控」转，之后固定（结算前 ≥0.8 秒画好，§0.2）
		var rw = e.get("rift_w")
		if rw is Dictionary and not rw.done and rw.t < 0.5 and g.ppos.distance_to(rw.pos) > 12.0:
			rw.gap_ang = (g.ppos - rw.pos).angle()
			rw.ang = rw.gap_ang
		if w2.t >= w2.dur:
			e.erase("leap")
			e.air = 0.0


## 图鉴 / Boss 演练：直接进入第二幕
func setup_preview_phase2(e: Dictionary) -> void:
	e.gates_passed = maxi(1, int(e.get("gates_passed", 0)))
	_tint2(e, TINT2)


func demo_moves(_e: Dictionary) -> Array:
	return MOVES


func force_move(e: Dictionary, name: String, dir: Vector2, _dist: float) -> bool:
	match name:
		"横扫":
			_sweep(e, dir)
			return true
		"跃击":
			_leap(e, false)
			return true
		"蚀潮吐息":
			_breath(e, dir)
			return true
		"裂潮":
			if not _pair_p2(e):
				return false
			_leap(e, true)
			return true
	return false


## A · 横扫（保留 + 合并双爪交斩）：扇形 r165 半角 1.05，跟随本体；第 1 段追踪 0.4 秒总 1.2 秒，第 2 段同时画出、方向偏 0.42、晚 0.6 秒结算（双爪）；
## e.dmg × 1.6 每段，侵蚀 0.5（两段合计受 2 秒上限）
func _sweep(e: Dictionary, dir: Vector2) -> void:
	_warn(e, "cone", 1.2, {"follow": true, "ang": dir.angle(), "half": 1.05, "r": 165.0, "track": 0.4, "act": "sweep", "name": "横扫", "col": COL, "dmg": e.dmg * 1.6, "corrode": 0.5, "skin": "mc_cone"})
	_warn(e, "cone", 1.8, {"follow": true, "ang": dir.angle() + 0.42, "half": 1.05, "r": 165.0, "act": "sweep", "name": "", "col": COL, "dmg": e.dmg * 1.6, "corrode": 0.5, "lock": false, "skin": "mc_cone"})


## B · 跃击（保留）：主控位置 r84 实填圈 1.0 秒，e.dmg × 1.5 侵蚀 0.5，冲击环 ≤ 预警圆；
## 第二幕同时以落点为心画出 D 裂潮的缺口环（同一次预警的两层，不另占令牌），落地后 0.3 秒结算 10 片刃弹
func _leap(e: Dictionary, rift: bool) -> void:
	var w := _warn(e, "circle", 1.0, {"pos": g.ppos, "r": 84.0, "act": "leap", "name": "跃击", "col": COL, "dmg": e.dmg * 1.5, "corrode": 0.5, "skin": "mc_slam"})
	e.leap = w
	e.leap_from = e.pos
	e.erase("rift_w")
	if not rift:
		return
	var move: Dictionary = {}
	for m in D.ENEMIES[e.type].get("patterns", []):
		if str(m.name) == "裂潮":
			move = m
	if move.is_empty():
		return
	var ga: float = (e.pos - w.pos).angle()
	e.rift_w = _warn(e, "circle", w.dur + 0.3, {"pos": w.pos, "r": float(move.get("ring_r", 84.0)), "act": "pattern_ring", "pattern": move, "wave": 0, "enhanced": false,
		"pattern_id": e.type + ":rift", "ang": ga, "gap_ang": ga, "gap_half": float(move.gap), "name": "", "col": g.vfx.boss_color(e.type),
		"dmg": e.dmg * float(move.get("mult", 0.8)), "corrode": 0.0, "cancel_dead": true, "lock": false})


## C · 蚀潮吐息（本作原创，取材 PRTS「攻击附带攻击力 50% 侵蚀损伤」）：口部射出 320 × 30 条纹线，追踪 0.4 秒后锁定，总 1.0 秒；
## e.dmg × 1.0 法术、侵蚀 0.5，命中后 3 秒内侵蚀结算 +25%（boss_ai _warn_damage → combat.drain_corrode，仍受 Boss 持续伤害上限）
func _breath(e: Dictionary, dir: Vector2) -> void:
	_warn(e, "line", 1.0, {"ang": dir.angle(), "len": 320.0, "wid": 30.0, "track": 0.4, "act": "breath", "kp": "archon", "kp_k": 2.0, "name": "蚀潮吐息", "col": COL, "dmg": e.dmg * 1.0,
		"corrode": 0.5, "corrode_amp": 0.25, "corrode_amp_t": 3.0, "arts": true, "skin": "mc_line"})


## 同步护盾（docs/142b §3.8）：血量比搭档低出门槛时受伤 × 0.4
func taken_mult(e: Dictionary) -> float:
	return _pair_shield(e)


## 主教的配合连段调这里（docs/170）：返回这一段占用的秒数，放不出 -1
func pair_move(e: Dictionary, move: String, dir: Vector2) -> float:
	match move:
		"跃击":
			_leap(e, _pair_p2(e))
			return 1.0
		"横扫":
			_sweep(e, dir)
			return 1.8
		"蚀潮吐息":
			_breath(e, dir)
			return 1.0
	return -1.0
