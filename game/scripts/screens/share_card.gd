extends RefCounted
## 战绩分享卡（10-28 协调人单：结算加「分享战绩」，竖版 3:4；10-28 用户「分享战绩的也做一下」：改成与结算「作战报告」同一视觉语言）。
## 只读结算数据（settlement_screen.model + 编队立绘），不碰模拟与随机数。卡面在 600×800 的版面单位里画，调用方给位置与缩放。
## 巨型描边英文结果横贯上缘 + 中文结果块，左侧暗斜板放队长立绘，右侧评级与数据格，下面编队与藏品，底部白条放头像昵称与二维码。
## 配色跟随本局队长（settle_base.lead_theme，与结算同一套夹取）；失败同色降饱和，队长去色盖洋红「击倒」。
## 借危机合约结算的细节（与结算同）：一道斜向浅光、左上徽记、藏品细白框方格 + 左下角稀有度三角。
## 头像 / 昵称 / 二维码由 share_toy.gd 经 Toy SDK 取（先 isSupport）；拿不到（itch / 桌面版 / 用户拒绝）时不画头像，
## 昵称写「博士」，二维码换成游戏名。隐私：头像昵称只在本地画卡，不发往任何第三方、不写日志；toyOpenId 不经过这里（docs/22 Toy 接入）。
const HH = preload("res://scripts/screens/hh_style.gd")
const UI = preload("res://scripts/ui.gd")
const D = preload("res://scripts/data.gd")
const TUI = preload("res://scripts/screens/tide_ui.gd")
const SB = preload("res://scripts/screens/settle/settle_base.gd")
const OpFig = preload("res://scripts/screens/op_figure.gd")

const W := 600.0
const H := 800.0
const GAME := "方舟幸存者"

var g
var font: Font
var _xf := Transform2D.IDENTITY   # 卡面变换（位置 + 缩放）
var _pc := {}                     # 像素字上下文（含卡面变换）


func _init(host) -> void:
	g = host
	font = g.font


func _t(ci: CanvasItem, p: Vector2, s: String, size: int, col: Color, align := "l", width := -1.0) -> void:
	var al := HORIZONTAL_ALIGNMENT_LEFT if align == "l" else (HORIZONTAL_ALIGNMENT_CENTER if align == "c" else HORIZONTAL_ALIGNMENT_RIGHT)
	var x := p.x
	if align != "l":
		if width < 0.0:
			width = 400.0
		x = p.x - (width * 0.5 if align == "c" else width)   # 居中 / 右对齐：p 是中心点 / 右端
	ci.draw_string(font, Vector2(x, p.y + size), s, al, width, size, col)


static func _time(t: float) -> String:
	return "%02d:%02d" % [int(t) / 60, int(t) % 60]


## 卡面要用的数据（结算 model + 当前难度名 + 编队立绘）
func data(screen) -> Dictionary:
	var m: Dictionary = screen.model
	var won: bool = str(m.get("result", "")) == "win"
	var ops: Array = []
	for r in screen.rows:
		ops.append({"key": str(r.key), "name": str(r.name), "en": str(r.get("en", "")), "elite": int(r.get("elite", 0)), "leader": bool(r.leader), "col": r.col, "art": g.panel_ui.op_idle(str(r.key))})
	var relics: Array = m.get("relic_list", []).duplicate()
	var rank := {"升华": 0, "稀有": 1, "遭诅古物": 2, "基础": 3}
	relics.sort_custom(func(a, b): return int(rank.get(str(a.rarity), 4)) < int(rank.get(str(b.rarity), 4)))
	return {"won": won, "result": "探索完成" if won else "探索终止", "result_en": "OPERATION COMPLETE" if won else "OPERATION FAILED",
		"ending": str(m.get("ending_name", "")) if won else ("击倒：" + str(m.get("killer", {}).get("name", "未知"))),
		"tier": str(D.DIFF_PRESETS[clampi(g.preset, 0, D.DIFF_PRESETS.size() - 1)].name), "t": float(m.get("t", 0.0)),
		"hi_label": "总伤害", "hi": g.run_stats.fmt_n(float(m.get("total", 0.0))), "kills": int(m.get("kills", 0)), "level": int(m.get("level", 1)), "relic_n": int(m.get("relics", relics.size())),
		"grade": screen.grade(m, g.preset), "ops": ops, "relics": relics.slice(0, 6),
		"frame": frame_pick(), "date": Time.get_date_string_from_system().replace("-", "."),   # 相框（拍立得样张 / 三连专属，docs/313）+ 下巴日期
		"name": "博士", "avatar": null, "qr": null}   # 头像 / 昵称 / 二维码：share_toy.gd 拿到后由结算屏填


