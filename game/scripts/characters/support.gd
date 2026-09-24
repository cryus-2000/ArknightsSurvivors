## 辅助干员（编队制）：减速光环（只减速不伤害）+ 向 2 名敌人发射追踪法术；技能「领域」扩大光环并给其他干员加攻。
extends "res://scripts/characters/character.gd"

var cd := 0.5
var field_t := 0.0


func aura_radius() -> float:
	return (85.0 + 15.0 * elite) * stat(&"op_range") * (1.6 if field_t > 0.0 else 1.0)


func update(dt: float) -> void:
	cd -= dt
	if field_t > 0.0:
		field_t -= dt
		if field_t <= 0.0:
			g.stats.remove_source("support_field")
			g._sync_stats()
	if charge_skill(dt):
		field_t = 10.0 if elite >= 2 else 5.0
		g.stats.remove_source("support_field")
		g.stats.add(&"op_atk", "add", 0.35 if elite >= 2 else 0.2, "support_field", "squad")
		g._sync_stats()
		g._show_banner("领域展开")
		g.fx.append({"kind": "ring", "pos": pos, "r": aura_radius(), "life": 0.6, "max": 0.6, "col": Color(0.6, 0.7, 1.0)})
	var rad := aura_radius()
	for j in g._query(pos, rad + 20.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or e.pos.distance_to(pos) > rad:
			continue
		e.slow = maxf(e.slow, 0.4 if field_t > 0.0 else 0.2)
		if elite >= 1:
			e["aura_weak"] = 0.2
	if cd <= 0.0:
		var ts: Array = g._nearest(2, 380.0 * stat(&"op_range"), pos)
		if ts.is_empty():
			cd = 0.2
		else:
			cd = 1.2 / stat(&"op_aspd")
			start_attack(ts[0].pos)


func _release() -> void:
	var n: int = 3 if elite >= 1 else 2
	var ts: Array = g._nearest(n, 400.0 * stat(&"op_range"), pos)
	for k in ts.size():
		var d: Vector2 = (ts[k].pos - pos).normalized().rotated(0.6 * (1 if k == 0 else -1))
		g.bullets.append({"kind": "arcane", "pos": pos + Vector2(0, -16), "vel": d * 330.0, "dmg": 16.0 * _dmg_bonus(),
			"life": 1.6, "r": 7.0, "aoe": 0.0, "home": ts[k], "turn": 7.0, "op": id})
	if not ts.is_empty():
		Sfx.play("tentacle", -14.0, 1.6, 0.05)


func draw_auras() -> void:
	if pos == Vector2.INF:
		return
	var col := Color(0.6, 0.7, 1.0, 0.3) if field_t > 0.0 else Color(0.5, 0.8, 1.0, 0.18 + 0.06 * sin(g.t * 3.0))
	g.draw_arc(pos, aura_radius(), 0.0, TAU, 40, col, 2.0)


func status_items() -> Array:
	if field_t > 0.0:
		return [["领域", Color(0.6, 0.7, 1.0)]]
	return []
