## 塞雷娅（重装，契约 v2.1）：护博士。站在博士身侧；阻挡圈把贴近博士的敌人推开并减速，持盾出拳击退身前敌人（攻击较高）。
## 技能全部是治疗，不给护盾（护盾太强）：S1 急救：回复 8%（低血翻倍）；S2 药剂散布：回复 10% + 5 秒持续回复；S3 钙质化：8 秒琥珀区域，敌人减速 + 易伤，博士持续回复。
## 特效（docs/25）：琥珀。阻挡圈为地面分段虚线环 + 绕行小晶体；盾击短弧 + 推力线；钙质化在博士周围升起琥珀晶柱。
extends "res://scripts/characters/character.gd"

const AMBER := Color(1.0, 0.72, 0.38)
const S3_DUR := 8.0
const S3_R := 180.0

var cd := 0.5
var block_t := 0.0
var calc := 0.0               # S3 钙质化剩余
var calc_acc := 0.0
var shard_t := 0.0
var hot_t := 0.0              # S2 持续回复剩余
var hot_acc := 0.0


## 基础数值全部可由 data/characters/saria.json 的 base 段覆盖（docs/27 §3）
func block_radius() -> float:
	return base("block_r", 62.0) * stat(&"op_range")


func _reach() -> float:
	return base("reach", 70.0) * stat(&"op_range")


## 站位：博士面前一侧（贴身护卫），不前压
func follow_target(_slot_pos: Vector2) -> Vector2:
	return g.ppos + Vector2(26.0 * g.facing, 6)


