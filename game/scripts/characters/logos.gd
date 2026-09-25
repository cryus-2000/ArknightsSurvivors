## Logos（术师·中坚，契约 v2.1，docs/26 第二批）：远程单体法伤 + 清场处决 + 反弹幕。
## 普攻「言」：对一名敌人法伤并附「安魂」5 秒（受到的法术伤害 +15%，全队法伤受益，game.gd _damage 读 e.requiem）；
## S1 提喻：5 秒锁定一名敌人（优先精英 / Boss），每 0.25 秒法伤，对同一目标逐步升到 ×3、减速加深；
## S2 湮灭（永久）：射程 +30%、攻击 +50%；普攻处决生命低于攻击 ×1.5 的非精英敌人，溢出伤害转给随机另一名敌人；
## S3 延展敏锐：12 秒射程 +60%、攻击 +150%、同时 4 个目标；范围内敌方弹幕速度 -80%，结束时范围内弹幕全部消失。
## 天赋 词法演化：40% 概率额外攻击随机一名敌人（60% 伤害）并减速 0.8 秒。
extends "res://scripts/characters/character.gd"

const INK := Color(0.55, 0.6, 1.0)
const PALE := Color(0.85, 0.9, 1.0)

var cd := 0.6
var perish := false           # S2 湮灭（永久）
var lock_t := 0.0             # S1 剩余
var lock_e = null
var lock_tick := 0.0
var lock_n := 0
var acuity_t := 0.0           # S3 剩余


func _range() -> float:
	return base("range", 420.0) * stat(&"op_range") * (1.0 + base("s2_range", 0.3) if perish else 1.0) * (1.0 + base("s3_range", 0.6) if acuity_t > 0.0 else 1.0)


func _atk() -> float:
	return base("atk", 30.0) * _dmg_bonus() * (1.0 + base("s2_atk", 0.5) if perish else 1.0) * (1.0 + base("s3_atk", 1.5) * skill_power() if acuity_t > 0.0 else 1.0)


func update(dt: float) -> void:
	cd -= dt
	_update_lock(dt)
	_update_acuity(dt)
	if acting():
		return
	var ready := charge_skills(dt)
	if ready >= 0:
		var ts: Array = g._nearest(1, _range(), pos)
		start_skill(ts[0].pos if not ts.is_empty() else Vector2.INF, ready)
		return
	if cd <= 0.0:
		var ts2: Array = g._nearest(1, _range(), pos)
		if ts2.is_empty():
			cd = 0.15
		else:
			cd = base("cd", 1.1) / stat(&"op_aspd")
			start_attack(ts2[0].pos)


## 「言」：单体法伤 + 安魂；精一天赋概率追加；湮灭处决
func _release() -> void:
	var n: int = int(base("s3_targets", 4.0)) if acuity_t > 0.0 else 1
	var ts: Array = g._nearest(n, _range(), pos)
	if ts.is_empty():
		return
	for e in ts:
		_word(e, _atk(), "言")
	# 天赋：40% 额外攻击随机一名敌人（60% 伤害）并减速
	if elite >= 1 and g.rng.randf() < base("talent_chance", 0.4):
		var pool: Array = g._nearest(8, _range(), pos)
		if not pool.is_empty():
			var e2: Dictionary = pool[g.rng.randi() % pool.size()]
			_word(e2, _atk() * base("talent_mult", 0.6), "词法演化")
			e2.slow = maxf(e2.slow, 0.8)
	Sfx.op(id, "atk", 0.0, 1.0, 0.08)


