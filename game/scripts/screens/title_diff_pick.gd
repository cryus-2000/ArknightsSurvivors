extends "res://scripts/screens/title_op_pick.gd"
## 标题界面 · 难度页（docs/126 C2，10-22 由 title.gd 原样拆出；继承链见 title_base.gd）


func _diff_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match Pad.kc(event):
			# 潮位尺是竖的：↑ 涨潮（更高档）/ ↓ 退潮；← → 保留（旧习惯与手柄横推）
			KEY_UP, KEY_W, KEY_RIGHT, KEY_D:
				_diff_step(1)
			KEY_DOWN, KEY_S, KEY_LEFT, KEY_A:
				_diff_step(-1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_diff_go()
			KEY_ESCAPE, KEY_BACKSPACE:
				_diff_back()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = make_input_local(event).position
		for k in diff_rects:
			if diff_rects[k].has_point(p):
				match k:
					"go":
						_diff_go()
					"back":
						_diff_back()
					_:
						if str(k).begins_with("tier"):
							_diff_step(int(str(k).substr(4)) - diff_sel)
				return


func _diff_back() -> void:
	transition.switch_page(func():
		diff_pick = false
		_op_reenter())
	Sfx.play("ui_move")


func _diff_step(d: int) -> void:
	# 未解锁的档也能翻过去看效果，只是不能出发（_diff_go）
	var n := clampi(diff_sel + d, 0, D.DIFF_PRESETS.size() - 1)
	if n != diff_sel:
		_diff_level_to(n, absi(n - diff_sel))
		diff_sel = n
		Sfx.play("ui_move")


func _diff_go() -> void:
	if transition.busy:
		return
	if diff_sel > Cfg.diff_unlocked:
		Sfx.play("ui_move", -4.0, 0.6)
		return
	Cfg.difficulty = diff_sel
	Cfg.save()
	diff_pick = false
	_prewarm()
	Sfx.play("start", -8.0)   # 音量巡检（2026-09-27）：原 0 dB 比标题曲响 18 dB，且开场一开始还会再播一次
	leaving = 0.0


## 难度页（T5s，docs/67 §12）：左边竖的潮位尺就是选档器（三档卡贴在刻度上，尺内水位停在所选档；↑↓ 换档 = 水位升降，
## docs/62 §3.3「潮位上涨」out_back(1.2)，跨两档 0.6 秒），右边「档位文件」列修正项，下面 出发 / 返回。
## 选中档 = 反白 + 细青边（与标题选中块同一处理）；档名用 DIFFICULTY_TIERS 的真实名字，Ⅳ / Ⅷ 换成像素字 IV / VIII（ui.ttf 没有 Ⅷ）。
var diff_lv_from := -1.0      # 水位动画：起点 / 终点（0 = 尺底，1 = 尺顶；按档位刻度换算）、开始时刻、时长
var diff_lv_to := -1.0
var diff_lv_t0 := -10.0
var diff_lv_dur := 0.38
var diff_was := false         # 上一帧难度页是否开着（打开那一帧水位从尺底涨上来）
var diff_mod_t := -10.0       # 换档时修正项淡入（T2）
const DIFF_PAD := 0.15        # 三档刻度离尺两端的留白（占尺高）
var _mod_re: RegEx


func _diff_frac(i: int) -> float:
	return DIFF_PAD + (1.0 - DIFF_PAD * 2.0) * float(i) / float(maxi(1, D.DIFF_PRESETS.size() - 1))


func _diff_level_to(n: int, steps: int) -> void:
	diff_lv_from = _diff_level_now()
	diff_lv_to = _diff_frac(n)
	diff_lv_t0 = t
	diff_lv_dur = 0.6 if steps > 1 else 0.38
	diff_mod_t = t


func _diff_level_now() -> float:
	if diff_lv_to < 0.0:
		return _diff_frac(diff_sel)
	if Cfg.reduce_motion or diff_lv_dur <= 0.0:
		return diff_lv_to
	var x := clampf((t - diff_lv_t0) / diff_lv_dur, 0.0, 1.0)
	var e := 1.0 + 2.2 * pow(x - 1.0, 3.0) + 1.2 * pow(x - 1.0, 2.0)   # out_back(1.2)
	return lerpf(diff_lv_from, diff_lv_to, e)


func _diff_layout(vs: Vector2, ph: bool) -> Dictionary:
	var L := {}
	if not ph:
		L.gauge = Rect2(40, 112, 92, vs.y - 192)
		L.card_x = 156.0
		L.card_w = 400.0
		L.card_h = minf(88.0, (vs.y - 192) * (1.0 - DIFF_PAD * 2.0) / maxf(1.0, D.DIFF_PRESETS.size() - 1) - 3.0)
		L.panel = Rect2(612, 100, vs.x - 28 - 612, vs.y - 220)
		L.go = Rect2(612, vs.y - 100, 300, 60)
		L.back = Rect2(932, vs.y - 92, 150, 44)
	else:
		L.gauge = Rect2(20, 64, 64, vs.y - 80)
		L.card_x = 100.0
		L.card_w = 300.0
		L.card_h = minf(74.0, (vs.y - 80) * (1.0 - DIFF_PAD * 2.0) / maxf(1.0, D.DIFF_PRESETS.size() - 1) - 2.0)
		L.panel = Rect2(420, 56, vs.x - 16 - 420, vs.y - 56 - 76)
		L.go = Rect2(420, vs.y - 64, 260, 52)
		L.back = Rect2(696, vs.y - 60, 150, 44)
	var g: Rect2 = L.gauge
	L.cards = []
	for i in D.DIFF_PRESETS.size():
		var cy: float = g.end.y - g.size.y * _diff_frac(i)
		L.cards.append(Rect2(L.card_x, cy - L.card_h / 2.0, L.card_w, L.card_h))
	return L


func _draw_diff(vs: Vector2) -> void:
	if not diff_was:
		# 打开难度页：水位从尺底涨到所选档（docs/62 §3.3）
		diff_was = true
		diff_lv_from = 0.0
		diff_lv_to = _diff_frac(diff_sel)
		diff_lv_t0 = t
		diff_lv_dur = 0.6
		diff_mod_t = t
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.008, 0.024, 0.063, 0.5))
	var ph: bool = vs.y < 520.0 or Cfg.phone_ui()   # 界面高度小或手机横屏：手机接手柄时（Pad.using）也得用紧凑版式，否则按钮出界
	var touch := Pad.touch_ui()
	var c := TUI.ctx(self)
	var L := _diff_layout(vs, ph)
	var ps := TUI.cell(c, 2.0 if not ph else 1.4)
	var k1 := 1.0 if not ph else 1.4   # 小号像素字：手机按屏幕至少 2 像素一格
	var hx := 28.0 if not ph else 20.0
	# 顶栏
	TUI.ptext(self, c, Vector2(hx, 34 if not ph else 18), "OPERATION // DIFFICULTY", k1, TUI.CY)
	var hs := 26 if not ph else 22
	UI.text(self, font, Vector2(hx, (62 if not ph else 40) + hs * 0.36), "选择难度", hs, TUI.TXT)
	var hw: float = font.get_string_size("选择难度", HORIZONTAL_ALIGNMENT_LEFT, -1, hs).x
	TUI.ptext(self, c, Vector2(hx + hw + 16, (64 if not ph else 42)), "TIDE LEVEL", 2.0 if not ph else 1.4, TUI.TXT2, 2)
	diff_rects.clear()
	# 潮位尺：抖动藏青竖条 + 水 + 刻度 + 涟漪
	var gg := TUI.grid(c, L.gauge, ps)
	TUI.panel(self, gg, 3)
	var lv := _diff_level_now()
	var base := int(round(gg.ch - 1 - (gg.ch - 2) * lv))
	TUI.water_rows(self, gg, 3, base, gg.ch + 6, 0.0 if Cfg.reduce_motion else t * 1.2, "edge_rest")
	var cl: float = gg.cl
	var yy := 8
	while yy < gg.ch - 4:
		var long := yy % 16 == 0
		draw_rect(Rect2(gg.pos + Vector2(3, yy) * cl, Vector2(7 if long else 3, 1) * cl), TUI.CY_DIM)
		yy += 4
	var rip := clampf((t - diff_lv_t0 - diff_lv_dur * 0.6) / 0.6, 0.0, 1.0) if not Cfg.reduce_motion else 1.0
	TUI.ripple(self, gg, 3, gg.rect.get_center().x, base, gg.rect.size.x * 0.42, 1.0 - pow(1.0 - rip, 3.0))
	if not ph:
		TUI.ptext(self, c, Vector2(gg.rect.get_center().x, gg.rect.end.y + 16), "TIDE", k1, TUI.TXT2, 1, 1)
	# 三档卡（刻度旁）
	for i in D.DIFF_PRESETS.size():
		var tdef: Dictionary = D.DIFF_PRESETS[i]
		var on := i == diff_sel
		var locked := i > Cfg.diff_unlocked
		var r: Rect2 = L.cards[i]
		diff_rects["tier%d" % i] = r
		var g := TUI.grid(c, r, ps)
		var cy := r.get_center().y
		if on:
			TUI.halo(self, g, 3)
			# 指针：从尺的右缘指到卡片
			var px0: float = gg.rect.end.x + 2.0
			var px1: float = g.rect.position.x - 4.0
			draw_colored_polygon(PackedVector2Array([Vector2(px0, cy), Vector2(px1, cy - 8), Vector2(px1, cy + 8)]), TUI.SEL_EDGE)
		else:
			draw_rect(Rect2(gg.rect.end.x + 4.0, cy - 1.0, g.rect.position.x - gg.rect.end.x - 10.0, 2.0), TUI.CY_DIM)
		TUI.tile(self, g, 3, on)
		var ink := TUI.SEL_INK if on else TUI.TXT
		var sub := TUI.SEL_SUB if on else TUI.TXT2
		var num_c := TUI.SEL_IDX if on else ink
		if locked and not on:
			ink = TUI.TXT2
			num_c = TUI.TXT2
		var x0: float = g.rect.position.x
		var y0: float = g.rect.position.y
		if L.card_h >= 50.0:
			# 三档（D.DIFF_PRESETS，用户 10-22）：编号 + 档名 + 英文 + 说明；右上写结算系数
			var tx1 := x0 + (96.0 if not ph else 72.0)
			TUI.ptext(self, c, Vector2(x0 + (22 if not ph else 14), cy), "%d" % (i + 1), 4.0 if not ph else 3.0, num_c)
			var ns1 := 22 if not ph else 19
			UI.text(self, font, Vector2(tx1, y0 + (30 if not ph else 24) + ns1 * 0.36), str(tdef.name), ns1, ink)
			TUI.ptext(self, c, Vector2(tx1 + 2, y0 + (54 if not ph else 44)), str(tdef.en), k1, ink, 2)
			var d1: String = str(tdef.get("desc", ""))
			if locked and i > 0:
				d1 = "通关「%s」后解锁" % str(D.DIFF_PRESETS[i - 1].name)
			UI.text_fit(self, font, Vector2(tx1, y0 + (72 if not ph else 60) + 5), d1, 13, sub, g.rect.end.x - tx1 - 10, 11)
			TUI.ptext(self, c, Vector2(g.rect.end.x - 14, y0 + 16), "X%.2f" % float(tdef.get("factor", 1.0)), k1, sub, 1, 2)
			continue
		# 潮位 0–15（docs/109 §5）：一行 = 像素编号 + 级名 + 本级新规则（锁定时写解锁条件）
		var nm: String = str(tdef.get("short", tdef.name))
		var num: String = "%02d" % int(tdef.get("level", i))
		var kn := (2.0 if not ph else 1.4) if L.card_h < 50.0 else (4.0 if not ph else 3.0)
		TUI.ptext(self, c, Vector2(x0 + (14 if not ph else 10), cy), num, kn, num_c)
		var tx0 := x0 + (58.0 if not ph else 40.0)
		var ns := 15 if not ph else 13
		UI.text(self, font, Vector2(tx0, cy + ns * 0.36), nm, ns, ink)
		var nw: float = font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.fs(ns)).x
		var desc: String = str(tdef.get("desc", ""))
		if locked and i > 0:
			desc = "通关潮位 %d 后解锁" % (i - 1)
		var dx0 := tx0 + maxf(nw, 52.0) + 10.0
		UI.text_fit(self, font, Vector2(dx0, cy + 12 * 0.36), desc, 12, sub, g.rect.end.x - dx0 - 8, 9)
	# 右：档位文件（修正项）
	var pr: Rect2 = L.panel
	var pg := TUI.grid(c, pr, ps)
	TUI.panel(self, pg, 3, 0.93)
	var pp: Vector2 = pg.rect.position
	var tdef2: Dictionary = D.DIFF_PRESETS[diff_sel]
	var locked2 := diff_sel > Cfg.diff_unlocked
	var ma := clampf((t - diff_mod_t) / (0.12 if Cfg.reduce_motion else 0.22), 0.0, 1.0)
	TUI.ptext(self, c, pp + Vector2(24 if not ph else 16, 24 if not ph else 18), "TIER FILE // MODIFIERS", k1, TUI.CY)
	var lines: Array = D.dmod_lines(D.dmod_for_tier(int(D.DIFF_PRESETS[diff_sel].tide)))
	var head: String = str(tdef2.get("desc", ""))
	if locked2:
		head = "通关「%s」后解锁 · 可以先看规则" % str(D.DIFF_PRESETS[diff_sel - 1].name)
	var hs2 := 18 if not ph else 16
	UI.text_fit(self, font, pp + Vector2(24 if not ph else 16, (54 if not ph else 42) + hs2 * 0.36), head, hs2, _fa(TUI.TXT, ma), pg.rect.size.x - 48, 12)
	var gx := pp.x + (24.0 if not ph else 16.0)
	var gy := pp.y + (84.0 if not ph else 64.0)
	var gw: float = pg.rect.size.x - (48.0 if not ph else 32.0)
	var gh: float = pg.rect.end.y - (20.0 if not ph else 14.0) - gy
	if lines.is_empty():
		UI.text(self, font, Vector2(gx, gy + 24), "没有额外修正。", 15, _fa(TUI.TXT2, ma))
	else:
		if _mod_re == null:
			_mod_re = RegEx.new()
			_mod_re.compile("^(.+?)\\s+([+\\-]?\\d+%|\\d+:\\d\\d)$")
		var per := ceili(lines.size() / 2.0)
		var colw := (gw - 16.0) / 2.0
		var rh := minf(80.0, gh / per)
		var chh := rh - (12.0 if not ph else 8.0)
		for k in lines.size():
			var col := k / per
			var row := k % per
			var cr := Rect2(gx + col * (colw + 16.0), gy + row * rh, colw, chh)
			var cg := TUI.grid(c, cr, ps)
			TUI.panel(self, cg, 2, 0.85 * ma)
			var cp: Vector2 = cg.rect.position
			var ln: String = lines[k]
			var lab := ln
			var val := ""
			var m := _mod_re.search(ln)
			if m != null:
				lab = m.get_string(1)
				val = m.get_string(2)
			var tc := TUI.TXT2 if locked2 else TUI.TXT
			var big := chh >= 52.0
			if big:
				TUI.ptext(self, c, cp + Vector2(14, 16), "MOD %02d" % (k + 1), k1, _fa(TUI.CY_DIM, ma))
			var vw := 0.0
			if val != "":
				vw = TUI.ptext(self, c, Vector2(cg.rect.end.x - 14, cg.rect.get_center().y + (6 if big else 0)), val, 2.0 if not ph else 1.4, _fa(tc, ma), 1, 2)
			var ls := 15 if not ph else 14
			UI.text_fit(self, font, Vector2(cp.x + 14, cg.rect.get_center().y + (8 if big else 0) + ls * 0.36), lab, ls, _fa(tc, ma), cg.rect.size.x - 28 - vw - 10, 11)
	# 出发 / 返回
	var mp := get_local_mouse_position()
	var gog := TUI.grid(c, L.go, ps)
	diff_rects["go"] = gog.rect
	TUI.panel(self, gog, 3)
	var go_h: bool = gog.rect.has_point(mp) and not touch
	var gcy: float = gog.rect.get_center().y
	if locked2:
		TUI.outline(self, gog, 3, TUI.EDGE)
		UI.text(self, font, Vector2(gog.rect.position.x + 72, gcy + 22 * 0.36), "未解锁", 22, TUI.TXT2)
	else:
		TUI.outline(self, gog, 3, TUI.FOAM if go_h else TUI.SEL_EDGE)
		TUI.icon(self, c, "deploy", Vector2(gog.rect.position.x + 36, gcy), 2.0 if not ph else 1.5, TUI.SEL_EDGE, TUI.FOAM)
		UI.text(self, font, Vector2(gog.rect.position.x + 72, gcy + 24 * 0.36), "出发", 24, TUI.TXT)
	if not touch:
		TUI.ptext(self, c, Vector2(gog.rect.end.x - 16, gcy), Pad.hint("ENTER", "PAD A", ""), k1, TUI.TXT2, 1, 2)
	var bg := TUI.grid(c, L.back, ps)
	diff_rects["back"] = bg.rect
	TUI.panel(self, bg, 2)
	if bg.rect.has_point(mp) and not touch:
		TUI.outline(self, bg, 2, TUI.CY)
	var bcy: float = bg.rect.get_center().y
	UI.text(self, font, Vector2(bg.rect.position.x + 20, bcy + 15 * 0.36), "返回", 15, TUI.TXT)
	if not touch:
		TUI.ptext(self, c, Vector2(bg.rect.end.x - 14, bcy), Pad.hint("ESC", "PAD B", ""), k1, TUI.TXT2, 1, 2)
		TUI.ptext(self, c, Vector2(vs.x - 28, vs.y - 20), Pad.hint("↑↓ CHANGE TIDE", "D-PAD CHANGE TIDE", ""), k1, TUI.TXT2, 1, 2)
