## 终结技形态（docs/198 §4.1–4.5，第一批 5 人）+ 连携终结技通用版（§7.3）。框架在 run/ult.gd（u），本文件只写各人怎么出招。
## 约定：start 返回动作状态字典，step 每帧推进、返回 true = 结束；伤害一律走 u.hit（按目标生命定的预算，frac = 这段占预算的比例）；
## 画面一律走 u.shape（程序占位：圆 / 环 / 扇形 / 长方形带 / 线 / 点），不用美术素材。
## 每段命中各记一张已命中表（e.id），同一敌人同一段只打一次；外缘 15% 宽的衰减带传 edge（§3.3）。不抽随机数，散布按序号算。
## 其余 15 人暂无专属终结技：以自身为中心半径 460 的冲击环（0.3 秒扩满，100% 预算）。
## 连携终结技：start_cult 按 ult/cult_style 分派（0 = 通用版：队长终结技形态 + 队友冲到敌群打放大冲击，同时落地时屏内敌人一次补满预算）。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")

const POINT_OPS := ["texas", "kaltsit", "ulpianus"]
const AUTO_OPS := ["exusiai", "skalter"]
const COL_SK_RED := Color(0.78, 0.06, 0.14)
const COL_SK_TEAL := Color(0.25, 0.95, 0.82)
const COL_STEEL := Color(0.72, 0.8, 0.9)


static func aim_kind(id: String) -> String:
	return "point" if id in POINT_OPS else "none"


## 瞄准指示的半径（选落点：落点圆；不瞄：以自身为中心的圈）
static func aim_r(id: String) -> float:
	match id:
		"exusiai", "skalter":
			return 480.0
		"ulpianus":
			return 440.0
	return 460.0


static func start(u, o, aim: Vector2, dir: Vector2) -> Dictionary:
	_m3_watch(u)
	if o == null or o.pos == Vector2.INF:
		return {}
	var a: Dictionary
	match str(o.id):
		"texas":
			a = _tx_start(u, o, aim, dir)
		"exusiai":
			a = _ex_start(u, o)
		"skalter":
			a = _sk_start(u, o, dir)
		"kaltsit":
			a = _ka_start(u, o, aim)
		"ulpianus":
			a = _ul_start(u, o, aim)
		_:
			a = _gen_start(u, o)
	a["o"] = o
	a["t"] = 0.0
	return a


static func step(u, a: Dictionary, dt: float) -> bool:
	if a.is_empty():
		return true
	var o = a.o
	if o == null or o.pos == Vector2.INF:
		_abort(u, a)
		return true
	a.t = float(a.t) + dt
	match str(a.k):
		"texas":
			return _tx_step(u, a, o)
		"exusiai":
			return _ex_step(u, a, o)
		"skalter":
			return _sk_step(u, a, o, dt)
		"kaltsit":
			return _ka_step(u, a, o)
		"ulpianus":
			return _ul_step(u, a, o)
	return _gen_step(u, a, o)


static func start_cult(u, o, aim: Vector2, dir: Vector2) -> Dictionary:
	match int(Bal.v("ult/cult_style", 0)):
		_:
			return _cult_generic_start(u, o, aim, dir)


static func step_cult(u, a: Dictionary, dt: float) -> bool:
	if a.is_empty():
		return true
	match str(a.get("style", "generic")):
		_:
			return _cult_generic_step(u, a, dt)


# ================================================================ 公用

## 一段伤害：带 cap 的动作（连携终结技）每名敌人合计不超过 cap（份预算）
static func _hit(u, a: Dictionary, o, e: Dictionary, frac: float, opt: Dictionary = {}) -> float:
	if a.has("cap"):
		var k: int = int(e.id)
		var done: float = float(a.fr.get(k, 0.0))
		frac = minf(frac, float(a.cap) - done)
		if frac <= 0.0001:
			return 0.0
		a.fr[k] = done + frac
	return u.hit(o, e, frac, opt)


## 圆形区：一次性打这一段（seg = 已命中表），外缘 15% 宽算衰减带
static func _hit_circle(u, a: Dictionary, o, c: Vector2, r: float, frac: float, seg: Dictionary, opt: Dictionary = {}, edge_r := -1.0) -> int:
	var n := 0
	var er: float = (edge_r if edge_r > 0.0 else r) * (1.0 - _edge_w())
	for e in u.in_circle(c, r):
		if seg.has(int(e.id)):
			continue
		seg[int(e.id)] = true
		var op: Dictionary = opt.duplicate()
		op["edge"] = e.pos.distance_to(c) > er
		_hit(u, a, o, e, frac, op)
		n += 1
	return n


static func _edge_w() -> float:
	return Bal.v("ult/edge_w", 0.15)


static func _route(o) -> String:
	var r = o.get("route")
	return str(r) if r != null else ""


## 击退距离 → 冲量（敌人 kb 每秒衰减 900）
static func _kb_v(dist: float) -> float:
	return sqrt(1800.0 * maxf(0.0, dist))


static func _ring(u, c: Vector2, r: float, r1: float, col: Color, life: float, w := 6.0, delay := 0.0) -> void:
	u.shape({"kind": "ring", "c": c, "r": r, "r1": r1, "w": w, "col": col, "life": life, "delay": delay})


static func _abort(u, a: Dictionary) -> void:
	if str(a.get("k", "")) == "kaltsit":
		_m3_back(u, a.o, false)


