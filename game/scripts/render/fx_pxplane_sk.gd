## 浊心斯卡蒂（docs/260，照 docs/246 斯卡蒂的做法）
## 她是召唤 + 控场的歌手，特效全是「圈」：判定半径随技能 / 精英化 / 成长连续变化，烤成帧条只能按整数倍放大对不上半径，
## 所以主形全部运行时画：笔触弧 = 三角形带（顶点对齐 2 世界像素格，进低分辨率层后正好 1 美术像素一格，硬边、无抗锯齿），
## 形状按 15 fps 全局节拍换（旋转角、扩散半径都按拍取值）。贴地件按 combat.GROUND_Y（0.72）压扁；音符、气泡、红光柱、小鱼是立起件，按脚底 y 和单位一起排序。
## 色层吃场景光（画在世界层），白热 / 红光柱芯出 emit 点进发光层，爆发与命中挂照地点光（fx_recipe 灯光预算）；颗粒只用 twinkle / drop 少量。
## 招式：普攻声浪 = 一圈断口笔触浪从 0.6 扩到判定边 + 命中处音符（E1 加厚 + 第二道浪 + 余音外环；E2 浪里夹一道酒红暗流 + 双音符）；
## 歌域（常驻地面区域）= 边上 3–5 段粗笔触 + 贴边淡渐变 + 内侧 2–4 道反向细笔触线；S1 = 身周气泡（E1 双层膜、E2 三团）+ 脚下酒红细环；
## S2 = 起手脚下旋涡 + 酒红小鱼（之后小鱼常驻绕歌域游，E1 3 条 / E2 5 条；E2 涡眼冲起一道水柱）；
## S3 = 起手与之后每 3 秒一次「潮涌」：粗笔触亮蓝环（深蓝内影）扩到歌域边 + 内部实心渐变（不透明度 0.5 → 0.35）+ 8 道旋转笔触线 + 5 根粗亮红竖光柱；持续期间歌域加粗加快。
## 伊莎玛拉（精二海嗣）的小歌域 = 酒红细笔触；连携 v2「歌声」= 区域笔触圈 + 酒红内圈 3 秒 + 音符；旧连携声浪 = 大一号声浪。
## 成长 / 后期：共鸣小声浪、潮汐和声回声（酒红细浪）、深海的回响爆点、late_shape「扩散」溅射环（同屏每拍至多 3 个）。
## docs/286 §4 第三批从 render/fx_pxplane.gd 原样拆出，行为不变：全部 static func，第一个参数 pv = fx_pxplane 实例（成员经 pv.、常量经 P.）；本节状态变量仍在 fx_pxplane 上。
extends RefCounted

const P = preload("res://scripts/render/fx_pxplane.gd")
const Bal = preload("res://scripts/core/balance.gd")
const SK_SY := 0.72
const SK_B := [Color("#070d22"), Color("#0e1d4a"), Color("#183486"), Color("#2752c4"), Color("#4f80ec"), Color("#9dbcff"), Color("#ffffff")]   # 深海蓝 7 阶（原作歌域蓝，避开敌弹青 #33ceff）
const SK_R := [Color("#3a0d1b"), Color("#5e1424"), Color("#86202d"), Color("#a8323c"), Color("#dc4048"), Color("#ffb4bc"), Color("#ffffff")]   # 酒红（house.js OP.skalter，亮段色相 357°，避开危险红 331–353°）
const SK_T := [Color("#06141c"), Color("#0b2a35"), Color("#124552"), Color("#1b6466"), Color("#3b8e89"), Color("#86c6bd"), Color("#e8f5f0")]   # 海嗣青（house.js OP.skalter_sea，原作海嗣色，偏灰、避开敌弹青）：伊莎玛拉小歌域与同步声浪
const SK_V := [Color("#24163f"), Color("#4a2f7a"), Color("#7a5ab8"), Color("#b49cf0"), Color("#ece4ff")]   # 余音专属淡紫（docs/310 §4.2）
const SK_NOTE := ["....####", "....#..#", "....#..#", "....#...", "....#...", "....#...", ".####...", "#####...", "#####...", ".###...."]
const SK_NOTE2 := ["...########", "...#......#", "...#......#", "...#......#", "...#......#", ".###....###", "####...####", "####...####", ".##.....##."]
const SK_UP := ["..#..", ".###.", "#.#.#", "..#..", ".###.", "#.#.#"]   # 增益双箭头（往上）
const SK_FISH := ["#...####..", "##.######.", ".#########", "##.######.", "#...####.."]
## 画面半径：判定半径一变（S1 开 / 关、S3、灯火档位……），画面在 SK_RT（0.3）秒里平滑过渡到新半径（smoothstep），
## 不一跳一跳（11-05 用户）；按美术像素取整；判定半径立即生效
const SK_RT := 0.3


static func _sk_beat(pv: P) -> int:
	var g = pv.g
	return int(floor(g.t * 15.0))


static func _sk_h(pv: P, i: int, s: float) -> float:
	return fposmod(sin(float(i) * 12.9898 + s * 78.233) * 43758.5453, 1.0)


static func _sk_state(pv: P, o) -> Dictionary:
	var id: String = str(o.id)
	if not pv._sk_st.has(id):
		pv._sk_st[id] = {"r": {}, "s3_next": -1.0, "s3_on": false, "dd": {}}
	return pv._sk_st[id]


static func _sk_r(pv: P, o, key: String, zr: float) -> float:
	var g = pv.g
	var st: Dictionary = _sk_state(pv, o)
	var e: Array = st.r.get(key, [zr, zr, zr, -99.0])   # [当前画面半径, 目标, 起点, 起变时刻]
	if absf(zr - float(e[1])) > 0.5:
		e = [float(e[0]), zr, float(e[0]), g.t]
	var u: float = clampf((g.t - float(e[3])) / SK_RT, 0.0, 1.0)
	e[0] = lerpf(float(e[2]), float(e[1]), u * u * (3.0 - 2.0 * u))
	st.r[key] = e
	return round(float(e[0]) / g.PX) * g.PX


## 跟歌域走的件（fz）的半径按画面半径同比缩放，和歌域边对齐
static func _sk_rk(pv: P, it: Dictionary) -> float:
	var o = it.get("o", null)
	if o == null or not it.get("fz", false) or not is_instance_valid(o):
		return 1.0
	var e: Array = _sk_state(pv, o).r.get("self", [])
	if e.is_empty() or float(o.zr) <= 1.0:
		return 1.0
	return clampf(float(e[0]) / float(o.zr), 0.3, 3.0)


## 椭圆上一点（贴地：纵向 × GROUND_Y）
static func _sk_ep(pv: P, c: Vector2, rr: float, a: float) -> Vector2:
	return c + Vector2(cos(a) * rr, sin(a) * rr * SK_SY)


## 一笔贴地笔触弧：c 圆心（世界）、R 半径（世界）、a0 → a1 弧度、w 宽（美术像素）、taper 两头收尖、seed 粗细起伏；
## 主色一条带 + 外缘 1 美术像素迎光边（中段）+ 内缘 1 美术像素暗边；顶点对齐 2 世界像素格
static func _sk_arc(pv: P, cv, c: Vector2, R: float, a0: float, a1: float, w: float, col: Color, hi: Color, lo: Color, seed: float, taper := true) -> void:
	var g = pv.g
	if g.opt_old & g.OPT_SKDOM:
		_sk_arc_old(pv, cv, c, R, a0, a1, w, col, hi, lo, seed, taper)
		return
	if pv._sk_test:   # --skdomtest：新旧两种写法各算一遍、逐位比顶点 / 颜色 / 下标，不一致计数（PF SKDOM 打印），画的是旧写法
		var ra := P._SkRec.new()
		var rb := P._SkRec.new()
		_sk_arc_old(pv, ra, c, R, a0, a1, w, col, hi, lo, seed, taper)
		_sk_arc_new(pv, rb, c, R, a0, a1, w, col, hi, lo, seed, taper)
		pv._sk_test_n += 1
		if not ra.same(rb):
			pv._sk_test_bad += 1
		if pv._sk_test_n % 2000 == 0:
			print("PF SKDOM n=%d bad=%d" % [pv._sk_test_n, pv._sk_test_bad])
		_sk_arc_old(pv, cv, c, R, a0, a1, w, col, hi, lo, seed, taper)
		return
	_sk_arc_new(pv, cv, c, R, a0, a1, w, col, hi, lo, seed, taper)


