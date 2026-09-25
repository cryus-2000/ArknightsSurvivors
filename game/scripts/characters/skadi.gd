## 斯卡蒂（近卫，docs/23 §10 / §11.1）：近战输出。前压到博士身边的敌人面前高频横扫大剑；
## 技能「重斩」：高举下劈，前方大范围重击并击退；精二追加第二次下劈。
extends "res://scripts/characters/character.gd"

const LEASH := 160.0

var cd := 0.3
var swings := 0               # 横扫计数（天赋：每第 3 次追加反手斩）
var second_t := -1.0          # 精二：第二次下劈倒计时
var second_ang := 0.0


func _reach() -> float:
	return 88.0 * stat(&"op_range")


func follow_target(slot_pos: Vector2) -> Vector2:
	var p := melee_spot(LEASH, 30.0)
	return p if p != Vector2.INF else slot_pos


func update(dt: float) -> void:
	cd -= dt
	if second_t >= 0.0:
		second_t -= dt
		if second_t < 0.0:
			second_t = -1.0
			_heavy(second_ang, 0.6)
	if acting():
		return
	if charge_skill(dt):
		var ts: Array = g._nearest(1, 200.0, pos)
		start_skill(ts[0].pos if not ts.is_empty() else Vector2.INF)
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


func _release() -> void:
	var ang := _aim()
	var dmg: float = 26.0 * _dmg_bonus()
	melee_hit("大剑", pos + Vector2(0, -10), ang, 1.4, _reach(), dmg, 60.0)
	g._slash_fx(pos + Vector2(0, -14), ang, 1.4, _reach(), Color(0.75, 0.9, 1.0))
	Sfx.play("swing", -12.0, 1.0, 0.08)
	swings += 1
	if elite >= 1 and swings % 3 == 0:
		var back: float = ang + PI
		melee_hit("反手斩", pos + Vector2(0, -10), back, 1.4, _reach(), dmg * 0.7, 60.0)
		g._slash_fx(pos + Vector2(0, -14), back, 1.4, _reach(), Color(0.55, 0.75, 1.0))


func _release_skill() -> void:
	var ang := _aim()
	_heavy(ang, 1.0)
	if elite >= 2:
		second_t = 0.3
		second_ang = ang


func _heavy(ang: float, mult: float) -> void:
	var r: float = 150.0 * stat(&"op_range") * (1.2 if elite >= 2 else 1.0)
	melee_hit("重斩", pos + Vector2(0, -10), ang, 1.92, r, 26.0 * 3.0 * mult * _dmg_bonus() * skill_power(), 240.0)
	g._slash_fx(pos + Vector2(0, -14), ang, 1.92, r, Color(0.6, 0.85, 1.0), "slash", 0.3)
	g.fx.append({"kind": "quake", "pos": pos + Vector2.from_angle(ang) * r * 0.45, "r": r * 0.6, "life": 0.4, "max": 0.4, "col": Color(0.6, 0.85, 1.0)})
	g.shake = maxf(g.shake, 4.0)
	Sfx.play("boom", -11.0, 0.8, 0.05)
