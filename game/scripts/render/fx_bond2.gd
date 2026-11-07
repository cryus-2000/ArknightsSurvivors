## 羁绊技 v2 画面（docs/294；玩法在 run/bond2.gd，开关 link/bond_v2）。只画：不读写玩法字段、不抽玩法随机数（颗粒走 fx_recipe 的 g.vrng）。
## 画法和转平面（docs/246，render/fx_pxplane.gd）同一套：1 特效像素 = 1 美术像素（g.PX 世界像素、对齐 2 像素格）、15 fps 全局节拍换帧、
## 色层当普通物体画进单位排序（吃场景光），最亮的热芯进光学发光层（共用转平面的 EMIT_CAP），命中挂 ≤ 0.15 秒的照地光、Noita 颗粒。
## 斩线 = 德克萨斯「一刀一道」（_tx_draw_line1）的画法：芯近白（前两拍过曝）、两侧一格角色色、两头收尖，hold 拍后断成碎段收掉。
## 角色定稿色：德克萨斯琥珀 TX_C（docs/257）、拉普兰德淡紫 LP（docs/273）、能天使红橙 RAMP.n（docs/262）、艾丽妮白 + 亮紫 LT（docs/272）、流明钢蓝 LM_C（docs/255）。
## 每招元素 ≤ 3 种（11-07 合击版：人物原地出手、不移动不隐身）：宿敌 = 两道剑气 + 相撞星芒 + 锯齿冲击波；企鹅物流 = 车（pixgen 贴图）+ 齐射曳光 + 胎痕；灯下审决 = 灯塔（pixgen 贴图）+ 聚光描边圈 + 审判光矛。裂网 / 烟尘 / 粒子在 run/bond2_pf.gd。
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
		"b_rival":   # 十字斩（11-07）：X 形预兆细线 → 两刀各一帧劈出（亮两拍后冷成地上的暗斩痕）；裂缝 / 烟尘在 run/bond2_pf.gd
			var L: float = a.L
			_push({"k": "xpre", "c": c, "d1": a.d1, "d2": a.d2, "L": L, "t0": t, "life": B2.RV_T2})
			_push({"k": "xcut", "c": c, "d": a.d1, "L": L, "w": float(a.hw), "pal": TX, "t0": t + B2.RV_T1, "life": 1.6})
			_push({"k": "xcut", "c": c, "d": a.d2, "L": L, "w": float(a.hw), "pal": LP, "t0": t + B2.RV_T2, "life": 1.6})
			_push({"k": "clash", "c": c + Vector2(0, -20), "t0": t + B2.RV_HIT, "life": 0.2})
			for q in 2:   # Noita 式颗粒：每刀沿斩痕 4 处各迸一把火星（会弹地、落地暗掉），交点一把余烬
				var d: Vector2 = a.d1 if q == 0 else a.d2
				var pal: Array = TX if q == 0 else LP
				var o = a.who.texas if q == 0 else a.who.lappland
				for j in 4:
					var pj: Vector2 = c + d * (float(j) / 3.0 - 0.5) * L * 0.8
					due.append([t + (B2.RV_T1 if q == 0 else B2.RV_T2) + 0.02 * float(j), "grains", {"o": o, "p": pj + Vector2(0, LIFT * 0.5), "n": 7, "c0": pal[5], "c1": pal[3], "mat": "streak"}])
			due.append([t + B2.RV_HIT, "grains", {"o": a.who.texas, "p": c + Vector2(0, LIFT * 0.5), "n": 14, "c0": Color(1.0, 0.9, 0.7), "c1": TX[3], "mat": "ember"}])
			due.append([t + B2.RV_HIT + 0.02, "grains", {"o": a.who.lappland, "p": c + Vector2(0, LIFT * 0.5), "n": 10, "c0": LP[5], "c1": LP[3], "mat": "ember"}])
		"b_penguin":   # 碾过去：车从画面外横向冲进来、穿过最密处再开出去（车上不画人）；能天使原地齐射的曳光由 shots() 逐发加
			_push({"k": "car", "c": c, "dl": a.dl, "run": float(a.run), "out": float(a.out), "t0": t, "T0": B2.PG_T0, "T1": B2.PG_T1, "life": 1.0})
			_push({"k": "skid", "c": c, "dl": a.dl, "run": float(a.run), "out": float(a.out), "t0": t, "T0": B2.PG_T0, "T1": B2.PG_T1, "life": 2.2})
			var S: Vector2 = c - Vector2(a.dl) * float(a.run)
			var LL: float = float(a.run) + float(a.out)
			for bm in a.bombs:   # 炸弹：从车顶抛出、0.3 秒落到车道两侧
				var tb: float = t + B2.PG_T0 + float(bm[0]) * (B2.PG_T1 - B2.PG_T0)
				_push({"k": "bomb", "a": S + Vector2(a.dl) * LL * float(bm[0]) + Vector2(0, -70), "b": bm[2], "t0": tb, "dur": B2.PG_BOMB, "life": B2.PG_BOMB + 0.05})
				due.append([tb + B2.PG_BOMB, "grains", {"o": a.who.texas, "p": bm[2] + Vector2(0, LIFT * 0.5), "n": 12, "c0": Color(1.0, 0.85, 0.5), "c1": EX[3], "mat": "ember"}])
				due.append([tb + B2.PG_BOMB, "grains", {"o": a.who.texas, "p": bm[2] + Vector2(0, LIFT * 0.5), "n": 6, "c0": Color(0.3, 0.3, 0.32), "c1": Color(0.16, 0.16, 0.18), "mat": "rock"}])
		"b_inq":   # 合击：灯塔从最密处拔地而起 → 灯室点亮、暖光圈从塔脚扫开（描边 + 紫印）→ 艾丽妮的审判光矛落到塔前
			_push({"k": "lh", "O": a.O, "c": c, "r": float(a.r), "t0": t, "life": 1.4})
			_push({"k": "lance", "p": c + Vector2(0, 60), "t0": t + B2.IQ_HIT - 0.12, "t1": t + B2.IQ_HIT, "life": 0.45})
			due.append([t + B2.IQ_HIT, "grains", {"o": a.who.irene, "p": c + Vector2(0, LIFT * 0.5), "n": 16, "c0": IR[5], "c1": IR[3], "mat": "streak"}])
			due.append([t + B2.IQ_HIT + 0.05, "grains", {"o": a.who.irene, "p": c + Vector2(0, LIFT * 0.5), "n": 12, "c0": LAMPG[5], "c1": LAMPG[3], "mat": "rise"}])
			due.append([t + 0.35, "light", {"o": a.who.lumen, "p": a.O + Vector2(0, -float(LH_LAMP_Y)), "r": 160.0, "i": 0.6, "c": LAMPG[4], "life": 0.15}])


