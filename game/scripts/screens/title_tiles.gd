extends RefCounted
## 标题页磁贴群（T5s，docs/67 §12，10-12 定稿）：放在左侧 Logo 下方（原纵向菜单的位置），keyart 与人物不动。
## 三行：[集结出发] / [图鉴][Boss 演练] / [操作说明][设置][退出]；哪几项出现由 title.gd _menu_ids() 决定（对外包没有 Boss 演练、
## 网页 / 手机没有退出），某一行只剩一块时它占满整行；编号按可见顺序连号（01…）。
## 导航（docs/67 §10.3）：↑↓ 换行并落到「水平位置最近」的那块（记住上次所在列：03 ↑ 01 ↓ 回 03），← → 行内移动，不循环；
## Tab / Shift+Tab 按可见顺序线性走。命中区始终是终态位置（docs/62 §2.5）。

const T = preload("res://scripts/screens/tide_ui.gd")
const UI = preload("res://scripts/ui.gd")

## 菜单表（docs/126 A2，10-22）：加一个局外入口 = 这里加一行（id 接着编、row 定在哪一行，行内按表里的先后）+ title.gd _activate 加一支；
## 若是盖在标题上的界面，再登记进 title.gd 的 _overlays()。id 是 title.gd sel / item_rects / menu_water 的下标，不重排旧 id。
## 6 = 认知塑造（局外成长 P2，docs/109 §4）：放在第二行图鉴 / Boss 演练之后
const MENU := [
	{"id": 0, "cn": "集结出发", "en": "DEPLOY", "icon": "deploy", "row": 0},
	{"id": 1, "cn": "图鉴", "en": "GALLERY", "icon": "gallery", "row": 1},
	{"id": 2, "cn": "Boss 演练", "en": "BOSS TRIAL", "icon": "boss", "row": 1},
	{"id": 3, "cn": "操作说明", "en": "GUIDE", "icon": "guide", "row": 2},
	{"id": 4, "cn": "设置", "en": "SETTINGS", "icon": "settings", "row": 2},
	{"id": 5, "cn": "退出", "en": "EXIT", "icon": "exit", "row": 2},
	{"id": 6, "cn": "认知塑造", "en": "SHAPING", "icon": "tree", "row": 1},
]
static var CN: Array = _col("cn")
static var EN: Array = _col("en")
static var ICON: Array = _col("icon")


## 按 id 取 MENU 的一列（下标 = id）
static func _col(k: String) -> Array:
	var out: Array = []
	out.resize(MENU.size())
	for m in MENU:
		out[int(m.id)] = m[k]
	return out


## 全部 id 按显示顺序（逐行，行内按表序）
static func order() -> Array:
	var out: Array = []
	for r in 3:
		for m in MENU:
			if int(m.row) == r:
				out.append(int(m.id))
	return out
const SUB0 := "选择干员与难度，走进深海"
## 设计尺寸（1280×720）：大 / 中 / 小号高度与缝
const HB := 146.0
const HM := 92.0
const HS := 54.0
const GAP := 8.0
## 选中块水位（占磁贴高度）
const FRAC := {"big": 0.22, "mid": 0.22, "small": 0.24}


## 按可见项分行（空行去掉）
static func rows(ids: Array) -> Array:
	var out: Array = []
	for row in 3:
		var r: Array = []
		for m in MENU:
			if int(m.row) == row and ids.has(int(m.id)):
				r.append(int(m.id))
		if not r.is_empty():
			out.append(r)
	return out


## 排版：x0 / y0 左上，w 宽，avail 可用高度；touch：小号至少 46 高（触控下限）
## 返回 {rects: {id: Rect2}, size: {id: "big"/"mid"/"small"}, rows, f, num: {id: 显示编号}, bottom}
static func layout(ids: Array, x0: float, y0: float, w: float, avail: float, touch: bool) -> Dictionary:
	var rs := rows(ids)
	var hb := HB
	var hm := HM
	var hs := HS
	var f := clampf((avail - GAP * 2.0) / (HB + HM + HS), 0.5, 1.0)
	hb *= f
	hm *= f
	hs *= f
	var g := maxf(5.0, GAP * f)
	if touch and hs < 46.0:
		var f2 := clampf((avail - g * 2.0 - 46.0) / (HB + HM), 0.4, 1.0)
		hb = HB * f2
		hm = HM * f2
		hs = 46.0
		f = f2
	var rects := {}
	var sizes := {}
	var num := {}
	var y := y0
	var n := 1
	for ri in rs.size():
		var row: Array = rs[ri]
		var kind := "big" if row.has(0) else ("mid" if (row.has(1) or row.has(2) or row.has(6)) else "small")
		var h: float = hb if kind == "big" else (hm if kind == "mid" else hs)
		var cw := (w - g * (row.size() - 1)) / row.size()
		for k in row.size():
			var id: int = row[k]
			rects[id] = Rect2(x0 + k * (cw + g), y, cw, h).abs()
			sizes[id] = kind
			num[id] = n
			n += 1
		y += h + g
	return {"rects": rects, "size": sizes, "rows": rs, "f": f, "num": num, "bottom": y - g, "w": w}


