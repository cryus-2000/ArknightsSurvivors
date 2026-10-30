extends RefCounted
## 界面绘制工具（2026-09-26 改版 · 方案 A「潮汐航线」）：仿《水月与深蓝之树》局内界面——
## 炭灰半透明平面板、白色线性图标、数值上方的彩色小标签头、「英文压缩字 + 中文」节点标签条。
## 语义色：青 = 可选 / 主操作，紫 = 当前，洋红 = 危险，金 = 灯火，绿 = 源石锭。
## 旧接口（frame / panel / chip / gbar / ring / pedestal / heading …）都保留，外观统一换成 A。

const BG := Color(0.063, 0.071, 0.086, 0.86)
const BG2 := Color(0.094, 0.106, 0.125, 0.9)
const LINE := Color(1.0, 1.0, 1.0, 0.16)
const CYAN := Color(0.212, 0.886, 0.863)        # #36e2dc 可选 / 主操作
const CYAN_DIM := Color(0.36, 0.62, 0.64)
const GOLD := Color(0.957, 0.753, 0.306)        # #f4c04e 灯火
const RED := Color(1.0, 0.239, 0.545)           # #ff3d8b 危险（原作「险路恶敌」的洋红）
const PURPLE := Color(0.66, 0.52, 1.0)          # 旧淡紫：水月 S3 发动光环、干员标签等仍在用，保持不变
const VIOLET := Color(0.486, 0.42, 1.0)         # #7c6bff 当前（原作地图上「当前节点」的紫）
const GREEN := Color(0.184, 0.827, 0.627)       # #2fd3a0 源石锭
const TEXT := Color(0.949, 0.957, 0.961)
const SUB := Color(0.604, 0.639, 0.678)         # #9aa3ad
const STEEL := Color(0.494, 0.596, 0.722)       # #7e98b8 普通按钮底
const TAB_HP := Color(0.09, 0.56, 0.65)         # 小标签头：生命值
const TAB_LAMP := Color(0.72, 0.53, 0.04)       # 小标签头：灯火
## 多行文字折行规则（文字要先过 soft()）：中文没有空格，soft() 在字与字之间插零宽空格当词界，这里只在词界断行；
## 一个「词」整行都放不下时才按字断（ADAPTIVE）。不能加 BREAK_GRAPHEME_BOUND：它允许在任意两个字之间断行，
## soft() 的「标点不放行首」就失效了（行首出现「、」「；」）
const BRK: int = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE

const CAT_COL := {"灯火": Color(1.0, 0.77, 0.42), "战斗": Color(0.33, 0.92, 0.88), "生存": Color(0.55, 0.9, 0.55), "海嗣": Color(0.66, 0.52, 1.0),
	# 藏品分类（docs/197：data/relics.json 的 lane_names，7 条流派 + 职业 / 通用 / 经济；「生存」与上面共用）
	"近战扩域": Color(1.0, 0.62, 0.4), "多弹火力": Color(0.33, 0.92, 0.88), "召唤驻场": Color(0.66, 0.52, 1.0), "控场引爆": Color(0.5, 0.75, 1.0),
	"弱点收割": Color(1.0, 0.55, 0.55), "护盾反击": Color(0.6, 0.85, 1.0), "治疗转伤": Color(1.0, 0.7, 0.9),
	"职业": Color(0.95, 0.78, 0.5), "通用": Color(0.8, 0.8, 0.85), "经济": Color(1.0, 0.85, 0.4)}
## 藏品分类的英文标签（卡片左上角节点标签条用）
const CAT_EN := {"灯火": "LIGHT", "战斗": "COMBAT", "生存": "SURVIVAL", "海嗣": "SEABORN",
	"近战扩域": "MELEE", "多弹火力": "BARRAGE", "召唤驻场": "SUMMON", "控场引爆": "CONTROL", "弱点收割": "WEAKNESS", "护盾反击": "SHIELD",
	"治疗转伤": "HEALING", "职业": "CLASS", "通用": "GENERAL", "经济": "ECONOMY"}

# 兼容旧代码的色名（外观已换成 A）
const EDGE := Color(1.0, 1.0, 1.0, 0.24)
const EDGE_DIM := Color(1.0, 1.0, 1.0, 0.12)
const GLOW := CYAN


# ---------------------------------------------------------------- 字体
## 英文压缩字：原作英文小标签是窄体粗字（Bender / Novecento 一类）。本作不额外带字体文件，
## 用 FontVariation 把 UI 字体横向压到 0.82 倍、略加粗；italic 再斜一点（节点标签条用）。
static var _cond := {}
static var _cond_italic := {}
## HUD 合批段（性能，协调人 9/30；hud.gd batch_begin / batch_end）：sink 非空时下面这些助手的色块 / 圆 / 弧 / 线写进
## 三角形批（hud.gd 的 Tris），tq 非空时文字延后（追加成 Callable，批提交后再画，保证字压在色块上）。平时都是 null，行为不变
static var sink = null
static var tq = null
## tq 也可以是 screens/hud_textq.gd（docs/50 §13 HUD 合批）：字按字体 / 字号 / 描边归组，段末同组连着画；为 Array 时照旧逐条延后
const TextQ = preload("res://scripts/screens/hud_textq.gd")
## 手机横屏正文字号放大（用户 10-13「手机版的字可以放大一点」）：局内（game.gd）在 Cfg.phone_ui() 时设为 balance.json ui/phone_font_mult，
## 离开局内恢复 1；桌面、平板、标题页恒为 1，排版逐像素不变。只放大正文类字号：< FS_CAP 的字号乘倍率、封顶 FS_CAP，
## 大标题（≥ FS_CAP）与英文小标签（en / en_width）不变。画字的助手只对 Control（HUD / 面板 / 设置 / 卡片）放大，
## 世界层（Node2D 上的头顶字）不变；量字的助手（cwidth / wrap_lines / fit / fit_line / chip_fits / strip_width）按同一倍率量，
## 调用方自己用 font.get_string_size 量、再交给这些助手画的地方要改用 fs() 换算
## 10-26 用户 iPhone 实机（Safari 横屏，1 界面像素约 0.6 pt）：放大后仍不到 FS_MIN 的小字（9–10 号的标签）一律抬到 FS_MIN
static var fk := 1.0
const FS_CAP := 24
const FS_MIN := 13


## 正文字号换算：手机局内放大（不小于 FS_MIN），其余原样
static func fs(size: int) -> int:
	if fk == 1.0 or size >= FS_CAP:
		return size
	return clampi(int(round(size * fk)), FS_MIN, FS_CAP)


static func _ks(ci: CanvasItem, size: int) -> int:
	return fs(size) if fk != 1.0 and ci is Control else size


static func cond(base: Font, italic := false) -> Font:
	var cache: Dictionary = _cond_italic if italic else _cond
	var cached = cache.get(base)
	if cached != null:
		return cached
	var fv := FontVariation.new()
	fv.base_font = base
	# 这个变换按 FreeType 矩阵解释（x' = xx·x + xy·y），所以斜体的切变量放在 x_axis.y
	fv.variation_transform = Transform2D(Vector2(0.82, 0.2 if italic else 0.0), Vector2(0.0, 1.0), Vector2.ZERO)
	fv.variation_embolden = 0.35
	cache[base] = fv
	return fv


## 压缩字文字（数字、英文）
static func ctext(ci: CanvasItem, font: Font, pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, italic := false) -> void:
	if tq != null:
		if tq is Array:
			tq.append(func(): ctext(ci, font, pos, s, size, col, align, width, italic))
		else:
			var cf := cond(font, italic)
			var ks := _ks(ci, size)
			tq.add(false, TextQ.key(cf, ks), func(): ci.draw_string(cf, pos, s, align, width, ks, col))
		return
	ci.draw_string(cond(font, italic), pos, s, align, width, _ks(ci, size), col)


static func cwidth(font: Font, s: String, size: int, italic := false) -> float:
	return cond(font, italic).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs(size)).x


