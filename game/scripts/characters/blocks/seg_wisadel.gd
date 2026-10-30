## 干员积木 · seg_wisadel（docs/101 §7.3 B6 ①，10-15：由 op_blocks.gd 按段拆出，内容与注释照搬；继承链与门面见 op_blocks.gd）
extends "res://scripts/characters/blocks/seg_suzuran.gd"

const WdVg = preload("res://scripts/characters/blocks/vis_growth.gd")   # 可见成长 #129 / #130（docs/163 §5）：魂灵之影副体与体型


# ---------------------------------------------------------------- 维什戴尔段（第 4 批续，WD_TAGS）
#  shape.cannon     炮击（普攻，手动 A 类，落点 aim_land）：目标 = 离队长最近、几个距离相仿（slack 内）时挑落点周围敌人最多的；炮弹是本干员自己的实体（高速平射 → 落点爆炸 → quake_t 秒后原地余震）。
#                   索敌距离 = k × (range / ref) × op_range（k：aim_r 起手 / fire_r 出手 / 技能的 aim_r）；爆炸半径 = aoe × op_range × aoe_mults；
#                   余震伤害 = 炮弹 × quake（quakes 里第一条 cond 成立的 value 取代），半径 × quake_r；echo {cond, delay, mult, size}：同一处再余震一次；
#                   ash {size, rings {cond}, stun}：次数型补丁（灰烬弹幕）的炮弹（rings：余震三圈并眩晕）；twin {cond, mult, size}：同时向次优目标再打一发；
#                   shade {cond, mult, r, stun, max}：被炸死的敌人留下残影，0.25 秒后殉爆；mark {dur, mult, r, max}：残影标记（死亡必殉爆）；
#                   giant {mult, size, cd, src}：饱和炮击装填的巨炮（普攻间隔 × cd）
#  verb.cannon_exec 凋零处刑：精英 / Boss 优先（血最多）的一发重炮（× mult × 技能强度、爆炸 × size、眩晕 stun）；mark {cond}：炸到的敌人挂残影标记
#  verb.cannon_load 饱和炮击：装填 n 发巨炮，第一发立刻打出去，之后的普攻换成巨炮直到打完（技能剩余 = 剩余发数）
#  verb.souls       魂灵之影（放 passive）：n 个悬在肩后，每 cd 秒各自飞向 range 内（优先未标记的）敌人挂上残影标记，再飞回来。
#                   follow: true（10-14 用户「魂灵之影只跟随维什戴尔发射炮击，而不是自己出去」）：不再飞出去，始终悬在肩后；
#                   维什戴尔每打出一发炮击（普攻 / 次数型补丁 / 巨炮），各影子依次（第 k 个晚 fire.gap × k 秒）朝主目标附近 fire.spread 内
#                   优先未标记、两个影子不重复的敌人（没有就主目标）开一炮（攻击 × fire.mult、同样余震）；魂炮命中时给它的目标挂上残影标记（标记机制照旧）

const BalW = preload("res://scripts/core/balance.gd")


static func _h4wd(o) -> Dictionary:
	var h := hw_st(o)
	if not h.has("wd"):
		h["wd"] = {"shells": [], "quakes": [], "shades": [], "ammo": 0, "marks": {}, "souls": [], "booms": [], "qbooms": [], "dup_skipped": 0, "dup_kinds": {}}
	return h.wd


static func _h4_wd_reach(o, a: Dictionary, k: float) -> float:
	return k * (float(a.get("range", 340.0)) / float(a.get("ref", 480.0))) * o.stat(&"op_range")


static func _h4_wd_aoe(o, a: Dictionary) -> float:
	var r: float = float(a.get("aoe", 52.0)) * o.stat(&"op_range")
	for m in a.get("aoe_mults", _EA):
		if m is Dictionary and cond_true(o, m.get("cond", _ED)):
			r *= float(m.get("mult", 1.0))
	return r


static func _h4_count_around(o, c: Vector2, r: float) -> int:
	var n := 0
	for j in o.query_ids(c, r):
		var q: Dictionary = o.g.enemies[j]
		if not q.dead and q.pos.distance_to(c) < r:
			n += 1
	return n


## 普攻 / 饱和炮击的目标：离队长最近；最近几个距离相仿（slack 内）时挑落点周围敌人最多的
static func _h4_wd_target(o, a: Dictionary, reach: float) -> Dictionary:
	var g = o.g
	var cands: Array = []
	for e in o.nearest_enemies(6, reach, g.ppos):
		if e.pos.distance_to(o.pos) <= reach:
			cands.append(e)
	if cands.is_empty():
		return {}
	var d0: float = cands[0].pos.distance_to(g.ppos)
	var best: Dictionary = cands[0]
	var most := -1
	var slack: float = float(a.get("slack", 40.0))
	for e in cands:
		if e.pos.distance_to(g.ppos) - d0 > slack:
			break
		var n := _h4_count_around(o, e.pos, _h4_wd_aoe(o, a))
		if n > most:
			most = n
			best = e
	return best


## 凋零处刑：精英 / Boss 优先（血最多的），没有就按普攻的选法
static func _h4_exec_target(o, a: Dictionary, reach: float) -> Dictionary:
	var best: Dictionary = {}
	var hp := -1.0
	for e in o.nearest_enemies(24, reach, o.pos):
		if (e.elite or e.boss) and e.hp > hp:
			hp = e.hp
			best = e
	return best if not best.is_empty() else _h4_wd_target(o, a, reach)


static func _h4_muzzle(o, a: Dictionary) -> Vector2:
	var tv = a.get("tip", [14, -34])
	return o.pos + Vector2(float(tv[0]) * o.face, float(tv[1]))


static func _h4_cannon_start(o, a: Dictionary) -> void:
	if o.cd > 0.0 or o.AttackPhases.attack_locked(o):
		return
	var reach: float = _h4_wd_reach(o, a, float(a.get("aim_r", 480.0)))
	var tgt: Dictionary = _h4_wd_target(o, a, reach)
	var at: Vector2 = o.atk_point([tgt] if not tgt.is_empty() else [], reach)   # 按住瞄准 A 类（契约 v2.5）：落点见 aim_land
	if at == Vector2.INF:
		o.cd = float(a.get("idle", 0.2))
	else:
		var gi: Dictionary = a.get("giant", {})
		o.cd = float(a.get("every", 1.4)) / o.stat(&"op_aspd") * (float(gi.get("cd", 0.6)) if int(_h4wd(o).ammo) > 0 else 1.0)
		o.start_attack(at, 0.5, 0.25, "", o.cd)


static func _h4_cannon_release(o, a: Dictionary) -> void:
	var wd := _h4wd(o)
	var tgt: Dictionary = _h4_wd_target(o, a, _h4_wd_reach(o, a, float(a.get("fire_r", 520.0)))) if o.atk_aim == Vector2.ZERO else o.aim_land(_h4_wd_reach(o, a, float(a.get("aim_r", 480.0))))
	if tgt.is_empty():
		return
	var atk: float = o.base(str(a.get("atk_key", "atk")), 0.0)
	if int(wd.ammo) > 0:
		wd.ammo = int(wd.ammo) - 1
		_h4_fire_giant(o, a, tgt.pos)
	else:
		var patch: Dictionary = _h4_take_patch(o)
		if not patch.is_empty():
			var ash: Dictionary = a.get("ash", {})
			var rings: bool = not _h4_sub(o, ash.get("rings", null)).is_empty()
			var d1: float = atk * float(patch.get("mult", 1.0)) * (o.skill_power() if patch.get("power", false) else 1.0)
			var aim_to: Vector2 = _g202_chain_aim(o, a, tgt.pos)   # docs/202 余烬未冷·续燃：残影链
			_h4_fire(o, a, aim_to, d1, str(a.get("src", "")), float(ash.get("size", 1.65)), true, 0.0, false, rings)
			_h4_twin(o, a, tgt, d1, rings)
		else:
			_h4_fire(o, a, tgt.pos, atk, str(a.get("src", "")), 1.0, true, 0.0)
			_h4_twin(o, a, tgt, atk, false)
	_h4_cannon_after(o, a, tgt)   # 精英化第 4 批（好礼）的挂点；迁移时没有
	_h4_souls_sync(o, a, tgt)   # 10-14：魂灵之影跟随开炮（verb.souls follow）


## 精一「好礼」（docs/91 §18）：炮击的主目标直接挂上残影标记（标记期间倒下必定引爆残影，攻击 × gift.mult）；手动给的落点（伪目标）不挂
static func _h4_cannon_after(o, a: Dictionary, tgt: Dictionary) -> void:
	var gf: Dictionary = _h4_sub(o, a.get("gift", null))
	if gf.is_empty() or int(tgt.get("id", -1)) < 0 or tgt.get("dead", false):
		return
	_h4_mark(o, a, tgt, true, float(gf.get("mult", 0.4)))


