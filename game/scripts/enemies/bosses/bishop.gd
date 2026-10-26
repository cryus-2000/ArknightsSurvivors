## 接潮主教（type bishop，docs/38 §2.3；招式改版 docs/95 §8，10-14 第 3 批）
## Boss 行为脚本（docs/55 §6 拆分，10-10）：状态仍在敌人字典 e 上，预警 / 冷却 / 迫近经基类转给 boss_ai.gd。本文件只有这只 Boss 自己的招式与阶段逻辑。
## 4 招：A 潮汐柱（① 直线上等距三圈）/ B 交错潮环（④，patterns）/ C 统一（② 两体之间的直线，boss_ai 公共段 + unite）/ D 接潮扇浪（③，第二幕，patterns manual）
## 机制不占名额：召潮、祝福、慌乱、假死赛跑
## 主轴「同步」（docs/142b §3.8 / §8.2，10-25）：血量差护盾（boss_base._pair_shield）、一幕两具推开 ≥360；
##   二幕「统一」（关卡名）：每 pair_swap_cd（10）秒「换位」——两体连线 + 各自连向主控的两条线（统一三角）同时结算，结算那一刻两具互换位置；取代原第二幕靠拢
extends "res://scripts/enemies/bosses/boss_base.gd"

const MOVES := ["潮汐柱", "交错潮环", "统一", "接潮扇浪"]
const TINT2 := Color(0.86, 1.1, 1.16)   # 第二幕常驻青色（docs/95 §8.2）


## 每帧（boss_ai._boss_ai 公共段之后）：ready = 本帧可以出招；mate = 接潮搭档（没有则 null）
func step(e: Dictionary, dt: float, dir: Vector2, dist: float, ready: bool, mate) -> void:
	# 慌乱（协调人 9/30 定 C，boss/bishop_panic，0 = 关）：搭档假死时停召潮、加速朝搭档靠拢，假死赛跑的 8 秒里能打到它
	# （原来它远程 300 站在自己召的杂兵后面，Ⅷ on_boss 0%）
	var panic: bool = Bal.v("boss/bishop_panic", 1.0) > 0.0 and mate != null and not mate.dead and mate.get("coma", false)
	var p2: bool = _pair_p2(e)
	if p2:
		_tint2(e, TINT2)
	_pair_spread(e, dt)
	# 第二幕换位 + 统一三角（取代原来的两体靠拢）
	if p2 and mate != null and not mate.dead and not panic and not mate.get("coma", false) and not e.get("coma", false):
		e.link_next_at = INF   # 二幕的「统一」由换位取代（boss_ai 公共段不再单放）
		if g.t >= float(e.get("swap_next", 0.0)) and e.get("wind", 0.0) <= 0.0 and e.stun <= 0.0 and float(e.get("break_t", 0.0)) <= 0.0:
			e.swap_next = g.t + Bal.v("boss/pair_swap_cd", 10.0)
			_swap(e, mate)
	elif float(e.get("link_next_at", 0.0)) == INF:
		e.link_next_at = g.t + 2.0   # 搭档假死 / 本体假死时恢复公共段的「统一」（假死赛跑那条连线）
	if panic:
		if not e.get("panic", false):
			e.panic_n = int(e.get("panic_n", 0)) + 1   # 遥测 panic_n
			g.vfx.add_text(e.pos + Vector2(0, -50), "慌乱", Color(1.0, 0.45, 0.8), 16)
			Sfx.play("bishop_panic", -4.8, 1.0, 0.0)   # 慌乱：结巴的吸气颤音
		e.ai = "melee"
		e.aggro = mate.pos
		e.haste = maxf(float(e.get("haste", 0.0)), 0.1)
	elif e.ai == "melee":
		e.ai = "ranged"
	e.panic = panic
	if not ready:
		return
	var p = e.get("partner")
	# D 接潮扇浪：第二幕、主控 <260、wave 8 秒；第一次先亮招式名 0.6 秒（§0.2）
	if p2 and dist < 260.0 and float(e.get("cds", {}).get("wave", 0.0)) <= g.t:
		if _first_tell(e, "wave", "接潮扇浪") and _cd(e, "wave", 8.0):
			_wave(e, dir, dist)
	elif _cd(e, "pillar", 7.0):
		_pillar(e, dir)
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


