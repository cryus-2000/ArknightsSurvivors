## 干员连携技（docs/160，用户 10-26 定稿：技能联动 β、合击动作要看得见、不提醒）：
## 编队里一名干员的技能出手（Character.spend_sp → Squad.syn_skill），原作有关系的搭档立刻做一次真实的合击动作：
##   volley       搭档原地朝目标打一轮弹（可见弹道）                         德克萨斯 → 能天使「默契」
##   dash_strike  搭档冲到目标面前一击（真实位移，冲刺中短暂无敌）            其余几对 + 集群狩猎
##   hook         搭档甩钩把目标拉近一击                                    归溟幽灵鲨 → 歌蕾蒂娅
## 每次触发：两人之间一道连线、搭档的合击动作、搭档一句原作台词（缺素材静默）、头顶一行小字连携名（原作出处名）。
## 数据：data/synergy.json（pairs 一对一条，groups 群体一条）；总开关 balance.json synergy/on（0 = 完全不求值，TRACE 与没有连携时逐行相同）。
## 约束（docs/160 §4）：每对冷却 cd（两个方向合计）、同时进行最多 synergy/max_active 条、不抽随机数（目标取最近的敌人）、
## 队长当搭档时不位移（dash_strike / 集群狩猎里的队长跳过，volley / hook 照常）。
extends RefCounted

const BalS = preload("res://scripts/core/balance.gd")
const PATH := "res://data/synergy.json"
static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var j = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = j if j is Dictionary else {"pairs": [], "groups": []}
	return _data


static func on() -> bool:
	return BalS.vi("synergy/on", 1) > 0


static func _col(a, k := 1.0) -> Color:
	return Color(float(a[0]) * k, float(a[1]) * k, float(a[2]) * k)


## ---- 入口 1：某干员放了技能（squad.syn_skill）
static func on_skill(sq, o, i: int) -> void:
	if not on() or o.pos == Vector2.INF:
		return
	var g = o.g
	if g.demo_op != "" or g.state != g.S.PLAY:
		return
	var d: Dictionary = data()
	for pr in d.get("pairs", []):   # 控场 → 收割（dash_cast，R6）最优先：猎人 ≥ 3 人时也不被集群狩猎吃掉
		for dr in pr.dirs:
			if str(dr.kind) == "dash_cast" and str(dr.from) == str(o.id) and _has_skill(dr.skills, i) and _pair_try(sq, o, pr, dr):
				return
	for gr in d.get("groups", []):
		if str(o.id) in gr.members and _has_skill(gr.skills, i) and _group_try(sq, o, gr, i):
			return   # 猎人 ≥ 3 人时集群狩猎取代两人的潮汐守望，不叠
	for pr in d.get("pairs", []):
		for dr in pr.dirs:
			if str(dr.kind) != "dash_cast" and str(dr.from) == str(o.id) and _has_skill(dr.skills, i):
				_pair_try(sq, o, pr, dr, i)   # 一人可参与多条（德克萨斯：默契 + 恩怨），同时进行上限由 _active 管


## json 数字读出来是 float，Array.has(int) 对 0.0 不一定认，逐个转 int 比
static func _has_skill(arr, i: int) -> bool:
	for x in arr:
		if int(x) == i:
			return true
	return false


static func _active(sq) -> int:
	var seen := {}
	for a in sq.syn.acts:
		seen[a.gid] = true
	return seen.size()


static func _ready_partner(sq, cid: String) -> Variant:
	var p = sq.get_op(cid)
	if p == null or p.pos == Vector2.INF or p.cmd_down > 0.0 or not p.syn_mv.is_empty():
		return null
	return p


## 精英 / Boss 优先（用户 10-26「控场 → 收割对精英怪释放更合理」）：列表（已按距离排好）里先取 Boss，其次第一个精英，都没有取第一个活的
static func _pri(list: Array) -> Variant:
	var elite: Variant = null
	var first: Variant = null
	for e in list:
		if e.dead:
			continue
		if first == null:
			first = e
		if e.boss:
			return e
		if elite == null and e.elite:
			elite = e
	return elite if elite != null else first


