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
var _idx := PackedInt32Array()
var _off := -1


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
	if _idx.is_empty():
		return
	if _gxf != Transform2D.IDENTITY:
		g.draw_set_transform_matrix(Transform2D.IDENTITY)
		_gxf = Transform2D.IDENTITY
	RenderingServer.canvas_item_add_triangle_array(g.get_canvas_item(), _idx, _pts, _cols)
	_pts = PackedVector2Array()
	_cols = PackedColorArray()
	_idx = PackedInt32Array()


## 直接往 g 上画之前：先提交几何，再把当前变换下发给 g（批外的贴图 / UI 画法与原来同样处在这个变换下）
func sync() -> void:
	flush()
	if _gxf != xf:
		g.draw_set_transform_matrix(xf)
		_gxf = xf


# ---------------------------------------------------------------- CanvasItem 同名接口

func draw_set_transform(p: Vector2, rot := 0.0, sc := Vector2.ONE) -> void:
	if not active:
		g.draw_set_transform(p, rot, sc)
		return
	xf = Transform2D(rot, sc, 0.0, p)


func draw_texture_rect_region(tex: Texture2D, rect: Rect2, src: Rect2, mod := Color.WHITE, transpose := false, clip := true) -> void:
	if active:
		sync()
	g.draw_texture_rect_region(tex, rect, src, mod, transpose, clip)


func draw_circle(p: Vector2, r: float, col: Color, filled := true, width := -1.0, aa := false) -> void:
	if not active:
		g.draw_circle(p, r, col, filled, width, aa)
		return
	var seg: int = _seg(r)
	if not filled:
		_arc(p, r, 0.0, TAU, seg + 1, col, width)
		return
	var base: int = _pts.size()
	_add(p, col)
	for q in seg:
		var a: float = q * TAU / seg
		_add(p + Vector2(cos(a), sin(a)) * r, col)
	for q in seg:
		_idx.append_array([base, base + 1 + q, base + 1 + (q + 1) % seg])


func draw_arc(c: Vector2, r: float, a0: float, a1: float, n: int, col: Color, width := -1.0, aa := false) -> void:
	if not active:
		g.draw_arc(c, r, a0, a1, n, col, width, aa)
		return
	_arc(c, r, a0, a1, n, col, width)


func draw_line(a: Vector2, b: Vector2, col: Color, width := -1.0, aa := false) -> void:
	if not active:
		g.draw_line(a, b, col, width, aa)
		return
	_seg_quad(a, b, col, width)


func draw_polyline(points: PackedVector2Array, col: Color, width := -1.0, aa := false) -> void:
	if not active:
		g.draw_polyline(points, col, width, aa)
		return
	for q in points.size() - 1:
		_seg_quad(points[q], points[q + 1], col, width)


func draw_colored_polygon(points: PackedVector2Array, col: Color, uvs := PackedVector2Array(), tex: Texture2D = null) -> void:
	if not active or tex != null:
		if active:
			sync()
		g.draw_colored_polygon(points, col, uvs, tex)
		return
	var tri: PackedInt32Array = Geometry2D.triangulate_polygon(points)
	if tri.is_empty():
		return
	var base: int = _pts.size()
	for p in points:
		_add(p, col)
	for t in tri:
		_idx.append(base + t)


func draw_rect(rect: Rect2, col: Color, filled := true, width := -1.0, aa := false) -> void:
	if not active:
		g.draw_rect(rect, col, filled, width, aa)
		return
	var p0 := rect.position
	var p1 := rect.position + Vector2(rect.size.x, 0.0)
	var p2 := rect.end
	var p3 := rect.position + Vector2(0.0, rect.size.y)
	if filled:
		var base: int = _pts.size()
		_add(p0, col)
		_add(p1, col)
		_add(p2, col)
		_add(p3, col)
		_idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	else:
		for s in [[p0, p1], [p1, p2], [p2, p3], [p3, p0]]:
			_seg_quad(s[0], s[1], col, width)


# ---------------------------------------------------------------- 内部

## 圆周分段：和屏幕上的大小相称（小点 10 段，大圈到 48 段）
func _seg(r: float) -> int:
	var s: float = r * maxf(absf(xf.x.x) + absf(xf.x.y), absf(xf.y.x) + absf(xf.y.y))
	return clampi(int(s * 0.5) + 8, 10, 48)


func _add(local: Vector2, col: Color) -> void:
	_pts.append(xf * local)
	_cols.append(col)


## 局部坐标里一段有宽度的线（宽度也在局部坐标里量，和 draw_line 在变换下的表现一致）
func _seg_quad(a: Vector2, b: Vector2, col: Color, width: float) -> void:
	var d: Vector2 = b - a
	if d.length_squared() < 0.000001:
		return
	var w: float = width if width > 0.0 else 1.0
	var n: Vector2 = d.orthogonal().normalized() * w * 0.5
	var base: int = _pts.size()
	_add(a + n, col)
	_add(b + n, col)
	_add(b - n, col)
	_add(a - n, col)
	_idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])


## 弧：n 个点（n - 1 段），宽度 width（≤ 0 = 1 像素）
func _arc(c: Vector2, r: float, a0: float, a1: float, n: int, col: Color, width: float) -> void:
	n = maxi(n, 2)
	var w: float = width if width > 0.0 else 1.0
	var ri: float = maxf(0.0, r - w * 0.5)
	var ro: float = r + w * 0.5
	var base: int = _pts.size()
	for q in n:
		var a: float = lerpf(a0, a1, float(q) / float(n - 1))
		var d := Vector2(cos(a), sin(a))
		_add(c + d * ri, col)
		_add(c + d * ro, col)
	for q in n - 1:
		var i0: int = base + q * 2
		_idx.append_array([i0, i0 + 1, i0 + 3, i0, i0 + 3, i0 + 2])
