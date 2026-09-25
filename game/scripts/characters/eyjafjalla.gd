## 艾雅法拉（术师，契约 v2.1）：熔岩弹（范围法伤）。
## S1 炽热：接下来 3 发火山弹范围 ×1.4 并点燃；S2 点燃：一发 ×2.5 熔岩弹 + 易伤；S3 火山：敌群最密处连续喷发 10 次并留下熔岩。
## 熔岩弹复用 game.gd 的 fire 子弹做命中（带 src / fx_col / hidden），弹体、喷发、熔岩池由本干员绘制。
## 特效（docs/25）：橙红白。熔岩球橙核白心 + 火星尾；喷发 = 地面红裂纹 → 熔岩柱 → 熔岩池冒泡；点燃 = 敌人身上的火舌。
extends "res://scripts/characters/character.gd"

const ORANGE := Color(1.0, 0.5, 0.2)
const LAVA := Color(0.95, 0.3, 0.08)

var cd := 0.6
var heat := 0               # S1：剩余强化火山弹数
var erupt := 0              # S3：剩余喷发次数
var erupt_t := 0.0
var lava: Array = []        # {pos, r, t, tick, dmg, bub}
var burns: Array = []       # 点燃：{e, t, dps, ft}
var pending: Array = []     # 喷发前摇：{pos, t}


## 基础数值全部可由 data/characters/eyjafjalla.json 的 base 段覆盖（docs/27 §3）
func _aoe() -> float:
	return base("aoe", 58.0) * stat(&"op_range") * (1.25 if elite >= 1 else 1.0)


func update(dt: float) -> void:
	cd -= dt
	_update_ground(dt)
	_update_orbs(dt)
	for p in pending:
		p.t -= dt
		if p.t <= 0.0:
			_erupt(p.pos)
	pending = pending.filter(func(p): return p.t > 0.0)
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
			var at: Vector2 = c + Vector2(g.rng.randf_range(-50, 50), g.rng.randf_range(-40, 40))
			pending.append({"pos": at, "t": 0.12})
			fx({"kind": "crack", "pos": at, "r": 40.0, "life": 0.3, "col": LAVA, "floor": true, "n": 6, "ang": at.x * 0.02})
		return
	if acting():
		return
	var ready := charge_skills(dt)
	if ready == 0:
		spend_sp(0)
		heat = 3
		fx({"kind": "glow", "pos": pos + Vector2(0, -30), "r": 22.0, "life": 0.3, "col": ORANGE, "alpha": 0.5})
		g._add_text(pos + Vector2(0, -80), "炽热", ORANGE, 14)
		return
	if ready > 0:
		var ts: Array = g._nearest(1, 440.0, pos)
		start_skill(ts[0].pos if not ts.is_empty() else Vector2.INF, ready)
		return
	if cd <= 0.0:
		var ts: Array = g._nearest(1, base("range", 380.0) * stat(&"op_range"), pos)
		if ts.is_empty():
			cd = 0.2
		else:
			cd = base("cd", 1.2) / stat(&"op_aspd")
			start_attack(ts[0].pos)


func _release() -> void:
	var ts: Array = g._nearest(1, 420.0 * stat(&"op_range"), pos)
	if ts.is_empty():
		return
	var hot := heat > 0
	if hot:
		heat -= 1
	_cast(pos + Vector2(10.0 * face, -30), ts[0].pos, base("atk", 22.0) * (1.0 if not hot else skill_power()), _aoe() * (base("s1_aoe", 1.4) if hot else 1.0), "火山弹", hot, 0.0)
	fx({"kind": "glow", "pos": pos + Vector2(10.0 * face, -30), "r": 10.0, "life": 0.12, "col": ORANGE, "alpha": 0.6})


func _release_skill() -> void:
	match cur_skill:
		1:
			# 点燃：一发重弹 + 易伤
			var ts: Array = g._nearest(1, 440.0 * stat(&"op_range"), pos)
			if ts.is_empty():
				return
			_cast(pos + Vector2(10.0 * face, -30), ts[0].pos, base("atk", 22.0) * base("s2_mult", 2.5) * skill_power(), _aoe() * 1.3, "点燃弹", true, 6.0)
			g.fx.append({"kind": "rays", "pos": pos + Vector2(0, -20), "life": 0.4, "max": 0.4, "col": ORANGE})
		2:
			erupt = int(base("s3_count", 10.0))
			erupt_t = 0.0
			g.fx.append({"kind": "rays", "pos": pos + Vector2(0, -20), "life": 0.5, "max": 0.5, "col": ORANGE})
			fx({"kind": "ring", "pos": pos, "r": 70.0, "r0": 10.0, "life": 0.5, "col": ORANGE, "floor": true})
			Sfx.play("roar", -14.0, 1.6, 0.05)


