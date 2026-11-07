## 羁绊技 v2（docs/294，开关 balance link/bond_v2，缺省 0 = 完全不求值，回到 docs/217 的羁绊合击 + 常驻小加成）。
## HoloCure 式联动招式：两名有原作关系的干员同队、且两人都已精一 → 解锁这对人的羁绊技（演出卡），之后按冷却自动释放，
## 每次落下一个大图形覆盖一片（大 X / 一条航线 / 一圈光）。取代这对人原来的 60 秒羁绊合击（link_bond.pick 跳过）和常驻小加成（link_bond.refresh 跳过）。
## 8 条（docs/294 §4：宿敌 / 企鹅物流 / 灯下审决 + 深海猎人四对 + 群猎；11-07 用户定「一下的合击」，人物原地出手不移动不隐身）。
## 玩法：不抽随机数、不位移干员（只播出手动作）；伤害按目标生命预算（同 skill_link._dmg 口径，bond2/* 旋钮）。画面全在 render/fx_bond2.gd（只画，用 g.vrng）。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const BPF = preload("res://scripts/run/bond2_pf.gd")

## 3 对：成员、标签、招式名、一句话（docs/294 §4，玩家可见文字按 docs/76）
const MOVES := {
	"b_rival": {"ops": ["texas", "lappland"], "tag": "宿敌", "name": "狼衔剑", "desc": "拉普兰德唤出狼影，叼起德克萨斯的巨剑从怪群里一路犁过去，再把剑甩上天钉进终点；狼影掠过的敌人被沉默"},
	"b_penguin": {"ops": ["exusiai", "texas"], "tag": "企鹅物流", "name": "急件航线", "desc": "德克萨斯开车从怪群里碾过去，一路往两边丢炸弹；能天使朝怪群齐射"},
	"b_inq": {"ops": ["lumen", "irene"], "tag": "灯下审决", "name": "提灯宣判", "desc": "艾丽妮的提灯悬在怪群上空洒下金光，审判光矛随即从灯下劈落"},
	"b_lesson": {"ops": ["ulpianus", "skadi"], "tag": "手术刀", "name": "收力一剑", "desc": "乌尔比安掷锚咬住怪群往回拽，把一路的敌人拖到斯卡蒂面前，斯卡蒂收着力一剑劈下"},
	"b_tide": {"ops": ["gladiia", "specter_unchained"], "tag": "引潮夺命", "name": "串刺", "desc": "歌蕾蒂娅掷出长槊贯穿一排敌人再拽回，归溟幽灵鲨趁槊经过一刀锯开"},
	"b_vortex": {"ops": ["gladiia", "ulpianus"], "tag": "漩涡钉锚", "name": "钉桩回旋", "desc": "歌蕾蒂娅的长槊钉进怪群当桩，乌尔比安的锚链缠上长槊绕圈收紧，最后砸在槊旁"},
	"b_fins": {"ops": ["skadi", "specter_unchained"], "tag": "双鳍", "name": "击锯", "desc": "归溟幽灵鲨抛出锯刃，斯卡蒂抡剑把它击飞，锯刃一路锯过怪群后嵌地炸开"},
	"b_hunt": {"ops": [], "group": ["skadi", "gladiia", "specter_unchained", "ulpianus", "skalter"], "min": 3, "tag": "群猎", "name": "群猎合围", "desc": "一圈暗潮从四面合拢，猎人们的武器从潮里一齐刺向中心"},
}
const ORDER := ["b_hunt", "b_rival", "b_penguin", "b_inq", "b_lesson", "b_tide", "b_vortex", "b_fins"]
const HUNTER_PAIRS := ["b_lesson", "b_tide", "b_vortex", "b_fins"]   # 群猎成立后取代猎人两两羁绊技（docs/294 §5）
const SRC_TAGS := ["skill", "羁绊技"]


static func on() -> bool:
	return Bal.vi("link/bond_v2", 0) > 0


## 这条羁绊已由羁绊技接管（link_bond 的合击 / 常驻加成跳过它）
static func handles(bid: String) -> bool:
	return on() and MOVES.has(bid)


## 状态挂在 ult 上（u.get_meta("bond2")）：{unlocked: {id: t}, e2: {id: true}, next: {id: t}, last_any: t, acts: [], log: []}
static func st(u) -> Dictionary:
	if not u.has_meta("bond2"):
		u.set_meta("bond2", {"unlocked": {}, "e2": {}, "next": {}, "last_any": -INF, "acts": [], "log": []})
	return u.get_meta("bond2")


static func _op(g, oid: String):
	for p in g.squad.ops:
		if str(p.id) == oid and p.pos != Vector2.INF:
			return p
	return null


static func _pair(g, bid: String) -> Array:
	if MOVES[bid].has("group"):   # 群猎：在场且已精一的猎人 ≥ min 名才成立（按表序，最多 4 名）
		var ps: Array = []
		for oid in MOVES[bid].group:
			var p = _op(g, str(oid))
			if p != null and int(p.elite) >= 1:
				ps.append(p)
		return ps.slice(0, 4) if ps.size() >= int(MOVES[bid].get("min", 3)) else []
	var ids: Array = MOVES[bid].ops
	var a = _op(g, str(ids[0]))
	var b = _op(g, str(ids[1]))
	return [a, b] if a != null and b != null else []


static func _fx(g):
	if g.headless_batch or not g.is_inside_tree():
		return null
	return load("res://scripts/render/fx_bond2.gd").of(g)


