## 圣聆初雪转平面（docs/403 §9，fx/px_plane = 1）：fx_pxplane.gd 按 id 转来的一节。全部运行时逐美术像素画（2 世界像素格、15 fps 统一节拍），不烤帧条。
## 照原作 sbell2.ab（tools/ref_fx/rebuild_prefab.py 回放，关键帧在主仓库 Claude outputs/sbell2_ref/）：
##   开阵命中 buff_01_hit_01：白色羽刺一闪 → 多面冰晶 + 四芒白星 → 碎成扁冰片飘散；
##   S1 skill_01_start_01：横吹风雪 + 一串「∩」白色风弧往前推；S2 skill_02_buff_01：斜向一束冰风；
##   冻结 frozen：宝蓝多面冰块；免死 revive：冰晶柱包住本体 + 暗铜小十字 + 扁冰片飞散。
## 配色取 PRTS 立绘：发银白（亮芯）、斗篷浅蓝 / 宝蓝、内衬深海军蓝（冷却色）、铃铛暗铜（点缀）。
## 只画：读玩法状态（o.gn.sb）与事件，不写玩法状态、不取玩法随机数（画面散布用哈希）。
extends RefCounted

const Pxp = preload("res://scripts/render/fx_pxplane.gd")
const Bal = preload("res://scripts/core/balance.gd")

const WH := Color("#dcecff")      # 银白亮芯（亮度封顶 0.9 以内）
const IC := Color("#9fd8ff")      # 斗篷浅蓝
const SA := Color("#3a78d8")      # 斗篷宝蓝
const NV := Color("#16234a")      # 内衬海军蓝（冷却 / 暗边）
const BE := Color("#a07a4a")      # 铃铛暗铜（点缀）
const BE2 := Color("#d2a964")     # 铃铛高光（一拍）

const HIT_CAP := 8      # 一次开阵至多画几处冰晶爆
const ICE_CAP := 24     # 同屏至多几个冰封块
const FX_MAX := 160

var _parent: WeakRef
var r:
	get:
		return _parent.get_ref()
var g
var _fx: Array = []       # 一次性件：{k, oid, t0, …}
var _ice: Dictionary = {}  # 敌人 id → {e, t0, t1, sd}（冰封块）
var _beat := {}
var _ult := {}            # 终结技：oid → {c, R, t0, plates, ts}


func _init(px) -> void:
	_parent = weakref(px)
	g = px.g


static func _h(x: float) -> float:
	var v: float = sin(x * 12.9898) * 43758.5453
	return v - floor(v)


func _beat_n(o, k: String) -> int:
	var b: int = int(floor(g.t * 15.0))
	var key: String = str(o.id) + k
	var e = _beat.get(key)
	if e == null or int(e[0]) != b:
		_beat[key] = [b, 1]
		return 1
	e[1] = int(e[1]) + 1
	return int(e[1])


func _add(o, it: Dictionary) -> void:
	it["oid"] = str(o.id)
	if not it.has("t0"):
		it["t0"] = g.t
	it["sd"] = float(it.get("sd", _h(g.t * 7.3 + float(_fx.size()) * 1.37)))
	_fx.append(it)
	if _fx.size() > FX_MAX:
		_fx.pop_front()


func _fr(it: Dictionary) -> int:
	return r.frame_of(float(it.t0))


func _sb(o) -> Dictionary:
	var gn = o.get("gn")
	if gn is Dictionary and gn.has("sb"):
		return gn.sb
	return {}


func _s2_on(o) -> bool:
	return o.s_t[1] > 0.0 or o.perm_on[1]


# ================================================================ 事件

