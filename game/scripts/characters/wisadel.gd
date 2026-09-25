## 维什戴尔（狙击，契约 v2.1）：炮击 → 余震爆炸 → 残影殉爆。
## S1 灰烬弹幕：接下来 3 发炮击 ×1.5 且必余震；S2 凋零处刑：一发 ×3 重炮 + 眩晕；S3 饱和炮击：8 发连射，每发余震。
## 炮弹是本干员自己的实体（抛物线飞行 → 落点爆炸 → 0.45 秒后原地余震），不走 game.gd 的子弹表。
## 特效（docs/25）：黑红。炮弹黑体红尾、落点黑烟 + 红环、余震地面双环 + 黑雾丝、殉爆先浮起黑色残影再炸并眩晕。
extends "res://scripts/characters/character.gd"

const RED := Color(0.95, 0.22, 0.2)
const DARK := Color(0.1, 0.06, 0.08)

var cd := 0.6
var shells: Array = []       # {from, to, t, dur, dmg, r, src, trail, quake, stun}
var quakes: Array = []       # 余震：{pos, t, dmg, r}
var shades: Array = []       # 残影（殉爆前摇）：{pos, t, dmg, r, depth}
var ash := 0                 # S1：剩余强化炮击数
var volley := 0              # S3：饱和炮击剩余发数
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
				_fire(to + Vector2(g.rng.randf_range(-24, 24), g.rng.randf_range(-24, 24)), 34.0 * 1.6 * skill_power(), "饱和炮击", 1.2, true, 0.0)
		return
	if acting():
		return
	var ready := charge_skills(dt)
	if ready == 0:
		spend_sp(0)
		ash = 3
		fx({"kind": "glow", "pos": _muzzle(), "r": 16.0, "life": 0.3, "col": RED, "alpha": 0.5})
		g._add_text(pos + Vector2(0, -80), "灰烬弹幕", RED, 14)
		return
	if ready > 0:
		var tg: Dictionary = g._sniper_target(pos, 520.0 * stat(&"op_range"))
		start_skill(tg.pos if not tg.is_empty() else Vector2.INF, ready)
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
	if ash > 0:
		ash -= 1
		_fire(tgt.pos, 34.0 * 1.5 * skill_power(), "炮击", 1.1, true, 0.0)
	else:
		_fire(tgt.pos, 34.0, "炮击", 1.0, true, 0.0)


func _release_skill() -> void:
	match cur_skill:
		1:
			# 凋零处刑：一发重炮，眩晕 + 余震
			var tgt: Dictionary = g._sniper_target(pos, 540.0 * stat(&"op_range"))
			if tgt.is_empty():
				return
			_fire(tgt.pos, 34.0 * 3.0 * skill_power(), "凋零处刑", 1.6, true, 0.8)
			fx({"kind": "glow", "pos": _muzzle(), "r": 28.0, "life": 0.3, "col": RED, "alpha": 0.6})
			fx_sparks(_muzzle(), RED, 10, 200.0, 0.3)
			g.shake = maxf(g.shake, 3.0)
			Sfx.play("boom", -8.0, 0.6, 0.05)
		2:
			# 饱和炮击：精英 / Boss 优先，其余按距离，最多 8 个不同目标轮流落弹
			var n := 8
			volley_tg = g._nearest(n, 520.0 * stat(&"op_range"), pos)
			var best: Dictionary = g._sniper_target(pos, 520.0 * stat(&"op_range"))
			if not best.is_empty():
				volley_tg.push_front(best)
			volley = n
			volley_t = 0.0
			fx({"kind": "glow", "pos": _muzzle(), "r": 24.0, "life": 0.3, "col": RED, "alpha": 0.5})
			fx_sparks(_muzzle(), RED, 8, 160.0, 0.3)
			Sfx.play("boom", -12.0, 0.8, 0.05)


func skill_active_left(i: int) -> float:
	return float(volley) * 0.08 if i == 2 else 0.0


func _muzzle() -> Vector2:
	return pos + Vector2(14.0 * face, -34)


