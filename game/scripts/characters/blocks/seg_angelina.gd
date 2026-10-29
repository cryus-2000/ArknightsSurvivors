## 干员积木 · seg_angelina（docs/101 §7.3 B6 ①，10-15：由 op_blocks.gd 按段拆出，内容与注释照搬；继承链与门面见 op_blocks.gd）
extends "res://scripts/characters/blocks/seg_hoshiguma.gd"

const KB_DECAY := 900.0                       # enemies.gd：e.kb.move_toward(ZERO, 900 * dt)

const AIR_RISE := 0.15                        # 悬浮：起跳 / 落地秒数（画面高度，不影响判定）

const AIR_FALL := 0.2

const _BalA = preload("res://scripts/core/balance.gd")   # docs/202 成长节点：控制递减（growth/cc_dr_*）与 op_api.add_cc_growth 同一旋钮
const GRAV_C := Color(0.7, 0.5, 0.95)                       # 重力紫（同 data_operator.GRAV）

static var _D = null


static func _heavy(e: Dictionary) -> bool:
	if _D == null:
		_D = load("res://scripts/data.gd")
	return _D.ENEMIES.get(e.get("type", ""), {}).get("heavy", false)


## 失重（st.weightless）期间受到的击退倍率；没有失重 = 1.0（character.gd melee_hit 的击退乘它，老干员乘 1.0 逐字节不变）
## 与 run/enemies.gd 的 kb_taken 同一算式（击退统一入口 apply_kb 在那边乘失重；这里只给本段按距离反算冲量用，docs/101 B7）
static func kb_taken(e: Dictionary, t: float) -> float:
	return float(e.wl_kb) if e.has("wl_t") and float(e.wl_t) > t else 1.0


## 能被位移 / 悬浮的敌人：不是 Boss、Boss 部件、宝箱、固定物
static func _movable(e: Dictionary) -> bool:
	return not (e.dead or e.boss or e.get("part", false) or e.get("chest", false) or str(e.get("ai", "")) == "static")


## 实际位移 dist（世界像素，已含所有倍率）所需的 e.kb 速度：位移 = |kb|² / (2·KB_DECAY) × m，m = 重型 0.3 × enemy_kb（enemies.gd 移动时乘）
static func kb_for(dist: float, m: float) -> float:
	return sqrt(2.0 * KB_DECAY * dist / m) if dist > 0.0 and m > 0.0 else 0.0


## 一名敌人按 b（verb.displace）位移；c = 中心，ring = 环带半径（dir ring 用），sc = 额外倍率（技能 force_mult、per_sec × 间隔）。返回是否动了
static func displace_one(o, e: Dictionary, c: Vector2, b: Dictionary, sc := 1.0, ring := -1.0) -> bool:
	if not _movable(e):
		return false
	var g = o.g
	var d: Vector2 = e.pos - c
	var L: float = d.length()
	var dist: float = float(b.get("dist", 0.0)) * sc * float(o.loc.force) * (float(b.get("elite_mult", 0.5)) if e.elite else 1.0)
	if e.pos.distance_to(g.ppos) <= o.lamp_radius():
		dist *= float(o.loc.force_lit)   # 灯光内的敌人拉得更远（天赋）
	dist *= kb_taken(e, g.t)
	var m: float = (0.3 if _heavy(e) else 1.0) * float(g.enemy_kb_mult)
	dist *= m
	var dir := Vector2.ZERO
	match str(b.get("dir", "pull")):
		"pull", "center":
			if L < 1.0:
				return false
			dir = -d / L
			dist = minf(dist, maxf(0.0, L - float(e.r)))   # 不越过中心
		"push":
			dir = d / L if L > 0.5 else Vector2.RIGHT
		"ring":
			var gap: float = L - ring
			if ring < 0.0 or absf(gap) < 2.0 or L < 1.0:
				return false
			dir = -d / L if gap > 0.0 else d / L
			dist = minf(dist, absf(gap))
	if dist < 0.5:
		return false
	o.apply_kb(e, dir * kb_for(dist, m), false)
	return true


