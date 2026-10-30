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
## 连携（docs/170，10-27）：阐释阶段每幕轮换两组连携，每组 = 起手蓄势（海嗣根须颗粒、短停）→ ≤4 段 → 收招破绽。
##   转幕 / 外部眩晕 / 韧性破绽 / 震撼 清掉未出的段；弹幕只用 izu_* 字段由本文件逐帧改速度，移动与命中仍走 shot_pool。
##   boss/izumik_cards = 0 退回旧轮转（云端 A/B）。连携组与新弹幕都是本作改编，组名只给文档 / 测试用，不上界面。
extends "res://scripts/enemies/bosses/boss_base.gd"

const Beam = preload("res://scripts/render/boss_beam.gd")
const COL := Color(0.4, 0.6, 1.0)   # 群青蓝（docs/142b §8.4）
const MOVES := ["潮汐坠落", "解读旋涡", "分享", "震撼"]
const PATTERNS := ["潮汐相位流", "子代共鸣", "螺旋弹臂", "习得弹", "回流弹", "潮门环", "习得路径", "孢子潮", "信息回传"]
const TENTACLE := "护群触腕"   # 追人圆形触腕（用户 10-28：换圆形、追着人打），不走 finals 的扇形
const CURRENT := "海流牵引"
const BROOD := "子代化生"   # 三幕独有（PRTS 子代「被阻挡时立即变为随机敌人」；用户 10-28：去掉幕内重复招、结合原作设定）   # 非弹幕专属招：海流把你往漩涡中心拖，中心最后涌起
## 每幕两组；「@近身分享」= 贴近时分享扇、否则潮汐坠落
## 缺口按幕递进（用户 10-28）：一幕固定缺口教学；二幕旋转 / 错位缺口 + 停住再射；三幕缝隙收窄、弹数与段数加多，
## 冲刺穿越的整墙（迁徙潮）只在三幕偶尔用
const CARDS := [
	[{"name": "迁徙潮汐", "segs": ["@潮汐相位流", "海流牵引", "@潮门环"]},
		{"name": "护群共鸣", "segs": ["护群触腕", "@子代共鸣", "潮汐坠落"]}],
	[{"name": "解读螺旋", "segs": ["@螺旋弹臂", "解读旋涡", "深渊涌流"]},
		{"name": "习得变形", "segs": ["@习得弹", "@习得路径", "@信息回传"]}],
	[{"name": "灯下三叶", "segs": ["分享·全场", "迁徙潮", "分享"]},
		{"name": "深蓝回流", "segs": ["@回流弹", "@孢子潮", "子代化生"]}]]
## 每幕躲法主题与行为（用户 10-28「每个阶段重复少、有自己的特色」，docs/170 §18）：一幕站定（在海流里找路）/ 二幕游走（读针阵）/ 三幕追人（孢子间穿行）
const ACT_MOVE := [0.0, 45.0, 50.0]
## 分阶段风格（用户 10-28「每个阶段做出不同风格」，docs/170 §16）：每幕段间节奏 / 弹形不同，弹色全程统一群青（用户 10-28「统一更有记忆点」），招式各幕独有
const SEG_GAPS := [0.7, 0.4, 0.65]   # 一幕慢、二幕快碎、三幕重（每段之间停顿长、段本身重）
const ACT_KIND := ["orb", "nerve", "nova"]   # 圆珠 / 梭形孢子针（按速度方向转）/ 脉动大孢子
const ACT_TINT := [Color(1, 1, 1), Color(1.0, 0.86, 1.14), Color(0.82, 1.1, 1.0)]
const DECLARE := 1.0      # 起手蓄势短停
const SEG_GAP := 0.5      # 段间收势（用户 10-27：给玩家出手机会）
const RECOVER := [2.6, 3.0, 3.6]   # 每幕收招破绽（用户 10-27：给干员输出的时间）
const REST := 1.6         # 破绽后到下一组起手之间的空档
const CARD_CAP := 30.0    # 保护性上限
const OWN_CAP := 150      # 本体同时在场弹数
## 潮门环每幕参数：一圈弹数 / 缺口占几格（三幕两道对开窄缝各占这么多）/ 圈数 / 圈间隔 / 每圈缺口错开（弧度）
const GATE_N := [20, 24, 24]
const GATE_SLOTS := [4, 3, 2]
const GATE_RINGS := [3, 4, 4]
const GATE_GAP := [0.8, 0.75, 0.65]
const GATE_STEP := [0.0, 0.3, 0.25]


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
		# 用户 10-30「一开始的水母可以多一点，现在队友能全部清完」：每 izumik_learn_cd 秒 izumik_learn_n 只，子代血量 × izumik_off_hp（仍不近战伤人，10-27）
		if e.bt > Bal.v("boss/izumik_learn_cd", 4.0) * SKILL_COOLDOWN_SCALE:
			e.bt = 0.0
			for k in int(Bal.v("boss/izumik_learn_n", 2.0)):
				var o: Dictionary = g.spawner.spawn_enemy("offspring", _offspring_edge(e, g.rng_enemy.randf() * TAU))
				o.feed = true
				o.feed_to_id = e.id   # 喂食目标存 id 句柄（docs/101 B5：原生端只认 id）
				o.spd = Bal.v("boss/izumik_learn_spd", 45.0)
				_beef(o)
				_tame(o)
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
		if gp >= 1 and e.get("tint2") != ACT_TINT[mini(gp, 2)]:
			_tint2(e, ACT_TINT[mini(gp, 2)])   # 二幕紫晶、三幕常驻青绿着色（docs/95 §3.2 D；docs/170 §16）
		_trail_step(e)
		_batch_step(e)
		if Bal.v("boss/izumik_cards", 1.0) > 0.0:
			# 符卡接管全部出招：旧共用轮转与数据招式只经 force_move 点名
			e.final_next = INF
			e.pattern_next = INF
			_bullet_step(e, dt)
			_emit_step(e)
			_current_step(e, dt)
			_move_step(e, dt)
			_tentacle_step(e)
			_share_fx_step(e)
			_card_step(e, dir, dist)
			return
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
	return MOVES + g.bai.finals.NAMES["izumik"] + PATTERNS + [CURRENT] if e.phase == 2 else ["分享"]   # 学习期只有吸收即放的小「分享」


