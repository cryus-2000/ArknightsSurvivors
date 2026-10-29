extends RefCounted
## 无贴图图元批（引擎同款几何，docs/50 §13）：draw_circle / draw_arc / draw_line / draw_rect / draw_polyline / draw_colored_polygon
## 在 GL 兼容渲染器里各算一次绘制调用（多边形不合批；线 / 矩形只和同类连着时才合批），中间夹着贴图时更是一笔一断。
## 这里按 Godot 4.7 源码（scene/main/canvas_item.cpp、servers/rendering/renderer_canvas_cull.cpp 非抗锯齿分支）生成同样的三角形：
##   圆 / 椭圆 —— 64 段扇形；弧 / 折线 —— 同一套斜接（miter）三角带；粗线 —— 同一个四边形；矩形 —— 同一个四边形。
## 攒成一个无索引三角形数组，flush 时一次 canvas_item_add_triangle_array 提交，同序画出的覆盖范围与原调用相同（只差浮点舍入）。
## xf：相当于 draw_set_transform 的变换（先变换再提交，提交时画布变换须为单位矩阵）

const SEG := 64   # 引擎 canvas_item_add_ellipse 的段数

static var _fan := PackedVector2Array()   # 64 段单位扇形（三角形列表，192 顶点）
static var _ring_cache := {}              # Vector4(段数, 半径, 线宽, 张角) -> 弧的三角形列表（圆心为原点、起始角 0）
static var _cols := {}                    # 顶点数 -> 填色用的临时数组（fill 后整段追加）

var pts := PackedVector2Array()
var cols := PackedColorArray()


static func _fan_table() -> void:
	for i in SEG:
		var a0: float = i * (TAU / SEG)
		var a1: float = (i + 1) * (TAU / SEG)
		_fan.append_array([Vector2.ZERO, Vector2(cos(a0), sin(a0)), Vector2(cos(a1), sin(a1))])


func _fill(n: int, col: Color) -> void:
	var c: PackedColorArray = _cols.get(n, PackedColorArray())
	if c.size() != n:
		c.resize(n)
		_cols[n] = c
	c.fill(col)
	cols.append_array(c)


func is_empty() -> bool:
	return pts.is_empty()


## draw_circle(c, r, col)（实心）；sy：纵向压缩（地面椭圆，等同 draw_set_transform 的 (1, sy) 缩放）
func circle(c: Vector2, r: float, col: Color, xf := Transform2D.IDENTITY) -> void:
	if _fan.is_empty():
		_fan_table()
	pts.append_array(xf * Transform2D(Vector2(r, 0.0), Vector2(0.0, r), c) * _fan)
	_fill(SEG * 3, col)


## draw_rect(r, col)（实心）
func rect(r: Rect2, col: Color, xf := Transform2D.IDENTITY) -> void:
	var a := r.position
	var b := r.end
	if xf == Transform2D.IDENTITY:
		pts.append_array([a, Vector2(b.x, a.y), b, a, b, Vector2(a.x, b.y)])
	else:
		pts.append_array(xf * PackedVector2Array([a, Vector2(b.x, a.y), b, a, b, Vector2(a.x, b.y)]))
	_fill(6, col)


## draw_line(a, b, col, w)（w ≥ 0；w < 0 是引擎的细线图元，不走这里）。引擎的粗线是「四点图元」，顶点色按半精度存，
## 这里先把颜色量化成半精度再进批，画出来逐像素相同（不量化时个别像素差最低一级）
func line(a: Vector2, b: Vector2, col: Color, w: float, xf := Transform2D.IDENTITY) -> void:
	var t: Vector2 = (a - b).orthogonal().normalized() * w * 0.5
	var q := PackedVector2Array([a + t, a - t, b - t, a + t, b - t, b + t])
	pts.append_array(q if xf == Transform2D.IDENTITY else xf * q)
	_fill(6, half(col))


static var _hbuf := PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0])

