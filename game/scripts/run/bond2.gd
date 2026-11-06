## 羁绊技 v2（docs/294，开关 balance link/bond_v2，缺省 0 = 完全不求值，回到 docs/217 的羁绊合击 + 常驻小加成）。
## HoloCure 式联动招式：两名有原作关系的干员同队、且两人都已精一 → 解锁这对人的羁绊技（演出卡），之后按冷却自动释放，
## 每次落下一个大图形覆盖一片（大 X / 一条航线 / 一圈光）。取代这对人原来的 60 秒羁绊合击（link_bond.pick 跳过）和常驻小加成（link_bond.refresh 跳过）。
## 本期只做 3 对（宿敌 / 企鹅物流 / 灯下审决，用户 11-06 批准先做特效）；其余 5 对开关开着时仍走旧羁绊。
## 玩法：不抽随机数、不位移干员（只播出手动作）；伤害按目标生命预算（同 skill_link._dmg 口径，bond2/* 旋钮）。画面全在 render/fx_bond2.gd（只画，用 g.vrng）。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")

## 3 对：成员、标签、招式名、一句话（docs/294 §4，玩家可见文字按 docs/76）
const MOVES := {
	"b_rival": {"ops": ["texas", "lappland"], "tag": "宿敌", "name": "十字旧怨", "desc": "两道剑刃交成十字，交点炸开；拉普兰德那一道附带沉默"},
	"b_penguin": {"ops": ["exusiai", "texas"], "tag": "企鹅物流", "name": "急件航线", "desc": "能天使扫出一条航线，德克萨斯的剑沿航线依次落下"},
	"b_inq": {"ops": ["lumen", "irene"], "tag": "灯下审决", "name": "提灯宣判", "desc": "流明提灯照出一圈光，艾丽妮三刺穿过，光里的敌人一齐受审"},
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
		var c: Vector2 = u._densest(cpos, Bal.v("bond2/reach", 560.0), 160.0)
		if c == Vector2.INF:
			continue
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
		"b_rival":
			var L: float = 420.0 * k
			a["L"] = L
			a["d1"] = d0.rotated(0.52)
			a["d2"] = d0.rotated(-0.52)
		"b_penguin":
			var ex = who.exusiai
			var dl: Vector2 = (c - ex.pos).normalized() if c != ex.pos else d0
			a["s"] = ex.pos + dl * 70.0
			a["dl"] = dl
			a["len"] = 760.0 * k
			a["hw"] = 90.0 * k
		"b_inq":
			a["r"] = 230.0 * k
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


## 宿敌「十字旧怨」：0.25 秒德克萨斯一道（琥珀），0.47 秒拉普兰德一道（附沉默），两道在最密处交成 X；0.78 秒交点炸开
static func _rival(u, a: Dictionary, t: float) -> bool:
	var tx = a.who.texas
	var lp = a.who.lappland
	var c: Vector2 = a.c
	var L: float = a.L
	var hw: float = 40.0 * float(a.k)
	if _once(a, "go"):
		if _ok(tx):
			tx.play_vis_anim("attack")
		if _ok(lp):
			lp.play_vis_anim("attack")
		_sfx(u.g, "op_texas_s3", -6.0, 1.05)
	if t >= 0.25 and _once(a, "l1"):
		var d: Vector2 = a.d1
		for e in u.in_band(c - d * L, c + d * L, hw):
			_hit(u, tx if _ok(tx) else lp, e, 1.0, "十字旧怨", a)
		_sfx(u.g, "op_texas_s3_cut_1", -3.0, 1.0)
	if t >= 0.47 and _once(a, "l2"):
		var d2: Vector2 = a.d2
		var sil: bool = Bal.v("bond2/rival_silence", 1.0) > 0.0
		for e in u.in_band(c - d2 * L, c + d2 * L, hw):
			_hit(u, lp if _ok(lp) else tx, e, 1.0, "十字旧怨", a)
			if sil and not e.dead and not e.boss:
				u.g.enemies_sys.silence(e, u.g.t + (0.5 if e.elite else 1.0))
		_sfx(u.g, "ult_lappland_slash_2", -3.0, 1.0)
	if t >= 0.78 and _once(a, "x"):
		var who = tx if _ok(tx) else lp
		for e in u.in_circle(c, 160.0 * float(a.k)):
			_hit(u, who, e, 0.6, "十字旧怨", a)
		_sfx(u.g, "ult_lappland_impact", -4.0, 1.0)
		if a.e2:   # 精二：交点再补一道竖斩（成「米」字）
			a["l3"] = true
	if a.get("l3", false) and t >= 0.95 and _once(a, "l3hit"):
		var d3: Vector2 = Vector2(a.d0).orthogonal()
		for e in u.in_band(c - d3 * L * 0.8, c + d3 * L * 0.8, hw):
			_hit(u, tx if _ok(tx) else lp, e, 0.8, "十字旧怨", a)
		_sfx(u.g, "op_texas_s3_cut_2", -4.0, 1.0)
	return t >= 1.6


## 企鹅物流「急件航线」：航线 = 能天使 → 最密处方向一条宽带；0.25–1.2 秒一路扫射（沿线由近及远 30 个落点），0.75 秒起 6 把剑沿线依次落下；1.35 秒整条航线收尾结算
static func _penguin(u, a: Dictionary, t: float) -> bool:
	var ex = a.who.exusiai
	var tx = a.who.texas
	var s0: Vector2 = a.s
	var dl: Vector2 = a.dl
	var nl: Vector2 = dl.orthogonal()
	var ln: float = a.len
	var hw: float = a.hw
	var shooter = ex if _ok(ex) else tx
	var sworder = tx if _ok(tx) else ex
	if _once(a, "go"):
		if _ok(ex):
			ex.play_vis_anim("attack")
		_sfx(u.g, "op_exusiai_s3", -5.0, 1.0)
	var nshot: int = 30
	var shots: int = clampi(int((t - 0.25) / 0.032) + 1, 0, nshot) if t >= 0.25 else 0
	while int(a.done.get("k", 0)) < shots:
		var i: int = int(a.done.get("k", 0))
		var u0: float = float(i) / float(nshot - 1)
		var off: float = (fposmod(float(i) * 0.618034, 1.0) * 2.0 - 1.0) * (hw - 16.0)   # 落点按黄金比例错开，不抽随机数
		var p: Vector2 = s0 + dl * (ln * (0.08 + 0.9 * u0)) + nl * off
		for e in u.in_circle(p, 38.0):
			_hit(u, shooter, e, 0.35, "急件航线", a)
		a.done["k"] = i + 1
		if i % 6 == 0:
			_sfx(u.g, "op_exusiai_atk", -9.0, 1.0)
	var nsw: int = 10 if a.e2 else 6
	for j in nsw:
		var ts: float = 0.75 + 0.09 * j * (6.0 / float(nsw))
		if t >= ts + 0.12 and _once(a, "sw%d" % j):
			var big: bool = j == nsw - 1
			var u1: float = (float(j) + 0.5) / float(nsw)
			var p2: Vector2 = s0 + dl * (ln * (0.12 + 0.84 * u1)) + nl * (18.0 if j % 2 == 0 else -18.0)
			for e in u.in_circle(p2, (130.0 if big else 100.0) * float(a.k)):
				_hit(u, sworder, e, 1.0 if big else 0.8, "急件航线", a)
			if j % 2 == 0 or big:
				_sfx(u.g, "op_texas_s3_cut_%d" % (1 + j % 3), -6.0, 1.0)
	if t >= 1.35 and _once(a, "sweep"):
		for e in u.in_band(s0, s0 + dl * ln, hw):
			_hit(u, sworder, e, 0.5, "急件航线", a)
		_sfx(u.g, "ult_texas_impact", -6.0, 1.1)
	return t >= 1.9


## 灯下审决「提灯宣判」：0.05 秒流明提灯张开光圈（0.3 秒张满）；0.55 / 0.72 / 0.89 秒艾丽妮三刺穿过光圈（精二四刺）；1.25 秒光里剩下的一齐受审
static func _inq(u, a: Dictionary, t: float) -> bool:
	var lm = a.who.lumen
	var ir = a.who.irene
	var c: Vector2 = a.c
	var R: float = a.r
	if _once(a, "go"):
		if _ok(lm):
			lm.play_vis_anim("skill")
		_sfx(u.g, "op_lumen_s2", -5.0, 1.0)
	var angs: Array = [-0.21, 0.84, 1.88, 2.9] if a.e2 else [-0.21, 0.84, 1.88]
	for i in angs.size():
		var tt: float = 0.55 + 0.17 * i
		if t >= tt and _once(a, "th%d" % i):
			var d := Vector2.from_angle(float(angs[i]))
			var p0: Vector2 = c - d * (R + 40.0)
			var p1: Vector2 = c + d * (R + 40.0)
			if _ok(ir):
				ir.play_vis_anim("attack")
			for e in u.in_band(p0, p1, 30.0 * float(a.k)):
				_hit(u, ir if _ok(ir) else lm, e, 1.0, "提灯宣判", a)
			_sfx(u.g, "op_irene_atk", -4.0, 1.0 + 0.05 * i)
	var tv: float = 0.55 + 0.17 * angs.size() + 0.2
	if t >= tv and _once(a, "judge"):
		var who = ir if _ok(ir) else lm
		var es: Array = u.in_circle(c, R)
		a["judged"] = es.slice(0, 40)
		for e in es:
			_hit(u, who, e, 1.0, "提灯宣判", a)
		_sfx(u.g, "op_irene_big", -4.0, 1.0)
		var fx = _fx(u.g)
		if fx != null:
			fx.judge(a, es.slice(0, 40))
	return t >= tv + 0.6


## 作战记录 / 测试用：本局解锁与释放
static func summary(u) -> Dictionary:
	if not on() or not u.has_meta("bond2"):
		return {}
	var s: Dictionary = st(u)
	return {"unlocked": s.unlocked.duplicate(), "e2": s.e2.duplicate(), "log": s.log.duplicate()}
