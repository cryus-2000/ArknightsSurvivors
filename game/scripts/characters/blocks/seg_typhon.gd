## 干员积木 · seg_typhon（docs/402 提丰：攻城手选目标、精一「锐如兽牙」、天赋「重如沼泥」、S2「冰原秩序」第二次起永久、S3「“永恒狩猎”」箭雨、精二「钉影」、成长节点）
## 弹体沿用能天使段（seg_exusiai：o.ext.bul、_exu_bullets 推进与命中）：exu_fire 看到 verb.ty_hunter 就转本文件 ty_fire 自己射一轮；
## 命中时 _exu_bullets 对带 "ty" 字段的弹体调 ty_hit_mult（结算前倍率）/ ty_after_hit（结算后效果）；每帧 exu_tick 末尾调 ty_tick，exu_draw 末尾调 ty_draw。
## 积木全是常驻标记（_exu_active 读）：verb.ty_hunter（特性）、ty_fang（精一）、ty_mire（天赋）、ty_pin（精二）、ty_ripple / ty_volley / ty_headhunt / ty_herd / ty_hh2 / ty_trap（成长节点）；
## 瞬时两个：verb.ty_s2（S2 do：数放出次数，第 permanent_after 次起永久）、verb.ty_hunt（S3 do：记下箭雨参数、标记目标）。
## 运行时状态放 o.ext.ty：fang 层数 / fang_t 上次射击、n 普攻计数、vn 齐射计数、s2n S2 放出次数、hunt 箭雨参数、mark 标记、stakes 黑箭、traps 影子陷阱、trap_t。
## 确定性：S2 眩晕概率、S3 箭雨落点取 g.rng_op（玩法随机，同能天使跳弹）；只在对应技能生效时才取，别的干员一个随机数都不多取。画面只发 _FXR.ev 事件 + 占位程序图形。
extends "res://scripts/characters/blocks/seg_ling.gd"

const TY_SUSTAIN := ["verb.ty_hunter", "verb.ty_fang", "verb.ty_mire", "verb.ty_pin", "verb.ty_ripple", "verb.ty_volley", "verb.ty_headhunt", "verb.ty_herd", "verb.ty_hh2", "verb.ty_trap"]
const TY_INSTANT := ["verb.ty_s2", "verb.ty_hunt"]
const TY_STAKE_MAX := 6      # 黑箭硬上限（积木 max 另限）
const TY_TRAP_MAX := 4
const TY_BLACK := Color(0.12, 0.08, 0.16)
const TY_VIOLET := Color(0.7, 0.55, 0.95)


static func ty_st(o) -> Dictionary:
	var st := exu_st(o)
	if not st.has("ty"):
		st["ty"] = {"fang": 0, "fang_t": -99.0, "n": 0, "vn": 0, "s2n": 0, "hunt": {}, "mark": null, "stakes": [], "traps": [], "trap_t": 0.0}
	return st.ty


static func _ty_one(o, tag: String) -> Dictionary:
	if not o.tags_all.has(tag):
		return _ED
	var a: Array = _exu_active(o, tag)
	return a.back() if not a.is_empty() else _ED


## 她自己的任意技能生效中（S3 是次数型：o.ext.ammo[2]）
static func ty_skill_on(o) -> bool:
	return o.s_t[0] > 0.0 or o.s_t[1] > 0.0 or o.perm_on[1] or int(o.ext.get("ammo", [0, 0, 0])[2]) > 0


static func _ty_s2_on(o) -> bool:
	return o.s_t[1] > 0.0 or o.perm_on[1]


# ---------------------------------------------------------------- 选目标（特性：Boss → 精英 → 重型 → 当前生命最多，同档近者优先）

