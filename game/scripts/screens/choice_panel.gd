extends RefCounted
## 界面 · 弹窗面板与选卡（state CHOICE）：弹窗框架（面板节点、布局、背景、标题、按钮）、升级 / 藏品 / 招募 / 事件的卡片绘制与入场动画、
## 事件插画与底栏。商店界面（screens/shop_screen.gd）也用这里的面板框架与按钮。界面层约定（docs/37）。2026-09-26 从 game.gd 拆出。

const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
const A = preload("res://scripts/art.gd")
const Character = preload("res://scripts/characters/character.gd")
const Affects = preload("res://scripts/run/affects.gd")

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game
var panel_band: ColorRect      # 选卡 / 商人 / 事件背后的灰阶压暗带（ui_band.gdshader）
var panel_sub_text := ""       # 面板标题下的一行说明（事件：剧情一句）
var ev_bars_h := 0.0           # 事件选项条的总高度（选项条按说明行数加高，提示文字跟在后面）
var serif: Font                # 事件标题用的衬线粗体（fonts/serif.ttf，缺失时退回 UI 字体）
## 事件（C 版式，原作「不期而遇」）：左边撕纸边灰阶墨色插画——画面里唯一的彩色物件是海嗣祭坛；
## 下方事件名（衬线粗体）+ 剧情一句；右边竖排选项条在 panel_col。插画的随机形状按事件名缓存
var ev_art := {}
var ink_tex: GradientTexture2D
## 选卡卡片（A3，仿原作「选择支援」）：炭灰卡 + 左上节点标签条（英文分类 + 中文）+ 右上序号 + 图标光环 + 名称 + 说明 +
## 作用对象标签（影响当前编队里的哪些干员，run/affects.gd）+ 底部操作条。悬停 / 焦点：青色细边与外晕，标签条与操作条变青
const CARD_W := 272.0
const CARD_H := 382.0
const CARDS_TOP := 190.0       # 卡片顶边；标题从它上方 92 处开始，底边（572）不压到底栏的技能图标


func _init(game: Game) -> void:
	g = game


## 卡片是否"被选中"：用手柄 / 方向键时看焦点，否则看鼠标悬停
func card_hot(card: Button, i: int) -> bool:
	if Pad.using or g.kb_nav:
		return i == g.nav_sel
	return card.is_hovered()


## 面板底部的按钮（商店：刷新 / 离开）：A 风格暗底细边；可带线性图标、源石锭价格、备注、按键牌。鼠标与触屏都能点
func button(text: String, r: Rect2, cb: Callable, enabled: bool, icon := "", note := "", price := -1, key := "") -> void:
	var b := Button.new()
	b.set_meta("shopbtn", true)
	b.position = r.position
	b.size = r.size
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not enabled
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(st, empty)
	b.draw.connect(func():
		var hov: bool = b.is_hovered() and enabled
		var br := Rect2(Vector2.ZERO, b.size)
		var fg: Color = UI.TEXT if enabled else UI.SUB
		b.draw_rect(br, Color(0.03, 0.035, 0.045, 0.82))
		b.draw_rect(br, Color(1, 1, 1, 0.6 if hov else (0.3 if enabled else 0.12)), false, 1.0)
		if hov:
			b.draw_rect(br.grow(2.0), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.35), false, 1.0)
		var x := 16.0
		if icon != "":
			UI.icon(b, icon, Vector2(x + 9, b.size.y / 2.0), 18.0, fg)
			x += 26.0
		UI.text(b, g.font, Vector2(x, b.size.y / 2.0 + 5), text, 14, fg)
		x += g.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 10.0
		if price >= 0:
			b.draw_texture_rect(g.tex.ingot, Rect2(Vector2(x, b.size.y / 2.0 - 7), Vector2(18, 14)), false, Color(1, 1, 1, 1.0 if enabled else 0.5))
			UI.ctext(b, g.font, Vector2(x + 22, b.size.y / 2.0 + 7), str(price), 18, fg)
			x += 22.0 + UI.cwidth(g.font, str(price), 18) + 8.0
		if note != "":
			UI.text(b, g.font, Vector2(x, b.size.y / 2.0 + 5), note, 11, UI.SUB)
		if key != "":
			UI.keycap(b, g.font, Vector2(b.size.x - UI.cwidth(g.font, key, 11) - 28, b.size.y / 2.0 - 9), key, fg, 11))
	b.mouse_entered.connect(b.queue_redraw)
	b.mouse_exited.connect(b.queue_redraw)
	b.pressed.connect(cb)
	g.panel.add_child(b)


