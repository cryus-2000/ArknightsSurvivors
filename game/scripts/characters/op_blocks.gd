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
	if not (atk is Dictionary) or not str(atk.get("shape", "")) in ["circle", "cone", "point_aoe"]:
		errs.append("blocks.attack 必须是一个伤害形状（shape.circle / shape.cone / shape.point_aoe）")
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
				if not k in ["dur", "do"] and not (k == "attack_patch" and dv is Dictionary):
					errs.append("%s.%s：技能积木只有 dur / do 两个字段（dur.next_n 另有 attack_patch）" % [p, k])
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
	if fam == "custom":
		ctx.custom += 1
		if not kind in ["skill", "instant"]:
			errs.append(p + "：custom 只能放在技能或触发器的 do 里（瞬时执行）")
		return
	var nm: String = str(b[fam])
	var tag := "%s.%s" % [fam, nm]
	if tag in ANGELINA_TAGS:
		_v_angelina(b, p, kind, ctx, tag)
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


# ================================================================ 安洁莉娜 angelina（docs/59 §5；docs/61 §11）—— 第三批追加段，只往后加
# 新积木：shape.point_aoe（落点弹）、verb.displace（拉 / 推 / 向心 / 环带整形）、verb.field（常驻力场）、verb.buff_leader（主控属性）、
# st.airborne（悬浮）、st.weightless（失重：受到的击退倍率）、st.dot（力场里的持续伤害）、trig.on_impact（落点触发）；
# 技能外壳 dur.next_n（{"next_attacks": N} + attack_patch）。
# 体型档（docs/60 §2.8 / §5「重量 / 力度」）：Boss 不位移、不悬浮（只吃写了 boss / boss_only 的子项）；精英位移 × elite_mult（缺省 0.5）、
# 控制时长 × 0.5；重型（enemies.json heavy）位移 × 0.3（就是 enemies.gd 对 e.kb 的既有折扣，这里先算进去好夹住不越过中心）。
# 位移走 e.kb（速度，enemies.gd 每秒衰减 KB_DECAY），所以自动乘 g.enemy_kb_mult：藏品 #103「安洁莉娜的创想」受到的击退 +40% = 拉得远 40%。

const ANGELINA_TAGS := ["shape.point_aoe", "verb.displace", "verb.field", "verb.buff_leader", "st.airborne", "st.weightless", "st.dot", "trig.on_impact"]
const KB_DECAY := 900.0                       # enemies.gd：e.kb.move_toward(ZERO, 900 * dt)
const LEADER_STATS := ["move_speed", "pickup"]   # verb.buff_leader 可写的主控属性（全局作用域）
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


## verb.displace 瞬时：中心（target = 落点 / zone / leader / self）半径 r（× 本干员 area 倍率）内的敌人逐个位移，再对动了的敌人施加 on_hit
static func displace_at(o, b: Dictionary, at: Vector2 = Vector2.INF) -> void:
	var c: Vector2 = shape_center(o, b, at)
	if c == Vector2.INF:
		return
	var r: float = float(b.get("r", 0.0)) * float(o.loc.area)
	var sc: float = float(o.shot.get("force_mult", 1.0))
	var moved: Array = []
	for j in o.query_ids(c, r + 24.0):
		var e: Dictionary = o.g.enemies[j]
		if e.dead or e.pos.distance_to(c) > r:
			continue
		if displace_one(o, e, c, b, sc):
			moved.append(e)
	for s in b.get("on_hit", []):
		for e in moved:
			status_one(o, e, s, c)
	if b.has("fx"):
		o.spawn_fx_sprite(str(b.fx), c, clampf(r / 30.0, 1.0, 3.2))   # fx_angelina_pull：外径 ≈ 30 美术像素，按半径缩放（docs/25 §6）


## 一名敌人吃一条状态（st.*）。c / ring / ring_w：within（离 c 不超过）与 where: ring（在环带 ±ring_w 内）的筛选。
## Boss：缺省不受；boss: true 也受（stun ×0.25 / slow 照常）；boss_only: true 只对 Boss
static func status_one(o, e: Dictionary, s: Dictionary, c := Vector2.INF, ring := -1.0, ring_w := 0.0) -> void:
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
	match str(s.get("_tag", "")):
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


