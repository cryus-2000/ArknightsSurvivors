## 塑路者（type path，docs/38 §2.1；招式改版 docs/95 §5，10-14 第 2 批；主轴改版 docs/142b §3.2 / §8.2，10-25；弹幕与连段改版 docs/170，10-27）
## Boss 行为脚本（docs/55 §6 拆分，10-10）：状态仍在敌人字典 e 上，预警 / 冷却 / 迫近经基类转给 boss_ai.gd。本文件只有这只 Boss 自己的招式与阶段逻辑。
## 主轴「截路」（原作：塑路者分形沿自身路径行动；描述「为大群探索生路」）：它从脚下往场边铺「生路」（4 段折线，每段末端一个金色路标），
##   分形沿路线走；队长跑过任一路标 = 这条路截断：路上的分形停下、变成主轴目标（部件，自动攻击先打）；所有路都断了它「迷路」硬直 path_lost（3）秒。
##   一幕「纠错」：一次一条，分形往外走，走到头它叠一层强化（伤害 +10%，最多 3 层）；每第 3 招附带召 1 只分形（原作「攻击 2 次后第 3 次召分形」）
##   二幕「订正」（关卡名）：一次两条，分形改往回走、走回它身上回 3% 生命；截断处放一圈「订正」刃环，2 秒后这条路改道重铺
## 弹幕（docs/170，本作改编，10-27）：每幕两套图案逐拍交替（A、B、A、B…），图案固定、只随你的位置和生路走向变，看两三拍就学得会。
##   一幕：探路分形（每个没断的路标向路线两侧吐分形种子，种子 1.35 秒后三分；截断路标 = 这一处不再吐）/ 错误路线（3 根树干弹两次二分成 12 根枝，枝间是缝）
##   二幕：回流（330 外一圈弹显形后往它身上收拢，缺口开在每条生路上：顺着路线跑、顺手截断就是躲法）/ 定向演化（6 向中弹各自二分）；
##        二幕每次冲撞沿锁定线留一排弹，冲完向两侧推开
## 连段（docs/169 口径，≤4 段、段间收势、结束破绽）：一幕 冲撞 → 震地 → 错误路线（或震地）/ 震地 → 冲撞；二幕 冲撞 → 折角冲撞 → 震地三连 / 震地三连 → 冲撞
## 躲招：冲撞（② 直线；队长靠近某条路线时顺着那条路冲——截路就是跑进冲撞道）/ 震地（① 落点圈）/ 订正（④ 断口刃环，二幕）
extends "res://scripts/enemies/bosses/boss_base.gd"

const MC = preload("res://scripts/enemies/mid_cards.gd")
const MOVES := ["冲撞", "震地", "订正", "探路分形", "错误路线", "回流", "定向演化"]
const TINT2 := Color(0.86, 0.95, 1.16)   # 第二幕常驻钢蓝亮边（docs/95 §5.2）
const STEEL := Color(0.7, 0.8, 0.95)
const SHOT1 := Color(0.42, 0.62, 1.0)    # 一幕弹：钢蓝（别和地面白石混）
const SHOT2 := Color(0.62, 0.42, 1.0)    # 二幕弹：分形紫
const DANGER := Color(1.0, 0.35, 0.3)


