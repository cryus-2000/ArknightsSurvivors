## 塑路者（type path，docs/38 §2.1；招式改版 docs/95 §5，10-14 第 2 批）
## Boss 行为脚本（docs/55 §6 拆分，10-10）：状态仍在敌人字典 e 上，预警 / 冷却 / 迫近经基类转给 boss_ai.gd。本文件只有这只 Boss 自己的招式与阶段逻辑。
## 4 招：A 冲撞（② 直线）/ B 震地（① 落点圈）/ C 分形塑路（③ 扇形，原作技能名；劈完长出 1 只分形）/ D 订正（④ 缺口环，50% 卡点后，patterns 数据）
## 机制不占名额：碎裂 75 / 50 / 25%、猎核、碎片回流（回流的同一刻必放一次订正）
extends "res://scripts/enemies/bosses/boss_base.gd"

const MOVES := ["冲撞", "震地", "分形塑路", "订正"]
const TINT2 := Color(0.86, 0.95, 1.16)   # 第二幕常驻钢蓝亮边（docs/95 §5.2）


## 每帧（boss_ai._boss_ai 公共段之后）：ready = 本帧可以出招；mate = 接潮搭档（没有则 null）
func step(e: Dictionary, _dt: float, dir: Vector2, dist: float, ready: bool, _mate) -> void:
	_expire_shaped(e)
	var p2: bool = int(e.get("gates_passed", 0)) >= 1
	if p2:
		_tint2(e, TINT2)
	if ready:
		if dist < 170.0 and _cd(e, "slam", 9.0):
			_slam(e)
		elif e.get("dash_left", 0) > 0 and e.get("dash_t", 0.0) <= 0.0:
			# 第二幕冲撞连段（docs/38 §8.1）：上一段冲完立刻接下一段，每段仍有完整预警
			e.dash_left -= 1
			_warn(e, "line", 0.8, {"ang": dir.angle(), "len": 440.0, "wid": 30.0, "track": 0.35, "act": "dash", "fit_len": true, "name": "", "col": Color(1.0, 0.35, 0.3)})
		elif p2 and dist < 600.0 and float(e.get("cds", {}).get("correct", 0.0)) <= g.t:
			# D 订正：第二幕 correct 10 秒；第一次先亮招式名 0.6 秒（§0.2）
			if _first_tell(e, "correct", "订正") and _cd(e, "correct", 10.0):
				_correct(e, dir, dist)
		elif dist < 260.0 and _cd(e, "shape", 5.0 if p2 else 8.0):
			_shape(e, dir)
		elif dist > 150.0 and _cd(e, "dash", 6.0):
			_dash(e, dir)
	var crack: int = e.get("crack", 0)
	if crack < 3 and e.hp < e.maxhp * (0.75 - 0.25 * crack):
		e.crack = crack + 1
		for k in 4:
			var fr: Dictionary = g.spawner.spawn_enemy("fractal", g.combat.arena_clamp(e.pos + Vector2.from_angle(TAU * k / 4.0 + 0.4) * 56.0))
			fr.owner = e
		g.fx.append({"kind": "ring", "pos": e.pos, "r": e.r * 2.2, "life": 0.35, "max": 0.35, "col": Color(0.6, 0.7, 1.0)})
		g.vfx.add_text(e.pos + Vector2(0, -60), "碎裂", Color(0.6, 0.7, 1.0), 18)
		Sfx.play("boom", -6.0, 1.3, 0.0)
	if p2:
		_path_core(e)


## 图鉴 / Boss 演练：直接进入第二幕（猎核、冲撞 2 连、订正）
func setup_preview_phase2(e: Dictionary) -> void:
	e.gates_passed = maxi(1, int(e.get("gates_passed", 0)))
	_tint2(e, TINT2)


func demo_moves(_e: Dictionary) -> Array:
	return MOVES


func force_move(e: Dictionary, name: String, dir: Vector2, dist: float) -> bool:
	match name:
		"冲撞":
			_dash(e, dir)
			return true
		"震地":
			_slam(e)
			return true
		"分形塑路":
			_shape(e, dir)
			return true
		"订正":
			if int(e.get("gates_passed", 0)) < 1:
				return false
			e.pattern_force = "订正"
			return g.bai.patterns.try_attack(e, dir, dist)
	return false


## A · 冲撞（保留）：440 × 30 条纹线，fit_len 真冲到位，追踪 0.45 秒后锁定，总 0.9 秒；第二幕 2 连 + 回流加段
func _dash(e: Dictionary, dir: Vector2) -> void:
	_warn(e, "line", 0.9, {"ang": dir.angle(), "len": 440.0, "wid": 30.0, "track": 0.45, "act": "dash", "fit_len": true, "name": "冲撞", "col": Color(1.0, 0.35, 0.3)})
	if e.get("gates_passed", 0) >= 1:
		e.dash_left = int(Bal.v("boss/path_dash_chain", 1.0)) + int(e.get("dash_bonus", 0))   # 第二幕常驻 2 连，核心没打碎再加
		e.dash_bonus = 0


