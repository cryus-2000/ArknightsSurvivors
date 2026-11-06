## 羁绊技 v2 画面（docs/294；玩法在 run/bond2.gd，开关 link/bond_v2）。只画：不读写玩法字段、不抽玩法随机数（颗粒走 fx_recipe 的 g.vrng）。
## 画法和转平面（docs/246，render/fx_pxplane.gd）同一套：1 特效像素 = 1 美术像素（g.PX 世界像素、对齐 2 像素格）、15 fps 全局节拍换帧、
## 色层当普通物体画进单位排序（吃场景光），最亮的热芯进光学发光层（共用转平面的 EMIT_CAP），命中挂 ≤ 0.15 秒的照地光、Noita 颗粒。
## 斩线 = 德克萨斯「一刀一道」（_tx_draw_line1）的画法：芯近白（前两拍过曝）、两侧一格角色色、两头收尖，hold 拍后断成碎段收掉。
## 角色定稿色：德克萨斯琥珀 TX_C（docs/257）、拉普兰德淡紫 LP（docs/273）、能天使红橙 RAMP.n（docs/262）、艾丽妮白 + 亮紫 LT（docs/272）、流明钢蓝 LM_C（docs/255）。
## 每招元素 ≤ 3 种（第二版，docs/296）：宿敌 = 两人残影 + 交锋星芒 + 散开的冲击波；企鹅物流 = 车（运行时生成贴图）+ 车顶曳光 + 胎痕；灯下审决 = 灯塔虚像（运行时生成贴图）+ 暖金光锥 + 紫印。
## 地面件（航线虚线、光圈、冲击环）排序键压到最前（画在所有单位下面）；立起件（斩线、曳光、落剑、光针）按最低点 y 排进单位层。
## 演出卡（解锁 / 精二强化）画在 HUD（hud.gd 调 draw_hud）。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const UI = preload("res://scripts/ui.gd")
const B2 = preload("res://scripts/run/bond2.gd")

## 7 阶（暗 → 白）
const TX := [Color("#2c1406"), Color("#5a2808"), Color("#9c4610"), Color("#e2781c"), Color("#ffac3c"), Color("#ffdc9c"), Color("#ffffff")]
const LP := [Color("#15121f"), Color("#2b2542"), Color("#4a4274"), Color("#7b70b4"), Color("#b3aae4"), Color("#e4e0ff"), Color("#ffffff")]
const EX := [Color("#2a100c"), Color("#5c2418"), Color("#a8402a"), Color("#f07048"), Color("#ffa880"), Color("#ffe0cc"), Color("#ffffff")]
const IR := [Color("#1a0c28"), Color("#3a1a58"), Color("#6a32a0"), Color("#9d58e0"), Color("#cf98ff"), Color("#f0e2ff"), Color("#ffffff")]
const LM := [Color("#121a2a"), Color("#1d3150"), Color("#2a5282"), Color("#4285ad"), Color("#7fb2d6"), Color("#c4e0f2"), Color("#ffffff")]
const PALS := {"texas": TX, "lappland": LP, "exusiai": EX, "irene": IR, "lumen": LM}
const LIFT := 24.0        # 斩线离地高度（同德克萨斯 TX_H）
const SQ := 0.72          # 地面圈压扁（同艾丽妮提灯光圈）
const GROUND_KEY := -1.0e9
const ITEM_MAX := 160

var g
var items: Array = []      # {k, t0, life, …}
var due: Array = []        # [t, kind, data]：到点挂照地光 / 颗粒
var cards: Array = []      # [{bid, ops:[a, b], t0, e2}]


static func of(game):
	if game.has_meta("fx_bond2"):
		return game.get_meta("fx_bond2")
	var r = new()
	r.g = game
	game.set_meta("fx_bond2", r)
	return r


func _px():
	return load("res://scripts/render/fx_pxplane.gd").of(g)


func _R():
	return load("res://scripts/render/fx_recipe.gd").of(g)


static func _snap(v: Vector2) -> Vector2:
	return (v / 2.0).round() * 2.0


func _push(it: Dictionary) -> void:
	if items.size() >= ITEM_MAX:
		items.pop_front()
	items.append(it)


func _beat(t0: float) -> int:
	return int(floor(g.t * 15.0)) - int(floor(t0 * 15.0))


func _glow(p: Vector2, c: Color) -> void:
	if not g.optical_on:
		return
	var r = _px()
	var fr: int = Engine.get_process_frames()
	if fr != r._emit_frame:
		r._emit_frame = fr
		r._emit_n = 0
	if r._emit_n >= 360:
		return
	r._emit_n += 1
	g.glow_next.append([_snap(p), g.PX, Color(c.r, c.g, c.b, Bal.v("fx/px_plane_emit", 0.8))])


func _cell(ci, p: Vector2, c: Color) -> void:
	ci.draw_rect(Rect2(_snap(p), Vector2(g.PX, g.PX)), c)


# ================================================================ 事件（bond2.gd 调）

func cast(a: Dictionary) -> void:
	var t: float = g.t
	var c: Vector2 = a.c
	match str(a.id):
		"b_rival":   # 对砍（docs/296）：两人残影相向冲上 → 刀锋相交定格 → 冲击波向四周散开
			var tx = a.who.texas
			var lp = a.who.lappland
			_ghost(tx, c + Vector2(-380, 10), c + Vector2(-30, 10), t, 0.42, TX)
			_ghost(lp, c + Vector2(380, 10), c + Vector2(30, 10), t, 0.42, LP)
			_push({"k": "ghost", "op": tx, "a": c + Vector2(-30, 10), "b": c + Vector2(-30, 10), "t0": t + 0.42, "dur": 0.6, "pal": TX, "up": 0.0, "life": 0.95, "fr": -2, "flip": false})
			_push({"k": "ghost", "op": lp, "a": c + Vector2(30, 10), "b": c + Vector2(30, 10), "t0": t + 0.42, "dur": 0.6, "pal": LP, "up": 0.0, "life": 0.95, "fr": -2, "flip": true})
			_push({"k": "clash", "c": c + Vector2(0, -30), "t0": t + 0.45, "life": 0.2})
			_push({"k": "shock", "c": c, "t0": t + 0.6, "rmax": float(a.rmax), "life": 0.8})
			due.append([t + 0.45, "light", {"o": tx, "p": c, "r": 150.0, "i": 0.8, "c": Color(1.0, 0.9, 0.85), "life": 0.1}])
			due.append([t + 0.47, "grains", {"o": tx, "p": c + Vector2(-8, -20), "n": 10, "c0": TX[5], "c1": TX[3]}])
			due.append([t + 0.47, "grains", {"o": lp, "p": c + Vector2(8, -20), "n": 10, "c0": LP[5], "c1": LP[3]}])
			due.append([t + 0.65, "grains", {"o": tx, "p": c, "n": 12, "c0": Color(0.55, 0.58, 0.62), "c1": Color(0.3, 0.32, 0.36), "mat": "dust"}])
		"b_penguin":   # 开车：车身 + 车顶能天使 + 驾驶位德克萨斯 + 胎痕；扫射曳光由 shots() 逐发加
			_push({"k": "car", "s": a.s, "dl": a.dl, "len": float(a.len), "t0": t, "T0": 0.15, "T1": 1.25, "ex": a.who.exusiai, "tx": a.who.texas, "life": 1.45})
			_push({"k": "skid", "s": a.s, "dl": a.dl, "len": float(a.len), "t0": t, "T0": 0.15, "T1": 1.25, "life": 2.4})
			for i in 11:
				var u: float = float(i) / 10.0
				due.append([t + 0.15 + 1.1 * u, "grains", {"o": a.who.texas, "p": Vector2(a.s) + Vector2(a.dl) * float(a.len) * u - Vector2(a.dl) * 60.0, "n": 3, "c0": Color(0.5, 0.52, 0.56), "c1": Color(0.28, 0.3, 0.34), "mat": "dust"}])
		"b_inq":   # 灯塔照海：灯塔虚像 + 旋转光锥 + 扫到的紫印；艾丽妮残影追着光锥
			_push({"k": "lh", "O": a.O, "t0": t, "life": 1.65, "ang0": float(a.ang0), "ang1": float(a.ang1), "R": float(a.R)})
			var O: Vector2 = a.O
			var n := 4
			for i in n:
				var a0: float = lerpf(float(a.ang0), float(a.ang1), float(i) / float(n))
				var a1: float = lerpf(float(a.ang0), float(a.ang1), float(i + 1) / float(n))
				_ghost(a.who.irene, O + Vector2.from_angle(a0) * float(a.R) * 0.55, O + Vector2.from_angle(a1) * float(a.R) * 0.55, t + 0.55 + 0.75 * float(i) / float(n), 0.75 / float(n), IR)
			due.append([t + 0.35, "light", {"o": a.who.lumen, "p": O + Vector2(0, -20), "r": 240.0, "i": 0.8, "c": LAMPG[4], "life": 0.15}])


