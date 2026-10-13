## 干员积木（docs/61）：数据干员（data_operator.gd）的积木编译、校验与共享执行器。
## 只走 op_api / character.gd 的公开方法与 g 的公共状态，不碰 game.gd 内部（下划线函数）、enemies.gd、combat.gd。
## 确定性（docs/36 §3）：本文件不用任何随机数；画面只往干员自己的 pfx 里加粒子（不碰 g.rng）。
## 本文件也被 -s 测试脚本（tests/test_core.gd，经 character.gd 的 validate_operator）加载：不许引用 Sfx 等自动加载。
extends RefCounted

const Dc = preload("res://scripts/render/declutter.gd")   # render/hit_rings：攻击 / 技能命中的装饰圆圈开关（剑雨终结亮环）

## 已实现的积木（族 → 名）。docs/61 里标 📝 的写在 PLANNED：写了校验会报「已登记未实现」
const IMPL := {
	"shape": ["circle", "cone", "orbit"],
	"verb": ["heal", "lamp", "buff_self", "mode", "sp_team"],
	"aura": ["atk", "aspd", "skill_power", "range"],
	"st": ["stun", "slow", "slow_soft"],
	"trig": ["passive", "every_n", "tick", "on_kill"],
}
## 第三批（星熊 / 安洁莉娜 / 德克萨斯 / 能天使）实现的积木不在 IMPL 里，由 _block 按 SHARED_TAGS / EXT_BLOCKS / ANGELINA_TAGS / TX_IMPL / EXU_IMPL 分流到文件末尾各段；
## 这里只剩还没人实现的
## verb.summon / verb.shield / aura.heal / st.seal 在文件末尾「召唤 / 封印段」（SM_TAGS，10-12）
const PLANNED := {
	"shape": ["chain", "summon"],
	"verb": ["protect", "dash"],   # verb.cleanse / verb.guard / verb.summon_mod / trig.on_deploy 在文件末尾「召唤物扩展段」（§15.9）
	"aura": ["dps", "dr", "inspire"],
	"st": ["fragile", "bind", "mark"],
	"trig": ["stack"],
}
const FAMILIES := ["shape", "verb", "aura", "st", "trig", "custom"]
## 本干员的局部倍率（verb.buff_self 的 stat 取这些时不进 g.stats）
const LOCAL_STATS := ["zone", "dmg", "heal", "interval", "area", "force", "force_lit"]   # area / force / force_lit：安洁莉娜段（落点范围 / 位移距离 / 灯光内位移）
## verb.buff_self 可写进 g.stats 的干员属性（作用域 op:<id>）
const OP_STATS := ["op_atk", "op_aspd", "op_range", "op_skill_power", "op_shots"]   # op_shots：能天使（docs/61 §14）
const AURA_STAT := {"atk": "op_atk", "aspd": "op_aspd", "skill_power": "op_skill_power", "range": "op_range"}
const COND_OPS := [">=", "<=", "==", ">", "<"]
## blocks.attack 能用的普攻形状（第三批追加：point_aoe 安洁莉娜、dash_line 德克萨斯、projectile 能天使）
const ATTACK_SHAPES := ["circle", "cone", "point_aoe", "dash_line", "projectile"]


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
	var mc := mf_parse_cond(s, base)   # 召唤物扩展段：a && b、node:<id>、hurt_any
	if not mc.is_empty():
		return mc
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
			var mc := mf_cond(o, c)   # 召唤物扩展段的条件
			r = mc[1] if mc[0] else ext_cond_true(o, str(c.k))
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
			if b.get("ring", true):   # ring: false = 不画缺省地面环（fx 里自己画，§15.9）
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
		"projectile":   # 能天使段：弹体自推进，命中在 exu_tick 里结算，这里返回空
			exu_fire(o, b)
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
	if s.has("within") and c != Vector2.INF and e.pos.distance_to(c) > float(s.within) + float(e.r) * 0.5:
		return
	if str(s.get("where", "")) == "ring" and (ring < 0.0 or absf(e.pos.distance_to(c) - ring) > ring_w):
		return
	if str(s.get("st", "")) == "seal":   # 召唤 / 封印段：Boss 有自己的规则（缩短 + 免疫），不走下面的「Boss 缺省不受」
		seal_apply(o, e, s)
		return
	if e.boss and not (s.get("boss", false) or s.get("boss_only", false)):
		return
	if s.get("boss_only", false) and not e.boss:
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
		"st.pause":   # 能天使段：短停顿只对非精英（Boss 缺省同样不受）
			if not e.elite:
				e.stun = maxf(e.stun, float(s.dur) * k)


static func shape_center(o, b: Dictionary, at: Vector2 = Vector2.INF) -> Vector2:
	var cn: String = str(b.get("center", "zone"))
	if cn.begins_with("summon"):   # 召唤物扩展段：summon:<种类> = 这种召唤物所在处
		return mf_at_point(o, cn)
	match cn:
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
	if b.get("r_abs", false):   # 召唤物扩展段：r_abs = 半径不吃 op_range（凯尔希熔毁 130）
		return float(r)
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
	var ctx := {"base": base, "srcs": srcs, "errs": errs, "custom": 0, "summons": blocks.get("summons", {}), "sprites": d.get("sprites", {})}
	for k in blocks:
		if not k in ["zone", "attack", "trait", "skills", "talent", "progression", "summons"]:
			errs.append("blocks.%s：不认识的段（只能是 zone / attack / trait / skills / talent / progression / summons）" % k)
	if blocks.has("summons"):   # 召唤物种类（文件末尾「召唤 / 封印段」）
		_sm_kinds(blocks, ctx)
	if blocks.has("zone"):
		var z = blocks.zone
		if not (z is Dictionary):
			errs.append("blocks.zone 必须是对象")
		else:
			if not str(z.get("center", "")) in ["leader", "self"]:
				errs.append("blocks.zone.center 只能是 leader / self")
			_num(z, "r", "blocks.zone", ctx, true)
	var atk = blocks.get("attack", null)
	if atk is Dictionary and str(atk.get("shape", "")) == "support":   # 召唤物扩展段：不造成伤害的普攻（凯尔希的治疗）
		_mf_support(atk, ctx)
	elif not (atk is Dictionary) or not str(atk.get("shape", "")) in ATTACK_SHAPES:
		errs.append("blocks.attack 必须是一个伤害形状（%s）" % " / ".join(ATTACK_SHAPES.map(func(x): return "shape." + x)))
	else:
		_block(atk, "blocks.attack", "attack", ctx)
		_num(atk, "every", "blocks.attack", ctx, true, 0.1)
		_num(atk, "range", "blocks.attack", ctx, false)
	var atk_shape: String = str(atk.get("shape", "")) if atk is Dictionary else ""
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
			if dv is Dictionary and dv.has("ammo"):   # dur.ammo（能天使段：N 发子弹）
				_exu_dur(dv, p, perm_json, i, ctx)
			elif dv is Dictionary:   # dur.next_n（安洁莉娜段：接下来 N 次普攻）
				_v_next_n(sb, p, perm_json, ctx)
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
				if not k in ["dur", "do", "fx", "aim", "status", "status_col"] + EXU_SKILL_KEYS:
					errs.append("%s.%s：技能积木只有 dur / do / fx / aim / status / status_col / attack_patch / end 这几个字段" % [p, k])
				elif k == "aim" and not (str(sb.aim) == "leader" or (str(sb.aim).begins_with("summon:") and ctx.summons is Dictionary and ctx.summons.has(str(sb.aim).substr(7)))):
					errs.append("%s.aim 只能是 leader / summon:<blocks.summons 里的种类>" % p)
				elif k == "attack_patch" and atk_shape == "point_aoe" and not (dv is Dictionary and dv.has("next_attacks")):
					errs.append("%s.attack_patch：落点弹普攻（shape.point_aoe）的 attack_patch 只能配 dur.next_n（{\"next_attacks\": N}）" % p)
			if sb.has("fx"):
				_fx(sb.fx, p + ".fx", ctx, "cast")
			_list(sb.get("do", []), p + ".do", "skill", ctx)
			_exu_skill(sb, p, ctx, atk_shape)   # 能天使段：attack_patch（落点弹的由 _v_next_n 查）/ end
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
	if b is Array:   # 召唤物扩展段（§15.9）：一个节点可以写几块积木（数组，按顺序生效）
		if b.is_empty() or b.size() > 8:
			ctx.errs.append(p + "：积木数组要有 1–8 块")
		for i in b.size():
			_node(b[i], "%s[%d]" % [p, i], ctx)
		return
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
	if _exu_block(b, p, kind, ctx, tag):   # 能天使段
		return
	if _sm_block(b, p, kind, ctx, tag):   # 召唤 / 封印段
		return
	if _mf_block(b, p, kind, ctx, tag):   # 召唤物扩展段（§15.9）
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
				if b.has("half"):   # 召唤物扩展段：half = 弧度（半角）
					_num(b, "half", p, ctx, true, 0.05, PI)
				else:
					_num(b, "half_deg", p, ctx, true)
				if str(b.get("center", "self")) != "self":
					errs.append(p + ".center：shape.cone 只能以自身为原点")
			elif str(b.get("center", "")).begins_with("summon:"):
				var sk2 := str(b.center).substr(7)
				if not (ctx.summons is Dictionary and ctx.summons.has(sk2)):
					errs.append("%s.center「%s」：summon: 后面应是 blocks.summons 里的种类" % [p, str(b.center)])
			elif not str(b.get("center", "zone")) in ["zone", "self", "leader", "target"]:
				errs.append(p + ".center 只能是 zone / self / leader / target / summon:<种类>")
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
			# 召唤物扩展段（§15.9）：scale / knight / on_over / text / sfx
			_num(b, "knight", p, ctx, false, 0.0, 1.0)
			_num(b, "text", p, ctx, false, 8.0, 40.0)
			if b.has("full") and not (b.full is bool):
				errs.append(p + ".full 只能是 true / false")
			if b.has("scale") and str(b.scale) != "op":
				errs.append(p + ".scale 只能是 op（× op_atk × 同伴倍率 × heal_out）")
			if b.has("on_over"):
				_list(b.on_over, p + ".on_over", "instant", ctx)
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

const FX_KEYS := ["strip", "vortex", "cond", "at", "layer", "fit", "scale", "max_scale", "n", "spread", "rise", "life", "every", "tint", "anchor", "off", "ang", "rot",
	"hold", "fade", "if_tex"]
## ground：紧贴地砖（溟痕 / Boss 地面预警 / 掉落之下），只给常驻跟随帧条（hold）用，大片地面特效不盖住危险提示（10-12 加）
const FX_LAYERS := ["floor", "over", "add", "behind", "front", "ground"]
## 常驻跟随帧条（hold: true，10-12 加）：积木生效期间循环、跟着区域中心 / 半径走，缺省淡入淡出秒数（条目 fade 可改）
const FX_HOLD_FADE := 0.3
const FX_HOLD_LAYERS := ["ground", "floor", "add"]
## 贴身层：画在干员本体的后面 / 前面（draw_body 前后），积木生效期间循环，帧号 = floor(生效秒数 × fps) % 帧数，退出时 FX_BODY_FADE 秒淡出
const FX_BODY := ["behind", "front"]
const FX_BODY_FADE := 0.15
## 放大上限（每个 1x 美术像素至多几个世界像素）：同 render/vfx.gd FX_SCALE_MAX，免得颗粒比人物粗太多；条目可用 max_scale 改
const FX_SCALE_MAX := 3.2
const FX_AT := ["center", "self", "leader", "zone", "hits", "orbit"]
## 只播一次的 fx 宿主（瞬时积木 / 技能发动 / 触发积木）：不能写 every、贴身层、漩涡（§8 第 9 条）。第三批新积木追加在这里
const FX_INSTANT_OWNERS := ["shape.circle", "shape.cone", "cast", "verb.sp_team",
	"shape.line", "verb.displace", "verb.field", "verb.negate_next", "trig.on_hurt", "trig.on_negate", "verb.summon", "verb.shield", "verb.guard"]
## 能写 at = hits 的宿主（带命中列表的伤害形状）
const FX_HITS_OWNERS := ["shape.circle", "shape.cone", "shape.line"]
## 自己在合适的位置播 fx 的积木：data_operator._exec_list 不再按区域中心替它们播
const FX_SELF_PLAY := ["shape.circle", "shape.cone", "shape.line", "verb.displace", "verb.field", "verb.negate_next", "verb.summon", "verb.shield", "verb.heal", "verb.guard"]
const ArtS = preload("res://scripts/art.gd")


## 瞬时播放：c / r 是出手形状的中心与半径（技能发动、常驻光环时是区域中心与半径），hits 是本次命中的敌人，ang 是锥形的朝向。
## 带 every 的条目（常驻定时播）和 at = orbit 的条目（绕行体常驻贴图）这里跳过
static func fx_play(o, entries, c: Vector2, r: float, hits: Array = [], ang := 0.0) -> void:
	if not (entries is Array):
		return
	for f in entries:
		if mf_is(f):   # 召唤物扩展段的程序条目
			if float(f.get("every", 0.0)) <= 0.0 and fx_on(o, f):
				mf_fx_spawn(o, f, {"c": c, "r": r, "hits": hits, "ang": ang})
			continue
		if not (f is Dictionary) or float(f.get("every", 0.0)) > 0.0 or str(f.get("at", "center")) == "orbit" or fx_is_hold(f):
			continue
		if fx_on(o, f):
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
			if fx_on(o, f):
				if mf_is(f):
					mf_fx_spawn(o, f, {"c": c, "r": r})
				else:
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


## 常驻跟随条目：贴身层（behind / front）、程序漩涡（vortex）或常驻跟随帧条（hold），积木生效期间一直画、退出淡出
static func fx_is_hold(f) -> bool:
	return f is Dictionary and (str(f.get("layer", "")) in FX_BODY or f.has("vortex") or _hold(f))


## 条目是不是常驻跟随帧条（hold: true；写成非布尔时按 false，校验另报错）
static func _hold(f: Dictionary) -> bool:
	var h = f.get("hold", false)
	return h is bool and h


## 条目这一刻画不画：cond（§1.3）+ if_tex（"fx_x" = 有这条贴图才画；"!fx_x" = 缺这条贴图才画，程序回退用；10-12 加）
static func fx_on(o, f: Dictionary) -> bool:
	if not cond_true(o, f.get("cond", {})):
		return false
	var it = f.get("if_tex", "")
	if it is String and it != "":
		var neg: bool = it.begins_with("!")
		var has: bool = o.g.tex.get(it.substr(1) if neg else it) != null
		return has != neg
	return true


## 常驻跟随条目的淡入 / 淡出秒数 Vector2(in, out)：条目 fade（数字 = 进出同长；[进, 出]）优先，
## 缺省：贴身层 (0, FX_BODY_FADE)，漩涡 (0.5, FX_VORTEX_FADE)，hold 帧条 (FX_HOLD_FADE, FX_HOLD_FADE)
static func fx_fade_io(f: Dictionary) -> Vector2:
	var d := Vector2(FX_HOLD_FADE, FX_HOLD_FADE)
	if f.has("vortex"):
		d = Vector2(0.5, FX_VORTEX_FADE)
	elif str(f.get("layer", "")) in FX_BODY:
		d = Vector2(0.0, FX_BODY_FADE)
	var v = f.get("fade", null)
	if v is Array and v.size() == 2:
		d = Vector2(float(v[0]), float(v[1]))
	elif v is int or v is float:
		d = Vector2(float(v), float(v))
	return d


## 积木退出后贴身层记录保留多久（= 各常驻跟随条目淡出秒数的最大值）
static func fx_hold_out(entries) -> float:
	var m := 0.0
	if entries is Array:
		for f in entries:
			if fx_is_hold(f):
				m = maxf(m, fx_fade_io(f).y)
	return m if m > 0.0 else FX_BODY_FADE


## 条目的进出透明度：e 是贴身层记录 {el = 生效秒数, fade = 退出后剩余秒数（< 0 = 生效中）}
static func fx_hold_alpha(f: Dictionary, e: Dictionary) -> float:
	var io := fx_fade_io(f)
	var a: float = 1.0 if io.x <= 0.0 else clampf(float(e.el) / io.x, 0.0, 1.0)
	if float(e.fade) >= 0.0:
		a *= clampf(float(e.fade) / io.y, 0.0, 1.0) if io.y > 0.0 else 0.0
	return a


## 常驻跟随帧条（hold: true）：积木生效期间在 at 点循环播（帧号 = floor(生效秒数 × fps) % 帧数），
## 写了 fit 时每帧按当前区域半径缩放（每个 1x 像素 = r / fit × scale，夹到 max_scale），区域变大变小即时跟上；进出按 fade 淡入淡出。
## layer：ground = 地砖之上、溟痕 / 地面预警 / 掉落之下（data_operator.draw_ground_fx）；floor = 区域椭圆层（draw_auras）；add = 加色层
static func fx_hold_strips(ci, o, e: Dictionary, layer: String, c_zone: Vector2, r_zone: float) -> void:
	var g = o.g
	for f in e.b.fx:
		if not (f is Dictionary) or not _hold(f) or str(f.get("layer", "floor")) != layer or not fx_on(o, f):
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
		col.a *= fx_hold_alpha(f, e) * float(g.world.fx_dim)
		if col.a <= 0.004:
			continue
		var c: Vector2 = c_zone
		match str(f.get("at", "zone")):
			"self":
				c = o.pos
			"leader":
				c = g.ppos
		if c == Vector2.INF:
			continue
		var ov = f.get("off", [])
		if ov is Array and ov.size() == 2:
			c += Vector2(float(ov[0]), float(ov[1]))
		var sc: float = float(f.get("scale", 1.0))
		var fit: float = float(f.get("fit", 0.0))
		sc *= r_zone / fit if fit > 0.0 and r_zone > 0.0 else g.PX
		sc = minf(sc, float(f.get("max_scale", FX_SCALE_MAX)))
		var av = f.get("anchor", [])
		var anc: Vector2 = Vector2(float(av[0]), float(av[1])) if av is Array and av.size() == 2 else Vector2(-1, -1)
		fx_frame(ci, g, name, frames, int(floor(float(e.el) * float(spec[1]))) % frames, c, sc, col, anc, deg_to_rad(float(f.get("ang", 0.0))))


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
			if f is Dictionary and o.g.tex.get(str(f.get("strip", ""))) != null and fx_on(o, f):
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
		if f is Dictionary and f.has("vortex") and fx_on(o, f):
			m = minf(m, float(_vp(f.vortex, "ring")))
	return m


## 画 e（贴身层记录 {b, el, fade, fl}）上 layer 层的漩涡条目。alpha：整体倍率（进出淡入淡出按条目 fade 在这里算，fx_hold_alpha）；sink：带 add_tris 的合批画布或 CanvasItem
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
		var want: float = 1.0 if fx_on(o, f) else 0.0
		var ca: float = float(e.va.get(i, want))
		ca = move_toward(ca, want, dt / 0.35)
		e.va[i] = ca
		var al: float = alpha * fx_hold_alpha(f, e) * ca * float(g.world.fx_dim)
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


