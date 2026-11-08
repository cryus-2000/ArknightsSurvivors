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


# ---------------------------------------------------------------- 拍立得相框（11-08 用户：关注、三连各送一种专属边框；关注 = 罗德岛，三连 = 深海）
## 卡面 = 相纸：四周边 PM、作战报告缩进去当照片，下巴（约 140 高）放昵称 / 日期 / 二维码。
const FRAMES := {
	"ri": {"name": "罗德岛", "item": "follow"},
	"deep": {"name": "深海", "item": "triple"},
}
const PM := 24.0          # 相纸边
const PHOTO_H := 690.0    # 作战报告（不含底部白条）的高
const RI_INK := Color("17181b")
const RI_SUB := Color("6b6c70")
const RI_YEL := Color("f2c230")
const SEA := Color("7ff0ee")
const SEA_HI := Color("e9ffff")


## 本局用哪种相框：--shareframe=<id> 截图用；否则取已解锁的（toy_support.frames），都没有 = 旧卡面（""）
static func frame_pick() -> String:
	for a in Cfg.dev_args():
		if a.begins_with("--shareframe="):
			return a.substr(13)
	if Cfg.dev_args().has("--supframe"):
		return "deep"
	var fs: Array = preload("res://scripts/core/toy_support.gd").frames()
	return str(fs[-1]) if not fs.is_empty() else ""


func _set_xf(ci: CanvasItem, xf: Transform2D) -> void:
	_xf = xf
	ci.draw_set_transform_matrix(_xf)
	var x: Transform2D = TUI.ctx(ci).xf * _xf
	_pc = {"xf": x, "inv": x.affine_inverse(), "k": maxf(0.01, x.get_scale().x)}


func _quad(ci: CanvasItem, pts: Array, cols: Array) -> void:
	ci.draw_polygon(PackedVector2Array(pts), PackedColorArray(cols))


func _polaroid(ci: CanvasItem, d: Dictionary, fr: String) -> void:
	var s: float = (W - PM * 2.0) / W
	var photo := Rect2(PM, PM, W - PM * 2.0, PHOTO_H * s)
	var chin := Rect2(0, photo.end.y, W, H - photo.end.y)
	var card := _xf
	if fr == "ri":
		_ri_back(ci, photo)
	else:
		_deep_back(ci, photo, Rect2(0, 0, W, H))
	_set_xf(ci, card * Transform2D(0.0, Vector2(s, s), 0.0, photo.position))
	_report(ci, d)
	_set_xf(ci, card)
	if fr == "ri":
		ci.draw_rect(chin, Color("e9e9e6"))   # 作战报告的底色会伸进下巴，重铺
		_ri_front(ci, d, photo, chin)
	else:
		_deep_back(ci, photo, chin)
		_deep_front(ci, d, photo, chin)


# ---- 罗德岛：浅灰档案相纸、照片硬投影、顶边黑标签、左边刻度尺、下巴斜切黑名牌 + 巨型水印、右下角黑三角
func _ri_back(ci: CanvasItem, photo: Rect2) -> void:
	_quad(ci, [Vector2(0, 0), Vector2(W, 0), Vector2(W, H), Vector2(0, H)], [Color("f5f5f3"), Color("eeeeeb"), Color("e3e3df"), Color("ebebe8")])
	ci.draw_rect(Rect2(photo.position + Vector2(5, 5), photo.size), Color("c8c8c3"))   # 硬投影（印刷错位感）


