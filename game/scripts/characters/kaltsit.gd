## 凯尔希（医疗，契约 v2.1）：周期治疗博士（与骑士同伴）；Mon3tr 作为近身输出单位，撕咬博士身边的敌人。
## S1 医疗单元：立即治疗 + 清神经损伤；S2 战术协同（永久型）：充能一次后 Mon3tr 攻速 / 范围与治疗频率永久提升；S3 熔毁：Mon3tr 真伤，结束时熔毁爆炸。
## Mon3tr 是本干员的附属实体（64×64 帧条，脚底 (32, 60)），自己寻敌、自己播动画，通过 extra_bodies 参与 2.5D 排序。
## 特效（docs/25，2026-09-26 照原作截图修改）：荧光绿。普通爪击三道平行爪痕、协同后双爪爪痕；
## 熔毁期间 Mon3tr 染猩红、周身红雾红光、每爪一道巨大猩红月牙斩；熔毁结束绿色八面体晶核碎裂，迸出空心方形晶片 + 黑色碎片 + 放射光束。
extends "res://scripts/characters/character.gd"

const GREEN := Color(0.55, 1.0, 0.5)
const CRIMSON := Color(1.0, 0.12, 0.16)   # 熔毁（照原作：Mon3tr 整体变猩红）
const M_LEASH := 190.0        # Mon3tr 离博士的最远距离
const M_REACH := 62.0         # 爪击半径（基础）
const S3_DUR := 8.0

var cd := 1.0
var guard_t := 0.0            # 溢出治疗后博士减伤的剩余时间
# ---- Mon3tr
var m := {"pos": Vector2.INF, "face": 1.0, "mv": 0.0, "kind": "idle", "at": 0.0, "act": 0.0, "fire": -1.0, "cd": 0.8, "tgt": null}
var coord := false            # S2 战术协同（永久）
var melt := 0.0               # S3 熔毁剩余
var glow_t := 0.0
var ghost := {}               # 残影：{pos, face, kind, at, t}
var m_swing := 1.0            # 月牙斩方向（上下交替）
# ---- 可见成长（docs/25 §5：原作八面晶体展开四爪 / S1 结构加固 / 天赋不毁重构 / S2 攻击所有阻挡）
var twin_claw := false        # N1「骨爪增生」：每次爪击两爪（第二爪 0.08 秒后、60%，交叉爪痕）
var wide_arc := false         # N2「清创」：爪击扇面 +40%
var s1_shell := false         # N4「结构加固」：医疗单元附带 3 秒减伤护壳
var melt_triple := false      # N5「不毁重构」：熔毁收尾三连爆并眩晕
var dual_side := false        # 精二「八面展开」：Mon3tr 前后同时出爪
var shell_t := 0.0            # 结构加固护壳剩余
var m_pend: Array = []        # 延迟的第二爪：{t, mult}
var melt_echo: Array = []     # 不毁重构的后续爆炸：{t, pos, r, dmg}


func _heal_mult() -> float:
	return stat(&"op_atk") * g.ally_mult * (1.5 if elite >= 1 else 1.0)


func _boosted() -> bool:
	return melt > 0.0


## 成长节点（data/characters/kaltsit.json 的 custom 节点）
func on_custom_node(nid: String, _choice: String = "") -> void:
	match nid:
		"twin_claw":
			twin_claw = true
		"wide_arc":
			wide_arc = true
		"s1_shell":
			s1_shell = true
		"melt_triple":
			melt_triple = true


func on_elite(stage: int, _choice: String = "") -> void:
	if stage >= 2:
		dual_side = true


func update(dt: float) -> void:
	cd -= dt
	guard_t = maxf(0.0, guard_t - dt)
	shell_t = maxf(0.0, shell_t - dt)
	if melt > 0.0:
		melt -= dt
		if melt <= 0.0:
			_meltdown()
	for me in melt_echo:
		me.t -= dt
		if me.t <= 0.0:
			_melt_burst(me.pos, me.r, me.dmg, false)
	melt_echo = melt_echo.filter(func(me): return me.t > 0.0)
	_update_mon3tr(dt)
	if acting():
		return
	var ready := charge_skills(dt)
	if ready >= 0:
		start_skill(m.pos if m.pos != Vector2.INF else g.ppos, ready)
		return
	if cd <= 0.0:
		cd = base("heal_cd", 3.5) / stat(&"op_aspd") / (1.3 if coord else 1.0)
		if g.hp < g.max_hp or (g.knight.alive and g.knight.hp < g.knight.maxhp):
			start_attack(g.ppos)


func _release() -> void:
	if g.knight.alive:
		g.knight.heal(g.knight.maxhp * 0.05)
	if g.hp < g.max_hp:
		_heal(g.max_hp * base("heal_pct", 0.035) * _heal_mult(), 16)