## 能天使车顶一轮扫射（bond2._penguin 每 0.08 秒调一次）：从车顶枪口到每个目标一道曳光
func shots(a: Dictionary, car: Vector2, targets: Array) -> void:
	var mz: Vector2 = car + Vector2(-8.0 * signf(Vector2(a.dl).x if Vector2(a.dl).x != 0.0 else 1.0), -70)
	for p in targets:
		_push({"k": "tracer", "a": mz, "b": p, "t0": g.t, "life": 0.3})
	if not targets.is_empty() and a.who.exusiai != null:
		due.append([g.t + 0.067, "light", {"o": a.who.exusiai, "p": targets[0], "r": 90.0, "i": 0.4, "c": EX[4]}])


## 残影：o 的出手帧条（attack）半透明分身从 a 冲到 b（dur 秒；a == b 时原地出招），身后拖 4 层越来越淡的残像，到点后停 0.12 秒淡出。
## up = 离地高度（能天使跃起）。色调往本人颜色偏一点、不透明度 ≤ 0.85，和本体分得开
func _ghost(o, a: Vector2, b: Vector2, t0: float, dur: float, pal: Array, up := 0.0) -> void:
	if o == null or not is_instance_valid(o):
		return
	_push({"k": "ghost", "op": o, "a": a, "b": b, "t0": t0, "dur": dur, "pal": pal, "up": up, "life": dur + 0.36})


## 受审：光里剩下的每只头顶一道短光针（bond2._inq 判定那一刻调，es 至多 40 只）
func judge(a: Dictionary, es: Array) -> void:
	var t: float = g.t
	for i in es.size():
		var e: Dictionary = es[i]
		_push({"k": "bolt", "p": e.pos, "h": float(e.get("r", 10.0)) * 1.6 + 6.0, "t0": t + 0.02 * float(i % 4), "life": 0.3})
	due.append([t, "light", {"o": a.who.irene, "p": a.c, "r": float(a.r) * 1.4, "i": 0.8, "c": IR[5]}])
	due.append([t, "grains", {"o": a.who.irene, "p": a.c, "n": 10, "c0": IR[5], "c1": IR[3], "mat": "rise"}])


func card(bid: String, pr: Array, e2: bool) -> void:
	cards.append({"bid": bid, "ops": pr, "t0": g.t, "e2": e2})


# ================================================================ 每帧

func _step() -> void:
	var now: float = g.t
	items = items.filter(func(it): return now - float(it.t0) < float(it.life) + 0.02)
	if due.is_empty():
		return
	var keep: Array = []
	var R = null
	for q in due:
		if now < float(q[0]):
			keep.append(q)
			continue
		if now - float(q[0]) > 0.25:
			continue
		var d: Dictionary = q[2]
		var o = d.get("o")
		if o == null or not is_instance_valid(o):
			continue
		if R == null:
			R = _R()
		match str(q[1]):
			"light":
				R._light(o, d.p + Vector2(0, -8), float(d.r), float(d.i), float(d.get("life", 0.12)), d.c)
			"grains":
				R._grains(o, d.p + Vector2(0, -LIFT * 0.5), float(d.p.y) + 1.0, str(d.get("mat", "shard")), int(d.n), {"tier": 1, "c0": d.c0, "c1": d.c1})
			"motes":
				R._grains(o, d.c + Vector2(0, -6), float(d.c.y) + 1.0, "rise", 8, {"tier": 1, "c0": LM[5], "c1": LM[3], "grain_spd": 3.0})
	due = keep


## fx_pxplane.sort_items 末尾调（转平面开着、非批跑）：返回排序项（带 skey）
static func sort_items(game) -> Array:
	if game == null or not game.has_meta("fx_bond2"):
		return []
	var r = game.get_meta("fx_bond2")
	r._step()
	var out: Array = []
	for it in r.items:
		if game.t < float(it.t0):
			continue
		var k: String = str(it.k)
		var sk: float
		match k:
			"lane", "lamp", "cross", "mark", "shock", "skid":
				sk = GROUND_KEY
			"car":
				sk = r._car_pos(it).y + 1.0
			"lh":
				sk = float((it.O as Vector2).y) + 1.0
				out.append({"bd2": it, "skey": 1.0e9, "beam": true})   # 光锥画在所有单位上面
			"clash":
				sk = float((it.c as Vector2).y) + 40.0
			"ln", "tracer", "ghost":
				sk = maxf((it.a as Vector2).y, (it.b as Vector2).y) + 2.0
			_:
				sk = float((it.p as Vector2).y) + 2.0
		out.append({"bd2": it, "skey": sk})
	return out


static func draw_sorted(game, ci, item: Dictionary) -> void:
	var r = game.get_meta("fx_bond2")
	var it: Dictionary = item.bd2
	if item.get("beam", false):
		r._draw_beam(ci, it)
		return
	match str(it.k):
		"clash":
			r._draw_clash(ci, it)
		"shock":
			r._draw_shock(ci, it)
		"car":
			r._draw_car(ci, it)
		"skid":
			r._draw_skid(ci, it)
		"lh":
			r._draw_lh(ci, it)
		"ln":
			r._draw_ln(ci, it)
		"lane":
			r._draw_lane(ci, it)
		"tracer":
			r._draw_tracer(ci, it)
		"sword":
			r._draw_sword(ci, it)
		"cross":
			r._draw_cross(ci, it)
		"mark":
			r._draw_mark(ci, it)
		"lamp":
			r._draw_lamp(ci, it)
		"bolt":
			r._draw_bolt(ci, it)
		"ghost":
			r._draw_ghost(it)


