## 干员积木 · seg_lumen（docs/101 §7.3 B6 ①，10-15：由 op_blocks.gd 按段拆出，内容与注释照搬；继承链与门面见 op_blocks.gd）
extends "res://scripts/characters/blocks/seg_specter.gd"

const H3_WARM := Color(1.0, 0.85, 0.55)

const H3_PALE := Color(0.7, 0.9, 1.0)

const H3_BOLT_MAX := 12


static func _h3lm(o) -> Dictionary:
	var h := hw_st(o)
	if not h.has("lm"):
		h["lm"] = {"heal_t": 0.0, "immune_t": 0.0, "bolts": [], "mote_t": 0.0, "hand_glow": 0.0, "armed": false,
			"tower_pos": Vector2.INF, "tower_side": 1.0, "tower_tick": 0.0, "tower_b": {}, "last_s": [0.0, 0.0, 0.0],
			"unit_cd": [], "unit_fire": [-9.0, -9.0, -9.0, -9.0], "unit_fdir": [1.0, 1.0, 1.0, 1.0], "charge_n": 0, "empowered": 0,
			"rain_t": 0.0, "rain_tick": 0.0, "rain_b": {}, "beam_t": 0.0, "beam_tick": 0.0, "beam_hit": {}}
	return h.lm


static func _h3_heal_mult(o) -> float:
	return o.stat(&"op_atk") * o.g.ally_mult * o.stat(&"heal_out")


## 生效中的天赋积木（第一块 tag 的）
static func _h3_trig_block(o, tag: String) -> Dictionary:
	for t in o._trigs():
		if str(t.get("_tag", "")) != "trig.passive" or not cond_true(o, t.get("cond", _ED)):
			continue
		for b in t.get("do", _EA):
			if str(b.get("_tag", "")) == tag and cond_true(o, b.get("cond", _ED)):
				return b
	return {}


## 天赋：每次回复 / 驱散灯火 +add（同手写 _talent_lamp）
static func _h3_heal_lamp(o) -> void:
	var b := _h3_trig_block(o, "verb.heal_lamp")
	if not b.is_empty():
		o.g.lamp = minf(o.g.lamp_cap, o.g.lamp + float(b.get("add", 2.0)))


## 治疗队长（同手写 _heal_doctor：满血也结算）
static func _h3_mend(o, h: float, size: int, sub: String) -> void:
	var g = o.g
	if h <= 0.0:
		return
	o.heal_leader(h, o.display_name(), sub)
	o.float_text(g.ppos + Vector2(0, -90), "+%d" % int(h), H3_WARM, size)
	o.spawn_fx_sprite("fx_holy_impact_lantern", g.ppos + Vector2(0, -34), g.PX * 0.9)
	if not o.spawn_fx_sprite("fx_heal_aura_amber", g.ppos + Vector2(0, 6), g.PX * 1.2, 0.0, false, true):
		o.fx({"kind": "ring", "pos": g.ppos, "r": 28.0, "r0": 8.0, "life": 0.4, "col": H3_WARM, "floor": true, "keep": true})


## 出手帧提灯位置（脚底前 hand[0]、上 hand[1]）
static func _h3_lamp_hand(o, a: Dictionary) -> Vector2:
	var hv = a.get("hand", [31, -42])
	return o.pos + Vector2(float(hv[0]) * o.face, float(hv[1]))


static func _h3_bolt_range(o, a: Dictionary) -> float:
	return float(a.get("range", 330.0)) * o.stat(&"op_range")


## 起手（hw: 不在出手、没有技能要放的帧）：先累计荧光计时，再看冷却
static func _h3_lantern_start(o, a: Dictionary, dt: float) -> void:
	var lm := _h3lm(o)
	var hb: Dictionary = a.get("heal", {})
	lm.heal_t = float(lm.heal_t) + dt
	if o.cd > 0.0:
		return
	var rr: float = _h3_bolt_range(o, a)
	var ts: Array = o.attack_targets(1, rr, o.pos) if o.held_aim() else o.los_targets(1, rr, o.pos)
	lm.armed = not ts.is_empty()
	var every: float = float(a.get("every", 1.0)) / o.stat(&"op_aspd")
	if not ts.is_empty() or float(lm.heal_t) >= float(hb.get("every", 3.0)):
		o.cd = every
		o.start_attack(ts[0].pos if not ts.is_empty() else o.g.ppos, 0.5, 0.25, _h3_lantern_anim(o, lm, ts))
	else:
		o.cd = every


## 这一发若是精二灯塔光柱（已充满、有目标），起手播光柱帧条（与 attack 同时长、同出手时刻，纯画面）
static func _h3_lantern_anim(o, lm: Dictionary, ts: Array) -> String:
	var bm = o.B.get("attack", _ED).get("beam", null)
	if ts.is_empty() or not (bm is Dictionary) or int(lm.get("empowered", 0)) <= 0 or not cond_true(o, bm.get("cond", _ED)):
		return ""
	return "attack_beam" if o.sprite_spec("attack_beam").has("frames") else ""