## pos = 卡左上角、k = 缩放；rot = 绕卡中心旋转（结算浮层的拍照出场用，导出图不转）
## 带相框时整张图是 outer_size：fit = 缩进原来 W × H 的位置（结算浮层）；导出图 fit = false、按 outer_size 1:1 画
func draw(ci: CanvasItem, d: Dictionary, pos: Vector2, k: float, rot := 0.0, fit := true) -> void:
	var fr := str(d.get("frame", ""))
	var os := outer_size(fr)
	var kk := k * (minf(W / os.x, H / os.y) if fit else 1.0)
	var c := pos + (Vector2(W, H) if fit else os) * k * 0.5
	_set_xf(ci, Transform2D(rot, Vector2(kk, kk), 0.0, c) * Transform2D(0.0, -os * 0.5))
	if FRAMES.has(fr):
		_polaroid(ci, d, fr)
	else:
		_report(ci, d)
		_footer(ci, d, _acc(d))
	ci.draw_set_transform(Vector2.ZERO)


func _acc(d: Dictionary) -> Color:
	var ld := _leader(d)
	return SB.lead_theme(ld.get("col", HH.CYB) if not ld.is_empty() else HH.CYB, bool(d.won))


# ---------------------------------------------------------------- 像素相框（11-08 用户：关注、三连各送一种专属边框；关注 = 罗德岛，三连 = 深海）
## 11-08 用户：报告卡面原样不动（1:1，含底部白条），只在卡外加一圈像素风相框：大像素格（PX）的粗描边相框带，
## 上边框嵌标题字，徽记 / 气泡 / 结晶 / 水母这类装饰探出框外，左下角一名队友探头（有队友用队友，没有用队长）。
## 导出图随之变大（outer_size）；结算浮层里整张缩进原来 W × H 的位置。
const FRAMES := {
	"ri": {"name": "罗德岛", "item": "follow"},
	"deep": {"name": "深海", "item": "triple"},
}
const PX := 8.0                                   # 相框像素格
const PD := 12.0                                  # 探出框外的装饰（徽记 / 气泡 / 结晶 / 水母…）的像素格，比相框粗一档
const MARGIN := [72.0, 104.0, 72.0, 76.0]         # 卡面到整张图边缘：左 上 右 下
const BAND := [3.0, 6.0, 3.0, 4.0]                # 相框带厚（格）：左 上 右 下
const RI_INK := Color("17181b")
const RI_YEL := Color("f2c230")
const RI_PAPER := Color("f7f7f4")
const SEA_INK := Color("0b2533")
const SEA := Color("7ff0ee")
const SEA_HI := Color("e9ffff")


## 本局用哪种相框：--shareframe=<id> / --supframe 截图用；否则取最后解锁的（toy_support.frames），都没有 = 普通卡面（""）
static func frame_pick() -> String:
	for a in Cfg.dev_args():
		if a.begins_with("--shareframe="):
			return a.substr(13)
	if Cfg.dev_args().has("--supframe"):
		return "deep"
	var fs: Array = preload("res://scripts/core/toy_support.gd").frames()
	return str(fs[-1]) if not fs.is_empty() else ""


## 整张图（含相框）的大小：普通卡面 = W × H
static func outer_size(fr: String) -> Vector2:
	if not FRAMES.has(fr):
		return Vector2(W, H)
	return Vector2(W + MARGIN[0] + MARGIN[2], H + MARGIN[1] + MARGIN[3])


func _set_xf(ci: CanvasItem, xf: Transform2D) -> void:
	_xf = xf
	ci.draw_set_transform_matrix(_xf)
	var x: Transform2D = TUI.ctx(ci).xf * _xf
	_pc = {"xf": x, "inv": x.affine_inverse(), "k": maxf(0.01, x.get_scale().x)}


