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


static var _seen := {}   # 见过一次、还没缓存的弧

## 这一段弧值得走三角形批：几何已缓存，或者上一帧也画过同样的弧（半径不变的预警圈等，第二次起现算一次、之后命中缓存）。
## 逐帧变半径的大环（进度环、收缩圈）每帧都是新键，返回 false，调用方退回引擎画法，免得每帧在脚本里现算
static func want_arc(n: int, r: float, w: float, span: float) -> bool:
	var key := Vector4(n, r, w, clampf(span, -TAU, TAU))
	if _ring_cache.has(key) or _seen.has(key):
		return true
	if _seen.size() > 1024:
		_seen.clear()
	_seen[key] = true
	return false


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