func _heal(h: float, size: int) -> void:
	var over: float = maxf(0.0, g.hp + h - g.max_hp)
	g._heal(h, "凯尔希")
	Sfx.op(id, "heal")
	if over > 0.0:
		guard_t = 5.0
	g._add_text(g.ppos + Vector2(0, -90), "+%d" % int(h), GREEN, size)
	fx({"kind": "ring", "pos": g.ppos, "r": 30.0, "r0": 8.0, "life": 0.4, "col": GREEN, "floor": true})
	# 治疗光环（Ninja Adventure Aura 调绿）+ 星光命中（Pimen，染绿）
	if not g._fx_sprite("fx_heal_aura_green", g.ppos + Vector2(0, 6), g.PX * 1.3, 0.0, false, true):
		for k in 6:
			g.fx.append({"kind": "cross", "pos": g.ppos + Vector2(randf_range(-22, 22), randf_range(-50, -5)), "life": 0.9, "max": 0.9,
				"delay": k * 0.08, "sz": randf_range(3.0, 5.0)})
	g._fx_sprite("fx_holy_impact", g.ppos + Vector2(0, -34), g.PX * 0.9, 0.0, false, false, Color(0.75, 1.3, 0.8))
	g.fx.append({"kind": "beam", "a": pos + Vector2(0, -24), "b": g.ppos + Vector2(0, -24), "life": 0.3, "max": 0.3, "col": GREEN, "w": 3.0})
	fx({"kind": "glow", "pos": pos + Vector2(8.0 * face, -26), "r": 10.0, "life": 0.25, "col": GREEN, "alpha": 0.5})


func _release_skill() -> void:
	match cur_skill:
		0:
			_heal(g.max_hp * base("s1_heal", 0.08) * _heal_mult() * skill_power(), 18)
			g.nerve = 0.0
			fx({"kind": "ring", "pos": pos, "r": 44.0, "r0": 6.0, "life": 0.45, "col": GREEN, "floor": true})
			# N4「结构加固」：主控身上罩一层绿色六边形护壳，受到的伤害 -35%
			if s1_shell:
				shell_t = base("shell_dur", 3.0)
				fx({"kind": "ring", "pos": g.ppos + Vector2(0, -22), "r": 40.0, "r0": 12.0, "life": 0.35, "col": Color(0.7, 1.6, 0.8), "w": 2.5})
		1:
			coord = true
			_mon3tr_burst()
			g._show_banner("战术协同：Mon3tr 永久强化")
		2:
			melt = S3_DUR
			_mon3tr_burst()
			g._add_text(m.pos + Vector2(0, -70), "熔毁", CRIMSON, 16)


func _mon3tr_burst() -> void:
	if m.pos == Vector2.INF:
		return
	g.fx.append({"kind": "rays", "pos": m.pos + Vector2(0, -30), "life": 0.5, "max": 0.5, "col": GREEN})
	g.fx.append({"kind": "beam", "a": pos + Vector2(0, -26), "b": m.pos + Vector2(0, -30), "life": 0.35, "max": 0.35, "col": GREEN, "w": 3.0})
	fx({"kind": "glow", "pos": m.pos + Vector2(0, -28), "r": 34.0, "life": 0.35, "col": GREEN, "alpha": 0.5})


func skill_active_left(i: int) -> float:
	return melt if i == 2 else 0.0


func skill_active_dur(i: int) -> float:
	return S3_DUR if i == 2 else 1.0


# ---------------------------------------------------------------- Mon3tr

## 基础数值全部可由 data/characters/kaltsit.json 的 base 段覆盖（docs/27 §3）
func _m_dmg() -> float:
	return base("m_atk", 22.0) * _dmg_bonus() * (1.3 if elite >= 1 else 1.0) * (base("s3_mult", 1.6) * skill_power() if melt > 0.0 else 1.0)


func _m_reach() -> float:
	return base("m_reach", M_REACH) * stat(&"op_range") * (1.2 if elite >= 1 else 1.0) * (1.3 if coord else 1.0)