## docs/202 余烬未冷·续燃（节点 5A，chain {cond node:ash_rings2, window, gap, snap_r}）：S1「定点清算」的强化炮击
##  - 每发强化炮击出手后 window 秒内，被炸死的敌人留下的残影、带标记倒下的残影都不等 0.25 秒，立即引爆；
##  - 紧接着上一发（gap 秒内）的下一发，落点吸到离原落点 snap_r 内最近的一个残影 / 残影标记上（一道弧线 + 落点环）。
## 不改伤害倍率。返回这一发的落点
static func _g202_chain_aim(o, a: Dictionary, to: Vector2) -> Vector2:
	var ch: Dictionary = _h4_sub(o, a.get("chain", null))
	if ch.is_empty():
		return to
	var g = o.g
	var wd := _h4wd(o)
	var out: Vector2 = to
	if g.t - float(wd.get("chain_prev", -99.0)) < float(ch.get("gap", 2.5)):
		var best := INF
		var sr: float = float(ch.get("snap_r", 260.0)) * o.stat(&"op_range")
		for k in wd.marks:
			var me: Dictionary = wd.marks[k].e
			if not me.dead:
				var d: float = me.pos.distance_to(to)
				if d <= sr and d < best:
					best = d
					out = me.pos
		for sd in wd.shades:
			var d2: float = (sd.pos as Vector2).distance_to(to)
			if d2 <= sr and d2 < best:
				best = d2
				out = sd.pos
		if out != to:
			o.fx({"kind": "line", "pos": to, "to": out, "life": 0.18, "col": H4_EMBER, "w": 2.0, "laser": true})
			o.fx({"kind": "ring", "pos": out, "r": 34.0, "r0": 8.0, "life": 0.3, "col": Color(1.7, 0.7, 0.3), "floor": true, "w": 2.5, "alpha": 0.9})
	wd["chain_prev"] = g.t
	wd["chain_until"] = g.t + float(ch.get("window", 1.2))
	return out


## 残影多久后殉爆：续燃的窗口内立即（t = 0），否则 0.25 秒
static func _g202_shade_delay(o) -> float:
	if o.g.t < float(_h4wd(o).get("chain_until", -1.0)):
		return 0.0
	return 0.25


## docs/202 亡者回响·回馈（节点 5B，fb {cond node:exec_mark2, kills, sp, cd}）：一次残影引爆杀死 ≥ kills 名敌人时，全队（含自身）技能技力各 + sp 秒，
## cd 秒内至多一次；金色光点从引爆处飞向每名队员
static func _g202_feedback(o, a: Dictionary, c: Vector2, n_kill: int) -> void:
	var fb: Dictionary = _h4_sub(o, a.get("fb", null))
	if fb.is_empty() or n_kill < int(fb.get("kills", 2)):
		return
	var g = o.g
	var wd := _h4wd(o)
	if g.t - float(wd.get("fb_t", -99.0)) < float(fb.get("cd", 4.0)):
		return
	wd["fb_t"] = g.t
	var sec: float = float(fb.get("sp", 0.6))
	var col: Color = o.col()
	for m in g.squad.ops:
		for i in 3:
			if m.skill_unlocked(i) and m.sp_need(i) > 0.0 and not m.perm[i]:
				m.sp[i] = minf(m.sp_need(i), m.sp[i] + sec)
		if m.pos == Vector2.INF:
			continue
		for q in 3:
			o.fx({"kind": "h4_spmote", "pos": c + Vector2(0, -16), "start": c + Vector2(0, -16), "tgt": m, "life": 0.45 + 0.08 * q, "col": col, "bend": g.vrng.randf_range(-40, 40)})
	o.fx({"kind": "ring", "pos": c, "r": 46.0, "r0": 10.0, "life": 0.35, "col": Color(2.0, 1.6, 0.6), "floor": true, "w": 3.0, "alpha": 0.9})


## 礼尚往来：第二发炮弹打次优目标（候选里第一个离首发落点超过爆炸半径的；没有就取下一个候选），伤害 × twin.mult
static func _h4_twin(o, a: Dictionary, first: Dictionary, dmg: float, rings: bool) -> void:
	var tw: Dictionary = _h4_sub(o, a.get("twin", null))
	if tw.is_empty():
		return
	var g = o.g
	var reach: float = _h4_wd_reach(o, a, float(a.get("fire_r", 520.0)))
	var best: Dictionary = {}
	for e in o.nearest_enemies(8, reach, g.ppos):
		if e.id == first.id or e.pos.distance_to(o.pos) > reach:
			continue
		if best.is_empty():
			best = e
		if e.pos.distance_to(first.pos) > _h4_wd_aoe(o, a):
			best = e
			break
	if best.is_empty():
		return
	_h4_fire(o, a, best.pos, dmg * float(tw.get("mult", 0.6)), str(a.get("src", "")), float(tw.get("size", 0.85)), true, 0.0, false, rings)


## 巨型炮弹：伤害 × giant.mult × 技能强度、爆炸 × size、必余震；炮口焰加倍 + 后坐火星
static func _h4_fire_giant(o, a: Dictionary, to: Vector2) -> void:
	var g = o.g
	var gi: Dictionary = a.get("giant", {})
	_h4_fire(o, a, to, o.base(str(a.get("atk_key", "atk")), 0.0) * float(gi.get("mult", 1.6)) * o.skill_power(), str(gi.get("src", "")), float(gi.get("size", 2.0)), true, 0.0, false, false, "giant")
	var mz: Vector2 = _h4_muzzle(o, a)
	var dir: Vector2 = (to - mz).normalized()
	o.fx({"kind": "glow", "pos": mz, "r": 26.0, "life": 0.16, "col": Color(1.8, 0.7, 0.5), "alpha": 0.8})
	for k in 8:
		o.fx({"kind": "spark", "pos": mz, "vel": (-dir).rotated(g.vrng.randf_range(-0.9, 0.9)) * g.vrng.randf_range(120, 260), "life": 0.3, "col": H4_EMBER, "sz": 2.5, "drag": 3.0})


## 发一发炮弹（rings：灰烬弹幕的强化炮弹，余震三圈并眩晕；kind：画面 / 音效档（"" 普通 / giant 巨炮 / exec 凋零处刑）；mark_c：炸到的敌人挂标记的条件，爆炸时求值）
static func _h4_fire(o, a: Dictionary, to: Vector2, base_dmg: float, src: String, size: float, quake: bool, stun: float, light := false, rings := false, kind := "", mark_c = null, from := Vector2.INF) -> Dictionary:
	var g = o.g
	var wd := _h4wd(o)
	var own: bool = from == Vector2.INF
	if own:
		o.face = signf(to.x - o.pos.x) if absf(to.x - o.pos.x) > 2.0 else o.face
		from = _h4_muzzle(o, a)
	# 高速炮弹：1500px/s、最高拱 18px（平射，但炮弹本身看得见）
	var dur: float = clampf(from.distance_to(to) / 1500.0, 0.08, 0.3)
	var s := {"from": from, "to": to, "t": 0.0, "dur": dur, "dmg": base_dmg * o._dmg_bonus(), "r": _h4_wd_aoe(o, a) * size, "src": src,
		"trail": 0.0, "quake": quake, "stun": stun, "light": light, "hist": [], "size": size, "rings": rings, "kind": kind, "mark_c": mark_c}
	wd.shells.append(s)
	if not own:
		return s
	# 出膛：暗红锥形炮口焰 + 向后飞的橙色火星
	var dir := (to - from).normalized()
	o.fx({"kind": "h4_muzzle", "pos": from, "dir": dir, "life": 0.07, "col": H4_RED, "sz": 30.0 * size})
	o.fx({"kind": "glow", "pos": from, "r": 9.0 * size, "life": 0.06, "col": Color(2.0, 1.1, 0.8), "alpha": 0.8})
	for k in 3:
		o.fx({"kind": "spark", "pos": from, "vel": (-dir).rotated(g.vrng.randf_range(-0.6, 0.6)) * g.vrng.randf_range(60, 140), "life": 0.2, "col": H4_EMBER, "sz": 2.0, "drag": 3.0})
	_h3_sfx(o, "atk", 2.0 if size <= 1.2 else 4.0, 1.0 if size <= 1.2 else 0.85)
	return s


static func _h4_shell_at(s: Dictionary, k: float) -> Vector2:
	return s.from.lerp(s.to, k) + Vector2(0, -sin(k * PI) * minf(18.0, s.from.distance_to(s.to) * 0.05))


## 凋零处刑：一发重炮，眩晕 + 余震
static func h4_cannon_exec(o, b: Dictionary) -> void:
	var a: Dictionary = o.B.get("attack", {})
	var tgt: Dictionary = _h4_exec_target(o, a, _h4_wd_reach(o, a, float(b.get("aim_r", 540.0))))
	if tgt.is_empty():
		return
	_h4_fire(o, a, tgt.pos, o.base(str(a.get("atk_key", "atk")), 0.0) * float(b.get("mult", 3.0)) * o.skill_power(), str(b.get("src", "")), float(b.get("size", 1.6)), true, float(b.get("stun", 0.8)), false, false, "exec", b.get("mark", null))
	var mz: Vector2 = _h4_muzzle(o, a)
	o.fx({"kind": "glow", "pos": mz, "r": 28.0, "life": 0.3, "col": H4_RED, "alpha": 0.6})
	_h3_vsparks(o, mz, H4_EMBER, 10, 200.0, 0.3)


