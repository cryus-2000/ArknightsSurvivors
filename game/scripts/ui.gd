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
## 多行文字折行规则：中文没有空格，必须允许按字折行，否则整段不换行溢出面板
const BRK: int = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_GRAPHEME_BOUND | TextServer.BREAK_ADAPTIVE

const CAT_COL := {"灯火": Color(1.0, 0.77, 0.42), "战斗": Color(0.33, 0.92, 0.88), "生存": Color(0.55, 0.9, 0.55), "海嗣": Color(0.66, 0.52, 1.0),
	# data/relics.json 的分类
	"攻击与输出": Color(0.33, 0.92, 0.88), "触手与控制": Color(0.66, 0.52, 1.0), "技能与技力": Color(0.5, 0.75, 1.0), "护盾": Color(0.6, 0.85, 1.0),
	"削弱敌人": Color(1.0, 0.55, 0.55), "经济": Color(1.0, 0.85, 0.4), "闪避": Color(0.7, 0.95, 1.0), "条件触发": Color(1.0, 0.7, 0.9),
	"援护干员": Color(0.9, 0.8, 0.6), "支援装置": Color(0.8, 0.8, 0.85), "负面藏品": Color(0.8, 0.35, 0.5)}


## 切角多边形（左上、右下切角）
static func cut_poly(r: Rect2, cut: float) -> PackedVector2Array:
	return PackedVector2Array([
		r.position + Vector2(cut, 0), Vector2(r.end.x, r.position.y), r.end - Vector2(0, cut),
		r.end - Vector2(cut, 0), Vector2(r.position.x, r.end.y), r.position + Vector2(0, cut)])


## 通用面板：统一走深海面板（frame）。accent 给了就作为主色并带外发光；vines_seed > 0 时画藤蔓
static func panel(ci: CanvasItem, r: Rect2, fill := BG, border := LINE, cut := 10.0, accent := Color(0, 0, 0, 0), vines_seed := 0, t := 0.0) -> void:
	var main := accent if accent.a > 0.0 else Color(border.r, border.g, border.b, 1.0)
	var small: float = minf(r.size.x, r.size.y)
	frame(ci, r, main, {"cut": cut, "alpha": clampf(fill.a / 0.88, 0.3, 1.0), "glow": 0.35 if accent.a > 0.0 else 0.0,
		"bracket": clampf(small * 0.22, 5.0, 12.0), "vines": vines_seed > 0, "seed": vines_seed, "t": t, "vine_k": 0.7})


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


## 中文自动换行：在每个 CJK 字符后插入零宽空格（U+200B）作为换行机会，
## 避免文本服务把整段中文当成一个「词」、只在空格处换行（表现为第一行极短）。
## 不在开头标点（《「（）后、也不在结尾标点（》」，。）前插入，避免标点悬在行首。
const _NO_BREAK_AFTER := "《「『（【〈"
const _NO_BREAK_BEFORE := "》」』）】〉，。、；：！？"
static func soft(s: String) -> String:
	var out := ""
	var n := s.length()
	for i in n:
		var ch := s[i]
		out += ch
		if i + 1 >= n:
			break
		var code := ch.unicode_at(0)
		var nx := s[i + 1]
		var cjk := (code >= 0x4E00 and code <= 0x9FFF) or (code >= 0x3000 and code <= 0x303F) or (code >= 0xFF00 and code <= 0xFFEF)
		if cjk and not _NO_BREAK_AFTER.contains(ch) and not _NO_BREAK_BEFORE.contains(nx) and nx != " ":
			out += "\u200B"
	return out


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


# =====================================================================
# 深海生物发光风 UI 套件（v1.2）
# 面板：半透明深蓝渐变 + 内暗线 + 荧光细边 + 像素角括；可选藤蔓缠绕装饰
# 条：发光分段条；环：技能圆环；舷窗：小地图；标签片
# =====================================================================
const DEEP := Color(0.015, 0.06, 0.12, 0.86)
const DEEP2 := Color(0.03, 0.10, 0.18, 0.86)
const EDGE := Color(0.22, 0.62, 0.70, 0.85)
const EDGE_DIM := Color(0.10, 0.30, 0.38, 0.9)
const GLOW := Color(0.35, 0.95, 0.95)
const KELP := Color(0.10, 0.36, 0.34)
const KELP2 := Color(0.16, 0.52, 0.46)
const KELP_LIGHT := Color(0.45, 0.95, 0.85)