## 目标：施放者周围（nearest_enemies 已按指挥优先级排序、不抽随机数）搭档够得着的敌人里，精英 / Boss 优先，没有精英就取最近的
static func _pick_target(o, p, reach: float) -> Variant:
	var cand: Array = []
	for e in o.nearest_enemies(8, 460.0, o.pos):
		if not e.dead and p.pos.distance_to(e.pos) <= reach:
			cand.append(e)
	return _pri(cand) if not cand.is_empty() else null


static func _pair_try(sq, o, pr: Dictionary, dr: Dictionary, skill := -1) -> bool:
	var g = o.g
	var st: Dictionary = sq.syn
	if g.t < float(st.cd.get(str(pr.id), -99.0)) or _active(sq) >= BalS.vi("synergy/max_active", 2):
		return false
	var p: Variant = _ready_partner(sq, str(dr.to))
	if p == null or (p.is_leader and str(dr.kind) != "volley" and str(dr.kind) != "hook"):
		return false   # 队长不位移；队长是乌尔比安且技能手动档时更不替玩家放（dash_cast 的队长搭档直接跳过）
	var tgt: Variant = _pick_target(o, p, float(dr.range))
	if tgt == null:
		return false
	st.cd[str(pr.id)] = g.t + float(pr.cd) * BalS.v("synergy/cd_mult", 1.0)
	st.n += 1
	var gid: int = st.n
	_announce(sq, pr, dr, o, p)
	sq.syn.acts.append(_act(gid, pr, dr, o, p, tgt, 0.0, _cl(dr, skill if skill >= 0 else _first_skill(dr))))
	return true


## 控场技能（dr.cluster_skills，如歌蕾蒂娅 S3 聚怪）出手时，合击落在聚怪中心而不是最近的那一只
static func _cl(dr: Dictionary, skill: int) -> bool:
	return dr.has("cluster") and (not dr.has("cluster_skills") or _has_skill(dr.cluster_skills, skill))


static func _first_skill(dr: Dictionary) -> int:
	return int((dr.skills as Array)[0]) if not (dr.skills as Array).is_empty() else 0


static func _group_try(sq, o, gr: Dictionary, skill := -1) -> bool:
	var g = o.g
	var st: Dictionary = sq.syn
	if g.t < float(st.cd.get(str(gr.id), -99.0)) or _active(sq) >= BalS.vi("synergy/max_active", 2):
		return false
	var hunters: Array = []
	for cid in gr.members:
		var h = sq.get_op(str(cid))
		if h != null and h.cmd_down <= 0.0 and h.pos != Vector2.INF:
			hunters.append(h)
	if hunters.size() < int(gr.min):
		return false
	var movers: Array = hunters.filter(func(h): return h != o and not h.is_leader and h.syn_mv.is_empty())
	if movers.is_empty():
		return false
	var tgt: Variant = _pick_target(o, movers[0], float(gr.range))
	if tgt == null:
		return false
	st.cd[str(gr.id)] = g.t + float(gr.cd) * BalS.v("synergy/cd_mult", 1.0)
	st.n += 1
	var gid: int = st.n
	_announce(sq, gr, gr, o, movers[0])
	var k := 0
	for h in movers:
		sq.syn.acts.append(_act(gid, gr, gr, o, h, tgt, float(gr.stagger) * k, gr.has("cluster") and _has_skill(gr.get("cluster_skills", []), skill) and skill >= 0))
		k += 1
	if float(gr.get("mark", 0.0)) > 0.0:   # 集群狩猎：同一目标在窗口里多吃一点伤害（沿用铃兰「印记」的受伤加成通道，取较大值不叠）
		tgt["frag_t"] = maxf(float(tgt.get("frag_t", 0.0)), g.t + float(gr.mark_t))
		tgt["frag_v"] = maxf(float(tgt.get("frag_v", 0.0)), float(gr.mark))
	return true


static func _act(gid: int, pr: Dictionary, dr: Dictionary, o, p, tgt, delay: float, cl := false) -> Dictionary:
	return {"cl": cl, "gid": gid, "pr": pr, "dr": dr, "from": o, "p": p, "tgt": tgt, "tpos": tgt.pos, "age": 0.0, "delay": delay, "phase": 0, "shots": 0, "t_phase": 0.0}