static func ty_targets(o, n: int, rr: float) -> Array:
	if o.held_aim() or o.prio_mode() == 1:
		return _exu_targets(o, n, rr, 1.0)   # 手动瞄准 / 指挥「清杂优先」照能天使的口径
	var hb := _ty_one(o, "verb.ty_hunter")
	var guard: float = float(hb.get("guard_r", 0.0))   # 近身护卫（11-21 云端配对：只按「最重」选时追踪者贴到队长身上没人打，胜率 22%）
	var lp: Vector2 = o.g.ppos if o.g.ppos != Vector2.INF else o.pos
	var keyed: Array = []
	for j in o.query_ids(o.pos, rr):
		var e: Dictionary = o.g.enemies[j]
		if e.dead or e.chest or o.pos.distance_to(e.pos) > rr:
			continue
		var tier: int = 0 if e.boss else (1 if e.elite else (2 if _heavy(e) else 3))
		var hp_key: float = -float(e.hp) if tier < 3 else e.pos.distance_to(lp)   # 普通杂兵按离队长近的先（11-21 配对：按生命最多选会漏掉冲脸的追踪者）
		if guard > 0.0 and not e.boss and e.pos.distance_to(lp) <= guard:
			tier = -1   # 贴近队长的敌人先打，同档离队长近的先
			hp_key = e.pos.distance_to(lp)
		if not o.hittable(e):
			tier += 10
		keyed.append([tier, hp_key, o.pos.distance_to(e.pos), int(e.id), e])
	keyed.sort_custom(func(x, y):
		for k in 4:
			if x[k] != y[k]:
				return x[k] < y[k]
		return false)
	var out: Array = []
	for k in mini(n, keyed.size()):
		out.append(keyed[k][4])
	if not out.is_empty() and o.g.map.tb_aim and o.g.map.blocks():
		var all: Array = []
		for kv in keyed:
			all.append(kv[4])
		out = o.los_sort(all, n)
	return out


# ---------------------------------------------------------------- 出手

## exu_fire 转来（普攻 / 次数型技能的那一轮）：p 已合过持续型技能的 attack_patch
static func ty_fire(o, p: Dictionary, main: bool) -> void:
	if not main:
		_exu_volley(o, p, main, true)
		return
	var g = o.g
	var st := exu_st(o)
	var ty := ty_st(o)
	if o.pos == Vector2.INF:
		return
	var rr: float = _exu_range(o, p)
	var fang_b := _ty_one(o, "verb.ty_fang")
	if int(st.ammo[2]) > 0 and not ty.hunt.is_empty():
		if _ty_rain(o, rr):
			st.ammo[2] = int(st.ammo[2]) - 1
			_ty_fang_add(o, fang_b)
		return
	var n := 2 if (_ty_s2_on(o) and not _ty_s2_block(o).is_empty()) else 1
	var fan := 0
	var vb := _ty_one(o, "verb.ty_volley")
	if not vb.is_empty() and o.s_t[0] > 0.0:
		ty.vn = int(ty.vn) + 1
		if int(ty.vn) % maxi(2, int(vb.get("every", 3))) == 0:
			fan = 3
	var ts: Array = ty_targets(o, n, rr)
	if ts.is_empty():
		return
	var aim0: Vector2 = ts[0].pos + Vector2(0, EXU_AIM_Y)
	o.face_to((aim0 - o.pos).angle())
	var mz := _exu_muzzle(o, p)
	var d0: Vector2 = (aim0 - mz).normalized() if aim0.distance_to(mz) > 1.0 else Vector2(o.face, 0.0)
	var speed: float = maxf(60.0, float(p.get("speed", 900.0)))
	var base_dmg: float = o.base(str(p.get("atk_key", "atk")), 0.0) * float(p.get("mult", 1.0)) * float(o.loc.dmg) * o._dmg_bonus()
	if p.get("power", false):
		base_dmg *= o.skill_power()
	ty.n = int(ty.n) + 1
	var pin_b := _ty_one(o, "verb.ty_pin")
	var pin_now: bool = not pin_b.is_empty() and int(ty.n) % maxi(2, int(pin_b.get("every", 3))) == 0
	var heavy := false   # 节点 5A 破甲重矢：满层且头号目标是精英 / Boss
	var hh2 := _ty_one(o, "verb.ty_hh2")
	if not hh2.is_empty() and not fang_b.is_empty() and int(ty.fang) >= int(fang_b.get("max", 5)) and (ts[0].elite or ts[0].boss):
		heavy = true
	var s2b := _ty_s2_block(o)
	var shots: Array = []   # [方向, 伤害倍率, 第几支]
	if fan > 0:
		var sp: float = deg_to_rad(float(vb.get("spread", 24.0))) * 0.5
		for k in fan:
			shots.append([d0.rotated(lerpf(-sp, sp, float(k) / float(fan - 1))), 1.0, k])
	else:
		for k in n:
			var e: Dictionary = ts[k % ts.size()]
			var to: Vector2 = e.pos + Vector2(0, EXU_AIM_Y) - mz
			var dir: Vector2 = to.normalized() if to.length() > 1.0 else d0
			if k > 0 and is_same(e, ts[0]):
				dir = dir.rotated(deg_to_rad(4.0))
			shots.append([dir, float(s2b.get("twin", 0.8)) if k > 0 else 1.0, k])
	var stacks: int = int(ty.fang)
	for s in shots:
		if st.bul.size() >= EXU_BULLET_MAX:
			break
		var k: int = int(s[2])
		var tyd: Dictionary = {"fang": stacks, "s2": not s2b.is_empty() and n == 2}
		var m: float = float(s[1])
		var src: String = str(p.get("src", ""))
		if k == 0 and pin_now:
			tyd["pin"] = true
		if k == 0 and heavy:
			m *= float(hh2.get("mult", 2.0))
			tyd["root"] = float(hh2.get("root", 0.6))
			src = str(hh2.get("src", src))
		if n == 2 and str(s2b.get("src", "")) != "":
			src = str(s2b.src)
		st.bul.append({"stn": 0.0, "p": mz, "v": s[0] * speed, "life": rr * 1.15 / speed, "dmg": base_dmg * m, "src": src,
			"tags": p.get("tags", []), "pierce": o.atk_pierce(int(p.get("pierce", 0))), "main": true, "kb": float(p.get("kb", 0.0)), "hit": {},
			"tex": "proj_exusiai_bullet_power" if (heavy and k == 0) or stacks >= int(fang_b.get("max", 99)) else str(p.get("tex", "proj_exusiai_bullet")),
			"hfx": str(p.get("hit_fx", "fx_exusiai_hit")), "on_hit": p.get("on_hit", []), "ric": false, "tr": {}, "ty": tyd})
	if heavy:
		ty.fang = 0
	else:
		_ty_fang_add(o, fang_b)
	_FXR.ev(o, "ty_fire", {"mz": mz, "d": d0, "n": shots.size(), "fang": stacks, "heavy": heavy, "pin": pin_now})
	o._sfx_op("atk", 1.5 if heavy else 0.0, 0.85 if heavy else 1.0)