# ================================================================ 通用占位（无专属终结技）

static func _gen_start(u, o) -> Dictionary:
	var c: Vector2 = o.pos
	var col: Color = u._col(o)
	_ring(u, c, 460.0, 40.0, col.lerp(Color.WHITE, 0.3), 0.6, 10.0)
	u.shape({"kind": "circle", "c": c, "r": 460.0, "col": col, "fill": 0.18, "life": 0.5})
	u.shape({"kind": "dots", "c": c, "r": 440.0, "n": 28, "col": col.lerp(Color.WHITE, 0.5), "life": 0.6})
	o.screen_shake(0.5)
	return {"k": "gen", "c": c, "seg": {}}


static func _gen_step(u, a: Dictionary, o) -> bool:
	var T := 0.3
	var r: float = lerpf(40.0, 460.0, clampf(float(a.t) / T, 0.0, 1.0))
	_hit_circle(u, a, o, a.c, r, 1.0, a.seg, {"src": "冲击"}, 460.0)
	return float(a.t) >= T


# ================================================================ 德克萨斯（§4.1）：落点圆内连闪刀痕 → 同时斩开 → 沿刀痕剑雨

static func _tx_start(u, o, aim: Vector2, dir: Vector2) -> Dictionary:
	var rt := _route(o)
	var R: float = 430.0 if rt == "back" else 460.0
	var c: Vector2 = aim if aim != Vector2.INF else o.pos
	var n: int = 5 + int(u.serial) % 3
	var base: float = dir.angle() + 0.35
	var lines: Array = []
	for i in n:
		var ang: float = base + PI * float(i) / float(n) + 0.12 * float((i * 5) % 3 - 1)
		var d: Vector2 = Vector2.from_angle(ang)
		var off: float = (float((i * 37) % 9) - 4.0) / 4.0 * R * 0.4
		var ln: float = 700.0 + float((i * 53) % 5) * 50.0
		var mid: Vector2 = c + d.orthogonal() * off
		lines.append([mid - d * ln * 0.5, mid + d * ln * 0.5])
	# 剑雨落点：沿刀痕每 40 一把，只落在落点圆内；按序号交错，各刀痕同时往外铺
	var per: Array = []
	var most := 0
	for ln in lines:
		var pts: Array = []
		var L: float = ln[0].distance_to(ln[1])
		var k := 0
		while k * 40.0 <= L:
			var p: Vector2 = ln[0].lerp(ln[1], k * 40.0 / L)
			if p.distance_to(c) <= R:
				pts.append(p)
			k += 1
		per.append(pts)
		most = maxi(most, pts.size())
	var swords: Array = []
	for j in most:
		for pts in per:
			if j < pts.size():
				swords.append(pts[j])
	for e in u.in_circle(c, R):
		if not e.boss:
			u.g.enemies_sys.add_cc(e, Bal.v("ult/tx_hold", 0.6))   # 定住，暂不受伤
	var col: Color = u._col(o)
	u.shape({"kind": "ring", "c": c, "r": R, "w": 3.0, "col": col.lerp(Color.WHITE, 0.4), "life": 1.7})
	u.shape({"kind": "circle", "c": c, "r": R, "col": col, "fill": 0.08, "life": 1.7})
	var rounds: Array = [[0.75, 0.3]]
	if rt == "rain2":
		rounds = [[0.75, 0.15], [1.05, 0.15]]
	return {"k": "texas", "c": c, "R": R, "lines": lines, "drawn": 0, "cut": false, "cut_seg": {}, "swords": swords,
		"rounds": rounds, "rain": [], "back": rt == "back", "back_done": false, "end": 0.0}


static func _tx_step(u, a: Dictionary, o) -> bool:
	var t: float = a.t
	var col: Color = u._col(o)
	var hi: Color = col.lerp(Color.WHITE, 0.6)
	var lines: Array = a.lines
	var n: int = lines.size()
	while int(a.drawn) < n and t >= float(a.drawn) * 0.5 / float(n):
		var ln: Array = lines[int(a.drawn)]
		u.shape({"kind": "line", "a": ln[0], "b": ln[1], "w": 3.0, "col": hi, "life": 0.85 - t})
		u.shape({"kind": "dots", "c": (ln[0] + ln[1]) * 0.5, "r": 60.0, "n": 6, "col": hi, "life": 0.3})
		a.drawn = int(a.drawn) + 1
	if not a.cut and t >= 0.75:
		a.cut = true
		for ln in lines:
			u.shape({"kind": "band", "a": ln[0], "b": ln[1], "w": 46.0, "col": hi, "fill": 0.55, "life": 0.3})
			u.shape({"kind": "line", "a": ln[0], "b": ln[1], "w": 9.0, "col": Color.WHITE, "life": 0.22})
		_ring(u, a.c, a.R, a.R * 0.3, hi, 0.4, 10.0)
		_hit_circle(u, a, o, a.c, a.R, Bal.v("ult/tx_cut", 0.7), a.cut_seg, {"src": "斩开"})
		o.screen_shake(0.6)
		o.play_vis_anim("attack")
	var sw: Array = a.swords
	var last := 0.0
	for ri in a.rounds.size():
		var rd: Array = a.rounds[ri]
		var t0: float = rd[0]
		last = maxf(last, t0 + 0.8)
		if t < t0:
			continue
		if a.rain.size() <= ri:
			a.rain.append({"i": 0, "seg": {}})
		var st: Dictionary = a.rain[ri]
		var due: int = mini(sw.size(), int(ceil((t - t0) / 0.8 * float(sw.size()))))
		while int(st.i) < due:
			var p: Vector2 = sw[int(st.i)]
			for e in u.in_circle(p, 30.0 + 8.0):
				if st.seg.has(int(e.id)):
					continue
				st.seg[int(e.id)] = true
				_hit(u, a, o, e, float(rd[1]), {"stun": Bal.v("ult/tx_rain_stun", 0.4), "src": "剑雨",
					"edge": e.pos.distance_to(a.c) > float(a.R) * (1.0 - _edge_w())})
			if int(st.i) % 2 == 0:
				u.shape({"kind": "line", "a": p + Vector2(6, -70), "b": p, "w": 3.0, "col": hi, "life": 0.16})
			if int(st.i) % 5 == 0:
				_ring(u, p, 30.0, 6.0, col, 0.2, 2.0)
			st.i = int(st.i) + 1
	if a.back and not a.back_done and t >= last:
		a.back_done = true   # 回马剑：收刀时在她身后再斩一圈（斩开打过的不再打）
		_ring(u, o.pos, 220.0, 40.0, hi, 0.35, 8.0)
		u.shape({"kind": "circle", "c": o.pos, "r": 220.0, "col": col, "fill": 0.25, "life": 0.25})
		_hit_circle(u, a, o, o.pos, 220.0, Bal.v("ult/tx_cut", 0.7), a.cut_seg, {"src": "回马剑"})
	if t >= last + 0.05:
		_tx_sp(u, o)
		return true
	return false


