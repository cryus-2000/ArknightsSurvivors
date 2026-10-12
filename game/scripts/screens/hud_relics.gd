extends RefCounted
## 界面 · HUD 右上（2026-10-10 从 hud.gd 拆出，docs/55 §6）：暂停键（触屏有自己的）、倍速键、藏品栏（缓存层）与悬停说明、当前结局走向。
const Bal = preload("res://scripts/core/balance.gd")
const PlayClock = preload("res://scripts/run/play_clock.gd")
const UI = preload("res://scripts/ui.gd")
const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
const Tris = preload("res://scripts/screens/hud_tris.gd")
var g: Game
var h   # screens/hud.gd：合批段（batch_begin / _hb）、共用助手（edge_glow / corrode_seg / draw_tooltip）与兄弟模块都从这里取


func _init(hud) -> void:
	h = hud
	g = hud.g


## 右上：暂停按钮 + 倍速 + 藏品栏（藏品 / 等级 / 悬停格变了才重画）+ 结局走向（原 _draw_body「右上」段）。
## 注意：暂停按钮画在 hud_bars.draw_top_center 开的合批段里（h._hb），本函数负责 h.batch_end；两块在 hud._draw_body 里必须相邻
func draw_right_top(vs: Vector2) -> void:
	# 右上：暂停按钮（鼠标可点；触屏有自己的按钮）+ 收藏品栏 + 当前结局走向
	var tray_x := vs.x - 80.0
	g.pause_btn = Rect2()
	if not g.touch.active:
		var pr := Rect2(vs.x - 56, 12, 40, 40)
		var ph: bool = g.state == Game.S.PLAY and pr.has_point(g.hud.get_local_mouse_position())
		h._hb.rect(pr, Color(0.03, 0.035, 0.045, 0.78))
		h._hb.frame(pr, UI.CYAN if g.state == Game.S.PAUSE else Color(1, 1, 1, 0.55 if ph else 0.22), 1.0)
		UI.icon(g.hud, "pause", pr.get_center(), 20.0, UI.TEXT)
		UI.ctext(g.hud, g.font, pr.position + Vector2(0, 52), "ESC", 9, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 40)
		if g.state == Game.S.PLAY:
			g.pause_btn = pr
	h.batch_end()
	draw_speed_button(vs)
	# 藏品栏：藏品 / 等级 / 悬停格变了才重画
	var trp := Vector2(tray_x, 12)
	var hov := -1
	var mouse := g.hud.get_local_mouse_position()
	for ci in g.tray_cells.size():
		if (g.tray_cells[ci][0] as Rect2).has_point(mouse):
			hov = ci
	var lvs: Array = g.relics.map(func(r): return g.rfx.lv.get(r, 1))
	h._layer("relics", [g.relics.duplicate(), lvs, hov, trp], func(): draw_relic_tray(trp))
	if not g.trial.active and (g.ending != "standard" or Cfg.endings_cleared.size() > 0):
		UI.text(g.hud, g.font, Vector2(tray_x - 220, 12.0 + tray_layout(g.relics.size()).h + 18.0), g.endg.cur_name(), 12, g.endg.cur_col(), HORIZONTAL_ALIGNMENT_RIGHT, 220, 2)


func draw_speed_button(vs: Vector2) -> void:
	var rect := Rect2(vs.x - 72.0, 76.0, 56.0, 34.0)
	var enabled: bool = g.state == Game.S.PLAY
	var hovered: bool = enabled and rect.has_point(g.hud.get_local_mouse_position())
	UI.button(g.hud, g.font, rect, PlayClock.current_label(), "outline" if enabled else "off", hovered, 16)
	UI.text(g.hud, g.font, rect.position + Vector2(0, 48), "倍速" if g.touch.active else "倍速 V", 13 if g.touch.active else 10, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)
	if enabled:
		g.speed_btn = g.touch._hit(rect) if g.touch.active else rect   # 触屏：点击区 84 见方


## 藏品栏排布（藏品不设上限后，10-12）：≤ 16 件 38 像素格、一行 8 个；更多时紧凑格 22 像素、一行 14 个，最多 3 行（42 格）。
## 超过 42 件：只画最近获得的 41 件，第一格写「+N」（较早的 N 件，悬停提示去 Tab 面板看全部）。高度封顶 96 + 30，60 件也不再往下长。
const TRAY_MAX_ROWS := 3


func tray_layout(n: int) -> Dictionary:
	var compact: bool = n > 16
	var per_row := 14 if compact else 8
	var cell := 22.0 if compact else 38.0
	var cap_cells: int = per_row * TRAY_MAX_ROWS
	var more: int = 0 if n <= cap_cells else n - (cap_cells - 1)
	var shown: int = mini(n, cap_cells)
	var rows: int = maxi(1, int(ceil(shown / float(per_row))))
	var w: float = maxf(mini(shown, per_row) * cell + 12.0, 132.0)
	return {"compact": compact, "per_row": per_row, "cell": cell, "icon": 16.0 if compact else 32.0, "rows": rows,
		"w": w, "h": rows * cell + 30.0, "more": more, "first": n - shown + (1 if more > 0 else 0)}