static func _ty_fang_add(o, fang_b: Dictionary) -> void:
	if fang_b.is_empty():
		return
	var ty := ty_st(o)
	ty.fang = mini(int(fang_b.get("max", 5)), int(ty.fang) + 1)
	ty.fang_t = o.g.t


## 本帧生效的 S2 参数块（S2 do 里的 verb.ty_s2；技能没开 = {}）
static func _ty_s2_block(o) -> Dictionary:
	if not _ty_s2_on(o):
		return _ED
	var sk: Array = o.B.get("skills", [])
	if sk.size() < 2:
		return _ED
	for b in sk[1].get("do", _EA):
		if str(b.get("_tag", "")) == "verb.ty_s2":
			return b
	return _ED


# ---------------------------------------------------------------- S3 箭雨

## 一轮箭雨：标记（死了就转到上一个标记 hop_r 内最重的，再没有就重新挑）周围 r 内随机 n 名敌人各一支；敌人不够时多出来的落在标记上
static func _ty_rain(o, rr: float) -> bool:
	var g = o.g
	var ty := ty_st(o)
	var h: Dictionary = ty.hunt
	var mk = ty.mark
	if mk == null or mk.dead or o.pos.distance_to(mk.pos) > rr * 1.3:
		var from: Vector2 = mk.pos if mk != null else o.pos
		mk = null
		var best: Array = []
		for j in o.query_ids(from, float(h.get("hop_r", 200.0))):
			var e: Dictionary = g.enemies[j]
			if e.dead or e.chest or not o.hittable(e) or o.pos.distance_to(e.pos) > rr:
				continue
			var key := [0 if e.boss else (1 if e.elite else (2 if _heavy(e) else 3)), -float(e.hp), int(e.id)]
			if best.is_empty() or key < best[0]:
				best = [key, e]
		if not best.is_empty():
			mk = best[1]
		else:
			var ts := ty_targets(o, 1, rr)
			if ts.is_empty():
				ty.mark = null
				return false
			mk = ts[0]
		ty.mark = mk
	o.face_to((mk.pos - o.pos).angle())
	var r: float = float(h.get("r", 100.0))
	var pool: Array = []
	for j in o.query_ids(mk.pos, r + 24.0):
		var e: Dictionary = g.enemies[j]
		if not e.dead and not e.chest and not is_same(e, mk) and e.pos.distance_to(mk.pos) <= r + float(e.r):
			pool.append(e)
	pool.sort_custom(func(a, b): return int(a.id) < int(b.id))
	var n: int = int(h.get("n", 5))
	var picks: Array = []
	var spill_n := 0
	for k in n:
		if pool.is_empty():
			picks.append(mk)
			spill_n += 1
			continue
		var idx: int = g.rng_op.randi() % pool.size()
		picks.append(pool[idx])
		pool.remove_at(idx)
	var dmg: float = o.base("atk", 0.0) * float(h.get("mult", 1.0)) * float(o.loc.dmg) * o._dmg_bonus()
	if h.get("power", false):
		dmg *= o.skill_power()
	var ve: float = o.vs_elite()
	var stacks: int = int(ty.fang)
	var pts: Array = []
	var spill: float = float(h.get("spill", 1.0))
	for pi in picks.size():
		var e: Dictionary = picks[pi]
		if e.dead:
			continue
		var dm: float = dmg * (spill if pi >= n - spill_n else 1.0)   # 多出来落在标记身上的箭（敌人不够 n 名）
		var bu := {"ty": {"fang": stacks, "rain": true}, "hit": {}, "dmg": dm, "v": Vector2(0, 1)}
		var m: float = ty_hit_mult(o, e, bu)
		var dealt: float = dm * (ve if e.elite or e.boss else 1.0) * m
		o.log_hit(str(h.get("src", "")), ["skill", "area"])
		o.deal_damage(e, dealt)
		var stn: float = float(h.get("stun", 0.4))
		if stn > 0.0 and not e.dead and not e.boss:
			o.add_cc(e, stn * (0.5 if e.elite else 1.0))
		bu.hit[e.id] = true
		ty_after_hit(o, e, bu, dealt)
		pts.append(e.pos)
	_FXR.ev(o, "ty_rain", {"mark": mk.pos, "pts": pts})
	ty["rain_fx"] = {"t": g.t, "pts": pts, "mark": mk.pos}
	o._sfx_op("hit")
	return true