static func _sk_arc_geo(pv: P, a0: float, a1: float, n: int, w: float, px: float, seed: float, taper: bool) -> Array:
	var bt: int = _sk_beat(pv)
	if bt != pv._sk_ac_beat:
		pv._sk_ac_beat = bt
		pv._sk_ac.clear()
	var key := [a0, a1, n, w, px, seed, taper]
	var e = pv._sk_ac.get(key)
	if e != null:
		return e
	var span: float = a1 - a0
	var ca := PackedFloat64Array()
	var sa := PackedFloat64Array()
	var ths := PackedFloat64Array()
	var cb := PackedFloat64Array()
	var sb := PackedFloat64Array()
	ca.resize(n + 1)
	sa.resize(n + 1)
	ths.resize(n + 1)
	cb.resize(n + 1)
	sb.resize(n + 1)
	for i in n + 1:
		var u: float = float(i) / float(n)
		var a: float = a0 + span * u
		var th: float = w * px * (pow(maxf(0.0, sin(PI * u)), 0.55) if taper else 1.0) * (0.82 + 0.36 * _sk_h(pv, i / 3, seed))
		th = maxf(th, px * 0.5) if taper else th
		ths[i] = th
		ca[i] = cos(a)
		sa[i] = sin(a)
		var a2: float = a0 + span * float(i) / float(n)
		cb[i] = cos(a2)
		sb[i] = sin(a2)
	e = [ca, sa, ths, cb, sb]
	pv._sk_ac[key] = e
	return e


static func _sk_arc_new(pv: P, cv, c: Vector2, R: float, a0: float, a1: float, w: float, col: Color, hi: Color, lo: Color, seed: float, taper := true) -> void:
	var g = pv.g
	if R <= 2.0 or w <= 0.0 or col.a <= 0.003:
		return
	var px: float = g.PX
	var span: float = a1 - a0
	var n: int = clampi(int(absf(span) * R / (px * 3.0)), 3, 72)
	var geo: Array = _sk_arc_geo(pv, a0, a1, n, w, px, seed, taper)
	var ca: PackedFloat64Array = geo[0]
	var sa: PackedFloat64Array = geo[1]
	var ths: PackedFloat64Array = geo[2]
	var cb: PackedFloat64Array = geo[3]
	var sb: PackedFloat64Array = geo[4]
	var pts := PackedVector2Array()
	pts.resize((n + 1) * 2)
	for i in n + 1:
		var th: float = ths[i]
		var r1: float = R + th * 0.5
		var r2: float = R - th * 0.5
		pts[i * 2] = ((c + Vector2(ca[i] * r1, sa[i] * r1 * SK_SY)) / 2.0).round() * 2.0
		pts[i * 2 + 1] = ((c + Vector2(ca[i] * r2, sa[i] * r2 * SK_SY)) / 2.0).round() * 2.0
	_sk_band_pts(pv, cv, pts, n + 1, col)
	if w >= 2.0 and hi.a > 0.003:   # 迎光边：外缘中段 1 美术像素
		var lo_i: int = n / 5
		var hi_i: int = n - n / 5
		var m2: int = hi_i - lo_i + 1
		var p2 := PackedVector2Array()
		p2.resize(m2 * 2)
		for i in range(lo_i, hi_i + 1):
			var th: float = ths[i]
			var r1: float = R + th * 0.5
			var r2: float = R + th * 0.5 - px
			var k: int = (i - lo_i) * 2
			p2[k] = ((c + Vector2(cb[i] * r1, sb[i] * r1 * SK_SY)) / 2.0).round() * 2.0
			p2[k + 1] = ((c + Vector2(cb[i] * r2, sb[i] * r2 * SK_SY)) / 2.0).round() * 2.0
		_sk_band_pts(pv, cv, p2, m2, hi)
	if w >= 3.0 and lo.a > 0.003:   # 内缘暗边
		var p3 := PackedVector2Array()
		p3.resize((n + 1) * 2)
		for i in n + 1:
			var th: float = ths[i]
			var r1: float = R - th * 0.5 + px
			var r2: float = R - th * 0.5
			p3[i * 2] = ((c + Vector2(cb[i] * r1, sb[i] * r1 * SK_SY)) / 2.0).round() * 2.0
			p3[i * 2 + 1] = ((c + Vector2(cb[i] * r2, sb[i] * r2 * SK_SY)) / 2.0).round() * 2.0
		_sk_band_pts(pv, cv, p3, n + 1, lo)


## _sk_band 的已交错版本：pts 已是 外0, 内0, 外1, 内1 …（m 对）；下标表按 m 缓存（与 _sk_band 生成的相同）
static func _sk_band_pts(pv: P, cv, pts: PackedVector2Array, m: int, col: Color) -> void:
	if m < 2:
		return
	var idx = pv._sk_idx.get(m)
	if idx == null:
		idx = PackedInt32Array()
		for i in m - 1:
			var k: int = i * 2
			idx.append_array([k, k + 1, k + 2, k + 1, k + 3, k + 2])
		pv._sk_idx[m] = idx
	var cols := PackedColorArray([col])
	cv.add_tris(pts, cols, idx)


static func _sk_arc_old(pv: P, cv, c: Vector2, R: float, a0: float, a1: float, w: float, col: Color, hi: Color, lo: Color, seed: float, taper := true) -> void:
	var g = pv.g
	if R <= 2.0 or w <= 0.0 or col.a <= 0.003:
		return
	var px: float = g.PX
	var span: float = a1 - a0
	var n: int = clampi(int(absf(span) * R / (px * 3.0)), 3, 72)
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var ths: Array = []
	for i in n + 1:
		var u: float = float(i) / float(n)
		var a: float = a0 + span * u
		var th: float = w * px * (pow(maxf(0.0, sin(PI * u)), 0.55) if taper else 1.0) * (0.82 + 0.36 * _sk_h(pv, i / 3, seed))
		th = maxf(th, px * 0.5) if taper else th
		ths.append(th)
		outer.append(pv._snap(_sk_ep(pv, c, R + th * 0.5, a)))
		inner.append(pv._snap(_sk_ep(pv, c, R - th * 0.5, a)))
	_sk_band(pv, cv, outer, inner, col)
	if w >= 2.0 and hi.a > 0.003:   # 迎光边：外缘中段 1 美术像素
		var o2 := PackedVector2Array()
		var i2 := PackedVector2Array()
		var lo_i: int = n / 5
		var hi_i: int = n - n / 5
		for i in range(lo_i, hi_i + 1):
			var a: float = a0 + span * float(i) / float(n)
			var th: float = float(ths[i])
			o2.append(pv._snap(_sk_ep(pv, c, R + th * 0.5, a)))
			i2.append(pv._snap(_sk_ep(pv, c, R + th * 0.5 - px, a)))
		_sk_band(pv, cv, o2, i2, hi)
	if w >= 3.0 and lo.a > 0.003:   # 内缘暗边
		var o3 := PackedVector2Array()
		var i3 := PackedVector2Array()
		for i in n + 1:
			var a: float = a0 + span * float(i) / float(n)
			var th: float = float(ths[i])
			o3.append(pv._snap(_sk_ep(pv, c, R - th * 0.5 + px, a)))
			i3.append(pv._snap(_sk_ep(pv, c, R - th * 0.5, a)))
		_sk_band(pv, cv, o3, i3, lo)


static func _sk_band(pv: P, cv, outer: PackedVector2Array, inner: PackedVector2Array, col: Color) -> void:
	var m: int = mini(outer.size(), inner.size())
	if m < 2:
		return
	var pts := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in m:
		pts.append(outer[i])
		pts.append(inner[i])
	for i in m - 1:
		var k: int = i * 2
		idx.append_array([k, k + 1, k + 2, k + 1, k + 3, k + 2])
	var cols := PackedColorArray()
	cols.resize(pts.size())
	cols.fill(col)
	cv.add_tris(pts, cols, idx)


## 贴边淡渐变 / 实心渐变：r0 → r1 两圈之间，透明度 a0（内）→ a1（外）
static func _sk_grad(pv: P, cv, c: Vector2, r0: float, r1: float, col: Color, a0: float, a1: float) -> void:
	var g = pv.g
	if r1 <= 2.0 or (a0 <= 0.003 and a1 <= 0.003):
		return
	var n: int = clampi(int(r1 / 6.0), 20, 64)
	var ci := Color(col.r, col.g, col.b, a0)
	var co := Color(col.r, col.g, col.b, a1)
	if not (g.opt_old & g.OPT_SKDOM) and not pv._sk_test:   # 缓存写法（docs/287 §3 ②）：方向表与下标表只跟点数有关；算式同下
		var gt = pv._sk_gc.get(n)
		if gt == null:
			var gc := PackedFloat64Array()
			var gs := PackedFloat64Array()
			var gi := PackedInt32Array()
			for i in n:
				var a: float = TAU * float(i) / float(n)
				gc.append(cos(a))
				gs.append(sin(a))
			for i in n:
				var k: int = i * 2
				var k2: int = ((i + 1) % n) * 2
				gi.append_array([k, k + 1, k2, k + 1, k2 + 1, k2])
			gt = [gc, gs, gi]
			pv._sk_gc[n] = gt
		var gc2: PackedFloat64Array = gt[0]
		var gs2: PackedFloat64Array = gt[1]
		var rr0: float = maxf(0.0, r0)
		var pts2 := PackedVector2Array()
		pts2.resize(n * 2)
		var cols2 := PackedColorArray()
		cols2.resize(n * 2)
		for i in n:
			pts2[i * 2] = ((c + Vector2(gc2[i] * r1, gs2[i] * r1 * SK_SY)) / 2.0).round() * 2.0
			pts2[i * 2 + 1] = ((c + Vector2(gc2[i] * rr0, gs2[i] * rr0 * SK_SY)) / 2.0).round() * 2.0
			cols2[i * 2] = co
			cols2[i * 2 + 1] = ci
		cv.add_tris(pts2, cols2, gt[2])
		return
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for i in n:
		var a: float = TAU * float(i) / float(n)
		pts.append(pv._snap(_sk_ep(pv, c, r1, a)))
		cols.append(co)
		pts.append(pv._snap(_sk_ep(pv, c, maxf(0.0, r0), a)))
		cols.append(ci)
	for i in n:
		var k: int = i * 2
		var k2: int = ((i + 1) % n) * 2
		idx.append_array([k, k + 1, k2, k + 1, k2 + 1, k2])
	cv.add_tris(pts, cols, idx)