## st.airborne：悬浮 = e.stun + e.air（world.gd 按 e.air 抬高绘制，enemies.gd 悬空时没有接触伤害；同艾丽妮浮空）。精英时长 × 0.5；
## elite_up / elite_down：精英按局内时间周期间歇落地（up 秒能被托起、down 秒落地，确定性）。重复施加只续时长、不重新起跳。
## o.air_list：[{e, t, dur, h}]，data_operator 每帧 airborne_tick 推进
static func lift(o, e: Dictionary, dur: float, h: float, s: Dictionary = {}) -> void:
	if not _movable(e) or dur <= 0.0:
		return
	if e.elite:
		if s.has("elite_up"):
			var up: float = float(s.elite_up)
			var per: float = up + float(s.get("elite_down", 0.0))
			if per > 0.0 and fmod(o.g.t, per) >= up:
				return
		dur *= 0.5
	for a in o.air_list:
		if is_same(a.e, e):
			a.dur = maxf(a.dur, a.t + dur)
			o.add_cc(e, a.dur - a.t, -INF, "airborne")
			return
	o.air_list.append({"e": e, "t": 0.0, "dur": dur, "h": h})
	o.add_cc(e, dur, -INF, "airborne")


static func air_height(a: Dictionary) -> float:
	var k: float = clampf(minf(a.t / AIR_RISE, (a.dur - a.t) / AIR_FALL), 0.0, 1.0)
	return a.h * (1.0 - (1.0 - k) * (1.0 - k))


static func airborne_tick(o, dt: float) -> void:
	if not o.taken.is_empty():   # docs/202 成长节点（透镜 / 致密）：没选节点时直接跳过，老局逐位不变
		lens_tick(o, dt)
		dense_tick(o, dt)
	if o.air_list.is_empty():
		return
	for a in o.air_list:
		a.t += dt
		var e: Dictionary = a.e
		o.set_air(e, 0.0 if e.dead or a.t >= a.dur else air_height(a))   # 托举不清击退（原样）
	o.air_list = o.air_list.filter(func(a): return a.t < a.dur and not a.e.dead)


## docs/202 沉落用的悬浮：同 lift，但控制走 add_cc_growth（同一敌人 3 秒内第二次受控时长减半）；画面悬浮时长同步减半
static func lift_growth(o, e: Dictionary, dur: float, h: float) -> void:
	if not _movable(e) or dur <= 0.0:
		return
	if e.elite:
		dur *= 0.5
	var dr: float = _BalA.v("growth/cc_dr_mult", 0.5) if o.g.t - float(e.get("gcc_t", -99.0)) < _BalA.v("growth/cc_dr_window", 3.0) else 1.0
	o.add_cc_growth(e, dur, -INF, "airborne")
	var vis: float = dur * dr
	for a in o.air_list:
		if is_same(a.e, e):
			a.dur = maxf(a.dur, a.t + vis)
			return
	o.air_list.append({"e": e, "t": 0.0, "dur": vis, "h": h})


