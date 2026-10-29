## 终结技形态（docs/198 §4.1–4.5，第一批 5 人）+ 连携终结技通用版（§7.3）。框架在 run/ult.gd（u），本文件只写各人怎么出招。
## 约定：start 返回动作状态字典，step 每帧推进、返回 true = 结束；伤害一律走 u.hit（按目标生命定的预算，frac = 这段占预算的比例）；
## 画面：5 人专属终结技走 Codex 第一批帧条（u.strip / tiles_line / tiles_arc，规格 art/incoming/ult_batch1_1029/manifest.json），
## 帧条接上的部分占位图形已删或减淡；瞄准指示、冲击环、其余 15 人通用版、连携终结技里队友那几下仍是 u.shape 程序占位。
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
	_fx_end(u, a)
	if str(a.get("k", "")) == "kaltsit":
		_m3_back(u, a.o, false)


# ================================================================ 帧条公用

## 弧状拼接段的参考半径（1x 像素，manifest arc_reference_radius_logical）：素材按这个半径画弧
const ARC_R0 := {"fx_ult_skalter_domain_back": 123.6385, "fx_ult_kaltsit_crack_back": 185.4578, "fx_ult_ulpianus_crack_back": 185.4578}


## 弧状拼接段铺到半径 r：沿切向缩放 k = √(r / 参考半径)、径向反缩 1 / k —— 弧的曲率正好变成 r（小角度近似），
## 厚度保持素材原样，段与段的两端切线对齐、不露缝（直接等比缩放会让小圈细得看不见、大圈粗过伤害区）
static func _arc(u, name: String, c: Vector2, r: float, opt: Dictionary = {}) -> Array:
	var r0: float = float(ARC_R0.get(name, r / u.g.PX)) * u.g.PX
	var k: float = sqrt(maxf(1.0, r) / r0)
	var op: Dictionary = opt.duplicate()
	op["sc"] = k * float(opt.get("sc", 1.0))
	op["sy"] = float(opt.get("sy", 1.0)) / k
	return u.tiles_arc(name, c, r, op)


## 拿掉一组帧条实例（每帧重铺的光束 / 锁链、提前收掉的锁定标记）：直接从 u.shapes 移除，当帧就不画
static func _kill(u, arr: Array) -> void:
	for s in arr:
		u.shapes.erase(s)
	arr.clear()


## 动作里挂着的长寿命帧条（a.fx 列表；锁定标记、海嗣、巨锚、光束、锁链）：动作结束 / 中途被清掉时一起收
static func _fx_end(u, a: Dictionary) -> void:
	for key in ["fx", "beam", "chain"]:
		if a.get(key) is Array:
			_kill(u, a[key])
	if a.get("locks") is Array:
		for lk in a.locks:
			u.shapes.erase(lk.s)
		a.locks.clear()


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
	# 剑雨帧条：一把 0.3 秒、一轮 0.8 秒铺完，同时在场约 剑数 × 0.375 × 轮数；超过 ult/tx_sword_fx（56）就隔把画（伤害照打每一把）
	var stride: int = maxi(1, ceili(float(swords.size()) * 0.375 * float(rounds.size()) / Bal.v("ult/tx_sword_fx", 56.0)))
	return {"k": "texas", "c": c, "R": R, "lines": lines, "drawn": 0, "cut": false, "cut_seg": {}, "swords": swords,
		"rounds": rounds, "rain": [], "sv": [], "stride": stride, "back": rt == "back", "back_done": false, "end": 0.0}


## 刀痕帧条（fx_ult_texas_slash_front，中心原点、沿 x 轴 384 × 40）：旋转到刀痕方向、横向拉到刀痕长
static func _tx_slash(u, ln: Array, opt: Dictionary) -> void:
	var a: Vector2 = ln[0]
	var b: Vector2 = ln[1]
	var op: Dictionary = opt.duplicate()
	op["o"] = Vector2(384, 40)
	op["ang"] = (b - a).angle()
	op["sx"] = a.distance_to(b) / (384.0 * u.g.PX)
	u.strip("fx_ult_texas_slash_front", (a + b) * 0.5, op)