func _quad(ci: CanvasItem, pts: Array, cols: Array) -> void:
	ci.draw_polygon(PackedVector2Array(pts), PackedColorArray(cols))


## 按字符图画像素块：rows 每行一个字符串，pal 字符 → 颜色（'.' 不画），o = 左上角，p = 格大小
func _pix(ci: CanvasItem, o: Vector2, rows: Array, pal: Dictionary, p := PX) -> void:
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var ch := row[x]
			if pal.has(ch):
				ci.draw_rect(Rect2(o + Vector2(x, y) * p, Vector2(p, p)), pal[ch])


## 相框：outer 坐标系（0,0 = 整张图左上）。顺序：背景 → 卡面 1:1 → 相框带 → 探出框外的装饰 → 探头的队友
func _polaroid(ci: CanvasItem, d: Dictionary, fr: String) -> void:
	var os := outer_size(fr)
	var photo := Rect2(MARGIN[0], MARGIN[1], W, H)
	var band := Rect2(photo.position - Vector2(BAND[0], BAND[1]) * PX, photo.size + Vector2(BAND[0] + BAND[2], BAND[1] + BAND[3]) * PX)
	var outer := _xf
	if fr == "ri":
		_ri_bg(ci, os)
	else:
		_deep_bg(ci, os)
	_set_xf(ci, outer * Transform2D(0.0, photo.position))
	_report(ci, d)
	_footer(ci, d, _acc(d))
	_set_xf(ci, outer)
	var ink: Color = RI_INK if fr == "ri" else SEA_INK
	var fill: Color = RI_PAPER if fr == "ri" else Color("d6f4f2")
	# 相框带：填色 + 外缘一格粗描边 + 内缘细线（卡面一圈）
	for r in [Rect2(band.position, Vector2(band.size.x, BAND[1] * PX)), Rect2(Vector2(band.position.x, photo.end.y), Vector2(band.size.x, BAND[3] * PX)),
			Rect2(Vector2(band.position.x, photo.position.y), Vector2(BAND[0] * PX, H)), Rect2(Vector2(photo.end.x, photo.position.y), Vector2(BAND[2] * PX, H))]:
		ci.draw_rect(r, fill)
	ci.draw_rect(band.grow(-PX * 0.5), ink, false, PX)
	ci.draw_rect(photo.grow(1.0), ink, false, 2.0)
	if fr == "ri":
		_ri_deco(ci, d, os, band, photo)
	else:
		_deep_deco(ci, d, os, band, photo)
	_peeker(ci, d, band, photo, ink)


## 干员 Q 版像素小人（没有就 null，退回游戏内小人）
static var _chibi_cache := {}

## Q 版小人贴图：按 k 倍最近邻放大成实像素（不靠画布过滤），外加一格 ink 色轮廓（压在卡面上也分得开）
static func chibi(key: String, k := 12, ink := Color.BLACK) -> Texture2D:
	var ck := "%s/%d/%s" % [key, k, ink.to_html()]
	if _chibi_cache.has(ck):
		return _chibi_cache[ck]
	var path := "res://art/operators/%s/op_%s_chibi.png" % [key, key]
	var tex: Texture2D = null
	if key != "" and ResourceLoader.exists(path):
		var src := load(path) as Texture2D   # 导入的压缩贴图在兼容渲染下直接画会成白块：取出图像自己做 ImageTexture
		if src != null:
			var im: Image = src.get_image()
			im.decompress()
			im.convert(Image.FORMAT_RGBA8)
			var w := im.get_width()
			var h := im.get_height()
			var ol := Image.create(w + 2, h + 2, false, Image.FORMAT_RGBA8)
			for y in h + 2:
				for x in w + 2:
					var sx := x - 1
					var sy := y - 1
					if sx >= 0 and sy >= 0 and sx < w and sy < h and im.get_pixel(sx, sy).a > 0.5:
						ol.set_pixel(x, y, im.get_pixel(sx, sy))
						continue
					for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var nx: int = sx + o.x
						var ny: int = sy + o.y
						if nx >= 0 and ny >= 0 and nx < w and ny < h and im.get_pixel(nx, ny).a > 0.5:
							ol.set_pixel(x, y, ink)
							break
			ol.resize((w + 2) * k, (h + 2) * k, Image.INTERPOLATE_NEAREST)
			tex = ImageTexture.create_from_image(ol)
	_chibi_cache[ck] = tex
	return tex


