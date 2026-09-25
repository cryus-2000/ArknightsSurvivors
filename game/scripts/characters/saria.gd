## 塞雷娅（重装，契约 v2.1）：护博士。站在博士身侧；阻挡圈把贴近博士的敌人推开并减速，持盾盾击击退身前敌人（攻击较高；原作档案：盾即法杖）。
## 技能全部是治疗，不给护盾（护盾太强）：S1 急救：回复 8%（低血翻倍）；S2 药剂散布：回复 10% + 5 秒持续回复；S3 钙质化：8 秒琥珀区域，敌人减速 + 易伤，博士持续回复。
## 特效（docs/25）：琥珀。阻挡圈为地面分段虚线环；盾击为一道短而宽的琥珀盾弧向前撞出；钙质化在博士周围升起琥珀晶柱。
## 可见成长（docs/25 §5.2）：N1 钙质沉积 3 枚环绕钙晶 → N2 晶簇 5 枚；N4 急救针剂：急救掷出 3 支注射器；
## N5 碎晶：钙质化期间每 1.2 秒击碎一根晶柱，碎片飞向区域内敌人；精二「莱茵充能护服」：护服 4 格充能，满格下一次盾击变为全方位冲击。
extends "res://scripts/characters/character.gd"

const AMBER := Color(1.0, 0.72, 0.38)
const S3_DUR := 8.0
const S3_R := 180.0
const SHOT_MAX := 12          # 同时存在的注射器 + 碎晶片上限

var cd := 0.5
var block_t := 0.0
var calc := 0.0               # S3 钙质化剩余
var calc_acc := 0.0
var shard_t := 0.0
var hot_t := 0.0              # S2 持续回复剩余
var hot_acc := 0.0
# ---- 可见成长
var orb_n := 0                # N1 / N2：环绕钙晶数量（0 / 3 / 5）
var orb_cd: Dictionary = {}   # 敌人 id → 钙晶命中冷却
var syringe_on := false       # N4 急救针剂
var shatter_on := false       # N5 碎晶
var shatter_t := 0.0
var pillars: Array = []       # 钙质化期间长出的晶柱 {pos, ref}（ref = 晶柱特效条目，击碎时提前结束）
var shots: Array = []         # 投射物 {kind: syringe / shard, pos, vel, t, dmg}
var suit_on := false          # 精二 莱茵充能护服
var suit_seg := 0             # 已充满的格数（0–4）
var suit_t := 0.0


## 基础数值全部可由 data/characters/saria.json 的 base 段覆盖（docs/27 §3）
func block_radius() -> float:
	return base("block_r", 62.0) * stat(&"op_range")


func _reach() -> float:
	return base("reach", 70.0) * stat(&"op_range")


## 站位：博士面前一侧（贴身护卫），不前压
func follow_target(_slot_pos: Vector2) -> Vector2:
	return g.ppos + Vector2(26.0 * g.facing, 6)


## 盾击基础伤害（成长节点的额外命中都按它折算）
func _bash_dmg() -> float:
	return base("atk", 28.0) * _dmg_bonus()


## 成长节点（data/characters/saria.json 的 custom 节点）
func on_custom_node(nid: String, _choice: String = "") -> void:
	match nid:
		"calc_orb":
			orb_n = int(base("orb_n1", 3.0))
		"calc_cluster":
			orb_n = int(base("orb_n2", 5.0))
		"syringe":
			syringe_on = true
		"shatter":
			shatter_on = true


func on_elite(stage: int, _choice: String = "") -> void:
	if stage >= 2:
		suit_on = true