## 全部连携组名（按幕顺序；文档 / 测试 / 预览用）
func card_names() -> Array:
	var out: Array = []
	for act in CARDS:
		for c in act:
			out.append(c.name)
	return out


func force_move(e: Dictionary, name: String, dir: Vector2, dist: float) -> bool:
	if e.phase == 2 and card_names().has(name):
		_end_card(e)
		_start_card(e, name)
		return true
	if e.phase == 2 and PATTERNS.has(name):
		return _emit_start(e, name, dir)
	if e.phase == 2 and name == CURRENT:
		_current(e)
		return true
	if e.phase == 2 and name == TENTACLE:
		_tentacles(e)
		return true
	if g.bai.finals.force_move(e, name, dir, dist):
		return true
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
			_warn(e, "cone", 1.6, {"ang": dir.angle() + TAU * k / 3.0, "r": 300.0, "half": 0.35, "track": 0.3, "aim_offset": TAU * k / 3.0, "act": "sweep",
				"name": "分享" if k == 0 else "", "col": COL, "dmg": e.dmg * Bal.v("boss/izumik_share_mult", 1.2), "arts": true, "lock": k == 0})
	else:
		_warn(e, "cone", 1.6, {"ang": dir.angle(), "r": 300.0, "half": 1.0, "track": 0.3, "act": "sweep", "name": "分享", "col": COL,
			"dmg": e.dmg * Bal.v("boss/izumik_share_mult", 1.2), "arts": true})


## D · 震撼（PRTS 技能「震撼」）：蓄力 5 秒（10-28 由 2 秒加长）的全场地波，冲刺无敌或站在点亮的灯柱光圈里才躲得开；66% 后每 25 秒、33% 后每 20 秒，
## 33% 后命中者额外每秒 e.dmg × 0.12 法伤持续 4 秒（PRTS「每秒攻击力 12%」；走 lose_hp 的 Boss 持续伤害口径 ≤4%/秒）
func _wave(e: Dictionary) -> void:
	var gp: int = int(e.get("gates_passed", 0))
	var cd: float = Bal.v("boss/izumik_wave_cd2", 20.0) if gp >= 2 else Bal.v("boss/izumik_wave_cd", 25.0)
	# 蓄力 2 → 5 秒（用户 10-28：1.5 倍速下反应不过来）→ 3.5 秒（用户 10-30）；读秒警告音取消（10-28）。预警圈 / 灯柱提示按预警时长走，自动同步
	var wt: float = Bal.v("boss/izumik_wave_charge", 3.5)
	e.wave_next = g.t + wt + cd
	_warn(e, "circle", wt, {"follow": true, "r": 2400.0, "act": "izu_wave", "name": "震撼", "must_dash": true, "col": COL,
		"dmg": minf(e.dmg * 2.0, g.max_hp * Bal.v("boss/izumik_wave_cap", 0.25)), "burn": (e.dmg * 0.12) if gp >= 2 else 0.0})


## 震撼 / 分享·全场结算画面（telegraph izu_wave 调用）：从本体推开一圈海浪（render/izumik_attack_draw.shock），浪头甩出水沫颗粒；纯画面
func wave_fx(e: Dictionary, _w: Dictionary) -> void:
	g.fx.append({"kind": "izu_shock", "pos": e.pos, "owner": e, "life": 1.1, "max": 1.1, "enemy": true})
	for k in 40:
		var d := Vector2.from_angle(TAU * k / 40.0)
		_puff(e.pos + Vector2(d.x * 60.0, d.y * 43.0), 1, Color(0.6, 0.82, 1.0), d)
	g.vfx.shake_screen(0.6)


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
		var n: int = g.rng_enemy.randi_range(int(Bal.v("boss/izumik_batch_min", 4.0)), int(Bal.v("boss/izumik_batch_max", 6.0))) if dirs.size() == 1 else 3   # 一幕一路（10-30 可调）；二幕两路各 3 只（用户 10-27：二幕少一点）
		for k in n:
			var p: Vector2 = _offspring_edge(e, a + (float(k) - (n - 1) * 0.5) * 0.09)
			var o: Dictionary = g.spawner.spawn_enemy("offspring", p)
			o.feed = true
			o.feed_to_id = e.id
			o.spd = Bal.v("boss/izumik_batch_spd", 45.0)
			if gp == 0:
				_beef(o)
				o.spd = Bal.v("boss/izumik_learn_spd", o.spd)   # 一幕批次与学习期同速（10-30：子代要真的走得到她身边）
			o.part = true
			o.izu_dir = di
			_tame(o)
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
	# 转幕：清掉未出的段，短停后进下一幕的连携（在场弹幕与已出的预警照常结算）
	_end_card(e)
	e.izu_next = g.t + 1.5
	e.izu_card_n = 0   # 每幕都从本幕第一组连携起（docs/201 §8：原来随上一幕计数奇偶，三幕低压在 0.34 / 0.41 之间摇摆）
	var gp: int = int(e.get("gates_passed", 0))
	if gp >= 2:
		e.lamp_r = Bal.v("boss/izumik_lamp_r", 120.0)
		e.lamps = []
		var a0: float = g.rng_enemy.randf() * TAU
		for k in 4:
			var p: Vector2 = g.combat.arena_clamp(e.pos + Vector2.from_angle(a0 + TAU * k / 4.0) * 280.0, 90.0)
			e.lamps.append({"pos": p, "lit": true, "prog": 1.0})
			g.fx.append({"kind": "ring", "pos": p, "r": e.lamp_r, "life": 0.6, "max": 0.6, "col": Color(1.4, 1.1, 0.5), "enemy": true})
		e.share_all_next = g.t + 4.0


## 本体倒下：茧一起散（还在走的子代由 combat 的喂食清理带走）
func on_kill(e: Dictionary) -> void:
	e.izu_emit_bg = {}
	for o in e.get("batch", []) + e.get("izu_brood", []):
		o.dead = true
	_end_card(e)
	_clear_bullets(e)


func izumik_safe(e: Dictionary) -> bool:
	for l in e.get("lamps", []):
		if l.lit and g.combat.ground_d(g.ppos, l.pos) < float(e.get("lamp_r", 120.0)):
			return true
	return false


## 前段子代更肉（用户 10-30）：学习期与一幕批次的子代生命 × boss/izumik_off_hp
func _beef(o: Dictionary) -> void:
	var k: float = Bal.v("boss/izumik_off_hp", 1.0)
	o.maxhp *= k
	o.hp *= k


