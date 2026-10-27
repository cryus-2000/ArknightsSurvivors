extends RefCounted
## 战绩分享卡（10-28 协调人单：结算加「分享战绩」，竖版 3:4；10-28 用户定样式 B「深海海报」，档案卡样式已删）。
## 只读结算数据（settlement_screen.model + 编队立绘），不碰模拟与随机数。卡面在 600×800 的版面单位里画，调用方给位置与缩放。
## 深色海底底图 + 地形线，大标题结果、正中一个大高光数字，编队立绘在下方一排，底部白条放头像昵称与二维码。
## 头像 / 昵称 / 二维码由 share_toy.gd 经 Toy SDK 取（先 isSupport）；拿不到（itch / 桌面版 / 用户拒绝）时不画头像，
## 昵称写「博士」，二维码换成游戏名。隐私：头像昵称只在本地画卡，不发往任何第三方、不写日志；toyOpenId 不经过这里（docs/22 Toy 接入）。
const HH = preload("res://scripts/screens/hh_style.gd")
const UI = preload("res://scripts/ui.gd")
const D = preload("res://scripts/data.gd")

const W := 600.0
const H := 800.0
const GAME := "方舟幸存者"

var g
var font: Font
var topography: Texture2D = preload("res://art/ui/settlement/topography.png")


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
		ops.append({"key": str(r.key), "name": str(r.name), "elite": int(r.get("elite", 0)), "leader": bool(r.leader), "col": r.col, "art": screen.art.get(r.key, {})})
	var relics: Array = m.get("relic_list", []).duplicate()
	var rank := {"升华": 0, "稀有": 1, "遭诅古物": 2, "基础": 3}
	relics.sort_custom(func(a, b): return int(rank.get(str(a.rarity), 4)) < int(rank.get(str(b.rarity), 4)))
	return {"won": won, "result": "探索完成" if won else "探索终止", "result_en": "OPERATION COMPLETE" if won else "OPERATION FAILED",
		"ending": str(m.get("ending_name", "")) if won else ("击倒：" + str(m.get("killer", {}).get("name", "未知"))),
		"tier": str(D.DIFF_PRESETS[clampi(g.preset, 0, D.DIFF_PRESETS.size() - 1)].name), "t": float(m.get("t", 0.0)),
		"hi_label": "总伤害", "hi": g.run_stats.fmt_n(float(m.get("total", 0.0))), "kills": int(m.get("kills", 0)),
		"grade": screen.grade(m, g.preset), "ops": ops, "relics": relics.slice(0, 6),
		"name": "博士", "avatar": null, "qr": null}   # 头像 / 昵称 / 二维码：share_toy.gd 拿到后由结算屏填


func draw(ci: CanvasItem, d: Dictionary, pos: Vector2, k: float) -> void:
	ci.draw_set_transform(pos, 0.0, Vector2(k, k))
	_poster(ci, d)
	ci.draw_set_transform(Vector2.ZERO)


