## 干员积木 · seg_skadi（docs/101 §7.3 B6 ①，10-15：由 op_blocks.gd 按段拆出，内容与注释照搬；继承链与门面见 op_blocks.gd）
extends "res://scripts/characters/blocks/seg_exusiai.gd"

const SwordEase = preload("res://scripts/characters/blocks/sword_ease.gd")   # 剑气非线性速度（10-27）
const BalS = preload("res://scripts/core/balance.gd")   # pixelfx 不加限制试验的开关 fx/px_unleashed（块脚本里不直接用 Bal 单例）


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
		var ll_tgt: Dictionary = {}   # docs/202 拉普兰德「追猎」：aim: low_hp 挑出的目标（给 ll_wave_post 记追踪）
		if o.held_aim() and o.get("in_release") == true and o.atk_aim != Vector2.ZERO:
			ang = o.atk_aim.angle()   # 按住瞄准（10-23 用户定）：普攻里放出的剑气 / 潮刃沿玩家指向，不吸附最近敌人；技能里的照旧找最近
		elif str(b.get("aim", "")) == "nearest":
			var ts: Array = o.nearest_enemies(1, float(b.get("aim_r", 260.0)), o.pos)
			if not ts.is_empty():
				ang = (ts[0].pos - o.pos).angle()
		elif str(b.get("aim", "")) == "low_hp":
			ll_tgt = _F().ll_pick_low(o, float(b.get("aim_r", 260.0)))
			if not ll_tgt.is_empty():
				ang = (ll_tgt.pos - o.pos).angle()
		var ov = b.get("off", [0, 0])
		var from0: Vector2 = o.pos + Vector2(float(ov[0]), float(ov[1]))
		if b.has("release_fx"):
			fx_play(o, b.release_fx, o.pos, 30.0, [], ang)
		# 首轮仍播完技能起手；每轮仅写纯画面事件。
		if b.has("release_pose"):
			var r: Dictionary = b.release_pose
			if o.sq_ph == 2 and o.sq_i == int(r.skill) and o.skill_active_left(int(r.skill)) > 0.0 and not (o.act_kind == "skill" and o.attack_t > 0.0):
				o.native_motion["wave_pose"] = {"slot": str(r.slot), "skill": int(r.skill), "cycle": float(r.cycle), "elapsed": 0.0, "angle": ang}
		var shared := {}   # fan_once：同一轮的几道共用命中表，一名敌人每轮只吃一道
		for fd in b.get("fan", [0]):
			var d2 := Vector2.from_angle(ang + deg_to_rad(float(fd)))
			if h.waves.size() >= int(b.get("cap", HW_WAVE_MAX)):
				h.waves.pop_front()
			h.waves.append(_wave_ease({"b": b, "pos": from0, "dir": d2, "dist": 0.0, "max": float(b.get("dist", 200.0)), "w": float(b.get("w", 140.0)), "dmg": dmg,
				"hit": shared if b.get("fan_once", false) else {}, "drop": 0.0}, o, b))
			px_ul_wave(o, b, h.waves[h.waves.size() - 1], from0, d2)
			if b.has("ll"):   # docs/202 拉普兰德成长节点（追猎 / 日晷·反斩）：seg_lappland
				_F().ll_wave_post(o, h.waves[h.waves.size() - 1], b, ll_tgt)
		return
	var dir := Vector2.from_angle(float(h.prev_ang))
	var from: Vector2 = o.pos + dir * float(h.prev_r) * float(b.get("along", 0.45))
	if h.waves.size() >= int(b.get("cap", HW_WAVE_MAX)):
		h.waves.pop_front()
	h.waves.append(_wave_ease({"b": b, "pos": from, "dir": dir, "dist": 0.0, "max": float(b.get("dist", 200.0)), "w": float(b.get("w", 140.0)), "dmg": dmg, "hit": {}, "drop": 0.0}, o, b))
	px_ul_wave(o, b, h.waves[h.waves.size() - 1], from, dir)