## 子代只走路、不伤人（用户 10-27：取消小水母近战、远程少一点）：无接触伤害、不出横扫、不放自己的孢子环；远程只剩本体点名的「子代共鸣」
func _tame(o: Dictionary) -> void:
	o.dmg = 0.0
	o.extra_next = INF
	o.nova_cd = INF


## Actual arena boundary, never a radius around the boss. Opposite sector prevents instant feeding.
func _offspring_edge(e: Dictionary, angle: float) -> Vector2:
	var center: Vector2 = g.zone_next_c if g.zone_frozen else g.zone_c
	var radius: float = maxf(200.0, g.zone_next_r - 65.0) if g.zone_frozen else maxf(500.0, g.zone_r - 65.0)
	var fallback: Vector2 = center - (e.pos - center).normalized() * radius
	if e.pos.distance_to(center) < 1.0:
		fallback = center + Vector2.from_angle(angle) * radius
	for k in 32:
		var offset: float = (ceili(k / 2.0) * (1.0 if k % 2 else -1.0)) * 0.2
		var p: Vector2 = center + Vector2.from_angle(angle + offset) * radius
		if p.distance_to(e.pos) < 380.0 or g.map.push_out(p, 18.0).distance_to(p) > 1.0:
			continue
		fallback = p
		if not g.map.segment_blocked(p, e.pos):
			return p
	return g.combat.arena_clamp(fallback, 65.0)


## ---- 连携（docs/170）
func _blocked(e: Dictionary) -> bool:
	return e.dead or e.get("invuln", false) or e.get("coma", false) or float(e.stun) > 0.0 or float(e.get("break_t", 0.0)) > 0.0 \
		or float(e.get("channel", 0.0)) > 0.0 or float(e.get("dash_t", 0.0)) > 0.0


func _card_step(e: Dictionary, dir: Vector2, dist: float) -> void:
	var active: bool = str(e.get("izu_card", "")) != ""
	# 外部眩晕 / 韧性破绽 / 超时：清队列，不给收招（破绽本身已是奖励）
	if active and (float(e.stun) > 0.0 or float(e.get("break_t", 0.0)) > 0.0 or g.t > float(e.get("izu_card_until", INF))):
		_end_card(e)
		return
	if g.t < float(e.get("izu_next", 0.0)) or _blocked(e):
		return
	var ov: bool = Bal.v("boss/izumik_overlap", 1.0) > 0.0
	var queue_peek: String = str(e.izu_queue[0]) if active and not e.izu_queue.is_empty() else ""
	if not _seg_free(e, ov, queue_peek):
		return
	if active:
		var queue: Array = e.izu_queue
		if queue.is_empty():
			if not e.get("izu_emit", {}).is_empty() or not e.get("izu_emit_bg", {}).is_empty() or int(e.get("izu_tent_n", 0)) > 0 \
					or g.warns.any(func(w): return is_same(w.owner, e) and not w.done and w.dmg > 0.0):
				return
			# 破绽会取消移动中的水墙：等它走完再收招；破绽窗口不叠弹幕——在场弹散到 boss/izumik_finish_live（原 8）颗以下再收招
			if g.bai.finals.hazards.any(func(h): return is_same(h.owner, e)) or int(e.get("izu_live", 0)) >= int(Bal.v("boss/izumik_finish_live", 20.0)) or g.ebullets.any(func(b): return b.life > 0.0 and str(b.get("izu", "")) == "spore"):   # 大孢子胀破完再收招
				return
			_finish_card(e)
			return
		_run_seg(e, str(queue.pop_front()), dir, dist)
		return
	# 组间先结算到阈值的震撼：只在一幕（75%）一次（docs/170 §18：标志招只放一幕；原作 75 / 50 / 25%）
	var shock: Array = [0.75]
	var si: int = int(e.get("shock_i", 0))
	if si < shock.size() and e.hp < e.maxhp * float(shock[si]):
		e.shock_i = si + 1
		_rise(e)
		_wave(e)
		e.izu_next = g.t + 0.6
		return
	_start_card(e, "")


func _start_card(e: Dictionary, name: String) -> void:
	var act: int = clampi(int(e.get("gates_passed", 0)), 0, CARDS.size() - 1)
	var card: Dictionary = {}
	if name == "":
		var n: int = int(e.get("izu_card_n", 0))
		card = CARDS[act][n % CARDS[act].size()]
		e.izu_card_n = n + 1
	else:
		for cards in CARDS:
			for c in cards:
				if c.name == name:
					card = c
	e.izu_card = card.name
	e.izu_queue = card.segs.duplicate()
	e.izu_card_until = g.t + CARD_CAP
	e.izu_next = g.t + DECLARE * _gap_k()
	_rise(e)


## 下一段能不能出（10-29 docs/201 §7：试炼承伤只有 21%/分，空档主要在「等上一段放完、预警结算完」）：
## boss/izumik_overlap = 0 → 旧规则（弹幕放完、触腕落完、有伤预警全部结算才接下一段）；
## = 1 → 重叠出招：上一段弹幕放了 izumik_overlap_lead（0.5）秒后转到后台继续放，下一段同时开始（后台最多一段）；
## 有伤预警 / 触腕不再挡下一段。不重叠的（防躲不开的墙）：潮门环（读缺口）前后都不叠；必须冲刺 / 全场（分享·全场、震撼）与移动水墙（迁徙潮）在场时照旧等
const NO_OVERLAP := ["潮门环"]
func _seg_free(e: Dictionary, ov: bool, nxt: String) -> bool:
	var em: Dictionary = e.get("izu_emit", {})
	if not ov:
		return em.is_empty() and int(e.get("izu_tent_n", 0)) <= 0 and not g.warns.any(func(w): return is_same(w.owner, e) and not w.done and w.dmg > 0.0)
	if g.warns.any(func(w): return is_same(w.owner, e) and not w.done and w.dmg > 0.0 and (w.get("must_dash", false) or w.get("share_all", false))):
		return false
	if g.bai.finals.hazards.any(func(h): return is_same(h.owner, e)):
		return false
	if em.is_empty():
		return true
	if not e.get("izu_emit_bg", {}).is_empty() or str(em.kind) in NO_OVERLAP or nxt.trim_prefix("@") in NO_OVERLAP:
		return false
	return g.t - float(em.t0) >= Bal.v("boss/izumik_overlap_lead", 0.5)


