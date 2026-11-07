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
	if str(a.id) in ["b_lesson", "b_tide", "b_vortex", "b_fins", "b_hunt"]:
		cast5(a)
		return
	match str(a.id):
		"b_rival":   # 十字斩（11-07）：X 形预兆细线 → 两刀各一帧劈出（亮两拍后冷成地上的暗斩痕）；裂缝 / 烟尘在 run/bond2_pf.gd
			var L: float = a.L
			_push({"k": "xcut", "c": c, "d": a.d1, "L": L, "w": float(a.hw), "pal": TX, "t0": t + B2.RV_T1, "life": 2.2})
			_push({"k": "xcut", "c": c, "d": a.d2, "L": L, "w": float(a.hw), "pal": LP, "t0": t + B2.RV_T2, "life": 2.2})
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
			_push({"k": "car", "c": c, "dl": a.dl, "run": float(a.run), "out": float(a.out), "t0": t, "T0": B2.PG_T0, "T1": B2.PG_T1, "life": B2.PG_T1 + 0.3, "tx": a.who.texas})
			_push({"k": "skid", "c": c, "dl": a.dl, "run": float(a.run), "out": float(a.out), "t0": t, "T0": B2.PG_T0, "T1": B2.PG_T1, "life": B2.PG_T1 + 1.6})
			var S: Vector2 = c - Vector2(a.dl) * float(a.run)
			var LL: float = float(a.run) + float(a.out)
			for bm in a.bombs:   # 炸弹：从车顶抛出、0.3 秒落到车道两侧
				var tb: float = t + B2.PG_T0 + float(bm[0]) * (B2.PG_T1 - B2.PG_T0)
				var kb: float = float(bm[0])
				var fk: float = kb * kb * 1.6 if kb < 0.25 else 0.1 + (kb - 0.25) * 1.2
				_push({"k": "bomb", "a": S + Vector2(a.dl) * LL * fk + Vector2(0, -90), "b": bm[2], "t0": tb, "dur": B2.PG_BOMB, "life": B2.PG_BOMB + 0.05})
				due.append([tb + B2.PG_BOMB, "grains", {"o": a.who.texas, "p": bm[2] + Vector2(0, LIFT * 0.5), "n": 12, "c0": Color(1.0, 0.85, 0.5), "c1": EX[3], "mat": "ember"}])
				due.append([tb + B2.PG_BOMB, "grains", {"o": a.who.texas, "p": bm[2] + Vector2(0, LIFT * 0.5), "n": 6, "c0": Color(0.3, 0.3, 0.32), "c1": Color(0.16, 0.16, 0.18), "mat": "rock"}])
		"b_inq":   # 合击（11-07 改）：艾丽妮的提灯飞到落点上空悬停 → 灯罩打开洒下暖金光雨（光圈描边 + 紫印）→ 审判光矛从灯下劈落
			var ir = a.who.irene
			var from: Vector2 = (ir.pos if ir != null else c) + Vector2(0, -40)
			_push({"k": "lantern", "a": from, "L": a.O, "c": c, "t0": t, "t1": t + 0.5, "life": B2.IQ_HIT + 0.55})
			_push({"k": "rain", "L": a.O, "c": c, "r": float(a.r), "t0": t, "life": B2.IQ_HIT + 0.3})
			_push({"k": "lance", "p": c, "top": c.y - float(a.O.y), "t0": t + B2.IQ_HIT - 0.2, "t1": t + B2.IQ_HIT, "life": 0.6})
			due.append([t + 0.6, "light", {"o": ir, "p": a.O, "r": 160.0, "i": 0.7, "c": LAMPG[4], "life": 0.15}])
			due.append([t + B2.IQ_HIT, "grains", {"o": ir, "p": c + Vector2(0, LIFT * 0.5), "n": 16, "c0": IR[5], "c1": IR[3], "mat": "streak"}])
			due.append([t + B2.IQ_HIT + 0.05, "grains", {"o": ir, "p": c + Vector2(0, LIFT * 0.5), "n": 12, "c0": LAMPG[5], "c1": LAMPG[3], "mat": "rise"}])


## 能天使原地齐射（bond2._penguin 每 0.09 秒调一次）：从她枪口到每个目标一道曳光
func shots(a: Dictionary, from: Vector2, targets: Array) -> void:
	var mz: Vector2 = from + Vector2(0, -30)
	for p in targets:
		_push({"k": "tracer", "a": mz, "b": p, "t0": g.t, "life": 0.3})
	if not targets.is_empty() and a.who.exusiai != null:
		due.append([g.t + 0.067, "light", {"o": a.who.exusiai, "p": targets[0], "r": 90.0, "i": 0.4, "c": EX[4]}])


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
			"skid", "chain", "trench", "plan", "tidering":
				sk = GROUND_KEY
			"car":
				sk = r._car_pos(it).y + 1.0
			"clash":
				sk = float((it.c as Vector2).y) + 40.0
			"anchor":
				sk = float((it.b as Vector2).y) + 1.0
			"surge":
				sk = maxf((it.A as Vector2).y, (it.F as Vector2).y) + 2.0
			"tslash", "fin", "spear":
				sk = float((it.c as Vector2).y) + 2.0
			"lantern":
				sk = 1.0e9 - 1.0
			"rain":
				sk = GROUND_KEY
				out.append({"bd2": it, "skey": 1.0e9 - 2.0, "rain": true})   # 光雨画在单位上面，地面闪光在地面层
			"xcut":
				sk = GROUND_KEY
				out.append({"bd2": it, "skey": 1.0e9, "blade": true})   # 亮的两拍画在单位上面，冷下来的斩痕留在地面层
			"tracer", "bomb":
				sk = maxf((it.a as Vector2).y, (it.b as Vector2).y) + 2.0
			_:
				sk = float((it.p as Vector2).y) + 2.0
		out.append({"bd2": it, "skey": sk})
	return out


