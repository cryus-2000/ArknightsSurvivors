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
const LOCAL_STATS := ["zone", "dmg", "heal", "interval"]
## verb.buff_self 可写进 g.stats 的干员属性（作用域 op:<id>）
const OP_STATS := ["op_atk", "op_aspd", "op_range", "op_skill_power", "op_shots"]   # op_shots：能天使（docs/61 §11）
const AURA_STAT := {"atk": "op_atk", "aspd": "op_aspd", "skill_power": "op_skill_power", "range": "op_range"}
const COND_OPS := [">=", "<=", "==", ">", "<"]


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
	match str(b.shape):
		"circle":
			var c: Vector2 = shape_center(o, b, at)
			var r: float = shape_radius(o, b)
			if c == Vector2.INF:
				return []
			hits = o.area_hit(src, c, r, dmg, kb, stun, tags, max_n)
			o.fx({"kind": "ring", "pos": c, "r": r, "r0": r * 0.55, "life": 0.32, "col": o.col(), "floor": true, "w": 2.0, "alpha": 0.6})
		"cone":
			var r2: float = shape_radius(o, b)
			var ts: Array = o.nearest_enemies(1, r2 + 30.0, o.pos)
			var ang: float = o.atk_angle((ts[0].pos - o.pos).angle() if not ts.is_empty() else o.facing_angle())
			hits = o.melee_hit(src, o.pos, ang, deg_to_rad(float(b.get("half_deg", 45.0))), r2, dmg, kb, stun, tags, max_n)
			o.fx({"kind": "ring", "pos": o.pos, "r": r2 * 0.6, "r0": 8.0, "life": 0.25, "col": o.col(), "floor": true, "w": 3.0})
		"projectile":   # 能天使挂钩（docs/61 §11）：弹体自推进，命中在 exu_tick 里结算，这里返回空
			exu_fire(o, b)
	for s in b.get("on_hit", []):
		for e in hits:
			apply_status(o, e, s)
	return hits


## 命中时的状态（st.stun / st.slow）：精英时长减半，Boss 不受
static func apply_status(o, e: Dictionary, s: Dictionary) -> void:
	if e.dead or e.boss or not cond_true(o, s.get("cond", {})):
		return
	var d: float = float(s.get("dur", 0.0)) * (0.5 if e.elite else 1.0)
	match str(s.get("st", "")):
		"stun":
			e.stun = maxf(e.stun, d)
		"slow":
			e.slow = maxf(e.slow, d)
		"pause":   # 能天使挂钩（docs/61 §11）：短停顿只对非精英
			if not e.elite:
				e.stun = maxf(e.stun, d)


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
	if not (atk is Dictionary) or not str(atk.get("shape", "")) in ["circle", "cone", "projectile"]:
		errs.append("blocks.attack 必须是一个伤害形状（shape.circle / shape.cone / shape.projectile）")
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
			if dv is Dictionary:   # 能天使挂钩（docs/61 §11）：dur.ammo
				_exu_dur(dv, p, perm_json, i, ctx)
			elif dv is String and dv == "permanent":
				if not perm_json:
					errs.append("%s.dur 是 permanent，但 skills[%d] 没写 \"permanent\": true" % [p, i])
			else:
				if perm_json:
					errs.append("skills[%d] 是 permanent，%s.dur 也要写 \"permanent\"" % [i, p])
				var ev := eval_expr(dv, base)
				if not ev[0]:
					errs.append("%s.dur：%s" % [p, ev[2]])
				elif ev[1] < 0.0:
					errs.append("%s.dur 不能为负" % p)
			for k in sb:
				if not k in ["dur", "do"] + EXU_SKILL_KEYS:
					errs.append("%s.%s：技能积木只有 dur / do / attack_patch / end 这几个字段" % [p, k])
			_list(sb.get("do", []), p + ".do", "skill", ctx)
			_exu_skill(sb, p, ctx)   # 能天使挂钩（docs/61 §11）：attack_patch / end
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
	if fam == "custom":
		ctx.custom += 1
		if not kind in ["skill", "instant"]:
			errs.append(p + "：custom 只能放在技能或触发器的 do 里（瞬时执行）")
		return
	var nm: String = str(b[fam])
	var tag := "%s.%s" % [fam, nm]
	if _exu_block(b, p, kind, ctx, tag):   # 能天使挂钩（docs/61 §11）：她的积木在文件末尾那一段校验
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