## 出招节奏（10-29 docs/201：机器人试炼每分钟只被打中约 1.3 下，太闲）：起手、段间停顿、破绽后空档统一 × boss/izumik_gap_k（缺省 1 = 原节奏）
func _gap_k() -> float:
	return Bal.v("boss/izumik_gap_k", 0.4)


func _finish_card(e: Dictionary) -> void:
	var rec: float = RECOVER[clampi(int(e.get("gates_passed", 0)), 0, RECOVER.size() - 1)] * Bal.v("boss/izumik_recover_mult", 0.6)
	_end_card(e)
	g.combat.start_break(e, rec)
	e.izu_next = g.t + rec + REST * _gap_k()


func _end_card(e: Dictionary) -> void:
	e.izu_card = ""
	e.izu_queue = []
	e.izu_emit = {}
	e.izu_emit_bg = {}


## 起手蓄势：本体脚下一圈群青颗粒向外扩、根须亮环，不闪白不出字
func _rise(e: Dictionary) -> void:
	e.izu_rise_t = g.t
	g.fx.append({"kind": "ring", "pos": e.pos, "r": 150.0, "life": 0.7, "max": 0.7, "col": Color(0.55, 0.75, 1.2), "enemy": true})
	for k in 24:
		var d := Vector2.from_angle(TAU * k / 24.0)
		_puff(e.pos + Vector2(d.x * 70.0, d.y * 50.0), 1, Color(0.62, 0.8, 1.0), d)
	Sfx.play("skill", -5.0, 0.7)


func _run_seg(e: Dictionary, seg: String, dir: Vector2, dist: float) -> void:
	e.izu_next = g.t + SEG_GAPS[_act(e)] * _gap_k()
	if seg == "@近身分享":
		if g.combat.ground_d(g.ppos, e.pos) < 320.0:
			_share(e, dir, false)
		else:
			_force_pattern(e, "潮汐坠落", dir, dist)
		return
	if seg.begins_with("@"):
		_emit_start(e, seg.substr(1), dir)
		return
	match seg:
		"分享·全场":
			_share_all(e)
		CURRENT:
			_current(e)
		TENTACLE:
			_tentacles(e)
		BROOD:
			_brood(e)
		"分享":
			_share(e, dir, false)
		"潮汐坠落", "解读旋涡":
			_force_pattern(e, seg, dir, dist)
		_:
			g.bai.finals.force_move(e, seg, dir, dist)


func _force_pattern(e: Dictionary, name: String, dir: Vector2, dist: float) -> void:
	e.pattern_force = name
	g.bai.patterns.try_attack(e, dir, minf(dist, 700.0))
	e.erase("pattern_force")
	e.pattern_next = INF


## 本体倒下：在场弹（含数据招式的环弹）化成颗粒
func _clear_bullets(e: Dictionary) -> void:
	var k := 0
	for b in g.ebullets:
		if b.life > 0.0 and int(b.get("source_id", -1)) == int(e.id):
			b.life = 0.0
			if k < 40:
				_puff(b.pos, 2, Color(0.6, 0.78, 1.0), Vector2.UP)
				k += 1


## 纯画面颗粒（g.vrng；低画质 / 颗粒层关闭时不画）
func _puff(p: Vector2, n: int, col: Color, d := Vector2.ZERO) -> void:
	if Cfg.quality == "low":
		return
	var pool = Beam.grains(g)
	if pool == null:
		return
	for i in Beam.take(g, n):
		pool.push("bfx_flash", p, d if d != Vector2.ZERO else Vector2.from_angle(g.vrng.randf() * TAU), col)


## ---- 弹幕（本作改编）：一段 = 一次发射计划 e.izu_emit；弹体进 g.ebullets，izu_* 字段由 _bullet_step 改速度
func _emit_start(e: Dictionary, kind: String, dir: Vector2) -> bool:
	var em := {"kind": kind, "t0": g.t, "next": g.t, "n": 0, "a0": dir.angle(), "until": g.t}
	match kind:
		"潮汐相位流":
			# 五条摆动水流；拦截路线（这一批子代的来向）落在两条流之间
			em.a0 = _lane_angle(e, dir) + TAU / (12.0 if _act(e) >= 2 else 8.0)   # 拦截路线正好在两条流中间
			em.until = g.t + 2.4
		"子代共鸣":
			var src: Array = []
			for o in e.get("batch", []):
				if not o.dead and src.size() < 3:
					src.append(o)
			if src.is_empty():
				src.append(e)
			em.sources = src
			em.next = g.t + 0.8
			em.until = g.t + 1.85   # 三轮（10-28 加压，原两轮）
			for s in src:
				g.fx.append({"kind": "ring", "pos": s.pos, "r": 34.0, "life": 0.8, "max": 0.8, "col": Color(0.55, 0.75, 1.2), "enemy": true})
		"螺旋弹臂":
			em.until = g.t + 3.0
			em.spin = 0.7 if int(e.get("izu_card_n", 0)) % 2 == 0 else -0.7
			em.arms = 2
		"习得弹":
			em.until = g.t + 0.65
		"回流弹":
			em.until = g.t + (1.85 if _act(e) >= 2 else 0.95)   # 三幕三圈（10-28 加压）
		"习得路径":
			# 二幕独有：沿你最近 2.5 秒的路线先亮起落点，0.5 秒后落下孢子针、停住 0.9 秒再一齐朝你射
			var pts: Array = []
			for p in e.get("izu_trail", []):
				if p.distance_to(g.ppos) > 90.0:
					pts.append(p)
			if pts.is_empty():
				return false
			em.trail = pts
			em.next = g.t + 0.5
			em.until = g.t + 0.5
			for p in pts:
				g.fx.append({"kind": "ring", "pos": p, "r": 18.0, "life": 0.5, "max": 0.5, "col": COL, "enemy": true})
		"信息回传":
			# 二幕独有（PRTS 子代「携带着从泰拉各地收集到的遗传信息返回母体」）：她脚下的每个茧把带回的信息一齐放出，各向外两圈孢子针——
			# 茧打得越干净这招越弱；没有茧时她身边结 2 个临时回传点
			var src: Array = []
			for o in e.get("batch", []):
				if not o.dead and o.get("izu_cocoon", false) and src.size() < 4:
					src.append(o.pos)
			if src.is_empty():
				var b0: float = (g.ppos - e.pos).angle()
				for k in 2:
					src.append(g.combat.arena_clamp(e.pos + Vector2.from_angle(b0 + PI * 0.5 + PI * k) * 110.0, 60.0))
			em.sources = src
			em.next = g.t + 0.7
			em.until = g.t + 1.25
			for p in src:
				g.fx.append({"kind": "ring", "pos": p, "r": 30.0, "life": 0.7, "max": 0.7, "col": COL, "enemy": true})
		"孢子潮":
			# 三幕独有：5 颗大孢子慢慢朝你漂（略微追踪），漂到尽头胀破成一圈 8 根小孢子针
			em.until = g.t
		"潮门环":
			# 一幕：缺口朝拦截路线、圈圈对齐不动（教学）；二幕：每圈错开；三幕：两道对开窄缝、圈更密
			var act: int = _act(e)
			em.a0 = _lane_angle(e, dir) if act == 0 else dir.angle()
			em.spin = GATE_STEP[act] * (1.0 if int(e.get("izu_card_n", 0)) % 2 == 0 else -1.0)
			em.until = g.t + GATE_GAP[act] * (GATE_RINGS[act] - 1)
		_:
			return false
	if not e.get("izu_emit", {}).is_empty():
		e.izu_emit_bg = e.izu_emit   # 重叠出招：上一段转后台继续放（_seg_free 已保证后台空着）
	e.izu_emit = em
	e.move_name = kind
	e.move_t = g.t
	Sfx.play("tentacle", -8.0, 1.15)
	return true