## pixelfx 放开版刀波（docs/242 §14.8，注册表 data/px_ul.json 的 "waves": {src: {…}}；原型拉普兰德 S2 狼魂剑气，11-04 收进样板）。三种写法可以组合：
##   base {base, variants, y, dist}：整段飞行（判定的飞行距离 dist）烤进帧条、原点 = 出手点，开播时沿方向放一次画完全程（成长把距离改长时按比例拉）；
##   proj {base}：弹体式（单体命中 / 追踪的远掷、双生刃）——弹体帧条换成放开版（keep 等宽 4 帧，飞行停第 1 帧、消散放 2–3 帧，同 proj_hold 口径），先画装饰层；
##   hit {base, y, sc}：刀波每命中一名敌人在它身上放一张命中帧条（不另定格）。
## 三项都缺（或缺图）时不接管。开关 fx/px_unleashed 关掉时注册表为空。只改画面，判定照旧走 w
static func px_ul_wave(o, b: Dictionary, w: Dictionary, from: Vector2, d: Vector2) -> void:
	var ent = o.g.vfx.px_ul_reg(str(o.id)).get("waves", _ED).get(str(b.get("src", "")))
	if not (ent is Dictionary):
		return
	var vx = o.g.vfx
	var el: int = vx.px_ul_el(o)
	var tm: bool = not o.is_leader
	var nv: int = int(ent.get("variants", 1))
	var vv: int = 1 + int(o.g.vrng.randf() * nv) if o.is_leader and nv >= 2 else 1
	var pj = ent.get("proj")
	if pj is Dictionary and o.g.tex.get(vx.px_ul_tex(str(pj.get("base", "")), 1, tm, "core", el)) != null:
		w["pxp"] = vx.px_ul_tex(str(pj.base), 1, tm, "core", el)
		w["pxpd"] = vx.px_ul_tex(str(pj.base), 1, tm, "deco", el)
	var ht = ent.get("hit")
	if ht is Dictionary and str(ht.get("base", "")) != "":
		w["pxh"] = ht
	if not ent.has("base"):
		return
	var base: String = str(ent.base)
	var cn: String = vx.px_ul_tex(base, vv, tm, "core", el)
	if o.g.tex.get(cn) == null:
		return
	w["px"] = true
	var p: Vector2 = from + Vector2(0, float(ent.get("y", 0.0)))
	var sc: float = o.g.PX * float(w.max) / float(ent.get("dist", w.max))
	var dn: String = vx.px_ul_tex(base, vv, tm, "deco", el)
	var dk: float = vx.px_deco_k(o)
	if dn != "" and dk > 0.0:
		o.spawn_fx_sprite(dn, p, sc, d.angle(), false, false, Color(1, 1, 1, dk))
	o.spawn_fx_sprite(cn, p, sc, d.angle())


## 剑气非线性速度（sword_ease.gd）：弹体式刀波（有 proj）缺省开，浪墙写了 "ease" 才开；ez 为空 = 改前匀速
static func _wave_ease(w: Dictionary, o, b: Dictionary) -> Dictionary:
	var ez: Dictionary = SwordEase.cfg(str(o.id), b, b.has("proj"))
	if not ez.is_empty():
		w.ez = ez
		w.p0 = w.pos
		w.t = 0.0
		w.T = float(w.max) / maxf(float(b.get("speed", 480.0)), 1.0)
		w.paused = false
	return w