static func draw_sorted(game, ci, item: Dictionary) -> void:
	var r = game.get_meta("fx_bond2")
	var it: Dictionary = item.bd2
	if item.get("rain", false):
		r._draw_rain(ci, it, true)
		return
	if item.get("blade", false):
		r._draw_xcut(ci, it, true)
		return
	match str(it.k):
		"clash":
			r._draw_clash(ci, it)
		"xcut":
			r._draw_xcut(ci, it, false)
		"car":
			r._draw_car(ci, it)
		"skid":
			r._draw_skid(ci, it)
		"tracer":
			r._draw_tracer(ci, it)
		"lance":
			r._draw_lance(ci, it)
		"bomb":
			r._draw_bomb(ci, it)
		"anchor":
			r._draw_anchor(ci, it)
		"lantern":
			r._draw_lantern(ci, it)
		"rain":
			r._draw_rain(ci, it, false)
		"chain":
			r._draw_chain(ci, it)
		"surge":
			r._draw_surge(ci, it)
		"trench":
			r._draw_trench(ci, it)
		"tslash":
			r._draw_tslash(ci, it)
		"plan":
			r._draw_plan(ci, it)
		"fin":
			r._draw_fin(ci, it)
		"tidering":
			r._draw_tidering(ci, it)
		"spear":
			r._draw_spear(ci, it)


# ================================================================ 画法

func _star(ci, c: Vector2, arm: int, pal: Array) -> void:
	var px: float = g.PX
	_cell(ci, c, pal[6])
	_glow(c, pal[6])
	for i in range(1, arm + 1):
		var col: Color = pal[5] if i < arm else pal[4]
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			_cell(ci, c + d * float(i) * px, col)


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


# ================================================================ 第二版主形（docs/296）：运行时按像素格生成贴图（不进包）+ 代码画

const LAMPG := [Color("#1c1408"), Color("#4a3612"), Color("#8c6a26"), Color("#cfa24a"), Color("#efd08a"), Color("#fff0c6"), Color("#ffffff")]   # 艾丽妮手提灯暖金（docs/272 LAMP）
## pixgen 出图（11-07，tools/imagegen：bd2_car_2 / bd2_lh_2，像素化 --cell 2）：1 纹素 = 1 世界像素（= 半个美术像素，同 @2x 干员帧）
const CAR_TEX := "res://art/fx/fx_bd2_car@2x.png"     # 240 × 152，埃尔法式 MPV + 企鹅物流涂鸦（bd2_van_3，用户 11-07 给参考图），车头朝右，(120, 136) 为着地点
const CAR_FOOT := Vector2(120, 136)


func _tex(path: String) -> Texture2D:
	var key := "bd2:" + path
	if not g.tex.has(key):
		g.tex[key] = load(path) if ResourceLoader.exists(path) else null
	return g.tex[key]


## 车（企鹅物流，11-07 用户：埃尔法式 MPV + 企鹅物流涂鸦，「直接碾过去」）：从 c - dl·run 一路开到 c + dl·out（T0 → T1，15 fps 每拍跳一段 + 两份拖影 + 速度线），
## 开过去后再往前开 0.15 秒淡出；车身两拍一颠
func _car_pos(it: Dictionary) -> Vector2:   # 11-07 用户「车子像是漂移」：逐帧平滑移动（不按 15 fps 跳格），先加速后匀速
	var age: float = g.t - float(it.t0)
	var u: float = clampf((age - float(it.T0)) / (float(it.T1) - float(it.T0)), 0.0, 1.0)
	var k: float = u * u * 1.6 if u < 0.25 else 0.1 + (u - 0.25) * 1.2   # 前 1/4 加速，之后匀速（两段在 0.25 处接上）
	var dl: Vector2 = it.dl
	return Vector2(it.c) - dl * float(it.run) + dl * (float(it.run) + float(it.out)) * k


## 车（企鹅物流）：车道恒为水平（侧面贴图，斜着走就像漂移）；起步时车头一翘（2 拍），之后每两拍车身一颠、后轮扬土；
## 车后速度线（不画半透明重影：重影会被看成车在滑）；车头灯发光
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
	var fs: float = -1.0 if dl.x < 0.0 else 1.0
	var p: Vector2 = _snap(_car_pos(it))
	var al: float = 1.0 - clampf((age - T1) / 0.2, 0.0, 1.0)
	var sz: Vector2 = tex.get_size()
	var bt: int = int(floor((age - T0) * 15.0))
	var tilt: float = [-0.06, -0.03][bt] if bt < 2 else 0.0   # 起步车头上翘
	var bounce: float = 2.0 * g.PX if (bt / 2) % 2 == 0 and bt >= 2 else 0.0
	for s5 in 7:   # 速度线（长短不一、隔格）
		var y0: float = -10.0 - 15.0 * float(s5)
		var ln: float = 90.0 + 50.0 * float((s5 * 7) % 3)
		var st: Vector2 = p - dl * (CAR_FOOT.x + 10.0 + 12.0 * float(s5 % 2)) + Vector2(0, y0)
		for i in range(0, int(ln / g.PX), 3):
			_cell(ci, st - dl * float(i) * g.PX, Color(1.0, 0.9, 0.7, 0.55 * al * (1.0 - float(i) * g.PX / ln)))
	ci.draw_set_transform(p + Vector2(0, -bounce), tilt * fs, Vector2(fs, 1.0))
	ci.draw_texture_rect(tex, Rect2(-CAR_FOOT, sz), false, Color(1, 1, 1, al))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for d in [Vector2.ZERO, Vector2(0, -6)]:
		_glow(p + dl * (sz.x * 0.46) + Vector2(0, -34.0) + d, Color(1.0, 0.95, 0.8))   # 车头灯
	if bt % 2 == 0 and age < T1:   # 后轮扬土（Noita 颗粒，往车后上方喷）
		var key: String = "w%d" % bt
		if not it.has(key):
			it[key] = true
			var o = it.get("tx")
			if o != null and is_instance_valid(o):
				_R()._grains(o, p - dl * (sz.x * 0.32) + Vector2(0, -6), p.y + 2.0, "dust", 6, {"tier": 1, "c0": Color(0.62, 0.58, 0.52), "c1": Color(0.36, 0.33, 0.3)}, -dl + Vector2(0, -0.6))


