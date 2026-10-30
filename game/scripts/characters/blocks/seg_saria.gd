## 干员积木 · seg_saria（docs/101 §7.3 B6 ①，10-15：由 op_blocks.gd 按段拆出，内容与注释照搬；继承链与门面见 op_blocks.gd）
extends "res://scripts/characters/blocks/seg_wisadel.gd"


# ---------------------------------------------------------------- 塞雷娅段（第 4 批续，SA_TAGS）
#  shape.bash       持盾出拳（普攻，手动 A 类）：扇形 r × op_range、半角 half、kb、stun，判定原点 脚底 + (0, y)，伤害 = 攻击 × 加成；
#                   护服（verb.suit）满格时这一拳换成全方位冲击
#  verb.guard_ring  阻挡圈（放 trait 的 passive）：每 every 秒把队长周围 r × op_range 内的非 Boss 敌人推到圈外（kb / 精英 kb_elite）、减速 slow 秒
#  verb.calc_orbs   环绕钙晶（放 passive）：n_by 里第一条 cond 成立的 n 枚绕本干员转（半径 r、角速度 spin），撞到敌人 拳击 × mult（同一敌人 cd 秒一次）；
#                   shatter {cond, every, reach, regrow, mult, n, src}：钙质化以外每 every 秒击碎一枚，碎片飞向附近至多 n 名敌人，regrow 秒后长回
#  verb.saria_heal  为队长回复 pct × 最大生命 × 技能强度（低于 low_hp 时 × low_mult）；cleanse 清寒冷 / 束缚；hot {dur, pct}：之后每秒再回复；
#                   syringe {cond, n, mult, slow, range, speed, src}：同时朝附近敌人掷出注射器（拳击 × mult × 技能强度、减速）
#  verb.calc_field  钙质化：dur 秒以队长为心 r 的琥珀区域（每帧清寒冷 / 束缚、每秒回复 heal、区域内敌人减速 slow 秒 + aura_weak），每 shard_every 秒在区域里长出一根晶柱；
#                   shatter {cond, every, n, mult, src}：每 every 秒击碎一根晶柱，碎片飞向区域内敌人
#  verb.suit        莱茵充能护服（放 passive）：每 seg_t 秒充满一格（共 segs 格），满格后下一次出拳变为全方位冲击（半径 r，拳击 × mult、kb、stun）
#  成长节点（docs/202，10-29 去数值化）：calc_orbs.mark {cond, dur, r, mult, max, src} = 「晶簇」：环绕钙晶撞到敌人留下钙晶碎片 dur 秒，被留碎片的敌人再被拳击（含护服冲击）命中时碎片爆开（半径 r、拳击 × mult）；
#                   saria_heal.syringe.flow {cond, dur, pct, cap, src} = 「针剂·回流」：被注射器命中的敌人 dur 秒内受到的伤害 × pct 转为队长回复，每次「急救」至多最大生命 × cap
#  verb.amber_ring  瞬时（响应动作 docs/118 §4.2）：以队长为心升起一圈晶柱，参数同 verb.suit.pillars（n / r / sy / life / pr / wall / mult / cd / elite_push / arm / src），
#                   与精二晶柱环共用一个位置（新的升起时旧的碎掉）

static func _h4sa(o) -> Dictionary:
	var h := hw_st(o)
	if not h.has("sa"):
		h["sa"] = {"block_t": 0.0, "calc": 0.0, "calc_acc": 0.0, "shard_t": 0.0, "hot_t": 0.0, "hot_acc": 0.0, "hot_pct": 0.0,
			"orb_cd": {}, "orb_broken": {}, "shatter_t": 0.0, "pillars": [], "slots": [], "shots": [], "seg": 0, "seg_t": 0.0, "calc_b": {},
			"hot_name": "", "calc_name": "", "slowed": [], "crystals": [],
			"marks": {}, "flow": [], "flow_pool": {}, "flow_cast": 0}
	return h.sa


static func _h4_bash_dmg(o) -> float:
	return o.base(str(o.B.get("attack", _ED).get("atk_key", "atk")), 0.0) * o._dmg_bonus()


## 净化：清除队长的寒冷（寒霜层数，满层冻结也一起解开）与束缚；balance.json operators/<id>/cleanse = 0 关掉。show = 清掉了东西时在队长头顶飘「净化」
static func h4_cleanse_ctrl(o, show: bool) -> bool:
	var g = o.g
	if preload("res://scripts/core/balance.gd").v("operators/%s/cleanse" % o.id, 1.0) <= 0.0:
		return false
	if g.cold <= 0 and g.root_t <= 0.0:
		return false
	g.cold = 0
	g.cold_t = 0.0
	g.root_t = 0.0
	g.combat.sync_cold()
	if show:
		o.float_text(g.ppos + Vector2(0, -96), "净化", H4_AMBER, 14)
	return true


static func _h4_bash_start(o, a: Dictionary) -> void:
	if o.cd > 0.0:
		return
	var reach: float = float(a.get("r", 115.0)) * o.stat(&"op_range")
	var at: Vector2 = o.atk_point(o.nearest_enemies(1, reach + 40.0, o.pos), reach)   # 按住瞄准 A 类（契约 v2.5）
	if at == Vector2.INF:
		o.cd = float(a.get("idle", 0.1))
	else:
		o.cd = float(a.get("every", 0.9)) / o.stat(&"op_aspd")
		o.start_attack(at, 0.5, 0.25, "", o.cd)


static func _h4_bash_release(o, a: Dictionary) -> void:
	var g = o.g
	var sa := _h4sa(o)
	var reach: float = float(a.get("r", 115.0)) * o.stat(&"op_range")
	var ts: Array = o.nearest_enemies(1, reach + 40.0, o.pos)
	var ang: float = o.facing_angle()
	if not ts.is_empty():
		ang = (ts[0].pos - o.pos).angle()
		o.face_to(ang)
	ang = o.atk_angle(ang)
	# 莱茵充能护服满格：这一击变成全方位冲击，之后清零重新充能
	var su: Dictionary = _h4_live(o, "verb.suit")
	if not su.is_empty() and int(sa.seg) >= int(su.get("segs", 4)):
		sa.seg = 0
		sa.seg_t = 0.0
		_h4_suit_blast(o, a, su)
		return
	var hits: Array = o.melee_hit(str(a.get("src", "")), o.pos + Vector2(0, float(a.get("y", -10.0))), ang, float(a.get("half", 1.1)), reach, _h4_bash_dmg(o), float(a.get("kb", 200.0)), float(a.get("stun", 0.2)), a.get("tags", []))
	_h4_marks_pop(o, hits, _h4_bash_dmg(o))   # 晶簇（docs/202）：被拳击命中的带碎片敌人，碎片爆开
	var d := Vector2.from_angle(ang)
	var fk: float = reach / maxf(1.0, float(a.get("r", 115.0)))   # 盾击帧条跟判定半径走（范围藏品放大判定时一起放大，163B §3）
	if not o.spawn_fx_sprite("fx_saria_shield_bash", o.pos + Vector2(0, -12) + d * (14.0 + 20.0 * g.PX * 0.9) * fk, g.PX * 0.9 * fk, ang):
		o.slash_fx(o.pos + Vector2(0, -14), ang, 1.0, reach * 0.8, H4_AMBER)
		o.fx({"kind": "line", "pos": o.pos + Vector2(0, -12) + d * 14.0, "to": o.pos + Vector2(0, -12) + d * reach * 1.3, "life": 0.15, "col": H4_AMBER, "w": 3.0})
	_h3_sfx(o, "hit" if not hits.is_empty() else "atk")
	_h4_bash_after(o, a, hits)   # 精英化第 4 批（钙化拳）的挂点；迁移时没有


