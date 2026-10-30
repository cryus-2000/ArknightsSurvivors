## 干员积木 · ob_core（docs/101 §7.3 B6 ①，10-15：由 op_blocks.gd 按段拆出，内容与注释照搬；继承链与门面见 op_blocks.gd）
## 干员积木（docs/61）：数据干员（data_operator.gd）的积木编译、校验与共享执行器。
## 只走 op_api / character.gd 的公开方法与 g 的公共状态，不碰 game.gd 内部（下划线函数）、enemies.gd、combat.gd。
## 确定性（docs/36 §3）：本文件不用任何随机数；画面只往干员自己的 pfx 里加粒子（不碰 g.rng）。
## 本文件也被 -s 测试脚本（tests/test_core.gd，经 character.gd 的 validate_operator）加载：不许引用 Sfx 等自动加载。
extends "res://scripts/characters/blocks/ob_geom.gd"   # B6 ⑤：几何判定在链的最底层

## 门面（op_blocks.gd = 链尾）：链上早的文件调用晚的文件里的函数时经 _F() 运行时转发（B6 ② 直连 / ③ 单播后去掉）
static var _facade = null

static func _F():
	if _facade == null:
		_facade = load("res://scripts/characters/op_blocks.gd")
	return _facade

## 只读的空缺省值：.get(k, _EA / _ED) 不每次新建空容器（docs/101 S9）；只用在只读的地方（for 遍历、条件、链式 .get）
const _EA: Array = []

const _ED: Dictionary = {}


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
	var mc = _F().mf_parse_cond(s, base)   # 召唤物扩展段：a && b、node:<id>、hurt_any
	if not mc.is_empty():
		return mc
	var ec = _F().el_parse_cond(s)   # 精英化段：buff:<key>
	if not ec.is_empty():
		return ec
	var hc = _F().hw_parse_cond(s)   # 手写迁移段：timer:<key> / armed:<key>
	if not hc.is_empty():
		return hc
	if s.begins_with("!"):
		c.neg = true
		s = s.substr(1).strip_edges()
	if s == "is_leader":
		c.k = "is_leader"
		return c
	if s == "response_on":   # 响应动作总开关开着（balance.json response.on，docs/118）
		c.k = "response_on"
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
		if lhs in ["lamp", "hp_pct", "elite", "still", "resp_idle"]:   # still：队长连续站定秒数；resp_idle：本干员响应上次触发距今秒数（响应关闭时恒为极大，响应动作 docs/118）
			c.k = lhs
		elif lhs.begins_with("faction:") and lhs.length() > 8:
			c.k = "faction"
			c.a = lhs.substr(8)
		elif lhs.begins_with("class:") and lhs.length() > 6:
			c.k = "class"
			c.a = lhs.substr(6)
		else:
			return {"err": "条件左边只能是 lamp / hp_pct / elite / still / resp_idle / faction:<阵营> / class:<职业>：「%s」" % s}
		return c
	return {"err": "看不懂的条件「%s」" % s}


## 编译：深拷贝 blocks，含 $ 的值解析成数字，cond 解析成字典，每块积木编上 _uid（常驻积木的累计器按它存）。
## 校验没通过的地方按 0 / 空处理（validate 已报错）
static func compile(def: Dictionary) -> Dictionary:
	var base: Dictionary = def.get("base", {})
	var counter := [0]
	var out = _compile_node(def.get("blocks", {}).duplicate(true), base, counter)
	return out if out is Dictionary else {}


## B6 ④（docs/101 §7.3.8）：编译后积木里出现过的全部 tag（深扫；常驻积木都出自本干员 B，所以没出现的 tag 每帧一定匹配不到）
static func tag_set(n, out: Dictionary) -> Dictionary:
	if n is Dictionary:
		if n.has("_tag"):
			out[n._tag] = true
		for k in n:
			tag_set(n[k], out)
	elif n is Array:
		for x in n:
			tag_set(x, out)
	return out