## verb.field 中心：leader = 主控（图鉴演示以自己为中心），self = 自己
static func field_center(o, b: Dictionary) -> Vector2:
	if str(b.get("center", "leader")) == "self" or o.g.demo_op != "":
		return o.pos
	return o.g.ppos


## verb.field（docs/60 §8 第 22 条）：以 center 为心、半径 r（× op_range）的常驻力场，每 every 秒对场内敌人逐个执行 tick 子项
## （verb.displace / st.*）。ring：环带半径（displace dir: ring 往这里收；子项 where: ring 只作用于环带 ±ring_w）。生效当帧先跑一次。
## st：本积木的状态 {acc, c, r, ring, look, t}（data_operator 的 _state，绘制也读它）
static func field_tick(o, b: Dictionary, st: Dictionary, dt: float) -> void:
	var every: float = float(b.get("every", 0.5))
	st.acc = float(st.get("acc", every)) + dt
	st.c = field_center(o, b)
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
						status_one(o, e, s2, c, st.ring, rw)
			else:
				status_one(o, e, s, c, st.ring, rw)


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
				status_one(o, e, st, c)
	o._exec_list(b.get("then", []), c)
	o.impact(c)
	o.shot = {}


# ---------------------------------------------------------------- 安洁莉娜段：校验

## _block 的分流：tag 是本段的积木时由这里校验
static func _v_angelina(b: Dictionary, p: String, kind: String, ctx: Dictionary, tag: String) -> void:
	var errs: Array = ctx.errs
	var where_ok := {
		"shape.point_aoe": ["attack"],
		"verb.displace": ["skill", "instant", "field"],
		"verb.field": ["skill", "sustain"],
		"verb.buff_leader": ["skill", "sustain"],
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
		"verb.displace":
			var dirs: Array = ["pull", "push", "center", "ring"] if kind == "field" else ["pull", "push"]
			if not str(b.get("dir", "pull")) in dirs:
				errs.append("%s.dir 只能是 %s" % [p, " / ".join(dirs)])
			_num(b, "dist", p, ctx, true, 0.0, 400.0)
			_num(b, "elite_mult", p, ctx, false, 0.0, 1.0)
			if kind != "field":
				_num(b, "r", p, ctx, true, 1.0)
				if not str(b.get("center", "target")) in ["target", "zone", "leader", "self"]:
					errs.append(p + ".center 只能是 target / zone / leader / self")
			_list(b.get("on_hit", []), p + ".on_hit", "on_hit", ctx)
		"verb.field":
			_num(b, "r", p, ctx, true, 1.0)
			_num(b, "every", p, ctx, false, 0.1)
			_num(b, "ring", p, ctx, false, 0.0)
			_num(b, "ring_w", p, ctx, false, 1.0)
			if not str(b.get("center", "leader")) in ["leader", "self"]:
				errs.append(p + ".center 只能是 leader / self")
			if not str(b.get("look", "none")) in ["ring", "lift", "none"]:
				errs.append(p + ".look 只能是 ring / lift / none")
			var tk = b.get("tick", [])
			if not (tk is Array) or tk.is_empty():
				errs.append(p + ".tick 至少要一个子项（verb.displace / st.*）")
			else:
				_list(tk, p + ".tick", "field", ctx)
				for i in tk.size():
					if tk[i] is Dictionary and (str(tk[i].get("where", "")) == "ring" or str(tk[i].get("dir", "")) == "ring") and not b.has("ring"):
						errs.append("%s.tick[%d]：where / dir 为 ring 时力场要写 ring" % [p, i])
		"verb.buff_leader":
			if not str(b.get("stat", "")) in LEADER_STATS:
				errs.append("%s.stat 只能是 %s" % [p, " / ".join(LEADER_STATS)])
			if not str(b.get("op", "")) in ["add", "mult"]:
				errs.append(p + ".op 只能是 add / mult")
			_num(b, "value", p, ctx, true, 0.0, 5.0)
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