## ult.tick 末尾调（PLAY 状态才到这里）
static func tick(u, dt: float) -> void:
	if not on():
		return
	var g = u.g
	var s: Dictionary = st(u)
	# 进行中的招
	var keep: Array = []
	for a in s.acts:
		if not _step(u, a, dt):
			keep.append(a)
	s.acts = keep
	# 解锁 / 强化 / 释放
	for bid in ORDER:
		var pr: Array = _pair(g, bid)
		if pr.is_empty():
			continue
		if HUNTER_PAIRS.has(bid) and s.unlocked.has("b_hunt") and not _pair(g, "b_hunt").is_empty():
			continue   # 群猎成立：猎人两两的羁绊技不再单独放
		var e1: bool = pr.all(func(p): return int(p.elite) >= 1)
		if not s.unlocked.has(bid):
			if not e1 or g.t < Bal.v("bond2/unlock_at", -1.0):   # 录像用（缺省 -1 = 关）：解锁不早于这个时刻（让演出卡出现在有怪的时候）
				continue
			s.unlocked[bid] = g.t
			s.next[bid] = g.t + Bal.v("bond2/first_delay", 0.6)   # 演出卡亮出后马上放第一次
			s.log.append({"id": bid, "ev": "unlock", "t": snappedf(g.t, 0.1)})
			if Bal.v("bond2/log", 0.0) > 0.0:
				print("BOND2 unlock %s t=%.1f" % [bid, g.t])
			var fx = _fx(g)
			if fx != null:
				fx.card(bid, pr, false)
			_sfx(g, "ui_ok", -5.0, 1.05)
		if not s.e2.has(bid) and pr.all(func(p): return int(p.elite) >= 2):
			s.e2[bid] = g.t
			s.log.append({"id": bid, "ev": "e2", "t": snappedf(g.t, 0.1)})
			var fx2 = _fx(g)
			if fx2 != null:
				fx2.card(bid, pr, true)
		if g.t < float(s.next.get(bid, INF)):
			continue
		if u.phase != "" or not s.acts.is_empty() or g.t - float(s.last_any) < Bal.v("bond2/gap", 6.0):
			continue
		if pr.any(func(p): return p.cmd_down > 0.0):
			continue
		var ld = g.squad.leader()
		var cpos: Vector2 = pr.reduce(func(acc, p): return acc + p.pos, Vector2.ZERO) / float(pr.size())
		if u.in_view(ld.pos if ld != null and ld.pos != Vector2.INF else cpos).size() < Bal.vi("bond2/min_foes", 6):
			continue
		var lp: Vector2 = ld.pos if ld != null and ld.pos != Vector2.INF else cpos   # 镜头跟队长：释放点挑队长附近、限在屏内（11-06 录像：挑到屏外只看到一根线）
		var c: Vector2 = u._densest(lp, Bal.v("bond2/reach", 380.0), 160.0)
		if c == Vector2.INF:
			continue
		var vw: Vector2 = Vector2(1524.0, 857.0) * Bal.v("bond2/view_k", 0.28)
		c = Vector2(clampf(c.x, lp.x - vw.x, lp.x + vw.x), clampf(c.y, lp.y - minf(vw.y, Bal.v("bond2/c_dy", 170.0)), lp.y + minf(vw.y, Bal.v("bond2/c_dy", 170.0))))   # 11-07：落点贴屏幕顶边会被演出卡 / HUD 盖住，上下限 c_dy
		if bid in ["b_hunt", "b_fins"]:   # 围着小队转的两条：落点往队长拉一半（11-07 录像：合围圈跑到屏幕角上被演出卡挡住）
			c = lp.lerp(c, 0.5)
		_cast(u, bid, pr, c, s.e2.has(bid))
		s.last_any = g.t
		s.next[bid] = g.t + (Bal.v("bond2/cd_e2", 20.0) if s.e2.has(bid) else Bal.v("bond2/cd", 22.0))


static func _sfx(g, k: String, db := -4.0, pitch := 1.0) -> void:
	var sfx: Node = g.get_node_or_null("/root/Sfx") if g.is_inside_tree() else null   # 核心契约测试不加载自动加载单例
	if sfx == null:
		return
	if sfx.has_method("ensure"):
		sfx.ensure([k])
	sfx.play(k, db, pitch, 0.03)