## 颜色按半精度量化（同引擎图元顶点色的存法）
static func half(c: Color) -> Color:
	_hbuf.encode_half(0, c.r)
	_hbuf.encode_half(2, c.g)
	_hbuf.encode_half(4, c.b)
	_hbuf.encode_half(6, c.a)
	return Color(_hbuf.decode_half(0), _hbuf.decode_half(2), _hbuf.decode_half(4), _hbuf.decode_half(6))


## draw_rect(r, col, false, w)（空心）：线宽不小于边长时是外扩的实心矩形，否则是闭合折线（斜接三角带）；折线几何按矩形缓存
static var _rl_cache := {}

func rect_line(r: Rect2, col: Color, w: float, xf := Transform2D.IDENTITY) -> void:
	var ra := r.abs()
	if w >= ra.size.x or w >= ra.size.y:
		rect(ra.grow(0.5 * w), col, xf)
		return
	var byw = _rl_cache.get(w)
	if byw == null:
		byw = {}
		_rl_cache[w] = byw
	var q = byw.get(ra)
	if q == null:
		if byw.size() > 256:
			byw.clear()
		q = strip_tris(PackedVector2Array([ra.position, ra.position + Vector2(ra.size.x, 0), ra.end, ra.position + Vector2(0, ra.size.y), ra.position]), w)
		byw[ra] = q
	pts.append_array(q if xf == Transform2D.IDENTITY else xf * q)
	_fill(q.size(), col)


## draw_colored_polygon(p, col)：引擎先三角化（Geometry2D.triangulate_polygon），这里同样三角化
func polygon(p: PackedVector2Array, col: Color, xf := Transform2D.IDENTITY) -> void:
	var idx: PackedInt32Array = Geometry2D.triangulate_polygon(p)
	if idx.is_empty():
		return
	var q := PackedVector2Array()
	q.resize(idx.size())
	for i in idx.size():
		q[i] = p[idx[i]]
	pts.append_array(q if xf == Transform2D.IDENTITY else xf * q)
	_fill(q.size(), col)


## draw_polygon(p, cs)（逐顶点颜色）：同样三角化
func polygon_colors(p: PackedVector2Array, cs: PackedColorArray, xf := Transform2D.IDENTITY) -> void:
	var idx: PackedInt32Array = Geometry2D.triangulate_polygon(p)
	if idx.is_empty():
		return
	var q := PackedVector2Array()
	var qc := PackedColorArray()
	q.resize(idx.size())
	qc.resize(idx.size())
	for i in idx.size():
		q[i] = p[idx[i]]
		qc[i] = cs[idx[i]]
	pts.append_array(q if xf == Transform2D.IDENTITY else xf * q)
	cols.append_array(qc)


## draw_polyline(p, col, w)（w ≥ 0，非抗锯齿）：同引擎的斜接三角带
func polyline(p: PackedVector2Array, col: Color, w: float, xf := Transform2D.IDENTITY) -> void:
	var q := strip_tris(p, w)
	if q.is_empty():
		return
	pts.append_array(q if xf == Transform2D.IDENTITY else xf * q)
	_fill(q.size(), col)


## draw_arc(c, r, a0, a1, n, col, w)：同 draw_ellipse_arc 取点 + 折线。几何按 (段数, 半径, 线宽, 张角) 缓存成以圆心为原点、
## 起始角 0 的模板，用时旋转到 a0 再平移（同一组点，只差浮点舍入）；整圈的模板用斜接的闭式解直接算（每点沿半径偏 w/2 ÷ cos(Δ/2)）
func arc(c: Vector2, r: float, a0: float, a1: float, n: int, col: Color, w: float, xf := Transform2D.IDENTITY) -> void:
	var span: float = clampf(a1 - a0, -TAU, TAU)
	var key := Vector4(n, r, w, span)
	var hit = _ring_cache.get(key)
	if hit == null:
		if _ring_cache.size() > 512:
			_ring_cache.clear()
		hit = _ring_tris(r, w, n) if span == TAU else strip_tris(arc_points(Vector2.ZERO, r, 0.0, span, n), w)
		_ring_cache[key] = hit
	if hit.is_empty():
		return
	pts.append_array(xf * Transform2D(a0, c) * hit)
	_fill(hit.size(), col)


