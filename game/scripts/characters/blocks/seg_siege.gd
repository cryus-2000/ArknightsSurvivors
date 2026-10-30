## 干员积木 · seg_siege（docs/101 §7.3 B6 ①，10-15：由 op_blocks.gd 按段拆出，内容与注释照搬；继承链与门面见 op_blocks.gd）
extends "res://scripts/characters/blocks/seg_mizuki.gd"


# ---------------------------------------------------------------- 推进之王：锤击

## 成长节点（docs/202）：attack.quake.roar.col_mult / wall_mult / life / col_src = 「狮吼」击退碰撞；verb.cmd_wave.purge {cond} = 「万兽之王·威令」号令波清负面状态
static func _h4sg(o) -> Dictionary:
	var h := hw_st(o)
	if not h.has("sg"):
		h["sg"] = {"leap_t": -1.0, "leap_pos": Vector2.ZERO, "leap_to": Vector2.ZERO, "leap_n": 0, "leap_second": false, "leap_b": {},
			"heavy_swing": false, "waves": [], "fissures": [], "spikes": [], "flights": []}
	return h.sg


static func _h4_heavy(o, a: Dictionary) -> Dictionary:
	return _h4_sub(o, a.get("heavy", null))


static func _h4_hammer_start(o, a: Dictionary) -> void:
	if o.cd > 0.0:
		return
	var reach: float = float(a.get("r", 108.0)) * o.stat(&"op_range")
	var at: Vector2 = o.atk_point(o.nearest_enemies(1, reach + 30.0, o.pos), reach)   # 按住瞄准 A 类（契约 v2.5）
	if at == Vector2.INF:
		o.cd = float(a.get("idle", 0.1))
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
			if not e.dead and not e.boss and g.rng_op.randf() < ch:
				o.add_cc(e, float(hv.get("stun", 0.8)) * (0.5 if e.elite else 1.0))
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


## 狮吼（docs/202，10-29 去数值化）：冲击环击退的敌人在 life 秒内撞上别的敌人（没被这一圈击退的）时，两者各受锤击 col_mult 的伤害；
## 撞上景物底座 / 障碍时那名敌人受锤击 wall_mult 的伤害。只挂在她自己这一圈的击退上，不碰全局击退函数；同时在飞的至多 40 名，每名只撞一次；Boss 不击退也不算
static func _h4_flights_add(o, ro: Dictionary, hits: Array, c: Vector2) -> void:
	if not ro.has("col_mult"):
		return
	var sg := _h4sg(o)
	var ids := {}
	for e in hits:
		ids[e.id] = true
	for e in hits:
		if e.dead or e.boss:
			continue
		if sg.flights.size() >= 40:
			break
		var d: Vector2 = e.pos - c
		sg.flights.append({"e": e, "dir": d.normalized() if d.length() > 1.0 else Vector2(o.face, 0), "t": float(ro.get("life", 0.45)), "set": ids, "b": ro})


static func _h4_flights_tick(o, sg: Dictionary, dt: float) -> void:
	if sg.flights.is_empty():
		return
	var g = o.g
	var wall_on: bool = g.map.blocks()
	var keep: Array = []
	for f in sg.flights:
		var e: Dictionary = f.e
		f.t = float(f.t) - dt
		if e.dead or float(f.t) <= 0.0:
			continue
		var b: Dictionary = f.b
		var dir: Vector2 = f.dir
		var base_d: float = o.base("atk", 0.0) * o._dmg_bonus()
		var done := false
		if e.kb.length_squared() > 400.0:   # 还在被推着走才算撞
			if wall_on and g.map.point_blocked(e.pos + dir * (float(e.r) + 6.0)):
				o.log_hit(str(b.get("col_src", "")))
				o.deal_damage(e, base_d * float(b.get("wall_mult", 0.5)) * (o.vs_elite() if e.elite else 1.0))
				_h4_crash_fx(o, e.pos + dir * float(e.r), dir)
				done = true
			else:
				for j in o.query_ids(e.pos + dir * float(e.r), float(e.r) + 50.0):
					var q: Dictionary = g.enemies[j]
					if q.dead or is_same(q, e) or f.set.has(q.id) or dir.dot(q.pos - e.pos) <= 0.0:
						continue
					if e.pos.distance_to(q.pos) > float(e.r) + float(q.r) + 2.0:
						continue
					var dm: float = base_d * float(b.get("col_mult", 0.3))
					o.log_hit(str(b.get("col_src", "")))
					o.deal_damage(e, dm * (o.vs_elite() if e.elite else 1.0))
					o.log_hit(str(b.get("col_src", "")))
					o.deal_damage(q, dm * (o.vs_elite() if q.elite or q.boss else 1.0))
					_h4_crash_fx(o, (e.pos + q.pos) * 0.5, dir)
					done = true
					break
		if not done:
			keep.append(f)
	sg.flights = keep


