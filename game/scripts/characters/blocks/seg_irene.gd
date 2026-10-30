## 干员积木 · seg_irene（docs/101 §7.3 B6 ①，10-15：由 op_blocks.gd 按段拆出，内容与注释照搬；继承链与门面见 op_blocks.gd）
extends "res://scripts/characters/blocks/seg_ulpianus.gd"
const IrVg = preload("res://scripts/characters/blocks/vis_growth.gd")   # 老近卫军之锋 #56（docs/163D）：刺击 / 环斩命中 ≥ 3 名


# ---------------------------------------------------------------- shape.thrust

static func h3_thrust_len(o, a: Dictionary) -> float:
	return _h3_mults(o, float(a.get("len", 180.0)) * o.stat(&"op_range"), a.get("len_mults", []))


static func h3_thrust_w(o, a: Dictionary) -> float:
	return _h3_mults(o, float(a.get("w", 26.0)), a.get("w_mults", []))


## 普攻起手（data_operator.update，按住瞄准 A 类）
static func h3_attack_aim(o, a: Dictionary) -> Vector2:
	match str(a.get("shape", "")):
		"thrust":
			var L: float = h3_thrust_len(o, a)
			return o.atk_point(o.nearest_enemies(1, L + float(a.get("aim_pad", 20.0)), o.pos), L)
		"saw":
			var r: float = _F().h3_saw_r(o, a)
			return o.atk_point(o.nearest_enemies(1, r + float(a.get("aim_pad", 30.0)), o.pos), r)
	return Vector2.INF


## 普攻起手（data_operator.update：技能判定之后）：荧光先累计计时；其余同数据干员的起手（冷却、闸门、replace 帧条），间隔按 h3_attack_cd
static func h3_attack_start(o, a: Dictionary, dt: float) -> void:
	if str(a.get("shape", "")) == "umbrella":
		_F().h3_umbrella_start(o, a)
		return
	if str(a.get("shape", "")) == "lantern":
		_F()._h3_lantern_start(o, a, dt)
		return
	if o.no_attack or o.cd > 0.0 or el_attack_locked(o) or hw_attack_locked(o):
		return
	var at: Vector2 = h3_attack_aim(o, a)
	if at == Vector2.INF:
		o.cd = float(a.get("idle", 0.2))
		return
	o.cd = _F().h3_attack_cd(o, a)
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
			_F()._h3_saw_release(o, a)
		"lantern":
			_F()._h3_lantern_release(o, a)


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
	if not stg.is_empty() and cond_true(o, stg[0].get("cond", _ED)):
		ir.st_t = _h3_stage_gap(o, a)
	else:
		ir.st_t = -1.0
	ir.st_ang = ang
	ir.st_mult = mult
	ir["strict_e"] = null
	if not first.is_empty() and not first.boss and "strict" in o.taken:   # docs/202 严律：第 1 段命中的第一个敌人停顿，第 2 段直刺它
		var halt: float = o.base("strict_halt", 0.3) * (0.5 if first.elite else 1.0)
		o.add_cc_growth(first, halt)
		ir["strict_e"] = first
		var hp: Vector2 = first.pos + Vector2(0, -float(first.r) * 2.4 - 12.0)   # 头顶一圈白色刺印
		o.fx({"kind": "ring", "pos": hp, "r": 13.0, "r0": 13.0, "life": halt + 0.15, "col": Color(2.0, 1.7, 2.0), "keep": true, "w": 3.0})
		for q in 4:
			var d4 := Vector2.from_angle(q * PI * 0.5 + PI * 0.25)
			o.fx({"kind": "line", "pos": hp + d4 * 13.0, "to": hp + d4 * 21.0, "life": halt + 0.15, "col": Color(1.1, 0.8, 1.1), "w": 2.5})
	if not patch.is_empty() and not first.is_empty():
		for s in patch.get("on_first", _EA):
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
	var gap := maxf(0.05, (float(spec.get("second", a.get("second", 3))) - float(spec.get("fire", 1))) / fps)
	# 连刺属于同一轮；压缩后不能仍按原秒数排队到下一轮。
	var action: Dictionary = o.sprite_spec(o.act_anim)
	if o.attack_phased and action.has("attack_timing"):
		gap *= o.attack_dur / float(action.attack_timing.duration)
	return gap


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
	var more: bool = k + 1 < stg.size() and cond_true(o, stg[k + 1].get("cond", _ED))
	if not more and ir.get("fin", false):   # 精英化第 3 批：这一轮的收尾换成 finisher（裂潮余波）
		ir.fin = false
		_e3_finisher(o, a)
		return
	var m: float = float(ir.st_mult) * float(sg.mult) if sg.has("mult") else float(ir.st_mult)
	var sang: float = float(ir.st_ang)
	var se = ir.get("strict_e")
	if k == 0 and se != null:   # docs/202 严律：第 2 段直刺被停顿的敌人（必中）
		if not se.dead:
			sang = (se.pos - (o.pos + Vector2(0, float(a.get("y", -12.0))))).angle()
		ir["strict_e"] = null
	var first: Dictionary = _h3_thrust(o, a, sang, m, {}, int(ir.st_i))
	if not first.is_empty():
		for s in sg.get("on_first", _EA):   # 精英化第 3 批：这一段首中目标的状态（挑刺）
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
		var along: float = seg_rect_along(org, d, L, W * 0.5, e.pos, e.r)   # B6 ⑤：ob_geom
		if along == -INF:
			continue
		hits.append([along, e])
	hits.sort_custom(func(x, y): return x[0] < y[0])
	var dmg: float = o.base(str(a.get("atk_key", "atk")), 0.0) * o._dmg_bonus() * mult
	if hits.size() >= 3:   # 老近卫军之锋 #56：这一段刺击的实际目标 ≥ 3 名
		dmg *= IrVg.crowd_mult(o, hits.map(func(x): return x[1]), a.get("tags", []))
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
	var tsc: float = g.PX * clampf(L / 128.0, 0.9, 1.1)   # 帧条限幅（再放大颗粒过粗）；判定被范围藏品拉长时下面用程序光束补齐全长
	var star: String = str(lk.get("star", "fx_star_hit_rose"))
	if not o.spawn_fx_sprite(str(lk.get("beam", "fx_irene_thrust")), st + d * 32.0 * tsc, tsc, ang, false, false, Color(1.1, 0.8, 1.0) if gust else Color.WHITE):
		o.fx({"kind": "h3_thrust", "pos": st, "dir": d, "len": L, "w": 9.0 if gust else 7.0, "life": 0.16, "col": gcol if gust else col, "star": star})
		o.spawn_fx_sprite(star, st + d * (L + 10.0), g.PX * 0.8)
	elif h3_thrust_w(o, a) > float(a.get("w", 26.0)) * 1.01 or o.stat(&"op_range") > 1.01:   # 163B §3：范围藏品拉长刺击时画面跟判定走
		var wk: float = maxf(1.0, h3_thrust_w(o, a) / maxf(1.0, float(a.get("w", 26.0))))
		o.fx({"kind": "h3_thrust", "pos": st, "dir": d, "len": L, "w": 7.0 * wk, "life": 0.16, "col": gcol if gust else col, "star": star})
		o.spawn_fx_sprite(star, st + d * (L + 6.0), g.PX * 0.8)
	if stage == 3:
		o.fx({"kind": "glow", "pos": st + d * L, "r": 10.0, "life": 0.18, "col": H3_LAMP, "alpha": 0.7})


