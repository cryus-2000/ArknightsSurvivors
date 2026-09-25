## 流明（医疗，契约 v2.1，docs/26 第二批）：不治血条，治环境。荧光周期治疗 + 驱散侵蚀 / 神经损伤，顺带射出「照亮」敌人的光弹。
## S1 净化之光：治疗 + 全部驱散 + 短暂免疫 + 灯火；S2 领航灯（永久）：光照半径 +35%、受击灯火流失 ×0.7、荧光回复升到 3%；
## S3 指引灯塔：在博士脚下立起不动的灯塔 10 秒（圣域：回复、免疫负面、溟痕 / 黑潮圈外惩罚失效、灯火回升），结束时光爆。
## 天赋 余晖：每次回复 / 驱散灯火 +2；灯火 ≥70 时自身充能 +20%。
## 挂点：g._heal / g.corrode_pool / g.nerve / g.lamp；光弹是本脚本自己推进的投射物（不改 game.gd 的子弹表）；
## 圣域通过 sanctuary()、光照半径通过 light_radius_mult() 供 game.gd 询问（同 dmg_taken_mult 模式）。
extends "res://scripts/characters/character.gd"

const WARM := Color(1.0, 0.85, 0.55)
const PALE := Color(0.7, 0.9, 1.0)

var cd := 1.0                  # 光弹间隔
var heal_t := 0.0              # 荧光治疗 / 驱散计时（每 heal_cd 秒在下一次出手时结算）
var immune_t := 0.0            # S1：免疫神经损伤剩余
var guiding := false           # S2 领航灯（永久）
var tower_t := 0.0             # S3 灯塔剩余
var tower_pos := Vector2.INF
var tower_tick := 0.0
var bolts: Array = []          # 光弹：{pos, vel, dmg, life}
var mote_t := 0.0


func _heal_mult() -> float:
	return stat(&"op_atk") * g.ally_mult


# ---------------------------------------------------------------- 每帧

func update(dt: float) -> void:
	cd -= dt
	immune_t = maxf(0.0, immune_t - dt)
	if immune_t > 0.0:
		g.nerve = 0.0
	_update_bolts(dt)
	_update_tower(dt)
	# 天赋：充盈时自身额外充能 20%
	if elite >= 1 and g.lamp >= 70.0:
		for i in 3:
			if skill_unlocked(i) and sp_need(i) > 0.0 and not perm[i] and skill_active_left(i) <= 0.0:
				sp[i] = minf(sp_need(i), sp[i] + dt * 0.2 * g.sp_mult * stat(&"op_skill_sp") * g._lamp_sp())
	if acting():
		return
	var ready := charge_skills(dt)
	if ready >= 0:
		start_skill(g.ppos, ready)
		return
	heal_t += dt
	if cd <= 0.0:
		cd = base("bolt_cd", 1.0) / stat(&"op_aspd")
		var ts: Array = g._nearest(1, base("bolt_range", 360.0) * stat(&"op_range"), pos)
		if not ts.is_empty() or heal_t >= base("heal_cd", 3.0):
			start_attack(ts[0].pos if not ts.is_empty() else g.ppos)


## 荧光出手帧（灯最亮）：到点则驱散优先、其次治疗；同时向最近敌人射光弹
func _release() -> void:
	var lamp_hand: Vector2 = pos + Vector2(10.0 * face, -26)
	var did := false
	if heal_t < base("heal_cd", 3.0):
		pass
	elif g.corrode_pool > 0.5 or g.nerve > 0.5:
		g.corrode_pool = 0.0
		g.nerve = maxf(0.0, g.nerve - 15.0)
		g._add_text(g.ppos + Vector2(0, -96), "驱散", PALE, 14)
		did = true
	elif g.hp < g.max_hp:
		_heal_doctor(g.max_hp * base("heal_pct", 0.02) * (1.5 if guiding else 1.0) * _heal_mult(), 15)
		did = true
	if did:
		heal_t = 0.0
		_talent_lamp()
		g.fx.append({"kind": "beam", "a": lamp_hand, "b": g.ppos + Vector2(0, -24), "life": 0.25, "max": 0.25, "col": WARM, "w": 2.5})
	fx({"kind": "glow", "pos": lamp_hand, "r": 12.0, "life": 0.3, "col": WARM, "alpha": 0.6})
	# 光弹
	var ts: Array = g._nearest(1, base("bolt_range", 360.0) * stat(&"op_range"), pos)
	if not ts.is_empty():
		var d: Vector2 = (ts[0].pos - lamp_hand).normalized()
		bolts.append({"pos": lamp_hand, "vel": d * 380.0, "dmg": base("bolt_atk", 8.0) * _dmg_bonus(), "life": 1.4})
		Sfx.op(id, "atk", 0.0, 1.0, 0.08)