## 逐美术像素的小图案（立起件：音符、小鱼）；左上角 tl（世界），fl 水平翻转
static func _sk_pat(pv: P, ci, pat: Array, tl: Vector2, col: Color, head: Color, fl := false, sh := Color(0, 0, 0, 0)) -> void:
	var g = pv.g
	if ci is CanvasItem and not (g.opt_old & g.OPT_SKPAT):
		if pv._skp_test:   # --skpattest：旧写法交出的矩形（记录器）与新写法的三角形逐个比（顶点 / 颜色 / 次序），PF SKPAT 打印
			var rec := P._SkRectRec.new()
			_sk_pat(pv, rec, pat, tl, col, head, fl, sh)
			var e2: Array = _sk_pat_geo(pv, pat, fl, col, head, sh)
			var pts: PackedVector2Array = Transform2D(0.0, pv._snap(tl)) * (e2[0] as PackedVector2Array)
			var ok: bool = pts.size() == rec.rects.size() * 4
			for i in rec.rects.size():
				if not ok:
					break
				var r2: Rect2 = rec.rects[i][0]
				ok = pts[i * 4] == r2.position and pts[i * 4 + 1] == r2.position + Vector2(r2.size.x, 0.0) and pts[i * 4 + 2] == r2.end and pts[i * 4 + 3] == r2.position + Vector2(0.0, r2.size.y) and (e2[1] as PackedColorArray)[i * 4] == rec.rects[i][1]
			pv._skp_test_n += 1
			if not ok:
				pv._skp_test_bad += 1
			if pv._skp_test_n % 500 == 0:
				print("PF SKPAT n=%d bad=%d" % [pv._skp_test_n, pv._skp_test_bad])
		_sk_pat_tris(pv, ci, pat, tl, col, head, fl, sh)
		return
	var px: float = g.PX
	var p0: Vector2 = pv._snap(tl)
	var hh: int = pat.size()
	if sh.a > 0.0:   # 1 美术像素暗描边（右下投影）：压在白色敌人 / 伤害数字上也读得出
		for y in hh:
			var row0: String = pat[y]
			var w0: int = row0.length()
			for x in w0:
				if row0[x] == "#":
					var x0: int = (w0 - 1 - x) if fl else x
					ci.draw_rect(Rect2(p0 + Vector2(x0 + 1, y + 1) * px, Vector2(px, px)), sh)
	for y in hh:
		var row: String = pat[y]
		var ww: int = row.length()
		for x in ww:
			if row[x] != "#":
				continue
			var xx: int = (ww - 1 - x) if fl else x
			ci.draw_rect(Rect2(p0 + Vector2(xx, y) * px, Vector2(px, px)), head if y >= hh - 2 else col)


static func _sk_pat_tris(pv: P, ci: CanvasItem, pat: Array, tl: Vector2, col: Color, head: Color, fl: bool, sh: Color) -> void:
	var e: Array = _sk_pat_geo(pv, pat, fl, col, head, sh)
	if (e[0] as PackedVector2Array).is_empty():
		return
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), e[2], Transform2D(0.0, pv._snap(tl)) * (e[0] as PackedVector2Array), e[1])


static func _sk_pat_geo(pv: P, pat: Array, fl: bool, col: Color, head: Color, sh: Color) -> Array:
	var g = pv.g
	var key := [pat, fl, col, head, sh]
	var e = pv._skp_cache.get(key)
	if e == null:
		var px: float = g.PX
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		var hh: int = pat.size()
		var rects: Array = []
		if sh.a > 0.0:
			for y in hh:
				var row0: String = pat[y]
				var w0: int = row0.length()
				for x in w0:
					if row0[x] == "#":
						var x0: int = (w0 - 1 - x) if fl else x
						rects.append([Vector2(x0 + 1, y + 1) * px, sh])
		for y in hh:
			var row: String = pat[y]
			var ww: int = row.length()
			for x in ww:
				if row[x] != "#":
					continue
				var xx: int = (ww - 1 - x) if fl else x
				rects.append([Vector2(xx, y) * px, head if y >= hh - 2 else col])
		for rc in rects:
			var q0: Vector2 = rc[0]
			pts.append_array([q0, q0 + Vector2(px, 0.0), q0 + Vector2(px, px), q0 + Vector2(0.0, px)])
			for j in 4:
				cols.append(rc[1])
		var n: int = rects.size()
		var idx = pv._skp_idx.get(n)
		if idx == null:
			idx = PackedInt32Array()
			for i in n:
				var k: int = i * 4
				idx.append_array([k, k + 1, k + 2, k, k + 2, k + 3])
			pv._skp_idx[n] = idx
		e = [pts, cols, idx]
		if pv._skp_cache.size() > 256:
			pv._skp_cache.clear()
		pv._skp_cache[key] = e
	return e


## 一圈断口笔触浪（普攻声浪 / 回声 / 海嗣同步 / 小声浪）：k 断成几段，w 宽，rot 起始角
static func _sk_ring(pv: P, cv, c: Vector2, R: float, k: int, w: float, col: Color, hi: Color, lo: Color, seed: float, rot: float, fill := 0.82) -> void:
	for j in k:
		var a0: float = rot + TAU * (float(j) + 0.06 * _sk_h(pv, j, seed)) / float(k)
		var a1: float = a0 + TAU / float(k) * (fill - 0.12 * _sk_h(pv, j + 7, seed))
		_sk_arc(pv, cv, c, R * (0.98 + 0.04 * _sk_h(pv, j + 13, seed)), a0, a1, w * (0.8 + 0.4 * _sk_h(pv, j + 3, seed)), col, hi, lo, seed + float(j))


static func _sk_push(pv: P, o, it: Dictionary) -> void:
	var g = pv.g
	it["oid"] = str(o.id)
	it["k"] = ""
	if not it.has("t0"):
		it["t0"] = g.t
	pv._push(it)


## 同屏件数（同一名干员、同一类）
static func _sk_count(pv: P, o, kind: String) -> int:
	var n := 0
	var id: String = str(o.id)
	for it in pv.items:
		if str(it.get("skr", "")) == kind and str(it.oid) == id:
			n += 1
	return n