func ev(o, kind: String, d: Dictionary, t: int, R, _p: Dictionary) -> void:
	match kind:
		"shape":   # 开阵（普攻）：每个被打中的敌人身上一个冰晶爆；手上铃铛一闪
			if str(d.get("src", "")) != "开阵":
				return
			var es: Array = d.get("es", [])
			var n := 0
			for e in es:
				if e == null or n >= HIT_CAP:
					break
				n += 1
				_add(o, {"k": "xb", "p": e.pos + Vector2(0, -float(e.r) * 0.4), "gy": float(e.pos.y) + 2.0, "t": t, "s3": o.s_t[2] > 0.0, "sd": _h(float(e.id) * 0.71 + g.t)})
			var bp: Vector2 = o.pos + Vector2(10.0 * (1.0 if float(o.face) >= 0.0 else -1.0), -30)
			_add(o, {"k": "ring_b", "p": bp, "gy": float(o.pos.y) + 1.0, "t": t})
			R._light(o, o.pos, 120.0 if t < 2 else 150.0, 0.32, 0.18, IC)
			if t >= 2:
				R._grains(o, bp, float(o.pos.y) + 2.0, "twinkle", 2, {"c0": WH, "c1": IC})
		"sb_bell":   # 精一铃落：暗铜小铃落到敌人脚下
			var ps: Array = d.get("ps", [])
			for i in mini(ps.size(), 6):
				_add(o, {"k": "bell", "p": ps[i], "gy": float((ps[i] as Vector2).y) + 1.0, "t0": g.t + 0.06 * i})
		"sb_step":   # 踏雪：2 粒冰屑
			var e2 = d.get("e")
			if e2 == null or _beat_n(o, "step") > 3:
				return
			R._grains(o, e2.pos + Vector2(0, -2), float(e2.pos.y) + 2.0, "shard", 2, {"c0": IC, "c1": WH})
		"sb_break":   # 一格雪被踏碎：冰屑落地
			if _beat_n(o, "brk") > 2:
				return
			var c: Vector2 = d.get("c", o.pos)
			R._grains(o, c, c.y + 6.0, "shard", 2 + int(d.get("n", 1)) / 2, {"c0": WH, "c1": SA})
		"sb_blast":   # S1 铃音吹雪：一下（第二下另一个事件）
			_add(o, {"k": "gust", "p": d.p, "ang": float(d.ang), "r": float(d.r), "half": float(d.half), "t": t})
			R._light(o, d.p + Vector2.from_angle(float(d.ang)) * float(d.r) * 0.4, 160.0, 0.35, 0.25, IC)
			var n2 := 0
			for e3 in d.get("es", []):
				if e3 == null or n2 >= 6:
					break
				n2 += 1
				_add(o, {"k": "xb", "p": e3.pos + Vector2(0, -float(e3.r) * 0.4), "gy": float(e3.pos.y) + 2.0, "t": mini(t, 1), "small": true, "t0": g.t + 0.05 + 0.02 * n2, "sd": _h(float(e3.id) * 0.37 + g.t)})
		"skill":
			var i: int = int(d.get("i", -1))
			if i == 1:
				_add(o, {"k": "s2go", "p": o.pos, "gy": float(o.pos.y) + 1.0, "t": t})
				R._light(o, o.pos, 150.0, 0.4, 0.4, IC)
			elif i == 2:
				_add(o, {"k": "curl", "p": o.pos, "r": float(o.base("s3_pull_r", 280.0)) * o.stat(&"op_range"), "t": t})
				R._light(o, o.pos, 200.0, 0.4, 0.5, SA)
		"sb_wave":   # 精二霜涛：只记一下时刻，浪峰在地面层按雪格画
			R._light(o, o.pos, 110.0, 0.25, 0.3, IC)
		"sb_freeze":
			var e4 = d.get("e")
			if e4 == null or e4.dead:
				return
			var id: int = int(e4.id)
			var secs: float = float(d.get("s", 1.0))
			if _ice.has(id):
				_ice[id].t1 = maxf(float(_ice[id].t1), g.t + secs)
				return
			if _ice.size() >= ICE_CAP:
				return
			_ice[id] = {"e": e4, "t0": g.t, "t1": g.t + secs, "sd": _h(float(id) * 0.913), "oid": str(o.id)}
		"sb_bless":   # 天赋免死：冰壳包住队长 bless_self 秒，到点碎开
			var dur: float = float(d.get("dur", 2.0))
			_add(o, {"k": "shell", "life": dur + 0.6, "dur": dur})
			R._light(o, g.ppos, 180.0, 0.5, dur, IC)
		"sb_shatter":   # 凝冰之阵（节点 5A）：S2 结束时满地碎裂（借冰晶爆）
			pass
		"sb_ult_go":
			_ult_go(o, d)
		"sb_ult_shatter":
			var u: Dictionary = _ult.get(str(o.id), {})
			if not u.is_empty():
				u["ts"] = g.t
				R._light(o, u.c, 240.0, 0.45, 0.5, IC)
				for k in 10:
					var a: float = TAU * _h(float(k) * 1.7 + float(u.sd))
					var pp: Vector2 = u.c + Vector2.from_angle(a) * float(u.R) * (0.2 + 0.7 * _h(float(k) * 3.1))
					R._grains(o, pp, pp.y + 8.0, "shard", 2, {"c0": WH, "c1": IC}, Vector2.from_angle(a))


# ================================================================ 生命周期

const LIFE := {"xb": 0.55, "ring_b": 0.27, "bell": 0.45, "gust": 0.6, "s2go": 0.6, "curl": 0.7, "shell": 2.6, "ishard": 0.4}


func _alive(it: Dictionary) -> bool:
	var life: float = float(it.get("life", LIFE.get(str(it.k), 0.3)))
	return g.t - float(it.t0) < life + 0.02


func _gc() -> void:
	_fx = _fx.filter(func(it): return _alive(it))
	var gone: Array = []
	for id in _ice:
		var ic: Dictionary = _ice[id]
		var e = ic.e
		if e == null or e.dead or g.t >= float(ic.t1):
			gone.append(id)
			if e != null:   # 冰封结束 / 敌人倒下：碎成扁冰片
				_fx.append({"k": "ishard", "oid": ic.oid, "t0": g.t, "p": e.pos + Vector2(0, -float(e.r) * 0.5), "gy": float(e.pos.y) + 2.0, "w": float(e.r) * 1.2, "sd": float(ic.sd)})
	for id in gone:
		_ice.erase(id)
	for k in _ult.keys():
		if g.t - float(_ult[k].t0) > 3.5:
			_ult.erase(k)


# ================================================================ 地面层

func draw_floor(o) -> void:
	_gc()
	var cv = o.cv
	var id: String = str(o.id)
	var st := _sb(o)
	if not st.is_empty() and not (st.get("wave", {}) as Dictionary).is_empty():
		_crest(cv, o, st)
	for it in _fx:
		if str(it.oid) != id or g.t < float(it.t0):
			continue
		match str(it.k):
			"curl":
				_curl(cv, it)
	var u: Dictionary = _ult.get(id, {})
	if not u.is_empty():
		_ult_floor(cv, u)


func draw_over(o) -> void:
	var cv = o.cv
	var id: String = str(o.id)
	if o.pos != Vector2.INF and _s2_on(o):
		_s2_motes(cv, o)
	for it in _fx:
		if str(it.oid) != id or g.t < float(it.t0):
			continue
		match str(it.k):
			"gust":
				_gust(cv, it)
			"s2go":
				_s2go(cv, it)
			"shell":
				_shell(cv, it)
	var u: Dictionary = _ult.get(id, {})
	if not u.is_empty():
		_ult_over(cv, u)


## 立起层：冰晶爆、铃、冰封块、碎冰片
func sort_items(o, out: Array) -> void:
	var id: String = str(o.id)
	for it in _fx:
		if str(it.oid) != id or g.t < float(it.t0):
			continue
		match str(it.k):
			"xb", "ring_b", "bell", "ishard":
				out.append({"sbrt": str(it.k), "it": it, "o": o, "gy": float(it.get("gy", (it.p as Vector2).y + 1.0)) + 16.0})
	for eid in _ice:
		var ic: Dictionary = _ice[eid]
		if str(ic.oid) != id or ic.e == null or ic.e.dead:
			continue
		out.append({"sbrt": "ice", "it": ic, "o": o, "gy": float(ic.e.pos.y) + 3.0})


