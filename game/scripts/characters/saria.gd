## 塞雷娅（重装，docs/23 §10 / §11.1）：护博士。站在博士身侧；阻挡圈把贴近博士的敌人推开并减速，
## 盾击击退身前敌人；技能「钙质化」为博士加护盾层（与局内护盾共用 g.shield，docs/23 §9.4）并回复少量生命。
## 特效（docs/25）：琥珀。阻挡圈为地面分段虚线环 + 绕行小晶体；盾击短弧 + 推力线；钙质化在博士周围升起琥珀晶柱。
extends "res://scripts/characters/character.gd"

const AMBER := Color(1.0, 0.72, 0.38)

var cd := 0.5
var block_t := 0.0
var burn_t := 0.0             # 精二：阻挡圈每秒伤害的计时


func block_radius() -> float:
	return 62.0 * stat(&"op_range")


func _reach() -> float:
	return 70.0 * stat(&"op_range")


## 站位：博士面前一侧（贴身护卫），不前压
func follow_target(_slot_pos: Vector2) -> Vector2:
	return g.ppos + Vector2(26.0 * g.facing, 6)


func update(dt: float) -> void:
	cd -= dt
	_block(dt)
	if acting():
		return
	if charge_skill(dt):
		start_skill(Vector2.INF)
		return
	if cd <= 0.0:
		var ts: Array = g._nearest(1, _reach() + 40.0, pos)
		if ts.is_empty():
			cd = 0.1
		else:
			cd = 1.1 / stat(&"op_aspd")
			start_attack(ts[0].pos)


## 阻挡圈：每 0.25 秒把博士周围 block_radius 内的非 Boss 敌人推到圈外、减速；精二每秒造成伤害
func _block(dt: float) -> void:
	block_t -= dt
	burn_t -= dt
	if block_t > 0.0:
		return
	block_t = 0.25
	var r := block_radius()
	var dmg_tick := elite >= 2 and burn_t <= 0.0
	if dmg_tick:
		burn_t = 1.0
	var shown := 0
	for j in g._query(g.ppos, r + 30.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or e.boss or e.chest:
			continue
		var off: Vector2 = e.pos - g.ppos
		if off.length() > r + e.r:
			continue
		e.kb += off.normalized() * (80.0 if e.elite else 200.0)
		e.slow = maxf(e.slow, 0.5)
		if shown < 4:
			shown += 1
			fx({"kind": "glow", "pos": e.pos, "r": 9.0, "life": 0.18, "col": AMBER, "alpha": 0.5, "floor": true})
		if dmg_tick:
			g._hit("阻挡")
			g._damage(e, 12.0 * _dmg_bonus())


func _release() -> void:
	var ts: Array = g._nearest(1, _reach() + 40.0, pos)
	var ang := facing_angle()
	if not ts.is_empty():
		ang = (ts[0].pos - pos).angle()
		face_to(ang)
	melee_hit("盾击", pos + Vector2(0, -10), ang, 1.1, _reach(), 22.0 * _dmg_bonus(), 260.0, 0.2)
	g._slash_fx(pos + Vector2(0, -14), ang, 1.0, _reach() * 0.8, AMBER)
	var d := Vector2.from_angle(ang)
	fx({"kind": "line", "pos": pos + Vector2(0, -12) + d * 14.0, "to": pos + Vector2(0, -12) + d * _reach() * 1.3, "life": 0.15, "col": AMBER, "w": 3.0})
	Sfx.play("swing", -12.0, 0.6, 0.05)


func _release_skill() -> void:
	var n: int = 3 if elite >= 2 else 2
	g.shield += n
	g.shield_pop = 0.4
	g._heal(g.max_hp * 0.05 * skill_power())
	g._add_text(g.ppos + Vector2(0, -96), "护盾 +%d" % n, Color(0.6, 0.9, 1.0), 18)
	fx({"kind": "ring", "pos": g.ppos, "r": 60.0, "r0": 10.0, "life": 0.5, "col": AMBER, "floor": true})
	for k in 8:
		var a: float = k * TAU / 8.0 + 0.3
		fx({"kind": "crystal", "pos": g.ppos + Vector2(cos(a) * 34.0, sin(a) * 34.0 * 0.55 + 4.0), "h": g.rng.randf_range(22, 40), "life": 1.5 + k * 0.03, "col": AMBER, "lean": g.rng.randf_range(-0.25, 0.25)})
	for k in 6:
		fx({"kind": "mote", "pos": g.ppos + Vector2(g.rng.randf_range(-20, 20), g.rng.randf_range(-40, -10)), "vel": Vector2(0, -35), "life": 0.8, "col": AMBER, "sz": 2.5})
	if elite >= 2:
		var r := 140.0
		area_hit("阻挡", g.ppos, r, 22.0 * 1.5 * _dmg_bonus() * skill_power(), 320.0, 0.4)
		fx({"kind": "crack", "pos": g.ppos, "r": r * 0.7, "life": 0.45, "col": AMBER, "floor": true, "n": 10})
		fx({"kind": "ring", "pos": g.ppos, "r": r, "r0": 30.0, "life": 0.4, "col": AMBER, "floor": true, "w": 4.0})
		g.shake = maxf(g.shake, 3.0)
	Sfx.play("dodge", -8.0, 0.8)


func _draw_pfx(f: Dictionary, a: float) -> bool:
	if f.kind == "crystal":
		# 琥珀晶柱：0.25 秒长出，最后 0.4 秒淡出
		var age: float = f.max - f.life
		var grow: float = clampf(age / 0.25, 0.0, 1.0)
		var fade: float = clampf(f.life / 0.4, 0.0, 1.0)
		var h: float = f.h * (1.0 - (1.0 - grow) * (1.0 - grow))
		var p: Vector2 = f.pos
		var top: Vector2 = p + Vector2(f.lean * h, -h)
		g.draw_colored_polygon(PackedVector2Array([p + Vector2(-5, 0), top + Vector2(-2, 2), top, top + Vector2(2, 3), p + Vector2(5, 0), p + Vector2(0, 3)]), Color(AMBER.r, AMBER.g, AMBER.b, 0.85 * fade))
		g.draw_line(p + Vector2(-3, -1), top + Vector2(-1, 2), Color(1.9, 1.6, 1.0, 0.9 * fade), 1.5)
		g.draw_circle(top, 2.0, Color(2.2, 2.0, 1.4, fade))
		return true
	return false


## 精一「坚守」：博士受到的伤害 -12%（game.gd _enemy_hit 查询）
func dmg_taken_mult() -> float:
	return 0.88 if elite >= 1 else 1.0


func draw_auras() -> void:
	var r := block_radius()
	var c: Vector2 = g.ppos + Vector2(0, 4)
	g.draw_set_transform(c, 0.0, Vector2(1.0, 0.55))
	# 分段虚线环缓慢旋转
	for k in 8:
		var a0: float = g.t * 0.6 + k * TAU / 8.0
		g.draw_arc(Vector2.ZERO, r, a0, a0 + TAU / 8.0 * 0.55, 6, Color(AMBER.r, AMBER.g, AMBER.b, 0.35 + 0.06 * sin(g.t * 4.0)), 2.0)
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 三枚绕行的小晶体
	for k in 3:
		var a: float = -g.t * 1.1 + k * TAU / 3.0
		var p := c + Vector2(cos(a) * r, sin(a) * r * 0.55 - 6.0)
		g.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -6), p + Vector2(3, 0), p + Vector2(0, 5), p + Vector2(-3, 0)]), Color(1.6, 1.2, 0.6, 0.8))