func _word(e: Dictionary, dmg: float, src: String) -> void:
	if e.dead:
		return
	var hand: Vector2 = pos + Vector2(10.0 * face, -28)
	# 湮灭：处决非精英残血，溢出转给随机另一名敌人
	if perish and not e.elite and not e.boss and e.hp < _atk() * base("s2_exec", 1.5):
		var over: float = maxf(0.0, dmg - e.hp)
		g._hit("湮灭")
		g._damage(e, e.hp + 1.0)
		Sfx.op(id, "big", -3.0)
		g._add_text(e.pos + Vector2(0, -e.r - 14), "湮灭", INK, 14)
		fx({"kind": "glow", "pos": e.pos + Vector2(0, -e.r * 0.5), "r": 16.0, "life": 0.3, "col": INK, "alpha": 0.7})
		if over > 0.0:
			var pool: Array = g._nearest(6, _range(), pos)
			pool = pool.filter(func(o): return not is_same(o, e) and not o.dead)
			if not pool.is_empty():
				var o: Dictionary = pool[g.rng.randi() % pool.size()]
				g._hit("言")
				g._damage(o, over)
				o["requiem"] = base("requiem_dur", 5.0)
				fx({"kind": "line", "pos": e.pos + Vector2(0, -e.r * 0.5), "to": o.pos + Vector2(0, -o.r * 0.5), "life": 0.2, "col": INK, "w": 2.0})
		return
	g._hit(src)
	g._damage(e, dmg)
	e["requiem"] = base("requiem_dur", 5.0)
	# 命中处小范围溅射（纯单体清不动 1:15 的骨潮，同铃兰 P5.1 的处理）
	var ar: float = base("aoe", 30.0)
	if ar > 0.0:
		for j in g._query(e.pos, ar + 20.0):
			var o: Dictionary = g.enemies[j]
			if o.dead or is_same(o, e) or o.pos.distance_to(e.pos) > ar + o.r:
				continue
			g._hit(src)
			g._damage(o, dmg * base("aoe_mult", 0.45))
			o["requiem"] = base("requiem_dur", 5.0)
	# 言：一道从手到目标的墨蓝细线 + 命中处墨蓝爆点（Ninja Flam 重调色；缺图退回光点）
	fx({"kind": "line", "pos": hand, "to": e.pos + Vector2(0, -e.r * 0.5), "life": 0.14, "col": INK, "w": 2.0})
	if not g._fx_sprite("fx_ink_hit", e.pos + Vector2(0, -e.r * 0.5), g.PX * 0.9, 0.0, g.rng.randf() < 0.5):
		fx({"kind": "glow", "pos": e.pos + Vector2(0, -e.r * 0.5), "r": 10.0, "life": 0.22, "col": PALE, "alpha": 0.6})
	for k in 3:
		fx({"kind": "mote", "pos": e.pos + Vector2(g.rng.randf_range(-8, 8), -e.r * 0.5 + g.rng.randf_range(-8, 8)), "vel": Vector2(0, -40), "life": 0.35, "col": INK, "sz": 2.0})


# ---------------------------------------------------------------- 技能

func _release_skill() -> void:
	match cur_skill:
		0:
			# 提喻：锁定精英 / Boss 优先
			var best = null
			var bd := INF
			for j in g._query(pos, _range()):
				var e: Dictionary = g.enemies[j]
				if e.dead:
					continue
				var score: float = e.pos.distance_to(pos) - (100000.0 if (e.elite or e.boss) else 0.0)
				if score < bd:
					bd = score
					best = e
			if best == null:
				sp[0] = sp_need(0) * 0.6
				return
			lock_e = best
			lock_t = base("s1_dur", 5.0)
			lock_tick = 0.0
			lock_n = 0
			g._fx_sprite("fx_circle_ink", best.pos + Vector2(0, best.r * 0.8), g.PX * clampf(best.r / 14.0, 1.2, 2.6))
			g._add_text(best.pos + Vector2(0, -best.r - 16), "提喻", INK, 15)
		1:
			perish = true
			g._show_banner("湮灭：射程与攻击永久提升，处决残血")
			fx({"kind": "ring", "pos": pos, "r": 80.0, "r0": 8.0, "life": 0.5, "col": INK, "floor": true})
			g._fx_sprite("fx_felspell", pos + Vector2(0, -16), g.PX * 1.2, 0.0, false, false, Color(0.8, 0.85, 1.4))
		2:
			acuity_t = base("s3_dur", 12.0)
			g._show_banner("延展敏锐")
			g._fx_sprite("fx_holy_pillar_ink", pos + Vector2(0, 4), g.PX * 1.3, 0.0, false, true)
			g._fx_sprite("fx_circle_ink", pos + Vector2(0, 4), g.PX * 2.4)
			g.fx.append({"kind": "rays", "pos": pos + Vector2(0, -26), "life": 0.6, "max": 0.6, "col": INK})
			fx({"kind": "ring", "pos": pos, "r": _range(), "r0": 30.0, "life": 0.8, "col": INK, "floor": true, "w": 2.0})
	# 技能发动音 op_logos_s1/s2/s3 由 spend_sp 播放