func _ri_front(ci: CanvasItem, d: Dictionary, photo: Rect2, chin: Rect2) -> void:
	# 下巴底纹：浅灰巨型水印「RHODES」，被底边裁掉一截
	_px(ci, Vector2(W - 64, H - 34), "RHODES", 9.0, Color("dfdfda"), 2, 1)
	ci.draw_rect(Rect2(photo.position + Vector2(photo.size.x, 5), Vector2(5, photo.size.y)), Color("c8c8c3"))   # 投影右缘被下巴盖掉的那段补回
	ci.draw_rect(Rect2(photo.position + Vector2(5, photo.size.y), Vector2(photo.size.x, 5)), Color("c8c8c3"))
	ci.draw_rect(photo, RI_INK, false, 1.0)
	# 顶边：黑标签 + 细线 + 右端小字
	var tag := Rect2(PM, 5, TUI.ptext_w(_pc, "RHODES ISLAND", 1.5) / _pc.k + 34.0, 14)
	ci.draw_rect(tag, RI_INK)
	var em := Vector2(tag.position.x + 9, tag.get_center().y)
	ci.draw_colored_polygon(PackedVector2Array([em + Vector2(0, -4.5), em + Vector2(4.5, 0), em + Vector2(0, 4.5), em + Vector2(-4.5, 0)]), RI_YEL)
	_px(ci, Vector2(tag.position.x + 20, tag.get_center().y), "RHODES ISLAND", 1.5, Color("f5f5f3"), 0, 2)
	ci.draw_line(Vector2(tag.end.x + 8, 12), Vector2(W - PM - 70, 12), Color(RI_INK, 0.5), 1.0)
	_px(ci, Vector2(W - PM, 12), "PRTS / FIELD PHOTO", 1.5, RI_SUB, 2, 2)
	# 左边刻度尺
	var y := photo.position.y
	var i := 0
	while y <= photo.end.y:
		var l := 10.0 if i % 5 == 0 else 5.0
		ci.draw_line(Vector2(PM - 6 - l, y), Vector2(PM - 6, y), Color(RI_INK, 0.55 if i % 5 == 0 else 0.3), 1.0)
		y += 16.0
		i += 1
	# 下巴：斜切黑名牌（左侧黄条）+ 日期 · 结果
	var nm := Rect2(PM, chin.position.y + 22, 236, 42)
	HH.para(ci, nm, RI_INK)
	ci.draw_rect(Rect2(nm.position.x + 10, nm.position.y + 9, 4, nm.size.y - 18), RI_YEL)
	var tx := nm.position.x + 26.0
	if d.avatar is Texture2D:
		_avatar(ci, d, Vector2(tx + 14, nm.get_center().y), 14.0, RI_YEL)
		tx += 36.0
	_t(ci, Vector2(tx, nm.position.y + 8), d.name, 22, Color("f5f5f3"), "l", nm.end.x - tx - 20)
	_px(ci, Vector2(PM + 2, nm.end.y + 16), "OPERATOR", 1.5, RI_SUB, 0, 2)
	_t(ci, Vector2(PM + 2 + TUI.ptext_w(_pc, "OPERATOR", 1.5) / _pc.k + 12, nm.end.y + 7), "%s  ·  %s" % [str(d.get("date", "")), d.result], 13, RI_SUB)
	# 右：二维码 / 游戏名
	if d.qr is Texture2D:
		_qr(ci, d, Rect2(W - PM - 96, chin.position.y + 20, 86, 86), Color("f5f5f3"))
	else:
		_t(ci, Vector2(W - PM - 12, chin.position.y + 26), GAME, 22, RI_INK, "r")
		_t(ci, Vector2(W - PM - 12, chin.position.y + 58), "明日方舟同人作品", 12, RI_SUB, "r")
	# 右下角：黑三角 + 黄斜条
	var c := Vector2(W, H)
	ci.draw_colored_polygon(PackedVector2Array([c, c - Vector2(56, 0), c - Vector2(0, 56)]), RI_INK)
	ci.draw_colored_polygon(PackedVector2Array([c - Vector2(66, 0), c - Vector2(60, 0), c - Vector2(0, 60), c - Vector2(0, 66)]), RI_YEL)


