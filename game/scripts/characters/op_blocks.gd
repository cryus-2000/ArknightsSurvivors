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
const LOCAL_STATS := ["zone", "dmg", "heal", "interval", "area", "force", "force_lit", "atk"]   # area / force / force_lit：安洁莉娜段（落点范围 / 位移距离 / 灯光内位移）；atk：只乘普攻（精英化段，星熊反击架势）
## verb.buff_self 可写进 g.stats 的干员属性（作用域 op:<id>）
const OP_STATS := ["op_atk", "op_aspd", "op_range", "op_skill_power", "op_shots"]   # op_shots：能天使（docs/61 §14）
const AURA_STAT := {"atk": "op_atk", "aspd": "op_aspd", "skill_power": "op_skill_power", "range": "op_range"}
const COND_OPS := [">=", "<=", "==", ">", "<"]
## blocks.attack 能用的普攻形状（第三批追加：point_aoe 安洁莉娜、dash_line 德克萨斯、projectile 能天使）
const ATTACK_SHAPES := ["circle", "cone", "point_aoe", "dash_line", "projectile", "shell", "bolt", "thrust", "saw", "lantern", "umbrella", "hammer", "foxfire", "cannon", "bash"]   # shell / bolt：手写迁移段（艾雅法拉 / 逻各斯）；thrust：手写迁移段第 3 批（艾丽妮）


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
	var ec := el_parse_cond(s)   # 精英化段：buff:<key>
	if not ec.is_empty():
		return ec
	var hc := hw_parse_cond(s)   # 手写迁移段：timer:<key> / armed:<key>
	if not hc.is_empty():
		return hc
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
	if n is String and "$" in n:   # 数组里的 $ 表达式（手写迁移段：mult 数组 = 依次乘）
		return eval_expr(n, base)[1]
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
			if mc[0]:
				r = mc[1]
			elif str(c.k) == "buff":   # 精英化段：限时增益 buff:<key> 生效中
				r = el_buff_on(o, str(c.a))
			elif str(c.k) in ["timer", "armed"]:   # 手写迁移段
				r = hw_cond(o, c)
			else:
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
	if who.begins_with("stack:"):   # 手写迁移段：本干员 verb.stack 的层数
		return hw_stack_n(o, who.substr(6))
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
	var dmg: float
	if b.has("basis"):   # 手写迁移段：伤害 = 本次普攻 / 上一个形状 / 触发事件的伤害 × mult（追加打击按原伤害的百分比，同手写的 dmg × k）
		dmg = hw_basis(o, str(b.basis)) * mult
	else:
		dmg = o.base(str(b.get("atk_key", "atk")), 0.0) * mult * float(o.loc.dmg) * o._dmg_bonus()
		if b.get("power", false):
			dmg *= o.skill_power()
		dmg *= el_atk_mult(o)   # 精英化段：只乘普攻的局部倍率 atk（普攻出手时才生效；其余干员恒 1.0）
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
			if str(b.get("center", "")) == "path":   # 精英化段：沿上一次冲刺路径每 step 一处（德克萨斯余像·剑雨）
				el_path_circles(o, b)
				return []
			var c: Vector2 = shape_center(o, b, at)
			var r: float = shape_radius(o, b)
			if str(b.get("center", "")) == "front":   # 手写迁移段：锚击砸在身前（朝最近敌人转身）
				var fr: Array = hw_front(o, b, r)
				c = fr[0]
				fx_a = fr[1]
			if c == Vector2.INF:
				return []
			if b.has("only"):   # 精英化段：只打处于某些状态的敌人（安洁莉娜失重井）
				hits = el_area_only(o, b, c, r, dmg)
			elif b.has("band") or b.has("among"):   # 精英化第 5 批段：环带 / 只打上一次普攻命中的敌人（浊心斯卡蒂余音）
				hits = e5_area(o, b, c, r, dmg)
			else:
				hits = o.area_hit(src, c, r, dmg, kb, stun, tags, max_n)
			if b.get("ring", true):   # ring: false = 不画缺省地面环（fx 里自己画，§15.9）
				o.fx({"kind": "ring", "pos": c, "r": r, "r0": r * 0.55, "life": 0.32, "col": o.col(), "floor": true, "w": 2.0, "alpha": 0.6})
			fx_c = c
			fx_r = r
			hw_record(o, dmg, fx_a, r, c)   # 手写迁移段：记下这一下（basis prev / 普攻的 attack）
		"cone":
			var r2: float = shape_radius(o, b)
			var org: Vector2 = o.pos + hw_off(b)   # 手写迁移段：origin_off（判定原点相对脚底的偏移）；没写 = o.pos
			var ang: float
			if str(b.get("dir", "")) == "back":   # 手写迁移段：本次普攻的反方向（斯卡蒂天赋反手斩），不另找目标、不转身
				ang = float(o.hw.get("atk_ang", o.facing_angle())) + PI
			else:
				var ar: float = r2   # 找目标的半径：aim_r（× op_range × aim_mult，手写「普攻半径 + aim_pad」）缺省 = 本形状半径
				if b.has("aim_r"):
					ar = float(b.aim_r) * o.stat(&"op_range") * float(b.aim_mult) if b.has("aim_mult") else float(b.aim_r) * o.stat(&"op_range")
				var ts: Array = o.nearest_enemies(1, ar + float(b.get("aim_pad", 30.0)), o.pos)
				var a0: float = (ts[0].pos - o.pos).angle() if not ts.is_empty() else o.facing_angle()
				if not ts.is_empty() and b.has("face") and hw_face_ok(o, b.face):   # 手写迁移段：face（布尔或条件串）= 朝目标转身
					o.face_to(a0)
				ang = o.atk_angle(a0)
			var half: float = float(b.half) if b.has("half") else deg_to_rad(float(b.get("half_deg", 45.0)))
			hits = o.melee_hit(src, org, ang, half, r2, dmg, kb, stun, tags, max_n)
			if b.get("ring", true):
				o.fx({"kind": "ring", "pos": o.pos, "r": r2 * 0.6, "r0": 8.0, "life": 0.25, "col": o.col(), "floor": true, "w": 3.0})
			fx_c = o.pos
			fx_r = r2
			fx_a = ang
			hw_record(o, dmg, ang, r2, org)
		"dash_line":
			return tx_dash_start(o, b, dmg)   # 德克萨斯段：命中逐帧结算，这里只起冲
		"projectile":   # 能天使段：弹体自推进，命中在 exu_tick 里结算，这里返回空
			exu_fire(o, b)
	for s in b.get("on_hit", []):
		for i in hits.size():
			apply_status(o, hits[i], s, Vector2.INF, -1.0, 0.0, i)
	if b.has("fx") and fx_c != Vector2.INF:
		fx_play(o, b.fx, fx_c, fx_r, hits, fx_a)
	return hits


## 命中 / 力场里的状态（st.*，第三批合并时与安洁莉娜段的 status_one 统一）：stun / slow 精英时长减半、Boss 缺省不受（与原 apply_status 逐字节相同）。
## 一名敌人吃一条状态。c / ring / ring_w：within（离 c 不超过）与 where: ring（在环带 ±ring_w 内）的筛选。
## Boss：缺省不受；boss: true 也受（stun ×0.25 / slow 照常）；boss_only: true 只对 Boss
static func apply_status(o, e: Dictionary, s: Dictionary, c := Vector2.INF, ring := -1.0, ring_w := 0.0, idx := -1) -> void:
	if e.dead or not cond_true(o, s.get("cond", {})):
		return
	if s.has("within") and c != Vector2.INF and e.pos.distance_to(c) > float(s.within) + float(e.r) * 0.5:
		return
	if str(s.get("where", "")) == "ring" and (ring < 0.0 or absf(e.pos.distance_to(c) - ring) > ring_w):
		return
	if str(s.get("st", "")) == "seal":   # 召唤 / 封印段：Boss 有自己的规则（缩短 + 免疫），不走下面的「Boss 缺省不受」
		seal_apply(o, e, s)
		return
	if hw_on(o) and hw_status(o, e, s):   # 手写迁移段：点燃 / 易伤（Boss 也吃）
		return
	if e.boss and not (s.get("boss", false) or s.get("boss_only", false)):
		return
	if s.get("boss_only", false) and not e.boss:
		return
	if (s.has("first_only") or s.has("cd")) and not el_status_gate(o, s, idx):   # 精英化段：只对这次命中的第一个敌人 / 冷却
		return
	if s.has("fx"):   # 精英化段：状态自带画面（中心 = 这名敌人脚底，半径 = 敌人半径）
		fx_play(o, s.fx, e.pos, float(e.r), [e])
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
		"st.launch":   # 手写迁移段第 3 批：浮空（艾丽妮式：精英减半在里面算）
			h3_launch(o, e, float(s.dur), float(s.get("h", 26.0)))


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
		if str(b.get("center", "")).begins_with("summon:"):   # 精英化第 5 批段：以召唤物为心 = 那个召唤物自带区域的半径
			return e5_summon_zr(o, str(b.center).substr(7))
		return o.zone_r()
	if b.get("r_abs", false):   # 召唤物扩展段：r_abs = 半径不吃 op_range（凯尔希熔毁 130）
		return float(r) * float(b.r_mult) if b.has("r_mult") else float(r)
	if b.has("r_mult"):   # 手写迁移段：半径再乘 r_mult（斯卡蒂潮汐 ×1.4 这类，按手写的乘法顺序：r × op_range × r_mult）
		return float(r) * o.stat(&"op_range") * float(b.r_mult)
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
			"self":   # 手写迁移段
				ok = m == o
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
	var ctx := {"base": base, "srcs": srcs, "errs": errs, "custom": 0, "summons": blocks.get("summons", {}), "sprites": d.get("sprites", {}), "stat_defs": d.get("stat_defs", {})}
	for k in blocks:
		if not k in ["zone", "attack", "trait", "skills", "talent", "progression", "summons", "follow", "hit_fx", "look", "dmg_bonus", "_doc"]:
			errs.append("blocks.%s：不认识的段（只能是 zone / attack / trait / skills / talent / progression / summons / follow / hit_fx / look / dmg_bonus）" % k)
	_hw_top(blocks, ctx)   # 手写迁移段：follow / hit_fx / look
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
			_num(z, "ring", "blocks.zone", ctx, false, 0.0, 2.0)   # 区域边线透明度倍率（10-14 加，纯画面）
	var atk = blocks.get("attack", null)
	if atk is Dictionary and str(atk.get("shape", "")) == "support":   # 召唤物扩展段：不造成伤害的普攻（凯尔希的治疗）
		_mf_support(atk, ctx)
	elif not (atk is Dictionary) or not str(atk.get("shape", "")) in ATTACK_SHAPES:
		errs.append("blocks.attack 必须是一个伤害形状（%s）" % " / ".join(ATTACK_SHAPES.map(func(x): return "shape." + x)))
	else:
		_block(atk, "blocks.attack", "attack", ctx)
		_num(atk, "every", "blocks.attack", ctx, true, 0.1)
		_num(atk, "range", "blocks.attack", ctx, false)
		_hw_attack(atk, ctx)   # 手写迁移段：first / idle / anim / turn / combo / armed
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
			elif dv is Dictionary and dv.has("pulses"):   # dur.pulses（手写迁移段：连续喷发，_hw_skill 查）
				pass
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
				if not k in ["dur", "do", "fx", "aim", "status", "status_col"] + EXU_SKILL_KEYS + HW_SKILL_KEYS:
					errs.append("%s.%s：技能积木只有 dur / do / fx / aim / aim_r / status / status_col / attack_patch / end 这几个字段" % [p, k])
				elif k == "aim" and not (str(sb.aim) in ["leader", "nearest", "los", "range", "tether", "elite", "cluster"] or (str(sb.aim).begins_with("summon:") and ctx.summons is Dictionary and ctx.summons.has(str(sb.aim).substr(7)))):
					errs.append("%s.aim 只能是 leader / nearest / summon:<blocks.summons 里的种类>" % p)
				elif k == "attack_patch" and atk_shape == "point_aoe" and not (dv is Dictionary and dv.has("next_attacks")):
					errs.append("%s.attack_patch：落点弹普攻（shape.point_aoe）的 attack_patch 只能配 dur.next_n（{\"next_attacks\": N}）" % p)
			_num(sb, "aim_r", p, ctx, false, 1.0, 2000.0)
			if sb.has("fx"):
				_fx(sb.fx, p + ".fx", ctx, "cast")
			_list(sb.get("do", []), p + ".do", "skill", ctx)
			_exu_skill(sb, p, ctx, atk_shape)   # 能天使段：attack_patch（落点弹的由 _v_next_n 查）/ end
			_hw_skill(sb, p, ctx)   # 手写迁移段：cast: instant / dur.pulses + pulse
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
	if fam == "st":   # 精英化段：命中状态的 first_only / cd（任何 st.* 都能写）
		_el_st_common(b, p, ctx)
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
	if _el_block(b, p, kind, ctx, tag):   # 精英化段（docs/91 第 1 批）
		return
	if _hw_block(b, p, kind, ctx, tag):   # 手写迁移段（精英化第 2 批：逻各斯 / 艾雅法拉 / 斯卡蒂 / 乌尔比安）
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
			elif str(b.get("center", "")) == "path":   # 精英化段：沿上一次冲刺 / 残像路径
				_num(b, "step", p, ctx, true, 8.0, 400.0)
				_num(b, "delay", p, ctx, false, 0.0, 5.0)
				_num(b, "stagger", p, ctx, false, 0.0, 1.0)
			elif not str(b.get("center", "zone")) in ["zone", "self", "leader", "target", "front"]:
				errs.append(p + ".center 只能是 zone / self / leader / target / path / front / summon:<种类>")
			_e5_shape(b, p, ctx, tag)   # 精英化第 5 批段：band / among、center summon:<种类> + r: zone
			if b.has("only"):   # 精英化段：只打处于这些状态的敌人
				var ol = b.only
				if not (ol is Array) or ol.is_empty() or ol.any(func(x): return not str(x) in EL_ONLY):
					errs.append(p + ".only 必须是非空数组，取值 " + " / ".join(EL_ONLY))
				elif tag != "shape.circle":
					errs.append(p + ".only 只用于 shape.circle")
			_src(b, p, ctx, true)
			_list(b.get("on_hit", []), p + ".on_hit", "on_hit", ctx)
			_hw_shape_params(b, p, ctx, tag)   # 手写迁移段：basis / origin_off / aim_pad / face / dir / r_mult / ring
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
			if not (b.has("add") or b.has("per_sec") or b.has("loss_mult") or b.has("decay_mult") or b.has("radius_mult")):   # decay_mult / radius_mult：第 3 批（流明「沛霖」）
				errs.append(p + "：verb.lamp 要写 add / per_sec / loss_mult / decay_mult / radius_mult 之一")
			if b.has("add") and (b.has("per_sec") or b.has("loss_mult")):
				errs.append(p + "：verb.lamp 的 add（瞬时）不能和 per_sec / loss_mult（常驻）写在同一块")
			for k in ["add", "per_sec", "loss_mult"]:
				_num(b, k, p, ctx, false)
		"verb.buff_self":
			var st := str(b.get("stat", ""))
			var own: bool = ctx.get("stat_defs", {}) is Dictionary and ctx.stat_defs.has(st)   # 第 3 批：干员 JSON stat_defs 里的专属属性（作用域 op:<id>）
			if not (st in LOCAL_STATS or st in OP_STATS or own):
				errs.append("%s.stat「%s」只能是 %s 或本干员 stat_defs 里的专属属性" % [p, st, " / ".join(LOCAL_STATS + OP_STATS)])
			if not str(b.get("op", "")) in ["add", "mult"] and not (own and str(b.get("op", "")) == "flat"):
				errs.append(p + ".op 只能是 add / mult（专属属性还可 flat）")
			_num(b, "value", p, ctx, true)
		"verb.mode":
			if not (b.has("dmg_mult") or b.has("zone_mult") or b.has("interval_mult") or b.has("no_attack")):
				errs.append(p + "：verb.mode 至少写 dmg_mult / zone_mult / interval_mult / no_attack 之一")
			_num(b, "dmg_mult", p, ctx, false, 0.0, 20.0)
			_num(b, "zone_mult", p, ctx, false, 0.0)
			_num(b, "interval_mult", p, ctx, false, 0.05)
		"verb.sp_team":
			_num(b, "pct", p, ctx, true, 0.0, 1.0)
			_num(b, "motes", p, ctx, false, 0.0, 6.0)   # 第 4 批：金色技力粒子飞向每名队友（画面）；power：× 技能强度
		"aura.atk", "aura.aspd", "aura.skill_power", "aura.range":
			_num(b, "value", p, ctx, true)
			var sc := str(b.get("scope", ""))
			if not (sc in ["squad", "others", "in_zone", "leader", "self"] or ((sc.begins_with("faction:") or sc.begins_with("class:")) and sc.find(":") < sc.length() - 1)):
				errs.append("%s.scope「%s」只能是 squad / others / in_zone / leader / self / faction:<阵营> / class:<职业>" % [p, sc])
			if b.has("per"):
				var pe := str(b.per)
				if not ((pe.begins_with("faction:") or pe.begins_with("class:") or pe.begins_with("stack:")) and pe.find(":") < pe.length() - 1):
					errs.append("%s.per「%s」只能是 faction:<阵营> / class:<职业> / stack:<层数 key>" % [p, pe])
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
			# 精英化段：replace = 这一次普攻整个换成 do（不再出普攻形状）；anim = 这一次起手播的帧条（sprites 里的键，缺图退回 attack）
			if b.has("replace") and not (b.replace is bool):
				errs.append(p + ".replace 只能是 true / false")
			if b.has("anim"):
				if not b.get("replace", false):
					errs.append(p + ".anim 只配 replace: true（换掉的那一次普攻播别的帧条）")
				elif not (ctx.sprites is Dictionary and ctx.sprites.has(str(b.anim))):
					errs.append("%s.anim「%s」不是 sprites 里的帧条键" % [p, str(b.anim)])
			if b.get("replace", false) and b.has("delay") and _val(b.delay, ctx.base) > 0.0:
				errs.append(p + "：replace 的 every_n 不写 delay（就在这一次出手帧执行）")
		"trig.tick":
			_num(b, "every", p, ctx, true, 0.1)
			_list(b.get("do", []), p + ".do", "instant", ctx)
			if b.has("countdown") and not (b.countdown is bool):   # 手写迁移段：倒计时写法（生效当帧起算，到点重置为 every）
				errs.append(p + ".countdown 只能是 true / false")
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
	"hold", "fade", "if_tex", "ease", "grow", "grow0", "grow_to", "wake", "xfade",
	"delay", "stay", "once", "face_x", "flash", "along", "play"]   # play：精英化第 5 批段（扩散缓动的帧号按 fps 播）；精英化段（docs/91 第 1 批）：延迟起播、末帧停留、区域里不循环、偏移随朝向、开火时提亮
## ground：紧贴地砖（溟痕 / Boss 地面预警 / 掉落之下），只给常驻跟随帧条（hold）用，大片地面特效不盖住危险提示（10-12 加）
const FX_LAYERS := ["floor", "over", "add", "behind", "front", "ground"]
## 常驻跟随帧条（hold: true，10-12 加）：积木生效期间循环、跟着区域中心 / 半径走，缺省淡入淡出秒数（条目 fade 可改）
const FX_HOLD_FADE := 0.3
const FX_HOLD_LAYERS := ["ground", "floor", "add", "over"]   # over：画在人物之上（_draw_skill_over，精英化段：能天使祝福光环挂在队友头顶）
## 贴身层：画在干员本体的后面 / 前面（draw_body 前后），积木生效期间循环，帧号 = floor(生效秒数 × fps) % 帧数，退出时 FX_BODY_FADE 秒淡出
const FX_BODY := ["behind", "front"]
const FX_BODY_FADE := 0.15
## 放大上限（每个 1x 美术像素至多几个世界像素）：同 render/vfx.gd FX_SCALE_MAX，免得颗粒比人物粗太多；条目可用 max_scale 改
const FX_SCALE_MAX := 3.2
const FX_AT := ["center", "self", "leader", "zone", "hits", "orbit", "members", "mate"]   # members：光环的受益者（hold）；mate：出手的那名队友（trig.on_mate_attack）
## 只播一次的 fx 宿主（瞬时积木 / 技能发动 / 触发积木）：不能写 every、贴身层、漩涡（§8 第 9 条）。第三批新积木追加在这里
const FX_INSTANT_OWNERS := ["shape.circle", "shape.cone", "cast", "verb.sp_team",
	"shape.line", "verb.displace", "verb.field", "verb.negate_next", "trig.on_hurt", "trig.on_negate", "verb.summon", "verb.shield", "verb.guard",
	"st.stun", "st.slow", "st.airborne", "st.weightless", "st.pause", "shape.boomerang", "verb.summon_cmd", "trig.on_mate_attack"]   # 精英化段（docs/91 第 1 批）
## 能写 at = hits 的宿主（带命中列表的伤害形状）
const FX_HITS_OWNERS := ["shape.circle", "shape.cone", "shape.line"]
## 自己在合适的位置播 fx 的积木：data_operator._exec_list 不再按区域中心替它们播
const FX_SELF_PLAY := ["shape.circle", "shape.cone", "shape.line", "verb.displace", "verb.field", "verb.negate_next", "verb.summon", "verb.shield", "verb.heal", "verb.guard",
	"shape.boomerang", "verb.summon_cmd"]
const ArtS = preload("res://scripts/art.gd")


## 瞬时播放：c / r 是出手形状的中心与半径（技能发动、常驻光环时是区域中心与半径），hits 是本次命中的敌人，ang 是锥形的朝向。
## 带 every 的条目（常驻定时播）和 at = orbit 的条目（绕行体常驻贴图）这里跳过
static func fx_play(o, entries, c: Vector2, r: float, hits: Array = [], ang := 0.0) -> void:
	if not (entries is Array):
		return
	for f in entries:
		if hw_fx_is(f):   # 手写迁移段的程序条目（blade 刀光；常驻的 aura_ring / outline 在画的时候按积木生效画）
			if float(f.get("every", 0.0)) <= 0.0 and not fx_is_hold(f) and fx_on(o, f):
				hw_fx_spawn(o, f, {"c": c, "r": r, "hits": hits, "ang": ang})
			continue
		if mf_is(f):   # 召唤物扩展段的程序条目
			if float(f.get("every", 0.0)) <= 0.0 and fx_on(o, f):
				mf_fx_spawn(o, f, {"c": c, "r": r, "hits": hits, "ang": ang})
			continue
		if not (f is Dictionary) or float(f.get("every", 0.0)) > 0.0 or str(f.get("at", "center")) == "orbit" or fx_is_hold(f):
			continue
		if fx_on_spawn(o, f):
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
			if fx_on_spawn(o, f):
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
	var loop: bool = f.has("life") and not f.get("once", false)
	var life: float = float(f.life) if loop else frames / fps
	if f.has("stay"):   # 精英化段：一次性帧条播完停在末帧，共 stay 秒（钉剑插在敌人身上）
		life = maxf(life, float(f.stay))
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
	if f.get("face_x", false):
		off.x *= float(o.face)
	if f.has("along"):   # 精英化段：沿出手方向往外放 along × 半径（锥形斩的刀光放在身前）
		off += Vector2.from_angle(ang) * r * float(f.along)
	var dly: float = float(f.get("delay", 0.0))   # 精英化段：delay 秒后才起播（画面计时，不进玩法）
	var rot: float = (ang if f.get("rot", false) else 0.0) + deg_to_rad(float(f.get("ang", 0.0)))
	var layer: String = str(f.get("layer", "over"))
	var spread: float = float(f.get("spread", 0.0)) * r
	var rise: float = float(f.get("rise", 0.0))
	var ease: String = str(f.get("ease", ""))
	var grow: float = float(f.get("grow", FX_GROW))
	if ease != "" and str(f.get("grow_to", "")) == "zone" and o.has_method("zone_c"):
		pts = [o.zone_c()]   # grow_to = zone：从区域中心扩到区域半径（画的时候每帧跟着区域中心 / 半径走）
	var sumk: String = str(f.get("grow_to", "")).substr(7) if ease != "" and str(f.get("grow_to", "")).begins_with("summon:") else ""
	if sumk != "":   # 精英化第 5 批段：grow_to = summon:<种类>，从那个召唤物扩到它的区域半径（画的时候每帧跟着它走）
		var sp := e5_summon(o, sumk)
		if sp.is_empty():
			return
		pts = [sp.pos]
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
			if dly > 0.0:
				px["life"] = life + dly
				px["dly"] = dly
			if rise != 0.0:
				px["vel"] = Vector2(0, -rise)
			if ease != "":   # 扩散缓动（§5.6 ease / grow / grow_to / wake，10-13 加）：半径在画的时候按经过时间算，见 fx_draw_grow
				px["life"] = grow
				px["grow"] = grow
				px["ease"] = ease
				px["g0"] = float(f.get("grow0", FX_GROW0))
				px["R"] = r * float(f.get("scale", 1.0))
				px["zmul"] = float(f.get("scale", 1.0))
				px["zone"] = str(f.get("grow_to", "")) == "zone"
				if sumk != "":
					px["sumk"] = sumk
				if str(f.get("play", "")) == "fps":
					px["pfps"] = true
				px["off"] = off
				px["maxs"] = float(f.get("max_scale", FX_SCALE_MAX))
				px["src"] = o
				if f.get("wake", null) is Dictionary:
					px["wake"] = f.wake
			if float(f.get("xfade", 0.0)) > 0.0:
				px["xe"] = f   # 交叉淡入淡出：画的时候乘条目 cond 的平滑权重（fx_xw）
				px["src"] = o
			o.fx(px)


## 画一条 strip 粒子（data_operator._draw_pfx / draw_fx_add 调）。dim：整体透明度（fx_dim）
static func fx_draw(ci, g, f: Dictionary, dim: float) -> void:
	if f.has("grow"):
		fx_draw_grow(ci, g, f, dim)
		return
	if f.has("xe"):
		dim *= fx_xw(f.src, f.xe)
		if dim <= 0.004:
			return
	var el: float = float(f.max) - float(f.life) - float(f.get("dly", 0.0))
	if el < 0.0:
		return   # 精英化段：delay 还没到
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


# ---------------------------------------------------------------- 扩散缓动 / 交叉淡入淡出 / 余波环（docs/61 §5.6，10-13 加；纯画面）
## 用户 10-13「浊心斯卡蒂的声浪的转变是不是也有点僵硬」：小帧条整条放大 4 倍、按灯火硬切两套、扩散匀速且够不到歌域边。
## ease：半径从 grow0 × R 按缓动曲线扩到 R（grow 秒），帧号跟着扩散进度走、每帧按这一帧自身的半径缩放（帧条里的圈不论画多大都正好落在当前半径上）；
## 帧条只作纹理层：随扩散渐淡，放大超过 max_scale 后按 (max_scale / 倍率)² 再淡（颗粒粗的大圈交给程序余波环）；
## wake：程序余波环（顶点色软边环带，合批提交），领头一道正好在当前半径、后面几道各晚 lag 秒，外缘随扩散渐淡。
## xfade：同一组按 cond 二选一的条目（灯火明 / 暗）不再硬切：两条都生成，透明度乘各自 cond 的平滑权重（xfade 秒从 0 到 1）。
const FX_GROW := 0.65        # 扩散时长缺省（秒）
const FX_GROW0 := 0.12       # 起始半径比例缺省
const FX_EASES := ["out", "out2", "linear"]
const FX_WAKE_DEF := {"n": 2, "w": 10.0, "a": 0.5, "lag": 0.09, "sy": 0.55, "col": null}
const FX_WAKE_LIM := {"n": [0, 4], "w": [1.0, 60.0], "a": [0.0, 1.0], "lag": [0.0, 0.5], "sy": [0.1, 1.0]}
static var _fr_r := {}       # 帧条名 → 每帧自身半径（1x 像素，按不透明像素的横向范围量一次缓存）


## 缓动：out = 三次方先快后慢（缺省），out2 = 二次方，linear = 匀速
static func fx_ease(kind: String, t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	match kind:
		"out2":
			return 1.0 - (1.0 - t) * (1.0 - t)
		"linear":
			return t
	return 1.0 - pow(1.0 - t, 3.0)


## 帧条第 fr 帧自身的半径（1x 像素）：不透明像素离帧中心的最大横向距离；量不到（压缩贴图读不出图）时按帧宽一半
static func fx_frame_r(g, name: String, frames: int, fr: int) -> float:
	if not _fr_r.has(name):
		var tx: Texture2D = g.tex.get(name)
		var rs: Array = []
		if tx != null:
			var h: float = ArtS.hires_of(tx)
			var fw: int = tx.get_width() / frames
			var img: Image = tx.get_image()
			if img != null and img.is_compressed():
				img = null
			for k in frames:
				var r := fw / 2.0
				if img != null:
					var mn := fw
					var mx := -1
					for x in fw:
						for y in range(0, img.get_height(), 1):
							if img.get_pixel(k * fw + x, y).a > 0.1:
								mn = mini(mn, x)
								mx = maxi(mx, x)
								break
					if mx >= mn:
						r = maxf(fw / 2.0 - mn, mx + 1 - fw / 2.0)
				rs.append(maxf(1.0, r) / h)
		_fr_r[name] = rs
	var a: Array = _fr_r[name]
	return float(a[fr]) if fr < a.size() else 0.0


## 交叉淡入淡出权重：条目 f 的 cond 此刻为真 → 1，假 → 0，按 xfade 秒线性靠拢（只看 g.t，画面状态存在干员的 meta 里，不碰玩法）。
## 同 strip + cond + if_tex 的条目共用一个权重（普攻与回声同一档灯火同进同出）
static func fx_xw(o, f: Dictionary) -> float:
	if o == null or not is_instance_valid(o):
		return 1.0
	var xf: float = float(f.get("xfade", 0.0))
	var tgt: float = 1.0 if fx_on(o, f) else 0.0
	if xf <= 0.0:
		return tgt
	var m: Dictionary = o.get_meta("fx_xw") if o.has_meta("fx_xw") else {}
	if not o.has_meta("fx_xw"):
		o.set_meta("fx_xw", m)
	var key := "%s|%s|%s" % [f.get("strip", ""), f.get("cond", ""), f.get("if_tex", "")]
	var t: float = float(o.g.t)
	if not m.has(key):
		m[key] = [tgt, t]
		return tgt
	var v: Array = m[key]
	var w: float = move_toward(float(v[0]), tgt, maxf(0.0, t - float(v[1])) / xf)
	m[key] = [w, t]
	return w


## 生成时的取舍：带 xfade 的条目只看 if_tex（cond 交给画的时候的权重），并先把权重推到此刻；其余同 fx_on
static func fx_on_spawn(o, f: Dictionary) -> bool:
	if float(f.get("xfade", 0.0)) <= 0.0 or not f.has("cond"):
		return fx_on(o, f)
	var it = f.get("if_tex", "")
	if it is String and it != "":
		var neg: bool = it.begins_with("!")
		if (o.g.tex.get(it.substr(1) if neg else it) != null) == neg:
			return false
	fx_xw(o, f)   # 先把权重推到此刻
	return true   # 两档都生成：扩散途中跨阈值时同一圈声浪也能平滑换图（权重为 0 的那条画的时候直接跳过）


## 扩散缓动粒子（fx_spawn 写了 grow）：帧条纹理层 + 程序余波环
static func fx_draw_grow(ci, g, f: Dictionary, dim: float) -> void:
	var o = f.get("src")
	var el: float = float(f.max) - float(f.life)
	var T: float = maxf(0.05, float(f.grow))
	var t: float = clampf(el / T, 0.0, 1.0)
	var a: float = dim * clampf(el / 0.06, 0.0, 1.0)
	if f.has("xe"):
		a *= fx_xw(o, f.xe)
	if a <= 0.004:
		return
	var c: Vector2 = f.pos
	var R: float = float(f.R)
	if f.zone and o != null and is_instance_valid(o) and o.has_method("zone_c"):
		var zc: Vector2 = o.zone_c()
		if zc != Vector2.INF:
			c = zc + f.off
			R = float(o.zr) * float(f.zmul)
	elif f.has("sumk") and o != null and is_instance_valid(o):   # 精英化第 5 批段：跟着召唤物与它的区域半径走（召唤物没了就停在最后的位置）
		var sp := e5_summon(o, str(f.sumk))
		if not sp.is_empty():
			c = sp.pos + f.off
			R = float(sp.get("zr", R)) * float(f.zmul)
	var e: float = fx_ease(str(f.ease), t)
	var g0: float = float(f.g0)
	var rad: float = R * lerpf(g0, 1.0, e)
	# 纹理层：帧号跟扩散进度走（帧 0 多是起爆小点，帧数 ≥ 3 时从帧 1 起），且不选比原尺寸（g.PX）还要放大的小帧——
	# 当前半径够大时直接跳到自身半径 × PX ≤ 当前半径的最后一帧；每帧按自身半径缩放到当前半径
	var frames: int = int(f.fr)
	var fr: int = clampi(int(e * frames), 1 if frames >= 3 else 0, frames - 1)
	if f.get("pfps", false):   # 精英化第 5 批段：play = fps，帧号按帧条自己的 fps 播（回声环一帧比一帧疏，不跳帧）
		fr = mini(int(el * float(f.fps)), frames - 1)
	else:
		for k in range(frames - 1, fr, -1):
			if fx_frame_r(g, str(f.name), frames, k) * g.PX <= rad:
				fr = k
				break
	var rf: float = fx_frame_r(g, str(f.name), frames, fr)
	if rf > 0.0:
		var sc: float = rad / rf
		var ta: float = a * pow(1.0 - t, 1.3)
		var mxs: float = float(f.maxs)
		if sc > mxs:
			ta *= pow(mxs / sc, 2.0)
		if ta > 0.004:
			fx_frame(ci, g, str(f.name), frames, fr, c, sc, Color(f.col.r, f.col.g, f.col.b, f.col.a * ta), f.anc, float(f.ang))
	if f.has("wake"):
		fx_wake(ci, f.wake, c, R, g0, str(f.ease), el, T, a, f.col)


## 程序余波环：n 道软边环带（透视椭圆 y × sy），第 i 道晚 i × lag 秒起步、同一缓动扩到 R；环带宽 w（随扩散略展宽），
## 透明度 a × (1 - 进度)^1.4 × 越往后越淡；颜色 col（缺省取条目 tint 的 rgb）。全部顶点色三角形攒成一组：合批画布走 add_tris，否则直接提交
static func fx_wake(ci, wk: Dictionary, c: Vector2, R: float, g0: float, ease: String, el: float, T: float, a: float, tint: Color) -> void:
	var n: int = int(wk.get("n", FX_WAKE_DEF.n))
	var w: float = float(wk.get("w", FX_WAKE_DEF.w))
	var wa: float = float(wk.get("a", FX_WAKE_DEF.a)) * a
	var lag: float = float(wk.get("lag", FX_WAKE_DEF.lag))
	var sy: float = float(wk.get("sy", FX_WAKE_DEF.sy))
	var cv = wk.get("col", null)
	var col := Color(tint.r, tint.g, tint.b)
	if cv is Array and cv.size() >= 3:
		col = Color(float(cv[0]), float(cv[1]), float(cv[2]))
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var seg: int = clampi(int(R / 5.0), 32, 72)
	for i in n:
		var ti: float = clampf((el - lag * i) / T, 0.0, 1.0)
		if ti <= 0.0:
			continue
		var ri: float = R * lerpf(g0, 1.0, fx_ease(ease, ti))
		var wi: float = w * (0.7 + 0.6 * ti) * (1.0 - 0.2 * i)
		var ai: float = wa * pow(1.0 - ti, 1.4) * (1.0 - 0.3 * i) * clampf((el - lag * i) / 0.05, 0.0, 1.0)
		if ai <= 0.004:
			continue
		var cin := Color(col.r, col.g, col.b, 0.0)
		var cpk := Color(minf(col.r * 1.15, 1.0), minf(col.g * 1.1, 1.0), minf(col.b * 1.1, 1.0), ai)
		_wake_band(pts, cols, idx, c, maxf(0.0, ri - wi), ri, cin, cpk, sy, seg)        # 内侧拖尾：透明 → 峰值
		_wake_band(pts, cols, idx, c, ri, ri + wi * 0.35, cpk, cin, sy, seg)             # 外缘：峰值 → 透明（窄，前沿清楚）
	if idx.is_empty():
		return
	if ci != null and ci.has_method("add_tris"):
		ci.add_tris(pts, cols, idx)
	else:
		RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), idx, pts, cols)


static func _wake_band(pts: PackedVector2Array, cols: PackedColorArray, idx: PackedInt32Array, c: Vector2, r0: float, r1: float, c0: Color, c1: Color, sy: float, seg: int) -> void:
	var base: int = pts.size()
	for q in seg:
		var d := Vector2.from_angle(q * TAU / seg)
		pts.append(c + Vector2(d.x * r0, d.y * r0 * sy))
		pts.append(c + Vector2(d.x * r1, d.y * r1 * sy))
		cols.append(c0)
		cols.append(c1)
	for q in seg:
		var a0: int = base + q * 2
		var a1: int = base + ((q + 1) % seg) * 2
		idx.append_array([a0, a0 + 1, a1 + 1, a0, a1 + 1, a1])


## 常驻跟随条目：贴身层（behind / front）、程序漩涡（vortex）或常驻跟随帧条（hold），积木生效期间一直画、退出淡出
static func fx_is_hold(f) -> bool:
	return f is Dictionary and (str(f.get("layer", "")) in FX_BODY or f.has("vortex") or _hold(f) or f.has("aura_ring") or f.has("outline"))


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
		if str(f.get("flash", "")) == "fire":   # 精英化段：本干员每次普攻出手提亮一下（0.25 秒衰减）
			var k: float = clampf(1.0 - (float(g.t) - float(o.el.get("fire_t", -99.0))) / 0.25, 0.0, 1.0)
			col = Color(col.r * (1.0 + 0.9 * k), col.g * (1.0 + 0.9 * k), col.b * (1.0 + 0.6 * k), minf(1.0, col.a * (1.0 + 0.5 * k)))
		var cs: Array = [c_zone]
		match str(f.get("at", "zone")):
			"self":
				cs = [o.pos]
			"leader":
				cs = [g.ppos]
			"members":   # 精英化段：光环（aura.*）的受益者，每人头顶一个
				cs = []
				for m in aura_members(o, str(e.b.get("scope", "others"))):
					cs.append(m.pos)
		var ov = f.get("off", [])
		var off: Vector2 = Vector2(float(ov[0]), float(ov[1])) if ov is Array and ov.size() == 2 else Vector2.ZERO
		if f.get("face_x", false):
			off.x *= float(o.face)
		var sc: float = float(f.get("scale", 1.0))
		var fit: float = float(f.get("fit", 0.0))
		sc *= r_zone / fit if fit > 0.0 and r_zone > 0.0 else g.PX
		sc = minf(sc, float(f.get("max_scale", FX_SCALE_MAX)))
		var av = f.get("anchor", [])
		var anc: Vector2 = Vector2(float(av[0]), float(av[1])) if av is Array and av.size() == 2 else Vector2(-1, -1)
		for c in cs:
			if c == Vector2.INF:
				continue
			fx_frame(ci, g, name, frames, int(floor(float(e.el) * float(spec[1]))) % frames, c + off, sc, col, anc, deg_to_rad(float(f.get("ang", 0.0))))


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
		if f.get("face_x", false):   # 精英化段：偏移随朝向（星熊盾在身前）
			off.x *= float(o.face)
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
		if _hw_fx_check(f, q, ctx, owner):   # 手写迁移段的程序条目（blade / aura_ring / outline）
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
				if not at in ["center", "zone", "self", "leader", "members"]:
					errs.append(q + ".at：hold 帧条只能是 zone / self / leader / members")
				if at == "members" and not owner.begins_with("aura."):
					errs.append(q + ".at = members（光环受益者）只能挂在 aura.* 上")
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
		# 扩散缓动 ease / grow / grow0 / grow_to / wake、交叉淡入淡出 xfade（10-13 加，§5.6）
		if f.has("ease") or f.has("grow") or f.has("grow0") or f.has("grow_to") or f.has("wake"):
			if not str(f.get("ease", "")) in FX_EASES:
				errs.append("%s.ease 只能是 %s（grow / grow0 / grow_to / wake 要配 ease）" % [q, " / ".join(FX_EASES)])
			if fx_is_hold(f) or f.has("life") or f.has("vortex"):
				errs.append(q + ".ease：扩散缓动只给一次性帧条用（不写 hold / life / vortex，不放贴身层）")
			if f.has("grow_to") and str(f.grow_to) != "zone" and not e5_grow_to_ok(f.grow_to, ctx):
				errs.append(q + ".grow_to 只能是 zone（扩到区域半径、跟着区域走）/ summon:<带 zone 的召唤物种类>")
			if f.has("play") and str(f.play) != "fps":
				errs.append(q + ".play 只能是 fps（帧号按帧条 fps 播）")
			if f.has("wake"):
				var wk = f.wake
				if not (wk is Dictionary):
					errs.append(q + ".wake 必须是对象 {n, w, a, lag, sy, col}")
				else:
					for k in wk:
						if k == "col":
							var cv = wk.col
							if not (cv is Array) or cv.size() != 3 or cv.any(func(x): return not (x is int or x is float)):
								errs.append(q + ".wake.col 必须是 3 个数字 [r, g, b]")
						elif not FX_WAKE_LIM.has(k):
							errs.append("%s.wake.%s：不认识的参数（只能是 n / w / a / lag / sy / col）" % [q, k])
						elif not (wk[k] is int or wk[k] is float) or float(wk[k]) < float(FX_WAKE_LIM[k][0]) or float(wk[k]) > float(FX_WAKE_LIM[k][1]):
							errs.append("%s.wake.%s 超出范围（%s–%s）" % [q, k, str(FX_WAKE_LIM[k][0]), str(FX_WAKE_LIM[k][1])])
		if f.has("play") and not f.has("ease"):   # 精英化第 5 批段
			errs.append(q + ".play 要配 ease（只用于扩散缓动条目）")
		if f.has("xfade"):
			if fx_is_hold(f):
				errs.append(q + ".xfade 只给一次性帧条用（常驻条目的 cond 切换另有淡入淡出）")
			if not f.has("cond"):
				errs.append(q + ".xfade 要配 cond（按 cond 的真假交叉淡入淡出）")
		_num(f, "grow", q, ctx, false, 0.1, 3.0)
		_num(f, "grow0", q, ctx, false, 0.0, 0.95)
		_num(f, "xfade", q, ctx, false, 0.0, 3.0)
		_num(f, "fit", q, ctx, false, 1.0, 512.0)
		_num(f, "scale", q, ctx, false, 0.05, 8.0)
		_num(f, "max_scale", q, ctx, false, 0.5, 16.0)
		_num(f, "n", q, ctx, false, 1.0, 16.0)
		_num(f, "spread", q, ctx, false, 0.0, 1.5)
		_num(f, "rise", q, ctx, false, -400.0, 400.0)
		_num(f, "life", q, ctx, false, 0.05, 5.0)
		_num(f, "every", q, ctx, false, 0.05, 60.0)
		_num(f, "ang", q, ctx, false)
		# 精英化段（docs/91 第 1 批）：delay / stay / once / face_x / flash；at = members / mate 的宿主
		_num(f, "delay", q, ctx, false, 0.0, 5.0)
		_num(f, "stay", q, ctx, false, 0.05, 5.0)
		_num(f, "along", q, ctx, false, -2.0, 2.0)
		for k in ["once", "face_x"]:
			if f.has(k) and not (f[k] is bool):
				errs.append("%s.%s 只能是 true / false" % [q, k])
		if (f.has("delay") or f.has("stay")) and fx_is_hold(f):
			errs.append(q + "：delay / stay 只给一次性帧条用")
		if f.has("stay") and f.has("life") and not f.get("once", false):
			errs.append(q + ".stay：循环帧条（写了 life）不停在末帧")
		if f.has("flash") and (str(f.flash) != "fire" or not _hold(f)):
			errs.append(q + ".flash 只能是 fire，且只给常驻跟随帧条（hold）用")
		if at == "mate" and owner != "trig.on_mate_attack":
			errs.append(q + ".at = mate 只能挂在 trig.on_mate_attack 上")
		if at == "members" and not _hold(f):
			errs.append(q + ".at = members 只给常驻跟随帧条（hold）用")
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
	dmg *= el_atk_mult(o)   # 精英化段：普攻（含 swap_attack 换上的直线斩）吃局部倍率 atk
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
	var r: float
	if str(b.get("r", "")) == "attack":   # 精英化第 2 批段：按当前普攻半径（乌尔比安收链：锚击外圈）
		r = shape_radius(o, o.cur_attack()) * float(b.get("r_mult", 1.0)) * float(o.loc.get("area", 1.0))
	else:
		r = float(b.get("r", 0.0)) * o.stat(&"op_range") * float(o.loc.get("area", 1.0))
	var r_in := -1.0
	if b.has("r_in"):
		r_in = h3_attack_r(o, o.cur_attack()) if str(b.r_in) == "attack" else float(b.r_in) * o.stat(&"op_range")   # h3_attack_r：第 3 批的普攻形状按各自半径，其余同 shape_radius
	var by_dist: bool = b.has("dist")
	var kb: float = float(b.get("kb", 0.0))
	var sc: float = float(o.shot.get("force_mult", 1.0)) if by_dist else 1.0
	var hits: Array = []
	for j in o.query_ids(c, r + 40.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or e.pos.distance_to(c) > r + float(e.r):
			continue
		if r_in >= 0.0 and e.pos.distance_to(c) <= r_in + float(e.r):
			continue   # r_in 内的（这一下已经打到的）不拉
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
				if str(b.get("r", "")) != "attack":
					_num(b, "r", p, ctx, true, 1.0, 800.0)
				_num(b, "r_mult", p, ctx, false, 0.05, 10.0)
				if b.has("r_in") and str(b.r_in) != "attack":
					_num(b, "r_in", p, ctx, false, 0.0, 800.0)
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
				_num(b, "cap", p, ctx, false, 1.0, 16.0)   # 精英化段：这块积木同时最多几处（超出时最早的先消失；安洁莉娜失重井 3 口）
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
			if not (b.has("len_add") or b.has("len_mult") or b.has("w_add") or b.has("w_mult") or b.has("on_hit")):
				errs.append(p + "：verb.dash_mod 至少写 len_add / len_mult / w_add / w_mult / on_hit 之一")
			for k in ["len_add", "w_add"]:
				_num(b, k, p, ctx, false, -0.9, 3.0)
			for k in ["len_mult", "w_mult"]:
				_num(b, k, p, ctx, false, 0.1, 4.0)
			_list(b.get("on_hit", []), p + ".on_hit", "on_hit", ctx)   # 精英化段：生效期间每次冲刺扫到的敌人追加的状态（德克萨斯钉剑 first_only）
		"verb.trail":
			_num(b, "life", p, ctx, true, 0.05, 5.0)
			_num(b, "mult", p, ctx, true, 0.0, 20.0)
			_src(b, p, ctx, true)
			_list(b.get("on_hit", []), p + ".on_hit", "on_hit", ctx)
			if b.has("on_expire"):   # 精英化段：残像消散时执行（do 里的 center: path 沿这道残像）
				_list(b.on_expire, p + ".on_expire", "instant", ctx)
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
		var gone: Array = []
		for tr in trails:
			tr.life -= dt
			_tx_sweep(o, tr.from, tr.to, tr.w, tr.hit, tr.dmg, tr.b)
			if tr.life <= 0.0 and tr.b.has("on_expire"):
				gone.append(tr)
		tx["trails"] = trails.filter(func(tr): return tr.life > 0.0)
		for tr in gone:   # 精英化段：残像消散 → on_expire（路径 = 这道残像）
			tx["ctx"] = {"from": tr.from, "to": tr.to, "dir": (tr.to - tr.from).normalized(), "w": tr.w, "n": 0, "src": ""}
			o._exec_list(tr.b.on_expire, tr.to)
	# 冲刺
	if not tx.has("dash") or o.pos == Vector2.INF:
		return false
	var d: Dictionary = tx.dash
	d.t += dt
	var k2: float = clampf(d.t / maxf(0.01, d.dur), 0.0, 1.0)
	if not d.ride:
		o.pos = (d.from as Vector2).lerp(d.to, 1.0 - (1.0 - k2) * (1.0 - k2))   # 先快后慢
	if d.t <= d.dur + dt * 0.5:
		_tx_sweep(o, d.last, o.pos, d.w, d.hit, d.dmg, d.b, true)
		d.last = o.pos
	if d.t >= d.dur + d.hold:
		_tx_dash_end(o)
		return false
	return true


## 扫一段线段：线段两侧 w/2（+ 敌人半径）内、hit 里没有的敌人各吃一次 dmg（对精英 / Boss 乘 vs_elite）与 on_hit 状态
static func _tx_sweep(o, a: Vector2, c: Vector2, w: float, hit: Dictionary, dmg: float, b: Dictionary, dash := false) -> void:
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
		if dash:   # 精英化段：verb.dash_mod 的 on_hit（idx = 这次冲刺扫到的第几个，first_only 只给第 0 个）
			for s in o.tx.get("on_hit", []):
				apply_status(o, e, s, Vector2.INF, -1.0, 0.0, hit.size() - 1)
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
	var oh: Array = []
	for b in act:
		match str(b.get("_tag", "")):
			"verb.dash_mod":
				la += float(b.get("len_add", 0.0))
				lm *= float(b.get("len_mult", 1.0))
				wa += float(b.get("w_add", 0.0))
				wm *= float(b.get("w_mult", 1.0))
				oh.append_array(b.get("on_hit", []))
	o.tx["len"] = (1.0 + la) * lm
	o.tx["w"] = (1.0 + wa) * wm
	if not oh.is_empty() or o.tx.has("on_hit"):   # 精英化段：冲刺追加状态（没有时不写这个键）
		o.tx["on_hit"] = oh


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
	"anchor", "hit_anchor", "mark_anchor", "layer", "finale",
	"along", "step", "if_tex"]   # 精英化段：along: path = 沿上一次冲刺路径每 step 一柄、按顺序 stagger 间隔落下；if_tex 同 fx 条目（缺图回退）
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
	var along := str(b.get("along", "")) == "path"
	if b.has("along") and not along:
		errs.append(p + ".along 只能是 path（沿上一次冲刺路径）")
	if along:
		_num(b, "step", p, ctx, true, 8.0, 400.0)
	elif not (b.has("density") or b.has("n")):
		errs.append(p + "：verb.fx_rain 要写 density（每 1 万平方像素几柄）或 n（固定柄数）")
	if b.has("if_tex"):
		var it := str(b.if_tex).trim_prefix("!")
		if not it.begins_with("fx_"):
			errs.append(p + ".if_tex 必须是帧条名（fx_*），前面加 ! 表示缺这条贴图时才画")
	_num(b, "r", p, ctx, not along, 0.0, 600.0)
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
	if b.has("if_tex"):   # 精英化段：按贴图有无取舍（同 fx 条目的 if_tex）
		var it: String = str(b.if_tex)
		var neg: bool = it.begins_with("!")
		if (o._fx_tex(it.substr(1) if neg else it) != null) == neg:
			return
	if str(b.get("along", "")) == "path":
		_tx_rain_path(o, b)
		return
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
	_tx_rain_emit(o, b, cc, r, bl, tmax, bs, ft)


## 精英化段：verb.fx_rain along: path——沿上一次冲刺（或残像）路径每 step 一柄（柄数 = ceil(路径长 / step)，均匀落在各段中点），
## 从起点到终点依次间隔 stagger 秒落下（缺省 0.03）；不撒随机落点、不先落在敌人身上。画面随机只用 g.vrng
static func _tx_rain_path(o, b: Dictionary) -> void:
	var g = o.g
	var c: Dictionary = o.tx.get("ctx", {})
	if not c.has("from"):
		return
	var bs: Array = _tx_rain_spec(o, str(b.strip), b.get("anchor"), Vector2(0.5, 2.0))
	if bs.is_empty():
		return
	var pts: Array = el_path_points(c.from, c.to, float(b.step))
	var rng: RandomNumberGenerator = g.vrng
	var st: float = float(b.get("stagger", 0.03))
	var sc: float = float(b.get("scale", 1.0))
	var sj: float = float(b.get("scale_j", 0.1))
	var tilt: float = deg_to_rad(float(b.get("tilt", 4.0)))
	var slant: float = deg_to_rad(float(b.get("slant", 0.0)))
	var bl: Array = []
	for k in pts.size():
		bl.append({"p": pts[k], "d": st * k, "s": sc * (1.0 + rng.randf_range(-sj, sj)), "a": slant + rng.randf_range(-tilt, tilt), "fl": rng.randf() < 0.5})
	var cc: Vector2 = ((c.from as Vector2) + (c.to as Vector2)) * 0.5
	_tx_rain_emit(o, b, cc, (c.from as Vector2).distance_to(c.to) * 0.5, bl, st * maxf(0.0, pts.size() - 1.0), bs, float(b.get("fall_t", 0.1)))


static func _tx_rain_emit(o, b: Dictionary, cc: Vector2, r: float, bl: Array, tmax: float, bs: Array, ft: float) -> void:
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
	if not o.manual_attack() and o.g.map.tb_aim and o.g.map.blocks():
		# 地形阻挡（terrain/aim_los）：自动瞄准时视线内的先（按上面的顺序补被挡的；全被挡 = 原结果）
		var all: Array = out.duplicate()
		for kv in keyed:
			if not all.has(kv[2]):
				all.append(kv[2])
		out = o.los_sort(all, n)
	return out


## 普攻起手点（data_operator.update 的 projectile 分支）：B 需要目标类手动普攻走 attack_targets
static func exu_aim(o, a: Dictionary) -> Vector2:
	var rr: float = _exu_range(o, _exu_params(o, a, true))
	var ts: Array = o.attack_targets(1, rr, o.pos) if o.manual_attack() else o.los_targets(1, rr, o.pos)
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
		var btex: String = str(q.get("tex", ""))
		if fan:
			dir = d0.rotated(lerpf(-sp, sp, float(k) / float(n - 1)) if n > 1 else 0.0)
		else:
			var e: Dictionary = ts[k % ts.size()]
			btex = el_stack_tex(o, str(q.get("src", "")), e, btex)   # 精英化段（st.stack）：瞄准的敌人身上的层数决定弹体颜色
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
				"tags": q.get("tags", []), "pierce": int(q.get("pierce", 0)), "kb": float(q.get("kb", 0.0)), "hit": {}, "tex": btex, "hfx": str(q.get("hit_fx", "fx_exusiai_hit")), "on_hit": oh, "ric": true})
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
		if g.map.tb_bul and g.map.bullet_blocked(bu, q):   # 地形阻挡：弹道（含跳弹）撞景物底座即消失
			bu.life = 0.0
			continue
		for j in o.query_ids(q, 32.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or bu.hit.has(e.id) or e.pos.distance_to(q) > float(e.r) + EXU_HIT_PAD:
				continue
			bu.hit[e.id] = true
			var sk: Array = el_stack_hit(o, e, str(bu.src))   # 精英化段（st.stack）：[伤害倍率, 满层命中火花（"" = 照旧）]
			o.log_hit(bu.src, bu.tags)
			o.deal_damage(e, bu.dmg * (ve if e.elite or e.boss else 1.0) * float(sk[0]))
			if float(bu.get("kb", 0.0)) > 0.0 and not e.dead and not e.boss:
				e.kb += bu.v.normalized() * float(bu.kb) * (0.3 if e.elite else 1.0)   # 同 melee_hit：精英 ×0.3、Boss 不受
			for s in bu.on_hit:
				apply_status(o, e, s)
			o._sfx_op("hit")
			o.spawn_fx_sprite(str(sk[1]) if str(sk[1]) != "" else str(bu.get("hfx", "fx_exusiai_hit")), e.pos + Vector2(0, EXU_AIM_Y), g.PX * 0.8)
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
	if sb.has("attack_patch") and not atk_shape in ["point_aoe", "shell", "thrust", "umbrella", "hammer", "foxfire", "cannon", "bash"]:   # shell / thrust / umbrella（手写迁移段）、hammer / foxfire / cannon / bash（第 4 批）的补丁由 _v_next_n 查
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
		elif kd.has("anim") or kd.has("zone"):   # 精英化第 5 批段：非随行召唤物的帧条状态（浮现 / 待机 / 移动 / 施放）、自带区域
			e5_spawn_state(o, s, kd)
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
		elif s.has("e5"):
			e5_step(o, s, kd, i, int(cnt.get(s.kind, 1)), dt)   # 精英化第 5 批段：带帧条 / 区域的召唤物（内部照样走 _sm_step）
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
			if mv.has("repick"):   # 精英化第 5 批段：每 repick 秒重新选一次目标（densest = 跟着敌群最密处走）
				s["rp"] = float(s.get("rp", 0.0)) - dt
				if float(s.rp) <= 0.0:
					s.rp = float(mv.repick)
					tg = null
					s.rt = 0.0
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
	if g.perf_alt and s.has("e5"):   # 精英化第 5 批段：--perfab 的 /b 桶不画（量净成本用）
		return
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
			if not q in SM_KIND_KEYS + MF_KIND_KEYS + E5_KIND_KEYS:
				errs.append("%s.%s：召唤物定义不认识的字段（只能是 %s）" % [p, q, " / ".join(SM_KIND_KEYS + MF_KIND_KEYS + E5_KIND_KEYS)])
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
				if not q in SM_MOVE_KEYS + MF_MOVE_KEYS + E5_MOVE_KEYS:
					errs.append("%s.move.%s：不认识的字段（只能是 %s）" % [p, q, " / ".join(SM_MOVE_KEYS + MF_MOVE_KEYS + E5_MOVE_KEYS)])
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
		_e5_kind(kd, p, ctx)   # 精英化第 5 批段：zone / move.repick / 非随行召唤物的 anim
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
const MF_SPRITE_KEYS := ["fit", "scale_r", "scale", "rot", "second_scale", "second_rot", "swing_rot", "tint", "bottom", "flip_side", "rot_ang"]
const MF_PFX_KINDS := ["ring", "glow", "spark", "shard", "line", "mote", "crescent", "impact", "core", "qshard", "beamray", "crack", "flame", "lava_pillar", "s1link", "h4_cross"]   # crack / flame：手写迁移段（character.gd 的地裂 / 火舌）；lava_pillar：hw_draw_pfx
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
		if b.has("lunge") and m.lunge.is_empty():   # 精英化段：扑击
			m.lunge = b.lunge
	if not mods.is_empty() or not o.mf.is_empty():
		mf_st(o).mods = mods


static func _mf_mod_empty() -> Dictionary:
	return {"dmg": [], "aspd": [], "reach": [], "arc": [], "speed": [], "then": {}, "mirror": {}, "lunge": {}}


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
	if a == "los":   # 手写迁移段：普攻射程（attack.range）+ aim_pad（× op_range）内视线优先的最近敌人
		var ra: float = (float(o.B.get("attack", {}).get("range", 300.0)) + float(sk[i].get("aim_pad", 0.0))) * o.stat(&"op_range")
		var tl: Array = o.los_targets(1, ra, o.pos)
		return tl[0].pos if not tl.is_empty() else Vector2.INF
	if a == "tether":   # 手写迁移段：这个技能的 verb.tether 选的落点
		for tb in sk[i].get("do", []):
			if str(tb.get("_tag", "")) == "verb.tether":
				return hw_tether_target(o, tb)
		return Vector2.INF
	if a == "range":   # 手写迁移段：攻击距离（逻各斯段 hw_range）内最近的敌人
		var tr: Array = o.nearest_enemies(1, hw_range(o), o.pos)
		return tr[0].pos if not tr.is_empty() else Vector2.INF
	if a == "elite" or a == "cluster":   # 手写迁移段第 4 批：凋零处刑（精英 / Boss 优先）/ 饱和炮击（离队长最近、相仿挑最密）
		return h4_skill_aim(o, i, a)
	if a == "nearest":   # 手写迁移段：aim_r（世界像素）内最近的敌人，没有 = 不转身
		var ts: Array = o.nearest_enemies(1, float(sk[i].get("aim_r", 200.0)), o.pos)
		return ts[0].pos if not ts.is_empty() else Vector2.INF
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
		if sk[i].has("status") and o.skill_on(i) and not "%d" in str(sk[i].status):   # 带 %d 的（次数型剩余发数）由手写迁移段 hw_status_items 画
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
	if s.has("dash"):   # 精英化段：扑击 / 回防跃回中（位移、落地结算、帧条都在 el_dash_step）
		el_dash_step(o, s, kd, mods, dt)
		return
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
	if tg != null and float(s.act) <= 0.0 and not mods.get("lunge", {}).is_empty() and el_lunge_try(o, s, kd, tg, mods.lunge):   # 精英化段：扑击
		return
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
	if not sq.is_empty() and not ak in ["attack", "lunge", "leap"]:   # lunge / leap：精英化段（扑击 / 跃回）照播自己的帧条
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
	var dash: bool = ak in ["lunge", "leap"]
	if dash and o.anim_tex(base_key) == null:   # 精英化段：扑击 / 跃回帧条缺图时用 run 代替（位移与残影照旧）
		base_key = str(an.get("run", an.get("idle", "")))
		dash = false
	var pa: Dictionary = pt.get("anim", {})
	var tx2: Texture2D = o.anim_tex(str(pa.get(ak, base_key)))
	if tx2 == null:
		tx2 = o.anim_tex(base_key)
	if tx2 == null:
		return []
	var n2: int = o.anim_hframes(tx2, base_key)
	var fr2: int
	if ak == "attack" or dash:
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
	if s.has("dash"):   # 精英化段：跃回的弧线高度 + 扑击 / 跃回的绿色残影
		hov -= float(s.dash.get("h_now", 0.0))
		el_draw_afterimages(o, s, kd, fr, hov)
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
	if sv.get("rot_ang", false):   # 手写迁移段：随这一击的方向转（锚击刀光）
		rot = float(ctx.get("ang", 0.0))
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
			if b.has("lunge"):   # 精英化段：扑击（召唤物移动参数，docs/91 §6 凯尔希精一）
				any = true
				_el_lunge_check(b.lunge, p + ".lunge", ctx)
			if not any:
				errs.append(p + "：verb.summon_mod 至少写 dmg / aspd / reach / arc / speed / then / mirror / lunge 之一")
			for kk in b:
				if not kk in MF_MOD_FACTORS + ["then", "mirror", "lunge", "verb", "kind", "cond", "_doc", "_uid", "_tag"]:
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
		var an = kd.anim
		if not esc:   # 精英化第 5 批段：非随行召唤物也能写 anim（idle / run / attack / spawn），在 _e5_kind 里查
			pass
		elif not (an is Dictionary) or not an.has("idle"):
			errs.append(p + ".anim 必须是对象，至少有 idle")
		else:
			for k in an:
				if not k in ["idle", "run", "attack", "lunge", "leap"]:   # lunge / leap：精英化段（扑击 / 回防跃回）
					errs.append("%s.anim.%s：只能是 idle / run / attack / lunge / leap" % [p, k])
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


# ================================================================ 精英化第 1 批（docs/91 §19 批 1、§20：德克萨斯 / 能天使 / 星熊 / 安洁莉娜 / 凯尔希，10-13）
# 只往后加。新积木：
#  st.stack          常驻（trait / talent / 节点 / passive do）：本干员 src 列表里的伤害命中同一名敌人时按层加伤——命中时伤害 × (1 + per × 已有层数)，
#                    然后层数 +1（至多 max）；这名敌人 decay 秒没被这些来源打中就清零。层数记在本干员身上（按敌人 id），不写进敌人。
#                    tex：按层数分档换弹体帧条（[1 档, 2 档, 3 档…]，层数 / max 均分；0 层用原弹体）；full_fx：叠满后这一下的命中火花。
#                    目前作用于弹道命中（shape.projectile，能天使「穿甲连射」）；逻各斯「剜魂」迁积木时接到 st.* 法伤上
#  verb.buff_timed   瞬时：stat / op（缺省 add）/ value，持续 dur 秒；同 key 再触发只刷新时间、不叠加。生效期间等同一块 verb.buff_self 常驻积木
#                    （局部倍率或 op_* 属性，fx 里的贴身层 / hold 帧条也照常画），条件 buff:<key> 为真。星熊「反击架势」
#  shape.boomerang   瞬时：往返弹体。朝最近敌人（手动普攻按 A 方向）飞出 len（× op_range），到头停 hold 秒，再飞回本干员手里（原点跟着她走）；
#                    去程、回程各扫一遍线段（宽 w），同一敌人每程一次：去程 × mult_out 并按 kb_out 击退，回程 × mult_back 不击退。伤害口径同 shape.line
#                    （普攻替换时也吃局部倍率 atk）。lock: true = 弹体在外面时本干员不普攻。tex：弹体帧条（缺图画程序圆盾）；spark：沿途火花帧条。星熊「般若回旋」
#  verb.summon_cmd   瞬时：指挥 kind 种召唤物做一个动作。action: leap = 以 t 秒弧线跃回 to（leader = 队长身边），落地执行 then（center: target = 落点）。凯尔希「回防」
#  trig.on_mate_attack  画面挂点：编队里 scope（缺省 others）范围内的队友每次普攻出手，在她的出手点播 fx（at: mate）。只有画面，不进玩法。能天使「天使的祝福」
# 新参数（挂在已有积木上）：
#  st.* 的 first_only（只给这次命中列表 / 这次冲刺的第一个敌人）、cd（同一块状态两次生效至少隔几秒）、fx（状态生效时在这名敌人处播，中心 = 敌人脚底）
#  trig.every_n 的 replace（这一次普攻整个换成 do）/ anim（这一次起手播的帧条）
#  shape.circle 的 only（[weightless / airborne]：只打处于这些状态的敌人）、center: path + step / delay / stagger（沿上一次冲刺路径每 step 一处，依次延迟结算）
#  verb.field 的 cap；verb.dash_mod 的 on_hit；verb.trail 的 on_expire；verb.fx_rain 的 along: path / step / if_tex；verb.summon_mod 的 lunge
#  （召唤物扑击：目标在 min_d 外时 t 秒扑过去，落地半径 r 内 × mult，cd 秒一次）；召唤物 anim 的 lunge / leap 帧条
#  fx 条目的 delay / stay / once / face_x / flash: fire，at: members（光环受益者，hold）/ mate；hold 的 over 层（画在人物之上）
# 确定性：本段不取 g.rng；画面只用 g.vrng 与 g.t。没写这些积木 / 参数的干员一个分支都不走（同 seed 逐行不变）。

const EL_TAGS := ["st.stack", "verb.buff_timed", "shape.boomerang", "verb.summon_cmd", "trig.on_mate_attack"]
const EL_ONLY := ["weightless", "airborne"]
const EL_BOOM_MAX := 6           # 每名干员同时在外的往返弹体上限
const EL_GREEN := Color(0.55, 1.0, 0.5)


## 本段状态（data_operator.el）：timed 限时增益、stk 叠层、boom 往返弹体、cd 状态冷却、fire_t 上次普攻出手的 g.t
static func el_st(o) -> Dictionary:
	if o.el.is_empty():
		o.el.merge({"timed": {}, "stk": {}, "boom": [], "cd": {}, "fire_t": -99.0})
	return o.el


static func el_parse_cond(s: String) -> Dictionary:
	var neg := s.begins_with("!")
	var t := s.substr(1).strip_edges() if neg else s
	if t.begins_with("buff:") and t.length() > 5:
		return {"neg": neg, "k": "buff", "a": t.substr(5), "op": "", "v": 0.0}
	return {}


## 限时增益 key 生效中
static func el_buff_on(o, key: String) -> bool:
	var el = o.get("el")
	if not (el is Dictionary) or el.is_empty():
		return false
	var tb: Dictionary = el.timed
	return tb.has(key) and float(tb[key].until) > float(o.g.t)


## 只乘普攻的局部倍率（data_operator 在普攻出手的那一下把 atk_live 置 true）
static func el_atk_mult(o) -> float:
	if o.get("atk_live") == true:
		return float(o.loc.get("atk", 1.0))
	return 1.0


## st.* 的 first_only / cd 闸门：idx = 这名敌人在这次命中列表里的序号（-1 = 没有顺序，first_only 不生效）
static func el_status_gate(o, s: Dictionary, idx: int) -> bool:
	if s.get("first_only", false) and idx != 0:
		return false
	if s.has("cd"):
		var st := el_st(o)
		var u: int = int(s.get("_uid", 0))
		if float(st.cd.get(u, -INF)) > float(o.g.t):
			return false
		st.cd[u] = float(o.g.t) + float(s.cd)
	return true


## shape.circle only：圆内（同 area_hit 的判定）且处于 only 列出的状态之一的敌人，伤害同 area_hit（× vs_elite），不击退不眩晕
static func el_area_only(o, b: Dictionary, c: Vector2, r: float, dmg: float) -> Array:
	var g = o.g
	var only: Array = b.get("only", [])
	var hits: Array = []
	for e in o.arc_targets(c, 0.0, PI, r):
		if e.dead:
			continue
		var ok := false
		for k in only:
			match str(k):
				"weightless":
					ok = ok or (e.has("wl_t") and float(e.wl_t) > float(g.t))
				"airborne":
					ok = ok or float(e.get("air", 0.0)) > 0.0 or o.air_list.any(func(a): return is_same(a.e, e))
		if ok:
			hits.append(e)
	var max_n: int = int(b.get("max_n", 0))
	if max_n > 0 and hits.size() > max_n:
		hits = o.cap_targets(hits, c, max_n)
	var ve: float = o.vs_elite()
	var src: String = str(b.get("src", ""))
	var tags: Array = b.get("tags", [])
	for e in hits:
		o.log_hit(src, tags)
		o.deal_damage(e, dmg * (ve if e.elite or e.boss else 1.0))
	return hits


## 路径上的点：from → to 均分 ceil(长 / step) 段，取各段中点
static func el_path_points(a: Vector2, b: Vector2, step: float) -> Array:
	var L: float = a.distance_to(b)
	var n: int = maxi(1, int(ceil(L / maxf(1.0, step) - 0.001)))
	var out: Array = []
	for i in n:
		out.append(a.lerp(b, (float(i) + 0.5) / float(n)))
	return out


## shape.circle center: path：沿德克萨斯段的上一次冲刺 / 残像路径（tx.ctx）每 step 一处；第 i 处在 delay + i × stagger 秒后结算（进冲刺延迟队列）
static func el_path_circles(o, b: Dictionary) -> void:
	var c: Dictionary = o.tx.get("ctx", {})
	if not c.has("from"):
		return
	var pts: Array = el_path_points(c.from, c.to, float(b.get("step", 40.0)))
	var d0: float = float(b.get("delay", 0.0))
	var st: float = float(b.get("stagger", 0.0))
	for i in pts.size():
		var b2: Dictionary = b.duplicate()
		b2["center"] = "target"
		b2.erase("cond")   # 条件在整块执行时已经看过
		var dl: float = d0 + st * i
		if dl <= 0.0:
			exec_shape(o, b2, pts[i])
		else:
			var q: Array = o.tx.get("queue", [])
			q.append({"t": dl, "do": [b2], "ctx": {"to": pts[i]}})
			o.tx["queue"] = q


# ---------------------------------------------------------------- st.stack（能天使「穿甲连射」）

## 本帧生效的 st.stack（第一块），没有 = {}
static func el_stack_block(o) -> Dictionary:
	var el = o.get("el")
	if not (el is Dictionary):
		return {}
	var bs: Array = el.get("stack_on", [])
	return bs[0] if not bs.is_empty() else {}


## 命中结算：返回 [伤害倍率, 满层火花帧条名或 ""]；不是 st.stack 的来源原样 [1.0, ""]
static func el_stack_hit(o, e: Dictionary, src: String) -> Array:
	var b := el_stack_block(o)
	if b.is_empty() or not src in b.get("src", []):
		return [1.0, ""]
	var st := el_st(o)
	var t: float = float(o.g.t)
	var cur: Array = st.stk.get(e.id, [0, -INF])
	var n: int = int(cur[0]) if t - float(cur[1]) <= float(b.decay) else 0
	var mult: float = 1.0 + float(b.per) * n
	var mx: int = int(b.max)
	n = mini(n + 1, mx)
	st.stk[e.id] = [n, t]
	if st.stk.size() > 96:   # 过期 / 死掉的清掉（只按时间，确定性）
		for k in st.stk.keys():
			if t - float(st.stk[k][1]) > float(b.decay):
				st.stk.erase(k)
	return [mult, str(b.get("full_fx", "")) if n >= mx else ""]


## 开火时的弹体帧条：瞄准的敌人身上当前层数分档（0 层 = 原帧条；缺图 = 原帧条）
static func el_stack_tex(o, src: String, e: Dictionary, dflt: String) -> String:
	var b := el_stack_block(o)
	if b.is_empty() or not src in b.get("src", []) or not b.has("tex"):
		return dflt
	var cur: Array = o.el.stk.get(e.id, [0, -INF])
	if float(o.g.t) - float(cur[1]) > float(b.decay) or int(cur[0]) <= 0:
		return dflt
	var tl: Array = b.tex
	var tier: int = clampi(int(ceil(float(cur[0]) / float(b.max) * tl.size() - 0.001)), 1, tl.size())
	var nm: String = str(tl[tier - 1])
	return nm if o.g.tex.get(nm) != null else dflt


# ---------------------------------------------------------------- 常驻部分（data_operator._sustain 转来）

## 本帧生效的限时增益积木（按 key 首次触发的顺序，确定性）追加进常驻列表；同时记下本帧的 st.stack
static func el_sustain_collect(o, act: Array) -> void:
	var el = o.get("el")
	if not (el is Dictionary) or el.is_empty():
		for b in act:
			if str(b.get("_tag", "")) == "st.stack":
				el_st(o)
				break
		if o.el.is_empty():
			return
	var t: float = float(o.g.t)
	for k in o.el.timed.keys():
		var tb: Dictionary = o.el.timed[k]
		if float(tb.until) > t:
			act.append(tb.b)
		else:
			o.el.timed.erase(k)
	var sk: Array = []
	for b in act:
		if str(b.get("_tag", "")) == "st.stack":
			sk.append(b)
	o.el["stack_on"] = sk


# ---------------------------------------------------------------- 瞬时（data_operator._exec_list 缺省分支转来）

static func el_exec(o, b: Dictionary, at: Vector2) -> void:
	match str(b.get("_tag", "")):
		"verb.buff_timed":
			var st := el_st(o)
			var key: String = str(b.get("key", "buff"))
			var had: bool = st.timed.has(key) and float(st.timed[key].until) > float(o.g.t)
			st.timed[key] = {"until": float(o.g.t) + float(b.dur), "b": b}
			if not had and b.has("text"):
				o.float_text(o.pos + Vector2(0, -80), str(b.text), Color(1.0, 0.45, 0.4), 14)
		"shape.boomerang":
			el_boom_start(o, b)
		"verb.summon_cmd":
			el_summon_cmd(o, b, at)


# ---------------------------------------------------------------- shape.boomerang（星熊「般若回旋」）

static func el_boom_start(o, b: Dictionary) -> void:
	var g = o.g
	if o.pos == Vector2.INF:
		return
	var st := el_st(o)
	if st.boom.size() >= EL_BOOM_MAX:
		return
	var L: float = float(b.get("len", 220.0)) * o.stat(&"op_range")
	var ts: Array = o.nearest_enemies(1, L + 20.0, o.pos)
	var ang: float = o.atk_angle((ts[0].pos - o.pos).angle() if not ts.is_empty() else o.facing_angle())
	var dir := Vector2.from_angle(ang)
	if absf(dir.x) > 0.1:
		o._set_face(signf(dir.x), true)
	var dmg: float = o.base(str(b.get("atk_key", "atk")), 0.0) * float(o.loc.dmg) * o._dmg_bonus() * el_atk_mult(o)
	if b.get("power", false):
		dmg *= o.skill_power()
	st.boom.append({"b": b, "dir": dir, "L": L, "w": float(b.get("w", 56.0)), "t": 0.0, "to": float(b.get("t_out", 0.3)), "hold": float(b.get("hold", 0.1)),
		"tb": float(b.get("t_back", 0.3)), "dmg": dmg, "last": 0.0, "hit0": {}, "hit1": {}, "spin": 0.0, "sp_t": 0.0})
	if b.has("sfx"):
		o._sfx_op(str(b.sfx))


## 弹体此刻离本干员的距离（世界像素）与所在程（0 去 / 1 回）
static func _el_boom_d(bm: Dictionary) -> Array:
	var t: float = float(bm.t)
	var to: float = float(bm.to)
	if t < to:
		var k: float = t / maxf(0.01, to)
		return [float(bm.L) * (1.0 - (1.0 - k) * (1.0 - k)), 0]   # 先快后慢
	if t < to + float(bm.hold):
		return [float(bm.L), 0]
	var k2: float = clampf((t - to - float(bm.hold)) / maxf(0.01, float(bm.tb)), 0.0, 1.0)
	return [float(bm.L) * (1.0 - k2 * k2), 1]   # 先慢后快地收回


static func el_boom_total(bm: Dictionary) -> float:
	return float(bm.to) + float(bm.hold) + float(bm.tb)


## 每帧（data_operator.update）：推进往返弹体、扫线段结算
static func el_tick(o, dt: float) -> void:
	var el = o.get("el")
	if not (el is Dictionary) or el.is_empty() or el.boom.is_empty() or o.pos == Vector2.INF:
		return
	var g = o.g
	for bm in el.boom:
		var d0: Array = _el_boom_d(bm)
		bm.t = float(bm.t) + dt
		bm.spin = float(bm.spin) + dt * 18.0
		var d1: Array = _el_boom_d(bm)
		var b: Dictionary = bm.b
		var leg: int = int(d1[1])
		if leg != int(d0[1]):   # 刚转回程：去程的最后一段补扫
			_el_boom_sweep(o, bm, float(d0[0]), float(bm.L), 0)
			d0 = [float(bm.L), 1]
		_el_boom_sweep(o, bm, float(d0[0]), float(d1[0]), leg)
		bm.sp_t = float(bm.sp_t) - dt
		if float(bm.sp_t) <= 0.0 and b.has("spark"):   # 沿途火花（画面）
			bm.sp_t = 0.06
			var p: Vector2 = o.pos + bm.dir * float(d1[0]) + Vector2(0, -22)
			o.spawn_fx_sprite(str(b.spark), p + Vector2(g.vrng.randf_range(-6.0, 6.0), g.vrng.randf_range(-6.0, 6.0)), g.PX, g.vrng.randf() * TAU)
	el.boom = el.boom.filter(func(bm): return float(bm.t) < el_boom_total(bm))


## 扫 [a, c]（离本干员的距离）这一段：线段内、这一程还没打过的敌人各吃一次
static func _el_boom_sweep(o, bm: Dictionary, a: float, c: float, leg: int) -> void:
	var g = o.g
	if absf(c - a) < 0.01 and a > 0.5:
		return
	var b: Dictionary = bm.b
	var dir: Vector2 = bm.dir
	var lo: float = minf(a, c)
	var hi: float = maxf(a, c)
	var p0: Vector2 = o.pos + dir * lo
	var hit: Dictionary = bm.hit0 if leg == 0 else bm.hit1
	var mult: float = float(b.get("mult_out", 1.0)) if leg == 0 else float(b.get("mult_back", 1.0))
	var kb: float = float(b.get("kb_out", 0.0)) if leg == 0 else 0.0
	var ve: float = o.vs_elite()
	var src: String = str(b.get("src", ""))
	var tags: Array = b.get("tags", [])
	var w: float = float(bm.w)
	var got: Array = []
	for j in o.query_ids(p0 + dir * (hi - lo) * 0.5, (hi - lo) * 0.5 + w + 40.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or hit.has(e.id) or not line_contains(p0, dir, hi - lo, w, e.pos, float(e.r)):
			continue
		hit[e.id] = true
		got.append(e)
	for e in got:
		o.log_hit(src, tags)
		o.deal_damage(e, float(bm.dmg) * mult * (ve if e.elite or e.boss else 1.0))
		if not e.dead and not e.boss and kb > 0.0:
			e.kb += dir * kb * (0.3 if e.elite else 1.0) * kb_taken(e, g.t)
		o._hit_fx(e, o.pos)
		if b.has("fx"):
			fx_play(o, b.fx, e.pos + Vector2(0, -float(e.r) * 0.5), float(e.r), [e], dir.angle())
	if not got.is_empty():
		o._sfx_op("hit")


## 普攻锁：有 lock: true 的往返弹体在外面
static func el_attack_locked(o) -> bool:
	var el = o.get("el")
	if not (el is Dictionary) or el.is_empty():
		return false
	for bm in el.boom:
		if bm.b.get("lock", false):
			return true
	return false


# ---------------------------------------------------------------- 召唤物：扑击（summon_mod.lunge）/ 跃回（verb.summon_cmd）

static func _el_dash_spec(o, kd: Dictionary, k: String) -> Dictionary:
	var key: String = str(kd.get("anim", {}).get(k, ""))
	if key == "" or o.anim_tex(key) == null:
		return {}
	return o.sprite_spec(key)


## 起一段位移：k = lunge / leap；to = 落点；t = 位移秒数；h = 弧线高度；land = 落地时执行的 [种类, 参数]
static func _el_dash_start(o, s: Dictionary, kd: Dictionary, k: String, to: Vector2, t: float, h: float, land: Dictionary) -> void:
	var sp := _el_dash_spec(o, kd, k)
	var fps: float = float(sp.get("fps", 12.0))
	var n: float = float(sp.get("frames", 0))
	var t0 := 0.0
	var end: float = t + 0.08
	if not sp.is_empty():
		var land_t: float = (float(sp.fire) + 0.5) / fps if sp.has("fire") else (n - 2.0) / fps   # 扑击：出手帧落爪；跃回：倒数第 2 帧（展开刃爪）落地
		t0 = maxf(0.0, land_t - t)
		end = t0 + t + 1.0 / fps   # 落地后再停一帧就交还给普通行动（帧条后面的收势帧让位给紧接着的爪击，不白占出手时间）
	s.dash = {"k": k, "from": s.pos, "to": to, "t": 0.0, "t0": t0, "dur": t, "end": end, "h": h, "h_now": 0.0, "land": land, "done": false, "hist": []}
	s.act = end
	s.fire = -1.0
	s.pend = []
	if absf(to.x - s.pos.x) > 2.0:
		s.face = signf(to.x - s.pos.x)
		s.flip_t = o.g.t
	s.ak = k
	s.at = 0.0


static func el_dash_step(o, s: Dictionary, kd: Dictionary, mods: Dictionary, dt: float) -> void:
	var g = o.g
	var d: Dictionary = s.dash
	var prev: Vector2 = s.pos
	var ph: float = float(d.h_now)
	d.t = float(d.t) + dt
	var k: float = clampf((float(d.t) - float(d.t0)) / maxf(0.01, float(d.dur)), 0.0, 1.0)
	s.pos = (d.from as Vector2).lerp(d.to, 1.0 - (1.0 - k) * (1.0 - k) if d.k == "lunge" else k)
	d.h_now = float(d.h) * sin(k * PI)
	var hist: Array = d.hist
	hist.append([float(d.t), s.pos, float(d.h_now)])
	if hist.size() > 12:
		hist.pop_front()
	if d.k == "leap" and k > 0.0 and k < 1.0 and s.pos.distance_to(prev) > 0.5:   # 跃回：空中拉一道绿色弧形拖尾（逐段淡出）
		o.fx({"kind": "line", "pos": prev + Vector2(0, -ph - 26.0), "to": s.pos + Vector2(0, -float(d.h_now) - 26.0), "w": 4.0, "life": 0.3, "col": Color(EL_GREEN.r * 1.4, EL_GREEN.g * 1.4, EL_GREEN.b * 1.4)})
	if not d.done and float(d.t) >= float(d.t0) + float(d.dur):
		d.done = true
		_el_land(o, s, kd, mods, d)
	var cdk: float = dt
	for f in mods.aspd:
		cdk *= f
	s.cd = float(s.cd) - cdk
	s.at = float(s.at) + dt
	s.mv = 0.0
	if float(d.t) >= float(d.end):
		s.erase("dash")
		s.act = 0.0
		_mf_set_anim(s, "idle")


static func _el_land(o, s: Dictionary, kd: Dictionary, mods: Dictionary, d: Dictionary) -> void:
	var g = o.g
	var ld: Dictionary = d.land
	match str(ld.get("kind", "")):
		"lunge":
			var lg: Dictionary = ld.b
			var a: Dictionary = kd.get("attack", {})
			var r: float = float(lg.get("r", 40.0)) * o.stat(&"op_range")
			var dmg: float = mf_dmg(o, a, mods, s.pcur) * float(lg.get("mult", 0.3))
			var tags: Array = a.get("tags", []).duplicate()
			if not "summon" in tags:
				tags.append("summon")
			var hits: Array = o.area_hit(str(s.pcur.get("src", a.get("src", ""))), s.pos, r, dmg, 0.0, 0.0, tags)
			if lg.has("fx"):
				fx_play(o, lg.fx, s.pos, r, hits)
			else:
				o.fx({"kind": "ring", "pos": s.pos, "r": r, "r0": r * 0.4, "life": 0.25, "col": EL_GREEN, "floor": true, "w": 2.0, "alpha": 0.7})
		"leap":
			o._exec_list(ld.get("then", []), s.pos)
			var b: Dictionary = ld.get("b", {})
			if b.has("fx"):
				fx_play(o, b.fx, s.pos, 100.0)


## 扑击：目标在 min_d（+ 目标半径）外、冷却好了 → 扑到目标身前；返回 true = 已起扑
static func el_lunge_try(o, s: Dictionary, kd: Dictionary, tg: Dictionary, lg: Dictionary) -> bool:
	var g = o.g
	if float(g.t) < float(s.get("lunge_cd", -INF)):
		return false
	var dv: Vector2 = tg.pos - s.pos
	# 够得着就直接出爪：扑击只替「走过去」那一段（目标在 min_d 与爪击距离两者较大的那个之外才扑）
	var reach: float = mf_reach(o, kd.get("attack", {}), mf_mods(o, str(s.kind)))
	if dv.length() <= maxf(float(lg.get("min_d", 80.0)), reach) + float(tg.r):
		return false
	var gap: float = float(tg.r) + float(kd.get("move", {}).get("gap", 26.0))
	var to: Vector2 = tg.pos - dv.normalized() * gap
	s.lunge_cd = float(g.t) + float(lg.get("cd", 1.5))
	_el_dash_start(o, s, kd, "lunge", to, float(lg.get("t", 0.15)), 0.0, {"kind": "lunge", "b": lg})
	return true


## verb.summon_cmd：现在只有 action leap（跃回 to 身边），to 缺省 leader
static func el_summon_cmd(o, b: Dictionary, _at: Vector2) -> void:
	var g = o.g
	if o.sm.is_empty():
		return
	if str(b.get("action", "")) == "cast":   # 精英化第 5 批段：原地施放（播 attack 帧条，出手帧执行 then）
		e5_cast(o, b)
		return
	var kind: String = str(b.get("kind", ""))
	var kd := sm_kind(o, kind)
	if kd.is_empty() or str(kd.get("move", {}).get("mode", "")) != "escort":
		return
	var c: Vector2 = g.ppos if str(b.get("to", "leader")) == "leader" else o.pos
	if c == Vector2.INF:
		return
	for s in o.sm.list:
		if str(s.kind) != kind or s.gone:
			continue
		var side: float = signf(s.pos.x - c.x) if absf(s.pos.x - c.x) > 4.0 else float(o.face)
		var to: Vector2 = c + Vector2(side * float(b.get("land_dx", 30.0)), float(b.get("land_dy", 8.0)))
		_el_dash_start(o, s, kd, "leap", to, float(b.get("t", 0.25)), float(b.get("h", 46.0)), {"kind": "leap", "then": b.get("then", []), "b": b})


## 扑击 / 跃回的残影：前 0.04 / 0.08 / 0.12 秒的位置各画一份绿色剪影（fx_mon3tr_afterimage；缺图时用当前帧染绿）
static func el_draw_afterimages(o, s: Dictionary, kd: Dictionary, fr: Array, hov: float) -> void:
	var g = o.g
	var d: Dictionary = s.dash
	var hist: Array = d.hist
	if hist.size() < 2 or float(d.t) < float(d.t0) or float(d.t) > float(d.t0) + float(d.dur) + 0.15:
		return
	var tx: Texture2D = g.tex.get("fx_mon3tr_afterimage")
	var flip: bool = float(s.face) < 0.0
	var base_h: float = hov + float(d.h_now)
	for q in [3, 2, 1]:
		var tq: float = float(d.t) - 0.04 * q
		var it: Array = hist[0]
		for h in hist:
			if float(h[0]) <= tq:
				it = h
		var p: Vector2 = it[1]
		if p.distance_to(s.pos) < 4.0:
			continue
		var al: float = 0.35 * (1.0 - 0.22 * (q - 1))
		var py: Vector2 = p + Vector2(0, base_h - float(it[2]))
		if tx != null:
			var hi: float = ArtS.hires_of(tx)
			var k: float = g.PX / hi
			o.cv.draw_set_transform(py.round(), 0.0, Vector2(-k if flip else k, k))
			o.cv.draw_texture_rect_region(tx, Rect2(-Vector2(32, 60) * hi, Vector2(tx.get_width(), tx.get_height())), Rect2(0, 0, tx.get_width(), tx.get_height()), Color(EL_GREEN.r, EL_GREEN.g, EL_GREEN.b, al))
			o.cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		elif not fr.is_empty():
			o.draw_sprite_at(py, flip != o.sprite_mirror(str(fr[3])), Color(EL_GREEN.r, EL_GREEN.g * 1.2, EL_GREEN.b, al), fr[1], fr[0], fr[2], o.foot_off(fr[0], fr[3]))


# ---------------------------------------------------------------- 画面（data_operator._draw_skill_over 转来）

static func el_draw_over(o) -> void:
	var g = o.g
	var el = o.get("el")
	if not (el is Dictionary) or el.is_empty() or o.pos == Vector2.INF:
		return
	for bm in el.boom:
		var d: Array = _el_boom_d(bm)
		var p: Vector2 = o.pos + bm.dir * float(d[0]) + Vector2(0, -22)
		var b: Dictionary = bm.b
		var tn: String = str(b.get("tex", ""))
		var tx = g.tex.get(tn) if tn != "" else null
		if tx != null and g.V6_FRAMES.has(tn):
			var spec: Array = g.V6_FRAMES[tn]
			fx_frame(o.cv, g, tn, int(spec[0]), int(float(bm.t) * float(spec[1])), p, g.PX * float(b.get("scale", 1.0)), Color.WHITE, Vector2(-1, -1), 0.0)
		else:   # 程序圆盾：翠绿盾面 + 外圈 + 4 道锯齿，转着飞
			var R: float = 13.0
			o.cv.draw_circle(p, R + 3.0, Color(0.03, 0.06, 0.05, 0.6))
			o.cv.draw_circle(p, R, Color(0.25, 0.75, 0.45))
			o.cv.draw_arc(p, R, 0.0, TAU, 20, Color(0.75, 1.0, 0.8), 2.0)
			for q in 4:
				var a: float = float(bm.spin) + q * TAU / 4.0
				var v := Vector2.from_angle(a)
				o.cv.draw_colored_polygon(PackedVector2Array([p + v * (R - 2.0) + v.orthogonal() * 4.0, p + v * (R + 6.0), p + v * (R - 2.0) - v.orthogonal() * 4.0]), Color(0.85, 1.0, 0.9))


# ---------------------------------------------------------------- trig.on_mate_attack（character.gd 出手时广播）

## 队友 m 普攻出手：本干员生效中的 trig.on_mate_attack 在她的出手点播 fx（scope 缺省 others）
static func el_mate_attack(o, m) -> void:
	if o.pos == Vector2.INF or m == o or m.pos == Vector2.INF:
		return
	for t in o._trigs():
		if str(t.get("_tag", "")) != "trig.on_mate_attack" or not cond_true(o, t.get("cond", {})):
			continue
		if not m in aura_members(o, str(t.get("scope", "others"))):
			continue
		var c: Vector2 = m.pos + Vector2(14.0 * float(m.face), -30.0)
		if t.has("fx"):
			fx_play(o, t.fx, c, 12.0)


# ---------------------------------------------------------------- 本段的校验

static func _el_st_common(b: Dictionary, p: String, ctx: Dictionary) -> void:
	if b.has("first_only") and not (b.first_only is bool):
		ctx.errs.append(p + ".first_only 只能是 true / false")
	_num(b, "cd", p, ctx, false, 0.0, 60.0)


static func _el_lunge_check(v, p: String, ctx: Dictionary) -> void:
	if not (v is Dictionary):
		ctx.errs.append(p + " 必须是对象 {min_d, t, cd, mult, r}")
		return
	for k in v:
		if not k in ["min_d", "t", "cd", "mult", "r", "fx", "_doc"]:
			ctx.errs.append("%s.%s：扑击只有 min_d / t / cd / mult / r / fx" % [p, k])
	_sm_exprs(v, p, ctx)
	_num(v, "min_d", p, ctx, true, 0.0, 400.0)
	_num(v, "t", p, ctx, true, 0.05, 1.0)
	_num(v, "cd", p, ctx, true, 0.0, 30.0)
	_num(v, "mult", p, ctx, true, 0.0, 10.0)
	_num(v, "r", p, ctx, true, 1.0, 300.0)
	if v.has("fx"):
		_fx(v.fx, p + ".fx", ctx, "shape.circle")


## _block 转来：本段的积木校验完返回 true
static func _el_block(b: Dictionary, p: String, kind: String, ctx: Dictionary, tag: String) -> bool:
	if not tag in EL_TAGS:
		return false
	var errs: Array = ctx.errs
	var where_ok := {
		"st.stack": ["sustain"],
		"verb.buff_timed": ["skill", "instant"],
		"shape.boomerang": ["skill", "instant"],
		"verb.summon_cmd": ["skill", "instant"],
		"trig.on_mate_attack": ["trig"],
	}
	if not kind in where_ok[tag]:
		errs.append("%s：「%s」不能放在这里（%s；只能在 %s）" % [p, tag, kind, " / ".join(where_ok[tag])])
		return true
	match tag:
		"st.stack":
			if str(b.get("key", "")) == "":
				errs.append(p + " 缺 key（叠层的名字）")
			_num(b, "per", p, ctx, true, 0.0, 1.0)
			_num(b, "max", p, ctx, true, 1.0, 50.0)
			_num(b, "decay", p, ctx, true, 0.1, 10.0)
			var sl = b.get("src", [])
			if not (sl is Array) or sl.is_empty():
				errs.append(p + ".src 必须是非空数组（哪些伤害来源叠层）")
			else:
				for s in sl:
					if not ctx.srcs.has(str(s)):
						errs.append("%s.src「%s」没在 hit_sources 里登记" % [p, str(s)])
			if b.has("tex"):
				var tl = b.tex
				if not (tl is Array) or tl.is_empty() or tl.size() > 6 or tl.any(func(x): return not str(x).begins_with("proj_")):
					errs.append(p + ".tex 必须是 1–6 个 proj_* 帧条名的数组（按层数分档）")
			if b.has("full_fx") and not str(b.full_fx).begins_with("fx_"):
				errs.append(p + ".full_fx 必须是 fx_* 帧条名")
		"verb.buff_timed":
			var st := str(b.get("stat", ""))
			if not (st in LOCAL_STATS or st in OP_STATS):
				errs.append("%s.stat「%s」只能是 %s" % [p, st, " / ".join(LOCAL_STATS + OP_STATS)])
			if not str(b.get("op", "add")) in ["add", "mult"]:
				errs.append(p + ".op 只能是 add / mult")
			_num(b, "value", p, ctx, true, -1.0, 10.0)
			_num(b, "dur", p, ctx, true, 0.1, 60.0)
			if str(b.get("key", "")) == "":
				errs.append(p + " 缺 key（同 key 再触发只刷新时间）")
		"shape.boomerang":
			_num(b, "len", p, ctx, true, 20.0, 800.0)
			_num(b, "w", p, ctx, true, 4.0, 200.0)
			_num(b, "t_out", p, ctx, true, 0.05, 2.0)
			_num(b, "hold", p, ctx, false, 0.0, 2.0)
			_num(b, "t_back", p, ctx, true, 0.05, 2.0)
			_num(b, "mult_out", p, ctx, true, 0.0, 20.0)
			_num(b, "mult_back", p, ctx, true, 0.0, 20.0)
			_num(b, "kb_out", p, ctx, false, 0.0, 2000.0)
			_num(b, "scale", p, ctx, false, 0.2, 4.0)
			if b.has("lock") and not (b.lock is bool):
				errs.append(p + ".lock 只能是 true / false")
			for k in ["tex", "spark"]:
				if b.has(k) and not (str(b[k]).begins_with("proj_") or str(b[k]).begins_with("fx_")):
					errs.append("%s.%s 必须是帧条名（proj_* / fx_*）" % [p, k])
			_src(b, p, ctx, true)
		"verb.summon_cmd":
			var k := str(b.get("kind", ""))
			if not (ctx.summons is Dictionary and ctx.summons.has(k)):
				errs.append("%s.kind「%s」没在 blocks.summons 里定义" % [p, k])
			if not str(b.get("action", "")) in ["leap", "cast"]:
				errs.append(p + ".action 只能是 leap（跃回 to 身边）/ cast（原地施放，精英化第 5 批段）")
			if not str(b.get("to", "leader")) in ["leader", "self"]:
				errs.append(p + ".to 只能是 leader / self")
			_num(b, "t", p, ctx, str(b.get("action", "")) == "leap", 0.05, 2.0)
			_num(b, "h", p, ctx, false, 0.0, 200.0)
			_num(b, "land_dx", p, ctx, false, 0.0, 200.0)
			_num(b, "land_dy", p, ctx, false, -100.0, 100.0)
			_list(b.get("then", []), p + ".then", "instant", ctx)
		"trig.on_mate_attack":
			var sc := str(b.get("scope", "others"))
			if not sc in ["others", "squad", "leader"]:
				errs.append(p + ".scope 只能是 others / squad / leader")
			if not b.has("fx"):
				errs.append(p + "：trig.on_mate_attack 只挂画面，要写 fx")
			if b.has("do") and not (b.do is Array and b.do.is_empty()):
				errs.append(p + "：trig.on_mate_attack 只挂画面，不写 do")
	return true


# ================================================================ 手写迁移段（精英化第 2 批：逻各斯 / 艾雅法拉 / 斯卡蒂 / 乌尔比安，docs/91 §19 批 2；docs/61 §17）
# 只往后加。四名手写干员迁到积木时缺的积木 / 参数都在这里；手写参照在 tests/data_ops/<id>_legacy.gd（check.py blocks_eq 同 seed 逐行对照）。
# 运行时状态在干员的 hw 字典（data_operator.gd var hw）：没用到本段的数据干员 hw 为空，本段的分支一个都不走（同 seed 逐行不变）。
# 确定性：玩法随机只在手写版也取 g.rng 的地方取（同样的次数、同样的顺序）；画面一律 g.vrng。
#
# 基础（任何数据干员都能用）：
#  blocks.follow {leash, gap}     近战前压：队友时站到队长 leash 内最近敌人的身前 gap 处（character.melee_spot）
#  blocks.hit_fx [fx…]            本干员每打中一名敌人（melee_hit / area_hit）在它身上播的画面
#  attack.first / idle            首击冷却 / 没目标时的重试间隔（缺省 0.5 / 0.2）
#  attack.anim / turn             普攻播的帧条（sprites 键）/ false = 起手不转身（swap_attack 换上的形状也能写）
#  attack.combo [{cond, delay, do}]  连斩：普攻出手后第 1 段 cond 成立就 delay 秒后执行它的 do，执行完再看下一段；最后一段执行完（或第 1 段不成立）触发 trig.on_combo_end
#  trig.on_combo_end              一轮连斩收尾（basis attack = 这一轮普攻的伤害）
#  形状参数 basis                 attack（本轮普攻这一下的伤害）/ prev（上一个伤害形状这一下的伤害）/ hit（触发事件的伤害：弹体命中、爆炸）× mult
#  shape.cone 参数                origin_off [x, y]（判定原点偏移）、aim_pad（找目标的半径 = r + aim_pad，缺省 30）、face（true / 条件串：朝目标转身）、
#                                 dir: back（本次普攻的反方向）、half（半角弧度）、ring: false
#  shape.circle / cone 参数       r_mult（半径 × op_range × r_mult）
#  trig.tick 参数 countdown       倒计时：生效当帧起算 every 秒，到点执行并重置为 every（手写干员的计时写法）
#  verb.buff_self 局部 mult + power   局部倍率也吃技能强度（例：潮汐期间普攻 ×1.5 × 技能强度）
#  技能积木 aim: nearest + aim_r   起手朝 aim_r（世界像素）内最近的敌人
#  fx 程序条目 blade / aura_ring / outline（见 hw_fx_spawn / hw_draw_rings / hw_draw_outline）
# 斯卡蒂：shape.wave（推进的浪墙）

const HW_TAGS := ["shape.wave", "trig.on_combo_end"]
const HW_FX_KINDS := ["blade", "aura_ring", "outline", "slam", "whirl"]
const HW_FX_COMMON := ["cond", "if_tex", "at", "off", "fade", "_doc"]
const HW_SKILL_KEYS := ["aim_r", "aim_pad", "cast", "pulse", "active_timer", "status_active", "stack_max"]   # status_active / stack_max：第 3 批（技能生效期间显示 status / 次数型可叠几次）
const HW_WAVE_MAX := 2           # 同时推进的浪墙上限（手写 skadi WAVE_MAX）


## 本段状态（data_operator.hw）；on = 本干员用到了本段
static func hw_st(o) -> Dictionary:
	if o.hw.is_empty():
		o.hw.merge({"on": true, "atk_dmg": 0.0, "atk_ang": 0.0, "atk_c": Vector2.INF, "prev_dmg": 0.0, "prev_ang": 0.0, "prev_r": 0.0, "prev_c": Vector2.INF,
			"hit_dmg": 0.0, "cc": {}, "waves": []})
	return o.hw


static func hw_on(o) -> bool:
	var h = o.get("hw")
	return h is Dictionary and not h.is_empty()


## data_operator._init：本干员 JSON 用到本段的积木 / 参数时打开 hw
static func hw_init(o) -> void:
	if not _hw_uses(o.B):
		return
	hw_st(o)
	var tags := {}
	_hw_tags(o.B, tags)
	for t in tags:   # 各段的状态一开始就建好（免得「第一次用到才建」时，之前的询问读不到）
		if t in HW2_TAGS:
			_hw2(o)
		elif t in HW3_TAGS:
			_hw3(o)
		elif t in HW4_TAGS:
			_hw4(o)
		elif t in HW5_TAGS:
			_hw5(o)
	h3_init(o, tags)   # 手写迁移段第 3 批
	h4_init(o, tags)   # 手写迁移段第 4 批
	if o.B.get("attack", {}).has("lob"):
		_hw5(o)


static func _hw_tags(n, out: Dictionary) -> void:
	if n is Dictionary:
		if n.has("_tag"):
			out[str(n._tag)] = true
		for k in n:
			_hw_tags(n[k], out)
	elif n is Array:
		for x in n:
			_hw_tags(x, out)


static func _hw_uses(n) -> bool:
	if n is Dictionary:
		for k in n:
			if k in ["follow", "basis", "combo", "countdown", "origin_off", "aim_pad", "hit_fx", "cast", "pulses"]:
				return true
			if k == "_tag" and (str(n[k]) in HW_TAGS or str(n[k]) in HW2_TAGS or str(n[k]) in HW3_TAGS or str(n[k]) in HW4_TAGS or str(n[k]) in HW5_TAGS or str(n[k]) in H3_TAGS or str(n[k]) in H4_TAGS):
				return true
			if _hw_uses(n[k]):
				return true
	elif n is Array:
		for x in n:
			if _hw_uses(x):
				return true
	return false


## basis 的值：attack = 本轮普攻这一下的伤害；prev = 上一个伤害形状；hit = 触发事件的伤害
static func hw_basis(o, k: String) -> float:
	if not hw_on(o):
		return 0.0
	match k:
		"attack":
			return float(o.hw.atk_dmg)
		"prev":
			return float(o.hw.prev_dmg)
		"hit":
			return float(o.hw.hit_dmg)
		"atk":   # 逻各斯段：攻击值（base × 加成 × attack.atk_mults）
			return hw_atk(o)
	return 0.0


## 伤害形状执行后记一笔（data_operator.atk_live = 普攻出手的那一下时同时记成 attack）
static func hw_record(o, dmg: float, ang: float, r: float, c: Vector2) -> void:
	if not hw_on(o):
		return
	var h: Dictionary = o.hw
	h.prev_dmg = dmg
	h.prev_ang = ang
	h.prev_r = r
	h.prev_c = c
	if o.get("atk_live") == true:
		h.atk_dmg = dmg
		h.atk_ang = ang
		h.atk_c = c


## 延迟执行（every_n delay / 连斩）要带着的 basis 快照
static func hw_snap(o) -> Dictionary:
	if not hw_on(o):
		return {}
	var h: Dictionary = o.hw
	return {"atk_dmg": h.atk_dmg, "atk_ang": h.atk_ang, "atk_c": h.atk_c, "prev_dmg": h.prev_dmg, "prev_ang": h.prev_ang, "prev_r": h.prev_r, "prev_c": h.prev_c, "hit_dmg": h.hit_dmg}


## 换上快照（返回原值，执行完 hw_pop 还原）
static func hw_push(o, snap: Dictionary) -> Dictionary:
	if snap.is_empty() or not hw_on(o):
		return {}
	var keep := hw_snap(o)
	o.hw.merge(snap, true)
	return keep


static func hw_pop(o, keep: Dictionary) -> void:
	if not keep.is_empty():
		o.hw.merge(keep, true)


static func hw_off(b: Dictionary) -> Vector2:
	var v = b.get("origin_off", null)
	return Vector2(float(v[0]), float(v[1])) if v is Array and v.size() == 2 else Vector2.ZERO


## face：布尔，或条件串（缓存解析结果）
static func hw_face_ok(o, v) -> bool:
	if v is bool:
		return v
	if v is Dictionary:
		return cond_true(o, v)
	if not (v is String):
		return false
	var cc: Dictionary = hw_st(o).cc
	if not cc.has(v):
		cc[v] = parse_cond(v, o.def.get("base", {}))
	return cond_true(o, cc[v])


# ---------------------------------------------------------------- 连斩（attack.combo / trig.on_combo_end）

## 普攻出手后（data_operator._release 末尾）：第 1 段成立就排进延迟队列，否则这一击就是收尾
static func hw_combo_start(o) -> void:
	var a: Dictionary = o.B.get("attack", {})
	if not a.has("combo"):
		return
	_hw_combo_from(o, a.combo, 0)


static func _hw_combo_from(o, cb: Array, k: int) -> void:
	if k < cb.size() and cond_true(o, cb[k].get("cond", {})):
		o.pending.append({"t": float(cb[k].get("delay", 0.12)), "do": cb[k].get("do", []), "combo": k, "bs": hw_snap(o)})
	else:
		hw_combo_end(o)


## 第 k 段执行完（data_operator._tick_pending）：下一段 / 收尾
static func hw_combo_next(o, k: int) -> void:
	_hw_combo_from(o, o.B.get("attack", {}).get("combo", []), k + 1)


static func hw_combo_end(o) -> void:
	for t in o._trigs():
		if str(t.get("_tag", "")) == "trig.on_combo_end" and cond_true(o, t.get("cond", {})):
			o._exec_list(t.get("do", []))


# ---------------------------------------------------------------- 每帧（data_operator.update：技能计时之后、延迟队列之前）

## 返回 true = 本帧不再起手（手写干员的「这件事没做完就 return」）
static func hw_tick(o, dt: float) -> bool:
	if not hw_on(o):
		return false
	var h: Dictionary = o.hw
	var b3 := false
	if h3_on(o):   # 手写迁移段第 3 批（各人手写 update 的先后；true = 本帧不起手：替身在场 / 倒下中）
		b3 = h3_tick(o, dt)
	if h4_on(o):   # 手写迁移段第 4 批（true = 本帧不起手：跃空锤在空中）
		b3 = h4_tick(o, dt) or b3
	if h.has("anchor"):   # 乌尔比安段：计时 → 锚 → 掀飞（手写 update 开头的先后）
		_hw4_tick(o, dt)
	if not h.waves.is_empty():
		_hw_waves(o, dt)
	if h.has("bolts"):   # 逻各斯段：锁定 → 咒域（手写 update 的先后：锁定、咒域、地面咒文、咒文弹）
		if not h.lock.is_empty():
			_hw3_lock(o, dt)
		if not h.fan.is_empty():
			_hw3_fan(o, dt)
	var busy := false
	if h.has("shells"):   # 艾雅法拉段：地面 / 点燃 / 抛射 / 后续弹 / 喷发；喷发序列期间不起手
		busy = _hw2_tick(o, dt)
	if h.has("bolts"):
		_hw3_bolts(o, dt)
	if h.has("links"):   # 精英化第 2 批段：咒文链、低弧抛射、掷锚
		_hw5_tick(o, dt)
	return busy or b3


## 延迟队列之后、起手之前再问一次：这件事没做完就不起手（锚在外面）
static func hw_busy(o) -> bool:
	return hw4_busy(o)


## 技能上层（data_operator._draw_skill_over）
static func hw_draw_over(o) -> void:
	hw_draw_shells(o)
	if o.hw.has("links"):   # 精英化第 2 批段
		hw_draw_lobs(o)
		hw_draw_links(o)
		hw_draw_runes(o)
		hw_draw_hooks(o)
	if o.hw.has("anchor"):
		hw_draw_tether(o)
	if o.hw.has("bolts"):
		hw_draw_logos_over(o)
	h3_draw_over(o)   # 手写迁移段第 3 批
	if h4_on(o):
		h4_draw_over(o)   # 手写迁移段第 4 批


## 区域层（data_operator.draw_auras）
static func hw_draw_auras(o) -> void:
	h3_draw_auras(o)   # 手写迁移段第 3 批
	if h4_on(o):
		h4_draw_auras(o)   # 手写迁移段第 4 批
	hw_draw_pulse_ring(o)
	hw_draw_look(o, "auras")
	if o.hw.has("fan"):
		hw_draw_fan(o)


## 地面层（data_operator.draw_entities_floor）
static func hw_draw_floor(o) -> void:
	h3_draw_floor(o)   # 手写迁移段第 3 批
	if h4_on(o):
		h4_draw_floor(o)   # 手写迁移段第 4 批
	if o.hw.has("links"):
		hw_draw_melt(o)
	hw_draw_waves(o)
	hw_draw_pools(o)
	hw_draw_rune_floor(o)


## 本体前后（data_operator.draw_body）
static func hw_draw_body(o, front: bool) -> void:
	if not front:
		hw_draw_look(o, "body")
	if o.hw.has("fan"):
		hw_draw_fan_body(o, front)


# ---------------------------------------------------------------- 瞬时（data_operator._exec_list 缺省分支）

static func hw_exec(o, b: Dictionary, at: Vector2) -> void:
	match str(b.get("_tag", "")):
		"shape.wave":
			hw_wave_start(o, b)
		"shape.shell":
			hw_shell_fire(o, b, false)
		"verb.lob":
			hw_lob(o, b, at)
		"verb.affect":
			hw_affect(o, b, at)
		"shape.pool":
			hw_pool(o, b, at)
		"shape.bolt":
			hw_bolt_fire(o, b, false)
		"shape.hit":
			hw_shape_hit(o, b)
		"verb.execute":
			hw_execute(o, b)
		"verb.lock":
			hw_lock_start(o, b)
		"verb.fan":
			hw_fan_start(o, b)
		"verb.tether":
			hw_tether_start(o, b)
		"verb.stack":
			hw_stack(o, b)
		"verb.arm":
			hw_arm(o, b)
		"verb.timer":
			hw_timer(o, b)
		"verb.link":
			hw_link(o, b)
		"shape.hookshot":
			hw_hook_start(o, b)
		_:
			h3_exec(o, b, at)   # 手写迁移段第 3 批
			if h4_on(o):
				h4_exec(o, b, at)   # 手写迁移段第 4 批


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
		if str(b.get("aim", "")) == "nearest":
			var ts: Array = o.nearest_enemies(1, float(b.get("aim_r", 260.0)), o.pos)
			if not ts.is_empty():
				ang = (ts[0].pos - o.pos).angle()
		var ov = b.get("off", [0, 0])
		var from0: Vector2 = o.pos + Vector2(float(ov[0]), float(ov[1]))
		if b.has("release_fx"):
			fx_play(o, b.release_fx, o.pos, 30.0, [], ang)
		var shared := {}   # fan_once：同一轮的几道共用命中表，一名敌人每轮只吃一道
		for fd in b.get("fan", [0]):
			var d2 := Vector2.from_angle(ang + deg_to_rad(float(fd)))
			if h.waves.size() >= int(b.get("cap", HW_WAVE_MAX)):
				h.waves.pop_front()
			h.waves.append({"b": b, "pos": from0, "dir": d2, "dist": 0.0, "max": float(b.get("dist", 200.0)), "w": float(b.get("w", 140.0)), "dmg": dmg,
				"hit": shared if b.get("fan_once", false) else {}, "drop": 0.0})
		return
	var dir := Vector2.from_angle(float(h.prev_ang))
	var from: Vector2 = o.pos + dir * float(h.prev_r) * float(b.get("along", 0.45))
	if h.waves.size() >= int(b.get("cap", HW_WAVE_MAX)):
		h.waves.pop_front()
	h.waves.append({"b": b, "pos": from, "dir": dir, "dist": 0.0, "max": float(b.get("dist", 200.0)), "w": float(b.get("w", 140.0)), "dmg": dmg, "hit": {}, "drop": 0.0})


static func _hw_waves(o, dt: float) -> void:
	var g = o.g
	var h: Dictionary = o.hw
	for w in h.waves:
		var b: Dictionary = w.b
		var step: float = float(b.get("speed", 480.0)) * dt
		w.pos += w.dir * step
		w.dist += step
		var nrm: Vector2 = w.dir.orthogonal()
		var depth: float = float(b.get("depth", 18.0))
		for j in o.query_ids(w.pos, w.w * 0.5 + 40.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or w.hit.has(e.id):
				continue
			var rel: Vector2 = e.pos - w.pos
			if absf(rel.dot(w.dir)) > depth + e.r or absf(rel.dot(nrm)) > w.w * 0.5 + e.r:
				continue
			w.hit[e.id] = true
			o.log_hit(str(b.get("src", "")), b.get("tags", []))
			o.deal_damage(e, w.dmg)
			if not e.dead and not e.boss:
				e.kb += w.dir * float(b.get("kb", 0.0)) * (0.3 if e.elite else 1.0)
			if b.has("hit_fx"):   # 精英化第 2 批段：潮刃命中的浪花
				fx_play(o, b.hit_fx, e.pos + Vector2(0, -float(e.r) * 0.5), float(e.r), [e], w.dir.angle())
		w.drop -= dt
		if w.drop <= 0.0 and not b.has("proj"):   # 浪尖甩出的水沫（画面，g.vrng；弹体式的潮刃不甩）
			w.drop = 0.03
			var l: float = g.vrng.randf_range(-0.5, 0.5) * w.w
			var mc: Color = _mf_col(b.get("foam", []), Color(0.8, 0.95, 1.0))
			o.fx({"kind": "mote", "pos": w.pos + nrm * l + Vector2(0, -18), "vel": w.dir * 120.0 + Vector2(0, g.vrng.randf_range(-120, -60)), "life": 0.4, "col": mc, "sz": 2.0, "grav": 320.0})
	h.waves = h.waves.filter(func(w): return w.dist < w.max)


## 地面层（data_operator.draw_entities_floor）：浪墙。有帧条（tex，朝右、底部锚点 anchor）时沿浪墙排三朵浪，帧按推进进度走完；缺图画程序浪墙
static func hw_draw_waves(o) -> void:
	if not hw_on(o) or o.hw.waves.is_empty():
		return
	var g = o.g
	var cv = o.cv
	for w in o.hw.waves:
		var b: Dictionary = w.b
		if b.has("proj"):   # 精英化第 2 批段：弹体式（潮刃）——旋转的弹体帧条，缺图画程序新月
			var pn: String = str(b.proj)
			var pa: float = clampf((w.max - w.dist) / 40.0, 0.0, 1.0)
			var pp: Vector2 = w.pos + Vector2(0, -16)
			if g.tex.get(pn) != null and g.V6_FRAMES.has(pn):
				var spec: Array = g.V6_FRAMES[pn]
				fx_frame(cv, g, pn, int(spec[0]), int(float(g.t) * float(spec[1])), pp, g.PX * float(b.get("proj_scale", 1.0)), Color(1, 1, 1, pa), Vector2(-1, -1), w.dir.angle())
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
		_hw_slam_fx(o, ctx.get("c", o.pos), float(ctx.get("r", 0.0)) * float(f.slam.get("r_mult", 1.0)), float(f.slam.get("k", 1.0)))
	elif f.has("whirl"):   # 锁链带锚甩一整圈（以本干员为心）
		o.ground_dust(o.pos, 48.0, 12)
		o.fx({"kind": "whirl", "pos": o.pos, "r": float(ctx.get("r", 0.0)), "life": float(f.whirl.get("life", 0.32)), "a0": o.g.vrng.randf() * TAU, "dir": float(o.face)})


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
		for f in e.b.get("fx", []):
			if not (f is Dictionary) or not f.has("aura_ring") or not fx_on(o, f):
				continue
			var rv: Dictionary = f.aura_ring
			var r: float
			if str(rv.get("r", "attack")) == "attack":
				r = shape_radius(o, o.cur_attack())
			else:
				r = float(rv.r)
			var c: Vector2 = g.ppos if str(f.get("at", "self")) == "leader" else o.pos
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


## blocks.attack 的追加字段
static func _hw_attack(atk: Dictionary, ctx: Dictionary) -> void:
	var errs: Array = ctx.errs
	_num(atk, "first", "blocks.attack", ctx, false, 0.0, 30.0)
	_num(atk, "idle", "blocks.attack", ctx, false, 0.0, 5.0)
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
	if b.has("ring") and not (b.ring is bool):
		errs.append(p + ".ring 只能是 true / false")
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
		return _hw2_block(b, p, kind, ctx, tag)
	if tag in HW3_TAGS:
		return _hw3_block(b, p, kind, ctx, tag)
	if tag in HW4_TAGS:
		return _hw4_block(b, p, kind, ctx, tag)
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
			_num(b, "aim_r", p, ctx, false, 1.0, 1000.0)
			if b.has("from") and not str(b.from) in ["prev", "self"]:
				errs.append(p + ".from 只能是 prev / self")
			if b.has("fan") and (not (b.fan is Array) or b.fan.is_empty() or b.fan.size() > 8):
				errs.append(p + ".fan 必须是 1–8 个偏角（度）的数组")
			if b.has("proj") and not str(b.proj).begins_with("proj_"):
				errs.append(p + ".proj 必须是 proj_* 帧条名")
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


# ---------------------------------------------------------------- 艾雅法拉段（手写迁移段续）：法术弹 / 抛射火团 / 点燃 / 易伤 / 地面熔岩 / 连续喷发
# shape.shell   直线法术弹（game 的 fire 子弹，命中即在 aoe 内爆炸）：普攻（手动 A 类：自动 = 射程内视线优先的最近敌人，手动 = aim_land）或技能 do。
#               伤害 = base × mult [× 技能强度]（出手时）× 加成（发射时）；follow：后续弹（第一条 cond 成立的：n 发、每 gap 秒一发，打首发目标以外的敌人，
#               不够就在首发目标两侧偏开 side）；on_explode：爆炸后执行的瞬时积木（center: target = 爆点，basis hit = 这一弹的伤害，r: hit = 爆炸半径）。
#               次数型技能（dur.next_n）的 attack_patch 可写 power / aoe_mult / on_explode（追加在本体之后）。tip / tip_skill：出手点（脚底为原点、朝右）。
# verb.lob      抛射火团（瞬时）：从 at（+ from_off）抛到 n 个落点，飞 clamp(距离 / 420, 0.25, 0.6) 秒（h > 80 再 + 0.2），落地 r 内 area_hit；同时 ≤ 12 个。
#               pick：near_out（at 附近 cand 个里离 at 超过 aoe × out_k 的，凑不够在 aoe × pad_k 处随机方向补，g.rng）/ shuffle（cand 个打乱取 n，g.rng）/
#               ring（随机起始角均分 n 个、距 aoe × ring_k，g.rng）。伤害 basis × mult，或不写 basis 时 base × mult × 加成 [× 技能强度]
# verb.affect   瞬时：center 半径 r（数字 × op_range，或 hit = 爆炸半径）内活着的敌人逐个吃 on_hit 里的状态（不伤害、不登记命中）
# st.burn       点燃：dur 秒内每 every 秒（按剩余时间跨过 every 的整数倍时）受到 basis × mult × every 的伤害（src；不乘 vs_elite）；Boss 也吃；同一敌人可叠多条
# st.fragile    易伤：dur 秒（敌人 aura_weak，受到的伤害 +10%，取较长）；kind: arts = 受到的法术伤害 + value（melt，同名取最高、不叠层；Boss 也吃）
# shape.pool    地面持续伤害区（瞬时生成）：center 处半径 r（× op_range × r_mult，生成时定），dur 秒，每 every 秒对区内 area_hit；伤害生成时定
#               （basis × mult，或 base × mult × 加成 [× 技能强度]）。tick0：首跳计时（0 = 下一帧）；accum：到点 += every（否则重置为 every）；
#               tail：剩余时间低于它不再跳（缺省不限）；group / group_cap / max：同组（例：铭文 + 墓志铭）同时上限，满了先挤掉同组最早的；
#               burst：只在到时那一下炸一次（墓志铭）。look：lava / rune（画法）
# 技能外壳：cast: instant（充满当帧直接生效、不播技能动作，手写「炽热」）；dur.pulses {pulses, every} + pulse {pick, r, pad, jit, delay, fx, do}
#           （连续喷发：每 every 秒在 (r + pad) × op_range 内敌群最密处 ± jit（g.rng）标一处，delay 秒后以它为 target 执行 do；喷发期间不起手、不放别的技能）；
#           技能积木 aim: los（起手朝普攻射程 + aim_pad 内视线优先的最近敌人）

const HW2_TAGS := ["shape.shell", "verb.lob", "verb.affect", "st.burn", "st.fragile", "shape.pool"]
const HW_LOB_MAX := 12
const HW_POOL_MAX := 32
const HW_LOB_PICKS := ["near_out", "shuffle", "ring"]
const HW_ORANGE := Color(1.0, 0.5, 0.2)
const HW_LAVA := Color(0.95, 0.3, 0.08)


static func _hw2(o) -> Dictionary:
	var h := hw_st(o)
	if not h.has("shells"):
		h.merge({"shells": [], "lobs": [], "pools": [], "burns": [], "erupts": [], "pulse": {}, "hit_r": 0.0, "pg": {}})
	return h


## 普攻 / 技能里的法术弹：出手点（tip / tip_skill，x 随朝向）
static func hw_tip(o, b: Dictionary) -> Vector2:
	var v = b.get("tip_skill", b.get("tip", [0, -40])) if str(o.act_kind) == "skill" else b.get("tip", [0, -40])
	return o.pos + Vector2(float(v[0]) * float(o.face), float(v[1]))


## 爆炸半径：aoe × op_range × aoe_mults（cond 成立的依次乘，例：精一天赋 ×1.25）
static func hw_aoe(o, b: Dictionary) -> float:
	var r: float = float(b.get("aoe", 50.0)) * o.stat(&"op_range")
	for m in b.get("aoe_mults", []):
		if cond_true(o, m.get("cond", {})):
			r *= float(m.get("mult", 1.0))
	return r


## 普攻起手点（data_operator.update 的 shell 分支）
static func hw_shell_aim(o, a: Dictionary) -> Vector2:
	var reach: float = float(a.get("range", 290.0)) * o.stat(&"op_range")
	return o.atk_point(o.los_targets(1, reach, o.pos), reach)


## 出手（普攻 is_atk = true / 技能 do）：选目标 → 次数型技能补丁 → 发射 → 后续弹排队
static func hw_shell_fire(o, b: Dictionary, is_atk: bool) -> void:
	var g = o.g
	var h := _hw2(o)
	var ts: Array
	if is_atk and o.atk_aim != Vector2.ZERO:
		ts = [o.aim_land(float(b.get("range", 290.0)) * o.stat(&"op_range"))]
	else:
		ts = o.los_targets(1, (float(b.get("range", 290.0)) + float(b.get("fire_pad", 40.0))) * o.stat(&"op_range"), o.pos)
	if ts.is_empty():
		return
	var patch := {}
	if is_atk:
		var sk: Array = o.B.get("skills", [])
		for i in 3:
			if o.ammo[i] > 0 and i < sk.size():
				o.ammo[i] -= 1
				patch = sk[i].get("attack_patch", {})
				break
	var pre: float = o.base(str(b.get("atk_key", "atk")), 0.0) * float(b.get("mult", 1.0))
	if b.get("power", false) or patch.get("power", false):
		pre *= o.skill_power()
	var aoe: float = hw_aoe(o, b) * float(b.get("aoe_mult", 1.0))
	if patch.has("aoe_mult"):
		aoe *= float(patch.aoe_mult)
	var oe: Array = b.get("on_explode", []) + patch.get("on_explode", [])
	if b.has("lob") and cond_true(o, b.lob.get("cond", {})):   # 精英化第 2 批段：低弧抛射三角落点 + 熔池（取代直线弹与后续弹）
		hw_lob_volley(o, b, hw_tip(o, b), ts[0].pos, pre, aoe, oe)
		if b.has("fire_fx"):
			fx_play(o, b.fire_fx, hw_tip(o, b), 10.0)
		return
	_hw_cast(o, b, hw_tip(o, b), ts[0].pos, pre, aoe, 1.0, oe, not is_atk)
	var tip: Vector2 = hw_tip(o, b)   # 发射时可能转了身：后续弹与出手光按转身后的出手点（同手写）
	if b.has("fire_fx"):
		fx_play(o, b.fire_fx, tip, 10.0)
	for f in b.get("follow", []):
		if not cond_true(o, f.get("cond", {})):
			continue
		var n: int = int(f.get("n", 1))
		var tos: Array = _hw_extra_targets(o, b, ts[0], n)
		for k in n:
			h.shells.append({"t": float(f.get("gap", 0.12)) * (k + 1), "to": tos[k], "pre": pre * float(f.get("mult", 1.0)), "aoe": aoe * float(f.get("aoe_mult", 1.0)),
				"sz": float(f.get("sz", 1.0)), "oe": oe, "b": b, "tip": tip - o.pos})
		break


## 后续弹的落点：首发目标之外最近的敌人（视线优先）；不够就在首发目标两侧垂直偏开 side（交替）
static func _hw_extra_targets(o, b: Dictionary, first: Dictionary, n: int) -> Array:
	var out: Array = []
	for e in o.los_targets(n + 3, (float(b.get("range", 290.0)) + float(b.get("fire_pad", 40.0))) * o.stat(&"op_range"), o.pos):
		if e.id != first.id and out.size() < n:
			out.append(e.pos)
	var side: Vector2 = (first.pos - o.pos).normalized().orthogonal() * float(b.get("side", 40.0))
	var k := 0
	while out.size() < n:
		out.append(first.pos + side * (1.0 if k % 2 == 0 else -1.0))
		k += 1
	return out


## 发射一弹（game 的 fire 子弹：hidden，弹体由本干员画；爆炸后回调 data_operator.bullet_exploded）
static func _hw_cast(o, b: Dictionary, from: Vector2, target: Vector2, pre: float, aoe: float, sz: float, oe: Array, sfx: bool) -> void:
	var g = o.g
	var d: Vector2 = (target - from).normalized()
	if absf(d.x) > 0.01:
		o._set_face(signf(d.x))
	g.bullets.append({"kind": "fire", "pos": from, "vel": d * float(b.get("speed", 360.0)), "dmg": pre * o._dmg_bonus(), "life": float(b.get("life", 1.3)), "r": float(b.get("r", 8.0)) * sz,
		"aoe": aoe, "src": str(b.get("src", "")), "op": o.id, "on_hit": o, "burn": false, "weak": 0.0, "fx_col": _mf_col(b.get("col", []), HW_ORANGE), "hidden": true,
		"etrail": 0.0, "sz": sz, "hw_b": b, "hw_oe": oe})
	if sfx:
		o._sfx_op("atk")


## fire 子弹爆炸后（weapons.gd → data_operator.bullet_exploded）：爆点画面，然后执行 on_explode（target = 爆点，basis hit = 这一弹伤害，r: hit = 爆炸半径）
static func hw_shell_boom(o, bl: Dictionary) -> void:
	var g = o.g
	var b: Dictionary = bl.get("hw_b", {})
	var h := _hw2(o)
	if b.has("boom_fx"):
		fx_play(o, b.boom_fx, bl.pos, float(bl.aoe))
	var keep := hw_snap(o)
	var kr: float = float(h.hit_r)
	h.hit_dmg = float(bl.dmg)
	h.hit_r = float(bl.aoe)
	o._exec_list(bl.get("hw_oe", []), bl.pos)
	hw_pop(o, keep)
	h.hit_r = kr


# ---------------------------------------------------------------- verb.lob / verb.affect / st.burn / st.fragile / shape.pool 的执行

static func hw_lob(o, b: Dictionary, at: Vector2) -> void:
	var g = o.g
	var h := _hw2(o)
	if at == Vector2.INF:
		at = o.pos
	var fv = b.get("from_off", [0, 0])
	var from: Vector2 = at + Vector2(float(fv[0]), float(fv[1]))
	var dmg: float
	if b.has("basis"):
		dmg = hw_basis(o, str(b.basis)) * float(b.get("mult", 1.0))
	else:
		dmg = o.base(str(b.get("atk_key", "atk")), 0.0) * float(b.get("mult", 1.0)) * float(o.loc.dmg) * o._dmg_bonus()
		if b.get("power", false):
			dmg *= o.skill_power()
	var aoe: float = float(h.hit_r)
	var n: int = int(b.get("n", 2))
	var tos: Array = []
	match str(b.get("pick", "near_out")):
		"near_out":
			for e in o.nearest_enemies(int(b.get("cand", 6)), float(b.get("reach", 200.0)), at):
				if e.pos.distance_to(at) > aoe * float(b.get("out_k", 0.6)) and tos.size() < n:
					tos.append(e.pos)
			while tos.size() < n:
				tos.append(at + Vector2.from_angle(g.rng.randf() * TAU) * aoe * float(b.get("pad_k", 1.5)))
		"shuffle":
			var mc: Array = o.nearest_enemies(int(b.get("cand", 10)), float(b.get("reach", 320.0)), at)
			o.shuffle_rng(mc)
			for k in mini(n, mc.size()):
				tos.append(mc[k].pos)
		"ring":
			var a0: float = g.rng.randf() * TAU
			for k in n:
				tos.append(at + Vector2.from_angle(a0 + k * TAU / float(n)) * aoe * float(b.get("ring_k", 1.4)))
	var hh: float = float(b.get("h", 30.0))
	var lk = b.get("look", null)
	if lk is Dictionary and lk.get("burst", false) and not tos.is_empty():
		_hw_lob_burst(o, from, float(b.get("sz", 1.0)))
	for p in tos:
		if h.lobs.size() >= HW_LOB_MAX:
			break
		var dur: float = clampf(from.distance_to(p) / 420.0, 0.25, 0.6) + (0.2 if hh > 80.0 else 0.0)
		h.lobs.append({"b": b, "from": from, "to": p, "t": 0.0, "dur": dur, "dmg": dmg, "r": float(b.get("r", 30.0)), "src": str(b.get("src", "")), "h": hh,
			"sz": float(b.get("sz", 1.0)), "trail": 0.0, "spin": signf(p.x - from.x) if absf(p.x - from.x) > 1.0 else 1.0})


## 熔岩块喷起的原点（10-14 用户「火山喷发的感觉」，纯画面，g.vrng）：白热闪光 + 一束向上猛喷的火星 + 几缕黑烟
static func _hw_lob_burst(o, at: Vector2, sz: float) -> void:
	var g = o.g
	o.fx({"kind": "glow", "pos": at + Vector2(0, -6), "r": 16.0 * sz, "life": 0.14, "col": Color(2.4, 1.4, 0.5), "alpha": 0.85})
	o.fx({"kind": "lava_spout", "pos": at, "r": 9.0 * sz, "h": 54.0 * sz, "life": 0.22})
	for k in 7:
		o.fx({"kind": "spark", "pos": at + Vector2(g.vrng.randf_range(-4, 4), -4), "vel": Vector2(g.vrng.randf_range(-55, 55), g.vrng.randf_range(-330, -200)),
			"life": g.vrng.randf_range(0.22, 0.34), "col": HW_ORANGE if k % 2 == 0 else Color(2.2, 1.5, 0.6), "sz": 2.5})
	for k in 3:
		o.fx({"kind": "mote", "pos": at + Vector2(g.vrng.randf_range(-6, 6), -8), "vel": Vector2(g.vrng.randf_range(-12, 12), g.vrng.randf_range(-70, -45)),
			"life": 0.5, "col": Color(0.16, 0.1, 0.09), "sz": 4.0})


static func hw_affect(o, b: Dictionary, at: Vector2) -> void:
	var c: Vector2 = field_center(o, b, at)
	if c == Vector2.INF:
		return
	var rv = b.get("r", "hit")
	var r: float = float(_hw2(o).hit_r) if str(rv) == "hit" else float(rv) * o.stat(&"op_range")
	for e in o.arc_targets(c, 0.0, PI, r):
		if e.dead:
			continue
		for s in b.get("on_hit", []):
			apply_status(o, e, s, c)


## apply_status 转来：本段的状态（Boss 也吃，所以在「Boss 缺省不受」之前截下）。返回 true = 已处理
static func hw_status(o, e: Dictionary, s: Dictionary) -> bool:
	match "st." + str(s.get("st", "")):
		"st.burn":
			var dps: float = hw_basis(o, str(s.get("basis", "hit"))) * float(s.get("mult", 0.1))
			_hw2(o).burns.append({"e": e, "t": float(s.dur), "dps": dps, "ft": 0.0, "s": s})
			return true
		"st.requiem":   # 逻各斯段：安魂（直接覆盖剩余时间，同手写）
			e["requiem_v"] = float(o.base("requiem_bonus", 0.15))   # 安魂增伤读 base.requiem_bonus（10-14 起不再写死 15%）
			if o.hw.has("rq") and hw_requiem_stack(o, e, s):   # 精英化第 2 批段：叠层安魂（剜魂）
				return true
			e["requiem"] = float(s.dur)
			return true
		"st.fragile":
			if str(s.get("kind", "")) == "arts":
				var g = o.g
				var mv: float = float(e.get("melt_v", 0.0)) if float(e.get("melt_t", 0.0)) > float(g.t) else 0.0
				e["melt_t"] = maxf(float(e.get("melt_t", 0.0)), float(g.t) + float(s.dur))
				e["melt_v"] = maxf(mv, float(s.get("value", 0.08)))
				if s.has("fx"):
					fx_play(o, s.fx, e.pos, float(e.r), [e])
				if s.has("look"):   # 精英化第 2 批段：脚下裂纹（熔蚀）
					hw_melt_mark(o, e, s)
			else:
				e["aura_weak"] = maxf(float(e.get("aura_weak", 0.0)), float(s.dur))
			return true
	return false


static func hw_pool(o, b: Dictionary, at: Vector2) -> void:
	var h := _hw2(o)
	var c: Vector2 = field_center(o, b, at)
	if c == Vector2.INF:
		return
	var grp: String = str(b.get("group", ""))
	if b.has("max") and grp != "":
		var same := 0
		for q in h.pools:
			if q.b == b:
				same += 1
		if same >= int(b.max):
			return
	if grp != "" and b.has("group_cap"):   # 同组满了：先挤掉同组里最早的、可挤的（evict: true 的）
		var cap: int = int(b.group_cap)
		while true:
			var gq: Array = h.pools.filter(func(q): return str(q.b.get("group", "")) == grp)
			if gq.size() < cap:
				break
			var ev: Array = gq.filter(func(q): return q.b.get("evict", false))
			if ev.is_empty():
				return
			h.pools.erase(ev[0])
	var r: float = shape_radius(o, b)
	var dmg: float
	if b.has("basis"):
		dmg = hw_basis(o, str(b.basis)) * float(b.get("mult", 1.0))
	else:
		dmg = o.base(str(b.get("atk_key", "atk")), 0.0) * float(b.get("mult", 1.0)) * float(o.loc.dmg) * o._dmg_bonus()
		if b.get("power", false):
			dmg *= o.skill_power()
	if h.pools.size() >= HW_POOL_MAX:
		h.pools.pop_front()
	var dur: float = float(b.get("dur", 1.0))
	h.pools.append({"b": b, "pos": c, "r": r, "t": dur, "dur": dur, "tick": float(b.get("tick0", 0.0)), "dmg": dmg, "bub": 0.0, "pat": o.g.vrng.randi()})


# ---------------------------------------------------------------- 每帧（hw_tick 转来，手写 update 的先后：地面 → 点燃 → 弹体尾迹 → 抛射 → 后续弹 → 喷发落点 → 喷发序列）

static func _hw2_tick(o, dt: float) -> bool:
	var g = o.g
	var h: Dictionary = o.hw
	if not h.pools.is_empty():
		for l in h.pools:   # 第一遍：持续跳伤的（手写：先铭文 / 熔岩池）
			var b: Dictionary = l.b
			if b.get("burst", false):
				continue
			l.t -= dt
			l.tick -= dt
			l.bub -= dt
			if l.tick <= 0.0 and l.t > float(b.get("tail", -INF)):
				l.tick = (l.tick + float(b.every)) if b.get("accum", false) else float(b.every)
				o.area_hit(str(b.get("src", "")), l.pos, l.r, l.dmg, 0.0, 0.0, b.get("tags", []))
			if str(b.get("look", "")) == "lava" and l.bub <= 0.0 and l.t > 0.4:   # 熔岩冒泡（画面，g.vrng）
				l.bub = 0.18
				var a: float = g.vrng.randf() * TAU
				var rr: float = g.vrng.randf() * l.r * 0.8
				o.fx({"kind": "mote", "pos": l.pos + Vector2(cos(a) * rr, sin(a) * rr * 0.55), "vel": Vector2(0, -28), "life": 0.55, "col": HW_ORANGE, "sz": 2.0})
		for l in h.pools:   # 第二遍：到时炸一次的（手写：再墓志铭）
			var b2: Dictionary = l.b
			if not b2.get("burst", false):
				continue
			l.t -= dt
			if l.t <= 0.0:
				o.area_hit(str(b2.get("src", "")), l.pos, l.r, l.dmg, float(b2.get("kb", 0.0)), 0.0, b2.get("tags", []))
				if b2.has("fx"):
					fx_play(o, b2.fx, l.pos, l.r)
		h.pools = h.pools.filter(func(l): return l.t > 0.0)
	if not h.burns.is_empty():
		for bu in h.burns:
			var s: Dictionary = bu.s
			bu.t -= dt
			bu.ft -= dt
			if bu.e.dead:
				bu.t = 0.0
				continue
			if bu.ft <= 0.0:   # 火舌（画面）
				bu.ft = 0.14
				o.fx({"kind": "flame", "pos": bu.e.pos + Vector2(g.vrng.randf_range(-bu.e.r * 0.5, bu.e.r * 0.5), -bu.e.r * 0.4), "vel": Vector2(0, -20), "life": 0.3, "col": HW_ORANGE, "sz": 9.0})
			var ev: float = float(s.get("every", 0.5))
			var k: float = 1.0 / ev
			if int((bu.t + dt) * k) != int(bu.t * k):
				o.log_hit(str(s.get("src", "")), s.get("tags", []))
				o.deal_damage(bu.e, bu.dps * ev)
		h.burns = h.burns.filter(func(bu): return bu.t > 0.0)
	for bl in g.bullets:   # 自己的法术弹：火星尾（画面）
		if bl.life <= 0.0 or bl.get("op", "") != o.id or bl.kind != "fire" or not bl.has("hw_b"):
			continue
		bl.etrail = float(bl.get("etrail", 0.0)) - dt
		if bl.etrail <= 0.0:
			bl.etrail = 0.04
			o.fx({"kind": "spark", "pos": bl.pos - bl.vel.normalized() * 6.0, "vel": -bl.vel * 0.12 + Vector2(g.vrng.randf_range(-20, 20), g.vrng.randf_range(-30, 10)), "life": 0.3, "col": HW_ORANGE, "sz": 3.0})
	if not h.lobs.is_empty():
		for l in h.lobs:
			l.t += dt
			l.trail -= dt
			var lk = l.b.get("look", null)
			if l.trail <= 0.0 and l.t < l.dur:
				if lk is Dictionary:   # 熔岩块：贴着块身的短火星拖尾（往飞行反方向甩、很快熄灭）
					l.trail = 0.035
					var lp: Vector2 = _hw_lob_pos(l)
					var back: Vector2 = (lp - _hw_lob_pos_at(l, maxf(0.0, l.t - 0.03))).normalized() * -40.0
					o.fx({"kind": "spark", "pos": lp + Vector2(g.vrng.randf_range(-2, 2), g.vrng.randf_range(-2, 2)), "vel": back + Vector2(g.vrng.randf_range(-15, 15), g.vrng.randf_range(-15, 5)),
						"life": 0.18, "col": HW_ORANGE if g.vrng.randf() < 0.6 else HW_LAVA, "sz": 2.0 * l.sz})
				else:
					l.trail = 0.05
					o.fx({"kind": "spark", "pos": _hw_lob_pos(l), "vel": Vector2(g.vrng.randf_range(-20, 20), g.vrng.randf_range(-20, 10)), "life": 0.25, "col": HW_ORANGE, "sz": 2.0 * l.sz})
			if l.t >= l.dur:
				o.area_hit(l.src, l.to, l.r, l.dmg)
				if lk is Dictionary:   # 熔岩块落地：一小下溅射闪光 + 碎块（纯画面）
					var ln: String = str(lk.get("land", ""))
					if ln != "":
						o.spawn_fx_sprite(ln, l.to + Vector2(0, -4), g.PX * float(lk.get("land_scale", 0.55)) * maxf(0.7, l.sz), 0.0, l.spin < 0.0)
					o.fx({"kind": "glow", "pos": l.to + Vector2(0, -3), "r": 14.0 * l.sz * float(lk.get("heavy", 1.0)), "life": 0.1, "col": Color(2.4, 1.5, 0.6), "alpha": 0.85})
					if float(lk.get("spot", 0.0)) > 0.0:   # 落点：地面一小块发红、0.3–0.5 秒褪去
						o.fx({"kind": "lava_spot", "pos": l.to, "r": l.r * 0.5, "life": float(lk.spot), "floor": true})
					if float(lk.get("heavy", 1.0)) > 1.0:   # 重落地：碎块四溅 + 贴地冲击环
						o.fx({"kind": "ring", "pos": l.to, "r": l.r * 0.9, "r0": l.r * 0.25, "life": 0.22, "col": Color(1.6, 0.6, 0.15), "floor": true, "w": 3.0})
						for q in 6:
							o.fx({"kind": "mote", "pos": l.to + Vector2(0, -4), "vel": Vector2(g.vrng.randf_range(-130, 130), g.vrng.randf_range(-190, -90)), "life": 0.42,
								"col": HW_LAVA if q % 2 == 0 else HW_ORANGE, "sz": 3.0, "grav": 520.0})
				o.fx({"kind": "ring", "pos": l.to, "r": l.r, "r0": l.r * 0.3, "life": 0.28, "col": HW_LAVA, "floor": true, "w": 2.0})
				o.fx({"kind": "glow", "pos": l.to, "r": l.r * 0.6, "life": 0.18, "col": Color(1.6, 0.8, 0.3), "alpha": 0.6})
				for k in (6 if l.sz >= 1.0 else 3):
					o.fx({"kind": "mote", "pos": l.to, "vel": Vector2(g.vrng.randf_range(-80, 80), g.vrng.randf_range(-140, -50)), "life": 0.4, "col": HW_LAVA, "sz": 2.0, "grav": 320.0})
				if l.sz >= 1.0:
					o.spawn_fx_sprite("fx_flam_hit", l.to + Vector2(0, -6), g.PX * clampf(l.r / 60.0, 0.6, 1.1))
		h.lobs = h.lobs.filter(func(l): return l.t < l.dur)
	if not h.shells.is_empty():
		for q in h.shells:
			q.t -= dt
			if q.t <= 0.0 and o.pos != Vector2.INF:
				_hw_cast(o, q.b, o.pos + q.tip, q.to, q.pre, q.aoe, q.sz, q.oe, true)
		h.shells = h.shells.filter(func(q): return q.t > 0.0)
	if not h.erupts.is_empty():
		for p in h.erupts:
			p.t -= dt
			if p.t <= 0.0:
				o._exec_list(p.do, p.pos)
		h.erupts = h.erupts.filter(func(p): return p.t > 0.0)
	if not h.pulse.is_empty():
		var pu: Dictionary = h.pulse
		if int(pu.n) <= 0:
			h.pulse = {}
			return false
		var sp: Dictionary = pu.sp
		pu.t -= dt
		if pu.t <= 0.0:
			pu.t = float(pu.every)
			pu.n = int(pu.n) - 1
			var rr: float = (float(sp.get("r", 290.0)) + float(sp.get("pad", 60.0))) * o.stat(&"op_range")
			var c: Vector2 = o.densest_point(rr, o.pos)
			if c == Vector2.INF:
				var ts: Array = o.nearest_enemies(1, rr, o.pos)
				if ts.is_empty():
					pu.n = 0
					return true
				c = ts[0].pos
			var jv = sp.get("jit", [0, 0])
			var at: Vector2 = c + Vector2(g.rng.randf_range(-float(jv[0]), float(jv[0])), g.rng.randf_range(-float(jv[1]), float(jv[1])))
			h.erupts.append({"pos": at, "t": float(sp.get("delay", 0.12)), "do": sp.get("do", [])})
			if sp.has("fx"):
				fx_play(o, sp.fx, at, 40.0, [], at.x * 0.02)
		return true
	return false


static func _hw_lob_pos(l: Dictionary) -> Vector2:
	return _hw_lob_pos_at(l, float(l.t))


## 飞行中 t 秒处的位置。look（熔岩块，10-14）：拱高 × apex_k、顶点提前到约 42%（k^0.8），落下比升起快，显得沉
static func _hw_lob_pos_at(l: Dictionary, t: float) -> Vector2:
	var k: float = clampf(t / l.dur, 0.0, 1.0)
	var lk = l.b.get("look", null)
	if lk is Dictionary:
		if lk.has("arc_pow"):
			return l.from.lerp(l.to, k) + Vector2(0, -pow(sin(k * PI), float(lk.arc_pow)) * l.h * float(lk.get("apex_k", 1.0)))
		return l.from.lerp(l.to, k) + Vector2(0, -sin(pow(k, 0.8) * PI) * l.h * float(lk.get("apex_k", 1.0)))
	return l.from.lerp(l.to, k) + Vector2(0, -sin(k * PI) * l.h)


## dur.pulses 的技能出手（data_operator._release_skill）：开喷发序列
static func hw_pulse_start(o, i: int, sb: Dictionary) -> void:
	var h := _hw2(o)
	var dv: Dictionary = sb.dur
	h.pulse = {"i": i, "n": int(dv.get("pulses", 10)), "every": float(dv.get("every", 0.2)), "t": 0.0, "sp": sb.get("pulse", {})}
	o.s_dur[i] = float(int(dv.get("pulses", 10))) * float(dv.get("every", 0.2))


## 技能剩余（data_operator.skill_active_left 转来）：喷发序列 = 剩余次数 × every；-1 = 本段不管
static func hw_active_left(o, i: int) -> float:
	if not hw_on(o):
		return -1.0
	if h4_on(o):   # 手写迁移段第 4 批：狐火迷雾 / 巨炮发数 / 钙质化
		var v4: float = h4_active_left(o, i)
		if v4 >= 0.0:
			return v4
	var pu = o.hw.get("pulse", {})
	if pu is Dictionary and not pu.is_empty() and int(pu.i) == i:
		return float(int(pu.n)) * float(pu.every)
	if o.hw.has("bolts"):
		return _hw3_left(o, i)
	if o.hw.has("anchor"):
		return _hw4_left(o, i)
	return -1.0


## cast: instant 的技能（data_operator.update 充满当帧）：扣技力、次数型技能装填、画面 / 飘字。返回 true = 已处理
static func hw_instant(o, i: int) -> bool:
	var sk: Array = o.B.get("skills", [])
	if i < 0 or i >= sk.size() or str(sk[i].get("cast", "")) != "instant":
		return false
	var sb: Dictionary = sk[i]
	o.spend_sp(i)
	var dv = sb.get("dur", 0)
	if dv is Dictionary and dv.has("next_attacks"):
		o.ammo[i] = int(dv.next_attacks)
	if sb.has("fx"):
		fx_play(o, sb.fx, o.pos, 30.0)
	o._exec_list(sb.get("do", []))
	return true


# ---------------------------------------------------------------- 画面

## 法术弹（g.bullets 里本干员的 fire 弹）与抛射火团（data_operator._draw_skill_over）
static func hw_draw_shells(o) -> void:
	var g = o.g
	var cv = o.cv
	for bl in g.bullets:
		if bl.life <= 0.0 or bl.get("op", "") != o.id or bl.kind != "fire" or not bl.has("hw_b"):
			continue
		var lk: Dictionary = bl.hw_b.get("look", {})
		var sz: float = float(bl.get("sz", 1.0))
		var fl := 1.0 + 0.15 * sin(g.t * 40.0 + bl.pos.x)
		cv.draw_circle(bl.pos, float(lk.get("glow", 13.0)) * fl * sz, Color(1.6, 0.6, 0.15, 0.22))
		var big: String = str(lk.get("big_tex", ""))
		if big != "" and g.tex.get(big) != null:
			cv.draw_circle(bl.pos, float(lk.get("glow2", 26.0)) * fl, Color(1.6, 0.5, 0.1, 0.25))
			o.draw_spr_rot(big, int(g.t * 14.0) % int(g.V6_FRAMES.get(big, [5])[0]), bl.pos - bl.vel.normalized() * float(lk.get("back", 14.0)), bl.vel.angle(), g.PX * float(lk.get("big_scale", 1.5)))
		elif g.tex.get(str(lk.get("tex", "proj_lavaball"))) != null:
			var tn: String = str(lk.get("tex", "proj_lavaball"))
			o.draw_spr_rot(tn, int(g.t * 12.0 + bl.pos.x * 0.05) % int(g.V6_FRAMES.get(tn, [6])[0]), bl.pos, bl.vel.angle(), g.PX * float(lk.get("scale", 1.1)) * sz)
		else:
			cv.draw_circle(bl.pos, 7.5 * fl * sz, Color(2.2, 0.9, 0.25, 0.9))
			cv.draw_circle(bl.pos, 3.5 * sz, Color(2.8, 2.4, 1.6))
	if not hw_on(o) or not o.hw.has("lobs"):
		return
	for l in o.hw.lobs:
		var p: Vector2 = _hw_lob_pos(l)
		var k: float = clampf(l.t / l.dur, 0.0, 1.0)
		cv.draw_set_transform(l.to, 0.0, Vector2(1.0, 0.5))
		cv.draw_circle(Vector2.ZERO, 5.0 * l.sz * (0.5 + 0.5 * k), Color(0.1, 0.03, 0.02, 0.35))
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var rr: float = 5.5 * l.sz
		var lk = l.b.get("look", null)
		if lk is Dictionary and g.tex.get(str(lk.get("tex", ""))) != null and g.V6_FRAMES.has(str(lk.get("tex", ""))):
			# 熔岩块（10-14 用户「小红点太抽象，改成小的熔岩块，保留力量感」）：暗红外晕 + 翻滚的熔岩块帧条
			var tn: String = str(lk.tex)
			cv.draw_circle(p, rr * 2.0, Color(1.6, 0.5, 0.1, 0.22))   # 外晕（同原来圆点的光晕，略收）
			if l.b.get("shell", false):
				cv.draw_circle(p, rr * 1.15, Color(0.4, 0.07, 0.03, 0.8))   # 熔岩天降：暗红壳
			var spec: Array = g.V6_FRAMES[tn]
			var mc: Color = _mf_col(lk.get("mod", []), Color(1.7, 1.35, 1.15))   # 提亮（HDR，进辉光），不然在暗处只剩一团褐色
			o.draw_spr_rot(tn, int(l.t * float(spec[1])) % int(spec[0]), p, l.t * float(lk.get("spin", 12.0)) * float(l.get("spin", 1.0)), g.PX * float(lk.get("scale", 0.75)) * l.sz, mc)
			continue
		cv.draw_circle(p, rr * 1.9, Color(1.6, 0.55, 0.12, 0.25))
		if l.b.get("shell", false):
			cv.draw_circle(p, rr * 1.2, Color(0.45, 0.08, 0.03, 0.95))
		cv.draw_circle(p, rr, Color(2.2, 0.8, 0.2, 0.95))
		cv.draw_circle(p, rr * 0.45, Color(2.8, 2.3, 1.4))


## 地面池（data_operator.draw_entities_floor）：look lava = 暗红椭圆 + 翻滚熔岩帧条
static func hw_draw_pools(o) -> void:
	if not o.hw.has("pools"):
		return
	var g = o.g
	var cv = o.cv
	for l in o.hw.pools:
		var b: Dictionary = l.b
		match str(b.get("look", "")):
			"lava":
				var a: float = clampf(l.t / 0.6, 0.0, 1.0)
				cv.draw_set_transform(l.pos, 0.0, Vector2(1.0, 0.55))
				cv.draw_circle(Vector2.ZERO, l.r, Color(0.7, 0.15, 0.03, 0.3 * a))
				cv.draw_circle(Vector2.ZERO, l.r * 0.6, Color(1.5, 0.55, 0.1, 0.22 * a + 0.06 * sin(g.t * 9.0 + l.pos.x)))
				cv.draw_arc(Vector2.ZERO, l.r, 0.0, TAU, 24, Color(1.8, 0.7, 0.2, 0.5 * a), 2.0)
				cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				if g.tex.get("fx_sunburst") != null:
					o.draw_spr_rot("fx_sunburst", int(g.t * 16.0 + l.pos.x * 0.1) % 16, l.pos + Vector2(0, -4), 0.0, l.r * 1.3 / 62.0, Color(1.0, 1.0, 1.0, 0.75 * a))
			"pool":   # Codex 熔池帧条（fx_eyja_lava_pool 这类循环地面件）：按半径缩放，缺图画 lava
				var tn: String = str(b.get("tex", ""))
				var a2: float = clampf(l.t / 0.3, 0.0, 1.0) * clampf((l.dur - l.t) / 0.12, 0.0, 1.0)
				if tn != "" and g.tex.get(tn) != null and g.V6_FRAMES.has(tn):
					var spec: Array = g.V6_FRAMES[tn]
					fx_frame(cv, g, tn, int(spec[0]), int((l.dur - l.t) * float(spec[1])), l.pos, l.r / float(b.get("fit", 22.0)), Color(1, 1, 1, a2 * float(b.get("alpha", 1.0))))
				else:
					cv.draw_set_transform(l.pos, 0.0, Vector2(1.0, 0.55))
					cv.draw_circle(Vector2.ZERO, l.r, Color(0.7, 0.15, 0.03, 0.35 * a2))
					cv.draw_arc(Vector2.ZERO, l.r, 0.0, TAU, 24, Color(1.8, 0.7, 0.2, 0.55 * a2), 2.0)
					cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 喷发期间脚下热浪环（draw_auras）
static func hw_draw_pulse_ring(o) -> void:
	if not o.hw.has("pulse") or o.hw.pulse.is_empty() or o.pos == Vector2.INF:
		return
	var g = o.g
	o.cv.draw_set_transform(o.pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
	o.cv.draw_arc(Vector2.ZERO, 56.0 + 6.0 * sin(g.t * 6.0), 0.0, TAU, 32, Color(HW_ORANGE.r, HW_ORANGE.g, HW_ORANGE.b, 0.35), 2.0)
	o.cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 程序粒子的画法（data_operator._draw_pfx → mf_draw_pfx 之后）：lava_pillar（熔岩柱）
static func hw_draw_pfx(o, f: Dictionary, a: float) -> bool:
	var cv = o.cv
	if str(f.kind).begins_with("h3_"):   # 手写迁移段第 3 批
		return h3_draw_pfx(o, f, a)
	if str(f.kind).begins_with("h4_"):   # 手写迁移段第 4 批
		return h4_draw_pfx(o, f, a)
	match str(f.kind):
		"whirl", "chain", "rift":   # 乌尔比安段
			return hw4_draw_pfx(o, f, a)
		"s1link":   # 逻各斯湮灭余伤传递：黑色咒文链从起点铺向目标
			var grow: float = minf(1.0, (1.0 - a) / 0.3)
			_hw_draw_tiled(o, "fx_logos_s1_link", f.pos, f.pos.lerp(f.to, grow), o.g.PX * 0.8, 0.0)
			return true
		"lava_spout":   # 熔岩块喷起的一小股喷射（10-14）：底宽上尖的火柱，很快缩回
			var hk: float = sin(a * PI * 0.5)
			var hs: float = float(f.h) * hk
			var ws: float = float(f.r)
			var ps: Vector2 = f.pos
			cv.draw_colored_polygon(PackedVector2Array([ps + Vector2(-ws, 0), ps + Vector2(-ws * 0.2, -hs), ps + Vector2(ws * 0.2, -hs), ps + Vector2(ws, 0)]), Color(HW_LAVA.r, HW_LAVA.g, HW_LAVA.b, 0.75 * a))
			cv.draw_colored_polygon(PackedVector2Array([ps + Vector2(-ws * 0.4, 0), ps + Vector2(0, -hs * 0.85), ps + Vector2(ws * 0.4, 0)]), Color(2.4, 1.7, 0.8, 0.85 * a))
			return true
		"lava_spot":   # 熔岩块落点（10-14）：地面一小块发红，从白热褪到暗红
			cv.draw_set_transform(f.pos, 0.0, Vector2(1.0, 0.5))
			cv.draw_circle(Vector2.ZERO, float(f.r), Color(1.2, 0.25, 0.05, 0.45 * a))
			cv.draw_circle(Vector2.ZERO, float(f.r) * 0.55, Color(2.2, 0.9, 0.25, 0.55 * a * a))
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			return true
		"lava_pillar":
			var k: float = sin(a * PI)
			var hh: float = (60.0 + f.r * 0.5) * k
			var w: float = f.r * 0.45
			var p: Vector2 = f.pos
			cv.draw_colored_polygon(PackedVector2Array([p + Vector2(-w, 0), p + Vector2(-w * 0.35, -hh), p + Vector2(w * 0.35, -hh), p + Vector2(w, 0)]), Color(HW_LAVA.r, HW_LAVA.g, HW_LAVA.b, 0.8 * a))
			cv.draw_colored_polygon(PackedVector2Array([p + Vector2(-w * 0.45, 0), p + Vector2(-w * 0.12, -hh * 0.9), p + Vector2(w * 0.12, -hh * 0.9), p + Vector2(w * 0.45, 0)]), Color(2.2, 1.6, 0.8, 0.85 * a))
			cv.draw_circle(p + Vector2(0, -hh), w * 0.35, Color(2.4, 1.9, 1.2, 0.8 * a))
			return true
	return false


## 状态条：次数型技能（status 里的 %d = 剩余发数）、喷发序列
static func hw_status_items(o) -> Array:
	var out: Array = hw3_status_items(o) if o.hw.has("bolts") else []
	if o.hw.has("anchor"):
		out += hw4_status_items(o)
	if h3_on(o):   # 手写迁移段第 3 批
		out += h3_status_items(o)
	if h4_on(o):   # 手写迁移段第 4 批
		out += h4_status_items(o)
	var sk: Array = o.B.get("skills", [])
	for i in mini(3, sk.size()):
		var st: String = str(sk[i].get("status", ""))
		if st != "" and "%d" in st and o.ammo[i] > 0:
			out.append([st % o.ammo[i], _mf_col(sk[i].get("status_col", []), o.col())])
	return out


# ---------------------------------------------------------------- 本段的校验

static func _hw2_block(b: Dictionary, p: String, kind: String, ctx: Dictionary, tag: String) -> bool:
	if not tag in HW2_TAGS:
		return false
	var errs: Array = ctx.errs
	var where_ok := {
		"shape.shell": ["attack", "skill", "instant"],
		"verb.lob": ["skill", "instant"],
		"verb.affect": ["skill", "instant"],
		"st.burn": ["on_hit", "field"],
		"st.fragile": ["on_hit", "field"],
		"shape.pool": ["skill", "instant"],
	}
	if not kind in where_ok[tag]:
		errs.append("%s：「%s」不能放在这里（%s；只能在 %s）" % [p, tag, kind, " / ".join(where_ok[tag])])
		return true
	match tag:
		"shape.shell":
			_num(b, "range", p, ctx, true, 10.0, 2000.0)
			_num(b, "aoe", p, ctx, true, 1.0, 400.0)
			_num(b, "mult", p, ctx, false, 0.0, 20.0)
			_num(b, "speed", p, ctx, false, 10.0, 3000.0)
			_num(b, "life", p, ctx, false, 0.05, 10.0)
			_num(b, "aoe_mult", p, ctx, false, 0.05, 10.0)
			_num(b, "fire_pad", p, ctx, false, 0.0, 400.0)
			_num(b, "side", p, ctx, false, 0.0, 200.0)
			for k in ["tip", "tip_skill"]:
				if b.has(k) and not (b[k] is Array and b[k].size() == 2):
					errs.append("%s.%s 必须是 [x, y]" % [p, k])
			for m in b.get("aoe_mults", []):
				if not (m is Dictionary) or not m.has("mult"):
					errs.append(p + ".aoe_mults 的每一条是 {cond, mult}")
			for f in b.get("follow", []):
				if not (f is Dictionary):
					errs.append(p + ".follow 的每一条是 {cond, n, gap, mult, aoe_mult, sz}")
					continue
				_num(f, "n", p + ".follow", ctx, true, 1.0, 6.0)
				_num(f, "gap", p + ".follow", ctx, false, 0.0, 2.0)
				_num(f, "mult", p + ".follow", ctx, false, 0.0, 20.0)
			_list(b.get("on_explode", []), p + ".on_explode", "instant", ctx)
			for k in ["fire_fx", "boom_fx"]:
				if b.has(k):
					_fx(b[k], p + "." + k, ctx, "shape.circle")
			_src(b, p, ctx, true)
			if b.has("lob"):   # 精英化第 2 批段：低弧抛射三角落点 + 熔池（docs/61 §18）
				var lb = b.lob
				if not (lb is Dictionary):
					errs.append(p + ".lob 必须是对象 {n, mults, gap, spacing, flight, apex, tex, boom_fx, pool}")
				else:
					_num(lb, "n", p + ".lob", ctx, true, 1.0, 6.0)
					_num(lb, "gap", p + ".lob", ctx, false, 0.0, 2.0)
					_num(lb, "spacing", p + ".lob", ctx, false, 0.0, 400.0)
					_num(lb, "flight", p + ".lob", ctx, true, 0.05, 3.0)
					_num(lb, "apex", p + ".lob", ctx, false, 0.0, 200.0)
					var ms = lb.get("mults", [1.0])
					if not (ms is Array) or ms.is_empty() or ms.any(func(x): return not (x is float or x is int or (x is String and str(x).begins_with("$")))):
						errs.append(p + ".lob.mults 必须是数字数组（第 k 发的倍率）")
					if lb.has("tex") and not str(lb.tex).begins_with("proj_"):
						errs.append(p + ".lob.tex 必须是 proj_* 帧条名")
					if lb.has("boom_fx"):
						_fx(lb.boom_fx, p + ".lob.boom_fx", ctx, "shape.circle")
					_list(lb.get("pool", []), p + ".lob.pool", "instant", ctx)
		"verb.lob":
			if not str(b.get("pick", "near_out")) in HW_LOB_PICKS:
				errs.append("%s.pick 只能是 %s" % [p, " / ".join(HW_LOB_PICKS)])
			_num(b, "n", p, ctx, true, 1.0, 8.0)
			_num(b, "r", p, ctx, true, 1.0, 400.0)
			_num(b, "mult", p, ctx, true, 0.0, 20.0)
			_num(b, "h", p, ctx, false, 0.0, 400.0)
			_num(b, "reach", p, ctx, false, 1.0, 2000.0)
			if b.has("basis") and not str(b.basis) in ["attack", "prev", "hit", "atk"]:
				errs.append(p + ".basis 只能是 attack / prev / hit / atk")
			if b.has("look"):
				if not (b.look is Dictionary) or not str(b.look.get("tex", "")).begins_with("proj_"):
					errs.append(p + ".look 必须是 {tex: proj_* 帧条名, scale, spin, apex_k, arc_pow, burst, heavy, spot, land, land_scale, mod}")
				elif b.look.has("land") and not str(b.look.land).begins_with("fx_"):
					errs.append(p + ".look.land 必须是 fx_* 帧条名")
			_src(b, p, ctx, true)
		"verb.affect":
			if not (str(b.get("r", "hit")) == "hit" or b.get("r", null) is float or b.get("r", null) is int):
				_num(b, "r", p, ctx, true, 1.0, 800.0)
			_list(b.get("on_hit", []), p + ".on_hit", "on_hit", ctx)
		"st.burn":
			_num(b, "dur", p, ctx, true, 0.1, 30.0)
			_num(b, "mult", p, ctx, true, 0.0, 5.0)
			_num(b, "every", p, ctx, false, 0.1, 5.0)
			_src(b, p, ctx, true)
		"st.fragile":
			_num(b, "dur", p, ctx, true, 0.1, 30.0)
			if str(b.get("kind", "")) == "arts":
				_num(b, "value", p, ctx, true, 0.0, 1.0)
			elif b.has("kind"):
				errs.append(p + ".kind 只能是 arts（不写 = 受到的全部伤害 +10%）")
		"shape.pool":
			_num(b, "r", p, ctx, true, 1.0, 600.0)
			_num(b, "dur", p, ctx, true, 0.05, 30.0)
			if not b.get("burst", false):
				_num(b, "every", p, ctx, true, 0.05, 10.0)
			_num(b, "mult", p, ctx, true, 0.0, 20.0)
			_num(b, "group_cap", p, ctx, false, 1.0, 16.0)
			_num(b, "max", p, ctx, false, 1.0, 16.0)
			if not str(b.get("center", "target")) in FIELD_CENTERS:
				errs.append("%s.center 只能是 %s" % [p, " / ".join(FIELD_CENTERS)])
			if b.has("look") and not str(b.look) in ["lava", "pool", "rune"]:
				errs.append(p + ".look 只能是 lava / pool / rune")
			_src(b, p, ctx, true)
	return true


## 技能积木的追加字段：cast: instant / dur.pulses + pulse
static func _hw_skill(sb: Dictionary, p: String, ctx: Dictionary) -> void:
	var errs: Array = ctx.errs
	if sb.has("cast") and str(sb.cast) != "instant":
		errs.append(p + ".cast 只能是 instant")
	var dv = sb.get("dur", 0)
	if dv is Dictionary and dv.has("pulses"):
		_num(dv, "pulses", p + ".dur", ctx, true, 1.0, 60.0)
		_num(dv, "every", p + ".dur", ctx, true, 0.05, 5.0)
		var pu = sb.get("pulse", null)
		if not (pu is Dictionary):
			errs.append(p + ".pulse 必须是对象 {r, pad, jit, delay, fx, do}")
		else:
			_num(pu, "r", p + ".pulse", ctx, true, 1.0, 2000.0)
			_list(pu.get("do", []), p + ".pulse.do", "instant", ctx)
			if pu.has("fx"):
				_fx(pu.fx, p + ".pulse.fx", ctx, "shape.circle")
	elif sb.has("pulse"):
		errs.append(p + ".pulse 要配 dur.pulses")


# ---------------------------------------------------------------- 逻各斯段（手写迁移段续）：飘飞咒文弹 / 处决 / 锁定 / 扇形咒域 / 安魂
# 攻击值 basis atk = base(atk) × 加成 × attack.atk_mults（cond 成立的依次乘，例：湮灭期间 ×1.5）；mult 可写数组 = 依次乘（同手写的 a × b × c）。
# 攻击距离 = attack.range × op_range × attack.range_mults（同上）。
# shape.bolt   飘飞咒文弹（普攻或触发 do）：pick aim（普攻：aim_targets，扇形咒域生效时多要 6 个再只留域内的；extra = 追加目标）/ random（射程内最近 pool 个里
#              用 g.rng 随机抽 count 个，chance = 先用 g.rng 掷一次概率；slow = 被选中时立即减速）。每枚排进出手队列（第 k 枚晚 gap × 队列长度 秒），
#              到点从 tip 飘出（同时 ≤ 12 枚，满了直接命中），追着目标飞（speed，左右摆动；相位 g.rng，同手写），飞到执行 then（target = 命中的敌人，
#              basis hit = 这一枚的伤害；then_of: attack = 用普攻那块的 then）；目标半路死了改打落点 60 内最近的
# shape.hit    瞬时：对 then 的命中敌人造成 basis × mult（src 缺省 = 这一枚的来源），on_hit 状态；splash {r, mult} = 周围 r 内其他敌人各吃 basis × mult × splash.mult
# verb.execute 瞬时：命中的敌人非精英、生命低于 攻击值 × thr 时处决（伤害记 src），溢出伤害转给射程内 pool 个里 g.rng 随机一名（over_src，并吃 over_on_hit）；
#              on_exec：处决时执行（target = 处决处）。halt: true = 处决了就不再执行 then 里后面的积木
# st.requiem   安魂：dur 秒内受到的法术伤害 +15%（全队法伤受益；直接覆盖剩余时间，同手写）
# verb.lock    锁定（技能 do）：射程内优先精英 / Boss 的最近敌人，dur 秒内每 tick 秒 攻击值 × mult × ramp × 技能强度（ramp 第 n 跳 = lerp(1, ramp_max, n / ramp_n)），
#              减速 slow × ramp；没有目标退回 refund 比例的技力；jump（cond）= 目标死了跳到离它最近的敌人
# verb.fan     扇形咒域（技能 do）：dur 秒，以自身为顶点、deg 度、半径 = 攻击距离 × r_mult；每 eval 秒重算敌人最多的方向，以 turn 度 / 秒转过去；
#              每 tick 秒对域内敌人 攻击值 × mult × 技能强度（src）并挂 on_hit；域内敌方弹幕减速到 bullet_slow（寿命相应拉长），结束时清掉域内弹幕

const HW3_TAGS := ["shape.bolt", "shape.hit", "verb.execute", "st.requiem", "verb.lock", "verb.fan"]
const HW_BOLT_MAX := 12
const HW_INK := Color(0.55, 0.6, 1.0)
const HW_PALE := Color(0.85, 0.9, 1.0)
## 咒文笔画（同手写 logos RUNES：单位坐标 -1..1，每条 = 起点 → 终点）
const HW_RUNES := [
	[[Vector2(0, -1), Vector2(0, 1)], [Vector2(-0.7, -0.5), Vector2(0.7, -0.5)], [Vector2(0, 1), Vector2(-0.45, 0.7)]],
	[[Vector2(-0.6, -0.6), Vector2(0.6, -0.6)], [Vector2(0.6, -0.6), Vector2(0.6, 0.6)], [Vector2(0.6, 0.6), Vector2(-0.6, 0.6)], [Vector2(-0.6, 0.6), Vector2(-0.6, -0.6)], [Vector2(-0.9, -1), Vector2(0.9, 1)]],
	[[Vector2(0, -1), Vector2(-0.8, 1)], [Vector2(-0.1, -0.2), Vector2(0.8, 1)], [Vector2(-0.6, -0.25), Vector2(0.6, -0.25)]],
	[[Vector2(-0.5, -1), Vector2(-0.5, 1)], [Vector2(-0.5, -0.6), Vector2(0.6, -1)], [Vector2(-0.5, 0), Vector2(0.6, -0.4)]],
	[[Vector2(-0.8, 0), Vector2(0.8, 0)], [Vector2(0, -1), Vector2(0, 1)], [Vector2(-0.55, -0.65), Vector2(-0.3, -0.4)], [Vector2(0.55, 0.45), Vector2(0.3, 0.7)]],
]


static func _hw3(o) -> Dictionary:
	var h := hw_st(o)
	if not h.has("bolts"):
		h.merge({"bolts": [], "word_q": [], "lock": {}, "fan": {}, "fan_ang": 0.0, "hit_e": {}, "hit_src": ""})
	return h


## 攻击值（basis atk）：base(atk) × 加成 × atk_mults
static func hw_atk(o) -> float:
	var a: Dictionary = o.B.get("attack", {})
	var v: float = o.base(str(a.get("atk_key", "atk")), 0.0) * o._dmg_bonus()
	for m in a.get("atk_mults", []):
		if cond_true(o, m.get("cond", {})):
			v *= float(m.get("mult", 1.0))
	return v


## 攻击距离：attack.range × op_range × range_mults
static func hw_range(o) -> float:
	var a: Dictionary = o.B.get("attack", {})
	var v: float = float(a.get("range", 300.0)) * o.stat(&"op_range")
	for m in a.get("range_mults", []):
		if cond_true(o, m.get("cond", {})):
			v *= float(m.get("mult", 1.0))
	return v


## mult：数字，或数组（依次乘）
static func hw_mul(v: float, m) -> float:
	if m is Array:
		for x in m:
			v *= float(x)
		return v
	return v * float(m)


# ---------------------------------------------------------------- shape.bolt

## 普攻起手（data_operator.update 的 bolt 分支，手动普攻 B 类）
static func hw_bolt_aim(o, a: Dictionary) -> Vector2:
	var ts: Array = o.attack_targets(1, hw_range(o), o.pos)
	return ts[0].pos if not ts.is_empty() else Vector2.INF


## 返回 false = 这一下没有目标、没出手（手写的 _release 在这里 return，后面的天赋判定也不走）
static func hw_bolt_fire(o, b: Dictionary, is_atk: bool) -> bool:
	var g = o.g
	var h := _hw3(o)
	var rng_r: float = hw_range(o)
	var src: String = str(b.get("src", ""))
	match str(b.get("pick", "aim")):
		"aim":
			var n: int = int(b.get("count", 1))
			var ex: Array = []
			for x in b.get("extra", []):
				if cond_true(o, x.get("cond", {})):
					ex.append(x)
			var fan: bool = not h.fan.is_empty() and float(h.fan.t) > 0.0 and b.get("fan_filter", false)
			var ts: Array = o.aim_targets(n + ex.size() + (6 if fan else 0), rng_r, o.pos)
			if fan:
				ts = ts.filter(func(e): return hw_in_fan(o, e.pos)).slice(0, n + ex.size())
			if ts.is_empty():
				return false
			var a: float = hw_atk(o)
			for k in ts.size():
				var d: float = hw_mul(a, b.get("mult", 1.0))
				d = hw_mul(d, ex[k - n].get("mult", 1.0)) if k >= n else d * 1.0
				_hw_word(o, ts[k], d, src, b)
		"random":
			if b.has("chance") and not roll(g, float(b.chance)):
				return false
			var pool: Array = o.nearest_enemies(int(b.get("pool", 8)), rng_r, o.pos)
			for q in int(b.get("count", 1)):
				if pool.is_empty():
					break
				var e2: Dictionary = pool.pop_at(g.rng.randi() % pool.size())
				_hw_word(o, e2, hw_mul(hw_atk(o), b.get("mult", 1.0)), src, b)
				if b.has("slow"):
					e2.slow = maxf(e2.slow, float(b.slow))
	return true


static func _hw_word(o, e: Dictionary, dmg: float, src: String, b: Dictionary) -> void:
	var h: Dictionary = o.hw
	h.word_q.append({"t": float(b.get("gap", 0.12)) * h.word_q.size(), "e": e, "dmg": dmg, "src": src, "b": b})


static func _hw_bolt_tip(o, b: Dictionary) -> Vector2:
	var v = b.get("tip", [40, -36])
	return o.pos + Vector2(float(v[0]) * float(o.face), float(v[1]))


## 出手队列 → 飞行 → 命中（hw_tick）
static func _hw3_bolts(o, dt: float) -> void:
	var g = o.g
	var h: Dictionary = o.hw
	if not h.word_q.is_empty():
		for q in h.word_q:
			q.t -= dt
			if q.t <= 0.0:
				var e: Dictionary = q.e
				if e.dead:
					var near: Array = o.nearest_enemies(1, hw_range(o), o.pos)
					e = near[0] if not near.is_empty() else {}
				if not e.is_empty() and not e.dead:
					var hand: Vector2 = _hw_bolt_tip(o, q.b)
					if h.bolts.size() >= HW_BOLT_MAX:
						hw_bolt_hit(o, e, q.dmg, q.src, q.b)
					else:
						h.bolts.append({"pos": hand, "e": e, "dmg": q.dmg, "src": q.src, "b": q.b, "hist": [hand], "life": float(q.b.get("life", 1.3)), "age": 0.0,
							"ph": g.rng.randf() * TAU, "rune": g.vrng.randi(), "to": e.pos + Vector2(0, -e.r * 0.5)})
						o.fx({"kind": "glow", "pos": hand, "r": 7.0, "life": 0.1, "col": HW_PALE, "alpha": 0.7})
		h.word_q = h.word_q.filter(func(q): return q.t > 0.0)
	if h.bolts.is_empty():
		return
	for bo in h.bolts:
		var spd: float = float(bo.b.get("speed", 260.0))
		bo.life -= dt
		bo.age += dt
		if bo.life <= 0.0:
			o.fx({"kind": "glow", "pos": bo.pos, "r": 8.0, "life": 0.25, "col": HW_INK, "alpha": 0.4})
			continue
		var e: Dictionary = bo.e
		if not e.dead:
			bo.to = e.pos + Vector2(0, -e.r * 0.5)
		var d: Vector2 = bo.to - bo.pos
		var step: float = spd * dt
		if d.length() <= step + 4.0:
			bo.pos = bo.to
			bo.life = -1.0
			var tgt: Dictionary = e
			if e.dead:
				var near2: Array = o.nearest_enemies(1, 60.0, bo.to)
				tgt = near2[0] if not near2.is_empty() else {}
			if not tgt.is_empty():
				hw_bolt_hit(o, tgt, bo.dmg, bo.src, bo.b)
			continue
		bo.pos += d.normalized().rotated(sin(bo.age * 7.0 + bo.ph) * 0.45) * step
		bo.hist.append(bo.pos)
		if bo.hist.size() > 6:
			bo.hist.pop_front()
	h.bolts = h.bolts.filter(func(bo): return bo.life > 0.0)


## 命中：then（target = 这名敌人，basis hit = 这一枚的伤害）；verb.execute 处决成功且 halt 时停下
static func hw_bolt_hit(o, e: Dictionary, dmg: float, src: String, b: Dictionary) -> void:
	if e.dead:
		return
	var h: Dictionary = o.hw
	var keep := hw_snap(o)
	var ke = h.hit_e
	var ks: String = h.hit_src
	h.hit_e = e
	h.hit_dmg = dmg
	h.hit_src = src
	var lst: Array = o.B.get("attack", {}).get("then", []) if str(b.get("then_of", "")) == "attack" else b.get("then", [])
	for blk in lst:
		if not cond_true(o, blk.get("cond", {})):
			continue
		if str(blk.get("_tag", "")) == "verb.execute":
			if hw_execute(o, blk) and blk.get("halt", true):
				break
			continue
		o._exec_list([blk], e.pos)
	h.hit_e = ke
	h.hit_src = ks
	hw_pop(o, keep)


static func hw_shape_hit(o, b: Dictionary) -> void:
	var g = o.g
	var h: Dictionary = o.hw
	var e: Dictionary = h.get("hit_e", {})
	if e.is_empty() or e.dead:
		return
	var dmg: float = hw_mul(hw_basis(o, str(b.get("basis", "hit"))), b.get("mult", 1.0))
	var src: String = str(b.get("src", h.hit_src))
	o.log_hit(src, b.get("tags", []))
	o.deal_damage(e, dmg)
	for s in b.get("on_hit", []):
		apply_status(o, e, s)
	if b.has("fx"):
		fx_play(o, b.fx, e.pos + Vector2(0, -float(e.r) * 0.5), float(e.r), [e])
	var sp = b.get("splash", null)
	if sp is Dictionary:
		var ar: float = float(sp.get("r", 30.0))
		if ar > 0.0:
			for j in o.query_ids(e.pos, ar + 20.0):
				var q: Dictionary = g.enemies[j]
				if q.dead or is_same(q, e) or q.pos.distance_to(e.pos) > ar + q.r:
					continue
				o.log_hit(src, b.get("tags", []))
				o.deal_damage(q, dmg * float(sp.get("mult", 0.5)))
				for s in b.get("on_hit", []):
					apply_status(o, q, s)


## verb.execute：返回是否处决了
static func hw_execute(o, b: Dictionary) -> bool:
	var g = o.g
	var h: Dictionary = o.hw
	var e: Dictionary = h.get("hit_e", {})
	if e.is_empty() or e.dead or e.elite or e.boss:
		return false
	if not (e.hp < hw_atk(o) * float(b.get("thr", 1.5))):
		return false
	var dmg: float = float(h.hit_dmg)
	var over: float = maxf(0.0, dmg - e.hp)
	o.log_hit(str(b.get("src", "")), b.get("tags", []))
	o.deal_damage(e, e.hp + 1.0)
	if b.has("fx"):
		fx_play(o, b.fx, e.pos + Vector2(0, -float(e.r) * 0.5), float(e.r), [e])
	o._exec_list(b.get("on_exec", []), e.pos)
	if over > 0.0:
		var pool: Array = o.nearest_enemies(int(b.get("pool", 6)), hw_range(o), o.pos)
		pool = pool.filter(func(q): return not is_same(q, e) and not q.dead)
		if not pool.is_empty():
			var q2: Dictionary = pool[g.rng.randi() % pool.size()]
			o.log_hit(str(b.get("over_src", b.get("src", ""))), [])
			o.deal_damage(q2, over)
			for s in b.get("over_on_hit", []):
				apply_status(o, q2, s)
			var la: Vector2 = e.pos + Vector2(0, -e.r * 0.5)
			var lb: Vector2 = q2.pos + Vector2(0, -q2.r * 0.5)
			if g.tex.get("fx_logos_s1_link") != null:
				o.fx({"kind": "s1link", "pos": la, "to": lb, "life": 0.3})
			else:
				o.fx({"kind": "line", "pos": la, "to": lb, "life": 0.2, "col": HW_INK, "w": 2.0})
	return true


# ---------------------------------------------------------------- verb.lock / verb.fan

static func hw_lock_start(o, b: Dictionary) -> void:
	var g = o.g
	var h := _hw3(o)
	var best = null
	var bd := INF
	for j in o.query_ids(o.pos, hw_range(o)):
		var e: Dictionary = g.enemies[j]
		if e.dead:
			continue
		var score: float = e.pos.distance_to(o.pos) - (100000.0 if (e.elite or e.boss) else 0.0)
		if score < bd:
			bd = score
			best = e
	var i: int = o.cur_skill
	if best == null:
		if i >= 0:
			o.sp[i] = o.sp_need(i) * float(b.get("refund", 0.6))
		return
	h.lock = {"e": best, "t": float(b.dur), "tick": 0.0, "n": 0, "b": b, "i": i}
	if i >= 0:
		o.s_dur[i] = float(b.dur)
	if b.has("fx"):
		fx_play(o, b.fx, best.pos, float(best.r), [best])


static func _hw3_lock(o, dt: float) -> void:
	var g = o.g
	var lk: Dictionary = o.hw.lock
	if float(lk.t) <= 0.0:
		return
	var b: Dictionary = lk.b
	lk.t = float(lk.t) - dt
	if lk.e != null and lk.e.dead and b.has("jump") and hw_face_ok(o, b.jump) and float(lk.t) > 0.0:
		_hw_lock_jump(o, lk)
	if lk.e == null or lk.e.dead:
		lk.t = 0.0
		lk.e = null
		return
	lk.tick = float(lk.tick) + dt
	var tick: float = float(b.get("tick", 0.25))
	while float(lk.tick) >= tick:
		lk.tick = float(lk.tick) - tick
		lk.n = int(lk.n) + 1
		var ramp: float = lerpf(1.0, float(b.get("ramp_max", 3.0)), clampf(int(lk.n) / float(b.get("ramp_n", 12.0)), 0.0, 1.0))
		o.log_hit(str(b.get("src", "")), b.get("tags", []))
		if not o.acting():
			o.face_to((lk.e.pos - o.pos).angle())
		o.deal_damage(lk.e, hw_atk(o) * float(b.get("mult", 0.5)) * ramp * o.skill_power())
		lk.e.slow = maxf(lk.e.slow, float(b.get("slow", 0.6)) * ramp)
		var tip: Vector2 = _hw_bolt_tip(o, o.B.get("attack", {}))
		o.fx({"kind": "line", "pos": tip, "to": lk.e.pos + Vector2(0, -lk.e.r * 0.5), "life": 0.12, "col": HW_INK, "w": 1.5 + ramp})
		o.fx({"kind": "glow", "pos": lk.e.pos + Vector2(0, -lk.e.r * 0.5), "r": 8.0 + 6.0 * ramp, "life": 0.2, "col": HW_PALE, "alpha": 0.5})


static func _hw_lock_jump(o, lk: Dictionary) -> void:
	var g = o.g
	var from: Vector2 = lk.e.pos
	var best = null
	var bd: float = INF
	var rr: float = hw_range(o)
	for j in o.query_ids(from, rr):
		var q: Dictionary = g.enemies[j]
		if q.dead or q.pos.distance_to(o.pos) > rr:
			continue
		var d: float = q.pos.distance_to(from)
		if d < bd:
			bd = d
			best = q
	if best == null:
		return
	lk.e = best
	var to: Vector2 = best.pos + Vector2(0, -best.r * 0.5)
	var mid: Vector2 = (from + to) * 0.5 + Vector2(0, -24)
	o.fx({"kind": "line", "pos": from + Vector2(0, -8), "to": mid, "life": 0.3, "col": HW_PALE, "w": 2.5})
	o.fx({"kind": "line", "pos": mid, "to": to, "life": 0.3, "col": HW_PALE, "w": 2.5})
	o.fx({"kind": "ring", "pos": best.pos, "r": best.r + 18.0, "r0": 4.0, "life": 0.35, "col": HW_INK, "floor": true})
	var b: Dictionary = lk.b
	if b.has("jump_fx"):
		fx_play(o, b.jump_fx, best.pos, float(best.r), [best])


static func hw_fan_r(o, b: Dictionary) -> float:
	return hw_range(o) * float(b.get("r_mult", 1.25))


static func hw_in_fan(o, p: Vector2) -> bool:
	var fn: Dictionary = o.hw.get("fan", {})
	if fn.is_empty():
		return false
	var b: Dictionary = fn.b
	var d: Vector2 = p - o.pos
	if d.length() > hw_fan_r(o, b):
		return false
	return d.length() < 8.0 or absf(wrapf(d.angle() - float(o.hw.fan_ang), -PI, PI)) <= deg_to_rad(float(b.get("deg", 100.0))) * 0.5


static func _hw_fan_best(o, b: Dictionary) -> float:
	var g = o.g
	var h: Dictionary = o.hw
	var r: float = hw_fan_r(o, b)
	var half: float = deg_to_rad(float(b.get("deg", 100.0))) * 0.5
	var angs: Array = []
	for j in o.query_ids(o.pos, r):
		var e: Dictionary = g.enemies[j]
		if not e.dead and e.pos.distance_to(o.pos) <= r:
			angs.append((e.pos - o.pos).angle())
	var on: bool = not h.fan.is_empty() and float(h.fan.t) > 0.0
	if angs.is_empty():
		return float(h.fan_ang) if on else o.facing_angle()
	var best: float = o.facing_angle()
	var bn := -1
	var fa: float = float(h.fan_ang)
	for k in 12:
		var a: float = k * TAU / 12.0
		var n := 0
		for ea in angs:
			if absf(wrapf(ea - a, -PI, PI)) <= half:
				n += 1
		if n > bn or (n == bn and absf(wrapf(a - fa, -PI, PI)) < absf(wrapf(best - fa, -PI, PI))):
			bn = n
			best = a
	return best


static func hw_fan_start(o, b: Dictionary) -> void:
	var h := _hw3(o)
	if h.fan.is_empty():
		h.fan = {"t": 0.0, "b": b}
	h.fan.b = b
	h.fan.t = float(b.dur)
	h.fan_ang = _hw_fan_best(o, b)
	h.fan.want = h.fan_ang
	h.fan.eval = 0.5
	h.fan.tick = 0.0
	h.fan.i = o.cur_skill
	if o.cur_skill >= 0:
		o.s_dur[o.cur_skill] = float(b.dur)
	o.face_to(float(h.fan_ang))


static func _hw3_fan(o, dt: float) -> void:
	var g = o.g
	var h: Dictionary = o.hw
	var fn: Dictionary = h.fan
	if float(fn.t) <= 0.0:
		return
	var b: Dictionary = fn.b
	fn.t = float(fn.t) - dt
	var r: float = hw_fan_r(o, b)
	fn.eval = float(fn.eval) - dt
	if float(fn.eval) <= 0.0:
		fn.eval = float(b.get("eval", 0.5))
		fn.want = _hw_fan_best(o, b)
	var turn: float = deg_to_rad(float(b.get("turn", 60.0))) * dt
	h.fan_ang = float(h.fan_ang) + clampf(wrapf(float(fn.want) - float(h.fan_ang), -PI, PI), -turn, turn)
	fn.tick = float(fn.tick) - dt
	if float(fn.tick) <= 0.0:
		fn.tick = float(fn.tick) + float(b.get("tick", 0.5))
		var dmg: float = hw_atk(o) * float(b.get("mult", 0.6)) * o.skill_power()
		var shown := 0
		for j in o.query_ids(o.pos, r + 30.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or not hw_in_fan(o, e.pos):
				continue
			o.log_hit(str(b.get("src", "")), b.get("tags", []))
			o.deal_damage(e, dmg)
			if not e.dead:
				for s in b.get("on_hit", []):
					apply_status(o, e, s)
			if shown < 3:
				shown += 1
				o.spawn_fx_sprite("fx_logos_glyph", e.pos + Vector2(0, -e.r * 0.5), g.PX * 0.7, 0.0, g.vrng.randf() < 0.5)
	var f: float = float(b.get("bullet_slow", 0.2))
	for bl in g.ebullets:
		if bl.life <= 0.0 or not hw_in_fan(o, bl.pos):
			continue
		if not bl.get("acuity", false):
			bl["acuity"] = true
			bl.vel *= f
			bl.life = bl.life / f
	if float(fn.t) <= 0.0:
		var n := 0
		for bl in g.ebullets:
			if bl.life > 0.0 and hw_in_fan(o, bl.pos):
				bl.life = 0.0
				n += 1
				o.fx({"kind": "glow", "pos": bl.pos, "r": 8.0, "life": 0.25, "col": HW_INK, "alpha": 0.6})
		if n > 0:
			o.float_text(o.pos + Vector2(0, -70), "消除弹幕 ×%d" % n, HW_INK, 15)
		o.fx({"kind": "glow", "pos": o.pos + Vector2.from_angle(float(h.fan_ang)) * r * 0.5, "r": 40.0, "life": 0.4, "col": HW_INK, "alpha": 0.4})


## 锁定 / 咒域的技能剩余（hw_active_left 转来）
static func _hw3_left(o, i: int) -> float:
	var h: Dictionary = o.hw
	var lk = h.get("lock", {})
	if lk is Dictionary and not lk.is_empty() and int(lk.get("i", -1)) == i:
		return maxf(0.0, float(lk.t))
	var fn = h.get("fan", {})
	if fn is Dictionary and not fn.is_empty() and int(fn.get("i", -1)) == i:
		return maxf(0.0, float(fn.t))
	return -1.0


# ---------------------------------------------------------------- 画面

## 咒文：按笔顺逐笔写出（write 0..1），暗色描边 + 墨蓝笔画 + 亮芯；顶点对齐 2 像素网格
static func _hw_draw_rune(o, c: Vector2, sz: float, pat: int, write: float, al: float) -> void:
	var cv = o.cv
	var strokes: Array = HW_RUNES[pat % HW_RUNES.size()]
	var ns: int = strokes.size()
	for i in ns:
		var k: float = clampf(write * ns - i, 0.0, 1.0)
		if k <= 0.0:
			break
		var a: Vector2 = ((c + strokes[i][0] * sz) / 2.0).round() * 2.0
		var b: Vector2 = ((c + (strokes[i][0].lerp(strokes[i][1], k)) * sz) / 2.0).round() * 2.0
		cv.draw_line(a, b, Color(0.03, 0.03, 0.08, 0.7 * al), 4.0)
		cv.draw_line(a, b, Color(HW_INK.r * 1.5, HW_INK.g * 1.5, HW_INK.b * 1.8, 0.95 * al), 2.0)
		cv.draw_line(a, b, Color(1.8, 1.9, 2.4, 0.6 * al), 1.0)


## 地面层：咒文池（look rune：铭文 = 小书写圈；burst = 墓志铭的书写大圈）
static func hw_draw_rune_floor(o) -> void:
	if not o.hw.has("pools"):
		return
	var cv = o.cv
	for l in o.hw.pools:
		if str(l.b.get("look", "")) != "rune":
			continue
		if l.b.get("burst", false):
			var k: float = 1.0 - l.t / maxf(0.01, l.dur)
			cv.draw_set_transform(l.pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.5))
			cv.draw_circle(Vector2.ZERO, l.r, Color(HW_INK.r, HW_INK.g, HW_INK.b, 0.08 + 0.12 * k))
			cv.draw_arc(Vector2.ZERO, l.r, 0.0, TAU, 40, Color(HW_INK.r * 1.4, HW_INK.g * 1.4, HW_INK.b * 1.7, 0.4 + 0.4 * k), 2.0)
			cv.draw_arc(Vector2.ZERO, l.r * k, 0.0, TAU, 40, Color(HW_PALE.r, HW_PALE.g, HW_PALE.b, 0.5), 1.5)
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			var al: float = clampf(l.t / 0.3, 0.0, 1.0)
			cv.draw_set_transform(l.pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.5))
			cv.draw_circle(Vector2.ZERO, l.r, Color(HW_INK.r, HW_INK.g, HW_INK.b, 0.1 * al))
			cv.draw_arc(Vector2.ZERO, l.r, 0.0, TAU, 24, Color(HW_INK.r * 1.3, HW_INK.g * 1.3, HW_INK.b * 1.5, 0.45 * al), 1.5)
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 扇形咒域（draw_auras）
static func hw_draw_fan(o) -> void:
	var h: Dictionary = o.hw
	var fn = h.get("fan", {})
	if not (fn is Dictionary) or fn.is_empty() or float(fn.t) <= 0.0 or o.pos == Vector2.INF:
		return
	var g = o.g
	var cv = o.cv
	var b: Dictionary = fn.b
	var r: float = hw_fan_r(o, b)
	var half: float = deg_to_rad(float(b.get("deg", 100.0))) * 0.5
	var fa: float = float(h.fan_ang)
	var fade: float = clampf(float(fn.t) / 0.5, 0.0, 1.0)
	var pts := PackedVector2Array([o.pos])
	for k in 25:
		pts.append(o.pos + Vector2.from_angle(fa - half + half * 2.0 * k / 24.0) * r)
	cv.draw_colored_polygon(pts, Color(HW_INK.r, HW_INK.g, HW_INK.b, (0.10 + 0.03 * sin(g.t * 3.0)) * fade))
	var ec := Color(HW_INK.r * 1.3, HW_INK.g * 1.3, HW_INK.b * 1.4, 0.55 * fade)
	cv.draw_line(o.pos, o.pos + Vector2.from_angle(fa - half) * r, ec, 2.0)
	cv.draw_line(o.pos, o.pos + Vector2.from_angle(fa + half) * r, ec, 2.0)
	cv.draw_arc(o.pos, r, fa - half, fa + half, 32, ec, 2.0)
	for q in 6:
		var t: float = fmod(g.t * 0.35 + q / 6.0, 1.0)
		cv.draw_circle(o.pos + Vector2.from_angle(fa - half + half * 2.0 * t) * r, 2.5, Color(HW_PALE.r, HW_PALE.g, HW_PALE.b, 0.7 * fade))


## 咒域期间绕身的符咒（draw_body 前后两层；fan.b.body = [back 帧条, front 帧条, 不分层回退]）
static func hw_draw_fan_body(o, front: bool) -> void:
	var h: Dictionary = o.hw
	var fn = h.get("fan", {})
	if not (fn is Dictionary) or fn.is_empty() or float(fn.t) <= 0.0 or o.pos == Vector2.INF:
		return
	var g = o.g
	var bd: Array = fn.b.get("body", [])
	if bd.size() < 3:
		return
	var tn: String = str(bd[1] if front else bd[0])
	if g.tex.get(tn) == null:
		if front and g.tex.get(str(bd[2])) != null:
			o.draw_spr_rot(str(bd[2]), int(g.t * 10.0) % 6, o.pos + Vector2(0, -36), 0.0, g.PX, Color(1, 1, 1, 0.95), Vector2(-1, -1), o.face < 0.0)
		return
	o.draw_spr_rot(tn, int(g.t * 10.0) % 6, o.pos + Vector2(0, -36), 0.0, g.PX, Color(1, 1, 1, 0.95), Vector2(-1, -1), o.face < 0.0)


## 技能上层：咒文弹、铭文 / 墓志铭的浮空咒文、锁定的书写带与标记、咒域头顶标记
static func hw_draw_logos_over(o) -> void:
	var g = o.g
	var cv = o.cv
	var h: Dictionary = o.hw
	for bo in h.bolts:
		var hh: Array = bo.hist
		for i in range(1, hh.size()):
			var k: float = float(i) / float(hh.size())
			cv.draw_line(hh[i - 1], hh[i], Color(HW_INK.r, HW_INK.g, HW_INK.b, 0.08 + 0.2 * k), 1.0 + 2.5 * k)
		var rtx: Texture2D = ArtS.tex("fx_logos_glyphs")
		if rtx != null:
			var fh: int = rtx.get_height()
			var rn: int = maxi(1, rtx.get_width() / maxi(1, fh))
			var sc: float = g.PX * 13.0 / float(fh)
			cv.draw_set_transform(bo.pos + g.draw_off, sin(bo.age * 5.0 + bo.ph) * 0.35, Vector2(sc, sc))
			cv.draw_texture_rect_region(rtx, Rect2(-Vector2(fh, fh) / 2.0, Vector2(fh, fh)), Rect2(fh * (int(bo.rune) % rn), 0, fh, fh), Color(1, 1, 1, clampf(bo.life / 0.25, 0.0, 1.0)))
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		elif g.tex.get("fx_logos_glyph") != null:
			o.draw_spr_rot("fx_logos_glyph", 5, bo.pos, sin(bo.age * 5.0 + bo.ph) * 0.35, g.PX * 13.0 / 24.0, Color(1, 1, 1, clampf(bo.life / 0.25, 0.0, 1.0)))
		elif g.tex.get("proj_logos_ink") != null and hh.size() >= 2:
			o.draw_spr_rot("proj_logos_ink", int(g.t * 12.0) % 4, bo.pos, (bo.pos - hh[hh.size() - 2]).angle(), g.PX)
		else:
			cv.draw_circle(bo.pos, 10.0, Color(HW_INK.r, HW_INK.g, HW_INK.b, 0.35))
			cv.draw_circle(bo.pos, 5.5, Color(HW_INK.r * 1.4, HW_INK.g * 1.4, HW_INK.b * 1.6))
			cv.draw_circle(bo.pos, 2.5, Color(1.8, 1.9, 2.2))
	if h.has("pools"):
		for l in h.pools:
			if str(l.b.get("look", "")) != "rune":
				continue
			if l.b.get("burst", false):
				var k2: float = 1.0 - l.t / maxf(0.01, l.dur)
				var c: Vector2 = l.pos + Vector2(0, -26)
				cv.draw_circle(c, 18.0 + 6.0 * k2, Color(HW_INK.r, HW_INK.g, HW_INK.b, 0.12 + 0.2 * k2))
				_hw_draw_rune(o, c, 16.0, int(l.pat), k2 * 1.25, 0.7 + 0.3 * k2)
			else:
				var al: float = clampf(l.t / 0.3, 0.0, 1.0)
				var bob: float = sin(g.t * 5.0 + int(l.pat) % 5) * 1.5
				cv.draw_circle(l.pos + Vector2(0, -16 + bob), 13.0, Color(HW_INK.r, HW_INK.g, HW_INK.b, 0.18 * al))
				_hw_draw_rune(o, l.pos + Vector2(0, -16 + bob), 9.0, int(l.pat), (l.dur - l.t) / 0.15, al)
	var lk = h.get("lock", {})
	if lk is Dictionary and not lk.is_empty() and float(lk.t) > 0.0 and lk.e != null and not lk.e.dead:
		var tip: Vector2 = _hw_bolt_tip(o, o.B.get("attack", {}))
		var to: Vector2 = lk.e.pos + Vector2(0, -lk.e.r * 0.5)
		if g.tex.get("fx_logos_script") != null:
			_hw_draw_tiled(o, "fx_logos_script", tip, to, g.PX * 0.8, fmod(g.t * 210.0, 64.0 * g.PX * 0.8))
		var p: Vector2 = lk.e.pos + Vector2(0, -lk.e.r - 14)
		var kk: float = 0.5 + 0.5 * sin(g.t * 8.0)
		cv.draw_arc(p, 6.0 + 2.0 * kk, 0.0, TAU, 12, Color(HW_INK.r, HW_INK.g, HW_INK.b, 0.9), 1.5)
		cv.draw_line(p + Vector2(-9, 0), p + Vector2(-4, 0), HW_PALE, 1.5)
		cv.draw_line(p + Vector2(4, 0), p + Vector2(9, 0), HW_PALE, 1.5)
	var fn = h.get("fan", {})
	if fn is Dictionary and not fn.is_empty() and float(fn.t) > 0.0:
		var q: Vector2 = o.pos + Vector2(0, -80)
		cv.draw_circle(q, 3.0 + sin(g.t * 12.0), Color(HW_INK.r * 1.6, HW_INK.g * 1.6, HW_INK.b * 1.4, 0.8))


## 沿 a→b 平铺一张横向帧条（每段一帧宽），offset 为沿方向的滚动位移；最后一段按端点裁剪
static func _hw_draw_tiled(o, tn: String, a: Vector2, b: Vector2, sc: float, offset: float, frame_off: int = 0, col := Color.WHITE, fixed := -1) -> void:
	var g = o.g
	var tx: Texture2D = g.tex.get(tn)
	if tx == null or not g.V6_FRAMES.has(tn):
		return
	o._cv_flush()
	var cv = o.cv
	var frames: int = g.V6_FRAMES[tn][0]
	var fw: float = tx.get_width() / frames
	var fh: float = tx.get_height()
	var k: float = sc / ArtS.hires_of(tx)
	var seg: float = fw * k
	var L: float = a.distance_to(b)
	if L < 2.0:
		return
	var fr: int = (int(g.t * float(g.V6_FRAMES[tn][1])) + frame_off) % frames if fixed < 0 else fixed % frames   # fixed：停在这一帧（锁链松 / 绷直）
	cv.draw_set_transform(a + g.draw_off, (b - a).angle(), Vector2(k, k))
	var x: float = -fmod(offset, seg)
	while x < L:
		var x0: float = maxf(x, 0.0)
		var x1: float = minf(x + seg, L)
		if x1 > x0:
			var u0: float = (x0 - x) / k
			var u1: float = (x1 - x) / k
			cv.draw_texture_rect_region(tx, Rect2(Vector2(x0 / k, -fh / 2.0), Vector2(u1 - u0, fh)), Rect2(fw * fr + u0, 0, u1 - u0, fh), col)
		x += seg
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func hw3_status_items(o) -> Array:
	var out: Array = []
	var h: Dictionary = o.hw
	var sk: Array = o.B.get("skills", [])
	for key in ["lock", "fan"]:
		var st = h.get(key, {})
		if st is Dictionary and not st.is_empty() and float(st.t) > 0.0:
			var i: int = int(st.get("i", -1))
			if i >= 0 and i < sk.size() and sk[i].has("status"):
				out.append([str(sk[i].status), _mf_col(sk[i].get("status_col", []), o.col())])
	return out


# ---------------------------------------------------------------- 本段的校验

static func _hw3_block(b: Dictionary, p: String, kind: String, ctx: Dictionary, tag: String) -> bool:
	if not tag in HW3_TAGS:
		return false
	var errs: Array = ctx.errs
	var where_ok := {
		"shape.bolt": ["attack", "skill", "instant"],
		"shape.hit": ["instant"],
		"verb.execute": ["instant"],
		"st.requiem": ["on_hit", "field"],
		"verb.lock": ["skill"],
		"verb.fan": ["skill"],
	}
	if not kind in where_ok[tag]:
		errs.append("%s：「%s」不能放在这里（%s；只能在 %s）" % [p, tag, kind, " / ".join(where_ok[tag])])
		return true
	match tag:
		"shape.bolt":
			if not str(b.get("pick", "aim")) in ["aim", "random"]:
				errs.append(p + ".pick 只能是 aim / random")
			_num(b, "count", p, ctx, false, 1.0, 8.0)
			_num(b, "speed", p, ctx, false, 10.0, 3000.0)
			_num(b, "life", p, ctx, false, 0.05, 10.0)
			_num(b, "gap", p, ctx, false, 0.0, 2.0)
			_num(b, "chance", p, ctx, false, 0.0, 1.0)
			_num(b, "pool", p, ctx, false, 1.0, 32.0)
			if kind == "attack":
				_num(b, "range", p, ctx, true, 10.0, 2000.0)
			if b.has("then"):
				_list(b.then, p + ".then", "instant", ctx)
			elif str(b.get("then_of", "")) != "attack":
				errs.append(p + "：要写 then（命中后执行的积木），或 then_of: attack（用普攻那块的）")
			_src(b, p, ctx, true)
		"shape.hit":
			if b.has("src"):
				_src(b, p, ctx, true)
			_list(b.get("on_hit", []), p + ".on_hit", "on_hit", ctx)
			if b.has("splash") and not (b.splash is Dictionary):
				errs.append(p + ".splash 必须是对象 {r, mult}")
		"verb.execute":
			_num(b, "thr", p, ctx, true, 0.0, 100.0)
			_src(b, p, ctx, true)
			_list(b.get("on_exec", []), p + ".on_exec", "instant", ctx)
			_list(b.get("over_on_hit", []), p + ".over_on_hit", "on_hit", ctx)
		"st.requiem":
			_num(b, "dur", p, ctx, true, 0.1, 30.0)
		"verb.lock":
			_num(b, "dur", p, ctx, true, 0.1, 30.0)
			_num(b, "tick", p, ctx, true, 0.05, 5.0)
			_num(b, "mult", p, ctx, true, 0.0, 20.0)
			_num(b, "ramp_max", p, ctx, false, 1.0, 20.0)
			_src(b, p, ctx, true)
		"verb.fan":
			_num(b, "dur", p, ctx, true, 0.1, 60.0)
			_num(b, "deg", p, ctx, true, 5.0, 360.0)
			_num(b, "tick", p, ctx, true, 0.05, 5.0)
			_num(b, "mult", p, ctx, true, 0.0, 20.0)
			_list(b.get("on_hit", []), p + ".on_hit", "on_hit", ctx)
			_src(b, p, ctx, true)
	return true


# ---------------------------------------------------------------- 乌尔比安段（手写迁移段续）：掷锚（钩回 / 弹射）/ 掀飞 / 拖拽 / 叠层 / 蓄势 / 计时
# shape.circle center: front   判定中心 = 脚底 + 朝 aim_r（× op_range，缺省 = 本形状半径）+ aim_pad 内最近敌人（转身）的方向 × 半径 × front（锚击砸在身前）
# verb.tether  掷锚（技能 do）：pick（elite = 射程 pick_r_elite 内最近的精英 / Boss，没有退到 densest；densest = pick_r 内敌群最密处，没有退到最近的）选落点，
#              manual: true = 当队长手动时用玩家给的落点 / 方向（aim_cone / aim_range / aim_empty / aim_free / aim_snap，契约 v2.4 / v2.5）；没有落点退回 refund 的技力。
#              锚 throw 秒飞到落点咬地；mode reel：钩住落点 hook_r（hook_more 成立时 × r_mult）内至多 hook_n（+ hook_more.n）名非 Boss 敌人，收链拽到身前、眩晕，
#              停 hold 秒后重砸身前（r × op_range，攻击 × mult × 加成 × 技能强度，钩中的首个精英 × elite_mult；stun；击退 slam_kb）；
#              钩不到或钩到 Boss 就和 mode zip 一样：本干员顺锁链弹射到落点前，落地砸 r（land_kb 击退，kb_boss = Boss 也推；stun_boss / stun_elite 时长系数），
#              落地后执行 then（target = 落点）、drag（cond：甩锁链拽来 r 内至多 n 名，伤害 = 落地伤害 × mult）、rift（cond：起跳点到落点裂开通路，
#              宽 w，沿线 攻击 × 加成 × mult × 技能强度 并掀飞 air 秒）。锚在外面时本干员不起手、不放别的技能，动作停在技能条第 hold_frame 帧
# verb.stack   叠层（触发 do）：key 层数 + add（Boss + add_boss），上限 cap + cap_more（cond 成立的 add）；层数变了立刻重算属性（aura 的 per: stack:<key>）
# verb.arm     蓄势（触发 do）：key 置位（已置位不重复）；attack.armed [{key, do}]：置位时下一次普攻整个换成 do（不计普攻次数、不走 every_n），用掉清零
# verb.timer   计时（瞬时）：key 计时 dur 秒（每帧开头倒数，同手写）；条件 timer:<key> / armed:<key>；技能积木 active_timer = 技能生效剩余按这个计时（手写的「开辟」8 秒）

const HW4_TAGS := ["verb.tether", "verb.stack", "verb.arm", "verb.timer"]
const HW_STEEL := Color(0.55, 0.75, 0.95)
const HW_CHAIN := Color(0.62, 0.68, 0.78)
const HW_ABYSS := Color(0.1, 0.12, 0.2)
const HW_EDGE := Color(0.4, 0.62, 1.1)
const HW_WATER := Color(0.45, 0.78, 1.0)
const HW_BLOOD := Color(1.0, 0.25, 0.3)


static func _hw4(o) -> Dictionary:
	var h := hw_st(o)
	if not h.has("anchor"):
		h.merge({"anchor": {}, "hooked": [], "launched": [], "stacks": {}, "armed": {}, "timers": {}, "sil": {}, "blk": {}})
	return h


static func hw_parse_cond(s: String) -> Dictionary:
	var neg := s.begins_with("!")
	var t := s.substr(1).strip_edges() if neg else s
	for k in ["timer", "armed"]:
		if t.begins_with(k + ":") and t.length() > k.length() + 1:
			return {"neg": neg, "k": k, "a": t.substr(k.length() + 1), "op": "", "v": 0.0}
	return {}


static func hw_cond(o, c: Dictionary) -> bool:
	if not hw_on(o) or not o.hw.has("anchor"):
		return false
	match str(c.k):
		"timer":
			return float(o.hw.timers.get(str(c.a), 0.0)) > 0.0
		"armed":
			return o.hw.armed.get(str(c.a), false)
	return false


# ---------------------------------------------------------------- 锚击中心 front

## shape.circle center: front 的判定中心（同时转身、记方向）。返回 [中心, 方向角]
static func hw_front(o, b: Dictionary, r: float) -> Array:
	var ar: float = r
	if b.has("aim_r"):
		ar = float(b.aim_r) * o.stat(&"op_range")
	var ts: Array = o.nearest_enemies(1, ar + float(b.get("aim_pad", 60.0)), o.pos)
	var ang: float = o.facing_angle()
	if not ts.is_empty():
		ang = (ts[0].pos - o.pos).angle()
		o.face_to(ang)
	ang = o.atk_angle(ang)
	return [o.pos + Vector2.from_angle(ang) * r * float(b.get("front", 0.55)), ang]


## 普攻起手点（data_operator.update 的 circle 分支，center: front）
static func hw_front_aim(o, a: Dictionary) -> Vector2:
	var r: float = shape_radius(o, a)
	return o.atk_point(o.nearest_enemies(1, r + float(a.get("start_pad", 40.0)), o.pos), r)


# ---------------------------------------------------------------- verb.timer / verb.arm / verb.stack

static func hw_timer(o, b: Dictionary) -> void:
	var h := _hw4(o)
	h.timers[str(b.get("key", "t"))] = float(b.get("dur", 1.0))
	h.blk["timer:" + str(b.get("key", "t"))] = b
	var sk: Array = o.B.get("skills", [])
	for i in mini(3, sk.size()):   # 技能 active_timer 用这个计时：HUD 的总时长
		if str(sk[i].get("active_timer", "")) == str(b.get("key", "t")):
			o.s_dur[i] = float(b.get("dur", 1.0))


static func hw_arm(o, b: Dictionary) -> void:
	var h := _hw4(o)
	var k: String = str(b.get("key", "armed"))
	if h.armed.get(k, false):
		return
	h.armed[k] = true
	h.blk["armed:" + k] = b
	if b.has("fx"):
		fx_play(o, b.fx, o.pos, 30.0)


static func hw_stack(o, b: Dictionary) -> void:
	var e: Dictionary = o.hw.get("kill_e", {})
	var h := _hw4(o)
	var k: String = str(b.get("key", "stack"))
	h.blk["stack:" + k] = b
	var add: int = int(b.get("add_boss", b.get("add", 1))) if not e.is_empty() and e.get("boss", false) else int(b.get("add", 1))
	var cap: int = hw_stack_cap(o, b)
	var n: int = int(h.stacks.get(k, 0))
	if add <= 0 or n >= cap:
		return
	h.stacks[k] = mini(cap, n + add)
	o._restat()   # 同手写：层数一变立刻重算攻击（不等下一帧）
	if b.has("text"):
		o.float_text(o.pos + Vector2(0, -60), str(b.text) % int(h.stacks[k]), _mf_col(b.get("text_col", []), HW_STEEL), 13)
	if b.has("fx"):
		fx_play(o, b.fx, o.pos, 30.0)


static func hw_stack_cap(o, b: Dictionary) -> int:
	var cap: int = int(b.get("cap", 10))
	for m in b.get("cap_more", []):
		if cond_true(o, m.get("cond", {})):
			cap += int(m.get("add", 0))
	return cap


static func hw_stack_n(o, key: String) -> int:
	if not hw_on(o) or not o.hw.has("stacks"):
		return 0
	return int(o.hw.stacks.get(key, 0))


## 蓄势的普攻（data_operator._release 开头）：attack.armed 里第一条已置位的，用掉清零、执行它的 do（target = 锚击中心）。返回 true = 这一下已换掉
static func hw_armed_release(o, a: Dictionary) -> bool:
	if not o.hw.has("armed"):
		return false
	for am in o.B.get("attack", {}).get("armed", []):   # 蓄势写在 blocks.attack 上；半径按当前普攻（含 swap_attack）
		var k: String = str(am.get("key", ""))
		if o.hw.armed.get(k, false):
			o.hw.armed[k] = false
			var r: float = shape_radius(o, a)
			var fr: Array = hw_front(o, a, r)
			o.hw.prev_ang = fr[1]
			o.hw.prev_c = fr[0]
			o.hw.prev_r = r
			o._exec_list(am.get("do", []), fr[0])
			return true
	return false


# ---------------------------------------------------------------- verb.tether

static func _hw_hand(o) -> Vector2:
	var b: Dictionary = o.hw.anchor.get("b", {})
	var v = b.get("hand", [33, -33])
	return o.pos + Vector2(float(v[0]) * float(o.face), float(v[1]))


## 选落点：elite = pick_r_elite 内最近的精英 / Boss，没有就 densest；densest = pick_r 内最密处，没有就最近的
static func hw_tether_target(o, b: Dictionary) -> Vector2:
	var g = o.g
	if str(b.get("pick", "densest")) == "elite":
		var best: Dictionary = {}
		var bd := INF
		for j in o.query_ids(o.pos, float(b.get("pick_r_elite", 420.0))):
			var e: Dictionary = g.enemies[j]
			if e.dead or not (e.elite or e.boss):
				continue
			var d: float = e.pos.distance_to(o.pos)
			if d < bd:
				bd = d
				best = e
		if not best.is_empty():
			return best.pos
	var pr: float = float(b.get("pick_r", 400.0))
	var c: Vector2 = o.densest_point(pr, o.pos)
	if c == Vector2.INF:
		var ts: Array = o.nearest_enemies(1, pr, o.pos)
		return ts[0].pos if not ts.is_empty() else Vector2.INF
	return c


## 带方向的落点（契约 v2.4）：方向 ±aim_cone° 扇形、aim_range 内敌人最密处；扇形里没有敌人落在该方向 aim_empty 远（0 = 退回自动瞄准）
static func hw_tether_aim_dir(o, b: Dictionary, dir: Vector2) -> Vector2:
	var g = o.g
	var cone: float = deg_to_rad(float(b.get("aim_cone", 30.0)))
	var reach: float = float(b.get("aim_range", 400.0))
	var cands: Array = []
	for j in o.query_ids(o.pos, reach):
		var e: Dictionary = g.enemies[j]
		if e.dead:
			continue
		var off: Vector2 = e.pos - o.pos
		var d: float = off.length()
		if d > reach or d < 1.0 or absf(dir.angle_to(off)) > cone:
			continue
		cands.append(e)
	if cands.is_empty():
		var far: float = float(b.get("aim_empty", 300.0))
		return o.pos + dir * far if far > 0.0 else hw_tether_target(o, b)
	var r: float = float(b.get("r", 140.0)) * o.stat(&"op_range")
	var step: int = maxi(1, int(cands.size() / 24.0))
	var best: Vector2 = cands[0].pos
	var bn := -1
	for a in range(0, cands.size(), step):
		var c: Vector2 = cands[a].pos
		var n := 0
		for e in cands:
			if e.pos.distance_squared_to(c) <= r * r:
				n += 1
		if n > bn:
			bn = n
			best = c
	return best


static func hw_tether_snap(o, b: Dictionary, pt: Vector2) -> Vector2:
	var sn: float = float(b.get("aim_snap", 0.0))
	if sn <= 0.0:
		return pt
	var ts: Array = o.nearest_enemies(1, sn, pt)
	return ts[0].pos if not ts.is_empty() else pt


static func hw_tether_start(o, b: Dictionary) -> void:
	var h := _hw4(o)
	var i: int = o.cur_skill
	var to: Vector2 = hw_tether_target(o, b)
	if b.get("manual", false):
		if o.manual_pt != Vector2.INF:
			to = hw_tether_snap(o, b, o.manual_pt)
		elif o.manual_dir != Vector2.ZERO:
			to = hw_tether_aim_dir(o, b, o.manual_dir)
		o.manual_dir = Vector2.ZERO
		o.manual_pt = Vector2.INF
	if to == Vector2.INF:
		if i >= 0:
			o.sp[i] = o.sp_need(i) * float(b.get("refund", 0.6))
		return
	h.anchor = {"b": b, "phase": "throw", "t": 0.0, "dur": float(b.get("throw", 0.16)), "from": Vector2.ZERO, "to": to, "trail": []}
	h.anchor.from = _hw_hand(o)


static func _hw_anchor_pos(an: Dictionary, k: float) -> Vector2:
	var travel: float = k * k * (2.0 - k)
	return (an.from as Vector2).lerp(an.to, travel) + Vector2(0, -sin(k * PI) * 10.0)


## 每帧（hw_tick）：飞 → 咬地 → 收链 / 停顿 / 重砸，或弹射 → 落地
static func _hw4_anchor(o, dt: float) -> void:
	var h: Dictionary = o.hw
	var an: Dictionary = h.anchor
	an.t = float(an.t) + dt
	var k: float = clampf(float(an.t) / float(an.dur), 0.0, 1.0)
	match str(an.phase):
		"throw":
			an.trail.push_front(_hw_anchor_pos(an, k))
			if an.trail.size() > 4:
				an.trail.pop_back()
			if k >= 1.0:
				_hw_anchor_bite(o)
		"reel":
			var kr: float = 1.0 - (1.0 - k) * (1.0 - k)
			an.head = (an.to as Vector2).lerp(an.front, kr)
			for hk in h.hooked:
				var e: Dictionary = hk.e
				if e.dead:
					continue
				e.pos = (hk.from as Vector2).lerp(hk.to, kr)
				e.kb = Vector2.ZERO
				e.stun = maxf(e.stun, 0.2)
			an.trail.push_front(an.head)
			if an.trail.size() > 5:
				an.trail.pop_back()
			if k >= 1.0:
				_hw_reel_arrive(o)
		"hold":
			if k >= 1.0:
				_hw_reel_slam(o)
				h.anchor = {}
		_:
			var kk: float = k * k
			o.pos = (an.start as Vector2).lerp(an.land, kk)
			o.face = signf(an.land.x - an.start.x) if absf(an.land.x - an.start.x) > 1.0 else o.face
			an.trail.push_front(o.pos)
			if an.trail.size() > 5:
				an.trail.pop_back()
			if k >= 1.0:
				_hw_zip_land(o)
				h.anchor = {}


static func _hw_anchor_bite(o) -> void:
	var g = o.g
	var h: Dictionary = o.hw
	var an: Dictionary = h.anchor
	var b: Dictionary = an.b
	var to: Vector2 = an.to
	var dir: Vector2 = (to - o.pos).normalized() if to.distance_to(o.pos) > 1.0 else Vector2(o.face, 0)
	var big: bool = b.get("big", false)
	o.impact_pause(0.07 if big else 0.05)
	o.fx({"kind": "glow", "pos": to + Vector2(0, -6), "r": 18.0 if big else 14.0, "life": 0.12, "col": Color(1.4, 1.7, 2.3), "alpha": 0.8})
	o.fx({"kind": "ring", "pos": to, "r": 48.0 if big else 36.0, "r0": 6.0, "life": 0.22, "col": HW_STEEL, "floor": true, "w": 3.0})
	_hw_splash(o, to, 6, 0.8)
	for i in 6:
		var a: float = dir.angle() + g.vrng.randf_range(-0.9, 0.9)
		o.fx({"kind": "spark", "pos": to + Vector2(0, -6), "vel": Vector2.from_angle(a) * g.vrng.randf_range(160, 300), "life": 0.22, "col": HW_CHAIN, "sz": 2.5})
	if str(b.get("mode", "zip")) == "reel" and _hw_start_reel(o, to, dir):
		var rf = b.get("rift", null)
		if rf is Dictionary and hw_face_ok(o, rf.get("cond", true)):
			_hw_open_rift(o, rf, o.pos, to)
		return
	var land: Vector2 = to - dir * 18.0
	an.phase = "zip"
	an.t = 0.0
	an.dur = clampf(o.pos.distance_to(land) / 1400.0, 0.08, 0.2)
	an.start = o.pos
	an.land = land
	an.trail = []
	o.melee_tgt = null


static func _hw_start_reel(o, to: Vector2, dir: Vector2) -> bool:
	var h: Dictionary = o.hw
	var an: Dictionary = h.anchor
	var b: Dictionary = an.b
	var hm = b.get("hook_more", {})
	var more: bool = hm is Dictionary and not hm.is_empty() and hw_face_ok(o, hm.get("cond", true))
	var hr: float = float(b.get("hook_r", 50.0)) * (float(hm.get("r_mult", 1.0)) if more else 1.0)
	var near: Array = o.nearest_enemies(12, hr, to)
	if near.is_empty() or near[0].boss:
		return false
	var n: int = int(b.get("hook_n", 2)) + (int(hm.get("n", 0)) if more else 0)
	var front: Vector2 = o.pos + dir * float(b.get("front", 34.0))
	h.hooked.clear()
	for e in near:
		if h.hooked.size() >= n:
			break
		if e.dead or e.boss:
			continue
		var i: int = h.hooked.size()
		var side: float = (1.0 if i % 2 == 1 else -1.0) * ceilf(i / 2.0)
		var spot: Vector2 = front + dir * (e.r * 0.5) + dir.orthogonal() * side * 16.0 + dir * absf(side) * 6.0
		h.hooked.append({"e": e, "from": e.pos, "to": spot})
		o.fx({"kind": "glow", "pos": e.pos + Vector2(0, -e.r * 0.5), "r": 12.0, "life": 0.18, "col": HW_EDGE, "alpha": 0.7})
	if h.hooked.is_empty():
		return false
	an.phase = "reel"
	an.t = 0.0
	an.dur = clampf(o.pos.distance_to(to) / 900.0, 0.16, 0.34)
	an.front = front
	an.head = to
	an.trail = []
	an.elite = h.hooked[0].e.elite
	if b.has("hook_text"):
		o.float_text(to + Vector2(0, -40), str(b.hook_text), HW_STEEL, 14)
	_hw_sfx_play(o, "tentacle", -6.0, 0.7)
	return true


static func _hw_reel_arrive(o) -> void:
	var h: Dictionary = o.hw
	var an: Dictionary = h.anchor
	var b: Dictionary = an.b
	var c: Vector2 = an.front
	for hk in h.hooked:
		var e: Dictionary = hk.e
		if e.dead:
			continue
		e.stun = maxf(e.stun, float(b.get("stun", 0.6)) * (0.5 if e.elite else 1.0) + 0.25)
		o.fx({"kind": "glow", "pos": e.pos + Vector2(0, -e.r * 0.6), "r": 10.0, "life": 0.25, "col": Color(1.3, 1.5, 2.0), "alpha": 0.6})
	o.impact_pause(0.05)
	o.fx({"kind": "ring", "pos": c, "r": 34.0, "r0": 4.0, "life": 0.2, "col": HW_CHAIN, "floor": true, "w": 2.0})
	for i in 5:
		o.fx({"kind": "spark", "pos": c + Vector2(0, -30), "vel": Vector2.from_angle(i * TAU / 5.0) * 60.0, "life": 0.3, "col": Color(1.4, 1.4, 0.8), "sz": 2.0})
	an.phase = "hold"
	an.t = 0.0
	an.dur = float(b.get("hold", 0.14))
	o.face_to((c - o.pos).angle())


static func _hw_reel_slam(o) -> void:
	var g = o.g
	var h: Dictionary = o.hw
	var an: Dictionary = h.anchor
	var b: Dictionary = an.b
	var dir: Vector2 = ((an.front as Vector2) - o.pos).normalized()
	var reach: float = shape_radius(o, o.cur_attack())
	var c: Vector2 = o.pos + dir * reach * 0.55
	var r: float = float(b.get("r", 90.0)) * o.stat(&"op_range")
	var dmg: float = o.base(str(b.get("atk_key", "atk")), 0.0) * float(b.get("mult", 1.0)) * o._dmg_bonus() * o.skill_power()
	var first: Dictionary = h.hooked[0].e if not h.hooked.is_empty() else {}
	var src: String = str(b.get("src", ""))
	for j in o.query_ids(c, r + 30.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or e.pos.distance_to(c) > r + e.r:
			continue
		o.log_hit(src)
		o.deal_damage(e, dmg * (float(b.get("elite_mult", 1.0)) if is_same(e, first) and e.elite else 1.0))
		if not e.dead:
			e.stun = maxf(e.stun, float(b.get("stun", 0.6)) * (0.5 if e.elite or e.boss else 1.0))
			if not e.boss:
				e.kb += (e.pos - o.pos).normalized() * float(b.get("slam_kb", 70.0))
	o.spawn_fx_sprite("fx_slash_heavy_steel", o.pos + Vector2(0, -16) + dir * reach * 0.45, reach * 1.5 / 28.0, dir.angle())
	_hw_slam_fx(o, c, r, 1.2)
	o.impact_pause(0.07)
	_hw_sfx_op(o, "atk", 2.0, 0.85)
	h.hooked.clear()


static func _hw_zip_land(o) -> void:
	var g = o.g
	var h: Dictionary = o.hw
	var an: Dictionary = h.anchor
	var b: Dictionary = an.b
	var c: Vector2 = an.land
	var r: float = float(b.get("r", 90.0)) * o.stat(&"op_range")
	var dmg: float = o.base(str(b.get("atk_key", "atk")), 0.0) * float(b.get("mult", 1.0)) * o._dmg_bonus() * o.skill_power()
	var src: String = str(b.get("src", ""))
	var sb: float = float(b.get("stun_boss", 0.5))
	var se: float = float(b.get("stun_elite", 0.5))
	var kb_boss: bool = b.get("kb_boss", false)
	for j in o.query_ids(c, r + 30.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or e.pos.distance_to(c) > r + e.r:
			continue
		o.log_hit(src)
		o.deal_damage(e, dmg)
		if not e.dead:
			e.stun = maxf(e.stun, float(b.get("stun", 0.6)) * (sb if e.boss else (se if e.elite else 1.0)))
			if kb_boss or not e.boss:
				e.kb += (e.pos - c).normalized() * float(b.get("land_kb", 50.0))
	var big: bool = b.get("big", false)
	_hw_slam_fx(o, c, r, 1.6 if big else 1.0)
	if big:
		_hw_splash(o, c, 10, 1.3)
	h.prev_dmg = dmg
	h.prev_c = c
	h.prev_r = r
	o._exec_list(b.get("then", []), c)
	if b.has("land_fx"):
		fx_play(o, b.land_fx, c, r)
	o.impact_pause(0.1 if big else 0.06)
	if big:
		_hw_sfx_op(o, "big", 0.0, 1.0)
	else:
		_hw_sfx_op(o, "atk", 2.0, 0.85)
	var dg = b.get("drag", null)
	if dg is Dictionary and hw_face_ok(o, dg.get("cond", true)):
		_hw_drag_in(o, dg, c, dmg * float(dg.get("mult", 0.6)))
	var rf = b.get("rift", null)
	if rf is Dictionary and hw_face_ok(o, rf.get("cond", true)):
		_hw_open_rift(o, rf, an.start, c)


static func _hw_drag_in(o, dg: Dictionary, c: Vector2, dmg: float) -> void:
	var cands: Array = o.nearest_enemies(12, float(dg.get("r", 200.0)), c).filter(func(e): return e.pos.distance_to(c) > 36.0)
	var src: String = str(dg.get("src", ""))
	for k in mini(int(dg.get("n", 3)), cands.size()):
		var e: Dictionary = cands[k]
		o.log_hit(src)
		o.deal_damage(e, dmg)
		o.fx({"kind": "chain", "pos": c + Vector2(0, -12), "to": e.pos + Vector2(0, -e.r * 0.5), "life": 0.3})
		o.fx({"kind": "glow", "pos": e.pos + Vector2(0, -e.r * 0.5), "r": 10.0, "life": 0.2, "col": HW_STEEL, "alpha": 0.6})
		if e.dead or e.boss:
			continue
		var dist: float = maxf(0.0, e.pos.distance_to(c) - 24.0)
		var v: float = minf(sqrt(1800.0 * dist), 620.0) * (0.5 if e.elite else 1.0)
		e.kb += (c - e.pos).normalized() * v
		e.stun = maxf(e.stun, 0.3)


static func _hw_open_rift(o, rf: Dictionary, a: Vector2, b: Vector2) -> void:
	var g = o.g
	if a.distance_to(b) < 8.0:
		return
	var dmg: float = o.base(str(rf.get("atk_key", "atk")), 0.0) * o._dmg_bonus() * float(rf.get("mult", 0.8)) * o.skill_power()
	var w: float = float(rf.get("w", 26.0))
	var d: Vector2 = (b - a).normalized()
	var L: float = a.distance_to(b)
	var src: String = str(rf.get("src", ""))
	for j in o.query_ids((a + b) * 0.5, L * 0.5 + w + 30.0):
		var e: Dictionary = g.enemies[j]
		if e.dead:
			continue
		var rel: Vector2 = e.pos - a
		var along: float = rel.dot(d)
		if along < -e.r or along > L + e.r or absf(rel.cross(d)) > w + e.r:
			continue
		o.log_hit(src)
		o.deal_damage(e, dmg)
		_hw_launch(o, e, float(rf.get("air", 0.8)), float(rf.get("h", 30.0)))
	o.fx({"kind": "rift", "pos": a, "to": b, "life": 0.8, "floor": true, "seed": g.vrng.randf() * 100.0})
	for k in 5:
		var p: Vector2 = a.lerp(b, (k + 0.5) / 5.0)
		_hw_sparks(o, p + Vector2(0, -4), HW_EDGE, 3, 160.0, 0.35, 2.5, 260.0)


## 掀飞：眩晕 + sin 弧线高度（game 按 e.air 抬高绘制）；精英时长减半，Boss 不受；重复施加从头再来、时长取长
static func _hw_launch(o, e: Dictionary, dur: float, hh: float) -> void:
	if e.dead or e.boss:
		return
	if e.elite:
		dur *= 0.5
	e.stun = maxf(e.stun, dur)
	for l in o.hw.launched:
		if is_same(l.e, e):
			l.t = 0.0
			l.dur = maxf(l.dur, dur)
			return
	o.hw.launched.append({"e": e, "t": 0.0, "dur": dur, "h": hh})


static func _hw4_launched(o, dt: float) -> void:
	var h: Dictionary = o.hw
	for l in h.launched:
		l.t += dt
		var e: Dictionary = l.e
		var k: float = clampf(l.t / l.dur, 0.0, 1.0)
		e.air = 0.0 if e.dead or k >= 1.0 else sin(k * PI) * l.h
		if not e.dead:
			e.kb = Vector2.ZERO
	h.launched = h.launched.filter(func(l): return l.t < l.dur and not l.e.dead)


## 每帧（hw_tick 开头转来）：计时 → 锚 → 掀飞（手写 update 的先后）
static func _hw4_tick(o, dt: float) -> void:
	var h: Dictionary = o.hw
	for k in h.timers:
		h.timers[k] = maxf(0.0, float(h.timers[k]) - dt)
	if not h.anchor.is_empty():
		_hw4_anchor(o, dt)
	if not h.launched.is_empty():
		_hw4_launched(o, dt)


## 锚在外面：不起手（hw_busy 转来）
static func hw4_busy(o) -> bool:
	return o.hw.has("anchor") and not o.hw.anchor.is_empty()


## 技能剩余：active_timer（hw_active_left 转来）
static func _hw4_left(o, i: int) -> float:
	var sk: Array = o.B.get("skills", [])
	if i < 0 or i >= sk.size() or not sk[i].has("active_timer"):
		return -1.0
	return float(o.hw.timers.get(str(sk[i].active_timer), 0.0))


# ---------------------------------------------------------------- 手动技能（契约 v2.3–v2.5：data_operator 的 manual_* 转来）

## 技能 i 的 verb.tether（manual: true 的）；没有 = {}
static func hw_tether_of(o, i: int) -> Dictionary:
	if not hw_on(o):
		return {}
	var sk: Array = o.B.get("skills", [])
	if i < 0 or i >= sk.size():
		return {}
	for b in sk[i].get("do", []):
		if str(b.get("_tag", "")) == "verb.tether":
			return b
	return {}


static func hw_manual_ready(o, i: int, dir: Vector2) -> bool:
	var b := hw_tether_of(o, i)
	if b.is_empty():
		return true
	if not _hw4(o).anchor.is_empty():
		return false
	if dir != Vector2.ZERO and float(b.get("aim_free", 1.0)) > 0.0:
		return true
	return not o.nearest_enemies(1, float(b.get("pick_r", 400.0)), o.pos).is_empty()


static func hw_manual_block_reason(o, i: int, dir: Vector2) -> String:
	var b := hw_tether_of(o, i)
	if b.is_empty():
		return ""
	if dir != Vector2.ZERO and float(b.get("aim_free", 1.0)) > 0.0:
		return ""
	if _hw4(o).anchor.is_empty() and o.pos != Vector2.INF and o.nearest_enemies(1, float(b.get("pick_r", 400.0)), o.pos).is_empty():
		return "附近没有敌人"
	return ""


static func hw_manual_aim_point(o, i: int, dir: Vector2) -> Vector2:
	var b := hw_tether_of(o, i)
	if b.is_empty() or o.pos == Vector2.INF:
		return Vector2.INF
	if o.manual_point(i) and o.is_leader:
		var p: Vector2 = o.g.doctor.point_preview(o, i)
		return hw_tether_snap(o, b, o.clamp_point(i, p)) if p != Vector2.INF else hw_tether_target(o, b)
	return hw_tether_aim_dir(o, b, dir.normalized()) if dir != Vector2.ZERO else hw_tether_target(o, b)


## 锚还在飞 / 收链时停在技能条的空手帧（hold_frame），不提前回到持锚姿势；技能动作播完、锚还在外面也停在这帧
static func hw_anim_state(o, st: Dictionary) -> Dictionary:
	if st.is_empty() or not o.hw.has("anchor") or o.hw.anchor.is_empty():
		return st
	var hf: int = int(o.hw.anchor.b.get("hold_frame", 5))
	if st.kind == "skill":
		if int(st.frame) > hf:
			st.frame = hf
	else:
		var tx: Texture2D = o.anim_tex("skill")
		if tx != null:
			st = {"tex": tx, "frame": hf, "hf": o.anim_hframes(tx, "skill"), "flip": (o.face < 0.0) != o.sprite_mirror("skill"), "kind": "skill"}
	return st


# ---------------------------------------------------------------- 画面

static func _hw_sfx_op(o, kind: String, db: float, pitch: float) -> void:
	var sfx: Node = o.g.get_node_or_null("/root/Sfx") if o.g != null and o.g.is_inside_tree() else null
	if sfx != null:
		sfx.op(o.id, kind, db, pitch)


static func _hw_sfx_play(o, nm: String, db: float, pitch: float) -> void:
	var sfx: Node = o.g.get_node_or_null("/root/Sfx") if o.g != null and o.g.is_inside_tree() else null
	if sfx != null:
		sfx.play(nm, db, pitch)


## 同 character.gd fx_sparks，散布用 g.vrng
static func _hw_sparks(o, p: Vector2, c: Color, n: int, spd: float, life := 0.4, sz := 3.0, grav := 0.0) -> void:
	var g = o.g
	n = int(round(n * (1.0 + 0.2 * o.node_lv)))
	for k in n:
		o.fx({"kind": "spark", "pos": p, "vel": Vector2.from_angle(g.vrng.randf() * TAU) * g.vrng.randf_range(spd * 0.4, spd), "life": life * g.vrng.randf_range(0.7, 1.2),
			"col": c, "sz": sz, "drag": 2.0, "grav": grav, "floor": false})


## 深海蓝水珠 + 落点一团蓝水花
static func _hw_splash(o, c: Vector2, n: int, k: float) -> void:
	var g = o.g
	o.spawn_fx_sprite("fx_splash_blue", c + Vector2(0, 6), g.PX * clampf(0.8 * k, 0.8, 1.6), 0.0, false, true)
	for i in n:
		var a: float = -PI / 2.0 + g.vrng.randf_range(-1.1, 1.1)
		o.fx({"kind": "mote", "pos": c + Vector2(g.vrng.randf_range(-10, 10), -4), "vel": Vector2.from_angle(a) * g.vrng.randf_range(90, 190) * k,
			"life": g.vrng.randf_range(0.35, 0.5), "col": HW_WATER, "sz": 2.0 if i % 2 == 0 else 1.5, "grav": 420.0})


## 砸地：尘土 + 顿帧 + 地裂 + 冲击环 + 水珠 + 火花
static func _hw_slam_fx(o, c: Vector2, r: float, k: float) -> void:
	o.ground_dust(c, minf(r * 0.45, 42.0), 10)
	o.impact_pause(0.045 * k)
	o.fx({"kind": "crack", "pos": c, "r": r * 0.9, "life": 0.4 * k, "col": HW_STEEL, "floor": true, "n": 7})
	o.fx({"kind": "ring", "pos": c, "r": r, "r0": 10.0, "life": 0.3 * k, "col": HW_STEEL, "floor": true, "w": 3.0})
	_hw_splash(o, c, int(8 * k), 1.0 * k)
	_hw_sparks(o, c + Vector2(0, -8), HW_CHAIN, 6, 150.0, 0.35, 2.5, 220.0)


static func _hw_draw_chain(o, a: Vector2, b: Vector2, al: float) -> void:
	var cv = o.cv
	cv.draw_line(a, b, Color(0.04, 0.05, 0.08, 0.75 * al), 5.0)
	cv.draw_line(a, b, Color(HW_CHAIN.r, HW_CHAIN.g, HW_CHAIN.b, 0.95 * al), 2.5)
	var tile: String = str(o.hw.get("chain_tex", ""))
	var links: int = clampi(int(a.distance_to(b) / 10.0), 1, 50)
	for i in links:
		var q: Vector2 = a.lerp(b, float(i) / links)
		if i % 2 == 0:
			cv.draw_circle(q, 2.6, Color(HW_CHAIN.r * 0.7, HW_CHAIN.g * 0.7, HW_CHAIN.b * 0.75, al))
		else:
			cv.draw_circle(q, 1.3, Color(1.1, 1.2, 1.35, al))


static func _hw_draw_anchor(o, p: Vector2, d: Vector2, a: float) -> void:
	var g = o.g
	var cv = o.cv
	if g.tex.get("proj_ulpianus_anchor") != null:
		o.draw_spr_rot("proj_ulpianus_anchor", int(g.t * 10.0) % 2, p, d.angle(), g.PX * 0.8, Color(1, 1, 1, a))
		return
	var n: Vector2 = d.orthogonal()
	var outline := Color(0.02, 0.03, 0.06, 0.85 * a)
	var body := Color(HW_ABYSS.r * 1.6, HW_ABYSS.g * 1.6, HW_ABYSS.b * 1.6, a)
	var edge := Color(HW_EDGE.r * 1.3, HW_EDGE.g * 1.3, HW_EDGE.b * 1.3, a)
	var head: Vector2 = p + d * 12.0
	var tail: Vector2 = p - d * 18.0
	cv.draw_line(tail, head, outline, 8.0)
	cv.draw_line(tail, head, body, 5.0)
	var hook := PackedVector2Array()
	for i in 8:
		var u: float = float(i) / 7.0
		var ang: float = lerpf(0.0, 2.4, u)
		hook.append(head + n * sin(ang) * 15.0 - d * (1.0 - cos(ang)) * 11.0)
	cv.draw_polyline(hook, outline, 9.0)
	cv.draw_polyline(hook, body, 5.5)
	cv.draw_polyline(hook.slice(0, 7), edge, 1.5)
	cv.draw_circle(hook[hook.size() - 1], 2.5, edge)
	cv.draw_line(head - d * 2.0, head - d * 9.0 - n * 7.0, outline, 6.0)
	cv.draw_line(head - d * 2.0, head - d * 9.0 - n * 7.0, body, 3.0)
	cv.draw_colored_polygon(PackedVector2Array([head + d * 7.0, head + n * 3.0, head - n * 3.0]), body)
	cv.draw_line(head, head + d * 6.0, edge, 1.5)
	cv.draw_arc(tail - d * 3.0, 3.5, 0.0, TAU, 12, Color(HW_CHAIN.r, HW_CHAIN.g, HW_CHAIN.b, a), 2.0)


## 锚与锁链、弹射残影（data_operator._draw_skill_over）
static func hw_draw_tether(o) -> void:
	var h: Dictionary = o.hw
	var an: Dictionary = h.anchor
	if an.is_empty() or o.pos == Vector2.INF:
		return
	var cv = o.cv
	var k: float = clampf(float(an.t) / float(an.dur), 0.0, 1.0)
	var hand: Vector2 = _hw_hand(o)
	var throwing: bool = an.phase == "throw"
	var reeling: bool = an.phase == "reel" or an.phase == "hold"
	var p: Vector2 = _hw_anchor_pos(an, k) if throwing else (an.to as Vector2) + Vector2(0, -6)
	var d: Vector2 = ((an.to as Vector2) - (an.from as Vector2)).normalized()
	if reeling:
		p = (an.head as Vector2) + Vector2(0, -6) if an.phase == "reel" else (an.front as Vector2) + Vector2(0, -6)
		var tr3: Array = an.trail
		for i in range(tr3.size() - 1, 0, -1):
			_hw_draw_anchor(o, (tr3[i] as Vector2) + Vector2(0, -6), -d, 0.3 * (1.0 - float(i) / tr3.size()))
		for hk in h.hooked:
			if not hk.e.dead:
				_hw_draw_chain(o, p, hk.e.pos + Vector2(0, -hk.e.r * 0.5), 0.8)
		for s in 3:
			var off3: Vector2 = d.orthogonal() * (s - 1) * 9.0
			if an.phase == "reel":
				cv.draw_line(p + d * 24.0 + off3, p + d * (58.0 + s * 12.0) + off3, Color(1.3, 1.5, 1.8, 0.35), 1.5)
	elif not throwing:
		var tr: Array = an.trail
		var mv_d: Vector2 = ((an.land as Vector2) - (an.start as Vector2)).normalized()
		for i in range(tr.size() - 1, 0, -1):
			o.draw_body_at(tr[i], o.face < 0.0, Color(HW_EDGE.r, HW_EDGE.g, HW_EDGE.b, 0.35 * (1.0 - float(i) / tr.size())))
		for s in 3:
			var off: Vector2 = mv_d.orthogonal() * (s - 1) * 10.0 + Vector2(0, -20)
			cv.draw_line(o.pos - mv_d * 16.0 + off, o.pos - mv_d * (56.0 + s * 14.0) + off, Color(1.3, 1.5, 1.8, 0.4), 1.5)
	_hw_draw_chain(o, hand, p, 1.0)
	if throwing:
		var tr2: Array = an.trail
		for i in range(tr2.size() - 1, 0, -1):
			_hw_draw_anchor(o, tr2[i], d, 0.3 * (1.0 - float(i) / tr2.size()))
		for s in 3:
			var off2: Vector2 = d.orthogonal() * (s - 1) * 9.0
			cv.draw_line(p - d * 24.0 + off2, p - d * (58.0 + s * 12.0) + off2, Color(1.3, 1.5, 1.8, 0.6), 2.0)
	_hw_draw_anchor(o, p, -d if reeling else d, 1.0)


## 程序粒子：whirl（锁链带锚甩一圈）/ chain（拽敌锁链）/ rift（通路裂隙）
static func hw4_draw_pfx(o, f: Dictionary, a: float) -> bool:
	var cv = o.cv
	match str(f.kind):
		"whirl":
			var u: float = 1.0 - a
			var dirv: float = float(f.get("dir", 1.0))
			var head: float = float(f.get("a0", 0.0)) + dirv * TAU * (1.0 - (1.0 - u) * (1.0 - u))
			var c: Vector2 = f.pos + Vector2(0, -14)
			var R: float = f.r * 0.85
			var trail := PackedVector2Array()
			for i in 16:
				var an: float = head - dirv * 2.2 * float(i) / 15.0
				trail.append(c + Vector2(cos(an) * R, sin(an) * R * 0.55))
			for i in 15:
				var al: float = (1.0 - float(i) / 15.0) * minf(1.0, a * 2.0)
				cv.draw_line(trail[i], trail[i + 1], Color(HW_EDGE.r * 1.4, HW_EDGE.g * 1.4, HW_EDGE.b * 1.4, 0.7 * al), 6.0 * (1.0 - float(i) / 15.0) + 1.0)
			_hw_draw_chain(o, f.pos + Vector2(0, -22), trail[0], minf(1.0, a * 2.0))
			_hw_draw_anchor(o, trail[0], Vector2.from_angle(head + dirv * PI * 0.5), minf(1.0, a * 2.0))
			return true
		"chain":
			var u2: float = 1.0 - a
			var tip: Vector2 = (f.pos as Vector2).lerp(f.to, minf(1.0, u2 / 0.4)) if u2 < 0.4 else (f.to as Vector2).lerp(f.pos, (u2 - 0.4) / 0.6)
			_hw_draw_chain(o, f.pos, tip, 1.0)
			cv.draw_circle(tip, 4.0, Color(HW_EDGE.r * 1.5, HW_EDGE.g * 1.5, HW_EDGE.b * 1.5, 0.9))
			return true
		"rift":
			var A: Vector2 = f.pos
			var B: Vector2 = f.to
			var L: float = A.distance_to(B)
			var dd: Vector2 = (B - A) / maxf(1.0, L)
			var nn: Vector2 = dd.orthogonal()
			var m: int = clampi(int(L / 14.0), 3, 40)
			var al2: float = minf(1.0, a * 2.0)
			var prev: Vector2 = A
			for i in range(1, m + 1):
				var t: float = float(i) / m
				var p: Vector2 = A + dd * L * t + nn * (sin(float(f.seed) + i * 1.7) * 5.0 if i < m else 0.0)
				var w: float = 2.0 + 5.0 * sin(t * PI)
				cv.draw_line(prev, p, Color(0.04, 0.03, 0.05, 0.9 * al2), w)
				cv.draw_line(prev, p, Color(HW_EDGE.r * 1.6, HW_EDGE.g * 1.6, HW_EDGE.b * 1.8, 0.8 * clampf((a - 0.3) * 2.0, 0.0, 1.0)), maxf(1.0, w * 0.35))
				prev = p
			return true
	return false


## blocks.look 里的轮廓光（outline，draw_body 前）：当前帧贴图的白色剪影向 8 个方向偏移、染色，两圈（rings [[偏移, 透明度倍率]…]），呼吸
static func hw_draw_outline(o, f: Dictionary) -> void:
	var g = o.g
	var ol: Dictionary = f.outline
	var st: Dictionary = o.anim_state()
	if st.is_empty():
		return
	var hz: float = float(ol.get("hz", 2.5))
	var pul: float = 0.5 + 0.5 * sin(g.t * hz)
	var av = ol.get("a", [0.3, 0.2])
	var al: float = float(av[0]) + float(av[1]) * pul
	var fo: float = o.foot_off(st.tex, st.get("kind", ""))
	var sil: Dictionary = _hw4(o).sil
	var wt: Texture2D = sil.get(st.tex)
	if wt == null:
		wt = ArtS.white_of(st.tex)
		sil[st.tex] = wt
	var cc: Color = _mf_col(ol.get("col", []), Color(1.0, 0.45, 0.5))
	for ring in ol.get("rings", [[4.0, 0.3], [2.0, 0.9]]):
		var c := Color(cc.r, cc.g, cc.b, al * float(ring[1]))
		for i in 8:
			var off: Vector2 = Vector2.from_angle(i * TAU / 8.0) * float(ring[0])
			o.draw_sprite_at(o.pos + off + Vector2(o.foot_dx(st), 0), st.flip, c, st.frame, wt, st.hf, fo)


## blocks.look：按 cond 常驻的画面（aura_ring 在区域层、outline 在本体后）
static func hw_draw_look(o, layer: String) -> void:
	if o.pos == Vector2.INF:
		return
	for f in o.B.get("look", []):
		if not (f is Dictionary) or not fx_on(o, f):
			continue
		if layer == "body" and f.has("outline"):
			hw_draw_outline(o, f)
		elif layer == "auras" and f.has("aura_ring"):
			_hw_ring_one(o, f, 1.0)


static func _hw_ring_one(o, f: Dictionary, al: float) -> void:
	var g = o.g
	var rv: Dictionary = f.aura_ring
	var r: float = shape_radius(o, o.cur_attack()) if str(rv.get("r", "attack")) == "attack" else float(rv.r)
	var c: Vector2 = g.ppos if str(f.get("at", "self")) == "leader" else o.pos
	var ov = f.get("off", [0, 4])
	c += Vector2(float(ov[0]), float(ov[1])) if ov is Array and ov.size() == 2 else Vector2.ZERO
	var col: Color = _mf_col(rv.get("col", []), o.col())
	var pul: float = 0.5 + 0.5 * sin(g.t * float(rv.get("hz", 5.0)))
	o.cv.draw_set_transform(c, 0.0, Vector2(1.0, float(rv.get("sy", 0.55))))
	if float(rv.get("fill", 0.0)) > 0.0:
		o.cv.draw_circle(Vector2.ZERO, r, Color(col.r, col.g, col.b, (float(rv.fill) + float(rv.get("fill_pulse", 0.0)) * pul) * al))
	o.cv.draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(col.r * float(rv.get("arc_k", 1.0)), col.g, col.b, float(rv.get("a", 0.3)) * (1.0 - float(rv.get("pulse", 0.0)) + float(rv.get("pulse", 0.0)) * pul) * al), float(rv.get("w", 2.0)))
	o.cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func hw4_status_items(o) -> Array:
	var out: Array = []
	var h: Dictionary = o.hw
	for k in h.stacks:
		var b: Dictionary = h.blk.get("stack:" + str(k), {})
		if int(h.stacks[k]) > 0 and b.has("status"):
			out.append([str(b.status) % int(h.stacks[k]), _mf_col(b.get("status_col", []), Color(0.9, 0.4, 0.45))])
	for k in h.timers:
		var b2: Dictionary = h.blk.get("timer:" + str(k), {})
		if float(h.timers[k]) > 0.0 and b2.has("status"):
			out.append([str(b2.status), _mf_col(b2.get("status_col", []), HW_STEEL)])
	for k in h.armed:
		var b3: Dictionary = h.blk.get("armed:" + str(k), {})
		if h.armed[k] and b3.has("status"):
			out.append([str(b3.status), _mf_col(b3.get("status_col", []), HW_BLOOD)])
	return out


## Tab 面板的行：verb.stack 的 row（「血脉层数」n / 上限）
static func hw_stats_rows(o) -> Array:
	var out: Array = h3_rows(o)   # 手写迁移段第 3 批（水月的伞击数值行）
	if not out.is_empty():
		return out
	if not hw_on(o) or not o.hw.has("stacks"):
		return out
	for t in o.B.get("trait", []) + o.B.get("talent", []):
		for b in t.get("do", []):
			if str(b.get("_tag", "")) == "verb.stack" and b.has("row"):
				out.append([str(b.row), "%d / %d" % [hw_stack_n(o, str(b.get("key", "stack"))), hw_stack_cap(o, b)]])
	return out


# ---------------------------------------------------------------- 本段的校验

static func _hw4_block(b: Dictionary, p: String, kind: String, ctx: Dictionary, tag: String) -> bool:
	if not tag in HW4_TAGS:
		return false
	var errs: Array = ctx.errs
	var where_ok := {
		"verb.tether": ["skill"],
		"verb.stack": ["instant"],
		"verb.arm": ["instant"],
		"verb.timer": ["skill", "instant"],
	}
	if not kind in where_ok[tag]:
		errs.append("%s：「%s」不能放在这里（%s；只能在 %s）" % [p, tag, kind, " / ".join(where_ok[tag])])
		return true
	match tag:
		"verb.tether":
			if not str(b.get("mode", "zip")) in ["reel", "zip"]:
				errs.append(p + ".mode 只能是 reel / zip")
			if not str(b.get("pick", "densest")) in ["elite", "densest"]:
				errs.append(p + ".pick 只能是 elite / densest")
			_num(b, "throw", p, ctx, true, 0.02, 2.0)
			_num(b, "r", p, ctx, true, 1.0, 800.0)
			_num(b, "mult", p, ctx, true, 0.0, 20.0)
			_num(b, "stun", p, ctx, false, 0.0, 10.0)
			_num(b, "hold_frame", p, ctx, false, 0.0, 30.0)
			for k in ["drag", "rift", "hook_more"]:
				if b.has(k) and not (b[k] is Dictionary):
					errs.append("%s.%s 必须是对象" % [p, k])
			_list(b.get("then", []), p + ".then", "instant", ctx)
			_src(b, p, ctx, true)
			for k in ["drag", "rift"]:
				if b.get(k, null) is Dictionary:
					_src(b[k], "%s.%s" % [p, k], ctx, true)
		"verb.stack":
			if str(b.get("key", "")) == "":
				errs.append(p + " 缺 key")
			_num(b, "add", p, ctx, false, 0.0, 50.0)
			_num(b, "add_boss", p, ctx, false, 0.0, 50.0)
			_num(b, "cap", p, ctx, true, 1.0, 999.0)
		"verb.arm":
			if str(b.get("key", "")) == "":
				errs.append(p + " 缺 key")
		"verb.timer":
			if str(b.get("key", "")) == "":
				errs.append(p + " 缺 key")
			_num(b, "dur", p, ctx, true, 0.05, 120.0)
	return true


# ================================================================ 精英化第 2 批（docs/91 §19 批 2：逻各斯 / 艾雅法拉 / 斯卡蒂 / 乌尔比安的精一 / 精二形态，docs/61 §18，10-14）
# 只往后加，建在手写迁移段上（hw 状态）。新积木：
#  verb.requiem_stack  常驻：本干员挂的「安魂」可叠层——再挂一次 +1 层（至多 max），每层受到的法术伤害 + per（combat.gd 读 e.requiem_k；不叠层时照旧 +15%）；
#                      look：按层数分档的头顶符文帧条（[1 层, 2 层, 3 层]）。逻各斯精一「剜魂」
#  verb.link           瞬时（命中 then）：从命中的敌人向 r 内最近 n 名拉出链 dur 秒（同时 ≤ cap 组）；链上任一名受到本干员 kinds 类伤害（来源不在 exclude 里）时，
#                      同组其他人各受到这次伤害 × share（src；链内不再互相传递）。tile / anchor / pulse：链节平铺、两端咒文结、传递时亮起。逻各斯精二「连缀」
#  shape.shell 的 lob  法术弹改低弧抛射：n 发（第 k 发 × mults[k]、晚 gap × k 秒出手）在目标周围呈三角（相邻落点间距 spacing）落下，飞 flight 秒、顶点 apex，
#                      落地在 aoe 内爆炸（同 fire 子弹：伤害发射时定、不乘 vs_elite），再执行 on_explode；整组落完在三角中心执行 pool（target = 中心，basis hit = 第一发）。
#                      没有落点预示圈，只有地面小影子。艾雅法拉精二「三重咏唱·低抛」
#  shape.wave 的 from: self / aim: nearest / fan / proj / hit_fx / release_fx   从本干员脚底朝最近敌人（aim_r 内，没有朝面向）放出，fan = 几道的偏角（度）；
#                      proj = 旋转的弹体帧条；命中 / 出手画面。斯卡蒂精二「涌潮」潮刃
#  verb.displace 的 r: attack + r_mult、r_in: attack   半径按当前普攻半径；r_in 内（已被这一下打到的）不拉。乌尔比安精一「收链」
#  shape.hookshot      瞬时：把锚掷向 range（× op_range）内离本干员最远、且在 min_d 外的敌人（没有就最近的），飞 clamp(距离 / speed, 0.1, 0.24) 秒（低弧 apex），
#                      落地 r 内 basis × mult（src），锁链绷直 taut 秒后把本干员与锚之间宽 w 的一线非 Boss 敌人连同锚拖回身前 front 处（drag 秒），
#                      到了再受 basis × back_mult（back_src）；lock = 锚在外面时不普攻。乌尔比安精二「掷锚」
# 确定性：本段不取 g.rng；画面只用 g.vrng 与 g.t。

const HW5_TAGS := ["verb.requiem_stack", "verb.link", "shape.hookshot"]
const HW_LINK_CAP := 8
const HW_HOOK_MAX := 2


static func _hw5(o) -> Dictionary:
	var h := hw_st(o)
	if not h.has("links"):
		h.merge({"links": [], "rq": {}, "rq_list": [], "melt_list": [], "lobvol": [], "hooks": [], "link_busy": false, "vid": 0})
	return h


# ---------------------------------------------------------------- 常驻（data_operator._sustain 末尾转来）：本帧生效的叠层安魂
static func hw_sustain(o, act: Array) -> void:
	if not o.hw.has("links"):
		return
	o.hw.rq = {}
	for b in act:
		if str(b.get("_tag", "")) == "verb.requiem_stack":
			o.hw.rq = b
			break


## st.requiem 叠层（hw_status 转来）：返回 true = 已按叠层处理
static func hw_requiem_stack(o, e: Dictionary, s: Dictionary) -> bool:
	var h: Dictionary = o.hw
	var rq: Dictionary = h.get("rq", {})
	if rq.is_empty():
		return false
	var n: int = mini(int(e.get("requiem_n", 0)) + 1, int(rq.get("max", 3))) if float(e.get("requiem", 0.0)) > 0.0 else 1
	e["requiem_n"] = n
	e["requiem_k"] = float(rq.get("per", 0.06)) * n
	e["requiem"] = float(s.dur)
	var lst: Array = h.rq_list
	if not lst.any(func(x): return is_same(x, e)):
		lst.append(e)
		if lst.size() > 96:
			lst.pop_front()
	return true


# ---------------------------------------------------------------- verb.link

static func hw_link(o, b: Dictionary) -> void:
	var h := _hw5(o)
	var e: Dictionary = h.get("hit_e", {})
	if e.is_empty() or e.dead:
		return
	var n: int = int(b.get("n", 2))
	var mem: Array = [e]
	for q in o.nearest_enemies(n + 2, float(b.get("r", 120.0)), e.pos):
		if mem.size() > n:
			break
		if q.dead or is_same(q, e):
			continue
		mem.append(q)
	if mem.size() < 2:
		return
	h.links.append({"m": mem, "t": float(b.get("dur", 1.5)), "dur": float(b.get("dur", 1.5)), "b": b, "pulse": {}})
	while h.links.size() > mini(int(b.get("cap", 4)), HW_LINK_CAP):
		h.links.pop_front()


static func _hw5_links(o, dt: float) -> void:
	var h: Dictionary = o.hw
	for lk in h.links:
		lk.t = float(lk.t) - dt
		for k in lk.pulse.keys():
			lk.pulse[k] = float(lk.pulse[k]) - dt
	h.links = h.links.filter(func(lk): return float(lk.t) > 0.0 and lk.m.filter(func(q): return not q.dead).size() >= 2)


## 本干员造成伤害之后（data_operator.deal_damage 转来）：链上传递
static func hw_dealt(o, e: Dictionary, dmg: float) -> void:
	var h: Dictionary = o.hw
	if not h.has("links") or h.links.is_empty() or h.link_busy or dmg <= 0.0:
		return
	var g = o.g
	var src: String = str(g.hit.get("src", ""))
	var hs: Dictionary = o.def.get("hit_sources", {}).get(src, {})
	var keep = g.hit
	h.link_busy = true
	for lk in h.links:
		var b: Dictionary = lk.b
		if src in b.get("exclude", []) or not str(hs.get("kind", "")) in b.get("kinds", ["法术"]):
			continue
		var at: int = -1
		for i in lk.m.size():
			if is_same(lk.m[i], e):
				at = i
				break
		if at < 0:
			continue
		for i in lk.m.size():
			var q: Dictionary = lk.m[i]
			if i == at or q.dead:
				continue
			o.log_hit(str(b.get("src", "")), b.get("tags", []))
			o.deal_damage(q, dmg * float(b.get("share", 0.3)))
			lk.pulse[i] = 0.2
		lk.pulse[at] = 0.2
	h.link_busy = false
	g.hit = keep


static func hw_draw_links(o) -> void:
	var g = o.g
	var h: Dictionary = o.hw
	if not h.has("links"):
		return
	for lk in h.links:
		var b: Dictionary = lk.b
		var al: float = clampf(float(lk.t) / 0.25, 0.0, 1.0) * clampf((float(lk.dur) - float(lk.t)) / 0.12, 0.0, 1.0)
		var m: Array = lk.m
		var a0: Dictionary = m[0]
		if a0.dead:
			continue
		var pa: Vector2 = a0.pos + Vector2(0, -float(a0.r) * 0.6)
		for i in range(1, m.size()):
			var q: Dictionary = m[i]
			if q.dead:
				continue
			var pb: Vector2 = q.pos + Vector2(0, -float(q.r) * 0.6)
			var tile: String = str(b.get("tile", ""))
			if tile != "" and g.tex.get(tile) != null:
				_hw_draw_tiled(o, tile, pa, pb, g.PX, fmod(g.t * 40.0, 16.0 * g.PX), i, Color(1, 1, 1, al))
				var pl: String = str(b.get("pulse", ""))
				if pl != "" and g.tex.get(pl) != null and (float(lk.pulse.get(i, 0.0)) > 0.0 or float(lk.pulse.get(0, 0.0)) > 0.0):
					var k: float = clampf(float(lk.pulse.get(i, lk.pulse.get(0, 0.0))) / 0.2, 0.0, 1.0)
					_hw_draw_tiled(o, pl, pa, pb, g.PX, 0.0, 0, Color(1, 1, 1, al * k))
			else:
				o.cv.draw_line(pa, pb, Color(0.03, 0.03, 0.08, 0.6 * al), 3.0)
				o.cv.draw_line(pa, pb, Color(HW_PALE.r * 1.4, HW_PALE.g * 1.4, HW_PALE.b * 1.5, 0.8 * al), 1.0)
		var an: String = str(b.get("anchor", ""))
		for q in m:
			if q.dead:
				continue
			var p: Vector2 = q.pos + Vector2(0, -float(q.r) * 0.6)
			if an != "" and g.tex.get(an) != null and g.V6_FRAMES.has(an):
				var spec: Array = g.V6_FRAMES[an]
				fx_frame(o.cv, g, an, int(spec[0]), int(g.t * float(spec[1])), p, g.PX, Color(1, 1, 1, al))
			else:
				o.cv.draw_arc(p, 6.0, 0.0, TAU, 12, Color(HW_PALE.r, HW_PALE.g, HW_PALE.b, 0.8 * al), 1.5)


## 叠层安魂的头顶符文（look：[1 层, 2 层, 3 层] 帧条，n 层横排 n 枚）
static func hw_draw_runes(o) -> void:
	var g = o.g
	var h: Dictionary = o.hw
	if not h.has("rq_list") or h.rq_list.is_empty():
		return
	h.rq_list = h.rq_list.filter(func(e): return not e.dead and float(e.get("requiem", 0.0)) > 0.0)
	var rq: Dictionary = h.get("rq", {})
	var look: Array = rq.get("look", [])
	for e in h.rq_list:
		var n: int = clampi(int(e.get("requiem_n", 1)), 1, 3)
		var al: float = clampf(float(e.requiem) / 0.4, 0.0, 1.0)
		var tn: String = str(look[n - 1]) if look.size() >= n else ""
		var top: Vector2 = e.pos + Vector2(0, -float(e.r) * 2.0 - 12.0)
		for i in n:
			var p: Vector2 = top + Vector2((i - (n - 1) * 0.5) * 9.0, 0)
			if tn != "" and g.tex.get(tn) != null and g.V6_FRAMES.has(tn):
				var spec: Array = g.V6_FRAMES[tn]
				fx_frame(o.cv, g, tn, int(spec[0]), int(g.t * float(spec[1])) + i, p, g.PX, Color(1, 1, 1, al))
			else:
				o.cv.draw_rect(Rect2(p - Vector2(2, 3), Vector2(4, 6)), Color(1.3, 1.1, 0.5, 0.9 * al))


## 熔蚀：被打中的敌人脚下暗红裂纹（st.fragile kind arts 的 look 帧条：前三成出现、中段停在中间帧、最后 0.3 秒淡出）
static func hw_melt_mark(o, e: Dictionary, s: Dictionary) -> void:
	var h := _hw5(o)
	for m in h.melt_list:
		if is_same(m.e, e):
			m.until = float(e.melt_t)
			m.tn = str(s.get("look", ""))
			return
	h.melt_list.append({"e": e, "t0": float(o.g.t), "until": float(e.melt_t), "tn": str(s.get("look", ""))})
	if h.melt_list.size() > 96:
		h.melt_list.pop_front()


static func hw_draw_melt(o) -> void:
	var g = o.g
	var h: Dictionary = o.hw
	if not h.has("melt_list") or h.melt_list.is_empty():
		return
	h.melt_list = h.melt_list.filter(func(m): return not m.e.dead and float(m.until) > float(g.t))
	for m in h.melt_list:
		var tn: String = str(m.tn)
		var e: Dictionary = m.e
		var el: float = float(g.t) - float(m.t0)
		var left: float = float(m.until) - float(g.t)
		if tn != "" and g.tex.get(tn) != null and g.V6_FRAMES.has(tn):
			var spec: Array = g.V6_FRAMES[tn]
			var nf: int = int(spec[0])
			var fps: float = float(spec[1])
			var fr: int = mini(int(el * fps), nf / 2)
			if left < 0.3:
				fr = clampi(nf - 1 - int(left / 0.3 * (nf - 1 - nf / 2)), nf / 2, nf - 1)
			fx_frame(o.cv, g, tn, nf, fr, e.pos + Vector2(0, float(e.r) * 0.6), g.PX * clampf(float(e.r) / 10.0, 1.0, 2.2), Color(1, 1, 1, 0.9))
		else:
			o.cv.draw_set_transform(e.pos + Vector2(0, float(e.r) * 0.6), 0.0, Vector2(1.0, 0.45))
			for q in 3:
				var a: float = q * TAU / 3.0 + float(e.id) * 0.7
				o.cv.draw_arc(Vector2.ZERO, float(e.r) + 3.0, a, a + 0.8, 4, Color(0.9, 0.3, 0.1, 0.7 * clampf(left / 0.5, 0.0, 1.0)), 2.0)
			o.cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---------------------------------------------------------------- shape.shell 的 lob（低弧抛射三角落点 + 熔池）

static func hw_lob_volley(o, b: Dictionary, tip: Vector2, P: Vector2, pre: float, aoe: float, oe: Array) -> void:
	var h := _hw5(o)
	var lb: Dictionary = b.lob
	var n: int = int(lb.get("n", 3))
	var mults: Array = lb.get("mults", [1.0])
	var R: float = float(lb.get("spacing", 40.0)) / sqrt(3.0)
	var d: Vector2 = (P - tip).normalized() if P.distance_to(tip) > 1.0 else Vector2(o.face, 0)
	h.vid = int(h.vid) + 1
	var vol := {"id": h.vid, "left": n, "P": P, "base": pre * o._dmg_bonus(), "b": b, "aoe": aoe}
	h.lobvol.append({"vol": vol, "shots": []})
	var shots: Array = h.lobvol[-1].shots
	for k in n:
		var a: float = d.angle() + k * TAU / float(n)
		var to: Vector2 = P + Vector2(cos(a) * R, sin(a) * R * 0.7)
		var mk: float = float(mults[mini(k, mults.size() - 1)])
		shots.append({"to": to, "wait": float(lb.get("gap", 0.12)) * k, "t": -1.0, "dur": float(lb.get("flight", 0.25)), "pre": pre * mk,
			"aoe": aoe, "oe": oe, "tip": tip - o.pos, "from": tip, "dmg": 0.0, "sz": 1.0 if k == 0 else 1.15})


static func _hw5_lobs(o, dt: float) -> void:
	var g = o.g
	var h: Dictionary = o.hw
	for v in h.lobvol:
		var vol: Dictionary = v.vol
		var b: Dictionary = vol.b
		var lb: Dictionary = b.lob
		for s in v.shots:
			if float(s.t) < 0.0:
				s.wait = float(s.wait) - dt
				if float(s.wait) <= 0.0 and o.pos != Vector2.INF:   # 出手：伤害按此刻加成定（同 fire 子弹）
					s.t = 0.0
					s.from = o.pos + s.tip
					s.dmg = float(s.pre) * o._dmg_bonus()
					if absf(s.to.x - s.from.x) > 1.0:
						o._set_face(signf(s.to.x - s.from.x))
					o._sfx_op("atk")
				continue
			if float(s.t) >= float(s.dur):
				continue
			s.t = float(s.t) + dt
			if float(s.t) >= float(s.dur):
				_hw5_lob_land(o, b, s)
				vol.left = int(vol.left) - 1
				if int(vol.left) <= 0 and lb.has("pool"):
					var keep := hw_snap(o)
					h.hit_dmg = float(vol.base)
					o._exec_list(lb.pool, vol.P)
					hw_pop(o, keep)
	h.lobvol = h.lobvol.filter(func(v): return int(v.vol.left) > 0)


## 落地爆炸：同 weapons.gd 的 fire 子弹（登记一次来源，aoe 内每名敌人吃这一发伤害，不乘 vs_elite），再画面与 on_explode
static func _hw5_lob_land(o, b: Dictionary, s: Dictionary) -> void:
	var g = o.g
	var c: Vector2 = s.to
	var aoe: float = float(s.aoe)
	o.log_hit(str(b.get("src", "")), b.get("tags", []))
	for k in o.query_ids(c, aoe + 20.0):
		var e: Dictionary = g.enemies[k]
		if not e.dead and e.pos.distance_to(c) < aoe + e.r:
			o.deal_damage(e, float(s.dmg))
	o._sfx_op("hit")
	var lb: Dictionary = b.lob
	if lb.has("boom_fx"):
		fx_play(o, lb.boom_fx, c, aoe)
	hw_shell_boom(o, {"pos": c, "dmg": float(s.dmg), "aoe": aoe, "hw_b": {}, "hw_oe": s.oe})


static func hw_draw_lobs(o) -> void:
	var g = o.g
	var h: Dictionary = o.hw
	if not h.has("lobvol"):
		return
	for v in h.lobvol:
		var lb: Dictionary = v.vol.b.lob
		var tn: String = str(lb.get("tex", ""))
		var apex: float = float(lb.get("apex", 20.0))
		for s in v.shots:
			if float(s.t) < 0.0 or float(s.t) >= float(s.dur):
				continue
			var k: float = clampf(float(s.t) / float(s.dur), 0.0, 1.0)
			var gp: Vector2 = (s.from as Vector2).lerp(s.to, k)
			var hh: float = sin(k * PI) * apex
			o.cv.draw_set_transform(gp + Vector2(0, 4), 0.0, Vector2(1.0, 0.5))
			o.cv.draw_circle(Vector2.ZERO, 6.0 * float(s.sz) * (1.0 - 0.3 * hh / maxf(1.0, apex)), Color(0.08, 0.03, 0.02, 0.45))
			o.cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			var p: Vector2 = gp + Vector2(0, -hh - 8.0)
			if tn != "" and g.tex.get(tn) != null and g.V6_FRAMES.has(tn):
				var spec: Array = g.V6_FRAMES[tn]
				fx_frame(o.cv, g, tn, int(spec[0]), int(float(g.t) * float(spec[1])), p, g.PX * float(s.sz), Color.WHITE)
			else:
				o.cv.draw_circle(p, 9.0 * float(s.sz), Color(1.6, 0.55, 0.12, 0.3))
				o.cv.draw_circle(p, 5.5 * float(s.sz), Color(2.2, 0.8, 0.2, 0.95))
				o.cv.draw_circle(p, 2.5 * float(s.sz), Color(2.8, 2.3, 1.4))


# ---------------------------------------------------------------- shape.hookshot（乌尔比安精二「掷锚」）

static func hw_hook_start(o, b: Dictionary) -> void:
	var g = o.g
	var h := _hw5(o)
	if o.pos == Vector2.INF or h.hooks.size() >= HW_HOOK_MAX:
		return
	var rr: float = float(b.get("range", 160.0)) * o.stat(&"op_range")
	var md: float = float(b.get("min_d", 160.0)) * o.stat(&"op_range")
	var best: Dictionary = {}
	var bd := -1.0
	for e in o.nearest_enemies(24, rr, o.pos):
		var dd: float = e.pos.distance_to(o.pos)
		if dd >= md and dd > bd:
			bd = dd
			best = e
	if best.is_empty():
		var ts: Array = o.nearest_enemies(1, rr, o.pos)
		if ts.is_empty():
			return
		best = ts[0]
	var to: Vector2 = best.pos
	var hv = b.get("hand", [33, -33])
	var hand: Vector2 = o.pos + Vector2(float(hv[0]) * float(o.face), float(hv[1]))
	if absf(to.x - o.pos.x) > 2.0:
		o._set_face(signf(to.x - o.pos.x), true)
	var dur: float = clampf(hand.distance_to(to) / float(b.get("speed", 900.0)), 0.1, 0.24)
	h.hooks.append({"b": b, "phase": "fly", "t": 0.0, "dur": dur, "from": hand, "to": to, "head": hand, "drag": [], "dmg": hw_basis(o, str(b.get("basis", "atk")))})
	if b.has("fx"):
		fx_play(o, b.fx, hand, 20.0, [], (to - hand).angle())


static func _hw5_hooks(o, dt: float) -> void:
	var g = o.g
	var h: Dictionary = o.hw
	for hk in h.hooks:
		var b: Dictionary = hk.b
		hk.t = float(hk.t) + dt
		var k: float = clampf(float(hk.t) / float(hk.dur), 0.0, 1.0)
		match str(hk.phase):
			"fly":
				hk.head = (hk.from as Vector2).lerp(hk.to, k) + Vector2(0, -sin(k * PI) * float(b.get("apex", 24.0)))
				if k >= 1.0:
					_hw5_hook_impact(o, hk)
			"taut":
				if k >= 1.0:
					_hw5_hook_drag_start(o, hk)
			"drag":
				var kr: float = 1.0 - (1.0 - k) * (1.0 - k)
				hk.head = (hk.to as Vector2).lerp(hk.front, kr)
				for dg in hk.drag:
					var e: Dictionary = dg.e
					if e.dead:
						continue
					e.pos = (dg.from as Vector2).lerp(dg.spot, kr)
					e.kb = Vector2.ZERO
					e.stun = maxf(e.stun, 0.15)
					dg.dust = float(dg.get("dust", 0.0)) - dt
					if float(dg.dust) <= 0.0 and b.has("dust_fx"):
						dg.dust = 0.07
						fx_play(o, b.dust_fx, e.pos, float(e.r), [e])
				if k >= 1.0:
					_hw5_hook_arrive(o, hk)
					hk.phase = "done"
	h.hooks = h.hooks.filter(func(hk): return str(hk.phase) != "done")


static func _hw5_hook_impact(o, hk: Dictionary) -> void:
	var g = o.g
	var b: Dictionary = hk.b
	var c: Vector2 = hk.to
	var r: float = float(b.get("r", 90.0)) * o.stat(&"op_range")
	var hits: Array = o.area_hit(str(b.get("src", "")), c, r, float(hk.dmg) * float(b.get("mult", 1.2)), float(b.get("kb", 0.0)), 0.0, b.get("tags", []))
	if b.has("impact_fx"):
		fx_play(o, b.impact_fx, c, r, hits)
	hk.phase = "taut"
	hk.t = 0.0
	hk.dur = float(b.get("taut", 0.2))
	hk.head = c


static func _hw5_hook_drag_start(o, hk: Dictionary) -> void:
	var g = o.g
	var b: Dictionary = hk.b
	if o.pos == Vector2.INF:
		hk.phase = "done"
		return
	var a: Vector2 = o.pos
	var c: Vector2 = hk.to
	var L: float = a.distance_to(c)
	var d: Vector2 = (c - a) / maxf(1.0, L)
	var w: float = float(b.get("w", 40.0))
	var front: Vector2 = a + d * float(b.get("front", 60.0))
	var got: Array = []
	for j in o.query_ids((a + c) * 0.5, L * 0.5 + w + 30.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or not _movable(e) or not line_contains(a, d, L, w, e.pos, float(e.r)):
			continue
		if e.pos.distance_to(a) <= float(b.get("front", 60.0)):
			continue   # 已经在身前的不拖
		got.append(e)
	got.sort_custom(func(x, y): return x.pos.distance_squared_to(a) < y.pos.distance_squared_to(a) if x.pos.distance_squared_to(a) != y.pos.distance_squared_to(a) else int(x.id) < int(y.id))
	var mx: int = int(b.get("max_n", 12))
	for i in mini(mx, got.size()):
		var e: Dictionary = got[i]
		var side: float = (1.0 if i % 2 == 1 else -1.0) * ceilf(i / 2.0)
		var spot: Vector2 = front + d * (float(e.r) * 0.5) + d.orthogonal() * side * 14.0 + d * absf(side) * 6.0
		hk.drag.append({"e": e, "from": e.pos, "spot": spot})
	hk.phase = "drag"
	hk.t = 0.0
	hk.dur = float(b.get("drag", 0.18))
	hk.front = front


static func _hw5_hook_arrive(o, hk: Dictionary) -> void:
	var b: Dictionary = hk.b
	var dmg: float = float(hk.dmg) * float(b.get("back_mult", 0.4))
	var src: String = str(b.get("back_src", b.get("src", "")))
	var ve: float = o.vs_elite()
	var hits: Array = []
	for dg in hk.drag:
		var e: Dictionary = dg.e
		if e.dead:
			continue
		o.log_hit(src, b.get("tags", []))
		o.deal_damage(e, dmg * (ve if e.elite or e.boss else 1.0))
		hits.append(e)
	if b.has("arrive_fx") and not hits.is_empty():
		fx_play(o, b.arrive_fx, hk.front, 40.0, hits)


static func hw_attack_locked(o) -> bool:
	if not o.hw.has("hooks"):
		return false
	for hk in o.hw.hooks:
		if hk.b.get("lock", false):
			return true
	return false


static func hw_draw_hooks(o) -> void:
	var g = o.g
	var h: Dictionary = o.hw
	if not h.has("hooks") or o.pos == Vector2.INF:
		return
	for hk in h.hooks:
		var b: Dictionary = hk.b
		var hv = b.get("hand", [33, -33])
		var hand: Vector2 = o.pos + Vector2(float(hv[0]) * float(o.face), float(hv[1]))
		var p: Vector2 = (hk.head as Vector2) + Vector2(0, -6)
		var tile: String = str(b.get("chain", ""))
		var taut: bool = str(hk.phase) != "fly"
		if tile != "" and g.tex.get(tile) != null:
			var shake: Vector2 = Vector2(0, sin(float(g.t) * 60.0) * 2.0) if str(hk.phase) == "taut" else Vector2.ZERO
			_hw_draw_tiled(o, tile, hand, p + shake, g.PX, 0.0, 0, Color.WHITE, 1 if taut else 0)
		else:
			_hw_draw_chain(o, hand, p, 1.0)
		for dg in hk.drag:
			if str(hk.phase) == "drag" and not dg.e.dead:
				_hw_draw_chain(o, p, dg.e.pos + Vector2(0, -float(dg.e.r) * 0.5), 0.7)
		var dirv: Vector2 = ((hk.to as Vector2) - (hk.from as Vector2)).normalized()
		_hw_draw_anchor(o, p, -dirv if str(hk.phase) == "drag" else dirv, 1.0)


# ---------------------------------------------------------------- 每帧（hw_tick 末尾转来）

static func _hw5_tick(o, dt: float) -> void:
	var h: Dictionary = o.hw
	if not h.links.is_empty():
		_hw5_links(o, dt)
	if not h.lobvol.is_empty():
		_hw5_lobs(o, dt)
	if not h.hooks.is_empty():
		_hw5_hooks(o, dt)


# ---------------------------------------------------------------- 本段的校验

static func _hw5_block(b: Dictionary, p: String, kind: String, ctx: Dictionary, tag: String) -> bool:
	if not tag in HW5_TAGS:
		return false
	var errs: Array = ctx.errs
	var where_ok := {
		"verb.requiem_stack": ["sustain", "skill"],
		"verb.link": ["instant"],
		"shape.hookshot": ["skill", "instant"],
	}
	if not kind in where_ok[tag]:
		errs.append("%s：「%s」不能放在这里（%s；只能在 %s）" % [p, tag, kind, " / ".join(where_ok[tag])])
		return true
	match tag:
		"verb.requiem_stack":
			_num(b, "per", p, ctx, true, 0.0, 1.0)
			_num(b, "max", p, ctx, true, 1.0, 10.0)
			var lk = b.get("look", [])
			if not (lk is Array) or lk.any(func(x): return not str(x).begins_with("fx_")):
				errs.append(p + ".look 必须是 fx_* 帧条名的数组（按层数分档）")
		"verb.link":
			_num(b, "n", p, ctx, true, 1.0, 6.0)
			_num(b, "r", p, ctx, true, 1.0, 600.0)
			_num(b, "dur", p, ctx, true, 0.1, 10.0)
			_num(b, "share", p, ctx, true, 0.0, 2.0)
			_num(b, "cap", p, ctx, false, 1.0, float(HW_LINK_CAP))
			for k in ["tile", "pulse", "anchor"]:
				if b.has(k) and not str(b[k]).begins_with("fx_"):
					errs.append("%s.%s 必须是 fx_* 帧条名" % [p, k])
			_src(b, p, ctx, true)
		"shape.hookshot":
			_num(b, "range", p, ctx, true, 10.0, 1000.0)
			_num(b, "r", p, ctx, true, 1.0, 400.0)
			_num(b, "mult", p, ctx, true, 0.0, 20.0)
			_num(b, "back_mult", p, ctx, false, 0.0, 20.0)
			_num(b, "w", p, ctx, false, 1.0, 200.0)
			_num(b, "taut", p, ctx, false, 0.0, 2.0)
			_num(b, "drag", p, ctx, false, 0.02, 2.0)
			if b.has("basis") and not str(b.basis) in ["attack", "prev", "hit", "atk"]:
				errs.append(p + ".basis 只能是 attack / prev / hit / atk")
			if b.has("chain") and not str(b.chain).begins_with("fx_"):
				errs.append(p + ".chain 必须是 fx_* 帧条名")
			_src(b, p, ctx, true)
			if b.has("back_src") and not ctx.srcs.has(str(b.back_src)):
				errs.append("%s.back_src「%s」没在 hit_sources 里登记" % [p, str(b.back_src)])
			for k in ["fx", "impact_fx", "arrive_fx", "dust_fx"]:
				if b.has(k) and k != "fx":
					_fx(b[k], p + "." + k, ctx, "shape.circle")
	return true


# ================================================================ 手写迁移段（第 3 批：归溟幽灵鲨 / 水月 / 艾丽妮 / 流明，docs/91 §19 批 3；docs/61 §19）
# 只往后加，建在手写迁移段上（o.hw 状态、hw_tick / hw_exec / hw_draw_* 挂钩），前缀 h3_ / _h3。各人一个子字典：
#   ir（刺击 / 浮空 / 手炮连射 / 二次斩）、sp（锯环 / 替身 / 血痕）、mz（伞击 / 触手 / 水母）、lm（光弹 / 发光单元 / 灯塔）。
# 确定性：玩法随机只在手写版也取 g.rng 的地方取（同样的次数、同样的顺序）；画面一律 g.vrng。
#
# 艾丽妮段（IR_TAGS）：
#  shape.thrust     直线穿刺（普攻）：长 len × op_range（× len_mults）、宽 w（× w_mults），判定原点 = 脚底 + (0, y)，按离原点远近逐个命中、穿透；
#                   stages = 剑豪多段：出手后每隔 gap（按 attack 帧条 second − fire 帧）再刺一段（第 k 段 cond 成立才有，mult 乘在这一轮倍率上）；
#                   次数型技能补丁（dur.next_n 的 attack_patch：mult / power / src / on_first / then_first）只作用于第一段；
#                   ctrl = 吃 verb.ctrl_bonus（对受控敌人增伤）；pursue {cond, cd, mult[], r, src}：刺中浮空 / 被控住的敌人时追加一发手炮
#  shape.cleave     扇形 / 环形斩（按手写的结算顺序：逐个 伤害 → 命中状态）：半径 r（× op_range，或 "attack" = 当前刺击长度）× r_mult，
#                   原点 = 脚底 + origin_off；aim: nearest + aim_r（世界像素）朝最近敌人（face 转身），没有 aim = 朝 ang（弧度）；
#                   order: near = 按离脚底远近、max_n 个；伤害 = atk × mult[] × 加成 [× 技能强度] × post[]
#  verb.barrage     手炮连射：n 发，第 i 发在 t0 + i × gap 秒；每发优先打本段浮空表里离发动点 r（× op_range）内的敌人，没有就打身边 r × near_k 内最近 near_n 个，
#                   g.rng 随机挑一个（同手写），转身开火，执行 cannon {mult[], power, r, src}
#  verb.followup    delay 秒后再执行 do：那一刻正在出手就直接执行，否则先起一个技能动作（不扣技力），出手帧执行
#  verb.ctrl_bonus  常驻（天赋）：写了 ctrl 的形状对浮空 / 眩晕 / 束缚中的敌人伤害 × (1 + value)
#  verb.lift_around 瞬时：以 target 为心、r 内（查询多给 pad）的敌人（不含刚才那个首中目标）浮空 dur 秒、高 h
#  st.launch        命中状态：浮空（同手写艾丽妮：精英时长减半、Boss 不受；已浮空的刷新时长，每帧清击退，sin 弧线抬高 h）

const H3_TAGS := ["shape.thrust", "shape.cleave", "verb.barrage", "verb.followup", "verb.ctrl_bonus", "verb.lift_around", "st.launch",
	"shape.saw", "verb.undying", "verb.substitute",
	"shape.lantern", "verb.mend", "verb.purge", "verb.light_rain", "verb.beam_window", "verb.tower", "verb.beam", "verb.heal_lamp",
	"shape.umbrella", "verb.kill_heal", "verb.cast_push", "verb.mirror"]
const H3_ATTACKS := ["thrust", "saw", "lantern", "umbrella"]   # 第 3 批的普攻形状（起手 / 出手由本段接管）
const H3_PINK := Color(0.95, 0.6, 0.8)
const H3_SILVER := Color(0.9, 0.92, 1.0)
const H3_LAMP := Color(1.0, 0.85, 0.5)


static func h3_on(o) -> bool:
	return hw_on(o) and (o.hw.has("ir") or o.hw.has("sp") or o.hw.has("mz") or o.hw.has("lm"))


## hw_init 转来：本段的状态一开始就建好
static func h3_init(o, tags: Dictionary) -> void:
	for t in tags:
		if t in SP_TAGS:
			_h3sp(o)
		elif t in LM_TAGS:
			_h3lm(o)
		elif t in MZ_TAGS:
			_h3mz(o)
		elif t in H3_TAGS:
			_h3ir(o)


static func _h3ir(o) -> Dictionary:
	var h := hw_st(o)
	if not h.has("ir"):
		h["ir"] = {"air": [], "strikes": [], "jc": Vector2.INF, "st_t": -1.0, "st_ang": 0.0, "st_mult": 1.0, "st_i": 0, "tn": 0, "pcd": 0.0,
			"fu_t": -1.0, "fu": {}, "swing": {}, "spin_t": 0.0, "first": {}, "judge": 0.0}
	return h.ir


static func _h3_sfx(o, kind: String, db := 0.0, pitch := 1.0, vary := 0.0) -> void:
	var g = o.g
	var sfx: Node = g.get_node_or_null("/root/Sfx") if g != null and g.is_inside_tree() else null
	if sfx != null:
		sfx.op(o.id, kind, db, pitch, vary)


## 条件成立的倍率依次乘（[{cond, mult}]）
static func _h3_mults(o, v: float, arr) -> float:
	if arr is Array:
		for m in arr:
			if m is Dictionary and cond_true(o, m.get("cond", {})):
				v *= float(m.get("mult", 1.0))
	return v


# ---------------------------------------------------------------- shape.thrust

static func h3_thrust_len(o, a: Dictionary) -> float:
	return _h3_mults(o, float(a.get("len", 180.0)) * o.stat(&"op_range"), a.get("len_mults", []))


static func h3_thrust_w(o, a: Dictionary) -> float:
	return _h3_mults(o, float(a.get("w", 26.0)), a.get("w_mults", []))


## 普攻起手（data_operator.update，手动普攻 A 类）
static func h3_attack_aim(o, a: Dictionary) -> Vector2:
	match str(a.get("shape", "")):
		"thrust":
			var L: float = h3_thrust_len(o, a)
			return o.atk_point(o.nearest_enemies(1, L + float(a.get("aim_pad", 20.0)), o.pos), L)
		"saw":
			var r: float = h3_saw_r(o, a)
			return o.atk_point(o.nearest_enemies(1, r + float(a.get("aim_pad", 30.0)), o.pos), r)
	return Vector2.INF


## 普攻起手（data_operator.update：技能判定之后）：荧光先累计计时；其余同数据干员的起手（冷却、闸门、replace 帧条），间隔按 h3_attack_cd
static func h3_attack_start(o, a: Dictionary, dt: float) -> void:
	if str(a.get("shape", "")) == "lantern":
		_h3_lantern_start(o, a, dt)
		return
	if o.no_attack or o.cd > 0.0 or el_attack_locked(o) or hw_attack_locked(o):
		return
	var at: Vector2 = h3_attack_aim(o, a)
	if at == Vector2.INF:
		o.cd = o.idle_cd(float(a.get("idle", 0.2)))
		return
	o.cd = h3_attack_cd(o, a)
	var rp: Dictionary = o._replace_trig(o.atk_n + 1)
	var an: String = str(rp.get("anim", ""))
	if an == "" and a.has("anim"):
		an = str(a.anim)
	o.start_attack(at if a.get("turn", true) else Vector2.INF, 0.5, 0.25, an)
	_e3_windup(o)   # 精英化第 3 批：trig.on_windup（卷刃）


## 普攻出手（data_operator._release）
static func h3_attack_fire(o, a: Dictionary) -> void:
	match str(a.get("shape", "")):
		"thrust":
			_h3_thrust_release(o, a)
		"saw":
			_h3_saw_release(o, a)
		"lantern":
			_h3_lantern_release(o, a)


static func _h3_thrust_release(o, a: Dictionary) -> void:
	var ir := _h3ir(o)
	var L: float = h3_thrust_len(o, a)
	var ts: Array = o.nearest_enemies(1, L + float(a.get("fire_pad", 40.0)), o.pos)
	var ang: float = o.facing_angle()
	if not ts.is_empty():
		ang = (ts[0].pos - o.pos).angle()
		o.face_to(ang)
	ang = o.atk_angle(ang)
	var patch := {}
	var sk: Array = o.B.get("skills", [])
	for i in 3:
		if o.ammo[i] > 0 and i < sk.size():
			o.ammo[i] -= 1
			patch = sk[i].get("attack_patch", {})
			break
	var mult := 1.0
	if not patch.is_empty():
		mult = float(patch.get("mult", 1.0)) * (o.skill_power() if patch.get("power", false) else 1.0)
	ir.st_i = 1
	_e3_fin_arm(o, a)   # 精英化第 3 批：这一轮是不是收尾换斩
	var first: Dictionary = _h3_thrust(o, a, ang, mult, patch, 1)
	var stg: Array = a.get("stages", [])
	if not stg.is_empty() and cond_true(o, stg[0].get("cond", {})):
		ir.st_t = _h3_stage_gap(o, a)
	else:
		ir.st_t = -1.0
	ir.st_ang = ang
	ir.st_mult = mult
	if not patch.is_empty() and not first.is_empty():
		for s in patch.get("on_first", []):
			apply_status(o, first, s, first.pos)
		if patch.has("first_fx"):
			fx_play(o, patch.first_fx, first.pos, float(first.r), [first])
		ir.first = first
		o._exec_list(patch.get("then_first", []), first.pos)
		ir.first = {}


## 段间隔：按 attack 帧条的 second 帧与出手帧之差（同手写 _stage_gap；second 缺省 3）
static func _h3_stage_gap(o, a: Dictionary) -> float:
	var spec: Dictionary = o.sprite_spec(str(a.get("gap_anim", "attack")))
	var fps: float = float(spec.get("fps", 12))
	return maxf(0.05, (float(spec.get("second", a.get("second", 3))) - float(spec.get("fire", 1))) / fps)


## 第 k 段之后的段（hw_tick：浮空 → 连射 → 追诉冷却之后）
static func _h3_stage_tick(o, ir: Dictionary, dt: float) -> void:
	if float(ir.st_t) < 0.0:
		return
	ir.st_t = float(ir.st_t) - dt
	if float(ir.st_t) >= 0.0:
		return
	ir.st_t = -1.0
	var a: Dictionary = o.B.get("attack", {})
	var stg: Array = a.get("stages", [])
	ir.st_i = int(ir.st_i) + 1
	var k: int = int(ir.st_i) - 2
	if k < 0 or k >= stg.size():
		return
	var sg: Dictionary = stg[k]
	var more: bool = k + 1 < stg.size() and cond_true(o, stg[k + 1].get("cond", {}))
	if not more and ir.get("fin", false):   # 精英化第 3 批：这一轮的收尾换成 finisher（裂潮余波）
		ir.fin = false
		_e3_finisher(o, a)
		return
	var m: float = float(ir.st_mult) * float(sg.mult) if sg.has("mult") else float(ir.st_mult)
	var first: Dictionary = _h3_thrust(o, a, float(ir.st_ang), m, {}, int(ir.st_i))
	if not first.is_empty():
		for s in sg.get("on_first", []):   # 精英化第 3 批：这一段首中目标的状态（挑刺）
			apply_status(o, first, s, first.pos, -1.0, 0.0, 0)
	if more:
		ir.st_t = _h3_stage_gap(o, a)


## 一段直刺：返回命中的第一个敌人（最近的）
static func _h3_thrust(o, a: Dictionary, ang: float, mult: float, patch: Dictionary, stage: int) -> Dictionary:
	var g = o.g
	var ir: Dictionary = o.hw.ir
	var d := Vector2.from_angle(ang)
	var org: Vector2 = o.pos + Vector2(0, float(a.get("y", -12.0)))
	var L: float = h3_thrust_len(o, a)
	var W: float = h3_thrust_w(o, a)
	var hits: Array = []
	for j in o.query_ids(org + d * L * 0.5, L * 0.6 + 40.0):
		var e: Dictionary = g.enemies[j]
		if e.dead:
			continue
		var rel: Vector2 = e.pos - org
		var along: float = rel.dot(d)
		if along < -e.r or along > L + e.r:
			continue
		if absf(rel.cross(d)) > W * 0.5 + e.r:
			continue
		hits.append([along, e])
	hits.sort_custom(func(x, y): return x[0] < y[0])
	var dmg: float = o.base(str(a.get("atk_key", "atk")), 0.0) * o._dmg_bonus() * mult
	var gust: bool = not patch.is_empty()
	var src: String = str(patch.get("src", a.get("src", ""))) if gust else str(a.get("src", ""))
	var pu: Dictionary = _h3_pursue(o, a)
	var lk: Dictionary = a.get("look", {})
	var first := {}
	for hh in hits:
		var e: Dictionary = hh[1]
		var pursue: bool = not pu.is_empty() and float(ir.pcd) <= 0.0 and not e.dead and (float(e.get("air", 0.0)) > 0.0 or _h3_is_air(o, e))
		o.log_hit(src, a.get("tags", []))
		o.deal_damage(e, dmg * h3_ctrl_mult(o, e, a))
		if pursue:
			ir.pcd = float(pu.get("cd", 0.4))
			_h3_cannon(o, pu, e.pos, hw_mul(o.base(str(pu.get("atk_key", "atk")), 0.0), pu.get("mult", 1.0)) * o._dmg_bonus())
		o.fx({"kind": "spark", "pos": e.pos + Vector2(0, -e.r * 0.5), "vel": d * 120.0 + Vector2(g.vrng.randf_range(-40, 40), -60), "life": 0.25, "col": _mf_col(lk.get("spark", []), H3_SILVER), "sz": 2.0, "drag": 3.0})
		if first.is_empty():
			first = e
			o.spawn_fx_sprite(str(lk.get("hit", "fx_thrust_hit_rose")), e.pos + Vector2(0, -e.r * 0.5), g.PX * 0.9, ang)
	_h3_thrust_fx(o, a, d, L, ang, gust, stage)
	if stage > 1:   # 第一段的出手音由 data_operator._release 播
		_h3_sfx(o, "atk", 0.0, 1.0, 0.08)
	if not first.is_empty():
		_h3_sfx(o, "hit")
	return first


## 刺击光束（同手写：帧条 fx_irene_thrust，缺图退回程序光束 + 剑尖星芒；更长的部分程序叠出；第三段剑尖金光）
static func _h3_thrust_fx(o, a: Dictionary, d: Vector2, L: float, ang: float, gust: bool, stage: int) -> void:
	var g = o.g
	var ir: Dictionary = o.hw.ir
	var lk: Dictionary = a.get("look", {})
	var col: Color = _mf_col(lk.get("col", []), H3_PINK)
	var gcol: Color = _mf_col(lk.get("gust_col", []), Color(1.1, 0.7, 0.95))
	ir.tn = int(ir.tn) + 1
	var side: float = 4.0 if int(ir.tn) % 2 == 0 else -4.0
	var st: Vector2 = o.pos + Vector2(0, -32) + d * 12.0 + d.orthogonal() * side
	var tsc: float = g.PX * clampf(L / 128.0, 0.9, 1.1)
	var star: String = str(lk.get("star", "fx_star_hit_rose"))
	if not o.spawn_fx_sprite(str(lk.get("beam", "fx_irene_thrust")), st + d * 32.0 * tsc, tsc, ang, false, false, Color(1.1, 0.8, 1.0) if gust else Color.WHITE):
		o.fx({"kind": "h3_thrust", "pos": st, "dir": d, "len": L, "w": 9.0 if gust else 7.0, "life": 0.16, "col": gcol if gust else col, "star": star})
		o.spawn_fx_sprite(star, st + d * (L + 10.0), g.PX * 0.8)
	elif h3_thrust_w(o, a) > float(a.get("w", 26.0)) * 1.01:
		var wk: float = h3_thrust_w(o, a) / maxf(1.0, float(a.get("w", 26.0)))
		o.fx({"kind": "h3_thrust", "pos": st, "dir": d, "len": L, "w": 7.0 * wk, "life": 0.16, "col": gcol if gust else col, "star": star})
		o.spawn_fx_sprite(star, st + d * (L + 6.0), g.PX * 0.8)
	if stage == 3:
		o.fx({"kind": "glow", "pos": st + d * L, "r": 10.0, "life": 0.18, "col": H3_LAMP, "alpha": 0.7})


static func _h3_pursue(o, a: Dictionary) -> Dictionary:
	var pu = a.get("pursue", null)
	if pu is Dictionary and cond_true(o, pu.get("cond", {})):
		return pu
	return {}


## 受控增伤：天赋里生效的 verb.ctrl_bonus；对浮空 / 眩晕 / 束缚中的敌人 × (1 + value)
static func h3_ctrl_mult(o, e: Dictionary, b: Dictionary) -> float:
	if not b.get("ctrl", false):
		return 1.0
	var v: float = _h3_ctrl_value(o)
	if v > 0.0 and (float(e.get("air", 0.0)) > 0.0 or e.stun > 0.0 or e.slow > 0.0):
		return 1.0 + v
	return 1.0


static func _h3_ctrl_value(o) -> float:
	for t in o._trigs():
		if str(t.get("_tag", "")) != "trig.passive" or not cond_true(o, t.get("cond", {})):
			continue
		for b in t.get("do", []):
			if str(b.get("_tag", "")) == "verb.ctrl_bonus" and cond_true(o, b.get("cond", {})):
				return float(b.get("value", 0.0))
	return 0.0


## 手炮一发：c 周围 r 内 area_hit（同手写 _cannon），炮口一闪 → 弹道光 → 黑烟小爆炸
static func _h3_cannon(o, cb: Dictionary, c: Vector2, dmg: float) -> void:
	var g = o.g
	o.area_hit(str(cb.get("src", "")), c, float(cb.get("r", 40.0)), dmg, 0.0, 0.0)
	var muzzle: Vector2 = o.pos + Vector2(12.0 * o.face, -30)
	o.spawn_fx_sprite(str(cb.get("muzzle", "fx_muzzle_flash")), muzzle, g.PX * 0.7)
	o.fx({"kind": "line", "pos": muzzle, "to": c + Vector2(0, -10), "life": 0.08, "col": Color(1.0, 0.8, 0.6), "w": 2.0})
	if not o.spawn_fx_sprite(str(cb.get("burst", "fx_cannon_burst")), c + Vector2(0, 6), g.PX * 1.2, 0.0, false, true):
		o.fx({"kind": "glow", "pos": c + Vector2(0, -10), "r": 18.0, "life": 0.2, "col": H3_LAMP, "alpha": 0.6})
	o.fx({"kind": "ring", "pos": c, "r": 34.0, "r0": 6.0, "life": 0.25, "col": H3_LAMP, "floor": true})
	_h3_sfx(o, "big", -4.0, 1.0, 0.1)


# ---------------------------------------------------------------- st.launch / verb.lift_around

static func h3_launch(o, e: Dictionary, dur: float, h: float) -> void:
	if e.dead or e.boss or dur <= 0.0:
		return
	if e.elite:
		dur *= 0.5
	var ir := _h3ir(o)
	for a in ir.air:
		if is_same(a.e, e):
			a.dur = maxf(a.dur, dur)
			a.t = 0.0
			return
	ir.air.append({"e": e, "t": 0.0, "dur": dur, "h": h})
	e.stun = maxf(e.stun, dur)


static func _h3_is_air(o, e: Dictionary) -> bool:
	if not o.hw.has("ir"):
		return false
	for a in o.hw.ir.air:
		if is_same(a.e, e):
			return true
	return false


static func _h3_air_tick(o, ir: Dictionary, dt: float) -> void:
	if ir.air.is_empty():
		return
	for a in ir.air:
		a.t += dt
		var e: Dictionary = a.e
		if e.dead:
			e.air = 0.0
			a.t = a.dur + 1.0
			continue
		var k: float = clampf(a.t / a.dur, 0.0, 1.0)
		e.air = sin(k * PI) * a.h
		e.kb = Vector2.ZERO
		if k >= 1.0:
			e.air = 0.0
	ir.air = ir.air.filter(func(a): return a.t < a.dur)


static func h3_lift_around(o, b: Dictionary, at: Vector2) -> void:
	var g = o.g
	var ir := _h3ir(o)
	if at == Vector2.INF:
		return
	var r: float = float(b.get("r", 70.0))
	var skip: Dictionary = ir.first
	for j in o.query_ids(at, r + float(b.get("pad", 30.0))):
		var e: Dictionary = g.enemies[j]
		if e.dead or is_same(e, skip) or e.pos.distance_to(at) > r + e.r:
			continue
		h3_launch(o, e, float(b.get("dur", 0.8)), float(b.get("h", 20.0)))
	if b.has("fx"):
		fx_play(o, b.fx, at, r)
	else:
		o.fx({"kind": "h3_gale", "pos": at, "r": r, "life": 0.45, "floor": true})


# ---------------------------------------------------------------- shape.cleave

static func h3_cleave(o, b: Dictionary, at: Vector2) -> Array:
	var g = o.g
	var ang: float = float(b.get("ang", 0.0))
	if str(b.get("aim", "")) == "thrust" and o.hw.has("ir"):   # 精英化第 3 批：沿这一轮刺击的方向（不转身）
		ang = float(o.hw.ir.st_ang)
	elif str(b.get("aim", "")) == "nearest":
		var ts: Array = o.nearest_enemies(1, float(b.get("aim_r", 240.0)), o.pos)
		ang = o.facing_angle()
		if not ts.is_empty():
			ang = (ts[0].pos - o.pos).angle()
			if b.get("face", true):
				o.face_to(ang)
	var r: float
	if str(b.get("r", "")) == "attack":
		r = h3_thrust_len(o, o.B.get("attack", {}))
	else:
		r = float(b.get("r", 100.0)) * o.stat(&"op_range")
	r = hw_mul(r, b.get("r_mult", 1.0))
	var org: Vector2 = o.pos + hw_off(b)
	var hits: Array = o.arc_targets(org, ang, float(b.get("half", PI)), r)
	if str(b.get("order", "")) == "near":
		var p0: Vector2 = o.pos
		hits.sort_custom(func(x, y): return x.pos.distance_squared_to(p0) < y.pos.distance_squared_to(p0))
	var dmg: float = hw_mul(o.base(str(b.get("atk_key", "atk")), 0.0), b.get("mult", 1.0)) * o._dmg_bonus()
	if b.get("power", false):
		dmg *= o.skill_power()
	dmg = hw_mul(dmg, b.get("post", 1.0))
	var n: int = mini(int(b.max_n), hits.size()) if b.has("max_n") else hits.size()
	var src: String = str(b.get("src", ""))
	var out: Array = []
	for i in n:
		var e: Dictionary = hits[i]
		o.log_hit(src, b.get("tags", []))
		o.deal_damage(e, dmg * h3_ctrl_mult(o, e, b))
		for s in b.get("on_hit", []):
			apply_status(o, e, s, org)
		out.append(e)
	hw_record(o, dmg, ang, r, org)
	if o.hw.has("ir"):
		o.hw.ir["last_hits"] = out
	var lk = b.get("look", "")
	if str(lk) == "rose_heavy":
		_h3_cleave_fx(o, b, ang, r)
	elif str(lk) == "crescent":
		_e3_crescent_fx(o, b, ang, r)
	if b.has("fx"):
		fx_play(o, b.fx, o.pos, r, out, ang)
	return out


## 碎潮的刀光（同手写 _shattertide：第二斩镜像偏银白、贴得更近）
static func _h3_cleave_fx(o, b: Dictionary, ang: float, r: float) -> void:
	var second: bool = b.get("second", false)
	var tint: Color = Color(1.1, 1.15, 1.35) if second else Color.WHITE
	if not o.spawn_fx_sprite(str(b.get("strip", "fx_slash_heavy_rose")), o.pos + Vector2(0, -14) + Vector2.from_angle(ang) * r * (0.2 if second else 0.32), r * 1.0 / 28.0, ang, second, false, tint):
		o.slash_fx(o.pos + Vector2(0, -14), ang, 0.8, r, H3_SILVER if second else H3_PINK, "slash", 0.25)
	_h3_vsparks(o, o.pos + Vector2.from_angle(ang) * r * 0.5, H3_SILVER, 10, 200.0, 0.4, 2.5, 200.0)
	if second:
		_h3_sfx(o, "atk", 2.0, 0.9)


## 同 character.gd fx_sparks，散布用 g.vrng（纯画面）
static func _h3_vsparks(o, p: Vector2, c: Color, n: int, spd: float, life := 0.4, sz := 3.0, grav := 0.0, floor_layer := false) -> void:
	var g = o.g
	n = int(round(n * (1.0 + 0.2 * o.node_lv)))
	for k in n:
		o.fx({"kind": "spark", "pos": p, "vel": Vector2.from_angle(g.vrng.randf() * TAU) * g.vrng.randf_range(spd * 0.4, spd), "life": life * g.vrng.randf_range(0.7, 1.2),
			"col": c, "sz": sz, "drag": 2.0, "grav": grav, "floor": floor_layer})


# ---------------------------------------------------------------- verb.barrage / verb.followup

static func h3_barrage(o, b: Dictionary) -> void:
	var ir := _h3ir(o)
	ir.jc = o.pos
	ir.strikes.clear()
	for i in int(b.get("n", 12)):
		ir.strikes.append({"t": float(b.get("t0", 0.35)) + i * float(b.get("gap", 0.25)), "b": b})


static func _h3_strikes_tick(o, ir: Dictionary, dt: float) -> void:
	ir.spin_t = maxf(0.0, float(ir.spin_t) - dt)
	if ir.strikes.is_empty():
		return
	var g = o.g
	for s in ir.strikes:
		s.t -= dt
		if s.t <= 0.0:
			var b: Dictionary = s.b
			var r3: float = float(b.get("r", 160.0)) * o.stat(&"op_range")
			var pool: Array = []
			for a in ir.air:
				if not a.e.dead and a.e.pos.distance_to(ir.jc) < r3:
					pool.append(a.e)
			if pool.is_empty():
				pool = o.nearest_enemies(int(b.get("near_n", 6)), r3 * float(b.get("near_k", 1.6)), o.pos)
			if pool.is_empty():
				continue
			var e: Dictionary = pool[g.rng.randi() % pool.size()]
			var c: Vector2 = e.pos
			var prev_face: float = o.face
			o.face_to((c - o.pos).angle())
			if o.face != prev_face:
				ir.spin_t = 0.12
			var cb: Dictionary = b.get("cannon", {})
			var dmg: float = hw_mul(o.base(str(cb.get("atk_key", "atk")), 0.0), cb.get("mult", 1.0)) * o._dmg_bonus()
			if cb.get("power", false):
				dmg *= o.skill_power()
			_h3_cannon(o, cb, c, dmg)
	ir.strikes = ir.strikes.filter(func(s): return s.t > 0.0)


static func h3_followup(o, b: Dictionary) -> void:
	var ir := _h3ir(o)
	ir.fu_t = float(b.get("delay", 0.35))
	ir.fu = b


static func _h3_followup_tick(o, ir: Dictionary, dt: float) -> void:
	if float(ir.fu_t) < 0.0:
		return
	ir.fu_t = float(ir.fu_t) - dt
	if float(ir.fu_t) >= 0.0:
		return
	ir.fu_t = -1.0
	var b: Dictionary = ir.fu
	if o.acting():
		o._exec_list(b.get("do", []))
	else:
		ir.swing = b
		o._start_action("skill", Vector2.INF, 0.5, 0.2)


## data_operator._release_skill 开头：后续斩那一下的出手帧（不走技能本体）。返回 true = 已处理
static func h3_release_skill(o) -> bool:
	if not o.hw.has("ir") or o.hw.ir.swing.is_empty():
		return false
	var b: Dictionary = o.hw.ir.swing
	o.hw.ir.swing = {}
	o._exec_list(b.get("do", []))
	return true


# ---------------------------------------------------------------- 每帧（hw_tick 开头转来，手写 update 的先后：浮空 → 连射 → 追诉冷却 → 后续段 → 后续斩）

static func h3_tick(o, dt: float) -> bool:
	var h: Dictionary = o.hw
	if h.has("sp"):
		return _h3sp_tick(o, h.sp, dt)
	if h.has("lm"):
		_h3lm_tick(o, h.lm, dt)
	if h.has("ir"):
		var ir: Dictionary = h.ir
		_h3_air_tick(o, ir, dt)
		_h3_strikes_tick(o, ir, dt)
		ir.pcd = maxf(0.0, float(ir.pcd) - dt)
		_h3_stage_tick(o, ir, dt)
		_h3_followup_tick(o, ir, dt)
		_e3_ir_tick(o, ir, dt)
	return false


## hw_exec 转来
static func h3_exec(o, b: Dictionary, at: Vector2) -> void:
	match str(b.get("_tag", "")):
		"shape.thrust":
			pass
		"shape.cleave":
			h3_cleave(o, b, at)
		"verb.barrage":
			h3_barrage(o, b)
		"verb.followup":
			h3_followup(o, b)
		"verb.lift_around":
			h3_lift_around(o, b, at)
		"verb.mend":
			h3_mend(o, b)
		"verb.purge":
			h3_purge(o, b)
		"verb.light_rain":
			h3_light_rain(o, b)
		"verb.beam_window":
			_h3lm(o).beam_t = float(b.get("dur", 3.0))
		"verb.tower":
			h3_tower_start(o, b)
		"verb.cast_push":
			h3_cast_push(o, b)
		"verb.mirror":
			_h3mz(o).mirror_pos = o.pos
		"verb.kill_heal":
			h3_kill_heal(o, b)
		"verb.heal_lamp":
			_h3_heal_lamp(o)
		"verb.doll_flash":
			h3_doll_flash(o, b)


# ---------------------------------------------------------------- 画面

## 技能上层（hw_draw_over 转来）
static func h3_draw_over(o) -> void:
	if o.hw.has("ir"):
		_h3ir_draw_over(o)
	if o.hw.has("sp"):
		_h3sp_draw_over(o)
	if o.hw.has("lm"):
		_h3lm_draw_over(o)
	if o.hw.has("mz"):
		_h3mz_draw_over(o)


## 地面层（hw_draw_floor 转来）
static func h3_draw_floor(o) -> void:
	if o.hw.has("sp"):
		_h3sp_draw_floor(o)
	if o.hw.has("mz"):
		_h3mz_draw_floor(o)


## 区域层（hw_draw_auras 转来）
static func h3_draw_auras(o) -> void:
	if o.hw.has("sp"):
		_h3sp_draw_auras(o)
	if o.hw.has("lm"):
		_h3lm_draw_auras(o)
	if o.hw.has("mz"):
		_h3mz_draw_auras(o)


## 加色层（data_operator.draw_fx_add 转来）
static func h3_draw_add_all(o, ci, loop: int) -> void:
	if not hw_on(o):
		return
	if o.hw.has("lm"):
		h3_draw_add(o, ci)
	if o.hw.has("mz"):
		_h3mz_draw_add(o, ci, loop)


## 附属实体（替身 / 灯塔）参与 2.5D 排序
static func h3_extra_bodies(o) -> Array:
	if not hw_on(o):
		return []
	if o.hw.has("sp"):
		return h3_bodies(o)
	if o.hw.has("lm"):
		return _h3lm_bodies(o)
	return []


static func h3_draw_body_extra(o, it: Dictionary) -> void:
	if str(it.get("h3", "")) == "tower":
		_h3lm_draw_tower(o)
	else:
		h3_draw_extra(o, it)


static func h3_shadows(o) -> void:
	if not hw_on(o):
		return
	if o.hw.has("sp"):
		h3_draw_shadows(o)
	if o.hw.has("lm"):
		_h3lm_shadow(o)


static func h3_rows(o) -> Array:
	if hw_on(o) and o.hw.has("mz"):
		return _h3mz_rows(o)
	return []


static func _h3ir_draw_over(o) -> void:
	var g = o.g
	var cv = o.cv
	var ir: Dictionary = o.hw.ir
	if o.pos == Vector2.INF:
		return
	var lk: Dictionary = o.B.get("attack", {}).get("look", {})
	var lamp_on: bool = o.skill_active_left(2) > 0.0 or (o.acting() and o.act_kind == "skill")
	if lamp_on and lk.get("lantern", true):
		var raised: bool = o.acting() and o.act_kind == "skill"
		var p: Vector2 = o.pos + (Vector2(20.0 * o.face, -56.0) if raised else Vector2(16.0 * o.face, -15.0))
		cv.draw_circle(p, 5.0 + sin(g.t * 20.0), Color(1.6, 1.3, 0.7, 0.8))
		cv.draw_circle(p, 12.0, Color(1.0, 0.85, 0.5, 0.2))
	if float(ir.spin_t) > 0.0:
		var k: float = float(ir.spin_t) / 0.12
		var c: Vector2 = o.pos + Vector2(0, -24)
		var a0: float = PI * 0.5 if o.face > 0.0 else -PI * 0.5
		cv.draw_arc(c, 22.0, a0, a0 + PI, 16, Color(H3_PINK.r * 1.5, H3_PINK.g * 1.4, H3_PINK.b * 1.4, 0.7 * k), 4.0)
		o.draw_body_at(o.pos, o.face > 0.0, Color(H3_PINK.r * 1.3, H3_PINK.g * 1.2, H3_PINK.b * 1.3, 0.45 * k))
	for a in ir.air:
		if not a.e.dead:
			cv.draw_set_transform(a.e.pos + Vector2(0, a.e.r * 0.8), 0.0, Vector2(1.0, 0.5))
			cv.draw_arc(Vector2.ZERO, a.e.r * 0.9, 0.0, TAU, 20, Color(H3_PINK.r, H3_PINK.g, H3_PINK.b, 0.5), 1.5)
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 程序粒子（hw_draw_pfx 转来）：h3_thrust（刺击光束）/ h3_gale（卷风旋风弧）
static func h3_draw_pfx(o, f: Dictionary, a: float) -> bool:
	match str(f.kind):
		"h3_saw":
			_h3_draw_saw(o, f, a)
			return true
		"h3_beam":
			_e3_draw_beam(o, f, a)
			return true
		"h3_thrust":
			_h3_draw_thrust(o, f, a)
			return true
		"h3_gale":
			var cv = o.cv
			var u0: float = 1.0 - a
			cv.draw_set_transform(f.pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.5))
			if Dc.hit_rings():
				cv.draw_arc(Vector2.ZERO, f.r, 0.0, TAU, 32, Color(H3_PINK.r, H3_PINK.g, H3_PINK.b, 0.35 * a), 1.5)
			for q in 3:
				var rr: float = f.r * (1.0 - 0.6 * u0) * (1.0 - q * 0.22)
				var a0: float = u0 * 9.0 + q * TAU / 3.0
				cv.draw_arc(Vector2.ZERO, rr, a0, a0 + 2.0, 12, Color(H3_PINK.r * 1.5, H3_PINK.g * 1.4, H3_PINK.b * 1.5, 0.8 * a), 3.0 - q * 0.6)
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			return true
	return false


static func _h3_quad(cv, q: PackedVector2Array, c: Color) -> void:
	if q[1].distance_to(q[3]) < 2.0:
		cv.draw_line(q[0], q[2], c, 2.0)
	else:
		cv.draw_colored_polygon(q, c)


## 刺击光束：前 30% 伸到最长（缓出），之后宽度收细、淡出；顶点对齐 2 像素网格
static func _h3_draw_thrust(o, f: Dictionary, a: float) -> void:
	var cv = o.cv
	var u: float = 1.0 - a
	var ext: float = 1.0 - pow(1.0 - minf(1.0, u / 0.3), 3.0)
	var d: Vector2 = f.dir
	var n: Vector2 = d.orthogonal()
	var L: float = f.len * ext
	var org: Vector2 = f.pos + d * 14.0 * u
	var tip: Vector2 = org + d * L
	var wide: float = f.w * (1.0 - 0.7 * maxf(0.0, (u - 0.3) / 0.7))
	var c: Color = f.col
	var P := func(v: Vector2) -> Vector2: return (v / 2.0).round() * 2.0
	if L < 12.0:
		return
	_h3_quad(cv, PackedVector2Array([P.call(org + d * 6.0), P.call(org + d * L * 0.7 + n * wide * 0.5), P.call(tip), P.call(org + d * L * 0.7 - n * wide * 0.5)]), Color(c.r, c.g, c.b, 0.55 * a))
	_h3_quad(cv, PackedVector2Array([P.call(org + d * L * 0.25), P.call(org + d * L * 0.72 + n * wide * 0.18), P.call(tip + d * 2.0), P.call(org + d * L * 0.72 - n * wide * 0.18)]), Color(2.2, 2.1, 2.2, 0.95 * a))
	for s in [-1.0, 1.0]:
		var off: Vector2 = n * s * (wide * 0.5 + 5.0)
		cv.draw_line(P.call(org + d * L * 0.35 + off), P.call(org + d * L * 0.85 + off), Color(c.r * 1.4, c.g * 1.4, c.b * 1.4, 0.45 * a), 1.0)
	if u > 0.2 and u < 0.75 and o.g.tex.get(str(f.get("star", "fx_star_hit_rose"))) == null:
		var k: float = 1.0 - absf(u - 0.35) / 0.4
		var sz: float = 7.0 * k
		cv.draw_line(P.call(tip - d * sz), P.call(tip + d * sz), Color(2.4, 2.2, 2.4, k), 2.0)
		cv.draw_line(P.call(tip - n * sz * 0.6), P.call(tip + n * sz * 0.6), Color(2.4, 2.2, 2.4, k), 2.0)


## 状态条（hw_status_items 转来）：次数型技能（没写 %d 的 status 也显示）、技能剩余（审判）
static func h3_status_items(o) -> Array:
	var out: Array = []
	if o.hw.has("sp"):
		out += _h3sp_status(o)
	if o.hw.has("lm"):
		out += _h3lm_status(o)
	if o.hw.has("mz"):
		return _h3mz_status(o)
	var sk: Array = o.B.get("skills", [])
	for i in mini(3, sk.size()):
		var st: String = str(sk[i].get("status", ""))
		if st == "" or "%d" in st:
			continue
		if o.ammo[i] > 0 or (sk[i].get("status_active", false) and o.s_t[i] > 0.0):
			out.append([st, _mf_col(sk[i].get("status_col", []), o.col())])
	return out


# ---------------------------------------------------------------- 本段的校验

static func _h3_block(b: Dictionary, p: String, kind: String, ctx: Dictionary, tag: String) -> bool:
	if not tag in H3_TAGS:
		return false
	var errs: Array = ctx.errs
	var where_ok := {
		"shape.thrust": ["attack"],
		"shape.cleave": ["skill", "instant"],
		"verb.barrage": ["skill", "instant"],
		"verb.followup": ["skill", "instant"],
		"verb.ctrl_bonus": ["sustain"],
		"verb.lift_around": ["skill", "instant"],
		"st.launch": ["on_hit"],
		"shape.saw": ["attack"],
		"verb.undying": ["skill"],
		"verb.substitute": ["skill"],
		"shape.lantern": ["attack"],
		"verb.mend": ["skill", "instant"],
		"verb.purge": ["skill", "instant"],
		"verb.light_rain": ["skill", "instant"],
		"verb.beam_window": ["skill", "instant"],
		"verb.tower": ["skill"],
		"verb.beam": ["sustain"],
		"verb.heal_lamp": ["sustain", "skill", "instant"],
		"shape.umbrella": ["attack"],
		"verb.kill_heal": ["instant"],
		"verb.cast_push": ["skill", "instant"],
		"verb.mirror": ["skill", "instant"],
	}
	if not kind in where_ok[tag]:
		errs.append("%s：「%s」不能放在这里（%s；只能在 %s）" % [p, tag, kind, " / ".join(where_ok[tag])])
		return true
	match tag:
		"shape.thrust":
			_num(b, "len", p, ctx, true, 10.0, 800.0)
			_num(b, "w", p, ctx, true, 1.0, 200.0)
			_num(b, "y", p, ctx, false, -100.0, 100.0)
			_num(b, "aim_pad", p, ctx, false, 0.0, 400.0)
			_num(b, "fire_pad", p, ctx, false, 0.0, 400.0)
			for k in ["len_mults", "w_mults"]:
				_h3_cond_mults(b, k, p, ctx)
			var stg = b.get("stages", [])
			if not (stg is Array) or stg.size() > 4:
				errs.append(p + ".stages 必须是 0–4 段的数组")
			else:
				for i in stg.size():
					var q := "%s.stages[%d]" % [p, i]
					if not (stg[i] is Dictionary):
						errs.append(q + " 必须是对象 {cond, mult}")
						continue
					for k in stg[i]:
						if not k in ["cond", "mult", "on_first", "_doc"]:
							errs.append("%s.%s：一段只有 cond / mult / on_first" % [q, k])
					_list(stg[i].get("on_first", []), q + ".on_first", "on_hit", ctx)
					if stg[i].has("cond") and (not (stg[i].cond is String) or parse_cond(stg[i].cond, ctx.base).has("err")):
						errs.append(q + ".cond 看不懂")
					_num(stg[i], "mult", q, ctx, false, 0.0, 10.0)
			if b.has("pursue"):
				var pu = b.pursue
				if not (pu is Dictionary):
					errs.append(p + ".pursue 必须是对象 {cond, cd, mult, r, src}")
				else:
					_num(pu, "cd", p + ".pursue", ctx, true, 0.0, 10.0)
					_num(pu, "r", p + ".pursue", ctx, false, 1.0, 200.0)
					_src(pu, p + ".pursue", ctx, true)
			if b.has("finisher"):   # 精英化第 3 批：收尾换斩
				var fn = b.finisher
				if not (fn is Dictionary):
					errs.append(p + ".finisher 必须是对象 {cond, every, anim, do, volley}")
				else:
					_num(fn, "every", p + ".finisher", ctx, true, 1.0, 20.0)
					if fn.has("anim") and not (ctx.sprites is Dictionary and ctx.sprites.has(str(fn.anim))):
						errs.append("%s.finisher.anim「%s」不是 sprites 里的帧条键" % [p, str(fn.anim)])
					_list(fn.get("do", []), p + ".finisher.do", "instant", ctx)
					if fn.get("volley", null) is Dictionary:
						_num(fn.volley, "n", p + ".finisher.volley", ctx, true, 1.0, 12.0)
						_src(fn.volley, p + ".finisher.volley", ctx, true)
			_src(b, p, ctx, true)
		"shape.cleave":
			if str(b.get("r", "")) != "attack":
				_num(b, "r", p, ctx, true, 1.0, 1000.0)
			_num(b, "half", p, ctx, false, 0.05, 3.2)   # ≥ PI = 整圈（不看角度）
			_num(b, "aim_r", p, ctx, false, 1.0, 2000.0)
			_num(b, "max_n", p, ctx, false, 1.0, 99.0)
			if b.has("aim") and not str(b.aim) in ["nearest", "thrust"]:
				errs.append(p + ".aim 只能是 nearest / thrust")
			if b.has("order") and str(b.order) != "near":
				errs.append(p + ".order 只能是 near")
			if b.has("origin_off") and not (b.origin_off is Array and b.origin_off.size() == 2):
				errs.append(p + ".origin_off 必须是 [x, y]")
			_list(b.get("on_hit", []), p + ".on_hit", "on_hit", ctx)
			_src(b, p, ctx, true)
		"verb.barrage":
			_num(b, "n", p, ctx, true, 1.0, 40.0)
			_num(b, "gap", p, ctx, true, 0.02, 5.0)
			_num(b, "r", p, ctx, true, 1.0, 1000.0)
			var cb = b.get("cannon", null)
			if not (cb is Dictionary):
				errs.append(p + ".cannon 必须是对象 {mult, power, r, src}")
			else:
				_src(cb, p + ".cannon", ctx, true)
		"verb.followup":
			_num(b, "delay", p, ctx, true, 0.0, 5.0)
			_list(b.get("do", []), p + ".do", "instant", ctx)
		"verb.ctrl_bonus":
			_num(b, "value", p, ctx, true, 0.0, 5.0)
		"verb.lift_around":
			_num(b, "r", p, ctx, true, 1.0, 400.0)
			_num(b, "dur", p, ctx, true, 0.0, 10.0)
		"st.launch":
			_num(b, "dur", p, ctx, true, 0.0, 10.0)
			_num(b, "h", p, ctx, false, 0.0, 100.0)
		"shape.saw":
			_num(b, "r", p, ctx, true, 1.0, 800.0)
			_num(b, "kb", p, ctx, false, 0.0, 1000.0)
			_h3_cond_mults(b, "r_mults", p, ctx)
			for k in ["spin2", "trail", "whirl", "low_hp"]:
				if b.has(k) and not (b[k] is Dictionary):
					errs.append("%s.%s 必须是对象" % [p, k])
			if b.get("trail", null) is Dictionary:
				_src(b.trail, p + ".trail", ctx, true)
			_src(b, p, ctx, true)
		"verb.substitute":
			_num(b, "life", p, ctx, true, 0.1, 60.0)
			if b.has("anim") and not (ctx.sprites is Dictionary and ctx.sprites.has(str(b.anim))):
				errs.append("%s.anim「%s」不是 sprites 里的帧条键" % [p, str(b.anim)])
			if b.get("doll_aura", null) is Dictionary:
				_src(b.doll_aura, p + ".doll_aura", ctx, true)
		"shape.lantern":
			_num(b, "range", p, ctx, true, 10.0, 2000.0)
			if not (b.get("heal", null) is Dictionary) or not (b.get("bolt", null) is Dictionary):
				errs.append(p + "：shape.lantern 要写 heal {every, pct} 与 bolt {atk_key, speed, src}")
			else:
				_num(b.heal, "every", p + ".heal", ctx, true, 0.1, 60.0)
				_num(b.heal, "pct", p + ".heal", ctx, true, 0.0, 0.2)
				_src(b.bolt, p + ".bolt", ctx, true)
			if b.get("units", null) is Dictionary:
				_src(b.units, p + ".units", ctx, true)
			if b.get("bolt", null) is Dictionary and b.bolt.get("refract", null) is Dictionary:   # 精英化第 3 批：折光
				_num(b.bolt.refract, "r", p + ".bolt.refract", ctx, true, 1.0, 600.0)
				_src(b.bolt.refract, p + ".bolt.refract", ctx, true)
			if b.has("beam"):   # 精英化第 3 批：灯塔光柱
				if not (b.beam is Dictionary):
					errs.append(p + ".beam 必须是对象")
				else:
					_num(b.beam, "need", p + ".beam", ctx, true, 1.0, 50.0)
					_num(b.beam, "len", p + ".beam", ctx, true, 10.0, 800.0)
					_src(b.beam, p + ".beam", ctx, true)
		"verb.mend":
			_num(b, "pct", p, ctx, true, 0.0, 0.5)
		"verb.purge":
			_num(b, "immune", p, ctx, false, 0.0, 30.0)
		"verb.light_rain":
			_num(b, "dur", p, ctx, true, 0.1, 30.0)
			_num(b, "r", p, ctx, true, 1.0, 800.0)
			_src(b, p, ctx, true)
		"verb.beam_window":
			_num(b, "dur", p, ctx, true, 0.1, 30.0)
		"verb.tower":
			_num(b, "r", p, ctx, true, 1.0, 1000.0)
			if b.get("burst", null) is Dictionary:
				_src(b.burst, p + ".burst", ctx, true)
		"verb.beam":
			_num(b, "len", p, ctx, true, 1.0, 1000.0)
			_num(b, "tick", p, ctx, true, 0.02, 5.0)
			_src(b, p, ctx, true)
		"verb.heal_lamp":
			_num(b, "add", p, ctx, kind == "sustain", 0.0, 100.0)
		"shape.umbrella":
			_num(b, "r", p, ctx, true, 1.0, 800.0)
			_h3_cond_mults(b, "r_mults", p, ctx)
			_h3_cond_mults(b, "dmg_mults", p, ctx)
			_h3_cond_mults(b, "interval_mults", p, ctx)
			if not (b.get("tentacle", null) is Dictionary):
				errs.append(p + ".tentacle 必须是对象")
			else:
				_src(b.tentacle, p + ".tentacle", ctx, true)
			if b.get("echo", null) is Dictionary:
				_src(b.echo, p + ".echo", ctx, true)
			if b.has("jelly"):   # 精英化第 3 批：深蓝之籽
				if not (b.jelly is Dictionary):
					errs.append(p + ".jelly 必须是对象")
				else:
					_num(b.jelly, "every", p + ".jelly", ctx, true, 0.1, 10.0)
					_num(b.jelly, "r", p + ".jelly", ctx, true, 1.0, 800.0)
					_src(b.jelly, p + ".jelly", ctx, true)
			_src(b, p, ctx, true)
		"verb.kill_heal":
			_num(b, "pct", p, ctx, true, 0.0, 0.2)
		"verb.cast_push":
			_num(b, "r", p, ctx, true, 1.0, 800.0)
	return true


static func _h3_cond_mults(b: Dictionary, k: String, p: String, ctx: Dictionary) -> void:
	if not b.has(k):
		return
	var arr = b[k]
	if not (arr is Array):
		ctx.errs.append("%s.%s 必须是 [{cond, mult}] 数组" % [p, k])
		return
	for i in arr.size():
		var q := "%s.%s[%d]" % [p, k, i]
		if not (arr[i] is Dictionary):
			ctx.errs.append(q + " 必须是对象 {cond, mult}")
			continue
		if arr[i].has("cond") and (not (arr[i].cond is String) or parse_cond(arr[i].cond, ctx.base).has("err")):
			ctx.errs.append(q + ".cond 看不懂")
		_num(arr[i], "mult", q, ctx, true, 0.0, 20.0)


# ---------------------------------------------------------------- 归溟幽灵鲨段（第 3 批续，SP_TAGS）
#  shape.saw        贴身 360° 环斩（普攻）：半径 r × op_range × r_mults（cond 成立的依次乘），判定原点 = 脚底 + (0, y)；
#                   伤害 = atk × 加成 × Π mults（cond 成立的：value，hp_lost = 再加主控已损失生命比例）[× 技能强度：power: active = 任一技能生效中]；
#                   low_hp {cond, below, mult}：生命低于 below 的敌人再 ×；kb：主圈从脚底向外推（不分精英，同手写）；
#                   cd_div / cd_mult [{cond, value}]：出手间隔 = every ÷ 攻速 ÷ … × …；
#                   spin2 {cond, delay, mult}：delay 秒后反向再转一圈；trail {cond, max, dur, tick, mult, src}：地上留一圈持续跳伤的水痕；
#                   whirl {cond, tick, dur, dur_dark, mult}：环斩化为持续旋转（精二旧「无尽回旋」）
#  verb.undying     放在技能 do：这个技能生效期间主控不会倒下（game.gd 经 squad.prevent_death 询问）
#  verb.substitute  放在技能 do：这个技能结束时本体倒下（anim 帧条播完），留下替身 life 秒（跟随队长、本体离场：不出手、不画）；
#                   aura {cond, every, r, slow, slow_mults, dps, src}：替身每 every 秒对 r 内敌人法伤、slow_r 内减速；elegy {cond, every}：挽歌水纹（画面）

const SP_TAGS := ["shape.saw", "verb.undying", "verb.substitute"]
const H3_GHOST := Color(0.75, 0.85, 0.95)
const H3_RED := Color(0.9, 0.3, 0.4)


static func _h3sp(o) -> Dictionary:
	var h := hw_st(o)
	if not h.has("sp"):
		h["sp"] = {"fall_t": 0.0, "doll_t": 0.0, "doll_pos": Vector2.INF, "doll_tick": 0.0, "doll_at": 0.0, "elegy_t": 0.0, "sub": {},
			"spin2_t": -1.0, "spin2_dmg": 0.0, "whirl_t": 0.0, "whirl_tick": 0.0, "whirl_n": 0, "whirl_dmg": 0.0, "whirl_ang": 0.0,
			"rings": [], "last_s": [0.0, 0.0, 0.0]}
	return h.sp


static func h3_saw_r(o, a: Dictionary) -> float:
	return _h3_mults(o, float(a.get("r", 120.0)) * o.stat(&"op_range"), a.get("r_mults", []))


## 普攻间隔（data_operator 起手）：every ÷ 攻速，再按 cd_div / cd_mult（同手写的除乘顺序），× 局部 interval
static func h3_attack_cd(o, a: Dictionary) -> float:
	var cdv: float = float(a.get("every", 1.0)) / o.stat(&"op_aspd")
	for m in a.get("cd_div", []):
		if cond_true(o, m.get("cond", {})):
			cdv /= float(m.get("value", 1.0))
	for m in a.get("cd_mult", []):
		if cond_true(o, m.get("cond", {})):
			cdv *= float(m.get("value", 1.0))
	return cdv * float(o.loc.interval)


static func _h3_any_skill(o) -> bool:
	return o.s_t[0] > 0.0 or o.s_t[1] > 0.0 or o.s_t[2] > 0.0


static func _h3_saw_release(o, a: Dictionary) -> void:
	var sp := _h3sp(o)
	var m := 1.0
	for it in a.get("mults", []):
		if not cond_true(o, it.get("cond", {})):
			continue
		var v: float = float(it.get("value", 1.0))
		if it.get("hp_lost", false):
			v += clampf(1.0 - o.g.hp / o.g.max_hp, 0.0, 1.0)
		m *= v
	var dmg: float = o.base(str(a.get("atk_key", "atk")), 0.0) * o._dmg_bonus() * m * (o.skill_power() if (str(a.get("power", "")) == "active" and _h3_any_skill(o)) else 1.0)
	hw_record(o, dmg, 0.0, h3_saw_r(o, a), o.pos)   # basis attack = 这一圈主环斩的伤害（替身闪现按它取百分比）
	_h3_spin(o, a, dmg, 0)
	var s2 = a.get("spin2", null)
	var dbl: bool = s2 is Dictionary and cond_true(o, s2.get("cond", {}))
	if dbl:
		sp.spin2_t = float(s2.get("delay", 0.15))
		sp.spin2_dmg = dmg * float(s2.get("mult", 0.7))
	var tr = a.get("trail", null)
	if tr is Dictionary and cond_true(o, tr.get("cond", {})):
		if sp.rings.size() >= int(tr.get("max", 6)):
			sp.rings.pop_front()
		sp.rings.append({"pos": o.pos, "r": h3_saw_r(o, a), "t": float(tr.get("dur", 1.5)), "tick": float(tr.get("tick", 0.5)), "dmg": dmg * float(tr.get("mult", 0.2)), "b": tr})
	var wh = a.get("whirl", null)
	if wh is Dictionary and cond_true(o, wh.get("cond", {})):
		var tk: float = float(wh.get("tick", 0.15))
		sp.whirl_t = float(wh.get("dur_dark", 1.2)) if o.g.lamp < 30.0 else float(wh.get("dur", 0.6))
		sp.whirl_n = int(round(float(sp.whirl_t) / tk)) - (1 if dbl else 0)
		sp.whirl_tick = tk * (2.0 if dbl else 1.0)
		sp.whirl_dmg = dmg * float(wh.get("mult", 0.45))


## 一圈环斩：kind 0 = 主圈 / 1 = 反向第二圈 / 2 = 持续旋转的一段
static func _h3_spin(o, a: Dictionary, dmg: float, kind: int) -> void:
	var g = o.g
	var sp: Dictionary = o.hw.sp
	var r: float = h3_saw_r(o, a)
	var hits: Array = o.arc_targets(o.pos + Vector2(0, float(a.get("y", -10.0))), 0.0, PI, r)
	var lh = a.get("low_hp", null)
	var low_on: bool = lh is Dictionary and cond_true(o, lh.get("cond", {}))
	var heavy: bool = _h3_heavy(o, a)
	var src: String = str(a.get("src", ""))
	var kb: float = float(a.get("kb", 70.0))
	for e in hits:
		var d: float = dmg
		if low_on and e.hp < e.maxhp * float(lh.get("below", 0.5)):
			d *= float(lh.get("mult", 1.5))
		o.log_hit(src, a.get("tags", []))
		o.deal_damage(e, d)
		if not e.dead and not e.boss and kind == 0:
			e.kb += (e.pos - o.pos).normalized() * kb
		o.fx({"kind": "glow", "pos": e.pos + Vector2(0, -e.r * 0.5), "r": 9.0, "life": 0.15, "col": H3_RED if heavy else H3_GHOST, "alpha": 0.5})
	var rev: bool = (o.face < 0.0) != (kind == 1)
	if kind == 2:
		rev = (o.face < 0.0) != (int(sp.whirl_n) % 2 == 1)
	var lk: Dictionary = a.get("look", {})
	if kind == 2 or not o.spawn_fx_sprite(str(lk.get("blood", "fx_specter_saw_blood")) if heavy else str(lk.get("saw", "fx_specter_saw")), o.pos + Vector2(0, -6), r / 40.0, 0.0, rev):
		o.fx({"kind": "h3_saw", "pos": o.pos + Vector2(0, -8), "r": r * (0.9 if kind == 2 else 1.0), "life": 0.3 if heavy else 0.24, "col": H3_RED if heavy else H3_GHOST,
			"spin": (-1.0 if rev else 1.0) * (26.0 if heavy else 34.0), "tooth": 8.0 if heavy else 6.0, "ang": g.vrng.randf() * TAU})
	if kind == 1:
		o.fx({"kind": "h3_saw", "pos": o.pos + Vector2(0, -8), "r": r * 1.08, "life": 0.22, "col": H3_RED if heavy else Color(0.6, 0.75, 0.95),
			"spin": (-1.0 if rev else 1.0) * 30.0, "tooth": 5.0, "ang": g.vrng.randf() * TAU})
	for e in hits:
		var ea: float = (e.pos - o.pos).angle() + PI / 2.0 * (-1.0 if rev else 1.0)
		for k in (3 if kind == 0 else 1):
			o.fx({"kind": "spark", "pos": e.pos + Vector2(0, -e.r * 0.5), "vel": Vector2.from_angle(ea + g.vrng.randf_range(-0.35, 0.35)) * g.vrng.randf_range(160, 300),
				"life": 0.22, "col": Color(1.4, 1.55, 1.75) if not heavy else Color(1.6, 0.5, 0.55), "sz": 2.0, "drag": 3.0})
	if heavy and kind == 0:
		o.fx({"kind": "crack", "pos": o.pos + Vector2(0, 4), "r": r * 0.8, "life": 0.6, "col": H3_RED, "floor": true, "n": 7})
		o.impact_pause(0.05)
	if kind == 1:
		_h3_sfx(o, "atk", -4.0, 1.15, 0.06)


static func _h3_heavy(o, a: Dictionary) -> bool:
	var hv = a.get("look", {}).get("heavy", null)
	return hv is Dictionary and cond_true(o, hv.get("cond", {}))


static func _h3_spins_tick(o, sp: Dictionary, dt: float) -> void:
	if h3_away(o):
		sp.spin2_t = -1.0
		sp.whirl_t = 0.0
		sp.whirl_n = 0
		return
	var a: Dictionary = o.B.get("attack", {})
	sp.whirl_ang = float(sp.whirl_ang) + dt * 14.0 * (1.0 if o.face >= 0.0 else -1.0)
	if float(sp.spin2_t) >= 0.0:
		sp.spin2_t = float(sp.spin2_t) - dt
		if float(sp.spin2_t) < 0.0:
			_h3_spin(o, a, float(sp.spin2_dmg), 1)
	if float(sp.whirl_t) > 0.0 or int(sp.whirl_n) > 0:
		sp.whirl_t = maxf(0.0, float(sp.whirl_t) - dt)
		sp.whirl_tick = float(sp.whirl_tick) - dt
		if float(sp.whirl_tick) <= 0.0 and int(sp.whirl_n) > 0:
			sp.whirl_tick = float(sp.whirl_tick) + float(a.get("whirl", {}).get("tick", 0.15))
			sp.whirl_n = int(sp.whirl_n) - 1
			_h3_spin(o, a, float(sp.whirl_dmg), 2)


static func _h3_rings_tick(o, sp: Dictionary, dt: float) -> void:
	if sp.rings.is_empty():
		return
	var g = o.g
	for rg in sp.rings:
		rg.t -= dt
		rg.tick -= dt
		if rg.tick <= 0.0 and rg.t > -0.01:
			rg.tick += float(rg.b.get("tick", 0.5))
			for j in o.query_ids(rg.pos, rg.r + 20.0):
				var e: Dictionary = g.enemies[j]
				if e.dead or e.pos.distance_to(rg.pos) > rg.r + e.r:
					continue
				o.log_hit(str(rg.b.get("src", "")), rg.b.get("tags", []))
				o.deal_damage(e, rg.dmg)
			_h3_vsparks(o, rg.pos + Vector2(0, 2), Color(1.1, 0.3, 0.4), 3, 60.0, 0.35, 2.0, 0.0, true)
	sp.rings = sp.rings.filter(func(rg): return rg.t > 0.0)


# ---------------------------------------------------------------- 替身（verb.substitute）/ 不倒（verb.undying）

static func h3_away(o) -> bool:
	return hw_on(o) and o.hw.has("sp") and float(o.hw.sp.doll_t) > 0.0


static func h3_prevent_death(o) -> bool:
	if not hw_on(o) or not o.hw.has("sp"):
		return false
	var sk: Array = o.B.get("skills", [])
	for i in mini(3, sk.size()):
		if o.s_t[i] > 0.0:
			for b in sk[i].get("do", []):
				if str(b.get("_tag", "")) == "verb.undying":
					return true
	return false


## 技能结束检测：带 verb.substitute 的技能剩余从 > 0 变成 0 的那一帧（同手写 s2_t -= dt; <= 0）
static func _h3_sub_check(o, sp: Dictionary) -> void:
	var sk: Array = o.B.get("skills", [])
	for i in mini(3, sk.size()):
		var was: float = float(sp.last_s[i])
		sp.last_s[i] = float(o.s_t[i])
		if was > 0.0 and o.s_t[i] <= 0.0:
			for b in sk[i].get("do", []):
				if str(b.get("_tag", "")) == "verb.substitute":
					_h3_start_fall(o, sp, b)
					break


static func _h3_fall_dur(o, b: Dictionary) -> float:
	var an: String = str(b.get("anim", "fall"))
	var spec: Dictionary = o.sprite_spec(an)
	return float(spec.get("frames", 5)) / float(spec.get("fps", 10)) if o.anim_tex(an) != null else 0.0


static func _h3_start_fall(o, sp: Dictionary, b: Dictionary) -> void:
	o.melee_tgt = null
	o.fire_t = -1.0
	sp.sub = b
	sp.fall_t = _h3_fall_dur(o, b)
	if float(sp.fall_t) <= 0.0:
		_h3_fall(o, sp)


static func _h3_fall(o, sp: Dictionary) -> void:
	var b: Dictionary = sp.sub
	sp.doll_pos = o.pos
	sp.doll_t = float(b.get("life", 12.0))
	sp.doll_tick = 0.0
	sp.doll_at = 0.0
	o.melee_tgt = null
	o.float_text(o.pos + Vector2(0, -60), str(b.get("text", "替身")), H3_GHOST, 15)
	o.fx({"kind": "glow", "pos": o.pos + Vector2(0, -24), "r": 30.0, "life": 0.5, "col": H3_GHOST, "alpha": 0.6})
	_h3_vsparks(o, o.pos + Vector2(0, -20), H3_GHOST, 10, 120.0, 0.5, 2.5)


static func _h3_doll_slow_r(o, au: Dictionary) -> float:
	return _h3_mults(o, float(au.get("r", 120.0)), au.get("slow_mults", []))


static func _h3_doll_tick(o, sp: Dictionary, dt: float) -> void:
	if float(sp.doll_t) <= 0.0:
		return
	var g = o.g
	var b: Dictionary = sp.sub
	var au: Dictionary = b.get("doll_aura", {})
	sp.doll_t = float(sp.doll_t) - dt
	sp.doll_at = float(sp.doll_at) + dt
	var fv = b.get("follow", [-46, 8])
	var want: Vector2 = g.ppos + Vector2(float(fv[0]) * g.squad.side, float(fv[1]))
	sp.doll_pos = (sp.doll_pos as Vector2).lerp(want, clampf(dt * 4.0, 0.0, 1.0))
	var el = b.get("elegy", null)
	if el is Dictionary and cond_true(o, el.get("cond", {})):
		sp.elegy_t = float(sp.elegy_t) - dt
		if float(sp.elegy_t) <= 0.0:
			sp.elegy_t = float(el.get("every", 0.8))
			var er: float = _h3_doll_slow_r(o, au)
			var dp: Vector2 = sp.doll_pos
			o.fx({"kind": "ring", "pos": dp + Vector2(0, 2), "r": er, "r0": 14.0, "life": 1.6, "col": Color(0.45, 0.75, 1.1), "floor": true, "w": 2.5, "alpha": 0.7, "keep": true})
			o.fx({"kind": "ring", "pos": dp + Vector2(0, 2), "r": er * 0.7, "r0": 6.0, "life": 1.2, "col": Color(0.8, 0.95, 1.3), "floor": true, "w": 1.5, "alpha": 0.45, "keep": true})
			o.fx({"kind": "mote", "pos": dp + Vector2(g.vrng.randf_range(-8, 8), -40), "vel": Vector2(g.vrng.randf_range(-10, 10), -26.0), "life": 1.0, "col": Color(0.6, 0.85, 1.2), "sz": 2.0})
	if not au.is_empty() and cond_true(o, au.get("cond", {})):
		sp.doll_tick = float(sp.doll_tick) + dt
		var ev: float = float(au.get("every", 1.0))
		if float(sp.doll_tick) >= ev:
			sp.doll_tick = float(sp.doll_tick) - ev
			var r: float = float(au.get("r", 120.0))
			var sr: float = _h3_doll_slow_r(o, au)
			var dp2: Vector2 = sp.doll_pos
			for j in o.query_ids(dp2, sr + 20.0):
				var e: Dictionary = g.enemies[j]
				if e.dead:
					continue
				var d: float = e.pos.distance_to(dp2)
				if d > sr:
					continue
				e.slow = maxf(e.slow, float(au.get("slow", 1.0)))
				if d > r:
					continue
				o.log_hit(str(au.get("src", "")), au.get("tags", []))
				o.deal_damage(e, float(au.get("dps", 10.0)) * o._dmg_bonus())
			if not o.spawn_fx_sprite("fx_circle_ghost", dp2 + Vector2(0, 4), g.PX * (r / 40.0)):
				o.fx({"kind": "ring", "pos": dp2, "r": r, "r0": r * 0.6, "life": 0.5, "col": H3_GHOST, "floor": true, "alpha": 0.5, "keep": true})
	if float(sp.doll_t) <= 0.0:
		sp.elegy_t = 0.0
		o.pos = sp.doll_pos
		sp.doll_pos = Vector2.INF
		o.float_text(o.pos + Vector2(0, -60), str(b.get("back_text", "归队")), H3_GHOST, 14)
		o.fx({"kind": "glow", "pos": o.pos + Vector2(0, -24), "r": 24.0, "life": 0.4, "col": H3_GHOST, "alpha": 0.5})


## 第 3 批幽灵鲨段每帧（h3_tick 转来，手写 update 的先后：技能结束 → 倒下 → 替身 → 血痕 → 气焰 → 第二圈 / 持续旋转）。返回 true = 本帧不起手
static func _h3sp_tick(o, sp: Dictionary, dt: float) -> bool:
	_h3_sub_check(o, sp)
	if float(sp.fall_t) > 0.0:
		sp.fall_t = float(sp.fall_t) - dt
		if float(sp.fall_t) <= 0.0:
			_h3_fall(o, sp)
	_h3_doll_tick(o, sp, dt)
	_h3_rings_tick(o, sp, dt)
	var g = o.g
	if o.s_t[0] > 0.0 and not h3_away(o) and g.vrng.randf() < dt * 14.0 and o.B.get("attack", {}).get("look", {}).get("flame", false):
		o.fx({"kind": "mote", "pos": o.pos + Vector2(g.vrng.randf_range(-16, 16), g.vrng.randf_range(-40, -4)), "vel": Vector2(0, -60), "life": 0.5, "col": Color(1.0, 0.2, 0.25), "sz": 2.0})
	_h3_spins_tick(o, sp, dt)
	_e3_flash_tick(o, sp, dt)   # 精英化第 3 批：替身闪现
	return h3_away(o) or float(sp.fall_t) > 0.0


static func h3_follow_away(o) -> bool:
	return h3_away(o)


## 倒下期间的帧（data_operator.anim_state 转来）
static func h3_anim_state(o, st: Dictionary) -> Dictionary:
	if not o.hw.has("sp") or float(o.hw.sp.fall_t) <= 0.0:
		return st
	var an: String = str(o.hw.sp.sub.get("anim", "fall"))
	var tx: Texture2D = o.anim_tex(an)
	if tx == null:
		return st
	var n: int = o.anim_hframes(tx, an)
	var fr: int = clampi(int((_h3_fall_dur(o, o.hw.sp.sub) - float(o.hw.sp.fall_t)) * float(o.sprite_spec(an).get("fps", 10))), 0, n - 1)
	return {"tex": tx, "frame": fr, "hf": n, "flip": (o.face < 0.0) != o.sprite_mirror(an), "kind": an}


## 替身参与 2.5D 排序（data_operator.extra_bodies 转来）
static func h3_bodies(o) -> Array:
	if not hw_on(o) or not o.hw.has("sp"):
		return []
	var sp: Dictionary = o.hw.sp
	var out: Array = []
	if float(sp.doll_t) > 0.0 and sp.doll_pos != Vector2.INF:
		out.append({"y": (sp.doll_pos as Vector2).y + 2.0, "h3": "doll"})
	if not sp.get("flash", {}).is_empty():
		out.append({"y": (sp.flash.pos as Vector2).y + 2.0, "h3": "flash"})
	return out


static func h3_draw_extra(o, it: Dictionary) -> void:
	if str(it.get("h3", "")) == "flash":
		_e3_flash_draw(o)
		return
	if str(it.get("h3", "")) == "doll":
		var sp: Dictionary = o.hw.sp
		var an: String = str(sp.sub.get("doll_anim", "doll"))
		var tx: Texture2D = o.anim_tex(an)
		var dp: Vector2 = sp.doll_pos
		if tx == null:
			o.cv.draw_circle(dp + Vector2(0, -20), 12.0, H3_GHOST)
			return
		var n: int = o.anim_hframes(tx, an)
		var fr: int = int(float(sp.doll_at) * 4.0) % n
		var sway: float = sin(float(sp.doll_at) * 2.0) * 1.0
		o.draw_sprite_at(dp + Vector2(sway, 0), o.face < 0.0, Color(0.95, 0.95, 1.0), fr, tx, n, o.foot_off(tx, an))


static func h3_draw_shadows(o) -> void:
	if not hw_on(o) or not o.hw.has("sp"):
		return
	var sp: Dictionary = o.hw.sp
	if float(sp.doll_t) > 0.0 and sp.doll_pos != Vector2.INF:
		o.draw_spr("shadow", 1, 0, (sp.doll_pos as Vector2) + Vector2(0, 4), o.g.PX)


## 地面层：潮痕（血色潮痕节点留下的水痕圈）。10-14 用户「血色水痕容易和怪物的攻击提示重合」：敌方预警是红色填充 + 白芯深色描边（world.draw_warn_outlines），
## 这里改成低饱和的深海青、压低透明度、线收细，不带白芯，和敌方预警分开；纯画面
const H3SP_TIDE_FILL := Color(0.07, 0.2, 0.25)
const H3SP_TIDE_EDGE := Color(0.3, 0.56, 0.62)
const H3SP_TIDE_RIPPLE := Color(0.4, 0.66, 0.7)
static func _h3sp_draw_floor(o) -> void:
	var cv = o.cv
	var sp: Dictionary = o.hw.sp
	for rg in sp.rings:
		var a: float = clampf(rg.t / 0.5, 0.0, 1.0)
		var age: float = float(rg.b.get("dur", 1.5)) - rg.t
		cv.draw_set_transform(rg.pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
		cv.draw_circle(Vector2.ZERO, rg.r, Color(H3SP_TIDE_FILL.r, H3SP_TIDE_FILL.g, H3SP_TIDE_FILL.b, 0.12 * a))
		cv.draw_arc(Vector2.ZERO, rg.r, 0.0, TAU, 40, Color(H3SP_TIDE_EDGE.r, H3SP_TIDE_EDGE.g, H3SP_TIDE_EDGE.b, 0.4 * a), 1.5)
		cv.draw_arc(Vector2.ZERO, rg.r * (0.5 + 0.4 * fmod(age * 1.2, 1.0)), 0.0, TAU, 32, Color(H3SP_TIDE_RIPPLE.r, H3SP_TIDE_RIPPLE.g, H3SP_TIDE_RIPPLE.b, 0.22 * a), 1.0)
		for q in 6:
			var an: float = q * TAU / 6.0 + rg.pos.x * 0.01
			cv.draw_circle(Vector2.from_angle(an) * rg.r, 2.0, Color(H3SP_TIDE_RIPPLE.r, H3SP_TIDE_RIPPLE.g, H3SP_TIDE_RIPPLE.b, 0.32 * a))
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 区域层：求生之技气焰、技能期间的锯环圈、替身光环圈
static func _h3sp_draw_auras(o) -> void:
	var g = o.g
	var cv = o.cv
	var sp: Dictionary = o.hw.sp
	var a: Dictionary = o.B.get("attack", {})
	var lk: Dictionary = a.get("look", {})
	var away: bool = h3_away(o)
	if o.pos != Vector2.INF and not away and o.s_t[0] > 0.0 and lk.get("flame", false):
		var hk: float = 0.5 + 0.5 * sin(g.t * 9.0)
		cv.draw_circle(o.pos + Vector2(0, -22), 22.0 + 3.0 * hk, Color(1.0, 0.1, 0.15, 0.16))
		for q in 7:
			var an: float = q * TAU / 7.0 + g.t * 2.0
			var bp: Vector2 = o.pos + Vector2(cos(an) * 16.0, -6.0 + sin(an) * 7.0)
			var hh: float = 14.0 + 6.0 * sin(g.t * 13.0 + q * 2.1)
			cv.draw_colored_polygon(PackedVector2Array([bp + Vector2(-4, 0), bp + Vector2(sin(g.t * 20.0 + q) * 2.0, -hh), bp + Vector2(4, 0)]), Color(1.5, 0.2, 0.25, 0.55))
	if o.pos != Vector2.INF and not away and _h3_any_skill(o):
		var c: Color = H3_RED if _h3_heavy(o, a) else H3_GHOST
		cv.draw_set_transform(o.pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
		cv.draw_arc(Vector2.ZERO, h3_saw_r(o, a), 0.0, TAU, 36, Color(c.r, c.g, c.b, 0.25 + 0.1 * sin(g.t * 6.0)), 2.0)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if float(sp.doll_t) > 0.0 and sp.doll_pos != Vector2.INF and not sp.sub.is_empty():
		var au: Dictionary = sp.sub.get("doll_aura", {})
		if not au.is_empty() and cond_true(o, au.get("cond", {})):
			cv.draw_set_transform((sp.doll_pos as Vector2) + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
			cv.draw_arc(Vector2.ZERO, float(au.get("r", 120.0)), 0.0, TAU, 36, Color(H3_GHOST.r, H3_GHOST.g, H3_GHOST.b, 0.2 + 0.08 * sin(g.t * 3.0)), 2.0)
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 上层：持续旋转的锯弧、技能期间眼中寒光
static func _h3sp_draw_over(o) -> void:
	if h3_away(o) or o.pos == Vector2.INF:
		return
	var g = o.g
	var cv = o.cv
	var sp: Dictionary = o.hw.sp
	var a: Dictionary = o.B.get("attack", {})
	if float(sp.whirl_t) > 0.0:
		var r: float = h3_saw_r(o, a) * 0.92
		var fade: float = clampf(float(sp.whirl_t) / 0.2, 0.0, 1.0)
		var heavy: bool = _h3_heavy(o, a) or g.lamp < 30.0
		var c: Color = Color(1.5, 0.45, 0.5) if heavy else Color(1.2, 1.35, 1.6)
		cv.draw_set_transform(o.pos + Vector2(0, -8), 0.0, Vector2(1.0, 0.55))
		for q in 2:
			var a0: float = float(sp.whirl_ang) + q * PI
			for k in 4:
				cv.draw_arc(Vector2.ZERO, r - k * 2.0, a0 - k * 0.22, a0 - k * 0.22 + 1.1, 16, Color(c.r, c.g, c.b, (0.85 - k * 0.2) * fade), 4.0 - k * 0.7)
			cv.draw_circle(Vector2.from_angle(a0 + 1.1) * r, 4.0, Color(c.r * 1.3, c.g * 1.3, c.b * 1.3, 0.9 * fade))
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if (o.s_t[1] > 0.0 or o.s_t[2] > 0.0) and a.get("look", {}).get("eye", false):
		var p: Vector2 = o.pos + Vector2(4.0 * o.face, -38)
		var c2: Color = H3_RED if o.s_t[2] > 0.0 else H3_GHOST
		cv.draw_circle(p, 2.5 + sin(g.t * 24.0), Color(c2.r * 2.0, c2.g * 1.6, c2.b * 1.6, 0.9))


## 锯环（程序）：半径 0→r 快速张开，锯齿斜切、按 spin 旋转；地面透视压扁
static func _h3_draw_saw(o, f: Dictionary, a: float) -> void:
	var cv = o.cv
	var u: float = 1.0 - a
	var rr: float = f.r * (0.55 + 0.45 * (1.0 - pow(1.0 - minf(1.0, u / 0.25), 2.0)))
	var rot: float = f.ang + f.spin * u * f.max
	var c: Color = f.col
	var T: float = f.tooth
	var n: int = clampi(int(TAU * rr / (T * 1.6)), 16, 48)
	var P := func(v: Vector2) -> Vector2: return (v / 2.0).round() * 2.0
	var fp: Vector2 = f.pos
	var flat := func(v: Vector2) -> Vector2: return fp + Vector2(v.x, v.y * 0.55)
	cv.draw_set_transform(fp, 0.0, Vector2(1.0, 0.55))
	cv.draw_arc(Vector2.ZERO, rr * 0.92, 0.0, TAU, 48, Color(c.r, c.g, c.b, 0.18 * a), T * 1.6)
	cv.draw_arc(Vector2.ZERO, rr, 0.0, TAU, 56, Color(0.05, 0.06, 0.09, 0.8 * a), 7.0)
	cv.draw_arc(Vector2.ZERO, rr, 0.0, TAU, 56, Color(c.r * 0.8, c.g * 0.8, c.b * 0.85, 0.95 * a), 4.0)
	cv.draw_arc(Vector2.ZERO, rr - 3.0, 0.0, TAU, 56, Color(c.r * 1.5, c.g * 1.5, c.b * 1.5, 0.7 * a), 1.0)
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var sgn: float = signf(f.spin)
	for i in n:
		var t0: float = rot + TAU * i / n
		var t1: float = t0 + sgn * TAU / n * 0.75
		var base0: Vector2 = Vector2.from_angle(t0) * rr
		var base1: Vector2 = Vector2.from_angle(t1) * rr
		var tip: Vector2 = Vector2.from_angle(t1) * (rr + T)
		var pts := PackedVector2Array([P.call(flat.call(base0)), P.call(flat.call(tip)), P.call(flat.call(base1))])
		if absf((pts[1] - pts[0]).cross(pts[2] - pts[0])) < 2.0:
			continue
		var lit: float = 0.75 + 0.35 * clampf(sin(t0), 0.0, 1.0)
		cv.draw_colored_polygon(pts, Color(c.r * lit * 1.3, c.g * lit * 1.3, c.b * lit * 1.35, a))


static func _h3sp_status(o) -> Array:
	var out: Array = []
	var sp: Dictionary = o.hw.sp
	var a: Dictionary = o.B.get("attack", {})
	if h3_prevent_death(o):
		out.append(["不倒", H3_GHOST])
	if o.s_t[2] > 0.0 and _h3_heavy(o, a):
		out.append([str(o.skill_def(2).get("name", "")), H3_RED])
	for m in a.get("r_mults", []):
		if m.has("status") and cond_true(o, m.get("cond", {})):
			out.append([str(m.status), H3_RED])
	if float(sp.doll_t) > 0.0:
		out.append(["%s %d" % [str(sp.sub.get("text", "替身")), int(ceil(float(sp.doll_t)))], H3_GHOST])
	return out


# ---------------------------------------------------------------- 流明段（第 3 批续，LM_TAGS）
#  shape.lantern    普攻「荧光」：每 heal.every 秒（不在出手、没技能可放的帧累计）到点就起手，出手帧驱散优先（侵蚀 > corrode、神经 > nerve）、
#                   其次治疗（pct × [mults] × op_atk × 同伴 × heal_out）；同时向射程内（视线优先，手动普攻 B 类）最近敌人射一发光弹 bolt
#                   {atk_key, speed, life, r, aoe, splash, lit, src}（本段自己推进，同时 ≤ 12 发，地形挡）；命中照亮 lit 秒并溅射。
#                   units {nodes, cd0, cd, mult, speed, src, charge {cond, need, shots, mult, speed, heal}}：成长节点给的发光单元，各自定时射光弹
#  verb.mend        瞬时：为队长回复 pct × 最大生命 × op_atk × 同伴 × heal_out [× 技能强度]（满血也结算），飘字 + 光环
#  verb.purge       瞬时：清除侵蚀与神经损伤，immune 秒内神经损伤归零
#  verb.light_rain  瞬时（cond 自写）：dur 秒内队长 r 内敌人每 tick 秒受 mult × 光弹、被照亮（发光单元洒下光雨，有单元才下）
#  verb.beam_window 瞬时：dur 秒内亮起旋转光束（verb.beam 的窗口）
#  verb.tower       放在持续技能 do：灯塔随行（光域中心平滑跟到队长，r 内回复 / 驱散 / 灯火 / 圣域），技能结束时光爆 burst {mult[], power, kb, stun, src}
#  verb.beam        常驻（成长节点）：灯塔在场或光束窗口内，旋转光束每 tick 秒扫一次（长 len、周期 period），扫到的敌人 mult × 光弹并照亮（同一敌人 cd 秒一次）
#  verb.heal_lamp   常驻（天赋）：每次治疗 / 驱散灯火 + add；灯火 ≥ lamp 时自身技力额外 + rate × 自然充能
#  verb.lamp 新参数 decay_mult / radius_mult：受击灯火损失倍率（light_decay）/ 队长照亮半径倍率（沛霖）

const LM_TAGS := ["shape.lantern", "verb.mend", "verb.purge", "verb.light_rain", "verb.beam_window", "verb.tower", "verb.beam", "verb.heal_lamp"]
const H3_WARM := Color(1.0, 0.85, 0.55)
const H3_PALE := Color(0.7, 0.9, 1.0)
const H3_BOLT_MAX := 12


static func _h3lm(o) -> Dictionary:
	var h := hw_st(o)
	if not h.has("lm"):
		h["lm"] = {"heal_t": 0.0, "immune_t": 0.0, "bolts": [], "mote_t": 0.0, "hand_glow": 0.0, "armed": false,
			"tower_pos": Vector2.INF, "tower_side": 1.0, "tower_tick": 0.0, "tower_b": {}, "last_s": [0.0, 0.0, 0.0],
			"unit_cd": [], "unit_fire": [-9.0, -9.0, -9.0, -9.0], "unit_fdir": [1.0, 1.0, 1.0, 1.0], "charge_n": 0, "empowered": 0,
			"rain_t": 0.0, "rain_tick": 0.0, "rain_b": {}, "beam_t": 0.0, "beam_tick": 0.0, "beam_hit": {}}
	return h.lm


static func _h3_heal_mult(o) -> float:
	return o.stat(&"op_atk") * o.g.ally_mult * o.stat(&"heal_out")


## 生效中的天赋积木（第一块 tag 的）
static func _h3_trig_block(o, tag: String) -> Dictionary:
	for t in o._trigs():
		if str(t.get("_tag", "")) != "trig.passive" or not cond_true(o, t.get("cond", {})):
			continue
		for b in t.get("do", []):
			if str(b.get("_tag", "")) == tag and cond_true(o, b.get("cond", {})):
				return b
	return {}


## 天赋：每次回复 / 驱散灯火 +add（同手写 _talent_lamp）
static func _h3_heal_lamp(o) -> void:
	var b := _h3_trig_block(o, "verb.heal_lamp")
	if not b.is_empty():
		o.g.lamp = minf(o.g.lamp_cap, o.g.lamp + float(b.get("add", 2.0)))


## 治疗队长（同手写 _heal_doctor：满血也结算）
static func _h3_mend(o, h: float, size: int, sub: String) -> void:
	var g = o.g
	if h <= 0.0:
		return
	o.heal_leader(h, o.display_name(), sub)
	o.float_text(g.ppos + Vector2(0, -90), "+%d" % int(h), H3_WARM, size)
	o.spawn_fx_sprite("fx_holy_impact_lantern", g.ppos + Vector2(0, -34), g.PX * 0.9)
	if not o.spawn_fx_sprite("fx_heal_aura_amber", g.ppos + Vector2(0, 6), g.PX * 1.2, 0.0, false, true):
		o.fx({"kind": "ring", "pos": g.ppos, "r": 28.0, "r0": 8.0, "life": 0.4, "col": H3_WARM, "floor": true, "keep": true})


## 出手帧提灯位置（脚底前 hand[0]、上 hand[1]）
static func _h3_lamp_hand(o, a: Dictionary) -> Vector2:
	var hv = a.get("hand", [31, -42])
	return o.pos + Vector2(float(hv[0]) * o.face, float(hv[1]))


static func _h3_bolt_range(o, a: Dictionary) -> float:
	return float(a.get("range", 330.0)) * o.stat(&"op_range")


## 起手（hw: 不在出手、没有技能要放的帧）：先累计荧光计时，再看冷却
static func _h3_lantern_start(o, a: Dictionary, dt: float) -> void:
	var lm := _h3lm(o)
	var hb: Dictionary = a.get("heal", {})
	lm.heal_t = float(lm.heal_t) + dt
	if o.cd > 0.0:
		return
	var rr: float = _h3_bolt_range(o, a)
	var ts: Array = o.attack_targets(1, rr, o.pos) if o.manual_attack() else o.los_targets(1, rr, o.pos)
	lm.armed = not ts.is_empty()
	var every: float = float(a.get("every", 1.0)) / o.stat(&"op_aspd")
	if not ts.is_empty() or float(lm.heal_t) >= float(hb.get("every", 3.0)):
		o.cd = every
		o.start_attack(ts[0].pos if not ts.is_empty() else o.g.ppos)
	else:
		o.cd = o.idle_cd(every)


static func _h3_lantern_release(o, a: Dictionary) -> void:
	var g = o.g
	var lm := _h3lm(o)
	var hb: Dictionary = a.get("heal", {})
	var hand: Vector2 = _h3_lamp_hand(o, a)
	var did := false
	if float(lm.heal_t) < float(hb.get("every", 3.0)):
		pass
	elif g.corrode_pool > 0.5 or g.nerve > 0.5:
		if g.bot != null:
			g.telemetry.note_clean("corrode", g.corrode_pool)
			g.telemetry.note_clean("nerve", minf(g.nerve, float(hb.get("nerve_cut", 15.0))))
		g.corrode_pool = 0.0
		g.nerve = maxf(0.0, g.nerve - float(hb.get("nerve_cut", 15.0)))
		o.float_text(g.ppos + Vector2(0, -96), "驱散", H3_PALE, 14)
		did = true
	elif g.hp < g.max_hp:
		var pct: float = g.max_hp * float(hb.get("pct", 0.02))
		var gm := 1.0
		for m in hb.get("mults", []):
			if cond_true(o, m.get("cond", {})):
				gm = float(m.get("mult", 1.0))
		_h3_mend(o, pct * gm * _h3_heal_mult(o), 15, str(hb.get("sub", "")))
		did = true
	if did:
		lm.heal_t = 0.0
		_h3_heal_lamp(o)
		g.fx.append({"kind": "beam", "a": hand, "b": g.ppos + Vector2(0, -24), "life": 0.25, "max": 0.25, "col": H3_WARM, "w": 2.5})
	lm.hand_glow = 0.18
	var rr: float = _h3_bolt_range(o, a)
	var ts: Array = ((o.aim_targets(1, rr, o.pos) if lm.armed else []) if o.manual_attack() else o.los_targets(1, rr, o.pos))
	if not ts.is_empty():
		var bt: Dictionary = a.get("bolt", {})
		var d: Vector2 = (ts[0].pos - hand).normalized()
		if _e3_beam_shot(o, lm, hand, ts[0].pos, o.base(str(bt.get("atk_key", "atk")), 0.0) * o._dmg_bonus()):
			return   # 精英化第 3 批：这一发变灯塔光柱
		if lm.bolts.size() < H3_BOLT_MAX:
			lm.bolts.append({"pos": hand, "vel": d * float(bt.get("speed", 380.0)), "dmg": o.base(str(bt.get("atk_key", "atk")), 0.0) * o._dmg_bonus(), "life": float(bt.get("life", 1.4)), "src": str(bt.get("src", ""))})


static func _h3_bolts_tick(o, lm: Dictionary, dt: float) -> void:
	if lm.bolts.is_empty():
		return
	var g = o.g
	var bt: Dictionary = o.B.get("attack", {}).get("bolt", {})
	var main_src: String = str(bt.get("src", ""))
	for b in lm.bolts:
		b.pos += b.vel * dt
		b.life -= dt
		lm.mote_t = float(lm.mote_t) - dt
		if b.life > 0.0 and g.map.tb_bul and g.map.bullet_blocked(b, b.pos):
			b.life = 0.0
			continue
		for j in o.query_ids(b.pos, 30.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or e.pos.distance_to(b.pos) > e.r + float(bt.get("r", 8.0)):
				continue
			var src: String = b.get("src", main_src)
			var was_lit: bool = float(e.get("lit", 0.0)) > 0.0   # 精英化第 3 批：折光看命中前是否已被照亮
			o.log_hit(src)
			o.deal_damage(e, b.dmg)
			e["lit"] = float(bt.get("lit", 3.0))
			_h3_sfx(o, "hit", -4.0 if src != main_src else 0.0)
			if b.get("heal", 0.0) > 0.0 and g.hp < g.max_hp:
				o.heal_leader(b.heal, o.display_name(), str(b.get("heal_sub", "")))
				o.fx({"kind": "glow", "pos": g.ppos + Vector2(0, -26), "r": 10.0, "life": 0.25, "col": H3_WARM, "alpha": 0.5})
			var ar: float = float(bt.get("aoe", 24.0))
			for j2 in o.query_ids(b.pos, ar + 20.0):
				var q: Dictionary = g.enemies[j2]
				if q.dead or is_same(q, e) or q.pos.distance_to(b.pos) > ar + q.r:
					continue
				o.log_hit(src)
				o.deal_damage(q, b.dmg * float(bt.get("splash", 0.6)))
				q["lit"] = float(bt.get("lit", 3.0))
			if was_lit:
				_e3_refract(o, bt, e, b.dmg)
			b.life = 0.0
			if not o.spawn_fx_sprite("fx_holy_impact_lantern", e.pos + Vector2(0, -e.r * 0.5), g.PX * 0.7):
				o.fx({"kind": "glow", "pos": e.pos + Vector2(0, -e.r * 0.5), "r": 12.0, "life": 0.25, "col": H3_WARM, "alpha": 0.6})
			_h3_vsparks(o, e.pos + Vector2(0, -e.r * 0.5), H3_WARM, 4, 120.0, 0.3, 2.0)
			break
	lm.bolts = lm.bolts.filter(func(b): return b.life > 0.0)


# ---- 灯塔（verb.tower）

static func h3_tower_start(o, b: Dictionary) -> void:
	var lm := _h3lm(o)
	lm.tower_pos = o.g.ppos
	lm.tower_tick = 0.0
	lm.tower_b = b
	var i := _h3_tower_i(o)
	lm.tower_t = o.s_t[i] if i >= 0 else 0.0   # 同技能剩余（各自每帧 -dt；这份不夹 0，同手写 tower_t）


## 灯塔在场：带 verb.tower 的技能剩余 > 0
static func _h3_tower_i(o) -> int:
	var sk: Array = o.B.get("skills", [])
	for i in mini(3, sk.size()):
		for b in sk[i].get("do", []):
			if str(b.get("_tag", "")) == "verb.tower":
				return i
	return -1


static func _h3_tower_on(o) -> bool:
	return float(o.hw.lm.get("tower_t", 0.0)) > 0.0 and o.hw.lm.tower_pos != Vector2.INF


static func _h3_tower_tick(o, lm: Dictionary, dt: float) -> void:
	if float(lm.get("tower_t", 0.0)) <= 0.0:
		return
	lm.tower_t = float(lm.tower_t) - dt
	var g = o.g
	var b: Dictionary = lm.tower_b
	var tt: float = lm.tower_t
	lm.tower_pos = (lm.tower_pos as Vector2).lerp(g.ppos, clampf(dt * 10.0, 0.0, 1.0))
	lm.tower_side = move_toward(float(lm.tower_side), g.facing, dt * 5.0)
	var r: float = float(b.get("r", 220.0))
	if tt > 0.0 and g.ppos.distance_to(lm.tower_pos) < r:
		if g.bot != null:
			g.telemetry.note_clean("corrode", g.corrode_pool)
		g.corrode_pool = 0.0
		g.nerve = 0.0
		lm.tower_tick = float(lm.tower_tick) + dt
		if float(lm.tower_tick) >= float(b.get("every", 1.0)):
			lm.tower_tick = float(lm.tower_tick) - float(b.get("every", 1.0))
			g.lamp = minf(g.lamp_cap, g.lamp + float(b.get("lamp", 2.0)))
			if g.hp < g.max_hp:
				o.heal_leader(g.max_hp * float(b.get("heal", 0.015)) * _h3_heal_mult(o), o.display_name(), str(b.get("sub", "")))
				_h3_heal_lamp(o)
	lm.mote_t = float(lm.mote_t) - dt
	if float(lm.mote_t) <= 0.0:
		lm.mote_t = 0.06
		var ma: float = g.vrng.randf() * TAU
		var mr: float = g.vrng.randf() * r
		o.fx({"kind": "mote", "pos": (lm.tower_pos as Vector2) + Vector2(cos(ma) * mr, sin(ma) * mr * 0.55), "vel": Vector2(0, -35), "life": 0.8, "col": H3_WARM, "sz": 1.8})
	if tt <= 0.0:
		_h3_light_burst(o, lm, b)


static func _h3_light_burst(o, lm: Dictionary, b: Dictionary) -> void:
	var g = o.g
	var r: float = float(b.get("r", 220.0))
	var bu: Dictionary = b.get("burst", {})
	var tp: Vector2 = lm.tower_pos
	var dmg: float = hw_mul(o.base(str(bu.get("atk_key", "atk")), 0.0), bu.get("mult", 3.0)) * o._dmg_bonus()
	if bu.get("power", false):
		dmg *= o.skill_power()
	o.area_hit(str(bu.get("src", "")), tp, r, dmg, float(bu.get("kb", 160.0)), float(bu.get("stun", 0.6)))
	o.spawn_fx_sprite("fx_sunburst", tp + Vector2(0, -40), g.PX * 2.4)
	for i in 3:
		o.fx({"kind": "ring", "pos": tp, "r": r * (0.6 + 0.2 * i), "r0": 16.0, "life": 0.4 + 0.1 * i, "col": H3_WARM, "floor": true, "w": 4.0 - i})
	g.fx.append({"kind": "rays", "pos": tp + Vector2(0, -40), "life": 0.6, "max": 0.6, "col": H3_WARM, "op_spoke": true})
	_h3_vsparks(o, tp + Vector2(0, -30), H3_WARM, 18, 240.0, 0.5, 3.0, 160.0)
	o.float_text(tp + Vector2(0, -90), str(bu.get("src", "")), H3_WARM, 18)
	g.shake = maxf(g.shake, 4.0)
	_h3_sfx(o, "big")
	lm.tower_pos = Vector2.INF


static func h3_sanctuary(o) -> Dictionary:
	if not hw_on(o) or not o.hw.has("lm") or not _h3_tower_on(o):
		return {}
	return {"pos": o.hw.lm.tower_pos, "r": float(o.hw.lm.tower_b.get("r", 220.0))}


## 队长照亮半径倍率：生效中的 verb.lamp radius_mult
static func h3_light_mult(o) -> float:
	if not hw_on(o) or not o.hw.has("lm"):
		return 1.0
	var m := 1.0
	var sk: Array = o.B.get("skills", [])
	for i in mini(3, sk.size()):
		if o.skill_on(i):
			for b in sk[i].get("do", []):
				if str(b.get("_tag", "")) == "verb.lamp" and b.has("radius_mult"):
					m *= float(b.radius_mult)
	return m


static func _h3_tower_sprite_pos(o) -> Vector2:
	var lm: Dictionary = o.hw.lm
	return (lm.tower_pos as Vector2) + Vector2(-40.0 * float(lm.tower_side), -8.0 + 3.0 * sin(o.g.t * 2.4))


static func _h3_tower_lamp(o) -> Vector2:
	return _h3_tower_sprite_pos(o) + Vector2(0, -83.0)


# ---- 发光单元

static func _h3_units_n(o, a: Dictionary) -> int:
	var un: Dictionary = a.get("units", {})
	var n := 0
	for nid in un.get("nodes", []):
		if str(nid) in o.taken:
			n += 1
	return mini(n, int(un.get("max", 2)))


static func _h3_unit_pos(o, k: int) -> Vector2:
	var g = o.g
	var ang: float = g.t * 1.1 + k * PI
	return o.pos + Vector2(cos(ang) * 30.0, -72.0 + sin(ang) * 7.0 + sin(g.t * 2.3 + k * 1.7) * 3.0)


static func _h3_units_tick(o, lm: Dictionary, dt: float) -> void:
	var a: Dictionary = o.B.get("attack", {})
	var units: int = _h3_units_n(o, a)
	if units <= 0 or o.pos == Vector2.INF:
		return
	var g = o.g
	var un: Dictionary = a.get("units", {})
	var bt: Dictionary = a.get("bolt", {})
	if lm.unit_cd.is_empty():
		lm.unit_cd = un.get("cd0", [0.5, 1.2]).duplicate()
		while lm.unit_cd.size() < 4:
			lm.unit_cd.append(1.0)
	var rng_r: float = _h3_bolt_range(o, a)
	var ch = un.get("charge", null)
	var charge_on: bool = ch is Dictionary and cond_true(o, ch.get("cond", {}))
	for k in units:
		lm.unit_cd[k] = float(lm.unit_cd[k]) - dt
		if float(lm.unit_cd[k]) > 0.0:
			continue
		var ts: Array = o.los_targets(1, rng_r, o.pos, _h3_unit_pos(o, k))
		if ts.is_empty() or lm.bolts.size() >= H3_BOLT_MAX:
			lm.unit_cd[k] = 0.15
			continue
		lm.unit_cd[k] = float(un.get("cd", 1.4)) / o.stat(&"op_aspd")
		var up: Vector2 = _h3_unit_pos(o, k)
		var d: Vector2 = (ts[0].pos + Vector2(0, -ts[0].r * 0.5) - up).normalized()
		var dmg: float = o.base(str(bt.get("atk_key", "atk")), 0.0) * o._dmg_bonus() * float(un.get("mult", 0.6))
		if _e3_beam_shot(o, lm, up, ts[0].pos, dmg):   # 精英化第 3 批：这一发变灯塔光柱
			lm.unit_fire[k] = g.t
			lm.unit_fdir[k] = -1.0 if d.x < 0.0 else 1.0
			continue
		var big := false
		if charge_on:
			if int(lm.empowered) > 0:
				lm.empowered = int(lm.empowered) - 1
				big = true
				dmg *= float(ch.get("mult", 2.0))
			else:
				lm.charge_n = int(lm.charge_n) + 1
				if int(lm.charge_n) >= int(ch.get("need", 8)):
					lm.charge_n = 0
					lm.empowered = int(ch.get("shots", 8))
					o.fx({"kind": "ring", "pos": o.pos + Vector2(0, -94), "r": 22.0, "r0": 4.0, "life": 0.4, "col": H3_WARM, "keep": true})
					_h3_vsparks(o, o.pos + Vector2(0, -94), H3_WARM, 8, 120.0, 0.4, 2.0)
		lm.unit_fire[k] = g.t
		lm.unit_fdir[k] = -1.0 if d.x < 0.0 else 1.0
		lm.bolts.append({"pos": up, "vel": d * (float(ch.get("speed", 340.0)) if big else float(un.get("speed", 400.0))), "dmg": dmg, "life": float(bt.get("life", 1.4)),
			"src": str(un.get("src", "")), "big": big, "heal": g.max_hp * float(ch.get("heal", 0.005)) if big else 0.0, "heal_sub": str(ch.get("heal_sub", "")) if big else ""})
		o.fx({"kind": "glow", "pos": up, "r": 12.0 if big else 8.0, "life": 0.2, "col": H3_WARM, "alpha": 0.6})


# ---- 光雨 / 光束

static func h3_light_rain(o, b: Dictionary) -> void:
	var lm := _h3lm(o)
	if _h3_units_n(o, o.B.get("attack", {})) <= 0:
		return
	lm.rain_t = float(b.get("dur", 3.0))
	lm.rain_tick = 0.0
	lm.rain_b = b


static func _h3_rain_tick(o, lm: Dictionary, dt: float) -> void:
	if float(lm.rain_t) <= 0.0:
		return
	var g = o.g
	var b: Dictionary = lm.rain_b
	lm.rain_t = float(lm.rain_t) - dt
	lm.rain_tick = float(lm.rain_tick) - dt
	if float(lm.rain_tick) > 0.0:
		return
	lm.rain_tick = float(lm.rain_tick) + float(b.get("tick", 0.5))
	var r: float = float(b.get("r", 140.0))
	for j in o.query_ids(g.ppos, r + 20.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or e.pos.distance_to(g.ppos) > r + e.r:
			continue
		e["lit"] = maxf(e.get("lit", 0.0), 1.0)
		o.log_hit(str(b.get("src", "")))
		o.deal_damage(e, o.base(str(b.get("atk_key", "atk")), 0.0) * o._dmg_bonus() * float(b.get("mult", 0.15)) * o.skill_power())
		o.fx({"kind": "glow", "pos": e.pos + Vector2(0, -e.r * 0.5), "r": 7.0, "life": 0.2, "col": H3_WARM, "alpha": 0.5})


static func _h3_beam_block(o) -> Dictionary:
	for t in o._trigs():
		if not cond_true(o, t.get("cond", {})):
			continue
		if str(t.get("_tag", "")) == "verb.beam":
			return t
		if str(t.get("_tag", "")) == "trig.passive":
			for b in t.get("do", []):
				if str(b.get("_tag", "")) == "verb.beam" and cond_true(o, b.get("cond", {})):
					return b
	return {}


static func _h3_beam_on(o, bb: Dictionary) -> bool:
	return not bb.is_empty() and (_h3_tower_on(o) or float(o.hw.lm.beam_t) > 0.0)


static func _h3_beam_origin(o) -> Vector2:
	return _h3_tower_sprite_pos(o) if _h3_tower_on(o) else o.g.ppos


static func _h3_beam_dir(o, bb: Dictionary) -> Vector2:
	var a: float = o.g.t * TAU / float(bb.get("period", 2.0))
	return Vector2(cos(a), sin(a) * 0.55)


static func _h3_beam_tick(o, lm: Dictionary, dt: float) -> void:
	var g = o.g
	for k in lm.beam_hit.keys():
		lm.beam_hit[k] -= dt
		if lm.beam_hit[k] <= 0.0:
			lm.beam_hit.erase(k)
	lm.beam_t = maxf(0.0, float(lm.beam_t) - dt)
	var bb := _h3_beam_block(o)
	if not _h3_beam_on(o, bb):
		return
	lm.beam_tick = float(lm.beam_tick) - dt
	if float(lm.beam_tick) > 0.0:
		return
	lm.beam_tick = float(lm.beam_tick) + float(bb.get("tick", 0.2))
	var L: float = float(bb.get("len", 260.0))
	var a: Vector2 = _h3_beam_origin(o)
	var b: Vector2 = a + _h3_beam_dir(o, bb) * L
	for j in o.query_ids(a, L + 20.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or lm.beam_hit.has(e.id):
			continue
		var q: Vector2 = Geometry2D.get_closest_point_to_segment(e.pos, a, b)
		if q.distance_to(e.pos) > e.r + 14.0:
			continue
		lm.beam_hit[e.id] = float(bb.get("cd", 0.4))
		e["lit"] = 3.0
		o.log_hit(str(bb.get("src", "")))
		o.deal_damage(e, o.base(str(bb.get("atk_key", "atk")), 0.0) * o._dmg_bonus() * float(bb.get("mult", 0.4)) * o.skill_power())
		o.fx({"kind": "glow", "pos": e.pos + Vector2(0, -e.r * 0.5), "r": 9.0, "life": 0.2, "col": H3_WARM, "alpha": 0.6})


## 天赋：灯火 ≥ lamp 时自身技力额外充能（同手写，在出手判定之前）
static func _h3_lamp_charge(o, dt: float) -> void:
	var b := _h3_trig_block(o, "verb.heal_lamp")
	var g = o.g
	if b.is_empty() or not b.has("rate") or g.lamp < float(b.get("lamp", 70.0)):
		return
	for i in 3:
		if o.skill_unlocked(i) and o.sp_need(i) > 0.0 and not o.perm[i] and o.skill_active_left(i) <= 0.0:
			o.sp[i] = minf(o.sp_need(i), o.sp[i] + dt * float(b.rate) * g.sp_mult * o.stat(&"op_skill_sp") * o.lamp_sp() * (0.0 if g.apop_t > 0.0 else 1.0))


## 流明段每帧（h3_tick 转来，手写 update 的先后：提灯光 / 免疫 → 光弹 → 灯塔 → 发光单元 → 光雨 → 光束 → 天赋充能）
static func _h3lm_tick(o, lm: Dictionary, dt: float) -> void:
	var g = o.g
	lm.hand_glow = maxf(0.0, float(lm.hand_glow) - dt)
	lm.immune_t = maxf(0.0, float(lm.immune_t) - dt)
	if float(lm.immune_t) > 0.0:
		g.nerve = 0.0
	_h3_bolts_tick(o, lm, dt)
	_h3_tower_tick(o, lm, dt)
	_h3_units_tick(o, lm, dt)
	_h3_rain_tick(o, lm, dt)
	_h3_beam_tick(o, lm, dt)
	if o.elite >= 1:
		_h3_lamp_charge(o, dt)


static func h3_mend(o, b: Dictionary) -> void:
	var g = o.g
	var h: float = g.max_hp * float(b.get("pct", 0.05)) * _h3_heal_mult(o)
	if b.get("power", false):
		h *= o.skill_power()
	_h3_mend(o, h, int(b.get("text", 18)), str(b.get("sub", "")))


static func h3_purge(o, b: Dictionary) -> void:
	var g = o.g
	var lm := _h3lm(o)
	if g.bot != null:
		g.telemetry.note_clean("corrode", g.corrode_pool)
		g.telemetry.note_clean("nerve", g.nerve)
	g.corrode_pool = 0.0
	g.nerve = 0.0
	lm.immune_t = float(b.get("immune", 3.0))


# ---- 画面

static func _h3lm_draw_auras(o) -> void:
	if not _h3_tower_on(o):
		return
	var g = o.g
	var cv = o.cv
	var r: float = float(o.hw.lm.tower_b.get("r", 220.0))
	cv.draw_set_transform((o.hw.lm.tower_pos as Vector2) + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
	cv.draw_circle(Vector2.ZERO, r, Color(H3_WARM.r, H3_WARM.g, H3_WARM.b, 0.05))
	cv.draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(H3_WARM.r, H3_WARM.g, H3_WARM.b, 0.35 + 0.1 * sin(g.t * 4.0)), 2.5)
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _h3lm_draw_over(o) -> void:
	var g = o.g
	var cv = o.cv
	var lm: Dictionary = o.hw.lm
	var a: Dictionary = o.B.get("attack", {})
	var bt: Dictionary = a.get("bolt", {})
	var tn: String = str(bt.get("tex", "proj_lumen_bolt"))
	for b in lm.bolts:
		var big: bool = b.get("big", false)
		if g.tex.get(tn) != null:
			if big:
				cv.draw_line(b.pos - b.vel.normalized() * 22.0, b.pos, Color(2.0, 1.6, 0.9, 0.55), 6.0)
				cv.draw_circle(b.pos, 8.0, Color(1.6, 1.3, 0.7, 0.5))
			o.draw_spr_rot(tn, int(g.t * 12.0 + b.pos.x * 0.05) % 6, b.pos, b.vel.angle(), g.PX * (1.5 if big else 1.0), Color(1.5, 1.35, 1.1) if big else Color.WHITE)
		else:
			cv.draw_line(b.pos - b.vel.normalized() * 14.0, b.pos, Color(H3_WARM.r * 1.4, H3_WARM.g * 1.3, H3_WARM.b, 0.5), 5.0 if big else 3.0)
			cv.draw_circle(b.pos, 6.0 if big else 4.0, Color(2.0, 1.8, 1.2))
	_h3lm_draw_units(o)
	_h3lm_draw_rain(o)


static func _h3lm_draw_units(o) -> void:
	var g = o.g
	var cv = o.cv
	var lm: Dictionary = o.hw.lm
	var a: Dictionary = o.B.get("attack", {})
	var units: int = _h3_units_n(o, a)
	if units <= 0 or o.pos == Vector2.INF:
		return
	var utx: Texture2D = o.A.tex("fx_lumen_unit")
	var hot: bool = int(lm.empowered) > 0
	for k in units:
		var p: Vector2 = _h3_unit_pos(o, k)
		var pulse: float = 0.5 + 0.5 * sin(g.t * 6.0 + k * 2.0)
		cv.draw_circle(p, 9.0 + 2.0 * pulse, Color(1.0, 0.8, 0.4, 0.16 if not hot else 0.3))
		if utx != null:
			var firing: bool = g.t - float(lm.unit_fire[k]) < 0.083
			var uf: int = 4 if firing else (int(g.t * 6.0) + k * 2) % 4
			o._strip(utx, 5, uf, p, g.PX, Vector2(6, 7), firing and float(lm.unit_fdir[k]) < 0.0, Color(1.35, 1.25, 1.05) if hot else Color.WHITE)
			continue
		cv.draw_colored_polygon(PackedVector2Array([p + Vector2(-5, -4), p + Vector2(5, -4), p + Vector2(3, -7), p + Vector2(-3, -7)]), Color(0.35, 0.27, 0.18))
		cv.draw_rect(Rect2(p + Vector2(-4, -4), Vector2(8, 7)), Color(1.0, 0.85, 0.5, 0.55))
		cv.draw_rect(Rect2(p + Vector2(-2, -2), Vector2(4, 4)), Color(2.2, 1.9, 1.2) if hot else Color(1.8, 1.5, 0.9))
		cv.draw_rect(Rect2(p + Vector2(-4, 3), Vector2(8, 2)), Color(0.35, 0.27, 0.18))
		cv.draw_line(p + Vector2(0, 5), p + Vector2(0, 9 + 2.0 * pulse), Color(1.4, 1.1, 0.6, 0.6), 1.0)
	var ch = a.get("units", {}).get("charge", null)
	if ch is Dictionary and cond_true(o, ch.get("cond", {})):
		var need: int = int(ch.get("need", 8))
		var c0: Vector2 = o.pos + Vector2(-(need - 1) * 3.0, -94)
		for q in need:
			var pp: Vector2 = c0 + Vector2(q * 6.0, 0)
			var on: bool = (q < int(lm.empowered)) if int(lm.empowered) > 0 else (q < int(lm.charge_n))
			var col: Color = Color(2.0, 1.6, 0.7) if (on and int(lm.empowered) > 0) else (Color(1.2, 1.05, 0.8) if on else Color(0.25, 0.22, 0.2, 0.8))
			cv.draw_rect(Rect2(pp - Vector2(2, 2), Vector2(4, 4)), col)


static func _h3lm_draw_rain(o) -> void:
	var lm: Dictionary = o.hw.lm
	if float(lm.rain_t) <= 0.0:
		return
	var g = o.g
	var cv = o.cv
	var b: Dictionary = lm.rain_b
	var r: float = float(b.get("r", 140.0))
	var fade: float = clampf(float(lm.rain_t) / 0.4, 0.0, 1.0) * clampf((float(b.get("dur", 3.0)) - float(lm.rain_t)) / 0.3, 0.0, 1.0)
	cv.draw_set_transform(g.ppos + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
	cv.draw_circle(Vector2.ZERO, r, Color(1.0, 0.85, 0.5, 0.06 * fade))
	cv.draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(1.3, 1.1, 0.7, 0.35 * fade), 1.5)
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for q in 28:
		var ph: float = fmod(g.t * 1.8 + q * 0.379, 1.0)
		var cyc: int = int(g.t * 1.8 + q * 0.379)
		var hh: int = hash(Vector2i(q, cyc))
		var an: float = float(hh % 628) / 100.0
		var rr: float = r * sqrt(float((hh >> 10) % 100) / 100.0)
		var ground: Vector2 = g.ppos + Vector2(cos(an) * rr, sin(an) * rr * 0.55)
		var top: Vector2 = ground + Vector2(0, -70.0 * (1.0 - ph))
		cv.draw_line(top + Vector2(0, -8), top, Color(1.6, 1.35, 0.8, 0.7 * fade), 1.5)
		if ph > 0.85:
			cv.draw_set_transform(ground, 0.0, Vector2(1.0, 0.5))
			cv.draw_arc(Vector2.ZERO, 3.0 + (ph - 0.85) * 40.0, 0.0, TAU, 10, Color(1.4, 1.2, 0.7, 0.5 * fade), 1.0)
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 加色层（data_operator.draw_fx_add 转来）
static func h3_draw_add(o, ci) -> void:
	if not hw_on(o) or not o.hw.has("lm") or o.pos == Vector2.INF:
		return
	var g = o.g
	var lm: Dictionary = o.hw.lm
	var a: Dictionary = o.B.get("attack", {})
	if float(lm.hand_glow) > 0.0:
		var hk: float = sin(float(lm.hand_glow) / 0.3 * PI)
		var hp: Vector2 = _h3_lamp_hand(o, a)
		ci.draw_circle(hp, 11.0 * (0.5 + 0.5 * hk), Color(0.9, 0.7, 0.35, 0.45 * hk))
		ci.draw_circle(hp, 4.0 * hk, Color(1.0, 0.9, 0.6, 0.8 * hk))
	var twr: bool = _h3_tower_on(o)
	if twr:
		var k: float = 0.5 + 0.5 * sin(g.t * 3.0)
		ci.draw_circle(_h3_tower_lamp(o), 26.0 + 4.0 * k, Color(0.9, 0.7, 0.35, 0.35))
		ci.draw_set_transform((lm.tower_pos as Vector2) + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
		ci.draw_circle(Vector2.ZERO, float(lm.tower_b.get("r", 220.0)) * 0.9, Color(0.6, 0.45, 0.2, 0.06 + 0.02 * k))
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for b in lm.bolts:
		ci.draw_circle(b.pos, 14.0 if b.get("big", false) else 9.0, Color(0.9, 0.7, 0.3, 0.35))
	var bb := _h3_beam_block(o)
	if _h3_beam_on(o, bb):
		var L: float = float(bb.get("len", 260.0))
		var org: Vector2 = _h3_beam_origin(o)
		var d: Vector2 = _h3_beam_dir(o, bb)
		var n: Vector2 = Vector2(-d.y, d.x).normalized()
		var tip: Vector2 = org + d * L
		var fade: float = clampf((float(lm.tower_t) if twr else float(lm.beam_t)) / 0.5, 0.0, 1.0)
		ci.draw_colored_polygon(PackedVector2Array([org + n * 4.0, tip + n * 26.0, tip - n * 26.0, org - n * 4.0]), Color(0.9, 0.7, 0.35, 0.28 * fade))
		ci.draw_colored_polygon(PackedVector2Array([org + n * 2.0, tip + n * 10.0, tip - n * 10.0, org - n * 2.0]), Color(1.0, 0.85, 0.5, 0.35 * fade))
		ci.draw_line(_h3_tower_lamp(o) if twr else org + Vector2(0, -44.0), org + d * 30.0, Color(0.9, 0.75, 0.4, 0.3 * fade), 3.0)


static func _h3lm_bodies(o) -> Array:
	if _h3_tower_on(o):
		return [{"y": (o.hw.lm.tower_pos as Vector2).y + 2.0, "h3": "tower"}]
	return []


static func _h3lm_draw_tower(o) -> void:
	var b: Dictionary = o.hw.lm.tower_b
	var an: String = str(b.get("anim", "lighthouse"))
	var tx: Texture2D = o.anim_tex(an)
	if tx == null:
		o.cv.draw_rect(Rect2((o.hw.lm.tower_pos as Vector2) + Vector2(-8, -60), Vector2(16, 60)), Color(0.5, 0.6, 0.7))
		return
	var n: int = o.anim_hframes(tx, an)
	o.draw_sprite_at(_h3_tower_sprite_pos(o), false, Color.WHITE, 1 % n, tx, n, o.foot_off(tx, an))


static func _h3lm_shadow(o) -> void:
	if _h3_tower_on(o):
		var sp: Vector2 = _h3_tower_sprite_pos(o)
		var tp: Vector2 = o.hw.lm.tower_pos
		o.draw_spr("shadow", 1, 0, Vector2(sp.x, tp.y + 4.0), o.g.PX * (1.3 - 0.02 * (tp.y - sp.y - 8.0)))


static func _h3lm_status(o) -> Array:
	var out: Array = []
	if _h3_tower_on(o):
		out.append([str(o.hw.lm.tower_b.get("status", "灯塔")), H3_WARM])
	if float(o.hw.lm.immune_t) > 0.0:
		out.append(["净化", H3_PALE])
	return out


# ---------------------------------------------------------------- 水月段（第 3 批续，MZ_TAGS）
#  attack.flow: free  不等动作的干员：技能充满即发（不起技能动作、发完不停手），普攻不起手直接出手（播一下攻击帧），每帧不看「正在出手」
#  shape.umbrella   伞击（普攻）：扇形 half = min(180°, half_deg + 角度加成)，半径 r × 范围倍率 × r_mults；伤害 = atk × 伤害倍率 × 加成 × dmg_mults；
#                   dirs [{cond, n}]（镜花水月三方向）；kb / stun [{cond, dur}]；empower（次数型技能的补丁：mult × 技能强度、r_mult、kb、burst 创伤扩散、
#                   swarm 额外触手）；tentacle：命中里生命最低的 n 个（n = 追击数属性 + n_add）触手追击 × t_mult，不够打附近的；
#                   drag 束缚时拖向自己；stake 触手桩（旧精二「固着」）；echo 镜像分身延时同步挥伞。stats：专属属性（attack.stats 映射 → 属性名）
#  verb.kill_heal   天赋（on_kill do）：击杀时为队长回复 pct × 最大生命（每秒预算 regen、上限 cap）
#  verb.cast_push   瞬时：发动时推开身边 r 内的非 Boss 敌人（技能发动光环）
#  verb.mirror      瞬时：镜像分身出现在自己身边（之后平滑跟在身后，镜花水月）
#  blocks.dmg_bonus {ally: false, mults [{cond, near_low_hp {r, below}, mult}]}：本干员的伤害加成（不吃同伴倍率；附近有半血敌人时 ×）

const MZ_TAGS := ["shape.umbrella", "verb.kill_heal", "verb.cast_push", "verb.mirror"]
const H3_GOLD := Color(0.957, 0.753, 0.306)   # 同 ui.gd GOLD（灯火金：唤醒）


static func _h3mz(o) -> Dictionary:
	var h := hw_st(o)
	if not h.has("mz"):
		h["mz"] = {"budget": 0.0, "stakes": [], "delayed": [], "afterimg": [], "afterimg_t": 0.0, "mirror_pos": Vector2.ZERO, "mirror_face": 1.0,
			"last_s": [0.0, 0.0, 0.0], "st": {}}
	return h.mz


## 专属属性缓存（data_operator.sync_stats 转来，同手写 sync_stats）
static func h3_sync_stats(o, st) -> void:
	if not hw_on(o) or not o.hw.has("mz"):
		return
	var sc: Array = o.scopes()
	var m: Dictionary = o.B.get("attack", {}).get("stats", {})
	for k in m:
		o.hw.mz.st[k] = st.value_for(StringName(str(m[k])), sc)


static func _h3_st(o, k: String, def: float) -> float:
	return float(o.hw.mz.st.get(k, def))


## data_operator._dmg_bonus 转来（blocks.dmg_bonus）
static func h3_dmg_bonus(o) -> float:
	var db: Dictionary = o.B.get("dmg_bonus", {})
	var m: float = o.stat(&"dmg") * o.stat(&"op_atk")
	if db.get("ally", true):
		m *= o.g.ally_mult
	for it in db.get("mults", []):
		if not cond_true(o, it.get("cond", {})):
			continue
		var nl = it.get("near_low_hp", null)
		if nl is Dictionary and not _h3_low_hp_near(o, float(nl.get("r", 160.0)), float(nl.get("below", 0.5))):
			continue
		m *= float(it.get("mult", 1.0))
	return m


static func _h3_low_hp_near(o, r: float, below: float) -> bool:
	var g = o.g
	for j in o.query_ids(o.pos, r):
		var e: Dictionary = g.enemies[j]
		if not e.dead and e.hp < e.maxhp * below and e.pos.distance_to(o.pos) < r:
			return true
	return false


static func h3_umb_radius(o, a: Dictionary) -> float:
	return _h3_mults(o, float(a.get("r", 142.0)) * _h3_st(o, "area", 1.0), a.get("r_mults", []))


## 一帧（data_operator.update 转来，attack.flow = free）：手写水月 update 的先后——击杀回复预算 → 触手桩 → 镜像 / 残影 → 技能 → 延时攻击 → 挥伞
static func h3_free_update(o, dt: float) -> void:
	var g = o.g
	var mz := _h3mz(o)
	var a: Dictionary = o.B.get("attack", {})
	o._sustain(dt)   # 常驻积木（成长节点的专属属性 buff_self 等）先落地，同手写节点当场 refresh_stats
	var kh := _h3_talent_any(o, "verb.kill_heal")
	if not kh.is_empty():
		mz.budget = min(float(mz.budget) + dt * float(kh.get("regen", 0.05)), float(kh.get("cap", 0.05)))
	_h3_stakes_tick(o, mz, dt)
	_e3_jelly_tick(o, mz, dt)   # 精英化第 3 批：深蓝之籽
	var s3i: int = int(a.get("mirror_skill", 2))
	var was3: float = float(mz.last_s[s3i])
	for i in 3:
		mz.last_s[i] = float(o.s_t[i])
	if was3 > 0.0:
		mz.mirror_pos = (mz.mirror_pos as Vector2).lerp(o.pos + Vector2(-o.face * 80.0, -10.0), minf(1.0, dt * 8.0))
		mz.afterimg_t = float(mz.afterimg_t) - dt
		if float(mz.afterimg_t) <= 0.0:
			mz.afterimg_t = 0.06
			var ast: Dictionary = o.anim_state()
			if not ast.is_empty():
				mz.afterimg.push_front({"pos": o.pos, "frame": ast.frame, "tex": ast.tex, "hf": ast.hf, "flip": ast.flip})
			if mz.afterimg.size() > 5:
				mz.afterimg.pop_back()
	else:
		mz.afterimg.clear()
	var ready: int = o.charge_skills(dt)
	if ready >= 0:
		_h3_free_skill(o, ready)
		mz.last_s[ready] = float(o.s_t[ready])
	for i in range(mz.delayed.size() - 1, -1, -1):
		var dl: Dictionary = mz.delayed[i]
		dl.at -= dt
		if dl.at <= 0.0:
			mz.delayed.remove_at(i)
			_h3_run_delayed(o, a, dl)
	if o.cd <= 0.0:
		var radius: float = h3_umb_radius(o, a)
		var at: Vector2 = o.atk_point(o.nearest_enemies(1, radius + float(a.get("aim_pad", 60.0)), o.pos), radius)
		if at != Vector2.INF:
			var interval: float = float(a.get("every", 0.9)) * _h3_st(o, "interval", 1.0) / o.stat(&"op_aspd") * (float(a.get("slow_mult", 1.5)) if g.atk_slow > 0.0 else 1.0)
			for m in a.get("interval_mults", []):
				if cond_true(o, m.get("cond", {})):
					interval *= float(m.get("mult", 1.0))
			o.cd = max(float(a.get("min_cd", 0.18)), interval)
			_h3_umbrella(o, a, at)
		else:
			o.cd = o.idle_cd(float(a.get("idle", 0.1)))


static func _h3_talent_any(o, tag: String) -> Dictionary:
	for sec in ["trait", "talent"]:
		for t in o.B.get(sec, []):
			for b in t.get("do", []):
				if str(b.get("_tag", "")) == tag:
					return b
	return {}


## 技能充满即发：扣技力（发动音 / 藏品事件），次数型叠到 stack_max，持续型开计时，再执行 do（不停手）
static func _h3_free_skill(o, i: int) -> void:
	var sk: Array = o.B.get("skills", [])
	o.spend_sp(i)
	if i >= sk.size():
		return
	var sb: Dictionary = sk[i]
	var dv = sb.get("dur", 0)
	if dv is Dictionary and dv.has("next_attacks"):
		o.ammo[i] = mini(int(sb.get("stack_max", 1)), o.ammo[i] + int(dv.next_attacks))
	elif not (dv is Dictionary) and float(dv) > 0.0:
		o.s_t[i] = float(dv)
		o.s_dur[i] = float(dv)
	o._exec_list(sb.get("do", []))
	if sb.has("fx"):
		fx_play(o, sb.fx, o.pos, 30.0)
	o.play_vis_anim(o.skill_anim(i))   # 技能帧条只是画面（docs/97 B：player_skill 8 帧 12fps，末帧 = 待机）：逻辑已在上面即时生效


## 伞击
static func _h3_umbrella(o, a: Dictionary, at: Vector2) -> void:
	var g = o.g
	var mz: Dictionary = o.hw.mz
	var radius: float = h3_umb_radius(o, a)
	var half: float = deg_to_rad(min(180.0, float(a.get("half_deg", 75.0)) + _h3_st(o, "arc", 0.0)))
	var ang: float = (at - o.pos).angle()
	o.face_to(ang)
	o.attack_t = o.attack_dur
	var dmg: float = o.base(str(a.get("atk_key", "atk")), 0.0) * _h3_st(o, "dmg", 1.0) * o._dmg_bonus()
	for m in a.get("dmg_mults", []):
		if cond_true(o, m.get("cond", {})):
			dmg *= float(m.get("mult", 1.0))
	var emp := {}
	var sk: Array = o.B.get("skills", [])
	for i in 3:
		if o.ammo[i] > 0 and i < sk.size():
			o.ammo[i] -= 1
			emp = sk[i].get("attack_patch", {})
			break
	var empowered: bool = not emp.is_empty()
	if empowered:
		dmg *= float(emp.get("mult", 1.0)) * o.skill_power()
		radius *= float(emp.get("r_mult", 1.0))
	var dirs: Array = [ang]
	for dv in a.get("dirs", []):
		if cond_true(o, dv.get("cond", {})):
			dirs = [ang, ang + TAU / 3.0, ang - TAU / 3.0]
			break
	var seen := {}
	var hit: Array = []
	for d in dirs:
		for e in o.arc_targets(o.pos, d, half, radius):
			if not seen.has(e.id):
				seen[e.id] = true
				hit.append(e)
	var lk: Dictionary = a.get("look", {})
	var s3: bool = dirs.size() > 1
	if s3:
		o.spawn_fx_sprite(str(lk.get("mass", "fx_mizuki_tentacle_mass")), o.pos + Vector2.from_angle(ang) * radius * 0.55 + Vector2(0, 12), g.PX * 0.9, 0.0, cos(ang) < 0.0, true, h3_deep_col(o))
	g.crit_hit = empowered
	dmg *= g.rfx.single_hit_mult(hit.size())
	var stun := 0.0
	for sv in a.get("stun", []):
		if cond_true(o, sv.get("cond", {})):
			stun = float(sv.get("dur", 0.0))
			break
	var src: String = str(a.get("src", ""))
	for e in hit:
		o.log_hit(src, ["empowered"] if empowered else [])
		o.deal_damage(e, dmg)
		if not e.boss:
			e.kb += (e.pos - o.pos).normalized() * (float(emp.get("kb", 360.0)) if empowered else float(a.get("kb", 240.0)))
		if stun > 0.0 and not e.dead:
			e.stun = maxf(e.stun, stun)
	g.crit_hit = false
	if empowered:
		var sfx: Node = g.get_node_or_null("/root/Sfx") if g.is_inside_tree() else null
		if sfx != null:
			sfx.play("swing_heavy", -3.0)
	else:
		_h3_sfx(o, "atk", 3.0)
	if hit.size() > 0:
		_h3_sfx(o, "hit", 8.0 if empowered else 4.0, 0.85 if empowered else 1.0)
		o.impact_pause(0.09 if empowered else 0.03)
		for k in min(hit.size(), 6):
			var he: Dictionary = hit[k]
			o.sparks(he.pos, he.pos - o.pos, H3_GOLD if empowered else Color(0.85, 0.97, 1.0), 4 if empowered else 3, 260.0)
	# 触手追击
	var tb: Dictionary = a.get("tentacle", {})
	var alive := hit.filter(func(e): return not e.dead)
	alive.sort_custom(func(x, y): return x.hp < y.hp)
	var n: int = int(_h3_st(o, "t_n", 1.0))
	for m in tb.get("n_add", []):
		if cond_true(o, m.get("cond", {})):
			n += int(m.get("n", 1))
	var tdmg: float = dmg * _h3_st(o, "t_mult", 0.6)
	var tstun := 0.0
	for sv in tb.get("stun", []):
		if cond_true(o, sv.get("cond", {})):
			tstun = float(sv.get("dur", 0.0))
			break
	for i in min(n, alive.size()):
		_h3_tentacle(o, a, alive[i], tdmg, tstun)
	if hit.size() > 0 and alive.size() < n:
		var more: Array = o.nearest_enemies(n + 4, radius * float(tb.get("more_r", 1.6)), o.pos).filter(func(e): return not e.dead and not alive.has(e))
		for i in mini(n - alive.size(), more.size()):
			_h3_tentacle(o, a, more[i], tdmg, tstun)
	var sw = emp.get("swarm", null)
	if empowered and sw is Dictionary and cond_true(o, sw.get("cond", {})):
		var near: Array = o.nearest_enemies(int(sw.get("n", 2)), radius * float(sw.get("r_mult", 1.6)), o.pos)
		for ne in near:
			if not ne.dead:
				_h3_tentacle(o, a, ne, tdmg, float(sw.get("stun", 0.4)))
	# 唤醒：命中处范围冲击（创伤扩散）
	var bu = emp.get("burst", null)
	if empowered and hit.size() > 0 and bu is Dictionary:
		var ip: Vector2 = hit[0].pos
		g.fx.append({"kind": "impact", "pos": ip, "ang": ang, "life": 0.35, "max": 0.35, "col": H3_GOLD})
		g.fx.append({"kind": "ring", "pos": ip, "r": 70.0, "life": 0.3, "max": 0.3, "col": H3_GOLD, "op_hit": true})
		g.flash = maxf(g.flash, 0.12)
		for k in mini(hit.size(), int(bu.get("n", 3))):
			mz.delayed.append({"at": float(bu.get("gap", 0.06)) * k, "kind": "burst", "pos": hit[k].pos, "dmg": dmg * float(bu.get("mult", 0.6)), "r": float(bu.get("r", 80.0)), "b": bu})
	# 镜花水月：镜像分身同步挥伞
	var ec = a.get("echo", null)
	if ec is Dictionary and cond_true(o, ec.get("cond", {})):
		mz.delayed.append({"at": float(ec.get("delay", 0.12)), "kind": "echo", "ang": ang, "dmg": dmg * float(ec.get("mult", 0.6)) * o.skill_power(), "half": half, "radius": radius, "dirs": dirs.size(), "b": ec})
	# 斩击表现
	var slash_col := Color.WHITE
	if empowered:
		slash_col = Color(1.6, 1.3, 0.7)
	elif s3:
		slash_col = Color(1.2, 0.85, 1.6)
	elif o.s_t[1] > 0.0:
		slash_col = Color(0.8, 1.1, 1.5)
	var slash_tex: String = o.slash_tex_name("awaken" if empowered else ("mirage" if s3 else "base"))
	if slash_tex.begins_with("fx_umbrella_slash"):
		slash_col = Color(1.15, 1.15, 1.15)
	if empowered and alive.size() > 0:
		o.play_anim_fx("fx_s1_burst", alive[0].pos, 0.35)
	for k in min(hit.size(), 3):
		o.enemy_hit_fx(hit[k], hit[k].pos - o.pos)
	for d in dirs:
		o.slash_fx(o.pos, d, half, radius, slash_col, slash_tex, 0.26 if empowered else 0.22)
	if empowered and not slash_tex.begins_with("fx_umbrella_slash"):
		o.slash_fx(o.pos, ang, half * 0.9, radius * 1.25, Color(2.0, 1.5, 0.6, 0.8), "slash", 0.3)


static func _h3_tentacle(o, a: Dictionary, target: Dictionary, dmg: float, stun: float) -> void:
	var g = o.g
	var mz: Dictionary = o.hw.mz
	var tb: Dictionary = a.get("tentacle", {})
	var p: Vector2 = target.pos
	o.log_hit(str(tb.get("src", "")))
	o.deal_damage(target, dmg)
	if not target.dead:
		target.stun = max(target.stun, stun if stun > 0.0 else float(tb.get("stun_min", 0.25)))
		var dr = tb.get("drag", null)
		if dr is Dictionary and cond_true(o, dr.get("cond", {})) and not target.boss:
			target.kb += (o.pos - target.pos).normalized() * (float(dr.get("kb_elite", 160.0)) if target.elite else float(dr.get("kb", 320.0)))
		_e3_pull(o, a, target)   # 精英化第 3 批：拖拽
		_e3_mark(o, target)   # 精英化第 3 批：深蓝之籽优先打被触手打过的
	var sk = tb.get("stake", null)
	if sk is Dictionary and cond_true(o, sk.get("cond", {})):
		if mz.stakes.size() >= int(sk.get("max", 6)):
			mz.stakes.pop_front()
		mz.stakes.append({"pos": p, "t": float(sk.get("life", 1.5)), "tick": float(sk.get("every", 0.5)), "dmg": dmg * float(sk.get("mult", 0.4)), "flip": g.vrng.randf() < 0.5, "b": sk})
	g.fx.append({"kind": "rift", "pos": p, "r": 26.0, "life": 0.25, "max": 0.25})
	if not o.spawn_fx_sprite("fx_mizuki_tentacle", p + Vector2(0, 10), g.PX, 0.0, g.vrng.randf() < 0.5, true, h3_deep_col(o)):
		var tl: float = 0.4 if g.tex.get("fx_tentacle_strike") != null else 0.6
		g.fx.append({"kind": "tentacle", "pos": p, "life": tl, "max": tl, "flip": g.vrng.randf() < 0.5})
	o.spawn_fx_sprite("fx_tentacle_grab", p + Vector2(0, -target.r * 0.6), g.PX * clampf(target.r / 12.0, 1.0, 2.0), g.vrng.randf() * TAU, false, false, h3_deep_col(o, 1.4))
	g.fx.append({"kind": "tendril", "a": o.pos + Vector2(0, 6), "b": p + Vector2(0, 6), "life": 0.32, "max": 0.32, "seed": g.vrng.randf() * 10.0})
	g.fx.append({"kind": "ring", "pos": p + Vector2(0, 4), "r": 34.0, "life": 0.3, "max": 0.3, "col": h3_deep_col(o, 1.6), "op_hit": true})
	var sfx: Node = g.get_node_or_null("/root/Sfx") if g.is_inside_tree() else null
	if sfx != null:
		sfx.play("tentacle", -4.0)
	o.sparks(p + Vector2(0, 8), Vector2.UP, h3_deep_col(o, 1.5), 7, 200.0)


static func _h3_stakes_tick(o, mz: Dictionary, dt: float) -> void:
	var g = o.g
	for s in mz.stakes:
		s.t -= dt
		s.tick -= dt
		if s.tick <= 0.0 and s.t > 0.0:
			var sk: Dictionary = s.b
			s.tick = float(sk.get("every", 0.5))
			var any := false
			var sr: float = float(sk.get("r", 60.0))
			for j in o.query_ids(s.pos, sr + 20.0):
				var e: Dictionary = g.enemies[j]
				if e.dead or e.pos.distance_to(s.pos) > sr + e.r:
					continue
				any = true
				o.log_hit(str(o.B.get("attack", {}).get("tentacle", {}).get("src", "")))
				o.deal_damage(e, s.dmg)
			if any:
				o.spawn_fx_sprite("fx_mizuki_tentacle", s.pos + Vector2(0, 10), g.PX * 0.85, 0.0, s.flip, true, h3_deep_col(o))
				s.flip = not s.flip
	mz.stakes = mz.stakes.filter(func(s): return s.t > 0.0)


static func _h3_run_delayed(o, a: Dictionary, dl: Dictionary) -> void:
	var g = o.g
	var mz: Dictionary = o.hw.mz
	match str(dl.kind):
		"burst":
			var bu: Dictionary = dl.b
			for j in o.query_ids(dl.pos, dl.r):
				var e: Dictionary = g.enemies[j]
				if not e.dead and e.pos.distance_to(dl.pos) < dl.r + e.r:
					o.log_hit(str(bu.get("src", "")))
					o.deal_damage(e, dl.dmg)
					if not e.boss:
						e.kb += (e.pos - dl.pos).normalized() * float(bu.get("kb", 200.0))
			g.fx.append({"kind": "burst", "pos": dl.pos, "r": dl.r, "life": 0.4, "max": 0.4, "col": H3_GOLD, "op_spoke": true})
			o.sparks(dl.pos, Vector2.ZERO, Color(1.0, 0.8, 0.4), 10, 280.0)
			var sfx: Node = g.get_node_or_null("/root/Sfx") if g.is_inside_tree() else null
			if sfx != null:
				sfx.play("boom", -10.0, 1.4, 0.1)
		"echo":
			var ec: Dictionary = dl.b
			var mp: Vector2 = mz.mirror_pos
			var ma: float = dl.ang
			var near_d: float = dl.radius * float(ec.get("near", 1.4))
			for e in g.enemies:
				if e.dead or e.get("friendly", false):
					continue
				var dd: float = mp.distance_to(e.pos)
				if dd < near_d:
					near_d = dd
					ma = (e.pos - mp).angle()
			var dirs: Array = [ma]
			if dl.dirs > 1:
				dirs = [ma, ma + TAU / 3.0, ma - TAU / 3.0]
			var seen := {}
			var mt: String = o.slash_tex_name("mirage")
			for d in dirs:
				for e in o.arc_targets(mp, d, dl.half, dl.radius):
					if seen.has(e.id):
						continue
					seen[e.id] = true
					o.log_hit(str(ec.get("src", "")), ec.get("tags", []))
					o.deal_damage(e, dl.dmg)
					if not e.dead:
						e.stun = maxf(e.stun, float(ec.get("stun", 0.3)))
				o.slash_fx(mp, d, dl.half, dl.radius, Color(1.0, 0.9, 1.2, 0.8) if mt.begins_with("fx_") else Color(0.9, 0.6, 1.6, 0.8), mt, 0.3)
			mz.mirror_face = -1.0 if cos(ma) < 0.0 else 1.0
			_h3_sfx(o, "atk", 0.0, 0.8)


## 技能发动光环 + 推开身边小怪（同手写 _skill_cast）
static func h3_cast_push(o, b: Dictionary) -> void:
	var g = o.g
	var big: bool = b.get("big", false)
	o.play_anim_fx("fx_cast", o.pos, 0.5, g.PX * (1.3 if big else 1.0), true)
	o.screen_shake(0.8 if big else 0.5)
	g.flash = maxf(g.flash, 0.25)
	var c: Color = _mf_col(b.get("col", []), Color(0.45, 0.8, 1.0))
	g.fx.append({"kind": "ring", "pos": o.pos, "r": 160.0, "life": 0.5, "max": 0.5, "col": c, "op_hit": true})
	g.fx.append({"kind": "ring", "pos": o.pos, "r": 260.0, "life": 0.7, "max": 0.7, "col": c, "op_hit": true})
	g.fx.append({"kind": "rays", "pos": o.pos, "life": 0.6, "max": 0.6, "col": c, "op_spoke": true})
	o.sparks(o.pos + Vector2(0, -20), Vector2.ZERO, c, 24, 360.0)
	var r: float = float(b.get("r", 140.0))
	for j in o.query_ids(o.pos, r):
		var e: Dictionary = g.enemies[j]
		if not e.dead and not e.boss and not e.chest:
			e.kb += (e.pos - o.pos).normalized() * float(b.get("kb", 420.0))


static func h3_kill_heal(o, b: Dictionary) -> void:
	var g = o.g
	var mz := _h3mz(o)
	var got: float = min(float(b.get("pct", 0.01)), float(mz.budget))
	mz.budget = float(mz.budget) - got
	o.heal_leader(g.max_hp * got, o.display_name())


## 触手本体的染色：look.deep（常态）/ look.deep_rej（排异后）× bright
static func h3_deep_col(o, bright := 1.0) -> Color:
	var lk: Dictionary = o.B.get("attack", {}).get("look", {})
	var c: Color = _mf_col(lk.get("deep", []), Color(0.22, 0.34, 0.88)) if o.rej.is_empty() else _mf_col(lk.get("deep_rej", []), Color(0.62, 0.34, 1.0))
	return Color(c.r * bright, c.g * bright, c.b * bright)


static func h3_tentacle_col(o, bright := 1.0) -> Color:
	if not hw_on(o) or not o.hw.has("mz"):
		return Color(1.3, 1.1, 1.6)
	var lk: Dictionary = o.B.get("attack", {}).get("look", {})
	var c: Color = _mf_col(lk.get("pale", []), Color(0.62, 0.9, 1.35)) if o.rej.is_empty() else _mf_col(lk.get("pale_rej", []), Color(1.25, 0.7, 1.6))
	return Color(c.r * bright, c.g * bright, c.b * bright)


# ---- 画面

static func _h3mz_draw_floor(o) -> void:
	var g = o.g
	var cv = o.cv
	var mz: Dictionary = o.hw.mz
	for f in g.fx:
		if f.kind == "tentacle":
			_h3_draw_tentacle(o, f)
	_e3_draw_binds(o)
	for s in mz.stakes:
		var a: float = clampf(s.t / 0.4, 0.0, 1.0)
		var sr: float = float(s.b.get("r", 60.0))
		cv.draw_set_transform(s.pos + Vector2(0, 6), 0.0, Vector2(1.0, 0.45))
		cv.draw_circle(Vector2.ZERO, sr * 0.8, Color(0.55, 0.4, 0.85, 0.12 * a))
		cv.draw_arc(Vector2.ZERO, sr * 0.8, 0.0, TAU, 24, Color(0.85, 0.7, 1.2, 0.45 * a), 1.5)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var bp: Vector2 = o.pos + Vector2(0, 6)
	var lr: float = o.lamp_radius()
	cv.draw_set_transform(bp, 0.0, Vector2(1.0, 0.5))
	for q in 32:
		if q % 2 == 0:
			cv.draw_arc(Vector2.ZERO, lr, TAU * q / 32.0 + g.t * 0.1, TAU * (q + 1) / 32.0 + g.t * 0.1, 3, Color(1.6, 1.3, 0.8, 0.22), 1.5)
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if o.s_t[2] > 0.0:
		var r: float = 110.0
		var fade := clampf(o.s_t[2] / 1.0, 0.0, 1.0) * clampf((o.s_dur[2] - o.s_t[2]) / 0.4, 0.0, 1.0)
		cv.draw_set_transform(bp, 0.0, Vector2(1.0, 0.45))
		cv.draw_circle(Vector2.ZERO, r, Color(0.5, 0.35, 1.0, 0.13 * fade))
		for q in 3:
			var rp := fmod(g.t * 0.6 + q / 3.0, 1.0)
			cv.draw_arc(Vector2.ZERO, r * rp, 0.0, TAU, 48, Color(1.4, 1.0, 2.2, (1.0 - rp) * 0.55 * fade), 2.0)
		cv.draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, Color(1.2, 0.9, 2.0, 0.7 * fade), 2.5)
		for q in 12:
			var dv := Vector2.from_angle(q * TAU / 12.0 - g.t * 0.4)
			cv.draw_line(dv * (r - 10.0), dv * r, Color(1.4, 1.1, 2.2, 0.8 * fade), 2.0)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if o.s_t[1] > 0.0:
		var fade2 := clampf(o.s_t[1] / 1.0, 0.0, 1.0)
		cv.draw_set_transform(bp, 0.0, Vector2(1.0, 0.45))
		cv.draw_arc(Vector2.ZERO, 58.0, 0.0, TAU, 40, Color(0.6, 1.1, 1.8, 0.6 * fade2), 2.0)
		cv.draw_arc(Vector2.ZERO, 66.0, g.t * 3.0, g.t * 3.0 + PI, 24, Color(0.6, 1.1, 1.8, 0.4 * fade2), 3.0)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if o.ammo[0] > 0:
		cv.draw_set_transform(bp, 0.0, Vector2(1.0, 0.45))
		cv.draw_arc(Vector2.ZERO, 34.0 + 3.0 * sin(g.t * 8.0), 0.0, TAU, 32, Color(2.0, 1.5, 0.6, 0.7), 2.0)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i in range(mz.afterimg.size() - 1, -1, -1):
		var ai: Dictionary = mz.afterimg[i]
		var aa: float = 0.45 * (1.0 - float(i) / mz.afterimg.size())
		o.draw_body_at(ai.pos, ai.flip, Color(0.9, 0.55, 1.8, aa), {"tex": ai.tex, "frame": ai.frame, "hf": ai.hf, "flip": ai.flip})
	if o.s_t[2] > 0.0:
		var ma: float = minf(1.0, o.s_t[2] * 3.0) * (0.62 + 0.08 * sin(g.t * 6.0))
		o.draw_body_at(mz.mirror_pos, float(mz.mirror_face) < 0.0, Color(0.85, 0.6, 1.9, ma))


static func _h3_draw_tentacle(o, f: Dictionary) -> void:
	var g = o.g
	var cv = o.cv
	var a: float = 1.0 - f.life / f.max
	cv.draw_set_transform(f.pos + Vector2(0, 10), 0.0, Vector2(1.0, 0.45))
	var gc: Color = h3_deep_col(o, 1.4)
	cv.draw_circle(Vector2.ZERO, 22.0, Color(gc.r, gc.g, gc.b, 0.35 * (1.0 - a)))
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if g.tex.get("fx_tentacle_strike") != null:
		var fr := clampi(int(a * 6.0), 0, 5)
		o.draw_spr("fx_tentacle_strike", 6, fr, f.pos + Vector2(0, 10), g.PX * 1.25, f.flip, h3_deep_col(o, 1.3 if fr == 3 else 1.0), Vector2(0.5, 46.0 / 48.0))
		return
	var fr2 := clampi(int(a * 5.0 / 0.75), 0, 4)
	o.draw_spr("tentacle", 5, fr2, f.pos + Vector2(0, 10), g.PX * 1.7, f.flip, h3_deep_col(o, 1.35) if a < 0.3 else h3_deep_col(o), Vector2(0.5, 1.0))


## 身后常驻的苍白小水母（数量 = 触手追击数）
static func _h3mz_draw_jellies(o) -> void:
	var g = o.g
	var cv = o.cv
	var n: int = int(_h3_st(o, "t_n", 1.0))
	var c: Color = h3_tentacle_col(o)
	var jg = o.B.get("attack", {}).get("look", {}).get("jelly_glow", null)
	var glow: bool = jg is Dictionary and cond_true(o, jg.get("cond", {}))
	for k in n:
		var ang: float = g.t * 0.6 + k * TAU / float(n)
		var ph: float = g.t * 1.3 + k * 2.1
		var p: Vector2 = o.pos + Vector2(cos(ang) * 34.0, -34.0 + sin(ang) * 12.0 + sin(ph * 1.7) * 3.0)
		if _e3_draw_jelly(o, k):   # 精英化第 3 批：离身游猎中的水母
			continue
		if glow:
			cv.draw_circle(p, 13.0, Color(0.9, 0.6, 1.6, 0.16))
		if o._fx_strip("fx_mizuki_jelly", 4, int(g.t * 6.0) + k * 3, p + Vector2(0, 6)):
			continue
		cv.draw_set_transform(p, 0.0, Vector2(1.0, 0.62))
		cv.draw_circle(Vector2.ZERO, 8.5, Color(c.r, c.g, c.b, 0.6))
		cv.draw_arc(Vector2.ZERO, 8.5, PI, TAU, 14, Color(1.7, 1.9, 2.3, 0.9), 1.6)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for q in 3:
			var x0: float = (q - 1) * 4.0
			var pts := PackedVector2Array()
			for s in 5:
				pts.append(p + Vector2(x0 + sin(ph * 2.0 + s * 0.9 + q) * (1.0 + s * 0.9), 3.0 + s * 4.5))
			cv.draw_polyline(pts, Color(c.r, c.g, c.b, 0.65 - q * 0.08), 1.5)


static func _h3mz_draw_over(o) -> void:
	var g = o.g
	var cv = o.cv
	_h3mz_draw_jellies(o)
	if o.s_t[1] > 0.0:
		var fade2 := clampf(o.s_t[1] / 1.0, 0.0, 1.0)
		for q in 10:
			var an = g.t * 2.6 + q * TAU / 10.0
			var p = o.pos + Vector2(cos(an) * 46.0, sin(an) * 20.0 - 26.0)
			var front := sin(an) > 0.0
			o.draw_diamond(p, 4.5 if front else 3.5, Color(0.02, 0.05, 0.08, fade2), Color(0.7, 1.3, 2.0, fade2 * (1.0 if front else 0.5)))
		for j in o.query_ids(o.pos, 320.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or e.stun < 0.15:
				continue
			for q in 3:
				var an2: float = g.t * 4.0 + q * TAU / 3.0 + e.id
				o.draw_diamond(e.pos + Vector2(cos(an2) * (e.r + 6.0), sin(an2) * (e.r + 6.0) * 0.4 - 4.0), 3.0, Color(0.02, 0.05, 0.08, 0.9), Color(0.6, 1.2, 2.0, 0.9))
	if o.s_t[2] > 0.0:
		for q in 6:
			var an = -g.t * 1.4 + q * TAU / 6.0
			var p = o.pos + Vector2(cos(an) * 64.0, sin(an) * 26.0 - 30.0 + sin(g.t * 3.0 + q) * 4.0)
			var w := 5.0 + 3.0 * absf(cos(g.t * 2.0 + q))
			cv.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -12), p + Vector2(w, 0), p + Vector2(0, 12), p + Vector2(-w, 0)]), Color(1.3, 1.0, 2.2, 0.75))
			cv.draw_line(p + Vector2(0, -12), p + Vector2(0, 12), Color(2.5, 2.2, 3.0, 0.9), 1.0)


static func _h3mz_draw_auras(o) -> void:
	var g = o.g
	var cv = o.cv
	if o.s_t[1] > 0.0 and g.tex.get("fx_s2_aura") == null:
		cv.draw_arc(o.pos + Vector2(0, -10), 30.0 + sin(g.t * 6.0) * 2.0, 0.0, TAU, 20, Color(0.5, 0.8, 1.0, 0.6), 2.0)
	if o.s_t[2] > 0.0 and g.tex.get("fx_s3_aura") == null:
		cv.draw_arc(o.pos + Vector2(0, -10), 40.0 + sin(g.t * 4.0) * 3.0, 0.0, TAU, 24, Color(0.8, 0.55, 1.0, 0.7), 3.0)
		cv.draw_circle(o.pos + Vector2(0, -10), 36.0, Color(0.6, 0.4, 1.0, 0.08))


static func _h3mz_draw_add(o, ci, loop: int) -> void:
	var g = o.g
	if o.s_t[1] > 0.0 and g.tex.get("fx_s2_aura") != null:
		o.draw_spr_on(ci, "fx_s2_aura", g.FXF.fx_s2_aura, loop, o.pos + Vector2(0, 4))
	if o.s_t[2] > 0.0 and g.tex.get("fx_s3_aura") != null:
		o.draw_spr_on(ci, "fx_s3_aura", g.FXF.fx_s3_aura, loop, o.pos + Vector2(0, 4))
	var mark := "fx_s2_bind" if o.s_t[1] > 0.0 else "fx_stun"
	if g.tex.get(mark) != null:
		for e in g.enemies:
			if e.stun > 0.3:
				o.draw_spr_on(ci, mark, g.FXF[mark], loop + e.id, e.pos + Vector2(0, -e.r - 10))


static func _h3mz_status(o) -> Array:
	var items: Array = []
	var sk: Array = o.def.get("skills", [])
	if o.ammo[0] > 0:
		items.append(["%s ×%d" % [str(sk[0].get("name", "")), o.ammo[0]], H3_GOLD, -1.0])
	if o.s_t[1] > 0.0:
		items.append([str(sk[1].get("name", "")), Color(0.45, 0.8, 1.0), o.s_t[1] / maxf(0.01, o.s_dur[1])])
	if o.s_t[2] > 0.0:
		items.append([str(sk[2].get("name", "")), Color(0.62, 0.55, 1.0), o.s_t[2] / maxf(0.01, o.s_dur[2])])
	return items


static func _h3mz_rows(o) -> Array:
	var a: Dictionary = o.B.get("attack", {})
	var interval: float = float(a.get("every", 0.9)) * _h3_st(o, "interval", 1.0) / o.stat(&"op_aspd")
	var half: float = minf(180.0, float(a.get("half_deg", 75.0)) + _h3_st(o, "arc", 0.0))
	return [
		["伞击伤害", "%d" % int(o.base(str(a.get("atk_key", "atk")), 0.0) * _h3_st(o, "dmg", 1.0) * o.g.dmg_mult)], ["全局伤害", "×%.2f" % o.g.dmg_mult], ["挥伞间隔", "%.2f 秒" % max(float(a.get("min_cd", 0.18)), interval)],
		["挥砍半径", "%d" % int(float(a.get("r", 142.0)) * _h3_st(o, "area", 1.0))], ["挥砍角度", "%d°" % int(half * 2.0)], ["触手倍率", "×%.2f" % _h3_st(o, "t_mult", 0.6)],
		["追击目标", "%d" % int(_h3_st(o, "t_n", 1.0))], ["技力回复", "×%.2f" % o.g.sp_mult],
	]


# ================================================================ 精英化第 3 批（docs/91 §5 / §8 / §9 / §14、§25；docs/61 §20，10-14）
# 只往后加，建在第 3 批手写迁移段上（o.hw 的 ir / sp / lm / mz）。新积木 / 新参数：
#  trig.on_windup     普攻起手时（第 3 批的普攻形状）执行 do。幽灵鲨精一「卷刃」：起手把外圈敌人吸近（verb.displace，环斩在出手帧）
#  verb.doll_flash    瞬时（trig.every_n 的 do）：替身人偶在 range（× op_range）内敌群最密处从水花里现身 appear 秒 → 旋身斩一圈
#                     （r × op_range，basis × mult，src）→ 碎成泡沫 burst 秒；同时最多 1 个，本体离场（替身跟随）时不出。幽灵鲨精二「替身闪现」
#  shape.thrust 的 stages[k].on_first           第 k 段命中的第一个敌人吃的状态（艾丽妮精一「挑刺」：第 2 段挑起，cd 门）
#  shape.thrust 的 finisher {cond, every, anim, do, volley}  每第 every 次刺击，最后一段换成 do（艾丽妮精二「裂潮余波」：新月斩 + 浮空），
#                     volley {delay, n, mult[], r, src}：收尾 delay 秒后手炮补射这一斩里浮空的至多 n 名
#  shape.cleave 的 aim: thrust（沿这一轮刺击的方向，不转身）、look: crescent
#  shape.lantern 的 bolt.refract {cond, r, mult, src}  光弹打中已被照亮的敌人时折向 r 内最近的未照亮敌人（流明精一「折光」）
#  shape.lantern 的 beam {cond, need, shots, len, w, mult, heal, src}  流明与发光单元每射满 need 发，接下来 shots 发变为直线光柱（流明精二「灯塔光柱」）
#  shape.umbrella 的 tentacle.pull {cond, dist, elite_mult}  触手命中把目标拖向自己（水月精一「拖拽」）
#  shape.umbrella 的 jelly {cond, every, s3, r, speed, back, mult, stun, src}  身后小水母离身游猎蜇刺（水月精二「深蓝之籽」）
# 确定性：本段不取 g.rng（选目标都按距离 / 次序）；画面只用 g.vrng 与 g.t。

const E3_TAGS := ["trig.on_windup", "verb.doll_flash"]
const H3_COLD := Color(0.6, 0.8, 1.05)


## 起手（h3_attack_start 转来）：trig.on_windup
static func _e3_windup(o) -> void:
	for t in o._trigs():
		if str(t.get("_tag", "")) == "trig.on_windup" and cond_true(o, t.get("cond", {})):
			o._exec_list(t.get("do", []), o.pos)


## 当前普攻的判定半径（verb.displace r_in: attack 用；第 3 批的形状按各自的长度 / 半径）
static func h3_attack_r(o, a: Dictionary) -> float:
	match str(a.get("shape", "")):
		"thrust":
			return h3_thrust_len(o, a)
		"saw":
			return h3_saw_r(o, a)
		"umbrella":
			return h3_umb_radius(o, a)
	return shape_radius(o, a)


# ---------------------------------------------------------------- 归溟幽灵鲨：替身闪现

static func h3_doll_flash(o, b: Dictionary) -> void:
	var sp := _h3sp(o)
	if not sp.get("flash", {}).is_empty() or h3_away(o) or o.pos == Vector2.INF:
		return
	var rr: float = float(b.get("range", 300.0)) * o.stat(&"op_range")
	var c: Vector2 = o.densest_point(rr, o.pos)
	if c == Vector2.INF:
		var ts: Array = o.nearest_enemies(1, rr, o.pos)
		if ts.is_empty():
			return
		c = ts[0].pos
	var dmg: float = hw_basis(o, str(b.get("basis", "attack"))) * float(b.get("mult", 0.4))
	sp["flash"] = {"pos": c, "t": 0.0, "dmg": dmg, "hit": false, "b": b, "rev": o.face < 0.0}
	var g = o.g
	if not o.spawn_fx_sprite("fx_water_splash", c + Vector2(0, 4), g.PX, 0.0, false, true):
		o.fx({"kind": "ring", "pos": c, "r": 26.0, "r0": 4.0, "life": 0.3, "col": H3_COLD, "floor": true, "w": 2.0})


static func _e3_flash_tick(o, sp: Dictionary, dt: float) -> void:
	var f: Dictionary = sp.get("flash", {})
	if f.is_empty():
		return
	var g = o.g
	var b: Dictionary = f.b
	f.t = float(f.t) + dt
	var ap: float = float(b.get("appear", 0.25))
	var sw: float = float(b.get("spin", 0.3))
	var spins: int = int(b.get("spins", 1))
	var gap: float = float(b.get("spin_gap", 0.15))
	while int(f.get("n_hit", 0)) < spins and float(f.t) >= ap + float(b.get("hit_at", 0.08)) + int(f.get("n_hit", 0)) * gap:   # 连斩 spins 圈，每圈间隔 spin_gap 秒
		var k: int = int(f.get("n_hit", 0))
		f["n_hit"] = k + 1
		var rev: bool = f.rev != (k % 2 == 1)   # 每圈换个转向
		var r: float = float(b.get("r", 100.0)) * o.stat(&"op_range")
		var c: Vector2 = f.pos
		var src: String = str(b.get("src", ""))
		for e in o.arc_targets(c + Vector2(0, -10), 0.0, PI, r):
			o.log_hit(src, b.get("tags", []))
			o.deal_damage(e, float(f.dmg))
			o.fx({"kind": "glow", "pos": e.pos + Vector2(0, -e.r * 0.5), "r": 8.0, "life": 0.15, "col": H3_COLD, "alpha": 0.5})
		var sc: float = r / 34.0
		var ok_b: bool = o.spawn_fx_sprite(str(b.get("saw_back", "fx_specter_saw_cold_back")), c + Vector2(0, -6), sc, 0.0, rev)
		var ok_f: bool = o.spawn_fx_sprite(str(b.get("saw_front", "fx_specter_saw_cold_front")), c + Vector2(0, -6), sc, 0.0, rev)
		if not (ok_b or ok_f):
			o.fx({"kind": "h3_saw", "pos": c + Vector2(0, -8), "r": r, "life": 0.24, "col": H3_COLD, "spin": (-1.0 if rev else 1.0) * 34.0, "tooth": 5.0, "ang": g.vrng.randf() * TAU})
		_h3_sfx(o, "atk", -3.0, 1.2 + 0.08 * k, 0.06)
	if float(f.t) >= ap + sw + float(b.get("burst", 0.3)):
		sp.flash = {}


static func _e3_flash_draw(o) -> void:
	var g = o.g
	var cv = o.cv
	var f: Dictionary = o.hw.sp.get("flash", {})
	if f.is_empty():
		return
	var b: Dictionary = f.b
	var ap: float = float(b.get("appear", 0.25))
	var sw: float = float(b.get("spin", 0.3))
	var bu: float = float(b.get("burst", 0.3))
	var t: float = float(f.t)
	var p: Vector2 = f.pos
	var mid := p + Vector2(0, -16.0 * g.PX)
	if t < ap:
		var k: float = t / ap
		var nm: String = str(b.get("appear_fx", "fx_specter_doll_appear"))
		if g.tex.get(nm) != null:
			fx_frame(cv, g, nm, 5, mini(int(k * 5.0), 4), mid, g.PX, Color.WHITE)
		else:
			_e3_doll_body(o, p, f.rev, Color(0.85, 0.92, 1.1, k), 0)
		return
	if t < ap + sw:
		var spins: int = maxi(1, int(b.get("spins", 1)))
		var ksp: float = fmod((t - ap) / sw * spins, 1.0)   # 旋身帧条每圈播一遍
		var tx: Texture2D = o.anim_tex(str(b.get("anim", "doll_spin")))
		if tx != null:
			var n: int = o.anim_hframes(tx, str(b.get("anim", "doll_spin")))
			o.draw_sprite_at(p, f.rev, Color(0.92, 0.96, 1.1), clampi(int(ksp * n), 0, n - 1), tx, n, o.foot_off(tx, str(b.get("anim", "doll_spin"))))
		else:
			_e3_doll_body(o, p, f.rev, Color(0.92, 0.96, 1.1), int(ksp * 4.0))
		return
	var kb: float = clampf((t - ap - sw) / bu, 0.0, 1.0)
	var nb: String = str(b.get("burst_fx", "fx_specter_doll_burst"))
	if g.tex.get(nb) != null:
		fx_frame(cv, g, nb, 6, mini(int(kb * 6.0), 5), mid, g.PX, Color.WHITE)
	else:
		_e3_doll_body(o, p, f.rev, Color(0.85, 0.92, 1.1, 1.0 - kb), 0)
		for q in 7:
			var an: float = q * TAU / 7.0 + p.x * 0.01
			cv.draw_circle(mid + Vector2(cos(an), sin(an) * 0.6) * (6.0 + 22.0 * kb) + Vector2(0, -14.0 * kb), 2.5 * (1.0 - kb) + 1.0, Color(0.8, 0.92, 1.2, 0.8 * (1.0 - kb)))


static func _e3_doll_body(o, p: Vector2, flip: bool, col: Color, fr: int) -> void:
	var tx: Texture2D = o.anim_tex("doll")
	if tx == null:
		o.cv.draw_circle(p + Vector2(0, -20), 12.0, Color(H3_GHOST.r, H3_GHOST.g, H3_GHOST.b, col.a))
		return
	var n: int = o.anim_hframes(tx, "doll")
	o.draw_sprite_at(p, flip, col, fr % n, tx, n, o.foot_off(tx, "doll"))


# ---------------------------------------------------------------- 艾丽妮：挑刺 / 裂潮余波

## 这一刺（出手帧）是不是收尾换斩的那一轮
static func _e3_fin_arm(o, a: Dictionary) -> void:
	var ir: Dictionary = o.hw.ir
	var fn = a.get("finisher", null)
	ir["fin"] = fn is Dictionary and cond_true(o, fn.get("cond", {})) and (int(o.atk_n) + 1) % maxi(1, int(fn.get("every", 3))) == 0


static func _e3_finisher(o, a: Dictionary) -> void:
	var ir: Dictionary = o.hw.ir
	var fn: Dictionary = a.finisher
	ir["fin_t"] = 0.0
	ir["fin_anim"] = str(fn.get("anim", ""))
	ir["last_hits"] = []
	o._exec_list(fn.get("do", []))
	var vl = fn.get("volley", null)
	if vl is Dictionary:
		ir["volley"] = {"t": float(vl.get("delay", 0.15)), "b": vl}


static func _e3_ir_tick(o, ir: Dictionary, dt: float) -> void:
	if ir.has("fin_t"):
		ir.fin_t = float(ir.fin_t) + dt
	var vo: Dictionary = ir.get("volley", {})
	if vo.is_empty():
		return
	vo.t = float(vo.t) - dt
	if float(vo.t) > 0.0:
		return
	ir.volley = {}
	var b: Dictionary = vo.b
	var n := 0
	for e in ir.get("last_hits", []):
		if n >= int(b.get("n", 2)):
			break
		if e.dead or not _h3_is_air(o, e):
			continue
		n += 1
		var cb: Dictionary = b.duplicate()
		if not cb.has("muzzle"):
			cb["muzzle"] = "fx_irene_gun_burst"
		_h3_cannon(o, cb, e.pos, hw_mul(o.base(str(b.get("atk_key", "atk")), 0.0), b.get("mult", 1.0)) * o._dmg_bonus())


## 收尾动作帧条（anim_state 转来）
static func e3_ir_anim(o, st: Dictionary) -> Dictionary:
	var ir: Dictionary = o.hw.ir
	var an: String = str(ir.get("fin_anim", ""))
	if an == "" or not ir.has("fin_t"):
		return st
	var tx: Texture2D = o.anim_tex(an)
	if tx == null:
		return st
	var spec: Dictionary = o.sprite_spec(an)
	var n: int = o.anim_hframes(tx, an)
	var fps: float = float(spec.get("fps", 14))
	var fire: float = float(spec.get("fire", 2))
	var fr: int = int(float(ir.fin_t) * fps + fire)   # 斩出帧对准收尾那一刻
	if fr >= n:
		return st
	return {"tex": tx, "frame": clampi(fr, 0, n - 1), "hf": n, "flip": (o.face < 0.0) != o.sprite_mirror(an), "kind": an}


static func _e3_crescent_fx(o, b: Dictionary, ang: float, r: float) -> void:
	var g = o.g
	var dir := Vector2.from_angle(ang)
	if not o.spawn_fx_sprite(str(b.get("strip", "fx_irene_crescent_wide")), o.pos + Vector2(0, -14) + dir * r * 0.5, r / 58.0, ang, false, false, Color.WHITE):
		o.slash_fx(o.pos + Vector2(0, -14), ang, float(b.get("half", 0.785)), r, Color(0.7, 0.95, 1.1), "slash", 0.26)
	_h3_vsparks(o, o.pos + dir * r * 0.55, Color(0.8, 0.95, 1.1), 8, 200.0, 0.35, 2.5, 160.0)
	_h3_sfx(o, "atk", 3.0, 0.9)


# ---------------------------------------------------------------- 流明：折光 / 灯塔光柱

## 光弹命中已被照亮的敌人（was_lit）：折向 r 内最近的未照亮敌人
static func _e3_refract(o, bt: Dictionary, e: Dictionary, dmg: float) -> void:
	var rf = bt.get("refract", null)
	if not (rf is Dictionary) or not cond_true(o, rf.get("cond", {})):
		return
	var g = o.g
	var r: float = float(rf.get("r", 120.0))
	var best := {}
	var bd := INF
	for j in o.query_ids(e.pos, r + 20.0):
		var q: Dictionary = g.enemies[j]
		if q.dead or is_same(q, e) or float(q.get("lit", 0.0)) > 0.0:
			continue
		var d: float = q.pos.distance_to(e.pos)
		if d <= r and d < bd:
			bd = d
			best = q
	if best.is_empty():
		return
	o.log_hit(str(rf.get("src", "")))
	o.deal_damage(best, dmg * float(rf.get("mult", 0.25)))
	best["lit"] = float(bt.get("lit", 3.0))
	var a: Vector2 = e.pos + Vector2(0, -e.r * 0.5)
	var b: Vector2 = best.pos + Vector2(0, -best.r * 0.5)
	o.fx({"kind": "line", "pos": a, "to": b, "life": 0.12, "col": Color(1.6, 1.45, 1.0), "w": 1.0})
	if not o.spawn_fx_sprite(str(rf.get("hit", "fx_lumen_refract_hit")), b, g.PX):
		o.spawn_fx_sprite("fx_holy_impact_lantern", b, g.PX * 0.5)


## 一发（流明本人 / 发光单元）：光柱攒满时这一发变光柱，返回 true（不再射光弹）；否则计数
static func _e3_beam_shot(o, lm: Dictionary, from: Vector2, to_pt: Vector2, dmg: float) -> bool:
	var bm = o.B.get("attack", {}).get("beam", null)
	if not (bm is Dictionary) or not cond_true(o, bm.get("cond", {})):
		return false
	if int(lm.empowered) > 0:
		lm.empowered = int(lm.empowered) - 1
		_e3_beam_fire(o, bm, from, (to_pt - o.pos).normalized(), dmg)
		return true
	lm.charge_n = int(lm.charge_n) + 1
	if int(lm.charge_n) >= int(bm.get("need", 8)):
		lm.charge_n = 0
		lm.empowered = int(bm.get("shots", 8))
		o.fx({"kind": "ring", "pos": o.pos + Vector2(0, -94), "r": 22.0, "r0": 4.0, "life": 0.4, "col": H3_WARM, "keep": true})
		_h3_vsparks(o, o.pos + Vector2(0, -94), H3_WARM, 8, 120.0, 0.4, 2.0)
	return false


static func _e3_beam_fire(o, bm: Dictionary, from: Vector2, d: Vector2, dmg: float) -> void:
	var g = o.g
	var L: float = float(bm.get("len", 200.0)) * o.stat(&"op_range")
	var W: float = float(bm.get("w", 10.0))
	var org: Vector2 = o.pos   # 判定贴地：从脚底朝目标脚底；画面从出光点（提灯 / 发光单元的高度）平行打出
	var hits: Array = []
	for j in o.query_ids(org + d * L * 0.5, L * 0.6 + 40.0):
		var e: Dictionary = g.enemies[j]
		if e.dead:
			continue
		var rel: Vector2 = e.pos - org
		var along: float = rel.dot(d)
		if along < -e.r or along > L + e.r or absf(rel.cross(d)) > W * 0.5 + e.r:
			continue
		hits.append([along, e])
	hits.sort_custom(func(x, y): return x[0] < y[0])
	var src: String = str(bm.get("src", ""))
	var bd: float = dmg * float(bm.get("mult", 1.4))
	for hh in hits:
		var e: Dictionary = hh[1]
		o.log_hit(src)
		o.deal_damage(e, bd)
		e["lit"] = 3.0
		if not o.spawn_fx_sprite(str(bm.get("hit", "fx_lumen_beam_hit")), e.pos + Vector2(0, -e.r * 0.5), g.PX):
			o.fx({"kind": "glow", "pos": e.pos + Vector2(0, -e.r * 0.5), "r": 10.0, "life": 0.18, "col": Color(1.6, 1.5, 1.2), "alpha": 0.7})
	if g.hp < g.max_hp and float(bm.get("heal", 0.0)) > 0.0:
		o.heal_leader(g.max_hp * float(bm.heal), o.display_name(), str(bm.get("heal_sub", "")))
	o.fx({"kind": "h3_beam", "pos": from, "dir": d, "len": L, "w": W, "life": 0.2, "tile": str(bm.get("tile", "fx_lumen_beam"))})
	if not o.spawn_fx_sprite(str(bm.get("flare", "fx_lumen_beam_flare")), from, g.PX):
		o.fx({"kind": "glow", "pos": from, "r": 14.0, "life": 0.2, "col": Color(1.6, 1.4, 0.9), "alpha": 0.7})
	_h3_sfx(o, "atk", 2.0, 1.25, 0.05)


static func _e3_draw_beam(o, f: Dictionary, a: float) -> void:
	var g = o.g
	var cv = o.cv
	var p0: Vector2 = f.pos
	var p1: Vector2 = p0 + (f.dir as Vector2) * float(f.len)
	var tn: String = str(f.get("tile", "fx_lumen_beam"))
	if g.tex.get(tn) != null and g.V6_FRAMES.has(tn):
		var nfr: int = int(g.V6_FRAMES[tn][0])
		_hw_draw_tiled(o, tn, p0, p1, g.PX, 0.0, 0, Color(1, 1, 1, clampf(a * 1.4, 0.0, 1.0)), mini(int((1.0 - a) * nfr), nfr - 1))
		return
	var w: float = float(f.get("w", 10.0)) * (0.35 + 0.65 * a)
	cv.draw_line(p0, p1, Color(1.0, 0.85, 0.5, 0.55 * a), w)
	cv.draw_line(p0, p1, Color(2.0, 1.9, 1.6, 0.9 * a), maxf(1.0, w * 0.35))
	cv.draw_circle(p0, 6.0 + 6.0 * a, Color(1.5, 1.3, 0.8, 0.5 * a))


# ---------------------------------------------------------------- 水月：拖拽 / 深蓝之籽

static func _e3_pull(o, a: Dictionary, target: Dictionary) -> void:
	var pl = a.get("tentacle", {}).get("pull", null)
	if not (pl is Dictionary) or target.dead or not cond_true(o, pl.get("cond", {})):
		return
	if displace_one(o, target, o.pos, pl):
		o.spawn_fx_sprite(str(pl.get("fx", "fx_mizuki_tentacle_curl")), target.pos + Vector2(0, -target.r * 0.5), o.g.PX, 0.0, target.pos.x > o.pos.x)


## 第 k 只水母在身后的位置（同常驻画法）
static func _e3_jelly_home(o, k: int, n: int) -> Vector2:
	var g = o.g
	var ang: float = g.t * 0.6 + k * TAU / float(maxi(1, n))
	var ph: float = g.t * 1.3 + k * 2.1
	return o.pos + Vector2(cos(ang) * 34.0, -34.0 + sin(ang) * 12.0 + sin(ph * 1.7) * 3.0)


static func _e3_jelly_on(o) -> Dictionary:
	var jb = o.B.get("attack", {}).get("jelly", null)
	if jb is Dictionary and cond_true(o, jb.get("cond", {})):
		return jb
	return {}


static func _e3_jelly_tick(o, mz: Dictionary, dt: float) -> void:
	var jb := _e3_jelly_on(o)
	if not mz.has("jel"):
		mz["jel"] = []
		mz["marks"] = {}
		mz["binds"] = []
	if jb.is_empty() or o.pos == Vector2.INF:
		mz.jel = []
		return
	var g = o.g
	var n: int = int(_h3_st(o, "t_n", 1.0))
	while mz.jel.size() < n:
		var k0: int = mz.jel.size()
		mz.jel.append({"ph": "home", "cd": 0.3 * k0, "p": _e3_jelly_home(o, k0, n), "v": Vector2.ZERO, "tgt": {}, "t": 0.0})
	while mz.jel.size() > n:
		mz.jel.pop_back()
	var rr: float = float(jb.get("r", 200.0)) * o.stat(&"op_range")
	var every: float = float(jb.get("every", 1.2))
	for m in jb.get("every_mults", []):
		if cond_true(o, m.get("cond", {})):
			every *= float(m.get("mult", 1.0))
	for k in n:
		var j: Dictionary = mz.jel[k]
		var home: Vector2 = _e3_jelly_home(o, k, n)
		match str(j.ph):
			"home":
				j.p = home
				j.cd = float(j.cd) - dt
				if float(j.cd) <= 0.0:
					var tgt := _e3_jelly_pick(o, mz, rr, k)
					if tgt.is_empty():
						j.cd = 0.25
					else:
						j.ph = "out"
						j.tgt = tgt
						j.t = 0.0
			"out":
				j.t = float(j.t) + dt
				var e: Dictionary = j.tgt
				if e.dead or float(j.t) > float(jb.get("max_t", 1.0)):
					j.ph = "back"
					continue
				var to: Vector2 = e.pos + Vector2(0, -float(e.r) * 0.5)
				var dv: Vector2 = to - (j.p as Vector2)
				var step: float = float(jb.get("speed", 420.0)) * dt
				if dv.length() <= step + float(e.r) * 0.5 + 4.0:
					j.p = to
					_e3_sting(o, jb, e)
					j.ph = "back"
				else:
					j.v = dv.normalized() * float(jb.get("speed", 420.0))
					j.p = (j.p as Vector2) + dv.normalized() * step
			"back":
				var dv2: Vector2 = home - (j.p as Vector2)
				var st2: float = float(jb.get("back", 160.0)) * dt
				if dv2.length() <= st2 + 2.0:
					j.p = home
					j.ph = "home"
					j.cd = every
				else:
					j.v = dv2.normalized() * float(jb.get("back", 160.0))
					j.p = (j.p as Vector2) + dv2.normalized() * st2
	for bd in mz.binds:
		bd.t = float(bd.t) - dt
	mz.binds = mz.binds.filter(func(x): return float(x.t) > 0.0 and not x.e.dead)


## 选目标：r 内、别的水母没盯上的；最近被触手打过的优先，其次最近的
static func _e3_jelly_pick(o, mz: Dictionary, rr: float, k: int) -> Dictionary:
	var g = o.g
	var taken := {}
	for q in mz.jel.size():
		var jq: Dictionary = mz.jel[q]
		if q != k and str(jq.ph) == "out" and not jq.tgt.is_empty():
			taken[int(jq.tgt.id)] = true
	var first := {}
	for e in o.nearest_enemies(10, rr, o.pos):
		if e.dead or taken.has(int(e.id)):
			continue
		if float(mz.marks.get(int(e.id), -99.0)) > float(g.t) - 3.0:
			return e
		if first.is_empty():
			first = e
	return first


static func _e3_sting(o, jb: Dictionary, e: Dictionary) -> void:
	var g = o.g
	var mz: Dictionary = o.hw.mz
	var a: Dictionary = o.B.get("attack", {})
	var dmg: float = o.base(str(a.get("atk_key", "atk")), 0.0) * _h3_st(o, "dmg", 1.0) * o._dmg_bonus()
	for m in a.get("dmg_mults", []):
		if cond_true(o, m.get("cond", {})):
			dmg *= float(m.get("mult", 1.0))
	o.log_hit(str(jb.get("src", "")))
	o.deal_damage(e, dmg * float(jb.get("mult", 0.4)))
	if not e.dead and not e.boss:
		var sd: float = float(jb.get("stun", 0.3)) * (0.5 if e.elite else 1.0)
		e.stun = maxf(e.stun, sd)
		mz.binds.append({"e": e, "t": sd})
	if not o.spawn_fx_sprite(str(jb.get("sting_fx", "fx_mizuki_jelly_sting")), e.pos + Vector2(0, -e.r * 0.5), g.PX):
		o.fx({"kind": "glow", "pos": e.pos + Vector2(0, -e.r * 0.5), "r": 10.0, "life": 0.2, "col": Color(0.9, 0.6, 1.6), "alpha": 0.6})


static func _e3_mark(o, e: Dictionary) -> void:
	var mz: Dictionary = o.hw.mz
	if not mz.has("marks") or _e3_jelly_on(o).is_empty():
		return
	mz.marks[int(e.id)] = float(o.g.t)
	if mz.marks.size() > 64:
		for kk in mz.marks.keys():
			if float(mz.marks[kk]) < float(o.g.t) - 3.0:
				mz.marks.erase(kk)


## 水母画法（_h3mz_draw_jellies 转来）：在外的画拉长的水滴形 + 淡紫细尾；返回 true = 已画
static func _e3_draw_jelly(o, k: int) -> bool:
	var mz: Dictionary = o.hw.mz
	if not mz.has("jel") or k >= mz.jel.size():
		return false
	var j: Dictionary = mz.jel[k]
	if str(j.ph) == "home":
		return false
	var g = o.g
	var cv = o.cv
	var p: Vector2 = j.p
	var v: Vector2 = j.v
	var ang: float = v.angle() if v.length() > 1.0 else 0.0
	cv.draw_line(p - v.normalized() * 14.0, p, Color(0.9, 0.65, 1.5, 0.45), 2.0)
	if g.tex.get("fx_mizuki_jelly_dart") != null:
		fx_frame(cv, g, "fx_mizuki_jelly_dart", 6, int(g.t * 14.0 + k * 2) % 6, p, g.PX, Color.WHITE, Vector2(-1, -1), ang)
		return true
	return false


static func _e3_draw_binds(o) -> void:
	var mz: Dictionary = o.hw.mz
	if not mz.has("binds"):
		return
	var g = o.g
	var cv = o.cv
	for bd in mz.binds:
		var e: Dictionary = bd.e
		var bp: Vector2 = e.pos + Vector2(0, float(e.r) * 0.6)
		if g.tex.get("fx_mizuki_bind_ring") != null:
			fx_frame(cv, g, "fx_mizuki_bind_ring", 6, int(g.t * 10.0) % 6, bp, g.PX * clampf(float(e.r) / 10.0, 1.0, 2.0), Color(1, 1, 1, 0.9))
		else:
			cv.draw_set_transform(bp, 0.0, Vector2(1.0, 0.45))
			cv.draw_arc(Vector2.ZERO, float(e.r) + 4.0, 0.0, TAU, 20, Color(0.9, 0.65, 1.5, 0.8), 2.0)
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---------------------------------------------------------------- 本段的校验

static func _e3_block(b: Dictionary, p: String, kind: String, ctx: Dictionary, tag: String) -> bool:
	if not tag in E3_TAGS:
		return false
	var errs: Array = ctx.errs
	var where_ok := {"trig.on_windup": ["trig"], "verb.doll_flash": ["skill", "instant"]}
	if not kind in where_ok[tag]:
		errs.append("%s：「%s」不能放在这里（%s；只能在 %s）" % [p, tag, kind, " / ".join(where_ok[tag])])
		return true
	match tag:
		"trig.on_windup":
			_list(b.get("do", []), p + ".do", "instant", ctx)
		"verb.doll_flash":
			_num(b, "range", p, ctx, true, 10.0, 1000.0)
			_num(b, "r", p, ctx, true, 1.0, 400.0)
			_num(b, "mult", p, ctx, true, 0.0, 10.0)
			for k in ["appear", "spin", "burst", "spin_gap"]:
				_num(b, k, p, ctx, false, 0.0, 3.0)
			_num(b, "spins", p, ctx, false, 1.0, 6.0)
			if b.has("basis") and not str(b.basis) in ["attack", "prev", "hit", "atk"]:
				errs.append(p + ".basis 只能是 attack / prev / hit / atk")
			if b.has("anim") and not (ctx.sprites is Dictionary and ctx.sprites.has(str(b.anim))):
				errs.append("%s.anim「%s」不是 sprites 里的帧条键" % [p, str(b.anim)])
			_src(b, p, ctx, true)
	return true


# ================================================================ 手写迁移段（第 4 批：推进之王 / 铃兰 / 维什戴尔 / 塞雷娅，docs/91 §19 批 4；docs/61 §21）
# 只往后加，建在手写迁移段上（o.hw 状态、hw_tick / hw_exec / hw_draw_* 挂钩），前缀 h4_ / _h4。各人一个子字典：
#   sg（锤击 / 跃空锤 / 号令波 / 地裂）、sz（狐火 / 光域 / 大狐火 / 金印）、wd（炮弹 / 余震 / 残影 / 标记 / 魂灵之影）、sa（拳击 / 阻挡圈 / 钙晶 / 投射物 / 护服 / 钙质化）。
# 确定性：玩法随机只在手写版也取 g.rng 的地方取（推进之王碎颅的 50% 眩晕、塞雷娅钙质化晶柱的落点与碎晶挑哪根），次数与顺序同手写；画面一律 g.vrng。
# 常驻的「系统积木」（光域、阻挡圈、钙晶、魂灵之影……）写在 trait / talent / 成长节点的 passive do 里，每帧按 _h4_live 现查（不缓存，精英化 / 选节点当帧生效，同手写）。
#
# 推进之王段（SG_TAGS）：
#  shape.hammer     扇形锤击（普攻）：半径 r × op_range、半角 half、kb、判定原点 脚底 + (0, y)；次数型补丁（dur.next_n 的 attack_patch：mult / power）乘在这一锤上；
#                   heavy {cond, mult, power, interval, stun_chance, stun, anim}：cond 成立时（碎颅）每一锤 × mult [× 技能强度]、间隔 × interval、用 anim 帧条起手（出手走技能出手帧）、
#                   命中的非 Boss 敌人 stun_chance 概率（g.rng，同手写）眩晕 stun 秒（精英减半）；hit_sp + hit_sp_mults：命中时其他干员技力 + 秒数（第一条 cond 成立的倍率）；
#                   quake {cond, r, mult, src, roar {cond, r_mult, kb}}：落点一圈贴地冲击环；breach {cond, len, w, mult, life, max, src}：沿锤击方向的直线地裂
#  verb.leap_slam   跃空锤：朝 aim_r 内最近的敌人跃过去（至多 dist，落在它面前 24 处），t 秒、高 h 的空中翻转，落地 r × op_range 内 × mult × 技能强度、kb、stun，
#                   其他干员技力 + sp × 技能强度；again {cond, range, dist, mult, near}：落地后再跃向身边敌人最密处砸第二下（× mult，不回技力）
#  verb.cmd_wave    号令波：以自身为心向外扩张到 r（dur 秒，先快后慢），扫到的敌人 × mult × 技能强度、非精英击退 kb；同时至多 max 道
#  verb.sp_team 的 power / motes（第 4 批追加）：技力 × 技能强度；金色技力粒子飞向每名队友

const H4_TAGS := ["shape.hammer", "verb.leap_slam", "verb.cmd_wave",
	"shape.foxfire", "verb.foxlight", "verb.fox_cast",
	"shape.cannon", "verb.cannon_exec", "verb.cannon_load", "verb.souls",
	"shape.bash", "verb.guard_ring", "verb.calc_orbs", "verb.saria_heal", "verb.calc_field", "verb.suit"]
const H4_ATTACKS := ["hammer", "foxfire", "cannon", "bash"]   # 第 4 批的普攻形状（起手 / 出手由本段接管）
const SG_TAGS := ["shape.hammer", "verb.leap_slam", "verb.cmd_wave"]
const SZ_TAGS := ["shape.foxfire", "verb.foxlight", "verb.fox_cast"]
const WD_TAGS := ["shape.cannon", "verb.cannon_exec", "verb.cannon_load", "verb.souls"]
const SA_TAGS := ["shape.bash", "verb.guard_ring", "verb.calc_orbs", "verb.saria_heal", "verb.calc_field", "verb.suit"]
const H4_GOLD := Color(1.0, 0.78, 0.35)
const H4_FLAME := Color(1.0, 0.55, 0.15)
const H4_FOX := Color(1.0, 0.82, 0.45)
const H4_RED := Color(0.95, 0.22, 0.2)
const H4_BOLT := Color(0.9, 0.08, 0.1)
const H4_EMBER := Color(1.0, 0.55, 0.3)
const H4_DARK := Color(0.1, 0.06, 0.08)
const H4_AMBER := Color(1.0, 0.72, 0.38)


static func h4_on(o) -> bool:
	return hw_on(o) and (o.hw.has("sg") or o.hw.has("sz") or o.hw.has("wd") or o.hw.has("sa"))


## hw_init 转来：本段的状态一开始就建好
static func h4_init(o, tags: Dictionary) -> void:
	for t in tags:
		if t in SG_TAGS:
			_h4sg(o)
		elif t in SZ_TAGS:
			_h4sz(o)
		elif t in WD_TAGS:
			_h4wd(o)
		elif t in SA_TAGS:
			_h4sa(o)


## 本帧生效的某块积木（trait → talent → 已选节点 → elite1 / elite2；passive 的 do 里找，各自的 cond 都成立）；没有 = {}
static func _h4_live(o, tag: String) -> Dictionary:
	for t in o._trigs():
		if not cond_true(o, t.get("cond", {})):
			continue
		var tg: String = str(t.get("_tag", ""))
		if tg == tag:
			return t
		if tg == "trig.passive":
			for b in t.get("do", []):
				if str(b.get("_tag", "")) == tag and cond_true(o, b.get("cond", {})):
					return b
	return {}


## 条件成立的第一条 [{cond, mult}] 的倍率；没有 = 1.0
static func _h4_first_mult(o, arr, key := "mult") -> float:
	if arr is Array:
		for m in arr:
			if m is Dictionary and cond_true(o, m.get("cond", {})):
				return float(m.get(key, 1.0))
	return 1.0


## 子参数块 {cond, …} 成立时返回它，否则 {}
static func _h4_sub(o, v) -> Dictionary:
	if v is Dictionary and not v.is_empty() and cond_true(o, v.get("cond", {})):
		return v
	return {}


## 次数型技能的补丁（dur.next_n 的 attack_patch）：先到先用，用掉一次
static func _h4_take_patch(o) -> Dictionary:
	var sk: Array = o.B.get("skills", [])
	for i in 3:
		if o.ammo[i] > 0 and i < sk.size():
			o.ammo[i] -= 1
			return sk[i].get("attack_patch", {})
	return {}


static func _h4_patch_pending(o) -> bool:
	return o.ammo[0] > 0 or o.ammo[1] > 0 or o.ammo[2] > 0


## 普攻起手（data_operator.update：技能判定之后）
static func h4_attack_start(o, a: Dictionary, _dt: float) -> void:
	match str(a.get("shape", "")):
		"hammer":
			_h4_hammer_start(o, a)
		"foxfire":
			_h4_fox_start(o, a)
		"cannon":
			_h4_cannon_start(o, a)
		"bash":
			_h4_bash_start(o, a)


## 普攻出手（data_operator._release）；音效由各形状自己播（同手写）
static func h4_attack_fire(o, a: Dictionary) -> void:
	match str(a.get("shape", "")):
		"hammer":
			_h4_hammer_release(o, a)
		"foxfire":
			_h4_fox_release(o, a)
		"cannon":
			_h4_cannon_release(o, a)
		"bash":
			_h4_bash_release(o, a)


## data_operator._release_skill 开头：碎颅期间用技能动作起手的那一锤（出手走技能出手帧）。返回 true = 已处理
static func h4_release_skill(o) -> bool:
	if not o.hw.has("sg") or not o.hw.sg.heavy_swing:
		return false
	o.hw.sg.heavy_swing = false
	o._release()
	return true


## 每帧（hw_tick 转来，手写 update 的先后）。返回 true = 本帧不起手（跃空锤在空中）
static func h4_tick(o, dt: float) -> bool:
	var h: Dictionary = o.hw
	if h.has("sg"):
		return _h4sg_tick(o, h.sg, dt)
	if h.has("sz"):
		_h4sz_tick(o, h.sz, dt)
	if h.has("wd"):
		_h4wd_tick(o, h.wd, dt)
	if h.has("sa"):
		_h4sa_tick(o, h.sa, dt)
	return false


## hw_exec 转来
static func h4_exec(o, b: Dictionary, _at: Vector2) -> void:
	match str(b.get("_tag", "")):
		"verb.leap_slam":
			h4_leap(o, b)
		"verb.cmd_wave":
			h4_cmd_wave(o, b)
		"verb.fox_cast":
			h4_fox_cast(o, b)
		"verb.cannon_exec":
			h4_cannon_exec(o, b)
		"verb.cannon_load":
			h4_cannon_load(o, b)
		"verb.saria_heal":
			h4_saria_heal(o, b)
		"verb.calc_field":
			h4_calc_start(o, b)


## 技能剩余（hw_active_left 转来）：铃兰狐火迷雾 / 维什戴尔巨炮发数 / 塞雷娅钙质化按本段的计时；-1 = 本段不管
static func h4_active_left(o, i: int) -> float:
	var h: Dictionary = o.hw
	if i != 2:
		return -1.0
	if h.has("sz"):
		return float(h.sz.haze_t)
	if h.has("wd"):
		return float(h.wd.ammo)
	if h.has("sa"):
		return float(h.sa.calc)
	return -1.0


## 起手朝向（mf_skill_aim 转来）：elite = 精英 / Boss 优先（血最多）；cluster = 离队长最近、相仿时挑落点最密
static func h4_skill_aim(o, i: int, aim: String) -> Vector2:
	var sk: Array = o.B.get("skills", [])
	var a: Dictionary = o.B.get("attack", {})
	var reach: float = _h4_wd_reach(o, a, float(sk[i].get("aim_r", 520.0)))
	var tg: Dictionary = _h4_exec_target(o, a, reach) if aim == "elite" else _h4_wd_target(o, a, reach)
	return tg.pos if not tg.is_empty() else Vector2.INF


## 击杀（data_operator.on_kill 转来）：维什戴尔带残影标记的敌人殉爆
static func h4_on_kill(o, e: Dictionary) -> void:
	if o.hw.has("wd"):
		_h4wd_on_kill(o, e)


## 受击询问（data_operator.dmg_taken_mult 转来）：verb.dr 按本刻生效的积木现算（精英化当帧就生效，同手写；不等下一帧 _sustain）
static func h4_live_dr(o) -> float:
	var dr := 1.0
	for t in o._trigs():
		if not cond_true(o, t.get("cond", {})) or str(t.get("_tag", "")) != "trig.passive":
			continue
		for b in t.get("do", []):
			if str(b.get("_tag", "")) == "verb.dr" and cond_true(o, b.get("cond", {})):
				dr *= 1.0 - float(b.value)
	return dr


## 离队：铃兰给队友的攻击加成一并撤掉（手写版不撤，这里顺手修）
static func h4_leave(o) -> void:
	if hw_on(o) and o.hw.has("sz"):
		o.g.stats.remove_source(_h4_field_src(o))


## 状态条（hw_status_items 转来）
static func h4_status_items(o) -> Array:
	var out: Array = []
	if o.hw.has("wd") and int(o.hw.wd.ammo) > 0:
		out.append([str(o.hw.wd.get("status", "×%d")) % int(o.hw.wd.ammo), Color(1.0, 0.55, 0.45)])
	if o.hw.has("sa"):
		var sa: Dictionary = o.hw.sa
		if float(sa.hot_t) > 0.0:
			out.append([str(sa.get("hot_name", "")), H4_AMBER])
		if float(sa.calc) > 0.0:
			out.append([str(sa.get("calc_name", "")), H4_AMBER])
		var su: Dictionary = _h4_live(o, "verb.suit")
		if not su.is_empty():
			var segs: int = int(su.get("segs", 4))
			out.append([str(su.get("name", "")) + " %d/%d" % [int(sa.seg), segs], H4_AMBER, float(sa.seg) / float(segs)])
	return out


# ---------------------------------------------------------------- 推进之王：锤击

static func _h4sg(o) -> Dictionary:
	var h := hw_st(o)
	if not h.has("sg"):
		h["sg"] = {"leap_t": -1.0, "leap_pos": Vector2.ZERO, "leap_to": Vector2.ZERO, "leap_n": 0, "leap_second": false, "leap_b": {},
			"heavy_swing": false, "waves": [], "fissures": [], "spikes": []}
	return h.sg


static func _h4_heavy(o, a: Dictionary) -> Dictionary:
	return _h4_sub(o, a.get("heavy", null))


static func _h4_hammer_start(o, a: Dictionary) -> void:
	if o.cd > 0.0:
		return
	var reach: float = float(a.get("r", 108.0)) * o.stat(&"op_range")
	var at: Vector2 = o.atk_point(o.nearest_enemies(1, reach + 30.0, o.pos), reach)   # 手动普攻 A 类（契约 v2.5）
	if at == Vector2.INF:
		o.cd = o.idle_cd(float(a.get("idle", 0.1)))
		return
	var hv: Dictionary = _h4_heavy(o, a)
	o.cd = float(a.get("every", 1.0)) / o.stat(&"op_aspd") * (float(hv.get("interval", 1.0)) if not hv.is_empty() else 1.0)
	if not hv.is_empty():
		# 碎颅：每一锤都是强化版砸地（播技能动作帧），出手时仍走普攻结算
		_h4sg(o).heavy_swing = true
		o._start_action("skill", at, 0.6, 0.3, str(hv.get("anim", "")))
	else:
		o.start_attack(at)


static func _h4_hammer_release(o, a: Dictionary) -> void:
	var g = o.g
	var reach: float = float(a.get("r", 108.0)) * o.stat(&"op_range")
	var ang: float = o.facing_angle()
	var ts: Array = o.nearest_enemies(1, reach + 40.0, o.pos)
	if not ts.is_empty():
		ang = (ts[0].pos - o.pos).angle()
		o.face_to(ang)
	ang = o.atk_angle(ang)
	var mult := 1.0
	var patch: Dictionary = _h4_take_patch(o)
	if not patch.is_empty():
		mult *= float(patch.get("mult", 1.0)) * (o.skill_power() if patch.get("power", false) else 1.0)
	var hv: Dictionary = _h4_heavy(o, a)
	var heavy: bool = not hv.is_empty()
	if heavy:
		mult *= float(hv.get("mult", 1.0)) * (o.skill_power() if hv.get("power", true) else 1.0)
	_h3_sfx(o, "atk")
	var dmg: float = o.base(str(a.get("atk_key", "atk")), 0.0) * mult * o._dmg_bonus()
	var hits: Array = o.melee_hit(str(a.get("src", "")), o.pos + Vector2(0, float(a.get("y", -10.0))), ang, float(a.get("half", 1.2)), reach, dmg, float(a.get("kb", 0.0)), 0.0, a.get("tags", []))
	if heavy:
		var ch: float = float(hv.get("stun_chance", 0.5))
		for e in hits:
			if not e.dead and not e.boss and g.rng.randf() < ch:
				e.stun = maxf(e.stun, float(hv.get("stun", 0.8)) * (0.5 if e.elite else 1.0))
	o.slash_fx(o.pos + Vector2(0, -14), ang, 1.0, reach, H4_GOLD if not heavy else Color(1.0, 0.6, 0.3))
	var land: Vector2 = o.pos + Vector2(0, -6) + Vector2.from_angle(ang) * reach * 0.7
	if heavy:
		# 碎颅的每一锤：落点一次小型砸地（闪光 + 冲击环 + 不规则地裂 + 火星）
		o.fx({"kind": "glow", "pos": land + Vector2(0, -4), "r": 24.0, "life": 0.14, "col": Color(2.0, 1.5, 0.8), "alpha": 0.8})
		o.fx({"kind": "ring", "pos": land + Vector2(0, 6), "r": 58.0, "r0": 8.0, "life": 0.3, "col": H4_FLAME, "floor": true, "w": 3.0})
		o.fx({"kind": "crack", "pos": land + Vector2(0, 6), "r": 56.0, "life": 0.7, "col": H4_FLAME, "floor": true, "n": 6})
		_h3_vsparks(o, land, Color(1.0, 0.8, 0.35), 8, 220.0, 0.35, 2.5, 320.0)
		o.impact_pause(0.04)
	hw_record(o, dmg, ang, reach, land)
	_h4_hammer_after(o, a, hits, dmg)   # 精英化第 4 批的追加（粉碎）；迁移时没有
	var q: Dictionary = _h4_sub(o, a.get("quake", null))
	if not q.is_empty():
		_h4_quake(o, q, land, mult)
	var br: Dictionary = _h4_sub(o, a.get("breach", null))
	if not br.is_empty():
		_h4_breach(o, br, land, ang, mult)
	if not hits.is_empty():
		# 每次命中（不论几个目标）全队 +hit_sp 秒技力（精一翻倍）
		_h4_squad_sp_seconds(o, float(a.get("hit_sp", 0.0)) * _h4_first_mult(o, a.get("hit_sp_mults", [])))
		_h4_sp_motes(o, 1)
		_h3_sfx(o, "hit", 2.0 if heavy else 0.0, 0.85 if heavy else 1.0)


## 精一「粉碎」（docs/91 §11）：这一锤击倒的敌人处迸出一圈碎石（r × op_range 内 锤击 × mult），每一锤至多 cap 处；只算锤击本身击倒的
static func _h4_hammer_after(o, a: Dictionary, hits: Array, dmg: float) -> void:
	var cr: Dictionary = _h4_sub(o, a.get("crush", null))
	if cr.is_empty():
		return
	var g = o.g
	var r: float = float(cr.get("r", 50.0)) * o.stat(&"op_range")
	var cap: int = int(cr.get("cap", 2))
	var pts: Array = []
	for e in hits:
		if pts.size() >= cap:
			break
		if e.dead:
			pts.append(e.pos)
	for p in pts:
		o.area_hit(str(cr.get("src", "")), p, r, dmg * float(cr.get("mult", 0.2)))
		if not o.spawn_fx_sprite(str(cr.get("tex", "fx_siege_pebbles")), p + Vector2(0, -6), g.PX * clampf(r / 40.0, 0.8, 1.6)):
			o.spawn_fx_sprite("fx_rock_burst", p, g.PX * 0.6, 0.0, false, false, Color(1.25, 1.05, 0.6))
			for k in 5:   # 程序回退：几颗金色石子抛物线落地
				var an: float = -PI / 2.0 + g.vrng.randf_range(-1.1, 1.1)
				o.fx({"kind": "spark", "pos": p + Vector2(0, -6), "vel": Vector2.from_angle(an) * g.vrng.randf_range(90.0, 170.0), "life": 0.45, "col": Color(1.6, 1.25, 0.55), "sz": 3.0, "grav": 520.0})
		o.fx({"kind": "ring", "pos": p, "r": r, "r0": 6.0, "life": 0.25, "col": H4_GOLD, "floor": true, "w": 2.0, "alpha": 0.6})


## 震地 / 狮吼：锤子落地处一圈贴地冲击环（锤击 quake.mult 伤害；roar：范围 × r_mult 并击退）+ 尘土
static func _h4_quake(o, q: Dictionary, p: Vector2, mult: float) -> void:
	var g = o.g
	var ro: Dictionary = _h4_sub(o, q.get("roar", null))
	var roar: bool = not ro.is_empty()
	var r: float = float(q.get("r", 70.0)) * (float(ro.get("r_mult", 1.0)) if roar else 1.0) * o.stat(&"op_range")
	var kb: float = float(ro.get("kb", 0.0)) if roar else 0.0
	o.area_hit(str(q.get("src", "")), p, r, o.base("atk", 0.0) * mult * float(q.get("mult", 0.25)) * o._dmg_bonus(), kb)
	o.fx({"kind": "ring", "pos": p + Vector2(0, 6), "r": r, "r0": 10.0, "life": 0.32, "col": H4_GOLD, "floor": true, "w": 3.0 if roar else 2.0})
	if roar:
		o.fx({"kind": "ring", "pos": p + Vector2(0, 6), "r": r * 0.7, "r0": 6.0, "life": 0.26, "col": Color(2.0, 1.6, 0.8), "floor": true, "w": 1.5})
	for k in (8 if roar else 5):
		var an: float = k * TAU / (8.0 if roar else 5.0) + g.vrng.randf_range(-0.3, 0.3)
		o.fx({"kind": "h4_dust", "pos": p + Vector2(cos(an) * r * 0.35, sin(an) * r * 0.2 + 4.0), "vel": Vector2(cos(an), sin(an) * 0.5) * r * 1.6, "drag": 5.0,
			"r": g.vrng.randf_range(7.0, 11.0), "life": 0.45, "col": Color(0.62, 0.52, 0.4), "floor": true})


## 破阵：锤子落点沿锤击方向砸出一道直线金色地裂（锤击 breach.mult 伤害），发光裂隙 life 秒淡出
static func _h4_breach(o, br: Dictionary, p: Vector2, ang: float, mult: float) -> void:
	var g = o.g
	var sg := _h4sg(o)
	var L: float = float(br.get("len", 180.0))
	var w: float = float(br.get("w", 30.0))
	var dir: Vector2 = Vector2.from_angle(ang)
	var a: Vector2 = p + Vector2(0, 6)
	var dmg: float = o.base("atk", 0.0) * mult * float(br.get("mult", 0.5)) * o._dmg_bonus()
	var src: String = str(br.get("src", ""))
	for j in o.query_ids(a + dir * L * 0.5, L * 0.5 + 40.0):
		var e: Dictionary = g.enemies[j]
		if e.dead:
			continue
		var t: float = clampf((e.pos - a).dot(dir) / L, 0.0, 1.0)
		if e.pos.distance_to(a + dir * L * t) > w * 0.5 + e.r:
			continue
		o.log_hit(src)
		o.deal_damage(e, dmg)
		o.fx({"kind": "h4_cross", "pos": e.pos + Vector2(0, -e.r * 0.5), "life": 0.15, "col": H4_GOLD, "ang": g.vrng.randf() * PI})
	# 锯齿状的裂隙折线（生成一次，绘制时逐渐淡出）
	var pts := PackedVector2Array()
	var n: int = 9
	var nrm: Vector2 = dir.orthogonal()
	for i in n + 1:
		var u: float = float(i) / n
		var jit: float = 0.0 if i == 0 or i == n else g.vrng.randf_range(-7.0, 7.0)
		pts.append(a + dir * L * u + nrm * jit)
	if sg.fissures.size() >= int(br.get("max", 6)):
		sg.fissures.pop_front()
	var life: float = float(br.get("life", 0.6))
	sg.fissures.append({"pts": pts, "t": life, "max": life, "w": w, "a": a, "dir": dir, "len": L, "b": br})
	for k in 4:
		_h3_vsparks(o, a + dir * L * (0.25 + 0.25 * k), Color(1.0, 0.8, 0.35), 2, 140.0, 0.3, 2.0, 280.0, true)
	_h4_breach_after(o, br, a, dir, L)   # 精英化第 4 批的追加（岩刺）；迁移时没有


## 精二「破阵 + 岩刺」（docs/91 §11，纯画面）：地裂出现后 delay 秒，沿地裂每 step 冒出一根金色岩刺（拔起 → 停 → 缩回），逐根错开 stagger 秒
static func _h4_breach_after(o, br: Dictionary, a: Vector2, dir: Vector2, L: float) -> void:
	var sp: Dictionary = _h4_sub(o, br.get("spikes", null))
	if sp.is_empty():
		return
	var sg := _h4sg(o)
	var step: float = maxf(8.0, float(sp.get("step", 36.0)))
	var n: int = maxi(1, int(floor(L / step)))
	for k in n:
		if sg.spikes.size() >= 48:
			break
		sg.spikes.append({"t": float(sp.get("delay", 0.1)) + k * float(sp.get("stagger", 0.0)), "pos": a + dir * step * (k + 0.5), "b": sp, "flip": o.g.vrng.randf() < 0.5})


## 全队（不含自己）技力 + 秒数
static func _h4_squad_sp_seconds(o, sec: float) -> void:
	for m in o.g.squad.ops:
		if m == o:
			continue
		for i in 3:
			if m.skill_unlocked(i) and m.sp_need(i) > 0.0:
				m.sp[i] = minf(m.sp_need(i), m.sp[i] + sec)


## 金色技力粒子：从她飞向每名队友（verb.sp_team motes 也用它）
static func h4_sp_motes(o, n: int) -> void:
	_h4_sp_motes(o, n)


static func _h4_sp_motes(o, n: int) -> void:
	var g = o.g
	var c: Color = o.col()
	for m in g.squad.ops:
		if m == o or m.pos == Vector2.INF:
			continue
		for k in n:
			o.fx({"kind": "h4_spmote", "pos": o.pos + Vector2(0, -22), "start": o.pos + Vector2(0, -22), "tgt": m, "life": 0.45 + 0.08 * k, "col": c, "bend": g.vrng.randf_range(-40, 40)})


# ---------------------------------------------------------------- 推进之王：跃空锤 / 号令波

static func h4_leap(o, b: Dictionary) -> void:
	var sg := _h4sg(o)
	var ag: Dictionary = _h4_sub(o, b.get("again", null))
	sg.leap_n = 1 if not ag.is_empty() else 0
	sg.leap_second = false
	sg.leap_b = b
	var ts: Array = o.nearest_enemies(1, float(b.get("aim_r", 160.0)), o.pos)
	_h4_start_leap(o, ts[0] if not ts.is_empty() else null, float(b.get("dist", 90.0)))


## 起跳：朝目标敌人跃过去（最多 maxd），落在它面前；没有目标就原地跃起
static func _h4_start_leap(o, tg, maxd: float) -> void:
	var sg := _h4sg(o)
	sg.leap_t = 0.0
	sg.leap_pos = o.pos
	sg.leap_to = o.pos
	if tg != null:
		var dv: Vector2 = tg.pos - o.pos
		sg.leap_to = o.pos + dv.normalized() * clampf(dv.length() - 24.0, 0.0, maxd)
		o.face = signf(dv.x) if absf(dv.x) > 1.0 else o.face
	o.fx({"kind": "ring", "pos": o.pos, "r": 26.0, "r0": 6.0, "life": 0.2, "col": H4_GOLD, "floor": true, "w": 2.0})


## 跃空锤落地：伤害 / 眩晕 / 全队技力；second = 再跃的第二跳（× again.mult，不回技力）
static func _h4_slam(o, b: Dictionary, second: bool) -> void:
	var g = o.g
	var pos: Vector2 = o.pos
	var r: float = float(b.get("r", 110.0)) * o.stat(&"op_range")
	var ag = b.get("again", {})
	var sm: float = float(ag.get("mult", 0.6)) if second else 1.0
	o.area_hit(str(b.get("src", "")), pos, r, o.base("atk", 0.0) * float(b.get("mult", 2.2)) * o._dmg_bonus() * o.skill_power() * sm, float(b.get("kb", 220.0)), float(b.get("stun", 0.6)))
	o.fx({"kind": "glow", "pos": pos + Vector2(0, -6), "r": 34.0, "life": 0.16, "col": Color(2.0, 1.7, 0.9), "alpha": 0.8})
	o.fx({"kind": "ring", "pos": pos, "r": r, "r0": 14.0, "life": 0.35, "col": H4_FLAME, "floor": true, "w": 4.0})
	o.fx({"kind": "crack", "pos": pos + Vector2(0, 2), "r": r * 0.8, "life": 0.55, "col": H4_GOLD, "floor": true, "n": 10, "ang": g.t})
	o.fx({"kind": "h4_pillar", "pos": pos + Vector2(0, 2), "life": 0.38, "col": Color(1.9, 1.7, 0.6)})
	# 10-14 用户「推进之王二技能打中地面的火焰效果删除，只保留裂地效果」：去掉落地火圈与一圈火焰（fx_fire_aura / fx_flames / 程序 h4_blaze），
	# 留裂地（crack）、冲击环、光柱、火星与扬尘；纯画面
	o.ground_dust(pos, r * 0.6, 10)
	_h3_vsparks(o, pos + Vector2(0, -4), Color(1.0, 0.8, 0.35), 12, 260.0, 0.4, 2.5, 320.0)
	o.impact_pause(0.07)
	if not second:
		g.squad.gain_sp(float(b.get("sp", 0.2)) * o.skill_power(), o)
		_h4_sp_motes(o, 3)
	_h3_sfx(o, "big")


## 再跃的落点：落点半径 × near 之外、身边 again.range 以内敌人最密的一处（按 70 以内的邻居数打分）
static func _h4_next_cluster(o, b: Dictionary):
	var g = o.g
	var ag = b.get("again", {})
	var rng_r: float = float(ag.get("range", 220.0))
	var near_r: float = float(b.get("r", 110.0)) * o.stat(&"op_range") * float(ag.get("near", 0.6))
	var best = null
	var best_s := -1.0
	var cands: Array = o.query_ids(o.pos, rng_r)
	for j in cands:
		var e: Dictionary = g.enemies[j]
		if e.dead or e.chest:
			continue
		var d: float = e.pos.distance_to(o.pos)
		if d > rng_r or d < near_r:
			continue
		var s := 0.0
		for j2 in o.query_ids(e.pos, 70.0):
			var q: Dictionary = g.enemies[j2]
			if not q.dead and q.pos.distance_to(e.pos) < 70.0:
				s += 1.0
		s -= d * 0.002
		if s > best_s:
			best_s = s
			best = e
	if best == null:
		var ts: Array = o.nearest_enemies(1, rng_r, o.pos)
		best = ts[0] if not ts.is_empty() else null
	return best


## 号令波：一圈向外扩张的金色号令波（攻击 × mult × 技能强度，推开小怪）
static func h4_cmd_wave(o, b: Dictionary) -> void:
	var sg := _h4sg(o)
	if sg.waves.size() >= int(b.get("max", 2)):
		sg.waves.pop_front()
	sg.waves.append({"pos": o.pos, "t": 0.0, "r": 0.0, "dmg": o.base("atk", 0.0) * float(b.get("mult", 0.6)) * o._dmg_bonus() * o.skill_power(), "hit": {}, "b": b})
	o.g.fx.append({"kind": "rays", "pos": o.pos + Vector2(0, -20), "life": 0.45, "max": 0.45, "col": H4_GOLD, "op_spoke": true})
	_h3_sfx(o, "big", -4.0, 1.2)


static func _h4sg_tick(o, sg: Dictionary, dt: float) -> bool:
	var g = o.g
	if not sg.waves.is_empty():
		for w in sg.waves:
			var b: Dictionary = w.b
			var R: float = float(b.get("r", 180.0))
			var dur: float = float(b.get("dur", 0.4))
			w.t += dt
			w.r = R * (1.0 - pow(1.0 - clampf(w.t / dur, 0.0, 1.0), 2.0))
			for j in o.query_ids(w.pos, w.r + 30.0):
				var e: Dictionary = g.enemies[j]
				if e.dead or w.hit.has(e.id) or e.pos.distance_to(w.pos) > w.r + e.r:
					continue
				w.hit[e.id] = true
				o.log_hit(str(b.get("src", "")))
				o.deal_damage(e, w.dmg)
				if not e.dead and not e.boss and not e.elite:
					e.kb += (e.pos - w.pos).normalized() * float(b.get("kb", 380.0))
				_h3_vsparks(o, e.pos, H4_GOLD, 2, 140.0, 0.3, 2.0)
		sg.waves = sg.waves.filter(func(w): return w.t < float(w.b.get("dur", 0.4)) + 0.25)
	for fs in sg.fissures:
		fs.t -= dt
	sg.fissures = sg.fissures.filter(func(fs): return fs.t > 0.0)
	_h4_spikes_tick(o, sg, dt)
	if float(sg.leap_t) >= 0.0:
		# 跃空锤：空中转一圈，落地砸击（在 follow 之后覆盖位置，沿起跳点 → 落点飞过去）
		var b2: Dictionary = sg.leap_b
		var ld: float = float(b2.get("t", 0.42))
		sg.leap_t = float(sg.leap_t) + dt
		var lu: float = clampf(float(sg.leap_t) / ld, 0.0, 1.0)
		o.pos = sg.leap_pos.lerp(sg.leap_to, lu)
		if float(sg.leap_t) >= ld:
			sg.leap_t = -1.0
			_h4_slam(o, b2, sg.leap_second)
			# 再跃：落地后立刻跃向下一群敌人（主控时连博士挂件一起带过去）
			if int(sg.leap_n) > 0:
				sg.leap_n = int(sg.leap_n) - 1
				var nc = _h4_next_cluster(o, b2)
				if nc != null:
					sg.leap_second = true
					_h4_start_leap(o, nc, float(b2.get("again", {}).get("dist", 150.0)))
		return true
	return false


## 岩刺的延迟画面（纯画面）：到点在地裂上播 Codex 岩刺帧条（底边中点落地）；缺图退回旧岩刺帧条染金，再缺画程序尖刺
static func _h4_spikes_tick(o, sg: Dictionary, dt: float) -> void:
	if sg.spikes.is_empty():
		return
	var g = o.g
	var due: Array = []
	for sk in sg.spikes:
		sk.t -= dt
		if sk.t <= 0.0:
			due.append(sk)
	sg.spikes = sg.spikes.filter(func(sk): return sk.t > 0.0)
	for sk in due:
		var b: Dictionary = sk.b
		var sc: float = g.PX * float(b.get("scale", 1.0))
		if o.spawn_fx_sprite(str(b.get("tex", "fx_siege_rock_spike")), sk.pos, sc, 0.0, sk.flip, true):
			continue
		if o.spawn_fx_sprite("fx_rock_spike", sk.pos, sc * 0.8, 0.0, sk.flip, true, Color(1.35, 1.1, 0.6)):
			continue
		o.fx({"kind": "h4_spike", "pos": sk.pos, "life": 0.4, "h": 24.0 * float(b.get("scale", 1.0))})


# ---------------------------------------------------------------- 推进之王：画面

## 跃空锤在空中：身体绕身体中心整圈翻转（贴图按帧画、只加旋转），高度抛物线；身后实心扇形扫光。返回 true = 已画（data_operator.draw_body 不再画本体）
static func h4_draw_body(o) -> bool:
	if not o.hw.has("sg") or float(o.hw.sg.leap_t) < 0.0:
		return false
	var g = o.g
	var cv = o.cv
	var sg: Dictionary = o.hw.sg
	var st: Dictionary = o.anim_state()
	if st.is_empty():
		return true
	var b: Dictionary = sg.leap_b
	var u: float = clampf(float(sg.leap_t) / float(b.get("t", 0.42)), 0.0, 1.0)
	var hh: float = 4.0 * float(b.get("h", 42.0)) * u * (1.0 - u)
	var ang: float = u * TAU * (1.0 if o.face >= 0.0 else -1.0)
	var tx: Texture2D = st.tex
	var hf: int = st.hf
	var fw: float = tx.get_width() / hf
	var fh: float = tx.get_height()
	var fo: float = o.foot_off(tx, st.get("kind", ""))
	var pk: float = g.PX / ArtS.hires_of(tx)
	var cy: float = (-fh + fo) / 2.0
	var center: Vector2 = o.pos + Vector2(0, -hh + cy * pk)
	_h4_spin_disc(o, center, u)
	cv.draw_set_transform(center.round(), ang, Vector2(-pk if st.flip else pk, pk))
	cv.draw_texture_rect_region(tx, Rect2(Vector2(-fw / 2.0, -fh + fo - cy), Vector2(fw, fh)), Rect2(fw * (st.frame % hf), 0, fw, fh))
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


## 空中翻转的速度感：以干员为圆心的实心扇形渐变盘，最前端最亮、往后按角度逐渐透明，前端一小条橙色
static func _h4_spin_disc(o, c: Vector2, u: float) -> void:
	var cv = o.cv
	var sgn: float = 1.0 if o.face >= 0.0 else -1.0
	var head: float = -PI / 2.0 + u * TAU * sgn
	var sweep: float = minf(u * TAU + 0.6, 5.8)
	var R := 36.0
	var N := 36
	for i in N:
		var t0: float = float(i) / N
		var t1: float = float(i + 1) / N
		var a0: float = head - sgn * sweep * t0
		var a1: float = head - sgn * sweep * t1
		var k: float = pow(1.0 - t0, 1.7)
		cv.draw_colored_polygon(PackedVector2Array([c, c + Vector2.from_angle(a0) * R, c + Vector2.from_angle(a1) * R]), Color(1.9, 1.9, 2.0, 0.7 * k))
	cv.draw_line(c, c + Vector2.from_angle(head) * R, Color(H4_FLAME.r * 1.6, H4_FLAME.g * 1.4, H4_FLAME.b, 0.9), 3.0)
	var o0: float = head - sgn * 0.5
	cv.draw_arc(c, R, minf(o0, head), maxf(o0, head), 6, Color(2.2, 2.2, 2.3, 0.9), 3.0)


## 地面层：破阵地裂（深色裂口 + 金色亮芯，前 0.08 秒向前裂开）与号令波
static func _h4sg_draw_floor(o) -> void:
	var cv = o.cv
	var sg: Dictionary = o.hw.sg
	for fs in sg.fissures:
		if _h4_draw_fissure_tex(o, fs):
			continue
		var a: float = clampf(fs.t / fs.max, 0.0, 1.0)
		var grow: float = clampf((fs.max - fs.t) / 0.08, 0.0, 1.0)
		var pts: PackedVector2Array = fs.pts
		var m: int = maxi(2, int(ceil(pts.size() * grow)))
		var sub: PackedVector2Array = pts.slice(0, m)
		cv.draw_polyline(sub, Color(1.0, 0.7, 0.3, 0.2 * a), fs.w)
		cv.draw_polyline(sub, Color(1.6, 1.1, 0.4, 0.35 * a), fs.w * 0.4)
		cv.draw_polyline(sub, Color(0.06, 0.04, 0.03, 0.85 * minf(1.0, a * 2.0)), 5.0)
		cv.draw_polyline(sub, Color(2.4, 1.8, 0.8, a), 2.0)
	for w in sg.waves:
		var dur: float = float(w.b.get("dur", 0.4))
		var fade: float = clampf(1.0 - (w.t - dur) / 0.25, 0.0, 1.0) if w.t > dur else 1.0
		cv.draw_set_transform(w.pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
		cv.draw_circle(Vector2.ZERO, w.r, Color(H4_GOLD.r, H4_GOLD.g, H4_GOLD.b, 0.08 * fade))
		cv.draw_arc(Vector2.ZERO, w.r, 0.0, TAU, 56, Color(2.2, 1.7, 0.7, 0.9 * fade), 5.0)
		cv.draw_arc(Vector2.ZERO, w.r * 0.86, 0.0, TAU, 48, Color(H4_GOLD.r, H4_GOLD.g, H4_GOLD.b, 0.45 * fade), 2.0)
		for q in (16 if Dc.hit_spokes() else 0):   # 狮鬃放射纹（render/hit_spokes 缺省不画），号令波环照画
			var dv := Vector2.from_angle(q * TAU / 16.0)
			cv.draw_line(dv * w.r * 0.75, dv * w.r, Color(2.0, 1.6, 0.7, 0.6 * fade), 2.0)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 精二地裂帧条（breach.tile，Codex fx_siege_fissure_tile 横向平铺）：前 0.08 秒向前裂开，4 帧随寿命推进（裂开 → 发光 → 冷却），整体淡出；缺图返回 false 画程序裂隙
static func _h4_draw_fissure_tex(o, fs: Dictionary) -> bool:
	var g = o.g
	var b: Dictionary = fs.get("b", {})
	var tn: String = str(b.get("tile", ""))
	if tn == "" or g.tex.get(tn) == null or not g.V6_FRAMES.has(tn):
		return false
	var a: float = clampf(fs.t / fs.max, 0.0, 1.0)
	var grow: float = clampf((fs.max - fs.t) / 0.08, 0.0, 1.0)
	var frames: int = int(g.V6_FRAMES[tn][0])
	var fr: int = mini(frames - 1, int((1.0 - a) * frames))
	var e: Vector2 = fs.a + fs.dir * fs.len * grow
	o.cv.draw_line(fs.a, e, Color(1.0, 0.7, 0.3, 0.16 * a), fs.w)   # 外光底（同程序版），帧条盖在上面
	_hw_draw_tiled(o, tn, fs.a, e, g.PX * float(b.get("tile_scale", 1.0)), 0.0, 0, Color(1, 1, 1, minf(1.0, a * 1.6)), fr)
	return true


## 区域层：碎颅期间头顶一圈橙色呼吸环（heavy.ring）
static func _h4sg_draw_auras(o) -> void:
	var hv: Dictionary = _h4_heavy(o, o.B.get("attack", {}))
	if hv.is_empty() or not hv.get("ring", false) or o.pos == Vector2.INF:
		return
	var g = o.g
	o.cv.draw_arc(o.pos + Vector2(0, -22), 26.0 + 3.0 * sin(g.t * 9.0), 0.0, TAU, 24, Color(1.0, 0.6, 0.3, 0.4 + 0.15 * sin(g.t * 9.0)), 2.0)


## 推进之王的程序粒子：尘土 / 火苗 / 落地光柱 / 技力粒子 / 命中十字闪
static func _h4sg_draw_pfx(o, f: Dictionary, a: float) -> bool:
	var g = o.g
	var cv = o.cv
	match str(f.kind):
		"h4_dust":
			var k0: float = 1.0 - a
			var dc: Color = f.col
			cv.draw_set_transform(f.pos, 0.0, Vector2(1.0, 0.6))
			cv.draw_circle(Vector2.ZERO, f.r * (0.7 + 0.8 * k0), Color(dc.r, dc.g, dc.b, 0.35 * a))
			cv.draw_circle(Vector2(f.r * 0.3, -f.r * 0.2), f.r * (0.45 + 0.6 * k0), Color(dc.r * 1.1, dc.g * 1.1, dc.b * 1.1, 0.3 * a))
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			return true
		"h4_blaze":
			var k: float = 1.0 - a
			var h: float = f.sz * (0.55 + 0.9 * minf(1.0, k * 3.0)) * (0.4 + 0.6 * a)
			var w: float = f.sz * 0.36 * (0.5 + 0.5 * a)
			var b: Vector2 = f.pos
			cv.draw_circle(b + Vector2(0, -h * 0.15), w * 1.4, Color(2.0, 0.9, 0.25, 0.22 * a))
			for layer in 2:
				var s2: float = 1.0 if layer == 0 else 0.55
				var hh: float = h * s2
				var ww: float = w * s2
				var left := PackedVector2Array()
				var right := PackedVector2Array()
				for i in 7:
					var t: float = float(i) / 6.0
					var hw: float = ww * sqrt(maxf(0.0, 1.0 - t)) * (0.75 + 1.6 * t if t < 0.15 else 1.0)
					var wob: float = sin(g.t * 22.0 + f.seed + t * 5.0) * ww * 0.3 * t
					left.append(b + Vector2(-hw + wob, -hh * t))
					right.append(b + Vector2(hw + wob, -hh * t))
				right.reverse()
				var pts: PackedVector2Array = left
				pts.append_array(right.slice(1))
				cv.draw_colored_polygon(pts, Color(2.0, 0.85, 0.22, 0.8 * a) if layer == 0 else Color(2.6, 2.1, 1.1, 0.9 * a))
			return true
		"h4_pillar":
			var k: float = 1.0 - a
			var H: float = 150.0 * minf(1.0, k * 4.0)
			var w: float = 30.0 * (1.0 - k * 0.8)
			var b: Vector2 = f.pos
			var c: Color = f.col
			cv.draw_colored_polygon(PackedVector2Array([b + Vector2(-w, 0), b + Vector2(-w * 0.25, -H), b + Vector2(w * 0.25, -H), b + Vector2(w, 0)]), Color(c.r, c.g, c.b, 0.35 * a))
			cv.draw_colored_polygon(PackedVector2Array([b + Vector2(-w * 0.35, 0), b + Vector2(-2, -H * 0.9), b + Vector2(2, -H * 0.9), b + Vector2(w * 0.35, 0)]), Color(2.2, 2.1, 1.6, 0.6 * a))
			for q in (6 if Dc.hit_spokes() else 0):
				var an: float = -PI / 2.0 + (q - 2.5) * 0.28
				cv.draw_line(b + Vector2(0, -8), b + Vector2(0, -8) + Vector2.from_angle(an) * H * (0.6 + 0.08 * (q % 3)), Color(c.r, c.g, c.b, 0.5 * a), 2.0)
			return true
		"h4_spmote":
			var k := 1.0 - a
			var to: Vector2 = f.tgt.pos + Vector2(0, -24)
			var p: Vector2 = f.start.lerp(to, k) + Vector2(0, -sin(k * PI) * 30.0) + f.start.direction_to(to).orthogonal() * sin(k * PI) * f.bend
			var tail: Vector2 = f.start.lerp(to, maxf(0.0, k - 0.12)) + Vector2(0, -sin(maxf(0.0, k - 0.12) * PI) * 30.0)
			var c: Color = f.col
			cv.draw_line(tail, p, Color(c.r, c.g, c.b, 0.5), 2.0)
			cv.draw_circle(p, 3.0, Color(2.2, 1.8, 0.9))
			return true
		"h4_cross":
			var L := 10.0 + 14.0 * (1.0 - a)
			for q in 2:
				var dv := Vector2.from_angle(float(f.get("ang", 0.0)) + q * PI / 2.0)
				cv.draw_line(f.pos - dv * L, f.pos + dv * L, Color(2.0, 1.7, 1.0, a), 2.5)
			cv.draw_circle(f.pos, 5.0 * a + 2.0, Color(2.4, 2.2, 1.6, a))
			return true
	return false


# ---------------------------------------------------------------- 铃兰段（第 4 批续，SZ_TAGS）
#  shape.foxfire    追踪狐火（普攻，手动 B 类）：起手 attack_targets(aim_n, range)，出手向 aim_targets(n, range + aim_pad) 发 n 团狐火（game 的 arcane 弹：追踪、命中小范围溅射）；
#                   n = shots + shot_adds 里 cond 成立的 n 之和；次数型补丁（狐火连珠）attack_patch {shots, mult, power}；狐火从杖头 tip 发出；同时在场的弹体 ≤ proj_max（含大狐火、围炉狐火）；
#                   merge {cond, every, all {cond}, mult, spd, life, r}：每第 every 次普攻（all 成立时每一次）三团合成一团大狐火直线贯穿（每名敌人一次）；
#                   seal {cond, stun, stun_elite}：狐火连珠的狐火命中后定身（Boss 不受）+ 脚下金印；狐火迷雾（光域 haze）期间不普攻
#  verb.foxlight    光域（放 trait 的 passive）：以本干员为心，半径 (r + r_elite × 精英阶段) × op_range，暖光（warm 条件）× warm_mult、迷雾 × haze_mult；
#                   区域内敌人减速（slow[平时 / 暖光 / 迷雾] 秒）、weak_cond 成立或迷雾时 aura_weak；暖光或迷雾期间每秒为队长回复 heal[平时 / 迷雾]；
#                   迷雾结束时：暖光在 → 其他干员攻击 + warm_buff × 技能强度，否则撤掉；hearth {cond, n, mult, cd, src}：暖光生效后光域边缘的狐火灼伤碰到的敌人
#  verb.fox_cast    暖光 / 狐火迷雾的出手：haze 秒迷雾（不写 = 暖光）、其他干员攻击 + buff × 技能强度、banner，光域边缘升起光柱

static func _h4sz(o) -> Dictionary:
	var h := hw_st(o)
	if not h.has("sz"):
		h["sz"] = {"haze_t": 0.0, "mote_t": 0.0, "heal_acc": 0.0, "pillar_t": 0.0, "n": 0, "merging": false,
			"bigfox": [], "sealed": [], "seals": [], "hearth_hit": {}, "brand": [], "brands": [], "trails": []}
	return h.sz


static func _h4_field_src(o) -> String:
	return "blk4:%s:field" % o.id


## 其他干员攻击加成：只写入别的干员的 op:<id> 作用域，不给自己（同手写，施放 / 迷雾结束时整组重写）
static func _h4_field_buff(o, v: float) -> void:
	var src: String = _h4_field_src(o)
	o.g.stats.remove_source(src)
	for m in o.g.squad.ops:
		if m != o:
			o.g.stats.add(&"op_atk", "add", v, src, "op:" + m.id)
	o.refresh_stats()


static func _h4_warm(o, fl: Dictionary) -> bool:
	return not fl.is_empty() and not _h4_sub(o, fl.get("warm", null)).is_empty()


## 光域半径（地面圆）：迷雾 × haze_mult，否则暖光 × warm_mult
static func h4_fox_r(o, fl: Dictionary) -> float:
	if fl.is_empty():
		return 0.0
	var r: float = (float(fl.get("r", 85.0)) + float(fl.get("r_elite", 0.0)) * o.elite) * o.stat(&"op_range")
	if float(_h4sz(o).haze_t) > 0.0:
		return r * float(fl.get("haze_mult", 2.2))
	return r * (float(fl.get("warm_mult", 1.6)) if _h4_warm(o, fl) else 1.0)


static func _h4_hearth(o, fl: Dictionary) -> Dictionary:
	if not _h4_warm(o, fl) or o.pos == Vector2.INF:
		return {}
	return _h4_sub(o, fl.get("hearth", null))


static func _h4_tip(o, a: Dictionary) -> Vector2:
	var tv = a.get("tip", [34, -42])
	return o.pos + Vector2(float(tv[0]) * o.face, float(tv[1]))


static func _h4_fox_shots(o, a: Dictionary) -> int:
	var n: int = int(a.get("shots", 2))
	for m in a.get("shot_adds", []):
		if m is Dictionary and cond_true(o, m.get("cond", {})):
			n += int(m.get("n", 1))
	return n


## 下一次普攻是否三火归一（merge.all 成立时每次都是）
static func _h4_next_merge(o, a: Dictionary) -> bool:
	var mg = a.get("merge", null)
	if not (mg is Dictionary):
		return false
	if not _h4_sub(o, mg.get("all", null)).is_empty():
		return true
	var every: int = maxi(1, int(mg.get("every", 3)))
	return cond_true(o, mg.get("cond", {})) and int(_h4sz(o).n) % every == every - 1


## 还能再放几发弹体（普通狐火 + 大狐火 + 围炉狐火合计 ≤ proj_max）
static func _h4_proj_room(o, a: Dictionary) -> int:
	var sz := _h4sz(o)
	var fl: Dictionary = _h4_live(o, "verb.foxlight")
	var hr: Dictionary = _h4_hearth(o, fl)
	var live: int = sz.bigfox.size() + (int(hr.get("n", 6)) if not hr.is_empty() else 0)
	for b in o.g.bullets:
		if b.life > 0.0 and b.get("op", "") == o.id:
			live += 1
	return int(a.get("proj_max", 12)) - live


static func _h4_fox_start(o, a: Dictionary) -> void:
	var sz := _h4sz(o)
	if float(sz.haze_t) > 0.0:
		return   # 狐火迷雾：期间不普攻
	if o.cd > 0.0:
		return
	var ts: Array = o.attack_targets(int(a.get("aim_n", 2)), float(a.get("range", 350.0)) * o.stat(&"op_range"), o.pos)   # 手动普攻 B 类（契约 v2.5）
	if ts.is_empty():
		o.cd = o.idle_cd(float(a.get("idle", 0.2)))
		return
	o.cd = float(a.get("every", 1.0)) / o.stat(&"op_aspd")
	sz.merging = _h4_next_merge(o, a) and not _h4_patch_pending(o)
	o.start_attack(ts[0].pos)
	if sz.merging:
		o.spawn_fx_sprite("fx_suzuran_foxfire_gather", _h4_tip(o, a), o.g.PX * 0.9)   # 三团狐火汇聚（原作：三团狐火合而为一再射出）


static func _h4_fox_release(o, a: Dictionary) -> void:
	var g = o.g
	var sz := _h4sz(o)
	var n: int = _h4_fox_shots(o, a)
	var mult := 1.0
	var volley := false
	var patch: Dictionary = _h4_take_patch(o)
	if not patch.is_empty():
		volley = true
		n = int(patch.get("shots", n))
		mult = float(patch.get("mult", 1.0)) * (o.skill_power() if patch.get("power", false) else 1.0)
	var big: bool = sz.merging and not volley
	sz.merging = false
	var reach: float = (float(a.get("range", 350.0)) + float(a.get("aim_pad", 20.0))) * o.stat(&"op_range")
	var ts: Array = o.aim_targets(n, reach, o.pos)
	var from: Vector2 = _h4_tip(o, a)
	if ts.is_empty():
		return
	if not volley:
		sz.n = int(sz.n) + 1
	var room: int = _h4_proj_room(o, a)
	if big and room > 0:
		# 三火归一：身前汇成的一团大狐火朝最近的敌人直线射出、贯穿沿途敌人；多出来的狐火照常发射
		room -= 1
		n = maxi(0, n - 3)
		var bt: Dictionary = ts[0]
		if not o.manual_attack():
			var lt: Array = o.los_targets(1, reach, o.pos)   # 地形阻挡：大狐火是直线弹，视线内的先
			if not lt.is_empty():
				bt = lt[0]
		_h4_fire_big(o, a, from, bt)
	var sl: Dictionary = _h4_sub(o, a.get("seal", null)) if volley else {}
	for k in n:
		if room <= 0:
			break
		room -= 1
		var tg: Dictionary = ts[k % ts.size()]
		var d: Vector2 = (tg.pos - o.pos).normalized().rotated(0.6 * (1 if k % 2 == 0 else -1) * (1.0 + 0.3 * (k / 2)))
		var b := {"kind": "arcane", "pos": from, "vel": d * float(a.get("speed", 330.0)), "dmg": o.base(str(a.get("atk_key", "atk")), 0.0) * mult * o._dmg_bonus() * (o.vs_elite() if tg.elite or tg.boss else 1.0),
			"life": float(a.get("life", 1.6)), "r": float(a.get("bullet_r", 7.0)), "aoe": float(a.get("aoe", 26.0)), "home": tg, "turn": float(a.get("turn", 7.0)), "src": str(a.get("src", "")), "op": o.id, "fx_col": H4_FOX, "hidden": true, "etrail": 0.0}
		g.bullets.append(b)
		if not sl.is_empty():
			sz.sealed.append(b)   # 画地为牢：命中由 game 结算，这里记住弹体，下一帧看它是否撞上了敌人
		_h4_fox_track(o, a, b)   # 精英化第 4 批（狐火灼印）的挂点；迁移时没有
	o.fx({"kind": "glow", "pos": from, "r": 10.0, "life": 0.15, "col": H4_FOX, "alpha": 0.5})
	_h3_sfx(o, "atk")


## 精一「狐火灼印」：记住这团狐火，命中后（game 结算时 life 置 0）给打中的敌人挂灼印
static func _h4_fox_track(o, a: Dictionary, b: Dictionary) -> void:
	if _h4_sub(o, a.get("brand", null)).is_empty():
		return
	var sz := _h4sz(o)
	if sz.brand.size() < 32:
		sz.brand.append(b)


## 灼印：dur 秒内受到的伤害 + value（敌人 frag_t / frag_v，combat.gd 读；同名取最高、再命中刷新）；脚下金印画面
static func _h4_brand_apply(o, br: Dictionary, e: Dictionary) -> void:
	if e.dead or e.get("chest", false):
		return
	var g = o.g
	var dur: float = float(br.get("dur", 2.0))
	var v: float = float(br.get("value", 0.08))
	if float(e.get("frag_t", 0.0)) > g.t:
		e["frag_v"] = maxf(float(e.get("frag_v", 0.0)), v)
	else:
		e["frag_v"] = v
	e["frag_t"] = maxf(float(e.get("frag_t", 0.0)), g.t + dur)
	var sz := _h4sz(o)
	for s2 in sz.brands:
		if is_same(s2.e, e):
			s2.t = maxf(float(s2.t), dur)
			return
	if sz.brands.size() >= int(br.get("max", 24)):
		sz.brands.pop_front()
	sz.brands.append({"e": e, "t": dur, "max": dur})


## 三火归一：大狐火（伤害 = 攻击 × merge.mult，贯穿，每名敌人只伤一次）
static func _h4_fire_big(o, a: Dictionary, from: Vector2, tg: Dictionary) -> void:
	var mg: Dictionary = a.get("merge", {})
	var d: Vector2 = (tg.pos + Vector2(0, -8) - from).normalized()
	_h4sz(o).bigfox.append({"pos": from, "vel": d * float(mg.get("spd", 340.0)), "dmg": o.base(str(a.get("atk_key", "atk")), 0.0) * float(mg.get("mult", 2.2)) * o._dmg_bonus(),
		"life": float(mg.get("life", 1.3)), "r": float(mg.get("r", 14.0)), "hit": {}, "trail": 0.0})
	o.fx({"kind": "glow", "pos": from, "r": 24.0, "life": 0.22, "col": H4_FOX, "alpha": 0.7})
	o.fx({"kind": "ring", "pos": from, "r": 30.0, "r0": 6.0, "life": 0.25, "col": H4_FOX, "w": 2.0})


static func _h4sz_tick(o, sz: Dictionary, dt: float) -> void:
	var g = o.g
	var a: Dictionary = o.B.get("attack", {})
	var fl: Dictionary = _h4_live(o, "verb.foxlight")
	# 狐火弹的火舌尾（纯画面）
	for b in g.bullets:
		if b.life <= 0.0 or b.get("op", "") != o.id or b.kind != "arcane":
			continue
		b.etrail = b.get("etrail", 0.0) - dt
		if b.etrail <= 0.0:
			b.etrail = 0.05
			o.fx({"kind": "flame", "pos": b.pos - b.vel.normalized() * 6.0, "vel": -b.vel * 0.08 + Vector2(0, -14), "life": 0.25, "col": H4_FOX, "sz": 7.0})
	_h4_bigfox_tick(o, sz, a, dt)
	_h4_seals_tick(o, sz, a, dt)
	_h4_brand_tick(o, sz, a, dt)   # 精英化第 4 批（狐火灼印 / 狐火拖尾）的挂点；迁移时没有
	if fl.is_empty():
		return
	var hr: Dictionary = _h4_hearth(o, fl)
	if not hr.is_empty():
		_h4_hearth_tick(o, sz, fl, hr)
	var warm: bool = _h4_warm(o, fl)
	if warm or float(sz.haze_t) > 0.0:
		var was_haze: bool = float(sz.haze_t) > 0.0
		sz.haze_t = maxf(0.0, float(sz.haze_t) - dt)
		sz.mote_t = float(sz.mote_t) - dt
		if float(sz.mote_t) <= 0.0:
			sz.mote_t = 0.05 if float(sz.haze_t) <= 0.0 else 0.03
			var an: float = g.vrng.randf() * TAU
			var rr: float = g.vrng.randf() * h4_fox_r(o, fl)
			o.fx({"kind": "mote", "pos": o.pos + Vector2(cos(an) * rr, sin(an) * rr * 0.55), "vel": Vector2(0, -40), "life": 0.7, "col": H4_FOX, "sz": 1.8})
		# 迷雾期间：光域里不时落下一根小光柱
		sz.pillar_t = float(sz.pillar_t) - dt
		if float(sz.haze_t) > 0.0 and float(sz.pillar_t) <= 0.0:
			sz.pillar_t = 0.9
			var a2: float = g.vrng.randf() * TAU
			var rr2: float = g.vrng.randf_range(0.3, 0.9) * h4_fox_r(o, fl)
			o.spawn_fx_sprite("fx_holy_pillar", o.pos + Vector2(cos(a2) * rr2, sin(a2) * rr2 * 0.55 + 4.0), g.PX * 0.7, 0.0, false, true)
		# 光域生效时主控缓慢回复（原作：范围内友军回复）
		sz.heal_acc = float(sz.heal_acc) + dt
		if float(sz.heal_acc) >= 1.0:
			sz.heal_acc = float(sz.heal_acc) - 1.0
			if g.hp < g.max_hp:
				var hv: Array = fl.get("heal", [0.005, 0.01])
				o.heal_leader(g.max_hp * (float(hv[1]) if float(sz.haze_t) > 0.0 else float(hv[0])), str(fl.get("src", o.display_name())))
		if was_haze and float(sz.haze_t) <= 0.0:
			# 迷雾刚结束：回到暖光（永久）或清除加成
			if warm:
				_h4_field_buff(o, float(fl.get("warm_buff", 0.15)) * o.skill_power())
			else:
				g.stats.remove_source(_h4_field_src(o))
				o.refresh_stats()
	var rad: float = h4_fox_r(o, fl)
	var haze: bool = float(sz.haze_t) > 0.0
	var sl: Array = fl.get("slow", [0.2, 0.4, 0.6])
	var slow: float = float(sl[2]) if haze else (float(sl[1]) if warm else float(sl[0]))
	var wk = fl.get("weak", {})
	var weak: bool = haze or not _h4_sub(o, wk).is_empty()
	var wv: float = float(wk.get("value", 0.2)) if wk is Dictionary else 0.2
	for j in o.query_ids(o.pos, rad + 20.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or e.pos.distance_to(o.pos) > rad:
			continue
		e.slow = maxf(e.slow, slow)
		if weak:
			e["aura_weak"] = maxf(float(e.get("aura_weak", 0.0)), wv)


static func _h4_bigfox_tick(o, sz: Dictionary, a: Dictionary, dt: float) -> void:
	if sz.bigfox.is_empty():
		return
	var g = o.g
	var src: String = str(a.get("src", ""))
	for f in sz.bigfox:
		f.life -= dt
		f.pos += f.vel * dt
		if g.map.tb_bul and g.map.bullet_blocked(f, f.pos):   # 地形阻挡：大狐火是直线弹，撞景物底座即消失
			f.life = 0.0
			continue
		f.trail -= dt
		if f.trail <= 0.0:
			f.trail = 0.03
			o.fx({"kind": "flame", "pos": f.pos - f.vel.normalized() * 10.0 + Vector2(g.vrng.randf_range(-4, 4), g.vrng.randf_range(-4, 4)), "vel": -f.vel * 0.12 + Vector2(0, -20), "life": 0.3, "col": H4_FOX, "sz": 11.0})
		_h4_bigfox_path(o, sz, a, f)   # 精英化第 4 批（狐火拖尾）的挂点
		for j in o.query_ids(f.pos, f.r + 40.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or f.hit.has(e.id) or e.pos.distance_to(f.pos) > f.r + e.r:
				continue
			f.hit[e.id] = true
			o.log_hit(src, ["pierce"])
			o.deal_damage(e, f.dmg * (o.vs_elite() if e.elite or e.boss else 1.0))
			if not e.dead:
				e.slow = maxf(e.slow, 1.0)
			o.fx({"kind": "ring", "pos": e.pos, "r": 26.0, "r0": 6.0, "life": 0.22, "col": H4_FOX, "w": 2.5})
			_h3_vsparks(o, e.pos, H4_FOX, 4, 180.0, 0.3, 2.5)
			_h4_fox_hit(o, a, e)   # 精英化第 4 批（狐火灼印）的挂点
	sz.bigfox = sz.bigfox.filter(func(f): return f.life > 0.0)


## 精二「狐火拖尾」：大狐火飞过的路径每 step 留一处狐火（life 秒），同一条拖尾每 every 秒灼伤后来踩进路径的敌人一次（攻击 × mult，对精英 / Boss × vs_elite；
## 这团大狐火已经贯穿过的敌人不再烧，免得原地不动的单体被同一团狐火连烧几跳）
static func _h4_bigfox_path(o, sz: Dictionary, a: Dictionary, f: Dictionary) -> void:
	var tr: Dictionary = _h4_sub(o, a.get("merge", {}).get("trail", null))
	if tr.is_empty():
		return
	if not f.has("tg"):
		if sz.trails.size() >= int(tr.get("cap", 4)):
			sz.trails.pop_front()
		f["tg"] = {"pts": [], "tick": float(tr.get("every", 0.3)), "dmg": o.base(str(a.get("atk_key", "atk")), 0.0) * float(tr.get("mult", 0.15)) * o._dmg_bonus(), "b": tr, "fhit": f.hit}
		f["tl"] = f.pos
		sz.trails.append(f.tg)
		f.tg.pts.append({"pos": f.pos, "t": float(tr.get("life", 1.0))})
		return
	if f.pos.distance_to(f.tl) >= float(tr.get("step", 22.0)) and f.tg.pts.size() < 48:
		f.tl = f.pos
		f.tg.pts.append({"pos": f.pos, "t": float(tr.get("life", 1.0))})


static func _h4_fox_hit(o, a: Dictionary, e: Dictionary) -> void:
	var br: Dictionary = _h4_sub(o, a.get("brand", null))
	if not br.is_empty() and not e.dead:
		_h4_brand_apply(o, br, e)


static func _h4_brand_tick(o, sz: Dictionary, a: Dictionary, dt: float) -> void:
	var g = o.g
	if not sz.brand.is_empty():
		var br: Dictionary = _h4_sub(o, a.get("brand", null))
		for i in range(sz.brand.size() - 1, -1, -1):
			var b: Dictionary = sz.brand[i]
			if b.life > 0.0:
				continue
			sz.brand.remove_at(i)
			if b.life < 0.0 or br.is_empty():
				continue
			var best = null
			var bd := 40.0
			for j in o.query_ids(b.pos, 40.0):
				var e: Dictionary = g.enemies[j]
				var dd: float = e.pos.distance_to(b.pos) - e.r
				if not e.dead and dd < bd:
					bd = dd
					best = e
			if best != null:
				_h4_brand_apply(o, br, best)
	if not sz.brands.is_empty():
		for s2 in sz.brands:
			s2.t -= dt
		sz.brands = sz.brands.filter(func(s2): return s2.t > 0.0 and not s2.e.dead)
	if sz.trails.is_empty():
		return
	for tg in sz.trails:
		for q in tg.pts:
			q.t -= dt
		tg.pts = tg.pts.filter(func(q): return q.t > 0.0)
		tg.tick -= dt
		if tg.tick > 0.0 or tg.pts.is_empty():
			continue
		tg.tick += float(tg.b.get("every", 0.3))
		var hit := {}
		var r: float = float(tg.b.get("r", 16.0))
		var src: String = str(tg.b.get("src", ""))
		for q in tg.pts:
			for j in o.query_ids(q.pos, r + 24.0):
				var e: Dictionary = g.enemies[j]
				if e.dead or hit.has(e.id) or tg.fhit.has(e.id) or e.pos.distance_to(q.pos) > r + e.r:
					continue
				hit[e.id] = true
				o.log_hit(src)
				o.deal_damage(e, tg.dmg * (o.vs_elite() if e.elite or e.boss else 1.0))
	sz.trails = sz.trails.filter(func(tg): return not tg.pts.is_empty())


## 画地为牢：狐火连珠的狐火撞上敌人（game 命中时把弹体 life 置 0；自然消散是负数）→ 定身 + 金印
static func _h4_seals_tick(o, sz: Dictionary, a: Dictionary, dt: float) -> void:
	var g = o.g
	var sl: Dictionary = a.get("seal", {})
	for i in range(sz.sealed.size() - 1, -1, -1):
		var b: Dictionary = sz.sealed[i]
		if b.life > 0.0:
			continue
		sz.sealed.remove_at(i)
		if b.life < 0.0:
			continue
		var best = null
		var bd := 40.0
		for j in o.query_ids(b.pos, 40.0):
			var e: Dictionary = g.enemies[j]
			var dd: float = e.pos.distance_to(b.pos) - e.r
			if not e.dead and dd < bd:
				bd = dd
				best = e
		if best == null or best.boss:
			continue
		var st: float = float(sl.get("stun_elite", 0.25)) if best.elite else float(sl.get("stun", 0.5))
		best.stun = maxf(best.stun, st)
		var found := false
		for s2 in sz.seals:
			if s2.e == best:
				s2.t = maxf(s2.t, st)
				found = true
		if not found:
			if sz.seals.size() >= int(sl.get("max", 6)):
				sz.seals.pop_front()
			sz.seals.append({"e": best, "t": st})
	for s2 in sz.seals:
		s2.t -= dt
	sz.seals = sz.seals.filter(func(s2): return s2.t > 0.0 and not s2.e.dead)


## 围炉：暖光光域边缘的狐火（与画面的位置一致）灼伤碰到的敌人，每名敌人 cd 秒一次
static func _h4_hearth_tick(o, sz: Dictionary, fl: Dictionary, hr: Dictionary) -> void:
	var g = o.g
	var r: float = h4_fox_r(o, fl)
	var n: int = int(hr.get("n", 6))
	var dmg: float = o.base("atk", 0.0) * float(hr.get("mult", 0.3)) * o._dmg_bonus()
	var every: float = float(hr.get("cd", 0.5))
	var hh: Dictionary = sz.hearth_hit
	for k in n:
		var an: float = g.t * 0.8 + k * TAU / n
		var p: Vector2 = o.pos + Vector2(4, 4) + Vector2(cos(an) * r, sin(an) * r * 0.55)
		for j in o.query_ids(p, 40.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or e.pos.distance_to(p) > 14.0 + e.r or float(hh.get(e.id, -1.0)) > g.t:
				continue
			hh[e.id] = g.t + every
			o.log_hit(str(hr.get("src", "")))
			o.deal_damage(e, dmg)
			o.fx({"kind": "flame", "pos": e.pos + Vector2(0, 4), "vel": Vector2(0, -30), "life": 0.3, "col": H4_FOX, "sz": 10.0})
	if hh.size() > 200:
		for key in hh.keys():
			if hh[key] < g.t:
				hh.erase(key)


## 暖光 / 狐火迷雾的出手
static func h4_fox_cast(o, b: Dictionary) -> void:
	var g = o.g
	var sz := _h4sz(o)
	sz.heal_acc = 0.0
	var haze: bool = b.has("haze")
	if haze:
		sz.haze_t = float(b.haze)
		if o.cur_skill >= 0:
			o.s_dur[o.cur_skill] = float(b.haze)
	_h4_field_buff(o, float(b.get("buff", 0.15)) * o.skill_power())
	if b.has("banner"):
		o.show_banner(str(b.banner))
	var fl: Dictionary = _h4_live(o, "verb.foxlight")
	var rr: float = h4_fox_r(o, fl)
	o.fx({"kind": "ring", "pos": o.pos, "r": rr, "r0": 10.0, "life": 0.6, "col": H4_FOX, "floor": true})
	g.fx.append({"kind": "rays", "pos": o.pos + Vector2(0, -24), "life": 0.5, "max": 0.5, "col": H4_FOX, "op_spoke": true})
	# 圣光光柱：中心一根 + 光域边缘六根小的
	o.spawn_fx_sprite("fx_holy_pillar", o.pos + Vector2(0, 4), g.PX * (1.4 if haze else 1.0), 0.0, false, true)
	for k in 6:
		var a3: float = k * TAU / 6.0 + g.t * 0.8
		o.spawn_fx_sprite("fx_holy_pillar", o.pos + Vector2(4, 4) + Vector2(cos(a3) * rr, sin(a3) * rr * 0.55), g.PX * 0.6, 0.0, false, true)
	o.spawn_fx_sprite("fx_circle_gold", o.pos + Vector2(0, 4), g.PX * 2.2)


# ---------------------------------------------------------------- 铃兰：画面

static func _h4_flame(o, p: Vector2, h: float, a: float) -> void:
	var g = o.g
	var cv = o.cv
	var wob: float = sin(g.t * 20.0 + p.x * 0.3) * 2.0
	cv.draw_colored_polygon(PackedVector2Array([p + Vector2(-h * 0.35, 0), p + Vector2(wob, -h), p + Vector2(h * 0.35, 0)]), Color(H4_FOX.r, H4_FOX.g, H4_FOX.b, 0.75 * a))
	cv.draw_colored_polygon(PackedVector2Array([p + Vector2(-h * 0.15, 0), p + Vector2(wob * 0.6, -h * 0.55), p + Vector2(h * 0.15, 0)]), Color(2.2, 2.0, 1.4, 0.8 * a))


## 区域层：九尾虚影（画在人物之下）、光域椭圆 + 边缘绕行的狐火（围炉时变大带热光）
static func _h4sz_draw_auras(o) -> void:
	if o.pos == Vector2.INF:
		return
	var g = o.g
	var cv = o.cv
	var a: Dictionary = o.B.get("attack", {})
	var tl: Dictionary = _h4_sub(o, a.get("tails", null))
	if not tl.is_empty():
		_h4_draw_tails(o, tl)
	var fl: Dictionary = _h4_live(o, "verb.foxlight")
	if fl.is_empty():
		return
	var sz: Dictionary = o.hw.sz
	var r: float = h4_fox_r(o, fl)
	var on: bool = _h4_warm(o, fl) or float(sz.haze_t) > 0.0
	cv.draw_set_transform(o.pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
	cv.draw_circle(Vector2.ZERO, r, Color(H4_FOX.r, H4_FOX.g, H4_FOX.b, 0.09 if on else 0.05))
	cv.draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(H4_FOX.r, H4_FOX.g, H4_FOX.b, (0.45 if on else 0.25) + 0.06 * sin(g.t * 3.0)), 2.0)
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var hr: Dictionary = _h4_hearth(o, fl)
	if not hr.is_empty():
		var hn: int = int(hr.get("n", 6))
		for k in hn:
			var an: float = g.t * 0.8 + k * TAU / hn
			var hp: Vector2 = o.pos + Vector2(4, 4) + Vector2(cos(an) * r, sin(an) * r * 0.55)
			cv.draw_circle(hp + Vector2(0, -6), 12.0, Color(H4_FOX.r, H4_FOX.g, H4_FOX.b, 0.22))
			_h4_flame(o, hp, 15.0, 1.0)
		return
	var n: int = 9 if float(sz.haze_t) > 0.0 else 6
	for k in n:
		var an2: float = g.t * 0.8 + k * TAU / n
		_h4_flame(o, o.pos + Vector2(4, 4) + Vector2(cos(an2) * r, sin(an2) * r * 0.55), 9.0 if on else 6.0, 0.9 if on else 0.6)


## 九尾虚影：Codex 帧条（tex，底部根点放在腰后，alpha），缺图画九条程序尾巴
static func _h4_draw_tails(o, tl: Dictionary) -> void:
	var g = o.g
	var cv = o.cv
	var root: Vector2 = o.pos + Vector2(-4.0 * o.face, -28)
	if o._fx_strip(str(tl.get("tex", "fx_suzuran_ninetails")), 4, int(g.t * 4.0), root, Vector2(0.5, 46.0 / 48.0), 0.0, Color(1, 1, 1, float(tl.get("alpha", 0.45))), o.face < 0.0):
		return
	var center: float = -PI / 2.0 - 0.25 * o.face
	for k in 9:
		var t: float = (k - 4) / 4.0
		var a0: float = center + t * 1.25
		var sway: float = sin(g.t * 1.8 + k * 0.7) * 0.12
		var L: float = 92.0 - absf(t) * 22.0
		for layer in 2:
			var ws: float = 1.0 if layer == 0 else 0.5
			var left := PackedVector2Array()
			var right := PackedVector2Array()
			for i in 9:
				var u: float = i / 8.0
				var an: float = a0 + sway * u * 2.0 + u * u * 0.4 * signf(t + 0.001) * o.face
				var p: Vector2 = root + Vector2.from_angle(an) * L * u
				var w: float = (12.0 * sin(PI * minf(1.0, u * 1.05 + 0.1)) + 0.8) * ws
				var nv: Vector2 = Vector2.from_angle(an).orthogonal()
				left.append(p + nv * w)
				right.append(p - nv * w)
			right.reverse()
			var pts: PackedVector2Array = left
			pts.append_array(right)
			var al: float = (0.2 if layer == 0 else 0.22) + 0.04 * sin(g.t * 3.0 + k)
			cv.draw_colored_polygon(pts, Color(H4_FOX.r * 1.3, H4_FOX.g * 1.2, H4_FOX.b, al) if layer == 0 else Color(2.0, 1.7, 1.0, al))
		var tip_an: float = a0 + sway * 2.0 + 0.4 * signf(t + 0.001) * o.face
		cv.draw_circle(root + Vector2.from_angle(tip_an) * L * 0.9, 3.5, Color(2.4, 2.2, 1.8, 0.3))


## 技能上层：身边常驻的小狐火（数量 = 每次普攻的狐火数；三火归一那一次三团向杖头汇聚）、大狐火、狐火弹
static func _h4sz_draw_over(o) -> void:
	if o.pos == Vector2.INF:
		return
	var g = o.g
	var cv = o.cv
	var a: Dictionary = o.B.get("attack", {})
	var sz: Dictionary = o.hw.sz
	var n: int = _h4_fox_shots(o, a)
	var conv := 0.0
	if sz.merging:
		conv = 1.0
	elif float(sz.haze_t) <= 0.0 and _h4_next_merge(o, a):
		conv = clampf(1.0 - o.cd / 0.45, 0.0, 1.0)
	var c: Vector2 = _h4_tip(o, a)
	for k in n:
		var an: float = g.t * 1.6 + k * TAU / n
		var p: Vector2 = o.pos + Vector2(cos(an) * 40.0, -22.0 + sin(an) * 13.0 + sin(g.t * 3.0 + k) * 2.0)
		if k < 3 and conv > 0.0:
			if conv > 0.85:
				continue
			p = p.lerp(c, conv * conv)
		cv.draw_circle(p + Vector2(0, -5), 9.0, Color(1.6, 1.1, 0.4, 0.35))
		if o._fx_strip("fx_suzuran_wisp", 4, int(g.t * 8.0) + k, p + Vector2(0, -8)):
			continue
		_h4_flame(o, p, 13.0, 1.0)
		cv.draw_circle(p + Vector2(0, -4), 2.5, Color(2.6, 2.4, 1.8, 0.95))
	if conv > 0.5:
		var hh: float = lerpf(10.0, 22.0, (conv - 0.5) * 2.0)
		cv.draw_circle(c + Vector2(0, -hh * 0.4), hh * 0.7, Color(H4_FOX.r, H4_FOX.g, H4_FOX.b, 0.3 * conv))
		_h4_flame(o, c, hh, conv)
	for f in sz.bigfox:
		cv.draw_circle(f.pos, 24.0, Color(H4_FOX.r, H4_FOX.g, H4_FOX.b, 0.22))
		cv.draw_circle(f.pos, 14.0, Color(2.0, 1.6, 0.8, 0.45))
		if o._fx_strip("proj_suzuran_bigfox", 4, int(g.t * 10.0), f.pos, Vector2(0.5, 0.5), f.vel.angle()):
			pass
		elif g.tex.get("proj_foxfire") != null:
			o.draw_spr_rot("proj_foxfire", int(g.t * 12.0) % 6, f.pos, f.vel.angle(), g.PX * 1.9)
		else:
			cv.draw_circle(f.pos, 9.0, Color(2.4, 2.0, 1.2))
	for b in g.bullets:
		if b.life <= 0.0 or b.get("op", "") != o.id or b.kind != "arcane":
			continue
		cv.draw_circle(b.pos, 10.0, Color(H4_FOX.r, H4_FOX.g, H4_FOX.b, 0.22))
		if g.tex.get("proj_foxfire") != null:
			o.draw_spr_rot("proj_foxfire", int(g.t * 12.0 + b.pos.x * 0.05) % 6, b.pos, b.vel.angle(), g.PX)
		else:
			cv.draw_circle(b.pos, 5.5, Color(2.2, 1.8, 1.0))


## 地面层：画地为牢的金色封印（跟着被定身的敌人）
static func _h4sz_draw_floor(o) -> void:
	var g = o.g
	var cv = o.cv
	for s2 in o.hw.sz.seals:
		var e: Dictionary = s2.e
		var al: float = clampf(s2.t / 0.15, 0.0, 1.0)
		var rr: float = e.r + 10.0
		cv.draw_set_transform(e.pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.5))
		cv.draw_circle(Vector2.ZERO, rr, Color(H4_FOX.r, H4_FOX.g, H4_FOX.b, 0.12 * al))
		cv.draw_arc(Vector2.ZERO, rr, 0.0, TAU, 28, Color(2.0, 1.6, 0.8, 0.85 * al), 2.0)
		cv.draw_arc(Vector2.ZERO, rr * 0.68, 0.0, TAU, 20, Color(2.0, 1.6, 0.8, 0.5 * al), 1.0)
		for q in 4:
			var qa: float = g.t * 2.0 + q * TAU / 4.0
			cv.draw_line(Vector2.from_angle(qa) * rr * 0.68, Vector2.from_angle(qa) * rr, Color(2.2, 1.8, 1.0, 0.8 * al), 1.5)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_h4sz_draw_floor_e(o)   # 精英化第 4 批（灼印 / 拖尾）


## 灼印：被狐火打中的敌人脚下一枚金色小印（Codex fx_suzuran_seal 循环，最后 0.3 秒淡出；缺图画程序小金环）
static func _h4sz_draw_floor_e(o) -> void:
	var sz: Dictionary = o.hw.sz
	if sz.brands.is_empty():
		return
	var g = o.g
	var cv = o.cv
	var br: Dictionary = o.B.get("attack", {}).get("brand", {})
	var tn: String = str(br.get("tex", "fx_suzuran_seal"))
	var has_tex: bool = g.tex.get(tn) != null and g.V6_FRAMES.has(tn)
	for s2 in sz.brands:
		var e: Dictionary = s2.e
		var al: float = clampf(float(s2.t) / 0.3, 0.0, 1.0) * clampf((float(s2.max) - float(s2.t)) / 0.12, 0.0, 1.0)
		var bp: Vector2 = e.pos + Vector2(0, float(e.r) * 0.7)
		if has_tex:
			fx_frame(cv, g, tn, int(g.V6_FRAMES[tn][0]), int(g.t * float(g.V6_FRAMES[tn][1]) + float(e.id) * 0.37), bp, g.PX * clampf(float(e.r) / 10.0, 0.9, 1.8), Color(1, 1, 1, al))
		else:
			cv.draw_set_transform(bp, 0.0, Vector2(1.0, 0.5))
			cv.draw_arc(Vector2.ZERO, float(e.r) * 0.8 + 4.0, 0.0, TAU, 20, Color(2.0, 1.6, 0.8, 0.75 * al), 1.5)
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---------------------------------------------------------------- 维什戴尔段（第 4 批续，WD_TAGS）
#  shape.cannon     炮击（普攻，手动 A 类，落点 aim_land）：目标 = 离队长最近、几个距离相仿（slack 内）时挑落点周围敌人最多的；炮弹是本干员自己的实体（高速平射 → 落点爆炸 → quake_t 秒后原地余震）。
#                   索敌距离 = k × (range / ref) × op_range（k：aim_r 起手 / fire_r 出手 / 技能的 aim_r）；爆炸半径 = aoe × op_range × aoe_mults；
#                   余震伤害 = 炮弹 × quake（quakes 里第一条 cond 成立的 value 取代），半径 × quake_r；echo {cond, delay, mult, size}：同一处再余震一次；
#                   ash {size, rings {cond}, stun}：次数型补丁（灰烬弹幕）的炮弹（rings：余震三圈并眩晕）；twin {cond, mult, size}：同时向次优目标再打一发；
#                   shade {cond, mult, r, stun, max}：被炸死的敌人留下残影，0.25 秒后殉爆；mark {dur, mult, r, max}：残影标记（死亡必殉爆）；
#                   giant {mult, size, cd, src}：饱和炮击装填的巨炮（普攻间隔 × cd）
#  verb.cannon_exec 凋零处刑：精英 / Boss 优先（血最多）的一发重炮（× mult × 技能强度、爆炸 × size、眩晕 stun）；mark {cond}：炸到的敌人挂残影标记
#  verb.cannon_load 饱和炮击：装填 n 发巨炮，第一发立刻打出去，之后的普攻换成巨炮直到打完（技能剩余 = 剩余发数）
#  verb.souls       魂灵之影（放 passive）：n 个悬在肩后，每 cd 秒各自飞向 range 内（优先未标记的）敌人挂上残影标记，再飞回来。
#                   follow: true（10-14 用户「魂灵之影只跟随维什戴尔发射炮击，而不是自己出去」）：不再飞出去，始终悬在肩后；
#                   维什戴尔每打出一发炮击（普攻 / 次数型补丁 / 巨炮），各影子依次（第 k 个晚 fire.gap × k 秒）朝主目标附近 fire.spread 内
#                   优先未标记、两个影子不重复的敌人（没有就主目标）开一炮（攻击 × fire.mult、同样余震）；魂炮命中时给它的目标挂上残影标记（标记机制照旧）

static func _h4wd(o) -> Dictionary:
	var h := hw_st(o)
	if not h.has("wd"):
		h["wd"] = {"shells": [], "quakes": [], "shades": [], "ammo": 0, "marks": {}, "souls": []}
	return h.wd


static func _h4_wd_reach(o, a: Dictionary, k: float) -> float:
	return k * (float(a.get("range", 340.0)) / float(a.get("ref", 480.0))) * o.stat(&"op_range")


static func _h4_wd_aoe(o, a: Dictionary) -> float:
	var r: float = float(a.get("aoe", 52.0)) * o.stat(&"op_range")
	for m in a.get("aoe_mults", []):
		if m is Dictionary and cond_true(o, m.get("cond", {})):
			r *= float(m.get("mult", 1.0))
	return r


static func _h4_count_around(o, c: Vector2, r: float) -> int:
	var n := 0
	for j in o.query_ids(c, r):
		var q: Dictionary = o.g.enemies[j]
		if not q.dead and q.pos.distance_to(c) < r:
			n += 1
	return n


## 普攻 / 饱和炮击的目标：离队长最近；最近几个距离相仿（slack 内）时挑落点周围敌人最多的
static func _h4_wd_target(o, a: Dictionary, reach: float) -> Dictionary:
	var g = o.g
	var cands: Array = []
	for e in o.nearest_enemies(6, reach, g.ppos):
		if e.pos.distance_to(o.pos) <= reach:
			cands.append(e)
	if cands.is_empty():
		return {}
	var d0: float = cands[0].pos.distance_to(g.ppos)
	var best: Dictionary = cands[0]
	var most := -1
	var slack: float = float(a.get("slack", 40.0))
	for e in cands:
		if e.pos.distance_to(g.ppos) - d0 > slack:
			break
		var n := _h4_count_around(o, e.pos, _h4_wd_aoe(o, a))
		if n > most:
			most = n
			best = e
	return best


## 凋零处刑：精英 / Boss 优先（血最多的），没有就按普攻的选法
static func _h4_exec_target(o, a: Dictionary, reach: float) -> Dictionary:
	var best: Dictionary = {}
	var hp := -1.0
	for e in o.nearest_enemies(24, reach, o.pos):
		if (e.elite or e.boss) and e.hp > hp:
			hp = e.hp
			best = e
	return best if not best.is_empty() else _h4_wd_target(o, a, reach)


static func _h4_muzzle(o, a: Dictionary) -> Vector2:
	var tv = a.get("tip", [14, -34])
	return o.pos + Vector2(float(tv[0]) * o.face, float(tv[1]))


static func _h4_cannon_start(o, a: Dictionary) -> void:
	if o.cd > 0.0:
		return
	var reach: float = _h4_wd_reach(o, a, float(a.get("aim_r", 480.0)))
	var tgt: Dictionary = _h4_wd_target(o, a, reach)
	var at: Vector2 = o.atk_point([tgt] if not tgt.is_empty() else [], reach)   # 手动普攻 A 类（契约 v2.5）：落点见 aim_land
	if at == Vector2.INF:
		o.cd = o.idle_cd(float(a.get("idle", 0.2)))
	else:
		var gi: Dictionary = a.get("giant", {})
		o.cd = float(a.get("every", 1.4)) / o.stat(&"op_aspd") * (float(gi.get("cd", 0.6)) if int(_h4wd(o).ammo) > 0 else 1.0)
		o.start_attack(at)


static func _h4_cannon_release(o, a: Dictionary) -> void:
	var wd := _h4wd(o)
	var tgt: Dictionary = _h4_wd_target(o, a, _h4_wd_reach(o, a, float(a.get("fire_r", 520.0)))) if o.atk_aim == Vector2.ZERO else o.aim_land(_h4_wd_reach(o, a, float(a.get("aim_r", 480.0))))
	if tgt.is_empty():
		return
	var atk: float = o.base(str(a.get("atk_key", "atk")), 0.0)
	if int(wd.ammo) > 0:
		wd.ammo = int(wd.ammo) - 1
		_h4_fire_giant(o, a, tgt.pos)
	else:
		var patch: Dictionary = _h4_take_patch(o)
		if not patch.is_empty():
			var ash: Dictionary = a.get("ash", {})
			var rings: bool = not _h4_sub(o, ash.get("rings", null)).is_empty()
			var d1: float = atk * float(patch.get("mult", 1.0)) * (o.skill_power() if patch.get("power", false) else 1.0)
			_h4_fire(o, a, tgt.pos, d1, str(a.get("src", "")), float(ash.get("size", 1.1)), true, 0.0, false, rings)
			_h4_twin(o, a, tgt, d1, rings)
		else:
			_h4_fire(o, a, tgt.pos, atk, str(a.get("src", "")), 1.0, true, 0.0)
			_h4_twin(o, a, tgt, atk, false)
	_h4_cannon_after(o, a, tgt)   # 精英化第 4 批（好礼）的挂点；迁移时没有
	_h4_souls_sync(o, a, tgt)   # 10-14：魂灵之影跟随开炮（verb.souls follow）


## 精一「好礼」（docs/91 §18）：炮击的主目标直接挂上残影标记（标记期间倒下必定引爆残影，攻击 × gift.mult）；手动给的落点（伪目标）不挂
static func _h4_cannon_after(o, a: Dictionary, tgt: Dictionary) -> void:
	var gf: Dictionary = _h4_sub(o, a.get("gift", null))
	if gf.is_empty() or int(tgt.get("id", -1)) < 0 or tgt.get("dead", false):
		return
	_h4_mark(o, a, tgt, true, float(gf.get("mult", 0.4)))


## 礼尚往来：第二发炮弹打次优目标（候选里第一个离首发落点超过爆炸半径的；没有就取下一个候选），伤害 × twin.mult
static func _h4_twin(o, a: Dictionary, first: Dictionary, dmg: float, rings: bool) -> void:
	var tw: Dictionary = _h4_sub(o, a.get("twin", null))
	if tw.is_empty():
		return
	var g = o.g
	var reach: float = _h4_wd_reach(o, a, float(a.get("fire_r", 520.0)))
	var best: Dictionary = {}
	for e in o.nearest_enemies(8, reach, g.ppos):
		if e.id == first.id or e.pos.distance_to(o.pos) > reach:
			continue
		if best.is_empty():
			best = e
		if e.pos.distance_to(first.pos) > _h4_wd_aoe(o, a):
			best = e
			break
	if best.is_empty():
		return
	_h4_fire(o, a, best.pos, dmg * float(tw.get("mult", 0.6)), str(a.get("src", "")), float(tw.get("size", 0.85)), true, 0.0, false, rings)


## 巨型炮弹：伤害 × giant.mult × 技能强度、爆炸 × size、必余震；炮口焰加倍 + 后坐火星
static func _h4_fire_giant(o, a: Dictionary, to: Vector2) -> void:
	var g = o.g
	var gi: Dictionary = a.get("giant", {})
	_h4_fire(o, a, to, o.base(str(a.get("atk_key", "atk")), 0.0) * float(gi.get("mult", 1.6)) * o.skill_power(), str(gi.get("src", "")), float(gi.get("size", 2.0)), true, 0.0, false, false, "giant")
	var mz: Vector2 = _h4_muzzle(o, a)
	var dir: Vector2 = (to - mz).normalized()
	o.fx({"kind": "glow", "pos": mz, "r": 26.0, "life": 0.16, "col": Color(1.8, 0.7, 0.5), "alpha": 0.8})
	for k in 8:
		o.fx({"kind": "spark", "pos": mz, "vel": (-dir).rotated(g.vrng.randf_range(-0.9, 0.9)) * g.vrng.randf_range(120, 260), "life": 0.3, "col": H4_EMBER, "sz": 2.5, "drag": 3.0})


## 发一发炮弹（rings：灰烬弹幕的强化炮弹，余震三圈并眩晕；kind：画面 / 音效档（"" 普通 / giant 巨炮 / exec 凋零处刑）；mark_c：炸到的敌人挂标记的条件，爆炸时求值）
static func _h4_fire(o, a: Dictionary, to: Vector2, base_dmg: float, src: String, size: float, quake: bool, stun: float, light := false, rings := false, kind := "", mark_c = null, from := Vector2.INF) -> Dictionary:
	var g = o.g
	var wd := _h4wd(o)
	var own: bool = from == Vector2.INF
	if own:
		o.face = signf(to.x - o.pos.x) if absf(to.x - o.pos.x) > 2.0 else o.face
		from = _h4_muzzle(o, a)
	# 高速炮弹：1500px/s、最高拱 18px（平射，但炮弹本身看得见）
	var dur: float = clampf(from.distance_to(to) / 1500.0, 0.08, 0.3)
	var s := {"from": from, "to": to, "t": 0.0, "dur": dur, "dmg": base_dmg * o._dmg_bonus(), "r": _h4_wd_aoe(o, a) * size, "src": src,
		"trail": 0.0, "quake": quake, "stun": stun, "light": light, "hist": [], "size": size, "rings": rings, "kind": kind, "mark_c": mark_c}
	wd.shells.append(s)
	if not own:
		return s
	# 出膛：暗红锥形炮口焰 + 向后飞的橙色火星
	var dir := (to - from).normalized()
	o.fx({"kind": "h4_muzzle", "pos": from, "dir": dir, "life": 0.07, "col": H4_RED, "sz": 30.0 * size})
	o.fx({"kind": "glow", "pos": from, "r": 9.0 * size, "life": 0.06, "col": Color(2.0, 1.1, 0.8), "alpha": 0.8})
	for k in 3:
		o.fx({"kind": "spark", "pos": from, "vel": (-dir).rotated(g.vrng.randf_range(-0.6, 0.6)) * g.vrng.randf_range(60, 140), "life": 0.2, "col": H4_EMBER, "sz": 2.0, "drag": 3.0})
	_h3_sfx(o, "atk", 2.0 if size <= 1.2 else 4.0, 1.0 if size <= 1.2 else 0.85)
	return s


static func _h4_shell_at(s: Dictionary, k: float) -> Vector2:
	return s.from.lerp(s.to, k) + Vector2(0, -sin(k * PI) * minf(18.0, s.from.distance_to(s.to) * 0.05))


## 凋零处刑：一发重炮，眩晕 + 余震
static func h4_cannon_exec(o, b: Dictionary) -> void:
	var a: Dictionary = o.B.get("attack", {})
	var tgt: Dictionary = _h4_exec_target(o, a, _h4_wd_reach(o, a, float(b.get("aim_r", 540.0))))
	if tgt.is_empty():
		return
	_h4_fire(o, a, tgt.pos, o.base(str(a.get("atk_key", "atk")), 0.0) * float(b.get("mult", 3.0)) * o.skill_power(), str(b.get("src", "")), float(b.get("size", 1.6)), true, float(b.get("stun", 0.8)), false, false, "exec", b.get("mark", null))
	var mz: Vector2 = _h4_muzzle(o, a)
	o.fx({"kind": "glow", "pos": mz, "r": 28.0, "life": 0.3, "col": H4_RED, "alpha": 0.6})
	_h3_vsparks(o, mz, H4_EMBER, 10, 200.0, 0.3)


## 饱和炮击：装填巨型炮弹，第一发立刻打出去，之后的普攻换成巨炮直到打完
static func h4_cannon_load(o, b: Dictionary) -> void:
	var wd := _h4wd(o)
	var a: Dictionary = o.B.get("attack", {})
	wd.ammo = int(b.get("n", 8))
	wd["status"] = str(b.get("status", "×%d"))
	if o.cur_skill >= 0:
		o.s_dur[o.cur_skill] = float(int(b.get("n", 8)))
	if b.has("banner"):
		o.show_banner(str(b.banner) % int(wd.ammo))
	var mz: Vector2 = _h4_muzzle(o, a)
	o.fx({"kind": "glow", "pos": mz, "r": 30.0, "life": 0.4, "col": H4_RED, "alpha": 0.6})
	_h3_vsparks(o, mz, H4_EMBER, 10, 160.0, 0.3)
	var tg3: Dictionary = _h4_wd_target(o, a, _h4_wd_reach(o, a, float(b.get("aim_r", 540.0))))
	if not tg3.is_empty():
		wd.ammo = int(wd.ammo) - 1
		_h4_fire_giant(o, a, tg3.pos)
		_h4_souls_sync(o, a, tg3)
		o.cd = float(a.get("every", 1.4)) / o.stat(&"op_aspd") * float(a.get("giant", {}).get("cd", 0.6))


static func _h4wd_tick(o, wd: Dictionary, dt: float) -> void:
	var g = o.g
	var a: Dictionary = o.B.get("attack", {})
	# 炮弹
	for s in wd.shells:
		s.t += dt
		s.trail -= dt
		if s.trail <= 0.0 and s.t < s.dur:
			s.trail = 0.03
			var p: Vector2 = _h4_shell_at(s, s.t / s.dur) if s.hist.size() < 3 else s.hist[s.hist.size() - 3]
			o.fx({"kind": "h4_ember", "pos": p, "vel": Vector2(g.vrng.randf_range(-30, 30), g.vrng.randf_range(-20, 30)), "life": 0.3, "col": H4_DARK, "sz": 3.0, "ang": g.vrng.randf() * TAU, "spin": 14.0, "grav": 200.0, "cold": true})
		if s.t < s.dur:
			s.hist.append(_h4_shell_at(s, s.t / s.dur))
			if s.hist.size() > 9:
				s.hist.pop_front()
		if s.t >= s.dur:
			_h4_explode(o, a, s.to, s.dmg, s.r, s.src, 0, s.stun, s.light, false, str(s.kind), s.get("mark_c", null))
			var me = s.get("mark_e", null)   # 魂炮（follow）：命中时给它的目标挂残影标记（目标还活着、在爆炸范围内）
			if me != null and not me.dead and me.pos.distance_to(s.to) < float(s.r) + float(me.r):
				_h4_mark(o, a, me)
			o.fx({"kind": "line", "pos": s.from, "to": s.to, "life": 0.09, "col": H4_RED, "w": 2.0 * float(s.get("size", 1.0))})
			if s.quake:
				var qd: float = s.dmg * _h4_first_val(o, a.get("quakes", []), float(a.get("quake", 0.4)))
				var qs: float = float(a.get("ash", {}).get("stun", 0.8)) if s.rings else 0.0
				var qt: float = float(a.get("quake_t", 0.45))
				wd.quakes.append({"pos": s.to, "t": qt, "dmg": qd, "r": s.r * float(a.get("quake_r", 1.2)), "rings": s.rings, "stun": qs})
				var ec: Dictionary = _h4_sub(o, a.get("echo", null))
				if not ec.is_empty():
					wd.quakes.append({"pos": s.to, "t": qt + float(ec.get("delay", 0.3)), "dmg": qd * float(ec.get("mult", 1.0)),
						"r": s.r * float(a.get("quake_r", 1.2)) * float(ec.get("size", 1.25)), "rings": s.rings, "stun": qs})
	wd.shells = wd.shells.filter(func(s): return s.t < s.dur)
	for q in wd.quakes:
		q.t -= dt
		if q.t <= 0.0:
			_h4_explode(o, a, q.pos, q.dmg, q.r, str(a.get("quake_src", "")), 0, q.stun, false, q.rings, "quake")
	wd.quakes = wd.quakes.filter(func(q): return q.t > 0.0)
	var sh: Dictionary = a.get("shade", {})
	for sd in wd.shades:
		sd.t -= dt
		if sd.t <= 0.0:
			_h4_explode(o, a, sd.pos, sd.dmg, sd.r, str(sh.get("src", "")), sd.depth, float(sh.get("stun", 0.6)), false, false, "shade")
	wd.shades = wd.shades.filter(func(sd): return sd.t > 0.0)
	# 残影标记
	if not wd.marks.is_empty():
		for k in wd.marks.keys():
			var mk: Dictionary = wd.marks[k]
			mk.t -= dt
			if mk.t <= 0.0 or mk.e.dead:
				wd.marks.erase(k)
	_h4_souls_tick(o, wd, a, dt)


## 条件成立的第一条 [{cond, value}] 的值；没有 = dv
static func _h4_first_val(o, arr, dv: float) -> float:
	if arr is Array:
		for m in arr:
			if m is Dictionary and cond_true(o, m.get("cond", {})):
				return float(m.get("value", dv))
	return dv


## 挂残影标记（亡者回响 / 魂灵之影）：mark.dur 秒内该敌人死亡（不论谁击杀）必定殉爆；同时最多 mark.max 个
static func _h4_mark(o, a: Dictionary, e: Dictionary, gift := false, mult := -1.0) -> void:
	if e.dead or e.get("chest", false):
		return
	var wd := _h4wd(o)
	var mk: Dictionary = a.get("mark", {})
	if not wd.marks.has(e.id) and wd.marks.size() >= int(mk.get("max", 12)):
		return
	var keep: bool = wd.marks.has(e.id) and wd.marks[e.id].get("gift", false)
	var m0: float = float(wd.marks[e.id].get("mult", -1.0)) if wd.marks.has(e.id) else -1.0
	wd.marks[e.id] = {"e": e, "t": float(mk.get("dur", 4.0)), "gift": gift or keep, "mult": maxf(m0, mult if mult >= 0.0 else float(mk.get("mult", 0.45)))}
	o.fx({"kind": "h4_shade", "pos": e.pos + Vector2(0, -e.r * 0.5), "life": 0.3, "col": H4_DARK})


## 击杀钩子：带残影标记的敌人殉爆（0.25 秒前摇 → 殉爆，伤害 = 攻击 × mark.mult）
static func _h4wd_on_kill(o, e: Dictionary) -> void:
	var wd: Dictionary = o.hw.wd
	if not wd.marks.has(e.id):
		return
	var mm: float = float(wd.marks[e.id].get("mult", -1.0))
	wd.marks.erase(e.id)
	e["wis_det"] = true
	var a: Dictionary = o.B.get("attack", {})
	if wd.shades.size() >= int(a.get("shade", {}).get("max", 12)):
		return
	var mk: Dictionary = a.get("mark", {})
	wd.shades.append({"pos": e.pos, "t": 0.25, "dmg": o.base(str(a.get("atk_key", "atk")), 0.0) * (mm if mm >= 0.0 else float(mk.get("mult", 0.45))) * o._dmg_bonus(), "r": _h4_wd_aoe(o, a) * float(mk.get("r", 0.9)), "depth": 1})
	o.fx({"kind": "h4_shade", "pos": e.pos, "life": 0.3, "col": H4_DARK})


## 魂灵之影：悬在维什戴尔肩后；每 cd 秒各自飞向附近一名（优先未标记的）敌人挂上残影，再飞回来
static func _h4_souls_tick(o, wd: Dictionary, a: Dictionary, dt: float) -> void:
	if o.pos == Vector2.INF:
		return
	var sb: Dictionary = _h4_live(o, "verb.souls")
	if sb.is_empty():
		return
	var g = o.g
	var souls: Array = wd.souls
	while souls.size() < int(sb.get("n", 2)):
		souls.append({"p": o.pos + Vector2(0, -50), "st": "idle", "tgt": null, "cd": 0.8 + 1.0 * souls.size()})
	if sb.get("follow", false):
		_h4_souls_follow_tick(o, wd, a, sb, dt)
		return
	var spd: float = float(sb.get("speed", 520.0))
	for k in souls.size():
		var s: Dictionary = souls[k]
		var home: Vector2 = _h4_soul_home(o, k)
		match str(s.st):
			"idle":
				s.p = s.p.lerp(home, minf(1.0, dt * 6.0))
				s.cd -= dt
				if s.cd <= 0.0:
					var tg: Dictionary = _h4_soul_target(o, sb)
					if tg.is_empty():
						s.cd = 0.3
					else:
						s.tgt = tg
						s.st = "go"
						s.gt = g.t
						s.cd = float(sb.get("cd", 2.0))
			"go":
				var tg2 = s.tgt
				if tg2 == null or tg2.dead:
					s.st = "back"
				else:
					var to: Vector2 = tg2.pos + Vector2(0, -tg2.r - 10.0)
					s.p = s.p.move_toward(to, spd * dt)
					if g.vrng.randf() < dt * 30.0:
						o.fx({"kind": "mote", "pos": s.p + Vector2(g.vrng.randf_range(-4, 4), 6), "vel": Vector2(0, -20), "life": 0.35, "col": Color(0.3, 0.05, 0.08), "sz": 2.5})
					if s.p.distance_to(to) < 8.0:
						_h4_mark(o, a, tg2)
						o.fx({"kind": "ring", "pos": tg2.pos, "r": tg2.r + 16.0, "r0": 4.0, "life": 0.3, "col": H4_RED, "floor": true, "w": 2.0})
						s.st = "back"
			"back":
				s.p = s.p.move_toward(home, spd * dt)
				if s.p.distance_to(home) < 10.0:
					s.st = "idle"
	_h4_soul_fire_tick(o, wd, a, sb, dt)   # 精英化第 4 批（魂炮）的挂点；迁移时没有


## 精二「魂炮」（docs/91 §18）：每个魂灵之影各自每 every 秒（待在肩后时）朝一名带残影标记的敌人开一炮（离它最近、两个影子不打同一个；没有标记就打离维什戴尔最近的），
## 攻击 × mult、同样余震；开火动作 anim 秒，第 fire_at 秒出膛
static func _h4_soul_fire_tick(o, wd: Dictionary, a: Dictionary, sb: Dictionary, dt: float) -> void:
	var fc: Dictionary = _h4_sub(o, sb.get("fire", null))
	if fc.is_empty():
		return
	var g = o.g
	for k in wd.souls.size():
		var s: Dictionary = wd.souls[k]
		if not s.has("fcd"):
			s["fcd"] = float(fc.get("first", 1.5)) + float(fc.get("stagger", 2.0)) * k
			s["ft"] = -1.0
		if float(s.ft) >= 0.0:
			s.ft = float(s.ft) + dt
			if not s.fired and float(s.ft) >= float(fc.get("fire_at", 0.16)):
				s.fired = true
				var tg = s.get("ftg", null)
				if tg != null and not tg.dead:
					_h4_soul_shot(o, a, fc, s, tg)
			if float(s.ft) >= float(fc.get("anim", 0.32)):
				s.ft = -1.0
			continue
		s.fcd = float(s.fcd) - dt
		if float(s.fcd) > 0.0 or str(s.st) != "idle":
			continue
		var tg2: Dictionary = _h4_soul_cannon_target(o, a, fc, s)
		if tg2.is_empty():
			s.fcd = 0.3
			continue
		s.fcd = float(fc.get("every", 4.0))
		s.ft = 0.0
		s.fired = false
		s.ftg = tg2


static func _h4_soul_cannon_target(o, a: Dictionary, fc: Dictionary, s: Dictionary) -> Dictionary:
	var wd: Dictionary = o.hw.wd
	var reach: float = _h4_wd_reach(o, a, float(fc.get("aim_r", 520.0)))
	var other = null
	for q in wd.souls:
		if not is_same(q, s) and float(q.get("ft", -1.0)) >= 0.0 and q.get("ftg", null) != null:
			other = q.ftg
	var best: Dictionary = {}
	var bd := INF
	for key in wd.marks:
		var e: Dictionary = wd.marks[key].e
		if e.dead or (other != null and is_same(e, other)) or e.pos.distance_to(o.pos) > reach:
			continue
		var ds: float = e.pos.distance_squared_to(s.p)
		if ds < bd:
			bd = ds
			best = e
	if not best.is_empty():
		return best
	var ts: Array = o.nearest_enemies(1, reach, o.pos)
	return ts[0] if not ts.is_empty() else {}


static func _h4_soul_shot(o, a: Dictionary, fc: Dictionary, s: Dictionary, tg: Dictionary) -> void:
	var g = o.g
	var from: Vector2 = s.p + Vector2(0, 4)
	var sh: Dictionary = _h4_fire(o, a, tg.pos, o.base(str(a.get("atk_key", "atk")), 0.0) * float(fc.get("mult", 0.3)), str(fc.get("src", "")), float(fc.get("size", 1.0)), true, 0.0, false, false, "soul", null, from)
	if fc.get("mark", false):
		sh["mark_e"] = tg
	var dir: Vector2 = (tg.pos - from).normalized()
	if g.tex.get("fx_wisadel_soul_fire") == null:   # 没有开火帧条：炮口一团暗紫烟
		o.spawn_fx_sprite("fx_muzzle_flash", from + dir * 6.0, g.PX * 0.7, dir.angle(), false, false, Color(0.55, 0.3, 0.75))
	for q in 3:
		o.fx({"kind": "spark", "pos": from, "vel": dir.rotated(g.vrng.randf_range(-0.6, 0.6)) * g.vrng.randf_range(60, 130), "life": 0.2, "col": Color(0.55, 0.15, 0.35), "sz": 2.0, "drag": 3.0})
	_h3_sfx(o, "atk", -4.0, 1.25, 0.05)


## follow 模式（10-14）：影子一直悬在肩后；排队的魂炮按 fq 倒数开火动作（anim 秒，第 fire_at 秒出膛）
static func _h4_souls_follow_tick(o, wd: Dictionary, a: Dictionary, sb: Dictionary, dt: float) -> void:
	var fc: Dictionary = _h4_sub(o, sb.get("fire", null))
	for k in wd.souls.size():
		var s: Dictionary = wd.souls[k]
		s.p = s.p.lerp(_h4_soul_home(o, k), minf(1.0, dt * 6.0))
		if fc.is_empty():
			s.ft = -1.0
			s.fq = -1.0
			continue
		if float(s.get("fq", -1.0)) >= 0.0:
			s.fq = float(s.fq) - dt
			if float(s.fq) < 0.0:
				s.fq = -1.0
				s.ft = 0.0
				s.fired = false
		if float(s.get("ft", -1.0)) >= 0.0:
			s.ft = float(s.ft) + dt
			if not s.fired and float(s.ft) >= float(fc.get("fire_at", 0.16)):
				s.fired = true
				var tg = s.get("ftg", null)
				if tg != null and not tg.dead:
					_h4_soul_shot(o, a, fc, s, tg)
			if float(s.ft) >= float(fc.get("anim", 0.32)):
				s.ft = -1.0


## 维什戴尔打出一发炮击：各影子排一发魂炮（正在开火的影子这次不跟）。目标 = 主目标 spread 内优先未标记、影子间不重复的敌人，没有就主目标
static func _h4_souls_sync(o, a: Dictionary, tgt: Dictionary) -> void:
	var sb: Dictionary = _h4_live(o, "verb.souls")
	if sb.is_empty() or not sb.get("follow", false) or int(tgt.get("id", -1)) < 0 or tgt.get("dead", false):
		return
	var fc: Dictionary = _h4_sub(o, sb.get("fire", null))
	if fc.is_empty():
		return
	var wd := _h4wd(o)
	var spread: float = float(fc.get("spread", 120.0)) * o.stat(&"op_range")
	var near: Array = o.nearest_enemies(8, spread, tgt.pos)
	var taken: Array = [tgt.id]
	var q := 0
	for k in wd.souls.size():
		var s: Dictionary = wd.souls[k]
		if float(s.get("ft", -1.0)) >= 0.0 or float(s.get("fq", -1.0)) >= 0.0:
			continue
		var pick: Dictionary = tgt
		for e in near:
			if not e.dead and not e.get("chest", false) and not wd.marks.has(e.id) and not taken.has(e.id):
				pick = e
				break
		taken.append(pick.id)
		s.ftg = pick
		s.fq = float(fc.get("delay", 0.05)) + float(fc.get("gap", 0.08)) * q
		q += 1


static func _h4_soul_home(o, k: int) -> Vector2:
	var side: float = -1.0 if k == 0 else 1.0
	return o.pos + Vector2(side * 32.0 - o.face * 6.0, -78.0 + sin(o.g.t * 2.2 + k * 2.0) * 4.0)


## 魂灵之影的目标：range 以内最近的未标记敌人；都标记过就取最近的
static func _h4_soul_target(o, sb: Dictionary) -> Dictionary:
	var wd: Dictionary = o.hw.wd
	var ts: Array = o.nearest_enemies(8, float(sb.get("range", 300.0)), o.pos)
	for e in ts:
		if not wd.marks.has(e.id) and not e.get("chest", false):
			return e
	return ts[0] if not ts.is_empty() else {}


## 爆炸：范围伤害；精一起（shade.cond）被炸死的敌人留下残影，0.25 秒后殉爆并眩晕。light：减量特效；rings：三圈余震
static func _h4_explode(o, a: Dictionary, c: Vector2, dmg: float, r: float, src: String, depth: int, stun: float, light := false, rings := false, kind := "", mark_c = null) -> void:
	var g = o.g
	var killed: Array = []
	var mark_hit: bool = not _h4_sub(o, mark_c).is_empty()
	for e in o.arc_targets(c, 0.0, PI, r):
		o.log_hit(src)
		o.deal_damage(e, dmg)
		if not e.dead and g.rfx.sniper_execute(e, g.hit):
			o.log_hit("真实")
			o.deal_damage(e, e.hp + 1.0)
		if e.dead:
			if not e.get("wis_det", false):   # 带残影标记的敌人已在 on_kill 里殉爆，这里不再重复留残影
				killed.append(e.pos)
		else:
			if stun > 0.0 and not e.boss:
				e.stun = maxf(e.stun, stun * (0.5 if e.elite else 1.0))
			if mark_hit:   # 亡者回响：凋零处刑炸到的敌人全部挂上残影标记
				_h4_mark(o, a, e)
	var sh: Dictionary = a.get("shade", {})
	if kind == "quake":
		# 只在地面：双红环 + 裂纹 + 一圈向上的余烬，不闪光不冒烟
		o.fx({"kind": "ring", "pos": c, "r": r, "r0": r * 0.2, "life": 0.35, "col": H4_RED, "floor": true, "w": 3.0})
		o.fx({"kind": "ring", "pos": c, "r": r * 0.65, "r0": r * 0.1, "life": 0.45, "col": Color(1.0, 0.45, 0.35), "floor": true, "w": 2.0})
		if rings:
			o.fx({"kind": "ring", "pos": c, "r": r * 1.3, "r0": r * 0.5, "life": 0.6, "col": Color(1.6, 0.6, 0.3), "floor": true, "w": 4.0})
			_h3_vsparks(o, c, H4_EMBER, 6, 160.0, 0.35, 2.5, -80.0)
		o.fx({"kind": "crack", "pos": c, "r": r * 0.7, "life": 0.35, "col": H4_RED, "floor": true, "n": 7, "ang": c.x * 0.01})
		for k in (4 if light else 8):
			var ox: float = g.vrng.randf_range(-r * 0.6, r * 0.6)
			o.fx({"kind": "spark", "pos": c + Vector2(ox, 0), "vel": Vector2(ox * 0.4, g.vrng.randf_range(-110, -60)), "life": 0.4, "col": H4_RED, "sz": 2.0, "grav": 160.0})
	elif kind == "shade":
		o.fx({"kind": "h4_smoke", "pos": c, "r": r * 0.8, "life": 0.45, "col": H4_DARK})
		h4_impact_fx(o, c, r, light)
	elif kind == "giant":
		h4_burst_fx(o, c, r)
		o.impact_pause(0.05)   # 巨炮落地：短顿帧
	elif kind == "exec":
		h4_burst_fx(o, c, r, true)
	elif kind == "soul":   # 魂炮：同炮击落地，缩到 0.7
		h4_impact_fx(o, c, r * 0.7, true)
	else:
		h4_impact_fx(o, c, r, light)
	if kind == "quake":
		_h3_sfx(o, "quake", 0.0, 1.0, 0.1)
	elif kind == "giant" or kind == "exec":
		_h3_sfx(o, "big", -1.0, 1.0, 0.04)
	else:
		_h3_sfx(o, "hit", -3.0 if light else 0.0, 1.0, 0.08)
	var shc: Dictionary = _h4_sub(o, sh)
	if not shc.is_empty() and depth < 1:
		var wd := _h4wd(o)
		for k in mini(killed.size(), 3):
			if wd.shades.size() >= int(sh.get("max", 12)):
				break
			wd.shades.append({"pos": killed[k], "t": 0.25, "dmg": dmg * float(sh.get("mult", 0.4)), "r": r * float(sh.get("r", 0.8)), "depth": depth + 1})
			o.fx({"kind": "h4_shade", "pos": killed[k], "life": 0.3, "col": H4_DARK})


## 落地：Codex 炮击帧条（fx_wisadel_cannon）；缺图保留程序特效（闪光 / 黑烟 / 红环 / 碎片 / 焦痕）
static func h4_impact_fx(o, c: Vector2, r: float, light: bool) -> void:
	var g = o.g
	if o.spawn_fx_sprite("fx_wisadel_cannon", c, r * (1.8 if light else 2.2) / 96.0):
		o.fx({"kind": "h4_scorch", "pos": c, "r": r * 0.7, "life": 1.2, "floor": true})
		return
	o.fx({"kind": "h4_flash", "pos": c, "r": r * 0.7, "life": 0.1})
	o.fx({"kind": "h4_smoke", "pos": c, "r": r * (0.75 if light else 1.0), "life": 0.5, "col": H4_DARK})
	if not light:
		o.fx({"kind": "h4_smoke", "pos": c + Vector2(r * 0.25, -r * 0.2), "r": r * 0.7, "life": 0.6, "col": H4_DARK, "delay": 0.06})
	o.fx({"kind": "ring", "pos": c, "r": r, "r0": r * 0.3, "life": 0.3, "col": H4_RED, "w": 3.0})
	for k in (3 if light else 7):
		var v: Vector2 = Vector2.from_angle(g.vrng.randf() * TAU) * g.vrng.randf_range(90, 210) + Vector2(0, -90)
		o.fx({"kind": "h4_ember", "pos": c, "vel": v, "life": 0.5, "col": Color(0.25, 0.16, 0.18), "sz": 5.0, "ang": g.vrng.randf() * TAU, "spin": 12.0, "grav": 420.0})
	_h3_vsparks(o, c, H4_EMBER, 4 if light else 8, 200.0, 0.3)
	o.fx({"kind": "h4_scorch", "pos": c, "r": r * 0.8, "life": 2.0, "floor": true})


## 饱和炮击 / 凋零处刑的爆炸：Codex 炮击帧条放大；缺图 = 白粉核心星芒 → 放射红刀锋 → 贴地冲击波 + 错落黑烟 → 红色碎刃
static func h4_burst_fx(o, c: Vector2, r: float, small := false) -> void:
	var g = o.g
	var sc: float = 0.7 if small else 1.0
	if o.spawn_fx_sprite("fx_wisadel_cannon", c, r * 2.8 * sc / 96.0):
		o.fx({"kind": "h4_scorch", "pos": c, "r": r * 0.9 * sc, "life": 2.0, "floor": true})
		return
	o.fx({"kind": "h4_burst", "pos": c, "r": r * 1.6 * sc, "life": 0.5 if small else 0.55, "seed": g.vrng.randf() * TAU, "n": 8 if small else 12})
	o.fx({"kind": "ring", "pos": c, "r": r * 1.45 * sc, "r0": r * 0.3, "life": 0.28, "col": H4_RED, "floor": true, "w": 2.5, "alpha": 0.75})
	var n: int = 3 if small else 5
	var seed: float = g.vrng.randf() * TAU
	for q in n:
		var ang: float = seed + q * TAU / n + g.vrng.randf_range(-0.45, 0.45)
		var off: Vector2 = Vector2.from_angle(ang) * r * sc * g.vrng.randf_range(0.3, 0.7)
		off.y *= 0.55
		o.fx({"kind": "h4_smoke", "pos": c + off, "r": r * sc * g.vrng.randf_range(0.32, 0.5), "life": g.vrng.randf_range(0.5, 0.75), "col": H4_DARK, "delay": q * 0.035})
	for k in (5 if small else 8):
		var v: Vector2 = Vector2.from_angle(g.vrng.randf() * TAU) * g.vrng.randf_range(120, 260)
		o.fx({"kind": "h4_sliver", "pos": c, "vel": v, "life": 0.45, "col": H4_BOLT, "sz": g.vrng.randf_range(6.0, 11.0), "ang": v.angle(), "drag": 2.5})
	o.fx({"kind": "h4_scorch", "pos": c, "r": r * 0.9, "life": 2.0, "floor": true})


# ---------------------------------------------------------------- 维什戴尔：画面

static func _h4wd_draw_pfx(o, f: Dictionary, a: float) -> bool:
	var cv = o.cv
	match str(f.kind):
		"h4_muzzle":
			var d: Vector2 = f.dir
			var n: Vector2 = d.orthogonal()
			var L: float = f.sz * (0.6 + 0.4 * a)
			cv.draw_colored_polygon(PackedVector2Array([f.pos + n * 3.0, f.pos + d * L, f.pos - n * 3.0, f.pos - d * 2.0]), Color(H4_RED.r, H4_RED.g, H4_RED.b, 0.7 * a))
			cv.draw_colored_polygon(PackedVector2Array([f.pos + n * 1.4, f.pos + d * L * 0.55, f.pos - n * 1.4]), Color(2.2, 1.2, 0.8, 0.9 * a))
			return true
		"h4_burst":
			var k := 1.0 - a
			var r: float = f.r
			var sd: float = f.seed
			cv.draw_circle(f.pos, r * (0.3 + 0.5 * k), Color(1.3, 0.1, 0.22, 0.4 * a))
			var nq: int = int(f.get("n", 12)) if Dc.hit_spokes() else 0
			for q in nq:
				var h: float = fmod(sd * 7.3 + q * 2.399, 1.0)
				var ang: float = sd + q * TAU / nq + (h - 0.5) * 0.35
				var dv: Vector2 = Vector2.from_angle(ang)
				var nv: Vector2 = dv.orthogonal()
				var L2: float = r * (0.55 + 0.7 * h) * minf(1.0, k * 2.2)
				var w: float = (2.5 + 3.5 * h) * (1.0 - k * 0.7)
				var s0: Vector2 = f.pos + dv * L2 * (0.1 + 0.35 * k)
				var s1: Vector2 = f.pos + dv * L2
				var sm: Vector2 = f.pos + dv * L2 * 0.45
				cv.draw_colored_polygon(PackedVector2Array([s0, sm + nv * w, s1, sm - nv * w]), Color(1.9, 0.1, 0.26, 0.9 * a))
				cv.draw_colored_polygon(PackedVector2Array([s0, sm + nv * w * 0.3, s1, sm - nv * w * 0.3]), Color(2.4, 0.7, 0.8, 0.7 * a))
			var cr: float = r * 0.16 * (1.0 if k < 0.2 else maxf(0.0, 1.0 - (k - 0.2) / 0.45))
			cv.draw_circle(f.pos, cr * 1.8, Color(1.6, 0.1, 0.12, 0.6 * a))
			cv.draw_circle(f.pos, cr, Color(2.2, 0.5, 0.32, a))
			cv.draw_circle(f.pos, cr * 0.45, Color(0.12, 0.02, 0.04, a))
			return true
		"h4_sliver":
			var dv: Vector2 = Vector2.from_angle(f.ang) * f.sz
			var nv: Vector2 = dv.orthogonal().normalized() * 1.6
			cv.draw_colored_polygon(PackedVector2Array([f.pos - dv, f.pos + nv, f.pos + dv, f.pos - nv]), Color(2.2, 0.3, 0.5, a))
			cv.draw_line(f.pos - dv * 0.6, f.pos + dv * 0.6, Color(2.8, 1.4, 1.6, a), 1.0)
			return true
		"h4_flash":
			cv.draw_circle(f.pos, f.r * (0.5 + 0.5 * a), Color(2.0, 0.4, 0.3, 0.75 * a))
			cv.draw_circle(f.pos, f.r * 0.4 * a, Color(2.8, 1.6, 1.2, a))
			return true
		"h4_smoke":
			var age: float = f.max - f.life
			if age < f.get("delay", 0.0):
				return true
			var k := 1.0 - a
			var p: Vector2 = f.pos + Vector2(0, -22.0 * k)
			cv.draw_circle(p, f.r * (0.4 + 0.8 * k), Color(0.14, 0.1, 0.12, 0.6 * a))
			cv.draw_circle(p + Vector2(f.r * 0.25, -f.r * 0.2), f.r * (0.3 + 0.55 * k), Color(0.22, 0.15, 0.17, 0.45 * a))
			cv.draw_circle(p + Vector2(-f.r * 0.2, -f.r * 0.1), f.r * (0.2 + 0.4 * k), Color(0.3, 0.2, 0.22, 0.3 * a))
			return true
		"h4_ember":
			var sv: Vector2 = Vector2.from_angle(f.ang) * f.sz
			cv.draw_colored_polygon(PackedVector2Array([f.pos - sv, f.pos + sv.orthogonal() * 0.45, f.pos + sv]), Color(0.16, 0.08, 0.12, a))
			if not f.get("cold", false):
				cv.draw_circle(f.pos + sv, 1.6, Color(2.0, 0.9, 0.5, a))
			return true
		"h4_scorch":
			cv.draw_set_transform(f.pos, 0.0, Vector2(1.0, 0.5))
			cv.draw_circle(Vector2.ZERO, f.r, Color(0.04, 0.02, 0.03, 0.45 * minf(1.0, a * 2.0)))
			cv.draw_circle(Vector2(f.r * 0.15, 0), f.r * 0.55, Color(0.02, 0.01, 0.02, 0.35 * minf(1.0, a * 2.0)))
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			return true
		"h4_shade":
			var p: Vector2 = f.pos + Vector2(0, -6.0 - 10.0 * (1.0 - a))
			cv.draw_set_transform(p, 0.0, Vector2(1.0, 1.7))
			cv.draw_circle(Vector2.ZERO, 9.0, Color(0.05, 0.03, 0.05, 0.8 * a))
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			cv.draw_circle(p + Vector2(-3, -7), 1.5, Color(2.0, 0.3, 0.3, a))
			cv.draw_circle(p + Vector2(3, -7), 1.5, Color(2.0, 0.3, 0.3, a))
			return true
	return false


## 地面层：落点准星（出膛即出现，随炮弹接近收缩变亮）、余震前兆环
static func _h4wd_draw_floor(o) -> void:
	var cv = o.cv
	var wd: Dictionary = o.hw.wd
	for s in wd.shells:
		var k: float = s.t / s.dur
		var rr: float = lerpf(s.r * 1.5, s.r, k)
		var al: float = 0.25 + 0.55 * k
		cv.draw_set_transform(s.to, 0.0, Vector2(1.0, 0.55))
		cv.draw_arc(Vector2.ZERO, rr, 0.0, TAU, 28, Color(H4_RED.r, H4_RED.g, H4_RED.b, al), 1.5)
		for q in 4:
			var dv := Vector2.from_angle(q * PI / 2.0)
			cv.draw_line(dv * rr * 0.55, dv * rr * 0.85, Color(H4_RED.r, H4_RED.g, H4_RED.b, al), 2.0)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for q in wd.quakes:
		if q.t > 0.45:
			continue
		var a: float = 1.0 - q.t / 0.45
		cv.draw_set_transform(q.pos, 0.0, Vector2(1.0, 0.55))
		cv.draw_arc(Vector2.ZERO, q.r * (0.25 + 0.2 * a), 0.0, TAU, 20, Color(H4_RED.r, H4_RED.g, H4_RED.b, 0.5 * a), 2.0)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 技能上层：彗星弹体（一整条连续轮廓）、残影标记、魂灵之影
static func _h4wd_draw_over(o) -> void:
	var cv = o.cv
	var wd: Dictionary = o.hw.wd
	for s in wd.shells:
		var p: Vector2 = _h4_shell_at(s, s.t / s.dur)
		var pts: Array = []
		for q in s.hist:
			if pts.is_empty() or q.distance_to(pts[-1]) > 1.0:
				pts.append(q)
		if pts.is_empty() or p.distance_to(pts[-1]) > 1.0:
			pts.append(p)
		var wk: float = 1.0 + (float(s.get("size", 1.0)) - 1.0) * 0.6
		if _h4_draw_shell_tex(o, s, p):
			continue
		if pts.size() < 2:
			cv.draw_circle(p, 5.5 * wk, Color(0.16, 0.02, 0.04))
			continue
		cv.draw_colored_polygon(_h4_comet(pts, 11.0 * wk), Color(1.2, 0.08, 0.1, 0.3))
		cv.draw_colored_polygon(_h4_comet(pts, 7.5 * wk), Color(0.34, 0.03, 0.06, 0.95))
		cv.draw_colored_polygon(_h4_comet(pts, 4.0 * wk), Color(0.1, 0.01, 0.03, 1.0))
	_h4wd_draw_marks(o)
	_h4wd_draw_souls(o)


## 魂炮的小炮弹（Codex proj_wisadel_soul_shell，沿飞行方向转）；缺图画小一号的彗星
static func _h4_draw_shell_tex(o, s: Dictionary, p: Vector2) -> bool:
	if str(s.get("kind", "")) != "soul":
		return false
	var g = o.g
	if g.tex.get("proj_wisadel_soul_shell") != null:
		o.draw_spr_rot("proj_wisadel_soul_shell", int(g.t * 20.0) % 2, p, (s.to - s.from).angle(), g.PX)
		return true
	o.cv.draw_circle(p, 6.0, Color(1.0, 0.1, 0.25, 0.3))
	o.cv.draw_circle(p, 3.5, Color(0.2, 0.02, 0.08))
	return true


static func _h4wd_draw_marks(o) -> void:
	var g = o.g
	var cv = o.cv
	for k in o.hw.wd.marks:
		var mk: Dictionary = o.hw.wd.marks[k]
		var e: Dictionary = mk.e
		if e.dead:
			continue
		if mk.t < 0.6 and fmod(mk.t * 8.0, 1.0) < 0.35:
			continue
		var p: Vector2 = e.pos + Vector2(0, -e.r - 18.0 + sin(g.t * 4.0 + e.id) * 2.0)
		cv.draw_circle(p, 9.0, Color(0.9, 0.05, 0.1, 0.18))
		if _h4_draw_gift(o, mk, p):
			continue
		if o._fx_strip("fx_wisadel_mark", 2, int(g.t * 4.0 + e.id * 0.5), p):
			continue
		_h4_shade_body(o, p, 5.5, 0.85)


## 好礼挂的标记：Codex fx_wisadel_gift_mark（比普通标记多一圈礼花状缎带）；缺图画普通标记
static func _h4_draw_gift(o, mk: Dictionary, p: Vector2) -> bool:
	if not mk.get("gift", false):
		return false
	var g = o.g
	return o._fx_strip("fx_wisadel_gift_mark", 6, int(g.t * 10.0 + float(mk.e.id) * 0.5), p)


static func _h4wd_draw_souls(o) -> void:
	var g = o.g
	var cv = o.cv
	var souls: Array = o.hw.wd.souls
	for i in souls.size():
		var s: Dictionary = souls[i]
		var p: Vector2 = s.p
		if _h4_draw_soul_fire(o, s, p):
			continue
		if o._fx_tex("fx_wisadel_soul") != null:
			cv.draw_circle(p, 18.0, Color(1.0, 0.06, 0.12, 0.2 + 0.06 * sin(g.t * 6.0)))
			if str(s.st) == "go":
				var tg = s.tgt
				var fl: bool = tg != null and not tg.dead and tg.pos.x < p.x
				o._fx_strip("fx_wisadel_soul", 6, 4 + mini(1, int((g.t - float(s.get("gt", g.t))) * 12.0)), p, Vector2(0.5, 0.5), 0.0, Color.WHITE, fl)
			else:
				o._fx_strip("fx_wisadel_soul", 6, (int(g.t * 8.0) + i * 2) % 4, p)
			continue
		var tail := PackedVector2Array()
		for q in 5:
			tail.append(p + Vector2(sin(g.t * 5.0 + q * 0.9) * (1.0 + q), 8.0 + q * 4.0))
		cv.draw_polyline(tail, Color(0.08, 0.03, 0.05, 0.7), 5.0)
		cv.draw_circle(p, 18.0, Color(1.0, 0.06, 0.12, 0.2 + 0.06 * sin(g.t * 6.0)))
		_h4_shade_body(o, p, 9.5, 0.95)


## 魂灵之影开火（Codex fx_wisadel_soul_fire 5 帧 16fps：收缩 → 炮口喷暗紫烟）；缺图时照常画悬浮帧
static func _h4_draw_soul_fire(o, s: Dictionary, p: Vector2) -> bool:
	if float(s.get("ft", -1.0)) < 0.0:
		return false
	var g = o.g
	if g.tex.get("fx_wisadel_soul_fire") == null:
		return false
	var tg = s.get("ftg", null)
	var fl: bool = tg != null and not tg.dead and tg.pos.x < p.x
	o.cv.draw_circle(p, 18.0, Color(1.0, 0.06, 0.12, 0.26))
	o._fx_strip("fx_wisadel_soul_fire", 5, mini(4, int(float(s.ft) * 16.0)), p, Vector2(0.5, 0.5), 0.0, Color.WHITE, fl)
	return true


static func _h4_shade_body(o, p: Vector2, r: float, al: float) -> void:
	var cv = o.cv
	cv.draw_set_transform(p, 0.0, Vector2(1.0, 1.7))
	cv.draw_circle(Vector2.ZERO, r, Color(0.05, 0.03, 0.05, al))
	cv.draw_arc(Vector2.ZERO, r, 0.0, TAU, 20, Color(1.2, 0.12, 0.16, 0.8 * al), 1.2)
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var ey: float = -r * 0.75
	cv.draw_circle(p + Vector2(-r * 0.35, ey), maxf(1.2, r * 0.18), Color(2.2, 0.3, 0.3, al))
	cv.draw_circle(p + Vector2(r * 0.35, ey), maxf(1.2, r * 0.18), Color(2.2, 0.3, 0.3, al))


## 彗星轮廓：pts 从尾到头；半宽按 u^1.3 从 0 平滑增到 hw，头部接半圆帽
static func _h4_comet(pts: Array, hw: float) -> PackedVector2Array:
	var n: int = pts.size()
	var L := PackedVector2Array()
	var R := PackedVector2Array()
	for i in n:
		var a0: Vector2 = pts[maxi(i - 1, 0)]
		var a1: Vector2 = pts[mini(i + 1, n - 1)]
		var nv: Vector2 = (a1 - a0).normalized().orthogonal()
		var u: float = float(i) / float(n - 1)
		var w: float = hw * pow(u, 1.3)
		L.append(pts[i] + nv * w)
		R.append(pts[i] - nv * w)
	var head: Vector2 = pts[n - 1]
	var dir: Vector2 = (pts[n - 1] - pts[n - 2]).normalized()
	var out := PackedVector2Array()
	out.append_array(L)
	var a_start: float = dir.orthogonal().angle()
	for k in range(1, 8):
		out.append(head + Vector2.from_angle(a_start + PI * k / 8.0) * hw)
	R.reverse()
	out.append_array(R)
	return out


# ---------------------------------------------------------------- 塞雷娅段（第 4 批续，SA_TAGS）
#  shape.bash       持盾出拳（普攻，手动 A 类）：扇形 r × op_range、半角 half、kb、stun，判定原点 脚底 + (0, y)，伤害 = 攻击 × 加成；
#                   护服（verb.suit）满格时这一拳换成全方位冲击
#  verb.guard_ring  阻挡圈（放 trait 的 passive）：每 every 秒把队长周围 r × op_range 内的非 Boss 敌人推到圈外（kb / 精英 kb_elite）、减速 slow 秒
#  verb.calc_orbs   环绕钙晶（放 passive）：n_by 里第一条 cond 成立的 n 枚绕本干员转（半径 r、角速度 spin），撞到敌人 拳击 × mult（同一敌人 cd 秒一次）；
#                   shatter {cond, every, reach, regrow, mult, n, src}：钙质化以外每 every 秒击碎一枚，碎片飞向附近至多 n 名敌人，regrow 秒后长回
#  verb.saria_heal  为队长回复 pct × 最大生命 × 技能强度（低于 low_hp 时 × low_mult）；cleanse 清寒冷 / 束缚；hot {dur, pct}：之后每秒再回复；
#                   syringe {cond, n, mult, slow, range, speed, src}：同时朝附近敌人掷出注射器（拳击 × mult × 技能强度、减速）
#  verb.calc_field  钙质化：dur 秒以队长为心 r 的琥珀区域（每帧清寒冷 / 束缚、每秒回复 heal、区域内敌人减速 slow 秒 + aura_weak），每 shard_every 秒在区域里长出一根晶柱；
#                   shatter {cond, every, n, mult, src}：每 every 秒击碎一根晶柱，碎片飞向区域内敌人
#  verb.suit        莱茵充能护服（放 passive）：每 seg_t 秒充满一格（共 segs 格），满格后下一次出拳变为全方位冲击（半径 r，拳击 × mult、kb、stun）

static func _h4sa(o) -> Dictionary:
	var h := hw_st(o)
	if not h.has("sa"):
		h["sa"] = {"block_t": 0.0, "calc": 0.0, "calc_acc": 0.0, "shard_t": 0.0, "hot_t": 0.0, "hot_acc": 0.0, "hot_pct": 0.0,
			"orb_cd": {}, "orb_broken": {}, "shatter_t": 0.0, "pillars": [], "shots": [], "seg": 0, "seg_t": 0.0, "calc_b": {},
			"hot_name": "", "calc_name": "", "slowed": [], "crystals": []}
	return h.sa


static func _h4_bash_dmg(o) -> float:
	return o.base(str(o.B.get("attack", {}).get("atk_key", "atk")), 0.0) * o._dmg_bonus()


## 净化：清除队长的寒冷（寒霜层数，满层冻结也一起解开）与束缚；balance.json operators/<id>/cleanse = 0 关掉。show = 清掉了东西时在队长头顶飘「净化」
static func h4_cleanse_ctrl(o, show: bool) -> bool:
	var g = o.g
	if preload("res://scripts/core/balance.gd").v("operators/%s/cleanse" % o.id, 1.0) <= 0.0:
		return false
	if g.cold <= 0 and g.root_t <= 0.0:
		return false
	g.cold = 0
	g.cold_t = 0.0
	g.root_t = 0.0
	g.combat.sync_cold()
	if show:
		o.float_text(g.ppos + Vector2(0, -96), "净化", H4_AMBER, 14)
	return true


static func _h4_bash_start(o, a: Dictionary) -> void:
	if o.cd > 0.0:
		return
	var reach: float = float(a.get("r", 115.0)) * o.stat(&"op_range")
	var at: Vector2 = o.atk_point(o.nearest_enemies(1, reach + 40.0, o.pos), reach)   # 手动普攻 A 类（契约 v2.5）
	if at == Vector2.INF:
		o.cd = o.idle_cd(float(a.get("idle", 0.1)))
	else:
		o.cd = float(a.get("every", 0.9)) / o.stat(&"op_aspd")
		o.start_attack(at)


static func _h4_bash_release(o, a: Dictionary) -> void:
	var g = o.g
	var sa := _h4sa(o)
	var reach: float = float(a.get("r", 115.0)) * o.stat(&"op_range")
	var ts: Array = o.nearest_enemies(1, reach + 40.0, o.pos)
	var ang: float = o.facing_angle()
	if not ts.is_empty():
		ang = (ts[0].pos - o.pos).angle()
		o.face_to(ang)
	ang = o.atk_angle(ang)
	# 莱茵充能护服满格：这一击变成全方位冲击，之后清零重新充能
	var su: Dictionary = _h4_live(o, "verb.suit")
	if not su.is_empty() and int(sa.seg) >= int(su.get("segs", 4)):
		sa.seg = 0
		sa.seg_t = 0.0
		_h4_suit_blast(o, a, su)
		return
	var hits: Array = o.melee_hit(str(a.get("src", "")), o.pos + Vector2(0, float(a.get("y", -10.0))), ang, float(a.get("half", 1.1)), reach, _h4_bash_dmg(o), float(a.get("kb", 200.0)), float(a.get("stun", 0.2)), a.get("tags", []))
	var d := Vector2.from_angle(ang)
	if not o.spawn_fx_sprite("fx_saria_shield_bash", o.pos + Vector2(0, -12) + d * (14.0 + 20.0 * g.PX * 0.9), g.PX * 0.9, ang):
		o.slash_fx(o.pos + Vector2(0, -14), ang, 1.0, reach * 0.8, H4_AMBER)
		o.fx({"kind": "line", "pos": o.pos + Vector2(0, -12) + d * 14.0, "to": o.pos + Vector2(0, -12) + d * reach * 1.3, "life": 0.15, "col": H4_AMBER, "w": 3.0})
	_h3_sfx(o, "hit" if not hits.is_empty() else "atk")
	_h4_bash_after(o, a, hits)   # 精英化第 4 批（钙化拳）的挂点；迁移时没有


## 精一「钙化拳」（docs/91 §10）：拳击命中的非 Boss 敌人 dur 秒内移速 -pct（精英时长 × elite_mult；同一敌人刷新时长取长）。
## 不是减速状态（不写 e.slow、不与其他减速叠）：本干员每帧把这名敌人这一帧朝队长走近的位移退回 pct（被推开 / 击退不打折），同 st.slow_soft 的做法
static func _h4_bash_after(o, a: Dictionary, hits: Array) -> void:
	var cf: Dictionary = _h4_sub(o, a.get("calcify", null))
	if cf.is_empty():
		return
	var g = o.g
	var sa := _h4sa(o)
	for e in hits:
		if e.dead or e.boss:
			continue
		var dur: float = float(cf.get("dur", 2.0)) * (float(cf.get("elite_mult", 0.5)) if e.elite else 1.0)
		var found := false
		for s in sa.slowed:
			if is_same(s.e, e):
				s.until = maxf(float(s.until), g.t + dur)
				s.t0 = g.t
				found = true
				break
		if not found:
			if sa.slowed.size() >= int(cf.get("max", 48)):
				sa.slowed.pop_front()
			sa.slowed.append({"e": e, "until": g.t + dur, "last": e.pos, "t0": g.t, "seed": float(e.id) * 1.37})


## 莱茵充能护服：以自身为中心的全方位冲击；六道琥珀冲击向外撞出 + 两道贴地冲击环
static func _h4_suit_blast(o, a: Dictionary, su: Dictionary) -> void:
	var r: float = float(su.get("r", 110.0))
	var hits: Array = o.melee_hit(str(a.get("src", "")), o.pos + Vector2(0, -6), 0.0, PI, r, _h4_bash_dmg(o) * float(su.get("mult", 1.8)), float(su.get("kb", 320.0)), float(su.get("stun", 0.3)), su.get("tags", ["empowered"]))
	for k in 6:
		o.fx({"kind": "h4_bash", "pos": o.pos + Vector2(0, -14), "ang": k * TAU / 6.0, "reach": r * 0.8, "life": 0.26, "big": true})
	o.fx({"kind": "ring", "pos": o.pos, "r": r, "r0": 16.0, "life": 0.35, "col": H4_AMBER, "floor": true, "w": 4.0})
	o.fx({"kind": "ring", "pos": o.pos, "r": r * 0.7, "r0": 8.0, "life": 0.45, "col": Color(1.6, 1.3, 0.8), "floor": true, "w": 2.0})
	o.fx({"kind": "glow", "pos": o.pos + Vector2(0, -26), "r": 26.0, "life": 0.25, "col": H4_AMBER, "alpha": 0.6})
	_h3_vsparks(o, o.pos + Vector2(0, -16), H4_AMBER, 12, 260.0, 0.4, 2.5, 160.0)
	if not hits.is_empty():
		o.impact_pause(0.05)
	_h3_sfx(o, "hit", 4.0, 0.8)
	_h4_suit_after(o, su)   # 精英化第 4 批（晶柱环）的挂点；迁移时没有


## 精二「晶柱环」（docs/91 §10）：满格冲击后在 r 处（地面椭圆，y × sy）升起 n 根琥珀晶柱 life 秒，柱间连成一圈看不见的墙
static func _h4_suit_after(o, su: Dictionary) -> void:
	var pc: Dictionary = _h4_sub(o, su.get("pillars", null))
	if pc.is_empty() or o.pos == Vector2.INF:
		return
	var sa := _h4sa(o)
	if not sa.crystals.is_empty():
		_h4_pillars_break(o, sa.crystals)
	var n: int = int(pc.get("n", 6))
	var R: float = float(pc.get("r", 110.0))
	var sy: float = float(pc.get("sy", 0.55))
	var posts: Array = []
	for k in n:
		var an: float = float(pc.get("a0", 0.0)) + k * TAU / n
		posts.append(o.pos + Vector2(cos(an) * R, sin(an) * R * sy))
	sa.crystals = {"c": o.pos, "t": 0.0, "life": float(pc.get("life", 2.0)), "posts": posts, "hit": {}, "b": pc}
	_h3_sfx(o, "hit", -2.0, 1.25)


static func _h4_pillars_break(o, cr: Dictionary) -> void:
	var g = o.g
	for p in cr.posts:
		if not o.spawn_fx_sprite("fx_saria_pillar_break", p + Vector2(0, -30), g.PX):
			o.spawn_fx_sprite("fx_rock_burst", p, g.PX * 0.7, 0.0, false, false, Color(1.3, 1.0, 0.6))
			for q in 4:
				o.fx({"kind": "shard", "pos": p + Vector2(0, -24), "vel": Vector2.from_angle(g.vrng.randf() * TAU) * g.vrng.randf_range(70, 140), "life": 0.3, "col": H4_AMBER,
					"sz": g.vrng.randf_range(2.5, 4.0), "ang": g.vrng.randf() * TAU, "spin": g.vrng.randf_range(-14, 14), "grav": 260.0})


static func _h4sa_tick(o, sa: Dictionary, dt: float) -> void:
	var g = o.g
	# 阻挡圈：每 every 秒把队长周围的非 Boss 敌人推到圈外、减速
	var gr: Dictionary = _h4_live(o, "verb.guard_ring")
	if not gr.is_empty():
		sa.block_t = float(sa.block_t) - dt
		if float(sa.block_t) <= 0.0:
			sa.block_t = float(gr.get("every", 0.25))
			var r: float = float(gr.get("r", 62.0)) * o.stat(&"op_range")
			var shown := 0
			for j in o.query_ids(g.ppos, r + 30.0):
				var e: Dictionary = g.enemies[j]
				if e.dead or e.boss or e.chest:
					continue
				var off: Vector2 = e.pos - g.ppos
				if off.length() > r + e.r:
					continue
				e.kb += off.normalized() * (float(gr.get("kb_elite", 80.0)) if e.elite else float(gr.get("kb", 200.0)))
				e.slow = maxf(e.slow, float(gr.get("slow", 0.5)))
				if shown < 4:
					shown += 1
					o.fx({"kind": "glow", "pos": e.pos, "r": 9.0, "life": 0.18, "col": H4_AMBER, "alpha": 0.5, "floor": true})
	var ob: Dictionary = _h4_live(o, "verb.calc_orbs")
	var orb_n: int = _h4_orb_n(o, ob)
	_h4_orbs_tick(o, sa, ob, orb_n, dt)
	_h4_shots_tick(o, sa, dt)
	# 精二 莱茵充能护服：每 seg_t 秒充满一格，满格后等下一次出拳放出
	var su: Dictionary = _h4_live(o, "verb.suit")
	if not su.is_empty() and int(sa.seg) < int(su.get("segs", 4)):
		sa.seg_t = float(sa.seg_t) + dt
		if float(sa.seg_t) >= float(su.get("seg_t", 5.0)):
			sa.seg_t = 0.0
			sa.seg = int(sa.seg) + 1
			o.fx({"kind": "glow", "pos": o.pos + Vector2(-19.5 + (int(sa.seg) - 1) * 13.0, 14), "r": 6.0, "life": 0.25, "col": H4_AMBER, "alpha": 0.7})
	if float(sa.hot_t) > 0.0:
		sa.hot_t = float(sa.hot_t) - dt
		sa.hot_acc = float(sa.hot_acc) + dt
		if float(sa.hot_acc) >= 1.0:
			sa.hot_acc = float(sa.hot_acc) - 1.0
			if g.hp < g.max_hp:
				o.heal_leader(g.max_hp * float(sa.hot_pct), o.display_name())
				o.fx({"kind": "mote", "pos": g.ppos + Vector2(g.vrng.randf_range(-16, 16), -20), "vel": Vector2(0, -35), "life": 0.7, "col": H4_AMBER, "sz": 2.0})
	var shb: Dictionary = _h4_sub(o, ob.get("shatter", null)) if not ob.is_empty() else {}
	if float(sa.calc) > 0.0:
		var cb: Dictionary = sa.calc_b
		var R: float = float(cb.get("r", 180.0))
		sa.calc = float(sa.calc) - dt
		sa.calc_acc = float(sa.calc_acc) + dt
		h4_cleanse_ctrl(o, false)   # 钙质化区域（跟着队长）里持续清除寒冷、束缚
		if float(sa.calc_acc) >= 1.0:
			sa.calc_acc = float(sa.calc_acc) - 1.0
			if g.hp < g.max_hp:
				o.heal_leader(g.max_hp * float(cb.get("heal", 0.01275)), o.display_name())
		for j in o.query_ids(g.ppos, R + 20.0):
			var e2: Dictionary = g.enemies[j]
			if e2.dead or e2.pos.distance_to(g.ppos) > R:
				continue
			e2.slow = maxf(e2.slow, float(cb.get("slow", 0.5)))
			e2["aura_weak"] = maxf(float(e2.get("aura_weak", 0.0)), float(cb.get("weak", 0.2)))
		sa.shard_t = float(sa.shard_t) - dt
		if float(sa.shard_t) <= 0.0:
			sa.shard_t = float(cb.get("shard_every", 0.35))
			var an: float = g.rng.randf() * TAU   # 晶柱落点吃 g.rng（碎晶从晶柱处射出，影响玩法；同手写）
			var rr: float = g.rng.randf_range(R * 0.3, R * 0.95)
			_h4_calcite(o, g.ppos + Vector2(cos(an) * rr, sin(an) * rr * 0.55 + 4.0), g.vrng.randf_range(0.6, 0.85), g.vrng.randf_range(12, 24), 1.2)
		# 碎晶：每 every 秒亲手击碎一根晶柱，碎片飞向区域内的敌人
		var cs: Dictionary = _h4_sub(o, cb.get("shatter", null))
		if not cs.is_empty():
			sa.shatter_t = float(sa.shatter_t) - dt
			if float(sa.shatter_t) <= 0.0 and _h4_shatter(o, sa, cb, cs):
				sa.shatter_t = float(cs.get("every", 1.2))
	else:
		sa.pillars.clear()
		# 碎晶（平时）：每 every 秒击碎一枚环绕钙晶，碎片飞向附近敌人，regrow 秒后重新长出
		if not shb.is_empty() and orb_n > 0:
			sa.shatter_t = float(sa.shatter_t) - dt
			if float(sa.shatter_t) <= 0.0 and _h4_shatter_orb(o, sa, ob, shb, orb_n):
				sa.shatter_t = float(shb.get("every", 3.0))
	_h4sa_tick_e(o, sa, dt)   # 精英化第 4 批（钙化拳减速 / 晶柱环）的挂点；迁移时没有


static func _h4sa_tick_e(o, sa: Dictionary, dt: float) -> void:
	var g = o.g
	if not sa.slowed.is_empty():
		var cf: Dictionary = _h4_sub(o, o.B.get("attack", {}).get("calcify", null))
		var pct: float = float(cf.get("pct", 0.15)) if not cf.is_empty() else 0.0
		for s in sa.slowed:
			var e: Dictionary = s.e
			if e.dead or g.t >= float(s.until):
				continue
			var d: Vector2 = e.pos - s.last
			if pct > 0.0 and d.dot(g.ppos - s.last) > 0.0:
				e.pos -= d * pct
			s.last = e.pos
		sa.slowed = sa.slowed.filter(func(s): return not s.e.dead and g.t < float(s.until))
	if not sa.crystals.is_empty():
		_h4_pillars_tick(o, sa, dt)


static var _h4_pperf = null   # --pillarperf（只计时、不改玩法）：[开着晶柱的帧数, 总微秒, 单帧最大微秒, 查到的敌人数合计]


## 晶柱环每帧：敌人碰到柱子或柱间的墙就沿法线推出去（精英一帧至多推回 elite_push × 自身移速 × dt，所以能慢慢挤过去；Boss / 定点单位不挡，队长和队友不受影响），
## 碰到的敌人受到拳击 × mult（同一敌人 cd 秒一次）。只查环心 r + pr + 40 内的敌人（空间网格），按椭圆环带快速剔除，剩下的每名只算所在扇区的一段墙与两根柱子
static func _h4_pillars_tick(o, sa: Dictionary, dt: float) -> void:
	var g = o.g
	var cr: Dictionary = sa.crystals
	cr.t = float(cr.t) + dt
	var pc: Dictionary = cr.b
	if float(cr.t) >= float(cr.life):
		_h4_pillars_break(o, cr)
		sa.crystals = {}
		return
	if float(cr.t) < float(pc.get("arm", 0.08)) or g.perf_alt:   # 拔起 arm 秒后才挡；--perfab 同局轮换的 /b 桶不挡（量净成本用，正常游戏恒为 false）
		return
	if _h4_pperf == null:
		_h4_pperf = [0, 0, 0, 0] if OS.is_debug_build() and OS.get_cmdline_user_args().has("--pillarperf") else []
	var perf: bool = not _h4_pperf.is_empty()
	var t0: int = Time.get_ticks_usec() if perf else 0
	var posts: Array = cr.posts
	var n: int = posts.size()
	var pr: float = float(pc.get("pr", 14.0))
	var hw: float = float(pc.get("wall", 6.0))
	var c: Vector2 = cr.c
	var R: float = float(pc.get("r", 110.0))
	var sy: float = float(pc.get("sy", 0.55))
	var ek: float = float(pc.get("elite_push", 0.5))
	var band: float = pr + 30.0
	var a0: float = float(pc.get("a0", 0.0))
	var sec: float = TAU / float(n)
	var hits: Array = []
	var ids: Array = o.query_ids(c, R + pr + 40.0)
	var ens: Array = g.enemies
	var rsy: float = R * sy
	for j in ids:
		var e: Dictionary = ens[j]
		if e.dead:
			continue
		var ep: Vector2 = e.pos
		var er: float = e.r
		var rel: Vector2 = ep - c
		var nx: float = rel.x / R
		var ny: float = rel.y / rsy
		if absf(sqrt(nx * nx + ny * ny) - 1.0) * rsy > band + er:   # 离环带太远（椭圆归一化半径，按短轴折回像素，偏宽松）
			continue
		if e.boss or e.ai == "static" or e.get("chest", false):
			continue
		# 只查这名敌人所在扇区的那一段墙与两端的柱子（椭圆归一化后的方位角；跨扇区的拐角由共用的柱子兜住）
		var k: int = posmod(int(floor((atan2(ny, nx) - a0) / sec)), n)
		var a2: Vector2 = posts[k]
		var b2: Vector2 = posts[(k + 1) % n]
		var push := Vector2.ZERO
		var best := 0.0
		var dp: Vector2 = ep - a2
		var lp: float = dp.length()
		var ov: float = pr + er - lp
		if ov > best:
			best = ov
			push = (dp / lp if lp > 0.01 else rel.normalized()) * ov
		var dq: Vector2 = ep - b2
		var lq: float = dq.length()
		ov = pr + er - lq
		if ov > best:
			best = ov
			push = (dq / lq if lq > 0.01 else rel.normalized()) * ov
		if hw >= 0.0:   # wall < 0 = 只有柱子、柱间不挡
			var ab: Vector2 = b2 - a2
			var dw: Vector2 = ep - (a2 + ab * clampf(dp.dot(ab) / ab.length_squared(), 0.0, 1.0))
			var lw: float = dw.length()
			ov = hw + er - lw
			if ov > best:
				best = ov
				push = (dw / lw if lw > 0.01 else rel.normalized()) * ov
		if best <= 0.0:
			continue
		if e.elite:
			push = push.limit_length(ek * float(e.spd) * dt)
		e.pos = ep + push
		hits.append(e)
	var dmg: float = _h4_bash_dmg(o) * float(pc.get("mult", 0.2))
	var hcd: float = float(pc.get("cd", 0.5))
	var hd: Dictionary = cr.hit
	for e in hits:
		if e.dead or float(hd.get(e.id, -1.0)) > g.t:
			continue
		hd[e.id] = g.t + hcd
		o.log_hit(str(pc.get("src", "")))
		o.deal_damage(e, dmg * (o.vs_elite() if e.elite else 1.0))
		o.fx({"kind": "glow", "pos": e.pos + Vector2(0, -float(e.r) * 0.5), "r": 8.0, "life": 0.14, "col": H4_AMBER, "alpha": 0.55})
	if perf:
		var us: int = Time.get_ticks_usec() - t0
		_h4_pperf[0] += 1
		_h4_pperf[1] += us
		_h4_pperf[2] = maxi(int(_h4_pperf[2]), us)
		_h4_pperf[3] += ids.size()
		if int(_h4_pperf[0]) % 600 == 0:
			print("PILLAR_PERF frames=%d total_us=%d avg_us=%.1f max_us=%d avg_checked=%.1f enemies=%d" % [_h4_pperf[0], _h4_pperf[1], float(_h4_pperf[1]) / _h4_pperf[0], _h4_pperf[2], float(_h4_pperf[3]) / _h4_pperf[0], g.enemies.size()])


## 晶柱参与 2.5D 排序（data_operator.extra_bodies 转来）
static func h4_extra_bodies(o) -> Array:
	if not hw_on(o) or not o.hw.has("sa") or o.hw.sa.crystals.is_empty():
		return []
	var out: Array = []
	var posts: Array = o.hw.sa.crystals.posts
	for k in posts.size():
		out.append({"y": (posts[k] as Vector2).y, "h4": "pillar", "k": k})
	return out


## 一根晶柱：拔起帧条播完转站立微光循环（Codex fx_saria_pillar_rise / _idle，底边中点落地）；缺图画程序琥珀晶柱（拔起 0.15 秒，缩放 0 → 1）
static func h4_draw_extra(o, it: Dictionary) -> void:
	var g = o.g
	var cv = o.cv
	var cr: Dictionary = o.hw.sa.crystals
	if cr.is_empty():
		return
	var p: Vector2 = cr.posts[int(it.k)]
	var t: float = float(cr.t)
	var fade: float = clampf((float(cr.life) - t) / 0.12, 0.0, 1.0)
	var col := Color(1, 1, 1, fade)
	var rise_n: int = int(g.V6_FRAMES.get("fx_saria_pillar_rise", [5, 20.0])[0])
	var rise_fps: float = float(g.V6_FRAMES.get("fx_saria_pillar_rise", [5, 20.0])[1])
	if g.tex.get("fx_saria_pillar_rise") != null and t < rise_n / rise_fps:
		fx_frame(cv, g, "fx_saria_pillar_rise", rise_n, int(t * rise_fps), p, g.PX, col, Vector2(8, 32))
		return
	if g.tex.get("fx_saria_pillar_idle") != null:
		var idle: Array = g.V6_FRAMES.get("fx_saria_pillar_idle", [4, 6.0])
		fx_frame(cv, g, "fx_saria_pillar_idle", int(idle[0]), int((t + float(it.k) * 0.13) * float(idle[1])), p, g.PX, col, Vector2(8, 32))
		return
	var grow: float = clampf(t / 0.15, 0.0, 1.0)
	var h: float = 30.0 * (1.0 - (1.0 - grow) * (1.0 - grow))
	var top: Vector2 = p + Vector2(0, -h)
	cv.draw_colored_polygon(PackedVector2Array([p + Vector2(-7, 0), top + Vector2(-3, 4), top, top + Vector2(3, 4), p + Vector2(7, 0), p + Vector2(0, 4)]), Color(H4_AMBER.r, H4_AMBER.g, H4_AMBER.b, 0.9 * fade))
	cv.draw_line(p + Vector2(-4, -1), top + Vector2(-1, 3), Color(1.9, 1.6, 1.0, 0.9 * fade), 1.5)
	cv.draw_circle(top, 2.0, Color(2.2, 2.0, 1.4, fade))


static func _h4_orb_n(o, ob: Dictionary) -> int:
	if ob.is_empty():
		return 0
	for m in ob.get("n_by", []):
		if m is Dictionary and cond_true(o, m.get("cond", {})):
			return int(m.get("n", 0))
	return 0


## 环绕钙晶的地面位置：绕本干员一圈（判定用真实圆，不做贴地压扁）
static func _h4_orb_ground(o, ob: Dictionary, orb_n: int, k: int) -> Vector2:
	var an: float = o.g.t * float(ob.get("spin", 2.2)) + k * TAU / float(maxi(1, orb_n))
	var R: float = float(ob.get("r", 70.0))
	return o.pos + Vector2(cos(an) * R, sin(an) * R + 2.0)


static func _h4_orbs_tick(o, sa: Dictionary, ob: Dictionary, orb_n: int, dt: float) -> void:
	if orb_n <= 0 or o.pos == Vector2.INF:
		return
	var g = o.g
	var cdd: Dictionary = sa.orb_cd
	for k in cdd.keys():
		cdd[k] -= dt
		if cdd[k] <= 0.0:
			cdd.erase(k)
	var dmg: float = _h4_bash_dmg(o) * float(ob.get("mult", 0.18))
	var br: Dictionary = sa.orb_broken
	for k in br.keys():
		br[k] -= dt
		if br[k] <= 0.0:
			br.erase(k)
	for k in orb_n:
		if br.has(k):
			continue
		var p: Vector2 = _h4_orb_ground(o, ob, orb_n, k)
		for j in o.query_ids(p, 40.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or cdd.has(e.id) or e.pos.distance_to(p) > 12.0 + e.r:
				continue
			cdd[e.id] = float(ob.get("cd", 0.5))
			o.log_hit(str(ob.get("src", "")))
			o.deal_damage(e, dmg)
			o.fx({"kind": "glow", "pos": p + Vector2(0, -16), "r": 7.0, "life": 0.14, "col": H4_AMBER, "alpha": 0.6})
			o.fx({"kind": "shard", "pos": p + Vector2(0, -16), "vel": Vector2.from_angle(g.vrng.randf() * TAU) * 90.0, "life": 0.22, "col": H4_AMBER, "sz": 3.0, "ang": g.vrng.randf() * TAU, "spin": 12.0})


## 投射物：直线飞行，碰到第一个敌人即命中；注射器附带减速
static func _h4_shoot(o, sa: Dictionary, kind: String, from: Vector2, to: Vector2, spd: float, dmg: float, src: String, slow := 0.0) -> void:
	if sa.shots.size() >= 12:
		return
	var d: Vector2 = (to - from).normalized() if to.distance_to(from) > 1.0 else Vector2(o.face, 0)
	sa.shots.append({"kind": kind, "pos": from, "vel": d * spd, "t": 0.7, "dmg": dmg, "ang": d.angle(), "src": src, "slow": slow})


static func _h4_shots_tick(o, sa: Dictionary, dt: float) -> void:
	if sa.shots.is_empty():
		return
	var g = o.g
	for s in sa.shots:
		s.t -= dt
		s.pos += s.vel * dt
		var gp: Vector2 = s.pos + Vector2(0, 16)   # 投射物飞在腰高（-16），按地面位置判定
		if g.map.tb_bul and g.map.bullet_blocked(s, gp):   # 地形阻挡：针剂 / 碎晶撞景物底座即消失
			s.t = 0.0
			continue
		for j in o.query_ids(gp, 36.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or e.pos.distance_to(gp) > 6.0 + e.r:
				continue
			o.log_hit(str(s.src))
			o.deal_damage(e, s.dmg)
			if s.kind == "syringe":
				if not e.dead:
					e.slow = maxf(e.slow, float(s.slow))
				o.fx({"kind": "glow", "pos": s.pos, "r": 7.0, "life": 0.18, "col": Color(0.7, 1.2, 0.9), "alpha": 0.6})
			else:
				o.fx({"kind": "glow", "pos": s.pos, "r": 8.0, "life": 0.16, "col": H4_AMBER, "alpha": 0.6})
				for q in 3:
					o.fx({"kind": "shard", "pos": s.pos, "vel": Vector2.from_angle(g.vrng.randf() * TAU) * 110.0, "life": 0.25, "col": H4_AMBER, "sz": 2.5, "ang": g.vrng.randf() * TAU, "spin": 14.0})
			s.t = 0.0
			break
	sa.shots = sa.shots.filter(func(s): return s.t > 0.0)


## 钙质晶体（Codex：冷白主体 + 琥珀边，从地面长出 → 停留 → 碎裂）；缺图退回程序琥珀晶柱。返回该晶柱的特效条目
static func _h4_calcite(o, p: Vector2, sc: float, h: float, life: float) -> Dictionary:
	var g = o.g
	var sa := _h4sa(o)
	var ref: Dictionary = {}
	if o.spawn_fx_sprite("fx_saria_calcite", p, g.PX * sc, 0.0, g.vrng.randf() < 0.5, true):
		ref = g.fx.back()
	else:
		o.fx({"kind": "h4_crystal", "pos": p, "h": h, "life": life, "col": H4_AMBER, "lean": g.vrng.randf_range(-0.3, 0.3)})
		ref = o.pfx.back()
	# 碎晶：钙质化期间记下长出的晶柱，供击碎
	if float(sa.calc) > 0.0 and not _h4_sub(o, sa.calc_b.get("shatter", null)).is_empty():
		sa.pillars.append({"pos": p, "ref": ref})
		if sa.pillars.size() > 12:
			sa.pillars.pop_front()
	return ref


## 碎晶：挑一根已长成的晶柱击碎（g.rng，同手写），碎片飞向区域内最近的至多 n 名敌人；没有目标就先不碎
static func _h4_shatter(o, sa: Dictionary, cb: Dictionary, cs: Dictionary) -> bool:
	var g = o.g
	sa.pillars = sa.pillars.filter(func(pl): return pl.ref.get("life", 0.0) > 0.25)
	if sa.pillars.is_empty():
		return false
	var pl: Dictionary = sa.pillars[g.rng.randi() % sa.pillars.size()]
	var p: Vector2 = pl.pos
	var R: float = float(cb.get("r", 180.0))
	var ts: Array = o.nearest_enemies(8, R * 2.0, p).filter(func(e): return e.pos.distance_to(g.ppos) <= R + e.r)
	if ts.is_empty():
		return false
	ts = o.los_sort(ts, ts.size(), p)   # 地形阻挡：碎片是直线弹，视线内的先
	sa.pillars.erase(pl)
	pl.ref.life = 0.001
	o.fx({"kind": "glow", "pos": p + Vector2(0, -18), "r": 16.0, "life": 0.22, "col": Color(1.8, 1.4, 0.8), "alpha": 0.8})
	o.fx({"kind": "ring", "pos": p, "r": 26.0, "r0": 4.0, "life": 0.25, "col": H4_AMBER, "floor": true, "w": 2.0})
	for q in 8:
		o.fx({"kind": "shard", "pos": p + Vector2(0, -16), "vel": Vector2.from_angle(g.vrng.randf() * TAU) * g.vrng.randf_range(80, 170), "life": 0.35, "col": H4_AMBER,
			"sz": g.vrng.randf_range(3.0, 5.0), "ang": g.vrng.randf() * TAU, "spin": g.vrng.randf_range(-14, 14), "grav": 260.0})
	var dmg: float = _h4_bash_dmg(o) * float(cs.get("mult", 0.6)) * o.skill_power()
	for k in mini(int(cs.get("n", 4)), ts.size()):
		_h4_shoot(o, sa, "shard", p + Vector2(0, -16), ts[k].pos + Vector2(0, -16), 560.0, dmg, str(cs.get("src", "")))
	_h3_sfx(o, "hit", -2.0, 1.3)
	return true


## 碎晶（平时）：挑离最近敌人最近的一枚完好钙晶击碎，碎片飞向附近至多 n 名敌人；没有目标就先不碎
static func _h4_shatter_orb(o, sa: Dictionary, ob: Dictionary, shb: Dictionary, orb_n: int) -> bool:
	var g = o.g
	var ts: Array = o.nearest_enemies(6, float(shb.get("reach", 260.0)), o.pos)
	if ts.is_empty():
		return false
	var best := -1
	var bd := INF
	for k in orb_n:
		if sa.orb_broken.has(k):
			continue
		var d: float = _h4_orb_ground(o, ob, orb_n, k).distance_to(ts[0].pos)
		if d < bd:
			bd = d
			best = k
	if best < 0:
		return false
	sa.orb_broken[best] = float(shb.get("regrow", 1.0))
	var p: Vector2 = _h4_orb_ground(o, ob, orb_n, best) + Vector2(0, -16)
	ts = o.los_sort(ts, ts.size(), _h4_orb_ground(o, ob, orb_n, best))
	o.fx({"kind": "glow", "pos": p, "r": 12.0, "life": 0.2, "col": Color(1.8, 1.4, 0.8), "alpha": 0.8})
	for q in 6:
		o.fx({"kind": "shard", "pos": p, "vel": Vector2.from_angle(g.vrng.randf() * TAU) * g.vrng.randf_range(80, 150), "life": 0.3, "col": H4_AMBER,
			"sz": g.vrng.randf_range(2.5, 4.0), "ang": g.vrng.randf() * TAU, "spin": g.vrng.randf_range(-14, 14), "grav": 260.0})
	var dmg: float = _h4_bash_dmg(o) * float(shb.get("mult", 0.4))
	for k in mini(int(shb.get("n", 3)), ts.size()):
		_h4_shoot(o, sa, "shard", p, ts[k].pos + Vector2(0, -16), 560.0, dmg, str(shb.get("src", "")))
	_h3_sfx(o, "hit", -4.0, 1.4)
	return true


## 治疗画面：飘字 + 光点 + 治疗光环 + 星光（她自己是队长时光环不画、星光挪到头顶，免得盖住注射动作）
static func _h4_heal_fx(o, h: float) -> void:
	var g = o.g
	o.float_text(g.ppos + Vector2(0, -90), "+%d" % int(h), H4_AMBER, 16)
	for k in 6:
		o.fx({"kind": "mote", "pos": g.ppos + Vector2(g.vrng.randf_range(-20, 20), g.vrng.randf_range(-40, -10)), "vel": Vector2(0, -35), "life": 0.8, "col": H4_AMBER, "sz": 2.5})
	var me: bool = o.is_leader
	if not me:
		o.spawn_fx_sprite("fx_heal_aura_amber", g.ppos + Vector2(0, 6), g.PX * 1.4, 0.0, false, true)
	o.spawn_fx_sprite("fx_holy_impact", g.ppos + Vector2(0, -72 if me else -34), g.PX * (0.7 if me else 1.0), 0.0, false, false, Color(1, 1, 1, 0.6 if me else 1.0))


## 急救 / 药剂散布
static func h4_saria_heal(o, b: Dictionary) -> void:
	var g = o.g
	var sa := _h4sa(o)
	var h: float = g.max_hp * float(b.get("pct", 0.068)) * o.skill_power() * (float(b.get("low_mult", 1.0)) if g.hp < g.max_hp * float(b.get("low_hp", 0.0)) else 1.0)
	o.heal_leader(h, o.display_name())
	_h4_heal_fx(o, h)
	if b.get("cleanse", false):
		h4_cleanse_ctrl(o, true)
	o.fx({"kind": "ring", "pos": g.ppos, "r": float(b.get("ring", 40.0)), "r0": 8.0 if float(b.get("ring", 40.0)) < 50.0 else 10.0, "life": 0.4 if float(b.get("ring", 40.0)) < 50.0 else 0.5, "col": H4_AMBER, "floor": true})
	var sy: Dictionary = _h4_sub(o, b.get("syringe", null))
	if not sy.is_empty():
		var dmg: float = _h4_bash_dmg(o) * float(sy.get("mult", 0.8)) * o.skill_power()
		for e in o.los_targets(int(sy.get("n", 3)), float(sy.get("range", 260.0)), o.pos):
			_h4_shoot(o, sa, "syringe", o.pos + Vector2(8.0 * o.face, -24), e.pos + Vector2(0, -16), float(sy.get("speed", 460.0)), dmg, str(sy.get("src", "")), float(sy.get("slow", 2.0)))
	var hot = b.get("hot", null)
	if hot is Dictionary:
		sa.hot_t = float(hot.get("dur", 5.0))
		sa.hot_acc = 0.0
		sa.hot_pct = float(hot.get("pct", 0.0085))
		sa.hot_name = str(hot.get("name", ""))
		if o.is_leader:
			o.fx({"kind": "glow", "pos": g.ppos + Vector2(0, -74), "r": 12.0, "life": 0.35, "col": H4_AMBER, "alpha": 0.6})
		else:
			o.spawn_fx_sprite("fx_shield_amber", g.ppos + Vector2(0, -26), g.PX * 1.6)


## 钙质化：晶柱升起 + 区域
static func h4_calc_start(o, b: Dictionary) -> void:
	var g = o.g
	var sa := _h4sa(o)
	sa.calc_b = b
	sa.calc = float(b.get("dur", 8.0))
	sa.calc_acc = 0.0
	sa.calc_name = str(b.get("name", ""))
	if o.cur_skill >= 0:
		o.s_dur[o.cur_skill] = float(b.get("dur", 8.0))
	for k in 8:
		var an: float = k * TAU / 8.0 + 0.3
		_h4_calcite(o, g.ppos + Vector2(cos(an) * 34.0, sin(an) * 34.0 * 0.55 + 4.0), g.vrng.randf_range(0.9, 1.15), g.vrng.randf_range(22, 40), 1.5 + k * 0.03)
	var R: float = float(b.get("r", 180.0))
	o.fx({"kind": "ring", "pos": g.ppos, "r": R, "r0": 30.0, "life": 0.5, "col": H4_AMBER, "floor": true, "w": 4.0})
	o.fx({"kind": "crack", "pos": g.ppos, "r": 90.0, "life": 0.45, "col": H4_AMBER, "floor": true, "n": 10})
	o.spawn_fx_sprite("fx_holy_pillar_amber", g.ppos + Vector2(0, 6), g.PX * 1.5, 0.0, false, true)
	o.spawn_fx_sprite("fx_circle_amber", g.ppos + Vector2(0, 6), g.PX * 3.0)
	if b.has("banner"):
		o.show_banner(str(b.banner))
	g.shake = maxf(g.shake, 3.0)


# ---------------------------------------------------------------- 塞雷娅：画面

static func _h4sa_draw_auras(o) -> void:
	var g = o.g
	var cv = o.cv
	var sa: Dictionary = o.hw.sa
	var c: Vector2 = g.ppos + Vector2(0, 4)
	if float(sa.calc) > 0.0:
		var R: float = float(sa.calc_b.get("r", 180.0))
		var fade: float = clampf(float(sa.calc) / 0.6, 0.0, 1.0)
		cv.draw_set_transform(c, 0.0, Vector2(1.0, 0.55))
		cv.draw_circle(Vector2.ZERO, R, Color(H4_AMBER.r, H4_AMBER.g, H4_AMBER.b, 0.08 * fade))
		cv.draw_arc(Vector2.ZERO, R, 0.0, TAU, 48, Color(H4_AMBER.r, H4_AMBER.g, H4_AMBER.b, 0.45 * fade), 2.5)
		for k in 6:
			var dv := Vector2.from_angle(k * TAU / 6.0 + g.t * 0.3)
			cv.draw_line(dv * R * 0.85, dv * R, Color(1.6, 1.3, 0.8, 0.6 * fade), 2.0)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var gr: Dictionary = _h4_live(o, "verb.guard_ring")
	if gr.is_empty():
		return
	var r: float = float(gr.get("r", 62.0)) * o.stat(&"op_range")
	cv.draw_set_transform(c, 0.0, Vector2(1.0, 0.55))
	for k in 8:
		var a0: float = g.t * 0.6 + k * TAU / 8.0
		cv.draw_arc(Vector2.ZERO, r, a0, a0 + TAU / 8.0 * 0.55, 6, Color(H4_AMBER.r, H4_AMBER.g, H4_AMBER.b, 0.35 + 0.06 * sin(g.t * 4.0)), 2.0)
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 角色之上：环绕钙晶、注射器 / 碎晶片、护服充能格
static func _h4sa_draw_over(o) -> void:
	if o.pos == Vector2.INF:
		return
	var g = o.g
	var cv = o.cv
	var sa: Dictionary = o.hw.sa
	var ob: Dictionary = _h4_live(o, "verb.calc_orbs")
	var orb_n: int = _h4_orb_n(o, ob)
	for k in orb_n:
		if sa.orb_broken.has(k):
			continue
		var gp: Vector2 = _h4_orb_ground(o, ob, orb_n, k)
		var back: bool = gp.y < o.pos.y + 2.0
		var p: Vector2 = gp + Vector2(0, -16 + sin(g.t * 3.0 + k) * 2.0)
		var al: float = 0.6 if back else 1.0
		cv.draw_set_transform(gp, 0.0, Vector2(1.0, 0.45))
		cv.draw_circle(Vector2.ZERO, 5.0, Color(0.0, 0.0, 0.0, 0.25 * al))
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		cv.draw_circle(p, 8.0, Color(H4_AMBER.r, H4_AMBER.g, H4_AMBER.b, 0.18 * al))
		var dia := PackedVector2Array([p + Vector2(0, -9), p + Vector2(4.5, -1), p + Vector2(0, 6), p + Vector2(-4.5, -1)])
		cv.draw_colored_polygon(dia, Color(1.35, 1.3, 1.15, 0.9 * al))
		cv.draw_polyline(PackedVector2Array([dia[0], dia[1], dia[2], dia[3], dia[0]]), Color(H4_AMBER.r * 1.5, H4_AMBER.g * 1.3, H4_AMBER.b, al), 1.5)
		cv.draw_line(p + Vector2(0, -7), p + Vector2(0, 4), Color(2.2, 2.0, 1.6, 0.8 * al), 1.0)
	for s in sa.shots:
		var d: Vector2 = Vector2.from_angle(s.ang)
		if s.kind == "syringe":
			cv.draw_line(s.pos - d * 7.0, s.pos + d * 4.0, Color(0.1, 0.1, 0.12, 0.8), 5.0)
			cv.draw_line(s.pos - d * 6.0, s.pos + d * 3.0, Color(1.6, 1.6, 1.6), 3.0)
			cv.draw_line(s.pos - d * 2.0, s.pos + d * 3.0, Color(0.6, 1.5, 0.9), 2.0)
			cv.draw_line(s.pos + d * 4.0, s.pos + d * 9.0, Color(2.0, 2.0, 2.0), 1.0)
			cv.draw_line(s.pos - d * 8.0 + d.orthogonal() * 3.0, s.pos - d * 8.0 - d.orthogonal() * 3.0, Color(1.4, 1.4, 1.4), 1.5)
		else:
			var sv: Vector2 = Vector2.from_angle(s.ang + g.t * 16.0) * 5.0
			cv.draw_line(s.pos - d * 14.0, s.pos, Color(H4_AMBER.r, H4_AMBER.g, H4_AMBER.b, 0.35), 2.0)
			cv.draw_colored_polygon(PackedVector2Array([s.pos - sv, s.pos + sv.orthogonal() * 0.5, s.pos + sv]), Color(1.9, 1.5, 0.9))
	var su: Dictionary = _h4_live(o, "verb.suit")
	if not su.is_empty():
		var segs: int = int(su.get("segs", 4))
		var full: bool = int(sa.seg) >= segs
		var pul: float = 0.75 + 0.25 * sin(g.t * 10.0) if full else 1.0
		for k in segs:
			var r := Rect2(o.pos + Vector2(-25.0 + k * 13.0, 12.0), Vector2(11.0, 5.0))
			cv.draw_rect(r.grow(1.0), Color(0.12, 0.07, 0.03, 0.85))
			if k < int(sa.seg):
				cv.draw_rect(r, Color(H4_AMBER.r * 1.6 * pul, H4_AMBER.g * 1.4 * pul, H4_AMBER.b * pul))
			elif k == int(sa.seg):
				var fr: float = clampf(float(sa.seg_t) / float(su.get("seg_t", 5.0)), 0.0, 1.0)
				cv.draw_rect(Rect2(r.position, Vector2(11.0 * fr, 5.0)), Color(H4_AMBER.r, H4_AMBER.g, H4_AMBER.b, 0.45))
		if full:
			cv.draw_arc(o.pos + Vector2(0, -30), 26.0 + 2.0 * sin(g.t * 10.0), 0.0, TAU, 28, Color(H4_AMBER.r * 1.5, H4_AMBER.g * 1.3, H4_AMBER.b, 0.35), 2.0)


static func _h4sa_draw_pfx(o, f: Dictionary, a: float) -> bool:
	var cv = o.cv
	match str(f.kind):
		"h4_bash":
			var u: float = 1.0 - a
			var ek: float = 1.0 - (1.0 - minf(1.0, u / 0.6)) * (1.0 - minf(1.0, u / 0.6))
			var d: Vector2 = Vector2.from_angle(f.ang)
			var big: bool = f.get("big", false)
			var R: float = 30.0 if big else 24.0
			var half: float = 1.05 if not big else 0.5
			var c: Vector2 = f.pos + d * (10.0 + f.reach * 0.45 * ek)
			var oc: Vector2 = c - d * R
			var w: float = (9.0 if big else 7.0) * (0.55 + 0.45 * a)
			cv.draw_arc(oc, R, f.ang - half, f.ang + half, 14, Color(0.25, 0.14, 0.05, 0.75 * a), w + 3.0)
			cv.draw_arc(oc, R, f.ang - half, f.ang + half, 14, Color(H4_AMBER.r * 1.3, H4_AMBER.g * 1.2, H4_AMBER.b, 0.95 * a), w)
			cv.draw_arc(oc, R + w * 0.4, f.ang - half * 0.85, f.ang + half * 0.85, 12, Color(2.2, 1.9, 1.3, a), 1.5)
			cv.draw_line(c - d * 2.0, c - d * (w + 2.0), Color(2.0, 1.7, 1.1, 0.8 * a), 2.0)
			for s in [-1.0, 0.0, 1.0]:
				var off: Vector2 = d.orthogonal() * s * R * 0.55
				cv.draw_line(c - d * 10.0 + off, c - d * (22.0 + 6.0 * absf(s)) + off, Color(H4_AMBER.r * 1.4, H4_AMBER.g * 1.3, H4_AMBER.b, 0.5 * a), 1.5)
			return true
		"h4_crystal":
			var age: float = f.max - f.life
			var grow: float = clampf(age / 0.25, 0.0, 1.0)
			var fade: float = clampf(f.life / 0.4, 0.0, 1.0)
			var h: float = f.h * (1.0 - (1.0 - grow) * (1.0 - grow))
			var p: Vector2 = f.pos
			var top: Vector2 = p + Vector2(f.lean * h, -h)
			cv.draw_colored_polygon(PackedVector2Array([p + Vector2(-5, 0), top + Vector2(-2, 2), top, top + Vector2(2, 3), p + Vector2(5, 0), p + Vector2(0, 3)]), Color(H4_AMBER.r, H4_AMBER.g, H4_AMBER.b, 0.85 * fade))
			cv.draw_line(p + Vector2(-3, -1), top + Vector2(-1, 2), Color(1.9, 1.6, 1.0, 0.9 * fade), 1.5)
			cv.draw_circle(top, 2.0, Color(2.2, 2.0, 1.4, fade))
			return true
	return false


# ---------------------------------------------------------------- 画面分发（hw_draw_* 转来）

static func h4_draw_pfx(o, f: Dictionary, a: float) -> bool:
	if not h4_on(o):
		return false
	if o.hw.has("sg") and _h4sg_draw_pfx(o, f, a):
		return true
	if o.hw.has("wd") and _h4wd_draw_pfx(o, f, a):
		return true
	if o.hw.has("sa") and _h4sa_draw_pfx(o, f, a):
		return true
	return _h4e_draw_pfx(o, f, a)


## 精英化第 4 批的程序粒子：h4_spike（岩刺缺图回退：拔起 → 停 → 缩回的金色尖刺）
static func _h4e_draw_pfx(o, f: Dictionary, a: float) -> bool:
	if str(f.kind) != "h4_spike":
		return false
	var cv = o.cv
	var u: float = 1.0 - a
	var k: float = minf(1.0, u / 0.25) if u < 0.6 else maxf(0.0, 1.0 - (u - 0.6) / 0.4)
	var h: float = float(f.h) * k
	if h < 2.0:
		return true
	var p: Vector2 = f.pos
	cv.draw_colored_polygon(PackedVector2Array([p + Vector2(-6, 0), p + Vector2(0, -h), p + Vector2(6, 0)]), Color(1.1, 0.8, 0.4, 0.95))
	cv.draw_colored_polygon(PackedVector2Array([p + Vector2(-2, 0), p + Vector2(0, -h * 0.85), p + Vector2(2, 0)]), Color(2.2, 1.8, 0.9, 0.9))
	return true


static func h4_draw_over(o) -> void:
	if o.hw.has("sz"):
		_h4sz_draw_over(o)
	if o.hw.has("wd"):
		_h4wd_draw_over(o)
	if o.hw.has("sa"):
		_h4sa_draw_over(o)
	_h4e_draw_over(o)


## 精英化第 4 批的上层画面：铃兰狐火拖尾、塞雷娅钙化拳的琥珀斑
static func _h4e_draw_over(o) -> void:
	var g = o.g
	var cv = o.cv
	if o.hw.has("sz") and not o.hw.sz.trails.is_empty():
		var tr: Dictionary = o.B.get("attack", {}).get("merge", {}).get("trail", {})
		var tn: String = str(tr.get("tex", "fx_suzuran_bigfox_trail"))
		var life: float = float(tr.get("life", 1.0))
		var spec: Array = g.V6_FRAMES.get(tn, [5, 12.0])
		var has_tex: bool = g.tex.get(tn) != null
		for tg in o.hw.sz.trails:
			var i := 0
			for q in tg.pts:
				var u: float = clampf(1.0 - float(q.t) / life, 0.0, 1.0)
				if has_tex:
					fx_frame(cv, g, tn, int(spec[0]), mini(int(spec[0]) - 1, int(u * int(spec[0]))), q.pos + Vector2(0, -4), g.PX, Color(1, 1, 1, 0.95))
				elif not o._fx_strip("fx_suzuran_wisp", 4, int(g.t * 8.0) + i, q.pos + Vector2(0, -6), Vector2(0.5, 0.5), 0.0, Color(1, 1, 1, 1.0 - u)):
					_h4_flame(o, q.pos + Vector2(0, 4), 12.0 * (1.0 - 0.5 * u), 1.0 - u)
				i += 1
	if o.hw.has("sa") and not o.hw.sa.slowed.is_empty():
		var cf: Dictionary = o.B.get("attack", {}).get("calcify", {})
		var tn2: String = str(cf.get("tex", "fx_saria_amber_spot"))
		var spec2: Array = g.V6_FRAMES.get(tn2, [4, 8.0])
		var has2: bool = g.tex.get(tn2) != null
		for s in o.hw.sa.slowed:
			var e: Dictionary = s.e
			var left: float = float(s.until) - g.t
			var age: float = g.t - float(s.t0)
			var fr: int = 0 if age < 0.12 else (1 if left > 0.4 else (2 if left > 0.2 else 3))   # 出现 → 停在中间帧 → 最后 0.4 秒淡出
			for q in 2:
				var sd: float = float(s.seed) + q * 2.1
				var off := Vector2(sin(sd) * float(e.r) * 0.55, -float(e.r) * (0.35 + 0.4 * fmod(sd * 0.7, 1.0)))
				if has2:
					fx_frame(cv, g, tn2, int(spec2[0]), fr, e.pos + off, g.PX * 0.8, Color(1, 1, 1, clampf(left / 0.4, 0.0, 1.0)))
				else:
					cv.draw_circle(e.pos + off, 2.5, Color(H4_AMBER.r * 1.5, H4_AMBER.g * 1.3, H4_AMBER.b, 0.85 * clampf(left / 0.4, 0.0, 1.0)))


static func h4_draw_floor(o) -> void:
	if o.hw.has("sg"):
		_h4sg_draw_floor(o)
	if o.hw.has("sz"):
		_h4sz_draw_floor(o)
	if o.hw.has("wd"):
		_h4wd_draw_floor(o)
	_h4e_draw_floor(o)


## 精英化第 4 批的地面画面：塞雷娅晶柱之间一圈淡琥珀墙脚（看得出哪里挡路）
static func _h4e_draw_floor(o) -> void:
	if not o.hw.has("sa") or o.hw.sa.crystals.is_empty():
		return
	var g = o.g
	var cv = o.cv
	var cr: Dictionary = o.hw.sa.crystals
	var t: float = float(cr.t)
	var al: float = clampf(t / 0.15, 0.0, 1.0) * clampf((float(cr.life) - t) / 0.2, 0.0, 1.0)
	var posts: Array = cr.posts
	var n: int = posts.size()
	if float(cr.b.get("wall", 6.0)) < 0.0:
		return
	for k in n:
		var a2: Vector2 = posts[k]
		var b2: Vector2 = posts[(k + 1) % n]
		cv.draw_line(a2, b2, Color(H4_AMBER.r, H4_AMBER.g, H4_AMBER.b, 0.16 * al), 7.0)
		cv.draw_line(a2, b2, Color(1.6, 1.25, 0.7, (0.32 + 0.08 * sin(g.t * 8.0 + k)) * al), 1.5)


static func h4_draw_auras(o) -> void:
	if o.hw.has("sg"):
		_h4sg_draw_auras(o)
	if o.hw.has("sz"):
		_h4sz_draw_auras(o)
	if o.hw.has("sa"):
		_h4sa_draw_auras(o)


# ---------------------------------------------------------------- 本段的校验

static func _h4_block(b: Dictionary, p: String, kind: String, ctx: Dictionary, tag: String) -> bool:
	if not tag in H4_TAGS:
		return false
	var errs: Array = ctx.errs
	var where_ok := {
		"shape.hammer": ["attack"], "shape.foxfire": ["attack"], "shape.cannon": ["attack"], "shape.bash": ["attack"],
		"verb.leap_slam": ["skill", "instant"], "verb.cmd_wave": ["skill", "instant"], "verb.fox_cast": ["skill", "instant"],
		"verb.cannon_exec": ["skill", "instant"], "verb.cannon_load": ["skill", "instant"], "verb.saria_heal": ["skill", "instant"], "verb.calc_field": ["skill", "instant"],
		"verb.foxlight": ["sustain"], "verb.souls": ["sustain"], "verb.guard_ring": ["sustain"], "verb.calc_orbs": ["sustain"], "verb.suit": ["sustain"],
	}
	if not kind in where_ok[tag]:
		errs.append("%s：「%s」不能放在这里（%s；只能在 %s）" % [p, tag, kind, " / ".join(where_ok[tag])])
		return true
	match tag:
		"shape.hammer":
			_num(b, "r", p, ctx, true, 1.0, 600.0)
			_num(b, "half", p, ctx, true, 0.05, PI)
			_num(b, "hit_sp", p, ctx, false, 0.0, 10.0)
			_src(b, p, ctx, true)
			for k in ["quake", "breach"]:
				if b.has(k):
					if not (b[k] is Dictionary):
						errs.append("%s.%s 必须是对象" % [p, k])
					else:
						_src(b[k], p + "." + k, ctx, true)
						_num(b[k], "mult", p + "." + k, ctx, true, 0.0, 20.0)
			if b.has("heavy") and not (b.heavy is Dictionary and b.heavy.has("cond")):
				errs.append(p + ".heavy 必须是带 cond 的对象")
			if b.has("heavy") and b.heavy is Dictionary and b.heavy.has("anim") and not (ctx.sprites is Dictionary and ctx.sprites.has(str(b.heavy.anim))):
				errs.append("%s.heavy.anim「%s」不是 sprites 里的帧条键" % [p, str(b.heavy.anim)])
			_h4e_check(b, p, ctx, tag)
		"verb.leap_slam":
			for k in ["r", "mult", "t", "dist"]:
				_num(b, k, p, ctx, true, 0.0, 1000.0)
			_src(b, p, ctx, true)
		"verb.cmd_wave":
			for k in ["r", "dur", "mult"]:
				_num(b, k, p, ctx, true, 0.0, 1000.0)
			_src(b, p, ctx, true)
		"shape.foxfire":
			_num(b, "range", p, ctx, true, 10.0, 2000.0)
			_num(b, "shots", p, ctx, true, 1.0, 12.0)
			_num(b, "speed", p, ctx, true, 10.0, 3000.0)
			_src(b, p, ctx, true)
			if b.has("merge") and not (b.merge is Dictionary and b.merge.has("mult")):
				errs.append(p + ".merge 必须是对象 {cond, every, all, mult, spd, life, r}")
			if b.has("tip") and not (b.tip is Array and b.tip.size() == 2):
				errs.append(p + ".tip 必须是 [x, y]")
			_h4e_check(b, p, ctx, tag)
		"verb.foxlight":
			_num(b, "r", p, ctx, true, 1.0, 1000.0)
			for k in ["slow", "heal"]:
				if b.has(k) and not (b[k] is Array):
					errs.append("%s.%s 必须是数组" % [p, k])
			if b.has("hearth") and b.hearth is Dictionary:
				_src(b.hearth, p + ".hearth", ctx, true)
		"verb.fox_cast":
			_num(b, "buff", p, ctx, true, 0.0, 5.0)
			_num(b, "haze", p, ctx, false, 0.1, 60.0)
		"shape.cannon":
			_num(b, "range", p, ctx, true, 10.0, 2000.0)
			_num(b, "aoe", p, ctx, true, 1.0, 400.0)
			_src(b, p, ctx, true)
			for k in ["quake_src"]:
				if not ctx.srcs.has(str(b.get(k, ""))):
					errs.append("%s.%s「%s」没在 hit_sources 里登记" % [p, k, str(b.get(k, ""))])
			if b.has("shade") and b.shade is Dictionary:
				_src(b.shade, p + ".shade", ctx, true)
			if b.has("giant") and b.giant is Dictionary:
				_src(b.giant, p + ".giant", ctx, true)
			_h4e_check(b, p, ctx, tag)
		"verb.cannon_exec":
			_num(b, "mult", p, ctx, true, 0.0, 20.0)
			_src(b, p, ctx, true)
		"verb.cannon_load":
			_num(b, "n", p, ctx, true, 1.0, 60.0)
		"verb.souls":
			_num(b, "n", p, ctx, true, 1.0, 6.0)
			_num(b, "cd", p, ctx, not b.get("follow", false), 0.1, 60.0)
			_h4e_check(b, p, ctx, tag)
		"shape.bash":
			_num(b, "r", p, ctx, true, 1.0, 600.0)
			_src(b, p, ctx, true)
			_h4e_check(b, p, ctx, tag)
		"verb.guard_ring":
			_num(b, "r", p, ctx, true, 1.0, 400.0)
			_num(b, "every", p, ctx, true, 0.05, 10.0)
		"verb.calc_orbs":
			if not (b.get("n_by", null) is Array):
				errs.append(p + ".n_by 必须是数组 [{cond, n}]")
			_src(b, p, ctx, true)
		"verb.saria_heal":
			_num(b, "pct", p, ctx, true, 0.0, 1.0)
			if b.has("syringe") and b.syringe is Dictionary:
				_src(b.syringe, p + ".syringe", ctx, true)
		"verb.calc_field":
			_num(b, "dur", p, ctx, true, 0.1, 60.0)
			_num(b, "r", p, ctx, true, 1.0, 1000.0)
			if b.has("shatter") and b.shatter is Dictionary:
				_src(b.shatter, p + ".shatter", ctx, true)
		"verb.suit":
			_num(b, "seg_t", p, ctx, true, 0.1, 60.0)
			_num(b, "r", p, ctx, true, 1.0, 1000.0)
			_num(b, "mult", p, ctx, true, 0.0, 20.0)
			_h4e_check(b, p, ctx, tag)
	return true


## 精英化第 4 批的参数校验（迁移时没有）
static func _h4e_check(b: Dictionary, p: String, ctx: Dictionary, tag: String) -> void:
	var errs: Array = ctx.errs
	var subs := {"shape.hammer": ["crush"], "shape.foxfire": ["brand"], "shape.cannon": ["gift"], "shape.bash": ["calcify"], "verb.souls": ["fire"], "verb.suit": ["pillars"]}
	for k in subs.get(tag, []):
		if b.has(k) and not (b[k] is Dictionary and b[k].has("cond")):
			errs.append("%s.%s 必须是带 cond 的对象" % [p, k])
	match tag:
		"shape.hammer":
			if b.get("crush", null) is Dictionary:
				_src(b.crush, p + ".crush", ctx, true)
				_num(b.crush, "r", p + ".crush", ctx, true, 1.0, 400.0)
				_num(b.crush, "mult", p + ".crush", ctx, true, 0.0, 10.0)
				_num(b.crush, "cap", p + ".crush", ctx, false, 1.0, 12.0)
			var br = b.get("breach", null)
			if br is Dictionary and br.get("spikes", null) is Dictionary:
				_num(br.spikes, "step", p + ".breach.spikes", ctx, true, 8.0, 400.0)
		"shape.foxfire":
			if b.get("brand", null) is Dictionary:
				_num(b.brand, "value", p + ".brand", ctx, true, 0.0, 1.0)
				_num(b.brand, "dur", p + ".brand", ctx, true, 0.1, 10.0)
			var mg = b.get("merge", null)
			if mg is Dictionary and mg.has("trail"):
				if not (mg.trail is Dictionary and mg.trail.has("cond")):
					errs.append(p + ".merge.trail 必须是带 cond 的对象")
				else:
					_src(mg.trail, p + ".merge.trail", ctx, true)
					for k in ["life", "every", "mult", "r", "step"]:
						_num(mg.trail, k, p + ".merge.trail", ctx, true, 0.0, 100.0)
		"shape.cannon":
			if b.get("gift", null) is Dictionary:
				_num(b.gift, "mult", p + ".gift", ctx, true, 0.0, 10.0)
		"verb.souls":
			if b.get("fire", null) is Dictionary:
				_src(b.fire, p + ".fire", ctx, true)
				_num(b.fire, "every", p + ".fire", ctx, not b.get("follow", false), 0.1, 60.0)
				_num(b.fire, "mult", p + ".fire", ctx, true, 0.0, 10.0)
				_num(b.fire, "gap", p + ".fire", ctx, false, 0.0, 2.0)
				_num(b.fire, "spread", p + ".fire", ctx, false, 0.0, 600.0)
		"shape.bash":
			if b.get("calcify", null) is Dictionary:
				_num(b.calcify, "pct", p + ".calcify", ctx, true, 0.0, 0.9)
				_num(b.calcify, "dur", p + ".calcify", ctx, true, 0.1, 10.0)
		"verb.suit":
			if b.get("pillars", null) is Dictionary:
				var pc: Dictionary = b.pillars
				_src(pc, p + ".pillars", ctx, true)
				_num(pc, "n", p + ".pillars", ctx, true, 3.0, 16.0)
				_num(pc, "r", p + ".pillars", ctx, true, 20.0, 400.0)
				_num(pc, "life", p + ".pillars", ctx, true, 0.1, 10.0)
				_num(pc, "mult", p + ".pillars", ctx, true, 0.0, 10.0)
				_num(pc, "elite_push", p + ".pillars", ctx, false, 0.0, 1.0)


# ================================================================ 精英化第 5 批（docs/91 §13 / §27：浊心斯卡蒂「余音」/「远古血亲」，10-14；docs/61 §23；只往后加）
# 新参数（通用，任何数据干员都能用；没写的干员一个新分支都不走）：
#  shape.circle 的 band [内, 外]     只打离中心 内 × r 到 外 × r 之间的敌人（按敌人边缘算，同 arc_hit 的 + e.r）
#  shape.circle 的 among: attack     只打本干员上一次普攻命中的敌人；放在带 delay 的 trig.every_n 里时，用排队那一刻的命中表。浊心斯卡蒂精一「余音」
#  召唤物 zone {r, share, mode, look}  召唤物自带区域：以召唤物为心，半径 = r × op_range × (1 + (本干员区域倍率 − 1) × share)；
#                                     mode: false = 区域倍率里不算 verb.mode 的 zone_mult（技能模式的放大不传给召唤物）。
#                                     与本干员的区域取并集：data_operator.in_zone 认它（aura scope in_zone、cond in_zone:leader），同一名干员不会因此叠加两份。
#                                     shape.circle center: summon:<种类> + r: zone = 那个召唤物的区域半径；look = 地面帧条（ground 层，紧贴地砖）+ 区域椭圆（ring = 透明度倍率）
#  召唤物 anim（非随行）{idle, run, attack, spawn}  spawn 出场播一遍（期间不走）；move.repick（chase）每隔几秒重选目标（densest = 跟着敌群最密处走）
#  verb.summon_cmd action: cast      召唤物原地施放：播 anim.attack，出手帧（sprites 的 fire）执行 then（center: summon:<种类> 落在它身上）；没有帧条 / 正在浮现时立即执行
#  fx 条目 grow_to: summon:<种类>      扩散缓动跟着那个召唤物与它的区域半径走；play: fps = 帧号按帧条 fps 播（不跟扩散进度跳帧）
# 运行时状态：干员的 e5 字典（ah = 上一次普攻命中的敌人 id 表）与 zmode（verb.mode 的 zone_mult 乘积）；召唤物身上 e5 / zr / ak / at / act / fire / e5_then / rp。
# 确定性：本段不取随机数，画面只看 g.t。--perfab 同局轮换的 /b 桶：带 e5 的召唤物不走、不画（量净成本用，正常游戏恒为 false）。

const E5_KIND_KEYS := ["zone"]
const E5_MOVE_KEYS := ["repick"]
const E5_ANIM_KEYS := ["idle", "run", "attack", "spawn"]
const E5_LOOK_KEYS := ["strip", "fit", "scale", "max_scale", "tint", "ring", "fade", "edge"]   # edge：边线透明度倍率（10-14 加）


## 普攻命中表（data_operator.exec_any_shape 记下、延迟队列带走）：敌人 id → true
static func e5_ids(hits: Array) -> Dictionary:
	var out := {}
	for e in hits:
		out[int(e.id)] = true
	return out


## blocks 里有没有写 among 的积木（data_operator._init 查一次；没有就不记命中表）
static func e5_scan(n) -> bool:
	if n is Dictionary:
		if n.has("among"):
			return true
		for k in n:
			if e5_scan(n[k]):
				return true
	elif n is Array:
		for x in n:
			if e5_scan(x):
				return true
	return false


## shape.circle 的 band / among：伤害口径同 area_hit（× vs_elite、log_hit、命中特效），多两道筛选；不击退、不眩晕
static func e5_area(o, b: Dictionary, c: Vector2, r: float, dmg: float) -> Array:
	var bd = b.get("band", [0.0, 1.0])
	var lo: float = float(bd[0]) * r
	var hi: float = float(bd[1]) * r
	var use_ah: bool = str(b.get("among", "")) == "attack"
	var ah: Dictionary = o.e5.get("ah", {}) if use_ah else {}
	var hits: Array = []
	if use_ah and ah.is_empty():
		return hits
	for e in o.arc_targets(c, 0.0, PI, hi):
		if e.dead or (use_ah and not ah.has(int(e.id))):
			continue
		if e.pos.distance_to(c) + float(e.r) < lo:
			continue
		hits.append(e)
	var max_n: int = int(b.get("max_n", 0))
	if max_n > 0 and hits.size() > max_n:
		hits = o.cap_targets(hits, c, max_n)
	var ve: float = o.vs_elite()
	var src: String = str(b.get("src", ""))
	var tags: Array = b.get("tags", [])
	for e in hits:
		o.log_hit(src, tags)
		o.deal_damage(e, dmg * (ve if e.elite or e.boss else 1.0))
	for e in hits:
		o._hit_fx(e, c)
	return hits


# ---------------------------------------------------------------- 召唤物自带区域 / 帧条 / 施放

## 这种召唤物里最早在场的一个（没有 = {}）
static func e5_summon(o, kind: String) -> Dictionary:
	if o.sm.is_empty():
		return {}
	for s in o.sm.list:
		if not s.gone and (kind == "" or str(s.kind) == kind):
			return s
	return {}


## 召唤物自带区域的半径：r × op_range × (1 + (本干员区域倍率 − 1) × share)；mode: false 时区域倍率先除掉 verb.mode 的 zone_mult
static func e5_zone_r(o, kd: Dictionary) -> float:
	var z = kd.get("zone", {})
	if not (z is Dictionary) or z.is_empty():
		return 0.0
	var lz: float = float(o.loc.zone)
	if not z.get("mode", true):
		lz /= maxf(0.01, float(o.zmode))
	return float(z.get("r", 0.0)) * o.stat(&"op_range") * maxf(0.0, 1.0 + (lz - 1.0) * float(z.get("share", 1.0)))


## shape.circle center: summon:<种类> + r: zone：那个召唤物的区域半径（场上没有时按定义现算）
static func e5_summon_zr(o, kind: String) -> float:
	var s := e5_summon(o, kind)
	if not s.is_empty() and s.has("zr"):
		return float(s.zr)
	return e5_zone_r(o, sm_kind(o, kind))


## data_operator.in_zone 转来：p 在本干员任一召唤物的区域里（半径是这一帧召唤物更新时记下的）
static func e5_in_zone(o, p: Vector2) -> bool:
	for s in o.sm.list:
		if float(s.get("zr", 0.0)) > 0.0 and not s.gone and s.pos.distance_to(p) <= float(s.zr):
			return true
	return false


## sm_spawn 转来：非随行召唤物的帧条 / 区域状态（mf_draw 认的那几个字段同随行召唤物）
static func e5_spawn_state(o, s: Dictionary, kd: Dictionary) -> void:
	var an: Dictionary = kd.get("anim", {})
	var sp: bool = an.has("spawn") and o.anim_tex(str(an.spawn)) != null
	s.merge({"e5": true, "mv": 0.0, "ak": "spawn" if sp else "idle", "at": 0.0, "act": 0.0, "fire": -1.0, "flip_t": -99.0,
		"pcur": {}, "pout": 0.0, "pold": -1, "ghost": {}, "e5_then": [], "rp": 0.0})
	s["zr"] = e5_zone_r(o, kd)


## 帧条一遍的秒数（sprites 的 frames / fps）
static func e5_anim_len(o, key: String) -> float:
	var sp: Dictionary = o.sprite_spec(key)
	return float(sp.get("frames", 4)) / maxf(1.0, float(sp.get("fps", 10)))


## 每帧（sm_tick 转来）：区域半径 → 浮现（期间不走）→ 照常 _sm_step（chase / follow / orbit / stay）→ 转向防抖、施放出手帧、帧条状态
static func e5_step(o, s: Dictionary, kd: Dictionary, i: int, n: int, dt: float) -> void:
	if o.g.perf_alt:
		return
	var an: Dictionary = kd.get("anim", {})
	if kd.has("zone"):
		s.zr = e5_zone_r(o, kd)
	if str(s.ak) == "spawn":
		if float(s.at) < e5_anim_len(o, str(an.get("spawn", ""))):
			s.at = float(s.at) + dt
			return
		_mf_set_anim(s, "idle")
	var prev: Vector2 = s.pos
	var f0: float = float(s.face)
	_sm_step(o, s, kd, i, n, dt)
	var want: float = float(s.face)
	s.face = f0
	var vel: Vector2 = (s.pos - prev) / maxf(dt, 0.0001)
	s.mv = lerpf(float(s.mv), vel.length(), clampf(dt * 10.0, 0.0, 1.0))
	if want != f0 and absf(vel.x) > 20.0:
		_mf_face(o, s, want)
	if float(s.act) > 0.0:
		s.act = float(s.act) - dt
		if float(s.fire) >= 0.0:
			s.fire = float(s.fire) - dt
			if float(s.fire) < 0.0:
				e5_cast_fire(o, s)
	if not an.is_empty():
		_mf_set_anim(s, "attack" if float(s.act) > 0.0 else ("run" if float(s.mv) > 30.0 else "idle"))
	s.at = float(s.at) + dt


## verb.summon_cmd action: cast：kind 种召唤物原地施放，出手帧执行 then（上一次还没到出手帧的先结算，不丢）
static func e5_cast(o, b: Dictionary) -> void:
	var kind: String = str(b.get("kind", ""))
	var kd := sm_kind(o, kind)
	var ak: String = str(kd.get("anim", {}).get("attack", ""))
	for s in o.sm.list.duplicate():
		if s.gone or str(s.kind) != kind:
			continue
		if not s.has("e5") or str(s.ak) == "spawn" or ak == "" or o.anim_tex(ak) == null or o.g.perf_alt:
			o._exec_list(b.get("then", []), s.pos)
			continue
		if float(s.fire) >= 0.0:
			e5_cast_fire(o, s)
		var sp: Dictionary = o.sprite_spec(ak)
		var fps: float = maxf(1.0, float(sp.get("fps", 10)))
		s.act = float(sp.get("frames", 4)) / fps
		s.fire = (float(sp.get("fire", 2)) + 0.5) / fps
		s.e5_then = b.get("then", [])
		s.ak = "attack"
		s.at = 0.0


static func e5_cast_fire(o, s: Dictionary) -> void:
	s.fire = -1.0
	var th: Array = s.get("e5_then", [])
	s.e5_then = []
	if not th.is_empty() and not s.gone:
		o._exec_list(th, s.pos)


## 区域淡入（召唤物出场后 look.fade 秒，缺省 0.5）
static func e5_zone_fade(s: Dictionary, lk: Dictionary) -> float:
	var fi: float = float(lk.get("fade", 0.5))
	return clampf(float(s.t) / fi, 0.0, 1.0) if fi > 0.0 else 1.0


## 召唤物区域的椭圆（data_operator.draw_auras 转来，同本干员区域的画法与颜色，透明度 × look.ring）
static func e5_draw_zones(o, cc: Color, on: bool) -> void:
	var g = o.g
	if g.perf_alt:
		return
	for s in o.sm.list:
		var zr: float = float(s.get("zr", 0.0))
		if zr <= 0.0 or s.gone:
			continue
		var lk: Dictionary = sm_kind(o, str(s.kind)).get("zone", {}).get("look", {})
		var k: float = float(lk.get("ring", 0.6)) * e5_zone_fade(s, lk)
		if k <= 0.004:
			continue
		o.cv.draw_set_transform(s.pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
		o.cv.draw_circle(Vector2.ZERO, zr, Color(cc.r, cc.g, cc.b, (0.08 if on else 0.045) * k))
		var ek: float = float(lk.get("edge", 1.0))   # look.edge：边线透明度倍率（0 = 不画边线；10-14 浊心斯卡蒂伊莎玛拉区域去掉红色外圈，纯画面）
		if ek > 0.0:
			o.cv.draw_arc(Vector2.ZERO, zr, 0.0, TAU, 40, Color(cc.r, cc.g, cc.b, ((0.45 if on else 0.28) + 0.06 * sin(g.t * 3.0 + 1.3)) * k * ek), 2.0)
		o.cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 召唤物区域的地面帧条（data_operator.draw_ground_fx 转来，紧贴地砖：溟痕 / Boss 地面预警之下）：每 1x 像素 = 半径 / fit × scale（封顶 max_scale），循环播
static func e5_draw_zone_ground(o) -> void:
	var g = o.g
	if g.perf_alt:
		return
	for s in o.sm.list:
		var zr: float = float(s.get("zr", 0.0))
		if zr <= 0.0 or s.gone:
			continue
		var lk: Dictionary = sm_kind(o, str(s.kind)).get("zone", {}).get("look", {})
		var name: String = str(lk.get("strip", ""))
		if name == "" or g.tex.get(name) == null or not g.V6_FRAMES.has(name):
			continue
		var spec: Array = g.V6_FRAMES[name]
		var frames: int = maxi(1, int(spec[0]))
		var fr: int = int(float(s.t) * float(spec[1])) % frames
		var sc: float = minf(zr / maxf(1.0, float(lk.get("fit", 64.0))) * float(lk.get("scale", 1.0)), float(lk.get("max_scale", FX_SCALE_MAX)))
		var col := _mf_col(lk.get("tint", []), Color(1, 1, 1, 0.5))
		col.a *= e5_zone_fade(s, lk) * float(g.world.fx_dim)
		if col.a > 0.004:
			fx_frame(o.cv, g, name, frames, fr, s.pos, sc, col)


# ---------------------------------------------------------------- 校验

## _sm_kinds 转来：zone / move.repick / 非随行召唤物的 anim
static func _e5_kind(kd: Dictionary, p: String, ctx: Dictionary) -> void:
	var errs: Array = ctx.errs
	var mv: Dictionary = kd.get("move", {}) if kd.get("move", {}) is Dictionary else {}
	var mode: String = str(mv.get("mode", ""))
	if mv.has("repick"):
		if mode != "chase":
			errs.append(p + ".move.repick 只用于 mode = chase")
		_num(mv, "repick", p + ".move", ctx, false, 0.1, 10.0)
	if kd.has("anim") and mode != "escort":
		var an = kd.anim
		if not (an is Dictionary) or not an.has("idle"):
			errs.append(p + ".anim 必须是对象，至少有 idle")
		else:
			for k in an:
				if not k in E5_ANIM_KEYS:
					errs.append("%s.anim.%s：非随行召唤物只能是 %s" % [p, k, " / ".join(E5_ANIM_KEYS)])
				elif not ctx.get("sprites", {}).has(str(an[k])):
					errs.append("%s.anim.%s「%s」不是本干员 sprites 里的帧条" % [p, k, str(an[k])])
		if kd.has("attack"):
			errs.append(p + "：非随行召唤物写了 anim 就不写 attack（出手用 verb.summon_cmd action: cast 指挥）")
	if kd.has("zone"):
		var z = kd.zone
		if not (z is Dictionary):
			errs.append(p + ".zone 必须是对象 {r, share, mode, look}")
			return
		for k in z:
			if not k in ["r", "share", "mode", "look", "_doc"]:
				errs.append("%s.zone.%s：不认识的字段（只能是 r / share / mode / look）" % [p, k])
		_sm_exprs(z, p + ".zone", ctx)
		_num(z, "r", p + ".zone", ctx, true, 10.0, 600.0)
		_num(z, "share", p + ".zone", ctx, false, 0.0, 1.0)
		if z.has("mode") and not (z.mode is bool):
			errs.append(p + ".zone.mode 只能是 true / false（false = 不算 verb.mode 的 zone_mult）")
		if z.has("look"):
			var lk = z.look
			if not (lk is Dictionary):
				errs.append(p + ".zone.look 必须是对象 {strip, fit, scale, max_scale, tint, ring, fade}")
				return
			for k in lk:
				if not k in E5_LOOK_KEYS:
					errs.append("%s.zone.look.%s：不认识的字段（只能是 %s）" % [p, k, " / ".join(E5_LOOK_KEYS)])
			if lk.has("strip") and not (lk.strip is String and str(lk.strip).begins_with("fx_")):
				errs.append(p + ".zone.look.strip 必须是 fx_* 帧条名（V6_FRAMES 里登记）")
			_num(lk, "fit", p + ".zone.look", ctx, false, 1.0, 512.0)
			_num(lk, "scale", p + ".zone.look", ctx, false, 0.05, 8.0)
			_num(lk, "max_scale", p + ".zone.look", ctx, false, 0.5, 16.0)
			_num(lk, "ring", p + ".zone.look", ctx, false, 0.0, 1.0)
			_num(lk, "fade", p + ".zone.look", ctx, false, 0.0, 5.0)
			if lk.has("tint"):
				var tv = lk.tint
				if not (tv is Array) or tv.size() < 3 or tv.size() > 4 or tv.any(func(x): return not (x is int or x is float)):
					errs.append(p + ".zone.look.tint 必须是 3–4 个数字")


## shape.circle / cone 校验转来：band / among、center summon:<种类> + r: zone
static func _e5_shape(b: Dictionary, p: String, ctx: Dictionary, tag: String) -> void:
	var errs: Array = ctx.errs
	if b.has("band"):
		var bd = b.band
		if tag != "shape.circle" or not (bd is Array) or bd.size() != 2:
			errs.append(p + ".band 必须是 [内, 外]（半径的比例，只用于 shape.circle）")
		else:
			var lo := _val(bd[0], ctx.base)
			var hi := _val(bd[1], ctx.base)
			if lo < 0.0 or hi > 1.0 or lo >= hi:
				errs.append(p + ".band 要满足 0 ≤ 内 < 外 ≤ 1")
	if b.has("among") and (tag != "shape.circle" or str(b.among) != "attack"):
		errs.append(p + ".among 只能是 attack（只打本干员上一次普攻命中的敌人；只用于 shape.circle）")
	if (b.has("band") or b.has("among")) and b.has("only"):
		errs.append(p + "：band / among 不和 only 同用")
	var cn := str(b.get("center", ""))
	if cn.begins_with("summon:") and b.get("r", null) is String and str(b.r) == "zone":
		var kd = ctx.summons.get(cn.substr(7), null) if ctx.summons is Dictionary else null
		if not (kd is Dictionary and kd.has("zone")):
			errs.append(p + "：center: summon:<种类> 配 r: zone 时，这种召唤物要写 zone（召唤物自带区域）")


## fx 条目 grow_to: summon:<种类>：种类要在 blocks.summons 里、且带 zone
static func e5_grow_to_ok(v, ctx: Dictionary) -> bool:
	if not (v is String) or not str(v).begins_with("summon:"):
		return false
	var kd = ctx.summons.get(str(v).substr(7), null) if ctx.get("summons", null) is Dictionary else null
	return kd is Dictionary and kd.has("zone")
