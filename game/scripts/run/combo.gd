## 连携技（docs/198 §5 / §6.2）：20 人触发条件 + 冲到目标出招再回队 + 原作关系组合升级。框架（亮起、排队、E、冷却、能量与协同）在 run/ult.gd（u）。
## 动作四种（a.k）：dash 冲到目标出招（syn_mv 位移 + 短暂无敌，结束由编队跟随拉回）、volley 原地扫射、hook 甩钩拖拽、cast 原地投射到落点；
## 落地后还要持续的部分（熔岩、晶柱、余震、托举、不倒）另挂一段 linger（p = null，不占干员）。
## 四类触发（§5.1）：A 跟队长动作（ev.dash_start_t / dash_end_t / leader_still_t），B 跟敌人状态，C 跟队长危险，D 跟队友连携（ev.hits / 安洁莉娜读亮起）。
## 事件类判定按事件时刻记账（_st(u).used），同一事件只亮一次；不抽随机数，目标按 nearest_enemies / 敌人数组顺序取。
## 组合升级（§6.2）：自动接的那段走 u.add_act（不亮、不占冷却、不再计能量 / 协同、不再触发别人的 D 类），同一名干员同一时间只做一段。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")

const CLS := {
	"texas": "A", "exusiai": "A", "skadi": "A", "siege": "A", "eyjafjalla": "A",
	"irene": "B", "lappland": "B", "logos": "B", "mizuki": "B", "gladiia": "B",
	"hoshiguma": "C", "saria": "C", "kaltsit": "C", "lumen": "C", "specter_unchained": "C",
	"wisadel": "D", "angelina": "D", "skalter": "D", "ulpianus": "D", "suzuran": "D",
}
const CD := {
	"texas": 12.0, "exusiai": 12.0, "skadi": 14.0, "siege": 14.0, "eyjafjalla": 16.0,
	"irene": 14.0, "lappland": 16.0, "logos": 16.0, "mizuki": 14.0, "gladiia": 16.0,
	"hoshiguma": 18.0, "saria": 20.0, "kaltsit": 20.0, "lumen": 18.0, "specter_unchained": 20.0,
	"wisadel": 14.0, "angelina": 14.0, "skalter": 16.0, "ulpianus": 16.0, "suzuran": 14.0,
}
const HUNTERS := ["skadi", "gladiia", "ulpianus", "specter_unchained", "skalter"]
const ARTS := ["eyjafjalla", "logos", "lumen", "skalter", "suzuran", "kaltsit", "angelina", "mizuki"]
const TRAVEL := {"eyjafjalla": 0.35, "wisadel": 0.3, "logos": 0.25, "kaltsit": 0.22, "lumen": 0.18, "angelina": 0.18}
const EV_WIN := 0.3       # 事件类：事件时刻在最近 0.3 秒内
const HIT_WIN := 1.5      # D 类：另一名队友连携命中后 1.5 秒内


static func cd_of(id: String) -> float:
	return float(CD.get(id, 14.0))


# ================================================================ 共用

## 本模块自己的记账（挂在 u.ev 下，框架不读）：used 事件已用时刻、ang 最近一次别人亮起（安洁莉娜读）、cdnext 下一次冷却缩短、nx B / C 类节流
static func _st(u) -> Dictionary:
	if not u.ev.has("cb"):
		u.ev["cb"] = {"used": {}, "ang": {}, "cdnext": {}, "nx": {}}
	return u.ev.cb


static func _fresh(u, o, key: String, t: float, win: float) -> bool:
	return t >= 0.0 and u.g.t - t <= win and t > float(_st(u).used.get(str(o.id) + key, -99.0))


static func _use(u, o, key: String, t: float) -> void:
	_st(u).used[str(o.id) + key] = t


## B / C 类扫敌人的判定每 0.1 秒做一次（游戏时间，可复现）
static func _throttle(u, o) -> bool:
	var nx: Dictionary = _st(u).nx
	var k := str(o.id)
	if u.g.t < float(nx.get(k, -99.0)):
		return true
	nx[k] = u.g.t + 0.1
	return false


static func _live(e) -> bool:
	return e is Dictionary and e.has("hp") and not e.get("dead", true) and not e.get("friendly", false)


## 精英 / Boss 优先，其次第一个（列表已按距离排好）
static func _pri(list: Array) -> Variant:
	var elite: Variant = null
	var first: Variant = null
	for e in list:
		if not _live(e):
			continue
		if first == null:
			first = e
		if e.boss:
			return e
		if elite == null and e.elite:
			elite = e
	return elite if elite != null else first


static func _reach() -> float:
	return Bal.v("ult/combo_reach", 400.0)


## 离 origin 最近、离干员 o 够得着（≤ reach）的敌人（精英优先）
static func _tgt_near(o, origin: Vector2, maxd: float, reach: float) -> Variant:
	var cand: Array = []
	for e in o.nearest_enemies(8, maxd, origin):
		if _live(e) and o.pos.distance_to(e.pos) <= reach:
			cand.append(e)
	return _pri(cand)


static func _mk(o, info: Dictionary) -> Dictionary:
	var tgt = info.get("tgt")
	return {"p": o, "id": str(o.id), "s": str(o.id), "tgt": tgt, "tpos": info.get("pos", o.pos), "age": 0.0, "ph": 0, "tp0": 0.0, "delay": 0.0, "auto": false}


static func _tpos(a: Dictionary) -> Vector2:
	if a.tgt != null and _live(a.tgt):
		a.tpos = a.tgt.pos
	return a.tpos


static func _dmg(o, mult: float) -> float:
	var ld := 1.0
	var loc = o.get("loc")
	if loc is Dictionary:
		ld = float(loc.get("dmg", 1.0))
	return o.base("atk", 0.0) * mult * ld * o._dmg_bonus() * Bal.v("ult/combo_dmg", 1.0)


## 伤害来源登记：「连携·<干员id>」，tags 带「连携」（进作战记录的输出统计）
static func _src(o) -> String:
	var k: String = "连携·%s" % str(o.id)
	if not o.g.hit_src.has(k):
		var arts: bool = str(o.id) in ARTS
		o.g.hit_src[k] = {"emitter": "operator", "origin": "skill", "range": "远程" if arts or str(o.id) in ["exusiai", "wisadel"] else "近战",
			"kind": "法术" if arts else "物理", "tags": ["skill", "连携"], "class": o.cls, "op": str(o.id)}
	return k


static func _hit1(o, e: Dictionary, mult: float) -> void:
	o.log_hit(_src(o), ["连携"])
	o.deal_damage(e, _dmg(o, mult))


