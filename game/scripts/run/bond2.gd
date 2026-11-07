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
	"b_rival": {"ops": ["texas", "lappland"], "tag": "宿敌", "name": "十字旧怨", "desc": "两人同时挥剑，两道剑气在怪群中心相撞炸开；拉普兰德一侧附带沉默"},
	"b_penguin": {"ops": ["exusiai", "texas"], "tag": "企鹅物流", "name": "急件航线", "desc": "德克萨斯开车从怪群里碾过去，一路往两边丢炸弹；能天使朝怪群齐射"},
	"b_inq": {"ops": ["lumen", "irene"], "tag": "灯下审决", "name": "提灯宣判", "desc": "艾丽妮的提灯悬在怪群上空洒下金光，审判光矛随即从灯下劈落"},
	"b_lesson": {"ops": ["ulpianus", "skadi"], "tag": "潮下授课", "name": "链上疾驰", "desc": "乌尔比安把锚掷过怪群、锚链绷直，斯卡蒂的浪锋沿锚链一路冲过去"},
	"b_tide": {"ops": ["gladiia", "specter_unchained"], "tag": "引潮夺命", "name": "引潮断线", "desc": "歌蕾蒂娅一钩拉开海沟、把两侧的敌人拖进去，归溟幽灵鲨沿海沟斩过"},
	"b_vortex": {"ops": ["gladiia", "ulpianus"], "tag": "漩涡钉锚", "name": "涡心落锚", "desc": "歌蕾蒂娅画出推演箭头把敌人往中心推，乌尔比安的锚依次砸在箭头尖上"},
	"b_fins": {"ops": ["skadi", "specter_unchained"], "tag": "双鳍", "name": "双鳍破浪", "desc": "两片背鳍绕着怪群交错游一圈，最后在圈心扎进水里"},
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
		"b_rival":   # 十字斩：交点 = 最密处；两刀各长 L、半宽 hw（画面上压扁成地面角度）
			var ang: float = Bal.v("bond2/rival_ang", 0.55)
			a["d1"] = Vector2(cos(ang), sin(ang))
			a["d2"] = Vector2(-cos(ang), sin(ang))
			a["L"] = Bal.v("bond2/rival_len", 560.0) * k
			a["hw"] = Bal.v("bond2/rival_hw", 46.0) * k
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
		"b_lesson":   # 链上疾驰：锚落在最密处再往外 ls_over（远端），锚链从乌尔比安到锚；落地圈 r、锚链带半宽 hw
			var ul = who.ulpianus
			var A0: Vector2 = ul.pos + Vector2(0, -6)
			var dv: Vector2 = (c - A0).normalized() if c != A0 else d0
			a["A"] = A0
			var Fr: Vector2 = c + dv * Bal.v("bond2/ls_over", 160.0) * k
			var ldq = g.squad.leader()
			var lq: Vector2 = ldq.pos if ldq != null and ldq.pos != Vector2.INF else from
			a["F"] = Vector2(clampf(Fr.x, lq.x - 620.0, lq.x + 620.0), clampf(Fr.y, lq.y - 150.0, lq.y + 300.0))   # 锚落点留在画面里（锚高 150，顶上有演出卡）
			a["r"] = Bal.v("bond2/ls_r", 110.0) * k
			a["hw"] = Bal.v("bond2/ls_hw", 52.0) * k
		"b_tide":   # 引潮断线：海沟过最密处、垂直于小队 → 落点方向；长 L、拖拽范围 pull、斩浪带半宽 hw
			a["d"] = d0.orthogonal()
			a["L"] = Bal.v("bond2/td_len", 520.0) * k
			a["pull"] = Bal.v("bond2/td_pull", 150.0) * k
			a["hw"] = Bal.v("bond2/td_hw", 60.0) * k
		"b_vortex":   # 涡心落锚：外圈 R 上五支箭头，箭头尖在 0.45 R 处；每只锚落点半径 ar
			a["R"] = Bal.v("bond2/vx_r", 260.0) * k
			a["ar"] = Bal.v("bond2/vx_ar", 80.0) * k
			var tips: Array = []
			var a0: float = fposmod(g.t * 1.3, TAU)   # 只取转角，不抽随机数
			for i in 5:
				tips.append(c + Vector2.from_angle(a0 + TAU * float(i) / 5.0) * float(a.R) * 0.45 * Vector2(1.0, 0.72))
			a["tips"] = tips
		"b_fins":   # 双鳍破浪：绕最密处游一圈的半径 R（扎水时圈里打一下）
			a["R"] = Bal.v("bond2/fn_r", 200.0) * k
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