## 深海面板。accent 为角括与光边颜色；vines 画藤蔓；glow 画外发光；seed 决定藤蔓形状；t 用于呼吸动画
static func frame(ci: CanvasItem, r: Rect2, accent := GLOW, opts := {}) -> void:
	var t: float = opts.get("t", 0.0)
	var cut: float = opts.get("cut", 6.0)
	var fill_a: float = opts.get("alpha", 1.0)
	var glow_k: float = opts.get("glow", 0.0)
	var p := cut_poly(r, cut)
	# 外发光（两层）
	if glow_k > 0.0:
		var closed := p.duplicate()
		closed.append(p[0])
		ci.draw_polyline(closed, Color(accent.r, accent.g, accent.b, 0.10 * glow_k), 9.0)
		ci.draw_polyline(closed, Color(accent.r, accent.g, accent.b, 0.22 * glow_k), 4.0)
	# 渐变底：上浅下深
	var cols := PackedColorArray()
	for q in p:
		var k := (q.y - r.position.y) / maxf(r.size.y, 1.0)
		var c := DEEP2.lerp(DEEP, k)
		cols.append(Color(c.r, c.g, c.b, c.a * fill_a))
	ci.draw_polygon(p, cols)
	# 顶部一道微光（像水面透下的光）
	ci.draw_line(r.position + Vector2(cut + 1, 1), Vector2(r.end.x - 1, r.position.y + 1), Color(accent.r, accent.g, accent.b, 0.10), 1.0)
	# 内暗线 + 外细边
	var inner := cut_poly(r.grow(-3.0), maxf(cut - 2.0, 2.0))
	inner.append(inner[0])
	ci.draw_polyline(inner, Color(0, 0, 0, 0.35), 1.0)
	var outer := p.duplicate()
	outer.append(p[0])
	ci.draw_polyline(outer, Color(accent.r, accent.g, accent.b, 0.55), 1.0)
	# 像素角括（四角，2px 粗）
	var L: float = opts.get("bracket", 10.0)
	var ac := Color(accent.r, accent.g, accent.b, 0.95)
	var x0 := r.position.x
	var y0 := r.position.y
	var x1 := r.end.x
	var y1 := r.end.y
	ci.draw_rect(Rect2(x0 + cut, y0, L, 2), ac)
	ci.draw_rect(Rect2(x0, y0 + cut, 2, L), ac)
	ci.draw_rect(Rect2(x1 - L, y0, L, 2), ac)
	ci.draw_rect(Rect2(x1 - 2, y0, 2, L), ac)
	ci.draw_rect(Rect2(x0, y1 - L, 2, L), ac)
	ci.draw_rect(Rect2(x0, y1 - 2, L, 2), ac)
	ci.draw_rect(Rect2(x1 - cut - L, y1 - 2, L, 2), ac)
	ci.draw_rect(Rect2(x1 - 2, y1 - cut - L, 2, L), ac)
	if opts.get("vines", false):
		vines(ci, r, int(opts.get("seed", 1)), t, opts.get("vine_k", 1.0))