## 能天使原地齐射（bond2._penguin 每 0.09 秒调一次）：从她枪口到每个目标一道曳光
func shots(a: Dictionary, from: Vector2, targets: Array) -> void:
	var mz: Vector2 = from + Vector2(0, -30)
	for p in targets:
		_push({"k": "tracer", "a": mz, "b": p, "t0": g.t, "life": 0.3})
	if not targets.is_empty() and a.who.exusiai != null:
		due.append([g.t + 0.067, "light", {"o": a.who.exusiai, "p": targets[0], "r": 90.0, "i": 0.4, "c": EX[4]}])


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
			"lane", "lamp", "cross", "mark", "shock", "skid", "xpre":
				sk = GROUND_KEY
			"car":
				sk = r._car_pos(it).y + 1.0
			"lh":
				sk = float((it.O as Vector2).y) + 1.0
				out.append({"bd2": it, "skey": 1.0e9, "beam": true})   # 光锥画在所有单位上面
			"clash":
				sk = float((it.c as Vector2).y) + 40.0
			"xcut":
				sk = GROUND_KEY
				out.append({"bd2": it, "skey": 1.0e9, "blade": true})   # 亮的两拍画在单位上面，冷下来的斩痕留在地面层
			"ln", "tracer", "ghost", "qi", "bomb":
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
	if item.get("blade", false):
		r._draw_xcut(ci, it, true)
		return
	match str(it.k):
		"clash":
			r._draw_clash(ci, it)
		"xcut":
			r._draw_xcut(ci, it, false)
		"xpre":
			r._draw_xpre(ci, it)
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
		"qi":
			r._draw_qi(ci, it)
		"lance":
			r._draw_lance(ci, it)
		"bomb":
			r._draw_bomb(ci, it)


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
## pixgen 出图（11-07，tools/imagegen：bd2_car_2 / bd2_lh_2，像素化 --cell 2）：1 纹素 = 1 世界像素（= 半个美术像素，同 @2x 干员帧）
const CAR_TEX := "res://art/fx/fx_bd2_car@2x.png"     # 240 × 152，埃尔法式 MPV + 企鹅物流涂鸦（bd2_van_3，用户 11-07 给参考图），车头朝右，(120, 136) 为着地点
const LH_TEX := "res://art/fx/fx_bd2_lh@2x.png"       # 108 × 240（bd2_lh_2 按 54 格重新像素化：塔要整根放进画面），底边中心为着地点，灯室中心离底 200
const CAR_FOOT := Vector2(120, 136)
const LH_LAMP_Y := 200.0


