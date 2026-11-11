## 世界层缩圈 / 溟痕带绘制（world.draw_zone 一族）。docs/286 §4 第三批从 render/world.gd 原样拆出，行为不变。
## 全部是 static func，第一个参数 wv = world（render/world.gd 实例）；缓存表 _zone_tabs / _zone_btabs 仍在 world 上，经 wv. 读写。
extends RefCounted

const W = preload("res://scripts/render/world.gd")
const Bal = preload("res://scripts/core/balance.gd")
const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错


static func draw_zone(wv: W) -> void:
	var g: Game = wv.g
	if g.zone_state == 0:
		return
	var vs := g.view_size()
	var far := vs.length() + 200.0
	var seg := 96
	var outer := g.zone_r + far + g.ppos.distance_to(g.zone_c)
	var pulse := 0.5 + 0.5 * sin(g.t * 2.5)
	_zone_dark_fast(wv, seg, far, outer)
	draw_zone_band(wv, pulse)
	_zone_next_ring(wv)


static func _zone_cells(wv: W, c: Vector2, r: float, cw: float, nb2: int, rj: Vector2i) -> Array:
	var g: Game = wv.g
	var a0: int = floori((rj.x - 1) / 4.0) * 4
	var a1: int = ceili((rj.y + 2) / 4.0) * 4
	var key: Array = [c, r, nb2, a0, a1]
	if key == wv._zc_key:
		return wv._zc_val
	var ins := {}
	for jr in range(a0, a1):
		var d3 := Vector2.from_angle(TAU * float(posmod(jr, nb2)) / nb2)
		var rr := r - 4.0
		while rr <= r + 36.0:
			var q := Vector2i(floori((c.x + d3.x * rr) / cw), floori((c.y + d3.y * rr) / cw))
			if not ins.has(q):
				var dd: float = ((Vector2(q) + Vector2(0.5, 0.5)) * cw).distance_to(c)
				if dd >= r - 4.0 and dd <= r + 36.0:
					ins[q] = true
			rr += cw * 0.5
	wv._zc_key = key
	wv._zc_val = g.map.mire_cells(ins) if not ins.is_empty() else []
	return wv._zc_val


## 下一圈预告（虚线）
static func _zone_next_ring(wv: W) -> void:
	var g: Game = wv.g
	if g.zone_state == 1:
		var n2 := 72
		for i in n2:
			if i % 2 == 0:
				continue
			var a0 := TAU * i / n2
			var a1 := TAU * (i + 1) / n2
			g.wcv.draw_line(g.zone_next_c + Vector2.from_angle(a0) * g.zone_next_r, g.zone_next_c + Vector2.from_angle(a1) * g.zone_next_r, Color(2.2, 2.2, 2.4, 0.6), 2.0)