func _lane_angle(e: Dictionary, dir: Vector2) -> float:
	for o in e.get("batch", []):
		if not o.dead and not o.get("izu_cocoon", false):
			return (o.pos - e.pos).angle()
	return dir.angle()


func _emit_step(e: Dictionary) -> void:
	if _blocked(e):
		e.izu_emit = {}
		e.izu_emit_bg = {}
		return
	for key in ["izu_emit_bg", "izu_emit"]:
		var em: Dictionary = e.get(key, {})
		if em.is_empty():
			continue
		var guard := 0
		while g.t >= float(em.next) and float(em.next) <= float(em.until) + 0.001 and guard < 8:
			guard += 1
			_emit_once(e, em)
			em.n = int(em.n) + 1
		if g.t > float(em.until):
			e[key] = {}
			if key == "izu_emit" and Bal.v("boss/izumik_overlap", 1.0) <= 0.0:
				e.izu_next = maxf(float(e.get("izu_next", 0.0)), g.t + SEG_GAPS[_act(e)] * _gap_k())


func _emit_once(e: Dictionary, em: Dictionary) -> void:
	var n: int = int(em.n)
	var a0: float = float(em.a0)
	match str(em.kind):
		"潮汐相位流":
			var arms: int = 6 if _act(e) >= 2 else 4   # 三幕六条流，流间更窄
			for k in arms:
				var a: float = a0 + TAU * k / float(arms)
				_shot(e, e.pos + Vector2.from_angle(a) * 30.0, a, 125.0, 6.0, 4.5, 0.45, {"izu": "wave", "izu_ph": PI * (k % 2), "izu_amp": 0.9})
			em.next = float(em.next) + 0.3 * _fast("潮汐相位流")
		"子代共鸣":
			for s in em.sources:
				if s.dead:
					continue
				var me: bool = is_same(s, e)
				var aim: float = (g.ppos - s.pos).angle()
				var cnt: int = _cn(4 if me else 3, _dense("子代共鸣"))
				for j in cnt:
					_shot(e, s.pos, aim + (j - (cnt - 1) * 0.5) * 0.2, 150.0, 7.0, 4.5, 0.45, {"izu": "fan"})
			em.next = float(em.next) + 0.5
		"螺旋弹臂":
			var t: float = float(em.next) - float(em.t0)
			for arm in int(em.arms):
				var a: float = a0 + TAU * arm / float(em.arms) + float(em.spin) * t
				_shot(e, e.pos + Vector2.from_angle(a) * 30.0, a, 115.0, 7.0, 4.5, 0.45, {"izu": "spiral"})
			em.next = float(em.next) + 0.2 * _fast("螺旋弹臂")
		"习得弹":
			# 先散开、停住「学习」0.5 秒，再各自转向停住那一刻的你；吸收层数越多弹越多
			var cnt: int = _cn(mini(8 + int(e.get("izu_stacks", 0)), 12))
			var v0: float = 2.0 * (150.0 + 80.0 * n) / 0.9
			for i in cnt:
				var a: float = a0 + (float(i) + 0.5 * n) * TAU / cnt
				_shot(e, e.pos, a, v0, 9.0, 5.0, 0.55, {"izu": "learn", "izu_v0": v0, "izu_ang": a})
			em.next = float(em.next) + 0.6
		"回流弹":
			# 两圈反向卷回的水流，交叉成格子；三幕点亮的灯柱光圈会吞掉它们
			var cnt: int = 16 if _act(e) >= 2 else _cn(12)   # 三幕每圈 16 颗（三幕不加弹：两圈交叉成格子 + 段多，再密就没有可输出的空档）
			for i in cnt:
				var a: float = a0 + (float(i) + 0.5 * n) * TAU / float(cnt)
				_shot(e, e.pos + Vector2.from_angle(a) * 30.0, a, 140.0, 8.0, 5.0, 0.5, {"izu": "back", "izu_curl": 1.5 if n % 2 == 0 else -1.5})
			em.next = float(em.next) + 0.9
		"信息回传":
			# 用户 10-30 选 A：改成朝队长的扇（每个回传点一扇、两轮错开半格），带轻追踪；扇宽 ±0.75 弧度，弹数为原整圈的一半
			for p in em.sources:
				var cn: int = maxi(3, _cn(10, _dense("信息回传")) / 2)
				var aim: float = (g.ppos - p).angle()
				for i in cn:
					var a: float = aim + lerpf(-0.75, 0.75, (float(i) + 0.5 * (n % 2)) / float(cn))
					_shot(e, p, a, 120.0, 7.0, 4.0, 0.45, {"izu": "fan"})
			em.next = float(em.next) + 0.55
		"孢子潮":
			for k in 5:
				var a: float = a0 + (float(k) - 2.0) * 0.55
				_shot(e, e.pos + Vector2.from_angle(a) * 40.0, a, 55.0, 15.0, 3.6, 0.6, {"izu": "spore"})
			em.next = float(em.next) + 1.0
		"习得路径":
			for p in em.trail:
				for j in _cn(3):
					var a: float = TAU * _n01(int(p.x) + j * 7)
					_shot(e, p, a, 0.0, 7.0, 4.0, 0.45, {"izu": "echo"})
			em.next = float(em.next) + 1.0
		"潮门环":
			var act: int = _act(e)
			var cnt: int = _cn(GATE_N[act])
			var slits: int = 2 if act >= 2 else 1
			var ga: float = a0 + float(em.spin) * n
			for i in cnt:
				var a: float = ga + TAU * (float(i) + 0.5) / cnt
				var skip := false
				for sl in slits:
					if absf(angle_difference(ga + TAU * sl / slits, a)) < TAU * GATE_SLOTS[act] * 0.5 / GATE_N[act]:   # 缺口角宽按原弹数算：加弹只让环更密、缺口不变窄
						skip = true
				if not skip:
					_shot(e, e.pos + Vector2.from_angle(a) * 30.0, a, 130.0, 7.0, 4.5, 0.45, {"izu": "gate"})
			em.next = float(em.next) + GATE_GAP[act]


