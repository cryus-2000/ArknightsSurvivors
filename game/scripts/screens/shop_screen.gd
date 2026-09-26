extends RefCounted
## 界面 · 商店（state SHOP）：商人货架的卡片、按钮与背景。货架内容、定价与购买结算在 run/shop.gd；面板框架与按钮在 screens/choice_panel.gd。
## 界面层约定（docs/37）。2026-09-26 从 game.gd 拆出。

const UI = preload("res://scripts/ui.gd")
const A = preload("res://scripts/art.gd")

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game
## 商人（A4）：左侧商人立绘框（暖色提灯光）+ 右上「货架」与持有源石锭 + 底部提示；五张货品卡在 panel_box
const MERCHANT_LINES := ["灯火暗下来之前，把源石锭花掉吧。", "深海里什么都能换，只要你出得起价。", "别盯着我看，看货。", "都是从沉船里捞上来的，保真。"]


func _init(game: Game) -> void:
	g = game


func build() -> void:
	g.nav_sel = clampi(g.nav_sel, 0, maxi(0, g.shop_items.size() - 1))
	for c in g.panel_box.get_children():
		c.queue_free()
	g.choice_kind = "shop"
	g.panel_ui.layout("shop")
	var n := g.shop_items.size()
	var sep: float = 14.0 if n <= 5 else 10.0
	g.panel_box.add_theme_constant_override("separation", int(sep))
	var cw: float = minf(160.0, (868.0 - sep * (n - 1)) / maxf(1.0, n))
	g.panel_title_text = "流浪商人"
	for c in g.panel.get_children():
		if c.has_meta("shopbtn"):
			c.queue_free()
	var vs0: Vector2 = g.get_viewport_rect().size
	var cx := vs0.x / 2.0
	g.panel_ui.button("刷新货架", Rect2(cx - 280, 546, 214, 40), g.shop_sys.refresh, not g.shop_refreshed and g.ingots >= g.shop_sys.price("refresh"), "refresh", "仅一次" if not g.shop_refreshed else "已刷新过", -1 if g.shop_refreshed else g.shop_sys.price("refresh"))
	g.panel_ui.button("离开", Rect2(cx - 52, 546, 150, 40), g.shop_sys.close, true, "", "", -1, "ESC")
	for i in n:
		var it: Dictionary = g.shop_items[i]
		var card := Button.new()
		card.custom_minimum_size = Vector2(cw, 296)
		card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		card.focus_mode = Control.FOCUS_NONE
		var empty := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			card.add_theme_stylebox_override(st, empty)
		card.set_meta("born", Time.get_ticks_msec() + i * 50)
		card.set_meta("oy", 60.0)
		card.set_meta("lift", 0.0)
		card.set_meta("dy", 174.0)
		card.set_meta("item", it)
		card.modulate.a = 0.0
		card.draw.connect(draw_card.bind(card, it, i))
		card.mouse_entered.connect(func(): card.queue_redraw())
		card.mouse_exited.connect(card.queue_redraw)
		card.pressed.connect(g.shop_sys.buy.bind(i))
		var fs0 := UI.fit(g.font, it.desc, cw - 20.0, 64.0, [12, 11])
		var sc_compact: bool = not fs0.fit
		if sc_compact:
			fs0 = UI.fit(g.font, it.desc, cw - 20.0, 80.0, [12, 11])
		card.set_meta("fit", fs0)
		card.set_meta("compact", sc_compact)
		g.panel_box.add_child(card)
	g.panel.visible = true
	g.panel_fg.queue_redraw()