func draw_rt(ci, it: Dictionary) -> void:
	match str(it.sbrt):
		"xb":
			_xb(ci, it.it)
		"ring_b":
			_bellflash(ci, it.it)
		"bell":
			_bell(ci, it.it)
		"ice":
			_iceblock(ci, it.it)
		"ishard":
			_ishard(ci, it.it)


# ================================================================ 画法基础

var _hfc = null   # 冲击帧剪影色（draw_hf 期间所有像素画成这一色）


func _P(ci, p: Vector2, c: Color) -> void:
	if _hfc != null:
		var q: Vector2 = Pxp._snap(p)
		var e: float = g.PX
		ci.tb_quad(q, q + Vector2(e, 0), q + Vector2(e, e), q + Vector2(0, e), _hfc)
		return
	r._px(ci, p, c)


## 像素线：按 2 格步进逐格画（th = 1 / 2 格粗）
func _L(ci, a: Vector2, b: Vector2, c: Color, th := 1) -> void:
	var px: float = g.PX
	var n: int = maxi(1, int(ceil(a.distance_to(b) / px)))
	var nrm: Vector2 = (b - a).orthogonal().normalized() * px if th > 1 else Vector2.ZERO
	for i in n + 1:
		var q: Vector2 = a.lerp(b, float(i) / float(n))
		_P(ci, q, c)
		if th > 1:
			_P(ci, q + nrm, c)


## 实心多边形（顶点对齐像素格）
func _poly(ci, pts: PackedVector2Array, c: Color) -> void:
	var s := PackedVector2Array()
	for p in pts:
		s.append(Pxp._snap(p))
	if _hfc != null:
		ci.tb_polygon(s, _hfc)
		return
	if s.size() >= 3 and c.a > 0.0:
		ci.draw_colored_polygon(s, c)


## 多边形描边
func _outline(ci, pts: PackedVector2Array, c: Color, th := 1) -> void:
	for i in pts.size():
		_L(ci, pts[i], pts[(i + 1) % pts.size()], c, th)


## 四芒星：中心 2×2 亮芯 + 四条臂（臂长 len 格，越外越暗）
func _star4(ci, p: Vector2, ln: int, c0: Color, c1: Color) -> void:
	var px: float = g.PX
	_P(ci, p, c0)
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		for i in range(1, ln + 1):
			_P(ci, p + d * px * i, c0 if i <= ln / 2 else c1)


static func _fade(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * clampf(a, 0.0, 1.0))


