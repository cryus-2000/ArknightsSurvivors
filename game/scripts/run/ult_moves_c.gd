## 终结技 第三组（塞雷娅 / 铃兰 / 逻各斯 / 星熊 / 推进之王 / 艾丽妮 / 拉普兰德 / 流明）（docs/198 §4.13–4.20，用户 10-29「20 个干员的都做好、先用粒子特效」）。接口同 run/ult_moves.gd：
## handles(id) 本文件管哪些人；aim_kind / aim_r 瞄准；start(u, o, aim, dir) 返回动作字典（ult_moves 会写入 a.k / a.o / a.t）；step(u, a, dt) true = 结束。
## 约定同 ult_moves：伤害一律走 u.hit（按目标生命定的预算，frac = 这段占预算的比例，各段合计 ≈ 1）；每段各记一张已命中表（e.id），同一敌人同一段只打一次；
## 带 cap 的动作（连携终结技通用版包进来时）每名敌人合计不超过 cap。冲击帧落在主打击那一下：之前的铺垫段标 pre。
## 外缘衰减带：圆形按面积口径取外圈 15%（核心半径 = R × ult/c_core 0.92 ≈ √0.85），带形 / 矩形按宽度取两侧各 15%（核心半宽 × ult/c_band_core 0.85）。
## 10-30 对齐 §3.4：以自身为圆心的四人（塞雷娅 / 星熊 / 拉普兰德 / 流明）R = 502（罩住 500 处的精英），核心系数各自 ult/<前缀>_core 0.872（核心 ≈ 438）：
## 均匀场景小怪 47.5%、聚怪 76.7%；核心再大均匀场景到 50.8% 但聚怪 80% 以上，核心 ≤ 436 聚怪 75% 但均匀只剩 44.2%（测试台网格的台阶，两头不能同时满足）。
## 画面全是程序占位（u.shape）+ 少量现有帧条（u.strip，art/fx 里已有的干员特效）；不用新素材、不画通用圆（动作字典都带 no_ring，冲击环各自画）。不抽随机数，散布按序号算。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const PF = preload("res://scripts/run/ult_pixfx.gd")   # pixfx 大贴图画法（docs/199 §7.8）
const IDS: Array = ["saria", "suzuran", "logos", "hoshiguma", "siege", "irene", "lappland", "lumen"]
const DIR_OPS: Array = ["suzuran", "logos", "irene"]   # 塞雷娅 10-30 改成以自身为圆心的拳风环，不瞄
const POINT_OPS: Array = ["siege"]

const COL_AMBER := Color(1.0, 0.72, 0.3)
const COL_LIGHT := Color(0.96, 0.98, 1.0)
const COL_INK := Color(0.3, 0.32, 0.85)
const COL_RED := Color(0.95, 0.25, 0.18)
const COL_ROCK := Color(0.62, 0.48, 0.3)
const COL_WIND := Color(0.9, 0.95, 1.0)


static func handles(id: String) -> bool:
	return id in IDS


static func aim_kind(id: String) -> String:
	if id == "lappland" and _la_fwd():   # 用户 10-31：改成往前乱砍
		return "dir"
	if id in DIR_OPS:
		return "dir"
	if id in POINT_OPS:
		return "point"
	return "none"


static func aim_r(id: String) -> float:
	match id:
		"saria":
			return Bal.v("ult/sa_r", 502.0)
		"siege":
			return Bal.v("ult/sg_r", 540.0)
		"irene":
			return Bal.v("ult/ir_r", 860.0)
		"lappland":
			return Bal.v("ult/la_fr", 860.0) if _la_fwd() else Bal.v("ult/la_r", 502.0)
	return 460.0


static func start(u, o, aim: Vector2, dir: Vector2) -> Dictionary:
	if o == null or o.pos == Vector2.INF:
		return {}
	var d: Vector2 = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	var a: Dictionary = {}
	var id := str(o.id)
	match id:
		"saria":
			a = _sa_start(u, o, d)
		"suzuran":
			a = _su_start(u, o, d)
		"logos":
			a = _lo_start(u, o, d)
		"hoshiguma":
			a = _ho_start(u, o)
		"siege":
			a = _sg_start(u, o, aim, d)
		"irene":
			a = _ir_start(u, o, d)
		"lappland":
			a = _la_start(u, o, d)
		"lumen":
			a = _lu_start(u, o)
	if a.is_empty():
		return {}
	a["id"] = id
	a["no_ring"] = true   # 冲击环各人自己画（框架那道 520 的通用圈不要）
	return a


static func step(u, a: Dictionary, dt: float) -> bool:
	if a.is_empty() or not a.has("id"):
		return true
	var o = a.o
	match str(a.id):
		"saria":
			return _sa_step(u, a, o)
		"suzuran":
			return _su_step(u, a, o)
		"logos":
			return _lo_step(u, a, o)
		"hoshiguma":
			return _ho_step(u, a, o)
		"siege":
			return _sg_step(u, a, o)
		"irene":
			return _ir_step(u, a, o)
		"lappland":
			return _la_step(u, a, o)
		"lumen":
			return _lu_step(u, a, o, dt)
	return true


# ================================================================ 公用

## 一段伤害：带 cap 的动作（连携终结技）每名敌人合计不超过 cap（同 ult_moves._hit）
static func _hit(u, a: Dictionary, o, e: Dictionary, frac: float, opt: Dictionary = {}) -> float:
	if a.has("cap"):
		var k: int = int(e.id)
		var done: float = float(a.fr.get(k, 0.0))
		frac = minf(frac, float(a.cap) - done)
		if frac <= 0.0001:
			return 0.0
		a.fr[k] = done + frac
	return u.hit(o, e, frac, opt)


## 同一段只打一次：seg 已命中表
static func _once(u, a: Dictionary, o, seg: Dictionary, e: Dictionary, frac: float, opt: Dictionary) -> bool:
	if seg.has(int(e.id)):
		return false
	seg[int(e.id)] = true
	_hit(u, a, o, e, frac, opt)
	return true


static func _core() -> float:
	return Bal.v("ult/c_core", 0.92)


static func _band_core() -> float:
	return Bal.v("ult/c_band_core", 0.85)


static func _route(o) -> String:
	var r = o.get("route")
	return str(r) if r != null else ""


## 击退距离 → 冲量（敌人 kb 每秒衰减 900）
static func _kb_v(dist: float) -> float:
	return sqrt(1800.0 * maxf(0.0, dist))


static func _minion(e: Dictionary) -> bool:
	return not (e.elite or e.boss or e.get("part", false))


## 局部坐标（x = 沿 d 向前，y = 侧向）
static func _loc(p: Vector2, org: Vector2, d: Vector2) -> Vector2:
	var r: Vector2 = p - org
	return Vector2(r.dot(d), r.dot(d.orthogonal()))


static func _w(org: Vector2, d: Vector2, x: float, y: float) -> Vector2:
	return org + d * x + d.orthogonal() * y


## 带 / 矩形：沿 d 从 x0 到 x1、两侧半宽 hw 内（敌人半径算一半）
static func _in_rect(u, org: Vector2, d: Vector2, x0: float, x1: float, hw: float) -> Array:
	var out: Array = []
	for e in u.g.enemies:
		if e.dead or e.get("friendly", false):
			continue
		var l: Vector2 = _loc(e.pos, org, d)
		var er: float = float(e.get("r", 10.0)) * 0.5
		if l.x >= x0 - er and l.x <= x1 + er and absf(l.y) <= hw + er:
			out.append(e)
	return out


## 扇形：朝 ang、半角 half、半径 r
static func _in_sector(u, c: Vector2, r: float, ang: float, half: float) -> Array:
	var out: Array = []
	for e in u.in_circle(c, r):
		var dv: Vector2 = e.pos - c
		if dv.length() < 30.0 or absf(angle_difference(ang, dv.angle())) <= half:
			out.append(e)
	return out


## 队长本人位移（期间无敌，同乌尔比安冲锋）
static func _lead_move(u, o, p: Vector2) -> void:
	var g = u.g
	g.ppos = p
	o.pos = p
	g.invuln = maxf(g.invuln, 0.15)
	g.invuln_move_until = g.t + 0.15


static func _lead_land(u, o) -> void:
	var g = u.g
	if g.get("map") != null and g.map.has_method("push_out"):
		g.ppos = g.map.push_out(g.ppos, 12.0)
		o.pos = g.ppos


static func _ring(u, c: Vector2, r: float, r1: float, col: Color, life: float, w := 6.0, delay := 0.0) -> void:
	u.shape({"kind": "ring", "c": c, "r": r, "r1": r1, "w": w, "col": col, "life": life, "delay": delay})


## 正六边形描边（星熊盾阵）
static func _hex(u, c: Vector2, r: float, rot: float, col: Color, w: float, life: float, delay := 0.0) -> void:
	for i in 6:
		var p0: Vector2 = c + Vector2.from_angle(rot + TAU * i / 6.0) * r
		var p1: Vector2 = c + Vector2.from_angle(rot + TAU * (i + 1) / 6.0) * r
		u.shape({"kind": "line", "a": p0, "b": p1, "w": w, "col": col, "life": life, "delay": delay})


## 弧线（折线近似）
static func _arc_lines(u, c: Vector2, r: float, a0: float, a1: float, n: int, col: Color, w: float, life: float, delay := 0.0) -> void:
	for i in n:
		var p0: Vector2 = c + Vector2.from_angle(lerpf(a0, a1, float(i) / n)) * r
		var p1: Vector2 = c + Vector2.from_angle(lerpf(a0, a1, float(i + 1) / n)) * r
		u.shape({"kind": "line", "a": p0, "b": p1, "w": w, "col": col, "life": life, "delay": delay})


## 队友技力 +pct（各技能按所需技力的比例加，已满 / 常驻的不动；不含自身）
static func _team_sp(u, o, pct: float) -> void:
	for m in u.g.squad.ops:
		if m == o or m.pos == Vector2.INF or not m.has_method("skill_unlocked"):
			continue
		for i in 3:
			if m.skill_unlocked(i) and m.sp_need(i) > 0.0 and not m.perm[i]:
				m.sp[i] = minf(m.sp_need(i), float(m.sp[i]) + m.sp_need(i) * pct)


## 浮空高度推进：air = [{e, t0, dur, h}]（画面抬高；落地清零）
static func _air_tick(u, a: Dictionary) -> void:
	var t: float = a.t
	for ar in a.air:
		var e: Dictionary = ar.e
		if e.dead or ar.get("down", false):
			continue
		var k: float = (t - float(ar.t0)) / maxf(0.01, float(ar.dur))
		if k >= 1.0:
			ar["down"] = true
			u.g.enemies_sys.set_air(e, 0.0)
		else:
			u.g.enemies_sys.set_air(e, sin(clampf(k, 0.0, 1.0) * PI) * float(ar.h), true)


static func _air_end(u, a: Dictionary) -> void:
	for ar in a.get("air", []):
		if not ar.e.dead and not ar.get("down", false):
			u.g.enemies_sys.set_air(ar.e, 0.0)
			ar["down"] = true


static func _launch(u, a: Dictionary, e: Dictionary, dur: float, h: float) -> void:
	if e.dead or e.boss:
		return
	var du: float = dur * (0.5 if e.elite else 1.0)
	u.g.enemies_sys.add_cc(e, du, -INF, "airborne")
	a.air.append({"e": e, "t0": float(a.t), "dur": du, "h": h})


# ================================================================ 塞雷娅（§4.13）：举拳蓄力 → 一拳砸地，拳风冲击环向四周打出去 + 脚下放射裂纹、沿裂纹接连爆开
## 10-30 用户「应该是一圈打出去的拳风和裂地的感觉」返工：不再是直线带、不瞄（aim_kind none）。以她为圆心半径 ult/sa_r（502；核心 × ult/sa_core 0.872 ≈ 438，
## 参考场景 500 处的精英也罩得住）：
##   举拳 ult/sa_charge（0.2 秒，琥珀光往拳头收）→ 砸地：轻震 + 拳风冲击环 ult/sa_travel（0.25 秒）扩到 R，波前扫过的敌人吃 1 − 裂地份额、往外击飞 ult/sa_kb（360）；
##   同时脚下裂开 ult/sa_cracks（10）道放射裂纹（琥珀色折线往外延伸），裂纹上每隔一节接连爆开（半径 80，每人一次 ult/sa_crack 20%）。
## 路线：碎晶 → 裂纹 14 道、裂地 30%（冲击环降到 70%）；急救针剂 → 结束时队长回复 6% 最大生命。附带护盾一层照旧
static func _sa_start(u, o, d: Vector2) -> Dictionary:
	var rt := _route(o)
	var R: float = Bal.v("ult/sa_r", 502.0)
	var cf: float = 0.3 if rt == "shatter" else Bal.v("ult/sa_crack", 0.2)
	var nc: int = 14 if rt == "shatter" else int(Bal.v("ult/sa_cracks", 10.0))
	var c: Vector2 = o.pos
	var ch: float = Bal.v("ult/sa_charge", 0.2)
	var tr: float = Bal.v("ult/sa_travel", 0.25)
	var cspd: float = R / Bal.v("ult/sa_crack_t", 0.3)   # 裂纹往外长的速度
	# 裂纹：每道是一条折线（节长 75，侧向按序号摆 ±18，不抽随机数）；第 1 / 3 / 5 节的端点是爆点
	var cracks: Array = []
	var booms: Array = []
	var a0: float = d.angle() + 0.2
	for i in nc:
		var ang: float = a0 + TAU * float(i) / float(nc) + 0.12 * sin(float(i) * 2.7)
		var dv := Vector2.from_angle(ang)
		var nv: Vector2 = dv.orthogonal()
		var pts: Array = [c + dv * 26.0]
		var x := 26.0
		var j := 0
		while x < R - 20.0:
			x = minf(R - 20.0, x + 75.0)
			j += 1
			pts.append(c + dv * x + nv * 18.0 * sin(float(i) * 7.3 + float(j) * 2.1))
		cracks.append(pts)
		for k in range(1, pts.size(), 2):
			booms.append({"p": pts[k], "t": ch + 0.06 + c.distance_to(pts[k]) / cspd, "done": false})
	var fist: Vector2 = c + Vector2(0, -58)
	var col: Color = u._col(o)
	# 举拳蓄力：琥珀光往高举的拳头收束
	_ring(u, fist, 22.0, 170.0, col.lerp(Color.WHITE, 0.3), ch + 0.02, 5.0)
	for k in 12:
		var dv := Vector2.from_angle(k * TAU / 12.0 + 0.3)
		u.shape({"kind": "line", "a": fist + dv * 150.0, "b": fist + dv * 105.0, "w": 3.0, "col": COL_AMBER, "life": ch, "v": -dv * 480.0})
	u.shape({"kind": "dots", "c": fist, "r": 100.0, "n": 16, "col": COL_AMBER.lerp(Color.WHITE, 0.4), "life": ch})
	u.shape({"kind": "circle", "c": fist, "r": 26.0, "col": COL_AMBER.lerp(Color.WHITE, 0.3), "fill": 0.8, "life": ch})
	u.light(fist, 140.0, COL_AMBER, ch)
	for k in 8:
		var dq := Vector2.from_angle(k * TAU / 8.0)
		u.grain("mote_in", fist + dq * 120.0, -dq, COL_AMBER, 2)
	u.shake(2.0, 0.15)
	var v2: bool = _sa_v2(u)
	if v2:   # 举拳那一下脚下一大片压暗
		u.shape({"kind": "circle", "c": c, "r": R * 1.05, "col": Color(0.0, 0.0, 0.01), "fill": 0.45, "life": ch + 0.03, "layer": "back"})
	return {"v2": v2, "org": c, "R": R, "ch": ch, "tr": tr, "cspd": cspd, "wf": 1.0 - cf, "cf": cf, "cracks": cracks, "booms": booms,
		"rc": R * Bal.v("ult/sa_core", 0.872), "wseg": {}, "cseg": {}, "punched": false, "punched2": false, "heal": rt == "syringe", "end_t": ch + maxf(tr, R / cspd + 0.06) + 0.12, "healed": false}


