extends RefCounted
## 干员绘制合批（性能 9/30，协调人派活）：干员脚本里的 g.draw_* 都经这里（character.cv）。
## 平时直接转给 g（逐条画，和原来一样）；squad 在「地面实体」「技能上层」两个绘制阶段 begin() / end() 之间开启合批：
## 圆 / 弧 / 线 / 折线 / 单色多边形 / 矩形按当前 draw_set_transform 换算成世界坐标的三角形攒起来，一次
## canvas_item_add_triangle_array 提交（Godot 4 只合批贴图矩形，每个 draw_circle / draw_arc 都是一次绘制调用）。
## 层序：画贴图（draw_texture_rect_region、干员的 draw_spr / draw_sprite_at 等）之前先 flush，所以「底圈 → 贴图 → 盖圈」照旧叠放。
## 不同：批里没有抗锯齿（干员这里本来都没开）；宽度 ≤ 0 的细线按 1 像素画
var g
var active := false
var xf := Transform2D.IDENTITY    # 当前 draw_set_transform（合批时只记下，不下发）
var _gxf := Transform2D.IDENTITY  # 已经下发给 g 的变换
var _pts := PackedVector2Array()
var _cols := PackedColorArray()
var _off := -1
var mute := false   # --clutterdbg=nofriend 量测：干员特效阶段的绘制全部丢掉（代码照跑、随机数照抽），squad 设
var dsat := 0.0     # 队友特效去饱和（docs/139 §10，render/mate_desat；squad._op_dim 按干员设）：颜色往同亮度灰拉，0 = 不变
var amul := 1.0     # 后期降噪（render/declutter mate_k / lead_k）：squad 在干员特效阶段按「队友 / 主控」设的透明度系数，乘在每次绘制的颜色上；1 = 不变
## 合批写法（性能 docs/50 §14 OPT_CV；10-15 删掉逐点 _add 的旧写法，docs/101 S2）：批里是无索引三角形列表，圆 / 弧的顶点用单位方向表
## × Transform2D 整组生成（引擎原生运算，算式与逐点 _add 相同：c + d × r 再乘 xf，浮点结果逐位一致），不再每个顶点一次函数调用、
## 每个三角形一个临时数组。三角形与顶点色和旧写法相同、同序，只是不共用顶点
static var _fans := {}     # 段数 -> 单位扇形三角形表（圆心 + 第 q、q+1 个圆周点，角度算式同 draw_circle）
static var _adirs := {}    # 点数 -> 整圈弧（0 → TAU）的单位方向（算式同 _arc）
static var _rings := {}    # Vector3(点数, 内半径, 外半径) -> 整圈弧以原点为心的三角形表（c + 表 = 旧写法的 c + d × r）
static var _cbuf := {}     # 顶点数 -> 填色临时数组


## 降噪 / 主次分层：透明度乘 amul、颜色往同亮度灰拉 dsat（亮度按 Rec.709）
func _dim(c: Color) -> Color:
	if dsat > 0.0:
		var l: float = c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
		c = Color(lerpf(c.r, l, dsat), lerpf(c.g, l, dsat), lerpf(c.b, l, dsat), c.a)
	c.a *= amul
	return c


func _init(game) -> void:
	g = game


func begin() -> void:
	if _off < 0:
		_off = 1 if Cfg.dev_args().has("--nobatch") else 0   # 对照测量：--nobatch 关掉合批，逐条画（与改动前相同）
	active = _off == 0
	xf = Transform2D.IDENTITY
	_gxf = Transform2D.IDENTITY


func end() -> void:
	flush()
	if _gxf != Transform2D.IDENTITY:
		g.draw_set_transform_matrix(Transform2D.IDENTITY)
		_gxf = Transform2D.IDENTITY
	xf = Transform2D.IDENTITY
	active = false


## 把攒下的三角形提交（提交时画布变换回到单位矩阵：顶点已是世界坐标）
func flush() -> void:
	if _pts.is_empty():
		return
	if _gxf != Transform2D.IDENTITY:
		g.draw_set_transform_matrix(Transform2D.IDENTITY)
		_gxf = Transform2D.IDENTITY
	RenderingServer.canvas_item_add_triangle_array(g.get_canvas_item(), PackedInt32Array(), _pts, _cols)
	_pts = PackedVector2Array()
	_cols = PackedColorArray()


