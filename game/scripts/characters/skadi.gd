## 斯卡蒂（近卫，契约 v2.1）：近战输出。前压到博士身边的敌人面前高频横扫大剑。
## S1 潮涌斩：立即一次 ×2 宽幅横扫；S2 重斩：高举下劈大范围重击并击退；S3 潮汐：8 秒全方向横扫、范围与伤害提升。
## 特效（docs/25）：深海蓝 + 白浪。横扫双层弧光（深蓝 + 窄白边）+ 水珠飞溅；重斩抬剑时眼位红光，下劈巨大新月 + 地裂 + 水花柱。
extends "res://scripts/characters/character.gd"

const BLUE := Color(0.35, 0.55, 0.95)
const FOAM := Color(0.8, 0.95, 1.0)
const DROP := Color(0.6, 0.9, 1.0)
const LEASH := 160.0
const S3_DUR := 8.0

var cd := 0.3
var swings := 0               # 横扫计数（天赋：每第 3 次追加反手斩）
var tide := 0.0               # S3 潮汐剩余


func _reach() -> float:
	return 88.0 * stat(&"op_range") * (1.4 if tide > 0.0 else 1.0)


func follow_target(slot_pos: Vector2) -> Vector2:
	var p := melee_spot(LEASH, 30.0)
	return p if p != Vector2.INF else slot_pos


func update(dt: float) -> void:
	cd -= dt
	tide = maxf(0.0, tide - dt)
	if acting():
		return
	var ready := charge_skills(dt)
	if ready >= 0:
		var ts: Array = g._nearest(1, 200.0, pos)
		start_skill(ts[0].pos if not ts.is_empty() else Vector2.INF, ready)
		if ready == 1:
			fx({"kind": "glow", "pos": pos + Vector2(0, -20), "r": 26.0, "life": 0.3, "col": BLUE, "alpha": 0.35})
		return
	if cd <= 0.0:
		var ts: Array = g._nearest(1, _reach() + 30.0, pos)
		if ts.is_empty():
			cd = 0.1
		else:
			cd = 0.75 / stat(&"op_aspd")
			start_attack(ts[0].pos)


func _aim() -> float:
	var ts: Array = g._nearest(1, _reach() + 60.0, pos)
	if ts.is_empty():
		return facing_angle()
	var a: float = (ts[0].pos - pos).angle()
	face_to(a)
	return a


## 斩击弧光（Ninja Adventure Slash 调深海蓝：普通 / 重斩 / 潮汐全方向三条帧条；缺图退回程序双层弧）+ 水珠
func _slash(ang: float, half: float, r: float, main: Color, edge: Color, life: float) -> void:
	var name := "fx_slash_arc_deep"
	var sc: float = r * 1.15 / 40.0
	if half >= PI - 0.01:
		name = "fx_slash_circle_deep"
		sc = r * 2.0 / 56.0
	elif half > 1.6:
		name = "fx_slash_heavy_deep"
		sc = r * 1.2 / 28.0
	var at: Vector2 = pos + Vector2(0, -14) + (Vector2.ZERO if name == "fx_slash_circle_deep" else Vector2.from_angle(ang) * r * 0.5)
	if not g._fx_sprite(name, at, sc, ang if name != "fx_slash_circle_deep" else 0.0):
		g._slash_fx(pos + Vector2(0, -14), ang, half, r, main, "slash", life)
		g._slash_fx(pos + Vector2(0, -14), ang, half * 0.9, r * 0.9, edge, "slash", life * 0.7)
	var sp: Vector2 = pos + Vector2(0, -10) + Vector2.from_angle(ang) * r * 0.6
	for k in 5:
		fx({"kind": "mote", "pos": sp + Vector2(g.rng.randf_range(-12, 12), g.rng.randf_range(-8, 8)), "vel": Vector2.from_angle(ang + g.rng.randf_range(-0.8, 0.8)) * g.rng.randf_range(40, 110) + Vector2(0, -60), "life": 0.4, "col": DROP, "sz": 2.0, "grav": 260.0})


func _release() -> void:
	var ang := _aim()
	var dmg: float = 26.0 * _dmg_bonus() * (1.5 * skill_power() if tide > 0.0 else 1.0)
	var half: float = PI if tide > 0.0 else 1.4
	melee_hit("大剑", pos + Vector2(0, -10), ang, half, _reach(), dmg, 60.0)
	_slash(ang, half, _reach(), BLUE if tide <= 0.0 else Color(0.25, 0.4, 0.85), FOAM, 0.22)
	Sfx.play("swing", -12.0, 1.0, 0.08)
	swings += 1
	if elite >= 1 and swings % 3 == 0 and tide <= 0.0:
		var back: float = ang + PI
		melee_hit("反手斩", pos + Vector2(0, -10), back, 1.4, _reach(), dmg * 0.7, 60.0)
		_slash(back, 1.4, _reach(), FOAM, Color(1.2, 1.5, 1.7), 0.2)


