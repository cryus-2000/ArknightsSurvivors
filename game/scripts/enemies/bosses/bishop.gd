## 接潮主教（type bishop，docs/38 §2.3；招式改版 docs/95 §8，10-14 第 3 批）
## Boss 行为脚本（docs/55 §6 拆分，10-10）：状态仍在敌人字典 e 上，预警 / 冷却 / 迫近经基类转给 boss_ai.gd。本文件只有这只 Boss 自己的招式与阶段逻辑。
## 4 招：A 潮汐柱（① 直线上等距三圈）/ B 交错潮环（④，patterns）/ C 统一（② 两体之间的直线，boss_ai 公共段 + unite）/ D 接潮扇浪（③，第二幕，patterns manual）
## 机制不占名额：召潮、祝福、慌乱、假死赛跑
## 主轴「同步」（docs/142b §3.8 / §8.2，10-25）：血量差护盾（boss_base._pair_shield）、一幕两具推开 ≥360；
##   二幕「统一」（关卡名）：每 pair_swap_cd（10）秒「换位」——两体连线 + 各自连向主控的两条线（统一三角）同时结算，结算那一刻两具互换位置；取代原第二幕靠拢
## 弹幕（docs/170，本作改编，10-27）：两具各从自己身上出弹、互为镜像（关于两体中垂线）；每幕两套图案逐拍交替，幕沿用现有卡点（任一具过 50%）。
##   一幕：镜潮（一具朝你放 5 向扇，0.6 秒后另一具放镜像，领头逐拍交替）/ 交错潮环（两具同放 16 向环，一具左弯、一具右弯，交出菱形格）
##   二幕：换位潮墙（两体连线上隔点显形一排弹，向两侧镜像推开；换位照旧）/ 双螺潮（两具各放两臂螺旋，转向相反，放 1.6 秒停 0.9 秒）
## 配合连段（≤4 段，结束两具一起破绽）：一幕 潮汐柱 → 搭档跃击 / 连斩 → 镜潮齐射；二幕 搭档横扫 / 连斩 → 潮汐柱 → 搭档吐息 / 迸发
extends "res://scripts/enemies/bosses/boss_base.gd"

const MC = preload("res://scripts/enemies/mid_cards.gd")

const MOVES := ["潮汐柱", "交错潮环", "统一", "接潮扇浪", "镜潮", "换位潮墙", "双螺潮"]
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
	var live: bool = mate != null and not mate.dead and not mate.get("coma", false) and not e.get("coma", false)
	_act_check(e, p2)
	MC.step_shots(g, e, dt)
	if mate != null and not mate.dead:
		MC.step_shots(g, mate, dt)
	_mirror_step(e, mate)
	if live and not panic:
		_pat_beat(e, mate)
	if MC.q_step(g, e, Callable(self, "_exec").bind(mate), p2):
		return
	if not ready:
		return
	var p = e.get("partner")
	# 配合连段（docs/170）：取代原来单放的潮汐柱 / 接潮扇浪
	if live and not panic and _cd(e, "pair_combo", 8.0 if p2 else 9.0):
		var m2: String = "跃击" if mate.type == "archon" else "连斩"
		if p2:
			MC.q_start(g, e, [{"actor": mate, "move": "横扫" if mate.type == "archon" else "连斩"}, {"actor": e, "move": "潮汐柱"},
				{"actor": mate, "move": "蚀潮吐息" if mate.type == "archon" else "迸发"}], 1.8, [mate])
		else:
			MC.q_start(g, e, [{"actor": e, "move": "潮汐柱"}, {"actor": mate, "move": m2}, {"actor": e, "move": "镜潮"}], 1.4, [mate])
	elif not live and _cd(e, "pillar", 7.0):
		_pillar(e, dir)
	elif not live and not panic and _cd(e, "solo_ring", 8.0):
		# 搭档不在（倒下 / 假死赛跑之外的单体情形）：没有镜像，退回原来的交错潮环
		e.pattern_force = "交错潮环"
		g.bai.patterns.try_attack(e, dir, dist)
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
		"镜潮", "换位潮墙", "双螺潮":
			var m = e.get("partner")
			if m == null or m.dead:
				return false
			match name:
				"镜潮":
					_mirror_fan(e, m, dir)
				"换位潮墙":
					_link_wall(e, m)
				"双螺潮":
					e.spiral_t0 = g.t
					e.spiral_until = g.t + 1.6
			return true
	return false


