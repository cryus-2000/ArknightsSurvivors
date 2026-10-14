## 干员积木 · seg_skalter（docs/101 §7.3 B6 ①，10-15：由 op_blocks.gd 按段拆出，内容与注释照搬；继承链与门面见 op_blocks.gd）
extends "res://scripts/characters/blocks/seg_saria.gd"

const E5_ANIM_KEYS := ["idle", "run", "attack", "spawn"]

const E5_LOOK_KEYS := ["strip", "fit", "scale", "max_scale", "tint", "ring", "fade", "edge"]   # edge：边线透明度倍率（10-14 加）


## 普攻命中表（data_operator.exec_any_shape 记下、延迟队列带走）：敌人 id → true
static func e5_ids(hits: Array) -> Dictionary:
	var out := {}
	for e in hits:
		out[int(e.id)] = true
	return out


## blocks 里有没有写 among 的积木（data_operator._init 查一次；没有就不记命中表）
static func e5_scan(n) -> bool:
	if n is Dictionary:
		if n.has("among"):
			return true
		for k in n:
			if e5_scan(n[k]):
				return true
	elif n is Array:
		for x in n:
			if e5_scan(x):
				return true
	return false


## shape.circle 的 band / among：伤害口径同 area_hit（× vs_elite、log_hit、命中特效），多两道筛选；不击退、不眩晕
static func e5_area(o, b: Dictionary, c: Vector2, r: float, dmg: float) -> Array:
	var bd = b.get("band", [0.0, 1.0])
	var lo: float = float(bd[0]) * r
	var hi: float = float(bd[1]) * r
	var use_ah: bool = str(b.get("among", "")) == "attack"
	var ah: Dictionary = o.e5.get("ah", {}) if use_ah else {}
	var hits: Array = []
	if use_ah and ah.is_empty():
		return hits
	for e in o.arc_targets(c, 0.0, PI, hi):
		if e.dead or (use_ah and not ah.has(int(e.id))):
			continue
		if e.pos.distance_to(c) + float(e.r) < lo:
			continue
		hits.append(e)
	var max_n: int = int(b.get("max_n", 0))
	if max_n > 0 and hits.size() > max_n:
		hits = o.cap_targets(hits, c, max_n)
	var ve: float = o.vs_elite()
	var src: String = str(b.get("src", ""))
	var tags: Array = b.get("tags", [])
	for e in hits:
		o.log_hit(src, tags)
		o.deal_damage(e, dmg * (ve if e.elite or e.boss else 1.0))
	for e in hits:
		o._hit_fx(e, c)
	return hits


# ---------------------------------------------------------------- 召唤物自带区域 / 帧条 / 施放

## 这种召唤物里最早在场的一个（没有 = {}）
static func e5_summon(o, kind: String) -> Dictionary:
	if o.sm.is_empty():
		return {}
	for s in o.sm.list:
		if not s.gone and (kind == "" or str(s.kind) == kind):
			return s
	return {}


## 召唤物自带区域的半径：r × op_range × (1 + (本干员区域倍率 − 1) × share)；mode: false 时区域倍率先除掉 verb.mode 的 zone_mult
static func e5_zone_r(o, kd: Dictionary) -> float:
	var z = kd.get("zone", {})
	if not (z is Dictionary) or z.is_empty():
		return 0.0
	var lz: float = float(o.loc.zone)
	if not z.get("mode", true):
		lz /= maxf(0.01, float(o.zmode))
	return float(z.get("r", 0.0)) * o.stat(&"op_range") * maxf(0.0, 1.0 + (lz - 1.0) * float(z.get("share", 1.0)))


## shape.circle center: summon:<种类> + r: zone：那个召唤物的区域半径（场上没有时按定义现算）
static func e5_summon_zr(o, kind: String) -> float:
	var s := e5_summon(o, kind)
	if not s.is_empty() and s.has("zr"):
		return float(s.zr)
	return e5_zone_r(o, sm_kind(o, kind))


## data_operator.in_zone 转来：p 在本干员任一召唤物的区域里（半径是这一帧召唤物更新时记下的）
static func e5_in_zone(o, p: Vector2) -> bool:
	for s in o.sm.list:
		if float(s.get("zr", 0.0)) > 0.0 and not s.gone and s.pos.distance_to(p) <= float(s.zr):
			return true
	return false


