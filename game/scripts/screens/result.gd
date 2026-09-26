extends RefCounted
## 界面 · 结算（state DEAD / WIN）：存活时间、击杀、结局、伤害与编队总结。
## 界面层约定（docs/39 §3）。2026-09-26 从 game.gd 拆出。

const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game


func _init(game: Game) -> void:
	g = game


func draw(vs: Vector2, title: String, en_title: String, col: Color, opts: Array, ending_panel := false) -> void:
	g.hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.02, 0.04, 0.72))
	var pw := 600.0 if opts.size() <= 3 else 700.0   # 暂停菜单五个按钮：加宽，按键牌才放得下
	var r := Rect2(vs.x / 2 - pw / 2.0, vs.y / 2 - 190, pw, 380)
	if ending_panel:
		# 结局结算：面板右侧浮现最终 Boss 剪影 + 结局色光晕 + 一句尾声
		var en: Dictionary = D.ENDINGS.get(g.ending, {})
		var bd: Dictionary = D.ENEMIES.get(en.get("boss", ""), {})
		var btx: Texture2D = g.tex.get(bd.get("tex", ""))
		var gc: Vector2 = Vector2(r.end.x + 120, r.get_center().y - 20)
		for k in 4:
			g.hud.draw_circle(gc, 150.0 - k * 28.0 + 6.0 * sin(g.t * 1.3 + k), Color(col.r, col.g, col.b, 0.05 + 0.03 * k))
		if btx != null:
			var fw: int = btx.get_width() / 2
			var fh: int = btx.get_height()
			var k2: float = minf(220.0 / fw, 240.0 / fh)
			k2 = floorf(k2) if k2 >= 1.0 else k2
			var sz := Vector2(fw, fh) * k2
			var fr: int = int(g.t * 2.0) % 2
			var bob: float = 4.0 * sin(g.t * 1.6)
			g.hud.draw_texture_rect_region(btx, Rect2((gc - sz / 2.0 + Vector2(0, bob)).round(), sz), Rect2(fw * fr, 0, fw, fh), Color(0.55, 0.6, 0.7, 0.9))
			g.hud.draw_texture_rect_region(btx, Rect2((gc - sz / 2.0 + Vector2(0, bob)).round(), sz), Rect2(fw * fr, 0, fw, fh), Color(col.r, col.g, col.b, 0.25 + 0.1 * sin(g.t * 2.0)))
		var idx: int = ["standard", "knight", "resolve", "deep"].find(g.ending)
		UI.text(g.hud, g.font, Vector2(gc.x - 90, gc.y + 150), "结局 %s" % ["Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ"][maxi(idx, 0)], 14, Color(col.r, col.g, col.b, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 180)
		UI.text(g.hud, g.font, Vector2(gc.x - 110, gc.y + 172), "已达成 %d / 4" % Cfg.endings_cleared.size(), 12, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 220)
	UI.frame(g.hud, r, col, {"t": g.t})
	g.hud.draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), Color(col.r, col.g, col.b, 0.85))
	UI.caustic(g.hud, Rect2(r.position + Vector2(24, 10), Vector2(r.size.x - 48, 24)), g.t, col)
	var ew := g.font.get_string_size(en_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + en_title.length() * 4.0
	UI.en(g.hud, g.font, Vector2(r.get_center().x - ew / 2.0, r.position.y + 50), en_title, 13, col, 4.0)
	UI.heading(g.hud, g.font, Vector2(r.get_center().x, r.position.y + 90), title, 36, col, 250.0)
	var mm := int(g.t) / 60
	var ss := int(g.t) % 60
	var stats := [["探索时间", "%02d:%02d" % [mm, ss]], ["等级", "Lv.%d  %s" % [g.level, ["精零", "精英化一", "精英化二"][g.ch.elite]]],
		["击杀", str(g.kills)], ["难度", D.DIFFICULTY_TIERS[g.tier].name]]
	if ending_panel:
		var ep: String = D.ENDINGS.get(g.ending, {}).get("gallery", {}).get("epilogue", "")
		UI.text(g.hud, g.font, Vector2(r.position.x + 40, r.position.y + 124), ep, 14, Color(col.r * 0.9 + 0.1, col.g * 0.9 + 0.1, col.b * 0.9 + 0.1, 0.9), HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 80)
		if g.ending_new:
			UI.chip(g.hud, g.font, Vector2(r.position.x + 30, r.position.y + 30), "新结局达成", col, 12)
	if g.diff_new and g.state == Game.S.WIN:
		UI.chip(g.hud, g.font, Vector2(r.get_center().x - 80, r.position.y + (142 if ending_panel else 118)), "解锁难度「%s」" % D.DIFFICULTY_TIERS[g.tier + 1].name, UI.GOLD, 13)
	for i in stats.size():
		var y := r.position.y + (166 if ending_panel else 156) + i * 32
		UI.diamond(g.hud, Vector2(r.position.x + 48, y - 6), 3.5, Color(col.r, col.g, col.b, 0.8))
		UI.text(g.hud, g.font, Vector2(r.position.x + 62, y), stats[i][0], 16, UI.SUB)
		UI.text(g.hud, g.font, Vector2(r.position.x + 200, y), stats[i][1], 18, UI.TEXT)
	var bx := r.position.x + 40
	var bw := (r.size.x - 80 - 12 * (opts.size() - 1)) / opts.size()
	g.result_btns.clear()
	var mouse := g.hud.get_local_mouse_position()
	for op in opts:
		var br := Rect2(bx, r.end.y - 70, bw, 40)
		var bi: int = g.result_btns.size()
		g.result_btns.append([br, op[2]])
		var hov: bool = (bi == g.res_sel) if (Pad.using or g.kb_nav) else br.has_point(mouse)
		g.hud.draw_rect(br, UI.CYAN if hov else Color(UI.STEEL.r, UI.STEEL.g, UI.STEEL.b, 0.4))
		var bink := Color(0.04, 0.07, 0.09) if hov else UI.TEXT
		UI.text(g.hud, g.font, br.position + Vector2(14, 26), op[0], 15, bink)
		var kst: String = ("Ⓐ" if hov else "") if Pad.using else op[1]
		if kst != "":
			UI.keycap(g.hud, g.font, Vector2(br.end.x - UI.cwidth(g.font, kst, 10) - 20, br.position.y + 11), kst, bink, 10)
		bx += bw + 12


## Tab 面板攻击栏下半：开局干员的三个技能 + 天赋。说明按栏宽折行；先每条给 1 行，再轮流给还没排完的加行，
## 直到把剩余高度用完。排不完的末行加「…」，鼠标移到这一行上看完整说明（stats_cells 的 skill 项）
func draw_generic_skill_rows(b1: Rect2, y: float, rows: Array) -> float:
	var c: Color = g.ch.col()
	var x0 := b1.position.x + 62.0
	var dw := b1.end.x - 14.0 - x0
	var dfs := 11
	var lh: float = g.font.get_height(dfs) + 1.0
	var avail: float = b1.end.y - 6.0 - y
	var rh := func(n: int) -> float: return maxf(42.0, 30.0 + n * lh)
	var wrapped: Array = []
	var give: Array = []
	var used := 0.0
	for row in rows:
		var wl: PackedStringArray = UI.wrap_lines(g.font, row[2], dfs, dw)
		wrapped.append(wl)
		give.append(mini(1, wl.size()))
		used += rh.call(give[give.size() - 1])
	var grew := true
	while grew:
		grew = false
		for k in rows.size():
			if give[k] < wrapped[k].size():
				var add: float = rh.call(give[k] + 1) - rh.call(give[k])
				if used + add <= avail:
					give[k] += 1
					used += add
					grew = true
	for k in rows.size():
		var row: Array = rows[k]
		var on: bool = row[3]
		var col: Color = (Color(0.85, 0.55, 1.0) if row[4] else c) if on else Color(0.35, 0.42, 0.46)
		var sc := Vector2(b1.position.x + 34, y + 20)
		var itx: Texture2D = g.tex.get(row[5]) if row.size() > 5 and row[5] != "" else null
		if itx != null:
			# 技能图标（32px 原尺寸），未解锁压暗；左下角小牌标技能序号
			g.hud.draw_texture_rect(itx, Rect2(sc - Vector2(16, 16), Vector2(32, 32)), false, Color.WHITE if on else Color(0.34, 0.37, 0.41))
			g.hud.draw_rect(Rect2(sc + Vector2(-17, 5), Vector2(11, 12)), Color(0.03, 0.035, 0.045, 0.92))
			UI.ctext(g.hud, g.font, sc + Vector2(-16, 15), row[0], 10, col, HORIZONTAL_ALIGNMENT_CENTER, 9)
		else:
			UI.ring(g.hud, sc, 17.0, 1.0 if on else 0.0, col, false, not on)
			UI.text(g.hud, g.font, sc + Vector2(-12, 7), row[0], 15, col, HORIZONTAL_ALIGNMENT_CENTER, 24)
		UI.text_fit(g.hud, g.font, Vector2(x0, y + 16), row[1] + ("  ·排异" if row[4] else ""), 14, UI.TEXT if on else UI.SUB, dw, 11)
		var lines: PackedStringArray = wrapped[k]
		var dcol: Color = col if on else Color(0.42, 0.48, 0.52)
		for j in give[k]:
			var ln: String = lines[j]
			if j == give[k] - 1 and give[k] < lines.size():
				while ln.length() > 0 and g.font.get_string_size(ln + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, dfs).x > dw:
					ln = ln.substr(0, ln.length() - 1)
				ln += "…"
			UI.text(g.hud, g.font, Vector2(x0, y + 33 + j * lh), ln, dfs, dcol)
		var row_h: float = rh.call(give[k])
		g.stats_cells.append([Rect2(Vector2(b1.position.x + 14, y), Vector2(b1.size.x - 28, row_h)), "skill", row])
		y += row_h
	return y