func _heal_doctor(h: float, size: int) -> void:
	if h <= 0.0:
		return
	g._heal(h, "流明")
	g._add_text(g.ppos + Vector2(0, -90), "+%d" % int(h), WARM, size)
	g._fx_sprite("fx_holy_impact_lantern", g.ppos + Vector2(0, -34), g.PX * 0.9)
	if not g._fx_sprite("fx_heal_aura_amber", g.ppos + Vector2(0, 6), g.PX * 1.2, 0.0, false, true):
		fx({"kind": "ring", "pos": g.ppos, "r": 28.0, "r0": 8.0, "life": 0.4, "col": WARM, "floor": true})


## 天赋余晖：每次回复 / 驱散灯火 +2
func _talent_lamp() -> void:
	if elite >= 1:
		g.lamp = minf(g.lamp_cap, g.lamp + base("talent_lamp", 2.0))


func _update_bolts(dt: float) -> void:
	if bolts.is_empty():
		return
	for b in bolts:
		b.pos += b.vel * dt
		b.life -= dt
		mote_t -= dt
		for j in g._query(b.pos, 30.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or e.pos.distance_to(b.pos) > e.r + 8.0:
				continue
			g._hit("光弹")
			g._damage(e, b.dmg)
			e["lit"] = 3.0
			Sfx.op(id, "hit")
			# 小范围溅射（60%），溅到的也被照亮
			var ar: float = base("bolt_aoe", 24.0)
			for j2 in g._query(b.pos, ar + 20.0):
				var o: Dictionary = g.enemies[j2]
				if o.dead or is_same(o, e) or o.pos.distance_to(b.pos) > ar + o.r:
					continue
				g._hit("光弹")
				g._damage(o, b.dmg * 0.6)
				o["lit"] = 3.0
			b.life = 0.0
			if not g._fx_sprite("fx_holy_impact_lantern", e.pos + Vector2(0, -e.r * 0.5), g.PX * 0.7):
				fx({"kind": "glow", "pos": e.pos + Vector2(0, -e.r * 0.5), "r": 12.0, "life": 0.25, "col": WARM, "alpha": 0.6})
			fx_sparks(e.pos + Vector2(0, -e.r * 0.5), WARM, 4, 120.0, 0.3, 2.0)
			break
	bolts = bolts.filter(func(b): return b.life > 0.0)


# ---------------------------------------------------------------- 技能

func _release_skill() -> void:
	match cur_skill:
		0:
			_heal_doctor(g.max_hp * base("s1_heal", 0.06) * _heal_mult() * skill_power(), 18)
			g.corrode_pool = 0.0
			g.nerve = 0.0
			immune_t = 3.0
			g.lamp = minf(g.lamp_cap, g.lamp + base("s1_lamp", 8.0))
			_talent_lamp()
			g._fx_sprite("fx_holy_pillar_amber", g.ppos + Vector2(0, 4), g.PX * 1.1, 0.0, false, true)
			g._fx_sprite("fx_circle_amber", g.ppos + Vector2(0, 4), g.PX * 1.8)
			g._add_text(g.ppos + Vector2(0, -110), "净化", PALE, 15)
		1:
			guiding = true
			g.stats.add(&"light_decay", "mult", 0.7, "lumen_guiding")
			g._sync_stats()
			g._show_banner("领航灯：博士光照永久扩大")
			g._fx_sprite("fx_sunburst", g.ppos + Vector2(0, -20), g.PX * 1.4)
		2:
			tower_pos = g.ppos
			tower_t = base("s3_dur", 10.0)
			tower_tick = 0.0
			g._show_banner("指引灯塔")
			g._fx_sprite("fx_holy_pillar_amber", tower_pos + Vector2(0, 4), g.PX * 1.6, 0.0, false, true)
			fx({"kind": "ring", "pos": tower_pos, "r": base("s3_r", 220.0), "r0": 20.0, "life": 0.7, "col": WARM, "floor": true, "w": 3.0})
	# 技能发动音 op_lumen_s1/s2/s3 由 spend_sp 播放


func skill_active_left(i: int) -> float:
	return tower_t if i == 2 else 0.0


func skill_active_dur(i: int) -> float:
	return base("s3_dur", 10.0) if i == 2 else 1.0


## game.gd 询问：博士光照半径倍率（S2 领航灯）
func light_radius_mult() -> float:
	return 1.35 if guiding else 1.0


## game.gd 询问：圣域（灯塔）{pos, r}，没有返回空字典
func sanctuary() -> Dictionary:
	if tower_t > 0.0 and tower_pos != Vector2.INF:
		return {"pos": tower_pos, "r": base("s3_r", 220.0)}
	return {}


func _in_tower(p: Vector2) -> bool:
	return tower_t > 0.0 and p.distance_to(tower_pos) < base("s3_r", 220.0)


func _update_tower(dt: float) -> void:
	if tower_t <= 0.0:
		return
	tower_t -= dt
	var r: float = base("s3_r", 220.0)
	if _in_tower(g.ppos):
		g.corrode_pool = 0.0
		g.nerve = 0.0
		tower_tick += dt
		if tower_tick >= 1.0:
			tower_tick -= 1.0
			g.lamp = minf(g.lamp_cap, g.lamp + base("s3_lamp", 2.0))
			if g.hp < g.max_hp:
				g._heal(g.max_hp * base("s3_heal", 0.015) * _heal_mult(), "流明")
				_talent_lamp()
	# 塔顶光点 + 区内漂浮光尘
	mote_t -= dt
	if mote_t <= 0.0:
		mote_t = 0.06
		var a: float = g.rng.randf() * TAU
		var rr: float = g.rng.randf() * r
		fx({"kind": "mote", "pos": tower_pos + Vector2(cos(a) * rr, sin(a) * rr * 0.55), "vel": Vector2(0, -35), "life": 0.8, "col": WARM, "sz": 1.8})
	if tower_t <= 0.0:
		_light_burst()


## 灯塔结束：范围内法伤 ×3 并眩晕 0.6 秒
func _light_burst() -> void:
	var r: float = base("s3_r", 220.0)
	area_hit("光爆", tower_pos, r, base("bolt_atk", 8.0) * base("s3_burst_mult", 3.0) * _dmg_bonus() * skill_power(), 160.0, 0.6)
	g._fx_sprite("fx_sunburst", tower_pos + Vector2(0, -40), g.PX * 2.4)
	for i in 3:
		fx({"kind": "ring", "pos": tower_pos, "r": r * (0.6 + 0.2 * i), "r0": 16.0, "life": 0.4 + 0.1 * i, "col": WARM, "floor": true, "w": 4.0 - i})
	g.fx.append({"kind": "rays", "pos": tower_pos + Vector2(0, -40), "life": 0.6, "max": 0.6, "col": WARM})
	fx_sparks(tower_pos + Vector2(0, -30), WARM, 18, 240.0, 0.5, 3.0, 160.0)
	g._add_text(tower_pos + Vector2(0, -90), "光爆", WARM, 18)
	g.shake = maxf(g.shake, 4.0)
	Sfx.op(id, "big")
	tower_pos = Vector2.INF


# ---------------------------------------------------------------- 绘制

func draw_auras() -> void:
	if tower_t > 0.0 and tower_pos != Vector2.INF:
		var r: float = base("s3_r", 220.0)
		g.draw_set_transform(tower_pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
		g.draw_circle(Vector2.ZERO, r, Color(WARM.r, WARM.g, WARM.b, 0.05))
		g.draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(WARM.r, WARM.g, WARM.b, 0.35 + 0.1 * sin(g.t * 4.0)), 2.5)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func draw_entities_over() -> void:
	for b in bolts:
		if g.tex.get("proj_lumen_bolt") != null:
			g._spr_rot("proj_lumen_bolt", int(g.t * 12.0 + b.pos.x * 0.05) % 6, b.pos, b.vel.angle(), g.PX)
		else:
			g.draw_line(b.pos - b.vel.normalized() * 14.0, b.pos, Color(WARM.r * 1.4, WARM.g * 1.3, WARM.b, 0.5), 3.0)
			g.draw_circle(b.pos, 4.0, Color(2.0, 1.8, 1.2))


func draw_fx_add(ci: CanvasItem, _loop: int) -> void:
	# 灯塔光柱与光区（加法层）
	if tower_t > 0.0 and tower_pos != Vector2.INF:
		var k: float = 0.5 + 0.5 * sin(g.t * 3.0)
		ci.draw_circle(tower_pos + Vector2(0, -100), 26.0 + 4.0 * k, Color(0.9, 0.7, 0.35, 0.35))
		ci.draw_set_transform(tower_pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
		ci.draw_circle(Vector2.ZERO, base("s3_r", 220.0) * 0.9, Color(0.6, 0.45, 0.2, 0.06 + 0.02 * k))
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for b in bolts:
		ci.draw_circle(b.pos, 9.0, Color(0.9, 0.7, 0.3, 0.35))


func extra_bodies() -> Array:
	if tower_t > 0.0 and tower_pos != Vector2.INF:
		return [{"y": tower_pos.y + 2.0}]
	return []


func draw_extra(_it: Dictionary) -> void:
	var tx: Texture2D = anim_tex("lighthouse")
	if tx == null:
		g.draw_rect(Rect2(tower_pos + Vector2(-8, -60), Vector2(16, 60)), Color(0.5, 0.6, 0.7))
		return
	var n: int = anim_hframes(tx, "lighthouse")
	var fr: int = 1 if int(g.t * 4.0) % 2 == 1 else 0
	g._draw_sprite_at(tower_pos, false, Color.WHITE, fr % n, tx, n, foot_off(tx, "lighthouse"))


func draw_extra_shadows() -> void:
	if tower_t > 0.0 and tower_pos != Vector2.INF:
		g._spr("shadow", 1, 0, tower_pos + Vector2(0, 4), g.PX * 1.5)


func status_items() -> Array:
	var out: Array = []
	if tower_t > 0.0:
		out.append(["灯塔", WARM])
	if immune_t > 0.0:
		out.append(["净化", PALE])
	return out
