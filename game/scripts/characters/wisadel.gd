## 维什戴尔（狙击，docs/23 §11.1）：炮击 → 余震爆炸 → 击杀再爆。
## 炮弹是本干员自己的实体（抛物线飞行 → 落点爆炸 → 0.45 秒后原地余震），不走 game.gd 的子弹表。
extends "res://scripts/characters/character.gd"

var cd := 0.6
var shells: Array = []       # {from, to, t, dur, dmg, r, src, tail}
var quakes: Array = []       # 余震：{pos, t, dmg, r}
var volley := 0              # 饱和炮击剩余发数
var volley_t := 0.0
var volley_tg: Array = []


func _aoe() -> float:
	return 52.0 * stat(&"op_range") * (1.15 if elite >= 1 else 1.0)


func update(dt: float) -> void:
	cd -= dt
	_update_shells(dt)
	if volley > 0:
		volley_t -= dt
		if volley_t <= 0.0:
			volley_t = 0.08
			volley -= 1
			var tg: Dictionary = volley_tg[volley % volley_tg.size()] if not volley_tg.is_empty() else {}
			var to: Vector2 = tg.pos if not tg.is_empty() and not tg.dead else _fallback_spot()
			if to != Vector2.INF:
				_fire(to + Vector2(g.rng.randf_range(-24, 24), g.rng.randf_range(-24, 24)), 34.0 * 1.6 * skill_power(), "饱和炮击", 1.2)
		return
	if acting():
		return
	if charge_skill(dt):
		var tg: Dictionary = g._sniper_target(pos, 520.0 * stat(&"op_range"))
		start_skill(tg.pos if not tg.is_empty() else Vector2.INF)
		return
	if cd <= 0.0:
		var tgt: Dictionary = g._sniper_target(pos, 480.0 * stat(&"op_range"))
		if tgt.is_empty():
			cd = 0.2
		else:
			cd = 1.4 / stat(&"op_aspd")
			start_attack(tgt.pos)


func _fallback_spot() -> Vector2:
	var ts: Array = g._nearest(1, 520.0 * stat(&"op_range"), pos)
	return ts[0].pos if not ts.is_empty() else Vector2.INF


func _release() -> void:
	var tgt: Dictionary = g._sniper_target(pos, 520.0 * stat(&"op_range"))
	if tgt.is_empty():
		return
	_fire(tgt.pos, 34.0, "炮击", 1.0)


func _release_skill() -> void:
	# 饱和炮击：精英 / Boss 优先，其余按距离，最多 n 个不同目标轮流落弹
	var n: int = 8 if elite >= 2 else 5
	volley_tg = g._nearest(n, 520.0 * stat(&"op_range"), pos)
	var best: Dictionary = g._sniper_target(pos, 520.0 * stat(&"op_range"))
	if not best.is_empty():
		volley_tg.push_front(best)
	volley = n
	volley_t = 0.0
	g.fx.append({"kind": "ring", "pos": _muzzle(), "r": 26.0, "life": 0.3, "max": 0.3, "col": Color(1.0, 0.45, 0.35)})
	Sfx.play("boom", -12.0, 0.8, 0.05)


func _muzzle() -> Vector2:
	return pos + Vector2(14.0 * face, -34)


func _fire(to: Vector2, base_dmg: float, src: String, size: float) -> void:
	face = signf(to.x - pos.x) if absf(to.x - pos.x) > 2.0 else face
	var from := _muzzle()
	var dur: float = clampf(from.distance_to(to) / 900.0, 0.18, 0.5)
	shells.append({"from": from, "to": to, "t": 0.0, "dur": dur, "dmg": base_dmg * _dmg_bonus(), "r": _aoe() * size, "src": src})
	g.fx.append({"kind": "spark", "pos": from, "vel": (to - from).normalized() * 160.0, "sz": 4.0, "life": 0.15, "max": 0.15, "col": Color(1.0, 0.75, 0.5)})
	Sfx.play("swing", -15.0, 0.7, 0.05)


func _update_shells(dt: float) -> void:
	for s in shells:
		s.t += dt
		if s.t >= s.dur:
			_explode(s.to, s.dmg, s.r, s.src, 0)
			# 余震：普攻与 E2 技能都有；E1 起伤害 40% → 60%
			if s.src == "炮击" or elite >= 2:
				quakes.append({"pos": s.to, "t": 0.45, "dmg": s.dmg * (0.6 if elite >= 1 else 0.4), "r": s.r * 1.2})
	shells = shells.filter(func(s): return s.t < s.dur)
	for q in quakes:
		q.t -= dt
		if q.t <= 0.0:
			_explode(q.pos, q.dmg, q.r, "余震", 0)
	quakes = quakes.filter(func(q): return q.t > 0.0)


## 爆炸：范围伤害；E1 起被炸死的敌人原地殉爆（depth 限制连锁层数，E2 可连锁一次）
func _explode(c: Vector2, dmg: float, r: float, src: String, depth: int) -> void:
	var killed: Array = []
	for e in g._arc_hit(c, 0.0, PI, r):
		g._hit(src)
		g._damage(e, dmg)
		if not e.dead and g.rfx.sniper_execute(e, g.hit):
			g._hit("真实")
			g._damage(e, e.hp + 1.0)
		if e.dead:
			killed.append(e.pos)
	if src == "余震":
		g.fx.append({"kind": "quake", "pos": c, "r": r, "life": 0.35, "max": 0.35, "col": Color(1.0, 0.6, 0.45)})
		g.fx.append({"kind": "ring", "pos": c, "r": r, "life": 0.3, "max": 0.3, "col": Color(1.0, 0.55, 0.4)})
	elif not g._fx_sprite("fx_missile_explode", c, clampf(r / g.EXPLODE_R_PX, 1.5, 3.0)):
		g.fx.append({"kind": "explode", "pos": c, "r": r, "life": 0.4, "max": 0.4, "col": Color(1.0, 0.45, 0.35)})
	Sfx.play("boom", -16.0 if src == "余震" else -13.0, 1.2, 0.1)
	var max_depth: int = 2 if elite >= 2 else 1
	if elite >= 1 and depth < max_depth:
		for k in mini(killed.size(), 3):
			_explode(killed[k], dmg * 0.4, r * 0.8, "殉爆", depth + 1)


func _draw_skill_over() -> void:
	for s in shells:
		var k: float = s.t / s.dur
		var p: Vector2 = s.from.lerp(s.to, k) + Vector2(0, -sin(k * PI) * minf(120.0, s.from.distance_to(s.to) * 0.35))
		g.draw_circle(p, 5.0, Color(0.12, 0.08, 0.1))
		g.draw_circle(p, 3.0, Color(2.2, 1.2, 0.8))
	for q in quakes:
		var a: float = 1.0 - q.t / 0.45
		g.draw_arc(q.pos, q.r * (0.3 + 0.2 * a), 0.0, TAU, 20, Color(1.0, 0.5, 0.35, 0.4 * a), 2.0)


func status_items() -> Array:
	if volley > 0:
		return [["饱和炮击", Color(1.0, 0.55, 0.45)]]
	return []