## o 的积木里有没有出现过 tag t；没有 tags_all 的对象（测试里的假干员）一律当「有」，照旧逐块匹配
static func has_tag(o, t: String) -> bool:
	var ta = o.get("tags_all")
	return not (ta is Dictionary) or ta.has(t)


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
		"still":
			r = _cmp(float(g.leader_still_t), c.op, c.v)
		"resp_idle":
			r = _cmp(preload("res://scripts/characters/blocks/responses.gd").idle(o), c.op, c.v)
		"response_on":
			r = preload("res://scripts/characters/blocks/responses.gd").on()
		"faction":
			r = _cmp(float(count_others(o, "faction:" + str(c.a))), c.op, c.v)
		"class":
			r = _cmp(float(count_others(o, "class:" + str(c.a))), c.op, c.v)
		_:
			var mc = _F().mf_cond(o, c)   # 召唤物扩展段的条件
			if mc[0]:
				r = mc[1]
			elif str(c.k) == "buff":   # 精英化段：限时增益 buff:<key> 生效中
				r = _F().el_buff_on(o, str(c.a))
			elif str(c.k) in ["timer", "armed"]:   # 手写迁移段
				r = _F().hw_cond(o, c)
			else:
				r = _F().ext_cond_true(o, str(c.k))
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
		return _F().hw_stack_n(o, who.substr(6))
	if who.begins_with("gn:"):   # 成长节点（docs/202）：本干员 gn 状态里的层数（浊心斯卡蒂 gn:tide）
		return _F().gn_n(o, who.substr(3))
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
		dmg = _F().hw_basis(o, str(b.basis)) * mult
	else:
		dmg = o.base(str(b.get("atk_key", "atk")), 0.0) * mult * float(o.loc.dmg) * o._dmg_bonus()
		if b.get("power", false):
			dmg *= o.skill_power()
		dmg *= _F().el_atk_mult(o)   # 精英化段：只乘普攻的局部倍率 atk（普攻出手时才生效；其余干员恒 1.0）
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
				_F().el_path_circles(o, b)
				return []
			var c: Vector2 = shape_center(o, b, at)
			var r: float = shape_radius(o, b)
			if str(b.get("center", "")) == "front":   # 手写迁移段：锚击砸在身前（朝最近敌人转身）
				var fr: Array = _F().hw_front(o, b, r)
				c = fr[0]
				fx_a = fr[1]
			if c == Vector2.INF:
				return []
			if b.has("only"):   # 精英化段：只打处于某些状态的敌人（安洁莉娜失重井）
				hits = _F().el_area_only(o, b, c, r, dmg)
			elif b.has("band") or b.has("among"):   # 精英化第 5 批段：环带 / 只打上一次普攻命中的敌人（浊心斯卡蒂余音）
				hits = _F().e5_area(o, b, c, r, dmg)
			else:
				hits = o.area_hit(src, c, r, dmg, kb, stun, tags, max_n)
			if b.get("ring", true):   # ring: false = 不画缺省地面环（fx 里自己画，§15.9）
				o.fx({"kind": "ring", "pos": c, "r": r, "r0": r * 0.55, "life": 0.32, "col": o.col(), "floor": true, "w": 2.0, "alpha": 0.6})
			fx_c = c
			fx_r = r
			_F().hw_record(o, dmg, fx_a, r, c)   # 手写迁移段：记下这一下（basis prev / 普攻的 attack）
		"cone":
			var r2: float = shape_radius(o, b)
			var org: Vector2 = o.pos + _F().hw_off(b)   # 手写迁移段：origin_off（判定原点相对脚底的偏移）；没写 = o.pos
			var ang: float
			if str(b.get("dir", "")) == "back":   # 手写迁移段：本次普攻的反方向（斯卡蒂天赋反手斩），不另找目标、不转身
				ang = float(o.hw.get("atk_ang", o.facing_angle())) + PI
			else:
				var ar: float = r2   # 找目标的半径：aim_r（× op_range × aim_mult，手写「普攻半径 + aim_pad」）缺省 = 本形状半径
				if b.has("aim_r"):
					ar = float(b.aim_r) * o.stat(&"op_range") * float(b.aim_mult) if b.has("aim_mult") else float(b.aim_r) * o.stat(&"op_range")
				var ts: Array = o.nearest_enemies(1, ar + float(b.get("aim_pad", 30.0)), o.pos)
				var a0: float = (ts[0].pos - o.pos).angle() if not ts.is_empty() else o.facing_angle()
				if not ts.is_empty() and b.has("face") and _F().hw_face_ok(o, b.face):   # 手写迁移段：face（布尔或条件串）= 朝目标转身
					o.face_to(a0)
				ang = o.atk_angle(a0)
			var half: float = float(b.half) if b.has("half") else deg_to_rad(float(b.get("half_deg", 45.0)))
			hits = o.melee_hit(src, org, ang, half, r2, dmg, kb, stun, tags, max_n)
			if not hits.is_empty() and b.has("pause"):   # 命中顿帧（秒，纯画面，走 vfx.impact_pause 总闸；星熊 10-29）
				o.impact_pause(float(b.pause))
			if b.get("ring", true):
				o.fx({"kind": "ring", "pos": o.pos, "r": r2 * 0.6, "r0": 8.0, "life": 0.25, "col": o.col(), "floor": true, "w": 3.0})
			fx_c = o.pos
			fx_r = r2
			fx_a = ang
			_F().hw_record(o, dmg, ang, r2, org)
		"dash_line":
			return _F().tx_dash_start(o, b, dmg)   # 德克萨斯段：命中逐帧结算，这里只起冲
		"projectile":   # 能天使段：弹体自推进，命中在 exu_tick 里结算，这里返回空
			_F().exu_fire(o, b)
	if b.has("resonate") and not hits.is_empty():   # 成长节点（docs/202）：浊心斯卡蒂「深海的回响」叠共振
		_F().gn_resonate(o, b, hits)
	for s in b.get("on_hit", _EA):
		var hs: Array = hits
		if s.has("nearest_n"):   # st.* 的 nearest_n：序号按离本干员由近到远排（同距按 id），只给最近的 n 名（德克萨斯「阻挡」）
			hs = hits.duplicate()
			hs.sort_custom(func(a, c): return a.pos.distance_squared_to(o.pos) < c.pos.distance_squared_to(o.pos) if a.pos.distance_squared_to(o.pos) != c.pos.distance_squared_to(o.pos) else int(a.id) < int(c.id))
		for i in hs.size():
			apply_status(o, hs[i], s, Vector2.INF, -1.0, 0.0, i)
	if b.has("fx") and fx_c != Vector2.INF:
		_F().fx_play(o, b.fx, fx_c, fx_r, hits, fx_a)
	return hits