# ================================================================ 画法

## 斩线：芯 w 格（前两拍过曝近白）+ 两侧一格角色色 + 地上一道暗焦痕；grow 拍里由起点长到全长；hold 拍后两拍里断成碎段
func _draw_ln(ci, it: Dictionary) -> void:
	var f: int = _beat(float(it.t0))
	var hold: int = int(it.hold)
	if f < 0 or f > hold + 2:
		return
	var pal: Array = it.pal
	var a: Vector2 = it.a
	var b: Vector2 = it.b
	var px: float = g.PX
	var L: float = a.distance_to(b)
	var dv: Vector2 = (b - a) / maxf(1.0, L)
	var nv := Vector2(-dv.y, dv.x)
	var n: int = maxi(2, int(L / px))
	var vis: int = n if f >= int(it.grow) - 1 else int(float(n) * float(f + 1) / float(it.grow))
	var hot: bool = f <= 1
	var brk: float = 0.0 if f <= hold else (0.5 if f == hold + 1 else 0.8)
	var lift := Vector2(0, -float(it.get("lift", LIFT)))
	var w: int = int(it.w) + (1 if hot else 0)
	var core: Color = Color(1.35, 1.3, 1.25) if hot else pal[5]   # 前两拍过曝近白，之后芯带本人颜色（11-06 录像：粗线全白时两人分不出）
	var side: Color = pal[5] if hot else (pal[4] if brk == 0.0 else pal[3])
	var seed: float = float(int(absf(a.x)) % 13) * 0.07
	for i in vis + 1:
		var u: float = float(i) / float(n)
		var prof: float = pow(sin(PI * clampf(u * 0.94 + 0.03, 0.0, 1.0)), 0.6)
		if brk > 0.0 and fposmod(float(i) * 0.618034 + seed + float(f) * 0.31, 1.0) < brk:
			continue
		var head: bool = vis < n and i > vis - 4
		var cw: int = maxi(1, int(round(float(w) * prof)))
		var q: Vector2 = a + dv * float(i) * px
		if f <= hold and (i & 1) == 0 and u > 0.04 and u < 0.96:   # 地上焦痕（暗一格，贴地）
			_cell(ci, q + Vector2(0, 2), pal[1] if f > 2 else pal[2])
		q += lift - nv * float(cw / 2) * px
		for k in cw:
			_cell(ci, q + nv * float(k) * px, Color(1.4, 1.35, 1.3) if head else core)
		if prof > 0.25:
			_cell(ci, q - nv * px, side)
			_cell(ci, q + nv * float(cw) * px, side)
			if w >= 4 and prof > 0.5 and brk == 0.0:   # 粗线再加一圈本人中间色外缘
				_cell(ci, q - nv * 2.0 * px, pal[3])
				_cell(ci, q + nv * float(cw + 1) * px, pal[3])
		if (hot or head) and prof > 0.2 and i % 3 == 0:
			_glow(q + nv * float(cw / 2) * px, pal[5])
		elif brk == 0.0 and i % 6 == 0 and prof > 0.4:
			_glow(q + nv * float(cw / 2) * px, pal[4])
	if it.get("star", false) and f <= 1:   # 刺击出手星芒（同艾丽妮 _star）
		_star(ci, a + lift, 5 if f == 0 else 3, pal)


func _star(ci, c: Vector2, arm: int, pal: Array) -> void:
	var px: float = g.PX
	_cell(ci, c, pal[6])
	_glow(c, pal[6])
	for i in range(1, arm + 1):
		var col: Color = pal[5] if i < arm else pal[4]
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			_cell(ci, c + d * float(i) * px, col)


## 起手预兆：交点一个小菱形（0.25 秒）
func _draw_mark(ci, it: Dictionary) -> void:
	var f: int = _beat(float(it.t0))
	var pal: Array = it.pal
	var c: Vector2 = _snap(it.c) + Vector2(0, -LIFT)
	var px: float = g.PX
	var s: int = 2 + mini(f, 2)
	for i in range(-s, s + 1):
		var col: Color = pal[6] if absi(i) <= 1 else pal[4]
		_cell(ci, c + Vector2(i, 0) * px, col)
		_cell(ci, c + Vector2(0, i) * px, col)
	_glow(c, pal[5])


## 交点：两色星芒（各一人色，交替）+ 一圈贴地冲击环往外扩（4 拍）
func _draw_cross(ci, it: Dictionary) -> void:
	var f: int = _beat(float(it.t0))
	if f < 0 or f > 6:
		return
	var c: Vector2 = _snap(it.c)
	var pa: Array = it.pa
	var pb: Array = it.pb
	var px: float = g.PX
	if f <= 2:
		var arm: int = 14 - f * 3
		for i in range(-arm, arm + 1):
			var k: float = absf(float(i)) / float(arm)
			var ca: Color = pa[6] if k < 0.3 else (pa[5] if k < 0.7 else pa[4])
			var cb: Color = pb[6] if k < 0.3 else (pb[5] if k < 0.7 else pb[4])
			_cell(ci, c + Vector2(i, roundf(i * 0.5)) * px + Vector2(0, -LIFT), ca)
			_cell(ci, c + Vector2(i, -roundf(i * 0.5)) * px + Vector2(0, -LIFT), cb)
			if f == 0 and i % 3 == 0:
				_glow(c + Vector2(i, 0) * px + Vector2(0, -LIFT), Color(1.0, 0.9, 0.85))
	var rr: float = float(it.r) * 0.5 * (0.35 + 0.65 * float(f + 1) / 5.0)   # 美术像素半径
	var n: int = int(rr * 6.0)
	for q in n:
		var t: float = float(q) / float(n) * TAU
		var pal: Array = pa if (q / 4) % 2 == 0 else pb
		var col: Color = pal[5] if f <= 1 else (pal[4] if f <= 3 else pal[3])
		if f >= 4 and q % 3 == 0:
			continue
		_cell(ci, c + Vector2(roundf(rr * cos(t)), roundf(rr * sin(t) * SQ)) * px, col)
		if f <= 2 and q % 2 == 0:
			_cell(ci, c + Vector2(roundf((rr - 1.0) * cos(t)), roundf((rr - 1.0) * sin(t) * SQ)) * px, pal[2])


