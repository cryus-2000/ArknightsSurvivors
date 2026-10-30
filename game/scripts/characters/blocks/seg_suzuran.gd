## 干员积木 · seg_suzuran（docs/101 §7.3 B6 ①，10-15：由 op_blocks.gd 按段拆出，内容与注释照搬；继承链与门面见 op_blocks.gd）
extends "res://scripts/characters/blocks/seg_siege.gd"


# ---------------------------------------------------------------- 铃兰段（第 4 批续，SZ_TAGS）
#  shape.foxfire    追踪狐火（普攻，手动 B 类）：起手 attack_targets(aim_n, range)，出手向 aim_targets(n, range + aim_pad) 发 n 团狐火（game 的 arcane 弹：追踪、命中小范围溅射）；
#                   n = shots + shot_adds 里 cond 成立的 n 之和；次数型补丁（狐火连珠）attack_patch {shots, mult, power}；狐火从杖头 tip 发出；同时在场的弹体 ≤ proj_max（含大狐火、围炉狐火）；
#                   merge {cond, every, all {cond}, mult, spd, life, r}：每第 every 次普攻（all 成立时每一次）三团合成一团大狐火直线贯穿（每名敌人一次）；
#                   seal {cond, stun, stun_elite}：狐火连珠的狐火命中后定身（Boss 不受）+ 脚下金印；狐火迷雾（光域 haze）期间不普攻
#  成长节点（docs/202，10-29）：attack.attach {cond, dur, r, every, mult, max, src} = 「狐火点点」：狐火（含大狐火）命中后不消散，附在目标身上 dur 秒（一团小火跟着敌人走），
#                   每 every 秒灼烧附着体周围 r 内的敌人（攻击 × mult，每名敌人每跳一次，不管几团火罩着它），并向 r 内一名未被附着的敌人传一次火；同时至多 max 团
#  verb.foxlight    光域（放 trait 的 passive）：以本干员为心，半径 (r + r_elite × 精英阶段) × op_range，暖光（warm 条件）× warm_mult、迷雾 × haze_mult；
#                   区域内敌人减速（slow[平时 / 暖光 / 迷雾] 秒）、weak_cond 成立或迷雾时 aura_weak；暖光或迷雾期间每秒为队长回复 heal[平时 / 迷雾]；
#                   迷雾结束时：暖光在 → 其他干员攻击 + warm_buff × 技能强度，否则撤掉；hearth {cond, n, mult, cd, src}：暖光生效后光域边缘的狐火灼伤碰到的敌人
#  verb.fox_cast    暖光 / 狐火迷雾的出手：haze 秒迷雾（不写 = 暖光）、其他干员攻击 + buff × 技能强度、banner，光域边缘升起光柱

static func _h4sz(o) -> Dictionary:
	var h := hw_st(o)
	if not h.has("sz"):
		h["sz"] = {"haze_t": 0.0, "mote_t": 0.0, "heal_acc": 0.0, "pillar_t": 0.0, "n": 0, "merging": false,
			"bigfox": [], "sealed": [], "seals": [], "hearth_hit": {}, "brand": [], "brands": [], "trails": [],
			"att_b": [], "att": [], "att_clock": 0.0}
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
	for m in a.get("shot_adds", _EA):
		if m is Dictionary and cond_true(o, m.get("cond", _ED)):
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
	return cond_true(o, mg.get("cond", _ED)) and int(_h4sz(o).n) % every == every - 1


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
	var ts: Array = o.attack_targets(int(a.get("aim_n", 2)), float(a.get("range", 350.0)) * o.stat(&"op_range"), o.pos)   # 按住瞄准 B 类（契约 v2.5）
	if ts.is_empty():
		o.cd = float(a.get("idle", 0.2))
		return
	o.cd = float(a.get("every", 1.0)) / o.stat(&"op_aspd")
	sz.merging = _h4_next_merge(o, a) and not _h4_patch_pending(o)
	o.start_attack(ts[0].pos, 0.5, 0.25, "", o.cd)
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
		if not o.held_aim():
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
	var sz := _h4sz(o)
	if not _h4_sub(o, a.get("attach", null)).is_empty() and sz.att_b.size() < 32:
		sz.att_b.append(b)   # 狐火点点（docs/202）：命中后附着
	if _h4_sub(o, a.get("brand", null)).is_empty():
		return
	if sz.brand.size() < 32:
		sz.brand.append(b)