## 每帧（boss_ai._boss_ai 公共段之后）：ready = 本帧可以出招；mate = 接潮搭档（没有则 null）
func step(e: Dictionary, dt: float, dir: Vector2, dist: float, ready: bool, _mate) -> void:
	_expire_shaped(e)
	var p2: bool = int(e.get("gates_passed", 0)) >= 1
	if p2:
		_tint2(e, TINT2)
	_act_check(e, p2)
	MC.step_shots(g, e, dt)
	_wall_step(e)
	_paths_step(e, dt, p2)
	_pat_beat(e, dir)
	if MC.q_step(g, e, Callable(self, "_exec"), p2):
		return
	if not ready:
		return
	if dist < 240.0 and _cd(e, "slam", 9.0):   # 震地砸在主控脚下，240 内都会放
		MC.q_start(g, e, [{"actor": e, "move": "震地"}, {"actor": e, "move": "冲撞"}], 1.2 if not p2 else 1.6)
		_third(e)
	elif dist > 150.0 and _cd(e, "dash", 7.0):
		var follow: String = "错误路线" if int(e.get("beat_n", 0)) % 2 == 1 else "震地"
		if p2:
			MC.q_start(g, e, [{"actor": e, "move": "冲撞"}, {"actor": e, "move": "冲撞折"}, {"actor": e, "move": "震地"}], 1.8)
		else:
			MC.q_start(g, e, [{"actor": e, "move": "冲撞"}, {"actor": e, "move": "震地"}, {"actor": e, "move": follow}], 1.4)
		_third(e)


## 连段一段（mid_cards.q_step 调）：返回这段占用的秒数，放不出返回 -1
func _exec(e: Dictionary, move: String) -> float:
	var dir: Vector2 = (g.ppos - e.pos).normalized() if g.ppos.distance_to(e.pos) > 1.0 else Vector2.RIGHT
	match move:
		"冲撞":
			return _dash(e, dir).dur
		"冲撞折":
			# 折角：上一冲的走向转 90°，转向队长那一侧（读法：第一冲之后往冲撞线的「另一边」走）
			var a0: float = float(e.get("last_dash_ang", dir.angle()))
			var side: float = signf(Vector2.from_angle(a0).cross(dir))
			if side == 0.0:
				side = 1.0
			return _dash(e, Vector2.from_angle(a0 + side * PI * 0.5), true).dur
		"震地":
			_slam(e, dir)
			return 1.1 if int(e.get("gates_passed", 0)) < 1 else 1.9
		"错误路线":
			_tree(e, dir)
			return 0.9
	return -1.0


## ---- 弹幕节拍
## 幕沿用现有卡点（gates_passed）；进新幕时从 A 图案重新数拍，第一拍晚 1.6 秒（让过卡点的护盾与转幕颗粒先走完）
func _act_check(e: Dictionary, p2: bool) -> void:
	var act: int = 1 if p2 else 0
	if int(e.get("pat_act", -1)) != act:
		e.pat_act = act
		e.beat_n = 0
		e.pat_beat = g.t + (1.0 if act == 0 else 1.6)


## 节拍（不占出招令牌：它是这一幕的底色）；破绽（含迷路）/ 眩晕时停。一幕：探路分形 / 错误路线；二幕：回流 / 定向演化
func _pat_beat(e: Dictionary, dir: Vector2) -> void:
	if e.stun > 0.0 or float(e.get("break_t", 0.0)) > 0.0 or g.t < float(e.get("pat_beat", INF)) or e.age < 2.0:
		return
	var i: int = int(e.pat_act) * 2 + int(e.get("beat_n", 0)) % 2
	e.beat_n = int(e.get("beat_n", 0)) + 1
	match i:
		0:
			e.pat_beat = g.t + Bal.v("boss/path_pat_seed_cd", 2.6)
			_seeds(e)
		1:
			e.pat_beat = g.t + Bal.v("boss/path_pat_tree_cd", 3.2)
			_tree(e, dir)
		2:
			e.pat_beat = g.t + Bal.v("boss/path_pat_reflow_cd", 3.4)
			_reflow(e, dir)
		3:
			e.pat_beat = g.t + Bal.v("boss/path_pat_evo_cd", 3.6)
			_evolve(e, dir)