## 圆形 / 扇形范围（melee_hit：精英控制减半、击退 ×0.3，Boss 不吃控制与击退）
static func _area(o, c: Vector2, r: float, mult: float, kb := 0.0, stun := 0.0, ang := 0.0, half := PI) -> Array:
	return o.melee_hit(_src(o), c, ang, half, r, _dmg(o, mult), kb, stun, ["连携"], 0)


static func _ring(u, c: Vector2, r: float, col: Color, life := 0.3) -> void:
	u.g.fx.append({"kind": "ring", "pos": c, "r": r, "r0": r * 0.4, "life": life, "max": life, "col": col, "floor": true, "w": 2.0, "alpha": 0.6})


static func _tracer(u, a: Vector2, b: Vector2, col: Color, life := 0.16, wid := 6.0) -> void:
	u.g.fx.append({"kind": "tracer", "a": a, "b": b, "life": life, "max": life, "col": col, "wid": wid})


static func _beam(u, a: Vector2, b: Vector2, col: Color, life := 0.3, w := 2.5) -> void:
	u.g.fx.append({"kind": "beam", "a": a, "b": b, "life": life, "max": life, "col": col, "w": w})


## 没有队长 / 不在场 / 倒地 / 正在出连携或排队的队友不能被拉去「自动接」
static func _free(u, o) -> bool:
	if o == null or o.is_leader or o.pos == Vector2.INF or o.cmd_down > 0.0 or u._queued(o):
		return false
	for a in u.combo_acts:
		if a.get("p") == o:
			return false
	return true


static func _op(u, id: String) -> Variant:
	for o in u.g.squad.ops:
		if str(o.id) == id:
			return o
	return null


## 正在放技能 / 冲锋 / 自己的位移时不拉走（docs/160 同口径）
static func _busy_move(p) -> bool:
	if p.rush_t > 0.0 or (p.act_kind == "skill" and p.attack_t > 0.0):
		return true
	if p.has_method("skills_occupied") and p.skills_occupied():
		return true
	var tx = p.get("tx")
	if tx is Dictionary and tx.has("dash"):
		return true
	var hw = p.get("hw")
	return hw is Dictionary and not hw.is_empty() and p.ObHw.hw_busy(p)


## 冷却改动（组合升级）：id 在冷却中直接减；不在冷却中记到下一次（下一次出手的第一帧扣）
static func _cut_cd(u, id: String, sec: float, next_if_ready := false) -> void:
	if u.g.t < float(u.cd.get(id, -99.0)):
		u.cd[id] = float(u.cd[id]) - sec
	elif next_if_ready:
		var cn: Dictionary = _st(u).cdnext
		cn[id] = maxf(float(cn.get(id, 0.0)), sec)


## 编队里不是队长的在场队友是不是只有 D 类（§5.1：只有 D 类时 D 类改跟队长终结技）
static func _only_d(u) -> bool:
	var n := 0
	for o in u.g.squad.ops:
		if o.is_leader or o.pos == Vector2.INF:
			continue
		n += 1
		if str(CLS.get(str(o.id), "")) != "D":
			return false
	return n > 0


# ================================================================ 触发判定