static var _dirs := {}   # 段数 -> 整圈单位方向（同 arc_points 的角度）

## 整圈（首尾重合，引擎按闭合折线处理）：每点的斜接方向都沿半径，长度 1 / cos(Δ / 2)，Δ = TAU / (n - 1)
static func _ring_tris(r: float, w: float, n: int) -> PackedVector2Array:
	var d: PackedVector2Array = _dirs.get(n, PackedVector2Array())
	if d.is_empty():
		d = arc_points(Vector2.ZERO, 1.0, 0.0, TAU, n)
		_dirs[n] = d
	var h: float = w * 0.5 / cos(PI / (n - 1))
	var o: PackedVector2Array = Transform2D(Vector2(r + h, 0.0), Vector2(0.0, r + h), Vector2.ZERO) * d
	var i: PackedVector2Array = Transform2D(Vector2(r - h, 0.0), Vector2(0.0, r - h), Vector2.ZERO) * d
	var out := PackedVector2Array()
	out.resize((n - 1) * 6)
	for k in n - 1:
		var b: int = k * 6
		out[b] = o[k]
		out[b + 1] = i[k]
		out[b + 2] = o[k + 1]
		out[b + 3] = i[k]
		out[b + 4] = o[k + 1]
		out[b + 5] = i[k + 1]
	return out


## ---- 照旧几何（docs/101 B4 ③）：原 world.tb_*（带索引、段数少的圆 / 环 / 弧）的顶点算式与三角形次序逐字照搬，
## 这里展开成无索引三角形（同样的三角形、同样的先后，画出来逐像素相同）。world.tb_* 现在只是转发；表驱动的快路径（_gt_ / _afx_）用 tris 原样追加

static var _qdirs := {}   # 段数 -> 单位方向表 Vector2.from_angle(q × TAU / 段数)
static var _qcs := {}     # 段数 -> [cos(q × TAU / 段数), sin(…)] 交错存（float64，与现算逐位相同）


## 已按三角形展开的顶点 / 顶点色原样追加（表驱动的快路径用）
func tris(p: PackedVector2Array, c: PackedColorArray) -> void:
	pts.append_array(p)
	cols.append_array(c)


## 模板缓存（docs/50 §24，10-30）：circle_n / ring_n 每个顶点一次 GDScript 循环（圆 10–14 段约 10–14 µs、环 16 段约 20 µs），
## 敌弹 / 光环这类「同一尺寸每帧画几十上百个」的调用占了弹幕战的大头。按 (段数, 半径, 纵压 / 线宽) 缓存以原点为圆心的三角形列表，
## 用时 Transform2D(0, c) * 模板（引擎原生，一次调用）整段平移后追加。模板里每个顶点的算式与原循环逐项相同（先算相对偏移、再加圆心，
## 平移那一步 x × 1 + y × 0 + c 也无舍入），所以顶点逐位相同。
## 动态尺寸（每帧都不同的半径）不进缓存：同一键第二次出现才建模板（第一次只记「见过」），缓存满 256 项整表清空
static var _ccache := {}   # Vector3(段数, 半径, 纵压) -> PackedVector2Array（seg × 3）
static var _rcache := {}   # Vector3(段数, 半径, 线宽) -> PackedVector2Array（seg × 6）
static var _cseen := {}    # 同键第一次出现的记号（超过 512 项清空）
const _TPL_CAP := 256


