## 干员积木 · seg_ulpianus（docs/101 §7.3 B6 ①，10-15：由 op_blocks.gd 按段拆出，内容与注释照搬；继承链与门面见 op_blocks.gd）
extends "res://scripts/characters/blocks/seg_logos.gd"

const UlpImpact = preload("res://scripts/characters/ulpianus_impact.gd")
const UlpCharge = preload("res://scripts/characters/ulpianus_charge_fx.gd")

const HW_STEEL := Color(0.55, 0.75, 0.95)

const HW_CHAIN := Color(0.62, 0.68, 0.78)

const HW_ABYSS := Color(0.1, 0.12, 0.2)

const HW_EDGE := Color(0.4, 0.62, 1.1)

const HW_WATER := Color(0.45, 0.78, 1.0)

const HW_BLOOD := Color(1.0, 0.25, 0.3)


static func _hw4(o) -> Dictionary:
	var h := hw_st(o)
	if not h.has("anchor"):
		h.merge({"anchor": {}, "hooked": [], "launched": [], "stacks": {}, "armed": {}, "timers": {}, "sil": {}, "blk": {}, "mute": {}, "leash": []})
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
	for m in b.get("cap_more", _EA):
		if cond_true(o, m.get("cond", _ED)):
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
	for am in o.B.get("attack", _ED).get("armed", _EA):   # 蓄势写在 blocks.attack 上；半径按当前普攻（含 swap_attack）
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
	if o.def.has("native_motion"):
		var socket: Vector2 = o.sprite_point("hand")
		if socket != Vector2.INF:
			return socket
	var b: Dictionary = o.hw.get("anchor", {}).get("b", {})   # 没掷过锚（歌蕾蒂娅只有钩索）时 hw 里没有 anchor
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


## 每帧（hw_tick）：飞 → 咬地 → 收链 / 停顿 / 重砸，或原地落锚砸下
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
			if an.b.has("path_w"):
				UlpCharge.windup(o, _hw_anchor_pos(an, k) + Vector2(0, -6), k)   # S3 起冲：颗粒向锚尖收拢（docs/143）
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
				o.add_cc(e, 0.2)
			an.trail.push_front(an.head)
			if an.trail.size() > 5:
				an.trail.pop_back()
			if k >= 1.0:
				_hw_reel_arrive(o)
		"hold":
			if k >= 1.0:
				_hw_reel_slam(o)
				h.anchor = {}
		"zip":
			# 冲锋（10-24）：本干员沿锁链冲向落点，整条路径对沿途敌人各结算一次（path_w 宽、path_mult 倍率），到点再落地砸
			var from_p: Vector2 = o.pos
			o.pos = (an.start as Vector2).lerp(an.land, k * k)
			o.face = signf(an.land.x - an.start.x) if absf(an.land.x - an.start.x) > 1.0 else o.face
			_hw_charge_sweep(o, an, from_p, o.pos)
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
	o.fx({"kind": "ulp_wave", "pos": to, "r": 48.0 if big else 36.0, "life": 0.36, "floor": true})
	UlpImpact.splash(o, to, 0.8)
	for i in 6:
		var a: float = dir.angle() + g.vrng.randf_range(-0.9, 0.9)
		o.fx({"kind": "spark", "pos": to + Vector2(0, -6), "vel": Vector2.from_angle(a) * g.vrng.randf_range(160, 300), "life": 0.22, "col": HW_CHAIN, "sz": 2.5})
	if str(b.get("mode", "zip")) == "reel" and _hw_start_reel(o, to, dir):
		var rf = b.get("rift", null)
		if rf is Dictionary and hw_face_ok(o, rf.get("cond", true)):
			_hw_open_rift(o, rf, o.pos, to)
		return
	an.start = o.pos
	if b.has("path_w"):
		# mode zip 且写了 path_w：冲锋（10-24 用户：S3 跳跃改冲锋，沿途伤害 + 落地 AOE）
		var land: Vector2 = to - dir * 18.0
		an.phase = "zip"
		an.t = 0.0
		an.dur = clampf(o.pos.distance_to(land) / 1100.0, 0.14, 0.34)
		an.land = land
		an.hit = {}
		an.trail = []
		o.melee_tgt = null
		_hw_sfx_op(o, "atk", 2.0, 0.85)
		if UlpCharge.on(o):
			UlpCharge.launch(o, o.pos, to, dir)
			# 起冲照明：模板有颗粒簇灯就在起点挂一盏，否则扬一团拖拽尘（光学观感把帧条登记成动态灯）；颗粒版沿途不再扬尘（每团一盏灯，一次冲锋 6–9 团会占满 12 灯预算）
			if not UlpCharge.lamp(o, o.pos + Vector2(0, -8), 80.0, 0.16):
				o.spawn_fx_sprite("fx_ulpianus_drag_dust", o.pos + Vector2(0, 4), g.PX, dir.angle(), false, true)
		return
	# 钩不到 / 钩到 Boss / 没写 path_w：锚在落点原地砸下（10-22 用户：S1 去掉顺锁链弹射）
	an.land = to
	_hw_zip_land(o)
	h.anchor = {}