static func _ev_skalter(pv: P, o, kind: String, d: Dictionary, raw: bool, t: int, R, p: Dictionary) -> void:
	var g = pv.g
	var px: float = g.PX
	var st: Dictionary = _sk_state(pv, o)
	if Bal.v("fx/recipe_log", 0.0) > 0.0:
		print("PXPLOG sk %s %s %.3f" % [kind, str(d.get("src", d.get("i", ""))), g.t])
	match kind:
		"shape":
			if not d.get("circle", false):
				return
			var src: String = str(d.get("src", ""))
			var c: Vector2 = d.get("c", o.pos)
			var r: float = float(d.get("r", 190.0))
			var es: Array = d.get("es", [])
			var key: String = "%s|%d|%d" % [src, int(c.x), int(c.y)]
			if st.dd.get(key, -1.0) == g.t:
				return   # 她当队长时「领唱」与普攻同一帧同一圈：只画一次
			st.dd[key] = g.t
			if raw:
				var rk: String = "sk_raw_wave_e%d" % t
				if src == "共鸣" or src == "深海的回响":
					rk = "sk_raw_wave_e0"
				pv._push({"k": rk, "t0": g.t, "gp": c, "ly": "raw", "rot": 0.0, "sc": px * (r * 0.5) / 95.0, "oid": str(o.id)})
				return
			match src:
				"声浪":
					if pv.mode() == 1 and (o.skill_active_left(0) > 0.0 or o.skill_active_left(2) > 0.0) and _sk_count(pv, o, "buff") < 6:
						for q in g.squad.ops:   # 增益挂在吃到增益的人身上：歌域里的每名干员头顶一枚往上飘的双箭头（攻速 / 攻击提升），每圈声浪一次
							if q.pos != Vector2.INF and o.in_zone(q.pos):
								_sk_push(pv, o, {"skr": "buff", "c": q.pos, "tgt": q, "s3": o.skill_active_left(2) > 0.0, "ly": "up", "gy": q.pos.y + 2.0, "life": 8.0 / 15.0})
					_sk_push(pv, o, {"skr": "wave", "c": c, "r": r, "tier": t, "ly": "gd", "life": 6.0 / 15.0, "o": o, "fz": true})
					_sk_notes(pv, o, es, t, R, p)
					var lp: Vector2 = c + Vector2(0, -6)
					for e0 in es:
						if e0 is Dictionary and not e0.get("dead", false):
							lp = e0.pos + Vector2(0, -float(e0.r) * 0.5)
							break
					var n2 := 0
					for e2 in es:   # 第二只命中的再挂一盏小的（每次 ≤ 2 盏）
						if e2 is Dictionary and not e2.get("dead", false):
							n2 += 1
							if n2 == 2:
								R._light(o, e2.pos + Vector2(0, -float(e2.r) * 0.5), 80.0, 0.38, 0.12, p.light)
								break
					R._light(o, lp, 100.0, 0.5, 0.12, p.light)   # docs/270：每次命中一盏、半径 100、强度 0.5（原来半径 = 0.7 歌域，摊满半屏照不出命中点）
				"余音":   # 精一：外圈回声
					_sk_push(pv, o, {"skr": "echo_ring", "c": c, "r": r, "tier": t, "ly": "gd", "life": 6.0 / 15.0, "o": o, "fz": true})
				"潮汐和声":
					_sk_push(pv, o, {"skr": "wave", "c": c, "r": r, "tier": t, "rose": true, "thin": true, "ly": "gd", "life": 6.0 / 15.0, "o": o, "fz": true})
				"海嗣":   # 精二伊莎玛拉同步声浪（酒红）
					_sk_push(pv, o, {"skr": "wave", "c": c, "r": r, "tier": t, "sea": true, "ly": "gd", "life": 6.0 / 15.0})
					_sk_notes(pv, o, es.slice(0, 2), t, R, p, true)
				"共鸣":   # 歌域内击杀处的小声浪
					if _sk_count(pv, o, "mini") < 6:
						_sk_push(pv, o, {"skr": "mini", "c": c, "r": r, "ly": "gd", "life": 4.0 / 15.0})
				_:
					if _sk_count(pv, o, "mini") < 6:
						_sk_push(pv, o, {"skr": "mini", "c": c, "r": r, "ly": "gd", "life": 4.0 / 15.0})
			if src != "声浪" and pv.mode() == 1:   # docs/270：每一圈（海嗣 / 余音 / 回声 / 小声浪）也各挂一盏灯 + 2 颗水滴，落在第一只命中的敌人身上
				var hp2: Vector2 = c + Vector2(0, -8)
				var gy2: float = c.y + 2.0
				for e1 in es:
					if e1 is Dictionary and not e1.get("dead", false):
						hp2 = e1.pos + Vector2(0, -float(e1.r) * 0.5)
						gy2 = float(e1.pos.y) + 2.0
						break
				R._light(o, hp2, 90.0, 0.42, 0.12, SK_T[5] if src == "海嗣" else p.light)
				R._grains(o, hp2, gy2, "ink", 2, {"tier": t})
				if not es.is_empty() and _sk_count(pv, o, "pop") < 8:   # 命中点白芯（同音符的起音），头两拍进发光层
					_sk_push(pv, o, {"skr": "pop", "c": hp2, "sea": src == "海嗣", "ly": "up", "gy": gy2, "life": 2.0 / 15.0})
		"sk_burst":   # 深海的回响：满层爆开（酒红小爆环 + 几颗碎光）
			var at: Vector2 = d.at
			if raw:
				pv._push({"k": "sk_raw_wave_e0", "t0": g.t, "gp": at, "ly": "raw", "rot": 0.0, "sc": px * (float(d.r) * 0.5) / 95.0, "oid": str(o.id)})
				return
			if _sk_count(pv, o, "burst") < 4:
				_sk_push(pv, o, {"skr": "burst", "c": at, "r": float(d.r), "ly": "gd", "life": 5.0 / 15.0})
				if pv.mode() == 1:
					R._grains(o, at + Vector2(0, -10), at.y + 2.0, "shard", 6, {"tier": t})
					R._light(o, at + Vector2(0, -8), 60.0, 0.35, 0.1, SK_R[4])
		"splash":   # late_shape「扩散」：命中溅射（同一拍至多 3 个）
			var at2: Vector2 = d.at
			if raw:
				pv._push({"k": "sk_raw_wave_e0", "t0": g.t, "gp": at2, "ly": "raw", "rot": 0.0, "sc": px * (float(d.r) * 0.5) / 95.0, "oid": str(o.id)})
				return
			if pv._lm_beat_n(o, "sk_splash") < 3:
				_sk_push(pv, o, {"skr": "splash", "c": at2, "r": float(d.r), "ly": "gd", "life": 3.0 / 15.0})
		"skill":
			var i: int = int(d.get("i", -1))
			var zc: Vector2 = o.zone_c()
			var zr: float = float(o.zr)
			if raw:
				var rk2: String = ["sk_raw_s1_e%d" % t, "sk_raw_s2_e%d" % maxi(t, 1), "sk_raw_s3_e2"][clampi(i, 0, 2)]
				pv._push({"k": rk2, "t0": g.t, "gp": zc, "ly": "raw", "rot": 0.0, "sc": px * (zr * 0.5) / 95.0, "oid": str(o.id)})
				return
			match i:
				0:   # S1 同归殊途之吟：身周气泡（循环到技能结束，读 skill_active_left）+ 脚下酒红细环；歌域扩张一道浪
					_sk_push(pv, o, {"skr": "wave", "c": zc, "r": zr, "tier": t, "ly": "gd", "life": 6.0 / 15.0, "o": o, "fz": true})
					R._light(o, zc + Vector2(0, -24), 90.0, 0.5, 0.15, SK_B[5])   # 歌域圆心 = 队长（她当队友时不在她脚下）
					if pv.mode() == 1:
						R._grains(o, zc + Vector2(0, -30), zc.y, "ink", 3 + t, {"tier": t})
				1:   # S2 同葬无光之愿：脚下旋涡 + 小鱼散开
					var tt: int = maxi(t, 1)
					_sk_push(pv, o, {"skr": "vortex", "c": zc, "tier": tt, "ly": "gd", "life": 12.0 / 15.0, "o": o, "fz": true})   # 歌域圆心 = 队长
					_sk_push(pv, o, {"skr": "fishburst", "c": zc, "tier": tt, "ly": "up", "gy": zc.y + 1.0, "life": 12.0 / 15.0, "o": o, "fz": true})
					if tt >= 2:
						_sk_push(pv, o, {"skr": "spout", "c": zc, "ly": "up", "gy": zc.y + 2.0, "life": 8.0 / 15.0, "o": o, "fz": true})
					R._light(o, zc + Vector2(0, -12), 110.0, 0.5, 0.15, SK_B[4])
				2:   # S3 潮涌，潮枯：起手就是第一次潮涌，之后每 3 秒一次（draw_floor 里按技能剩余时间续）
					st.s3_next = g.t
		"sk_link":   # 连携 v2「歌声」：区域笔触圈 3 秒 + 起手一道大浪 + 音符
			var lc: Vector2 = d.c
			var lr: float = float(d.r)
			if raw:
				pv._push({"k": "sk_raw_s1_e2", "t0": g.t, "gp": lc, "ly": "raw", "rot": 0.0, "sc": px * (lr * 0.5) / 95.0, "oid": str(o.id)})
				return
			_sk_push(pv, o, {"skr": "song", "c": lc, "r": lr, "ly": "gd", "life": 3.0})
			_sk_push(pv, o, {"skr": "wave", "c": lc, "r": lr, "tier": 2, "ly": "gd", "life": 6.0 / 15.0})
			_sk_push(pv, o, {"skr": "songnotes", "c": lc, "r": lr, "ly": "up", "gy": lc.y, "life": 3.0})
			R._light(o, lc + Vector2(0, -10), lr, 0.6, 0.15, SK_B[4])
		"sk_combo":   # 旧连携（link/v2 关）：落点大一号声浪 + 命中音符
			var cc: Vector2 = d.at
			var cr: float = float(d.r)
			if raw:
				pv._push({"k": "sk_raw_wave_e2", "t0": g.t, "gp": cc, "ly": "raw", "rot": 0.0, "sc": px * (cr * 0.5) / 95.0, "oid": str(o.id)})
				return
			_sk_push(pv, o, {"skr": "wave", "c": cc, "r": cr, "tier": 2, "big": true, "ly": "gd", "life": 6.0 / 15.0})
			_sk_notes(pv, o, d.get("es", []), 2, R, p)
			R._light(o, cc + Vector2(0, -10), cr, 0.6, 0.15, SK_B[4])


