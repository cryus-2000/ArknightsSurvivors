extends RefCounted
## 无贴图图元批（性能，协调人 9/30：Godot 画布只合批贴图矩形，draw_rect / draw_circle / draw_line 各算一次绘制调用）：
## 矩形 / 边框 / 渐变 / 多边形 / 圆 / 线攒成三角形，flush 时一次 canvas_item_add_triangle_array 提交。
## 提交时画布变换须为单位矩阵
## 2026-10-10 从 hud.gd 的内部类 Tris 拆成独立脚本（docs/55 §6），hud.gd 与各 HUD 模块以 const Tris 预载，用法不变

var pts := PackedVector2Array()
var cols := PackedColorArray()
var idx := PackedInt32Array()

func quad4(p: Array, c: Array) -> void:
	var b: int = pts.size()
	for q in 4:
		pts.append(p[q])
		cols.append(c[q])
	idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])

func rect(r: Rect2, col: Color) -> void:
	quad4([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)], [col, col, col, col])

## 上下渐变（顶色 / 底色）
func grad(r: Rect2, ct: Color, cb: Color) -> void:
	quad4([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)], [ct, ct, cb, cb])

## 边框：同 draw_rect(filled = false, w)，线宽骑在边上
func frame(r: Rect2, col: Color, w := 1.0) -> void:
	var o := r.grow(w * 0.5)
	rect(Rect2(o.position, Vector2(o.size.x, w)), col)
	rect(Rect2(Vector2(o.position.x, o.end.y - w), Vector2(o.size.x, w)), col)
	rect(Rect2(Vector2(o.position.x, o.position.y + w), Vector2(w, o.size.y - w * 2.0)), col)
	rect(Rect2(Vector2(o.end.x - w, o.position.y + w), Vector2(w, o.size.y - w * 2.0)), col)

## 凸多边形（扇形三角化）
func poly(p: PackedVector2Array, col: Color) -> void:
	var b: int = pts.size()
	for v in p:
		pts.append(v)
		cols.append(col)
	for q in range(1, p.size() - 1):
		idx.append_array([b, b + q, b + q + 1])

func line(a: Vector2, b: Vector2, col: Color, w := 1.0) -> void:
	var d := b - a
	if d.length_squared() < 0.0001:
		return
	var n := d.normalized().orthogonal() * (w * 0.5)
	quad4([a + n, b + n, b - n, a - n], [col, col, col, col])

func circle(c: Vector2, r: float, col: Color, seg := 12) -> void:
	var b: int = pts.size()
	pts.append(c)
	cols.append(col)
	for q in seg:
		pts.append(c + Vector2.from_angle(TAU * q / seg) * r)
		cols.append(col)
	for q in seg:
		idx.append_array([b, b + 1 + q, b + 1 + (q + 1) % seg])

func arc(c: Vector2, r: float, a0: float, a1: float, w: float, col: Color, seg := 24) -> void:
	var b: int = pts.size()
	for q in seg + 1:
		var d := Vector2.from_angle(lerpf(a0, a1, float(q) / seg))
		pts.append(c + d * (r - w * 0.5))
		pts.append(c + d * (r + w * 0.5))
		cols.append(col)
		cols.append(col)
	for q in seg:
		var i0: int = b + q * 2
		idx.append_array([i0, i0 + 1, i0 + 3, i0, i0 + 3, i0 + 2])

## 同 UI.diamond：实心菱形 + 可选 1px 描边
func diamond(c: Vector2, rad: float, fill: Color, border := Color(0, 0, 0, 0)) -> void:
	var p := PackedVector2Array([c + Vector2(0, -rad), c + Vector2(rad, 0), c + Vector2(0, rad), c + Vector2(-rad, 0)])
	poly(p, fill)
	if border.a > 0.0:
		for q in 4:
			line(p[q], p[(q + 1) % 4], border, 1.0)

func flush(ci: CanvasItem) -> void:
	if idx.is_empty():
		return
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), idx, pts, cols)
	pts = PackedVector2Array()
	cols = PackedColorArray()
	idx = PackedInt32Array()
