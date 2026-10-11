## 干员积木（docs/61）：数据干员（data_operator.gd）的积木编译、校验与共享执行器。
## 只走 op_api / character.gd 的公开方法与 g 的公共状态，不碰 game.gd 内部（下划线函数）、enemies.gd、combat.gd。
## 确定性（docs/36 §3）：本文件不用任何随机数；画面只往干员自己的 pfx 里加粒子（不碰 g.rng）。
## 本文件也被 -s 测试脚本（tests/test_core.gd，经 character.gd 的 validate_operator）加载：不许引用 Sfx 等自动加载。
extends RefCounted

## 已实现的积木（族 → 名）。docs/61 里标 📝 的写在 PLANNED：写了校验会报「已登记未实现」
const IMPL := {
	"shape": ["circle", "cone", "orbit"],
	"verb": ["heal", "lamp", "buff_self", "mode", "sp_team"],
	"aura": ["atk", "aspd", "skill_power", "range"],
	"st": ["stun", "slow", "slow_soft"],
	"trig": ["passive", "every_n", "tick", "on_kill"],
}
const PLANNED := {
	"shape": ["line", "point_aoe", "projectile", "chain", "dash_line", "summon"],
	"verb": ["field", "summon", "shield", "protect", "displace", "cleanse", "dash"],
	"aura": ["heal", "dps", "dr", "inspire"],
	"st": ["fragile", "airborne", "bind", "weightless", "dot", "mark"],
	"trig": ["on_skill_start", "on_hurt", "on_leader_dash", "on_deploy", "stack"],
}
const FAMILIES := ["shape", "verb", "aura", "st", "trig", "custom"]
## 本干员的局部倍率（verb.buff_self 的 stat 取这些时不进 g.stats）
const LOCAL_STATS := ["zone", "dmg", "heal", "interval", "area", "force", "force_lit"]   # area / force / force_lit：安洁莉娜段（落点范围 / 位移距离 / 灯光内位移）
## verb.buff_self 可写进 g.stats 的干员属性（作用域 op:<id>）
const OP_STATS := ["op_atk", "op_aspd", "op_range", "op_skill_power"]
const AURA_STAT := {"atk": "op_atk", "aspd": "op_aspd", "skill_power": "op_skill_power", "range": "op_range"}
const COND_OPS := [">=", "<=", "==", ">", "<"]
## blocks.attack 能用的普攻形状（第三批追加：point_aoe 安洁莉娜、dash_line 德克萨斯、projectile 能天使）
const ATTACK_SHAPES := ["circle", "cone", "point_aoe", "dash_line"]


# ================================================================ 表达式 / 条件（docs/61 §1.2 / §1.3）

## 解析一个数值：数字原样；含 $ 的字符串按「一个操作数」或「操作数 运算 操作数」求值（$key 取 base）。
## 返回 [ok, 值, 错误说明]
static func eval_expr(v, base: Dictionary) -> Array:
	if v is int or v is float:
		return [true, float(v), ""]
	if not (v is String):
		return [false, 0.0, "应为数字或 \"$key\" 表达式，实际是 %s" % type_string(typeof(v))]
	var s: String = v.strip_edges().replace(" ", "")
	if s.is_valid_float():
		return [true, s.to_float(), ""]
	# 找二元运算符（跳过开头的负号）
	var at := -1
	for i in range(1, s.length()):
		if s[i] in ["+", "-", "*", "/"]:
			at = i
			break
	if at < 0:
		return _operand(s, base)
	var l := _operand(s.substr(0, at), base)
	var r := _operand(s.substr(at + 1), base)
	if not l[0]:
		return l
	if not r[0]:
		return r
	match s[at]:
		"+":
			return [true, l[1] + r[1], ""]
		"-":
			return [true, l[1] - r[1], ""]
		"*":
			return [true, l[1] * r[1], ""]
		_:
			if r[1] == 0.0:
				return [false, 0.0, "表达式「%s」除以 0" % s]
			return [true, l[1] / r[1], ""]


static func _operand(s: String, base: Dictionary) -> Array:
	var neg := s.begins_with("-")
	if neg:
		s = s.substr(1)
	var val := 0.0
	if s.is_valid_float():
		val = s.to_float()
	elif s.begins_with("$") and s.length() > 1:
		var k := s.substr(1)
		if not base.has(k):
			return [false, 0.0, "引用的「$%s」不在 base 里" % k]
		var bv = base[k]
		if not (bv is int or bv is float):
			return [false, 0.0, "base.%s 不是数字" % k]
		val = float(bv)
	else:
		return [false, 0.0, "看不懂的操作数「%s」（只支持数字、$key 和一次 + - * / 运算）" % s]
	return [true, -val if neg else val, ""]


## 条件串 → {neg, k, a, op, v}；错误时返回 {"err": 说明}
static func parse_cond(s: String, base: Dictionary) -> Dictionary:
	var c := {"neg": false, "k": "", "a": "", "op": "", "v": 0.0}
	s = s.strip_edges()
	if s.begins_with("!"):
		c.neg = true
		s = s.substr(1).strip_edges()
	if s == "is_leader":
		c.k = "is_leader"
		return c
	if s == "in_zone:leader":
		c.k = "in_zone"
		return c
	if s in EXT_CONDS:   # 各干员段落追加的无参数条件（文件末尾）
		c.k = s
		return c
	if s.begins_with("skill_active:"):
		var n := s.substr(13)
		if not n.is_valid_int() or int(n) < 0 or int(n) > 2:
			return {"err": "skill_active 后面应是技能序号 0–2：「%s」" % s}
		c.k = "skill_active"
		c.v = float(int(n))
		return c
	for op in COND_OPS:
		var i := s.find(op)
		if i <= 0:
			continue
		var lhs := s.substr(0, i).strip_edges()
		var rhs := s.substr(i + op.length()).strip_edges()
		var ev := eval_expr(rhs, base)
		if not ev[0]:
			return {"err": ev[2]}
		c.op = op
		c.v = ev[1]
		if lhs in ["lamp", "hp_pct", "elite"]:
			c.k = lhs
		elif lhs.begins_with("faction:") and lhs.length() > 8:
			c.k = "faction"
			c.a = lhs.substr(8)
		elif lhs.begins_with("class:") and lhs.length() > 6:
			c.k = "class"
			c.a = lhs.substr(6)
		else:
			return {"err": "条件左边只能是 lamp / hp_pct / elite / faction:<阵营> / class:<职业>：「%s」" % s}
		return c
	return {"err": "看不懂的条件「%s」" % s}


## 编译：深拷贝 blocks，含 $ 的值解析成数字，cond 解析成字典，每块积木编上 _uid（常驻积木的累计器按它存）。
## 校验没通过的地方按 0 / 空处理（validate 已报错）
static func compile(def: Dictionary) -> Dictionary:
	var base: Dictionary = def.get("base", {})
	var counter := [0]
	var out = _compile_node(def.get("blocks", {}).duplicate(true), base, counter)
	return out if out is Dictionary else {}


static func _compile_node(n, base: Dictionary, counter: Array):
	if n is Dictionary:
		var o := {}
		for k in n:
			var v = n[k]
			if k == "cond" and v is String:
				var c := parse_cond(v, base)
				o[k] = c if not c.has("err") else {"neg": true, "k": "is_leader", "a": "", "op": "", "v": 0.0, "bad": true}
			elif v is String and "$" in v:
				var ev := eval_expr(v, base)
				o[k] = ev[1]
			else:
				o[k] = _compile_node(v, base, counter)
		for f in FAMILIES:
			if o.has(f):
				counter[0] += 1
				o["_uid"] = counter[0]
				o["_tag"] = "%s.%s" % [f, str(o[f])] if f != "custom" else "custom"
				break
		return o
	if n is Array:
		return n.map(func(x): return _compile_node(x, base, counter))
	return n


## 条件求值（o 是干员实例；data_operator 提供 skill_on / in_zone / zone_ok_r）
static func cond_true(o, c) -> bool:
	if not (c is Dictionary) or c.is_empty():
		return true
	var g = o.g
	var r := true
	match str(c.k):
		"is_leader":
			r = o.is_leader
		"in_zone":
			r = o.in_zone(g.ppos)
		"skill_active":
			r = o.skill_on(int(c.v))
		"lamp":
			r = _cmp(float(g.lamp), c.op, c.v)
		"hp_pct":
			r = _cmp(g.hp / maxf(1.0, g.max_hp), c.op, c.v)
		"elite":
			r = _cmp(float(o.elite), c.op, c.v)
		"faction":
			r = _cmp(float(count_others(o, "faction:" + str(c.a))), c.op, c.v)
		"class":
			r = _cmp(float(count_others(o, "class:" + str(c.a))), c.op, c.v)
		_:
			r = ext_cond_true(o, str(c.k))
	return r != bool(c.neg)


static func _cmp(a: float, op: String, b: float) -> bool:
	match op:
		">=":
			return a >= b
		"<=":
			return a <= b
		">":
			return a > b
		"<":
			return a < b
		"==":
			return a == b
	return false


## 编队里除自己以外满足 who（faction:<阵营> / class:<职业>）的人数
static func count_others(o, who: String) -> int:
	var n := 0
	for m in o.g.squad.ops:
		if m != o and member_is(m, who):
			n += 1
	return n


static func member_is(m, who: String) -> bool:
	if who.begins_with("faction:"):
		return who.substr(8) in m.def.get("faction", [])
	if who.begins_with("class:"):
		return m.cls == who.substr(6)
	return false


# ================================================================ 执行器（瞬时）

## 伤害形状（shape.circle / shape.cone）：o.loc.dmg 是本干员的局部伤害倍率。at：center = target 时的点
static func exec_shape(o, b: Dictionary, at: Vector2 = Vector2.INF) -> Array:
	var g = o.g
	var mult: float = float(b.get("mult", 1.0))
	var dmg: float = o.base(str(b.get("atk_key", "atk")), 0.0) * mult * float(o.loc.dmg) * o._dmg_bonus()
	if b.get("power", false):
		dmg *= o.skill_power()
	var src: String = str(b.get("src", ""))
	var tags: Array = b.get("tags", [])
	var kb: float = float(b.get("kb", 0.0))
	var stun: float = float(b.get("stun", 0.0))
	var max_n: int = int(b.get("max_n", 0))   # 0 = 不设上限
	var hits: Array = []
	var fx_c := Vector2.INF   # 画面帧条（docs/61 §5.6）的位置 / 半径 / 角度
	var fx_r := 0.0
	var fx_a := 0.0
	match str(b.shape):
		"circle":
			var c: Vector2 = shape_center(o, b, at)
			var r: float = shape_radius(o, b)
			if c == Vector2.INF:
				return []
			hits = o.area_hit(src, c, r, dmg, kb, stun, tags, max_n)
			o.fx({"kind": "ring", "pos": c, "r": r, "r0": r * 0.55, "life": 0.32, "col": o.col(), "floor": true, "w": 2.0, "alpha": 0.6})
			fx_c = c
			fx_r = r
		"cone":
			var r2: float = shape_radius(o, b)
			var ts: Array = o.nearest_enemies(1, r2 + 30.0, o.pos)
			var ang: float = o.atk_angle((ts[0].pos - o.pos).angle() if not ts.is_empty() else o.facing_angle())
			hits = o.melee_hit(src, o.pos, ang, deg_to_rad(float(b.get("half_deg", 45.0))), r2, dmg, kb, stun, tags, max_n)
			o.fx({"kind": "ring", "pos": o.pos, "r": r2 * 0.6, "r0": 8.0, "life": 0.25, "col": o.col(), "floor": true, "w": 3.0})
			fx_c = o.pos
			fx_r = r2
			fx_a = ang
		"dash_line":
			return tx_dash_start(o, b, dmg)   # 德克萨斯段：命中逐帧结算，这里只起冲
	for s in b.get("on_hit", []):
		for e in hits:
			apply_status(o, e, s)
	if b.has("fx") and fx_c != Vector2.INF:
		fx_play(o, b.fx, fx_c, fx_r, hits, fx_a)
	return hits


## 命中 / 力场里的状态（st.*，第三批合并时与安洁莉娜段的 status_one 统一）：stun / slow 精英时长减半、Boss 缺省不受（与原 apply_status 逐字节相同）。
## 一名敌人吃一条状态。c / ring / ring_w：within（离 c 不超过）与 where: ring（在环带 ±ring_w 内）的筛选。
## Boss：缺省不受；boss: true 也受（stun ×0.25 / slow 照常）；boss_only: true 只对 Boss
static func apply_status(o, e: Dictionary, s: Dictionary, c := Vector2.INF, ring := -1.0, ring_w := 0.0) -> void:
	if e.dead or not cond_true(o, s.get("cond", {})):
		return
	if e.boss and not (s.get("boss", false) or s.get("boss_only", false)):
		return
	if s.get("boss_only", false) and not e.boss:
		return
	if s.has("within") and c != Vector2.INF and e.pos.distance_to(c) > float(s.within) + float(e.r) * 0.5:
		return
	if str(s.get("where", "")) == "ring" and (ring < 0.0 or absf(e.pos.distance_to(c) - ring) > ring_w):
		return
	var g = o.g
	var k: float = 0.25 if e.boss else (0.5 if e.elite else 1.0)
	match "st." + str(s.get("st", "")):
		"st.stun":
			e.stun = maxf(e.stun, float(s.dur) * k)
		"st.slow":
			e.slow = maxf(e.slow, float(s.dur) * (1.0 if e.boss else k))
		"st.airborne":
			lift(o, e, float(s.dur), float(s.get("h", 26.0)), s)
		"st.weightless":
			if _movable(e):
				var was: float = float(e.get("wl_kb", 1.0)) if float(e.get("wl_t", 0.0)) > g.t else 1.0
				e["wl_t"] = maxf(float(e.get("wl_t", 0.0)), g.t + float(s.dur))
				e["wl_kb"] = maxf(was, float(s.kb_mult))
		"st.dot":
			o.log_hit(str(s.get("src", "")), s.get("tags", []))
			o.deal_damage(e, o.base(str(s.get("atk_key", "atk")), 0.0) * float(s.get("mult", 0.0)) * float(o.loc.dmg) * o._dmg_bonus() * (o.vs_elite() if e.elite or e.boss else 1.0))