## 满足返回 info（{"tgt": 敌人或 null, "pos": 落点, …}），不满足返回 {}
static func check(u, o) -> Dictionary:
	var g = u.g
	var id := str(o.id)
	var ev: Dictionary = u.ev
	match id:
		# ---- A 跟队长动作
		"texas":   # 队长冲刺起步：沿同一方向冲刺斩
			if _fresh(u, o, ":ds", ev.dash_start_t, EV_WIN):
				var d: Vector2 = Vector2(ev.dash_dir).normalized()
				if not u.in_band(o.pos, o.pos + d * _reach(), 40.0).is_empty():
					_use(u, o, ":ds", ev.dash_start_t)
					return {"tgt": null, "pos": o.pos + d * 300.0, "dir": d}
		"exusiai":   # 队长冲刺起步：朝队长身后最近的敌群扫射
			if _fresh(u, o, ":ds", ev.dash_start_t, EV_WIN):
				var back: Vector2 = Vector2(ev.dash_from) - Vector2(ev.dash_dir).normalized() * 160.0
				var t = _tgt_near(o, back, 320.0, 470.0)
				if t != null:
					_use(u, o, ":ds", ev.dash_start_t)
					return {"tgt": t, "pos": t.pos}
		"skadi":   # 队长冲刺结束：跃到落点横扫
			if _fresh(u, o, ":de", ev.dash_end_t, EV_WIN):
				var lp: Vector2 = ev.dash_end_pos
				if o.pos.distance_to(lp) <= _reach() and not u.in_circle(lp, 150.0).is_empty():
					_use(u, o, ":de", ev.dash_end_t)
					return {"tgt": null, "pos": lp}
		"siege":   # 队长冲刺结束：跃向落点附近最密的敌群砸锤
			if _fresh(u, o, ":de", ev.dash_end_t, EV_WIN):
				var dp: Vector2 = o.densest_point(260.0, ev.dash_end_pos)
				if dp != Vector2.INF and o.pos.distance_to(dp) <= _reach():
					_use(u, o, ":de", ev.dash_end_t)
					return {"tgt": null, "pos": dp}
		"eyjafjalla":   # 队长站定满 1.2 秒（同一段站定只亮一次）
			var still: float = float(g.leader_still_t)
			if still >= 1.2:
				var s0: float = snappedf(g.t - still, 0.1)
				if s0 > float(_st(u).used.get(id + ":still", -99.0)) + 0.2:
					var fwd: Vector2 = g.ppos + Vector2(g.facing, 0.0) * 200.0
					var dp: Vector2 = o.densest_point(280.0, fwd)
					if dp == Vector2.INF:
						dp = o.densest_point(300.0, g.ppos)
					if dp != Vector2.INF and o.pos.distance_to(dp) <= 520.0:
						_use(u, o, ":still", s0)
						return {"tgt": null, "pos": dp}
		# ---- B 跟敌人状态
		"irene":   # 屏内 ≥ 3 名浮空 / 眩晕（束缚 = 眩晕）中的敌人
			if _throttle(u, o):
				return {}
			var cc: Array = []
			for e in u.in_view(g.ppos):
				if float(e.stun) > 0.0 or float(e.get("air", 0.0)) > 0.0:
					cc.append(e)
			if cc.size() >= 3:
				var best = null
				var bd := INF
				for e in cc:
					var dd: float = o.pos.distance_to(e.pos)
					if dd < bd:
						bd = dd
						best = e
				if bd <= _reach():
					return {"tgt": best, "pos": best.pos}
		"lappland":   # 精英开始读招（特殊招式预警 / 远程开火前摇）
			if _throttle(u, o):
				return {}
			var best = null
			var bd := INF
			for w in g.warns:
				var e = w.get("owner")
				if e is Dictionary and _live(e) and e.elite and not e.boss and not w.get("done", false):
					var dd: float = o.pos.distance_to(e.pos)
					if dd < bd:
						bd = dd
						best = e
			if best == null:
				for e in u.in_view(g.ppos):
					if e.elite and not e.boss and float(e.get("shot_wind_until", -1.0)) > g.t:
						var dd: float = o.pos.distance_to(e.pos)
						if dd < bd:
							bd = dd
							best = e
			if best != null and bd <= _reach():
				return {"tgt": best, "pos": best.pos}
		"logos":   # 屏内 ≥ 6 名生命低于 30% 的普通敌人
			if _throttle(u, o):
				return {}
			var low := _low_minions(u, 0.3)
			if low.size() >= 6:
				return {"tgt": null, "pos": _centroid(low)}
		"mizuki":   # 他附近 400 内 ≥ 5 名生命低于一半的敌人
			if _throttle(u, o):
				return {}
			var n := 0
			for e in u.in_circle(o.pos, 400.0):
				if e.hp < 0.5 * e.maxhp:
					n += 1
			if n >= 5:
				return {"tgt": null, "pos": o.pos}
		"gladiia":   # 屏内、离队长 500 以外的精英或远程敌人
			if _throttle(u, o):
				return {}
			var best = null
			var bd := INF
			for e in u.in_view(g.ppos):
				if e.boss or e.get("part", false) or not (e.elite or str(e.get("ai", "")) == "ranged"):
					continue
				var dl: float = e.pos.distance_to(g.ppos)
				if dl <= 500.0 or o.pos.distance_to(e.pos) > 780.0:
					continue
				var score: float = dl - (10000.0 if e.elite else 0.0)   # 精英优先，其次最远的远程
				if score < bd:
					bd = score
					best = e
			if best != null:
				return {"tgt": best, "pos": best.pos}
		# ---- C 跟队长危险
		"hoshiguma":   # 队长 1 秒内被近战命中 ≥ 2 次，或身边 120 内 ≥ 6 名敌人
			var mt := 0
			for t in ev.melee_t:
				if g.t - float(t) <= 1.0:
					mt += 1
			if mt >= 2 and _fresh(u, o, ":melee", float(ev.melee_t[ev.melee_t.size() - 1]), 1.0):
				_use(u, o, ":melee", float(ev.melee_t[ev.melee_t.size() - 1]))
				return {"tgt": null, "pos": g.ppos}
			if _throttle(u, o):
				return {}
			if u.in_circle(g.ppos, 120.0).size() >= 6:
				return {"tgt": null, "pos": g.ppos}
		"saria":   # 队长生命低于 50%
			if g.hp < 0.5 * g.max_hp:
				return {"tgt": null, "pos": g.ppos}
		"kaltsit":   # 队长生命低于 40%，或神经损伤 ≥ 80%
			if g.hp < 0.4 * g.max_hp or g.nerve >= 0.8 * g.combat.nerve_max():
				return {"tgt": null, "pos": g.ppos}
		"lumen":   # 队长神经损伤 ≥ 60%，或灯火进入暗淡（< 30）
			if g.nerve >= 0.6 * g.combat.nerve_max() or g.lamp < 30.0:
				return {"tgt": null, "pos": g.ppos}
		"specter_unchained":   # 队长一次受到 ≥ 10% 最大生命的伤害
			if _fresh(u, o, ":big", ev.big_t, EV_WIN):
				var src = ev.big_src
				var t = src if (src is Dictionary and not src.is_empty() and _live(src) and o.pos.distance_to(src.pos) <= _reach() + 120.0) else _tgt_near(o, g.ppos, 300.0, _reach() + 120.0)
				if t != null:
					_use(u, o, ":big", ev.big_t)
					return {"tgt": t, "pos": t.pos}
		# ---- D 跟队友连携
		"wisadel", "skalter", "suzuran", "ulpianus":
			var h := _recent_hit(u, o, id == "ulpianus")
			if not h.is_empty():
				if id == "ulpianus" and o.pos.distance_to(h.pos) > _reach() + 80.0:
					return {}
				_use(u, o, ":hit", float(h.t))
				return {"tgt": null, "pos": h.pos, "from": str(h.op)}
			return _d_fallback(u, o)
		"angelina":   # 另一名队友的连携亮起时（出手前）：on_lit 记下来
			var la: Dictionary = _st(u).ang
			if not la.is_empty() and la.op != o and _fresh(u, o, ":lit", float(la.t), EV_WIN):
				_use(u, o, ":lit", float(la.t))
				return {"tgt": la.get("tgt"), "pos": la.pos, "for": la.op}
			return _d_fallback(u, o)
	return {}


## D 类：另一名队友的连携命中（1.5 秒内、本人没用过的最近一条）；gather = 乌尔比安要「聚到 200 内 ≥ 6」
static func _recent_hit(u, o, gather: bool) -> Dictionary:
	var hs: Array = u.ev.hits
	for k in range(hs.size() - 1, -1, -1):
		var h: Dictionary = hs[k]
		if str(h.op) == str(o.id) or not _fresh(u, o, ":hit", float(h.t), HIT_WIN):
			continue
		if gather and int(h.get("gathered", 0)) < 6:
			continue
		return h
	return {}


## 编队里只有 D 类队友：改为「队长放终结技 / 连携终结技后 1 秒内」
static func _d_fallback(u, o) -> Dictionary:
	var t: float = maxf(float(u.ev.ult_t), float(u.ev.cult_t))
	if not _fresh(u, o, ":ult", t, 1.0) or not _only_d(u):
		return {}
	var dp: Vector2 = o.densest_point(300.0, u.g.ppos)
	if dp == Vector2.INF:
		return {}
	_use(u, o, ":ult", t)
	return {"tgt": null, "pos": dp}


static func _low_minions(u, frac: float) -> Array:
	var out: Array = []
	for e in u.in_view(u.g.ppos):
		if not e.elite and not e.boss and not e.get("part", false) and e.hp < frac * e.maxhp:
			out.append(e)
	return out


static func _centroid(list: Array) -> Vector2:
	var s := Vector2.ZERO
	for e in list:
		s += e.pos
	return s / maxf(1.0, list.size())