## 连线 + 头顶小字 + 台词（每次触发一次）
static func _announce(sq, pr: Dictionary, dr: Dictionary, o, p) -> void:
	var g = o.g
	var c: Color = _col(dr.col)
	g.fx.append({"kind": "beam", "a": o.pos + Vector2(0, -26), "b": p.pos + Vector2(0, -26), "life": 0.5, "max": 0.5, "col": c, "w": 2.0})
	g.vfx.add_text(g.ppos + Vector2(0, -118), str(pr.name), c.lerp(Color.WHITE, 0.4), 12)
	var sfx: Node = g.get_node_or_null("/root/Sfx") if g.is_inside_tree() else null
	var vk: String = str((dr.get("voice_map", {}) as Dictionary).get(str(p.id), dr.get("voice", "")))
	if sfx != null and vk != "":
		sfx.voice(str(p.id), vk, false, true)


## 伤害来源登记（按「连携名·干员」，进作战记录的输出统计）
static func _src(p, pr: Dictionary, dr: Dictionary) -> String:
	var k: String = "连携·%s·%s" % [str(pr.name), str(p.id)]
	if not p.g.hit_src.has(k):
		p.g.hit_src[k] = {"emitter": "operator", "origin": "skill", "range": str(dr.get("rng", "近战")), "kind": str(dr.get("kind_dmg", "物理")),
			"tags": ["skill", "连携"], "class": p.cls, "op": p.id}
	return k


static func _dmg(p, mult: float) -> float:
	var ld := 1.0
	var loc = p.get("loc")
	if loc is Dictionary:
		ld = float(loc.get("dmg", 1.0))
	return p.base("atk", 0.0) * mult * ld * p._dmg_bonus() * BalS.v("synergy/dmg_mult", 1.0)


## ---- 入口 2：每帧（squad.update，在干员 follow 之前，搭档的 syn_mv 当帧就生效）
static func tick(sq, dt: float) -> void:
	var acts: Array = sq.syn.acts
	if acts.is_empty():
		return
	for k in range(acts.size() - 1, -1, -1):
		var a: Dictionary = acts[k]
		if a.delay > 0.0:
			a.delay -= dt
			continue
		a.age += dt
		var done := false
		match str(a.dr.kind):
			"volley":
				done = _step_volley(a, dt)
			"dash_strike", "dash_cast":
				done = _step_dash(a, dt)
			"hook":
				done = _step_hook(a, dt)
			_:
				done = true
		if done:
			if not a.p.syn_mv.is_empty():
				a.p.syn_mv = {}
			acts.remove_at(k)


static func _alive(a: Dictionary) -> bool:
	return a.p != null and a.p.pos != Vector2.INF and a.p.cmd_down <= 0.0


## 目标死了就朝它死前的位置打（动作做完整，伤害落在那一带的敌人身上）
static func _tpos(a: Dictionary) -> Vector2:
	if a.tgt != null and not a.tgt.dead:
		a.tpos = a.tgt.pos
		if a.cl:   # 聚怪中心（聚怪涡 / 钩锁把怪拉拢以后）：聚怪范围里有精英 / Boss 就瞄它，没有再取敌人最密处
			var cdr: Dictionary = a.dr if a.dr.has("cluster") else a.pr
			var near: Array = a.p.nearest_enemies(16, float(cdr.cluster) * 1.6, a.tgt.pos)
			var top: Variant = _pri(near)
			if top != null and (top.boss or top.elite):
				a.tgt = top
				a.tpos = top.pos
			else:
				var c: Vector2 = a.p.densest_point(float(cdr.cluster), a.tgt.pos)
				if c != Vector2.INF:
					a.tpos = c
	return a.tpos


