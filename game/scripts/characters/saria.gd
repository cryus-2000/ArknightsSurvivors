## 塞雷娅（重装，docs/23 §10 / §11.1）：护博士。站在博士身侧；阻挡圈把贴近博士的敌人推开并减速，
## 盾击击退身前敌人；技能「钙质化」为博士加护盾层（与局内护盾共用 g.shield，docs/23 §9.4）并回复少量生命。
extends "res://scripts/characters/character.gd"

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
	for j in g._query(g.ppos, r + 30.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or e.boss or e.chest:
			continue
		var off: Vector2 = e.pos - g.ppos
		if off.length() > r + e.r:
			continue
		e.kb += off.normalized() * (80.0 if e.elite else 200.0)
		e.slow = maxf(e.slow, 0.5)
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
	g._slash_fx(pos + Vector2(0, -14), ang, 1.0, _reach() * 0.8, Color(1.0, 0.7, 0.4))
	Sfx.play("swing", -12.0, 0.6, 0.05)


func _release_skill() -> void:
	var n: int = 3 if elite >= 2 else 2
	g.shield += n
	g.shield_pop = 0.4
	g._heal(g.max_hp * 0.05 * skill_power())
	g._add_text(g.ppos + Vector2(0, -96), "护盾 +%d" % n, Color(0.6, 0.9, 1.0), 18)
	g.fx.append({"kind": "ring", "pos": g.ppos, "r": 48.0, "life": 0.5, "max": 0.5, "col": Color(1.0, 0.75, 0.45)})
	if elite >= 2:
		var r := 140.0
		area_hit("阻挡", g.ppos, r, 22.0 * 1.5 * _dmg_bonus() * skill_power(), 320.0, 0.4)
		g.fx.append({"kind": "quake", "pos": g.ppos, "r": r, "life": 0.4, "max": 0.4, "col": Color(1.0, 0.75, 0.45)})
	Sfx.play("dodge", -8.0, 0.8)


## 精一「坚守」：博士受到的伤害 -12%（game.gd _enemy_hit 查询）
func dmg_taken_mult() -> float:
	return 0.88 if elite >= 1 else 1.0


func draw_auras() -> void:
	var r := block_radius()
	g.draw_set_transform(g.ppos + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
	g.draw_arc(Vector2.ZERO, r, 0.0, TAU, 36, Color(1.0, 0.72, 0.4, 0.22 + 0.06 * sin(g.t * 4.0)), 2.0)
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