## 探路分形（一幕 A）：每个没断的路标向路线法向（逐拍左右交替）吐一颗分形种子：中弹 0.35 秒显形、60 px/s、1 秒后三分（±0.6 弧度、85 px/s 小弹）。
## 队长 70 以内的路标这一拍不吐（不在你脚下生弹）
func _seeds(e: Dictionary) -> void:
	var flip: float = 1.0 if int(e.beat_n) % 2 == 0 else -1.0
	for p in e.get("paths", []):
		if p.cut:
			continue
		var pts: Array = p.pts
		for k in range(1, pts.size()):
			var q: Vector2 = pts[k]
			if q.distance_to(g.ppos) < 70.0:
				continue
			var seg: Vector2 = (pts[k] - pts[k - 1]).normalized()
			var nrm: Vector2 = seg.orthogonal() * (flip if k % 2 == 0 else -flip)
			MC.shot(g, e, q, nrm.angle(), 60.0, 1, {"hold": 0.35, "mult": 0.35, "col": SHOT1,
				"split": {"t": 1.35, "n": 3, "spread": 0.6, "spd": 85.0, "tier": 0, "life": 3.0}})
			_puff(q, SHOT1, 4)


## 错误路线（一幕 B）：3 根树干弹（大，±0.5 弧度扇面朝队长）0.3 秒显形、70 px/s；1.1 秒后二分（±0.42），再 0.8 秒二分 → 12 根枝弹
func _tree(e: Dictionary, dir: Vector2) -> void:
	var col: Color = SHOT2 if int(e.get("gates_passed", 0)) >= 1 else SHOT1
	for k in 3:
		var a: float = dir.angle() + (float(k) - 1.0) * 0.5
		MC.shot(g, e, e.pos + Vector2.from_angle(a) * (float(e.r) + 6.0), a, 70.0, 2, {"hold": 0.3, "mult": 0.4, "col": col,
			"split": {"t": 1.4, "n": 2, "spread": 0.42, "spd": 80.0, "tier": 1, "depth": 1, "t2": 0.8, "life": 3.4}})
	_puff(e.pos, col, 10)
	e.move_name = "错误路线"
	e.move_t = g.t


## 回流（二幕 A）：半径 330 一圈 22 颗，0.7 秒显形后以 85 px/s 往它身上收拢（3.5 秒后消散，到不了本体）；
## 缺口开在每条没断的生路上（路线上每个点的方向 ±0.26 弧度不放弹）；没有路时缺口开在队长方向偏 0.9 弧度处
func _reflow(e: Dictionary, dir: Vector2) -> void:
	var gaps: Array = []
	for p in e.get("paths", []):
		if p.cut:
			continue
		for k in range(1, p.pts.size()):
			gaps.append((p.pts[k] - e.pos).angle())
	if gaps.is_empty():
		gaps = [dir.angle() + 0.9, dir.angle() + 0.9 + PI]
	var n := 22
	var off: float = (PI / n) * float(int(e.beat_n) % 2)
	for k in n:
		var a: float = TAU * k / n + off
		var blocked := false
		for ga in gaps:
			if absf(angle_difference(a, float(ga))) < 0.26:
				blocked = true
				break
		if blocked:
			continue
		var at: Vector2 = e.pos + Vector2.from_angle(a) * 330.0
		MC.shot(g, e, at, a + PI, 85.0, 1, {"hold": 0.7, "mult": 0.35, "col": SHOT2, "life": 3.5})
	e.move_name = "回流"
	e.move_t = g.t


## 定向演化（二幕 B）：6 向中弹（逐拍转 π/6），70 px/s，1.2 秒后各二分（±0.3）
func _evolve(e: Dictionary, dir: Vector2) -> void:
	var off: float = dir.angle() + PI / 6.0 * float(int(e.beat_n) % 2)
	for k in 6:
		var a: float = off + TAU * k / 6.0
		MC.shot(g, e, e.pos + Vector2.from_angle(a) * (float(e.r) + 6.0), a, 70.0, 1, {"hold": 0.25, "mult": 0.35, "col": SHOT2,
			"split": {"t": 1.45, "n": 2, "spread": 0.3, "spd": 95.0, "tier": 0, "life": 3.2}})
	_puff(e.pos, SHOT2, 8)