## 二维导航：dir = Vector2i；mem_x = 记住的列（屏幕 x 中心）。返回 [新选中, 新 mem_x]
static func nav(lay: Dictionary, sel: int, dir: Vector2i, mem_x: float) -> Array:
	var rs: Array = lay.rows
	var ri := -1
	for i in rs.size():
		if rs[i].has(sel):
			ri = i
	if ri < 0:
		return [rs[0][0], mem_x]
	var row: Array = rs[ri]
	if dir.x != 0:
		var k := clampi(row.find(sel) + dir.x, 0, row.size() - 1)
		var ns: int = row[k]
		return [ns, (lay.rects[ns] as Rect2).get_center().x]
	if dir.y != 0:
		var nr := ri + dir.y
		if nr < 0 or nr >= rs.size():
			return [sel, mem_x]
		var best: int = rs[nr][0]
		var bd := INF
		for id in rs[nr]:
			var d := absf((lay.rects[id] as Rect2).get_center().x - mem_x)
			if d < bd - 0.5:   # 等距取左边那块（05 ↑ → 02）
				bd = d
				best = id
		return [best, mem_x]
	return [sel, mem_x]


## Tab 线性：按可见顺序
static func linear(ids: Array, sel: int, d: int) -> int:
	return ids[posmod(ids.find(sel) + d, ids.size())]