func update(dt: float) -> void:
	cd -= dt
	_block(dt)
	_update_orbs(dt)
	_update_shots(dt)
	# 精二 莱茵充能护服：每 5 秒充满一格，4 格满后等下一次盾击放出
	if suit_on and suit_seg < 4:
		suit_t += dt
		if suit_t >= base("suit_seg_t", 5.0):
			suit_t = 0.0
			suit_seg += 1
			fx({"kind": "glow", "pos": pos + Vector2(-19.5 + (suit_seg - 1) * 13.0, 14), "r": 6.0, "life": 0.25, "col": AMBER, "alpha": 0.7})
	if hot_t > 0.0:
		hot_t -= dt
		hot_acc += dt
		if hot_acc >= 1.0:
			hot_acc -= 1.0
			if g.hp < g.max_hp:
				g._heal(g.max_hp * 0.01, "塞雷娅")
				fx({"kind": "mote", "pos": g.ppos + Vector2(g.rng.randf_range(-16, 16), -20), "vel": Vector2(0, -35), "life": 0.7, "col": AMBER, "sz": 2.0})
	if calc > 0.0:
		calc -= dt
		calc_acc += dt
		if calc_acc >= 1.0:
			calc_acc -= 1.0
			if g.hp < g.max_hp:
				g._heal(g.max_hp * 0.015, "塞雷娅")
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
			_calcite(g.ppos + Vector2(cos(a) * rr, sin(a) * rr * 0.55 + 4.0), g.rng.randf_range(0.6, 0.85), g.rng.randf_range(12, 24), 1.2)
		# N5 碎晶：每 1.2 秒亲手击碎一根晶柱，碎片飞向区域内的敌人
		if shatter_on:
			shatter_t -= dt
			if shatter_t <= 0.0 and _shatter():
				shatter_t = base("shatter_every", 1.2)
	else:
		pillars.clear()
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
	# 精二 莱茵充能护服满格：这一击变成全方位冲击（半径 110、×1.8、强击退），之后清零重新充能
	if suit_seg >= 4:
		suit_seg = 0
		suit_t = 0.0
		_suit_blast()
		return
	var hits := melee_hit("盾击", pos + Vector2(0, -10), ang, 1.1, _reach(), _bash_dmg(), 200.0, 0.2)
	# 盾击（用户定：原作档案「盾即法杖」，不是出拳）：一道短而宽的琥珀盾弧从身前向前撞出，身后三道推力短线
	fx({"kind": "bash", "pos": pos + Vector2(0, -14), "ang": ang, "reach": _reach(), "life": 0.2})
	Sfx.op(id, "hit" if not hits.is_empty() else "atk")


func _hit_fx(e: Dictionary, origin: Vector2) -> void:
	fx({"kind": "glow", "pos": e.pos + Vector2(0, -e.r * 0.5), "r": 8.0, "life": 0.14, "col": AMBER, "alpha": 0.5})
	var dv: Vector2 = (e.pos - origin).normalized()
	for k in 2:
		fx({"kind": "spark", "pos": e.pos + Vector2(0, -e.r * 0.5), "vel": dv.rotated(g.rng.randf_range(-0.7, 0.7)) * g.rng.randf_range(120, 220), "life": 0.2, "col": AMBER, "sz": 2.0, "drag": 3.0})


## 莱茵充能护服：以自身为中心的全方位盾击冲击波；六面盾弧向外撞出 + 两道贴地冲击环
func _suit_blast() -> void:
	var r: float = base("suit_r", 110.0)
	var hits := melee_hit("盾击", pos + Vector2(0, -6), 0.0, PI, r, _bash_dmg() * base("suit_mult", 1.8), base("suit_kb", 320.0), 0.3, ["empowered"])
	for k in 6:
		fx({"kind": "bash", "pos": pos + Vector2(0, -14), "ang": k * TAU / 6.0, "reach": r * 0.8, "life": 0.26, "big": true})
	fx({"kind": "ring", "pos": pos, "r": r, "r0": 16.0, "life": 0.35, "col": AMBER, "floor": true, "w": 4.0})
	fx({"kind": "ring", "pos": pos, "r": r * 0.7, "r0": 8.0, "life": 0.45, "col": Color(1.6, 1.3, 0.8), "floor": true, "w": 2.0})
	fx({"kind": "glow", "pos": pos + Vector2(0, -26), "r": 26.0, "life": 0.25, "col": AMBER, "alpha": 0.6})
	fx_sparks(pos + Vector2(0, -16), AMBER, 12, 260.0, 0.4, 2.5, 160.0)
	if not hits.is_empty():
		g.hitstop = maxf(g.hitstop, 0.05)
	Sfx.op(id, "hit", 4.0, 0.8)


