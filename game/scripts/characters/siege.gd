## 推进之王（先锋，契约 v2.1）：节奏位。前压到博士身边的敌人面前抡锤，命中时为全队回复技力。
## S1 冲锋号令：全队技力 + 下一锤强化；S2 空中锤：砸地范围晕眩 + 全队技力；S3 碎颅：8 秒重锤，命中概率眩晕，攻速下降。
## 特效（docs/25）：狮王金。锤击重弧 + 命中十字闪 + 尘土；命中后金色技力粒子飞向每名队友（回 DP）；砸地双环 + 地裂 + 尘柱。
extends "res://scripts/characters/character.gd"

const GOLD := Color(1.0, 0.78, 0.35)
const DUST := Color(0.55, 0.5, 0.42)
const LEASH := 150.0          # 前压：只追博士这么远以内的敌人
const S3_DUR := 8.0

var cd := 0.4
var charge_next := false      # S1：下一锤 ×1.5
var skull := 0.0              # S3 碎颅剩余


func _reach() -> float:
	return 72.0 * stat(&"op_range")


func follow_target(slot_pos: Vector2) -> Vector2:
	var p := melee_spot(LEASH, 26.0)
	return p if p != Vector2.INF else slot_pos


func update(dt: float) -> void:
	cd -= dt
	skull = maxf(0.0, skull - dt)
	if acting():
		return
	var ready := charge_skills(dt)
	if ready == 0:
		spend_sp(0)
		charge_next = true
		g.squad.gain_sp(0.15 * skill_power(), self)
		_sp_motes(2)
		fx({"kind": "glow", "pos": pos + Vector2(0, -24), "r": 20.0, "life": 0.3, "col": GOLD, "alpha": 0.5})
		g._add_text(pos + Vector2(0, -80), "冲锋号令", GOLD, 14)
		return
	if ready > 0:
		start_skill(Vector2.INF, ready)
		return
	if cd <= 0.0:
		var ts: Array = g._nearest(1, _reach() + 30.0, pos)
		if ts.is_empty():
			cd = 0.1
		else:
			cd = 1.0 / stat(&"op_aspd") * (1.33 if skull > 0.0 else 1.0)
			start_attack(ts[0].pos)


func _release() -> void:
	var ang := facing_angle()
	var ts: Array = g._nearest(1, _reach() + 40.0, pos)
	if not ts.is_empty():
		ang = (ts[0].pos - pos).angle()
		face_to(ang)
	var mult := 1.0
	if charge_next:
		charge_next = false
		mult *= 1.5 * skill_power()
	if skull > 0.0:
		mult *= 1.8 * skill_power()
	var hits := melee_hit("锤击", pos + Vector2(0, -10), ang, 1.2, _reach(), 30.0 * mult * _dmg_bonus(), 140.0)
	if skull > 0.0:
		for e in hits:
			if not e.dead and not e.boss and g.rng.randf() < 0.5:
				e.stun = maxf(e.stun, 0.8 * (0.5 if e.elite else 1.0))
	g._slash_fx(pos + Vector2(0, -14), ang, 1.0, _reach(), GOLD if skull <= 0.0 else Color(1.0, 0.6, 0.3))
	var hp: Vector2 = pos + Vector2(0, -6) + Vector2.from_angle(ang) * _reach() * 0.7
	for k in 4:
		fx({"kind": "mote", "pos": hp + Vector2(g.rng.randf_range(-10, 10), 0), "vel": Vector2(g.rng.randf_range(-20, 20), g.rng.randf_range(-50, -25)), "life": 0.5, "col": DUST, "sz": 3.0})
	if not hits.is_empty():
		# 每次命中（不论几个目标）全队 +0.5 秒技力，精一翻倍
		_squad_sp_seconds(1.0 if elite >= 1 else 0.5)
		_sp_motes(1)
		Sfx.play("swing", -11.0, 0.7, 0.05)


func _hit_fx(e: Dictionary, _origin: Vector2) -> void:
	# 命中点十字重击闪
	fx({"kind": "impact", "pos": e.pos + Vector2(0, -e.r * 0.5), "life": 0.15, "col": GOLD, "ang": g.rng.randf() * PI})