## 宿敌「十字旧怨」· 十字斩（11-07 用户：改成斩击，选「十字斩裂地」）：两人原地出手（0 秒），落点先闪一下 X 形预兆细线，
## 德克萨斯一刀（左上 → 右下，0.24 秒）、拉普兰德一刀（右上 → 左下，0.32 秒）在最密处交成大 X，斩痕带上的各打一下；
## 拉普兰德那一刀附带沉默；交点 0.34 秒炸开（只画）
const RV_T1 := 0.6
const RV_T2 := 0.82
const RV_HIT := 0.88
static func _rival(u, a: Dictionary, t: float) -> bool:
	var tx = a.who.texas
	var lp = a.who.lappland
	var c: Vector2 = a.c
	if _once(a, "go"):
		if _ok(tx):
			tx.play_vis_anim("attack")
		if _ok(lp):
			lp.play_vis_anim("attack")
		_sfx(u.g, "op_texas_s3", -6.0, 1.05)
	var hit: Dictionary = a.get("hitset", {})
	for cut in [[RV_T1, "c1", tx, a.d1, false], [RV_T2, "c2", lp, a.d2, true]]:
		if t >= float(cut[0]) and _once(a, str(cut[1])):
			var who = cut[2] if _ok(cut[2]) else (tx if _ok(tx) else lp)
			var d: Vector2 = cut[3]
			var L: float = float(a.L)
			_sfx(u.g, "op_texas_s3_cut_1" if not bool(cut[4]) else "ult_lappland_impact", -4.0, 0.9)
			for e in u.in_band(c - d * L * 0.5, c + d * L * 0.5, float(a.hw)):
				var eid: int = int(e.get("id", -1))
				if hit.has(eid):
					continue
				hit[eid] = true
				_hit(u, who, e, Bal.v("bond2/rival_frac", 1.2), "十字旧怨", a)
				if bool(cut[4]) and Bal.v("bond2/rival_silence", 1.0) > 0.0 and not e.dead and not e.boss:
					u.g.enemies_sys.silence(e, u.g.t + (0.5 if e.elite else 1.0))
	a["hitset"] = hit
	if t >= RV_HIT and _once(a, "x"):
		BPF.rival_hit(u, a)
	return t >= 1.9


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