## 胎痕（11-07 用户：保留胎痕、换表现形式，不要几何线条）：两道轮胎压痕 = 一块块斜胎面花纹（3 × 2 格、左右交错成人字），
## 深浅按哈希起伏、边上偶尔掉一格土色碎屑；车开过 1 秒后从后往前一块块褪掉
func _draw_skid(ci, it: Dictionary) -> void:
	var age: float = g.t - float(it.t0)
	if age < float(it.T0):
		return
	var dl: Vector2 = it.dl
	var nl: Vector2 = dl.orthogonal()
	var c: Vector2 = it.c
	var s0: Vector2 = c - dl * float(it.run)
	var head: Vector2 = _car_pos(it) if age < float(it.T1) else c + dl * float(it.out)
	var px: float = g.PX
	var fade: float = clampf((age - float(it.T1) - 0.6) / 0.8, 0.0, 1.0)
	var n: int = int(s0.distance_to(head - dl * CAR_FOOT.x * 0.55) / (px * 3.0))
	for i in n:
		var hz: float = fposmod(sin(float(i) * 12.9898) * 43758.5453, 1.0)
		if float(i) / float(maxi(1, n)) < fade + 0.15 * hz * fade:
			continue
		var q: Vector2 = s0 + dl * float(i) * px * 3.0
		for sd in [-1.0, 1.0]:
			var base: Vector2 = q + nl * 22.0 * sd + Vector2(0, 6)
			var off: float = 1.0 if (i % 2 == 0) == (sd > 0.0) else -1.0   # 人字纹：左右交错
			var dark: Color = Color(0.05, 0.05, 0.06, 0.75 + 0.2 * hz)
			for x in 2:
				for y in range(-1, 2):
					_cell(ci, base + dl * float(x) * px + nl * (float(y) + off * float(x) * 0.5) * px, dark)
			if hz > 0.82:
				_cell(ci, base + nl * sd * px * 3.0, Color(0.34, 0.3, 0.26, 0.8))


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
		var tip: Vector2 = p + Vector2(0, -float(it.get("top", 420.0)) * (1.0 - k))
		for i in 70:   # 矛身（矛尖在下）
			var q: Vector2 = tip + Vector2(0, -float(i) * px)
			var w: int = 3 if i < 50 else 2
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
	var ia: String = str(ops[0].id) if ops.size() > 0 and is_instance_valid(ops[0]) else ""
	var ib: String = str(ops[1].id) if ops.size() > 1 and is_instance_valid(ops[1]) else ia
	var pa: Array = PALS.get(ia, HUNT_PAL.get(ia, LP))
	var pb: Array = PALS.get(ib, HUNT_PAL.get(ib, LP))
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


## 十字斩一刀：第一拍整条直接出现（不长出来）——两头尖、中间宽 w，芯近白、两侧本人色；亮两拍（blade = 画在单位上面）；
## 之后地面层留一道暗斩痕（中间一格暗芯 + 两侧暗本人色），1 秒内逐格碎掉
func _draw_xcut(ci, it: Dictionary, blade: bool) -> void:
	var age: float = g.t - float(it.t0)
	if age < 0.0 or age > float(it.life):
		return
	var f: int = int(floor(age * 15.0))
	if blade != (f < 4):
		return
	var c: Vector2 = it.c
	var d: Vector2 = it.d
	var nv: Vector2 = d.orthogonal()
	var L: float = it.L
	var pal: Array = it.pal
	var px: float = g.PX
	var n: int = int(L / px)
	var wmax: float = minf(float(it.w) * 0.5, 26.0) / px
	var melt: float = clampf((age - 1.0) / 1.1, 0.0, 1.0)
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


# ================================================================ 深海猎人五条（11-07 合击版：人物原地出手，物件砸到怪群上）
## 各人定稿色（data/fx_pxplane/*.json palette：dark / main / hot），按 7 阶排（暗 → 白）
const SK := [Color("#0b1a3a"), Color("#1c3570"), Color("#3a62c0"), Color("#598cf2"), Color("#93b4f7"), Color("#cddcfb"), Color("#ffffff")]
const GL := [Color("#0d1a2e"), Color("#1f3658"), Color("#35598f"), Color("#4c80c7"), Color("#7fa6e0"), Color("#c9d9ee"), Color("#ffffff")]
const GLA := Color("#b3a8ee")    # 歌蕾蒂娅 accent 淡紫
const SPP := [Color("#0d1832"), Color("#1d3866"), Color("#2c5a9a"), Color("#3a77c2"), Color("#78afe6"), Color("#c4e2fa"), Color("#ffffff")]
const SPA := Color("#ffa04a")    # 归溟幽灵鲨 accent 橙
const ULP := [Color("#0c1235"), Color("#1a2766"), Color("#2e45a0"), Color("#4463c8"), Color("#7b93e6"), Color("#c0cbf6"), Color("#ffffff")]
const SKA := [Color("#0e1d4a"), Color("#1a3584"), Color("#2752c4"), Color("#4f80ec"), Color("#9dbcff"), Color("#dc4048"), Color("#ffffff")]
const HUNT_PAL := {"skadi": SK, "gladiia": GL, "specter_unchained": SPP, "ulpianus": ULP, "skalter": SKA}
const ANCHOR_TEX := "res://art/fx/fx_bd2_anchor@2x.png"   # pixgen bd2_anchor（11-07），底边中心着地
const FIN_TEX := "res://art/fx/fx_bd2_fin@2x.png"         # pixgen bd2_fin（11-07），底边中心着水、鳍尖朝上偏左（往右游）
const WATER := Color(0.86, 0.93, 1.0)


