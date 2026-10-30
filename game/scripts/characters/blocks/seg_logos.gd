## 干员积木 · seg_logos（docs/101 §7.3 B6 ①，10-15：由 op_blocks.gd 按段拆出，内容与注释照搬；继承链与门面见 op_blocks.gd）
extends "res://scripts/characters/blocks/seg_eyjafjalla.gd"

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
	for m in a.get("atk_mults", _EA):
		if cond_true(o, m.get("cond", _ED)):
			v *= float(m.get("mult", 1.0))
	return v


## 攻击距离：attack.range × op_range × range_mults
static func hw_range(o) -> float:
	var a: Dictionary = o.B.get("attack", {})
	var v: float = float(a.get("range", 300.0)) * o.stat(&"op_range")
	for m in a.get("range_mults", _EA):
		if cond_true(o, m.get("cond", _ED)):
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

## 普攻起手（data_operator.update 的 bolt 分支，按住瞄准 B 类）
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
			for x in b.get("extra", _EA):
				if cond_true(o, x.get("cond", _ED)):
					ex.append(x)
			var fan: bool = not h.fan.is_empty() and float(h.fan.t) > 0.0 and b.get("fan_filter", false)
			var ts: Array = o.aim_targets(n + ex.size() + (6 if fan else 0), rng_r, o.pos)
			if fan:
				ts = ts.filter(func(e): return hw_in_fan(o, e.pos)).slice(0, n + ex.size())
			if ts.is_empty():
				return false
			var variant := -1
			if is_atk and b.has("flight_visual"):
				variant = int(h.get("bolt_variant", 0))
				h.bolt_variant = 1 - variant
			var a: float = hw_atk(o)
			for k in ts.size():
				var d: float = hw_mul(a, b.get("mult", 1.0))
				d = hw_mul(d, ex[k - n].get("mult", 1.0)) if k >= n else d * 1.0
				_hw_word(o, ts[k], d, src, b, variant)
		"random":
			if b.has("chance") and not roll(g, float(b.chance)):
				return false
			var pool: Array = o.nearest_enemies(int(b.get("pool", 8)), rng_r, o.pos)
			for q in int(b.get("count", 1)):
				if pool.is_empty():
					break
				var e2: Dictionary = pool.pop_at(g.rng_op.randi() % pool.size())
				_hw_word(o, e2, hw_mul(hw_atk(o), b.get("mult", 1.0)), src, b)
				if b.has("slow"):
					o.add_cc(e2, -INF, float(b.slow))
	return true


static func _hw_word(o, e: Dictionary, dmg: float, src: String, b: Dictionary, variant := -1) -> void:
	var h: Dictionary = o.hw
	h.word_q.append({"t": float(b.get("gap", 0.12)) * h.word_q.size(), "e": e, "dmg": dmg, "src": src, "b": b, "variant": variant})


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
						# ph 决定飞行摆动 → 命中时刻，是玩法量：不能取 g.vrng（画面随机流的消耗次数随画面特效变，同 seed 会分叉）；
						# 用发射计数的黄金角序列，确定且不耗任何随机流。rune 只决定画哪个符文，仍取 g.vrng
						h["bolt_n"] = int(h.get("bolt_n", 0)) + 1
						var bolt := {"pos": hand, "e": e, "dmg": q.dmg, "src": q.src, "b": q.b, "hist": [hand], "life": float(q.b.get("life", 1.3)), "age": 0.0,
							"ph": fposmod(float(h.bolt_n) * 2.399963, TAU), "rune": g.vrng.randi(), "to": e.pos + Vector2(0, -e.r * 0.5)}
						if int(q.get("variant", -1)) >= 0:
							bolt.visual = {"variant": q.variant, "start": hand, "span": maxf(1.0, hand.distance_to(bolt.to)), "u": 0.0, "hist": [hand]}
						h.bolts.append(bolt)
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
		if not e.dead and int(e.get("id", 0)) >= 0:
			bo.to = e.pos + Vector2(0, -e.r * 0.5)
		var d: Vector2 = bo.to - bo.pos
		var step: float = spd * dt
		if d.length() <= step + 4.0:
			bo.pos = bo.to
			bo.life = -1.0
			var tgt: Dictionary = e
			if e.dead or int(e.get("id", 0)) < 0:   # 目标已死 / 手动打空的伪目标（aim_point_target）：落点 60 内最近的
				var near2: Array = o.nearest_enemies(1, 60.0, bo.to)
				tgt = near2[0] if not near2.is_empty() else {}
			if not tgt.is_empty():
				hw_bolt_hit(o, tgt, bo.dmg, bo.src, bo.b)
			continue
		bo.pos += d.normalized().rotated(sin(bo.age * 7.0 + bo.ph) * 0.45) * step
		bo.hist.append(bo.pos)
		if bo.hist.size() > 6:
			bo.hist.pop_front()
		if bo.has("visual"):
			var v: Dictionary = bo.visual
			v.u = maxf(v.u, clampf(1.0 - bo.pos.distance_to(bo.to) / v.span, 0.0, 1.0))
			v.hist.append(hw_bolt_pose(bo)[0])
			if v.hist.size() > 6:
				v.hist.pop_front()
	h.bolts = h.bolts.filter(func(bo): return bo.life > 0.0)


