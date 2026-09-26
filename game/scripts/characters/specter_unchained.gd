## 归溟幽灵鲨（特种·傀儡师，契约 v2.1，docs/26 第二批）：危机爆发 + 低灯火。贴身 360° 环斩，主控越危险她越狠。
## S1 求生之技：8 秒攻击 +（40% + 主控已损失生命%）；银蓝锯环 + 周身红色兽性气焰（与 S3 血锯区分）；
## S2 求生之渴（自动，2026-09-26 用户定）：10 秒攻速 +60%、攻击 +40%，期间主控生命不会低于 1；结束时本体倒下，替身跟随主控 12 秒后归队；
## S3 求生之压：12 秒环斩间隔 ×1.6，但每斩 ×3.2、范围 +50%，对生命 <50% 的敌人再 ×1.5；血红锯环 + 每斩地裂与顿帧。
## 天赋 拥抱自我：替身每秒对周围 120 内敌人法伤并减速；灯火 <30「昏暗」时她的伤害 +25%。
## 主控不死通过 prevent_death() 供 game.gd 询问（同 dmg_taken_mult 模式）；替身是不动的附属实体（extra_bodies）。
## 可见成长（docs/25 §5）：N1 双重回转 / N2 血色潮痕 / N4 困兽 / N5 阿戈尔挽歌 / 精二质变 无尽回旋。
extends "res://scripts/characters/character.gd"

const GHOST := Color(0.75, 0.85, 0.95)
const RED := Color(0.9, 0.3, 0.4)
const LEASH := 260.0   # 2026-09-27 用户定：近战前压加大（原 150.0）

var cd := 0.4
var s1_t := 0.0
var s2_t := 0.0
var s3_t := 0.0
var doll_t := 0.0             # 替身剩余（本体离场）
var doll_pos := Vector2.INF
var doll_tick := 0.0
var doll_at := 0.0
# ---- 可见成长（docs/25 §5：只长锯环；原作依据 贝壳状圆锯 / 替身唱阿戈尔挽歌）
var double_spin := false      # N1「双重回转」：每次环斩 0.15 秒后反向再转一圈（70%）
var blood_ring := false       # N2「血色潮痕」：环斩在地上留下一圈血色水痕，持续跳伤
var beast := false            # N4「困兽」：求生之技期间锯刃变红、半径 +50%
var elegy := false            # N5「阿戈尔挽歌」：替身唱挽歌，一圈圈水纹外扩，减速范围翻倍
var whirl_on := false         # 精二质变「无尽回旋」：每次环斩变成持续旋转
var spin2_t := -1.0           # 第二圈倒计时（<0 表示没有待转的第二圈）
var spin2_dmg := 0.0
var whirl_t := 0.0            # 持续旋转剩余
var whirl_tick := 0.0
var whirl_n := 0              # 持续旋转剩余段数
var whirl_dmg := 0.0          # 持续旋转每段伤害（本次环斩单圈伤害 × whirl_mult）
var whirl_ang := 0.0          # 旋转锯弧的相位（绘制用）
var rings: Array = []         # 血色水痕 {pos, r, t, tick, dmg}
var elegy_t := 0.0            # 挽歌水纹计时