func cast5(a: Dictionary) -> void:
	var t: float = g.t
	var c: Vector2 = a.c
	match str(a.id):
		"b_lesson":
			_push({"k": "chain", "A": a.A, "F": a.F, "t0": t, "life": B2.LS_S1 + 0.6})
			_push({"k": "anchor", "a": Vector2(a.A) + Vector2(0, -30), "b": a.F, "t0": t + 0.05, "t1": t + B2.LS_LAND, "h": 220.0, "pal": ULP, "life": B2.LS_S1 + 0.55, "sc": 1.4})
			_push({"k": "surge", "A": a.A, "F": a.F, "t0": t + B2.LS_S0, "t1": t + B2.LS_S1, "life": B2.LS_S1 - B2.LS_S0 + 0.35})
			due.append([t + B2.LS_LAND, "grains", {"o": a.who.ulpianus, "p": Vector2(a.F) + Vector2(0, LIFT * 0.5), "n": 10, "c0": Color(0.42, 0.44, 0.5), "c1": Color(0.2, 0.22, 0.26), "mat": "rock"}])
			for j in 5:
				due.append([t + lerpf(B2.LS_S0, B2.LS_S1, float(j) / 4.0), "grains", {"o": a.who.skadi, "p": Vector2(a.A).lerp(a.F, float(j) / 4.0) + Vector2(0, LIFT * 0.5), "n": 8, "c0": WATER, "c1": SK[4], "mat": "drop"}])
		"b_tide":
			_push({"k": "trench", "c": c, "d": a.d, "L": float(a.L), "t0": t, "life": B2.TD_S1 + 0.6})
			_push({"k": "tslash", "c": c, "d": a.d, "L": float(a.L), "t0": t + B2.TD_S0, "t1": t + B2.TD_S1, "life": B2.TD_S1 - B2.TD_S0 + 0.3})
			for j in 5:
				due.append([t + lerpf(B2.TD_S0, B2.TD_S1, float(j) / 4.0), "grains", {"o": a.who.specter_unchained, "p": c + Vector2(a.d) * (float(j) / 4.0 - 0.5) * float(a.L) + Vector2(0, LIFT * 0.5), "n": 7, "c0": SPP[5], "c1": SPA, "mat": "streak"}])
		"b_vortex":
			_push({"k": "plan", "c": c, "R": float(a.R), "tips": a.tips, "t0": t, "life": B2.VX_A0 + B2.VX_DA * 5.0 + 0.5})
			for i in a.tips.size():
				var ta: float = t + B2.VX_A0 + B2.VX_DA * float(i)
				_push({"k": "anchor", "a": Vector2(a.tips[i]) + Vector2(0, -520), "b": a.tips[i], "t0": ta - 0.2, "t1": ta, "h": 0.0, "pal": ULP, "life": 0.2 + 0.9, "sc": 0.9})
				due.append([ta, "grains", {"o": a.who.ulpianus, "p": Vector2(a.tips[i]) + Vector2(0, LIFT * 0.5), "n": 6, "c0": ULP[5], "c1": ULP[3], "mat": "shard"}])
		"b_fins":
			for q in 2:
				_push({"k": "fin", "c": c, "R": float(a.R), "a0": PI * float(q), "t0": t + B2.FN_T0, "t1": t + B2.FN_T1, "hit": t + B2.FN_HIT, "pal": SK if q == 0 else SPP, "life": B2.FN_HIT - B2.FN_T0 + 0.15})
				for j in 6:
					var tj: float = t + lerpf(B2.FN_T0, B2.FN_T1, float(j) / 6.0)
					var aj: float = PI * float(q) + TAU * float(j) / 6.0
					due.append([tj, "grains", {"o": a.who.skadi if q == 0 else a.who.specter_unchained, "p": c + Vector2(cos(aj), sin(aj) * SQ) * float(a.R) + Vector2(0, LIFT * 0.5), "n": 5, "c0": WATER, "c1": (SK if q == 0 else SPP)[4], "mat": "drop"}])
			due.append([t + B2.FN_HIT, "grains", {"o": a.who.skadi, "p": c + Vector2(0, LIFT * 0.5), "n": 16, "c0": WATER, "c1": SK[4], "mat": "drop"}])
		"b_hunt":
			var ids: Array = a.ps.map(func(p): return str(p.id))
			_push({"k": "tidering", "c": c, "R0": float(a.R0), "t0": t, "t1": t + B2.HT_T1, "life": B2.HT_HIT + 0.3})
			for i in ids.size():
				var ang: float = fposmod(t * 0.7, TAU) + TAU * float(i) / float(ids.size())
				_push({"k": "spear", "c": c, "ang": ang, "pal": HUNT_PAL.get(ids[i], SK), "t0": t + B2.HT_T1, "t1": t + B2.HT_HIT, "sing": ids[i] == "skalter", "life": B2.HT_HIT - B2.HT_T1 + 0.25})
			due.append([t + B2.HT_HIT, "grains", {"o": a.ps[0], "p": c + Vector2(0, LIFT * 0.5), "n": 18, "c0": WATER, "c1": SK[4], "mat": "drop"}])


## 锚：从 a 抛到 b（h > 0 抛物线；h = 0 竖直砸下），2–4 拍不补间；落地后插在地上，最后 0.3 秒淡出。缺贴图时画一个像素锚
func _draw_anchor(ci, it: Dictionary) -> void:
	var t: float = g.t
	var t0: float = it.t0
	var t1: float = it.t1
	var life: float = it.life
	if t < t0 or t > t0 + life:
		return
	var a: Vector2 = it.a
	var b: Vector2 = it.b
	var nb: float = maxf(1.0, floor((t1 - t0) * 15.0))
	var k: float = clampf(floor((t - t0) * 15.0 + 1.0) / nb, 0.0, 1.0)
	var p: Vector2 = a.lerp(b, k) + Vector2(0, -float(it.h) * 4.0 * k * (1.0 - k))
	var al: float = 1.0 - clampf((t - (t0 + life - 0.3)) / 0.3, 0.0, 1.0)
	var sc: float = float(it.get("sc", 1.0))
	var tex: Texture2D = _tex(ANCHOR_TEX)
	var sink: float = 14.0 * sc if k >= 1.0 else 0.0   # 落地后插进地里一截
	if tex != null:
		var sz: Vector2 = tex.get_size() * sc
		ci.draw_texture_rect(tex, Rect2(_snap(p) + Vector2(-sz.x * 0.5, -sz.y + sink), sz), false, Color(1, 1, 1, al))
	else:
		var pal: Array = it.pal
		for y in range(0, int(60.0 * sc / g.PX)):
			_cell(ci, p + Vector2(0, -float(y) * g.PX + sink), pal[3] if y % 5 else pal[5])
	if k < 1.0:   # 下落拖影
		for j in range(1, 4):
			var q: Vector2 = a.lerp(b, maxf(0.0, k - 0.12 * float(j)))
			_cell(ci, q + Vector2(0, -20.0 * sc), Color(ULP[4], 0.6 - 0.15 * float(j)))