func build(parent: Node) -> void:
	var theme := Theme.new()
	theme.default_font = g.font
	theme.default_font_size = 18
	g.panel = Control.new()
	g.panel.theme = theme
	g.panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	g.panel.visible = false
	parent.add_child(g.panel)
	# 灰阶压暗带（方案 A，仿原作局内弹窗）：读屏幕纹理，把背后的战场变灰变暗；位置按界面类型在 _layout_panel 里设
	panel_band = ColorRect.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/ui_band.gdshader")
	panel_band.material = sm
	panel_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.panel.add_child(panel_band)
	# 标题 / 商人立绘 / 事件插画画在这一层：在压暗带之上、卡片之下
	g.panel_fg = Control.new()
	g.panel_fg.set_anchors_preset(Control.PRESET_FULL_RECT)
	g.panel_fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.panel_fg.draw.connect(draw_bg)
	g.panel.add_child(g.panel_fg)
	g.panel_box = HBoxContainer.new()
	g.panel_box.add_theme_constant_override("separation", 36)
	g.panel_box.alignment = BoxContainer.ALIGNMENT_CENTER
	g.panel_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	g.panel_box.offset_top = 184
	g.panel_box.offset_bottom = -100
	g.panel.add_child(g.panel_box)
	# 事件选项（C 版式）：右半屏竖排的选项条
	g.panel_col = VBoxContainer.new()
	g.panel_col.add_theme_constant_override("separation", 14)
	g.panel_col.anchor_left = 0.5
	g.panel_col.anchor_right = 0.5
	g.panel_col.offset_left = 12
	g.panel_col.offset_right = 608
	g.panel_col.offset_top = 196
	g.panel_col.offset_bottom = 560
	g.panel_col.visible = false
	g.panel.add_child(g.panel_col)
	# 最上层：说明被截断（排不下末行带「…」）的卡片，悬停 / 焦点时在这里画完整说明
	g.panel_tip = Control.new()
	g.panel_tip.set_anchors_preset(Control.PRESET_FULL_RECT)
	g.panel_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.panel_tip.z_index = 10
	g.panel_tip.draw.connect(draw_panel_tip)
	g.panel.add_child(g.panel_tip)
	# 事件标题的衬线字；没导入（别的工作区的 .godot 缓存里还没有）就用 UI 字体
	var sf: Font = load("res://fonts/serif.ttf") if ResourceLoader.exists("res://fonts/serif.ttf") else null
	if sf != null:
		sf.fallbacks = [g.font]
		serif = sf
	else:
		serif = g.font


## 压暗带与卡片容器的布局：选卡在顶栏与底栏之间；商人压暗到底部；事件整屏灰阶（C 版式）
func layout(kind: String) -> void:
	var vs: Vector2 = g.get_viewport_rect().size
	var sm: ShaderMaterial = panel_band.material
	var top := 64.0
	var bot := vs.y - 108.0
	var fade := 34.0
	var desat := 0.85
	var dim := 0.5
	if kind == "shop":
		bot = vs.y - 56.0
	elif kind == "event":
		top = 0.0
		bot = vs.y
		fade = 0.0
		desat = 1.0
		dim = 0.46
	panel_band.position = Vector2(0, top)
	panel_band.size = Vector2(vs.x, bot - top)
	sm.set_shader_parameter("rect_size", panel_band.size)
	sm.set_shader_parameter("fade_px", fade)
	sm.set_shader_parameter("desat", desat)
	sm.set_shader_parameter("dim", dim)
	if kind == "shop":
		g.panel_box.anchor_left = 0.5
		g.panel_box.anchor_right = 0.5
		g.panel_box.offset_left = -280.0
		g.panel_box.offset_right = 588.0
		g.panel_box.offset_top = 222.0
	else:
		g.panel_box.anchor_left = 0.0
		g.panel_box.anchor_right = 1.0
		g.panel_box.offset_left = 0.0
		g.panel_box.offset_right = 0.0
		g.panel_box.offset_top = CARDS_TOP
	g.panel_box.visible = kind != "event"
	g.panel_col.visible = kind == "event"


func draw_bg() -> void:
	var vs := g.panel_fg.size
	match g.choice_kind:
		"shop":
			g.shop_ui.draw_bg(vs)
		"event":
			draw_event_bg(vs)
		_:
			var en_label := "RELIC" if g.choice_kind == "relic" else "LEVEL UP"
			if g.choices.size() > 0 and g.choices[0].kind == "recruit":
				en_label = "RECRUIT"
			header(vs, en_label + "  ·  CHOOSE ONE", g.panel_title_text, panel_sub_text, CARDS_TOP - 92.0)
			var hint := "←→ 选择 · Ⓐ 确认" if Pad.using else "点击卡片，或按 1–%d 选择" % g.choices.size()
			UI.text(g.panel_fg, g.font, Vector2(0, CARDS_TOP + CARD_H + 26), hint, 12, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, vs.x)