# ================================================================ 能天使 exusiai（docs/61 §11，2026-10-11 第三批第四人）
# 本段只追加。积木：弹道 shape.projectile、技能外壳 dur.ammo（次数型）+ attack_patch（技能生效期间改普攻）+ end（技能结束时执行）、
# trig.on_attack（命名计数器满时，这一次普攻换成 do 里的积木）、verb.counter（命名计数器）/ verb.counter_cap（常驻：改计数器上限）/
# verb.attack_lock（之后一段时间不普攻）/ verb.ricochet（常驻：弹体命中后按概率跳向附近另一名敌人）、st.pause（短停顿，只对非精英）。
# 上面的通用代码只插了几行挂钩（都标「能天使挂钩」）；data_operator.gd 同样只插挂钩，外加末尾的绘制 / 状态两个函数。
# 运行时状态放 o.ext（data_operator 的扩展字典）：bul 弹体、cnt / cap 计数器与上限、ammo 次数型技能剩余、lock 普攻锁、burst 连射队列、was 技能上一帧是否生效。
# 确定性（docs/36 §3）：选目标按「距离 ÷ 精英优先度」再按 id 排序；只有跳弹掷 g.rng（玩法随机，docs/61 §0.4）；画面不碰 g.rng。

const EXU_IMPL := {"shape": ["projectile"], "verb": ["counter", "counter_cap", "attack_lock", "ricochet"], "st": ["pause"], "trig": ["on_attack"]}
const EXU_SKILL_KEYS := ["attack_patch", "end"]
const EXU_PATCH_KEYS := ["mult", "pierce", "src", "tags", "tex", "power", "burst", "burst_gap", "range_mult", "elite_prio", "last_on_hit", "muzzle_fx", "spread_deg", "focus_boss", "kb"]
const EXU_BULLET_MAX := 96            # 同时在场的弹体上限（docs/59 §4：上限约 36 发/秒 × 寿命 0.7 秒）
const EXU_AIM_Y := -10.0              # 瞄准 / 判定点：敌人脚底往上 10（身体中段）
const EXU_HIT_PAD := 6.0              # 判定半径 = 敌人半径 + 6
## 弹体帧条的弹头锚点（docs/25 §6，1x 像素；@2x 自动 ×2）
const EXU_TEX_ANCHOR := {"proj_exusiai_bullet": Vector2(12, 3), "proj_exusiai_bullet_power": Vector2(15, 4)}
const EXU_ART = preload("res://scripts/art.gd")


static func exu_st(o) -> Dictionary:
	if not o.ext.has("bul"):
		o.ext.merge({"bul": [], "cnt": {}, "cap": {}, "ammo": [0, 0, 0], "lock": 0.0, "burst": [], "was": [false, false, false]})
	return o.ext


## 这名数据干员用不用得到本段（普攻是弹道，或技能带 attack_patch / end / dur.ammo）；用不到时 exu_tick 什么都不做，老数据干员逐字节不变
static func _exu_used(o) -> bool:
	if not o.ext.is_empty():
		return true
	if str(o.B.get("attack", {}).get("shape", "")) == "projectile":
		return true
	for sb in o.B.get("skills", []):
		if sb.has("attack_patch") or sb.has("end") or sb.get("dur", 0) is Dictionary:
			return true
	return false


static func _exu_main(o, b: Dictionary) -> bool:
	return int(b.get("_uid", -1)) == int(o.B.get("attack", {}).get("_uid", -2))


## 本帧生效的某种常驻积木（成长节点 / 精英化直接写的积木，或 trig.passive 的 do 里的），按 docs/61 §5.5 的固定顺序
static func _exu_active(o, tag: String) -> Array:
	var out: Array = []
	for t in o._trigs():
		if not cond_true(o, t.get("cond", {})):
			continue
		if str(t.get("_tag", "")) == "trig.passive":
			for b in t.get("do", []):
				if str(b.get("_tag", "")) == tag and cond_true(o, b.get("cond", {})):
					out.append(b)
		elif str(t.get("_tag", "")) == tag:
			out.append(t)
	return out


