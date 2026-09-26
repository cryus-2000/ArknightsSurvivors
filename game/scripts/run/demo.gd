extends RefCounted
## 图鉴攻击演示 / 精英化演出（gallery.gd 把 game.tscn 以 demo_op 模式放进 SubViewport）：分段轮播技能、刷怪海、主控走走停停。
## 演示状态（demo_op / demo_stage / demo_label …）仍在 game.gd，图鉴直接读。2026-09-26 从 game.gd 拆出。

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game
var demo_skill := -1           # 演示时只循环施放这个技能（-1 = 一 / 二 / 三技能分段轮流）
## 图鉴演示每帧：主控满状态；三个位置各维持一只不动、不伤人的假人海嗣，被打死 1.5 秒后原地重生。
## 假人会慢慢挪向开局干员并停在 70 以外，让近战干员也够得着；击退后自然回位
## 图鉴 / 精英化演出（2026-09-25 改版，用户要求）：按「一技能 → 二技能 → 三技能」分段循环，每段单独展示一招。
## 每段开始时重置：干员重新生成（永久型 / 叠层等状态不带到下一段）、主控站左边、右边刷一片怪海慢慢推过来；
## 先普攻约 1 秒再充满这一段的技能（其余技能压住不充），技能放完、效果结束再停 1.5 秒进入下一段；怪清空了就在右边补一波。
## 精英化演出（demo_skill ≥ 0）只循环刚解锁的那一招。gallery.gd 读 demo_label 显示当前是哪一段。
const DEMO_HORDE := 16
const DEMO_FILL_AT := 1.0
const DEMO_HOLD := 1.5
const DEMO_MAX := 14.0
const DEMO_MAX_LINGER := 27.0    # 留场表现中的上限（幽灵鲨：S2 10 秒 + 替身 12 秒 + 起手）
var demo_ph_t := 0.0
var demo_cast_t := -1.0          # 本段技能放出后经过的秒数（-1 = 还没放）
## 走位（见 wander）：当前要走去的点（INF = 站着）、还要站多久
var walk_to := Vector2.INF
var stand_t := 0.0
const WALK_X := Vector2(-45.0, 65.0)    # 落脚点：出发点左 45 到右 65（再往左贴画面边）、上下 ±48（演示画面是固定机位）
const WALK_Y := 48.0
const WALK_MIN_GAP := 105.0              # 落脚点离最近的怪至少这么远；怪贴到 WALK_BACK 以内就先往后退
const WALK_BACK := 62.0


func _init(game: Game) -> void:
	g = game


func step(dt: float) -> void:
	g.lamp = 100.0
	g.hp = g.max_hp
	g.xp = 0.0
	g.gems.clear()
	if g.demo_origin == Vector2.INF:
		g.demo_origin = g.ppos
		g.demo_phases = phase_list()
		next_phase()
	var si: int = g.demo_phases[g.demo_pi]
	demo_ph_t += dt
	_walk_plan(dt)
	if g.demo_basic:
		# 三联对照：只看普攻，技能全部压住；怪少了就补
		for i in 3:
			if not g.ch.perm[i]:
				g.ch.sp[i] = 0.0
		var alive0 := 0
		for e in g.enemies:
			if not e.dead:
				alive0 += 1
		if alive0 < 8:
			horde(10)
		return
	# 只让本段的技能充能：其余压成 0
	for i in 3:
		if i != si and not g.ch.perm[i]:
			g.ch.sp[i] = 0.0
	if demo_cast_t < 0.0:
		if demo_ph_t >= DEMO_FILL_AT and g.ch.skill_unlocked(si):
			if g.ch.sp[si] < g.ch.sp_need(si) and demo_ph_t < DEMO_FILL_AT + dt * 1.5:
				g.ch.sp[si] = g.ch.sp_need(si)
			if g.ch.is_manual(si) and g.ch.sp[si] >= g.ch.sp_need(si):
				g.ch.cast_manual(si)   # 手动技能（幽灵鲨 S2）没人按键：替玩家放
			# 充满后被消费掉（或永久型已生效）= 放出去了
			if g.ch.sp[si] < g.ch.sp_need(si) * 0.5 or g.ch.perm[si] or g.ch.skill_active_left(si) > 0.0:
				demo_cast_t = 0.0
	else:
		demo_cast_t += dt
	# 技能结束后还有留场表现（幽灵鲨 S2 结束本体倒下、替身跟随 12 秒，away()）：等它演完再切下一段，
	# 否则一切段就重建干员，替身只出现一帧（docs/32 §3，测试与验收发现）
	var lingering: bool = g.ch.has_method("away") and g.ch.away()
	var done: bool = demo_cast_t >= DEMO_HOLD and g.ch.skill_active_left(si) <= 0.0 and not g.ch.acting() and not lingering
	if done or demo_ph_t >= (DEMO_MAX_LINGER if lingering else DEMO_MAX):
		next_phase()
		return
	# 怪海清空了：右边补一波
	var alive := 0
	for e in g.enemies:
		if not e.dead:
			alive += 1
	if alive < 4:
		horde(10)


