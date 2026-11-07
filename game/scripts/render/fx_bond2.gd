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
const B3 = preload("res://scripts/render/fx_bond3.gd")

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


## 借干员技能帧条（11-07 用户「当作干员的技能来做」）：k = fx_pxplane 的帧条键（带前缀，如 tx_ / lp_ / ex_ / bd_）；
## ly：up 立起层（按 gp.y 排进单位层）/ gd 贴地层 / bk 立起层后半（画在圈心单位后面）；hold > 0 = 循环帧条循环播 hold 秒
func _pxs(k: String, gp: Vector2, t0: float, ly := "up", flip := false, hold := 0.0) -> void:
	var m: Dictionary = _px()._meta(k)
	if m.is_empty():
		return
	_push({"k": "pxs", "s": k, "gp": _snap(gp), "t0": t0, "ly": ly, "flip": flip, "hold": hold, "life": (hold if hold > 0.0 else float(m.n) / 15.0) + 0.07})


## 方向件：键里 %d 换成最近的预生成平面角，另一半水平翻转
func _pxd(fmt: String, gp: Vector2, ang: float, t0: float, ly := "up") -> void:
	var dk: Array = _px().pick_dir(ang)
	_pxs(fmt % int(dk[0]), gp, t0, ly, bool(dk[1]))


## 立起 + 贴地一对（同原点）
func _pair(k: String, gp: Vector2, t0: float, hold := 0.0) -> void:
	_pxs(k + "_up", gp, t0, "up", false, hold)
	_pxs(k + "_gd", gp, t0, "gd", false, hold)


func _draw_pxs(ci, it: Dictionary) -> void:
	var P = _px()
	var fi: int = P.frame_of(float(it.t0))
	P._draw_strip(ci, str(it.s), fi, it.gp, bool(it.flip), float(it.hold) <= 0.0)


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
	if str(a.id) in ["b_rival", "b_lesson", "b_tide", "b_vortex", "b_fins"]:   # 第四轮（docs/314）：画面在 fx_bond3.gd
		B3.cast(self, a)
		return
	if str(a.id) == "b_hunt":
		cast5(a)
		return
	match str(a.id):
		"b_penguin":   # 碾过去：车从画面外横向冲进来、穿过最密处再开出去（车上不画人）；炸弹落地 = pixelfx 爆炸（bd_bomb_v*）；能天使齐射由 shots() 逐发加
			_push({"k": "car", "c": c, "dl": a.dl, "run": float(a.run), "out": float(a.out), "t0": t, "T0": B2.PG_T0, "T1": B2.PG_T1, "life": B2.PG_T1 + 0.3, "tx": a.who.texas})
			_push({"k": "skid", "c": c, "dl": a.dl, "run": float(a.run), "out": float(a.out), "t0": t, "T0": B2.PG_T0, "T1": B2.PG_T1, "life": B2.PG_T1 + 1.6})
			var S: Vector2 = c - Vector2(a.dl) * float(a.run)
			var LL: float = float(a.run) + float(a.out)
			var bi: int = 0
			for bm in a.bombs:   # 炸弹：从车顶抛出、PG_BOMB 秒落到车道两侧 → 炸开
				var tb: float = t + B2.PG_T0 + float(bm[0]) * (B2.PG_T1 - B2.PG_T0)
				var kb: float = float(bm[0])
				var fk: float = kb * kb * 1.6 if kb < 0.25 else 0.1 + (kb - 0.25) * 1.2
				_push({"k": "bomb", "a": S + Vector2(a.dl) * LL * fk + Vector2(0, -90), "b": bm[2], "t0": tb, "dur": B2.PG_BOMB, "life": B2.PG_BOMB + 0.05})
				_pxs("bd_bomb_v%d" % (bi % 3), bm[2], tb + B2.PG_BOMB, "up", bi % 2 == 1)
				due.append([tb + B2.PG_BOMB, "light", {"o": a.who.texas, "p": bm[2], "r": 150.0, "i": 0.8, "c": Color(1.0, 0.6, 0.3), "life": 0.15}])
				bi += 1
		"b_inq":   # 合击：艾丽妮的提灯飞到落点上空 → 灯罩打开 = 流明灯火星芒 + 一道道水光柱落进光圈 → 艾丽妮 S3 审判（光矛劈下 + 一圈光柱）+ 星爆
			var ir = a.who.irene
			var from: Vector2 = (ir.pos if ir != null else c) + Vector2(0, -40)
			_push({"k": "lantern", "a": from, "L": a.O, "c": c, "t0": t, "t1": t + 0.5, "life": B2.IQ_HIT + 0.55})
			_pxs("lm_burst_up", Vector2(a.O) + Vector2(0, 80), t + 0.6)
			var r: float = float(a.r)
			for j in 8:   # 流明骤雨：灯下一道道水光柱砸进光圈
				var hj: float = fposmod(sin(float(j) * 7.233 + t) * 43758.5453, 1.0)
				var aj: float = TAU * float(j) / 8.0 + hj * 0.7
				var pj: Vector2 = c + Vector2(cos(aj), sin(aj) * SQ) * r * (0.3 + 0.55 * hj)
				_pxs("lm_downpour_e2_up", pj, t + 0.65 + 0.08 * float(j))
			_pxs("lm_burst_gd", c, t + 0.7, "gd")
			_pair("ir_s3_r106", c, t + B2.IQ_HIT - 3.0 / 15.0)   # 前三帧是劈下来的光矛，第 4 帧（= IQ_HIT）一圈光柱
			_pxs("ir_nova_up", c, t + B2.IQ_HIT)
			due.append([t + 0.6, "light", {"o": ir, "p": a.O, "r": 160.0, "i": 0.7, "c": LAMPG[4], "life": 0.15}])
			due.append([t + B2.IQ_HIT, "grains", {"o": ir, "p": c + Vector2(0, LIFT * 0.5), "n": 16, "c0": IR[5], "c1": IR[3], "mat": "streak"}])


