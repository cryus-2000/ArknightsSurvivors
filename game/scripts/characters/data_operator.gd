## 数据驱动干员（docs/61）：读干员 JSON 的 blocks 段，把普攻 / 技能 / 特性 / 天赋 / 成长节点都交给积木（characters/op_blocks.gd）执行。
## 和手写干员一样继承 character.gd、只走 op_api；同一份数值写成手写脚本（tests/data_ops/eqtest_hand.gd）同 seed 逐字节相同（check.py blocks_eq）。
## 每帧顺序（docs/61 §7）：技能计时 → 延迟队列 → 常驻积木（局部倍率 → 属性重建 → 治疗 / 灯火 / tick / 软减速 / 绕行体）→ 技能起手 → 普攻起手。
extends "res://scripts/characters/character.gd"

const OB = preload("res://scripts/characters/op_blocks.gd")

var B: Dictionary = {}                 # 编译后的 blocks（$ 已解析成数字、cond 已解析）
var cd := 0.5                          # 普攻冷却
var s_t: Array = [0.0, 0.0, 0.0]       # 持续型技能剩余秒数
var s_dur: Array = [0.0, 0.0, 0.0]     # 持续型技能总时长（HUD）
var perm_on: Array = [false, false, false]   # 永久型技能已放出（出手帧起生效）
var taken: Array = []                  # 已选的 custom 节点 id（按选下顺序）
var nodes_taken := ""                  # 同上的字符串（成长节点测试看「当场有变化」）
var atk_n := 0                         # 普攻出手次数（trig.every_n）
var pending: Array = []                # 延迟执行：[{t, do}]
var loc := {"zone": 1.0, "dmg": 1.0, "heal": 1.0, "interval": 1.0, "area": 1.0, "force": 1.0, "force_lit": 1.0}   # 本干员局部倍率（docs/61 §5.1；area / force / force_lit 见安洁莉娜段）
var no_attack := false
var zr := 0.0                          # 本帧区域半径（上一帧的值给 in_zone 条件用）
var _mods: Array = []                  # 已写进 g.stats 的修正 [stat, op, value, scope]
var _acc: Dictionary = {}              # 常驻积木的累计器（_uid → 秒）
var _state: Dictionary = {}            # 常驻积木的状态（软减速的位置记忆、绕行体角度）
var _warned := {}
var _fxt: Dictionary = {}              # 画面帧条（docs/61 §5.6）：常驻积木上 every 条目的计时（_uid → [秒…]），纯画面
var _fxb: Dictionary = {}              # 贴身层（behind / front）：_uid → {b, el, fade}；fade < 0 = 生效中，≥ 0 = 退出后淡出剩余秒数
var tx: Dictionary = {}                # 德克萨斯段（op_blocks.gd 末尾）：冲刺 / 残像 / 延迟队列等状态
var ext := {}                          # 积木扩展段的运行时状态（能天使：弹体 / 计数器 / 次数型技能，op_blocks.gd 末尾）
var sm := {}                           # 召唤 / 封印段（op_blocks.gd 末尾，docs/61 §15）：召唤物、封印标记、护盾、治疗光环计时；空 = 用不到
var mf := {}                           # 召唤物扩展段（docs/61 §15.9）：限时减伤、召唤物倍率表、已执行的 on_deploy；空 = 用不到


func _init(game, def_: Dictionary) -> void:
	super(game, def_)
	B = OB.compile(def)
	# 召唤物扩展段（§15.9）：普攻 shape.support 的 when 条件、首拍；有没有 trig.on_deploy（每帧只在有时才查）
	var a: Dictionary = B.get("attack", {})
	if str(a.get("shape", "")) == "support":
		if a.get("when", null) is String:
			a.when = OB.parse_cond(str(a.when), def.get("base", {}))
		cd = float(a.get("first", cd))
	var dep := false
	for sec in ["trait", "talent"]:
		for t in B.get(sec, []):
			dep = dep or str(t.get("_tag", "")) == "trig.on_deploy"
	for k in B.get("progression", {}):
		for t in _node_list(B.progression[k]):
			dep = dep or str(t.get("_tag", "")) == "trig.on_deploy"
	B["_mf_deploy"] = dep


## 成长节点的积木：一块，或数组（§15.9）
static func _node_list(v) -> Array:
	return v if v is Array else [v]


func _src_tag() -> String:
	return "blk:" + id


# ---------------------------------------------------------------- 区域 / 技能状态（op_blocks 回调）

## 区域中心（docs/61 §3.1）：leader = 主控（图鉴演示以自己为中心）
func zone_c() -> Vector2:
	var z: Dictionary = B.get("zone", {})
	if str(z.get("center", "self")) == "leader" and g.demo_op == "":
		return g.ppos
	return pos


func zone_r() -> float:
	return zr


func _zone_r_now() -> float:
	return float(B.get("zone", {}).get("r", 0.0)) * stat(&"op_range") * float(loc.zone)


func in_zone(p: Vector2) -> bool:
	var c := zone_c()
	return c != Vector2.INF and p != Vector2.INF and p.distance_to(c) <= zr


func skill_on(i: int) -> bool:
	return s_t[i] > 0.0 or perm_on[i] or ammo[i] > 0


func skill_active_left(i: int) -> float:
	return maxf(s_t[i], OB.exu_ammo_left(self, i))   # 次数型（dur.ammo）返回剩余发数


func skill_active_dur(i: int) -> float:
	return s_dur[i] if s_dur[i] > 0.0 else 1.0


func _swing_radius() -> float:
	var a: Dictionary = B.get("attack", {})
	return OB.shape_radius(self, a) if a.has("shape") and str(a.shape) != "support" else 90.0


# ---------------------------------------------------------------- 成长

func on_custom_node(nid: String, _choice: String = "") -> void:
	taken.append(nid)
	nodes_taken = ",".join(taken)


func on_leave() -> void:
	OB.airborne_clear(self)
	OB.sm_clear(self)   # 召唤 / 封印段
	g.stats.remove_source(_src_tag())
	_mods = []
	refresh_stats()