## 锚链：乌尔比安手边 A → 锚落点 F，大方环（3 × 4 格，比他普攻的锁链粗一档）一环横一环竖；锚落地前跟着锚伸长，落地后绷直；浪锋扫过的那段染深海蓝，0.9 秒起往回收
func _draw_chain(ci, it: Dictionary) -> void:
	var age: float = g.t - float(it.t0)
	if age < 0.05 or age > float(it.life):
		return
	var A: Vector2 = Vector2(it.A) + Vector2(0, -26)
	var F: Vector2 = Vector2(it.F) + Vector2(0, -40)
	var kf: float = clampf(floor((age - 0.05) * 15.0 + 1.0) / floor((B2.LS_LAND - 0.05) * 15.0), 0.0, 1.0)
	var back: float = clampf((age - B2.LS_S1 - 0.3) / 0.25, 0.0, 1.0)
	var tip: Vector2 = A.lerp(F, kf * (1.0 - back))
	var sk: float = clampf((age - B2.LS_S0) / (B2.LS_S1 - B2.LS_S0), 0.0, 1.0)
	var L: float = A.distance_to(tip)
	var d: Vector2 = (F - A).normalized()
	var nv: Vector2 = d.orthogonal()
	var px: float = g.PX
	var sag: float = 18.0 * (1.0 - kf)   # 没绷直前稍微下垂
	var n: int = int(L / (px * 6.0))
	for i in n:
		var u: float = float(i) / float(maxi(1, n))
		var q: Vector2 = A.lerp(tip, u) + Vector2(0, sag * sin(u * PI))
		var dyed: bool = u * L / maxf(1.0, A.distance_to(F)) < sk
		var pal: Array = SK if dyed else ULP
		var vert: bool = i % 2 == 0
		for x in range(-2, 3):
			for y in range(-4, 4):
				var edge: bool = absi(x) == 2 or y == -4 or y == 3
				if not edge:
					continue
				var off: Vector2 = (d * float(x) + nv * float(y)) if vert else (d * float(y) + nv * float(x))
				_cell(ci, q + off * px, pal[5] if (y <= -3 and dyed) else (pal[4] if y <= -3 else (pal[3] if absi(x) == 2 and y < 0 else pal[1])))
		if dyed and i % 3 == 0:
			_glow(q, SK[5])


## 浪锋：斯卡蒂的深海蓝浪头沿锚链从 A 冲到 F（每拍跳一段）——卷起的浪唇（白芯 + 深海蓝）+ 后面一道染色拖尾
func _draw_surge(ci, it: Dictionary) -> void:
	var t: float = g.t
	var t0: float = it.t0
	var t1: float = it.t1
	if t < t0 or t > t1 + 0.1:
		return
	var A: Vector2 = Vector2(it.A) + Vector2(0, -26)
	var F: Vector2 = Vector2(it.F) + Vector2(0, -40)
	var nb: float = maxf(1.0, floor((t1 - t0) * 15.0))
	var k: float = clampf(floor((t - t0) * 15.0 + 1.0) / nb, 0.0, 1.0)
	var p: Vector2 = A.lerp(F, k)
	var d: Vector2 = (F - A).normalized()
	var nv: Vector2 = d.orthogonal()
	var px: float = g.PX
	for j in range(-24, 25):   # 浪唇：往前凸的大弧（高 100、厚 6 格），白芯 + 深海蓝
		var ang: float = float(j) / 24.0 * 1.25
		var off: Vector2 = d * cos(ang) * 40.0 + nv * sin(ang) * 54.0 - d * 30.0
		var th: int = 6 - absi(j) / 5
		for s in th:
			_cell(ci, p + off - d * float(s) * px, Color(1.3, 1.32, 1.4) if s == 0 and absi(j) < 10 else (SK[5] if s < 2 else SK[3]))
		if j % 4 == 0:
			_glow(p + off, SK[5])
	var p0: Vector2 = A.lerp(F, maxf(0.0, k - 0.35))
	var n: int = int(p0.distance_to(p) / px)
	for i in range(0, n, 2):
		var u: float = float(i) / float(maxi(1, n))
		for s in range(-3, 4):
			if (i / 2 + s) % 2 == 0:
				_cell(ci, p0.lerp(p, u) + nv * float(s) * px * 2.0, Color(SK[4], 0.3 + 0.5 * u))