static func draw_zone_band(wv: W, pulse: float) -> void:
	var g: Game = wv.g
	var r: float = g.zone_r
	var c: Vector2 = g.zone_c
	var vc: Vector2 = g.cam.position
	var view: float = g.view_size().length() * 0.6 + 80.0
	var n: int = clampi(int(TAU * r / W.ZB_SEG), 64, 420)
	var t: float = g.t
	var crest := PackedVector2Array()
	var crests: Array = []           # 内沿线段先收集，等溟痕贴图铺完再画在最上面
	var prev_in := Vector2.ZERO
	var prev_mid := Vector2.ZERO
	var prev_out := Vector2.ZERO
	var prev_vis := false
	# 溟痕配色（2026-09-27 用户要求：圈边要是溟痕本身的样子——深色黏液 + 青黑纹理，和地上的溟痕一致；不再用粉紫潮线）
	# 10-24 用户「直接改溟痕颜色」（docs/139 §6.4 方案 A）：带色、贴图块与地上溟痕同乘 render/mire_tint，靛紫 → 深海青蓝
	var mtn: Color = g.map.mire_tint()
	var c_in := Color(0.06, 0.03, 0.1, 0.92) * mtn
	var c_mid := Color(0.05, 0.03, 0.08, 0.8) * mtn
	var c_out := Color(0.05, 0.02, 0.08, 0.0) * mtn
	# 性能（测试与验收 9/30：黑潮每帧 2.3 毫秒）：只遍历镜头附近那段圆弧的序号（原来整圈 420 段、贴图 900 块逐个算三角函数再判可见）
	var rng_i: Vector2i = _arc_range(wv, n, c, r, vc, view)
	var run_mid := PackedVector2Array()
	var run_out := PackedVector2Array()
	if rng_i.y < rng_i.x:
		return
	var tab: Array = _zone_tab(wv, n)
	var za: PackedFloat64Array = tab[0]
	var zd: PackedVector2Array = tab[1]
	for i in range(rng_i.x, rng_i.y + 1):
		var im: int = posmod(i, n)
		var a: float = za[im]
		var d: Vector2 = zd[im]
		# 内沿潮头：两层正弦叠加并随时间流动；外沿更慢、更宽
		var rin: float = r - 6.0 + 5.0 * sin(a * 23.0 + t * 1.3) + 1.5 * sin(a * 57.0 - t * 2.1)
		var rmid: float = r + 12.0 + 4.0 * sin(a * 31.0 - t * 0.9)
		var rout: float = r + 44.0 + 10.0 * sin(a * 13.0 + t * 0.6) + 5.0 * sin(a * 41.0 - t * 1.4)
		var pin: Vector2 = c + d * rin
		var pmid: Vector2 = c + d * rmid
		var pout: Vector2 = c + d * rout
		var vis: bool = pin.distance_to(vc) < view
		if i > rng_i.x and (vis or prev_vis):
			# 连续可见的一段收集成三条边线，整段画成两个多边形（原来每小段两次 draw_polygon，一屏约 400 次）
			if crest.is_empty():
				crest.append(prev_in)
				run_mid.append(prev_mid)
				run_out.append(prev_out)
			crest.append(pin)
			run_mid.append(pmid)
			run_out.append(pout)
		elif crest.size() > 1:
			_zone_strips(wv, crest, run_mid, run_out, c_in, c_mid, c_out)
			crests.append(crest)
			crest = PackedVector2Array()
			run_mid = PackedVector2Array()
			run_out = PackedVector2Array()
		prev_in = pin
		prev_mid = pmid
		prev_out = pout
		prev_vis = vis
	if crest.size() > 1:
		_zone_strips(wv, crest, run_mid, run_out, c_in, c_mid, c_out)
		crests.append(crest)
	# 溟痕贴图沿圈边密铺：每 26 像素弧长一块（贴图约 60 像素宽，互相叠一半以上，连成一整条），两帧脉动和地上的溟痕一致；
	# 大小、左右翻转、前后位置按序号取固定的伪随机，看不出重复；只画视野内的块（后期同屏元素多，一屏约五六十块）
	# 溟痕 v2（world_spec_1024）：圈边改用同一套 1:1 平铺 + 围边——环带 [r − 4, r + 36]（世界单位）按溟痕格栅格化，只取镜头附近那段弧
	var mt: Texture2D = null if g.map.mire_v2 else g.tex.get("terrain_mire")
	if g.map.mire_v2:
		var cw: float = g.map.MIRE_CELL * Game.PX
		var nb2: int = clampi(int(TAU * r / (cw * 0.5)), 24, 4000)
		var rj: Vector2i = _arc_range(wv, nb2, c, r, vc, view)
		if rj.y >= rj.x:
			var zc: Array = _zone_cells(wv, c, r, cw, nb2, rj)
			if not zc.is_empty():
				g.map.draw_mire_cells(zc, int(t * 2.0) % 2, Color(1, 1, 1, 0.95))
	if mt != null:
		var fw: int = mt.get_width() / 2
		var nb: int = clampi(int(TAU * r / 26.0), 24, 900)
		var rng_j: Vector2i = _arc_range(wv, nb, c, r, vc, view)
		for jr in range(rng_j.x - 1, rng_j.y + 2):
			if rng_j.y < rng_j.x:
				break
			var j: int = posmod(jr, nb)
			var d2: Vector2
			var bp: Vector2
			var bs: float
			var fl: bool
			# 每块的方向 / 径向偏移 / 大小 / 翻转只跟序号走：按块数缓存（同一算式，逐位相同），每帧只算位置
			var bt: Array = _zone_btab(wv, nb)
			d2 = bt[0][j]
			bp = c + d2 * (r + 12.0 + bt[1][j])
			if bp.distance_to(vc) > view:
				continue
			bs = bt[2][j]
			fl = bt[3][j] != 0
			var sz := Vector2(bs, bs)
			var fr: int = (int(t * 2.0) + j) % 2
			if fl:
				g.wcv.draw_set_transform(bp, 0.0, Vector2(-1, 1))
				g.wcv.draw_texture_rect_region(mt, Rect2(-sz / 2.0, sz), Rect2(fw * fr, 0, fw, mt.get_height()), Color(1, 1, 1, 0.95) * mtn)
				g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			else:
				g.wcv.draw_texture_rect_region(mt, Rect2(bp - sz / 2.0, sz), Rect2(fw * fr, 0, fw, mt.get_height()), Color(1, 1, 1, 0.95) * mtn)
	for cr in crests:
		_zone_crest(wv, cr, pulse)