## 左下角的小队成员（11-08 用户：每名干员一个 Q 版像素小人当小摆件，左下角放三个人的小队成员）：
## 队长在最左、画在最前，队友依次往右排、往后叠；一格 5，骑在相框左下角，下沿略出画面，只压卡面左下角的空白。
## 还没有 Q 版的干员跳过（全没有就不画）。
func _peeker(ci: CanvasItem, d: Dictionary, band: Rect2, photo: Rect2, ink := Color.BLACK) -> void:
	var ld := _leader(d)
	var team: Array = []
	if not ld.is_empty():
		team.append(ld)
	for o in d.ops:
		if not o.leader:
			team.append(o)
	var shown: Array = []
	for o in team:
		var tex := chibi(str(o.get("key", "")), 5, ink)
		if tex != null:
			shown.append(tex)
		if shown.size() >= 3:
			break
	var os := outer_size("ri")
	for i in range(shown.size() - 1, -1, -1):   # 后面的先画，队长压在最前
		var tex: Texture2D = shown[i]
		var sz := Vector2(tex.get_width(), tex.get_height())
		ci.draw_texture_rect(tex, Rect2(Vector2(band.position.x + 12.0 + i * 64.0 - sz.x * 0.5, os.y + 8.0 - sz.y), sz), false)


# ---- 罗德岛：灰白渐变背景 + 散落的菱形碎片；白相框黑描边，上边嵌「RHODES ISLAND」；左上徽记、右侧医疗十字气泡、
#      下边黄黑警示格、右下源石结晶簇
const RI_EMBLEM := [".....K.....", "....KWK....", "...KWWWK...", "..KWWKWWK..", ".KWWKYKWWK.", "KWWKYYYKWWK", ".KWWKYKWWK.", "..KWWKWWK..", "...KWWWK...", "....KWK....", ".....K....."]
const RI_BUBBLE := [".KKKKKKK.", "KWWWWWWWK", "KWWWRWWWK", "KWWRRRWWK", "KWWWRWWWK", "KWWWWWWWK", ".KKKWKKK.", "...KWK...", "....K...."]
const RI_ORIG := ["....K.....", "...KOK..K.", "...KOK.KOK", "..KODDKKOK", ".K.KDDKODK", "KOKKODDDDK", "KODKDDODK.", "KDDDODDDK.", ".KKKKKKK.."]

func _ri_bg(ci: CanvasItem, os: Vector2) -> void:
	_quad(ci, [Vector2.ZERO, Vector2(os.x, 0), os, Vector2(0, os.y)], [Color("eef0f3"), Color("eef0f3"), Color("c3c9d2"), Color("c3c9d2")])
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for i in 26:   # 散落的小菱形（黑 / 黄 / 灰），只在相框外
		var p := Vector2(rng.randf() * os.x, rng.randf() * os.y).snapped(Vector2(PX * 0.5, PX * 0.5))
		if Rect2(MARGIN[0] - 40, MARGIN[1] - 64, W + 80, H + 112).has_point(p):
			continue
		var col: Color = [RI_INK, RI_YEL, Color("9aa1ab")][i % 3]
		var c := 3.0 + float(i % 2) * 2.0
		ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -c), p + Vector2(c, 0), p + Vector2(0, c), p + Vector2(-c, 0)]), col)