# ---------------------------------------------------------------- 命中挂钩（_exu_bullets / _ty_rain 调）

## 结算前倍率：锐如兽牙（无视减伤 + 对精英 / Boss 加成，层数按射出时）× 重如沼泥（技能中对每名敌人的第一次伤害）
static func ty_hit_mult(o, e: Dictionary, bu: Dictionary) -> float:
	var m := 1.0
	var tyd: Dictionary = bu.ty
	var fang_b := _ty_one(o, "verb.ty_fang")
	var stacks: int = int(tyd.get("fang", 0))
	if not fang_b.is_empty() and stacks > 0:
		var edef: float = float(e.get("def", 1.0))
		if edef < 1.0 and edef > 0.0:
			var ign: float = minf(1.0, float(stacks) * float(fang_b.get("ign", 0.1)))
			m *= (1.0 - (1.0 - edef) * (1.0 - ign)) / edef
		if e.elite or e.boss:
			m *= 1.0 + float(stacks) * float(fang_b.get("elite", 0.03))
	var mire := _ty_one(o, "verb.ty_mire")
	if not mire.is_empty() and ty_skill_on(o):
		var fresh: bool = not e.has("ty_m")
		if not fresh and (e.elite or e.boss) and not _ty_one(o, "verb.ty_headhunt").is_empty():
			fresh = o.g.t - float(e.ty_m) >= float(_ty_one(o, "verb.ty_headhunt").get("cd", 6.0))   # 节点 4A 猎首：精英 / Boss 每 cd 秒重新算第一次
		if fresh:
			e["ty_m"] = o.g.t
			m *= float(mire.get("mult", 1.6))
			tyd["mired"] = true
	return m


