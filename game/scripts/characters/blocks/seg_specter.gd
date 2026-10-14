## 干员积木 · seg_specter（docs/101 §7.3 B6 ①，10-15：由 op_blocks.gd 按段拆出，内容与注释照搬；继承链与门面见 op_blocks.gd）
extends "res://scripts/characters/blocks/seg_irene.gd"

const H3_GHOST := Color(0.75, 0.85, 0.95)

const H3_RED := Color(0.9, 0.3, 0.4)


static func _h3sp(o) -> Dictionary:
	var h := hw_st(o)
	if not h.has("sp"):
		h["sp"] = {"fall_t": 0.0, "doll_t": 0.0, "doll_pos": Vector2.INF, "doll_tick": 0.0, "doll_at": 0.0, "elegy_t": 0.0, "sub": {},
			"spin2_t": -1.0, "spin2_dmg": 0.0, "whirl_t": 0.0, "whirl_tick": 0.0, "whirl_n": 0, "whirl_dmg": 0.0, "whirl_ang": 0.0,
			"rings": [], "last_s": [0.0, 0.0, 0.0]}
	return h.sp


static func h3_saw_r(o, a: Dictionary) -> float:
	return _h3_mults(o, float(a.get("r", 120.0)) * o.stat(&"op_range"), a.get("r_mults", []))


## 普攻间隔（data_operator 起手）：every ÷ 攻速，再按 cd_div / cd_mult（同手写的除乘顺序），× 局部 interval
static func h3_attack_cd(o, a: Dictionary) -> float:
	var cdv: float = float(a.get("every", 1.0)) / o.stat(&"op_aspd")
	for m in a.get("cd_div", _EA):
		if cond_true(o, m.get("cond", _ED)):
			cdv /= float(m.get("value", 1.0))
	for m in a.get("cd_mult", _EA):
		if cond_true(o, m.get("cond", _ED)):
			cdv *= float(m.get("value", 1.0))
	return cdv * float(o.loc.interval)


static func _h3_any_skill(o) -> bool:
	return o.s_t[0] > 0.0 or o.s_t[1] > 0.0 or o.s_t[2] > 0.0


static func _h3_saw_release(o, a: Dictionary) -> void:
	var sp := _h3sp(o)
	var m := 1.0
	for it in a.get("mults", _EA):
		if not cond_true(o, it.get("cond", _ED)):
			continue
		var v: float = float(it.get("value", 1.0))
		if it.get("hp_lost", false):
			v += clampf(1.0 - o.g.hp / o.g.max_hp, 0.0, 1.0)
		m *= v
	var dmg: float = o.base(str(a.get("atk_key", "atk")), 0.0) * o._dmg_bonus() * m * (o.skill_power() if (str(a.get("power", "")) == "active" and _h3_any_skill(o)) else 1.0)
	hw_record(o, dmg, 0.0, h3_saw_r(o, a), o.pos)   # basis attack = 这一圈主环斩的伤害（替身闪现按它取百分比）
	_h3_spin(o, a, dmg, 0)
	var s2 = a.get("spin2", null)
	var dbl: bool = s2 is Dictionary and cond_true(o, s2.get("cond", _ED))
	if dbl:
		sp.spin2_t = float(s2.get("delay", 0.15))
		sp.spin2_dmg = dmg * float(s2.get("mult", 0.7))
	var tr = a.get("trail", null)
	if tr is Dictionary and cond_true(o, tr.get("cond", _ED)):
		if sp.rings.size() >= int(tr.get("max", 6)):
			sp.rings.pop_front()
		sp.rings.append({"pos": o.pos, "r": h3_saw_r(o, a), "t": float(tr.get("dur", 1.5)), "tick": float(tr.get("tick", 0.5)), "dmg": dmg * float(tr.get("mult", 0.2)), "b": tr})
	var wh = a.get("whirl", null)
	if wh is Dictionary and cond_true(o, wh.get("cond", _ED)):
		var tk: float = float(wh.get("tick", 0.15))
		sp.whirl_t = float(wh.get("dur_dark", 1.2)) if o.g.lamp < 30.0 else float(wh.get("dur", 0.6))
		sp.whirl_n = int(round(float(sp.whirl_t) / tk)) - (1 if dbl else 0)
		sp.whirl_tick = tk * (2.0 if dbl else 1.0)
		sp.whirl_dmg = dmg * float(wh.get("mult", 0.45))