func _update_mon3tr(dt: float) -> void:
	if m.pos == Vector2.INF or m.pos.distance_to(g.ppos) > 700.0:
		m.pos = pos + Vector2(-30.0 * face, 10)
	if _boosted():
		glow_t -= dt
		if glow_t <= 0.0:
			glow_t = 0.07
			if melt > 0.0:
				# 熔毁：周身红雾团 + 红色飞线
				fx({"kind": "glow", "pos": m.pos + Vector2(g.rng.randf_range(-26, 26), g.rng.randf_range(-46, -4)), "r": g.rng.randf_range(10.0, 18.0), "life": 0.5, "col": CRIMSON, "alpha": 0.3})
				fx({"kind": "line", "pos": m.pos + Vector2(g.rng.randf_range(-30, 30), g.rng.randf_range(-44, 0)), "to": m.pos + Vector2(g.rng.randf_range(-50, 50), g.rng.randf_range(-70, -10)), "life": 0.15, "col": CRIMSON, "w": 1.5})
			else:
				fx({"kind": "mote", "pos": m.pos + Vector2(g.rng.randf_range(-22, 22), g.rng.randf_range(-40, 0)), "vel": Vector2(0, -50), "life": 0.5, "col": GREEN, "sz": 2.0})
		if ghost.is_empty() or ghost.t <= 0.0:
			ghost = {"pos": m.pos, "face": m.face, "kind": m.kind, "at": m.at, "t": 0.12}
		else:
			ghost.t -= dt
	else:
		ghost = {}
	# 目标：博士 leash 范围内离 Mon3tr 最近的敌人；没有就回到凯尔希身边
	var tg = m.tgt
	if tg == null or tg.dead or tg.pos.distance_to(g.ppos) > M_LEASH + 40.0:
		var ts: Array = g._nearest(1, M_LEASH, g.ppos)
		tg = ts[0] if not ts.is_empty() else null
		m.tgt = tg
	var want: Vector2 = pos + Vector2(-34.0 * face, 14)
	if tg != null:
		var off: Vector2 = m.pos - tg.pos
		want = tg.pos + (off.normalized() if off.length() > 1.0 else Vector2(-m.face, 0)) * (tg.r + 26.0)
	var prev: Vector2 = m.pos
	if m.act <= 0.0:
		var spd: float = 260.0 * (1.3 if _boosted() else 1.0)
		var d: Vector2 = want - m.pos
		m.pos += d.normalized() * minf(d.length(), spd * dt)
		if g.tex.get("prop_pillar") != null:
			m.pos = g.map.push_out(m.pos, 14.0)
	var vel: Vector2 = (m.pos - prev) / maxf(dt, 0.0001)
	m.mv = lerpf(m.mv, vel.length(), clampf(dt * 10.0, 0.0, 1.0))
	if absf(vel.x) > 20.0 and m.act <= 0.0:
		m.face = signf(vel.x)
	# 爪击
	m.cd -= dt * (1.4 if coord else 1.0)
	for pc in m_pend:
		pc.t -= dt
		if pc.t <= 0.0:
			_m_claw(pc.mult, true)
	m_pend = m_pend.filter(func(pc): return pc.t > 0.0)
	if m.act > 0.0:
		m.act -= dt
		if m.fire >= 0.0:
			m.fire -= dt
			if m.fire < 0.0:
				m.fire = -1.0
				_m_strike()
	elif tg != null and m.cd <= 0.0 and m.pos.distance_to(tg.pos) < tg.r + _m_reach():
		m.cd = base("m_cd", 0.9) / stat(&"op_aspd")
		m.face = signf(tg.pos.x - m.pos.x) if absf(tg.pos.x - m.pos.x) > 2.0 else m.face
		var spec := sprite_spec("m_attack")
		var fps: float = float(spec.get("fps", 14))
		m.act = float(spec.get("frames", 4)) / fps
		m.fire = (float(spec.get("fire", 2)) + 0.5) / fps
		_m_set_kind("attack")
	var k: String = "attack" if m.act > 0.0 else ("run" if m.mv > 30.0 else "idle")
	_m_set_kind(k)
	m.at += dt


func _m_set_kind(k: String) -> void:
	if m.kind != k:
		m.kind = k
		m.at = 0.0


func _m_strike() -> void:
	if melt > 0.0:
		m_swing = -m_swing
	_m_claw(1.0, false)
	# N1「骨爪增生」：0.08 秒后第二爪（60%），爪痕与第一爪交叉
	if twin_claw:
		m_pend.append({"t": base("claw2_delay", 0.08), "mult": base("claw2_mult", 0.6)})