## 二幕冲撞留弹：冲撞预警锁定那一刻，沿锁定线每 48 放一颗（0 速显形，冲完再 0.45 秒）→ 逐颗左右交替向两侧推开（50 → 120 px/s）
func _wall_step(e: Dictionary) -> void:
	var w = e.get("wall_w")
	if not (w is Dictionary):
		return
	if w.t < float(w.track) and not w.done:
		return
	e.erase("wall_w")
	if int(e.get("pat_act", 0)) != 1 or e.dead:
		return
	var d := Vector2.from_angle(float(w.ang))
	var n: int = int(float(w.len) / 48.0)
	var rem: float = maxf(0.0, float(w.dur) - float(w.t))
	for k in range(1, n + 1):
		var at: Vector2 = w.pos + d * 48.0 * float(k)
		var side: float = 1.0 if k % 2 == 0 else -1.0
		MC.shot(g, e, at, (d.orthogonal() * side).angle(), 50.0, 1, {"hold": rem + 0.45 + 0.03 * k, "mult": 0.35, "col": SHOT2, "acc": 90.0, "vmax": 120.0, "life": 3.2})


## 弹出生的一小团颗粒（纯画面，走 Boss 颗粒预算）
func _puff(at: Vector2, col: Color, n: int) -> void:
	var gr = MC.BossBeam.grains(g)
	if gr == null:
		return
	for k in MC.BossBeam.take(g, n):
		gr.push("mote_burst", at, Vector2.from_angle(TAU * k / maxf(1.0, float(n))), col)


## 图鉴 / Boss 演练：直接进入第二幕
func setup_preview_phase2(e: Dictionary) -> void:
	e.gates_passed = maxi(1, int(e.get("gates_passed", 0)))
	_tint2(e, TINT2)


func demo_moves(_e: Dictionary) -> Array:
	return MOVES


func force_move(e: Dictionary, name: String, dir: Vector2, _dist: float) -> bool:
	match name:
		"冲撞":
			_dash(e, dir)
			return true
		"震地":
			_slam(e, dir)
			return true
		"订正":
			if int(e.get("gates_passed", 0)) < 1:
				return false
			_correct_at(e, g.combat.arena_clamp(e.pos + dir * 160.0, 80.0))
			return true
		"探路分形":
			if e.get("paths", []).is_empty():
				e.paths = [_new_path(e, false)]
			e.beat_n = int(e.get("beat_n", 0)) + 1
			_seeds(e)
			return true
		"错误路线":
			_tree(e, dir)
			return true
		"回流":
			e.beat_n = int(e.get("beat_n", 0)) + 1
			_reflow(e, dir)
			return true
		"定向演化":
			e.pat_act = 1
			_evolve(e, dir)
			_dash(e, dir)
			return true
	return false


## 过卡点（第二幕「订正」）：旧路清掉，按新规则重铺两条
func on_gate(e: Dictionary) -> void:
	_clear_paths(e)
	MC.q_cancel(g, e)
	e.path_next = g.t + 0.6


## A · 冲撞（保留）：440 × 30 线，fit_len 真冲到位，追踪 0.45 秒后锁定，总 0.9 秒；队长靠近某条路线时顺着那条路冲。
## 二幕沿锁定线留一排弹（_wall_step）。fixed：折角冲撞不追踪、不改顺路
func _dash(e: Dictionary, dir: Vector2, fixed := false) -> Dictionary:
	var ang: float = dir.angle() if fixed else _charge_ang(e, dir)
	var w: Dictionary = _warn(e, "line", 0.9 if not fixed else 0.8, {"ang": ang, "len": 440.0, "wid": 30.0, "track": 0.45 if not fixed else 0.0, "act": "dash", "fit_len": true,
		"name": "冲撞" if not fixed else "", "col": DANGER, "skin": "mc_dash"})
	e.last_dash_ang = ang
	if int(e.get("pat_act", 0)) == 1:
		e.wall_w = w
	return w


