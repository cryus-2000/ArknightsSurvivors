extends RefCounted
## 界面绘制工具：深海黑蓝底、生物荧光青色点缀、切角面板、细线与英文小标签。

const BG := Color(0.02, 0.05, 0.08, 0.88)
const BG2 := Color(0.04, 0.10, 0.14, 0.92)
const LINE := Color(0.20, 0.45, 0.50, 0.9)
const CYAN := Color(0.33, 0.92, 0.88)
const CYAN_DIM := Color(0.18, 0.55, 0.56)
const GOLD := Color(1.0, 0.77, 0.42)
const RED := Color(1.0, 0.36, 0.43)
const PURPLE := Color(0.66, 0.52, 1.0)
const TEXT := Color(0.90, 0.96, 0.96)
const SUB := Color(0.50, 0.66, 0.70)

const CAT_COL := {"灯火": Color(1.0, 0.77, 0.42), "战斗": Color(0.33, 0.92, 0.88), "生存": Color(0.55, 0.9, 0.55), "海嗣": Color(0.66, 0.52, 1.0)}


## 切角多边形（左上、右下切角）
static func cut_poly(r: Rect2, cut: float) -> PackedVector2Array:
	return PackedVector2Array([
		r.position + Vector2(cut, 0), Vector2(r.end.x, r.position.y), r.end - Vector2(0, cut),
		r.end - Vector2(cut, 0), Vector2(r.position.x, r.end.y), r.position + Vector2(0, cut)])


static func panel(ci: CanvasItem, r: Rect2, fill := BG, border := LINE, cut := 10.0, accent := Color(0, 0, 0, 0)) -> void:
	var p := cut_poly(r, cut)
	ci.draw_colored_polygon(p, fill)
	var closed := p.duplicate()
	closed.append(p[0])
	ci.draw_polyline(closed, border, 1.0)
	if accent.a > 0.0:
		# 左上角荧光短线
		ci.draw_line(r.position + Vector2(cut, 0), r.position + Vector2(cut + 36, 0), accent, 3.0)
		ci.draw_line(r.position + Vector2(0, cut), r.position + Vector2(0, cut + 18), accent, 3.0)


## 英文小标签（加字距）
static func en(ci: CanvasItem, font: Font, pos: Vector2, text: String, size: int, col: Color, spacing := 2.0) -> float:
	var x := pos.x
	for ch in text:
		ci.draw_string(font, Vector2(x, pos.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + spacing
	return x - pos.x


static func text(ci: CanvasItem, font: Font, pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, outline := 0) -> void:
	if outline > 0:
		ci.draw_string_outline(font, pos, s, align, width, size, outline, Color(0, 0, 0, col.a * 0.8))
	ci.draw_string(font, pos, s, align, width, size, col)


## 分段细条
static func bar(ci: CanvasItem, r: Rect2, frac: float, col: Color, segments := 0) -> void:
	ci.draw_rect(r, Color(0, 0, 0, 0.55))
	frac = clamp(frac, 0.0, 1.0)
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x * frac, r.size.y)), col)
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x * frac, 1)), col.lightened(0.4))
	if segments > 1:
		for i in range(1, segments):
			var x := r.position.x + r.size.x * i / segments
			ci.draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(0, 0, 0, 0.6), 1.0)


static func diamond(ci: CanvasItem, c: Vector2, rad: float, fill: Color, border := Color(0, 0, 0, 0)) -> void:
	var p := PackedVector2Array([c + Vector2(0, -rad), c + Vector2(rad, 0), c + Vector2(0, rad), c + Vector2(-rad, 0)])
	ci.draw_colored_polygon(p, fill)
	if border.a > 0.0:
		p.append(p[0])
		ci.draw_polyline(p, border, 1.0)


## 横向装饰线：——◆——
static func rule(ci: CanvasItem, a: Vector2, b: Vector2, col: Color) -> void:
	var m := (a + b) / 2.0
	ci.draw_line(a, m - Vector2(8, 0), col, 1.0)
	ci.draw_line(m + Vector2(8, 0), b, col, 1.0)
	diamond(ci, m, 4.0, col)
