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
const TAB_GREY := Color(0.32, 0.35, 0.39)
## 多行文字折行规则：中文没有空格，必须允许按字折行，否则整段不换行溢出面板
const BRK: int = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_GRAPHEME_BOUND | TextServer.BREAK_ADAPTIVE

const CAT_COL := {"灯火": Color(1.0, 0.77, 0.42), "战斗": Color(0.33, 0.92, 0.88), "生存": Color(0.55, 0.9, 0.55), "海嗣": Color(0.66, 0.52, 1.0),
	# data/relics.json 的分类
	"攻击与输出": Color(0.33, 0.92, 0.88), "触手与控制": Color(0.66, 0.52, 1.0), "技能与技力": Color(0.5, 0.75, 1.0), "护盾": Color(0.6, 0.85, 1.0),
	"削弱敌人": Color(1.0, 0.55, 0.55), "经济": Color(1.0, 0.85, 0.4), "闪避": Color(0.7, 0.95, 1.0), "条件触发": Color(1.0, 0.7, 0.9),
	"援护干员": Color(0.9, 0.8, 0.6), "支援装置": Color(0.8, 0.8, 0.85), "负面藏品": Color(0.8, 0.35, 0.5),
	# docs/35 流派重做后的分类
	"追击与控制": Color(0.66, 0.52, 1.0), "编队协同": Color(0.95, 0.78, 0.5)}
## 藏品分类的英文标签（卡片左上角节点标签条用）
const CAT_EN := {"灯火": "LIGHT", "战斗": "COMBAT", "生存": "SURVIVAL", "海嗣": "SEABORN", "攻击与输出": "OFFENSE", "触手与控制": "CONTROL",
	"技能与技力": "SKILL", "护盾": "SHIELD", "削弱敌人": "DEBUFF", "经济": "ECONOMY", "闪避": "EVASION", "条件触发": "TRIGGER",
	"援护干员": "SUPPORT", "支援装置": "DEVICE", "负面藏品": "CURSED", "追击与控制": "CONTROL", "编队协同": "SQUAD"}

# 兼容旧代码的深海色名（外观已换成 A）
const DEEP := BG
const DEEP2 := BG2
const EDGE := Color(1.0, 1.0, 1.0, 0.24)
const EDGE_DIM := Color(1.0, 1.0, 1.0, 0.12)
const GLOW := CYAN
const KELP := Color(0.10, 0.36, 0.34)
const KELP2 := Color(0.16, 0.52, 0.46)
const KELP_LIGHT := Color(0.45, 0.95, 0.85)


# ---------------------------------------------------------------- 字体
## 英文压缩字：原作英文小标签是窄体粗字（Bender / Novecento 一类）。本作不额外带字体文件，
## 用 FontVariation 把 UI 字体横向压到 0.82 倍、略加粗；italic 再斜一点（节点标签条用）。
static var _cond := {}


static func cond(base: Font, italic := false) -> Font:
	var key := "%d:%s" % [base.get_instance_id(), italic]
	if _cond.has(key):
		return _cond[key]
	var fv := FontVariation.new()
	fv.base_font = base
	# 这个变换按 FreeType 矩阵解释（x' = xx·x + xy·y），所以斜体的切变量放在 x_axis.y
	fv.variation_transform = Transform2D(Vector2(0.82, 0.2 if italic else 0.0), Vector2(0.0, 1.0), Vector2.ZERO)
	fv.variation_embolden = 0.35
	_cond[key] = fv
	return fv


## 压缩字文字（数字、英文）
static func ctext(ci: CanvasItem, font: Font, pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, italic := false) -> void:
	ci.draw_string(cond(font, italic), pos, s, align, width, size, col)


static func cwidth(font: Font, s: String, size: int, italic := false) -> float:
	return cond(font, italic).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## 英文小标签（压缩字 + 字距）