## 一圈环斩：kind 0 = 主圈 / 1 = 反向第二圈 / 2 = 持续旋转的一段
static func _h3_spin(o, a: Dictionary, dmg: float, kind: int) -> void:
	var g = o.g
	var sp: Dictionary = o.hw.sp
	var r: float = h3_saw_r(o, a)
	var hits: Array = o.arc_targets(o.pos + Vector2(0, float(a.get("y", -10.0))), 0.0, PI, r)
	var lh = a.get("low_hp", null)
	var low_on: bool = lh is Dictionary and cond_true(o, lh.get("cond", _ED))
	var heavy: bool = _h3_heavy(o, a)
	var src: String = str(a.get("src", ""))
	var kb: float = float(a.get("kb", 70.0))
	for e in hits:
		var d: float = dmg
		if low_on and e.hp < e.maxhp * float(lh.get("below", 0.5)):
			d *= float(lh.get("mult", 1.5))
		o.log_hit(src, a.get("tags", []))
		o.deal_damage(e, d)
		if not e.dead and not e.boss and kind == 0:
			e.kb += (e.pos - o.pos).normalized() * kb
		o.fx({"kind": "glow", "pos": e.pos + Vector2(0, -e.r * 0.5), "r": 9.0, "life": 0.15, "col": H3_RED if heavy else H3_GHOST, "alpha": 0.5})
	var rev: bool = (o.face < 0.0) != (kind == 1)
	if kind == 2:
		rev = (o.face < 0.0) != (int(sp.whirl_n) % 2 == 1)
	var lk: Dictionary = a.get("look", {})
	if kind == 2 or not o.spawn_fx_sprite(str(lk.get("blood", "fx_specter_saw_blood")) if heavy else str(lk.get("saw", "fx_specter_saw")), o.pos + Vector2(0, -6), r / 40.0, 0.0, rev):
		o.fx({"kind": "h3_saw", "pos": o.pos + Vector2(0, -8), "r": r * (0.9 if kind == 2 else 1.0), "life": 0.3 if heavy else 0.24, "col": H3_RED if heavy else H3_GHOST,
			"spin": (-1.0 if rev else 1.0) * (26.0 if heavy else 34.0), "tooth": 8.0 if heavy else 6.0, "ang": g.vrng.randf() * TAU})
	if kind == 1:
		o.fx({"kind": "h3_saw", "pos": o.pos + Vector2(0, -8), "r": r * 1.08, "life": 0.22, "col": H3_RED if heavy else Color(0.6, 0.75, 0.95),
			"spin": (-1.0 if rev else 1.0) * 30.0, "tooth": 5.0, "ang": g.vrng.randf() * TAU})
	for e in hits:
		var ea: float = (e.pos - o.pos).angle() + PI / 2.0 * (-1.0 if rev else 1.0)
		for k in (3 if kind == 0 else 1):
			o.fx({"kind": "spark", "pos": e.pos + Vector2(0, -e.r * 0.5), "vel": Vector2.from_angle(ea + g.vrng.randf_range(-0.35, 0.35)) * g.vrng.randf_range(160, 300),
				"life": 0.22, "col": Color(1.4, 1.55, 1.75) if not heavy else Color(1.6, 0.5, 0.55), "sz": 2.0, "drag": 3.0})
	if heavy and kind == 0:
		o.fx({"kind": "crack", "pos": o.pos + Vector2(0, 4), "r": r * 0.8, "life": 0.6, "col": H3_RED, "floor": true, "n": 7})
		o.impact_pause(0.05)
	if kind == 1:
		_h3_sfx(o, "atk", -4.0, 1.15, 0.06)


static func _h3_heavy(o, a: Dictionary) -> bool:
	var hv = a.get("look", _ED).get("heavy", null)
	return hv is Dictionary and cond_true(o, hv.get("cond", _ED))


static func _h3_spins_tick(o, sp: Dictionary, dt: float) -> void:
	if h3_away(o):
		sp.spin2_t = -1.0
		sp.whirl_t = 0.0
		sp.whirl_n = 0
		return
	var a: Dictionary = o.B.get("attack", {})
	sp.whirl_ang = float(sp.whirl_ang) + dt * 14.0 * (1.0 if o.face >= 0.0 else -1.0)
	if float(sp.spin2_t) >= 0.0:
		sp.spin2_t = float(sp.spin2_t) - dt
		if float(sp.spin2_t) < 0.0:
			_h3_spin(o, a, float(sp.spin2_dmg), 1)
	if float(sp.whirl_t) > 0.0 or int(sp.whirl_n) > 0:
		sp.whirl_t = maxf(0.0, float(sp.whirl_t) - dt)
		sp.whirl_tick = float(sp.whirl_tick) - dt
		if float(sp.whirl_tick) <= 0.0 and int(sp.whirl_n) > 0:
			sp.whirl_tick = float(sp.whirl_tick) + float(a.get("whirl", _ED).get("tick", 0.15))
			sp.whirl_n = int(sp.whirl_n) - 1
			_h3_spin(o, a, float(sp.whirl_dmg), 2)


