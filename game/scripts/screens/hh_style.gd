extends RefCounted
## 寻访 / 结算定稿的视觉语言（docs/125 §6，10-22 用户以 GPT 寻访概念图 27–33 为准）：
## 左白右黑斜切分栏、「| 01 / 人事寻访」小标 + 大黑字中文 + 像素描边英文、RHODES ISLAND HUMAN RESOURCE DEPARTMENT 小字、
## 顶栏灰块 + 警示条 + 黄色斜标签、职业色顶条的平行四边形卡、灰色像素剪影 + LOCKED、青色主按钮、右上「返回 Esc」。
## 全部静态函数；坐标是调用方的界面单位，s = 版面缩放（桌面 720 高 = 1）。像素字用 tide_ui 的 5×7 字（按屏幕像素取整）。

const UI = preload("res://scripts/ui.gd")
const TUI = preload("res://scripts/screens/tide_ui.gd")

const DARK := Color8(19, 23, 30)          # 右侧暗场
const DARK2 := Color8(27, 32, 41)         # 卡底
const DARK3 := Color8(36, 42, 53)
const LIGHT := Color8(223, 226, 230)      # 左侧浅灰面板
const LIGHT2 := Color8(206, 210, 215)
const INK := Color8(17, 19, 24)
const INK2 := Color8(92, 97, 106)
const MUTE := Color8(150, 156, 166)
const YEL := Color8(255, 206, 0)          # 标题标签 / 新加入（同图鉴警示黄）
const CYB := Color8(56, 214, 240)         # 主按钮青
const RIB := Color8(24, 120, 214)         # 罗德岛蓝：进入转场的斜切色块（10-22 用户：不用警示黄）
const SIL := Color8(118, 123, 132)        # 剪影灰
const SKEW := 0.18                        # 平行四边形斜率（每 1 高度右移 0.18）
const GLITCH := "#/_<>01:=+"               # 解码中的乱码字符（像素字与 ui.ttf 都有）

## 转场「文字解码 / 逐字打出」进度（docs/124 §12）：调用方在画一屏前设好、画完复位为 1。< 1 时标题、英文、编号逐字出现，
## 已出现的最后两格是乱码（英文 / 编号），中文只逐字出现不乱码
static var reveal := 1.0
static var glitch_seed := 0


## 按 reveal 截字：英文 / 编号把正在出现的两格换成乱码
static func dec(s: String, latin := true) -> String:
	if reveal >= 1.0:
		return s
	var n := int(ceil(s.length() * clampf(reveal, 0.0, 1.0)))
	var out := s.substr(0, maxi(0, n - (2 if latin else 0)))
	if latin:
		for i in range(maxi(0, n - 2), n):
			if s[i] == " ":
				out += " "
			else:
				out += GLITCH[absi(hash([glitch_seed, i])) % GLITCH.length()]
	return out


## 填充多边形（先看能否三角化：斜块扫出画面边、窄卡斜切时会退化成自交 / 零面积；带 tag 时退化会打印出来，便于定位）
static var poly_debug := false


static func fill(ci: CanvasItem, pts: PackedVector2Array, col: Color, tag := "") -> void:
	if Geometry2D.triangulate_polygon(pts).is_empty():
		if poly_debug:
			print("HHPOLY bad %s %s" % [tag, pts])
		return
	ci.draw_colored_polygon(pts, col)


## 背景：暗场 + 几道很淡的斜带
static func backdrop(ci: CanvasItem, vs: Vector2) -> void:
	ci.draw_rect(Rect2(Vector2.ZERO, vs), DARK)
	for i in 5:
		var x := vs.x * (0.3 + 0.16 * i)
		fill(ci, PackedVector2Array([Vector2(x, 0), Vector2(x + vs.x * 0.06, 0), Vector2(x + vs.x * 0.06 - vs.y * 0.35, vs.y), Vector2(x - vs.y * 0.35, vs.y)]), Color(1, 1, 1, 0.022))