# ---- 深海：上浅下深的海水相纸、自上而下的光束、浮游微粒、照片青色微光、下巴大水母（伞盖压在照片角上）
func _deep_back(ci: CanvasItem, photo: Rect2, clip: Rect2) -> void:
	var top := Color("15405a")
	var bot := Color("03111a")
	var t0: Color = top.lerp(bot, clip.position.y / H)
	var t1: Color = top.lerp(bot, clip.end.y / H)
	_quad(ci, [clip.position, Vector2(clip.end.x, clip.position.y), clip.end, Vector2(clip.position.x, clip.end.y)], [t0, t0, t1, t1])
	# 光束：从上往下淡出
	for b in [[40.0, 60.0, 0.2], [190.0, 30.0, 0.14], [300.0, 80.0, 0.16], [480.0, 40.0, 0.12]]:
		var x0: float = b[0]
		var w: float = b[1]
		var a: float = b[2]
		var y0 := clip.position.y
		var y1 := clip.end.y
		var dx := 0.28   # 斜率
		var ca := Color(SEA_HI, a * (1.0 - y0 / H))
		var cb := Color(SEA_HI, a * (1.0 - y1 / H))
		_quad(ci, [Vector2(x0 + y0 * dx, y0), Vector2(x0 + w + y0 * dx, y0), Vector2(x0 + w * 1.8 + y1 * dx, y1), Vector2(x0 + y1 * dx, y1)], [ca, ca, cb, cb])
	# 浮游微粒（固定种子）
	var rng := RandomNumberGenerator.new()
	rng.seed = 1108
	for i in 220:
		var p := Vector2(rng.randf() * W, rng.randf() * H)
		var sz := 2.0 if rng.randf() < 0.7 else 3.0
		var a2 := 0.15 + 0.55 * rng.randf()
		if not clip.has_point(p) or photo.grow(2.0).has_point(p):
			continue
		ci.draw_rect(Rect2(p.floor(), Vector2(sz, sz)), Color(SEA, a2))
		if sz > 2.0:
			ci.draw_circle(p + Vector2(1.5, 1.5), 6.0, Color(SEA, a2 * 0.12))


func _deep_front(ci: CanvasItem, d: Dictionary, photo: Rect2, chin: Rect2) -> void:
	# 照片青色微光
	for gi in 4:
		ci.draw_rect(photo.grow(1.0 + gi * 2.5), Color(SEA, 0.26 - gi * 0.06), false, 2.0)
	ci.draw_rect(photo, Color(SEA_HI, 0.85), false, 1.0)
	# 两侧气泡往上冒
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 18:
		var left := i % 2 == 0
		var p := Vector2((7.0 + rng.randf() * 10.0) if left else (W - 7.0 - rng.randf() * 10.0), 60.0 + rng.randf() * (H - 120.0))
		ci.draw_arc(p, 1.5 + 2.5 * (p.y / H), 0.0, TAU, 10, Color(SEA_HI, 0.2 + 0.35 * (p.y / H)), 1.0)
	# 大水母：伞盖压住照片右下角，触手垂出卡外
	_big_jelly(ci, Vector2(W - PM - 86, photo.end.y - 62), 5.0)
	_small_jelly(ci, Vector2(W - PM - 196, chin.position.y + 74), 3.0, 0.6)
	_small_jelly(ci, Vector2(W - PM - 20, chin.position.y + 98), 2.0, 0.35)
	# 下巴文字
	var tx := PM + 6.0
	var cy := chin.position.y + 30.0
	if d.avatar is Texture2D:
		_avatar(ci, d, Vector2(tx + 24, cy + 22), 24.0, SEA)
		tx += 60.0
	_t(ci, Vector2(tx, cy), d.name, 26, SEA_HI)
	var pts := PackedVector2Array()
	for i in 41:
		pts.append(Vector2(tx + i * 4.0, cy + 34 + sin(i * 0.7) * 1.8))
	ci.draw_polyline(pts, Color(SEA, 0.55), 1.2)
	_t(ci, Vector2(tx, cy + 44), "%s  ·  %s" % [str(d.get("date", "")), d.result], 13, Color("79b9c1"))
	if d.qr is Texture2D:
		_qr(ci, d, Rect2(W * 0.5 - 50, chin.position.y + 24, 86, 86), Color("e9ffff"))
	else:
		_t(ci, Vector2(tx, cy + 66), GAME + "  ·  明日方舟同人作品", 11, Color("4f8d96"))


