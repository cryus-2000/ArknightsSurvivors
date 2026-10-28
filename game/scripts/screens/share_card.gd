extends RefCounted
## 战绩分享卡（10-28 协调人单：结算加「分享战绩」，竖版 3:4；10-28 用户「分享战绩的也做一下」：改成与结算「作战报告」同一视觉语言）。
## 只读结算数据（settlement_screen.model + 编队立绘），不碰模拟与随机数。卡面在 600×800 的版面单位里画，调用方给位置与缩放。
## 巨型描边英文结果横贯上缘 + 中文结果块，左侧暗斜板放队长立绘，右侧评级与数据格，下面编队与藏品，底部白条放头像昵称与二维码。
## 配色跟随本局队长（settle_base.lead_theme，与结算同一套夹取）；失败同色降饱和，队长去色盖洋红「击倒」。
## 结算样式为「合约结算」（ui/settle_style = 2）时换成同一套版式（_contract：徽记 + 三角评级章 + 斜排编队卡格 + 方格获得）。
## 头像 / 昵称 / 二维码由 share_toy.gd 经 Toy SDK 取（先 isSupport）；拿不到（itch / 桌面版 / 用户拒绝）时不画头像，
## 昵称写「博士」，二维码换成游戏名。隐私：头像昵称只在本地画卡，不发往任何第三方、不写日志；toyOpenId 不经过这里（docs/22 Toy 接入）。
const HH = preload("res://scripts/screens/hh_style.gd")
const UI = preload("res://scripts/ui.gd")
const D = preload("res://scripts/data.gd")
const TUI = preload("res://scripts/screens/tide_ui.gd")
const SB = preload("res://scripts/screens/settle/settle_base.gd")

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
		ops.append({"key": str(r.key), "name": str(r.name), "en": str(r.get("en", "")), "elite": int(r.get("elite", 0)), "leader": bool(r.leader), "col": r.col, "art": screen.art.get(r.key, {})})
	var relics: Array = m.get("relic_list", []).duplicate()
	var rank := {"升华": 0, "稀有": 1, "遭诅古物": 2, "基础": 3}
	relics.sort_custom(func(a, b): return int(rank.get(str(a.rarity), 4)) < int(rank.get(str(b.rarity), 4)))
	return {"won": won, "result": "探索完成" if won else "探索终止", "result_en": "OPERATION COMPLETE" if won else "OPERATION FAILED",
		"ending": str(m.get("ending_name", "")) if won else ("击倒：" + str(m.get("killer", {}).get("name", "未知"))),
		"tier": str(D.DIFF_PRESETS[clampi(g.preset, 0, D.DIFF_PRESETS.size() - 1)].name), "t": float(m.get("t", 0.0)),
		"hi_label": "总伤害", "hi": g.run_stats.fmt_n(float(m.get("total", 0.0))), "kills": int(m.get("kills", 0)), "level": int(m.get("level", 1)), "relic_n": int(m.get("relics", relics.size())),
		"grade": screen.grade(m, g.preset), "ops": ops, "relics": relics.slice(0, 6),
		"name": "博士", "avatar": null, "qr": null, "style": screen.style_id()}   # 头像 / 昵称 / 二维码：share_toy.gd 拿到后由结算屏填


## pos = 卡左上角、k = 缩放；rot = 绕卡中心旋转（结算浮层的拍照出场用，导出图不转）
func draw(ci: CanvasItem, d: Dictionary, pos: Vector2, k: float, rot := 0.0) -> void:
	_xf = Transform2D(rot, Vector2(k, k), 0.0, pos + Vector2(W, H) * k * 0.5) * Transform2D(0.0, -Vector2(W, H) * 0.5)
	ci.draw_set_transform_matrix(_xf)
	var x: Transform2D = TUI.ctx(ci).xf * _xf
	_pc = {"xf": x, "inv": x.affine_inverse(), "k": maxf(0.01, x.get_scale().x)}
	if int(d.get("style", 1)) == 2:
		_contract(ci, d)
	else:
		_report(ci, d)
	ci.draw_set_transform(Vector2.ZERO)


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
	for i in 7:   # 斜向速度线（静帧取结算出场后的淡态）
		ci.draw_rect(Rect2(40.0 + float((i * 211) % 300), 24.0 + i * 27.0, 120.0 + float((i * 137) % 200), 2), Color(acc, 0.1))
	var head := "OPERATION REPORT  //  RHODES ISLAND"
	if TUI.ptext_w(_pc, head, 2.0, 2) > W - 56.0:   # 结算浮层里卡面缩小、像素格不能小于 1 像素：放不下就只留前半
		head = "OPERATION REPORT"
	_px(ci, Vector2(28, 26), head, 2.0, HH.MUTE, 0, 2)
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
	_relic_row(ci, d.relics, Vector2(28, 630), 46.0, 8.0)
	_footer(ci, d, acc)