## 一次爪击：朝 Mon3tr 面向挥爪；精二「八面展开」时同时向身后镜像出爪（背后一爪 70%）。
## second：N1 的第二爪（爪痕旋转交叉、月牙反向扫）
func _m_claw(mult: float, second: bool) -> void:
	var fwd: float = 0.0 if m.face >= 0.0 else PI
	var o: Vector2 = m.pos + Vector2(0, -14)
	var half: float = base("m_arc", 1.3) * (base("m_arc_wide", 1.4) if wide_arc else 1.0)
	var dirs: Array = [fwd, fwd + PI] if dual_side else [fwd]
	var any := false
	for i in dirs.size():
		var ang: float = dirs[i]
		var sd: float = 1.0 if cos(ang) >= 0.0 else -1.0   # 这一爪朝向的左右
		var dmg: float = _m_dmg() * mult * (1.0 if i == 0 else base("m_back_mult", 0.7))
		var hits := melee_hit("Mon3tr · 真伤" if melt > 0.0 else "Mon3tr", m.pos + Vector2(0, -10), ang, half, _m_reach() + 16.0, dmg, 120.0)
		any = any or not hits.is_empty()
		if melt > 0.0:
			# 照原作：熔毁期间一整道巨大的猩红月牙斩；方向上下交替，像两只爪轮流挥（第二爪反向扫，交叉成 X）
			var sw: float = -m_swing if second else m_swing
			var R: float = _m_reach() * 1.25
			fx({"kind": "crescent", "pos": o + Vector2(-10.0 * sd, 0), "ang": ang, "r": R, "w": 22.0 * (0.8 if second else 1.0),
				"sweep": 2.3, "dir": sw * sd, "life": 0.26, "col": CRIMSON})
			fx({"kind": "crescent", "pos": o + Vector2(-10.0 * sd, 0), "ang": ang, "r": R * 0.72, "w": 10.0, "sweep": 1.8, "dir": sw * sd, "life": 0.2, "col": Color(1.0, 0.45, 0.4)})
			var hp: Vector2 = o + Vector2.from_angle(ang) * R * 0.75
			fx({"kind": "impact", "pos": hp, "r": 20.0, "life": 0.14, "col": CRIMSON})
			fx_sparks(hp, Color(1.6, 0.4, 0.4), 7, 240.0, 0.28, 2.5)
		else:
			# 平行爪痕帧条（Ninja Adventure Claw 调绿；协同后用双爪，用户确认保留爪痕）；没有帧条时退回程序画的三道爪痕
			# 第二爪：爪痕旋转约 60°，与第一爪交叉
			var rot: float = (1.05 * sd) if second else 0.0
			var cp: Vector2 = o + Vector2.from_angle(ang) * (_m_reach() * 0.55)
			var sc: float = g.PX * clampf(_m_reach() / 40.0, 1.2, 2.2) * (0.9 if second else 1.0)
			if not g._fx_sprite("fx_claw_double_green" if coord else "fx_claw_green", cp, sc, rot, sd < 0.0):
				fx({"kind": "claw", "pos": o + Vector2.from_angle(ang) * 10.0, "ang": ang + rot, "len": _m_reach() + 10.0, "life": 0.25, "col": GREEN})
			fx_sparks(o + Vector2.from_angle(ang) * _m_reach() * 0.6, GREEN, 5, 160.0, 0.3, 2.5)
			# N2「清创」：更宽的扇面用一道淡绿细月牙画出来
			if wide_arc and not second:
				fx({"kind": "crescent", "pos": o, "ang": ang, "r": _m_reach() + 8.0, "w": 5.0, "sweep": half * 2.0, "dir": sd, "life": 0.2, "col": Color(0.5, 1.1, 0.55)})
	if any:
		Sfx.op(id, "atk", 2.0 if melt > 0.0 else 0.0, (0.85 if melt > 0.0 else 1.0) * (1.15 if second else 1.0))


func _hit_fx(e: Dictionary, _origin: Vector2) -> void:
	fx({"kind": "glow", "pos": e.pos + Vector2(0, -e.r * 0.5), "r": 10.0, "life": 0.18, "col": CRIMSON if melt > 0.0 else GREEN, "alpha": 0.55})


func _meltdown() -> void:
	var r := 130.0
	var dmg: float = base("m_atk", 22.0) * base("melt_mult", 5.0) * _dmg_bonus() * skill_power()
	_melt_burst(m.pos, r, dmg, true)
	# N5「不毁重构」：再接两次更大的爆炸（间隔 0.2 秒，半径 ×1.25 / ×1.5，伤害 50%）
	if melt_triple:
		for k in 2:
			melt_echo.append({"t": base("melt_echo_gap", 0.2) * (k + 1), "pos": m.pos, "r": r * (1.25 + 0.25 * k), "dmg": dmg * base("melt_echo_mult", 0.5)})