static func _cast(u, bid: String, pr: Array, c: Vector2, e2: bool) -> void:
	var g = u.g
	var ids: Array = MOVES[bid].ops
	var who := {}
	for p in pr:
		who[str(p.id)] = p
	for oid in ids:
		if not who.has(str(oid)):
			who[str(oid)] = null
	var from: Vector2 = pr.reduce(func(acc, p): return acc + p.pos, Vector2.ZERO) / float(pr.size())
	var d0: Vector2 = (c - from).normalized() if c != from else Vector2.RIGHT
	var k: float = Bal.v("bond2/size_e2", 1.0) if e2 else Bal.v("bond2/size", 1.0)
	var a := {"id": bid, "who": who, "c": c, "d0": d0, "k": k, "e2": e2, "age": 0.0, "done": {}, "fr": {}, "from": from}
	match bid:
		"b_rival":   # 狼衔剑：横向车道（同企鹅物流的车：狼影是侧面像，斜着走像在滑），从最密处后方 rv_run 拖到前方 rv_out；车道半宽 hw、终点钉剑半径 r
			var sx0: float = 1.0 if d0.x >= 0.0 else -1.0
			a["dl"] = Vector2(sx0, 0.0)
			var ld0 = g.squad.leader()
			var ly0: float = ld0.pos.y if ld0 != null and ld0.pos != Vector2.INF else from.y
			var cc: Vector2 = Vector2(c.x, clampf(c.y, ly0 - 60.0, ly0 + 160.0))
			a["c"] = cc
			a["S"] = cc - a.dl * Bal.v("bond2/rv_run", 260.0) * k
			a["E"] = cc + a.dl * Bal.v("bond2/rv_out", 260.0) * k
			a["hw"] = Bal.v("bond2/rival_hw", 50.0) * k
			a["r"] = Bal.v("bond2/rv_r", 110.0) * k
		"b_penguin":   # 碾过去：车只走横向（斜率封顶 0.12），从最密处后方 car_run 处冲进来、开过去 car_out；车道半宽 hw
			var sx: float = 1.0 if d0.x >= 0.0 else -1.0
			a["dl"] = Vector2(sx, 0.0).normalized()
			var ld = g.squad.leader()
			var ly: float = ld.pos.y if ld != null and ld.pos != Vector2.INF else from.y
			a["c"] = Vector2(c.x, clampf(c.y, ly - Bal.v("bond2/car_up", 40.0), ly + Bal.v("bond2/car_dn", 140.0)))   # 车身往上占 140：车道贴队长上方会被演出卡 / HUD 盖住
			a["run"] = Bal.v("bond2/car_run", 560.0)
			a["out"] = Bal.v("bond2/car_out", 340.0) * k
			a["hw"] = Bal.v("bond2/car_hw", 58.0) * k
			var bombs: Array = []   # 11-07 用户：车子往两边丢炸弹。[车开到车道第几成时丢, 左右, 落点]；落点在车道两侧 bomb_off 处
			var S: Vector2 = a.c - a.dl * float(a.run)
			var LL: float = float(a.run) + float(a.out)
			var nb: int = Bal.vi("bond2/bombs", 6)
			for i in nb:
				var kb: float = 0.3 + 0.55 * float(i) / float(maxi(1, nb - 1))
				var sd: float = 1.0 if i % 2 == 0 else -1.0
				var fk: float = kb * kb * 1.6 if kb < 0.25 else 0.1 + (kb - 0.25) * 1.2
				var lnd: Vector2 = S + a.dl * (LL * fk + 50.0) + a.dl.orthogonal() * sd * Bal.v("bond2/bomb_off", 130.0) * k
				bombs.append([kb, sd, lnd])
			a["bombs"] = bombs
			a["br"] = Bal.v("bond2/bomb_r", 80.0) * k
		"b_inq":   # 合击：提灯悬在最密处上空，光圈半径 r
			var lm = who.lumen
			a["O"] = c + Vector2(0, -Bal.v("bond2/lamp_h", 170.0))   # 提灯悬停点：落点正上方
			a["r"] = Bal.v("bond2/inq_r", 240.0) * k
		"b_lesson":   # 收力一剑：锚落在最密处再往外 ls_over（F，留在画面里）；拖回到斯卡蒂面前 Pp；钩住半径 hw、一剑半径 r
			var ul = who.ulpianus
			var skd = who.skadi
			var A0: Vector2 = (ul.pos if ul != null else from) + Vector2(0, -6)
			var dv: Vector2 = (c - A0).normalized() if c != A0 else d0
			a["A"] = A0
			var Fr: Vector2 = c + dv * Bal.v("bond2/ls_over", 120.0) * k
			var ldq = g.squad.leader()
			var lq: Vector2 = ldq.pos if ldq != null and ldq.pos != Vector2.INF else from
			a["F"] = Vector2(clampf(Fr.x, lq.x - 620.0, lq.x + 620.0), clampf(Fr.y, lq.y - 150.0, lq.y + 300.0))
			var kp: Vector2 = skd.pos if skd != null else A0
			a["Pp"] = kp + ((c - kp).normalized() if c != kp else d0) * Bal.v("bond2/ls_pile", 90.0)
			a["r"] = Bal.v("bond2/ls_r", 100.0) * k
			a["hw"] = Bal.v("bond2/ls_hw", 50.0) * k
		"b_tide":   # 串刺：槊从歌蕾蒂娅手里沿 G → E 飞（穿过最密处再往外 td_over，总长封顶 720）；幽灵鲨在 G–E 上的投影 P 处锯开（半径 r）；贯穿带半宽 hw
			var glw = who.gladiia
			var spw = who.specter_unchained
			var G: Vector2 = (glw.pos if glw != null else from) + Vector2(0, -6)
			var dd: Vector2 = (c - G).normalized() if c != G else d0
			var Ln: float = minf(G.distance_to(c) + Bal.v("bond2/td_over", 180.0) * k, 720.0)
			a["G"] = G
			a["E"] = G + dd * Ln
			var sp0: Vector2 = spw.pos if spw != null else G
			a["P"] = G + dd * clampf((sp0 - G).dot(dd), Ln * 0.15, Ln * 0.6)
			a["r"] = Bal.v("bond2/td_r", 90.0) * k
			a["hw"] = Bal.v("bond2/td_hw", 36.0) * k
		"b_vortex":   # 钉桩回旋：桩 = 最密处；锚绕桩起始半径 R、扫到半径 ar、最后砸地半径 r
			a["R"] = Bal.v("bond2/vx_r", 170.0) * k
			a["ar"] = Bal.v("bond2/vx_ar", 46.0) * k
			a["r"] = Bal.v("bond2/vx_slam", 130.0) * k
		"b_fins":   # 击锯：斯卡蒂面前 H 击飞，锯刃沿 H → E（穿过最密处再往外 fn_over）；锯道半宽 hw、嵌地半径 r
			var skf = who.skadi
			var K: Vector2 = skf.pos if skf != null else from
			var df: Vector2 = (c - K).normalized() if c != K else d0
			a["H"] = K + df * 40.0
			a["E"] = c + df * Bal.v("bond2/fn_over", 160.0) * k
			a["hw"] = Bal.v("bond2/fn_hw", 44.0) * k
			a["r"] = Bal.v("bond2/fn_r", 100.0) * k
		"b_hunt":   # 群猎合围：暗潮从 R0 合拢，圈心交汇半径 r
			a["ps"] = pr
			a["R0"] = Bal.v("bond2/ht_r0", 260.0) * k
			a["r"] = Bal.v("bond2/ht_r", 220.0) * k
	st(u).acts.append(a)
	var s: Dictionary = st(u)
	s.log.append({"id": bid, "ev": "cast", "t": snappedf(g.t, 0.1)})
	if Bal.v("bond2/log", 0.0) > 0.0:
		print("BOND2 cast %s t=%.1f e2=%s c=%s" % [bid, g.t, str(e2), str(c.round())])
	u.stats["bond2_" + bid] = int(u.stats.get("bond2_" + bid, 0)) + 1
	for p in pr:
		p._set_face(1.0 if c.x >= p.pos.x else -1.0, true)
	var fx = _fx(g)
	if fx != null:
		fx.cast(a)