## 放完：队友技力 +2 秒（各技能按自然充能的秒数加，已满 / 常驻的不动）
static func _tx_sp(u, o) -> void:
	var add: float = Bal.v("ult/tx_sp", 2.0)
	for m in u.g.squad.ops:
		if m == o or m.pos == Vector2.INF or not m.has_method("skill_unlocked"):
			continue
		for i in 3:
			if m.skill_unlocked(i) and m.sp_need(i) > 0.0 and not m.perm[i]:
				m.sp[i] = minf(m.sp_need(i), float(m.sp[i]) + add)


# ================================================================ 能天使（§4.2）：自动锁定半径 480，2.5 秒 24 发 / 秒爆裂弹

static func _ex_start(u, o) -> Dictionary:
	var rt := _route(o)
	var R: float = 480.0 * (1.1 if rt == "range" else 1.0)
	var elites: Array = []
	var normals: Array = []
	for e in u.in_circle(o.pos, R):
		if e.elite or e.boss or e.get("part", false):
			elites.append(e)
		else:
			normals.append(e)
	var c: Vector2 = o.pos
	elites.sort_custom(func(x, y): return x.pos.distance_squared_to(c) < y.pos.distance_squared_to(c))
	normals.sort_custom(func(x, y): return x.pos.distance_squared_to(c) < y.pos.distance_squared_to(c))
	var ne: int = int(Bal.v("ult/ex_elite_shots", 7.0))
	var cap: int = int(Bal.v("ult/ex_cap", 60.0))
	var eq: Array = []
	for e in elites:
		for k in ne:
			if eq.size() < cap - 12:   # 至少留 12 发给普通目标
				eq.append(e)
	var col: Color = u._col(o)
	for e in elites:
		_ring(u, e.pos, float(e.get("r", 14.0)) + 18.0, float(e.get("r", 14.0)) + 30.0, Color(1.0, 0.85, 0.35), 0.9, 3.0)
	_ring(u, c, R, R * 0.6, col.lerp(Color.WHITE, 0.4), 0.5, 4.0)
	return {"k": "exusiai", "R": R, "mult": 0.9 if rt == "range" else 1.0, "rico": rt == "ricochet", "eq": eq, "ne": ne,
		"normals": normals, "done": {}, "fired": 0, "ncap": cap, "dur": Bal.v("ult/ex_dur", 2.5), "rate": Bal.v("ult/ex_rate", 24.0), "ring_t": 0.5}


static func _ex_step(u, a: Dictionary, o) -> bool:
	var t: float = a.t
	var dur: float = a.dur
	var due: int = mini(int(a.ncap), int(t * float(a.rate)) + 1)
	while int(a.fired) < due and t < dur:
		_ex_fire(u, a, o)
		a.fired = int(a.fired) + 1
	if t >= float(a.ring_t) and t < dur:
		a.ring_t = float(a.ring_t) + 0.5
		u.shape({"kind": "ring", "c": o.pos, "r": a.R, "w": 2.0, "col": u._col(o).lerp(Color.WHITE, 0.4), "life": 0.5})
	if t >= dur:
		var ext = o.get("ext")   # 天赋「快速弹匣」：弹匣直接装满（天赋没解锁 / 计数器没建立就跳过）
		if ext is Dictionary and ext.has("cap") and ext.has("cnt") and ext.cap.has("mag"):
			ext.cnt["mag"] = float(ext.cap["mag"])
		return true
	return false


