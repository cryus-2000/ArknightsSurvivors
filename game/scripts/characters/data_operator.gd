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
var loc := {"zone": 1.0, "dmg": 1.0, "heal": 1.0, "interval": 1.0}   # 本干员局部倍率（docs/61 §5.1）
var no_attack := false
var zr := 0.0                          # 本帧区域半径（上一帧的值给 in_zone 条件用）
var _mods: Array = []                  # 已写进 g.stats 的修正 [stat, op, value, scope]
var _acc: Dictionary = {}              # 常驻积木的累计器（_uid → 秒）
var _state: Dictionary = {}            # 常驻积木的状态（软减速的位置记忆、绕行体角度）
var _warned := {}
var ext := {}                          # 积木扩展段的运行时状态（能天使：弹体 / 计数器 / 次数型技能，op_blocks.gd 末尾）


func _init(game, def_: Dictionary) -> void:
	super(game, def_)
	B = OB.compile(def)


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
	return s_t[i] > 0.0 or perm_on[i]


func skill_active_left(i: int) -> float:
	return maxf(s_t[i], OB.exu_ammo_left(self, i))   # 次数型（dur.ammo）返回剩余发数


func skill_active_dur(i: int) -> float:
	return s_dur[i] if s_dur[i] > 0.0 else 1.0


func _swing_radius() -> float:
	var a: Dictionary = B.get("attack", {})
	return OB.shape_radius(self, a) if a.has("shape") else 90.0


# ---------------------------------------------------------------- 成长

func on_custom_node(nid: String, _choice: String = "") -> void:
	taken.append(nid)
	nodes_taken = ",".join(taken)


func on_leave() -> void:
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
			out.append(pg[nid])
	for k in [["elite1", 1], ["elite2", 2]]:
		if elite >= k[1] and pg.has(k[0]):
			out.append(pg[k[0]])
	return out


# ---------------------------------------------------------------- 每帧

func update(dt: float) -> void:
	cd -= dt
	for i in 3:
		if s_t[i] > 0.0:
			s_t[i] = maxf(0.0, s_t[i] - dt)
	_tick_pending(dt)
	_sustain(dt)
	OB.exu_tick(self, dt)   # 能天使挂钩（docs/61 §11）：技能 end、普攻锁、连射队列、弹体
	if acting():
		return
	var ready := charge_skills(dt)
	if ready >= 0:
		start_skill(Vector2.INF, ready)
		return
	if no_attack or cd > 0.0:
		return
	var a: Dictionary = B.get("attack", {})
	var at := Vector2.INF
	match str(a.get("shape", "")):
		"circle":
			var c: Vector2 = OB.shape_center(self, a)
			var r: float = float(a.get("range", 0.0)) * stat(&"op_range") if a.has("range") else OB.shape_radius(self, a)
			if c != Vector2.INF:
				at = atk_point(nearest_enemies(1, r, c), r)   # 手动普攻（v2.5）：不分方向，只受闸门
		"cone":
			var r2: float = OB.shape_radius(self, a)
			at = atk_point(nearest_enemies(1, r2 + 30.0, pos), r2)   # 手动普攻 A 类
		"projectile":   # 能天使挂钩（docs/61 §11）：手动普攻 B 类
			at = OB.exu_aim(self, a)
	if at == Vector2.INF:
		cd = idle_cd(0.2)
	else:
		cd = float(a.get("every", 1.0)) / stat(&"op_aspd") * float(loc.interval)
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
		_exec_list(p.do)


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
			_collect_trig(pg[nid], act)
	for k in [["elite1", 1], ["elite2", 2]]:
		if elite >= k[1] and pg.has(k[0]):
			_collect_trig(pg[k[0]], act)
	# 一：局部倍率
	var add := {"zone": 0.0, "dmg": 0.0, "heal": 0.0, "interval": 0.0}
	var mul := {"zone": 1.0, "dmg": 1.0, "heal": 1.0, "interval": 1.0}
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
			"aura.atk", "aura.aspd", "aura.skill_power", "aura.range":
				var v: float = float(b.value)
				if b.get("power", false):
					v *= skill_power()
				if b.has("per"):
					v *= float(mini(OB.count_others(self, str(b.per)), int(b.get("cap", 99))))
				if v != 0.0:
					for m in OB.aura_members(self, str(b.scope)):
						want.append([OB.AURA_STAT[str(b.aura)], "add", v, "op:" + m.id])
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
	# 这一帧没生效的累计器 / 状态清零（技能结束、条件不成立时重新计时）
	for u in _acc.keys():
		if not seen.has(u):
			_acc.erase(u)
	for u in _state.keys():
		if not seen.has(u):
			_state.erase(u)


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
	if g.hp >= g.max_hp:
		return
	var h: float = g.max_hp * float(b.pct) * float(loc.heal)
	if b.get("power", false):
		h *= skill_power()
	heal_leader(h, str(b.get("src", display_name())))


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
			"custom":
				var fn: String = str(b.custom)
				if has_method(fn):
					call(fn, b)
				elif not _warned.has(fn):
					_warned[fn] = true
					push_warning("数据干员 %s：custom 函数「%s」不存在，已忽略" % [id, fn])
			_:   # 能天使挂钩（docs/61 §11）：shape.projectile / verb.counter / verb.attack_lock
				OB.exu_exec(self, b, at)


# ---------------------------------------------------------------- 出手

func _release() -> void:
	OB.exec_shape(self, B.get("attack", {}))
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
	elif dv is Dictionary:   # 能天使挂钩（docs/61 §11）：dur.ammo
		OB.exu_skill_shell(self, i, dv)
	elif float(dv) > 0.0:
		s_t[i] = float(dv)
		s_dur[i] = float(dv)
	_exec_list(sb.get("do", []))
	fx({"kind": "ring", "pos": pos, "r": 70.0, "r0": 10.0, "life": 0.5, "col": col(), "floor": true})


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
	if pos == Vector2.INF or not B.has("zone"):
		return
	var c := zone_c()
	var cc: Color = col()
	if g.lamp >= 70.0:
		cc = cc.lerp(Color(1.0, 0.92, 0.8), 0.4)
	elif g.lamp < 30.0:
		cc = cc.lerp(Color(0.45, 0.2, 0.75), 0.6)
	var on := skill_active()
	cv.draw_set_transform(c + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
	cv.draw_circle(Vector2.ZERO, zr, Color(cc.r, cc.g, cc.b, 0.08 if on else 0.045))
	cv.draw_arc(Vector2.ZERO, zr, 0.0, TAU, 48, Color(cc.r, cc.g, cc.b, (0.45 if on else 0.28) + 0.06 * sin(g.t * 3.0)), 2.0)
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for u in _state:
		var st = _state[u]
		if st is Dictionary and st.has("ang"):
			var b := _find_uid(u)
			for p in OB.orbit_points(self, b, st.ang):
				draw_diamond(p + Vector2(0, -6), 5.0, Color(cc.r * 1.4, cc.g * 1.4, cc.b * 1.4, 0.85), Color(0.05, 0.05, 0.1, 0.7))


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


# ---------------------------------------------------------------- 能天使（docs/61 §11）：弹体与状态条（实现在 op_blocks.gd 末尾）

func _draw_skill_over() -> void:
	OB.exu_draw(self)


func status_items() -> Array:
	return OB.exu_status_items(self)