## 左侧浅灰斜切面板：上边宽 wt、下边宽 wb，从 y0 到底；外侧再一道浅色细带
static func left_panel(ci: CanvasItem, vs: Vector2, wt: float, wb: float, y0: float) -> void:
	fill(ci, PackedVector2Array([Vector2(0, y0), Vector2(wt + 26, y0), Vector2(wb + 26, vs.y), Vector2(0, vs.y)]), LIGHT2)
	fill(ci, PackedVector2Array([Vector2(0, y0), Vector2(wt, y0), Vector2(wb, vs.y), Vector2(0, vs.y)]), LIGHT)


## 右侧浅灰斜切面板（人事调度函 / 揭示用）
static func right_panel(ci: CanvasItem, vs: Vector2, xt: float, xb: float, y0: float, y1 := -1.0) -> void:
	var yb := vs.y if y1 < 0 else y1
	fill(ci, PackedVector2Array([Vector2(xt, y0), Vector2(vs.x, y0), Vector2(vs.x, yb), Vector2(xb, yb)]), LIGHT)


## 顶栏：左灰块两行英文 + 警示条 + 黄色斜标签（标题）；右「01 / 01」+ 平行四边形返回键。返回返回键矩形
static func topbar(ci: CanvasItem, font: Font, vs: Vector2, en: Array, title: String, s := 1.0, page := "01 / 01", back := "返回  Esc") -> Rect2:
	var h := 62.0 * s
	ci.draw_rect(Rect2(0, 0, vs.x, h), Color8(14, 17, 22))
	ci.draw_rect(Rect2(0, h - 2, vs.x, 2), Color(1, 1, 1, 0.5))
	var bw := 160.0 * s
	ci.draw_rect(Rect2(0, 0, bw, h - 2), LIGHT2)
	for i in en.size():
		spaced(ci, font, Vector2(26 * s, (20 + 18 * i) * s), dec(str(en[i])), int(10 * s), INK, 2.0)
	UI.hazard(ci, Rect2(bw, 0, 28 * s, h - 2), 0.0, YEL, INK, 9.0 * s)
	var tw := UI.cwidth(font, title, int(22 * s)) + 44 * s
	para(ci, Rect2(bw + 40 * s, 10 * s, tw, h - 22 * s), YEL)
	UI.text_at(ci, font, Vector2(bw + 62 * s, h / 2.0 - 1), dec(title, false), int(22 * s), INK, "lm", true)
	if page != "":
		spaced(ci, font, Vector2(vs.x - 250 * s, h / 2.0 + 5 * s), page, int(10 * s), MUTE, 3.0)
	var br := Rect2(vs.x - 160 * s, 12 * s, 140 * s, h - 26 * s)
	if back == "":
		return Rect2()
	para(ci, br, Color(0, 0, 0, 0), Color(1, 1, 1, 0.8))
	var bk: Array = UI.split_key(back)   # 10-31 TA H7：「返回  Esc」→ 按钮只写「返回」，ESC 进左内侧的按键牌
	UI.text_at(ci, font, br.get_center(), bk[0], int(15 * s), UI.TEXT, "mm", true)
	UI.btn_key(ci, font, br, bk[1], UI.SUB, 10, br.size.y * SKEW + 10.0 * s)
	return br


## 平行四边形（左下 → 右上斜），fill / line 可空
static func para(ci: CanvasItem, r: Rect2, fill: Color, line := Color(0, 0, 0, 0), w := 1.5) -> void:
	if r.size.x < 1.0 or r.size.y < 1.0:
		return
	var k := minf(r.size.y * SKEW, r.size.x - 1.0)   # 比斜切量还窄（卡片翻入中）就收斜切，免得多边形自交、三角化失败
	var p := PackedVector2Array([Vector2(r.position.x + k, r.position.y), Vector2(r.end.x, r.position.y), Vector2(r.end.x - k, r.end.y), Vector2(r.position.x, r.end.y)])
	if fill.a > 0.0:
		fill(ci, p, fill)
	if line.a > 0.0:
		p.append(p[0])
		ci.draw_polyline(p, line, w)


