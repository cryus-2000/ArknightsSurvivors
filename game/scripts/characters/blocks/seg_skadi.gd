## 干员积木 · seg_skadi（docs/101 §7.3 B6 ①，10-15：由 op_blocks.gd 按段拆出，内容与注释照搬；继承链与门面见 op_blocks.gd）
extends "res://scripts/characters/blocks/seg_exusiai.gd"


# ---------------------------------------------------------------- shape.wave（斯卡蒂「跃浪」：重斩落点掀起一道向前推进的浪墙）
# 起点 = 本干员脚底 + 上一个形状的方向 × 上一个形状的半径 × along；方向同上一个形状。每帧前进 speed × dt，
# 浪墙（宽 w、厚 depth）扫到的敌人各吃一次 basis × mult（不乘 vs_elite，同手写），非 Boss 沿推进方向击退 kb（精英 ×0.3）；走满 dist 消失。

static func hw_wave_start(o, b: Dictionary) -> void:
	var h := hw_st(o)
	var dmg: float = hw_basis(o, str(b.get("basis", "prev"))) * float(b.get("mult", 1.0))
	if str(b.get("from", "prev")) == "self":   # 精英化第 2 批段：从脚底朝最近敌人放出（涌潮潮刃），fan = 几道的偏角
		if o.pos == Vector2.INF:
			return
		var ang: float = o.facing_angle()
		if str(b.get("aim", "")) == "nearest":
			var ts: Array = o.nearest_enemies(1, float(b.get("aim_r", 260.0)), o.pos)
			if not ts.is_empty():
				ang = (ts[0].pos - o.pos).angle()
		var ov = b.get("off", [0, 0])
		var from0: Vector2 = o.pos + Vector2(float(ov[0]), float(ov[1]))
		if b.has("release_fx"):
			fx_play(o, b.release_fx, o.pos, 30.0, [], ang)
		var shared := {}   # fan_once：同一轮的几道共用命中表，一名敌人每轮只吃一道
		for fd in b.get("fan", [0]):
			var d2 := Vector2.from_angle(ang + deg_to_rad(float(fd)))
			if h.waves.size() >= int(b.get("cap", HW_WAVE_MAX)):
				h.waves.pop_front()
			h.waves.append({"b": b, "pos": from0, "dir": d2, "dist": 0.0, "max": float(b.get("dist", 200.0)), "w": float(b.get("w", 140.0)), "dmg": dmg,
				"hit": shared if b.get("fan_once", false) else {}, "drop": 0.0})
		return
	var dir := Vector2.from_angle(float(h.prev_ang))
	var from: Vector2 = o.pos + dir * float(h.prev_r) * float(b.get("along", 0.45))
	if h.waves.size() >= int(b.get("cap", HW_WAVE_MAX)):
		h.waves.pop_front()
	h.waves.append({"b": b, "pos": from, "dir": dir, "dist": 0.0, "max": float(b.get("dist", 200.0)), "w": float(b.get("w", 140.0)), "dmg": dmg, "hit": {}, "drop": 0.0})