static func _hw_waves(o, dt: float) -> void:
	var g = o.g
	var h: Dictionary = o.hw
	for w in h.waves:
		var b: Dictionary = w.b
		if w.has("ll"):   # docs/202 拉普兰德：追踪转向 / 大剑气的紫色边（seg_lappland）
			_F().ll_wave_tick(o, w, dt)
		var step: float
		var hc: Vector2 = w.pos   # 判定盒中心 / 半长：匀速照旧取这一帧的位置；非线性扫过上一帧 → 这一帧整段
		var depth: float = float(b.get("depth", 18.0))
		var hl: float = depth
		if w.has("ez"):
			w.t += dt
			var nd: float = w.max * SwordEase.prog(w.ez, w.t / w.T)
			step = nd - w.dist
			w.pos = w.p0 + w.dir * nd
			w.dist = nd if w.t < w.T else w.max
			hc = w.pos - w.dir * step * 0.5
			hl = depth + step * 0.5
		else:
			step = float(b.get("speed", 480.0)) * dt
			w.pos += w.dir * step
			w.dist += step
			hc = w.pos
		var nrm: Vector2 = w.dir.orthogonal()
		for j in o.query_ids(hc, w.w * 0.5 + 40.0 + (hl - depth)):
			var e: Dictionary = g.enemies[j]
			if e.dead or w.hit.has(e.id):
				continue
			if not box_centered(hc, w.dir, hl, w.w * 0.5, e.pos, e.r):   # B6 ⑤：ob_geom
				continue
			if w.has("ez") and not w.paused and float(w.ez.pause) > 0.0 and SwordEase.fast(w.ez, w.t / w.T) > 0.3:   # 出手猛冲段的头一下命中：极短顿帧（vfx.impact_pause 共享限频）
				w.paused = true
				o.impact_pause(float(w.ez.pause))
			var pm: float = o.atk_pierce_mult(w.hit.size()) if b.has("max_hits") else 1.0   # 穿甲弹：普攻剑气每穿过一名 −15%（10-23）
			w.hit[e.id] = true
			o.log_hit(str(b.get("src", "")), b.get("tags", []))
			o.deal_damage(e, w.dmg * pm)
			if not e.dead and not e.boss:
				o.apply_kb(e, w.dir * float(b.get("kb", 0.0)) * (0.3 if e.elite else 1.0))
			if w.has("pxh"):   # pixelfx 放开版刀波命中帧条（px_ul_wave）
				var ph: Dictionary = w.pxh
				g.vfx._px_ul_at(str(ph.base), e.pos + Vector2(0, float(ph.get("y", -float(e.r) * 0.5))), g.PX * float(ph.get("sc", 1.0)), not o.is_leader, g.vfx.px_ul_el(o), g.vfx.px_deco_k(o))
			if b.has("hit_fx"):   # 精英化第 2 批段：潮刃命中的浪花
				fx_play(o, b.hit_fx, e.pos + Vector2(0, -float(e.r) * 0.5), float(e.r), [e], w.dir.angle())
			if b.has("max_hits") and w.hit.size() >= o.atk_pierce(int(b.max_hits)):   # 10-23 用户定：远程普攻取消穿透——命中 max_hits 名即消失（缺省不限）；贯穿卡 / 穿甲弹加在上面
				w.dist = w.max
				break
		w.drop -= dt
		if w.drop <= 0.0 and not b.has("proj"):   # 浪尖甩出的水沫（画面，g.vrng；弹体式的潮刃不甩）
			w.drop = 0.03
			var l: float = g.vrng.randf_range(-0.5, 0.5) * w.w
			var mc: Color = _mf_col(b.get("foam", []), Color(0.8, 0.95, 1.0))
			o.fx({"kind": "mote", "pos": w.pos + nrm * l + Vector2(0, -18), "vel": w.dir * 120.0 + Vector2(0, g.vrng.randf_range(-120, -60)), "life": 0.4, "col": mc, "sz": 2.0, "grav": 320.0})
		var pjn: String = str(w.get("pxp", b.get("proj", "")))   # 放开版弹体（px_ul_wave proj）替换 b.proj
		if w.dist >= w.max and b.has("proj_hold") and g.tex.get(pjn) != null and g.V6_FRAMES.has(pjn) and not w.get("px", false):
			# 消散只进粒子表，不延长碰撞寿命。放开版先放装饰层
			for pl in ([str(w.pxpd), pjn] if w.has("pxp") and str(w.get("pxpd", "")) != "" and g.V6_FRAMES.has(str(w.pxpd)) and g.vfx.px_deco_k(o) > 0.0 else [pjn]):
				var spec: Array = g.V6_FRAMES[pl]
				o.fx({"kind": "strip", "name": pl, "pos": w.pos + Vector2(0, -16),
					"life": 2.0 / float(spec[1]), "fr": int(spec[0]), "first_frame": 2, "fps": float(spec[1]),
					"loop": false, "ph": 0, "sc": g.PX * float(b.get("proj_scale", 1.0)), "col": Color(1, 1, 1, g.vfx.px_deco_k(o)) if pl != pjn else Color.WHITE,
					"anc": Vector2(-1, -1), "ang": w.dir.angle(), "floor": not b.get("proj_front", false)})
	h.waves = h.waves.filter(func(w): return w.dist < w.max)