static func _once(a: Dictionary, k: String) -> bool:
	if a.done.has(k):
		return false
	a.done[k] = true
	return true


## 伤害：按目标生命预算（同 skill_link._dmg）：小怪 = 当前基准生命 × bond2/minion，精英 / Boss 按最大生命比例；× 构筑倍率（封顶 bond2/build_cap）
## 同一次释放里同一只敌人累计份额封顶 bond2/frac_cap（精英 / Boss 不会被几段叠穿）
static func _hit(u, p, e: Dictionary, frac: float, nm: String, a: Dictionary) -> void:
	if e.dead or e.get("friendly", false) or p == null:
		return
	var eid: int = int(e.get("id", -1))
	var used: float = float(a.fr.get(eid, 0.0))
	var cap: float = Bal.v("bond2/frac_cap", 1.6)
	if (e.elite or e.boss or e.get("part", false)) and used >= cap:
		return
	if e.elite or e.boss or e.get("part", false):
		frac = minf(frac, cap - used)
	a.fr[eid] = used + frac
	var g = u.g
	var b: float
	if e.boss:
		b = e.maxhp * (Bal.v("bond2/final", 0.004) if e == g.final_boss else Bal.v("bond2/boss", 0.01))
	elif e.elite or e.get("part", false):
		b = e.maxhp * Bal.v("bond2/elite", 0.05)
	else:
		b = u.ref_hp() * Bal.v("bond2/minion", 1.2)
	var bm: float = minf(u.build_mult(p), Bal.v("bond2/build_cap", 1.5))
	p.log_hit(_src(p, nm), ["羁绊技"])
	p.deal_damage(e, b * frac * bm)


static func _src(p, nm: String) -> String:
	var k: String = "羁绊技·%s·%s" % [nm, str(p.id)]
	if not p.g.hit_src.has(k):
		p.g.hit_src[k] = {"emitter": "operator", "origin": "skill", "range": "范围", "kind": "物理", "tags": SRC_TAGS, "class": p.cls, "op": str(p.id)}
	return k


static func _ok(p) -> bool:
	return p != null and is_instance_valid(p) and p.pos != Vector2.INF


## 每帧推进一招；true = 结束
static func _step(u, a: Dictionary, dt: float) -> bool:
	a.age = float(a.age) + dt
	match str(a.id):
		"b_rival":
			return _rival(u, a, float(a.age))
		"b_penguin":
			return _penguin(u, a, float(a.age))
		"b_inq":
			return _inq(u, a, float(a.age))
		"b_lesson":
			return _lesson(u, a, float(a.age))
		"b_tide":
			return _tide(u, a, float(a.age))
		"b_vortex":
			return _vortex(u, a, float(a.age))
		"b_fins":
			return _fins(u, a, float(a.age))
		"b_hunt":
			return _hunt(u, a, float(a.age))
	return true


## 宿敌「狼衔剑」（docs/314，11-07 用户选）：拉普兰德唤出狼影、德克萨斯一柄巨剑插在车道起点（RV_DROP）；狼叼剑沿横向车道从 S 拖到 E
## （RV_GRAB–RV_RUN，剑尖犁地，带上的打一下、往两侧掀开，拉普兰德一侧沉默）；到头把剑甩上天、剑转一圈钉进 E（RV_STAB，一圈打一下往外推）
const RV_DROP := 0.3
const RV_GRAB := 0.5
const RV_RUN := 1.1
const RV_STAB := 1.45
static func rv_wolf(a: Dictionary, t: float) -> Vector2:   # 狼（剑柄）位置；画面同用
	var S: Vector2 = a.S
	var E: Vector2 = a.E
	if t < RV_GRAB:
		return S - Vector2(a.dl) * 60.0 * (1.0 - clampf(t / RV_GRAB, 0.0, 1.0))
	var k: float = clampf((t - RV_GRAB) / (RV_RUN - RV_GRAB), 0.0, 1.0)
	return S.lerp(E, k * k * (3.0 - 2.0 * k))
