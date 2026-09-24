## 狙击干员（编队制，docs/23 §10）：远程单体，优先精英 / Boss 与高血量目标；普攻命中流血；技能「连射」。
extends "res://scripts/characters/character.gd"

var cd := 0.5
var volley := 0            # 连射剩余发数
var volley_t := 0.0


func update(dt: float) -> void:
	cd -= dt
	if charge_skill(dt):
		volley = 5 if elite >= 2 else 3
		volley_t = 0.0
	if volley > 0:
		volley_t -= dt
		if volley_t <= 0.0:
			volley_t = 0.12
			volley -= 1
			_shoot(2.0, elite >= 2)
		return
	if cd <= 0.0:
		var tgt: Dictionary = g._sniper_target(pos, 460.0 * stat(&"op_range"))
		if tgt.is_empty():
			cd = 0.2
		else:
			cd = 0.8 / stat(&"op_aspd")
			start_attack(tgt.pos)


func _release() -> void:
	_shoot(1.0, false)


func _shoot(mult: float, pierce: bool) -> void:
	var tgt: Dictionary = g._sniper_target(pos, 500.0 * stat(&"op_range"))
	if tgt.is_empty():
		return
	var d: Vector2 = (tgt.pos - pos).normalized()
	face = signf(d.x) if absf(d.x) > 0.01 else face
	var dmg: float = 24.0 * _dmg_bonus() * mult
	if elite >= 1 and (tgt.elite or tgt.boss):
		dmg *= 1.3
	if elite >= 2 and g.rng.randf() < 0.2:
		dmg *= 2.0
	g.bullets.append({"kind": "arrow", "pos": pos + Vector2(0, -12), "vel": d * 900.0, "dmg": dmg, "life": 0.8, "r": 5.0, "aoe": 0.0, "pierce": pierce, "op": id})
	g.fx.append({"kind": "ring", "pos": pos + Vector2(0, -12) + d * 12.0, "r": 10.0, "life": 0.12, "max": 0.12, "col": Color(1.0, 0.9, 0.7)})
	Sfx.play("swing", -16.0, 1.8)


func status_items() -> Array:
	if volley > 0:
		return [["连射", Color(1.0, 0.9, 0.6)]]
	return []
