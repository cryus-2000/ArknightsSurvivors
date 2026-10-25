## 塑路者（type path，docs/38 §2.1；招式改版 docs/95 §5，10-14 第 2 批；主轴改版 docs/142b §3.2 / §8.2，10-25）
## Boss 行为脚本（docs/55 §6 拆分，10-10）：状态仍在敌人字典 e 上，预警 / 冷却 / 迫近经基类转给 boss_ai.gd。本文件只有这只 Boss 自己的招式与阶段逻辑。
## 主轴「截路」（原作：塑路者分形沿自身路径行动；描述「为大群探索生路」）：它从脚下往场边铺「生路」（4 段折线，每段末端一个金色路标），
##   分形沿路线走；队长跑过任一路标 = 这条路截断：路上的分形停下、变成主轴目标（部件，自动攻击先打）；所有路都断了它「迷路」硬直 path_lost（3）秒。
##   一幕「探路」：一次一条，分形往外走，走到头它叠一层强化（伤害 +10%，最多 3 层）；每第 3 招附带召 1 只分形（原作「攻击 2 次后第 3 次召分形」）
##   二幕「订正」（关卡名）：一次两条，分形改往回走、走回它身上回 3% 生命；截断处放一圈「订正」刃环，2 秒后这条路改道重铺；冲撞 2 连、震地 3 连
## 躲招：冲撞（② 直线；队长靠近某条路线时顺着那条路冲——截路就是跑进冲撞道）/ 震地（① 落点圈）/ 订正（④ 断口刃环，二幕）
## 去掉：碎裂、猎核、分形塑路扇形（截路取代「要去打的东西」）
extends "res://scripts/enemies/bosses/boss_base.gd"

const MOVES := ["冲撞", "震地", "订正"]
const TINT2 := Color(0.86, 0.95, 1.16)   # 第二幕常驻钢蓝亮边（docs/95 §5.2）
const STEEL := Color(0.7, 0.8, 0.95)


## 每帧（boss_ai._boss_ai 公共段之后）：ready = 本帧可以出招；mate = 接潮搭档（没有则 null）
func step(e: Dictionary, dt: float, dir: Vector2, dist: float, ready: bool, _mate) -> void:
	_expire_shaped(e)
	var p2: bool = int(e.get("gates_passed", 0)) >= 1
	if p2:
		_tint2(e, TINT2)
	_paths_step(e, dt, p2)
	if not ready:
		return
	if dist < 240.0 and _cd(e, "slam", 9.0):   # 震地砸在主控脚下，240 内都会放（原 170；分形塑路扇形删掉后中距离只剩冲撞）
		_slam(e, dir)
		_third(e)
	elif e.get("dash_left", 0) > 0 and e.get("dash_t", 0.0) <= 0.0:
		# 第二幕冲撞连段（docs/38 §8.1）：上一段冲完立刻接下一段，每段仍有完整预警
		e.dash_left -= 1
		_warn(e, "line", 0.8, {"ang": _charge_ang(e, dir), "len": 440.0, "wid": 30.0, "track": 0.35, "act": "dash", "fit_len": true, "name": "", "col": Color(1.0, 0.35, 0.3)})
	elif dist > 150.0 and _cd(e, "dash", 6.0):
		_dash(e, dir)
		_third(e)


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
	return false


## 过卡点（第二幕「订正」）：旧路清掉，按新规则重铺两条
func on_gate(e: Dictionary) -> void:
	_clear_paths(e)
	e.path_next = g.t + 0.6


## A · 冲撞（保留）：440 × 30 条纹线，fit_len 真冲到位，追踪 0.45 秒后锁定，总 0.9 秒；第二幕 2 连。队长靠近某条路线时顺着那条路冲
func _dash(e: Dictionary, dir: Vector2) -> void:
	_warn(e, "line", 0.9, {"ang": _charge_ang(e, dir), "len": 440.0, "wid": 30.0, "track": 0.45, "act": "dash", "fit_len": true, "name": "冲撞", "col": Color(1.0, 0.35, 0.3)})
	if e.get("gates_passed", 0) >= 1:
		e.dash_left = int(Bal.v("boss/path_dash_chain", 1.0))


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
		_warn(e, "circle", 1.1, {"pos": g.ppos, "r": 90.0, "act": "slam", "name": "震地", "col": Color(1.0, 0.55, 0.3), "dmg": e.dmg * 1.3})
		return
	for k in 3:
		_warn(e, "circle", 1.1 + 0.4 * k, {"pos": g.combat.arena_clamp(g.ppos + dir * (float(k) - 1.0) * 90.0, 80.0), "r": 70.0, "act": "slam",
			"name": "震地" if k == 0 else "", "col": Color(1.0, 0.55, 0.3), "dmg": e.dmg * 1.1, "lock": k == 0})


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