static func _rival(u, a: Dictionary, t: float) -> bool:
	var tx = a.who.texas
	var lp = a.who.lappland
	if _once(a, "go"):
		if _ok(lp):
			lp.play_vis_anim("skill")
		if _ok(tx):
			tx.play_vis_anim("attack")
		_sfx(u.g, "ult_lappland_impact", -6.0, 0.8)
	var drv = lp if _ok(lp) else tx
	if t >= RV_DROP and _once(a, "drop"):
		_sfx(u.g, "op_texas_s3_cut_1", -5.0, 0.8)
		for e in u.in_circle(a.S, 60.0):
			_hit(u, tx if _ok(tx) else lp, e, Bal.v("bond2/rv_drop", 0.3), "狼衔剑", a)
	if t >= RV_GRAB and t < RV_RUN + 0.05:
		var p: Vector2 = rv_wolf(a, t)
		var p0: Vector2 = a.get("wp", a.S)
		a["wp"] = p
		var hit: Dictionary = a.get("hitset", {})
		var nv: Vector2 = Vector2(a.dl).orthogonal()
		for e in u.in_band(p0, p, float(a.hw)):
			var eid: int = int(e.get("id", -1))
			if hit.has(eid):
				continue
			hit[eid] = true
			_hit(u, drv, e, Bal.v("bond2/rival_frac", 1.0), "狼衔剑", a)
			if not e.dead and not e.boss:
				var sd: float = 1.0 if (e.pos - p).dot(nv) >= 0.0 else -1.0
				drv.apply_kb(e, (nv * sd + Vector2(a.dl) * 0.3).normalized() * 200.0)
				if Bal.v("bond2/rival_silence", 1.0) > 0.0:
					u.g.enemies_sys.silence(e, u.g.t + (0.5 if e.elite else 1.0))
		a["hitset"] = hit
		if int(t * 15.0) % 2 == 0 and _once(a, "dust%d" % int(t * 15.0)):
			BPF.wolf_trail(u, a, p)
	if t >= RV_STAB and _once(a, "stab"):
		_sfx(u.g, "ult_texas_impact", -4.0, 0.75)
		for e in u.in_circle(a.E, float(a.r)):
			_hit(u, tx if _ok(tx) else lp, e, Bal.v("bond2/rv_stab", 0.8), "狼衔剑", a)
			if not e.dead and not e.boss:
				(tx if _ok(tx) else lp).apply_kb(e, (e.pos - Vector2(a.E)).normalized() * 180.0)
		BPF.rival_hit(u, a)
	return t >= 2.1


## 企鹅物流「急件航线」· 碾过去（11-07 用户：「一辆车直接碾过去」，不裂地）：能天使原地朝最密处齐射（0–0.6 秒，每 0.09 秒最近 3 只各一枪）；
## 德克萨斯的车（不画人）从画面外横向冲进来、穿过最密处再开出去（0.10–0.75 秒），车身扫过的带状区域打一下、往两侧撞开；车后一路扬尘
const PG_T0 := 0.4
const PG_T1 := 1.7
const PG_BOMB := 0.4   # 炸弹出手到落地
static func _penguin(u, a: Dictionary, t: float) -> bool:
	var ex = a.who.exusiai
	var tx = a.who.texas
	var c: Vector2 = a.c
	var dl: Vector2 = a.dl
	var driver = tx if _ok(tx) else ex
	var shooter = ex if _ok(ex) else tx
	if _once(a, "go"):
		if _ok(ex):
			ex.play_vis_anim("attack")
		if _ok(tx):
			tx.play_vis_anim("skill")
		_sfx(u.g, "op_exusiai_s3", -6.0, 1.0)
	var nshot: int = int(clampf(t - 0.2, 0.0, 1.2) / 0.12)
	while int(a.done.get("shots", 0)) < nshot:
		a.done["shots"] = int(a.done.get("shots", 0)) + 1
		var near: Array = u.in_circle(c, 220.0)
		near.sort_custom(func(x, y): return x.pos.distance_squared_to(c) < y.pos.distance_squared_to(c))
		var tg: Array = near.slice(0, 3)
		for e in tg:
			_hit(u, shooter, e, Bal.v("bond2/pg_shot", 0.3), "急件航线", a)
		var fx = _fx(u.g)
		if fx != null and _ok(shooter):
			fx.shots(a, shooter.pos, tg.map(func(e): return e.pos))
		if int(a.done.shots) % 2 == 0:
			_sfx(u.g, "op_exusiai_atk", -10.0, 1.0)
	if t >= PG_T0:
		if _once(a, "vroom"):
			_sfx(u.g, "ult_texas_impact", -6.0, 0.7)
		var uu: float = clampf((t - PG_T0) / (PG_T1 - PG_T0), 0.0, 1.0)
		var k: float = uu * uu * 1.6 if uu < 0.25 else 0.1 + (uu - 0.25) * 1.2   # 同画面 _car_pos：先加速后匀速
		var p: Vector2 = c - dl * float(a.run) + dl * (float(a.run) + float(a.out)) * k
		var p0: Vector2 = a.get("cp", c - dl * float(a.run))
		a["cp"] = p
		var hit: Dictionary = a.get("hitset", {})
		for e in u.in_band(p0, p, float(a.hw)):
			var eid: int = int(e.get("id", -1))
			if hit.has(eid):
				continue
			hit[eid] = true
			_hit(u, driver, e, Bal.v("bond2/pg_frac", 1.2), "急件航线", a)
			if not e.dead and not e.boss:
				var side: float = 1.0 if (e.pos - p).dot(dl.orthogonal()) >= 0.0 else -1.0
				driver.apply_kb(e, (dl.orthogonal() * side + dl * 0.5).normalized() * 190.0)
		a["hitset"] = hit
		for bi in a.bombs.size():
			var bm: Array = a.bombs[bi]
			if t >= PG_T0 + float(bm[0]) * (PG_T1 - PG_T0) + PG_BOMB and _once(a, "b%d" % bi):
				for e in u.in_circle(bm[2], float(a.br)):
					var eid2: int = int(e.get("id", -1))
					if hit.has(eid2):
						continue
					hit[eid2] = true
					_hit(u, driver, e, Bal.v("bond2/pg_frac", 1.2), "急件航线", a)
				_sfx(u.g, "op_exusiai_atk", -8.0, 0.6)
				BPF.bomb_hit(u, a, bm[2], bi)
		a["hitset"] = hit
		var nd: int = int(k * 10.0)
		while int(a.done.get("dust", 0)) < nd:
			a.done["dust"] = int(a.done.get("dust", 0)) + 1
			BPF.penguin_trail(u, a, p, int(a.done.dust))
	return t >= 2.4


