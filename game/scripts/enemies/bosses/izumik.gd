## 伊祖米克（type izumik，docs/38 §2.6 / §8.7；招式改版 docs/95 §3，10-14）
## Boss 行为脚本（docs/55 §6 拆分，10-10）：状态仍在敌人字典 e 上，预警 / 冷却 / 迫近经基类转给 boss_ai.gd。本文件只有这只 Boss 自己的招式与阶段逻辑。
## 4 招：A 潮汐坠落（① 弧形 5 圈，patterns 数据）/ B 解读旋涡（④ 缺口环 2 波，patterns 数据）/ C 分享（③ 扇形；学习期吸收即放小扇、阐释阶段正式招，手写，原作技能名）
##      / D 震撼（⑤ 全场·必须冲刺；66% 后 25 秒、33% 后 20 秒并带 4 秒持续法伤，原作技能名）
## 机制不占名额：学习期 / 子代 / 吸收 / 灯柱
extends "res://scripts/enemies/bosses/boss_base.gd"

const COL := Color(0.5, 1.0, 0.7)
const MOVES := ["潮汐坠落", "解读旋涡", "分享", "震撼"]


## 每帧（boss_ai._boss_ai 公共段之后）：ready = 本帧可以出招；mate = 接潮搭档（没有则 null）
func step(e: Dictionary, dt: float, dir: Vector2, dist: float, ready: bool, _mate) -> void:
	if e.phase == 1:
		# 学习阶段（docs/38 §8.7）：固定 boss/izumik_learn（20）秒，无敌；血条从 35% 匀速涨到 100% 只是演出；子代回到本体被吸收 = 强化层数
		if not e.has("learn_t"):
			e.learn_t = Bal.v("boss/izumik_learn", 20.0)
			e.count_end = g.t + e.learn_t
			e.count_max = e.learn_t
		e.learn_t -= dt
		var lk: float = 1.0 - clampf(e.learn_t / maxf(1.0, e.count_max), 0.0, 1.0)
		e.hp = e.maxhp * (0.35 + 0.65 * lk)
		if e.bt > 4.0 * SKILL_COOLDOWN_SCALE:
			e.bt = 0.0
			for k in 2:
				var o: Dictionary = g.spawner.spawn_enemy("offspring", g.combat.arena_clamp(e.pos + Vector2.from_angle(g.rng_enemy.randf() * TAU) * 140.0))
				o.feed = true
				o.feed_to_id = e.id   # 喂食目标存 id 句柄（docs/101 B5：原生端只认 id）
				o.spd = 45.0
		if e.learn_t <= 0.0:
			e.phase = 2
			e.invuln = false
			e.bt = 0.0
			e.hp = e.maxhp
			e.act_t = 0.0
			e.count_end = 0.0
			e.dmg *= pow(1.0 + Bal.v("boss/izumik_layer_dmg", 0.08), int(e.get("izu_layers", 0)))
			_izumik_lamps(e)
			Sfx.play_cue("phase", e.type, "start")
			g.vfx.show_banner("伊祖米克进入「阐释」阶段！")
			Sfx.play("roar", 0.0, 0.8, 0.0)
			g.vfx.shake_screen(1.0)
	else:
		# 阐释阶段（docs/38 §8.7）：灯柱 + 震撼（原「全场地波」，改用原作名）
		_izumik_lamp_step(e, dt)
		_burn_step(e, dt)
		var gp: int = int(e.get("gates_passed", 0))
		if gp >= 2 and not e.has("tint2"):
			_tint2(e, Color(0.82, 1.1, 1.0))   # 33% 后常驻青绿着色（docs/95 §3.2 D）
		if gp >= 1 and not e.has("wave_next"):
			e.wave_next = g.t + 0.8   # 66% 卡点后先安静 0.8 秒
		if ready and gp >= 1 and g.t >= float(e.get("wave_next", INF)):
			_wave(e)
		elif ready and dist < 320.0 and _cd(e, "share", 10.0):
			_share(e, dir, false)


