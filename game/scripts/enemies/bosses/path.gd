## 塑路者（type path，docs/38 §2.1）
## Boss 行为脚本（docs/55 §6 拆分，10-10）：状态仍在敌人字典 e 上，预警 / 冷却 / 迫近经基类转给 boss_ai.gd。本文件只有这只 Boss 自己的招式与阶段逻辑。
extends "res://scripts/enemies/bosses/boss_base.gd"


## 每帧（boss_ai._boss_ai 公共段之后）：ready = 本帧可以出招；mate = 接潮搭档（没有则 null）
func step(e: Dictionary, _dt: float, dir: Vector2, dist: float, ready: bool, _mate) -> void:
	# 塑路者：冲撞（直线预警→冲锋）、震地（近身蓄力→冲击波）、碎裂（75/50/25% 裂出分形）
	if ready:
		if dist < 170.0 and _cd(e, "slam", 9.0):
			# 震地：砸在主控当前位置（固定落点、不跟随 Boss），r 90（docs/48 P0-4；原来 r230 跟着 Boss 走）
			_warn(e, "circle", 1.0, {"pos": g.ppos, "r": 90.0, "act": "slam", "name": "震地", "col": Color(1.0, 0.55, 0.3), "dmg": e.dmg * 1.3})
		elif e.get("dash_left", 0) > 0 and e.get("dash_t", 0.0) <= 0.0:
			# 第二幕冲撞连段（docs/38 §8.1）：上一段冲完立刻接下一段，每段仍有完整预警
			e.dash_left -= 1
			_warn(e, "line", 0.8, {"ang": dir.angle(), "len": 440.0, "wid": 30.0, "track": 0.35, "act": "dash", "fit_len": true, "name": "", "col": Color(1.0, 0.35, 0.3)})
		elif dist > 150.0 and _cd(e, "dash", 6.0):
			_warn(e, "line", 0.9, {"ang": dir.angle(), "len": 440.0, "wid": 30.0, "track": 0.45, "act": "dash", "fit_len": true, "name": "冲撞", "col": Color(1.0, 0.35, 0.3)})
			if e.get("gates_passed", 0) >= 1:
				e.dash_left = int(Bal.v("boss/path_dash_chain", 1.0)) + int(e.get("dash_bonus", 0))   # 第二幕常驻 2 连，核心没打碎再加
				e.dash_bonus = 0
	var crack: int = e.get("crack", 0)
	if crack < 3 and e.hp < e.maxhp * (0.75 - 0.25 * crack):
		e.crack = crack + 1
		for k in 4:
			var fr: Dictionary = g.spawner.spawn_enemy("fractal", g.combat.arena_clamp(e.pos + Vector2.from_angle(TAU * k / 4.0 + 0.4) * 56.0))
			fr.owner = e
		g.fx.append({"kind": "ring", "pos": e.pos, "r": e.r * 2.2, "life": 0.35, "max": 0.35, "col": Color(0.6, 0.7, 1.0)})
		g.vfx.add_text(e.pos + Vector2(0, -60), "碎裂", Color(0.6, 0.7, 1.0), 18)
		Sfx.play("boom", -6.0, 1.3, 0.0)
	if e.get("gates_passed", 0) >= 1:
		_path_core(e)


## 塑路者「猎核」（docs/38 §8.1，50% 卡点之后）：场上最老的一块碎片发光成为核心部件（不动、固定血量），编队优先打它；
## 主控得带队走过去。打碎：其余碎片崩解、Boss 破绽 boss/path_core_break 秒；boss/path_core_time 秒没打碎：碎片冲回本体，
## 下一次冲撞多连几段（最多 3）。不回血。boss/path_core_gap 秒后出新核心
func _path_core(e: Dictionary) -> void:
	var core = e.get("core")
	if core != null:
		if core.dead:
			for o in g.enemies:
				if o.type == "fractal" and not o.dead and is_same(o.get("owner"), e):
					o.dead = true
					g.vfx.sparks(o.pos, Vector2.ZERO, Color(0.6, 0.7, 1.0), 6, 160.0)
			g.combat.start_break(e, Bal.v("boss/path_core_break", 3.0))
			g.fx.append({"kind": "ring", "pos": core.pos, "r": 60.0, "life": 0.5, "max": 0.5, "col": Color(1.0, 0.85, 0.4), "enemy": true})
			g.vfx.add_text(e.pos + Vector2(0, -70), "核心碎裂 —— 碎片崩解", Color(1.0, 0.85, 0.4), 20)
			Sfx.play("boom", -4.0, 1.4, 0.0)
			e.core = null
			e.core_next = g.t + Bal.v("boss/path_core_gap", 6.0)
		elif g.t >= float(e.core_until):
			var n := 0
			for o in g.enemies:
				if o.type == "fractal" and not o.dead and is_same(o.get("owner"), e):
					n += 1
					g.fx.append({"kind": "reflow", "a": o.pos, "b": e.pos, "life": 0.7, "max": 0.7, "enemy": true})   # 碎片回流（world.gd 画）
					o.dead = true
			e.dash_bonus = mini(3, n)
			g.vfx.add_text(e.pos + Vector2(0, -70), "碎片回流 —— 冲撞 +%d 段" % e.dash_bonus, Color(1.0, 0.45, 0.35), 18)
			e.core = null
			e.core_next = g.t + Bal.v("boss/path_core_gap", 6.0)
		return
	if g.t < float(e.get("core_next", 0.0)):
		return
	var owned: Array = []
	for o in g.enemies:
		if o.type == "fractal" and not o.dead and is_same(o.get("owner"), e):
			owned.append(o)
	while owned.size() < 3:
		var fr: Dictionary = g.spawner.spawn_enemy("fractal", g.combat.arena_clamp(e.pos + Vector2.from_angle(g.rng.randf() * TAU) * g.rng.randf_range(120.0, 200.0)))
		fr.owner = e
		owned.append(fr)
	var oldest: Dictionary = owned[0]
	for o in owned:
		if o.age > oldest.age:
			oldest = o
	oldest.part = true
	oldest.core = true
	oldest.spd = 0.0
	oldest.dmg = 0.0
	oldest.maxhp = e.maxhp * Bal.v("boss/path_core_hp", 0.04)
	oldest.hp = oldest.maxhp
	var ct: float = Bal.v("boss/path_core_time", 12.0)
	oldest.count_end = g.t + ct   # 倒计时环（界面与美术读 count_end / count_max）
	oldest.count_max = ct
	e.core = oldest
	e.core_until = g.t + ct
	g.vfx.add_text(oldest.pos + Vector2(0, -30), "核心", Color(1.0, 0.85, 0.4), 18)
