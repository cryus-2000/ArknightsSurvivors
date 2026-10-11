## 积木等价测试的手写参照（docs/61 §测试）：tests/data_ops/eqtest.json 的同一份数值，按 13 名手写干员的写法实现（base() 取数、update 里自己计时），
## 不调用 op_blocks.gd。数据版（data_operator.gd）同 seed 的 TRACE / BALANCE 必须和它逐字节相同（tools/check.py blocks_eq）。
## 加载：--op=eqtest --opscript=eqtest=res://tests/data_ops/eqtest_hand.gd。
## 为了逐字节相同，这里的「本帧条件 → 局部倍率 → 属性修正 → 治疗 / 灯火 / 共鸣 / 软减速 / 音符」顺序与数据版一致（docs/61 §5.5），
## 属性修正也按同一顺序整组重建——手写干员（乌尔比安 _apply_stacks）本来也是这么做的。
extends "res://scripts/characters/character.gd"

var cd := 0.5
var s1_t := 0.0
var s3_t := 0.0
var s2_on := false
var n1 := false
var n2 := false
var echo_on := false
var res_on := false
var atk_n := 0
var echo_q: Array = []        # 回声倒计时（秒）
var zone_mult := 1.0
var dmg_mult := 1.0
var zr := 0.0
var applied: Array = []
var heal_acc := -1.0          # -1 = 本帧之前没在计时
var s1_heal_acc := -1.0
var res_acc := -1.0
var soft_mem: Dictionary = {}
var orb_on := false
var orb_ang := 0.0
var orb_hit: Dictionary = {}


func on_custom_node(nid: String, _choice: String = "") -> void:
	match nid:
		"n1":
			n1 = true
		"n2":
			n2 = true
		"echo":
			echo_on = true
		"res":
			res_on = true


func _zc() -> Vector2:
	return g.ppos if g.demo_op == "" else pos


func _in_zone(p: Vector2) -> bool:
	return p != Vector2.INF and p.distance_to(_zc()) <= zr


func skill_active_left(i: int) -> float:
	return s1_t if i == 0 else (s3_t if i == 2 else 0.0)


func skill_active_dur(i: int) -> float:
	return base("s1_dur", 4.0) if i == 0 else (base("s3_dur", 8.0) if i == 2 else 1.0)


func _swing_radius() -> float:
	return zr


func _hunters() -> int:
	var n := 0
	for o in g.squad.ops:
		if o != self and "深海猎人" in o.def.get("faction", []):
			n += 1
	return n


func update(dt: float) -> void:
	cd -= dt
	if s1_t > 0.0:
		s1_t = maxf(0.0, s1_t - dt)
	if s3_t > 0.0:
		s3_t = maxf(0.0, s3_t - dt)
	# 回声（延迟 0.2 秒）
	if not echo_q.is_empty():
		var due := 0
		for k in echo_q.size():
			echo_q[k] -= dt
			if echo_q[k] <= 0.0:
				due += 1
		echo_q = echo_q.filter(func(t): return t > 0.0)
		for k in due:
			_pulse(base("echo_mult", 0.5), "测试回声", ["follow_up"], int(base("echo_max_n", 0.0)))
	# ---- 本帧条件（帧首求值一次）
	var s1 := s1_t > 0.0
	var s3 := s3_t > 0.0
	var talent := elite >= 1
	var heal_on := _in_zone(g.ppos)
	var drain: bool = s3 and g.lamp >= base("dark", 30.0)
	var bright: bool = talent and g.lamp >= base("bright", 70.0)
	var dark: bool = talent and g.lamp < base("dark", 30.0)
	var res := res_on and s1
	# ---- 区域与伤害倍率
	var za := 0.0
	var zm := 1.0
	var da := 0.0
	var dm := 1.0
	if s1:
		zm *= base("s1_zone", 1.3)
	if s2_on:
		za += base("s2_zone", 0.25)
		da += base("s2_dmg", 0.2)
	if s3:
		dm *= base("s3_mult", 2.5) * skill_power()
	if bright:
		za += base("bright_zone", 0.15)
	if dark:
		dm *= base("dark_mult", 1.4)
	if n1:
		zm *= base("n1_zone", 1.15)
	if n2:
		dm *= base("n2_dmg", 1.15)
	zone_mult = (1.0 + za) * zm
	dmg_mult = (1.0 + da) * dm
	zr = base("aura", 170.0) * stat(&"op_range") * zone_mult
	# ---- 属性修正：一技能灯火流失、二技能区域内攻速、三技能全队攻击、天赋深海猎人
	var want: Array = []
	if s1:
		want.append(["light_loss", "mult", base("s1_loss", 0.5), ""])
	if s2_on:
		var v: float = base("s2_aspd", 0.12) * skill_power()
		for o in g.squad.ops:
			if _in_zone(o.pos):
				want.append(["op_aspd", "add", v, "op:" + o.id])
	if s3:
		var v3: float = base("s3_atk", 0.3) * skill_power()
		for o in g.squad.ops:
			want.append(["op_atk", "add", v3, "op:" + o.id])
	if talent:
		var vh: float = base("mate_atk", 0.03) * float(mini(_hunters(), int(base("mate_cap", 3.0))))
		if vh != 0.0:
			for o in g.squad.ops:
				if _in_zone(o.pos):
					want.append(["op_atk", "add", vh, "op:" + o.id])
	if want != applied:
		g.stats.remove_source("eqtest_hand")
		for m in want:
			g.stats.add(StringName(m[0]), m[1], m[2], "eqtest_hand", m[3])
		applied = want
		refresh_stats()
	# ---- 治疗 / 灯火 / 软减速 / 共鸣 / 音符
	if heal_on:
		heal_acc = maxf(heal_acc, 0.0) + dt
		if heal_acc >= base("heal_cd", 2.0):
			heal_acc -= base("heal_cd", 2.0)
			_heal(base("heal_pct", 0.004), false)
	else:
		heal_acc = -1.0
	if s1:
		s1_heal_acc = maxf(s1_heal_acc, 0.0) + dt
		if s1_heal_acc >= 1.0:
			s1_heal_acc -= 1.0
			_heal(base("s1_heal", 0.01), true)
	else:
		s1_heal_acc = -1.0
	if drain:
		g.lamp = clampf(g.lamp + -base("s3_drain", 1.5) * dt, 0.0, g.lamp_cap)
	if dark:
		_soft_slow()
	else:
		soft_mem = {}
	if res:
		res_acc = maxf(res_acc, 0.0) + dt
		if res_acc >= 1.0:
			res_acc -= 1.0
			var hits := _pulse(base("res_mult", 0.3), "测试共鸣", ["skill", "dot"])
			for e in hits:
				if not e.dead and not e.boss:
					e.slow = maxf(e.slow, base("res_slow", 0.5) * (0.5 if e.elite else 1.0))
	else:
		res_acc = -1.0
	if elite >= 2:
		_orbit(dt)
	# ---- 技能 / 普攻
	if acting():
		return
	var ready := charge_skills(dt)
	if ready >= 0:
		start_skill(Vector2.INF, ready)
		return
	if cd > 0.0:
		return
	var at := atk_point(nearest_enemies(1, zr, _zc()), zr)
	if at == Vector2.INF:
		cd = idle_cd(0.2)
	else:
		cd = base("cd", 0.9) / stat(&"op_aspd")
		start_attack(at)