## 节点「重力透镜」（wide）：重力弹飞行途中，弹道（脚底到落点的直线）两侧 lens_r 内、弹头已扫过的敌人被吸向弹道中线，
## 每名敌人每发至多吸 lens_pull 像素（精英 ×0.5、重型 ×0.3、Boss / 固定物不动）
static func lens_tick(o, dt: float) -> void:
	if o.shots.is_empty() or not ("wide" in o.taken):
		return
	var g = o.g
	var r: float = o.base("lens_r", 60.0)
	var cap: float = o.base("lens_pull", 20.0)
	for s in o.shots:
		var g0: Vector2 = s.get("g0", s.p0)
		var L: Vector2 = s.p1 - g0
		var len: float = L.length()
		if len < 8.0:
			continue
		var d: Vector2 = L / len
		var done: Dictionary = s.get("lens", {})
		s["lens"] = done
		var reach: float = clampf(s.t / maxf(0.05, s.dur), 0.0, 1.0) * len + 36.0
		var step: float = cap * dt / maxf(0.1, s.dur) * 1.6
		for j in o.query_ids((g0 + s.p1) * 0.5, len * 0.5 + r + 24.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or not _movable(e):
				continue
			var rel: Vector2 = e.pos - g0
			var along: float = rel.dot(d)
			if along < 0.0 or along > minf(len, reach):
				continue
			var perp: Vector2 = rel - d * along
			var pd: float = perp.length()
			if pd > r or pd < 2.0:
				continue
			var used: float = float(done.get(e.id, 0.0))
			if used >= cap:
				continue
			var f: float = (0.5 if e.elite else 1.0) * (0.3 if _heavy(e) else 1.0) * float(g.enemy_kb_mult) * float(o.loc.force)
			var mv: float = minf(minf(step * f, pd), cap - used)
			o.nudge(e, -perp / pd * mv)
			if used <= 0.0 and done.size() < 10:
				o.fx({"kind": "spark", "pos": e.pos + Vector2(0, -float(e.r) * 0.4), "vel": -perp / pd * 90.0, "life": 0.22, "col": GRAV_C * 1.5, "sz": 2.0})
			done[e.id] = used + mv


## 重力弹飞行画面（data_operator._draw_shots 逐发调用）：弹道亮线 + 两侧透镜边线（只有选了重力透镜才画）
static func lens_draw(o, s: Dictionary, _p: Vector2) -> void:
	if not ("wide" in o.taken):
		return
	var cv = o.cv
	var g0: Vector2 = s.get("g0", s.p0)
	var L: Vector2 = s.p1 - g0
	if L.length() < 8.0:
		return
	var n: Vector2 = L.normalized().orthogonal() * o.base("lens_r", 60.0) * 0.8
	var k: float = clampf(s.t / maxf(0.05, s.dur), 0.0, 1.0)
	var pk: Vector2 = g0.lerp(s.p1, k)
	cv.draw_line(g0, s.p1, Color(GRAV_C.r, GRAV_C.g, GRAV_C.b, 0.22), 1.5)
	cv.draw_line(g0, pk, Color(GRAV_C.r * 1.5, GRAV_C.g * 1.5, GRAV_C.b * 1.5, 0.7), 2.5)
	for sg in [-1.0, 1.0]:   # 两侧向中线收拢的边线（到弹头处汇合）
		cv.draw_line(g0 + n * sg, pk, Color(GRAV_C.r, GRAV_C.g, GRAV_C.b, 0.28), 1.0)


## 节点「致密」（dense）：落点 ≥ dense_n 名敌人时，被命中的敌人叠向中心（dense_gather 像素，走 displace_one 的精英 / 重型倍率），
## dense_delay 秒后坍缩爆开（半径 dense_r，dense_mult × 攻击）；队列 gr_q 最多 6 个
static func dense_collapse(o, c: Vector2, hits: Array) -> void:
	var q: Array = o.get_meta("gr_q", [])
	if q.size() >= 6:
		return
	var gb := {"dir": "pull", "dist": o.base("dense_gather", 36.0), "elite_mult": o.base("pull_elite", 0.5)}
	for e in hits:
		if not e.dead:
			displace_one(o, e, c, gb)
	q.append({"t": o.base("dense_delay", 0.3), "c": c})
	o.set_meta("gr_q", q)
	var r: float = o.base("dense_r", 60.0) * float(o.loc.area)
	o.fx({"kind": "ring", "pos": c, "r": 6.0, "r0": r * 1.1, "life": 0.3, "col": GRAV_C * 1.4, "floor": true, "keep": true, "w": 2.5})   # 向内收拢的环
	o.fx({"kind": "glow", "pos": c, "r": 10.0, "life": 0.3, "col": Color(0.35, 0.2, 0.6), "alpha": 0.9})                 # 压缩成黑点


static func dense_tick(o, dt: float) -> void:
	if not o.has_meta("gr_q"):
		return
	var q: Array = o.get_meta("gr_q")
	if q.is_empty():
		return
	var g = o.g
	for it in q:
		it.t -= dt
		if it.t > 0.0:
			continue
		var r: float = o.base("dense_r", 60.0) * float(o.loc.area)
		var dmg: float = o.base("atk", 0.0) * o.base("dense_mult", 0.3) * float(o.loc.dmg) * o._dmg_bonus()
		o.area_hit("致密", it.c, r, dmg)
		o.fx({"kind": "ring", "pos": it.c, "r": r, "r0": r * 0.2, "life": 0.28, "col": GRAV_C * 1.6, "floor": true, "keep": true, "w": 3.0})
		o.fx({"kind": "glow", "pos": it.c, "r": r * 0.7, "life": 0.2, "col": Color(1.2, 0.8, 1.6), "alpha": 0.75})
		for k in 7:
			var a: float = g.vrng.randf() * TAU
			o.fx({"kind": "spark", "pos": it.c, "vel": Vector2.from_angle(a) * g.vrng.randf_range(80.0, 170.0), "life": 0.3, "col": GRAV_C * 1.6, "sz": 2.5})
	o.set_meta("gr_q", q.filter(func(it): return it.t > 0.0))


## 节点「潮汐锁·沉落」（lock2）：环带内停留满 sink 秒的敌人被锁定悬浮（lift_growth），每名敌人 sink_cd 秒内至多一次。
## s = field 的 tick 子项（st: airborne + sink / sink_cd）；停留以 field 的间隔累计，离开环带 / 场停转即清零
static func sink_tick(o, e: Dictionary, s: Dictionary, c: Vector2, ring: float, rw: float, every: float) -> void:
	var g = o.g
	var inband: bool = ring >= 0.0 and absf(e.pos.distance_to(c) - ring) <= rw
	if not inband or not _movable(e):
		e["ang_dw"] = 0.0
		return
	if g.t - float(e.get("ang_sk", -99.0)) < float(s.get("sink_cd", 6.0)):
		return
	var dw: float = float(e.get("ang_dw", 0.0)) if g.t - float(e.get("ang_dwt", -99.0)) <= every * 1.6 else 0.0
	dw += every
	e["ang_dw"] = dw
	e["ang_dwt"] = g.t
	var need: float = float(s.get("sink", 2.0))
	if dw < need:
		o.fx({"kind": "ring", "pos": e.pos, "r": float(e.r) + 3.0, "r0": float(e.r) + 3.0 + 14.0 * (1.0 - dw / need), "life": every, "col": GRAV_C, "floor": true, "w": 1.5, "keep": true, "alpha": 0.6})   # 停留进度：脚下的锁环逐渐收紧
		return
	e["ang_dw"] = 0.0
	e["ang_sk"] = g.t
	lift_growth(o, e, float(s.dur), float(s.get("h", 22.0)))
	o.fx({"kind": "ring", "pos": e.pos, "r": float(e.r) + 14.0, "r0": float(e.r), "life": 0.3, "col": GRAV_C * 1.6, "floor": true, "keep": true, "w": 2.5})
	for k in 3:
		o.fx({"kind": "mote", "pos": e.pos + Vector2((k - 1) * float(e.r) * 0.5, -float(e.r) * 0.3), "vel": Vector2(0, -50), "life": 0.5, "col": GRAV_C * 1.5, "sz": 2.0})


static func airborne_clear(o) -> void:
	for a in o.air_list:
		o.set_air(a.e, 0.0)
	o.air_list = []


## 常驻力场（verb.field 带 tick）的中心：leader = 主控（缺省；图鉴演示以自己为中心），self = 自己
static func force_center(o, b: Dictionary) -> Vector2:
	if str(b.get("center", "leader")) == "self" or o.g.demo_op != "":
		return o.pos
	return o.g.ppos


## verb.field（docs/60 §8 第 22 条）：以 center 为心、半径 r（× op_range）的常驻力场，每 every 秒对场内敌人逐个执行 tick 子项
## （verb.displace / st.*）。ring：环带半径（displace dir: ring 往这里收；子项 where: ring 只作用于环带 ±ring_w）。生效当帧先跑一次。
## st：本积木的状态 {acc, c, r, ring, look, t}（data_operator 的 _state，绘制也读它）
static func field_tick(o, b: Dictionary, st: Dictionary, dt: float) -> void:
	var every: float = float(b.get("every", 0.5))
	st.acc = float(st.get("acc", every)) + dt
	st.c = force_center(o, b)
	st.r = float(b.get("r", 0.0)) * o.stat(&"op_range")
	st.ring = float(b.get("ring", -1.0)) * o.stat(&"op_range") if b.has("ring") else -1.0
	st.look = str(b.get("look", "none"))
	st.t = float(st.get("t", 0.0)) + dt
	if st.acc < every or st.c == Vector2.INF:
		return
	st.acc -= every
	var c: Vector2 = st.c
	var rw: float = float(b.get("ring_w", 24.0))
	for j in o.query_ids(c, st.r + 24.0):
		var e: Dictionary = o.g.enemies[j]
		if e.dead or e.pos.distance_to(c) > st.r:
			continue
		for s in b.get("tick", _EA):
			if e.dead:
				break
			if s.has("sink"):   # docs/202 潮汐锁·沉落
				sink_tick(o, e, s, c, st.ring, rw, every)
				continue
			if str(s.get("_tag", "")) == "verb.displace":
				if not cond_true(o, s.get("cond", _ED)):
					continue
				if displace_one(o, e, c, s, every if s.get("per_sec", false) else 1.0, st.ring):
					for s2 in s.get("on_hit", _EA):
						apply_status(o, e, s2, c, st.ring, rw)
			else:
				apply_status(o, e, s, c, st.ring, rw)


## shape.point_aoe 选落点：land = densest（射程内敌群最密处，缺省）/ nearest
static func point_aoe_target(o, b: Dictionary) -> Vector2:
	var reach: float = float(b.get("range", 300.0)) * o.stat(&"op_range")
	if str(b.get("land", "densest")) == "nearest":
		var ts: Array = o.nearest_enemies(1, reach, o.pos)
		return ts[0].pos if not ts.is_empty() else Vector2.INF
	return o.densest_point(reach, o.pos)


## shape.point_aoe 出手：从 muzzle（脚底为原点、朝右，世界像素 = @2x 像素）射向落点，飞 dist / speed 秒。patch：次数型技能的 attack_patch
static func point_aoe_fire(o, b: Dictionary, to: Vector2, patch: Dictionary) -> void:
	if to == Vector2.INF:
		return
	var mz = b.get("muzzle", [0.0, 0.0])
	var p0: Vector2 = o.pos + Vector2(float(mz[0]) * o.face, float(mz[1])) if mz is Array and mz.size() == 2 else o.pos
	var dur: float = o.pos.distance_to(to) / maxf(1.0, float(b.get("speed", 400.0)))
	o.shots.append({"p0": p0, "p1": to, "t": 0.0, "dur": dur, "patch": patch, "g0": o.pos})


## 落点结算：半径 r（× area × patch.r_mult）伤害 + on_hit（本体的 + patch 的）→ then（瞬时积木，center: target = 落点）→ trig.on_impact
static func point_aoe_land(o, b: Dictionary, s: Dictionary) -> void:
	var c: Vector2 = s.p1
	var patch: Dictionary = s.patch
	o.shot = patch
	var r: float = float(b.get("r", 0.0)) * float(o.loc.area) * float(patch.get("r_mult", 1.0))
	var dmg: float = o.base(str(b.get("atk_key", "atk")), 0.0) * float(b.get("mult", 1.0)) * float(patch.get("mult", 1.0)) * float(o.loc.dmg) * o._dmg_bonus()
	var hits: Array = o.area_hit(str(patch.get("src", b.get("src", ""))), c, r, dmg, 0.0, 0.0, b.get("tags", []), int(b.get("max_n", 0)))
	for lst in [b.get("on_hit", []), patch.get("on_hit", [])]:
		for st in lst:
			for e in hits:
				apply_status(o, e, st, c)
	o._exec_list(b.get("then", []), c)
	if not o.taken.is_empty() and "dense" in o.taken and hits.size() >= int(o.base("dense_n", 5.0)):   # docs/202 致密
		dense_collapse(o, c, hits)
	o.impact(c)
	o.shot = {}


# ---------------------------------------------------------------- 安洁莉娜段：校验

## _block 的分流：tag 是本段的积木时由这里校验
static func _v_angelina(b: Dictionary, p: String, kind: String, ctx: Dictionary, tag: String) -> void:
	var errs: Array = ctx.errs
	var where_ok := {
		"shape.point_aoe": ["attack"],
		"st.airborne": ["on_hit", "field"],
		"st.weightless": ["on_hit", "field"],
		"st.dot": ["field"],
		"trig.on_impact": ["trig"],
	}
	if not kind in where_ok[tag]:
		errs.append("%s：「%s」不能放在这里（只能在 %s）" % [p, tag, " / ".join(where_ok[tag])])
		return
	match tag:
		"shape.point_aoe":
			_num(b, "range", p, ctx, true, 1.0)
			_num(b, "r", p, ctx, true, 1.0, 400.0)
			_num(b, "speed", p, ctx, false, 1.0)
			_num(b, "mult", p, ctx, false, -INF, 20.0)
			_num(b, "max_n", p, ctx, false, 1.0, 99.0)
			if not str(b.get("land", "densest")) in ["densest", "nearest"]:
				errs.append(p + ".land 只能是 densest / nearest")
			var mz = b.get("muzzle", [0, 0])
			if not (mz is Array and mz.size() == 2 and (mz[0] is float or mz[0] is int) and (mz[1] is float or mz[1] is int)):
				errs.append(p + ".muzzle 应是 [x, y]（脚底为原点、朝右，@2x 像素）")
			_src(b, p, ctx, true)
			_list(b.get("on_hit", []), p + ".on_hit", "on_hit", ctx)
			_list(b.get("then", []), p + ".then", "instant", ctx)
		"st.airborne":
			_num(b, "dur", p, ctx, true, 0.0, 10.0)
			_num(b, "h", p, ctx, false, 0.0, 80.0)
			_num(b, "within", p, ctx, false, 0.0)
			_num(b, "elite_up", p, ctx, false, 0.0)
			_num(b, "elite_down", p, ctx, false, 0.0)
		"st.weightless":
			_num(b, "dur", p, ctx, true, 0.0, 10.0)
			_num(b, "kb_mult", p, ctx, true, 1.0, 3.0)
		"st.dot":
			_num(b, "mult", p, ctx, true, 0.0, 20.0)
			_src(b, p, ctx, true)
		"trig.on_impact":
			_num(b, "delay", p, ctx, false, 0.0, 5.0)
			_list(b.get("do", []), p + ".do", "instant", ctx)


## 技能外壳 dur.next_n（docs/61 §2）：{"next_attacks": N} + attack_patch（叠到接下来 N 次普攻上；目前只配 shape.point_aoe 的普攻）
static func _v_next_n(sb: Dictionary, p: String, perm_json: bool, ctx: Dictionary) -> void:
	var errs: Array = ctx.errs
	var dv: Dictionary = sb.dur
	if perm_json:
		errs.append(p + ".dur：permanent 技能不能写 next_attacks")
	for k in dv:
		if k != "next_attacks":
			errs.append("%s.dur.%s：dur 对象只支持 next_attacks" % [p, k])
	_num(dv, "next_attacks", p + ".dur", ctx, true, 1.0, 20.0)
	_num(sb, "stack_max", p, ctx, false, 1.0, 20.0)
	var ap = sb.get("attack_patch", {})
	if not (ap is Dictionary):
		errs.append(p + ".attack_patch 必须是对象")
		return
	for k in ap:
		if not k in ["mult", "r_mult", "force_mult", "src", "on_hit", "power", "aoe_mult", "on_explode", "on_first", "first_fx", "then_first", "kb", "burst", "swarm", "shots", "anim", "_doc"]:   # shots：第 4 批（狐火连珠）；power / aoe_mult / on_explode：手写迁移段（法术弹普攻）；on_first / first_fx / then_first：第 3 批（刺击普攻）；kb / burst / swarm：第 3 批（伞击）
			errs.append("%s.attack_patch.%s：只支持 mult / r_mult / force_mult / src / on_hit / power / aoe_mult / on_explode / on_first / first_fx / then_first / kb / burst / swarm" % [p, k])
	if ap.has("anim") and (not ap.anim is String or not ctx.sprites.get(ap.anim) is Dictionary):
		errs.append(p + ".attack_patch.anim 必须指向已定义的帧条")
	_list(ap.get("on_first", []), p + ".attack_patch.on_first", "on_hit", ctx)
	_list(ap.get("then_first", []), p + ".attack_patch.then_first", "instant", ctx)
	if ap.has("first_fx"):
		_fx(ap.first_fx, p + ".attack_patch.first_fx", ctx, "shape.circle")
	if ap.has("on_explode"):
		_list(ap.on_explode, p + ".attack_patch.on_explode", "instant", ctx)
	for k in ["mult", "r_mult", "force_mult"]:
		_num(ap, k, p + ".attack_patch", ctx, false, 0.0, 20.0)
	if ap.has("src"):
		_src(ap, p + ".attack_patch", ctx, true)
	_list(ap.get("on_hit", []), p + ".attack_patch.on_hit", "on_hit", ctx)