static func _sa_step(u, a: Dictionary, o) -> bool:
	var g = u.g
	var t: float = a.t
	var ch: float = a.ch
	var org: Vector2 = a.org
	var R: float = a.R
	var tr: float = a.tr
	var col: Color = u._col(o)
	if t < ch:
		return false
	if not a.punched:
		a.punched = true
		o.play_vis_anim("attack")
		u.shake(Bal.v("ult/sa_shake", 8.0), 0.35)
		# 砸地：落点白闪 + 拳风冲击环（白芯 + 两道琥珀，生长段 = 冲击环走到 R 的时间）+ 往外飞的拳风速度线
		u.shape({"kind": "circle", "c": org, "r": 110.0, "col": COL_AMBER.lerp(Color.WHITE, 0.45), "fill": 0.95, "life": 0.1})
		u.shape({"kind": "ellipse", "c": org + Vector2(0, 8), "rx": 150.0, "ry": 70.0, "col": COL_ROCK.darkened(0.45), "fill": 0.6, "life": 1.2, "layer": "back"})   # 砸出的浅坑
		u.light(org, 380.0, COL_AMBER, 0.45)
		u.debris(org, COL_AMBER, 3)
		u.debris(org, COL_ROCK, 2)
		u.spark(org, COL_AMBER, 10, 30.0)
		if a.v2:
			_sa_punch_v2(u, a, org, R, tr)
	if not a.punched2 and not a.v2:
		a.punched2 = true
		u.shape({"kind": "circle", "c": org, "r": R, "col": COL_AMBER, "fill": 0.16, "life": tr + 0.15})
		_ring(u, org, R, 40.0, COL_AMBER.lerp(Color.WHITE, 0.5), tr * 2.0, 26.0)   # 缺省碎裂：拳风是一圈往外崩的碎块
		_ring(u, org, R * 0.96, 30.0, COL_AMBER.lerp(Color.WHITE, 0.25), tr * 2.0, 14.0, 0.03)
		_ring(u, org, R * 0.9, 20.0, COL_AMBER, tr * 2.0 + 0.1, 6.0, 0.07)
		_ring(u, org, 160.0, 20.0, COL_AMBER.lerp(Color.WHITE, 0.5), 0.2, 10.0)
		var spd: float = R / tr
		for k in 20:
			var dv := Vector2.from_angle(float(k) * TAU / 20.0 + 0.05)
			var r0: float = 40.0 + 30.0 * float(k % 3)
			u.shape({"kind": "line", "a": org + dv * r0, "b": org + dv * (r0 + 120.0), "w": 4.0 if k % 2 == 0 else 2.5,
				"col": COL_AMBER.lerp(Color.WHITE, 0.5 if k % 2 == 0 else 0.2), "life": tr * 0.95, "v": dv * spd})
		u.shape({"kind": "dots", "c": org, "r": R * 0.5, "n": 30, "col": COL_ROCK.lerp(COL_AMBER, 0.4), "life": 0.5})
		# 裂纹：从脚下往外一节节长出去（每节按离她的距离延迟），琥珀粗线 + 前段白芯，0.9 秒后淡掉
		var cspd: float = a.cspd
		for pts in a.cracks:
			for j in pts.size() - 1:
				var p0: Vector2 = pts[j]
				var p1: Vector2 = pts[j + 1]
				var dl: float = org.distance_to(p0) / cspd
				var wk: float = 1.0 - float(j) / float(pts.size())
				u.shape({"kind": "line", "a": p0, "b": p1, "w": 3.0 + 6.0 * wk, "col": COL_AMBER.darkened(0.15), "life": 1.1 - dl, "delay": dl, "layer": "back"})   # 裂纹画在地面层（怪脚下）
				if j < 2:
					u.shape({"kind": "line", "a": p0, "b": p1, "w": 1.5 + 1.5 * wk, "col": COL_AMBER.lerp(Color.WHITE, 0.45), "life": 0.6 - dl, "delay": dl, "layer": "back"})
	if a.punched and not a.get("shielded", false):
		a["shielded"] = true
		g.shield = mini(g.shield + 1, maxi(g.shield_max, 1) + 1)   # 附带：队长护盾（本作护盾按层；docs 写 15% 最大生命，没有按量的护盾，先给一层）
		g.shield_pop = 1.0
	if a.v2:
		PF.beats_tick(u, a, t, org, Color(1.0, 0.9, 0.7))
	# 拳风冲击环：波前扫过的敌人各吃一次，往外击飞、短硬直
	var f: float = R * clampf((t - ch) / tr, 0.0, 1.0)
	var hc: float = a.rc
	var kb: float = _kb_v(Bal.v("ult/sa_kb", 360.0))
	for e in u.in_circle(org, f):
		var off: Vector2 = e.pos - org
		var dv: Vector2 = off.normalized() if off.length() > 1.0 else Vector2.RIGHT
		_once(u, a, o, a.wseg, e, float(a.wf), {"src": "拳风", "edge": off.length() > hc, "kb": dv * kb, "stun": 0.3})
	# 拳风扫地扬尘：波前所到的半径上撒一圈尘（颗粒拼出往外推的环）
	if f < R and int(t * 60.0) % 2 == 0:
		for k in 14:
			var dq := Vector2.from_angle(float(k) * TAU / 14.0 + t * 3.0)
			u.grain("bfx_dust", org + dq * f, dq, Color(0.62, 0.6, 0.56) if a.v2 else COL_ROCK.lerp(COL_AMBER, 0.5), 2)
	# 沿裂纹接连爆开
	for b in a.booms:
		if b.done or t < float(b.t):
			continue
		b.done = true
		var p: Vector2 = b.p
		for e in u.in_circle(p, 80.0):
			_once(u, a, o, a.cseg, e, float(a.cf), {"src": "裂地", "edge": e.pos.distance_to(org) > hc})
		if a.v2:   # v2：沿裂口崩起一簇碎石 + 尘，不画琥珀圆盘 / 晶柱（用户 10-30 嫌琥珀）
			var hb: float = PF.h(float(a.booms.find(b)) + PF.vseed(u, org))
			for m in 3:
				PF.rock(u, p, Vector2.from_angle(TAU * (m + hb) / 3.0) * 70.0, 200.0 + 90.0 * PF.h(hb + m), PF.h(hb * 7.0 + m), 0.45, 0.02 * m)
			u.grain("bfx_dust", p, Vector2.UP, Color(0.62, 0.6, 0.56), 5)
		else:
			u.shape({"kind": "circle", "c": p, "r": 54.0, "col": COL_AMBER.lerp(Color.WHITE, 0.2), "fill": 0.7, "life": 0.14})
			_ring(u, p, 92.0, 16.0, COL_AMBER.lerp(Color.WHITE, 0.3), 0.26, 6.0)
			u.strip("fx_saria_pillar_break", p + Vector2(0, -16), {"sc": 1.4})
		var bi: int = a.booms.find(b)
		u.grain("sh_shard", p, Vector2.UP, Color(0.7, 0.68, 0.64) if a.v2 else COL_AMBER, 5)
		u.grain("bfx_dust", p, Vector2.UP, COL_ROCK, 3)
		if bi % 3 == 0 and not a.v2:   # 灯只有 16 盏、碎屑也抽稀
			u.light(p, 130.0, COL_AMBER, 0.2)
			u.debris(p, COL_AMBER, 1)
			u.spark(p, COL_AMBER, 3, 18.0)
	if t >= float(a.end_t):
		if a.heal and not a.healed:
			a.healed = true
			g.combat.heal(g.max_hp * Bal.v("ult/sa_heal", 0.06), "终结技", "saria")
		return true
	return false


## ---------------- 塞雷娅 v2（ult/sa_fx_v2，缺省 1；0 = 程序画同心碎裂环 + 琥珀折线裂纹 + 速度线版。pixfx，docs/199 §7.8）
## 举拳时脚下压暗 → 砸地（爆点 / 判定 / 时序不动）。第一版（琥珀冲击环贴图 + 琥珀裂网）已撤：
## 用户 10-30 第二轮：「一圈超人感没做出来；要的不是琥珀裂网，是一拳打出去以后拳风造成的裂地」→ 白色气浪 + 波前尘石墙；
## 第三轮：「裂地的力量感、停顿感还不够，所有裂地都跟乌尔比安的对齐」→ 裂缝换成乌尔比安同形的分叉裂网（fx_sa_fork1–4，淡金白光、暖灰岩唇），
## 顺原裂纹方向随拳风往外长、先亮后冷；砸地那下另加 ult/sa_hitstop（0.12 秒）顿帧 + 大灯 + 碎屑
const SA_FORKS := ["fx_sa_fork1", "fx_sa_fork2", "fx_sa_fork3", "fx_sa_fork4"]
const A = preload("res://scripts/art.gd")


static func _sa_v2(u) -> bool:
	return Bal.v("ult/sa_fx_v2", 1.0) > 0.0 and PF.pick(u, SA_FORKS, 0.0) != "" and u.fx_ready(PF.WALL)


static func _sa_punch_v2(u, a: Dictionary, org: Vector2, R: float, tr: float) -> void:
	var vs: float = PF.vseed(u, org)
	u.g.vfx.stop(Bal.v("ult/sa_hitstop", 0.12), "ult", true)   # 停顿感：砸地那一下顿住（画面层，同 skalter 收尾大爆）
	u.light(org, R * 0.8, Color(1.0, 0.9, 0.7), 0.4)
	u.debris(org, Color(0.85, 0.8, 0.7), 3)
	# 拳坑
	u.shape({"kind": "ellipse", "c": org + Vector2(0, 6), "rx": 120.0, "ry": 60.0, "col": Color(0.08, 0.07, 0.06), "fill": 0.7, "life": 1.8, "layer": "back"})
	# 裂网：顺原裂纹方向（爆点都在线上），随拳风往外长
	var angs: Array = []
	var lens: Array = []
	var j := 0
	for pts in a.cracks:
		angs.append((Vector2(pts[pts.size() - 1]) - org).angle())
		lens.append(R * (0.62 + 0.45 * PF.h(j + 21.0 + vs)))
		j += 1
	PF.cracks(u, SA_FORKS, org, angs, lens, {"seed": vs, "rev": R / float(a.cspd), "rev0": 0.15, "delay": 0.03, "life": 2.0, "fade": 0.7,
		"col": Color(1.15, 1.1, 1.05), "col1": Color(0.3, 0.27, 0.24), "cold": 0.9})
	# 白色气浪薄环（两道，后一道稍慢）
	u.shape({"kind": "ring", "c": org, "r": R, "r1": 50.0, "w": 10.0, "col": Color(0.95, 0.93, 0.88), "solid": true, "life": tr * 2.0})
	u.shape({"kind": "ring", "c": org, "r": R * 0.85, "r1": 40.0, "w": 5.0, "col": Color(0.9, 0.85, 0.75), "solid": true, "life": tr * 2.3, "delay": 0.04})
	_sa_wall(u, org, R * 0.22, R / tr, tr, vs)
	var spd: float = R / tr
	for k in 24:
		var dv := Vector2.from_angle(TAU * (k + PF.h(k + vs)) / 24.0)
		var r0: float = 40.0 + 40.0 * PF.h(k * 3.0 + vs)
		u.shape({"kind": "line", "a": org + dv * r0, "b": org + dv * (r0 + 90.0 + 60.0 * PF.h(k + 7.0)), "w": 4.0 if k % 3 == 0 else 2.5,
			"col": Color(0.95, 0.95, 0.9), "life": tr * 0.9, "v": dv * spd * 1.05})
	# 节奏（用户 10-30「裂地的顿感和节奏」对齐乌尔比安：一拍一圈、每拍震屏 + 隆起 + 灯 + 尘，间隔 0.18）
	a["vs"] = vs
	a["beats"] = [[float(a.t) + 0.0, R * 0.3, 0], [float(a.t) + 0.18, R * 0.55, 1], [float(a.t) + 0.36, R * 0.8, 2], [float(a.t) + 0.54, R * 1.0, 3]]
	PF.particles(u, org, 160, "ult_burst_s", [Color(1.0, 0.95, 0.85), Color(0.75, 0.7, 0.62)], 0.0, vs)   # 拳坑迸出的碎石尘
	PF.aftershock(u, org, R, 3.0 + vs, 0.54 + 0.3, 14)


## 尘土碎石墙从半径 r0 起以 spd 往外推 dur 秒（段数按终点半径取，起点处互相叠着，不会断开）
static func _sa_wall(u, c: Vector2, r0: float, spd: float, dur: float, vs: float) -> void:
	var t: Texture2D = u._strip_tex(PF.WALL)
	var k: float = u.g.PX / A.hires_of(t)
	var R1: float = r0 + spd * dur
	var n: int = maxi(16, roundi(TAU * R1 / 150.0))
	var chord: float = 2.0 * R1 * sin(PI / n)
	var uw: float = minf(t.get_width(), chord * 1.1 / k)
	for q in n:
		var am: float = TAU * (q + 0.5) / n + PF.h(vs) * TAU
		var out := Vector2.from_angle(am)
		var tg: Vector2 = out.orthogonal()
		var sc: float = r0 / R1
		u.strip(PF.WALL, c + out * r0 - tg * chord * 0.5 * sc, {"layer": "back", "ang": tg.angle(), "o": Vector2(0.0, t.get_height() * 0.5),
			"ux": floorf(PF.h(q * 3.0 + vs) * (t.get_width() - uw)), "uw": uw, "sc": sc, "sc1": 1.0, "scd": dur,
			"v": out * spd - tg * chord * 0.5 * (1.0 - sc) / dur, "life": dur + 0.25, "fade": 0.35, "col": Color(1, 1, 1, 0.9)})


## ---------------- 推进之王 v2（ult/sg_fx_v2，缺省 1；0 = 程序画同心环 + 直线裂地 + 碎石刀光版。pixfx，docs/199 §7.8）
## 跃空时落点地面渐暗（压暗）→ 砸落：白闪 + 顿帧 + pixgen 灰黑尘浪环（fx_sg_shock 3 种）扩到 R、乌尔比安同形灰裂网（fx_sg_fork）11–15 条往外长、
## 三圈地块隆起、外圈尘土墙外推、余震；岩刺 / 碎石帧条照旧。不用凯尔希的红白熔缝（验收员 10-30）
## 变体：尘浪环 3 种；裂网（用户 10-30「推进之王的裂地感太直」「都跟乌尔比安的对齐」）用乌尔比安同形的分叉裂缝 4 种转灰（fx_sg_fork1–4：灰白尘光、冷灰岩唇）
const SG_RINGS := ["fx_sg_shock", "fx_sg_shock2", "fx_sg_shock3"]
const SG_FORKS := ["fx_sg_fork1", "fx_sg_fork2", "fx_sg_fork3", "fx_sg_fork4"]


static func _sg_v2(u) -> bool:
	return Bal.v("ult/sg_fx_v2", 1.0) > 0.0 and PF.pick(u, SG_RINGS, 0.0) != "" and PF.pick(u, SG_FORKS, 0.0) != ""


static func _sg_smash_v2(u, c: Vector2, R: float) -> void:
	var vs: float = PF.vseed(u, c)
	PF.ring(u, SG_RINGS, c, 60.0, R * 1.02, 0.28, 0.4, {"seed": vs, "fade": 0.3, "col": Color(1, 1, 1, 0.7)})
	_ring(u, c, R, 60.0, COL_ROCK.lerp(Color.WHITE, 0.2), 0.4, 6.0)   # 细的范围环
	PF.crack_net(u, SG_FORKS, c, R, 11 + int(PF.h(vs + 1.0) * 5.0), PF.h(vs + 2.0) * TAU, vs, 0.54, Color(1.1, 1.08, 1.05), Color(0.3, 0.29, 0.28), 30.0)
	u.g.vfx.stop(Bal.v("ult/sg_hitstop", 0.1), "ult", true)
	PF.particles(u, c, 200, "ult_burst_s", [Color(0.95, 0.92, 0.85), Color(0.7, 0.68, 0.62)], 0.0, vs)   # 锤坑迸出的碎石尘
	PF.wall(u, c, R, 0.54)
	PF.aftershock(u, c, R, 7.0 + vs, 0.54 + 0.3, 12)


# ================================================================ 铃兰（§4.14）：忍冬在她身旁现身 → 化白光瞬身斩出 → 停半拍 → 斩痕爆裂