## 地面层（data_operator.draw_entities_floor）：浪墙。有帧条（tex，朝右、底部锚点 anchor）时沿浪墙排三朵浪，帧按推进进度走完；缺图画程序浪墙
static func hw_draw_waves(o, front := false) -> void:
	if not hw_on(o) or o.hw.waves.is_empty():
		return
	var g = o.g
	var cv = o.cv
	for w in o.hw.waves:
		var b: Dictionary = w.b
		if bool(b.get("proj_front", false)) != front: continue
		if w.get("px", false):   # pixelfx 放开版接管了这道刀波的画面（px_ul_wave：飞行烤进帧条，开播时整条放出），这里不再画弹体
			continue
		if b.has("proj"):   # 精英化第 2 批段：弹体式（潮刃）——旋转的弹体帧条，缺图画程序新月
			var pn: String = str(w.get("pxp", b.proj))   # 放开版弹体（px_ul_wave proj）
			var pdn: String = str(w.get("pxpd", "")) if w.has("pxp") and g.vfx.px_deco_k(o) > 0.0 else ""
			var pa: float = 1.0 if b.has("proj_hold") else clampf((w.max - w.dist) / 40.0, 0.0, 1.0)
			var pp: Vector2 = w.pos + Vector2(0, -16)
			if g.tex.get(pn) != null and g.V6_FRAMES.has(pn):
				var spec: Array = g.V6_FRAMES[pn]
				var frame := int(float(g.t) * float(spec[1]))
				if b.has("proj_hold"):
					frame = mini(int((w.t if w.has("ez") else w.dist / float(b.speed)) * float(spec[1])), int(b.proj_hold))
				var psc: float = g.PX * float(b.get("proj_scale", 1.0))
				if w.has("ez"):   # 力量感：猛冲段拉长、提亮、拖两道残影（残影间距跟速度走），滑行段变短变暗
					var u: float = w.t / w.T
					var f: float = SwordEase.fast(w.ez, u)
					var fa: float = SwordEase.fade(w.ez, u)
					var br: float = (1.0 + float(w.ez.bright) * f) * fa   # 滑行段压暗颜色、不压透明度（飞行中不淡出，docs/122 定的播放口径）
					var gap: float = w.max / w.T * SwordEase.vel_mul(w.ez, u) * 0.022
					for gi in range(int(w.ez.ghost), 0, -1):
						if f > 0.05:
							fx_frame(cv, g, pn, int(spec[0]), frame, pp - w.dir * gap * gi, psc, Color(br, br, br, pa * f * 0.38 / gi), Vector2(-1, -1), w.dir.angle(), 1.0 + float(w.ez.stretch) * f)
					if pdn != "" and g.tex.get(pdn) != null and g.V6_FRAMES.has(pdn):
						fx_frame(cv, g, pdn, int(g.V6_FRAMES[pdn][0]), frame, pp, psc, Color(br, br, br, pa * g.vfx.px_deco_k(o)), Vector2(-1, -1), w.dir.angle(), 1.0 + float(w.ez.stretch) * f - 0.12 * (1.0 - fa) / 0.45)
					fx_frame(cv, g, pn, int(spec[0]), frame, pp, psc, Color(br, br, br, pa), Vector2(-1, -1), w.dir.angle(), 1.0 + float(w.ez.stretch) * f - 0.12 * (1.0 - fa) / 0.45)
				else:
					if pdn != "" and g.tex.get(pdn) != null and g.V6_FRAMES.has(pdn):
						fx_frame(cv, g, pdn, int(g.V6_FRAMES[pdn][0]), frame, pp, psc, Color(1, 1, 1, pa * g.vfx.px_deco_k(o)), Vector2(-1, -1), w.dir.angle())
					fx_frame(cv, g, pn, int(spec[0]), frame, pp, psc, Color(1, 1, 1, pa), Vector2(-1, -1), w.dir.angle())
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


## pixelfx 放开版接管（docs/242，balance fx/px_unleashed，缺省 0；漏项 #25）：ob_core 的 circle / cone 判定结算后调这里，按 o.id 查注册表
## data/px_ul.json（vfx.px_ul_reg），src 登记过的这一下画面整个换成 fx_<人>_ul_* 帧条（源码 tools/pixelfx_fx），招式本体 fx 条目和通用近战刀光不画；
## 先画装饰（透明度 × px_deco_k）后画核心；队长命中时走 impact_pause 共享顿帧（纯画面：批跑不消耗顿帧、只用 g.vrng，伤害 / TRACE 不变）。
## c = 圆形判定的圆心（cone 传 INF，按脚底 + 方向画）。返回 true = 已接管，ob_core 只再播 relic: / node: 附加条目
static var _px_alt_c := {}


static func _px_alt_cond(o, s: String) -> Dictionary:
	var k: String = "%s|%s" % [str(o.id), s]
	if not _px_alt_c.has(k):
		_px_alt_c[k] = parse_cond(s, o.def.get("base", {}) if o.get("def") is Dictionary else {}) if s != "" else {}
	return _px_alt_c[k]


## 召唤物接管（docs/242 §14.11，格式照凯尔希 11-04 提案）：注册表 "summons": {"<召唤物 kind>": {攻击字段…, "aura": {…}, "lunge": {…}, "leap": {…}}}；
## part = "" 取攻击（条目本身），否则取子条目
static func px_ul_sm(o, kind: String, part: String):
	var sm = o.g.vfx.px_ul_reg(str(o.id)).get("summons", _ED).get(kind)
	if not (sm is Dictionary):
		return null
	return sm if part == "" else sm.get(part)