## 潮下授课「链上疾驰」· 合击（docs/296 第七轮用户选定，11-07 改合击：人物原地出手）：乌尔比安原地掷锚，巨锚越过最密处砸在远端（0.05–0.28 秒，落地打一圈），
## 锚链从他手里绷直横跨怪群；斯卡蒂原地出手，一道深海蓝浪锋沿锚链从近到远冲过去（0.38–0.62 秒，锚链两侧的带状区域打一下），锚链随后收回
const LS_LAND := 0.6
const LS_S0 := 0.95
const LS_S1 := 1.45
static func _lesson(u, a: Dictionary, t: float) -> bool:
	var ul = a.who.ulpianus
	var sk = a.who.skadi
	if _once(a, "go"):
		if _ok(ul):
			ul.play_vis_anim("attack")
		_sfx(u.g, "op_ulpianus_flesh_1", -5.0, 0.8)
	var hit: Dictionary = a.get("hitset", {})
	if t >= LS_LAND and _once(a, "land"):
		_sfx(u.g, "ult_texas_impact", -5.0, 0.6)
		for e in u.in_circle(a.F, float(a.r)):
			hit[int(e.get("id", -1))] = true
			_hit(u, ul if _ok(ul) else sk, e, Bal.v("bond2/ls_frac", 1.2), "链上疾驰", a)
		BPF.lesson_land(u, a)
	if t >= LS_S0 - 0.1 and _once(a, "sk"):
		if _ok(sk):
			sk.play_vis_anim("attack")
		_sfx(u.g, "op_skadi_flesh_1", -5.0, 1.0)
	if t >= LS_S0:
		var k: float = clampf((t - LS_S0) / (LS_S1 - LS_S0), 0.0, 1.0)
		var A: Vector2 = a.A
		var F: Vector2 = a.F
		var p: Vector2 = A.lerp(F, k)
		var p0: Vector2 = a.get("sp", A)
		a["sp"] = p
		for e in u.in_band(p0, p, float(a.hw)):
			var eid: int = int(e.get("id", -1))
			if hit.has(eid):
				continue
			hit[eid] = true
			_hit(u, sk if _ok(sk) else ul, e, Bal.v("bond2/ls_frac", 1.2), "链上疾驰", a)
	a["hitset"] = hit
	return t >= 2.1


## 引潮夺命「引潮断线」· 合击（docs/296 第八轮「海沟」）：歌蕾蒂娅原地甩钩，钩线横过最密处（0.05–0.2），地面沿钩线裂开一道锯齿海沟（0.25），
## 两侧 pull 内的怪被拖向海沟；幽灵鲨原地出手，一道斩浪沿海沟从一头冲到另一头（0.5–0.72 秒，海沟两侧带状区域打一下），海沟 1.0 秒合拢
const TD_OPEN := 0.55
const TD_S0 := 1.05
const TD_S1 := 1.5
static func _tide(u, a: Dictionary, t: float) -> bool:
	var gl = a.who.gladiia
	var sp = a.who.specter_unchained
	var c: Vector2 = a.c
	var d: Vector2 = a.d
	var L: float = a.L
	if _once(a, "go"):
		if _ok(gl):
			gl.play_vis_anim("attack")
		_sfx(u.g, "op_gladiia_flesh_1", -5.0, 0.9)
	if t >= TD_OPEN and _once(a, "open"):
		_sfx(u.g, "ult_texas_impact", -6.0, 0.55)
		var nv: Vector2 = d.orthogonal()
		for e in u.in_band(c - d * L * 0.5, c + d * L * 0.5, float(a.pull)):
			if e.dead or e.boss:
				continue
			var off: float = (e.pos - c).dot(nv)
			if absf(off) > 20.0:
				(gl if _ok(gl) else sp).apply_kb(e, -nv * signf(off) * minf(absf(off) * 2.2, 260.0))
		BPF.tide_open(u, a)
	if t >= TD_S0 - 0.08 and _once(a, "sp"):
		if _ok(sp):
			sp.play_vis_anim("attack")
		_sfx(u.g, "op_specter_unchained_flesh_1", -4.0, 1.0)
	if t >= TD_S0:
		var k: float = clampf((t - TD_S0) / (TD_S1 - TD_S0), 0.0, 1.0)
		var A: Vector2 = c - d * L * 0.5
		var p: Vector2 = A + d * L * k
		var p0: Vector2 = a.get("sp", A)
		a["sp"] = p
		var hit: Dictionary = a.get("hitset", {})
		for e in u.in_band(p0, p, float(a.hw)):
			var eid: int = int(e.get("id", -1))
			if hit.has(eid):
				continue
			hit[eid] = true
			_hit(u, sp if _ok(sp) else gl, e, Bal.v("bond2/td_frac", 1.2), "引潮断线", a)
		a["hitset"] = hit
	return t >= 2.2


