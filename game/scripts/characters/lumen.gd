## 流明（医疗，契约 v2.1，docs/26 第二批）：不治血条，治环境。荧光周期治疗 + 驱散侵蚀 / 神经损伤，顺带射出「照亮」敌人的光弹。
## S1 净化之光：治疗 + 全部驱散 + 短暂免疫 + 灯火；S2 领航灯（永久）：光照半径 +35%、受击灯火流失 ×0.7、荧光回复升到 3%；
## S3 指引灯塔（2026-09-26 用户定：跟随主控干员）：10 秒内灯塔悬在主控干员身侧随行，以主控为中心展开光域（圣域：回复、免疫负面、
## 溟痕 / 黑潮圈外惩罚失效、灯火回升），结束时在主控身边光爆。
## 天赋 余晖：每次回复 / 驱散灯火 +2；灯火 ≥70 时自身充能 +20%。
## 挂点：heal_leader / g.corrode_pool / g.nerve / g.lamp；光弹是本脚本自己推进的投射物（不改 game.gd 的子弹表）；
## 圣域通过 sanctuary()、光照半径通过 light_radius_mult() 供 game.gd 询问（同 dmg_taken_mult 模式）。
## 可见成长（docs/25 §5）：N1 发光单元 / N2 灯影成双 / N4 沐雨 / N5 灯塔守望 / 精二质变 灯火不灭。
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
var bolts: Array = []          # 光弹：{pos, vel, dmg, life, src, big, heal}
var mote_t := 0.0
var hand_glow := 0.0            # 出手时提灯的闪光（加法层画，见 draw_fx_add）
# ---- 可见成长（docs/25 §5：只长发光单元；原作依据 档案「灯塔工程师之子、自制发光单元」/ 原作技能 沐雨、灯火不灭）
var units := 0                 # N1 / N2：身边漂浮的发光单元数（0–2）
var unit_cd: Array = [0.5, 1.2]   # 每个单元自己的射击计时（错开出手）
var unit_fire: Array = [-9.0, -9.0]   # 每个单元上次开火的时刻（g.t），帧条开火帧显示约 83ms
var unit_fdir: Array = [1.0, 1.0]     # 上次开火的左右朝向（开火帧闪光朝右画，朝左时镜像）
var rain_on := false           # N4「沐雨」：净化之光时发光单元洒下光雨
var rain_t := 0.0
var rain_tick := 0.0
var watch := false             # N5「灯塔守望」：指引灯塔射出旋转光束
var beam_t := 0.0              # 灯塔守望：净化之光后光束持续（精二前也有）
var beam_tick := 0.0
var beam_hit: Dictionary = {}  # 光束每名敌人的冷却：敌人 id → 剩余秒
var charge_on := false         # 精二质变「灯火不灭」：发光单元攒弹，满 8 发后连射 8 发强化光弹
var charge_n := 0              # 已攒的发数（0–8）
var empowered := 0             # 剩余强化光弹
const BOLT_MAX := 12           # 同时存在的光弹上限


func _heal_mult() -> float:
	return stat(&"op_atk") * g.ally_mult * stat(&"heal_out")


# ---------------------------------------------------------------- 每帧

func update(dt: float) -> void:
	cd -= dt
	hand_glow = maxf(0.0, hand_glow - dt)
	immune_t = maxf(0.0, immune_t - dt)
	if immune_t > 0.0:
		g.nerve = 0.0
	_update_bolts(dt)
	_update_tower(dt)
	_update_units(dt)
	_update_rain(dt)
	_update_beam(dt)
	# 天赋：充盈时自身额外充能 20%
	if elite >= 1 and g.lamp >= 70.0:
		for i in 3:
			if skill_unlocked(i) and sp_need(i) > 0.0 and not perm[i] and skill_active_left(i) <= 0.0:
				sp[i] = minf(sp_need(i), sp[i] + dt * 0.2 * g.sp_mult * stat(&"op_skill_sp") * lamp_sp())
	if acting():
		return
	var ready := charge_skills(dt)
	if ready >= 0:
		start_skill(g.ppos, ready)
		return
	heal_t += dt
	if cd <= 0.0:
		cd = base("bolt_cd", 1.0) / stat(&"op_aspd")
		var ts: Array = nearest_enemies(1, base("bolt_range", 360.0) * stat(&"op_range"), pos)
		if not ts.is_empty() or heal_t >= base("heal_cd", 3.0):
			start_attack(ts[0].pos if not ts.is_empty() else g.ppos)