## 饱和炮击：装填巨型炮弹，第一发立刻打出去，之后的普攻换成巨炮直到打完
static func h4_cannon_load(o, b: Dictionary) -> void:
	var wd := _h4wd(o)
	var a: Dictionary = o.B.get("attack", {})
	wd.ammo = int(b.get("n", 8))
	o.SkillLifecycle.bind(o, "cannon_load", o.effect_skill, wd, "ammo", true, true, Callable(), "attacks")
	wd["status"] = str(b.get("status", "×%d"))
	if o.cur_skill >= 0:
		o.s_dur[o.cur_skill] = float(int(b.get("n", 8)))
	if b.has("banner"):
		o.show_banner(str(b.banner) % int(wd.ammo))
	var mz: Vector2 = _h4_muzzle(o, a)
	o.fx({"kind": "glow", "pos": mz, "r": 30.0, "life": 0.4, "col": H4_RED, "alpha": 0.6})
	_h3_vsparks(o, mz, H4_EMBER, 10, 160.0, 0.3)
	var tg3: Dictionary = _h4_wd_target(o, a, _h4_wd_reach(o, a, float(b.get("aim_r", 540.0))))
	if not tg3.is_empty():
		wd.ammo = int(wd.ammo) - 1
		_h4_fire_giant(o, a, tg3.pos)
		_h4_souls_sync(o, a, tg3)
		o.cd = float(a.get("every", 1.4)) / o.stat(&"op_aspd") * float(a.get("giant", _ED).get("cd", 0.6))


static func _h4wd_tick(o, wd: Dictionary, dt: float) -> void:
	var g = o.g
	var a: Dictionary = o.B.get("attack", {})
	# 炮弹
	for s in wd.shells:
		s.t += dt
		s.trail -= dt
		if s.trail <= 0.0 and s.t < s.dur:
			s.trail = 0.03
			var p: Vector2 = _h4_shell_at(s, s.t / s.dur) if s.hist.size() < 3 else s.hist[s.hist.size() - 3]
			o.fx({"kind": "h4_ember", "pos": p, "vel": Vector2(g.vrng.randf_range(-30, 30), g.vrng.randf_range(-20, 30)), "life": 0.3, "col": H4_DARK, "sz": 3.0, "ang": g.vrng.randf() * TAU, "spin": 14.0, "grav": 200.0, "cold": true})
		if s.t < s.dur:
			s.hist.append(_h4_shell_at(s, s.t / s.dur))
			if s.hist.size() > 9:
				s.hist.pop_front()
		if s.t >= s.dur:
			_h4_explode(o, a, s.to, s.dmg, s.r, s.src, 0, s.stun, s.light, false, str(s.kind), s.get("mark_c", null))
			var me = s.get("mark_e", null)   # 魂炮（follow）：命中时给它的目标挂残影标记（目标还活着、在爆炸范围内）
			if me != null and not me.dead and me.pos.distance_to(s.to) < float(s.r) + float(me.r):
				_h4_mark(o, a, me)
			o.fx({"kind": "line", "pos": s.from, "to": s.to, "life": 0.09, "col": H4_RED, "w": 2.0 * float(s.get("size", 1.0)), "laser": true})
			if s.quake:
				var qd: float = s.dmg * _h4_first_val(o, a.get("quakes", []), float(a.get("quake", 0.4)))
				var qs: float = float(a.get("ash", _ED).get("stun", 0.8)) if s.rings else 0.0
				var qt: float = float(a.get("quake_t", 0.45))
				wd.quakes.append({"pos": s.to, "t": qt, "dmg": qd, "r": s.r * float(a.get("quake_r", 1.2)), "rings": s.rings, "stun": qs})
				var ec: Dictionary = _h4_sub(o, a.get("echo", null))
				if not ec.is_empty():
					wd.quakes.append({"pos": s.to, "t": qt + float(ec.get("delay", 0.3)), "dmg": qd * float(ec.get("mult", 1.0)),
						"r": s.r * float(a.get("quake_r", 1.2)) * float(ec.get("size", 1.25)), "rings": s.rings, "stun": qs})
	wd.shells = wd.shells.filter(func(s): return s.t < s.dur)
	for q in wd.quakes:
		q.t -= dt
		if q.t <= 0.0:
			_h4_explode(o, a, q.pos, q.dmg, q.r, str(a.get("quake_src", "")), 0, q.stun, false, q.rings, "quake")
	wd.quakes = wd.quakes.filter(func(q): return q.t > 0.0)
	var sh: Dictionary = a.get("shade", {})
	for sd in wd.shades:
		sd.t -= dt
		if sd.t <= 0.0:
			_h4_explode(o, a, sd.pos, sd.dmg, sd.r, str(sh.get("src", "")), sd.depth, float(sh.get("stun", 0.6)), false, false, "shade")
	wd.shades = wd.shades.filter(func(sd): return sd.t > 0.0)
	# 残影标记
	if not wd.marks.is_empty():
		for k in wd.marks.keys():
			var mk: Dictionary = wd.marks[k]
			mk.t -= dt
			if mk.t <= 0.0 or mk.e.dead:
				wd.marks.erase(k)
	_h4_souls_tick(o, wd, a, dt)


## 条件成立的第一条 [{cond, value}] 的值；没有 = dv
static func _h4_first_val(o, arr, dv: float) -> float:
	if arr is Array:
		for m in arr:
			if m is Dictionary and cond_true(o, m.get("cond", _ED)):
				return float(m.get("value", dv))
	return dv


## 挂残影标记（亡者回响 / 魂灵之影）：mark.dur 秒内该敌人死亡（不论谁击杀）必定殉爆；同时最多 mark.max 个
static func _h4_mark(o, a: Dictionary, e: Dictionary, gift := false, mult := -1.0) -> void:
	if e.dead or e.get("chest", false):
		return
	var wd := _h4wd(o)
	var mk: Dictionary = a.get("mark", {})
	if not wd.marks.has(e.id) and wd.marks.size() >= int(mk.get("max", 12)):
		return
	var keep: bool = wd.marks.has(e.id) and wd.marks[e.id].get("gift", false)
	var m0: float = float(wd.marks[e.id].get("mult", -1.0)) if wd.marks.has(e.id) else -1.0
	wd.marks[e.id] = {"e": e, "t": float(mk.get("dur", 4.0)), "gift": gift or keep, "mult": maxf(m0, mult if mult >= 0.0 else float(mk.get("mult", 0.45)))}
	o.fx({"kind": "h4_shade", "pos": e.pos + Vector2(0, -e.r * 0.5), "life": 0.3, "col": H4_DARK})


## 击杀钩子：带残影标记的敌人殉爆（0.25 秒前摇 → 殉爆，伤害 = 攻击 × mark.mult）
static func _h4wd_on_kill(o, e: Dictionary) -> void:
	var wd: Dictionary = o.hw.wd
	if not wd.marks.has(e.id):
		return
	var mm: float = float(wd.marks[e.id].get("mult", -1.0))
	wd.marks.erase(e.id)
	e["wis_det"] = true
	var a: Dictionary = o.B.get("attack", {})
	if wd.shades.size() >= int(a.get("shade", _ED).get("max", 12)):
		return
	var mk: Dictionary = a.get("mark", {})
	wd.shades.append({"pos": e.pos, "t": _g202_shade_delay(o), "dmg": o.base(str(a.get("atk_key", "atk")), 0.0) * (mm if mm >= 0.0 else float(mk.get("mult", 0.45))) * o._dmg_bonus(), "r": _h4_wd_aoe(o, a) * float(mk.get("r", 0.9)), "depth": 1})
	o.fx({"kind": "h4_shade", "pos": e.pos, "life": 0.3, "col": H4_DARK})


