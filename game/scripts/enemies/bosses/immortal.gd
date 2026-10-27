## 接潮斥亡体（type immortal，docs/38 §2.3；招式改版 docs/95 §10，10-14 第 3 批）
## Boss 行为脚本（docs/55 §6 拆分，10-10）：状态仍在敌人字典 e 上，预警 / 冷却 / 迫近经基类转给 boss_ai.gd。本文件只有这只 Boss 自己的招式与阶段逻辑。
## 4 招：A 连斩（② 3 段突刺，第二幕 4 段）/ B 斥亡旋刃（④，patterns）/ C 迸发（① 自身为心落点圈：狂暴开始、复苏各一次，平时 12 秒）/ D 掠海飞刃（③，第二幕，patterns manual）
## 机制不占名额：狂暴（搭档假死时）、假死、复苏
## 弹幕与配合连段（docs/170）：主教指挥两具的镜像弹幕与配合连段；连段进行中本体不自己选招（连斩续段照走）；第二幕掠海飞刃不再自动放（镜像弹幕取代，force_move 仍可放）
extends "res://scripts/enemies/bosses/boss_base.gd"

const MC = preload("res://scripts/enemies/mid_cards.gd")

const MOVES := ["连斩", "斥亡旋刃", "迸发", "掠海飞刃"]
const COL := Color(0.6, 0.8, 1.0)
const TINT2 := Color(0.88, 0.98, 1.18)   # 第二幕常驻淡蓝（docs/95 §10.2）


## 每帧（boss_ai._boss_ai 公共段之后）：ready = 本帧可以出招；mate = 接潮搭档（没有则 null）
func step(e: Dictionary, dt: float, dir: Vector2, dist: float, ready: bool, _mate) -> void:
	_pair_spread(e, dt)
	if not e.get("light_rage", false):
		e.light_rage = true
		e.spd *= Bal.v("boss/immortal_light_rage", 1.2)   # 常驻轻狂暴（PRTS 描述「更弱小，更狂暴」，docs/142b §3.8）
	var p2: bool = _pair_p2(e)
	if p2:
		_tint2(e, TINT2)
	var pt = e.get("partner")
	# 搭档苏醒时狂暴解除（docs/38 §2.3）
	if e.get("rage", false) and (pt == null or pt.dead or not pt.get("coma", false)):
		e.rage = false
		e.spd /= 1.35
		e.dmg /= 1.2
	if pt != null and not pt.dead and pt.get("coma", false) and not e.get("rage", false):
		e.rage = true
		e.spd *= 1.35
		e.dmg *= 1.2
		g.vfx.add_text(e.pos + Vector2(0, -50), "狂暴", Color(1.0, 0.4, 0.4), 18)
		g.fx.append({"kind": "ring", "pos": e.pos, "r": e.r * 2.0, "life": 0.4, "max": 0.4, "col": Color(1.0, 0.3, 0.3)})
		Sfx.play("roar", -6.0, 1.3)
		_erupt(e)   # C 迸发：狂暴开始的一刻（docs/95 §10.2 C）
	if ready and e.get("combo_n", 0) > 0 and e.get("combo_t", 0.0) <= g.t:
		e.combo_n -= 1
		# 每段 0.6 秒（原写 0.38 被 _warn 的 0.6 下限钳住，docs/95 §10.1 文档和代码对不上，这里直接写 0.6）、段间 0.62 秒
		_warn(e, "line", 0.6, {"ang": dir.angle(), "len": 190.0, "wid": 22.0, "track": 0.19, "act": "stab", "spd": 820.0, "name": "连斩" if e.get("combo_first", false) else "", "col": COL, "dmg": e.dmg * 1.1, "corrode": 0.5, "skin": "mc_line"})
		e.combo_first = false
		e.combo_t = g.t + 0.62
	elif ready and MC.in_pair_combo(e):
		pass   # 主教的配合连段进行中：不自己选招
	elif ready and p2 and Bal.v("boss/immortal_auto_fan", 0.0) > 0.0 and dist >= 120.0 and dist <= 360.0 and float(e.get("cds", {}).get("fan", 0.0)) <= g.t:
		# D 掠海飞刃：第二幕、主控 120–360、fan 7 秒；第一次先亮招式名 0.6 秒（§0.2）
		if _first_tell(e, "fan", "掠海飞刃") and _cd(e, "fan", 7.0):
			_fan(e, dir, dist)
	elif ready and dist < 280.0 and _cd(e, "combo", 6.0):
		e.combo_n = 4 if p2 else 3
		e.combo_first = true
		e.combo_t = 0.0
	elif ready and dist < 240.0 and _cd(e, "burst", 12.0):
		_erupt(e)


## 公共段复苏时调用（boss_ai.gd，docs/95 §12 on_revive）：C 迸发，和「复苏（n / 2）」飘字同帧
func on_revive(e: Dictionary) -> void:
	_erupt(e)


## 图鉴 / Boss 演练：直接进入第二幕
func setup_preview_phase2(e: Dictionary) -> void:
	e.gates_passed = maxi(1, int(e.get("gates_passed", 0)))
	_tint2(e, TINT2)


func demo_moves(_e: Dictionary) -> Array:
	return MOVES


func force_move(e: Dictionary, name: String, dir: Vector2, dist: float) -> bool:
	match name:
		"连斩":
			e.combo_n = 4 if _pair_p2(e) else 3
			e.combo_first = true
			e.combo_t = 0.0
			return true
		"斥亡旋刃":
			e.pattern_force = name
			return g.bai.patterns.try_attack(e, dir, dist)
		"迸发":
			_erupt(e)
			return true
		"掠海飞刃":
			if not _pair_p2(e):
				return false
			_fan(e, dir, dist)
			return true
	return false


## C · 迸发（本作原创，取材 PRTS「假死每秒回复 10%」与狂暴）：以自身为心 r120 实填圈，跟随本体 0.3 秒后锁定，总 0.9 秒；
## e.dmg × 1.2（狂暴期间 e.dmg 已 ×1.2，沿用）、侵蚀 0.5；结算 boss_ai erupt（Codex fx_immortal_burst）
func _erupt(e: Dictionary) -> void:
	_warn(e, "circle", 0.9, {"pos": e.pos, "r": 120.0, "track_pos": "self", "track": 0.3, "act": "erupt", "name": "迸发", "col": g.vfx.boss_color(e.type),
		"dmg": e.dmg * 1.2, "corrode": 0.5, "skin": "mc_slam"})


## D · 掠海飞刃（第二幕）：enemies.json patterns「掠海飞刃」（manual）——扇形 r300 半角 0.85，追踪 0.3 总 1.5；7 片刃弹 430px/s，e.dmg × 0.8 / 片
func _fan(e: Dictionary, dir: Vector2, dist: float) -> void:
	e.pattern_force = "掠海飞刃"
	g.bai.patterns.try_attack(e, dir, dist)


## 同步护盾（docs/142b §3.8）：血量比搭档低出门槛时受伤 × 0.4
func taken_mult(e: Dictionary) -> float:
	return _pair_shield(e)


## 主教的配合连段调这里（docs/170）：返回这一段占用的秒数，放不出 -1
func pair_move(e: Dictionary, move: String, _dir: Vector2) -> float:
	match move:
		"连斩":
			e.combo_n = 4 if _pair_p2(e) else 3
			e.combo_first = true
			e.combo_t = 0.0
			return 1.22 * float(e.combo_n) + 0.4
		"迸发":
			_erupt(e)
			return 0.9
	return -1.0