## 海沟：沿 d 的一道锯齿裂口（宽度按哈希起伏，两头收尖），里面深黑 + 一格冷青边光；TD_OPEN 前只有一道淡紫钩线伸过去；0.9 秒起两拍内合拢成一道湿痕
func _draw_trench(ci, it: Dictionary) -> void:
	var age: float = g.t - float(it.t0)
	if age < 0.05 or age > float(it.life):
		return
	var c: Vector2 = it.c
	var d: Vector2 = it.d
	var nv: Vector2 = d.orthogonal()
	var L: float = it.L
	var px: float = g.PX
	var n: int = int(L / px)
	if age < B2.TD_OPEN:   # 钩线：从一头 3 拍伸过去
		var kk: float = clampf(floor((age - 0.05) * 15.0 + 1.0) / 3.0, 0.0, 1.0)
		for i in range(0, int(float(n) * kk), 3):   # 钩过去的一串水雾（上下抖、疏密不匀，不成直线）
			var hz: float = fposmod(sin(float(i) * 12.9898) * 43758.5453, 1.0)
			if hz < 0.3:
				continue
			_cell(ci, c + d * ((float(i) / float(n)) - 0.5) * L + nv * (hz - 0.6) * 18.0 + Vector2(0, -LIFT * 0.4), WATER if hz > 0.85 else (GLA if hz > 0.6 else GL[4]))
		return
	var op: float = clampf(floor((age - B2.TD_OPEN) * 15.0 + 1.0) / 2.0, 0.0, 1.0)
	var cl: float = clampf((age - B2.TD_S1 - 0.15) / 0.25, 0.0, 1.0)
	var wk: float = op * (1.0 - cl)
	for i in n:
		var u: float = float(i) / float(n)
		var q: Vector2 = c + d * (u - 0.5) * L
		var hz: float = fposmod(sin(float(i / 3) * 12.9898) * 43758.5453, 1.0)
		var w: int = int(round((6.0 + 9.0 * hz) * pow(sin(u * PI), 0.6) * wk))
		var jig: int = int(round((fposmod(sin(float(i / 5) * 7.13) * 9831.7, 1.0) - 0.5) * 4.0 * wk))
		for s in range(-w, w + 1):
			var e: int = absi(s)
			var col: Color = (Color(0.02, 0.03, 0.06) if e < w - 3 else (SPP[2] if e < w - 2 else (SPP[5] if s < 0 else SPP[4])))
			if e < w - 4 and (i + s * 3 + int(floor(g.t * 15.0))) % 11 == 0:
				col = SPP[3]   # 沟底水光
			_cell(ci, q + nv * float(s + jig) * px, col)
		if w <= 0 and cl > 0.0 and hz > 0.7:   # 合拢后只剩零星湿点（不留一条直线）
			_cell(ci, q + nv * float(jig) * px, Color(0.12, 0.18, 0.26, 0.8 * (1.0 - clampf((age - 1.1) / 0.15, 0.0, 1.0))))
		if w > 2 and i % 20 == 0:
			_glow(q + nv * float(-w + jig) * px, SPP[5])


## 斩浪：幽灵鲨一道竖起的斩浪沿海沟冲过去——竖向月牙（幽灵青 + 白芯，前沿一格橙），后面海沟里亮一段
func _draw_tslash(ci, it: Dictionary) -> void:
	var t: float = g.t
	var t0: float = it.t0
	var t1: float = it.t1
	if t < t0 or t > t1 + 0.1:
		return
	var c: Vector2 = it.c
	var d: Vector2 = it.d
	var L: float = it.L
	var nb: float = maxf(1.0, floor((t1 - t0) * 15.0))
	var k: float = clampf(floor((t - t0) * 15.0 + 1.0) / nb, 0.0, 1.0)
	var p: Vector2 = c + d * (k - 0.5) * L
	var px: float = g.PX
	for j in range(-34, 4):   # 竖起的月牙：底在海沟、往上 76 格，向前弯，厚 5 格
		var y: float = float(j) * px * 2.0
		var bow: float = 22.0 * (1.0 - pow(float(j + 15) / 19.0, 2.0))
		var th: int = 5 if j > -24 else 3
		for s in th:
			var q: Vector2 = p + Vector2(0, y) + d * (bow - float(s) * px)
			_cell(ci, q, SPA if s == 0 and j < -14 else (Color(1.25, 1.3, 1.4) if s == 0 else (SPP[5] if s == 1 else SPP[3])))
		if j % 6 == 0:
			_glow(p + Vector2(0, y) + d * bow, SPP[5])
	var p0: Vector2 = c + d * (maxf(0.0, k - 0.3) - 0.5) * L
	for i in range(0, int(p0.distance_to(p) / px), 2):
		_cell(ci, p0 + d * float(i) * px, Color(SPP[4], 0.8))


## 作战推演（11-07 用户「不要明显的简约几何线条」：箭头 / 虚线圈删掉）：外圈的水往中心卷——几股水流粒子沿螺线从外往里流（每股 5 支「推演」方向之一），
## 箭头尖（锚的落点）上一团打旋的水花；锚落下后那团水花散掉
func _draw_plan(ci, it: Dictionary) -> void:
	var age: float = g.t - float(it.t0)
	if age < 0.0 or age > float(it.life):
		return
	var c: Vector2 = it.c
	var R: float = it.R
	var px: float = g.PX
	var fa: float = 1.0 - clampf((age - B2.VX_A0 - B2.VX_DA * 5.0) / 0.4, 0.0, 1.0)
	var tips: Array = it.tips
	var flow: float = clampf(age / 0.7, 0.0, 1.0)
	for i in 150:
		var h1: float = fposmod(float(i) * 0.618034, 1.0)
		var h2: float = fposmod(float(i) * 0.754877 + age * 1.8, 1.0)   # 沿流线的位置（随时间往里走）
		var arm: int = i % tips.size()
		var a0: float = (Vector2(tips[arm]) - c).angle() + (h1 - 0.5) * 0.5
		var rr: float = R * (1.0 - h2) * flow + R * (1.0 - flow)
		var ang: float = a0 + (1.0 - rr / R) * 1.6   # 越往里转得越多（螺线）
		var q: Vector2 = c + Vector2(cos(ang) * rr, sin(ang) * rr * SQ)
		var col: Color = WATER if i % 5 == 0 else (GL[5] if i % 3 else GLA)
		_cell(ci, q, Color(col, fa * (0.4 + 0.6 * h2)))
		if i % 9 == 0:
			_cell(ci, q + Vector2(px, 0), Color(GL[4], fa * 0.6))
	for i in tips.size():
		if age < 0.15 * float(i) + 0.15 or age > B2.VX_A0 + B2.VX_DA * float(i) + 0.04:
			continue
		var tp: Vector2 = tips[i]
		for j in 14:   # 打旋的水花
			var aj: float = TAU * float(j) / 14.0 + age * 9.0
			var rj: float = 18.0 + 6.0 * sin(float(j) * 2.3 + age * 12.0)
			_cell(ci, tp + Vector2(cos(aj) * rj, sin(aj) * rj * SQ), Color(WATER if j % 3 == 0 else GL[5], fa))
		_glow(tp, GL[5])