func _release_skill() -> void:
	match cur_skill:
		1:
			# 空中锤：砸地
			var r: float = 110.0 * stat(&"op_range")
			area_hit("震地", pos, r, 30.0 * 2.2 * _dmg_bonus() * skill_power(), 220.0, 0.6)
			fx({"kind": "glow", "pos": pos + Vector2(12.0 * face, -6), "r": 30.0, "life": 0.18, "col": Color(1.8, 1.5, 0.8), "alpha": 0.7})
			fx({"kind": "ring", "pos": pos, "r": r, "r0": 12.0, "life": 0.4, "col": GOLD, "floor": true, "w": 5.0})
			fx({"kind": "ring", "pos": pos, "r": r * 0.6, "r0": 8.0, "life": 0.5, "col": Color(1.0, 0.9, 0.6), "floor": true, "w": 2.0})
			fx({"kind": "crack", "pos": pos + Vector2(12.0 * face, 2), "r": r * 0.8, "life": 0.55, "col": GOLD, "floor": true, "n": 10, "ang": g.t})
			for k in 14:
				fx({"kind": "mote", "pos": pos + Vector2(g.rng.randf_range(-30, 30), 0), "vel": Vector2(g.rng.randf_range(-60, 60), g.rng.randf_range(-170, -80)), "life": 0.6, "col": DUST, "sz": 3.5, "grav": 240.0})
			g.shake = maxf(g.shake, 5.0)
			g.squad.gain_sp(0.2 * skill_power(), self)
			_sp_motes(3)
			Sfx.play("boom", -9.0, 0.6)
		2:
			# 碎颅：8 秒重锤
			skull = S3_DUR
			fx({"kind": "glow", "pos": pos + Vector2(0, -24), "r": 30.0, "life": 0.35, "col": Color(1.0, 0.6, 0.3), "alpha": 0.6})
			g.fx.append({"kind": "rays", "pos": pos + Vector2(0, -20), "life": 0.5, "max": 0.5, "col": GOLD})
			g._show_banner("碎颅")
			Sfx.play("roar", -12.0, 1.3, 0.05)


func skill_active_left(i: int) -> float:
	return skull if i == 2 else 0.0


func skill_active_dur(i: int) -> float:
	return S3_DUR if i == 2 else 1.0


## 金色技力粒子：从她飞向每名队友
func _sp_motes(n: int) -> void:
	for o in g.squad.ops:
		if o == self or o.pos == Vector2.INF:
			continue
		for k in n:
			fx({"kind": "sp_mote", "pos": pos + Vector2(0, -22), "start": pos + Vector2(0, -22), "tgt": o, "life": 0.45 + 0.08 * k, "col": GOLD, "bend": g.rng.randf_range(-40, 40)})


func _draw_pfx(f: Dictionary, a: float) -> bool:
	match f.kind:
		"sp_mote":
			var k := 1.0 - a
			var to: Vector2 = f.tgt.pos + Vector2(0, -24)
			var p: Vector2 = f.start.lerp(to, k) + Vector2(0, -sin(k * PI) * 30.0) + f.start.direction_to(to).orthogonal() * sin(k * PI) * f.bend
			var tail: Vector2 = f.start.lerp(to, maxf(0.0, k - 0.12)) + Vector2(0, -sin(maxf(0.0, k - 0.12) * PI) * 30.0)
			g.draw_line(tail, p, Color(GOLD.r, GOLD.g, GOLD.b, 0.5), 2.0)
			g.draw_circle(p, 3.0, Color(2.2, 1.8, 0.9))
			return true
		"impact":
			var L := 10.0 + 14.0 * (1.0 - a)
			for q in 2:
				var dv := Vector2.from_angle(f.ang + q * PI / 2.0)
				g.draw_line(f.pos - dv * L, f.pos + dv * L, Color(2.0, 1.7, 1.0, a), 2.5)
			g.draw_circle(f.pos, 5.0 * a + 2.0, Color(2.4, 2.2, 1.6, a))
			return true
	return false


func draw_auras() -> void:
	if skull > 0.0 and pos != Vector2.INF:
		g.draw_arc(pos + Vector2(0, -22), 26.0 + 3.0 * sin(g.t * 9.0), 0.0, TAU, 24, Color(1.0, 0.6, 0.3, 0.4 + 0.15 * sin(g.t * 9.0)), 2.0)


## 全队（不含自己）技力 + 秒数
func _squad_sp_seconds(sec: float) -> void:
	for o in g.squad.ops:
		if o == self:
			continue
		for i in 3:
			if o.skill_unlocked(i) and o.sp_need(i) > 0.0:
				o.sp[i] = minf(o.sp_need(i), o.sp[i] + sec)


func status_items() -> Array:
	var out: Array = []
	if charge_next:
		out.append(["冲锋号令", GOLD])
	if skull > 0.0:
		out.append(["碎颅", Color(1.0, 0.6, 0.3)])
	return out