static func _zone_dark_fast(wv: W, seg: int, far: float, outer: float) -> void:
	var g: Game = wv.g
	var dirs = wv._zdark_dirs.get(seg)
	if dirs == null:
		dirs = PackedVector2Array()
		for i in seg + 1:
			dirs.append(Vector2.from_angle(TAU * i / seg))
		wv._zdark_dirs[seg] = dirs
	var zc: Vector2 = g.zone_c
	var zr: float = g.zone_r
	var pp: Vector2 = g.ppos
	var P: PackedVector2Array = Transform2D(Vector2(zr, 0.0), Vector2(0.0, zr), zc) * dirs
	var Q: PackedVector2Array = Transform2D(Vector2(outer, 0.0), Vector2(0.0, outer), zc) * dirs
	var inside: bool = pp.distance_to(zc) < zr
	var lim: float = far + 400.0
	var out := PackedVector2Array()
	out.resize(seg * 6)
	var k := 0
	var far0: bool = P[0].distance_to(pp) > lim
	for i in seg:
		var far1: bool = P[i + 1].distance_to(pp) > lim
		if inside and far0 and far1:
			far0 = far1
			continue
		far0 = far1
		var p0: Vector2 = P[i]
		var q1: Vector2 = Q[i + 1]
		out[k] = p0
		out[k + 1] = P[i + 1]
		out[k + 2] = q1
		out[k + 3] = p0
		out[k + 4] = q1
		out[k + 5] = Q[i]
		k += 6
	if k == 0:
		return
	out.resize(k)
	wv.tb_flush()
	var cs := PackedColorArray()
	cs.resize(k)
	# docs/139 §6 试验旋钮 render/zone_dark_r / _g / _b：黑潮圈外压暗色（缺省原值紫 0.16, 0.03, 0.22）
	cs.fill(Color(Bal.v("render/zone_dark_r", 0.03), Bal.v("render/zone_dark_g", 0.08), Bal.v("render/zone_dark_b", 0.12), 0.55))
	RenderingServer.canvas_item_add_triangle_array(g.get_canvas_item(), PackedInt32Array(), out, cs)


static func _zone_tab(wv: W, n: int) -> Array:
	var t = wv._zone_tabs.get(n)
	if t == null:
		var aa := PackedFloat64Array()
		var dd := PackedVector2Array()
		for i in n:
			var a: float = TAU * i / n
			aa.append(a)
			dd.append(Vector2.from_angle(a))
		t = [aa, dd]
		if wv._zone_tabs.size() > 64:
			wv._zone_tabs.clear()
		wv._zone_tabs[n] = t
	return t