## 命中 / 力场里的状态（st.*，第三批合并时与安洁莉娜段的 status_one 统一）：stun / slow 精英时长减半、Boss 缺省不受（与原 apply_status 逐字节相同）。
## 一名敌人吃一条状态。c / ring / ring_w：within（离 c 不超过）与 where: ring（在环带 ±ring_w 内）的筛选。
## Boss：缺省不受；boss: true 也受（stun ×0.25 / slow 照常）；boss_only: true 只对 Boss
static func apply_status(o, e: Dictionary, s: Dictionary, c := Vector2.INF, ring := -1.0, ring_w := 0.0, idx := -1) -> void:
	if e.dead or not cond_true(o, s.get("cond", _ED)):
		return
	if s.has("within") and c != Vector2.INF and e.pos.distance_to(c) > float(s.within) + float(e.r) * 0.5:
		return
	if str(s.get("where", "")) == "ring" and (ring < 0.0 or absf(e.pos.distance_to(c) - ring) > ring_w):
		return
	if str(s.get("st", "")) == "seal":   # 召唤 / 封印段：Boss 有自己的规则（缩短 + 免疫），不走下面的「Boss 缺省不受」
		_F().seal_apply(o, e, s)
		return
	if _F().hw_on(o) and _F().hw_status(o, e, s):   # 手写迁移段：点燃 / 易伤（Boss 也吃）
		return
	if e.boss and not (s.get("boss", false) or s.get("boss_only", false)):
		return
	if s.get("boss_only", false) and not e.boss:
		return
	if (s.has("first_only") or s.has("cd") or s.has("nearest_n")) and not _F().el_status_gate(o, s, idx):   # 精英化段：只对这次命中的第一个敌人 / 冷却
		return
	if s.has("fx"):   # 精英化段：状态自带画面（中心 = 这名敌人脚底，半径 = 敌人半径）
		_F().fx_play(o, s.fx, e.pos, float(e.r), [e])
	var g = o.g
	var k: float = 0.25 if e.boss else (0.5 if e.elite else 1.0)
	match "st." + str(s.get("st", "")):
		"st.stun":
			o.add_cc(e, float(s.dur) * k)
		"st.slow":
			o.add_cc(e, -INF, float(s.dur) * (1.0 if e.boss else k), str(o.def.get("slow_kind", "")))   # slow_kind：干员 json（铃兰 stop = 定住式减速）
		"st.airborne":
			_F().lift(o, e, float(s.dur), float(s.get("h", 26.0)), s)
		"st.weightless":
			if _F()._movable(e):
				var was: float = float(e.get("wl_kb", 1.0)) if float(e.get("wl_t", 0.0)) > g.t else 1.0
				e["wl_t"] = maxf(float(e.get("wl_t", 0.0)), g.t + float(s.dur))
				e["wl_kb"] = maxf(was, float(s.kb_mult))
		"st.dot":
			o.log_hit(str(s.get("src", "")), s.get("tags", []))
			o.deal_damage(e, o.base(str(s.get("atk_key", "atk")), 0.0) * float(s.get("mult", 0.0)) * float(o.loc.dmg) * o._dmg_bonus() * (o.vs_elite() if e.elite or e.boss else 1.0))
		"st.pause":   # 能天使段：短停顿只对非精英（Boss 缺省同样不受）
			if not e.elite:
				o.add_cc(e, float(s.dur) * k)
		"st.launch":   # 手写迁移段第 3 批：浮空（艾丽妮式：精英减半在里面算）
			_F().h3_launch(o, e, float(s.dur), float(s.get("h", 26.0)))