## 能天使的伤害：连携终结技时份额上限在 a.share（_hit 读 cap，这里换名避免和总发数冲突）
static func _ex_hit(u, a: Dictionary, o, e: Dictionary, frac: float, opt: Dictionary) -> void:
	if a.has("share"):
		var k: int = int(e.id)
		var done: float = float(a.fr.get(k, 0.0))
		frac = minf(frac, float(a.share) - done)
		if frac <= 0.0001:
			return
		a.fr[k] = done + frac
	u.hit(o, e, frac, opt)


static func _ex_undone(a: Dictionary) -> Array:
	var out: Array = []
	for e in a.normals:
		if not e.dead and not a.done.has(int(e.id)):
			out.append(e)
	return out


static func _ex_fire(u, a: Dictionary, o) -> void:
	var R: float = a.R
	var er: float = R * (1.0 - _edge_w())
	var gold := Color(1.0, 0.82, 0.35)
	var tg = null
	var frac := 0.0
	while not a.eq.is_empty():
		var e: Dictionary = a.eq.pop_front()
		if not e.dead:
			tg = e
			frac = 1.0 / float(a.ne)
			break
	var und: Array = []
	if tg == null:
		und = _ex_undone(a)
		if und.is_empty():   # 锁定的都打完了：重新锁圈内新进来的
			for e in u.in_circle(o.pos, R):
				if not (e.elite or e.boss or e.get("part", false)) and not a.done.has(int(e.id)):
					a.normals.append(e)
			und = _ex_undone(a)
		if und.is_empty():
			return
		tg = und[0]
		frac = 1.0
	var imp: Vector2 = tg.pos
	var src := {"src": "爆裂弹"}
	src["edge"] = imp.distance_to(o.pos) > er
	_ex_hit(u, a, o, tg, frac * float(a.mult), src)
	if not (tg.elite or tg.boss or tg.get("part", false)):
		a.done[int(tg.id)] = true
	# 爆裂：半径 60 内锁定圈里还没打过的普通目标各吃整份（溅射计入预算）
	var n_sp := 0
	for e in u.in_circle(imp, 60.0):
		if e == tg or e.elite or e.boss or e.get("part", false) or a.done.has(int(e.id)) or e.pos.distance_to(o.pos) > R:
			continue
		a.done[int(e.id)] = true
		_ex_hit(u, a, o, e, float(a.mult), {"src": "爆裂弹", "edge": e.pos.distance_to(o.pos) > er})
		n_sp += 1
	# 目标多于剩余发数：一发打多个框（就近再分几名）
	var left: int = maxi(1, int(a.ncap) - int(a.fired))
	und = _ex_undone(a)
	var k: int = int(ceil(float(und.size()) / float(left)))
	if k > 1:
		und.sort_custom(func(x, y): return x.pos.distance_squared_to(imp) < y.pos.distance_squared_to(imp))
		for j in mini(k - 1, und.size()):
			var e: Dictionary = und[j]
			a.done[int(e.id)] = true
			_ex_hit(u, a, o, e, float(a.mult), {"src": "爆裂弹", "edge": e.pos.distance_to(o.pos) > er})
			u.shape({"kind": "line", "a": imp, "b": e.pos, "w": 2.0, "col": gold, "life": 0.08})
	# 跳弹路线：每 5 发里 2 发（按序号，不抽随机数）弹向圈内另一个还没锁上的敌人
	if a.rico and (int(a.fired) * 2) % 5 < 2:
		var best = null
		var bd := 220.0 * 220.0
		for e in u.in_circle(imp, 220.0):
			if e == tg or a.done.has(int(e.id)) or e.elite or e.boss or e.pos.distance_to(o.pos) > R:
				continue
			var d2: float = e.pos.distance_squared_to(imp)
			if d2 < bd:
				bd = d2
				best = e
		if best != null:
			a.done[int(best.id)] = true
			_ex_hit(u, a, o, best, float(a.mult), {"src": "跳弹"})
			u.shape({"kind": "line", "a": imp, "b": best.pos, "w": 2.0, "col": gold, "life": 0.1})
	var mz: Vector2 = o.pos + Vector2(0, -20)
	u.shape({"kind": "line", "a": mz, "b": imp, "w": 2.0, "col": Color(1.0, 0.95, 0.7), "life": 0.06})
	_ring(u, imp, 60.0, 10.0, gold, 0.18, 3.0 if n_sp == 0 else 5.0)
	if int(a.fired) % 6 == 0:
		o.face_to((imp - o.pos).angle())
		o.play_vis_anim("attack")


# ================================================================ 浊心斯卡蒂（§4.3）：海嗣旋转激光扫一圈 → 半径 480 领域 6 秒

static func _sk_start(u, o, dir: Vector2) -> Dictionary:
	var rt := _route(o)
	var laps := 2 if rt == "echo" else 1
	var lfrac: float = 0.55 if rt == "echo" else (0.75 if rt == "resonance" else Bal.v("ult/sk_laser", 0.85))
	var dd: float = 4.0 if rt == "echo" else (9.0 if rt == "resonance" else Bal.v("ult/sk_dom_t", 6.0))
	var dfrac: float = (1.0 - lfrac) if rt == "resonance" else Bal.v("ult/sk_dom", 0.15)   # 领域合计
	var soff := Vector2(-42.0 * float(u.g.facing), -26.0)
	u.shape({"kind": "circle", "c": o.pos + soff, "r": 26.0, "col": COL_SK_RED, "fill": 0.9, "life": 0.25})
	_ring(u, o.pos + soff, 60.0, 10.0, COL_SK_TEAL, 0.3, 3.0)
	return {"k": "skalter", "soff": soff, "a0": dir.angle(), "laps": laps, "lap": 0, "swept": 0.0, "lfrac": lfrac, "lseg": {},
		"T": Bal.v("ult/sk_sweep", 1.6), "L": 480.0, "dd": dd, "dfrac": dfrac, "dc": Vector2.INF, "dt0": 0.0, "tick": 0, "buf_t": 0.0, "fr2": 0}