## 魂灵之影：悬在维什戴尔肩后；每 cd 秒各自飞向附近一名（优先未标记的）敌人挂上残影，再飞回来
static func _h4_souls_tick(o, wd: Dictionary, a: Dictionary, dt: float) -> void:
	if o.pos == Vector2.INF:
		return
	var sb: Dictionary = _h4_live(o, "verb.souls")
	if sb.is_empty():
		return
	var g = o.g
	var souls: Array = wd.souls
	var n0: int = int(sb.get("n", 2))
	while souls.size() < n0 + WdVg.summon_subs(g, "soul"):   # 可见成长 #129：副体排在本体之后（sub = true：伤害 × sub_dmg、体型 × sub_scale）
		souls.append({"p": o.pos + Vector2(0, -50), "st": "idle", "tgt": null, "cd": 0.8 + 1.0 * souls.size(), "sub": souls.size() >= n0})
	if sb.get("follow", false):
		_h4_souls_follow_tick(o, wd, a, sb, dt)
		return
	var spd: float = float(sb.get("speed", 520.0))
	for k in souls.size():
		var s: Dictionary = souls[k]
		var home: Vector2 = _h4_soul_home(o, k)
		match str(s.st):
			"idle":
				s.p = s.p.lerp(home, minf(1.0, dt * 6.0))
				s.cd -= dt
				if s.cd <= 0.0:
					var tg: Dictionary = _h4_soul_target(o, sb)
					if tg.is_empty():
						s.cd = 0.3
					else:
						s.tgt = tg
						s.st = "go"
						s.gt = g.t
						s.cd = float(sb.get("cd", 2.0))
			"go":
				var tg2 = s.tgt
				if tg2 == null or tg2.dead:
					s.st = "back"
				else:
					var to: Vector2 = tg2.pos + Vector2(0, -tg2.r - 10.0)
					s.p = s.p.move_toward(to, spd * dt)
					if g.vrng.randf() < dt * 30.0:
						o.fx({"kind": "mote", "pos": s.p + Vector2(g.vrng.randf_range(-4, 4), 6), "vel": Vector2(0, -20), "life": 0.35, "col": Color(0.3, 0.05, 0.08), "sz": 2.5})
					if s.p.distance_to(to) < 8.0:
						_h4_mark(o, a, tg2)
						o.fx({"kind": "ring", "pos": tg2.pos, "r": tg2.r + 16.0, "r0": 4.0, "life": 0.3, "col": H4_RED, "floor": true, "w": 2.0})
						s.st = "back"
			"back":
				s.p = s.p.move_toward(home, spd * dt)
				if s.p.distance_to(home) < 10.0:
					s.st = "idle"
	_h4_soul_fire_tick(o, wd, a, sb, dt)   # 精英化第 4 批（魂炮）的挂点；迁移时没有


## 精二「魂炮」（docs/91 §18）：每个魂灵之影各自每 every 秒（待在肩后时）朝一名带残影标记的敌人开一炮（离它最近、两个影子不打同一个；没有标记就打离维什戴尔最近的），
## 攻击 × mult、同样余震；开火动作 anim 秒，第 fire_at 秒出膛
static func _h4_soul_fire_tick(o, wd: Dictionary, a: Dictionary, sb: Dictionary, dt: float) -> void:
	var fc: Dictionary = _h4_sub(o, sb.get("fire", null))
	if fc.is_empty():
		return
	var g = o.g
	for k in wd.souls.size():
		var s: Dictionary = wd.souls[k]
		if not s.has("fcd"):
			s["fcd"] = float(fc.get("first", 1.5)) + float(fc.get("stagger", 2.0)) * k
			s["ft"] = -1.0
		if float(s.ft) >= 0.0:
			s.ft = float(s.ft) + dt
			if not s.fired and float(s.ft) >= float(fc.get("fire_at", 0.16)):
				s.fired = true
				var tg = s.get("ftg", null)
				if tg != null and not tg.dead:
					_h4_soul_shot(o, a, fc, s, tg)
			if float(s.ft) >= float(fc.get("anim", 0.32)):
				s.ft = -1.0
			continue
		s.fcd = float(s.fcd) - dt
		if float(s.fcd) > 0.0 or str(s.st) != "idle":
			continue
		var tg2: Dictionary = _h4_soul_cannon_target(o, a, fc, s)
		if tg2.is_empty():
			s.fcd = 0.3
			continue
		s.fcd = float(fc.get("every", 4.0))
		s.ft = 0.0
		s.fired = false
		s.ftg = tg2


static func _h4_soul_cannon_target(o, a: Dictionary, fc: Dictionary, s: Dictionary) -> Dictionary:
	var wd: Dictionary = o.hw.wd
	var reach: float = _h4_wd_reach(o, a, float(fc.get("aim_r", 520.0)))
	var other = null
	for q in wd.souls:
		if not is_same(q, s) and float(q.get("ft", -1.0)) >= 0.0 and q.get("ftg", null) != null:
			other = q.ftg
	var best: Dictionary = {}
	var bd := INF
	for key in wd.marks:
		var e: Dictionary = wd.marks[key].e
		if e.dead or (other != null and is_same(e, other)) or e.pos.distance_to(o.pos) > reach:
			continue
		var ds: float = e.pos.distance_squared_to(s.p)
		if ds < bd:
			bd = ds
			best = e
	if not best.is_empty():
		return best
	var ts: Array = o.nearest_enemies(1, reach, o.pos)
	return ts[0] if not ts.is_empty() else {}


static func _h4_soul_shot(o, a: Dictionary, fc: Dictionary, s: Dictionary, tg: Dictionary) -> void:
	var g = o.g
	var from: Vector2 = s.p + Vector2(0, 4)
	var sub_k: float = WdVg.kn("sub_dmg", 0.6) if s.get("sub", false) else 1.0
	var sh: Dictionary = _h4_fire(o, a, tg.pos, o.base(str(a.get("atk_key", "atk")), 0.0) * float(fc.get("mult", 0.3)) * sub_k, str(fc.get("src", "")), float(fc.get("size", 1.0)) * (WdVg.kn("sub_scale", 0.85) if s.get("sub", false) else 1.0), true, 0.0, false, false, "soul", null, from)
	if fc.get("mark", false):
		sh["mark_e"] = tg
	var dir: Vector2 = (tg.pos - from).normalized()
	o.spawn_fx_sprite("fx_muzzle_flash", from + dir * 6.0, g.PX * 0.7, dir.angle(), false, false, Color(0.55, 0.3, 0.75))   # 炮口一团暗紫烟（10-21 用户：魂灵之影不要攻击帧，直接出弹）
	for q in 3:
		o.fx({"kind": "spark", "pos": from, "vel": dir.rotated(g.vrng.randf_range(-0.6, 0.6)) * g.vrng.randf_range(60, 130), "life": 0.2, "col": Color(0.55, 0.15, 0.35), "sz": 2.0, "drag": 3.0})
	_h3_sfx(o, "atk", -4.0, 1.25, 0.05)


## follow 模式（10-14）：影子一直悬在肩后；排队的魂炮按 fq 倒数开火动作（anim 秒，第 fire_at 秒出膛）
static func _h4_souls_follow_tick(o, wd: Dictionary, a: Dictionary, sb: Dictionary, dt: float) -> void:
	var fc: Dictionary = _h4_sub(o, sb.get("fire", null))
	for k in wd.souls.size():
		var s: Dictionary = wd.souls[k]
		s.p = s.p.lerp(_h4_soul_home(o, k), minf(1.0, dt * 6.0))
		if fc.is_empty():
			s.ft = -1.0
			s.fq = -1.0
			continue
		if float(s.get("fq", -1.0)) >= 0.0:
			s.fq = float(s.fq) - dt
			if float(s.fq) < 0.0:
				s.fq = -1.0
				s.ft = 0.0
				s.fired = false
		if float(s.get("ft", -1.0)) >= 0.0:
			s.ft = float(s.ft) + dt
			if not s.fired and float(s.ft) >= float(fc.get("fire_at", 0.16)):
				s.fired = true
				var tg = s.get("ftg", null)
				if tg != null and not tg.dead:
					_h4_soul_shot(o, a, fc, s, tg)
			if float(s.ft) >= float(fc.get("anim", 0.32)):
				s.ft = -1.0


## 维什戴尔打出一发炮击：各影子排一发魂炮（正在开火的影子这次不跟）。目标 = 主目标 spread 内优先未标记、影子间不重复的敌人，没有就主目标
static func _h4_souls_sync(o, a: Dictionary, tgt: Dictionary) -> void:
	var sb: Dictionary = _h4_live(o, "verb.souls")
	if sb.is_empty() or not sb.get("follow", false) or int(tgt.get("id", -1)) < 0 or tgt.get("dead", false):
		return
	var fc: Dictionary = _h4_sub(o, sb.get("fire", null))
	if fc.is_empty():
		return
	var wd := _h4wd(o)
	var spread: float = float(fc.get("spread", 120.0)) * o.stat(&"op_range")
	var near: Array = o.nearest_enemies(8, spread, tgt.pos)
	var taken: Array = [tgt.id]
	var q := 0
	for k in wd.souls.size():
		var s: Dictionary = wd.souls[k]
		if float(s.get("ft", -1.0)) >= 0.0 or float(s.get("fq", -1.0)) >= 0.0:
			continue
		var pick: Dictionary = tgt
		for e in near:
			if not e.dead and not e.get("chest", false) and not wd.marks.has(e.id) and not taken.has(e.id):
				pick = e
				break
		taken.append(pick.id)
		s.ftg = pick
		s.fq = float(fc.get("delay", 0.05)) + float(fc.get("gap", 0.08)) * q
		q += 1


