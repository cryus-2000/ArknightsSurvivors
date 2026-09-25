## 铃兰（辅助，契约 v2.1）：减速光域（只减速不伤害）+ 向 2 名敌人发射追踪狐火。
## S1 狐火连珠：下一次普攻 5 发；S2 暖光（永久型）：充能一次后光域永久扩大、其他干员加攻、博士回复；S3 狐火迷雾：10 秒大光域，减速 60%、易伤 25%，期间不普攻。
## 特效（docs/25）：狐火金。光域为地面淡金椭圆 + 边缘绕行的六团狐火；狐火弹金白火球带火舌尾；技能期间光点上升。
extends "res://scripts/characters/character.gd"

const GOLD := Color(1.0, 0.82, 0.45)
const S3_DUR := 10.0

var cd := 0.5
var volley_next := false      # S1：下一次普攻改为 5 发
var warm := false             # S2 暖光（永久）
var haze_t := 0.0             # S3 狐火迷雾
var mote_t := 0.0
var heal_acc := 0.0
var pillar_t := 0.0


## 基础数值全部可由 data/characters/suzuran.json 的 base 段覆盖（docs/27 §3）
func aura_radius() -> float:
	var r: float = (base("aura", 85.0) + 15.0 * elite) * stat(&"op_range")
	if haze_t > 0.0:
		return r * 2.2
	return r * (1.6 if warm else 1.0)