func _hit_fx(e: Dictionary, origin: Vector2) -> void:
	var d: Vector2 = (e.pos - origin).normalized()
	fx({"kind": "line", "pos": e.pos + Vector2(0, -e.r * 0.5) - d.orthogonal() * 8.0, "to": e.pos + Vector2(0, -e.r * 0.5) + d.orthogonal() * 8.0, "life": 0.15, "col": FOAM, "w": 2.0})


func _release_skill() -> void:
	match cur_skill:
		0:
			# 潮涌斩：一次 ×2 宽幅横扫
			var ang := _aim()
			melee_hit("潮涌斩", pos + Vector2(0, -10), ang, 1.75, _reach() * 1.1, 26.0 * 2.0 * _dmg_bonus() * skill_power(), 120.0)
			_slash(ang, 1.75, _reach() * 1.1, Color(0.3, 0.5, 0.9), FOAM, 0.26)
			Sfx.play("swing_heavy", -8.0, 1.0, 0.05)
		1:
			_heavy(_aim())
		2:
			tide = S3_DUR
			fx({"kind": "ring", "pos": pos, "r": 120.0, "r0": 10.0, "life": 0.5, "col": BLUE, "floor": true})
			g.fx.append({"kind": "rays", "pos": pos + Vector2(0, -20), "life": 0.5, "max": 0.5, "col": BLUE})
			for k in 16:
				fx({"kind": "mote", "pos": pos + Vector2(g.rng.randf_range(-40, 40), 0), "vel": Vector2(g.rng.randf_range(-40, 40), g.rng.randf_range(-220, -100)), "life": 0.6, "col": DROP, "sz": 2.5, "grav": 300.0})
			g._show_banner("潮汐")
			Sfx.play("roar", -12.0, 1.5, 0.05)


func skill_active_left(i: int) -> float:
	return tide if i == 2 else 0.0


func skill_active_dur(i: int) -> float:
	return S3_DUR if i == 2 else 1.0


func _heavy(ang: float) -> void:
	var r: float = 150.0 * stat(&"op_range")
	melee_hit("重斩", pos + Vector2(0, -10), ang, 1.92, r, 26.0 * 3.0 * _dmg_bonus() * skill_power(), 240.0)
	_slash(ang, 1.92, r, Color(0.25, 0.4, 0.85), FOAM, 0.32)
	var c: Vector2 = pos + Vector2.from_angle(ang) * r * 0.45
	fx({"kind": "crack", "pos": c, "r": r * 0.6, "life": 0.45, "col": BLUE, "floor": true, "n": 9, "ang": ang})
	fx({"kind": "ring", "pos": c, "r": r * 0.7, "r0": 10.0, "life": 0.35, "col": BLUE, "floor": true, "w": 3.0})
	fx({"kind": "glow", "pos": c + Vector2(0, -10), "r": 34.0, "life": 0.2, "col": FOAM, "alpha": 0.5})
	g._fx_sprite("fx_water_splash", c + Vector2(0, 6), g.PX * 1.6, 0.0, false, true)
	for k in 18:
		fx({"kind": "mote", "pos": c + Vector2(g.rng.randf_range(-r * 0.3, r * 0.3), 0), "vel": Vector2(g.rng.randf_range(-70, 70), g.rng.randf_range(-260, -120)), "life": 0.6, "col": DROP, "sz": 2.5, "grav": 380.0})
	g.shake = maxf(g.shake, 4.0)
	Sfx.play("boom", -11.0, 0.8, 0.05)


func draw_auras() -> void:
	if tide > 0.0 and pos != Vector2.INF:
		g.draw_set_transform(pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
		g.draw_arc(Vector2.ZERO, _reach(), 0.0, TAU, 36, Color(BLUE.r, BLUE.g, BLUE.b, 0.3 + 0.1 * sin(g.t * 5.0)), 2.0)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_skill_over() -> void:
	# 重斩 / 潮汐起手：眼位一点红光（精二红瞳）
	if (acting() and act_kind == "skill" and fire_t >= 0.0) or tide > 0.0:
		var p := pos + Vector2(5.0 * face, -38)
		g.draw_circle(p, 3.0 + sin(g.t * 30.0), Color(2.4, 0.4, 0.4, 0.9))
		g.draw_circle(p, 7.0, Color(1.0, 0.2, 0.2, 0.25))


func status_items() -> Array:
	if tide > 0.0:
		return [["潮汐", BLUE]]
	return []