## 每波弹数（协调人转用户 10-29「弹幕数量偏低」，docs/201 §7）：本作改编弹幕的每圈 / 每扇弹数 × boss/izumik_count_k；
## 相位流条数、螺旋臂数、大孢子数与数据招式不乘（加了会把流间 / 臂间通道挤没）；潮门环缺口角宽按原弹数算
func _cn(n: int, extra := 1.0) -> int:
	return maxi(1, int(round(n * Bal.v("boss/izumik_count_k", 1.0) * extra)))


## 招式分工（用户 10-29「攻击频率和弹幕再高一点，分配到不同的招式上」，docs/201 §8）：
## 密度招 = 弹数 × boss/izumik_dense_k（一幕子代共鸣、二幕信息回传；三幕段多、预警久，不加）；
## 快节奏招 = 连发间隔 × boss/izumik_fast_k、持续时间不变（一幕潮汐相位流、二幕螺旋弹臂）；其余（潮门环、习得弹、习得路径、回流弹与预警招）是喘息段，不加
const DENSE := ["子代共鸣", "信息回传"]
const FAST := ["潮汐相位流", "螺旋弹臂"]
func _dense(kind: String) -> float:
	return Bal.v("boss/izumik_dense_k", 1.0) if kind in DENSE else 1.0


func _fast(kind: String) -> float:
	return Bal.v("boss/izumik_fast_k", 1.0) if kind in FAST else 1.0


## 当前幕（0 / 1 / 2）
func _act(e: Dictionary) -> int:
	return clampi(int(e.get("gates_passed", 0)), 0, 2)


## 弹体分级：r 6 细流 / 7–8 中弹 / 9 大弹；暗描边 + 发光核心由 world 的敌弹三遍绘制给出，颜色 = Boss 专属群青
func _shot(e: Dictionary, p: Vector2, a: float, spd: float, r: float, life: float, mult: float, extra: Dictionary) -> void:
	if int(e.get("izu_live", 0)) >= OWN_CAP:
		return
	e.izu_live = int(e.get("izu_live", 0)) + 1
	# 单发伤害旋钮（协调人 10-27：弹幕变密，先 ×0.8，云端测完再定）
	var act: int = _act(e)
	var b := {"pos": p, "vel": Vector2.from_angle(a) * spd, "dmg": e.dmg * mult * Bal.v("boss/izumik_bullet_mult", 1.15), "r": r, "life": life,
		"slow": false, "frost": 0.0, "corrode": 0.0, "nerve": 0.0, "true": false, "kind": ACT_KIND[act], "home": false, "boss": true,
		"atk": "法术", "hit_cap": e.get("hit_cap", 0.0), "source_id": e.id, "col": COL, "own_col": COL, "src_type": e.type, "izu_t": 0.0}
	b.merge(extra, true)
	g.ebullets.append(b)


func _bullet_step(e: Dictionary, dt: float) -> void:
	var lamps: Array = []
	if int(e.get("gates_passed", 0)) >= 2:
		for l in e.get("lamps", []):
			if l.lit and not l.get("out", false):
				lamps.append(l.pos)
	var lr: float = float(e.get("lamp_r", 120.0))
	var target: Vector2 = g.shots.aim_pt()
	var n := 0
	var bursts: Array = []
	var rk: float = Bal.v("boss/izumik_r_k", 1.0)
	for b in g.ebullets:
		if b.life <= 0.0 or int(b.get("source_id", -1)) != int(e.id):
			continue
		n += 1
		var izk: String = str(b.get("izu", ""))
		if (izk == "" or (izk == "spiral" and str(b.get("kind", "")) == "nerve")) and float(b.get("izu_age", 0.0)) < 1.6:
			# 轻追踪（协调人 10-31 选 A，docs/201 §8.4）：数据招式的圆珠 / 快弹与二幕螺旋针，出膛 1.6 秒内每秒最多转 boss/izumik_home_aim 弧度；
			# 潮门环、回流、习得弹 / 习得路径（自带瞄准）不加，缺口与图案不变
			b.izu_age = float(b.get("izu_age", 0.0)) + dt
			var ha: float = Bal.v("boss/izumik_home_aim", 0.0) * dt
			if ha > 0.0:
				b.vel = b.vel.rotated(clampf(angle_difference(b.vel.angle(), (target - b.pos).angle()), -ha, ha))
		if not b.has("izu_rk"):
			# 弹体（画面 = 判定，外缘 100%）放大（10-31 docs/201 §8.3：新判定半径 + 3 下机器人几乎都躲得开）；
			# 在这里统一乘，连携弹（_shot）和数据招式 / finals 出的圆珠、快弹（方案 A 时命中的大头）一起放大，每颗只乘一次
			b.izu_rk = true
			b.r = float(b.r) * rk
		var kind: String = str(b.get("izu", ""))
		if kind != "":
			b.izu_t = float(b.izu_t) + dt
			var t: float = b.izu_t
			match kind:
				"wave":
					b.vel = b.vel.rotated(float(b.izu_amp) * sin(float(b.izu_ph) + 2.4 * t) * dt)
				"learn":
					if t < 0.9:
						b.vel = Vector2.from_angle(float(b.izu_ang)) * float(b.izu_v0) * (1.0 - t / 0.9)
					elif t < 1.4:
						b.vel = Vector2.ZERO
					else:
						if not b.has("izu_aim"):
							b.izu_aim = (target - b.pos).angle()
						b.vel = Vector2.from_angle(float(b.izu_aim)) * minf(150.0, (t - 1.4) * 300.0) * Bal.v("boss/izumik_aim_k", 1.5)   # 瞄准段弹速（docs/201 弹速统一）
				"back":
					if t > 1.1 and t < 2.6:
						b.vel = b.vel.rotated(float(b.izu_curl) * dt)
				"spore":
					b.vel = b.vel.rotated(clampf(angle_difference(b.vel.angle(), (target - b.pos).angle()), -0.6 * dt, 0.6 * dt))
					if b.life <= 0.15:
						b.life = 0.0
						bursts.append(b.pos)
				"fan":
					# 子代共鸣 / 信息回传：轻追踪 boss/izumik_home_rate（每秒 0.4 弧度，用户 10-30 选 A），出膛 1.6 秒后不再转——侧移仍躲得开
					if t < 1.6:
						var hr: float = Bal.v("boss/izumik_home_rate", 0.0) * dt
						b.vel = b.vel.rotated(clampf(angle_difference(b.vel.angle(), (target - b.pos).angle()), -hr, hr))
				"echo":
					if t >= 0.9:
						if not b.has("izu_aim"):
							b.izu_aim = (target - b.pos).angle() + (float(absi(int(b.pos.x)) % 5) - 2.0) * 0.06
						b.vel = Vector2.from_angle(float(b.izu_aim)) * minf(170.0, (t - 0.9) * 340.0) * Bal.v("boss/izumik_aim_k", 1.5)
		for lp in lamps:
			if g.combat.ground_d(b.pos, lp) < lr:
				b.life = 0.0
				_puff(b.pos, 2, Color(1.0, 0.85, 0.5), Vector2.UP)
				break
	e.izu_live = n
	for p in bursts:
		var bn: int = _cn(8, _dense("孢子潮"))
		for k in bn:
			_shot(e, p, TAU * k / float(bn) + 0.2, 125.0, 6.0, 2.4, 0.35, {})
		_puff(p, 6, COL)


