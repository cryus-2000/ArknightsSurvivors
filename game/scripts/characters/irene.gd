## 艾丽妮（近卫·剑豪，契约 v2.1，docs/26 第二批）：控制 + 处决。刺剑直线穿刺一列敌人，每次两段；唯一会把敌人打浮空的干员。
## S1 疾风：下一次刺击命中的第一个敌人浮空 1 秒，落下时补一刺（两段各 ×1.6）；
## S2 碎潮：前方锥形斩击最多 8 名 ×2.8，浮空 2 秒（精英 1 秒，Boss 不浮空）；
## S3 审判：自身 r160 斩击 ×2.5 并浮空全部敌人 3 秒，随后 10 次灯光轰击 ×1.8，优先砸浮空目标。
## 天赋 涤罪之焰：对浮空 / 眩晕 / 束缚（slow）中的敌人伤害 +30%。
## 浮空 = e.stun + e.air（Boss 跳跃已在用的高度字段，game.gd 绘制时按 air 抬高），本脚本每帧写一条 sin 弧线；不改 game.gd。
extends "res://scripts/characters/character.gd"

const PINK := Color(0.95, 0.6, 0.8)
const SILVER := Color(0.9, 0.92, 1.0)
const LAMP := Color(1.0, 0.85, 0.5)
const LEASH := 170.0

var cd := 0.4
var second_t := -1.0          # 第二刺倒计时
var second_ang := 0.0
var second_mult := 1.0
var gust_next := false        # S1：下一次刺击带浮空
var airborne: Array = []      # {e, t, dur, h}
var strikes: Array = []       # S3 灯光轰击队列：{t}
var judge_c := Vector2.INF
var judge_left := 0.0


func _reach() -> float:
	return base("len", 120.0) * stat(&"op_range")


func follow_target(slot_pos: Vector2) -> Vector2:
	var p := melee_spot(LEASH, 40.0)
	return p if p != Vector2.INF else slot_pos


func update(dt: float) -> void:
	cd -= dt
	_update_airborne(dt)
	_update_strikes(dt)
	if second_t >= 0.0:
		second_t -= dt
		if second_t < 0.0:
			second_t = -1.0
			_thrust(second_ang, second_mult, false)
	if acting():
		return
	var ready := charge_skills(dt)
	if ready == 0:
		spend_sp(0)
		gust_next = true
		fx({"kind": "glow", "pos": pos + Vector2(10.0 * face, -30), "r": 14.0, "life": 0.3, "col": PINK, "alpha": 0.5})
		return
	if ready > 0:
		var ts: Array = g._nearest(1, 220.0, pos)
		start_skill(ts[0].pos if not ts.is_empty() else Vector2.INF, ready)
		return
	if cd <= 0.0:
		var ts2: Array = g._nearest(1, _reach() + 20.0, pos)
		if ts2.is_empty():
			cd = 0.1
		else:
			cd = base("cd", 0.8) / stat(&"op_aspd")
			start_attack(ts2[0].pos)


## 出手帧（第一刺）；第二刺按帧条的 second 帧延后
func _release() -> void:
	var ts: Array = g._nearest(1, _reach() + 40.0, pos)
	var ang: float = facing_angle()
	if not ts.is_empty():
		ang = (ts[0].pos - pos).angle()
		face_to(ang)
	var mult := 1.0
	var gust := gust_next
	gust_next = false
	if gust:
		mult = base("s1_mult", 1.6) * skill_power()
	var first := _thrust(ang, mult, gust)
	var spec := sprite_spec("attack")
	var fps: float = float(spec.get("fps", 12))
	second_t = maxf(0.05, (float(spec.get("second", 3)) - float(spec.get("fire", 1))) / fps)
	second_ang = ang
	second_mult = mult
	if gust and not first.is_empty():
		# 疾风：第一个命中者浮空 1 秒，落下时再补一刺
		_lift(first, 1.0, 26.0)
		fx({"kind": "ring", "pos": first.pos, "r": 30.0, "r0": 6.0, "life": 0.3, "col": PINK, "floor": true})