## 藤蔓：从面板左上与右下角长出，沿边缘缠绕，带叶片与发光节点
static func vines(ci: CanvasItem, r: Rect2, seed: int, t: float, k := 1.0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var corners := [
		[r.position + Vector2(-2, 8), Vector2(1, 0), Vector2(0, 1)],       # 左上：沿上边向右
		[r.position + Vector2(8, -2), Vector2(0, 1), Vector2(1, 0)],       # 左上：沿左边向下
		[r.end - Vector2(-2, 8), Vector2(-1, 0), Vector2(0, -1)],           # 右下：沿下边向左
	]
	for ci_ in corners.size():
		var c: Array = corners[ci_]
		var p: Vector2 = c[0]
		var along: Vector2 = c[1]
		var out: Vector2 = c[2]     # 指向面板内侧
		var length: float = rng.randf_range(0.22, 0.42) * (r.size.x if along.x != 0 else r.size.y) * k
		var pts := PackedVector2Array()
		var n := int(length / 4.0)
		var ph := rng.randf() * TAU
		var amp := rng.randf_range(3.0, 5.0)
		for i in n + 1:
			var s := float(i) / maxf(n, 1)
			var sway := sin(s * 9.0 + ph + t * 0.8) * amp * (0.4 + s)
			pts.append(p + along * (s * length) + out * (sway - 2.0 * (1.0 - s)) * -1.0)
		if pts.size() < 2:
			continue
		ci.draw_polyline(pts, Color(0.02, 0.09, 0.10, 0.9), 4.0)
		ci.draw_polyline(pts, KELP, 2.5)
		# 高光
		var hl := PackedVector2Array()
		for q in pts:
			hl.append(q + out * -1.0)
		ci.draw_polyline(hl, Color(KELP2.r, KELP2.g, KELP2.b, 0.6), 1.0)
		# 叶片与发光节点
		var leaves := rng.randi_range(2, 4)
		for j in leaves:
			var idx := int((0.25 + 0.7 * j / leaves) * (pts.size() - 1))
			var q: Vector2 = pts[idx]
			var side := 1.0 if j % 2 == 0 else -1.0
			var dir: Vector2 = (out * -side).rotated(rng.randf_range(-0.5, 0.5))
			var la := 5.0 + rng.randf_range(0.0, 3.0)
			var leaf := PackedVector2Array([q, q + dir * la + along * 2.0, q + dir * (la + 3.0), q + dir * la - along * 2.0])
			ci.draw_colored_polygon(leaf, KELP2)
			ci.draw_line(q, q + dir * (la + 2.0), Color(KELP_LIGHT.r, KELP_LIGHT.g, KELP_LIGHT.b, 0.5), 1.0)
		var nodes := rng.randi_range(2, 3)
		for j in nodes:
			var idx := int((0.15 + 0.8 * j / maxf(nodes - 1, 1)) * (pts.size() - 1))
			var q: Vector2 = pts[idx]
			var a := 0.5 + 0.5 * sin(t * 1.6 + rng.randf() * TAU)
			ci.draw_circle(q, 4.0 + 2.0 * a, Color(KELP_LIGHT.r, KELP_LIGHT.g, KELP_LIGHT.b, 0.10 + 0.12 * a))
			ci.draw_rect(Rect2(q.round() - Vector2(1, 1), Vector2(2, 2)), Color(KELP_LIGHT.r, KELP_LIGHT.g, KELP_LIGHT.b, 0.6 + 0.4 * a))


## 发光分段条：底槽 + 填充 + 顶部高光 + 外晕；trail 为残影比例（掉血用）
static func gbar(ci: CanvasItem, r: Rect2, frac: float, col: Color, segments := 0, trail := -1.0) -> void:
	frac = clampf(frac, 0.0, 1.0)
	ci.draw_rect(r.grow(1.0), Color(0, 0, 0, 0.6))
	ci.draw_rect(r, Color(0.02, 0.05, 0.09, 0.9))
	if trail > frac:
		ci.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(trail, 0.0, 1.0), r.size.y)), Color(1.0, 0.95, 0.9, 0.8))
	var fw := r.size.x * frac
	if fw > 0.0:
		var fr := Rect2(r.position, Vector2(fw, r.size.y))
		ci.draw_rect(fr.grow(2.0), Color(col.r, col.g, col.b, 0.12))
		ci.draw_rect(fr, col)
		ci.draw_rect(Rect2(fr.position, Vector2(fw, 2)), col.lightened(0.45))
		ci.draw_rect(Rect2(fr.position + Vector2(0, r.size.y - 2), Vector2(fw, 2)), col.darkened(0.35))
	if segments > 1:
		for i in range(1, segments):
			var x := r.position.x + r.size.x * i / segments
			ci.draw_rect(Rect2(Vector2(x, r.position.y), Vector2(1, r.size.y)), Color(0, 0, 0, 0.55))
	ci.draw_rect(r, EDGE_DIM, false, 1.0)


## 技能圆环：暗底 + 进度弧 + 外光；active 时整环发光
static func ring(ci: CanvasItem, c: Vector2, rad: float, frac: float, col: Color, active := false, dim := false) -> void:
	ci.draw_circle(c, rad + 3.0, Color(0, 0, 0, 0.55))
	ci.draw_circle(c, rad, Color(0.02, 0.06, 0.11, 0.92))
	var base := Color(col.r, col.g, col.b, 0.18 if not dim else 0.06)
	ci.draw_arc(c, rad - 2.0, 0.0, TAU, 48, base, 3.0)
	if not dim and frac > 0.0:
		var a0 := -PI / 2.0
		ci.draw_arc(c, rad - 2.0, a0, a0 + TAU * clampf(frac, 0.0, 1.0), 48, col, 3.0)
	if active:
		ci.draw_arc(c, rad + 1.0, 0.0, TAU, 48, Color(col.r, col.g, col.b, 0.35), 6.0)
		ci.draw_circle(c, rad - 4.0, Color(col.r, col.g, col.b, 0.16))
	ci.draw_arc(c, rad, 0.0, TAU, 48, EDGE if not dim else EDGE_DIM, 1.0)