## 图鉴 / Boss 演练：直接进入二阶段的完整状态
func setup_preview_phase2(e: Dictionary) -> void:
	e.phase = 2
	e.hp = e.maxhp
	e.invuln = false
	e.bt = 0.0


func demo_moves(e: Dictionary) -> Array:
	return MOVES if e.phase == 2 else ["分享"]   # 学习期只有吸收即放的小「分享」


func force_move(e: Dictionary, name: String, dir: Vector2, dist: float) -> bool:
	if e.phase != 2:
		if name == "分享":
			_share(e, dir, true)
			return true
		return false
	match name:
		"分享":
			_share(e, dir, false)
			return true
		"震撼":
			e.gates_passed = maxi(int(e.get("gates_passed", 0)), 1)
			if not e.has("lamps"):
				_izumik_lamps(e)
			_wave(e)
			return true
		"潮汐坠落", "解读旋涡":
			e.pattern_force = name
			return g.bai.patterns.try_attack(e, dir, dist)
	return false


## C · 分享（PRTS 技能「分享」：对全场我方 100% 近战法术溅射）：学习期每吸收 1 只子代放一次窄扇（r200 半角 0.5，0.7 秒，e.dmg × 0.5）——
## 给拦截子代一个马上看得见的理由；阐释阶段正式招 r300 半角 1.0、追踪 0.3 + 锁定 1.3（总 1.6），e.dmg × 1.2（强化层已乘进 e.dmg）
func _share(e: Dictionary, dir: Vector2, small: bool) -> void:
	if small:
		_warn(e, "cone", 0.7, {"ang": dir.angle(), "r": 200.0, "half": 0.5, "act": "sweep", "name": "分享", "col": COL,
			"dmg": e.dmg * Bal.v("boss/izumik_share_small", 0.5), "arts": true, "lock": false})
	else:
		_warn(e, "cone", 1.6, {"ang": dir.angle(), "r": 300.0, "half": 1.0, "track": 0.3, "act": "sweep", "name": "分享", "col": COL,
			"dmg": e.dmg * Bal.v("boss/izumik_share_mult", 1.2), "arts": true})


## D · 震撼（PRTS 技能「震撼」）：蓄力 2 秒的全场地波，冲刺无敌或站在点亮的灯柱光圈里才躲得开；66% 后每 25 秒、33% 后每 20 秒，
## 33% 后命中者额外每秒 e.dmg × 0.12 法伤持续 4 秒（PRTS「每秒攻击力 12%」；走 lose_hp 的 Boss 持续伤害口径 ≤4%/秒）
func _wave(e: Dictionary) -> void:
	var gp: int = int(e.get("gates_passed", 0))
	var cd: float = Bal.v("boss/izumik_wave_cd2", 20.0) if gp >= 2 else Bal.v("boss/izumik_wave_cd", 25.0)
	var wt: float = Bal.v("boss/izumik_wave_charge", 2.0)
	e.wave_next = g.t + wt + cd
	Sfx.play("izu_wave_count", 0.7, 2.0 / maxf(wt, 0.5), 0.0)   # 地波读秒：文件 2 秒，按蓄力时长 wt 变速，结束正好落在结算
	_warn(e, "circle", wt, {"follow": true, "r": 2400.0, "act": "izu_wave", "name": "震撼", "must_dash": true, "col": COL,
		"dmg": minf(e.dmg * 2.0, g.max_hp * Bal.v("boss/izumik_wave_cap", 0.25)), "burn": (e.dmg * 0.12) if gp >= 2 else 0.0})
	Sfx.play("skill", -2.0, 0.6)


## 震撼命中后的持续法伤（boss_ai 的 izu_wave 结算写 e.burn_t / e.burn_dps）：每 0.5 秒结算一跳，来源 izu_burn（combat.BOSS_DOT）
func _burn_step(e: Dictionary, dt: float) -> void:
	if float(e.get("burn_t", 0.0)) <= 0.0:
		return
	e.burn_t -= dt
	e.burn_acc = float(e.get("burn_acc", 0.0)) + dt
	if e.burn_acc >= 0.5:
		e.burn_acc -= 0.5
		var amt: float = g.combat.lose_hp(float(e.burn_dps) * 0.5, "izu_burn", true)
		if amt >= 1.0:
			g.hurt_flash = maxf(g.hurt_flash, 0.06)
			g.vfx.add_text(g.ppos + Vector2(0, -80), "-%d 震撼" % int(amt), COL, 14)