## 贴身层（behind / front）：锚点对准干员脚底 o.pos（+ off）；e 是贴身层记录 {b, el = 积木已生效秒数, fade}，进出淡入淡出按条目 fade（fx_hold_alpha）
static func fx_body(ci, o, e: Dictionary, front: bool) -> void:
	var g = o.g
	var entries = e.b.get("fx", [])
	var el: float = float(e.el)
	if not (entries is Array) or o.pos == Vector2.INF:
		return
	for f in entries:
		if not (f is Dictionary) or str(f.get("layer", "")) != ("front" if front else "behind") or not fx_on(o, f):
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
		col.a *= fx_hold_alpha(f, e) * g.world.fx_dim
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
		if not (f is Dictionary) or str(f.get("at", "")) != "orbit" or not fx_on(o, f):
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
	if arr.size() > 16:
		errs.append("%s：一块积木至多 16 个 fx 条目，这里有 %d 个" % [p, arr.size()])
	var instant_owner: bool = owner in FX_INSTANT_OWNERS
	for i in arr.size():
		var q := "%s[%d]" % [p, i]
		var f = arr[i]
		if not (f is Dictionary):
			errs.append(q + " 必须是对象")
			continue
		if _mf_fx_check(f, q, ctx, owner):   # 召唤物扩展段的程序条目（pfx / sprite / sparks / ghost …）
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
		# 常驻跟随帧条 hold / 进出淡入淡出 fade / 按贴图有无取舍 if_tex（10-12 加，§5.6）
		if f.has("hold"):
			if not (f.hold is bool):
				errs.append(q + ".hold 必须是 true / false")
			elif f.hold:
				if f.has("vortex"):
					errs.append(q + ".hold：vortex 本来就跟着积木常驻，不写 hold")
				if instant_owner:
					errs.append(q + ".hold 是常驻跟随帧条，只能挂在常驻积木上（技能 do 里的常驻积木、光环等）")
				if not str(f.get("layer", "floor")) in FX_HOLD_LAYERS:
					errs.append("%s.layer：hold 帧条只能是 %s" % [q, " / ".join(FX_HOLD_LAYERS)])
				if not at in ["center", "zone", "self", "leader"]:
					errs.append(q + ".at：hold 帧条只能是 zone / self / leader")
				for k in ["every", "life", "n", "spread", "rise", "rot"]:
					if f.has(k):
						errs.append("%s.%s：hold 帧条跟着积木生效循环，不写这个字段" % [q, k])
		if str(f.get("layer", "")) == "ground" and not _hold(f):
			errs.append(q + ".layer = ground 只给常驻跟随帧条（hold: true）用")
		if f.has("fade"):
			var fv = f.fade
			if not fx_is_hold(f):
				errs.append(q + ".fade 只用于常驻跟随条目（贴身层 / vortex / hold 帧条）")
			if fv is int or fv is float:
				if float(fv) < 0.0 or float(fv) > 5.0:
					errs.append(q + ".fade 超出范围（0–5 秒）")
			elif fv is Array and fv.size() == 2 and fv.all(func(x): return x is int or x is float):
				if fv.any(func(x): return float(x) < 0.0 or float(x) > 5.0):
					errs.append(q + ".fade 超出范围（0–5 秒）")
			else:
				errs.append(q + ".fade 必须是秒数，或 [淡入, 淡出] 两个秒数")
		if f.has("if_tex"):
			var tn = f.if_tex
			var tb: String = tn.trim_prefix("!") if tn is String else ""
			if not (tb.begins_with("fx_") or tb.begins_with("proj_")):
				errs.append(q + ".if_tex 必须是帧条名（fx_* / proj_*），前面加 ! 表示缺这条贴图时才画")
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
#                    逐帧扫过的线段内敌人各吃一次（不重复）。aim：nearest（最近敌人，手动普攻 A 方向类）/ densest（敌群最密处；附近没有敌人就不冲）/
#                    leader_dir（主控冲刺方向；本干员是主控时不另行位移，跟着主控的冲刺扫）/ reverse（上一次冲刺的反方向）。
#                    干员是主控时冲刺就是主控本体位移（同乌尔比安弹射，squad.update 把 g.ppos 拉过去），到头不停顿。
#                    其余参数同 shape.circle：mult、src、tags、power、on_hit（st.stun / st.slow）；strip：剑光帧条名（可选，冲刺专用画法：拉到冲刺长度、半程起播；不是通用 fx 字段）；sfx：起冲时播的音（可选）
#  verb.sp_secs      瞬时：编队技能各 +seconds 秒充能（推进之王 _squad_sp_seconds 的写法；不吃回复倍率）；exclude_self 缺省 true
#  verb.dash_mod     常驻：本干员冲刺长度 / 宽度倍率（len_add / len_mult / w_add / w_mult；(1 + Σadd) × Πmult）
#  （verb.buff_leader 合并后在「共用积木」段；德克萨斯自动冲刺改版后不再改主控冲刺冷却）
#  verb.trail        瞬时（放在 trig.on_dash_end 里）：沿刚结束的那次冲刺留下 life 秒的残像，踩进的敌人各吃一次 mult 伤害 + on_hit
#  verb.fx_scatter   瞬时、只有画面：在 center（self / target）半径 r 内撒 n 个帧条（strip），错开 stagger 秒起播；不碰 g.rng
#  verb.fx_rain      瞬时、只有画面（10-12 加，§13.5）：剑雨编排——按面积密度撒剑、错开下落 + 残影、落地前地面预兆、冲击帧条、插地停留、焦痕、终结亮环；只用 g.vrng
#  trig.on_dash_end  本干员任一次 dash_line 结束时：src（只认这个伤害来源的冲刺，缺省全部）、min_hits（这次扫中的敌人数下限）、delay
#  trig.on_leader_dash  主控按下冲刺（g.dash_t 上升沿）：cd（两次之间至少隔几秒）。积木保留可用；德克萨斯 10-12 改自动冲刺后不再用它
#  trig.on_skill_start / trig.on_skill_end  本干员技能 skill（0 起）出手 / 持续结束：delay（只 on_skill_start）

const TX_IMPL := {
	"shape": ["dash_line"],
	"verb": ["sp_secs", "dash_mod", "trail", "fx_scatter", "fx_rain"],   # verb.buff_leader 在「共用积木」段
	"trig": ["on_dash_end", "on_leader_dash", "on_skill_start", "on_skill_end"],
}
const TX_AIMS := ["nearest", "densest", "leader_dir", "reverse"]
const TxArt = preload("res://scripts/art.gd")


## 校验（由 _block 转来；cond 与 $ 表达式已在 _block 里查过）
static func _tx_block(b: Dictionary, p: String, kind: String, tag: String, ctx: Dictionary) -> void:
	var errs: Array = ctx.errs
	var instant: bool = tag in ["shape.dash_line", "verb.sp_secs", "verb.trail", "verb.fx_scatter", "verb.fx_rain"]
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
		"verb.fx_rain":
			_tx_rain_validate(b, p, ctx)
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
			if b.has("at"):   # 召唤物扩展段（§15.9）：do 里 center: target 落在这个点；on_skill_end 带 at 时也能写 delay
				var atv := str(b.at)
				if not (atv in ["self", "leader"] or (atv.begins_with("summon:") and ctx.summons is Dictionary and ctx.summons.has(atv.substr(7)))):
					errs.append(p + ".at 只能是 self / leader / summon:<blocks.summons 里的种类>")
			if tag == "trig.on_skill_start" or b.has("at"):
				_num(b, "delay", p, ctx, false, 0.0, 5.0)
			elif b.has("delay"):
				errs.append(p + "：trig.on_skill_end 不写 at 时不支持 delay")
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
	var aim: String = str(b.get("aim", "nearest"))
	var len: float = tx_len(o, b)
	var pd := Vector2.INF
	if aim == "densest":
		# 朝敌群冲：附近没有敌人就不冲（德克萨斯天赋自动冲刺 / 剑雨滂沱；她当主控时不把主控带去空地）
		pd = _tx_densest(o, len * 1.6)
		if pd == Vector2.INF:
			return []
	if o.tx.has("dash"):
		_tx_dash_end(o)
	var dir := Vector2.ZERO
	match aim:
		"nearest":
			var ts: Array = o.nearest_enemies(1, len * 1.3, o.pos)
			var ang: float = (ts[0].pos - o.pos).angle() if not ts.is_empty() else o.facing_angle()
			dir = Vector2.from_angle(o.atk_angle(ang))
		"densest":
			dir = (pd - o.pos).normalized() if pd.distance_to(o.pos) > 1.0 else Vector2(o.face, 0.0)
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
				if str(t.get("_tag", "")) == "trig.on_skill_end" and not t.has("at") and int(t.get("skill", -1)) == i and cond_true(o, t.get("cond", {})):   # 带 at 的在 mf_tick（帧开头）
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
		if t.has("at"):   # 召唤物扩展段：点在触发这一刻取，delay 进本干员延迟队列
			mf_fire_at(o, t, mf_at_point(o, str(t.at)))
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
		"verb.fx_rain":
			tx_rain(o, b, at)


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


## ---------------------------------------------------------------- verb.fx_rain（10-12 加，docs/61 §13.5；德克萨斯剑雨首用，docs/70）
## 瞬时、只有画面：半径 r 内按面积密度撒 n 柄剑，错开 stagger 秒、各自从 fall 像素高处 fall_t 秒加速落下（带 streak 道残影），
## 落地前 lead 秒地面出现预兆标记（mark 帧条前 mark_frames 帧），落地播冲击帧条（hit）、剑身插地停留 stick 秒、地面焦痕（mark 后半）停留 scorch 秒；
## finale：最后一柄落地后在中心再来一次放大的冲击 + 一圈亮环。落点：on_enemies 比例先落在半径内的敌人身上（近的先、第一波），其余黄金角铺满透视椭圆。
## 随机只用 g.vrng（画面），敌人位置只读（query_ids），不碰 g.rng / 玩法状态；伤害照旧由同一 do 里的 shape 瞬时结算（第一波 fall_t ≈ 0.1 秒内落地）。
## 一次施放 = 两个 pfx 粒子（kind tx_rain：上层剑 + 冲击，地面层标记 + 焦痕 + 终结亮环），共享同一份剑列表；同一张贴图连着画（合批）。
const TX_RAIN_KEYS := ["verb", "cond", "_doc", "strip", "hit", "mark", "r", "center", "density", "n", "n_min", "n_max", "stagger", "fall", "fall_t", "lead",
	"stick", "scorch", "scale", "scale_j", "tilt", "slant", "streak", "on_enemies", "alpha", "fall_frames", "mark_frames", "hit_scale", "mark_scale",
	"anchor", "hit_anchor", "mark_anchor", "layer", "finale"]
const TX_RAIN_FIN_KEYS := ["scale", "ring", "t", "col"]


static func _tx_rain_validate(b: Dictionary, p: String, ctx: Dictionary) -> void:
	var errs: Array = ctx.errs
	for k in b:
		if not str(k).begins_with("_") and not str(k) in TX_RAIN_KEYS:
			errs.append("%s：verb.fx_rain 没有参数「%s」" % [p, str(k)])
	for k in ["strip", "hit", "mark"]:
		if b.has(k) or k == "strip":
			var s = b.get(k, "")
			if not (s is String and s.begins_with("fx_")):
				errs.append("%s.%s 必须是帧条名（fx_*）" % [p, k])
	if not (b.has("density") or b.has("n")):
		errs.append(p + "：verb.fx_rain 要写 density（每 1 万平方像素几柄）或 n（固定柄数）")
	_num(b, "r", p, ctx, true, 0.0, 600.0)
	_num(b, "density", p, ctx, false, 0.05, 20.0)
	for k in ["n", "n_min", "n_max"]:
		_num(b, k, p, ctx, false, 1.0, 64.0)
	_num(b, "stagger", p, ctx, false, 0.0, 2.0)
	_num(b, "fall", p, ctx, false, 0.0, 600.0)
	_num(b, "fall_t", p, ctx, false, 0.02, 1.0)
	_num(b, "lead", p, ctx, false, 0.0, 1.0)
	_num(b, "stick", p, ctx, false, 0.0, 3.0)
	_num(b, "scorch", p, ctx, false, 0.0, 5.0)
	_num(b, "scale", p, ctx, false, 0.1, 4.0)
	_num(b, "scale_j", p, ctx, false, 0.0, 0.9)
	_num(b, "tilt", p, ctx, false, 0.0, 45.0)
	_num(b, "slant", p, ctx, false, -60.0, 60.0)
	_num(b, "streak", p, ctx, false, 0.0, 4.0)
	_num(b, "on_enemies", p, ctx, false, 0.0, 1.0)
	_num(b, "alpha", p, ctx, false, 0.05, 1.0)
	_num(b, "fall_frames", p, ctx, false, 1.0, 32.0)
	_num(b, "mark_frames", p, ctx, false, 0.0, 32.0)
	_num(b, "hit_scale", p, ctx, false, 0.1, 8.0)
	_num(b, "mark_scale", p, ctx, false, 0.1, 8.0)
	for k in ["anchor", "hit_anchor", "mark_anchor"]:
		if b.has(k) and not (b[k] is Array and b[k].size() == 2 and (b[k][0] is float or b[k][0] is int) and (b[k][1] is float or b[k][1] is int)):
			errs.append("%s.%s 要写 [x, y]（1x 帧内像素）" % [p, k])
	if not str(b.get("layer", "over")) in ["over", "add"]:
		errs.append(p + ".layer 只能是 over / add")
	if not str(b.get("center", "self")) in ["self", "target"]:
		errs.append(p + ".center 只能是 self / target")
	if b.has("n_min") and b.has("n_max") and b.n_min is float and b.n_max is float and float(b.n_min) > float(b.n_max):
		errs.append(p + "：n_min 大于 n_max")
	if b.has("finale"):
		if not b.finale is Dictionary:
			errs.append(p + ".finale 要写 {scale, ring, t, col}")
		else:
			for k in b.finale:
				if not str(k) in TX_RAIN_FIN_KEYS:
					errs.append("%s.finale 没有参数「%s」" % [p, str(k)])
			_num(b.finale, "scale", p + ".finale", ctx, false, 0.5, 3.0)
			_num(b.finale, "ring", p + ".finale", ctx, false, 0.0, 3.0)
			_num(b.finale, "t", p + ".finale", ctx, false, 0.0, 3.0)
			if b.finale.has("col") and not (b.finale.col is Array and b.finale.col.size() in [3, 4]):
				errs.append(p + ".finale.col 要写 [r, g, b] 或 [r, g, b, a]")


## 帧条规格：[贴图, 帧数, fps, 每帧宽（贴图像素）, 帧高, 锚点（贴图像素）, 1x 像素 → 贴图像素倍数]；缺图返回空
static func _tx_rain_spec(o, name: String, anchor, def_anchor: Vector2) -> Array:
	if name == "":
		return []
	var t: Texture2D = o._fx_tex(name)
	if t == null:
		return []
	var fr: Array = o.g.V6_FRAMES.get(name, [1, 12.0])
	var n: int = maxi(1, int(fr[0]))
	var hi: float = TxArt.hires_of(t)
	var fw: float = float(t.get_width() / n)
	var fh: float = float(t.get_height())
	var an: Vector2 = Vector2(float(anchor[0]), float(anchor[1])) * hi if anchor is Array else Vector2(fw * def_anchor.x, fh - def_anchor.y * hi)
	return [t, n, float(fr[1]), fw, fh, an, hi]


static func tx_rain(o, b: Dictionary, at: Vector2) -> void:
	var g = o.g
	var cc: Vector2 = o.pos if str(b.get("center", "self")) == "self" or at == Vector2.INF else at
	if cc == Vector2.INF:
		return
	var bs: Array = _tx_rain_spec(o, str(b.strip), b.get("anchor"), Vector2(0.5, 2.0))
	if bs.is_empty():
		return   # 缺剑的帧条：整条跳过（伤害形状自己的扩散环照旧）
	var r: float = float(b.r) * o.stat(&"op_range")
	var n: int
	if b.has("density"):
		n = clampi(int(round(float(b.density) * PI * r * r / 10000.0)), int(b.get("n_min", 6)), int(b.get("n_max", 48)))
	else:
		n = int(b.n)
	var cfg = g.get_node_or_null("/root/Cfg")   # 不直接写 Cfg：核心契约测试（-s 脚本模式）没有自动加载
	n = maxi(1, int(round(n * (float(cfg.fx_density()) if cfg != null else 1.0))))   # 低画质减半（同 vfx.sparks）
	var rng: RandomNumberGenerator = g.vrng
	var st: float = float(b.get("stagger", 0.4))
	var ft: float = float(b.get("fall_t", 0.1))
	var sc: float = float(b.get("scale", 1.0))
	var sj: float = float(b.get("scale_j", 0.15))
	var tilt: float = deg_to_rad(float(b.get("tilt", 5.0)))
	var slant: float = deg_to_rad(float(b.get("slant", 0.0)))
	# 第一波：半径内的敌人（含这一下刚打死的），近的先
	var pts: Array = []
	var ne: int = int(round(n * float(b.get("on_enemies", 0.0))))
	if ne > 0:
		var cand: Array = []
		for j in o.query_ids(cc, r):
			var ep: Vector2 = g.enemies[j].pos
			if ep.distance_squared_to(cc) <= r * r:
				cand.append(ep)
		cand.sort_custom(func(p1, p2): return p1.distance_squared_to(cc) < p2.distance_squared_to(cc))
		for k in mini(ne, cand.size()):
			pts.append(cand[k] + Vector2(rng.randf_range(-4.0, 4.0), rng.randf_range(-2.0, 2.0)))
	var first: int = pts.size()
	var m: int = n - first
	var u0: float = rng.randf()
	for k in m:
		var rad: float = r * sqrt((k + rng.randf_range(0.2, 0.8)) / float(m))
		var ang: float = u0 * TAU + k * 2.39996 + rng.randf_range(-0.3, 0.3)
		pts.append(cc + Vector2.from_angle(ang) * rad * Vector2(1.0, 0.55))
	var bl: Array = []
	var tmax := 0.0
	for k in pts.size():
		# 敌人身上的在前四分之一时间里落，其余在 stagger 里均匀铺开（抖动），第一柄贴着 0 秒
		var d: float = rng.randf_range(0.0, st * 0.25) if k < first else st * (float(k - first) + rng.randf()) / float(maxi(1, m))
		if k == 0:
			d = 0.0
		var a: float = slant + rng.randf_range(-tilt, tilt)
		bl.append({"p": pts[k], "d": d, "s": sc * (1.0 + rng.randf_range(-sj, sj)), "a": a, "fl": rng.randf() < 0.5})
		tmax = maxf(tmax, d)
	var hs: Array = _tx_rain_spec(o, str(b.get("hit", "")), b.get("hit_anchor"), Vector2(0.5, 4.0))
	var ms: Array = _tx_rain_spec(o, str(b.get("mark", "")), b.get("mark_anchor"), Vector2(0.5, -1.0))
	if not ms.is_empty() and not b.has("mark_anchor"):
		ms[5] = Vector2(ms[3], ms[4]) * 0.5   # 地面标记缺省锚点 = 帧中心
	var q := {"bs": bs, "hs": hs, "ms": ms, "fall": float(b.get("fall", 90.0)), "ft": ft, "lead": float(b.get("lead", 0.12)),
		"stick": float(b.get("stick", 0.35)), "scorch": float(b.get("scorch", 0.45)), "streak": int(b.get("streak", 2)), "al": float(b.get("alpha", 1.0)),
		"ff": clampi(int(b.get("fall_frames", maxi(1, bs[1] / 2))), 1, bs[1]), "mf": int(b.get("mark_frames", 0 if ms.is_empty() else maxi(1, ms[1] / 2))),
		"hsc": float(b.get("hit_scale", 1.0)), "msc": float(b.get("mark_scale", 1.0)), "c": cc, "r": r}
	var hd: float = 0.0 if hs.is_empty() else float(hs[1]) / maxf(1.0, float(hs[2]))
	var life: float = tmax + ft + maxf(maxf(q.stick, hd), q.scorch) + 0.05
	if b.has("finale") and b.finale is Dictionary:
		var fin: Dictionary = b.finale
		var c4: Array = fin.get("col", [1.0, 0.72, 0.4, 0.9])
		q["fin"] = {"t": float(fin.get("t", tmax + ft)), "scale": float(fin.get("scale", 1.6)), "ring": float(fin.get("ring", 1.0)),
			"col": Color(float(c4[0]), float(c4[1]), float(c4[2]), float(c4[3]) if c4.size() > 3 else 0.9)}
		life = maxf(life, float(q.fin.t) + maxf(hd * 1.5, 0.45) + 0.05)
	var add: bool = str(b.get("layer", "over")) == "add"
	o.fx({"kind": "tx_rain", "pos": cc, "life": life, "bl": bl, "q": q, "add": add})
	if not ms.is_empty() or q.has("fin"):
		o.fx({"kind": "tx_rain", "pos": cc, "life": life, "bl": bl, "q": q, "floor": true})