static func _exu_cap(o, cn: String, dflt: float) -> float:
	var v := dflt
	for b in _exu_active(o, "verb.counter_cap"):
		if str(b.get("name", "")) == cn:
			v = float(b.get("value", dflt))
	return v


## 技能 attack_patch 叠到弹道参数上：mult / range_mult 相乘，power 取或，其余覆盖（src 换了 tags 也跟着换）
static func _exu_merge(p: Dictionary, patch: Dictionary) -> Dictionary:
	var q := p.duplicate()
	for k in patch:
		match str(k):
			"mult", "range_mult":
				q[k] = float(q.get(k, 1.0)) * float(patch[k])
			"power":
				q[k] = bool(q.get(k, false)) or bool(patch[k])
			_:
				q[k] = patch[k]
	return q


## 这一次射击的参数：形状自己的 + （普攻时）生效中的持续型技能 attack_patch；range / speed / muzzle / tex 缺省取普攻的
static func _exu_params(o, b: Dictionary, main: bool) -> Dictionary:
	var a: Dictionary = o.B.get("attack", {})
	var p := b.duplicate()
	for k in ["range", "speed", "muzzle", "tex"]:
		if not p.has(k) and a.has(k):
			p[k] = a[k]
	if main:
		var sk: Array = o.B.get("skills", [])
		for i in mini(3, sk.size()):
			if sk[i].has("attack_patch") and not (sk[i].get("dur", 0) is Dictionary) and (o.s_t[i] > 0.0 or o.perm_on[i]):
				p = _exu_merge(p, sk[i].attack_patch)
	return p


static func _exu_range(o, p: Dictionary) -> float:
	return float(p.get("range", 300.0)) * o.stat(&"op_range") * float(p.get("range_mult", 1.0))


static func _exu_muzzle(o, p: Dictionary) -> Vector2:
	var m = p.get("muzzle", [0.0, -30.0])
	return o.pos + Vector2(float(m[0]) * o.face, float(m[1]))


## 选目标：aim_targets（自动 = 最近，含 Boss 优先；手动 = 瞄准锥内）的候选里按「距离 ÷ 精英优先度」、再按 id 取前 n 个
static func _exu_targets(o, n: int, rr: float, prio: float) -> Array:
	var pool: Array = o.aim_targets(maxi(n * 3, 8), rr, o.pos)
	var keyed: Array = []
	for e in pool:
		if e.dead:
			continue
		var d: float = o.pos.distance_to(e.pos)
		if e.elite or e.boss:
			d /= maxf(1.0, prio)
		keyed.append([d, int(e.id), e])
	keyed.sort_custom(func(x, y): return x[0] < y[0] if x[0] != y[0] else x[1] < y[1])
	var out: Array = []
	for k in mini(n, keyed.size()):
		out.append(keyed[k][2])
	if not pool.is_empty() and pool[0].boss and not pool[0].dead and (out.is_empty() or not is_same(out[0], pool[0])):
		out.erase(pool[0])
		out.push_front(pool[0])   # 保留 op_api 的 Boss 优先（ai/boss_focus）
		if out.size() > n:
			out.resize(n)
	return out


## 普攻起手点（data_operator.update 的 projectile 分支）：B 需要目标类手动普攻走 attack_targets
static func exu_aim(o, a: Dictionary) -> Vector2:
	var ts: Array = o.attack_targets(1, _exu_range(o, _exu_params(o, a, true)), o.pos)
	return ts[0].pos if not ts.is_empty() else Vector2.INF