func update(dt: float) -> void:
	cd -= dt
	_block(dt)
	if hot_t > 0.0:
		hot_t -= dt
		hot_acc += dt
		if hot_acc >= 1.0:
			hot_acc -= 1.0
			if g.hp < g.max_hp:
				g._heal(g.max_hp * 0.01)
				fx({"kind": "mote", "pos": g.ppos + Vector2(g.rng.randf_range(-16, 16), -20), "vel": Vector2(0, -35), "life": 0.7, "col": AMBER, "sz": 2.0})
	if calc > 0.0:
		calc -= dt
		calc_acc += dt
		if calc_acc >= 1.0:
			calc_acc -= 1.0
			if g.hp < g.max_hp:
				g._heal(g.max_hp * 0.015)
		# 区域内敌人：减速 + 易伤
		for j in g._query(g.ppos, S3_R + 20.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or e.pos.distance_to(g.ppos) > S3_R:
				continue
			e.slow = maxf(e.slow, 0.5)
			e["aura_weak"] = maxf(float(e.get("aura_weak", 0.0)), 0.2)
		shard_t -= dt
		if shard_t <= 0.0:
			shard_t = 0.35
			var a: float = g.rng.randf() * TAU
			var rr: float = g.rng.randf_range(S3_R * 0.3, S3_R * 0.95)
			fx({"kind": "crystal", "pos": g.ppos + Vector2(cos(a) * rr, sin(a) * rr * 0.55 + 4.0), "h": g.rng.randf_range(12, 24), "life": 1.2, "col": AMBER, "lean": g.rng.randf_range(-0.3, 0.3)})
	if acting():
		return
	var ready := charge_skills(dt)
	if ready >= 0:
		start_skill(Vector2.INF, ready)
		return
	if cd <= 0.0:
		var ts: Array = g._nearest(1, _reach() + 40.0, pos)
		if ts.is_empty():
			cd = 0.1
		else:
			cd = base("cd", 1.1) / stat(&"op_aspd")
			start_attack(ts[0].pos)


## 阻挡圈：每 0.25 秒把博士周围 block_radius 内的非 Boss 敌人推到圈外、减速
func _block(dt: float) -> void:
	block_t -= dt
	if block_t > 0.0:
		return
	block_t = 0.25
	var r := block_radius()
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


func _release() -> void:
	var ts: Array = g._nearest(1, _reach() + 40.0, pos)
	var ang := facing_angle()
	if not ts.is_empty():
		ang = (ts[0].pos - pos).angle()
		face_to(ang)
	melee_hit("拳击", pos + Vector2(0, -10), ang, 1.1, _reach(), base("atk", 28.0) * _dmg_bonus(), 200.0, 0.2)
	g._slash_fx(pos + Vector2(0, -14), ang, 1.0, _reach() * 0.8, AMBER)
	var d := Vector2.from_angle(ang)
	fx({"kind": "line", "pos": pos + Vector2(0, -12) + d * 14.0, "to": pos + Vector2(0, -12) + d * _reach() * 1.3, "life": 0.15, "col": AMBER, "w": 3.0})
	Sfx.play("swing", -12.0, 0.6, 0.05)


func _heal_fx(h: float) -> void:
	g._add_text(g.ppos + Vector2(0, -90), "+%d" % int(h), AMBER, 16)
	for k in 6:
		fx({"kind": "mote", "pos": g.ppos + Vector2(g.rng.randf_range(-20, 20), g.rng.randf_range(-40, -10)), "vel": Vector2(0, -35), "life": 0.8, "col": AMBER, "sz": 2.5})


func _release_skill() -> void:
	match cur_skill:
		0:
			# 急救
			var h: float = g.max_hp * base("s1_heal", 0.08) * skill_power() * (2.0 if g.hp < g.max_hp * 0.5 else 1.0)
			g._heal(h)
			_heal_fx(h)
			fx({"kind": "ring", "pos": g.ppos, "r": 40.0, "r0": 8.0, "life": 0.4, "col": AMBER, "floor": true})
		1:
			# 药剂散布：立即回复 + 5 秒持续回复
			var h2: float = g.max_hp * base("s2_heal", 0.10) * skill_power()
			g._heal(h2)
			_heal_fx(h2)
			hot_t = 5.0
			hot_acc = 0.0
			fx({"kind": "ring", "pos": g.ppos, "r": 60.0, "r0": 10.0, "life": 0.5, "col": AMBER, "floor": true})
		2:
			# 钙质化：晶柱升起 + 区域
			calc = S3_DUR
			calc_acc = 0.0
			for k in 8:
				var a: float = k * TAU / 8.0 + 0.3
				fx({"kind": "crystal", "pos": g.ppos + Vector2(cos(a) * 34.0, sin(a) * 34.0 * 0.55 + 4.0), "h": g.rng.randf_range(22, 40), "life": 1.5 + k * 0.03, "col": AMBER, "lean": g.rng.randf_range(-0.25, 0.25)})
			fx({"kind": "ring", "pos": g.ppos, "r": S3_R, "r0": 30.0, "life": 0.5, "col": AMBER, "floor": true, "w": 4.0})
			fx({"kind": "crack", "pos": g.ppos, "r": 90.0, "life": 0.45, "col": AMBER, "floor": true, "n": 10})
			g._show_banner("钙质化")
			g.shake = maxf(g.shake, 3.0)
	Sfx.play("dodge", -8.0, 0.8)


func skill_active_left(i: int) -> float:
	return calc if i == 2 else 0.0


func skill_active_dur(i: int) -> float:
	return S3_DUR if i == 2 else 1.0


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
	if calc > 0.0:
		# 钙质化区域：琥珀地面 + 缓慢旋转的晶格
		var fade: float = clampf(calc / 0.6, 0.0, 1.0)
		g.draw_set_transform(c, 0.0, Vector2(1.0, 0.55))
		g.draw_circle(Vector2.ZERO, S3_R, Color(AMBER.r, AMBER.g, AMBER.b, 0.08 * fade))
		g.draw_arc(Vector2.ZERO, S3_R, 0.0, TAU, 48, Color(AMBER.r, AMBER.g, AMBER.b, 0.45 * fade), 2.5)
		for k in 6:
			var dv := Vector2.from_angle(k * TAU / 6.0 + g.t * 0.3)
			g.draw_line(dv * S3_R * 0.85, dv * S3_R, Color(1.6, 1.3, 0.8, 0.6 * fade), 2.0)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
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


func status_items() -> Array:
	var out: Array = []
	if hot_t > 0.0:
		out.append(["药剂散布", AMBER])
	if calc > 0.0:
		out.append(["钙质化", AMBER])
	return out