static func _h4_soul_home(o, k: int) -> Vector2:
	if k >= 2:   # 可见成长 #129 的副体：本体两侧之外再往外、略高，左右交替
		var side2: float = -1.0 if k % 2 == 0 else 1.0
		return o.pos + Vector2(side2 * (52.0 + 12.0 * int((k - 2) / 2)) - o.face * 6.0, -96.0 + sin(o.g.t * 2.2 + k * 2.0) * 4.0)
	var side: float = -1.0 if k == 0 else 1.0
	return o.pos + Vector2(side * 32.0 - o.face * 6.0, -78.0 + sin(o.g.t * 2.2 + k * 2.0) * 4.0)


## 魂灵之影的目标：range 以内最近的未标记敌人；都标记过就取最近的
static func _h4_soul_target(o, sb: Dictionary) -> Dictionary:
	var wd: Dictionary = o.hw.wd
	var ts: Array = o.nearest_enemies(8, float(sb.get("range", 300.0)), o.pos)
	for e in ts:
		if not wd.marks.has(e.id) and not e.get("chest", false):
			return e
	return ts[0] if not ts.is_empty() else {}


## 爆炸：范围伤害；精一起（shade.cond）被炸死的敌人留下残影，0.25 秒后殉爆并眩晕。light：减量特效；rings：三圈余震
static func _h4_explode(o, a: Dictionary, c: Vector2, dmg: float, r: float, src: String, depth: int, stun: float, light := false, rings := false, kind := "", mark_c = null) -> void:
	var g = o.g
	var killed: Array = []
	var mark_hit: bool = not _h4_sub(o, mark_c).is_empty()
	var low_mark: Dictionary = _h4_sub(o, a.get("lowmark", null)) if kind != "shade" else {}   # docs/202 亡者回响：炮击 / 余震波及的残血敌人直接挂残影标记
	var n_kill := 0
	for e in o.arc_targets(c, 0.0, PI, r):
		o.log_hit(src)
		o.deal_damage(e, dmg)
		if not e.dead and g.rfx.sniper_execute(e, g.hit):
			o.log_hit("真实")
			o.deal_damage(e, e.hp + 1.0)
		if e.dead:
			n_kill += 1
			if not e.get("wis_det", false):   # 带残影标记的敌人已在 on_kill 里殉爆，这里不再重复留残影
				killed.append(e.pos)
		else:
			if stun > 0.0 and not e.boss:
				o.add_cc(e, stun * (0.5 if e.elite else 1.0))
			if mark_hit:   # 亡者回响：凋零处刑炸到的敌人全部挂上残影标记
				_h4_mark(o, a, e)
			if not low_mark.is_empty() and e.hp < e.maxhp * float(low_mark.get("below", 0.3)) and not _h4wd(o).marks.has(e.id):
				_h4_mark(o, a, e)
	if kind == "shade" and n_kill > 0:
		_g202_feedback(o, a, c, n_kill)
	var sh: Dictionary = a.get("shade", {})
	if not _h4_boom_dup(o, c, kind):   # 同一处短时间内只画一次爆炸动画 / 只响一次（10-26 用户）；上面的伤害判定每发都照打
		_h4_boom_visual(o, a, c, r, kind, light, rings)
	var shc: Dictionary = _h4_sub(o, sh)
	if not shc.is_empty() and depth < 1:
		var wd := _h4wd(o)
		for k in mini(killed.size(), 3):
			if wd.shades.size() >= int(sh.get("max", 12)):
				break
			wd.shades.append({"pos": killed[k], "t": _g202_shade_delay(o), "dmg": dmg * float(sh.get("mult", 0.4)), "r": r * float(sh.get("r", 0.8)), "depth": depth + 1})
			o.fx({"kind": "h4_shade", "pos": killed[k], "life": 0.3, "col": H4_DARK})


## 爆炸的画面 + 音效（伤害在 _h4_explode 里先结算，这里只管看和听）
static func _h4_boom_visual(o, a: Dictionary, c: Vector2, r: float, kind: String, light: bool, rings: bool) -> void:
	var g = o.g
	if kind == "quake":
		# 只在地面：双红环 + 裂纹 + 一圈向上的余烬，不闪光不冒烟
		o.fx({"kind": "ring", "pos": c, "r": r, "r0": r * 0.2, "life": 0.35, "col": H4_RED, "floor": true, "w": 3.0})
		o.fx({"kind": "ring", "pos": c, "r": r * 0.65, "r0": r * 0.1, "life": 0.45, "col": Color(1.0, 0.45, 0.35), "floor": true, "w": 2.0})
		if rings:
			o.fx({"kind": "ring", "pos": c, "r": r * 1.3, "r0": r * 0.5, "life": 0.6, "col": Color(1.6, 0.6, 0.3), "floor": true, "w": 4.0})
			_h3_vsparks(o, c, H4_EMBER, 6, 160.0, 0.35, 2.5, -80.0)
		o.fx({"kind": "crack", "pos": c, "r": r * 0.7, "life": 0.35, "col": H4_RED, "floor": true, "n": 7, "ang": c.x * 0.01})
		for k in (4 if light else 8):
			var ox: float = g.vrng.randf_range(-r * 0.6, r * 0.6)
			o.fx({"kind": "spark", "pos": c + Vector2(ox, 0), "vel": Vector2(ox * 0.4, g.vrng.randf_range(-110, -60)), "life": 0.4, "col": H4_RED, "sz": 2.0, "grav": 160.0})
	elif kind == "shade":
		o.fx({"kind": "h4_smoke", "pos": c, "r": r * 0.8, "life": 0.45, "col": H4_DARK})
		h4_impact_fx(o, c, r, light)
	elif kind == "giant":
		h4_burst_fx(o, c, r)
		o.impact_pause(0.05)   # 巨炮落地：短顿帧
	elif kind == "exec":
		h4_burst_fx(o, c, r, true)
	elif kind == "soul":   # 魂炮：同炮击落地，缩到 0.7
		h4_impact_fx(o, c, r * 0.7, true)
	else:
		h4_impact_fx(o, c, r, light)
	if kind == "quake":
		_h3_sfx(o, "quake", 0.0, 1.0, 0.1)
	elif kind == "giant" or kind == "exec":
		_h3_sfx(o, "big", -1.0, 1.0, 0.04)
	else:
		_h3_sfx(o, "hit", -3.0 if light else 0.0, 1.0, 0.08)


## 同一处（半径 fx/boom_dedup_r 以内）fx/boom_dedup_t 秒内已经画过爆炸 / 余震就返回 true（并记数）；余震圈和爆炸动画各记各的，fx/boom_dedup_t = 0 关闭
static func _h4_boom_dup(o, c: Vector2, kind: String) -> bool:
	var win: float = BalW.v("fx/boom_dedup_t", 0.2)
	if win <= 0.0:
		return false
	var wd := _h4wd(o)
	var key: String = "qbooms" if kind == "quake" else "booms"
	var now: float = o.g.t
	var log_: Array = wd[key].filter(func(e): return now - float(e.t) < win)
	var rr: float = BalW.v("fx/boom_dedup_r", 24.0)
	for e in log_:
		if Vector2(e.pos).distance_to(c) <= rr:
			wd[key] = log_
			wd.dup_skipped = int(wd.dup_skipped) + 1
			wd.dup_kinds[kind] = int(wd.dup_kinds.get(kind, 0)) + 1
			return true
	log_.append({"pos": c, "t": now})
	wd[key] = log_
	return false


## 炮击帧条按爆炸半径放大（10-24 范围改版，docs/137 §8）。fx_wisadel_cannon 最亮那帧的实心部分（不透明像素 90 分位）离中心约 37 美术像素，
## 尖刺到 59：倍率 = 判定半径 × fill ÷ 37（实心边落在判定圈上、尖刺伸出圈外），小数部分 > 0.3 就进位（宁大勿小），取整（像素块整齐）
## 并受 vfx.FX_SCALE_MAX 封顶。一团盖不住时（S3 巨炮）改「连环爆」：外圈补 n 团同像素尺度的帧条，实心边到判定圈、几乎同时炸开
## （依次晚 0.02 秒，外圈略淡），再加一道贴地冲击环收边。返回中心一团的实心半径（焦痕按它画）；缺图返回 0。
## 10-24 用户「特效还变小了」：原来按 r × k / 96 换算，实心部分只到判定圈的六七成（S2 约 0.66），改成按实测 37 换算
const H4_BOOM_CORE := 37.0
static func _h4_cannon_sprite(o, c: Vector2, r: float, fill: float) -> float:
	var g = o.g
	var cap: float = floorf(g.vfx.FX_SCALE_MAX)
	var want: float = r * fill / H4_BOOM_CORE
	# 10-26 用户「爆炸半径 78 → 66 之后特效也得跟着变」：原来取整进位（r 66 和 78 都落在 2 档，画面一点没缩，66 的实心边还比判定圈大 12%），
	# 现在实心边直接 = 判定半径 × fill（小数倍率，帧条本来就支持）；fx/boom_scale_exact = 0 回到旧的取整档（对照用）
	var sc: float = clampf(want, 1.0, cap) if BalW.v("fx/boom_scale_exact", 1.0) > 0.0 else clampf(ceilf(want - 0.3), 1.0, cap)
	if not o.spawn_fx_sprite("fx_wisadel_cannon", c, sc):
		return 0.0
	var rv: float = sc * H4_BOOM_CORE
	if want > sc * 1.15:
		var ss: float = clampf(ceilf((r * fill - rv) * 0.5 / H4_BOOM_CORE - 0.3), 1.0, cap)   # 外圈每团：实心直径 ≈ 外圈环带宽度
		var rs: float = ss * H4_BOOM_CORE
		var d: float = maxf(rv * 0.6, r * fill - rs)   # 外圈中心到圆心：实心外沿 ≈ 判定圈
		var n: int = clampi(ceili(TAU * d / (rs * 1.8)), 3, 8)
		var a0: float = g.vrng.randf() * TAU
		for i in n:
			var p: Vector2 = c + Vector2.from_angle(a0 + TAU * i / n) * d
			g.vfx.fx_sprite("fx_wisadel_cannon", p, ss, 0.0, i % 2 == 1, false, Color(1, 1, 1, 0.85), false, Vector2(-1, -1), 0.02 + 0.02 * i)
		o.fx({"kind": "ring", "pos": c, "r": r, "r0": r * 0.5, "life": 0.4, "col": H4_RED, "w": 2.0, "floor": true, "alpha": 0.6})
	return minf(r, rv)


