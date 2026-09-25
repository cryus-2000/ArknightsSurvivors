## 艾雅法拉（术师，docs/23 §11.1）：熔岩弹（范围法伤）；技能「火山」在敌群最密处连续喷发并留下熔岩。
## 熔岩弹复用 game.gd 的 fire 子弹（带 src），喷发与熔岩是本干员自己的实体。
extends "res://scripts/characters/character.gd"

var cd := 0.6
var erupt := 0              # 剩余喷发次数
var erupt_t := 0.0
var lava: Array = []        # {pos, r, t, tick, dmg}
var burns: Array = []       # 点燃：{e, t, dps}


func _aoe() -> float:
	return 58.0 * stat(&"op_range") * (1.25 if elite >= 1 else 1.0)


func update(dt: float) -> void:
	cd -= dt
	_update_ground(dt)
	if erupt > 0:
		erupt_t -= dt
		if erupt_t <= 0.0:
			erupt_t = 0.2
			erupt -= 1
			var c: Vector2 = g._densest_point(440.0 * stat(&"op_range"), pos)
			if c == Vector2.INF:
				var ts: Array = g._nearest(1, 440.0 * stat(&"op_range"), pos)
				if ts.is_empty():
					erupt = 0
					return
				c = ts[0].pos
			_erupt(c + Vector2(g.rng.randf_range(-50, 50), g.rng.randf_range(-40, 40)))
		return
	if acting():
		return
	if charge_skill(dt):
		var ts: Array = g._nearest(1, 440.0, pos)
		start_skill(ts[0].pos if not ts.is_empty() else Vector2.INF)
		return
	if cd <= 0.0:
		var ts: Array = g._nearest(1, 380.0 * stat(&"op_range"), pos)
		if ts.is_empty():
			cd = 0.2
		else:
			cd = 1.2 / stat(&"op_aspd")
			start_attack(ts[0].pos)


func _release() -> void:
	var ts: Array = g._nearest(1, 420.0 * stat(&"op_range"), pos)
	if ts.is_empty():
		return
	_cast(pos + Vector2(10.0 * face, -30), ts[0].pos, 22.0, _aoe(), true)


func _cast(from: Vector2, target: Vector2, base_dmg: float, aoe: float, split: bool) -> void:
	var d: Vector2 = (target - from).normalized()
	face = signf(d.x) if absf(d.x) > 0.01 else face
	g.bullets.append({"kind": "fire", "pos": from, "vel": d * 360.0, "dmg": base_dmg * _dmg_bonus(), "life": 1.3, "r": 8.0,
		"aoe": aoe, "src": "火山弹", "op": id, "on_hit": self if (elite >= 1 or (split and elite >= 2)) else null, "split": split})
	Sfx.play("oil", -12.0, 1.2, 0.05)


## fire 子弹爆炸后由 game.gd 回调（有 on_hit 字段时）：点燃 / 分裂
func bullet_exploded(b: Dictionary) -> void:
	if elite >= 1:
		for e in g._arc_hit(b.pos, 0.0, PI, b.aoe):
			if not e.dead:
				burns.append({"e": e, "t": 3.0, "dps": b.dmg * 0.1})
	if elite >= 2 and b.get("split", false):
		for k in 2:
			var a: float = g.rng.randf() * TAU
			_cast(b.pos, b.pos + Vector2.from_angle(a) * 120.0, 22.0 * 0.5, b.aoe * 0.6, false)


func _release_skill() -> void:
	erupt = 10 if elite >= 2 else 6
	erupt_t = 0.0
	g.fx.append({"kind": "rays", "pos": pos + Vector2(0, -20), "life": 0.5, "max": 0.5, "col": Color(1.0, 0.45, 0.2)})


func _erupt(c: Vector2) -> void:
	var r: float = 75.0 * stat(&"op_range")
	area_hit("火山", c, r, 20.0 * 1.8 * _dmg_bonus() * skill_power())
	g.fx.append({"kind": "pillar", "pos": c, "life": 0.45, "max": 0.45, "col": Color(1.0, 0.4, 0.15)})
	if not g._fx_sprite("fx_fire_explode", c, clampf(r / g.EXPLODE_R_PX, 1.5, 3.0)):
		g.fx.append({"kind": "explode", "pos": c, "r": r, "life": 0.4, "max": 0.4, "col": Color(1.0, 0.45, 0.2)})
	g.fx.append({"kind": "quake", "pos": c, "r": r, "life": 0.4, "max": 0.4, "col": Color(1.0, 0.5, 0.2)})
	lava.append({"pos": c, "r": r * 0.8 * (1.4 if elite >= 2 else 1.0), "t": 3.0, "tick": 0.0, "dmg": 20.0 * 0.25 * _dmg_bonus() * skill_power()})
	Sfx.play("boom", -13.0, 0.9, 0.1)


func _update_ground(dt: float) -> void:
	for l in lava:
		l.t -= dt
		l.tick -= dt
		if l.tick <= 0.0:
			l.tick = 0.5
			area_hit("熔岩", l.pos, l.r, l.dmg)
	lava = lava.filter(func(l): return l.t > 0.0)
	for b in burns:
		b.t -= dt
		if b.e.dead:
			b.t = 0.0
			continue
		if int((b.t + dt) * 2.0) != int(b.t * 2.0):
			g._hit("点燃")
			g._damage(b.e, b.dps * 0.5)
	burns = burns.filter(func(b): return b.t > 0.0)


func draw_entities_floor() -> void:
	for l in lava:
		var a: float = clampf(l.t / 0.6, 0.0, 1.0)
		g.draw_set_transform(l.pos, 0.0, Vector2(1.0, 0.55))
		g.draw_circle(Vector2.ZERO, l.r, Color(0.9, 0.25, 0.05, 0.28 * a))
		g.draw_circle(Vector2.ZERO, l.r * 0.6, Color(1.6, 0.6, 0.1, 0.22 * a + 0.06 * sin(g.t * 9.0 + l.pos.x)))
		g.draw_arc(Vector2.ZERO, l.r, 0.0, TAU, 24, Color(1.8, 0.7, 0.2, 0.5 * a), 2.0)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func status_items() -> Array:
	if erupt > 0:
		return [["火山", Color(1.0, 0.5, 0.2)]]
	return []