func skill_active_left(i: int) -> float:
	return float(erupt) * 0.2 if i == 2 else 0.0


func skill_active_dur(i: int) -> float:
	return 2.0 if i == 2 else 1.0


func _cast(from: Vector2, target: Vector2, base_dmg: float, aoe: float, src: String, burn: bool, weak: float) -> void:
	var d: Vector2 = (target - from).normalized()
	face = signf(d.x) if absf(d.x) > 0.01 else face
	g.bullets.append({"kind": "fire", "pos": from, "vel": d * 360.0, "dmg": base_dmg * _dmg_bonus(), "life": 1.3, "r": 8.0,
		"aoe": aoe, "src": src, "op": id, "on_hit": self, "burn": burn, "weak": weak, "fx_col": ORANGE, "hidden": true, "etrail": 0.0})
	Sfx.play("oil", -12.0, 1.2, 0.05)


## 自己的熔岩球：火星尾
func _update_orbs(dt: float) -> void:
	for b in g.bullets:
		if b.life <= 0.0 or b.get("op", "") != id or b.kind != "fire":
			continue
		b.etrail = b.get("etrail", 0.0) - dt
		if b.etrail <= 0.0:
			b.etrail = 0.04
			fx({"kind": "spark", "pos": b.pos - b.vel.normalized() * 6.0, "vel": -b.vel * 0.12 + Vector2(g.rng.randf_range(-20, 20), g.rng.randf_range(-30, 10)), "life": 0.3, "col": ORANGE, "sz": 3.0})


## fire 子弹爆炸后由 game.gd 回调：熔岩飞溅；点燃 / 易伤
func bullet_exploded(b: Dictionary) -> void:
	for k in 6:
		fx({"kind": "mote", "pos": b.pos, "vel": Vector2(g.rng.randf_range(-90, 90), g.rng.randf_range(-160, -60)), "life": 0.45, "col": LAVA, "sz": 2.5, "grav": 320.0})
	fx({"kind": "ring", "pos": b.pos, "r": b.aoe, "r0": b.aoe * 0.3, "life": 0.3, "col": Color(0.8, 0.2, 0.05), "floor": true, "w": 2.0})
	if b.get("burn", false) or b.get("weak", 0.0) > 0.0:
		for e in g._arc_hit(b.pos, 0.0, PI, b.aoe):
			if e.dead:
				continue
			if b.get("burn", false):
				burns.append({"e": e, "t": 3.0 + (1.0 if elite >= 1 else 0.0), "dps": b.dmg * 0.1, "ft": 0.0})
			if b.get("weak", 0.0) > 0.0:
				e["aura_weak"] = maxf(float(e.get("aura_weak", 0.0)), b.weak)


func _erupt(c: Vector2) -> void:
	var r: float = base("s3_r", 75.0) * stat(&"op_range")
	area_hit("火山", c, r, base("atk", 22.0) * base("s3_mult", 1.64) * _dmg_bonus() * skill_power())
	fx({"kind": "lava_pillar", "pos": c, "r": r, "life": 0.5, "col": ORANGE})
	fx({"kind": "glow", "pos": c, "r": r * 0.5, "life": 0.18, "col": Color(1.6, 0.9, 0.4), "alpha": 0.7})
	fx({"kind": "ring", "pos": c, "r": r, "r0": r * 0.2, "life": 0.35, "col": ORANGE, "floor": true, "w": 3.0})
	for k in 8:
		fx({"kind": "mote", "pos": c + Vector2(g.rng.randf_range(-8, 8), -30), "vel": Vector2(g.rng.randf_range(-120, 120), g.rng.randf_range(-260, -120)), "life": 0.6, "col": LAVA, "sz": 3.0, "grav": 420.0})
	lava.append({"pos": c, "r": r * 0.8, "t": 3.0, "tick": 0.0, "bub": 0.0, "dmg": base("atk", 22.0) * base("lava_mult", 0.23) * _dmg_bonus() * skill_power()})
	g.shake = maxf(g.shake, 2.5)
	Sfx.play("boom", -13.0, 0.9, 0.1)