static func _su_start(u, o, d: Vector2) -> Dictionary:
	var rt := _route(o)
	var hw: float = Bal.v("ult/su_w", 1000.0) * 0.5
	var L: float = Bal.v("ult/su_len", 900.0)
	var bk: float = Bal.v("ult/su_back", 160.0)   # 斩痕带从队长身后 bk 起（10-30 对齐 §3.4：原 60）
	var side: Vector2 = o.pos + d.orthogonal() * -48.0 + d * -10.0
	var tp: float = Bal.v("ult/su_appear", 0.3)
	var col: Color = u._col(o)
	# 忍冬：程序剪影（白光人形 + 狐耳 + 刀 + 三条尾巴），淡入
	var gold: Color = col.lerp(Color.WHITE, 0.2)
	u.shape({"kind": "circle", "c": side + Vector2(0, -36), "r": 54.0, "col": COL_LIGHT, "fill": 0.22, "life": tp + 0.05})
	_ring(u, side + Vector2(0, -36), 60.0, 20.0, gold, tp, 3.0)
	for k in 3:
		var ta: float = PI * 0.5 + (k - 1) * 0.5
		u.shape({"kind": "sector", "c": side + Vector2(0, -14), "r": 34.0, "a": ta + PI * 0.15, "half": 0.16, "col": gold, "fill": 0.55, "life": tp + 0.05})
	u.shape({"kind": "blade", "a": side + Vector2(0, -2), "b": side + Vector2(0, -60), "w": 15.0, "col": COL_LIGHT, "glow": gold, "life": tp + 0.05, "grow": 0.12})
	u.shape({"kind": "circle", "c": side + Vector2(0, -68), "r": 9.0, "col": COL_LIGHT, "fill": 0.95, "life": tp + 0.05})
	u.shape({"kind": "blade", "a": side + Vector2(-5, -73), "b": side + Vector2(-11, -88), "w": 5.0, "col": COL_LIGHT, "glow": gold, "life": tp + 0.05})
	u.shape({"kind": "blade", "a": side + Vector2(5, -73), "b": side + Vector2(11, -88), "w": 5.0, "col": COL_LIGHT, "glow": gold, "life": tp + 0.05})
	u.shape({"kind": "line", "a": side + Vector2(6, -40) + d * 4.0, "b": side + Vector2(0, -40) + d * 46.0, "w": 2.5, "col": COL_LIGHT, "life": tp + 0.05})
	u.shape({"kind": "dots", "c": side + Vector2(0, -36), "r": 70.0, "n": 10, "col": gold, "life": tp})
	o.face_to(d.angle())
	var fe: float = 0.68 if rt == "hearth" else 0.8
	return {"org": o.pos, "side": side, "d": d, "hw": hw, "L": L, "bk": bk, "tp": tp, "stall": Bal.v("ult/su_stall", 0.3),
		"pf": 1.0 - fe - (0.12 if rt == "hearth" else 0.0), "ef": fe, "pseg": {}, "eseg": {}, "dashed": false, "boom": false,
		"seal": rt == "seal", "hearth": rt == "hearth", "ht": 0, "hseg": [{}, {}, {}]}


static func _su_step(u, a: Dictionary, o) -> bool:
	var g = u.g
	var t: float = a.t
	var org: Vector2 = a.org
	var d: Vector2 = a.d
	var hw: float = a.hw
	var L: float = a.L
	var tp: float = a.tp
	var bk: float = a.bk
	var col: Color = u._col(o)
	var gold: Color = col.lerp(Color.WHITE, 0.2)
	var hc: float = hw * _band_core()
	var tb: float = tp + float(a.stall)
	if t < tp:
		return false
	if not a.dashed:
		a.dashed = true
		var side: Vector2 = a.side
		var tip: Vector2 = org + d * L
		# 瞬身：一道白光贯穿，留下细长斩痕（停到炸开）
		u.shape({"kind": "blade", "a": side, "b": tip, "w": 26.0, "col": COL_LIGHT, "glow": gold, "grow": 0.04, "life": 0.14})
		u.shape({"kind": "line", "a": side, "b": tip, "w": 3.0, "col": COL_LIGHT, "life": float(a.stall) + 0.1})
		for j in 2:
			var lat: float = 14.0 * (1 if j == 0 else -1)
			u.shape({"kind": "line", "a": side + d.orthogonal() * lat, "b": tip + d.orthogonal() * lat, "w": 1.5, "col": gold, "life": float(a.stall) + 0.05})
		for k in 12:
			var p: Vector2 = side.lerp(tip, (k + 0.5) / 12.0)
			u.shape({"kind": "dots", "c": p, "r": 26.0, "n": 4, "col": COL_LIGHT, "life": 0.25, "delay": 0.01 * k})
		for e in _in_rect(u, org, d, -bk, L, hw):
			_once(u, a, o, a.pseg, e, float(a.pf), {"src": "瞬身", "stun": 0.3, "pre": true, "edge": absf(_loc(e.pos, org, d).y) > hc})
	if not a.boom and t >= tb:
		a.boom = true
		o.play_vis_anim("attack")
		o.screen_shake(0.7)
		# 斩痕爆裂：沿斩痕一串白光爆点 + 横贯带宽的交叉斩
		u.shape({"kind": "band", "a": org - d * bk, "b": org + d * L, "w": hw * 2.0, "col": COL_LIGHT, "fill": 0.2, "life": 0.3})
		var n: int = 10
		for k in n:
			var x: float = lerpf(30.0 - bk, L - 30.0, (k + 0.5) / n)
			var p: Vector2 = _w(org, d, x, 0.0)
			var dl: float = 0.012 * k
			u.shape({"kind": "circle", "c": p, "r": 90.0, "col": COL_LIGHT, "fill": 0.55, "life": 0.22, "delay": dl})
			_ring(u, p, 150.0, 30.0, gold, 0.3, 6.0, dl)
			var sg: float = 1.0 if k % 2 == 0 else -1.0
			var cd: Vector2 = d.orthogonal().rotated(0.45 * sg)
			u.shape({"kind": "blade", "a": p - cd * hw * 1.02, "b": p + cd * hw * 1.02, "w": 9.0, "col": COL_LIGHT, "glow": gold, "grow": 0.04, "life": 0.24, "delay": dl})
		u.shape({"kind": "line", "a": org + d * L, "b": org - d * bk, "w": 6.0, "col": gold, "life": 0.2, "delay": 0.15})   # 白光收回
		var st: float = Bal.v("ult/su_seal", 1.0) if a.seal else 0.0
		for e in _in_rect(u, org, d, -bk, L, hw):
			var opt := {"src": "斩痕", "edge": absf(_loc(e.pos, org, d).y) > hc}
			if st > 0.0:
				opt["stun"] = st * (0.5 if e.elite else 1.0)
			if _once(u, a, o, a.eseg, e, float(a.ef), opt) and not e.dead:
				g.enemies_sys.lite_slow(e, Bal.v("ult/su_slow", 0.4), Bal.v("ult/su_slow_t", 4.0))
	if a.hearth:   # 围炉：斩痕留 3 秒狐火（每秒 4%）
		while int(a.ht) < 3 and t >= tb + 1.0 * (int(a.ht) + 1):
			var i: int = int(a.ht)
			a.ht = i + 1
			for k in 8:
				var p: Vector2 = _w(org, d, lerpf(60.0 - bk, L - 60.0, (k + 0.5) / 8.0), hw * 0.4 * (1.0 if (k + i) % 2 == 0 else -1.0))
				u.shape({"kind": "dots", "c": p, "r": 60.0, "n": 7, "col": COL_AMBER, "life": 0.8})
			for e in _in_rect(u, org, d, -bk, L, hw):
				_once(u, a, o, a.hseg[i], e, 0.04, {"src": "狐火", "edge": absf(_loc(e.pos, org, d).y) > hc})
		return int(a.ht) >= 3
	return t >= tb + 0.25


# ================================================================ 逻各斯（§4.15）：面前长方形咒域 → 区域内敌人头顶咒文标记 → 一词念出、标记同时爆裂（处决 / 清矩形内弹幕）

## 用户 10-31「方形面积和边缘那一圈咒文都很奇怪」（开关 ult/lo_circ 缺省 1；0 = 原长方形咒域）：
## 判定与画面改成她面前一个圆（圆心在瞄准方向 ult/lo_off 处、半径 ult/lo_cr，按 ult_bench --area 定到标准面积 950 千平方像素 ±15%，docs/199 §5.10）；
## 不画边框 / 咒文带 / 分隔线；圆里一层淡墨、边缘几团墨渍；「删去」的墨线改成横贯圆的弦。处决 / 安魂 / 清弹 / 转喻 / 墓志铭照旧，只是改按圆判
static func _lo_circ() -> bool:
	return Bal.v("ult/lo_circ", 1.0) > 0.0


static func _lo_in(a: Dictionary, p: Vector2) -> bool:
	if a.get("circ", false):
		return p.distance_to(Vector2(a.cc)) <= float(a.cr)
	var l: Vector2 = _loc(p, a.org, a.d)
	return l.x >= -float(a.bk) and l.x <= float(a.L) and absf(l.y) <= float(a.hw)


static func _lo_targets(u, a: Dictionary) -> Array:
	if a.get("circ", false):
		return u.in_circle(Vector2(a.cc), float(a.cr))
	return _in_rect(u, a.org, a.d, -float(a.bk), float(a.L), float(a.hw))


static func _lo_start(u, o, d: Vector2) -> Dictionary:
	var rt := _route(o)
	var hw: float = Bal.v("ult/lo_w", 920.0) * 0.5
	var L: float = Bal.v("ult/lo_len", 900.0)
	var bk: float = Bal.v("ult/lo_back", 160.0)   # 咒域从队长身后 bk 起（10-30 对齐 §3.4：原 60）
	var org: Vector2 = o.pos
	var tm: float = Bal.v("ult/lo_mark", 0.5)
	var v4: bool = _lo_circ() and Bal.v("ult/lo_fx_v4", 1.0) > 0.0 and u.fx_ready(LO_GLYPH[0])   # 用户 10-31「咒文慢慢出现 → 一起真空压缩爆炸」
	if v4:
		tm = Bal.v("ult/lo_mark_v4", 1.2)   # 咒文慢慢浮现：结算推迟到 1.2 秒（份额不变）
		u.hush(tm + 0.5)   # 配乐压成寂静（时空暂停感）
	var col: Color = u._col(o)
	var p0: Vector2 = _w(org, d, -bk, -hw)
	var p1: Vector2 = _w(org, d, L, -hw)
	var p2: Vector2 = _w(org, d, L, hw)
	var p3: Vector2 = _w(org, d, -bk, hw)
	var v2: bool = _lo_v2(u)
	var v3: bool = v2 and Bal.v("ult/lo_fx_v3", 1.0) > 0.0   # 「删去」粗稿（§7.11）
	var vs: float = PF.vseed(u, org)
	var circ: bool = _lo_circ()
	var cc: Vector2 = org + d * Bal.v("ult/lo_off", 330.0)
	var cr: float = Bal.v("ult/lo_cr", 550.0)
	var a0 := {"circ": circ, "cc": cc, "cr": cr, "org": org, "d": d, "bk": bk, "L": L, "hw": hw}
	if circ and not v4:
		_lo_ink_area(u, cc, cr, tm, vs)
	if v4:
		u.shape({"kind": "nop", "c": org, "desat": 0.55, "din": 0.4, "dout": 0.6, "life": tm + 0.7})   # 慢慢褪色 = 时间停住
	# 咒域：矩形描边 + 底色 + 两条长边的咒文条（fx_logos_script 拼接）+ 横向分隔线
	if not circ:
		u.shape({"kind": "band", "a": org - d * bk, "b": org + d * L, "w": hw * 2.0, "col": COL_INK, "fill": 0.16, "life": tm + 0.1})
	if circ:
		pass
	elif v2:
		_lo_field_v2(u, [p0, p1, p2, p3], tm, vs)
	for pr in ([] if v2 or circ else [[p0, p1], [p1, p2], [p2, p3], [p3, p0]]):
		u.shape({"kind": "line", "a": pr[0], "b": pr[1], "w": 3.0, "col": col.lerp(Color.WHITE, 0.3), "life": tm + 0.1})
	if not v2 and not circ:
		u.tiles_line("fx_logos_script", p0 + d.orthogonal() * 14.0, p1 + d.orthogonal() * 14.0, {"loop": true, "life": tm + 0.1})
		u.tiles_line("fx_logos_script", p3 - d.orthogonal() * 14.0, p2 - d.orthogonal() * 14.0, {"loop": true, "life": tm + 0.1})
	for k in (0 if v3 or circ else 4):
		var x: float = lerpf(-bk, L, (k + 1) / 5.0)
		u.shape({"kind": "line", "a": _w(org, d, x, -hw), "b": _w(org, d, x, hw), "w": 1.5, "col": Color(col, 0.6), "life": tm, "delay": 0.05 * k})
	if v3 and not v4:
		_lo_erase_v3(u, org, d, hw, L, bk, tm, vs, a0)
	# 标记（头顶咒文，fx_logos_glyph 画入 0–3；同屏至多 ult/lo_mark_fx 个，伤害照打每一个）
	var marks: Array = []
	var cap: int = int(Bal.v("ult/lo_mark_fx", 40.0))
	for e in _lo_targets(u, a0):
		if marks.size() >= cap:
			break
		var mp: Vector2 = e.pos + Vector2(0, -float(e.get("r", 10.0)) - 20.0)
		if v4:   # 每只头顶一枚萨卡兹咒印，按离她远近错开 0–0.4 秒依次浮现、在 tm 内慢慢长到位
			var dl: float = 0.4 * clampf(e.pos.distance_to(org) / (cr * 2.0), 0.0, 1.0)
			marks.append({"e": e, "s": _lo_glyph(u, mp + Vector2(0, -10), 62.0, tm - dl, vs + marks.size() * 1.3, {"sc1d": (tm - dl) * 0.8, "fade": 0.05, "delay": dl, "col": Color(1.3, 1.2, 1.45, 1.0)})})
			continue
		marks.append({"e": e, "s": {"c": mp} if v3 else _lo_glyph(u, mp, 48.0, tm, vs + marks.size() * 1.3) if v2 else u.strip("fx_logos_glyph", mp, {"seg": [0, 3], "fps": 9.0, "life": tm, "sc": 1.2})})
	o.face_to(d.angle())
	return {"org": org, "d": d, "hw": hw, "L": L, "bk": bk, "tm": tm, "marks": marks, "seg": {}, "boom": false, "v2": v2, "v3": v3, "v4": v4, "vs": vs, "circ": circ, "cc": cc, "cr": cr,
		"mf": 0.9 if rt == "epitaph" else 1.0, "meto": rt == "metonymy", "epi": rt == "epitaph", "big": [], "bseg": {}, "mseg": {}}