## 冲撞方向：队长离某条没断的路线 < path_charge_near（110）时，取那一段的走向（朝队长那一侧）；否则直接朝队长
func _charge_ang(e: Dictionary, dir: Vector2) -> float:
	var best := INF
	var seg_dir := Vector2.ZERO
	for p in e.get("paths", []):
		if p.cut:
			continue
		var pts: Array = p.pts
		for i in pts.size() - 1:
			var q: Vector2 = Geometry2D.get_closest_point_to_segment(g.ppos, pts[i], pts[i + 1])
			var d: float = q.distance_to(g.ppos)
			if d < best:
				best = d
				seg_dir = (pts[i + 1] - pts[i]).normalized()
	if best < Bal.v("boss/path_charge_near", 110.0) and seg_dir != Vector2.ZERO:
		if seg_dir.dot(dir) < 0.0:
			seg_dir = -seg_dir
		return seg_dir.angle()
	return dir.angle()


## B · 震地：主控当前位置 r90 固定落点，1.1 秒；e.dmg × 1.3。二幕沿「塑路者 → 主控」方向 3 连（主控身后 / 脚下 / 身前各一圈，依次晚 0.4 秒）
func _slam(e: Dictionary, dir: Vector2) -> void:
	if int(e.get("gates_passed", 0)) < 1:
		_warn(e, "circle", 1.1, {"pos": g.ppos, "r": 90.0, "act": "slam", "name": "震地", "col": Color(1.0, 0.55, 0.3), "dmg": e.dmg * 1.3, "skin": "mc_slam"})
		return
	for k in 3:
		_warn(e, "circle", 1.1 + 0.4 * k, {"pos": g.combat.arena_clamp(g.ppos + dir * (float(k) - 1.0) * 90.0, 80.0), "r": 70.0, "act": "slam",
			"name": "震地" if k == 0 else "", "col": Color(1.0, 0.55, 0.3), "dmg": e.dmg * 1.1, "lock": k == 0, "skin": "mc_slam"})


## 原作「攻击 2 次后，下一次攻击时召唤 1 个分形」：一幕每第 3 招在脚边长 1 只（20 秒自灭，本体所属 <8）
func _third(e: Dictionary) -> void:
	if int(e.get("gates_passed", 0)) >= 1:
		return
	e.move_n = int(e.get("move_n", 0)) + 1
	if int(e.move_n) % 3 != 0 or _owned(e) >= 8:
		return
	var o: Dictionary = g.spawner.spawn_enemy("fractal", g.combat.arena_clamp(e.pos + Vector2.from_angle(g.rng_enemy.randf() * TAU) * 50.0, 60.0))
	o.owner = e
	o.expire_at = g.t + 20.0
	var lst: Array = e.get("spawned_after", [])
	lst.append(o)
	e.spawned_after = lst


## 订正（二幕，本作原创，取材紧急关卡「订正」）：截断处为心 r70 空心刃环（缺口朝塑路者，从缺口里退出），0.9 秒；e.dmg × 0.8
func _correct_at(e: Dictionary, at: Vector2) -> void:
	_warn(e, "circle", 0.9, {"pos": at, "r": 70.0, "act": "spin_ring", "gap_ang": (e.pos - at).angle(), "gap_half": 0.7, "ang": 0.0,
		"name": "订正", "col": Color(0.55, 0.65, 1.0), "dmg": e.dmg * 0.8, "lock": false})


