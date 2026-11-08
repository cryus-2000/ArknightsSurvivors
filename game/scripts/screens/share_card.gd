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
func draw(ci: CanvasItem, d: Dictionary, pos: Vector2, k: float, rot := 0.0) -> void:
	_xf = Transform2D(rot, Vector2(k, k), 0.0, pos + Vector2(W, H) * k * 0.5) * Transform2D(0.0, -Vector2(W, H) * 0.5)
	ci.draw_set_transform_matrix(_xf)
	var x: Transform2D = TUI.ctx(ci).xf * _xf
	_pc = {"xf": x, "inv": x.affine_inverse(), "k": maxf(0.01, x.get_scale().x)}
	var fr := str(d.get("frame", ""))
	if FRAMES.has(fr):
		_polaroid(ci, d, fr)
	else:
		_report(ci, d)
		_footer(ci, d, _acc(d))
	ci.draw_set_transform(Vector2.ZERO)


func _acc(d: Dictionary) -> Color:
	var ld := _leader(d)
	return SB.lead_theme(ld.get("col", HH.CYB) if not ld.is_empty() else HH.CYB, bool(d.won))


# ---------------------------------------------------------------- 拍立得相框（11-08 用户：「跟拍立得一样设计不同的相框」；方向：罗德岛设计感 / 深海感，样张待定）
## 卡面 = 相纸：四周边 PM、作战报告缩进去当照片，下巴（约 140 高）放昵称 / 日期 / 二维码。
## paper / paper2 相纸色（有 paper2 = 上下渐变）、ink / sub 下巴字色、edge 照片内缘线、grain 颗粒色
const FRAMES := {
	"ri_paper": {"name": "罗德岛·档案", "paper": Color("e8e6df"), "ink": Color("17191d"), "sub": Color("6a6862"), "edge": Color(0, 0, 0, 0.35), "grain": Color(0, 0, 0, 0.045)},
	"ri_black": {"name": "罗德岛·作战", "paper": Color("1b1d21"), "ink": Color("eceae4"), "sub": Color("8d929a"), "edge": Color(1, 1, 1, 0.22), "grain": Color(1, 1, 1, 0.03)},
	"tide": {"name": "深海·潮光", "paper": Color("dbeff0"), "paper2": Color("15515f"), "ink": Color("effafa"), "sub": Color("a6d6dc"), "edge": Color(1, 1, 1, 0.35), "grain": Color(1, 1, 1, 0.07)},
	"abyss": {"name": "深海·渊", "paper": Color("0a1a22"), "paper2": Color("061016"), "ink": Color("d9f6f7"), "sub": Color("5f9aa3"), "edge": Color(0.45, 0.95, 0.95, 0.55), "grain": Color(0.5, 1, 1, 0.025)},
	"supporter": {"name": "支持者", "paper": Color("101114"), "ink": Color("f0d48a"), "sub": Color("a38b52"), "edge": Color(0.93, 0.76, 0.33, 0.55), "grain": Color(0.93, 0.76, 0.33, 0.05)},
}
const PM := 24.0          # 相纸边
const PHOTO_H := 690.0    # 作战报告（不含底部白条）的高
const HAZ := Color("f2c230")
const SEA := Color(0.45, 0.95, 0.95)


## 本局用哪种相框：--shareframe=<id> 截图用；三连领过 = 支持者（docs/313）；否则沿用旧卡面（""）
static func frame_pick() -> String:
	for a in Cfg.dev_args():
		if a.begins_with("--shareframe="):
			return a.substr(13)
	if preload("res://scripts/core/toy_support.gd").frame_unlocked() or Cfg.dev_args().has("--supframe"):
		return "supporter"
	return ""


func _set_xf(ci: CanvasItem, xf: Transform2D) -> void:
	_xf = xf
	ci.draw_set_transform_matrix(_xf)
	var x: Transform2D = TUI.ctx(ci).xf * _xf
	_pc = {"xf": x, "inv": x.affine_inverse(), "k": maxf(0.01, x.get_scale().x)}


func _vgrad(ci: CanvasItem, r: Rect2, top: Color, bot: Color) -> void:
	ci.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), PackedColorArray([top, top, bot, bot]))