## 字距拉开的小字（英文 / 中文都行）
static func spaced(ci: CanvasItem, font: Font, pos: Vector2, s: String, size: int, col: Color, gap := 4.0) -> float:
	var x := pos.x
	for ch in s:
		ci.draw_string(font, Vector2(x, pos.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + gap
	return x - pos.x


## 标题块：「| 01 / 人 事 寻 访」+ 大黑字中文 + 像素描边英文 + 一道短黑线；返回块底 y
static func title_block(ci: CanvasItem, font: Font, p: Vector2, idx: String, sub: String, cn: String, en: String, s := 1.0, cn_size := 76, ink := INK, line := INK2) -> float:
	ci.draw_rect(Rect2(p.x, p.y - 12 * s, 3 * s, 16 * s), ink)
	var w := spaced(ci, font, Vector2(p.x + 16 * s, p.y + 2 * s), dec(idx + "  /  "), int(13 * s), ink, 3.0)
	spaced(ci, font, Vector2(p.x + 16 * s + w, p.y + 2 * s), dec(sub, false), int(13 * s), ink, 6.0)
	UI.text_at(ci, font, Vector2(p.x - 4 * s, p.y + 24 * s), dec(cn, false), int(cn_size * s), ink, "la", true)
	var ey := p.y + 24 * s + cn_size * s * 1.32
	var ek := 2.0 * s * (cn_size / 76.0) * 4.6 / 2.0
	outline_px(ci, Vector2(p.x, ey + 18 * s * cn_size / 76.0), dec(en), ek, line, LIGHT if ink == INK else DARK)
	var by := ey + 48 * s * cn_size / 76.0
	ci.draw_rect(Rect2(p.x, by, 58 * s, 4 * s), ink)
	return by + 4 * s


## 像素描边英文（5×7 像素字画一圈描边、中间填底色）：k = 每个字像素的界面单位
static func outline_px(ci: CanvasItem, pos: Vector2, s: String, k: float, line: Color, fill: Color) -> float:
	var c := TUI.ctx(ci)
	var d := maxf(1.0, k / 3.0)
	for o in [Vector2(-d, 0), Vector2(d, 0), Vector2(0, -d), Vector2(0, d), Vector2(-d, -d), Vector2(d, d), Vector2(-d, d), Vector2(d, -d)]:
		TUI.ptext(ci, c, pos + o, s, k, line, 1)
	return TUI.ptext(ci, c, pos, s, k, fill, 1)


## 像素实心英文
static func solid_px(ci: CanvasItem, pos: Vector2, s: String, k: float, col: Color, align := 0) -> float:
	return TUI.ptext(ci, TUI.ctx(ci), pos, s, k, col, 1, align)


## 人事部小字三行（RHODES ISLAND / HUMAN RESOURCE / DEPARTMENT）+ 短线
static func hr_mark(ci: CanvasItem, font: Font, p: Vector2, s := 1.0, col := INK2, lines := ["RHODES ISLAND", "HUMAN RESOURCE", "DEPARTMENT"]) -> void:
	for i in lines.size():
		spaced(ci, font, Vector2(p.x, p.y + i * 15 * s), str(lines[i]), int(9 * s), col, 3.0)
	ci.draw_rect(Rect2(p.x, p.y + lines.size() * 15 * s, 16 * s, 1.5 * s), col)


## 职业卡：平行四边形暗卡 + 顶部职业色条 + 右上小斜杠；sel = 浅色底 + 青边 + 四角小菱形
static func card(ci: CanvasItem, r: Rect2, top: Color, sel := false, dim := false) -> void:
	var a := 0.45 if dim else 1.0
	para(ci, r, LIGHT if sel else UI.fa(DARK2, 0.96), Color(1, 1, 1, 0.16 * a) if not sel else Color(0, 0, 0, 0))
	var k := r.size.y * SKEW
	if r.size.x < k + 30.0:   # 翻入中的窄卡只画底板
		return
	fill(ci, PackedVector2Array([Vector2(r.position.x + k, r.position.y - 6), Vector2(r.end.x, r.position.y - 6), Vector2(r.end.x - 1.1, r.position.y), Vector2(r.position.x + k - 1.1, r.position.y)]), UI.fa(top, a))
	ci.draw_line(Vector2(r.end.x - 18, r.position.y + 18), Vector2(r.end.x - 10, r.position.y + 10), UI.fa(top, a), 2.0)
	fill(ci, PackedVector2Array([Vector2(r.end.x - k - 14, r.end.y), Vector2(r.end.x - k, r.end.y), Vector2(r.end.x - k + 14 * SKEW * 4, r.end.y - 14)]), Color(1, 1, 1, 0.12 * a))
	if sel:
		para(ci, r.grow(4), Color(0, 0, 0, 0), CYB, 2.5)
		for c in [Vector2(r.position.x + k - 2, r.position.y - 4), Vector2(r.end.x + 4, r.position.y - 4), Vector2(r.position.x - 4, r.end.y + 4), Vector2(r.end.x - k + 2, r.end.y + 4)]:
			UI.diamond(ci, c, 4.0, CYB)


## 主按钮（青色平行四边形：文字 + 键位 + ›）
static func main_btn(ci: CanvasItem, font: Font, r: Rect2, text: String, key := "Enter", s := 1.0) -> void:
	para(ci, r, CYB)
	var size := int(22 * s)
	var tw := UI.cwidth(font, text, size)
	var x := r.get_center().x - (tw + 34 * s) / 2.0
	UI.text_at(ci, font, Vector2(x, r.get_center().y), text, size, INK, "lm", true)
	UI.btn_key(ci, font, r, key, UI.fa(INK, 0.7), 10, r.size.y * SKEW + 12.0 * s)   # 10-31 TA H7：键名不进按钮文字，左内侧一个按键牌
	chevron(ci, Vector2(r.end.x - r.size.y * SKEW - 26 * s, r.get_center().y), 6 * s, INK)


## 次按钮（描边平行四边形）
static func ghost_btn(ci: CanvasItem, font: Font, r: Rect2, text: String, key := "", s := 1.0, dark := true) -> void:
	var col := UI.TEXT if dark else INK
	para(ci, r, Color(0, 0, 0, 0.35) if dark else Color(1, 1, 1, 0.5), UI.fa(col, 0.85), 1.5)
	var tw := UI.cwidth(font, text, int(17 * s))
	var x := r.get_center().x - tw / 2.0
	UI.text_at(ci, font, Vector2(x, r.get_center().y), text, int(17 * s), col, "lm", true)
	UI.btn_key(ci, font, r, key, UI.fa(col, 0.6), 10, r.size.y * SKEW + 10.0 * s)   # 10-31 TA H7：键名不进按钮文字


static func chevron(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.5, -r), c + Vector2(r * 0.5, 0), c + Vector2(-r * 0.5, r)]), col, maxf(2.0, r * 0.4))