## 画一次施放（data_operator._draw_pfx / draw_fx_add 调）：上层 = 残影 → 剑 → 冲击（同贴图连着画）；地面层 = 预兆 / 焦痕标记 → 终结亮环
static func tx_rain_draw(ci, o, f: Dictionary) -> void:   # ci：干员的 cv（batch_canvas）或加色层 CanvasItem
	var g = o.g
	if g.perf_alt:   # --perfab 同局轮换：/b 桶不画剑雨（量净成本用；正常游戏恒为 false）
		return
	var q: Dictionary = f.q
	var el: float = float(f.max) - float(f.life)
	var base: float = float(q.al) * float(g.world.fx_dim)
	var ft: float = q.ft
	var px: float = g.PX
	if f.get("floor", false):
		var ms: Array = q.ms
		if not ms.is_empty():
			var tx: Texture2D = ms[0]
			var nf: int = ms[1]
			var mf: int = mini(int(q.mf), nf)
			for bl in f.bl:
				var tl: float = float(bl.d) + ft
				var t0: float = maxf(0.0, tl - float(q.lead))
				var fr := -1
				var al := base
				if el >= t0 and el < tl and mf > 0:
					fr = mini(mf - 1, int((el - t0) / maxf(0.001, tl - t0) * mf))
					al *= 0.85
				elif el >= tl and el < tl + float(q.scorch) and nf > mf:
					var k: float = (el - tl) / maxf(0.001, float(q.scorch))
					fr = mf + mini(nf - mf - 1, int(k * (nf - mf)))
					al *= 1.0 if k < 0.6 else (1.0 - k) / 0.4
				if fr < 0:
					continue
				var kk: float = px * float(bl.s) * float(q.msc) / float(ms[6])
				var sz := Vector2(ms[3], ms[4]) * kk
				ci.draw_texture_rect_region(tx, Rect2((bl.p as Vector2).round() - (ms[5] as Vector2) * kk, sz), Rect2(float(ms[3]) * fr, 0, ms[3], ms[4]), Color(1, 1, 1, al))
		if q.has("fin"):
			var fin: Dictionary = q.fin
			var k2: float = (el - float(fin.t)) / 0.4
			if k2 >= 0.0 and k2 < 1.0 and float(fin.ring) > 0.0:
				var rr: float = float(q.r) * float(fin.ring) * lerpf(0.25, 1.0, 1.0 - (1.0 - k2) * (1.0 - k2))
				var c: Color = fin.col
				ci.draw_set_transform(q.c, 0.0, Vector2(1.0, 0.55))
				if k2 < 0.6:   # 地面闪光：一片热橙椭圆迅速淡掉（程序画，合批三角形；不把冲击帧条放大成粗方块）
					var kf: float = 1.0 - k2 / 0.6
					ci.draw_circle(Vector2.ZERO, rr * 0.85, Color(1.0, 0.62, 0.3, 0.22 * kf * kf * base))
					ci.draw_circle(Vector2.ZERO, rr * 0.4, Color(1.0, 0.9, 0.72, 0.3 * kf * kf * base))
				if Dc.hit_rings():   # 终结亮环属命中装饰圈（render/hit_rings 缺省不画），地面闪光照画
					ci.draw_arc(Vector2.ZERO, rr, 0.0, TAU, 56, Color(c.r, c.g, c.b, c.a * (1.0 - k2) * base), 4.0)
					ci.draw_arc(Vector2.ZERO, rr * 0.92, 0.0, TAU, 56, Color(1.0, 0.95, 0.85, 0.6 * (1.0 - k2) * base), 1.5)
				ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	# 上层：剑（下落 + 残影 / 插地），同一张贴图
	var bs: Array = q.bs
	var btx: Texture2D = bs[0]
	var nb: int = bs[1]
	var ff: int = q.ff
	var fw: float = bs[3]
	var fh: float = bs[4]
	var ban: Vector2 = bs[5]
	var stick: float = q.stick
	for bl in f.bl:
		var d: float = bl.d
		if el < d:
			continue
		var tl: float = d + ft
		var kk: float = px * float(bl.s) / float(bs[6])
		var sx: float = -kk if bl.fl else kk
		var a: float = bl.a
		var p: Vector2 = bl.p
		if el < tl:
			var kf: float = (el - d) / maxf(0.001, ft)
			var dirv := Vector2(-sin(a), cos(a))   # 剑尖朝向（落向）
			var off: float = float(q.fall) * (1.0 - kf * kf)   # 先慢后快地扎下来
			var fr: int = int(el * float(bs[2])) % ff
			var src := Rect2(fw * fr, 0, fw, fh)
			var al: float = base * minf(1.0, kf * 5.0 + 0.2)
			for i in range(int(q.streak), -1, -1):
				var pp: Vector2 = p - dirv * (off + float(q.fall) * 0.16 * i)
				ci.draw_set_transform(pp.round(), a, Vector2(sx, kk))
				ci.draw_texture_rect_region(btx, Rect2(-ban, Vector2(fw, fh)), src, Color(1, 1, 1, al * pow(0.42, i)))
		elif el < tl + stick and nb > ff:
			var k3: float = (el - tl) / maxf(0.001, stick)
			var fr2: int = ff + mini(nb - ff - 1, int(k3 * (nb - ff)))
			ci.draw_set_transform(p.round(), a, Vector2(sx, kk))
			ci.draw_texture_rect_region(btx, Rect2(-ban, Vector2(fw, fh)), Rect2(fw * fr2, 0, fw, fh), Color(1, 1, 1, base * (1.0 if k3 < 0.7 else (1.0 - k3) / 0.3)))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 冲击帧条
	var hs: Array = q.hs
	if hs.is_empty():
		return
	var htx: Texture2D = hs[0]
	var hn: int = hs[1]
	var hfps: float = hs[2]
	var hw: float = hs[3]
	var hh: float = hs[4]
	for bl in f.bl:
		var e2: float = el - float(bl.d) - ft
		if e2 < 0.0:
			continue
		var fr3: int = int(e2 * hfps)
		if fr3 >= hn:
			continue
		var kh: float = px * float(bl.s) * float(q.hsc) / float(hs[6])
		ci.draw_texture_rect_region(htx, Rect2((bl.p as Vector2).round() - (hs[5] as Vector2) * kh, Vector2(hw, hh) * kh), Rect2(hw * fr3, 0, hw, hh), Color(1, 1, 1, base))
	if q.has("fin"):
		var fin2: Dictionary = q.fin
		var e3: float = el - float(fin2.t)
		var fr4: int = int(e3 * hfps * 0.75)   # 终结冲击放慢一点
		if e3 >= 0.0 and fr4 < hn:
			var kf2: float = px * float(fin2.scale) / float(hs[6])
			ci.draw_texture_rect_region(htx, Rect2((q.c as Vector2).round() - (hs[5] as Vector2) * kf2, Vector2(hw, hh) * kf2), Rect2(hw * fr4, 0, hw, hh), Color(1, 1, 1, base))
# ================================================================ 能天使 exusiai（docs/61 §14，2026-10-11 第三批第四人）
# 本段只追加。积木：弹道 shape.projectile、技能外壳 dur.ammo（次数型）+ attack_patch（技能生效期间改普攻）+ end（技能结束时执行）、
# trig.on_attack（命名计数器满时，这一次普攻换成 do 里的积木）、verb.counter（命名计数器）/ verb.counter_cap（常驻：改计数器上限）/
# verb.attack_lock（之后一段时间不普攻）/ verb.ricochet（常驻：弹体命中后按概率跳向附近另一名敌人）、st.pause（短停顿，只对非精英）。
# 上面的通用代码只插了几行挂钩（都标「能天使挂钩」）；data_operator.gd 同样只插挂钩，外加末尾的绘制 / 状态两个函数。
# 运行时状态放 o.ext（data_operator 的扩展字典）：bul 弹体、cnt / cap 计数器与上限、ammo 次数型技能剩余、lock 普攻锁、burst 连射队列、was 技能上一帧是否生效。
# 确定性（docs/36 §3）：选目标按「距离 ÷ 精英优先度」再按 id 排序；只有跳弹掷 g.rng（玩法随机，docs/61 §0.4）；画面不碰 g.rng。

const EXU_IMPL := {"shape": ["projectile"], "verb": ["counter", "counter_cap", "attack_lock", "ricochet"], "st": ["pause"], "trig": ["on_attack"]}
const EXU_SKILL_KEYS := ["attack_patch", "end"]
const EXU_PATCH_KEYS := ["mult", "pierce", "src", "tags", "tex", "power", "burst", "burst_gap", "range_mult", "elite_prio", "last_on_hit", "muzzle_fx", "spread_deg", "focus_boss", "kb", "hit_fx"]
const EXU_BULLET_MAX := 96            # 同时在场的弹体上限（docs/59 §4：上限约 36 发/秒 × 寿命 0.7 秒）
const EXU_AIM_Y := -10.0              # 瞄准 / 判定点：敌人脚底往上 10（身体中段）
const EXU_HIT_PAD := 6.0              # 判定半径 = 敌人半径 + 6
## 弹体帧条的弹头锚点（docs/25 §6，1x 像素；@2x 自动 ×2）
const EXU_TEX_ANCHOR := {"proj_exusiai_bullet": Vector2(12, 3), "proj_exusiai_bullet_power": Vector2(15, 4),
	"proj_exusiai_bullet_s1": Vector2(15, 4), "proj_exusiai_bullet_s2": Vector2(12, 3), "proj_exusiai_bullet_s3": Vector2(12, 3)}   # 技能弹药换色帧条（docs/25 §6.1）同源帧条的锚点
## 画面帧条字段（tex 弹体 / muzzle_fx 枪口焰 / hit_fx 命中火花）：纯画面，不进结算；缺省 = 能天使的普攻那一套
const EXU_FX_KEYS := {"tex": "proj_", "muzzle_fx": "fx_", "hit_fx": "fx_"}
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
		var dv = sb.get("dur", 0)
		if sb.has("end") or (dv is Dictionary and dv.has("ammo")):   # dur.next_n + attack_patch 是安洁莉娜段的落点弹，不归这里
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
	var mfx: String = str(p.get("muzzle_fx", "fx_exusiai_muzzle"))
	for k in n:
		var q := p
		if ap[0] >= 0 and int(st.ammo[ap[0]]) > 0:
			q = _exu_merge(p, ap[1])
			st.ammo[ap[0]] = int(st.ammo[ap[0]]) - 1
			if k == 0:
				mfx = str(q.get("muzzle_fx", mfx))   # 次数型技能的补丁是逐发合并的：枪口焰跟第一发子弹走（冲锋模式的青色焰）
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
				"tags": q.get("tags", []), "pierce": int(q.get("pierce", 0)), "kb": float(q.get("kb", 0.0)), "hit": {}, "tex": str(q.get("tex", "")), "hfx": str(q.get("hit_fx", "fx_exusiai_hit")), "on_hit": oh, "ric": true})
	o.spawn_fx_sprite(mfx, mz + d0 * 7.0 * g.PX * 0.8, g.PX * 0.8, d0.angle())


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
			o.spawn_fx_sprite(str(bu.get("hfx", "fx_exusiai_hit")), e.pos + Vector2(0, EXU_AIM_Y), g.PX * 0.8)
			if bu.ric and not ric.is_empty() and g.rng.randf() < float(ric.get("chance", 0.0)):
				var nx = _exu_next(o, e, float(ric.get("r", 120.0)))
				if nx != null:
					var from: Vector2 = e.pos + Vector2(0, EXU_AIM_Y)
					var spd: float = bu.v.length()
					spawn.append({"p": from, "v": (nx.pos + Vector2(0, EXU_AIM_Y) - from).normalized() * spd, "life": float(ric.get("r", 120.0)) * 1.4 / spd,
						"dmg": bu.dmg * float(ric.get("mult", 0.5)), "src": str(ric.get("src", "")), "tags": [], "pierce": 0, "hit": {e.id: true},
						"tex": bu.tex, "hfx": bu.get("hfx", "fx_exusiai_hit"), "on_hit": [], "ric": false})
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
			_exu_fx_ok(b, p, ctx)
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


## tex / muzzle_fx / hit_fx：帧条名（小写字母、数字、下划线，tex 以 proj_ 开头、另两个以 fx_ 开头）；帧条要在 game.gd V6_FRAMES 登记（exusiai_blocks 场景测试查）
static func _exu_fx_ok(b: Dictionary, p: String, ctx: Dictionary) -> void:
	for k in EXU_FX_KEYS:
		if not b.has(k):
			continue
		var v = b[k]
		var re := RegEx.create_from_string("^[a-z0-9_]+$")
		if not (v is String) or not str(v).begins_with(EXU_FX_KEYS[k]) or re.search(str(v)) == null:
			ctx.errs.append("%s.%s 应是帧条名（%s…，小写字母 / 数字 / 下划线）" % [p, k, EXU_FX_KEYS[k]])


## dur.ammo：{"ammo": N}，次数型（与 permanent 互斥）
static func _exu_dur(dv: Dictionary, p: String, perm_json: bool, i: int, ctx: Dictionary) -> void:
	if perm_json:
		ctx.errs.append("skills[%d] 是 permanent，%s.dur 也要写 \"permanent\"" % [i, p])
	for k in dv:
		if k != "ammo":
			ctx.errs.append("%s.dur.%s：dur 的对象写法只有 {\"ammo\": N}（次数型）" % [p, k])
	_num(dv, "ammo", p + ".dur", ctx, true, 1.0, 99.0)


## attack_patch（技能生效期间改普攻弹道）与 end（技能结束时执行一次）
static func _exu_skill(sb: Dictionary, p: String, ctx: Dictionary, atk_shape := "") -> void:
	if sb.has("attack_patch") and atk_shape != "point_aoe":
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
			_exu_fx_ok(ap, p + ".attack_patch", ctx)
			if ap.has("src"):
				_src(ap, p + ".attack_patch", ctx, true)
			_list(ap.get("last_on_hit", []), p + ".attack_patch.last_on_hit", "on_hit", ctx)
	if sb.has("end"):
		_list(sb.end, p + ".end", "instant", ctx)


# ================================================================ 召唤 / 封印 / 护盾 / 治疗光环（docs/61 §15，10-12 通用积木，下一批干员备用）
# 通用积木，现在还没有正式干员用（测试专用干员 tests/data_ops/sstest.json 演示全部写法）。核心部分只加了几处转发：
# validate 认 blocks.summons 段、_block 里 SM_TAGS 命中时转给 _sm_block、apply_status 的 st.seal 绕开「Boss 缺省不受」（Boss 有自己的规则）。
# data_operator.gd 对应的转发都标了「召唤 / 封印段」；运行时状态在干员的 sm 字典（不放 ext：ext 非空会被能天使段当成用得到）。
# 游戏侧挂点（敌人一侧，封印读 e.seal_t）：run/enemies.gd 2 处（特殊招式 pattern、远程开火）、boss_ai.gd 1 处（Boss 出招 ready）、
# run/combat.gd 2 处（甲壳 / 潮盾词条失效）+ 1 处（受击询问时把这一下的伤害放进 combat.cur_dmg，护盾用）。没有封印 / 护盾时这些分支都不走，老干员逐字节不变。
#
#  verb.summon  瞬时：召唤 n 个 kind（写在 blocks.summons.<kind>）的召唤物。at：self（缺省）/ leader / target / zone；spread 散开半径；life 可覆盖种类的 life
#  st.seal      命中状态（on_hit / 力场 tick）：封印 dur 秒——非 Boss 敌人不起新的特殊招式（enemy_ai 的 pattern：冲刺 / 吐酸 / 环弹 / 神经光环 / 额外招式……）、
#               不远程开火、甲壳 / 潮盾词条失效；已经起手的蓄力照常打完。精英 × elite_mult；
#               Boss：时长 × boss_mult、封顶 boss_max 秒，期间不起新招（冷却照走 = 推迟下一招），封印结束后 boss_immune 秒免疫
#  verb.shield  瞬时：主控护盾 + pct × 最大生命（总量封顶 cap × 最大生命），dur 秒后消失，每秒按当前量衰减 decay；吸收在减伤（verb.dr）之后、护甲 / 法抗之前
#  aura.heal    常驻：scope in_zone（缺省，主控在本干员区域内）/ always，每秒回复主控 pct × 最大生命（× 局部 heal 倍率 [× 技能强度]）；满血时不治

const SM_TAGS := ["verb.summon", "st.seal", "verb.shield", "aura.heal"]
const SM_MOVES := ["orbit", "chase", "stay", "follow"]
const SM_TARGETS := ["nearest", "densest", "elite", "low_hp"]
const SM_AT := ["self", "leader", "target", "zone", "rest"]   # rest：escort 召唤物的闲时站位（§15.9）
const SM_KIND_KEYS := ["name", "hp", "invuln", "life", "cap", "r", "col", "move", "attack", "on_spawn", "on_expire", "body", "enemy_target", "decoy_r", "hurt_mult", "_doc"]
const SM_MOVE_KEYS := ["mode", "speed", "anchor", "leash", "orbit_r", "orbit_speed", "target"]
const SM_BODY_KEYS := ["strip", "frames", "fps", "scale", "anchor", "tint", "flip", "hover"]
const SM_TOTAL_CAP := 24      # 全编队同时在场的召唤物上限（性能：每个召唤物 = 一个 2.5D 排序条目 + 一次贴图 / 几何绘制）
const SM_KIND_CAP := 12       # 每种召唤物 cap 的上限（校验）
const SM_FAR := 900.0         # 离锚点超过这么远（主控冲刺 / 传送）直接拉回锚点
const SM_GOLD := 2.39996      # 黄金角：召唤落点 / 围攻站位的确定性散布（不取随机数）
const SEAL_COL := Color(0.66, 0.45, 1.0)
const SHIELD_COL := Color(0.55, 0.9, 1.0)


static func sm_st(o) -> Dictionary:
	if o.sm.is_empty():
		o.sm.merge({"list": [], "seq": 0, "ang": {}, "seal": {}, "shield": 0.0, "shield_max": 0.0, "shield_t": 0.0, "shield_decay": 0.0, "heal_acc": {}})
	return o.sm


static func sm_kind(o, k: String) -> Dictionary:
	return o.B.get("summons", {}).get(k, {})


## 全编队在场的召唤物数（SM_TOTAL_CAP 用）
static func sm_total(o) -> int:
	var sq = o.g.get("squad")
	if sq == null or not (o in sq.ops):
		return o.sm.get("list", []).size()
	var n := 0
	for m in sq.ops:
		var s = m.get("sm")
		if s is Dictionary and s.has("list"):
			n += s.list.size()
	return n


## 瞬时积木（data_operator._exec_list 的缺省分支转来）
static func sm_exec(o, b: Dictionary, at: Vector2) -> void:
	match str(b.get("_tag", "")):
		"verb.summon":
			sm_spawn(o, b, at)
		"verb.shield":
			shield_add(o, b)


# ---------------------------------------------------------------- 召唤物

## 召唤：每个召唤物 {id, kind, pos, face, t, life（< 0 不限时）, skill（life: skill 时绑定的技能序号）, hp, max_hp, inv, tgt, cd, anim, rt, hurt, flash, gone}
static func sm_spawn(o, b: Dictionary, at: Vector2) -> void:
	var g = o.g
	var kind: String = str(b.get("kind", ""))
	var kd := sm_kind(o, kind)
	if kd.is_empty():
		return
	var st := sm_st(o)
	var c := Vector2.INF
	match str(b.get("at", "self")):
		"leader":
			c = g.ppos
		"target":
			c = at
		"zone":
			c = o.zone_c()
		"rest":
			c = mf_rest(o, kd.get("move", {}))
		_:
			c = o.pos
	if c == Vector2.INF:
		c = g.ppos
	if c == Vector2.INF:
		return
	var lv = b.get("life", kd.get("life", 0.0))
	var life := -1.0
	var sk := -1
	if lv is String:
		if lv == "skill":
			sk = o.cur_skill
	elif float(lv) > 0.0:
		life = float(lv)
	var n: int = int(b.get("n", 1))
	var spread: float = float(b.get("spread", 28.0))
	var cap: int = int(kd.get("cap", 1))
	var hp: float = float(kd.get("hp", 0.0))
	for k in n:
		var same: Array = st.list.filter(func(q): return q.kind == kind)
		if same.size() >= cap:
			_sm_end(o, same[0], "cap")   # 同种超过 cap：最早的先到期（也执行 on_expire）
		if sm_total(o) >= SM_TOTAL_CAP:
			break
		st.seq += 1
		var a: float = float(st.seq) * SM_GOLD
		var rr: float = spread * (0.5 + 0.5 * float(k + 1) / float(n))
		var p: Vector2 = c + Vector2(cos(a) * rr, sin(a) * rr * 0.55)
		var esc: bool = str(kd.get("move", {}).get("mode", "")) == "escort"
		if esc and n == 1:
			p = c   # 随行召唤物：就站在落点（rest 时 = 闲时站位）
		var s := {"id": int(st.seq), "kind": kind, "pos": p, "face": 1.0 if esc else float(o.face), "t": 0.0, "life": life, "skill": sk,
			"hp": hp, "max_hp": maxf(1.0, hp), "inv": bool(kd.get("invuln", false)), "tgt": null, "cd": float(kd.get("attack", {}).get("first", 0.25)), "anim": 0.0, "rt": 0.0,
			"hurt": {}, "flash": 0.0, "gone": false}
		if esc:   # 召唤物扩展段（§15.9）的状态：动画、出手动作、绕行、追击队列、patch、残影、画面计时
			s.merge({"mv": 0.0, "ak": "idle", "at": 0.0, "act": 0.0, "fire": -1.0, "flip_t": -99.0, "via": Vector2.INF, "via_t": 0.0, "via_off": -99.0,
				"pend": [], "pidx": -1, "pt": 0.0, "pout": 0.0, "pold": -1, "pcur": {}, "ghost": {}, "fxt": {}, "swing": 1.0, "cmd_t": 0.0})
		st.list.append(s)
		o.fx({"kind": "ring", "pos": p, "r": float(kd.get("r", 10.0)) * 2.4, "r0": 4.0, "life": 0.35, "col": _sm_col(o, kd), "floor": true, "w": 2.0, "alpha": 0.8, "keep": true})
		if b.has("fx"):
			fx_play(o, b.fx, p, float(kd.get("r", 10.0)) * 2.0)
		o._exec_list(kd.get("on_spawn", []), p)


