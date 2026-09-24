## 医疗干员（编队制）：周期性治疗博士（与骑士同伴）；博士满血时向最近敌人投掷小法术，避免纯空位；技能「急救」。
extends "res://scripts/characters/character.gd"

var cd := 1.0
var guard_t := 0.0        # 精二：溢出治疗转为减伤的剩余时间


func _heal_mult() -> float:
	return stat(&"op_atk") * g.ally_mult * (1.5 if elite >= 1 else 1.0)


func update(dt: float) -> void:
	cd -= dt
	guard_t = maxf(0.0, guard_t - dt)
	if charge_skill(dt):
		var h: float = g.max_hp * 0.15 * _heal_mult()
		g._heal(h)
		g.nerve = 0.0
		if elite >= 2 and g.shield_max > 0 and g.shield < g.shield_max:
			g.shield += 1
		g._add_text(g.ppos + Vector2(0, -96), "急救 +%d" % int(h), Color(0.5, 1.0, 0.6), 18)
		g.fx.append({"kind": "ring", "pos": g.ppos, "r": 60.0, "life": 0.5, "max": 0.5, "col": Color(0.5, 1.0, 0.6)})
		start_attack(g.ppos)
		return
	if cd <= 0.0:
		cd = 3.5 / stat(&"op_aspd")
		if g.hp < g.max_hp or (g.knight.alive and g.knight.hp < g.knight.maxhp):
			start_attack(g.ppos)
		else:
			var ts: Array = g._nearest(1, 300.0, pos)
			if not ts.is_empty():
				var d: Vector2 = (ts[0].pos - pos).normalized()
				face = signf(d.x) if absf(d.x) > 0.01 else face
				g.bullets.append({"kind": "arcane", "pos": pos + Vector2(0, -16), "vel": d * 300.0, "dmg": 10.0 * _dmg_bonus(), "life": 1.2, "r": 6.0, "aoe": 0.0, "home": ts[0], "turn": 6.0, "op": id})


func _release() -> void:
	if g.knight.alive:
		g.knight.heal(g.knight.maxhp * 0.05)
	if g.hp < g.max_hp:
		var h: float = g.max_hp * 0.035 * _heal_mult()
		var over: float = maxf(0.0, g.hp + h - g.max_hp)
		g._heal(h)
		if elite >= 2 and over > 0.0:
			guard_t = 5.0
		g._add_text(g.ppos + Vector2(0, -90), "+%d" % int(h), Color(0.5, 1.0, 0.6), 16)
		g.fx.append({"kind": "ring", "pos": g.ppos, "r": 26.0, "life": 0.4, "max": 0.4, "col": Color(0.5, 1.0, 0.6)})
		for k in 6:
			g.fx.append({"kind": "cross", "pos": g.ppos + Vector2(randf_range(-22, 22), randf_range(-50, -5)), "life": 0.9, "max": 0.9,
				"delay": k * 0.08, "sz": randf_range(3.0, 5.0)})
		g.fx.append({"kind": "beam", "a": pos + Vector2(0, -20), "b": g.ppos + Vector2(0, -24), "life": 0.3, "max": 0.3, "col": Color(0.5, 1.0, 0.6), "w": 3.0})


## 精二：溢出治疗后 5 秒博士受伤 -20%（game.gd _enemy_hit 查询）
func dmg_taken_mult() -> float:
	return 0.8 if guard_t > 0.0 else 1.0


func status_items() -> Array:
	if guard_t > 0.0:
		return [["庇护", Color(0.5, 1.0, 0.6)]]
	return []