static func _sk_step(u, a: Dictionary, o, dt: float) -> bool:
	var g = u.g
	var L: float = a.L
	var T: float = a.T
	var org: Vector2 = o.pos + Vector2(a.soff)
	if int(a.lap) < int(a.laps):
		var sgn: float = 1.0 if int(a.lap) % 2 == 0 else -1.0
		a.swept = minf(TAU, float(a.swept) + TAU * dt / T)
		var cur: float = float(a.a0) + sgn * float(a.swept)
		var er: float = L * (1.0 - Bal.v("ult/sk_edge", 0.3))   # 激光前端 30% 长度算外缘
		for e in u.in_circle(org, L):
			if a.lseg.has(int(e.id)):
				continue
			var d: Vector2 = e.pos - org
			var rel: float = fposmod((d.angle() - float(a.a0)) * sgn, TAU)
			if rel <= float(a.swept) or d.length() < 24.0:
				a.lseg[int(e.id)] = true
				_hit(u, a, o, e, float(a.lfrac), {"src": "激光", "edge": d.length() > er})
		var tip: Vector2 = org + Vector2.from_angle(cur) * L
		u.shape({"kind": "line", "a": org, "b": tip, "w": 18.0, "col": COL_SK_RED, "life": 0.05})
		u.shape({"kind": "line", "a": org, "b": tip, "w": 5.0, "col": COL_SK_TEAL, "life": 0.05})
		u.shape({"kind": "circle", "c": org, "r": 24.0, "col": COL_SK_RED, "fill": 0.9, "life": 0.05})
		a.fr2 = int(a.fr2) + 1
		if int(a.fr2) % 3 == 0:
			u.shape({"kind": "sector", "c": org, "r": L, "a": cur - sgn * 0.15, "half": 0.15, "col": COL_SK_RED, "fill": 0.22, "life": 0.25})
		if float(a.swept) >= TAU:
			a.lap = int(a.lap) + 1
			a.swept = 0.0
			a.lseg = {}
			if int(a.lap) >= int(a.laps):
				a.dc = org
				a.dt0 = float(a.t)
				var dd: float = a.dd
				u.shape({"kind": "circle", "c": org, "r": L, "col": COL_SK_RED, "fill": 0.12, "life": dd})
				u.shape({"kind": "ring", "c": org, "r": L, "w": 3.0, "col": COL_SK_TEAL.lerp(COL_SK_RED, 0.5), "life": dd})
				o.screen_shake(0.4)
		return false
	# 领域：每秒一跳（合计 dfrac），队长在领域内：全队攻击 +20%、每秒回 1.5% 最大生命
	var dc: Vector2 = a.dc
	var el: float = float(a.t) - float(a.dt0)
	var n_ticks: int = int(round(float(a.dd)))
	while int(a.tick) < n_ticks and el >= float(int(a.tick) + 1):
		a.tick = int(a.tick) + 1
		_hit_circle(u, a, o, dc, L, float(a.dfrac) / float(n_ticks), {}, {"src": "领域"})
		_ring(u, dc, L, 60.0, COL_SK_TEAL, 0.5, 4.0)
		u.shape({"kind": "dots", "c": dc, "r": L * 0.95, "n": 24, "col": COL_SK_RED.lerp(Color.WHITE, 0.3), "life": 0.6})
	if g.ppos.distance_to(dc) <= L:
		g.combat.heal(g.max_hp * Bal.v("ult/sk_heal", 0.015) * dt, "终结技", "skalter")
		if float(a.t) >= float(a.buf_t):
			a.buf_t = float(a.t) + 0.5
			u.team_buff("ult:skalter_dom", 0.6, [[&"dmg", "mult", Bal.v("ult/sk_atk", 1.2)]])
	return el >= float(a.dd)


# ================================================================ 凯尔希（§4.4）：Mon3tr 冲到落点 → 熔毁三圈 → 8 秒后重构

static func _ka_m3(o):
	var sm = o.get("sm")
	if sm is Dictionary and sm.has("list"):
		for s in sm.list:
			if str(s.kind) == "mon3tr" and not s.get("gone", false):
				return s
	return null


static func _ka_start(u, o, aim: Vector2) -> Dictionary:
	var rt := _route(o)
	var sc: float = 400.0 / 460.0 if rt == "melt_triple" else 1.0
	var m3 = _ka_m3(o)
	var p0: Vector2 = m3.pos if m3 != null else o.pos
	if m3 != null:
		o.ObSummon._sm_end(o, m3, "leave")   # Mon3tr 冲出去用掉：8 秒内不在场（不执行 on_expire）
		o.set_meta("ult_m3_back", u.g.t + 9.0)   # 兜底：动作被中途清掉时，下次任何人放终结技会补回 Mon3tr
	var c: Vector2 = aim if aim != Vector2.INF else o.pos
	var cd: float = clampf(p0.distance_to(c) / 2000.0, 0.12, 0.35)
	return {"k": "kaltsit", "p0": p0, "c": c, "cd": cd, "rs": [180.0 * sc, 320.0 * sc, 460.0 * sc], "fs": [0.3, 0.35, 0.35],
		"ring": 0, "segs": [{}, {}, {}], "push": {}, "prev": p0, "had": m3 != null, "shell": rt == "s1_shell",
		"rebuild_t": 0.0 if rt == "melt_triple" else Bal.v("ult/ka_gone", 8.0), "melt_t": -1.0, "back": false}