## 当前生效的触发积木（docs/61 §5.5 的固定顺序：trait → talent → 已选节点 → elite1 / elite2）
func _trigs() -> Array:
	var out: Array = []
	out.append_array(B.get("trait", []))
	if elite >= 1:
		out.append_array(B.get("talent", []))
	var pg: Dictionary = B.get("progression", {})
	for nid in taken:
		if pg.has(nid):
			out.append_array(_node_list(pg[nid]))
	for k in [["elite1", 1], ["elite2", 2]]:
		if elite >= k[1] and pg.has(k[0]):
			out.append_array(_node_list(pg[k[0]]))
	return out


# ---------------------------------------------------------------- 每帧

func update(dt: float) -> void:
	cd -= dt
	var prev_s: Array = s_t.duplicate()
	for i in 3:
		if s_t[i] > 0.0:
			s_t[i] = maxf(0.0, s_t[i] - dt)
	OB.mf_tick(self, dt, prev_s)   # 召唤物扩展段（§15.9）：限时减伤计时、trig.on_deploy、带 at 的 trig.on_skill_end
	_tick_pending(dt)
	_sustain(dt)
	_tick_shots(dt)
	OB.exu_tick(self, dt)   # 能天使段：技能 end、普攻锁、连射队列、弹体
	OB.sm_tick(self, dt)    # 召唤 / 封印段：召唤物、护盾计时、封印标记（sm 为空时直接返回）
	if OB.tx_update(self, dt):   # 德克萨斯段：冲刺中不起手
		return
	if acting():
		return
	var ready := charge_skills(dt)
	if ready >= 0:
		start_skill(OB.mf_skill_aim(self, ready), ready)   # blocks.skills[i].aim（§15.9）；没写 = INF 不转身
		return
	if no_attack or cd > 0.0:
		return
	var a: Dictionary = cur_attack()
	var at := Vector2.INF
	match str(a.get("shape", "")):
		"support":   # 召唤物扩展段（§15.9）：不造成伤害的普攻，every 一拍，when 成立才朝主控起手（手动普攻不管它）
			cd = float(a.get("every", 1.0)) / stat(&"op_aspd") * float(loc.interval)
			if OB.cond_true(self, a.get("when", {})):
				start_attack(g.ppos)
			return
		"circle":
			var c: Vector2 = OB.shape_center(self, a)
			var r: float = float(a.get("range", 0.0)) * stat(&"op_range") if a.has("range") else OB.shape_radius(self, a)
			if c != Vector2.INF:
				at = atk_point(nearest_enemies(1, r, c), r)   # 手动普攻（v2.5）：不分方向，只受闸门
		"cone":
			var r2: float = OB.shape_radius(self, a)
			at = atk_point(nearest_enemies(1, r2 + 30.0, pos), r2)   # 手动普攻 A 类
		"line":
			var rl: float = float(a.get("len", 0.0)) * stat(&"op_range")
			at = atk_point(nearest_enemies(1, rl, pos), rl)   # 手动普攻 A 类
		"point_aoe":
			var tp: Vector2 = OB.point_aoe_target(self, a)
			atk_to = tp
			at = atk_point([{"pos": tp}] if tp != Vector2.INF else [], float(a.get("range", 300.0)) * stat(&"op_range"))   # 手动普攻 A 类（落点 aim_land）
		"dash_line":
			at = OB.tx_attack_point(self, a)   # 德克萨斯段
		"projectile":   # 能天使段：手动普攻 B 类
			at = OB.exu_aim(self, a)
	if at == Vector2.INF:
		cd = idle_cd(0.2)
	else:
		cd = float(B.get("attack", {}).get("every", 1.0)) / stat(&"op_aspd") * float(loc.interval)
		start_attack(at)


func _tick_pending(dt: float) -> void:
	if pending.is_empty():
		return
	var due: Array = []
	for p in pending:
		p.t -= dt
		if p.t <= 0.0:
			due.append(p)
	pending = pending.filter(func(p): return p.t > 0.0)
	for p in due:
		_exec_list(p.do, p.get("at", Vector2.INF))