## 不规则多面冰晶轮廓：n 个顶点，半径按哈希 0.7–1.0 抖、角度错开；竖向拉长 sy
func _crystal_pts(p: Vector2, rad: float, n: int, sd: float, sy := 1.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a: float = TAU * (float(i) + 0.35 * (_h(sd * 9.1 + i) - 0.5)) / float(n) - PI * 0.5
		var rr: float = rad * (0.7 + 0.3 * _h(sd * 5.3 + i * 1.9))
		out.append(p + Vector2(cos(a) * rr, sin(a) * rr * sy))
	return out


# ================================================================ 开阵 · 冰晶爆（原作 buff_01_hit_01）

## 第 0 拍：白羽刺（精二换三道弯爪痕）→ 1–3 拍：多面冰晶 + 四芒星 → 4–7 拍：裂成 3 片扁冰片往外飘、冷却成海军蓝
func _xb(ci, it: Dictionary) -> void:
	var f: int = _fr(it)
	var t: int = int(it.get("t", 1))
	var sd: float = float(it.sd)
	var p: Vector2 = it.p
	var s: float = (20.0 if t < 2 else 28.0) * (0.75 if it.get("small", false) else 1.0) * (1.2 if it.get("s3", false) else 1.0)
	var px: float = g.PX
	if f <= 0:
		if t >= 2 and not it.get("small", false):   # 精二：三道弯爪痕（原作 hit_01 首帧的白色弯刺）
			for k in 3:
				var a0: float = -0.9 + 0.45 * k + 0.2 * (_h(sd * 3.0 + k) - 0.5)
				var c0: Vector2 = p + Vector2(-s * 0.3, s * 0.2)
				var prev := Vector2.INF
				for j in 7:
					var u: float = float(j) / 6.0
					var q: Vector2 = c0 + Vector2.from_angle(a0 + (u - 0.5) * 1.3) * (s * 0.95) + Vector2(u * s * 0.5, -u * s * 0.4)
					if prev != Vector2.INF:
						_L(ci, prev, q, WH if j < 5 else IC, 2 if j > 1 and j < 5 else 1)
					prev = q
		else:   # 白色羽刺 4 根（角度、长度按哈希错开，不放射规整）
			for k in 4:
				var a: float = TAU * (float(k) + 0.6 * (_h(sd * 7.7 + k) - 0.5)) / 4.0 + sd * 3.0
				var ln: float = s * (0.6 + 0.5 * _h(sd * 2.3 + k))
				_L(ci, p, p + Vector2.from_angle(a) * ln * 0.55, WH, 2)
				_L(ci, p + Vector2.from_angle(a) * ln * 0.55, p + Vector2.from_angle(a) * ln, IC, 1)
		return
	if f <= 3:
		var k2: float = 1.0 if f >= 2 else 0.8
		var pts := _crystal_pts(p, s * 0.55 * k2, 6, sd, 1.15)
		_poly(ci, pts, Color(IC.r, IC.g, IC.b, 1.0 if f < 3 else 0.75))
		var core := PackedVector2Array([pts[5], pts[0], pts[1], p + Vector2(-px, px)])   # 左上受光面（银白）
		_poly(ci, core, WH)
		_poly(ci, PackedVector2Array([pts[2], pts[3], pts[4], p + Vector2(px, 0)]), SA)   # 右下背光面（宝蓝）
		_outline(ci, pts, NV, 2)
		if f <= 2 and t < 2 or f == 1:
			_star4(ci, pts[1] + Vector2(px, 0), 3 if t < 2 else 4, WH, IC)
		return
	if f <= 7:
		var k3: float = float(f - 3) / 4.0
		for j in 3:
			var a2: float = TAU * (float(j) / 3.0 + 0.25 * _h(sd * 4.4 + j)) - PI * 0.5
			var d: float = s * (0.3 + 0.9 * (1.0 - (1.0 - k3) * (1.0 - k3)))
			var q2: Vector2 = p + Vector2.from_angle(a2) * d + Vector2(0, k3 * k3 * 6.0)
			var w: float = s * 0.28 * (1.0 - 0.4 * k3)
			var c: Color = IC.lerp(NV, k3)
			var pl := PackedVector2Array([q2 + Vector2(-w, 0), q2 + Vector2(0, -w * 0.5), q2 + Vector2(w, 0), q2 + Vector2(0, w * 0.5)])
			_poly(ci, pl, _fade(c, 1.0 - k3 * 0.6))


## 手上铃铛一闪：暗铜铃身 + 一拍高光 + 小四芒星
func _bellflash(ci, it: Dictionary) -> void:
	var f: int = _fr(it)
	var p: Vector2 = it.p
	_bell_icon(ci, p, BE2 if f <= 1 else BE)
	if f <= 1:
		_star4(ci, p + Vector2(0, -6), 3 if int(it.t) < 2 else 4, WH, IC)


## 5 × 5 小铃（2 格一像素）
func _bell_icon(ci, p: Vector2, c: Color) -> void:
	var px: float = g.PX
	for q in [Vector2i(0, -2), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(-2, 1), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(0, 2)]:
		_P(ci, p + Vector2(q) * px, c)


## 精一铃落：小铃从上方落下（3 拍）→ 落地一闪（白 2 拍）
func _bell(ci, it: Dictionary) -> void:
	var f: int = _fr(it)
	var p: Vector2 = it.p
	if f <= 2:
		_bell_icon(ci, p + Vector2(0, -16.0 + 6.0 * f), BE)
		return
	if f <= 4:
		_bell_icon(ci, p + Vector2(0, -2), BE2 if f == 3 else BE)
		_P(ci, p + Vector2(-6, 0), WH)
		_P(ci, p + Vector2(6, 0), WH)
		if f == 3:
			_star4(ci, p + Vector2(0, -4), 2, WH, IC)


# ================================================================ 冰封块（原作 frozen：宝蓝多面冰块）

func _iceblock(ci, ic: Dictionary) -> void:
	var e = ic.e
	var er: float = float(e.r)
	var sd: float = float(ic.sd)
	var age: float = g.t - float(ic.t0)
	var grow: float = clampf(age / 0.12, 0.25, 1.0)
	var w: float = maxf(10.0, er * 1.15)
	var hgt: float = maxf(14.0, er * 1.7) * grow
	var base: Vector2 = e.pos + Vector2(0, er * 0.35)
	var top: Vector2 = base + Vector2(0, -hgt)
	var pts := PackedVector2Array([
		base + Vector2(-w * (0.85 + 0.2 * _h(sd)), 0), base + Vector2(-w, -hgt * (0.45 + 0.15 * _h(sd * 2.0))),
		top + Vector2(-w * 0.4, hgt * 0.05), top + Vector2(w * (0.1 + 0.2 * _h(sd * 3.0)), 0),
		base + Vector2(w * 0.95, -hgt * (0.6 + 0.15 * _h(sd * 4.0))), base + Vector2(w * (0.8 + 0.2 * _h(sd * 5.0)), 0)])
	_poly(ci, pts, Color(SA.r, SA.g, SA.b, 0.42))
	_poly(ci, PackedVector2Array([pts[1], pts[2], pts[3], base + Vector2(-w * 0.1, -hgt * 0.5)]), Color(IC.r, IC.g, IC.b, 0.42))   # 受光面
	_L(ci, pts[2], base + Vector2(-w * 0.1, -hgt * 0.5), WH)
	_L(ci, base + Vector2(-w * 0.1, -hgt * 0.5), pts[5], IC)
	_outline(ci, pts, IC)
	var left: float = float(ic.t1) - g.t
	if left < 0.25 and int(floor(g.t * 15.0)) % 2 == 0:   # 快碎：边一闪一闪
		_outline(ci, pts, WH)


## 冰封碎：3–4 片扁冰片往外落
func _ishard(ci, it: Dictionary) -> void:
	var k: float = clampf((g.t - float(it.t0)) / 0.4, 0.0, 1.0)
	var p: Vector2 = it.p
	var w: float = float(it.w)
	var sd: float = float(it.sd)
	for j in 4:
		var a: float = -PI * 0.5 + (float(j) - 1.5) * 0.9 + 0.4 * (_h(sd * 6.0 + j) - 0.5)
		var q: Vector2 = p + Vector2.from_angle(a) * w * (0.3 + 1.1 * k) + Vector2(0, 40.0 * k * k)
		var s: float = maxf(3.0, w * 0.3 * (1.0 - 0.5 * k))
		_poly(ci, PackedVector2Array([q + Vector2(-s, 0), q + Vector2(0, -s * 0.6), q + Vector2(s, 0), q + Vector2(0, s * 0.6)]), _fade(IC.lerp(NV, k), 1.0 - k * 0.5))


# ================================================================ 精二霜涛：沿雪格的冰浪峰（没雪处断开）

func _crest(cv, o, st: Dictionary) -> void:
	var w: Dictionary = st.wave
	var b: Dictionary = st.get("b", {})
	var T: float = float(b.get("wave_t", 0.6))
	var R: float = float(b.get("wave_r", 240.0)) * o.stat(&"op_range")
	var k: float = clampf(float(w.t) / T, 0.0, 1.0)
	var wr: float = R * k
	if wr < 16.0:
		return
	var cs: float = float(b.get("cell", 42.0))
	var c: Vector2 = w.c
	var cells: Dictionary = st.cells
	var px: float = g.PX
	var fade: float = 1.0 - maxf(0.0, k - 0.75) * 3.0
	for key in cells:
		var cc: Vector2 = Vector2((float(key.x) + 0.5) * cs, (float(key.y) + 0.5) * cs)
		var dd: float = cc.distance_to(c)
		if absf(dd - wr) > cs * 0.75:
			continue
		var hh: float = _h(float(key.x) * 1.3 + float(key.y) * 7.1)
		if hh < 0.35:
			continue   # 雪铺满时也断开（不连成整圈，docs/407 F14）
		var a0: float = (cc - c).angle()
		var span: float = cs * 0.62 / maxf(wr, 1.0) * (0.6 + 0.5 * _h(hh * 13.0))
		var rr: float = wr + (hh - 0.5) * 16.0
		var n: int = maxi(3, int(span * rr / px))
		for i in n + 1:
			var a: float = a0 - span + 2.0 * span * float(i) / float(n)
			var q: Vector2 = c + Vector2.from_angle(a) * rr
			var jit: float = 2.0 * sin(float(i) * 1.7 + hh * 9.0)
			_P(cv, q + Vector2(0, -jit), _fade(WH, fade))
			_P(cv, q + Vector2.from_angle(a) * -px + Vector2(0, -jit), _fade(IC, fade))
			if i % 2 == 0:
				_P(cv, q + Vector2.from_angle(a) * -px * 2.0 + Vector2(0, -jit), _fade(SA, fade * 0.8))


# ================================================================ S1 铃音吹雪（原作 skill_01_start_01：「∩」风弧 + 横吹雪粒）

func _gust(cv, it: Dictionary) -> void:
	var age: float = g.t - float(it.t0)
	var t: int = int(it.t)
	var R: float = float(it.r)
	var half: float = float(it.half)
	var ang: float = float(it.ang)
	var sd: float = float(it.sd)
	var p: Vector2 = it.p + Vector2(0, -16)
	var dir: Vector2 = Vector2.from_angle(ang)
	var nrm: Vector2 = dir.orthogonal()
	var px: float = g.PX
	var n_arc: int = 3 + t
	var passes: int = 2 if t >= 1 else 1
	for ps in passes:
		var a_age: float = age - 0.12 * ps
		if a_age < 0.0:
			continue
		var k: float = clampf(a_age / 0.42, 0.0, 1.0)
		var ke: float = 1.0 - (1.0 - k) * (1.0 - k)
		for i in n_arc:
			var hi: float = _h(sd * 2.0 + float(i) * 1.37 + ps * 5.0)   # 每道弧各自的宽窄 / 远近 / 起步（不排成一排一样的弧）
			var ki: float = clampf((a_age - 0.07 * _h(hi * 9.0)) / 0.42, 0.0, 1.0)
			var kei: float = 1.0 - (1.0 - ki) * (1.0 - ki)
			var off: float = ((float(i) + 0.5) / float(n_arc) - 0.5) * 2.0 * half * 0.8 + 0.3 * (_h(sd * 5.0 + i + ps * 3.0) - 0.5) * half
			var dist: float = R * (0.15 + 0.85 * kei) * (0.6 + 0.55 * hi) * (0.8 if ps == 1 else 1.0)
			var ctr: Vector2 = p + Vector2.from_angle(ang + off) * dist
			var wdt: float = (16.0 + 8.0 * t) * (0.65 + 0.7 * _h(hi * 3.3)) * (1.0 - 0.3 * k) * (0.8 if ps == 1 else 1.0)
			var hgt: float = (10.0 + 4.0 * t) * (0.7 + 0.6 * _h(hi * 5.1)) * (1.0 - 0.4 * k)
			var col_f: Color = WH.lerp(IC, k)
			var col_b: Color = IC.lerp(SA, k)
			var al: float = 1.0 - maxf(0.0, k - 0.6) * 2.5
			if al <= 0.0:
				continue
			# 「∩」：沿法线方向展开的一道拱（拱顶朝外 = 风推出去的方向）
			var prev := Vector2.INF
			var m: int = maxi(6, int(wdt / px))
			for j in m + 1:
				var u: float = float(j) / float(m) * 2.0 - 1.0
				var q: Vector2 = ctr + nrm * u * wdt + dir * hgt * (1.0 - u * u)
				if prev != Vector2.INF:
					var thick: int = 3 if absf(u) < 0.5 else (2 if absf(u) < 0.85 else 1)   # 拱顶厚、两脚细
					_L(cv, prev, q, _fade(col_f, al), 2)
					for z in range(2, 2 + thick * 2):
						_P(cv, q - dir * px * float(z), _fade(col_b if z < 2 + thick else SA, al * 0.95))
				prev = q
				if t >= 2 and j % 3 == 1 and absf(u) < 0.8:   # 精二：拱顶外沿一排冰牙
					var tip: Vector2 = q + dir * (5.0 + 3.0 * _h(sd + j))
					_L(cv, q, tip, _fade(WH, al), 1)
	# 横吹雪粒：长条，越飞越快变淡
	var kk: float = clampf(age / 0.5, 0.0, 1.0)
	for s in 8 + 2 * t:
		var off2: float = (2.0 * _h(sd * 11.0 + s) - 1.0) * half * 0.9
		var d0: float = R * (0.1 + 0.3 * _h(sd * 13.0 + s))
		var d1: float = d0 + R * 1.0 * kk * (0.7 + 0.5 * _h(sd * 17.0 + s))
		var q0: Vector2 = p + Vector2.from_angle(ang + off2) * d1
		var al2: float = 1.0 - kk
		if al2 <= 0.05:
			continue
		_L(cv, q0, q0 - Vector2.from_angle(ang + off2) * (6.0 + 6.0 * kk), _fade(WH if s % 3 == 0 else IC, al2), 1)


# ================================================================ S2 霜涛覆岭（原作 skill_02_buff_01：斜向冰风；常驻：斜飘雪点）

func _s2go(cv, it: Dictionary) -> void:
	var k: float = clampf((g.t - float(it.t0)) / 0.6, 0.0, 1.0)
	var ke: float = 1.0 - (1.0 - k) * (1.0 - k)
	var p: Vector2 = it.p + Vector2(0, -30)
	var sd: float = float(it.sd)
	var big: float = 1.0 if int(it.t) < 2 else 1.4
	var al: float = 1.0 - maxf(0.0, k - 0.5) * 2.0
	for i in 7:
		var a: float = -PI * 0.25 + (float(i) - 3.0) * 0.16 + 0.1 * (_h(sd * 3.0 + i) - 0.5)
		if i % 2 == 1:
			a += PI   # 原作是斜着一束往两头冲
		var ln: float = (26.0 + 22.0 * _h(sd * 7.0 + i)) * big * (0.4 + 0.8 * ke)
		var st: Vector2 = p + Vector2.from_angle(a) * (6.0 + 10.0 * ke)
		var en: Vector2 = st + Vector2.from_angle(a) * ln
		var nrm: Vector2 = Vector2.from_angle(a).orthogonal() * (3.0 * big)
		_poly(cv, PackedVector2Array([st + nrm, en, st - nrm]), _fade(IC.lerp(SA, k), al))
		_L(cv, st, st.lerp(en, 0.7), _fade(WH, al), 1)


## 永续期间：身边雪点斜飘上升（原作 skill_02_buff 余段），精二夹两颗四芒小星
func _s2_motes(cv, o) -> void:
	var t: int = r.tier(o)
	var p: Vector2 = o.pos
	var n: int = 5 if t < 2 else 7
	for i in n:
		var ph: float = fmod(g.t * 0.6 + _h(float(i) * 3.7), 1.0)
		var x0: float = (_h(float(i) * 5.1) - 0.5) * 50.0
		var q: Vector2 = p + Vector2(x0 + ph * 22.0, -6.0 - ph * 52.0)
		var al: float = sin(ph * PI)
		if t >= 2 and i >= 5:
			if ph > 0.2 and ph < 0.6:
				_star4(cv, q, 2, _fade(WH, al), _fade(IC, al))
			continue
		_P(cv, q, _fade(WH if i % 2 == 0 else IC, al))


## S3 起手：往里卷的风弧（反向的「∩」），从 pull_r 收到她身边
func _curl(cv, it: Dictionary) -> void:
	var k: float = clampf((g.t - float(it.t0)) / 0.7, 0.0, 1.0)
	var ke: float = k * k
	var p: Vector2 = it.p + Vector2(0, -10)
	var R: float = float(it.r)
	var sd: float = float(it.sd)
	var px: float = g.PX
	var al: float = 1.0 - maxf(0.0, k - 0.7) * 3.3
	for i in 6:
		var a: float = TAU * (float(i) + 0.4 * (_h(sd * 2.0 + i) - 0.5)) / 6.0 + k * 1.2
		var dist: float = lerpf(R, 70.0, ke)
		var dir: Vector2 = Vector2.from_angle(a)
		var nrm: Vector2 = dir.orthogonal()
		var ctr: Vector2 = p + dir * dist
		var wdt: float = 22.0 * (1.0 - 0.4 * k)
		var prev := Vector2.INF
		var m: int = maxi(6, int(wdt / px))
		for j in m + 1:
			var u: float = float(j) / float(m) * 2.0 - 1.0
			var q: Vector2 = ctr + nrm * u * wdt - dir * 10.0 * (1.0 - u * u)
			if prev != Vector2.INF:
				_L(cv, prev, q, _fade(WH.lerp(IC, k), al), 2 if absf(u) < 0.5 else 1)
			prev = q


# ================================================================ 天赋免死「圣山的祝福」（原作 revive：冰晶柱包住本体 → 冰片飞散）

func _shell(cv, it: Dictionary) -> void:
	var age: float = g.t - float(it.t0)
	var dur: float = float(it.dur)
	var p: Vector2 = g.ppos
	var sd: float = float(it.sd)
	var px: float = g.PX
	var W := 26.0
	var H := 74.0
	var pts := PackedVector2Array([p + Vector2(-W, 4), p + Vector2(-W - 4, -H * 0.55), p + Vector2(-W * 0.4, -H), p + Vector2(W * 0.5, -H - 6),
		p + Vector2(W + 3, -H * 0.5), p + Vector2(W, 4)])
	if age < dur:
		var grow: float = clampf(age / 0.18, 0.0, 1.0)
		if grow < 1.0:   # 冰从脚下往上包
			for i in pts.size():
				pts[i] = Vector2(pts[i].x, p.y + (pts[i].y - p.y) * grow)
		# 内部只抖动低透明（≤ 0.25），亮度靠边与照地光
		var y0: float = minf(pts[2].y, pts[3].y)
		var yy: float = p.y - px
		while yy > y0:
			var xx: float = p.x - W
			while xx < p.x + W:
				var ix: int = int(xx / px)
				var iy: int = int(yy / px)
				if (ix + iy) % 3 == 0:
					_P(cv, Vector2(xx, yy), Color(IC.r, IC.g, IC.b, 0.22))
				xx += px
			yy -= px * 2.0
		_outline(cv, pts, WH, 2)
		_L(cv, pts[2], p + Vector2(-4, -H * 0.35), IC)   # 两道棱
		_L(cv, pts[3], p + Vector2(6, -H * 0.3), IC)
		_L(cv, p + Vector2(-4, -H * 0.35), p + Vector2(6, -H * 0.3), SA)
		for j in 3:   # 零星暗铜小十字（原作 revive 的暗金点）
			var ph: float = fmod(g.t * 1.3 + _h(sd * 3.0 + j), 1.0)
			var q: Vector2 = p + Vector2((_h(sd * 5.0 + j) - 0.5) * W * 1.4, -12.0 - H * 0.8 * _h(sd * 7.0 + j))
			if ph < 0.5:
				_P(cv, q, BE2)
				_P(cv, q + Vector2(px, 0), BE)
				_P(cv, q - Vector2(px, 0), BE)
				_P(cv, q + Vector2(0, px), BE)
				_P(cv, q - Vector2(0, px), BE)
		if dur - age < 0.3 and int(floor(g.t * 15.0)) % 2 == 0:   # 快碎：裂缝一闪
			_L(cv, p + Vector2(-W * 0.6, -H * 0.2), p + Vector2(4, -H * 0.55), WH, 1)
			_L(cv, p + Vector2(4, -H * 0.55), p + Vector2(W * 0.5, -H * 0.8), WH, 1)
		return
	# 碎开：8 片扁冰片往外炸（缓出 + 少量重力）
	var k: float = clampf((age - dur) / 0.6, 0.0, 1.0)
	var ke: float = 1.0 - (1.0 - k) * (1.0 - k)
	for j in 8:
		var a: float = TAU * (float(j) + 0.5 * (_h(sd * 9.0 + j) - 0.5)) / 8.0
		var q2: Vector2 = p + Vector2(0, -H * 0.45) + Vector2.from_angle(a) * (10.0 + 90.0 * ke) + Vector2(0, 30.0 * k * k)
		var s: float = (7.0 + 5.0 * _h(sd + j)) * (1.0 - 0.3 * k)
		var rot: float = a + k * 4.0 * (_h(sd * 2.0 + j) - 0.5)
		var d1: Vector2 = Vector2.from_angle(rot) * s
		var d2: Vector2 = Vector2.from_angle(rot + PI * 0.5) * s * 0.45
		_poly(cv, PackedVector2Array([q2 - d1, q2 - d2, q2 + d1, q2 + d2]), _fade(IC.lerp(NV, k), 1.0 - k * 0.7))
		_L(cv, q2 - d1, q2 - d2, _fade(WH, 1.0 - k), 1)


# ================================================================ 终结技「千分之一的心」（run/ult_sb.gd 发事件）
## 摇铃 → 冰面由内向外冻结（泰森多边形冰板：只画亮缝 + 低透明抖动）→ 静止、冰缝从中心亮起、往里一吸 →
## 冲击帧（剪影 = 冰缝网）→ 冰板往外炸（缓出外飞 + 旋转 + 迎镜头变大 + 少量重力）→ 淡出，留满层雪地（玩法）

const ULT_FREEZE0 := 0.3
const ULT_FREEZE1 := 0.9
const ULT_CRACK := 1.05
const ULT_SHATTER := 1.2


func _ult_go(o, d: Dictionary) -> void:
	var c: Vector2 = d.c
	var R: float = float(d.R)
	var sd: float = _h(g.t * 3.1 + c.x * 0.013)
	# 种子：越近中心越密（半径按 u^1.4 取），外圈一圈稀
	var seeds: Array = []
	var n := 38
	for i in n:
		var u: float = _h(sd * 17.0 + float(i) * 1.618)
		var rr: float = R * pow(u, 1.4) * 1.02
		var a: float = TAU * _h(sd * 29.0 + float(i) * 2.399)
		seeds.append(c + Vector2.from_angle(a) * rr)
	seeds.append(c)
	var border := PackedVector2Array()
	for i in 28:
		var a2: float = TAU * float(i) / 28.0
		border.append(c + Vector2.from_angle(a2) * R * (0.94 + 0.1 * _h(sd * 41.0 + i)))
	var plates: Array = []
	for i in seeds.size():
		var poly: PackedVector2Array = border
		var si: Vector2 = seeds[i]
		for j in seeds.size():
			if i == j:
				continue
			var sj: Vector2 = seeds[j]
			if si.distance_squared_to(sj) > (R * 1.1) * (R * 1.1):
				continue
			poly = _clip_half(poly, (si + sj) * 0.5, (sj - si).normalized())
			if poly.size() < 3:
				break
		if poly.size() < 3:
			continue
		var ctr := Vector2.ZERO
		for q in poly:
			ctr += q
		ctr /= float(poly.size())
		var local := PackedVector2Array()
		for q in poly:
			local.append(q - ctr)
		plates.append({"c": ctr, "pts": local, "d": ctr.distance_to(c), "sp": (_h(sd * 7.0 + i) - 0.5) * 3.0, "v": 0.35 + 0.4 * _h(sd * 13.0 + i)})
	_ult[str(o.id)] = {"c": c, "R": R, "t0": g.t, "plates": plates, "ts": -1.0, "sd": sd}


## 半平面裁剪（Sutherland–Hodgman）：保留 (q - m)·n <= 0 一侧
static func _clip_half(poly: PackedVector2Array, m: Vector2, nrm: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var cnt: int = poly.size()
	for i in cnt:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % cnt]
		var da: float = (a - m).dot(nrm)
		var db: float = (b - m).dot(nrm)
		if da <= 0.0:
			out.append(a)
		if (da <= 0.0) != (db <= 0.0):
			out.append(a.lerp(b, da / (da - db)))
	return out


## 一块冰板此刻的顶点（世界坐标）：冻结前不画；吸气往中心收；炸开后外飞 / 转 / 变大 / 下坠
func _plate_pts(u: Dictionary, pl: Dictionary, t: float) -> PackedVector2Array:
	var c: Vector2 = u.c
	var ctr: Vector2 = pl.c
	var sc := 1.0
	var rot := 0.0
	if t >= ULT_CRACK and t < ULT_SHATTER:
		var k: float = (t - ULT_CRACK) / (ULT_SHATTER - ULT_CRACK)
		ctr = c + (ctr - c) * (1.0 - 0.035 * k)   # 往里一吸
		sc = 1.0 - 0.03 * k
	elif t >= ULT_SHATTER:
		var k2: float = clampf(_fly_age(u) / 0.75, 0.0, 1.0)
		if _fly_age(u) <= 0.0:   # 冲击帧还没来：停在吸气收尾的位置
			ctr = c + (ctr - c) * 0.965
			sc = 0.97
		var ke: float = 1.0 - pow(1.0 - k2, 3.0)
		var dir: Vector2 = (ctr - c).normalized() if ctr.distance_to(c) > 1.0 else Vector2.UP
		var near: float = 1.0 - clampf(float(pl.d) / float(u.R), 0.0, 1.0)
		ctr = ctr + dir * float(u.R) * float(pl.v) * (0.6 + 0.6 * near) * ke + Vector2(0, 70.0 * k2 * k2)
		rot = float(pl.sp) * ke
		sc = 1.0 + 0.35 * ke
	var out := PackedVector2Array()
	var xf := Transform2D(rot, Vector2(sc, sc), 0.0, ctr)
	for q in pl.pts:
		out.append(xf * (q as Vector2))
	return out


func _ult_t(u: Dictionary) -> float:
	return g.t - float(u.t0)


## 冰板飞散的时钟：从冲击帧第一拍（draw_hf 记下）起算；冲击帧没画（减少动态 / 关冲击帧）时按碎裂后 0.25 游戏秒起
func _fly_age(u: Dictionary) -> float:
	var f0: float = float(u.get("fly", -1.0))
	if f0 < 0.0:
		var ts: float = float(u.get("ts", -1.0))
		if ts < 0.0 or g.t - ts < 0.25:
			return 0.0
		f0 = ts + 0.25
		u["fly"] = f0
	return maxf(0.0, g.t - f0)


## 地面层：冻结中的冰面（亮缝 + 低透明抖动），冻结前沿一段段断续冰峰
func _ult_floor(cv, u: Dictionary) -> void:
	var t: float = _ult_t(u)
	if t < ULT_FREEZE0 or t >= ULT_SHATTER:
		return
	var c: Vector2 = u.c
	var R: float = float(u.R)
	var rf: float = R * clampf((t - ULT_FREEZE0) / (ULT_FREEZE1 - ULT_FREEZE0), 0.0, 1.0)
	var crack_r: float = R * clampf((t - ULT_CRACK) / (ULT_SHATTER - ULT_CRACK), 0.0, 1.0) if t >= ULT_CRACK else -1.0
	for pl in u.plates:
		if float(pl.d) > rf:
			continue
		var pts := _plate_pts(u, pl, t)
		var age: float = (t - ULT_FREEZE0) - float(pl.d) / R * (ULT_FREEZE1 - ULT_FREEZE0)
		_poly(cv, pts, Color(IC.r, IC.g, IC.b, 0.16 if age > 0.1 else 0.28))   # 刚冻上那一拍亮一点
		var lit: bool = crack_r >= 0.0 and float(pl.d) <= crack_r
		_outline(cv, pts, WH if lit else (IC if age < 0.12 else SA), 1)
	# 冻结前沿：一段段断续冰峰（不画整圈）
	if t < ULT_FREEZE1 + 0.05 and rf > 20.0:
		var px: float = g.PX
		var nseg: int = 22
		for i in nseg:
			if _h(float(u.sd) * 5.0 + i) < 0.3:
				continue
			var a0: float = TAU * float(i) / float(nseg)
			var span: float = TAU / float(nseg) * 0.7
			var m: int = maxi(3, int(span * rf / px))
			for j in m + 1:
				var a: float = a0 + span * float(j) / float(m)
				var q: Vector2 = c + Vector2.from_angle(a) * (rf + 6.0 * (_h(float(u.sd) * 3.0 + i) - 0.5))
				_P(cv, q, WH)
				_P(cv, q - Vector2.from_angle(a) * px, IC)
				_P(cv, q - Vector2.from_angle(a) * px * 2.0, SA)


## 上层：摇铃（铃 + 四芒星）；炸开后飞散的冰板
func _ult_over(cv, u: Dictionary) -> void:
	var t: float = _ult_t(u)
	if t < 0.35:
		var p: Vector2 = u.c + Vector2(0, -74)
		_bell_icon(cv, p, BE2 if int(floor(g.t * 15.0)) % 2 == 0 else BE)
		_star4(cv, p + Vector2(0, -8), 4 if t < 0.15 else 3, WH, IC)
	if t < ULT_SHATTER:
		return
	var k: float = clampf(_fly_age(u) / 0.75, 0.0, 1.0)
	if k >= 1.0:
		return
	for pl in u.plates:
		var pts := _plate_pts(u, pl, t)
		var al: float = 1.0 - maxf(0.0, k - 0.45) / 0.55
		_shard(cv, pts, k, al)


## 一片有厚度的冰：实心浅蓝（不透明度 0.6）+ 往左上偏的银白受光面 + 左上亮边 / 右下宝蓝暗边各 2 格
func _shard(cv, pts: PackedVector2Array, k: float, al: float) -> void:
	var ctr := Vector2.ZERO
	for q in pts:
		ctr += q
	ctr /= float(pts.size())
	_poly(cv, pts, _fade(IC.lerp(SA, k * 0.8), 0.45 * al))
	var hi := PackedVector2Array()
	for q in pts:
		hi.append(ctr + (q - ctr) * 0.55 + Vector2(-3, -3))
	_poly(cv, hi, _fade(WH, 0.35 * al))
	for i in pts.size():
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		var lit: bool = ((a + b) * 0.5 - ctr).dot(Vector2(-1, -1)) > 0.0
		_L(cv, a, b, _fade(WH if lit else SA, al), 2)


## 冲击帧（ult_draw._draw_hit_frame 转来）：剪影 = 冰缝网（冰板描边，加粗），不画实心整片
func draw_hf(_uv, w, col: Color) -> void:
	for oid in _ult:
		var u: Dictionary = _ult[oid]
		if float(u.get("fly", -1.0)) < 0.0:
			u["fly"] = g.t   # 冰板从冲击帧这一拍起往外炸
		_hfc = col
		for pl in u.plates:
			var pts := _plate_pts(u, pl, ULT_SHATTER - 0.001)
			for i in pts.size():
				var a: Vector2 = pts[i]
				var b: Vector2 = pts[(i + 1) % pts.size()]
				_L(w, a, b, col, 2)
		_hfc = null