## 熔毁爆炸（main：第一次，带晶核碎裂全套特效；后续爆炸只有光束 + 晶片 + 地面环）。
## 不毁重构后每次都眩晕 1.5 秒（精英减半、Boss 免疫，由 melee_hit 处理）
func _melt_burst(at: Vector2, r: float, dmg: float, main: bool) -> void:
	var stun: float = base("melt_stun", 1.5) if melt_triple else 0.5
	area_hit("Mon3tr · 熔毁", at, r, dmg, 260.0 if main else 160.0, stun)
	if not main:
		var c2: Vector2 = at + Vector2(0, -24)
		fx({"kind": "glow", "pos": c2, "r": 40.0, "life": 0.25, "col": Color(1.2, 2.2, 1.0), "alpha": 0.5})
		for i in 8:
			fx({"kind": "beamray", "pos": c2, "ang": TAU * i / 8.0 + g.rng.randf_range(-0.3, 0.3), "len": r * g.rng.randf_range(0.8, 1.1), "life": 0.3, "col": GREEN})
		for i in 6:
			var v3: Vector2 = Vector2.from_angle(g.rng.randf() * TAU) * g.rng.randf_range(160, 340)
			fx({"kind": "qshard", "pos": c2, "vel": v3, "drag": 2.2, "life": 0.5, "sz": g.rng.randf_range(5.0, 9.0), "ang": g.rng.randf() * TAU, "spin": g.rng.randf_range(-9, 9)})
		fx({"kind": "ring", "pos": at, "r": r, "r0": r * 0.5, "life": 0.4, "col": GREEN, "floor": true, "w": 3.0})
		Sfx.op(id, "big", -4.0, 1.15)
		return
	# 照原作：绿色八面体晶核亮起胀大后碎裂 → 空心方形晶片 + 黑色碎片四散、放射光束、大量绿色光点
	var c: Vector2 = at + Vector2(0, -24)
	fx({"kind": "glow", "pos": c, "r": 60.0, "life": 0.3, "col": Color(1.2, 2.2, 1.0), "alpha": 0.7})
	fx({"kind": "core", "pos": c, "r": 26.0, "life": 0.4})
	for i in 10:
		var ba: float = TAU * i / 10.0 + g.rng.randf_range(-0.2, 0.2)
		fx({"kind": "beamray", "pos": c, "ang": ba, "len": r * g.rng.randf_range(0.8, 1.3), "life": 0.35, "col": GREEN})
	for i in 14:
		var v: Vector2 = Vector2.from_angle(g.rng.randf() * TAU) * g.rng.randf_range(120, 320)
		fx({"kind": "qshard", "pos": c, "vel": v, "drag": 2.2, "life": g.rng.randf_range(0.5, 0.8), "sz": g.rng.randf_range(5.0, 11.0), "ang": g.rng.randf() * TAU, "spin": g.rng.randf_range(-9, 9)})
	for i in 10:
		var v2: Vector2 = Vector2.from_angle(g.rng.randf() * TAU) * g.rng.randf_range(100, 260)
		fx({"kind": "shard", "pos": c, "vel": v2, "drag": 2.0, "life": 0.5, "col": Color(0.03, 0.05, 0.04), "sz": g.rng.randf_range(4.0, 7.0), "ang": v2.angle(), "spin": 10.0})
	for i in 24:
		fx({"kind": "mote", "pos": c + Vector2(g.rng.randf_range(-r, r), g.rng.randf_range(-r, r) * 0.6), "vel": Vector2(g.rng.randf_range(-30, 30), g.rng.randf_range(-70, -20)), "life": g.rng.randf_range(0.5, 0.9), "col": GREEN, "sz": g.rng.randf_range(1.5, 3.0)})
	fx({"kind": "ring", "pos": at, "r": r, "r0": 12.0, "life": 0.4, "col": GREEN, "floor": true, "w": 3.0})
	g.hitstop = maxf(g.hitstop, 0.1)
	g._add_text(at + Vector2(0, -70), "熔毁", GREEN, 18)
	Sfx.op(id, "big")


