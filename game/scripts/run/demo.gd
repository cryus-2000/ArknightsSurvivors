extends RefCounted
## 图鉴攻击演示 / 精英化演出（gallery.gd 把 game.tscn 以 demo_op 模式放进 SubViewport）：分段轮播技能、刷怪海、主控冲向怪群出手。
## 演示状态（demo_op / demo_stage / demo_label …）仍在 game.gd，图鉴直接读。2026-09-26 从 game.gd 拆出。

const Ult = preload("res://scripts/run/ult.gd")
const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game
var demo_skill := -1           # 演示时只循环施放这个技能（-1 = 一 / 二 / 三技能分段轮流）
## 终结技演示段（图鉴按钮「终结技」，mode = ULT）：干员当队长，DEMO_FILL_AT 时替它充满能量、按一下 Q 自动瞄准放出；演出结束再停 DEMO_HOLD 秒重放
const ULT := 4
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
var demo_filled := false         # 本段已经替它充满过一次（只充一次：放完后不会再被补满、放第二遍）
var demo_after_t := 0.0          # 技能效果 / 出手 / 留场都结束后又过了多久（收尾爆炸等演完再切段）
var demo_hurt_t := 0.0
const DEMO_HURT_EVERY := 3.0     # 每 3 秒把主控生命压到 70%：治疗干员（凯尔希、铃兰…）才有东西可治（演示里怪不伤人）
## 走位（见 wander）：是否正在走向怪
var charging := false
var skill_hold := 0.0            # 放技能的动作期间及之后 1 秒站着不动：施放特效（铃兰金环、光柱）画在起手点，走开就偏到身后
var charge_t := 0.0              # 这次起步后走了多久：至少走 WALK_MIN_T 才允许停（不走一帧就停）
const WALK_MIN_T := 0.3
const WALK_MV := 0.7             # 摇杆量（匀速）
const WALK_SLACK := 28.0         # 停下后，最近的怪要比出手距离再远这么多才重新起步（滞后，免得走一步停一步）
const WALK_MAX_X := 110.0        # 最远走到出发点右边这么远（固定机位，别走出画面）
const DEMO_DY := 40.0            # 主控和怪海整体下移：图鉴演示框上沿压着标题与两排按钮（约 70 像素），飘字 / 炸点 / Mon3tr / 跃空锤（跳高 42）别钻到下面
const DEMO_OP_DX := -180.0       # 主控出发点在演示中心左边多远（原 150；用户 10-24「图鉴里干员和怪物离开得远一点」，镜头同时拉远到 ×0.8，两者都在框里）
const DEMO_HORDE_DX := 115.0     # 怪海中心在演示中心右边多远（原 85）
const DEMO_BITE_KB := 240.0      # 贴身的怪「扑一口」后弹开的冲量：enemies.gd 按 900/s 衰减，240 ≈ 弹开 32，再以 spd 16 走回来约 2 秒
const DEMO_BITE_CD := 1.2        # 同一只怪两次扑击至少隔这么久（弹开 + 走回来的时间里不会再扑）


func _init(game: Game) -> void:
	g = game


func step(dt: float) -> void:
	g.lamp = 100.0
	demo_hurt_t += dt
	if demo_hurt_t >= DEMO_HURT_EVERY:
		demo_hurt_t = 0.0
		g.hp = g.max_hp * 0.7
		if g.ch != null and g.ch.has_method("demo_hurt"):
			g.ch.demo_hurt()   # 数据干员：模拟一次「队长受到攻击」（凯尔希回防、星熊格挡 / 反击架势在演示里也能看到）
	for m in g.squad.ops:   # 演示队友（gallery.demo_mate）只普攻、不放技能
		if m != g.ch:
			for i in 3:
				if not m.perm[i]:
					m.sp[i] = 0.0
	g.hp = clampf(g.hp, g.max_hp * 0.5, g.max_hp)
	g.xp = 0.0
	g.gems.clear()
	_growth_demo(dt)   # docs/202 成长节点演示条件（gallery.demo_dash_cd / demo_ctrl）
	if g.demo_origin == Vector2.INF:
		g.demo_origin = g.ppos
		g.demo_phases = phase_list()
		next_phase()
	_contact_cycle()
	var si: int = g.demo_phases[g.demo_pi]
	demo_ph_t += dt
	if g.ult != null and si != ULT:
		g.ult.energy = 0.0   # 技能段不攒终结技能量（免得 HUD 一直提示就绪）
	if si == ULT:
		_ult_step(dt)
		return
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
	# 只让本段的技能充能：其余压成 0；本段的技能放出后也压住，免得短冷却的技能在长段里自然回满再放一遍（docs/45）
	for i in 3:
		if (i != si or demo_cast_t >= 0.0) and not g.ch.perm[i]:
			g.ch.sp[i] = 0.0
	if demo_cast_t < 0.0:
		if demo_ph_t >= DEMO_FILL_AT and g.ch.skill_unlocked(si):
			if not demo_filled:
				demo_filled = true
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
	var busy: bool = g.ch.skill_active_left(si) > 0.0 or g.ch.skill_pending(si) or lingering
	# 从效果结束起再停 DEMO_HOLD 秒（以前从放出时算：凯尔希熔毁 8 秒一结束就切段，收尾大爆演不到）；普攻出手不算忙，只是不在出手中途切
	demo_after_t = 0.0 if busy or demo_cast_t < 0.0 else demo_after_t + dt
	var done: bool = demo_cast_t >= 0.0 and demo_after_t >= DEMO_HOLD and not g.ch.acting()
	if done or demo_ph_t >= (DEMO_MAX_LINGER if busy else DEMO_MAX):
		next_phase()
		return
	# 怪海清空了：右边补一波
	var alive := 0
	for e in g.enemies:
		if not e.dead:
			alive += 1
	if alive < 4:
		horde(10)