## 常驻积木：先收集本帧生效的（条件在这里各求值一次），再按 局部倍率 → 属性 → 副作用 三遍执行
func _sustain(dt: float) -> void:
	var act: Array = []   # 常驻效果积木与 trig.tick，按固定顺序
	for t in B.get("trait", []):
		_collect_trig(t, act)
	var sk: Array = B.get("skills", [])
	for i in mini(3, sk.size()):
		if skill_on(i):
			for b in sk[i].get("do", []):
				if OB.cond_true(self, b.get("cond", {})):
					act.append(b)
	if elite >= 1:
		for t in B.get("talent", []):
			_collect_trig(t, act)
	var pg: Dictionary = B.get("progression", {})
	for nid in taken:
		if pg.has(nid):
			for t in _node_list(pg[nid]):
				_collect_trig(t, act)
	for k in [["elite1", 1], ["elite2", 2]]:
		if elite >= k[1] and pg.has(k[0]):
			for t in _node_list(pg[k[0]]):
				_collect_trig(t, act)
	# 一：局部倍率
	var add := {}
	var mul := {}
	for k in loc:
		add[k] = 0.0
		mul[k] = 1.0
	no_attack = false
	for b in act:
		match str(b.get("_tag", "")):
			"verb.buff_self":
				var st: String = str(b.stat)
				if loc.has(st):
					if str(b.op) == "add":
						add[st] += float(b.value)
					else:
						mul[st] *= float(b.value)
			"verb.mode":
				if b.has("dmg_mult"):
					mul.dmg *= float(b.dmg_mult) * (skill_power() if b.get("power", false) else 1.0)
				if b.has("zone_mult"):
					mul.zone *= float(b.zone_mult)
				if b.has("interval_mult"):
					mul.interval *= float(b.interval_mult)
				if b.get("no_attack", false):
					no_attack = true
	for k in loc:
		loc[k] = (1.0 + add[k]) * mul[k]
	zr = _zone_r_now()
	# 二：g.stats 修正（与上一帧相同就不动；不同就整组重建，顺序固定）
	var want: Array = []
	for b in act:
		match str(b.get("_tag", "")):
			"verb.buff_self":
				if not loc.has(str(b.stat)):
					want.append([str(b.stat), str(b.op), float(b.value) * (skill_power() if b.get("power", false) else 1.0), "op:" + id])
			"verb.lamp":
				if b.has("loss_mult"):
					want.append(["light_loss", "mult", float(b.loss_mult), ""])
			"verb.buff_leader":
				want.append([str(b.stat), str(b.op), float(b.value), ""])
			"aura.atk", "aura.aspd", "aura.skill_power", "aura.range":
				var v: float = float(b.value)
				if b.get("power", false):
					v *= skill_power()
				if b.has("per"):
					v *= float(mini(OB.count_others(self, str(b.per)), int(b.get("cap", 99))))
				if v != 0.0:
					for m in OB.aura_members(self, str(b.scope)):
						want.append([OB.AURA_STAT[str(b.aura)], "add", v, "op:" + m.id])
	OB.tx_sustain(self, act, want)   # 德克萨斯段：冲刺长度 / 宽度、主控属性
	if want != _mods:
		g.stats.remove_source(_src_tag())
		for m in want:
			g.stats.add(StringName(m[0]), m[1], m[2], _src_tag(), m[3])
		_mods = want
		refresh_stats()
	# 三：副作用（治疗、灯火、tick、软减速、绕行体）
	var seen := {}
	for b in act:
		var u: int = int(b.get("_uid", 0))
		match str(b.get("_tag", "")):
			"verb.heal":
				if b.has("every"):
					seen[u] = true
					_acc[u] = float(_acc.get(u, 0.0)) + dt
					if _acc[u] >= float(b.every):
						_acc[u] -= float(b.every)
						_heal(b)
			"verb.lamp":
				if b.has("per_sec"):
					g.lamp = clampf(g.lamp + float(b.per_sec) * dt, 0.0, g.lamp_cap)
			"trig.tick":
				seen[u] = true
				_acc[u] = float(_acc.get(u, 0.0)) + dt
				if _acc[u] >= float(b.every):
					_acc[u] -= float(b.every)
					_exec_list(b.get("do", []))
			"st.slow_soft":
				seen[u] = true
				_state[u] = OB.slow_soft(self, b, _state.get(u, {}))
			"shape.orbit":
				seen[u] = true
				if not _state.has(u):
					_state[u] = {"ang": 0.0, "hit": {}}
				OB.orbit_tick(self, b, _state[u], dt)
			"verb.field":
				if not b.has("tick"):   # 瞬时留场（星熊）不是常驻的，在 _exec_list 里生成
					continue
				seen[u] = true
				if not _state.has(u):
					_state[u] = {}
				OB.field_tick(self, b, _state[u], dt)
	# 这一帧没生效的累计器 / 状态清零（技能结束、条件不成立时重新计时）
	for u in _acc.keys():
		if not seen.has(u):
			_acc.erase(u)
	for u in _state.keys():
		if not seen.has(u):
			_state.erase(u)
	_ext_sustain(act, dt)
	OB.sm_sustain(self, act, dt)   # 召唤 / 封印段：aura.heal
	OB.mf_sustain(self, act)       # 召唤物扩展段：verb.summon_mod 的倍率表
	# 四：画面帧条（docs/61 §5.6）：常驻积木上带 every 的 fx 条目定时播；只动 pfx / g.vrng，不影响玩法
	var fseen := {}
	for b in act:
		if b.has("fx"):
			var u: int = int(b.get("_uid", 0))
			fseen[u] = true
			_fxt[u] = OB.fx_tick(self, b.fx, zone_c(), zr, _fxt.get(u, []), dt)
			if OB.fx_has_body(b.fx):
				if not _fxb.has(u) or float(_fxb[u].fade) >= 0.0:
					_fxb[u] = {"b": b, "el": 0.0, "fade": -1.0, "fl": OB.fx_hold_out(b.fx)}
				else:
					_fxb[u].el += dt
	for u in _fxt.keys():
		if not fseen.has(u):
			_fxt.erase(u)
	for u in _fxb.keys():
		if not fseen.has(u):
			var e: Dictionary = _fxb[u]
			e.el += dt
			e.fade = float(e.fl) if float(e.fade) < 0.0 else float(e.fade) - dt
			if e.fade <= 0.0:
				_fxb.erase(u)


## 触发积木进本帧列表：passive → 它的 do（各自再看 cond）；tick → 它本身；裸效果积木（成长节点）→ 它本身
func _collect_trig(t: Dictionary, act: Array) -> void:
	if not OB.cond_true(self, t.get("cond", {})):
		return
	match str(t.get("_tag", "")):
		"trig.passive":
			for b in t.get("do", []):
				if OB.cond_true(self, b.get("cond", {})):
					act.append(b)
		"trig.tick":
			act.append(t)
		"trig.every_n", "trig.on_kill":
			pass
		_:
			act.append(t)


func _heal(b: Dictionary) -> void:
	if b.has("knight") and g.knight.alive:   # 召唤物扩展段（§15.9）：同时治骑士同伴（按骑士最大生命）
		g.knight.heal(g.knight.maxhp * float(b.knight))
	if g.hp >= g.max_hp and not b.get("full", false):   # full: true = 满血也照常结算（溢出治疗类藏品 / on_over 照常触发，同手写凯尔希 S1）
		return
	var h: float
	if str(b.get("scale", "")) == "op":   # × op_atk × 同伴倍率 × heal_out × 局部 heal 倍率（同手写治疗干员的写法）
		h = g.max_hp * float(b.pct) * (stat(&"op_atk") * g.ally_mult * stat(&"heal_out") * float(loc.heal))
	else:
		h = g.max_hp * float(b.pct) * float(loc.heal)
	if b.get("power", false):
		h *= skill_power()
	var over: float = maxf(0.0, g.hp + h - g.max_hp)
	heal_leader(h, str(b.get("src", display_name())), "技能" if b.get("power", false) else "常驻")   # 子项只进 docs/88 遥测
	if b.has("sfx"):
		_sfx_op(str(b.sfx))
	if over > 0.0 and b.has("on_over"):
		_exec_list(b.on_over)
	if b.has("text"):
		float_text(g.ppos + Vector2(0, -90), "+%d" % int(h), col(), int(b.text))
	if b.has("fx"):
		OB.fx_play(self, b.fx, g.ppos, 30.0)