## 图鉴 / Boss 演练：直接进入第二幕
func setup_preview_phase2(e: Dictionary) -> void:
	e.gates_passed = maxi(1, int(e.get("gates_passed", 0)))
	_tint2(e, TINT2)


func demo_moves(_e: Dictionary) -> Array:
	return MOVES


func force_move(e: Dictionary, name: String, dir: Vector2, dist: float) -> bool:
	match name:
		"潮汐柱":
			_pillar(e, dir)
			return true
		"交错潮环":
			e.pattern_force = name
			return g.bai.patterns.try_attack(e, dir, dist)
		"统一":
			var m = e.get("partner")
			if m == null or m.dead:
				return false
			g.bai.unite(e, m)
			return true
		"接潮扇浪":
			if not _pair_p2(e):
				return false
			_wave(e, dir, dist)
			return true
	return false


## A · 潮汐柱（保留微调）：3 圈 r64 改为一条直线上等距三点——主控脚下 + 沿「主教 → 主控」方向前后各 110，同时锁定 1.1 秒；
## 侧向一步就全躲开（原来两个随机偏移圈读不出规律）；e.dmg × 1.1 法术 / 柱
func _pillar(e: Dictionary, dir: Vector2) -> void:
	for k in 3:
		var off: Vector2 = dir * (0.0 if k == 0 else (110.0 if k == 1 else -110.0))
		_warn(e, "circle", 1.1, {"pos": g.ppos + off, "r": 64.0, "act": "pillar", "name": "潮汐柱" if k == 0 else "", "col": Color(0.4, 0.9, 1.0), "dmg": e.dmg * 1.1, "lock": k == 0})


## 二幕「换位」（docs/142b §3.8）：两体连线（双端跟随 0.6 秒后锁定，Kanpelle 靛蓝光束）+ 各自连向主控的两条线，1.0 秒同时结算；
## 连线结算那一刻两具互换位置（telegraph tide_link 的 swap）。读法：别站两体之间、也别站在任一体与自己的连线上，往三角外斜走，换完重新选边
func _swap(e: Dictionary, mate: Dictionary) -> void:
	_warn(e, "line", 1.0, {"ang": (mate.pos - e.pos).angle(), "len": e.pos.distance_to(mate.pos), "wid": 17.0, "track": 0.6, "act": "tide_link", "name": "换位",
		"col": g.vfx.boss_color(e.type), "dmg": e.dmg * 0.47, "cancel_dead": true, "b_owner": mate, "lock": false, "swap": true, "kp": "bishop", "kp_k": 1.0})
	# 各自连向主控的线 + 穿过主控、与两体连线平行的第 4 道（10-25 加密：原三角 3 道；×0.78）
	for src in [e, mate]:
		var v: Vector2 = g.ppos - src.pos
		_warn(e, "line", 1.0, {"pos": src.pos, "source": src, "aim_extend": true, "ang": v.angle(), "len": v.length() + 40.0, "wid": 14.0, "track": 0.4, "act": "shot", "name": "",
			"col": g.vfx.boss_color(src.type), "dmg": e.dmg * 0.39, "lock": false, "kp": "bishop", "kp_k": 1.0})
	var pa: float = (mate.pos - e.pos).angle()
	_warn(e, "line", 1.15, {"pos": g.ppos - Vector2.from_angle(pa) * 420.0, "ang": pa, "len": 840.0, "wid": 14.0, "track": 0.5, "track_center": true, "act": "shot", "name": "",
		"col": g.vfx.boss_color(e.type), "dmg": e.dmg * 0.39, "lock": false, "kp": "bishop", "kp_k": 1.0})
	g.vfx.add_text(e.pos + Vector2(0, -50), "统一", Color(0.4, 0.9, 1.0), 16)


## D · 接潮扇浪（第二幕）：enemies.json patterns「接潮扇浪」（manual）——扇形 r260 半角 0.9，追踪 0.3 总 1.4；扇形本身一次 e.dmg × 0.9 + 7 发浪弹 320px/s
func _wave(e: Dictionary, dir: Vector2, dist: float) -> void:
	e.pattern_force = "接潮扇浪"
	g.bai.patterns.try_attack(e, dir, dist)


## 同步护盾（docs/142b §3.8）：血量比搭档低出门槛时受伤 × 0.4
func taken_mult(e: Dictionary) -> float:
	return _pair_shield(e)