func _heal(pct: float, power: bool) -> void:
	if g.hp >= g.max_hp:
		return
	var h: float = g.max_hp * pct
	if power:
		h *= skill_power()
	heal_leader(h, display_name())


func _pulse(mult: float, src: String, tags: Array, max_n := 0) -> Array:
	return area_hit(src, _zc(), zr, base("atk", 0.0) * mult * dmg_mult * _dmg_bonus(), 0.0, 0.0, tags, max_n)


func _soft_slow() -> void:
	var c := _zc()
	var nm := {}
	for j in query_ids(c, zr + 20.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or e.boss or e.pos.distance_to(c) > zr:
			continue
		if soft_mem.has(e.id):
			var last: Vector2 = soft_mem[e.id]
			e.pos -= (e.pos - last) * base("dark_slow", 0.1)
		nm[e.id] = e.pos
	soft_mem = nm


func _orbit(dt: float) -> void:
	orb_ang += base("orb_speed", 0.9) * dt
	var c := _zc()
	var n := int(base("orb_n", 4.0))
	var hr: float = base("orb_hit", 18.0)
	var r: float = zr
	for k in n:
		var a: float = orb_ang + k * TAU / float(n)
		var p: Vector2 = c + Vector2(cos(a) * r, sin(a) * r * 0.55)
		for j in query_ids(p, hr + 24.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or e.boss or e.pos.distance_to(p) > hr + float(e.r):
				continue
			if float(orb_hit.get(e.id, -1.0)) > g.t:
				continue
			orb_hit[e.id] = g.t + base("orb_cd", 0.5)
			log_hit("测试音符", ["basic"])
			deal_damage(e, base("atk", 0.0) * base("orb_mult", 0.2) * dmg_mult * _dmg_bonus())
			if e.dead:
				continue
			var d: Vector2 = e.pos - c
			e.kb += (d.normalized() if d.length() > 0.5 else Vector2.RIGHT) * base("orb_kb", 100.0) * (0.3 if e.elite else 1.0)
	if orb_hit.size() > 64:
		for k in orb_hit.keys():
			if float(orb_hit[k]) <= g.t:
				orb_hit.erase(k)


func _release() -> void:
	_pulse(1.0, "测试脉冲", ["basic"])
	var sfx: Node = g.get_node_or_null("/root/Sfx") if g.is_inside_tree() else null
	if sfx != null:
		sfx.op(id, "atk")
	atk_n += 1
	if echo_on and atk_n % int(base("echo_n", 3.0)) == 0:
		echo_q.append(base("echo_delay", 0.2))


func _release_skill() -> void:
	match cur_skill:
		0:
			s1_t = base("s1_dur", 4.0)
			g.squad.gain_sp(base("s1_sp", 0.1), self)
		1:
			s2_on = true
		2:
			s3_t = base("s3_dur", 8.0)
			var r: float = base("s3_cone_r", 140.0) * stat(&"op_range")
			var ts: Array = nearest_enemies(1, r + 30.0, pos)
			var ang: float = atk_angle((ts[0].pos - pos).angle() if not ts.is_empty() else facing_angle())
			var hits := melee_hit("测试斩", pos, ang, deg_to_rad(base("s3_cone_deg", 60.0)), r,
				base("atk", 0.0) * base("s3_cone_mult", 3.0) * dmg_mult * _dmg_bonus() * skill_power(), 0.0, 0.0, ["skill"])
			for e in hits:
				if not e.dead and not e.boss:
					e.stun = maxf(e.stun, base("s3_stun", 0.6) * (0.5 if e.elite else 1.0))


func on_kill(e: Dictionary) -> void:
	if e.elite or e.boss:
		_heal(base("kill_heal", 0.002), false)