## 舷窗（小地图外框）：圆形深蓝底 + 双环 + 四个铆钉
static func porthole(ci: CanvasItem, c: Vector2, rad: float, accent := GLOW) -> void:
	ci.draw_circle(c, rad + 6.0, Color(0.01, 0.04, 0.08, 0.9))
	ci.draw_circle(c, rad, Color(0.02, 0.06, 0.10, 0.78))
	ci.draw_arc(c, rad + 6.0, 0.0, TAU, 64, EDGE_DIM, 2.0)
	ci.draw_arc(c, rad + 2.0, 0.0, TAU, 64, Color(accent.r, accent.g, accent.b, 0.55), 1.0)
	for k in 4:
		var q := c + Vector2.from_angle(PI / 4.0 + k * PI / 2.0) * (rad + 4.0)
		ci.draw_rect(Rect2(q.round() - Vector2(1, 1), Vector2(3, 3)), Color(accent.r, accent.g, accent.b, 0.9))


## 标签片：深底 + 色边 + 文字，返回宽度
static func chip(ci: CanvasItem, font: Font, pos: Vector2, s: String, col: Color, size := 12) -> float:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 14.0
	var r := Rect2(pos, Vector2(w, size + 8))
	ci.draw_rect(r, Color(col.r, col.g, col.b, 0.12))
	ci.draw_rect(r, Color(col.r, col.g, col.b, 0.55), false, 1.0)
	ci.draw_rect(Rect2(pos, Vector2(2, size + 8)), col)
	ci.draw_string(font, pos + Vector2(8, size + 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	return w


## 图标底座：径向光晕 + 暗圆 + 荧光环（卡片图标用）
static func pedestal(ci: CanvasItem, c: Vector2, rad: float, col: Color, t: float, hot := false) -> void:
	var pulse := 0.5 + 0.5 * sin(t * 2.2)
	for k in 4:
		var rr := rad * (1.9 - k * 0.22) + (6.0 * pulse if hot else 0.0)
		ci.draw_circle(c, rr, Color(col.r, col.g, col.b, 0.035 + 0.02 * k))
	ci.draw_circle(c, rad, Color(0.02, 0.06, 0.10, 0.95))
	ci.draw_arc(c, rad, 0.0, TAU, 40, Color(col.r, col.g, col.b, 0.8), 1.5)
	ci.draw_arc(c, rad - 4.0, 0.0, TAU, 40, Color(col.r, col.g, col.b, 0.18), 1.0)
	# 底座下方的一弯托架
	ci.draw_arc(c + Vector2(0, 4), rad + 8.0, PI * 0.2, PI * 0.8, 20, Color(col.r, col.g, col.b, 0.5), 2.0)


## 标题装饰：—◆— 文字 —◆—，带发光
static func heading(ci: CanvasItem, font: Font, center: Vector2, s: String, size: int, col: Color, half_w := 240.0) -> void:
	var tw := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var gap := tw / 2.0 + 26.0
	for sgn in [-1.0, 1.0]:
		var a := center + Vector2(sgn * gap, 0)
		var b := center + Vector2(sgn * half_w, 0)
		ci.draw_line(a, b, Color(col.r, col.g, col.b, 0.5), 1.0)
		diamond(ci, a, 4.0, col)
		diamond(ci, b, 2.5, Color(col.r, col.g, col.b, 0.6))
	ci.draw_string_outline(font, center + Vector2(-tw / 2.0, size * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(0, 0, 0, 0.7))
	ci.draw_string(font, center + Vector2(-tw / 2.0, size * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, TEXT)


## 水波状光带（面板顶部或标题栏用）
static func caustic(ci: CanvasItem, r: Rect2, t: float, col: Color) -> void:
	for k in 3:
		var pts := PackedVector2Array()
		var x := r.position.x
		while x <= r.end.x:
			pts.append(Vector2(x, r.position.y + r.size.y * 0.5 + sin(x * 0.02 + t * (0.8 + k * 0.3) + k * 2.0) * r.size.y * 0.35))
			x += 12.0
		ci.draw_polyline(pts, Color(col.r, col.g, col.b, 0.06 + 0.03 * k), 2.0)