static func _h3_rings_tick(o, sp: Dictionary, dt: float) -> void:
	if sp.rings.is_empty():
		return
	var g = o.g
	for rg in sp.rings:
		rg.t -= dt
		rg.tick -= dt
		if rg.tick <= 0.0 and rg.t > -0.01:
			rg.tick += float(rg.b.get("tick", 0.5))
			for j in o.query_ids(rg.pos, rg.r + 20.0):
				var e: Dictionary = g.enemies[j]
				if e.dead or e.pos.distance_to(rg.pos) > rg.r + e.r:
					continue
				o.log_hit(str(rg.b.get("src", "")), rg.b.get("tags", []))
				o.deal_damage(e, rg.dmg)
			_h3_vsparks(o, rg.pos + Vector2(0, 2), Color(1.1, 0.3, 0.4), 3, 60.0, 0.35, 2.0, 0.0, true)
	sp.rings = sp.rings.filter(func(rg): return rg.t > 0.0)


# ---------------------------------------------------------------- 替身（verb.substitute）/ 不倒（verb.undying）

static func h3_away(o) -> bool:
	return hw_on(o) and o.hw.has("sp") and float(o.hw.sp.doll_t) > 0.0


static func h3_prevent_death(o) -> bool:
	if not hw_on(o) or not o.hw.has("sp"):
		return false
	var sk: Array = o.B.get("skills", [])
	for i in mini(3, sk.size()):
		if o.s_t[i] > 0.0:
			for b in sk[i].get("do", _EA):
				if str(b.get("_tag", "")) == "verb.undying":
					return true
	return false


## 技能结束检测：带 verb.substitute 的技能剩余从 > 0 变成 0 的那一帧（同手写 s2_t -= dt; <= 0）
static func _h3_sub_check(o, sp: Dictionary) -> void:
	var sk: Array = o.B.get("skills", [])
	for i in mini(3, sk.size()):
		var was: float = float(sp.last_s[i])
		sp.last_s[i] = float(o.s_t[i])
		if was > 0.0 and o.s_t[i] <= 0.0:
			for b in sk[i].get("do", _EA):
				if str(b.get("_tag", "")) == "verb.substitute":
					_h3_start_fall(o, sp, b)
					break


static func _h3_fall_dur(o, b: Dictionary) -> float:
	var an: String = str(b.get("anim", "fall"))
	var spec: Dictionary = o.sprite_spec(an)
	return float(spec.get("frames", 5)) / float(spec.get("fps", 10)) if o.anim_tex(an) != null else 0.0


static func _h3_start_fall(o, sp: Dictionary, b: Dictionary) -> void:
	o.melee_tgt = null
	o.fire_t = -1.0
	sp.sub = b
	sp.fall_t = _h3_fall_dur(o, b)
	if float(sp.fall_t) <= 0.0:
		_h3_fall(o, sp)


static func _h3_fall(o, sp: Dictionary) -> void:
	var b: Dictionary = sp.sub
	sp.doll_pos = o.pos
	sp.doll_t = float(b.get("life", 12.0))
	sp.doll_tick = 0.0
	sp.doll_at = 0.0
	o.melee_tgt = null
	o.float_text(o.pos + Vector2(0, -60), str(b.get("text", "替身")), H3_GHOST, 15)
	o.fx({"kind": "glow", "pos": o.pos + Vector2(0, -24), "r": 30.0, "life": 0.5, "col": H3_GHOST, "alpha": 0.6})
	_h3_vsparks(o, o.pos + Vector2(0, -20), H3_GHOST, 10, 120.0, 0.5, 2.5)


static func _h3_doll_slow_r(o, au: Dictionary) -> float:
	return _h3_mults(o, float(au.get("r", 120.0)), au.get("slow_mults", []))