## 锯环：半径 0→r 快速张开（前 25%），锯齿斜切、按 spin 旋转；地面透视压扁（y × 0.55）；顶点对齐 2 像素网格
func _draw_pfx(f: Dictionary, a: float) -> bool:
	if f.kind != "saw":
		return false
	var u: float = 1.0 - a
	var rr: float = f.r * (0.55 + 0.45 * (1.0 - pow(1.0 - minf(1.0, u / 0.25), 2.0)))
	var rot: float = f.ang + f.spin * u * f.max
	var c: Color = f.col
	var T: float = f.tooth
	var n: int = clampi(int(TAU * rr / (T * 1.6)), 16, 48)
	var P := func(v: Vector2) -> Vector2: return (v / 2.0).round() * 2.0
	var flat := func(v: Vector2) -> Vector2: return f.pos + Vector2(v.x, v.y * 0.55)
	# 残影：上一瞬的锯环，淡、略小
	g.draw_set_transform(f.pos, 0.0, Vector2(1.0, 0.55))
	g.draw_arc(Vector2.ZERO, rr * 0.92, 0.0, TAU, 48, Color(c.r, c.g, c.b, 0.18 * a), T * 1.6)
	# 锯身：暗描边 + 本色环 + 内侧亮边
	g.draw_arc(Vector2.ZERO, rr, 0.0, TAU, 56, Color(0.05, 0.06, 0.09, 0.8 * a), 7.0)
	g.draw_arc(Vector2.ZERO, rr, 0.0, TAU, 56, Color(c.r * 0.8, c.g * 0.8, c.b * 0.85, 0.95 * a), 4.0)
	g.draw_arc(Vector2.ZERO, rr - 3.0, 0.0, TAU, 56, Color(c.r * 1.5, c.g * 1.5, c.b * 1.5, 0.7 * a), 1.0)
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 锯齿：外缘一圈斜三角（齿尖朝旋转方向）
	var sgn: float = signf(f.spin)
	for i in n:
		var t0: float = rot + TAU * i / n
		var t1: float = t0 + sgn * TAU / n * 0.75
		var base0: Vector2 = Vector2.from_angle(t0) * rr
		var base1: Vector2 = Vector2.from_angle(t1) * rr
		var tip: Vector2 = Vector2.from_angle(t1) * (rr + T)
		var pts := PackedVector2Array([P.call(flat.call(base0)), P.call(flat.call(tip)), P.call(flat.call(base1))])
		if absf((pts[1] - pts[0]).cross(pts[2] - pts[0])) < 2.0:
			continue   # 对齐网格后退化成线的齿不画（否则三角化报错）
		# 前半圈（屏幕下方，y > 0）更亮：像锯盘朝镜头这一侧反光
		var lit: float = 0.75 + 0.35 * clampf(sin(t0), 0.0, 1.0)
		g.draw_colored_polygon(pts, Color(c.r * lit * 1.3, c.g * lit * 1.3, c.b * lit * 1.35, a))
	return true


func _reach() -> float:
	return base("reach", 120.0) * stat(&"op_range") * (base("s3_reach", 1.5) if s3_t > 0.0 else 1.0) * (base("beast_reach", 1.5) if _beast_on() else 1.0)


## 「困兽」生效中：求生之技期间
func _beast_on() -> bool:
	return beast and s1_t > 0.0


func away() -> bool:
	return doll_t > 0.0


func follow_target(slot_pos: Vector2) -> Vector2:
	if away():
		return slot_pos
	var p := melee_spot(LEASH, 26.0)
	return p if p != Vector2.INF else slot_pos


func update(dt: float) -> void:
	cd -= dt
	s1_t = maxf(0.0, s1_t - dt)
	s3_t = maxf(0.0, s3_t - dt)
	if s2_t > 0.0:
		s2_t -= dt
		if s2_t <= 0.0:
			_start_fall()
	if fall_t > 0.0:
		fall_t -= dt
		if fall_t <= 0.0:
			_fall()
	_update_doll(dt)
	_update_rings(dt)
	if s1_t > 0.0 and not away() and g.rng.randf() < dt * 14.0:
		fx({"kind": "mote", "pos": pos + Vector2(g.rng.randf_range(-16, 16), g.rng.randf_range(-40, -4)), "vel": Vector2(0, -60), "life": 0.5, "col": Color(1.0, 0.2, 0.25), "sz": 2.0})
	_update_spins(dt)
	if away() or acting() or fall_t > 0.0:
		return
	var ready := charge_skills(dt)
	if ready >= 0:
		start_skill(Vector2.INF, ready)
		return
	if cd <= 0.0:
		var ts: Array = nearest_enemies(1, _reach() + 30.0, pos)
		if ts.is_empty():
			cd = 0.1
		else:
			cd = base("cd", 1.2) / stat(&"op_aspd") / (1.0 + base("s2_aspd", 0.6) if s2_t > 0.0 else 1.0) * (base("s3_cd_mult", 1.6) if s3_t > 0.0 else 1.0)
			start_attack(ts[0].pos)


func _atk_mult() -> float:
	var m := 1.0
	if s1_t > 0.0:
		m *= 1.0 + base("s1_atk", 0.4) + clampf(1.0 - g.hp / g.max_hp, 0.0, 1.0)
	if s2_t > 0.0:
		m *= 1.0 + base("s2_atk", 0.4)
	if s3_t > 0.0:
		m *= base("s3_mult", 3.2)
	if elite >= 1 and g.lamp < 30.0:
		m *= 1.0 + base("dark_bonus", 0.25)
	return m