func _draw_pfx(f: Dictionary, a: float) -> bool:
	var P := func(v: Vector2) -> Vector2: return (v / 2.0).round() * 2.0
	match f.kind:
		"crescent":
			# 宽月牙：以 pos 为圆心、ang 为中线扫过 sweep 弧度；前 40% 从起点扫到终点，中间最厚两头尖；本色填充 + 白亮外缘
			var u: float = 1.0 - a
			var rev: float = minf(1.0, u / 0.4)
			var half: float = f.sweep * 0.5
			var a0: float = f.ang - half * f.dir
			var a1: float = a0 + f.sweep * rev * f.dir
			var n := 16
			var outer := PackedVector2Array()
			var inner := PackedVector2Array()
			var edge := PackedVector2Array()
			for i in n + 1:
				var t: float = float(i) / n
				var an: float = lerpf(a0, a1, t)
				var th: float = f.w * sin(t * PI) * (1.0 - 0.5 * maxf(0.0, u - 0.4) / 0.6)
				var dv: Vector2 = Vector2.from_angle(an)
				var sq := Vector2(1.0, 0.8)
				outer.append(P.call(f.pos + dv * (f.r + th * 0.5) * sq))
				inner.append(P.call(f.pos + dv * (f.r - th * 0.5) * sq))
				edge.append(P.call(f.pos + dv * (f.r + th * 0.35) * sq))
			var c: Color = f.col
			if outer[0].distance_to(outer[outer.size() - 1]) > 4.0:
				for i in n:
					var q := PackedVector2Array([outer[i], outer[i + 1], inner[i + 1], inner[i]])
					if absf((q[1] - q[0]).cross(q[3] - q[0])) + absf((q[2] - q[1]).cross(q[3] - q[1])) > 2.0:
						g.draw_colored_polygon(q, Color(c.r * 1.3, c.g * 1.3, c.b * 1.3, 0.75 * a))
				g.draw_polyline(edge, Color(2.0, 2.0, 1.9, 0.9 * a), 2.0)
			return true
		"impact":
			# 命中闪光：白亮核心 + 光晕 + 四道星芒
			var k: float = 1.0 - a
			var L: float = f.r * (0.6 + 0.8 * k)
			var c2: Color = f.col
			g.draw_circle(f.pos, f.r * (0.9 + 0.4 * k), Color(c2.r * 1.5, c2.g * 1.5, c2.b * 1.5, 0.35 * a))
			g.draw_circle(f.pos, f.r * 0.7 * a + 2.0, Color(2.4, 2.4, 2.2, a))
			for q in 4:
				var dv2 := Vector2.from_angle(q * PI / 4.0)
				var ll: float = L * (1.0 if q % 2 == 0 else 0.6)
				g.draw_line(f.pos - dv2 * ll, f.pos + dv2 * ll, Color(2.2, 2.2, 2.0, a), 2.0)
			return true
		"core":
			# 熔毁晶核：绿色八面体（菱形 + 亮面），先胀大变亮，后半程碎掉消失
			var k3: float = 1.0 - a
			var sc: float = 0.6 + 0.8 * minf(1.0, k3 * 2.5)
			var al: float = 1.0 if k3 < 0.55 else maxf(0.0, 1.0 - (k3 - 0.55) / 0.45)
			var R: float = f.r * sc
			var top: Vector2 = f.pos + Vector2(0, -R * 1.3)
			var bot: Vector2 = f.pos + Vector2(0, R * 1.3)
			var lft: Vector2 = f.pos + Vector2(-R, 0)
			var rgt: Vector2 = f.pos + Vector2(R, 0)
			var mid: Vector2 = f.pos + Vector2(R * 0.25, -R * 0.1)
			g.draw_circle(f.pos, R * 1.8, Color(0.8, 2.0, 0.7, 0.25 * al))
			g.draw_colored_polygon(PackedVector2Array([top, rgt, bot, lft]), Color(0.5, 1.6, 0.45, 0.85 * al))
			g.draw_colored_polygon(PackedVector2Array([top, mid, bot, lft]), Color(1.0, 2.2, 0.9, 0.9 * al))
			g.draw_polyline(PackedVector2Array([top, rgt, bot, lft, top]), Color(2.0, 2.4, 1.8, al), 2.0)
			return true
		"qshard":
			# 空心方形晶片：旋转的绿色方框，亮边 + 淡填充
			var hs: float = f.sz * 0.5
			var r0: Vector2 = Vector2.from_angle(f.get("ang", 0.0)) * hs * 1.414
			var r1: Vector2 = r0.orthogonal()
			var pts := PackedVector2Array([f.pos + r0, f.pos + r1, f.pos - r0, f.pos - r1, f.pos + r0])
			g.draw_colored_polygon(pts.slice(0, 4), Color(0.6, 1.6, 0.5, 0.25 * a))
			g.draw_polyline(pts, Color(1.0, 2.2, 0.7, a), 2.0)
			return true
		"beamray":
			# 放射光束：从核心向外迅速伸出、变细消失
			var k4: float = 1.0 - a
			var dv3: Vector2 = Vector2.from_angle(f.ang)
			var L2: float = f.len * minf(1.0, k4 * 3.0)
			g.draw_line(f.pos + dv3 * 10.0, f.pos + dv3 * L2, Color(f.col.r * 1.4, f.col.g * 1.6, f.col.b * 1.3, 0.6 * a), 3.0 * a + 1.0)
			return true
	if f.kind == "claw":
		# 三道平行爪痕：略弧，随时间拉长、变细、淡出
		var d := Vector2.from_angle(f.ang)
		var nrm := d.orthogonal()
		var l: float = f.len * (0.5 + 0.5 * (1.0 - a))
		for i in 3:
			var off: Vector2 = nrm * (float(i) - 1.0) * 8.0
			var p0: Vector2 = f.pos + off - d * 4.0 * float(i)
			var mid: Vector2 = p0 + d * l * 0.5 + nrm * 3.0 * (1.0 if i != 1 else -1.0)
			var p1: Vector2 = p0 + d * l
			g.draw_polyline(PackedVector2Array([p0, mid, p1]), Color(GREEN.r * 1.8, GREEN.g * 1.8, GREEN.b * 1.6, a), 3.0 * a + 1.0)
		return true
	return false


