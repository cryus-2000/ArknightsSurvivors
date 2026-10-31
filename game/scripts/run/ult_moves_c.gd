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
	if id == "saria" and _sa_cone():   # 用户 10-30：塞雷娅改朝前打（ult/sa_cone 1；0 = 原以自身为圆心的拳风环）
		return "dir"
	if id == "irene" and _irv_on():   # 用户 10-31「宣判」：绕身一圈，不瞄
		return "none"
	if id in DIR_OPS:
		return "dir"
	if id in POINT_OPS:
		return "point"
	return "none"


static func aim_r(id: String) -> float:
	match id:
		"saria":
			return Bal.v("ult/sa_r", 502.0) * (Bal.v("ult/sa_len_k", 1.35) if _sa_cone() else 1.0)
		"siege":
			return Bal.v("ult/sg_r", 540.0)
		"irene":
			return Bal.v("ult/ir_verdict_r", 550.0) if _irv_on() else Bal.v("ult/ir_r", 860.0)
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
			a = _irv_start(u, o) if _irv_on() else _ir_start(u, o, d)
		"lappland":
			a = _la_start(u, o)
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
			return _irv_step(u, a, o) if a.get("irv", false) else _ir_step(u, a, o)
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
static func _sa_cone() -> bool:
	return Bal.v("ult/sa_cone", 1.0) > 0.0