## 面板标题（原作「选择支援」）：英文小标签 + 大标题（两侧渐隐细线 + 靠近文字的短粗线）+ 一行说明
func header(vs: Vector2, micro: String, title: String, sub: String, y0 := 104.0) -> void:
	var c := vs.x / 2.0
	var mw := UI.en_width(g.font, micro, 12, 4.0)
	UI.en(g.panel_fg, g.font, Vector2(c - mw / 2.0, y0 + 12), micro, 12, UI.SUB, 4.0)
	UI.heading(g.panel_fg, g.font, Vector2(c, y0 + 36), title, 30, UI.TEXT, 290.0)
	if sub != "":
		UI.text(g.panel_fg, g.font, Vector2(0, y0 + 70), sub, 13, Color(0.67, 0.7, 0.74), HORIZONTAL_ALIGNMENT_CENTER, vs.x)


func event_art(key: String) -> Dictionary:
	if ev_art.get("key", "") == key:
		return ev_art
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var a := {"key": key, "blobs": [], "streaks": [], "dots": [], "bars": [], "ensos": []}
	a.panel = UI.jag_rect(Rect2(0, 0, 560, 500), 8.0, 12.0, rng)
	for k in 9:
		var y: float = rng.randf_range(-30.0, 60.0) if rng.randf() < 0.5 else rng.randf_range(430.0, 530.0)
		a.blobs.append(UI.blob(Vector2(rng.randf_range(-20.0, 580.0), y), rng.randf_range(40.0, 110.0), rng))
	for k in 5:
		var bp := UI.brush_poly(Vector2(rng.randf_range(-80.0, 200.0), rng.randf_range(60.0, 380.0)), rng.randf_range(260.0, 460.0), rng.randf_range(6.0, 16.0), rng)
		var rot := Transform2D(deg_to_rad(rng.randf_range(-30.0, -18.0)), Vector2.ZERO)
		var out := PackedVector2Array()
		for q in bp:
			out.append(Vector2(280, 250) + rot * (q - Vector2(280, 250)))
		a.streaks.append(out)
	for k in 18:
		a.dots.append([Vector2(rng.randf_range(20.0, 540.0), rng.randf_range(20.0, 480.0)), rng.randf_range(0.8, 3.2)])
	for k in 4:
		var bar := UI.jag_rect(Rect2(0, 0, 596, 100), 1.5, 9.0, rng, "tbl")
		for j in bar.size():
			if bar[j].x < 20.0:
				bar[j].x += rng.randf_range(-4.0, 10.0)
		a.bars.append(bar)
		a.ensos.append(UI.enso(Vector2(56, 50), 36.0, 3.0, rng))
	a.emblem = UI.curly_lines(Vector2.ZERO, 24.0 * 0.38, 24.0, 16, 24.0 * 0.14, rng)
	a.emblem_small = UI.curly_lines(Vector2.ZERO, 9.0 * 0.38, 9.0, 12, 9.0 * 0.16, rng)
	ev_art = a
	return a


func ink_grad() -> GradientTexture2D:
	if ink_tex == null:
		var gr := Gradient.new()
		gr.offsets = PackedFloat32Array([0.0, 0.3, 0.6, 0.88, 1.0])
		gr.colors = PackedColorArray([Color("dcd7ce"), Color("aca79e"), Color("5f5c57"), Color("1c1c1d"), Color("1c1c1d")])
		ink_tex = GradientTexture2D.new()
		ink_tex.gradient = gr
		ink_tex.fill = GradientTexture2D.FILL_RADIAL
		ink_tex.fill_from = Vector2(0.5, 0.42)
		ink_tex.fill_to = Vector2(1.08, 0.42)
		ink_tex.width = 256
		ink_tex.height = 256
	return ink_tex