## 荧光出手帧（灯最亮）：到点则驱散优先、其次治疗；同时向最近敌人射光弹
func _release() -> void:
	var lamp_hand: Vector2 = _lamp_hand()
	var did := false
	if heal_t < base("heal_cd", 3.0):
		pass
	elif g.corrode_pool > 0.5 or g.nerve > 0.5:
		g.corrode_pool = 0.0
		g.nerve = maxf(0.0, g.nerve - 15.0)
		float_text(g.ppos + Vector2(0, -96), "驱散", PALE, 14)
		did = true
	elif g.hp < g.max_hp:
		_heal_doctor(g.max_hp * base("heal_pct", 0.02) * (1.5 if guiding else 1.0) * _heal_mult(), 15)
		did = true
	if did:
		heal_t = 0.0
		_talent_lamp()
		g.fx.append({"kind": "beam", "a": lamp_hand, "b": g.ppos + Vector2(0, -24), "life": 0.25, "max": 0.25, "col": WARM, "w": 2.5})
	hand_glow = 0.3
	# 光弹
	var ts: Array = nearest_enemies(1, base("bolt_range", 360.0) * stat(&"op_range"), pos)
	if not ts.is_empty():
		var d: Vector2 = (ts[0].pos - lamp_hand).normalized()
		if bolts.size() < BOLT_MAX:
			bolts.append({"pos": lamp_hand, "vel": d * 380.0, "dmg": base("bolt_atk", 22.0) * _dmg_bonus(), "life": 1.4, "src": "光弹"})
		Sfx.op(id, "atk", 0.0, 1.0, 0.08)


