extends RefCounted
## Pure presentation: the existing panel owns settings, inputs, clipping and persistence.
const UI = preload("res://scripts/ui.gd")

static func draw(p: Control) -> void:
	var vs: Vector2 = p.size
	var paused: bool = p.game_ref != null
	p.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.015, 0.025, 0.04, 0.65 if paused else 1.0))
	var safe: Rect2 = Cfg.touch_safe_rect(vs)
	var compact: bool = vs.y < 620
	var margin := Vector2(24, 64 if compact else 94) if paused else Vector2.ZERO
	margin.y = minf(margin.y, maxf(0, (safe.size.y - 370) / 2.0))
	var r := Rect2(safe.position + margin, safe.size - margin * 2.0)
	compact = r.size.y < 540
	p.panel_rect = r
	p.draw_rect(r, Color("12171e"))
	var rail: float = clampf(r.size.x * 0.285, 180.0, 364.0)
	var top: float = r.position.y + (40 if compact else 48)
	var bottom: float = r.end.y - 56
	var white := Color("dfe3e7")
	var ink := Color("131820")
	p.draw_colored_polygon(PackedVector2Array([Vector2(r.position.x, top), Vector2(r.position.x + rail, top), Vector2(r.position.x + rail - 38, bottom), Vector2(r.position.x, bottom)]), white)
	UI.text(p, p.font, r.position + Vector2(24, 31), "设置", 18, UI.TEXT)
	UI.en(p, p.font, r.position + Vector2(124, 30), "SYSTEM / CONFIGURATION", 9, UI.SUB, 1.0)
	p.close_rect = Rect2(r.end.x - 118, r.position.y + 2, 110, 44)
	UI.text(p, p.font, p.close_rect.position + Vector2(0, 29), "返回", 16, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 110)
	UI.btn_key(p, p.font, p.close_rect, "" if Pad.using else "ESC", UI.SUB, 10, 6.0)   # 10-31 TA H7
	UI.text(p, p.font, Vector2(r.position.x + 24, top + (32 if compact else 60)), "系统设置", 30, ink)
	UI.en(p, p.font, Vector2(r.position.x + 24, top + (52 if compact else 86)), "CONFIGURATION", 11, Color("5a636e"), 1.0)
	var tabs: Array = p._tabs()
	p.tab_rects.resize(tabs.size())
	var order: Array = [1, 0, 2]
	if tabs.size() > 3:
		order.append(3)
	var rail_top: float = 64 if compact else 132
	var spacing: float = maxf(46, minf(88, (bottom - top - rail_top) / order.size()))
	for slot in order.size():
		var index: int = order[slot]
		var tr := Rect2(r.position.x + 16, top + rail_top + slot * spacing, rail - 42, maxf(44, spacing - 12))
		p.tab_rects[index] = tr
		var active: bool = index == p.tab
		if active:
			p.draw_rect(tr, ink)
			p.draw_rect(Rect2(tr.position, Vector2(4, tr.size.y)), UI.CYAN)
		UI.en(p, p.font, tr.position + Vector2(16, 25), "%02d" % (slot + 1), 10, UI.CYAN if active else Color("5a636e"))
		UI.text(p, p.font, tr.position + Vector2(52, 23 if compact else 29), tabs[index][0], 23, UI.TEXT if active else Color("5a636e"))
		UI.en(p, p.font, tr.position + Vector2(52, 38 if compact else 47), tabs[index][1], 9, UI.CYAN if active else Color("5a636e"), 1.0)
	var left: float = r.position.x + rail + 22
	UI.text(p, p.font, Vector2(left, top + (30 if compact else 56)), tabs[p.tab][0], 28, UI.TEXT)
	UI.en(p, p.font, Vector2(left, top + (50 if compact else 80)), tabs[p.tab][1] + " SETTINGS", 10, UI.SUB, 1.0)
	p.draw_line(Vector2(left, top + (62 if compact else 104)), Vector2(r.end.x - 26, top + (62 if compact else 104)), Color("3b4652"), 1)
	p.row_rects.clear()
	p._layout_list(Rect2(left, top + (72 if compact else 120), r.end.x - 26 - left, maxf(50, bottom - top - (80 if compact else 136))))
	p.draw_line(Vector2(r.position.x, bottom), Vector2(r.end.x, bottom), Color("3b4652"), 1)
	UI.text(p, p.font, Vector2(r.position.x + 24, bottom + 34), Pad.hint("Q / E 切换分类    ↑ ↓ 选择    ← → 调整    滚轮翻看", "LB / RB 切换分类    ↑ ↓ 选择    ← → 调整    Ⓑ 返回", "点分类切换 · 拖动列表"), 13, UI.SUB)

	p.footer_rect = Rect2(r.end.x - 158, bottom + 6, 146, 44)
	p.draw_rect(p.footer_rect, UI.CYAN)
	UI.text(p, p.font, p.footer_rect.position + Vector2(0, 29), "返回", 20, ink, HORIZONTAL_ALIGNMENT_CENTER, p.footer_rect.size.x)