func _fire(to: Vector2, base_dmg: float, src: String, size: float, quake: bool, stun: float) -> void:
	face = signf(to.x - pos.x) if absf(to.x - pos.x) > 2.0 else face
	var from := _muzzle()
	var dur: float = clampf(from.distance_to(to) / 900.0, 0.18, 0.5)
	shells.append({"from": from, "to": to, "t": 0.0, "dur": dur, "dmg": base_dmg * _dmg_bonus(), "r": _aoe() * size, "src": src, "trail": 0.0, "quake": quake, "stun": stun})
	# 炮口：暗红闪 + 后坐火星
	fx({"kind": "glow", "pos": from, "r": 12.0, "life": 0.12, "col": RED, "alpha": 0.6})
	for k in 3:
		fx({"kind": "spark", "pos": from, "vel": (from - to).normalized().rotated(g.rng.randf_range(-0.6, 0.6)) * g.rng.randf_range(60, 140), "life": 0.2, "col": Color(1.0, 0.7, 0.5), "sz": 2.0, "drag": 3.0})
	Sfx.play("swing", -15.0, 0.7, 0.05)


func _shell_pos(s: Dictionary) -> Vector2:
	var k: float = s.t / s.dur
	return s.from.lerp(s.to, k) + Vector2(0, -sin(k * PI) * minf(120.0, s.from.distance_to(s.to) * 0.35))


func _update_shells(dt: float) -> void:
	for s in shells:
		s.t += dt
		s.trail -= dt
		if s.trail <= 0.0 and s.t < s.dur:
			s.trail = 0.03
			fx({"kind": "spark", "pos": _shell_pos(s), "vel": Vector2(g.rng.randf_range(-15, 15), g.rng.randf_range(-10, 20)), "life": 0.22, "col": RED, "sz": 2.0})
		if s.t >= s.dur:
			_explode(s.to, s.dmg, s.r, s.src, 0, s.stun)
			# 余震：E1 起伤害 40% → 60%
			if s.quake:
				quakes.append({"pos": s.to, "t": 0.45, "dmg": s.dmg * (0.6 if elite >= 1 else 0.4), "r": s.r * 1.2})
	shells = shells.filter(func(s): return s.t < s.dur)
	for q in quakes:
		q.t -= dt
		if q.t <= 0.0:
			_explode(q.pos, q.dmg, q.r, "余震", 0, 0.0)
	quakes = quakes.filter(func(q): return q.t > 0.0)
	for sh in shades:
		sh.t -= dt
		if sh.t <= 0.0:
			_explode(sh.pos, sh.dmg, sh.r, "殉爆", sh.depth, 0.6)
	shades = shades.filter(func(sh): return sh.t > 0.0)


## 爆炸：范围伤害；E1 起被炸死的敌人留下残影，0.25 秒后殉爆并眩晕
func _explode(c: Vector2, dmg: float, r: float, src: String, depth: int, stun: float) -> void:
	var killed: Array = []
	for e in g._arc_hit(c, 0.0, PI, r):
		g._hit(src)
		g._damage(e, dmg)
		if not e.dead and g.rfx.sniper_execute(e, g.hit):
			g._hit("真实")
			g._damage(e, e.hp + 1.0)
		if e.dead:
			killed.append(e.pos)
		elif stun > 0.0 and not e.boss:
			e.stun = maxf(e.stun, stun * (0.5 if e.elite else 1.0))
	match src:
		"余震":
			fx({"kind": "ring", "pos": c, "r": r, "r0": r * 0.2, "life": 0.35, "col": RED, "floor": true, "w": 3.0})
			fx({"kind": "ring", "pos": c, "r": r * 0.65, "r0": r * 0.1, "life": 0.45, "col": Color(1.0, 0.45, 0.35), "floor": true, "w": 2.0})
			fx({"kind": "crack", "pos": c, "r": r * 0.7, "life": 0.35, "col": RED, "floor": true, "n": 7, "ang": c.x * 0.01})
			for k in 3:
				fx({"kind": "wisp", "pos": c + Vector2(g.rng.randf_range(-r * 0.4, r * 0.4), 0), "vel": Vector2(0, -45.0), "life": 0.55, "col": DARK, "ph": g.rng.randf() * TAU})
		"殉爆":
			fx({"kind": "glow", "pos": c, "r": r * 0.7, "life": 0.2, "col": RED, "alpha": 0.6})
			fx({"kind": "smoke", "pos": c, "r": r * 0.8, "life": 0.45, "col": DARK})
			fx({"kind": "ring", "pos": c, "r": r, "life": 0.3, "col": RED, "w": 3.0})
			fx_sparks(c, RED, 8, 220.0, 0.35)
		_:
			fx({"kind": "glow", "pos": c, "r": r * 0.6, "life": 0.16, "col": Color(1.4, 0.5, 0.4), "alpha": 0.7})
			fx({"kind": "smoke", "pos": c, "r": r, "life": 0.5, "col": DARK})
			fx({"kind": "ring", "pos": c, "r": r, "r0": r * 0.3, "life": 0.3, "col": RED, "w": 3.0})
			for k in 5:
				fx({"kind": "shard", "pos": c, "vel": Vector2.from_angle(g.rng.randf() * TAU) * g.rng.randf_range(80, 200) + Vector2(0, -80), "life": 0.45, "col": Color(0.3, 0.2, 0.22), "sz": 5.0, "ang": g.rng.randf() * TAU, "spin": 12.0, "grav": 400.0})
			fx_sparks(c, Color(1.0, 0.55, 0.4), 6, 200.0, 0.3)
	Sfx.play("boom", -16.0 if src == "余震" else -13.0, 1.2, 0.1)
	if elite >= 1 and depth < 1:
		for k in mini(killed.size(), 3):
			shades.append({"pos": killed[k], "t": 0.25, "dmg": dmg * 0.4, "r": r * 0.8, "depth": depth + 1})
			fx({"kind": "shade", "pos": killed[k], "life": 0.3, "col": DARK})