## 结算后：沼泥停顿、S2 眩晕、重矢定身、空间涟漪、钉影（插箭 / 涟漪转发）、驱群寒气
static func ty_after_hit(o, e: Dictionary, bu: Dictionary, dealt: float) -> void:
	var g = o.g
	var tyd: Dictionary = bu.ty
	var first: bool = bu.hit.size() == 1
	if tyd.get("mired", false):
		tyd.erase("mired")
		var mire := _ty_one(o, "verb.ty_mire")
		var pz: float = float(mire.get("pause", 1.5))
		if not e.dead and not e.boss:
			o.add_cc_growth(e, pz * (0.5 if e.elite else 1.0))
			e["ty_mp"] = g.t + pz * (0.5 if e.elite else 1.0)
		_FXR.ev(o, "ty_mire", {"e": e, "at": e.pos})
		o.fx({"kind": "ring", "pos": e.pos, "r": float(e.r) + 12.0, "r0": float(e.r) + 2.0, "life": 0.3, "col": Color(0.55, 0.45, 0.3), "floor": true, "w": 2.0, "alpha": 0.8})
	if tyd.get("s2", false) and not e.dead and not e.boss:
		var s2b := _ty_s2_block(o)
		if not s2b.is_empty() and g.rng_op.randf() < float(s2b.get("stun_p", 0.3)):
			o.add_cc(e, float(s2b.get("stun", 0.8)) * (0.5 if e.elite else 1.0))
	if float(tyd.get("root", 0.0)) > 0.0 and first and not e.dead and e.elite and not e.boss:
		o.add_cc_growth(e, float(tyd.root))
	if first and not tyd.get("rain", false) and not tyd.get("echo", false):
		var rip := _ty_one(o, "verb.ty_ripple")
		if not rip.is_empty():
			_ty_splash(o, e.pos, float(rip.get("r", 60.0)), float(bu.dmg) * float(rip.get("mult", 0.35)), e, str(rip.get("src", "")))
			ncue(o, {"p": e.pos, "shape": "ring", "r": float(rip.get("r", 60.0)), "c": TY_VIOLET, "life": 0.22})
	var pin_b := _ty_one(o, "verb.ty_pin")
	if not pin_b.is_empty():
		if tyd.get("pin", false) and first and not e.dead:
			_ty_pin(o, e, pin_b)
		elif float(e.get("ty_pin_t", 0.0)) > g.t and not tyd.get("echo", false):
			var stake = _ty_stake_of(o, e)
			if stake != null:
				_ty_splash(o, stake.p, float(pin_b.get("r", 90.0)), dealt * float(pin_b.get("echo", 0.4)), e, str(pin_b.get("src", "")))
				stake["pulse"] = g.t
				_FXR.ev(o, "ty_echo", {"at": stake.p, "r": float(pin_b.get("r", 90.0))})
	if e.dead and float(e.get("ty_mp", 0.0)) > g.t:
		var hb := _ty_one(o, "verb.ty_herd")
		if not hb.is_empty():
			e["ty_mp"] = 0.0
			var dmg: float = o.base("atk", 0.0) * float(hb.get("mult", 0.5)) * float(o.loc.dmg) * o._dmg_bonus()
			var hits := _ty_splash(o, e.pos, float(hb.get("r", 70.0)), dmg, e, str(hb.get("src", "")))
			for h in hits:
				if not h.dead and not h.boss:
					o.add_cc_growth(h, float(hb.get("pause", 0.8)) * (0.5 if h.elite else 1.0))
			ncue(o, {"p": e.pos, "shape": "burst", "r": float(hb.get("r", 70.0)), "r0": 8.0, "c": Color(0.85, 0.95, 1.0), "n": 8, "life": 0.35})


