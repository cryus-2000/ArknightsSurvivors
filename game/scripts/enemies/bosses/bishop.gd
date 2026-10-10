## 接潮主教（type bishop，docs/38 §2.3）
## Boss 行为脚本（docs/55 §6 拆分，10-10）：状态仍在敌人字典 e 上，预警 / 冷却 / 迫近经基类转给 boss_ai.gd。本文件只有这只 Boss 自己的招式与阶段逻辑。
extends "res://scripts/enemies/bosses/boss_base.gd"


## 每帧（boss_ai._boss_ai 公共段之后）：ready = 本帧可以出招；mate = 接潮搭档（没有则 null）
func step(e: Dictionary, _dt: float, _dir: Vector2, _dist: float, ready: bool, mate) -> void:
	# 接潮主教：潮汐柱（脚下三圈）、召潮（4 只海嗣）、祝福（治疗并加速搭档）
	# 慌乱（协调人 9/30 定 C，boss/bishop_panic，0 = 关）：搭档假死时停召潮、加速朝搭档靠拢，假死赛跑的 8 秒里能打到它
	# （原来它远程 300 站在自己召的杂兵后面，Ⅷ on_boss 0%）
	var panic: bool = Bal.v("boss/bishop_panic", 1.0) > 0.0 and mate != null and not mate.dead and mate.get("coma", false)
	if panic:
		if not e.get("panic", false):
			e.panic_n = int(e.get("panic_n", 0)) + 1   # 遥测 panic_n
			g.vfx.add_text(e.pos + Vector2(0, -50), "慌乱", Color(1.0, 0.45, 0.8), 16)
			Sfx.play("bishop_panic", -4.8, 1.0, 0.0)   # 慌乱：结巴的吸气颤音
		e.ai = "melee"
		e.aggro = mate.pos
		e.haste = maxf(float(e.get("haste", 0.0)), 0.1)
	elif e.get("panic", false):
		e.ai = "ranged"
	e.panic = panic
	if ready:
		var p = e.get("partner")
		if _cd(e, "pillar", 7.0):
			for k in 3:
				var off: Vector2 = Vector2.ZERO if k == 0 else Vector2.from_angle(g.rng.randf() * TAU) * g.rng.randf_range(70.0, 130.0)
				_warn(e, "circle", 1.1, {"pos": g.ppos + off, "r": 64.0, "act": "pillar", "name": "潮汐柱" if k == 0 else "", "col": Color(0.4, 0.9, 1.0), "dmg": e.dmg * 1.1, "lock": k == 0})
		elif p != null and not p.dead and not p.get("coma", false) and p.hp < p.maxhp * 0.9 and _cd(e, "bless", 10.0):
			p.hp = minf(p.maxhp, p.hp + p.maxhp * 0.08)
			p.haste = 5.0
			e.pose = 0.5
			e.pose_max = 0.5
			# 敌方增益用敌方洋红（docs/48 ⑤：原来借用友方治疗十字和绿环，看着像我方在回血）
			g.fx.append({"kind": "ring", "pos": p.pos, "r": p.r * 2.0, "life": 0.5, "max": 0.5, "col": Color(1.0, 0.3, 0.72)})
			g.fx.append({"kind": "rays", "pos": p.pos, "life": 0.5, "max": 0.5, "col": Color(1.0, 0.3, 0.72)})
			g.vfx.add_text(e.pos + Vector2(0, -50), "祝福", Color(1.0, 0.45, 0.8), 16)
			g.vfx.add_text(p.pos + Vector2(0, -50), "加速", Color(1.0, 0.45, 0.8), 14)
			Sfx.play("pickup", -6.0, 0.8)
		elif not panic and _cd(e, "summon", 14.0):
			e.pose = 0.6
			e.pose_max = 0.6
			for k in 4:
				var sp: Vector2 = e.pos + Vector2.from_angle(TAU * k / 4.0) * 70.0
				g.spawner.spawn_enemy("bone" if k % 2 == 0 else "slider", sp)
				g.fx.append({"kind": "ring", "pos": sp, "r": 22.0, "life": 0.4, "max": 0.4, "col": Color(0.5, 0.9, 1.0)})
			g.vfx.add_text(e.pos + Vector2(0, -50), "召潮", Color(0.5, 0.9, 1.0), 16)
			Sfx.play("tentacle", -6.0, 0.8)