## 自动技能的放出门槛（10-25 用户「范围内没有敌人就不开技能」）：返回「周围这个半径（未乘 op_range）内要有敌人才放」，0 = 推不出来（校验报错）。
## 优先级：技能自己写的 need_enemy → 技能 do 里会打到敌人的积木（GATE_HIT_KINDS）的最大作用半径 + GATE_MARGIN（敌人体型）→ 该干员普攻的射程（range / r / len）→ GATE_DEFAULT。
## 治疗类技能（纯治疗 / 回血 / 给血盾，以及治疗为主的混合增益）写 "no_gate": true，不加门槛（返回 0）；其余没有伤害积木的增益 / 召唤类走普攻射程。sb / atk 可以是原始 json（带 $ 表达式，传 base）或编译后的 B（数字，base 传空）
const GATE_HIT_KINDS := ["cone", "cleave", "circle", "wave", "shell", "hookshot", "tether", "leap_slam", "fan", "lock", "barrage", "cast_push", "fx_rain", "mark", "followup", "taunt_guard"]
const GATE_RADIUS_KEYS := ["r", "aim_r", "range", "wave_dist", "dist", "len"]
const GATE_MARGIN := 20.0
const GATE_DEFAULT := 180.0


static func _gate_num(v, base: Dictionary) -> float:
	var ev := eval_expr(v, base)
	return float(ev[1]) if ev[0] else 0.0


static func skill_gate_base(sb: Dictionary, atk: Dictionary, base: Dictionary, fallback: float = GATE_DEFAULT) -> float:
	if sb.get("no_gate", false):   # 治疗类自动技能不加门槛（用户 10-25「治疗类的取消这么限制」）：技力满就放，0 = 恒放
		return 0.0
	if sb.has("need_enemy"):
		return _gate_num(sb.need_enemy, base)
	var best := 0.0
	for x in sb.get("do", []):
		if not x is Dictionary:
			continue
		var kind := str(x.get("shape", x.get("verb", "")))
		if not kind in GATE_HIT_KINDS:
			continue
		for k in GATE_RADIUS_KEYS:
			if x.has(k):
				var r := _gate_num(x[k], base)
				if r > 0.0:
					best = maxf(best, r)
					break
	if best > 0.0:
		return best + GATE_MARGIN
	for k in ["range", "r", "len"]:
		if atk.has(k):
			var ar := _gate_num(atk[k], base)
			if ar > 0.0:
				return ar
	return fallback



static func shape_center(o, b: Dictionary, at: Vector2 = Vector2.INF) -> Vector2:
	var cn: String = str(b.get("center", "zone"))
	if cn.begins_with("summon"):   # 召唤物扩展段：summon:<种类> = 这种召唤物所在处
		return _F().mf_at_point(o, cn)
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
			return _F().e5_summon_zr(o, str(b.center).substr(7))
		return o.zone_r()
	if b.get("r_abs", false):   # 召唤物扩展段：r_abs = 半径不吃 op_range（凯尔希熔毁 130）
		return float(r) * float(b.r_mult) if b.has("r_mult") else float(r)
	if b.has("r_mult"):   # 手写迁移段：半径再乘 r_mult（斯卡蒂潮汐 ×1.4 这类，按手写的乘法顺序：r × op_range × r_mult）
		return float(r) * o.stat(&"op_range") * float(b.r_mult)
	return float(r) * o.stat(&"op_range")