static func _tx_step(u, a: Dictionary, o) -> bool:
	var t: float = a.t
	var col: Color = u._col(o)
	var hi: Color = col.lerp(Color.WHITE, 0.6)
	var lines: Array = a.lines
	var n: int = lines.size()
	while int(a.drawn) < n and t >= float(a.drawn) * 0.5 / float(n):
		# 画网：刀痕细线显现（帧段 start 0–2，停在 f2 等斩开）
		_tx_slash(u, lines[int(a.drawn)], {"seg": [0, 2], "life": maxf(0.05, 0.75 - t)})
		a.drawn = int(a.drawn) + 1
	if not a.cut and t >= 0.75:
		a.cut = true
		for ln in lines:   # 斩开：burst 3–5 → out 6–7；地面残痕沿刀痕拼接，0.8 秒走完 4 帧淡出（末帧随实例结束）
			_tx_slash(u, ln, {"seg": [3, 7]})
			u.tiles_line("fx_ult_texas_scar_back", ln[0], ln[1], {"layer": "back", "fps": 5.0, "life": 0.8})
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
		# 剑帧条比伤害早 3 帧（落 0–2）放下去，插地那一帧（f3）正好是这把剑打到的时刻；伤害时序不动
		var lead: float = 3.0 / 20.0
		if t >= t0 - lead:
			if a.sv.size() <= ri:
				a.sv.append(0)
			var due_v: int = mini(sw.size(), int(ceil((t + lead - t0) / 0.8 * float(sw.size()))))
			while int(a.sv[ri]) < due_v:
				var j: int = int(a.sv[ri])
				if j % int(a.stride) == 0:
					u.strip("fx_ult_texas_sword_front", sw[j], {"o": Vector2(32, 224)})
				a.sv[ri] = j + 1
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
	var dur: float = Bal.v("ult/ex_dur", 2.5)
	# 锁定标记（fx_ult_exusiai_lock_orbit）：精英 / Boss 先、再按距离挑普通目标，至多 ult/ex_lock_fx（24）个
	var locks: Array = []
	var lk_cap: int = int(Bal.v("ult/ex_lock_fx", 24.0))
	for e in elites + normals:
		if locks.size() >= lk_cap:
			break
		var sc: float = clampf((float(e.get("r", 14.0)) + 10.0) / 24.0, 0.8, 3.0)
		locks.append({"e": e, "out": -1.0, "s": u.strip("fx_ult_exusiai_lock_orbit", e.pos, {"o": Vector2(48, 48), "f": 0, "sc": sc, "life": dur + 0.5})})
	_ring(u, c, R, R * 0.6, col.lerp(Color.WHITE, 0.4), 0.5, 4.0)
	return {"k": "exusiai", "R": R, "mult": 0.9 if rt == "range" else 1.0, "rico": rt == "ricochet", "eq": eq, "ne": ne,
		"normals": normals, "done": {}, "fired": 0, "ncap": cap, "dur": dur, "rate": Bal.v("ult/ex_rate", 24.0), "ring_t": 0.5,
		"locks": locks, "lk_done": {}, "bt": []}


## 锁定标记推进：start 0–3 锁上 → loop 4–5 保持（跟着目标走）→ 被打到（精英：最后一发打完）/ 目标倒下 / 扫射结束 → out 6–7 碎掉
static func _ex_locks(u, a: Dictionary) -> void:
	var t: float = a.t
	for k in range(a.locks.size() - 1, -1, -1):
		var lk: Dictionary = a.locks[k]
		var e: Dictionary = lk.e
		var s: Dictionary = lk.s
		if not e.dead:
			s.c = e.pos
		if float(lk.out) < 0.0 and (e.dead or a.done.has(int(e.id)) or a.lk_done.has(int(e.id)) or t >= float(a.dur)):
			lk.out = t
		if float(lk.out) >= 0.0:
			var j: int = int((t - float(lk.out)) * 24.0)
			if j >= 2:
				u.shapes.erase(s)
				a.locks.remove_at(k)
				continue
			s.f = 6 + j
		else:
			var j2: int = int(t * 24.0)
			s.f = j2 if j2 < 4 else 4 + (j2 - 4) % 2