## 演示走位（2026-09-26 用户要求：像对局里一样走，不要固定绕圈）：走走停停——站 0.6–1.6 秒，再走到附近一个
## 随机落脚点（出发点附近 WALK_X × WALK_Y 内、离怪至少 WALK_MIN_GAP），走到就停；怪贴脸（WALK_BACK 以内）时先往后退一步，
## 和机器人躲贴身敌人一个思路。返回摇杆量（≤0.6），朝向 / 走路动画 / 队友跟随都走对局的同一套逻辑
func wander() -> Vector2:
	if g.demo_origin == Vector2.INF:
		return Vector2.ZERO
	var push := Vector2.ZERO
	for e in g.enemies:
		if e.dead:
			continue
		var d: Vector2 = g.ppos - e.pos
		var l: float = d.length()
		if l < WALK_BACK and l > 0.01:
			push += d / l * (WALK_BACK - l) / WALK_BACK
	if push != Vector2.ZERO:
		walk_to = Vector2.INF
		return push.normalized() * 0.6
	if walk_to == Vector2.INF:
		return Vector2.ZERO
	var dv: Vector2 = walk_to - g.ppos
	if dv.length() < 6.0:
		walk_to = Vector2.INF
		stand_t = g.rng.randf_range(0.6, 1.6)
		return Vector2.ZERO
	return (dv / maxf(g.speed * 0.25, 1.0)).limit_length(0.6)


## 每帧：站够了就挑下一个落脚点（试几次，挑离怪最远的那个）
func _walk_plan(dt: float) -> void:
	if walk_to != Vector2.INF:
		return
	stand_t -= dt
	if stand_t > 0.0:
		return
	var home: Vector2 = g.demo_origin + Vector2(-150, 10)
	var best := Vector2.INF
	var best_gap := -1.0
	for k in 6:
		var p: Vector2 = home + Vector2(g.rng.randf_range(WALK_X.x, WALK_X.y), g.rng.randf_range(-WALK_Y, WALK_Y))
		if p.distance_to(g.ppos) < 30.0:
			continue   # 太近的挪一小步看不出在走
		var gap := 99999.0
		for e in g.enemies:
			if not e.dead:
				gap = minf(gap, p.distance_to(e.pos))
		if gap >= WALK_MIN_GAP:
			best = p
			break
		if gap > best_gap:
			best_gap = gap
			best = p
	walk_to = best
	if walk_to == Vector2.INF:
		stand_t = 0.3


## 图鉴手动切换（gallery.gd 点击调用）：stage 0 精零（N1 N2 后）/ 1 精一（N5 后）/ 2 精二；
## mode -1 轮播已解锁的技能 / 0–2 只放该技能 / 3 只普攻。立即重置场地与干员
func configure(stage: int, mode: int) -> void:
	g.demo_stage = clampi(stage, 0, 2)
	g.demo_basic = mode == 3
	demo_skill = mode if mode >= 0 and mode <= 2 else -1
	if g.demo_origin == Vector2.INF:
		return   # 还没开始跑：第一帧 _demo_step 初始化时按这些设置来
	g.demo_phases = phase_list()
	g.demo_pi = -1
	next_phase()


## 本阶段可展示的技能段：只轮播已解锁的技能（精零只有一技能）
func phase_list() -> Array:
	if demo_skill >= 0:
		return [demo_skill]
	if g.demo_stage >= 0:
		return range(g.demo_stage + 1)
	return [0, 1, 2]