## 航线：两侧红橙虚线（6 亮 4 空，贴地一格暗边），3 拍内由近及远画出；结尾两拍断开；终点一个像素「>」
func _draw_lane(ci, it: Dictionary) -> void:
	var f: int = _beat(float(it.t0))
	var life_b: int = int(float(it.life) * 15.0)
	if f < 0 or f > life_b:
		return
	var s0: Vector2 = it.s
	var dl: Vector2 = it.dl
	var nl: Vector2 = dl.orthogonal()
	var ln: float = it.len
	var hw: float = it.hw
	var px: float = g.PX
	var n: int = int(ln / px)
	var vis: int = n if f >= 3 else int(float(n) * float(f + 1) / 4.0)
	var brk: float = clampf(float(f - (life_b - 3)) / 3.0, 0.0, 0.85)
	var flash: bool = f >= 20 and f <= 21   # 1.35 秒收尾结算那一下亮一拍
	var col: Color = EX[5] if (f <= 1 or flash) else EX[4]
	for sd in [-1.0, 1.0]:
		for i in vis + 1:
			if (i / 5) % 2 == 1:
				continue
			if brk > 0.0 and fposmod(float(i) * 0.618034 + sd * 0.3, 1.0) < brk:
				continue
			var q: Vector2 = s0 + dl * float(i) * px + nl * hw * sd
			_cell(ci, q, col)   # 11-06 录像：一格细虚线后期看不见 → 两格宽 + 外侧暗边
			_cell(ci, q - nl * px * sd, EX[3] if not (f <= 1 or flash) else EX[4])
			_cell(ci, q + nl * px * sd, EX[1])
			if i % 5 == 0:
				_glow(q, EX[4] if (f <= 1 or flash) else EX[3])
	if vis >= n:
		var tip: Vector2 = s0 + dl * ln
		for j in range(-6, 7):
			var q2: Vector2 = tip - dl * float(absi(j)) * px + nl * float(j) * px * 1.3
			_cell(ci, q2, EX[5] if brk < 0.5 else EX[3])


## 曳光：枪口 → 落点，两拍飞到（头 3 格近白 + 尾 10 格红橙渐暗）；第 2–3 拍落点十字星
func _draw_tracer(ci, it: Dictionary) -> void:
	var f: int = _beat(float(it.t0))
	if f < 0 or f > 3:
		return
	var a: Vector2 = it.a
	var b: Vector2 = it.b
	var px: float = g.PX
	if f <= 1:
		var u: float = 0.55 if f == 0 else 1.0
		var hp: Vector2 = a.lerp(b, u) + Vector2(0, -LIFT * (1.0 - u))
		var dv: Vector2 = (b - a).normalized()
		var nv := Vector2(-dv.y, dv.x)
		for k in 22:
			var col: Color = EX[6] if k < 4 else (EX[5] if k < 9 else (EX[4] if k < 15 else EX[3]))
			_cell(ci, hp - dv * float(k) * px, col)
			if k < 12:
				_cell(ci, hp - dv * float(k) * px + nv * px, EX[4] if k < 6 else EX[3])
		_glow(hp, EX[5])
	else:
		_star(ci, _snap(b) + Vector2(0, -4), 5 if f == 2 else 3, EX)


## 落剑：两拍从高处直落（竖直亮线，3 格宽：芯近白 + 两侧琥珀），落地后剑身插在地上 5 拍、逐拍变暗
func _draw_sword(ci, it: Dictionary) -> void:
	var f: int = _beat(float(it.t0))
	if f < 0:
		return
	var p: Vector2 = _snap(it.p)
	var px: float = g.PX
	var big: bool = it.big
	var hl: int = 36 if big else 28
	if f <= 1:
		var y0: float = -180.0 * (1.0 - float(f + 1) / 2.0) - 8.0
		for k in hl:
			var q: Vector2 = p + Vector2(0, y0 - float(k) * px)
			var core: Color = TX[6] if k < 8 else TX[5]
			_cell(ci, q, core)
			_cell(ci, q + Vector2(-px, 0), TX[4] if k < 14 else TX[3])
			_cell(ci, q + Vector2(px, 0), TX[4] if k < 14 else TX[3])
			if k % 3 == 0:
				_glow(q, TX[5])
		return
	var g2: int = f - 2
	if g2 > 5:
		return
	var blade: int = 16 if big else 12
	for k in blade:
		var q2: Vector2 = p + Vector2(0, -float(k) * px)
		var c2: Color = TX[6] if g2 == 0 else (TX[5] if g2 <= 2 else TX[4])
		_cell(ci, q2, c2 if k > 1 else TX[3])
		_cell(ci, q2 + Vector2(px, 0), TX[2])
	for x in range(-3, 4):   # 护手
		_cell(ci, p + Vector2(x * px, -float(blade) * px), TX[3] if absi(x) < 3 else TX[2])
	_cell(ci, p + Vector2(0, -float(blade + 2) * px), TX[4])
	if g2 == 0:
		_glow(p + Vector2(0, -4), TX[6])


## 提灯光圈：钢蓝描边圈（10 段虚线、慢转）+ 内圈暗一格；0.3 秒内张开、最后 0.3 秒断开；流明头顶灯点 + 一道点线引到圈心（只在张开时）
func _draw_lamp(ci, it: Dictionary) -> void:
	var age: float = g.t - float(it.t0)
	var life: float = float(it.life)
	if age < 0.0 or age > life:
		return
	var px: float = g.PX
	var c: Vector2 = _snap(it.c)
	var k: float = clampf(age / 0.3, 0.0, 1.0)
	var rr: float = float(it.r) * 0.5 * (1.0 - pow(1.0 - k, 3.0))
	var bt: int = int(floor(g.t * 15.0))
	var brk: float = clampf((age - (life - 0.3)) / 0.3, 0.0, 0.85)
	var n: int = int(rr * 6.6)
	var rot: float = float((bt / 2) % 32) / 32.0 * TAU / 10.0
	for q in n:
		var t: float = float(q) / float(n) * TAU
		var seg: float = fposmod(t - rot, TAU / 10.0) / (TAU / 10.0)
		if brk > 0.0 and fposmod(float(q) * 0.618034, 1.0) < brk:
			continue
		if seg < 0.72:
			var p: Vector2 = c + Vector2(roundf(rr * cos(t)), roundf(rr * sin(t) * SQ)) * px
			_cell(ci, p, LM[6] if (seg < 0.15 and k < 1.0) else (LM[5] if seg < 0.5 else LM[4]))
			if q % 8 == 0:
				_glow(p, LM[4])
		if q % 2 == 0:
			_cell(ci, c + Vector2(roundf((rr - 2.0) * cos(t)), roundf((rr - 2.0) * sin(t) * SQ)) * px, LM[2])
	var o = it.get("op")
	if o != null and is_instance_valid(o) and o.pos != Vector2.INF and age < life - 0.3:
		var lp: Vector2 = _snap(o.pos + Vector2(10.0 * o.face, -58.0))
		_star(ci, lp, 3 if (bt / 2) % 2 == 0 else 2, LM)
		if age < 0.4:
			var m: int = int(lp.distance_to(c) / (px * 3.0))
			for i in m:
				if float(i) / float(m) > k + 0.1:
					break
				_cell(ci, lp.lerp(c, float(i) / float(m)), LM[4])