static func _sm_col(o, kd: Dictionary) -> Color:
	var cv = kd.get("col", [])
	if cv is Array and cv.size() >= 3:
		return Color(float(cv[0]), float(cv[1]), float(cv[2]))
	return o.col()


## 一个召唤物结束（why：life / skill / dead / cap / leave）：移出列表，leave 以外执行 on_expire（中心 target = 召唤物位置）
static func _sm_end(o, s: Dictionary, why: String) -> void:
	if s.gone:
		return
	s.gone = true
	o.sm.list.erase(s)
	var kd := sm_kind(o, str(s.kind))
	o.fx({"kind": "ring", "pos": s.pos, "r": float(kd.get("r", 10.0)) * 2.0, "r0": float(kd.get("r", 10.0)), "life": 0.3, "col": _sm_col(o, kd), "floor": true, "w": 2.0, "alpha": 0.6, "keep": true})
	if why != "leave":
		o._exec_list(kd.get("on_expire", []), s.pos)


## 干员离队 / 局结束：清掉召唤物（不执行 on_expire）、护盾、封印标记
static func sm_clear(o) -> void:
	if o.sm.is_empty():
		return
	for s in o.sm.list.duplicate():
		_sm_end(o, s, "leave")
	o.sm.shield = 0.0
	o.sm.seal = {}


static func _sm_anchor(o, mv: Dictionary) -> Vector2:
	var p: Vector2 = o.pos if str(mv.get("anchor", "leader")) == "self" else o.g.ppos
	return p if p != Vector2.INF else o.g.ppos


## 攻击距离（世界像素）：写了 range 用 range × op_range；否则按形状（circle 以自身为心 = r，以目标为心 = 40；cone = r；line = len）
static func sm_reach(o, a: Dictionary) -> float:
	if a.is_empty():
		return 0.0
	var k: float = o.stat(&"op_range")
	if a.has("range"):
		return float(a.range) * k
	match str(a.get("shape", "")):
		"circle":
			return float(a.get("r", 30.0)) * k if str(a.get("center", "self")) == "self" else 40.0 * k
		"line":
			return float(a.get("len", 60.0)) * k
	return float(a.get("r", 30.0)) * k


## 能当目标：活着、不是友方单位、不是宝箱
static func _sm_ok(e) -> bool:
	return e != null and not e.dead and not e.get("friendly", false) and not e.chest


static func _hp_frac(e: Dictionary) -> float:
	return float(e.hp) / maxf(1.0, float(e.maxhp))


## 选目标（chase）：锚点 leash 内。nearest = 离召唤物最近（同伴已盯上的往后排，分散开；含 Boss 优先，同 nearest_enemies）；
## densest = 敌群最密处最近的；elite = Boss → 精英 → 其余（同档近的先，cap_targets 的顺序）；low_hp = 生命比例最低（同比例按 id）。全部确定性，不取随机数
static func _sm_pick(o, s: Dictionary, mv: Dictionary, anc: Vector2, leash: float):
	var g = o.g
	var taken := {}
	for q in o.sm.list:
		if q != s and q.tgt != null:
			taken[int(q.tgt.id)] = true
	var cand: Array = []
	var how: String = str(mv.get("target", "nearest"))
	match how:
		"densest":
			var dp: Vector2 = o.densest_point(leash, anc)
			if dp == Vector2.INF:
				return null
			cand = o.nearest_enemies(1, 60.0, dp)
		"elite", "low_hp":
			for j in o.query_ids(anc, leash):
				var e: Dictionary = g.enemies[j]
				if _sm_ok(e) and e.pos.distance_to(anc) <= leash:
					cand.append(e)
			if how == "elite":
				cand = o.cap_targets(cand, s.pos, 6)
			else:
				cand.sort_custom(func(x, y): return _hp_frac(x) < _hp_frac(y) if _hp_frac(x) != _hp_frac(y) else int(x.id) < int(y.id))
		_:
			for e in o.nearest_enemies(6, leash * 2.0, s.pos):
				if e.pos.distance_to(anc) <= leash:
					cand.append(e)
	cand = cand.filter(func(e): return _sm_ok(e))
	if cand.is_empty():
		return null
	for e in cand:
		if not taken.has(int(e.id)):
			return e
	return cand[0]


## 每帧（data_operator.update 在能天使段之后调）：护盾计时、封印标记清理、召唤物到期 / 移动 / 出手 / 诱饵
static func sm_tick(o, dt: float) -> void:
	if o.sm.is_empty():
		return
	var g = o.g
	var st: Dictionary = o.sm
	if float(st.shield) > 0.0:
		st.shield_t = float(st.shield_t) - dt
		if st.shield_t <= 0.0:
			st.shield = 0.0
		else:
			st.shield = maxf(0.0, float(st.shield) * (1.0 - float(st.shield_decay) * dt))
	if not st.seal.is_empty():
		for id in st.seal.keys():
			var se: Dictionary = st.seal[id]
			if se.dead or float(se.get("seal_t", 0.0)) <= g.t:
				st.seal.erase(id)
	if st.list.is_empty():
		return
	var cnt := {}
	for s in st.list:
		cnt[s.kind] = int(cnt.get(s.kind, 0)) + 1
	for k in cnt:
		var mv: Dictionary = sm_kind(o, k).get("move", {})
		st.ang[k] = fposmod(float(st.ang.get(k, 0.0)) + float(mv.get("orbit_speed", 1.6)) * dt, TAU)
	var idx := {}
	var ends: Array = []
	for s in st.list.duplicate():   # 出手可能击杀 → on_kill → 再召唤，遍历副本
		if s.gone:
			continue
		var kd := sm_kind(o, s.kind)
		s.t += dt
		s.flash = maxf(0.0, float(s.flash) - dt)
		if float(s.life) > 0.0 and s.t >= float(s.life):
			ends.append([s, "life"])
			continue
		if int(s.skill) >= 0 and not o.skill_on(int(s.skill)):
			ends.append([s, "skill"])
			continue
		if not s.inv and float(s.hp) <= 0.0:
			ends.append([s, "dead"])
			continue
		var i: int = int(idx.get(s.kind, 0))
		idx[s.kind] = i + 1
		if str(kd.get("move", {}).get("mode", "")) == "escort":
			mf_step(o, s, kd, dt)   # 召唤物扩展段（§15.9）：随行召唤物
		else:
			_sm_step(o, s, kd, i, int(cnt.get(s.kind, 1)), dt)
	for en in ends:
		_sm_end(o, en[0], en[1])


static func _sm_step(o, s: Dictionary, kd: Dictionary, i: int, n: int, dt: float) -> void:
	var mv: Dictionary = kd.get("move", {})
	var mode: String = str(mv.get("mode", "follow"))
	var anc := _sm_anchor(o, mv)
	var a: Dictionary = kd.get("attack", {})
	var reach := sm_reach(o, a)
	if s.pos.distance_to(anc) > SM_FAR:
		s.pos = anc
		s.tgt = null
	var tg = s.tgt
	if tg != null and not _sm_ok(tg):
		tg = null
	var orr: float = float(mv.get("orbit_r", 60.0 if mode == "orbit" else 44.0))
	var sa: float = PI * 0.5 + TAU * i / maxf(1.0, n)
	var slot: Vector2 = anc + Vector2(cos(sa) * orr, sin(sa) * orr * 0.55)
	var want: Vector2 = s.pos
	match mode:
		"orbit":
			var an: float = float(o.sm.ang.get(s.kind, 0.0)) + TAU * i / maxf(1.0, n)
			want = anc + Vector2(cos(an) * orr, sin(an) * orr * 0.55)
			tg = null
		"follow":
			want = slot
			tg = null
		"stay":
			tg = null
		_:   # chase
			var leash: float = float(mv.get("leash", 240.0))
			if tg != null and tg.pos.distance_to(anc) > leash + 40.0:
				tg = null
			s.rt = float(s.rt) - dt
			if tg == null and s.rt <= 0.0:
				tg = _sm_pick(o, s, mv, anc, leash)
				if tg == null:
					s.rt = 0.25   # 没目标时每 0.25 秒再找（大群里不每帧排序）
			if tg != null:
				var ga: float = float(s.id) * SM_GOLD
				want = tg.pos + Vector2(cos(ga), sin(ga) * 0.55) * (float(tg.r) + maxf(8.0, reach * 0.6))
			else:
				want = slot
	s.tgt = tg
	var prev: Vector2 = s.pos
	s.pos = s.pos.move_toward(want, float(mv.get("speed", 240.0)) * dt)
	var vx: float = s.pos.x - prev.x
	if absf(vx) > 0.5:
		s.face = signf(vx)
	# 诱饵：近战杂兵改追它（同骑士 / 海嗣分身的 e.aggro，每帧重标）；有生命的诱饵挨贴身接触伤害（每个敌人 1 秒一次）
	if str(kd.get("enemy_target", "ignore")) == "decoy":
		_sm_decoy(o, s, kd)
	# 出手
	s.cd = float(s.cd) - dt
	s.anim = maxf(0.0, float(s.anim) - dt)
	if a.is_empty() or s.cd > 0.0:
		return
	var t2 = tg
	if t2 == null:
		var ts: Array = o.nearest_enemies(1, reach + 30.0, s.pos)
		t2 = ts[0] if not ts.is_empty() else null
	if not _sm_ok(t2) or s.pos.distance_to(t2.pos) > reach + float(t2.r):
		return
	s.cd = float(a.get("every", 1.0)) / maxf(0.05, o.stat(&"op_aspd"))
	sm_strike(o, s, a, t2)