func next_phase() -> void:
	g.demo_pi = (g.demo_pi + 1) % g.demo_phases.size()
	demo_ph_t = 0.0
	demo_cast_t = -1.0
	walk_to = Vector2.INF
	stand_t = 1.0   # 开场先站着普攻一会儿
	g.enemies.clear()
	g.bullets.clear()
	g.ppos = g.demo_origin + Vector2(-150, 10)
	new_op()
	horde(DEMO_HORDE)
	var si: int = g.demo_phases[g.demo_pi]
	g.demo_label = "普攻「%s」" % g.ch.attack_def().get("name", "") if g.demo_basic else "%s技能「%s」" % [["一", "二", "三"][si], g.ch.skill_def(si).get("name", "")]


## 重新生成演示干员：清掉旧实例挂在 op:<id> 作用域上的全部修正，再按演示要求推到精英化阶段
func new_op() -> void:
	var id: String = g.demo_op
	if g.ch != null and g.squad.has(id):
		g.squad.remove(id)
	g.stats.remove_scope("op:" + id)
	g._sync_stats()
	g.ch = g.squad.add(id)
	if g.demo_stage >= 0:
		# 三联对照：按成长节点数推进（N1 N2 → 2 个；到 N5 → 5 个；全部 → 6 个）
		var nodes: int = [2, 5, 6][clampi(g.demo_stage, 0, 2)]
		for k in nodes:
			if g.ch.next_node().is_empty():
				break
			var n0: Dictionary = g.ch.next_node()
			var chs0: Dictionary = g.ch.elite_choices(n0) if n0.get("type", "") == "elite" else {}
			g.ch.advance(chs0.keys()[0] if not chs0.is_empty() else "")
		g.show_queue.clear()
		g.facing = 1.0
		g.ch.pos = g.ppos
		return
	var want: int = g.demo_elite if g.demo_elite > 0 else 2
	var guard := 0
	while g.ch.elite < want and not g.ch.next_node().is_empty() and guard < 12 and g.demo_elite > 0:
		guard += 1
		var n: Dictionary = g.ch.next_node()
		var chs: Dictionary = g.ch.elite_choices(n) if n.get("type", "") == "elite" else {}
		g.ch.advance(chs.keys()[0] if not chs.is_empty() else "")
	if g.ch.elite < want:
		g.ch.elite = want
	g.show_queue.clear()
	g.facing = 1.0   # 主控面朝右侧怪海
	g.ch.pos = g.ppos + g.squad._slot_offset(0)   # 直接站在跟随位上，开场不再先走一步


## 右边刷一片怪海：椭圆区域里随机撒开，慢慢向主控推进（演示里敌人不造成伤害）
func horde(n: int) -> void:
	for k in n:
		var a: float = g.rng.randf() * TAU
		var r: float = sqrt(g.rng.randf())
		# 前排离主控约 140（近战干员的前压范围 150 以内），一开场就能接敌
		var p: Vector2 = g.demo_origin + Vector2(85 + cos(a) * r * 90.0, sin(a) * r * 72.0)
		var ne := g.spawner.spawn_enemy("bone", p)
		ne.spd = 16.0
		ne.dmg = 0.0
		ne.hp = 140.0
		ne.maxhp = 140.0
		ne.xp = 0.0


## 开发自测：把所有 Boss（含假死/二阶段形态）摆成一排截图，检查美术接入与 2.5D 遮挡
func gallery_step() -> void:
	g.ppos = Vector2.ZERO
	g.hp = g.max_hp
	g.lamp = 100.0
	if g.at_frames == 20:
		for e in g.enemies:
			e.dead = true
		var types := ["path", "carmen", "iberia", "bishop", "archon", "immortal", "paranoia", "paranoia", "bishop", "archon", "immortal", "fractal"]
		for i in types.size():
			var p := Vector2(-520 + (i % 6) * 208, -170 + (i / 6) * 250)
			var e := g.spawner.spawn_enemy(types[i], p)
			e.spd = 0.0
			e.dmg = 0.0
			e["gallery"] = true
			if i == 7:
				e.phase = 2
			if i >= 8 and i <= 10:
				e["gal_coma"] = true
	for e in g.enemies:
		if not e.get("gallery", false):
			e.dead = true
		else:
			e.hp = e.maxhp
			e.stun = 0.0
			if e.get("gal_coma", false):
				e["coma"] = true
				e.hp = e.maxhp * 0.5
			e.kb = Vector2.ZERO
	if g.at_frames == 90 and DisplayServer.get_name() != "headless":
		g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_gallery.png")
		g.get_tree().quit()