## 命中音符：每下至多 2 / 3 / 4 个（E0 / E1 / E2），同屏至多 12 个
static func _sk_notes(pv: P, o, es: Array, t: int, R, p: Dictionary, rose := false) -> void:
	var nmax: int = [2, 3, 4][t]
	var n := 0
	for e in es:
		if n >= nmax or _sk_count(pv, o, "note") >= 12:
			break
		if not (e is Dictionary) or e.get("dead", false):
			continue
		var hp: Vector2 = e.pos + Vector2(0, -float(e.r) - 6.0)
		_sk_push(pv, o, {"skr": "note", "c": hp, "hp": e.pos + Vector2(0, -float(e.r) * 0.5), "tier": t, "rose": rose, "fl": (n % 2) == 1, "ly": "up", "gy": float(e.pos.y) + 1.0, "life": 9.0 / 15.0})
		if n == 0 and pv.mode() == 1:
			R._grains(o, hp, float(e.pos.y) + 2.0, "ink", 3 + t, {"tier": t})   # docs/270：Noita 水滴 4–6 px、寿命约 0.9 秒，每下 3 / 4 / 5 颗
		n += 1


## 地面层：歌域（常驻）、伊莎玛拉小歌域、S3 持续加粗 / 潮涌、一次性贴地件
static func _sk_draw_floor(pv: P, o) -> void:
	var g = pv.g
	var cv = o.cv
	var id: String = str(o.id)
	var t: int = pv.tier(o)
	var st: Dictionary = _sk_state(pv, o)
	var bt: float = float(_sk_beat(pv)) / 15.0
	var s3: float = o.skill_active_left(2)
	if s3 > 0.0 and float(st.s3_next) >= 0.0 and g.t >= float(st.s3_next):   # 潮涌：起手一次，之后每 3 秒
		st.s3_next = g.t + 3.0
		_sk_push(pv, o, {"skr": "surge", "c": o.zone_c(), "r": float(o.zr), "ly": "gd", "life": 7.0 / 15.0, "o": o, "fz": true})
		_sk_push(pv, o, {"skr": "pillars", "c": o.zone_c(), "r": float(o.zr), "ly": "up", "gy": o.zone_c().y + 2.0, "life": 7.0 / 15.0, "o": o, "fz": true})
		var R = load("res://scripts/render/fx_recipe.gd").of(g)
		R._light(o, o.zone_c() + Vector2(0, -20), minf(float(o.zr), 220.0), 0.8, 0.15, SK_B[4])
		R._light(o, o.zone_c() + Vector2(0, -60), 120.0, 0.6, 0.15, SK_R[4])
		R._grains(o, o.zone_c() + Vector2(0, -30), o.zone_c().y, "ink", 10, {"tier": 2})
	elif s3 <= 0.0:
		st.s3_next = -1.0
	if o.pos != Vector2.INF and o.B.has("zone"):
		var zc: Vector2 = o.zone_c()
		var zv: float = _sk_r(pv, o, "self", float(o.zr))
		var s1: bool = o.skill_active_left(0) > 0.0
		_sk_domain(pv, cv, zc, zv, t, s1, s3 > 0.0, bt, 0.0, false)
	for s in (o.sm.list if not o.sm.is_empty() else []):
		var szr: float = float(s.get("zr", 0.0))
		if szr <= 0.0 or s.gone:
			continue
		var fa: float = clampf(float(s.t) / 0.5, 0.0, 1.0)
		_sk_domain(pv, cv, s.pos, _sk_r(pv, o, "sm", szr) * fa, t, false, false, bt, 3.7, true)
	for it in pv.items_for(id):
		if str(it.ly) == "gd" and it.has("skr"):
			_sk_draw_gd(pv, cv, o, it)


## 一个歌域：边上 3–5 段粗笔触（慢转）+ 贴边淡渐变 + 内侧反向细笔触线；rose = 伊莎玛拉小歌域（酒红、细）
static func _sk_domain(pv: P, cv, c: Vector2, R: float, t: int, s1: bool, s3: bool, bt: float, seed: float, rose: bool) -> void:
	var g = pv.g
	if R <= 8.0:
		return
	var dim: float = clampf(float(g.world.fx_dim), 0.5, 1.0)
	var C: Array = SK_T if rose else SK_B
	var n: int = (3 + t) if not s3 else 6
	if s1 and not s3:
		n += 1
	var w: float = (3.0 if t < 2 else 4.0) if not s3 else 5.0
	if rose:
		n = 3
		w = 2.0
	var spin: float = (0.10 if not s3 else 0.28) * (1.0 if not rose else -1.3)
	var rot: float = bt * spin + seed
	var main: Color = C[3] if not (s1 or s3) else C[4]
	main.a = 0.92 * dim
	var hi: Color = C[5]
	hi.a = 0.9 * dim
	var lo: Color = C[1]
	lo.a = 0.8 * dim
	var cover: float = 0.62 if not s3 else 0.72
	for j in n:
		var a0: float = rot + TAU * (float(j) + 0.15 * _sk_h(pv, j, seed + 1.0)) / float(n)
		var a1: float = a0 + TAU / float(n) * cover * (0.75 + 0.5 * _sk_h(pv, j + 5, seed + 1.0))
		_sk_arc(pv, cv, c, R * (0.985 + 0.03 * _sk_h(pv, j + 11, seed)), a0, a1, w, main, hi, lo, seed + float(j) * 1.7)
	# 贴边淡渐变（不平涂中心）
	var ga: float = (0.10 if not s3 else 0.16) * dim * (0.7 if rose else 1.0)
	_sk_grad(pv, cv, c, R - g.PX * (10.0 if not s3 else 18.0), R, C[3], 0.0, ga)
	# 内侧细笔触线（11-05 用户「内部可以稍微实一点，或者加点线条」）：2–4 道，反向慢转，1 美术像素
	if not rose:
		var nl: int = 2 + t if not s3 else 5
		var lc: Color = C[4]
		lc.a = (0.45 if not s3 else 0.6) * dim
		for j in nl:
			var rr: float = R * (0.62 + 0.22 * _sk_h(pv, j + 31, seed))
			var a0: float = -bt * (0.18 if not s3 else 0.45) + TAU * float(j) / float(nl) + _sk_h(pv, j + 41, seed)
			_sk_arc(pv, cv, c, rr, a0, a0 + 0.9 + 0.5 * _sk_h(pv, j + 51, seed), 1.0, lc, Color(0, 0, 0, 0), Color(0, 0, 0, 0), seed + 9.0 + j)


## 挂在人身上的件（歌域圆心 fz / 本人脚下 fs）：持续期间跟着施放者当前位置走（按 15 fps 拍跳格）；落在地上的件留在原地
static func _sk_c(pv: P, it: Dictionary) -> Vector2:
	var o = it.get("o", null)
	if o != null and is_instance_valid(o) and o.pos != Vector2.INF:
		if it.get("fz", false):
			return pv._snap(o.zone_c())
		if it.get("fs", false):
			return pv._snap(o.pos)
	return it.c