## 瞬时积木列表（技能出手、触发器触发、延迟到点）
func _exec_list(arr: Array, at: Vector2 = Vector2.INF) -> void:
	for b in arr:
		if not OB.cond_true(self, b.get("cond", {})):
			continue
		match str(b.get("_tag", "")):
			"shape.circle", "shape.cone":
				OB.exec_shape(self, b, at)
			"verb.heal":
				if not b.has("every"):
					_heal(b)
			"verb.lamp":
				if b.has("add"):
					g.lamp = clampf(g.lamp + float(b.add), 0.0, g.lamp_cap)
			"verb.sp_team":
				g.squad.gain_sp(float(b.pct), self if b.get("exclude_self", true) else null)
			"verb.displace":
				OB.displace_at(self, b, at)
			"custom":
				var fn: String = str(b.custom)
				if has_method(fn):
					call(fn, b)
				elif not _warned.has(fn):
					_warned[fn] = true
					push_warning("数据干员 %s：custom 函数「%s」不存在，已忽略" % [id, fn])
			_:
				_ext_exec(b, at)       # 星熊段
				OB.tx_exec(self, b, at)   # 德克萨斯段
				OB.exu_exec(self, b, at)  # 能天使段：shape.projectile / verb.counter / verb.attack_lock
				OB.sm_exec(self, b, at)   # 召唤 / 封印段：verb.summon / verb.shield
				OB.mf_exec(self, b, at)   # 召唤物扩展段：verb.guard / verb.cleanse
		if b.has("fx") and not str(b.get("_tag", "")) in OB.FX_SELF_PLAY:   # 伤害形状 / 位移 / 区域等的 fx 由执行器按自己的位置播
			OB.fx_play(self, b.fx, zone_c(), zr)


# ---------------------------------------------------------------- 出手

func _release() -> void:
	var a: Dictionary = cur_attack()
	if str(a.get("shape", "")) == "support":   # 召唤物扩展段（§15.9）：出手帧执行 do（音效由 do 里的积木自己播）
		_exec_list(a.get("do", []), g.ppos)
		return
	if str(a.get("shape", "")) == "point_aoe":
		_fire_point_aoe(a)
	else:
		exec_any_shape(a, Vector2.INF, true)
	_sfx_op("atk")
	atk_n += 1
	for t in _trigs():
		if str(t.get("_tag", "")) == "trig.every_n" and OB.cond_true(self, t.get("cond", {})):
			var n: int = maxi(1, int(t.n))
			if atk_n % n == 0:
				var dl: float = float(t.get("delay", 0.0))
				if dl > 0.0:
					pending.append({"t": dl, "do": t.get("do", [])})
				else:
					_exec_list(t.get("do", []))


func _release_skill() -> void:
	var i := cur_skill
	var sk: Array = B.get("skills", [])
	if i < 0 or i >= sk.size():
		return
	var sb: Dictionary = sk[i]
	var dv = sb.get("dur", 0.0)
	if dv is String and dv == "permanent":
		perm_on[i] = true
	elif dv is Dictionary and dv.has("ammo"):   # 能天使段：dur.ammo（N 发子弹）
		OB.exu_skill_shell(self, i, dv)
	elif dv is Dictionary:
		ammo[i] = int(dv.get("next_attacks", 0))   # 安洁莉娜段：dur.next_n，接下来 N 次普攻带 attack_patch
	elif float(dv) > 0.0:
		s_t[i] = float(dv)
		s_dur[i] = float(dv)
	_exec_list(sb.get("do", []))
	OB.tx_skill_start(self, i)   # 德克萨斯段：trig.on_skill_start
	fx({"kind": "ring", "pos": pos, "r": 70.0, "r0": 10.0, "life": 0.5, "col": col(), "floor": true})
	if sb.has("fx"):
		OB.fx_play(self, sb.fx, zone_c(), _zone_r_now())


func on_kill(e: Dictionary) -> void:
	for t in _trigs():
		if str(t.get("_tag", "")) != "trig.on_kill" or not OB.cond_true(self, t.get("cond", {})):
			continue
		var f: String = str(t.get("filter", "any"))
		if f == "any" or (f == "elite" and (e.elite or e.boss)) or (f == "boss" and e.boss):
			_exec_list(t.get("do", []), e.pos)


func _sfx_op(kind: String) -> void:
	var sfx: Node = g.get_node_or_null("/root/Sfx") if g != null and g.is_inside_tree() else null
	if sfx != null:
		sfx.op(id, kind)


# ---------------------------------------------------------------- 绘制

