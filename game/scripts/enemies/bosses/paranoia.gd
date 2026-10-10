## 偏执泡影（type paranoia，docs/38 §2.4 / §8.5）
## Boss 行为脚本（docs/55 §6 拆分，10-10）：状态仍在敌人字典 e 上，预警 / 冷却 / 迫近经基类转给 boss_ai.gd。本文件只有这只 Boss 自己的招式与阶段逻辑。
extends "res://scripts/enemies/bosses/boss_base.gd"


## 每帧（boss_ai._boss_ai 公共段之后）：ready = 本帧可以出招；mate = 接潮搭档（没有则 null）
func step(e: Dictionary, dt: float, dir: Vector2, dist: float, ready: bool, _mate) -> void:
	# "偏执泡影"：一阶段 环形弹幕 + 多重凝视；归零结茧（docs/38 §8.5）；二阶段 泡影爆裂、多重凝视、子弹落地留溟痕
	if e.get("cocoon_t", 0.0) > 0.0:
		_paranoia_cocoon_step(e, dt)
		return
	_paranoia_aura(e, dist)
	if ready:
		# 一阶段悬浮远程时的迫近（泡影漂近，协调人 9/30 定 b；close6b：落地前 on_boss 0.01–0.10，用时一一对应）
		if e.phase == 1 and _close_in(e, dir, dist, "paranoia", "泡影漂近", Color(0.85, 0.45, 1.0)) >= 0.0:
			pass
		elif _cd(e, "gaze", 11.0):
			# 多重凝视：只打主控，依次高亮、间隔 0.6 秒，都可以走开躲；一阶段 2 道、二阶段 3 道，茧没打破再 +1
			var ng: int = (2 if e.phase == 1 else 3) + int(e.get("gaze_bonus", 0))
			for k in ng:
				_warn(e, "line", 1.3 + 0.6 * k, {"ang": dir.angle(), "len": 820.0, "wid": 26.0, "track": 0.65 + 0.6 * k, "act": "beam",
					"name": "凝视" if k == 0 else "", "col": Color(0.9, 0.4, 1.0), "dmg": e.dmg * 2.0, "corrode": 0.5, "lock": k == 0})
		elif e.phase == 1:
			if _cd(e, "ring", 6.0):
				_warn(e, "circle", 0.6, {"follow": true, "r": 46.0, "act": "bring", "name": "泡影", "col": Color(0.8, 0.5, 1.0), "dmg": e.dmg * 0.6})
		else:
			if _cd(e, "burst", 7.0):
				var a0: float = g.rng.randf() * TAU
				for k in 4:
					_warn(e, "circle", 1.0, {"pos": g.ppos + Vector2.from_angle(a0 + TAU * k / 4.0) * 88.0, "r": 70.0, "act": "burst", "name": "泡影爆裂" if k == 0 else "", "col": Color(0.85, 0.45, 1.0), "dmg": e.dmg * 1.2, "corrode": 0.5, "lock": k == 0})


## 图鉴 / Boss 演练：直接进入二阶段的完整状态
func setup_preview_phase2(e: Dictionary) -> void:
	_paranoia_p2(e)


## ---- 偏执泡影（docs/38 §8.5）
## 二阶段状态（破茧后 / 图鉴预览共用）：失去悬浮、转近战、弱物理、伤害 ×1.2
func _paranoia_p2(e: Dictionary) -> void:
	if e.phase == 2:
		return
	e.phase = 2
	e.range = 400.0
	e.weak = "物理"
	e.dmg *= 1.2
	e.hover_lost = true
	e.ai = "melee"
	e.spd = 70.0


## 认知负担光环：主控站在 boss/paranoia_aura_r（220）内时，全队攻速 ×(1 − paranoia_aura_aspd)（stats 来源 "paranoia_aura"）
func _paranoia_aura(e: Dictionary, dist: float) -> void:
	e.burden_r = Bal.v("boss/paranoia_aura_r", 220.0)   # 画面读这个半径画地面符文圈
	var inside: bool = dist < e.burden_r
	if inside != e.get("burden_in", false):
		e.burden_in = inside
		g.stats.remove_source("paranoia_aura")
		if inside:
			g.stats.add(&"op_aspd", "mult", 1.0 - Bal.v("boss/paranoia_aura_aspd", 0.10), "paranoia_aura")
		g.sync_stats()


