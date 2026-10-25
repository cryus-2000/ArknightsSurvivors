## 伊祖米克（type izumik，docs/38 §2.6 / §8.7；招式改版 docs/95 §3，10-14）
## Boss 行为脚本（docs/55 §6 拆分，10-10）：状态仍在敌人字典 e 上，预警 / 冷却 / 迫近经基类转给 boss_ai.gd。本文件只有这只 Boss 自己的招式与阶段逻辑。
## 4 招：A 潮汐坠落（① 弧形 5 圈，patterns 数据）/ B 解读旋涡（④ 缺口环 2 波，patterns 数据）/ C 分享（③ 扇形；学习期吸收即放小扇、阐释阶段正式招，手写，原作技能名）
##      / D 震撼（⑤ 全场·必须冲刺；66% 后 25 秒、33% 后 20 秒并带 4 秒持续法伤，原作技能名）
## 机制不占名额：学习期 / 子代 / 吸收 / 灯柱
## 主轴「拦截」（docs/142b §3.7 / §8.2，10-25；取材 PRTS「学习」召唤子代、吸收 5 次强化 1 层并回血、「震撼」75 / 50 / 25% 强制触发）：
##   一幕「阐释」（阐释阶段 100–66）：每 izumik_batch_cd（12）秒一批子代（4–6 只）从场边一个方向走向她（每秒 70），主轴目标；
##     走到她身边被吸收：每 5 只强化 1 层（伤害 +15%，最多 4 层）并回 5% 生命；队长身边的金色箭头指向这一批的来向
##   二幕「学习」（66–33）：一次两个方向；走到她身边的子代在她脚下结茧 4 秒（主轴目标，青色倒计时环），茧没打掉才被吸收
##   三幕「分享」（33–0）：不再来子代；4 根灯柱全部点亮；每 12 秒「分享·全场」（预告 3 秒 + 蓄力 1.6 秒），站在灯柱光圈里或冲刺无敌不受伤，
##     每次分享后你躲进的那根灯柱熄灭（不能再点）；分享扇形改三叶扇
##   震撼：原来 66% / 33% 后的周期地波改成按原作阈值 75 / 50 / 25% 各强制一次（izumik_shock_at）
extends "res://scripts/enemies/bosses/boss_base.gd"

const COL := Color(0.4, 0.6, 1.0)   # 群青蓝（docs/142b §8.4）
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
			e.vis_act = "root_end"   # 扎根收势 e_izumik_root_end（纯画面）
			e.vis_t0 = g.t
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
		_rule_banner("izumik_axis", "拦截：子代从场边走向她，迎上去半路截杀，别让它们被吸收")
		_batch_step(e)
		var shock: Array = [0.75, 0.5, 0.25]
		var si: int = int(e.get("shock_i", 0))
		if ready and si < shock.size() and e.hp < e.maxhp * float(shock[si]):
			e.shock_i = si + 1
			_wave(e)
		elif ready and gp >= 2 and g.t >= float(e.get("share_all_next", INF)):
			_share_all(e)
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
	elif int(e.get("gates_passed", 0)) >= 2:
		# 三幕三叶扇（docs/142b §8.2「拦路」：在去下一根灯柱的路上）：三片窄扇（半角 0.35）互成 120°，第一片追踪你
		for k in 3:
			_warn(e, "cone", 1.6, {"ang": dir.angle() + TAU * k / 3.0, "r": 300.0, "half": 0.35, "track": 0.3 if k == 0 else 0.0, "act": "sweep",
				"name": "分享" if k == 0 else "", "col": COL, "dmg": e.dmg * Bal.v("boss/izumik_share_mult", 1.2), "arts": true, "lock": k == 0})
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
		if l.get("out", false):
			continue   # 三幕分享后熄灭的灯柱不能再点（docs/142b §3.7）
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
				g.enemies_sys.add_cc(o, -INF, 0.2)


## ---- 主轴「拦截」（docs/142b §3.7）
## 子代批次 e.batch：spawn_enemy("offspring")，feed 走向她（enemies.gd 的喂食移动；引擎只在学习期吸收，阐释阶段由这里判到身边），part = 主轴目标
func _batch_step(e: Dictionary) -> void:
	var gp: int = int(e.get("gates_passed", 0))
	var live: Array = []
	for o in e.get("batch", []):
		if o.dead:
			continue
		if o.get("izu_cocoon", false):
			if g.t >= float(o.cocoon_until):
				o.dead = true
				g.fx.append({"kind": "ring", "pos": o.pos, "r": 30.0, "life": 0.4, "max": 0.4, "col": COL, "enemy": true})
				_absorb2(e)
			else:
				live.append(o)
			continue
		if o.pos.distance_to(e.pos) < e.r + o.r + 10.0:
			if gp >= 1:
				_cocoon(e, o)
				live.append(o)
			else:
				o.dead = true
				_absorb2(e)
			continue
		live.append(o)
	e.batch = live
	if gp >= 2:
		return
	if not e.has("batch_next"):
		e.batch_next = g.t + 2.0
	if g.t < float(e.batch_next):
		return
	e.batch_next = g.t + Bal.v("boss/izumik_batch_cd", 12.0)
	var a0: float = g.rng_enemy.randf() * TAU
	var dirs: Array = [a0]
	if gp >= 1:
		dirs.append(a0 + PI + g.rng_enemy.randf_range(-0.7, 0.7))
	for di in dirs.size():
		var a: float = dirs[di]
		var n: int = g.rng_enemy.randi_range(4, 6) if dirs.size() == 1 else g.rng_enemy.randi_range(3, 4)
		var c: Vector2 = g.combat.arena_clamp(e.pos + Vector2.from_angle(a) * Bal.v("boss/izumik_batch_dist", 700.0), 60.0)
		for k in n:
			var p: Vector2 = g.combat.arena_clamp(c + Vector2.from_angle(a + PI * 0.5) * (float(k) - (n - 1) * 0.5) * 34.0, 60.0)
			var o: Dictionary = g.spawner.spawn_enemy("offspring", p)
			o.feed = true
			o.feed_to_id = e.id
			o.spd = Bal.v("boss/izumik_batch_spd", 70.0)
			o.part = true
			o.izu_dir = di
			g.enemies_sys.part_add(o)
			live.append(o)
	e.batch = live
	e.batch_t = g.t
	g.vfx.add_text(e.pos + Vector2(0, -60), "子代来袭", COL, 16)
	Sfx.play("tentacle", -5.0, 0.8)