func draw_event_bg(vs: Vector2) -> void:
	var art := event_art(g.panel_title_text)
	var cx := vs.x / 2.0
	var p0 := Vector2(cx - 576.0, 120.0)
	var pts: PackedVector2Array = art.panel
	var tp := PackedVector2Array()
	var uv := PackedVector2Array()
	for q in pts:
		tp.append(p0 + q)
		uv.append(Vector2(clampf(q.x / 560.0, 0.0, 1.0), clampf(q.y / 500.0, 0.0, 1.0)))
	g.panel_fg.draw_colored_polygon(tp, Color.WHITE, uv, ink_grad())
	for b in art.blobs:
		g.panel_fg.draw_colored_polygon(offset_poly(b, p0, tp), Color(0.047, 0.047, 0.05, 0.5))
	for s in art.streaks:
		g.panel_fg.draw_colored_polygon(offset_poly(s, p0, tp), Color(0.08, 0.08, 0.085, 0.35))
	for d in art.dots:
		g.panel_fg.draw_circle(p0 + d[0], d[1], Color(0.047, 0.047, 0.05, 0.55))
	# 蓝色微光 + 海嗣祭坛（彩色）
	var ac := p0 + Vector2(280, 158)
	for k in 5:
		g.panel_fg.draw_circle(ac, 120.0 - k * 20.0, Color(0.18, 0.72, 1.0, 0.05))
	var etx: Texture2D = g.tex.get("e_event")
	if etx != null:
		var fw := etx.get_width() / 2
		var fh := etx.get_height()
		var ks: float = 8.0 / A.hires_of(etx)
		var sz := Vector2(fw, fh) * ks
		var fr := int(g.t * 2.0) % 2
		g.panel_fg.draw_texture_rect_region(etx, Rect2((ac - sz / 2.0).round(), sz), Rect2(fw * fr, 0, fw, fh))
	# 底部压暗，放事件名与剧情
	var g0 := Color(0.04, 0.04, 0.043, 0.0)
	var g1 := Color(0.04, 0.04, 0.043, 0.95)
	g.panel_fg.draw_polygon(PackedVector2Array([p0 + Vector2(6, 300), p0 + Vector2(554, 300), p0 + Vector2(554, 492), p0 + Vector2(6, 492)]), PackedColorArray([g0, g0, g1, g1]))
	var ew0 := UI.en(g.panel_fg, g.font, p0 + Vector2(92, 366), "EVENT", 12, Color(0.6, 0.59, 0.56), 3.0)
	UI.text(g.panel_fg, g.font, p0 + Vector2(92 + ew0 + 6, 366), "·  海嗣祭坛", 12, Color(0.6, 0.59, 0.56))
	var em := p0 + Vector2(54, 400)
	var emb: Array = []
	for pl in art.emblem:
		var o2 := PackedVector2Array()
		for q in pl:
			o2.append(em + q)
		emb.append(o2)
	UI.curly_emblem(g.panel_fg, emb, em, 24.0, Color(0.18, 0.72, 1.0))
	g.panel_fg.draw_string(serif, p0 + Vector2(92, 408), g.panel_title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color.WHITE)
	if panel_sub_text != "":
		g.panel_fg.draw_multiline_string(g.font, p0 + Vector2(92, 440), UI.soft(panel_sub_text), HORIZONTAL_ALIGNMENT_LEFT, 430, 13, 3, Color(0.81, 0.79, 0.76), UI.BRK)
	# 右侧标题
	UI.en(g.panel_fg, g.font, Vector2(cx + 20, 142), "EVENT  ·  CHOOSE ONE", 12, Color(0.6, 0.59, 0.56), 4.0)
	g.panel_fg.draw_string(serif, Vector2(cx + 20, 178), "做出你的选择", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.925, 0.91, 0.882))
	var hint := "←→ 选择 · Ⓐ 确认" if Pad.using else "点击选项，或按 1–%d" % g.choices.size()
	UI.text(g.panel_fg, g.font, Vector2(cx + 20, 196 + ev_bars_h + 6), hint, 12, Color(0.55, 0.54, 0.52))


