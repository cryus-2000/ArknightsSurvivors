extends RefCounted
## 局外菜单「T5s」像素风格的公共画法（docs/37 §8、docs/67 §12，10-12 定稿）：标题页磁贴群与难度页共用。
## - 像素字：自画 5×7 位图字（0–9、A–Z、罗马数字用 I / V / X 拼、标点 / : + - % . · 与箭头），编号、英文、档位数字用；
##   中文仍走 ui.ttf。ui.ttf 没有「Ⅷ」字形，档位数字一律经 roman_ascii() 换成 IV / VIII 再用像素字画。
## - 16×16 像素图标（双色：主色 + 青点缀），整数倍放大。
## - 磁贴：四角阶梯切角（每级 1 格）、藏青三阶 Bayer 4×4 有序抖动 + 阶梯描边 + 左上一小段亮青；选中 = 反白 #EEF3F6 + 细青边（S4），
##   只有选中块有发光潮线 + 涨水 + 涟漪（S2 的发光潮线叠在 S4 上）。
## 像素锐利：所有「格」按屏幕像素算（ctx() 取 视口最终变换 × 画布变换，格边长 = round(逻辑格 × 缩放)，位置取整到屏幕像素），
## 手机界面层放大 1.3、窗口非整数缩放时格子仍是整数个屏幕像素，不糊、不出摩尔纹。贴图按「格」分辨率生成（一格一像素），最近邻铺满。

const NAVY := [Color8(18, 40, 68), Color8(11, 26, 48), Color8(6, 14, 30)]       # 藏青三阶：上浅下深
const WATER := [Color8(30, 92, 116), Color8(18, 62, 88), Color8(10, 38, 62)]    # 潮水三阶
const EDGE := Color8(44, 98, 124)
const CY := Color8(96, 224, 232)
const CY_DIM := Color8(70, 140, 160)
const TXT := Color8(228, 236, 244)
const TXT2 := Color8(138, 160, 182)
const SEL := Color8(238, 243, 246)       # S4 反白 #EEF3F6
const SEL_EDGE := Color8(60, 200, 228)   # 细青边
const SEL_INK := Color8(10, 28, 52)      # 反白上的深藏青字
const SEL_SUB := Color8(70, 92, 112)
const SEL_IDX := Color8(24, 130, 160)
const SEL_ICO2 := Color8(30, 150, 180)
const FOAM := Color8(200, 255, 255)
const TIDE_GLOW := Color8(90, 230, 255)
const HALO := Color8(90, 200, 230)
const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

## 5×7 像素字：每行 5 位（高位在左）
const GLYPHS := {
	"A": "0E 11 11 1F 11 11 11", "B": "1E 11 11 1E 11 11 1E", "C": "0E 11 10 10 10 11 0E", "D": "1E 11 11 11 11 11 1E",
	"E": "1F 10 10 1E 10 10 1F", "F": "1F 10 10 1E 10 10 10", "G": "0E 11 10 17 11 11 0F", "H": "11 11 11 1F 11 11 11",
	"I": "0E 04 04 04 04 04 0E", "J": "07 02 02 02 02 12 0C", "K": "11 12 14 18 14 12 11", "L": "10 10 10 10 10 10 1F",
	"M": "11 1B 15 15 11 11 11", "N": "11 11 19 15 13 11 11", "O": "0E 11 11 11 11 11 0E", "P": "1E 11 11 1E 10 10 10",
	"Q": "0E 11 11 11 15 12 0D", "R": "1E 11 11 1E 14 12 11", "S": "0F 10 10 0E 01 01 1E", "T": "1F 04 04 04 04 04 04",
	"U": "11 11 11 11 11 11 0E", "V": "11 11 11 11 11 0A 04", "W": "11 11 11 15 15 15 0A", "X": "11 11 0A 04 0A 11 11",
	"Y": "11 11 11 0A 04 04 04", "Z": "1F 01 02 04 08 10 1F",
	"0": "0E 11 13 15 19 11 0E", "1": "04 0C 04 04 04 04 0E", "2": "0E 11 01 02 04 08 1F", "3": "1F 02 04 02 01 11 0E",
	"4": "02 06 0A 12 1F 02 02", "5": "1F 10 1E 01 01 11 0E", "6": "06 08 10 1E 11 11 0E", "7": "1F 01 02 04 08 08 08",
	"8": "0E 11 11 0E 11 11 0E", "9": "0E 11 11 0F 01 02 0C",
	"/": "01 01 02 04 08 10 10", ".": "00 00 00 00 00 0C 0C", ":": "00 0C 0C 00 0C 0C 00", "-": "00 00 00 1F 00 00 00",
	"+": "00 04 04 1F 04 04 00", "%": "18 19 02 04 08 13 03", ">": "08 04 02 01 02 04 08", "<": "02 04 08 10 08 04 02",
	"(": "02 04 08 08 08 04 02", ")": "08 04 02 02 02 04 08", "&": "0C 12 14 08 15 12 0D", "#": "0A 0A 1F 0A 1F 0A 0A",
	"↑": "04 0E 15 04 04 04 04", "↓": "04 04 04 04 15 0E 04", "←": "00 04 08 1F 08 04 00", "→": "00 04 02 1F 02 04 00",
	"·": "00 00 00 0C 0C 00 00", ",": "00 00 00 00 0C 04 08", "'": "04 04 08 00 00 00 00",   # 逗号 / 撇号：作战记录的千分位、KAL'TSIT（docs/77）
}