## 漩涡钉锚「涡心落锚」· 合击（docs/296 第八轮「作战推演」）：歌蕾蒂娅原地出手，地上一支支画出五支推演箭头从外圈指向中心（0.05–0.4），
## 圈里的怪被往中心推（0.4）；乌尔比安原地出手，五只锚从高处依次砸在箭头尖上（0.6–0.84，每只落点一圈打一下）
const VX_PUSH := 0.85
const VX_A0 := 1.15
const VX_DA := 0.12
static func _vortex(u, a: Dictionary, t: float) -> bool:
	var gl = a.who.gladiia
	var ul = a.who.ulpianus
	var c: Vector2 = a.c
	if _once(a, "go"):
		if _ok(gl):
			gl.play_vis_anim("attack")
		_sfx(u.g, "op_gladiia_flesh_2", -5.0, 1.0)
	if t >= VX_PUSH and _once(a, "push"):
		for e in u.in_circle(c, float(a.R)):
			if e.dead or e.boss:
				continue
			var dv: Vector2 = c - e.pos
			if dv.length() > 30.0:
				(gl if _ok(gl) else ul).apply_kb(e, dv.normalized() * minf(dv.length() * 1.4, 220.0))
	if t >= VX_A0 - 0.12 and _once(a, "ul"):
		if _ok(ul):
			ul.play_vis_anim("attack")
	var hit: Dictionary = a.get("hitset", {})
	for i in a.tips.size():
		if t >= VX_A0 + VX_DA * float(i) and _once(a, "a%d" % i):
			var tp: Vector2 = a.tips[i]
			_sfx(u.g, "op_ulpianus_flesh_2", -6.0, 0.9 + 0.05 * float(i))
			for e in u.in_circle(tp, float(a.ar)):
				var eid: int = int(e.get("id", -1))
				if hit.has(eid):
					continue
				hit[eid] = true
				_hit(u, ul if _ok(ul) else gl, e, Bal.v("bond2/vx_frac", 1.2), "涡心落锚", a)
			BPF.vortex_anchor(u, a, tp, i)
	a["hitset"] = hit
	return t >= 2.2


## 双鳍「双鳍破浪」· 合击（docs/296 第八轮「背鳍」）：两人原地出手，两片巨大背鳍（斯卡蒂深海蓝、幽灵鲨幽灵青）从圈两端冒出，
## 绕最密处交错游一圈（0.15–0.8 秒，半径 R，拖白色破浪；每过半圈把圈里的怪往里卷一次），最后在圈心交错扎进水里（0.85 秒，圈里打一下）
const FN_T0 := 0.3
const FN_T1 := 1.55
const FN_HIT := 1.7
static func _fins(u, a: Dictionary, t: float) -> bool:
	var sk = a.who.skadi
	var sp = a.who.specter_unchained
	var c: Vector2 = a.c
	if _once(a, "go"):
		if _ok(sk):
			sk.play_vis_anim("attack")
		if _ok(sp):
			sp.play_vis_anim("attack")
		_sfx(u.g, "op_skadi_flesh_2", -6.0, 0.8)
	for q in 2:
		if t >= FN_T0 + (FN_T1 - FN_T0) * (0.5 * float(q) + 0.35) and _once(a, "pull%d" % q):
			for e in u.in_circle(c, float(a.R) * 1.15):
				if e.dead or e.boss:
					continue
				var dv: Vector2 = c - e.pos
				if dv.length() > 40.0:
					(sk if _ok(sk) else sp).apply_kb(e, (dv.normalized() + dv.normalized().orthogonal() * 0.6).normalized() * 150.0)
	if t >= FN_HIT and _once(a, "dive"):
		_sfx(u.g, "ult_texas_impact", -5.0, 0.7)
		for e in u.in_circle(c, float(a.R)):
			_hit(u, sk if (_ok(sk) and e.pos.x < c.x) or not _ok(sp) else sp, e, Bal.v("bond2/fn_frac", 1.2), "双鳍破浪", a)
		BPF.fins_dive(u, a)
	return t >= 2.2


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