func _draw_ghost(it: Dictionary) -> void:
	var o = it.op
	if o == null or not is_instance_valid(o) or not o.has_method("draw_body_at"):
		return
	var age: float = g.t - float(it.t0)
	var dur: float = float(it.dur)
	if age < 0.0 or age > dur + 0.34:
		return
	var tx: Texture2D = o.anim_tex("attack")
	if tx == null:
		return
	var hf: int = o.anim_hframes(tx, "attack")
	var a: Vector2 = it.a
	var b: Vector2 = it.b
	var still: bool = a.distance_to(b) < 2.0
	var u: float = clampf(age / maxf(0.01, dur), 0.0, 1.0)
	var fade: float = 1.0 - clampf((age - dur - 0.12) / 0.22, 0.0, 1.0)
	var flip: bool = bool(it.flip) if it.has("flip") else ((b.x < a.x) if not still else (o.face < 0.0))
	var pc: Color = it.pal[4]
	var lift := Vector2(0, -float(it.up))
	var bt: int = _beat(float(it.t0))
	var fr: int = (bt % hf) if still else mini(hf - 1, int(u * float(hf - 1)) + 1)
	if int(it.get("fr", -1)) == -2:
		fr = hf / 2   # 交锋定格：停在出刀那一帧
	if not still:
		for j in range(4, 0, -1):   # 残像：越后越淡、越偏本人颜色
			var uj: float = u - 0.14 * float(j)
			if uj < 0.0:
				continue
			var al: float = 0.42 * (1.0 - float(j) / 5.0) * fade
			var cj := Color(lerpf(1.0, pc.r * 1.3, 0.6), lerpf(1.0, pc.g * 1.3, 0.6), lerpf(1.0, pc.b * 1.3, 0.6), al)
			o.draw_body_at(_snap(a.lerp(b, uj)) + lift, flip, cj, {"tex": tx, "frame": fr, "hf": hf, "kind": "attack"})
	var ch := Color(lerpf(1.0, pc.r * 1.25, 0.3), lerpf(1.0, pc.g * 1.25, 0.3), lerpf(1.0, pc.b * 1.25, 0.3), 0.85 * fade)
	o.draw_body_at(_snap(a.lerp(b, u)) + lift, flip, ch, {"tex": tx, "frame": fr, "hf": hf, "kind": "attack"})
	if o.has_method("_cv_flush"):
		o._cv_flush()


## 受审光针：头顶上方 22 格往下扎（2 拍），落到头顶一个小星芒
func _draw_bolt(ci, it: Dictionary) -> void:
	var f: int = _beat(float(it.t0))
	if f < 0 or f > 3:
		return
	var px: float = g.PX
	var top: Vector2 = _snap(it.p) + Vector2(0, -float(it.h) - 44.0)
	var hd: Vector2 = _snap(it.p) + Vector2(0, -float(it.h))
	if f <= 1:
		var m: int = 22 if f == 1 else 11
		for k in m:
			var q: Vector2 = top + Vector2(0, float(k) * px)
			_cell(ci, q, IR[6] if k > m - 5 else IR[5])
			if k % 5 == 0:
				_cell(ci, q + Vector2(px, 0), IR[4])
		_glow(top + Vector2(0, float(m) * px), IR[5])
	else:
		_star(ci, hd, 3 if f == 2 else 2, IR)



# ================================================================ 第二版主形（docs/296）：运行时按像素格生成贴图（不进包）+ 代码画

const LAMPG := [Color("#1c1408"), Color("#4a3612"), Color("#8c6a26"), Color("#cfa24a"), Color("#efd08a"), Color("#fff0c6"), Color("#ffffff")]   # 艾丽妮手提灯暖金（docs/272 LAMP）
const BLK := [Color("#07080a"), Color("#101216"), Color("#1a1d23"), Color("#272b33"), Color("#3a3f4a")]
const CARC := [Color("#0e1014"), Color("#1c2028"), Color("#2e3440"), Color("#48505e"), Color("#6c7686")]
const LH_W := 96
const LH_H := 190
const LH_LAMP_Y := 21
const CAR_W := 72
const CAR_H := 50

var _tex := {}


func _img_tex(key: String, w: int, h: int, fill: Callable) -> Texture2D:
	if _tex.has(key):
		return _tex[key]
	var im := Image.create(w, h, false, Image.FORMAT_RGBA8)
	im.fill(Color(0, 0, 0, 0))
	fill.call(im)
	var t := ImageTexture.create_from_image(im)
	_tex[key] = t
	return t