func update(dt: float) -> void:
	cd -= dt
	_update_orbs(dt)
	var on := warm or haze_t > 0.0
	if on:
		var was_haze := haze_t > 0.0
		haze_t = maxf(0.0, haze_t - dt)
		mote_t -= dt
		if mote_t <= 0.0:
			mote_t = 0.05 if haze_t <= 0.0 else 0.03
			var a: float = g.rng.randf() * TAU
			var rr: float = g.rng.randf() * aura_radius()
			fx({"kind": "mote", "pos": pos + Vector2(cos(a) * rr, sin(a) * rr * 0.55), "vel": Vector2(0, -40), "life": 0.7, "col": GOLD, "sz": 1.8})
		# 迷雾期间：光域里不时落下一根小光柱
		pillar_t -= dt
		if haze_t > 0.0 and pillar_t <= 0.0:
			pillar_t = 0.9
			var a2: float = g.rng.randf() * TAU
			var rr2: float = g.rng.randf_range(0.3, 0.9) * aura_radius()
			g._fx_sprite("fx_holy_pillar", pos + Vector2(cos(a2) * rr2, sin(a2) * rr2 * 0.55 + 4.0), g.PX * 0.7, 0.0, false, true)
		# 光域内的博士缓慢回复（原作：范围内友军回复）
		heal_acc += dt
		if heal_acc >= 1.0:
			heal_acc -= 1.0
			if g.hp < g.max_hp:
				g._heal(g.max_hp * (0.01 if haze_t > 0.0 else 0.005), "铃兰")
		if was_haze and haze_t <= 0.0:
			# 迷雾刚结束：回到暖光（永久）或清除加成
			if warm:
				_field_buff(base("s2_buff", 0.15) * skill_power())
			else:
				g.stats.remove_source("suzuran_field")
				g._sync_stats()
	var rad := aura_radius()
	for j in g._query(pos, rad + 20.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or e.pos.distance_to(pos) > rad:
			continue
		e.slow = maxf(e.slow, 0.6 if haze_t > 0.0 else (0.4 if warm else 0.2))
		if elite >= 1 or haze_t > 0.0:
			e["aura_weak"] = maxf(float(e.get("aura_weak", 0.0)), 0.2)
	if acting():
		return
	var ready := charge_skills(dt)
	if ready == 0:
		spend_sp(0)
		volley_next = true
		fx({"kind": "glow", "pos": pos + Vector2(0, -30), "r": 18.0, "life": 0.3, "col": GOLD, "alpha": 0.5})
		g._fx_sprite("fx_circle_gold", pos + Vector2(0, 4), g.PX * 1.6)
		return
	if ready > 0:
		start_skill(Vector2.INF, ready)
		return
	if haze_t > 0.0:
		return   # 狐火迷雾：期间不普攻
	if cd <= 0.0:
		var ts: Array = g._nearest(2, base("range", 380.0) * stat(&"op_range"), pos)
		if ts.is_empty():
			cd = 0.2
		else:
			cd = base("cd", 1.2) / stat(&"op_aspd")
			start_attack(ts[0].pos)


func _release() -> void:
	var n: int = int(base("shots", 2.0)) + (1 if elite >= 1 else 0)
	var mult := 1.0
	if volley_next:
		volley_next = false
		n = int(base("s1_shots", 5.0))
		mult = base("s1_mult", 1.2) * skill_power()
	var ts: Array = g._nearest(n, 400.0 * stat(&"op_range"), pos)
	var from := pos + Vector2(12.0 * face, -30)
	for k in n:
		if ts.is_empty():
			break
		var tg: Dictionary = ts[k % ts.size()]
		var d: Vector2 = (tg.pos - pos).normalized().rotated(0.6 * (1 if k % 2 == 0 else -1) * (1.0 + 0.3 * (k / 2)))
		# aoe：狐火命中时的小范围溅射（P5.1：纯单体的辅助单人开局清不动 1:15 的骨潮，永远到不了招募等级）
		g.bullets.append({"kind": "arcane", "pos": from, "vel": d * 330.0, "dmg": base("atk", 20.0) * mult * _dmg_bonus(),
			"life": 1.6, "r": 7.0, "aoe": base("aoe", 26.0), "home": tg, "turn": 7.0, "src": "狐火", "op": id, "fx_col": GOLD, "hidden": true, "etrail": 0.0})
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
	heal_acc = 0.0
	match cur_skill:
		1:
			warm = true
			_field_buff(base("s2_buff", 0.15) * skill_power())
			g._show_banner("暖光：光域永久扩大")
		2:
			haze_t = S3_DUR
			_field_buff(base("s3_buff", 0.2) * skill_power())
			g._show_banner("狐火迷雾")
	fx({"kind": "ring", "pos": pos, "r": aura_radius(), "r0": 10.0, "life": 0.6, "col": GOLD, "floor": true})
	g.fx.append({"kind": "rays", "pos": pos + Vector2(0, -24), "life": 0.5, "max": 0.5, "col": GOLD})
	# 圣光光柱（Pimen Holy VFX 02）：中心一根 + 光域边缘六根小的
	g._fx_sprite("fx_holy_pillar", pos + Vector2(0, 4), g.PX * (1.4 if cur_skill == 2 else 1.0), 0.0, false, true)
	var rr3 := aura_radius()
	for k in 6:
		var a3: float = k * TAU / 6.0 + g.t * 0.8
		g._fx_sprite("fx_holy_pillar", pos + Vector2(4, 4) + Vector2(cos(a3) * rr3, sin(a3) * rr3 * 0.55), g.PX * 0.6, 0.0, false, true)
	g._fx_sprite("fx_circle_gold", pos + Vector2(0, 4), g.PX * 2.2)


## 其他干员攻击加成：只写入别的干员的 op:<id> 作用域，不给自己
func _field_buff(v: float) -> void:
	g.stats.remove_source("suzuran_field")
	for o in g.squad.ops:
		if o != self:
			g.stats.add(&"op_atk", "add", v, "suzuran_field", "op:" + o.id)
	g._sync_stats()


func skill_active_left(i: int) -> float:
	return haze_t if i == 2 else 0.0


func skill_active_dur(i: int) -> float:
	return S3_DUR if i == 2 else 1.0


func _flame(p: Vector2, h: float, a: float) -> void:
	var wob: float = sin(g.t * 20.0 + p.x * 0.3) * 2.0
	g.draw_colored_polygon(PackedVector2Array([p + Vector2(-h * 0.35, 0), p + Vector2(wob, -h), p + Vector2(h * 0.35, 0)]), Color(GOLD.r, GOLD.g, GOLD.b, 0.75 * a))
	g.draw_colored_polygon(PackedVector2Array([p + Vector2(-h * 0.15, 0), p + Vector2(wob * 0.6, -h * 0.55), p + Vector2(h * 0.15, 0)]), Color(2.2, 2.0, 1.4, 0.8 * a))


func draw_auras() -> void:
	if pos == Vector2.INF:
		return
	var r := aura_radius()
	var on := warm or haze_t > 0.0
	g.draw_set_transform(pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
	g.draw_circle(Vector2.ZERO, r, Color(GOLD.r, GOLD.g, GOLD.b, 0.09 if on else 0.05))
	g.draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(GOLD.r, GOLD.g, GOLD.b, (0.45 if on else 0.25) + 0.06 * sin(g.t * 3.0)), 2.0)
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 边缘六团狐火绕行（迷雾时九团）
	var n: int = 9 if haze_t > 0.0 else 6
	for k in n:
		var a: float = g.t * 0.8 + k * TAU / n
		_flame(pos + Vector2(4, 4) + Vector2(cos(a) * r, sin(a) * r * 0.55), 9.0 if on else 6.0, 0.9 if on else 0.6)


func _draw_skill_over() -> void:
	# 狐火弹：OGA Light Bolt 调金（proj_foxfire），按速度方向旋转 + 外圈热光
	for b in g.bullets:
		if b.life <= 0.0 or b.get("op", "") != id or b.kind != "arcane":
			continue
		g.draw_circle(b.pos, 10.0, Color(GOLD.r, GOLD.g, GOLD.b, 0.22))
		if g.tex.get("proj_foxfire") != null:
			g._spr_rot("proj_foxfire", int(g.t * 12.0 + b.pos.x * 0.05) % 6, b.pos, b.vel.angle(), g.PX)
		else:
			g.draw_circle(b.pos, 5.5, Color(2.2, 1.8, 1.0))


func status_items() -> Array:
	var out: Array = []
	if volley_next:
		out.append(["狐火连珠", GOLD])
	if haze_t > 0.0:
		out.append(["狐火迷雾", GOLD])
	return out