static func _hw_waves(o, dt: float) -> void:
	var g = o.g
	var h: Dictionary = o.hw
	for w in h.waves:
		var b: Dictionary = w.b
		var step: float = float(b.get("speed", 480.0)) * dt
		w.pos += w.dir * step
		w.dist += step
		var nrm: Vector2 = w.dir.orthogonal()
		var depth: float = float(b.get("depth", 18.0))
		for j in o.query_ids(w.pos, w.w * 0.5 + 40.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or w.hit.has(e.id):
				continue
			if not box_centered(w.pos, w.dir, depth, w.w * 0.5, e.pos, e.r):   # B6 ⑤：ob_geom
				continue
			w.hit[e.id] = true
			o.log_hit(str(b.get("src", "")), b.get("tags", []))
			o.deal_damage(e, w.dmg)
			if not e.dead and not e.boss:
				o.apply_kb(e, w.dir * float(b.get("kb", 0.0)) * (0.3 if e.elite else 1.0))
			if b.has("hit_fx"):   # 精英化第 2 批段：潮刃命中的浪花
				fx_play(o, b.hit_fx, e.pos + Vector2(0, -float(e.r) * 0.5), float(e.r), [e], w.dir.angle())
		w.drop -= dt
		if w.drop <= 0.0 and not b.has("proj"):   # 浪尖甩出的水沫（画面，g.vrng；弹体式的潮刃不甩）
			w.drop = 0.03
			var l: float = g.vrng.randf_range(-0.5, 0.5) * w.w
			var mc: Color = _mf_col(b.get("foam", []), Color(0.8, 0.95, 1.0))
			o.fx({"kind": "mote", "pos": w.pos + nrm * l + Vector2(0, -18), "vel": w.dir * 120.0 + Vector2(0, g.vrng.randf_range(-120, -60)), "life": 0.4, "col": mc, "sz": 2.0, "grav": 320.0})
	h.waves = h.waves.filter(func(w): return w.dist < w.max)


## 地面层（data_operator.draw_entities_floor）：浪墙。有帧条（tex，朝右、底部锚点 anchor）时沿浪墙排三朵浪，帧按推进进度走完；缺图画程序浪墙
static func hw_draw_waves(o) -> void:
	if not hw_on(o) or o.hw.waves.is_empty():
		return
	var g = o.g
	var cv = o.cv
	for w in o.hw.waves:
		var b: Dictionary = w.b
		if b.has("proj"):   # 精英化第 2 批段：弹体式（潮刃）——旋转的弹体帧条，缺图画程序新月
			var pn: String = str(b.proj)
			var pa: float = clampf((w.max - w.dist) / 40.0, 0.0, 1.0)
			var pp: Vector2 = w.pos + Vector2(0, -16)
			if g.tex.get(pn) != null and g.V6_FRAMES.has(pn):
				var spec: Array = g.V6_FRAMES[pn]
				fx_frame(cv, g, pn, int(spec[0]), int(float(g.t) * float(spec[1])), pp, g.PX * float(b.get("proj_scale", 1.0)), Color(1, 1, 1, pa), Vector2(-1, -1), w.dir.angle())
			else:
				cv.draw_arc(pp - w.dir * 10.0, w.w * 0.5, w.dir.angle() - 1.0, w.dir.angle() + 1.0, 12, Color(0.6, 0.85, 1.3, 0.9 * pa), 4.0)
			continue
		var tn: String = str(b.get("tex", ""))
		var tx: Texture2D = ArtS.tex(tn) if tn != "" else null
		if tx != null and g.V6_FRAMES.has(tn):
			var nf: int = int(g.V6_FRAMES[tn][0])
			var av = b.get("anchor", [32, 30])
			var anc := Vector2(float(av[0]), float(av[1]))
			var nrm2: Vector2 = w.dir.orthogonal()
			var wf: int = clampi(int(w.dist / w.max * nf), 0, nf - 1)
			var pts: Array = []
			for u in [-0.62, 0.0, 0.62]:
				pts.append(w.pos + nrm2 * u * w.w * 0.5 - w.dir * (u * u) * 16.0)
			pts.sort_custom(func(p1, p2): return p1.y < p2.y)
			for bp in pts:
				o._strip(tx, nf, wf, bp, g.PX, anc, w.dir.x < 0.0)
			continue
		var a: float = clampf((w.max - w.dist) / 60.0, 0.0, 1.0)
		var nrm: Vector2 = w.dir.orthogonal()
		var basel := PackedVector2Array()
		var top := PackedVector2Array()
		var N := 12
		for i in N + 1:
			var u: float = float(i) / N * 2.0 - 1.0
			var bp2: Vector2 = w.pos + nrm * u * w.w * 0.5 - w.dir * (u * u) * 16.0
			var hh: float = 26.0 * (1.0 - u * u) + 4.0 + sin(g.t * 14.0 + i) * 2.0
			basel.append(bp2)
			top.append(bp2 + Vector2(0, -hh))
		var poly: PackedVector2Array = basel.duplicate()
		var rt: PackedVector2Array = top.duplicate()
		rt.reverse()
		poly.append_array(rt)
		cv.draw_colored_polygon(poly, Color(0.25, 0.45, 0.95, 0.45 * a))
		cv.draw_polyline(top, Color(1.4, 1.8, 2.2, 0.9 * a), 3.0)
		cv.draw_polyline(basel, Color(0.5, 0.8, 1.4, 0.5 * a), 2.0)


# ---------------------------------------------------------------- 程序 fx 条目

static func hw_fx_is(f) -> bool:
	if not (f is Dictionary):
		return false
	for k in HW_FX_KINDS:
		if f.has(k):
			return true
	return false


## 一次性程序条目：blade（刀光帧条 + 程序回退 + 水珠）。ctx：c / r / ang
static func hw_fx_spawn(o, f: Dictionary, ctx: Dictionary) -> void:
	if f.has("blade"):
		_hw_blade(o, f.blade, float(ctx.get("r", 0.0)), float(ctx.get("ang", 0.0)))
	elif f.has("slam"):   # 砸地一套（尘土 / 顿帧 / 地裂 / 冲击环 / 水珠 / 火花）：中心 = 形状中心，半径 = 形状半径
		_F()._hw_slam_fx(o, ctx.get("c", o.pos), float(ctx.get("r", 0.0)) * float(f.slam.get("r_mult", 1.0)), float(f.slam.get("k", 1.0)))
	elif f.has("whirl"):   # 锁链带锚甩一整圈（以本干员为心）
		o.ground_dust(o.pos, 48.0, 12)
		o.fx({"kind": "whirl", "pos": o.pos, "r": float(ctx.get("r", 0.0)), "life": float(f.whirl.get("life", 0.32)), "a0": o.g.vrng.randf() * TAU, "dir": float(o.face)})


## 刀光（手写 skadi._slash 的通用版）：strip 帧条，缩放 = r × k ÷ fit（每 1x 像素的世界像素），位置 = 脚底 + (0, y) + 方向 × r × along；
## rot（缺省 true）随出手方向转（mirror 时再转半圈并翻转 = 沿挥砍方向上下翻转）；mirror: face = 朝左时翻；缺图画两道程序弧光（col / edge）。
## motes {n, col, along, y, sz, grav}：沿出手方向甩出的水珠 / 火星（g.vrng）
static func _hw_blade(o, bl: Dictionary, r: float, ang: float) -> void:
	var g = o.g
	if o.pos == Vector2.INF:
		return
	var mirror: bool = false
	var mv = bl.get("mirror", false)
	if mv is bool:
		mirror = mv
	elif str(mv) == "face":
		mirror = float(o.face) < 0.0
	var nm: String = str(bl.get("strip", "fx_slash_arc_deep"))
	if bl.has("r"):   # 半径另给（技能发动时没有形状半径）
		r = float(bl.r)
	var sc: float = r * float(bl.get("k", 1.15)) / float(bl.get("fit", 40.0))
	var dir := Vector2.from_angle(ang)
	var at: Vector2 = o.pos + Vector2(0, float(bl.get("y", -14.0))) + dir * r * float(bl.get("along", 0.5))
	var rot: bool = bl.get("rot", true)
	var sa: float = (ang + (PI if mirror else 0.0)) if rot else 0.0
	var tint: Color = _mf_col(bl.get("tint", []), Color(0.72, 0.86, 1.05, 0.88))
	if not o.spawn_fx_sprite(nm, at, sc, sa, mirror, false, tint):
		var half: float = float(bl.get("half", 1.4))
		var life: float = float(bl.get("life", 0.22))
		o.slash_fx(o.pos + Vector2(0, -14), ang, half, r, _mf_col(bl.get("col", []), o.col()), "slash", life)
		o.slash_fx(o.pos + Vector2(0, -14), ang, half * 0.9, r * 0.9, _mf_col(bl.get("edge", []), Color(0.8, 0.95, 1.0)), "slash", life * 0.7)
	var mo = bl.get("motes", null)
	if mo is Dictionary:
		var sp: Vector2 = o.pos + Vector2(0, float(mo.get("y", -10.0))) + dir * r * float(mo.get("along", 0.6))
		var mc: Color = _mf_col(mo.get("col", []), Color(0.6, 0.9, 1.0))
		for k in int(mo.get("n", 5)):
			o.fx({"kind": "mote", "pos": sp + Vector2(g.vrng.randf_range(-12, 12), g.vrng.randf_range(-8, 8)), "vel": Vector2.from_angle(ang + g.vrng.randf_range(-0.8, 0.8)) * g.vrng.randf_range(40, 110) + Vector2(0, -60),
				"life": float(mo.get("life", 0.4)), "col": mc, "sz": float(mo.get("sz", 2.0)), "grav": float(mo.get("grav", 260.0))})


## 常驻程序圈（aura_ring：挂在常驻积木上，生效期间在 at 画一圈地面椭圆）：r = attack（当前普攻半径）/ 数字；col、a（透明度）、w（线宽）、
## pulse（呼吸幅度）、hz（呼吸频率）、fill（实心底透明度）、sy（压扁，缺省 0.55）。draw_auras 调
static func hw_draw_rings(o) -> void:
	if o.pos == Vector2.INF:
		return
	var g = o.g
	for u in o._fxb:
		var e: Dictionary = o._fxb[u]
		for f in e.b.get("fx", _EA):
			if not (f is Dictionary) or not f.has("aura_ring") or not fx_on(o, f):
				continue
			var rv: Dictionary = f.aura_ring
			var r: float
			if str(rv.get("r", "attack")) == "attack":
				r = shape_radius(o, o.cur_attack())
			else:
				r = float(rv.r)
			var c: Vector2 = g.ppos if str(f.get("at", "self")) == "leader" else o.pos
			var ov = f.get("off", [0, 4])
			c += Vector2(float(ov[0]), float(ov[1])) if ov is Array and ov.size() == 2 else Vector2.ZERO
			var al: float = fx_hold_alpha(f, e)
			var col: Color = _mf_col(rv.get("col", []), o.col())
			var hz: float = float(rv.get("hz", 5.0))
			var pul: float = float(rv.get("pulse", 0.1)) * sin(g.t * hz)
			o.cv.draw_set_transform(c, 0.0, Vector2(1.0, float(rv.get("sy", 0.55))))
			if float(rv.get("fill", 0.0)) > 0.0:
				o.cv.draw_circle(Vector2.ZERO, r, Color(col.r, col.g, col.b, (float(rv.fill) + pul * 0.5) * al))
			o.cv.draw_arc(Vector2.ZERO, r, 0.0, TAU, 36, Color(col.r, col.g, col.b, (float(rv.get("a", 0.3)) + pul) * al), float(rv.get("w", 2.0)))
			o.cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---------------------------------------------------------------- 本段的校验

## blocks 顶层：follow / hit_fx / look
static func _hw_top(blocks: Dictionary, ctx: Dictionary) -> void:
	var errs: Array = ctx.errs
	if blocks.has("follow"):
		var fw = blocks.follow
		if not (fw is Dictionary):
			errs.append("blocks.follow 必须是对象 {leash, gap}")
		else:
			if fw.has("side"):   # 第 4 批：护卫站位（队长朝向一侧的固定偏移，不前压）
				if not (fw.side is Array and fw.side.size() == 2):
					errs.append("blocks.follow.side 必须是 [x, y]")
			else:
				_num(fw, "leash", "blocks.follow", ctx, true, 20.0, 800.0)
				_num(fw, "gap", "blocks.follow", ctx, true, 0.0, 200.0)
	if blocks.has("hit_fx"):
		_fx(blocks.hit_fx, "blocks.hit_fx", ctx, "shape.circle")
	if blocks.has("look"):
		_fx(blocks.look, "blocks.look", ctx, "verb.buff_self")


## blocks.attack 的追加字段
static func _hw_attack(atk: Dictionary, ctx: Dictionary) -> void:
	var errs: Array = ctx.errs
	_num(atk, "first", "blocks.attack", ctx, false, 0.0, 30.0)
	_num(atk, "idle", "blocks.attack", ctx, false, 0.0, 5.0)
	if atk.has("combo"):
		var cb = atk.combo
		if not (cb is Array) or cb.is_empty() or cb.size() > 6:
			errs.append("blocks.attack.combo 必须是 1–6 段的数组")
		else:
			for i in cb.size():
				var q := "blocks.attack.combo[%d]" % i
				var st = cb[i]
				if not (st is Dictionary):
					errs.append(q + " 必须是对象 {cond, delay, do}")
					continue
				for k in st:
					if not k in ["cond", "delay", "do", "_doc"]:
						errs.append("%s.%s：连斩一段只有 cond / delay / do" % [q, k])
				if st.has("cond") and (not (st.cond is String) or parse_cond(st.cond, ctx.base).has("err")):
					errs.append(q + ".cond 看不懂")
				_num(st, "delay", q, ctx, true, 0.0, 3.0)
				_list(st.get("do", []), q + ".do", "instant", ctx)


## shape.circle / cone 的追加参数
static func _hw_shape_params(b: Dictionary, p: String, ctx: Dictionary, tag: String) -> void:
	var errs: Array = ctx.errs
	if b.has("basis") and not str(b.basis) in ["attack", "prev", "hit", "atk"]:
		errs.append(p + ".basis 只能是 attack / prev / hit / atk")
	if b.has("basis") and (b.has("power") or b.has("atk_key")):
		errs.append(p + "：写了 basis（按已算好的伤害取百分比）就不写 power / atk_key")
	_num(b, "r_mult", p, ctx, false, 0.05, 10.0)
	_num(b, "aim_pad", p, ctx, false, 0.0, 400.0)
	_num(b, "aim_r", p, ctx, false, 1.0, 2000.0)
	_num(b, "aim_mult", p, ctx, false, 0.05, 10.0)
	if b.has("aim_mult") and not b.has("aim_r"):
		errs.append(p + ".aim_mult 要配 aim_r")
	if b.has("origin_off") and not (b.origin_off is Array and b.origin_off.size() == 2):
		errs.append(p + ".origin_off 必须是 [x, y]")
	if b.has("face") and not (b.face is bool or (b.face is String and not parse_cond(b.face, ctx.base).has("err"))):
		errs.append(p + ".face 只能是 true / false 或条件串")
	if b.has("dir") and not str(b.dir) in ["back", "face", "target"]:   # face / target：召唤物扩展段（随行召唤物的爪击方向）
		errs.append(p + ".dir 只能是 back（本次普攻的反方向）/ face / target")
	if b.has("dir") and tag != "shape.cone":
		errs.append(p + ".dir 只用于 shape.cone")
	if b.has("ring") and not (b.ring is bool):
		errs.append(p + ".ring 只能是 true / false")
	if b.has("anim") and not (ctx.sprites is Dictionary and ctx.sprites.has(str(b.anim))):
		errs.append("%s.anim「%s」不是 sprites 里的帧条键" % [p, str(b.anim)])
	if b.has("turn") and not (b.turn is bool):
		errs.append(p + ".turn 只能是 true / false")


## _block 转来：本段的积木
static func _hw_block(b: Dictionary, p: String, kind: String, ctx: Dictionary, tag: String) -> bool:
	if tag in H3_TAGS:   # 手写迁移段第 3 批
		return _h3_block(b, p, kind, ctx, tag)
	if tag in H4_TAGS:   # 手写迁移段第 4 批
		return _h4_block(b, p, kind, ctx, tag)
	if tag in E3_TAGS:   # 精英化第 3 批
		return _e3_block(b, p, kind, ctx, tag)
	if tag in HW2_TAGS:
		return _F()._hw2_block(b, p, kind, ctx, tag)
	if tag in HW3_TAGS:
		return _F()._hw3_block(b, p, kind, ctx, tag)
	if tag in HW4_TAGS:
		return _F()._hw4_block(b, p, kind, ctx, tag)
	if tag in HW5_TAGS:   # 精英化第 2 批段
		return _hw5_block(b, p, kind, ctx, tag)
	if not tag in HW_TAGS:
		return false
	var errs: Array = ctx.errs
	var where_ok := {
		"shape.wave": ["skill", "instant"],
		"trig.on_combo_end": ["trig"],
	}
	if not kind in where_ok.get(tag, []):
		errs.append("%s：「%s」不能放在这里（%s；只能在 %s）" % [p, tag, kind, " / ".join(where_ok.get(tag, []))])
		return true
	match tag:
		"shape.wave":
			_num(b, "dist", p, ctx, true, 10.0, 800.0)
			_num(b, "w", p, ctx, true, 4.0, 400.0)
			_num(b, "speed", p, ctx, true, 10.0, 2000.0)
			_num(b, "mult", p, ctx, true, 0.0, 20.0)
			_num(b, "kb", p, ctx, false, 0.0, 2000.0)
			_num(b, "along", p, ctx, false, -2.0, 2.0)
			_num(b, "depth", p, ctx, false, 1.0, 100.0)
			_num(b, "cap", p, ctx, false, 1.0, 16.0)
			_num(b, "aim_r", p, ctx, false, 1.0, 1000.0)
			if b.has("from") and not str(b.from) in ["prev", "self"]:
				errs.append(p + ".from 只能是 prev / self")
			if b.has("fan") and (not (b.fan is Array) or b.fan.is_empty() or b.fan.size() > 8):
				errs.append(p + ".fan 必须是 1–8 个偏角（度）的数组")
			if b.has("proj") and not str(b.proj).begins_with("proj_"):
				errs.append(p + ".proj 必须是 proj_* 帧条名")
			for k in ["hit_fx", "release_fx"]:
				if b.has(k):
					_fx(b[k], p + "." + k, ctx, "shape.circle")
			if b.has("basis") and not str(b.basis) in ["attack", "prev", "hit", "atk"]:
				errs.append(p + ".basis 只能是 attack / prev / hit / atk")
			if b.has("tex") and not str(b.tex).begins_with("fx_"):
				errs.append(p + ".tex 必须是 fx_* 帧条名")
			_src(b, p, ctx, true)
		"trig.on_combo_end":
			_list(b.get("do", []), p + ".do", "instant", ctx)
	return true


## fx 程序条目（_fx 转来）：返回 true = 已校验
static func _hw_fx_check(f: Dictionary, q: String, ctx: Dictionary, owner: String) -> bool:
	if not hw_fx_is(f):
		return false
	var errs: Array = ctx.errs
	var kinds: Array = HW_FX_KINDS.filter(func(k): return f.has(k))
	if kinds.size() != 1:
		errs.append("%s：程序 fx 条目恰好写一种（%s）" % [q, " / ".join(HW_FX_KINDS)])
		return true
	var kk: String = kinds[0]
	for k in f:
		if k != kk and not k in HW_FX_COMMON:
			errs.append("%s.%s：程序 fx 条目不认识的字段" % [q, k])
	if not (f[kk] is Dictionary):
		errs.append("%s.%s 必须是对象" % [q, kk])
		return true
	if kk in ["aura_ring", "outline"] and owner in FX_INSTANT_OWNERS:
		errs.append("%s.%s 是常驻画面，只能挂在常驻积木上" % [q, kk])
	if f.has("cond") and (not (f.cond is String) or parse_cond(f.cond, ctx.base).has("err")):
		errs.append(q + ".cond 看不懂")
	if kk == "blade":
		var sn: String = str(f.blade.get("strip", "fx_slash_arc_deep"))
		if not sn.begins_with("fx_"):
			errs.append(q + ".blade.strip 必须是 fx_* 帧条名")
	return true