static func _sm_decoy(o, s: Dictionary, kd: Dictionary) -> void:
	var g = o.g
	var dr: float = float(kd.get("decoy_r", 160.0))
	var br: float = float(kd.get("r", 10.0))
	for j in o.query_ids(s.pos, dr):
		var e: Dictionary = g.enemies[j]
		if e.dead or e.chest or e.boss or e.ai != "melee" or e.pos.distance_to(s.pos) > dr:
			continue
		e.aggro = s.pos
	if s.inv:
		return
	var hm: float = float(kd.get("hurt_mult", 0.4))
	for j in o.query_ids(s.pos, br + 40.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or e.chest or e.dmg <= 0.0 or e.ai != "melee" or e.get("coma", false) or e.get("under", false) or e.get("dormant", false):
			continue
		if e.pos.distance_to(s.pos) > float(e.r) + br or float(s.hurt.get(e.id, -1.0)) > g.t:
			continue
		s.hurt[e.id] = g.t + 1.0
		s.hp = float(s.hp) - float(e.dmg) * hm
		s.flash = 0.15
	if s.hurt.size() > 48:
		for k in s.hurt.keys():
			if float(s.hurt[k]) <= g.t:
				s.hurt.erase(k)


## 召唤物出手：已有形状（circle / cone / line）以召唤物为原点。伤害 = 本干员 base[atk_key] × mult × 局部 dmg × _dmg_bonus（含 op_atk）[× 技能强度]，
## 精英 / Boss × vs_elite；来源 src 记在本干员名下，tags 自动加 summon；on_hit 状态（含 st.seal）照常；画面走通用 fx（中心 = 判定中心）
static func sm_dmg(o, a: Dictionary) -> float:
	var dmg: float = o.base(str(a.get("atk_key", "atk")), 0.0) * float(a.get("mult", 1.0)) * float(o.loc.dmg) * o._dmg_bonus()
	return dmg * o.skill_power() if a.get("power", false) else dmg


static func sm_strike(o, s: Dictionary, a: Dictionary, tg: Dictionary) -> Array:
	var g = o.g
	var dmg: float = sm_dmg(o, a)
	var src: String = str(a.get("src", ""))
	var tags: Array = a.get("tags", []).duplicate()
	if not "summon" in tags:
		tags.append("summon")
	var kb: float = float(a.get("kb", 0.0))
	var stun: float = float(a.get("stun", 0.0))
	var max_n: int = int(a.get("max_n", 0))
	var kr: float = o.stat(&"op_range")
	var ang: float = (tg.pos - s.pos).angle()
	if absf(tg.pos.x - s.pos.x) > 2.0:
		s.face = signf(tg.pos.x - s.pos.x)
	s.anim = 0.22
	var hits: Array = []
	var c: Vector2 = s.pos
	var r: float = float(a.get("r", 30.0)) * kr
	match str(a.get("shape", "circle")):
		"cone":
			hits = o.melee_hit(src, s.pos, ang, deg_to_rad(float(a.get("half_deg", 45.0))), r, dmg, kb, stun, tags, max_n)
		"line":
			var L: float = float(a.get("len", 60.0)) * kr
			var W: float = float(a.get("width", 20.0))
			var d := Vector2.from_angle(ang)
			for j in o.query_ids(s.pos + d * L * 0.5, L * 0.5 + W + 40.0):
				var e: Dictionary = g.enemies[j]
				if not e.dead and line_contains(s.pos, d, L, W, e.pos, float(e.r)):
					hits.append(e)
			if max_n > 0 and hits.size() > max_n:
				hits = o.cap_targets(hits, s.pos, max_n)
			var ve: float = o.vs_elite()
			for e in hits:
				o.log_hit(src, tags)
				o.deal_damage(e, dmg * (ve if e.elite or e.boss else 1.0))
				if not e.dead and not e.boss and kb > 0.0:
					e.kb += d * kb * (0.3 if e.elite else 1.0)
				if not e.dead and not e.boss and stun > 0.0:
					e.stun = maxf(e.stun, stun * (0.5 if e.elite else 1.0))
			c = s.pos + d * L * 0.5
			r = L * 0.5
		_:
			if str(a.get("center", "self")) == "target":
				c = tg.pos
			hits = o.area_hit(src, c, r, dmg, kb, stun, tags, max_n)
	for stt in a.get("on_hit", []):
		for e in hits:
			apply_status(o, e, stt)
	if a.has("fx") and fx_any_tex(o, a.fx):
		fx_play(o, a.fx, c, r, hits, ang)
	else:
		var cc: Color = _sm_col(o, sm_kind(o, str(s.kind)))
		o.fx({"kind": "ring", "pos": c, "r": maxf(10.0, r * 0.8), "r0": 4.0, "life": 0.2, "col": cc, "floor": true, "w": 2.0, "alpha": 0.7})
	return hits


## 2.5D 排序条目（data_operator.extra_bodies）
static func sm_bodies(o) -> Array:
	var out: Array = []
	if o.sm.is_empty():
		return out
	for s in o.sm.list:
		out.append({"y": s.pos.y + 4.0, "s": s})
	return out


## 影子（squad.draw_shadows 的合批画布里）
static func sm_shadows(o) -> void:
	if o.sm.is_empty():
		return
	for s in o.sm.list:
		if mf_shadow(o, s, sm_kind(o, str(s.kind))):   # 召唤物扩展段：影子贴图
			continue
		var r: float = float(sm_kind(o, str(s.kind)).get("r", 10.0))
		o.cv.draw_set_transform(s.pos + Vector2(0, 2), 0.0, Vector2(1.0, 0.4))
		o.cv.draw_circle(Vector2.ZERO, r * 1.1, Color(0, 0, 0, 0.28))
		o.cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 画一个召唤物（data_operator.draw_extra）：body.strip 帧条（按脚底锚点、随朝向翻转、可悬浮起伏）；缺图时画程序体（圆身 + 眼睛 + 出手前扑）
static func sm_draw(o, s: Dictionary) -> void:
	var g = o.g
	var kd := sm_kind(o, str(s.kind))
	if kd.has("anim") and mf_draw(o, s, kd):   # 召唤物扩展段：按状态的帧条（缺图时往下画程序体）
		return
	var body: Dictionary = kd.get("body", {})
	var hov: float = float(body.get("hover", 0.0))
	var p: Vector2 = s.pos + Vector2(0, -hov + (sin(g.t * 3.5 + float(s.id)) * 2.0 if hov > 0.0 else 0.0))
	var al: float = clampf(float(s.t) / 0.15, 0.0, 1.0)
	if float(s.life) > 0.0:
		al *= clampf((float(s.life) - float(s.t)) / 0.3, 0.0, 1.0)
	var lunge := Vector2(float(s.face) * 4.0 * sin(clampf(float(s.anim) / 0.22, 0.0, 1.0) * PI), 0)
	var tint := Color.WHITE
	var tv = body.get("tint", [])
	if tv is Array and tv.size() >= 3:
		tint = Color(float(tv[0]), float(tv[1]), float(tv[2]), float(tv[3]) if tv.size() > 3 else 1.0)
	if float(s.flash) > 0.0:
		tint = tint.lerp(Color(1.6, 1.6, 1.6, tint.a), 0.6)
	tint.a *= al
	var name: String = str(body.get("strip", ""))
	var tx: Texture2D = g.tex.get(name) if name != "" else null
	if tx != null:
		var spec: Array = g.V6_FRAMES.get(name, [])
		var frames: int = maxi(1, int(body.get("frames", spec[0] if spec.size() > 0 else 1)))
		var fps: float = maxf(1.0, float(body.get("fps", spec[1] if spec.size() > 1 else 8)))
		var fr: int = int(float(s.t) * fps) % frames
		var h: float = ArtS.hires_of(tx)
		var fw: int = tx.get_width() / frames
		var fh: int = tx.get_height()
		var an := Vector2(fw * 0.5, fh)
		var av = body.get("anchor", [])
		if av is Array and av.size() == 2:
			an = Vector2(float(av[0]), float(av[1])) * h
		var sc: float = g.PX * float(body.get("scale", 1.0))
		var fl: float = -1.0 if body.get("flip", true) and float(s.face) < 0.0 else 1.0
		o._cv_flush()
		o.cv.draw_set_transform(p + lunge, 0.0, Vector2(fl * sc / h, sc / h))
		o.cv.draw_texture_rect_region(tx, Rect2(-an, Vector2(fw, fh)), Rect2(fw * fr, 0, fw, fh), tint)
		o.cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		var r: float = float(kd.get("r", 10.0))
		var cc: Color = _sm_col(o, kd)
		var q: Vector2 = p + lunge + Vector2(0, -r)
		o.cv.draw_circle(q, r + 1.5, Color(0.03, 0.03, 0.06, 0.8 * al))
		o.cv.draw_circle(q, r, Color(cc.r * tint.r, cc.g * tint.g, cc.b * tint.b, al))
		o.cv.draw_circle(q + Vector2(-r * 0.25, -r * 0.3), r * 0.45, Color(minf(cc.r * 1.5, 1.5), minf(cc.g * 1.5, 1.5), minf(cc.b * 1.5, 1.5), 0.5 * al))
		var ex: float = float(s.face) * r * 0.45
		o.cv.draw_circle(q + Vector2(ex, -r * 0.15), maxf(1.5, r * 0.18), Color(1.0, 0.95, 0.85, al))
	if not s.inv and float(s.hp) < float(s.max_hp):
		var w: float = 18.0
		var bp: Vector2 = s.pos + Vector2(-w * 0.5, -hov - float(kd.get("r", 10.0)) * 2.0 - 8.0)
		o.cv.draw_rect(Rect2(bp, Vector2(w, 2.5)), Color(0.05, 0.05, 0.08, 0.8 * al))
		o.cv.draw_rect(Rect2(bp, Vector2(w * clampf(float(s.hp) / float(s.max_hp), 0.0, 1.0), 2.5)), Color(0.5, 1.0, 0.6, al))


# ---------------------------------------------------------------- 封印 st.seal

## 一名敌人吃封印（apply_status 转来；Boss 规则在这里，不走「Boss 缺省不受」）。
## e.seal_t = 封印结束的 g.t；e.seal_imm = Boss 免疫结束的 g.t；e.seal_by = 施加者 id（画标记用）
static func seal_apply(o, e: Dictionary, s: Dictionary) -> void:
	var g = o.g
	if e.dead or e.chest or e.get("friendly", false):
		return
	var dur: float = float(s.get("dur", 0.0))
	if e.boss:
		if not s.get("boss", true):
			return
		if float(e.get("seal_imm", -1.0)) > g.t:
			if float(e.get("seal_txt", -1.0)) <= g.t:
				e["seal_txt"] = g.t + 1.5
				o.float_text(e.pos + Vector2(0, -float(e.r) * 2.0 - 30.0), "封印免疫", Color(0.75, 0.7, 0.85), 13)
			return
		dur = minf(dur * float(s.get("boss_mult", 0.3)), float(s.get("boss_max", 1.5)))
		if dur <= 0.0:
			return
		e["seal_imm"] = g.t + dur + float(s.get("boss_immune", 10.0))
	elif e.elite:
		dur *= float(s.get("elite_mult", 0.5))
	if dur <= 0.0:
		return
	var was: bool = float(e.get("seal_t", 0.0)) > g.t
	e["seal_t"] = maxf(float(e.get("seal_t", 0.0)), g.t + dur)
	e["seal_by"] = o.id
	sm_st(o).seal[int(e.id)] = e
	if not was and (e.elite or e.boss):
		o.float_text(e.pos + Vector2(0, -float(e.r) * 2.0 - 30.0), "封印", SEAL_COL, 15)


static func sealed(e: Dictionary, t: float) -> bool:
	return float(e.get("seal_t", 0.0)) > t


## 技能上层（data_operator._draw_skill_over）：本干员施加的封印标记（头顶旋转的锁环 + 脚下紫环）、主控护盾（泡壳 + 头顶护盾条）
static func sm_draw_over(o) -> void:
	if o.sm.is_empty():
		return
	var g = o.g
	var cv = o.cv
	for id in o.sm.seal:
		var e: Dictionary = o.sm.seal[id]
		if e.dead or not sealed(e, g.t) or str(e.get("seal_by", "")) != o.id:
			continue
		var left: float = float(e.seal_t) - g.t
		var al: float = clampf(left / 0.3, 0.0, 1.0) * 0.9
		var er: float = float(e.r)
		cv.draw_set_transform(e.pos + Vector2(0, er * 0.6), 0.0, Vector2(1.0, 0.45))
		cv.draw_arc(Vector2.ZERO, er + 6.0, 0.0, TAU, 24, Color(SEAL_COL.r, SEAL_COL.g, SEAL_COL.b, 0.55 * al), 2.0)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var hp: Vector2 = e.pos + Vector2(0, -er * 2.0 - 14.0)
		var rot: float = g.t * 1.6 + float(id)
		var pts := PackedVector2Array()
		for k in 5:
			pts.append(hp + Vector2.from_angle(rot + TAU * k / 4.0) * 7.0)
		cv.draw_polyline(pts, Color(0.05, 0.02, 0.1, 0.7 * al), 4.0)
		cv.draw_polyline(pts, Color(SEAL_COL.r * 1.3, SEAL_COL.g * 1.3, SEAL_COL.b * 1.3, al), 2.0)
		cv.draw_line(hp + Vector2(-3, -3), hp + Vector2(3, 3), Color(1.2, 1.0, 1.4, al), 1.5)
		cv.draw_line(hp + Vector2(-3, 3), hp + Vector2(3, -3), Color(1.2, 1.0, 1.4, al), 1.5)
	var sh: float = float(o.sm.shield)
	if sh > 0.0 and g.ppos != Vector2.INF:
		var k2: float = clampf(sh / maxf(1.0, float(o.sm.shield_max)), 0.0, 1.0)
		var pulse: float = 0.5 + 0.15 * sin(g.t * 5.0)
		cv.draw_set_transform(g.ppos + Vector2(0, -22), 0.0, Vector2(1.0, 1.25))
		cv.draw_arc(Vector2.ZERO, 26.0, 0.0, TAU, 40, Color(SHIELD_COL.r, SHIELD_COL.g, SHIELD_COL.b, (0.25 + 0.35 * k2) * pulse), 2.0)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var bp: Vector2 = g.ppos + Vector2(-20, -100)
		cv.draw_rect(Rect2(bp, Vector2(40, 3)), Color(0.03, 0.05, 0.08, 0.75))
		cv.draw_rect(Rect2(bp, Vector2(40.0 * k2, 3)), Color(SHIELD_COL.r, SHIELD_COL.g, SHIELD_COL.b, 0.95))


# ---------------------------------------------------------------- 护盾 verb.shield / 治疗光环 aura.heal

static func shield_add(o, b: Dictionary) -> void:
	var g = o.g
	var st := sm_st(o)
	var mh: float = g.max_hp
	var add: float = mh * float(b.get("pct", 0.0)) * (o.skill_power() if b.get("power", false) else 1.0)
	var cap: float = mh * float(b.get("cap", b.get("pct", 0.0)))
	st.shield = maxf(float(st.shield), minf(float(st.shield) + add, cap))   # 已有的护盾比上限还多时不削
	st.shield_max = maxf(cap, float(st.shield))
	st.shield_t = maxf(float(st.shield_t), float(b.get("dur", 10.0)))
	st.shield_decay = float(b.get("decay", 0.0))
	if b.has("fx"):
		fx_play(o, b.fx, g.ppos, 30.0)


## 受击询问（data_operator.dmg_taken_mult 末尾）：m = 其余减伤的乘积；护盾吸收 combat.cur_dmg × m 里能吸的部分，返回新的倍率
## （全吸收 = 0，combat 按「这一下作废」处理：不扣血、不掉灯火，给 0.3 秒无敌）
static func shield_mult(o, m: float) -> float:
	if o.sm.is_empty() or float(o.sm.shield) <= 0.0:
		return m
	var raw: float = float(o.g.combat.cur_dmg)
	var d: float = raw * m
	if raw <= 0.0 or d <= 0.0:
		return m
	var ab: float = minf(float(o.sm.shield), d)
	o.sm.shield = float(o.sm.shield) - ab
	o.float_text(o.g.ppos + Vector2(18, -92), "护盾 -%d" % int(ab), SHIELD_COL, 13)
	return (d - ab) / raw


## 常驻部分（data_operator._sustain 末尾）：aura.heal 每秒回复（各积木独立计时，没生效的计时清零）
static func sm_sustain(o, act: Array, dt: float) -> void:
	var seen := {}
	for b in act:
		if str(b.get("_tag", "")) != "aura.heal":
			continue
		var st := sm_st(o)
		var u: int = int(b.get("_uid", 0))
		seen[u] = true
		if str(b.get("scope", "in_zone")) == "in_zone" and not o.in_zone(o.g.ppos):
			st.heal_acc.erase(u)
			continue
		st.heal_acc[u] = float(st.heal_acc.get(u, 0.0)) + dt
		if st.heal_acc[u] >= 1.0:
			st.heal_acc[u] -= 1.0
			var g = o.g
			if g.hp < g.max_hp:
				o.heal_leader(g.max_hp * float(b.get("pct", 0.0)) * float(o.loc.heal) * (o.skill_power() if b.get("power", false) else 1.0), str(b.get("src", o.display_name())))
	if not o.sm.is_empty() and not o.sm.heal_acc.is_empty():
		for u in o.sm.heal_acc.keys():
			if not seen.has(u):
				o.sm.heal_acc.erase(u)


## Tab / 头像下的状态条：各种召唤物在场数、护盾
static func sm_status_items(o) -> Array:
	var out: Array = []
	if o.sm.is_empty():
		return out
	var cnt := {}
	for s in o.sm.list:
		cnt[s.kind] = int(cnt.get(s.kind, 0)) + 1
	for k in cnt:
		var kd := sm_kind(o, k)
		if not kd.get("status", true):   # 召唤物扩展段：status: false = 不显示在场数（常驻随行的 Mon3tr）
			continue
		out.append(["%s ×%d" % [str(kd.get("name", k)), int(cnt[k])], _sm_col(o, kd)])
	if float(o.sm.shield) > 0.0:
		out.append(["护盾 %d" % int(o.sm.shield), SHIELD_COL])
	return out


# ---------------------------------------------------------------- 召唤 / 封印段的校验

## blocks.summons 段：每种召唤物的定义（docs/61 §15.1）
static func _sm_kinds(blocks: Dictionary, ctx: Dictionary) -> void:
	var errs: Array = ctx.errs
	var sd = blocks.get("summons", {})
	if not (sd is Dictionary):
		errs.append("blocks.summons 必须是对象（种类名 → 定义）")
		return
	for k in sd:
		var p := "blocks.summons." + str(k)
		var kd = sd[k]
		if not str(k).is_valid_identifier():
			errs.append(p + "：种类名只能是字母 / 数字 / 下划线（不以数字开头）")
		if not (kd is Dictionary):
			errs.append(p + " 必须是对象")
			continue
		for q in kd:
			if not q in SM_KIND_KEYS + MF_KIND_KEYS:
				errs.append("%s.%s：召唤物定义不认识的字段（只能是 %s）" % [p, q, " / ".join(SM_KIND_KEYS + MF_KIND_KEYS)])
		_sm_exprs(kd, p, ctx)
		var inv = kd.get("invuln", false)
		if not (inv is bool):
			errs.append(p + ".invuln 只能是 true / false")
		elif not inv:
			_num(kd, "hp", p, ctx, true, 1.0, 100000.0)
		elif kd.has("hp"):
			errs.append(p + "：invuln（无敌）的召唤物不写 hp")
		var lv = kd.get("life", null)
		if lv == null:
			errs.append(p + " 缺 life（秒数 / \"skill\" = 召唤它的技能生效期间 / \"permanent\"）")
		elif lv is String and not "$" in lv:
			if not lv in ["skill", "permanent"]:
				errs.append(p + ".life 只能是秒数、\"skill\" 或 \"permanent\"")
		else:
			_num(kd, "life", p, ctx, true, 0.5, 120.0)
		_num(kd, "cap", p, ctx, true, 1.0, float(SM_KIND_CAP))
		_num(kd, "r", p, ctx, false, 4.0, 40.0)
		_num(kd, "decoy_r", p, ctx, false, 20.0, 600.0)
		_num(kd, "hurt_mult", p, ctx, false, 0.0, 5.0)
		if not str(kd.get("enemy_target", "ignore")) in ["ignore", "decoy"]:
			errs.append(p + ".enemy_target 只能是 ignore（缺省：敌人不理召唤物）/ decoy（诱饵：近战杂兵改追它、贴身时它挨打）")
		if kd.has("col"):
			var c = kd.col
			if not (c is Array) or c.size() != 3 or c.any(func(x): return not (x is int or x is float)):
				errs.append(p + ".col 必须是 3 个数字 [r, g, b]")
		var mv = kd.get("move", null)
		if not (mv is Dictionary):
			errs.append(p + ".move 必须是对象（mode / speed / anchor / leash / orbit_r / orbit_speed / target）")
		else:
			for q in mv:
				if not q in SM_MOVE_KEYS + MF_MOVE_KEYS:
					errs.append("%s.move.%s：不认识的字段（只能是 %s）" % [p, q, " / ".join(SM_MOVE_KEYS + MF_MOVE_KEYS)])
			_sm_exprs(mv, p + ".move", ctx)
			if not str(mv.get("mode", "")) in SM_MOVES + ["escort"]:
				errs.append("%s.move.mode 只能是 %s" % [p, " / ".join(SM_MOVES + ["escort"])])
			if not str(mv.get("anchor", "leader")) in ["leader", "self"]:
				errs.append(p + ".move.anchor 只能是 leader / self")
			if not str(mv.get("target", "nearest")) in SM_TARGETS:
				errs.append("%s.move.target 只能是 %s" % [p, " / ".join(SM_TARGETS)])
			_num(mv, "speed", p + ".move", ctx, false, 0.0, 1200.0)
			_num(mv, "leash", p + ".move", ctx, false, 40.0, 800.0)
			_num(mv, "orbit_r", p + ".move", ctx, false, 0.0, 400.0)
			_num(mv, "orbit_speed", p + ".move", ctx, false, -6.0, 6.0)
		var a = kd.get("attack", null)
		if a != null:
			if not (a is Dictionary) or not str(a.get("shape", "")) in ["circle", "cone", "line"]:
				errs.append(p + ".attack 必须是一个伤害形状（shape.circle / shape.cone / shape.line）")
			else:
				_block(a, p + ".attack", "attack", ctx)
				_num(a, "every", p + ".attack", ctx, true, 0.1, 10.0)
				_num(a, "range", p + ".attack", ctx, false, 4.0, 600.0)
				if str(a.shape) == "circle" and not str(a.get("center", "self")) in ["self", "target"]:
					errs.append(p + ".attack.center：召唤物的圆形判定只能以自身（self）或目标（target）为心")
		_mf_kind(kd, p, ctx)   # 召唤物扩展段（§15.9）：escort / anim / patch / fx …
		for lk in ["on_spawn", "on_expire"]:
			if kd.has(lk):
				_list(kd[lk], "%s.%s" % [p, lk], "instant", ctx)
				if kd[lk] is Array and kd[lk].any(func(x): return x is Dictionary and str(x.get("verb", "")) == "summon"):
					errs.append("%s.%s：不能再召唤（免得召唤物连环生成）" % [p, lk])
		if kd.has("body"):
			var bd = kd.body
			if not (bd is Dictionary):
				errs.append(p + ".body 必须是对象")
			else:
				for q in bd:
					if not q in SM_BODY_KEYS:
						errs.append("%s.body.%s：不认识的字段（只能是 %s）" % [p, q, " / ".join(SM_BODY_KEYS)])
				var sn = bd.get("strip", "")
				if not (sn is String) or not (sn.begins_with("fx_") or sn.begins_with("proj_") or sn.begins_with("op_") or sn.begins_with("ally_")):
					errs.append(p + ".body.strip 必须是帧条名（fx_* / proj_* / op_* / ally_*）；缺图时画程序体")
				_num(bd, "frames", p + ".body", ctx, false, 1.0, 64.0)
				_num(bd, "fps", p + ".body", ctx, false, 1.0, 60.0)
				_num(bd, "scale", p + ".body", ctx, false, 0.1, 8.0)
				_num(bd, "hover", p + ".body", ctx, false, 0.0, 60.0)
				if bd.has("flip") and not (bd.flip is bool):
					errs.append(p + ".body.flip 只能是 true / false")
				for kk in [["tint", 3, 4], ["anchor", 2, 2]]:
					if bd.has(kk[0]):
						var v = bd[kk[0]]
						if not (v is Array) or v.size() < kk[1] or v.size() > kk[2] or v.any(func(x): return not (x is int or x is float)):
							errs.append("%s.body.%s 必须是 %d%s 个数字的数组" % [p, kk[0], kk[1], "" if kk[1] == kk[2] else "–%d" % kk[2]])


## 对象里一层的 $ 表达式（召唤物定义 / move 不是积木，_block 的 $ 扫描管不到）
static func _sm_exprs(d: Dictionary, p: String, ctx: Dictionary) -> void:
	for k in d:
		if d[k] is String and "$" in d[k]:
			var ev := eval_expr(d[k], ctx.base)
			if not ev[0]:
				ctx.errs.append("%s.%s：%s" % [p, k, ev[2]])


## 本段的积木：校验完返回 true（_block 不再往下走）；不是本段的返回 false
static func _sm_block(b: Dictionary, p: String, kind: String, ctx: Dictionary, tag: String) -> bool:
	if not tag in SM_TAGS:
		return false
	var errs: Array = ctx.errs
	var where_ok := {
		"verb.summon": ["skill", "instant"],
		"verb.shield": ["skill", "instant"],
		"st.seal": ["on_hit", "field"],
		"aura.heal": ["skill", "sustain"],
	}
	if not kind in where_ok[tag]:
		errs.append("%s：「%s」不能放在这里（%s；只能在 %s）" % [p, tag, kind, " / ".join(where_ok[tag])])
		return true
	match tag:
		"verb.summon":
			var k := str(b.get("kind", ""))
			var sd = ctx.get("summons", {})
			var kd = sd.get(k, null) if sd is Dictionary else null
			if not (kd is Dictionary):
				errs.append("%s.kind「%s」没在 blocks.summons 里定义" % [p, k])
			_num(b, "n", p, ctx, false, 1.0, float(SM_KIND_CAP))
			_num(b, "spread", p, ctx, false, 0.0, 200.0)
			if not str(b.get("at", "self")) in SM_AT:
				errs.append("%s.at 只能是 %s" % [p, " / ".join(SM_AT)])
			var lv = b.get("life", kd.get("life", 0.0) if kd is Dictionary else 0.0)
			if b.has("life"):
				if lv is String and not "$" in lv:
					if not lv in ["skill", "permanent"]:
						errs.append(p + ".life 只能是秒数、\"skill\" 或 \"permanent\"")
				else:
					_num(b, "life", p, ctx, true, 0.5, 120.0)
			if lv is String and lv == "skill" and kind != "skill":
				errs.append(p + "：life = skill（随技能结束消失）的召唤只能放在技能 do 里")
		"verb.shield":
			_num(b, "pct", p, ctx, true, 0.01, 1.0)
			_num(b, "cap", p, ctx, false, 0.01, 2.0)
			_num(b, "dur", p, ctx, false, 0.5, 60.0)
			_num(b, "decay", p, ctx, false, 0.0, 1.0)
		"st.seal":
			_num(b, "dur", p, ctx, true, 0.1, 10.0)
			_num(b, "elite_mult", p, ctx, false, 0.0, 1.0)
			_num(b, "boss_mult", p, ctx, false, 0.0, 1.0)
			_num(b, "boss_max", p, ctx, false, 0.0, 3.0)
			_num(b, "boss_immune", p, ctx, false, 3.0, 60.0)
			if b.has("boss") and not (b.boss is bool):
				errs.append(p + ".boss 只能是 true / false")
		"aura.heal":
			_num(b, "pct", p, ctx, true, 0.0, 0.1)
			if not str(b.get("scope", "in_zone")) in ["in_zone", "always"]:
				errs.append(p + ".scope 只能是 in_zone（主控在本干员区域内）/ always")
	return true


# ================================================================ 召唤物扩展段（docs/61 §15.9，10-12：凯尔希 Mon3tr 迁到通用召唤积木；只往后加）
# 给「常驻随行、按状态播帧条、技能期间改攻击」一类召唤物用的通用扩展（第一个用户：凯尔希的 Mon3tr）：
#  trig.on_deploy        招募 / 节点生效时执行一次（召唤物从上场起就在）
#  move.mode = escort    随行：闲时站本干员身前 rest，追锚点 leash 内离锚点最近的敌人、从当前一侧贴到 gap 处；
#                        出手动作期间不走；绕开本干员 / 主控（avoid，滞回）、柱子推出（solid）、离锚点 recall 外瞬回
#  anim                  按状态的帧条 {idle, run, attack}（干员自己 sprites 里的键）；攻击在 attack 帧条的出手帧（fire）才判定
#  patch                 条件成立（如 skill_active:2）时的攻击覆盖：mult（× 技能强度 power）、src（如真伤来源）、speed、
#                        anim / seq（换帧条、起手 + 循环 + 收尾）、tint、sfx；第一条成立的生效
#  verb.summon_mod       常驻：某种召唤物的 dmg / aspd / reach / arc / speed 倍率（按 §5.5 固定顺序依次乘），
#                        then（延迟 delay 秒再追一击 mult）、mirror（同时向身后镜像一击 mult，没打到不画）
#  manual = command      手动普攻 B 类：按攻击键才命令召唤物扑向瞄准方向的目标，松手 manual/m_linger 秒内打完
#  fx（种类 / 攻击上）     §5.6 条目之外的程序条目：pfx / gfx / sprite / sparks / arc / text / banner / pause / sfx；
#                        种类上另有 ghost（残影）/ mist（身后红雾）/ side（身体两侧的常驻爪刃）。散布一律 g.vrng
#  verb.guard            瞬时：限时减伤（同名共用一个计时，重复施加重新计时），dmg_taken_mult 里按积木顺序相乘；look 画护壳
#  verb.cleanse          瞬时：清除主控负面状态（what: nerve = 神经损伤）
#  verb.heal 追加        scale: op（× op_atk × 同伴倍率 × heal_out）、knight（同时治骑士同伴）、on_over（溢出时执行）、text / sfx
#  shape.support         普攻不造成伤害：every 秒一拍、when 条件成立时朝主控起手、出手帧执行 do（凯尔希的治疗）
#  条件追加              node:<custom 节点 id>（已选这个节点）、hurt_any（主控或骑士同伴没满血）、a && b
#  trig.on_skill_start / on_skill_end 追加 at（summon:<种类> / self / leader）：do 里 center: target 落在触发那一刻的这个点，
#                        带 at 的 on_skill_end 在本帧开头结算（召唤物移动之前），二者都可写 delay（进本干员延迟队列）

const MF_TAGS := ["verb.summon_mod", "verb.guard", "verb.cleanse", "trig.on_deploy"]
const MF_KIND_KEYS := ["anim", "patch", "float", "shadow", "fx", "status", "manual"]
const MF_MOVE_KEYS := ["rest", "gap", "avoid", "solid", "recall"]
const MF_PATCH_KEYS := ["cond", "mult", "power", "src", "speed", "anim", "seq", "tint", "sfx", "_doc"]
const MF_MOD_FACTORS := ["dmg", "aspd", "reach", "arc", "speed"]
const MF_FX_KINDS := ["pfx", "gfx", "sprite", "sparks", "arc", "text", "banner", "pause", "sfx", "ghost", "mist", "side"]
const MF_FX_COMMON := ["cond", "if_tex", "at", "off", "n", "every", "jit", "jit_r", "ring", "r_scale", "vel_r", "ang_vel", "along", "side_x", "r_mult",
	"first_only", "face_x", "to", "to_off", "to_jit", "_doc"]
const MF_SPRITE_KEYS := ["fit", "scale_r", "scale", "rot", "second_scale", "second_rot", "swing_rot", "tint", "bottom", "flip_side"]
const MF_PFX_KINDS := ["ring", "glow", "spark", "shard", "line", "mote", "crescent", "impact", "core", "qshard", "beamray"]
const MF_GFX_KINDS := ["beam", "rays", "cross"]
const MF_AT := ["center", "self", "leader", "hits", "summon"]
const MF_CLEANSE := ["nerve"]
const MF_GUARD_KEYS := ["verb", "value", "dur", "name", "col", "look", "fx", "cond", "_doc"]
const MF_LOOK_KEYS := ["strip", "frames", "fps", "anchor", "alpha", "off", "fade_in", "blink", "r"]
const MF_FACE_MIN := 0.35   # 同 character.gd FACE_MIN（转向防抖）
const MfBal = preload("res://scripts/core/balance.gd")


## 干员的扩展状态（data_operator.mf）：guards（名字 → {t, v, u, dur, col, look}）、mods（种类 → 倍率表）、deployed（已执行的 on_deploy）
static func mf_st(o) -> Dictionary:
	if o.mf.is_empty():
		o.mf.merge({"guards": {}, "mods": {}, "deployed": {}})
	return o.mf


static func _mf_col(v, def := Color.WHITE) -> Color:
	if v is Array and v.size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]), float(v[3]) if v.size() > 3 else 1.0)
	return def