static func _h3_lantern_release(o, a: Dictionary) -> void:
	var g = o.g
	var lm := _h3lm(o)
	var hb: Dictionary = a.get("heal", {})
	var hand: Vector2 = _h3_lamp_hand(o, a)
	var did := false
	if float(lm.heal_t) < float(hb.get("every", 3.0)):
		pass
	elif g.corrode_pool > 0.5 or g.nerve > 0.5:
		if g.bot != null:
			g.telemetry.note_clean("corrode", g.corrode_pool)
			g.telemetry.note_clean("nerve", minf(g.nerve, float(hb.get("nerve_cut", 15.0))))
		g.afflict.clear_corrode()
		g.afflict.cut_nerve(float(hb.get("nerve_cut", 15.0)))
		o.float_text(g.ppos + Vector2(0, -96), "驱散", H3_PALE, 14)
		did = true
	elif g.hp < g.max_hp:
		var pct: float = g.max_hp * float(hb.get("pct", 0.02))
		var gm := 1.0
		for m in hb.get("mults", _EA):
			if cond_true(o, m.get("cond", _ED)):
				gm *= float(m.get("mult", 1.0))   # 10-21 响应动作起成立的依次乘（原来只有一条，取最后一条 = 乘）
		_h3_mend(o, pct * gm * _h3_heal_mult(o), 15, str(hb.get("sub", "")))
		did = true
	if did:
		lm.heal_t = 0.0
		_h3_heal_lamp(o)
		for m in hb.get("lamp_adds", _EA):   # 响应动作（docs/118 §4.2）：cond 成立时这次回复 / 驱散另给灯火 + add
			if cond_true(o, m.get("cond", _ED)):
				g.lamp = minf(g.lamp_cap, g.lamp + float(m.get("add", 0.0)))
		g.fx.append({"kind": "beam", "a": hand, "b": g.ppos + Vector2(0, -24), "life": 0.25, "max": 0.25, "col": H3_WARM, "w": 2.5})
	lm.hand_glow = 0.18
	var rr: float = _h3_bolt_range(o, a)
	var ts: Array = ((o.aim_targets(1, rr, o.pos) if lm.armed else []) if o.held_aim() else o.los_targets(1, rr, o.pos))
	if not ts.is_empty():
		var bt: Dictionary = a.get("bolt", {})
		var d: Vector2 = (ts[0].pos - hand).normalized()
		if _e3_beam_shot(o, lm, hand, ts[0].pos, o.base(str(bt.get("atk_key", "atk")), 0.0) * o._dmg_bonus()):
			return   # 精英化第 3 批：这一发变灯塔光柱
		if lm.bolts.size() < H3_BOLT_MAX:
			lm.bolts.append({"pos": hand, "vel": d * float(bt.get("speed", 380.0)), "dmg": o.base(str(bt.get("atk_key", "atk")), 0.0) * o._dmg_bonus(), "life": float(bt.get("life", 1.4)), "src": str(bt.get("src", "")),
				"pierce": o.atk_pierce(0), "hit": {}})   # 普攻光弹：穿透只来自贯穿卡 / 穿甲弹（10-23）