## 亮起那一刻：别人亮起记下来给安洁莉娜；安洁莉娜亮起时把她排到要配合的那名队友前面（重力弹先落，那次连携多打到人）
static func on_lit(u, o, info: Dictionary) -> void:
	if str(o.id) != "angelina":
		_st(u).ang = {"t": u.g.t, "pos": info.get("pos", o.pos), "tgt": info.get("tgt"), "op": o}
		return
	var mate = info.get("for")
	if mate == null:
		return
	var qi := -1
	var ai := -1
	for i in u.queue.size():
		if u.queue[i].o == mate:
			qi = i
		elif u.queue[i].o == o:
			ai = i
	if qi >= 0 and ai > qi:
		var ent: Dictionary = u.queue[ai]
		u.queue.remove_at(ai)
		u.queue.insert(qi, ent)


# ================================================================ 出手

## dir 非零（玩家按 E 时的移动方向）：冲刺类按这个方向出手
static func fire(u, o, info: Dictionary, dir: Vector2) -> Dictionary:
	var g = u.g
	var id := str(o.id)
	var a := _mk(o, info)
	if dir != Vector2.ZERO and id in ["skadi", "siege", "irene", "lappland", "specter_unchained", "ulpianus"]:
		_aim_dir(o, a, dir)
	match id:
		"texas":
			a.merge({"k": "dash", "path": dir if dir != Vector2.ZERO else Vector2(info.get("dir", Vector2(g.facing, 0.0))), "wind": 0.06, "dur": 0.2, "hold": 0.2}, true)
			if _op(u, "lappland") != null:
				_cut_cd(u, "lappland", Bal.v("ult/rival_cut", 3.0))   # 宿敌：互相缩短对方冷却
		"exusiai":
			a.merge({"k": "volley", "wind": 0.15, "n": 8, "gap": 0.07, "mult": 0.18}, true)
			if _op(u, "texas") != null:
				_cut_cd(u, "texas", Bal.v("ult/penguin_cut", 4.0), true)   # 企鹅物流：德克萨斯下一次冷却 −4 秒
		"skadi":
			a.merge({"k": "dash", "wind": 0.1, "dur": 0.22, "gap": 0.0, "hold": 0.24}, true)
		"siege":
			a.merge({"k": "dash", "wind": 0.12, "dur": 0.26, "gap": 20.0, "hold": 0.24}, true)
		"irene":
			a.merge({"k": "dash", "wind": 0.08, "dur": 0.18, "gap": 22.0, "hold": 0.42}, true)
		"lappland":
			a.merge({"k": "dash", "wind": 0.1, "dur": 0.2, "gap": 26.0, "hold": 0.22}, true)
			if _op(u, "texas") != null:
				_cut_cd(u, "texas", Bal.v("ult/rival_cut", 3.0))
		"hoshiguma":
			a.merge({"k": "dash", "guard": true, "wind": 0.06, "dur": 0.18, "hold": 0.25, "reach": 900.0}, true)
		"saria":
			a.merge({"k": "dash", "guard": true, "wind": 0.08, "dur": 0.2, "hold": 0.25, "reach": 900.0}, true)
		"specter_unchained":
			a.merge({"k": "dash", "wind": 0.06, "dur": 0.16, "gap": 22.0, "hold": 0.34, "reach": 560.0}, true)
		"ulpianus":
			a.merge({"k": "dash", "wind": 0.12, "dur": 0.24, "gap": 0.0, "hold": 0.26, "reach": 520.0}, true)
		"gladiia":
			a.merge({"k": "hook", "wind": 0.12, "pull": 0.3}, true)
		"eyjafjalla", "wisadel", "logos", "kaltsit", "lumen", "angelina":
			a.merge({"k": "cast", "wind": 0.1, "travel": float(TRAVEL[id])}, true)
		"mizuki", "skalter", "suzuran":
			a.merge({"k": "cast", "wind": 0.12, "travel": 0.0}, true)
		_:
			return {}
	if not o.acting():
		o.play_vis_anim("attack")
	return a


## 冲刺类按玩家方向：那个方向 400 内的敌人（精英优先），没有就朝那个方向冲 240
static func _aim_dir(o, a: Dictionary, dir: Vector2) -> void:
	var d := dir.normalized()
	var cand: Array = []
	for e in o.nearest_enemies(12, _reach(), o.pos):
		if _live(e) and (e.pos - o.pos).normalized().dot(d) > 0.6:
			cand.append(e)
	var t = _pri(cand)
	a.tgt = t
	a.tpos = t.pos if t != null else o.pos + d * 240.0


static func step(u, a: Dictionary, dt: float) -> bool:
	if str(a.get("k", "")) == "linger":
		return _step_linger(u, a, dt)
	var p = a.get("p")
	if p == null or p.pos == Vector2.INF or p.cmd_down > 0.0:
		return true
	if not a.get("init", false):
		a["init"] = true
		var cn: Dictionary = _st(u).cdnext
		if not a.auto and cn.has(a.id):   # 企鹅物流：上一次能天使扫射记下的「下一次冷却 −4 秒」
			u.cd[a.id] = float(u.cd.get(a.id, u.g.t)) - float(cn[a.id])
			cn.erase(a.id)
	if float(a.delay) > 0.0:
		a.delay -= dt
		return false
	a.age += dt
	match str(a.k):
		"dash":
			return _step_dash(u, a, dt)
		"volley":
			return _step_volley(u, a, dt)
		"hook":
			return _step_hook(u, a, dt)
		"cast":
			return _step_cast(u, a, dt)
	return true


## 第一下命中：给框架记（能量 / 协同 / D 类）+ 组合升级的自动接（自动接的那段不再记、不再连锁）
static func _landed(u, a: Dictionary, pos: Vector2, n_hit: int, support := false) -> void:
	if a.auto or a.get("landed", false) or (n_hit <= 0 and not support):
		return
	a["landed"] = true
	var p = a.p if a.get("p") != null else a.get("o")
	u.combo_landed(p, pos, n_hit, u.in_circle(pos, 200.0).size())
	var id := str(a.id)
	if id in HUNTERS:
		_hunter_chain(u, a, pos)
	if id == "texas":
		var ex = _op(u, "exusiai")
		if ex != null and _free(u, ex):   # 企鹅物流：能天使自动接一轮扫射打被阻挡的敌人
			var tg: Array = a.get("blocked", [])
			var b := _mk(ex, {"tgt": tg[0] if not tg.is_empty() else null, "pos": pos})
			b.merge({"k": "volley", "wind": 0.1, "n": 6, "gap": 0.07, "mult": 0.18, "auto": true, "list": tg, "s": "pvolley"}, true)
			u.add_act(b)


