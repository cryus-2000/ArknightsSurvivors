## 接潮蔑死体（type archon，docs/38 §2.3）
## Boss 行为脚本（docs/55 §6 拆分，10-10）：状态仍在敌人字典 e 上，预警 / 冷却 / 迫近经基类转给 boss_ai.gd。本文件只有这只 Boss 自己的招式与阶段逻辑。
extends "res://scripts/enemies/bosses/boss_base.gd"


## 每帧（boss_ai._boss_ai 公共段之后）：ready = 本帧可以出招；mate = 接潮搭档（没有则 null）
func step(e: Dictionary, _dt: float, dir: Vector2, dist: float, ready: bool, _mate) -> void:
	# 接潮蔑死体：横扫（扇形重击+侵蚀）、跃击（跳砸目标点）
	if ready:
		if dist < 160.0 and _cd(e, "sweep", 5.0):
			_warn(e, "cone", 0.8, {"follow": true, "ang": dir.angle(), "half": 1.05, "r": 165.0, "track": 0.4, "act": "sweep", "name": "横扫", "col": Color(0.6, 1.0, 0.9), "dmg": e.dmg * 1.6, "corrode": 0.5})
		elif dist >= 160.0 and dist < 520.0 and _cd(e, "leap", 9.0):
			var w := _warn(e, "circle", 1.0, {"pos": g.ppos, "r": 84.0, "act": "leap", "name": "跃击", "col": Color(0.6, 1.0, 0.9), "dmg": e.dmg * 1.5, "corrode": 0.5})
			e.leap = w
			e.leap_from = e.pos
	if e.has("leap"):
		var w2: Dictionary = e.leap
		var k := clampf(w2.t / w2.dur, 0.0, 1.0)
		e.pos = e.leap_from.lerp(w2.pos, k)
		e.air = sin(k * PI) * 150.0
		if w2.t >= w2.dur:
			e.erase("leap")
			e.air = 0.0