# ---------------------------------------------------------------- 条件追加（parse_cond / cond_true 转来）

static func mf_parse_cond(s: String, base: Dictionary) -> Dictionary:
	if "&&" in s:
		var out := {"neg": false, "k": "all", "a": "", "op": "", "v": 0.0, "list": []}
		for part in s.split("&&"):
			var c := parse_cond(part.strip_edges(), base)
			if c.has("err"):
				return c
			out.list.append(c)
		return out
	var neg := s.begins_with("!")
	var t := s.substr(1).strip_edges() if neg else s
	if t.begins_with("node:") and t.length() > 5:
		return {"neg": neg, "k": "node", "a": t.substr(5), "op": "", "v": 0.0}
	if t == "hurt_any":
		return {"neg": neg, "k": "hurt_any", "a": "", "op": "", "v": 0.0}
	return {}


## 返回 [是否本段的条件, 值]
static func mf_cond(o, c: Dictionary) -> Array:
	match str(c.k):
		"all":
			for q in c.list:
				if not cond_true(o, q):
					return [true, false]
			return [true, true]
		"node":
			var tk = o.get("taken")
			return [true, tk is Array and str(c.a) in tk]
		"hurt_any":
			var g = o.g
			return [true, g.hp < g.max_hp or (g.knight.alive and g.knight.hp < g.knight.maxhp)]
	return [false, false]


# ---------------------------------------------------------------- 瞬时 / 常驻积木

## 瞬时（data_operator._exec_list 缺省分支）：verb.guard / verb.cleanse
static func mf_exec(o, b: Dictionary, _at: Vector2) -> void:
	match str(b.get("_tag", "")):
		"verb.guard":
			var st := mf_st(o)
			var nm: String = str(b.get("name", "减伤"))
			var gd: Dictionary = st.guards.get(nm, {})
			if gd.is_empty():
				gd = {"u": int(b.get("_uid", 0))}
				st.guards[nm] = gd
				var keys: Array = st.guards.keys()
				keys.sort_custom(func(x, y): return int(st.guards[x].u) < int(st.guards[y].u))   # 相乘顺序固定：按积木顺序
				var sorted := {}
				for k in keys:
					sorted[k] = st.guards[k]
				st.guards = sorted
			gd.t = float(b.get("dur", 3.0))
			gd.dur = float(b.get("dur", 3.0))
			gd.v = float(b.get("value", 0.0))
			gd.col = _mf_col(b.get("col", []), o.col())
			gd.look = b.get("look", {})
			if b.has("fx"):
				fx_play(o, b.fx, o.g.ppos, 30.0)
		"verb.cleanse":
			for w in b.get("what", []):
				if str(w) == "nerve":
					o.g.nerve = 0.0


## 常驻（data_operator._sustain 转来）：verb.summon_mod 按本帧生效顺序整理成每种召唤物的倍率表
static func mf_sustain(o, act: Array) -> void:
	var mods := {}
	for b in act:
		if str(b.get("_tag", "")) != "verb.summon_mod":
			continue
		var k: String = str(b.get("kind", ""))
		if not mods.has(k):
			mods[k] = _mf_mod_empty()
		var m: Dictionary = mods[k]
		for f in MF_MOD_FACTORS:
			if b.has(f):
				m[f].append(float(b[f]))
		if b.has("then") and m.then.is_empty():
			m.then = b.then
		if b.has("mirror") and m.mirror.is_empty():
			m.mirror = b.mirror
	if not mods.is_empty() or not o.mf.is_empty():
		mf_st(o).mods = mods


static func _mf_mod_empty() -> Dictionary:
	return {"dmg": [], "aspd": [], "reach": [], "arc": [], "speed": [], "then": {}, "mirror": {}}


static func mf_mods(o, kind: String) -> Dictionary:
	if o.mf.is_empty():
		return _mf_mod_empty()
	return o.mf.mods.get(kind, _mf_mod_empty())


## 每帧开头（data_operator.update）：限时减伤计时、trig.on_deploy、带 at 的 trig.on_skill_end（prev = 上一帧的技能剩余秒数）
static func mf_tick(o, dt: float, prev: Array) -> void:
	if not o.mf.is_empty() and not o.mf.guards.is_empty():
		for nm in o.mf.guards:
			var gd: Dictionary = o.mf.guards[nm]
			gd.t = maxf(0.0, float(gd.t) - dt)
	if o.B.get("_mf_deploy", false):
		var st := mf_st(o)
		for t in o._trigs():
			if str(t.get("_tag", "")) == "trig.on_deploy" and not st.deployed.has(int(t._uid)) and o.pos != Vector2.INF and cond_true(o, t.get("cond", {})):
				st.deployed[int(t._uid)] = true
				o._exec_list(t.get("do", []))
	for i in 3:
		if prev[i] > 0.0 and o.s_t[i] <= 0.0:
			for t in o._trigs():
				if str(t.get("_tag", "")) == "trig.on_skill_end" and t.has("at") and int(t.get("skill", -1)) == i and cond_true(o, t.get("cond", {})):
					mf_fire_at(o, t, mf_at_point(o, str(t.at)))


## 带 at 的技能触发：delay > 0 进本干员延迟队列（带点），否则立即执行（do 里 center: target = 这个点）
static func mf_fire_at(o, t: Dictionary, p: Vector2) -> void:
	var dl: float = float(t.get("delay", 0.0))
	if dl > 0.0:
		o.pending.append({"t": dl, "do": t.get("do", []), "at": p})
	else:
		o._exec_list(t.get("do", []), p)


## summon:<种类> = 这种召唤物里最早的一个的位置（没有时退回本干员）；self / leader
static func mf_at_point(o, at: String) -> Vector2:
	if at.begins_with("summon"):
		var k: String = at.substr(7) if at.length() > 7 else ""
		if not o.sm.is_empty():
			for s in o.sm.list:
				if k == "" or str(s.kind) == k:
					return s.pos
		return o.pos
	if at == "leader":
		return o.g.ppos
	return o.pos


## 技能起手朝向（blocks.skills[i].aim）：summon:<种类> / leader；没写返回 INF（不转身）
static func mf_skill_aim(o, i: int) -> Vector2:
	var sk: Array = o.B.get("skills", [])
	if i < 0 or i >= sk.size() or not sk[i].has("aim"):
		return Vector2.INF
	var a: String = str(sk[i].aim)
	if a.begins_with("summon") and (o.sm.is_empty() or o.sm.list.is_empty()):
		return o.g.ppos
	return mf_at_point(o, a)


## 受击询问（data_operator.dmg_taken_mult）：m × Π(1 - 各生效减伤)，按积木顺序
static func mf_guard_mult(o, m: float) -> float:
	if o.mf.is_empty():
		return m
	for nm in o.mf.guards:
		var gd: Dictionary = o.mf.guards[nm]
		if float(gd.t) > 0.0:
			m *= 1.0 - float(gd.v)
	return m


## 状态条：技能 status（生效中）+ 生效的减伤
static func mf_status_items(o) -> Array:
	var out: Array = []
	var sk: Array = o.B.get("skills", [])
	for i in mini(3, sk.size()):
		if sk[i].has("status") and o.skill_on(i):
			out.append([str(sk[i].status), _mf_col(sk[i].get("status_col", []), o.col())])
	if not o.mf.is_empty():
		for nm in o.mf.guards:
			if float(o.mf.guards[nm].t) > 0.0:
				out.append([str(nm), o.mf.guards[nm].col])
	return out


## 减伤护壳（verb.guard.look）：主控周身。strip（art.gd 贴图，frames / fps / anchor）缺图时画程序六边形；
## 刚罩上 fade_in 秒淡入，最后 blink 秒闪烁淡出
static func mf_draw_guards(o) -> void:
	if o.mf.is_empty() or o.g.ppos == Vector2.INF:
		return
	var g = o.g
	for nm in o.mf.guards:
		var gd: Dictionary = o.mf.guards[nm]
		var lk: Dictionary = gd.get("look", {})
		var t: float = float(gd.t)
		if t <= 0.0 or lk.is_empty():
			continue
		var bl: float = float(lk.get("blink", 0.5))
		var al: float = 1.0 if t > bl else (0.35 + 0.65 * absf(sin(t * 18.0)))
		var c: Vector2 = g.ppos + Vector2(0, -22)
		var ov = lk.get("off", [])
		if ov is Array and ov.size() == 2:
			c = g.ppos + Vector2(float(ov[0]), float(ov[1]))
		var stx: Texture2D = ArtS.tex(str(lk.get("strip", ""))) if lk.has("strip") else null
		if stx != null:
			var fr: int = maxi(1, int(lk.get("frames", 1)))
			var fin: float = clampf((float(gd.dur) - t) / maxf(0.01, float(lk.get("fade_in", 0.2))), 0.0, 1.0)
			var av = lk.get("anchor", [])
			var an: Vector2 = Vector2(float(av[0]), float(av[1])) if av is Array and av.size() == 2 else Vector2.ZERO
			o._strip(stx, fr, int(g.t * float(lk.get("fps", 6))) % fr, c, g.PX, an, false, Color(1, 1, 1, float(lk.get("alpha", 0.5)) * al * fin))
			continue
		var cc: Color = gd.col
		var R: float = float(lk.get("r", 34.0)) + 1.5 * sin(g.t * 5.0)
		var hexp := PackedVector2Array()
		for i in 7:
			var an2: float = g.t * 0.6 + i * TAU / 6.0
			hexp.append(c + Vector2(cos(an2) * R, sin(an2) * R * 1.12))
		o.cv.draw_colored_polygon(hexp.slice(0, 6), Color(cc.r * 0.7, cc.g * 1.3, cc.b * 0.9, 0.13 * al))
		o.cv.draw_polyline(hexp, Color(minf(cc.r * 1.6, 2.0), 2.0, minf(cc.b * 1.6, 2.0), 0.7 * al), 2.0)
		for i in 3:
			o.cv.draw_line(hexp[i], hexp[i + 3], Color(cc.r * 1.2, cc.g * 1.7, cc.b * 1.3, 0.18 * al), 1.0)


# ---------------------------------------------------------------- 随行召唤物（move.mode = escort）

## 闲时站位：本干员脚底 + rest（x 乘本干员朝向）
static func mf_rest(o, mv: Dictionary) -> Vector2:
	var rv = mv.get("rest", [44, 18])
	var r := Vector2(float(rv[0]), float(rv[1])) if rv is Array and rv.size() == 2 else Vector2(44, 18)
	return o.pos + r * Vector2(o.face, 1.0)


## 攻击距离：r × op_range × 各 reach 倍率（依次乘）
static func mf_reach(o, a: Dictionary, mods: Dictionary) -> float:
	var r: float = float(a.get("r", 30.0)) * o.stat(&"op_range")
	for f in mods.reach:
		r *= f
	return r


## 出手伤害：base[atk_key] × _dmg_bonus × 各 dmg 倍率 [× patch.mult（× 技能强度）]
static func mf_dmg(o, a: Dictionary, mods: Dictionary, pt: Dictionary) -> float:
	var d: float = o.base(str(a.get("atk_key", "atk")), 0.0) * o._dmg_bonus()
	for f in mods.dmg:
		d *= f
	if pt.has("mult"):
		d *= float(pt.mult) * (o.skill_power() if pt.get("power", false) else 1.0)
	return d


## 转向防抖：距上次翻身至少 FACE_MIN 秒（同干员本体）
static func _mf_face(o, s: Dictionary, want: float) -> void:
	if want == 0.0 or want == float(s.face) or o.g.t - float(s.get("flip_t", -99.0)) < MF_FACE_MIN:
		return
	s.face = want
	s.flip_t = o.g.t


static func _mf_set_anim(s: Dictionary, k: String) -> void:
	if str(s.ak) != k:
		s.ak = k
		s.at = 0.0


## 回位 / 追击路径绕开 avoid 里的人（self = 本干员、leader = 主控）：直线会从人身上穿过时，先走到那人脚下前方 56 的绕行点；
## 滞回：进了绕行就走到绕行点（16 内）或 1.2 秒后才退出，退出后 0.4 秒内不再进入（docs/45 §5 的 Mon3tr 走位）
static func _mf_route(o, s: Dictionary, mv: Dictionary, want: Vector2) -> Vector2:
	var av = mv.get("avoid", [])
	if not (av is Array) or av.is_empty():
		return want
	var g = o.g
	if s.via != Vector2.INF:
		if s.pos.distance_to(s.via) > 16.0 and g.t - float(s.via_t) < 1.2:
			return s.via
		s.via = Vector2.INF
		s.via_off = g.t
	if g.t - float(s.via_off) < 0.4:
		return want
	var cs: Array = []
	for w in av:
		cs.append(o.pos if str(w) == "self" else g.ppos)
	for c in cs:
		if c == Vector2.INF or s.pos.distance_to(c) < 12.0 or want.distance_to(c) < 12.0:
			continue
		var q: Vector2 = Geometry2D.get_closest_point_to_segment(c, s.pos, want)
		if q.distance_to(c) < 40.0 and absf(s.pos.y - c.y) < 50.0:
			var via: Vector2 = c + Vector2(0, 56)
			if mv.has("solid") and g.tex.get("prop_pillar") != null:
				via = g.map.push_out(via, float(mv.solid))
			if s.pos.distance_to(via) > 32.0:
				s.via = via
				s.via_t = g.t
				return via
	return want


## 当前生效的 patch（第一条 cond 成立的；没有 = {}）。换 patch 时记下旧 patch 的 seq 收尾秒数
static func _mf_patch_tick(o, s: Dictionary, kd: Dictionary, dt: float) -> Dictionary:
	var pl: Array = kd.get("patch", [])
	var idx := -1
	for i in pl.size():
		if cond_true(o, pl[i].get("cond", {})):
			idx = i
			break
	if idx != int(s.pidx):
		var old: int = int(s.pidx)
		if old >= 0 and old < pl.size() and pl[old].has("seq"):
			s.pout = float(pl[old].seq.get("out", 0.0))
			s.pold = old
		s.pidx = idx
		s.pt = 0.0
	s.pt = float(s.pt) + dt
	s.pout = maxf(0.0, float(s.pout) - dt)
	s.pcur = pl[idx] if idx >= 0 else {}
	return s.pcur


## 种类 fx 的定时部分：带 every 的条目在召唤物处播；ghost 每 every 秒记一次残影（条件不成立时清掉）
static func _mf_fx_tick(o, s: Dictionary, kd: Dictionary, dt: float) -> void:
	var fl: Array = kd.get("fx", [])
	if fl.is_empty():
		return
	var gh := false
	for i in fl.size():
		var f: Dictionary = fl[i]
		if f.has("ghost"):
			if not fx_on(o, f):
				continue
			gh = true
			if s.ghost.is_empty() or float(s.ghost.t) <= 0.0:
				s.ghost = {"pos": s.pos, "face": s.face, "ak": s.ak, "at": s.at, "t": float(f.ghost.get("every", 0.12))}
			else:
				s.ghost.t = float(s.ghost.t) - dt
			continue
		var ev: float = float(f.get("every", 0.0))
		if ev <= 0.0:
			continue
		var tm: float = float(s.fxt.get(i, 0.0)) - dt
		if tm <= 0.0:
			tm = ev
			if fx_on(o, f):
				if mf_is(f):
					mf_fx_spawn(o, f, {"c": s.pos, "r": float(kd.get("r", 10.0)), "s": s})
				else:
					fx_spawn(o, f, s.pos, float(kd.get("r", 10.0)), [], 0.0)
		s.fxt[i] = tm
	if not gh:
		s.ghost = {}


## 一步（sm_tick 转来，代替 _sm_step）：顺序同原 Mon3tr——瞬回 → patch / 画面计时 → 选目标 → 移动 → 冷却 → 追击队列 → 出手动作 / 起手 → 动画状态
static func mf_step(o, s: Dictionary, kd: Dictionary, dt: float) -> void:
	var g = o.g
	var mv: Dictionary = kd.get("move", {})
	var a: Dictionary = kd.get("attack", {})
	var mods: Dictionary = mf_mods(o, str(s.kind))
	var rest := mf_rest(o, mv)
	if s.pos == Vector2.INF or s.pos.distance_to(g.ppos) > float(mv.get("recall", SM_FAR)):
		s.pos = rest
	var pt := _mf_patch_tick(o, s, kd, dt)
	_mf_fx_tick(o, s, kd, dt)
	var leash: float = float(mv.get("leash", 240.0))
	var anc: Vector2 = _sm_anchor(o, mv)
	var tg = s.tgt
	if str(kd.get("manual", "")) == "command" and o.manual_attack():
		# 手动普攻 B 类（契约 v2.5）：按攻击键命令召唤物扑向瞄准方向的目标；按下时换目标，松手后 manual/m_linger 秒内打完手上这个
		if g.doctor.attack_want():
			s.cmd_t = MfBal.v("manual/m_linger", 1.2)
			if g.doctor.atk_edge or tg == null or tg.dead or tg.pos.distance_to(anc) > leash + 40.0:
				var tsm: Array = o.aim_targets(1, leash, anc)
				if not tsm.is_empty():
					tg = tsm[0]
					g.doctor.atk_buf = 0.0
		else:
			s.cmd_t = maxf(0.0, float(s.cmd_t) - dt)
		if float(s.cmd_t) <= 0.0 or (tg != null and (tg.dead or tg.pos.distance_to(anc) > leash + 40.0)):
			tg = null
		s.tgt = tg
	elif tg == null or tg.dead or tg.pos.distance_to(anc) > leash + 40.0:
		var ts: Array = o.nearest_enemies(1, leash, anc)
		tg = ts[0] if not ts.is_empty() else null
		s.tgt = tg
	var want: Vector2 = rest
	if tg != null:
		var off: Vector2 = s.pos - tg.pos
		want = tg.pos + (off.normalized() if off.length() > 1.0 else Vector2(-float(s.face), 0)) * (float(tg.r) + float(mv.get("gap", 26.0)))
	var prev: Vector2 = s.pos
	if float(s.act) <= 0.0:
		var spd: float = float(mv.get("speed", 240.0))
		if pt.has("speed"):
			spd *= float(pt.speed)
		for f in mods.speed:
			spd *= f
		var d: Vector2 = _mf_route(o, s, mv, want) - s.pos
		s.pos += d.normalized() * minf(d.length(), spd * dt)
		if mv.has("solid") and g.tex.get("prop_pillar") != null:
			s.pos = g.map.push_out(s.pos, float(mv.solid))
	var vel: Vector2 = (s.pos - prev) / maxf(dt, 0.0001)
	s.mv = lerpf(float(s.mv), vel.length(), clampf(dt * 10.0, 0.0, 1.0))
	if absf(vel.x) > 20.0 and float(s.act) <= 0.0:
		_mf_face(o, s, signf(vel.x))
	var k: float = dt
	for f in mods.aspd:
		k *= f
	s.cd = float(s.cd) - k
	if not s.pend.is_empty():
		for pc in s.pend:
			pc.t -= dt
			if pc.t <= 0.0:
				_mf_claw(o, s, kd, float(pc.mult), true)
		s.pend = s.pend.filter(func(pc): return pc.t > 0.0)
	if float(s.act) > 0.0:
		s.act = float(s.act) - dt
		if float(s.fire) >= 0.0:
			s.fire = float(s.fire) - dt
			if float(s.fire) < 0.0:
				s.fire = -1.0
				_mf_strike(o, s, kd)
	elif tg != null and not a.is_empty() and float(s.cd) <= 0.0 and s.pos.distance_to(tg.pos) < float(tg.r) + mf_reach(o, a, mods):
		s.cd = float(a.get("every", 1.0)) / o.stat(&"op_aspd")
		if absf(tg.pos.x - s.pos.x) > 2.0:
			_mf_face(o, s, signf(tg.pos.x - s.pos.x))
		var spec: Dictionary = o.sprite_spec(str(kd.get("anim", {}).get("attack", "")))
		var fps: float = float(spec.get("fps", 14))
		s.act = float(spec.get("frames", 4)) / fps
		s.fire = (float(spec.get("fire", 2)) + 0.5) / fps
		_mf_set_anim(s, "attack")
	_mf_set_anim(s, "attack" if float(s.act) > 0.0 else ("run" if float(s.mv) > 30.0 else "idle"))
	s.at = float(s.at) + dt


