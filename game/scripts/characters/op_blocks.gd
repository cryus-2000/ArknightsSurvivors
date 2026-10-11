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
	for s in b.get("on_hit", []):
		for e in hits:
			apply_status(o, e, s)
	if b.has("fx") and fx_c != Vector2.INF:
		fx_play(o, b.fx, fx_c, fx_r, hits, fx_a)
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
	if not (atk is Dictionary) or not str(atk.get("shape", "")) in ["circle", "cone"]:
		errs.append("blocks.attack 必须是一个伤害形状（shape.circle / shape.cone）")
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
				if not k in ["dur", "do", "fx"]:
					errs.append("%s.%s：技能积木只有 dur / do / fx 三个字段" % [p, k])
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

const FX_KEYS := ["strip", "cond", "at", "layer", "fit", "scale", "max_scale", "n", "spread", "rise", "life", "every", "tint", "anchor", "off", "ang", "rot"]
const FX_LAYERS := ["floor", "over", "add", "behind", "front"]
## 贴身层：画在干员本体的后面 / 前面（draw_body 前后），积木生效期间循环，帧号 = floor(生效秒数 × fps) % 帧数，退出时 FX_BODY_FADE 秒淡出
const FX_BODY := ["behind", "front"]
const FX_BODY_FADE := 0.15
## 放大上限（每个 1x 美术像素至多几个世界像素）：同 render/vfx.gd FX_SCALE_MAX，免得颗粒比人物粗太多；条目可用 max_scale 改
const FX_SCALE_MAX := 3.2
const FX_AT := ["center", "self", "leader", "zone", "hits", "orbit"]
const ArtS = preload("res://scripts/art.gd")


## 瞬时播放：c / r 是出手形状的中心与半径（技能发动、常驻光环时是区域中心与半径），hits 是本次命中的敌人，ang 是锥形的朝向。
## 带 every 的条目（常驻定时播）和 at = orbit 的条目（绕行体常驻贴图）这里跳过
static func fx_play(o, entries, c: Vector2, r: float, hits: Array = [], ang := 0.0) -> void:
	if not (entries is Array):
		return
	for f in entries:
		if not (f is Dictionary) or float(f.get("every", 0.0)) > 0.0 or str(f.get("at", "center")) == "orbit" or str(f.get("layer", "")) in FX_BODY:
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
		if ev <= 0.0 or str(f.get("at", "center")) == "orbit" or str(f.get("layer", "")) in FX_BODY:
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


## 积木的 fx 里有没有贴身层条目
static func fx_has_body(entries) -> bool:
	if entries is Array:
		for f in entries:
			if f is Dictionary and str(f.get("layer", "")) in FX_BODY:
				return true
	return false


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
	var instant_owner: bool = owner in ["shape.circle", "shape.cone", "cast", "verb.sp_team"]
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
		if not (sn is String) or not (sn.begins_with("fx_") or sn.begins_with("proj_")):
			errs.append(q + ".strip 必须是 V6_FRAMES 里登记的帧条名（fx_* / proj_*）")
		if not str(f.get("layer", "over")) in FX_LAYERS:
			errs.append("%s.layer 只能是 %s" % [q, " / ".join(FX_LAYERS)])
		var at := str(f.get("at", "center"))
		if not at in FX_AT:
			errs.append("%s.at 只能是 %s" % [q, " / ".join(FX_AT)])
		elif at == "orbit" and owner != "shape.orbit":
			errs.append(q + ".at = orbit 只能挂在 shape.orbit 上")
		elif at == "hits" and not owner in ["shape.circle", "shape.cone"]:
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