## 16×16 像素图标：1 = 主色，2 = 点缀色
const ICONS := {
	"deploy": [
		"................", "................", "................", "..11..11..11....", "...11..11..11...", "....11..11..11..",
		".....11..11..11.", "......11..11..11", "......11..11..11", ".....11..11..11.", "....11..11..11..", "...11..11..11...",
		"..11..11..11....", "................", "................", "................"],
	"hunt": [
		"................", "................", "................", ".11111111111111.", ".1.22........1..", ".1.22.1.1.1..1..",
		".1.22........1..", ".1.22.11111111..", ".1.22........1..", ".1.22.......1...", ".1.22........1..", ".11111111111111.",
		"................", "................", "................", "................"],
	"tree": [
		".......22.......", "......2222......", ".......22.......", ".......11.......", "..22...11...22..", "..221..11..122..",
		"....11.11.11....", "......1111......", ".......11.......", "...22..11..22...", "...221.11.122...", ".....111111.....",
		".......11.......", ".......11.......", ".....111111.....", "................"],
	"gallery": [
		"................", "................", "................", ".11111111111111.", ".1.....11.....1.", ".1.222.11.222.1.",
		".1.....11.....1.", ".1.222.11.222.1.", ".1.....11.....1.", ".1.222.11.222.1.", ".1.....11.....1.", ".1.....11.....1.",
		".11111111111111.", "................", "................", "................"],
	"boss": [
		".......11.......", ".......11.......", "......1111......", "....11.11.11....", "...1...11...1...", "...1........1...",
		"..1..........1..", "11111..22..11111", "11111..22..11111", "..1..........1..", "...1........1...", "...1...11...1...",
		"....11.11.11....", "......1111......", ".......11.......", ".......11......."],
	"guide": [
		"................", "................", "................", "................", "................", "..111111111111..",
		".11..........11.", ".11..2....2..11.", ".11.222......11.", ".11..2......211.", ".11..........11.", ".11111111111111.",
		".1............1.", "................", "................", "................"],
	"settings": [
		"................", ".......11.......", ".......11.......", "...11.1111.11...", "...111....111...", "....1......1....",
		"...1..2222..1...", ".111..2..2..111.", ".111..2..2..111.", "...1..2222..1...", "....1......1....", "...111....111...",
		"...11.1111.11...", ".......11.......", ".......11.......", "................"],
	"exit": [
		"................", "................", "..11111111......", "..1......1......", "..1......1......", "..1........2....",
		"..1.........2...", "..1...222222222.", "..1...222222222.", "..1.........2...", "..1........2....", "..1......1......",
		"..1......1......", "..11111111......", "................", "................"],
}

static var _font_tex: ImageTexture
static var _font_idx := {}
static var _icon_tex := {}     # kind → [layer1, layer2]
static var _cache := {}        # 磁贴 / 水贴图缓存（按格尺寸与状态）
static var _white: ImageTexture