## 底栏：暗条 + 顶部细线
static func bottom_bar(ci: CanvasItem, vs: Vector2, h: float) -> void:
	ci.draw_rect(Rect2(0, vs.y - h, vs.x, h), Color8(14, 17, 22))
	ci.draw_rect(Rect2(0, vs.y - h, vs.x, 1.5), Color(1, 1, 1, 0.35))


## 寻访凭证图标（像素票面：白底 + 青色条 + 编号孔，斜放 10°）。不改画布变换（调用方可能在缩放版面里）
static func voucher(ci: CanvasItem, c: Vector2, s: float) -> void:
	var rot := Transform2D(deg_to_rad(-10.0), c)
	var quad := func(r: Rect2, col: Color) -> void:
		fill(ci, PackedVector2Array([rot * r.position, rot * Vector2(r.end.x, r.position.y), rot * r.end, rot * Vector2(r.position.x, r.end.y)]), col)
	var rr := Rect2(-Vector2(30, 16) * s, Vector2(60, 32) * s)
	quad.call(rr.grow(2 * s), INK)
	quad.call(rr, Color8(240, 244, 248))
	quad.call(Rect2(rr.position + Vector2(4, 4) * s, Vector2(8, 24) * s), CYB)
	quad.call(Rect2(rr.position + Vector2(18, 18) * s, Vector2(34, 6) * s), Color8(40, 90, 200))
	for i in 3:
		quad.call(Rect2(rr.position + Vector2(20 + i * 8, 8) * s, Vector2(4, 4) * s), INK)


## 黄色小标签（新加入 / 新职业）
static func tag(ci: CanvasItem, font: Font, p: Vector2, text: String, s := 1.0, col := YEL) -> float:
	var w := UI.cwidth(font, text, int(14 * s)) + 22 * s
	para(ci, Rect2(p, Vector2(w, 26 * s)), col)
	UI.text_at(ci, font, p + Vector2(w / 2.0, 13 * s), text, int(14 * s), INK, "mm", true)
	return w