## 范围补伤（不含 ex）：r 内活着的敌人各一下；返回命中列表
static func _ty_splash(o, c: Vector2, r: float, dmg: float, ex, src: String) -> Array:
	var out: Array = []
	if dmg <= 0.0:
		return out
	var ve: float = o.vs_elite()
	for j in o.query_ids(c, r + 24.0):
		var e: Dictionary = o.g.enemies[j]
		if e.dead or e.chest or is_same(e, ex) or e.pos.distance_to(c) > r + float(e.r):
			continue
		out.append(e)
	for e in out:
		o.log_hit(src, ["follow_up", "area"])
		o.deal_damage(e, dmg * (ve if e.elite or e.boss else 1.0))
	return out


# ---------------------------------------------------------------- 精二 钉影

static func _ty_pin(o, e: Dictionary, pb: Dictionary) -> void:
	var g = o.g
	var ty := ty_st(o)
	var dur: float = float(pb.get("dur", 4.0))
	if e.boss:
		o.add_cc(e, -INF, 2.0)   # Boss 不定身，改减速
	else:
		o.add_cc_growth(e, float(pb.get("root", 1.2)) * (0.5 if e.elite else 1.0))
	e["ty_pin_t"] = g.t + dur
	var team: float = float(pb.get("team", 0.0))   # 精二全队效果（docs/402 §2.5，用户 11-21 定①）：被钉住的敌人受到全队伤害 +team（借铃兰 frag 状态，同名取最高）
	if team > 0.0:
		var cur: float = float(e.get("frag_v", 0.0)) if float(e.get("frag_t", 0.0)) > g.t else 0.0
		e["frag_v"] = maxf(cur, team)
		e["frag_t"] = maxf(float(e.get("frag_t", 0.0)), g.t + dur)
	var stakes: Array = ty.stakes
	for s in stakes:
		if is_same(s.e, e):
			s.t = g.t + dur
			s.p = e.pos
			return
	stakes.append({"e": e, "p": e.pos, "t": g.t + dur, "t0": g.t, "pulse": -9.0, "ang": g.vrng.randf_range(-0.35, 0.35)})
	var cap: int = mini(TY_STAKE_MAX, int(pb.get("max", 3)))
	while stakes.size() > cap:
		var old: Dictionary = stakes.pop_front()
		if not old.e.dead:
			old.e["ty_pin_t"] = 0.0
	_FXR.ev(o, "ty_pin", {"e": e, "at": e.pos})


static func _ty_stake_of(o, e: Dictionary):
	for s in ty_st(o).stakes:
		if is_same(s.e, e):
			return s
	return null


# ---------------------------------------------------------------- 每帧 / 瞬时积木

static func ty_tick(o, dt: float) -> void:
	var g = o.g
	var ty := ty_st(o)
	var fang_b := _ty_one(o, "verb.ty_fang")
	if int(ty.fang) > 0 and (fang_b.is_empty() or g.t - float(ty.fang_t) > float(fang_b.get("keep", 4.0))):
		ty.fang = 0
	if not ty.stakes.is_empty():
		ty.stakes = ty.stakes.filter(func(s): return s.t > g.t and not s.e.dead)
		for s in ty.stakes:
			s.p = s.e.pos   # 黑箭钉在影子上：被钉的敌人被击退时影子跟着走
	if int(o.ext.ammo[2]) <= 0 and not ty.hunt.is_empty():
		ty.hunt = {}
		ty.mark = null
	var tb := _ty_one(o, "verb.ty_trap")
	if not tb.is_empty() and _ty_s2_on(o):
		ty.trap_t = float(ty.trap_t) - dt
		if ty.trap_t <= 0.0:
			ty.trap_t = float(tb.get("cd", 5.0))
			var c: Vector2 = o.densest_point(float(tb.get("pick_r", 300.0)), o.pos)
			if c != Vector2.INF:
				ty.traps.append({"p": c, "t": g.t + float(tb.get("dur", 3.0)), "hit": {}})
				while ty.traps.size() > TY_TRAP_MAX:
					ty.traps.pop_front()
				_FXR.ev(o, "ty_trap", {"at": c})
	if not ty.traps.is_empty():
		var keep: Array = []
		for tr in ty.traps:
			if tr.t <= g.t:
				continue
			keep.append(tr)
			var r: float = float(tb.get("r", 60.0)) if not tb.is_empty() else 60.0
			for j in o.query_ids(tr.p, r + 24.0):
				var e: Dictionary = g.enemies[j]
				if e.dead or e.chest or tr.hit.has(e.id) or e.pos.distance_to(tr.p) > r + float(e.r):
					continue
				tr.hit[e.id] = true
				if not e.boss:
					o.add_cc_growth(e, float(tb.get("pause", 1.0)) * (0.5 if e.elite else 1.0))
				var dmg: float = o.base("atk", 0.0) * float(tb.get("mult", 0.6)) * float(o.loc.dmg) * o._dmg_bonus()
				o.log_hit(str(tb.get("src", "")), ["skill", "area"])
				o.deal_damage(e, dmg * (o.vs_elite() if e.elite or e.boss else 1.0))
		ty.traps = keep