func _heal_doctor(h: float, size: int) -> void:
	if h <= 0.0:
		return
	heal_leader(h, "流明")
	float_text(g.ppos + Vector2(0, -90), "+%d" % int(h), WARM, size)
	spawn_fx_sprite("fx_holy_impact_lantern", g.ppos + Vector2(0, -34), g.PX * 0.9)
	if not spawn_fx_sprite("fx_heal_aura_amber", g.ppos + Vector2(0, 6), g.PX * 1.2, 0.0, false, true):
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
		for j in query_ids(b.pos, 30.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or e.pos.distance_to(b.pos) > e.r + 8.0:
				continue
			var src: String = b.get("src", "光弹")
			log_hit(src)
			deal_damage(e, b.dmg)
			e["lit"] = 3.0
			Sfx.op(id, "hit", -4.0 if src != "光弹" else 0.0)
			# 灯火不灭：强化光弹命中时为主控回复 0.5% 最大生命
			if b.get("heal", 0.0) > 0.0 and g.hp < g.max_hp:
				heal_leader(b.heal, "流明")
				fx({"kind": "glow", "pos": g.ppos + Vector2(0, -26), "r": 10.0, "life": 0.25, "col": WARM, "alpha": 0.5})
			# 小范围溅射（60%），溅到的也被照亮
			var ar: float = base("bolt_aoe", 24.0)
			for j2 in query_ids(b.pos, ar + 20.0):
				var o: Dictionary = g.enemies[j2]
				if o.dead or is_same(o, e) or o.pos.distance_to(b.pos) > ar + o.r:
					continue
				log_hit(src)
				deal_damage(o, b.dmg * 0.6)
				o["lit"] = 3.0
			b.life = 0.0
			if not spawn_fx_sprite("fx_holy_impact_lantern", e.pos + Vector2(0, -e.r * 0.5), g.PX * 0.7):
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
			spawn_fx_sprite("fx_holy_pillar_amber", g.ppos + Vector2(0, 4), g.PX * 1.1, 0.0, false, true)
			spawn_fx_sprite("fx_circle_amber", g.ppos + Vector2(0, 4), g.PX * 1.8)
			float_text(g.ppos + Vector2(0, -110), "净化", PALE, 15)
			# N5 灯塔守望：主控身上亮起旋转光束 3 秒（精二后指引灯塔全程也有）
			if watch:
				beam_t = base("watch_s1_dur", 3.0)
			# N4 沐雨：发光单元在主控周围洒下光雨 3 秒
			if rain_on and units > 0:
				rain_t = base("rain_dur", 3.0)
				rain_tick = 0.0
		1:
			guiding = true
			g.stats.add(&"light_decay", "mult", 0.7, "lumen_guiding")
			refresh_stats()
			show_banner("领航灯：主控光照永久扩大")
			spawn_fx_sprite("fx_sunburst", g.ppos + Vector2(0, -20), g.PX * 1.4)
		2:
			tower_pos = g.ppos
			tower_t = base("s3_dur", 10.0)
			tower_tick = 0.0
			show_banner("指引灯塔")
			spawn_fx_sprite("fx_holy_pillar_amber", tower_pos + Vector2(0, 4), g.PX * 1.6, 0.0, false, true)
			fx({"kind": "ring", "pos": tower_pos, "r": base("s3_r", 220.0), "r0": 20.0, "life": 0.7, "col": WARM, "floor": true, "w": 3.0})
	# 技能发动音 op_lumen_s1/s2/s3 由 spend_sp 播放


func skill_active_left(i: int) -> float:
	return tower_t if i == 2 else 0.0


func skill_active_dur(i: int) -> float:
	return base("s3_dur", 10.0) if i == 2 else 1.0


## game.gd 询问：主控光照半径倍率（S2 领航灯）
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
	# 随行：光域中心平滑跟到主控干员脚下
	tower_pos = tower_pos.lerp(g.ppos, clampf(dt * 10.0, 0.0, 1.0))
	var r: float = base("s3_r", 220.0)
	if _in_tower(g.ppos):
		g.corrode_pool = 0.0
		g.nerve = 0.0
		tower_tick += dt
		if tower_tick >= 1.0:
			tower_tick -= 1.0
			g.lamp = minf(g.lamp_cap, g.lamp + base("s3_lamp", 2.0))
			if g.hp < g.max_hp:
				heal_leader(g.max_hp * base("s3_heal", 0.015) * _heal_mult(), "流明")
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
	area_hit("光爆", tower_pos, r, base("bolt_atk", 22.0) * base("s3_burst_mult", 3.0) * _dmg_bonus() * skill_power(), 160.0, 0.6)
	spawn_fx_sprite("fx_sunburst", tower_pos + Vector2(0, -40), g.PX * 2.4)
	for i in 3:
		fx({"kind": "ring", "pos": tower_pos, "r": r * (0.6 + 0.2 * i), "r0": 16.0, "life": 0.4 + 0.1 * i, "col": WARM, "floor": true, "w": 4.0 - i})
	g.fx.append({"kind": "rays", "pos": tower_pos + Vector2(0, -40), "life": 0.6, "max": 0.6, "col": WARM})
	fx_sparks(tower_pos + Vector2(0, -30), WARM, 18, 240.0, 0.5, 3.0, 160.0)
	float_text(tower_pos + Vector2(0, -90), "光爆", WARM, 18)
	g.shake = maxf(g.shake, 4.0)
	Sfx.op(id, "big")
	tower_pos = Vector2.INF


# ---------------------------------------------------------------- 成长：发光单元 / 沐雨 / 灯塔守望 / 灯火不灭

func on_custom_node(nid: String, _choice: String = "") -> void:
	match nid:
		"unit_a", "unit_b":
			units = mini(2, units + 1)
		"rain":
			rain_on = true
		"watch":
			watch = true


func on_elite(stage: int, _choice: String = "") -> void:
	if stage >= 2:
		charge_on = true


## 第 k 个发光单元的位置：在流明头顶两侧缓慢绕飞、上下浮动
func _unit_pos(k: int) -> Vector2:
	var ang: float = g.t * 1.1 + k * PI
	return pos + Vector2(cos(ang) * 30.0, -72.0 + sin(ang) * 7.0 + sin(g.t * 2.3 + k * 1.7) * 3.0)


## 发光单元各自每 1.4 秒向最近敌人射一发光弹（60%，照亮）；灯火不灭：攒满 8 发后连射 8 发强化光弹
func _update_units(dt: float) -> void:
	if units <= 0 or pos == Vector2.INF:
		return
	var rng_r: float = base("bolt_range", 360.0) * stat(&"op_range")
	for k in units:
		unit_cd[k] -= dt
		if unit_cd[k] > 0.0:
			continue
		var ts: Array = nearest_enemies(1, rng_r, pos)
		if ts.is_empty() or bolts.size() >= BOLT_MAX:
			unit_cd[k] = 0.15
			continue
		unit_cd[k] = base("unit_cd", 1.4) / stat(&"op_aspd")
		var up: Vector2 = _unit_pos(k)
		var d: Vector2 = (ts[0].pos + Vector2(0, -ts[0].r * 0.5) - up).normalized()
		var dmg: float = base("bolt_atk", 22.0) * _dmg_bonus() * base("unit_mult", 0.6)
		var big := false
		if charge_on:
			if empowered > 0:
				empowered -= 1
				big = true
				dmg *= base("charge_mult", 2.0)
			else:
				charge_n += 1
				if charge_n >= int(base("charge_need", 8.0)):
					charge_n = 0
					empowered = int(base("charge_shots", 8.0))
					fx({"kind": "ring", "pos": pos + Vector2(0, -94), "r": 22.0, "r0": 4.0, "life": 0.4, "col": WARM})
					fx_sparks(pos + Vector2(0, -94), WARM, 8, 120.0, 0.4, 2.0)
		unit_fire[k] = g.t
		unit_fdir[k] = -1.0 if d.x < 0.0 else 1.0
		bolts.append({"pos": up, "vel": d * (340.0 if big else 400.0), "dmg": dmg, "life": 1.4, "src": "发光单元", "big": big,
			"heal": g.max_hp * base("charge_heal", 0.005) if big else 0.0})
		fx({"kind": "glow", "pos": up, "r": 12.0 if big else 8.0, "life": 0.2, "col": WARM, "alpha": 0.6})


## 沐雨：主控周围 140 内的敌人被照亮，每 0.5 秒受 15% 光弹伤害
func _update_rain(dt: float) -> void:
	if rain_t <= 0.0:
		return
	rain_t -= dt
	rain_tick -= dt
	if rain_tick > 0.0:
		return
	rain_tick += base("rain_tick", 0.5)
	var r: float = base("rain_r", 140.0)
	for j in query_ids(g.ppos, r + 20.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or e.pos.distance_to(g.ppos) > r + e.r:
			continue
		e["lit"] = maxf(e.get("lit", 0.0), 1.0)
		log_hit("沐雨")
		deal_damage(e, base("bolt_atk", 22.0) * _dmg_bonus() * base("rain_mult", 0.15) * skill_power())
		fx({"kind": "glow", "pos": e.pos + Vector2(0, -e.r * 0.5), "r": 7.0, "life": 0.2, "col": WARM, "alpha": 0.5})


## 光束是否在转：指引灯塔期间，或净化之光后的 3 秒
func _beam_on() -> bool:
	return watch and ((tower_t > 0.0 and tower_pos != Vector2.INF) or beam_t > 0.0)


## 光束的中心：有灯塔用灯塔，否则主控
func _beam_origin() -> Vector2:
	return tower_pos if tower_t > 0.0 and tower_pos != Vector2.INF else g.ppos


## 灯塔光束的方向（地面透视：y × 0.55）
func _beam_dir() -> Vector2:
	var a: float = g.t * TAU / base("beam_period", 2.0)
	return Vector2(cos(a), sin(a) * 0.55)


## 灯塔守望：旋转光束每 0.2 秒扫一次，扫到的敌人 40% 伤害 + 照亮（同一敌人 0.4 秒冷却）
func _update_beam(dt: float) -> void:
	for k in beam_hit.keys():
		beam_hit[k] -= dt
		if beam_hit[k] <= 0.0:
			beam_hit.erase(k)
	beam_t = maxf(0.0, beam_t - dt)
	if not _beam_on():
		return
	beam_tick -= dt
	if beam_tick > 0.0:
		return
	beam_tick += base("beam_tick", 0.2)
	var L: float = base("beam_len", 260.0)
	var a: Vector2 = _beam_origin()
	var b: Vector2 = a + _beam_dir() * L
	for j in query_ids(a, L + 20.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or beam_hit.has(e.id):
			continue
		var q: Vector2 = Geometry2D.get_closest_point_to_segment(e.pos, a, b)
		if q.distance_to(e.pos) > e.r + 14.0:
			continue
		beam_hit[e.id] = base("beam_cd", 0.4)
		e["lit"] = 3.0
		log_hit("灯塔光束")
		deal_damage(e, base("bolt_atk", 22.0) * _dmg_bonus() * base("beam_mult", 0.4) * skill_power())
		fx({"kind": "glow", "pos": e.pos + Vector2(0, -e.r * 0.5), "r": 9.0, "life": 0.2, "col": WARM, "alpha": 0.6})


# ---------------------------------------------------------------- 绘制

func draw_auras() -> void:
	if tower_t > 0.0 and tower_pos != Vector2.INF:
		var r: float = base("s3_r", 220.0)
		g.draw_set_transform(tower_pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
		g.draw_circle(Vector2.ZERO, r, Color(WARM.r, WARM.g, WARM.b, 0.05))
		g.draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(WARM.r, WARM.g, WARM.b, 0.35 + 0.1 * sin(g.t * 4.0)), 2.5)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 光弹与发光单元画在覆盖层（squad.gd 不调 draw_entities_over，之前光弹帧条一直没画出来，只剩加法层的光晕）
func _draw_skill_over() -> void:
	for b in bolts:
		var big: bool = b.get("big", false)
		if g.tex.get("proj_lumen_bolt") != null:
			if big:
				# 强化光弹：外圈亮晕 + 拖尾，更大更亮
				g.draw_line(b.pos - b.vel.normalized() * 22.0, b.pos, Color(2.0, 1.6, 0.9, 0.55), 6.0)
				g.draw_circle(b.pos, 8.0, Color(1.6, 1.3, 0.7, 0.5))
			draw_spr_rot("proj_lumen_bolt", int(g.t * 12.0 + b.pos.x * 0.05) % 6, b.pos, b.vel.angle(), g.PX * (1.5 if big else 1.0), Color(1.5, 1.35, 1.1) if big else Color.WHITE)
		else:
			g.draw_line(b.pos - b.vel.normalized() * 14.0, b.pos, Color(WARM.r * 1.4, WARM.g * 1.3, WARM.b, 0.5), 5.0 if big else 3.0)
			g.draw_circle(b.pos, 6.0 if big else 4.0, Color(2.0, 1.8, 1.2))
	_draw_units()
	_draw_rain()


## 发光单元：黄铜小灯罩 + 暖光灯芯（自制的小灯，原作档案），下方一缕光；强化待发时灯芯变亮
func _draw_units() -> void:
	if units <= 0 or pos == Vector2.INF:
		return
	# Codex 成长线帧条 fx_lumen_unit（12×14、5 帧、中心锚点）：0–3 灯芯 6fps 循环，4 开火帧（刚开火后约 83ms，闪光朝右，朝左开火时镜像）；
	# 强化待发时整体提亮。背后的暖光晕保留；缺图退回下面的程序小灯
	var utx: Texture2D = A.tex("fx_lumen_unit")
	for k in units:
		var p: Vector2 = _unit_pos(k)
		var hot: bool = empowered > 0
		var pulse: float = 0.5 + 0.5 * sin(g.t * 6.0 + k * 2.0)
		g.draw_circle(p, 9.0 + 2.0 * pulse, Color(1.0, 0.8, 0.4, 0.16 if not hot else 0.3))
		if utx != null:
			var firing: bool = g.t - float(unit_fire[k]) < 0.083
			var uf: int = 4 if firing else (int(g.t * 6.0) + k * 2) % 4
			_strip(utx, 5, uf, p, g.PX, Vector2(6, 7), firing and float(unit_fdir[k]) < 0.0, Color(1.35, 1.25, 1.05) if hot else Color.WHITE)
			continue
		# 灯罩（上下两片暗色黄铜）+ 灯芯
		g.draw_colored_polygon(PackedVector2Array([p + Vector2(-5, -4), p + Vector2(5, -4), p + Vector2(3, -7), p + Vector2(-3, -7)]), Color(0.35, 0.27, 0.18))
		g.draw_rect(Rect2(p + Vector2(-4, -4), Vector2(8, 7)), Color(1.0, 0.85, 0.5, 0.55))
		g.draw_rect(Rect2(p + Vector2(-2, -2), Vector2(4, 4)), Color(2.2, 1.9, 1.2) if hot else Color(1.8, 1.5, 0.9))
		g.draw_rect(Rect2(p + Vector2(-4, 3), Vector2(8, 2)), Color(0.35, 0.27, 0.18))
		g.draw_line(p + Vector2(0, 5), p + Vector2(0, 9 + 2.0 * pulse), Color(1.4, 1.1, 0.6, 0.6), 1.0)
	# 灯火不灭：8 格计数（空格暗、已攒亮；强化连射时金色，显示剩余发数）
	if charge_on:
		var need: int = int(base("charge_need", 8.0))
		var c0: Vector2 = pos + Vector2(-(need - 1) * 3.0, -94)
		for q in need:
			var pp: Vector2 = c0 + Vector2(q * 6.0, 0)
			var on: bool = (q < empowered) if empowered > 0 else (q < charge_n)
			var col: Color = Color(2.0, 1.6, 0.7) if (on and empowered > 0) else (Color(1.2, 1.05, 0.8) if on else Color(0.25, 0.22, 0.2, 0.8))
			g.draw_rect(Rect2(pp - Vector2(2, 2), Vector2(4, 4)), col)


## 沐雨：发光单元洒下的光雨（程序生成的落雨线，落点在主控周围 140 的椭圆内）
func _draw_rain() -> void:
	if rain_t <= 0.0:
		return
	var r: float = base("rain_r", 140.0)
	var fade: float = clampf(rain_t / 0.4, 0.0, 1.0) * clampf((base("rain_dur", 3.0) - rain_t) / 0.3, 0.0, 1.0)
	g.draw_set_transform(g.ppos + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
	g.draw_circle(Vector2.ZERO, r, Color(1.0, 0.85, 0.5, 0.06 * fade))
	g.draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(1.3, 1.1, 0.7, 0.35 * fade), 1.5)
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for q in 28:
		var ph: float = fmod(g.t * 1.8 + q * 0.379, 1.0)
		var cyc: int = int(g.t * 1.8 + q * 0.379)
		var h: int = hash(Vector2i(q, cyc))
		var an: float = float(h % 628) / 100.0
		var rr: float = r * sqrt(float((h >> 10) % 100) / 100.0)
		var ground: Vector2 = g.ppos + Vector2(cos(an) * rr, sin(an) * rr * 0.55)
		var top: Vector2 = ground + Vector2(0, -70.0 * (1.0 - ph))
		g.draw_line(top + Vector2(0, -8), top, Color(1.6, 1.35, 0.8, 0.7 * fade), 1.5)
		if ph > 0.85:
			g.draw_set_transform(ground, 0.0, Vector2(1.0, 0.5))
			g.draw_arc(Vector2.ZERO, 3.0 + (ph - 0.85) * 40.0, 0.0, TAU, 10, Color(1.4, 1.2, 0.7, 0.5 * fade), 1.0)
			g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func draw_fx_add(ci: CanvasItem, _loop: int) -> void:
	# 出手时提灯的暖光（加法层，不再用普通混合的发光团，避免在身上糊成浑色圆斑）
	if hand_glow > 0.0:
		var hk: float = sin(hand_glow / 0.3 * PI)
		var hp: Vector2 = _lamp_hand()
		ci.draw_circle(hp, 11.0 * (0.5 + 0.5 * hk), Color(0.9, 0.7, 0.35, 0.45 * hk))
		ci.draw_circle(hp, 4.0 * hk, Color(1.0, 0.9, 0.6, 0.8 * hk))
	# 灯塔光柱与光区（加法层）
	if tower_t > 0.0 and tower_pos != Vector2.INF:
		var k: float = 0.5 + 0.5 * sin(g.t * 3.0)
		ci.draw_circle(_tower_lamp(), 26.0 + 4.0 * k, Color(0.9, 0.7, 0.35, 0.35))
		ci.draw_set_transform(tower_pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
		ci.draw_circle(Vector2.ZERO, base("s3_r", 220.0) * 0.9, Color(0.6, 0.45, 0.2, 0.06 + 0.02 * k))
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for b in bolts:
		ci.draw_circle(b.pos, 14.0 if b.get("big", false) else 9.0, Color(0.9, 0.7, 0.3, 0.35))
	# 灯塔守望：塔顶灯室射出的旋转光束（贴地的细长光楔 + 塔顶到地面的光柱连线）
	if _beam_on():
		var L: float = base("beam_len", 260.0)
		var o: Vector2 = _beam_origin()
		var twr: bool = tower_t > 0.0 and tower_pos != Vector2.INF
		var d: Vector2 = _beam_dir()
		var n: Vector2 = Vector2(-d.y, d.x).normalized()
		var tip: Vector2 = o + d * L
		var fade: float = clampf((tower_t if twr else beam_t) / 0.5, 0.0, 1.0)
		ci.draw_colored_polygon(PackedVector2Array([o + n * 4.0, tip + n * 26.0, tip - n * 26.0, o - n * 4.0]), Color(0.9, 0.7, 0.35, 0.28 * fade))
		ci.draw_colored_polygon(PackedVector2Array([o + n * 2.0, tip + n * 10.0, tip - n * 10.0, o - n * 2.0]), Color(1.0, 0.85, 0.5, 0.35 * fade))
		ci.draw_line(_tower_lamp() if twr else o + Vector2(0, -44.0), o + d * 30.0, Color(0.9, 0.75, 0.4, 0.3 * fade), 3.0)


## 出手帧提灯的位置（op_lumen_attack@2x 第 2 帧量得：脚底前 26、上 32；docs/32 §3）
func _lamp_hand() -> Vector2:
	return pos + Vector2(26.0 * face, -32.0)


## 悬浮灯塔贴图的脚底位置（光域中心 tower_pos 在主控脚下，贴图画在身后一侧）
func _tower_sprite_pos() -> Vector2:
	return tower_pos + Vector2(-40.0 * g.facing, -8.0 + 3.0 * sin(g.t * 2.4))


## 灯室中心（prop_lighthouse@2x 第 1 帧量得：脚底正上方 83）
func _tower_lamp() -> Vector2:
	return _tower_sprite_pos() + Vector2(0, -83.0)


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
	# 灯塔悬在主控身后一侧随行、轻微上下浮动；灯室常亮（帧 1），不再 4Hz 亮灭频闪（docs/32 §3）
	draw_sprite_at(_tower_sprite_pos(), false, Color.WHITE, 1 % n, tx, n, foot_off(tx, "lighthouse"))


func draw_extra_shadows() -> void:
	if tower_t > 0.0 and tower_pos != Vector2.INF:
		# 影子落在悬浮灯塔正下方的地面上，随浮动高度轻微缩放
		var sp: Vector2 = _tower_sprite_pos()
		draw_spr("shadow", 1, 0, Vector2(sp.x, tower_pos.y + 4.0), g.PX * (1.3 - 0.02 * (tower_pos.y - sp.y - 8.0)))


func status_items() -> Array:
	var out: Array = []
	if tower_t > 0.0:
		out.append(["灯塔", WARM])
	if immune_t > 0.0:
		out.append(["净化", PALE])
	return out


## 画一帧横向帧条（Codex 成长线 growth_fx，双密度）：anchor_px 按 @1x 帧内像素给，sc 为 @1x 每像素的世界尺寸；
## @2x 贴图自动把倍率减半、锚点加倍（同 game.gd _spr_rot 的口径）
func _strip(tx: Texture2D, frames: int, fr: int, p: Vector2, sc: float, anchor_px: Vector2, flip := false, col := Color.WHITE) -> void:
	var hi: float = A.hires_of(tx)
	var fw: int = tx.get_width() / frames
	var fh: int = tx.get_height()
	var k: float = sc / hi
	g.draw_set_transform(p.round(), 0.0, Vector2(-k if flip else k, k))
	g.draw_texture_rect_region(tx, Rect2(-anchor_px * hi, Vector2(fw, fh)), Rect2(fw * (fr % frames), 0, fw, fh), col)
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