static func _ka_step(u, a: Dictionary, o) -> bool:
	var g = u.g
	var t: float = a.t
	var cd: float = a.cd
	var c: Vector2 = a.c
	var mc := Color(0.35, 0.95, 0.85)
	if t < cd:
		var k: float = t / cd
		var p: Vector2 = Vector2(a.p0).lerp(c, 1.0 - (1.0 - k) * (1.0 - k))
		for e in u.in_band(a.prev, p, 50.0):   # 冲锋路径撞开小怪（不伤害）
			if e.elite or e.boss or a.push.has(int(e.id)):
				continue
			a.push[int(e.id)] = true
			var dv: Vector2 = (p - Vector2(a.prev)).normalized().orthogonal()
			if dv.dot(e.pos - p) < 0.0:
				dv = -dv
			g.enemies_sys.apply_kb(e, dv * _kb_v(90.0))
		u.shape({"kind": "line", "a": a.prev, "b": p, "w": 10.0, "col": mc, "life": 0.18})
		u.shape({"kind": "circle", "c": p, "r": 20.0, "col": mc, "fill": 0.9, "life": 0.05})
		a.prev = p
		return false
	var t1: float = cd + 0.3
	if t < t1:   # 到位：发红发白
		var hot: Color = Color(1.0, 0.3, 0.2).lerp(Color.WHITE, (t - cd) / 0.3)
		u.shape({"kind": "circle", "c": c, "r": 22.0 + 30.0 * (t - cd) / 0.3, "col": hot, "fill": 0.85, "life": 0.05})
		return false
	var rs: Array = a.rs
	while int(a.ring) < 3 and t >= t1 + 0.15 * float(a.ring):
		var i: int = int(a.ring)
		var r0: float = 0.0 if i == 0 else float(rs[i - 1])
		var opt := {"src": "熔毁"}
		if i == 0:
			opt["stun"] = Bal.v("ult/ka_stun", 1.0)
		_hit_circle(u, a, o, c, float(rs[i]), float(a.fs[i]), a.segs[i], opt, float(rs[2]))
		var col: Color = Color(1.0, 0.35, 0.2).lerp(Color.WHITE, 0.5 - 0.2 * i)
		_ring(u, c, float(rs[i]), maxf(30.0, r0), col, 0.35, 10.0 - 2.0 * i)
		u.shape({"kind": "circle", "c": c, "r": float(rs[i]), "col": Color(1.0, 0.3, 0.2), "fill": 0.3 - 0.07 * i, "life": 0.3})
		u.shape({"kind": "dots", "c": c, "r": float(rs[i]), "n": 10 + 6 * i, "col": col, "life": 0.4})
		o.screen_shake(0.5 + 0.15 * i)
		if i == 0 and a.shell:
			u.team_buff("ult:kaltsit_shell", Bal.v("ult/ka_shell_t", 5.0), [[&"dmg_taken", "mult", Bal.v("ult/ka_shell", 0.7)]])
		a.ring = i + 1
		if a.ring == 3:
			a.melt_t = t
	if int(a.ring) < 3:
		return false
	if float(a.rebuild_t) <= 0.0:
		_m3_back(u, o, true)
	else:   # 动作到最后一圈就结束（下一次终结技不用等 8 秒）；重构由 tick_bg 每帧看点
		o.set_meta("ult_m3_back", u.g.t + float(a.rebuild_t))
		o.set_meta("ult_m3_heal", true)
	return true


## Mon3tr 重构（heal = 队长回复 8% 最大生命）
static func _m3_back(u, o, heal: bool) -> void:
	if o.has_meta("ult_m3_back"):
		o.remove_meta("ult_m3_back")
	if o.has_meta("ult_m3_heal"):
		o.remove_meta("ult_m3_heal")
	if o.pos == Vector2.INF or _ka_m3(o) != null:
		return
	var kd: Dictionary = o.ObSummon.sm_kind(o, "mon3tr")
	if kd.is_empty():
		return
	o.ObSummon.sm_spawn(o, {"kind": "mon3tr", "at": "rest"}, Vector2.INF)
	var m3 = _ka_m3(o)
	if m3 != null:
		_ring(u, m3.pos, 70.0, 10.0, Color(0.35, 0.95, 0.85), 0.4, 4.0)
	if heal:
		u.g.combat.heal(u.g.max_hp * Bal.v("ult/ka_heal", 0.08), "终结技", "kaltsit")


## 每帧（ult.tick）：凯尔希熔毁后到点重构 Mon3tr（ult_m3_heal = 正常结束，重构时给队长回血；动作被中途清掉的兜底不回血）
static func tick_bg(u) -> void:
	_m3_watch(u)


static func _m3_watch(u) -> void:
	if u.g.squad == null:
		return
	for m in u.g.squad.ops:
		if m.has_meta("ult_m3_back") and u.g.t >= float(m.get_meta("ult_m3_back")):
			_m3_back(u, m, m.has_meta("ult_m3_heal"))