## 精一「钙化拳」（docs/91 §10）：拳击命中的非 Boss 敌人 dur 秒内移速 -pct（精英时长 × elite_mult；同一敌人刷新时长取长）。
## 不是减速状态（不写 e.slow、不与其他减速叠）：本干员每帧把这名敌人这一帧朝队长走近的位移退回 pct（被推开 / 击退不打折），同 st.slow_soft 的做法
static func _h4_bash_after(o, a: Dictionary, hits: Array) -> void:
	var cf: Dictionary = _h4_sub(o, a.get("calcify", null))
	if cf.is_empty():
		return
	var g = o.g
	var sa := _h4sa(o)
	for e in hits:
		if e.dead or e.boss:
			continue
		var dur: float = float(cf.get("dur", 2.0)) * (float(cf.get("elite_mult", 0.5)) if e.elite else 1.0)
		var found := false
		for s in sa.slowed:
			if is_same(s.e, e):
				s.until = maxf(float(s.until), g.t + dur)
				s.t0 = g.t
				found = true
				break
		if not found:
			if sa.slowed.size() >= int(cf.get("max", 48)):
				sa.slowed.pop_front()
			sa.slowed.append({"e": e, "until": g.t + dur, "last": e.pos, "t0": g.t, "seed": float(e.id) * 1.37})


## 莱茵充能护服：以自身为中心的全方位冲击；六道琥珀冲击向外撞出 + 两道贴地冲击环
static func _h4_suit_blast(o, a: Dictionary, su: Dictionary) -> void:
	var r: float = float(su.get("r", 110.0)) * o.stat(&"op_range")   # 范围藏品同样放大满格冲击（判定与六道冲击 / 环一起）
	var hits: Array = o.melee_hit(str(a.get("src", "")), o.pos + Vector2(0, -6), 0.0, PI, r, _h4_bash_dmg(o) * float(su.get("mult", 1.8)), float(su.get("kb", 320.0)), float(su.get("stun", 0.3)), su.get("tags", ["empowered"]))
	_h4_marks_pop(o, hits, _h4_bash_dmg(o))
	for k in 6:
		o.fx({"kind": "h4_bash", "pos": o.pos + Vector2(0, -14), "ang": k * TAU / 6.0, "reach": r * 0.8, "life": 0.26, "big": true})
	o.fx({"kind": "ring", "pos": o.pos, "r": r, "r0": 16.0, "life": 0.35, "col": H4_AMBER, "floor": true, "w": 4.0})
	o.fx({"kind": "ring", "pos": o.pos, "r": r * 0.7, "r0": 8.0, "life": 0.45, "col": Color(1.6, 1.3, 0.8), "floor": true, "w": 2.0})
	o.fx({"kind": "glow", "pos": o.pos + Vector2(0, -26), "r": 26.0, "life": 0.25, "col": H4_AMBER, "alpha": 0.6})
	_h3_vsparks(o, o.pos + Vector2(0, -16), H4_AMBER, 12, 260.0, 0.4, 2.5, 160.0)
	if not hits.is_empty():
		o.impact_pause(0.05)
	_h3_sfx(o, "hit", 4.0, 0.8)
	_h4_suit_after(o, su)   # 精英化第 4 批（晶柱环）的挂点；迁移时没有


## 精二「晶柱环」（docs/91 §10）：满格冲击后在 r 处（地面椭圆，y × sy）升起 n 根琥珀晶柱 life 秒，柱间连成一圈看不见的墙
static func _h4_suit_after(o, su: Dictionary) -> void:
	var pc: Dictionary = _h4_sub(o, su.get("pillars", null))
	if pc.is_empty() or o.pos == Vector2.INF:
		return
	_h4_pillars_raise(o, pc, o.pos)


## 响应动作（verb.amber_ring）：以队长为心升起晶柱环
static func h4_amber_ring(o, b: Dictionary) -> void:
	if o.pos == Vector2.INF:
		return
	_h4_pillars_raise(o, b, o.g.ppos)


static func _h4_pillars_raise(o, pc: Dictionary, c: Vector2) -> void:
	var sa := _h4sa(o)
	if not sa.crystals.is_empty():
		_h4_pillars_break(o, sa.crystals)
	var n: int = int(pc.get("n", 6))
	var R: float = float(pc.get("r", 110.0))
	var sy: float = float(pc.get("sy", 0.55))
	var posts: Array = []
	for k in n:
		var an: float = float(pc.get("a0", 0.0)) + k * TAU / n
		posts.append(c + Vector2(cos(an) * R, sin(an) * R * sy))
	sa.crystals = {"c": c, "t": 0.0, "life": float(pc.get("life", 2.0)), "posts": posts, "hit": {}, "b": pc}
	_h3_sfx(o, "hit", -2.0, 1.25)


static func _h4_pillars_break(o, cr: Dictionary) -> void:
	var g = o.g
	for p in cr.posts:
		if not o.spawn_fx_sprite("fx_saria_pillar_break", p + Vector2(0, -30), g.PX):
			o.spawn_fx_sprite("fx_rock_burst", p, g.PX * 0.7, 0.0, false, false, Color(1.3, 1.0, 0.6))
			for q in 4:
				o.fx({"kind": "shard", "pos": p + Vector2(0, -24), "vel": Vector2.from_angle(g.vrng.randf() * TAU) * g.vrng.randf_range(70, 140), "life": 0.3, "col": H4_AMBER,
					"sz": g.vrng.randf_range(2.5, 4.0), "ang": g.vrng.randf() * TAU, "spin": g.vrng.randf_range(-14, 14), "grav": 260.0})


static func _h4sa_tick(o, sa: Dictionary, dt: float) -> void:
	var g = o.g
	# 阻挡圈：每 every 秒把队长周围的非 Boss 敌人推到圈外、减速
	var gr: Dictionary = _h4_live(o, "verb.guard_ring")
	if not gr.is_empty():
		sa.block_t = float(sa.block_t) - dt
		if float(sa.block_t) <= 0.0:
			sa.block_t = float(gr.get("every", 0.25))
			var r: float = float(gr.get("r", 62.0)) * o.stat(&"op_range")
			var shown := 0
			for j in o.query_ids(g.ppos, r + 30.0):
				var e: Dictionary = g.enemies[j]
				if e.dead or e.boss or e.chest:
					continue
				var off: Vector2 = e.pos - g.ppos
				if off.length() > r + e.r:
					continue
				o.apply_kb(e, off.normalized() * (float(gr.get("kb_elite", 80.0)) if e.elite else float(gr.get("kb", 200.0))))
				o.add_cc(e, -INF, float(gr.get("slow", 0.5)))
				if shown < 4:
					shown += 1
					o.fx({"kind": "glow", "pos": e.pos, "r": 9.0, "life": 0.18, "col": H4_AMBER, "alpha": 0.5, "floor": true})
	var ob: Dictionary = _h4_live(o, "verb.calc_orbs")
	var orb_n: int = _h4_orb_n(o, ob)
	_h4_orbs_tick(o, sa, ob, orb_n, dt)
	_h4_shots_tick(o, sa, dt)
	_h4_marks_tick(o, sa)
	_h4_flow_tick(o, sa)
	# 精二 莱茵充能护服：每 seg_t 秒充满一格，满格后等下一次出拳放出
	var su: Dictionary = _h4_live(o, "verb.suit")
	if not su.is_empty() and int(sa.seg) < int(su.get("segs", 4)):
		sa.seg_t = float(sa.seg_t) + dt
		if float(sa.seg_t) >= float(su.get("seg_t", 5.0)):
			sa.seg_t = 0.0
			sa.seg = int(sa.seg) + 1
			o.fx({"kind": "glow", "pos": o.pos + Vector2(-19.5 + (int(sa.seg) - 1) * 13.0, 14), "r": 6.0, "life": 0.25, "col": H4_AMBER, "alpha": 0.7})
	if float(sa.hot_t) > 0.0:
		sa.hot_t = float(sa.hot_t) - dt
		sa.hot_acc = float(sa.hot_acc) + dt
		if float(sa.hot_acc) >= 1.0:
			sa.hot_acc = float(sa.hot_acc) - 1.0
			if g.hp < g.max_hp:
				o.heal_leader(g.max_hp * float(sa.hot_pct), o.display_name())
				o.fx({"kind": "mote", "pos": g.ppos + Vector2(g.vrng.randf_range(-16, 16), -20), "vel": Vector2(0, -35), "life": 0.7, "col": H4_AMBER, "sz": 2.0})
	var shb: Dictionary = _h4_sub(o, ob.get("shatter", null)) if not ob.is_empty() else {}
	if float(sa.calc) > 0.0:
		var cb: Dictionary = sa.calc_b
		var R: float = float(cb.get("r", 180.0))
		sa.calc = float(sa.calc) - dt
		sa.calc_acc = float(sa.calc_acc) + dt
		h4_cleanse_ctrl(o, false)   # 钙质化区域（跟着队长）里持续清除寒冷、束缚
		if float(sa.calc_acc) >= 1.0:
			sa.calc_acc = float(sa.calc_acc) - 1.0
			if g.hp < g.max_hp:
				o.heal_leader(g.max_hp * float(cb.get("heal", 0.01275)), o.display_name())
		for j in o.query_ids(g.ppos, R + 20.0):
			var e2: Dictionary = g.enemies[j]
			if e2.dead or e2.pos.distance_to(g.ppos) > R:
				continue
			o.add_cc(e2, -INF, float(cb.get("slow", 0.5)))
			e2["aura_weak"] = maxf(float(e2.get("aura_weak", 0.0)), float(cb.get("weak", 0.2)))
		if not sa.slots.is_empty():
			_h4_slots_tick(o, sa, cb, dt)   # 10-29 用户：晶体碰到怪物会碎、过一会原位重新长出
		else:
			sa.shard_t = float(sa.shard_t) - dt
			if float(sa.shard_t) <= 0.0:
				sa.shard_t = float(cb.get("shard_every", 0.35))
				var an: float = g.rng_op.randf() * TAU   # 晶柱落点吃 g.rng（碎晶从晶柱处射出，影响玩法；同手写）
				var rr: float = g.rng_op.randf_range(R * 0.3, R * 0.95)
				_h4_calcite(o, g.ppos + Vector2(cos(an) * rr, sin(an) * rr * 0.55 + 4.0), g.vrng.randf_range(0.6, 0.85), g.vrng.randf_range(12, 24), 1.2)
		# 碎晶：每 every 秒亲手击碎一根晶柱，碎片飞向区域内的敌人
		var cs: Dictionary = _h4_sub(o, cb.get("shatter", null))
		if not cs.is_empty():
			sa.shatter_t = float(sa.shatter_t) - dt
			if float(sa.shatter_t) <= 0.0 and _h4_shatter(o, sa, cb, cs):
				sa.shatter_t = float(cs.get("every", 1.2))
	else:
		sa.pillars.clear()
		# 碎晶（平时）：每 every 秒击碎一枚环绕钙晶，碎片飞向附近敌人，regrow 秒后重新长出
		if not shb.is_empty() and orb_n > 0:
			sa.shatter_t = float(sa.shatter_t) - dt
			if float(sa.shatter_t) <= 0.0 and _h4_shatter_orb(o, sa, ob, shb, orb_n):
				sa.shatter_t = float(shb.get("every", 3.0))
	_h4sa_tick_e(o, sa, dt)   # 精英化第 4 批（钙化拳减速 / 晶柱环）的挂点；迁移时没有