## 光环的受益者（docs/61 §5.2 scope）
## 光照 / 范围区域的「不填充」画法（10-29 特效审查）：贴边三道渐淡的内羽边 + 区域内缓缓漂的少量光点，替代整片半透明圆盘（不糊敌人 / 弹幕）。
## 调用前先 draw_set_transform 成地面椭圆；col 为设定色，a 为总透明度；约 13 次绘制
static func feather_ring(cv, r: float, col: Color, a: float, t: float) -> void:
	if a <= 0.01:
		return
	cv.draw_arc(Vector2.ZERO, r - 5.0, 0.0, TAU, 40, Color(col.r, col.g, col.b, a * 0.22), 3.0)
	cv.draw_arc(Vector2.ZERO, r - 12.0, 0.0, TAU, 36, Color(col.r, col.g, col.b, a * 0.12), 3.0)
	cv.draw_arc(Vector2.ZERO, r - 20.0, 0.0, TAU, 32, Color(col.r, col.g, col.b, a * 0.06), 3.0)
	for i in 10:
		var ang: float = TAU * i / 10.0 + t * 0.18 * (1.0 if i % 2 == 0 else -1.0)
		var rad: float = r * (0.3 + 0.62 * fmod(i * 0.381, 1.0))
		var tw: float = 0.5 + 0.5 * sin(t * 1.6 + i * 2.3)
		cv.draw_circle(Vector2.from_angle(ang) * rad, 1.6, Color(col.r * 1.2, col.g * 1.2, col.b * 1.2, a * 0.55 * tw))


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
				o.apply_kb(e, (d.normalized() if d.length() > 0.5 else Vector2.RIGHT) * kb * (0.3 if e.elite else 1.0))
	if hit.size() > 64:
		for k in hit.keys():
			if float(hit[k]) <= g.t:
				hit.erase(k)


# ---------------------------------------------------------------- 程序漩涡 vortex（docs/61 §5.6，10-11 加；纯画面）
## 用户 10-11 对照原作 S3：大片、柔和、半透明的青色水流漩涡铺在地面上（覆盖区域，不贴身），细细的弧形水流线绕着转、
## 零星光点、少量暗红流线点缀，整体低饱和低透明，战场与单位看得清。
## 写法：常驻积木的 fx 条目 {"vortex": {参数…}, "layer": "floor" | "add", "at": "zone" | "self" | "leader", "cond", "tint"}。
## 画法：n 条流线 = 透视椭圆（y × 0.55）上的螺旋弧，各自从外圈慢慢卷向内圈（生命周期 sin 包络淡入淡出）、沿弧两端渐隐、内圈转得快；
## 加 motes 个上飘闪烁的小光点，中心一团柔光、整片一层极淡的水色底。全部攒成一组三角形（顶点色）一次提交（合批，docs/50）。
## 每条流线 / 光点的随机常数在积木生效后第一次画时用 g.vrng 生成并缓存在贴身层记录里（不碰 g.rng）；运动只看 g.t。
const FX_VORTEX_FADE := 0.4

## 无参数条件
const EXT_CONDS := ["beacon_charging", "enemy_near", "roaming"]   # 主控正在给灯标读条（run/beacon.gd charging）

const FIELD_CENTERS := ["self", "leader", "target", "zone", "last_hit"]

# ================================================================ 安洁莉娜 angelina（docs/59 §5；docs/61 §12）—— 第三批追加段，只往后加
# 新积木：shape.point_aoe（落点弹）、verb.displace（拉 / 推 / 向心 / 环带整形）、verb.field（常驻力场）、verb.buff_leader（主控属性）、
# st.airborne（悬浮）、st.weightless（失重：受到的击退倍率）、st.dot（力场里的持续伤害）、trig.on_impact（落点触发）；
# 技能外壳 dur.next_n（{"next_attacks": N} + attack_patch）。
# 体型档（docs/60 §2.8 / §5「重量 / 力度」）：Boss 不位移、不悬浮（只吃写了 boss / boss_only 的子项）；精英位移 × elite_mult（缺省 0.5）、
# 控制时长 × 0.5；重型（enemies.json heavy）位移 × 0.3（就是 enemies.gd 对 e.kb 的既有折扣，这里先算进去好夹住不越过中心）。
# 位移走 e.kb（速度，enemies.gd 每秒衰减 KB_DECAY），所以自动乘 g.enemy_kb_mult：藏品 #103「安洁莉娜的创想」受到的击退 +40% = 拉得远 40%。

const ANGELINA_TAGS := ["shape.point_aoe", "st.airborne", "st.weightless", "st.dot", "trig.on_impact"]   # verb.displace / verb.field / verb.buff_leader 在「共用积木」段