static func _h3_bolts_tick(o, lm: Dictionary, dt: float) -> void:
	if lm.bolts.is_empty():
		return
	var g = o.g
	var bt: Dictionary = o.B.get("attack", _ED).get("bolt", {})
	var main_src: String = str(bt.get("src", ""))
	for b in lm.bolts:
		b.pos += b.vel * dt
		b.life -= dt
		lm.mote_t = float(lm.mote_t) - dt
		if b.life > 0.0 and g.map.tb_bul and g.map.bullet_blocked(b, b.pos):
			b.life = 0.0
			continue
		for j in o.query_ids(b.pos, 30.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or e.pos.distance_to(b.pos) > e.r + float(bt.get("r", 8.0)) or b.get("hit", _ED).has(e.id):
				continue
			var pm: float = o.atk_pierce_mult(b.hit.size()) if b.has("hit") else 1.0   # 穿甲弹：每穿过一名 −15%（10-23）
			if b.has("hit"):
				b.hit[e.id] = true
			var src: String = b.get("src", main_src)
			var was_lit: bool = float(e.get("lit", 0.0)) > 0.0   # 精英化第 3 批：折光看命中前是否已被照亮
			o.log_hit(src)
			o.deal_damage(e, b.dmg * pm)
			e["lit"] = float(bt.get("lit", 3.0))
			_h3_sfx(o, "hit", -4.0 if src != main_src else 0.0)
			if b.get("heal", 0.0) > 0.0 and g.hp < g.max_hp:
				o.heal_leader(b.heal, o.display_name(), str(b.get("heal_sub", "")))
				o.fx({"kind": "glow", "pos": g.ppos + Vector2(0, -26), "r": 10.0, "life": 0.25, "col": H3_WARM, "alpha": 0.5})
			var ar: float = float(bt.get("aoe", 24.0))
			for j2 in o.query_ids(b.pos, ar + 20.0):
				var q: Dictionary = g.enemies[j2]
				if q.dead or is_same(q, e) or q.pos.distance_to(b.pos) > ar + q.r:
					continue
				o.log_hit(src)
				o.deal_damage(q, b.dmg * float(bt.get("splash", 0.6)))
				q["lit"] = float(bt.get("lit", 3.0))
			if was_lit:
				_e3_refract(o, bt, e, b.dmg)
			if int(b.get("pierce", 0)) > 0:
				b.pierce = int(b.pierce) - 1   # 贯穿卡 / 穿甲弹：穿过去继续飞（已命中的不再打）
			else:
				b.life = 0.0
			if not o.spawn_fx_sprite("fx_holy_impact_lantern", e.pos + Vector2(0, -e.r * 0.5), g.PX * 0.7):
				o.fx({"kind": "glow", "pos": e.pos + Vector2(0, -e.r * 0.5), "r": 12.0, "life": 0.25, "col": H3_WARM, "alpha": 0.6})
			_h3_vsparks(o, e.pos + Vector2(0, -e.r * 0.5), H3_WARM, 4, 120.0, 0.3, 2.0)
			break
	lm.bolts = lm.bolts.filter(func(b): return b.life > 0.0)


# ---- 灯塔（verb.tower）

static func h3_tower_start(o, b: Dictionary) -> void:
	var lm := _h3lm(o)
	lm.tower_pos = o.g.ppos
	lm.tower_tick = 0.0
	lm.tower_b = b
	var i := _h3_tower_i(o)
	lm.tower_t = o.s_t[i] if i >= 0 else 0.0   # 同技能剩余（各自每帧 -dt；这份不夹 0，同手写 tower_t）


## 灯塔在场：带 verb.tower 的技能剩余 > 0
static func _h3_tower_i(o) -> int:
	var sk: Array = o.B.get("skills", [])
	for i in mini(3, sk.size()):
		for b in sk[i].get("do", _EA):
			if str(b.get("_tag", "")) == "verb.tower":
				return i
	return -1


static func _h3_tower_on(o) -> bool:
	return float(o.hw.lm.get("tower_t", 0.0)) > 0.0 and o.hw.lm.tower_pos != Vector2.INF


static func _h3_tower_tick(o, lm: Dictionary, dt: float) -> void:
	if float(lm.get("tower_t", 0.0)) <= 0.0:
		return
	lm.tower_t = float(lm.tower_t) - dt
	var g = o.g
	var b: Dictionary = lm.tower_b
	var tt: float = lm.tower_t
	lm.tower_pos = (lm.tower_pos as Vector2).lerp(g.ppos, clampf(dt * 10.0, 0.0, 1.0))
	lm.tower_side = move_toward(float(lm.tower_side), g.facing, dt * 5.0)
	var r: float = float(b.get("r", 220.0))
	if tt > 0.0 and g.ppos.distance_to(lm.tower_pos) < r:
		if g.bot != null:
			g.telemetry.note_clean("corrode", g.corrode_pool)
		g.afflict.clear_corrode()
		g.afflict.clear_nerve()
		lm.tower_tick = float(lm.tower_tick) + dt
		if float(lm.tower_tick) >= float(b.get("every", 1.0)):
			lm.tower_tick = float(lm.tower_tick) - float(b.get("every", 1.0))
			g.lamp = minf(g.lamp_cap, g.lamp + float(b.get("lamp", 2.0)))
			if g.hp < g.max_hp:
				o.heal_leader(g.max_hp * float(b.get("heal", 0.015)) * _h3_heal_mult(o), o.display_name(), str(b.get("sub", "")))
				_h3_heal_lamp(o)
	lm.mote_t = float(lm.mote_t) - dt
	if float(lm.mote_t) <= 0.0:
		lm.mote_t = 0.06
		var ma: float = g.vrng.randf() * TAU
		var mr: float = g.vrng.randf() * r
		o.fx({"kind": "mote", "pos": (lm.tower_pos as Vector2) + Vector2(cos(ma) * mr, sin(ma) * mr * 0.55), "vel": Vector2(0, -35), "life": 0.8, "col": H3_WARM, "sz": 1.8})
	if tt <= 0.0:
		_h3_light_burst(o, lm, b)


static func _h3_light_burst(o, lm: Dictionary, b: Dictionary) -> void:
	var g = o.g
	var r: float = float(b.get("r", 220.0))
	var bu: Dictionary = b.get("burst", {})
	var tp: Vector2 = lm.tower_pos
	var dmg: float = hw_mul(o.base(str(bu.get("atk_key", "atk")), 0.0), bu.get("mult", 3.0)) * o._dmg_bonus()
	if bu.get("power", false):
		dmg *= o.skill_power()
	o.area_hit(str(bu.get("src", "")), tp, r, dmg, float(bu.get("kb", 160.0)), float(bu.get("stun", 0.6)))
	# 10-29：取消「日炎」大火球（fx_sunburst，用户定）；爆发只留地面环 / 光线 / 火花
	for i in 3:
		o.fx({"kind": "ring", "pos": tp, "r": r * (0.6 + 0.2 * i), "r0": 16.0, "life": 0.4 + 0.1 * i, "col": H3_WARM, "floor": true, "w": 4.0 - i})
	g.fx.append({"kind": "rays", "pos": tp + Vector2(0, -40), "life": 0.6, "max": 0.6, "col": H3_WARM, "op_spoke": true})
	_h3_vsparks(o, tp + Vector2(0, -30), H3_WARM, 18, 240.0, 0.5, 3.0, 160.0)
	o.float_text(tp + Vector2(0, -90), str(bu.get("src", "")), H3_WARM, 18)
	g.shake = maxf(g.shake, 4.0)
	_h3_sfx(o, "big")
	lm.tower_pos = Vector2.INF


static func h3_sanctuary(o) -> Dictionary:
	if not hw_on(o) or not o.hw.has("lm") or not _h3_tower_on(o):
		return {}
	return {"pos": o.hw.lm.tower_pos, "r": float(o.hw.lm.tower_b.get("r", 220.0))}


## 队长照亮半径倍率：生效中的 verb.lamp radius_mult
static func h3_light_mult(o) -> float:
	if not hw_on(o) or not o.hw.has("lm"):
		return 1.0
	var m := 1.0
	var sk: Array = o.B.get("skills", [])
	for i in mini(3, sk.size()):
		if o.skill_on(i):
			for b in sk[i].get("do", _EA):
				if str(b.get("_tag", "")) == "verb.lamp" and b.has("radius_mult"):
					m *= float(b.radius_mult)
	return m


static func _h3_tower_sprite_pos(o) -> Vector2:
	var lm: Dictionary = o.hw.lm
	return (lm.tower_pos as Vector2) + Vector2(-40.0 * float(lm.tower_side), -8.0 + 3.0 * sin(o.g.t * 2.4))


static func _h3_tower_lamp(o) -> Vector2:
	return _h3_tower_sprite_pos(o) + Vector2(0, -83.0)


# ---- 发光单元

static func _h3_units_n(o, a: Dictionary) -> int:
	var un: Dictionary = a.get("units", {})
	var n := 0
	for nid in un.get("nodes", _EA):
		if str(nid) in o.taken:
			n += 1
	return mini(n, int(un.get("max", 2)))


static func _h3_unit_pos(o, k: int) -> Vector2:
	var g = o.g
	var ang: float = g.t * 1.1 + k * PI
	return o.pos + Vector2(cos(ang) * 30.0, -72.0 + sin(ang) * 7.0 + sin(g.t * 2.3 + k * 1.7) * 3.0)


static func _h3_units_tick(o, lm: Dictionary, dt: float) -> void:
	var a: Dictionary = o.B.get("attack", {})
	var units: int = _h3_units_n(o, a)
	if units <= 0 or o.pos == Vector2.INF:
		return
	var g = o.g
	var un: Dictionary = a.get("units", {})
	var bt: Dictionary = a.get("bolt", {})
	if lm.unit_cd.is_empty():
		lm.unit_cd = un.get("cd0", [0.5, 1.2]).duplicate()
		while lm.unit_cd.size() < 4:
			lm.unit_cd.append(1.0)
	var rng_r: float = _h3_bolt_range(o, a)
	var ch = un.get("charge", null)
	var charge_on: bool = ch is Dictionary and cond_true(o, ch.get("cond", _ED))
	for k in units:
		lm.unit_cd[k] = float(lm.unit_cd[k]) - dt
		if float(lm.unit_cd[k]) > 0.0:
			continue
		var ts: Array = o.los_targets(1, rng_r, o.pos, _h3_unit_pos(o, k))
		if ts.is_empty() or lm.bolts.size() >= H3_BOLT_MAX:
			lm.unit_cd[k] = 0.15
			continue
		lm.unit_cd[k] = float(un.get("cd", 1.4)) / o.stat(&"op_aspd")
		var up: Vector2 = _h3_unit_pos(o, k)
		var d: Vector2 = (ts[0].pos + Vector2(0, -ts[0].r * 0.5) - up).normalized()
		var dmg: float = o.base(str(bt.get("atk_key", "atk")), 0.0) * o._dmg_bonus() * float(un.get("mult", 0.6))
		if _e3_beam_shot(o, lm, up, ts[0].pos, dmg):   # 精英化第 3 批：这一发变灯塔光柱
			lm.unit_fire[k] = g.t
			lm.unit_fdir[k] = -1.0 if d.x < 0.0 else 1.0
			continue
		var big := false
		if charge_on:
			if int(lm.empowered) > 0:
				lm.empowered = int(lm.empowered) - 1
				big = true
				dmg *= float(ch.get("mult", 2.0))
			else:
				lm.charge_n = int(lm.charge_n) + 1
				if int(lm.charge_n) >= int(ch.get("need", 8)):
					lm.charge_n = 0
					lm.empowered = int(ch.get("shots", 8))
					o.fx({"kind": "ring", "pos": o.pos + Vector2(0, -94), "r": 22.0, "r0": 4.0, "life": 0.4, "col": H3_WARM, "keep": true})
					_h3_vsparks(o, o.pos + Vector2(0, -94), H3_WARM, 8, 120.0, 0.4, 2.0)
		lm.unit_fire[k] = g.t
		lm.unit_fdir[k] = -1.0 if d.x < 0.0 else 1.0
		lm.bolts.append({"pos": up, "vel": d * (float(ch.get("speed", 340.0)) if big else float(un.get("speed", 400.0))), "dmg": dmg, "life": float(bt.get("life", 1.4)),
			"src": str(un.get("src", "")), "big": big, "heal": g.max_hp * float(ch.get("heal", 0.005)) if big else 0.0, "heal_sub": str(ch.get("heal_sub", "")) if big else ""})
		o.fx({"kind": "glow", "pos": up, "r": 12.0 if big else 8.0, "life": 0.2, "col": H3_WARM, "alpha": 0.6})


# ---- 光雨 / 光束

static func h3_light_rain(o, b: Dictionary) -> void:
	var lm := _h3lm(o)
	if _h3_units_n(o, o.B.get("attack", {})) <= 0:
		return
	lm.rain_t = float(b.get("dur", 3.0))
	lm.rain_tick = 0.0
	lm.rain_b = b


static func _h3_rain_tick(o, lm: Dictionary, dt: float) -> void:
	if float(lm.rain_t) <= 0.0:
		return
	var g = o.g
	var b: Dictionary = lm.rain_b
	lm.rain_t = float(lm.rain_t) - dt
	lm.rain_tick = float(lm.rain_tick) - dt
	if float(lm.rain_tick) > 0.0:
		return
	lm.rain_tick = float(lm.rain_tick) + float(b.get("tick", 0.5))
	var r: float = float(b.get("r", 140.0))
	for j in o.query_ids(g.ppos, r + 20.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or e.pos.distance_to(g.ppos) > r + e.r:
			continue
		e["lit"] = maxf(e.get("lit", 0.0), 1.0)
		o.log_hit(str(b.get("src", "")))
		o.deal_damage(e, o.base(str(b.get("atk_key", "atk")), 0.0) * o._dmg_bonus() * float(b.get("mult", 0.15)) * o.skill_power())
		o.fx({"kind": "glow", "pos": e.pos + Vector2(0, -e.r * 0.5), "r": 7.0, "life": 0.2, "col": H3_WARM, "alpha": 0.5})


static func _h3_beam_block(o) -> Dictionary:
	for t in o._trigs():
		if not cond_true(o, t.get("cond", _ED)):
			continue
		if str(t.get("_tag", "")) == "verb.beam":
			return t
		if str(t.get("_tag", "")) == "trig.passive":
			for b in t.get("do", _EA):
				if str(b.get("_tag", "")) == "verb.beam" and cond_true(o, b.get("cond", _ED)):
					return b
	return {}


static func _h3_beam_on(o, bb: Dictionary) -> bool:
	return not bb.is_empty() and (_h3_tower_on(o) or float(o.hw.lm.beam_t) > 0.0)


static func _h3_beam_origin(o) -> Vector2:
	return _h3_tower_sprite_pos(o) if _h3_tower_on(o) else o.g.ppos


static func _h3_beam_dir(o, bb: Dictionary) -> Vector2:
	var a: float = o.g.t * TAU / float(bb.get("period", 2.0))
	return Vector2(cos(a), sin(a) * 0.55)


static func _h3_beam_tick(o, lm: Dictionary, dt: float) -> void:
	var g = o.g
	for k in lm.beam_hit.keys():
		lm.beam_hit[k] -= dt
		if lm.beam_hit[k] <= 0.0:
			lm.beam_hit.erase(k)
	lm.beam_t = maxf(0.0, float(lm.beam_t) - dt)
	var bb := _h3_beam_block(o)
	if not _h3_beam_on(o, bb):
		return
	lm.beam_tick = float(lm.beam_tick) - dt
	if float(lm.beam_tick) > 0.0:
		return
	lm.beam_tick = float(lm.beam_tick) + float(bb.get("tick", 0.2))
	var L: float = float(bb.get("len", 260.0))
	var a: Vector2 = _h3_beam_origin(o)
	var b: Vector2 = a + _h3_beam_dir(o, bb) * L
	for j in o.query_ids(a, L + 20.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or lm.beam_hit.has(e.id):
			continue
		var q: Vector2 = Geometry2D.get_closest_point_to_segment(e.pos, a, b)
		if q.distance_to(e.pos) > e.r + 14.0:
			continue
		lm.beam_hit[e.id] = float(bb.get("cd", 0.4))
		e["lit"] = 3.0
		o.log_hit(str(bb.get("src", "")))
		o.deal_damage(e, o.base(str(bb.get("atk_key", "atk")), 0.0) * o._dmg_bonus() * float(bb.get("mult", 0.4)) * o.skill_power())
		o.fx({"kind": "glow", "pos": e.pos + Vector2(0, -e.r * 0.5), "r": 9.0, "life": 0.2, "col": H3_WARM, "alpha": 0.6})


## 天赋：灯火 ≥ lamp 时自身技力额外充能（同手写，在出手判定之前）
static func _h3_lamp_charge(o, dt: float) -> void:
	var b := _h3_trig_block(o, "verb.heal_lamp")
	var g = o.g
	if b.is_empty() or not b.has("rate") or g.lamp < float(b.get("lamp", 70.0)):
		return
	for i in 3:
		if o.skill_unlocked(i) and o.sp_need(i) > 0.0 and not o.perm[i] and o.skill_active_left(i) <= 0.0:
			o.sp[i] = minf(o.sp_need(i), o.sp[i] + dt * float(b.rate) * g.sp_mult * o.stat(&"op_skill_sp") * o.lamp_sp() * (0.0 if g.apop_t > 0.0 else 1.0))


## 流明段每帧（h3_tick 转来，手写 update 的先后：提灯光 / 免疫 → 光弹 → 灯塔 → 发光单元 → 光雨 → 光束 → 天赋充能）
static func _h3lm_tick(o, lm: Dictionary, dt: float) -> void:
	var g = o.g
	lm.hand_glow = maxf(0.0, float(lm.hand_glow) - dt)
	lm.immune_t = maxf(0.0, float(lm.immune_t) - dt)
	if float(lm.immune_t) > 0.0:
		g.afflict.clear_nerve()
	_h3_bolts_tick(o, lm, dt)
	_h3_tower_tick(o, lm, dt)
	_h3_units_tick(o, lm, dt)
	_h3_rain_tick(o, lm, dt)
	_h3_beam_tick(o, lm, dt)
	if o.elite >= 1:
		_h3_lamp_charge(o, dt)


static func h3_mend(o, b: Dictionary) -> void:
	var g = o.g
	var h: float = g.max_hp * float(b.get("pct", 0.05)) * _h3_heal_mult(o)
	if b.get("power", false):
		h *= o.skill_power()
	_h3_mend(o, h, int(b.get("text", 18)), str(b.get("sub", "")))


static func h3_purge(o, b: Dictionary) -> void:
	var g = o.g
	var lm := _h3lm(o)
	if g.bot != null:
		g.telemetry.note_clean("corrode", g.corrode_pool)
		g.telemetry.note_clean("nerve", g.nerve)
	g.afflict.clear_corrode()
	g.afflict.clear_nerve()
	lm.immune_t = float(b.get("immune", 3.0))


# ---- 画面

static func _h3lm_draw_auras(o) -> void:
	if not _h3_tower_on(o):
		return
	var g = o.g
	var cv = o.cv
	var r: float = float(o.hw.lm.tower_b.get("r", 220.0))
	cv.draw_set_transform((o.hw.lm.tower_pos as Vector2) + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
	feather_ring(cv, r, H3_WARM, 0.5, g.t)   # 10-29：不填充，改内羽边 + 光点
	cv.draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(H3_WARM.r, H3_WARM.g, H3_WARM.b, 0.35 + 0.1 * sin(g.t * 4.0)), 2.5)
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _h3lm_draw_over(o) -> void:
	var g = o.g
	var cv = o.cv
	var lm: Dictionary = o.hw.lm
	var a: Dictionary = o.B.get("attack", {})
	var bt: Dictionary = a.get("bolt", {})
	var tn: String = str(bt.get("tex", "proj_lumen_bolt"))
	for b in lm.bolts:
		var big: bool = b.get("big", false)
		if g.tex.get(tn) != null:
			if big:
				cv.draw_line(b.pos - b.vel.normalized() * 22.0, b.pos, Color(2.0, 1.6, 0.9, 0.55), 6.0)
				cv.draw_circle(b.pos, 8.0, Color(1.6, 1.3, 0.7, 0.5))
			o.draw_spr_rot(tn, int(g.t * 12.0 + b.pos.x * 0.05) % 6, b.pos, b.vel.angle(), g.PX * (1.5 if big else 1.0), Color(1.5, 1.35, 1.1) if big else Color.WHITE)
		else:
			cv.draw_line(b.pos - b.vel.normalized() * 14.0, b.pos, Color(H3_WARM.r * 1.4, H3_WARM.g * 1.3, H3_WARM.b, 0.5), 5.0 if big else 3.0)
			cv.draw_circle(b.pos, 6.0 if big else 4.0, Color(2.0, 1.8, 1.2))
	_h3lm_draw_units(o)
	_h3lm_draw_rain(o)


static func _h3lm_draw_units(o) -> void:
	var g = o.g
	var cv = o.cv
	var lm: Dictionary = o.hw.lm
	var a: Dictionary = o.B.get("attack", {})
	var units: int = _h3_units_n(o, a)
	if units <= 0 or o.pos == Vector2.INF:
		return
	var utx: Texture2D = o.A.tex("fx_lumen_unit")
	var hot: bool = int(lm.empowered) > 0
	for k in units:
		var p: Vector2 = _h3_unit_pos(o, k)
		var pulse: float = 0.5 + 0.5 * sin(g.t * 6.0 + k * 2.0)
		cv.draw_circle(p, 9.0 + 2.0 * pulse, Color(1.0, 0.8, 0.4, 0.16 if not hot else 0.3))
		if utx != null:
			var firing: bool = g.t - float(lm.unit_fire[k]) < 0.083
			var uf: int = 4 if firing else (int(g.t * 6.0) + k * 2) % 4
			o._strip(utx, 5, uf, p, g.PX, Vector2(6, 7), firing and float(lm.unit_fdir[k]) < 0.0, Color(1.35, 1.25, 1.05) if hot else Color.WHITE)
			continue
		cv.draw_colored_polygon(PackedVector2Array([p + Vector2(-5, -4), p + Vector2(5, -4), p + Vector2(3, -7), p + Vector2(-3, -7)]), Color(0.35, 0.27, 0.18))
		cv.draw_rect(Rect2(p + Vector2(-4, -4), Vector2(8, 7)), Color(1.0, 0.85, 0.5, 0.55))
		cv.draw_rect(Rect2(p + Vector2(-2, -2), Vector2(4, 4)), Color(2.2, 1.9, 1.2) if hot else Color(1.8, 1.5, 0.9))
		cv.draw_rect(Rect2(p + Vector2(-4, 3), Vector2(8, 2)), Color(0.35, 0.27, 0.18))
		cv.draw_line(p + Vector2(0, 5), p + Vector2(0, 9 + 2.0 * pulse), Color(1.4, 1.1, 0.6, 0.6), 1.0)
	var ch = a.get("units", _ED).get("charge", null)
	if ch is Dictionary and cond_true(o, ch.get("cond", _ED)):
		var need: int = int(ch.get("need", 8))
		var c0: Vector2 = o.pos + Vector2(-(need - 1) * 3.0, -94)
		for q in need:
			var pp: Vector2 = c0 + Vector2(q * 6.0, 0)
			var on: bool = (q < int(lm.empowered)) if int(lm.empowered) > 0 else (q < int(lm.charge_n))
			var col: Color = Color(2.0, 1.6, 0.7) if (on and int(lm.empowered) > 0) else (Color(1.2, 1.05, 0.8) if on else Color(0.25, 0.22, 0.2, 0.8))
			cv.draw_rect(Rect2(pp - Vector2(2, 2), Vector2(4, 4)), col)


static func _h3lm_draw_rain(o) -> void:
	var lm: Dictionary = o.hw.lm
	if float(lm.rain_t) <= 0.0:
		return
	var g = o.g
	var cv = o.cv
	var b: Dictionary = lm.rain_b
	var r: float = float(b.get("r", 140.0))
	var fade: float = clampf(float(lm.rain_t) / 0.4, 0.0, 1.0) * clampf((float(b.get("dur", 3.0)) - float(lm.rain_t)) / 0.3, 0.0, 1.0)
	cv.draw_set_transform(g.ppos + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
	feather_ring(cv, r, Color(1.0, 0.85, 0.5), 0.5 * fade, g.t)
	cv.draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(1.3, 1.1, 0.7, 0.35 * fade), 1.5)
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for q in 28:
		var ph: float = fmod(g.t * 1.8 + q * 0.379, 1.0)
		var cyc: int = int(g.t * 1.8 + q * 0.379)
		var hh: int = hash(Vector2i(q, cyc))
		var an: float = float(hh % 628) / 100.0
		var rr: float = r * sqrt(float((hh >> 10) % 100) / 100.0)
		var ground: Vector2 = g.ppos + Vector2(cos(an) * rr, sin(an) * rr * 0.55)
		var top: Vector2 = ground + Vector2(0, -70.0 * (1.0 - ph))
		cv.draw_line(top + Vector2(0, -8), top, Color(1.6, 1.35, 0.8, 0.7 * fade), 1.5)
		if ph > 0.85:
			cv.draw_set_transform(ground, 0.0, Vector2(1.0, 0.5))
			cv.draw_arc(Vector2.ZERO, 3.0 + (ph - 0.85) * 40.0, 0.0, TAU, 10, Color(1.4, 1.2, 0.7, 0.5 * fade), 1.0)
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 加色层（data_operator.draw_fx_add 转来）
static func h3_draw_add(o, ci) -> void:
	if not hw_on(o) or not o.hw.has("lm") or o.pos == Vector2.INF:
		return
	var g = o.g
	var lm: Dictionary = o.hw.lm
	var a: Dictionary = o.B.get("attack", {})
	if float(lm.hand_glow) > 0.0:
		var hk: float = sin(float(lm.hand_glow) / 0.3 * PI)
		var hp: Vector2 = _h3_lamp_hand(o, a)
		ci.draw_circle(hp, 11.0 * (0.5 + 0.5 * hk), Color(0.9, 0.7, 0.35, 0.45 * hk))
		ci.draw_circle(hp, 4.0 * hk, Color(1.0, 0.9, 0.6, 0.8 * hk))
	var twr: bool = _h3_tower_on(o)
	if twr:
		var k: float = 0.5 + 0.5 * sin(g.t * 3.0)
		ci.draw_circle(_h3_tower_lamp(o), 26.0 + 4.0 * k, Color(0.9, 0.7, 0.35, 0.35))
		ci.draw_set_transform((lm.tower_pos as Vector2) + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
		pass
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for b in lm.bolts:
		ci.draw_circle(b.pos, 14.0 if b.get("big", false) else 9.0, Color(0.9, 0.7, 0.3, 0.35))
	var bb := _h3_beam_block(o)
	if _h3_beam_on(o, bb):
		var L: float = float(bb.get("len", 260.0))
		var org: Vector2 = _h3_beam_origin(o)
		var d: Vector2 = _h3_beam_dir(o, bb)
		var n: Vector2 = Vector2(-d.y, d.x).normalized()
		var tip: Vector2 = org + d * L
		var fade: float = clampf((float(lm.tower_t) if twr else float(lm.beam_t)) / 0.5, 0.0, 1.0)
		ci.draw_colored_polygon(PackedVector2Array([org + n * 4.0, tip + n * 26.0, tip - n * 26.0, org - n * 4.0]), Color(0.9, 0.7, 0.35, 0.28 * fade))
		ci.draw_colored_polygon(PackedVector2Array([org + n * 2.0, tip + n * 10.0, tip - n * 10.0, org - n * 2.0]), Color(1.0, 0.85, 0.5, 0.35 * fade))
		ci.draw_line(_h3_tower_lamp(o) if twr else org + Vector2(0, -44.0), org + d * 30.0, Color(0.9, 0.75, 0.4, 0.3 * fade), 3.0)


static func _h3lm_bodies(o) -> Array:
	if _h3_tower_on(o):
		return [{"y": (o.hw.lm.tower_pos as Vector2).y + 2.0, "h3": "tower"}]
	return []


static func _h3lm_draw_tower(o) -> void:
	var b: Dictionary = o.hw.lm.tower_b
	var an: String = str(b.get("anim", "lighthouse"))
	var tx: Texture2D = o.anim_tex(an)
	if tx == null:
		o.cv.draw_rect(Rect2((o.hw.lm.tower_pos as Vector2) + Vector2(-8, -60), Vector2(16, 60)), Color(0.5, 0.6, 0.7))
		return
	var n: int = o.anim_hframes(tx, an)
	o.draw_sprite_at(_h3_tower_sprite_pos(o), false, Color.WHITE, 1 % n, tx, n, o.foot_off(tx, an))


static func _h3lm_shadow(o) -> void:
	if _h3_tower_on(o):
		var sp: Vector2 = _h3_tower_sprite_pos(o)
		var tp: Vector2 = o.hw.lm.tower_pos
		o.draw_spr("shadow", 1, 0, Vector2(sp.x, tp.y + 4.0), o.g.PX * (1.3 - 0.02 * (tp.y - sp.y - 8.0)))


static func _h3lm_status(o) -> Array:
	var out: Array = []
	if _h3_tower_on(o):
		out.append([str(o.hw.lm.tower_b.get("status", "灯塔")), H3_WARM])
	if float(o.hw.lm.immune_t) > 0.0:
		out.append(["净化", H3_PALE])
	return out


# ---------------------------------------------------------------- 流明：折光 / 灯塔光柱

## 光弹命中已被照亮的敌人（was_lit）：折向 r 内最近的未照亮敌人
static func _e3_refract(o, bt: Dictionary, e: Dictionary, dmg: float) -> void:
	var rf = bt.get("refract", null)
	if not (rf is Dictionary) or not cond_true(o, rf.get("cond", _ED)):
		return
	var g = o.g
	var r: float = float(rf.get("r", 120.0))
	var best := {}
	var bd := INF
	for j in o.query_ids(e.pos, r + 20.0):
		var q: Dictionary = g.enemies[j]
		if q.dead or is_same(q, e) or float(q.get("lit", 0.0)) > 0.0:
			continue
		var d: float = q.pos.distance_to(e.pos)
		if d <= r and d < bd:
			bd = d
			best = q
	if best.is_empty():
		return
	o.log_hit(str(rf.get("src", "")))
	o.deal_damage(best, dmg * float(rf.get("mult", 0.25)))
	best["lit"] = float(bt.get("lit", 3.0))
	var a: Vector2 = e.pos + Vector2(0, -e.r * 0.5)
	var b: Vector2 = best.pos + Vector2(0, -best.r * 0.5)
	o.fx({"kind": "line", "pos": a, "to": b, "life": 0.12, "col": Color(1.6, 1.45, 1.0), "w": 1.0, "laser": true})
	if not o.spawn_fx_sprite(str(rf.get("hit", "fx_lumen_refract_hit")), b, g.PX):
		o.spawn_fx_sprite("fx_holy_impact_lantern", b, g.PX * 0.5)


## 一发（流明本人 / 发光单元）：光柱攒满时这一发变光柱，返回 true（不再射光弹）；否则计数
static func _e3_beam_shot(o, lm: Dictionary, from: Vector2, to_pt: Vector2, dmg: float) -> bool:
	var bm = o.B.get("attack", _ED).get("beam", null)
	if not (bm is Dictionary) or not cond_true(o, bm.get("cond", _ED)):
		return false
	if int(lm.empowered) > 0:
		lm.empowered = int(lm.empowered) - 1
		_e3_beam_fire(o, bm, from, (to_pt - o.pos).normalized(), dmg)
		return true
	lm.charge_n = int(lm.charge_n) + 1
	if int(lm.charge_n) >= int(bm.get("need", 8)):
		lm.charge_n = 0
		lm.empowered = int(bm.get("shots", 8))
		o.fx({"kind": "ring", "pos": o.pos + Vector2(0, -94), "r": 22.0, "r0": 4.0, "life": 0.4, "col": H3_WARM, "keep": true})
		_h3_vsparks(o, o.pos + Vector2(0, -94), H3_WARM, 8, 120.0, 0.4, 2.0)
	return false


static func _e3_beam_fire(o, bm: Dictionary, from: Vector2, d: Vector2, dmg: float) -> void:
	var g = o.g
	var L: float = float(bm.get("len", 200.0)) * o.stat(&"op_range")
	var W: float = float(bm.get("w", 10.0))
	var org: Vector2 = o.pos   # 判定贴地：从脚底朝目标脚底；画面从出光点（提灯 / 发光单元的高度）平行打出
	var hits: Array = []
	for j in o.query_ids(org + d * L * 0.5, L * 0.6 + 40.0):
		var e: Dictionary = g.enemies[j]
		if e.dead:
			continue
		var along: float = seg_rect_along(org, d, L, W * 0.5, e.pos, e.r)   # B6 ⑤：ob_geom
		if along == -INF:
			continue
		hits.append([along, e])
	hits.sort_custom(func(x, y): return x[0] < y[0])
	var src: String = str(bm.get("src", ""))
	var bd: float = dmg * float(bm.get("mult", 1.4))
	for hh in hits:
		var e: Dictionary = hh[1]
		o.log_hit(src)
		o.deal_damage(e, bd)
		e["lit"] = 3.0
		if not o.spawn_fx_sprite(str(bm.get("hit", "fx_lumen_beam_hit")), e.pos + Vector2(0, -e.r * 0.5), g.PX):
			o.fx({"kind": "glow", "pos": e.pos + Vector2(0, -e.r * 0.5), "r": 10.0, "life": 0.18, "col": Color(1.6, 1.5, 1.2), "alpha": 0.7})
	if g.hp < g.max_hp and float(bm.get("heal", 0.0)) > 0.0:
		o.heal_leader(g.max_hp * float(bm.heal), o.display_name(), str(bm.get("heal_sub", "")))
	o.fx({"kind": "h3_beam", "pos": from, "dir": d, "len": L, "w": W, "life": 0.2, "tile": str(bm.get("tile", "fx_lumen_beam"))})
	if not o.spawn_fx_sprite(str(bm.get("flare", "fx_lumen_beam_flare")), from, g.PX):
		o.fx({"kind": "glow", "pos": from, "r": 14.0, "life": 0.2, "col": Color(1.6, 1.4, 0.9), "alpha": 0.7})
	_h3_sfx(o, "atk", 2.0, 1.25, 0.05)


static func _e3_draw_beam(o, f: Dictionary, a: float) -> void:
	var g = o.g
	var cv = o.cv
	var p0: Vector2 = f.pos
	var p1: Vector2 = p0 + (f.dir as Vector2) * float(f.len)
	var tn: String = str(f.get("tile", "fx_lumen_beam"))
	if g.tex.get(tn) != null and g.V6_FRAMES.has(tn):
		var nfr: int = int(g.V6_FRAMES[tn][0])
		_hw_draw_tiled(o, tn, p0, p1, g.PX, 0.0, 0, Color(1, 1, 1, clampf(a * 1.4, 0.0, 1.0)), mini(int((1.0 - a) * nfr), nfr - 1))
		return
	var w: float = float(f.get("w", 10.0)) * (0.35 + 0.65 * a)
	cv.draw_line(p0, p1, Color(1.0, 0.85, 0.5, 0.55 * a), w)
	cv.draw_line(p0, p1, Color(2.0, 1.9, 1.6, 0.9 * a), maxf(1.0, w * 0.35))
	cv.draw_circle(p0, 6.0 + 6.0 * a, Color(1.5, 1.3, 0.8, 0.5 * a))