static func shape_center(o, b: Dictionary, at: Vector2 = Vector2.INF) -> Vector2:
	match str(b.get("center", "zone")):
		"self":
			return o.pos
		"leader":
			return o.g.ppos
		"target":
			return at
	return o.zone_c()


static func shape_radius(o, b: Dictionary) -> float:
	var r = b.get("r", 0.0)
	if r is String and r == "zone":
		return o.zone_r()
	return float(r) * o.stat(&"op_range")


## 光环的受益者（docs/61 §5.2 scope）
static func aura_members(o, scope: String) -> Array:
	var out: Array = []
	for m in o.g.squad.ops:
		var ok := false
		match scope:
			"squad":
				ok = true
			"others":
				ok = m != o
			"leader":
				ok = m.is_leader
			"in_zone":
				ok = m.pos != Vector2.INF and o.in_zone(m.pos)
			_:
				ok = member_is(m, scope)
		if ok:
			out.append(m)
	return out


# ================================================================ 执行器（常驻）

## st.slow_soft：区域内非 Boss 敌人这一帧的位移退回 pct（不是减速状态）。mem：上一帧结束时的位置（按敌人 id），返回新的 mem
static func slow_soft(o, b: Dictionary, mem: Dictionary) -> Dictionary:
	var g = o.g
	var c: Vector2 = o.zone_c()
	var r: float = o.zone_r()
	var pct: float = float(b.get("pct", 0.0))
	var hit_boss: bool = b.get("boss", false)
	var nm := {}
	if c == Vector2.INF:
		return nm
	for j in o.query_ids(c, r + 20.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or (e.boss and not hit_boss) or e.pos.distance_to(c) > r:
			continue
		if mem.has(e.id):
			var last: Vector2 = mem[e.id]
			e.pos -= (e.pos - last) * pct
		nm[e.id] = e.pos
	return nm


## shape.orbit：区域边缘 n 个绕行判定点（地面椭圆，y × 0.55）。st = {ang, hit: {敌人 id: 下次可再碰的时刻}}
static func orbit_points(o, b: Dictionary, ang: float) -> Array:
	var c: Vector2 = o.zone_c()
	var r: float = shape_radius(o, b)
	var n: int = int(b.get("n", 6))
	var out: Array = []
	if c == Vector2.INF:
		return out
	for k in n:
		var a: float = ang + k * TAU / float(n)
		out.append(c + Vector2(cos(a) * r, sin(a) * r * 0.55))
	return out


static func orbit_tick(o, b: Dictionary, st: Dictionary, dt: float) -> void:
	var g = o.g
	st.ang = float(st.get("ang", 0.0)) + float(b.get("speed", 0.8)) * dt
	var hit: Dictionary = st.get("hit", {})
	st.hit = hit
	var hr: float = float(b.get("hit_r", 16.0))
	var kb: float = float(b.get("kb", 0.0))
	var mult: float = float(b.get("mult", 0.0))
	var cdv: float = float(b.get("cd", 0.5))
	var c: Vector2 = o.zone_c()
	for p in orbit_points(o, b, st.ang):
		for j in o.query_ids(p, hr + 24.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or e.boss or e.pos.distance_to(p) > hr + float(e.r):
				continue
			if float(hit.get(e.id, -1.0)) > g.t:
				continue
			hit[e.id] = g.t + cdv
			if mult > 0.0:
				o.log_hit(str(b.get("src", "")), b.get("tags", []))
				o.deal_damage(e, o.base("atk", 0.0) * mult * float(o.loc.dmg) * o._dmg_bonus())
				if e.dead:
					continue
			if kb > 0.0:
				var d: Vector2 = e.pos - c
				e.kb += (d.normalized() if d.length() > 0.5 else Vector2.RIGHT) * kb * (0.3 if e.elite else 1.0)
	if hit.size() > 64:
		for k in hit.keys():
			if float(hit[k]) <= g.t:
				hit.erase(k)


# ================================================================ 校验（docs/61 §8）

## 校验数据干员的 blocks 段；每条错误 push_error 一行（写明干员与字段路径）。返回是否通过
static func validate(cid: String, d: Dictionary) -> bool:
	var errs: Array = []
	var blocks = d.get("blocks", null)
	if not (blocks is Dictionary):
		errs.append("blocks 必须是对象")
		return _report(cid, errs)
	var base: Dictionary = d.get("base", {})
	var srcs: Dictionary = d.get("hit_sources", {})
	var ctx := {"base": base, "srcs": srcs, "errs": errs, "custom": 0}
	for k in blocks:
		if not k in ["zone", "attack", "trait", "skills", "talent", "progression"]:
			errs.append("blocks.%s：不认识的段（只能是 zone / attack / trait / skills / talent / progression）" % k)
	if blocks.has("zone"):
		var z = blocks.zone
		if not (z is Dictionary):
			errs.append("blocks.zone 必须是对象")
		else:
			if not str(z.get("center", "")) in ["leader", "self"]:
				errs.append("blocks.zone.center 只能是 leader / self")
			_num(z, "r", "blocks.zone", ctx, true)
	var atk = blocks.get("attack", null)
	if not (atk is Dictionary) or not str(atk.get("shape", "")) in ATTACK_SHAPES:
		errs.append("blocks.attack 必须是一个伤害形状（%s）" % " / ".join(ATTACK_SHAPES.map(func(x): return "shape." + x)))
	else:
		_block(atk, "blocks.attack", "attack", ctx)
		_num(atk, "every", "blocks.attack", ctx, true, 0.1)
		_num(atk, "range", "blocks.attack", ctx, false)
	var sk = blocks.get("skills", null)
	var skd: Array = d.get("skills", [])
	if not (sk is Array) or sk.size() != 3:
		errs.append("blocks.skills 必须恰好 3 条（与 skills 一一对应）")
	else:
		for i in 3:
			var p := "blocks.skills[%d]" % i
			var sb = sk[i]
			if not (sb is Dictionary):
				errs.append(p + " 必须是对象")
				continue
			var perm_json: bool = skd.size() > i and skd[i] is Dictionary and skd[i].get("permanent", false)
			var dv = sb.get("dur", 0)
			if dv is String and dv == "permanent":
				if not perm_json:
					errs.append("%s.dur 是 permanent，但 skills[%d] 没写 \"permanent\": true" % [p, i])
			elif dv is Dictionary:
				_v_next_n(sb, p, perm_json, ctx)   # dur.next_n（安洁莉娜段）
			else:
				if perm_json:
					errs.append("skills[%d] 是 permanent，%s.dur 也要写 \"permanent\"" % [i, p])
				var ev := eval_expr(dv, base)
				if not ev[0]:
					errs.append("%s.dur：%s" % [p, ev[2]])
				elif ev[1] < 0.0:
					errs.append("%s.dur 不能为负" % p)
			for k in sb:
				if not (k in ["dur", "do", "fx"] or (k == "attack_patch" and dv is Dictionary)):
					errs.append("%s.%s：技能积木只有 dur / do / fx 三个字段（dur.next_n 另有 attack_patch）" % [p, k])
			if sb.has("fx"):
				_fx(sb.fx, p + ".fx", ctx, "cast")
			_list(sb.get("do", []), p + ".do", "skill", ctx)
	for sec in ["trait", "talent"]:
		var arr = blocks.get(sec, [])
		if not (arr is Array):
			errs.append("blocks.%s 必须是数组" % sec)
			continue
		for i in arr.size():
			_trig(arr[i], "blocks.%s[%d]" % [sec, i], ctx)
	var pg = blocks.get("progression", {})
	if not (pg is Dictionary):
		errs.append("blocks.progression 必须是对象（节点 id → 积木）")
	else:
		var custom_ids: Array = []
		for n in d.get("progression", []):
			if n is Dictionary and n.get("type", "") == "custom":
				custom_ids.append(str(n.get("id", "")))
		for k in pg:
			if not (k in custom_ids or k in ["elite1", "elite2"]):
				errs.append("blocks.progression.%s：不是 progression 里的 custom 节点 id，也不是 elite1 / elite2" % k)
			else:
				_node(pg[k], "blocks.progression." + k, ctx)
		for cid2 in custom_ids:
			if not pg.has(cid2):
				errs.append("progression 的 custom 节点「%s」在 blocks.progression 里没有积木" % cid2)
	if ctx.custom > 2:
		errs.append("custom 逃生口用了 %d 个（每名干员至多 2 个，docs/61 §6）" % ctx.custom)
	return _report(cid, errs)


static func _report(cid: String, errs: Array) -> bool:
	for e in errs:
		push_error("干员 %s 的 %s" % [cid, e])
	return errs.is_empty()


## 成长节点：触发积木，或一块常驻效果积木
static func _node(b, p: String, ctx: Dictionary) -> void:
	if b is Dictionary and b.has("trig"):
		_trig(b, p, ctx)
	else:
		_block(b, p, "sustain", ctx)


static func _trig(b, p: String, ctx: Dictionary) -> void:
	if not (b is Dictionary) or not b.has("trig"):
		ctx.errs.append(p + "：这里要一个触发积木（{\"trig\": …, \"do\": […]}）")
		return
	_block(b, p, "trig", ctx)


static func _list(arr, p: String, kind: String, ctx: Dictionary) -> void:
	if not (arr is Array):
		ctx.errs.append(p + " 必须是数组")
		return
	for i in arr.size():
		_block(arr[i], "%s[%d]" % [p, i], kind, ctx)


## 一块积木。kind：attack（普攻形状）/ skill（技能 do：瞬时 + 常驻都行）/ sustain（常驻列表）/ instant（触发器的 do）/ on_hit（命中状态）/ trig
static func _block(b, p: String, kind: String, ctx: Dictionary) -> void:
	var errs: Array = ctx.errs
	if not (b is Dictionary):
		errs.append(p + " 必须是对象")
		return
	var fams: Array = FAMILIES.filter(func(f): return b.has(f))
	if fams.size() != 1:
		errs.append("%s：每块积木恰好一个族键（shape / verb / aura / st / trig / custom），这里有 %d 个" % [p, fams.size()])
		return
	var fam: String = fams[0]
	if b.has("cond"):
		if not (b.cond is String):
			errs.append(p + ".cond 必须是字符串")
		else:
			var c := parse_cond(b.cond, ctx.base)
			if c.has("err"):
				errs.append("%s.cond：%s" % [p, c.err])
	# 所有 $ 表达式
	for k in b:
		if k != "cond" and b[k] is String and "$" in b[k]:
			var ev := eval_expr(b[k], ctx.base)
			if not ev[0]:
				errs.append("%s.%s：%s" % [p, k, ev[2]])
	if b.has("fx"):
		_fx(b.fx, p + ".fx", ctx, "%s.%s" % [fam, str(b[fam])] if fam != "custom" else "custom")
	if fam == "custom":
		ctx.custom += 1
		if not kind in ["skill", "instant"]:
			errs.append(p + "：custom 只能放在技能或触发器的 do 里（瞬时执行）")
		return
	var nm: String = str(b[fam])
	var tag := "%s.%s" % [fam, nm]
	if tag in SHARED_TAGS:   # 第三批多名干员共用、合并时统一的积木（verb.displace / verb.field / verb.buff_leader，文件末尾「共用积木」段）
		_v_shared(b, p, kind, ctx, tag)
		return
	var xk := ext_kind(tag)   # 星熊段（文件末尾 EXT_BLOCKS）：放置与参数在 _ext_block 里查
	if xk != "":
		_ext_block(b, p, kind, tag, xk, ctx)
		return
	if tag in ANGELINA_TAGS:   # 安洁莉娜段
		_v_angelina(b, p, kind, ctx, tag)
		return
	if nm in TX_IMPL.get(fam, []):   # 德克萨斯段
		_tx_block(b, p, kind, tag, ctx)
		return
	if nm in PLANNED.get(fam, []):
		errs.append("%s：积木「%s」已登记（docs/61 📝）但还没实现" % [p, tag])
		return
	if not nm in IMPL.get(fam, []):
		errs.append("%s：不认识的积木「%s」" % [p, tag])
		return
	# 放的位置
	var instant: bool = tag in ["shape.circle", "shape.cone", "verb.sp_team"] or (tag == "verb.heal" and not b.has("every")) or (tag == "verb.lamp" and b.has("add"))
	var sustained: bool = (not instant and fam != "trig" and fam != "st") or tag == "st.slow_soft"
	match kind:
		"attack":
			pass
		"trig":
			if fam != "trig":
				errs.append("%s：这里要触发积木，不是「%s」" % [p, tag])
				return
		"on_hit":
			if not tag in ["st.stun", "st.slow"]:
				errs.append("%s：on_hit 里只能放 st.stun / st.slow，不能放「%s」" % [p, tag])
				return
		"instant":
			if not instant:
				errs.append("%s：触发器的 do 只执行一次，「%s」是常驻积木，放这里不会生效" % [p, tag])
				return
		"sustain":
			if not sustained:
				errs.append("%s：常驻列表里只能放常驻积木，「%s」是瞬时的（放到技能 do 或 trig.every_n / tick 的 do 里）" % [p, tag])
				return
		"skill":
			if fam == "trig" or tag in ["st.stun", "st.slow"]:
				errs.append("%s：技能 do 里不能放「%s」" % [p, tag])
				return
	match tag:
		"shape.circle", "shape.cone":
			_num(b, "mult", p, ctx, false, -INF, 20.0)
			_num(b, "max_n", p, ctx, false, 1.0, 99.0)
			if not (b.get("r", null) is String and b.r == "zone"):
				_num(b, "r", p, ctx, true)
			if tag == "shape.cone":
				_num(b, "half_deg", p, ctx, true)
				if str(b.get("center", "self")) != "self":
					errs.append(p + ".center：shape.cone 只能以自身为原点")
			elif not str(b.get("center", "zone")) in ["zone", "self", "leader", "target"]:
				errs.append(p + ".center 只能是 zone / self / leader / target")
			_src(b, p, ctx, true)
			_list(b.get("on_hit", []), p + ".on_hit", "on_hit", ctx)
		"shape.orbit":
			_num(b, "n", p, ctx, true, 1.0, 12.0)
			if not (b.get("r", null) is String and b.r == "zone"):
				_num(b, "r", p, ctx, true)
			for k in ["speed", "hit_r", "kb", "cd"]:
				_num(b, k, p, ctx, false)
			_num(b, "mult", p, ctx, false, -INF, 20.0)
			_src(b, p, ctx, _val(b.get("mult", 0.0), ctx.base) > 0.0)
		"verb.heal":
			_num(b, "pct", p, ctx, true, 0.0, 0.2)
			_num(b, "every", p, ctx, false, 0.1)
		"verb.lamp":
			if not (b.has("add") or b.has("per_sec") or b.has("loss_mult")):
				errs.append(p + "：verb.lamp 要写 add / per_sec / loss_mult 之一")
			if b.has("add") and (b.has("per_sec") or b.has("loss_mult")):
				errs.append(p + "：verb.lamp 的 add（瞬时）不能和 per_sec / loss_mult（常驻）写在同一块")
			for k in ["add", "per_sec", "loss_mult"]:
				_num(b, k, p, ctx, false)
		"verb.buff_self":
			var st := str(b.get("stat", ""))
			if not (st in LOCAL_STATS or st in OP_STATS):
				errs.append("%s.stat「%s」只能是 %s" % [p, st, " / ".join(LOCAL_STATS + OP_STATS)])
			if not str(b.get("op", "")) in ["add", "mult"]:
				errs.append(p + ".op 只能是 add / mult")
			_num(b, "value", p, ctx, true)
		"verb.mode":
			if not (b.has("dmg_mult") or b.has("zone_mult") or b.has("interval_mult") or b.has("no_attack")):
				errs.append(p + "：verb.mode 至少写 dmg_mult / zone_mult / interval_mult / no_attack 之一")
			_num(b, "dmg_mult", p, ctx, false, 0.0, 20.0)
			_num(b, "zone_mult", p, ctx, false, 0.0)
			_num(b, "interval_mult", p, ctx, false, 0.05)
		"verb.sp_team":
			_num(b, "pct", p, ctx, true, 0.0, 1.0)
		"aura.atk", "aura.aspd", "aura.skill_power", "aura.range":
			_num(b, "value", p, ctx, true)
			var sc := str(b.get("scope", ""))
			if not (sc in ["squad", "others", "in_zone", "leader"] or ((sc.begins_with("faction:") or sc.begins_with("class:")) and sc.find(":") < sc.length() - 1)):
				errs.append("%s.scope「%s」只能是 squad / others / in_zone / leader / faction:<阵营> / class:<职业>" % [p, sc])
			if b.has("per"):
				var pe := str(b.per)
				if not ((pe.begins_with("faction:") or pe.begins_with("class:")) and pe.find(":") < pe.length() - 1):
					errs.append("%s.per「%s」只能是 faction:<阵营> / class:<职业>" % [p, pe])
				_num(b, "cap", p, ctx, true, 1.0)
		"st.stun", "st.slow":
			_num(b, "dur", p, ctx, true, 0.0, 10.0)
		"st.slow_soft":
			_num(b, "pct", p, ctx, true, 0.0, 0.9)
			if str(b.get("scope", "in_zone")) != "in_zone":
				errs.append(p + ".scope：st.slow_soft 目前只支持 in_zone")
		"trig.passive":
			_list(b.get("do", []), p + ".do", "sustain", ctx)
		"trig.every_n":
			_num(b, "n", p, ctx, true, 1.0)
			_num(b, "delay", p, ctx, false, 0.0)
			_list(b.get("do", []), p + ".do", "instant", ctx)
		"trig.tick":
			_num(b, "every", p, ctx, true, 0.1)
			_list(b.get("do", []), p + ".do", "instant", ctx)
		"trig.on_kill":
			if not str(b.get("filter", "any")) in ["any", "elite", "boss"]:
				errs.append(p + ".filter 只能是 any / elite / boss")
			_list(b.get("do", []), p + ".do", "instant", ctx)


static func _val(v, base: Dictionary) -> float:
	var ev := eval_expr(v, base)
	return ev[1] if ev[0] else 0.0


## 数值参数：必填 / 可选，范围夹紧（docs/61 §8 第 8 条）
static func _num(b: Dictionary, k: String, p: String, ctx: Dictionary, required: bool, lo := -INF, hi := INF) -> void:
	if not b.has(k):
		if required:
			ctx.errs.append("%s 缺参数 %s" % [p, k])
		return
	if b[k] is bool:
		return
	var ev := eval_expr(b[k], ctx.base)
	if not ev[0]:
		if not (b[k] is String and "$" in b[k]):   # $ 表达式的错误已在上面报过
			ctx.errs.append("%s.%s：%s" % [p, k, ev[2]])
		return
	if ev[1] < lo or ev[1] > hi:
		ctx.errs.append("%s.%s = %s 超出范围 [%s, %s]" % [p, k, str(ev[1]), str(lo), str(hi)])


static func _src(b: Dictionary, p: String, ctx: Dictionary, required: bool) -> void:
	var s := str(b.get("src", ""))
	if s == "":
		if required:
			ctx.errs.append(p + " 缺 src（伤害来源名）")
	elif not ctx.srcs.has(s):
		ctx.errs.append("%s.src「%s」没在 hit_sources 里登记" % [p, s])


# ================================================================ 画面帧条 fx（docs/61 §5.6，10-11 加；纯画面，追加式）
## 任何积木（以及 blocks.skills[i] 本身）可以带 "fx": [条目…]，把 game.gd V6_FRAMES 里登记的帧条挂到出手 / 技能发动 / 常驻光环上。
## 不写 fx 的干员画法与原来逐像素相同；fx 只往干员自己的 pfx 里加粒子、散布只用 g.vrng，不碰 g.rng / 玩法状态（同 seed TRACE / BALANCE 不变）。
## 缺图（g.tex 没有这条）时静默跳过，程序画法照旧作底。

const FX_KEYS := ["strip", "vortex", "cond", "at", "layer", "fit", "scale", "max_scale", "n", "spread", "rise", "life", "every", "tint", "anchor", "off", "ang", "rot"]
const FX_LAYERS := ["floor", "over", "add", "behind", "front"]
## 贴身层：画在干员本体的后面 / 前面（draw_body 前后），积木生效期间循环，帧号 = floor(生效秒数 × fps) % 帧数，退出时 FX_BODY_FADE 秒淡出
const FX_BODY := ["behind", "front"]
const FX_BODY_FADE := 0.15
## 放大上限（每个 1x 美术像素至多几个世界像素）：同 render/vfx.gd FX_SCALE_MAX，免得颗粒比人物粗太多；条目可用 max_scale 改
const FX_SCALE_MAX := 3.2
const FX_AT := ["center", "self", "leader", "zone", "hits", "orbit"]
## 只播一次的 fx 宿主（瞬时积木 / 技能发动 / 触发积木）：不能写 every、贴身层、漩涡（§8 第 9 条）。第三批新积木追加在这里
const FX_INSTANT_OWNERS := ["shape.circle", "shape.cone", "cast", "verb.sp_team",
	"shape.line", "verb.displace", "verb.field", "verb.negate_next", "trig.on_hurt", "trig.on_negate"]
## 能写 at = hits 的宿主（带命中列表的伤害形状）
const FX_HITS_OWNERS := ["shape.circle", "shape.cone", "shape.line"]
## 自己在合适的位置播 fx 的积木：data_operator._exec_list 不再按区域中心替它们播
const FX_SELF_PLAY := ["shape.circle", "shape.cone", "shape.line", "verb.displace", "verb.field", "verb.negate_next"]
const ArtS = preload("res://scripts/art.gd")


## 瞬时播放：c / r 是出手形状的中心与半径（技能发动、常驻光环时是区域中心与半径），hits 是本次命中的敌人，ang 是锥形的朝向。
## 带 every 的条目（常驻定时播）和 at = orbit 的条目（绕行体常驻贴图）这里跳过
static func fx_play(o, entries, c: Vector2, r: float, hits: Array = [], ang := 0.0) -> void:
	if not (entries is Array):
		return
	for f in entries:
		if not (f is Dictionary) or float(f.get("every", 0.0)) > 0.0 or str(f.get("at", "center")) == "orbit" or fx_is_hold(f):
			continue
		if cond_true(o, f.get("cond", {})):
			fx_spawn(o, f, c, r, hits, ang)


## 常驻积木上带 every 的条目：ts 是这块积木各条目的画面计时（秒，按条目下标），返回新的计时。积木生效的第一帧就播一次
static func fx_tick(o, entries, c: Vector2, r: float, ts: Array, dt: float) -> Array:
	if not (entries is Array):
		return ts
	if ts.size() != entries.size():
		ts = []
		ts.resize(entries.size())
		ts.fill(INF)
	for i in entries.size():
		var f = entries[i]
		if not (f is Dictionary):
			continue
		var ev: float = float(f.get("every", 0.0))
		if ev <= 0.0 or str(f.get("at", "center")) == "orbit" or fx_is_hold(f):
			continue
		ts[i] = float(ts[i]) + dt
		if ts[i] >= ev:
			ts[i] = 0.0 if ts[i] == INF else fmod(ts[i], ev)
			if cond_true(o, f.get("cond", {})):
				fx_spawn(o, f, c, r, [], 0.0)
	return ts


static func fx_spawn(o, f: Dictionary, c: Vector2, r: float, hits: Array, ang: float) -> void:
	var g = o.g
	var name: String = str(f.get("strip", ""))
	if g == null or g.tex.get(name) == null or not g.V6_FRAMES.has(name) or o.pfx.size() > 220:
		return
	var spec: Array = g.V6_FRAMES[name]
	var frames: int = maxi(1, int(spec[0]))
	var fps: float = maxf(1.0, float(spec[1]))
	var pts: Array = []
	match str(f.get("at", "center")):
		"self":
			pts.append(o.pos)
		"leader":
			pts.append(g.ppos)
		"zone":
			pts.append(o.zone_c() if o.has_method("zone_c") else c)
		"hits":
			for e in hits:
				pts.append(e.pos + Vector2(0, -float(e.r) * 0.5))
		_:
			pts.append(c)
	var sc: float = float(f.get("scale", 1.0))
	var fit: float = float(f.get("fit", 0.0))
	sc *= r / fit if fit > 0.0 and r > 0.0 else g.PX
	sc = minf(sc, float(f.get("max_scale", FX_SCALE_MAX)))
	var loop: bool = f.has("life")
	var life: float = float(f.life) if loop else frames / fps
	var tint: Color = Color.WHITE
	var tv = f.get("tint", [])
	if tv is Array and tv.size() >= 3:
		tint = Color(float(tv[0]), float(tv[1]), float(tv[2]), float(tv[3]) if tv.size() > 3 else 1.0)
	var anc := Vector2(-1, -1)
	var av = f.get("anchor", [])
	if av is Array and av.size() == 2:
		anc = Vector2(float(av[0]), float(av[1]))
	var off := Vector2.ZERO
	var ov = f.get("off", [])
	if ov is Array and ov.size() == 2:
		off = Vector2(float(ov[0]), float(ov[1]))
	var rot: float = (ang if f.get("rot", false) else 0.0) + deg_to_rad(float(f.get("ang", 0.0)))
	var layer: String = str(f.get("layer", "over"))
	var spread: float = float(f.get("spread", 0.0)) * r
	var rise: float = float(f.get("rise", 0.0))
	for p in pts:
		if p == Vector2.INF:
			continue
		for k in int(f.get("n", 1)):
			var q: Vector2 = p + off
			if spread > 0.0:
				var a: float = g.vrng.randf() * TAU
				var d: float = sqrt(g.vrng.randf()) * spread
				q += Vector2(cos(a) * d, sin(a) * d * 0.55)   # 地面椭圆（同区域画法 y × 0.55）
			var px := {"kind": "strip", "name": name, "pos": q, "life": life, "sc": sc, "col": tint, "ang": rot, "anc": anc,
				"fr": frames, "fps": fps, "loop": loop, "ph": g.vrng.randi_range(0, frames - 1) if loop else 0,
				"floor": layer == "floor", "add": layer == "add"}
			if rise != 0.0:
				px["vel"] = Vector2(0, -rise)
			o.fx(px)


## 画一条 strip 粒子（data_operator._draw_pfx / draw_fx_add 调）。dim：整体透明度（fx_dim）
static func fx_draw(ci, g, f: Dictionary, dim: float) -> void:
	var el: float = float(f.max) - float(f.life)
	var frames: int = int(f.fr)
	var fr: int
	var a: float = dim
	if f.loop:
		fr = (int(el * float(f.fps)) + int(f.ph)) % frames
		a *= clampf(float(f.life) / maxf(0.01, float(f.max) * 0.3), 0.0, 1.0) * clampf(el / 0.08, 0.0, 1.0)   # 循环件：进场 0.08 秒、最后三成淡出
	else:
		fr = mini(int(el * float(f.fps)), frames - 1)
	fx_frame(ci, g, str(f.name), frames, fr, f.pos, float(f.sc), Color(f.col.r, f.col.g, f.col.b, f.col.a * a), f.anc, float(f.ang))


## 帧条的第 fr 帧：sc = 每个 1x 美术像素的世界像素数；anc = 1x 帧内锚点（(-1,-1) = 帧中心），@2x 贴图自动换算（docs/25 §6 的 ×A.hires 规则）
static func fx_frame(ci, g, name: String, frames: int, fr: int, pos: Vector2, sc: float, col: Color, anc := Vector2(-1, -1), ang := 0.0) -> void:
	var tx: Texture2D = g.tex.get(name)
	if tx == null or col.a <= 0.0:
		return
	var h: float = ArtS.hires_of(tx)
	var fw: int = tx.get_width() / frames
	var fh: int = tx.get_height()
	var an: Vector2 = anc * h if anc.x >= 0.0 else Vector2(fw, fh) / 2.0
	ci.draw_set_transform(pos, ang, Vector2(sc / h, sc / h))
	ci.draw_texture_rect_region(tx, Rect2(-an, Vector2(fw, fh)), Rect2(fw * (fr % frames), 0, fw, fh), col)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 常驻跟随条目：贴身层（behind / front）或程序漩涡（vortex），积木生效期间一直画、退出淡出
static func fx_is_hold(f) -> bool:
	return f is Dictionary and (str(f.get("layer", "")) in FX_BODY or f.has("vortex"))


## 积木的 fx 里有没有常驻跟随条目（贴身层 / 漩涡）
static func fx_has_body(entries) -> bool:
	if entries is Array:
		for f in entries:
			if fx_is_hold(f):
				return true
	return false


## fx 条目里有没有一条帧条的贴图在（没有时调用方画程序底）
static func fx_any_tex(o, entries) -> bool:
	if entries is Array:
		for f in entries:
			if f is Dictionary and o.g.tex.get(str(f.get("strip", ""))) != null and cond_true(o, f.get("cond", {})):
				return true
	return false


## 积木的 fx 里有没有漩涡条目（退出淡出用 FX_VORTEX_FADE）
static func fx_has_vortex(entries) -> bool:
	if entries is Array:
		for f in entries:
			if f is Dictionary and f.has("vortex"):
				return true
	return false


# ---------------------------------------------------------------- 程序漩涡 vortex（docs/61 §5.6，10-11 加；纯画面）
## 用户 10-11 对照原作 S3：大片、柔和、半透明的青色水流漩涡铺在地面上（覆盖区域，不贴身），细细的弧形水流线绕着转、
## 零星光点、少量暗红流线点缀，整体低饱和低透明，战场与单位看得清。
## 写法：常驻积木的 fx 条目 {"vortex": {参数…}, "layer": "floor" | "add", "at": "zone" | "self" | "leader", "cond", "tint"}。
## 画法：n 条流线 = 透视椭圆（y × 0.55）上的螺旋弧，各自从外圈慢慢卷向内圈（生命周期 sin 包络淡入淡出）、沿弧两端渐隐、内圈转得快；
## 加 motes 个上飘闪烁的小光点，中心一团柔光、整片一层极淡的水色底。全部攒成一组三角形（顶点色）一次提交（合批，docs/50）。
## 每条流线 / 光点的随机常数在积木生效后第一次画时用 g.vrng 生成并缓存在贴身层记录里（不碰 g.rng）；运动只看 g.t。
const FX_VORTEX_FADE := 0.4
const VORTEX_DEF := {
	"n": 32,              # 流线条数（≤ 64）
	"r": 1.0,             # 外半径 = 区域半径 × r
	"max_r": 520.0,       # 外半径上限（世界像素）
	"r0": 0.12,           # 流线卷到的最内圈（外半径的比例）
	"len": 1.3,           # 每条流线的弧长（弧度）
	"curl": 0.22,         # 尾端比头端外扩多少（外半径比例）：螺旋感
	"spin": 0.55,         # 角速度（弧度 / 秒，外圈；内圈按 1 / (0.35 + 0.65 rf) 加快）
	"drift": 0.10,        # 向内卷的速度（每秒走完生命周期的几分之几）
	"w": 1.6,             # 线宽（世界像素，中段；两端收细）
	"a": 0.3,             # 流线最大透明度
	"col": [0.55, 0.92, 1.0],    # 主色（青）
	"acc": [0.95, 0.32, 0.42],   # 点缀色（暗红）
	"acc_n": 4,           # 点缀流线条数
	"acc_a": 0.55,        # 点缀流线透明度系数（相对 a）
	"seg": 8,             # 每条流线分几段
	"halo": 0.0,          # 软边：再画一遍宽 halo 倍、透明度 halo_a 倍的淡线（0 = 不画；约多一倍顶点）
	"halo_a": 0.25,
	"motes": 24,          # 光点个数（≤ 64）
	"mote_a": 0.55,       # 光点最大透明度
	"mote_sz": 2.0,       # 光点边长（世界像素）
	"mote_rise": 18.0,    # 光点上飘高度（世界像素，一个周期）
	"glow": 0.12,         # 中心柔光透明度（0 = 不画）
	"glow_r": 0.3,        # 中心柔光半径（外半径比例）
	"fill": 0.05,         # 整片水色底透明度（0 = 不画）
	"ring": 1.0,          # 区域椭圆边线透明度倍率（< 1 把程序硬边压淡；取所有生效漩涡的最小值）
	"sy": 0.55,           # 透视压扁（同区域椭圆）
}
const VORTEX_LIM := {"n": [0, 64], "r": [0.05, 3.0], "max_r": [16.0, 2000.0], "r0": [0.0, 0.95], "len": [0.1, 6.3], "curl": [-1.0, 1.0],
	"spin": [-8.0, 8.0], "drift": [0.0, 2.0], "w": [0.5, 8.0], "a": [0.0, 1.0], "halo": [0.0, 8.0], "halo_a": [0.0, 1.0], "acc_n": [0, 64], "acc_a": [0.0, 2.0], "seg": [2, 24],
	"motes": [0, 64], "mote_a": [0.0, 1.0], "mote_sz": [0.5, 8.0], "mote_rise": [-200.0, 200.0], "glow": [0.0, 1.0], "glow_r": [0.0, 1.0],
	"fill": [0.0, 1.0], "ring": [0.0, 1.0], "sy": [0.1, 1.0]}


static func _vp(v: Dictionary, k: String):
	return v.get(k, VORTEX_DEF[k])


static func _vcol(v: Dictionary, k: String) -> Color:
	var a = v.get(k, VORTEX_DEF[k])
	return Color(float(a[0]), float(a[1]), float(a[2])) if a is Array and a.size() >= 3 else Color.WHITE


## 区域椭圆边线的透明度倍率：e 是贴身层记录（data_operator._fxb 的值）
static func vortex_ring_mul(o, e: Dictionary) -> float:
	var m := 1.0
	for f in e.b.fx:
		if f is Dictionary and f.has("vortex") and cond_true(o, f.get("cond", {})):
			m = minf(m, float(_vp(f.vortex, "ring")))
	return m


## 画 e（贴身层记录 {b, el, fade, fl}）上 layer 层的漩涡条目。alpha：积木进出的淡入淡出；sink：带 add_tris 的合批画布或 CanvasItem
static func fx_vortex(sink, o, e: Dictionary, layer: String, alpha: float, c_zone: Vector2, r_zone: float) -> void:
	var g = o.g
	var fx_arr = e.b.fx
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var t: float = float(g.t)
	if not e.has("vx"):
		e["vx"] = {}
		e["va"] = {}
		e["vt"] = t
	var dt: float = clampf(t - float(e.vt), 0.0, 0.1)
	e.vt = t
	for i in fx_arr.size():
		var f = fx_arr[i]
		if not (f is Dictionary) or not f.has("vortex") or str(f.get("layer", "floor")) != layer:
			continue
		# 条目条件切换时 0.35 秒交叉淡入淡出（例：歌域漩涡在 S3 期间让位给 S3 漩涡）
		var want: float = 1.0 if cond_true(o, f.get("cond", {})) else 0.0
		var ca: float = float(e.va.get(i, want))
		ca = move_toward(ca, want, dt / 0.35)
		e.va[i] = ca
		var al: float = alpha * ca * float(g.world.fx_dim)
		var tv = f.get("tint", [])
		var tint := Color.WHITE
		if tv is Array and tv.size() >= 3:
			tint = Color(float(tv[0]), float(tv[1]), float(tv[2]), float(tv[3]) if tv.size() > 3 else 1.0)
		al *= tint.a
		if al <= 0.004:
			continue
		var v: Dictionary = f.vortex
		var c: Vector2 = c_zone
		match str(f.get("at", "zone")):
			"self":
				c = o.pos
			"leader":
				c = g.ppos
		var ov = f.get("off", [])
		if ov is Array and ov.size() == 2:
			c += Vector2(float(ov[0]), float(ov[1]))
		if c == Vector2.INF:
			continue
		var R: float = minf(r_zone * float(_vp(v, "r")), float(_vp(v, "max_r")))
		if R <= 1.0:
			continue
		var n: int = int(_vp(v, "n"))
		var acc_n: int = mini(int(_vp(v, "acc_n")), n)
		var nm: int = int(_vp(v, "motes"))
		if not e.vx.has(i):
			# 随机常数（g.vrng）：流线 [基角, 相位, 弧长倍率, 透明度倍率, 速度倍率, 线宽倍率]，光点 [角, 半径比例, 相位, 速度, 闪烁相位]
			var sl: Array = []
			for k in n:
				sl.append([g.vrng.randf() * TAU, g.vrng.randf(), g.vrng.randf_range(0.6, 1.4), g.vrng.randf_range(0.45, 1.0),
					g.vrng.randf_range(0.75, 1.3), g.vrng.randf_range(0.6, 1.25)])
			var ml: Array = []
			for k in nm:
				ml.append([g.vrng.randf() * TAU, sqrt(g.vrng.randf()) * 0.95, g.vrng.randf(), g.vrng.randf_range(0.15, 0.4), g.vrng.randf() * TAU,
					2.0 if g.vrng.randf() < 0.3 else 1.0])
			e.vx[i] = [sl, ml]
		var sl2: Array = e.vx[i][0]
		var ml2: Array = e.vx[i][1]
		var sy: float = float(_vp(v, "sy"))
		var col: Color = _vcol(v, "col") * Color(tint.r, tint.g, tint.b, 1.0)
		var acc: Color = _vcol(v, "acc") * Color(tint.r, tint.g, tint.b, 1.0)
		# 整片水色底 + 中心柔光：径向扇形（中心 → glow_r → 外缘），顶点色插值成软边
		var fill: float = float(_vp(v, "fill")) * al
		var glow: float = float(_vp(v, "glow")) * al
		if fill > 0.002 or glow > 0.002:
			var gr: float = R * float(_vp(v, "glow_r"))
			var segc := 28
			var b0: int = pts.size()
			pts.append(c)
			cols.append(Color(col.r, col.g, col.b, glow + fill))
			for q in segc:
				var d := Vector2(cos(q * TAU / segc), sin(q * TAU / segc) * sy)
				pts.append(c + d * gr)
				cols.append(Color(col.r, col.g, col.b, fill))
				pts.append(c + d * R)
				cols.append(Color(col.r, col.g, col.b, 0.0))
			for q in segc:
				var q1: int = (q + 1) % segc
				var i0: int = b0 + 1 + q * 2
				var i1: int = b0 + 1 + q1 * 2
				idx.append_array([b0, i0, i1, i0, i0 + 1, i1 + 1, i0, i1 + 1, i1])
		# 流线
		var r0: float = float(_vp(v, "r0"))
		var ln: float = float(_vp(v, "len"))
		var curl: float = float(_vp(v, "curl"))
		var spin: float = float(_vp(v, "spin"))
		var drift: float = float(_vp(v, "drift"))
		var w: float = float(_vp(v, "w"))
		var amax: float = float(_vp(v, "a")) * al
		var acc_a: float = float(_vp(v, "acc_a"))
		var seg: int = int(_vp(v, "seg"))
		var halo: float = float(_vp(v, "halo"))
		var halo_a: float = float(_vp(v, "halo_a"))
		var dir: float = 1.0 if spin >= 0.0 else -1.0
		for k in n:
			var s: Array = sl2[k]
			var u: float = fposmod(float(s[1]) + t * drift * float(s[4]), 1.0)
			var env: float = sin(u * PI)
			var aa: float = amax * float(s[3]) * env
			if aa <= 0.004:
				continue
			var rf: float = lerpf(1.0, r0, u)
			var a0: float = float(s[0]) + spin * t * float(s[4]) / (0.35 + 0.65 * rf)
			var cc: Color = acc if k < acc_n else col
			if k < acc_n:
				aa *= acc_a
			var L: float = ln * float(s[2]) * (0.6 + 0.4 * rf)
			var ww: float = w * float(s[5])
			var cp := PackedVector2Array()   # 中心线与法向（近似取径向：流线大致沿切向）
			var cn := PackedVector2Array()
			var pr := PackedFloat32Array()   # 沿线包络：两端渐隐、中段最亮
			for q in seg + 1:
				var sq: float = float(q) / seg
				var ang: float = a0 - dir * L * (1.0 - sq)          # 头（sq = 1）在前，尾在后
				var rr: float = R * (rf + curl * (1.0 - sq) * rf)    # 尾端更靠外：螺旋
				var ca2: float = cos(ang)
				var sa2: float = sin(ang)
				cp.append(c + Vector2(ca2 * rr, sa2 * rr * sy))
				cn.append(Vector2(ca2, sa2 * sy).normalized())
				pr.append(sin(sq * PI))
			# 两遍：halo（宽、很淡，软边水光）→ 芯线（细、亮）
			for pass_i in 2:
				var pw: float = ww * (halo if pass_i == 0 else 1.0)
				var pa: float = aa * (halo_a if pass_i == 0 else 1.0)
				if pass_i == 0 and (halo <= 0.0 or halo_a <= 0.0):
					continue
				var b1: int = pts.size()
				for q in seg + 1:
					var nrm: Vector2 = cn[q] * (pw * 0.5 * (0.35 + 0.65 * pr[q]))
					var va: float = pa * pow(pr[q], 0.7) if q > 0 and q < seg else 0.0
					pts.append(cp[q] - nrm)
					pts.append(cp[q] + nrm)
					var vc := Color(cc.r, cc.g, cc.b, va)
					cols.append(vc)
					cols.append(vc)
				for q in seg:
					var j: int = b1 + q * 2
					idx.append_array([j, j + 1, j + 3, j, j + 3, j + 2])
		# 光点：跟着漩涡慢转、上飘、闪烁（mote_sz 见方的小方块，三成是两倍大，像素风）
		var ma: float = float(_vp(v, "mote_a")) * al
		var msz: float = float(_vp(v, "mote_sz"))
		var mrise: float = float(_vp(v, "mote_rise"))
		var mcol: Color = Color(minf(col.r * 1.3, 1.0), minf(col.g * 1.15, 1.0), 1.0)
		for k in nm:
			var m: Array = ml2[k]
			var ph: float = fposmod(float(m[2]) + t * float(m[3]), 1.0)
			var am: float = ma * sin(ph * PI) * (0.6 + 0.4 * sin(t * 5.0 + float(m[4])))
			if am <= 0.004:
				continue
			var ang2: float = float(m[0]) + spin * 0.6 * t
			var rm: float = R * float(m[1])
			var mp := c + Vector2(cos(ang2) * rm, sin(ang2) * rm * sy - ph * mrise)
			mp = mp.round()
			var ms: float = msz * float(m[5])
			var b2: int = pts.size()
			pts.append_array([mp, mp + Vector2(ms, 0), mp + Vector2(ms, ms), mp + Vector2(0, ms)])
			var mc := Color(mcol.r, mcol.g, mcol.b, am)
			cols.append_array([mc, mc, mc, mc])
			idx.append_array([b2, b2 + 1, b2 + 2, b2, b2 + 2, b2 + 3])
	if idx.is_empty():
		return
	if sink != null and sink.has_method("add_tris"):
		sink.add_tris(pts, cols, idx)
	else:
		RenderingServer.canvas_item_add_triangle_array(sink.get_canvas_item(), idx, pts, cols)


## 校验漩涡参数（§8 第 9 条）
static func _fx_vortex_check(v, q: String, ctx: Dictionary) -> void:
	var errs: Array = ctx.errs
	if not (v is Dictionary):
		errs.append(q + ".vortex 必须是对象（参数见 docs/61 §5.6 漩涡表）")
		return
	for k in v:
		if not VORTEX_DEF.has(k):
			errs.append("%s.vortex.%s：不认识的漩涡参数（只能是 %s）" % [q, k, " / ".join(VORTEX_DEF.keys())])
		elif k in ["col", "acc"]:
			var a = v[k]
			if not (a is Array) or a.size() != 3 or a.any(func(x): return not (x is int or x is float)):
				errs.append("%s.vortex.%s 必须是 3 个数字的数组" % [q, k])
		elif VORTEX_LIM.has(k):
			_num(v, k, q + ".vortex", ctx, false, float(VORTEX_LIM[k][0]), float(VORTEX_LIM[k][1]))


## 贴身层（behind / front）：锚点对准干员脚底 o.pos（+ off），el = 积木已生效秒数，alpha 用于退出淡出
static func fx_body(ci, o, entries, el: float, alpha: float, front: bool) -> void:
	var g = o.g
	if not (entries is Array) or o.pos == Vector2.INF:
		return
	for f in entries:
		if not (f is Dictionary) or str(f.get("layer", "")) != ("front" if front else "behind") or not cond_true(o, f.get("cond", {})):
			continue
		var name: String = str(f.get("strip", ""))
		if g.tex.get(name) == null or not g.V6_FRAMES.has(name):
			continue
		var spec: Array = g.V6_FRAMES[name]
		var frames: int = maxi(1, int(spec[0]))
		var tv = f.get("tint", [])
		var col := Color.WHITE
		if tv is Array and tv.size() >= 3:
			col = Color(float(tv[0]), float(tv[1]), float(tv[2]), float(tv[3]) if tv.size() > 3 else 1.0)
		col.a *= alpha * g.world.fx_dim
		var ov = f.get("off", [])
		var off: Vector2 = Vector2(float(ov[0]), float(ov[1])) if ov is Array and ov.size() == 2 else Vector2.ZERO
		var av = f.get("anchor", [])
		var anc: Vector2 = Vector2(float(av[0]), float(av[1])) if av is Array and av.size() == 2 else Vector2(-1, -1)
		fx_frame(ci, g, name, frames, int(floor(el * float(spec[1]))) % frames, o.pos + off, float(f.get("scale", 1.0)) * g.PX, col, anc, deg_to_rad(float(f.get("ang", 0.0))))


## shape.orbit 上 at = orbit 的条目：每个判定点画一个循环帧条（代替缺省的小菱形）。返回是否画了（缺图时 false，调用方画菱形）
static func fx_orbit(ci, o, b: Dictionary, pts: Array, dim: float) -> bool:
	var g = o.g
	var drew := false
	for f in b.get("fx", []):
		if not (f is Dictionary) or str(f.get("at", "")) != "orbit" or not cond_true(o, f.get("cond", {})):
			continue
		var name: String = str(f.get("strip", ""))
		if g.tex.get(name) == null or not g.V6_FRAMES.has(name):
			continue
		var spec: Array = g.V6_FRAMES[name]
		var frames: int = maxi(1, int(spec[0]))
		var sc: float = float(f.get("scale", 1.0)) * g.PX
		var tv = f.get("tint", [])
		var col := Color.WHITE
		if tv is Array and tv.size() >= 3:
			col = Color(float(tv[0]), float(tv[1]), float(tv[2]), float(tv[3]) if tv.size() > 3 else 1.0)
		col.a *= dim
		var ov = f.get("off", [])
		var off: Vector2 = Vector2(float(ov[0]), float(ov[1])) if ov is Array and ov.size() == 2 else Vector2.ZERO
		var anc := Vector2(-1, -1)
		var av = f.get("anchor", [])
		if av is Array and av.size() == 2:
			anc = Vector2(float(av[0]), float(av[1]))
		for k in pts.size():
			fx_frame(ci, g, name, frames, int(g.t * float(spec[1])) + k, pts[k] + off, sc, col, anc)
		drew = true
	return drew


## 校验 fx 列表（docs/61 §8 第 9 条）。owner：所属积木的「族.名」，技能本身是 "cast"
static func _fx(arr, p: String, ctx: Dictionary, owner: String) -> void:
	var errs: Array = ctx.errs
	if not (arr is Array):
		errs.append(p + " 必须是数组（fx 条目列表）")
		return
	if arr.size() > 8:
		errs.append("%s：一块积木至多 8 个 fx 条目，这里有 %d 个" % [p, arr.size()])
	var instant_owner: bool = owner in FX_INSTANT_OWNERS
	for i in arr.size():
		var q := "%s[%d]" % [p, i]
		var f = arr[i]
		if not (f is Dictionary):
			errs.append(q + " 必须是对象")
			continue
		for k in f:
			if not k in FX_KEYS:
				errs.append("%s.%s：fx 条目不认识的字段（只能是 %s）" % [q, k, " / ".join(FX_KEYS)])
		var sn = f.get("strip", null)
		if f.has("vortex"):
			# 程序漩涡：不用帧条；常驻跟随（同贴身层），只能挂在常驻积木上；层只能 floor / add；at 只能 zone / self / leader
			_fx_vortex_check(f.vortex, q, ctx)
			if f.has("strip"):
				errs.append(q + "：vortex 条目是程序画法，不写 strip")
			if instant_owner:
				errs.append(q + ".vortex 是常驻漩涡，只能挂在常驻积木上（光环、技能 do 里的常驻积木等）")
			if not str(f.get("layer", "floor")) in ["floor", "add"]:
				errs.append(q + ".layer：vortex 只能是 floor / add")
			if not str(f.get("at", "zone")) in ["zone", "self", "leader"]:
				errs.append(q + ".at：vortex 只能是 zone / self / leader")
			for k in ["every", "life", "n", "spread", "rise", "fit", "scale", "max_scale", "anchor", "ang", "rot"]:
				if f.has(k):
					errs.append("%s.%s：vortex 条目不写这个字段（参数写进 vortex 对象）" % [q, k])
		elif not (sn is String) or not (sn.begins_with("fx_") or sn.begins_with("proj_")):
			errs.append(q + ".strip 必须是 V6_FRAMES 里登记的帧条名（fx_* / proj_*）")
		if not str(f.get("layer", "over")) in FX_LAYERS:
			errs.append("%s.layer 只能是 %s" % [q, " / ".join(FX_LAYERS)])
		var at := str(f.get("at", "center"))
		if not at in FX_AT:
			errs.append("%s.at 只能是 %s" % [q, " / ".join(FX_AT)])
		elif at == "orbit" and owner != "shape.orbit":
			errs.append(q + ".at = orbit 只能挂在 shape.orbit 上")
		elif at == "hits" and not owner in FX_HITS_OWNERS:
			errs.append(q + ".at = hits 只能挂在伤害形状（shape.circle / shape.cone）上")
		if str(f.get("layer", "")) in FX_BODY:
			if instant_owner:
				errs.append(q + ".layer = behind / front 是贴身常驻层，只能挂在常驻积木上（技能 do 里的常驻积木、光环等）")
			if f.has("every") or f.has("life") or f.has("n") or f.has("spread") or f.has("rise"):
				errs.append(q + "：贴身层（behind / front）跟着积木生效循环，不写 every / life / n / spread / rise")
			if at != "self" and f.has("at"):
				errs.append(q + ".at：贴身层只能是 self（干员脚底）")
		if f.has("every") and instant_owner:
			errs.append(q + ".every：瞬时积木 / 技能发动只播一次，every 只能写在常驻积木上")
		if f.has("cond"):
			if not (f.cond is String):
				errs.append(q + ".cond 必须是字符串")
			else:
				var c := parse_cond(f.cond, ctx.base)
				if c.has("err"):
					errs.append("%s.cond：%s" % [q, c.err])
		_num(f, "fit", q, ctx, false, 1.0, 512.0)
		_num(f, "scale", q, ctx, false, 0.05, 8.0)
		_num(f, "max_scale", q, ctx, false, 0.5, 16.0)
		_num(f, "n", q, ctx, false, 1.0, 16.0)
		_num(f, "spread", q, ctx, false, 0.0, 1.5)
		_num(f, "rise", q, ctx, false, -400.0, 400.0)
		_num(f, "life", q, ctx, false, 0.05, 5.0)
		_num(f, "every", q, ctx, false, 0.05, 60.0)
		_num(f, "ang", q, ctx, false)
		for k in f:
			if k != "cond" and f[k] is String and "$" in f[k]:
				var ev := eval_expr(f[k], ctx.base)
				if not ev[0]:
					errs.append("%s.%s：%s" % [q, k, ev[2]])
		for k in [["tint", 3, 4], ["anchor", 2, 2], ["off", 2, 2]]:
			if f.has(k[0]):
				var v = f[k[0]]
				if not (v is Array) or v.size() < k[1] or v.size() > k[2] or v.any(func(x): return not (x is int or x is float)):
					errs.append("%s.%s 必须是 %d%s 个数字的数组" % [q, k[0], k[1], "" if k[1] == k[2] else "–%d" % k[2]])

# ================================================================ 星熊 hoshiguma（docs/59 §3，docs/61「星熊」节）：格挡 / 反击 / 击退 / 直线斩 / 地面区域
## 第一位用到这些积木的是星熊，积木本身是通用的（任何数据干员都能写）。后来的干员追加积木：另起自己的段落，把名字登进 EXT_BLOCKS / EXT_CONDS，
## 校验写进 _ext_block 的 match，执行写进 data_operator.gd 末尾对应的段落。
## 确定性：只有 trig.on_hurt 的概率用 g.rng，且只在该触发器生效、概率在 (0, 1) 之间时才取数（不带这些积木的干员一个随机数都不多取）。

## 族.名 → 放置类别：instant = 瞬时（技能 do、触发器 do、区域 do）；sustain = 常驻（技能 do、passive do、成长节点）；
## skill = 只能放技能 do；trig = 触发积木（trait / talent / 成长节点）
const EXT_BLOCKS := {
	"shape.line": "instant",          # 直线斩：从自身朝最近目标（手动普攻按 A 方向）长 len、宽 width 的矩形，命中沿线全部
	# verb.displace / verb.field 与安洁莉娜共用，合并时统一到文件末尾「共用积木」段（SHARED_TAGS）
	"verb.negate_next": "skill",      # 技能持续期间，主控下一次受到的攻击完全格挡（on_block）；持续结束仍没挨打则执行 on_miss
	"verb.dr": "sustain",             # 主控受到的伤害 × (1 - value)（经 dmg_taken_mult）
	"verb.negate_chance": "sustain",  # 本干员带 negate 的 trig.on_hurt 概率：(chance + Σadd) × Πmult
	"verb.swap_attack": "sustain",    # 生效期间普攻换成 attack 里的形状（节奏仍按 blocks.attack.every）
	"trig.on_hurt": "trig",           # 主控将受到一次攻击（闪避 / 护盾之后）：chance / boss_chance 概率执行 do；negate = 这一下完全格挡
	"trig.on_negate": "trig",         # 本干员格挡了一次攻击（negate_next 或带 negate 的 on_hurt）
}
## 无参数条件
const EXT_CONDS := ["beacon_charging"]   # 主控正在给灯标读条（run/beacon.gd charging）
const FIELD_CENTERS := ["self", "leader", "target", "zone", "last_hit"]


static func ext_kind(tag: String) -> String:
	return str(EXT_BLOCKS.get(tag, ""))


static func ext_cond_true(o, k: String) -> bool:
	match k:
		"beacon_charging":
			return o.g.beacon_sys != null and o.g.beacon_sys.charging != null
	return false


## 线段判定（纯几何，测试可直接调）：敌人圆心 + 半径与「origin 起、方向 d、长 L、宽 W」的矩形相交
static func line_contains(origin: Vector2, d: Vector2, L: float, W: float, p: Vector2, er: float) -> bool:
	var rel: Vector2 = p - origin
	var along: float = rel.dot(d)
	if along < -er or along > L + er:
		return false
	return absf(rel.cross(d)) <= W * 0.5 + er


## trig.on_hurt 的生效概率：Boss 来源有 boss_chance 时用它；negate 触发器再吃 verb.negate_chance 的 add / mult；夹到 [0, max_chance]
static func hurt_chance(t: Dictionary, boss: bool, add: float, mul: float) -> float:
	var p: float = float(t.get("chance", 1.0))
	if boss and t.has("boss_chance"):
		p = float(t.boss_chance)
	if t.get("negate", false):
		p = (p + add) * mul
	return clampf(p, 0.0, float(t.get("max_chance", 1.0)))


## 概率判定：0 / 1 不取随机数（确定性：概率为常数 1 的触发器不改变 g.rng 序列）
static func roll(g, p: float) -> bool:
	if p >= 1.0:
		return true
	if p <= 0.0:
		return false
	return g.rng.randf() < p


## shape.line：返回命中列表。伤害口径同 exec_shape（base[atk_key] × mult × 局部 dmg × _dmg_bonus [× skill_power]，精英 / Boss × vs_elite）；
## 击退沿斩击方向；画面走通用 fx（中心 = 线段中点，半径 = 半长，例：fit 32 = 原「按 len / 64 缩放」）
static func exec_line(o, b: Dictionary) -> Array:
	var g = o.g
	var L: float = float(b.get("len", 0.0)) * o.stat(&"op_range")
	var W: float = float(b.get("width", 40.0))
	var ts: Array = o.nearest_enemies(1, L + 20.0, o.pos)
	var ang: float = o.atk_angle((ts[0].pos - o.pos).angle() if not ts.is_empty() else o.facing_angle())
	var d := Vector2.from_angle(ang)
	var hits: Array = []
	for j in o.query_ids(o.pos + d * L * 0.5, L * 0.5 + W + 40.0):
		var e: Dictionary = g.enemies[j]
		if not e.dead and line_contains(o.pos, d, L, W, e.pos, float(e.r)):
			hits.append(e)
	var max_n: int = int(b.get("max_n", 0))
	if max_n > 0 and hits.size() > max_n:
		hits = o.cap_targets(hits, o.pos, max_n)
	var dmg: float = o.base(str(b.get("atk_key", "atk")), 0.0) * float(b.get("mult", 1.0)) * float(o.loc.dmg) * o._dmg_bonus()
	if b.get("power", false):
		dmg *= o.skill_power()
	var src: String = str(b.get("src", ""))
	var tags: Array = b.get("tags", [])
	var kb: float = float(b.get("kb", 0.0))
	var stun: float = float(b.get("stun", 0.0))
	var ve: float = o.vs_elite()
	for e in hits:
		o.log_hit(src, tags)
		o.deal_damage(e, dmg * (ve if e.elite or e.boss else 1.0))
		if e.dead or e.boss:
			continue
		if kb > 0.0:
			e.kb += d * kb * (0.3 if e.elite else 1.0)
		if stun > 0.0:
			e.stun = maxf(e.stun, stun * (0.5 if e.elite else 1.0))
	for e in hits:
		o._hit_fx(e, o.pos)
	for s in b.get("on_hit", []):
		for e in hits:
			apply_status(o, e, s)
	# 画面：通用 fx（docs/61 §5.6）以线段中点为中心、半长为半径、斩击方向为角度（rot: true 随方向转）；没有 fx 或缺图时画一道程序线
	if fx_any_tex(o, b.get("fx", [])):
		fx_play(o, b.fx, o.pos + d * L * 0.5, L * 0.5, hits, ang)
	else:
		var fy := Vector2(0, -12.0)
		o.fx({"kind": "line", "pos": o.pos + fy, "to": o.pos + d * L + fy, "life": 0.18, "col": o.col(), "w": W * 0.3})
	return hits


## 瞬时区域 / 位移的中心：self（缺省）/ leader / target（调用方给的点：区域 tick、落点、on_kill 的敌人、on_hurt 的主控）/ zone（本干员区域中心）/
## last_hit（本干员上一次普攻命中的第一个敌人）
static func field_center(o, b: Dictionary, at: Vector2 = Vector2.INF) -> Vector2:
	match str(b.get("center", "self")):
		"leader":
			return o.g.ppos
		"target":
			return at
		"zone":
			return o.zone_c()
		"last_hit":
			return o.last_hit_pos
	return o.pos


## 新积木的放置与参数校验（_block 认出 EXT_BLOCKS 里的名字后转到这里）
static func _ext_block(b: Dictionary, p: String, kind: String, tag: String, xk: String, ctx: Dictionary) -> void:
	var errs: Array = ctx.errs
	var ok_place := false
	match kind:
		"attack":
			ok_place = tag.begins_with("shape.") and xk == "instant"
		"trig":
			ok_place = xk == "trig"
		"instant":
			ok_place = xk == "instant"
		"sustain":
			ok_place = xk == "sustain"
		"skill":
			ok_place = xk in ["instant", "sustain", "skill"]
	if not ok_place:
		var kn: String = {"instant": "瞬时", "sustain": "常驻", "skill": "只能放技能 do", "trig": "触发积木"}.get(xk, xk)
		errs.append("%s：「%s」（%s）不能放在这里（%s）" % [p, tag, kn, kind])
		return
	match tag:
		"shape.line":
			_num(b, "len", p, ctx, true, 10.0, 800.0)
			_num(b, "width", p, ctx, true, 4.0, 300.0)
			_num(b, "mult", p, ctx, false, -INF, 20.0)
			_num(b, "max_n", p, ctx, false, 1.0, 99.0)
			_num(b, "kb", p, ctx, false, 0.0)
			_num(b, "stun", p, ctx, false, 0.0, 10.0)
			_src(b, p, ctx, true)
			_list(b.get("on_hit", []), p + ".on_hit", "on_hit", ctx)
		"verb.negate_next":
			_list(b.get("on_block", []), p + ".on_block", "instant", ctx)
			_list(b.get("on_miss", []), p + ".on_miss", "instant", ctx)
		"verb.dr":
			_num(b, "value", p, ctx, true, 0.0, 0.9)
		"verb.negate_chance":
			if not (b.has("add") or b.has("mult")):
				errs.append(p + "：verb.negate_chance 要写 add / mult 之一")
			_num(b, "add", p, ctx, false, -1.0, 1.0)
			_num(b, "mult", p, ctx, false, 0.0, 5.0)
		"verb.swap_attack":
			var a = b.get("attack", null)
			if not (a is Dictionary) or not str(a.get("shape", "")) in ["circle", "cone", "line"]:
				errs.append(p + ".attack 必须是一个伤害形状（shape.circle / shape.cone / shape.line）")
			else:
				_block(a, p + ".attack", "attack", ctx)
		"trig.on_hurt":
			_num(b, "chance", p, ctx, false, 0.0, 1.0)
			_num(b, "boss_chance", p, ctx, false, 0.0, 1.0)
			_num(b, "max_chance", p, ctx, false, 0.0, 1.0)
			_num(b, "cd", p, ctx, false, 0.0)
			if b.has("negate") and not (b.negate is bool):
				errs.append(p + ".negate 只能是 true / false")
			_list(b.get("do", []), p + ".do", "instant", ctx)
		"trig.on_negate":
			_list(b.get("do", []), p + ".do", "instant", ctx)
# ================================================================ 安洁莉娜 angelina（docs/59 §5；docs/61 §12）—— 第三批追加段，只往后加
# 新积木：shape.point_aoe（落点弹）、verb.displace（拉 / 推 / 向心 / 环带整形）、verb.field（常驻力场）、verb.buff_leader（主控属性）、
# st.airborne（悬浮）、st.weightless（失重：受到的击退倍率）、st.dot（力场里的持续伤害）、trig.on_impact（落点触发）；
# 技能外壳 dur.next_n（{"next_attacks": N} + attack_patch）。
# 体型档（docs/60 §2.8 / §5「重量 / 力度」）：Boss 不位移、不悬浮（只吃写了 boss / boss_only 的子项）；精英位移 × elite_mult（缺省 0.5）、
# 控制时长 × 0.5；重型（enemies.json heavy）位移 × 0.3（就是 enemies.gd 对 e.kb 的既有折扣，这里先算进去好夹住不越过中心）。
# 位移走 e.kb（速度，enemies.gd 每秒衰减 KB_DECAY），所以自动乘 g.enemy_kb_mult：藏品 #103「安洁莉娜的创想」受到的击退 +40% = 拉得远 40%。

const ANGELINA_TAGS := ["shape.point_aoe", "st.airborne", "st.weightless", "st.dot", "trig.on_impact"]   # verb.displace / verb.field / verb.buff_leader 在「共用积木」段
const KB_DECAY := 900.0                       # enemies.gd：e.kb.move_toward(ZERO, 900 * dt)
const LEADER_STATS := ["move_speed", "pickup", "dash_cd"]   # verb.buff_leader 可写的主控属性（全局作用域；dash_cd = 主控冲刺冷却倍率，德克萨斯 S2）
const AIR_RISE := 0.15                        # 悬浮：起跳 / 落地秒数（画面高度，不影响判定）
const AIR_FALL := 0.2
static var _D = null


static func _heavy(e: Dictionary) -> bool:
	if _D == null:
		_D = load("res://scripts/data.gd")
	return _D.ENEMIES.get(e.get("type", ""), {}).get("heavy", false)


## 失重（st.weightless）期间受到的击退倍率；没有失重 = 1.0（character.gd melee_hit 的击退乘它，老干员乘 1.0 逐字节不变）
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
	e.kb += dir * kb_for(dist, m)
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
		for s in b.get("tick", []):
			if e.dead:
				break
			if str(s.get("_tag", "")) == "verb.displace":
				if not cond_true(o, s.get("cond", {})):
					continue
				if displace_one(o, e, c, s, every if s.get("per_sec", false) else 1.0, st.ring):
					for s2 in s.get("on_hit", []):
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
		if not k in ["mult", "r_mult", "force_mult", "src", "on_hit"]:
			errs.append("%s.attack_patch.%s：只支持 mult / r_mult / force_mult / src / on_hit" % [p, k])
	for k in ["mult", "r_mult", "force_mult"]:
		_num(ap, k, p + ".attack_patch", ctx, false, 0.0, 20.0)
	if ap.has("src"):
		_src(ap, p + ".attack_patch", ctx, true)
	_list(ap.get("on_hit", []), p + ".attack_patch.on_hit", "on_hit", ctx)


# ================================================================ 共用积木（第三批合并时统一，docs/61 §5.1 / §11–§14）
# 星熊与安洁莉娜各自实现过 verb.displace / verb.field，德克萨斯与安洁莉娜各自实现过 verb.buff_leader；合并后每个名字只有这一份实现，
# 参数形式不同的地方用「写了哪个参数」区分（不是两个名字），各干员的 JSON 与单元测试都照旧通过。
#
#  verb.displace  瞬时（技能 do / 触发器 do / 落点 then），或常驻力场 tick 子项。中心 center（缺省 self；self / leader / target / zone / last_hit），
#                 半径 r × op_range × 本干员 area 倍率（敌人身体与圆相交即算）。两种力度写法，恰好写一个：
#                   kb   = 冲量：非 Boss 可位移敌人沿离心方向 e.kb += kb（负数 = 拉），精英 ×0.3，乘失重倍率（星熊：推开 / 震退）
#                   dist = 位移距离（像素）：dir pull / push（力场里另有 center / ring），精英 × elite_mult，重型 ×0.3，灯光内 × force_lit，
#                          反解成 e.kb（安洁莉娜：拉拢、环带整形）；技能 attack_patch.force_mult 再乘
#                 on_hit：半径内每个敌人各吃一次（st.*，Boss 规则见 apply_status）；不造成伤害、不登记命中。
#                 画面：通用 fx 以中心 / 半径播（没有 fx 或缺图时画一道程序环）。
#  verb.field     两种形式，看写了 tick 还是 do：
#                   do + dur + every = 瞬时留场（星熊热砂）：在 center 留 dur 秒，每 every 秒以区域中心为 target 执行一次 do（共 round(dur / every) 次）
#                   tick (+ every)   = 常驻力场（安洁莉娜 S2 / S3）：生效期间以主控（或自己）为心，每 every 秒对场内敌人逐个执行 tick 子项
#  verb.buff_leader 常驻：主控属性修正（全局作用域），stat 只能是 LEADER_STATS（move_speed / pickup），op add / mult

const SHARED_TAGS := ["verb.displace", "verb.field", "verb.buff_leader"]
const DISPLACE_CENTERS := ["self", "leader", "target", "zone", "last_hit"]


## verb.displace 执行（瞬时）：返回半径内的敌人（on_hit 的对象）
static func displace_at(o, b: Dictionary, at: Vector2 = Vector2.INF) -> Array:
	var c: Vector2 = field_center(o, b, at)
	if c == Vector2.INF:
		return []
	var g = o.g
	var r: float = float(b.get("r", 0.0)) * o.stat(&"op_range") * float(o.loc.get("area", 1.0))
	var by_dist: bool = b.has("dist")
	var kb: float = float(b.get("kb", 0.0))
	var sc: float = float(o.shot.get("force_mult", 1.0)) if by_dist else 1.0
	var hits: Array = []
	for j in o.query_ids(c, r + 40.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or e.pos.distance_to(c) > r + float(e.r):
			continue
		hits.append(e)
		if by_dist:
			displace_one(o, e, c, b, sc)
		elif kb != 0.0 and _movable(e):
			var dv: Vector2 = e.pos - c
			e.kb += (dv.normalized() if dv.length() > 0.5 else Vector2.RIGHT) * kb * (0.3 if e.elite else 1.0) * kb_taken(e, g.t)
	for s in b.get("on_hit", []):
		for e in hits:
			apply_status(o, e, s, c)
	if fx_any_tex(o, b.get("fx", [])):
		fx_play(o, b.fx, c, r, hits)
	else:
		o.fx({"kind": "ring", "pos": c, "r": r, "r0": r * 0.3, "life": 0.3, "col": o.col(), "floor": true, "w": 3.0, "alpha": 0.7})
	return hits


## 共用积木的放置与参数校验（_block 认出 SHARED_TAGS 后转到这里）。kind 多了 field（常驻力场的 tick 子项）
static func _v_shared(b: Dictionary, p: String, kind: String, ctx: Dictionary, tag: String) -> void:
	var errs: Array = ctx.errs
	match tag:
		"verb.displace":
			var has_kb: bool = b.has("kb")
			var has_d: bool = b.has("dist")
			if has_kb == has_d:
				errs.append(p + "：verb.displace 要写 kb（冲量）或 dist（位移距离）其中一个")
				return
			if not kind in (["skill", "instant", "field"] if has_d else ["skill", "instant"]):
				errs.append("%s：「verb.displace」是瞬时积木，不能放在这里（%s）" % [p, kind])
				return
			if has_kb:
				_num(b, "kb", p, ctx, true, -2000.0, 2000.0)
			else:
				var dirs: Array = ["pull", "push", "center", "ring"] if kind == "field" else ["pull", "push"]
				if not str(b.get("dir", "pull")) in dirs:
					errs.append("%s.dir 只能是 %s" % [p, " / ".join(dirs)])
				_num(b, "dist", p, ctx, true, 0.0, 400.0)
				_num(b, "elite_mult", p, ctx, false, 0.0, 1.0)
			if kind != "field":
				_num(b, "r", p, ctx, true, 1.0, 800.0)
				if not str(b.get("center", "self")) in DISPLACE_CENTERS:
					errs.append("%s.center 只能是 %s" % [p, " / ".join(DISPLACE_CENTERS)])
			_list(b.get("on_hit", []), p + ".on_hit", "on_hit", ctx)
		"verb.field":
			if b.has("tick"):
				if not kind in ["skill", "sustain"]:
					errs.append("%s：常驻力场（verb.field 带 tick）只能放技能 do 或常驻列表（这里是 %s）" % [p, kind])
					return
				if b.has("do") or b.has("dur"):
					errs.append(p + "：verb.field 写了 tick（常驻力场）就不写 do / dur（瞬时留场）")
				_num(b, "r", p, ctx, true, 1.0)
				_num(b, "every", p, ctx, false, 0.1)
				_num(b, "ring", p, ctx, false, 0.0)
				_num(b, "ring_w", p, ctx, false, 1.0)
				if not str(b.get("center", "leader")) in ["leader", "self"]:
					errs.append(p + ".center 只能是 leader / self")
				if not str(b.get("look", "none")) in ["ring", "lift", "none"]:
					errs.append(p + ".look 只能是 ring / lift / none")
				var tk = b.tick
				if not (tk is Array) or tk.is_empty():
					errs.append(p + ".tick 至少要一个子项（verb.displace / st.*）")
				else:
					_list(tk, p + ".tick", "field", ctx)
					for i in tk.size():
						if tk[i] is Dictionary and (str(tk[i].get("where", "")) == "ring" or str(tk[i].get("dir", "")) == "ring") and not b.has("ring"):
							errs.append("%s.tick[%d]：where / dir 为 ring 时力场要写 ring" % [p, i])
			else:
				if not kind in ["skill", "instant"]:
					errs.append("%s：瞬时留场（verb.field 带 do）只能放技能或触发器的 do（这里是 %s）" % [p, kind])
					return
				_num(b, "r", p, ctx, true, 1.0, 800.0)
				_num(b, "dur", p, ctx, true, 0.1, 30.0)
				_num(b, "every", p, ctx, true, 0.1, 30.0)
				if not str(b.get("center", "self")) in FIELD_CENTERS:
					errs.append("%s.center 只能是 %s" % [p, " / ".join(FIELD_CENTERS)])
				if not (b.get("do", null) is Array) or b.do.is_empty():
					errs.append(p + "：verb.field 要有 do（瞬时留场每次 tick 执行的瞬时积木）或 tick（常驻力场）")
				else:
					_list(b.do, p + ".do", "instant", ctx)
		"verb.buff_leader":
			if not kind in ["skill", "sustain"]:
				errs.append("%s：「verb.buff_leader」是常驻积木，不能放在这里（%s）" % [p, kind])
				return
			if not str(b.get("stat", "")) in LEADER_STATS:
				errs.append("%s.stat 只能是 %s" % [p, " / ".join(LEADER_STATS)])
			if not str(b.get("op", "")) in ["add", "mult"]:
				errs.append(p + ".op 只能是 add / mult")
			_num(b, "value", p, ctx, true, 0.0, 5.0)

# ================================================================ 德克萨斯 texas（docs/61 §13）
# 第三批并行实装约定：每名干员的新积木在文件末尾各占一段（append-only）；核心部分只加三处转发：
# validate 的普攻形状表、_block 里 TX_IMPL 命中时转给 _tx_block、exec_shape 的 dash_line 分支。
# data_operator.gd 里对应的转发都标了「德克萨斯段」。状态存在干员的 tx 字典里（data_operator.gd 的 var tx）。
#
#  shape.dash_line   冲刺穿行：沿一条线段冲出 r（× op_range × 冲刺长度倍率），宽 w，用时 t、到头停 hold；
#                    逐帧扫过的线段内敌人各吃一次（不重复）。aim：nearest（最近敌人，手动普攻 A 方向类）/ densest（敌群最密处）/
#                    leader_dir（主控冲刺方向；本干员是主控时不另行位移，跟着主控的冲刺扫）/ reverse（上一次冲刺的反方向）。
#                    干员是主控时冲刺就是主控本体位移（同乌尔比安弹射，squad.update 把 g.ppos 拉过去），到头不停顿。
#                    其余参数同 shape.circle：mult、src、tags、power、on_hit（st.stun / st.slow）；strip：剑光帧条名（可选，冲刺专用画法：拉到冲刺长度、半程起播；不是通用 fx 字段）；sfx：起冲时播的音（可选）
#  verb.sp_secs      瞬时：编队技能各 +seconds 秒充能（推进之王 _squad_sp_seconds 的写法；不吃回复倍率）；exclude_self 缺省 true
#  verb.dash_mod     常驻：本干员冲刺长度 / 宽度倍率（len_add / len_mult / w_add / w_mult；(1 + Σadd) × Πmult）
#  verb.buff_leader  常驻：主控属性修正，第一版只开 stat = dash_cd（主控冲刺冷却倍率，game.gd dash_cd_mult）；op: add / mult
#  verb.trail        瞬时（放在 trig.on_dash_end 里）：沿刚结束的那次冲刺留下 life 秒的残像，踩进的敌人各吃一次 mult 伤害 + on_hit
#  verb.fx_scatter   瞬时、只有画面：在 center（self / target）半径 r 内撒 n 个帧条（strip），错开 stagger 秒起播；不碰 g.rng
#  trig.on_dash_end  本干员任一次 dash_line 结束时：src（只认这个伤害来源的冲刺，缺省全部）、min_hits（这次扫中的敌人数下限）、delay
#  trig.on_leader_dash  主控按下冲刺（g.dash_t 上升沿）：cd（两次之间至少隔几秒）
#  trig.on_skill_start / trig.on_skill_end  本干员技能 skill（0 起）出手 / 持续结束：delay（只 on_skill_start）

const TX_IMPL := {
	"shape": ["dash_line"],
	"verb": ["sp_secs", "dash_mod", "trail", "fx_scatter"],   # verb.buff_leader 在「共用积木」段
	"trig": ["on_dash_end", "on_leader_dash", "on_skill_start", "on_skill_end"],
}
const TX_AIMS := ["nearest", "densest", "leader_dir", "reverse"]
const TxArt = preload("res://scripts/art.gd")


## 校验（由 _block 转来；cond 与 $ 表达式已在 _block 里查过）
static func _tx_block(b: Dictionary, p: String, kind: String, tag: String, ctx: Dictionary) -> void:
	var errs: Array = ctx.errs
	var instant: bool = tag in ["shape.dash_line", "verb.sp_secs", "verb.trail", "verb.fx_scatter"]
	var is_trig: bool = tag.begins_with("trig.")
	match kind:
		"attack":
			if tag != "shape.dash_line":
				errs.append("%s：普攻只能是伤害形状，不能是「%s」" % [p, tag])
				return
		"trig":
			if not is_trig:
				errs.append("%s：这里要触发积木，不是「%s」" % [p, tag])
				return
		"on_hit":
			errs.append("%s：on_hit 里只能放 st.stun / st.slow，不能放「%s」" % [p, tag])
			return
		"instant":
			if not instant:
				errs.append("%s：触发器的 do 只执行一次，「%s」不是瞬时积木" % [p, tag])
				return
		"sustain":
			if instant or is_trig:
				errs.append("%s：常驻列表里只能放常驻积木，「%s」不是" % [p, tag])
				return
		"skill":
			if is_trig:
				errs.append("%s：技能 do 里不能放「%s」" % [p, tag])
				return
	match tag:
		"shape.dash_line":
			_num(b, "r", p, ctx, true, 10.0, 600.0)
			_num(b, "w", p, ctx, true, 4.0, 200.0)
			_num(b, "t", p, ctx, false, 0.02, 1.0)
			_num(b, "hold", p, ctx, false, 0.0, 1.0)
			_num(b, "mult", p, ctx, false, -INF, 20.0)
			if not str(b.get("aim", "nearest")) in TX_AIMS:
				errs.append("%s.aim 只能是 %s" % [p, " / ".join(TX_AIMS)])
			if b.has("strip") and not (b.strip is String and (b.strip.begins_with("fx_") or b.strip.begins_with("proj_"))):
				errs.append(p + ".strip 必须是帧条名（fx_* / proj_*）")
			if kind == "attack" and str(b.get("aim", "nearest")) != "nearest":
				errs.append(p + ".aim：普攻冲刺只能朝最近敌人（nearest）")
			_src(b, p, ctx, true)
			_list(b.get("on_hit", []), p + ".on_hit", "on_hit", ctx)
		"verb.sp_secs":
			_num(b, "seconds", p, ctx, true, 0.0, 10.0)
		"verb.dash_mod":
			if not (b.has("len_add") or b.has("len_mult") or b.has("w_add") or b.has("w_mult")):
				errs.append(p + "：verb.dash_mod 至少写 len_add / len_mult / w_add / w_mult 之一")
			for k in ["len_add", "w_add"]:
				_num(b, k, p, ctx, false, -0.9, 3.0)
			for k in ["len_mult", "w_mult"]:
				_num(b, k, p, ctx, false, 0.1, 4.0)
		"verb.trail":
			_num(b, "life", p, ctx, true, 0.05, 5.0)
			_num(b, "mult", p, ctx, true, 0.0, 20.0)
			_src(b, p, ctx, true)
			_list(b.get("on_hit", []), p + ".on_hit", "on_hit", ctx)
		"verb.fx_scatter":
			if str(b.get("strip", "")) == "":
				errs.append(p + " 缺 strip（帧条名）")
			_num(b, "n", p, ctx, true, 1.0, 32.0)
			_num(b, "r", p, ctx, true, 0.0, 600.0)
			_num(b, "stagger", p, ctx, false, 0.0, 2.0)
			if not str(b.get("center", "self")) in ["self", "target"]:
				errs.append(p + ".center 只能是 self / target")
		"trig.on_dash_end":
			_num(b, "min_hits", p, ctx, false, 0.0, 99.0)
			_num(b, "delay", p, ctx, false, 0.0, 5.0)
			if b.has("src"):
				_src(b, p, ctx, true)
			_list(b.get("do", []), p + ".do", "instant", ctx)
		"trig.on_leader_dash":
			_num(b, "cd", p, ctx, false, 0.0, 60.0)
			_list(b.get("do", []), p + ".do", "instant", ctx)
		"trig.on_skill_start", "trig.on_skill_end":
			_num(b, "skill", p, ctx, true, 0.0, 2.0)
			if tag == "trig.on_skill_start":
				_num(b, "delay", p, ctx, false, 0.0, 5.0)
			elif b.has("delay"):
				errs.append(p + "：trig.on_skill_end 不支持 delay")
			_list(b.get("do", []), p + ".do", "instant", ctx)


## 冲刺长度（世界像素）：r × op_range × 本干员冲刺长度倍率
static func tx_len(o, b: Dictionary) -> float:
	return float(b.get("r", 0.0)) * o.stat(&"op_range") * float(o.tx.get("len", 1.0))


## 普攻起手点（data_operator.update 转来）：最近敌人在冲刺长度 × 1.3 内就起手（手动普攻 A 方向类：沿瞄准方向照冲）
static func tx_attack_point(o, b: Dictionary) -> Vector2:
	var r: float = tx_len(o, b)
	return o.atk_point(o.nearest_enemies(1, r * 1.3, o.pos), r)


## 起冲（瞬时）：正在冲的那次先结算掉，再按 aim 定方向。dmg 已含 mult / 局部伤害倍率 / 技能强度（exec_shape 算好）
static func tx_dash_start(o, b: Dictionary, dmg: float) -> Array:
	var g = o.g
	if o.pos == Vector2.INF:
		return []
	if o.tx.has("dash"):
		_tx_dash_end(o)
	var aim: String = str(b.get("aim", "nearest"))
	var len: float = tx_len(o, b)
	var dir := Vector2.ZERO
	match aim:
		"nearest":
			var ts: Array = o.nearest_enemies(1, len * 1.3, o.pos)
			var ang: float = (ts[0].pos - o.pos).angle() if not ts.is_empty() else o.facing_angle()
			dir = Vector2.from_angle(o.atk_angle(ang))
		"densest":
			var p: Vector2 = _tx_densest(o, len * 1.6)
			dir = (p - o.pos).normalized() if p != Vector2.INF and p.distance_to(o.pos) > 1.0 else Vector2(o.face, 0.0)
		"leader_dir":
			dir = g.dash_dir if g.dash_dir != Vector2.ZERO else Vector2(g.facing, 0.0)
		"reverse":
			dir = -Vector2(o.tx.get("last_dir", Vector2(o.face, 0.0)))
	if dir == Vector2.ZERO:
		dir = Vector2(o.face, 0.0)
	dir = dir.normalized()
	if absf(dir.x) > 0.1:
		o._set_face(signf(dir.x), true)
	var ride: bool = o.is_leader and aim == "leader_dir"   # 主控自己按的冲刺：位移交给主控，冲刺只负责扫
	var d := {"from": o.pos, "to": o.pos + dir * len, "dir": dir, "t": 0.0, "dur": float(b.get("t", 0.18)),
		"hold": 0.0 if o.is_leader else float(b.get("hold", 0.0)), "ride": ride, "last": o.pos, "hit": {},
		"dmg": dmg, "w": float(b.get("w", 40.0)) * float(o.tx.get("w", 1.0)), "b": b, "src": str(b.get("src", ""))}
	o.tx["dash"] = d
	if b.has("sfx"):
		o._sfx_op(str(b.sfx))
	if b.has("strip"):
		var fr: Array = g.V6_FRAMES.get(str(b.strip), [4, 20.0])
		o.fx({"kind": "tx_strip", "strip": str(b.strip), "frames": int(fr[0]), "fps": float(fr[1]), "pos": d.to, "ang": dir.angle(), "sx": len / 128.0,
			"anchor": Vector2(63.0 / 64.0, 0.5), "life": float(fr[0]) / float(fr[1]) + d.dur * 0.5, "delay": d.dur * 0.5})
	return []


## 敌群最密处：半径 rr 内最近的 24 个敌人里，80 像素内邻居最多的那个（并列取近的）；没有敌人返回 INF
static func _tx_densest(o, rr: float) -> Vector2:
	var cand: Array = o.g.enemies_sys.nearest(24, rr, o.pos)
	var best := Vector2.INF
	var bn := -1
	for e in cand:
		var n := 0
		for f in cand:
			if e.pos.distance_squared_to(f.pos) <= 6400.0:
				n += 1
		if n > bn:
			bn = n
			best = e.pos
	return best


## 每帧（data_operator.update 在常驻积木之后调）：主控冲刺 / 技能结束的触发、延迟队列、残像、冲刺推进与扫线。
## 返回 true = 正在冲刺（这一帧不起手普攻 / 技能）
static func tx_update(o, dt: float) -> bool:
	var g = o.g
	var tx: Dictionary = o.tx
	# 主控冲刺上升沿
	var ld: float = float(g.dash_t)
	if ld > 0.0 and float(tx.get("prev_ld", 0.0)) <= 0.0 and g.demo_op == "":
		for t in o._trigs():
			if str(t.get("_tag", "")) != "trig.on_leader_dash" or not cond_true(o, t.get("cond", {})):
				continue
			var k: String = "ld%d" % int(t.get("_uid", 0))
			if g.t < float(tx.get(k, -99.0)):
				continue
			tx[k] = g.t + float(t.get("cd", 0.0))
			o._exec_list(t.get("do", []))
	tx["prev_ld"] = ld
	# 技能持续结束
	var prev: Array = tx.get("prev_s", [0.0, 0.0, 0.0])
	for i in 3:
		if prev[i] > 0.0 and o.s_t[i] <= 0.0:
			for t in o._trigs():
				if str(t.get("_tag", "")) == "trig.on_skill_end" and int(t.get("skill", -1)) == i and cond_true(o, t.get("cond", {})):
					o._exec_list(t.get("do", []), tx.get("last_to", o.pos))
	tx["prev_s"] = o.s_t.duplicate()
	# 延迟队列（on_dash_end / on_skill_start 的 delay）
	var q: Array = tx.get("queue", [])
	if not q.is_empty():
		var due: Array = []
		for it in q:
			it.t -= dt
			if it.t <= 0.0:
				due.append(it)
		tx["queue"] = q.filter(func(it): return it.t > 0.0)
		for it in due:
			tx["ctx"] = it.ctx
			o._exec_list(it.do, it.ctx.get("to", Vector2.INF))
	# 残像
	var trails: Array = tx.get("trails", [])
	if not trails.is_empty():
		for tr in trails:
			tr.life -= dt
			_tx_sweep(o, tr.from, tr.to, tr.w, tr.hit, tr.dmg, tr.b)
		tx["trails"] = trails.filter(func(tr): return tr.life > 0.0)
	# 冲刺
	if not tx.has("dash") or o.pos == Vector2.INF:
		return false
	var d: Dictionary = tx.dash
	d.t += dt
	var k2: float = clampf(d.t / maxf(0.01, d.dur), 0.0, 1.0)
	if not d.ride:
		o.pos = (d.from as Vector2).lerp(d.to, 1.0 - (1.0 - k2) * (1.0 - k2))   # 先快后慢
	if d.t <= d.dur + dt * 0.5:
		_tx_sweep(o, d.last, o.pos, d.w, d.hit, d.dmg, d.b)
		d.last = o.pos
	if d.t >= d.dur + d.hold:
		_tx_dash_end(o)
		return false
	return true


## 扫一段线段：线段两侧 w/2（+ 敌人半径）内、hit 里没有的敌人各吃一次 dmg（对精英 / Boss 乘 vs_elite）与 on_hit 状态
static func _tx_sweep(o, a: Vector2, c: Vector2, w: float, hit: Dictionary, dmg: float, b: Dictionary) -> void:
	var g = o.g
	var seg: Vector2 = c - a
	var L: float = seg.length()
	var mid: Vector2 = (a + c) * 0.5
	var src: String = str(b.get("src", ""))
	var tags: Array = b.get("tags", [])
	var ve: float = o.vs_elite()
	for j in o.query_ids(mid, L * 0.5 + w * 0.5 + 40.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or hit.has(e.id):
			continue
		var q: Vector2 = a if L < 0.5 else a + seg * clampf((e.pos - a).dot(seg) / (L * L), 0.0, 1.0)
		if e.pos.distance_to(q) > w * 0.5 + float(e.r):
			continue
		hit[e.id] = true
		o.log_hit(src, tags)
		o.deal_damage(e, dmg * (ve if e.elite or e.boss else 1.0))
		for s in b.get("on_hit", []):
			apply_status(o, e, s)
		o.fx({"kind": "shard", "pos": e.pos + Vector2(0, -float(e.r) * 0.5), "ang": seg.angle() + 0.5, "sz": 7.0, "life": 0.16, "col": Color(1.0, 0.75, 0.4)})


## 一次冲刺结束：记下终点与方向，按 on_dash_end 触发
static func _tx_dash_end(o) -> void:
	var tx: Dictionary = o.tx
	var d: Dictionary = tx.dash
	tx.erase("dash")
	var n: int = d.hit.size()
	tx["last_to"] = o.pos if d.ride else d.to
	tx["last_dir"] = d.dir
	var ctx := {"from": d.from, "to": tx.last_to, "dir": d.dir, "n": n, "src": d.src, "w": d.w}
	if n > 0:
		o._sfx_op("hit")
	for t in o._trigs():
		if str(t.get("_tag", "")) != "trig.on_dash_end" or not cond_true(o, t.get("cond", {})):
			continue
		if t.has("src") and str(t.src) != d.src:
			continue
		if n < int(t.get("min_hits", 0)):
			continue
		var dl: float = float(t.get("delay", 0.0))
		if dl > 0.0:
			var q: Array = tx.get("queue", [])
			q.append({"t": dl, "do": t.get("do", []), "ctx": ctx})
			tx["queue"] = q
		else:
			tx["ctx"] = ctx
			o._exec_list(t.get("do", []), ctx.to)


## 技能出手（data_operator._release_skill 转来）：trig.on_skill_start
static func tx_skill_start(o, i: int) -> void:
	for t in o._trigs():
		if str(t.get("_tag", "")) != "trig.on_skill_start" or int(t.get("skill", -1)) != i or not cond_true(o, t.get("cond", {})):
			continue
		var dl: float = float(t.get("delay", 0.0))
		if dl > 0.0:
			var q: Array = o.tx.get("queue", [])
			q.append({"t": dl, "do": t.get("do", []), "ctx": {}})
			o.tx["queue"] = q
		else:
			o._exec_list(t.get("do", []))


## 瞬时积木（data_operator._exec_list 的缺省分支转来）
static func tx_exec(o, b: Dictionary, at: Vector2) -> void:
	match str(b.get("_tag", "")):
		"shape.dash_line":
			exec_shape(o, b, at)
		"verb.sp_secs":
			var sec: float = float(b.seconds)
			for m in o.g.squad.ops:
				if m == o and b.get("exclude_self", true):
					continue
				for i in 3:
					if m.skill_unlocked(i) and m.sp_need(i) > 0.0 and not m.perm[i]:
						m.sp[i] = minf(m.sp_need(i), m.sp[i] + sec)
		"verb.trail":
			var c: Dictionary = o.tx.get("ctx", {})
			if c.has("from"):
				var tr := {"from": c.from, "to": c.to, "w": float(c.w), "life": float(b.life), "hit": {}, "b": b,
					"dmg": o.base(str(b.get("atk_key", "atk")), 0.0) * float(b.mult) * float(o.loc.dmg) * o._dmg_bonus()}
				var trails: Array = o.tx.get("trails", [])
				trails.append(tr)
				o.tx["trails"] = trails
				o.fx({"kind": "line", "pos": c.from, "to": c.to, "w": float(c.w) * 0.35, "life": float(b.life), "col": o.col(), "floor": true})
		"verb.fx_scatter":
			var cc: Vector2 = o.pos if str(b.get("center", "self")) == "self" or at == Vector2.INF else at
			var n: int = int(b.n)
			var r: float = float(b.r) * o.stat(&"op_range")
			var fr: Array = o.g.V6_FRAMES.get(str(b.strip), [6, 20.0])
			var life0: float = float(fr[0]) / float(fr[1])
			var st: float = float(b.get("stagger", 0.25))
			var sd: int = int(o.tx.get("fxn", 0))
			o.tx["fxn"] = sd + 1
			for k in n:
				# 画面用的低差异序列（黄金角），不碰 g.rng
				var u: float = fposmod((sd * n + k) * 0.618034, 1.0)
				var rad: float = r * sqrt((k + 0.5) / float(n))
				var p: Vector2 = cc + Vector2.from_angle(u * TAU + k * 2.39996) * rad * Vector2(1.0, 0.55)
				var dl: float = st * fposmod(k * 0.381966 + u, 1.0)
				o.fx({"kind": "tx_strip", "strip": str(b.strip), "frames": int(fr[0]), "fps": float(fr[1]), "pos": p, "anchor": Vector2(0.5, 30.0 / 32.0),
					"life": life0 + dl, "delay": dl})


## 常驻积木（data_operator._sustain 第二遍末尾转来）：冲刺长度 / 宽度倍率写进 tx，主控属性修正追加进 want（随 g.stats 整组重建）
static func tx_sustain(o, act: Array, want: Array) -> void:
	var la := 0.0
	var lm := 1.0
	var wa := 0.0
	var wm := 1.0
	for b in act:
		match str(b.get("_tag", "")):
			"verb.dash_mod":
				la += float(b.get("len_add", 0.0))
				lm *= float(b.get("len_mult", 1.0))
				wa += float(b.get("w_add", 0.0))
				wm *= float(b.get("w_mult", 1.0))
	o.tx["len"] = (1.0 + la) * lm
	o.tx["w"] = (1.0 + wa) * wm


## 帧条粒子（data_operator._draw_pfx 转来）：kind = tx_strip（与通用 fx 的 strip 粒子分开）；delay 秒后起播，sx 横向缩放（冲刺剑光拉到冲刺长度）
static func tx_draw_pfx(o, f: Dictionary, a: float) -> bool:
	if str(f.get("kind", "")) != "tx_strip":
		return false
	var el: float = float(f.max) - float(f.life) - float(f.get("delay", 0.0))
	if el < 0.0:
		return true
	var tx: Texture2D = o._fx_tex(str(f.strip))
	if tx == null:
		return true
	var frames: int = int(f.frames)
	var fr: int = mini(frames - 1, int(el * float(f.fps)))
	var fw: float = float(tx.get_width() / frames)
	var fh: float = float(tx.get_height())
	var k: float = o.g.PX / TxArt.hires_of(tx)
	var al: float = o.g.world.fx_dim if a > 0.0 else 0.0
	o.cv.draw_set_transform((f.pos as Vector2).round(), float(f.get("ang", 0.0)), Vector2(k * float(f.get("sx", 1.0)), k))
	o.cv.draw_texture_rect_region(tx, Rect2(-Vector2(fw, fh) * (f.anchor as Vector2), Vector2(fw, fh)), Rect2(fw * fr, 0, fw, fh), Color(1, 1, 1, al))
	o.cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true