static func ty_exec(o, b: Dictionary, _at: Vector2) -> void:
	var ty := ty_st(o)
	match str(b.get("_tag", "")):
		"verb.ty_s2":   # 冰原秩序：第 permanent_after 次起持续时间无限（原作「第二次及以后使用时持续时间无限」）
			ty.s2n = int(ty.s2n) + 1
			var i: int = o.effect_skill if o.effect_skill >= 0 else 1
			if int(ty.s2n) >= int(b.get("permanent_after", 2)):
				o.perm[i] = true
				o.sp[i] = o.sp_need(i)
				o.perm_on[i] = true
				o.s_t[i] = 0.0
		"verb.ty_hunt":
			ty.hunt = b.duplicate()
			ty.mark = null
			var ts := ty_targets(o, 1, _exu_range(o, o.B.get("attack", {})))
			if not ts.is_empty():
				ty.mark = ts[0]
				_FXR.ev(o, "ty_mark", {"e": ts[0], "at": ts[0].pos})


# ---------------------------------------------------------------- 占位画面（转平面 / 正式特效接手前；只画）

static func ty_draw(o) -> void:
	if _FXR.Pxp.owns_id(o.g, str(o.id)):
		return
	var g = o.g
	var ty := ty_st(o)
	var cv = o.cv
	for s in ty.stakes:
		var base: Vector2 = s.p + Vector2(0, 2)
		var top: Vector2 = base + Vector2(0, -22).rotated(float(s.ang))
		cv.draw_line(base, top, TY_BLACK, 3.0)
		cv.draw_line(top, top + Vector2(-3, 4).rotated(float(s.ang)), TY_VIOLET, 2.0)
		var k: float = clampf((g.t - float(s.pulse)) / 0.3, 0.0, 1.0)
		if k < 1.0:
			cv.draw_arc(base, 20.0 + 70.0 * k, 0.0, TAU, 24, Color(TY_VIOLET.r, TY_VIOLET.g, TY_VIOLET.b, 0.6 * (1.0 - k)), 1.5)
	for tr in ty.traps:
		cv.draw_arc(tr.p, 60.0, 0.0, TAU, 24, Color(0.1, 0.06, 0.14, 0.55), 2.0)
		cv.draw_line(tr.p, tr.p + Vector2(0, -18), TY_BLACK, 2.5)
	if ty.mark != null and not ty.mark.dead and not ty.hunt.is_empty():
		var p: Vector2 = ty.mark.pos
		cv.draw_arc(p, float(ty.mark.r) + 10.0, 0.0, TAU, 20, Color(0.95, 0.35, 0.35, 0.8), 1.5)
		cv.draw_line(p + Vector2(-16, 0), p + Vector2(16, 0), Color(0.95, 0.35, 0.35, 0.7), 1.0)
		cv.draw_line(p + Vector2(0, -16), p + Vector2(0, 16), Color(0.95, 0.35, 0.35, 0.7), 1.0)
	var rf: Dictionary = ty.get("rain_fx", _ED)
	if not rf.is_empty() and g.t - float(rf.t) < 0.25:
		var a: float = 1.0 - (g.t - float(rf.t)) / 0.25
		for q in rf.pts:
			cv.draw_line(q + Vector2(-10, -40), q, Color(0.85, 0.85, 0.95, 0.8 * a), 2.0)