static func _lo_step(u, a: Dictionary, o) -> bool:
	var g = u.g
	var t: float = a.t
	var org: Vector2 = a.org
	var d: Vector2 = a.d
	var hw: float = a.hw
	var L: float = a.L
	var bk: float = a.bk
	var col: Color = u._col(o)
	var hc: float = hw * _band_core()
	for mk in a.marks:
		if not mk.e.dead:
			mk.s.c = mk.e.pos + Vector2(0, -float(mk.e.get("r", 10.0)) - 20.0)
	if not a.boom and t >= float(a.tm):
		a.boom = true
		o.play_vis_anim("attack")
		o.screen_shake(0.6)
		if a.v4:
			_lo_implode_v4(u, a)
		elif a.circ:   # 句点：整片抹白一下（不爆）
			u.shape({"kind": "circle", "c": a.cc, "r": float(a.cr), "col": Color(0.8, 0.79, 0.76), "fill": 0.16, "life": 0.15})   # 预审：抹白别发白
		elif a.v3:
			u.shape({"kind": "band", "a": org - d * bk, "b": org + d * L, "w": hw * 2.0, "col": Color(0.96, 0.95, 0.9), "fill": 0.32, "life": 0.2})
		else:
			u.shape({"kind": "band", "a": org - d * bk, "b": org + d * L, "w": hw * 2.0, "col": col.lerp(Color.WHITE, 0.5), "fill": 0.22 if a.v2 else 0.35, "life": 0.25})
		if a.v2 and not a.v3 and not a.circ:
			_lo_boom_v2(u, a, org, d, hw, L, bk)
		for k in (0 if a.v2 or a.circ else 6):   # 一词念出：咒文从队长往矩形尽头横扫
			var x: float = lerpf(-bk, L, (k + 0.5) / 6.0)
			u.shape({"kind": "line", "a": _w(org, d, x, -hw), "b": _w(org, d, x, hw), "w": 5.0, "col": Color.WHITE, "life": 0.18, "delay": 0.02 * k})
		for mk in ([] if a.v2 else a.marks):
			var p: Vector2 = mk.s.c
			u.strip("fx_logos_glyph", p, {"seg": [3, 5], "fps": 14.0, "sc": 1.5})
		var thr: float = u.ref_hp() * Bal.v("ult/lo_exec", 2.0)
		var nexe := 0
		var nmeto := 0
		var ninks := 0
		for e in _lo_targets(u, a):
			var edge: bool = e.pos.distance_to(Vector2(a.cc)) > float(a.cr) * _core() if a.circ else absf(_loc(e.pos, org, d).y) > hc
			var frac: float = a.mf
			var exe: bool = _minion(e) and float(e.hp) < thr   # 处决按生命阈值，外缘也算（§3.3：和小怪档同一档）
			if exe:   # 处决：按她的生命直接补满（照亮的 1.25 折扣也补回）
				frac = maxf(frac, float(e.hp) / maxf(1.0, u.budget(e, edge) * u.build_mult(o)) * 1.3)
			var pos: Vector2 = e.pos
			_once(u, a, o, a.seg, e, frac, {"src": "处决" if exe else "咒文", "edge": edge})
			if e.dead and a.v3 and not a.v4 and ninks < 18:   # 被划掉的化墨迹散开
				ninks += 1
				PF.particles(u, pos, 60, "ult_burst_s", [Color(0.08, 0.08, 0.1), Color(0.2, 0.19, 0.22)], 0.0, float(a.vs) + ninks * 2.7, 55.0)
			if e.dead:
				if exe:
					nexe += 1
					if not a.v3:
						u.shape({"kind": "dots", "c": pos, "r": 22.0, "n": 6, "col": Color(0.25, 0.25, 0.3), "life": 0.5})   # 化灰
						u.shape({"kind": "line", "a": pos + Vector2(0, 8), "b": pos + Vector2(0, -46), "w": 3.0, "col": col.lerp(Color.WHITE, 0.6), "life": 0.16})
					if a.meto and nmeto < 10:   # 转喻：溢出伤害转给矩形外最近一名敌人
						var tg = _lo_outside(u, a, pos)
						if tg != null:
							nmeto += 1
							u.shape({"kind": "line", "a": pos, "b": tg.pos, "w": 2.0, "col": COL_INK.lerp(Color.WHITE, 0.4), "life": 0.15})
							_hit(u, a, o, tg, 0.25, {"src": "转喻", "edge": true})
					if a.epi and nexe % 5 == 0:   # 墓志铭：每处决 5 名留一枚大咒文，1 秒后爆开
						a.big.append({"p": pos, "t": t + 1.0})
						if a.v2:
							_lo_glyph(u, pos + Vector2(0, -10), 70.0, 1.0, float(a.vs) + nexe, {"sc1d": 1.0})
						else:
							u.strip("fx_logos_glyph", pos + Vector2(0, -10), {"seg": [0, 3], "fps": 4.0, "sc": 2.6, "life": 1.0})
			elif not e.boss:
				e["requiem"] = Bal.v("ult/lo_requiem", 8.0)   # 安魂（受到的法术伤害 +15%）
		for bl in g.ebullets:   # 只清矩形内的敌方弹幕
			if float(bl.get("life", 0.0)) <= 0.0:
				continue
			if _lo_in(a, bl.pos):
				bl.life = 0.0
	for b in a.big:
		if not b.get("done", false) and t >= float(b.t):
			b["done"] = true
			_ring(u, b.p, 100.0, 20.0, col.lerp(Color.WHITE, 0.4), 0.3, 6.0)
			u.shape({"kind": "circle", "c": b.p, "r": 100.0, "col": COL_INK, "fill": 0.4, "life": 0.2})
			for e in u.in_circle(b.p, 100.0):
				_once(u, a, o, a.bseg, e, 0.1, {"src": "墓志铭"})
	var tend: float = float(a.tm) + 0.15
	for b in a.big:
		tend = maxf(tend, float(b.t) + 0.05)
	return a.boom and t >= tend


## ---- 逻各斯 pixfx（docs/199 §7.10，开关 ult/lo_fx_v2 缺省 1；0 = 细线描边 + 咒文拼接 + 旧标记版）
## 审阅 10-30「连续边框加萨卡兹字样的符文带，不要火柴人」：边框 = fx_lo_rune（三条符文带横向拼成一张、按周长接着截）沿矩形四边连续铺一整圈，
## 从队长身后一角起依次显现（像被写出来）；四角各一枚大咒印 fx_lo_glyph1–4 慢转；敌人头顶标记 = 萨卡兹字咒印（同一组，按序号挑字）从小长到位；
## 一词念出 = 一道横跨咒域的符文带从队长扫到尽头 + 各标记扫到时放大闪亮、碎成紫色像素粒子。判定 / 时序 / u.hit / 清弹不动
const LO_RUNE := "fx_lo_rune"
const LO_GLYPH := ["fx_lo_glyph1", "fx_lo_glyph2", "fx_lo_glyph3", "fx_lo_glyph4"]
const LO_VIO := Color(0.72, 0.62, 1.0)


static func _lo_v2(u) -> bool:
	return Bal.v("ult/lo_fx_v2", 1.0) > 0.0 and u.fx_ready(LO_RUNE) and u.fx_ready(LO_GLYPH[0])


## 一枚咒印：w = 世界宽；从 0.5 倍在 opt.sc1d 秒内长到位；opt.spin 时画在地面层慢转
static func _lo_glyph(u, p: Vector2, w: float, life: float, sd: float, opt := {}) -> Dictionary:
	var name := PF.pick(u, LO_GLYPH, sd * 0.43)
	var sc: float = w / PF.tex_w(u, name)
	var s := {"sc": sc * 0.5, "sc1": sc, "scd": float(opt.get("sc1d", 0.12)), "life": life, "fade": float(opt.get("fade", 0.08)),
		"sx": -1.0 if PF.h(sd + 1.0) < 0.3 else 1.0, "col": opt.get("col", Color(1, 1, 1, 0.95)), "delay": float(opt.get("delay", 0.0))}
	if opt.has("spin"):
		s["spin"] = opt.spin
		s["layer"] = "back"
	return u.strip(name, p, s)


## 符文带一段：从 p 沿 dir 铺 len（截 fx_lo_rune 的一段，ux 起点 ux0）
static func _lo_band(u, p: Vector2, dir: Vector2, len: float, ux0: float, opt: Dictionary) -> Dictionary:
	var t: Texture2D = u._strip_tex(LO_RUNE)
	var kk: float = PF.tex_w(u, LO_RUNE) / t.get_width()
	var sc: float = float(opt.get("sc", 1.0))
	var uw: float = minf(t.get_width() - 1.0, len / (kk * sc))
	var s := {"layer": str(opt.get("layer", "back")), "ang": dir.angle(), "sc": sc, "o": Vector2(0.0, t.get_height() * 0.5),
		"ux": fposmod(ux0, maxf(1.0, t.get_width() - uw)), "uw": uw, "life": float(opt.life), "fade": float(opt.get("fade", 0.1)),
		"col": opt.get("col", Color.WHITE), "delay": float(opt.get("delay", 0.0))}
	for k in ["rev", "rev0", "v"]:
		if opt.has(k):
			s[k] = opt[k]
	return u.strip(LO_RUNE, p, s)


## 咒域边框：四边连续符文带（每段接着上一段的截取位置），从 p0（身后一角）起按周长依次写出；四角大咒印慢转
static func _lo_field_v2(u, ps: Array, tm: float, vs: float) -> void:
	var t: Texture2D = u._strip_tex(LO_RUNE)
	var kk: float = PF.tex_w(u, LO_RUNE) / t.get_width()
	var per: float = 0.0
	for i in 4:
		per += (ps[i] as Vector2).distance_to(ps[(i + 1) % 4])
	var ux: float = floorf(PF.h(vs) * t.get_width())
	var acc := 0.0
	var wt: float = minf(0.3, tm * 0.6)   # 写满一圈的时间
	for i in 4:
		var a0: Vector2 = ps[i]
		var b0: Vector2 = ps[(i + 1) % 4]
		var ln: float = a0.distance_to(b0)
		var dv: Vector2 = (b0 - a0) / ln
		var n: int = maxi(1, ceili(ln / 300.0))   # 每段 ≤ 300（贴图截段不超宽）
		for q in n:
			var l0: float = ln * q / n
			var l1: float = ln * (q + 1) / n
			_lo_band(u, a0 + dv * l0, dv, l1 - l0, ux, {"sc": 0.75, "life": tm + 0.12, "fade": 0.12, "rev": wt * (l1 - l0) / per, "delay": wt * (acc + l0) / per,
				"col": Color(1.0, 1.0, 1.0, 0.92)})
			ux += (l1 - l0) / (kk * 0.75)
		acc += ln
	for i in 4:
		_lo_glyph(u, ps[i], 64.0, tm + 0.12, vs + i * 2.9, {"spin": 1.2 * (1.0 if i % 2 == 0 else -1.0), "sc1d": 0.2, "delay": wt * 0.25 * i, "col": Color(1, 1, 1, 0.9)})


## 一词念出：一道横跨咒域的符文带从身后扫到尽头（0.16 秒）+ 各标记扫到时放大闪亮、碎成紫色像素粒子 + 冷紫短灯
static func _lo_boom_v2(u, a: Dictionary, org: Vector2, d: Vector2, hw: float, L: float, bk: float) -> void:
	var n: Vector2 = d.orthogonal()
	var sw: float = 0.16
	var spd: float = (L + bk) / sw
	for l in 2:
		_lo_band(u, org - d * (bk - 20.0 * l) - n * hw, n, hw * 2.0, PF.h(float(a.vs) + l) * 900.0,
			{"layer": "front", "sc": 1.0 - 0.25 * l, "life": sw, "fade": 0.05, "v": d * spd, "col": Color(1.1, 1.1, 1.15, 1.0 - 0.4 * l), "delay": 0.02 * l})
	u.light(org + d * (L * 0.5), maxf(L, hw) * 0.8, LO_VIO, 0.25)
	var i := 0
	for mk in a.marks:
		var p: Vector2 = mk.s.c
		var dl: float = clampf(_loc(p, org, d).x + bk, 0.0, L + bk) / spd   # 符文带扫到才炸
		_lo_glyph(u, p, 56.0, 0.18, float(a.vs) + i * 1.3, {"sc1d": 0.08, "fade": 0.12, "delay": dl, "col": Color(1.2, 1.15, 1.25)})
		if i % 2 == 0 and i < 20:   # 碎成紫色粒子：隔一个放、至多 10 团，聚怪处不堆成一片
			PF.particles(u, p, 60, "ult_burst_s", [LO_VIO, Color(0.5, 0.42, 0.9)], dl + 0.05, float(a.vs) + i * 3.0, 50.0)
		u.shapes.erase(mk.s)
		i += 1


## ---- 逻各斯「删去」粗稿（docs/199 §7.11，开关 ult/lo_fx_v3 缺省 1；0 = §7.10 符文咒域版）。用户 10-30：「做个大概的给我看看」
## 画面褪成墨色（全屏去色 0.85，ult.gd desat 图形）像一页手稿 → 空中一行萨卡兹字逐字写出（截 fx_lo_rune 单字，每字 0.07 秒）→
## 每写完一字，咒域里对应一段被一笔墨线横向划掉（fx_ir_slash 染墨黑）→ 0.5 秒（原结算时刻）落「句点」：整片抹白一下、被划掉的敌人化墨迹散开、
## 颜色 0.8 秒内慢慢回来。安静克制、不爆。时序沿用原判定（0.5 秒一次结算），逐字逐段结算要改判定，列给协调人
const LO_INK := Color(0.07, 0.07, 0.09)


static func _lo_erase_v3(u, org: Vector2, d: Vector2, hw: float, L: float, bk: float, tm: float, vs: float, ar := {}) -> void:
	var circ: bool = ar.get("circ", false)
	u.shape({"kind": "nop", "c": org, "desat": 0.85, "din": 0.12, "dout": 0.8, "life": tm + 0.95})
	var n := 6
	var t: Texture2D = u._strip_tex(LO_RUNE)
	var lw: float = t.get_width() / 66.0   # fx_lo_rune 三条 × 22 字，一字宽
	var sc := 0.85
	var kk: float = PF.tex_w(u, LO_RUNE) / t.get_width() * sc
	var w0: Vector2 = org + d * 160.0 + Vector2(-lw * kk * n * 0.5, -240.0)   # 一行字：她前上方（避开本体），屏幕横排
	for k in n:
		var tk: float = 0.04 + 0.07 * k
		var li: int = int(PF.h(vs * 0.3 + k * 7.1) * 66.0) % 66
		u.strip(LO_RUNE, w0 + Vector2(lw * kk * k, 0.0), {"sc": sc, "o": Vector2(0.0, t.get_height() * 0.5), "ux": li * lw, "uw": lw,
			"rev": 0.06, "rev0": 0.0, "delay": tk, "life": tm + 0.35 - tk, "fade": 0.3, "col": Color(1.2, 1.15, 1.25)})
		# 写完这一字：咒域第 k 段被一笔墨线划掉（横跨整个宽度，略斜、按哈希错开）
		var x: float = lerpf(-bk, L, (k + 0.5) / n) + (PF.h(vs + k * 3.3) - 0.5) * 60.0
		var j: float = (PF.h(vs + k * 5.9) - 0.5) * 120.0
		var a0: Vector2 = _w(org, d, x + j, -hw * 0.96)
		var a1: Vector2 = _w(org, d, x - j, hw * 0.96)
		if circ:   # 圆：沿瞄准方向排 6 道横贯圆的弦（长短跟着圆、略斜）
			var cr: float = ar.cr
			var y: float = lerpf(-cr * 0.85, cr * 0.85, (k + 0.5) / n) + (PF.h(vs + k * 3.3) - 0.5) * 40.0
			var hl: float = sqrt(maxf(0.0, cr * cr - y * y)) * 0.92
			var cc: Vector2 = ar.cc
			a0 = cc + d * y + d.orthogonal() * (-hl) + d * j * 0.4
			a1 = cc + d * y + d.orthogonal() * hl - d * j * 0.4
		var nm := PF.pick(u, IR_SLASH, vs * 0.2 + k * 1.9)
		var st: Texture2D = u._strip_tex(nm)
		var sx: float = a0.distance_to(a1) / PF.tex_w(u, nm)
		u.strip(nm, a0, {"ang": (a1 - a0).angle(), "o": Vector2(0.0, st.get_height() * 0.5), "sx": sx, "sy": 0.9 * (1.0 if k % 2 == 0 else -1.0),
			"rev": 0.08, "rev0": 0.0, "delay": tk + 0.06, "life": tm + 0.3 - tk, "fade": 0.25, "col": LO_INK})
	# 句点：一行字末尾一个墨点，0.5 秒落下
	u.shape({"kind": "circle", "c": w0 + Vector2(lw * kk * (n + 0.4), 10.0), "r": 9.0, "col": Color(0.95, 0.93, 0.88), "fill": 0.95, "delay": tm - 0.02, "life": 0.4})


## 圆形咒域的底：一层淡墨（地面层）+ 边缘 7 团大小不一的墨渍（粒子帧条着墨色），不画边线
static func _lo_ink_area(u, cc: Vector2, cr: float, tm: float, vs: float) -> void:
	u.shape({"kind": "circle", "c": cc, "r": cr, "col": Color(0.04, 0.04, 0.06), "fill": 0.22, "life": tm + 0.6, "layer": "back"})
	for q in 7:
		var hh: float = PF.h(vs + q * 3.7)
		var pq: Vector2 = cc + Vector2.from_angle(TAU * (q + hh) / 7.0) * cr * (0.85 + 0.12 * hh)
		PF.particles(u, pq, 60, "ult_burst_s", [Color(0.06, 0.06, 0.08), Color(0.16, 0.15, 0.18)], 0.03 * q, vs + q * 5.0, 50.0 + 50.0 * hh)


## 真空压缩爆炸：所有咒印同时往里一缩（0.1 秒缩到一个亮点，四周光尘往里吸）→ 再同时炸开（紫白像素粒子 + 冷紫小灯 + 一圈暗紫碎环）；不整屏白闪
static func _lo_implode_v4(u, a: Dictionary) -> void:
	var i := 0
	for mk in a.marks:
		var s: Dictionary = mk.s
		var p: Vector2 = s.c
		if not s.is_empty():
			s.age = 0.0
			s.max = 0.1
			s["sc"] = float(s.get("sc1", s.get("sc", 1.0)))
			s["sc1"] = float(s.sc) * 0.12
			s["scd"] = 0.1
			s.erase("delay")
		if i < 30:
			u.grain("mote_in", p, Vector2.ZERO, LO_VIO, 3)
			PF.particles(u, p, 60, "ult_burst_s", [LO_VIO, Color(0.85, 0.8, 1.0)], 0.1, float(a.vs) + i * 3.0, 55.0)
			u.shape({"kind": "ring", "c": p, "r": 46.0, "r1": 6.0, "w": 3.0, "col": Color(0.5, 0.42, 0.85), "life": 0.3, "delay": 0.1})
			if i % 3 == 0:   # 余韵：慢慢飘落的暗紫余烬
				PF.particles(u, p, 40, "ult_ember", [Color(0.42, 0.36, 0.7)], 0.25, float(a.vs) + i * 5.0, 45.0)
		i += 1
	u.light(Vector2(a.cc), float(a.cr), LO_VIO, 0.3)
	var sfx: Node = u.g.get_node_or_null("/root/Sfx") if u.g.is_inside_tree() else null
	if sfx != null:
		sfx.play("boom", -4.0, 0.7)