## 爆裂弹帧条（fx_ult_exusiai_burst_front，6 帧 0.2 秒）：同一时刻在场超过 ult/ex_burst_fx（48）个就跳过这一个（只少画、不少打）
static func _ex_burst(u, a: Dictionary, p: Vector2, sc: float) -> void:
	var t: float = a.t
	var bt: Array = a.bt
	while not bt.is_empty() and t - float(bt[0]) >= 0.2:
		bt.pop_front()
	if bt.size() >= int(Bal.v("ult/ex_burst_fx", 48.0)):
		return
	bt.append(t)
	u.strip("fx_ult_exusiai_burst_front", p, {"o": Vector2(64, 64), "sc": sc})


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
	_ex_locks(u, a)
	if t >= dur:
		for lk in a.locks:   # 还挂着的锁定标记就地碎掉（独立实例，动作照常结束）
			u.shapes.erase(lk.s)
			u.strip("fx_ult_exusiai_lock_orbit", lk.s.c, {"o": Vector2(48, 48), "sc": lk.s.sc, "seg": [6, 7]})
		a.locks.clear()
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
			if a.eq.is_empty() or int(a.eq[0].id) != int(e.id):
				a.lk_done[int(e.id)] = true   # 这是打它的最后一发：锁定标记收
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
	_ex_burst(u, a, imp, 1.0 if n_sp > 0 else 0.85)   # 主弹先占名额；爆裂半径 60 ≈ 帧条峰值帧 120 宽
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
			_ex_burst(u, a, e.pos, 0.6)
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
			_ex_burst(u, a, best.pos, 0.75)
	var mz: Vector2 = o.pos + Vector2(0, -20)
	u.shape({"kind": "line", "a": mz, "b": imp, "w": 2.0, "col": Color(1.0, 0.95, 0.7), "life": 0.06})
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
	# 海嗣（fx_ult_skalter_seaborn_front / _back，同一世界脚底）站在她身后；激光原点 = 海嗣张口处（f6 口在脚底 +8, −99）
	var fs: float = 1.0 if float(u.g.facing) >= 0.0 else -1.0
	var foot := Vector2(-56.0 * fs, -4.0)
	var soff: Vector2 = foot + Vector2(8.0 * fs, -99.0)
	var T: float = Bal.v("ult/sk_sweep", 1.6)
	var life: float = float(laps) * T + 0.6
	var sf: Dictionary = u.strip("fx_ult_skalter_seaborn_front", o.pos + foot, {"o": Vector2(160, 316), "f": 0, "sx": fs, "life": life})
	var sb: Dictionary = u.strip("fx_ult_skalter_seaborn_back", o.pos + foot, {"o": Vector2(160, 48), "f": 0, "sx": fs, "layer": "back", "life": life})
	return {"k": "skalter", "soff": soff, "foot": foot, "sf": sf, "sb": sb, "fx": [sf, sb], "beam": [], "close_t": -1.0,
		"a0": dir.angle(), "laps": laps, "lap": 0, "swept": 0.0, "lfrac": lfrac, "lseg": {},
		"T": T, "L": 480.0, "dd": dd, "dfrac": dfrac, "dc": Vector2.INF, "dt0": 0.0, "tick": 0, "buf_t": 0.0, "fr2": 0}


## 海嗣帧号（自己按时间算，写进两个实例的 f）：front 起 0–5（24 fps 快升，0.25 秒；激光伤害从第 0 帧就开始，不能等）
## → 张口 6–7 乒乓循环（12 fps，激光期间）→ 激光结束沉下 8–9（12 fps）后收；back 按 manifest front_to_back_frame_mapping 跟 front
const SK_F2B := [0, 0, 1, 1, 2, 2, 3, 4, 5, 5]