static func _step_volley(a: Dictionary, dt: float) -> bool:
	var dr: Dictionary = a.dr
	var p = a.p
	if not _alive(a):
		return true
	if a.age < float(dr.wind):
		return false
	var g = p.g
	if a.shots == 0 and not a.get("vstart", false):
		a["vstart"] = true
		if dr.get("prefer_stun", false):   # 控场 → 收割：剑雨的眩晕落下之后，改打被晕的怪（离原目标最近的一只）
			var stunned: Array = a.from.nearest_enemies(12, float(dr.range), a.from.pos).filter(func(e): return float(e.get("stun", 0.0)) > 0.0 and not e.dead)
			if not stunned.is_empty():
				stunned.sort_custom(func(x, y): return x.pos.distance_squared_to(a.tpos) < y.pos.distance_squared_to(a.tpos))
				var top: Variant = _pri(stunned)   # 被晕的这一批里精英 / Boss 优先，没有精英取离原目标最近的
				a.tgt = top
				a.tpos = top.pos
		if dr.get("cast", false) and not p.is_leader:   # 搭档的技能正好就绪（自动档、够门槛）就对准放出去；没就绪就照常打弹，不白送技能、不回技力
			var idx: int = int(p.charge_skills(0.0))
			if idx >= 0 and p.acting() and float(a.get("cwait", 0.0)) < 0.6:
				a["cwait"] = float(a.get("cwait", 0.0)) + dt   # 搭档正在出手：最多等 0.6 秒，等他收手再放技能
				a["vstart"] = false
				return false
			if idx >= 0 and not p.acting():
				p.start_skill(p.ObSummon.mf_skill_aim(p, idx), idx)
				p.face_to((_tpos(a) - p.pos).angle())
				return true
	var due: int = mini(int(dr.n), 1 + int((a.age - float(dr.wind)) / maxf(0.02, float(dr.gap))))
	while a.shots < due:
		a.shots += 1
		var tp: Vector2 = _tpos(a)
		var from: Vector2 = p.pos + Vector2(float(p.face) * 14.0, -24.0)
		var c: Color = _col(dr.col)
		g.fx.append({"kind": "tracer", "a": from, "b": tp + Vector2(0, -8), "life": 0.16, "max": 0.16, "col": c, "wid": 6.0})
		p.sparks(from, (tp - from).normalized(), c, 3, 120.0)
		p._set_face(1.0 if tp.x >= p.pos.x else -1.0)
		if a.shots == 1:
			p.play_vis_anim("attack")
		var hits: Array = p.nearest_enemies(1, 56.0, tp)
		if not hits.is_empty():
			p.log_hit(_src(p, a.pr, dr), ["连携"])
			p.deal_damage(hits[0], _dmg(p, float(dr.mult)))
			p.sparks(hits[0].pos, (tp - from).normalized(), c, 2, 90.0)
	return a.shots >= int(dr.n)