static func _lo_outside(u, a: Dictionary, p: Vector2):
	var best = null
	var bd := 400.0 * 400.0
	for e in u.in_circle(p, 400.0):
		if _lo_in(a, e.pos):
			continue
		var d2: float = e.pos.distance_squared_to(p)
		if d2 < bd:
			bd = d2
			best = e
	return best


# ================================================================ 星熊（§4.16）：盾「般若」砸地 → 全场嘲讽 + 吸怪到盾前 → 挡 1.5 秒（盾面发红、裂纹扩大）→ 盾甲反震炸开

static func _ho_start(u, o) -> Dictionary:
	var rt := _route(o)
	var g = u.g
	var c: Vector2 = o.pos
	var R: float = Bal.v("ult/ho_r", 502.0)
	var pr: float = Bal.v("ult/ho_pull_r", 438.0)
	var hold: float = Bal.v("ult/ho_hold", 1.5)
	var col: Color = u._col(o)
	o.play_vis_anim("attack")
	o.screen_shake(0.6)
	u.strip("fx_hoshiguma_block", c + Vector2(0, -14), {"sc": 3.0, "life": 0.3})
	_hex(u, c, 110.0, 0.0, col, 5.0, hold + 0.1)
	_hex(u, c, 70.0, PI / 6.0, col.lerp(Color.WHITE, 0.4), 3.0, hold + 0.1)
	_ring(u, c, pr, 120.0, Color(col, 0.6), 0.35, 3.0)
	# 吸怪：半径 pr 内小怪吸到盾前（距她 ~100），精英吸近一截
	var n := 0
	for e in u.in_circle(c, pr):
		if e.boss:
			continue
		var dv: Vector2 = c - e.pos
		var dist: float = dv.length()
		if dist < 1.0:
			continue
		var pull: float = maxf(0.0, dist - 100.0) if _minion(e) else maxf(0.0, dist - 150.0)
		g.enemies_sys.apply_kb(e, dv / dist * _kb_v(pull))
		if n < 36 and pull > 60.0:
			n += 1
			u.shape({"kind": "line", "a": e.pos, "b": e.pos + dv / dist * minf(pull, 120.0), "w": 2.0, "col": col.lerp(Color.WHITE, 0.3), "life": 0.2, "v": dv / dist * 500.0})
	var hv2: bool = _ho_v2(u)
	if hv2:   # 盾砸地：顿帧 + 盾下地面碎裂（fx_hs_crack 整张，压出来）+ 碎石掀起 + 灰尘粒子
		u.g.vfx.stop(Bal.v("ult/ho_hitstop", 0.1), "ult", true)
		var vs0: float = PF.vseed(u, c)
		u.strip("fx_hs_crack", c, {"layer": "back", "sc": 0.35, "sc1": 0.55, "scd": 0.1, "ang": PF.h(vs0) * TAU, "sx": -1.0 if PF.h(vs0 + 1.0) < 0.5 else 1.0,
			"life": hold + 1.4, "fade": 0.6, "col": Color(1.1, 1.08, 1.05), "col1": Color(0.6, 0.58, 0.56), "cold": hold + 0.6})
		PF.heave(u, c, 120.0, vs0 + 3.0)
		PF.particles(u, c, 100, "ult_burst_s", [Color(0.85, 0.82, 0.76)], 0.0, vs0, 140.0)
	return {"v2": hv2, "c": c, "R": R, "rc": R * Bal.v("ult/ho_core", 0.872), "hold": hold, "tick": 0, "tseg": [{}, {}, {}, {}, {}], "rseg": {}, "boom": -1.0,
		"rf": 0.78 if rt == "ember" else Bal.v("ult/ho_boom", 0.9), "wall": rt == "wall", "ember": rt == "ember", "et": 0, "eseg": [{}, {}, {}],
		"glow": u.strip("fx_hoshiguma_guard_glow", c + Vector2(0, -16), {"sc": 2.2, "loop": true, "life": hold})}


static func _ho_step(u, a: Dictionary, o) -> bool:
	var g = u.g
	var t: float = a.t
	var c: Vector2 = a.c
	var R: float = a.R
	var hold: float = a.hold
	var col: Color = u._col(o)
	var rc: float = a.rc
	if t < hold:
		g.invuln = maxf(g.invuln, 0.2)   # 挡的期间队长无敌
		for e in u.in_view(c):   # 全场嘲讽
			if not e.boss:
				g.enemies_sys.set_aggro(e, c)
		var k: float = t / hold
		a.glow.col = Color.WHITE.lerp(COL_RED, k)
		while int(a.tick) < 5 and t >= 0.3 * (int(a.tick) + 1) - 0.01:
			var i: int = int(a.tick)
			a.tick = i + 1
			for e in u.in_circle(c, R):
				_once(u, a, o, a.tseg[i], e, 0.02, {"src": "格挡", "pre": true, "edge": e.pos.distance_to(c) > rc})
			if a.v2:   # 裂纹扩大：每跳地面碎裂再撑大一圈 + 一下震 + 碎石（v2 不画程序线段裂纹）
				var vs1: float = PF.vseed(u, c) + i
				u.strip("fx_hs_crack", c, {"layer": "back", "sc": 0.55 + 0.12 * i, "sc1": 0.6 + 0.12 * (i + 1), "scd": 0.08, "ang": PF.h(vs1) * TAU,
					"life": hold - t + 1.2, "fade": 0.6, "col": Color(0.95, 0.9, 0.88, 0.8), "col1": Color(0.55, 0.52, 0.5, 0.8), "cold": 0.5})
				u.shake(2.0 + i, 0.12)
				PF.heave(u, c, 130.0 + 40.0 * i, vs1 + 7.0)
			for j in (0 if a.v2 else 3 + i):
				var ang: float = j * 2.39996 + i * 0.7
				var dv := Vector2.from_angle(ang)
				u.shape({"kind": "line", "a": c + dv * 60.0, "b": c + dv * (90.0 + 40.0 * i), "w": 3.0, "col": col.lerp(COL_RED, k), "life": hold - t + 0.15})
			_hex(u, c, 110.0, 0.0, col.lerp(COL_RED, k), 6.0, 0.12)
			o.sparks(c + Vector2(0, -16), Vector2.UP, COL_RED.lerp(col, 0.5), 6, 260.0)
		return false
	if float(a.boom) < 0.0:
		a.boom = t
		o.play_vis_anim("attack")
		o.screen_shake(1.0)
		u.shapes.erase(a.glow)
		if a.v2:   # 反震：顿帧 + 石尘冲击环（fx_hs_ring）推到 R + 灰白粒子迸开 + 四拍往外震（节奏同乌尔比安四圈）
			u.g.vfx.stop(Bal.v("ult/ho_hitstop", 0.1), "ult", true)
			var vs2: float = PF.vseed(u, c) + 50.0
			PF.ring(u, ["fx_hs_ring"], c, 110.0, R * 1.02, 0.16, 0.45, {"seed": vs2, "fade": 0.3, "col": Color(1.05, 1.0, 0.98, 0.85)})
			PF.particles(u, c, 300, "ult_burst", [Color(0.95, 0.9, 0.85), Color(1.0, 0.55, 0.45)], 0.0, vs2, R * 0.8)
			a["vs"] = vs2
			a["beats"] = [[t, R * 0.3, 0], [t + 0.18, R * 0.55, 1], [t + 0.36, R * 0.8, 2], [t + 0.54, R, 3]]
			PF.aftershock(u, c, R, vs2 + 9.0, 0.84, 10)
		else:
			u.shape({"kind": "circle", "c": c, "r": R, "col": COL_RED.lerp(col, 0.5), "fill": 0.3, "life": 0.22})
			_ring(u, c, R, 80.0, col.lerp(Color.WHITE, 0.3), 0.45, 14.0)
		for j in (0 if a.v2 else 18):   # 盾甲碎片往外飞
			var dv := Vector2.from_angle(j * TAU / 18.0 + 0.17)
			u.shape({"kind": "blade", "a": c + dv * 90.0, "b": c + dv * 130.0, "w": 7.0, "col": Color(1.0, 0.9, 0.7), "glow": COL_RED, "life": 0.4, "v": dv * 900.0})
	if a.v2:
		PF.beats_tick(u, a, t, c, Color(1.0, 0.85, 0.8))
	var el: float = t - float(a.boom)
	var T: float = 0.14
	if el <= T + 0.1:   # 反震：两层六边形从盾前扩到 R（逐帧描，形状一眼是盾阵）
		var r: float = lerpf(110.0, R, clampf(el / T, 0.0, 1.0))
		_hex(u, c, r, 0.0, col.lerp(Color.WHITE, 0.4), 10.0, 0.06)
		_hex(u, c, r * 0.8, PI / 6.0, COL_RED.lerp(col, 0.4), 6.0, 0.06)
		for e in u.in_circle(c, r + 20.0):
			if a.rseg.has(int(e.id)):
				continue
			var op: Dictionary = {"src": "反震", "edge": e.pos.distance_to(c) > rc}
			if e.pos.distance_to(c) > 1.0:
				op["kb"] = (e.pos - c).normalized() * _kb_v(Bal.v("ult/ho_kb", 300.0))
			if a.wall:
				op["stun"] = 1.0 if _minion(e) else 0.5
			_once(u, a, o, a.rseg, e, float(a.rf), op)
	if a.ember:   # 热砂·余烬：反震圈留热砂，每 0.6 秒 4%（3 跳）
		while int(a.et) < 3 and el >= 0.6 * (int(a.et) + 1):
			var i: int = int(a.et)
			a.et = i + 1
			u.shape({"kind": "circle", "c": c, "r": R, "col": Color(1.0, 0.5, 0.2), "fill": 0.12, "life": 0.6})
			u.shape({"kind": "dots", "c": c, "r": R * 0.95, "n": 30, "col": Color(1.0, 0.6, 0.25), "life": 0.6})
			for e in u.in_circle(c, R):
				_once(u, a, o, a.eseg[i], e, 0.04, {"src": "热砂", "edge": e.pos.distance_to(c) > rc})
		return int(a.et) >= 3
	return el >= T + 0.12


## 星熊 v2（ult/ho_fx_v2，缺省 1；pixfx，docs/199 §7.8 第一批）：盾砸地顿帧 + 盾下地面碎裂整张（fx_hs_crack），格挡每跳裂开一圈；
## 反震顿帧 + 石尘冲击环（fx_hs_ring）+ 粒子 + 四拍隆起；盾阵六边形照旧（形状一眼是盾阵）。灰黑断裂，不用凯尔希的红缝
static func _ho_v2(u) -> bool:
	return Bal.v("ult/ho_fx_v2", 1.0) > 0.0 and u.fx_ready("fx_hs_crack") and u.fx_ready("fx_hs_ring")


# ================================================================ 推进之王（§4.17）：高高跃起 → 0.6 秒后巨锤砸落点 → 冲击波横扫、碎石飞溅、敌人震上半空 0.8 秒后落地

static func _sg_start(u, o, aim: Vector2, d: Vector2) -> Dictionary:
	var rt := _route(o)
	var c: Vector2 = aim if aim != Vector2.INF else o.pos + d * 260.0
	var T: float = Bal.v("ult/sg_air", 0.6)
	var R: float = Bal.v("ult/sg_r", 540.0) * (450.0 / 480.0 if rt == "leap" else 1.0)
	var col: Color = u._col(o)
	# 起跳尘 + 落点预兆（影子在落点由大缩小、越来越深）
	_ring(u, o.pos, 110.0, 30.0, COL_ROCK.lerp(Color.WHITE, 0.3), 0.3, 5.0)
	u.shape({"kind": "dots", "c": o.pos, "r": 80.0, "n": 10, "col": COL_ROCK, "life": 0.35})
	_ring(u, c, 50.0, R, Color(col, 0.7), T, 3.0)
	o.play_vis_anim("attack")
	return {"p0": o.pos, "c": c, "T": T, "R": R, "H": Bal.v("ult/sg_h", 170.0), "landed": false, "mseg": {}, "fseg": {}, "air": [], "still": [],
		"fall": false, "sp": 0.4 if rt == "cmd" else Bal.v("ult/sg_sp", 0.25), "cmd": rt == "cmd", "leap": rt == "leap",
		"l2": {}, "l2seg": {}, "prev": o.pos}


static func _sg_smash(u, a: Dictionary, o, c: Vector2, R: float, frac: float, seg: Dictionary, big: bool) -> void:
	var col: Color = u._col(o)
	var rc: float = R * _core()
	o.play_vis_anim("attack")
	o.screen_shake(1.0 if big else 0.6)
	u.shape({"kind": "circle", "c": c, "r": 100.0, "col": Color.WHITE, "fill": 0.9, "life": 0.1})
	var v2: bool = big and _sg_v2(u)
	if v2:
		_sg_smash_v2(u, c, R)
	else:
		u.shape({"kind": "circle", "c": c, "r": R, "col": COL_ROCK, "fill": 0.22, "life": 0.3})
		_ring(u, c, R, 60.0, col.lerp(Color.WHITE, 0.3), 0.4, 16.0 if big else 10.0)
		_ring(u, c, R * 0.7, 40.0, COL_ROCK.lerp(col, 0.5), 0.35, 8.0, 0.04)
	var nc: int = 0 if v2 else (14 if big else 8)
	for j in nc:   # 放射裂地
		var dv := Vector2.from_angle(j * TAU / nc + 0.2)
		var ln: float = R * (0.55 + 0.4 * float((j * 5) % 4) / 3.0)
		u.shape({"kind": "line", "a": c + dv * 40.0, "b": c + dv * ln, "w": 5.0, "col": COL_ROCK.lerp(Color(0.2, 0.15, 0.1), 0.4), "life": 0.9})
	# 碎石飞溅（fx_rock_burst）+ 一圈岩刺（fx_siege_rock_spike）由内往外冒
	var rings: Array = [[R * 0.3, 6], [R * 0.58, 9], [R * 0.85, 13]] if big else [[R * 0.5, 6]]
	for ri in rings.size():
		var rr: float = rings[ri][0]
		var nn: int = rings[ri][1]
		for j in nn:
			var p: Vector2 = c + Vector2.from_angle(TAU * (j + 0.5 * (ri % 2)) / nn + 0.3 * ri) * rr
			if v2:   # v2 不画黄色岩刺 / fx_rock_burst（用户 10-30 不喜欢那团黄色烟尘），碎石交给隆起
				continue
			if j % 2 == 0:
				u.strip("fx_siege_rock_spike", p, {"o": Vector2(16, 54), "sc": 1.5, "delay": 0.05 * ri})
			else:
				u.strip("fx_rock_burst", p, {"sc": 1.6, "delay": 0.05 * ri})
	for j in (0 if v2 else 16):   # 碎石块往外飞
		var dv := Vector2.from_angle(j * 2.39996)
		u.shape({"kind": "blade", "a": c + dv * 50.0, "b": c + dv * 64.0, "w": 6.0, "col": COL_ROCK.lerp(Color.WHITE, 0.2), "glow": COL_ROCK, "life": 0.45, "v": dv * (500.0 + 120.0 * float(j % 3))})
	for e in u.in_circle(c, R):
		if seg.has(int(e.id)):
			continue
		var edge: bool = e.pos.distance_to(c) > rc
		e["_sg_edge"] = edge
		_once(u, a, o, seg, e, frac, {"src": "砸地", "edge": edge})
		if e.boss and big:
			a.still.append(e)   # Boss 不浮空，落地那一份照样记（不然 Boss 只吃到 75%）
		elif not e.dead:
			_launch(u, a, e, Bal.v("ult/sg_lift", 0.8), 70.0)