static func _h3_doll_tick(o, sp: Dictionary, dt: float) -> void:
	if float(sp.doll_t) <= 0.0:
		return
	var g = o.g
	var b: Dictionary = sp.sub
	var au: Dictionary = b.get("doll_aura", {})
	sp.doll_t = float(sp.doll_t) - dt
	sp.doll_at = float(sp.doll_at) + dt
	var fv = b.get("follow", [-46, 8])
	var want: Vector2 = g.ppos + Vector2(float(fv[0]) * g.squad.side, float(fv[1]))
	sp.doll_pos = (sp.doll_pos as Vector2).lerp(want, clampf(dt * 4.0, 0.0, 1.0))
	var el = b.get("elegy", null)
	if el is Dictionary and cond_true(o, el.get("cond", _ED)):
		sp.elegy_t = float(sp.elegy_t) - dt
		if float(sp.elegy_t) <= 0.0:
			sp.elegy_t = float(el.get("every", 0.8))
			var er: float = _h3_doll_slow_r(o, au)
			var dp: Vector2 = sp.doll_pos
			o.fx({"kind": "ring", "pos": dp + Vector2(0, 2), "r": er, "r0": 14.0, "life": 1.6, "col": Color(0.45, 0.75, 1.1), "floor": true, "w": 2.5, "alpha": 0.7, "keep": true})
			o.fx({"kind": "ring", "pos": dp + Vector2(0, 2), "r": er * 0.7, "r0": 6.0, "life": 1.2, "col": Color(0.8, 0.95, 1.3), "floor": true, "w": 1.5, "alpha": 0.45, "keep": true})
			o.fx({"kind": "mote", "pos": dp + Vector2(g.vrng.randf_range(-8, 8), -40), "vel": Vector2(g.vrng.randf_range(-10, 10), -26.0), "life": 1.0, "col": Color(0.6, 0.85, 1.2), "sz": 2.0})
	if not au.is_empty() and cond_true(o, au.get("cond", _ED)):
		sp.doll_tick = float(sp.doll_tick) + dt
		var ev: float = float(au.get("every", 1.0))
		if float(sp.doll_tick) >= ev:
			sp.doll_tick = float(sp.doll_tick) - ev
			var r: float = float(au.get("r", 120.0))
			var sr: float = _h3_doll_slow_r(o, au)
			var dp2: Vector2 = sp.doll_pos
			for j in o.query_ids(dp2, sr + 20.0):
				var e: Dictionary = g.enemies[j]
				if e.dead:
					continue
				var d: float = e.pos.distance_to(dp2)
				if d > sr:
					continue
				e.slow = maxf(e.slow, float(au.get("slow", 1.0)))
				if d > r:
					continue
				o.log_hit(str(au.get("src", "")), au.get("tags", []))
				o.deal_damage(e, float(au.get("dps", 10.0)) * o._dmg_bonus())
			if not o.spawn_fx_sprite("fx_circle_ghost", dp2 + Vector2(0, 4), g.PX * (r / 40.0)):
				o.fx({"kind": "ring", "pos": dp2, "r": r, "r0": r * 0.6, "life": 0.5, "col": H3_GHOST, "floor": true, "alpha": 0.5, "keep": true})
	if float(sp.doll_t) <= 0.0:
		sp.elegy_t = 0.0
		o.pos = sp.doll_pos
		sp.doll_pos = Vector2.INF
		o.float_text(o.pos + Vector2(0, -60), str(b.get("back_text", "归队")), H3_GHOST, 14)
		o.fx({"kind": "glow", "pos": o.pos + Vector2(0, -24), "r": 24.0, "life": 0.4, "col": H3_GHOST, "alpha": 0.5})


## 第 3 批幽灵鲨段每帧（h3_tick 转来，手写 update 的先后：技能结束 → 倒下 → 替身 → 血痕 → 气焰 → 第二圈 / 持续旋转）。返回 true = 本帧不起手
static func _h3sp_tick(o, sp: Dictionary, dt: float) -> bool:
	_h3_sub_check(o, sp)
	if float(sp.fall_t) > 0.0:
		sp.fall_t = float(sp.fall_t) - dt
		if float(sp.fall_t) <= 0.0:
			_h3_fall(o, sp)
	_h3_doll_tick(o, sp, dt)
	_h3_rings_tick(o, sp, dt)
	var g = o.g
	if o.s_t[0] > 0.0 and not h3_away(o) and g.vrng.randf() < dt * 14.0 and o.B.get("attack", _ED).get("look", {}).get("flame", false):
		o.fx({"kind": "mote", "pos": o.pos + Vector2(g.vrng.randf_range(-16, 16), g.vrng.randf_range(-40, -4)), "vel": Vector2(0, -60), "life": 0.5, "col": Color(1.0, 0.2, 0.25), "sz": 2.0})
	_h3_spins_tick(o, sp, dt)
	_e3_flash_tick(o, sp, dt)   # 精英化第 3 批：替身闪现
	return h3_away(o) or float(sp.fall_t) > 0.0


static func h3_follow_away(o) -> bool:
	return h3_away(o)


## 倒下期间的帧（data_operator.anim_state 转来）
static func h3_anim_state(o, st: Dictionary) -> Dictionary:
	if not o.hw.has("sp") or float(o.hw.sp.fall_t) <= 0.0:
		return st
	var an: String = str(o.hw.sp.sub.get("anim", "fall"))
	var tx: Texture2D = o.anim_tex(an)
	if tx == null:
		return st
	var n: int = o.anim_hframes(tx, an)
	var fr: int = clampi(int((_h3_fall_dur(o, o.hw.sp.sub) - float(o.hw.sp.fall_t)) * float(o.sprite_spec(an).get("fps", 10))), 0, n - 1)
	return {"tex": tx, "frame": fr, "hf": n, "flip": (o.face < 0.0) != o.sprite_mirror(an), "kind": an}