# ---------------------------------------------------------------- 合约结算（借危机合约结算的版式语言）
func _contract(ci: CanvasItem, d: Dictionary) -> void:
	var won: bool = d.won
	var ld := _leader(d)
	var acc: Color = SB.lead_theme(ld.get("col", HH.CYB) if not ld.is_empty() else HH.CYB, won)
	ci.draw_rect(Rect2(0, 0, W, H), HH.DARK)
	HH.fill(ci, PackedVector2Array([Vector2(300, 0), Vector2(W, 0), Vector2(W, 690), Vector2(140, 690)]), Color(1, 1, 1, 0.035))
	# 徽记 + 作战名
	var c := Vector2(58, 52)
	for rr in [[26, HH.LIGHT], [18, HH.DARK], [10, acc]]:
		var q: float = rr[0]
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -q), c + Vector2(q, 0), c + Vector2(0, q), c + Vector2(-q, 0)]), rr[1])
	_px(ci, Vector2(96, 42), "RHODES ISLAND", 1.5, HH.MUTE, 0, 2)
	_px(ci, Vector2(96, 60), "OPERATION REPORT", 1.5, HH.MUTE, 0, 2)
	_t(ci, Vector2(28, 92), d.result, 34, HH.LIGHT)
	_px(ci, Vector2(32, 144), "OPERATION COMPLETE" if won else "OPERATION FAILED", 1.5, acc, 0, 2)
	_t(ci, Vector2(28, 158), d.ending, 14, HH.LIGHT2, "l", 300)
	_t(ci, Vector2(28, 180), "探索用时 %s  ·  %s" % [_time(d.t), d.tier], 13, HH.MUTE, "l", 300)
	# 右上数据
	ci.draw_rect(Rect2(360, 96, 2, 50), acc)
	_t(ci, Vector2(372, 96), d.hi_label, 12, HH.MUTE)
	_t(ci, Vector2(372, 112), str(d.hi), 28, HH.LIGHT, "l", 210)
	for i in 2:
		var x := 360.0 + i * 110.0
		ci.draw_rect(Rect2(x, 160, 2, 44), HH.DARK3)
		_t(ci, Vector2(x + 12, 160), ["击败敌人", "藏品"][i], 12, HH.MUTE)
		_t(ci, Vector2(x + 12, 176), [g.run_stats.fmt_n(float(d.kills)), str(d.get("relic_n", d.relics.size()))][i], 20, HH.LIGHT)
	# 三角评级章 + 两行标签
	var tc := Vector2(74, 262)
	ci.draw_colored_polygon(PackedVector2Array([tc + Vector2(0, -44), tc + Vector2(46, 34), tc + Vector2(-46, 34)]), acc)
	ci.draw_colored_polygon(PackedVector2Array([tc + Vector2(0, -32), tc + Vector2(35, 27), tc + Vector2(-35, 27)]), HH.DARK)
	_px(ci, tc + Vector2(0, 10), str(d.grade), [5.0, 4.0, 3.0][clampi(str(d.grade).length() - 1, 0, 2)], HH.LIGHT, 1)
	_t(ci, Vector2(136, 236), "作战评级", 18, HH.LIGHT)
	_px(ci, Vector2(138, 272), "OPERATION RATING", 1.5, HH.MUTE, 0, 2)
	ci.draw_rect(Rect2(28, 318, W - 56, 1), Color(1, 1, 1, 0.25))
	# 编队卡格（3 × 2，斜排；空位 NO INFO/）
	for i in 6:
		var rc := Rect2(28 + (i % 3) * 86 - (i / 3) * 14 + 14, 338 + (i / 3) * 128, 78, 118)
		if i < d.ops.size():
			var o: Dictionary = d.ops[i]
			ci.draw_rect(rc, HH.DARK2)
			ci.draw_rect(Rect2(rc.position, Vector2(rc.size.x, 3)), acc if o.leader else o.col)
			_art(ci, o.art, Rect2(rc.position.x + 4, rc.position.y + 8, rc.size.x - 8, rc.size.y - 38), Color(0.5, 0.5, 0.55) if (o.leader and not won) else Color.WHITE)
			ci.draw_rect(Rect2(rc.position.x, rc.end.y - 28, rc.size.x, 28), Color(HH.INK, 0.86))
			for e in int(o.elite):
				var ec := Vector2(rc.position.x + 8 + e * 9, rc.end.y - 22)
				ci.draw_colored_polygon(PackedVector2Array([ec + Vector2(0, -3), ec + Vector2(3, 0), ec + Vector2(0, 3), ec + Vector2(-3, 0)]), HH.CYB)
			_t(ci, Vector2(rc.position.x + 5, rc.end.y - 17), str(o.name), 11, HH.LIGHT, "l", rc.size.x - 8)
			if o.leader:
				_t(ci, Vector2(rc.end.x - 4, rc.position.y + 6), "队长", 10, acc, "r", rc.size.x)
		else:
			ci.draw_rect(rc, Color(1, 1, 1, 0.1), false, 1.0)
			ci.draw_rect(Rect2(rc.get_center().x - 10, rc.get_center().y - 6, 20, 1), Color(1, 1, 1, 0.14))
			ci.draw_rect(Rect2(rc.get_center().x, rc.get_center().y - 12, 1, 13), Color(1, 1, 1, 0.14))
			_px(ci, Vector2(rc.position.x + 6, rc.end.y - 18), "NO", 1.5, Color(HH.MUTE, 0.6), 0, 2)
			_px(ci, Vector2(rc.position.x + 6, rc.end.y - 8), "INFO/", 1.5, Color(HH.MUTE, 0.6), 0, 2)
	# 队长立绘（右侧）+ 名牌 + 击倒章
	if not ld.is_empty():
		_art(ci, ld.art, Rect2(320, 330, 250, 236), Color.WHITE if won else Color(0.52, 0.52, 0.58))
		HH.para(ci, Rect2(316, 566, 250, 30), HH.LIGHT)
		ci.draw_rect(Rect2(316, 596, 250, 3), acc)
		_t(ci, Vector2(332, 570), str(ld.name), 18, HH.INK)
		_t(ci, Vector2(332 + font.get_string_size(str(ld.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 10, 575), "队长  Lv.%d" % int(d.get("level", 1)), 11, HH.INK2)
		if not won:
			ci.draw_set_transform_matrix(_xf * Transform2D(-0.12, Vector2(500, 380)))
			ci.draw_rect(Rect2(-52, -20, 104, 40), SB.MAG, false, 3.0)
			_t(ci, Vector2(0, -17), "击倒", 26, SB.MAG, "c", 104)
			ci.draw_set_transform_matrix(_xf)
	# 本局获得方格（左下角三角）
	_t(ci, Vector2(28, 608), "本局获得", 12, HH.MUTE)
	for i in mini(8, d.relics.size()):
		var rl: Dictionary = d.relics[i]
		var r := Rect2(96 + i * 60, 612, 52, 52)
		ci.draw_rect(r, HH.DARK2)
		ci.draw_rect(r.grow(-2), Color(1, 1, 1, 0.55), false, 1.0)
		var tx: Texture2D = g.run_stats._relic_tex(str(rl.id)) if g.run_stats.has_method("_relic_tex") else null
		if tx != null:
			ci.draw_texture_rect(tx, r.grow(-9), false)
		else:
			_t(ci, r.get_center() - Vector2(0, 12), str(rl.name).substr(0, 1), 20, HH.LIGHT, "c", r.size.x)
		var rar := str(rl.rarity)
		var cc: Color = SB.MAG if rar == "遭诅古物" else (Color8(170, 120, 255) if rar == "升华" else acc)
		ci.draw_colored_polygon(PackedVector2Array([Vector2(r.position.x, r.end.y - 14), Vector2(r.position.x + 14, r.end.y), Vector2(r.position.x, r.end.y)]), cc)
	_footer(ci, d, acc)


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
	if a.is_empty() or not (a.bounds as Rect2).has_area():
		return
	var bb: Rect2 = a.bounds
	var kk: float = maxf(0.5, floorf(minf(box.size.x / bb.size.x, box.size.y / bb.size.y) * 2.0) / 2.0)
	var sz: Vector2 = bb.size * kk
	if sz.x > box.size.x or sz.y > box.size.y:
		sz *= minf(box.size.x / sz.x, box.size.y / sz.y)
	ci.draw_texture_rect_region(a.tex, Rect2(Vector2(box.position.x + (box.size.x - sz.x) * 0.5, box.end.y - sz.y).round(), sz), bb, mod)


# ---------------------------------------------------------------- 共用部件
## 关键藏品一排：图标（没有图标画稀有度色块 + 名字首字）
func _relic_row(ci: CanvasItem, relics: Array, p: Vector2, sz: float, gap: float) -> void:
	var rc := {"升华": Color8(255, 206, 0), "稀有": Color8(120, 170, 255), "遭诅古物": Color8(200, 80, 90), "基础": Color8(150, 156, 166)}
	for i in mini(6, relics.size()):
		var rl: Dictionary = relics[i]
		var r := Rect2(p.x + i * (sz + gap), p.y, sz, sz)
		ci.draw_rect(r, HH.DARK3)
		ci.draw_rect(r, rc.get(str(rl.rarity), HH.MUTE), false, 2.0)
		var tx: Texture2D = g.run_stats._relic_tex(str(rl.id)) if g.run_stats.has_method("_relic_tex") else null
		if tx != null:
			var s: float = floorf((sz - 8) / maxf(tx.get_width(), tx.get_height()))
			s = maxf(1.0, s)
			var ts := Vector2(tx.get_width(), tx.get_height()) * s
			ci.draw_texture_rect(tx, Rect2(r.get_center() - ts / 2.0, ts), false)
		else:
			_t(ci, r.get_center() - Vector2(0, 12), str(rl.name).substr(0, 1), 20, HH.LIGHT, "c", sz)


func _avatar(ci: CanvasItem, d: Dictionary, c: Vector2, r: float, ring: Color) -> void:
	ci.draw_circle(c, r + 2, ring)
	ci.draw_texture_rect(d.avatar, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false)


## 二维码（toy.getQrCode 的 PNG）：留白边
func _qr(ci: CanvasItem, d: Dictionary, r: Rect2, bg: Color) -> void:
	ci.draw_rect(r.grow(4), bg)
	ci.draw_texture_rect(d.qr, r, false)