# ------------------------------------------------------------------ 屏幕像素换算
## 画布 → 屏幕像素的变换与缩放（每次 _draw 开头取一次）
static func ctx(ci: CanvasItem) -> Dictionary:
	var x: Transform2D = ci.get_global_transform_with_canvas()
	if DisplayServer.get_name() != "headless":   # 无头窗口只有 64×64，最终变换是 0.05 倍，不能拿来算格子
		x = ci.get_viewport().get_final_transform() * x
	return {"xf": x, "inv": x.affine_inverse(), "k": maxf(0.01, x.get_scale().x)}


## 逻辑格 → 屏幕像素格（至少 1）
static func cell(c: Dictionary, p_log: float) -> int:
	return maxi(1, int(round(p_log * c.k)))


## 本地点 → 取整到屏幕像素后的本地点
static func snap(c: Dictionary, p: Vector2) -> Vector2:
	return c.inv * (c.xf * p).round()


## 本地矩形按 ps 屏幕像素一格对齐：{pos 本地左上, cw, ch 格数, cl 一格的本地长度, rect 本地矩形}
static func grid(c: Dictionary, r: Rect2, ps: int) -> Dictionary:
	var sp: Vector2 = (c.xf * r.position).round()
	var cw := maxi(4, int(round(r.size.x * c.k / ps)))
	var ch := maxi(4, int(round(r.size.y * c.k / ps)))
	var pos: Vector2 = c.inv * sp
	var cl: float = ps / c.k
	return {"pos": pos, "cw": cw, "ch": ch, "cl": cl, "ps": ps, "rect": Rect2(pos, Vector2(cw, ch) * cl)}


static func white() -> ImageTexture:
	if _white == null:
		var im := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		im.fill(Color.WHITE)
		_white = ImageTexture.create_from_image(im)
	return _white


# ------------------------------------------------------------------ 像素字
static func _font() -> void:
	if _font_tex != null:
		return
	var keys: Array = GLYPHS.keys()
	var im := Image.create(keys.size() * 6, 7, false, Image.FORMAT_RGBA8)
	for gi in keys.size():
		var rows: PackedStringArray = str(GLYPHS[keys[gi]]).split(" ")
		for r in 7:
			var bits := ("0x" + rows[r]).hex_to_int()
			for col in 5:
				if bits & (1 << (4 - col)):
					im.set_pixel(gi * 6 + col, r, Color.WHITE)
		_font_idx[keys[gi]] = gi
	_font_tex = ImageTexture.create_from_image(im)


## 罗马数字字符（Ⅰ–Ⅻ）换成 ASCII（像素字只有 I / V / X；ui.ttf 没有 Ⅷ）
static func roman_ascii(s: String) -> String:
	var m := {"Ⅰ": "I", "Ⅱ": "II", "Ⅲ": "III", "Ⅳ": "IV", "Ⅴ": "V", "Ⅵ": "VI", "Ⅶ": "VII", "Ⅷ": "VIII", "Ⅸ": "IX", "Ⅹ": "X", "Ⅺ": "XI", "Ⅻ": "XII"}
	for k in m:
		s = s.replace(k, m[k])
	return s


static func _adv(ch: String, track: int) -> int:
	return (3 if ch == " " else 5) + 1 + track


## 像素字宽度（本地单位）
static func ptext_w(c: Dictionary, s: String, k: float, track := 1) -> float:
	var ks := cell(c, k)
	var w := 0
	for ch in s.to_upper():
		w += _adv(ch, track)
	return maxf(0.0, (w - 1 - track) * ks / c.k)


## 像素字：k = 逻辑倍数（按屏幕取整）；align 0 左 / 1 中 / 2 右；pos.y 是字的竖直中线。返回宽度（本地单位）
static func ptext(ci: CanvasItem, c: Dictionary, pos: Vector2, s: String, k: float, col: Color, track := 1, align := 0) -> float:
	_font()
	s = s.to_upper()
	var ks := cell(c, k)
	var wpx := 0
	for ch in s:
		wpx += _adv(ch, track) * ks
	wpx -= (1 + track) * ks
	var sp: Vector2 = c.xf * pos
	sp.x -= wpx * (0.5 if align == 1 else (1.0 if align == 2 else 0.0))
	sp.y -= 7 * ks * 0.5
	sp = sp.round()
	var gs: Vector2 = Vector2(5, 7) * ks / c.k
	for ch in s:
		if _font_idx.has(ch):
			ci.draw_texture_rect_region(_font_tex, Rect2(c.inv * sp, gs), Rect2(_font_idx[ch] * 6, 0, 5, 7), col)
		sp.x += _adv(ch, track) * ks
	return maxf(0.0, wpx / c.k)