# ================================================================ 乌尔比安（§4.5）：掷锚 → 沿锁链冲过去 → 落地 4 圈裂地

static func _ul_start(u, o, aim: Vector2) -> Dictionary:
	var rt := _route(o)
	var c: Vector2 = aim if aim != Vector2.INF else o.pos
	var sc: float = 410.0 / 440.0 if rt == "drag" else 1.0
	return {"k": "ulpianus", "p0": o.pos, "c": c, "ta": Bal.v("ult/ul_throw", 0.18), "td": Bal.v("ult/ul_dash", 0.22),
		"hw": 110.0 if rt == "rift" else 80.0, "rift": rt == "rift", "drag": rt == "drag", "pseg": {}, "landed": false, "thrown": false,
		"rs": [110.0 * sc, 220.0 * sc, 330.0 * sc, 440.0 * sc], "fs": [0.15, 0.2, 0.2, 0.25], "ring": 0, "segs": [{}, {}, {}, {}]}


static func _ul_step(u, a: Dictionary, o) -> bool:
	var g = u.g
	var t: float = a.t
	var p0: Vector2 = a.p0
	var c: Vector2 = a.c
	var ta: float = a.ta
	var td: float = a.td
	if t < ta:   # 锚飞出去
		var tip: Vector2 = p0.lerp(c, t / ta)
		u.shape({"kind": "line", "a": p0, "b": tip, "w": 4.0, "col": COL_STEEL, "life": 0.05})
		u.shape({"kind": "circle", "c": tip, "r": 18.0, "col": COL_STEEL, "fill": 0.9, "life": 0.05})
		return false
	if not a.thrown:
		a.thrown = true
		_ring(u, c, 90.0, 20.0, COL_STEEL, 0.25, 5.0)
		u.shape({"kind": "line", "a": p0, "b": c, "w": 4.0, "col": COL_STEEL, "life": td + 0.2})
		if a.drag:   # 不容挣脱：锚落地瞬间把半径 560 内的敌人往落点拖 120
			for e in u.in_circle(c, 560.0):
				if not e.boss and e.pos.distance_to(c) > 30.0:
					g.enemies_sys.apply_kb(e, (c - e.pos).normalized() * _kb_v(120.0) * (0.5 if e.elite else 1.0))
	if not a.landed:   # 沿锁链冲过去：队长本人位移，期间无敌
		var k: float = clampf((t - ta) / td, 0.0, 1.0)
		var p: Vector2 = p0.lerp(c, k * k)
		g.ppos = p
		o.pos = p
		g.invuln = maxf(g.invuln, 0.15)
		g.invuln_move_until = g.t + 0.15
		var hw: float = a.hw
		for e in u.in_band(p0, p, hw * 0.5):
			if a.pseg.has(int(e.id)):
				continue
			a.pseg[int(e.id)] = true
			_hit(u, a, o, e, Bal.v("ult/ul_path", 0.2), {"src": "锁链", "stun": 0.8 if a.rift else 0.0})
			if a.rift and not e.boss:
				g.enemies_sys.add_cc(e, 0.8, -INF, "airborne")
		u.shape({"kind": "band", "a": p0, "b": p, "w": hw, "col": COL_STEEL, "fill": 0.15, "life": 0.1})
		if k >= 1.0 and not a.landed:
			a.landed = true
			a["land_t"] = t
			if g.get("map") != null and g.map.has_method("push_out"):
				g.ppos = g.map.push_out(g.ppos, 12.0)
				o.pos = g.ppos
			var hw4 = o.get("hw")   # 落地后 5 秒锚击间隔 −30%：沿用 S3 的 haste 计时（他的数据里没有这个计时就跳过）
			if hw4 is Dictionary and hw4.has("timers"):
				hw4.timers["haste"] = maxf(float(hw4.timers.get("haste", 0.0)), Bal.v("ult/ul_haste", 5.0))
			o.play_vis_anim("attack")
		return false
	var lt: float = a.land_t
	var rs: Array = a.rs
	var lc: Vector2 = c
	while int(a.ring) < 4 and t >= lt + 0.18 * float(a.ring):
		var i: int = int(a.ring)
		var opt := {"src": "裂地"}
		if i == 3:
			opt["stun"] = Bal.v("ult/ul_stun", 1.2)
		var r: float = rs[i]
		var r0: float = 0.0 if i == 0 else float(rs[i - 1])
		for e in u.in_circle(lc, r):
			if a.segs[i].has(int(e.id)):
				continue
			a.segs[i][int(e.id)] = true
			var op: Dictionary = opt.duplicate()
			op["edge"] = e.pos.distance_to(lc) > float(rs[3]) * (1.0 - _edge_w())
			if i == 3 and e.pos.distance_to(lc) > 1.0:
				op["kb"] = (e.pos - lc).normalized() * _kb_v(Bal.v("ult/ul_kb", 200.0))
			_hit(u, a, o, e, float(a.fs[i]), op)
		var col: Color = COL_STEEL.lerp(Color(1.0, 0.55, 0.3), 0.25 * i)
		_ring(u, lc, r, maxf(30.0, r0), col, 0.35, 8.0 + 2.0 * i)
		u.shape({"kind": "circle", "c": lc, "r": r, "col": col, "fill": 0.12, "life": 0.25})
		u.shape({"kind": "dots", "c": lc, "r": r, "n": 8 + 5 * i, "col": col, "life": 0.35})
		o.screen_shake(0.35 + 0.15 * i)
		a.ring = i + 1
	return int(a.ring) >= 4 and t >= lt + 0.18 * 3.0 + 0.1