## 现成的顶点色三角形（程序漩涡 op_blocks.fx_vortex 等）：pts 按当前 draw_set_transform 换算后并进批；不在合批阶段时直接提交给 g
func add_tris(pts: PackedVector2Array, cols: PackedColorArray, idx: PackedInt32Array) -> void:
	if mute:
		return
	if amul < 1.0 or dsat > 0.0:
		cols = cols.duplicate()
		for i in cols.size():
			cols[i] = _dim(cols[i])
	if xf != Transform2D.IDENTITY:
		pts = xf * pts
	if not active:
		sync()
		if _gxf != Transform2D.IDENTITY:
			g.draw_set_transform_matrix(Transform2D.IDENTITY)
			_gxf = Transform2D.IDENTITY
		RenderingServer.canvas_item_add_triangle_array(g.get_canvas_item(), idx, pts, cols)
		return
	var n: int = idx.size()
	if n > 96:
		# 大块现成网格（程序漩涡等）逐个索引展开反而更慢：先交前面攒的，再把它原样单独提交（同序，画面相同，多一两次绘制调用）
		flush()
		if _gxf != Transform2D.IDENTITY:
			g.draw_set_transform_matrix(Transform2D.IDENTITY)
			_gxf = Transform2D.IDENTITY
		RenderingServer.canvas_item_add_triangle_array(g.get_canvas_item(), idx, pts, cols)
		return
	var q := PackedVector2Array()
	var qc := PackedColorArray()
	q.resize(n)
	qc.resize(n)
	for k in n:
		var i: int = idx[k]
		q[k] = pts[i]
		qc[k] = cols[i]
	_pts.append_array(q)
	_cols.append_array(qc)


## 直接往 g 上画之前：先提交几何，再把当前变换下发给 g（批外的贴图 / UI 画法与原来同样处在这个变换下）
func sync() -> void:
	flush()
	if _gxf != xf:
		g.draw_set_transform_matrix(xf)
		_gxf = xf


## 批外的画法（vfx.spr 等）可能自己改了 g 的变换（画完重置为单位矩阵）：记成「未知」，下次 flush / sync 一定重新下发
const _UNKNOWN := Transform2D(0.0, Vector2.ZERO, 0.0, Vector2(-1.0e9, -1.0e9))

func touch() -> void:
	_gxf = _UNKNOWN


# ---------------------------------------------------------------- CanvasItem 同名接口

func draw_set_transform(p: Vector2, rot := 0.0, sc := Vector2.ONE) -> void:
	if not active:
		g.draw_set_transform(p, rot, sc)
		return
	xf = Transform2D(rot, sc, 0.0, p)


func draw_texture_rect_region(tex: Texture2D, rect: Rect2, src: Rect2, mod := Color.WHITE, transpose := false, clip := true) -> void:
	if mute:
		return
	if amul < 1.0 or dsat > 0.0:
		mod = _dim(mod)
	if active:
		sync()
	g.draw_texture_rect_region(tex, rect, src, mod, transpose, clip)


func draw_circle(p: Vector2, r: float, col: Color, filled := true, width := -1.0, aa := false) -> void:
	if mute:
		return
	if amul < 1.0 or dsat > 0.0:
		col = _dim(col)
	if not active:
		g.draw_circle(p, r, col, filled, width, aa)
		return
	var seg: int = _seg(r)
	if not filled:
		_arc(p, r, 0.0, TAU, seg + 1, col, width)
		return
	var fan = _fans.get(seg)
	if fan == null:
		fan = _fan_table(seg)
	var loc: PackedVector2Array = Transform2D(Vector2(r, 0.0), Vector2(0.0, r), p) * fan
	_pts.append_array(loc if xf == Transform2D.IDENTITY else xf * loc)
	_fill(seg * 3, col)


func draw_arc(c: Vector2, r: float, a0: float, a1: float, n: int, col: Color, width := -1.0, aa := false) -> void:
	if mute:
		return
	if amul < 1.0 or dsat > 0.0:
		col = _dim(col)
	if not active:
		g.draw_arc(c, r, a0, a1, n, col, width, aa)
		return
	_arc(c, r, a0, a1, n, col, width)


func draw_line(a: Vector2, b: Vector2, col: Color, width := -1.0, aa := false) -> void:
	if mute:
		return
	if amul < 1.0 or dsat > 0.0:
		col = _dim(col)
	if not active:
		g.draw_line(a, b, col, width, aa)
		return
	_seg_quad(a, b, col, width)


func draw_polyline(points: PackedVector2Array, col: Color, width := -1.0, aa := false) -> void:
	if mute:
		return
	var unbatched: bool = width > 2.0 or col.a < 1.0   # 按原色判断进不进批（降噪的 amul 不改变合批与否）
	if amul < 1.0 or dsat > 0.0:
		col = _dim(col)
	if not active:
		g.draw_polyline(points, col, width, aa)
		return
	if unbatched:
		# 粗线 / 半透明折线不进批，交 Godot 画（折点的衔接与原来完全一样；测试与验收 9/30 查出推进之王破阵地裂变成方块链）
		sync()
		g.draw_polyline(points, col, width, aa)
		return
	_strip(points, col, width)