## 召唤物的一下（攻击 / 扑击落地 / 跃回落地共用）：ent {base, variants, draw {fit, k, y, along}, skill {"<技能序号>": {base, variants} 或 base}, rot, mirror}，
## 技能开着时换 skill 里那条（凯尔希 S3 熔毁爪）；缩放 = r × k ÷ fit（写了 fit）或 PX × sc；位置 = p + (0, y) + 方向 × r × along；
## rot（缺省 true）= 帧条正右对准方向（原点 = 判定原点）；mirror: true 时朝左再转半圈并翻转（上下不颠倒的帧条用）。先装饰后核心，不定格。返回 true = 已画
static func px_ul_sm_draw(o, ent: Dictionary, p: Vector2, ang: float, r: float) -> bool:
	var g = o.g
	var use: Dictionary = ent
	var sk = ent.get("skill")
	if sk is Dictionary:
		for k in sk:
			if o.skill_on(int(k)):
				use = sk[k] if sk[k] is Dictionary else {"base": str(sk[k])}
				break
	var base: String = str(use.get("base", ""))
	var nv: int = int(use.get("variants", 1))
	var vv: int = 1 + int(g.vrng.randf() * nv) if o.is_leader and nv >= 2 else 1
	var el: int = g.vfx.px_ul_el(o)
	var tm: bool = not o.is_leader
	var cn: String = g.vfx.px_ul_tex(base, vv, tm, "core", el)
	if base == "" or g.tex.get(cn) == null:
		return false
	var dw: Dictionary = ent.get("draw", ent)
	var fit: float = float(dw.get("fit", 0.0))
	var sc: float = r * float(dw.get("k", 1.0)) / fit if fit > 0.0 and r > 0.0 else g.PX * float(dw.get("sc", 1.0))
	var at: Vector2 = p + Vector2(0, float(dw.get("y", 0.0))) + Vector2.from_angle(ang) * r * float(dw.get("along", 0.0))
	var mirror: bool = ent.get("mirror", false) and cos(ang) < 0.0
	var sa: float = (ang + (PI if mirror else 0.0)) if ent.get("rot", true) else 0.0
	var fl: bool = mirror
	var dn: String = g.vfx.px_ul_tex(base, vv, tm, "deco", el)
	var dk: float = g.vfx.px_deco_k(o)
	if dn != "" and dk > 0.0:
		o.spawn_fx_sprite(dn, at, sc, sa, fl, false, Color(1, 1, 1, dk))
	o.spawn_fx_sprite(cn, at, sc, sa, fl)
	return true


## 召唤物技能常驻（注册表 summon[kind].aura = {"<技能序号>": {base, y, sc, back}}）：技能开着时在召唤物身上循环播；mf_draw 在本体前后各调一次
static func px_ul_sm_aura(o, s: Dictionary, hov: float, front: bool) -> void:
	var au = px_ul_sm(o, str(s.kind), "aura")
	if not (au is Dictionary):
		return
	var g = o.g
	for k in au:
		var e = au[k]
		if not (e is Dictionary) or bool(e.get("back", false)) == front or not o.skill_on(int(k)):
			continue
		var p: Vector2 = s.pos + Vector2(0, hov + float(e.get("y", 0.0)))
		var dk: float = g.vfx.px_deco_k(o)
		for ly in ["deco", "core"]:
			var nm: String = g.vfx.px_ul_tex(str(e.get("base", "")), 1, not o.is_leader, ly, g.vfx.px_ul_el(o))
			if nm == "" or g.tex.get(nm) == null or not g.V6_FRAMES.has(nm) or (ly == "deco" and dk <= 0.0):
				continue
			var spec: Array = g.V6_FRAMES[nm]
			fx_frame(o.cv, g, nm, int(spec[0]), int(float(g.t) * float(spec[1])), p, g.PX * float(e.get("sc", 1.0)), Color(1, 1, 1, dk if ly == "deco" else 1.0))


## 敌人身上的常驻状态附件（docs/242 §14.18，§11.2 #6）：注册表 "status": {"<状态>": {base, stack: [b1, b2, …], at: head / foot / side, y, sc}}；
## 状态：seal（本人施加的封印）/ mark（本人 verb.mark 的层数，stack 按层数取）/ slow / stun / 其他写 key（敌人字段 > 0，time: true 时 > 当前时刻）。
## 尺寸 = e.r ÷ 12 夹 0.8–2.0（× sc）；同屏最多 30 个（离队长近的优先）；全部算装饰层（透明度 × px_deco_k）。返回本人接管了的状态名（旧画法据此跳过）
const PX_STATUS_MAX := 30