func extra_bodies() -> Array:
	if m.pos == Vector2.INF:
		return []
	return [{"y": m.pos.y + 4.0}]


func _m_frame(kind: String, at: float) -> Array:
	var tx: Texture2D = anim_tex("m_" + kind)
	if tx == null:
		return []
	var n: int = anim_hframes(tx, "m_" + kind)
	var fr: int
	if kind == "attack":
		fr = clampi(int(at * float(sprite_spec("m_attack").get("fps", 14))), 0, n - 1)
	else:
		fr = int(at * float(sprite_spec("m_" + kind).get("fps", 4))) % n
	return [tx, fr, n]


func draw_extra(_it: Dictionary) -> void:
	var fr := _m_frame(m.kind, m.at)
	if fr.is_empty():
		g.draw_circle(m.pos + Vector2(0, -14), 14.0, Color(0.3, 0.4, 0.3))
		return
	if _boosted():
		# 残影 + 周身脉冲环（熔毁期间更亮）
		if not ghost.is_empty() and ghost.pos.distance_to(m.pos) > 3.0:
			var gf := _m_frame(ghost.kind, ghost.at)
			if not gf.is_empty():
				g._draw_sprite_at(ghost.pos, ghost.face < 0.0, Color(1.4, 0.3, 0.3, 0.4) if melt > 0.0 else Color(0.5, 1.3, 0.6, 0.35), gf[1], gf[0], gf[2], foot_off(gf[0], "m_" + ghost.kind))
		var ac: Color = CRIMSON if melt > 0.0 else GREEN
		var k: float = 0.35 + 0.15 * sin(g.t * 10.0) + (0.2 if melt > 0.0 else 0.0)
		if melt > 0.0:
			# 熔毁：身后一团红光晕
			# 熔毁：身后几团错开、缓慢翻动的半透明红雾（不是一整块红盘）
			for q in 5:
				var ph: float = g.t * 1.7 + q * 1.3
				var off := Vector2(cos(ph) * 16.0, sin(ph * 1.3) * 10.0 - 26.0)
				g.draw_circle(m.pos + off, 14.0 + 5.0 * sin(ph * 2.0), Color(1.0, 0.06, 0.1, 0.13))
		g.draw_arc(m.pos + Vector2(0, -22), 30.0 + 4.0 * sin(g.t * 10.0), 0.0, TAU, 28, Color(ac.r, ac.g, ac.b, k), 2.0)
	# 熔毁：整体染猩红（原作截图）；协同：略偏绿
	var col := Color(1.7, 0.45, 0.45) if melt > 0.0 else (Color(1.08, 1.18, 1.05) if coord else Color.WHITE)
	# 悬浮体（2026-09-25 美术改为无腿浮游）：轻微上下起伏
	g._draw_sprite_at(m.pos + Vector2(0, _hover()), m.face < 0.0, col, fr[1], fr[0], fr[2], foot_off(fr[0], "m_" + m.kind))
	_draw_claw_blades()


## 常驻爪刃（可见成长）：Mon3tr 身侧发光的月牙爪刃，数量 = 每次爪击的爪数（骨爪增生后 2 道）；
## 精二「八面展开」后身后镜像再展开一组，一眼看出前后都会出爪。熔毁期间染猩红
func _draw_claw_blades() -> void:
	var n: int = 2 if twin_claw else 1
	var sides: Array = [m.face, -m.face] if dual_side else [m.face]
	var c: Color = CRIMSON if melt > 0.0 else GREEN
	var body: Vector2 = m.pos + Vector2(0, _hover() - 26.0)
	# Codex 成长线帧条 fx_mon3tr_blade（16×24、2 帧 4fps 循环、中心锚点）：原图是「(」形朝左凸，
	# 身前 / 身后两组都让刃背朝外——朝右的一侧由程序水平镜像；熔毁时整体染猩红。缺图退回下面的程序弧
	var btx: Texture2D = A.tex("fx_mon3tr_blade")
	if btx != null:
		var bc: Color = Color(1.8, 0.35, 0.35) if melt > 0.0 else Color.WHITE
		var bf: int = int(g.t * 4.0) % 2
		for s in sides:
			for j in n:
				var bob: float = sin(g.t * 3.0 + j * 1.7 + s) * 2.5
				var bp: Vector2 = body + Vector2(s * (33.0 + 5.0 * j), -10.0 + j * 15.0 + bob)
				_strip(btx, 2, (bf + j) % 2, bp, g.PX, Vector2(8, 12), s > 0.0, bc)
		return
	for s in sides:
		var base_a: float = 0.0 if s >= 0.0 else PI
		for j in n:
			var sway: float = sin(g.t * 3.0 + j * 1.7 + s) * 0.18
			var cp: Vector2 = body + Vector2(s * (27.0 + 5.0 * j), -10.0 + j * 15.0)
			var a0: float = base_a - 0.95 + sway
			var a1: float = base_a + 0.95 + sway
			g.draw_arc(cp, 15.0, a0, a1, 12, Color(c.r, c.g, c.b, 0.22), 6.0)
			g.draw_arc(cp, 15.0, a0, a1, 12, Color(c.r * 1.7, c.g * 1.7, c.b * 1.5, 0.85), 2.0)