func _tex(path: String) -> Texture2D:
	var key := "bd2:" + path
	if not g.tex.has(key):
		g.tex[key] = load(path) if ResourceLoader.exists(path) else null
	return g.tex[key]


## 剑气（宿敌合击）：一道新月形剑气从出手者身上飞向撞点（2–3 拍，不补间：每拍跳一大段），后面一条拖影带；芯近白、两侧本人色
func _draw_qi(ci, it: Dictionary) -> void:
	var t: float = g.t
	var t0: float = it.t0
	var t1: float = it.t1
	if t < t0 or t > t1 + 0.05:
		return
	var a: Vector2 = it.a
	var b: Vector2 = it.b
	var nb: float = maxf(1.0, floor((t1 - t0) * 15.0))
	var k: float = clampf(floor((t - t0) * 15.0 + 1.0) / nb, 0.0, 1.0)
	var p: Vector2 = a.lerp(b, k)
	var d: Vector2 = (b - a).normalized() if b != a else Vector2.RIGHT
	var nv: Vector2 = d.orthogonal()
	var pal: Array = it.pal
	var px: float = g.PX
	var p0: Vector2 = a.lerp(b, maxf(0.0, k - 0.45))
	var n: int = int(p0.distance_to(p) / px)
	for i in range(0, n, 2):   # 拖影带：越后越淡、越窄
		var u: float = float(i) / float(maxi(1, n))
		var q: Vector2 = p0.lerp(p, u)
		var w: int = 1 + int(u * 3.0)
		for s in range(-w, w + 1):
			_cell(ci, q + nv * float(s) * px, Color(pal[4].r, pal[4].g, pal[4].b, 0.25 + 0.45 * u))
	for j in range(-14, 15):   # 新月：弧心在剑气后方，弧向前凸
		var ang: float = float(j) / 14.0 * 1.05
		var off: Vector2 = d * cos(ang) * 30.0 + nv * sin(ang) * 30.0 - d * 22.0
		var th: int = 3 - absi(j) / 5
		for s in th:
			var q2: Vector2 = p + off - d * float(s) * px
			_cell(ci, q2, Color(1.3, 1.28, 1.24) if s == 0 and absi(j) < 9 else (pal[5] if s < 2 else pal[3]))
		if j % 4 == 0:
			_glow(p + off, pal[5])