## 冲锋沿途结算：本帧位移线段 a→c 两侧 path_w / 2（+ 敌人半径）内、这次冲锋还没吃过的敌人各吃一次 path_mult 倍率；
## 画面：脚下留一段锚链拖痕（floor 线）+ 间隔扬起拖拽尘（帧条特效，光学观感自动给粒子与动态光）
static func _hw_charge_sweep(o, an: Dictionary, a: Vector2, c: Vector2) -> void:
	var g = o.g
	var b: Dictionary = an.b
	var w: float = float(b.get("path_w", 50.0))
	var seg: Vector2 = c - a
	var L: float = seg.length()
	if L < 0.01:
		return
	var mid: Vector2 = (a + c) * 0.5
	var dmg: float = o.base(str(b.get("atk_key", "atk")), 0.0) * float(b.get("path_mult", 1.2)) * o._dmg_bonus() * o.skill_power()
	var src: String = str(b.get("src", ""))
	var grains: bool = UlpCharge.on(o)
	for j in o.query_ids(mid, L * 0.5 + w * 0.5 + 40.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or an.hit.has(e.id):
			continue
		var q: Vector2 = a + seg * clampf((e.pos - a).dot(seg) / (L * L), 0.0, 1.0)
		if e.pos.distance_to(q) > w * 0.5 + float(e.r):
			continue
		an.hit[e.id] = true
		o.log_hit(src)
		o.deal_damage(e, dmg)
		if grains:
			UlpCharge.hit(o, e, 2)   # 命中三档·中档（颗粒火星落到脚底冷却 + 命中星）
		else:
			o.fx({"kind": "spark", "pos": e.pos + Vector2(0, -float(e.r) * 0.5), "vel": seg.normalized().orthogonal() * g.vrng.randf_range(-120.0, 120.0), "life": 0.2, "col": HW_CHAIN, "sz": 2.5})
	if grains:
		UlpCharge.path(o, an, a, c)   # 颗粒版：脚下拖出深海水体颗粒，逐颗熄灭，不画 0.35 秒锚链拖痕
		return
	o.fx({"kind": "line", "pos": a, "to": c, "w": 5.0, "life": 0.35, "col": Color(HW_CHAIN.r, HW_CHAIN.g, HW_CHAIN.b, 0.6), "floor": true})
	an.dust = float(an.get("dust", 0.0)) + L
	if an.dust >= 36.0:
		an.dust = 0.0
		o.spawn_fx_sprite("fx_ulpianus_drag_dust", c + Vector2(0, 4), g.PX, seg.angle(), false, true)


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
		o.add_cc(e, float(b.get("stun", 0.6)) * (0.5 if e.elite else 1.0) + 0.25)
		if b.get("pull_cc", false):
			_hw_pull_cc(o, e)
		o.fx({"kind": "glow", "pos": e.pos + Vector2(0, -e.r * 0.6), "r": 10.0, "life": 0.25, "col": Color(1.3, 1.5, 2.0), "alpha": 0.6})
		var lh = b.get("leash", null)
		if lh is Dictionary and hw_face_ok(o, lh.get("cond", true)):
			_hw_leash_add(o, lh, e)
	o.impact_pause(0.05)
	o.fx({"kind": "ulp_wave", "pos": c, "r": 34.0, "life": 0.2, "pull": true, "floor": true})
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
			o.add_cc(e, float(b.get("stun", 0.6)) * (0.5 if e.elite or e.boss else 1.0))
			if not e.boss:
				o.apply_kb(e, (e.pos - o.pos).normalized() * float(b.get("slam_kb", 70.0)))
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
	var charge: bool = b.has("path_w") and UlpCharge.on(o)
	var heavy := 0
	for j in o.query_ids(c, r + 30.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or e.pos.distance_to(c) > r + e.r:
			continue
		o.log_hit(src)
		o.deal_damage(e, dmg)
		if charge and heavy < 6:
			heavy += 1
			UlpCharge.hit(o, e, 3)   # 冲锋落地：命中三档·重档（前 6 名，防满屏火星）
		if not e.dead:
			o.add_cc(e, float(b.get("stun", 0.6)) * (sb if e.boss else (se if e.elite else 1.0)))
			if kb_boss or not e.boss:
				o.apply_kb(e, (e.pos - c).normalized() * float(b.get("land_kb", 50.0)))
	var big: bool = b.get("big", false)
	_hw_slam_fx(o, c, r, 1.6 if big else 1.0)
	if charge:
		UlpCharge.land(o, c, r)   # 冲锋终点：冲击颗粒环 + 落地冷却的水花与碎屑（docs/143）
	if b.has("path_w"):
		UlpCharge.burst(o, c, r)   # 冲锋终点：大范围冲击环推到判定半径 r（低画质也画环，颗粒在 on 时）（docs/143 §8）
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


## 拖回不送死（用户 10-28「把自爆怪或者精英怪拉到面前的时候很容易死」，定「先眩晕、后沉默」）：锚链拖回的非 Boss 敌人
## 先打断（起手中的预警作废、自爆引信清零），再眩晕 hook_stun 秒、眩晕结束后沉默 hook_silence 秒（精英各用 *_elite）；
## 沉默 = 不起特殊招式、不远程开火，仍可移动和接触（run/enemies.gd silence）。积木键 pull_cc: true 开启，数值读本干员 base
static func _hw_pull_cc(o, e: Dictionary) -> void:
	if e.dead or e.boss:
		return
	var g = o.g
	g.enemies_sys.interrupt(e)
	var st: float = o.base("hook_stun_elite" if e.elite else "hook_stun", 1.0)
	o.add_cc(e, st)
	var sl: float = o.base("hook_silence_elite" if e.elite else "hook_silence", 1.0)
	g.enemies_sys.silence(e, g.t + maxf(float(e.stun), 0.0) + sl)
	_hw4(o).mute[int(e.id)] = e


## 沉默标记：眩晕结束后、沉默期间头顶画禁言符（只画本干员施加的）
static func hw_draw_mute(o) -> void:
	_hw_draw_leashes(o)
	var g = o.g
	var mu: Dictionary = _hw4(o).mute
	for id in mu.keys():
		var e: Dictionary = mu[id]
		var left: float = float(e.get("silence_t", 0.0)) - g.t
		if e.dead or left <= 0.0:
			mu.erase(id)
			continue
		if float(e.stun) > 0.0:
			continue
		# 图标：灰蓝圆环 + 一道横杠（禁言符），头顶上方 14px；干员画布不能写字，状态名写在技能说明与图鉴
		var al: float = clampf(left / 0.25, 0.0, 1.0)
		var cp: Vector2 = e.pos + Vector2(0, -float(e.r) * 2.0 - 14.0)
		var sc := Color(0.78, 0.82, 0.92, 0.95 * al)
		var dk := Color(0.04, 0.05, 0.08, 0.6 * al)
		o.cv.draw_arc(cp, 6.0, 0.0, TAU, 16, dk, 4.0)
		o.cv.draw_line(cp + Vector2(-4, 0), cp + Vector2(4, 0), dk, 4.0)
		o.cv.draw_arc(cp, 6.0, 0.0, TAU, 16, sc, 2.0)
		o.cv.draw_line(cp + Vector2(-4, 0), cp + Vector2(4, 0), sc, 2.0)


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
		o.apply_kb(e, (c - e.pos).normalized() * v)
		o.add_cc(e, 0.3)
		if dg.get("pull_cc", false):
			_hw_pull_cc(o, e)


static func _hw_open_rift(o, rf: Dictionary, a: Vector2, b: Vector2) -> void:
	var g = o.g
	if a.distance_to(b) < 8.0:
		return
	var dmg: float = o.base(str(rf.get("atk_key", "atk")), 0.0) * o._dmg_bonus() * float(rf.get("mult", 0.8)) * o.skill_power()
	var w: float = float(rf.get("w", 52.0))   # 全宽（B6 ⑤ 改对：原来当半宽用、数据写 26，现数据 rift_w 52，判定逐位不变）
	var d: Vector2 = (b - a).normalized()
	var L: float = a.distance_to(b)
	var src: String = str(rf.get("src", ""))
	var after: Dictionary = {}   # 通路洞开·余震（docs/202）：这条通路掀飞的敌人落地时各炸一圈小冲击；同一条通路共用一个计数 / 上一处落点
	var af = rf.get("after", null)
	if af is Dictionary and hw_face_ok(o, af.get("cond", true)):
		after = {"b": af, "n": 0, "last": Vector2.INF}
	for j in o.query_ids((a + b) * 0.5, L * 0.5 + w * 0.5 + 30.0):
		var e: Dictionary = g.enemies[j]
		if e.dead:
			continue
		if not seg_rect(a, d, L, w * 0.5, e.pos, e.r):   # B6 ⑤：ob_geom
			continue
		o.log_hit(src)
		o.deal_damage(e, dmg)
		_hw_launch(o, e, float(rf.get("air", 0.8)), float(rf.get("h", 30.0)), after)
	o.fx({"kind": "rift", "pos": a, "to": b, "life": 0.8, "floor": true, "seed": g.vrng.randf() * 100.0})
	for k in 5:
		var p: Vector2 = a.lerp(b, (k + 0.5) / 5.0)
		_hw_sparks(o, p + Vector2(0, -4), HW_EDGE, 3, 160.0, 0.35, 2.5, 260.0)


## 掀飞：眩晕 + sin 弧线高度（game 按 e.air 抬高绘制）；精英时长减半，Boss 不受；重复施加从头再来、时长取长
static func _hw_launch(o, e: Dictionary, dur: float, hh: float, after := {}) -> void:
	if e.dead or e.boss:
		return
	if e.elite:
		dur *= 0.5
	o.add_cc(e, dur, -INF, "airborne")
	for l in o.hw.launched:
		if is_same(l.e, e):
			l.t = 0.0
			l.dur = maxf(l.dur, dur)
			if not after.is_empty():
				l.after = after
			return
	o.hw.launched.append({"e": e, "t": 0.0, "dur": dur, "h": hh, "after": after})


static func _hw4_launched(o, dt: float) -> void:
	var h: Dictionary = o.hw
	for l in h.launched:
		l.t += dt
		var e: Dictionary = l.e
		var k: float = clampf(l.t / l.dur, 0.0, 1.0)
		o.set_air(e, 0.0 if e.dead or k >= 1.0 else sin(k * PI) * l.h, not e.dead)   # 掀飞期间不吃击退
		if k >= 1.0 and not e.dead and not l.after.is_empty():
			_hw_aftershock(o, l.after, e)
			l.after = {}
	h.launched = h.launched.filter(func(l): return l.t < l.dur and not l.e.dead)


## 通路洞开·余震（docs/202）：被通路掀飞的敌人落地时炸出一圈小冲击（半径 r、锚击 × mult）；同一条通路至多 max 处，落点之间连一道细锁链光（落点连成一串）
static func _hw_aftershock(o, ctx: Dictionary, e: Dictionary) -> void:
	var b: Dictionary = ctx.b
	if int(ctx.n) >= int(b.get("max", 12)):
		return
	ctx.n = int(ctx.n) + 1
	var g = o.g
	var p: Vector2 = e.pos
	var r: float = float(b.get("r", 50.0)) * o.stat(&"op_range")
	var dmg: float = o.base("atk", 0.0) * o._dmg_bonus() * float(b.get("mult", 0.3))
	var src: String = str(b.get("src", ""))
	for j in o.query_ids(p, r + 30.0):
		var q: Dictionary = g.enemies[j]
		if q.dead or q.pos.distance_to(p) > r + q.r:
			continue
		o.log_hit(src)
		o.deal_damage(q, dmg * (o.vs_elite() if q.elite or q.boss else 1.0))
	o.fx({"kind": "ulp_wave", "pos": p, "r": r, "life": 0.3, "floor": true})
	_hw_sparks(o, p + Vector2(0, -4), HW_EDGE, 4, 150.0, 0.3, 2.5, 240.0)
	if ctx.last != Vector2.INF:
		o.fx({"kind": "line", "pos": ctx.last + Vector2(0, -6), "to": p + Vector2(0, -6), "life": 0.3, "col": Color(0.7, 0.9, 1.5), "w": 2.0})
	ctx.last = p


## 不容挣脱（docs/202）：S1 钩回的敌人被锁链拴在乌尔比安身边 dur 秒，离他不能超过 r（精英时长减半，Boss 除外）；
## 同一敌人 growth/cc_dr_window 秒内再被拴，时长按成长节点的递减口径 × cc_dr_mult（拴住是位置约束，不是眩晕，口径同 add_cc_growth）
static func _hw_leash_add(o, lh: Dictionary, e: Dictionary) -> void:
	if e.dead or e.boss:
		return
	var g = o.g
	var h: Dictionary = o.hw
	var dur: float = float(lh.get("dur", 3.0)) * (0.5 if e.elite else 1.0)
	if g.t - float(e.get("gcc_leash_t", -99.0)) < MfBal.v("growth/cc_dr_window", 3.0):
		dur *= MfBal.v("growth/cc_dr_mult", 0.5)
	e["gcc_leash_t"] = g.t
	for l in h.leash:
		if is_same(l.e, e):
			l.t = dur
			l.dur = dur
			return
	if h.leash.size() >= int(lh.get("max", 8)):
		h.leash.pop_front()
	h.leash.append({"e": e, "t": dur, "dur": dur, "r": float(lh.get("r", 140.0))})


static func _hw4_leash_tick(o, dt: float) -> void:
	var h: Dictionary = o.hw
	for l in h.leash:
		l.t = float(l.t) - dt
		var e: Dictionary = l.e
		if e.dead or float(l.t) <= 0.0:
			continue
		var d: Vector2 = e.pos - o.pos
		var R: float = float(l.r) * o.stat(&"op_range")
		if d.length() > R:
			e.pos = o.pos + d.normalized() * R
			if e.kb.dot(d) > 0.0:
				e.kb = Vector2.ZERO
	h.leash = h.leash.filter(func(l): return float(l.t) > 0.0 and not l.e.dead)


## 拴住的画面：锁链从乌尔比安的手连到敌人身上，绷直（到了 r）时亮一点；到期前 0.4 秒淡出
static func _hw_draw_leashes(o) -> void:
	var h: Dictionary = o.hw
	if h.leash.is_empty() or o.pos == Vector2.INF:
		return
	var hand: Vector2 = _hw_hand(o)
	for l in h.leash:
		var e: Dictionary = l.e
		if e.dead:
			continue
		var al: float = clampf(float(l.t) / 0.4, 0.0, 1.0)
		var taut: bool = e.pos.distance_to(o.pos) >= float(l.r) * o.stat(&"op_range") - 3.0
		_hw_draw_chain(o, hand, e.pos + Vector2(0, -float(e.r) * 0.5), al if taut else al * 0.7, not taut)
		o.cv.draw_arc(e.pos + Vector2(0, 3), float(e.r) + 3.0, 0.0, TAU, 14, Color(HW_EDGE.r, HW_EDGE.g, HW_EDGE.b, 0.7 * al), 1.5)


## 每帧（hw_tick 开头转来）：计时 → 锚 → 掀飞（手写 update 的先后）
static func _hw4_tick(o, dt: float) -> void:
	var h: Dictionary = o.hw
	for k in h.timers:
		h.timers[k] = maxf(0.0, float(h.timers[k]) - dt)
	if not h.anchor.is_empty():
		_hw4_anchor(o, dt)
	if h.has("burst"):
		UlpCharge.burst_tick(o, dt)
	if not h.launched.is_empty():
		_hw4_launched(o, dt)
	if not h.leash.is_empty():
		_hw4_leash_tick(o, dt)


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
	for b in sk[i].get("do", _EA):
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


## Keep the existing hit pause; separate water and delayed ground wake.
static func _hw_slam_fx(o, c: Vector2, r: float, k: float) -> void:
	o.ground_dust(c, minf(r * 0.25, 24.0), 5)
	o.impact_pause(0.045 * k)
	UlpImpact.spawn(o, c, r, k)


static func _hw_draw_chain(o, a: Vector2, b: Vector2, al: float, thin := false) -> void:
	var cv = o.cv
	if thin:
		cv.draw_line(a, b, Color(0.04, 0.05, 0.08, 0.75 * al), 2.0)
		cv.draw_line(a, b, Color(0.58, 0.65, 0.68, 0.95 * al), 1.0)
		return
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
	var native: Dictionary = o.sprite_spec("anchor_native")
	if not native.is_empty():
		var anchor: Array = native.anchor
		if o._fx_strip(str(native.tex), 1, 0, p, Vector2(float(anchor[0]), float(anchor[1])), d.angle(), Color(1, 1, 1, a)):
			return
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


## 锚与锁链（data_operator._draw_skill_over）
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
		# 冲锋：本体残影 + 身后三道锚链拖痕
		var tr: Array = an.trail
		var mv_d: Vector2 = ((an.land as Vector2) - (an.start as Vector2)).normalized()
		var gz: bool = UlpCharge.on(o)
		if gz:
			# 颗粒版（docs/143）：残影只留上一帧一张、压暗不发光——4 张 HW_EDGE（分量 > 1）残影经发光层连成一大团白，读作「粘腻」；运动感交给水体颗粒
			if tr.size() > 1:
				o.draw_body_at(tr[1], o.face < 0.0, Color(0.45, 0.62, 0.85, 0.22))
		else:
			for i in range(tr.size() - 1, 0, -1):
				o.draw_body_at(tr[i], o.face < 0.0, Color(HW_EDGE.r, HW_EDGE.g, HW_EDGE.b, 0.35 * (1.0 - float(i) / tr.size())))
		for s in (0 if gz else 3):   # 颗粒版不画身后三道实线拖痕（水体颗粒代替）
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
		"ulp_wave", "ulp_fracture", "ulp_burst":
			return UlpImpact.draw(o, f, a)
		"whirl":
			if o.def.has("native_motion") and str(o.anim_state().get("kind", "")) == "whirl_native":
				return true  # Native body, chain and four-blade anchor are composed together.
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
	for f in o.B.get("look", _EA):
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
	for t in o.B.get("trait", []) + o.B.get("talent", _EA):
		for b in t.get("do", _EA):
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
			if b.has("pull_cc") and not b.pull_cc is bool:
				errs.append(p + ".pull_cc 应是 true / false（拖回的敌人打断 + 眩晕 + 沉默）")
			_num(b, "hold_frame", p, ctx, false, 0.0, 30.0)
			_num(b, "path_w", p, ctx, false, 1.0, 300.0)
			_num(b, "path_mult", p, ctx, false, 0.0, 20.0)
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


# ---------------------------------------------------------------- shape.hookshot（乌尔比安精二「掷锚」）

static func hw_hook_start(o, b: Dictionary) -> void:
	var g = o.g
	var h := _hw5(o)
	if o.pos == Vector2.INF or h.hooks.size() >= HW_HOOK_MAX:
		return
	var rr: float = float(b.get("range", 160.0)) * o.stat(&"op_range")
	var md: float = float(b.get("min_d", 160.0)) * o.stat(&"op_range")
	var tgt_e: Dictionary = {}   # 钩索瞄准的那名敌人（拖拽时无论落在不在一线都算在内，歌蕾蒂娅「钩中的人一定被拉动」）
	var to: Vector2
	if str(b.get("at", "")) == "leader":   # 响应动作（docs/118 §4.1）：掷向队长（冲刺落点），超出 range 就掷到 range 处；不找敌人
		var dv: Vector2 = o.g.ppos - o.pos
		to = o.pos + dv.limit_length(rr)
	else:
		var manual: bool = o.held_aim() and o.get("in_release") == true   # 按住瞄准（10-23）：只在玩家指向的锥内找目标，没有就掷到指向 rr 处
		var pool: Array = o.aim_targets(24, rr, o.pos) if manual else o.nearest_enemies(24, rr, o.pos)
		var best: Dictionary = {}
		var bd := -1.0
		for e in pool:
			if int(e.get("id", 0)) < 0:
				continue
			var dd: float = e.pos.distance_to(o.pos)
			if dd >= md and dd > bd:
				bd = dd
				best = e
		if best.is_empty():
			var ts: Array = pool.slice(0, 1) if manual else o.nearest_enemies(1, rr, o.pos)
			if ts.is_empty():
				return
			best = ts[0]
		to = best.pos
		tgt_e = best
	var hv = b.get("hand", [33, -33])
	var hand: Vector2 = o.pos + Vector2(float(hv[0]) * float(o.face), float(hv[1]))
	if absf(to.x - o.pos.x) > 2.0:
		o._set_face(signf(to.x - o.pos.x), true)
	var dur: float = clampf(hand.distance_to(to) / float(b.get("speed", 900.0)), 0.1, 0.24)
	h.hooks.append({"b": b, "phase": "fly", "t": 0.0, "dur": dur, "from": hand, "to": to, "head": hand, "drag": [], "dmg": hw_basis(o, str(b.get("basis", "atk"))), "tgt": tgt_e,
		"gl": o.B.get("attack", {}).has("hook_nodes")})   # gl：歌蕾蒂娅成长节点（docs/202，seg_gladiia）
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
					o.add_cc(e, 0.15)
					if hk.gl:
						_F().gl_drag_tick(o, hk, dg, dt)   # docs/202 歌蕾蒂娅「倒钩」：拖拽路径迸火星
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
	if not hits.is_empty() and "last_hit_pos" in o:   # 钩索当普攻（歌蕾蒂娅 every_n replace）：落地命中也算「上一次普攻命中点」（verb.field center: last_hit，S3 漩涡落点）
		o.last_hit_pos = hits[0].pos
	if b.has("impact_fx"):
		fx_play(o, b.impact_fx, c, r, hits)
	hk.phase = "taut"
	hk.t = 0.0
	hk.dur = float(b.get("taut", 0.2))
	hk.head = c


static var _HD = null


## 拖回落点离本干员的距离：front；当队长且写了 front_leader 时用它（歌蕾蒂娅当队长不把怪拖到脸上，docs/196 §3.2）
static func _hook_front_d(o, b: Dictionary) -> float:
	if o.is_leader and b.has("front_leader"):
		return float(b.front_leader)
	return float(b.get("front", 60.0))


## heavy_half 的对象：精英，或会自爆 / 爆裂的怪（壳海狂奔者 pattern blast、囊海爬行者 burst_at）
static func _hook_heavy(e: Dictionary) -> bool:
	if e.elite or e.has("burst_at"):
		return true
	if _HD == null:
		_HD = load("res://scripts/data.gd")
	return str(_HD.ENEMIES.get(e.get("type", ""), {}).get("pattern", "")) == "blast"


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
	var fd: float = _hook_front_d(o, b)
	var front: Vector2 = a + d * fd
	var got: Array = []
	for j in o.query_ids((a + c) * 0.5, L * 0.5 + w + 30.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or not _movable(e) or not line_contains(a, d, L, w, e.pos, float(e.r)):
			continue
		if e.pos.distance_to(a) <= fd and not bool(b.get("push_out", false)):
			continue   # 已经在身前的不拖（push_out：比落点近的也推到落点去——歌蕾蒂娅「别拉到面前」，docs/123 §2.1 第 8 轮）
		if str(b.get("drag_only", "all")) == "ranged" and str(e.get("ai", "")) != "ranged":
			continue   # 歌蕾蒂娅（docs/123 §2.1，10-22）：只把远程怪拖回身前，近战怪本来就会贴上来，拉过来只会把队长埋进怪堆
		got.append(e)
	var te: Dictionary = hk.get("tgt", {})
	if not te.is_empty() and int(te.get("id", -1)) >= 0 and not te.dead and _movable(te) and not got.has(te) and str(b.get("drag_only", "all")) != "ranged" and (te.pos.distance_to(a) > fd or bool(b.get("push_out", false))):
		got.append(te)   # 钩中的那一名：落地后 0.12–0.34 秒里队长位置 / 敌人位置变了、掉出一线的窄走廊也照样拖（10-24 歌蕾蒂娅「拉不动人」）
	got.sort_custom(func(x, y): return x.pos.distance_squared_to(a) < y.pos.distance_squared_to(a) if x.pos.distance_squared_to(a) != y.pos.distance_squared_to(a) else int(x.id) < int(y.id))
	var mx: int = int(b.get("max_n", 12))
	for i in mini(mx, got.size()):
		var e: Dictionary = got[i]
		var side: float = (1.0 if i % 2 == 1 else -1.0) * ceilf(i / 2.0)
		var spot: Vector2 = front + d * (float(e.r) * 0.5) + d.orthogonal() * side * 14.0 + d * absf(side) * 6.0
		if bool(b.get("heavy_half", false)) and o.is_leader and _hook_heavy(e):
			spot = e.pos.lerp(spot, 0.5)   # 歌蕾蒂娅当队长：精英与自爆怪只拖半程（全员手感排查 docs/196 §3.2，协调人 10-29 定）
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
	var st_arr: float = float(b.get("arrive_stun", 0.0))   # 歌蕾蒂娅（docs/123 §2.1，用户 10-22 定）：拖回到位的敌人原地眩晕；精一起用 arrive_stun_elite1
	if o.elite >= 1 and b.has("arrive_stun_elite1"):
		st_arr = float(b.arrive_stun_elite1)
	for dg in hk.drag:
		var e: Dictionary = dg.e
		if e.dead:
			continue
		o.log_hit(src, b.get("tags", []))
		o.deal_damage(e, dmg * (ve if e.elite or e.boss else 1.0))
		if st_arr > 0.0 and not e.dead:
			apply_status(o, e, {"st": "stun", "dur": st_arr}, e.pos)
		if b.get("pull_cc", false) and not e.dead:
			_hw_pull_cc(o, e)
		hits.append(e)
	if b.has("arrive_fx") and not hits.is_empty():
		fx_play(o, b.arrive_fx, hk.front, 40.0, hits)
	if hk.gl and not hits.is_empty():
		_F().gl_arrive(o, hk)   # docs/202 歌蕾蒂娅成长节点：倒钩结算 / 回收斩 / 锁链沉底（seg_gladiia）
	if not hits.is_empty() and o.has_method("notify_mate_hook"):   # 联动段（docs/123 §2.7「钩与锚」）：告诉队友「我把人拖到 front 了」
		o.notify_mate_hook(hk.front, hits)


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
		if o.def.has("native_motion"):
			hand = _hw_hand(o)
			if hk.phase == "fly":
				p = hand.lerp(hk.to, clampf(float(hk.t) / maxf(float(hk.dur), .001), 0.0, 1.0)) + Vector2(0, -6)
		var tile: String = str(b.get("chain", ""))
		var taut: bool = str(hk.phase) != "fly"
		if tile != "" and g.tex.get(tile) != null:
			var shake: Vector2 = Vector2(0, sin(float(g.t) * 60.0) * 2.0) if str(hk.phase) == "taut" else Vector2.ZERO
			_hw_draw_tiled(o, tile, hand, p + shake, g.PX, 0.0, 0, Color.WHITE, 1 if taut else 0)
		else:
			_hw_draw_chain(o, hand, p, 1.0, bool(b.get("thin_chain", false)))
		for dg in hk.drag:
			if str(hk.phase) == "drag" and not dg.e.dead:
				_hw_draw_chain(o, p, dg.e.pos + Vector2(0, -float(dg.e.r) * 0.5), 0.7, bool(b.get("thin_chain", false)))
		var dirv: Vector2 = ((hk.to as Vector2) - (hk.from as Vector2)).normalized()
		var head: String = str(b.get("head", ""))   # 歌蕾蒂娅（docs/123 §6）：细长倒钩贴图代替程序锚头；缺图退回程序锚
		if head != "" and g.tex.get(head) != null and g.V6_FRAMES.has(head):
			var hf: int = 0 if str(hk.phase) == "fly" else (1 if str(hk.phase) == "taut" else 2)
			o.draw_spr_rot(head, hf, p, (-dirv if str(hk.phase) == "drag" else dirv).angle(), g.PX, Color.WHITE)
		else:
			_hw_draw_anchor(o, p, -dirv if str(hk.phase) == "drag" else dirv, 1.0)


## 原生动作信号（native_motion.gd 按 json native_motion.states / exits 取用，docs/108 §3.5）：
## tether.<阶段> / zip.<阶段> = 掷锚（mode zip 的掷锚归 zip），hook.<阶段> = 最后一条钩索，whirl = 甩锚；值为该阶段进度 0–1
static func hw_native_signals(o, out: Dictionary) -> void:
	var an: Dictionary = o.hw.get("anchor", {})
	if not an.is_empty() and str(an.get("phase", "")) != "":
		var fam := "zip" if str(an.phase) == "zip" or str(an.get("b", {}).get("mode", "")) == "zip" else "tether"
		out[fam + "." + str(an.phase)] = clampf(float(an.t) / maxf(float(an.dur), 0.001), 0.0, 1.0)
	var hooks: Array = o.hw.get("hooks", [])
	if not hooks.is_empty():
		var hk: Dictionary = hooks[-1]
		out["hook." + str(hk.phase)] = clampf(float(hk.t) / maxf(float(hk.dur), .001), 0.0, 1.0)
	for f in o.pfx:
		if str(f.get("kind", "")) == "whirl":
			out["whirl"] = 1.0 - float(f.life) / float(f.max)
			break
