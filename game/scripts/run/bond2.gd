## 羁绊技 v2（docs/294，开关 balance link/bond_v2，缺省 0 = 完全不求值，回到 docs/217 的羁绊合击 + 常驻小加成）。
## HoloCure 式联动招式：两名有原作关系的干员同队、且两人都已精一 → 解锁这对人的羁绊技（演出卡），之后按冷却自动释放，
## 每次落下一个大图形覆盖一片（大 X / 一条航线 / 一圈光）。取代这对人原来的 60 秒羁绊合击（link_bond.pick 跳过）和常驻小加成（link_bond.refresh 跳过）。
## 本期只做 3 对（宿敌 / 企鹅物流 / 灯下审决，用户 11-06 批准先做特效）；其余 5 对开关开着时仍走旧羁绊。
## 玩法：不抽随机数、不位移干员（只播出手动作）；伤害按目标生命预算（同 skill_link._dmg 口径，bond2/* 旋钮）。画面全在 render/fx_bond2.gd（只画，用 g.vrng）。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")

## 3 对：成员、标签、招式名、一句话（docs/294 §4，玩家可见文字按 docs/76）
const MOVES := {
	"b_rival": {"ops": ["texas", "lappland"], "tag": "宿敌", "name": "十字旧怨", "desc": "两人对砍，刀锋相撞的余波向四周散开；拉普兰德一侧附带沉默"},
	"b_penguin": {"ops": ["exusiai", "texas"], "tag": "企鹅物流", "name": "急件航线", "desc": "德克萨斯开车冲过怪群，能天使站在车顶朝四周扫射"},
	"b_inq": {"ops": ["lumen", "irene"], "tag": "灯下审决", "name": "提灯宣判", "desc": "流明身后升起灯塔，光锥扫过的敌人由艾丽妮逐个审判"},
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
		c = Vector2(clampf(c.x, lp.x - vw.x, lp.x + vw.x), clampf(c.y, lp.y - vw.y, lp.y + vw.y))
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
		"b_rival":   # 对砍：交锋点 = 最密处；冲击波最大半径
			a["rmax"] = Bal.v("bond2/rival_r", 440.0) * k
		"b_penguin":   # 开车：车是侧面贴图，只走横向（斜率封顶 0.25）；从最密处后方 car_back 处开进画面，穿过最密处再开出去
			var sx: float = 1.0 if d0.x >= 0.0 else -1.0
			var dl: Vector2 = Vector2(sx, clampf(d0.y / maxf(absf(d0.x), 0.001), -0.25, 0.25)).normalized()
			a["s"] = c - dl * Bal.v("bond2/car_back", 450.0) * k
			a["dl"] = dl
			a["len"] = Bal.v("bond2/car_len", 1000.0) * k
			a["hw"] = Bal.v("bond2/car_hw", 56.0) * k
		"b_inq":   # 灯塔：立在流明身后，光锥以朝最密处为中线左右各扫 sweep 弧度
			var lm = who.lumen
			var O: Vector2 = lm.pos - d0 * 90.0 + Vector2(0, -4)
			var dc: Vector2 = (c - O).normalized() if c != O else d0
			var sw: float = Bal.v("bond2/inq_sweep", 0.95)
			a["O"] = O
			a["R"] = Bal.v("bond2/inq_r", 700.0) * k
			a["ang0"] = dc.angle() - sw
			a["ang1"] = dc.angle() + sw
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


## 宿敌「十字旧怨」· 对砍（docs/296 第五轮，用户 11-06 定）：两人残影相向冲上（0–0.45 秒），刀锋相交停一拍（0.45–0.6），
## 冲击波从交锋点向四周散开（0.6–1.1 秒，半径 40 → rmax），冲到哪只打哪只；拉普兰德一侧（交点右半边）附带沉默
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
	if t >= 0.45 and _once(a, "clash"):
		_sfx(u.g, "ult_lappland_impact", -3.0, 1.0)
		_sfx(u.g, "op_texas_s3_cut_1", -4.0, 0.9)
	if t >= 0.6:
		var rmax: float = a.rmax
		var r: float = lerpf(40.0, rmax, clampf((t - 0.6) / 0.5, 0.0, 1.0))
		var hit: Dictionary = a.get("hitset", {})
		var sil: bool = Bal.v("bond2/rival_silence", 1.0) > 0.0
		for e in u.in_circle(c, r):
			var eid: int = int(e.get("id", -1))
			if hit.has(eid):
				continue
			hit[eid] = true
			var right: bool = e.pos.x >= c.x
			_hit(u, (lp if right else tx) if (_ok(lp) and _ok(tx)) else (tx if _ok(tx) else lp), e, 1.2, "十字旧怨", a)
			if right and sil and not e.dead and not e.boss:
				u.g.enemies_sys.silence(e, u.g.t + (0.5 if e.elite else 1.0))
		a["hitset"] = hit
	return t >= 1.4


## 企鹅物流「急件航线」· 开车（docs/296 第五轮）：德克萨斯开车从小队旁冲过怪群（0.15–1.25 秒），车身碾过的带状区域打一下；
## 能天使站在车顶，每 0.08 秒朝车周围 260 内最近的 3 只各开一枪（不抽随机数，按 g.enemies 顺序取最近）
static func _penguin(u, a: Dictionary, t: float) -> bool:
	var ex = a.who.exusiai
	var tx = a.who.texas
	var s0: Vector2 = a.s
	var dl: Vector2 = a.dl
	var ln: float = a.len
	var T0 := 0.15
	var T1 := 1.25
	var driver = tx if _ok(tx) else ex
	var shooter = ex if _ok(ex) else tx
	if _once(a, "go"):
		_sfx(u.g, "op_exusiai_s3", -6.0, 1.0)
	if t < T0:
		return false
	var uu: float = clampf((t - T0) / (T1 - T0), 0.0, 1.0)
	var p: Vector2 = s0 + dl * ln * uu
	var p0: Vector2 = a.get("cp", s0)
	a["cp"] = p
	var hit: Dictionary = a.get("hitset", {})
	for e in u.in_band(p0, p, float(a.hw)):
		var eid: int = int(e.get("id", -1))
		if hit.has(eid):
			continue
		hit[eid] = true
		_hit(u, driver, e, 1.0, "急件航线", a)
		if not e.dead and not e.boss:
			driver.apply_kb(e, dl.orthogonal() * (140.0 if (e.pos - p).dot(dl.orthogonal()) >= 0.0 else -140.0))
	a["hitset"] = hit
	var nshot: int = int((minf(t, T1) - T0) / 0.08)
	while int(a.done.get("shots", 0)) < nshot:
		a.done["shots"] = int(a.done.get("shots", 0)) + 1
		var near: Array = u.in_circle(p, 260.0)
		near.sort_custom(func(x, y): return x.pos.distance_squared_to(p) < y.pos.distance_squared_to(p))
		var tg: Array = near.slice(0, 3)
		for e in tg:
			_hit(u, shooter, e, 0.5, "急件航线", a)
		var fx = _fx(u.g)
		if fx != null:
			fx.shots(a, p, tg.map(func(e): return e.pos))
		if int(a.done.shots) % 3 == 0:
			_sfx(u.g, "op_exusiai_atk", -10.0, 1.0)
	if t >= T1 and _once(a, "end"):
		_sfx(u.g, "ult_texas_impact", -8.0, 1.2)
	return t >= 1.6


## 灯下审决「提灯宣判」· 灯塔照海、审判守岸（docs/296 第七轮，用户给参考图）：流明身后升起灯塔虚像（0–0.4 秒），
## 光锥从 ang0 扫到 ang1（0.4–1.15 秒，半径 R），扫到的敌人亮紫印、0.15 秒后受审（艾丽妮出手）
static func _inq(u, a: Dictionary, t: float) -> bool:
	var lm = a.who.lumen
	var ir = a.who.irene
	var O: Vector2 = a.O
	var R: float = a.R
	if _once(a, "go"):
		if _ok(lm):
			lm.play_vis_anim("skill")
		_sfx(u.g, "op_lumen_s2", -5.0, 0.9)
	if t >= 0.4 and t < 1.2:
		var k: float = clampf((t - 0.4) / 0.75, 0.0, 1.0)
		var ang: float = lerpf(float(a.ang0), float(a.ang1), k)
		var pa: float = float(a.get("pang", a.ang0))
		a["pang"] = ang
		var marks: Array = a.get("marks", [])
		var seen: Dictionary = a.get("seen", {})
		for e in u.in_circle(O, R):
			var eid: int = int(e.get("id", -1))
			if seen.has(eid):
				continue
			var ea: float = (e.pos - O).angle()
			var rel: float = wrapf(ea - float(a.ang0), -PI, PI)
			var lo: float = wrapf(pa - float(a.ang0), -PI, PI)
			var hi: float = wrapf(ang - float(a.ang0), -PI, PI)
			if rel >= minf(lo, hi) - 0.02 and rel <= maxf(lo, hi) + 0.02:
				seen[eid] = true
				marks.append([e, t + 0.15])
		a["seen"] = seen
		a["marks"] = marks
		if int(t * 15) % 3 == 0 and _ok(ir) and _once(a, "ia%d" % int(t * 5)):
			ir.play_vis_anim("attack")
	var keep: Array = []
	for m in a.get("marks", []):
		if t >= float(m[1]):
			_hit(u, ir if _ok(ir) else lm, m[0], 1.2, "提灯宣判", a)
			if _once(a, "js%d" % int(t * 10)):
				_sfx(u.g, "op_irene_atk", -7.0, 1.0)
		else:
			keep.append(m)
	a["marks"] = keep
	if t >= 1.2 and _once(a, "end"):
		_sfx(u.g, "op_irene_big", -5.0, 1.0)
	return t >= 1.6 and keep.is_empty()


## 作战记录 / 测试用：本局解锁与释放
static func summary(u) -> Dictionary:
	if not on() or not u.has_meta("bond2"):
		return {}
	var s: Dictionary = st(u)
	return {"unlocked": s.unlocked.duplicate(), "e2": s.e2.duplicate(), "log": s.log.duplicate()}