## 贴身循环（用户 10-14 反馈：图鉴里怪海推到干员身边后贴着模型边缘不动 / 抖动）。
## 原因：演示里的怪不伤人（horde 给 dmg 0），走不到 enemies.gd 的接触伤害分支；而正式局里接触也不会把怪推开，
## 全靠玩家走位拉开距离——演示主控站定出手，骨海漂流体就一路走到主控脚下叠在身上，只剩怪与怪的分离在来回推挤。
## 这里按正式局同一接触半径（e.r + 12）判「扑上来」：播攻击帧条（atk_until）、沿离主控方向弹开 DEMO_BITE_KB（走 e.kb，
## 和被干员打退同一条路），再以原速走回来，每只至少隔 DEMO_BITE_CD 秒再扑一次——「扑上来 → 弹开 → 再上来」。
## 只在 step（demo_op 模式）里调用，正式局的敌人逻辑不变
var demo_ctrl_t := 0.0
var demo_wind_t := 0.0
var demo_surr_t := 0.0


## 成长节点演示条件（docs/202，干员 JSON gallery 里写）：demo_dash_cd = 队长冲刺冷却保持在这个秒数（德克萨斯「居合」有东西可缩）；
## demo_ctrl = 每这么多秒让离队长最近的 3 只怪眩晕 1.5 秒（能天使「对空优先」有受控目标）；demo_windup = 每这么多秒让最近 4 只怪进入前摇；demo_surround = 每这么多秒把最近 4 只怪拉到队长身边。只在图鉴演示里生效
func _growth_demo(dt: float) -> void:
	if g.ch == null:
		return
	var gl: Dictionary = g.ch.def.get("gallery", {})
	if gl.has("demo_dash_cd"):
		g.dash_cd = maxf(g.dash_cd, float(gl.demo_dash_cd))
	if gl.has("demo_ctrl"):
		demo_ctrl_t += dt
		if demo_ctrl_t >= float(gl.demo_ctrl):
			demo_ctrl_t = 0.0
			for e in g.ch.nearest_enemies(3, 400.0, g.ppos):
				g.enemies_sys.add_cc(e, 1.5)
	if gl.has("demo_windup"):   # 每 demo_windup 秒让离队长最近的 4 只怪进入 0.6 秒前摇（德克萨斯「破绽」有东西可打断）
		demo_wind_t += dt
		if demo_wind_t >= float(gl.demo_windup):
			demo_wind_t = 0.0
			for e in g.ch.nearest_enemies(4, 400.0, g.ppos):
				e["wind"] = 0.6
	if gl.has("demo_surround"):   # 每 demo_surround 秒把最近 4 只怪拉到队长身边一圈（能天使「护航射击」有被围的条件）
		demo_surr_t += dt
		if demo_surr_t >= float(gl.demo_surround):
			demo_surr_t = 0.0
			var k := 0
			for e in g.ch.nearest_enemies(4, 600.0, g.ppos):
				e.pos = g.ppos + Vector2.from_angle(0.6 + float(k) * 0.9) * 100.0
				k += 1