## 环斩：贴身 360°（第一圈）；成长后追加第二圈 / 血色水痕 / 持续旋转
func _release() -> void:
	var dmg: float = base("atk", 46.0) * _dmg_bonus() * _atk_mult() * (skill_power() if (s1_t > 0.0 or s2_t > 0.0 or s3_t > 0.0) else 1.0)
	_spin(dmg, 0)
	# N1 双重回转：0.15 秒后反向再转一圈（70%）
	if double_spin:
		spin2_t = base("spin2_delay", 0.15)
		spin2_dmg = dmg * base("spin2_mult", 0.7)
	# N2 血色潮痕：锯过的地面留下一圈血色水痕（最多 6 圈，旧的先消失）
	if blood_ring:
		if rings.size() >= int(base("ring_max", 6.0)):
			rings.pop_front()
		rings.append({"pos": pos, "r": _reach(), "t": base("ring_dur", 1.5), "tick": base("ring_tick", 0.5), "dmg": dmg * base("ring_mult", 0.2)})
	# 精二 无尽回旋：环斩不停，持续旋转 0.6 秒（灯火 <30 时 1.2 秒），每 0.15 秒一段 45%；新的环斩重置时长
	if whirl_on:
		var tk: float = base("whirl_tick", 0.15)
		whirl_t = base("whirl_dur_dark", 1.2) if g.lamp < 30.0 else base("whirl_dur", 0.6)
		# 段数 = 时长 / 0.15（0.6 秒 4 段、1.2 秒 8 段）；有双重回转时 0.15 秒那一段由第二圈（70%）顶替
		whirl_n = int(round(whirl_t / tk)) - (1 if double_spin else 0)
		whirl_tick = tk * (2.0 if double_spin else 1.0)
		whirl_dmg = dmg * base("whirl_mult", 0.45)


## 第二圈与持续旋转的计时（本体离场时停止）
func _update_spins(dt: float) -> void:
	if away():
		spin2_t = -1.0
		whirl_t = 0.0
		whirl_n = 0
		return
	whirl_ang += dt * 14.0 * (1.0 if face >= 0.0 else -1.0)
	if spin2_t >= 0.0:
		spin2_t -= dt
		if spin2_t < 0.0:
			_spin(spin2_dmg, 1)
	if whirl_t > 0.0 or whirl_n > 0:
		whirl_t = maxf(0.0, whirl_t - dt)
		whirl_tick -= dt
		if whirl_tick <= 0.0 and whirl_n > 0:
			whirl_tick += base("whirl_tick", 0.15)
			whirl_n -= 1
			_spin(whirl_dmg, 2)