static func px_ul_status_draw(o) -> Dictionary:
	var st = o.g.vfx.px_ul_reg(str(o.id)).get("status")
	if not (st is Dictionary) or st.is_empty() or o.pos == Vector2.INF:
		return {}
	var g = o.g
	var dk: float = g.vfx.px_deco_k(o)
	var cov := {}
	for k in st:
		cov[k] = true
	if dk <= 0.0:
		return cov
	var marks: Dictionary = o.sm.get("marks", {}) if o.get("sm") is Dictionary else {}
	var cand: Array = []
	for e in g.enemies:
		if e.dead or e.get("friendly", false):
			continue
		for k in st:
			var ent = st[k]
			if not (ent is Dictionary):
				continue
			var n: int = 0
			match str(k):
				"seal":
					n = 1 if float(e.get("seal_t", 0.0)) > g.t and str(e.get("seal_by", "")) == str(o.id) else 0
				"mark":
					n = int(marks[int(e.id)].n) if marks.has(int(e.id)) else 0
				"slow":
					n = 1 if float(e.get("slow", 0.0)) > 0.0 else 0
				"stun":
					n = 1 if float(e.get("stun", 0.0)) > 0.0 else 0
				_:
					var kk: String = str(ent.get("key", ""))
					n = 1 if kk != "" and float(e.get(kk, 0.0)) > (g.t if ent.get("time", false) else 0.0) else 0
			if n > 0:
				cand.append([e.pos.distance_squared_to(g.ppos), e, ent, n])
	if cand.size() > PX_STATUS_MAX:
		cand.sort_custom(func(a, b): return a[0] < b[0])
		cand.resize(PX_STATUS_MAX)
	var tm: bool = not o.is_leader
	var el: int = g.vfx.px_ul_el(o)
	for c in cand:
		var e: Dictionary = c[1]
		var ent: Dictionary = c[2]
		var stk = ent.get("stack")
		var base: String = str(stk[clampi(int(c[3]) - 1, 0, stk.size() - 1)]) if stk is Array and not stk.is_empty() else str(ent.get("base", ""))
		var nm: String = g.vfx.px_ul_tex(base, 1, tm, "core", el)
		if g.tex.get(nm) == null or not g.V6_FRAMES.has(nm):
			continue
		var er: float = float(e.r)
		var p: Vector2 = e.pos + Vector2(0, float(ent.get("y", 0.0)))
		match str(ent.get("at", "head")):
			"head":
				p += Vector2(0, -er * 2.0 - 12.0)
			"side":
				p += Vector2(er + 6.0, -er)
		var spec: Array = g.V6_FRAMES[nm]
		var sc: float = g.vfx.int_scale(clampf(er / 12.0, 0.8, 2.0) * g.PX * float(ent.get("sc", 1.0)))
		fx_frame(o.cv, g, nm, int(spec[0]), int(float(g.t) * float(spec[1])), p, sc, Color(1, 1, 1, dk))
	return cov


static func px_ul_on(o) -> bool:
	return not o.g.vfx.px_ul_reg(str(o.id)).is_empty()


