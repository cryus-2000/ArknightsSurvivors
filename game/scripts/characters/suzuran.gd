## 铃兰（辅助，docs/23 §11.1）：减速光域（只减速不伤害）+ 向 2 名敌人发射追踪狐火；技能「光域」扩大光域并给其他干员加攻。
## 特效（docs/25）：狐火金。光域为地面淡金椭圆 + 边缘绕行的六团狐火；狐火弹金白火球带火舌尾；技能期间光点上升、博士缓慢回复。
extends "res://scripts/characters/character.gd"

const GOLD := Color(1.0, 0.82, 0.45)

var cd := 0.5
var field_t := 0.0
var mote_t := 0.0
var heal_acc := 0.0


func aura_radius() -> float:
	return (85.0 + 15.0 * elite) * stat(&"op_range") * (1.6 if field_t > 0.0 else 1.0)


func update(dt: float) -> void:
	cd -= dt
	_update_orbs(dt)
	if field_t > 0.0:
		field_t -= dt
		mote_t -= dt
		if mote_t <= 0.0:
			mote_t = 0.05
			var a: float = g.rng.randf() * TAU
			var rr: float = g.rng.randf() * aura_radius()
			fx({"kind": "mote", "pos": pos + Vector2(cos(a) * rr, sin(a) * rr * 0.55), "vel": Vector2(0, -40), "life": 0.7, "col": GOLD, "sz": 1.8})
		# 光域内的博士缓慢回复（原作：范围内友军回复）
		heal_acc += dt
		if heal_acc >= 1.0:
			heal_acc -= 1.0
			if g.hp < g.max_hp:
				g._heal(g.max_hp * 0.005)
		if field_t <= 0.0:
			g.stats.remove_source("suzuran_field")
			g._sync_stats()
	var rad := aura_radius()
	for j in g._query(pos, rad + 20.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or e.pos.distance_to(pos) > rad:
			continue
		e.slow = maxf(e.slow, 0.4 if field_t > 0.0 else 0.2)
		if elite >= 1:
			e["aura_weak"] = 0.2
	if acting():
		return
	if charge_skill(dt):
		start_skill(Vector2.INF)
		return
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
	var from := pos + Vector2(12.0 * face, -30)
	for k in ts.size():
		var d: Vector2 = (ts[k].pos - pos).normalized().rotated(0.6 * (1 if k % 2 == 0 else -1))
		g.bullets.append({"kind": "arcane", "pos": from, "vel": d * 330.0, "dmg": 16.0 * _dmg_bonus(),
			"life": 1.6, "r": 7.0, "aoe": 0.0, "home": ts[k], "turn": 7.0, "src": "狐火", "op": id, "fx_col": GOLD, "hidden": true, "etrail": 0.0})
	if not ts.is_empty():
		fx({"kind": "glow", "pos": from, "r": 10.0, "life": 0.15, "col": GOLD, "alpha": 0.5})
		Sfx.play("tentacle", -14.0, 1.6, 0.05)


## 狐火弹的火舌尾
func _update_orbs(dt: float) -> void:
	for b in g.bullets:
		if b.life <= 0.0 or b.get("op", "") != id or b.kind != "arcane":
			continue
		b.etrail = b.get("etrail", 0.0) - dt
		if b.etrail <= 0.0:
			b.etrail = 0.05
			fx({"kind": "flame", "pos": b.pos - b.vel.normalized() * 6.0, "vel": -b.vel * 0.08 + Vector2(0, -14), "life": 0.25, "col": GOLD, "sz": 7.0})


func _release_skill() -> void:
	field_t = 10.0 if elite >= 2 else 5.0
	heal_acc = 0.0
	# 其他干员攻击加成：只写入别的干员的 op:<id> 作用域，不给自己
	g.stats.remove_source("suzuran_field")
	for o in g.squad.ops:
		if o != self:
			g.stats.add(&"op_atk", "add", (0.35 if elite >= 2 else 0.2) * skill_power(), "suzuran_field", "op:" + o.id)
	g._sync_stats()
	g._show_banner("光域展开")
	fx({"kind": "ring", "pos": pos, "r": aura_radius(), "r0": 10.0, "life": 0.6, "col": GOLD, "floor": true})
	g.fx.append({"kind": "rays", "pos": pos + Vector2(0, -24), "life": 0.5, "max": 0.5, "col": GOLD})
	for k in 10:
		fx({"kind": "flame", "pos": pos + Vector2(0, -20), "vel": Vector2.from_angle(k * TAU / 10.0) * 120.0, "life": 0.5, "col": GOLD, "sz": 9.0, "drag": 2.5})


func _flame(p: Vector2, h: float, a: float) -> void:
	var wob: float = sin(g.t * 20.0 + p.x * 0.3) * 2.0
	g.draw_colored_polygon(PackedVector2Array([p + Vector2(-h * 0.35, 0), p + Vector2(wob, -h), p + Vector2(h * 0.35, 0)]), Color(GOLD.r, GOLD.g, GOLD.b, 0.75 * a))
	g.draw_colored_polygon(PackedVector2Array([p + Vector2(-h * 0.15, 0), p + Vector2(wob * 0.6, -h * 0.55), p + Vector2(h * 0.15, 0)]), Color(2.2, 2.0, 1.4, 0.8 * a))


func draw_auras() -> void:
	if pos == Vector2.INF:
		return
	var r := aura_radius()
	var on := field_t > 0.0
	g.draw_set_transform(pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
	g.draw_circle(Vector2.ZERO, r, Color(GOLD.r, GOLD.g, GOLD.b, 0.09 if on else 0.05))
	g.draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(GOLD.r, GOLD.g, GOLD.b, (0.45 if on else 0.25) + 0.06 * sin(g.t * 3.0)), 2.0)
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 边缘六团狐火绕行
	for k in 6:
		var a: float = g.t * 0.8 + k * TAU / 6.0
		_flame(pos + Vector2(4, 4) + Vector2(cos(a) * r, sin(a) * r * 0.55), 9.0 if on else 6.0, 0.9 if on else 0.6)


func _draw_skill_over() -> void:
	# 自绘狐火弹：金白火球
	for b in g.bullets:
		if b.life <= 0.0 or b.get("op", "") != id or b.kind != "arcane":
			continue
		g.draw_circle(b.pos, 10.0, Color(GOLD.r, GOLD.g, GOLD.b, 0.28))
		g.draw_circle(b.pos, 5.5, Color(2.2, 1.8, 1.0))
		g.draw_circle(b.pos, 2.5, Color(2.8, 2.7, 2.2))


func skill_active_left() -> float:
	return maxf(0.0, field_t)


func skill_active_dur() -> float:
	return 10.0 if elite >= 2 else 5.0


func status_items() -> Array:
	if field_t > 0.0:
		return [["光域", GOLD]]
	return []