## A · 潮汐柱（保留微调）：3 圈 r64 改为一条直线上等距三点——主控脚下 + 沿「主教 → 主控」方向前后各 110，同时锁定 1.1 秒；
## 侧向一步就全躲开（原来两个随机偏移圈读不出规律）；e.dmg × 1.1 法术 / 柱
func _pillar(e: Dictionary, dir: Vector2) -> void:
	for k in 3:
		var off: Vector2 = dir * (0.0 if k == 0 else (110.0 if k == 1 else -110.0))
		_warn(e, "circle", 1.1, {"pos": g.ppos + off, "r": 64.0, "act": "pillar", "name": "潮汐柱" if k == 0 else "", "col": Color(0.4, 0.9, 1.0), "dmg": e.dmg * 1.1, "lock": k == 0, "skin": "mc_pillar"})


## 二幕「换位」（docs/142b §3.8）：两体连线（双端跟随 0.6 秒后锁定，Kanpelle 靛蓝光束）+ 各自连向主控的两条线，1.0 秒同时结算；
## 连线结算那一刻两具互换位置（telegraph tide_link 的 swap）。读法：别站两体之间、也别站在任一体与自己的连线上，往三角外斜走，换完重新选边
func _swap(e: Dictionary, mate: Dictionary) -> void:
	_warn(e, "line", 1.0, {"ang": (mate.pos - e.pos).angle(), "len": e.pos.distance_to(mate.pos), "wid": 17.0, "track": 0.6, "act": "tide_link", "name": "换位",
		"col": g.vfx.boss_color(e.type), "dmg": e.dmg * 0.47, "cancel_dead": true, "b_owner": mate, "lock": false, "swap": true, "kp": "bishop", "kp_k": 1.0, "skin": "mc_link"})
	# 各自连向主控的线 + 穿过主控、与两体连线平行的第 4 道（10-25 加密：原三角 3 道；×0.78）
	for src in [e, mate]:
		var v: Vector2 = g.ppos - src.pos
		_warn(e, "line", 1.0, {"pos": src.pos, "source": src, "aim_extend": true, "ang": v.angle(), "len": v.length() + 40.0, "wid": 14.0, "track": 0.4, "act": "shot", "name": "",
			"col": g.vfx.boss_color(src.type), "dmg": e.dmg * 0.39, "lock": false, "kp": "bishop", "kp_k": 1.0, "skin": "mc_link"})
	var pa: float = (mate.pos - e.pos).angle()
	_warn(e, "line", 1.15, {"pos": g.ppos - Vector2.from_angle(pa) * 420.0, "ang": pa, "len": 840.0, "wid": 14.0, "track": 0.5, "track_center": true, "act": "shot", "name": "",
		"col": g.vfx.boss_color(e.type), "dmg": e.dmg * 0.39, "lock": false, "kp": "bishop", "kp_k": 1.0, "skin": "mc_link"})
	g.vfx.add_text(e.pos + Vector2(0, -50), "统一", Color(0.4, 0.9, 1.0), 16)


## D · 接潮扇浪（第二幕）：enemies.json patterns「接潮扇浪」（manual）——扇形 r260 半角 0.9，追踪 0.3 总 1.4；扇形本身一次 e.dmg × 0.9 + 7 发浪弹 320px/s
func _wave(e: Dictionary, dir: Vector2, dist: float) -> void:
	e.pattern_force = "接潮扇浪"
	g.bai.patterns.try_attack(e, dir, dist)