## 弧线只用于显示；逻辑弹位与命中时刻继续走原追踪，画面进度不倒退。
static func hw_bolt_pose(bo: Dictionary) -> Array:
	if not bo.has("visual"):
		var hist: Array = bo.hist
		return [bo.pos, (bo.pos - hist[-2]).angle() if hist.size() >= 2 else 0.0]
	var v: Dictionary = bo.visual
	var cfg: Dictionary = bo.b.flight_visual
	var delta: Vector2 = bo.to - v.start
	var axis: Vector2 = delta.normalized()
	var normal := Vector2(axis.y, -axis.x)
	var lift := clampf(delta.length() * float(cfg.arc_lift[int(v.variant)]), -float(cfg.max_lift), float(cfg.max_lift))
	var u: float = v.u
	return [v.start.lerp(bo.to, u) + normal * (4.0 * lift * u * (1.0 - u)), (delta + normal * (4.0 * lift * (1.0 - 2.0 * u))).angle()]


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
	var lst: Array = o.B.get("attack", _ED).get("then", []) if str(b.get("then_of", "")) == "attack" else b.get("then", [])
	for blk in lst:
		if not cond_true(o, blk.get("cond", _ED)):
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
	for s in b.get("on_hit", _EA):
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
				for s in b.get("on_hit", _EA):
					apply_status(o, q, s)