static func _h4sa_tick_e(o, sa: Dictionary, dt: float) -> void:
	var g = o.g
	if not sa.slowed.is_empty():
		var cf: Dictionary = _h4_sub(o, o.B.get("attack", _ED).get("calcify", null))
		var pct: float = float(cf.get("pct", 0.15)) if not cf.is_empty() else 0.0
		for s in sa.slowed:
			var e: Dictionary = s.e
			if e.dead or g.t >= float(s.until):
				continue
			var d: Vector2 = e.pos - s.last
			if pct > 0.0 and d.dot(g.ppos - s.last) > 0.0:
				e.pos -= d * pct
			s.last = e.pos
		sa.slowed = sa.slowed.filter(func(s): return not s.e.dead and g.t < float(s.until))
	if not sa.crystals.is_empty():
		_h4_pillars_tick(o, sa, dt)


static var _h4_pperf = null   # --pillarperf（只计时、不改玩法）：[开着晶柱的帧数, 总微秒, 单帧最大微秒, 查到的敌人数合计]


## 晶柱环每帧：敌人碰到柱子或柱间的墙就沿法线推出去（精英一帧至多推回 elite_push × 自身移速 × dt，所以能慢慢挤过去；Boss / 定点单位不挡，队长和队友不受影响），
## 碰到的敌人受到拳击 × mult（同一敌人 cd 秒一次）。只查环心 r + pr + 40 内的敌人（空间网格），按椭圆环带快速剔除，剩下的每名只算所在扇区的一段墙与两根柱子
static func _h4_pillars_tick(o, sa: Dictionary, dt: float) -> void:
	var g = o.g
	var cr: Dictionary = sa.crystals
	cr.t = float(cr.t) + dt
	var pc: Dictionary = cr.b
	if float(cr.t) >= float(cr.life):
		_h4_pillars_break(o, cr)
		sa.crystals = {}
		return
	if float(cr.t) < float(pc.get("arm", 0.08)):   # 拔起 arm 秒后才挡（10-15 起 --perfab 的 /b 桶也照常挡：量帧开关只许影响绘制，docs/101 S4）
		return
	if _h4_pperf == null:
		_h4_pperf = [0, 0, 0, 0] if OS.is_debug_build() and OS.get_cmdline_user_args().has("--pillarperf") else []
	var perf: bool = not _h4_pperf.is_empty()
	var t0: int = Time.get_ticks_usec() if perf else 0
	var posts: Array = cr.posts
	var n: int = posts.size()
	var pr: float = float(pc.get("pr", 14.0))
	var hw: float = float(pc.get("wall", 6.0))
	var c: Vector2 = cr.c
	var R: float = float(pc.get("r", 110.0))
	var sy: float = float(pc.get("sy", 0.55))
	var ek: float = float(pc.get("elite_push", 0.5))
	var band: float = pr + 30.0
	var a0: float = float(pc.get("a0", 0.0))
	var sec: float = TAU / float(n)
	var hits: Array = []
	var ids: Array = o.query_ids(c, R + pr + 40.0)
	var ens: Array = g.enemies
	var rsy: float = R * sy
	for j in ids:
		var e: Dictionary = ens[j]
		if e.dead:
			continue
		var ep: Vector2 = e.pos
		var er: float = e.r
		var rel: Vector2 = ep - c
		var nx: float = rel.x / R
		var ny: float = rel.y / rsy
		if absf(sqrt(nx * nx + ny * ny) - 1.0) * rsy > band + er:   # 离环带太远（椭圆归一化半径，按短轴折回像素，偏宽松）
			continue
		if e.boss or e.ai == "static" or e.get("chest", false):
			continue
		# 只查这名敌人所在扇区的那一段墙与两端的柱子（椭圆归一化后的方位角；跨扇区的拐角由共用的柱子兜住）
		var k: int = posmod(int(floor((atan2(ny, nx) - a0) / sec)), n)
		var a2: Vector2 = posts[k]
		var b2: Vector2 = posts[(k + 1) % n]
		var push := Vector2.ZERO
		var best := 0.0
		var dp: Vector2 = ep - a2
		var lp: float = dp.length()
		var ov: float = pr + er - lp
		if ov > best:
			best = ov
			push = (dp / lp if lp > 0.01 else rel.normalized()) * ov
		var dq: Vector2 = ep - b2
		var lq: float = dq.length()
		ov = pr + er - lq
		if ov > best:
			best = ov
			push = (dq / lq if lq > 0.01 else rel.normalized()) * ov
		if hw >= 0.0:   # wall < 0 = 只有柱子、柱间不挡
			var ab: Vector2 = b2 - a2
			var dw: Vector2 = ep - (a2 + ab * clampf(dp.dot(ab) / ab.length_squared(), 0.0, 1.0))
			var lw: float = dw.length()
			ov = hw + er - lw
			if ov > best:
				best = ov
				push = (dw / lw if lw > 0.01 else rel.normalized()) * ov
		if best <= 0.0:
			continue
		if e.elite:
			push = push.limit_length(ek * float(e.spd) * dt)
		e.pos = ep + push
		hits.append(e)
	var dmg: float = _h4_bash_dmg(o) * float(pc.get("mult", 0.2))
	var hcd: float = float(pc.get("cd", 0.5))
	var hd: Dictionary = cr.hit
	for e in hits:
		if e.dead or float(hd.get(e.id, -1.0)) > g.t:
			continue
		hd[e.id] = g.t + hcd
		o.log_hit(str(pc.get("src", "")))
		o.deal_damage(e, dmg * (o.vs_elite() if e.elite else 1.0))
		o.fx({"kind": "glow", "pos": e.pos + Vector2(0, -float(e.r) * 0.5), "r": 8.0, "life": 0.14, "col": H4_AMBER, "alpha": 0.55})
	if perf:
		var us: int = Time.get_ticks_usec() - t0
		_h4_pperf[0] += 1
		_h4_pperf[1] += us
		_h4_pperf[2] = maxi(int(_h4_pperf[2]), us)
		_h4_pperf[3] += ids.size()
		if int(_h4_pperf[0]) % 600 == 0:
			print("PILLAR_PERF frames=%d total_us=%d avg_us=%.1f max_us=%d avg_checked=%.1f enemies=%d" % [_h4_pperf[0], _h4_pperf[1], float(_h4_pperf[1]) / _h4_pperf[0], _h4_pperf[2], float(_h4_pperf[3]) / _h4_pperf[0], g.enemies.size()])