static func _sk_sea(u, a: Dictionary, o) -> void:
	if a.fx.is_empty():
		return
	var t: float = a.t
	var ff: int
	if float(a.close_t) >= 0.0:
		ff = 8 + int((t - float(a.close_t)) * 12.0)
		if ff > 9:
			_kill(u, a.fx)
			return
	elif t < 0.25:
		ff = mini(5, int(t * 24.0))
	else:
		ff = 6 + int((t - 0.25) * 12.0) % 2
	a.sf.f = ff
	a.sb.f = SK_F2B[ff]
	if float(a.close_t) < 0.0:   # 激光期间跟着她走（激光原点同样每帧按她的位置算）
		a.sf.c = o.pos + Vector2(a.foot)
		a.sb.c = a.sf.c


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
		# 光束（fx_ult_skalter_beam_front 拼接段，左端中心原点）：每帧从海嗣口沿当前角度重铺到 480；
		# 显示宽 80 = 纹理高 40（1x）× g.PX，sy 不另放大（manifest review_draw_width 80 与海嗣同一 @2x 口径）；海嗣升起那 0.25 秒淡入
		_kill(u, a.beam)
		a.beam = u.tiles_line("fx_ult_skalter_beam_front", org, tip, {"f": int(float(a.t) * 24.0) % 6, "life": 0.5,
			"col": Color(1, 1, 1, clampf(float(a.t) / 0.25, 0.35, 1.0))})
		a.fr2 = int(a.fr2) + 1
		if int(a.fr2) % 3 == 0:   # 扫过的余迹（占位减淡）
			u.shape({"kind": "sector", "c": org, "r": L, "a": cur - sgn * 0.15, "half": 0.15, "col": COL_SK_RED, "fill": 0.1, "life": 0.25})
		if float(a.swept) >= TAU:
			a.lap = int(a.lap) + 1
			a.swept = 0.0
			a.lseg = {}
			if int(a.lap) >= int(a.laps):
				a.dc = org
				a.dt0 = float(a.t)
				var dd: float = a.dd
				_kill(u, a.beam)
				a.close_t = float(a.t)   # 海嗣沉下
				u.shape({"kind": "circle", "c": org, "r": L, "col": COL_SK_RED, "fill": 0.06, "life": dd})
				# 领域花纹（fx_ult_skalter_domain_back 弧状拼接段，地面层循环）：铺在领域边上往里 20，外缘不出伤害圈
				_arc(u, "fx_ult_skalter_domain_back", org, L - 20.0, {"layer": "back", "loop": true, "life": dd})
				o.screen_shake(0.4)
		_sk_sea(u, a, o)
		return false
	_sk_sea(u, a, o)
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
	if t < t1:   # 到位：熔毁蓄力（fx_ult_kaltsit_melt_front charge 0–2，铺满这 0.3 秒）
		if not a.get("charged", false):
			a["charged"] = true
			u.strip("fx_ult_kaltsit_melt_front", c, {"o": Vector2(192, 192), "seg": [0, 2], "fps": 10.0, "life": t1 - t})
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
		if i == 0:   # 爆 3–5 对上第一圈、散 6–7（峰值帧 384 宽 ≈ 第一圈直径 360）
			u.strip("fx_ult_kaltsit_melt_front", c, {"o": Vector2(192, 192), "seg": [3, 7], "fps": 20.0})
		# 裂纹（fx_ult_kaltsit_crack_back 弧状拼接段，地面层）：裂开 0–3 → 余热 4–5，末帧留到 0.7 秒随实例结束
		_arc(u, "fx_ult_kaltsit_crack_back", c, float(rs[i]), {"layer": "back", "fps": 14.0, "life": 0.7})
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
	if m3 != null:   # 重构（fx_ult_kaltsit_rebuild_orbit，底部中心 = 脚底，12 帧 0.75 秒）：只是结构线特效，本体就是这只真 Mon3tr；_m3_watch 让它跟着走
		o.set_meta("ult_m3_fx", u.strip("fx_ult_kaltsit_rebuild_orbit", m3.pos, {"o": Vector2(128, 253)}))
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
		if m.has_meta("ult_m3_fx"):
			var s: Dictionary = m.get_meta("ult_m3_fx")
			var m3 = _ka_m3(m)
			if m3 == null or float(s.age) >= float(s.max):
				m.remove_meta("ult_m3_fx")
			else:
				s.c = m3.pos


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
		_ul_anchor(u, a, tip, (c - p0).angle())
		_ul_chain(u, a, o.pos, tip, (c - p0).angle())
		return false
	if not a.thrown:
		a.thrown = true
		_ul_anchor(u, a, c, (c - p0).angle())   # 锚扎在落点，等他冲过来
		_ring(u, c, 90.0, 20.0, COL_STEEL, 0.25, 5.0)
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
			_hit(u, a, o, e, Bal.v("ult/ul_path", 0.2), {"src": "锁链", "stun": 0.8 if a.rift else 0.0, "pre": true})   # pre：冲击帧留给第一圈裂地
			if a.rift and not e.boss:
				g.enemies_sys.add_cc(e, 0.8, -INF, "airborne")
		u.shape({"kind": "band", "a": p0, "b": p, "w": hw, "col": COL_STEEL, "fill": 0.07, "life": 0.1})
		_ul_chain(u, a, o.pos, c, (c - p0).angle())
		if k >= 1.0 and not a.landed:
			a.landed = true
			a["land_t"] = t
			_fx_end(u, a)   # 落地：收锚、收锁链
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
		# 裂地（fx_ult_ulpianus_crack_back 弧状拼接段，地面层）+ 沿圈撒喷发单元（fx_ult_ulpianus_burst_front，底部中心；喷 0–3 / 落 4–7）
		_arc(u, "fx_ult_ulpianus_crack_back", lc, r, {"layer": "back", "fps": 14.0, "life": 0.7, "a0": 0.21 * i})
		var nb: int = clampi(roundi(TAU * r / 140.0), 5, int(Bal.v("ult/ul_burst_fx", 14.0)))
		var bsc: float = 0.6 + 0.07 * i   # 水柱是竖着的高度，外圈也压在 0.8 以内，免得顶上一圈高出伤害区太多
		for j in nb:
			var ang: float = 0.37 * i + TAU * (float(j) + 0.5 * float(i % 2)) / float(nb)
			u.strip("fx_ult_ulpianus_burst_front", lc + Vector2.from_angle(ang) * r, {"o": Vector2(64, 192), "sc": bsc,
				"delay": 0.02 * float((j * 3) % 4)})
		o.screen_shake(0.35 + 0.15 * i)
		a.ring = i + 1
	return int(a.ring) >= 4 and t >= lt + 0.18 * 3.0 + 0.1