## 钙质晶体（Codex：冷白主体 + 琥珀边，从地面长出 → 停留 → 碎裂）；缺图退回程序琥珀晶柱。返回该晶柱的特效条目
func _calcite(p: Vector2, sc: float, h: float, life: float) -> Dictionary:
	var ref: Dictionary = {}
	if g._fx_sprite("fx_saria_calcite", p, g.PX * sc, 0.0, g.rng.randf() < 0.5, true):
		ref = g.fx.back()
	else:
		fx({"kind": "crystal", "pos": p, "h": h, "life": life, "col": AMBER, "lean": g.rng.randf_range(-0.3, 0.3)})
		ref = pfx.back()
	# 碎晶：钙质化期间记下长出的晶柱，供击碎
	if shatter_on and calc > 0.0:
		pillars.append({"pos": p, "ref": ref})
		if pillars.size() > 12:
			pillars.pop_front()
	return ref


# ---------------------------------------------------------------- 可见成长

## 环绕钙晶的地面位置：绕塞雷娅一圈，半径略大于阻挡圈（阻挡圈把敌人推到 62 之外，钙晶正好扫在圈边）。
## 判定用真实圆（和阻挡圈同一度量），不做贴地压扁，否则上下两侧永远碰不到被推开的敌人
func _orb_ground(k: int) -> Vector2:
	var a: float = g.t * base("orb_spin", 2.2) + k * TAU / float(maxi(1, orb_n))
	var R: float = base("orb_r", 70.0)
	return pos + Vector2(cos(a) * R, sin(a) * R + 2.0)