## 一圈环斩：kind 0 = 主圈 / 1 = 双重回转的反向第二圈 / 2 = 无尽回旋的持续段
func _spin(dmg: float, kind: int) -> void:
	var r := _reach()
	var hits: Array = arc_targets(pos + Vector2(0, -10), 0.0, PI, r)
	for e in hits:
		var d: float = dmg
		if s3_t > 0.0 and e.hp < e.maxhp * 0.5:
			d *= base("s3_low_mult", 1.5)
		log_hit("锯刃")
		deal_damage(e, d)
		if not e.dead and not e.boss and kind == 0:
			e.kb += (e.pos - pos).normalized() * 70.0
		_hit_fx(e, pos)
	# 锯环（2026-09-25，替换斩击环帧条：她用的是长柄圆锯，不是刀）：锯盘绕身一圈的轨迹画成高速旋转的锯齿圆环，
	# 贴地压扁；锯过的敌人沿切线甩出火星。S3 求生之压：血红、齿更大
	var heavy: bool = s3_t > 0.0   # 血锯只属于 S3；困兽（S1）保持银蓝锯环，靠周身红焰区分
	# 第二圈反向旋转（锯环镜像）；持续段交替方向
	var rev: bool = (face < 0.0) != (kind == 1)
	if kind == 2:
		rev = (face < 0.0) != (whirl_n % 2 == 1)
	# Codex 锯环（80×44 贴地椭圆，中心对齐人物；半径 = 40 × 缩放）；缺图退回程序锯环
	# 持续段只画程序锯环（每 0.15 秒一段，帧条叠太多会糊成一片）
	if kind == 2 or not spawn_fx_sprite("fx_specter_saw_blood" if heavy else "fx_specter_saw", pos + Vector2(0, -6), r / 40.0, 0.0, rev):
		fx({"kind": "saw", "pos": pos + Vector2(0, -8), "r": r * (0.9 if kind == 2 else 1.0), "life": 0.3 if heavy else 0.24, "col": RED if heavy else GHOST,
			"spin": (-1.0 if rev else 1.0) * (26.0 if heavy else 34.0), "tooth": 8.0 if heavy else 6.0, "ang": g.rng.randf() * TAU})
	# 第二圈：外侧再加一道淡蓝锯环，两道锯痕一眼可辨
	if kind == 1:
		fx({"kind": "saw", "pos": pos + Vector2(0, -8), "r": r * 1.08, "life": 0.22, "col": RED if heavy else Color(0.6, 0.75, 0.95),
			"spin": (-1.0 if rev else 1.0) * 30.0, "tooth": 5.0, "ang": g.rng.randf() * TAU})
	for e in hits:
		var ea: float = (e.pos - pos).angle() + PI / 2.0 * (-1.0 if rev else 1.0)
		for k in (3 if kind == 0 else 1):
			fx({"kind": "spark", "pos": e.pos + Vector2(0, -e.r * 0.5), "vel": Vector2.from_angle(ea + g.rng.randf_range(-0.35, 0.35)) * g.rng.randf_range(160, 300),
				"life": 0.22, "col": Color(1.4, 1.55, 1.75) if not heavy else Color(1.6, 0.5, 0.55), "sz": 2.0, "drag": 3.0})
	# 求生之压：每一斩脚下砸出地裂 + 短顿帧（慢而重）
	if s3_t > 0.0 and kind == 0:
		fx({"kind": "crack", "pos": pos + Vector2(0, 4), "r": r * 0.8, "life": 0.6, "col": RED, "floor": true, "n": 7})
		g.hitstop = maxf(g.hitstop, 0.05)
	# 求生之压期间：更响、更低沉；第二圈更轻，持续段不再逐段出声
	if kind == 0:
		Sfx.op(id, "atk", 4.0 if s3_t > 0.0 else 0.0, 0.8 if s3_t > 0.0 else 1.0, 0.06)
	elif kind == 1:
		Sfx.op(id, "atk", -4.0, 1.15, 0.06)


func _hit_fx(e: Dictionary, _origin: Vector2) -> void:
	fx({"kind": "glow", "pos": e.pos + Vector2(0, -e.r * 0.5), "r": 9.0, "life": 0.15, "col": RED if s3_t > 0.0 else GHOST, "alpha": 0.5})


# ---------------------------------------------------------------- 技能

func _release_skill() -> void:
	match cur_skill:
		0:
			s1_t = base("s1_dur", 8.0)
			float_text(pos + Vector2(0, -60), "求生之技", GHOST, 15)
		1:
			s2_t = base("s2_dur", 10.0)
			show_banner("求生之渴：主控暂不会倒下")
		2:
			s3_t = base("s3_dur", 12.0)
			show_banner("求生之压")
	fx({"kind": "ring", "pos": pos, "r": _reach(), "r0": 8.0, "life": 0.45, "col": GHOST if cur_skill < 2 else RED, "floor": true})
	spawn_fx_sprite("fx_circle_ghost", pos + Vector2(0, 4), g.PX * 1.8)
	g.fx.append({"kind": "rays", "pos": pos + Vector2(0, -24), "life": 0.5, "max": 0.5, "col": GHOST if cur_skill < 2 else RED})
	# 锯盘砸地的落点（op_specter_unchained_skill@2x 出手帧第 4 帧：锯盘中心在脚底前 34、上 13）：一小圈贴地冲击 + 火星，
	# 原来只在脚下画光环，锯头落地处什么都没有（docs/32 §3）
	var saw: Vector2 = pos + Vector2(27.0 * face, 0)
	fx({"kind": "ring", "pos": saw, "r": 30.0, "r0": 6.0, "life": 0.3, "col": GHOST if cur_skill < 2 else RED, "floor": true, "w": 3.0})
	fx_sparks(saw + Vector2(0, -13), Color(0.85, 0.9, 1.0) if cur_skill < 2 else RED, 8, 200.0, 0.3, 2.5, 320.0)