## 同步护盾（docs/142b §3.8）：血量比搭档低出门槛时受伤 × 0.4
func taken_mult(e: Dictionary) -> float:
	return _pair_shield(e)


## ---- 弹幕节拍（docs/170）
## 幕沿用现有卡点（_pair_p2）；进新幕时从 A 图案重新数拍，第一拍晚 1.6 秒
func _act_check(e: Dictionary, p2: bool) -> void:
	var act: int = 1 if p2 else 0
	if int(e.get("pat_act", -1)) != act:
		e.pat_act = act
		e.beat_n = 0
		e.pat_beat = g.t + (1.5 if act == 0 else 1.6)
		e.spiral_until = -1.0


## 连段一段：主教自己的招在这里，搭档的招转给搭档脚本 pair_move（返回占用秒数，放不出 -1）
func _exec(actor: Dictionary, move: String, mate) -> float:
	var dir: Vector2 = (g.ppos - actor.pos).normalized() if g.ppos.distance_to(actor.pos) > 1.0 else Vector2.RIGHT
	if actor.type == "bishop":
		match move:
			"潮汐柱":
				_pillar(actor, dir)
				return 1.1
			"镜潮":
				if mate == null or mate.dead:
					return -1.0
				_mirror_fan(actor, mate, dir)
				return 1.0
		return -1.0
	var h = g.bai.boss(actor.type)
	return h.pair_move(actor, move, dir) if h != null and h.has_method("pair_move") else -1.0


## 节拍（不占招式令牌，是这一幕的底色）；任一具破绽 / 眩晕时停。一幕：镜潮 / 交错潮环；二幕：换位潮墙 / 双螺潮
func _pat_beat(e: Dictionary, mate: Dictionary) -> void:
	for o in [e, mate]:
		if o.stun > 0.0 or float(o.get("break_t", 0.0)) > 0.0:
			return
	_spiral(e, mate)
	if g.t < float(e.get("pat_beat", INF)) or e.age < 2.0:
		return
	var n: int = int(e.get("beat_n", 0))
	var i: int = int(e.pat_act) * 2 + n % 2
	e.beat_n = n + 1
	match i:
		0:
			e.pat_beat = g.t + Bal.v("boss/tide_pat_mirror_cd", 2.6)
			var lead: Dictionary = e if int(n / 2.0) % 2 == 0 else mate
			var other: Dictionary = mate if is_same(lead, e) else e
			_mirror_fan(lead, other, (g.ppos - lead.pos).normalized())
		1:
			e.pat_beat = g.t + Bal.v("boss/tide_pat_ring_cd", 3.0)
			_twin_rings(e, mate)
		2:
			e.pat_beat = g.t + Bal.v("boss/tide_pat_wall_cd", 3.2)
			_link_wall(e, mate)
		3:
			e.pat_beat = g.t + 2.5
			e.spiral_t0 = g.t
			e.spiral_until = g.t + 1.6


## 镜潮（一幕 A）：lead 朝队长放 5 向扇（出弹点离本体中心 28，两具一致才镜像得准）（间隔 0.2 弧度，120 px/s，中弹，0.25 秒显形）；0.6 秒后 other 放它的镜像（关于两体中垂线）
func _mirror_fan(lead: Dictionary, other: Dictionary, dir: Vector2) -> void:
	var angs: Array = []
	for k in 5:
		var a: float = dir.angle() + (float(k) - 2.0) * 0.2
		angs.append(MC.mirror_ang(a, lead.pos, other.pos))
		MC.shot(g, lead, lead.pos + Vector2.from_angle(a) * 28.0, a, 120.0, 1, {"hold": 0.25, "mult": 0.4, "col": _shot_col(lead)})
	lead.mirror_q = {"at": g.t + 0.6, "src": other, "angs": angs}
	lead.move_name = "镜潮"
	lead.move_t = g.t