## 原 tb_circle：seg 段扇形实心圆，sy 纵向压缩；第 q 个三角形 = 圆心、第 q 点、第 q+1 点
func circle_n(c: Vector2, r: float, col: Color, sy := 1.0, seg := 14) -> void:
	var key := Vector3(seg, r, sy)
	var tpl = _ccache.get(key)
	if tpl != null:
		pts.append_array(Transform2D(0.0, c) * tpl)
		_fill(seg * 3, col)
		return
	if _cseen.has(key):
		if _ccache.size() >= _TPL_CAP:
			_ccache.clear()
		_ccache[key] = _circle_tpl(r, sy, seg)
		pts.append_array(Transform2D(0.0, c) * _ccache[key])
		_fill(seg * 3, col)
		return
	if _cseen.size() > 512:
		_cseen.clear()
	_cseen[key] = true
	_circle_direct(c, r, col, sy, seg)


func _circle_tpl(r: float, sy: float, seg: int) -> PackedVector2Array:
	var cs = _qcs.get(seg)
	if cs == null:
		var nc := PackedFloat64Array()
		for q in seg:
			var aq: float = q * TAU / seg
			nc.append(cos(aq))
			nc.append(sin(aq))
		_qcs[seg] = nc
		cs = nc
	var out := PackedVector2Array()
	out.resize(seg * 3)
	var p0 := Vector2(cs[0] * r, cs[1] * r * sy)
	var prev := p0
	for q in seg:
		var nxt: Vector2 = p0 if q == seg - 1 else Vector2(cs[2 * q + 2] * r, cs[2 * q + 3] * r * sy)
		var k: int = q * 3
		out[k] = Vector2.ZERO
		out[k + 1] = prev
		out[k + 2] = nxt
		prev = nxt
	return out


func _circle_direct(c: Vector2, r: float, col: Color, sy: float, seg: int) -> void:
	var cs = _qcs.get(seg)
	if cs == null:
		var nc := PackedFloat64Array()
		for q in seg:
			var aq: float = q * TAU / seg
			nc.append(cos(aq))
			nc.append(sin(aq))
		_qcs[seg] = nc
		cs = nc
	var base: int = pts.size()
	pts.resize(base + seg * 3)
	var p0 := c + Vector2(cs[0] * r, cs[1] * r * sy)
	var prev := p0
	for q in seg:
		var nxt: Vector2 = p0 if q == seg - 1 else c + Vector2(cs[2 * q + 2] * r, cs[2 * q + 3] * r * sy)
		var k: int = base + q * 3
		pts[k] = c
		pts[k + 1] = prev
		pts[k + 2] = nxt
		prev = nxt
	_fill(seg * 3, col)


## 原 tb_ring：seg 段圆环（线宽 w 跨在半径 r 两侧）；第 q 段 = (内q 外q 外q+1)、(内q 外q+1 内q+1)
func ring_n(c: Vector2, r: float, w: float, col: Color, seg := 16) -> void:
	var key := Vector3(seg, r, w)
	var tpl = _rcache.get(key)
	if tpl != null:
		pts.append_array(Transform2D(0.0, c) * tpl)
		_fill(seg * 6, col)
		return
	if _cseen.has(key):
		if _rcache.size() >= _TPL_CAP:
			_rcache.clear()
		_rcache[key] = _ring_tpl(r, w, seg)
		pts.append_array(Transform2D(0.0, c) * _rcache[key])
		_fill(seg * 6, col)
		return
	if _cseen.size() > 512:
		_cseen.clear()
	_cseen[key] = true
	_ring_direct(c, r, w, col, seg)