## 第一次血量归零：结成泡影茧 boss/paranoia_cocoon 秒。本体无敌，外壳是部件（shell_hp = 最大生命 × paranoia_shell），会吐慢速弹；
## 场地收到 paranoia_arena2。打破外壳 → 复活到 paranoia_revive（40%）并进入 5 秒大破绽；没打破 → 同样复活，但凝视永久 +1 道
func paranoia_cocoon(e: Dictionary) -> void:
	Sfx.play_cue("phase", e.type, "start")
	e.cocoon_done = true
	e.cocoon_t = Bal.v("boss/paranoia_cocoon", 8.0)
	Sfx.play("cocoon_form", -7.3, 1.0, 0.0)   # 结茧（tools/gen_sfx_boss_events.py），垫在阶段音下面
	e.hp = 1.0
	e.invuln = true
	e.part = true
	e.shell_max = e.maxhp * Bal.v("boss/paranoia_shell", 0.08)
	e.shell_hp = e.shell_max
	e.shell_room = 0.0
	e.count_end = g.t + e.cocoon_t
	e.count_max = e.cocoon_t
	e.shell_shot = 0.0
	g.warns = g.warns.filter(func(w): return not is_same(w.owner, e))
	g.stats.remove_source("paranoia_aura")
	e.burden_in = false
	g.sync_stats()
	if g.zone_frozen:
		g.combat.freeze_zone(Bal.v("boss/paranoia_arena2", 520.0))
	g.vfx.show_banner("\"偏执泡影\" 结茧 —— 打破外壳", 3)
	Sfx.play("roar", -2.0, 1.1, 0.0)


func _paranoia_cocoon_step(e: Dictionary, dt: float) -> void:
	e.cocoon_t -= dt
	# 外壳受伤额度按秒补充（combat.damage 里截），最多攒 0.5 秒的量
	var rate: float = e.shell_max / maxf(0.5, Bal.v("boss/paranoia_shell_min", 4.0))
	e.shell_room = minf(e.get("shell_room", 0.0) + rate * dt, rate * 0.5)
	e.shell_shot -= dt
	if e.shell_shot <= 0.0:
		e.shell_shot = 2.0
		for k in 8:
			g.ebullets.append({"pos": e.pos, "vel": Vector2.from_angle(TAU * k / 8.0 + g.t) * 120.0, "dmg": e.dmg * 0.4, "slow": false, "r": 7.0,
				"life": 3.0, "corrode": 0.0, "nerve": 0.0, "true": false, "kind": "nova", "home": false, "boss": true, "src_type": e.type})
	if e.cocoon_t <= 0.0:
		paranoia_hatch(e, false)


func paranoia_hatch(e: Dictionary, broken: bool) -> void:
	e.cocoon_t = 0.0
	e.shell_hp = 0.0
	e.part = false
	e.invuln = false
	e.count_end = 0.0
	e.hp = e.maxhp * Bal.v("boss/paranoia_revive", 0.4)
	_paranoia_p2(e)
	g.fx.append({"kind": "ring", "pos": e.pos, "r": e.r * 3.0, "life": 0.6, "max": 0.6, "col": Color(0.85, 0.45, 1.0), "enemy": true})
	if broken:
		g.combat.start_break(e, Bal.v("boss/paranoia_hatch_break", 5.0))
		g.vfx.add_text(e.pos + Vector2(0, -70), "破茧！", Color(1.0, 0.85, 0.4), 22)
	else:
		e.gaze_bonus = int(e.get("gaze_bonus", 0)) + 1
		g.vfx.add_text(e.pos + Vector2(0, -70), "蜕变 —— 凝视 +1", Color(0.9, 0.4, 1.0), 20)
	Sfx.play("shell_break" if broken else "cocoon_revive", 2.0 if broken else -5.2, 1.0, 0.0)   # 破茧 / 超时蜕变