const LEADER_STATS := ["move_speed", "pickup"]   # verb.buff_leader 可写的主控属性（全局作用域）


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
	var c: Vector2 = _F().field_center(o, b, at)
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
		r_in = _F().h3_attack_r(o, o.cur_attack()) if str(b.r_in) == "attack" else float(b.r_in) * o.stat(&"op_range")   # h3_attack_r：第 3 批的普攻形状按各自半径，其余同 shape_radius
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
			_F().displace_one(o, e, c, b, sc)
		elif kb != 0.0 and _F()._movable(e):
			var dv: Vector2 = e.pos - c
			o.apply_kb(e, (dv.normalized() if dv.length() > 0.5 else Vector2.RIGHT) * kb * (0.3 if e.elite else 1.0))
	for s in b.get("on_hit", _EA):
		for e in hits:
			apply_status(o, e, s, c)
	if _F().fx_any_tex(o, b.get("fx", [])):
		_F().fx_play(o, b.fx, c, r, hits)
	elif not b.get("quiet", false):   # quiet：搭在别的爆点上时不再画默认圈（艾雅法拉熔岩弹击退，10-29）
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
				_F()._num(b, "kb", p, ctx, true, -2000.0, 2000.0)
			else:
				var dirs: Array = ["pull", "push", "center", "ring"] if kind == "field" else ["pull", "push"]
				if not str(b.get("dir", "pull")) in dirs:
					errs.append("%s.dir 只能是 %s" % [p, " / ".join(dirs)])
				_F()._num(b, "dist", p, ctx, true, 0.0, 400.0)
				_F()._num(b, "elite_mult", p, ctx, false, 0.0, 1.0)
			if kind != "field":
				if str(b.get("r", "")) != "attack":
					_F()._num(b, "r", p, ctx, true, 1.0, 800.0)
				_F()._num(b, "r_mult", p, ctx, false, 0.05, 10.0)
				if b.has("r_in") and str(b.r_in) != "attack":
					_F()._num(b, "r_in", p, ctx, false, 0.0, 800.0)
				if not str(b.get("center", "self")) in DISPLACE_CENTERS:
					errs.append("%s.center 只能是 %s" % [p, " / ".join(DISPLACE_CENTERS)])
			_F()._list(b.get("on_hit", []), p + ".on_hit", "on_hit", ctx)
		"verb.field":
			if b.has("tick"):
				if not kind in ["skill", "sustain"]:
					errs.append("%s：常驻力场（verb.field 带 tick）只能放技能 do 或常驻列表（这里是 %s）" % [p, kind])
					return
				if b.has("do") or b.has("dur"):
					errs.append(p + "：verb.field 写了 tick（常驻力场）就不写 do / dur（瞬时留场）")
				_F()._num(b, "r", p, ctx, true, 1.0)
				_F()._num(b, "every", p, ctx, false, 0.1)
				_F()._num(b, "ring", p, ctx, false, 0.0)
				_F()._num(b, "ring_w", p, ctx, false, 1.0)
				if not str(b.get("center", "leader")) in ["leader", "self"]:
					errs.append(p + ".center 只能是 leader / self")
				if not str(b.get("look", "none")) in ["ring", "lift", "none"]:
					errs.append(p + ".look 只能是 ring / lift / none")
				var tk = b.tick
				if not (tk is Array) or tk.is_empty():
					errs.append(p + ".tick 至少要一个子项（verb.displace / st.*）")
				else:
					_F()._list(tk, p + ".tick", "field", ctx)
					for i in tk.size():
						if tk[i] is Dictionary and (str(tk[i].get("where", "")) == "ring" or str(tk[i].get("dir", "")) == "ring") and not b.has("ring"):
							errs.append("%s.tick[%d]：where / dir 为 ring 时力场要写 ring" % [p, i])
			else:
				if not kind in ["skill", "instant"]:
					errs.append("%s：瞬时留场（verb.field 带 do）只能放技能或触发器的 do（这里是 %s）" % [p, kind])
					return
				_F()._num(b, "r", p, ctx, true, 1.0, 800.0)
				_F()._num(b, "dur", p, ctx, true, 0.1, 30.0)
				_F()._num(b, "every", p, ctx, true, 0.1, 30.0)
				if b.has("visual_end"):
					var ve = b.visual_end
					if not ve is Dictionary:
						errs.append(p + ".visual_end 须为 {skill, fx}")
					else:
						var skill = ve.get("skill", -1)
						if not (skill is int or skill is float) or float(skill) != floorf(float(skill)) or float(skill) < 0.0 or float(skill) > 2.0:
							errs.append(p + ".visual_end.skill 须为 0–2 的整数")
						if not ve.get("fx") is Array or ve.fx.is_empty():
							errs.append(p + ".visual_end.fx 须为非空特效列表")
						else:
							_F()._fx(ve.fx, p + ".visual_end.fx", ctx, "verb.field")
				_F()._num(b, "cap", p, ctx, false, 1.0, 16.0)   # 精英化段：这块积木同时最多几处（超出时最早的先消失；安洁莉娜失重井 3 口）
				if not str(b.get("center", "self")) in FIELD_CENTERS:
					errs.append("%s.center 只能是 %s" % [p, " / ".join(FIELD_CENTERS)])
				if not (b.get("do", null) is Array) or b.do.is_empty():
					errs.append(p + "：verb.field 要有 do（瞬时留场每次 tick 执行的瞬时积木）或 tick（常驻力场）")
				else:
					_F()._list(b.do, p + ".do", "instant", ctx)
		"verb.buff_leader":
			if not kind in ["skill", "sustain"]:
				errs.append("%s：「verb.buff_leader」是常驻积木，不能放在这里（%s）" % [p, kind])
				return
			if not str(b.get("stat", "")) in LEADER_STATS:
				errs.append("%s.stat 只能是 %s" % [p, " / ".join(LEADER_STATS)])
			if not str(b.get("op", "")) in ["add", "mult"]:
				errs.append(p + ".op 只能是 add / mult")
			_F()._num(b, "value", p, ctx, true, 0.0, 5.0)