func _ring_tpl(r: float, w: float, seg: int) -> PackedVector2Array:
	var dirs = _qdirs.get(seg)
	if dirs == null:
		var nd := PackedVector2Array()
		for q in seg:
			nd.append(Vector2.from_angle(q * TAU / seg))
		_qdirs[seg] = nd
		dirs = nd
	var out := PackedVector2Array()
	out.resize(seg * 6)
	var d0: Vector2 = dirs[0]
	var i0 := d0 * (r - w * 0.5)
	var o0 := d0 * (r + w * 0.5)
	var pi := i0
	var po := o0
	for q in seg:
		var ni: Vector2 = i0
		var no: Vector2 = o0
		if q < seg - 1:
			var d: Vector2 = dirs[q + 1]
			ni = d * (r - w * 0.5)
			no = d * (r + w * 0.5)
		var k: int = q * 6
		out[k] = pi
		out[k + 1] = po
		out[k + 2] = no
		out[k + 3] = pi
		out[k + 4] = no
		out[k + 5] = ni
		pi = ni
		po = no
	return out


func _ring_direct(c: Vector2, r: float, w: float, col: Color, seg: int) -> void:
	var dirs = _qdirs.get(seg)
	if dirs == null:
		var nd := PackedVector2Array()
		for q in seg:
			nd.append(Vector2.from_angle(q * TAU / seg))
		_qdirs[seg] = nd
		dirs = nd
	var base: int = pts.size()
	pts.resize(base + seg * 6)
	var d0: Vector2 = dirs[0]
	var i0 := c + d0 * (r - w * 0.5)
	var o0 := c + d0 * (r + w * 0.5)
	var pi := i0
	var po := o0
	for q in seg:
		var ni: Vector2 = i0
		var no: Vector2 = o0
		if q < seg - 1:
			var d: Vector2 = dirs[q + 1]
			ni = c + d * (r - w * 0.5)
			no = c + d * (r + w * 0.5)
		var k: int = base + q * 6
		pts[k] = pi
		pts[k + 1] = po
		pts[k + 2] = no
		pts[k + 3] = pi
		pts[k + 4] = no
		pts[k + 5] = ni
		pi = ni
		po = no
	_fill(seg * 6, col)


## 原 tb_ring2：径向渐变圆环（内圈 r0 颜色 c0 → 外圈 r1 颜色 c1）
func ring2(c: Vector2, r0: float, r1: float, c0: Color, c1: Color, seg := 48) -> void:
	var ri := PackedVector2Array()
	var ro := PackedVector2Array()
	ri.resize(seg)
	ro.resize(seg)
	for q in seg:
		var d := Vector2.from_angle(q * TAU / seg)
		ri[q] = c + d * r0
		ro[q] = c + d * r1
	for q in seg:
		var q1: int = (q + 1) % seg
		pts.append_array([ri[q], ro[q], ro[q1], ri[q], ro[q1], ri[q1]])
		cols.append_array([c0, c1, c1, c0, c1, c0])


## 原 tb_quad：四边形 p0 p1 p2 p3 = 三角形 (p0 p1 p2)、(p0 p2 p3)
func quad(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, col: Color) -> void:
	pts.append_array([p0, p1, p2, p0, p2, p3])
	_fill(6, col)


## 原 tb_line：粗线 = 沿法线外扩 w / 2 的四边形（不量化颜色；引擎同款粗线用 line）
func line_q(a: Vector2, b: Vector2, col: Color, w := 1.0) -> void:
	var n: Vector2 = (b - a).orthogonal().normalized() * w * 0.5
	quad(a + n, b + n, b - n, a - n, col)


## 原 tb_arc：seg 段弧带（a0 → a1，线宽 w，sy 纵向压缩）；第 q 段 = (内q 外q 外q+1)、(内q 外q+1 内q+1)
func arc_q(c: Vector2, r: float, a0: float, a1: float, w: float, col: Color, seg := 8, sy := 1.0) -> void:
	var base: int = pts.size()
	pts.resize(base + seg * 6)
	var pi := Vector2.ZERO
	var po := Vector2.ZERO
	for q in seg + 1:
		var aq: float = lerpf(a0, a1, float(q) / seg)
		var d := Vector2(cos(aq), sin(aq))
		var ni := c + Vector2(d.x * (r - w * 0.5), d.y * (r - w * 0.5) * sy)
		var no := c + Vector2(d.x * (r + w * 0.5), d.y * (r + w * 0.5) * sy)
		if q > 0:
			var k: int = base + (q - 1) * 6
			pts[k] = pi
			pts[k + 1] = po
			pts[k + 2] = no
			pts[k + 3] = pi
			pts[k + 4] = no
			pts[k + 5] = ni
		pi = ni
		po = no
	_fill(seg * 6, col)