static func _zone_btab(wv: W, nb: int) -> Array:
	var t = wv._zone_btabs.get(nb)
	if t == null:
		var dd := PackedVector2Array()
		var ro := PackedFloat64Array()
		var bs := PackedFloat64Array()
		var fl := PackedByteArray()
		for j in nb:
			var a2: float = TAU * (j + 0.5 * sin(j * 12.9898)) / nb
			dd.append(Vector2.from_angle(a2))
			ro.append(7.0 * sin(j * 4.1))
			bs.append(56.0 * (0.85 + 0.25 * (0.5 + 0.5 * sin(j * 7.3))))
			fl.append(1 if int(j * 2654435761) % 2 == 0 else 0)
		t = [dd, ro, bs, fl]
		if wv._zone_btabs.size() > 64:
			wv._zone_btabs.clear()
		wv._zone_btabs[nb] = t
	return t


static func _zone_strips(wv: W, pin: PackedVector2Array, pmid: PackedVector2Array, pout: PackedVector2Array, c_in: Color, c_mid: Color, c_out: Color) -> void:
	var g: Game = wv.g
	var m: int = pin.size()
	var t = wv._band_idx.get(m)
	if t == null:
		var ix := PackedInt32Array()
		ix.resize((m - 1) * 12)
		var k := 0
		for band in 2:   # 先整条内带（内沿→中线），再整条外带（中线→外沿），同原来两个多边形的先后
			var a0: int = band * m
			var b0: int = a0 + m
			for q in m - 1:
				ix[k] = a0 + q
				ix[k + 1] = a0 + q + 1
				ix[k + 2] = b0 + q + 1
				ix[k + 3] = a0 + q
				ix[k + 4] = b0 + q + 1
				ix[k + 5] = b0 + q
				k += 6
		var cs := PackedColorArray()
		cs.resize(m * 3)
		for q in m:
			cs[q] = c_in
			cs[m + q] = c_mid
			cs[2 * m + q] = c_out
		t = [ix, cs]
		if wv._band_idx.size() > 64:
			wv._band_idx.clear()
		wv._band_idx[m] = t
	var pts := PackedVector2Array(pin)
	pts.append_array(pmid)
	pts.append_array(pout)
	RenderingServer.canvas_item_add_triangle_array(g.get_canvas_item(), t[0], pts, t[1])


## 圆周分成 n 段时，镜头 vc（半径 view）附近那段弧的序号范围 [x, y]（y 可以超过 n，调用方取模）；整圈都要画时返回 [0, n]，
## 看不到任何一段时返回 y < x
static func _arc_range(wv: W, n: int, c: Vector2, r: float, vc: Vector2, view: float) -> Vector2i:
	var dc: float = vc.distance_to(c)
	if absf(dc - r) > view + 60.0:
		return Vector2i(0, -1)
	if r < 1.0 or dc < 1.0 or view + 60.0 >= r:
		return Vector2i(0, n)
	var half: float = minf(PI, asin(clampf((view + 60.0) / r, 0.0, 1.0)) * 1.3)
	var a0: float = fposmod((vc - c).angle(), TAU)
	var i0: int = floori((a0 - half) / TAU * n) - 1
	var i1: int = ceili((a0 + half) / TAU * n) + 1
	if i1 - i0 >= n:
		return Vector2i(0, n)
	return Vector2i(i0, i1)


## 溟痕内沿：暗色描边垫底 + 溟痕裂纹的青色细线（安全区边界一眼看清，颜色取自溟痕贴图的青色裂纹）
static func _zone_crest(wv: W, pts: PackedVector2Array, pulse: float) -> void:
	var g: Game = wv.g
	g.wcv.draw_polyline(pts, Color(0.02, 0.0, 0.04, 0.75), 5.0)
	g.wcv.draw_polyline(pts, Color(0.35, 0.95, 0.95, 0.55 + 0.25 * pulse), 2.0)
