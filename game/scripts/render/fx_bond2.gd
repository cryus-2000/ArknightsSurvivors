## 羁绊技 v2 画面（docs/294；玩法在 run/bond2.gd，开关 link/bond_v2）。只画：不读写玩法字段、不抽玩法随机数（颗粒走 fx_recipe 的 g.vrng）。
## 画法和转平面（docs/246，render/fx_pxplane.gd）同一套：1 特效像素 = 1 美术像素（g.PX 世界像素、对齐 2 像素格）、15 fps 全局节拍换帧、
## 色层当普通物体画进单位排序（吃场景光），最亮的热芯进光学发光层（共用转平面的 EMIT_CAP），命中挂 ≤ 0.15 秒的照地光、Noita 颗粒。
## 斩线 = 德克萨斯「一刀一道」（_tx_draw_line1）的画法：芯近白（前两拍过曝）、两侧一格角色色、两头收尖，hold 拍后断成碎段收掉。
## 角色定稿色：德克萨斯琥珀 TX_C（docs/257）、拉普兰德淡紫 LP（docs/273）、能天使红橙 RAMP.n（docs/262）、艾丽妮白 + 亮紫 LT（docs/272）、流明钢蓝 LM_C（docs/255）。
## 每招元素 ≤ 3 种：宿敌 = 两道斩线 + 交点星芒 / 冲击环；企鹅物流 = 航线虚线 + 曳光 + 落剑；灯下审决 = 光圈 + 刺线 + 受审光针。
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
		"b_rival":
			var L: float = a.L
			var d1: Vector2 = a.d1
			var d2: Vector2 = a.d2
			var w: int = 3 if a.e2 else 2
			_push({"k": "mark", "c": c, "t0": t, "life": 0.25, "pal": LP})
			_push({"k": "ln", "a": c - d1 * L, "b": c + d1 * L, "t0": t + 0.25, "w": w, "hold": 9, "grow": 2, "pal": TX, "life": 1.2})
			_push({"k": "ln", "a": c - d2 * L, "b": c + d2 * L, "t0": t + 0.47, "w": w, "hold": 6, "grow": 2, "pal": LP, "life": 1.0})
			_push({"k": "cross", "c": c, "t0": t + 0.78, "life": 0.5, "r": 160.0 * float(a.k), "pa": TX, "pb": LP})
			due.append([t + 0.25, "light", {"o": a.who.texas, "p": c - d1 * L * 0.3, "r": 180.0, "i": 0.6, "c": TX[4]}])
			due.append([t + 0.47, "light", {"o": a.who.lappland, "p": c + d2 * L * 0.3, "r": 180.0, "i": 0.6, "c": LP[4]}])
			due.append([t + 0.78, "light", {"o": a.who.texas, "p": c, "r": 260.0, "i": 0.9, "c": Color(1.0, 0.86, 0.8)}])
			due.append([t + 0.78, "grains", {"o": a.who.texas, "p": c, "n": 8, "c0": TX[5], "c1": TX[3]}])
			due.append([t + 0.8, "grains", {"o": a.who.lappland, "p": c, "n": 8, "c0": LP[5], "c1": LP[3]}])
			if a.e2:
				var d3: Vector2 = Vector2(a.d0).orthogonal()
				_push({"k": "ln", "a": c - d3 * L * 0.8, "b": c + d3 * L * 0.8, "t0": t + 0.95, "w": 3, "hold": 5, "grow": 2, "pal": TX, "life": 0.9})
		"b_penguin":
			var s0: Vector2 = a.s
			var dl: Vector2 = a.dl
			var nl: Vector2 = dl.orthogonal()
			var ln: float = a.len
			var hw: float = a.hw
			_push({"k": "lane", "s": s0, "dl": dl, "len": ln, "hw": hw, "t0": t, "life": 1.75})
			var ex = a.who.exusiai
			var mz: Vector2 = (ex.pos if ex != null and is_instance_valid(ex) else s0) + Vector2(0, -26)
			for i in 30:
				var u0: float = float(i) / 29.0
				var off: float = (fposmod(float(i) * 0.618034, 1.0) * 2.0 - 1.0) * (hw - 16.0)
				var p: Vector2 = s0 + dl * (ln * (0.08 + 0.9 * u0)) + nl * off
				var ts: float = t + 0.25 + 0.032 * i
				_push({"k": "tracer", "a": mz, "b": p, "t0": ts, "life": 0.3})
				if i % 3 == 0:
					due.append([ts + 0.067, "grains", {"o": ex, "p": p, "n": 2, "c0": EX[5], "c1": EX[3]}])
				if i % 5 == 0:
					due.append([ts + 0.067, "light", {"o": ex, "p": p, "r": 90.0, "i": 0.45, "c": EX[4]}])
			var nsw: int = 10 if a.e2 else 6
			for j in nsw:
				var ts2: float = t + 0.75 + 0.09 * j * (6.0 / float(nsw))
				var big: bool = j == nsw - 1
				var u1: float = (float(j) + 0.5) / float(nsw)
				var p2: Vector2 = s0 + dl * (ln * (0.12 + 0.84 * u1)) + nl * (18.0 if j % 2 == 0 else -18.0)
				_push({"k": "sword", "p": p2, "t0": ts2, "big": big, "life": 0.75})
				var L2: float = 64.0 if big else 46.0
				_push({"k": "ln", "a": p2 + Vector2(-L2, -L2 * 0.45), "b": p2 + Vector2(L2, L2 * 0.45), "t0": ts2 + 0.133, "w": 2, "hold": 2, "grow": 1, "pal": TX, "life": 0.4, "lift": 6.0})
				_push({"k": "ln", "a": p2 + Vector2(-L2, L2 * 0.45), "b": p2 + Vector2(L2, -L2 * 0.45), "t0": ts2 + 0.133, "w": 2, "hold": 2, "grow": 1, "pal": TX, "life": 0.4, "lift": 6.0})
				due.append([ts2 + 0.133, "light", {"o": a.who.texas, "p": p2, "r": 160.0 if big else 120.0, "i": 0.75 if big else 0.55, "c": TX[4]}])
				due.append([ts2 + 0.133, "grains", {"o": a.who.texas, "p": p2, "n": 6 if big else 3, "c0": TX[5], "c1": TX[3]}])
		"b_inq":
			var R: float = a.r
			_push({"k": "lamp", "c": c, "r": R, "t0": t + 0.05, "life": 0.55 + 0.17 * (4 if a.e2 else 3) + 0.2 + 0.55, "op": a.who.lumen})
			due.append([t + 0.1, "light", {"o": a.who.lumen, "p": c, "r": R * 1.6, "i": 0.55, "c": LM[4], "life": 0.15}])
			due.append([t + 0.2, "motes", {"o": a.who.lumen, "c": c, "r": R}])
			var angs: Array = [-0.21, 0.84, 1.88, 2.9] if a.e2 else [-0.21, 0.84, 1.88]
			for i in angs.size():
				var d := Vector2.from_angle(float(angs[i]))
				var p0: Vector2 = c - d * (R + 40.0)
				var p1: Vector2 = c + d * (R + 40.0)
				if i % 2 == 1:
					var tmp: Vector2 = p0
					p0 = p1
					p1 = tmp
				var ts3: float = t + 0.55 + 0.17 * i
				_push({"k": "ln", "a": p0, "b": p1, "t0": ts3, "w": 2, "hold": 3, "grow": 1, "pal": IR, "life": 0.5, "star": true})
				due.append([ts3, "light", {"o": a.who.irene, "p": c + d * R * 0.2, "r": 170.0, "i": 0.6, "c": IR[4]}])


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
			"lane", "lamp", "cross", "mark":
				sk = GROUND_KEY
			"ln", "tracer":
				sk = maxf((it.a as Vector2).y, (it.b as Vector2).y) + 2.0
			_:
				sk = float((it.p as Vector2).y) + 2.0
		out.append({"bd2": it, "skey": sk})
	return out