func _contact_cycle() -> void:
	for e in g.enemies:
		if e.dead or e.boss or g.t < float(e.get("demo_bite", 0.0)):
			continue
		var off: Vector2 = e.pos - g.ppos
		var d: float = off.length()
		if d >= e.r + 12.0:
			continue
		e["demo_bite"] = g.t + DEMO_BITE_CD
		e.atk_until = g.t + 0.25
		g.enemies_sys.apply_kb(e, (off / d if d > 0.5 else Vector2.RIGHT) * DEMO_BITE_KB)


## 演示走位（2026-09-26 用户定的简单方案，替代「走走停停 + 后退 + 保持间距」：那几条规则互相打架，主控来回抽）：
## 主控朝身前最近的怪直走过去，进出手距离就停下出手；那只死了 / 被打飞到 WALK_SLACK 以外再走向下一只。不后退、不绕。
## 出手距离：近战 = 贴身（怪半径 + 40），远程 = JSON range 的 0.7（至多 230，开场多半已经够得着，站着打）。
## 只挑身前（右边、不比主控靠左 20 以上）的怪，怪一直在主控右边，出手时就不会左右翻身；朝向照常跟移动方向
func wander() -> Vector2:
	if g.demo_origin == Vector2.INF or g.ch == null:
		return Vector2.ZERO
	if g.ch.acting() and g.ch.act_kind == "skill":
		skill_hold = 1.0
	if skill_hold > 0.0:
		skill_hold -= g.get_process_delta_time()
		charging = false
		return Vector2.ZERO
	var best: Dictionary = {}
	var bd := 99999.0
	for e in g.enemies:
		if e.dead or e.pos.x < g.ppos.x - 20.0:
			continue
		var d: float = g.ppos.distance_to(e.pos)
		if d < bd:
			bd = d
			best = e
	if best.is_empty():
		charging = false
		return Vector2.ZERO
	var stop: float = best.r + 40.0 if g.ch.range_cls() == "近战" else minf(float(g.ch.def.get("range", 260.0)) * 0.7, 230.0)
	# 带召唤物的干员（凯尔希的 Mon3tr 只追主控 190 以内的敌人）：主控站远了，杀完一只下一只就出了牵引范围，
	# Mon3tr 会跑回来发呆（2026-09-27 用户：图鉴里 Mon3tr 展示有点呆）。往前站到离怪 110，让它一直有目标可追
	if "m" in g.ch:
		stop = minf(stop, 110.0)
	if charging:
		charge_t += g.get_process_delta_time()
		charging = bd > stop or (charge_t < WALK_MIN_T and bd > best.r + 24.0)
	elif bd > stop + WALK_SLACK:
		charging = true
		charge_t = 0.0
	if not charging:
		return Vector2.ZERO
	var dv: Vector2 = best.pos - g.ppos
	if g.ppos.x > g.demo_origin.x + WALK_MAX_X and dv.x > 0.0:
		dv.x = 0.0
	if dv.length() < 1.0:
		return Vector2.ZERO
	return dv.normalized() * WALK_MV


## 终结技段：技能全部压住；充满能量按 Q（随即松开 = 自动瞄准，ult.gd auto_aim），演出（ult.phase / playing）结束后停 DEMO_HOLD 秒重开这一段
func _ult_step(dt: float) -> void:
	for i in 3:
		if not g.ch.perm[i]:
			g.ch.sp[i] = 0.0
	var u = g.ult
	if u == null:
		return
	if demo_cast_t < 0.0:
		if demo_ph_t >= DEMO_FILL_AT:
			u.cells = 0
			u.energy = u.FULL
			if u.press_q():
				u.release_q()
				demo_cast_t = 0.0
	else:
		demo_cast_t += dt
	var busy: bool = u.phase != "" or u.playing()
	demo_after_t = 0.0 if busy or demo_cast_t < 0.0 else demo_after_t + dt
	if (demo_cast_t >= 0.0 and demo_after_t >= DEMO_HOLD) or demo_ph_t >= DEMO_MAX_LINGER:
		next_phase()
		return
	var alive := 0
	for e in g.enemies:
		if not e.dead:
			alive += 1
	if alive < 4:
		horde(10)