func _update_ground(dt: float) -> void:
	for l in lava:
		l.t -= dt
		l.tick -= dt
		l.bub -= dt
		if l.tick <= 0.0:
			l.tick = 0.5
			area_hit("熔岩", l.pos, l.r, l.dmg)
		if l.bub <= 0.0 and l.t > 0.4:
			l.bub = 0.18
			var a: float = g.rng.randf() * TAU
			var rr: float = g.rng.randf() * l.r * 0.8
			fx({"kind": "mote", "pos": l.pos + Vector2(cos(a) * rr, sin(a) * rr * 0.55), "vel": Vector2(0, -28), "life": 0.55, "col": ORANGE, "sz": 2.0})
	lava = lava.filter(func(l): return l.t > 0.0)
	for b in burns:
		b.t -= dt
		b.ft -= dt
		if b.e.dead:
			b.t = 0.0
			continue
		if b.ft <= 0.0:
			b.ft = 0.14
			fx({"kind": "flame", "pos": b.e.pos + Vector2(g.rng.randf_range(-b.e.r * 0.5, b.e.r * 0.5), -b.e.r * 0.4), "vel": Vector2(0, -20), "life": 0.3, "col": ORANGE, "sz": 9.0})
		if int((b.t + dt) * 2.0) != int(b.t * 2.0):
			g._hit("点燃")
			g._damage(b.e, b.dps * 0.5)
	burns = burns.filter(func(b): return b.t > 0.0)


func _draw_pfx(f: Dictionary, a: float) -> bool:
	if f.kind == "lava_pillar":
		# 熔岩柱：底宽上窄，先冲高再落下，白芯
		var k: float = sin(a * PI)
		var h: float = (60.0 + f.r * 0.5) * k
		var w: float = f.r * 0.45
		var p: Vector2 = f.pos
		g.draw_colored_polygon(PackedVector2Array([p + Vector2(-w, 0), p + Vector2(-w * 0.35, -h), p + Vector2(w * 0.35, -h), p + Vector2(w, 0)]), Color(LAVA.r, LAVA.g, LAVA.b, 0.8 * a))
		g.draw_colored_polygon(PackedVector2Array([p + Vector2(-w * 0.45, 0), p + Vector2(-w * 0.12, -h * 0.9), p + Vector2(w * 0.12, -h * 0.9), p + Vector2(w * 0.45, 0)]), Color(2.2, 1.6, 0.8, 0.85 * a))
		g.draw_circle(p + Vector2(0, -h), w * 0.35, Color(2.4, 1.9, 1.2, 0.8 * a))
		return true
	return false


func draw_entities_floor() -> void:
	for l in lava:
		var a: float = clampf(l.t / 0.6, 0.0, 1.0)
		g.draw_set_transform(l.pos, 0.0, Vector2(1.0, 0.55))
		g.draw_circle(Vector2.ZERO, l.r, Color(0.7, 0.15, 0.03, 0.3 * a))
		g.draw_circle(Vector2.ZERO, l.r * 0.6, Color(1.5, 0.55, 0.1, 0.22 * a + 0.06 * sin(g.t * 9.0 + l.pos.x)))
		g.draw_arc(Vector2.ZERO, l.r, 0.0, TAU, 24, Color(1.8, 0.7, 0.2, 0.5 * a), 2.0)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func draw_auras() -> void:
	# 火山生效期间：脚下热浪环呼吸
	if erupt > 0 and pos != Vector2.INF:
		g.draw_set_transform(pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
		g.draw_arc(Vector2.ZERO, 56.0 + 6.0 * sin(g.t * 6.0), 0.0, TAU, 32, Color(ORANGE.r, ORANGE.g, ORANGE.b, 0.35), 2.0)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_skill_over() -> void:
	# 自绘熔岩球：橙核白心 + 外圈热光
	for b in g.bullets:
		if b.life <= 0.0 or b.get("op", "") != id or b.kind != "fire":
			continue
		var big: bool = b.get("src", "") == "点燃弹"
		var fl := 1.0 + 0.15 * sin(g.t * 40.0 + b.pos.x)
		g.draw_circle(b.pos, (17.0 if big else 13.0) * fl, Color(1.6, 0.6, 0.15, 0.22))
		g.draw_circle(b.pos, (10.0 if big else 7.5) * fl, Color(2.2, 0.9, 0.25, 0.9))
		g.draw_circle(b.pos, 4.5 if big else 3.5, Color(2.8, 2.4, 1.6))


func status_items() -> Array:
	var out: Array = []
	if heat > 0:
		out.append(["炽热 ×%d" % heat, ORANGE])
	if erupt > 0:
		out.append(["火山", ORANGE])
	return out