static func en(ci: CanvasItem, font: Font, pos: Vector2, text: String, size: int, col: Color, spacing := 2.0) -> float:
	var f := cond(font)
	var x := pos.x
	for ch in text:
		ci.draw_string(f, Vector2(x, pos.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
		x += f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + spacing
	return x - pos.x


static func en_width(font: Font, text: String, size: int, spacing := 2.0) -> float:
	var f := cond(font)
	var w := 0.0
	for ch in text:
		w += f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + spacing
	return w


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
			out += "​"
	return out


# ---------------------------------------------------------------- 面板
## 切角多边形（左上、右下切角）——A 风格面板不再切角，保留给个别装饰用
static func cut_poly(r: Rect2, cut: float) -> PackedVector2Array:
	return PackedVector2Array([
		r.position + Vector2(cut, 0), Vector2(r.end.x, r.position.y), r.end - Vector2(0, cut),
		r.end - Vector2(cut, 0), Vector2(r.position.x, r.end.y), r.position + Vector2(0, cut)])


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
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 12.0
	ci.draw_rect(Rect2(pos, Vector2(w, size + 6)), bg)
	ci.draw_string(font, pos + Vector2(6, size + 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 1, 1, bg.a))
	return w


## 节点标签条（原作地图上的「COMBAT OPS. ✕ 虫群横行」）：左段彩色底 + 压缩斜体英文，右段暗底中文；返回宽度
static func strip(ci: CanvasItem, font: Font, pos: Vector2, en_s: String, cn: String, col: Color, cn_col := TEXT, size := 12, bg := Color(0.0, 0.0, 0.0, 0.6)) -> float:
	var cf := cond(font, true)
	var h := size + 8.0
	var ew := cf.get_string_size(en_s, HORIZONTAL_ALIGNMENT_LEFT, -1, size - 1).x + 13.0 if en_s != "" else 0.0
	var cw := font.get_string_size(cn, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 15.0 if cn != "" else 0.0
	ci.draw_rect(Rect2(pos, Vector2(ew + cw, h)), Color(bg.r, bg.g, bg.b, bg.a * col.a))
	if en_s != "":
		ci.draw_rect(Rect2(pos, Vector2(ew, h)), col)
		var ink := Color(0.04, 0.07, 0.08, col.a) if col.get_luminance() > 0.45 else Color(1, 1, 1, col.a)
		ci.draw_string(cf, pos + Vector2(6, h - 5), en_s, HORIZONTAL_ALIGNMENT_LEFT, -1, size - 1, ink)
	if cn != "":
		ci.draw_string(font, pos + Vector2(ew + 7, h - 5), cn, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(cn_col.r, cn_col.g, cn_col.b, cn_col.a * col.a))
	return ew + cw


## 标签片：暗底 + 左侧色条 + 文字，返回宽度
static func chip(ci: CanvasItem, font: Font, pos: Vector2, s: String, col: Color, size := 12) -> float:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 16.0
	var r := Rect2(pos, Vector2(w, size + 8))
	ci.draw_rect(r, Color(0.03, 0.035, 0.045, 0.8 * col.a))
	ci.draw_rect(Rect2(pos, Vector2(3, size + 8)), col)
	ci.draw_string(font, pos + Vector2(9, size + 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(col.r, col.g, col.b, col.a).lerp(Color(TEXT.r, TEXT.g, TEXT.b, col.a), 0.3))
	return w


## 按键牌：细边框里的按键名（SPACE / Esc / 1）；返回宽度
static func keycap(ci: CanvasItem, font: Font, pos: Vector2, key: String, col := TEXT, size := 11) -> float:
	var w := cwidth(font, key, size) + 12.0
	ci.draw_rect(Rect2(pos, Vector2(w, size + 7)), Color(col.r, col.g, col.b, 0.55 * col.a), false, 1.0)
	ci.draw_string(cond(font), pos + Vector2(6, size + 2), key, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	return w


## A 风格按钮：kind = "primary"（青底深字）/ "normal"（钢蓝半透明底）/ "outline"（暗底细边）/ "off"（禁用）
static func button(ci: CanvasItem, font: Font, r: Rect2, s: String, kind := "normal", hot := false, size := 15, a := 1.0) -> void:
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
		ci.draw_arc(pc, rp, th - deg_to_rad(140.0), th + deg_to_rad(140.0), 20, col, w)


## 线性图标（白色细线）：enemy / clock / box / ingot / pause / refresh / exit
static func icon(ci: CanvasItem, kind: String, c: Vector2, s: float, col: Color) -> void:
	var h := s / 2.0
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
	var ew := cond(font, true).get_string_size(en_s, HORIZONTAL_ALIGNMENT_LEFT, -1, size - 1).x + 13.0 if en_s != "" else 0.0
	var cw := font.get_string_size(cn, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 15.0 if cn != "" else 0.0
	return ew + cw