## 画整个磁贴群。st：{sel, water: Array[6] 0–1, rip_t: 选中开始时刻（界面时钟）, now, rise: Array[6] 0–1（冒出水面的进度）,
## text_a: Array[6]（文字透明度）, phase, font}
static func draw(ci: CanvasItem, lay: Dictionary, st: Dictionary) -> void:
	var c := T.ctx(ci)
	var f: float = lay.f
	var big_ui := f >= 0.8
	var ps := T.cell(c, 2.0 if big_ui else 1.4)
	var k1 := 1.0 if big_ui else 1.4   # 小号像素字（手机按屏幕至少 2 像素一格）
	var font: Font = st.font
	var sel: int = st.sel
	# 先画未选中，再画选中（光晕压在邻居上方一点）
	var order: Array = []
	for id in lay.rects:
		if id != sel:
			order.append(id)
	if lay.rects.has(sel):
		order.append(sel)
	for id in order:
		var r: Rect2 = lay.rects[id]
		var kind: String = lay.size[id]
		var n := 3 if kind != "small" else 2
		var on: bool = id == sel
		var rise: float = st.rise[id]
		if rise <= 0.0:
			continue
		var g := T.grid(c, r, ps)
		if rise < 1.0:
			_surface(ci, g, n, on, rise)
			continue
		if on:
			T.halo(ci, g, n)
		T.tile(ci, g, n, on)
		var wl: float = st.water[id]
		var frac: float = 0.2 if (kind == "small" and not big_ui) else FRAC[kind]   # 手机小号磁贴矮（46），水位压低一点，不淹英文
		var crest := T.water(ci, g, n, frac, UI_ease(wl), st.phase, on)
		var ta: float = st.text_a[id]
		var ink := T.SEL_INK if on else T.TXT
		var sub := T.SEL_SUB if on else T.TXT2
		var idx := T.SEL_IDX if on else T.CY
		var ico := T.SEL_INK if on else Color8(200, 226, 238)
		var ico2 := T.SEL_ICO2 if on else T.CY
		ink.a *= ta
		sub.a *= ta
		idx.a *= ta
		ico.a *= ta
		ico2.a *= ta
		var rr: Rect2 = g.rect
		var x0 := rr.position.x
		var y0 := rr.position.y
		var w := rr.size.x
		var h := rr.size.y
		var nums := "%02d" % int(lay.num[id])
		var crest_y: float = (rr.position.y + crest * g.cl) if crest >= 0 else rr.end.y
		var rip_p: float = clampf((st.now - st.rip_t) / 0.6, 0.0, 1.0) if on else 0.0
		rip_p = 1.0 - pow(1.0 - rip_p, 3.0)
		if st.get("rm", false) and on:
			rip_p = 1.0
		match kind:
			"big":
				var kb := 2.0 if big_ui else 1.4
				var wi := T.ptext(ci, c, Vector2(x0 + 18 * f, y0 + 18 * f), nums, kb, idx)
				T.ptext(ci, c, Vector2(x0 + 18 * f + wi + 8, y0 + 18 * f), "// OPERATION", k1, sub)
				var cs := int(34 * f)
				UI.text(ci, font, Vector2(x0 + 16 * f, y0 + 52 * f + cs * 0.36), CN[id], cs, ink)
				T.ptext(ci, c, Vector2(x0 + 19 * f, y0 + 82 * f), EN[id], kb, ink, 2)
				if big_ui:
					UI.text(ci, font, Vector2(x0 + 18 * f, y0 + 100 * f + 5), SUB0, 14, sub)
				var icx := rr.end.x - 46 * f
				if on:
					T.ripple(ci, g, n, icx, crest, 40.0 * f, rip_p)
				var icy: float = (crest_y - 22 * f) if crest >= 0 else y0 + h * 0.56
				T.icon(ci, c, ICON[id], Vector2(icx, icy), 3.0 if big_ui else 2.0, ico, ico2)
			"mid":
				var km := 2.0 if big_ui else 1.4
				T.ptext(ci, c, Vector2(x0 + 14 * f, y0 + 16 * f), nums, km, idx)
				T.icon(ci, c, ICON[id], Vector2(rr.end.x - 24 * f, y0 + 24 * f), km, ico, ico2)
				var cs := int(22 * f) if big_ui else int(maxf(16.0, 22 * f))
				# 一行三块（图鉴 / Boss 演练 / 认知塑造）时块窄：缩字，不压右上角图标
				while cs > 14 and font.get_string_size(CN[id], HORIZONTAL_ALIGNMENT_LEFT, -1, UI.fs(cs)).x > w - 14 * f - 36 * km:
					cs -= 1
				UI.text(ci, font, Vector2(x0 + 14 * f, y0 + 44 * f + cs * 0.36), CN[id], cs, ink)
				T.ptext(ci, c, Vector2(x0 + 16 * f, y0 + 64 * f + (0.0 if big_ui else 5.0)), EN[id], k1, ink, 2)
				if on:
					T.ripple(ci, g, n, rr.end.x - 40 * f, crest, 30.0 * f, rip_p)
			_:
				var ks := 2.0 if big_ui else 1.4
				if on:
					T.ripple(ci, g, n, x0 + 20 * f, crest, 20.0 * f, rip_p)
				T.icon(ci, c, ICON[id], Vector2(x0 + 20 * maxf(f, 0.8), y0 + h / 2 - 4 * minf(f, 1.0)), ks, ico, ico2)
				var cs := int(16 * f) if big_ui else 15
				var tx := x0 + 38 * maxf(f, 0.8)
				var cy0 := (h / 2 - 6 * minf(f, 1.0)) if big_ui else (h / 2 - 10.0)
				var ey0 := (h / 2 + 9 * minf(f, 1.0)) if big_ui else (h / 2 + 8.0)
				UI.text(ci, font, Vector2(tx, y0 + cy0 + cs * 0.36), CN[id], cs, ink)
				T.ptext(ci, c, Vector2(tx + 1, y0 + ey0), EN[id], k1, sub)
				T.ptext(ci, c, Vector2(rr.end.x - 8 * f, y0 + 8 * f), nums, k1, idx, 1, 2)


## 入场：磁贴从潮线下「浮出」——终态底边是一条水线，磁贴自下而上露出（只露水线以上的部分），水线上一排泡沫
static func _surface(ci: CanvasItem, g: Dictionary, n: int, on: bool, p: float) -> void:
	var ch: int = g.ch
	var vis := int(round(ch * p))
	if vis <= 0:
		return
	var gx0 := int(round(g.pos.x / g.cl))
	var gy0 := int(round(g.pos.y / g.cl))
	var tx := T.body_tex(g.cw, ch, n, "sel" if on else "rest", gx0, gy0)
	var cl: float = g.cl
	var dst := Rect2(g.pos + Vector2(0, ch - vis) * cl, Vector2(g.cw, vis) * cl)
	ci.draw_texture_rect_region(tx, dst, Rect2(0, 0, g.cw, vis))
	# 水线：终态底边一排断续泡沫
	var y: float = g.rect.end.y - cl
	var x := 1
	while x < g.cw - 1:
		if (x * 7) % 11 > 1:
			ci.draw_rect(Rect2(g.pos.x + x * cl, y, cl, cl), Color(T.FOAM.r, T.FOAM.g, T.FOAM.b, 0.8 * (1.0 - p * 0.6)))
		x += 1


static func UI_ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)