## 灯下审决「提灯宣判」· 合击（11-07 用户：灯塔和流明自己的技能重复，改「提灯悬空洒金光」）：两人原地出手，艾丽妮的手提灯飞到最密处上空停住（0–0.3 秒），
## 灯罩打开、暖金光点像雨一样洒下（0.35–0.75 秒），光里的敌人亮紫印；艾丽妮再出手（0.55），一道审判光矛从灯下直劈下来（0.78）：光圈里的一齐受审
const IQ_HIT := 1.5
static func _inq(u, a: Dictionary, t: float) -> bool:
	var lm = a.who.lumen
	var ir = a.who.irene
	var c: Vector2 = a.c
	if _once(a, "go"):
		if _ok(lm):
			lm.play_vis_anim("skill")
		_sfx(u.g, "op_lumen_s2", -5.0, 0.9)
		if _ok(ir):
			ir.play_vis_anim("skill")
	if t >= 0.55 and _once(a, "ir"):
		if _ok(ir):
			ir.play_vis_anim("attack")
		_sfx(u.g, "op_irene_atk", -6.0, 0.9)
	if t >= IQ_HIT and _once(a, "judge"):
		_sfx(u.g, "op_irene_big", -4.0, 1.0)
		for e in u.in_circle(c, float(a.r)):
			_hit(u, ir if _ok(ir) else lm, e, Bal.v("bond2/inq_frac", 1.2), "提灯宣判", a)
		BPF.inq_hit(u, a)
	return t >= 2.1


## 手术刀「收力一剑」（docs/314，原作：乌尔比安把锚叫「手术刀」、教斯卡蒂节制用力）：乌尔比安头顶抡锚（LS_SPIN–LS_THROW）掷进怪群远端 F，
## 锚爪咬地（LS_BITE，一圈打一下）；往回一拽（LS_PULL–LS_PILE），锚经过的怪被钩住拖到斯卡蒂面前 Pp 堆成一堆；斯卡蒂一剑劈下（LS_CUT），只炸这一堆
const LS_SPIN := 0.08
const LS_THROW := 0.42
const LS_BITE := 0.62
const LS_PULL := 0.8
const LS_PILE := 1.12
const LS_CUT := 1.24
static func ls_anchor(a: Dictionary, t: float) -> Vector2:   # 锚落点（地面）；抡锚 / 飞行阶段由画面另算
	var F: Vector2 = a.F
	var Pp: Vector2 = a.Pp
	if t < LS_PULL:
		return F
	var k: float = clampf((t - LS_PULL) / (LS_PILE - LS_PULL), 0.0, 1.0)
	return F.lerp(Pp + (F - Pp).normalized() * 28.0, k * k)
static func _lesson(u, a: Dictionary, t: float) -> bool:
	var ul = a.who.ulpianus
	var sk = a.who.skadi
	var hu = ul if _ok(ul) else sk
	if _once(a, "go"):
		if _ok(ul):
			ul.play_vis_anim("attack")
		_sfx(u.g, "op_ulpianus_flesh_1", -5.0, 0.8)
	if t >= LS_BITE and _once(a, "bite"):
		_sfx(u.g, "ult_texas_impact", -6.0, 0.6)
		for e in u.in_circle(a.F, 70.0):
			_hit(u, hu, e, Bal.v("bond2/ls_bite", 0.3), "收力一剑", a)
		BPF.lesson_land(u, a)
	if t >= LS_PULL and t < LS_PILE + 0.03:
		var p: Vector2 = ls_anchor(a, t)
		var hook: Dictionary = a.get("hook", {})
		for e in u.in_circle(p, float(a.hw)):
			var eid: int = int(e.get("id", -1))
			if hook.has(eid) or e.boss:
				continue
			hook[eid] = true
			_hit(u, hu, e, Bal.v("bond2/ls_hook", 0.3), "收力一剑", a)
			var dv: Vector2 = Vector2(a.Pp) - e.pos
			hu.apply_kb(e, dv.normalized() * minf(dv.length() * 2.4, 420.0))
		a["hook"] = hook
	if t >= LS_CUT - 0.18 and _once(a, "sk"):
		if _ok(sk):
			sk.play_vis_anim("attack")
	if t >= LS_CUT and _once(a, "cut"):
		_sfx(u.g, "op_skadi_flesh_1", -3.0, 0.85)
		for e in u.in_circle(a.Pp, float(a.r)):
			_hit(u, sk if _ok(sk) else ul, e, Bal.v("bond2/ls_frac", 1.2), "收力一剑", a)
		BPF.lesson_cut(u, a)
	return t >= 1.95


## 引潮夺命「串刺」（docs/314，11-07 用户选）：歌蕾蒂娅掷长槊（原作长槊贯穿首言者），槊从她手里沿 G → E 飞出（TD_THROW–TD_STICK），
## 一路贯穿的怪打一下、离槊最近的几只串在槊上；槊尾一顿后被拽回（TD_PULL，串着的往她那边拖）；幽灵鲨在槊经过她面前时一刀锯开（TD_SAW）
const TD_THROW := 0.22
const TD_STICK := 0.42
const TD_PULL := 0.62
const TD_BACK := 1.05
const TD_SAW := 0.86
static func td_head(a: Dictionary, t: float) -> Vector2:   # 槊尖位置；画面同用
	var G: Vector2 = a.G
	var E: Vector2 = a.E
	if t < TD_THROW:
		return G
	if t < TD_STICK:
		var k: float = (t - TD_THROW) / (TD_STICK - TD_THROW)
		return G.lerp(E, 1.0 - pow(1.0 - k, 4.0))
	if t < TD_PULL:
		return E
	var k2: float = clampf((t - TD_PULL) / (TD_BACK - TD_PULL), 0.0, 1.0)
	return E.lerp(G + (E - G).normalized() * 40.0, k2 * k2 * (3.0 - 2.0 * k2))