func draw_colored_polygon(points: PackedVector2Array, col: Color, uvs := PackedVector2Array(), tex: Texture2D = null) -> void:
	if mute:
		return
	if amul < 1.0 or dsat > 0.0:
		col = _dim(col)
	if not active or tex != null:
		if active:
			sync()
		g.draw_colored_polygon(points, col, uvs, tex)
		return
	var tri: PackedInt32Array = Geometry2D.triangulate_polygon(points)
	if tri.is_empty():
		return
	var q := PackedVector2Array()
	q.resize(tri.size())
	for k in tri.size():
		q[k] = points[tri[k]]
	_pts.append_array(q if xf == Transform2D.IDENTITY else xf * q)
	_fill(q.size(), col)


func draw_rect(rect: Rect2, col: Color, filled := true, width := -1.0, aa := false) -> void:
	if mute:
		return
	if amul < 1.0 or dsat > 0.0:
		col = _dim(col)
	if not active:
		g.draw_rect(rect, col, filled, width, aa)
		return
	var p0 := rect.position
	var p1 := rect.position + Vector2(rect.size.x, 0.0)
	var p2 := rect.end
	var p3 := rect.position + Vector2(0.0, rect.size.y)
	if filled:
		_quad(p0, p1, p2, p3, col)
	elif width > 2.0 or col.a < 1.0:
		sync()
		g.draw_rect(rect, col, false, width, aa)
	else:
		_strip(PackedVector2Array([p0, p1, p2, p3, p0]), col, width)   # 闭合带斜接：四个角是满的


# ---------------------------------------------------------------- 内部

## 圆周分段：和屏幕上的大小相称（小点 10 段，大圈到 48 段）
func _seg(r: float) -> int:
	var s: float = r * maxf(absf(xf.x.x) + absf(xf.x.y), absf(xf.y.x) + absf(xf.y.y))
	return clampi(int(s * 0.5) + 8, 10, 48)


## 局部坐标里一段有宽度的线（宽度也在局部坐标里量，和 draw_line 在变换下的表现一致）
func _seg_quad(a: Vector2, b: Vector2, col: Color, width: float) -> void:
	var d: Vector2 = b - a
	if d.length_squared() < 0.000001:
		return
	var w: float = width if width > 0.0 else 1.0
	var n: Vector2 = d.orthogonal().normalized() * w * 0.5
	_quad(a + n, b + n, b - n, a - n, col)