func _polaroid(ci: CanvasItem, d: Dictionary, fr: String) -> void:
	var st: Dictionary = FRAMES[fr]
	var s: float = (W - PM * 2.0) / W
	var photo := Rect2(PM, PM, W - PM * 2.0, PHOTO_H * s)
	var chin := Rect2(0, photo.end.y, W, H - photo.end.y)
	var card := _xf
	_paper(ci, st, fr, photo)
	_set_xf(ci, card * Transform2D(0.0, Vector2(s, s), 0.0, photo.position))
	_report(ci, d)
	_set_xf(ci, card)
	_paper(ci, st, fr, photo, chin)   # 作战报告的底色会伸进下巴，下巴重铺一遍
	_grain(ci, photo, st.grain)
	match fr:
		"ri_paper":
			_ri_paper(ci, d, photo, chin, st)
		"ri_black":
			_ri_black(ci, d, photo, chin, st)
		"tide":
			_tide(ci, d, photo, chin, st)
		"abyss":
			_abyss(ci, d, photo, chin, st)
		_:
			ci.draw_rect(photo, st.edge, false, 1.5)
			_gold_edges(ci)
			_chin_text(ci, d, chin, st, PM + 6.0)
			var tag := Rect2(Vector2(W * 0.5 - 62, H - 36), Vector2(124, 22))
			ci.draw_rect(tag, Color(0.05, 0.05, 0.06, 1.0))
			ci.draw_rect(tag, FRAME_GOLD, false, 1.5)
			_px(ci, Vector2(W * 0.5, tag.position.y + 11.0), "SUPPORTER", 1.5, FRAME_GOLD, 1, 2)


## 相纸底：整张（clip 为空）或只铺 clip 那一块
func _paper(ci: CanvasItem, st: Dictionary, fr: String, photo: Rect2, clip := Rect2()) -> void:
	var full := Rect2(0, 0, W, H)
	var r := full if clip.size == Vector2.ZERO else clip
	if st.has("paper2"):
		var t0: Color = st.paper.lerp(st.paper2, r.position.y / H)
		var t1: Color = st.paper.lerp(st.paper2, r.end.y / H)
		_vgrad(ci, r, t0, t1)
	else:
		ci.draw_rect(r, st.paper)
	if fr == "tide" and clip.size == Vector2.ZERO:   # 潮光：自上而下的几道斜光（照片会盖住中间，只在相纸上看得到）
		for i in 5:
			var x0 := 40.0 + i * 120.0
			var w := 26.0 + (i % 3) * 14.0
			ci.draw_colored_polygon(PackedVector2Array([Vector2(x0, 0), Vector2(x0 + w, 0), Vector2(x0 + w + 160, H), Vector2(x0 + 160, H)]), Color(1, 1, 1, 0.07))