static func draw_sorted(game, ci, item: Dictionary) -> void:
	var r = game.get_meta("fx_bond2")
	var it: Dictionary = item.bd2
	match str(it.k):
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
	var core: Color = Color(1.35, 1.3, 1.25) if hot else (pal[6] if f < hold - 2 else pal[5])
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
			_cell(ci, q, col)
			_cell(ci, q + Vector2(0, px), EX[1])
			if (f <= 1 or flash) and i % 10 == 0:
				_glow(q, EX[4])
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
		for k in 14:
			var col: Color = EX[6] if k < 3 else (EX[5] if k < 6 else (EX[4] if k < 10 else EX[3]))
			_cell(ci, hp - dv * float(k) * px, col)
		_glow(hp, EX[5])
	else:
		_star(ci, _snap(b) + Vector2(0, -4), 3 if f == 2 else 2, EX)


## 落剑：两拍从高处直落（竖直亮线，3 格宽：芯近白 + 两侧琥珀），落地后剑身插在地上 5 拍、逐拍变暗
func _draw_sword(ci, it: Dictionary) -> void:
	var f: int = _beat(float(it.t0))
	if f < 0:
		return
	var p: Vector2 = _snap(it.p)
	var px: float = g.PX
	var big: bool = it.big
	var hl: int = 26 if big else 20
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
	var blade: int = 12 if big else 9
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