## 悬浮起伏（像素）：越高影子越小
func _hover() -> float:
	return -4.0 - 3.0 * sin(g.t * 2.6 + m.pos.x * 0.01)


func draw_extra_shadows() -> void:
	if m.pos != Vector2.INF:
		g._spr("shadow", 1, 0, m.pos + Vector2(0, 4), g.PX * (1.4 + 0.08 * sin(g.t * 2.6 + m.pos.x * 0.01)))


## 溢出治疗后 5 秒博士受伤 -20%；结构加固护壳期间再 -35%（game.gd _enemy_hit 查询）
func dmg_taken_mult() -> float:
	var k: float = 0.8 if guard_t > 0.0 else 1.0
	if shell_t > 0.0:
		k *= 1.0 - base("shell_red", 0.35)
	return k


## N4「结构加固」护壳：主控周身一层半透明绿色六边形，边缘描亮、缓慢自转，最后 0.5 秒闪烁淡出
func _draw_skill_over() -> void:
	if shell_t <= 0.0 or g.ppos == Vector2.INF:
		return
	var al: float = 1.0 if shell_t > 0.5 else (0.35 + 0.65 * absf(sin(shell_t * 18.0)))
	var c: Vector2 = g.ppos + Vector2(0, -22)
	# Codex 成长线帧条 fx_kaltsit_shell（48×40、4 帧 6fps 循环、中心锚点）：轮廓是二值透明，整体半透明靠 modulate（建议 0.5）；
	# 刚罩上 0.2 秒内从 0 淡入，最后 0.5 秒沿用闪烁淡出。缺图退回下面的程序六边形
	var stx: Texture2D = A.tex("fx_kaltsit_shell")
	if stx != null:
		var dur: float = base("shell_dur", 3.0)
		var fin: float = clampf((dur - shell_t) / 0.2, 0.0, 1.0)
		_strip(stx, 4, int(g.t * 6.0) % 4, c, g.PX, Vector2(24, 20), false, Color(1, 1, 1, 0.5 * al * fin))
		return
	var R: float = 34.0 + 1.5 * sin(g.t * 5.0)
	var hexp := PackedVector2Array()
	for i in 7:
		var an: float = g.t * 0.6 + i * TAU / 6.0
		hexp.append(c + Vector2(cos(an) * R, sin(an) * R * 1.12))
	g.draw_colored_polygon(hexp.slice(0, 6), Color(0.4, 1.3, 0.5, 0.13 * al))
	g.draw_polyline(hexp, Color(0.9, 2.0, 0.9, 0.7 * al), 2.0)
	# 内侧淡淡的蜂窝线：三条对角线
	for i in 3:
		g.draw_line(hexp[i], hexp[i + 3], Color(0.7, 1.7, 0.7, 0.18 * al), 1.0)


func status_items() -> Array:
	var out: Array = []
	if melt > 0.0:
		out.append(["熔毁", CRIMSON])
	if guard_t > 0.0:
		out.append(["庇护", GREEN])
	if shell_t > 0.0:
		out.append(["结构加固", GREEN])
	return out


## 画一帧横向帧条（Codex 成长线 growth_fx，双密度）：anchor_px 按 @1x 帧内像素给，sc 为 @1x 每像素的世界尺寸；
## @2x 贴图自动把倍率减半、锚点加倍（同 game.gd _spr_rot 的口径）
func _strip(tx: Texture2D, frames: int, fr: int, p: Vector2, sc: float, anchor_px: Vector2, flip := false, col := Color.WHITE) -> void:
	var hi: float = A.hires_of(tx)
	var fw: int = tx.get_width() / frames
	var fh: int = tx.get_height()
	var k: float = sc / hi
	g.draw_set_transform(p.round(), 0.0, Vector2(-k if flip else k, k))
	g.draw_texture_rect_region(tx, Rect2(-anchor_px * hi, Vector2(fw, fh)), Rect2(fw * (fr % frames), 0, fw, fh), col)
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