## 晶柱参与 2.5D 排序（data_operator.extra_bodies 转来）
static func h4_extra_bodies(o) -> Array:
	if not hw_on(o) or not o.hw.has("sa"):
		return []
	var out: Array = []
	var sa: Dictionary = o.hw.sa
	if not sa.crystals.is_empty():
		var posts: Array = sa.crystals.posts
		for k in posts.size():
			out.append({"y": (posts[k] as Vector2).y, "h4": "pillar", "k": k})
	for k in sa.slots.size():   # 钙质化的固定晶柱槽（空着等重新长出的不画）
		var sl: Dictionary = sa.slots[k]
		if int(sl.st) < 3 and float(sl.t) >= 0.0:
			out.append({"y": (sl.pos as Vector2).y, "h4": "calc", "k": k})
	return out


## 一根晶柱：拔起帧条播完转站立微光循环（Codex fx_saria_pillar_rise / _idle，底边中点落地）；缺图画程序琥珀晶柱（拔起 0.15 秒，缩放 0 → 1）
static func h4_draw_extra(o, it: Dictionary) -> void:
	var g = o.g
	var cv = o.cv
	if str(it.h4) == "calc":
		var sl: Dictionary = o.hw.sa.slots[int(it.k)]
		var t: float = float(sl.t)
		var fr: int
		match int(sl.st):
			0:
				fr = mini(3, int(t / SLOT_GROW * 4.0))
			1:
				fr = 4
			_:
				fr = mini(7, 5 + int(t / SLOT_BREAK * 3.0))
		var sc: float = g.PX * float(sl.sc) * (-1.0 if sl.flip else 1.0)
		fx_frame(cv, g, "fx_saria_calcite", 8, fr, sl.pos, absf(sc), Color(1, 1, 1, 1), Vector2(16, 40))
		return
	var cr: Dictionary = o.hw.sa.crystals
	if cr.is_empty():
		return
	var p: Vector2 = cr.posts[int(it.k)]
	var t: float = float(cr.t)
	var fade: float = clampf((float(cr.life) - t) / 0.12, 0.0, 1.0)
	var col := Color(1, 1, 1, fade)
	var rise_n: int = int(g.V6_FRAMES.get("fx_saria_pillar_rise", [5, 20.0])[0])
	var rise_fps: float = float(g.V6_FRAMES.get("fx_saria_pillar_rise", [5, 20.0])[1])
	if g.tex.get("fx_saria_pillar_rise") != null and t < rise_n / rise_fps:
		fx_frame(cv, g, "fx_saria_pillar_rise", rise_n, int(t * rise_fps), p, g.PX, col, Vector2(8, 32))
		return
	if g.tex.get("fx_saria_pillar_idle") != null:
		var idle: Array = g.V6_FRAMES.get("fx_saria_pillar_idle", [4, 6.0])
		fx_frame(cv, g, "fx_saria_pillar_idle", int(idle[0]), int((t + float(it.k) * 0.13) * float(idle[1])), p, g.PX, col, Vector2(8, 32))
		return
	var grow: float = clampf(t / 0.15, 0.0, 1.0)
	var h: float = 30.0 * (1.0 - (1.0 - grow) * (1.0 - grow))
	var top: Vector2 = p + Vector2(0, -h)
	cv.draw_colored_polygon(PackedVector2Array([p + Vector2(-7, 0), top + Vector2(-3, 4), top, top + Vector2(3, 4), p + Vector2(7, 0), p + Vector2(0, 4)]), Color(H4_AMBER.r, H4_AMBER.g, H4_AMBER.b, 0.9 * fade))
	cv.draw_line(p + Vector2(-4, -1), top + Vector2(-1, 3), Color(1.9, 1.6, 1.0, 0.9 * fade), 1.5)
	cv.draw_circle(top, 2.0, Color(2.2, 2.0, 1.4, fade))


static func _h4_orb_n(o, ob: Dictionary) -> int:
	if ob.is_empty():
		return 0
	for m in ob.get("n_by", _EA):
		if m is Dictionary and cond_true(o, m.get("cond", _ED)):
			return int(m.get("n", 0))
	return 0


## 环绕钙晶的地面位置：绕本干员一圈（判定用真实圆，不做贴地压扁）
static func _h4_orb_ground(o, ob: Dictionary, orb_n: int, k: int) -> Vector2:
	var an: float = o.g.t * float(ob.get("spin", 2.2)) + k * TAU / float(maxi(1, orb_n))
	var R: float = float(ob.get("r", 70.0))
	return o.pos + Vector2(cos(an) * R, sin(an) * R + 2.0)