func _ri_deco(ci: CanvasItem, d: Dictionary, os: Vector2, band: Rect2, photo: Rect2) -> void:
	var pal := {"K": RI_INK, "W": RI_PAPER, "Y": RI_YEL, "R": Color("e8483f"), "O": Color("ff8a3d"), "D": Color("3a3d46")}
	# 下边框：黄黑警示格（两格一条斜纹）
	var by := photo.end.y + 1.0
	var nx := int((band.size.x - PX * 2.0) / PX)
	var ny := int(BAND[3] - 1)
	for j in ny:
		for i in nx:
			if int(floor((i + j) / 2.0)) % 2 == 0:
				ci.draw_rect(Rect2(band.position.x + PX + i * PX, by + j * PX, PX, PX), RI_YEL)
	# 上边框标题
	_px(ci, Vector2(band.position.x + 13 * PX, band.position.y + BAND[1] * PX * 0.5 + 2), "RHODES ISLAND", 3.5, RI_INK, 0, 1)
	_px(ci, Vector2(band.end.x - PX * 2, band.position.y + BAND[1] * PX * 0.5 + 2), str(d.get("date", "")), 1.5, Color("6b6c70"), 2, 2)
	# 左上徽记（压在相框角上）
	_pix(ci, band.position - Vector2(40, 44), RI_EMBLEM, pal, PD)
	# 右侧医疗十字气泡（挂在右边框外）
	_pix(ci, Vector2(band.end.x - 72, photo.position.y + 230), RI_BUBBLE, pal, PD)
	# 右下源石结晶簇
	_pix(ci, band.end - Vector2(60, 66), RI_ORIG, pal, PD)


# ---- 深海：海水渐变背景 + 像素光束 + 像素气泡；浅水色相框深蓝描边，上边嵌「DEEP SEA」；右上大水母探出框外、
#      右侧一条小鱼、下边波纹格、右下珊瑚海草
const SEA_JELLY := ["...KKKKK...", "..KHHHHHK..", ".KHHCCCHHK.", "KHCCCCCCCHK", "KCCCCCCCCCK", "KKCKCKCKCKK", ".C.C.C.C.C.", ".C..C.C..C.", "C..C...C..C", ".C..C...C..", "..C..C.C...", ".C...C..C..", "..C...C...."]
const SEA_FISH := ["..KKKK...K", ".KCCCCK.KC", "KCWKCCCCKC", ".KCCCCK.KC", "..KKKK...K"]
const SEA_CORAL := [".P........", "PPP...G.P.", ".P.P..G.PP", ".PPP.GG.P.", "..P.P.G.PP", "..PPP.GPP.", "...P..GP..", "...P.GGP..", "..KKKKKKKK"]
const SEA_BUBBLE := [".HH.", "H..H", "H..H", ".HH."]

func _deep_bg(ci: CanvasItem, os: Vector2) -> void:
	_quad(ci, [Vector2.ZERO, Vector2(os.x, 0), os, Vector2(0, os.y)], [Color("2a86a8"), Color("2a86a8"), Color("0a2a3d"), Color("0a2a3d")])
	for b in [[40.0, 6], [200.0, 4], [420.0, 7], [620.0, 4]]:   # 像素光束：一格一格往下斜
		var x0: float = b[0]
		var w: int = b[1]
		var y := 0.0
		while y < os.y:
			var a := 0.16 * (1.0 - y / os.y)
			ci.draw_rect(Rect2(Vector2(x0 + y * 0.25, y).snapped(Vector2(PX, PX)), Vector2(w * PX, PX)), Color(SEA_HI, a))
			y += PX
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var pal := {"H": Color(SEA_HI, 0.75)}
	for i in 14:   # 像素气泡，只在相框外
		var p := Vector2(rng.randf() * (os.x - 32), rng.randf() * (os.y - 32)).snapped(Vector2(PX * 0.5, PX * 0.5))
		if Rect2(MARGIN[0] - 48, MARGIN[1] - 72, W + 96, H + 120).has_point(p):
			continue
		_pix(ci, p, SEA_BUBBLE, pal, 4.0 if i % 2 == 0 else 6.0)