## ---- 生路（docs/142b §3.2）
## e.paths = [{pts: [起点 + 4 个路标], cut, cut_i, inward, frs: [{o, s}], next_spawn, born, reroute_at}]；画面在 render/boss_beam.draw_ground
func _paths_step(e: Dictionary, dt: float, p2: bool) -> void:
	if float(e.get("break_t", 0.0)) > 0.0 and e.get("lost", false):
		return   # 迷路硬直中：路已经清掉，起身再铺
	e.lost = false
	var paths: Array = e.get("paths", [])
	var want: int = 2 if p2 else 1
	# 铺新路：没断的路少于 want 条、冷却到了
	var live: int = paths.filter(func(p): return not p.cut).size()
	if live < want and g.t >= float(e.get("path_next", 0.0)):
		paths.append(_new_path(e, p2))
		e.path_next = g.t + Bal.v("boss/path_lay_cd", 10.0) * (0.5 if p2 else 1.0)
	var spd: float = Bal.v("boss/path_fr_spd", 60.0)
	for p in paths:
		# 截断：队长跑过任一路标
		if not p.cut:
			for i in range(1, p.pts.size()):
				if g.combat.ground_d(g.ppos, p.pts[i]) < Bal.v("boss/path_node_r", 24.0):
					_cut(e, p, i, p2)
					break
		# 改道重铺（二幕）
		if p.cut and p2 and float(p.get("reroute_at", INF)) <= g.t:
			p.reroute_at = INF
			var np: Dictionary = _new_path(e, true)
			p.pts = np.pts
			p.cut = false
			p.cut_i = -1
			p.born = g.t
			p.frs = []
		# 刷分形
		if not p.cut and g.t >= float(p.next_spawn) and p.frs.size() < 4 and _owned(e) < 8:
			p.next_spawn = g.t + Bal.v("boss/path_fr_every", 2.5)
			var at: Vector2 = p.pts[p.pts.size() - 1] if p.inward else p.pts[0]
			var o: Dictionary = g.spawner.spawn_enemy("fractal", at)
			o.owner = e
			o.spd = 0.0   # 自己沿路走（下面），不追人
			o.path_walk = true
			p.frs.append({"o": o, "s": 0.0})
		# 走路
		var keep: Array = []
		for f in p.frs:
			var o: Dictionary = f.o
			if o.dead:
				continue
			if p.cut:
				keep.append(f)
				continue
			f.s = float(f.s) + spd * dt
			var res: Array = _along(p.pts, float(f.s), p.inward)
			o.pos = res[0]
			if res[1]:
				if p.inward:
					# 走回本体：再直线走过去，到了回血
					if o.pos.distance_to(e.pos) > e.r + 12.0:
						f.s = float(f.s) - spd * dt   # 停在路尽头，直线靠过去
						o.pos = o.pos.move_toward(e.pos, spd * dt * 1.5)
						if o.pos.distance_to(e.pos) > e.r + 12.0:
							keep.append(f)
							continue
					o.dead = true
					e.hp = minf(e.maxhp, e.hp + e.maxhp * Bal.v("boss/path_return_heal", 0.03))
					g.vfx.add_text(e.pos + Vector2(0, -60), "订正 · 回流", STEEL, 14)
					g.fx.append({"kind": "reflow", "a": res[0], "b": e.pos, "life": 0.5, "max": 0.5, "enemy": true})
				else:
					o.dead = true
					_stack(e)
				continue
			keep.append(f)
		p.frs = keep
	# 旧路（一幕没断、存在超过 path_life 秒）撤掉
	paths = paths.filter(func(p): return p.cut and p2 or g.t - float(p.born) < Bal.v("boss/path_life", 16.0) or p.cut)
	e.paths = paths
	# 迷路：有过路、全部截断
	if not paths.is_empty() and paths.all(func(p): return p.cut) and paths.size() >= want:
		_lost(e)


## 新路：起点 = 本体，朝背对队长的方向（± 1 弧度随机）分 4 段、每段 path_seg（110–150）、每段转 ±0.6 弧度；都夹在场地圈内
func _new_path(e: Dictionary, inward: bool) -> Dictionary:
	var ang: float = (e.pos - g.ppos).angle() + g.rng_enemy.randf_range(-1.0, 1.0)
	var pts: Array = [e.pos]
	var p: Vector2 = e.pos
	for k in 4:
		ang += g.rng_enemy.randf_range(-0.6, 0.6)
		p = g.combat.arena_clamp(p + Vector2.from_angle(ang) * g.rng_enemy.randf_range(110.0, 150.0), 80.0)
		pts.append(p)
	g.fx.append({"kind": "gcrack", "pos": e.pos, "r": 60.0, "life": 0.6, "max": 0.6, "col": Color(0.6, 0.7, 1.0), "enemy": true, "opts": {"n": 6}})
	return {"pts": pts, "cut": false, "cut_i": -1, "inward": inward, "frs": [], "next_spawn": g.t + 0.3, "born": g.t, "reroute_at": INF}