static func ty_status_items(o) -> Array:
	var ty := ty_st(o)
	var out: Array = []
	if int(ty.fang) > 0:
		out.append(["锐如兽牙 %d" % int(ty.fang), Color(0.8, 0.7, 1.0)])
	return out


# ---------------------------------------------------------------- 校验（seg_hoshiguma._ext_block 转来）

static func _ty_validate(b: Dictionary, p: String, ctx: Dictionary, tag: String) -> void:
	match tag:
		"verb.ty_hunter":
			_num(b, "guard_r", p, ctx, false, 0.0, 400.0)
		"verb.ty_fang":
			_num(b, "max", p, ctx, true, 1.0, 20.0)
			_num(b, "keep", p, ctx, true, 0.5, 30.0)
			_num(b, "ign", p, ctx, true, 0.0, 1.0)
			_num(b, "elite", p, ctx, true, 0.0, 0.5)
		"verb.ty_mire":
			_num(b, "mult", p, ctx, true, 1.0, 5.0)
			_num(b, "pause", p, ctx, true, 0.0, 5.0)
		"verb.ty_pin":
			_num(b, "every", p, ctx, true, 2.0, 20.0)
			_num(b, "dur", p, ctx, true, 0.5, 20.0)
			_num(b, "root", p, ctx, true, 0.0, 5.0)
			_num(b, "echo", p, ctx, true, 0.0, 2.0)
			_num(b, "r", p, ctx, true, 10.0, 400.0)
			_num(b, "max", p, ctx, true, 1.0, 6.0)
			_num(b, "team", p, ctx, false, 0.0, 0.5)
			_src(b, p, ctx, true)
		"verb.ty_ripple":
			_num(b, "r", p, ctx, true, 10.0, 300.0)
			_num(b, "mult", p, ctx, true, 0.0, 3.0)
			_src(b, p, ctx, true)
		"verb.ty_volley":
			_num(b, "every", p, ctx, true, 2.0, 20.0)
			_num(b, "spread", p, ctx, true, 0.0, 90.0)
		"verb.ty_headhunt":
			_num(b, "cd", p, ctx, true, 1.0, 60.0)
		"verb.ty_herd":
			_num(b, "r", p, ctx, true, 10.0, 300.0)
			_num(b, "mult", p, ctx, true, 0.0, 3.0)
			_num(b, "pause", p, ctx, true, 0.0, 3.0)
			_src(b, p, ctx, true)
		"verb.ty_hh2":
			_num(b, "mult", p, ctx, true, 1.0, 10.0)
			_num(b, "root", p, ctx, true, 0.0, 3.0)
			_src(b, p, ctx, true)
		"verb.ty_trap":
			_num(b, "cd", p, ctx, true, 1.0, 60.0)
			_num(b, "r", p, ctx, true, 10.0, 300.0)
			_num(b, "dur", p, ctx, true, 0.5, 20.0)
			_num(b, "pause", p, ctx, true, 0.0, 3.0)
			_num(b, "mult", p, ctx, true, 0.0, 3.0)
			_num(b, "pick_r", p, ctx, false, 50.0, 800.0)
			_src(b, p, ctx, true)
		"verb.ty_s2":
			_num(b, "permanent_after", p, ctx, true, 1.0, 9.0)
			_num(b, "twin", p, ctx, true, 0.0, 3.0)
			_num(b, "stun_p", p, ctx, true, 0.0, 1.0)
			_num(b, "stun", p, ctx, true, 0.0, 3.0)
			if b.has("src"):
				_src(b, p, ctx, true)
		"verb.ty_hunt":
			_num(b, "n", p, ctx, true, 1.0, 12.0)
			_num(b, "r", p, ctx, true, 10.0, 400.0)
			_num(b, "mult", p, ctx, true, 0.0, 10.0)
			_num(b, "stun", p, ctx, true, 0.0, 3.0)
			_num(b, "hop_r", p, ctx, true, 10.0, 600.0)
			_num(b, "spill", p, ctx, false, 0.0, 1.0)
			_src(b, p, ctx, true)