# ---------------------------------------------------------------- 深海海报
func _poster(ci: CanvasItem, d: Dictionary) -> void:
	ci.draw_rect(Rect2(0, 0, W, H), Color8(8, 16, 26))
	for i in 8:   # 由浅到深的海水分层（硬边色块，不渐变）
		ci.draw_rect(Rect2(0, H * i / 8.0, W, H / 8.0 + 1), Color8(12, 30 - i * 2, 44 - i * 3).lerp(Color8(6, 12, 20), i / 8.0))
	ci.draw_texture_rect(topography, Rect2(-80, 120, 760, 430), false, Color(0.4, 0.95, 1.0, 0.18))
	_t(ci, Vector2(28, 30), GAME, 16, HH.CYB)
	_t(ci, Vector2(W - 28, 32), "OPERATION REPORT", 12, Color(0.6, 0.85, 0.95, 0.7), "r")
	ci.draw_line(Vector2(28, 58), Vector2(W - 28, 58), Color(0.3, 0.85, 0.95, 0.5), 1.0)
	_t(ci, Vector2(W / 2.0, 82), d.result, 64, HH.LIGHT, "c", W)
	_t(ci, Vector2(W / 2.0, 158), d.result_en, 16, HH.CYB, "c", W)
	_t(ci, Vector2(W / 2.0, 186), d.ending, 15, Color(0.75, 0.85, 0.92), "c", W - 60)
	# 正中高光数字
	_t(ci, Vector2(W / 2.0, 250), d.hi_label, 15, Color(0.6, 0.8, 0.9), "c", W)
	_t(ci, Vector2(W / 2.0, 272), d.hi, 72, HH.CYB, "c", W)
	var y := 372.0
	var cols := [["潮位", d.tier], ["用时", _time(d.t)], ["评级", d.grade], ["击败", str(d.kills)]]
	for i in cols.size():
		var cx: float = 75.0 + i * 150.0
		_t(ci, Vector2(cx, y), cols[i][0], 12, Color(0.6, 0.8, 0.9), "c", 140)
		_t(ci, Vector2(cx, y + 18), str(cols[i][1]), 22, HH.LIGHT, "c", 140)
	# 编队立绘一排（站在亮线上）+ 藏品
	ci.draw_line(Vector2(28, 588), Vector2(W - 28, 588), HH.CYB, 2.0)
	_ops_row(ci, d.ops, Rect2(28, 440, W - 56, 150), false)
	_relic_row(ci, d.relics, Vector2(W / 2.0 - (mini(6, d.relics.size()) * 62.0 - 10.0) / 2.0, 606), 52.0, 10.0)
	# 底部白条
	ci.draw_rect(Rect2(0, 690, W, 110), HH.LIGHT)
	var tx := 28.0
	if d.avatar is Texture2D:
		_avatar(ci, d, Vector2(54, 745), 30.0)
		tx = 96.0
	_t(ci, Vector2(tx, 722), d.name, 20, HH.INK)
	if d.qr is Texture2D:
		_t(ci, Vector2(tx, 750), "扫码一起潜入深海", 13, HH.INK2)
		_qr(ci, d, Rect2(W - 104, 702, 86, 86), HH.LIGHT)
	else:   # 没有二维码（itch / 桌面版）：右侧写游戏名
		_t(ci, Vector2(tx, 750), "一起潜入深海", 13, HH.INK2)
		_t(ci, Vector2(W - 28, 716), GAME, 22, HH.INK, "r")
		_t(ci, Vector2(W - 28, 748), "明日方舟同人作品", 12, HH.INK2, "r")


# ---------------------------------------------------------------- 共用部件
## 干员一排：立绘按包围盒缩放、脚底对齐；精英化标记（◆ ×精英阶段），队长标「队长」
func _ops_row(ci: CanvasItem, ops: Array, r: Rect2, cards: bool) -> void:
	var n: int = mini(ops.size(), 6)
	if n == 0:
		return
	var cw: float = r.size.x / n
	for i in n:
		var o: Dictionary = ops[i]
		var x: float = r.position.x + cw * i
		if cards:
			HH.fill(ci, PackedVector2Array([Vector2(x + 10, r.position.y), Vector2(x + cw - 4, r.position.y), Vector2(x + cw - 14, r.end.y), Vector2(x, r.end.y)]), HH.LIGHT if o.leader else HH.DARK2)
			ci.draw_rect(Rect2(x + 10, r.position.y, 28, 3), o.col)
		var a: Dictionary = o.art
		if not a.is_empty() and (a.bounds as Rect2).has_area():
			var bb: Rect2 = a.bounds
			var kk: float = maxf(0.5, floorf(minf((cw - 16) / bb.size.x, (r.size.y - 40) / bb.size.y) * 2.0) / 2.0)
			var sz: Vector2 = bb.size * kk
			ci.draw_texture_rect_region(a.tex, Rect2(Vector2(x + cw / 2.0 - sz.x / 2.0, r.end.y - 28 - sz.y).round(), sz), bb)
		var nc: Color = (HH.INK if o.leader else HH.LIGHT) if cards else HH.LIGHT
		_t(ci, Vector2(x + cw / 2.0, r.end.y - 24), o.name, 13, nc, "c", cw)
		for e in int(o.elite):   # 精英化：每阶一颗青色菱形
			var c := Vector2(x + 18 + e * 12, r.position.y + 16)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -5), c + Vector2(5, 0), c + Vector2(0, 5), c + Vector2(-5, 0)]), HH.CYB)
		if o.leader:
			_t(ci, Vector2(x + cw - 12, r.position.y + 8), "队长", 11, HH.CYB if not cards else HH.RIB, "r", cw)


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


func _avatar(ci: CanvasItem, d: Dictionary, c: Vector2, r: float) -> void:
	ci.draw_circle(c, r + 2, HH.CYB)
	ci.draw_texture_rect(d.avatar, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false)


## 二维码（toy.getQrCode 的 PNG）：留白边
func _qr(ci: CanvasItem, d: Dictionary, r: Rect2, bg: Color) -> void:
	ci.draw_rect(r.grow(4), bg)
	ci.draw_texture_rect(d.qr, r, false)
