## 伊莎玛拉（type ishar，docs/38 §2.5 / §8.6）；一阶段由 run/ishar_encounter.gd 负责
## Boss 行为脚本（docs/55 §6 拆分，10-10）：状态仍在敌人字典 e 上，预警 / 冷却 / 迫近经基类转给 boss_ai.gd。本文件只有这只 Boss 自己的招式与阶段逻辑。
extends "res://scripts/enemies/bosses/boss_base.gd"


## 每帧（boss_ai._boss_ai 公共段之后）：ready = 本帧可以出招；mate = 接潮搭档（没有则 null）
func step(e: Dictionary, _dt: float, dir: Vector2, dist: float, ready: bool, _mate) -> void:
	# P1 治疗海嗣和充能由 IsharEncounter 负责；这里仅调度敌对海嗣形态。
	if e.phase == 2 and ready and g.t >= float(e.get("transform_until", 0.0)):
		_ishar_phase2(e, dir, dist)



## 图鉴 / Boss 演练：直接进入二阶段的完整状态
func setup_preview_phase2(e: Dictionary) -> void:
	transform_ishar(e)


## 以原作「三目标真实伤害」为基础的幸存者玩法改编。
## 下列提示是攻击形状说明，不冒称原作技能名；固定轮转避免近身招式永久压住远程招式。
func _ishar_phase2(e: Dictionary, dir: Vector2, dist: float) -> void:
	var d: Dictionary = D.ENEMIES.ishar.get("attack", {})
	# 潮涌迫近（协调人 9/30 定，见 _close_in）：原来她站在 660 射程边上、躲在杂兵墙后，近战队伍打不到（Boss A/B 9/30：高手用时中位 199 秒、15/50 没打死）
	if g.t >= float(e.get("ishar_next_at", 0.0)):
		var cdur := _close_in(e, dir, dist, "ishar", "潮涌迫近", Color(0.35, 1.0, 0.9))
		if cdur >= 0.0:
			e.ishar_next_at = g.t + cdur + 0.6
			return
	if dist > float(d.get("range", 660.0)) or g.t < float(e.get("ishar_next_at", 0.0)):
		return
	var move: int = int(e.get("ishar_cycle", 0)) % 4
	var col := Color(0.35, 1.0, 0.9)
	var end := 0.0
	var echoes: Array = e.get("tear_echoes", [])
	if not echoes.is_empty():
		# 只保存变身前未压制的泪滴；锁定一刻的主控位置，各束同时结算。
		var target: Vector2 = g.combat.arena_clamp(g.ppos, 80.0)
		for source in echoes:
			var to_target: Vector2 = target - source
			var w := _warn(e, "line", 1.0, {"pos": source, "ang": to_target.angle(), "len": to_target.length(),
				"wid": 13.0, "act": "ishar_echo", "true": true, "name": "泪滴共鸣" if source == echoes[0] else "",
				"col": col, "dmg": e.dmg * Bal.v("boss/ishar_echo_mult", 0.6), "cancel_dead": true, "lock": source == echoes[0]})
			end = maxf(end, w.dur)
		e.tear_echoes = []
		e.wind = maxf(e.wind, end)
		e.cdt = maxf(e.cdt, end)
		e.ishar_next_at = g.t + end + float(d.get("recovery", 1.25)) * SKILL_COOLDOWN_SCALE * _ishar_haste(e)
		return
	e.ishar_cycle = (move + 1) % 4
	match move:
		0:
			# 一人主控制：三目标改为当前脚底与两侧三个固定落点；队员仍不受伤。
			var side := dir.orthogonal()
			var offsets := [0.0, -1.0, 1.0]
			for k in 3:
				var pos: Vector2 = g.combat.arena_clamp(g.ppos + side * offsets[k] * float(d.get("mark_spacing", 106.0)), 90.0)
				var w := _warn(e, "circle", float(d.get("mark_warn", 0.9)),
					{"pos": pos, "r": float(d.get("mark_radius", 56.0)), "act": "ishar_strike", "true": true,
					"name": "三点落击" if k == 0 else "", "col": col, "dmg": e.dmg * float(d.get("mark_mult", 0.65)),
					"cancel_dead": true, "lock": k == 0})
				end = maxf(end, w.dur)
		1:
			# 三条固定方向的射线同时释放，锁定后不追人；夹缝始终能避开。
			for k in 3:
				var w := _warn(e, "line", float(d.get("line_warn", 1.0)),
					{"ang": dir.angle() + (k - 1) * float(d.get("line_spread", 0.38)),
					"len": float(d.get("range", 660.0)), "wid": float(d.get("line_width", 14.0)),
					"act": "ishar_line", "true": true, "name": "三线扫射" if k == 0 else "", "col": col,
					"dmg": e.dmg * float(d.get("line_mult", 0.7)), "cancel_dead": true, "lock": k == 0})
				end = maxf(end, w.dur)
		2:
			var w := _warn(e, "cone", float(d.get("volley_warn", 0.8)),
				{"ang": dir.angle(), "r": 672.0, "half": 0.26, "track": 0.35, "act": "ishar_volley",
				"true": true, "name": "三重吐息", "col": col, "cancel_dead": true})
			end = w.dur
		3:
			var near: bool = dist < float(d.get("bite_range", 190.0))
			var w := _warn(e, "cone", float(d.get("maw_warn", 0.85)),
				{"ang": dir.angle(), "half": 0.85 if near else 0.46,
				"r": float(d.get("bite_range", 190.0)) if near else minf(dist + 40.0, float(d.get("range", 660.0))),
				"track": 0.3, "act": "bite" if near else "sweep", "true": true,
				"name": "近身撕咬" if near else "扇形横扫", "col": col,
				"dmg": e.dmg * float(d.get("maw_mult", 0.9)), "cancel_dead": true})
			end = w.dur
	# 完整连段期间停留且不插入普通射击；按经过难度修正后的真实预警长度计时。
	e.wind = maxf(e.wind, end)
	e.cdt = maxf(e.cdt, end)
	e["ishar_next_at"] = g.t + end + float(d.get("recovery", 1.25)) * SKILL_COOLDOWN_SCALE * _ishar_haste(e)