## 巨锚（fx_ult_ulpianus_anchor_front）：4 个角度帧 f0–f3 = 锚头朝下（+90°）起每帧顺时针 45°；
## 按飞行方向取最近的角度帧（超过 180° 的用对面那帧转半圈），剩下的差角用旋转补；不按 fps 播
static func _ul_anchor(u, a: Dictionary, p: Vector2, dir_ang: float) -> void:
	var rho: float = dir_ang - PI / 2.0
	var k: int = posmod(roundi(rho / (PI / 4.0)), 8)
	var f: int = k % 4
	if not a.has("anc"):
		a["anc"] = u.strip("fx_ult_ulpianus_anchor_front", p, {"o": Vector2(96, 96), "f": f, "life": float(a.ta) + float(a.td) + 0.3})
		if not a.has("fx"):
			a["fx"] = []
		a.fx.append(a.anc)
	var s: Dictionary = a.anc
	s.c = p
	s.f = f
	s.ang = rho - f * PI / 4.0


## 锁链（fx_ult_ulpianus_chain_front 拼接段，循环 0–1）：从他手边铺到锚尾（锚中心往回 60），每帧重铺
static func _ul_chain(u, a: Dictionary, from: Vector2, tip: Vector2, dir_ang: float) -> void:
	if not a.has("chain"):
		a["chain"] = []
	_kill(u, a.chain)
	var b: Vector2 = tip - Vector2.from_angle(dir_ang) * 60.0
	var p: Vector2 = from + Vector2(0, -20)
	if (b - p).dot(Vector2.from_angle(dir_ang)) < 8.0:
		return
	a.chain = u.tiles_line("fx_ult_ulpianus_chain_front", p, b, {"f": int(float(a.t) * 12.0) % 2, "life": 0.3})


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