func skill_active_left(i: int) -> float:
	match i:
		0: return lock_t
		2: return acuity_t
	return 0.0


func skill_active_dur(i: int) -> float:
	return [base("s1_dur", 5.0), 1.0, base("s3_dur", 12.0)][i]


func _update_lock(dt: float) -> void:
	if lock_t <= 0.0:
		return
	lock_t -= dt
	if lock_e == null or lock_e.dead:
		lock_t = 0.0
		lock_e = null
		return
	lock_tick += dt
	var tick: float = base("s1_tick", 0.25)
	while lock_tick >= tick:
		lock_tick -= tick
		lock_n += 1
		var ramp: float = lerpf(1.0, base("s1_max", 3.0), clampf(lock_n / 12.0, 0.0, 1.0))
		g._hit("提喻")
		g._damage(lock_e, _atk() * base("s1_tick_mult", 0.5) * ramp * skill_power())
		lock_e.slow = maxf(lock_e.slow, 0.6 * ramp)
		fx({"kind": "line", "pos": pos + Vector2(10.0 * face, -28), "to": lock_e.pos + Vector2(0, -lock_e.r * 0.5), "life": 0.12, "col": INK, "w": 1.5 + ramp})
		fx({"kind": "glow", "pos": lock_e.pos + Vector2(0, -lock_e.r * 0.5), "r": 8.0 + 6.0 * ramp, "life": 0.2, "col": PALE, "alpha": 0.5})


func _update_acuity(dt: float) -> void:
	if acuity_t <= 0.0:
		return
	acuity_t -= dt
	var r := _range()
	var f: float = base("s3_bullet_slow", 0.2)
	for b in g.ebullets:
		if b.life <= 0.0 or b.pos.distance_to(pos) > r:
			continue
		if not b.get("acuity", false):
			b["acuity"] = true
			b.vel *= f
			b.life = b.life / f
	if acuity_t <= 0.0:
		# 结束：范围内弹幕全部消失
		var n := 0
		for b in g.ebullets:
			if b.life > 0.0 and b.pos.distance_to(pos) <= r:
				b.life = 0.0
				n += 1
				fx({"kind": "glow", "pos": b.pos, "r": 8.0, "life": 0.25, "col": INK, "alpha": 0.6})
		if n > 0:
			g._add_text(pos + Vector2(0, -70), "消除弹幕 ×%d" % n, INK, 15)
		fx({"kind": "ring", "pos": pos, "r": r, "r0": r * 0.5, "life": 0.5, "col": INK, "floor": true})


# ---------------------------------------------------------------- 绘制

func draw_auras() -> void:
	if acuity_t > 0.0 and pos != Vector2.INF:
		g.draw_set_transform(pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
		g.draw_arc(Vector2.ZERO, _range(), 0.0, TAU, 60, Color(INK.r, INK.g, INK.b, 0.18 + 0.06 * sin(g.t * 3.0)), 2.0)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_skill_over() -> void:
	if lock_t > 0.0 and lock_e != null and not lock_e.dead:
		var p: Vector2 = lock_e.pos + Vector2(0, -lock_e.r - 14)
		var k: float = 0.5 + 0.5 * sin(g.t * 8.0)
		g.draw_arc(p, 6.0 + 2.0 * k, 0.0, TAU, 12, Color(INK.r, INK.g, INK.b, 0.9), 1.5)
		g.draw_line(p + Vector2(-9, 0), p + Vector2(-4, 0), PALE, 1.5)
		g.draw_line(p + Vector2(4, 0), p + Vector2(9, 0), PALE, 1.5)
	if acuity_t > 0.0:
		var q := pos + Vector2(0, -44)
		g.draw_circle(q, 3.0 + sin(g.t * 12.0), Color(INK.r * 1.6, INK.g * 1.6, INK.b * 1.4, 0.8))


func status_items() -> Array:
	var out: Array = []
	if lock_t > 0.0:
		out.append(["提喻", INK])
	if acuity_t > 0.0:
		out.append(["延展敏锐", INK])
	return out