static func _h4_crash_fx(o, p: Vector2, dir: Vector2) -> void:
	o.fx({"kind": "glow", "pos": p + Vector2(0, -8), "r": 15.0, "life": 0.16, "col": Color(2.0, 1.6, 0.8), "alpha": 0.85})
	o.fx({"kind": "ring", "pos": p + Vector2(0, 2), "r": 22.0, "r0": 4.0, "life": 0.2, "col": H4_GOLD, "floor": true, "w": 2.5})
	o.fx({"kind": "line", "pos": p + Vector2(0, -8) - dir * 12.0, "to": p + Vector2(0, -8) + dir * 12.0, "life": 0.14, "col": Color(2.0, 1.7, 1.0), "w": 3.0})
	_h3_vsparks(o, p + Vector2(0, -6), H4_GOLD, 6, 200.0, 0.3, 2.5, 200.0)
	_h3_sfx(o, "hit", 1.0, 0.9)


## 震地 / 狮吼：锤子落地处一圈贴地冲击环（锤击 quake.mult 伤害；roar：击退，被击退的敌人撞上别的敌人 / 障碍时受伤）+ 尘土
static func _h4_quake(o, q: Dictionary, p: Vector2, mult: float) -> void:
	var g = o.g
	var ro: Dictionary = _h4_sub(o, q.get("roar", null))
	var roar: bool = not ro.is_empty()
	var r: float = float(q.get("r", 70.0)) * (float(ro.get("r_mult", 1.0)) if roar else 1.0) * o.stat(&"op_range")
	var kb: float = float(ro.get("kb", 0.0)) if roar else 0.0
	var qh: Array = o.area_hit(str(q.get("src", "")), p, r, o.base("atk", 0.0) * mult * float(q.get("mult", 0.25)) * o._dmg_bonus(), kb)
	if roar and kb > 0.0:
		_h4_flights_add(o, ro, qh, p)
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
	var lead: bool = str(b.get("from", "self")) == "leader"
	if lead and float(sg.leap_t) >= 0.0:
		return   # 响应动作：已在空中（S2 跃空锤）就不另跳
	var ag: Dictionary = _h4_sub(o, b.get("again", null))
	sg.leap_n = 1 if not ag.is_empty() else 0
	sg.leap_second = false
	sg.leap_b = b
	# from: leader（响应动作 docs/118 §4.1）：找队长 aim_r 内离队长最近的敌人；她本人是队长时原地砸（不另位移，冲刺已由队长本体完成）
	var ts: Array = [] if lead and o.is_leader else o.nearest_enemies(1, float(b.get("aim_r", 160.0)), o.g.ppos if lead else o.pos)
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
	var pw: float = o.skill_power() if b.get("power", true) else 1.0   # power: false = 不吃技能强度（响应动作的补锤）
	var hits: Array = o.area_hit(str(b.get("src", "")), pos, r, o.base("atk", 0.0) * float(b.get("mult", 2.2)) * o._dmg_bonus() * pw * sm, float(b.get("kb", 220.0)), float(b.get("stun", 0.6)))
	o.fx({"kind": "glow", "pos": pos + Vector2(0, -6), "r": 34.0, "life": 0.16, "col": Color(2.0, 1.7, 0.9), "alpha": 0.8})
	o.fx({"kind": "ring", "pos": pos, "r": r, "r0": 14.0, "life": 0.35, "col": H4_FLAME, "floor": true, "w": 4.0})
	o.fx({"kind": "crack", "pos": pos + Vector2(0, 2), "r": r * 0.8, "life": 0.55, "col": H4_GOLD, "floor": true, "n": 10, "ang": g.t})
	o.fx({"kind": "h4_pillar", "pos": pos + Vector2(0, 2), "life": 0.38, "col": Color(1.9, 1.7, 0.6)})
	# 10-14 用户「推进之王二技能打中地面的火焰效果删除，只保留裂地效果」：去掉落地火圈与一圈火焰（fx_fire_aura / fx_flames / 程序 h4_blaze），
	# 留裂地（crack）、冲击环、光柱、火星与扬尘；纯画面
	o.ground_dust(pos, r * 0.6, 10)
	_h3_vsparks(o, pos + Vector2(0, -4), Color(1.0, 0.8, 0.35), 12, 260.0, 0.4, 2.5, 320.0)
	o.impact_pause(0.07)
	if second:
		pass
	elif b.has("sp_secs"):   # 响应动作的补锤：砸中敌人时全队（不含自己）技力 + 秒数，同锤击的 hit_sp
		if not hits.is_empty():
			_h4_squad_sp_seconds(o, float(b.sp_secs))
			_h4_sp_motes(o, 2)
	else:
		g.squad.gain_sp(float(b.get("sp", 0.2)) * pw, o)
		_h4_sp_motes(o, 3)
	_h3_sfx(o, "big")