## 二幕：走到她身边的子代原地结茧 izumik_cocoon_t（4）秒（不再走、不打人），茧没被打掉就吸收
func _cocoon(e: Dictionary, o: Dictionary) -> void:
	o.izu_cocoon = true
	o.cocoon_until = g.t + Bal.v("boss/izumik_cocoon_t", 4.0)
	o.feed = false
	o.ai = "static"
	o.spd = 0.0
	o.dmg = 0.0
	o.extra_next = INF
	o.pos = g.combat.arena_clamp(e.pos + (o.pos - e.pos).normalized() * (e.r + 30.0), 60.0)
	g.vfx.add_text(o.pos + Vector2(0, -36), "结茧", COL, 13)


## 阐释阶段的吸收：每 izumik_absorb_need（5）只强化 1 层（伤害 × (1 + izumik_stack_dmg 0.15)，最多 izumik_stack_max 4 层）并回 izumik_stack_heal（5%）生命
func _absorb2(e: Dictionary) -> void:
	Sfx.play("izu_absorb", -9.5, 1.0, 0.0)
	e.absorb_n = int(e.get("absorb_n", 0)) + 1
	var need: int = maxi(1, int(Bal.v("boss/izumik_absorb_need", 5.0)))
	if e.absorb_n % need == 0 and int(e.get("izu_stacks", 0)) < int(Bal.v("boss/izumik_stack_max", 4.0)):
		e.izu_stacks = int(e.get("izu_stacks", 0)) + 1
		e.dmg *= 1.0 + Bal.v("boss/izumik_stack_dmg", 0.15)
		e.hp = minf(e.maxhp, e.hp + e.maxhp * Bal.v("boss/izumik_stack_heal", 0.05))
		g.vfx.add_text(e.pos + Vector2(0, -60), "吸收 · 强化 %d 层" % int(e.izu_stacks), Color(0.5, 1.0, 0.6), 18)
		g.fx.append({"kind": "ring", "pos": e.pos, "r": e.r * 2.0, "life": 0.5, "max": 0.5, "col": Color(0.5, 1.0, 0.6), "enemy": true})
	else:
		g.vfx.add_text(e.pos + Vector2(0, -50), "吸收 %d / %d" % [e.absorb_n % need, need], Color(0.5, 1.0, 0.6), 14)


## 三幕「分享·全场」：借震撼的全场判定（telegraph izu_wave：冲刺无敌或灯柱光圈里不受伤），带 share_all——结算后你躲进的那根灯柱熄灭
func _share_all(e: Dictionary) -> void:
	e.share_all_next = g.t + Bal.v("boss/izumik_share_all_cd", 12.0)
	var dur: float = Bal.v("boss/izumik_share_all_warn", 3.0) + Bal.v("boss/izumik_share_all_charge", 1.6)
	_warn(e, "circle", dur, {"follow": true, "r": 2400.0, "act": "izu_wave", "name": "分享·全场", "must_dash": true, "col": COL,
		"dmg": minf(e.dmg * 1.5, g.max_hp * Bal.v("boss/izumik_share_all_cap", 0.2)), "share_all": true, "arts": true})
	Sfx.play("skill", -2.0, 0.8)


## 过卡点：二幕横幅；三幕灯柱重排成 4 根全亮、4 秒后第一次全场分享
func on_gate(e: Dictionary) -> void:
	if e.phase != 2:
		return
	var gp: int = int(e.get("gates_passed", 0))
	if gp == 1:
		_rule_banner("izumik_p2", "学习：子代分两路来，到她脚下会结茧 4 秒，打掉茧")
	elif gp >= 2:
		e.lamp_r = Bal.v("boss/izumik_lamp_r", 120.0)
		e.lamps = []
		var a0: float = g.rng_enemy.randf() * TAU
		for k in 4:
			var p: Vector2 = g.combat.arena_clamp(e.pos + Vector2.from_angle(a0 + TAU * k / 4.0) * 280.0, 90.0)
			e.lamps.append({"pos": p, "lit": true, "prog": 1.0})
			g.fx.append({"kind": "ring", "pos": p, "r": e.lamp_r, "life": 0.6, "max": 0.6, "col": Color(1.4, 1.1, 0.5), "enemy": true})
		e.share_all_next = g.t + 4.0
		_rule_banner("izumik_p3", "分享：每 12 秒全场分享，躲进灯柱光圈；躲过的那根会熄灭")


## 本体倒下：茧一起散（还在走的子代由 combat 的喂食清理带走）
func on_kill(e: Dictionary) -> void:
	for o in e.get("batch", []):
		o.dead = true


func izumik_safe(e: Dictionary) -> bool:
	for l in e.get("lamps", []):
		if l.lit and g.combat.ground_d(g.ppos, l.pos) < float(e.get("lamp_r", 120.0)):
			return true
	return false