## 折线：连续三角带，折点处斜接（原来逐段一个矩形：折点内侧重叠、半透明叠两次变亮，外侧缺楔形，测试与验收 9/30 查出）。
## 首尾重合时按闭合处理（首尾也斜接）；斜接过尖（超过 4 倍半宽）时截到 4 倍
func _strip(points: PackedVector2Array, col: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for p in points:
		if pts.is_empty() or p.distance_squared_to(pts[pts.size() - 1]) > 0.000001:
			pts.append(p)
	var n: int = pts.size()
	if n < 2:
		return
	var closed: bool = n > 2 and pts[0].distance_squared_to(pts[n - 1]) < 0.000001
	if closed:
		pts.remove_at(n - 1)
		n -= 1
	var hw: float = (width if width > 0.0 else 1.0) * 0.5
	var vv := PackedVector2Array()   # 两侧顶点先收齐（局部坐标），最后整组乘 xf、展开成三角形
	vv.resize(n * 2)
	for i in n:
		var has_prev: bool = closed or i > 0
		var has_next: bool = closed or i < n - 1
		var d_in: Vector2 = (pts[i] - pts[(i - 1 + n) % n]).normalized() if has_prev else Vector2.ZERO
		var d_out: Vector2 = (pts[(i + 1) % n] - pts[i]).normalized() if has_next else Vector2.ZERO
		var nrm: Vector2
		var ml: float = hw
		if has_prev and has_next:
			var n1: Vector2 = d_in.orthogonal()
			var n2: Vector2 = d_out.orthogonal()
			nrm = (n1 + n2)
			if nrm.length_squared() < 0.000001:
				nrm = n1
			else:
				nrm = nrm.normalized()
				ml = minf(hw / maxf(nrm.dot(n1), 0.0001), hw * 4.0)
		else:
			nrm = (d_out if has_next else d_in).orthogonal()
		vv[i * 2] = pts[i] + nrm * ml
		vv[i * 2 + 1] = pts[i] - nrm * ml
	var segs: int = n if closed else n - 1
	if xf != Transform2D.IDENTITY:
		vv = xf * vv
	var out := PackedVector2Array()
	out.resize(segs * 6)
	for q in segs:
		var a0: int = q * 2
		var a1: int = ((q + 1) % n) * 2
		var o: int = q * 6
		out[o] = vv[a0]
		out[o + 1] = vv[a0 + 1]
		out[o + 2] = vv[a1 + 1]
		out[o + 3] = vv[a0]
		out[o + 4] = vv[a1 + 1]
		out[o + 5] = vv[a1]
	_pts.append_array(out)
	_fill(out.size(), col)


## 弧：n 个点（n - 1 段），宽度 width（≤ 0 = 1 像素）
func _arc(c: Vector2, r: float, a0: float, a1: float, n: int, col: Color, width: float) -> void:
	n = maxi(n, 2)
	var w: float = width if width > 0.0 else 1.0
	var ri: float = maxf(0.0, r - w * 0.5)
	var ro: float = r + w * 0.5
	_arc_fast(c, ri, ro, a0, a1, n, col)


# ---------------------------------------------------------------- 合批几何（docs/50 §14 OPT_CV）

func _fill(n: int, col: Color) -> void:
	var c: PackedColorArray = _cbuf.get(n, PackedColorArray())
	if c.size() != n:
		c.resize(n)
		_cbuf[n] = c
	c.fill(col)
	_cols.append_array(c)


## 四边形 p0 p1 p2 p3 → 两个三角形 (0, 1, 2) (0, 2, 3)（同旧写法的索引）
func _quad(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, col: Color) -> void:
	var q := PackedVector2Array([p0, p1, p2, p0, p2, p3])
	_pts.append_array(q if xf == Transform2D.IDENTITY else xf * q)
	_fill(6, col)


static func _fan_table(seg: int) -> PackedVector2Array:
	var fan := PackedVector2Array()
	for q in seg:
		var a: float = q * TAU / seg
		var q2: int = (q + 1) % seg
		var a2: float = q2 * TAU / seg
		fan.append_array([Vector2.ZERO, Vector2(cos(a), sin(a)), Vector2(cos(a2), sin(a2))])
	_fans[seg] = fan
	return fan


## 弧：n 个点的内外两圈整组生成，再按旧写法的索引 (i, o, o+1) (i, o+1, i+1) 展开；整圈（0 → TAU）按 (点数, 内径, 外径) 缓存以原点为心的三角形表
## （表里存的就是 d × r，加圆心与旧写法 c + d × r 逐位相同；半径只以单精度进入运算，所以按单精度作键不会串）
func _arc_fast(c: Vector2, ri: float, ro: float, a0: float, a1: float, n: int, col: Color) -> void:
	var full: bool = a0 == 0.0 and a1 == TAU
	var key := Vector3(n, ri, ro)
	if full:
		var hit = _rings.get(key)
		if hit != null:
			var loc0: PackedVector2Array = Transform2D(Vector2(1.0, 0.0), Vector2(0.0, 1.0), c) * hit
			_pts.append_array(loc0 if xf == Transform2D.IDENTITY else xf * loc0)
			_fill(hit.size(), col)
			return
	var dirs = _adirs.get(n) if full else null
	if dirs == null:
		dirs = PackedVector2Array()
		dirs.resize(n)
		for q in n:
			var a: float = lerpf(a0, a1, float(q) / float(n - 1))
			dirs[q] = Vector2(cos(a), sin(a))
		if full:
			_adirs[n] = dirs
	var org: Vector2 = Vector2.ZERO if full else c
	var pin: PackedVector2Array = Transform2D(Vector2(ri, 0.0), Vector2(0.0, ri), org) * dirs
	var pout: PackedVector2Array = Transform2D(Vector2(ro, 0.0), Vector2(0.0, ro), org) * dirs
	var m: int = n - 1
	var out := PackedVector2Array()
	out.resize(m * 6)
	for q in m:
		var o: int = q * 6
		var iq: Vector2 = pin[q]
		var o1: Vector2 = pout[q + 1]
		out[o] = iq
		out[o + 1] = pout[q]
		out[o + 2] = o1
		out[o + 3] = iq
		out[o + 4] = o1
		out[o + 5] = pin[q + 1]
	if full:
		if _rings.size() > 1024:
			_rings.clear()
		_rings[key] = out
		out = Transform2D(Vector2(1.0, 0.0), Vector2(0.0, 1.0), c) * out
	_pts.append_array(out if xf == Transform2D.IDENTITY else xf * out)
	_fill(out.size(), col)