## 背鳍：从圈上 a0 处冒出（2 拍从水下升起），绕圈心游一圈（每拍一段），身后白色破浪；到 hit 时一拍扎进水里不见
func _draw_fin(ci, it: Dictionary) -> void:
	var t: float = g.t
	var t0: float = it.t0
	var t1: float = it.t1
	if t < t0 or t > float(it.hit) + 0.05:
		return
	var c: Vector2 = it.c
	var R: float = it.R
	var nb: float = maxf(1.0, floor((t1 - t0) * 15.0))
	var k: float = clampf(floor((t - t0) * 15.0 + 1.0) / nb, 0.0, 1.0)
	var ang: float = float(it.a0) + TAU * k
	var rr: float = R * (1.0 - 0.75 * clampf((t - t1) / (float(it.hit) - t1), 0.0, 1.0))   # 游完一圈往圈心收
	var p: Vector2 = _snap(c + Vector2(cos(ang), sin(ang) * SQ) * rr)
	var rise: float = clampf((t - t0) / 0.13, 0.0, 1.0) * (1.0 - clampf((t - float(it.hit) + 0.07) / 0.07, 0.0, 1.0))
	var pal: Array = it.pal
	var px: float = g.PX
	for j in range(1, 10):   # 破浪：身后弧上几段白沫
		var aj: float = ang - 0.12 * float(j)
		var q: Vector2 = c + Vector2(cos(aj), sin(aj) * SQ) * rr
		for s in range(-2, 3):
			if (j + s) % 2 == 0:
				_cell(ci, q + Vector2(0, float(s) * px), Color(WATER, 0.9 - 0.08 * float(j)))
	var tex: Texture2D = _tex(FIN_TEX)
	var flip: bool = sin(ang) > 0.0   # 往右游（上半圈）朝右、下半圈朝左
	if tex != null and rise > 0.0:
		var sz: Vector2 = tex.get_size() * 1.5   # 11-07 用户「不够明显」：放大
		var vis: float = sz.y * rise
		ci.draw_set_transform(p, 0.0, Vector2(-1.0 if flip else 1.0, 1.0))
		ci.draw_texture_rect_region(tex, Rect2(Vector2(-sz.x * 0.5, -vis), Vector2(sz.x, vis)), Rect2(0, 0, sz.x / 1.5, vis / 1.5), Color(lerpf(1.0, pal[4].r * 1.2, 0.35), lerpf(1.0, pal[4].g * 1.2, 0.35), lerpf(1.0, pal[4].b * 1.2, 0.35)))
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	elif rise > 0.0:
		for y in int(40.0 * rise / px):
			for x in range(-(10 - y / 3), 1):
				_cell(ci, p + Vector2(float(x) * px, -float(y) * px), pal[3] if x > -2 else pal[2])
	_glow(p + Vector2(0, -10), pal[5])


## 暗潮（11-07 用户「不要明显的简约几何线条」）：一圈往里涌的浪花团——每团几颗深海蓝水珠 + 一两格白沫，按哈希错开远近和大小，
## 整体从 R0 往里合拢（缓入），不画连续环带；到位后 2 拍溅散
func _draw_tidering(ci, it: Dictionary) -> void:
	var t: float = g.t
	var t0: float = it.t0
	var t1: float = it.t1
	if t < t0 or t > t0 + float(it.life):
		return
	var c: Vector2 = it.c
	var px: float = g.PX
	var k: float = clampf((t - t0) / (t1 - t0), 0.0, 1.0)
	var rr: float = lerpf(float(it.R0), 60.0, k * k)
	var burst: float = clampf((t - t1) / 0.15, 0.0, 1.0)
	var bt: int = int(floor(g.t * 15.0))
	var n: int = 90
	for i in n:
		var h1: float = fposmod(float(i) * 0.618034, 1.0)
		var h2: float = fposmod(float(i) * 0.754877, 1.0)
		var a0: float = TAU * (float(i) + h1 * 0.8) / float(n)
		var r2: float = rr * (0.82 + 0.36 * h2) + burst * 90.0 * h2
		var p: Vector2 = c + Vector2(cos(a0), sin(a0) * SQ) * r2
		var m: int = 4 + int(h1 * 6.0)
		for j in m:
			var hj: float = fposmod(float(i * 7 + j * 3 + bt) * 0.4142, 1.0)
			var q: Vector2 = p + Vector2((hj - 0.5) * 10.0, (fposmod(hj * 7.1, 1.0) - 0.5) * 8.0)
			var col: Color = WATER if j == 0 and (i + bt) % 3 != 0 else (SK[4] if j < 2 else SK[2])
			_cell(ci, q, Color(col, 1.0 - burst))
		if i % 8 == 0:
			_glow(p, SK[5])