## 狐火点点（docs/202）：附着。同一名敌人再被附着只刷新时长；上限 max 团（满了丢最早的）
static func _h4_attach(o, at: Dictionary, e: Dictionary, can_pass := true) -> void:
	if e.dead or e.get("chest", false):
		return
	var sz := _h4sz(o)
	var dur: float = float(at.get("dur", 2.0))
	for s2 in sz.att:
		if is_same(s2.e, e):
			s2.t = maxf(float(s2.t), dur)
			return
	if sz.att.size() >= int(at.get("max", 12)):
		sz.att.pop_front()
	sz.att.append({"e": e, "t": dur, "pass": can_pass})
	o.fx({"kind": "glow", "pos": e.pos + Vector2(0, -float(e.r)), "r": 12.0, "life": 0.2, "col": H4_FOX, "alpha": 0.7})


static func _h4_attach_tick(o, sz: Dictionary, a: Dictionary, dt: float) -> void:
	var at: Dictionary = _h4_sub(o, a.get("attach", null))
	if at.is_empty():
		sz.att_b.clear()
		sz.att.clear()
		return
	var g = o.g
	# 命中判定：同灼印——game 结算命中时把弹体 life 置 0，自然消散是负数
	for i in range(sz.att_b.size() - 1, -1, -1):
		var b: Dictionary = sz.att_b[i]
		if b.life > 0.0:
			continue
		sz.att_b.remove_at(i)
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
		if best != null:
			_h4_attach(o, at, best)
	if sz.att.is_empty():
		return
	for s2 in sz.att:
		s2.t = float(s2.t) - dt
	sz.att = sz.att.filter(func(s2): return float(s2.t) > 0.0 and not s2.e.dead)
	if sz.att.is_empty():
		return
	sz.att_clock = float(sz.att_clock) + dt
	if float(sz.att_clock) < float(at.get("every", 0.5)):
		return
	sz.att_clock = 0.0
	var r: float = float(at.get("r", 60.0)) * o.stat(&"op_range")
	var dmg: float = o.base(str(a.get("atk_key", "atk")), 0.0) * float(at.get("mult", 0.15)) * o._dmg_bonus()
	var src: String = str(at.get("src", ""))
	var burned := {}
	var victims: Array = []
	var passes: Array = []
	for s2 in sz.att:
		var c: Vector2 = s2.e.pos
		for j in o.query_ids(c, r + 40.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or burned.has(e.id) or e.pos.distance_to(c) > r + e.r:
				continue
			burned[e.id] = true
			victims.append(e)
		if s2.pass:
			passes.append(s2)
	for e3 in victims:
		o.log_hit(src)
		o.deal_damage(e3, dmg * (o.vs_elite() if e3.elite or e3.boss else 1.0))
		o.fx({"kind": "flame", "pos": e3.pos + Vector2(0, 4), "vel": Vector2(0, -30), "life": 0.3, "col": H4_FOX, "sz": 9.0})
	o.fx({"kind": "ring", "pos": sz.att[0].e.pos, "r": r, "r0": r * 0.6, "life": 0.25, "col": H4_FOX, "floor": true, "w": 1.5, "alpha": 0.5})
	# 传火：每团附着体至多传一次，传给 r 内最近的一名未被附着的敌人
	for s2 in passes:
		if not sz.att.has(s2) or s2.e.dead:
			continue
		var best2 = null
		var bd2 := r
		for j in o.query_ids(s2.e.pos, r + 40.0):
			var q: Dictionary = g.enemies[j]
			if q.dead or q.get("chest", false) or is_same(q, s2.e):
				continue
			var taken := false
			for s3 in sz.att:
				if is_same(s3.e, q):
					taken = true
					break
			if taken:
				continue
			var dq: float = q.pos.distance_to(s2.e.pos) - q.r
			if dq < bd2:
				bd2 = dq
				best2 = q
		if best2 == null:
			continue
		s2.pass = false
		_h4_attach(o, at, best2, false)
		o.fx({"kind": "line", "pos": s2.e.pos + Vector2(0, -10), "to": best2.pos + Vector2(0, -10), "life": 0.25, "col": Color(2.0, 1.6, 0.8), "w": 3.0})
		o.fx({"kind": "glow", "pos": best2.pos + Vector2(0, -10), "r": 14.0, "life": 0.25, "col": H4_FOX, "alpha": 0.8})


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
	_h4_attach_tick(o, sz, a, dt)
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
		o.add_cc(e, -INF, slow, "stop")
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
				o.add_cc(e, -INF, 1.0, "stop")
			o.fx({"kind": "ring", "pos": e.pos, "r": 26.0, "r0": 6.0, "life": 0.22, "col": H4_FOX, "w": 2.5})
			_h3_vsparks(o, e.pos, H4_FOX, 4, 180.0, 0.3, 2.5)
			_h4_fox_hit(o, a, e)   # 精英化第 4 批（狐火灼印）的挂点
	sz.bigfox = sz.bigfox.filter(func(f): return f.life > 0.0)


## 精二「狐火拖尾」：大狐火飞过的路径每 step 留一处狐火（life 秒），同一条拖尾每 every 秒灼伤后来踩进路径的敌人一次（攻击 × mult，对精英 / Boss × vs_elite；
## 这团大狐火已经贯穿过的敌人不再烧，免得原地不动的单体被同一团狐火连烧几跳）
static func _h4_bigfox_path(o, sz: Dictionary, a: Dictionary, f: Dictionary) -> void:
	var tr: Dictionary = _h4_sub(o, a.get("merge", _ED).get("trail", null))
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
	var at: Dictionary = _h4_sub(o, a.get("attach", null))
	if not at.is_empty() and not e.dead:
		_h4_attach(o, at, e)
	var br: Dictionary = _h4_sub(o, a.get("brand", null))
	if not br.is_empty() and not e.dead:
		_h4_brand_apply(o, br, e)
	var sl = a.get("slow", null)   # 狐火命中轻减速（用户 10-29：开局自保）：{value, dur}，同一目标只刷新，Boss 不吃
	if sl is Dictionary and not e.dead:
		o.g.enemies_sys.lite_slow(e, float(sl.get("value", 0.2)), float(sl.get("dur", 0.8)))


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
		o.add_cc(best, st)
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
		o.SkillLifecycle.bind(o, "fox_haze", o.effect_skill, sz, "haze_t", true, false, func(): _h4_field_cancel(o))
		if o.cur_skill >= 0:
			o.s_dur[o.cur_skill] = float(b.haze)
	else:
		o.SkillLifecycle.bind(o, "fox_warm", o.effect_skill, o.perm_on, o.cur_skill, false, false, func(): _h4_field_cancel(o), "permanent")
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
	feather_ring(cv, r, H4_FOX, 0.6 if on else 0.35, g.t)   # 10-29：不填充，改内羽边 + 光点
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
	for s2 in sz.att:
		var ee: Dictionary = s2.e
		var fp: Vector2 = ee.pos + Vector2(0, -float(ee.r) * 1.2 + sin(g.t * 9.0 + float(ee.id)) * 1.5)
		var fa: float = clampf(float(s2.t) / 0.3, 0.0, 1.0)
		cv.draw_circle(fp + Vector2(0, -4), 11.0, Color(H4_FOX.r, H4_FOX.g, H4_FOX.b, 0.28 * fa))
		_h4_flame(o, fp, 15.0, fa)
		cv.draw_circle(fp + Vector2(0, -3), 2.5, Color(2.6, 2.4, 1.8, 0.9 * fa))
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
		pass
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
	var br: Dictionary = o.B.get("attack", _ED).get("brand", {})
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


static func _h4_field_cancel(o) -> void:
	o.g.stats.remove_source(_h4_field_src(o))
	o.refresh_stats()