static func _tide(u, a: Dictionary, t: float) -> bool:
	var gl = a.who.gladiia
	var sp = a.who.specter_unchained
	var gw = gl if _ok(gl) else sp
	if _once(a, "go"):
		if _ok(gl):
			gl.play_vis_anim("attack")
		_sfx(u.g, "op_gladiia_flesh_1", -5.0, 0.9)
	var d: Vector2 = (Vector2(a.E) - Vector2(a.G)).normalized()
	if t >= TD_THROW and t < TD_STICK + 0.03:
		var p: Vector2 = td_head(a, t)
		var p0: Vector2 = a.get("hp", a.G)
		a["hp"] = p
		var hit: Dictionary = a.get("hitset", {})
		var sk: Array = a.get("skew", [])
		for e in u.in_band(p0, p, float(a.hw)):
			var eid: int = int(e.get("id", -1))
			if hit.has(eid):
				continue
			hit[eid] = true
			_hit(u, gw, e, Bal.v("bond2/td_frac", 0.6), "串刺", a)
			var off: float = (e.pos - p).dot(d.orthogonal())
			if not e.dead and not e.boss and absf(off) < float(a.hw) * 0.6 and sk.size() < Bal.vi("bond2/td_skew", 9):
				sk.append(e)
			elif not e.dead and not e.boss:
				gw.apply_kb(e, d.orthogonal() * signf(off) * 160.0)
		a["hitset"] = hit
		a["skew"] = sk
	if t >= TD_STICK and _once(a, "stick"):
		_sfx(u.g, "ult_texas_impact", -7.0, 0.7)
		BPF.tide_open(u, a)
	if t >= TD_PULL and _once(a, "pull"):
		for e in a.get("skew", []):
			if not e.dead:
				var dv: Vector2 = Vector2(a.P) - e.pos
				gw.apply_kb(e, dv.normalized() * minf(dv.length() * 2.2, 420.0))
	if t >= TD_SAW - 0.1 and _once(a, "sp"):
		if _ok(sp):
			sp.play_vis_anim("attack")
	if t >= TD_SAW and _once(a, "saw"):
		_sfx(u.g, "op_specter_unchained_flesh_1", -3.0, 0.9)
		var hs: Dictionary = {}
		for e in a.get("skew", []):
			if not e.dead:
				hs[int(e.get("id", -1))] = true
				_hit(u, sp if _ok(sp) else gl, e, Bal.v("bond2/td_saw", 0.8), "串刺", a)
		for e in u.in_circle(a.P, float(a.r)):
			if not hs.has(int(e.get("id", -1))):
				_hit(u, sp if _ok(sp) else gl, e, Bal.v("bond2/td_saw", 0.8), "串刺", a)
		BPF.tide_saw(u, a)
	return t >= 1.8


## 漩涡钉锚「钉桩回旋」（docs/314）：歌蕾蒂娅的长槊从天上钉进最密处当桩（VX_STAKE，原作乌尔比安「向歌蕾蒂娅核实坐标」）；
## 乌尔比安头顶抡锚（VX_SPIN–VX_THROW）掷出，锚链缠上长槊（VX_WRAP），锚绕槊甩一圈、越绕越紧（VX_WRAP–VX_SLAM：扫到的打一下、往桩拖），最后砸在槊旁（VX_SLAM，一圈打一下）
const VX_STAKE := 0.32
const VX_SPIN := 0.12
const VX_THROW := 0.6
const VX_WRAP := 0.85
const VX_SLAM := 1.6
const VX_SQ := 0.55
static func vx_ang(t: float) -> float:
	var k: float = clampf((t - VX_WRAP) / (VX_SLAM - VX_WRAP), 0.0, 1.0)
	return -0.2 + k * k * TAU * 1.2
static func vx_rad(a: Dictionary, t: float) -> float:
	var k: float = clampf((t - VX_WRAP) / (VX_SLAM - VX_WRAP), 0.0, 1.0)
	return float(a.R) * (1.0 - 0.82 * k * k)
static func vx_anchor(a: Dictionary, t: float) -> Vector2:   # 绕桩阶段的锚（地面）
	var c: Vector2 = a.c
	var an: float = vx_ang(t)
	return c + Vector2(cos(an), sin(an) * VX_SQ) * vx_rad(a, t)
static func _vortex(u, a: Dictionary, t: float) -> bool:
	var gl = a.who.gladiia
	var ul = a.who.ulpianus
	var c: Vector2 = a.c
	var hu = ul if _ok(ul) else gl
	if _once(a, "go"):
		if _ok(gl):
			gl.play_vis_anim("attack")
		_sfx(u.g, "op_gladiia_flesh_1", -5.0, 0.8)
	if t >= VX_STAKE and _once(a, "stake"):
		_sfx(u.g, "ult_texas_impact", -7.0, 0.8)
		for e in u.in_circle(c, 50.0):
			_hit(u, gl if _ok(gl) else ul, e, Bal.v("bond2/vx_stake", 0.3), "钉桩回旋", a)
	if t >= VX_THROW - 0.06 and _once(a, "ul"):
		if _ok(ul):
			ul.play_vis_anim("attack")
		_sfx(u.g, "op_ulpianus_flesh_1", -5.0, 0.7)
	if t >= VX_WRAP and t < VX_SLAM:
		var p: Vector2 = vx_anchor(a, t)
		var sw: Dictionary = a.get("hitset", {})
		for e in u.in_circle(p, float(a.ar)):
			var eid: int = int(e.get("id", -1))
			if sw.has(eid):
				continue
			sw[eid] = true
			_hit(u, hu, e, Bal.v("bond2/vx_sweep", 0.4), "钉桩回旋", a)
			if not e.dead and not e.boss:
				var dv: Vector2 = c - e.pos
				hu.apply_kb(e, dv.normalized() * minf(dv.length() * 2.0, 300.0))
		a["hitset"] = sw
	if t >= VX_SLAM and _once(a, "slam"):
		_sfx(u.g, "ult_texas_impact", -3.0, 0.6)
		for e in u.in_circle(c, float(a.r)):
			_hit(u, hu, e, Bal.v("bond2/vx_frac", 1.0), "钉桩回旋", a)
		BPF.vortex_anchor(u, a, c, 0)
	return t >= 2.2