## ---- 海流牵引（本作改编，非弹幕）：在你脚下锁一个漩涡，2.6 秒内半径 320 内的海流把你往中心拖（最高 70px/s，低于步行速度，顶着流走得出去），
## 结束时中心 r80 涌起一次（e.dmg × 1.0）。读法：地面向心流线 + 中心暗红圈；冲刺也能直接脱出。破绽 / 眩晕会取消（finals.cancelled）
func _current(e: Dictionary) -> void:
	var p: Vector2 = g.combat.arena_clamp(g.ppos, 110.0)
	g.bai.finals._warn(e, "circle", 2.6, {"name": CURRENT, "pos": p, "r": 80.0, "skin": "current", "pull_r": 320.0,
		"dmg": e.dmg * Bal.v("boss/izumik_current_mult", 1.0)})
	Sfx.play("tentacle", -6.0, 0.6)


func _current_step(e: Dictionary, dt: float) -> void:
	if g.invuln > 0.0 and float(g.get("dash_t")) > 0.0:
		return   # 冲刺中不拖
	for w in g.warns:
		if w.done or not is_same(w.owner, e) or str(w.get("skin", "")) != "current" or g.bai.finals.cancelled(w):
			continue
		var to: Vector2 = w.pos - g.ppos
		var d: float = g.combat.ground_d(g.ppos, w.pos)
		if d > float(w.pull_r) or d < 6.0:
			continue
		var k: float = clampf(float(w.t) / 0.6, 0.0, 1.0) * (1.0 - 0.5 * d / float(w.pull_r))
		g.ppos = g.map.push_out(g.ppos + to.normalized() * 70.0 * k * dt, 12.0)


## 分享（扇形）结算画面：通用 sweep 只有一道细刀光，这里补喷涌——扇形里的水流喷射 + 孢子雾 + 扇缘浪沫（render/izumik_attack_draw.share），纯画面
func _share_fx_step(e: Dictionary) -> void:
	for w in g.warns:
		if w.done and not w.get("izu_mire", false) and is_same(w.owner, e) and str(w.get("skin", "")) in ["current", "tentacle"]:
			w.izu_mire = true
			if not g.bai.finals.cancelled(w):
				_tide_mires(e, w)
				if str(w.skin) == "current":
					# 收尾浪甩出的水沫颗粒（docs/136 颗粒模板，纯画面）
					for q in 24:
						var d := Vector2.from_angle(TAU * q / 24.0)
						_puff(w.pos + Vector2(d.x, d.y * 0.72) * float(w.r), 1, Color(0.7, 0.88, 1.0), (d + Vector2.UP).normalized())
					g.vfx.shake_screen(0.25)
		if not w.done or w.get("izu_fx", false) or not is_same(w.owner, e) or str(w.get("act", "")) != "sweep":
			continue
		w.izu_fx = true
		g.fx.append({"kind": "izu_share", "pos": w.pos, "ang": float(w.ang), "half": float(w.half), "r": float(w.r), "life": 0.7, "max": 0.7, "enemy": true})
		for k in 18:
			var a: float = float(w.ang) + lerpf(-float(w.half), float(w.half), (k + 0.5) / 18.0)
			_puff(w.pos + Vector2.from_angle(a) * float(w.r) * 0.85, 1, Color(0.62, 0.82, 1.0), Vector2.from_angle(a))


## ---- 持续压迫与输出窗口（协调人 10-27，测试台 docs/170_boss_bench：单场 54 秒、队长从没危险过）
## 潮痕（场地侵蚀）：海流牵引的涌起点、护群触腕最后一圈留下 Boss 溟痕（减速 + 每秒 2% 最大生命，走 Boss 持续伤害上限），
## 存在 boss/izumik_mire_life（8）秒；一次最多 boss/izumik_mire_max（6）块伊祖米克溟痕。被破绽 / 眩晕取消的招不留
func _tide_mires(e: Dictionary, w: Dictionary) -> void:
	var life: float = Bal.v("boss/izumik_mire_life", 10.0)
	if life <= 0.0:
		return
	var pts: Array = []
	if str(w.skin) == "current":
		pts.append(w.pos)
	elif w.get("izu_last", false):
		pts.append(w.pos)
	var cap: int = int(Bal.v("boss/izumik_mire_max", 6.0))
	for p in pts:
		if g.mires.filter(func(m): return m.get("izu", false) and m.life > 0.0).size() >= cap:
			return
		g.mires.append({"pos": g.combat.arena_clamp(p, 60.0), "r": 10.0, "maxr": Bal.v("boss/izumik_mire_r", 90.0), "life": life,
			"seed": g.vrng.randf() * 100.0, "boss": true, "izu": true})