## verb.execute：返回是否处决了
static func hw_execute(o, b: Dictionary) -> bool:
	var g = o.g
	var h: Dictionary = o.hw
	var e: Dictionary = h.get("hit_e", {})
	if e.is_empty() or e.dead or e.elite or e.boss:
		return false
	if not (e.hp < hw_atk(o) * float(b.get("thr", 1.5)) * kill_weight(g, e)):   # 密度缩放过的普通怪血量 × 1/k，阈值同比（docs/50 §16.8）
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
			var q2: Dictionary = pool[g.rng_op.randi() % pool.size()]
			o.log_hit(str(b.get("over_src", b.get("src", ""))), [])
			o.deal_damage(q2, over)
			for s in b.get("over_on_hit", _EA):
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
		o.add_cc(lk.e, -INF, float(b.get("slow", 0.6)) * ramp)
		var tip: Vector2 = _hw_bolt_tip(o, o.B.get("attack", {}))
		if g.tex.get("fx_logos_s1_chain") == null:
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
		var shots := 0
		if _s3_extra_on(g):   # 出手瞬间他身前一闪（施法符文）
			o.spawn_fx_sprite("fx_logos_glyph", o.pos + Vector2.from_angle(float(h.fan_ang)) * 24.0 + Vector2(0, -22), g.PX * 0.9, 0.0, false)
		for j in o.query_ids(o.pos, r + 30.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or not hw_in_fan(o, e.pos):
				continue
			o.log_hit(str(b.get("src", "")), b.get("tags", []))
			o.deal_damage(e, dmg)
			if not e.dead:
				for s in b.get("on_hit", _EA):
					apply_status(o, e, s)
			if shown < 3:
				shown += 1
				o.spawn_fx_sprite("fx_logos_glyph", e.pos + Vector2(0, -e.r * 0.5), g.PX * 0.7, 0.0, g.vrng.randf() < 0.5)
			if shots < S3_SHOT_MAX and _s3_extra_on(g):   # 出手轨迹（10-29）：S3 没有普攻动作帧，让每次出手看得见 他 → 目标
				shots += 1
				var sl: Array = h.get("s3_shots", [])
				sl.append({"to": e.pos + Vector2(0, -e.r * 0.5), "t0": g.t, "side": 1.0 if shots % 2 == 0 else -1.0})
				h["s3_shots"] = sl
	var f: float = float(b.get("bullet_slow", 0.2))
	var in_fan := func(p: Vector2) -> bool: return hw_in_fan(o, p)
	g.shots.slow_in(in_fan, f, "acuity")   # 敌弹池接口（docs/101 §7.3.10）
	if float(fn.t) <= 0.0:
		var gone: PackedVector2Array = g.shots.cancel_in(in_fan)
		var n: int = gone.size()
		for bp in gone:
			o.fx({"kind": "glow", "pos": bp, "r": 8.0, "life": 0.25, "col": HW_INK, "alpha": 0.6})
		if n > 0:
			o.float_text(o.pos + Vector2(0, -70), "消除弹幕 ×%d" % n, HW_INK, 15)


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
	_hw_draw_shots(o)
	if _hw_fan_sheets(o, b, fn, fa, r, fade):
		return   # 咒域素材到位（docs/192）：整片扇形由帧条画，程序填充 / 边线不再画
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


## 咒域整片扇形素材（docs/192）：fx_logos_s3_fan_ground（循环）/ _open（起手 0.5 秒）/ _close（收尾 0.5 秒），三条同画布（1x 180×264，原点 (4,132)，
## 画的是参考半径 170 美术像素 = 340 世界像素、100° 的扇形，朝右），按 r / 340 等比缩放、绕原点转到咒域朝向。ground 没图就整体回退程序画法（返回 false）；
## open / close 缺图时只用 ground。起手 / 收尾期间 ground 淡入 / 淡出，不与 open / close 叠成双层
const FAN_REF_R := 340.0
const FAN_OPEN_T := 0.5
const FAN_CLOSE_T := 0.375   # fan_close 6 帧 / 16 fps
## 旋钮 fx/logos_s3_extra（缺省 1；0 = 关掉出手轨迹 / 施法闪）。积木脚本不直接引用自动加载
static func _s3_extra_on(g) -> bool:
	var b = g.get_node_or_null("/root/Bal")
	return b == null or float(b.v("fx/logos_s3_extra", 1.0)) > 0.0

const S3_SHOT_MAX := 6     # 每 tick 最多画几道出手轨迹（同屏 ≤ 6 × 3 次绘制）
const S3_SHOT_DUR := 0.3
const SLOW_MARK_MAX := 40   # 被减速弹幕标记同屏上限（docs/192）

static func _hw_fan_sheets(o, b: Dictionary, fn: Dictionary, fa: float, r: float, fade: float) -> bool:
	var g = o.g
	if g.tex.get("fx_logos_s3_fan_ground") == null or not g.V6_FRAMES.has("fx_logos_s3_fan_ground"):
		return false
	var elapsed: float = float(b.get("dur", 12.0)) - float(fn.t)
	var left: float = float(fn.t)
	var tn := "fx_logos_s3_fan_ground"
	var frame := -1
	var a := 1.0
	if elapsed < FAN_OPEN_T and g.tex.get("fx_logos_s3_fan_open") != null:
		tn = "fx_logos_s3_fan_open"
		frame = mini(int(elapsed / FAN_OPEN_T * g.V6_FRAMES[tn][0]), g.V6_FRAMES[tn][0] - 1)
	elif left < FAN_CLOSE_T and g.tex.get("fx_logos_s3_fan_close") != null:
		tn = "fx_logos_s3_fan_close"
		frame = mini(int((1.0 - left / FAN_CLOSE_T) * g.V6_FRAMES[tn][0]), g.V6_FRAMES[tn][0] - 1)
	else:
		# ground 用本技能局部时钟、open 结束后从 f0 起（open f7 = ground f0 = close f0，无缝）
		frame = int((elapsed - FAN_OPEN_T) * float(g.V6_FRAMES[tn][1])) % int(g.V6_FRAMES[tn][0])
	_hw_draw_sheet(o, tn, frame, fa, r / FAN_REF_R, Color(1, 1, 1, a * 0.78))   # 减重：扇形底纹透明度 ×0.78
	_hw_draw_ribbons(o, fa, r / FAN_REF_R, fade, minf(elapsed / FAN_OPEN_T, 1.0))
	_hw_draw_slow_marks(o, b, fa)
	return true


## 扇形边缘 / 内部的竖条符文（fx_logos_s3_ribbon 24×56 @2x，原点 (12,56)）：39 条边缘（弧上 -44°..44° 步 4°；两侧边 ±50° 半径 64..288 步 32）+ 5 条内部淡影。
## 位置随咒域朝向转，条自身保持竖直；亮暗交替、高度错落、上下浮 4 px、帧相位错开（HANDOFF 10-29）
const RIB_SIZES := [Vector2(20, 40), Vector2(24, 56), Vector2(20, 40), Vector2(28, 64), Vector2(24, 48)]
const RIB_INNER := [Vector2(120, 20), Vector2(180, -45), Vector2(235, 55), Vector2(270, -80), Vector2(210, 120)]

static func _hw_draw_ribbons(o, fa: float, k: float, fade: float, grow: float) -> void:
	var g = o.g
	var tx: Texture2D = g.tex.get("fx_logos_s3_ribbon")
	if tx == null or not g.V6_FRAMES.has("fx_logos_s3_ribbon"):
		return
	o._cv_flush()
	var frames: int = g.V6_FRAMES["fx_logos_s3_ribbon"][0]
	var fps: float = g.V6_FRAMES["fx_logos_s3_ribbon"][1]
	var fw: float = tx.get_width() / frames
	var fh: float = tx.get_height()
	var hi: float = ArtS.hires_of(tx)
	var u: float = g.PX / hi * k   # @2x 像素 → 世界像素
	var al: float = fade * grow
	var n := 0
	var spots: Array = []   # [本地位置 @2x, 亮?, 序号]
	for d in range(-44, 45, 8):   # 10-29 减重：弧上条数 23 → 12
		spots.append([Vector2.from_angle(deg_to_rad(d)) * FAN_REF_R, n % 2 == 0, n])
		n += 1
	for sgn in [-1.0, 1.0]:
		for rr in range(64, 289, 64):   # 两侧边 8 → 4 条
			spots.append([Vector2.from_angle(deg_to_rad(50.0 * sgn)) * float(rr), n % 2 == 0, n])
			n += 1
	var base: Vector2 = o.pos + g.draw_off
	var rot := Transform2D(fa, Vector2.ZERO)
	for sp in spots:
		var i: int = sp[2]
		var sz: Vector2 = RIB_SIZES[i % RIB_SIZES.size()]
		var bob: float = sin(g.t * 1.6 + float(i) * 1.3) * 4.0
		var a: float = ((0.71 + 0.18 * (0.5 + 0.5 * sin(g.t * 2.0 + i))) if sp[1] else (0.27 + 0.18 * (0.5 + 0.5 * sin(g.t * 1.7 + i * 0.7)))) * 0.62   # 减重：整体透明度 ×0.62
		_hw_ribbon_at(o, tx, base + rot * (sp[0] * u), sz, u, bob, int(g.t * fps + i) % frames, fw, fh, a * al)
	for j in RIB_INNER.size():
		var sz2: Vector2 = RIB_SIZES[j % RIB_SIZES.size()]
		var a2: float = (0.085 + 0.07 * (0.5 + 0.5 * sin(g.t * 1.3 + j * 1.9))) * 0.6
		_hw_ribbon_at(o, tx, base + rot * (RIB_INNER[j] * u), sz2, u, sin(g.t * 1.2 + j) * 4.0, int(g.t * fps + j * 3) % frames, fw, fh, a2 * al)

static func _hw_ribbon_at(o, tx: Texture2D, p: Vector2, sz: Vector2, u: float, bob: float, fr: int, fw: float, fh: float, a: float) -> void:
	var w: float = sz.x * u
	var h: float = sz.y * u
	o.cv.draw_texture_rect_region(tx, Rect2(p + Vector2(-w * 0.5, -h + bob * u), Vector2(w, h)), Rect2(fw * fr, 0, fw, fh), Color(1, 1, 1, a))


## 出手轨迹（10-29）：竖条符文（fx_logos_s3_ribbon）从他身前飞向目标，弧线 + 两道拖影，到达时一小团墨光（不新增贴图）
static func _hw_draw_shots(o) -> void:
	var h: Dictionary = o.hw
	var sl: Array = h.get("s3_shots", [])
	if sl.is_empty():
		return
	var g = o.g
	var tx: Texture2D = g.tex.get("fx_logos_s3_ribbon")
	var keep: Array = []
	var from: Vector2 = o.pos + Vector2.from_angle(float(h.fan_ang)) * 20.0 + Vector2(0, -20)
	if tx != null and g.V6_FRAMES.has("fx_logos_s3_ribbon"):
		o._cv_flush()
	var frames: int = g.V6_FRAMES["fx_logos_s3_ribbon"][0] if tx != null and g.V6_FRAMES.has("fx_logos_s3_ribbon") else 1
	for sh in sl:
		var k: float = (g.t - float(sh.t0)) / S3_SHOT_DUR
		if k >= 1.0:
			if not sh.get("hit", false):
				o.fx({"kind": "glow", "pos": sh.to, "r": 12.0, "life": 0.2, "col": HW_INK, "alpha": 0.5})   # 命中点墨光（小，淡出）
			continue
		keep.append(sh)
		if tx == null or frames <= 1 and not g.V6_FRAMES.has("fx_logos_s3_ribbon"):
			continue
		var fw: float = tx.get_width() / frames
		var fh: float = tx.get_height()
		var hi: float = ArtS.hires_of(tx)
		for tr in 3:
			var kk: float = clampf(k - 0.07 * tr, 0.0, 1.0)
			var ez: float = 1.0 - pow(1.0 - kk, 2.0)
			var pt: Vector2 = from.lerp(sh.to, ez)
			var dirv: Vector2 = (sh.to - from).normalized()
			pt += dirv.orthogonal() * sin(kk * PI) * 16.0 * float(sh.side) + g.draw_off
			var a: float = (1.0 - 0.38 * tr) * minf(k * 6.0, 1.0) * (1.0 - k * 0.3)
			var sc: float = g.PX / hi * 0.95
			o.cv.draw_set_transform(pt, dirv.angle() + PI * 0.5, Vector2(sc, sc))
			o.cv.draw_texture_rect_region(tx, Rect2(Vector2(-fw * 0.5, -fh * 0.5), Vector2(fw, fh)), Rect2(fw * (int(g.t * 12.0) % frames), 0, fw, fh), Color(1, 1, 1, a))
		o.cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	h["s3_shots"] = keep


## 被「延异视阈」减速的敌弹打标记（fx_logos_s3_slow 48×48 @2x，中心镂空，只标实际被减速、仍在扇形内的弹，最多 40 个）
static func _hw_draw_slow_marks(o, b: Dictionary, fa: float) -> void:
	var g = o.g
	var tx: Texture2D = g.tex.get("fx_logos_s3_slow")
	if tx == null or not g.V6_FRAMES.has("fx_logos_s3_slow"):
		return
	var frames: int = g.V6_FRAMES["fx_logos_s3_slow"][0]
	var fw: float = tx.get_width() / frames
	var fh: float = tx.get_height()
	var hi: float = ArtS.hires_of(tx)
	var s: float = g.PX / hi
	var fr: int = int(g.t * float(g.V6_FRAMES["fx_logos_s3_slow"][1])) % frames
	o._cv_flush()
	var n := 0
	for bl in g.ebullets:
		if bl.life <= 0.0 or not bl.get("acuity", false) or not hw_in_fan(o, bl.pos):
			continue
		var c: Vector2 = bl.pos + g.draw_off
		o.cv.draw_texture_rect_region(tx, Rect2(c - Vector2(fw, fh) * 0.5 * s, Vector2(fw, fh) * s), Rect2(fw * fr, 0, fw, fh))
		n += 1
		if n >= SLOW_MARK_MAX:
			break


## 整帧画帧条里的一帧：原点（1x (4, 高/2)）放在咒域中心，转到 ang，缩放 k × PX / 2（@2x 与 1x 显示同大）；frame < 0 = 按 fps 循环
static func _hw_draw_sheet(o, tn: String, frame: int, ang: float, k: float, col: Color) -> void:
	var g = o.g
	var tx: Texture2D = g.tex.get(tn)
	if tx == null or not g.V6_FRAMES.has(tn):
		return
	o._cv_flush()
	var frames: int = g.V6_FRAMES[tn][0]
	var fr: int = int(g.t * float(g.V6_FRAMES[tn][1])) % frames if frame < 0 else frame
	var fw: float = tx.get_width() / frames
	var fh: float = tx.get_height()
	var hi: float = ArtS.hires_of(tx)
	var sc: float = g.PX / hi * k
	o.cv.draw_set_transform(o.pos + g.draw_off, ang, Vector2(sc, sc))
	o.cv.draw_texture_rect_region(tx, Rect2(Vector2(-4.0 * hi, -fh / 2.0), Vector2(fw, fh)), Rect2(fw * fr, 0, fw, fh), col)
	o.cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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
		var visual: Dictionary = bo.get("visual", {})
		var hh: Array = visual.get("hist", bo.hist)
		var pose := hw_bolt_pose(bo)
		var draw_pos: Vector2 = pose[0]
		var name: String = str(bo.b.flight_visual.variants[int(visual.variant)]) if not visual.is_empty() else ""
		var trail_alpha: float = float(bo.b.flight_visual.get("trail_alpha", 0.28)) if not visual.is_empty() else 0.28
		var trail_width: float = float(bo.b.flight_visual.get("trail_width", 3.5)) if not visual.is_empty() else 3.5
		for i in range(1, hh.size()):
			var k: float = float(i) / float(hh.size())
			cv.draw_line(hh[i - 1], hh[i], Color(HW_INK.r, HW_INK.g, HW_INK.b, 0.08 + (trail_alpha - 0.08) * k), 1.0 + (trail_width - 1.0) * k)
		var rtx: Texture2D = ArtS.tex("fx_logos_glyphs")
		if name != "" and g.tex.get(name) != null:
			o.draw_spr_rot(name, int(bo.age * float(bo.b.flight_visual.fps)) % 4, draw_pos, pose[1], g.PX)
		elif rtx != null:
			var fh: int = rtx.get_height()
			var rn: int = maxi(1, rtx.get_width() / maxi(1, fh))
			var sc: float = g.PX * 13.0 / float(fh)
			cv.draw_set_transform(draw_pos + g.draw_off, sin(bo.age * 5.0 + bo.ph) * 0.35, Vector2(sc, sc))
			cv.draw_texture_rect_region(rtx, Rect2(-Vector2(fh, fh) / 2.0, Vector2(fh, fh)), Rect2(fh * (int(bo.rune) % rn), 0, fh, fh), Color(1, 1, 1, clampf(bo.life / 0.25, 0.0, 1.0)))
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		elif g.tex.get("fx_logos_glyph") != null:
			o.draw_spr_rot("fx_logos_glyph", 5, draw_pos, sin(bo.age * 5.0 + bo.ph) * 0.35, g.PX * 13.0 / 24.0, Color(1, 1, 1, clampf(bo.life / 0.25, 0.0, 1.0)))
		elif g.tex.get("proj_logos_ink") != null and hh.size() >= 2:
			o.draw_spr_rot("proj_logos_ink", int(g.t * 12.0) % 4, draw_pos, pose[1], g.PX)
		else:
			cv.draw_circle(draw_pos, 10.0, Color(HW_INK.r, HW_INK.g, HW_INK.b, 0.35))
			cv.draw_circle(draw_pos, 5.5, Color(HW_INK.r * 1.4, HW_INK.g * 1.4, HW_INK.b * 1.6))
			cv.draw_circle(draw_pos, 2.5, Color(1.8, 1.9, 2.2))
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
		if g.tex.get("fx_logos_s1_chain") != null:
			var train := hw_s1_train_pose(lk, tip, to)
			if not train.is_empty():
				_hw_draw_tiled(o, "fx_logos_s1_chain", train[0], train[1], g.PX, train[3], 0, Color.WHITE, -1, true, train[2])
		elif g.tex.get("fx_logos_script") != null:
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


## 首轮抵达后符文首尾衔接；滚动只影响画面，伤害仍由 lock 的 tick 独立结算。
static func hw_s1_train_pose(lk: Dictionary, a: Vector2, b: Vector2) -> Array:
	if lk.is_empty() or float(lk.get("t", 0.0)) <= 0.0:
		return []
	var period: float = maxf(0.001, float(lk.b.get("tick", 0.25)))
	var elapsed: float = float(lk.get("n", 0)) * period + float(lk.get("tick", 0.0))
	var length: float = a.distance_to(b)
	if elapsed <= 0.0 or length < 2.0:
		return []
	var head_t: float = minf(1.0, elapsed / period)
	var bend: float = minf(12.0, length * 0.05)
	var normal := Vector2(-(b - a).y, (b - a).x) / length
	var head := a.lerp(b, head_t) - normal * 4.0 * bend * head_t * (1.0 - head_t)
	return [a, head, bend * head_t * head_t, -elapsed * 60.0 / period]


static func hw_native_body_state(o, st: Dictionary) -> Dictionary:
	if st.is_empty():
		return st
	var kind: String = str(st.kind)
	if kind == "idle" and o.perm[1]:
		kind = "idle_s2"
	elif kind == "attack":
		# 起手固定身体变体，命中或丢失目标都不在收势中换姿势。
		var variant: int = int(o.hw.get("body_variant", o.hw.get("bolt_variant", 0)))
		kind = "attack_s2" if o.perm[1] else ("attack_b" if variant == 1 else "attack")
	var tx: Texture2D = o.anim_tex(kind)
	if kind == st.kind or tx == null:
		return st
	var n: int = o.anim_hframes(tx, kind)
	st.tex = tx
	st.hf = n
	st.frame = o.timed_frame(kind, range(n), o.anim_t, true) if kind == "idle_s2" else mini(int(st.frame), n - 1)
	st.kind = kind
	st.flip = (o.face < 0.0) != o.sprite_mirror(kind)
	return st


static func _hw_tile_curve(x: float, length: float, bend: float, offset: float, variation: float) -> Vector2:
	var t: float = x / length
	var curve := Vector2(-4.0 * bend * t * (1.0 - t), -4.0 * bend * (1.0 - 2.0 * t) / length)
	if variation > 0.0:
		# 局部曲线随符文前进，两端衰减为零以固定手部和命中点。
		var phase: float = (x + offset) * TAU / 64.0
		var wave: float = 0.75 * sin(phase) + 0.25 * sin(phase * 0.73 + 1.2)
		var slope: float = (0.75 * cos(phase) + 0.1825 * cos(phase * 0.73 + 1.2)) * TAU / 64.0
		var envelope: float = 4.0 * t * (1.0 - t)
		curve.x += variation * envelope * wave
		curve.y += variation * (4.0 * (1.0 - 2.0 * t) * wave / length + envelope * slope)
	return curve


## 沿 a→b 平铺一张横向帧条（每段一帧宽），offset 为沿方向的滚动位移；最后一段按端点裁剪
static func _hw_draw_tiled(o, tn: String, a: Vector2, b: Vector2, sc: float, offset: float, frame_off: int = 0, col := Color.WHITE, fixed := -1, fade_to_target := false, bend := 0.0) -> void:
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
	var variation: float = 1.5 if tn == "fx_logos_s1_chain" and bend != 0.0 else 0.0
	cv.draw_set_transform(a + g.draw_off, (b - a).angle(), Vector2(k, k))
	var x: float = -fposmod(offset, seg)
	while x < L:
		var x0: float = maxf(x, 0.0)
		var x1: float = minf(x + seg, L)
		if x1 > x0:
			var u0: float = (x0 - x) / k
			var u1: float = (x1 - x) / k
			if fade_to_target or bend != 0.0:
				# 小段沿同一浅弧线排布，明暗按整条法术进度计算。
				var parts: int = maxi(1, ceili((x1 - x0) / (4.0 if variation > 0.0 else 8.0)))
				for j in parts:
					var lo: float = lerpf(x0, x1, float(j) / parts)
					var hi: float = lerpf(x0, x1, float(j + 1) / parts)
					var t0: float = lo / L
					var t1: float = hi / L
					var c0 := _hw_tile_curve(lo, L, bend, offset, variation)
					var c1 := _hw_tile_curve(hi, L, bend, offset, variation)
					var p0 := Vector2(lo, c0.x) / k
					var p1 := Vector2(hi, c1.x) / k
					var n0 := Vector2(-c0.y, 1).normalized() * fh / 2.0
					var n1 := Vector2(-c1.y, 1).normalized() * fh / 2.0
					var tint: Color = col
					if fade_to_target:
						tint *= Color(0.55, 0.55, 0.55, 0.55).lerp(Color(1.15, 1.15, 1.15, 1.0), smoothstep(0.0, 1.0, (t0 + t1) * 0.5))
					var uv0: float = (fw * fr + (lo - x) / k) / tx.get_width()
					var uv1: float = (fw * fr + (hi - x) / k) / tx.get_width()
					cv.draw_colored_polygon(PackedVector2Array([p0 - n0, p1 - n1, p1 + n1, p0 + n0]), tint,
						PackedVector2Array([Vector2(uv0, 0), Vector2(uv1, 0), Vector2(uv1, 1), Vector2(uv0, 1)]), tx)
			else:
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
	var hs: Dictionary = o.def.get("hit_sources", _ED).get(src, {})
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