## 车（企鹅物流，11-07 用户：埃尔法式 MPV + 企鹅物流涂鸦，「直接碾过去」）：从 c - dl·run 一路开到 c + dl·out（T0 → T1，15 fps 每拍跳一段 + 两份拖影 + 速度线），
## 开过去后再往前开 0.15 秒淡出；车身两拍一颠
func _car_pos(it: Dictionary) -> Vector2:
	var age: float = g.t - float(it.t0)
	var T0: float = it.T0
	var T1: float = it.T1
	var k: float = (floor((age - T0) * 15.0 + 1.0) / 15.0) / (T1 - T0)
	var dl: Vector2 = it.dl
	return Vector2(it.c) - dl * float(it.run) + dl * (float(it.run) + float(it.out)) * maxf(0.0, k)


func _draw_car(ci, it: Dictionary) -> void:
	var age: float = g.t - float(it.t0)
	var T0: float = it.T0
	var T1: float = it.T1
	if age < T0 or age > T1 + 0.2:
		return
	var tex: Texture2D = _tex(CAR_TEX)
	if tex == null:
		return
	var dl: Vector2 = it.dl
	var flip: bool = dl.x < 0.0
	var fs: float = -1.0 if flip else 1.0
	var p: Vector2 = _snap(_car_pos(it))
	var al: float = 1.0 - clampf((age - T1) / 0.2, 0.0, 1.0)
	var sz: Vector2 = tex.get_size()
	var bounce: float = g.PX if (int(floor(g.t * 15.0)) / 2) % 2 == 0 else 0.0
	for j in [2, 1]:   # 拖影：沿车道往后 80 / 160，越后越淡、偏琥珀
		var q: Vector2 = p - dl * 80.0 * float(j)
		ci.draw_set_transform(q, 0.0, Vector2(fs, 1.0))
		ci.draw_texture_rect(tex, Rect2(-CAR_FOOT, sz), false, Color(1.0, 0.82, 0.6, 0.26 * al / float(j)))
	for s5 in 6:   # 速度线
		var y0: float = -14.0 - 16.0 * float(s5)
		var ln: float = 70.0 + 40.0 * float((s5 * 7) % 3)
		var st: Vector2 = p - dl * (CAR_FOOT.x + 8.0) + Vector2(0, y0)
		for i in range(0, int(ln / g.PX), 2):
			_cell(ci, st - dl * float(i) * g.PX, Color(1.0, 0.88, 0.65, 0.5 * al * (1.0 - float(i) * g.PX / ln)))
	ci.draw_set_transform(p + Vector2(0, -bounce), 0.0, Vector2(fs, 1.0))
	ci.draw_texture_rect(tex, Rect2(-CAR_FOOT, sz), false, Color(1, 1, 1, al))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_glow(p + dl * (sz.x * 0.45) + Vector2(0, -40.0), Color(1.0, 0.95, 0.8))   # 车头灯


## 胎痕：车道最后一段两道断续暗痕，撞点处一道横甩的刹车痕；撞完 1 秒内逐渐断开
func _draw_skid(ci, it: Dictionary) -> void:
	var age: float = g.t - float(it.t0)
	if age < float(it.T0):
		return
	var dl: Vector2 = it.dl
	var nl: Vector2 = dl.orthogonal()
	var c: Vector2 = it.c
	var s0: Vector2 = c - dl * float(it.run)
	var head: Vector2 = _car_pos(it) if age < float(it.T1) else c + dl * float(it.out)
	var brk: float = clampf((age - float(it.T1)) / 1.0, 0.0, 0.9)
	var n: int = int(s0.distance_to(head) / g.PX)
	for i in range(0, n, 2):
		if brk > 0.0 and fposmod(float(i) * 0.618034, 1.0) < brk:
			continue
		var q: Vector2 = s0 + dl * float(i) * g.PX - dl * CAR_FOOT.x * 0.6
		for sd in [-1.0, 1.0]:
			_cell(ci, q + nl * 16.0 * sd + Vector2(0, 2), Color(0.05, 0.05, 0.06, 0.8))


