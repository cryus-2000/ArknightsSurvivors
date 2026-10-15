## 干员积木 · seg_angelina（docs/101 §7.3 B6 ①，10-15：由 op_blocks.gd 按段拆出，内容与注释照搬；继承链与门面见 op_blocks.gd）
extends "res://scripts/characters/blocks/seg_hoshiguma.gd"

const KB_DECAY := 900.0                       # enemies.gd：e.kb.move_toward(ZERO, 900 * dt)

const AIR_RISE := 0.15                        # 悬浮：起跳 / 落地秒数（画面高度，不影响判定）

const AIR_FALL := 0.2

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
			e.stun = maxf(e.stun, a.dur - a.t)
			return
	o.air_list.append({"e": e, "t": 0.0, "dur": dur, "h": h})
	e.stun = maxf(e.stun, dur)


static func air_height(a: Dictionary) -> float:
	var k: float = clampf(minf(a.t / AIR_RISE, (a.dur - a.t) / AIR_FALL), 0.0, 1.0)
	return a.h * (1.0 - (1.0 - k) * (1.0 - k))


static func airborne_tick(o, dt: float) -> void:
	if o.air_list.is_empty():
		return
	for a in o.air_list:
		a.t += dt
		var e: Dictionary = a.e
		e.air = 0.0 if e.dead or a.t >= a.dur else air_height(a)
	o.air_list = o.air_list.filter(func(a): return a.t < a.dur and not a.e.dead)


static func airborne_clear(o) -> void:
	for a in o.air_list:
		a.e.air = 0.0
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
	o.shots.append({"p0": p0, "p1": to, "t": 0.0, "dur": dur, "patch": patch})


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
	var ap = sb.get("attack_patch", {})
	if not (ap is Dictionary):
		errs.append(p + ".attack_patch 必须是对象")
		return
	for k in ap:
		if not k in ["mult", "r_mult", "force_mult", "src", "on_hit", "power", "aoe_mult", "on_explode", "on_first", "first_fx", "then_first", "kb", "burst", "swarm", "shots", "_doc"]:   # shots：第 4 批（狐火连珠）；power / aoe_mult / on_explode：手写迁移段（法术弹普攻）；on_first / first_fx / then_first：第 3 批（刺击普攻）；kb / burst / swarm：第 3 批（伞击）
			errs.append("%s.attack_patch.%s：只支持 mult / r_mult / force_mult / src / on_hit / power / aoe_mult / on_explode / on_first / first_fx / then_first / kb / burst / swarm" % [p, k])
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