## 出手（exec_shape 的 projectile 分支）：普攻先看 trig.on_attack（计数满就换成它的 do），再按技能补丁射一轮；burst > 1 的后几轮进连射队列
static func exu_fire(o, b: Dictionary) -> void:
	var st := exu_st(o)
	var main := _exu_main(o, b)
	if main:
		o.attack_t = minf(o.attack_t, maxf(0.0, o.cd))   # 射击间隔短于动作时把剩下的动作截短，下一次起手不被拖慢
		for t in o._trigs():
			if str(t.get("_tag", "")) != "trig.on_attack" or not cond_true(o, t.get("cond", {})):
				continue
			var cn := str(t.get("counter", ""))
			var need: float = float(t.need) if t.has("need") else float(st.cap.get(cn, INF))
			if float(st.cnt.get(cn, 0.0)) >= need:
				if t.get("reset", true):
					st.cnt[cn] = 0.0
				o._exec_list(t.get("do", []))
				o._sfx_op("big")
				if t.get("replace", true):
					return
	var p := _exu_params(o, b, main)
	var burst: int = int(p.get("burst", 1))
	_exu_volley(o, p, main, burst <= 1)
	if burst > 1:
		st.burst.append({"t": float(p.get("burst_gap", 0.06)), "left": burst - 1, "p": p, "main": main})


## 次数型技能的 attack_patch（剩余发数 > 0 的第一个）：[技能序号, 补丁]；没有 [-1, {}]
static func _exu_ammo_patch(o) -> Array:
	var sk: Array = o.B.get("skills", [])
	for i in mini(3, sk.size()):
		if sk[i].get("dur", 0) is Dictionary and sk[i].has("attack_patch") and int(o.ext.ammo[i]) > 0:
			return [i, sk[i].attack_patch]
	return [-1, {}]


## 射一轮：n 发（普攻乘 op_shots），各自独立索敌（最近的 n 个不同目标，不够时同一目标按 ±spread 错开）；fan = 朝最近目标的扇形均布；
## focus_boss = 头号目标是 Boss 时 n 发全打它
static func _exu_volley(o, p: Dictionary, main: bool, last: bool) -> void:
	var g = o.g
	var st := exu_st(o)
	if o.pos == Vector2.INF:
		return
	var n: int = int(p.get("shots", 1))
	if main:
		n = int(round(float(n) * o.stat(&"op_shots")))
	n = clampi(n, 1, 12)
	var fan: bool = p.get("fan", false)
	var ts: Array = _exu_targets(o, 1 if fan else n, _exu_range(o, p), float(p.get("elite_prio", 1.0)))
	if ts.is_empty():
		return
	if p.get("focus_boss", false) and ts[0].boss:
		ts = [ts[0]]   # 头号目标是 Boss 时全部子弹都打它（同一目标按 ±spread 错开）
	var aim0: Vector2 = ts[0].pos + Vector2(0, EXU_AIM_Y)
	o.face_to((aim0 - o.pos).angle())
	var mz := _exu_muzzle(o, p)
	var d0: Vector2 = (aim0 - mz).normalized() if aim0.distance_to(mz) > 1.0 else Vector2(o.face, 0.0)
	var sp: float = deg_to_rad(float(p.get("spread_deg", 0.0)))
	var speed: float = maxf(60.0, float(p.get("speed", 520.0)))
	var ap: Array = _exu_ammo_patch(o) if main else [-1, {}]
	for k in n:
		var q := p
		if ap[0] >= 0 and int(st.ammo[ap[0]]) > 0:
			q = _exu_merge(p, ap[1])
			st.ammo[ap[0]] = int(st.ammo[ap[0]]) - 1
		var dir: Vector2
		if fan:
			dir = d0.rotated(lerpf(-sp, sp, float(k) / float(n - 1)) if n > 1 else 0.0)
		else:
			var e: Dictionary = ts[k % ts.size()]
			var rep: int = k / ts.size()
			var off: float = sp * float((rep + 1) / 2) * (1.0 if rep % 2 == 1 else -1.0)
			var to: Vector2 = e.pos + Vector2(0, EXU_AIM_Y) - mz
			dir = (to.normalized() if to.length() > 1.0 else d0).rotated(off)
		var dmg: float = o.base(str(q.get("atk_key", "atk")), 0.0) * float(q.get("mult", 1.0)) * float(o.loc.dmg) * o._dmg_bonus()
		if q.get("power", false):
			dmg *= o.skill_power()
		var oh: Array = q.get("on_hit", [])
		if last and q.has("last_on_hit"):
			oh = oh + q.last_on_hit
		if st.bul.size() < EXU_BULLET_MAX:
			st.bul.append({"p": mz, "v": dir * speed, "life": _exu_range(o, q) * 1.15 / speed, "dmg": dmg, "src": str(q.get("src", "")),
				"tags": q.get("tags", []), "pierce": int(q.get("pierce", 0)), "kb": float(q.get("kb", 0.0)), "hit": {}, "tex": str(q.get("tex", "")), "on_hit": oh, "ric": true})
	o.spawn_fx_sprite(str(p.get("muzzle_fx", "fx_exusiai_muzzle")), mz + d0 * 7.0 * g.PX * 0.8, g.PX * 0.8, d0.angle())