## 英文小标签（压缩字 + 字距）
static func en(ci: CanvasItem, font: Font, pos: Vector2, text: String, size: int, col: Color, spacing := 2.0, italic := false) -> float:
	if tq != null:
		if tq is Array:
			tq.append(func(): en(ci, font, pos, text, size, col, spacing, italic))
		else:
			var cf := cond(font, italic)
			tq.add(false, TextQ.key(cf, size), func(): _en_draw(ci, cf, pos, text, size, col, spacing))
		return en_width(font, text, size, spacing)
	var f := cond(font, italic)
	var x := pos.x
	for ch in text:
		ci.draw_string(f, Vector2(x, pos.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
		x += f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + spacing
	return x - pos.x


static func _en_draw(ci: CanvasItem, f: Font, pos: Vector2, text: String, size: int, col: Color, spacing: float) -> void:
	var x := pos.x
	for ch in text:
		ci.draw_string(f, Vector2(x, pos.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
		x += f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + spacing


static func en_width(font: Font, text: String, size: int, spacing := 2.0) -> float:
	var f := cond(font)
	var w := 0.0
	for ch in text:
		w += f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + spacing
	return w


static func text(ci: CanvasItem, font: Font, pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, outline := 0) -> void:
	if tq != null:
		if tq is Array:
			tq.append(func(): text(ci, font, pos, s, size, col, align, width, outline))
		else:
			var ks := _ks(ci, size)
			if outline > 0:
				tq.add(true, TextQ.key(font, ks, outline), func(): ci.draw_string_outline(font, pos, s, align, width, ks, outline, Color(0, 0, 0, col.a * 0.8)))
			tq.add(false, TextQ.key(font, ks), func(): ci.draw_string(font, pos, s, align, width, ks, col))
		return
	size = _ks(ci, size)
	if outline > 0:
		ci.draw_string_outline(font, pos, s, align, width, size, outline, Color(0, 0, 0, col.a * 0.8))
	ci.draw_string(font, pos, s, align, width, size, col)


## 中文自动换行：在每个 CJK 字符后插入零宽空格（U+200B）作为换行机会，
## 避免文本服务把整段中文当成一个「词」、只在空格处换行（表现为第一行极短）。
## 不在开头标点（《「（）后、也不在结尾标点（》」，。）前插入，避免标点悬在行首。
## 弯引号（10-30 招募卡简介「……冲锋”，对她来说」把后引号甩到了行首）：后引号不放行首、前引号不留行尾
const _NO_BREAK_AFTER := "《「『（【〈“‘"
const _NO_BREAK_BEFORE := "》」』）】〉，。、；：！？”’…"
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
			out += "​"
	return out


# ---------------------------------------------------------------- 面板
## 通用面板：统一走 frame。accent 给了就作为强调色并带外发光
static func panel(ci: CanvasItem, r: Rect2, fill := BG, border := LINE, cut := 10.0, accent := Color(0, 0, 0, 0), vines_seed := 0, t := 0.0) -> void:
	var main := accent if accent.a > 0.0 else Color(border.r, border.g, border.b, 1.0)
	frame(ci, r, main, {"alpha": clampf(fill.a / 0.86, 0.3, 1.0), "glow": 0.6 if accent.a > 0.0 else 0.0})


## A 风格面板：炭灰半透明平面（上略亮下略暗）+ 顶部一线高光 + 1px 细边，左上角一小段强调色。
## glow > 0（悬停 / 选中）：细边换成强调色并加外晕。旧参数 cut / bracket / vines / t 仍接受，不再画切角与藤蔓。
static func frame(ci: CanvasItem, r: Rect2, accent := CYAN, opts := {}) -> void:
	var a: float = opts.get("alpha", 1.0)
	var glow_k: float = opts.get("glow", 0.0)
	if glow_k > 0.0:
		for k in 3:
			ci.draw_rect(r.grow(2.0 + k * 3.0), Color(accent.r, accent.g, accent.b, (0.12 - k * 0.035) * glow_k * a), false, 3.0)
	var top := Color(0.118, 0.129, 0.153, 0.93 * a)
	var bot := Color(0.059, 0.067, 0.082, 0.93 * a)
	ci.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([top, top, bot, bot]))
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), Color(1, 1, 1, 0.13 * a))
	var edge := Color(1, 1, 1, 0.12).lerp(Color(accent.r, accent.g, accent.b, 0.4), 0.25)
	if glow_k > 0.4:
		edge = Color(accent.r, accent.g, accent.b, 0.95)
	ci.draw_rect(r, Color(edge.r, edge.g, edge.b, edge.a * a), false, 1.0)
	# 左上角强调色短线（分类色提示）
	ci.draw_rect(Rect2(r.position, Vector2(minf(14.0, r.size.x * 0.3), 2)), Color(accent.r, accent.g, accent.b, 0.9 * a))


## 藤蔓（旧深海风装饰；A 风格不再调用，保留函数以免旧代码报错）
static func vines(_ci: CanvasItem, _r: Rect2, _seed: int, _t: float, _k := 1.0) -> void:
	pass


## 小标签头（原作「目标生命值 / 指挥等级」）：彩色底 + 白字，放在数值上方；返回宽度
static func tab(ci: CanvasItem, font: Font, pos: Vector2, s: String, bg: Color, size := 11) -> float:
	size = _ks(ci, size)
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 12.0
	if sink != null:
		sink.rect(Rect2(pos, Vector2(w, size + 6)), bg)
	else:
		ci.draw_rect(Rect2(pos, Vector2(w, size + 6)), bg)
	if tq != null:
		var tf := func(): ci.draw_string(font, pos + Vector2(6, size + 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 1, 1, bg.a))
		if tq is Array:
			tq.append(tf)
		else:
			tq.add(false, TextQ.key(font, size), tf)
	else:
		ci.draw_string(font, pos + Vector2(6, size + 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 1, 1, bg.a))
	return w


## 节点标签条（原作地图上的「COMBAT OPS. ✕ 虫群横行」）：左段彩色底 + 压缩斜体英文，右段暗底中文；返回宽度
static func strip(ci: CanvasItem, font: Font, pos: Vector2, en_s: String, cn: String, col: Color, cn_col := TEXT, size := 12, bg := Color(0.0, 0.0, 0.0, 0.6)) -> float:
	size = _ks(ci, size)
	var cf := cond(font, true)
	var h := size + 8.0
	var ew := cf.get_string_size(en_s, HORIZONTAL_ALIGNMENT_LEFT, -1, size - 1).x + 13.0 if en_s != "" else 0.0
	var cw := font.get_string_size(cn, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 15.0 if cn != "" else 0.0
	if sink != null and tq != null:
		sink.rect(Rect2(pos, Vector2(ew + cw, h)), Color(bg.r, bg.g, bg.b, bg.a * col.a))
		if en_s != "":
			sink.rect(Rect2(pos, Vector2(ew, h)), col)
		if tq is Array:
			tq.append(func(): _strip_text(ci, font, cf, pos, h, ew, en_s, cn, col, cn_col, size))
		else:
			if en_s != "":
				tq.add(false, TextQ.key(cf, size - 1), func(): _strip_text(ci, font, cf, pos, h, ew, en_s, "", col, cn_col, size))
			if cn != "":
				tq.add(false, TextQ.key(font, size), func(): _strip_text(ci, font, cf, pos, h, ew, "", cn, col, cn_col, size))
		return ew + cw
	ci.draw_rect(Rect2(pos, Vector2(ew + cw, h)), Color(bg.r, bg.g, bg.b, bg.a * col.a))
	if en_s != "":
		ci.draw_rect(Rect2(pos, Vector2(ew, h)), col)
	_strip_text(ci, font, cf, pos, h, ew, en_s, cn, col, cn_col, size)
	return ew + cw


static func _strip_text(ci: CanvasItem, font: Font, cf: Font, pos: Vector2, h: float, ew: float, en_s: String, cn: String, col: Color, cn_col: Color, size: int) -> void:
	if en_s != "":
		var ink := Color(0.04, 0.07, 0.08, col.a) if col.get_luminance() > 0.45 else Color(1, 1, 1, col.a)
		ci.draw_string(cf, pos + Vector2(6, h - 5), en_s, HORIZONTAL_ALIGNMENT_LEFT, -1, size - 1, ink)
	if cn != "":
		ci.draw_string(font, pos + Vector2(ew + 7, h - 5), cn, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(cn_col.r, cn_col.g, cn_col.b, cn_col.a * col.a))


## 标签片：暗底 + 左侧色条 + 文字，返回宽度
static func chip(ci: CanvasItem, font: Font, pos: Vector2, s: String, col: Color, size := 12) -> float:
	return _chip(ci, font, pos, s, col, _ks(ci, size))


static func _chip(ci: CanvasItem, font: Font, pos: Vector2, s: String, col: Color, size: int) -> float:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 16.0
	var r := Rect2(pos, Vector2(w, size + 8))
	ci.draw_rect(r, Color(0.03, 0.035, 0.045, 0.8 * col.a))
	ci.draw_rect(Rect2(pos, Vector2(3, size + 8)), col)
	ci.draw_string(font, pos + Vector2(9, size + 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(col.r, col.g, col.b, col.a).lerp(Color(TEXT.r, TEXT.g, TEXT.b, col.a), 0.3))
	return w


## 一组标签片排成至多 rows 行、每行居中（选卡 / 商店卡片底部的作用对象）：chips = [[文字, 颜色]…]，
## bot_c 为整块的底边中点（行数变了底边不动，贴着下面的操作条）。第一行前面可带灰色小字 label；
## 放不下先去掉 label，再放不下把末尾收成「+N」，单个也放不下就截断加「…」。返回用了几行
static func chip_row(ci: CanvasItem, font: Font, bot_c: Vector2, chips: Array, max_w: float, rows := 1, label := "", size := 11, a := 1.0) -> int:
	if chips.is_empty():
		return 0
	size = _ks(ci, size)
	var lay := _chip_layout(font, chips, max_w, rows, label, size)
	var packed: Array = lay.packed
	var lw: float = lay.lw
	var h := size + 8.0
	var y0: float = bot_c.y - packed.size() * (h + 4.0) + 4.0
	for j in packed.size():
		var row: Array = packed[j]
		var w := (lw if j == 0 else 0.0) + 4.0 * (row.size() - 1)
		for it in row:
			w += it[2]
		var p := Vector2(bot_c.x - w / 2.0, y0 + j * (h + 4.0)).round()
		if j == 0 and lw > 0.0:
			ci.draw_string(font, p + Vector2(0, size + 2), label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(SUB.r, SUB.g, SUB.b, a))
			p.x += lw
		for it in row:
			if it.size() > 3:
				# 「+N」：细边框
				ci.draw_rect(Rect2(p, Vector2(it[2], h)), Color(1, 1, 1, 0.22 * a), false, 1.0)
				ci.draw_string(font, p + Vector2(6, size + 2), it[0], HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(SUB.r, SUB.g, SUB.b, a))
			else:
				var col: Color = it[1]
				_chip(ci, font, p, it[0], Color(col.r, col.g, col.b, col.a * a), size)
			p.x += it[2] + 4.0
	return packed.size()


## chip_row 能否不收起（不出现「+N」、不截断）地放下全部标签片；放不下时调用方可以在悬停提示里列全
static func chip_fits(font: Font, chips: Array, max_w: float, rows := 1, size := 11) -> bool:
	return chips.is_empty() or not _pack_chips(_chip_items(font, chips, fs(size)), max_w, rows, 0.0).is_empty()


static func _chip_items(font: Font, chips: Array, size: int) -> Array:
	return chips.map(func(c): return [c[0], c[1], font.get_string_size(c[0], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 16.0])


## chip_row 的排版：{packed: 每行的标签片 [文字, 颜色, 宽度, (是「+N」)], lw: 第一行 label 占的宽度（去掉了为 0）}
static func _chip_layout(font: Font, chips: Array, max_w: float, rows: int, label: String, size: int) -> Dictionary:
	var items := _chip_items(font, chips, size)
	var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 6.0 if label != "" else 0.0
	var packed := _pack_chips(items, max_w, rows, lw)
	if packed.is_empty() and lw > 0.0:
		lw = 0.0
		packed = _pack_chips(items, max_w, rows, 0.0)
	var k := items.size() - 1
	while packed.is_empty() and k >= 1:
		var more := "+%d" % (items.size() - k)
		packed = _pack_chips(items.slice(0, k) + [[more, SUB, font.get_string_size(more, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 12.0, true]], max_w, rows, 0.0)
		k -= 1
	if packed.is_empty():
		var fl := _fit_line(font, items[0][0], size, max_w - 16.0, size)
		packed = [[[fl[0], items[0][1], font.get_string_size(fl[0], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 16.0]]]
	return {"packed": packed, "lw": lw}


## chip_row 的排版：按顺序装进至多 rows 行（第一行先让出 label 的宽度）；装不下返回空数组
static func _pack_chips(items: Array, max_w: float, rows: int, lw: float) -> Array:
	var out: Array = [[]]
	var x := lw
	for it in items:
		var need: float = it[2] + (4.0 if not out[-1].is_empty() else 0.0)
		if x + need > max_w and not out[-1].is_empty():
			if out.size() >= rows:
				return []
			out.append([])
			x = 0.0
			need = it[2]
		if x + need > max_w:
			return []
		out[-1].append(it)
		x += need
	return out


## 按键牌：细边框里的按键名（SPACE / Esc / 1）；返回宽度
## 按钮上的按键牌（10-31 TA 审阅 docs/208 H7：按钮文字里不夹键名、卡面价签不写 [n]）：按钮左内侧一个小按键牌（细框 + 大写键名），
## 不和文字混写；inset = 离按钮左沿的距离（平行四边形按钮要让开斜边）。触屏不画，key 为空不画
static func btn_key(ci: CanvasItem, font: Font, r: Rect2, key: String, col := SUB, size := 10, inset := 10.0) -> void:
	if key == "" or _touch_ui():
		return
	var k := key.to_upper()
	keycap(ci, font, Vector2(r.position.x + inset, r.get_center().y - (_ks(ci, size) + 7) / 2.0), k, col, size)


## 触屏界面（Pad.touch_ui）：ui.gd 也给不带自动加载的测试脚本用，这里按节点名找 Pad，找不到当作非触屏
static func _touch_ui() -> bool:
	var ml := Engine.get_main_loop()
	var pad: Node = (ml as SceneTree).root.get_node_or_null("Pad") if ml is SceneTree else null
	return pad != null and pad.touch_ui()


## 「标签  键名」拆成 [标签, 键名]（两个以上空格分隔；没有键名返回 [s, ""]）
static func split_key(s: String) -> Array:
	var i := s.find("  ")
	if i < 0:
		return [s, ""]
	return [s.substr(0, i).strip_edges(), s.substr(i).strip_edges()]


static func keycap(ci: CanvasItem, font: Font, pos: Vector2, key: String, col := TEXT, size := 11) -> float:
	size = _ks(ci, size)
	var w := cond(font).get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 12.0
	if sink != null and tq != null:
		sink.frame(Rect2(pos, Vector2(w, size + 7)), Color(col.r, col.g, col.b, 0.55 * col.a), 1.0)
		var kf := func(): ci.draw_string(cond(font), pos + Vector2(6, size + 2), key, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
		if tq is Array:
			tq.append(kf)
		else:
			tq.add(false, TextQ.key(cond(font), size), kf)
		return w
	ci.draw_rect(Rect2(pos, Vector2(w, size + 7)), Color(col.r, col.g, col.b, 0.55 * col.a), false, 1.0)
	ci.draw_string(cond(font), pos + Vector2(6, size + 2), key, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	return w


## A 风格按钮：kind = "primary"（青底深字）/ "normal"（钢蓝半透明底）/ "outline"（暗底细边）/ "off"（禁用）
static func button(ci: CanvasItem, font: Font, r: Rect2, s: String, kind := "normal", hot := false, size := 15, a := 1.0) -> void:
	size = _ks(ci, size)
	var fg := Color(1, 1, 1, a)
	match kind:
		"primary":
			ci.draw_rect(r, Color(CYAN.r, CYAN.g, CYAN.b, a))
			fg = Color(0.04, 0.07, 0.09, a)
		"normal":
			ci.draw_rect(r, Color(STEEL.r, STEEL.g, STEEL.b, (0.55 if hot else 0.38) * a))
		"outline":
			ci.draw_rect(r, Color(0.03, 0.04, 0.05, 0.8 * a))
			ci.draw_rect(r, Color(1, 1, 1, (0.6 if hot else 0.3) * a), false, 1.0)
		_:
			ci.draw_rect(r, Color(0.2, 0.22, 0.25, 0.5 * a))
			fg = Color(SUB.r, SUB.g, SUB.b, 0.7 * a)
	if hot and kind != "off":
		ci.draw_rect(r.grow(2.0), Color(CYAN.r, CYAN.g, CYAN.b, 0.35 * a), false, 1.0)
	ci.draw_string(font, Vector2(r.position.x, r.position.y + r.size.y / 2.0 + size * 0.36), s, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, size, fg)


# ---------------------------------------------------------------- 条 / 环 / 光环
## 细条：暗槽 + 实色填充 + 顶部高光
static func bar(ci: CanvasItem, r: Rect2, frac: float, col: Color, segments := 0) -> void:
	gbar(ci, r, frac, col, segments)


## 进度条：暗槽 + 实色填充 + 顶部高光 + 淡外晕；trail 为残影比例（掉血用）
static func gbar(ci: CanvasItem, r: Rect2, frac: float, col: Color, segments := 0, trail := -1.0) -> void:
	frac = clampf(frac, 0.0, 1.0)
	if sink != null:
		sink.rect(r, Color(1, 1, 1, 0.12 * col.a))
		if trail > frac:
			sink.rect(Rect2(r.position, Vector2(r.size.x * clampf(trail, 0.0, 1.0), r.size.y)), Color(1, 1, 1, 0.6 * col.a))
		var sfw := r.size.x * frac
		if sfw > 0.0:
			sink.rect(Rect2(r.position - Vector2(0, 1), Vector2(sfw, r.size.y + 2)), Color(col.r, col.g, col.b, 0.2 * col.a))
			sink.rect(Rect2(r.position, Vector2(sfw, r.size.y)), col)
			sink.rect(Rect2(r.position, Vector2(sfw, 1)), Color(col.lightened(0.45).r, col.lightened(0.45).g, col.lightened(0.45).b, col.a))
		if segments > 1:
			for i in range(1, segments):
				sink.rect(Rect2(Vector2(r.position.x + r.size.x * i / segments, r.position.y), Vector2(1, r.size.y)), Color(0, 0, 0, 0.45 * col.a))
		return
	ci.draw_rect(r, Color(1, 1, 1, 0.12 * col.a))
	if trail > frac:
		ci.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(trail, 0.0, 1.0), r.size.y)), Color(1, 1, 1, 0.6 * col.a))
	var fw := r.size.x * frac
	if fw > 0.0:
		ci.draw_rect(Rect2(r.position - Vector2(0, 1), Vector2(fw, r.size.y + 2)), Color(col.r, col.g, col.b, 0.2 * col.a))
		ci.draw_rect(Rect2(r.position, Vector2(fw, r.size.y)), col)
		ci.draw_rect(Rect2(r.position, Vector2(fw, 1)), Color(col.lightened(0.45).r, col.lightened(0.45).g, col.lightened(0.45).b, col.a))
	if segments > 1:
		for i in range(1, segments):
			var x := r.position.x + r.size.x * i / segments
			ci.draw_rect(Rect2(Vector2(x, r.position.y), Vector2(1, r.size.y)), Color(0, 0, 0, 0.45 * col.a))


## 圆形进度环：暗底 + 外圈细轨 + 进度弧；active 时整环发光
static func ring(ci: CanvasItem, c: Vector2, rad: float, frac: float, col: Color, active := false, dim := false) -> void:
	if sink != null:
		sink.circle(c, rad, Color(0.04, 0.047, 0.059, 0.9), 32)
		sink.arc(c, rad, 0.0, TAU, 1.0, Color(1, 1, 1, 0.08 if dim else 0.2), 48)
		sink.arc(c, rad + 2.5, 0.0, TAU, 2.0, Color(1, 1, 1, 0.05 if dim else 0.12), 48)
		if not dim and frac > 0.0:
			sink.arc(c, rad + 2.5, -PI / 2.0, -PI / 2.0 + TAU * clampf(frac, 0.0, 1.0), 2.0, col, 48)
		if active:
			sink.arc(c, rad + 5.0, 0.0, TAU, 3.0, Color(col.r, col.g, col.b, 0.35), 48)
			sink.circle(c, rad - 2.0, Color(col.r, col.g, col.b, 0.14), 32)
		return
	ci.draw_circle(c, rad, Color(0.04, 0.047, 0.059, 0.9))
	ci.draw_arc(c, rad, 0.0, TAU, 48, Color(1, 1, 1, 0.08 if dim else 0.2), 1.0)
	ci.draw_arc(c, rad + 2.5, 0.0, TAU, 48, Color(1, 1, 1, 0.05 if dim else 0.12), 2.0)
	if not dim and frac > 0.0:
		var a0 := -PI / 2.0
		ci.draw_arc(c, rad + 2.5, a0, a0 + TAU * clampf(frac, 0.0, 1.0), 48, col, 2.0)
	if active:
		ci.draw_arc(c, rad + 5.0, 0.0, TAU, 48, Color(col.r, col.g, col.b, 0.35), 3.0)
		ci.draw_circle(c, rad - 2.0, Color(col.r, col.g, col.b, 0.14))


## 声呐外框：暗色半透明圆 + 细白环 + 虚线十字
static func porthole(ci: CanvasItem, c: Vector2, rad: float, _accent := CYAN) -> void:
	ci.draw_circle(c, rad, Color(0.03, 0.035, 0.045, 0.62))
	ci.draw_arc(c, rad, 0.0, TAU, 72, Color(1, 1, 1, 0.34), 1.0)
	ci.draw_arc(c, rad * 0.64, 0.0, TAU, 56, Color(1, 1, 1, 0.1), 1.0)
	for k in 4:
		var d := Vector2.from_angle(k * PI / 2.0)
		var s := 0.0
		while s < rad - 4.0:
			ci.draw_line(c + d * s, c + d * minf(s + 3.0, rad - 4.0), Color(1, 1, 1, 0.1), 1.0)
			s += 7.0


## 图标光环（原作「选择支援」卡：细圆环 + 放射细线）；hot 时线更长更亮并带强调色外晕
static func halo(ci: CanvasItem, c: Vector2, rad: float, col: Color, hot := false, a := 1.0) -> void:
	if hot:
		for k in 4:
			ci.draw_circle(c, rad * (1.55 - k * 0.14), Color(col.r, col.g, col.b, 0.045 * a))
	ci.draw_circle(c, rad, Color(1, 1, 1, 0.03 * a))
	ci.draw_arc(c, rad, 0.0, TAU, 64, Color(1, 1, 1, 0.24 * a), 1.0)
	var r0 := rad + 7.0
	var r1 := rad + (19.0 if hot else 14.0)
	var la := (0.55 if hot else 0.28) * a
	for i in 60:
		var d := Vector2.from_angle(TAU * i / 60.0)
		ci.draw_line(c + d * r0, c + d * r1, Color(1, 1, 1, la), 1.0)
	for i in 12:
		var d := Vector2.from_angle(TAU * i / 12.0 + 0.13)
		ci.draw_line(c + d * (r1 + 3.0), c + d * (r1 + 11.0), Color(1, 1, 1, (0.6 if hot else 0.24) * a), 1.0)


## 图标底座（旧接口）：换成光环
static func pedestal(ci: CanvasItem, c: Vector2, rad: float, col: Color, _t: float, hot := false) -> void:
	halo(ci, c, rad, col, hot, col.a)


# ---------------------------------------------------------------- 装饰
static func diamond(ci: CanvasItem, c: Vector2, rad: float, fill: Color, border := Color(0, 0, 0, 0)) -> void:
	if sink != null:
		sink.diamond(c, rad, fill, border)
		return
	var p := PackedVector2Array([c + Vector2(0, -rad), c + Vector2(rad, 0), c + Vector2(0, rad), c + Vector2(-rad, 0)])
	ci.draw_colored_polygon(p, fill)
	if border.a > 0.0:
		p.append(p[0])
		ci.draw_polyline(p, border, 1.0)


## 横向装饰线：细线中间一个小菱形
static func rule(ci: CanvasItem, a: Vector2, b: Vector2, col: Color) -> void:
	var m := (a + b) / 2.0
	ci.draw_line(a, m - Vector2(7, 0), Color(col.r, col.g, col.b, col.a * 0.7), 1.0)
	ci.draw_line(m + Vector2(7, 0), b, Color(col.r, col.g, col.b, col.a * 0.7), 1.0)
	diamond(ci, m, 3.0, col)


## 渐隐细线（从 a 到 b 透明度由 a0 过渡到 a1）
static func hairline(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, a0 := 0.4, a1 := 0.0) -> void:
	ci.draw_polygon(PackedVector2Array([a - Vector2(0, 0.5), b - Vector2(0, 0.5), b + Vector2(0, 0.5), a + Vector2(0, 0.5)]),
		PackedColorArray([Color(col.r, col.g, col.b, a0), Color(col.r, col.g, col.b, a1), Color(col.r, col.g, col.b, a1), Color(col.r, col.g, col.b, a0)]))


## 两端渐隐的暗底带（顶栏计时、横幅用）：中间实色，左右 edge 像素内淡出
static func fade_band(ci: CanvasItem, r: Rect2, col: Color, edge := 50.0) -> void:
	var c0 := Color(col.r, col.g, col.b, 0.0)
	var x0 := r.position.x
	var x1 := r.end.x
	var y0 := r.position.y
	var y1 := r.end.y
	var e := minf(edge, r.size.x / 2.0)
	if sink != null:
		sink.quad4([Vector2(x0, y0), Vector2(x0 + e, y0), Vector2(x0 + e, y1), Vector2(x0, y1)], [c0, col, col, c0])
		sink.rect(Rect2(Vector2(x0 + e, y0), Vector2(r.size.x - 2.0 * e, r.size.y)), col)
		sink.quad4([Vector2(x1 - e, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x1 - e, y1)], [col, c0, c0, col])
		return
	ci.draw_polygon(PackedVector2Array([Vector2(x0, y0), Vector2(x0 + e, y0), Vector2(x0 + e, y1), Vector2(x0, y1)]), PackedColorArray([c0, col, col, c0]))
	ci.draw_rect(Rect2(Vector2(x0 + e, y0), Vector2(r.size.x - 2.0 * e, r.size.y)), col)
	ci.draw_polygon(PackedVector2Array([Vector2(x1 - e, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x1 - e, y1)]), PackedColorArray([col, c0, c0, col]))


## 面板标题（原作「选择支援」）：居中白字，两侧渐隐细线，靠近文字处各一小段粗白线
static func heading(ci: CanvasItem, font: Font, center: Vector2, s: String, size: int, _col: Color, half_w := 240.0) -> void:
	var tw := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var gap := tw / 2.0 + 24.0
	for sgn in [-1.0, 1.0]:
		var a := center + Vector2(sgn * gap, 0)
		var b := center + Vector2(sgn * half_w, 0)
		hairline(ci, a, b, Color(1, 1, 1), 0.42, 0.0)
		ci.draw_rect(Rect2(a + Vector2(0.0 if sgn > 0 else -14.0, -1.5), Vector2(14, 3)), Color(1, 1, 1, 0.95))
	ci.draw_string_outline(font, center + Vector2(-tw / 2.0, size * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(0, 0, 0, 0.6))
	ci.draw_string(font, center + Vector2(-tw / 2.0, size * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, TEXT)


## 水波光带（旧深海风装饰；A 风格不画）
static func caustic(_ci: CanvasItem, _r: Rect2, _t: float, _col: Color) -> void:
	pass


## 四叶环（原作节点地图背景的四瓣环线），楼层名背后的淡徽记
static func quatrefoil(ci: CanvasItem, c: Vector2, s: float, col: Color, w := 1.5) -> void:
	var rp := s * 0.42
	var d := s * 0.5
	for k in 4:
		var th := k * PI / 2.0 - PI / 4.0
		var pc := c + Vector2.from_angle(th) * d
		if sink != null:
			sink.arc(pc, rp, th - deg_to_rad(140.0), th + deg_to_rad(140.0), w, col, 20)
		else:
			ci.draw_arc(pc, rp, th - deg_to_rad(140.0), th + deg_to_rad(140.0), 20, col, w)


## 线性图标（白色细线）：enemy / clock / box / ingot / pause / refresh / exit
static func icon(ci: CanvasItem, kind: String, c: Vector2, s: float, col: Color) -> void:
	var h := s / 2.0
	if sink != null and kind in ["enemy", "clock", "pause"]:
		match kind:
			"enemy":
				sink.circle(c, h, Color(1.0, 0.54, 0.24, col.a), 20)
				sink.arc(c, h * 0.36, 0.0, TAU, 1.6, Color(0.1, 0.07, 0.03, col.a), 16)
				for k in 4:
					var d := Vector2.from_angle(k * PI / 2.0)
					sink.line(c + d * h * 0.55, c + d * h * 0.82, Color(0.1, 0.07, 0.03, col.a), 1.6)
			"clock":
				sink.arc(c, h - 1.0, 0.0, TAU, 1.5, col, 24)
				sink.line(c, c + Vector2(0, -h * 0.55), col, 1.5)
				sink.line(c, c + Vector2(h * 0.4, h * 0.2), col, 1.5)
			"pause":
				sink.rect(Rect2(c + Vector2(-h * 0.45, -h * 0.5), Vector2(h * 0.28, h)), col)
				sink.rect(Rect2(c + Vector2(h * 0.17, -h * 0.5), Vector2(h * 0.28, h)), col)
		return
	match kind:
		"enemy":
			ci.draw_circle(c, h, Color(1.0, 0.54, 0.24, col.a))
			ci.draw_arc(c, h * 0.36, 0.0, TAU, 16, Color(0.1, 0.07, 0.03, col.a), 1.6)
			for k in 4:
				var d := Vector2.from_angle(k * PI / 2.0)
				ci.draw_line(c + d * h * 0.55, c + d * h * 0.82, Color(0.1, 0.07, 0.03, col.a), 1.6)
		"clock":
			ci.draw_arc(c, h - 1.0, 0.0, TAU, 24, col, 1.5)
			ci.draw_line(c, c + Vector2(0, -h * 0.55), col, 1.5)
			ci.draw_line(c, c + Vector2(h * 0.4, h * 0.2), col, 1.5)
		"box":
			var r := Rect2(c - Vector2(h - 1, h * 0.4), Vector2(s - 2, h * 1.4 - 1))
			ci.draw_rect(r, col, false, 1.4)
			ci.draw_line(Vector2(r.position.x, c.y), Vector2(r.end.x, c.y), col, 1.2)
			ci.draw_line(Vector2(c.x, c.y), Vector2(c.x, c.y + h * 0.3), col, 1.2)
		"ingot":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -h + 1), c + Vector2(h - 1, h - 2), c + Vector2(-h + 1, h - 2)]), col)
			ci.draw_line(c + Vector2(0, -h * 0.2), c + Vector2(0, h - 4), Color(0.02, 0.14, 0.1, col.a), 1.4)
		"pause":
			ci.draw_rect(Rect2(c + Vector2(-h * 0.45, -h * 0.5), Vector2(h * 0.28, h)), col)
			ci.draw_rect(Rect2(c + Vector2(h * 0.17, -h * 0.5), Vector2(h * 0.28, h)), col)
		"refresh":
			ci.draw_arc(c, h - 2.0, -PI * 0.35, PI * 1.35, 24, col, 1.5)
			var tip := c + Vector2.from_angle(-PI * 0.35) * (h - 2.0)
			ci.draw_line(tip, tip + Vector2(-5, -1), col, 1.5)
			ci.draw_line(tip, tip + Vector2(0, 5), col, 1.5)
		"exit":
			ci.draw_polyline(PackedVector2Array([c + Vector2(h * 0.1, -h + 2), c + Vector2(-h + 2, -h + 2), c + Vector2(-h + 2, h - 2), c + Vector2(h * 0.1, h - 2)]), col, 1.4)
			ci.draw_line(c + Vector2(-h * 0.2, 0), c + Vector2(h - 1, 0), col, 1.4)
			ci.draw_line(c + Vector2(h - 1, 0), c + Vector2(h - 5, -4), col, 1.4)
			ci.draw_line(c + Vector2(h - 1, 0), c + Vector2(h - 5, 4), col, 1.4)


# ---------------------------------------------------------------- 墨痕（事件画面 · C 版式：灰阶炭笔插画 + 撕纸边）
## 撕纸边矩形：沿边每隔 step 左右取一个点，按 sides（t/b/l/r）决定哪几条边抖动 amp 像素
## 填充可能自交的随机多边形（撕纸边、墨团、笔刷）：能三角化就原样画；不能（顶点重合 / 自交，引擎会报
## 「Invalid polygon data, triangulation failed」）就先用 offset_polygon(0) 拆成干净的几块再画，拆开后不带 uv / 贴图
static func fill_poly(ci: CanvasItem, pts: PackedVector2Array, col: Color, uvs := PackedVector2Array(), tex: Texture2D = null) -> void:
	if pts.size() < 3:
		return
	if not Geometry2D.triangulate_polygon(pts).is_empty():
		ci.draw_colored_polygon(pts, col, uvs, tex)
		return
	for p in Geometry2D.offset_polygon(pts, 0.0):
		if p.size() >= 3 and not Geometry2D.triangulate_polygon(p).is_empty():
			ci.draw_colored_polygon(p, col)


static func jag_rect(r: Rect2, amp: float, step: float, rng: RandomNumberGenerator, sides := "tblr") -> PackedVector2Array:
	var pts := PackedVector2Array()
	var x0 := r.position.x
	var y0 := r.position.y
	var x1 := r.end.x
	var y1 := r.end.y
	var x := x0
	while x < x1 - step * 0.5:
		pts.append(Vector2(x, y0 + (rng.randf_range(-amp, amp) if sides.contains("t") else 0.0)))
		x += rng.randf_range(step * 0.5, step * 1.3)
	var y := y0
	while y < y1 - step * 0.5:
		pts.append(Vector2(x1 + (rng.randf_range(-amp, amp) if sides.contains("r") else 0.0), y))
		y += rng.randf_range(step * 0.5, step * 1.3)
	x = x1
	while x > x0 + step * 0.5:
		pts.append(Vector2(x, y1 + (rng.randf_range(-amp, amp) if sides.contains("b") else 0.0)))
		x -= rng.randf_range(step * 0.5, step * 1.3)
	y = y1
	while y > y0 + step * 0.5:
		pts.append(Vector2(x0 + (rng.randf_range(-amp, amp) if sides.contains("l") else 0.0), y))
		y -= rng.randf_range(step * 0.5, step * 1.3)
	return pts


## 笔刷横条：起笔细、行笔满、收笔略干；frac < 1 时只取前一段（按整条的粗细曲线截断）
static func brush_poly(pos: Vector2, w: float, h: float, rng: RandomNumberGenerator, frac := 1.0) -> PackedVector2Array:
	var phase := rng.randf_range(0.0, 6.0)
	var n := maxi(8, int(40.0 * frac))
	var top := PackedVector2Array()
	var bot := PackedVector2Array()
	for i in n + 1:
		var tt := frac * i / n
		var prof := 1.0
		if tt < 0.1:
			prof = 0.3 + 0.7 * tt / 0.1
		elif tt > 0.86:
			prof = 1.0 - 0.5 * (tt - 0.86) / 0.14
		var th := h * prof * (0.9 + 0.1 * sin(tt * 23.0 + phase))
		var cy := pos.y + h / 2.0 + h * 0.08 * sin(tt * 5.0 + phase)
		var px := pos.x + w * tt
		top.append(Vector2(px, cy - th / 2.0 + rng.randf_range(-0.4, 0.4)))
		bot.append(Vector2(px, cy + th / 2.0 + rng.randf_range(-0.4, 0.4)))
	bot.reverse()
	top.append_array(bot)
	return top


## 墨圈：一笔画成、中间粗两头细、留一个缺口的圆环
static func enso(c: Vector2, r: float, th: float, rng: RandomNumberGenerator, gap := 0.5) -> PackedVector2Array:
	var a0 := rng.randf_range(0.0, TAU)
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var n := 72
	for i in n + 1:
		var tt := float(i) / n
		var a := a0 + tt * (TAU - gap)
		var prof := pow(sin(PI * minf(1.0, tt * 1.08)), 0.55)
		var w := th * (0.2 + 0.8 * prof) * (0.85 + 0.15 * sin(tt * 17.0 + a0))
		var rr := r + 0.7 * sin(tt * 9.0 + a0)
		outer.append(c + Vector2.from_angle(a) * (rr + w / 2.0))
		inner.append(c + Vector2.from_angle(a) * (rr - w / 2.0))
	inner.reverse()
	outer.append_array(inner)
	return outer


## 不规则墨点（锯齿圆）
static func blob(c: Vector2, r: float, rng: RandomNumberGenerator, spikes := 0.4, n := 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		pts.append(c + Vector2.from_angle(TAU * i / n) * r * (1.0 + rng.randf_range(-spikes, spikes)))
	return pts


## 卷须放射徽记（原作事件画面左侧的蓝色徽记）：放射线末端卷曲成小旋涡；返回若干条折线
static func curly_lines(c: Vector2, r0: float, r1: float, n: int, curl: float, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for i in n:
		var a := TAU * i / n + rng.randf_range(-0.05, 0.05)
		var L := r1 if i % 2 == 0 else r0 + (r1 - r0) * 0.62
		var pts := PackedVector2Array()
		for s in 9:
			var tt := s / 8.0
			var rr := r0 + (L - r0) * tt
			var off := 1.1 * sin(tt * TAU + i) * tt
			pts.append(c + Vector2.from_angle(a) * rr + Vector2.from_angle(a + PI / 2.0) * off)
		var e := pts[pts.size() - 1]
		var cr := curl * (1.0 if i % 2 == 0 else 0.7)
		var left := i % 4 < 2
		var nrm := Vector2.from_angle(a + PI / 2.0) if left else Vector2.from_angle(a - PI / 2.0)
		var cc := e + nrm * cr
		var phi0 := (e - cc).angle()
		var sgn := 1.0 if left else -1.0
		for s in range(1, 13):
			var u := s / 12.0
			var phi := phi0 + sgn * u * deg_to_rad(290.0)
			pts.append(cc + Vector2.from_angle(phi) * cr * (1.0 - 0.62 * u))
		out.append(pts)
	return out


## 画卷须徽记：中心小圆 + 卷须；glow 时先画一层粗的淡色当外发光
static func curly_emblem(ci: CanvasItem, lines: Array, c: Vector2, r: float, col: Color, w := 1.5) -> void:
	for pl in lines:
		ci.draw_polyline(pl, Color(col.r, col.g, col.b, 0.22 * col.a), w + 3.0)
	ci.draw_arc(c, r * 0.26, 0.0, TAU, 24, Color(col.r, col.g, col.b, 0.22 * col.a), w + 3.0)
	for pl in lines:
		ci.draw_polyline(pl, col, w)
	ci.draw_arc(c, r * 0.26, 0.0, TAU, 24, col, w)


## 节点标签条的宽度（排版前量一下，放不下时可以只留英文）
static func strip_width(font: Font, en_s: String, cn: String, size := 12) -> float:
	size = fs(size)
	var ew := cond(font, true).get_string_size(en_s, HORIZONTAL_ALIGNMENT_LEFT, -1, size - 1).x + 13.0 if en_s != "" else 0.0
	var cw := font.get_string_size(cn, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 15.0 if cn != "" else 0.0
	return ew + cw


# ---------------------------------------------------------------- 文字排版（按像素宽度折行，放不下时先缩字号，最后才截断加「…」）
## 按像素宽度折行（中文按字断行，遵守 soft() 的标点规则）；\n 分段。返回每一行的文字。
## 防孤字：某段末行只剩一两个字（多为「字 + 句号」）时，把这段收窄一到四个字宽重排，行数不变才采用（不会让文字变高）
static func wrap_lines(font: Font, s: String, size: int, width: float) -> PackedStringArray:
	return _wrap_lines(font, s, fs(size), width)


## 折行结果缓存（10-25 帧率审计：属性面板 / 精英化演出 / 选人技能行 / 图鉴每帧对同一段静态文字重排，fit 一次要试几个字号、每个字号新建 TextParagraph）。
## 键 = 字体 + 文字 + 字号 + 宽度；超过 512 条整表清空。PackedStringArray 按值传，调用方改不到缓存里的
static var _wrap_cache := {}

static func _wrap_lines(font: Font, s: String, size: int, width: float) -> PackedStringArray:
	var key := "%d|%d|%.3f|%s" % [font.get_instance_id(), size, width, s]
	var hit = _wrap_cache.get(key)
	if hit != null:
		return hit
	var res := _wrap_lines_raw(font, s, size, width)
	if _wrap_cache.size() >= 512:
		_wrap_cache.clear()
	_wrap_cache[key] = res
	return res


static func _wrap_lines_raw(font: Font, s: String, size: int, width: float) -> PackedStringArray:
	var out := PackedStringArray()
	for para in s.split("\n"):
		var sp := soft(para)
		if sp.strip_edges() == "":
			out.append("")
			continue
		var pl := _wrap_para(font, sp, size, width)
		if pl.size() >= 2 and pl[pl.size() - 1].length() <= 2:
			for k in range(1, 5):
				var alt := _wrap_para(font, sp, size, width - k * size)
				if alt.size() == pl.size() and alt[alt.size() - 1].length() > 2:
					pl = alt
					break
		out.append_array(pl)
	return out


static func _wrap_para(font: Font, sp: String, size: int, width: float) -> PackedStringArray:
	var p := TextParagraph.new()
	p.break_flags = BRK
	p.width = width
	p.add_string(sp, font, size)
	var out := PackedStringArray()
	for i in p.get_line_count():
		var rg: Vector2i = p.get_line_range(i)
		out.append(sp.substr(rg.x, rg.y - rg.x).replace("​", "").strip_edges())
	return out


## 把文字排进 width × max_h：从 sizes（由大到小）里挑最大的能整段放下的字号；
## 最小字号也放不下时截断，末行加「…」（fit = false，调用方可以另给悬停提示）。
## 返回 {size, lines, lh（行高）, h（总高）, fit}
static func fit(font: Font, s: String, width: float, max_h: float, sizes: Array = [13, 12, 11], gap := 0.0) -> Dictionary:
	var res := {}
	for fs0 in sizes:
		var sz := fs(int(fs0))
		var lines := _wrap_lines(font, s, sz, width)
		var lh: float = font.get_height(sz) + gap
		var n := maxi(1, int(floor((max_h + gap) / lh)))
		res = {"size": sz, "lines": lines, "lh": lh, "n": n, "fit": lines.size() <= n}
		if lines.size() <= n:
			res.h = lines.size() * lh
			return res
	var ls: PackedStringArray = res.lines
	var nn: int = res.n
	if ls.size() > nn:
		ls = ls.slice(0, nn)
		var last := ls[nn - 1]
		while last.length() > 0 and font.get_string_size(last + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, res.size).x > width:
			last = last.substr(0, last.length() - 1)
		ls[nn - 1] = last + "…"
	res.lines = ls
	res.h = ls.size() * float(res.lh)
	return res


## 画 fit() 排好的文字；pos 是第一行的顶边。align / width 同 draw_string。返回占用高度
static func draw_fit(ci: CanvasItem, font: Font, pos: Vector2, f: Dictionary, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> float:
	var y := pos.y
	var asc := font.get_ascent(f.size)
	for ln in f.lines:
		ci.draw_string(font, Vector2(pos.x, y + asc), ln, align, width, f.size, col)
		y += f.lh
	return y - pos.y


## 单行文字限宽：太宽先缩字号（最小 min_size），还放不下就截断加「…」
static func text_fit(ci: CanvasItem, font: Font, pos: Vector2, s: String, size: int, col: Color, max_w: float, min_size := 10) -> void:
	var fl := _fit_line(font, s, _ks(ci, size), max_w, _ks(ci, min_size))
	ci.draw_string(font, pos, fl[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fl[1], col)


## text_fit 的排版部分：返回 [文字, 字号]
static func fit_line(font: Font, s: String, size: int, max_w: float, min_size := 10) -> Array:
	return _fit_line(font, s, fs(size), max_w, fs(min_size))


static func _fit_line(font: Font, s: String, size: int, max_w: float, min_size: int) -> Array:
	var sz := size
	while sz > min_size and font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x > max_w:
		sz -= 1
	var t := s
	if font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x > max_w:
		while t.length() > 1 and font.get_string_size(t + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x > max_w:
			t = t.substr(0, t.length() - 1)
		t += "…"
	return [t, sz]


# ---------------------------------------------------------------- B+（干员选择，docs/58 §11；图鉴 C4' 也复用其中的斜带 / 描边英文名 / 名册卡结构）
## 水月 / 集成战略式：无切角圆角面板、紫色细边 + 顶角青菱形饰角（docs/37 §1 旁注：饰角不是像素角括）、圆角标签片、青色出击。
## 只加组件，不改上面的常量。动效参数（t 0–1）由调用方按真实时间算，这里只按进度画；不碰任何随机数。
const B_FILL := Color(0.039, 0.063, 0.11, 0.80)       # 面板底 (10,16,28,205)
const B_FILL_SEL := Color(0.086, 0.102, 0.204, 0.90)  # 选中底 (22,26,52,230)
const B_LINE := Color(0.66, 0.52, 1.0, 0.31)          # 紫色细边 (168,133,255,80)
const B_SUB := Color(0.627, 0.659, 0.745)             # B 的次要字 (160,168,190)
const B_ACC := Color(0.235, 0.784, 0.894)             # B 的点缀青 #3CC8E4（饰角菱形 / 细线 / 出击框；10-15 用户定选人页去黄，docs/37 §8）
const CLASS_GLYPH := {"先锋": "flag", "近卫": "blade", "重装": "shield", "狙击": "cross", "术师": "orb", "医疗": "plus", "辅助": "wave", "特种": "diamond"}
static var _rbox_cache := {}


static func ease_out(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)


static func ease_io(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 4.0 * x * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 3.0) / 2.0


## ease-out back（名册卡选中抬起的轻微过冲）
static func ease_back(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	var c1 := 1.70158
	return 1.0 + (c1 + 1.0) * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)


static func fa(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)


## 圆角矩形（StyleBoxFlat，抗锯齿）；border.a = 0 时不描边
static func rbox(ci: CanvasItem, r: Rect2, radius: float, fill: Color, border := Color(0, 0, 0, 0), bw := 1) -> void:
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	var key := "%s|%s|%d|%d" % [fill.to_html(), border.to_html(), bw, int(radius)]
	var sb: StyleBoxFlat = _rbox_cache.get(key)
	if sb == null:
		if _rbox_cache.size() > 400:
			_rbox_cache.clear()
		sb = StyleBoxFlat.new()
		sb.bg_color = fill
		sb.draw_center = fill.a > 0.0
		sb.set_corner_radius_all(int(radius))
		sb.corner_detail = 6
		sb.anti_aliasing = true
		if border.a > 0.0:
			sb.border_color = border
			sb.set_border_width_all(bw)
		_rbox_cache[key] = sb
	ci.draw_style_box(sb, r)


## 文字按锚点画（移植概念图坐标用）：anchor = la（左上）/ lm（左中）/ mm（正中）/ ma（中上）/ ra（右上）/ rm（右中）；bold = 同色 1px 描边加粗
static func text_at(ci: CanvasItem, font: Font, pos: Vector2, s: String, size: int, col: Color, anchor := "la", bold := false) -> float:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := pos.x
	if anchor[0] == "m":
		x -= w / 2.0
	elif anchor[0] == "r":
		x -= w
	var asc := font.get_ascent(size)
	var y := pos.y + asc
	if anchor[1] == "m":
		y = pos.y + (asc - font.get_descent(size)) / 2.0
	if bold:
		ci.draw_string_outline(font, Vector2(x, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 2, col)
	ci.draw_string(font, Vector2(x, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	return w


## 微型代码（`No.04 // 近卫 // 近战`、`OPERATOR DATA // SKILL`）：压缩字、不斜体、字距 2；pos 是左上角
static func code(ci: CanvasItem, font: Font, pos: Vector2, s: String, size := 9, col := B_SUB, anchor := "la") -> float:
	var w := en_width(font, s, size, 2.0)
	var x := pos.x - (w / 2.0 if anchor == "ma" else (w if anchor == "ra" else 0.0))
	return en(ci, font, Vector2(x, pos.y + cond(font).get_ascent(size)), s, size, col, 2.0)


## B 面板：圆角 4、紫色细边、内衬细线、顶部高光；accent（当前 / 选中）时顶角金菱形 + 两段金细线；edge = 选中时的描边色
static func bpanel(ci: CanvasItem, r: Rect2, accent := false, sel := false, a := 1.0, edge := Color(0, 0, 0, 0)) -> void:
	var border := fa(B_LINE, a)
	if sel and edge.a > 0.0:
		border = fa(Color(edge.r, edge.g, edge.b, 0.9), a)
	rbox(ci, r, 4, fa(B_FILL_SEL if sel else B_FILL, a), border)
	if r.size.x > 60.0 and r.size.y > 40.0:
		rbox(ci, r.grow(-3.0), 3, Color(0, 0, 0, 0), Color(1, 1, 1, 0.063 * a))
	ci.draw_line(Vector2(r.position.x + 6, r.position.y + 1.5), Vector2(r.end.x - 6, r.position.y + 1.5), Color(1, 1, 1, 0.12 * a), 1.0)
	if accent or sel:
		diamond(ci, r.position + Vector2(1, 1), 4.0, fa(B_ACC, a))
		diamond(ci, Vector2(r.end.x - 1, r.position.y + 1), 4.0, fa(B_ACC, a))
		if r.size.x > 120.0:
			ci.draw_line(r.position + Vector2(10, 0.5), r.position + Vector2(40, 0.5), fa(B_ACC, a), 1.0)
			ci.draw_line(Vector2(r.end.x - 40, r.position.y + 0.5), Vector2(r.end.x - 10, r.position.y + 0.5), fa(B_ACC, a), 1.0)


## B 圆角标签片：solid = 实色底深字，否则暗底 + 彩色细边；返回占位宽度（含 6 像素间距）
static func pill(ci: CanvasItem, font: Font, pos: Vector2, s: String, col: Color, size := 11, solid := false, a := 1.0) -> float:
	var h := size + 8.0
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 18.0
	rbox(ci, Rect2(pos, Vector2(w, h)), h / 2.0, fa(col, a) if solid else Color(0, 0, 0, 0.51 * a), fa(Color(col.r, col.g, col.b, 0.86), a))
	text_at(ci, font, pos + Vector2(w / 2.0, h / 2.0), s, size, Color(0.04, 0.05, 0.06, a) if solid else fa(TEXT, a), "mm")
	return w + 6.0


static func pill_width(font: Font, s: String, size := 11) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 24.0


## B 小标签头（圆角 3，彩色底白字）；pos 左上，返回宽度
static func btab(ci: CanvasItem, font: Font, pos: Vector2, s: String, col: Color, size := 9, a := 1.0) -> float:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 10.0
	rbox(ci, Rect2(pos, Vector2(w, size + 5)), 3, fa(col, a))
	text_at(ci, font, pos + Vector2(5, 1), s, size, Color(1, 1, 1, a))
	return w


## 职业线性图标（白线几何示意，不用原作图标）：c 中心，r 半径
static func class_glyph(ci: CanvasItem, cls: String, c: Vector2, r: float, col: Color, w := 2.0) -> void:
	var x := c.x
	var y := c.y
	match CLASS_GLYPH.get(cls, "diamond"):
		"blade":
			ci.draw_line(Vector2(x - r, y + r), Vector2(x + r, y - r), col, w)
			ci.draw_line(Vector2(x - r * 0.3, y + r), Vector2(x + r, y + r * 0.3), col, w)
		"shield":
			var p := PackedVector2Array([Vector2(x - r, y - r), Vector2(x + r, y - r), Vector2(x + r, y + r * 0.2), Vector2(x, y + r), Vector2(x - r, y + r * 0.2), Vector2(x - r, y - r)])
			ci.draw_polyline(p, col, w)
		"cross":
			ci.draw_arc(c, r, 0.0, TAU, 24, col, w)
			ci.draw_line(Vector2(x - r, y), Vector2(x + r, y), col, w)
			ci.draw_line(Vector2(x, y - r), Vector2(x, y + r), col, w)
		"orb":
			ci.draw_arc(c, r * 0.7, 0.0, TAU, 20, col, w)
			ci.draw_polyline(PackedVector2Array([Vector2(x, y - r), Vector2(x + r, y + r * 0.8), Vector2(x - r, y + r * 0.8), Vector2(x, y - r)]), col, 1.0)
		"plus":
			ci.draw_rect(Rect2(x - r * 0.3, y - r, r * 0.6, r * 2.0), col)
			ci.draw_rect(Rect2(x - r, y - r * 0.3, r * 2.0, r * 0.6), col)
		"wave":
			var p := PackedVector2Array()
			for i in 9:
				p.append(Vector2(x - r + i * r / 4.0, y + (r * 0.5 if i % 2 else -r * 0.5)))
			ci.draw_polyline(p, col, w)
		"flag":
			ci.draw_line(Vector2(x - r * 0.7, y - r), Vector2(x - r * 0.7, y + r), col, w)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(x - r * 0.7, y - r), Vector2(x + r, y - r * 0.5), Vector2(x - r * 0.7, y)]), col)
		_:
			ci.draw_polyline(PackedVector2Array([Vector2(x, y - r), Vector2(x + r, y), Vector2(x, y + r), Vector2(x - r, y), Vector2(x, y - r)]), col, w)


## 职业色斜带（选人 B+ 与图鉴 C4' 同一位置 / 倾角 / 宽度）：设计坐标 1280×720 下底边 x 560–800、顶边 770–1010（约 66°）；
## h = 画面高、ox / sc = 横向偏移与缩放（手机版式用）；t = 扫入进度（新带从左 -900 扫到位，盖住 prev 旧带）；
## alpha 0.35 + 右缘金细线 + 左缘紫细线（B 的柔带）；C4' 传 alpha 0.8、lines = false 后自己画黑细带
static func class_band(ci: CanvasItem, h: float, ox: float, sc: float, col: Color, prev: Color, t: float, alpha := 0.35, lines := true, a := 1.0) -> void:
	var e := ease_io(t)
	if e < 1.0 and prev.a > 0.0:
		_band_poly(ci, h, ox, sc, 0.0, Color(prev.r, prev.g, prev.b, alpha * a))
	var dx := -900.0 * (1.0 - e)
	_band_poly(ci, h, ox, sc, dx, Color(col.r, col.g, col.b, alpha * a))
	if lines:
		ci.draw_line(Vector2(ox + (806 + dx) * sc, h), Vector2(ox + (1016 + dx) * sc, 0), fa(Color(B_ACC.r, B_ACC.g, B_ACC.b, 0.67), a), 2.0, true)
		ci.draw_line(Vector2(ox + (548 + dx) * sc, h), Vector2(ox + (758 + dx) * sc, 0), fa(Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.47), a), 1.0, true)


static func _band_poly(ci: CanvasItem, h: float, ox: float, sc: float, dx: float, c: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([Vector2(ox + (560 + dx) * sc, h), Vector2(ox + (800 + dx) * sc, h), Vector2(ox + (1010 + dx) * sc, 0), Vector2(ox + (770 + dx) * sc, 0)]), c)


## 巨型描边英文名（压在立绘后）：只描边不填充；frac = 打字机进度（逐字出现）；pos 是左上角
static func ghost_name(ci: CanvasItem, font: Font, pos: Vector2, s: String, frac: float, size := 150, col := Color(0.745, 0.824, 1.0, 0.18), outline := 3) -> void:
	var n := int(round(s.length() * clampf(frac, 0.0, 1.0)))
	if n <= 0:
		return
	ci.draw_string_outline(font, pos + Vector2(0, font.get_ascent(size)), s.substr(0, n), HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, col)


## 贴图区域画进 dst，但只画落在 clip 里的部分（src 按比例同步裁掉）：小像 / 名册卡的人物不出框
static func blit_clipped(ci: CanvasItem, tx: Texture2D, dst: Rect2, src: Rect2, clip: Rect2, col := Color.WHITE) -> void:
	var vis := dst.intersection(clip)
	if vis.size.x <= 0.0 or vis.size.y <= 0.0 or dst.size.x <= 0.0 or dst.size.y <= 0.0:
		return
	var sx := src.size.x / dst.size.x
	var sy := src.size.y / dst.size.y
	var s2 := Rect2(src.position + (vis.position - dst.position) * Vector2(sx, sy), vis.size * Vector2(sx, sy))
	ci.draw_texture_rect_region(tx, vis, s2, col)


## 名册卡（B 皮：圆角 + 紫金描边 + 青色强调条；C4' 换直角黑框 / 黄条时另写皮，结构相同）
## od：{tex, frames, bb（帧内非透明区，贴图像素）, hires, name, cls, col}；lift 0–1（选中抬 10 px）、hover 0–1（悬停抬 4 px）；
## elite = 右上精英菱形个数；frame = 待机帧序号
static func roster_card(ci: CanvasItem, font: Font, r: Rect2, od: Dictionary, lift: float, hover: float, elite: int, frame: int, a := 1.0, name_size := 12) -> void:
	r.position.y -= 10.0 * lift + 4.0 * hover
	var col: Color = od.get("col", CYAN)
	var selv := lift > 0.5
	if lift > 0.01:
		rbox(ci, r.grow(3.0), 7, Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.2 * minf(lift, 1.0) * a))
	rbox(ci, r, 5, Color(0.086, 0.102, 0.204, 0.92 * a) if selv else Color(0.039, 0.078, 0.118, 0.86 * a),
		fa(VIOLET, a) if selv else Color(0.66, 0.52, 1.0, 0.31 * a), 2 if selv else 1)
	ci.draw_rect(Rect2(r.position.x + 4, r.position.y + 2, r.size.x - 8, 3), fa(col, a))
	var tx: Texture2D = od.get("tex")
	if tx != null:
		var hi: float = od.get("hires", 1.0)
		var fw: float = tx.get_width() / float(maxi(1, int(od.get("frames", 1))))
		var bb: Rect2 = card_bb(od, tx)
		var pl := card_place(r, fw, tx.get_height(), hi, bb, 24.0, float(od.get("ds", 1.0)))
		var src := Rect2(fw * frame + bb.position.x, bb.position.y, bb.size.x, bb.size.y)
		blit_clipped(ci, tx, pl, src, r.grow(-1.0), Color(1, 1, 1, a))
	rbox(ci, Rect2(r.position.x + 2, r.end.y - 22, r.size.x - 4, 20), 4, Color(0.016, 0.031, 0.063, 0.78 * a))
	rbox(ci, Rect2(r.position.x + 4, r.position.y + 8, 16, 16), 3, Color(0, 0, 0, 0.63 * a), Color(col.r, col.g, col.b, 0.78 * a))
	class_glyph(ci, od.get("cls", ""), r.position + Vector2(12, 16), 5.0, fa(col, a), 1.6)
	var fl := fit_line(font, str(od.get("name", "")), name_size, r.size.x - 8.0, 9)
	text_at(ci, font, Vector2(r.get_center().x, r.end.y - 12), fl[0], fl[1], fa(TEXT, a), "mm")
	for i in elite:
		diamond(ci, Vector2(r.end.x - 6 - elite * 9 + i * 9 + 3, r.position.y + 13), 3.0, fa(B_ACC, a))
	var hl := maxf(lift, hover * 0.6)
	if hl > 0.01:
		var w := maxf(4.0, (r.size.x - 12.0) * ease_out(minf(hl, 1.0)))
		rbox(ci, Rect2(r.position.x + 6, r.end.y + 4, w, 3), 1, fa(CYAN, a))
	if selv:
		diamond(ci, Vector2(r.get_center().x, r.position.y), 5.0, fa(B_ACC, a))


## 技能充能 SP 环：灰轨 + 彩色进度弧（12 点起顺时针），中间 SP 数，下方「SP」
static func sp_ring(ci: CanvasItem, font: Font, c: Vector2, rad: float, frac: float, col: Color, sp: String, a := 1.0, size := 11) -> void:
	ci.draw_arc(c, rad, 0.0, TAU, 40, Color(1, 1, 1, 0.12 * a), 3.0, true)
	if frac > 0.0:
		ci.draw_arc(c, rad, -PI / 2.0, -PI / 2.0 + TAU * clampf(frac, 0.0, 1.0), 40, fa(col, a), 3.0, true)
	text_at(ci, font, c, sp, size, fa(TEXT, a), "mm")
	text_at(ci, font, c + Vector2(0, rad + 4.0), "SP", 7, fa(B_SUB, a), "mm")


## 圆角量条（UI.gbar 的 B 版）：暗槽 + 紫细边 + 实色填充 + 顶部高光
static func gauge(ci: CanvasItem, r: Rect2, frac: float, col: Color, a := 1.0) -> void:
	var rad := r.size.y / 2.0
	rbox(ci, r, rad, Color(0, 0, 0, 0.59 * a), Color(0.66, 0.52, 1.0, 0.27 * a))
	var w := r.size.x * clampf(frac, 0.0, 1.0)
	if w > r.size.y:
		rbox(ci, Rect2(r.position, Vector2(w, r.size.y)), rad, fa(col, a))
		ci.draw_line(r.position + Vector2(4, 1.5), r.position + Vector2(w - 4, 1.5), Color(1, 1, 1, 0.47 * a), 1.0)


## B 页签：当前页淡紫底 + 紫下划线（pos 可为小数：滑动中）+ 金菱形；返回每个页签的矩形
static func btabs(ci: CanvasItem, font: Font, r: Rect2, names: Array, pos: float, size := 14, a := 1.0) -> Array:
	var tw := r.size.x / names.size()
	var cur := int(round(pos))
	var out: Array = []
	rbox(ci, Rect2(r.position.x + cur * tw + 2, r.position.y + 2, tw - 4, r.size.y - 2), 4, Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.22 * a))
	for i in names.size():
		out.append(Rect2(r.position.x + i * tw, r.position.y, tw, r.size.y))
		text_at(ci, font, Vector2(r.position.x + i * tw + tw / 2.0, r.get_center().y), names[i], size, fa(TEXT if i == cur else B_SUB, a), "mm")
	ci.draw_line(Vector2(r.position.x, r.end.y), r.end, fa(B_LINE, a), 1.0)
	var ux := r.position.x + pos * tw
	rbox(ci, Rect2(ux + 10, r.end.y - 2, tw - 20, 2), 1, fa(VIOLET, a))
	diamond(ci, Vector2(ux + tw / 2.0, r.end.y - 1), 3.0, fa(B_ACC, a))
	return out


## B 出击按钮：青底圆角 + 金外框 + 两侧金菱形；breathe 0–1 = 外圈青光呼吸（1.6 秒一次，调用方算）；press 0–1 = 按下（下沉 3 px + 闪白）
static func deploy_button(ci: CanvasItem, font: Font, r: Rect2, s: String, sub: String, breathe: float, press := 0.0, size := 24, a := 1.0, sink_px := 3.0) -> void:
	if press > 0.0 and press < 1.0:
		r.position.y += roundf(sink_px * sin(PI * press))
	rbox(ci, r.grow(7.0), 12, Color(0, 0, 0, 0), Color(CYAN.r, CYAN.g, CYAN.b, (0.16 + 0.24 * breathe) * a), 2)
	rbox(ci, r.grow(4.0), 9, Color(0, 0, 0, 0), fa(B_ACC, a), 1)
	rbox(ci, r, 6, fa(CYAN, a))
	ci.draw_line(r.position + Vector2(8, 2.5), Vector2(r.end.x - 8, r.position.y + 2.5), Color(0.78, 1.0, 0.99, a), 1.0)
	diamond(ci, Vector2(r.position.x - 4, r.get_center().y), 5.0, fa(B_ACC, a))
	diamond(ci, Vector2(r.end.x + 4, r.get_center().y), 5.0, fa(B_ACC, a))
	var ink := Color(0.03, 0.08, 0.094, a)
	var cy := r.get_center().y - (7.0 if sub != "" else 0.0)
	text_at(ci, font, Vector2(r.get_center().x, cy), s, size, ink, "mm", true)
	if sub != "":
		text_at(ci, font, Vector2(r.get_center().x, cy + 22), sub, 10, ink, "mm")
	if press > 0.0 and press < 1.0:
		rbox(ci, r, 6, Color(1, 1, 1, 0.59 * sin(PI * press) * a))


## 深海浪幕（选人 → 难度的转场，docs/58 §11.2）：e = 0–1 总进度（调用方已做 ease-in-out）；前半浪从下往上漫过（填浪下方），
## 过半由调用方换页，后半继续上涌退出（填浪上方）。气泡位置由序号哈希决定，不用随机数
static func wave_wipe(ci: CanvasItem, vs: Vector2, e: float) -> void:
	var first := e < 0.5
	var k := e * 2.0 if first else (e - 0.5) * 2.0
	var base_y := vs.y + 70.0 - (vs.y + 140.0) * k
	var pts := PackedVector2Array()
	var x := 0.0
	while x <= vs.x + 8.0:
		pts.append(Vector2(x, _wave_y(x, base_y, k)))
		x += 8.0
	var end_x: float = pts[pts.size() - 1].x
	var tail := PackedVector2Array([Vector2(end_x, vs.y + 10.0), Vector2(0, vs.y + 10.0)]) if first else PackedVector2Array([Vector2(end_x, -10.0), Vector2(0, -10.0)])
	var body := pts.duplicate()
	body.append_array(tail)
	fill_poly(ci, body, Color(0.039, 0.102, 0.173, 1.0))
	var dy := 40.0 if first else -40.0
	var p2 := PackedVector2Array()
	for p in pts:
		p2.append(p + Vector2(0, dy))
	p2.append_array(tail)
	fill_poly(ci, p2, Color(0.118, 0.063, 0.22, 0.63))
	var bucket := int(k * 1000.0) / 50
	for i in 40:
		var h1 := fposmod(sin(i * 12.9898 + bucket * 78.233) * 43758.5453, 1.0)
		var h2 := fposmod(sin(i * 39.3468 + bucket * 11.135) * 24634.6345, 1.0)
		var bx := h1 * vs.x
		var by := _wave_y(bx, base_y, k) + (10.0 + h2 * 150.0) * (1.0 if first else -1.0)
		ci.draw_arc(Vector2(bx, by), 1.0 + float(i % 3), 0.0, TAU, 10, Color(0.59, 0.92, 0.96, 0.47), 1.0)
	ci.draw_polyline(pts, Color(0.59, 0.94, 0.96, 0.9), 3.0, true)
	var p3 := PackedVector2Array()
	for p in pts:
		p3.append(p + Vector2(0, 8.0 if first else -8.0))
	ci.draw_polyline(p3, Color(CYAN.r, CYAN.g, CYAN.b, 0.43), 1.0, true)


static func _wave_y(x: float, base_y: float, k: float) -> float:
	return base_y + 22.0 * sin(x / 95.0 + k * 7.0) + 9.0 * sin(x / 37.0 - k * 11.0)


# ---------------------------------------------------------------- C 版式（干员图鉴 C4'，docs/58 §8 / §11；docs/37：浅色面板、平行四边形、警示黄只用于图鉴）
## 令牌：亮场 L（右侧终端数据面板）/ 暗场 D（左侧舞台、名册、顶栏）。只加常量，不改上面的。
const C_ACC := Color(1.0, 0.808, 0.0)                    # 警示黄 #FFCE00（只在图鉴里用）
const C_HZ := Color(0.086, 0.094, 0.11)                  # 警示条的黑段 (22,24,28)
const C_L_BG := Color(0.886, 0.894, 0.906)               # #E2E4E7
const C_L_GLASS := Color(0.886, 0.894, 0.906, 0.82)    # 图鉴右侧面板 + ARCHIVE 块：磨砂玻璃（ui_glass.gdshader，模糊后叠 0.70 浅色底）不可用时的平涂底（10-11 用户：「右边白色可以改成半透明吗」）
const C_L_PANEL := Color(0.98, 0.98, 0.98, 1.0)         # 不透明：磨砂玻璃上的「标签卡」（技能行 / 成长节点）
const C_L_SEL := Color(1.0, 0.969, 0.808)                # #FFF7CE
const C_L_INK := Color(0.086, 0.094, 0.11)               # #16181C 正文 / 线
const C_L_SUB := Color(0.361, 0.376, 0.408)              # #5C6068
const C_L_INV := Color(0.98, 0.98, 0.98)
const C_D_BG := Color(0.059, 0.063, 0.075)               # #0F1013
const C_D_PANEL := Color(0.102, 0.11, 0.129, 0.94)       # #1A1C21
const C_D_SEL := Color(0.227, 0.204, 0.078)              # #3A3414
const C_D_INK := Color(0.925, 0.933, 0.941)              # #ECEEF0
const C_D_SUB := Color(0.573, 0.592, 0.627)              # #9297A0
const C_D_INV := Color(0.059, 0.063, 0.075)
const C_D_CARD := Color(0.125, 0.133, 0.153)
const C_D_GHOST := Color(1.0, 1.0, 1.0, 0.133)           # 舞台上的描边英文名


## 平行四边形（右倾，原作按钮 / 页签）：r 外接矩形，skew 顶边右移量；fill / line 的 a = 0 时不画
static func para(ci: CanvasItem, r: Rect2, skew: float, fill: Color, line := Color(0, 0, 0, 0), w := 1.0) -> void:
	var p := PackedVector2Array([Vector2(r.position.x + skew, r.position.y), Vector2(r.end.x, r.position.y), Vector2(r.end.x - skew, r.end.y), Vector2(r.position.x, r.end.y)])
	if fill.a > 0.0:
		ci.draw_colored_polygon(p, fill)
	if line.a > 0.0:
		p.append(p[0])
		ci.draw_polyline(p, line, w, true)


## 黄黑警示条（45°，条宽 step）：phase = 滚动像素（调用方按时间算；减少动态时传 0）
static func hazard(ci: CanvasItem, r: Rect2, phase := 0.0, a := C_ACC, b := C_HZ, step := 8.0) -> void:
	ci.draw_rect(r, a)
	var h := r.size.y
	var x := -h - step * 2.0 + fposmod(phase, step * 2.0)
	while x < r.size.x + h:
		var q := _clip_poly_x(PackedVector2Array([r.position + Vector2(x, h), r.position + Vector2(x + step, h), r.position + Vector2(x + step + h, 0), r.position + Vector2(x + h, 0)]), r.position.x, r.end.x)
		if q.size() >= 3:
			ci.draw_colored_polygon(q, b)
		x += step * 2.0


## 多边形按竖直线 x0 / x1 裁切（Sutherland–Hodgman 两刀）
static func _clip_poly_x(p: PackedVector2Array, x0: float, x1: float) -> PackedVector2Array:
	for side in 2:
		var out := PackedVector2Array()
		var n := p.size()
		var xe := x0 if side == 0 else x1
		for i in n:
			var a := p[i]
			var b := p[(i + 1) % n]
			var ina := a.x >= x0 if side == 0 else a.x <= x1
			var inb := b.x >= x0 if side == 0 else b.x <= x1
			if ina:
				out.append(a)
			if ina != inb and absf(b.x - a.x) > 0.0001:
				out.append(a.lerp(b, (xe - a.x) / (b.x - a.x)))
		p = out
		if p.size() < 3:
			return p
	return p


## 职业框：图标装在方框里（卡上 16 / 名字旁 22 / 左轨 36）；on = 强调色底 + 黑图标；ink / inv = 所在场的墨色与反色
static func class_box(ci: CanvasItem, pos: Vector2, s: float, cls: String, on := false, ink := C_D_INK, inv := C_D_INV, a := 1.0) -> void:
	ci.draw_rect(Rect2(pos, Vector2(s, s)), fa(C_ACC if on else ink, a))
	class_glyph(ci, cls, pos + Vector2(s, s) / 2.0, s * 0.3, fa(C_HZ if on else inv, a), maxf(1.4, s / 12.0))


## 大数字：微型英文代码 + 小号中文标签，下方大号数值（右侧数据面板）；返回数值宽度
static func stat_big(ci: CanvasItem, font: Font, pos: Vector2, label: String, en_s: String, val: String, size := 22, ink := C_L_INK, sub := C_L_SUB, a := 1.0) -> float:
	var ew := code(ci, font, pos, en_s, 8, fa(sub, a))
	text_at(ci, font, pos + Vector2(ew + 4, -2), label, 9, fa(sub, a))
	return text_at(ci, font, pos + Vector2(0, 12), val, size, fa(ink, a), "la", size >= 18)


## C 平行四边形页签 + 可滑动的强调下划线（pos 可为小数）；亮场配色；返回每个页签的命中矩形
static func c_tabs(ci: CanvasItem, font: Font, r: Rect2, names: Array, pos: float, skew := 8.0, size := 13, a := 1.0) -> Array:
	var tw := r.size.x / names.size()
	var cur := int(round(pos))
	var out: Array = []
	for i in names.size():
		var tr := Rect2(r.position.x + i * tw + 2, r.position.y, tw - 4, r.size.y - 6)
		var on := i == cur
		para(ci, tr, skew, fa(C_L_INK, a) if on else Color(0, 0, 0, 0), fa(C_L_INK, a))
		if tr.size.x - font.get_string_size(names[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x >= 2.0 * (skew + 16.0):   # 窄页签（手机四页签）不画序号，免得压字
			code(ci, font, tr.position + Vector2(skew + 4, 2), "%02d" % (i + 1), 7, fa(C_ACC if on else C_L_SUB, a))
		text_at(ci, font, tr.get_center() + Vector2(0, 2), names[i], size, fa(C_L_INV if on else C_L_INK, a), "mm")
		out.append(Rect2(r.position.x + i * tw, r.position.y, tw, r.size.y))
	var ux := r.position.x + pos * tw
	ci.draw_rect(Rect2(ux + 6, r.end.y - 3, tw - 12, 3), fa(C_ACC, a))
	ci.draw_line(Vector2(r.position.x, r.end.y), r.end, fa(C_L_INK, a), 1.0)
	return out


## C 面板（亮场）：白底 + 1 px 墨色框；sel = 选中底 + 2 px 框 + 左侧 4 px 强调条
static func cpanel(ci: CanvasItem, r: Rect2, sel := false, a := 1.0) -> void:
	ci.draw_rect(r, fa(C_L_SEL if sel else C_L_PANEL, a))
	ci.draw_rect(r, fa(C_L_INK, a), false, 2.0 if sel else 1.0)
	if sel:
		ci.draw_rect(Rect2(r.position, Vector2(4, r.size.y)), fa(C_ACC, a))


## C 标签片：面板底 + 左侧 UI.PURPLE 色条（PURPLE 仍只做干员标签）；dark = 画在暗场上；返回占位宽度（含 6 间距）
static func ctag(ci: CanvasItem, font: Font, pos: Vector2, s: String, size := 11, dark := true, a := 1.0) -> float:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 16.0
	var h := size + 8.0
	var ink := C_D_INK if dark else C_L_INK
	ci.draw_rect(Rect2(pos, Vector2(w, h)), fa(C_D_PANEL if dark else C_L_PANEL, a))
	ci.draw_rect(Rect2(pos, Vector2(w, h)), fa(ink, a), false, 1.0)
	ci.draw_rect(Rect2(pos, Vector2(3, h)), fa(PURPLE, a))
	text_at(ci, font, pos + Vector2(9, 4), s, size, fa(ink, a))
	return w + 6.0


## C 斜带（图鉴 C4'）：职业色实带 + 右侧一道细带（暗场里是浅墨色）；与 class_band 同一扫入规则：新带从左扫到位盖住 prev
## b0 = 主带底边左 x，w = 带宽，run = 顶边相对底边右移，thin = (细带相对主带的偏移, 细带宽)
static func c_band(ci: CanvasItem, h: float, b0: float, w: float, run: float, col: Color, prev: Color, t: float, alpha := 0.6, thin := Vector2(258, 16), ink := C_D_INK, a := 1.0) -> void:
	var e := ease_io(t)
	if e < 1.0 and prev.a > 0.0:
		_c_band_poly(ci, h, b0, w, run, Color(prev.r, prev.g, prev.b, alpha * a))
		_c_band_poly(ci, h, b0 + thin.x, thin.y, run, Color(ink.r, ink.g, ink.b, 0.86 * a))
	var dx := -900.0 * w / 240.0 * (1.0 - e)
	_c_band_poly(ci, h, b0 + dx, w, run, Color(col.r, col.g, col.b, alpha * a))
	_c_band_poly(ci, h, b0 + thin.x + dx, thin.y, run, Color(ink.r, ink.g, ink.b, 0.86 * a))


static func _c_band_poly(ci: CanvasItem, h: float, x0: float, w: float, run: float, c: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([Vector2(x0, h), Vector2(x0 + w, h), Vector2(x0 + w + run, 0), Vector2(x0 + run, 0)]), c)


## 名册卡上的人物：整数倍（@2x 像素 1 / 2 / 3 倍；放不下高度时退到 0.5 = 原始像素 1:1），整身放进卡里、裁进卡框
## （与 roster_card 同一规则，图鉴 C4' 的卡用）；od：{tex, frames, bb, hires}；name_h = 底部名字条高
static func card_art(ci: CanvasItem, r: Rect2, od: Dictionary, frame: int, col := Color.WHITE, name_h := 24.0) -> void:
	var tx: Texture2D = od.get("tex")
	if tx == null:
		return
	var hi: float = od.get("hires", 1.0)
	var fw: float = tx.get_width() / float(maxi(1, int(od.get("frames", 1))))
	var bb: Rect2 = card_bb(od, tx)
	var src := Rect2(fw * frame + bb.position.x, bb.position.y, bb.size.x, bb.size.y)
	blit_clipped(ci, tx, card_place(r, fw, tx.get_height(), hi, bb, name_h, float(od.get("ds", 1.0))), src, r.grow(-1.0), col)


## 名册卡 / 图鉴格子里的小人（10-21 用户：居中、统一缩放、留在名字条之上，长武器 / 大盾不另降倍但整幅在格子内）：
## 倍数按卡的尺寸与 CARD_FIT（全员待机并集的最大宽高，@2x 像素）取 CARD_STEPS 里放得下的最大一档，同一种卡里每人同倍率、看上去一样大；
## 脚底点（画布水平中线、脚底行）对齐卡中线与名字条上方的同一条底线（脚下的阴影 / 衣摆留 8 像素）；横向超出时只平移不缩放。
## 返回贴图并集区 bb 在屏幕上的目标矩形
const CARD_REF := Vector2(100.0, 100.0)   # 10-21 实测：浊心待机举杖高 99、归溟锯盘宽 98（@2x 像素）
## 舞台立绘取倍数用 CARD_REF；格子小人用实测并集 CARD_FIT（放得下的上限，差 1 像素以内算放得下）
const CARD_FIT := Vector2(98.0, 99.0)
## 非整数档只取规律丢像素的分数（10-21 用户要放大到 0.85 左右）：0.8 = 每 5 个 @2x 像素画成 4 个（桌面图鉴 80 × 110 / 名册 82 × 112），
## 0.6 = 每 5 个画成 3 个（手机 62 × 88–90）；0.833 / 0.875 在桌面卡里放不下归溟的锯盘与浊心举杖
const CARD_STEPS := [3.0, 2.0, 1.0, 0.875, 0.8, 0.75, 0.6, 0.5]

static func card_place(r: Rect2, fw: float, fh: float, hi: float, bb: Rect2, name_h: float, ds := 1.0) -> Rect2:
	var room := Vector2(r.size.x - 2.0, r.size.y - name_h - 4.0)   # 横向到裁切框（r.grow(-1)）为止
	var kk: float = 0.5
	for st in CARD_STEPS:
		if CARD_FIT.x * st <= room.x + 1.0 and CARD_FIT.y * st <= room.y + 1.0:
			kk = st
			break
	var k: float = kk * 2.0 / hi * ds
	var base := Vector2(r.get_center().x, r.end.y - name_h - 2.0 - 8.0 * kk)
	var dst := Rect2(foot_pos(base, bb, fw, fh, hi, k), bb.size * k)
	var inner := r.grow(-1.0)
	dst.position.x += maxf(0.0, inner.position.x - dst.position.x) - maxf(0.0, dst.end.x - inner.end.x)
	dst.position.y += maxf(0.0, inner.position.y - dst.position.y)
	dst.position = dst.position.round()
	dst.size = dst.size.round()
	return dst


## 小人的待机帧并集区：有 bb（立绘已算）就用；没有就自己算一次存进 card_bb（10-21：选人名册里还没上过舞台的干员只有整帧，
## 整帧顶边越界被往下推，水月等大画布的人会沉到名字条后面）。不写 bb，免得跳过选人页 _op_art 的剪影计算
static func card_bb(od: Dictionary, tx: Texture2D) -> Rect2:
	if od.has("bb"):
		return od.bb
	if not od.has("card_bb"):
		od["card_bb"] = idle_bb(tx, int(od.get("frames", 1)))
	return od.card_bb


## 立绘按脚底点摆放（10-21 水月）：foot = 屏幕上的脚底点，返回并集区 bb 的左上角；脚底点 = 画布水平中线、foot_row 行。
## 原来按并集区底边 / 中线摆，水月伞尖在脚下 14 像素、整个人被抬高，大画布的人横向也偏
static func foot_pos(foot: Vector2, bb: Rect2, fw: float, fh: float, hi: float, k: float) -> Vector2:
	return foot - (Vector2(fw / 2.0, foot_row(fh, hi)) - bb.position) * k


## 干员整体显示倍率（sprites.draw_scale，水月 96 画布 0.9）：界面小人 / 立绘同局内一样乘上，和别人一样大
static func op_scale(def) -> float:
	return float(def.get("sprites", {}).get("draw_scale", 1.0)) if def is Dictionary else 1.0


## 帧内脚底行（贴图像素）：48 画布 46；64 口径 60，96 / 128 加边画布各加一半边宽（docs/108 §5）
static func foot_row(fh: float, hi: float) -> float:
	var c: float = fh / hi
	return (46.0 if c <= 48.0 else 60.0 + (c - 64.0) / 2.0) * hi


## 立绘适配（选人 B+ 与图鉴 C4' 同一规则）：在舞台框里（四边留 m）取 ≤ kmax 的最大整数倍（@2x 像素），使待机帧并集区整个放得下；
## w2 / h2 = 并集区按 @2x 像素的宽高；中心先放在 cx，放不下再往舞台里挪；返回 [倍数, 脚底中点]
## full2：完整并集高度（含按 fit_h 不计入降倍的角 / 武器）；给了就保证整幅仍在舞台框内（框边留 2，10-21 浊心待机举杖）
static func art_fit(w2: float, h2: float, stage: Rect2, kmax: float, cx: float, foot_y: float, m := 8.0, full2 := 0.0) -> Array:
	var k: float = maxf(1.0, floorf(kmax))
	while k > 1.0 and (w2 * k > stage.size.x - 2.0 * m or h2 * k > foot_y - stage.position.y - m or full2 * k > foot_y - stage.position.y - 2.0):
		k -= 1.0
	var half: float = w2 * k / 2.0
	cx = clampf(cx, stage.position.x + m + half, stage.end.x - m - half)
	return [k, Vector2(cx, foot_y)]


## 干员立绘判倍率用的高度（贴图像素）：旧 64 画布（48 < 帧高 / hires ≤ 64，docs/103 §5），角 / 帽 / 武器超出「身体」的部分不触发降倍——
## 按 STAND_FIT 美术像素封顶（docs/103 §3 站立高上限 36 + 1）；48 及大于 64 的原生画布使用完整并集高度。只给干员用。
const STAND_FIT := 37.0
## 干员小图标的取景窗（帧内贴图像素）：按固定框缩放的小图标（招募 / 升级卡、属性面板、开场说明）原来按整帧高缩放，
## 64 画布（docs/103 §5）会让人物缩到 3/4。64 画布起取「以脚底为准的旧 48 画布范围」：foot − (24, 46) 起 48 × 48 美术像素，
## 版式与 48 画布逐像素相同（站立高 + 头饰 ≤ 46 都在窗内）；48 画布返回整帧（结果不变）
static func op_win(fw: float, fh: float, hi: float, foot) -> Rect2:
	if fh / hi <= 48.0 or not (foot is Array) or foot.size() < 2:
		return Rect2(0, 0, fw, fh)
	var x0: float = clampf((float(foot[0]) - 24.0) * hi, 0.0, fw - 48.0 * hi)
	var y0: float = clampf((float(foot[1]) - 46.0) * hi, 0.0, fh - 48.0 * hi)
	return Rect2(x0, y0, 48.0 * hi, 48.0 * hi)
static func fit_h(bb: Rect2, fh: float, hi: float) -> float:
	# 旧 64 画布身体高度封顶不适用于完整原生 Spine 画布。
	if fh / hi <= 48.0 or fh / hi > 64.0:
		return bb.size.y
	return minf(bb.size.y, STAND_FIT * hi)


## 待机帧并集区（各帧非透明区的并集，立绘按它对齐、不抖）；读不到图（无头）就用整帧
static func idle_bb(tx: Texture2D, frames: int) -> Rect2:
	if tx == null:
		return Rect2()
	var fw: int = tx.get_width() / maxi(1, frames)
	var out := Rect2(0, 0, fw, tx.get_height())
	var img := tx.get_image()
	if img == null or img.is_empty():
		return out
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var u := Rect2i()
	for f in maxi(1, frames):
		var r := img.get_region(Rect2i(f * fw, 0, fw, img.get_height())).get_used_rect()
		if r.size.x > 0:
			u = r if u.size.x == 0 else u.merge(r)
	return Rect2(u) if u.size.x > 0 else out