static func _h3_pursue(o, a: Dictionary) -> Dictionary:
	var pu = a.get("pursue", null)
	if pu is Dictionary and cond_true(o, pu.get("cond", _ED)):
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
		if str(t.get("_tag", "")) != "trig.passive" or not cond_true(o, t.get("cond", _ED)):
			continue
		for b in t.get("do", _EA):
			if str(b.get("_tag", "")) == "verb.ctrl_bonus" and cond_true(o, b.get("cond", _ED)):
				return float(b.get("value", 0.0))
	return 0.0


## 手炮一发：c 周围 r 内 area_hit（同手写 _cannon），炮口一闪 → 弹道光 → 黑烟小爆炸
static func _h3_cannon(o, cb: Dictionary, c: Vector2, dmg: float) -> void:
	var g = o.g
	o.area_hit(str(cb.get("src", "")), c, float(cb.get("r", 40.0)), dmg, 0.0, 0.0)
	var muzzle: Vector2 = o.pos + Vector2(12.0 * o.face, -30)
	o.spawn_fx_sprite(str(cb.get("muzzle", "fx_muzzle_flash")), muzzle, g.PX * 0.7)
	o.fx({"kind": "line", "pos": muzzle, "to": c + Vector2(0, -10), "life": 0.08, "col": Color(1.0, 0.8, 0.6), "w": 2.0, "laser": true})
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
	o.add_cc(e, dur, -INF, "airborne")


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
			o.set_air(e, 0.0)
			a.t = a.dur + 1.0
			continue
		var k: float = clampf(a.t / a.dur, 0.0, 1.0)
		o.set_air(e, sin(k * PI) * a.h if k < 1.0 else 0.0, true)   # 浮空期间不吃击退
	ir.air = ir.air.filter(func(a): return a.t < a.dur)


static func h3_lift_around(o, b: Dictionary, at: Vector2) -> void:
	var g = o.g
	var ir := _h3ir(o)
	if at == Vector2.INF and b.has("center"):   # 响应动作（docs/118）：没有命中点时以 center（self / leader）为心
		at = g.ppos if str(b.center) == "leader" else o.pos
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
		for s in b.get("on_hit", _EA):
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
			var e: Dictionary = pool[g.rng_op.randi() % pool.size()]
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


# ---------------------------------------------------------------- 艾丽妮：挑刺 / 裂潮余波

## 这一刺（出手帧）是不是收尾换斩的那一轮
static func _e3_fin_arm(o, a: Dictionary) -> void:
	var ir: Dictionary = o.hw.ir
	var fn = a.get("finisher", null)
	ir["fin"] = fn is Dictionary and cond_true(o, fn.get("cond", _ED)) and (int(o.atk_n) + 1) % maxi(1, int(fn.get("every", 3))) == 0


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
	for e in ir.get("last_hits", _EA):
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