func draw_relic_tray(tr: Vector2) -> void:
	var n := g.relics.size()
	var L: Dictionary = tray_layout(n)
	var compact: bool = L.compact
	var per_row: int = L.per_row
	var cell: float = L.cell
	var icon_sz: float = L.icon
	var w: float = L.w
	var o := tr + Vector2(-w, 0)
	var r := Rect2(o, Vector2(w, L.h))
	# 原作底栏「收藏品 N」：暗底 + 图标 + 数量，下面一排藏品格（左上角一小段分类色）
	g.hud.draw_rect(r, Color(0.03, 0.035, 0.045, 0.74))
	g.hud.draw_rect(Rect2(o, Vector2(w, 1)), Color(1, 1, 1, 0.14))
	UI.icon(g.hud, "box", o + Vector2(15, 14), 14.0, Color(0.81, 0.84, 0.86))
	UI.text(g.hud, g.font, o + Vector2(28, 19), "藏品", 12, Color(0.81, 0.84, 0.86))
	if w >= 220.0:
		UI.en(g.hud, g.font, o + Vector2(70, 18), "RELICS", 9, UI.SUB, 2.0)
	var cap: int = g.progression.relic_cap()
	UI.ctext(g.hud, g.font, o + Vector2(w - 70, 20), str(n) if cap < 0 else "%d / %d" % [n, cap], 15, UI.GOLD if cap >= 0 and n >= cap else UI.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, 60)
	g.tray_cells.clear()
	var mouse := g.hud.get_local_mouse_position()
	# 格底 / 边框 / 分类色攒成一批画在图标下，等级点一批画在图标上（原来每格 4–6 次绘制调用）
	var under := Tris.new()
	var over := Tris.new()
	var late: Array[Callable] = []
	var slot := 0
	if L.more > 0:
		# 第一格：较早获得、没画出来的件数
		var c0 := o + Vector2(6 + cell / 2, 26 + cell / 2)
		var r0 := Rect2(c0 - Vector2(cell / 2.0 - 2.0, cell / 2.0 - 2.0), Vector2(cell - 4.0, cell - 4.0))
		g.tray_cells.append([r0, ""])
		var hov0: bool = r0.has_point(mouse)
		under.rect(r0, Color(1, 1, 1, 0.10) if not hov0 else Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.22))
		under.frame(r0, Color(1, 1, 1, 0.22) if not hov0 else UI.CYAN, 1.0)
		var mt: String = "+%d" % L.more
		late.append(func(): UI.text(g.hud, g.font, c0 + Vector2(-cell / 2.0, 4), mt, 9, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, cell))
		slot = 1
	for i in range(L.first, n):
		var rd: Dictionary = g.RL[g.relics[i]]
		var col: Color = UI.CAT_COL.get(rd.cat, UI.GOLD)
		var c := o + Vector2(6 + (slot % per_row) * cell + cell / 2, 26 + (slot / per_row) * cell + cell / 2)
		slot += 1
		var cellr := Rect2(c - Vector2(cell / 2.0 - 2.0, cell / 2.0 - 2.0), Vector2(cell - 4.0, cell - 4.0))
		g.tray_cells.append([cellr, g.relics[i]])
		var hov: bool = cellr.has_point(mouse)
		under.rect(cellr, Color(1, 1, 1, 0.05) if not hov else Color(col.r, col.g, col.b, 0.22))
		under.frame(cellr, Color(1, 1, 1, 0.13) if not hov else col, 1.0)
		under.rect(Rect2(cellr.position, Vector2(8 if not compact else 5, 2)), Color(col.r, col.g, col.b, 0.85))
		var ic: Texture2D = g.tex.get("relic_" + g.relics[i])
		if ic != null:
			late.append(func(): g.hud.draw_texture_rect(ic, Rect2(c - Vector2(icon_sz, icon_sz) / 2.0, Vector2(icon_sz, icon_sz)), false))
		else:
			under.diamond(c, icon_sz * 0.34, Color(0.03, 0.08, 0.1), col)
			var ch: String = rd.name.substr(0, 1)
			late.append(func(): UI.text(g.hud, g.font, c + Vector2(-15, 5), ch, 12 if not compact else 9, col, HORIZONTAL_ALIGNMENT_CENTER, 30))
		var rl: int = g.rfx.lv.get(g.relics[i], 1)
		if rl > 1:
			var pip: float = 6.0 if not compact else 3.0
			for q in rl:
				over.rect(Rect2(c + Vector2(-icon_sz / 2.0 + q * pip, icon_sz / 2.0 - 4.0), Vector2(pip - 2.0, 2 if compact else 3)), Color(col.r * 1.5, col.g * 1.5, col.b * 1.5))
	under.flush(g.hud)
	for f in late:
		f.call()
	over.flush(g.hud)


## 藏品栏悬停提示（游戏中 / 暂停）
func draw_relic_tooltip(vs: Vector2) -> void:
	if g.state != Game.S.PLAY and g.state != Game.S.PAUSE:
		return
	var mouse := g.hud.get_local_mouse_position()
	for cellinfo in g.tray_cells:
		var cr: Rect2 = cellinfo[0]
		if not cr.has_point(mouse):
			continue
		var id: String = cellinfo[1]
		if id == "":
			var more: int = tray_layout(g.relics.size()).more
			h.draw_tooltip(vs, cr, "另有 %d 件藏品" % more, "较早获得", "藏品栏只显示最近获得的 %d 件。%s" % [g.relics.size() - more, Pad.hint("按 Tab 查看全部。", "按 SELECT 查看全部。", "点「属性」查看全部。")], "", UI.CYAN)
			return
		var rd: Dictionary = g.RL[id]
		var mx: int = g.rfx.max_lv(id)
		h.draw_tooltip(vs, cr, rd.name + ((" Lv.%d/%d" % [g.rfx.lv.get(id, 1), mx]) if mx > 1 else ""), "%s · %s" % [rd.cat, rd.rarity], rd.desc, "relic_" + id, UI.CAT_COL.get(rd.cat, UI.GOLD))
		return