## 落地：Codex 炮击帧条（fx_wisadel_cannon）；缺图保留程序特效（闪光 / 黑烟 / 红环 / 碎片 / 焦痕）
static func h4_impact_fx(o, c: Vector2, r: float, light: bool) -> void:
	var g = o.g
	var rv: float = _h4_cannon_sprite(o, c, r, 0.82 if light else 1.0)
	if rv > 0.0:
		o.fx({"kind": "h4_scorch", "pos": c, "r": rv * 0.7, "life": 1.2, "floor": true})
		return
	o.fx({"kind": "h4_flash", "pos": c, "r": r * 0.7, "life": 0.1})
	o.fx({"kind": "h4_smoke", "pos": c, "r": r * (0.75 if light else 1.0), "life": 0.5, "col": H4_DARK})
	if not light:
		o.fx({"kind": "h4_smoke", "pos": c + Vector2(r * 0.25, -r * 0.2), "r": r * 0.7, "life": 0.6, "col": H4_DARK, "delay": 0.06})
	o.fx({"kind": "ring", "pos": c, "r": r, "r0": r * 0.3, "life": 0.3, "col": H4_RED, "w": 3.0})
	for k in (3 if light else 7):
		var v: Vector2 = Vector2.from_angle(g.vrng.randf() * TAU) * g.vrng.randf_range(90, 210) + Vector2(0, -90)
		o.fx({"kind": "h4_ember", "pos": c, "vel": v, "life": 0.5, "col": Color(0.25, 0.16, 0.18), "sz": 5.0, "ang": g.vrng.randf() * TAU, "spin": 12.0, "grav": 420.0})
	_h3_vsparks(o, c, H4_EMBER, 4 if light else 8, 200.0, 0.3)
	o.fx({"kind": "h4_scorch", "pos": c, "r": r * 0.8, "life": 2.0, "floor": true})


## 饱和炮击 / 凋零处刑的爆炸：Codex 炮击帧条放大；缺图 = 白粉核心星芒 → 放射红刀锋 → 贴地冲击波 + 错落黑烟 → 红色碎刃
static func h4_burst_fx(o, c: Vector2, r: float, small := false) -> void:
	var g = o.g
	var sc: float = 0.7 if small else 1.0
	var rv: float = _h4_cannon_sprite(o, c, r, 1.0)
	if rv > 0.0:
		o.fx({"kind": "h4_scorch", "pos": c, "r": rv * 0.8, "life": 2.0, "floor": true})
		return
	o.fx({"kind": "h4_burst", "pos": c, "r": r * 1.6 * sc, "life": 0.5 if small else 0.55, "seed": g.vrng.randf() * TAU, "n": 8 if small else 12})
	o.fx({"kind": "ring", "pos": c, "r": r * 1.45 * sc, "r0": r * 0.3, "life": 0.28, "col": H4_RED, "floor": true, "w": 2.5, "alpha": 0.75})
	var n: int = 3 if small else 5
	var seed: float = g.vrng.randf() * TAU
	for q in n:
		var ang: float = seed + q * TAU / n + g.vrng.randf_range(-0.45, 0.45)
		var off: Vector2 = Vector2.from_angle(ang) * r * sc * g.vrng.randf_range(0.3, 0.7)
		off.y *= 0.55
		o.fx({"kind": "h4_smoke", "pos": c + off, "r": r * sc * g.vrng.randf_range(0.32, 0.5), "life": g.vrng.randf_range(0.5, 0.75), "col": H4_DARK, "delay": q * 0.035})
	for k in (5 if small else 8):
		var v: Vector2 = Vector2.from_angle(g.vrng.randf() * TAU) * g.vrng.randf_range(120, 260)
		o.fx({"kind": "h4_sliver", "pos": c, "vel": v, "life": 0.45, "col": H4_BOLT, "sz": g.vrng.randf_range(6.0, 11.0), "ang": v.angle(), "drag": 2.5})
	o.fx({"kind": "h4_scorch", "pos": c, "r": r * 0.9, "life": 2.0, "floor": true})


# ---------------------------------------------------------------- 维什戴尔：画面

static func _h4wd_draw_pfx(o, f: Dictionary, a: float) -> bool:
	var cv = o.cv
	match str(f.kind):
		"h4_spmote":   # docs/202 亡者回响·回馈：金色技力光点飞向队友（同推进之王的 h4_spmote，金色光点 + 细尾）
			var kk := 1.0 - a
			var to: Vector2 = f.tgt.pos + Vector2(0, -24)
			var pp: Vector2 = f.start.lerp(to, kk) + Vector2(0, -sin(kk * PI) * 30.0) + f.start.direction_to(to).orthogonal() * sin(kk * PI) * f.bend
			var tail: Vector2 = f.start.lerp(to, maxf(0.0, kk - 0.12)) + Vector2(0, -sin(maxf(0.0, kk - 0.12) * PI) * 30.0)
			cv.draw_line(tail, pp, Color(1.6, 1.3, 0.6, 0.55), 2.0)
			cv.draw_circle(pp, 3.5, Color(2.2, 1.8, 0.9))
			return true
		"h4_muzzle":
			var d: Vector2 = f.dir
			var n: Vector2 = d.orthogonal()
			var L: float = f.sz * (0.6 + 0.4 * a)
			cv.draw_colored_polygon(PackedVector2Array([f.pos + n * 3.0, f.pos + d * L, f.pos - n * 3.0, f.pos - d * 2.0]), Color(H4_RED.r, H4_RED.g, H4_RED.b, 0.7 * a))
			cv.draw_colored_polygon(PackedVector2Array([f.pos + n * 1.4, f.pos + d * L * 0.55, f.pos - n * 1.4]), Color(2.2, 1.2, 0.8, 0.9 * a))
			return true
		"h4_burst":
			var k := 1.0 - a
			var r: float = f.r
			var sd: float = f.seed
			cv.draw_circle(f.pos, r * (0.3 + 0.5 * k), Color(1.3, 0.1, 0.22, 0.4 * a))
			var nq: int = int(f.get("n", 12)) if Dc.hit_spokes() else 0
			for q in nq:
				var h: float = fmod(sd * 7.3 + q * 2.399, 1.0)
				var ang: float = sd + q * TAU / nq + (h - 0.5) * 0.35
				var dv: Vector2 = Vector2.from_angle(ang)
				var nv: Vector2 = dv.orthogonal()
				var L2: float = r * (0.55 + 0.7 * h) * minf(1.0, k * 2.2)
				var w: float = (2.5 + 3.5 * h) * (1.0 - k * 0.7)
				var s0: Vector2 = f.pos + dv * L2 * (0.1 + 0.35 * k)
				var s1: Vector2 = f.pos + dv * L2
				var sm: Vector2 = f.pos + dv * L2 * 0.45
				cv.draw_colored_polygon(PackedVector2Array([s0, sm + nv * w, s1, sm - nv * w]), Color(1.9, 0.1, 0.26, 0.9 * a))
				cv.draw_colored_polygon(PackedVector2Array([s0, sm + nv * w * 0.3, s1, sm - nv * w * 0.3]), Color(2.4, 0.7, 0.8, 0.7 * a))
			var cr: float = r * 0.16 * (1.0 if k < 0.2 else maxf(0.0, 1.0 - (k - 0.2) / 0.45))
			cv.draw_circle(f.pos, cr * 1.8, Color(1.6, 0.1, 0.12, 0.6 * a))
			cv.draw_circle(f.pos, cr, Color(2.2, 0.5, 0.32, a))
			cv.draw_circle(f.pos, cr * 0.45, Color(0.12, 0.02, 0.04, a))
			return true
		"h4_sliver":
			var dv: Vector2 = Vector2.from_angle(f.ang) * f.sz
			var nv: Vector2 = dv.orthogonal().normalized() * 1.6
			cv.draw_colored_polygon(PackedVector2Array([f.pos - dv, f.pos + nv, f.pos + dv, f.pos - nv]), Color(2.2, 0.3, 0.5, a))
			cv.draw_line(f.pos - dv * 0.6, f.pos + dv * 0.6, Color(2.8, 1.4, 1.6, a), 1.0)
			return true
		"h4_flash":
			cv.draw_circle(f.pos, f.r * (0.5 + 0.5 * a), Color(2.0, 0.4, 0.3, 0.75 * a))
			cv.draw_circle(f.pos, f.r * 0.4 * a, Color(2.8, 1.6, 1.2, a))
			return true
		"h4_smoke":
			var age: float = f.max - f.life
			if age < f.get("delay", 0.0):
				return true
			var k := 1.0 - a
			var p: Vector2 = f.pos + Vector2(0, -22.0 * k)
			cv.draw_circle(p, f.r * (0.4 + 0.8 * k), Color(0.14, 0.1, 0.12, 0.6 * a))
			cv.draw_circle(p + Vector2(f.r * 0.25, -f.r * 0.2), f.r * (0.3 + 0.55 * k), Color(0.22, 0.15, 0.17, 0.45 * a))
			cv.draw_circle(p + Vector2(-f.r * 0.2, -f.r * 0.1), f.r * (0.2 + 0.4 * k), Color(0.3, 0.2, 0.22, 0.3 * a))
			return true
		"h4_ember":
			var sv: Vector2 = Vector2.from_angle(f.ang) * f.sz
			cv.draw_colored_polygon(PackedVector2Array([f.pos - sv, f.pos + sv.orthogonal() * 0.45, f.pos + sv]), Color(0.16, 0.08, 0.12, a))
			if not f.get("cold", false):
				cv.draw_circle(f.pos + sv, 1.6, Color(2.0, 0.9, 0.5, a))
			return true
		"h4_scorch":
			cv.draw_set_transform(f.pos, 0.0, Vector2(1.0, 0.5))
			cv.draw_circle(Vector2.ZERO, f.r, Color(0.04, 0.02, 0.03, 0.45 * minf(1.0, a * 2.0)))
			cv.draw_circle(Vector2(f.r * 0.15, 0), f.r * 0.55, Color(0.02, 0.01, 0.02, 0.35 * minf(1.0, a * 2.0)))
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			return true
		"h4_shade":
			var p: Vector2 = f.pos + Vector2(0, -6.0 - 10.0 * (1.0 - a))
			cv.draw_set_transform(p, 0.0, Vector2(1.0, 1.7))
			cv.draw_circle(Vector2.ZERO, 9.0, Color(0.05, 0.03, 0.05, 0.8 * a))
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			cv.draw_circle(p + Vector2(-3, -7), 1.5, Color(2.0, 0.3, 0.3, a))
			cv.draw_circle(p + Vector2(3, -7), 1.5, Color(2.0, 0.3, 0.3, a))
			return true
	return false