## 真实形态切换由逻辑记录起始时间，渲染和演练均使用同一个入口。
func transform_ishar(e: Dictionary) -> void:
	if e.phase == 2:
		return
	Sfx.play_cue("phase", e.type, "start")
	e.phase = 2
	e.friendly = false
	e.invuln = false   # 0.9 秒变身免伤由 combat 的 transform_until 护栏控制，不留永久无敌。
	e.ai = "melee"   # 接近主控，但伤害只从有预警的轮转招式结算。
	e["ishar_cycle"] = 0
	e["ishar_next_at"] = g.t + 0.9
	e["tear_echoes"] = []
	for o in g.enemies:
		if o.type == "tear" and is_same(o.get("owner", {}), e):
			if not o.dead and not g.ishar.tear_blocked(o):
				e.tear_echoes.append(o.pos)
				g.fx.append({"kind": "ring", "pos": o.pos, "r": 34.0, "life": 1.4, "max": 1.4,
					"col": Color(0.35, 1.0, 0.9), "enemy": true})
				g.fx.append({"kind": "tide_link", "a": o.pos, "b": e.pos, "life": 1.0, "max": 1.0,
					"col": Color(0.35, 1.0, 0.9), "enemy": true})
			o.dead = true
	e.dmg *= 1.6
	e.spd = maxf(e.spd, 58.0)
	e.r = 46.0
	e.r0 = 46.0
	e["transform_started"] = g.t
	e["transform_until"] = g.t + 0.9
	e.wind = maxf(e.wind, 0.9)
	e.pose = 0.0
	e.cdt = maxf(e.cdt, 0.9)
	g.warns = g.warns.filter(func(w): return not is_same(w.owner, e))
	g.vfx.show_banner("伊莎玛拉 完成了转化！")
	Sfx.play("roar", 2.0, 0.6, 0.0)
	g.vfx.shake_screen(1.2)


## 伊莎玛拉强度上调（docs/38 §8.6）：过了卡点后轮换恢复时间 ×boss/ishar_gate_haste（0.8）
func _ishar_haste(e: Dictionary) -> float:
	return Bal.v("boss/ishar_gate_haste", 0.8) if int(e.get("gates_passed", 0)) >= 1 else 1.0
