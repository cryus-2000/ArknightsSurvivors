## 羁绊技 v2（docs/294，开关 balance link/bond_v2，缺省 0 = 完全不求值，回到 docs/217 的羁绊合击 + 常驻小加成）。
## HoloCure 式联动招式：两名有原作关系的干员同队、且两人都已精一 → 解锁这对人的羁绊技（演出卡），之后按冷却自动释放，
## 每次落下一个大图形覆盖一片（大 X / 一条航线 / 一圈光）。取代这对人原来的 60 秒羁绊合击（link_bond.pick 跳过）和常驻小加成（link_bond.refresh 跳过）。
## 本期只做 3 对（宿敌 / 企鹅物流 / 灯下审决，用户 11-06 批准先做特效）；其余 5 对开关开着时仍走旧羁绊。
## 玩法：不抽随机数、不位移干员（只播出手动作）；伤害按目标生命预算（同 skill_link._dmg 口径，bond2/* 旋钮）。画面全在 render/fx_bond2.gd（只画，用 g.vrng）。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const BPF = preload("res://scripts/run/bond2_pf.gd")

## 3 对：成员、标签、招式名、一句话（docs/294 §4，玩家可见文字按 docs/76）
const MOVES := {
	"b_rival": {"ops": ["texas", "lappland"], "tag": "宿敌", "name": "十字旧怨", "desc": "两人同时挥剑，两道剑气在怪群中心相撞炸开；拉普兰德一侧附带沉默"},
	"b_penguin": {"ops": ["exusiai", "texas"], "tag": "企鹅物流", "name": "急件航线", "desc": "能天使朝怪群齐射，德克萨斯开车从怪群里碾过去"},
	"b_inq": {"ops": ["lumen", "irene"], "tag": "灯下审决", "name": "提灯宣判", "desc": "流明身后的灯塔照亮怪群，艾丽妮的审判光矛随即落下"},
}
const ORDER := ["b_rival", "b_penguin", "b_inq"]
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
		var e1: bool = int(pr[0].elite) >= 1 and int(pr[1].elite) >= 1
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
		if not s.e2.has(bid) and int(pr[0].elite) >= 2 and int(pr[1].elite) >= 2:
			s.e2[bid] = g.t
			s.log.append({"id": bid, "ev": "e2", "t": snappedf(g.t, 0.1)})
			var fx2 = _fx(g)
			if fx2 != null:
				fx2.card(bid, pr, true)
		if g.t < float(s.next.get(bid, INF)):
			continue
		if u.phase != "" or not s.acts.is_empty() or g.t - float(s.last_any) < Bal.v("bond2/gap", 6.0):
			continue
		if pr[0].cmd_down > 0.0 or pr[1].cmd_down > 0.0:
			continue
		var ld = g.squad.leader()
		var cpos: Vector2 = (pr[0].pos + pr[1].pos) * 0.5
		if u.in_view(ld.pos if ld != null and ld.pos != Vector2.INF else cpos).size() < Bal.vi("bond2/min_foes", 6):
			continue
		var lp: Vector2 = ld.pos if ld != null and ld.pos != Vector2.INF else cpos   # 镜头跟队长：释放点挑队长附近、限在屏内（11-06 录像：挑到屏外只看到一根线）
		var c: Vector2 = u._densest(lp, Bal.v("bond2/reach", 380.0), 160.0)
		if c == Vector2.INF:
			continue
		var vw: Vector2 = Vector2(1524.0, 857.0) * Bal.v("bond2/view_k", 0.28)
		c = Vector2(clampf(c.x, lp.x - vw.x, lp.x + vw.x), clampf(c.y, lp.y - minf(vw.y, Bal.v("bond2/c_dy", 170.0)), lp.y + minf(vw.y, Bal.v("bond2/c_dy", 170.0))))   # 11-07：落点贴屏幕顶边会被演出卡 / HUD 盖住，上下限 c_dy
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
	var who := {str(ids[0]): pr[0], str(ids[1]): pr[1]}
	var from: Vector2 = (pr[0].pos + pr[1].pos) * 0.5
	var d0: Vector2 = (c - from).normalized() if c != from else Vector2.RIGHT
	var k: float = Bal.v("bond2/size_e2", 1.3) if e2 else Bal.v("bond2/size", 1.0)
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
			a["dl"] = Vector2(sx, clampf(d0.y / maxf(absf(d0.x), 0.001), -0.12, 0.12)).normalized()
			var ld = g.squad.leader()
			var ly: float = ld.pos.y if ld != null and ld.pos != Vector2.INF else from.y
			a["c"] = Vector2(c.x, clampf(c.y, ly - Bal.v("bond2/car_up", 40.0), ly + Bal.v("bond2/car_dn", 140.0)))   # 车身往上占 140：车道贴队长上方会被演出卡 / HUD 盖住
			a["run"] = Bal.v("bond2/car_run", 560.0)
			a["out"] = Bal.v("bond2/car_out", 340.0) * k
			a["hw"] = Bal.v("bond2/car_hw", 58.0) * k
		"b_inq":   # 合击：灯塔立在流明身后，聚光落在最密处，光圈半径 r
			var lm = who.lumen
			a["O"] = lm.pos + Vector2(-signf(d0.x if d0.x != 0.0 else 1.0) * 96.0, -36.0)   # 立在流明侧后方（y 更小 = 排在他和小队后面，不挡人）
			a["r"] = Bal.v("bond2/inq_r", 240.0) * k
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
	return true