static func _sg_step(u, a: Dictionary, o) -> bool:
	var g = u.g
	var t: float = a.t
	var T: float = a.T
	var c: Vector2 = a.c
	var col: Color = u._col(o)
	_air_tick(u, a)
	if t < T:   # 跃空：沿抛物线过去（画面抬高 H），影子留在地上
		var k: float = t / T
		var gp: Vector2 = Vector2(a.p0).lerp(c, k)
		var p: Vector2 = gp + Vector2(0, -sin(k * PI) * float(a.H))
		_lead_move(u, o, p)
		u.shape({"kind": "circle", "c": gp, "r": 22.0 - 8.0 * sin(k * PI), "col": Color(0.05, 0.04, 0.03), "fill": 0.5, "life": 0.04})
		u.shape({"kind": "circle", "c": c, "r": lerpf(30.0, 70.0, k), "col": Color(0.05, 0.04, 0.03), "fill": 0.35 * k, "life": 0.04})
		u.shape({"kind": "line", "a": a.prev, "b": p, "w": 6.0, "col": col.lerp(Color.WHITE, 0.3), "life": 0.2})
		if _sg_v2(u):   # 落点一大片地面跟着渐暗（压暗，砸下那一刻撤掉）
			u.shape({"kind": "circle", "c": c, "r": float(a.R) * 1.05, "col": Color(0.0, 0.0, 0.01), "fill": 0.5 * k * k, "life": 0.04, "layer": "back"})
		a.prev = p
		return false
	if not a.landed:
		a.landed = true
		_lead_move(u, o, c)
		_lead_land(u, o)
		_sg_smash(u, a, o, c, float(a.R), Bal.v("ult/sg_smash", 0.75), a.mseg, true)
		if _sg_v2(u):   # 节奏：一拍一圈往外震（对齐乌尔比安四圈，间隔 0.18）
			var Rr: float = float(a.R)
			a["vs"] = PF.vseed(u, c)
			a["beats"] = [[t, Rr * 0.3, 0], [t + 0.18, Rr * 0.55, 1], [t + 0.36, Rr * 0.8, 2], [t + 0.54, Rr * 1.0, 3]]
		_team_sp(u, o, float(a.sp))
		if a.cmd:   # 万兽之王：金色号令波
			_ring(u, c, 620.0, 100.0, Color(1.0, 0.85, 0.3), 0.6, 6.0, 0.1)
			_ring(u, c, 520.0, 80.0, Color(1.0, 0.95, 0.6), 0.5, 3.0, 0.18)
		if a.leap:
			var nx: Vector2 = u._densest(c, 420.0, 220.0)
			a.l2 = {"from": c, "to": nx if nx != Vector2.INF and nx.distance_to(c) > 120.0 else c + (c - Vector2(a.p0)).normalized() * 260.0, "t0": t + 0.25, "dur": 0.3, "done": false}
	PF.beats_tick(u, a, t, c, Color(0.95, 0.9, 0.8))
	var lt: float = T
	if not a.fall and t >= lt + Bal.v("ult/sg_lift", 0.8):
		a.fall = true   # 震上半空的落地：25%
		var n := 0
		for ar in a.air:
			var e: Dictionary = ar.e
			if e.dead or not a.mseg.has(int(e.id)):
				continue
			_once(u, a, o, a.fseg, e, Bal.v("ult/sg_fall", 0.25), {"src": "落地", "edge": bool(e.get("_sg_edge", false))})
			if n < 30:
				n += 1
				u.shape({"kind": "dots", "c": ar.e.pos, "r": 20.0, "n": 5, "col": COL_ROCK, "life": 0.3})
		for e in a.still:
			if not e.dead:
				_once(u, a, o, a.fseg, e, Bal.v("ult/sg_fall", 0.25), {"src": "落地", "edge": bool(e.get("_sg_edge", false))})
		_air_end(u, a)
	var l2: Dictionary = a.l2
	if not l2.is_empty() and not l2.done and t >= float(l2.t0):
		var k2: float = clampf((t - float(l2.t0)) / float(l2.dur), 0.0, 1.0)
		var gp2: Vector2 = Vector2(l2.from).lerp(l2.to, k2)
		_lead_move(u, o, gp2 + Vector2(0, -sin(k2 * PI) * 90.0))
		if k2 >= 1.0:
			l2.done = true
			_lead_land(u, o)
			for e in u.in_circle(l2.to, 220.0):   # 再跃：砸到的只算主体没打到的
				if a.mseg.has(int(e.id)):
					a.l2seg[int(e.id)] = true
			_sg_smash(u, a, o, l2.to, 220.0, 0.75, a.l2seg, false)
	var tend: float = lt + Bal.v("ult/sg_lift", 0.8) + 0.05
	if not l2.is_empty():
		tend = maxf(tend, float(l2.t0) + float(l2.dur) + 0.1)
	if a.fall and t >= tend and (l2.is_empty() or l2.done):
		_air_end(u, a)
		return true
	return false


# ================================================================ 艾丽妮（§4.18）：前方 170° 扇形狂风卷起浮空 → 化风冲进去连斩 → 瞬身回原地 → 手炮朝风眼一枪收尾

static func _ir_start(u, o, d: Vector2) -> Dictionary:
	var rt := _route(o)
	var half: float = deg_to_rad(90.0 if rt == "gale" else 85.0)
	var R: float = Bal.v("ult/ir_r", 860.0) * (sqrt(85.0 / 90.0) if rt == "gale" else 1.0)   # 狂飙：角度放宽、半径按等面积收
	var n: int = 8 if rt == "tide" else 6
	var ang: float = d.angle()
	var home: Vector2 = o.pos
	var org: Vector2 = home - d * Bal.v("ult/ir_back", 130.0)   # 扇形顶点在她身后 ir_back（10-30 对齐 §3.4：前沿仍约 730，身侧罩得更全）
	var col: Color = u._col(o)
	var tw: float = Bal.v("ult/ir_wind", 0.2)
	var v2: bool = _ir_v2(u)
	var vs: float = PF.vseed(u, home)
	# 起风：扇形底色 + 卷风的弧线（沿切向飞）
	u.shape({"kind": "sector", "c": org, "r": R, "a": ang, "half": half, "col": COL_WIND, "fill": 0.06 if v2 else 0.1, "life": 1.0})
	if v2:
		_ir_gale_v2(u, org, R, ang, half, vs)
	for j in (0 if v2 else 4):
		var rr: float = R * (0.3 + 0.22 * j)
		_arc_lines(u, org, rr, ang - half, ang + half, 12, Color(COL_WIND, 0.7), 2.0, 0.5, 0.04 * j)
	for j in (0 if v2 else 28):
		var aj: float = ang - half + 2.0 * half * float((j * 11) % 28) / 27.0
		var rj: float = R * (0.2 + 0.75 * float((j * 7) % 10) / 9.0)
		var p: Vector2 = org + Vector2.from_angle(aj) * rj
		var tg: Vector2 = Vector2.from_angle(aj + PI / 2.0 * (1.0 if j % 2 == 0 else -1.0))
		u.shape({"kind": "line", "a": p, "b": p + tg * 50.0, "w": 2.5, "col": COL_WIND, "life": 0.45, "v": tg * 420.0 + Vector2.from_angle(aj) * 90.0, "delay": 0.01 * (j % 6)})
	o.face_to(ang)
	var cuts: Array = []
	for i in n:
		var lo: float = ang - half + 2.0 * half * i / n
		var hi: float = ang - half + 2.0 * half * (i + 1) / n
		var mid: float = (lo + hi) * 0.5
		var rr: float = R * (0.42 if i % 2 == 0 else 0.68)   # 一近一远，之字形穿过风暴
		cuts.append({"lo": lo, "hi": hi, "p": org + Vector2.from_angle(mid) * rr, "t": tw + 0.02 + float(i) * Bal.v("ult/ir_cut_gap", 0.075), "done": false})
	var tb: float = float(cuts[-1].t) + 0.08
	return {"org": org, "ang": ang, "half": half, "R": R, "tw": tw, "wseg": {}, "wind": false, "cuts": cuts, "cseg": {}, "cf": Bal.v("ult/ir_cut", 0.6),
		"tb": tb, "back": false, "shot": false, "eye": home + Vector2.from_angle(ang) * Bal.v("ult/ir_eye", 420.0), "bseg": {}, "air": [], "prev": home, "home": home,
		"v2": v2, "vs": vs}


static func _ir_step(u, a: Dictionary, o) -> bool:
	var g = u.g
	var t: float = a.t
	var org: Vector2 = a.org
	var ang: float = a.ang
	var half: float = a.half
	var R: float = a.R
	var col: Color = u._col(o)
	var rc: float = R * _core()
	_air_tick(u, a)
	if not a.wind and t >= float(a.tw) * 0.5:
		a.wind = true
		for e in _in_sector(u, org, R, ang, half):
			_once(u, a, o, a.wseg, e, Bal.v("ult/ir_wind_f", 0.1), {"src": "起风", "pre": true, "edge": e.pos.distance_to(org) > rc})
			if not e.dead:
				_launch(u, a, e, Bal.v("ult/ir_lift", 1.2), 60.0)
	for ai in a.cuts.size():
		var ct: Dictionary = a.cuts[ai]
		if ct.done or t < float(ct.t):
			continue
		ct.done = true
		var p: Vector2 = ct.p
		if a.v2:   # 化风冲刺的残影：沿路线一段风线（不画直线）
			var dd: Vector2 = p - a.prev
			_ir_wind(u, a.prev, dd.normalized(), dd.length(), Vector2.ZERO, 0.18, float(a.vs) + ai * 2.1, Color(0.85, 0.88, 0.94, 0.7))
		else:
			u.shape({"kind": "line", "a": a.prev, "b": p, "w": 7.0, "col": col.lerp(Color.WHITE, 0.4), "life": 0.15})   # 化风冲刺的残影
		_lead_move(u, o, p)
		a.prev = p
		var mid: float = (float(ct.lo) + float(ct.hi)) * 0.5
		o.face_to(mid)
		o.play_vis_anim("attack")
		var pa: Vector2 = org + Vector2.from_angle(float(ct.lo)) * R * 0.2
		var pb: Vector2 = org + Vector2.from_angle(float(ct.hi)) * R * 0.97
		if ai % 2 == 1:
			pa = org + Vector2.from_angle(float(ct.hi)) * R * 0.2
			pb = org + Vector2.from_angle(float(ct.lo)) * R * 0.97
		if a.v2:
			_ir_cut_v2(u, pa, pb, p, float(a.vs) + ai * 3.7, ai)
		else:
			u.shape({"kind": "blade", "a": pa, "b": pb, "w": 10.0, "col": Color.WHITE, "glow": col, "grow": 0.03, "life": 0.2})
			u.strip("fx_irene_crescent_wide", p, {"ang": mid, "sc": 2.4})
		for e in u.in_circle(org, R):
			var dv: Vector2 = e.pos - org
			var ea: float = angle_difference(ang, dv.angle())
			var rel: float = ea + half
			if absf(ea) > half and dv.length() >= 30.0:
				continue
			var lo_r: float = float(ct.lo) - (ang - half)
			var hi_r: float = float(ct.hi) - (ang - half)
			if dv.length() >= 30.0 and (rel < lo_r - 0.0001 or rel > hi_r + 0.0001):
				continue
			_once(u, a, o, a.cseg, e, float(a.cf), {"src": "连斩", "edge": dv.length() > rc})
	var tb: float = a.tb
	if not a.back and t >= tb:
		a.back = true   # 瞬身回原地，转身举手炮
		var home: Vector2 = a.home
		if a.v2:
			var dh: Vector2 = home - o.pos
			_ir_wind(u, o.pos, dh.normalized(), dh.length(), Vector2.ZERO, 0.18, float(a.vs) + 40.0, Color(0.85, 0.88, 0.94, 0.7))
		else:
			u.shape({"kind": "line", "a": o.pos, "b": home, "w": 6.0, "col": col.lerp(Color.WHITE, 0.5), "life": 0.15})
		_lead_move(u, o, home)
		_lead_land(u, o)
		o.face_to(ang)
	var eye: Vector2 = a.eye
	if not a.shot and t >= tb + 0.06:
		a.shot = true
		var home: Vector2 = a.home
		u.shape({"kind": "line", "a": home + Vector2(0, -18), "b": eye, "w": 4.0, "col": Color(1.0, 0.95, 0.75), "life": 0.08})
		u.strip("fx_irene_gun_burst", home + Vector2.from_angle(ang) * 30.0 + Vector2(0, -18), {"ang": ang, "sc": 2.5})
	if a.shot and not a.get("boom", false) and t >= tb + 0.12:
		a["boom"] = true
		o.screen_shake(0.8)
		var br: float = Bal.v("ult/ir_boom_r", 280.0)
		if a.v2:
			_ir_boom_v2(u, eye, br, org, R, ang, half, float(a.vs))
		else:
			u.strip("fx_cannon_burst", eye + Vector2(0, 30), {"o": Vector2(16, 27), "sc": 5.0})
			u.shape({"kind": "circle", "c": eye, "r": br, "col": Color(1.0, 0.8, 0.5), "fill": 0.35, "life": 0.25})
			_ring(u, eye, br, 30.0, col.lerp(Color.WHITE, 0.5), 0.35, 12.0)
			_arc_lines(u, org, R, ang - half, ang + half, 16, Color(COL_WIND, 0.8), 4.0, 0.3)   # 风暴边缘被炸散
		var bf: float = Bal.v("ult/ir_boom", 0.35)
		for e in _in_sector(u, org, R, ang, half):
			var de: float = e.pos.distance_to(eye)
			if de <= br:
				_once(u, a, o, a.bseg, e, bf, {"src": "手炮", "edge": de > br * _core()})
			else:
				_once(u, a, o, a.bseg, e, bf * Bal.v("ult/ir_boom_out", 0.6), {"src": "手炮", "edge": true})
	var air_end: float = Bal.v("ult/ir_lift", 1.2) + float(a.tw) * 0.5
	if a.get("boom", false) and t >= maxf(tb + 0.15, air_end):
		_air_end(u, a)
		return true
	return false


## ---- 艾丽妮 pixfx（docs/199 §7.10，开关 ult/ir_fx_v2 缺省 1；0 = 程序弧线 / 刀光 / 炮弹圆盘版）
## 风 = fx_ir_gale（三条稀疏风线首尾接成的无缝圈，截段沿扇形各圈切向飞）；刀 = fx_ir_slash1–3 灰冷白长弧斩光，从 pa 到 pb 快速划开；
## 手炮 = 白金亮核只留约 2–3 帧 → 金褐烟团 fx_ir_smoke1–4 鼓开、冷成暗褐 + 金色粒子 + 碎片飞落 + 风暴边缘风线被炸散。判定 / 时序 / u.hit 不动
const IR_SLASH := ["fx_ir_slash1", "fx_ir_slash2", "fx_ir_slash3"]
const IR_SMOKE := ["fx_ir_smoke1", "fx_ir_smoke2", "fx_ir_smoke3", "fx_ir_smoke4"]
const IR_GALE := "fx_ir_gale"
const IR_GOLD := Color(1.0, 0.82, 0.48)


static func _ir_v2(u) -> bool:
	return Bal.v("ult/ir_fx_v2", 1.0) > 0.0 and u.fx_ready(IR_GALE) and u.fx_ready(IR_SLASH[0]) and u.fx_ready(IR_SMOKE[0])


## 一段风线：从 p 起沿 dir 铺 len 长（截 fx_ir_gale 的一段，起点按哈希挑），往 v 飞、rev 秒内从尾到头显现
static func _ir_wind(u, p: Vector2, dir: Vector2, len: float, v: Vector2, life: float, hh: float, col: Color, delay := 0.0) -> void:
	var t: Texture2D = u._strip_tex(IR_GALE)
	var kk: float = PF.tex_w(u, IR_GALE) / t.get_width()
	var uw: float = minf(t.get_width() * 0.3, len / kk)
	u.strip(IR_GALE, p, {"layer": "back", "ang": dir.angle(), "o": Vector2(0.0, t.get_height() * 0.5), "ux": floorf(PF.h(hh) * (t.get_width() - uw)), "uw": uw,
		"sy": 1.0 if PF.h(hh + 3.0) < 0.5 else -1.0, "v": v, "rev": 0.12, "rev0": 0.25, "life": life, "fade": life * 0.5, "col": col, "delay": delay})


## 起风：扇形里三圈稀疏风线沿切向卷（同一圈同向、圈与圈反向错开），长短 / 起点 / 时刻按哈希
static func _ir_gale_v2(u, org: Vector2, R: float, ang: float, half: float, vs: float) -> void:
	for j in 3:
		var rr: float = R * (0.35 + 0.28 * j)
		var n: int = maxi(2, roundi(2.0 * half * rr / 420.0))
		var sg: float = 1.0 if j % 2 == 0 else -1.0
		for q in n:
			var hh: float = PF.h(vs * 0.7 + j * 13.0 + q * 3.1)
			var aj: float = ang - half + 2.0 * half * (q + 0.2 + 0.6 * hh) / n
			var rd := Vector2.from_angle(aj)
			var tg: Vector2 = rd.orthogonal() * sg
			var ln: float = 90.0 + 90.0 * PF.h(hh * 7.0)
			_ir_wind(u, org + rd * rr * (0.94 + 0.12 * hh) - tg * ln * 0.5, tg, ln, tg * (380.0 + 160.0 * hh) + rd * 70.0, 0.45 + 0.15 * hh,
				hh * 11.0, Color(0.8, 0.84, 0.9, 0.6), 0.03 * j + 0.06 * PF.h(hh * 5.0))