func _deep_deco(ci: CanvasItem, d: Dictionary, os: Vector2, band: Rect2, photo: Rect2) -> void:
	var pal := {"K": SEA_INK, "H": SEA_HI, "C": SEA, "W": Color.WHITE, "P": Color("ff7fa8"), "G": Color("3fc59a")}
	# 下边框：波纹格（深浅两色错开）
	var by := photo.end.y + 1.0
	var nx := int((band.size.x - PX * 2.0) / PX)
	for i in nx:
		var h := 1 + int(round((sin(i * 0.8) + 1.0) * 0.5))
		for j in h:
			ci.draw_rect(Rect2(band.position.x + PX + i * PX, by + (BAND[3] - 1 - 1 - j) * PX, PX, PX), Color("5cc8d6") if j == h - 1 else Color("2e8fa8"))
	# 上边框标题 + 日期
	_px(ci, Vector2(band.position.x + PX * 2, band.position.y + BAND[1] * PX * 0.5 + 2), "DEEP SEA", 3.5, SEA_INK, 0, 1)
	_px(ci, Vector2(band.end.x - 15 * PX, band.position.y + BAND[1] * PX * 0.5 + 2), str(d.get("date", "")), 1.5, Color("2e6e7d"), 2, 2)
	# 右上大水母（伞盖探出框外，触手垂在相框带上）
	for gi in 4:
		ci.draw_circle(Vector2(band.end.x - 15, 40), (5.0 + gi * 3.0) * 10.0 * 0.5, Color(SEA, 0.1 - gi * 0.02))
	_pix(ci, Vector2(band.end.x - 70, 8), SEA_JELLY, pal, 10.0)
	# 右侧小鱼
	_pix(ci, Vector2(band.end.x - 54, photo.position.y + 300), SEA_FISH, pal, 9.0)
	# 右下珊瑚海草
	_pix(ci, band.end - Vector2(60, 66), SEA_CORAL, pal, PD)


func _px(ci: CanvasItem, p: Vector2, s: String, kk: float, col: Color, align := 0, track := 1) -> float:
	return TUI.ptext(ci, _pc, p, s, kk, col, track, align)


## 像素描边字（一圈 line、中间 fill）
func _px_line(ci: CanvasItem, p: Vector2, s: String, kk: float, line: Color, fill: Color, align := 0) -> void:
	var dd := maxf(1.0, kk / 3.0)
	for o in [Vector2(-dd, 0), Vector2(dd, 0), Vector2(0, -dd), Vector2(0, dd), Vector2(-dd, -dd), Vector2(dd, dd), Vector2(-dd, dd), Vector2(dd, -dd)]:
		_px(ci, p + o, s, kk, line, align)
	_px(ci, p, s, kk, fill, align)


static func _leader(d: Dictionary) -> Dictionary:
	for o in d.ops:
		if o.leader:
			return o
	return d.ops[0] if not d.ops.is_empty() else {}