## sm_spawn 转来：非随行召唤物的帧条 / 区域状态（mf_draw 认的那几个字段同随行召唤物）
static func e5_spawn_state(o, s: Dictionary, kd: Dictionary) -> void:
	var an: Dictionary = kd.get("anim", {})
	var sp: bool = an.has("spawn") and o.anim_tex(str(an.spawn)) != null
	s.merge({"e5": true, "mv": 0.0, "ak": "spawn" if sp else "idle", "at": 0.0, "act": 0.0, "fire": -1.0, "flip_t": -99.0,
		"pcur": {}, "pout": 0.0, "pold": -1, "ghost": {}, "e5_then": [], "rp": 0.0})
	s["zr"] = e5_zone_r(o, kd)


## 帧条一遍的秒数（sprites 的 frames / fps）
static func e5_anim_len(o, key: String) -> float:
	var sp: Dictionary = o.sprite_spec(key)
	return float(sp.get("frames", 4)) / maxf(1.0, float(sp.get("fps", 10)))


## 每帧（sm_tick 转来）：区域半径 → 浮现（期间不走）→ 照常 _sm_step（chase / follow / orbit / stay）→ 转向防抖、施放出手帧、帧条状态
static func e5_step(o, s: Dictionary, kd: Dictionary, i: int, n: int, dt: float) -> void:
	if o.g.perf_alt:
		return
	var an: Dictionary = kd.get("anim", {})
	if kd.has("zone"):
		s.zr = e5_zone_r(o, kd)
	if str(s.ak) == "spawn":
		if float(s.at) < e5_anim_len(o, str(an.get("spawn", ""))):
			s.at = float(s.at) + dt
			return
		_mf_set_anim(s, "idle")
	var prev: Vector2 = s.pos
	var f0: float = float(s.face)
	_sm_step(o, s, kd, i, n, dt)
	var want: float = float(s.face)
	s.face = f0
	var vel: Vector2 = (s.pos - prev) / maxf(dt, 0.0001)
	s.mv = lerpf(float(s.mv), vel.length(), clampf(dt * 10.0, 0.0, 1.0))
	if want != f0 and absf(vel.x) > 20.0:
		_mf_face(o, s, want)
	if float(s.act) > 0.0:
		s.act = float(s.act) - dt
		if float(s.fire) >= 0.0:
			s.fire = float(s.fire) - dt
			if float(s.fire) < 0.0:
				e5_cast_fire(o, s)
	if not an.is_empty():
		_mf_set_anim(s, "attack" if float(s.act) > 0.0 else ("run" if float(s.mv) > 30.0 else "idle"))
	s.at = float(s.at) + dt


## verb.summon_cmd action: cast：kind 种召唤物原地施放，出手帧执行 then（上一次还没到出手帧的先结算，不丢）
static func e5_cast(o, b: Dictionary) -> void:
	var kind: String = str(b.get("kind", ""))
	var kd := sm_kind(o, kind)
	var ak: String = str(kd.get("anim", _ED).get("attack", ""))
	for s in o.sm.list.duplicate():
		if s.gone or str(s.kind) != kind:
			continue
		if not s.has("e5") or str(s.ak) == "spawn" or ak == "" or o.anim_tex(ak) == null or o.g.perf_alt:
			o._exec_list(b.get("then", []), s.pos)
			continue
		if float(s.fire) >= 0.0:
			e5_cast_fire(o, s)
		var sp: Dictionary = o.sprite_spec(ak)
		var fps: float = maxf(1.0, float(sp.get("fps", 10)))
		s.act = float(sp.get("frames", 4)) / fps
		s.fire = (float(sp.get("fire", 2)) + 0.5) / fps
		s.e5_then = b.get("then", [])
		s.ak = "attack"
		s.at = 0.0


static func e5_cast_fire(o, s: Dictionary) -> void:
	s.fire = -1.0
	var th: Array = s.get("e5_then", [])
	s.e5_then = []
	if not th.is_empty() and not s.gone:
		o._exec_list(th, s.pos)