func skill_active_left(i: int) -> float:
	match i:
		0: return s1_t
		1: return s2_t
		2: return s3_t
	return 0.0


func skill_active_dur(i: int) -> float:
	return [base("s1_dur", 8.0), base("s2_dur", 10.0), base("s3_dur", 12.0)][i]


## game.gd 询问：S2 期间主控不会倒下
func prevent_death() -> bool:
	return s2_t > 0.0


## S2 结束：先播倒下帧条 op_specter_unchained_fall（5 帧 10fps，不循环、停在末帧；docs/32 验收 §2），播完再切替身。
## 倒下期间不出手；缺图时直接切替身（和以前一样）
var fall_t := 0.0

func _fall_dur() -> float:
	var sp := sprite_spec("fall")
	return float(sp.get("frames", 5)) / float(sp.get("fps", 10)) if anim_tex("fall") != null else 0.0


func _start_fall() -> void:
	melee_tgt = null
	fire_t = -1.0   # 取消已起手、还没到出手帧的那一刀（docs/45 #13）
	fall_t = _fall_dur()
	if fall_t <= 0.0:
		_fall()


func anim_state() -> Dictionary:
	if fall_t > 0.0:
		var tx: Texture2D = anim_tex("fall")
		if tx != null:
			var n: int = anim_hframes(tx, "fall")
			var fr: int = clampi(int((_fall_dur() - fall_t) * float(sprite_spec("fall").get("fps", 10))), 0, n - 1)
			return {"tex": tx, "frame": fr, "hf": n, "flip": face < 0.0, "kind": "fall"}
	return super()


## 倒下播完：留下替身（替身跟随主控干员，_update_doll）
func _fall() -> void:
	doll_pos = pos
	doll_t = base("doll_dur", 12.0)
	doll_tick = 0.0
	doll_at = 0.0
	melee_tgt = null
	float_text(pos + Vector2(0, -60), "替身", GHOST, 15)
	fx({"kind": "glow", "pos": pos + Vector2(0, -24), "r": 30.0, "life": 0.5, "col": GHOST, "alpha": 0.6})
	fx_sparks(pos + Vector2(0, -20), GHOST, 10, 120.0, 0.5, 2.5)


func _update_doll(dt: float) -> void:
	if doll_t <= 0.0:
		return
	doll_t -= dt
	doll_at += dt
	# 替身跟随主控干员（用户定：不原地停留），站在主控身后一侧
	var want: Vector2 = g.ppos + Vector2(-46.0 * g.facing, 8.0)
	doll_pos = doll_pos.lerp(want, clampf(dt * 4.0, 0.0, 1.0))
	# N5 阿戈尔挽歌：替身唱挽歌，每 0.8 秒一圈水纹从脚下外扩到减速范围边缘
	if elegy:
		elegy_t -= dt
		if elegy_t <= 0.0:
			elegy_t = base("elegy_every", 0.8)
			var er: float = _doll_slow_r()
			fx({"kind": "ring", "pos": doll_pos + Vector2(0, 2), "r": er, "r0": 14.0, "life": 1.6, "col": Color(0.45, 0.75, 1.1), "floor": true, "w": 2.5, "alpha": 0.7})
			fx({"kind": "ring", "pos": doll_pos + Vector2(0, 2), "r": er * 0.7, "r0": 6.0, "life": 1.2, "col": Color(0.8, 0.95, 1.3), "floor": true, "w": 1.5, "alpha": 0.45})
			fx({"kind": "mote", "pos": doll_pos + Vector2(g.rng.randf_range(-8, 8), -40), "vel": Vector2(g.rng.randf_range(-10, 10), -26.0), "life": 1.0, "col": Color(0.6, 0.85, 1.2), "sz": 2.0})
	# 天赋：替身光环每秒法伤 + 减速（挽歌：减速范围翻倍，伤害范围不变）
	if elite >= 1:
		doll_tick += dt
		if doll_tick >= 1.0:
			doll_tick -= 1.0
			var r: float = base("doll_r", 120.0)
			var sr: float = _doll_slow_r()
			for j in query_ids(doll_pos, sr + 20.0):
				var e: Dictionary = g.enemies[j]
				if e.dead:
					continue
				var d: float = e.pos.distance_to(doll_pos)
				if d > sr:
					continue
				e.slow = maxf(e.slow, 1.0)
				if d > r:
					continue
				log_hit("替身")
				deal_damage(e, base("doll_dps", 10.0) * _dmg_bonus())
			if not spawn_fx_sprite("fx_circle_ghost", doll_pos + Vector2(0, 4), g.PX * (r / 40.0)):
				fx({"kind": "ring", "pos": doll_pos, "r": r, "r0": r * 0.6, "life": 0.5, "col": GHOST, "floor": true, "alpha": 0.5})
	if doll_t <= 0.0:
		elegy_t = 0.0
		# 归队：从替身处回到编队位
		pos = doll_pos
		doll_pos = Vector2.INF
		float_text(pos + Vector2(0, -60), "归队", GHOST, 14)
		fx({"kind": "glow", "pos": pos + Vector2(0, -24), "r": 24.0, "life": 0.4, "col": GHOST, "alpha": 0.5})