## 相纸颗粒：固定种子的小点，只撒在照片外（导出图逐张一致）
func _grain(ci: CanvasItem, photo: Rect2, col: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1108
	for i in 900:
		var p := Vector2(rng.randf() * W, rng.randf() * H)
		if photo.grow(1.0).has_point(p):
			continue
		ci.draw_rect(Rect2(p.floor(), Vector2(2, 2)), col)


## 昵称 + 日期 · 结果（下巴左栏），返回下一行 y
func _chin_text(ci: CanvasItem, d: Dictionary, chin: Rect2, st: Dictionary, tx: float, y0 := -1.0) -> void:
	var cy := chin.position.y + 30.0 if y0 < 0.0 else y0
	if d.avatar is Texture2D:
		_avatar(ci, d, Vector2(tx + 24, cy + 22), 24.0, st.ink)
		tx += 60.0
	_t(ci, Vector2(tx, cy), d.name, 24, st.ink)
	_t(ci, Vector2(tx, cy + 36), "%s  ·  %s" % [str(d.get("date", "")), d.result], 13, st.sub)


## 右栏：有二维码画二维码，否则写游戏名
func _chin_right(ci: CanvasItem, d: Dictionary, chin: Rect2, st: Dictionary, right: float, y0: float) -> void:
	if d.qr is Texture2D:
		_qr(ci, d, Rect2(right - 86, chin.position.y + 24, 86, 86), Color("efebe2"))
	else:
		_t(ci, Vector2(right, y0), GAME, 22, st.ink, "r")
		_t(ci, Vector2(right, y0 + 32), "明日方舟同人作品", 12, st.sub, "r")


# ---- 罗德岛·档案：米白档案相纸 + 定位十字 + 警示斜纹 + 条码编号
func _ri_paper(ci: CanvasItem, d: Dictionary, photo: Rect2, chin: Rect2, st: Dictionary) -> void:
	var ink: Color = st.ink
	# 相纸细网格（只在边与下巴）
	for x in range(0, int(W) + 1, 24):
		ci.draw_line(Vector2(x, photo.end.y + 2), Vector2(x, H), Color(ink, 0.05), 1.0)
	for y in range(int(photo.end.y) + 24, int(H), 24):
		ci.draw_line(Vector2(0, y), Vector2(W, y), Color(ink, 0.05), 1.0)
	ci.draw_rect(photo, st.edge, false, 1.5)
	# 照片四角定位十字
	for c in [photo.position, Vector2(photo.end.x, photo.position.y), Vector2(photo.position.x, photo.end.y), photo.end]:
		ci.draw_line(c + Vector2(-10, 0), c + Vector2(10, 0), Color(ink, 0.7), 1.5)
		ci.draw_line(c + Vector2(0, -10), c + Vector2(0, 10), Color(ink, 0.7), 1.5)
	# 上边小字
	_px(ci, Vector2(PM, 8), "PRTS  //  FIELD PHOTO", 1.5, Color(ink, 0.55), 0, 2)
	_px(ci, Vector2(W - PM, 8), "RI-%s" % str(d.get("date", "")).replace(".", ""), 1.5, Color(ink, 0.55), 2, 2)
	# 下巴：左侧警示斜纹竖条 + 黑底标签
	var hz := Rect2(PM, chin.position.y + 18, 12, chin.size.y - 40)
	_hazard(ci, hz, HAZ, ink)
	var tx := hz.end.x + 16.0
	var lab := Rect2(tx, chin.position.y + 16, TUI.ptext_w(_pc, "OPERATOR RECORD", 1.5) / _pc.k + 14.0, 18)
	ci.draw_rect(lab, ink)
	_px(ci, Vector2(lab.position.x + 7, lab.position.y + 9), "OPERATOR RECORD", 1.5, st.paper, 0, 2)
	_chin_text(ci, d, chin, st, tx, chin.position.y + 42)
	# 右侧：条码 + 编号（有二维码就换成二维码）
	var right := W - PM
	if d.qr is Texture2D:
		_qr(ci, d, Rect2(right - 86, chin.position.y + 22, 86, 86), st.paper)
	else:
		var bc := Rect2(right - 150, chin.position.y + 20, 150, 40)
		_barcode(ci, bc, ink, str(d.get("date", "")) + str(d.result))
		_px(ci, Vector2(right, bc.end.y + 14), "RHODES ISLAND", 1.5, Color(ink, 0.6), 2, 2)
		_t(ci, Vector2(right, bc.end.y + 30), GAME + "  ·  明日方舟同人作品", 11, st.sub, "r")


## 警示斜纹：底色 a 上画 b 色 45° 斜条（竖条 / 横条都行，逐条按矩形裁好再画）
func _hazard(ci: CanvasItem, r: Rect2, a: Color, b: Color) -> void:
	ci.draw_rect(r, a)
	var step := 12.0
	var band := 6.0
	var span := r.size.x + r.size.y
	var o := -r.size.y
	while o < span:
		# 斜条：x - (y - top) 介于 [o, o + band] 之间的部分
		var pts := PackedVector2Array()
		for q in [[o, 0.0], [o + band, 0.0], [o + band, 1.0], [o, 1.0]]:
			var yy: float = r.position.y + q[1] * r.size.y
			pts.append(Vector2(r.position.x + q[0] + (yy - r.position.y), yy))
		var clip := Geometry2D.intersect_polygons(pts, PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]))
		for poly in clip:
			ci.draw_colored_polygon(poly, b)
		o += step