## 再跃（队长版）：不位移，从落点朝下一群敌人砸出一道地裂（长度够到那群、至多 again.range），伤害同第二跳（× again.mult × 技能强度）
static func _h4_leap_crack(o, b: Dictionary, tg: Dictionary) -> void:
	var ag = b.get("again", {})
	var dv: Vector2 = tg.pos - o.pos
	var L: float = clampf(dv.length() + 40.0, 120.0, float(ag.get("range", 220.0)))
	var pw: float = o.skill_power() if b.get("power", true) else 1.0
	_h4_breach(o, {"len": L, "w": 40.0, "mult": float(ag.get("mult", 0.6)), "life": 0.6, "max": 6, "src": str(b.get("src", ""))}, o.pos, dv.angle(), float(b.get("mult", 2.2)) * pw)
	o.face = signf(dv.x) if absf(dv.x) > 1.0 else o.face
	o.impact_pause(0.05)
	_h3_sfx(o, "big", -3.0, 1.1)


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


## 万兽之王·威令（docs/202）：号令波扫过队长 / 队友时，每名干员每道波一次：队长清除一个负面状态（束缚 → 寒冷 → 减速 → 神经损伤，按顺序取第一个有的），队友脚下一圈金光（队友没有负面状态）
static func _h4_wave_purge(o, w: Dictionary, b: Dictionary) -> void:
	var pg: Dictionary = _h4_sub(o, b.get("purge", null))
	if pg.is_empty():
		return
	var g = o.g
	if not w.has("purged"):
		w["purged"] = {}
	var pd: Dictionary = w.purged
	var R: float = float(w.r)
	if not pd.has("leader") and g.ppos.distance_to(w.pos) <= R:
		pd["leader"] = true
		var nm: String = _h4_purge_one(o)
		o.fx({"kind": "ring", "pos": g.ppos, "r": 34.0, "r0": 8.0, "life": 0.4, "col": H4_GOLD, "floor": true, "w": 3.0})
		o.fx({"kind": "glow", "pos": g.ppos + Vector2(0, -30), "r": 18.0, "life": 0.3, "col": Color(2.0, 1.7, 0.9), "alpha": 0.7})
		if nm != "":
			o.float_text(g.ppos + Vector2(0, -96), "净化 · " + nm, H4_GOLD, 14)
	for m in g.squad.ops:
		if m == o or m.pos == Vector2.INF or pd.has(m.id):
			continue
		if m.pos.distance_to(w.pos) <= R:
			pd[m.id] = true
			o.fx({"kind": "ring", "pos": m.pos, "r": 30.0, "r0": 8.0, "life": 0.4, "col": H4_GOLD, "floor": true, "w": 2.5})
			o.fx({"kind": "glow", "pos": m.pos + Vector2(0, -26), "r": 14.0, "life": 0.3, "col": Color(2.0, 1.7, 0.9), "alpha": 0.6})


static func _h4_purge_one(o) -> String:
	var g = o.g
	if g.root_t > 0.0:
		g.root_t = 0.0
		return "束缚"
	if g.cold > 0:
		g.cold = 0
		g.cold_t = 0.0
		g.combat.sync_cold()
		return "寒冷"
	if g.frost > 0.0 or g.fire_slow_t > 0.0:
		g.frost = 0.0
		g.fire_slow_t = 0.0
		return "减速"
	if g.nerve > 0.0:
		g.nerve = 0.0
		return "神经损伤"
	return ""


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
					o.apply_kb(e, (e.pos - w.pos).normalized() * float(b.get("kb", 380.0)))
				_h3_vsparks(o, e.pos, H4_GOLD, 2, 140.0, 0.3, 2.0)
			_h4_wave_purge(o, w, b)
		sg.waves = sg.waves.filter(func(w): return w.t < float(w.b.get("dur", 0.4)) + 0.25)
	_h4_flights_tick(o, sg, dt)
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
				if nc != null and o.is_leader:
					_h4_leap_crack(o, b2, nc)   # 她当队长时不再跃进下一群怪（全员手感排查 docs/196 §3.1，协调人 10-29 定）：原地朝那群砸出一道地裂
				elif nc != null:
					sg.leap_second = true
					_h4_start_leap(o, nc, float(b2.get("again", _ED).get("dist", 150.0)))
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
	if o.def.has("native_motion"):
		return false  # Native leap poses already contain the turn and height.
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
		pass   # 10-29 特效审查：去掉整片半透明填充圆盘（遮敌人 / 弹幕），只留描边
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


## 原生动作信号（native_motion.gd 按 json native_motion.states / exits 取用，docs/108 §3.5）：leap = 跃空锤进度 0–1
static func h4_native_signals(o, out: Dictionary) -> void:
	if o.hw.has("sg") and float(o.hw.sg.get("leap_t", -1.0)) >= 0.0:
		out["leap"] = float(o.hw.sg.leap_t) / float(o.hw.sg.get("leap_b", {}).get("t", 0.42))