## 一刀：灰冷白长弧斩光从 pa 划到 pb（0.05 秒划开、0.2 秒淡），隔刀翻面 + 刀口一小撮风线迸开 + 冷光
static func _ir_cut_v2(u, pa: Vector2, pb: Vector2, p: Vector2, sd: float, ai: int) -> void:
	var name := PF.pick(u, IR_SLASH, sd)
	var t: Texture2D = u._strip_tex(name)
	var L: float = pa.distance_to(pb)
	var dv: Vector2 = (pb - pa) / maxf(1.0, L)
	var sx: float = L / PF.tex_w(u, name)
	var fl: float = (1.0 if ai % 2 == 0 else -1.0) * (1.0 if PF.h(sd + 2.0) < 0.7 else -1.0)
	u.strip(name, pa, {"ang": dv.angle(), "o": Vector2(0.0, t.get_height() * 0.5), "sx": sx, "sy": fl * clampf(sx, 0.85, 1.25),
		"rev": 0.05, "rev0": 0.08, "life": 0.2, "fade": 0.14, "col": Color(0.88, 0.9, 0.94, 0.85)})   # 六刀 0.075 秒一刀：寿命短、略暗，免得叠成一片白
	u.light(p, 170.0, Color(0.8, 0.88, 1.0), 0.12)
	for q in 2:
		var dq := Vector2.from_angle(dv.angle() + (PF.h(sd + q) - 0.5) * 1.6)
		_ir_wind(u, p, dq, 70.0 + 40.0 * PF.h(sd * 3.0 + q), dq * 520.0, 0.25, sd + q * 5.0, Color(0.85, 0.88, 0.94, 0.6))


## 手炮落点：亮核 0.08 秒（约 2–3 帧）→ 金褐烟团两团鼓开冷成暗褐 + 金色粒子 + 碎片飞落 + 顿帧；风暴边缘一圈风线往外炸散
static func _ir_boom_v2(u, eye: Vector2, br: float, org: Vector2, R: float, ang: float, half: float, vs: float) -> void:
	u.g.vfx.stop(Bal.v("ult/ir_hitstop", 0.08), "ult", true)   # 停顿感：炸开那一下顿住（画面层）
	u.shape({"kind": "circle", "c": eye, "r": br * 0.42, "col": Color(1.0, 0.93, 0.72), "fill": 0.92, "life": 0.08})
	u.shape({"kind": "circle", "c": eye, "r": br * 0.22, "col": Color(1.0, 0.98, 0.9), "fill": 0.95, "life": 0.06})
	u.light(eye, br * 1.7, IR_GOLD, 0.35)
	for l in 2:
		var name := PF.pick(u, IR_SMOKE, vs * 0.37 + l * 1.9)
		var rr: float = PF.tex_w(u, name) * 0.5
		var r0: float = br * (0.3 if l == 0 else 0.2)
		var r1: float = br * (0.78 if l == 0 else 0.55)
		u.strip(name, eye + Vector2.from_angle(PF.h(vs + l) * TAU) * br * 0.25 * l, {"sc": r0 / rr, "sc1": r1 / rr, "scd": 0.6, "life": 1.1 - 0.2 * l,
			"fade": 0.75, "ang": PF.h(vs * 1.3 + l * 7.0) * TAU, "sx": -1.0 if PF.h(vs + l * 4.0) < 0.5 else 1.0, "delay": 0.06 + 0.06 * l,
			"col": Color(1.15, 1.0, 0.85, 0.8), "col1": Color(0.45, 0.38, 0.33, 0.8), "cold": 0.45})
	PF.particles(u, eye, 600, "ult_burst", [Color(0.8, 0.6, 0.32), Color(0.62, 0.42, 0.22)], 0.03, vs, br * 1.35)
	PF.particles(u, eye, 100, "ult_ember", [Color(0.8, 0.55, 0.3)], 0.25, vs + 9.0)
	PF.aftershock(u, eye, br * 0.8, vs, 0.05, 9, Color(0.85, 0.7, 0.5))
	u.debris(eye, IR_GOLD, 3)
	_ring(u, eye, br, 30.0, Color(1.0, 0.85, 0.6, 0.6), 0.3, 4.0)
	var n: int = 6
	for q in n:   # 风暴边缘被炸散：风线往外甩
		var hh: float = PF.h(vs * 0.9 + q * 2.3)
		var aq: float = ang - half + 2.0 * half * (q + hh) / n
		var rd := Vector2.from_angle(aq)
		_ir_wind(u, org + rd * R * (0.85 + 0.1 * hh), rd, 90.0 + 60.0 * hh, rd * 600.0, 0.35, hh * 17.0, Color(0.85, 0.88, 0.94, 0.6), 0.04)


# ================================================================ 拉普兰德（§4.19）：原地狂舞连斩，4 圈双刃十字剑气向四面八方飞出，命中沉默

## 用户 10-31「拉普兰德改成往前攻击，高频剑气保留但朝前方乱砍，不要绕身」（开关 ult/la_fwd 缺省 1；0 = 原绕身四圈）：
## 判定改成前方扇形——顶点在她身后 ult/la_back（100），半角 ult/la_half、半径 ult/la_fr（按 ult_bench --area 定到标准面积 950 千平方像素 ±15%，docs/199 §5.10）；
## 四圈剑气照旧按时序从顶点往外扫（每圈 1/n、沉默、断喝末圈击退），只是只打扇形里的；乱砍剑气铺满扇形，收尾横斩横在扇形中段、垂直于朝向
static func _la_fwd() -> bool:
	return Bal.v("ult/la_fwd", 1.0) > 0.0


static func _la_in(a: Dictionary, p: Vector2) -> bool:
	if not a.get("fwd", false):
		return true
	var v: Vector2 = p - Vector2(a.org)
	return v.length() < 60.0 or absf(angle_difference(Vector2(a.d).angle(), v.angle())) <= float(a.half)


static func _la_start(u, o, d := Vector2.ZERO) -> Dictionary:
	var rt := _route(o)
	var n: int = 5 if rt == "rage" else 4
	var gap: float = 0.2 if rt == "rage" else Bal.v("ult/la_gap", 0.25)
	if _la_fwd() and d != Vector2.ZERO:   # 用户 10-31「斩击太卵太短，要连续不断」：朝前版圈与圈拉开到 la_fwd_gap，连续斩约 1.5 秒（狂暴路线同比 × 0.8）
		gap = Bal.v("ult/la_fwd_gap", 0.5) * (0.8 if rt == "rage" else 1.0)
	var segs: Array = []
	var wd: Array = []
	for i in n:
		segs.append({})
		wd.append(false)
	var R: float = Bal.v("ult/la_r", 502.0)
	var fwd: bool = _la_fwd() and d != Vector2.ZERO
	var face := Vector2(1.0 if float(o.face) >= 0.0 else -1.0, 0.0)
	var a := {"c": o.pos, "R": R, "rc": R * Bal.v("ult/la_core", 0.872), "n": n, "gap": gap, "fly": Bal.v("ult/la_fly", 0.24), "f": 1.0 / n,
		"segs": segs, "wd": wd, "fired": 0, "bark": rt == "bark",
		"v3": _la_v3(u), "face": face, "vs": PF.vseed(u, o.pos), "sl_t": 0.0, "sl_i": 0}
	if fwd:
		var dn: Vector2 = d.normalized()
		var bk: float = Bal.v("ult/la_back", 100.0)
		R = Bal.v("ult/la_fr", 860.0)
		a.merge({"fwd": true, "d": dn, "half": Bal.v("ult/la_half", 1.0), "org": o.pos - dn * bk, "R": R + bk, "rc": (R + bk) * Bal.v("ult/la_core", 0.872), "face": dn}, true)
		o.face_to(dn.angle())
	return a


static func _la_wave(u, a: Dictionary, o, i: int) -> void:
	var c: Vector2 = o.pos
	a.c = c
	var R: float = a.R
	var fly: float = a.fly
	var col: Color = u._col(o)
	var glow: Color = col.lerp(Color(0.55, 0.35, 1.0), 0.65)
	var spd: float = (R - 40.0) / fly
	var nb: int = 12
	var a0: float = (PI / nb) * float(i % 2) + 0.13 * i
	var last_bark: bool = a.bark and i == int(a.n) - 1
	if a.get("v3", false):   # 乱砍版：剑气由 _la_frenzy 按时刻撒，这里只播动作，末圈落横斩（不画脚底旋刃：会压在她身上）
		_la_wave_v3(u, a, o, i, c, R)
		return
	if _la_v2(u):
		_la_wave_v2(u, a, o, i, c, R, fly, spd, a0, nb, last_bark)
		return
	for k in nb:
		var dv := Vector2.from_angle(a0 + TAU * k / nb)
		var p: Vector2 = c + dv * 40.0
		var tg: Vector2 = dv.orthogonal()
		if last_bark:   # 断喝：第 4 圈是冲击波（宽弧）
			u.shape({"kind": "blade", "a": p - tg * 70.0, "b": p + tg * 70.0, "w": 12.0, "col": Color.WHITE, "glow": glow, "life": fly, "v": dv * spd})
			continue
		for s in [-1.0, 1.0]:   # 双刃十字：两道交叉的短刃一起往外飞
			var bd: Vector2 = tg.rotated(0.75 * s)
			u.shape({"kind": "blade", "a": p - bd * 30.0, "b": p + bd * 30.0, "w": 7.0, "col": Color.WHITE, "glow": glow, "life": fly, "v": dv * spd})
	u.shape({"kind": "ring", "c": c, "r": R, "r1": 40.0, "w": 2.0, "col": Color(glow, 0.5), "life": fly * 2.0})
	for k in 3:   # 她身边旋舞的剑光
		u.strip("fx_lappland_slash", c + Vector2(0, -16), {"ang": a0 + TAU * k / 3.0, "sc": 1.3, "col": Color(1, 1, 1, 0.9)})
	o.play_vis_anim("attack")
	if i == 0:
		o.screen_shake(0.5)


static func _la_step(u, a: Dictionary, o) -> bool:
	var g = u.g
	var t: float = a.t
	var n: int = a.n
	var gap: float = a.gap
	var fly: float = a.fly
	var R: float = a.R
	var rc: float = a.rc
	if a.get("v3", false):
		_la_frenzy(u, a, t)
	while int(a.fired) < n and t >= gap * int(a.fired):
		_la_wave(u, a, o, int(a.fired))
		a.fired = int(a.fired) + 1
	var c: Vector2 = a.org if a.get("fwd", false) else a.c
	for i in int(a.fired):
		var el: float = t - gap * i
		if a.wd[i]:
			continue
		if el >= fly:
			a.wd[i] = true   # 剑气飞到 R 的那一帧必扫一次（帧长较粗时不会从外缘漏过去）
		var fr: float = lerpf(40.0, R, clampf(el / fly, 0.0, 1.0))
		var bark: bool = a.bark and i == n - 1
		for e in u.in_circle(c, fr + 16.0):
			if not _la_in(a, e.pos):
				continue
			var dist: float = e.pos.distance_to(c)
			var op := {"src": "剑气", "edge": dist > rc}
			if bark and dist > 1.0:
				op["kb"] = (e.pos - c).normalized() * _kb_v(200.0)
			if _once(u, a, o, a.segs[i], e, float(a.f), op) and not e.dead and not e.boss:
				var sl: float = Bal.v("ult/la_silence", 4.0) * (0.5 if e.elite else 1.0)
				g.enemies_sys.silence(e, g.t + sl)
				e["seal_t"] = maxf(float(e.get("seal_t", 0.0)), g.t + sl)   # 甲壳 / 潮盾失效（同天赋「精神摧毁」的封印状态）
				e["seal_look"] = "cross"
				e["seal_by"] = str(o.id)
	return int(a.fired) >= n and t >= gap * (n - 1) + fly + 0.05


## ---- 拉普兰德 pixfx（docs/199 §7.10，开关 ult/la_fx_v2 缺省 1；0 = 程序白刃十字版）
## 审阅 10-30「冷蓝，不要纯白 X」：每圈 12 道双刃十字剑气 = fx_la_x1–4（冷蓝两道弯月刃交叉，每圈按 vseed 挑变体、隔道翻面），往外飞到 R、尾段淡；
## 一圈细弯刃旋环 fx_la_ring2–4（淡、跟剑气同速扩到 R 就散） 从 40 扩到 R（跟剑气同速、转着走）+ 脚底一团小旋刃（地面层，不画在她身上）；断喝末圈 = 加宽加长的十字刃
const LA_X := ["fx_la_x1", "fx_la_x2", "fx_la_x3", "fx_la_x4"]
const LA_RING := ["fx_la_ring2", "fx_la_ring3", "fx_la_ring4"]   # fx_la_ring1 粗旋涡太重（四圈叠成满屏蓝墙），只留给脚底小旋刃 fx_la_whirl
const LA_WHIRL := "fx_la_whirl"
const LA_COL := Color(0.75, 0.9, 1.0)


## ---- 拉普兰德「狂舞乱砍」（docs/199 §7.11，开关 ult/la_fx_v3 缺省 1；0 = §7.10 十字剑气圈版）。用户 10-30 认可方向：
## 对前方扇形高频乱砍，每道剑气角度 / 长短 / 弯度都不同、有交叉有残缺，冷蓝夹狼的银白，越砍越快越乱，最后一道最大的横斩收尾。
## 只改画面：剑气在 0 → 末圈时刻（gap ×（n−1））之间按哈希撒（间隔 0.06 → 0.02 秒），末圈落横斩；判定仍是原来的四圈全向（时序 / 扇形化列给协调人）
const LA_SILVER := Color(0.93, 0.95, 1.0)
const LA_ICE := Color(0.6, 0.82, 1.0)


static func _la_v3(u) -> bool:
	return Bal.v("ult/la_fx_v3", 1.0) > 0.0 and _la_v2(u) and u.fx_ready(IR_SLASH[0])


## 一道乱砍剑气：p 中点、ang 方向、ln 长；sd 哈希定变体 / 弯度 / 翻面 / 残缺 / 颜色
static func _la_cut(u, p: Vector2, ang: float, ln: float, sd: float, life: float, col: Color, thick := 1.0, whole := false, vel := Vector2.ZERO, delay := 0.0) -> void:
	var nm := PF.pick(u, IR_SLASH, sd * 0.41)
	var t: Texture2D = u._strip_tex(nm)
	var tw: float = PF.tex_w(u, nm)
	var dv := Vector2.from_angle(ang)
	var o := {"ang": ang, "o": Vector2(0.0, t.get_height() * 0.5), "sx": ln / tw, "sy": thick * (1.0 if whole else 0.55 + 1.1 * PF.h(sd + 5.0)) * (1.0 if PF.h(sd + 2.0) < 0.5 else -1.0),
		"rev": 0.035, "rev0": 0.1, "life": life, "fade": life * 0.6, "col": col}
	if vel != Vector2.ZERO:   # 飞行剑气：整道跟着飞，不逐渐显现、不残缺
		o.erase("rev")
		o["v"] = vel
		o["delay"] = delay
		o["fade"] = life * 0.35
		whole = true
	if not whole and PF.h(sd + 8.0) < 0.3:   # 残缺：只截中间一段
		var uw: float = t.get_width() * (0.45 + 0.35 * PF.h(sd + 9.0))
		o["ux"] = floorf(PF.h(sd + 10.0) * (t.get_width() - uw))
		o["uw"] = uw
	u.strip(nm, p - dv * ln * 0.5, o)