# ---------------------------------------------------------------- 作战报告
func _report(ci: CanvasItem, d: Dictionary) -> void:
	var won: bool = d.won
	var ld := _leader(d)
	var acc: Color = SB.lead_theme(ld.get("col", HH.CYB) if not ld.is_empty() else HH.CYB, won)
	ci.draw_rect(Rect2(0, 0, W, H), HH.DARK)
	HH.fill(ci, PackedVector2Array([Vector2(300, 0), Vector2(W, 0), Vector2(W, 690), Vector2(140, 690)]), Color(1, 1, 1, 0.03))
	for i in 7:   # 斜向速度线（静帧取结算出场后的淡态）
		ci.draw_rect(Rect2(40.0 + float((i * 211) % 300), 24.0 + i * 27.0, 120.0 + float((i * 137) % 200), 2), Color(acc, 0.1))
	var em := Vector2(40, 21)   # 徽记：三层菱形
	for q in [[14.0, HH.LIGHT], [9.0, HH.DARK], [5.0, acc]]:
		var qr: float = q[0]
		ci.draw_colored_polygon(PackedVector2Array([em + Vector2(0, -qr), em + Vector2(qr, 0), em + Vector2(0, qr), em + Vector2(-qr, 0)]), q[1])
	_px(ci, Vector2(64, 12), "RHODES ISLAND", 1.5, HH.MUTE, 0, 2)   # 1:1 导出时 1.5 倍取整成 2 像素格（字高 14），行距留 18
	_px(ci, Vector2(64, 30), "OPERATION REPORT", 1.5, HH.MUTE, 0, 2)
	# 巨型描边英文结果
	var word := "COMPLETE" if won else "FAILED"
	var kk := 11.0
	while kk > 6.0 and TUI.ptext_w(_pc, word, kk) > W - 56.0:
		kk -= 0.5
	_px_line(ci, Vector2(28, 92), word, kk, acc, HH.DARK)
	# 中文结果块 + 结局 / 用时
	HH.para(ci, Rect2(28, 146, 236, 56), acc.lerp(HH.LIGHT, 0.6))
	_t(ci, Vector2(48, 152), d.result, 34, HH.INK)
	_t(ci, Vector2(284, 150), d.ending, 14, HH.LIGHT, "l", W - 312)
	_t(ci, Vector2(284, 176), "探索用时 %s  ·  %s" % [_time(d.t), d.tier], 13, HH.MUTE, "l", W - 312)
	# 左侧暗斜板 + 队长立绘
	HH.fill(ci, PackedVector2Array([Vector2(0, 224), Vector2(330, 224), Vector2(280, 590), Vector2(0, 590)]), HH.DARK2.lerp(acc, 0.1))
	HH.fill(ci, PackedVector2Array([Vector2(330, 224), Vector2(337, 224), Vector2(287, 590), Vector2(280, 590)]), acc)
	_px(ci, Vector2(28, 242), "LEADER", 2.0, HH.MUTE, 0, 2)
	if not ld.is_empty():
		var en := str(ld.en)
		if TUI.ptext_w(_pc, en, 5.0) > 290.0:   # 长英文名（SKADI THE CORRUPTING HEART）只留首词
			en = en.get_slice(" ", 0)
		_px(ci, Vector2(28, 282), en, 5.0, Color(ld.col, 0.18))
		_art(ci, ld.art, Rect2(24, 252, 250, 290), Color.WHITE if won else Color(0.52, 0.52, 0.58))
		HH.para(ci, Rect2(16, 548, 250, 34), HH.LIGHT)
		ci.draw_rect(Rect2(16, 582, 250, 3), acc)
		_t(ci, Vector2(34, 553), str(ld.name), 20, HH.INK)
		_t(ci, Vector2(34 + font.get_string_size(str(ld.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 10, 559), "队长  Lv.%d" % int(d.get("level", 1)), 12, HH.INK2)
		if not won:   # 击倒章（洋红，斜盖在立绘上）
			ci.draw_set_transform_matrix(_xf * Transform2D(-0.12, Vector2(220, 300)))
			ci.draw_rect(Rect2(-56, -22, 112, 44), SB.MAG, false, 3.0)
			_t(ci, Vector2(0, -19), "击倒", 28, SB.MAG, "c", 112)
			ci.draw_set_transform_matrix(_xf)
	# 右侧：评级 + 数据格
	var gk: float = [14.0, 11.0, 8.0][clampi(str(d.grade).length() - 1, 0, 2)]
	_px_line(ci, Vector2(466, 302), str(d.grade), gk, acc, HH.LIGHT if won else HH.DARK3, 1)
	# 「RATING」按两行字实际画出的格高摆在评级字上方（卡面缩小时像素格取整、不能小于 1 像素，写死的坐标会叠上）
	var gtop: float = 302.0 - (3.5 * TUI.cell(_pc, gk) + TUI.cell(_pc, gk / 3.0)) / _pc.k
	_px(ci, Vector2(466, gtop - 6.0 - 3.5 * TUI.cell(_pc, 2.0) / _pc.k), "RATING", 2.0, HH.MUTE, 1, 2)
	var cells: Array = [[d.hi_label, str(d.hi), 360.0, 370.0, 30], ["击败敌人", g.run_stats.fmt_n(float(d.kills)), 360.0, 444.0, 24], ["潮位", str(d.tier), 470.0, 444.0, 24],
		["编队", "%d 名" % d.ops.size(), 360.0, 508.0, 24], ["藏品", str(d.get("relic_n", d.relics.size())), 470.0, 508.0, 24]]
	for c in cells:
		ci.draw_rect(Rect2(c[2], c[3], 3, 50), acc if c[3] < 400.0 else HH.DARK3)
		_t(ci, Vector2(c[2] + 12, c[3]), str(c[0]), 12, HH.MUTE)
		_t(ci, Vector2(c[2] + 12, c[3] + 14), str(c[1]), int(c[4]), HH.LIGHT, "l", W - c[2] - 40)
	# 编队一排（色块 + 名字）+ 关键藏品
	_t(ci, Vector2(28, 602), "|  编队", 12, HH.MUTE)
	var n: int = mini(d.ops.size(), 6)
	for i in n:
		var o: Dictionary = d.ops[i]
		var x := 96.0 + i * 82.0
		if o.leader:
			ci.draw_rect(Rect2(x - 4, 600, 80, 20), Color(acc, 0.16))
		ci.draw_rect(Rect2(x, 604, 4, 12), o.col)
		_t(ci, Vector2(x + 9, 602), str(o.name), 13, HH.LIGHT if o.leader else HH.LIGHT2, "l", 70)
	_relic_row(ci, d.relics, Vector2(28, 630), 46.0, 8.0, acc)


## 底部白条：头像昵称 + 二维码（没有就写游戏名）
func _footer(ci: CanvasItem, d: Dictionary, acc: Color) -> void:
	ci.draw_rect(Rect2(0, 690, W, 110), HH.LIGHT)
	ci.draw_rect(Rect2(0, 690, W, 4), acc)
	var tx := 28.0
	if d.avatar is Texture2D:
		_avatar(ci, d, Vector2(54, 745), 30.0, acc)
		tx = 96.0
	_t(ci, Vector2(tx, 722), d.name, 20, HH.INK)
	if d.qr is Texture2D:
		_t(ci, Vector2(tx, 750), "扫码一起潜入深海", 13, HH.INK2)
		_qr(ci, d, Rect2(W - 104, 702, 86, 86), HH.LIGHT)
	else:   # 没有二维码（itch / 桌面版）：右侧写游戏名
		_t(ci, Vector2(tx, 750), "一起潜入深海", 13, HH.INK2)
		_t(ci, Vector2(W - 28, 716), GAME, 22, HH.INK, "r")
		_t(ci, Vector2(W - 28, 748), "明日方舟同人作品", 12, HH.INK2, "r")


## 立绘按包围盒以 0.5 倍为档缩放、脚底对齐，夹在框里不出框
func _art(ci: CanvasItem, a: Dictionary, box: Rect2, mod: Color) -> void:
	OpFig.draw(ci, a, box, 0, mod)   # 全员同一比例、脚底对齐（screens/op_figure.gd，同结算 / 作战记录）


# ---------------------------------------------------------------- 共用部件
## 关键藏品一排：图标（没有图标画稀有度色块 + 名字首字）
func _relic_row(ci: CanvasItem, relics: Array, p: Vector2, sz: float, gap: float, acc: Color) -> void:
	var rc := {"升华": Color8(170, 120, 255), "遭诅古物": SB.MAG}
	for i in mini(6, relics.size()):
		var rl: Dictionary = relics[i]
		var r := Rect2(p.x + i * (sz + gap), p.y, sz, sz)
		ci.draw_rect(r, HH.DARK2)
		ci.draw_rect(r.grow(-2), Color(1, 1, 1, 0.5), false, 1.0)
		var tx: Texture2D = g.run_stats._relic_tex(str(rl.id)) if g.run_stats.has_method("_relic_tex") else null
		if tx != null:
			var s: float = floorf((sz - 8) / maxf(tx.get_width(), tx.get_height()))
			s = maxf(1.0, s)
			var ts := Vector2(tx.get_width(), tx.get_height()) * s
			ci.draw_texture_rect(tx, Rect2(r.get_center() - ts / 2.0, ts), false)
		else:
			_t(ci, r.get_center() - Vector2(0, 12), str(rl.name).substr(0, 1), 20, HH.LIGHT, "c", sz)
		ci.draw_colored_polygon(PackedVector2Array([Vector2(r.position.x, r.end.y - 13), Vector2(r.position.x + 13, r.end.y), Vector2(r.position.x, r.end.y)]), rc.get(str(rl.rarity), acc))   # 左下角稀有度三角


func _avatar(ci: CanvasItem, d: Dictionary, c: Vector2, r: float, ring: Color) -> void:
	ci.draw_circle(c, r + 2, ring)
	ci.draw_texture_rect(d.avatar, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false)


## 二维码（toy.getQrCode 的 PNG）：留白边
func _qr(ci: CanvasItem, d: Dictionary, r: Rect2, bg: Color) -> void:
	ci.draw_rect(r.grow(4), bg)
	ci.draw_texture_rect(d.qr, r, false)