## 区域：地面椭圆，灯火充盈 / 昏暗 / 其他三种色；shape.orbit 的判定点画成小菱形
func draw_auras() -> void:
	_draw_fields()
	if pos == Vector2.INF or not B.has("zone"):
		return
	var c := zone_c()
	var cc: Color = col()
	if g.lamp >= 70.0:
		cc = cc.lerp(Color(1.0, 0.92, 0.8), 0.4)
	elif g.lamp < 30.0:
		cc = cc.lerp(Color(0.45, 0.2, 0.75), 0.6)
	var on := skill_active()
	var rm := 1.0   # 程序漩涡（§5.6 vortex.ring）可把区域硬边压淡
	for u in _fxb:
		rm = minf(rm, OB.vortex_ring_mul(self, _fxb[u]))
	cv.draw_set_transform(c + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
	cv.draw_circle(Vector2.ZERO, zr, Color(cc.r, cc.g, cc.b, (0.08 if on else 0.045) * rm))
	cv.draw_arc(Vector2.ZERO, zr, 0.0, TAU, 48, Color(cc.r, cc.g, cc.b, ((0.45 if on else 0.28) + 0.06 * sin(g.t * 3.0)) * rm), 2.0)
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_hold_strips(cv, "floor")
	_draw_vortex(cv, "floor")
	for u in _state:
		var st = _state[u]
		if st is Dictionary and st.has("ang"):
			var b := _find_uid(u)
			var pts: Array = OB.orbit_points(self, b, st.ang)
			if b.has("fx") and OB.fx_orbit(cv, self, b, pts, g.world.fx_dim):   # 帧条代替菱形（docs/61 §5.6 at = orbit）
				continue
			for p in pts:
				draw_diamond(p + Vector2(0, -6), 5.0, Color(cc.r * 1.4, cc.g * 1.4, cc.b * 1.4, 0.85), Color(0.05, 0.05, 0.1, 0.7))


## 贴身层（docs/61 §5.6 layer = behind / front）：本体前后各画一遍
func draw_body() -> void:
	_draw_body_fx(false)
	super()
	_draw_body_fx(true)


func _draw_body_fx(front: bool) -> void:
	for u in _fxb:
		OB.fx_body(cv, self, _fxb[u], front)


## 程序漩涡（docs/61 §5.6 vortex）：floor 层在 draw_auras（人物下面）、add 层在 draw_fx_add；进出淡入淡出按条目 fade（缺省 0.5 秒淡入、FX_VORTEX_FADE 秒淡出）
func _draw_vortex(sink, layer: String) -> void:
	if pos == Vector2.INF or g.perf_alt:   # g.perf_alt：--perfab 同局轮换量漩涡开 / 关的净成本（/b 桶不画；正常游戏恒为 false）
		return
	for u in _fxb:
		var e: Dictionary = _fxb[u]
		if not OB.fx_has_vortex(e.b.fx):
			continue
		OB.fx_vortex(sink, self, e, layer, 1.0, zone_c(), zr)


## 常驻跟随帧条（docs/61 §5.6 hold: true，10-12 加）：ground 层在 draw_ground_fx（地砖之上、溟痕 / 地面预警之下）、floor 层在 draw_auras、add 层在 draw_fx_add
func _draw_hold_strips(ci, layer: String) -> void:
	if pos == Vector2.INF:
		return
	for u in _fxb:
		OB.fx_hold_strips(ci, self, _fxb[u], layer, zone_c(), zr)


## squad.draw_ground_fx → 这里（world.draw_world 画完地砖紧接着调；没有 ground 层条目时什么都不画）
func draw_ground_fx() -> void:
	_draw_hold_strips(cv, "ground")


## 画面帧条粒子（docs/61 §5.6）：地面 / 上层在这里画，加色层（add）留给 draw_fx_add
## 德克萨斯段的冲刺剑光 / 旧剑雨（kind = tx_strip：横向拉伸、延迟起播）交给 OB.tx_draw_pfx；剑雨编排（kind = tx_rain，verb.fx_rain）交给 OB.tx_rain_draw
func _draw_pfx(f: Dictionary, a: float) -> bool:
	if str(f.kind) == "tx_strip":
		return OB.tx_draw_pfx(self, f, a)
	if str(f.kind) == "tx_rain":   # verb.fx_rain（docs/61 §13.5）：加色层的在 draw_fx_add 画
		if not f.get("add", false):
			OB.tx_rain_draw(cv, self, f)
		return true
	if str(f.kind) != "strip":
		return OB.mf_draw_pfx(self, f, a)   # 召唤物扩展段的程序粒子（crescent / impact / core / qshard / beamray）
	if not f.get("add", false):
		OB.fx_draw(cv, g, f, g.world.fx_dim)
	return true


func draw_fx_add(ci: CanvasItem, loop: int) -> void:
	super(ci, loop)
	_draw_hold_strips(ci, "add")
	_draw_vortex(ci, "add")
	for f in pfx:
		if str(f.kind) == "strip" and f.get("add", false):
			OB.fx_draw(ci, g, f, g.world.fx_dim)
		elif str(f.kind) == "tx_rain" and f.get("add", false):
			OB.tx_rain_draw(ci, self, f)


func _find_uid(u: int) -> Dictionary:
	for t in _trigs():
		if int(t.get("_uid", -1)) == u:
			return t
		for b in t.get("do", []):
			if int(b.get("_uid", -1)) == u:
				return b
	return {}


func stats_rows() -> Array:
	return [["区域半径", "%d" % int(zr)], ["伤害倍率", "×%.2f" % float(loc.dmg)]]


# ================================================================ 星熊 hoshiguma（docs/59 §3，docs/61「星熊」节）：新积木的执行（op_blocks.gd 末尾同名段落）
## shape.line / verb.field（瞬时留场；verb.displace 与常驻力场在共用段 / 安洁莉娜段）/ verb.negate_next / verb.dr / verb.negate_chance / verb.swap_attack / trig.on_hurt / trig.on_negate。
## 受击询问走 character 的 dmg_taken_mult 挂点（combat.gd enemy_hit 在闪避 / 护盾之后、扣血之前逐个干员询问）：返回 0 = 这一下被格挡，
## combat.gd 整下作废（不扣血、不掉灯火、不吃控制 / 侵蚀，同闪避给 0.3 秒无敌）。

const FIELD_CAP := 16                   # 每名干员同时存在的地面区域上限（超出时最早的先消失）

var last_hit_pos := Vector2.INF        # 上一次普攻命中的第一个敌人（verb.field center: last_hit）
var neg_armed: Dictionary = {}         # 待命的 verb.negate_next：技能序号 → 积木
var fields: Array = []                 # 地面区域：{pos, r, t, dur, every, n, done, do, fx}
var ext_dr := 1.0                      # 本帧 verb.dr 的乘积
var neg_add := 0.0                     # 本帧 verb.negate_chance 的 Σadd
var neg_mul := 1.0                     # 本帧 verb.negate_chance 的 Πmult
var swap_atk: Dictionary = {}          # 本帧生效的 verb.swap_attack（空 = 用 blocks.attack）
var negate_n := 0                      # 本局格挡次数（图鉴 / 测试看）
var _hurt_cd: Dictionary = {}          # trig.on_hurt 的冷却（_uid → 下次可触发的 g.t）


## 当前普攻形状：verb.swap_attack 生效时用它，否则 blocks.attack
func cur_attack() -> Dictionary:
	return swap_atk if not swap_atk.is_empty() else B.get("attack", {})


## 执行一个伤害形状（circle / cone 走 op_blocks.exec_shape，line 走 exec_line）；is_attack = 普攻出手，记下第一个命中点
func exec_any_shape(b: Dictionary, at: Vector2 = Vector2.INF, is_attack := false) -> Array:
	var hits: Array = OB.exec_line(self, b) if str(b.get("shape", "")) == "line" else OB.exec_shape(self, b, at)
	if is_attack:
		last_hit_pos = hits[0].pos if not hits.is_empty() else Vector2.INF
		if b.get("slash", false) and not hits.is_empty() and str(b.get("shape", "")) == "cone":
			slash_fx(pos, (hits[0].pos - pos).angle(), deg_to_rad(float(b.get("half_deg", 45.0))), OB.shape_radius(self, b), col())
	return hits


## 常驻部分（_sustain 末尾调用；act 是本帧生效的常驻积木，条件已求值）
func _ext_sustain(act: Array, dt: float) -> void:
	var dr := 1.0
	var add := 0.0
	var mul := 1.0
	var sw: Dictionary = {}
	for b in act:
		match str(b.get("_tag", "")):
			"verb.dr":
				dr *= 1.0 - float(b.value)
			"verb.negate_chance":
				add += float(b.get("add", 0.0))
				mul *= float(b.get("mult", 1.0))
			"verb.swap_attack":
				if sw.is_empty():
					sw = b.attack
	ext_dr = dr
	neg_add = add
	neg_mul = mul
	swap_atk = sw
	# 技能结束仍没挨打：negate_next 执行 on_miss（不白放）
	if not neg_armed.is_empty():
		var ks: Array = neg_armed.keys()
		ks.sort()
		for i in ks:
			if not skill_on(int(i)):
				var nb: Dictionary = neg_armed[i]
				neg_armed.erase(i)
				_exec_list(nb.get("on_miss", []))
	# 地面区域：按 tick 计数（第 k 次在 k × every 秒），不靠浮点累加，次数 = round(dur / every)
	if not fields.is_empty():
		for f in fields:
			f.t += dt
			while f.done < f.n and f.t >= (f.done + 1) * f.every - 0.0001:
				f.done += 1
				_exec_list(f.do, f.pos)
		fields = fields.filter(func(f): return f.done < f.n)


## 瞬时部分（_exec_list 认不出的族.名转到这里）
func _ext_exec(b: Dictionary, at: Vector2) -> void:
	match str(b.get("_tag", "")):
		"shape.line":
			OB.exec_line(self, b)
		"verb.field":
			if b.has("tick"):   # 常驻力场（安洁莉娜）在 _sustain 里，这里只管瞬时留场
				return
			var c: Vector2 = OB.field_center(self, b, at)
			if c == Vector2.INF:
				return
			var ev: float = float(b.every)
			var fr: float = float(b.r) * stat(&"op_range") * float(loc.area)
			fields.append({"pos": c, "r": fr, "t": 0.0, "dur": float(b.dur), "every": ev,
				"n": maxi(1, roundi(float(b.dur) / ev)), "done": 0, "do": b.get("do", []), "fx": b.get("fx", [])})
			if fields.size() > FIELD_CAP:
				fields.pop_front()
			if b.has("fx"):   # 通用 fx（§5.6）：中心 = 区域中心、半径 = 区域半径；没写 life 的条目循环到区域结束
				var fl: Array = []
				for f in b.fx:
					fl.append(f if not (f is Dictionary) or f.has("life") else f.merged({"life": float(b.dur)}))
				OB.fx_play(self, fl, c, fr)
		"verb.negate_next":
			if cur_skill >= 0:
				neg_armed[cur_skill] = b


## 主控受击询问（combat.gd enemy_hit）：先用待命的 negate_next，再按固定顺序过 trig.on_hurt；格挡了返回 0，否则返回 verb.dr 的乘积
func dmg_taken_mult() -> float:
	var src: Dictionary = g.combat.cur_src
	var boss: bool = src.get("boss", false)
	var negated := false
	if not neg_armed.is_empty():
		var ks: Array = neg_armed.keys()
		ks.sort()
		var i: int = int(ks[0])
		var nb: Dictionary = neg_armed[i]
		neg_armed.erase(i)
		s_t[i] = 0.0   # 「下一次」用掉了，技能随即结束
		negated = true
		_negate_fx(nb)
		_defer(nb.get("on_block", []))
	for t in _trigs():
		if str(t.get("_tag", "")) != "trig.on_hurt" or not OB.cond_true(self, t.get("cond", {})):
			continue
		var neg: bool = t.get("negate", false)
		if neg and negated:
			continue
		var u: int = int(t.get("_uid", 0))
		if float(_hurt_cd.get(u, -INF)) > g.t:
			continue
		if not OB.roll(g, OB.hurt_chance(t, boss, neg_add, neg_mul)):
			continue
		if t.has("cd"):
			_hurt_cd[u] = g.t + float(t.cd)
		if neg:
			negated = true
			_negate_fx(t)
		_defer(t.get("do", []))
	if not negated:
		return OB.shield_mult(self, OB.mf_guard_mult(self, ext_dr))   # 召唤物扩展段 verb.guard 的限时减伤；召唤 / 封印段：verb.shield 在减伤之后吸收（没有护盾时原样返回）
	negate_n += 1
	for t in _trigs():
		if str(t.get("_tag", "")) == "trig.on_negate" and OB.cond_true(self, t.get("cond", {})):
			_defer(t.get("do", []))
	return 0.0


## 受击询问里触发的积木推迟到本干员下一次 update 开头执行（延迟队列，t = 0）：enemy_hit 常在敌人遍历中途被调用，
## 不在那里造成伤害 / 击杀，免得遍历中改敌人列表；顺序仍固定（同 seed 可复现）
func _defer(arr: Array) -> void:
	if not arr.is_empty():
		pending.append({"t": 0.0, "do": arr})


## 格挡的画面 / 声音（不碰 g.rng）：通用 fx（§5.6，中心 = 主控）、text = 飘字（缺省「格挡」）
func _negate_fx(b: Dictionary) -> void:
	if b.has("fx"):
		OB.fx_play(self, b.fx, g.ppos, 30.0)
	float_text(g.ppos + Vector2(0, -88), str(b.get("text", "格挡")), Color(1.0, 0.85, 0.4), 16)
	_sfx_op("big")


## 地面层：区域帧条由通用 fx 在生成时播（pfx，循环到区域结束）；没写 fx / 缺图时画程序椭圆；negate_next 待命时主控脚下一圈金色盾环
func draw_entities_floor() -> void:
	for f in fields:
		if OB.fx_any_tex(self, f.fx):
			continue
		var a: float = clampf((f.n * f.every - f.t) / 0.4, 0.0, 1.0) * clampf(f.t / 0.15, 0.0, 1.0)
		var cc: Color = col()
		cv.draw_set_transform(f.pos, 0.0, Vector2(1.0, 0.5))
		cv.draw_circle(Vector2.ZERO, float(f.r), Color(cc.r, cc.g, cc.b, 0.16 * a))
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if not neg_armed.is_empty() and g.ppos != Vector2.INF:
		var k: float = 0.55 + 0.25 * sin(g.t * 8.0)
		cv.draw_set_transform(g.ppos + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
		cv.draw_arc(Vector2.ZERO, 30.0, 0.0, TAU, 32, Color(1.0, 0.82, 0.35, k), 2.5)
# ================================================================ 安洁莉娜 angelina（docs/59 §5；docs/61 §12）—— 第三批追加段，只往后加
# shape.point_aoe 的飞行弹、dur.next_n 的次数、st.airborne 的悬浮表、verb.field 的画法；积木本身在 op_blocks.gd 的同名段

const GRAV := Color(0.7, 0.5, 0.95)   # 重力紫（docs/59 §5 特效主色）
var ammo: Array = [0, 0, 0]            # dur.next_n：技能 i 还剩几次强化普攻
var shots: Array = []                  # shape.point_aoe 飞行中的弹：[{p0, p1, t, dur, patch}]
var shot: Dictionary = {}              # 正在结算的这一弹的 attack_patch（verb.displace 读 force_mult）
var air_list: Array = []               # st.airborne：[{e, t, dur, h}]
var atk_to := Vector2.INF              # point_aoe 起手时选的落点（出手帧找不到新落点时用）


func skill_pending(i: int) -> bool:
	return ammo[i] > 0


## 出手帧：手动给了方向用 aim_land，否则重新选最密处（起手到出手之间敌人会动），都没有用起手时的落点；接下来 N 次的强化按技能序号先到先用
func _fire_point_aoe(a: Dictionary) -> void:
	var reach: float = float(a.get("range", 300.0)) * stat(&"op_range")
	var to := Vector2.INF
	var lp: Dictionary = aim_land(reach)
	if not lp.is_empty():
		to = lp.pos
	else:
		to = OB.point_aoe_target(self, a)
	if to == Vector2.INF:
		to = atk_to
	if to == Vector2.INF:
		return
	face = signf(to.x - pos.x) if absf(to.x - pos.x) > 2.0 else face
	var patch := {}
	var sk: Array = B.get("skills", [])
	for i in 3:
		if ammo[i] > 0 and i < sk.size():
			ammo[i] -= 1
			patch = sk[i].get("attack_patch", {})
			break
	OB.point_aoe_fire(self, a, to, patch)


func _tick_shots(dt: float) -> void:
	OB.airborne_tick(self, dt)
	if shots.is_empty():
		return
	var a: Dictionary = B.get("attack", {})
	var landed: Array = []
	for s in shots:
		s.t += dt
		if s.t >= s.dur:
			landed.append(s)
	shots = shots.filter(func(s): return s.t < s.dur)
	for s in landed:
		OB.point_aoe_land(self, a, s)
		_sfx_op("hit")
		fx({"kind": "ring", "pos": s.p1, "r": float(a.get("r", 60.0)) * float(loc.area), "r0": 6.0, "life": 0.3, "col": GRAV, "floor": true, "w": 2.0, "alpha": 0.7})


## 落点触发（trig.on_impact）：c = 落点；delay > 0 进延迟队列（带落点）
func impact(c: Vector2) -> void:
	for t in _trigs():
		if str(t.get("_tag", "")) != "trig.on_impact" or not OB.cond_true(self, t.get("cond", {})):
			continue
		var dl: float = float(t.get("delay", 0.0))
		if dl > 0.0:
			pending.append({"t": dl, "do": t.get("do", []), "at": c})
		else:
			_exec_list(t.get("do", []), c)


## 力场（verb.field look）：ring = 地面环带虚线缓慢旋转 + 内外两圈相向的光点（S2 重力场）；lift = 大圆 + 上升光点（S3 悬浮场）。
## 悬浮中的敌人脚下挂 fx_angelina_levitate。全部只读 g.t，不碰随机数
func _draw_fields() -> void:
	for u in _state:
		var st = _state[u]
		if not (st is Dictionary) or not st.has("look") or st.look == "none" or st.c == Vector2.INF:
			continue
		var c: Vector2 = st.c
		var r: float = st.r
		var gt: float = g.t
		cv.draw_set_transform(c + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
		if st.look == "ring":
			var rr: float = st.ring if st.ring > 0.0 else r * 0.7
			cv.draw_circle(Vector2.ZERO, r, Color(GRAV.r, GRAV.g, GRAV.b, 0.035))
			cv.draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(GRAV.r, GRAV.g, GRAV.b, 0.16), 1.0)
			var n := 24
			for q in n:
				var a0: float = TAU * q / n + gt * 0.35
				cv.draw_arc(Vector2.ZERO, rr, a0, a0 + TAU / n * 0.55, 4, Color(GRAV.r * 1.3, GRAV.g * 1.3, GRAV.b * 1.3, 0.55), 2.0)
			for q in 10:
				var k: float = fmod(gt * 0.6 + q * 0.1, 1.0)
				var ang: float = TAU * q / 10.0 + 0.4 * q
				var po: Vector2 = Vector2.from_angle(ang) * lerpf(r, rr, k)          # 外圈往里
				var pin: Vector2 = Vector2.from_angle(ang + 0.3) * lerpf(rr * 0.35, rr, k)   # 内圈往外
				var al: float = sin(k * PI) * 0.8
				cv.draw_circle(po, 2.2, Color(GRAV.r * 1.6, GRAV.g * 1.6, GRAV.b * 1.6, al))
				cv.draw_circle(pin, 1.8, Color(1.2, 1.0, 1.5, al * 0.7))
		else:
			var pulse: float = 0.5 + 0.5 * sin(gt * 2.4)
			cv.draw_circle(Vector2.ZERO, r, Color(GRAV.r, GRAV.g, GRAV.b, 0.06 + 0.02 * pulse))
			for q in 32:
				var a1: float = TAU * q / 32 - gt * 0.25
				cv.draw_arc(Vector2.ZERO, r, a1, a1 + TAU / 64.0, 3, Color(GRAV.r * 1.4, GRAV.g * 1.4, GRAV.b * 1.4, 0.6), 2.0)
			cv.draw_arc(Vector2.ZERO, r * 0.55, 0.0, TAU, 40, Color(GRAV.r, GRAV.g, GRAV.b, 0.12 + 0.1 * pulse), 1.5)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if st.look == "lift":
			for q in 14:
				var k2: float = fmod(gt * 0.45 + q * 0.071, 1.0)
				var ang2: float = TAU * q / 14.0 + q * 1.7
				var rad: float = r * (0.25 + 0.7 * fmod(q * 0.37, 1.0))
				var p2: Vector2 = c + Vector2(cos(ang2) * rad, sin(ang2) * rad * 0.55) + Vector2(0, -60.0 * k2)
				cv.draw_circle(p2, 1.8, Color(1.3, 1.0, 1.6, sin(k2 * PI) * 0.7))
	var lt: Texture2D = _fx_tex("fx_angelina_levitate") if not air_list.is_empty() else null
	for a in air_list:
		var e: Dictionary = a.e
		if e.dead:
			continue
		var fr: int = int((g.t + float(e.id) * 0.13) * 10.0) % 6
		if lt == null or not _fx_strip("fx_angelina_levitate", 6, fr, e.pos + Vector2(0, float(e.r) * 0.8), Vector2(0.5, 27.0 / 32.0)):
			cv.draw_set_transform(e.pos + Vector2(0, float(e.r) * 0.8), 0.0, Vector2(1.0, 0.45))
			cv.draw_arc(Vector2.ZERO, float(e.r) + 4.0, 0.0, TAU, 20, Color(GRAV.r * 1.4, GRAV.g * 1.4, GRAV.b * 1.4, 0.7), 2.0)
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 重力弹：杖头飞向落点，略带弧线；proj_angelina_orb 循环帧条（docs/25 §6，锚点居中）+ 落点地面预示圈
func _draw_shots() -> void:
	if shots.is_empty():
		return
	var a: Dictionary = B.get("attack", {})
	for s in shots:
		var k: float = clampf(s.t / maxf(0.01, s.dur), 0.0, 1.0)
		var p: Vector2 = s.p0.lerp(s.p1, k) + Vector2(0, -sin(k * PI) * 26.0)
		var big: bool = not s.patch.is_empty()
		cv.draw_circle(p, 11.0 if big else 8.0, Color(GRAV.r, GRAV.g, GRAV.b, 0.25))
		if _fx_tex("proj_angelina_orb") != null:
			draw_spr_rot("proj_angelina_orb", int(g.t * 12.0) % 4, p, 0.0, g.PX * (1.35 if big else 1.0))
		else:
			cv.draw_circle(p, 5.0, Color(GRAV.r * 1.6, GRAV.g * 1.6, GRAV.b * 1.6))
		var lr: float = float(a.get("r", 60.0)) * float(loc.area) * float(s.patch.get("r_mult", 1.0))
		cv.draw_set_transform(s.p1 + Vector2(0, 4), 0.0, Vector2(1.0, 0.5))
		cv.draw_arc(Vector2.ZERO, lr * (1.0 - 0.6 * k), 0.0, TAU, 28, Color(GRAV.r, GRAV.g, GRAV.b, 0.35 * k), 1.5)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
# ---------------------------------------------------------------- 能天使（docs/61 §14）：弹体与状态条（实现在 op_blocks.gd 末尾）

func _draw_skill_over() -> void:
	_draw_shots()      # 安洁莉娜段：重力弹
	OB.exu_draw(self)  # 能天使段：弹体
	OB.sm_draw_over(self)   # 召唤 / 封印段：封印标记、护盾
	OB.mf_draw_guards(self)  # 召唤物扩展段：限时减伤护壳


func status_items() -> Array:
	return OB.mf_status_items(self) + OB.exu_status_items(self) + OB.sm_status_items(self)


# ---------------------------------------------------------------- 召唤 / 封印段（docs/61 §15）：召唤物参与 2.5D 排序（同凯尔希 Mon3tr 的 extra_bodies）

func extra_bodies() -> Array:
	return OB.sm_bodies(self)


func draw_extra(it: Dictionary) -> void:
	OB.sm_draw(self, it.s)


func draw_extra_shadows() -> void:
	OB.sm_shadows(self)