## 地面层：落点准星（出膛即出现，随炮弹接近收缩变亮）、余震前兆环
static func _h4wd_draw_floor(o) -> void:
	var cv = o.cv
	var wd: Dictionary = o.hw.wd
	for s in wd.shells:
		var k: float = s.t / s.dur
		var rr: float = lerpf(s.r * 1.5, s.r, k)
		var al: float = 0.25 + 0.55 * k
		cv.draw_set_transform(s.to, 0.0, Vector2(1.0, 0.55))
		cv.draw_arc(Vector2.ZERO, rr, 0.0, TAU, 28, Color(H4_RED.r, H4_RED.g, H4_RED.b, al), 1.5)
		for q in 4:
			var dv := Vector2.from_angle(q * PI / 2.0)
			cv.draw_line(dv * rr * 0.55, dv * rr * 0.85, Color(H4_RED.r, H4_RED.g, H4_RED.b, al), 2.0)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for q in wd.quakes:
		if q.t > 0.45:
			continue
		var a: float = 1.0 - q.t / 0.45
		cv.draw_set_transform(q.pos, 0.0, Vector2(1.0, 0.55))
		cv.draw_arc(Vector2.ZERO, q.r * (0.25 + 0.2 * a), 0.0, TAU, 20, Color(H4_RED.r, H4_RED.g, H4_RED.b, 0.5 * a), 2.0)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 技能上层：彗星弹体（一整条连续轮廓）、残影标记（魂灵之影改在本体后层，见 h4wd_draw_back）
static func _h4wd_draw_over(o) -> void:
	var cv = o.cv
	var wd: Dictionary = o.hw.wd
	for s in wd.shells:
		var p: Vector2 = _h4_shell_at(s, s.t / s.dur)
		var pts: Array = []
		for q in s.hist:
			if pts.is_empty() or q.distance_to(pts[-1]) > 1.0:
				pts.append(q)
		if pts.is_empty() or p.distance_to(pts[-1]) > 1.0:
			pts.append(p)
		var wk: float = 1.0 + (float(s.get("size", 1.0)) - 1.0) * 0.6
		if _h4_draw_shell_tex(o, s, p):
			continue
		if pts.size() < 2:
			cv.draw_circle(p, 5.5 * wk, Color(0.16, 0.02, 0.04))
			continue
		cv.draw_colored_polygon(_h4_comet(pts, 11.0 * wk), Color(1.2, 0.08, 0.1, 0.3))
		cv.draw_colored_polygon(_h4_comet(pts, 7.5 * wk), Color(0.34, 0.03, 0.06, 0.95))
		cv.draw_colored_polygon(_h4_comet(pts, 4.0 * wk), Color(0.1, 0.01, 0.03, 1.0))
	_h4wd_draw_marks(o)
	# 魂灵之影不在这里画：10-20 用户要求放在干员身后，改由本体后层 ObHw.hw_draw_body(front=false) 画


## 魂炮的小炮弹（Codex proj_wisadel_soul_shell，沿飞行方向转）；缺图画小一号的彗星
static func _h4_draw_shell_tex(o, s: Dictionary, p: Vector2) -> bool:
	if str(s.get("kind", "")) != "soul":
		return false
	var g = o.g
	if g.tex.get("proj_wisadel_soul_shell") != null:
		o.draw_spr_rot("proj_wisadel_soul_shell", int(g.t * 20.0) % 2, p, (s.to - s.from).angle(), g.PX)
		return true
	o.cv.draw_circle(p, 6.0, Color(1.0, 0.1, 0.25, 0.3))
	o.cv.draw_circle(p, 3.5, Color(0.2, 0.02, 0.08))
	return true


static func _h4wd_draw_marks(o) -> void:
	var g = o.g
	var cv = o.cv
	for k in o.hw.wd.marks:
		var mk: Dictionary = o.hw.wd.marks[k]
		var e: Dictionary = mk.e
		if e.dead:
			continue
		if mk.t < 0.6 and fmod(mk.t * 8.0, 1.0) < 0.35:
			continue
		var p: Vector2 = e.pos + Vector2(0, -e.r - 18.0 + sin(g.t * 4.0 + e.id) * 2.0)
		cv.draw_circle(p, 9.0, Color(0.9, 0.05, 0.1, 0.18))
		if _h4_draw_gift(o, mk, p):
			continue
		if o._fx_strip("fx_wisadel_mark", 2, int(g.t * 4.0 + e.id * 0.5), p):
			continue
		_h4_shade_body(o, p, 5.5, 0.85)


## 好礼挂的标记：Codex fx_wisadel_gift_mark（比普通标记多一圈礼花状缎带）；缺图画普通标记
static func _h4_draw_gift(o, mk: Dictionary, p: Vector2) -> bool:
	if not mk.get("gift", false):
		return false
	var g = o.g
	return o._fx_strip("fx_wisadel_gift_mark", 6, int(g.t * 10.0 + float(mk.e.id) * 0.5), p)


## 本体后层（ObHw.hw_draw_body front=false）：魂灵之影画在维什戴尔身后（10-20 用户：「魂灵之影的图层要在干员的后面」）；
## 与本体一起按 y 排序，纯画面
static func h4wd_draw_back(o) -> void:
	_h4wd_draw_souls(o)