## 替身减速半径：挽歌翻倍
func _doll_slow_r() -> float:
	return base("doll_r", 120.0) * (base("elegy_r_mult", 2.0) if elegy else 1.0)


## 血色水痕：每 0.5 秒对圈内敌人跳一次伤害
func _update_rings(dt: float) -> void:
	if rings.is_empty():
		return
	for rg in rings:
		rg.t -= dt
		rg.tick -= dt
		if rg.tick <= 0.0 and rg.t > -0.01:
			rg.tick += base("ring_tick", 0.5)
			for j in query_ids(rg.pos, rg.r + 20.0):
				var e: Dictionary = g.enemies[j]
				if e.dead or e.pos.distance_to(rg.pos) > rg.r + e.r:
					continue
				log_hit("血色潮痕")
				deal_damage(e, rg.dmg)
			fx_sparks(rg.pos + Vector2(0, 2), Color(1.1, 0.3, 0.4), 3, 60.0, 0.35, 2.0, 0.0, true)
	rings = rings.filter(func(rg): return rg.t > 0.0)


# ---------------------------------------------------------------- 成长节点（data/characters/specter_unchained.json 的 custom 节点）

func on_custom_node(nid: String, _choice: String = "") -> void:
	match nid:
		"double_spin":
			double_spin = true
		"blood_ring":
			blood_ring = true
		"beast":
			beast = true
		"elegy":
			elegy = true


func on_elite(stage: int, _choice: String = "") -> void:
	if stage >= 2:
		whirl_on = true


# ---------------------------------------------------------------- 绘制

func draw_body() -> void:
	if away():
		return
	super()