static func _sk_draw_gd(pv: P, cv, o, it: Dictionary) -> void:
	var g = pv.g
	var f: int = pv.frame_of(float(it.t0))
	var px: float = g.PX
	var c: Vector2 = _sk_c(pv, it)
	match str(it.skr):
		"wave":   # 声浪：断口笔触浪 0.6R → R（4 拍扩到边、第 5 拍淡），E1 第二道、E2 夹酒红暗流
			if f < 0 or f > 5:
				return
			var t: int = int(it.tier)
			var rose: bool = it.get("rose", false)
			var thin: bool = it.get("thin", false)
			var sea: bool = it.get("sea", false)
			var C: Array = SK_T if sea else (SK_R if rose else SK_B)
			var R: float = float(it.r) * _sk_rk(pv, it) * [0.6, 0.78, 0.9, 0.97, 1.0, 1.02][f]
			var w: float = ([4.0, 5.0, 6.0][t] if not thin else 2.0) * [1.0, 1.0, 0.85, 0.7, 0.5, 0.35][f]
			if it.get("big", false):
				w += 2.0
			var col: Color = C[6] if f == 0 else (C[5] if f == 1 else C[4])
			if f >= 4:
				col = C[3]
				col.a = 0.6 if f == 4 else 0.35
			var hi: Color = C[6] if f <= 2 else C[5]
			var lo: Color = C[2]
			var seed: float = float(int(it.t0 * 7.0) % 97)
			_sk_ring(pv, cv, c, R, 7 if t < 2 else 8, w, col, hi, lo, seed, seed * 0.37)
			if t >= 1 and not thin and f >= 1:   # 精一：晚一拍的第二道细浪
				var c2: Color = C[4]
				c2.a = 0.7 if f < 4 else 0.3
				_sk_ring(pv, cv, c, R * 0.86, 6, 2.0, c2, Color(0, 0, 0, 0), Color(0, 0, 0, 0), seed + 3.0, seed * 0.37 + 0.4, 0.7)
			if t >= 2 and not rose and not sea and f <= 4:   # 精二：浪里一道酒红暗流（专属色），紧贴浪内侧
				var rc: Color = SK_R[3] if f < 3 else SK_R[2]
				_sk_ring(pv, cv, c, R - (w * 0.5 + 1.5) * px, 7, 2.0, rc, SK_R[4], Color(0, 0, 0, 0), seed + 5.0, seed * 0.37 + 0.2, 0.7)
			if f <= 1:
				var ne: int = clampi(int(R / (px * 3.0)), 16, 64)   # docs/270：浪头白热整圈进发光层（约每 16 世界像素一点）
				for j in ne:
					pv._glow(_sk_ep(pv, c, R, seed + TAU * float(j) / float(ne)), C[6])
		"echo_ring":   # 余音：歌域外圈一道淡紫环闪 5 拍（docs/310 §4.2：原酒红细环 α 降到 0.25、与基础声浪分不开 → 专属淡紫、2 像素、带暗边）
			if f < 0 or f > 4:
				return
			var col2: Color = SK_V[3] if f < 2 else SK_V[2]
			col2.a = [1.0, 0.95, 0.8, 0.55, 0.3][f]
			var lo2: Color = SK_V[0]
			lo2.a = col2.a * 0.8
			_sk_ring(pv, cv, c, float(it.r) * _sk_rk(pv, it) * (0.92 + 0.02 * f), 9, 4.0, col2, SK_V[4] if f < 2 else Color(0, 0, 0, 0), lo2, float(int(it.t0 * 5.0) % 31), 0.3)
		"mini", "splash":   # 小声浪 / 溅射环
			var nb: int = 4 if str(it.skr) == "mini" else 3
			if f < 0 or f >= nb:
				return
			var R2: float = float(it.r) * [0.5, 0.8, 1.0, 1.05][f]
			var col3: Color = SK_B[5] if f == 0 else SK_B[4]
			col3.a = [1.0, 0.85, 0.5, 0.3][f]
			_sk_ring(pv, cv, c, R2, 5, 2.0 if f < 2 else 1.0, col3, Color(0, 0, 0, 0), Color(0, 0, 0, 0), float(int(it.t0 * 9.0) % 41), 0.0, 0.75)
		"burst":   # 深海的回响：酒红小爆环 + 实心亮芯一拍
			if f < 0 or f > 4:
				return
			var R3: float = float(it.r) * [0.35, 0.7, 0.9, 1.0, 1.05][f]
			var col4: Color = SK_R[5] if f == 0 else SK_R[4]
			col4.a = [1.0, 1.0, 0.8, 0.5, 0.25][f]
			_sk_ring(pv, cv, c, R3, 6, 3.0 if f < 2 else 2.0, col4, SK_R[6] if f < 2 else Color(0, 0, 0, 0), SK_R[2], float(int(it.t0 * 3.0) % 23), 0.5)
			if f <= 1:
				_sk_grad(pv, cv, c, 0.0, R3 * 0.6, SK_R[4], 0.55, 0.2)
		"vortex":   # S2 起手旋涡：3 / 5 条旋臂笔触从脚下卷开再淡
			if f < 0 or f > 11:
				return
			var t2: int = int(it.tier)
			var arms: int = 3 if t2 < 2 else 5
			var Rv: float = 130.0 * [0.4, 0.6, 0.75, 0.85, 0.92, 0.97, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0][f]
			var al: float = 1.0 if f < 7 else (1.0 - float(f - 6) / 6.0)
			for j in arms:
				var base: float = TAU * float(j) / float(arms) + float(f) * 0.35
				for s in 3:   # 每条旋臂三节，越往外越靠后（旋）
					var rr: float = Rv * (0.35 + 0.25 * float(s))
					var cl: Color = [SK_B[5], SK_B[4], SK_B[3]][s]
					cl.a = al * [1.0, 0.9, 0.75][s]
					_sk_arc(pv, cv, c, rr, base + 0.55 * float(s), base + 0.55 * float(s) + 1.0, [4.0, 4.0, 3.0][s] + (1.0 if t2 >= 2 else 0.0), cl, SK_B[6] if s == 0 and f < 4 else Color(0, 0, 0, 0), SK_B[1], float(j) * 3.0 + float(s))
			_sk_grad(pv, cv, c, 0.0, Rv * 0.5, SK_B[2], 0.35 * al, 0.0)
		"surge":   # S3 潮涌：粗笔触亮蓝环扩到歌域边 + 深蓝内影 + 内部实心渐变 + 8 道旋转笔触线
			if f < 0 or f > 6:
				return
			var Rs: float = float(it.r) * _sk_rk(pv, it) * [0.6, 0.78, 0.9, 0.97, 1.0, 1.0, 1.0][f]
			var fa2: float = [1.0, 1.0, 1.0, 0.9, 0.75, 0.5, 0.25][f]
			if Bal.v("fx/px_plane_sk_fill", 1.0) <= 0.0:   # 0 = 旧版平滑渐变（对照用）
				var fill_k: float = [1.0, 0.9, 0.7, 0.45, 0.2, 0.0, 0.0][f]
				_sk_grad(pv, cv, c, 0.0, Rs * 0.98, SK_B[2], 0.35 * fill_k, 0.5 * fill_k)
			else:
				_sk_surge_fill(pv, cv, c, Rs, f)
			var nl: int = 8
			for j in nl:   # 旋转向心笔触线
				var a0: float = TAU * float(j) / float(nl) + float(f) * 0.32
				var lc: Color = SK_B[5] if f < 3 else SK_B[4]
				lc.a = fa2 * 0.9
				for s in 2:
					var rr2: float = Rs * (0.42 + 0.26 * float(s))
					_sk_arc(pv, cv, c, rr2, a0 + 0.35 * float(s), a0 + 0.35 * float(s) + 0.55, 2.0, lc, Color(0, 0, 0, 0), Color(0, 0, 0, 0), float(j) + float(s) * 5.0)
			var mc: Color = SK_B[6] if f == 0 else (SK_B[5] if f <= 2 else SK_B[4])
			mc.a = fa2
			var w8: float = 8.0 * [1.0, 1.0, 0.95, 0.85, 0.7, 0.55, 0.4][f]
			_sk_ring(pv, cv, c, Rs, 6, w8, mc, SK_B[6], Color(SK_B[1].r, SK_B[1].g, SK_B[1].b, fa2), 17.0, float(f) * 0.12, 0.9)
			if f <= 2:
				for j in 10:
					pv._glow(_sk_ep(pv, c, Rs, TAU * float(j) / 10.0 + 0.3), SK_B[6])
		"song":   # 连携 v2「歌声」区域：4 段粗笔触 + 3 段酒红内圈（反向）+ 贴边渐变，3 秒，最后 0.4 秒淡
			var age: float = g.t - float(it.t0)
			var fa3: float = 1.0 if age < 2.6 else clampf((3.0 - age) / 0.4, 0.0, 1.0)
			var bt: float = float(_sk_beat(pv)) / 15.0
			var Rg: float = float(it.r)
			var mcol: Color = SK_B[4]
			mcol.a = 0.95 * fa3
			for j in 4:
				var a0: float = bt * 0.35 + TAU * float(j) / 4.0
				_sk_arc(pv, cv, c, Rg, a0, a0 + 1.05, 5.0, mcol, Color(SK_B[5].r, SK_B[5].g, SK_B[5].b, fa3), Color(SK_B[1].r, SK_B[1].g, SK_B[1].b, fa3), 21.0 + float(j))
			var rcol: Color = SK_R[3]
			rcol.a = 0.9 * fa3
			for j in 3:
				var a0: float = -bt * 0.5 + TAU * float(j) / 3.0
				_sk_arc(pv, cv, c, Rg * 0.82, a0, a0 + 1.2, 2.0, rcol, Color(SK_R[4].r, SK_R[4].g, SK_R[4].b, fa3), Color(0, 0, 0, 0), 31.0 + float(j))
			_sk_grad(pv, cv, c, Rg - px * 14.0, Rg, SK_B[3], 0.0, 0.16 * fa3)