static func _h4wd_draw_souls(o) -> void:
	var g = o.g
	var cv = o.cv
	var souls: Array = o.hw.wd.souls
	for i in souls.size():
		var s: Dictionary = souls[i]
		var p: Vector2 = s.p
		var native := _h4_soul_native(o, i, s)
		if o._fx_tex("fx_wisadel_soul") != null:
			cv.draw_circle(p, 18.0, Color(1.0, 0.06, 0.12, 0.2 + 0.06 * sin(g.t * 6.0)))
			if str(s.st) == "go":
				var tg = s.tgt
				var fl: bool = tg != null and not tg.dead and tg.pos.x < p.x
				o._fx_strip("fx_wisadel_soul", 6, 4 + mini(1, int((g.t - float(s.get("gt", g.t))) * 12.0)), p, Vector2(0.5, 0.5), 0.0, Color.WHITE, fl)
			else:
				var sub: bool = s.get("sub", false)
				var sk: float = WdVg.summon_scale(g) * (WdVg.kn("sub_scale", 0.85) if sub else 1.0)
				var scol: Color = Color(1.25, 1.2, 1.3, 0.85) if sub else Color.WHITE   # 副体：同款贴图、略浅、小一号
				if native.is_empty():
					o._fx_strip("fx_wisadel_soul", 6, (int(g.t * 8.0) + i * 2) % 4, p, Vector2(0.5, 0.5), 0.0, scol)
				else:
					o.draw_sprite_at(p, false, scol, native[1], native[0], native[2], o.foot_off(native[0], native[3]), sk)
			continue
		var tail := PackedVector2Array()
		for q in 5:
			tail.append(p + Vector2(sin(g.t * 5.0 + q * 0.9) * (1.0 + q), 8.0 + q * 4.0))
		cv.draw_polyline(tail, Color(0.08, 0.03, 0.05, 0.7), 5.0)
		cv.draw_circle(p, 18.0, Color(1.0, 0.06, 0.12, 0.2 + 0.06 * sin(g.t * 6.0)))
		_h4_shade_body(o, p, 9.5, 0.95)


## 魂灵之影原生身体（docs/108 §3、docs/107 显示时钟；纯画面，状态只写 wd.vis，玩法不读）：
## 首次出现 / 离场后重新上场播 native_soul_start → 常驻 soul_idle 循环；魂炮开火不换动作（10-21 用户：不需要攻击帧，直接发射），
## 身体时间线照常走，出膛只有炮口烟（_h4_soul_shot）。
## 离场（data_operator.on_leave → h4_souls_leave）在原地播 native_soul_die。返回 mf_visual_frame 的 [tex, 帧, 帧数, 槽]，缺图为空
static func _h4_soul_native(o, k: int, s: Dictionary) -> Array:
	var g = o.g
	var wd: Dictionary = o.hw.wd
	if not wd.has("vis"):
		wd["vis"] = []
	var vis: Array = wd.vis
	while vis.size() <= k:
		vis.append({})
	var st: Dictionary = vis[k]
	if g.t - float(st.get("seen", -99.0)) > 0.25:
		SummonVisual.start(st, o.sprite_spec("native_soul_start").get("visual", {}), g.t)
		st["fire"] = false
	st["seen"] = g.t
	return mf_visual_frame(o, st, "soul_idle", g.t + k * 0.25)


## 离场：每个魂灵之影在原地播一次 native_soul_die（世界特效，纯画面）；下次上场重播出场
static func h4_souls_leave(o) -> void:
	if not o.hw.has("wd"):
		return
	for s in o.hw.wd.souls:
		o.spawn_fx_sprite("op_wisadel_soul_native_die", s.p, o.g.PX)
	o.hw.wd.erase("vis")


static func _h4_shade_body(o, p: Vector2, r: float, al: float) -> void:
	var cv = o.cv
	cv.draw_set_transform(p, 0.0, Vector2(1.0, 1.7))
	cv.draw_circle(Vector2.ZERO, r, Color(0.05, 0.03, 0.05, al))
	cv.draw_arc(Vector2.ZERO, r, 0.0, TAU, 20, Color(1.2, 0.12, 0.16, 0.8 * al), 1.2)
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var ey: float = -r * 0.75
	cv.draw_circle(p + Vector2(-r * 0.35, ey), maxf(1.2, r * 0.18), Color(2.2, 0.3, 0.3, al))
	cv.draw_circle(p + Vector2(r * 0.35, ey), maxf(1.2, r * 0.18), Color(2.2, 0.3, 0.3, al))


## 彗星轮廓：pts 从尾到头；半宽按 u^1.3 从 0 平滑增到 hw，头部接半圆帽
static func _h4_comet(pts: Array, hw: float) -> PackedVector2Array:
	var n: int = pts.size()
	var L := PackedVector2Array()
	var R := PackedVector2Array()
	for i in n:
		var a0: Vector2 = pts[maxi(i - 1, 0)]
		var a1: Vector2 = pts[mini(i + 1, n - 1)]
		var nv: Vector2 = (a1 - a0).normalized().orthogonal()
		var u: float = float(i) / float(n - 1)
		var w: float = hw * pow(u, 1.3)
		L.append(pts[i] + nv * w)
		R.append(pts[i] - nv * w)
	var head: Vector2 = pts[n - 1]
	var dir: Vector2 = (pts[n - 1] - pts[n - 2]).normalized()
	var out := PackedVector2Array()
	out.append_array(L)
	var a_start: float = dir.orthogonal().angle()
	for k in range(1, 8):
		out.append(head + Vector2.from_angle(a_start + PI * k / 8.0) * hw)
	R.reverse()
	out.append_array(R)
	return out


static func h4_phase_shot(o, a: Dictionary, round_: Dictionary, muzzle: int) -> void:
	var effect: Dictionary = o.B.skills[o.phases.skill].attack_effect
	var reach: float = _h4_wd_reach(o, a, float(effect.get("aim_r", 540.0)))
	var target: Dictionary = {}
	if round_.target == "random":
		target = o.random_enemy(reach, o.pos)
	else:
		target = _h4_wd_target(o, a, reach) if o.atk_aim == Vector2.ZERO else o.aim_land(reach)
	if target.is_empty():
		return
	var mult: float = float(round_.damage_mult)
	var slot: String = str(round_.anim)
	var spec: Dictionary = o.sprite_spec(slot)
	var frame: int = o.attack_phase_frame(int(spec.frames), int(spec.fire), o.attack_dur - o.attack_t)
	var origin: Vector2 = o.sprite_point_at(slot, "muzzles", frame, muzzle, null, false)
	_h4_fire(o, a, target.pos, o.base(str(a.get("atk_key", "atk")), 0.0) * mult * o.skill_power(), str(effect.src), float(effect.size), true, 0.0, false, false, "exec", effect.get("mark", null), origin)
	o.fx({"kind": "h4_muzzle", "pos": origin, "dir": (target.pos-origin).normalized(), "life": 0.07, "col": H4_RED, "sz": 18.0})
	_h3_sfx(o, "atk", 2.0)
	_h4_cannon_after(o, a, target)
	if muzzle == 0:
		_h4_souls_sync(o, a, target)



static func h4_phase_validate(sb: Dictionary, p: String, ctx: Dictionary, attack, i: int) -> void:
	if not attack is Dictionary:
		return
	if str(attack.get("shape", "")) != "cannon":
		if sb.has("attack_effect"):
			ctx.errs.append(p + ".attack_effect requires cannon")
		return
	var effect = sb.get("attack_effect")
	if not effect is Dictionary:
		ctx.errs.append(p + ".attack_effect must configure the cannon adapter")
		return
	_src(effect, p + ".attack_effect", ctx, true)
	_num(effect, "size", p + ".attack_effect", ctx, true, 0.01, 20.0)
	_num(effect, "aim_r", p + ".attack_effect", ctx, true, 1.0, 2000.0)
	var stages = sb.attack_phases
	var sequences = ctx.sprites.get("skills", {})
	var sequence = sequences.get("s%d" % (i + 1), {}) if sequences is Dictionary else null
	if not sequence is Dictionary:
		return
	var animations = sequence.get("phases", [])
	if not stages is Array or not animations is Array or stages.size() != animations.size():
		return
	for j in stages.size():
		if not stages[j] is Dictionary or not animations[j] is Dictionary:
			continue
		var count := eval_expr(stages[j].get("burst", 0), ctx.base)
		var spec = ctx.sprites.get(animations[j].get("attack", ""), {})
		if not spec is Dictionary:
			ctx.errs.append(p + ".attack_phases cannon strip must be an object")
			continue
		var muzzles = spec.get("muzzles", [])
		if not spec.get("foot") is Array or spec.get("foot", []).size() != 2 or not spec.has("fire") or not preload("res://scripts/characters/blocks/attack_phases.gd").positive_number(spec.get("frames")) or not muzzles is Array or muzzles.size() != int(spec.get("frames", 0)):
			ctx.errs.append(p + ".attack_phases cannon strip requires foot/fire and per-frame muzzles")
			continue
		for frame in muzzles:
			if not frame is Array or frame.size() < int(count[1]):
				ctx.errs.append(p + ".attack_phases cannon muzzle count is smaller than burst")
				continue
			for point in frame:
				if not point is Array or point.size() != 2 or not (point[0] is float or point[0] is int) or not (point[1] is float or point[1] is int) or not is_finite(float(point[0])) or not is_finite(float(point[1])):
					ctx.errs.append(p + ".attack_phases cannon muzzle must be [x,y]")