## 货品卡（A4）：炭灰卡 + 节点标签条 + 序号 + 图标光环 + 名称 + 说明 + 底部价格条
## （可买：钢蓝，悬停青底；买不起：洋红细边 +「不足」；已售出：整卡变暗、图标去色）
func draw_card(card: Button, it: Dictionary, i: int) -> void:
	var hov: bool = g.panel_ui.card_hot(card, i) and not it.sold
	var afford: bool = g.ingots >= it.price
	var r := Rect2(Vector2(0, card.get_meta("oy", 0.0)), card.size)
	var a := 0.55 if it.sold else 1.0
	if hov:
		for k in 3:
			card.draw_rect(r.grow(2.0 + k * 3.0), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.12 - k * 0.035), false, 3.0)
	var top := Color(0.118, 0.129, 0.153, 0.95 * a)
	var bot := Color(0.059, 0.067, 0.082, 0.95 * a)
	card.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), PackedColorArray([top, top, bot, bot]))
	card.draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), Color(1, 1, 1, 0.14 * a))
	card.draw_rect(r, UI.CYAN if hov else Color(1, 1, 1, 0.11 * a), false, 1.0)
	var en_s := "SUPPLY"
	var cn_s := "补给"
	if it.kind == "relic":
		var rd: Dictionary = g.RL[it.id]
		en_s = UI.CAT_EN.get(rd.cat, "RELIC")
		cn_s = rd.cat
	elif it.kind == "oil":
		en_s = "LIGHT"
		cn_s = "灯火"
	var sc: Color = UI.CYAN if hov else Color(1, 1, 1, 0.88 * a)
	# 序号在底部价格条里（[ 1 ]）；标签条放不下就只留英文
	if UI.strip_width(g.font, en_s, cn_s, 11) > r.size.x - 20.0:
		cn_s = ""
	UI.strip(card, g.font, r.position + Vector2(10, 10), en_s, cn_s, sc, UI.TEXT, 11)
	if it.get("deep", false):
		UI.chip(card, g.font, r.position + Vector2(10, 36), "深海馈赠", Color(UI.PURPLE.r, UI.PURPLE.g, UI.PURPLE.b, a), 10)
	var sc_compact: bool = card.get_meta("compact", false)
	var c := r.position + Vector2(r.size.x / 2.0, 80.0 if sc_compact else 94.0)
	UI.halo(card, c, 32.0, UI.CYAN, hov, a)
	var mod := Color(1, 1, 1, a) if not it.sold else Color(0.45, 0.45, 0.45, a)
	var ic: Texture2D = g.tex.get("relic_" + it.id) if it.kind == "relic" else null
	if ic != null:
		g.panel_ui.draw_icon_fit(card, ic, c, 64.0, mod)
	elif it.kind == "oil" and g.tex.get("oil") != null:
		g.panel_ui.draw_icon_fit(card, g.tex.oil, c, 52.0, mod)
	elif it.kind == "heal" and g.tex.get("pickup_heal") != null:
		g.panel_ui.draw_icon_fit(card, g.tex.pickup_heal, c, 56.0, mod)
	else:
		UI.text(card, g.font, c + Vector2(-30, 10), it.name.substr(0, 1), 28, Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, a), HORIZONTAL_ALIGNMENT_CENTER, 60, 3)
	var fs := 15 if g.font.get_string_size(it.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x <= r.size.x - 14.0 else 12
	UI.text(card, g.font, r.position + Vector2(0, 150.0 if sc_compact else 164.0), it.name, fs, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 2)
	var fd: Dictionary = card.get_meta("fit", {})
	if not fd.is_empty():
		UI.draw_fit(card, g.font, r.position + Vector2(10, 158.0 if sc_compact else 172.0), fd, Color(0.655, 0.69, 0.725, a), HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 20.0)
	var pb := Rect2(r.position + Vector2(10, r.size.y - 44), Vector2(r.size.x - 20, 32))
	if it.sold:
		card.draw_rect(pb, Color(1, 1, 1, 0.06))
		UI.text(card, g.font, Vector2(pb.position.x, pb.position.y + 21), "已售出", 13, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, pb.size.x)
		return
	var pc := Color.WHITE
	var kc := Color(1, 1, 1, 0.7)
	if hov and afford:
		card.draw_rect(pb, UI.CYAN)
		pc = Color(0.04, 0.07, 0.09)
		kc = pc
	elif not afford:
		card.draw_rect(pb, Color(UI.RED.r, UI.RED.g, UI.RED.b, 0.12))
		card.draw_rect(pb, Color(UI.RED.r, UI.RED.g, UI.RED.b, 0.55), false, 1.0)
		pc = Color(1.0, 0.48, 0.66)
		kc = Color(1.0, 0.48, 0.66, 0.8)
	else:
		card.draw_rect(pb, Color(UI.STEEL.r, UI.STEEL.g, UI.STEEL.b, 0.4))
	card.draw_texture_rect(g.tex.ingot, Rect2(pb.position + Vector2(10, 9), Vector2(18, 14)), false)
	UI.ctext(card, g.font, pb.position + Vector2(34, 24), str(it.price), 21, pc)
	if not afford:
		UI.text(card, g.font, pb.position + Vector2(40 + UI.cwidth(g.font, str(it.price), 21), 21), "不足", 11, pc)
	UI.ctext(card, g.font, Vector2(pb.end.x - 40, pb.position.y + 21), "[ %d ]" % (i + 1), 12, kc, HORIZONTAL_ALIGNMENT_RIGHT, 32)


func draw_bg(vs: Vector2) -> void:
	var cx := vs.x / 2.0
	g.panel_ui.header(vs, "SHOP  ·  WANDERING TRADER", "流浪商人", "在灯火熄灭之前，用源石锭换些能活下去的东西")
	var mr := Rect2(Vector2(cx - 580, 192), Vector2(280, 388))
	var mt := Color(0.125, 0.11, 0.094, 0.95)
	var mb := Color(0.055, 0.051, 0.047, 0.95)
	g.panel_fg.draw_polygon(PackedVector2Array([mr.position, Vector2(mr.end.x, mr.position.y), mr.end, Vector2(mr.position.x, mr.end.y)]), PackedColorArray([mt, mt, mb, mb]))
	var gc := mr.position + Vector2(mr.size.x / 2.0, 236)
	for k in 6:
		g.panel_fg.draw_circle(gc, 150.0 - k * 22.0, Color(1.0, 0.66, 0.31, 0.035))
	g.panel_fg.draw_set_transform(mr.position + Vector2(mr.size.x / 2.0, 330), 0.0, Vector2(1.0, 0.16))
	g.panel_fg.draw_circle(Vector2.ZERO, 76.0, Color(0, 0, 0, 0.5))
	g.panel_fg.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var mtx: Texture2D = g.tex.get("merchant")
	if mtx != null:
		var fw := mtx.get_width() / 2
		var fh := mtx.get_height()
		var ks: float = 5.0 / A.hires_of(mtx)
		var sz := Vector2(fw, fh) * ks
		var fr := int(g.t * 2.0) % 2
		g.panel_fg.draw_texture_rect_region(mtx, Rect2((mr.position + Vector2(mr.size.x / 2.0 - sz.x / 2.0, 334 - sz.y)).round(), sz), Rect2(fw * fr, 0, fw, fh))
	g.panel_fg.draw_rect(mr, Color(1, 1, 1, 0.11), false, 1.0)
	g.panel_fg.draw_rect(Rect2(mr.position, Vector2(14, 2)), UI.GOLD)
	UI.strip(g.panel_fg, g.font, mr.position + Vector2(12, 12), "STAY", "还会停留 %d 秒" % int(g.merchant.get("life", 0.0)), UI.GOLD, Color(0.95, 0.87, 0.68))
	UI.tab(g.panel_fg, g.font, mr.position + Vector2(16, 340), "流浪商人", UI.TAB_LAMP)
	UI.en(g.panel_fg, g.font, mr.position + Vector2(90, 353), "WANDERING TRADER", 10, UI.SUB, 2.0)
	UI.text(g.panel_fg, g.font, mr.position + Vector2(16, 378), "「%s」" % MERCHANT_LINES[maxi(0, g.merchant_idx - 1) % MERCHANT_LINES.size()], 13, Color(0.85, 0.87, 0.89))
	# 右上：货架 + 持有源石锭（明日方舟费用框）
	UI.text(g.panel_fg, g.font, Vector2(cx - 280, 216), "货架", 20, UI.TEXT)
	UI.en(g.panel_fg, g.font, Vector2(cx - 232, 214), "GOODS  ·  %d" % g.shop_items.size(), 12, UI.SUB, 3.0)
	var dp := Rect2(Vector2(cx + 460, 188), Vector2(128, 34))
	g.panel_fg.draw_rect(dp, Color(0.03, 0.035, 0.045, 0.86))
	g.panel_fg.draw_rect(Rect2(dp.position, Vector2(3, dp.size.y)), UI.GREEN)
	g.panel_fg.draw_texture_rect(g.tex.ingot, Rect2(dp.position + Vector2(12, 10), Vector2(18, 14)), false)
	UI.ctext(g.panel_fg, g.font, dp.position + Vector2(38, 27), str(g.ingots), 26, UI.TEXT)
	UI.text(g.panel_fg, g.font, dp.position + Vector2(84, 22), "源石锭", 10, UI.SUB)
	UI.text(g.panel_fg, g.font, Vector2(dp.position.x - 110, dp.position.y + 22), "持有", 12, Color(0.81, 0.84, 0.86), HORIZONTAL_ALIGNMENT_RIGHT, 100)
	var hint := ("←→ 选择 · Ⓐ 购买 · Ⓨ 刷新 · Ⓑ 离开" if Pad.using else "点击或按 1–%d 购买  ·  F 刷新  ·  Esc 离开" % g.shop_items.size())
	UI.text(g.panel_fg, g.font, Vector2(cx + 116, 571), hint, 12, UI.SUB)