## S3 潮涌内部（11-05 用户「内部需要渐变填充或者别的填充方法吗」→ 试分阶色带）：贴着潮涌环往里 3 圈硬边色带
## （深 → 中 → 暗，每圈一个颜色、一个透明度，按颜色阶跳，不做平滑过渡），靠里 40% 不填（站人处清楚）；
## 色带里一层水纹：短亮线随节拍转（按固定散列成团，不抖动）；收的时候色带从外往里一段段断开，不整片淡出
static func _sk_surge_fill(pv: P, cv, c: Vector2, Rs: float, f: int) -> void:
	var g = pv.g
	if f > 5:
		return
	var px: float = g.PX
	var cover: float = [1.0, 1.0, 1.0, 0.8, 0.55, 0.3][f]
	var widths: Array = [9.0, 9.0, 12.0]   # 美术像素
	var cols: Array = [SK_B[3], SK_B[2], SK_B[1]]
	var alps: Array = [0.5, 0.42, 0.34]
	var r: float = Rs - 4.0 * px   # 从潮涌环的内影往里
	for k in 3:
		var w: float = float(widths[k])
		var rc: float = r - w * px * 0.5
		var col: Color = cols[k]
		col.a = float(alps[k]) * (1.0 if f < 4 else 0.8)
		var kc: float = cover * (1.0 if k == 0 else (0.92 if k == 1 else 0.85)) if f >= 3 else 1.0
		if kc >= 0.999:
			_sk_grad(pv, cv, c, rc - w * px * 0.5, rc + w * px * 0.5, col, col.a, col.a)
		else:   # 断开：每圈 10 段，覆盖率按拍降，外圈先断
			var nseg: int = 10
			for j in nseg:
				var a0: float = TAU * (float(j) + 0.3 * _sk_h(pv, j + k * 13, 2.0)) / float(nseg) + 0.2 * float(k)
				var a1: float = a0 + TAU / float(nseg) * kc * (0.75 + 0.25 * _sk_h(pv, j + 5, float(k)))
				_sk_arc(pv, cv, c, rc, a0, a1, w, col, Color(0, 0, 0, 0), Color(0, 0, 0, 0), float(j + k * 10), false)
		r -= w * px
		if r < Rs * 0.42:
			break
	# 水纹：色带里 14 道短亮线，按拍转、成团分布
	if f <= 4:
		var gc: Color = SK_B[5] if f <= 1 else SK_B[4]
		gc.a = [0.95, 0.9, 0.8, 0.6, 0.35][f]
		for j in 14:
			var rr: float = Rs * (0.5 + 0.42 * _sk_h(pv, j, 7.0))
			var a0: float = TAU * _sk_h(pv, j + 20, 7.0) + float(f) * (0.22 if j % 2 == 0 else -0.16)
			var ln: float = (6.0 + 8.0 * _sk_h(pv, j + 40, 7.0)) * px / maxf(rr, 1.0)
			_sk_arc(pv, cv, c, rr, a0, a0 + ln, 1.0, gc, Color(0, 0, 0, 0), Color(0, 0, 0, 0), float(j) + 90.0)


## 立起层（排序项 kind 7）
static func _sk_draw_up(pv: P, ci, it: Dictionary) -> void:
	var g = pv.g
	var f: int = pv.frame_of(float(it.t0))
	var px: float = g.PX
	var c: Vector2 = _sk_c(pv, it)
	match str(it.skr):
		"note":   # 命中音符：第 0 拍白头，往上飘 9 拍，最后两拍只剩符头
			if f < 0 or f > 8:
				return
			var t: int = int(it.tier)
			var rose: bool = it.get("rose", false)
			var pat: Array = SK_NOTE2 if t >= 2 else SK_NOTE
			var C: Array = SK_T if rose else SK_R   # 酒红音符：敌人多是白 / 蓝，压在上面读得出来；海嗣的音符用海嗣青
			var col: Color = C[5] if f < 3 else C[4]
			var head: Color = C[6] if f == 0 else (C[5] if f < 4 else C[4])
			if f >= 7:
				col.a = 0.0
				head.a = 0.6
			var up: float = float(f) * px * (1.0 if f < 5 else 0.6)
			var w: float = float((pat[0] as String).length()) * px
			var shc: Color = C[0]
			shc.a = 0.85 if f < 7 else 0.0
			_sk_pat(pv, ci, pat, c + Vector2(-w * 0.5 + (10.0 if it.get("fl", false) else -10.0), -float(pat.size()) * px - up - 8.0), col, head, it.get("fl", false), shc)
			if f <= 1 and it.has("hp"):   # 命中点白芯（音符的「起音」）：十字 5 格 + 外圈 4 格浅色，头两拍，整块进发光层（docs/270：命中帧核心辉光）
				var hc: Vector2 = pv._snap(it.hp)
				for dq in [Vector2(0, 0), Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1), Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2), Vector2(0, -2)]:
					var core: bool = absf(dq.x) + absf(dq.y) <= 1.0
					if f == 1 and not core:
						continue
					ci.draw_rect(Rect2(hc + dq * px, Vector2(px, px)), C[6] if core else C[5])
					pv._glow(hc + dq * px, C[6])
			if f <= 1:
				var tl: Vector2 = pv._snap(c + Vector2(-w * 0.5 + (10.0 if it.get("fl", false) else -10.0), -float(pat.size()) * px - up - 8.0))
				for y in pat.size():   # 命中头两拍：整枚音符进发光层（docs/270：命中帧核心辉光）
					var row: String = pat[y]
					for x in row.length():
						if row[x] == "#":
							pv._glow(tl + Vector2(float(x), float(y)) * px, C[6] if y >= pat.size() - 2 else C[5])
		"buff":   # 增益标记：吃到增益的干员头顶一枚双箭头，往上飘 8 拍（S1 蓝、S3 酒红），跟着那名干员走
			if f < 0 or f > 7:
				return
			var q2 = it.get("tgt", null)
			var bp: Vector2 = c
			if q2 != null and is_instance_valid(q2) and q2.pos != Vector2.INF:
				bp = q2.pos
			var Cb: Array = SK_R if it.get("s3", false) else SK_B
			var colb: Color = Cb[5] if f < 4 else Cb[4]
			colb.a = 1.0 if f < 6 else 0.5
			var tlb: Vector2 = bp + Vector2(-5.0 * px * 0.5, -58.0 - float(f) * px)
			_sk_pat(pv, ci, SK_UP, tlb, colb, Cb[6] if f < 2 else colb, false, Color(Cb[0].r, Cb[0].g, Cb[0].b, 0.7))
			if f <= 1:
				pv._glow(tlb + Vector2(2.0 * px, 0.0), Cb[6])
		"pop":   # 命中点白芯：十字 5 格 + 外圈 4 格浅色（第 1 拍只剩十字），整块进发光层
			if f < 0 or f > 1:
				return
			var Cp: Array = SK_T if it.get("sea", false) else SK_B
			var hcp: Vector2 = pv._snap(c)
			for dq in [Vector2(0, 0), Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1), Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2), Vector2(0, -2)]:
				var core2: bool = absf(dq.x) + absf(dq.y) <= 1.0
				if f == 1 and not core2:
					continue
				ci.draw_rect(Rect2(hcp + dq * px, Vector2(px, px)), Cp[6] if core2 else Cp[5])
				pv._glow(hcp + dq * px, Cp[6])
		"pillars":   # S3 潮涌：5 根粗亮红竖光柱从歌域里冲起又回落（原作 skill_03_buff_02 的红光柱）；白热芯、亮红身、暗酒红边，顶端淡出
			if f < 0 or f > 6:
				return
			var Rr: float = float(it.r) * _sk_rk(pv, it)
			var H: float = 80.0 * px * [0.55, 1.0, 1.0, 0.95, 0.85, 0.7, 0.5][f]
			var W: int = [11, 15, 15, 13, 11, 7, 4][f]
			for j in 5:
				var a: float = TAU * float(j) / 5.0 + 0.6 + 0.2 * _sk_h(pv, j, float(it.t0))
				var foot: Vector2 = pv._snap(_sk_ep(pv, c, Rr * (0.28 + 0.22 * _sk_h(pv, j + 3, 1.0)), a))   # 围在她身边冲起（原作光柱贴着人）
				var hj: float = H * (0.8 + 0.35 * _sk_h(pv, j + 9, 2.0))
				_sk_pillar(pv, ci, foot, W, hj, f)
		"fishburst":   # S2 起手：小鱼从脚下沿旋涡散开
			if f < 0 or f > 11:
				return
			var t2: int = int(it.tier)
			var n: int = 3 if t2 < 2 else 5
			for j in n:
				var a: float = TAU * float(j) / float(n) + float(f) * 0.3
				var rr: float = (12.0 + 7.0 * float(f)) * px
				var q: Vector2 = _sk_ep(pv, c, rr, a) + Vector2(0, -10.0 - 1.5 * float(f))
				var fl: bool = cos(a + PI * 0.5) < 0.0
				_sk_pat(pv, ci, SK_FISH, q, SK_R[3], SK_R[4], fl, Color(SK_R[0].r, SK_R[0].g, SK_R[0].b, 0.8))
		"spout":   # S2 精二：涡眼冲起一道水柱
			if f < 0 or f > 7:
				return
			var Hs: float = 52.0 * px * [0.4, 0.8, 1.0, 1.0, 0.9, 0.75, 0.55, 0.35][f]
			_sk_column(pv, ci, pv._snap(c), [4, 5, 5, 5, 4, 4, 3, 2][f], Hs, SK_B, f)
		"songnotes":   # 连携 v2：区域里每 0.5 秒冒 3 个音符往上飘
			var age: float = g.t - float(it.t0)
			if age > 3.0:
				return
			var Rg: float = float(it.r)
			for k in 3:
				var wave: int = int(age * 2.0)
				var u: float = fposmod(age * 2.0, 1.0)
				var a: float = TAU * (float(k) / 3.0 + 0.37 * float(wave))
				var q: Vector2 = _sk_ep(pv, c, Rg * (0.35 + 0.4 * _sk_h(pv, k + wave * 3, 4.0)), a)
				var fb: int = int(u * 7.5)
				var colN: Color = (SK_R if k == 1 else SK_B)[5]
				var headN: Color = (SK_R if k == 1 else SK_B)[6 if fb == 0 else 5]
				if fb >= 6:
					colN.a = 0.0
				_sk_pat(pv, ci, SK_NOTE, q + Vector2(-8.0, -30.0 - float(fb) * px), colN, headN, k == 2, Color(SK_B[0].r, SK_B[0].g, SK_B[0].b, 0.0 if fb >= 6 else 0.8))