# ================================================================ 演出卡（HUD）

## hud.gd 调（指点 / 终结技瞄准之前）：解锁 1.4 秒、精二强化 0.9 秒；屏幕上方 22% 一条两色横带 + 两人待机首帧 ×3 + 三行字
static func draw_hud(game, vs: Vector2) -> void:
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
	var sw: float = clampf(t / 0.22, 0.0, 1.0)
	var hud = game.hud
	var y: float = vs.y * 0.22
	var hgt: float = 92.0
	var half: float = vs.x * 0.5 * sw
	var ca: Color = pa[1]
	var cb: Color = pb[1]
	hud.draw_rect(Rect2(0, y, vs.x, hgt), Color(0.02, 0.03, 0.05, 0.55 * a))
	hud.draw_rect(Rect2(0, y, half, hgt), Color(ca.r, ca.g, ca.b, 0.75 * a))
	hud.draw_rect(Rect2(vs.x - half, y, half, hgt), Color(cb.r, cb.g, cb.b, 0.75 * a))
	hud.draw_rect(Rect2(0, y, half, 2), Color(pa[5].r, pa[5].g, pa[5].b, a))
	hud.draw_rect(Rect2(vs.x - half, y + hgt - 2, half, 2), Color(pb[5].r, pb[5].g, pb[5].b, a))
	var ease: float = 1.0 - pow(1.0 - sw, 3.0)
	for i in 2:
		var o = ops[i] if i < ops.size() else null
		if o == null or not is_instance_valid(o):
			continue
		var pt: Dictionary = o.portrait()
		var tex: Texture2D = game.tex.get(str(pt.get("tex", "")))
		if tex == null:
			continue
		var fw: float = tex.get_width() / maxf(1.0, float(pt.get("frames", 1)))
		var fh: float = tex.get_height()
		var sc: float = clampf((hgt + 40.0) / fh, 1.0, 4.0)
		var sz := Vector2(fw, fh) * sc
		var cx: float = lerpf(-sz.x, vs.x * 0.2, ease) if i == 0 else lerpf(vs.x + sz.x, vs.x * 0.8, ease)
		var src := Rect2(0, 0, fw, fh)
		if i == 1:
			src = Rect2(fw, 0, -fw, fh)   # 右边那位朝左
		hud.draw_texture_rect_region(tex, Rect2(Vector2(cx - sz.x * 0.5, y + hgt - sz.y + 6.0), sz), src, Color(1, 1, 1, a))
	var kt: float = clampf((t - 0.12) / 0.15, 0.0, 1.0) * a
	if kt <= 0.0:
		return
	var head: String = ("羁绊技强化 · " if cd.e2 else "羁绊技解锁 · ") + str(mv.get("tag", ""))
	UI.text(hud, game.font, Vector2(0, y + 20), head, 14, Color(0.92, 0.92, 0.92, kt), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	UI.text(hud, game.font, Vector2(0, y + 56), str(mv.get("name", "")), 32, Color(1, 1, 1, kt), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 3)
	if not cd.e2:
		UI.text(hud, game.font, Vector2(0, y + 82), str(mv.get("desc", "")), 14, Color(0.86, 0.88, 0.9, kt), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