## 直线穿刺：返回命中的第一个敌人（最近的）
func _thrust(ang: float, mult: float, tag_gust: bool) -> Dictionary:
	var d := Vector2.from_angle(ang)
	var o: Vector2 = pos + Vector2(0, -12)
	var L: float = _reach()
	var W: float = base("width", 26.0)
	var hits: Array = []
	for j in g._query(o + d * L * 0.5, L * 0.6 + 40.0):
		var e: Dictionary = g.enemies[j]
		if e.dead:
			continue
		var rel: Vector2 = e.pos - o
		var along: float = rel.dot(d)
		if along < -e.r or along > L + e.r:
			continue
		if absf(rel.cross(d)) > W * 0.5 + e.r:
			continue
		hits.append([along, e])
	hits.sort_custom(func(a, b): return a[0] < b[0])
	var dmg: float = base("atk", 16.0) * _dmg_bonus() * mult
	var first: Dictionary = {}
	for h in hits:
		var e: Dictionary = h[1]
		g._hit("疾风" if tag_gust else "刺剑")
		g._damage(e, dmg * _talent_mult(e))
		fx({"kind": "spark", "pos": e.pos + Vector2(0, -e.r * 0.5), "vel": d * 120.0 + Vector2(g.rng.randf_range(-40, 40), -60), "life": 0.25, "col": SILVER, "sz": 2.0, "drag": 3.0})
		if first.is_empty():
			first = e
	# 剑光：玫瑰色弧光帧条（Ninja Slash Arc 重调色）沿刺击方向拉长；缺图退回细亮线
	if not g._fx_sprite("fx_slash_arc_rose", o + d * L * 0.55, L * 0.9 / 40.0, ang):
		fx({"kind": "line", "pos": o + d * 10.0, "to": o + d * L, "life": 0.12, "col": SILVER, "w": 3.0})
	fx({"kind": "line", "pos": o + d * 10.0, "to": o + d * L * 0.7, "life": 0.08, "col": PINK, "w": 1.5})
	Sfx.op(id, "atk", 0.0, 1.0, 0.08)
	if not first.is_empty():
		Sfx.op(id, "hit")
	return first


## 天赋：对受控敌人 +30%
func _talent_mult(e: Dictionary) -> float:
	if elite >= 1 and (e.get("air", 0.0) > 0.0 or e.stun > 0.0 or e.slow > 0.0):
		return 1.0 + base("talent_bonus", 0.3)
	return 1.0


# ---------------------------------------------------------------- 浮空

func _lift(e: Dictionary, dur: float, h: float) -> void:
	if e.dead or e.boss or dur <= 0.0:
		return
	if e.elite:
		dur *= 0.5
	for a in airborne:
		if is_same(a.e, e):
			a.dur = maxf(a.dur, dur)
			a.t = 0.0
			return
	airborne.append({"e": e, "t": 0.0, "dur": dur, "h": h})
	e.stun = maxf(e.stun, dur)


func _update_airborne(dt: float) -> void:
	if airborne.is_empty():
		return
	for a in airborne:
		a.t += dt
		var e: Dictionary = a.e
		if e.dead:
			e.air = 0.0
			a.t = a.dur + 1.0
			continue
		var k: float = clampf(a.t / a.dur, 0.0, 1.0)
		e.air = sin(k * PI) * a.h
		e.kb = Vector2.ZERO
		if k >= 1.0:
			e.air = 0.0
	airborne = airborne.filter(func(a): return a.t < a.dur)


func _airborne_enemies(c: Vector2, r: float) -> Array:
	var out: Array = []
	for a in airborne:
		if not a.e.dead and a.e.pos.distance_to(c) < r:
			out.append(a.e)
	return out


# ---------------------------------------------------------------- 技能