## 双鳍「击锯」（docs/314，11-07 用户「锯子 + 剑」）：幽灵鲨把锯刃转着抛高（FN_TOSS–FN_BAT），斯卡蒂抡巨剑像挥棒一样把它击飞（FN_BAT），
## 锯刃从 H 沿一条直道锯到 E（FN_GO–FN_END：带上的打一下、往两侧掀开），嵌进地里炸开（FN_END，一圈打一下）
const FN_TOSS := 0.12
const FN_BAT := 0.55
const FN_GO := 0.63
const FN_END := 1.0
static func fn_saw(a: Dictionary, t: float) -> Vector2:   # 锯刃地面投影（击飞后）
	var H: Vector2 = a.H
	var E: Vector2 = a.E
	var k: float = clampf((t - FN_GO) / (FN_END - FN_GO), 0.0, 1.0)
	return H.lerp(E, 1.0 - (1.0 - k) * (1.0 - k))
static func _fins(u, a: Dictionary, t: float) -> bool:
	var sk = a.who.skadi
	var sp = a.who.specter_unchained
	var bw = sk if _ok(sk) else sp
	if _once(a, "go"):
		if _ok(sp):
			sp.play_vis_anim("attack")
		_sfx(u.g, "op_specter_unchained_flesh_1", -6.0, 1.1)
	if t >= FN_BAT - 0.15 and _once(a, "sk"):
		if _ok(sk):
			sk.play_vis_anim("attack")
	if t >= FN_BAT and _once(a, "bat"):
		_sfx(u.g, "op_skadi_flesh_1", -3.0, 0.8)
	if t >= FN_GO and t < FN_END + 0.03:
		var p: Vector2 = fn_saw(a, t)
		var p0: Vector2 = a.get("spp", a.H)
		a["spp"] = p
		var hit: Dictionary = a.get("hitset", {})
		var d: Vector2 = (Vector2(a.E) - Vector2(a.H)).normalized()
		for e in u.in_band(p0, p, float(a.hw)):
			var eid: int = int(e.get("id", -1))
			if hit.has(eid):
				continue
			hit[eid] = true
			_hit(u, sp if _ok(sp) else sk, e, Bal.v("bond2/fn_frac", 1.0), "击锯", a)
			if not e.dead and not e.boss:
				var off: float = (e.pos - p).dot(d.orthogonal())
				bw.apply_kb(e, (d.orthogonal() * (1.0 if off >= 0.0 else -1.0) + d * 0.3).normalized() * 190.0)
		a["hitset"] = hit
	if t >= FN_END and _once(a, "end"):
		_sfx(u.g, "ult_texas_impact", -4.0, 0.9)
		for e in u.in_circle(a.E, float(a.r)):
			_hit(u, bw, e, Bal.v("bond2/fn_end", 0.6), "击锯", a)
			if not e.dead and not e.boss:
				bw.apply_kb(e, (e.pos - Vector2(a.E)).normalized() * 170.0)
		BPF.fins_dive(u, a)
	return t >= 1.7


## 群猎「群猎合围」· 合击（docs/294 §5 + docs/296 第八轮「暗潮合围」）：在场猎人原地出手，一圈暗潮从外圈 R0 往里合拢到 60（0–0.6 秒，
## 浪唇翻白沫，潮头扫过的怪往里卷）；各人的武器从潮里朝圈心刺出（0.6–0.72），在圈心交汇（0.74：半径 r 打一下）。浊心斯卡蒂不刺：在圈心起一圈歌声环
const HT_T1 := 1.15
const HT_HIT := 1.4
static func _hunt(u, a: Dictionary, t: float) -> bool:
	var c: Vector2 = a.c
	var ps: Array = a.ps
	if _once(a, "go"):
		for p in ps:
			if _ok(p):
				p.play_vis_anim("attack")
		_sfx(u.g, "op_gladiia_flesh_1", -5.0, 0.7)
	var k: float = clampf(t / HT_T1, 0.0, 1.0)
	var rr: float = lerpf(float(a.R0), 60.0, k * k)
	var pr0: float = float(a.get("rr", a.R0))
	a["rr"] = rr
	if t < HT_T1:
		var pushed: Dictionary = a.get("pushed", {})
		for e in u.in_circle(c, pr0 + 10.0):
			var eid: int = int(e.get("id", -1))
			if pushed.has(eid) or e.dead or e.boss:
				continue
			var dd: float = e.pos.distance_to(c)
			if dd >= rr - 20.0:
				pushed[eid] = true
				if _ok(ps[0]):
					ps[0].apply_kb(e, (c - e.pos).normalized() * minf(dd * 1.2, 240.0))
		a["pushed"] = pushed
	if t >= HT_HIT and _once(a, "hit"):
		_sfx(u.g, "ult_texas_impact", -4.0, 0.6)
		var i := 0
		for e in u.in_circle(c, float(a.r)):
			var p = ps[i % ps.size()]
			i += 1
			_hit(u, p if _ok(p) else ps[0], e, Bal.v("bond2/ht_frac", 1.2), "群猎合围", a)
		BPF.hunt_hit(u, a)
	return t >= 2.0


## 作战记录 / 测试用：本局解锁与释放
static func summary(u) -> Dictionary:
	if not on() or not u.has_meta("bond2"):
		return {}
	var s: Dictionary = st(u)
	return {"unlocked": s.unlocked.duplicate(), "e2": s.e2.duplicate(), "log": s.log.duplicate()}