static func _mf_strike(o, s: Dictionary, kd: Dictionary) -> void:
	s.swing = -float(s.swing)
	_mf_claw(o, s, kd, 1.0, false)
	var th: Dictionary = mf_mods(o, str(s.kind)).then
	if not th.is_empty():
		s.pend.append({"t": float(th.get("delay", 0.1)), "mult": float(th.get("mult", 0.5))})


## 一击：朝 dir（face = 召唤物面向；target = 朝目标）挥出锥形；mirror 时同时向身后镜像一击（没打到不画）。second = then 的追击
static func _mf_claw(o, s: Dictionary, kd: Dictionary, mult: float, second: bool) -> void:
	var a: Dictionary = kd.get("attack", {})
	var mods: Dictionary = mf_mods(o, str(s.kind))
	var pt: Dictionary = s.pcur
	var fwd: float = 0.0 if float(s.face) >= 0.0 else PI
	if str(a.get("dir", "face")) == "target" and s.tgt != null and not s.tgt.dead:
		fwd = (s.tgt.pos - s.pos).angle()
	var ov = a.get("origin", [])
	var org: Vector2 = s.pos + (Vector2(float(ov[0]), float(ov[1])) if ov is Array and ov.size() == 2 else Vector2.ZERO)
	var fv = a.get("fx_origin", ov)
	var fo: Vector2 = s.pos + (Vector2(float(fv[0]), float(fv[1])) if fv is Array and fv.size() == 2 else Vector2.ZERO)
	var half: float = float(a.half) if a.has("half") else deg_to_rad(float(a.get("half_deg", 45.0)))
	for f in mods.arc:
		half *= f
	var mi: Dictionary = mods.mirror
	var dirs: Array = [fwd, fwd + PI] if not mi.is_empty() else [fwd]
	var src: String = str(pt.get("src", a.get("src", "")))
	var tags: Array = a.get("tags", []).duplicate()
	if not "summon" in tags:
		tags.append("summon")
	var any := false
	for i in dirs.size():
		var ang: float = dirs[i]
		var sd: float = 1.0 if cos(ang) >= 0.0 else -1.0
		var reach := mf_reach(o, a, mods)
		var dmg: float = mf_dmg(o, a, mods, pt) * mult * (1.0 if i == 0 else float(mi.get("mult", 1.0)))
		var hits: Array = o.melee_hit(src, org, ang, half, reach + float(a.get("pad", 0.0)), dmg, float(a.get("kb", 0.0)), float(a.get("stun", 0.0)), tags, int(a.get("max_n", 0)))
		any = any or not hits.is_empty()
		for stt in a.get("on_hit", []):
			for e in hits:
				apply_status(o, e, stt)
		if i > 0 and hits.is_empty():
			continue   # 身后一击没打到时不画（刀光会正好盖在本干员和主控身上，docs/45 #6）
		if a.has("fx"):
			for f in a.fx:
				if f is Dictionary and fx_on(o, f) and not (second and f.get("first_only", false)):
					if mf_is(f):
						mf_fx_spawn(o, f, {"c": fo, "r": reach, "hits": hits, "ang": ang, "sd": sd, "reach": reach, "half": half, "second": second, "swing": float(s.swing), "s": s})
					else:
						fx_spawn(o, f, fo, reach, hits, ang)
	if any:
		var sf: Dictionary = a.get("sfx", {})
		var ps: Dictionary = pt.get("sfx", {})
		if not sf.is_empty():
			var th: Dictionary = mods.then
			_mf_sfx(o, str(sf.get("kind", "atk")), float(ps.get("db", sf.get("db", 0.0))),
				float(ps.get("pitch", sf.get("pitch", 1.0))) * (float(th.get("pitch", 1.0)) if second else 1.0))


static func _mf_sfx(o, kind: String, db: float, pitch: float) -> void:
	var g = o.g
	var sfx: Node = g.get_node_or_null("/root/Sfx") if g != null and g.is_inside_tree() else null
	if sfx != null:
		sfx.op(o.id, kind, db, pitch)


## 悬浮高度（世界像素，负 = 往上）：float {h, amp, hz}：-h - amp × sin(g.t × hz + x × 0.01)
static func _mf_hover(o, s: Dictionary, kd: Dictionary) -> float:
	var fl: Dictionary = kd.get("float", {})
	if fl.is_empty():
		return 0.0
	return -float(fl.get("h", 0.0)) - float(fl.get("amp", 0.0)) * sin(o.g.t * float(fl.get("hz", 2.6)) + s.pos.x * 0.01)


## 这一帧的帧条：[贴图, 帧号, 帧数, 脚底键]；patch 的 seq（起手 intro 帧、loop 段循环、收尾 out 秒停在末帧）代替 idle / run，攻击用 patch.anim.attack
static func _mf_frame(o, s: Dictionary, kd: Dictionary, ak: String, at: float) -> Array:
	var an: Dictionary = kd.get("anim", {})
	var pl: Array = kd.get("patch", [])
	var pt: Dictionary = s.pcur
	var sq: Dictionary = {}
	var live := false
	if pt.has("seq"):
		sq = pt.seq
		live = true
	elif float(s.pout) > 0.0 and int(s.get("pold", -1)) >= 0 and int(s.pold) < pl.size():
		sq = pl[int(s.pold)].get("seq", {})
	if not sq.is_empty() and ak != "attack":
		var key: String = str(sq.get("strip", ""))
		var tx: Texture2D = o.anim_tex(key)
		if tx != null:
			var n: int = o.anim_hframes(tx, key)
			var fps: float = float(o.sprite_spec(key).get("fps", 12))
			var fr: int
			if not live:
				fr = n - 1
			else:
				var el: float = float(s.pt)
				var intro: float = float(sq.get("intro", 0)) / fps
				var lp = sq.get("loop", [0, n - 1])
				var l0: int = int(lp[0])
				var ln: int = maxi(1, int(lp[1]) - l0 + 1)
				fr = int(el * fps) if el < intro else l0 + int((el - intro) * fps) % ln
			return [tx, clampi(fr, 0, n - 1), n, key]
	var base_key: String = str(an.get(ak, an.get("idle", "")))
	var pa: Dictionary = pt.get("anim", {})
	var tx2: Texture2D = o.anim_tex(str(pa.get(ak, base_key)))
	if tx2 == null:
		tx2 = o.anim_tex(base_key)
	if tx2 == null:
		return []
	var n2: int = o.anim_hframes(tx2, base_key)
	var fr2: int
	if ak == "attack":
		fr2 = clampi(int(at * float(o.sprite_spec(base_key).get("fps", 14))), 0, n2 - 1)
	else:
		fr2 = int(at * float(o.sprite_spec(base_key).get("fps", 4))) % n2
	return [tx2, fr2, n2, base_key]


## 画一个随行召唤物（sm_draw 转来）：残影 → 身后红雾 → 本体（按状态帧条、悬浮起伏、patch 染色）→ 两侧爪刃
static func mf_draw(o, s: Dictionary, kd: Dictionary) -> bool:
	var fr := _mf_frame(o, s, kd, str(s.ak), float(s.at))
	if fr.is_empty():
		return false
	var g = o.g
	var hov := _mf_hover(o, s, kd)
	var fl: Array = kd.get("fx", [])
	for f in fl:
		if not (f is Dictionary) or not fx_on(o, f):
			continue
		if f.has("ghost") and not s.ghost.is_empty() and s.ghost.pos.distance_to(s.pos) > 3.0:
			var gf := _mf_frame(o, s, kd, str(s.ghost.ak), float(s.ghost.at))
			if not gf.is_empty():
				o.draw_sprite_at(s.ghost.pos + Vector2(0, hov), (float(s.ghost.face) < 0.0) != o.sprite_mirror(str(gf[3])), _mf_col(f.ghost.get("tint", []), Color(1, 1, 1, 0.35)), gf[1], gf[0], gf[2], o.foot_off(gf[0], gf[3]))
		elif f.has("mist"):
			var m: Dictionary = f.mist
			var mc: Color = _mf_col(m.get("col", []), Color(0.85, 0.025, 0.02, 0.12))
			for q in int(m.get("n", 3)):
				var ph: float = g.t * float(m.get("hz", 1.7)) + q * 1.3
				var off := Vector2(cos(ph) * float(m.get("dx", 16.0)), sin(ph * 1.3) * float(m.get("dy", 10.0)) + hov + float(m.get("y", -50.0)))
				o.cv.draw_circle(s.pos + off, float(m.get("r", 14.0)) + float(m.get("rv", 5.0)) * sin(ph * 2.0), mc)
	var col := Color.WHITE
	if float(s.pout) <= 0.0 and s.pcur.has("tint"):
		col = _mf_col(s.pcur.tint)
	o.draw_sprite_at(s.pos + Vector2(0, hov), (float(s.face) < 0.0) != o.sprite_mirror(str(fr[3])), col, fr[1], fr[0], fr[2], o.foot_off(fr[0], fr[3]))
	for f in fl:
		if f is Dictionary and f.has("side") and fx_on(o, f):
			_mf_side(o, s, f.side, hov)
	return true


## 身体两侧对称的常驻装饰（爪刃）：strip（art.gd 贴图，frames / fps / anchor，朝右一侧水平镜像）或程序双层弧（col）；j = 第几组（往外 dxj、往下 yj）
static func _mf_side(o, s: Dictionary, sd: Dictionary, hov: float) -> void:
	var g = o.g
	var j: int = int(sd.get("j", 0))
	var body: Vector2 = s.pos + Vector2(0, hov + float(sd.get("body_y", -26.0)))
	var sides: Array = [float(s.face), -float(s.face)]
	var tx: Texture2D = ArtS.tex(str(sd.strip)) if sd.has("strip") else null
	if tx != null:
		var frames: int = maxi(1, int(sd.get("frames", 1)))
		var bf: int = int(g.t * float(sd.get("fps", 4))) % frames
		var av = sd.get("anchor", [])
		var anc: Vector2 = Vector2(float(av[0]), float(av[1])) if av is Array and av.size() == 2 else Vector2.ZERO
		for q in sides:
			var bob: float = sin(g.t * 3.0 + j * 1.7 + q) * float(sd.get("bob", 2.5))
			var bp: Vector2 = body + Vector2(q * (float(sd.get("dx", 33.0)) + float(sd.get("dxj", 5.0)) * j), float(sd.get("y", -10.0)) + float(sd.get("yj", 15.0)) * j + bob)
			o._strip(tx, frames, (bf + j) % frames, bp, g.PX, anc, q > 0.0, Color.WHITE)
		return
	if sd.has("strip") and not sd.has("col"):
		return
	var c: Color = _mf_col(sd.get("col", []), o.col())
	for q in sides:
		var base_a: float = 0.0 if q >= 0.0 else PI
		var sway: float = sin(g.t * 3.0 + j * 1.7 + q) * 0.18
		var cp: Vector2 = body + Vector2(q * (float(sd.get("arc_dx", 27.0)) + float(sd.get("dxj", 5.0)) * j), float(sd.get("y", -10.0)) + float(sd.get("yj", 15.0)) * j)
		var a0: float = base_a - 0.95 + sway
		var a1: float = base_a + 0.95 + sway
		o.cv.draw_arc(cp, 15.0, a0, a1, 12, Color(c.r, c.g, c.b, 0.22), 6.0)
		o.cv.draw_arc(cp, 15.0, a0, a1, 12, Color(c.r * 1.7, c.g * 1.7, c.b * 1.5, 0.85), 2.0)


## 影子：shadow = 影子贴图倍率（悬浮时随起伏缩放 ±10%）；返回 false = 没写，走程序椭圆
static func mf_shadow(o, s: Dictionary, kd: Dictionary) -> bool:
	if not kd.has("shadow"):
		return false
	var fl: Dictionary = kd.get("float", {})
	var k: float = float(kd.shadow)
	if not fl.is_empty():
		k *= 1.0 - 0.1 * sin(o.g.t * float(fl.get("hz", 2.6)) + s.pos.x * 0.01)
	o.draw_spr("shadow", 1, 0, s.pos + Vector2(0, 4), o.g.PX * k)
	return true


# ---------------------------------------------------------------- 程序 fx 条目（§5.6 追加；纯画面，只用 g.vrng）

static func mf_is(f) -> bool:
	if not (f is Dictionary):
		return false
	for k in MF_FX_KINDS:
		if f.has(k):
			return true
	return false


## 一个数值：数字原样；[lo, hi] 取 g.vrng 区间随机
static func _mf_num(g, v) -> float:
	if v is Array and v.size() == 2:
		return g.vrng.randf_range(float(v[0]), float(v[1]))
	return float(v)


## 条目的落点列表（at：center = 出手 / 区域中心、self、leader、hits = 每个命中的敌人、summon = 本干员的每个召唤物）
static func _mf_points(o, f: Dictionary, ctx: Dictionary) -> Array:
	var g = o.g
	var out: Array = []
	match str(f.get("at", "center")):
		"self":
			out.append(o.pos)
		"leader":
			out.append(g.ppos)
		"hits":
			for e in ctx.get("hits", []):
				out.append(e.pos + Vector2(0, -float(e.r) * 0.5))
		"summon":
			if not o.sm.is_empty():
				for s in o.sm.list:
					out.append(s.pos)
		_:
			out.append(ctx.get("c", o.pos))
	var res: Array = []
	var ov = f.get("off", [])
	var off := Vector2(float(ov[0]), float(ov[1])) if ov is Array and ov.size() == 2 else Vector2.ZERO
	if f.get("face_x", false):
		off.x *= o.face
	var al: float = float(f.get("along", 0.0)) * float(f.get("r_mult", 1.0))
	var sx: float = float(f.get("side_x", 0.0)) * float(f.get("r_mult", 1.0))
	var rch: float = float(ctx.get("reach", ctx.get("r", 0.0)))
	var dir := Vector2.from_angle(float(ctx.get("ang", 0.0)))
	for p in out:
		if p == Vector2.INF:
			continue
		res.append(p + off + dir * rch * al + Vector2(float(ctx.get("sd", 1.0)) * rch * sx, 0))
	return res


## 播一个程序条目。ctx：c（中心）、r（半径）、hits、ang、sd（这一击朝左右）、reach、half、second、swing、s（召唤物）
static func mf_fx_spawn(o, f: Dictionary, ctx: Dictionary) -> void:
	var g = o.g
	if g == null:
		return
	if f.has("pause"):
		o.impact_pause(float(f.pause))
		return
	if f.has("sfx"):
		var sv = f.sfx
		if sv is Dictionary:
			_mf_sfx(o, str(sv.get("kind", "hit")), float(sv.get("db", 0.0)), float(sv.get("pitch", 1.0)))
		else:
			_mf_sfx(o, str(sv), 0.0, 1.0)
		return
	if f.has("banner"):
		o.show_banner(str(f.banner))
		return
	if f.has("ghost") or f.has("mist") or f.has("side"):
		return   # 种类常驻画面，在 mf_draw 里画
	if f.has("pfx") and o.pfx.size() > 260:
		return
	for p in _mf_points(o, f, ctx):
		if f.has("text"):
			var tv: Dictionary = f.text if f.text is Dictionary else {"s": str(f.text)}
			o.float_text(p, str(tv.get("s", "")), _mf_col(tv.get("col", []), o.col()), int(tv.get("size", 14)))
		elif f.has("sparks"):
			var sp: Dictionary = f.sparks
			var n: int = int(round(float(sp.get("n", 5)) * (1.0 + 0.2 * o.node_lv)))
			var spd: float = float(sp.get("spd", 160.0))
			for k in n:
				o.fx({"kind": "spark", "pos": p, "vel": Vector2.from_angle(g.vrng.randf() * TAU) * g.vrng.randf_range(spd * 0.4, spd),
					"life": float(sp.get("life", 0.3)) * g.vrng.randf_range(0.7, 1.2), "col": _mf_col(sp.get("col", []), o.col()), "sz": float(sp.get("sz", 2.5)), "drag": 2.0, "grav": 0.0, "floor": false})
		elif f.has("arc"):
			var ar: Dictionary = f.arc
			o.fx({"kind": "crescent", "pos": p, "ang": float(ctx.get("ang", 0.0)), "r": float(ctx.get("reach", 30.0)) + float(ar.get("pad", 0.0)),
				"w": float(ar.get("w", 5.0)), "sweep": float(ctx.get("half", 0.5)) * 2.0, "dir": float(ctx.get("sd", 1.0)), "life": float(ar.get("life", 0.2)),
				"col": _mf_col(ar.get("col", []), o.col())})
		elif f.has("sprite"):
			_mf_sprite(o, f, p, ctx)
		elif f.has("pfx") or f.has("gfx"):
			var tpl: Dictionary = f.pfx if f.has("pfx") else f.gfx
			var n2: int = int(f.get("n", 1))
			for i in n2:
				var px := _mf_particle(o, f, tpl, p, ctx, i, n2)
				if f.has("gfx"):
					px["max"] = px.life
					if str(px.get("kind", "")) == "rays":
						px["op_spoke"] = true   # 干员技能发动的放射光束（render/hit_spokes）
					g.fx.append(px)
				else:
					o.fx(px)


## 一个粒子：模板里的 [lo, hi] 取随机；jit 方框 / jit_r（× 半径的地面椭圆）散开；ring 均匀分角度（± 抖动）；vel_r 随机方向速度；
## r_scale 列出的字段 × 半径；to / to_off 给 beam / line 的终点；颜色字段是数组
static func _mf_particle(o, f: Dictionary, tpl: Dictionary, p: Vector2, ctx: Dictionary, i: int, n: int) -> Dictionary:
	var g = o.g
	var px := {}
	for k in tpl:
		var v = tpl[k]
		if k in ["col"]:
			px[k] = _mf_col(v, o.col())
		elif k == "vel" and v is Array and v.size() == 2 and v[0] is Array:
			px[k] = Vector2(_mf_num(g, v[0]), _mf_num(g, v[1]))
		elif v is Array and v.size() == 2 and (v[0] is int or v[0] is float):
			px[k] = _mf_num(g, v)
		else:
			px[k] = v
	var r: float = float(ctx.get("r", 0.0))
	for k in f.get("r_scale", []):
		if px.has(k):
			px[k] = float(px[k]) * r
	var q: Vector2 = p
	var jv = f.get("jit", [])
	if jv is Array and jv.size() == 4:
		q += Vector2(g.vrng.randf_range(float(jv[0]), float(jv[2])), g.vrng.randf_range(float(jv[1]), float(jv[3])))
	var jr = f.get("jit_r", [])
	if jr is Array and jr.size() == 2:
		q += Vector2(g.vrng.randf_range(-r, r) * float(jr[0]), g.vrng.randf_range(-r, r) * float(jr[1]))
	px["pos"] = q
	if f.has("ring"):
		px["ang"] = TAU * i / float(maxi(1, n)) + g.vrng.randf_range(-float(f.ring), float(f.ring))
	if f.has("vel_r"):
		var vr = f.vel_r
		var vel: Vector2 = Vector2.from_angle(g.vrng.randf() * TAU) * _mf_num(g, vr)
		px["vel"] = vel
		if f.get("ang_vel", false):
			px["ang"] = vel.angle()
	if f.has("to"):
		var tp: Vector2 = mf_at_point(o, str(f.to)) if str(f.to) != "center" else ctx.get("c", o.pos)
		var tv2 = f.get("to_off", [])
		if tv2 is Array and tv2.size() == 2:
			tp += Vector2(float(tv2[0]), float(tv2[1]))
		var tj = f.get("to_jit", [])
		if tj is Array and tj.size() == 4:
			tp += Vector2(g.vrng.randf_range(float(tj[0]), float(tj[2])), g.vrng.randf_range(float(tj[1]), float(tj[3])))
		if str(px.get("kind", "")) == "beam":
			px["a"] = q
			px["b"] = tp
		else:
			px["to"] = tp
	if not px.has("life"):
		px["life"] = 0.3
	return px