func _barcode(ci: CanvasItem, r: Rect2, col: Color, key: String) -> void:
	var h := key.hash()
	var x := r.position.x
	var i := 0
	while x < r.end.x - 2.0:
		var w := 1.0 + float((h >> (i % 28)) & 3)
		if i % 2 == 0:
			ci.draw_rect(Rect2(x, r.position.y, w, r.size.y), col)
		x += w + 1.0
		i += 1


# ---- 罗德岛·作战：炭黑相纸 + 照片外折角框 + 竖排公司名 + 底边警示条
func _ri_black(ci: CanvasItem, d: Dictionary, photo: Rect2, chin: Rect2, st: Dictionary) -> void:
	var ink: Color = st.ink
	ci.draw_rect(photo, st.edge, false, 1.0)
	var o := photo.grow(7.0)
	var l := 22.0
	for c in [[o.position, 1, 1], [Vector2(o.end.x, o.position.y), -1, 1], [Vector2(o.position.x, o.end.y), 1, -1], [o.end, -1, -1]]:
		var p: Vector2 = c[0]
		ci.draw_line(p, p + Vector2(l * c[1], 0), ink, 2.0)
		ci.draw_line(p, p + Vector2(0, l * c[2]), ink, 2.0)
	# 右边竖排小字
	var card := _xf
	ci.draw_set_transform_matrix(card * Transform2D(PI * 0.5, Vector2(W - 6, PM + 20)))
	ci.draw_string(font, Vector2(0, 0), "RHODES ISLAND PHARMACEUTICALS INC.   //   OPERATION ARCHIVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(ink, 0.4))
	ci.draw_set_transform_matrix(card)
	# 下巴：徽记 + 青色短条
	var em := Vector2(PM + 18, chin.position.y + 46)
	for q in [[16.0, ink], [10.0, st.paper], [5.0, SEA]]:
		var qr: float = q[0]
		ci.draw_colored_polygon(PackedVector2Array([em + Vector2(0, -qr), em + Vector2(qr, 0), em + Vector2(0, qr), em + Vector2(-qr, 0)]), q[1])
	ci.draw_rect(Rect2(PM + 46, chin.position.y + 22, 44, 3), SEA)
	_chin_text(ci, d, chin, st, PM + 46, chin.position.y + 32)
	_chin_right(ci, d, chin, st, W - PM - 4, chin.position.y + 28)
	_hazard(ci, Rect2(0, H - 8, W, 8), HAZ, st.paper)


# ---- 深海·潮光：上浅下深的海水相纸 + 斜光 + 两侧气泡 + 下巴发光水母
func _tide(ci: CanvasItem, d: Dictionary, photo: Rect2, chin: Rect2, st: Dictionary) -> void:
	ci.draw_rect(photo, st.edge, false, 1.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 26:   # 两侧边上的气泡往上冒
		var left := i % 2 == 0
		var p := Vector2((6.0 + rng.randf() * 12.0) if left else (W - 6.0 - rng.randf() * 12.0), 40.0 + rng.randf() * (H - 80.0))
		var r := 1.5 + rng.randf() * 3.0 * (p.y / H)
		ci.draw_arc(p, r, 0.0, TAU, 10, Color(1, 1, 1, 0.25 + 0.4 * (p.y / H)), 1.0)
	_glow_jelly(ci, Vector2(W * 0.5 + 40, chin.position.y + 18), 4.0, Color(0.8, 1.0, 1.0), 0.85)
	_glow_jelly(ci, Vector2(W * 0.5 + 104, chin.position.y + 70), 2.0, Color(0.8, 1.0, 1.0), 0.5)
	_chin_text(ci, d, chin, st, PM + 6.0)
	_chin_right(ci, d, chin, st, W - PM - 6.0, chin.position.y + 28)


# ---- 深海·渊：近黑海蓝相纸 + 发光照片边 + 下深上浅的荧光微粒 + 大水母剪影 + 波纹分隔
func _abyss(ci: CanvasItem, d: Dictionary, photo: Rect2, chin: Rect2, st: Dictionary) -> void:
	for g in 4:
		ci.draw_rect(photo.grow(1.0 + g * 2.0), Color(SEA, 0.22 - g * 0.05), false, 2.0)
	ci.draw_rect(photo, st.edge, false, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for i in 260:
		var p := Vector2(rng.randf() * W, pow(rng.randf(), 0.6) * H)
		if photo.grow(8.0).has_point(p):
			continue
		var a := 0.15 + 0.6 * rng.randf() * (p.y / H)
		ci.draw_rect(Rect2(p.floor(), Vector2(2, 2)), Color(SEA, a))
		if rng.randf() < 0.08:
			ci.draw_circle(p + Vector2(1, 1), 4.0, Color(SEA, a * 0.18))
	_jelly(ci, Vector2(W - PM - 70, chin.position.y + 4), 8.0, Color(SEA, 0.1), BIG_JELLY)
	_glow_jelly(ci, Vector2(W * 0.5 + 20, chin.position.y + 40), 2.0, SEA, 0.9)
	# 下巴顶的波纹线
	var pts := PackedVector2Array()
	for i in 61:
		var x := PM + (W - PM * 2.0) * i / 60.0
		pts.append(Vector2(x, chin.position.y + 12 + sin(i * 0.55) * 2.5))
	ci.draw_polyline(pts, Color(SEA, 0.45), 1.5)
	_chin_text(ci, d, chin, st, PM + 6.0, chin.position.y + 32)
	_chin_right(ci, d, chin, st, W - PM - 6.0, chin.position.y + 30)


## 像素水母（k = 像素格）；BIG_JELLY 是大号
const JELLY := ["..####..", ".######.", "########", "#.#..#.#", "..#..#..", ".#....#.", "..#..#.."]
const BIG_JELLY := ["....#####....", "..#########..", ".###########.", "#############", "#.#.#.#.#.#.#", "..#..#..#..#.", "..#..#...#.#.", ".#...#..#..#.", "..#...#.#...#", "..#..#..#..#.", ".#...#...#..."]

func _jelly(ci: CanvasItem, c: Vector2, k: float, col: Color, pat: Array = JELLY) -> void:
	var half: float = pat[0].length() * 0.5
	for y in pat.size():
		var row: String = pat[y]
		for x in row.length():
			if row[x] == "#":
				ci.draw_rect(Rect2(c + Vector2((x - half) * k, y * k), Vector2(k, k)), col if y < 4 else Color(col, col.a * 0.7))


func _glow_jelly(ci: CanvasItem, c: Vector2, k: float, col: Color, a: float) -> void:
	var ctr := c + Vector2(0, 2.0 * k)
	for g in 4:
		ci.draw_circle(ctr, (6.0 + g * 5.0) * k * 0.5, Color(col, a * (0.12 - g * 0.025)))
	_jelly(ci, c, k, Color(col, a), BIG_JELLY if k >= 3.0 else JELLY)


## 支持者：金箔双线 + 四角折角
func _gold_edges(ci: CanvasItem) -> void:
	var r := Rect2(7, 7, W - 14, H - 14)
	ci.draw_rect(r, FRAME_GOLD, false, 2.0)
	ci.draw_rect(Rect2(12, 12, W - 24, H - 24), Color(FRAME_GOLD, 0.45), false, 1.0)
	var l := 40.0
	var t := 5.0
	for c in [[r.position, 1, 1], [Vector2(r.end.x, r.position.y), -1, 1], [Vector2(r.position.x, r.end.y), 1, -1], [r.end, -1, -1]]:
		var p: Vector2 = c[0]
		ci.draw_rect(Rect2(p + Vector2(0 if c[1] > 0 else -l, 0 if c[2] > 0 else -t), Vector2(l, t)), FRAME_GOLD)
		ci.draw_rect(Rect2(p + Vector2(0 if c[1] > 0 else -t, 0 if c[2] > 0 else -l), Vector2(t, l)), FRAME_GOLD)


## 专属分享卡边框色（B站 Toy 三连奖励，docs/313）
const FRAME_GOLD := Color(0.93, 0.76, 0.33)


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