## 深海猎人：另一名猎人自动接一段扑向同一目标（0.09 秒后）；歌蕾蒂娅钩回精英时乌尔比安优先
static func _hunter_chain(u, a: Dictionary, pos: Vector2) -> void:
	var order: Array = []
	var t = a.tgt if (a.tgt != null and _live(a.tgt)) else null
	if str(a.id) == "gladiia" and t != null and t.elite:
		order.append("ulpianus")
	for h in HUNTERS:
		if not h in order:
			order.append(h)
	for h in order:
		if h == str(a.id):
			continue
		var o2 = _op(u, h)
		if o2 == null or not _free(u, o2) or o2.pos.distance_to(pos) > _reach() + 60.0:
			continue
		var b := _mk(o2, {"tgt": t, "pos": pos})
		b.merge({"k": "dash", "wind": 0.04, "dur": 0.2, "gap": 26.0, "hold": 0.22, "delay": Bal.v("ult/hunter_gap", 0.09), "auto": true, "s": "pounce"}, true)
		u.add_act(b)
		return


# ---------------------------------------------------------------- dash：冲到目标出招再回队

static func _step_dash(u, a: Dictionary, dt: float) -> bool:
	var p = a.p
	var g = u.g
	if a.ph == 0:
		if a.age < float(a.get("wind", 0.1)):
			return false
		if g.squad.stance == g.squad.RECALL:
			return _give_up(u, a)
		if _busy_move(p):   # 正在放技能 / 冲锋：最多等 0.5 秒，还忙就放弃（冷却退回）
			a["bwait"] = float(a.get("bwait", 0.0)) + dt
			return _give_up(u, a) if float(a.bwait) >= 0.5 else false
		var p0: Vector2 = p.pos
		var stop: Vector2
		var dir: Vector2
		if a.has("path"):   # 德克萨斯：沿方向冲过去
			dir = Vector2(a.path).normalized()
			if dir == Vector2.ZERO:
				dir = Vector2(g.facing, 0.0)
			var far := 200.0
			for e in u.in_band(p0, p0 + dir * _reach(), 40.0):
				far = maxf(far, minf(_reach(), (e.pos - p0).dot(dir) + 40.0))
			stop = p0 + dir * far
		elif a.get("guard", false):   # 星熊 / 塞雷娅：冲到队长身前 / 身边
			var dp: Vector2 = p.densest_point(220.0, g.ppos)
			var side: Vector2 = (dp - g.ppos).normalized() if dp != Vector2.INF and dp != g.ppos else (p0 - g.ppos).normalized()
			if side == Vector2.ZERO:
				side = Vector2(g.facing, 0.0)
			stop = g.ppos + side * (44.0 if str(a.s) == "hoshiguma" else 36.0)
			dir = (stop - p0).normalized()
			a.tpos = stop + side * 40.0
		else:
			var tp: Vector2 = _tpos(a)
			var dv: Vector2 = tp - p0
			if dv.length() > float(a.get("reach", _reach())) * 1.25:
				return _give_up(u, a)
			dir = dv.normalized() if dv != Vector2.ZERO else Vector2(p.face, 0.0)
			var rt: float = float(a.tgt.r) if a.tgt != null and _live(a.tgt) else 14.0
			stop = tp - dir * (rt + float(a.get("gap", 26.0))) if float(a.get("gap", 26.0)) > 0.0 else tp
		if g.get("map") != null and g.map.segment_blocked(p0, stop):
			return _give_up(u, a)
		a["from"] = p0
		a["stop"] = stop
		a["dir"] = dir
		var dur: float = float(a.get("dur", 0.2))
		p.syn_mv = {"from": p0, "to": stop, "t": 0.0, "dur": dur}
		p.cmd_inv = maxf(p.cmd_inv, dur + 0.4)
		p._set_face(1.0 if dir.x >= 0.0 else -1.0, true)
		_tracer(u, p0 + Vector2(0, -20), stop + Vector2(0, -20), p.col(), dur + 0.14, 8.0)   # 干员色拖影
		a.ph = 1
		a.tp0 = a.age
		return false
	if a.ph == 1:
		if a.age - a.tp0 < float(a.get("dur", 0.2)):
			return false
		_strike(u, a)
		if not p.acting():
			p.play_vis_anim("attack")
		p.screen_shake(0.1)
		a.ph = 2
		a.tp0 = a.age
		return false
	return _post(u, a)


static func _give_up(u, a: Dictionary) -> bool:
	if not a.auto:
		u.cd[a.id] = u.g.t   # 没出成：冷却退回
	return true


