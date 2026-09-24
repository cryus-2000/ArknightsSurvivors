## 术师干员（编队制）：向最近敌人发射爆裂法术，命中范围爆炸（法术）；技能「火雨」向敌群最密处连投。
extends "res://scripts/characters/character.gd"

var cd := 0.6
var rain := 0
var rain_t := 0.0


func _aoe() -> float:
	return (55.0 + 10.0 * elite) * stat(&"op_range") * (1.3 if elite >= 1 else 1.0)


func update(dt: float) -> void:
	cd -= dt
	if charge_skill(dt):
		rain = 5 if elite >= 2 else 3
		rain_t = 0.0
	if rain > 0:
		rain_t -= dt
		if rain_t <= 0.0:
			rain_t = 0.18
			rain -= 1
			var c: Vector2 = g._densest_point(420.0, pos)
			if c == Vector2.INF:
				var ts: Array = g._nearest(1, 420.0, pos)
				if ts.is_empty():
					rain = 0
					return
				c = ts[0].pos
			_cast(c + Vector2(g.rng.randf_range(-40, 40), g.rng.randf_range(-40, 40)), 1.4, true)
		return
	if cd <= 0.0:
		var ts: Array = g._nearest(1, 360.0 * stat(&"op_range"), pos)
		if ts.is_empty():
			cd = 0.2
		else:
			cd = 1.25 / stat(&"op_aspd")
			start_attack(ts[0].pos)


func _release() -> void:
	var ts: Array = g._nearest(1, 400.0 * stat(&"op_range"), pos)
	if ts.is_empty():
		return
	_cast(ts[0].pos, 1.0, false)


func _cast(target: Vector2, mult: float, big: bool) -> void:
	var d: Vector2 = (target - pos).normalized()
	face = signf(d.x) if absf(d.x) > 0.01 else face
	g.bullets.append({"kind": "fire", "pos": pos + Vector2(0, -14), "vel": d * 340.0, "dmg": 20.0 * _dmg_bonus() * mult, "life": 1.3,
		"r": 8.0, "aoe": _aoe() * (1.3 if big else 1.0), "slow": elite >= 2, "op": id})
	Sfx.play("oil", -12.0, 1.4, 0.05)


func status_items() -> Array:
	if rain > 0:
		return [["火雨", Color(0.8, 0.5, 1.0)]]
	return []
