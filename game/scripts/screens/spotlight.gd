extends RefCounted
## 聚光框的画法（局内引导 screens/tour.gd 与主界面引导 screens/title_tour.gd 共用；docs/157）：
## 压暗全屏（洞内不压）+ 洞边淡黄底、细边、四角 L 括号（呼吸）+ 旁边一块斜切说明板（黄条、小标、标题、一两句正文、操作提示）+ 底部「跳过引导」。
## 只画，不管输入；返回跳过按钮的点击区（没画跳过时返回空 Rect2）。

const UI = preload("res://scripts/ui.gd")


## holes：要框的矩形（画布局部坐标）；o：
##   idx / n（第几步 / 共几步）、tag（小标前缀，缺省 GUIDE）、en（英文小标）、title、text、hint（操作提示）、
##   e（入场 0..1，缺省 1）、t（本步已过秒，呼吸用）、dim（压暗，缺省 0.68；0 = 不压暗，只框）、skip（画「跳过引导」，缺省 true）、touch（触屏尺寸）
static func draw(ci: CanvasItem, font: Font, vs: Vector2, holes: Array, o: Dictionary) -> Rect2:
	var e: float = float(o.get("e", 1.0))
	var t: float = float(o.get("t", 0.0))
	var touch: bool = bool(o.get("touch", false))
	var hs: Array = []
	for r in holes:
		hs.append(r.grow((1.0 - e) * 26.0 + 5.0))
	var dim: float = float(o.get("dim", 0.68))
	if dim > 0.0:
		_dim(ci, vs, hs, dim * minf(1.0, e * 1.5))
	var pulse: float = 0.5 + 0.5 * sin(t * 4.2)
	for r in hs:
		_frame(ci, r, e, pulse)
	# 说明板
	var pw: float = minf(vs.x - 32.0, 400.0 if touch else 380.0)
	var fsz := 15
	var lines: PackedStringArray = UI.wrap_lines(font, str(o.text), fsz, pw - 44.0)
	var lh: float = font.get_height(UI.fs(fsz)) + 3.0
	var ph: float = 78.0 + lines.size() * lh + 34.0
	var ub: Rect2 = hs[0]
	for r in hs:
		ub = ub.merge(r)
	var py: float = ub.end.y + 16.0
	if py + ph > vs.y - 66.0:
		py = ub.position.y - 16.0 - ph
	py = clampf(py, 8.0, vs.y - ph - 8.0)
	var px: float = clampf(ub.get_center().x - pw / 2.0, 16.0, vs.x - pw - 16.0)
	var pr := Rect2(Vector2(px, py + (1.0 - e) * 10.0), Vector2(pw, ph))
	var gold := Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, e)
	UI.panel(ci, pr, Color(UI.BG2.r, UI.BG2.g, UI.BG2.b, 0.96 * e), Color(1, 1, 1, 0.16 * e), 12.0, gold)
	ci.draw_rect(Rect2(pr.position + Vector2(0, 12), Vector2(4, ph - 24)), gold)
	var head := "%s  %02d / %02d  ·  %s" % [str(o.get("tag", "GUIDE")), int(o.idx) + 1, int(o.n), str(o.en)]
	UI.en(ci, font, pr.position + Vector2(22, 26), head, 11, gold, 2.5)
	UI.text(ci, font, pr.position + Vector2(22, 56), str(o.title), 22, Color(UI.TEXT.r, UI.TEXT.g, UI.TEXT.b, e))
	var asc: float = font.get_ascent(UI.fs(fsz))
	var y: float = pr.position.y + 66.0
	for i in lines.size():
		ci.draw_string(font, Vector2(pr.position.x + 22, y + asc + i * lh), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, UI.fs(fsz), Color(0.85, 0.93, 0.95, e))
	UI.text(ci, font, pr.position + Vector2(22, ph - 14), str(o.get("hint", "")), 11, Color(UI.SUB.r, UI.SUB.g, UI.SUB.b, e))
	if not bool(o.get("skip", true)):
		return Rect2()
	# 跳过按钮：屏幕底部居中（顶部与两侧都有界面键）
	var bw := 150.0 if touch else 128.0
	var bh := 44.0 if touch else 34.0
	var br := Rect2(vs.x / 2.0 - bw / 2.0, vs.y - bh - 14.0, bw, bh)
	var hov: bool = br.has_point(ci.get_local_mouse_position())
	UI.frame(ci, br, UI.GOLD, {"cut": 6.0, "bracket": 6.0, "glow": 1.0 if hov else 0.0, "alpha": (1.0 if hov else 0.75) * e})
	UI.text(ci, font, br.position + Vector2(0, bh * 0.66), "跳过引导", 15 if touch else 14, Color(UI.TEXT.r, UI.TEXT.g, UI.TEXT.b, e), HORIZONTAL_ALIGNMENT_CENTER, bw)
	return br.grow_individual(12, 8, 12, 8) if touch else br


## 暗幕：按各个洞的边把全屏切成网格，洞内的格子不画
static func _dim(ci: CanvasItem, vs: Vector2, holes: Array, a: float) -> void:
	var xs: Array = [0.0, vs.x]
	var ys: Array = [0.0, vs.y]
	for r in holes:
		xs.append_array([clampf(r.position.x, 0.0, vs.x), clampf(r.end.x, 0.0, vs.x)])
		ys.append_array([clampf(r.position.y, 0.0, vs.y), clampf(r.end.y, 0.0, vs.y)])
	xs.sort()
	ys.sort()
	var col := Color(0.0, 0.012, 0.03, a)
	for i in xs.size() - 1:
		for j in ys.size() - 1:
			var cell := Rect2(xs[i], ys[j], xs[i + 1] - xs[i], ys[j + 1] - ys[j])
			if cell.size.x < 0.5 or cell.size.y < 0.5:
				continue
			var inside := false
			for r in holes:
				if r.has_point(cell.get_center()):
					inside = true
					break
			if not inside:
				ci.draw_rect(cell, col)


## 聚光框：淡黄底 + 细边 + 四角 L 形括号，呼吸闪烁
static func _frame(ci: CanvasItem, r: Rect2, e: float, pulse: float) -> void:
	var gold := Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 1.0)
	ci.draw_rect(r, Color(gold.r, gold.g, gold.b, (0.04 + 0.05 * pulse) * e))
	ci.draw_rect(r, Color(gold.r, gold.g, gold.b, 0.5 * e), false, 1.0)
	var cl := 16.0
	for sx in [0.0, 1.0]:
		for sy in [0.0, 1.0]:
			var q := Vector2(r.position.x + sx * r.size.x, r.position.y + sy * r.size.y)
			var dx: float = -cl if sx > 0.5 else cl
			var dy: float = -cl if sy > 0.5 else cl
			ci.draw_polyline(PackedVector2Array([q + Vector2(0, dy), q, q + Vector2(dx, 0)]), Color(gold.r, gold.g, gold.b, (0.75 + 0.25 * pulse) * e), 3.0)