## 用户 10-31「剑气是全部往前飞行的，不是凭空出现；相当于她普攻剑气的 pro max 版本」（开关 ult/la_fly_wave 缺省 1）：
## 每道剑气从她身前发出（弧面垂直于飞行方向，像普攻的剑气波），以 ult/la_wave_spd（1900）飞到扇形尽头、尾段淡；长 220–420、粗 2–3 倍，
## 后面拖一层暗冷蓝残影（晚 0.03 秒同速）；方向在扇形里按哈希散、越到后面越乱；偶尔一道双刃十字同飞。判定仍是四圈扫
static func _la_fly_wave(u, a: Dictionary, dv: Vector2, sd: float, pr: float, i: int) -> void:
	var spd: float = Bal.v("ult/la_wave_spd", 1900.0)
	var p0: Vector2 = Vector2(a.org) + Vector2(a.d) * (float(Bal.v("ult/la_back", 100.0)) + 40.0) + dv.orthogonal() * (PF.h(sd + 2.2) - 0.5) * 60.0
	var life: float = float(a.R) / spd
	var ang: float = dv.angle() + PI * 0.5 + (PF.h(sd + 3.0) - 0.5) * lerpf(0.3, 0.8, pr)
	var ln: float = lerpf(220.0, 420.0, PF.h(sd + 4.0))
	var th: float = lerpf(2.0, 3.0, PF.h(sd + 5.5))
	var col: Color = LA_SILVER if i % 3 == 1 else LA_ICE
	_la_cut(u, p0, ang, ln * 0.95, sd + 0.5, life, Color(0.35, 0.5, 0.75, 0.55), th * 1.25, true, dv * spd, 0.03)   # 残影
	_la_cut(u, p0, ang, ln, sd, life, Color(col, 0.95), th, true, dv * spd)
	if PF.h(sd + 7.0) < 0.18:
		var xn := PF.pick(u, LA_X, sd)
		u.strip(xn, p0, {"ang": dv.angle(), "sc": 130.0 / PF.tex_w(u, xn), "life": life, "fade": life * 0.35, "v": dv * spd * 0.9})
	if i % 4 == 0:
		PF.particles(u, p0, 40, "ult_burst_s", [LA_ICE, LA_SILVER], 0.0, sd, 50.0)


static func _la_frenzy(u, a: Dictionary, t: float) -> void:
	var T: float = float(a.gap) * (int(a.n) - 1)
	var R: float = a.R
	var fw: Vector2 = a.face
	while float(a.sl_t) <= t and float(a.sl_t) < T - 0.02:
		var i: int = a.sl_i
		var pr: float = float(a.sl_t) / T
		var sd: float = float(a.vs) * 0.37 + i * 3.17
		var spread: float = float(a.half) * 1.8 if a.get("fwd", false) else 2.4
		var dv: Vector2 = fw.rotated((PF.h(sd) - 0.5) * spread)   # 前方（朝前版铺满扇形 ±0.9 半角；旧版 ±69°）
		if a.get("fwd", false) and Bal.v("ult/la_fly_wave", 1.0) > 0.0:
			_la_fly_wave(u, a, dv, sd, pr, i)
			a.sl_i = i + 1
			a.sl_t = float(a.sl_t) + lerpf(0.05, 0.03, pr)
			continue
		var p: Vector2 = (Vector2(a.org) if a.get("fwd", false) else Vector2(a.c)) + dv * R * (0.18 + 0.68 * PF.h(sd + 1.0))
		var ang: float = dv.angle() + PI * 0.5 + (PF.h(sd + 3.0) - 0.5) * PI * lerpf(0.45, 1.0, pr)   # 越砍越乱
		var ln: float = lerpf(260.0, 560.0, PF.h(sd + 4.0)) * (0.9 + 0.3 * pr)
		var col: Color = LA_SILVER if i % 3 == 1 else LA_ICE
		var th: float = lerpf(1.8, 2.8, PF.h(sd + 5.5))   # 粗：用户「太卵」
		_la_cut(u, p - Vector2.from_angle(ang) * 26.0, ang, ln * 0.9, sd + 0.5, 0.18, Color(0.35, 0.5, 0.75, 0.55), th * 1.3)   # 后一层暗冷蓝残影，给刀身厚度
		_la_cut(u, p, ang, ln, sd, 0.26 + 0.1 * PF.h(sd + 6.0), Color(col, 0.95), th)
		if i % 2 == 0:
			PF.particles(u, p + Vector2(0, 10), 40, "ult_ember", [Color(0.55, 0.62, 0.72)], 0.02, sd, 60.0)
		if PF.h(sd + 7.0) < 0.22:   # 偶尔一道双刃十字
			var xn := PF.pick(u, LA_X, sd)
			u.strip(xn, p, {"ang": ang, "sc": 110.0 / PF.tex_w(u, xn), "life": 0.16, "fade": 0.1, "v": dv * 500.0})
		if i % 5 == 0:
			PF.particles(u, p, 60, "ult_burst_s", [LA_ICE, LA_SILVER], 0.0, sd, 60.0)
		a.sl_i = i + 1
		a.sl_t = float(a.sl_t) + (lerpf(0.045, 0.028, pr) if a.get("fwd", false) else lerpf(0.06, 0.02, pow(pr, 1.2)))   # 朝前版：几乎匀速连斩，越到后面略密


static func _la_wave_v3(u, a: Dictionary, o, i: int, c: Vector2, R: float) -> void:
	var vs: float = float(a.vs) + i * 7.0
	o.play_vis_anim("attack")
	if i != int(a.n) - 1:
		return
	# 收尾横斩：屏幕横向贯穿约 2.2R、最长，下面一层冷蓝宽影；顿帧 + 冷光 + 中心一团银蓝粒子
	u.g.vfx.stop(Bal.v("ult/la_hitstop", 0.1), "ult", true)
	var ang: float = (PF.h(vs + 1.0) - 0.5) * 0.24
	if a.get("fwd", false):   # 朝前版：横斩横在扇形中段、垂直于朝向
		c = Vector2(a.org) + Vector2(a.d) * R * 0.45
		ang = Vector2(a.d).orthogonal().angle() + (PF.h(vs + 1.0) - 0.5) * 0.24
		R = R * sin(float(a.half)) * 0.5
	var dv := Vector2.from_angle(ang)
	_la_cut(u, c + dv.orthogonal() * 14.0, ang, R * 2.3, vs + 101.0, 0.45, Color(LA_ICE, 0.55), 1.3, true)   # 一整道（两段拼会成海鸥翅膀形）
	_la_cut(u, c, ang, R * 2.2, vs + 101.0, 0.5, Color(0.8, 0.86, 0.95, 0.9), 0.95, true)   # 压暗（预审报横斩发白）
	u.light(c, R * 1.2, LA_ICE, 0.3)
	PF.particles(u, c, 200, "ult_burst_s", [LA_ICE, LA_SILVER], 0.04, vs + 3.0, 140.0)
	if a.get("fwd", false):   # 用户 10-31：最后接一个空气爆破——横斩之后 0.12 秒，斩线中点一圈冷白气浪炸开（尘浪环三种挑一）+ 一大团银蓝粒子 + 尘
		var bc: Vector2 = c
		var br: float = float(a.R) * 0.55
		PF.ring(u, ["fx_sg_shock", "fx_sg_shock2", "fx_sg_shock3"], bc, br * 0.15, br, 0.28, 0.6,
			{"seed": vs, "layer": "front", "col": Color(0.75, 0.82, 0.95, 0.75), "col1": Color(0.4, 0.5, 0.65, 0.45), "cold": 0.2, "delay": 0.12, "fade": 0.35})
		PF.particles(u, bc, 300, "ult_burst", [Color(0.55, 0.7, 0.9), LA_ICE.darkened(0.25)], 0.12, vs + 9.0, br * 1.1)   # 预审：爆破别发白（少一层、压暗）
		PF.particles(u, bc, 200, "ult_ember", [Color(0.62, 0.68, 0.78)], 0.16, vs + 4.0, br * 0.7)
		u.light(bc, br * 1.4, LA_ICE, 0.3)
		var sfx: Node = u.g.get_node_or_null("/root/Sfx") if u.g.is_inside_tree() else null
		if sfx != null:
			sfx.play("boom", -2.0, 1.3)


static func _la_v2(u) -> bool:
	return Bal.v("ult/la_fx_v2", 1.0) > 0.0 and u.fx_ready(LA_X[0]) and u.fx_ready(LA_RING[0]) and u.fx_ready(LA_WHIRL)


static func _la_wave_v2(u, a: Dictionary, o, i: int, c: Vector2, R: float, fly: float, spd: float, a0: float, nb: int, bark: bool) -> void:
	var vs: float = PF.vseed(u, c) + i * 7.0
	var len: float = 150.0 if bark else 96.0   # 剑气宽（世界）
	for k in nb:   # 每道各挑变体、大小 0.75–1.25、转角 ±0.35、起点 30–70（同时飞到 R；飞行方向 = 判定方向不变）
		var dv := Vector2.from_angle(a0 + TAU * k / nb)
		var hh: float = PF.h(vs + k * 1.7)
		var name := PF.pick(u, LA_X, vs * 0.31 + k * 2.3)
		var r0: float = 30.0 + 40.0 * PF.h(hh * 13.0)
		u.strip(name, c + dv * r0, {"ang": dv.angle() + (PF.h(hh * 5.0) - 0.5) * 0.7, "sc": len / PF.tex_w(u, name) * (0.75 + 0.5 * hh), "sx": 1.4 if bark else 1.0,
			"sy": 1.0 if PF.h(hh * 3.0) < 0.5 else -1.0, "v": dv * spd * (R - r0) / (R - 40.0), "life": fly + 0.04, "fade": 0.1, "col": Color(1.05, 1.05, 1.05)})
	PF.ring(u, LA_RING, c, 50.0, R, fly, fly + 0.06, {"seed": vs, "layer": "back", "fade": fly * 0.6, "col": Color(1.0, 1.0, 1.0, 0.3)})
	var rr: float = PF.tex_w(u, LA_WHIRL) * 0.5
	u.strip(LA_WHIRL, c, {"sx": -1.0 if i % 2 == 1 else 1.0, "layer": "back", "sc": 70.0 / rr, "sc1": 95.0 / rr, "scd": 0.2, "spin": 14.0 * (1.0 if i % 2 == 0 else -1.0), "ang": PF.h(vs) * TAU, "life": 0.24, "fade": 0.12})
	u.light(c, 220.0, LA_COL, 0.15)
	o.play_vis_anim("attack")


# ================================================================ 流明（§4.20）：队长脚下升起灯塔光柱 → 光圈扩散灼烧 → 光柱亮 2 秒（每 0.5 秒一跳、灯塔光束扫过）后熄灭

static func _lu_start(u, o) -> Dictionary:
	var rt := _route(o)
	var g = u.g
	var c: Vector2 = o.pos
	var dur: float = Bal.v("ult/lu_dur", 2.0)
	var col: Color = u._col(o)
	var H: float = 620.0
	# 光柱：外层干员色、内芯白；脚下灯塔点亮（fx_beacon_ignite）
	u.shape({"kind": "band", "a": c + Vector2(0, 10), "b": c + Vector2(0, -H), "w": 86.0, "col": col, "fill": 0.45, "life": dur + 0.3})
	u.shape({"kind": "band", "a": c + Vector2(0, 6), "b": c + Vector2(0, -H), "w": 30.0, "col": COL_LIGHT, "fill": 0.85, "life": dur + 0.25})
	u.shape({"kind": "blade", "a": c + Vector2(0, 20), "b": c + Vector2(0, -H - 40.0), "w": 22.0, "col": COL_LIGHT, "glow": col, "grow": 0.15, "life": 0.4})
	u.strip("fx_beacon_ignite", c, {"sc": 3.0, "col": Color(0.85, 0.95, 1.0)})
	u.strip("fx_lumen_beam_flare", c + Vector2(0, -H), {"sc": 2.5, "loop": true, "life": dur + 0.2})
	g.lamp = maxf(g.lamp, float(g.lamp_cap))   # 附带：灯火补满
	g.nerve = 0.0   # 清除神经损伤，6 秒内不再累积
	g.nerve_lock = maxf(g.nerve_lock, Bal.v("ult/lu_nerve_t", 6.0))
	var ticks: int = 0 if rt == "watch" else 4
	var R: float = Bal.v("ult/lu_r", 502.0)
	return {"c": c, "R": R, "rc": R * Bal.v("ult/lu_core", 0.872), "t0": Bal.v("ult/lu_rise", 0.2), "exp": 0.25, "ef": 0.7 if rt == "rain" else 0.8,
		"eseg": {}, "boomed": false, "dur": dur, "tick": 0, "ticks": ticks, "tseg": [{}, {}, {}, {}], "rain": rt == "rain", "rseg": [{}, {}],
		"rn": 0, "rf": 0, "watch": rt == "watch", "wseg": {}, "wcnt": {}, "rot": 0.0}


static func _lu_step(u, a: Dictionary, o, dt: float) -> bool:
	var t: float = a.t
	var c: Vector2 = a.c
	var R: float = a.R
	var col: Color = u._col(o)
	var rc: float = a.rc
	var t0: float = a.t0
	if t < t0:
		return false
	var el: float = t - t0
	if not a.boomed:
		a.boomed = true
		o.play_vis_anim("attack")
		o.screen_shake(0.6)
		_ring(u, c, R, 40.0, COL_LIGHT, 0.5, 18.0)
		_ring(u, c, R * 0.92, 40.0, col, 0.5, 6.0, 0.05)
		u.shape({"kind": "circle", "c": c, "r": R, "col": col.lerp(Color.WHITE, 0.4), "fill": 0.22, "life": 0.45})
		for j in 20:   # 光芒放射
			var dv := Vector2.from_angle(j * TAU / 20.0)
			u.shape({"kind": "line", "a": c + dv * 50.0, "b": c + dv * R, "w": 3.0 if j % 2 == 0 else 1.5, "col": COL_LIGHT, "life": 0.3})
	var T: float = a.exp
	if not a.get("edone", false):   # 光圈扩散：前沿经过时 80%（扩到 R 的那一帧必扫一次）
		a["edone"] = el >= T
		var fr: float = lerpf(40.0, R, clampf(el / T, 0.0, 1.0))
		for e in u.in_circle(c, fr + 16.0):
			_once(u, a, o, a.eseg, e, float(a.ef), {"src": "光圈", "edge": e.pos.distance_to(c) > rc})
	# 灯塔光束：两道旋转光束扫过光圈（画面；灯塔守望路线下真打）
	var dur: float = a.dur
	if el <= dur:
		a.rot = float(a.rot) + TAU / Bal.v("ult/lu_rot_t", 1.0) * dt
		var fade: float = 1.0 - el / dur
		for s in 2:
			var ba: float = float(a.rot) + PI * s
			u.shape({"kind": "sector", "c": c, "r": R, "a": ba, "half": 0.07, "col": COL_LIGHT, "fill": (0.45 if a.watch else 0.22) * fade + 0.05, "life": 0.05})
			if a.watch:
				for e in _in_sector(u, c, R, ba, 0.09):
					var k: int = int(e.id)
					var last: float = float(a.wseg.get(k, -9.0))
					if t - last < 0.4 or int(a.wcnt.get(k, 0)) >= 4:
						continue
					a.wseg[k] = t
					a.wcnt[k] = int(a.wcnt.get(k, 0)) + 1
					_hit(u, a, o, e, 0.05, {"src": "灯塔光束", "edge": e.pos.distance_to(c) > rc})
	# 光柱持续：每 0.5 秒一跳 5%
	while int(a.tick) < int(a.ticks) and el >= 0.5 * (int(a.tick) + 1):
		var i: int = int(a.tick)
		a.tick = i + 1
		_ring(u, c, R, R * 0.75, Color(col.lerp(Color.WHITE, 0.5), 0.8), 0.3, 5.0)
		u.shape({"kind": "dots", "c": c, "r": R * 0.9, "n": 20, "col": COL_LIGHT, "life": 0.35})
		for e in u.in_circle(c, R):
			_once(u, a, o, a.tseg[i], e, 0.05, {"src": "光柱", "edge": e.pos.distance_to(c) > rc})
	if a.rain:   # 光雨：光圈内落 2 秒光雨（每秒 5%）
		a.rf = int(a.rf) + 1
		if int(a.rf) % 3 == 0 and el <= dur:
			for k in 3:
				var q: int = int(a.rf) * 3 + k
				var p: Vector2 = c + Vector2.from_angle(q * 2.39996) * R * sqrt(float((q * 37) % 97) / 97.0)
				u.shape({"kind": "line", "a": p + Vector2(0, -60), "b": p + Vector2(0, -20), "w": 2.0, "col": COL_LIGHT, "life": 0.2, "v": Vector2(0, 200)})
		while int(a.rn) < 2 and el >= 1.0 * (int(a.rn) + 1):
			var i2: int = int(a.rn)
			a.rn = i2 + 1
			for e in u.in_circle(c, R):
				_once(u, a, o, a.rseg[i2], e, 0.05, {"src": "光雨", "edge": e.pos.distance_to(c) > rc})
	return el >= dur + 0.05