static func px_ul_shape(o, b: Dictionary, hits: Array, ang: float, r: float, c := Vector2.INF) -> bool:
	if b.get("px_ul", true) == false:   # 形状块写 "px_ul": false = 不接管这一下（同 src 同圆心同拍的重复判定，例：浊心斯卡蒂 trait「领唱」与普攻「声浪」；纯画面）
		return false
	var reg: Dictionary = o.g.vfx.px_ul_reg(str(o.id))
	if reg.is_empty():
		return false
	var src: String = str(b.get("px_key", b.get("src", "")))   # px_key（docs/242 §14.12）：同一个 src 的几段要换不同帧条时，形状块写自己的区分键
	var ent = reg.get("shapes", _ED).get(src)
	if not (ent is Dictionary):
		return false
	var skill: bool = ent.get("skill", false)
	var alt_base: String = ""
	var alt_draw = null
	for al in ent.get("alt", _EA):   # alt（组长 11-04，docs/242 §14.4）：[{cond, base, skill, draw}]，第一条成立的换主形（例：乌尔比安 S2 生效后锚击换形 "skill_active:1"），draw 逐字段覆盖画法
		if al is Dictionary and cond_true(o, _px_alt_cond(o, str(al.get("cond", "")))):
			alt_base = str(al.get("base", ""))
			skill = al.get("skill", skill)
			alt_draw = al.get("draw")
			break
	var half: float = float(b.half) if b.has("half") else deg_to_rad(float(b.get("half_deg", 45.0)))
	var a: float = ang
	var use: Dictionary = ent
	if half >= 3.1 and reg.get("full") is Dictionary:
		use = reg.full   # 全方向横扫（斯卡蒂涌潮悲歌）：整圈随机转个角度（画面随机数 vrng，判定不动）；full.aim = facing / nearest 时帧条正右对准朝向 / 最近敌人（斯卡蒂 v4 S3 主浪，§14.25）
		match str(use.get("aim", "")):
			"facing":
				a = o.facing_angle()
			"nearest":
				var ne: Array = o.nearest_raw(1, maxf(r * 3.0, 400.0), o.pos)
				a = (ne[0].pos - o.pos).angle() if not ne.is_empty() else o.facing_angle()
			_:
				a = ang + o.g.vrng.randf() * TAU
	var base: String = alt_base if alt_base != "" else str(use.base)
	var nv: int = int(use.get("variants", 1))
	var vv: int = 1 + int(o.g.vrng.randf() * nv) if o.is_leader and nv >= 2 else 1   # 只有队长挑种子变体；队友版 _tm 余韵约减半、亮度不降
	var el: int = o.g.vfx.px_ul_el(o)
	var dn: String = o.g.vfx.px_ul_tex(base, vv, not o.is_leader, "deco", el)
	var nm: String = o.g.vfx.px_ul_tex(base, vv, not o.is_leader, "core", el)
	if o.g.tex.get(nm) == null:
		return false
	var dw: Dictionary = reg.get("draw", _ED)
	if ent.has("draw"):   # 形状条目自带 draw（各形状半径差得多时各用各的 fit）：逐字段覆盖干员级 draw
		dw = dw.duplicate()
		dw.merge(ent.draw, true)
	if alt_draw is Dictionary:   # alt 换主形时再按它的 draw 逐字段覆盖
		dw = dw.duplicate()
		dw.merge(alt_draw, true)
	var dk: float = o.g.vfx.px_deco_k(o)
	var mo: Dictionary = reg.get("motes", _ED)
	var bl := {"fit": float(dw.get("fit", 80.0)), "k": float(dw.get("k", 1.0)), "along": float(dw.get("along", 0.0)), "y": float(dw.get("y", -10.0)), "mirror": dw.get("mirror", "face")}
	if c != Vector2.INF:   # 圆形判定：画在圆心，不随出手方向转（形状条目 spin = 整圈随机转角，画面随机 vrng：德克萨斯骤雨连斩 4 下各不相同）
		var sc: float = r * float(bl.k) / float(bl.fit)
		var rot: float = o.g.vrng.randf() * TAU if ent.get("spin", false) else 0.0
		var cfl := false
		match str(ent.get("aim", "")):   # aim（组长 11-04「去匀圆」）：帧条正右对准最近的敌人（nearest）/ 干员朝向（facing）；flip: true 时朝左转半圈并翻转（上下不颠倒）
			"nearest":
				var ne: Array = o.nearest_raw(1, maxf(r * 3.0, 400.0), c)
				rot = (ne[0].pos - c).angle() if not ne.is_empty() and ne[0].pos != c else o.facing_angle()
			"facing":
				rot = o.facing_angle()
		if ent.get("flip", false) and ent.has("aim") and cos(rot) < 0.0:
			rot += PI
			cfl = true
		if dn != "" and dk > 0.0:
			o.spawn_fx_sprite(dn, c + Vector2(0, float(bl.y)), sc, rot, cfl, false, Color(1, 1, 1, dk))
		o.spawn_fx_sprite(nm, c + Vector2(0, float(bl.y)), sc, rot, cfl, false, Color.WHITE)
	else:
		if dn != "" and dk > 0.0:
			var bd: Dictionary = bl.duplicate()
			bd["strip"] = dn
			bd["tint"] = [1.0, 1.0, 1.0, dk]
			_hw_blade(o, bd, r, a)
		bl["strip"] = nm
		bl["tint"] = [1.0, 1.0, 1.0, 1.0]
		if not mo.is_empty():
			var m2: Dictionary = mo.duplicate()
			m2["n"] = int(round(float(mo.get("n_skill" if skill else "n", 0)) * dk))
			bl["motes"] = m2
		_hw_blade(o, bl, r, a)
	var pz: Array = reg.get("pause", _EA)
	if not hits.is_empty() and o.is_leader and pz.size() >= 2:
		o.impact_pause(float(pz[1] if skill else pz[0]))   # 命中定格只给队长（用户 11-03 定：队友不定格；共享限频，纯画面）
	return true


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
			var c: Vector2 = o.lead_pos() if str(f.get("at", "self")) == "leader" else o.pos
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
	if blocks.has("run_fx"):   # 跑动拖尾（10-22 歌蕾蒂娅水滑行）：动作为 run 时每 every 秒在脚底播一次的瞬时条目
		var rf = blocks.run_fx
		if not (rf is Dictionary) or not (rf.get("fx", null) is Array):
			errs.append("blocks.run_fx 必须是 {every, fx: [条目…]}")
		else:
			_num(rf, "every", "blocks.run_fx", ctx, true, 0.05, 2.0)
			_fx(rf.fx, "blocks.run_fx.fx", ctx, "shape.circle")