## 像素水母：伞盖上亮下暗 + 光晕 + 口腕 + 摆动的长触手（k = 像素格）
const JELLY_CAP := [".....#####.....", "...#########...", "..###########..", ".#############.", ".#############.", "###############", "#.##.##.##.##.#"]

func _big_jelly(ci: CanvasItem, c: Vector2, k: float) -> void:
	var half := 7.5
	var ctr := c + Vector2(0, 3.0 * k)
	for gi in 6:
		ci.draw_circle(ctr, (10.0 + gi * 6.0) * k * 0.5, Color(SEA, 0.07 - gi * 0.01))
	# 触手：从伞缘 5 处垂下，正弦摆动、越往下越淡
	for ti in 5:
		var x0: float = (1.5 + ti * 3.0 - half) * k
		for j in 26:
			var y := (7.0 + j) * k
			var x := x0 + sin(j * 0.45 + ti * 1.3) * (1.0 + j * 0.12) * k
			ci.draw_rect(Rect2(c + Vector2(x, y).snapped(Vector2(k, k)), Vector2(k, k)), Color(SEA, 0.55 * (1.0 - j / 26.0)))
	# 口腕：中间两条粗一点
	for oi in 2:
		var x1: float = (-1.0 + oi * 2.0) * k
		for j in 16:
			var y := (7.0 + j) * k
			var x := x1 + sin(j * 0.35 + oi * 2.0) * 1.5 * k
			ci.draw_rect(Rect2(c + Vector2(x - k * 0.5, y).snapped(Vector2(k, k)), Vector2(k * 2.0, k)), Color(SEA_HI, 0.6 * (1.0 - j / 16.0)))
	# 伞盖
	for y in JELLY_CAP.size():
		var row: String = JELLY_CAP[y]
		var col: Color = SEA_HI.lerp(SEA, float(y) / (JELLY_CAP.size() - 1))
		for x in row.length():
			if row[x] == "#":
				ci.draw_rect(Rect2(c + Vector2((x - half) * k, y * k), Vector2(k, k)), Color(col, 0.92))
	# 伞盖高光
	ci.draw_rect(Rect2(c + Vector2(-4.5 * k, 1.0 * k), Vector2(3.0 * k, k)), Color(1, 1, 1, 0.9))
	ci.draw_rect(Rect2(c + Vector2(-5.5 * k, 2.0 * k), Vector2(k, k)), Color(1, 1, 1, 0.7))


func _small_jelly(ci: CanvasItem, c: Vector2, k: float, a: float) -> void:
	for gi in 3:
		ci.draw_circle(c + Vector2(0, 2.0 * k), (6.0 + gi * 4.0) * k * 0.5, Color(SEA, a * (0.1 - gi * 0.03)))
	var pat := ["..###..", ".#####.", "#######", "#.#.#.#"]
	for y in pat.size():
		var row: String = pat[y]
		for x in row.length():
			if row[x] == "#":
				ci.draw_rect(Rect2(c + Vector2((x - 3.5) * k, y * k), Vector2(k, k)), Color(SEA_HI.lerp(SEA, y / 3.0), a))
	for ti in 3:
		for j in 7:
			ci.draw_rect(Rect2(c + Vector2((-2.5 + ti * 2.0) * k + sin(j * 0.6 + ti) * k, (4 + j) * k).snapped(Vector2(k, k)), Vector2(k, k)), Color(SEA, a * 0.6 * (1.0 - j / 7.0)))




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