## 灯塔：流明身后从下往上显形（0–0.35 秒），之后灯室常亮（暖金发光点）；最后 0.3 秒淡出
func _draw_lh(ci, it: Dictionary) -> void:
	var age: float = g.t - float(it.t0)
	var life: float = float(it.life)
	if age < 0.0 or age > life:
		return
	var tex: Texture2D = _tex(LH_TEX)
	if tex == null:
		return
	var sz: Vector2 = tex.get_size()
	var k: float = clampf(floor(age * 15.0 + 1.0) / 5.0, 0.0, 1.0)
	var al: float = 1.0 - clampf((age - (life - 0.3)) / 0.3, 0.0, 1.0)
	var O: Vector2 = _snap(it.O)
	var vis: float = sz.y * k
	ci.draw_texture_rect_region(tex, Rect2(O + Vector2(-sz.x * 0.5, -vis), Vector2(sz.x, vis)), Rect2(0, sz.y - vis, sz.x, vis), Color(1, 1, 1, al))
	if age >= 0.3:
		var lp: Vector2 = O + Vector2(0, -LH_LAMP_Y)
		for i in 6:
			_glow(lp + Vector2(float(i % 3 - 1) * 8.0, float(i / 3) * 10.0 - 5.0), LAMPG[5])


## 聚光（画在单位上面）：灯室 → 落点的一束暖金光（两条亮边 + 光里的尘点，越往下越宽越淡），落点一圈断续描边光圈（docs/294 §7：只描边，不整片填充），
## 圈里的敌人头顶紫印；光矛落下后光束收掉
func _draw_beam(ci, it: Dictionary) -> void:
	var age: float = g.t - float(it.t0)
	var hit: float = B2.IQ_HIT
	if age < 0.3 or age > hit + 0.3:
		return
	var px: float = g.PX
	var O: Vector2 = _snap(it.O)
	var lp: Vector2 = O + Vector2(0, -LH_LAMP_Y)
	var c: Vector2 = _snap(it.c)
	var r: float = it.r
	var fa: float = 1.0 - clampf((age - hit) / 0.3, 0.0, 1.0)
	var bt: int = int(floor(g.t * 15.0))
	# 灯室点亮：十字星芒（两拍大、之后呼吸）+ 发光点
	var f: int = int(floor((age - 0.3) * 15.0))
	_star(ci, lp, [16, 12, 9, 10][mini(f, 3)] if f < 4 else (9 + bt % 2), [LAMPG[0], LAMPG[1], LAMPG[2], LAMPG[3], LAMPG[4], LAMPG[5], Color.WHITE])
	for i in 4:
		_glow(lp + Vector2(float(i % 2) * 6.0 - 3.0, float(i / 2) * 6.0 - 3.0), LAMPG[5])
	# 暖光圈从塔脚扫开（3 拍到 r，断续描边 2–3 格厚、前沿亮），到位后断开收掉；圈里地面闪光点
	var k: float = clampf(floor((age - 0.35) * 15.0 + 1.0) / 3.0, 0.0, 1.0)
	if age < 0.35:
		return
	var rr: float = lerpf(40.0, r, k)
	var segs: int = maxi(24, int(TAU * rr / (px * 2.0)))
	for i in segs:
		if (i / 6 + bt) % 5 == 0:   # 每 30 格断一小段
			continue
		var a0: float = TAU * float(i) / float(segs)
		var dv: Vector2 = Vector2(cos(a0), sin(a0) * SQ)
		var th: int = 2 + int(fposmod(float(i) * 0.618, 1.0) * 2.0)
		for w in th:
			_cell(ci, c + dv * (rr - float(w) * px * 1.5), Color(Color(1.25, 1.2, 1.05) if (w == 0 and k < 1.0) else (LAMPG[5] if w < 2 else LAMPG[3]), fa))
		if i % 12 == 0:
			_glow(c + dv * rr, LAMPG[4])
	for i in 50:
		var h3: float = fposmod(float(i) * 0.754877 + float(bt) * 0.093, 1.0)
		var h4: float = fposmod(float(i) * 0.569840 + float(bt) * 0.131, 1.0)
		var r2: float = sqrt(h4) * rr * 0.95
		_cell(ci, c + Vector2(cos(h3 * TAU), sin(h3 * TAU) * SQ) * r2, Color(LAMPG[5], fa * 0.75))
	if age < hit:
		for e in g.enemies:
			if e.dead or e.get("friendly", false):
				continue
			var dd: Vector2 = e.pos - c
			if dd.x * dd.x + dd.y * dd.y / (SQ * SQ) > rr * rr:
				continue
			var hp: Vector2 = _snap(e.pos + Vector2(0, -float(e.get("r", 10.0)) * 1.6 - 10.0))
			for dv2 in [Vector2.ZERO, Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				_cell(ci, hp + dv2 * px, IR[5] if dv2 == Vector2.ZERO else IR[3])


## 审判光矛：从落点正上方 420 处 2 拍扎下（不补间），矛身白芯 + 紫边、后面一条拖影；落地一拍竖直光柱，再两拍缩成落点星芒
func _draw_lance(ci, it: Dictionary) -> void:
	var t: float = g.t
	var t0: float = it.t0
	var t1: float = it.t1
	if t < t0 or t > t1 + 0.3:
		return
	var p: Vector2 = _snap(it.p)
	var px: float = g.PX
	if t < t1:
		var k: float = clampf(floor((t - t0) * 15.0 + 1.0) / 2.0, 0.0, 1.0)
		var tip: Vector2 = p + Vector2(0, -420.0 * (1.0 - k))
		for i in 70:   # 矛身（矛尖在下）
			var q: Vector2 = tip + Vector2(0, -float(i) * px)
			var w: int = 2 if i < 50 else 1
			for s in range(-w, w + 1):
				_cell(ci, q + Vector2(float(s) * px, 0), Color(1.3, 1.25, 1.4) if absi(s) == 0 else (IR[5] if absi(s) == 1 else IR[3]))
		for i in range(70, 150, 2):   # 拖影
			_cell(ci, tip + Vector2(0, -float(i) * px), Color(IR[4], 0.6 * (1.0 - float(i - 70) / 80.0)))
		_glow(tip, IR[5])
		return
	var f: int = int(floor((t - t1) * 15.0))
	if f == 0:   # 落地一拍：竖直光柱
		for i in 110:
			for s in range(-3, 4):
				_cell(ci, p + Vector2(float(s) * px, -float(i) * px), Color(1.3, 1.25, 1.4) if absi(s) < 2 else IR[4])
			if i % 10 == 0:
				_glow(p + Vector2(0, -float(i) * px), IR[5])
	else:
		_star(ci, p + Vector2(0, -6), [14, 9, 5, 3][mini(f - 1, 3)], IR)


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


## 十字斩预兆：落点上两条 X 形细线（1 格、隔格断开、按节拍闪），提示两刀要落在哪
func _draw_xpre(ci, it: Dictionary) -> void:
	var age: float = g.t - float(it.t0)
	if age < 0.0 or age > float(it.life):
		return
	var bt: int = int(floor(g.t * 15.0))
	var c: Vector2 = it.c
	var L: float = it.L
	for q in 2:
		var d: Vector2 = it.d1 if q == 0 else it.d2
		var pal: Array = TX if q == 0 else LP
		var n: int = int(L / g.PX)
		for i in range(0, n, 3):
			if (i / 3 + bt) % 3 == 0:
				continue
			var u: float = float(i) / float(n)
			_cell(ci, c + d * (u - 0.5) * L + Vector2(0, -LIFT * 0.3), Color(pal[4], 0.55 * (1.0 - absf(u - 0.5) * 1.4)))


## 十字斩一刀：第一拍整条直接出现（不长出来）——两头尖、中间宽 w，芯近白、两侧本人色；亮两拍（blade = 画在单位上面）；
## 之后地面层留一道暗斩痕（中间一格暗芯 + 两侧暗本人色），1 秒内逐格碎掉
func _draw_xcut(ci, it: Dictionary, blade: bool) -> void:
	var age: float = g.t - float(it.t0)
	if age < 0.0 or age > float(it.life):
		return
	var f: int = int(floor(age * 15.0))
	if blade != (f < 2):
		return
	var c: Vector2 = it.c
	var d: Vector2 = it.d
	var nv: Vector2 = d.orthogonal()
	var L: float = it.L
	var pal: Array = it.pal
	var px: float = g.PX
	var n: int = int(L / px)
	var wmax: float = minf(float(it.w) * 0.32, 18.0) / px
	var melt: float = clampf((age - 0.6) / 0.9, 0.0, 1.0)
	for i in n:
		var u: float = float(i) / float(n)
		var q: Vector2 = c + d * (u - 0.5) * L
		var w: int = int(round(wmax * pow(sin(u * PI), 0.7)))
		if blade:
			for s in range(-w, w + 1):
				var e: float = absf(float(s)) / maxf(1.0, float(w))
				var col: Color = Color(1.35, 1.32, 1.28) if (e < 0.35 and f == 0) else (pal[6] if e < 0.35 else (pal[5] if e < 0.7 else pal[3]))
				_cell(ci, q + nv * float(s) * px + Vector2(0, -LIFT * 0.3), col)
			if i % 10 == 0:
				_glow(q + Vector2(0, -LIFT * 0.3), pal[5])
		else:
			if melt > 0.0 and fposmod(float(i) * 0.618034, 1.0) < melt:
				continue
			var w2: int = maxi(0, w / 2)
			for s in range(-w2, w2 + 1):
				_cell(ci, q + nv * float(s) * px, Color(0.06, 0.05, 0.06, 0.85) if s == 0 else Color(pal[1], 0.8))


## 交点爆闪：两色四芒（横向左琥珀 / 右淡紫，竖向白 → 本人色），3 拍收
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


## 炸弹：一颗圆滚滚的黑炸弹（5 × 5 格，高光一格、引信火星两拍一闪）沿抛物线从车顶飞到落点，后面拖一串火星
func _draw_bomb(ci, it: Dictionary) -> void:
	var age: float = g.t - float(it.t0)
	var dur: float = it.dur
	if age < 0.0 or age > dur:
		return
	var a: Vector2 = it.a
	var b: Vector2 = it.b
	var px: float = g.PX
	var bt: int = int(floor(g.t * 15.0))
	for j in 4:   # 火星拖尾
		var uj: float = clampf((age - 0.03 * float(j + 1)) / dur, 0.0, 1.0)
		var qj: Vector2 = a.lerp(b, uj) + Vector2(0, -120.0 * 4.0 * uj * (1.0 - uj))
		_cell(ci, qj, Color(EX[5] if j < 2 else EX[3], 0.9 - 0.2 * float(j)))
	var u: float = clampf(age / dur, 0.0, 1.0)
	var p: Vector2 = _snap(a.lerp(b, u) + Vector2(0, -120.0 * 4.0 * u * (1.0 - u)))
	for y in range(-2, 3):
		for x in range(-2, 3):
			if absi(x) + absi(y) > 3:
				continue
			_cell(ci, p + Vector2(x, y) * px, Color("#3a3f4a") if (x == -1 and y == -1) else Color("#14161b"))
	if bt % 2 == 0:
		_cell(ci, p + Vector2(1, -3) * px, EX[5])
		_glow(p + Vector2(1, -3) * px, EX[4])
