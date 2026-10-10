## 接潮斥亡体（type immortal，docs/38 §2.3）
## Boss 行为脚本（docs/55 §6 拆分，10-10）：状态仍在敌人字典 e 上，预警 / 冷却 / 迫近经基类转给 boss_ai.gd。本文件只有这只 Boss 自己的招式与阶段逻辑。
extends "res://scripts/enemies/bosses/boss_base.gd"


## 每帧（boss_ai._boss_ai 公共段之后）：ready = 本帧可以出招；mate = 接潮搭档（没有则 null）
func step(e: Dictionary, _dt: float, dir: Vector2, dist: float, ready: bool, _mate) -> void:
	# 接潮斥亡体：连斩（三段突刺）、搭档昏迷时狂暴
	var p2 = e.get("partner")
	# 搭档苏醒时狂暴解除（docs/38 §2.3）
	if e.get("rage", false) and (p2 == null or p2.dead or not p2.get("coma", false)):
		e.rage = false
		e.spd /= 1.35
		e.dmg /= 1.2
	if p2 != null and not p2.dead and p2.get("coma", false) and not e.get("rage", false):
		e.rage = true
		e.spd *= 1.35
		e.dmg *= 1.2
		g.vfx.add_text(e.pos + Vector2(0, -50), "狂暴", Color(1.0, 0.4, 0.4), 18)
		g.fx.append({"kind": "ring", "pos": e.pos, "r": e.r * 2.0, "life": 0.4, "max": 0.4, "col": Color(1.0, 0.3, 0.3)})
		Sfx.play("roar", -6.0, 1.3)
	if ready and e.get("combo_n", 0) > 0 and e.get("combo_t", 0.0) <= g.t:
		e.combo_n -= 1
		_warn(e, "line", 0.38, {"ang": dir.angle(), "len": 190.0, "wid": 22.0, "track": 0.19, "act": "stab", "spd": 820.0, "name": "" if e.combo_n < 2 else "连斩", "col": Color(0.6, 0.8, 1.0), "dmg": e.dmg * 1.1, "corrode": 0.5})
		e.combo_t = g.t + 0.62
	elif ready and dist < 280.0 and _cd(e, "combo", 6.0):
		e.combo_n = 3
		e.combo_t = 0.0