static func _ip(im: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < im.get_width() and y < im.get_height():
		im.set_pixel(x, y, c)


## 灯塔（用户 11-07 给的参考：黑色细高塔身 + 带城垛与两角塔楼的堡垒基座 + 正面金色徽记 + 竖栅格灯室透暖光 + 尖顶）；同 tools/bond2_concept.py lighthouse3
func _lighthouse_tex(lit: bool) -> Texture2D:
	return _img_tex("lh%d" % int(lit), LH_W, LH_H, func(im: Image):
		var cx := LH_W / 2
		for y in range(158, 190):
			var hw: int = 40 + (y - 158) / 6
			for x in range(-hw, hw + 1):
				var col: Color = BLK[2] if ((y - 158) % 6 == 0 or posmod(x + (6 if ((y - 158) / 6) % 2 else 0), 12) == 0) else BLK[1]
				if absi(x) >= hw - 1:
					col = BLK[0]
				if y == 158 or x == -hw:
					col = LAMPG[2] if lit else BLK[3]
				_ip(im, cx + x, y, col)
		for y in range(152, 158):
			for x in range(-40, 41):
				if posmod(x, 8) < 4:
					_ip(im, cx + x, y, BLK[2] if y > 152 else BLK[3])
		for tcx in [-38, 38]:
			for y in range(140, 158):
				for x in range(-7, 8):
					_ip(im, cx + tcx + x, y, BLK[2] if x < 0 else BLK[1])
			for y in range(135, 140):
				for x in range(-7, 8):
					if posmod(x, 6) < 3:
						_ip(im, cx + tcx + x, y, BLK[3])
		for y in 7:
			for x in range(-7, 8):
				var wing: bool = absi(x) >= 2 and y <= 4 - (absi(x) - 2) / 2 + 1 and y >= (absi(x) - 2) / 3
				var body: bool = absi(x) <= 1 and y >= 1 and y <= 6
				if wing or body:
					_ip(im, cx + x, 166 + y, LAMPG[4] if (x + y) % 3 else LAMPG[5])
		for y in range(40, 152):
			var hw2: int = 7 + int(float(y - 40) / 112.0 * 6.0)
			for x in range(-hw2, hw2 + 1):
				var col2: Color = BLK[2] if x < -hw2 / 3 else BLK[1]
				if x == -hw2:
					col2 = LAMPG[3] if lit else BLK[4]
				elif x == -hw2 + 1 and lit:
					col2 = LAMPG[1]
				elif x == hw2:
					col2 = BLK[0]
				if y == 60 or y == 98 or y == 136 or y == 137:   # 塔身金色箍带（参考图的金饰）
					col2 = LAMPG[3] if (lit and x < hw2 / 2) else (LAMPG[2] if lit else BLK[3])
				if (y >= 72 and y < 80 or y >= 110 and y < 118) and absi(x) <= 1:   # 窄窗：亮时透暖光
					col2 = LAMPG[4] if lit else BLK[0]
				_ip(im, cx + x, y, col2)
		for y in range(34, 40):
			for x in range(-9, 10):
				_ip(im, cx + x, y, BLK[3] if y == 34 or y == 39 else BLK[2])
		for y in range(8, 34):
			for x in range(-9, 10):
				var bar: bool = absi(x) == 9 or posmod(x, 3) == 0 or y == 8 or y == 20 or y == 33
				if bar:
					_ip(im, cx + x, y, BLK[2] if lit else BLK[1])
				else:
					var d: float = Vector2(x, (y - 21) * 0.6).length() / 10.0
					_ip(im, cx + x, y, (LAMPG[5] if d < 0.3 else (LAMPG[4] if d < 0.65 else LAMPG[3])) if lit else BLK[0])
		for y in 8:
			var hw3: int = maxi(0, (y - 2) / 2)
			for x in range(-hw3, hw3 + 1):
				_ip(im, cx + x, y, LAMPG[4] if lit and x == 0 else BLK[2]))


## 车（俯视 3/4，72×50）：车顶 + 朝镜头的侧面（侧窗、琥珀腰线）+ 前后挡风 + 四个轮子 + 红橙顶灯；同 tools/bond2_concept.py car3（车头朝右）
func _car_tex() -> Texture2D:
	return _img_tex("car", CAR_W, CAR_H, func(im: Image):
		var yb := CAR_H - 6
		var hs := 16
		var dpt := 22
		for x in range(-2, CAR_W + 2):
			for y in 4:
				_ip(im, x, yb + 2 + y, Color(0.04, 0.04, 0.05, 0.6))
		for x in CAR_W:
			for y in hs:
				var col: Color = CARC[1] if y < 3 else CARC[2]   # y 从车底往上数：下沿暗一档
				if y == 5 or y == 6:
					col = TX[4] if x > 4 and x < CAR_W - 4 else CARC[2]
				if (x > 14 and x < 30 and y >= hs - 6 and y <= hs - 2) or (x > 34 and x < 52 and y >= hs - 6 and y <= hs - 2):   # 侧窗在侧面上部
					col = Color8(46, 66, 88) if (x + y) % 5 else Color8(110, 140, 165)
				if x == 0 or x == CAR_W - 1:
					col = CARC[0]
				_ip(im, x, yb - y, col)
		for x in range(6, CAR_W - 10):
			for y in dpt:
				var col2: Color = CARC[2] if y > 2 else CARC[3]
				if x > CAR_W - 22:
					col2 = Color8(52, 74, 98) if (x + y) % 6 else Color8(120, 150, 175)
				if x < 14:
					col2 = Color8(40, 56, 74)
				_ip(im, x, yb - hs - y + dpt / 3 - 2, col2)
		for x in range(5, CAR_W - 9):   # 车顶外轮廓（深一档，免得被受光洗白）
			_ip(im, x, yb - hs - dpt + dpt / 3 - 3, CARC[0])
		for y in range(dpt + 1):
			_ip(im, 5, yb - hs - y + dpt / 3 - 2, CARC[0])
			_ip(im, CAR_W - 10, yb - hs - y + dpt / 3 - 2, CARC[0])
		for dx in range(-3, 4):
			_ip(im, CAR_W / 2 - 6 + dx, yb - hs - dpt + 4, EX[4] if absi(dx) < 2 else EX[3])
		for wx in [10, CAR_W - 18]:
			for dx in 10:
				for dy in 6:
					var r: float = Vector2(dx - 4.5, (dy - 2.5) * 1.6).length()
					if r < 5.0:
						_ip(im, wx + dx, yb + dy - 3, Color8(16, 16, 18) if r > 2.0 else CARC[3]))


## 对砍交锋：两色四芒（横向左琥珀 / 右淡紫，竖向白 → 本人色），3 拍收
func _draw_clash(ci, it: Dictionary) -> void:
	var f: int = _beat(float(it.t0))
	if f < 0 or f > 2:
		return
	var c: Vector2 = _snap(it.c)
	var px: float = g.PX
	var arm: int = [22, 16, 9][f]
	for i in range(1, arm + 1):
		var k: float = float(i) / float(arm)
		_cell(ci, c + Vector2(-i, 0) * px, Color.WHITE if k < 0.25 else (TX[5] if k < 0.6 else TX[4]))
		_cell(ci, c + Vector2(i, 0) * px, Color.WHITE if k < 0.25 else (LP[5] if k < 0.6 else LP[4]))
		if i < arm * 0.6:
			_cell(ci, c + Vector2(0, -i) * px, Color.WHITE if k < 0.3 else TX[5])
			_cell(ci, c + Vector2(0, i) * px, Color.WHITE if k < 0.3 else LP[5])
		if i % 3 == 0:
			_glow(c + Vector2(-i, 0) * px, TX[5])
			_glow(c + Vector2(i, 0) * px, LP[5])
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			_cell(ci, c + Vector2(dx, dy) * px, Color(1.35, 1.3, 1.25))
	_glow(c, Color.WHITE)


## 对砍余波：冲击波向四周散开（docs/296 第五轮）。不画整齐细环（11-04 起细环 / 半透明盘被否）：
## 波前按 15 帧节拍跳半径，96 段每段厚薄、前后错位都不一样（断续的锯齿浪头），左半琥珀、右半淡紫，前两拍近白；
## 浪头后面一圈翻起的地面碎屑（深灰块往外飞），最后浪头碎成散点淡出
static func _h(i: int, s: int) -> float:
	var v: float = sin(float(i) * 12.9898 + float(s) * 78.233) * 43758.5453
	return v - floor(v)


func _draw_shock(ci, it: Dictionary) -> void:
	var age: float = g.t - float(it.t0)
	if age < 0.0 or age > 0.8:
		return
	var f: int = _beat(float(it.t0))
	var kq: float = clampf(float(f) / 7.0, 0.0, 1.0)
	var r: float = lerpf(50.0, float(it.rmax), 1.0 - pow(1.0 - kq, 2.0))
	var brk: float = clampf((age - 0.4) / 0.4, 0.0, 1.0)
	var c: Vector2 = _snap(it.c)
	var px: float = g.PX
	var segs := 96
	ci.draw_set_transform(c, 0.0, Vector2(1.0, SQ))
	for i in segs:
		if _h(i, 3) < brk:
			continue
		var a0: float = TAU * float(i) / float(segs)
		var a1: float = TAU * float(i + 1) / float(segs)
		var right: bool = cos((a0 + a1) * 0.5) >= 0.0
		var pal: Array = LP if right else TX
		var jit: float = (_h(i, 1) - 0.5) * 10.0 * px * (0.4 + kq)
		var th: float = (2.0 + floor(_h(i, 2) * 4.0)) * px * (1.0 - 0.5 * brk)
		var rr: float = r + jit
		var hot: bool = f < 2
		ci.draw_arc(Vector2.ZERO, rr - th * 0.9, a0, a1, 3, Color(pal[2].r, pal[2].g, pal[2].b, 0.85), th * 0.8)
		ci.draw_arc(Vector2.ZERO, rr, a0, a1, 3, Color(1.3, 1.28, 1.25) if hot else pal[4], th)
		if _h(i, 4) > 0.55:
			ci.draw_arc(Vector2.ZERO, rr + th * 0.6, a0, a1, 3, Color(1.2, 1.18, 1.15) if hot else pal[5], px)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 翻起的地面碎屑：浪头后面 0–60 处，块往外飞、两拍一换位
	var nd := 48
	for j in nd:
		if _h(j, 7) < brk * 0.8:
			continue
		var a: float = TAU * (float(j) + _h(j, 5)) / float(nd)
		var back: float = (0.15 + 0.6 * _h(j, 6)) * 60.0 * (0.5 + kq)
		var p: Vector2 = c + Vector2(cos(a), sin(a) * SQ) * (r - back) + Vector2(0, -(1.0 - kq) * 10.0 * _h(j, 8))
		var sz: int = 1 + int(_h(j, 9) * 2.0)
		var col: Color = Color(0.5, 0.53, 0.58) if _h(j, 10) > 0.35 else ((LP if cos(a) >= 0.0 else TX)[3])
		ci.draw_rect(Rect2(_snap(p), Vector2(sz, sz) * px), col)
	if f < 4:
		for i in 16:
			var a: float = TAU * float(i) / 16.0
			_glow(c + Vector2(cos(a) * r, sin(a) * r * SQ), LP[5] if cos(a) >= 0.0 else TX[5])


## 车：驾驶位德克萨斯（只露上半身）→ 车身贴图 → 车顶能天使（出手帧）；两拍一颠
func _car_pos(it: Dictionary) -> Vector2:
	var u: float = clampf((g.t - float(it.t0) - float(it.T0)) / (float(it.T1) - float(it.T0)), 0.0, 1.0)
	return Vector2(it.s) + Vector2(it.dl) * float(it.len) * u


func _draw_car(ci, it: Dictionary) -> void:
	var age: float = g.t - float(it.t0)
	if age < float(it.T0) - 0.05 or age > float(it.T1) + 0.2:
		return
	var p: Vector2 = _snap(_car_pos(it))
	var flip: bool = Vector2(it.dl).x < 0.0
	var fs: float = -1.0 if flip else 1.0
	var bounce: float = g.PX if (_beat(float(it.t0)) / 2) % 2 == 0 else 0.0
	var al: float = clampf((age - float(it.T0) + 0.05) / 0.1, 0.0, 1.0) * (1.0 - clampf((age - float(it.T1)) / 0.2, 0.0, 1.0))
	var tx = it.tx
	if tx != null and is_instance_valid(tx) and tx.has_method("draw_body_at"):
		var ti: Texture2D = tx.anim_tex("idle")
		if ti != null:
			tx.draw_body_at(p + Vector2(fs * 22.0, -40.0 - bounce), flip, Color(1, 1, 1, al), {"tex": ti, "frame": 0, "hf": tx.anim_hframes(ti, "idle"), "kind": "idle"})
			tx._cv_flush()
	var t: Texture2D = _car_tex()
	var sz: Vector2 = Vector2(CAR_W, CAR_H) * float(g.PX)
	ci.draw_set_transform(p + Vector2(0, -bounce), 0.0, Vector2(fs, 1.0))
	ci.draw_texture_rect(t, Rect2(Vector2(-sz.x * 0.5, -sz.y + 6.0 * g.PX), sz), false, Color(1, 1, 1, al))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_glow(p + Vector2(fs * -12.0, -sz.y + 14.0 * g.PX), EX[5])
	var ex = it.ex
	if ex != null and is_instance_valid(ex) and ex.has_method("draw_body_at"):
		var ta: Texture2D = ex.anim_tex("attack")
		if ta != null:
			var hf: int = ex.anim_hframes(ta, "attack")
			ex.draw_body_at(p + Vector2(fs * -10.0, -62.0 - bounce), (_beat(float(it.t0)) / 3) % 2 == 1, Color(1, 1, 1, al), {"tex": ta, "frame": _beat(float(it.t0)) % hf, "hf": hf, "kind": "attack"})
			ex._cv_flush()


## 胎痕：车后两道断续暗痕，车开过后 1 秒内逐渐断开
func _draw_skid(ci, it: Dictionary) -> void:
	var age: float = g.t - float(it.t0)
	if age < float(it.T0):
		return
	var s0: Vector2 = it.s
	var dl: Vector2 = it.dl
	var nl: Vector2 = dl.orthogonal()
	var u: float = clampf((age - float(it.T0)) / (float(it.T1) - float(it.T0)), 0.0, 1.0)
	var brk: float = clampf((age - float(it.T1)) / 1.0, 0.0, 0.9)
	var n: int = int(float(it.len) * u / g.PX)
	for i in range(0, n, 2):
		if brk > 0.0 and fposmod(float(i) * 0.618034, 1.0) < brk:
			continue
		var q: Vector2 = s0 + dl * float(i) * g.PX
		for sd in [-1.0, 1.0]:
			_cell(ci, q + nl * 20.0 * sd + Vector2(0, 4), Color(0.06, 0.06, 0.07, 0.85))


## 灯塔：从下往上显形（0–0.4 秒），0.25 秒起灯室亮；最后 0.35 秒淡出
func _draw_lh(ci, it: Dictionary) -> void:
	var age: float = g.t - float(it.t0)
	var life: float = float(it.life)
	if age < 0.0 or age > life:
		return
	var k: float = clampf(age / 0.4, 0.0, 1.0)
	var al: float = 0.95 * (1.0 - clampf((age - (life - 0.35)) / 0.35, 0.0, 1.0))
	var t: Texture2D = _lighthouse_tex(age >= 0.25)
	var px: float = g.PX
	var O: Vector2 = _snap(it.O)
	var vis: float = float(LH_H) * minf(1.0, k * 1.3)
	var src := Rect2(0, float(LH_H) - vis, LH_W, vis)
	ci.draw_texture_rect_region(t, Rect2(O + Vector2(-LH_W * 0.5, -vis) * px, Vector2(LH_W, vis) * px), src, Color(1, 1, 1, al))
	if age >= 0.25:
		var lp: Vector2 = O + Vector2(0, -(LH_H - LH_LAMP_Y)) * px
		for i in 6:
			_glow(lp + Vector2((i % 3 - 1) * 6, (i / 3) * 8 - 4), LAMPG[5])


## 光锥：灯室发出的暖金扇形光（两条亮边 + 中线 + 隔点抖动），从灯室斜落到地面；扫到的敌人头顶亮紫印（只画 0.15 秒，之后受审倒下）
func _draw_beam(ci, it: Dictionary) -> void:
	var age: float = g.t - float(it.t0)
	if age < 0.4 or age > 1.2:
		return
	var k: float = clampf((age - 0.4) / 0.75, 0.0, 1.0)
	var a0: float = it.ang0
	var a1: float = it.ang1
	var ang: float = lerpf(a0, a1, k)
	var R: float = it.R
	var px: float = g.PX
	var O: Vector2 = _snap(it.O)
	var lp: Vector2 = O + Vector2(0, -(LH_H - LH_LAMP_Y)) * px
	var spread := 0.3
	# 光锥本体：灯室处暖金、往外渐隐的扇形（顶点色渐变，不是整块半透明盘）；两条边按格子画、越远越淡、隔格断开
	var fa: float = 0.55 * (1.0 - clampf((age - 1.05) / 0.15, 0.0, 1.0))
	var ea: Vector2 = O + Vector2.from_angle(ang - spread * 0.5) * R
	var eb: Vector2 = O + Vector2.from_angle(ang + spread * 0.5) * R
	var pts := PackedVector2Array([lp, lp.lerp(ea, 0.5), lp.lerp(eb, 0.5)])
	var c0: Color = Color(LAMPG[4].r, LAMPG[4].g, LAMPG[4].b, 0.42 * fa)
	var c1: Color = Color(LAMPG[3].r, LAMPG[3].g, LAMPG[3].b, 0.16 * fa)
	ci.draw_polygon(pts, PackedColorArray([c0, c1, c1]))
	ci.draw_polygon(PackedVector2Array([lp.lerp(ea, 0.5), ea, eb, lp.lerp(eb, 0.5)]), PackedColorArray([c1, Color(c1, 0.0), Color(c1, 0.0), c1]))
	for e in [ea, eb]:
		var n: int = int(lp.distance_to(e) / px)
		for i in range(0, n, 2):
			var u: float = float(i) / float(n)
			if u > 0.4 and (i / 2) % 3 == 0:
				continue
			var q: Vector2 = lp.lerp(e, u)
			var col: Color = LAMPG[5] if u < 0.15 else (LAMPG[4] if u < 0.5 else LAMPG[3])
			_cell(ci, q, Color(col, fa * 1.6 * (1.0 - u * 0.8)))
	var bt: int = int(floor(g.t * 15.0))
	for i in 70:   # 光里飘的暖金尘点（按节拍换位，不抽随机数）
		var h1: float = fposmod(float(i) * 0.618034 + float(bt) * 0.137, 1.0)
		var h2: float = fposmod(float(i) * 0.414214 + float(bt) * 0.071, 1.0)
		var aa: float = ang + (h1 - 0.5) * spread * 0.9
		var q2: Vector2 = lp.lerp(O + Vector2.from_angle(aa) * R, 0.1 + 0.8 * h2)
		_cell(ci, q2, Color(LAMPG[5] if (i % 5) else Color.WHITE, fa * 1.4 * (1.0 - h2 * 0.7)))
	for i in 3:
		_glow(lp.lerp(O + Vector2.from_angle(ang) * R, 0.04 + 0.05 * float(i)), LAMPG[4])
	var rate: float = (a1 - a0) / 0.75
	for e2 in g.enemies:
		if e2.dead or e2.get("friendly", false):
			continue
		if e2.pos.distance_squared_to(O) > R * R:
			continue
		var lag: float = wrapf(ang - (e2.pos - O).angle(), -PI, PI) / rate
		if lag >= 0.0 and lag < 0.18:
			var hp: Vector2 = _snap(e2.pos + Vector2(0, -float(e2.get("r", 10.0)) * 1.6 - 10.0))
			for d in [Vector2.ZERO, Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				_cell(ci, hp + d * px, IR[5] if d == Vector2.ZERO else IR[3])
			_glow(hp, IR[4])


# ================================================================ 演出卡（HUD）

## hud.gd 调（指点 / 终结技瞄准之前；hu = hud_ult 实例，借它的圆形头像）。解锁 1.4 秒、精二强化 0.9 秒。
## 版式同精英化横幅（elite_moment.draw_hud）：屏幕上方 22% 一条深色半透明窄条；上沿两人色细线从两头往中间长、在中线汇合，下沿暗一档；
## 两人圆形头像（终结技 HUD 同一套眼睛对齐）在标题两侧、向中间轻滑 24 像素；英文小字 + 招式名 + 一句话。不铺整块纯色。
static func draw_hud(game, vs: Vector2, hu = null) -> void:
	if game == null or not game.has_meta("fx_bond2"):
		return
	var r = game.get_meta("fx_bond2")
	if r.cards.is_empty() or game.state != game.S.PLAY:
		return
	var cd: Dictionary = r.cards[0]
	var dur: float = 0.9 if cd.e2 else 1.4
	var t: float = game.t - float(cd.t0)
	if t > dur:
		r.cards.pop_front()
		return
	var mv: Dictionary = B2.MOVES.get(str(cd.bid), {})
	var ops: Array = cd.ops
	var pa: Array = PALS.get(str(mv.ops[0]), LP)
	var pb: Array = PALS.get(str(mv.ops[1]), LP)
	var a: float = clampf(t / 0.12, 0.0, 1.0) * clampf((dur - t) / 0.25, 0.0, 1.0)
	if a <= 0.0:
		return
	var sw: float = 1.0 - pow(1.0 - clampf(t / 0.28, 0.0, 1.0), 3.0)
	var hud = game.hud
	var y: float = vs.y * 0.22
	var hgt: float = 74.0 if cd.e2 else 92.0
	var cx: float = vs.x * 0.5
	var ca: Color = pa[4]
	var cb: Color = pb[4]
	hud.draw_rect(Rect2(0, y, vs.x, hgt), Color(0.02, 0.03, 0.05, 0.62 * a))
	hud.draw_rect(Rect2(cx - cx * sw, y, cx * sw, 2), Color(ca.r, ca.g, ca.b, 0.95 * a))
	hud.draw_rect(Rect2(cx, y, cx * sw, 2), Color(cb.r, cb.g, cb.b, 0.95 * a))
	hud.draw_rect(Rect2(cx - cx * sw, y + hgt - 2, cx * sw, 2), Color(ca.r, ca.g, ca.b, 0.45 * a))
	hud.draw_rect(Rect2(cx, y + hgt - 2, cx * sw, 2), Color(cb.r, cb.g, cb.b, 0.45 * a))
	if sw >= 1.0 and t < 0.45:   # 汇合那一下：中线一个小亮点
		var k: float = 1.0 - (t - 0.28) / 0.17
		hud.draw_rect(Rect2(cx - 6, y - 1, 12, 4), Color(1, 1, 1, clampf(k, 0.0, 1.0) * a))
	var kt: float = clampf((t - 0.1) / 0.15, 0.0, 1.0) * a
	var rr: float = hgt * 0.34
	if hu != null and hu.has_method("_avatar"):
		for i in mini(2, ops.size()):
			var o = ops[i]
			if o == null or not is_instance_valid(o):
				continue
			var dx: float = (1.0 - sw) * 24.0
			var pc := Vector2(cx - 210.0 + dx, y + hgt * 0.5) if i == 0 else Vector2(cx + 210.0 - dx, y + hgt * 0.5)
			var col: Color = ca if i == 0 else cb
			hud.draw_arc(pc, rr + 3.0, 0.0, TAU, 40, Color(col.r, col.g, col.b, kt), 2.0, true)
			var hv = hu.get("v")
			if hv != null and hv.has_method("_avatar_hi"):
				hv._avatar_hi(o, pc, rr, Color(1, 1, 1, kt))   # 终结技 HUD 同款眼睛对齐头像（avatar_eyes.json，用户 10-31 已确认）
			else:
				hu._avatar(o, pc, rr, Color(1, 1, 1, kt))
	if kt <= 0.0:
		return
	var head: String = ("BOND ARTS  ·  ENHANCED" if cd.e2 else "BOND ARTS  ·  UNLOCKED")
	UI.en(hud, game.font, Vector2(cx - 92, y + 18), head, 11, Color(0.82, 0.86, 0.9, kt), 3.0)
	var title: String = "%s · %s" % [str(mv.get("tag", "")), str(mv.get("name", ""))]
	UI.text(hud, game.font, Vector2(0, y + (52 if not cd.e2 else 56)), title, 28, Color(1, 1, 1, kt), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	if not cd.e2:
		UI.text(hud, game.font, Vector2(0, y + 78), str(mv.get("desc", "")), 14, Color(0.84, 0.88, 0.92, kt), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