# ================================================================ 德克萨斯 texas（docs/61 §13）
# 第三批并行实装约定：每名干员的新积木在文件末尾各占一段（append-only）；核心部分只加三处转发：
# validate 的普攻形状表、_block 里 TX_IMPL 命中时转给 _tx_block、exec_shape 的 dash_line 分支。
# data_operator.gd 里对应的转发都标了「德克萨斯段」。状态存在干员的 tx 字典里（data_operator.gd 的 var tx）。
#
#  shape.dash_line   冲刺穿行：沿一条线段冲出 r（× op_range × 冲刺长度倍率），宽 w，用时 t、到头停 hold；
#                    逐帧扫过的线段内敌人各吃一次（不重复）。aim：nearest（最近敌人，手动普攻 A 方向类）/ densest（敌群最密处；附近没有敌人就不冲）/
#                    leader_dir（主控冲刺方向；本干员是主控时不另行位移，跟着主控的冲刺扫）/ reverse（上一次冲刺的反方向）。
#                    干员是主控时冲刺就是主控本体位移（squad.update 把 g.ppos 拉过去），到头不停顿。
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
	"verb": ["sp_secs", "dash_mod", "trail", "fx_scatter", "fx_rain", "emit_path", "rift_slash"],   # verb.buff_leader 在「共用积木」段
	"trig": ["on_dash_end", "on_leader_dash", "on_skill_start", "on_skill_end"],
}

const EXU_SKILL_KEYS := ["attack_patch", "end"]

const EL_ONLY := ["weightless", "airborne"]

const HW_SKILL_KEYS := ["aim_r", "aim_pad", "cast", "pulse", "active_timer", "status_active", "stack_max"]   # status_active / stack_max：第 3 批（技能生效期间显示 status / 次数型可叠几次）


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


# ---------------------------------------------------------------- 逻各斯段（手写迁移段续）：飘飞咒文弹 / 处决 / 锁定 / 扇形咒域 / 安魂
# 攻击值 basis atk = base(atk) × 加成 × attack.atk_mults（cond 成立的依次乘，例：湮灭期间 ×1.5）；mult 可写数组 = 依次乘（同手写的 a × b × c）。
# 攻击距离 = attack.range × op_range × attack.range_mults（同上）。
# shape.bolt   飘飞咒文弹（普攻或触发 do）：pick aim（普攻：aim_targets，扇形咒域生效时多要 6 个再只留域内的；extra = 追加目标）/ random（射程内最近 pool 个里
#              用 g.rng_op 随机抽 count 个，chance = 先用 g.rng_op 掷一次概率；slow = 被选中时立即减速）。每枚排进出手队列（第 k 枚晚 gap × 队列长度 秒），
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