# ------------------------------------------------------------------ 像素图标
static func _icons(kind: String) -> Array:
	if _icon_tex.has(kind):
		return _icon_tex[kind]
	var out := []
	for layer in ["1", "2"]:
		var im := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		var rows: Array = ICONS.get(kind, [])
		for y in rows.size():
			for x in 16:
				if str(rows[y])[x] == layer:
					im.set_pixel(x, y, Color.WHITE)
		out.append(ImageTexture.create_from_image(im))
	_icon_tex[kind] = out
	return out


static func icon(ci: CanvasItem, c: Dictionary, kind: String, center: Vector2, k: float, c1: Color, c2: Color) -> void:
	var ks := cell(c, k)
	var sp: Vector2 = ((c.xf * center) - Vector2(8, 8) * ks).round()
	var r := Rect2(c.inv * sp, Vector2(16, 16) * ks / c.k)
	var tx := _icons(kind)
	ci.draw_texture_rect(tx[0], r, false, c1)
	ci.draw_texture_rect(tx[1], r, false, c2)


## 像素菱形（「更换封面干员」前的小标）
static func pdiamond(ci: CanvasItem, c: Dictionary, center: Vector2, rad: int, ps: int, col: Color) -> void:
	var sp: Vector2 = (c.xf * center).round()
	var cl: float = ps / c.k
	for dy in range(-rad, rad + 1):
		var hw := rad - absi(dy)
		for dx in [-hw, hw]:
			ci.draw_rect(Rect2(c.inv * (sp + Vector2(dx, dy) * ps), Vector2(cl, cl)), col)
			if hw == 0:
				break


# ------------------------------------------------------------------ 阶梯切角磁贴
static func _in(x: int, y: int, cw: int, ch: int, n: int) -> bool:
	if x < 0 or y < 0 or x >= cw or y >= ch:
		return false
	var yy := mini(y, ch - 1 - y)
	if yy >= n:
		return true
	var ins := n - yy
	return x >= ins and x < cw - ins


static func _edge(x: int, y: int, cw: int, ch: int, n: int) -> bool:
	return _in(x, y, cw, ch, n) and not (_in(x - 1, y, cw, ch, n) and _in(x + 1, y, cw, ch, n) and _in(x, y - 1, cw, ch, n) and _in(x, y + 1, cw, ch, n))


static func _px(b: PackedByteArray, i: int, col: Color, a := -1.0) -> void:
	b[i * 4] = col.r8
	b[i * 4 + 1] = col.g8
	b[i * 4 + 2] = col.b8
	b[i * 4 + 3] = int((col.a if a < 0.0 else a) * 255.0)


## 磁贴底贴图（一格一像素）：kind = "rest" 藏青抖动 + 描边 + 左上亮青 / "sel" 反白 + 青边 / "edge_sel" "edge_rest" 只有描边（盖在水上）
## dim：藏青底的不透明度
static func body_tex(cw: int, ch: int, n: int, kind: String, gx0: int, gy0: int, a := 0.91) -> ImageTexture:
	a = snappedf(a, 0.02)   # 透明度在动画里连续变时不必每帧一张新图（相差 < 1% 看不出）
	var key := "%s|%d|%d|%d|%d|%d|%.2f" % [kind, cw, ch, n, posmod(gx0, 4), posmod(gy0, 4), a]
	if _cache.has(key):
		return _cache[key]
	var b := PackedByteArray()
	b.resize(cw * ch * 4)
	for y in ch:
		for x in cw:
			var i := y * cw + x
			if not _in(x, y, cw, ch, n):
				continue
			var e := _edge(x, y, cw, ch, n)
			match kind:
				"rest", "edge_rest":
					if e:
						var acc := y < ch * 0.28 and x < cw * 0.18
						_px(b, i, CY if acc else EDGE, 1.0 if acc else 0.78)
					elif kind == "rest":
						var v := clampf(((y + 0.5) / ch * 0.8 + (x + 0.5) / cw * 0.2) * 2.3 - 0.05, 0.0, 2.0)
						var lv := int(floor(v)) + (1 if (v - floor(v)) * 16.0 > BAYER[posmod(y + gy0, 4) * 4 + posmod(x + gx0, 4)] + 0.5 else 0)
						_px(b, i, NAVY[mini(lv, 2)], a)
				"edge_w":
					if e:
						_px(b, i, Color.WHITE)
				"sel", "edge_sel":
					if e:
						_px(b, i, SEL_EDGE)
					elif kind == "sel":
						_px(b, i, SEL)
	var im := Image.create_from_data(cw, ch, false, Image.FORMAT_RGBA8, b)
	var tx := ImageTexture.create_from_image(im)
	if _cache.size() > 96:
		_cache.clear()
	_cache[key] = tx
	return tx