## 替身参与 2.5D 排序（data_operator.extra_bodies 转来）
static func h3_bodies(o) -> Array:
	if not hw_on(o) or not o.hw.has("sp"):
		return []
	var sp: Dictionary = o.hw.sp
	var out: Array = []
	if float(sp.doll_t) > 0.0 and sp.doll_pos != Vector2.INF:
		out.append({"y": (sp.doll_pos as Vector2).y + 2.0, "h3": "doll"})
	if not sp.get("flash", {}).is_empty():
		out.append({"y": (sp.flash.pos as Vector2).y + 2.0, "h3": "flash"})
	return out


static func h3_draw_extra(o, it: Dictionary) -> void:
	if str(it.get("h3", "")) == "flash":
		_e3_flash_draw(o)
		return
	if str(it.get("h3", "")) == "doll":
		var sp: Dictionary = o.hw.sp
		var an: String = str(sp.sub.get("doll_anim", "doll"))
		var tx: Texture2D = o.anim_tex(an)
		var dp: Vector2 = sp.doll_pos
		if tx == null:
			o.cv.draw_circle(dp + Vector2(0, -20), 12.0, H3_GHOST)
			return
		var n: int = o.anim_hframes(tx, an)
		var fr: int = int(float(sp.doll_at) * 4.0) % n
		var sway: float = sin(float(sp.doll_at) * 2.0) * 1.0
		o.draw_sprite_at(dp + Vector2(sway, 0), o.face < 0.0, Color(0.95, 0.95, 1.0), fr, tx, n, o.foot_off(tx, an))


static func h3_draw_shadows(o) -> void:
	if not hw_on(o) or not o.hw.has("sp"):
		return
	var sp: Dictionary = o.hw.sp
	if float(sp.doll_t) > 0.0 and sp.doll_pos != Vector2.INF:
		o.draw_spr("shadow", 1, 0, (sp.doll_pos as Vector2) + Vector2(0, 4), o.g.PX)


## 地面层：潮痕（血色潮痕节点留下的水痕圈）。10-14 用户「血色水痕容易和怪物的攻击提示重合」：敌方预警是红色填充 + 白芯深色描边（world.draw_warn_outlines），
## 这里改成低饱和的深海青、压低透明度、线收细，不带白芯，和敌方预警分开；纯画面
const H3SP_TIDE_FILL := Color(0.07, 0.2, 0.25)

const H3SP_TIDE_EDGE := Color(0.3, 0.56, 0.62)

const H3SP_TIDE_RIPPLE := Color(0.4, 0.66, 0.7)