## 区域淡入（召唤物出场后 look.fade 秒，缺省 0.5）
static func e5_zone_fade(s: Dictionary, lk: Dictionary) -> float:
	var fi: float = float(lk.get("fade", 0.5))
	return clampf(float(s.t) / fi, 0.0, 1.0) if fi > 0.0 else 1.0


## 召唤物区域的椭圆（data_operator.draw_auras 转来，同本干员区域的画法与颜色，透明度 × look.ring）
static func e5_draw_zones(o, cc: Color, on: bool) -> void:
	var g = o.g
	if g.perf_alt:
		return
	for s in o.sm.list:
		var zr: float = float(s.get("zr", 0.0))
		if zr <= 0.0 or s.gone:
			continue
		var lk: Dictionary = sm_kind(o, str(s.kind)).get("zone", _ED).get("look", {})
		var k: float = float(lk.get("ring", 0.6)) * e5_zone_fade(s, lk)
		if k <= 0.004:
			continue
		o.cv.draw_set_transform(s.pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
		o.cv.draw_circle(Vector2.ZERO, zr, Color(cc.r, cc.g, cc.b, (0.08 if on else 0.045) * k))
		var ek: float = float(lk.get("edge", 1.0))   # look.edge：边线透明度倍率（0 = 不画边线；10-14 浊心斯卡蒂伊莎玛拉区域去掉红色外圈，纯画面）
		if ek > 0.0:
			o.cv.draw_arc(Vector2.ZERO, zr, 0.0, TAU, 40, Color(cc.r, cc.g, cc.b, ((0.45 if on else 0.28) + 0.06 * sin(g.t * 3.0 + 1.3)) * k * ek), 2.0)
		o.cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 召唤物区域的地面帧条（data_operator.draw_ground_fx 转来，紧贴地砖：溟痕 / Boss 地面预警之下）：每 1x 像素 = 半径 / fit × scale（封顶 max_scale），循环播
static func e5_draw_zone_ground(o) -> void:
	var g = o.g
	if g.perf_alt:
		return
	for s in o.sm.list:
		var zr: float = float(s.get("zr", 0.0))
		if zr <= 0.0 or s.gone:
			continue
		var lk: Dictionary = sm_kind(o, str(s.kind)).get("zone", _ED).get("look", {})
		var name: String = str(lk.get("strip", ""))
		if name == "" or g.tex.get(name) == null or not g.V6_FRAMES.has(name):
			continue
		var spec: Array = g.V6_FRAMES[name]
		var frames: int = maxi(1, int(spec[0]))
		var fr: int = int(float(s.t) * float(spec[1])) % frames
		var sc: float = minf(zr / maxf(1.0, float(lk.get("fit", 64.0))) * float(lk.get("scale", 1.0)), float(lk.get("max_scale", FX_SCALE_MAX)))
		var col := _mf_col(lk.get("tint", []), Color(1, 1, 1, 0.5))
		col.a *= e5_zone_fade(s, lk) * float(g.world.fx_dim)
		if col.a > 0.004:
			fx_frame(o.cv, g, name, frames, fr, s.pos, sc, col)


# ---------------------------------------------------------------- 校验

## _sm_kinds 转来：zone / move.repick / 非随行召唤物的 anim
static func _e5_kind(kd: Dictionary, p: String, ctx: Dictionary) -> void:
	var errs: Array = ctx.errs
	var mv: Dictionary = kd.get("move", {}) if kd.get("move", {}) is Dictionary else {}
	var mode: String = str(mv.get("mode", ""))
	if mv.has("repick"):
		if mode != "chase":
			errs.append(p + ".move.repick 只用于 mode = chase")
		_num(mv, "repick", p + ".move", ctx, false, 0.1, 10.0)
	if kd.has("anim") and mode != "escort":
		var an = kd.anim
		if not (an is Dictionary) or not an.has("idle"):
			errs.append(p + ".anim 必须是对象，至少有 idle")
		else:
			for k in an:
				if not k in E5_ANIM_KEYS:
					errs.append("%s.anim.%s：非随行召唤物只能是 %s" % [p, k, " / ".join(E5_ANIM_KEYS)])
				elif not ctx.get("sprites", {}).has(str(an[k])):
					errs.append("%s.anim.%s「%s」不是本干员 sprites 里的帧条" % [p, k, str(an[k])])
		if kd.has("attack"):
			errs.append(p + "：非随行召唤物写了 anim 就不写 attack（出手用 verb.summon_cmd action: cast 指挥）")
	if kd.has("zone"):
		var z = kd.zone
		if not (z is Dictionary):
			errs.append(p + ".zone 必须是对象 {r, share, mode, look}")
			return
		for k in z:
			if not k in ["r", "share", "mode", "look", "_doc"]:
				errs.append("%s.zone.%s：不认识的字段（只能是 r / share / mode / look）" % [p, k])
		_sm_exprs(z, p + ".zone", ctx)
		_num(z, "r", p + ".zone", ctx, true, 10.0, 600.0)
		_num(z, "share", p + ".zone", ctx, false, 0.0, 1.0)
		if z.has("mode") and not (z.mode is bool):
			errs.append(p + ".zone.mode 只能是 true / false（false = 不算 verb.mode 的 zone_mult）")
		if z.has("look"):
			var lk = z.look
			if not (lk is Dictionary):
				errs.append(p + ".zone.look 必须是对象 {strip, fit, scale, max_scale, tint, ring, fade}")
				return
			for k in lk:
				if not k in E5_LOOK_KEYS:
					errs.append("%s.zone.look.%s：不认识的字段（只能是 %s）" % [p, k, " / ".join(E5_LOOK_KEYS)])
			if lk.has("strip") and not (lk.strip is String and str(lk.strip).begins_with("fx_")):
				errs.append(p + ".zone.look.strip 必须是 fx_* 帧条名（V6_FRAMES 里登记）")
			_num(lk, "fit", p + ".zone.look", ctx, false, 1.0, 512.0)
			_num(lk, "scale", p + ".zone.look", ctx, false, 0.05, 8.0)
			_num(lk, "max_scale", p + ".zone.look", ctx, false, 0.5, 16.0)
			_num(lk, "ring", p + ".zone.look", ctx, false, 0.0, 1.0)
			_num(lk, "fade", p + ".zone.look", ctx, false, 0.0, 5.0)
			if lk.has("tint"):
				var tv = lk.tint
				if not (tv is Array) or tv.size() < 3 or tv.size() > 4 or tv.any(func(x): return not (x is int or x is float)):
					errs.append(p + ".zone.look.tint 必须是 3–4 个数字")


## shape.circle / cone 校验转来：band / among、center summon:<种类> + r: zone
static func _e5_shape(b: Dictionary, p: String, ctx: Dictionary, tag: String) -> void:
	var errs: Array = ctx.errs
	if b.has("band"):
		var bd = b.band
		if tag != "shape.circle" or not (bd is Array) or bd.size() != 2:
			errs.append(p + ".band 必须是 [内, 外]（半径的比例，只用于 shape.circle）")
		else:
			var lo := _val(bd[0], ctx.base)
			var hi := _val(bd[1], ctx.base)
			if lo < 0.0 or hi > 1.0 or lo >= hi:
				errs.append(p + ".band 要满足 0 ≤ 内 < 外 ≤ 1")
	if b.has("among") and (tag != "shape.circle" or str(b.among) != "attack"):
		errs.append(p + ".among 只能是 attack（只打本干员上一次普攻命中的敌人；只用于 shape.circle）")
	if (b.has("band") or b.has("among")) and b.has("only"):
		errs.append(p + "：band / among 不和 only 同用")
	var cn := str(b.get("center", ""))
	if cn.begins_with("summon:") and b.get("r", null) is String and str(b.r) == "zone":
		var kd = ctx.summons.get(cn.substr(7), null) if ctx.summons is Dictionary else null
		if not (kd is Dictionary and kd.has("zone")):
			errs.append(p + "：center: summon:<种类> 配 r: zone 时，这种召唤物要写 zone（召唤物自带区域）")


## fx 条目 grow_to: summon:<种类>：种类要在 blocks.summons 里、且带 zone
static func e5_grow_to_ok(v, ctx: Dictionary) -> bool:
	if not (v is String) or not str(v).begins_with("summon:"):
		return false
	var kd = ctx.summons.get(str(v).substr(7), null) if ctx.get("summons", null) is Dictionary else null
	return kd is Dictionary and kd.has("zone")