## 水贴图：第 0 行泡沫、第 1 行发青光的潮线、往下三阶抖动（一格一像素，按列裁取）
static func water_tex(cw: int, rows: int, gx0: int) -> ImageTexture:
	var key := "water|%d|%d|%d" % [cw, rows, posmod(gx0, 4)]
	if _cache.has(key):
		return _cache[key]
	var b := PackedByteArray()
	b.resize(cw * rows * 4)
	for y in rows:
		for x in cw:
			var i := y * cw + x
			if y == 0:
				_px(b, i, FOAM)
			elif y == 1:
				_px(b, i, WATER[0].lerp(TIDE_GLOW, 0.6), 0.97)
			elif y == 2:
				_px(b, i, WATER[0].lerp(TIDE_GLOW, 0.25), 0.94)
			else:
				var v := clampf(float(y - 2) / maxf(1.0, rows - 3) * 2.4, 0.0, 2.0)
				var lv := int(floor(v)) + (1 if (v - floor(v)) * 16.0 > BAYER[posmod(y, 4) * 4 + posmod(x + gx0, 4)] + 0.5 else 0)
				_px(b, i, WATER[mini(lv, 2)], 0.93)
	var tx := ImageTexture.create_from_image(Image.create_from_data(cw, rows, false, Image.FORMAT_RGBA8, b))
	_cache[key] = tx
	return tx


## 一块磁贴：g = grid()；sel 反白；n 切角级数。返回 g
static func tile(ci: CanvasItem, g: Dictionary, n: int, sel: bool, a := 1.0) -> void:
	var gx0 := int(round(g.pos.x / g.cl))
	var gy0 := int(round(g.pos.y / g.cl))
	ci.draw_texture_rect(body_tex(g.cw, g.ch, n, "sel" if sel else "rest", gx0, gy0), g.rect, false, Color(1, 1, 1, a))


## 选中块外一圈台阶式弱青光（3 格，越外越淡）
static func halo(ci: CanvasItem, g: Dictionary, n: int, a := 1.0) -> void:
	var al := [0.25, 0.14, 0.07]
	var cl: float = g.cl
	var r: Rect2 = g.rect
	for k in 3:
		var d := (k + 1) * cl
		var col := Color(HALO.r, HALO.g, HALO.b, al[k] * a)
		var ins := (n + 1) * cl
		ci.draw_rect(Rect2(r.position.x + ins, r.position.y - d, r.size.x - ins * 2, cl), col)
		ci.draw_rect(Rect2(r.position.x + ins, r.end.y + d - cl, r.size.x - ins * 2, cl), col)
		ci.draw_rect(Rect2(r.position.x - d, r.position.y + ins, cl, r.size.y - ins * 2), col)
		ci.draw_rect(Rect2(r.end.x + d - cl, r.position.y + ins, cl, r.size.y - ins * 2), col)


## 潮水：level 0–1（相对选中水位 frac）；phase 浪的相位（减少动态时传常数）。返回浪顶所在格行（-1 = 没水）
static func water(ci: CanvasItem, g: Dictionary, n: int, frac: float, level: float, phase: float, sel: bool) -> int:
	if level <= 0.01:
		return -1
	var ch: int = g.ch
	var full := maxi(3, int(round(ch * frac)))
	var base := ch - 1 - int(round(full * level))
	water_rows(ci, g, n, base, full + 5, phase, "edge_sel" if sel else "edge_rest")
	return base