## 受伤倍率（combat 经 boss 脚本询问）：阐释阶段连携期间受伤 × boss/izumik_taken_out（0.7），破绽期 × boss/izumik_break_taken（1.1，再乘通用破绽 1.4）——
## 把输出往收招破绽里挤（测试台破绽输出 8% → 目标 ≥ 35%）；连携关掉时不变
func taken_mult(e: Dictionary) -> float:
	if e.phase != 2 or Bal.v("boss/izumik_cards", 1.0) <= 0.0:
		return 1.0
	return Bal.v("boss/izumik_break_taken", 1.4) if float(e.get("break_t", 0.0)) > 0.0 else Bal.v("boss/izumik_taken_out", 0.47)


## ---- 护群触腕（用户 10-28：换圆形、追着人打）：在队长脚下连落 boss/izumik_tentacle_n（4）个圆（半径 izumik_tentacle_r 110），
## 每隔 izumik_tentacle_gap（0.6）秒按队长当时的位置落下一个，每个预警 1.1 秒后触手从圆里钻出（e.dmg × 1.1）；一直走动就躲得开
func _tentacles(e: Dictionary) -> void:
	e.izu_tent_n = int(Bal.v("boss/izumik_tentacle_n", 4.0))
	e.izu_tent_next = g.t
	Sfx.play("tentacle", -4.0, 0.8)
	_tentacle_step(e)   # 第一个圈当帧落下


func _tentacle_step(e: Dictionary) -> void:
	var n: int = int(e.get("izu_tent_n", 0))
	if n <= 0:
		return
	if float(e.get("break_t", 0.0)) > 0.0 or float(e.stun) > 0.0:
		e.izu_tent_n = 0
		return
	if g.t < float(e.izu_tent_next):
		return
	e.izu_tent_n = n - 1
	e.izu_tent_next = g.t + Bal.v("boss/izumik_tentacle_gap", 0.6)
	g.bai.finals._warn(e, "circle", 1.1, {"name": TENTACLE if n == int(Bal.v("boss/izumik_tentacle_n", 4.0)) else "",
		"pos": g.combat.arena_clamp(g.ppos, 60.0), "r": Bal.v("boss/izumik_tentacle_r", 110.0), "skin": "tentacle",
		"dmg": e.dmg * 1.1, "izu_last": n == 1})


## 习得路径：每 0.25 秒记一次队长位置，留最近 10 个（2.5 秒）
func _trail_step(e: Dictionary) -> void:
	if g.t < float(e.get("izu_trail_t", 0.0)):
		return
	e.izu_trail_t = g.t + 0.25
	var tr: Array = e.get("izu_trail", [])
	tr.append(g.ppos)
	if tr.size() > 10:
		tr.pop_front()
	e.izu_trail = tr


static func _n01(i: int) -> float:
	var k: int = (i * 73471 + 137) & 65535
	k = ((k ^ (k >> 7)) * 127) & 65535
	return float(k) / 65535.0


## 每幕行为（docs/170 §18）：阐释阶段不走通用远程 AI（e.spd = 0，也就不放通用普通弹），位置由这里定——
## 一幕扎根不动；二幕每组连携换一个落点（场地中心 320 内）缓慢漂过去；三幕缓缓逼近队长，贴到 200 内停；出招预警（wind）期间都不动
func _move_step(e: Dictionary, dt: float) -> void:
	e.spd = 0.0
	var act: int = _act(e)
	var v: float = ACT_MOVE[act]
	if v <= 0.0 or float(e.get("wind", 0.0)) > 0.0 or float(e.get("break_t", 0.0)) > 0.0 or float(e.stun) > 0.0:
		return
	var c: Vector2 = g.zone_c if g.zone_state != 0 else Vector2.ZERO
	var goal: Vector2
	if act == 1:
		if int(e.get("izu_wander_n", -1)) != int(e.get("izu_card_n", 0)):
			e.izu_wander_n = int(e.get("izu_card_n", 0))
			e.izu_wander = c + Vector2.from_angle(g.rng_enemy.randf() * TAU) * g.rng_enemy.randf_range(120.0, 320.0)
		goal = e.izu_wander
	else:
		if g.combat.ground_d(e.pos, g.ppos) < 200.0:
			return
		goal = g.ppos
	e.pos = g.combat.arena_clamp(e.pos.move_toward(goal, v * dt), 80.0)


## ---- 子代化生（三幕独有，取材 PRTS 伊祖米克的子代：「被阻挡时立即变为随机敌人」）：她从身边放出 boss/izumik_brood_n（4）只子代直扑队长（每秒 60）；
## 子代碰到队长 = 被阻挡，就地蜕变成两只海嗣（enemies.gd morph）。读法：在它们碰到你之前打掉（子代 70 血），或绕开；不放子代自己的孢子环 / 横扫
func _brood(e: Dictionary) -> void:
	var n: int = int(Bal.v("boss/izumik_brood_n", 4.0))
	var a0: float = (g.ppos - e.pos).angle()
	var live: Array = e.get("izu_brood", []).filter(func(o): return not o.dead)
	for k in n:
		var a: float = a0 + (float(k) - (n - 1) * 0.5) * 0.6
		var o: Dictionary = g.spawner.spawn_enemy("offspring", g.combat.arena_clamp(e.pos + Vector2.from_angle(a) * (e.r + 30.0), 60.0))
		o.spd = Bal.v("boss/izumik_brood_spd", 60.0)
		o.extra_next = INF
		o.nova_cd = INF
		live.append(o)
		g.fx.append({"kind": "ring", "pos": o.pos, "r": 30.0, "life": 0.5, "max": 0.5, "col": COL, "enemy": true})
	e.izu_brood = live
	g.vfx.add_text(e.pos + Vector2(0, -60), "子代化生", COL, 16)
	Sfx.play("tentacle", -4.0, 0.7)