## 图鉴手动切换（gallery.gd 点击调用）：stage 0 精零（N1 N2 后）/ 1 精一（N5 后）/ 2 精二；
## mode -1 轮播已解锁的技能 / 0–2 只放该技能 / 3 只普攻 / ULT 只放终结技。立即重置场地与干员
func configure(stage: int, mode: int) -> void:
	g.demo_stage = clampi(stage, 0, 2)
	g.demo_basic = mode == 3
	demo_skill = mode if (mode >= 0 and mode <= 2) or mode == ULT else -1
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
	charging = false
	skill_hold = 0.0
	# 每段从干净的场地开始，不继承上一段的任何东西（用户要求）：怪、弹幕、特效、飘字、预警、溟痕、掉落、博士位置、朝向
	g.enemies.clear()
	g.bullets.clear()
	g.ebullets.clear()
	g.lobs.clear()
	g.shocks.clear()
	g.warns.clear()
	g.mires.clear()
	g.gems.clear()
	g.fx.clear()
	g.texts.clear()
	g.hitstop = 0.0
	g.dash_t = 0.0
	g.doc_pos = Vector2.INF
	g.ppos = g.demo_origin + Vector2(DEMO_OP_DX, 10 + DEMO_DY)
	new_op()
	# 推成长节点到精英化时，新解锁的技能会被充满（character.gd 解锁即满）：重建后同一帧就会放出最高的技能，
	# 每段开头都先来一发三技能。这里全部清零，本段的技能由 step 在 DEMO_FILL_AT 时替它充满
	for i in 3:
		if not g.ch.perm[i]:
			g.ch.sp[i] = 0.0
	demo_filled = false
	demo_after_t = 0.0
	horde(DEMO_HORDE)
	var si: int = g.demo_phases[g.demo_pi]
	if si == ULT:
		g.demo_label = "终结技"
		if g.ult != null:
			g.ult.energy = 0.0
			g.ult.cells = 0
		var un: String = str(Ult.text_table().get("ops", {}).get(str(g.ch.id), {}).get("ult", {}).get("name", ""))
		if un != "":
			g.demo_label = "终结技「%s」" % un
		return
	g.demo_label = "普攻「%s」" % g.ch.attack_def().get("name", "") if g.demo_basic else "%s技能「%s」" % [["一", "二", "三"][si], g.ch.skill_def(si).get("name", "")]


## 重新生成演示干员：清掉旧实例挂在 op:<id> 作用域上的全部修正，再按演示要求推到精英化阶段
func new_op() -> void:
	var id: String = g.demo_op
	if g.ch != null and g.squad.has(id):
		g.squad.remove(id)
	for m in g.squad.ops.duplicate():   # 上一段的演示队友
		if m.id != id:
			g.squad.remove(m.id)
			g.stats.remove_scope("op:" + m.id)
	g.stats.remove_scope("op:" + id)
	g.sync_stats()
	g.ch = g.squad.add(id)   # 图鉴演示直接出现，不播登场条（10-22 用户；局内入场仍播 play_entry）
	if g.demo_stage >= 0:
		# 三联对照：按成长节点数推进（N1 N2 → 2 个；到 N5 → 5 个；全部 → 6 个）
		var nodes: int = g.demo_nodes if g.demo_nodes >= 0 else [2, 5, 6][clampi(g.demo_stage, 0, 2)]
		for k in nodes:
			if g.ch.next_node().is_empty():
				break
			var n0: Dictionary = g.ch.next_node()
			var chs0: Dictionary = g.ch.elite_choices(n0) if n0.get("type", "") == "elite" else {}
			g.ch.advance(chs0.keys()[0] if not chs0.is_empty() else "")
		g.show_queue.clear()
		g.facing = 1.0
		g.ch.pos = g.ppos
		_add_demo_mate()
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
	_add_demo_mate()


## 演示队友（干员 JSON gallery.demo_mate = {"op": 干员 id, "elite": 起始精英阶段}）：本干员到了这个精英阶段才带上一名队友，
## 给「赋予队友」类的效果一个对象（能天使精二「天使的祝福」光环 / 金光）。队友只普攻（step 压住技力），不推成长节点
func _add_demo_mate() -> void:
	var dm = g.ch.def.get("gallery", {}).get("demo_mate", null)
	if not (dm is Dictionary) or g.ch.elite < int(dm.get("elite", 2)):
		return
	var mid: String = str(dm.get("op", ""))
	if mid == "" or mid == g.demo_op or g.squad.has(mid):
		return
	var m = g.squad.add(mid)
	if m != null:
		m.pos = g.ppos + g.squad._slot_offset(m.slot)
		for i in 3:
			m.sp[i] = 0.0


## 右边刷一片怪海：椭圆区域里随机撒开，慢慢向主控推进（演示里敌人不造成伤害）
func horde(n: int) -> void:
	for k in n:
		var a: float = g.rng.randf() * TAU
		var r: float = sqrt(g.rng.randf())
		# 前排离主控约 140（近战干员的前压范围 150 以内），一开场就能接敌
		var p: Vector2 = g.demo_origin + Vector2(DEMO_HORDE_DX + cos(a) * r * 90.0, DEMO_DY + sin(a) * r * 72.0)
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