## 猎人扑向圈心（11-07 不画直线矛）：各人色的一股粒子流从潮里冲向圈心（2 拍：头部一团亮粒子 + 后面散开的拖尾颗粒），
## 浊心斯卡蒂不冲：圈心一圈往外扩的歌声音符点（断续、按节拍闪）
func _draw_spear(ci, it: Dictionary) -> void:
	var t: float = g.t
	var t0: float = it.t0
	var t1: float = it.t1
	if t < t0 or t > t1 + 0.2:
		return
	var c: Vector2 = it.c
	var pal: Array = it.pal
	var px: float = g.PX
	var f: int = int(floor((t - t0) * 15.0))
	var bt: int = int(floor(g.t * 15.0))
	if bool(it.sing):
		var r: float = [40.0, 80.0, 120.0, 150.0][mini(f, 3)]
		for i in 30:
			var hi: float = fposmod(float(i) * 0.618 + float(bt) * 0.21, 1.0)
			if hi < 0.35:
				continue
			var a0: float = TAU * (float(i) + hi) / 30.0
			_cell(ci, c + Vector2(cos(a0) * r, sin(a0) * r * SQ) * (0.9 + 0.2 * hi), pal[5] if i % 2 else pal[4])
		return
	var dv: Vector2 = Vector2.from_angle(float(it.ang))
	var tail: Vector2 = c + Vector2(dv.x, dv.y * SQ) * 170.0
	var k: float = [0.5, 1.0, 1.0, 1.0][mini(f, 3)]
	var head: Vector2 = tail.lerp(c, k) + Vector2(0, -LIFT * 0.6)
	var dd: Vector2 = (c - tail).normalized()
	var nn: Vector2 = dd.orthogonal()
	for j in 26:
		var hj: float = fposmod(float(j) * 0.618034 + float(bt) * 0.13, 1.0)
		var back: float = pow(hj, 1.6) * 120.0 * k
		var spread: float = (fposmod(float(j) * 0.7548, 1.0) - 0.5) * (6.0 + back * 0.25)
		var q: Vector2 = head - dd * back + nn * spread
		_cell(ci, q, Color(1.3, 1.3, 1.4) if back < 10.0 else (pal[5] if back < 50.0 else pal[3]))
	for d2 in [Vector2.ZERO, Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		_cell(ci, head + d2 * px, Color(1.3, 1.3, 1.4))
	_glow(head, pal[5])


## 提灯（pixgen bd2_lamp，11-07）：从艾丽妮身边 2 拍飞到落点上空 L，悬停时两拍一晃；0.35 秒灯罩打开（灯光星芒 + 发光点），最后 0.3 秒淡出。缺贴图时画像素小灯
const LAMP_TEX := "res://art/fx/fx_bd2_lamp@2x.png"
const BLK := [Color("#07080a"), Color("#101216"), Color("#1a1d23"), Color("#272b33"), Color("#3a3f4a")]


func _draw_lantern(ci, it: Dictionary) -> void:
	var t: float = g.t
	var t0: float = it.t0
	var t1: float = it.t1
	var life: float = it.life
	if t < t0 or t > t0 + life:
		return
	var nb: float = maxf(1.0, floor((t1 - t0) * 15.0))
	var k: float = clampf(floor((t - t0) * 15.0 + 1.0) / nb, 0.0, 1.0)
	var bt: int = int(floor(g.t * 15.0))
	var sway: float = 0.0 if k < 1.0 else [0.0, 2.0, 0.0, -2.0][(bt / 2) % 4]
	var p: Vector2 = _snap(Vector2(it.a).lerp(it.L, k) + Vector2(0, -60.0 * 4.0 * k * (1.0 - k)) + Vector2(sway, 0))
	var al: float = 1.0 - clampf((t - (t0 + life - 0.3)) / 0.3, 0.0, 1.0)
	var tex: Texture2D = _tex(LAMP_TEX)
	if tex != null:
		var sz: Vector2 = tex.get_size() * 1.6   # 11-07 用户「不够明显」：放大
		ci.draw_texture_rect(tex, Rect2(p - sz * 0.5, sz), false, Color(1, 1, 1, al))
	else:
		for y in range(-8, 9):
			for x in range(-5, 6):
				_cell(ci, p + Vector2(x, y) * g.PX, LAMPG[5] if absi(x) < 3 and absi(y) < 5 else BLK[1])
	var age: float = t - t0
	if age >= 0.6 and age < B2.IQ_HIT + 0.1:
		var f: int = int(floor((age - 0.6) * 15.0))
		_star(ci, p, [14, 10, 7][mini(f, 2)] if f < 3 else (6 + bt % 2), [LAMPG[0], LAMPG[1], LAMPG[2], LAMPG[3], LAMPG[4], LAMPG[5], Color.WHITE])
	for i in 3:
		_glow(p + Vector2(float(i - 1) * 6.0, 0), LAMPG[5])


## 光雨：灯罩打开后（0.35 秒起）暖金光点从提灯往下洒、散到落点光圈里（每颗按哈希挑落点、加速往下落，落地变成一格地面闪光，Noita 式）；
## top = true 画空中的光点，false 画地面层的断续描边光圈 + 地面闪光 + 紫印
func _draw_rain(ci, it: Dictionary, top: bool) -> void:
	var age: float = g.t - float(it.t0)
	var hit: float = B2.IQ_HIT
	if age < 0.6 or age > hit + 0.3:
		return
	var px: float = g.PX
	var lp: Vector2 = it.L
	var c: Vector2 = it.c
	var r: float = it.r
	var fa: float = 1.0 - clampf((age - hit) / 0.3, 0.0, 1.0)
	var bt: int = int(floor(g.t * 15.0))
	var span: float = age - 0.6
	var sp: float = hit - 0.6 - 0.3   # 光点出发时刻散布在这段里（最后一颗在光矛前落地）
	if top:
		for i in 180:
			var h1: float = fposmod(float(i) * 0.618034, 1.0)
			var h2: float = fposmod(float(i) * 0.754877, 1.0)
			var h3: float = fposmod(float(i) * 0.414214, 1.0)
			var tt: float = span - h3 * sp
			if tt < 0.0:
				continue
			var u: float = tt / 0.28
			if u >= 1.0:
				continue
			var land: Vector2 = c + Vector2(cos(h1 * TAU), sin(h1 * TAU) * SQ) * sqrt(h2) * r
			var q: Vector2 = lp.lerp(land, u * u)
			var big: bool = i % 6 == 0
			_cell(ci, q, Color(Color.WHITE if big else LAMPG[5], fa))
			_cell(ci, q + Vector2(px, 0), Color(LAMPG[5], fa))
			for tr in range(1, 5):   # 拖尾 4 格
				_cell(ci, q + Vector2(0, -px * float(tr)), Color(LAMPG[4] if tr < 3 else LAMPG[3], fa * (0.85 - 0.18 * float(tr))))
			if big:
				_glow(q, LAMPG[4])
		return
	var rr: float = r * clampf(span / 0.4, 0.0, 1.0)   # 11-07 用户「不要明显的简约几何线条」：光圈不描边，范围只靠落地闪光
	for i in 120:   # 光点落地后的地面闪光（落地后 0.2 秒内）
		var h1: float = fposmod(float(i) * 0.618034, 1.0)
		var h2: float = fposmod(float(i) * 0.754877, 1.0)
		var h3: float = fposmod(float(i) * 0.414214, 1.0)
		var tl: float = span - h3 * sp - 0.28
		if tl < 0.0 or tl > 0.2:
			continue
		var land: Vector2 = c + Vector2(cos(h1 * TAU), sin(h1 * TAU) * SQ) * sqrt(h2) * r
		_cell(ci, land, Color(LAMPG[5], fa * (1.0 - tl / 0.2)))
		_cell(ci, land + Vector2(px, 0), Color(LAMPG[4], fa * 0.6 * (1.0 - tl / 0.2)))
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