## 潮水（按浪顶格行 base 画到底）：rows = 水贴图行数（≥ 最大水深 + 浪高），edge_kind = 画完后补回的描边贴图（"" 不补）
static func water_rows(ci: CanvasItem, g: Dictionary, n: int, base: int, rows: int, phase: float, edge_kind: String) -> void:
	var cw: int = g.cw
	var ch: int = g.ch
	var gx0 := int(round(g.pos.x / g.cl))
	var wt := water_tex(cw, rows, gx0)
	var cl: float = g.cl
	var x := 1
	while x < cw - 1:
		var gx := x + gx0
		var crest := base + int(round(sin(gx * 0.45 + phase) * 0.8 + sin(gx * 0.17 + 1.3 + phase * 0.5) * 0.6))
		var m := mini(x, cw - 1 - x)
		var bottom := ch - 2 - maxi(0, n - m)
		# 同浪顶、同底的相邻列合并成一次绘制
		var x2 := x + 1
		while x2 < cw - 1:
			var gx2 := x2 + gx0
			var c2 := base + int(round(sin(gx2 * 0.45 + phase) * 0.8 + sin(gx2 * 0.17 + 1.3 + phase * 0.5) * 0.6))
			if c2 != crest or ch - 2 - maxi(0, n - mini(x2, cw - 1 - x2)) != bottom:
				break
			x2 += 1
		crest = maxi(crest, 1)
		var depth := mini(bottom - crest + 1, rows)
		if depth > 0:
			ci.draw_texture_rect_region(wt, Rect2(g.pos + Vector2(x, crest) * cl, Vector2(x2 - x, depth) * cl), Rect2(x, 0, x2 - x, depth))
		x = x2
	# 水盖住的角上描边补回来
	if edge_kind != "":
		var gy0 := int(round(g.pos.y / g.cl))
		ci.draw_texture_rect(body_tex(cw, ch, n, edge_kind, gx0, gy0), g.rect, false)


## 涟漪：浪顶处三圈压扁的断续像素环；p = 扩散进度 0–1
static func ripple(ci: CanvasItem, g: Dictionary, n: int, cx: float, crest_row: int, rad: float, p: float) -> void:
	if crest_row < 0 or p <= 0.0:
		return
	var cl: float = g.cl
	var cw: int = g.cw
	var ch: int = g.ch
	var ccx: float = (cx - g.pos.x) / cl
	var al := [0.86, 0.6, 0.32]
	var rr := [rad * 0.32, rad * 0.63, rad]
	for j in 3:
		var r: float = rr[j] / cl * (0.35 + 0.65 * p)
		var a: float = al[j] * (1.0 - 0.35 * p if j == 0 else 1.0) * clampf(p * 3.0, 0.0, 1.0)
		var col := Color(FOAM.r, FOAM.g, FOAM.b, a)
		var col_up := Color(SEL_EDGE.r, SEL_EDGE.g, SEL_EDGE.b, a * 0.8)   # 浪顶以上（反白底）用青色，泡沫色在白底上看不见
		var deg := 0
		while deg < 360:
			if (deg / 20 + j) % 4 != 3:
				var ang := deg_to_rad(deg)
				var px := int(round(ccx + cos(ang) * r))
				var py := int(round(crest_row + sin(ang) * r * 0.28))
				if px > 0 and px < cw - 1 and py > 0 and py < ch - 1 and _in(px, py, cw, ch, n + 1):
					ci.draw_rect(Rect2(g.pos + Vector2(px, py) * cl, Vector2(cl, cl)), col if py > crest_row else col_up)
			deg += 5


## 深色小面板（难度页的潮位尺、修正项卡、按钮）：抖动藏青 + 阶梯描边（无左上亮青）
## fade：整块淡入淡出用乘色，不进贴图缓存键（10-25 帧率审计：作战记录整屏底板按淡入的透明度每帧重烘一张全屏贴图，一次几百毫秒）
static func panel(ci: CanvasItem, g: Dictionary, n: int, a := 0.92, fade := 1.0) -> void:
	var gx0 := int(round(g.pos.x / g.cl))
	var gy0 := int(round(g.pos.y / g.cl))
	ci.draw_texture_rect(body_tex(g.cw, g.ch, n, "rest", gx0, gy0, a), g.rect, false, Color(1, 1, 1, fade))


## 描边换色（按钮的强调边）：用描边贴图乘色
static func outline(ci: CanvasItem, g: Dictionary, n: int, col: Color) -> void:
	var gx0 := int(round(g.pos.x / g.cl))
	var gy0 := int(round(g.pos.y / g.cl))
	ci.draw_texture_rect(body_tex(g.cw, g.ch, n, "edge_w", gx0, gy0), g.rect, false, col)