## ---- 伊祖米克（docs/38 §8.7）
## 吸收子代：强化层数 +1（最多 izumik_layer_max 层，每层阐释阶段伤害 +izumik_layer_dmg）；借鉴项（docs/49 §5.2）：
## 每吸收一只学习期缩短 boss/izumik_absorb_cut 秒（缺省 0 = 不缩短）；学习期吸收即放一次小「分享」（docs/95 §3.2 C，用户 10-14 定）
func izumik_absorb(e: Dictionary) -> void:
	Sfx.play("izu_absorb", -9.5, 1.0, 0.0)   # 吸收子代
	e.izu_layers = mini(int(e.get("izu_layers", 0)) + 1, int(Bal.v("boss/izumik_layer_max", 5.0)))
	var cut: float = Bal.v("boss/izumik_absorb_cut", 0.0)
	if cut > 0.0 and e.has("learn_t"):
		e.learn_t -= cut
		e.count_end -= cut
	g.vfx.add_text(e.pos + Vector2(0, -50), "吸收 · 强化 %d" % e.izu_layers, Color(0.5, 1.0, 0.6), 16)
	if e.phase == 1 and not e.dead and Bal.v("boss/izumik_share_small", 0.5) > 0.0 and not g.warns.any(func(w): return is_same(w.owner, e) and not w.done):
		_share(e, (g.ppos - e.pos).normalized(), true)


## 灯柱：阐释阶段开始时在本体周围 220–300 处立 3 根（限制在场地内）。主控靠近 izumik_lamp_touch 内待 1 秒点亮；
## 点亮后形成 izumik_lamp_r（120）光圈：主控在里面每秒 +2 灯火、躲得开震撼；子代进光圈减速
func _izumik_lamps(e: Dictionary) -> void:
	e.lamp_r = Bal.v("boss/izumik_lamp_r", 120.0)
	e.lamps = []
	var a0: float = g.rng_enemy.randf() * TAU
	for k in 3:
		var p: Vector2 = g.combat.arena_clamp(e.pos + Vector2.from_angle(a0 + TAU * k / 3.0) * g.rng_enemy.randf_range(220.0, 300.0), 90.0)
		e.lamps.append({"pos": p, "lit": false, "prog": 0.0})


func _izumik_lamp_step(e: Dictionary, dt: float) -> void:
	var touch: float = Bal.v("boss/izumik_lamp_touch", 40.0)
	for l in e.get("lamps", []):
		if not l.lit:
			if g.ppos.distance_to(l.pos) < touch:
				l.prog += dt
				if l.prog >= 1.0:
					l.lit = true
					g.fx.append({"kind": "ring", "pos": l.pos, "r": e.lamp_r, "life": 0.6, "max": 0.6, "col": Color(1.4, 1.1, 0.5), "enemy": true})
					g.vfx.add_text(l.pos + Vector2(0, -40), "灯柱点亮", Color(1.0, 0.85, 0.4), 16)
					Sfx.play("izu_lamp_lit", -4.0, 1.0, 0.0)
			else:
				l.prog = maxf(0.0, l.prog - dt)
			continue
		if g.combat.ground_d(g.ppos, l.pos) < e.lamp_r:
			g.lamp = minf(g.lamp_cap, g.lamp + 2.0 * dt)
		for j in g.enemies_sys.query(l.pos, e.lamp_r):
			var o: Dictionary = g.enemies[j]
			if o.type == "offspring" and not o.dead:
				o.slow = maxf(o.slow, 0.2)


func izumik_safe(e: Dictionary) -> bool:
	for l in e.get("lamps", []):
		if l.lit and g.combat.ground_d(g.ppos, l.pos) < float(e.get("lamp_r", 120.0)):
			return true
	return false