## blocks.attack 的追加字段
static func _hw_attack(atk: Dictionary, ctx: Dictionary) -> void:
	var errs: Array = ctx.errs
	_num(atk, "first", "blocks.attack", ctx, false, 0.0, 30.0)
	_num(atk, "idle", "blocks.attack", ctx, false, 0.0, 5.0)
	if atk.has("far"):   # 远程形态（docs/61 §21.3）：一个形状对象，或一组带 cond 的形状对象（第一块 cond 成立的）
		var fl = atk.far
		for fr in (fl if fl is Array else [fl]):
			if not (fr is Dictionary) or not str(fr.get("shape", "")) in ["wave", "circle", "cone"]:
				errs.append("blocks.attack.far 必须是一个伤害形状对象（shape.wave / circle / cone）或这样的数组，远处的这一下替代近战普攻")
			else:
				_num(fr, "every", "blocks.attack.far", ctx, false, 0.1, 10.0)
				if fr.has("anim") and not (fr.anim is String):
					errs.append("blocks.attack.far.anim 必须是帧条名")
				if fr.has("count") and not (fr.count is bool):
					errs.append("blocks.attack.far.count 必须是 true / false")
				_list([fr], "blocks.attack.far", "skill", ctx)
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
	if b.has("ring") and not (b.ring is bool or (b.ring is String and not parse_cond(b.ring, ctx.base).has("err"))):
		errs.append(p + ".ring 只能是 true / false 或条件串（例 \"!px_ul\"，docs/242 §14.3）")
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
			_num(b, "max_hits", p, ctx, false, 1.0, 99.0)   # 命中几名敌人后消失（缺省不限；普攻剑气 1）
			_num(b, "aim_r", p, ctx, false, 1.0, 1000.0)
			if b.has("from") and not str(b.from) in ["prev", "self"]:
				errs.append(p + ".from 只能是 prev / self")
			if b.has("fan") and (not (b.fan is Array) or b.fan.is_empty() or b.fan.size() > 8):
				errs.append(p + ".fan 必须是 1–8 个偏角（度）的数组")
			if b.has("proj") and not str(b.proj).begins_with("proj_"):
				errs.append(p + ".proj 必须是 proj_* 帧条名")
			if b.has("proj_hold"):
				var spec: Array = ArtS.V6_FRAMES.get(str(b.get("proj", "")), [])
				if b.proj_hold != 1 or spec.size() < 2 or int(spec[0]) != 4:
					errs.append(p + ".proj_hold 须为 1，且 proj 须登记为四帧弹体")
			if b.has("proj_front") and (not b.proj_front is bool or not b.has("proj")):
				errs.append(p + ".proj_front 须为布尔值且须配置 proj")
			if b.has("release_pose"):
				if b.get("from", "prev") != "self":
					errs.append(p + ".release_pose 只用于 from:self")
				var r = b.release_pose
				if not r is Dictionary:
					errs.append(p + ".release_pose 须是 {slot, skill, cycle}")
				else:
					var spr: Dictionary = ctx.sprites.get(str(r.get("slot", "")), {})
					if spr.is_empty() or not spr.has("fire") or int(spr.fire) < 1 or int(spr.fire) >= int(spr.get("frames", 0)):
						errs.append(p + ".release_pose.slot 须引用有出手帧的动作槽")
					_num(r, "skill", p + ".release_pose", ctx, true, 0.0, 2.0)
					_num(r, "cycle", p + ".release_pose", ctx, true, 0.001)
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