## 红光柱：宽 W 美术像素、高 H 世界像素；脚下一小片亮红地光
static func _sk_pillar(pv: P, ci, foot: Vector2, W: int, H: float, f: int) -> void:
	var g = pv.g
	var px: float = g.PX
	var x0: float = foot.x - float(W / 2) * px
	var steps: int = maxi(1, int(H / (px * 4.0)))
	for s in steps:   # 自下而上 4 美术像素一段，顶端三段淡出
		var y: float = foot.y - float(s + 1) * px * 4.0
		var top_k: float = 1.0 - clampf(float(s - (steps - 3)) / 3.0, 0.0, 1.0) * 0.85 if steps > 3 else 1.0
		for x in W:
			var dx: int = absi(x - W / 2)
			var edge: bool = x == 0 or x == W - 1
			var halo: bool = not edge and dx >= W / 2 - 2 and W >= 9
			var core: bool = W >= 5 and dx <= maxi(0, W / 5)
			var col: Color = SK_R[2] if edge else (SK_R[3] if halo else (SK_R[6] if core and f <= 2 else (SK_R[5] if core else SK_R[4])))
			col.a = top_k * (0.45 if edge else (0.75 if halo else 1.0))
			ci.draw_rect(Rect2(Vector2(x0 + float(x) * px, y), Vector2(px, px * 4.0)), col)
		if s % 2 == 0 and f <= 3:
			pv._glow(Vector2(foot.x, y), SK_R[5])
	var fc: Color = SK_R[4]
	fc.a = 0.6
	ci.draw_rect(Rect2(pv._snap(foot + Vector2(-float(W) * px, -px)), Vector2(float(W) * 2.0 * px, px * 2.0)), fc)


## 水柱（S2 涡眼）：同红光柱的画法，蓝色
static func _sk_column(pv: P, ci, foot: Vector2, W: int, H: float, C: Array, f: int) -> void:
	var g = pv.g
	var px: float = g.PX
	var x0: float = foot.x - float(W / 2) * px
	var steps: int = maxi(1, int(H / (px * 3.0)))
	for s in steps:
		var y: float = foot.y - float(s + 1) * px * 3.0
		var top_k: float = 1.0 if s < steps - 2 else 0.55
		for x in W:
			var edge: bool = x == 0 or x == W - 1
			var col: Color = C[3] if edge else (C[6] if f <= 1 and x == W / 2 else C[5])
			col.a = top_k
			ci.draw_rect(Rect2(Vector2(x0 + float(x) * px, y), Vector2(px, px * 3.0)), col)


## 立起层的状态件：S1 身周气泡、S2 常驻小鱼
static func _sk_sort_items(pv: P, o, out: Array) -> void:
	var t: int = pv.tier(o)
	if o.skill_active_left(0) > 0.0 and o.B.has("zone"):
		out.append({"skr_s": "bubble", "o": o, "gy": o.zone_c().y + 3.0})   # 气泡罩在歌域圆心 = 队长身上
	var s2on: bool = o.get("perm_on") != null and bool(o.perm_on[1])
	if s2on and o.B.has("zone"):
		out.append({"skr_s": "fish", "o": o, "gy": o.zone_c().y + 1.0})


static func _sk_draw_state_up(pv: P, ci, it: Dictionary) -> void:
	var g = pv.g
	var o = it.o
	var t: int = pv.tier(o)
	var px: float = g.PX
	var bt: int = _sk_beat(pv)
	match str(it.skr_s):
		"bubble":   # S1：身周一团气泡（细膜 + 左上高光 + 淡淡的水 0.16）；E1 双层膜、E2 三团（主泡两侧各连一个小泡）
			var zc0: Vector2 = o.zone_c()
			var c: Vector2 = pv._snap(zc0 + Vector2(0, -26))
			var wob: float = [0.0, 1.0, 0.0, -1.0][bt % 4] * px
			var Rb: float = (23.0 if t == 0 else 26.0) * px
			var bubs: Array = [[c, Rb + wob]]
			if t >= 2:
				bubs.append([pv._snap(c + Vector2(-Rb * 1.05, Rb * 0.45)), Rb * 0.42 - wob * 0.5])
				bubs.append([pv._snap(c + Vector2(Rb * 1.0, Rb * 0.55)), Rb * 0.36 + wob * 0.5])
			for b in bubs:
				var bc: Vector2 = b[0]
				var br: float = b[1]
				ci.draw_circle(bc, br, Color(SK_B[3].r, SK_B[3].g, SK_B[3].b, 0.16))
				ci.draw_arc(bc, br, 0.0, TAU, clampi(int(br / 2.0), 12, 40), Color(SK_B[5].r, SK_B[5].g, SK_B[5].b, 0.9), px)
				ci.draw_arc(bc, br - px * 2.0, PI * 1.05, PI * 1.45, 8, SK_B[6], px)   # 左上高光
				if t >= 1 and br > Rb * 0.6:
					ci.draw_arc(bc, br - px * 3.0, PI * 0.1, PI * 0.9, 14, Color(SK_B[4].r, SK_B[4].g, SK_B[4].b, 0.6), px)   # 精一：第二层膜（下半）
			for q in 10:   # 气泡左上高光弧进发光层（docs/270：持续类核心辉光）
				var aq: float = PI * (1.05 + 0.04 * float(q))
				pv._glow(c + Vector2(cos(aq), sin(aq)) * (Rb - px * 2.0), SK_B[6])
			# 脚下酒红细环（贴地，跟在立起件里画：它跟着气泡走、本来就在她脚下）
			var fr := PackedVector2Array()
			for k in 25:
				fr.append(pv._snap(_sk_ep(pv, zc0 + Vector2(0, 2), 20.0 * px, TAU * float(k) / 24.0)))
			ci.draw_polyline(fr, Color(SK_R[3].r, SK_R[3].g, SK_R[3].b, 0.85), px)
			if t >= 1:   # 精一：外面再一圈酒红细环
				var fr2 := PackedVector2Array()
				for k in 25:
					fr2.append(pv._snap(_sk_ep(pv, zc0 + Vector2(0, 2), 26.0 * px, TAU * float(k) / 24.0 + 0.1)))
				ci.draw_polyline(fr2, Color(SK_R[2].r, SK_R[2].g, SK_R[2].b, 0.7), px)
			# 上浮小泡：每拍错落 3–5 个
			var nb: int = 3 + t
			for k in nb:
				var ph: int = (bt + k * 5) % 15
				var bx: float = (_sk_h(pv, k, 3.0) - 0.5) * Rb * 1.6
				var q: Vector2 = pv._snap(c + Vector2(bx, Rb * 0.6 - float(ph) * px * 2.0))
				ci.draw_rect(Rect2(q, Vector2(px, px)), Color(SK_B[5].r, SK_B[5].g, SK_B[5].b, 0.9 if ph < 10 else 0.4))
		"fish":   # S2 常驻：酒红小鱼绕歌域边慢慢游（E1 3 条 / E2 5 条）
			var zc: Vector2 = o.zone_c()
			var zv: float = _sk_r(pv, o, "self", float(o.zr))
			var n: int = 3 if t < 2 else 5
			for j in n:
				var a: float = TAU * float(j) / float(n) + float(bt) / 15.0 * 0.22 * (1.0 if j % 2 == 0 else 0.8)
				var q: Vector2 = _sk_ep(pv, zc, zv * (0.9 + 0.06 * _sk_h(pv, j, 6.0)), a) + Vector2(-7.0, -16.0 - px * float((bt + j * 4) % 6 / 3))
				var fl: bool = sin(a) > 0.0   # 顺时针游：上半圈朝右、下半圈朝左
				_sk_pat(pv, ci, SK_FISH, q, Color(SK_R[3].r, SK_R[3].g, SK_R[3].b, 0.9), SK_R[4], fl, Color(SK_R[0].r, SK_R[0].g, SK_R[0].b, 0.7))


## 旧做法（2）：整张贴（光晕烤进颜色，按歌域半径小数缩放、盖在所有单位上）；S1 / S3 期间按技能剩余时间循环
static func _sk_draw_raw(pv: P, o) -> void:
	var g = pv.g
	var cv = o.cv
	var id: String = str(o.id)
	var rf: float = Bal.v("fx/px_plane_raw_fps", 12.8)
	for it in pv.items_for(id):
		if str(it.ly) != "raw":
			continue
		pv._draw_raw(cv, str(it.k), int((g.t - float(it.t0)) * rf), it.gp, float(it.rot), float(it.sc))