## 地面层：血色水痕（淡红水面 + 外缘水线 + 内侧涟漪 + 边缘水珠），随剩余时间淡出
func draw_entities_floor() -> void:
	for rg in rings:
		var a: float = clampf(rg.t / 0.5, 0.0, 1.0)
		var age: float = base("ring_dur", 1.5) - rg.t
		g.draw_set_transform(rg.pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
		g.draw_circle(Vector2.ZERO, rg.r, Color(0.55, 0.05, 0.12, 0.16 * a))
		g.draw_arc(Vector2.ZERO, rg.r, 0.0, TAU, 40, Color(1.0, 0.22, 0.3, 0.65 * a), 2.5)
		g.draw_arc(Vector2.ZERO, rg.r * (0.5 + 0.4 * fmod(age * 1.2, 1.0)), 0.0, TAU, 32, Color(1.2, 0.4, 0.45, 0.35 * a), 1.5)
		for q in 6:
			var an: float = q * TAU / 6.0 + rg.pos.x * 0.01
			g.draw_circle(Vector2.from_angle(an) * rg.r, 3.0, Color(1.1, 0.25, 0.32, 0.55 * a))
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func draw_auras() -> void:
	if pos != Vector2.INF and not away() and s1_t > 0.0:
		# 求生之技：周身红色兽性气焰（一圈跳动的红色火舌）+ 身体红光，锯环仍是银蓝
		var hk: float = 0.5 + 0.5 * sin(g.t * 9.0)
		g.draw_circle(pos + Vector2(0, -22), 22.0 + 3.0 * hk, Color(1.0, 0.1, 0.15, 0.16))
		for q in 7:
			var an: float = q * TAU / 7.0 + g.t * 2.0
			var bp: Vector2 = pos + Vector2(cos(an) * 16.0, -6.0 + sin(an) * 7.0)
			var h: float = 14.0 + 6.0 * sin(g.t * 13.0 + q * 2.1)
			g.draw_colored_polygon(PackedVector2Array([bp + Vector2(-4, 0), bp + Vector2(sin(g.t * 20.0 + q) * 2.0, -h), bp + Vector2(4, 0)]), Color(1.5, 0.2, 0.25, 0.55))
	if pos != Vector2.INF and not away() and (s1_t > 0.0 or s2_t > 0.0 or s3_t > 0.0):
		var c: Color = RED if s3_t > 0.0 else GHOST
		g.draw_set_transform(pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
		g.draw_arc(Vector2.ZERO, _reach(), 0.0, TAU, 36, Color(c.r, c.g, c.b, 0.25 + 0.1 * sin(g.t * 6.0)), 2.0)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if doll_t > 0.0 and doll_pos != Vector2.INF and elite >= 1:
		g.draw_set_transform(doll_pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
		g.draw_arc(Vector2.ZERO, base("doll_r", 120.0), 0.0, TAU, 36, Color(GHOST.r, GHOST.g, GHOST.b, 0.2 + 0.08 * sin(g.t * 3.0)), 2.0)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_skill_over() -> void:
	if away():
		return
	# 无尽回旋：身周两道高速旋转的锯弧 + 拖尾（持续期间一直在转；灯火 <30 时变血红）
	if whirl_t > 0.0:
		var r: float = _reach() * 0.92
		var fade: float = clampf(whirl_t / 0.2, 0.0, 1.0)
		var heavy: bool = s3_t > 0.0 or g.lamp < 30.0
		var c: Color = Color(1.5, 0.45, 0.5) if heavy else Color(1.2, 1.35, 1.6)
		g.draw_set_transform(pos + Vector2(0, -8), 0.0, Vector2(1.0, 0.55))
		for q in 2:
			var a0: float = whirl_ang + q * PI
			for k in 4:
				g.draw_arc(Vector2.ZERO, r - k * 2.0, a0 - k * 0.22, a0 - k * 0.22 + 1.1, 16, Color(c.r, c.g, c.b, (0.85 - k * 0.2) * fade), 4.0 - k * 0.7)
			g.draw_circle(Vector2.from_angle(a0 + 1.1) * r, 4.0, Color(c.r * 1.3, c.g * 1.3, c.b * 1.3, 0.9 * fade))
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if s2_t > 0.0 or s3_t > 0.0:
		var p := pos + Vector2(4.0 * face, -38)
		var c: Color = RED if s3_t > 0.0 else GHOST
		g.draw_circle(p, 2.5 + sin(g.t * 24.0), Color(c.r * 2.0, c.g * 1.6, c.b * 1.6, 0.9))


func extra_bodies() -> Array:
	if doll_t > 0.0 and doll_pos != Vector2.INF:
		return [{"y": doll_pos.y + 2.0}]
	return []


func draw_extra(_it: Dictionary) -> void:
	var tx: Texture2D = anim_tex("doll")
	if tx == null:
		g.draw_circle(doll_pos + Vector2(0, -20), 12.0, GHOST)
		return
	var n: int = anim_hframes(tx, "doll")
	var fr: int = int(doll_at * 4.0) % n
	var sway: float = sin(doll_at * 2.0) * 1.0
	draw_sprite_at(doll_pos + Vector2(sway, 0), face < 0.0, Color(0.95, 0.95, 1.0), fr, tx, n, foot_off(tx, "doll"))


func draw_extra_shadows() -> void:
	if doll_t > 0.0 and doll_pos != Vector2.INF:
		draw_spr("shadow", 1, 0, doll_pos + Vector2(0, 4), g.PX)


func status_items() -> Array:
	var out: Array = []
	if s2_t > 0.0:
		out.append(["不倒", GHOST])
	if s3_t > 0.0:
		out.append(["求生之压", RED])
	if _beast_on():
		out.append(["困兽", RED])
	if doll_t > 0.0:
		out.append(["替身 %d" % int(ceil(doll_t)), GHOST])
	return out