static func _h4_orbs_tick(o, sa: Dictionary, ob: Dictionary, orb_n: int, dt: float) -> void:
	if orb_n <= 0 or o.pos == Vector2.INF:
		return
	var g = o.g
	var cdd: Dictionary = sa.orb_cd
	for k in cdd.keys():
		cdd[k] -= dt
		if cdd[k] <= 0.0:
			cdd.erase(k)
	var dmg: float = _h4_bash_dmg(o) * float(ob.get("mult", 0.18))
	var mk: Dictionary = _h4_sub(o, ob.get("mark", null))   # 晶簇（docs/202）
	var mk_on: bool = not mk.is_empty()
	var br: Dictionary = sa.orb_broken
	for k in br.keys():
		br[k] -= dt
		if br[k] <= 0.0:
			br.erase(k)
	for k in orb_n:
		if br.has(k):
			continue
		var p: Vector2 = _h4_orb_ground(o, ob, orb_n, k)
		for j in o.query_ids(p, 40.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or cdd.has(e.id) or e.pos.distance_to(p) > 12.0 + e.r:
				continue
			cdd[e.id] = float(ob.get("cd", 0.5))
			o.log_hit(str(ob.get("src", "")))
			o.deal_damage(e, dmg)
			o.fx({"kind": "glow", "pos": p + Vector2(0, -16), "r": 7.0, "life": 0.14, "col": H4_AMBER, "alpha": 0.6})
			o.fx({"kind": "shard", "pos": p + Vector2(0, -16), "vel": Vector2.from_angle(g.vrng.randf() * TAU) * 90.0, "life": 0.22, "col": H4_AMBER, "sz": 3.0, "ang": g.vrng.randf() * TAU, "spin": 12.0})
			if mk_on and not e.dead:
				_h4_mark_set(o, mk, e)


## 投射物：直线飞行，碰到第一个敌人即命中；注射器附带减速
static func _h4_shoot(o, sa: Dictionary, kind: String, from: Vector2, to: Vector2, spd: float, dmg: float, src: String, slow := 0.0, flow := {}, cast := 0) -> void:
	if sa.shots.size() >= 12:
		return
	var d: Vector2 = (to - from).normalized() if to.distance_to(from) > 1.0 else Vector2(o.face, 0)
	sa.shots.append({"kind": kind, "pos": from, "vel": d * spd, "t": 0.7, "dmg": dmg, "ang": d.angle(), "src": src, "slow": slow, "flow": flow, "cast": cast})


static func _h4_shots_tick(o, sa: Dictionary, dt: float) -> void:
	if sa.shots.is_empty():
		return
	var g = o.g
	for s in sa.shots:
		s.t -= dt
		s.pos += s.vel * dt
		var gp: Vector2 = s.pos + Vector2(0, 16)   # 投射物飞在腰高（-16），按地面位置判定
		if g.map.tb_bul and g.map.bullet_blocked(s, gp):   # 地形阻挡：针剂 / 碎晶撞景物底座即消失
			s.t = 0.0
			continue
		for j in o.query_ids(gp, 36.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or e.pos.distance_to(gp) > 6.0 + e.r:
				continue
			o.log_hit(str(s.src))
			o.deal_damage(e, s.dmg)
			if s.kind == "syringe":
				if not e.dead:
					o.add_cc(e, -INF, float(s.slow))
					if not s.flow.is_empty():
						_h4_flow_tag(o, s.flow, e, int(s.cast))
				o.fx({"kind": "glow", "pos": s.pos, "r": 7.0, "life": 0.18, "col": Color(0.7, 1.2, 0.9), "alpha": 0.6})
			else:
				o.fx({"kind": "glow", "pos": s.pos, "r": 8.0, "life": 0.16, "col": H4_AMBER, "alpha": 0.6})
				for q in 3:
					o.fx({"kind": "shard", "pos": s.pos, "vel": Vector2.from_angle(g.vrng.randf() * TAU) * 110.0, "life": 0.25, "col": H4_AMBER, "sz": 2.5, "ang": g.vrng.randf() * TAU, "spin": 14.0})
			s.t = 0.0
			break
	sa.shots = sa.shots.filter(func(s): return s.t > 0.0)


## 2 晶簇（docs/202）：环绕钙晶撞到敌人时留下钙晶碎片 dur 秒（至多 max 处，同一敌人只刷新）
static func _h4_mark_set(o, mk: Dictionary, e: Dictionary) -> void:
	var sa := _h4sa(o)
	var m: Dictionary = sa.marks
	if not m.has(e.id) and m.size() >= int(mk.get("max", 24)):
		return
	m[e.id] = {"e": e, "until": o.g.t + float(mk.get("dur", 2.0)), "b": mk}


## 被拳击命中的带碎片敌人：碎片爆开（半径 r、拳击 × mult，不吃刀光弧），每个碎片只爆一次
static func _h4_marks_pop(o, hits: Array, dmg: float) -> void:
	var sa := _h4sa(o)
	if sa.marks.is_empty():
		return
	for e in hits:
		var m = sa.marks.get(e.id, null)
		if m == null or not is_same(m.e, e):
			continue
		sa.marks.erase(e.id)
		_h4_mark_burst(o, m.b, e.pos, dmg)


static func _h4_mark_burst(o, mk: Dictionary, p: Vector2, dmg: float) -> void:
	var g = o.g
	var r: float = float(mk.get("r", 50.0)) * o.stat(&"op_range")
	var d: float = dmg * float(mk.get("mult", 0.4))
	for j in o.query_ids(p, r + 30.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or e.pos.distance_to(p) > r + e.r:
			continue
		o.log_hit(str(mk.get("src", "")))
		o.deal_damage(e, d * (o.vs_elite() if e.elite or e.boss else 1.0))
	o.fx({"kind": "ring", "pos": p, "r": r, "r0": 8.0, "life": 0.28, "col": H4_AMBER, "floor": true, "w": 2.5})
	o.fx({"kind": "glow", "pos": p + Vector2(0, -12), "r": 14.0, "life": 0.2, "col": Color(1.9, 1.5, 0.9), "alpha": 0.8})
	for q in 7:
		o.fx({"kind": "shard", "pos": p + Vector2(0, -12), "vel": Vector2.from_angle(g.vrng.randf() * TAU) * g.vrng.randf_range(90, 180), "life": 0.3, "col": H4_AMBER,
			"sz": g.vrng.randf_range(2.5, 4.0), "ang": g.vrng.randf() * TAU, "spin": g.vrng.randf_range(-14, 14), "grav": 240.0})


static func _h4_marks_tick(o, sa: Dictionary) -> void:
	if sa.marks.is_empty():
		return
	var t: float = o.g.t
	for id in sa.marks.keys():
		var m: Dictionary = sa.marks[id]
		if m.e.dead or t >= float(m.until):
			sa.marks.erase(id)


## 5A 针剂·回流（docs/202）：注射器命中的敌人 dur 秒内，受到的伤害（逐帧比对生命的减少量）× pct 转为队长回复；同一次急救的回复合计至多最大生命 × cap
static func _h4_flow_tag(o, fl: Dictionary, e: Dictionary, cast: int) -> void:
	var sa := _h4sa(o)
	var until: float = o.g.t + float(fl.get("dur", 4.0))
	for f in sa.flow:
		if is_same(f.e, e):
			f.until = maxf(float(f.until), until)
			return
	if sa.flow.size() >= 12:
		sa.flow.pop_front()
	sa.flow.append({"e": e, "until": until, "hp": float(e.hp), "cast": cast, "b": fl})


static func _h4_flow_tick(o, sa: Dictionary) -> void:
	if sa.flow.is_empty():
		return
	var g = o.g
	for f in sa.flow:
		var e: Dictionary = f.e
		var hp: float = maxf(0.0, float(e.hp))
		var lost: float = float(f.hp) - hp
		f.hp = hp
		if lost <= 0.0 or g.hp >= g.max_hp:
			continue
		var b: Dictionary = f.b
		var pool: float = float(sa.flow_pool.get(f.cast, 0.0))
		var room: float = g.max_hp * float(b.get("cap", 0.03)) - pool
		var h: float = minf(lost * float(b.get("pct", 0.08)), room)
		if h <= 0.0:
			continue
		sa.flow_pool[f.cast] = pool + h
		o.heal_leader(h, str(b.get("src", "针剂回流")))
		var from: Vector2 = e.pos + Vector2(0, -float(e.r) * 0.6)
		var to: Vector2 = g.ppos + Vector2(0, -30)
		o.fx({"kind": "mote", "pos": from, "vel": (to - from) / 0.4, "life": 0.4, "col": Color(0.7, 1.4, 0.9), "sz": 2.5})
	sa.flow = sa.flow.filter(func(f): return not f.e.dead and g.t < float(f.until))
	if sa.flow_pool.size() > 6:
		var ks: Array = sa.flow_pool.keys()
		ks.sort()
		for k in ks.slice(0, ks.size() - 4):
			sa.flow_pool.erase(k)


## 钙质晶体（Codex：冷白主体 + 琥珀边，从地面长出 → 停留 → 碎裂）；缺图退回程序琥珀晶柱。返回该晶柱的特效条目
static func _h4_calcite(o, p: Vector2, sc: float, h: float, life: float) -> Dictionary:
	var g = o.g
	var sa := _h4sa(o)
	var ref: Dictionary = {}
	if o.spawn_fx_sprite("fx_saria_calcite", p, g.PX * sc, 0.0, g.vrng.randf() < 0.5, true):
		ref = g.fx.back()
	else:
		o.fx({"kind": "h4_crystal", "pos": p, "h": h, "life": life, "col": H4_AMBER, "lean": g.vrng.randf_range(-0.3, 0.3)})
		ref = o.pfx.back()
	# 碎晶：钙质化期间记下长出的晶柱，供击碎
	if float(sa.calc) > 0.0 and not _h4_sub(o, sa.calc_b.get("shatter", null)).is_empty():
		sa.pillars.append({"pos": p, "ref": ref})
		if sa.pillars.size() > 12:
			sa.pillars.pop_front()
	return ref


## 碎晶：挑一根已长成的晶柱击碎（g.rng，同手写），碎片飞向区域内最近的至多 n 名敌人；没有目标就先不碎
static func _h4_shatter(o, sa: Dictionary, cb: Dictionary, cs: Dictionary) -> bool:
	var g = o.g
	sa.pillars = sa.pillars.filter(func(pl): return pl.ref.get("life", 0.0) > 0.25)
	if sa.pillars.is_empty():
		return false
	var pl: Dictionary = sa.pillars[g.rng_op.randi() % sa.pillars.size()]
	var p: Vector2 = pl.pos
	var R: float = float(cb.get("r", 180.0))
	var ts: Array = o.nearest_enemies(8, R * 2.0, p).filter(func(e): return e.pos.distance_to(g.ppos) <= R + e.r)
	if ts.is_empty():
		return false
	ts = o.los_sort(ts, ts.size(), p)   # 地形阻挡：碎片是直线弹，视线内的先
	sa.pillars.erase(pl)
	pl.ref.life = 0.001
	o.fx({"kind": "glow", "pos": p + Vector2(0, -18), "r": 16.0, "life": 0.22, "col": Color(1.8, 1.4, 0.8), "alpha": 0.8})
	o.fx({"kind": "ring", "pos": p, "r": 26.0, "r0": 4.0, "life": 0.25, "col": H4_AMBER, "floor": true, "w": 2.0})
	for q in 8:
		o.fx({"kind": "shard", "pos": p + Vector2(0, -16), "vel": Vector2.from_angle(g.vrng.randf() * TAU) * g.vrng.randf_range(80, 170), "life": 0.35, "col": H4_AMBER,
			"sz": g.vrng.randf_range(3.0, 5.0), "ang": g.vrng.randf() * TAU, "spin": g.vrng.randf_range(-14, 14), "grav": 260.0})
	var dmg: float = _h4_bash_dmg(o) * float(cs.get("mult", 0.6)) * o.skill_power()
	for k in mini(int(cs.get("n", 4)), ts.size()):
		_h4_shoot(o, sa, "shard", p + Vector2(0, -16), ts[k].pos + Vector2(0, -16), 560.0, dmg, str(cs.get("src", "")))
	_h3_sfx(o, "hit", -2.0, 1.3)
	return true


## 碎晶（平时）：挑离最近敌人最近的一枚完好钙晶击碎，碎片飞向附近至多 n 名敌人；没有目标就先不碎
static func _h4_shatter_orb(o, sa: Dictionary, ob: Dictionary, shb: Dictionary, orb_n: int) -> bool:
	var g = o.g
	var ts: Array = o.nearest_enemies(6, float(shb.get("reach", 260.0)), o.pos)
	if ts.is_empty():
		return false
	var best := -1
	var bd := INF
	for k in orb_n:
		if sa.orb_broken.has(k):
			continue
		var d: float = _h4_orb_ground(o, ob, orb_n, k).distance_to(ts[0].pos)
		if d < bd:
			bd = d
			best = k
	if best < 0:
		return false
	sa.orb_broken[best] = float(shb.get("regrow", 1.0))
	var p: Vector2 = _h4_orb_ground(o, ob, orb_n, best) + Vector2(0, -16)
	ts = o.los_sort(ts, ts.size(), _h4_orb_ground(o, ob, orb_n, best))
	o.fx({"kind": "glow", "pos": p, "r": 12.0, "life": 0.2, "col": Color(1.8, 1.4, 0.8), "alpha": 0.8})
	for q in 6:
		o.fx({"kind": "shard", "pos": p, "vel": Vector2.from_angle(g.vrng.randf() * TAU) * g.vrng.randf_range(80, 150), "life": 0.3, "col": H4_AMBER,
			"sz": g.vrng.randf_range(2.5, 4.0), "ang": g.vrng.randf() * TAU, "spin": g.vrng.randf_range(-14, 14), "grav": 260.0})
	var dmg: float = _h4_bash_dmg(o) * float(shb.get("mult", 0.4))
	for k in mini(int(shb.get("n", 3)), ts.size()):
		_h4_shoot(o, sa, "shard", p, ts[k].pos + Vector2(0, -16), 560.0, dmg, str(shb.get("src", "")))
	_h3_sfx(o, "hit", -4.0, 1.4)
	return true


## 治疗画面：飘字 + 光点 + 治疗光环 + 星光（她自己是队长时光环不画、星光挪到头顶，免得盖住注射动作）
static func _h4_heal_fx(o, h: float) -> void:
	var g = o.g
	o.float_text(g.ppos + Vector2(0, -90), "+%d" % int(h), H4_AMBER, 16)
	for k in 6:
		o.fx({"kind": "mote", "pos": g.ppos + Vector2(g.vrng.randf_range(-20, 20), g.vrng.randf_range(-40, -10)), "vel": Vector2(0, -35), "life": 0.8, "col": H4_AMBER, "sz": 2.5})
	var me: bool = o.is_leader
	if not me:
		o.spawn_fx_sprite("fx_heal_aura_amber", g.ppos + Vector2(0, 6), g.PX * 1.4, 0.0, false, true)
	o.spawn_fx_sprite("fx_holy_impact", g.ppos + Vector2(0, -72 if me else -34), g.PX * (0.7 if me else 1.0), 0.0, false, false, Color(1, 1, 1, 0.6 if me else 1.0))


## 急救 / 药剂散布
static func h4_saria_heal(o, b: Dictionary) -> void:
	var g = o.g
	var sa := _h4sa(o)
	var h: float = g.max_hp * float(b.get("pct", 0.068)) * o.skill_power() * (float(b.get("low_mult", 1.0)) if g.hp < g.max_hp * float(b.get("low_hp", 0.0)) else 1.0)
	o.heal_leader(h, o.display_name())
	_h4_heal_fx(o, h)
	if b.get("cleanse", false):
		h4_cleanse_ctrl(o, true)
	o.fx({"kind": "ring", "pos": g.ppos, "r": float(b.get("ring", 40.0)), "r0": 8.0 if float(b.get("ring", 40.0)) < 50.0 else 10.0, "life": 0.4 if float(b.get("ring", 40.0)) < 50.0 else 0.5, "col": H4_AMBER, "floor": true})
	var sy: Dictionary = _h4_sub(o, b.get("syringe", null))
	if not sy.is_empty():
		var dmg: float = _h4_bash_dmg(o) * float(sy.get("mult", 0.8)) * o.skill_power()
		var flow: Dictionary = _h4_sub(o, sy.get("flow", null))   # 针剂·回流（docs/202）
		sa.flow_cast = int(sa.flow_cast) + 1
		for e in o.los_targets(int(sy.get("n", 3)), float(sy.get("range", 260.0)), o.pos):
			_h4_shoot(o, sa, "syringe", o.pos + Vector2(8.0 * o.face, -24), e.pos + Vector2(0, -16), float(sy.get("speed", 460.0)), dmg, str(sy.get("src", "")), float(sy.get("slow", 2.0)), flow, int(sa.flow_cast))
	var hot = b.get("hot", null)
	if hot is Dictionary:
		sa.hot_t = float(hot.get("dur", 5.0))
		o.SkillLifecycle.bind(o, "heal_over_time", o.effect_skill, sa, "hot_t", false, false)
		sa.hot_acc = 0.0
		sa.hot_pct = float(hot.get("pct", 0.0085))
		sa.hot_name = str(hot.get("name", ""))
		if o.is_leader:
			o.fx({"kind": "glow", "pos": g.ppos + Vector2(0, -74), "r": 12.0, "life": 0.35, "col": H4_AMBER, "alpha": 0.6})
		else:
			o.spawn_fx_sprite("fx_shield_amber", g.ppos + Vector2(0, -26), g.PX * 1.6)


## 钙质化的固定晶柱槽（10-29 用户「晶体碰到怪物会碎掉，然后过一会重新生成」）：每个槽 st 0 长出（0.4 秒）→ 1 立着（敌人碰到就碎）→ 2 碎裂（0.3 秒）→ 3 空着等 regrow 秒 → 原位重新长出。
## 碎时给触碰者（及脚边的）非 Boss 敌人一次击退 kb（精英 × 0.5）+ 短眩晕 stun；不造成伤害。碎晶节点（shatter）击碎的晶柱同样进入「碎 → 重新长出」
const SLOT_GROW := 0.4
const SLOT_BREAK := 0.3

static func _h4_slots_make(o, sa: Dictionary, b: Dictionary) -> void:
	var g = o.g
	var n: int = int(b.get("slots", 0))
	var R: float = float(b.get("r", 180.0))
	sa.slots = []
	sa.pillars.clear()
	for k in n:
		var p: Vector2
		if k < 4:
			var an0: float = k * TAU / 4.0 + 0.4
			p = g.ppos + Vector2(cos(an0) * 52.0, sin(an0) * 52.0 * 0.55 + 4.0)
		else:
			var an: float = g.rng_op.randf() * TAU
			var rr: float = g.rng_op.randf_range(R * 0.4, R * 0.9)
			p = g.ppos + Vector2(cos(an) * rr, sin(an) * rr * 0.55 + 4.0)
		sa.slots.append({"pos": g.map.push_out(p, 12.0), "st": 0, "t": -0.08 * float(k), "life": 9.0, "sc": g.vrng.randf_range(0.9, 1.1), "flip": g.vrng.randf() < 0.5})


static func _h4_slot_break(o, sl: Dictionary, cb: Dictionary) -> void:
	var g = o.g
	sl.st = 2
	sl.t = 0.0
	sl.life = 0.0
	var p: Vector2 = sl.pos
	var kb: float = float(cb.get("kb", 140.0))
	var stun: float = float(cb.get("stun", 0.2))
	for j in o.query_ids(p, 60.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or e.boss or e.get("chest", false):
			continue
		var off: Vector2 = e.pos - p
		if off.length() > 40.0 + e.r:
			continue
		var m: float = 0.5 if e.elite else 1.0
		o.apply_kb(e, (off.normalized() if off.length() > 1.0 else Vector2(1, 0)) * kb * m)
		if stun > 0.0:
			o.add_cc(e, stun * m)
	o.fx({"kind": "glow", "pos": p + Vector2(0, -18), "r": 14.0, "life": 0.2, "col": Color(1.8, 1.4, 0.8), "alpha": 0.7})
	for q in 5:
		o.fx({"kind": "shard", "pos": p + Vector2(0, -16), "vel": Vector2.from_angle(g.vrng.randf() * TAU) * g.vrng.randf_range(70, 150), "life": 0.3, "col": H4_AMBER,
			"sz": g.vrng.randf_range(2.5, 4.5), "ang": g.vrng.randf() * TAU, "spin": g.vrng.randf_range(-14, 14), "grav": 260.0})


static func _h4_slots_tick(o, sa: Dictionary, cb: Dictionary, dt: float) -> void:
	var g = o.g
	var regrow: float = float(cb.get("regrow", 3.0))
	var touch: float = float(cb.get("touch", 14.0))
	var shat: bool = not _h4_sub(o, cb.get("shatter", null)).is_empty()
	for sl in sa.slots:
		sl.t = float(sl.t) + dt
		match int(sl.st):
			0:
				if float(sl.t) >= SLOT_GROW:
					sl.st = 1
					if shat:
						sa.pillars.append({"pos": sl.pos, "ref": sl})
			1:
				if float(sl.life) <= 0.001:   # 碎晶节点（_h4_shatter）击碎的
					_h4_slot_break(o, sl, cb)
					continue
				for j in o.query_ids(sl.pos, 44.0):
					var e: Dictionary = g.enemies[j]
					if e.dead or e.get("chest", false) or e.pos.distance_to(sl.pos) > touch + e.r * 0.6:
						continue
					_h4_slot_break(o, sl, cb)
					break
			2:
				if float(sl.t) >= SLOT_BREAK:
					sl.st = 3
					sl.t = 0.0
			3:
				if float(sl.t) >= regrow:
					sl.st = 0
					sl.t = 0.0
					sl.life = 9.0


## 技能结束 / 队长离队：立着的晶柱一起碎掉
static func _h4_slots_end(o, sa: Dictionary) -> void:
	var g = o.g
	for sl in sa.slots:
		if int(sl.st) <= 1:
			if not o.spawn_fx_sprite("fx_saria_pillar_break", (sl.pos as Vector2) + Vector2(0, -30), g.PX):
				o.spawn_fx_sprite("fx_rock_burst", sl.pos, g.PX * 0.7, 0.0, false, false, Color(1.3, 1.0, 0.6))
	sa.slots = []
	sa.pillars.clear()


## 钙质化：晶柱升起 + 区域
static func h4_calc_start(o, b: Dictionary) -> void:
	var g = o.g
	var sa := _h4sa(o)
	sa.calc_b = b
	sa.calc = float(b.get("dur", 8.0))
	o.SkillLifecycle.bind(o, "calc_field", o.effect_skill, sa, "calc", true, false, func(): _h4_slots_end(o, sa))
	sa.calc_acc = 0.0
	sa.calc_name = str(b.get("name", ""))
	if o.cur_skill >= 0:
		o.s_dur[o.cur_skill] = float(b.get("dur", 8.0))
	sa.slots = []
	if int(b.get("slots", 0)) > 0:
		_h4_slots_make(o, sa, b)
	else:
		for k in 8:
			var an: float = k * TAU / 8.0 + 0.3
			_h4_calcite(o, g.ppos + Vector2(cos(an) * 34.0, sin(an) * 34.0 * 0.55 + 4.0), g.vrng.randf_range(0.9, 1.15), g.vrng.randf_range(22, 40), 1.5 + k * 0.03)
	var R: float = float(b.get("r", 180.0))
	o.fx({"kind": "ring", "pos": g.ppos, "r": R, "r0": 30.0, "life": 0.5, "col": H4_AMBER, "floor": true, "w": 4.0})
	o.fx({"kind": "crack", "pos": g.ppos, "r": 90.0, "life": 0.45, "col": H4_AMBER, "floor": true, "n": 10})
	o.spawn_fx_sprite("fx_holy_pillar_amber", g.ppos + Vector2(0, 6), g.PX * 1.5, 0.0, false, true)
	o.spawn_fx_sprite("fx_circle_amber", g.ppos + Vector2(0, 6), g.PX * 3.0)
	if b.has("banner"):
		o.show_banner(str(b.banner))
	g.shake = maxf(g.shake, 3.0)


# ---------------------------------------------------------------- 塞雷娅：画面

static func _h4sa_draw_auras(o) -> void:
	var g = o.g
	var cv = o.cv
	var sa: Dictionary = o.hw.sa
	var c: Vector2 = g.ppos + Vector2(0, 4)
	if float(sa.calc) > 0.0:
		var R: float = float(sa.calc_b.get("r", 180.0))
		var fade: float = clampf(float(sa.calc) / 0.6, 0.0, 1.0)
		cv.draw_set_transform(c, 0.0, Vector2(1.0, 0.55))
		feather_ring(cv, R, H4_AMBER, 0.55 * fade, g.t)   # 10-29：不填充，改内羽边 + 光点
		cv.draw_arc(Vector2.ZERO, R, 0.0, TAU, 48, Color(H4_AMBER.r, H4_AMBER.g, H4_AMBER.b, 0.45 * fade), 2.5)
		for k in 6:
			var dv := Vector2.from_angle(k * TAU / 6.0 + g.t * 0.3)
			cv.draw_line(dv * R * 0.85, dv * R, Color(1.6, 1.3, 0.8, 0.6 * fade), 2.0)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var gr: Dictionary = _h4_live(o, "verb.guard_ring")
	if gr.is_empty():
		return
	var r: float = float(gr.get("r", 62.0)) * o.stat(&"op_range")
	cv.draw_set_transform(c, 0.0, Vector2(1.0, 0.55))
	for k in 8:
		var a0: float = g.t * 0.6 + k * TAU / 8.0
		cv.draw_arc(Vector2.ZERO, r, a0, a0 + TAU / 8.0 * 0.55, 6, Color(H4_AMBER.r, H4_AMBER.g, H4_AMBER.b, 0.35 + 0.06 * sin(g.t * 4.0)), 2.0)
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 角色之上：环绕钙晶、注射器 / 碎晶片、护服充能格
static func _h4sa_draw_over(o) -> void:
	if o.pos == Vector2.INF:
		return
	var g = o.g
	var cv = o.cv
	var sa: Dictionary = o.hw.sa
	var ob: Dictionary = _h4_live(o, "verb.calc_orbs")
	var orb_n: int = _h4_orb_n(o, ob)
	for k in orb_n:
		if sa.orb_broken.has(k):
			continue
		var gp: Vector2 = _h4_orb_ground(o, ob, orb_n, k)
		var back: bool = gp.y < o.pos.y + 2.0
		var p: Vector2 = gp + Vector2(0, -16 + sin(g.t * 3.0 + k) * 2.0)
		var al: float = 0.6 if back else 1.0
		cv.draw_set_transform(gp, 0.0, Vector2(1.0, 0.45))
		cv.draw_circle(Vector2.ZERO, 5.0, Color(0.0, 0.0, 0.0, 0.25 * al))
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		cv.draw_circle(p, 8.0, Color(H4_AMBER.r, H4_AMBER.g, H4_AMBER.b, 0.18 * al))
		var dia := PackedVector2Array([p + Vector2(0, -9), p + Vector2(4.5, -1), p + Vector2(0, 6), p + Vector2(-4.5, -1)])
		cv.draw_colored_polygon(dia, Color(1.35, 1.3, 1.15, 0.9 * al))
		cv.draw_polyline(PackedVector2Array([dia[0], dia[1], dia[2], dia[3], dia[0]]), Color(H4_AMBER.r * 1.5, H4_AMBER.g * 1.3, H4_AMBER.b, al), 1.5)
		cv.draw_line(p + Vector2(0, -7), p + Vector2(0, 4), Color(2.2, 2.0, 1.6, 0.8 * al), 1.0)
	for s in sa.shots:
		var d: Vector2 = Vector2.from_angle(s.ang)
		if s.kind == "syringe":
			cv.draw_line(s.pos - d * 7.0, s.pos + d * 4.0, Color(0.1, 0.1, 0.12, 0.8), 5.0)
			cv.draw_line(s.pos - d * 6.0, s.pos + d * 3.0, Color(1.6, 1.6, 1.6), 3.0)
			cv.draw_line(s.pos - d * 2.0, s.pos + d * 3.0, Color(0.6, 1.5, 0.9), 2.0)
			cv.draw_line(s.pos + d * 4.0, s.pos + d * 9.0, Color(2.0, 2.0, 2.0), 1.0)
			cv.draw_line(s.pos - d * 8.0 + d.orthogonal() * 3.0, s.pos - d * 8.0 - d.orthogonal() * 3.0, Color(1.4, 1.4, 1.4), 1.5)
		else:
			var sv: Vector2 = Vector2.from_angle(s.ang + g.t * 16.0) * 5.0
			cv.draw_line(s.pos - d * 14.0, s.pos, Color(H4_AMBER.r, H4_AMBER.g, H4_AMBER.b, 0.35), 2.0)
			cv.draw_colored_polygon(PackedVector2Array([s.pos - sv, s.pos + sv.orthogonal() * 0.5, s.pos + sv]), Color(1.9, 1.5, 0.9))
	_h4sa_draw_nodes(o, sa)
	var su: Dictionary = _h4_live(o, "verb.suit")
	if not su.is_empty():
		var segs: int = int(su.get("segs", 4))
		var full: bool = int(sa.seg) >= segs
		var pul: float = 0.75 + 0.25 * sin(g.t * 10.0) if full else 1.0
		for k in segs:
			var r := Rect2(o.pos + Vector2(-25.0 + k * 13.0, 12.0), Vector2(11.0, 5.0))
			cv.draw_rect(r.grow(1.0), Color(0.12, 0.07, 0.03, 0.85))
			if k < int(sa.seg):
				cv.draw_rect(r, Color(H4_AMBER.r * 1.6 * pul, H4_AMBER.g * 1.4 * pul, H4_AMBER.b * pul))
			elif k == int(sa.seg):
				var fr: float = clampf(float(sa.seg_t) / float(su.get("seg_t", 5.0)), 0.0, 1.0)
				cv.draw_rect(Rect2(r.position, Vector2(11.0 * fr, 5.0)), Color(H4_AMBER.r, H4_AMBER.g, H4_AMBER.b, 0.45))
		if full:
			cv.draw_arc(o.pos + Vector2(0, -30), 26.0 + 2.0 * sin(g.t * 10.0), 0.0, TAU, 28, Color(H4_AMBER.r * 1.5, H4_AMBER.g * 1.3, H4_AMBER.b, 0.35), 2.0)


## 成长节点画面（docs/202）：带钙晶碎片的敌人头顶一枚琥珀菱形碎片 + 脚下小环；回流中的敌人脚下一圈绿环 + 十字
static func _h4sa_draw_nodes(o, sa: Dictionary) -> void:
	var g = o.g
	var cv = o.cv
	for id in sa.marks:
		var m: Dictionary = sa.marks[id]
		var e: Dictionary = m.e
		var p: Vector2 = e.pos + Vector2(0, -float(e.r) * 1.9 - 4.0 + sin(g.t * 6.0 + float(id)) * 1.5)
		var left: float = clampf((float(m.until) - g.t) / 0.4, 0.0, 1.0)
		var dia := PackedVector2Array([p + Vector2(0, -7), p + Vector2(4, 0), p + Vector2(0, 6), p + Vector2(-4, 0)])
		cv.draw_colored_polygon(dia, Color(1.4, 1.35, 1.2, 0.95 * left))
		cv.draw_polyline(PackedVector2Array([dia[0], dia[1], dia[2], dia[3], dia[0]]), Color(H4_AMBER.r * 1.6, H4_AMBER.g * 1.3, H4_AMBER.b, left), 1.5)
		cv.draw_arc(e.pos + Vector2(0, 3), float(e.r) + 3.0, 0.0, TAU, 14, Color(H4_AMBER.r, H4_AMBER.g, H4_AMBER.b, 0.6 * left), 1.5)
	for f in sa.flow:
		var e2: Dictionary = f.e
		var c: Vector2 = e2.pos + Vector2(0, 3)
		var gc := Color(0.55, 1.5, 0.85, 0.85)
		cv.draw_arc(c, float(e2.r) + 5.0, 0.0, TAU, 16, gc, 1.8)
		var tp: Vector2 = e2.pos + Vector2(0, -float(e2.r) * 1.9 - 4.0)
		cv.draw_line(tp + Vector2(-4, 0), tp + Vector2(4, 0), gc, 2.0)
		cv.draw_line(tp + Vector2(0, -4), tp + Vector2(0, 4), gc, 2.0)


static func _h4sa_draw_pfx(o, f: Dictionary, a: float) -> bool:
	var cv = o.cv
	match str(f.kind):
		"h4_bash":
			var u: float = 1.0 - a
			var ek: float = 1.0 - (1.0 - minf(1.0, u / 0.6)) * (1.0 - minf(1.0, u / 0.6))
			var d: Vector2 = Vector2.from_angle(f.ang)
			var big: bool = f.get("big", false)
			var R: float = 30.0 if big else 24.0
			var half: float = 1.05 if not big else 0.5
			var c: Vector2 = f.pos + d * (10.0 + f.reach * 0.45 * ek)
			var oc: Vector2 = c - d * R
			var w: float = (9.0 if big else 7.0) * (0.55 + 0.45 * a)
			cv.draw_arc(oc, R, f.ang - half, f.ang + half, 14, Color(0.25, 0.14, 0.05, 0.75 * a), w + 3.0)
			cv.draw_arc(oc, R, f.ang - half, f.ang + half, 14, Color(H4_AMBER.r * 1.3, H4_AMBER.g * 1.2, H4_AMBER.b, 0.95 * a), w)
			cv.draw_arc(oc, R + w * 0.4, f.ang - half * 0.85, f.ang + half * 0.85, 12, Color(2.2, 1.9, 1.3, a), 1.5)
			cv.draw_line(c - d * 2.0, c - d * (w + 2.0), Color(2.0, 1.7, 1.1, 0.8 * a), 2.0)
			for s in [-1.0, 0.0, 1.0]:
				var off: Vector2 = d.orthogonal() * s * R * 0.55
				cv.draw_line(c - d * 10.0 + off, c - d * (22.0 + 6.0 * absf(s)) + off, Color(H4_AMBER.r * 1.4, H4_AMBER.g * 1.3, H4_AMBER.b, 0.5 * a), 1.5)
			return true
		"h4_crystal":
			var age: float = f.max - f.life
			var grow: float = clampf(age / 0.25, 0.0, 1.0)
			var fade: float = clampf(f.life / 0.4, 0.0, 1.0)
			var h: float = f.h * (1.0 - (1.0 - grow) * (1.0 - grow))
			var p: Vector2 = f.pos
			var top: Vector2 = p + Vector2(f.lean * h, -h)
			cv.draw_colored_polygon(PackedVector2Array([p + Vector2(-5, 0), top + Vector2(-2, 2), top, top + Vector2(2, 3), p + Vector2(5, 0), p + Vector2(0, 3)]), Color(H4_AMBER.r, H4_AMBER.g, H4_AMBER.b, 0.85 * fade))
			cv.draw_line(p + Vector2(-3, -1), top + Vector2(-1, 2), Color(1.9, 1.6, 1.0, 0.9 * fade), 1.5)
			cv.draw_circle(top, 2.0, Color(2.2, 2.0, 1.4, fade))
			return true
	return false