# ---------------------------------------------------------------- 乌尔比安段（手写迁移段续）：掷锚（钩回 / 原地落锚）/ 掀飞 / 拖拽 / 叠层 / 蓄势 / 计时
# shape.circle center: front   判定中心 = 脚底 + 朝 aim_r（× op_range，缺省 = 本形状半径）+ aim_pad 内最近敌人（转身）的方向 × 半径 × front（锚击砸在身前）
# verb.tether  掷锚（技能 do）：pick（elite = 射程 pick_r_elite 内最近的精英 / Boss，没有退到 densest；densest = pick_r 内敌群最密处，没有退到最近的）选落点，
#              manual: true = 当队长手动时用玩家给的落点 / 方向（aim_cone / aim_range / aim_empty / aim_free / aim_snap，契约 v2.4 / v2.5）；没有落点退回 refund 的技力。
#              锚 throw 秒飞到落点咬地；mode reel：钩住落点 hook_r（hook_more 成立时 × r_mult）内至多 hook_n（+ hook_more.n）名非 Boss 敌人，收链拽到身前、眩晕，
#              停 hold 秒后重砸身前（r × op_range，攻击 × mult × 加成 × 技能强度，钩中的首个精英 × elite_mult；stun；击退 slam_kb）；
#              钩不到或钩到 Boss 就和 mode zip 一样：锚在落点原地砸 r（10-22 起本干员不位移）（land_kb 击退，kb_boss = Boss 也推；stun_boss / stun_elite 时长系数），
#              落地后执行 then（target = 落点）、drag（cond：甩锁链拽来 r 内至多 n 名，伤害 = 落地伤害 × mult）、rift（cond：本干员到落点裂开通路，
#              宽 w，沿线 攻击 × 加成 × mult × 技能强度 并掀飞 air 秒）。锚在外面时本干员不起手、不放别的技能，动作停在技能条第 hold_frame 帧
# verb.stack   叠层（触发 do）：key 层数 + add（Boss + add_boss），上限 cap + cap_more（cond 成立的 add）；层数变了立刻重算属性（aura 的 per: stack:<key>）
# verb.arm     蓄势（触发 do）：key 置位（已置位不重复）；attack.armed [{key, do}]：置位时下一次普攻整个换成 do（不计普攻次数、不走 every_n），用掉清零
# verb.timer   计时（瞬时）：key 计时 dur 秒（每帧开头倒数，同手写）；条件 timer:<key> / armed:<key>；技能积木 active_timer = 技能生效剩余按这个计时（手写的「开辟」8 秒）

const HW4_TAGS := ["verb.tether", "verb.stack", "verb.arm", "verb.timer"]


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


# ---------------------------------------------------------------- 流明段（第 3 批续，LM_TAGS）
#  shape.lantern    普攻「荧光」：每 heal.every 秒（不在出手、没技能可放的帧累计）到点就起手，出手帧驱散优先（侵蚀 > corrode、神经 > nerve）、
#                   其次治疗（pct × [mults] × op_atk × 同伴 × heal_out）；同时向射程内（视线优先，按住瞄准 B 类）最近敌人射一发光弹 bolt
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


# ---------------------------------------------------------------- 水月段（第 3 批续，MZ_TAGS）
#  shape.umbrella   伞击（普攻）：扇形 half = min(180°, half_deg + 角度加成)，半径 r × 范围倍率 × r_mults；伤害 = atk × 伤害倍率 × 加成 × dmg_mults；
#                   full_circle {cond}（自身周围全范围）；kb；empower（次数型技能的补丁：mult × 技能强度、r_mult、kb、burst 创伤扩散、
#                   swarm 额外触手）；tentacle：命中里生命最低的 n 个（n = 追击数属性 + n_add）触手追击 × t_mult，不够打附近的；
#                   drag 束缚时拖向自己；stake 触手桩（旧精二「固着」）。stats：专属属性（attack.stats 映射 → 属性名）
#  verb.kill_heal   天赋（on_kill do）：击杀时为队长回复 pct × 最大生命（每秒预算 regen、上限 cap）
#  verb.cast_push   瞬时：发动时推开身边 r 内的非 Boss 敌人（技能发动光环）
#  blocks.dmg_bonus {ally: false, mults [{cond, near_low_hp {r, below}, mult}]}：本干员的伤害加成（不吃同伴倍率；附近有半血敌人时 ×）

const MZ_TAGS := ["shape.umbrella", "verb.kill_heal", "verb.cast_push"]


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
