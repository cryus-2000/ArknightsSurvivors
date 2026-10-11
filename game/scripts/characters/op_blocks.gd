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
		"dash_line":
			return tx_dash_start(o, b, dmg)   # 德克萨斯段：命中逐帧结算，这里只起冲
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
	if not (atk is Dictionary) or not str(atk.get("shape", "")) in ["circle", "cone", "dash_line"]:
		errs.append("blocks.attack 必须是一个伤害形状（shape.circle / shape.cone / shape.dash_line）")
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
			else:
				if perm_json:
					errs.append("skills[%d] 是 permanent，%s.dur 也要写 \"permanent\"" % [i, p])
				var ev := eval_expr(dv, base)
				if not ev[0]:
					errs.append("%s.dur：%s" % [p, ev[2]])
				elif ev[1] < 0.0:
					errs.append("%s.dur 不能为负" % p)
			for k in sb:
				if not k in ["dur", "do"]:
					errs.append("%s.%s：技能积木只有 dur / do 两个字段" % [p, k])
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
	if nm in TX_IMPL.get(fam, []):   # 德克萨斯段（文件末尾）
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



# ================================================================ 德克萨斯 texas（docs/61 §11）
# 第三批并行实装约定：每名干员的新积木在文件末尾各占一段（append-only）；核心部分只加三处转发：
# validate 的普攻形状表、_block 里 TX_IMPL 命中时转给 _tx_block、exec_shape 的 dash_line 分支。
# data_operator.gd 里对应的转发都标了「德克萨斯段」。状态存在干员的 tx 字典里（data_operator.gd 的 var tx）。
#
#  shape.dash_line   冲刺穿行：沿一条线段冲出 r（× op_range × 冲刺长度倍率），宽 w，用时 t、到头停 hold；
#                    逐帧扫过的线段内敌人各吃一次（不重复）。aim：nearest（最近敌人，手动普攻 A 方向类）/ densest（敌群最密处）/
#                    leader_dir（主控冲刺方向；本干员是主控时不另行位移，跟着主控的冲刺扫）/ reverse（上一次冲刺的反方向）。
#                    干员是主控时冲刺就是主控本体位移（同乌尔比安弹射，squad.update 把 g.ppos 拉过去），到头不停顿。
#                    其余参数同 shape.circle：mult、src、tags、power、on_hit（st.stun / st.slow）；fx：剑光帧条名（可选）；sfx：起冲时播的音（可选）
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
	"verb": ["sp_secs", "dash_mod", "buff_leader", "trail", "fx_scatter"],
	"trig": ["on_dash_end", "on_leader_dash", "on_skill_start", "on_skill_end"],
}
const TX_AIMS := ["nearest", "densest", "leader_dir", "reverse"]
const TX_LEADER_STATS := ["dash_cd"]
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
		"verb.buff_leader":
			if not str(b.get("stat", "")) in TX_LEADER_STATS:
				errs.append("%s.stat 只能是 %s" % [p, " / ".join(TX_LEADER_STATS)])
			if not str(b.get("op", "")) in ["add", "mult"]:
				errs.append(p + ".op 只能是 add / mult")
			_num(b, "value", p, ctx, true, -1.0, 4.0)
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
	if b.has("fx"):
		var fr: Array = g.V6_FRAMES.get(str(b.fx), [4, 20.0])
		o.fx({"kind": "strip", "strip": str(b.fx), "frames": int(fr[0]), "fps": float(fr[1]), "pos": d.to, "ang": dir.angle(), "sx": len / 128.0,
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
				o.fx({"kind": "strip", "strip": str(b.strip), "frames": int(fr[0]), "fps": float(fr[1]), "pos": p, "anchor": Vector2(0.5, 30.0 / 32.0),
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
			"verb.buff_leader":
				want.append([str(b.stat), str(b.op), float(b.value), ""])
	o.tx["len"] = (1.0 + la) * lm
	o.tx["w"] = (1.0 + wa) * wm


## 帧条粒子（data_operator._draw_pfx 转来）：kind = strip；delay 秒后起播，sx 横向缩放（冲刺剑光拉到冲刺长度）
static func tx_draw_pfx(o, f: Dictionary, a: float) -> bool:
	if str(f.get("kind", "")) != "strip":
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