## 沿折线走 s 像素（inward 从末端往起点走）：返回 [位置, 是否走到头]
func _along(pts: Array, s: float, inward: bool) -> Array:
	var seq: Array = pts.duplicate()
	if inward:
		seq.reverse()
	var left: float = s
	for i in seq.size() - 1:
		var L: float = seq[i].distance_to(seq[i + 1])
		if left <= L:
			return [seq[i].lerp(seq[i + 1], left / maxf(L, 1.0)), false]
		left -= L
	return [seq[seq.size() - 1], true]


## 截断：路上的分形停下、变成主轴目标（部件，自动攻击先打）；二幕断口放订正刃环、2 秒后改道重铺
func _cut(e: Dictionary, p: Dictionary, i: int, p2: bool) -> void:
	p.cut = true
	p.cut_i = i
	for f in p.frs:
		var o: Dictionary = f.o
		if o.dead:
			continue
		o.part = true
		g.enemies_sys.part_add(o)
	g.fx.append({"kind": "ring", "pos": p.pts[i], "r": 30.0, "life": 0.4, "max": 0.4, "col": Color(1.0, 0.85, 0.4), "enemy": true})
	g.vfx.add_text(p.pts[i] + Vector2(0, -30), "截断", Color(1.0, 0.85, 0.4), 16)
	Sfx.play("stake_hit", -8.0, 1.4, 0.0)
	if p2:
		_correct_at(e, p.pts[i])
		p.reroute_at = g.t + Bal.v("boss/path_reroute", 2.0)


## 探到生路（一幕）：叠一层强化，伤害 +10%（最多 3 层）
func _stack(e: Dictionary) -> void:
	var n: int = int(e.get("path_stack", 0))
	if n >= 3:
		return
	if not e.has("dmg0"):
		e.dmg0 = e.dmg
	e.path_stack = n + 1
	e.dmg = float(e.dmg0) * (1.0 + 0.1 * e.path_stack)
	g.vfx.add_text(e.pos + Vector2(0, -60), "探到生路 · 强化 %d" % e.path_stack, Color(1.0, 0.45, 0.35), 16)
	Sfx.play("roar", -10.0, 1.4, 0.0)


## 迷路：所有路都断了 → 硬直 path_lost（3）秒（破绽，受伤 × break_mult），路清掉，起身再铺
func _lost(e: Dictionary) -> void:
	_clear_paths(e)
	e.lost = true
	g.combat.start_break(e, Bal.v("boss/path_lost", 3.0))
	g.vfx.add_text(e.pos + Vector2(0, -70), "迷路！", Color(1.0, 0.85, 0.4), 22)
	Sfx.play("boom", -6.0, 1.3, 0.0)
	e.path_next = g.t + Bal.v("boss/path_lost", 3.0) + 0.5


func _clear_paths(e: Dictionary) -> void:
	e.paths = []


func _owned(e: Dictionary) -> int:
	var n := 0
	for o in g.enemies:
		if o.type == "fractal" and not o.dead and is_same(o.get("owner"), e):
			n += 1
	return n


## 第 3 招长出来的分形 20 秒自灭（docs/38 §2.1；路上的、截停的不限时）
func _expire_shaped(e: Dictionary) -> void:
	var lst: Array = e.get("spawned_after", [])
	if lst.is_empty():
		return
	var keep: Array = []
	for o in lst:
		if o.dead:
			continue
		if g.t >= float(o.get("expire_at", INF)):
			o.dead = true
			g.vfx.sparks(o.pos, Vector2.ZERO, Color(0.6, 0.7, 1.0), 6, 140.0)
			continue
		keep.append(o)
	e.spawned_after = keep