## 出招（落点 a.stop，朝 a.tpos）
static func _strike(u, a: Dictionary) -> void:
	var p = a.p
	var g = u.g
	var stop: Vector2 = a.stop
	var tp: Vector2 = _tpos(a) if not a.get("guard", false) else a.tpos
	var ang: float = (tp - stop).angle() if tp != stop else Vector2(a.dir).angle()
	var c: Color = p.col()
	var hits: Array = []
	match str(a.s):
		"texas":   # 冲刺斩：路径上的敌人都挨一刀，前 2 名被阻挡 0.6 秒
			var path: Array = u.in_band(a.from, stop, 36.0)
			var f0: Vector2 = a.from
			path.sort_custom(func(x, y): return x.pos.distance_squared_to(f0) < y.pos.distance_squared_to(f0))
			var blocked: Array = []
			for e in path:
				_hit1(p, e, 1.3)
				if not e.dead and blocked.size() < 2:
					blocked.append(e)
					if not e.boss:
						p.add_cc(e, 0.6 * (0.5 if e.elite else 1.0))
			hits = path
			a["blocked"] = blocked
			p.slash_fx(stop, ang, 0.6, 120.0, c, "slash", 0.24)
			_beam(u, Vector2(a.from) + Vector2(0, -16), stop + Vector2(0, -16), c.lerp(Color.WHITE, 0.4), 0.22, 3.0)
		"skadi":   # 大剑横扫一周并击退
			hits = _area(p, stop, 115.0, 1.4, 200.0)
			p.slash_fx(stop, ang, PI, 110.0, c, "slash", 0.3)
		"siege":   # 砸锤：眩晕 0.6 秒，其他干员技力 +1 秒
			hits = _area(p, stop, 105.0, 1.5, 120.0, 0.6)
			for o2 in g.squad.ops:
				if o2 != p and o2.pos != Vector2.INF:
					_sp_add(o2, Bal.v("ult/siege_sp", 1.0))
			_ring(u, stop, 105.0, c, 0.36)
		"irene":   # 第一刺（第二刺在 _post）：对浮空 / 眩晕中的敌人 +50%
			hits = _irene_stab(u, a, false)
		"lappland":   # 横扫并封印：打断这次出招，2 秒不起特殊招式 / 不开火
			hits = _area(p, stop, 95.0, 1.4, 90.0, 0.0, ang, 1.5)
			var e = a.tgt
			if e != null and _live(e) and not e.boss:
				g.enemies_sys.interrupt(e)
				g.enemies_sys.silence(e, g.t + Bal.v("ult/lapp_seal", 2.0))
				if not e in hits and e.pos.distance_to(stop) <= 140.0:
					_hit1(p, e, 1.4)
					hits.append(e)
			p.slash_fx(stop, ang, 1.5, 95.0, c, "slash", 0.26)
		"hoshiguma":   # 举盾推开周围敌人，队长 1.5 秒受到伤害 −50%
			hits = _area(p, g.ppos, 140.0, 1.2, 260.0)
			u.team_buff("combo:hoshiguma", Bal.v("ult/hoshi_t", 1.5), [[&"dmg_taken", "mult", Bal.v("ult/hoshi_taken", 0.5)]])
			_ring(u, g.ppos, 140.0, c, 0.4)
			_landed(u, a, g.ppos, hits.size(), true)
			return
		"saria":   # 琥珀晶柱围一圈挡 2 秒，队长回复 6% 最大生命
			hits = _area(p, g.ppos, 90.0, 1.0, 200.0)
			p.heal_leader(g.max_hp * Bal.v("ult/saria_heal", 0.06), "连携")
			_linger(u, p, {"kind": "pillars", "dur": 2.0, "r": 90.0})
			_ring(u, g.ppos, 90.0, c, 0.4)
			_landed(u, a, g.ppos, hits.size(), true)
			return
		"specter_unchained":   # 替身连斩（三下，后两下在 _post），之后 2 秒队长生命不会低于 1
			hits = _area(p, stop, 90.0, 0.55, 60.0, 0.0, ang, 1.6)
			p.slash_fx(stop, ang, 1.4, 90.0, c, "slash", 0.2)
			_linger(u, p, {"kind": "undying", "dur": Bal.v("ult/specter_t", 2.0)})
		"ulpianus":   # 砸锚：击退并眩晕 0.4 秒
			hits = _area(p, stop, 125.0, 1.5, 220.0, 0.4)
			_ring(u, stop, 125.0, c, 0.4)
			u.shape({"kind": "circle", "c": stop, "r": 125.0, "col": c, "fill": 0.25, "life": 0.3})
		"pounce":   # 深海猎人自动接的一扑
			hits = _area(p, stop, 92.0, 1.0, 120.0)
			p.slash_fx(stop, ang, PI, 90.0, c, "slash", 0.22)
		"istab":   # 审判庭：艾丽妮补一刺
			hits = _area(p, stop, 80.0, 1.0, 60.0, 0.0, ang, 1.0)
			p.slash_fx(stop, ang, 1.0, 80.0, c, "slash", 0.2)
	_ring(u, tp, 70.0, c)
	p.sparks(tp, Vector2(a.dir), c, 6, 160.0)
	_landed(u, a, stop, hits.size())


## 收势：多段（艾丽妮第二刺、幽灵鲨后两斩）在这里出；hold 秒后结束，编队跟随拉回
static func _post(u, a: Dictionary) -> bool:
	var p = a.p
	var el: float = a.age - a.tp0
	match str(a.s):
		"irene":
			if el >= 0.18 and not a.get("s2", false):
				a["s2"] = true
				_irene_stab(u, a, true)
		"specter_unchained":
			var n2: int = mini(3, 1 + int(el / 0.1))
			while int(a.get("sl", 1)) < n2:
				a["sl"] = int(a.get("sl", 1)) + 1
				var stop: Vector2 = a.stop
				var ang: float = (_tpos(a) - stop).angle() + (0.7 if int(a.sl) == 2 else -0.7)
				var hits: Array = _area(p, stop, 90.0, 0.5, 60.0, 0.0, ang, 1.6)
				p.slash_fx(stop, ang, 1.4, 90.0, p.col().lerp(Color.WHITE, 0.3), "slash", 0.2)
				_landed(u, a, stop, hits.size())
	return el >= float(a.get("hold", 0.22))


## 艾丽妮：连刺两段，对浮空 / 眩晕中的敌人伤害 +50%；第二刺把敌人挑起 0.5 秒（审判庭：流明在队时被挑起的敌人受到的伤害 +10%，4 秒）
static func _irene_stab(u, a: Dictionary, second: bool) -> Array:
	var p = a.p
	var g = u.g
	var stop: Vector2 = a.stop
	var ang: float = (_tpos(a) - stop).angle()
	var hits: Array = p.arc_targets(stop, ang, 1.2, 95.0)
	for e in hits:
		_hit1(p, e, 0.75 * (1.5 if float(e.stun) > 0.0 or float(e.get("air", 0.0)) > 0.0 else 1.0))
	p.slash_fx(stop, ang + (0.4 if second else -0.4), 1.2, 95.0, p.col(), "slash", 0.2)
	if second:
		var lift: Array = []
		for e in hits:
			if _live(e) and not e.boss:
				p.add_cc(e, 0.5 * (0.5 if e.elite else 1.0), -INF, "airborne")
				lift.append(e)
		if not lift.is_empty():
			_linger(u, p, {"kind": "float", "dur": 0.5, "list": lift, "h": 26.0})
			var lm = _op(u, "lumen")
			if lm != null and lm.pos != Vector2.INF:
				for e in lift:
					e["frag_t"] = maxf(float(e.get("frag_t", 0.0)), g.t + Bal.v("ult/judge_t", 4.0))
					e["frag_v"] = maxf(float(e.get("frag_v", 0.0)), Bal.v("ult/judge_v", 0.1))
				u.shape({"kind": "dots", "c": stop, "r": 90.0, "n": 14, "col": lm.col().lerp(Color.WHITE, 0.4), "life": 0.6})
	_landed(u, a, stop, hits.size())
	return hits


## 推进之王：技力 +秒数（已解锁、非常驻的技能各自加，封顶）
static func _sp_add(o, sec: float) -> void:
	if not o.has_method("skill_unlocked"):
		return
	for i in 3:
		if o.skill_unlocked(i) and o.sp_need(i) > 0.0 and not o.perm[i]:
			o.sp[i] = minf(o.sp_need(i), o.sp[i] + sec)


# ---------------------------------------------------------------- volley：原地扫射