static func _step_dash(a: Dictionary, dt: float) -> bool:
	var dr: Dictionary = a.dr
	var p = a.p
	if not _alive(a):
		return true
	var g = p.g
	if a.phase == 0:
		if a.age < float(dr.wind):
			return false
		var tp: Vector2 = _tpos(a)
		var p0: Vector2 = p.pos
		var dv: Vector2 = tp - p0
		if dv.length() > float(dr.range) * 1.25 or p.is_leader:
			return true   # 够不着 / 队长不位移：不做
		var dir: Vector2 = dv.normalized()
		var rt: float = float(a.tgt.r) if a.tgt != null else 14.0
		var stop: Vector2 = tp - dir * (rt + float(dr.gap))
		if g.get("map") != null and g.map.segment_blocked(p0, stop):
			return true
		a["stop"] = stop
		a["dir"] = dir
		p.syn_mv = {"from": p0, "to": stop, "t": 0.0, "dur": float(dr.dur)}
		p.cmd_inv = maxf(p.cmd_inv, float(dr.dur) + 0.4)
		p._set_face(1.0 if dir.x >= 0.0 else -1.0, true)
		var c: Color = _col(dr.col)
		g.fx.append({"kind": "tracer", "a": p0 + Vector2(0, -20), "b": stop + Vector2(0, -20), "life": float(dr.dur) + 0.14, "max": float(dr.dur) + 0.14, "col": c, "wid": 8.0})
		if dr.get("strip", "") != "" and g.V6_FRAMES.has(str(dr.strip)):
			var fr: Array = g.V6_FRAMES[str(dr.strip)]
			p.fx({"kind": "tx_strip", "strip": str(dr.strip), "frames": int(fr[0]), "fps": float(fr[1]), "pos": stop, "ang": dir.angle(), "sx": p0.distance_to(stop) / 128.0,
				"anchor": Vector2(63.0 / 64.0, 0.5), "life": float(fr[0]) / float(fr[1]) + float(dr.dur) * 0.5, "delay": float(dr.dur) * 0.5})
		a.phase = 1
		a.t_phase = a.age
		return false
	if a.phase == 1:
		if a.age - a.t_phase < float(dr.dur):
			return false
		var stop: Vector2 = a.stop
		var tp: Vector2 = _tpos(a)
		var ang: float = (tp - stop).angle()
		var c: Color = _col(dr.col)
		var half: float = float(dr.half)
		var rr: float = float(dr.r)
		if str(dr.kind) == "dash_cast" and not p.is_leader:
			# 控场 → 收割：搭档的技能正好就绪（自动档、够门槛）就对准这群怪放出去；没就绪就打一次冲锋重击，不白送技能、不回技力
			var idx: int = int(p.charge_skills(0.0))
			if idx >= 0 and p.acting() and float(a.get("cwait", 0.0)) < 0.5:
				a["cwait"] = float(a.get("cwait", 0.0)) + dt   # 搭档正在出手：最多等 0.5 秒（原地停在落点），等他收手再放技能
				return false
			if idx >= 0 and not p.acting():
				p.syn_mv = {}
				p.start_skill(p.ObSummon.mf_skill_aim(p, idx), idx)
				p.face_to(ang)
				g.fx.append({"kind": "ring", "pos": tp, "r": rr, "r0": rr * 0.4, "life": 0.3, "max": 0.3, "col": c, "floor": true, "w": 2.0, "alpha": 0.6})
				a.phase = 2
				a.t_phase = a.age
				return false
		p.melee_hit(_src(p, a.pr, dr), stop, ang, half, rr, _dmg(p, float(dr.mult)), float(dr.kb), float(dr.get("stun", 0.0)), ["连携"], 0)
		p.slash_fx(stop, ang, minf(half, 1.5), rr * 0.9, c, "slash", 0.26)
		if dr.get("cross", false):   # 两人刀光交叉：施放者的刀光从另一个角度也落在目标处（只有画面，伤害只算搭档这一击）
			var cf = a.from
			p.slash_fx(tp, ang + 1.25, 1.1, rr * 0.85, Color(1.0, 0.85, 0.5), "slash", 0.26)
			if cf != null and cf.pos != Vector2.INF:
				cf.play_vis_anim("attack")
		if dr.get("chain", false):   # 锚链：从搭档到目标一道细光
			g.fx.append({"kind": "beam", "a": stop + Vector2(0, -20), "b": tp + Vector2(0, -12), "life": 0.3, "max": 0.3, "col": c, "w": 2.5})
		g.fx.append({"kind": "ring", "pos": tp, "r": rr, "r0": rr * 0.4, "life": 0.3, "max": 0.3, "col": c, "floor": true, "w": 2.0, "alpha": 0.6})
		p.sparks(tp, a.dir, c, 6, 160.0)
		p.play_vis_anim("attack")
		p.screen_shake(0.12)
		a.phase = 2
		a.t_phase = a.age
		return false
	return a.age - a.t_phase >= 0.22   # 收势停一下再回编队位（follow 自己拉回去）


static func _step_hook(a: Dictionary, dt: float) -> bool:
	var dr: Dictionary = a.dr
	var p = a.p
	if not _alive(a):
		return true
	if a.age < float(dr.wind):
		return false
	var g = p.g
	var tp: Vector2 = _tpos(a)
	var c: Color = _col(dr.col)
	var from: Vector2 = p.pos + Vector2(0, -24.0)
	g.fx.append({"kind": "beam", "a": from, "b": tp + Vector2(0, -8), "life": 0.32, "max": 0.32, "col": c, "w": 3.0})
	p._set_face(1.0 if tp.x >= p.pos.x else -1.0)
	p.play_vis_anim("attack")
	var hits: Array = p.nearest_enemies(1, 56.0, tp)
	if not hits.is_empty():
		var e: Dictionary = hits[0]
		p.log_hit(_src(p, a.pr, dr), ["连携"])
		p.deal_damage(e, _dmg(p, float(dr.mult)))
		if not e.dead and not e.boss:
			var pull: Vector2 = (p.pos - e.pos).limit_length(float(dr.pull))
			p.nudge(e, pull)
			if float(dr.get("stun", 0.0)) > 0.0:
				p.add_cc(e, float(dr.stun) * (0.5 if e.elite else 1.0))
		p.sparks(e.pos, (p.pos - e.pos).normalized(), c, 5, 130.0)
	return true