## 钙质沉积 / 晶簇：环绕的钙晶撞到敌人造成盾击 30% 伤害，同一敌人 0.5 秒冷却
func _update_orbs(dt: float) -> void:
	if orb_n <= 0 or pos == Vector2.INF:
		return
	for k in orb_cd.keys():
		orb_cd[k] -= dt
		if orb_cd[k] <= 0.0:
			orb_cd.erase(k)
	var dmg: float = _bash_dmg() * base("orb_mult", 0.18)
	for k in orb_n:
		var p: Vector2 = _orb_ground(k)
		for j in g._query(p, 40.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or orb_cd.has(e.id) or e.pos.distance_to(p) > 12.0 + e.r:
				continue
			orb_cd[e.id] = base("orb_cd", 0.5)
			g._hit("钙晶")
			g._damage(e, dmg)
			fx({"kind": "glow", "pos": p + Vector2(0, -16), "r": 7.0, "life": 0.14, "col": AMBER, "alpha": 0.6})
			fx({"kind": "shard", "pos": p + Vector2(0, -16), "vel": Vector2.from_angle(g.rng.randf() * TAU) * 90.0, "life": 0.22, "col": AMBER, "sz": 3.0, "ang": g.rng.randf() * TAU, "spin": 12.0})


## 投射物：直线飞行，碰到第一个敌人即命中；注射器附带减速
func _shoot(kind: String, from: Vector2, to: Vector2, spd: float, dmg: float) -> void:
	if shots.size() >= SHOT_MAX:
		return
	var d: Vector2 = (to - from).normalized() if to.distance_to(from) > 1.0 else Vector2(face, 0)
	shots.append({"kind": kind, "pos": from, "vel": d * spd, "t": 0.7, "dmg": dmg, "ang": d.angle()})


func _update_shots(dt: float) -> void:
	if shots.is_empty():
		return
	for s in shots:
		s.t -= dt
		s.pos += s.vel * dt
		# 投射物飞在腰高（-16），按地面位置判定
		var gp: Vector2 = s.pos + Vector2(0, 16)
		for j in g._query(gp, 36.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or e.pos.distance_to(gp) > 6.0 + e.r:
				continue
			if s.kind == "syringe":
				g._hit("急救针剂")
				g._damage(e, s.dmg)
				if not e.dead:
					e.slow = maxf(e.slow, base("syringe_slow", 2.0))
				fx({"kind": "glow", "pos": s.pos, "r": 7.0, "life": 0.18, "col": Color(0.7, 1.2, 0.9), "alpha": 0.6})
			else:
				g._hit("碎晶")
				g._damage(e, s.dmg)
				fx({"kind": "glow", "pos": s.pos, "r": 8.0, "life": 0.16, "col": AMBER, "alpha": 0.6})
				for q in 3:
					fx({"kind": "shard", "pos": s.pos, "vel": Vector2.from_angle(g.rng.randf() * TAU) * 110.0, "life": 0.25, "col": AMBER, "sz": 2.5, "ang": g.rng.randf() * TAU, "spin": 14.0})
			s.t = 0.0
			break
	shots = shots.filter(func(s): return s.t > 0.0)


## 碎晶：挑一根已长成的晶柱击碎（特效提前结束 + 迸裂），碎片飞向区域内最近的至多 4 名敌人；没有目标就先不碎
func _shatter() -> bool:
	pillars = pillars.filter(func(pl): return pl.ref.get("life", 0.0) > 0.25)
	if pillars.is_empty():
		return false
	var pl: Dictionary = pillars[g.rng.randi() % pillars.size()]
	var p: Vector2 = pl.pos
	var ts: Array = g._nearest(8, S3_R * 2.0, p).filter(func(e): return e.pos.distance_to(g.ppos) <= S3_R + e.r)
	if ts.is_empty():
		return false
	pillars.erase(pl)
	pl.ref.life = 0.001
	# 晶柱迸裂：亮闪 + 一圈琥珀碎片 + 小冲击环
	fx({"kind": "glow", "pos": p + Vector2(0, -18), "r": 16.0, "life": 0.22, "col": Color(1.8, 1.4, 0.8), "alpha": 0.8})
	fx({"kind": "ring", "pos": p, "r": 26.0, "r0": 4.0, "life": 0.25, "col": AMBER, "floor": true, "w": 2.0})
	for q in 8:
		fx({"kind": "shard", "pos": p + Vector2(0, -16), "vel": Vector2.from_angle(g.rng.randf() * TAU) * g.rng.randf_range(80, 170), "life": 0.35, "col": AMBER,
			"sz": g.rng.randf_range(3.0, 5.0), "ang": g.rng.randf() * TAU, "spin": g.rng.randf_range(-14, 14), "grav": 260.0})
	var dmg: float = _bash_dmg() * base("shatter_mult", 0.5) * skill_power()
	for k in mini(int(base("shatter_n", 4.0)), ts.size()):
		_shoot("shard", p + Vector2(0, -16), ts[k].pos + Vector2(0, -16), 560.0, dmg)
	Sfx.op(id, "hit", -2.0, 1.3)
	return true


func _heal_fx(h: float) -> void:
	g._add_text(g.ppos + Vector2(0, -90), "+%d" % int(h), AMBER, 16)
	for k in 6:
		fx({"kind": "mote", "pos": g.ppos + Vector2(g.rng.randf_range(-20, 20), g.rng.randf_range(-40, -10)), "vel": Vector2(0, -35), "life": 0.8, "col": AMBER, "sz": 2.5})
	# 治疗光环（Ninja Adventure Aura 调琥珀）+ 星光命中（Pimen）
	g._fx_sprite("fx_heal_aura_amber", g.ppos + Vector2(0, 6), g.PX * 1.4, 0.0, false, true)
	g._fx_sprite("fx_holy_impact", g.ppos + Vector2(0, -34), g.PX)


func _release_skill() -> void:
	match cur_skill:
		0:
			# 急救
			var h: float = g.max_hp * base("s1_heal", 0.08) * skill_power() * (2.0 if g.hp < g.max_hp * 0.5 else 1.0)
			g._heal(h, "塞雷娅")
			_heal_fx(h)
			fx({"kind": "ring", "pos": g.ppos, "r": 40.0, "r0": 8.0, "life": 0.4, "col": AMBER, "floor": true})
			# N4 急救针剂（档案：她随身带着注射器）：同时朝附近 3 名敌人掷出注射器，×0.6 盾击伤害并减速 2 秒
			if syringe_on:
				var dmg: float = _bash_dmg() * base("syringe_mult", 0.6) * skill_power()
				for e in g._nearest(int(base("syringe_n", 3.0)), 260.0, pos):
					_shoot("syringe", pos + Vector2(8.0 * face, -24), e.pos + Vector2(0, -16), 460.0, dmg)
		1:
			# 药剂散布：立即回复 + 5 秒持续回复
			var h2: float = g.max_hp * base("s2_heal", 0.10) * skill_power()
			g._heal(h2, "塞雷娅")
			_heal_fx(h2)
			hot_t = 5.0
			hot_acc = 0.0
			fx({"kind": "ring", "pos": g.ppos, "r": 60.0, "r0": 10.0, "life": 0.5, "col": AMBER, "floor": true})
			g._fx_sprite("fx_shield_amber", g.ppos + Vector2(0, -26), g.PX * 1.6)
		2:
			# 钙质化：晶柱升起 + 区域
			calc = S3_DUR
			calc_acc = 0.0
			for k in 8:
				var a: float = k * TAU / 8.0 + 0.3
				_calcite(g.ppos + Vector2(cos(a) * 34.0, sin(a) * 34.0 * 0.55 + 4.0), g.rng.randf_range(0.9, 1.15), g.rng.randf_range(22, 40), 1.5 + k * 0.03)
			fx({"kind": "ring", "pos": g.ppos, "r": S3_R, "r0": 30.0, "life": 0.5, "col": AMBER, "floor": true, "w": 4.0})
			fx({"kind": "crack", "pos": g.ppos, "r": 90.0, "life": 0.45, "col": AMBER, "floor": true, "n": 10})
			# 琥珀光柱 + 地面法阵（Pimen / Ninja Adventure 调色）
			g._fx_sprite("fx_holy_pillar_amber", g.ppos + Vector2(0, 6), g.PX * 1.5, 0.0, false, true)
			g._fx_sprite("fx_circle_amber", g.ppos + Vector2(0, 6), g.PX * 3.0)
			g._show_banner("钙质化")
			g.shake = maxf(g.shake, 3.0)


func skill_active_left(i: int) -> float:
	return calc if i == 2 else 0.0


func skill_active_dur(i: int) -> float:
	return S3_DUR if i == 2 else 1.0


func _draw_pfx(f: Dictionary, a: float) -> bool:
	if f.kind == "bash":
		_draw_bash(f, a)
		return true
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
	# （阻挡圈上原来的三枚装饰小晶体已去掉：环绕的晶体改由 N1 / N2 的钙晶表示，数量 = 节点成长，一眼可数）


## 盾击：一道短而宽的琥珀盾弧（凸面朝前）由身前 10px 撞到约 0.45 × 射程处，内侧暗描边、外缘白热亮边；身后三道推力短线。
## big = 护服冲击（六面同时撞出，更厚更远）
func _draw_bash(f: Dictionary, a: float) -> void:
	var u: float = 1.0 - a
	var ek: float = 1.0 - (1.0 - minf(1.0, u / 0.6)) * (1.0 - minf(1.0, u / 0.6))
	var d: Vector2 = Vector2.from_angle(f.ang)
	var big: bool = f.get("big", false)
	var R: float = 30.0 if big else 24.0
	var half: float = 1.05 if not big else 0.5
	var c: Vector2 = f.pos + d * (10.0 + f.reach * 0.45 * ek)
	var o: Vector2 = c - d * R
	var w: float = (9.0 if big else 7.0) * (0.55 + 0.45 * a)
	g.draw_arc(o, R, f.ang - half, f.ang + half, 14, Color(0.25, 0.14, 0.05, 0.75 * a), w + 3.0)
	g.draw_arc(o, R, f.ang - half, f.ang + half, 14, Color(AMBER.r * 1.3, AMBER.g * 1.2, AMBER.b, 0.95 * a), w)
	g.draw_arc(o, R + w * 0.4, f.ang - half * 0.85, f.ang + half * 0.85, 12, Color(2.2, 1.9, 1.3, a), 1.5)
	# 盾面上的纹章竖线（盾即法杖）
	g.draw_line(c - d * 2.0, c - d * (w + 2.0), Color(2.0, 1.7, 1.1, 0.8 * a), 2.0)
	for s in [-1.0, 0.0, 1.0]:
		var off: Vector2 = d.orthogonal() * s * R * 0.55
		g.draw_line(c - d * 10.0 + off, c - d * (22.0 + 6.0 * absf(s)) + off, Color(AMBER.r * 1.4, AMBER.g * 1.3, AMBER.b, 0.5 * a), 1.5)


## 角色之上：环绕钙晶、注射器 / 碎晶片、护服充能格
func _draw_skill_over() -> void:
	if pos == Vector2.INF:
		return
	# 环绕钙晶（N1 3 枚 / N2 5 枚）：冷白菱形晶体 + 琥珀边，腰高绕行，身后的略暗；地面一点投影
	for k in orb_n:
		var gp: Vector2 = _orb_ground(k)
		var back: bool = gp.y < pos.y + 2.0
		var p: Vector2 = gp + Vector2(0, -16 + sin(g.t * 3.0 + k) * 2.0)
		var al: float = 0.6 if back else 1.0
		g.draw_set_transform(gp, 0.0, Vector2(1.0, 0.45))
		g.draw_circle(Vector2.ZERO, 5.0, Color(0.0, 0.0, 0.0, 0.25 * al))
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		g.draw_circle(p, 8.0, Color(AMBER.r, AMBER.g, AMBER.b, 0.18 * al))
		var dia := PackedVector2Array([p + Vector2(0, -9), p + Vector2(4.5, -1), p + Vector2(0, 6), p + Vector2(-4.5, -1)])
		g.draw_colored_polygon(dia, Color(1.35, 1.3, 1.15, 0.9 * al))
		g.draw_polyline(PackedVector2Array([dia[0], dia[1], dia[2], dia[3], dia[0]]), Color(AMBER.r * 1.5, AMBER.g * 1.3, AMBER.b, al), 1.5)
		g.draw_line(p + Vector2(0, -7), p + Vector2(0, 4), Color(2.2, 2.0, 1.6, 0.8 * al), 1.0)
	# 投射物：注射器（白筒 + 绿药液 + 针尖）/ 碎晶片（旋转的琥珀三角）
	for s in shots:
		var d: Vector2 = Vector2.from_angle(s.ang)
		if s.kind == "syringe":
			g.draw_line(s.pos - d * 7.0, s.pos + d * 4.0, Color(0.1, 0.1, 0.12, 0.8), 5.0)
			g.draw_line(s.pos - d * 6.0, s.pos + d * 3.0, Color(1.6, 1.6, 1.6), 3.0)
			g.draw_line(s.pos - d * 2.0, s.pos + d * 3.0, Color(0.6, 1.5, 0.9), 2.0)
			g.draw_line(s.pos + d * 4.0, s.pos + d * 9.0, Color(2.0, 2.0, 2.0), 1.0)
			g.draw_line(s.pos - d * 8.0 + d.orthogonal() * 3.0, s.pos - d * 8.0 - d.orthogonal() * 3.0, Color(1.4, 1.4, 1.4), 1.5)
		else:
			var sv: Vector2 = Vector2.from_angle(s.ang + g.t * 16.0) * 5.0
			g.draw_line(s.pos - d * 14.0, s.pos, Color(AMBER.r, AMBER.g, AMBER.b, 0.35), 2.0)
			g.draw_colored_polygon(PackedVector2Array([s.pos - sv, s.pos + sv.orthogonal() * 0.5, s.pos + sv]), Color(1.9, 1.5, 0.9))
	# 精二 护服充能：脚下 4 格琥珀，满格时一起脉动
	if suit_on:
		var full: bool = suit_seg >= 4
		var pul: float = 0.75 + 0.25 * sin(g.t * 10.0) if full else 1.0
		for k in 4:
			var r := Rect2(pos + Vector2(-25.0 + k * 13.0, 12.0), Vector2(11.0, 5.0))
			g.draw_rect(r.grow(1.0), Color(0.12, 0.07, 0.03, 0.85))
			if k < suit_seg:
				g.draw_rect(r, Color(AMBER.r * 1.6 * pul, AMBER.g * 1.4 * pul, AMBER.b * pul))
			elif k == suit_seg:
				var fr: float = clampf(suit_t / base("suit_seg_t", 5.0), 0.0, 1.0)
				g.draw_rect(Rect2(r.position, Vector2(11.0 * fr, 5.0)), Color(AMBER.r, AMBER.g, AMBER.b, 0.45))
		if full:
			g.draw_arc(pos + Vector2(0, -30), 26.0 + 2.0 * sin(g.t * 10.0), 0.0, TAU, 28, Color(AMBER.r * 1.5, AMBER.g * 1.3, AMBER.b, 0.35), 2.0)


func status_items() -> Array:
	var out: Array = []
	if hot_t > 0.0:
		out.append(["药剂散布", AMBER])
	if calc > 0.0:
		out.append(["钙质化", AMBER])
	if suit_on:
		out.append(["护服充能 %d/4" % suit_seg, AMBER, float(suit_seg) / 4.0])
	return out