static func _step_volley(u, a: Dictionary, _dt: float) -> bool:
	var p = a.p
	if a.age < float(a.wind):
		return false
	if not a.has("list") or (a.list as Array).is_empty():
		a["list"] = p.nearest_enemies(8, 200.0, _tpos(a))
	var lst: Array = a.list
	var due: int = mini(int(a.n), 1 + int((a.age - float(a.wind)) / maxf(0.02, float(a.gap))))
	var c: Color = p.col()
	while int(a.get("shots", 0)) < due:
		var k: int = int(a.get("shots", 0))
		a["shots"] = k + 1
		var e = null
		for j in lst.size():   # 按序号轮着打，打死的跳过
			var cand = lst[(k + j) % lst.size()]
			if _live(cand):
				e = cand
				break
		var tp: Vector2 = e.pos if e != null else _tpos(a)
		var from: Vector2 = p.pos + Vector2(float(p.face) * 14.0, -24.0)
		_tracer(u, from, tp + Vector2(0, -8), c)
		p.sparks(from, (tp - from).normalized(), c, 3, 120.0)
		p._set_face(1.0 if tp.x >= p.pos.x else -1.0)
		if e == null:
			var near: Array = p.nearest_enemies(1, 56.0, tp)
			e = near[0] if not near.is_empty() else null
		if e != null:
			_hit1(p, e, float(a.mult))
			_landed(u, a, e.pos, 1)
	if int(a.shots) >= int(a.n):
		_ring(u, _tpos(a), 60.0, c, 0.25)
		return true
	return false


# ---------------------------------------------------------------- hook：甩钩把它拖到队长前方 120

static func _step_hook(u, a: Dictionary, _dt: float) -> bool:
	var p = a.p
	var g = u.g
	var e = a.tgt
	if a.ph == 0:
		if a.age < float(a.wind):
			return false
		if e == null or not _live(e):
			return true
		var side: Vector2 = (e.pos - g.ppos).normalized()
		a["from"] = e.pos
		a["dest"] = g.ppos + (side if side != Vector2.ZERO else Vector2(g.facing, 0.0)) * 120.0
		a.ph = 1
		a.tp0 = a.age
		p._set_face(1.0 if e.pos.x >= p.pos.x else -1.0)
		_hit1(p, e, 0.5)
		return false
	if a.ph == 1:
		var k: float = clampf((a.age - a.tp0) / float(a.pull), 0.0, 1.0)
		if e != null and _live(e):
			g.enemies_sys.hold_at(e, Vector2(a.from).lerp(a.dest, 1.0 - (1.0 - k) * (1.0 - k)))
			_beam(u, p.pos + Vector2(0, -24), e.pos + Vector2(0, -8), p.col(), 0.05, 3.0)
		if k < 1.0:
			return false
		var at: Vector2 = e.pos if e != null and _live(e) else a.dest
		var n := 0
		if e != null and _live(e):
			_hit1(p, e, 0.9)
			if not e.dead:
				p.add_cc(e, 0.6 * (0.5 if e.elite else 1.0))
			n = 1
		_ring(u, at, 80.0, p.col(), 0.35)
		p.sparks(at, (p.pos - at).normalized(), p.col(), 6, 140.0)
		_landed(u, a, at, n)
		return true
	return true


# ---------------------------------------------------------------- cast：原地投射到落点

static func _step_cast(u, a: Dictionary, _dt: float) -> bool:
	var p = a.p
	var g = u.g
	var c: Color = p.col()
	if a.ph == 0:
		if a.age < float(a.wind):
			return false
		var tp: Vector2 = _cast_pos(u, a)
		a.tpos = tp
		var tr: float = float(a.travel)
		if tr > 0.0:
			_tracer(u, p.pos + Vector2(0, -26), tp, c, tr + 0.1, 7.0)
			u.shape({"kind": "ring", "c": tp, "r": 60.0, "r1": 20.0, "w": 2.0, "col": c, "life": tr})
		p._set_face(1.0 if tp.x >= p.pos.x else -1.0)
		a.ph = 1
		a.tp0 = a.age
		return false
	if a.ph == 1:
		if a.age - a.tp0 < float(a.travel):
			return false
		_impact(u, a)
		a.ph = 2
		a.tp0 = a.age
		return false
	return a.age - a.tp0 >= 0.15


## 落点：跟队长走的（凯尔希 / 流明）按队长现在的位置
static func _cast_pos(u, a: Dictionary) -> Vector2:
	match str(a.s):
		"kaltsit", "lumen":
			return u.g.ppos
		"mizuki":
			return a.p.pos
	return _tpos(a)