func _release_skill() -> void:
	match cur_skill:
		1:
			# 碎潮：前方锥形，最多 8 名，×2.8，浮空 2 秒
			var ts: Array = g._nearest(1, 240.0, pos)
			var ang: float = facing_angle()
			if not ts.is_empty():
				ang = (ts[0].pos - pos).angle()
				face_to(ang)
			var r: float = _reach() * 1.3
			var hits: Array = g._arc_hit(pos + Vector2(0, -10), ang, 0.8, r)
			hits.sort_custom(func(a, b): return a.pos.distance_squared_to(pos) < b.pos.distance_squared_to(pos))
			var dmg: float = base("atk", 16.0) * base("s2_mult", 2.8) * _dmg_bonus() * skill_power()
			var n: int = mini(int(base("s2_n", 8.0)), hits.size())
			for i in n:
				var e: Dictionary = hits[i]
				g._hit("碎潮")
				g._damage(e, dmg * _talent_mult(e))
				_lift(e, 2.0, 34.0)
			if not g._fx_sprite("fx_slash_heavy_rose", pos + Vector2(0, -14) + Vector2.from_angle(ang) * r * 0.5, r * 1.2 / 28.0, ang):
				g._slash_fx(pos + Vector2(0, -14), ang, 0.8, r, PINK, "slash", 0.25)
			fx_sparks(pos + Vector2.from_angle(ang) * r * 0.5, SILVER, 10, 200.0, 0.4, 2.5, 200.0)
			# 发动音 op_irene_s2 由 spend_sp 播放（锥形重斩本身）
		2:
			# 审判：周身 r160 斩击 ×2.5 + 全部浮空 3 秒，然后 10 次灯光轰击
			var r3: float = base("s3_r", 160.0) * stat(&"op_range")
			var dmg3: float = base("atk", 16.0) * base("s3_mult", 2.5) * _dmg_bonus() * skill_power()
			for e in g._arc_hit(pos + Vector2(0, -10), 0.0, PI, r3):
				g._hit("审判")
				g._damage(e, dmg3 * _talent_mult(e))
				_lift(e, 3.0, 40.0)
			judge_c = pos
			judge_left = 3.0
			strikes.clear()
			for i in int(base("s3_strikes", 10.0)):
				strikes.append({"t": 0.3 + i * 0.27})
			if not g._fx_sprite("fx_slash_circle_rose", pos + Vector2(0, -14), r3 * 2.0 / 56.0, 0.0):
				g._slash_fx(pos + Vector2(0, -14), 0.0, PI, r3, PINK, "slash", 0.3)
			fx({"kind": "ring", "pos": pos, "r": r3, "r0": 20.0, "life": 0.5, "col": LAMP, "floor": true, "w": 3.0})
			g.fx.append({"kind": "rays", "pos": pos + Vector2(0, -30), "life": 0.6, "max": 0.6, "col": LAMP})
			g._show_banner("审判")


func skill_active_left(i: int) -> float:
	return judge_left if i == 2 else 0.0


func skill_active_dur(i: int) -> float:
	return 3.0 if i == 2 else 1.0


func _update_strikes(dt: float) -> void:
	judge_left = maxf(0.0, judge_left - dt)
	if strikes.is_empty():
		return
	var r3: float = base("s3_r", 160.0) * stat(&"op_range")
	for s in strikes:
		s.t -= dt
		if s.t <= 0.0:
			# 优先砸浮空目标，其次范围内随机敌人
			var pool: Array = _airborne_enemies(judge_c, r3)
			if pool.is_empty():
				pool = g._nearest(6, r3, judge_c)
			if pool.is_empty():
				continue
			var e: Dictionary = pool[g.rng.randi() % pool.size()]
			var c: Vector2 = e.pos
			area_hit("灯光轰击", c, 40.0, base("atk", 16.0) * base("s3_strike_mult", 1.8) * _dmg_bonus() * skill_power(), 0.0, 0.0)
			if not g._fx_sprite("fx_holy_pillar_amber", c + Vector2(0, 4), g.PX * 0.9, 0.0, false, true):
				fx({"kind": "line", "pos": c + Vector2(0, -140), "to": c, "life": 0.2, "col": LAMP, "w": 6.0})
			g._fx_sprite("fx_holy_impact_lantern", c + Vector2(0, -16), g.PX * 0.8)
			fx({"kind": "ring", "pos": c, "r": 40.0, "r0": 6.0, "life": 0.3, "col": LAMP, "floor": true})
			fx({"kind": "glow", "pos": c + Vector2(0, -10), "r": 18.0, "life": 0.2, "col": LAMP, "alpha": 0.6})
			Sfx.op(id, "big", -4.0, 1.0, 0.1)
	strikes = strikes.filter(func(s): return s.t > 0.0)


# ---------------------------------------------------------------- 绘制

func _draw_skill_over() -> void:
	# 举灯 / 审判期间：提灯亮
	if judge_left > 0.0 or (acting() and act_kind == "skill"):
		var p := pos + Vector2(-8.0 * face, -34)
		g.draw_circle(p, 5.0 + sin(g.t * 20.0), Color(1.6, 1.3, 0.7, 0.8))
		g.draw_circle(p, 12.0, Color(1.0, 0.85, 0.5, 0.2))
	# 浮空敌人脚下的小影环
	for a in airborne:
		if not a.e.dead:
			g.draw_set_transform(a.e.pos + Vector2(0, a.e.r * 0.8), 0.0, Vector2(1.0, 0.5))
			g.draw_arc(Vector2.ZERO, a.e.r * 0.9, 0.0, TAU, 20, Color(PINK.r, PINK.g, PINK.b, 0.5), 1.5)
			g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func status_items() -> Array:
	var out: Array = []
	if gust_next:
		out.append(["疾风", PINK])
	if judge_left > 0.0:
		out.append(["审判", LAMP])
	return out