## 每帧（data_operator.update 在常驻积木之后调）：技能结束 → end；普攻锁；连射队列；弹体推进与命中
static func exu_tick(o, dt: float) -> void:
	if not _exu_used(o):
		return
	var st := exu_st(o)
	var sk: Array = o.B.get("skills", [])
	for i in mini(3, sk.size()):
		var on: bool = o.s_t[i] > 0.0
		if st.was[i] and not on and sk[i].has("end"):
			o._exec_list(sk[i].end)
		st.was[i] = on
	if st.lock > 0.0:
		st.lock = maxf(0.0, st.lock - dt)
		o.no_attack = true
	if not st.burst.is_empty():
		var keep: Array = []
		for bq in st.burst:
			bq.t -= dt
			while bq.t <= 0.0 and bq.left > 0:
				bq.left -= 1
				_exu_volley(o, bq.p, bq.main, bq.left == 0)
				bq.t += maxf(0.02, float(bq.p.get("burst_gap", 0.06)))
			if bq.left > 0:
				keep.append(bq)
		st.burst = keep
	_exu_bullets(o, dt)


static func _exu_bullets(o, dt: float) -> void:
	var st: Dictionary = o.ext
	if st.bul.is_empty():
		return
	var g = o.g
	var ve: float = o.vs_elite()
	var rics: Array = _exu_active(o, "verb.ricochet")
	var ric: Dictionary = rics[0] if not rics.is_empty() else {}
	var spawn: Array = []
	for bu in st.bul:
		bu.p += bu.v * dt
		bu.life -= dt
		if bu.life <= 0.0:
			continue
		var q: Vector2 = bu.p - Vector2(0, EXU_AIM_Y)
		for j in o.query_ids(q, 32.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or bu.hit.has(e.id) or e.pos.distance_to(q) > float(e.r) + EXU_HIT_PAD:
				continue
			bu.hit[e.id] = true
			o.log_hit(bu.src, bu.tags)
			o.deal_damage(e, bu.dmg * (ve if e.elite or e.boss else 1.0))
			if float(bu.get("kb", 0.0)) > 0.0 and not e.dead and not e.boss:
				e.kb += bu.v.normalized() * float(bu.kb) * (0.3 if e.elite else 1.0)   # 同 melee_hit：精英 ×0.3、Boss 不受
			for s in bu.on_hit:
				apply_status(o, e, s)
			o._sfx_op("hit")
			o.spawn_fx_sprite("fx_exusiai_hit", e.pos + Vector2(0, EXU_AIM_Y), g.PX * 0.8)
			if bu.ric and not ric.is_empty() and g.rng.randf() < float(ric.get("chance", 0.0)):
				var nx = _exu_next(o, e, float(ric.get("r", 120.0)))
				if nx != null:
					var from: Vector2 = e.pos + Vector2(0, EXU_AIM_Y)
					var spd: float = bu.v.length()
					spawn.append({"p": from, "v": (nx.pos + Vector2(0, EXU_AIM_Y) - from).normalized() * spd, "life": float(ric.get("r", 120.0)) * 1.4 / spd,
						"dmg": bu.dmg * float(ric.get("mult", 0.5)), "src": str(ric.get("src", "")), "tags": [], "pierce": 0, "hit": {e.id: true},
						"tex": bu.tex, "on_hit": [], "ric": false})
			if bu.pierce > 0:
				bu.pierce -= 1
			else:
				bu.life = 0.0
				break
	st.bul = st.bul.filter(func(x): return x.life > 0.0)
	for s in spawn:
		if st.bul.size() < EXU_BULLET_MAX:
			st.bul.append(s)


## 跳弹目标：被打中的敌人 r 内离它最近的另一名活着的敌人（同距离按 id）
static func _exu_next(o, from_e: Dictionary, r: float):
	var best = null
	var bd := INF
	for j in o.query_ids(from_e.pos, r):
		var e: Dictionary = o.g.enemies[j]
		if e.dead or is_same(e, from_e):
			continue
		var d: float = e.pos.distance_to(from_e.pos)
		if d <= r and (d < bd or (d == bd and int(e.id) < int(best.id))):
			bd = d
			best = e
	return best


## 瞬时积木（data_operator._exec_list 的缺省分支）：shape.projectile / verb.counter / verb.attack_lock
static func exu_exec(o, b: Dictionary, at: Vector2) -> void:
	match str(b.get("_tag", "")):
		"shape.projectile":
			exu_fire(o, b)
		"verb.counter":
			var st := exu_st(o)
			var cn := str(b.get("name", ""))
			if b.get("own", false) and str(o.g.hit.get("op", "")) != o.id:
				return
			var cap := _exu_cap(o, cn, float(b.get("cap", INF)))
			st.cap[cn] = cap
			if b.has("set"):
				st.cnt[cn] = minf(cap, float(b.set))
				return
			var add: float = float(b.get("add", 1.0))
			if b.has("add_lit") and at != Vector2.INF and at.distance_to(o.g.ppos) <= o.lamp_radius():
				add = float(b.add_lit)
			st.cnt[cn] = minf(cap, float(st.cnt.get(cn, 0.0)) + add)
		"verb.attack_lock":
			var st2 := exu_st(o)
			st2.lock = maxf(float(st2.lock), float(b.get("dur", 0.0)))


## 技能外壳 dur.ammo（data_operator._release_skill）：装填 N 发，打完为止；HUD 环显示剩余 / 总数
static func exu_skill_shell(o, i: int, dv: Dictionary) -> void:
	var st := exu_st(o)
	st.ammo[i] = int(dv.get("ammo", 0))
	o.s_dur[i] = float(st.ammo[i])


static func exu_ammo_left(o, i: int) -> float:
	return float(o.ext.ammo[i]) if o.ext.has("ammo") else 0.0


## 画弹体（data_operator._draw_skill_over）：帧条按速度方向旋转；计数器满（下一发换成 trig.on_attack）时枪口一点金光
static func exu_draw(o) -> void:
	if o.ext.is_empty() or o.pos == Vector2.INF:
		return
	var g = o.g
	var fr: int = int(g.t * 20.0) % 2
	for bu in o.ext.bul:
		var tn: String = str(bu.tex)
		var tx = g.tex.get(tn) if tn != "" else null
		if tx != null:
			var an: Vector2 = EXU_TEX_ANCHOR[tn] * EXU_ART.hires_of(tx) if EXU_TEX_ANCHOR.has(tn) else Vector2(-1, -1)
			o.draw_spr_rot(tn, fr, bu.p, bu.v.angle(), g.PX, Color.WHITE, an)
		else:
			o.cv.draw_line(bu.p - bu.v.normalized() * 12.0, bu.p, Color(1.0, 0.45, 0.45, 0.85), 3.0)
	for t in o._trigs():
		if str(t.get("_tag", "")) == "trig.on_attack":
			var cn := str(t.get("counter", ""))
			var need: float = float(t.need) if t.has("need") else float(o.ext.cap.get(cn, INF))
			if float(o.ext.cnt.get(cn, 0.0)) >= need:
				var mz := _exu_muzzle(o, o.B.get("attack", {}))
				var k: float = 0.5 + 0.5 * sin(g.t * 10.0)
				o.cv.draw_circle(mz, 5.0 + 2.0 * k, Color(1.0, 0.8, 0.3, 0.35 + 0.2 * k))
				o.cv.draw_circle(mz, 2.5, Color(1.0, 0.95, 0.7, 0.9))


## Tab / 头像下的状态条：次数型技能剩余、计数器（label 或名字）、普攻锁
static func exu_status_items(o) -> Array:
	var out: Array = []
	if o.ext.is_empty():
		return out
	for i in 3:
		if int(o.ext.ammo[i]) > 0:
			out.append(["%s ×%d" % [str(o.skill_def(i).get("name", "")), int(o.ext.ammo[i])], Color(1.0, 0.8, 0.45)])
	for cn in o.ext.cnt:
		var lbl: String = cn
		for b in _exu_trig_counters(o):
			if str(b.get("name", "")) == cn and b.has("label"):
				lbl = str(b.label)
		out.append(["%s %d/%d" % [lbl, int(o.ext.cnt[cn]), int(o.ext.cap.get(cn, 0.0))], Color(1.0, 0.85, 0.4)])
	if float(o.ext.lock) > 0.0:
		out.append(["过热", Color(1.0, 0.45, 0.35)])
	return out


static func _exu_trig_counters(o) -> Array:
	var out: Array = []
	for t in o._trigs():
		for b in t.get("do", []):
			if str(b.get("_tag", "")) == "verb.counter":
				out.append(b)
	return out


# ---------------------------------------------------------------- 能天使段的校验（_block / validate 里的挂钩调这里）

## 本段的积木：校验完返回 true（_block 不再往下走）；不是本段的返回 false
static func _exu_block(b: Dictionary, p: String, kind: String, ctx: Dictionary, tag: String) -> bool:
	var parts := tag.split(".")
	if parts.size() != 2 or not parts[1] in EXU_IMPL.get(parts[0], []):
		return false
	var errs: Array = ctx.errs
	var instant: bool = tag in ["shape.projectile", "verb.counter", "verb.attack_lock"]
	var sustained: bool = tag in ["verb.counter_cap", "verb.ricochet"]
	match kind:
		"attack":
			if tag != "shape.projectile":
				errs.append("%s：普攻只能是伤害形状，不是「%s」" % [p, tag])
				return true
		"trig":
			if tag != "trig.on_attack":
				errs.append("%s：这里要触发积木，不是「%s」" % [p, tag])
				return true
		"on_hit":
			if tag != "st.pause":
				errs.append("%s：on_hit 里只能放 st.stun / st.slow / st.pause，不能放「%s」" % [p, tag])
				return true
		"instant", "skill":
			if not instant:
				var why: String = "常驻积木只能放在特性 / 天赋 / 成长节点（直接作节点或 trig.passive 的 do）" if sustained else "只能放在 trait / talent / progression 或 on_hit"
				errs.append("%s：「%s」不能放在这里（%s）" % [p, tag, why])
				return true
		"sustain":
			if not sustained:
				errs.append("%s：常驻列表里只能放常驻积木，「%s」是瞬时的" % [p, tag])
				return true
	match tag:
		"shape.projectile":
			_num(b, "shots", p, ctx, kind == "attack", 1.0, 12.0)
			_num(b, "range", p, ctx, kind == "attack", 20.0, 1200.0)
			_num(b, "speed", p, ctx, false, 60.0, 3000.0)
			_num(b, "spread_deg", p, ctx, false, 0.0, 90.0)
			_num(b, "pierce", p, ctx, false, 0.0, 20.0)
			_num(b, "kb", p, ctx, false, 0.0, 400.0)
			_num(b, "mult", p, ctx, false, -INF, 20.0)
			_num(b, "burst", p, ctx, false, 1.0, 8.0)
			_num(b, "burst_gap", p, ctx, false, 0.02, 1.0)
			_num(b, "elite_prio", p, ctx, false, 1.0, 100.0)
			_exu_muzzle_ok(b, p, ctx)
			_src(b, p, ctx, true)
			_list(b.get("on_hit", []), p + ".on_hit", "on_hit", ctx)
		"verb.counter":
			if str(b.get("name", "")) == "":
				errs.append(p + " 缺 name（计数器名）")
			for k in ["add", "add_lit", "set"]:
				_num(b, k, p, ctx, false, 0.0, 99.0)
			_num(b, "cap", p, ctx, true, 1.0, 99.0)
		"verb.counter_cap":
			if str(b.get("name", "")) == "":
				errs.append(p + " 缺 name（计数器名）")
			_num(b, "value", p, ctx, true, 1.0, 99.0)
		"verb.attack_lock":
			_num(b, "dur", p, ctx, true, 0.0, 10.0)
		"verb.ricochet":
			_num(b, "chance", p, ctx, true, 0.0, 1.0)
			_num(b, "r", p, ctx, true, 1.0, 600.0)
			_num(b, "mult", p, ctx, true, 0.0, 20.0)
			_src(b, p, ctx, true)
		"st.pause":
			_num(b, "dur", p, ctx, true, 0.0, 2.0)
		"trig.on_attack":
			if str(b.get("counter", "")) == "":
				errs.append(p + " 缺 counter（看哪个计数器满了）")
			_num(b, "need", p, ctx, false, 1.0, 99.0)
			_list(b.get("do", []), p + ".do", "instant", ctx)
	return true


static func _exu_muzzle_ok(b: Dictionary, p: String, ctx: Dictionary) -> void:
	if not b.has("muzzle"):
		return
	var m = b.muzzle
	if not (m is Array) or m.size() != 2 or not (m[0] is float or m[0] is int) or not (m[1] is float or m[1] is int):
		ctx.errs.append(p + ".muzzle 应是 [x, y]（脚底为原点、朝右、世界像素）")


## dur.ammo：{"ammo": N}，次数型（与 permanent 互斥）
static func _exu_dur(dv: Dictionary, p: String, perm_json: bool, i: int, ctx: Dictionary) -> void:
	if perm_json:
		ctx.errs.append("skills[%d] 是 permanent，%s.dur 也要写 \"permanent\"" % [i, p])
	for k in dv:
		if k != "ammo":
			ctx.errs.append("%s.dur.%s：dur 的对象写法只有 {\"ammo\": N}（次数型）" % [p, k])
	_num(dv, "ammo", p + ".dur", ctx, true, 1.0, 99.0)


## attack_patch（技能生效期间改普攻弹道）与 end（技能结束时执行一次）
static func _exu_skill(sb: Dictionary, p: String, ctx: Dictionary) -> void:
	if sb.has("attack_patch"):
		var ap = sb.attack_patch
		if not (ap is Dictionary):
			ctx.errs.append(p + ".attack_patch 必须是对象")
		else:
			var dv = sb.get("dur", 0)
			if not (dv is Dictionary) and not (dv is String) and _val(dv, ctx.base) <= 0.0:
				ctx.errs.append(p + ".attack_patch 要配持续型或次数型（dur > 0 或 {\"ammo\": N}）")
			for k in ap:
				if not k in EXU_PATCH_KEYS:
					ctx.errs.append("%s.attack_patch.%s：只能改 %s" % [p, k, " / ".join(EXU_PATCH_KEYS)])
			for k in ["mult", "range_mult"]:
				_num(ap, k, p + ".attack_patch", ctx, false, 0.0, 20.0)
			_num(ap, "pierce", p + ".attack_patch", ctx, false, 0.0, 20.0)
			_num(ap, "burst", p + ".attack_patch", ctx, false, 1.0, 8.0)
			_num(ap, "burst_gap", p + ".attack_patch", ctx, false, 0.02, 1.0)
			_num(ap, "elite_prio", p + ".attack_patch", ctx, false, 1.0, 100.0)
			_num(ap, "spread_deg", p + ".attack_patch", ctx, false, 0.0, 90.0)
			if ap.has("src"):
				_src(ap, p + ".attack_patch", ctx, true)
			_list(ap.get("last_on_hit", []), p + ".attack_patch.last_on_hit", "on_hit", ctx)
	if sb.has("end"):
		_list(sb.end, p + ".end", "instant", ctx)