## 宿敌「十字旧怨」· 十字斩（11-07 用户：改成斩击，选「十字斩裂地」）：两人原地出手（0 秒），落点先闪一下 X 形预兆细线，
## 德克萨斯一刀（左上 → 右下，0.24 秒）、拉普兰德一刀（右上 → 左下，0.32 秒）在最密处交成大 X，斩痕带上的各打一下；
## 拉普兰德那一刀附带沉默；交点 0.34 秒炸开（只画）
const RV_T1 := 0.24
const RV_T2 := 0.32
const RV_HIT := 0.34
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
	return t >= 1.0


## 企鹅物流「急件航线」· 碾过去（11-07 用户：「一辆车直接碾过去」，不裂地）：能天使原地朝最密处齐射（0–0.6 秒，每 0.09 秒最近 3 只各一枪）；
## 德克萨斯的车（不画人）从画面外横向冲进来、穿过最密处再开出去（0.10–0.75 秒），车身扫过的带状区域打一下、往两侧撞开；车后一路扬尘
const PG_T0 := 0.10
const PG_T1 := 0.75
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
	var nshot: int = int(minf(t, 0.6) / 0.09)
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
		var k: float = clampf((t - PG_T0) / (PG_T1 - PG_T0), 0.0, 1.0)
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
		var nd: int = int(k * 8.0)
		while int(a.done.get("dust", 0)) < nd:
			a.done["dust"] = int(a.done.get("dust", 0)) + 1
			BPF.penguin_trail(u, a, p, int(a.done.dust))
	return t >= 1.0


## 灯下审决「提灯宣判」· 合击：流明原地举灯，身后升起灯塔（0–0.35 秒），灯室点亮后一束聚光斜落到最密处（0.35–0.55 秒），
## 光圈里的敌人亮紫印；艾丽妮原地出手（0.55），一道审判光矛从高处落进光圈中心（0.78）：光圈里的一齐受审
const IQ_HIT := 0.78
static func _inq(u, a: Dictionary, t: float) -> bool:
	var lm = a.who.lumen
	var ir = a.who.irene
	var c: Vector2 = a.c
	if _once(a, "go"):
		if _ok(lm):
			lm.play_vis_anim("skill")
		_sfx(u.g, "op_lumen_s2", -5.0, 0.9)
	if t >= 0.55 and _once(a, "ir"):
		if _ok(ir):
			ir.play_vis_anim("attack")
		_sfx(u.g, "op_irene_atk", -6.0, 0.9)
	if t >= IQ_HIT and _once(a, "judge"):
		_sfx(u.g, "op_irene_big", -4.0, 1.0)
		for e in u.in_circle(c, float(a.r)):
			_hit(u, ir if _ok(ir) else lm, e, Bal.v("bond2/inq_frac", 1.2), "提灯宣判", a)
		BPF.inq_hit(u, a)
	return t >= 1.4


## 作战记录 / 测试用：本局解锁与释放
static func summary(u) -> Dictionary:
	if not on() or not u.has_meta("bond2"):
		return {}
	var s: Dictionary = st(u)
	return {"unlocked": s.unlocked.duplicate(), "e2": s.e2.duplicate(), "log": s.log.duplicate()}