## 墨点 / 笔触多边形平移到插画框里；超出框的部分交给撕纸边外的暗底盖住（这里只做平移）
func offset_poly(p: PackedVector2Array, o: Vector2, _clip: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in p:
		out.append(o + Vector2(clampf(q.x, 2.0, 558.0), clampf(q.y, 2.0, 498.0)))
	return out


func show_choices(title: String, opts: Array, kind: String, sub := "") -> void:
	g.choices = opts
	g.choice_kind = kind
	g.nav_sel = 0
	g.state = Game.S.CHOICE
	g.panel_title_text = title
	panel_sub_text = sub
	if sub == "":
		if kind == "relic":
			panel_sub_text = "精英倒下后留下一只宝箱 —— 挑选一件带走"
		elif opts.size() > 0 and opts[0].kind == "recruit":
			panel_sub_text = "挑选一名干员加入编队"
		elif kind != "event":
			panel_sub_text = "选择一项强化"
	Sfx.play("relic" if kind == "relic" else "levelup", -2.0, 1.0, 0.0)
	for c in g.panel_box.get_children():
		c.queue_free()
	for c in g.panel_col.get_children():
		c.queue_free()
	layout(kind)
	var ev := kind == "event"
	ev_bars_h = 0.0
	for i in opts.size():
		var o: Dictionary = opts[i]
		var card := Button.new()
		card.custom_minimum_size = Vector2(596, 100) if ev else Vector2(CARD_W, CARD_H)
		card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		card.focus_mode = Control.FOCUS_NONE
		var empty := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			card.add_theme_stylebox_override(st, empty)
		card.set_meta("born", Time.get_ticks_msec() + i * 70)
		card.set_meta("oy", 60.0)
		card.set_meta("lift", 0.0)
		if ev:
			card.set_meta("bar", true)
		card.modulate.a = 0.0
		card.draw.connect((draw_event_bar if ev else draw_card).bind(card, o, i))
		card.mouse_entered.connect(func(): Sfx.play("ui_move", -6.0); card.queue_redraw())
		card.mouse_exited.connect(card.queue_redraw)
		card.pressed.connect(g.progression.pick.bind(i))
		# 说明文字：创建时按宽度排好版（放不下先缩字号）。选卡卡片三行还放不下就切紧凑布局——
		# 图标缩小、名字上移，把位置让给说明；事件选项条则按行数加高
		if ev:
			var fe := UI.fit(g.font, o.desc, 420.0, 4.0 * g.font.get_height(13), [13, 12])
			card.set_meta("fit", fe)
			card.custom_minimum_size.y = 100.0 + maxf(0.0, fe.lines.size() - 2) * float(fe.lh)
			ev_bars_h += card.custom_minimum_size.y + 14.0
		else:
			var f0 := UI.fit(g.font, o.desc, CARD_W - 40.0, 60.0, [13, 12])
			var compact: bool = not f0.fit
			if compact:
				f0 = UI.fit(g.font, o.desc, CARD_W - 40.0, 108.0, [13, 12, 11])
			card.set_meta("fit", f0)
			card.set_meta("compact", compact)
			# 作用对象标签（影响编队里的哪些干员）；一行放不下会收成「+N」，悬停提示里列全
			var chips := Affects.chips(g, o)
			card.set_meta("affects", chips)
			card.set_meta("chips_cut", not UI.chip_fits(g.font, chips, CARD_W - 32.0))
		(g.panel_col if ev else g.panel_box).add_child(card)
	g.panel.visible = true
	g.panel_fg.queue_redraw()


func animate_cards(dt: float) -> void:
	if not g.panel.visible:
		return
	g.panel_fg.queue_redraw()
	g.panel_tip.queue_redraw()
	var now := Time.get_ticks_msec()
	var box: BoxContainer = g.panel_col if (g.choice_kind == "event" and g.state == Game.S.CHOICE) else g.panel_box
	for card in box.get_children():
		if not card.has_meta("born"):
			continue
		var age := (now - int(card.get_meta("born"))) / 1000.0
		var k := clampf(age / 0.32, 0.0, 1.0)
		# easeOutBack
		var c1 := 1.7
		var e := 1.0 + (c1 + 1.0) * pow(k - 1.0, 3) + c1 * pow(k - 1.0, 2)
		var sold: bool = card.has_meta("item") and card.get_meta("item").get("sold", false)
		var hot := card_hot(card as Button, card.get_index()) and not sold
		var desc: Label = card.get_meta("desc") if card.has_meta("desc") else null   # get_meta 的默认值给 null 会报错
		card.modulate.a = clampf(age / 0.2, 0.0, 1.0)
		if card.has_meta("bar"):
			# 事件选项条：从右侧滑入，悬停时向左探出一点
			var lift: float = lerpf(card.get_meta("lift"), -8.0 if hot else 0.0, clampf(dt * 18.0, 0.0, 1.0))
			card.set_meta("lift", lift)
			var ox := (1.0 - e) * 80.0 + lift
			card.set_meta("ox", ox)
			if desc != null:
				desc.position.x = float(card.get_meta("dx", 112.0)) + ox
		else:
			var lift2: float = lerpf(card.get_meta("lift"), -10.0 if hot else 0.0, clampf(dt * 18.0, 0.0, 1.0))
			card.set_meta("lift", lift2)
			var oy := (1.0 - e) * 60.0 + lift2
			card.set_meta("oy", oy)
			if desc != null:
				desc.position.y = float(card.get_meta("dy", 230.0)) + oy
		card.queue_redraw()


## 卡片图标：按种类取对应贴图（relic_ / growth_ / weapon_ / evo_ / skill_），没有则返回 null
func card_icon(o: Dictionary) -> Texture2D:
	if o.has("icon"):
		return g.tex.get(o.icon)
	match o.kind:
		"relic":
			return g.tex.get("relic_" + o.id)
		"growth":
			return g.tex.get("growth_" + o.id)
		"weapon":
			return g.tex.get("weapon_" + o.id)
		"prog":
			return g.tex.get(o.get("icon", ""), null) if o.get("icon", "") != "" else null
		"recruit":
			var pt: Texture2D = g.tex.get("ally_" + o.id)
			return pt
	return null


func card_color(o: Dictionary) -> Color:
	if o.has("col"):
		return o.col
	match o.kind:
		"relic":
			return UI.CAT_COL.get(g.RL[o.id].cat, UI.GOLD)
		"recruit":
			return Color(0.55, 0.9, 0.55)
		"prog":
			if o.get("col", null) != null:
				return o.col
			return Color(0.8, 0.55, 1.0) if o.get("elite", 0) > 0 else Color(0.55, 0.85, 1.0)
		"weapon":
			return D.WEAPONS[o.id].col
	return UI.CYAN


func draw_card(card: Button, o: Dictionary, i: int) -> void:
	var hov := card_hot(card, i)
	var r := Rect2(Vector2(0, card.get_meta("oy", 0.0)), card.size)
	if hov:
		for k in 3:
			card.draw_rect(r.grow(2.0 + k * 3.0), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.12 - k * 0.035), false, 3.0)
	var top := Color(0.118, 0.129, 0.153, 0.95)
	var bot := Color(0.059, 0.067, 0.082, 0.95)
	card.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), PackedColorArray([top, top, bot, bot]))
	card.draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), Color(1, 1, 1, 0.14))
	card.draw_rect(r, UI.CYAN if hov else Color(1, 1, 1, 0.11), false, 1.0)
	var tag := card_tag(o)
	UI.strip(card, g.font, r.position + Vector2(14, 14), tag[0], tag[1], UI.CYAN if hov else Color(1, 1, 1, 0.88), UI.TEXT, 12)
	UI.ctext(card, g.font, r.position + Vector2(r.size.x - 40, 32), str(i + 1), 17, UI.TEXT if hov else Color(0.43, 0.47, 0.51), HORIZONTAL_ALIGNMENT_RIGHT, 24)
	if tag[2] != "":
		var rw := UI.cwidth(g.font, tag[2], 10) + 10.0
		card.draw_rect(Rect2(r.position + Vector2(14, 40), Vector2(rw, 15)), tag[3])
		UI.ctext(card, g.font, r.position + Vector2(19, 52), tag[2], 10, Color(0.08, 0.06, 0.02))
	# 图标 + 光环
	var compact: bool = card.get_meta("compact", false)
	var c := r.position + Vector2(r.size.x / 2.0, 100.0 if compact else 124.0)
	UI.halo(card, c, 40.0 if compact else 58.0, UI.CYAN, hov)
	var name: String = o.name
	var glyph := name.substr(0, 1)
	if o.kind == "relic":
		glyph = g.RL[o.id].name.substr(0, 1)
	elif o.kind == "weapon":
		glyph = D.WEAPONS[o.id].glyph
	var ic: Texture2D = card_icon(o)
	var bob := sin(g.t * 2.0 + i) * 2.0
	# 干员相关的卡（招募 / 成长 / 精英化 / 技能进阶）没有专属图标时，画该干员的待机第一帧
	var opid: String = o.id if o.kind == "recruit" else o.get("op", "")
	var idle: Dictionary = op_idle(opid) if ic == null and opid != "" else {}
	if not idle.is_empty():
		var ks: float = ((1.0 if compact else 2.0) if idle.fh <= 48 else (64.0 if compact else 96.0) / idle.fh)
		var asz := Vector2(idle.fw, idle.fh) * ks
		card.draw_texture_rect_region(idle.tex, Rect2(c - asz / 2.0 + Vector2(0, bob + 4), asz), Rect2(0, 0, idle.fw, idle.fh))
	elif ic != null:
		draw_icon_fit(card, ic, c + Vector2(0, bob), 64.0 if compact else 96.0)
	else:
		UI.text(card, g.font, c + Vector2(-40, 13 + bob), glyph, 34, card_color(o), HORIZONTAL_ALIGNMENT_CENTER, 80, 3)
	var nm := name
	if o.kind == "relic":
		nm = g.RL[o.id].name
	UI.text(card, g.font, r.position + Vector2(0, 184.0 if compact else 230.0), nm, 20, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 3)
	var fd: Dictionary = card.get_meta("fit", {})
	if not fd.is_empty():
		UI.draw_fit(card, g.font, r.position + Vector2(20, 198.0 if compact else 244.0), fd, Color(0.655, 0.69, 0.725), HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 40.0)
	# 作用对象：这张卡影响编队里的哪些干员（招募卡列这名干员的伤害特征）；说明区最多到 306，标签行在 310
	var chips: Array = card.get_meta("affects", [])
	if not chips.is_empty():
		UI.chip_row(card, g.font, r.position + Vector2(r.size.x / 2.0, r.size.y - 53.0), chips, r.size.x - 32.0, 1, "特性" if o.kind == "recruit" else "影响")
	# 底部操作条：普通钢蓝；悬停青底深字
	var ab := Rect2(r.position + Vector2(16, r.size.y - 44), Vector2(r.size.x - 32, 30))
	card.draw_rect(ab, UI.CYAN if hov else Color(UI.STEEL.r, UI.STEEL.g, UI.STEEL.b, 0.4))
	var ink := Color(0.04, 0.07, 0.09) if hov else Color.WHITE
	var kl := "[ %d ]" % (i + 1)
	var w1 := g.font.get_string_size("选择", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var w2 := UI.cwidth(g.font, kl, 12)
	var sx := ab.get_center().x - (w1 + 8.0 + w2) / 2.0
	UI.text(card, g.font, Vector2(sx, ab.position.y + 20), "选择", 14, ink)
	UI.ctext(card, g.font, Vector2(sx + w1 + 8.0, ab.position.y + 20), kl, 12, ink if hov else Color(1, 1, 1, 0.7))


## 卡片左上角标签：[英文, 中文, 稀有度小牌, 小牌底色]
func card_tag(o: Dictionary) -> Array:
	if o.kind == "relic" and not o.has("cat"):
		var rd: Dictionary = g.RL[o.id]
		var rar: String = rd.rarity
		var chip: Array = {"稀有": ["RARE", Color(0.62, 0.72, 0.85)], "核心": ["CORE", UI.GOLD], "升华": ["ASCEND", Color(0.72, 0.64, 1.0)], "遭诅古物": ["CURSED", UI.RED]}.get(rar, ["", Color.WHITE])
		return [UI.CAT_EN.get(rd.cat, "RELIC"), "%s · %s" % [rd.cat, rar], chip[0], chip[1]]
	var cat := "成长  GROWTH"
	if o.has("cat"):
		cat = o.cat
	elif o.kind == "recruit":
		cat = "招募 · " + o.get("cls", "") + "  RECRUIT"
	elif o.kind == "prog":
		cat = ("精英化  ELITE" if o.get("elite", 0) > 0 else "干员深度  OPERATOR")
	elif o.kind == "weapon":
		cat = "支援  " + D.WEAPONS[o.id].en
	# 「中文  ENGLISH」拆成两段；没有英文的整段当中文
	var parts := cat.split("  ", false)
	if parts.size() >= 2 and parts[parts.size() - 1].to_upper() == parts[parts.size() - 1]:
		var cn_s := "  ".join(parts.slice(0, parts.size() - 1))
		return [parts[parts.size() - 1], cn_s, "", Color.WHITE]
	return ["", cat, "", Color.WHITE]


## 按整数倍把像素图标放大到不超过 target 像素，居中画在 c
func draw_icon_fit(ci: CanvasItem, tx: Texture2D, c: Vector2, target: float, mod := Color.WHITE) -> void:
	var w := float(tx.get_width())
	var h := float(tx.get_height())
	var k: float = maxf(1.0, floorf(target / maxf(w, h)))
	if maxf(w, h) > target:
		k = target / maxf(w, h)
	var sz := Vector2(w, h) * k
	ci.draw_texture_rect(tx, Rect2((c - sz / 2.0).round(), sz), false, mod)


## 事件选项条（C 版式）：左端撕边的暗条 + 墨圈里的图标 + 衬线标题 + 效果小牌 + 说明（Label）+ 右侧序号；
## 选中：浅色底 + 左侧蓝色竖条 + 蓝色序号
func draw_event_bar(card: Button, o: Dictionary, i: int) -> void:
	var hov := card_hot(card, i)
	var art := event_art(g.panel_title_text)
	var ox: float = card.get_meta("ox", 0.0)
	var w := card.size.x
	var base := Vector2(ox, 0)
	var shape: PackedVector2Array = art.bars[i % art.bars.size()]
	var sp := PackedVector2Array()
	for q in shape:
		sp.append(base + Vector2(q.x * w / 596.0, q.y * card.size.y / 100.0))
	card.draw_colored_polygon(sp, Color(0.925, 0.91, 0.882, 0.14) if hov else Color(0.07, 0.07, 0.075, 0.9))
	var en_ring: PackedVector2Array = art.ensos[i % art.ensos.size()]
	var er := PackedVector2Array()
	for q in en_ring:
		er.append(base + q + Vector2(0, card.size.y / 2.0 - 50.0))
	card.draw_colored_polygon(er, Color(0.925, 0.91, 0.882, 0.55 if hov else 0.22))
	var ink := Color(0.925, 0.91, 0.882)
	var icn: String = o.get("icon", "")
	var itx: Texture2D = g.tex.get(icn) if icn != "" and icn != "exit" else null
	if itx != null:
		draw_icon_fit(card, itx, base + Vector2(56, card.size.y / 2.0), 64.0)
	else:
		UI.icon(card, "exit", base + Vector2(56, card.size.y / 2.0), 32.0, ink)
	card.draw_string(serif, base + Vector2(112, 38), o.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE if hov else ink)
	var x := 112.0 + serif.get_string_size(o.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 14.0
	for chp in o.get("chips", []):
		var cw := g.font.get_string_size(chp[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 12.0
		var cr := Rect2(base + Vector2(x, 20), Vector2(cw, 18))
		card.draw_rect(cr, Color(chp[1].r, chp[1].g, chp[1].b, 0.9), false, 1.0)
		card.draw_string(g.font, cr.position + Vector2(6, 13), chp[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, chp[1])
		x += cw + 6.0
	var fb: Dictionary = card.get_meta("fit", {})
	if not fb.is_empty():
		UI.draw_fit(card, g.font, base + Vector2(112, 50), fb, Color(0.81, 0.79, 0.76))
	UI.ctext(card, g.font, base + Vector2(w - 46, card.size.y / 2.0 + 10.0), str(i + 1), 24, Color(0.18, 0.72, 1.0) if hov else Color(0.37, 0.36, 0.35), HORIZONTAL_ALIGNMENT_CENTER, 24)
	if hov:
		card.draw_rect(Rect2(base + Vector2(8, 20), Vector2(8, card.size.y - 40.0)), Color(0.18, 0.72, 1.0, 0.25))
		card.draw_rect(Rect2(base + Vector2(10, 22), Vector2(4, card.size.y - 44.0)), Color(0.18, 0.72, 1.0))


## 干员待机条的第一帧：{tex, fw, fh}（按 data/characters/<id>.json 的 sprites.idle；没有返回空）
func op_idle(cid: String) -> Dictionary:
	if cid == "" or not Character.list_ids().has(cid):
		return {}
	var sp = Character.load_def(cid).get("sprites", {}).get("idle", null)
	if sp == null:
		return {}
	var tn: String = sp if sp is String else sp.get("tex", "")
	var tx: Texture2D = g.tex.get(tn)
	if tx == null:
		tx = A.tex(tn)
		g.tex[tn] = tx
	if tx == null:
		return {}
	var frames: int = int(sp.get("frames", 0)) if sp is Dictionary else 0
	if frames <= 0:
		frames = maxi(1, tx.get_width() / tx.get_height())
	return {"tex": tx, "fw": tx.get_width() / frames, "fh": tx.get_height()}


## 干员贴图集（运行中招募 / 测试编入时补加载）
func load_op_tex(cid: String) -> void:
	var cdef: Dictionary = Character.load_def(cid)
	var csp: Dictionary = cdef.get("sprites", {})
	for kind in ["idle", "run", "attack", "skill"] + cdef.get("extra_sprites", []):
		if csp.has(kind):
			var tn: String = csp[kind] if csp[kind] is String else csp[kind].tex
			if g.tex.get(tn) == null:
				g.tex[tn] = A.tex(tn)


## 选卡 / 商店 / 事件：焦点卡片的说明被截断（或作用对象标签收成了「+N」）时，在面板最上层画完整说明（卡片下方，放不下放上方）
func draw_panel_tip() -> void:
	var box: BoxContainer = g.panel_col if (g.choice_kind == "event" and g.state == Game.S.CHOICE) else g.panel_box
	var vs := g.panel_tip.size
	for card in box.get_children():
		if not (card is Button) or card.is_queued_for_deletion():
			continue
		var fd: Dictionary = card.get_meta("fit", {})
		var cut: bool = card.get_meta("chips_cut", false)
		if ((fd.is_empty() or fd.get("fit", true)) and not cut) or not g.panel_ui.card_hot(card, card.get_index()):
			continue
		var gr: Rect2 = card.get_global_rect()
		var it: Dictionary = card.get_meta("item", {})
		var title: String = it.get("name", "") if not it.is_empty() else (g.choices[card.get_index()].get("name", "") if card.get_index() < g.choices.size() else "")
		var desc: String = it.get("desc", "") if not it.is_empty() else (g.choices[card.get_index()].get("desc", "") if card.get_index() < g.choices.size() else "")
		if cut:
			desc += "\n影响：" + "、".join(PackedStringArray(card.get_meta("affects", []).map(func(c): return c[0])))
		g.hud_view.draw_tooltip(vs, Rect2(gr.position - g.panel_tip.get_global_rect().position, gr.size), title, "完整说明", desc, "", UI.CYAN, g.panel_tip)
		return