## 原 tb_poly：凸多边形按第 0 点扇形三角化
func fan(p: PackedVector2Array, col: Color) -> void:
	var n: int = p.size()
	if n < 3:
		return
	for q in range(1, n - 1):
		pts.append_array([p[0], p[q], p[q + 1]])
	_fill((n - 2) * 3, col)


func flush(ci: CanvasItem) -> void:
	if pts.is_empty():
		return
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), PackedInt32Array(), pts, cols)
	pts = PackedVector2Array()
	cols = PackedColorArray()


## CanvasItem.draw_ellipse_arc 的取点
static func arc_points(c: Vector2, r: float, a0: float, a1: float, n: int) -> PackedVector2Array:
	var p := PackedVector2Array()
	p.resize(n)
	var da: float = clampf(a1 - a0, -TAU, TAU)
	for i in n:
		var th: float = (i / (n - 1.0)) * da + a0
		p[i] = c + Vector2(r * cos(th), r * sin(th))
	return p


## renderer_canvas_cull.cpp canvas_item_add_polyline（非抗锯齿）：每点沿斜接方向左右各偏 w/2，三角带展开成三角形列表
static func strip_tris(p: PackedVector2Array, w: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n: int = p.size()
	if n < 2:
		return out
	var loop: bool = p[0].is_equal_approx(p[n - 1])
	var first := Vector2.ZERO
	var last := Vector2.ZERO
	for i in range(1, n):
		first = (p[i] - p[i - 1]).normalized()
		if not first.is_zero_approx():
			break
	for i in range(n - 1, 0, -1):
		last = (p[i] - p[i - 1]).normalized()
		if not last.is_zero_approx():
			break
	var s := PackedVector2Array()
	s.resize(n * 2)
	var prev := Vector2.ZERO
	var hw: float = w * 0.5
	for i in n:
		var seg: Vector2
		if i == n - 1:
			seg = prev
		else:
			seg = (p[i + 1] - p[i]).normalized()
			if seg.is_zero_approx():
				seg = prev
		if i == 0 and loop:
			prev = last
		elif i == n - 1 and loop:
			prev = first
		var off: Vector2
		if i == 0 and not loop:
			off = first.orthogonal()
		elif i == n - 1 and not loop:
			off = last.orthogonal()
		else:
			off = _miter(seg, prev)
		off *= hw
		s[i * 2] = p[i] + off
		s[i * 2 + 1] = p[i] - off
		prev = seg
	out.resize((n - 1) * 6)
	for k in n - 1:
		var b: int = k * 2
		out[k * 6] = s[b]
		out[k * 6 + 1] = s[b + 1]
		out[k * 6 + 2] = s[b + 2]
		out[k * 6 + 3] = s[b + 1]
		out[k * 6 + 4] = s[b + 2]
		out[k * 6 + 5] = s[b + 3]
	return out


## compute_polyline_edge_offset_clamped
static func _miter(seg: Vector2, prev: Vector2) -> Vector2:
	var length := 1.0
	var bis: Vector2 = (prev * seg.length() - seg * prev.length()).normalized()
	var ang: float = atan2(bis.cross(prev), bis.dot(prev))
	var sa: float = sin(ang)
	if not is_zero_approx(sa) and not seg.is_equal_approx(prev):
		length = clampf(1.0 / sa, -3.0, 3.0)
	else:
		bis = seg.orthogonal()
	if bis.is_zero_approx():
		bis = seg.orthogonal()
	return bis * length