# ================================================================ 连携终结技通用版（§7.3）

static func _cult_generic_start(u, o, aim: Vector2, dir: Vector2) -> Dictionary:
	var g = u.g
	var lead: Dictionary = start(u, o, aim, dir)
	var fr := {}
	if str(lead.get("k", "")) == "exusiai":
		lead["share"] = 1.0
	else:
		lead["cap"] = 1.0
	lead["fr"] = fr
	var mates: Array = []
	var others: Array = []
	for m in g.squad.ops:
		if m != o and not m.is_leader and m.pos != Vector2.INF and m.cmd_down <= 0.0:
			others.append(m)
	var hx: float = u.VIEW.x * 0.5 - 80.0
	var hy: float = u.VIEW.y * 0.5 - 80.0
	var land: float = Bal.v("ult/cult_land", 0.45)
	for i in others.size():
		var m = others[i]
		var org: Vector2 = g.ppos + Vector2.from_angle(dir.angle() + TAU * (float(i) + 0.5) / float(others.size())) * 320.0
		var tp: Vector2 = m.densest_point(260.0, org)
		if tp == Vector2.INF or tp.distance_to(org) > 360.0:
			tp = org
		tp = Vector2(clampf(tp.x, g.ppos.x - hx, g.ppos.x + hx), clampf(tp.y, g.ppos.y - hy, g.ppos.y + hy))
		var stop: Vector2 = tp - (tp - m.pos).normalized() * 30.0 if tp.distance_to(m.pos) > 30.0 else m.pos
		var dur: float = land * 0.8
		m.syn_mv = {"from": m.pos, "to": stop, "t": 0.0, "dur": dur}
		m.cmd_inv = maxf(m.cmd_inv, land + 0.4)
		m._set_face(1.0 if stop.x >= m.pos.x else -1.0, true)
		u.shape({"kind": "line", "a": m.pos, "b": stop, "w": 8.0, "col": u._col(m), "life": land + 0.15})
		mates.append({"m": m, "p": stop})
	_ring(u, g.ppos, 120.0, 20.0, u._col(o).lerp(Color.WHITE, 0.5), land, 6.0)
	return {"style": "generic", "o": o, "lead": lead, "lead_done": lead.is_empty(), "mates": mates, "t": 0.0, "land": land, "landed": false, "cleared": false}


static func _cult_generic_step(u, a: Dictionary, dt: float) -> bool:
	var g = u.g
	a.t = float(a.t) + dt
	var o = a.o
	if not a.lead_done:
		a.lead_done = step(u, a.lead, dt)
	var lead: Dictionary = a.lead
	var land: float = a.land
	if not a.landed and float(a.t) >= land:
		a.landed = true
		var mr: float = Bal.v("ult/cult_mate_r", 300.0)
		for mt in a.mates:   # 队友的放大冲击（打在各自落点；份额和队长共用，合计不超过 1）
			var m = mt.m
			var p: Vector2 = mt.p
			var col: Color = u._col(m)
			_ring(u, p, mr, 40.0, col.lerp(Color.WHITE, 0.4), 0.5, 12.0)
			u.shape({"kind": "circle", "c": p, "r": mr, "col": col, "fill": 0.3, "life": 0.4})
			u.shape({"kind": "dots", "c": p, "r": mr, "n": 18, "col": col.lerp(Color.WHITE, 0.5), "life": 0.5})
			if m.pos != Vector2.INF:
				m.play_vis_anim("attack")
			if not lead.is_empty():
				for e in u.in_circle(p, mr):
					_cult_hit(u, lead, m, e, {"src": "放大冲击"})
		# 屏内所有敌人按连携终结技档一次补满（u.tier = cult）
		var vr: float = u.VIEW.length() * 0.5
		var cc: Color = u._col(o).lerp(Color.WHITE, 0.5)
		_ring(u, g.ppos, vr, 100.0, cc, 0.8, 14.0)
		u.shape({"kind": "circle", "c": g.ppos, "r": vr, "col": u._col(o), "fill": 0.18, "life": 0.45})
		u.shape({"kind": "dots", "c": g.ppos, "r": vr * 0.9, "n": 48, "col": cc, "life": 0.7})
		for e in u.in_view(g.ppos):
			if lead.is_empty():
				u.hit(o, e, 1.0, {"src": "合围"})
			else:
				_cult_hit(u, lead, o, e, {"src": "合围"})
		o.screen_shake(1.0)
	if not a.cleared and float(a.t) >= land + 0.25:
		a.cleared = true
		for mt in a.mates:
			mt.m.syn_mv = {}   # 编队跟随把队友拉回队形
	return a.lead_done and a.cleared and float(a.t) >= land + 0.3


## 连携终结技补满：按队长动作里已打的份额补到 1
static func _cult_hit(u, lead: Dictionary, o, e: Dictionary, opt: Dictionary) -> void:
	if lead.has("share"):
		_ex_hit(u, lead, o, e, 1.0, opt)
	else:
		_hit(u, lead, o, e, 1.0, opt)