## 能天使原地齐射（bond2._penguin 每 0.09 秒调一次）：从她枪口到每个目标一道曳光
func shots(a: Dictionary, from: Vector2, targets: Array) -> void:
	var mz: Vector2 = from + Vector2(0, -30)
	for p in targets:
		_push({"k": "tracer", "a": mz, "b": p, "t0": g.t, "life": 0.3})
		_pxd("ex_hit_s3_e2_d%d", p, (p - from).angle(), g.t + 0.05)
	if not targets.is_empty():
		_pxd("ex_mz_s3_e2_v%d" % (int(g.t * 15.0) % 2) + "_d%d", from, (Vector2(targets[0]) - from).angle(), g.t)
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
			"pxs":
				var ly: String = str(it.ly)
				sk = GROUND_KEY if ly == "gd" else float((it.gp as Vector2).y) + (-60.0 if ly == "bk" else 1.0)
			"b3":
				sk = B3.sort_key(it)
			"skid":
				sk = GROUND_KEY
			"car":
				sk = r._car_pos(it).y + 1.0
			"lantern":
				sk = 1.0e9 - 1.0
			"tracer", "bomb":
				sk = maxf((it.a as Vector2).y, (it.b as Vector2).y) + 2.0
			_:
				sk = float((it.p as Vector2).y) + 2.0
		out.append({"bd2": it, "skey": sk})
	return out


static func draw_sorted(game, ci, item: Dictionary) -> void:
	var r = game.get_meta("fx_bond2")
	var it: Dictionary = item.bd2
	match str(it.k):
		"pxs":
			r._draw_pxs(ci, it)
		"b3":
			B3.draw(r, ci, it)
		"car":
			r._draw_car(ci, it)
		"skid":
			r._draw_skid(ci, it)
		"tracer":
			r._draw_tracer(ci, it)
		"bomb":
			r._draw_bomb(ci, it)
		"lantern":
			r._draw_lantern(ci, it)


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
		"b_hunt":   # 群猎：在场猎人按序各放自己的大招形体，在 HT_HIT 一齐落到圈心（斯卡蒂怒涛 / 歌蕾蒂娅收潮 / 幽灵鲨锯潮 / 乌尔比安浪冠 + 锚震 / 斯卡蒂（浊心）回潮）
			var ids: Array = a.ps.map(func(p): return str(p.id))
			for i in ids.size():
				var ti: float = t + B2.HT_T1 - 0.45 + 0.15 * float(i)
				match ids[i]:
					"skadi":
						_pair("nutao", c, ti)
					"gladiia":
						_pxs("gl_s3close_bk", c, ti, "bk")
						_pair("gl_s3close", c, ti)
					"specter_unchained":
						_pxs("su_saw_h_r100_bk_up", c, ti, "bk")
						_pxs("su_saw_h_r100_fr_up", c, ti)
						_pxs("su_saw_h_r100_gd", c, ti, "gd")
					"ulpianus":
						_pair("ul_s3_r85", c, ti)
						_pxs("ul_quake_r125_gd", c, ti + 0.1, "gd")
					_:
						_pair("backwash", c, ti)
			due.append([t + B2.HT_HIT, "grains", {"o": a.ps[0], "p": c + Vector2(0, LIFT * 0.5), "n": 18, "c0": WATER, "c1": SK[4], "mat": "drop"}])


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