## 一次性帧条（vfx 精灵，同手写干员的 spawn_fx_sprite）：along / side_x 沿这一击的方向放；fit = [参考半径, 最小, 最大] 按攻击距离缩放、
## scale_r = 每世界像素半径的倍率（× r_mult 后的半径）；rot / second_rot / swing_rot 都乘这一击的左右（sd）；flip_side（缺省 true）：朝左时水平翻转
static func _mf_sprite(o, f: Dictionary, p: Vector2, ctx: Dictionary) -> void:
	var g = o.g
	var sv: Dictionary = f.sprite if f.sprite is Dictionary else {"name": str(f.sprite)}
	var nm: String = str(sv.get("name", ""))
	var sd: float = float(ctx.get("sd", 1.0))
	var second: bool = ctx.get("second", false)
	var rch: float = float(ctx.get("reach", ctx.get("r", 0.0)))
	var sc: float = g.PX
	var fit = sv.get("fit", [])
	if fit is Array and fit.size() == 3:
		sc = g.PX * clampf(rch / float(fit[0]), float(fit[1]), float(fit[2]))
	elif sv.has("scale_r"):
		sc = rch * float(f.get("r_mult", 1.0)) * float(sv.scale_r)
	sc *= float(sv.get("scale", 1.0)) * (float(sv.get("second_scale", 1.0)) if second else 1.0)
	var sw: float = float(ctx.get("swing", 1.0)) * (-1.0 if second else 1.0)
	var rot: float = sd * (float(sv.get("rot", 0.0)) + (float(sv.get("second_rot", 0.0)) if second else 0.0) + float(sv.get("swing_rot", 0.0)) * sw)
	o.spawn_fx_sprite(nm, p, sc, rot, sv.get("flip_side", true) and sd < 0.0, sv.get("bottom", false), _mf_col(sv.get("tint", [])))


## 程序粒子的画法（data_operator._draw_pfx 转来；原凯尔希脚本的 crescent / impact / core / qshard / beamray）
static func mf_draw_pfx(o, f: Dictionary, a: float) -> bool:
	var cv = o.cv
	var P := func(v: Vector2) -> Vector2: return (v / 2.0).round() * 2.0
	match str(f.kind):
		"crescent":
			var u: float = 1.0 - a
			var rev: float = minf(1.0, u / 0.4)
			var half: float = f.sweep * 0.5
			var a0: float = f.ang - half * f.dir
			var a1: float = a0 + f.sweep * rev * f.dir
			var n := 16
			var outer := PackedVector2Array()
			var inner := PackedVector2Array()
			var edge := PackedVector2Array()
			for i in n + 1:
				var t: float = float(i) / n
				var an: float = lerpf(a0, a1, t)
				var th: float = f.w * sin(t * PI) * (1.0 - 0.5 * maxf(0.0, u - 0.4) / 0.6)
				var dv: Vector2 = Vector2.from_angle(an)
				var sq := Vector2(1.0, 0.8)
				outer.append(P.call(f.pos + dv * (f.r + th * 0.5) * sq))
				inner.append(P.call(f.pos + dv * (f.r - th * 0.5) * sq))
				edge.append(P.call(f.pos + dv * (f.r + th * 0.35) * sq))
			var c: Color = f.col
			if outer[0].distance_to(outer[outer.size() - 1]) > 4.0:
				for i in n:
					var q := PackedVector2Array([outer[i], outer[i + 1], inner[i + 1], inner[i]])
					if absf((q[1] - q[0]).cross(q[3] - q[0])) + absf((q[2] - q[1]).cross(q[3] - q[1])) > 2.0:
						cv.draw_colored_polygon(q, Color(c.r * 1.3, c.g * 1.3, c.b * 1.3, 0.75 * a))
				cv.draw_polyline(edge, Color(2.0, 2.0, 1.9, 0.9 * a), 2.0)
			return true
		"impact":
			var k: float = 1.0 - a
			var L: float = f.r * (0.6 + 0.8 * k)
			var c2: Color = f.col
			cv.draw_circle(f.pos, f.r * (0.9 + 0.4 * k), Color(c2.r * 1.5, c2.g * 1.5, c2.b * 1.5, 0.35 * a))
			cv.draw_circle(f.pos, f.r * 0.7 * a + 2.0, Color(2.4, 2.4, 2.2, a))
			for q in 4:
				var dv2 := Vector2.from_angle(q * PI / 4.0)
				var ll: float = L * (1.0 if q % 2 == 0 else 0.6)
				cv.draw_line(f.pos - dv2 * ll, f.pos + dv2 * ll, Color(2.2, 2.2, 2.0, a), 2.0)
			return true
		"core":
			var k3: float = 1.0 - a
			var sc: float = 0.6 + 0.8 * minf(1.0, k3 * 2.5)
			var al: float = 1.0 if k3 < 0.55 else maxf(0.0, 1.0 - (k3 - 0.55) / 0.45)
			var R: float = f.r * sc
			var top: Vector2 = f.pos + Vector2(0, -R * 1.3)
			var bot: Vector2 = f.pos + Vector2(0, R * 1.3)
			var lft: Vector2 = f.pos + Vector2(-R, 0)
			var rgt: Vector2 = f.pos + Vector2(R, 0)
			var mid: Vector2 = f.pos + Vector2(R * 0.25, -R * 0.1)
			var cc: Color = f.get("col", Color(1.6, 0.16, 0.12))
			cv.draw_circle(f.pos, R * 1.8, Color(cc.r * 1.25, cc.g * 1.9, cc.b * 1.25, 0.25 * al))
			cv.draw_colored_polygon(PackedVector2Array([top, rgt, bot, lft]), Color(cc.r, cc.g, cc.b, 0.85 * al))
			cv.draw_colored_polygon(PackedVector2Array([top, mid, bot, lft]), Color(cc.r * 1.375, cc.g * 3.1, cc.b * 2.5, 0.9 * al))
			cv.draw_polyline(PackedVector2Array([top, rgt, bot, lft, top]), Color(cc.r * 1.5, cc.g * 6.2, cc.b * 5.8, al), 2.0)
			return true
		"qshard":
			var hs: float = f.sz * 0.5
			var r0: Vector2 = Vector2.from_angle(f.get("ang", 0.0)) * hs * 1.414
			var r1: Vector2 = r0.orthogonal()
			var pts := PackedVector2Array([f.pos + r0, f.pos + r1, f.pos - r0, f.pos - r1, f.pos + r0])
			var qc: Color = f.get("col", Color(1.6, 0.2, 0.1))
			cv.draw_colored_polygon(pts.slice(0, 4), Color(qc.r, qc.g, qc.b, 0.25 * a))
			cv.draw_polyline(pts, Color(qc.r * 1.375, qc.g * 2.0, qc.b * 2.0, a), 2.0)
			return true
		"beamray":
			if not Dc.hit_spokes():   # 放射光束（render/hit_spokes 缺省不画）：粒子照走寿命，只是不画
				return true
			var k4: float = 1.0 - a
			var dv3: Vector2 = Vector2.from_angle(f.ang)
			var L2: float = f.len * minf(1.0, k4 * 3.0)
			cv.draw_line(f.pos + dv3 * 10.0, f.pos + dv3 * L2, Color(f.col.r * 1.4, f.col.g * 1.6, f.col.b * 1.3, 0.6 * a), 3.0 * a + 1.0)
			return true
	return false


# ---------------------------------------------------------------- 本段的校验

## _block 转来：本段的积木（MF_TAGS）校验完返回 true
static func _mf_block(b: Dictionary, p: String, kind: String, ctx: Dictionary, tag: String) -> bool:
	if not tag in MF_TAGS:
		return false
	var errs: Array = ctx.errs
	var where_ok := {
		"verb.summon_mod": ["skill", "sustain"],
		"verb.guard": ["skill", "instant"],
		"verb.cleanse": ["skill", "instant"],
		"trig.on_deploy": ["trig"],
	}
	if not kind in where_ok[tag]:
		errs.append("%s：「%s」不能放在这里（%s；只能在 %s）" % [p, tag, kind, " / ".join(where_ok[tag])])
		return true
	match tag:
		"verb.summon_mod":
			var k := str(b.get("kind", ""))
			var sd = ctx.get("summons", {})
			if not (sd is Dictionary) or not sd.has(k):
				errs.append("%s.kind「%s」没在 blocks.summons 里定义" % [p, k])
			var any := false
			for f in MF_MOD_FACTORS:
				if b.has(f):
					any = true
					_num(b, f, p, ctx, false, 0.1, 10.0)
			for q in ["then", "mirror"]:
				if b.has(q):
					any = true
					var v = b[q]
					if not (v is Dictionary):
						errs.append("%s.%s 必须是对象" % [p, q])
						continue
					for kk in v:
						if not kk in ["delay", "mult", "pitch", "_doc"]:
							errs.append("%s.%s.%s：只能写 delay / mult / pitch" % [p, q, kk])
					_sm_exprs(v, "%s.%s" % [p, q], ctx)
					_num(v, "mult", "%s.%s" % [p, q], ctx, true, 0.0, 5.0)
					if q == "then":
						_num(v, "delay", "%s.%s" % [p, q], ctx, true, 0.0, 2.0)
					_num(v, "pitch", "%s.%s" % [p, q], ctx, false, 0.25, 4.0)
			if not any:
				errs.append(p + "：verb.summon_mod 至少写 dmg / aspd / reach / arc / speed / then / mirror 之一")
			for kk in b:
				if not kk in MF_MOD_FACTORS + ["then", "mirror", "verb", "kind", "cond", "_doc", "_uid", "_tag"]:
					errs.append("%s.%s：verb.summon_mod 不认识的字段" % [p, kk])
		"verb.guard":
			_num(b, "value", p, ctx, true, 0.0, 0.9)
			_num(b, "dur", p, ctx, true, 0.1, 60.0)
			for kk in b:
				if not kk in MF_GUARD_KEYS:
					errs.append("%s.%s：verb.guard 不认识的字段（只能是 %s）" % [p, kk, " / ".join(MF_GUARD_KEYS)])
			if b.has("look"):
				if not (b.look is Dictionary):
					errs.append(p + ".look 必须是对象")
				else:
					for kk in b.look:
						if not kk in MF_LOOK_KEYS:
							errs.append("%s.look.%s：不认识的字段（只能是 %s）" % [p, kk, " / ".join(MF_LOOK_KEYS)])
		"verb.cleanse":
			var w = b.get("what", [])
			if not (w is Array) or w.is_empty() or w.any(func(x): return not str(x) in MF_CLEANSE):
				errs.append("%s.what 必须是非空数组，取值 %s" % [p, " / ".join(MF_CLEANSE)])
		"trig.on_deploy":
			_list(b.get("do", []), p + ".do", "instant", ctx)
	return true


## 召唤物种类的扩展字段（_sm_kinds 转来）
static func _mf_kind(kd: Dictionary, p: String, ctx: Dictionary) -> void:
	var errs: Array = ctx.errs
	var mv: Dictionary = kd.get("move", {}) if kd.get("move", {}) is Dictionary else {}
	var esc: bool = str(mv.get("mode", "")) == "escort"
	for k in MF_MOVE_KEYS:
		if mv.has(k) and not esc:
			errs.append("%s.move.%s 只用于 mode = escort" % [p, k])
	if esc:
		if mv.has("rest") and not (mv.rest is Array and mv.rest.size() == 2):
			errs.append(p + ".move.rest 必须是 [x, y]")
		_num(mv, "gap", p + ".move", ctx, false, 0.0, 200.0)
		_num(mv, "solid", p + ".move", ctx, false, 1.0, 60.0)
		_num(mv, "recall", p + ".move", ctx, false, 100.0, 2000.0)
		var av = mv.get("avoid", [])
		if not (av is Array) or av.any(func(x): return not str(x) in ["self", "leader"]):
			errs.append(p + ".move.avoid 只能是 self / leader 的数组")
		var a = kd.get("attack", null)
		if a is Dictionary and str(a.get("shape", "")) != "cone":
			errs.append(p + ".attack：escort 召唤物的攻击只能是 shape.cone（朝面向挥出）")
		if a is Dictionary:
			if not str(a.get("dir", "face")) in ["face", "target"]:
				errs.append(p + ".attack.dir 只能是 face / target")
			_num(a, "pad", p + ".attack", ctx, false, 0.0, 200.0)
			for q in ["origin", "fx_origin"]:
				if a.has(q) and not (a[q] is Array and a[q].size() == 2):
					errs.append("%s.attack.%s 必须是 [x, y]" % [p, q])
	if kd.has("manual") and str(kd.manual) != "command":
		errs.append(p + ".manual 只能是 command（手动普攻 B 类：按攻击键才命令它出击）")
	if kd.has("manual") and not esc:
		errs.append(p + ".manual 只用于 mode = escort")
	if kd.has("status") and not (kd.status is bool):
		errs.append(p + ".status 只能是 true / false（false = 状态条不显示在场数）")
	_num(kd, "shadow", p, ctx, false, 0.2, 4.0)
	if kd.has("float"):
		if not (kd.float is Dictionary):
			errs.append(p + ".float 必须是对象 {h, amp, hz}")
		else:
			_num(kd.float, "h", p + ".float", ctx, false, 0.0, 60.0)
			_num(kd.float, "amp", p + ".float", ctx, false, 0.0, 30.0)
			_num(kd.float, "hz", p + ".float", ctx, false, 0.0, 20.0)
	if kd.has("anim"):
		if not esc:
			errs.append(p + ".anim 只用于 mode = escort")
		var an = kd.anim
		if not (an is Dictionary) or not an.has("idle"):
			errs.append(p + ".anim 必须是对象，至少有 idle")
		else:
			for k in an:
				if not k in ["idle", "run", "attack"]:
					errs.append("%s.anim.%s：只能是 idle / run / attack" % [p, k])
				elif not ctx.get("sprites", {}).has(str(an[k])):
					errs.append("%s.anim.%s「%s」不是本干员 sprites 里的帧条" % [p, k, str(an[k])])
	if kd.has("patch"):
		var pl = kd.patch
		if not (pl is Array) or pl.size() > 6:
			errs.append(p + ".patch 必须是数组（≤ 6 条）")
		else:
			for i in pl.size():
				var q := "%s.patch[%d]" % [p, i]
				var pe = pl[i]
				if not (pe is Dictionary):
					errs.append(q + " 必须是对象")
					continue
				for k in pe:
					if not k in MF_PATCH_KEYS:
						errs.append("%s.%s：不认识的字段（只能是 %s）" % [q, k, " / ".join(MF_PATCH_KEYS)])
				if not pe.has("cond"):
					errs.append(q + " 缺 cond（什么时候生效）")
				elif not (pe.cond is String) or parse_cond(pe.cond, ctx.base).has("err"):
					errs.append(q + ".cond 看不懂")
				_sm_exprs(pe, q, ctx)
				_num(pe, "mult", q, ctx, false, 0.0, 20.0)
				_num(pe, "speed", q, ctx, false, 0.1, 5.0)
				if pe.has("src") and not ctx.srcs.has(str(pe.src)):
					errs.append("%s.src「%s」没在 hit_sources 里登记" % [q, str(pe.src)])
				if pe.has("anim"):
					for k in pe.anim:
						if not ctx.get("sprites", {}).has(str(pe.anim[k])):
							errs.append("%s.anim.%s「%s」不是本干员 sprites 里的帧条" % [q, k, str(pe.anim[k])])
				if pe.has("seq"):
					var sq = pe.seq
					if not (sq is Dictionary) or not ctx.get("sprites", {}).has(str(sq.get("strip", ""))):
						errs.append(q + ".seq.strip 必须是本干员 sprites 里的帧条")
					elif sq.has("loop") and not (sq.loop is Array and sq.loop.size() == 2):
						errs.append(q + ".seq.loop 必须是 [首帧, 末帧]")
	if kd.has("fx"):
		_fx(kd.fx, p + ".fx", ctx, "summon")


## fx 条目里的程序条目（_fx 转来）：返回 true = 已校验
static func _mf_fx_check(f: Dictionary, q: String, ctx: Dictionary, owner: String) -> bool:
	if not mf_is(f):
		return false
	var errs: Array = ctx.errs
	var kinds: Array = MF_FX_KINDS.filter(func(k): return f.has(k))
	if kinds.size() != 1:
		errs.append("%s：程序 fx 条目恰好写一种（%s），这里有 %d 种" % [q, " / ".join(MF_FX_KINDS), kinds.size()])
		return true
	var kk: String = kinds[0]
	for k in f:
		if k != kk and not k in MF_FX_COMMON:
			errs.append("%s.%s：程序 fx 条目不认识的字段" % [q, k])
	if kk in ["ghost", "mist", "side"] and owner != "summon":
		errs.append("%s.%s 只能写在召唤物种类的 fx 里" % [q, kk])
	var at := str(f.get("at", "center"))
	if not at in MF_AT:
		errs.append("%s.at 只能是 %s" % [q, " / ".join(MF_AT)])
	if f.has("cond"):
		if not (f.cond is String) or parse_cond(f.cond, ctx.base).has("err"):
			errs.append(q + ".cond 看不懂")
	_num(f, "n", q, ctx, false, 1.0, 32.0)
	_num(f, "every", q, ctx, false, 0.03, 60.0)
	if f.has("every") and owner in FX_INSTANT_OWNERS:
		errs.append(q + ".every 只能写在常驻积木 / 召唤物种类上")
	match kk:
		"pfx", "gfx":
			var t = f[kk]
			if not (t is Dictionary):
				errs.append("%s.%s 必须是粒子模板对象" % [q, kk])
			elif not str(t.get("kind", "")) in (MF_PFX_KINDS if kk == "pfx" else MF_GFX_KINDS):
				errs.append("%s.%s.kind 只能是 %s" % [q, kk, " / ".join(MF_PFX_KINDS if kk == "pfx" else MF_GFX_KINDS)])
			else:
				for k in t:   # 数值字段：数字或 [lo, hi]（g.vrng 区间随机）
					var v = t[k]
					if v is Array and v.size() == 2 and v.all(func(x): return x is int or x is float):
						if float(v[0]) > float(v[1]):
							errs.append("%s.%s.%s：[lo, hi] 要 lo ≤ hi" % [q, kk, k])
					elif k == "life":
						_num(t, "life", "%s.%s" % [q, kk], ctx, false, 0.02, 5.0)
		"sprite":
			var sv = f.sprite
			var nm: String = str(sv.get("name", "")) if sv is Dictionary else str(sv)
			if not nm.begins_with("fx_"):
				errs.append(q + ".sprite 必须是 V6_FRAMES 里的 fx_* 帧条（字符串，或 {name, fit, scale, rot…}）")
			if sv is Dictionary:
				for k in sv:
					if k != "name" and not k in MF_SPRITE_KEYS:
						errs.append("%s.sprite.%s：不认识的字段（只能是 name / %s）" % [q, k, " / ".join(MF_SPRITE_KEYS)])
		"text":
			if not (f.text is String or f.text is Dictionary):
				errs.append(q + ".text 必须是字符串或 {s, col, size}")
		"pause":
			_num(f, "pause", q, ctx, true, 0.0, 0.2)
	return true


## shape.support（不造成伤害的普攻：every 一拍、when 条件、出手帧执行 do）
static func _mf_support(atk: Dictionary, ctx: Dictionary) -> void:
	var errs: Array = ctx.errs
	for k in atk:
		if not k in ["shape", "every", "first", "when", "do", "_doc"]:
			errs.append("blocks.attack.%s：shape.support 只有 every / first / when / do" % k)
	_num(atk, "every", "blocks.attack", ctx, true, 0.1)
	_num(atk, "first", "blocks.attack", ctx, false, 0.0, 30.0)
	if atk.has("when") and (not (atk.when is String) or parse_cond(atk.when, ctx.base).has("err")):
		errs.append("blocks.attack.when 看不懂（条件串，§1.3）")
	_list(atk.get("do", []), "blocks.attack.do", "instant", ctx)
	_sm_exprs(atk, "blocks.attack", ctx)