## 镜像那一半的延迟发射（主教每帧查两具）
func _mirror_step(e: Dictionary, mate) -> void:
	for o in [e, mate]:
		if o == null or o.dead:
			continue
		var q = o.get("mirror_q")
		if not (q is Dictionary) or g.t < float(q.at):
			continue
		o.erase("mirror_q")
		var src: Dictionary = q.src
		if src.dead or src.get("coma", false):
			continue
		for a in q.angs:
			MC.shot(g, src, src.pos + Vector2.from_angle(float(a)) * 28.0, float(a), 120.0, 1, {"hold": 0.25, "mult": 0.4, "col": _shot_col(src)})


## 交错潮环（一幕 B）：两具同时放 16 向小弹环（90 px/s），主教的每秒左转 0.35 弧度、搭档的右转（2.2 秒后不再转），两环交出菱形格
func _twin_rings(e: Dictionary, mate: Dictionary) -> void:
	var base: float = (mate.pos - e.pos).angle()
	for o in [e, mate]:
		var sgn: float = 1.0 if is_same(o, e) else -1.0
		var ob: float = MC.mirror_ang(base, e.pos, mate.pos) if is_same(o, mate) else base
		for k in 16:
			var a: float = ob + TAU * k / 16.0 + PI / 16.0 * float(int(e.beat_n) % 2)
			MC.shot(g, o, o.pos + Vector2.from_angle(a) * (float(o.r) + 4.0), a, 90.0, 0, {"hold": 0.2, "mult": 0.4, "col": _shot_col(o), "turn": 0.35 * sgn, "turn_until": 2.2, "life": 4.5})
	e.move_name = "交错潮环"
	e.move_t = g.t


## 换位潮墙（二幕 A）：两体连线上等距 10 点，逐拍隔点取 5 点；每点显形一对弹（0.6 秒），各向连线两侧推开（60 → 115 px/s），颜色取近的那具
func _link_wall(e: Dictionary, mate: Dictionary) -> void:
	var a: Vector2 = e.pos
	var b: Vector2 = mate.pos
	var nrm: Vector2 = (b - a).normalized().orthogonal()
	for k in range(1, 11):
		if (k + int(e.get("beat_n", 0))) % 2 == 0:
			continue
		var at: Vector2 = a.lerp(b, float(k) / 11.0)
		var src: Dictionary = e if k <= 5 else mate
		for s in [1.0, -1.0]:
			MC.shot(g, src, at, (nrm * s).angle(), 60.0, 1, {"hold": 0.6, "mult": 0.4, "col": _shot_col(src), "acc": 70.0, "vmax": 115.0, "life": 4.0})
	e.move_name = "换位潮墙"
	e.move_t = g.t


## 双螺潮（二幕 B）：放的 1.6 秒里每 0.24 秒两具各出两臂小弹（100 px/s），主教的臂每秒转 +1.1 弧度、搭档的是它的镜像
func _spiral(e: Dictionary, mate: Dictionary) -> void:
	if g.t >= float(e.get("spiral_until", -1.0)) or g.t < float(e.get("spiral_next", -1.0)):
		return
	e.spiral_next = g.t + 0.24
	var t: float = g.t - float(e.get("spiral_t0", 0.0))
	var base: float = (mate.pos - e.pos).angle()
	for o in [e, mate]:
		var a0: float = base + 1.1 * t if is_same(o, e) else MC.mirror_ang(base + 1.1 * t, e.pos, mate.pos)
		for arm in 2:
			var a: float = a0 + PI * arm
			MC.shot(g, o, o.pos + Vector2.from_angle(a) * (float(o.r) + 4.0), a, 100.0, 0, {"mult": 0.4, "col": _shot_col(o), "life": 4.0})


## 弹体本色：各具专属色提亮（主教靛蓝太暗，各分量压到下限以上）
func _shot_col(o: Dictionary) -> Color:
	var c: Color = g.vfx.boss_color(o.type)
	return Color(maxf(c.r, 0.42), maxf(c.g, 0.5), maxf(c.b, 0.6))
