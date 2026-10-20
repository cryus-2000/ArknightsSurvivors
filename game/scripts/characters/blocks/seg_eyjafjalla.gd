## 干员积木 · seg_eyjafjalla（docs/101 §7.3 B6 ①，10-15：由 op_blocks.gd 按段拆出，内容与注释照搬；继承链与门面见 op_blocks.gd）
extends "res://scripts/characters/blocks/seg_skadi.gd"

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
	for m in b.get("aoe_mults", _EA):
		if cond_true(o, m.get("cond", _ED)):
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
	if b.has("lob") and cond_true(o, b.lob.get("cond", _ED)):   # 精英化第 2 批段：低弧抛射三角落点 + 熔池（取代直线弹与后续弹）
		hw_lob_volley(o, b, hw_tip(o, b), ts[0].pos, pre, aoe, oe)
		if b.has("fire_fx"):
			fx_play(o, b.fire_fx, hw_tip(o, b), 10.0)
		return
	_hw_cast(o, b, hw_tip(o, b), ts[0].pos, pre, aoe, 1.0, oe, not is_atk)
	var tip: Vector2 = hw_tip(o, b)   # 发射时可能转了身：后续弹与出手光按转身后的出手点（同手写）
	if b.has("fire_fx"):
		fx_play(o, b.fire_fx, tip, 10.0)
	for f in b.get("follow", _EA):
		if not cond_true(o, f.get("cond", _ED)):
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
				tos.append(at + Vector2.from_angle(g.rng_op.randf() * TAU) * aoe * float(b.get("pad_k", 1.5)))
		"shuffle":
			var mc: Array = o.nearest_enemies(int(b.get("cand", 10)), float(b.get("reach", 320.0)), at)
			o.shuffle_rng(mc)
			for k in mini(n, mc.size()):
				tos.append(mc[k].pos)
		"ring":
			var a0: float = g.rng_op.randf() * TAU
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
		for s in b.get("on_hit", _EA):
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
					_F().hw_melt_mark(o, e, s)
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
			var at: Vector2 = c + Vector2(g.rng_op.randf_range(-float(jv[0]), float(jv[0])), g.rng_op.randf_range(-float(jv[1]), float(jv[1])))
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
	var pu = o.hw.get("pulse", {})
	if pu is Dictionary and not pu.is_empty() and int(pu.i) == i:
		return float(int(pu.n)) * float(pu.every)
	if o.hw.has("bolts"):
		return _F()._hw3_left(o, i)
	if o.hw.has("anchor"):
		return _F()._hw4_left(o, i)
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
		o.load_skill_attacks(i, int(dv.next_attacks))
	if sb.has("fx"):
		fx_play(o, sb.fx, o.pos, 30.0)
	o.effect_skill = i
	o._exec_list(sb.get("do", []))
	o.effect_skill = -1
	o.bind_skill_duration(i)
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
		"whirl", "chain", "rift", "ulp_wave":   # 乌尔比安段
			return _F().hw4_draw_pfx(o, f, a)
		"s1link":   # 逻各斯湮灭余伤传递：黑色咒文链从起点铺向目标
			var grow: float = minf(1.0, (1.0 - a) / 0.3)
			_F()._hw_draw_tiled(o, "fx_logos_s1_link", f.pos, f.pos.lerp(f.to, grow), o.g.PX * 0.8, 0.0)
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
	var out: Array = _F().hw3_status_items(o) if o.hw.has("bolts") else []
	if o.hw.has("anchor"):
		out += _F().hw4_status_items(o)
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
			for m in b.get("aoe_mults", _EA):
				if not (m is Dictionary) or not m.has("mult"):
					errs.append(p + ".aoe_mults 的每一条是 {cond, mult}")
			for f in b.get("follow", _EA):
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