static func _impact(u, a: Dictionary) -> void:
	var p = a.p
	var g = u.g
	var tp: Vector2 = a.tpos
	var c: Color = p.col()
	var hits: Array = []
	var support := false
	match str(a.s):
		"eyjafjalla":   # 放大熔岩弹 + 2 秒熔岩
			hits = _area(p, tp, 105.0, 1.4, 80.0)
			_ring(u, tp, 105.0, c, 0.4)
			_linger(u, p, {"kind": "lava", "dur": 2.0, "c": tp, "r": 90.0})
		"wisadel":   # 炮击 + 余震
			hits = _area(p, tp, 110.0, 1.5, 120.0)
			_ring(u, tp, 110.0, c, 0.35)
			u.shape({"kind": "circle", "c": tp, "r": 110.0, "col": c, "fill": 0.3, "life": 0.25})
			_linger(u, p, {"kind": "after", "dur": 0.5, "c": tp})
		"logos":   # 咒文扩散，处决至多 6 名低于 30% 的普通敌人
			var low: Array = _low_minions(u, 0.3)
			low.sort_custom(func(x, y): return x.pos.distance_squared_to(tp) < y.pos.distance_squared_to(tp))
			for e in low.slice(0, int(Bal.v("ult/logos_n", 6.0))):
				_beam(u, tp + Vector2(0, -10), e.pos + Vector2(0, -8), c, 0.25, 2.0)
				p.log_hit(_src(p), ["连携"])
				p.deal_damage(e, maxf(_dmg(p, 1.2), float(e.hp) * 4.0 + 50.0))
				hits.append(e)
			u.shape({"kind": "ring", "c": tp, "r": 240.0, "r1": 30.0, "w": 3.0, "col": c, "life": 0.45})
		"mizuki":   # 触手追击附近低于一半的敌人，束缚 1 秒
			var cand: Array = []
			for e in u.in_circle(p.pos, 400.0):
				if e.hp < 0.5 * e.maxhp:
					cand.append(e)
			var pp: Vector2 = p.pos
			cand.sort_custom(func(x, y): return x.pos.distance_squared_to(pp) < y.pos.distance_squared_to(pp))
			for e in cand.slice(0, 8):
				_beam(u, pp + Vector2(0, -16), e.pos + Vector2(0, -6), c, 0.3, 3.0)
				_hit1(p, e, 1.2)
				if not e.dead and not e.boss:
					p.add_cc(e, 1.0 * (0.5 if e.elite else 1.0))
				hits.append(e)
			tp = _centroid(hits) if not hits.is_empty() else pp
		"kaltsit":   # Mon3tr 扑击击退，队长回复 8% 并清神经损伤
			hits = _area(p, tp, 130.0, 1.5, 220.0)
			p.heal_leader(g.max_hp * Bal.v("ult/kaltsit_heal", 0.08), "连携")
			g.nerve = 0.0
			_ring(u, tp, 130.0, c, 0.4)
			support = true
		"lumen":   # 光弹清除神经损伤，灯火 +10；队长身边照亮
			var had: bool = g.nerve > 0.0
			g.nerve = 0.0
			g.lamp = minf(g.lamp_cap, g.lamp + Bal.v("ult/lumen_lamp", 10.0))
			hits = _area(p, tp, 150.0, 1.2)
			for e in hits:
				if not e.dead:
					e["lit"] = maxf(float(e.get("lit", 0.0)), 3.0)
			u.shape({"kind": "circle", "c": tp, "r": 150.0, "col": c.lerp(Color.WHITE, 0.5), "fill": 0.2, "life": 0.4})
			support = true
			var ir = _op(u, "irene")
			if had and ir != null and _free(u, ir):   # 审判庭：艾丽妮自动补一刺打队长身边最近的敌人
				var t = _tgt_near(ir, g.ppos, 300.0, _reach() + 100.0)
				if t != null:
					var b := _mk(ir, {"tgt": t, "pos": t.pos})
					b.merge({"k": "dash", "wind": 0.05, "dur": 0.16, "gap": 22.0, "hold": 0.2, "auto": true, "s": "istab", "reach": 500.0}, true)
					u.add_act(b)
		"angelina":   # 重力弹：把周围敌人拉向目标
			hits = _area(p, tp, 90.0, 1.2)
			_linger(u, p, {"kind": "pull", "dur": 0.6, "c": tp, "r": 210.0})
			u.shape({"kind": "ring", "c": tp, "r": 210.0, "r1": 40.0, "w": 2.0, "col": c, "life": 0.6})
		"skalter":   # 声浪 + 3 秒全队攻击速度 +12%
			hits = _area(p, tp, 160.0, 1.2, 60.0)
			u.team_buff("combo:skalter", Bal.v("ult/skalter_t", 3.0), [[&"op_aspd", "mult", 1.0 + Bal.v("ult/skalter_aspd", 0.12)]])
			u.shape({"kind": "ring", "c": tp, "r": 160.0, "r1": 30.0, "w": 4.0, "col": c, "life": 0.45})
			support = true
		"suzuran":   # 狐火追向那批敌人：减速 2 秒、受到的伤害 +10%
			for e in p.nearest_enemies(6, 220.0, tp):
				if not _live(e):
					continue
				_tracer(u, p.pos + Vector2(0, -20), e.pos, c, 0.22, 5.0)
				_hit1(p, e, 1.0)
				if not e.dead:
					g.enemies_sys.lite_slow(e, Bal.v("ult/suzu_slow", 0.3), 2.0)
					e["frag_t"] = maxf(float(e.get("frag_t", 0.0)), g.t + 2.0)
					e["frag_v"] = maxf(float(e.get("frag_v", 0.0)), 0.1)
				hits.append(e)
	p.sparks(tp, Vector2.UP, c, 6, 140.0)
	_landed(u, a, tp, hits.size(), support)


# ---------------------------------------------------------------- linger：落地后持续的部分（不占干员）

static func _linger(u, o, d: Dictionary) -> void:
	d.merge({"k": "linger", "p": null, "o": o, "age": 0.0}, true)
	u.combo_acts.append(d)


static func _step_linger(u, a: Dictionary, dt: float) -> bool:
	var g = u.g
	var o = a.o
	a.age += dt
	var done: bool = a.age >= float(a.dur)
	if o == null or o.pos == Vector2.INF:
		done = true
	match str(a.kind):
		"lava":   # 每 0.5 秒烫一次
			var tk: int = int(a.age / 0.5)
			if tk > int(a.get("tk", 0)) and not done:
				a["tk"] = tk
				_area(o, a.c, float(a.r), 0.2)
			if int(a.age / 0.25) != int(a.get("vf", -1)):
				a["vf"] = int(a.age / 0.25)
				u.shape({"kind": "circle", "c": a.c, "r": float(a.r), "col": Color(1.0, 0.45, 0.15), "fill": 0.22, "life": 0.3})
		"after":   # 0.45 秒后余震
			if a.age >= 0.45 and not a.get("hit", false):
				a["hit"] = true
				_area(o, a.c, 150.0, 0.4, 160.0)
				_ring(u, a.c, 150.0, o.col(), 0.35)
				o.screen_shake(0.08)
		"pillars":   # 琥珀晶柱：队长身边 r 内的普通敌人被推出去
			var r: float = float(a.r)
			for e in u.in_circle(g.ppos, r):
				if e.boss:
					continue
				var dv: Vector2 = e.pos - g.ppos
				var dd: float = dv.length()
				var dirv: Vector2 = dv / dd if dd > 0.01 else Vector2.RIGHT
				o.nudge(e, dirv * (r - dd) * (0.5 if e.elite else 1.0))
			if int(a.age / 0.3) != int(a.get("vf", -1)):
				a["vf"] = int(a.age / 0.3)
				for i in 6:
					u.shape({"kind": "circle", "c": g.ppos + Vector2.from_angle(i * TAU / 6.0) * r, "r": 10.0, "col": Color(1.0, 0.75, 0.3), "fill": 0.7, "life": 0.32})
		"undying":   # 归溟幽灵鲨：2 秒里队长生命不会低于 1（squad.prevent_death 读 ev.undying_until）
			u.ev["undying_until"] = g.t + maxf(0.0, float(a.dur) - a.age)
		"float":   # 艾丽妮挑起的敌人：高度按 sin 曲线
			var k: float = clampf(a.age / float(a.dur), 0.0, 1.0)
			for e in a.list:
				if e.dead or e.boss:
					continue
				o.set_air(e, 0.0 if done else sin(k * PI) * float(a.h), not done)
		"pull":   # 重力弹：周围敌人被拉向中心
			for e in u.in_circle(a.c, float(a.r)):
				if e.boss:
					continue
				var dv: Vector2 = Vector2(a.c) - e.pos
				if dv.length() > 24.0:
					o.nudge(e, dv.normalized() * minf(dv.length() - 20.0, 320.0 * dt * (0.5 if e.elite else 1.0)))
	return done