static func _sa_start(u, o, d: Vector2) -> Dictionary:
	var rt := _route(o)
	var cone: bool = _sa_cone()
	var half: float = Bal.v("ult/sa_half", 0.62)   # 朝前打：扇形半角（约 35°，比漏斗印子略宽，协调人 10-31「可以开宽一点」）；射程 ult/sa_len_k 倍
	var R: float = Bal.v("ult/sa_r", 502.0) * (Bal.v("ult/sa_len_k", 1.35) if cone else 1.0)
	var ck: float = Bal.v("ult/sa_cone_k", 1.0) if cone else 1.0   # 朝前打命中面变小（同 seed 4 局终结技输出 −32%）；补偿旋钮，用户 10-31 定美术定稿、范围定了再补，缺省先 1
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
		if cone:   # 朝前打：裂纹 / 爆点都在前方扇形里散开
			ang = d.angle() + (float(i) / maxf(1.0, float(nc - 1)) - 0.5) * 2.0 * half * 0.9 + 0.06 * sin(float(i) * 2.7)
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
	return {"v2": v2, "fa": d.angle(), "cone": cone, "half": half, "org": c, "R": R, "ch": ch, "tr": tr, "cspd": cspd, "wf": (1.0 - cf) * ck, "cf": cf * ck, "cracks": cracks, "booms": booms,
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
		u.shape({"kind": "circle", "c": org, "r": 110.0, "col": COL_AMBER.lerp(Color.WHITE, 0.25 if a.get("v2", false) else 0.45), "fill": 0.7 if a.get("v2", false) else 0.95, "life": 0.07 if a.get("v2", false) else 0.1})   # v2 压白闪（预审 1/3 报发白）
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
		if a.get("cone", false) and off.length() > 70.0 and absf(wrapf(off.angle() - float(a.fa), -PI, PI)) > float(a.half):
			continue   # 朝前打：扇形外（脚边 70 内照打）不吃拳风
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
			if hb < 0.3:   # 爆点沿判定裂纹等距，每处都崩碎石会排成一串方块（预审报），只给约三成、一块
				PF.rock(u, p, Vector2.from_angle(TAU * hb) * 70.0, 200.0 + 90.0 * PF.h(hb), PF.h(hb * 7.0), 0.45, 0.0)
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
## 用户 10-30 第四轮：「往前打一拳，面前的拳风撕裂空气和大地，在地上留下一个漏斗形的裂地印子，要有空气爆炸的感觉」：
## 顿帧 → 朝出拳方向（fa）一团空气爆炸（fx_sa_air，白 / 淡金气浪弧往前炸开，两层错开）+ 前方锥内速度线 → 地面撕出漏斗形裂地印子
## （fx_sa_funnel1/2，窄端在她脚下、往前张开，0.12 秒撕开、慢慢冷却）+ 四拍隆起。判定仍是以她为圆心的拳风环 + 放射裂纹爆点（只改画面），
## 圈的范围留一道淡的细环提示。旧版的分叉裂网 / 尘石墙 / 360° 速度线不画
const SA_FUNNELS := ["fx_sa_funnel1", "fx_sa_funnel2"]
const SA_AIR := "fx_sa_air"
const A = preload("res://scripts/art.gd")


static func _sa_v2(u) -> bool:
	return Bal.v("ult/sa_fx_v2", 1.0) > 0.0 and PF.pick(u, SA_FUNNELS, 0.0) != "" and u.fx_ready(SA_AIR)


static func _sa_punch_v2(u, a: Dictionary, org: Vector2, R: float, tr: float) -> void:
	# 用户 10-30 第六轮：「漏斗范围更大、停顿不够、先裂地再拳风爆炸」——顿帧加长到 ult/sa_hitstop（0.2）→ 地面先撕开（三道漏斗印子铺满前方扇形）
	# → 0.16 秒后拳风空气爆炸往前炸开 → 四拍隆起
	var vs: float = PF.vseed(u, org)
	var fa: float = float(a.get("fa", 0.0)) + (PF.h(vs) - 0.5) * 0.08
	var fw := Vector2.from_angle(fa)
	var half: float = float(a.get("half", 0.55))
	u.g.vfx.stop(Bal.v("ult/sa_hitstop", 0.2), "ult", true)
	u.light(org + fw * R * 0.4, R * 0.7, Color(1.0, 0.92, 0.75), 0.4)
	u.debris(org + fw * 60.0, Color(0.85, 0.8, 0.7), 3)
	u.shape({"kind": "ellipse", "c": org + Vector2(0, 6), "rx": 80.0, "ry": 38.0, "col": Color(0.08, 0.07, 0.06), "fill": 0.6, "life": 1.8, "layer": "back"})
	# ① 先裂地：中间一道主漏斗 + 两侧两道小一点的，铺满前方扇形
	for m in 3:
		var side: float = 0.0 if m == 0 else (half * 0.55 * (1.0 if m == 1 else -1.0))
		var fn: String = SA_FUNNELS[(m + int(PF.h(vs) * 2.0)) % SA_FUNNELS.size()]   # 中间和两侧换不同的漏斗（预审报三道一样）
		var ft: Texture2D = u._strip_tex(fn)
		var k: float = R * (1.0 if m == 0 else (0.78 if m == 1 else 0.66)) / PF.tex_w(u, fn)
		u.strip(fn, org - Vector2.from_angle(fa + side) * 10.0, {"layer": "back", "ang": fa + side + (PF.h(vs + m) - 0.5) * 0.1, "o": Vector2(0.0, ft.get_height() * 0.5),
			"sx": k, "sy": k * (1.5 if m == 0 else 1.15) * (1.0 if PF.h(vs + 1.0 + m) < 0.5 else -1.0),
			"rev": 0.14 + 0.05 * m, "rev0": 0.1, "delay": [0.0, 0.05, 0.09][m], "life": 2.6, "fade": 0.8, "col": Color(1.0, 0.96, 0.9), "col1": Color(0.55, 0.5, 0.46), "cold": 0.6})
	# ② 再拳风空气爆炸：两层气浪往前炸开
	var at: Texture2D = u._strip_tex(SA_AIR)
	var ka: float = R * 0.8 / PF.tex_w(u, SA_AIR)
	for m in 2:
		u.strip(SA_AIR, org + fw * (20.0 + 30.0 * m), {"ang": fa + (0.08 if m == 1 else 0.0), "o": Vector2(0.0, at.get_height() * 0.5),
			"sc": ka * 0.45, "sc1": ka * (1.0 - 0.25 * m), "scd": 0.14, "delay": 0.16 + 0.05 * m, "life": 0.3, "fade": 0.18,
			"col": Color(1.0, 1.0, 1.0, 0.65 - 0.25 * m), "sy": -1.0 if m == 1 else 1.0})
	var spd: float = R / tr
	for q in 12:
		var dv := Vector2.from_angle(fa + (PF.h(q * 5.1 + vs) - 0.5) * 2.0 * half)
		var r0: float = 30.0 + 80.0 * PF.h(q * 3.0 + vs)
		u.shape({"kind": "line", "a": org + dv * r0, "b": org + dv * (r0 + 60.0 + 110.0 * PF.h(q + 7.0 + vs)), "w": 4.0 if q % 3 == 0 else 2.5,
			"col": Color(0.95, 0.95, 0.9), "life": tr * (0.6 + 0.4 * PF.h(q + 11.0)), "delay": 0.16 + 0.03 * PF.h(q + 13.0 + vs), "v": dv * spd * (0.9 + 0.4 * PF.h(q + 17.0))})
	PF.particles(u, org + fw * R * 0.35, 160, "ult_burst_s", [Color(1.0, 0.95, 0.85)], 0.16, vs, R * 0.35)
	a["vs"] = vs
	a["beats"] = [[float(a.t) + 0.0, R * 0.3, 0], [float(a.t) + 0.18, R * 0.55, 1], [float(a.t) + 0.36, R * 0.8, 2], [float(a.t) + 0.54, R * 1.0, 3]]
	if a.get("cone", false):
		a["beat_fan"] = [fa, half]
	PF.aftershock(u, org + fw * R * 0.4, R * 0.6, 3.0 + vs, 0.84, 10)


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
	PF.crack_net(u, SG_FORKS, c, R, 11 + int(PF.h(vs + 1.0) * 5.0), PF.h(vs + 2.0) * TAU, vs, 0.54, Color(1.1, 1.08, 1.05), Color(0.3, 0.29, 0.28), 30.0, true)   # crop：预审报同形瓦片重复
	u.g.vfx.stop(Bal.v("ult/sg_hitstop", 0.1), "ult", true)
	PF.particles(u, c, 200, "ult_burst_s", [Color(0.95, 0.92, 0.85), Color(0.7, 0.68, 0.62)], 0.0, vs)   # 锤坑迸出的碎石尘
	PF.aftershock(u, c, R, 7.0 + vs, 0.54 + 0.3, 12)   # 尘土墙（同一张截段排一圈）预审报瓦片重复，去掉


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

static func _lo_start(u, o, d: Vector2) -> Dictionary:
	var rt := _route(o)
	var hw: float = Bal.v("ult/lo_w", 920.0) * 0.5
	var L: float = Bal.v("ult/lo_len", 900.0)
	var bk: float = Bal.v("ult/lo_back", 160.0)   # 咒域从队长身后 bk 起（10-30 对齐 §3.4：原 60）
	var org: Vector2 = o.pos
	var tm: float = Bal.v("ult/lo_mark", 0.5)
	var col: Color = u._col(o)
	var p0: Vector2 = _w(org, d, -bk, -hw)
	var p1: Vector2 = _w(org, d, L, -hw)
	var p2: Vector2 = _w(org, d, L, hw)
	var p3: Vector2 = _w(org, d, -bk, hw)
	# 咒域：矩形描边 + 底色 + 两条长边的咒文条（fx_logos_script 拼接）+ 横向分隔线
	u.shape({"kind": "band", "a": org - d * bk, "b": org + d * L, "w": hw * 2.0, "col": COL_INK, "fill": 0.16, "life": tm + 0.1})
	for pr in [[p0, p1], [p1, p2], [p2, p3], [p3, p0]]:
		u.shape({"kind": "line", "a": pr[0], "b": pr[1], "w": 3.0, "col": col.lerp(Color.WHITE, 0.3), "life": tm + 0.1})
	u.tiles_line("fx_logos_script", p0 + d.orthogonal() * 14.0, p1 + d.orthogonal() * 14.0, {"loop": true, "life": tm + 0.1})
	u.tiles_line("fx_logos_script", p3 - d.orthogonal() * 14.0, p2 - d.orthogonal() * 14.0, {"loop": true, "life": tm + 0.1})
	for k in 4:
		var x: float = lerpf(-bk, L, (k + 1) / 5.0)
		u.shape({"kind": "line", "a": _w(org, d, x, -hw), "b": _w(org, d, x, hw), "w": 1.5, "col": Color(col, 0.6), "life": tm, "delay": 0.05 * k})
	# 标记（头顶咒文，fx_logos_glyph 画入 0–3；同屏至多 ult/lo_mark_fx 个，伤害照打每一个）
	var marks: Array = []
	var cap: int = int(Bal.v("ult/lo_mark_fx", 40.0))
	for e in _in_rect(u, org, d, -bk, L, hw):
		if marks.size() >= cap:
			break
		marks.append({"e": e, "s": u.strip("fx_logos_glyph", e.pos + Vector2(0, -float(e.get("r", 10.0)) - 20.0), {"seg": [0, 3], "fps": 9.0, "life": tm, "sc": 1.2})})
	o.face_to(d.angle())
	return {"org": org, "d": d, "hw": hw, "L": L, "bk": bk, "tm": tm, "marks": marks, "seg": {}, "boom": false,
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
		u.shape({"kind": "band", "a": org - d * bk, "b": org + d * L, "w": hw * 2.0, "col": col.lerp(Color.WHITE, 0.5), "fill": 0.35, "life": 0.25})
		for k in 6:   # 一词念出：咒文从队长往矩形尽头横扫
			var x: float = lerpf(-bk, L, (k + 0.5) / 6.0)
			u.shape({"kind": "line", "a": _w(org, d, x, -hw), "b": _w(org, d, x, hw), "w": 5.0, "col": Color.WHITE, "life": 0.18, "delay": 0.02 * k})
		for mk in a.marks:
			var p: Vector2 = mk.s.c
			u.strip("fx_logos_glyph", p, {"seg": [3, 5], "fps": 14.0, "sc": 1.5})
		var thr: float = u.ref_hp() * Bal.v("ult/lo_exec", 2.0)
		var nexe := 0
		var nmeto := 0
		for e in _in_rect(u, org, d, -bk, L, hw):
			var edge: bool = absf(_loc(e.pos, org, d).y) > hc
			var frac: float = a.mf
			var exe: bool = _minion(e) and float(e.hp) < thr   # 处决按生命阈值，外缘也算（§3.3：和小怪档同一档）
			if exe:   # 处决：按她的生命直接补满（照亮的 1.25 折扣也补回）
				frac = maxf(frac, float(e.hp) / maxf(1.0, u.budget(e, edge) * u.build_mult(o)) * 1.3)
			var pos: Vector2 = e.pos
			_once(u, a, o, a.seg, e, frac, {"src": "处决" if exe else "咒文", "edge": edge})
			if e.dead:
				if exe:
					nexe += 1
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
						u.strip("fx_logos_glyph", pos + Vector2(0, -10), {"seg": [0, 3], "fps": 4.0, "sc": 2.6, "life": 1.0})
			elif not e.boss:
				e["requiem"] = Bal.v("ult/lo_requiem", 8.0)   # 安魂（受到的法术伤害 +15%）
		for bl in g.ebullets:   # 只清矩形内的敌方弹幕
			if float(bl.get("life", 0.0)) <= 0.0:
				continue
			var l: Vector2 = _loc(bl.pos, org, d)
			if l.x >= -bk and l.x <= L and absf(l.y) <= hw:
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


static func _lo_outside(u, a: Dictionary, p: Vector2):
	var best = null
	var bd := 400.0 * 400.0
	for e in u.in_circle(p, 400.0):
		var l: Vector2 = _loc(e.pos, a.org, a.d)
		if l.x >= -float(a.bk) and l.x <= float(a.L) and absf(l.y) <= float(a.hw):
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
	# 起风：扇形底色 + 卷风的弧线（沿切向飞）
	u.shape({"kind": "sector", "c": org, "r": R, "a": ang, "half": half, "col": COL_WIND, "fill": 0.1, "life": 1.0})
	for j in 4:
		var rr: float = R * (0.3 + 0.22 * j)
		_arc_lines(u, org, rr, ang - half, ang + half, 12, Color(COL_WIND, 0.7), 2.0, 0.5, 0.04 * j)
	for j in 28:
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
		"tb": tb, "back": false, "shot": false, "eye": home + Vector2.from_angle(ang) * Bal.v("ult/ir_eye", 420.0), "bseg": {}, "air": [], "prev": home, "home": home}


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


# ================================================================ 艾丽妮「宣判」（用户 10-31 选 A 并修改；docs/199 §7.15；开关 ult/ir_verdict 缺省 1，0 = 原扇形狂风连斩 + 手炮）
## ① 定罪（0.1 秒）：脚下盖下金色审判纹章（fx_irv_seal，从 1.25 倍压到位），圈内敌人被地下伸出的锁链（fx_irv_chain1–4）直接钉住（眩晕，不拖拽）；
## ② 行刑（0.18–0.78 秒）：她原地旋风转身连转 3 圈（狂飙路线 4 圈），细剑扫斩 + 手铳朝四周连射：脚下 smear 弧（fx_irv_smear1–4）跟着转、速度线、枪口火光；
##    第一圈扫到谁就斩谁（按方位角随刀扫过的先后）；
## ③ 收尾（0.85 秒起）：被钉住的敌人按距离由近到远连环炸开（0.4 秒铺满），锁链跟着断，最后纹章碎裂（金色分叉裂纹 + 碎片）；第一下爆炸走冲击帧（全屏），其余是局部光。
## 判定：以她为圆心半径 ult/ir_verdict_r 550（范围统一的标准面积 95 万平方像素，claude/ult-area-unify a3fa40308、docs/199 §5.10；扇形版的 708 是扇形半径，绕身整圈用它面积会超七成）。数值沿用原三段：定罪 ult/ir_wind_f 0.1（pre）、
## 斩 ult/ir_cut 0.6（pre）、炸 ult/ir_boom 0.35（半径一半以外 × ult/ir_boom_out 0.6），等范围统一后再对齐。色调冷白 / 金 / 深蓝（和流明暖金拉开）
const IRV_SEAL := "fx_irv_seal"
const IRV_CHAIN := ["fx_irv_chain1", "fx_irv_chain2", "fx_irv_chain3", "fx_irv_chain4"]
const IRV_SMEAR := ["fx_irv_smear1", "fx_irv_smear2", "fx_irv_smear3", "fx_irv_smear4"]
const IRV_GOLD := Color(0.95, 0.8, 0.45)
const IRV_WHITE := Color(0.88, 0.93, 1.0)
const IRV_NAVY := Color(0.2, 0.3, 0.55)
const IRV_FORKS := ["fx_sg_fork1", "fx_sg_fork2", "fx_sg_fork3", "fx_sg_fork4"]   # 金色碎裂：借推进之王灰白分叉裂缝染金（乌尔比安那组是青色，染金发绿）


static func _irv_on() -> bool:
	return Bal.v("ult/ir_verdict", 1.0) > 0.0


static func _irv_start(u, o) -> Dictionary:
	var rt := _route(o)
	var c: Vector2 = o.pos
	var R: float = Bal.v("ult/ir_verdict_r", 550.0)   # 范围统一（claude/ult-area-unify a3fa40308、docs/199 §5.10）：标准面积 95 万平方像素 = 半径约 550 的绕身圆；画面全按它缩放
	var vs: float = PF.vseed(u, c)
	var spins: int = 4 if rt == "gale" else 3
	o.play_vis_anim("attack")
	if _irv3():   # 用户 10-31「镜头不要晃，固定」：整段终结技镜头钉在纹章中心（她穿梭时镜头不跟）
		u.cam_hold = c
		u.cam_hold_until = u.g.t + 1.7
	# 定罪前一拍：纹章从 1.25 倍压下来（0.1 秒），金光收拢
	if u.fx_ready(IRV_SEAL):
		var rr: float = PF.tex_w(u, IRV_SEAL) * 0.5
		var s: Dictionary = u.strip(IRV_SEAL, c, {"layer": "back", "sc": R * 1.25 / rr, "sc1": R / rr, "scd": 0.1, "ang": PF.h(vs) * TAU, "life": 2.0, "fade": 0.3,
			"col": Color(0.95, 0.9, 0.78, 0.5), "col1": Color(0.75, 0.76, 0.82, 0.32), "cold": 0.5})   # 半透明盖地（深蓝底别盖满屏）
		return {"irv": true, "c": c, "R": R, "rc": R * _core(), "vs": vs, "spins": spins, "seal": s, "pins": [], "wseg": {}, "cseg": {}, "bseg": {},
			"stamped": false, "booms": [], "boomed": false, "air": [], "end_t": 99.0, "cf": Bal.v("ult/ir_cut", 0.6), "shot_t": 0.0, "smear_t": 0.0}
	return {"irv": true, "c": c, "R": R, "rc": R * _core(), "vs": vs, "spins": spins, "seal": {}, "pins": [], "wseg": {}, "cseg": {}, "bseg": {},
		"stamped": false, "booms": [], "boomed": false, "air": [], "end_t": 99.0, "cf": Bal.v("ult/ir_cut", 0.6), "shot_t": 0.0, "smear_t": 0.0}


static func _irv_step(u, a: Dictionary, o) -> bool:
	var t: float = a.t
	var c: Vector2 = a.c
	var R: float = a.R
	var vs: float = a.vs
	# ① 定罪
	if not a.stamped and t >= 0.1:
		a.stamped = true
		u.g.vfx.stop(0.05, "ult", true)   # 局部顿一下
		u.light(c, R * 0.5, IRV_GOLD, 2.0 if _irv3() else 0.25)   # 用户 10-31「灯火的快速闪动让画面有闪烁感」：第三版只留这一盏、2 秒慢慢暗下去，其余短灯都不点
		PF.dust(u, c, 260.0, 0.0, vs, Vector2.ZERO, Color(0.6, 0.58, 0.55))
		var n := 0
		for e in u.in_circle(c, R):
			_once(u, a, o, a.wseg, e, Bal.v("ult/ir_wind_f", 0.1), {"src": "定罪", "pre": true, "edge": e.pos.distance_to(c) > float(a.rc)})
			if e.dead:
				continue
			if not e.boss:
				u.g.enemies_sys.add_cc(e, Bal.v("ult/ir_lift", 1.2) * (0.5 if e.elite else 1.0))   # 钉住（原来是挑飞浮空，同时长）
			var pin := {"e": e, "d": e.pos.distance_to(c), "chain": {}}
			if n < 18 and _irv2():   # 用户 10-31 改表现：锁链从纹章外圈一根根射出、绷直扎到怪身上（链节沿线逐节伸出 0.12 秒），扎中处金色碎光
				var rim: Vector2 = c + (e.pos - c).normalized() * R * 0.97 if e.pos.distance_to(c) > 1.0 else c + Vector2.RIGHT * R
				pin["rim"] = rim
				pin["links"] = _irv_chain(u, rim, e.pos + Vector2(0, -10), 0.02 * (n % 6))
				PF.particles(u, e.pos + Vector2(0, -10), 60, "ult_burst_s", [IRV_GOLD, IRV_WHITE], 0.12 + 0.02 * (n % 6), vs + n * 3.0, 40.0)
			elif n < 18:   # 锁链至多 18 根（伤害照打每一个）
				var nm := PF.pick(u, IRV_CHAIN, vs * 0.3 + n * 1.7)
				if nm != "":
					var tex: Texture2D = u._strip_tex(nm)
					var side: float = -1.0 if PF.h(vs + n) < 0.5 else 1.0
					pin.chain = u.strip(nm, e.pos + Vector2(-26.0 * side, 10.0), {"o": Vector2(0.0 if side > 0.0 else tex.get_width(), tex.get_height()), "sx": side,
						"sc": 70.0 / PF.tex_w(u, nm), "rev": 0.06, "rev0": 0.0, "life": 1.6, "fade": 0.2, "col": Color(1.05, 1.05, 1.1), "delay": 0.01 * (n % 5)})
				PF.particles(u, e.pos + Vector2(0, 6), 60, "ult_burst_s", [IRV_WHITE, Color(0.55, 0.6, 0.7)], 0.0, vs + n * 3.0, 40.0)
			n += 1
			a.pins.append(pin)
		a.pins.sort_custom(func(x, y): return float(x.d) < float(y.d))
	for pn in a.pins:   # 链子末端跟着被锁的怪（被推挤时链子绷着跟）
		if pn.has("links") and not pn.e.dead and not pn.get("done", false):
			_irv_chain_follow(pn.links, Vector2(pn.rim), pn.e.pos + Vector2(0, -10))
	# ② 行刑：旋风转身
	var t0: float = 0.18
	var T: float = 0.6
	if _irv3() and t >= t0 and t < t0 + T:
		_irv_shuttle(u, a, o, (t - t0) / T)
	elif t >= t0 and t < t0 + T:
		var k: float = (t - t0) / T
		var th: float = float(a.spins) * TAU * (k * (1.2 - 0.2 * k))   # 起手猛、尾段略收
		o.face_to(th)
		if int(th / PI) != int(a.get("half", -1)):
			a["half"] = int(th / PI)
			o.play_vis_anim("attack")
		if t >= float(a.smear_t):   # 脚下 smear 弧跟着转（每 0.08 秒一片，转着淡）
			a.smear_t = t + 0.08
			var nm2 := PF.pick(u, IRV_SMEAR, vs * 0.5 + t * 13.0)
			if nm2 != "":
				var rr2: float = PF.tex_w(u, nm2) * 0.5
				var big: float = 1.6 if _irv2() else 1.0   # 用户 10-31 改表现：刀弧加大 + 外面再套一层反向的暗弧
				u.strip(nm2, c + Vector2(0, -6), {"layer": "back", "sc": 150.0 * big / rr2, "sc1": 175.0 * big / rr2, "scd": 0.12, "ang": th, "spin": 30.0, "life": 0.14, "fade": 0.08,
					"col": Color(0.78, 0.84, 0.95, 0.8)})   # 预审：旋斩中心别发白
				if _irv2():
					u.strip(nm2, c + Vector2(0, -6), {"layer": "back", "sc": 300.0 / rr2, "sc1": 340.0 / rr2, "scd": 0.12, "ang": th + 2.0, "spin": 26.0, "sx": -1.0, "life": 0.12, "fade": 0.08,
						"col": Color(0.4, 0.5, 0.72, 0.55)})
					for q in 3:   # 放射速度线：刀扫过的方向甩出三道细冷光
						var sv := Vector2.from_angle(th + q * 0.35)
						u.shape({"kind": "blade", "a": c + sv * 90.0, "b": c + sv * (200.0 + 80.0 * PF.h(t * 7.0 + q)), "w": 2.0, "col": IRV_WHITE, "glow": IRV_NAVY, "life": 0.07, "v": sv * 900.0})
		if t >= float(a.shot_t):   # 手铳朝四周连射：短曳光 + 枪口火光
			a.shot_t = t + 0.08
			var sd: Vector2 = Vector2.from_angle(th + 1.3 + (PF.h(t * 31.0) - 0.5) * 0.6)
			if _irv2() and not a.pins.is_empty():   # 用户 10-31 改表现：子弹真打到被锁的怪身上（金色细曳光一闪到目标 + 命中碎光）
				var pk: Dictionary = a.pins[int(PF.h(t * 17.0) * a.pins.size()) % a.pins.size()]
				if not pk.e.dead:
					sd = (pk.e.pos - c).normalized()
					var mz2: Vector2 = c + Vector2(0, -22) + sd * 26.0
					u.shape({"kind": "blade", "a": mz2, "b": pk.e.pos + Vector2(0, -12), "w": 2.0, "col": IRV_GOLD, "glow": IRV_NAVY, "life": 0.05})
					PF.particles(u, pk.e.pos + Vector2(0, -12), 20, "ult_burst_s", [IRV_GOLD], 0.0, t * 41.0, 24.0)
			var mz: Vector2 = c + Vector2(0, -22) + sd * 26.0
			u.shape({"kind": "blade", "a": mz, "b": mz + sd * 70.0, "w": 2.0, "col": IRV_GOLD, "glow": IRV_NAVY, "life": 0.05, "v": sd * 1600.0})
			PF.particles(u, mz, 20, "ult_burst_s", [IRV_GOLD], 0.0, t * 53.0, 16.0)
		for e in u.in_circle(c, R):   # 第一圈：刀扫过谁斩谁
			if a.cseg.has(int(e.id)):
				continue
			var fa: float = fposmod((e.pos - c).angle(), TAU) / TAU
			if fa <= minf(1.0, k * float(a.spins)):
				_once(u, a, o, a.cseg, e, float(a.cf), {"src": "行刑", "pre": true, "edge": e.pos.distance_to(c) > float(a.rc)})
				if e.dead and a.cseg.size() % 3 == 0:
					PF.particles(u, e.pos, 30, "ult_burst_s", [IRV_WHITE, IRV_NAVY], 0.0, float(e.id), 30.0)
	if t >= t0 + T and not a.has("spun"):
		a["spun"] = true
		o.play_vis_anim("attack")
		if _irv3():   # 穿梭完瞬身回纹章中心
			u.shape({"kind": "blade", "a": o.pos, "b": c, "w": 4.0, "col": IRV_WHITE, "glow": IRV_NAVY, "life": 0.12})
			_lead_move(u, o, c)
			_lead_land(u, o)
		for e in u.in_circle(c, R):   # 收刀前扫漏的补斩（刀扫过时还没进圈的）
			_once(u, a, o, a.cseg, e, float(a.cf), {"src": "行刑", "pre": true, "edge": e.pos.distance_to(c) > float(a.rc)})
	# ③ 收尾：由近到远连环炸开
	var tb: float = 0.85
	if t >= tb and not a.boomed:
		a.boomed = true
		var pins: Array = a.pins
		for e in u.in_circle(c, R):   # 圈里后进来、没钉住的也要炸（份额同原手炮）
			var has := false
			for pn in pins:
				if pn.e == e:
					has = true
					break
			if not has:
				pins.append({"e": e, "d": e.pos.distance_to(c), "chain": {}})
		pins.sort_custom(func(x, y): return float(x.d) < float(y.d))
		for i in pins.size():
			pins[i]["tb"] = tb + 0.4 * float(pins[i].d) / R
		a["end_t"] = tb + 0.4 + 0.3
	if a.boomed:
		for pn in a.pins:
			if pn.get("done", false) or t < float(pn.tb):
				continue
			pn["done"] = true
			var e: Dictionary = pn.e
			var bp: Vector2 = e.pos if not e.dead else pn.get("last", e.pos)
			var fr: float = Bal.v("ult/ir_boom", 0.35) * (1.0 if float(pn.d) <= R * 0.5 else Bal.v("ult/ir_boom_out", 0.6))
			_once(u, a, o, a.bseg, e, fr, {"src": "宣判", "edge": float(pn.d) > float(a.rc)})   # 第一下（非 pre）= 冲击帧
			var hh: float = PF.h(vs + float(pn.d))
			if _irv2():   # 用户 10-31 改表现：每一炸更大更实——金白爆团 + 烟尘 + 地块崩起；链子崩成链节飞散
				PF.particles(u, bp, 200, "ult_burst", [Color(0.8, 0.66, 0.38), Color(0.45, 0.52, 0.7)], 0.0, vs + float(pn.d), 90.0 + 40.0 * hh)   # 预审：连环爆叠起来发白，压暗一档
				PF.dust(u, bp, 120.0, 0.03, vs + float(pn.d) * 0.1, Vector2.ZERO, Color(0.6, 0.58, 0.56))
				PF.aftershock(u, bp, 50.0, vs + float(pn.d), 0.02, 3, Color(0.75, 0.72, 0.7))
				if int(pn.d) % 3 == 0 and not _irv3():
					u.light(bp, 130.0, IRV_GOLD, 0.15)
				if pn.has("links"):
					_irv_chain_break(pn.links, Vector2(pn.rim), bp, vs + float(pn.d))
			else:
				PF.particles(u, bp, 120, "ult_burst_s", [IRV_GOLD, IRV_NAVY], 0.0, vs + float(pn.d), 60.0 + 30.0 * hh)
				if int(pn.d) % 2 == 0:
					PF.dust(u, bp, 90.0, 0.04, vs + float(pn.d) * 0.1, Vector2.ZERO, Color(0.7, 0.72, 0.78))
				u.light(bp, 120.0, IRV_WHITE, 0.15)
			var ch: Dictionary = pn.chain
			if not ch.is_empty():   # 锁链断：链子 0.1 秒内淡掉、迸几颗链节碎片
				ch.max = float(ch.age) + 0.1
				PF.particles(u, bp + Vector2(0, -10), 30, "ult_burst_s", [Color(0.6, 0.65, 0.75), IRV_GOLD], 0.0, vs + float(pn.d) * 2.0, 45.0)
		if t >= float(a.end_t) - 0.3 and not a.has("shatter"):
			a["shatter"] = true   # 纹章碎裂：金色分叉裂纹从中心炸开 + 纹章快淡 + 大光 + 金白粒子
			var s: Dictionary = a.seal
			if _irv3() and Bal.v("ult/ir_final_cut", 1.0) > 0.0:   # 用户 10-31「最后接一个斩击暴烈」
				_irv_final_cut(u, c, R, vs)
			if not s.is_empty() and _irv3():   # 用户 10-31「纹章改成缓慢消失，而不是被切碎」：1.4 秒慢慢冷下去、淡掉
				s["col"] = s.get("col1", s.get("col", Color.WHITE))
				s.erase("col1")
				s.max = float(s.age) + 1.4
				s["fade"] = 1.4
			elif not s.is_empty() and _irv2():   # 用户 10-31 改表现：纹章本体碎成 7 条竖片，各自往外崩飞、转着落地淡掉
				_irv_shatter(u, s, c, vs)
				s.max = float(s.age)
			elif not s.is_empty():
				s.max = float(s.age) + 0.25
			var cl_l: Array = []
			for j in 8:   # 纹章碎裂：细、短、长短悬殊的金色裂纹，亮一下很快冷掉（粗长的会像树根）
				cl_l.append(R * (0.3 + 0.35 * PF.h(vs + j * 4.3)))
			if not _irv2():
				PF.cracks(u, IRV_FORKS, c, PF.angles(8, PF.h(vs) * TAU, vs), cl_l, {"seed": vs, "r0": 40.0, "rev": 0.15, "rev0": 0.2, "life": 0.9, "fade": 0.5,
				"big": 0.45, "small": 0.3, "col": Color(1.0, 0.86, 0.5), "col1": Color(0.3, 0.3, 0.34, 0.6), "cold": 0.35})
			PF.particles(u, c, 300, "ult_burst", [Color(0.85, 0.7, 0.4)], 0.0, vs, R * 0.5)   # 深蓝粒子团放大后成一块平的蓝圆盘，只留暗金
			if not _irv3():
				PF.aftershock(u, c, R * 0.7, vs, 0.05, 10, Color(0.75, 0.72, 0.7))   # 纹章碎块崩起
			if not _irv3():
				u.light(c, R * 0.6, IRV_GOLD, 0.25)
	return a.boomed and t >= float(a.end_t)


## ---- 「宣判」行刑第三版（用户 10-31「从旋风连斩改成在纹章内来回穿梭斩击，最后爆炸」；开关 ult/ir_verdict3 缺省 1，0 = 旋风连斩）：
## 0.6 秒里她在纹章内来回瞬身穿梭 6 刀（狂飙路线 8 刀）：落点在纹章 0.78 R 圈上按星形跳（每刀转 ~0.62 圈，来回交错），每刀一道冷白细斩线贯穿全程 +
## 刀口迸冷白 / 深蓝粒子 + 沿线一撮金色碎光 + 起落两端尘；结算同旋风版（按刀扫过的方位角先后斩到每只，0.6 份额），穿梭完瞬身回中心，接连环爆
static func _irv3() -> bool:
	return Bal.v("ult/ir_verdict3", 1.0) > 0.0


static func _irv_shuttle(u, a: Dictionary, o, k: float) -> void:
	var c: Vector2 = a.c
	var R: float = a.R
	var vs: float = a.vs
	var nd: int = 8 if int(a.spins) >= 4 else 6
	var j: int = mini(nd - 1, int(k * nd))
	if j != int(a.get("dash", -1)):
		a["dash"] = j
		var a0: float = PF.h(vs) * TAU + j * TAU * 0.62
		var np: Vector2 = c + Vector2.from_angle(a0 + (PF.h(vs + j) - 0.5) * 0.4) * R * (0.65 + 0.2 * PF.h(vs + j * 3.0))
		var fp: Vector2 = o.pos
		var dv: Vector2 = (np - fp).normalized() if np != fp else Vector2.RIGHT
		u.shape({"kind": "blade", "a": fp - dv * 30.0, "b": np + dv * 40.0, "w": 6.0, "col": IRV_WHITE, "glow": IRV_NAVY, "grow": 0.03, "life": 0.28})   # 斩线
		u.shape({"kind": "blade", "a": fp, "b": np, "w": 2.0, "col": IRV_GOLD, "glow": IRV_NAVY, "life": 0.4})   # 留下的金丝
		for q in 3:
			PF.particles(u, fp.lerp(np, (q + 0.5) / 3.0), 40, "ult_burst_s", [IRV_WHITE, IRV_NAVY], 0.02 * q, vs + j * 7.0 + q, 50.0)
		PF.dust(u, np + Vector2(0, 8), 80.0, 0.0, vs + j, -dv * 60.0, Color(0.62, 0.64, 0.7))
		_lead_move(u, o, np)
		o.face_to(dv.angle())
		o.play_vis_anim("attack")
	for e in u.in_circle(c, R):   # 结算同旋风版：按方位角先后斩到
		if a.cseg.has(int(e.id)):
			continue
		var fa: float = fposmod((e.pos - c).angle(), TAU) / TAU
		if fa <= minf(1.0, k * float(a.spins)):
			_once(u, a, o, a.cseg, e, float(a.cf), {"src": "行刑", "pre": true, "edge": e.pos.distance_to(c) > float(a.rc)})


## 收尾斩击爆裂：连环爆之后一刀横贯整个纹章（冷白主刃 + 金色细刃 + 深蓝宽影，0.05 秒划开），斩线上从中心往两端接连炸开 7 团金白爆 + 烟尘；顿帧 0.06；
## 不点短灯（用户嫌闪）。只有画面，伤害 / 时长不变（图形在终结技结束后自己播完）
static func _irv_final_cut(u, c: Vector2, R: float, vs: float) -> void:
	var dv := Vector2.from_angle(PF.h(vs + 77.0) * PI)
	u.g.vfx.stop(0.06, "ult", true)
	u.shape({"kind": "blade", "a": c - dv * R * 1.15, "b": c + dv * R * 1.15, "w": 22.0, "col": Color(0.35, 0.45, 0.7), "glow": IRV_NAVY, "grow": 0.05, "life": 0.45})
	u.shape({"kind": "blade", "a": c - dv * R * 1.1, "b": c + dv * R * 1.1, "w": 10.0, "col": IRV_WHITE, "glow": IRV_NAVY, "grow": 0.05, "life": 0.35})
	u.shape({"kind": "blade", "a": c - dv * R * 1.05, "b": c + dv * R * 1.05, "w": 3.0, "col": IRV_GOLD, "glow": IRV_GOLD, "grow": 0.05, "life": 0.6})
	for i in 7:
		var x: float = (float(i) - 3.0) / 3.0
		var bp: Vector2 = c + dv * R * x * 0.95 + dv.orthogonal() * (PF.h(vs + i) - 0.5) * 30.0
		var dl: float = 0.08 + 0.04 * absf(x) * 3.0
		PF.particles(u, bp, 200, "ult_burst", [Color(0.85, 0.72, 0.42), Color(0.5, 0.58, 0.78)], dl, vs + i * 9.0, 110.0 + 30.0 * PF.h(vs + i * 2.0))
		PF.dust(u, bp, 110.0, dl + 0.03, vs + i * 3.0, dv.orthogonal() * (60.0 if i % 2 == 0 else -60.0), Color(0.62, 0.62, 0.66))
	var sfx: Node = u.g.get_node_or_null("/root/Sfx") if u.g.is_inside_tree() else null
	if sfx != null:
		sfx.play("boom", -1.0, 1.1)


## ---- 「宣判」表现第二版（用户 10-31「纹章没问题，后面的表现形式需要改」：锁链 / 旋风 / 连环爆 / 碎裂四段都改；开关 ult/ir_verdict2 缺省 1，0 = 第一版）
const IRV_LINK := "fx_ulpianus_chain_tile"   # 链节（乌尔比安锚链那张，染金）


static func _irv2() -> bool:
	return Bal.v("ult/ir_verdict2", 1.0) > 0.0


## 从 a 往 b 逐节铺链节（每节晚 0.012 秒出现 = 链子射出去），返回链节列表（跟随 / 断裂用）
static func _irv_chain(u, a: Vector2, b: Vector2, d0: float) -> Array:
	var out: Array = []
	if not u.fx_ready(IRV_LINK):
		return out
	var arr: Array = u.tiles_line(IRV_LINK, a, b, {"life": 1.8, "fade": 0.2, "col": Color(2.4, 1.9, 1.0), "sc": 1.2, "f": 0})   # 链节原图是暗青，乘亮成金
	var L0: float = maxf(1.0, a.distance_to(b))
	for i in arr.size():
		arr[i].age = -(d0 + 0.012 * i)
		arr[i]["sx0"] = float(arr[i].get("sx", 1.0))
		arr[i]["L0"] = L0
		out.append(arr[i])
	return out


## 链子末端跟着怪：各节按比例重新摆、角度 / 拉伸跟着改
static func _irv_chain_follow(links: Array, a: Vector2, b: Vector2) -> void:
	var n: int = links.size()
	if n == 0:
		return
	var L: float = a.distance_to(b)
	var ang: float = (b - a).angle()
	for i in n:
		var s: Dictionary = links[i]
		s.c = a.lerp(b, float(i) / n)
		s.ang = ang
		s.sx = float(s.sx0) * L / maxf(1.0, float(s.L0))


## 链子断：每节带一点往外的速度 + 重力 + 转，0.4 秒淡掉
static func _irv_chain_break(links: Array, a: Vector2, b: Vector2, sd: float) -> void:
	var n: int = links.size()
	for i in n:
		var s: Dictionary = links[i]
		var k: float = float(i) / maxf(1.0, float(n))
		var dv: Vector2 = ((b - a).normalized().orthogonal() * (PF.h(sd + i) - 0.5) * 2.0 + (b - a).normalized() * k).normalized()
		s["v"] = dv * (120.0 + 160.0 * PF.h(sd + i * 3.0)) + Vector2(0, -120.0)
		s["grav"] = 900.0
		s["spin"] = (PF.h(sd + i * 5.0) - 0.5) * 12.0
		s.max = float(s.age) + 0.4
		s["fade"] = 0.3


## 纹章碎裂：把纹章贴图按 7 条竖片切开（ux / uw），每片放回原位，往外崩飞、转着落地、淡掉
static func _irv_shatter(u, s: Dictionary, c: Vector2, vs: float) -> void:
	var t: Texture2D = u._strip_tex(IRV_SEAL)
	var W: float = t.get_width()
	var H: float = t.get_height()
	var sc: float = float(s.get("sc1", s.get("sc", 1.0)))
	var wk: float = PF.tex_w(u, IRV_SEAL) / W * sc   # 1 纹素 = 多少世界
	var ang: float = float(s.get("ang", 0.0))
	var m := 7
	for k in m:
		var ux: float = floorf(W * k / m)
		var uw: float = floorf(W * (k + 1) / m) - ux
		var xw: float = (ux + uw * 0.5 - W * 0.5) * wk
		var pc: Vector2 = c + Vector2(xw, 0.0).rotated(ang)
		var out: Vector2 = (pc - c).normalized() if pc.distance_to(c) > 1.0 else Vector2.from_angle(PF.h(vs + k) * TAU)
		var hh: float = PF.h(vs + k * 2.3)
		u.strip(IRV_SEAL, pc, {"layer": "back", "sc": sc, "ang": ang, "o": Vector2(uw * 0.5, H * 0.5), "ux": ux, "uw": uw,
			"v": out * (160.0 + 140.0 * hh) + Vector2(0, -60.0), "grav": 260.0, "spin": (hh - 0.5) * 2.4, "life": 0.8, "fade": 0.5,
			"col": Color(1.15, 1.05, 0.85, 0.7), "col1": Color(0.6, 0.6, 0.66, 0.4), "cold": 0.35})


# ================================================================ 拉普兰德（§4.19）：原地狂舞连斩，4 圈双刃十字剑气向四面八方飞出，命中沉默

static func _la_start(u, o) -> Dictionary:
	var rt := _route(o)
	var n: int = 5 if rt == "rage" else 4
	var gap: float = 0.2 if rt == "rage" else Bal.v("ult/la_gap", 0.25)
	var segs: Array = []
	var wd: Array = []
	for i in n:
		segs.append({})
		wd.append(false)
	var R: float = Bal.v("ult/la_r", 502.0)
	return {"c": o.pos, "R": R, "rc": R * Bal.v("ult/la_core", 0.872), "n": n, "gap": gap, "fly": Bal.v("ult/la_fly", 0.24), "f": 1.0 / n,
		"segs": segs, "wd": wd, "fired": 0, "bark": rt == "bark"}


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
	while int(a.fired) < n and t >= gap * int(a.fired):
		_la_wave(u, a, o, int(a.fired))
		a.fired = int(a.fired) + 1
	var c: Vector2 = a.c
	for i in int(a.fired):
		var el: float = t - gap * i
		if a.wd[i]:
			continue
		if el >= fly:
			a.wd[i] = true   # 剑气飞到 R 的那一帧必扫一次（帧长较粗时不会从外缘漏过去）
		var fr: float = lerpf(40.0, R, clampf(el / fly, 0.0, 1.0))
		var bark: bool = a.bark and i == n - 1
		for e in u.in_circle(c, fr + 16.0):
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