## B · 震地（保留微调）：主控当前位置 r90 固定落点（docs/48 P0-4），预警 1.0 → 1.1 秒（锁定 ≥（90 + 12）÷ 105 + 0.1 ≈ 1.07）；
## e.dmg × 1.3，冲击环命中在 Boss 战里换成 0.5 秒减速（不僵直，enemies.gd 冲击环 + stun_as_slow）
func _slam(e: Dictionary) -> void:
	_warn(e, "circle", 1.1, {"pos": g.ppos, "r": 90.0, "act": "slam", "name": "震地", "col": Color(1.0, 0.55, 0.3), "dmg": e.dmg * 1.3})


## C · 分形塑路（标志性，原作技能名；PRTS「攻击 100% 物理 + 分形不足 8 时召 1 只」）：扇形 r220 半角 0.9，追踪 0.3 秒、总 1.1 秒；
## e.dmg × 1.1；不管命没命中，劈痕处（轴线 r140）长出 1 只分形（本体所属 <8，20 秒自灭，boss_ai._spawn_after）。猎核幕里新长的也能当核心候选
func _shape(e: Dictionary, dir: Vector2) -> void:
	_warn(e, "cone", 1.1, {"ang": dir.angle(), "half": 0.9, "r": 220.0, "track": 0.3, "act": "sweep", "name": "分形塑路", "col": g.vfx.boss_color(e.type),
		"dmg": e.dmg * 1.1, "spawn_after": "fractal", "spawn_r": 140.0, "spawn_cap": 8, "spawn_life": 20.0, "cone_fx": "fx_slash_heavy_steel"})


## D · 订正（二阶段，本作原创，取材紧急关卡「订正」）：enemies.json patterns「订正」（manual：只由这里和回流点名）——
## 本体为心 r90 空心环、缺口朝主控，总 1.0 秒；结算 12 片碎片形刃弹 380px/s、寿命 2.2 秒，e.dmg × 0.8
func _correct(e: Dictionary, dir: Vector2, dist: float) -> void:
	e.pattern_force = "订正"
	g.bai.patterns.try_attack(e, dir, dist)


## 分形塑路长出来的分形 20 秒自灭（docs/38 §2.1；碎裂 / 猎核吐出的照旧不限时）
func _expire_shaped(e: Dictionary) -> void:
	var lst: Array = e.get("spawned_after", [])
	if lst.is_empty():
		return
	var keep: Array = []
	for o in lst:
		if o.dead:
			continue
		if g.t >= float(o.get("expire_at", INF)) and not o.get("core", false):
			o.dead = true
			g.vfx.sparks(o.pos, Vector2.ZERO, Color(0.6, 0.7, 1.0), 6, 140.0)
			continue
		keep.append(o)
	e.spawned_after = keep


## 塑路者「猎核」（docs/38 §8.1，50% 卡点之后）：场上最老的一块碎片发光成为核心部件（不动、固定血量），编队优先打它；
## 主控得带队走过去。打碎：其余碎片崩解、Boss 破绽 boss/path_core_break 秒；boss/path_core_time 秒没打碎：碎片冲回本体，
## 下一次冲撞多连几段（最多 3），并且同一刻放一次「订正」（docs/95 §5.2 D：把失败惩罚画出来）。不回血。boss/path_core_gap 秒后出新核心
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
					# 碎片回流（world.gd 画；Codex fx_path_reflow 到了再换拖尾）
					g.fx.append({"kind": "reflow", "a": o.pos, "b": e.pos, "life": 0.7, "max": 0.7, "enemy": true})
					o.dead = true
			e.dash_bonus = mini(3, n)
			g.vfx.add_text(e.pos + Vector2(0, -70), "碎片回流 —— 冲撞 +%d 段" % e.dash_bonus, Color(1.0, 0.45, 0.35), 18)
			e.pattern_force = "订正"   # 回流 → 订正：下一次能出招时必放（boss_patterns 点名，不看冷却）
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
		var fr: Dictionary = g.spawner.spawn_enemy("fractal", g.combat.arena_clamp(e.pos + Vector2.from_angle(g.rng_enemy.randf() * TAU) * g.rng_enemy.randf_range(120.0, 200.0)))
		fr.owner = e
		owned.append(fr)
	var oldest: Dictionary = owned[0]
	for o in owned:
		if o.age > oldest.age:
			oldest = o
	oldest.part = true
	g.enemies_sys.part_add(oldest)   # 部件登记（docs/101 S7）
	oldest.core = true
	oldest.erase("expire_at")   # 当上核心就不再自灭（倒计时看 core_until）
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