func _draw_pfx(f: Dictionary, a: float) -> bool:
	match f.kind:
		"smoke":
			# 黑烟团：膨胀、变淡、略上飘
			var k := 1.0 - a
			var p: Vector2 = f.pos + Vector2(0, -14.0 * k)
			g.draw_circle(p, f.r * (0.45 + 0.75 * k), Color(0.14, 0.1, 0.12, 0.55 * a))
			g.draw_circle(p + Vector2(f.r * 0.25, -f.r * 0.15), f.r * (0.3 + 0.5 * k), Color(0.2, 0.14, 0.16, 0.4 * a))
			return true
		"wisp":
			# 上飘的黑色雾丝
			var pts := PackedVector2Array()
			for i in 5:
				pts.append(f.pos + Vector2(sin(f.ph + g.t * 9.0 + i * 1.3) * 4.0, -i * 7.0))
			g.draw_polyline(pts, Color(0.08, 0.05, 0.07, 0.8 * a), 3.0)
			return true
		"shade":
			# 残影：黑色人形 + 一对红点，浮起
			var p: Vector2 = f.pos + Vector2(0, -6.0 - 10.0 * (1.0 - a))
			g.draw_set_transform(p, 0.0, Vector2(1.0, 1.7))
			g.draw_circle(Vector2.ZERO, 9.0, Color(0.05, 0.03, 0.05, 0.8 * a))
			g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			g.draw_circle(p + Vector2(-3, -7), 1.5, Color(2.0, 0.3, 0.3, a))
			g.draw_circle(p + Vector2(3, -7), 1.5, Color(2.0, 0.3, 0.3, a))
			return true
	return false


func draw_entities_floor() -> void:
	# 落点预告：炮弹飞行后半程在落点画暗红圈
	for s in shells:
		var k: float = s.t / s.dur
		if k > 0.5:
			g.draw_set_transform(s.to, 0.0, Vector2(1.0, 0.55))
			g.draw_arc(Vector2.ZERO, s.r * 0.6, 0.0, TAU, 24, Color(RED.r, RED.g, RED.b, 0.35 * (k - 0.5) * 2.0), 2.0)
			g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for q in quakes:
		var a: float = 1.0 - q.t / 0.45
		g.draw_set_transform(q.pos, 0.0, Vector2(1.0, 0.55))
		g.draw_arc(Vector2.ZERO, q.r * (0.25 + 0.2 * a), 0.0, TAU, 20, Color(RED.r, RED.g, RED.b, 0.5 * a), 2.0)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_skill_over() -> void:
	for s in shells:
		var p := _shell_pos(s)
		g.draw_circle(p, 5.5, Color(0.08, 0.05, 0.07))
		g.draw_circle(p + Vector2(-1, -1), 2.0, Color(1.6, 0.5, 0.4))


func status_items() -> Array:
	var out: Array = []
	if ash > 0:
		out.append(["灰烬弹幕 ×%d" % ash, RED])
	if volley > 0:
		out.append(["饱和炮击", Color(1.0, 0.55, 0.45)])
	return out