static func _h3sp_draw_floor(o) -> void:
	var cv = o.cv
	var sp: Dictionary = o.hw.sp
	for rg in sp.rings:
		var a: float = clampf(rg.t / 0.5, 0.0, 1.0)
		var age: float = float(rg.b.get("dur", 1.5)) - rg.t
		cv.draw_set_transform(rg.pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
		cv.draw_circle(Vector2.ZERO, rg.r, Color(H3SP_TIDE_FILL.r, H3SP_TIDE_FILL.g, H3SP_TIDE_FILL.b, 0.12 * a))
		cv.draw_arc(Vector2.ZERO, rg.r, 0.0, TAU, 40, Color(H3SP_TIDE_EDGE.r, H3SP_TIDE_EDGE.g, H3SP_TIDE_EDGE.b, 0.4 * a), 1.5)
		cv.draw_arc(Vector2.ZERO, rg.r * (0.5 + 0.4 * fmod(age * 1.2, 1.0)), 0.0, TAU, 32, Color(H3SP_TIDE_RIPPLE.r, H3SP_TIDE_RIPPLE.g, H3SP_TIDE_RIPPLE.b, 0.22 * a), 1.0)
		for q in 6:
			var an: float = q * TAU / 6.0 + rg.pos.x * 0.01
			cv.draw_circle(Vector2.from_angle(an) * rg.r, 2.0, Color(H3SP_TIDE_RIPPLE.r, H3SP_TIDE_RIPPLE.g, H3SP_TIDE_RIPPLE.b, 0.32 * a))
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 区域层：求生之技气焰、技能期间的锯环圈、替身光环圈
static func _h3sp_draw_auras(o) -> void:
	var g = o.g
	var cv = o.cv
	var sp: Dictionary = o.hw.sp
	var a: Dictionary = o.B.get("attack", {})
	var lk: Dictionary = a.get("look", {})
	var away: bool = h3_away(o)
	if o.pos != Vector2.INF and not away and o.s_t[0] > 0.0 and lk.get("flame", false):
		var hk: float = 0.5 + 0.5 * sin(g.t * 9.0)
		cv.draw_circle(o.pos + Vector2(0, -22), 22.0 + 3.0 * hk, Color(1.0, 0.1, 0.15, 0.16))
		for q in 7:
			var an: float = q * TAU / 7.0 + g.t * 2.0
			var bp: Vector2 = o.pos + Vector2(cos(an) * 16.0, -6.0 + sin(an) * 7.0)
			var hh: float = 14.0 + 6.0 * sin(g.t * 13.0 + q * 2.1)
			cv.draw_colored_polygon(PackedVector2Array([bp + Vector2(-4, 0), bp + Vector2(sin(g.t * 20.0 + q) * 2.0, -hh), bp + Vector2(4, 0)]), Color(1.5, 0.2, 0.25, 0.55))
	if o.pos != Vector2.INF and not away and _h3_any_skill(o):
		var c: Color = H3_RED if _h3_heavy(o, a) else H3_GHOST
		cv.draw_set_transform(o.pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
		cv.draw_arc(Vector2.ZERO, h3_saw_r(o, a), 0.0, TAU, 36, Color(c.r, c.g, c.b, 0.25 + 0.1 * sin(g.t * 6.0)), 2.0)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if float(sp.doll_t) > 0.0 and sp.doll_pos != Vector2.INF and not sp.sub.is_empty():
		var au: Dictionary = sp.sub.get("doll_aura", {})
		if not au.is_empty() and cond_true(o, au.get("cond", _ED)):
			cv.draw_set_transform((sp.doll_pos as Vector2) + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
			cv.draw_arc(Vector2.ZERO, float(au.get("r", 120.0)), 0.0, TAU, 36, Color(H3_GHOST.r, H3_GHOST.g, H3_GHOST.b, 0.2 + 0.08 * sin(g.t * 3.0)), 2.0)
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 上层：持续旋转的锯弧、技能期间眼中寒光
static func _h3sp_draw_over(o) -> void:
	if h3_away(o) or o.pos == Vector2.INF:
		return
	var g = o.g
	var cv = o.cv
	var sp: Dictionary = o.hw.sp
	var a: Dictionary = o.B.get("attack", {})
	if float(sp.whirl_t) > 0.0:
		var r: float = h3_saw_r(o, a) * 0.92
		var fade: float = clampf(float(sp.whirl_t) / 0.2, 0.0, 1.0)
		var heavy: bool = _h3_heavy(o, a) or g.lamp < 30.0
		var c: Color = Color(1.5, 0.45, 0.5) if heavy else Color(1.2, 1.35, 1.6)
		cv.draw_set_transform(o.pos + Vector2(0, -8), 0.0, Vector2(1.0, 0.55))
		for q in 2:
			var a0: float = float(sp.whirl_ang) + q * PI
			for k in 4:
				cv.draw_arc(Vector2.ZERO, r - k * 2.0, a0 - k * 0.22, a0 - k * 0.22 + 1.1, 16, Color(c.r, c.g, c.b, (0.85 - k * 0.2) * fade), 4.0 - k * 0.7)
			cv.draw_circle(Vector2.from_angle(a0 + 1.1) * r, 4.0, Color(c.r * 1.3, c.g * 1.3, c.b * 1.3, 0.9 * fade))
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if (o.s_t[1] > 0.0 or o.s_t[2] > 0.0) and a.get("look", _ED).get("eye", false):
		var p: Vector2 = o.pos + Vector2(4.0 * o.face, -38)
		var c2: Color = H3_RED if o.s_t[2] > 0.0 else H3_GHOST
		cv.draw_circle(p, 2.5 + sin(g.t * 24.0), Color(c2.r * 2.0, c2.g * 1.6, c2.b * 1.6, 0.9))


## 锯环（程序）：半径 0→r 快速张开，锯齿斜切、按 spin 旋转；地面透视压扁
static func _h3_draw_saw(o, f: Dictionary, a: float) -> void:
	var cv = o.cv
	var u: float = 1.0 - a
	var rr: float = f.r * (0.55 + 0.45 * (1.0 - pow(1.0 - minf(1.0, u / 0.25), 2.0)))
	var rot: float = f.ang + f.spin * u * f.max
	var c: Color = f.col
	var T: float = f.tooth
	var n: int = clampi(int(TAU * rr / (T * 1.6)), 16, 48)
	var P := func(v: Vector2) -> Vector2: return (v / 2.0).round() * 2.0
	var fp: Vector2 = f.pos
	var flat := func(v: Vector2) -> Vector2: return fp + Vector2(v.x, v.y * 0.55)
	cv.draw_set_transform(fp, 0.0, Vector2(1.0, 0.55))
	cv.draw_arc(Vector2.ZERO, rr * 0.92, 0.0, TAU, 48, Color(c.r, c.g, c.b, 0.18 * a), T * 1.6)
	cv.draw_arc(Vector2.ZERO, rr, 0.0, TAU, 56, Color(0.05, 0.06, 0.09, 0.8 * a), 7.0)
	cv.draw_arc(Vector2.ZERO, rr, 0.0, TAU, 56, Color(c.r * 0.8, c.g * 0.8, c.b * 0.85, 0.95 * a), 4.0)
	cv.draw_arc(Vector2.ZERO, rr - 3.0, 0.0, TAU, 56, Color(c.r * 1.5, c.g * 1.5, c.b * 1.5, 0.7 * a), 1.0)
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var sgn: float = signf(f.spin)
	for i in n:
		var t0: float = rot + TAU * i / n
		var t1: float = t0 + sgn * TAU / n * 0.75
		var base0: Vector2 = Vector2.from_angle(t0) * rr
		var base1: Vector2 = Vector2.from_angle(t1) * rr
		var tip: Vector2 = Vector2.from_angle(t1) * (rr + T)
		var pts := PackedVector2Array([P.call(flat.call(base0)), P.call(flat.call(tip)), P.call(flat.call(base1))])
		if absf((pts[1] - pts[0]).cross(pts[2] - pts[0])) < 2.0:
			continue
		var lit: float = 0.75 + 0.35 * clampf(sin(t0), 0.0, 1.0)
		cv.draw_colored_polygon(pts, Color(c.r * lit * 1.3, c.g * lit * 1.3, c.b * lit * 1.35, a))


static func _h3sp_status(o) -> Array:
	var out: Array = []
	var sp: Dictionary = o.hw.sp
	var a: Dictionary = o.B.get("attack", {})
	if h3_prevent_death(o):
		out.append(["不倒", H3_GHOST])
	if o.s_t[2] > 0.0 and _h3_heavy(o, a):
		out.append([str(o.skill_def(2).get("name", "")), H3_RED])
	for m in a.get("r_mults", _EA):
		if m.has("status") and cond_true(o, m.get("cond", _ED)):
			out.append([str(m.status), H3_RED])
	if float(sp.doll_t) > 0.0:
		out.append(["%s %d" % [str(sp.sub.get("text", "替身")), int(ceil(float(sp.doll_t)))], H3_GHOST])
	return out


# ---------------------------------------------------------------- 归溟幽灵鲨：替身闪现

static func h3_doll_flash(o, b: Dictionary) -> void:
	var sp := _h3sp(o)
	if not sp.get("flash", {}).is_empty() or h3_away(o) or o.pos == Vector2.INF:
		return
	var rr: float = float(b.get("range", 300.0)) * o.stat(&"op_range")
	var c: Vector2 = o.densest_point(rr, o.pos)
	if c == Vector2.INF:
		var ts: Array = o.nearest_enemies(1, rr, o.pos)
		if ts.is_empty():
			return
		c = ts[0].pos
	var dmg: float = hw_basis(o, str(b.get("basis", "attack"))) * float(b.get("mult", 0.4))
	sp["flash"] = {"pos": c, "t": 0.0, "dmg": dmg, "hit": false, "b": b, "rev": o.face < 0.0}
	var g = o.g
	if not o.spawn_fx_sprite("fx_water_splash", c + Vector2(0, 4), g.PX, 0.0, false, true):
		o.fx({"kind": "ring", "pos": c, "r": 26.0, "r0": 4.0, "life": 0.3, "col": H3_COLD, "floor": true, "w": 2.0})


static func _e3_flash_tick(o, sp: Dictionary, dt: float) -> void:
	var f: Dictionary = sp.get("flash", {})
	if f.is_empty():
		return
	var g = o.g
	var b: Dictionary = f.b
	f.t = float(f.t) + dt
	var ap: float = float(b.get("appear", 0.25))
	var sw: float = float(b.get("spin", 0.3))
	var spins: int = int(b.get("spins", 1))
	var gap: float = float(b.get("spin_gap", 0.15))
	while int(f.get("n_hit", 0)) < spins and float(f.t) >= ap + float(b.get("hit_at", 0.08)) + int(f.get("n_hit", 0)) * gap:   # 连斩 spins 圈，每圈间隔 spin_gap 秒
		var k: int = int(f.get("n_hit", 0))
		f["n_hit"] = k + 1
		var rev: bool = f.rev != (k % 2 == 1)   # 每圈换个转向
		var r: float = float(b.get("r", 100.0)) * o.stat(&"op_range")
		var c: Vector2 = f.pos
		var src: String = str(b.get("src", ""))
		for e in o.arc_targets(c + Vector2(0, -10), 0.0, PI, r):
			o.log_hit(src, b.get("tags", []))
			o.deal_damage(e, float(f.dmg))
			o.fx({"kind": "glow", "pos": e.pos + Vector2(0, -e.r * 0.5), "r": 8.0, "life": 0.15, "col": H3_COLD, "alpha": 0.5})
		var sc: float = r / 34.0
		var ok_b: bool = o.spawn_fx_sprite(str(b.get("saw_back", "fx_specter_saw_cold_back")), c + Vector2(0, -6), sc, 0.0, rev)
		var ok_f: bool = o.spawn_fx_sprite(str(b.get("saw_front", "fx_specter_saw_cold_front")), c + Vector2(0, -6), sc, 0.0, rev)
		if not (ok_b or ok_f):
			o.fx({"kind": "h3_saw", "pos": c + Vector2(0, -8), "r": r, "life": 0.24, "col": H3_COLD, "spin": (-1.0 if rev else 1.0) * 34.0, "tooth": 5.0, "ang": g.vrng.randf() * TAU})
		_h3_sfx(o, "atk", -3.0, 1.2 + 0.08 * k, 0.06)
	if float(f.t) >= ap + sw + float(b.get("burst", 0.3)):
		sp.flash = {}


static func _e3_flash_draw(o) -> void:
	var g = o.g
	var cv = o.cv
	var f: Dictionary = o.hw.sp.get("flash", {})
	if f.is_empty():
		return
	var b: Dictionary = f.b
	var ap: float = float(b.get("appear", 0.25))
	var sw: float = float(b.get("spin", 0.3))
	var bu: float = float(b.get("burst", 0.3))
	var t: float = float(f.t)
	var p: Vector2 = f.pos
	var mid := p + Vector2(0, -16.0 * g.PX)
	if t < ap:
		var k: float = t / ap
		var nm: String = str(b.get("appear_fx", "fx_specter_doll_appear"))
		if g.tex.get(nm) != null:
			fx_frame(cv, g, nm, 5, mini(int(k * 5.0), 4), mid, g.PX, Color.WHITE)
		else:
			_e3_doll_body(o, p, f.rev, Color(0.85, 0.92, 1.1, k), 0)
		return
	if t < ap + sw:
		var spins: int = maxi(1, int(b.get("spins", 1)))
		var ksp: float = fmod((t - ap) / sw * spins, 1.0)   # 旋身帧条每圈播一遍
		var tx: Texture2D = o.anim_tex(str(b.get("anim", "doll_spin")))
		if tx != null:
			var n: int = o.anim_hframes(tx, str(b.get("anim", "doll_spin")))
			o.draw_sprite_at(p, f.rev, Color(0.92, 0.96, 1.1), clampi(int(ksp * n), 0, n - 1), tx, n, o.foot_off(tx, str(b.get("anim", "doll_spin"))))
		else:
			_e3_doll_body(o, p, f.rev, Color(0.92, 0.96, 1.1), int(ksp * 4.0))
		return
	var kb: float = clampf((t - ap - sw) / bu, 0.0, 1.0)
	var nb: String = str(b.get("burst_fx", "fx_specter_doll_burst"))
	if g.tex.get(nb) != null:
		fx_frame(cv, g, nb, 6, mini(int(kb * 6.0), 5), mid, g.PX, Color.WHITE)
	else:
		_e3_doll_body(o, p, f.rev, Color(0.85, 0.92, 1.1, 1.0 - kb), 0)
		for q in 7:
			var an: float = q * TAU / 7.0 + p.x * 0.01
			cv.draw_circle(mid + Vector2(cos(an), sin(an) * 0.6) * (6.0 + 22.0 * kb) + Vector2(0, -14.0 * kb), 2.5 * (1.0 - kb) + 1.0, Color(0.8, 0.92, 1.2, 0.8 * (1.0 - kb)))


static func _e3_doll_body(o, p: Vector2, flip: bool, col: Color, fr: int) -> void:
	var tx: Texture2D = o.anim_tex("doll")
	if tx == null:
		o.cv.draw_circle(p + Vector2(0, -20), 12.0, Color(H3_GHOST.r, H3_GHOST.g, H3_GHOST.b, col.a))
		return
	var n: int = o.anim_hframes(tx, "doll")
	o.draw_sprite_at(p, flip, col, fr % n, tx, n, o.foot_off(tx, "doll"))
