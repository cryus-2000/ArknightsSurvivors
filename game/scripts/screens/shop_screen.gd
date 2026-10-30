extends RefCounted
## 界面 · 商店（state SHOP）：商人货架的卡片、按钮与背景。货架内容、定价与购买结算在 run/shop.gd；面板框架与按钮在 screens/choice_panel.gd。
## 界面层约定（docs/39 §3）。2026-09-26 从 game.gd 拆出。

const UI = preload("res://scripts/ui.gd")
const A = preload("res://scripts/art.gd")
const Affects = preload("res://scripts/run/affects.gd")

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game
## 商人（A4）：左侧商人立绘框（暖色提灯光）+ 右上「货架」与持有源石锭 + 底部提示；五张货品卡在 panel_box
const CARD_H := 330.0          # 货品卡高度（含两行作用对象标签）；卡片顶边见 choice_panel.layout("shop")
const TOP_PHONE := 96.0        # 手机（界面层放大后逻辑约 1044×481，手机端 UI 优化 r2）：卡片顶边；不画商人立绘框，卡片横跨整屏
## 三档布局参数（docs/126 C6）：下标 = Cfg.ui_form()（0 桌面 / 1 触屏 / 2 手机横屏，商店触屏与手机同一版式）。
## touch：卡片横跨整屏、不画商人立绘框；card_max_w：卡宽上限；btn_h：按钮高；name_fs：名字放得下时的字号（0 = 按卡宽 15 / 12）
const LAY := [
	{"touch": false, "card_max_w": 160.0, "btn_h": 40.0, "name_fs": 0},
	{"touch": true, "card_max_w": 190.0, "btn_h": 44.0, "name_fs": 18},
	{"touch": true, "card_max_w": 190.0, "btn_h": 44.0, "name_fs": 18},
]


func lay() -> Dictionary:
	return LAY[Cfg.ui_form()]


## 货品卡高度：手机按剩余高度（顶 96、底下留按钮 72）
func card_h(vs: Vector2) -> float:
	return clampf(vs.y - TOP_PHONE - 72.0, 240.0, CARD_H) if lay().touch else CARD_H
const MERCHANT_LINES := ["灯火暗下来之前，把源石锭花掉吧。", "深海里什么都能换，只要你出得起价。", "别盯着我看，看货。", "都是从沉船里捞上来的，保真。"]


func _init(game: Game) -> void:
	g = game


## restart：打开商店 / 刷新货架时为 true（货架从第一格重新点亮，docs/62 §3.15）；买东西重建卡片时不重放
func build(restart := false) -> void:
	if restart:
		g.panel_ui.motion.start_shop()
	g.nav_sel = clampi(g.nav_sel, 0, maxi(0, g.shop_items.size() - 1))
	for c in g.panel_box.get_children():
		c.queue_free()
	g.choice_kind = "shop"
	g.panel_ui.layout("shop")
	var n := g.shop_items.size()
	var sep: float = 14.0 if n <= 5 else 10.0
	g.panel_box.add_theme_constant_override("separation", int(sep))
	var cw: float = minf(160.0, (868.0 - sep * (n - 1)) / maxf(1.0, n))
	g.panel_title_text = "诡意行商" if g.shop_sys.trader else "流浪商人"
	g.panel_ui.detail_i = -1
	for a in Cfg.dev_args():   # --carddetail=<n>（截图验收）：直接展开第 n 张货品的详情
		if a.begins_with("--carddetail="):
			g.panel_ui.detail_i = int(a.substr(13))
	var ph: bool = Cfg.phone_ui()   # 手机（10-26 实机挤满）：卡上一句核心效果、大字，完整说明点「详情」
	for c in g.panel.get_children():
		if c.has_meta("shopbtn"):
			c.queue_free()
	var vs0: Vector2 = g.panel.size   # 触屏界面层放大后 = UI 逻辑尺寸
	var cx := vs0.x / 2.0
	var L: Dictionary = lay()
	var touch: bool = L.touch
	var ch: float = card_h(vs0)
	var bl: float = cx - 280.0   # 按钮行左边
	if touch:
		# 手机：卡片加宽到 ≤ 190、横跨整屏居中（左右各留 20），顶边 96；按钮本体 44 高跟在卡片下
		cw = minf(float(L.card_max_w), (vs0.x - 40.0 - sep * (n - 1)) / maxf(1.0, n))
		var tot: float = cw * n + sep * (n - 1)
		g.panel_box.offset_left = -tot / 2.0
		g.panel_box.offset_right = tot / 2.0
		g.panel_box.offset_top = TOP_PHONE
		bl = cx - tot / 2.0
	var by: float = g.panel_box.offset_top + ch + 14.0
	var bh: float = float(L.btn_h)
	var free: bool = g.shop_sys.refresh_free()
	g.panel_ui.button("刷新货架", Rect2(bl, by, 214, bh), g.shop_sys.refresh, not g.shop_refreshed and (free or g.ingots >= g.shop_sys.price("refresh")), "refresh",
		("本局免费一次" if free else "仅一次") if not g.shop_refreshed else "已刷新过", -1 if (g.shop_refreshed or free) else g.shop_sys.price("refresh"))
	g.panel_ui.button("离开", Rect2(bl + 228, by, 150, bh), g.shop_sys.close, true, "", "", -1, "ESC")
	for i in n:
		var it: Dictionary = g.shop_items[i]
		var card := Button.new()
		card.custom_minimum_size = Vector2(cw, ch)
		card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		card.focus_mode = Control.FOCUS_NONE
		var empty := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			card.add_theme_stylebox_override(st, empty)
		card.set_meta("born", Time.get_ticks_msec() + i * 50)
		card.set_meta("oy", 0.0)
		card.set_meta("lift", 0.0)
		card.set_meta("item", it)
		card.draw.connect(func():
			draw_card(card, it, i)
			g.panel_ui.motion.shop_card_post(card, i))
		card.mouse_entered.connect(func(): card.queue_redraw())
		card.mouse_exited.connect(card.queue_redraw)
		if ph:
			card.pressed.connect(func():
				if not g.panel_ui.detail_tap(card, i):
					g.panel_ui.detail_i = -1
					g.shop_sys.buy(i))
		else:
			card.pressed.connect(g.shop_sys.buy.bind(i))
		# 触屏说明字先试大 2 号（手机上 12 号只有约 6.5 pt），放不下再退回原字号；手机一句话 20 起、最小 17
		var szs: Array = ([18, 17, 16, 15, 14] if touch else [14, 13, 12, 11]) if Pad.touch_ui() else [13, 12]   # 电脑：说明不低于 13（docs/37 最小字号）
		if ph:
			szs = [20, 19, 18, 17]
		var chips := Affects.chips(g, it)
		# 触屏：说明区底边留到「影响」标签上方（标签行底在卡底上方 52，每行 22 高，最多 2 行）。原来固定留 60，
		# 标签一行时压 10、两行时压 32（10-13 手机实测「炸裂之手」说明末行压在标签上）
		var bot: float = 60.0
		if touch and not chips.is_empty():
			bot = 52.0 + (22.0 if UI.chip_fits(g.font, chips, cw - 16.0, 1, 10) else 44.0) + 6.0
		# 商品卡说明 + 构筑受益行（docs/119 §4.4，build_affinity.relic_lines；非三条链 / 开关关为空）
		var sdesc: String = str(it.desc)
		if it.kind == "relic":
			var bline: String = g.progression.affinity.relic_lines(str(it.id), true)
			if bline != "":
				sdesc += "\n" + bline
		var sfull := sdesc
		if str(it.get("full", it.desc)) != str(it.desc):
			# 卡面只写本编队相关的部分（relic_fx.squad_desc，10-28）：完整规则进悬停 / 详情
			sfull = str(it.full) + sdesc.substr(str(it.desc).length())
			card.set_meta("full_desc", sfull)
			card.set_meta("squad_cut", true)
		if ph:
			card.set_meta("full_desc", sfull)
			var bf: String = g.panel_ui.brief(sdesc)
			card.set_meta("brief", bf)
			card.set_meta("more", bf != sfull.strip_edges())
			sdesc = bf
		var fs0 := UI.fit(g.font, sdesc, cw - 20.0, (ch - 164.0 - bot) if touch else 64.0, szs)
		var sc_compact: bool = not fs0.fit
		if sc_compact:
			fs0 = UI.fit(g.font, sdesc, cw - 20.0, (ch - 152.0 - bot) if touch else 80.0, szs)
		card.set_meta("fit", fs0)
		card.set_meta("compact", sc_compact)
		card.set_meta("affects", chips)
		card.set_meta("chips_cut", not UI.chip_fits(g.font, chips, cw - 16.0, 2, 10))
		g.panel_box.add_child(card)
	g.panel.visible = true
	g.panel_fg.queue_redraw()


## 货品卡（A4）：炭灰卡 + 节点标签条 + 序号 + 图标光环 + 名称 + 说明 + 作用对象标签（至多两行）+ 底部价格条
## （可买：钢蓝，悬停青底；买不起：洋红细边 +「不足」；已售出：整卡变暗、图标去色）
func draw_card(card: Button, it: Dictionary, i: int) -> void:
	var hov: bool = g.panel_ui.card_hot(card, i) and not it.sold
	var afford: bool = g.ingots >= it.price
	var blocked: bool = it.kind == "relic" and (g.shop_sys.relic_buys_left() <= 0 or not g.progression.can_gain_relic(it.id))
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
		en_s = UI.CAT_EN.get(rd.lane_name, "RELIC")
		cn_s = rd.lane_name
	elif it.kind == "oil":
		en_s = "LIGHT"
		cn_s = "灯火"
	var sc: Color = UI.CYAN if hov else Color(1, 1, 1, 0.88 * a)
	# 序号在底部价格条里（[ 1 ]）；标签条放不下就只留英文
	if UI.strip_width(g.font, en_s, cn_s, 11) > r.size.x - 20.0:
		cn_s = ""
	if card.get_meta("more", false):
		cn_s = ""   # 手机：右上有「详情」键，标签条只留英文
	UI.strip(card, g.font, r.position + Vector2(10, 10), en_s, cn_s, sc, UI.TEXT, 11)
	if card.get_meta("more", false) and not it.sold:
		g.panel_ui.draw_detail_chip(card, r, i, true)
	if it.get("deep", false):
		UI.chip(card, g.font, r.position + Vector2(10, 36), "深海馈赠", Color(UI.PURPLE.r, UI.PURPLE.g, UI.PURPLE.b, a), 10)
	var sc_compact: bool = card.get_meta("compact", false)
	var c := r.position + Vector2(r.size.x / 2.0, 76.0 if sc_compact else 88.0)
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
	# 10-31 TA 审阅 docs/208 H8（同组卡字号统一，商人货架同样检查）：原来逐张判断，长名字那张单独缩到 12。改成整排取都放得下的最大字号
	var fit_all := func(sz: int) -> bool:
		return g.shop_items.all(func(x): return g.font.get_string_size(str(x.name), HORIZONTAL_ALIGNMENT_LEFT, -1, UI.fs(sz)).x <= r.size.x - 14.0)
	var fs := 12
	for sz in [15, 14, 13]:
		if fit_all.call(sz):
			fs = sz
			break
	var nfs: int = int(lay().name_fs)
	if nfs > 0 and fit_all.call(nfs):
		fs = nfs   # 手机：名字 18（整排都放得下才用）
	UI.text(card, g.font, r.position + Vector2(0, 144.0 if sc_compact else 156.0), it.name, fs, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 2)
	var fd: Dictionary = card.get_meta("fit", {})
	if not fd.is_empty():
		var dc := Color(0.86, 0.9, 0.93, a) if card.has_meta("brief") else Color(0.655, 0.69, 0.725, a)
		UI.draw_fit(card, g.font, r.position + Vector2(10, 152.0 if sc_compact else 164.0), fd, dc, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 20.0)
	# 作用对象（run/affects.gd）：卡窄，不带「影响」小字，放不下折到第二行；贴着价格条（说明区最多到 232）
	var chips: Array = card.get_meta("affects", [])
	if not chips.is_empty():
		UI.chip_row(card, g.font, r.position + Vector2(r.size.x / 2.0, r.size.y - 52.0), chips, r.size.x - 16.0, 2, "", 10, a)
	var pb := Rect2(r.position + Vector2(10, r.size.y - 44), Vector2(r.size.x - 20, 32))
	if blocked and not it.sold:
		card.draw_rect(pb, Color(1, 1, 1, 0.06))
		UI.text(card, g.font, Vector2(pb.position.x, pb.position.y + 21), "本次限购已满" if g.shop_sys.relic_buys_left() <= 0 else "空间已预留", 12, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, pb.size.x)
		return
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
	# 10-31 TA H7：价签不再写「[ n ]」（底部提示行已写「按 1–N 购买」）


## 手机版背景（手机端 UI 优化 r2）：标题压在顶栏上（压暗带遮住）、一行交易说明、「藏品 n · 商人还会停留」一行，
## 右上持有源石锭；商人立绘框放不下不画
func _draw_bg_phone(vs: Vector2) -> void:
	var cx := vs.x / 2.0
	var top: float = g.panel_box.offset_top
	var note: String = "第 %d 次交易 · 价格 ×%.2f · %s" % [maxi(1, g.merchant_idx), g.shop_sys.price_mult(), g.shop_sys.step_note()]
	if not g.shop_sys.relic_buy_unlimited():
		note += " · 藏品还可买 %d 件" % g.shop_sys.relic_buys_left()
	g.panel_ui.header(vs, "SHOP  ·  WANDERING TRADER", "流浪商人", note, top - 92.0)
	var left: float = cx + g.panel_box.offset_left
	var right: float = cx + g.panel_box.offset_right
	# 底下垫一条暗底：手机上压暗带只压一半，左上 HUD 的状态小字会从这行后面透出来（10-11）
	var rl: String = "%s · 商人还会停留 %d 秒" % [g.progression.relic_count_text(), int(g.merchant.get("life", 0.0))]
	g.panel_fg.draw_rect(Rect2(left - 6.0, top - 24.0, g.font.get_string_size(rl, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.fs(14)).x + 12.0, 22.0), Color(0.03, 0.035, 0.045, 0.9))
	UI.text(g.panel_fg, g.font, Vector2(left, top - 6.0), rl, 14, UI.SUB)
	var dp := Rect2(Vector2(right - 128.0, top - 48.0), Vector2(128, 34))
	g.panel_fg.draw_rect(dp, Color(0.03, 0.035, 0.045, 0.86))
	g.panel_fg.draw_rect(Rect2(dp.position, Vector2(3, dp.size.y)), UI.GREEN)
	g.panel_fg.draw_texture_rect(g.tex.ingot, Rect2(dp.position + Vector2(12, 10), Vector2(18, 14)), false)
	UI.ctext(g.panel_fg, g.font, dp.position + Vector2(38, 27), str(g.ingots), 26, UI.TEXT)
	UI.text(g.panel_fg, g.font, Vector2(dp.position.x + 84, dp.position.y + 22), "源石锭", 10, UI.SUB)
	UI.text(g.panel_fg, g.font, Vector2(dp.position.x - 60, dp.position.y + 22), "持有", 13, Color(0.81, 0.84, 0.86), HORIZONTAL_ALIGNMENT_RIGHT, 50)
	var hints: Array = ["←→ 选择 · Ⓐ 购买", "Ⓨ 刷新 · Ⓑ 离开"] if Pad.using else ["点卡片购买", "点「刷新货架」/「离开」"]
	var hy: float = top + card_h(vs) + 14.0
	UI.text(g.panel_fg, g.font, Vector2(left + 400.0, hy + 18.0), hints[0], 14, UI.SUB)
	UI.text(g.panel_fg, g.font, Vector2(left + 400.0, hy + 38.0), hints[1], 14, UI.SUB)


func draw_bg(vs: Vector2) -> void:
	if lay().touch:
		_draw_bg_phone(vs)
		return
	var cx := vs.x / 2.0
	# 纵向：标题 92 起；货架卡片顶边 = panel_box.offset_top（222），下面是按钮；商人框与卡片 + 按钮等高
	var top: float = g.panel_box.offset_top
	var note: String = "第 %d 次交易 · 当前价格 ×%.2f · %s" % [maxi(1, g.merchant_idx), g.shop_sys.price_mult(), g.shop_sys.step_note()]
	if not g.shop_sys.relic_buy_unlimited():
		note += " · 藏品还可买 %d 件（刷新不重置）" % g.shop_sys.relic_buys_left()
	g.panel_ui.header(vs, "SHOP  ·  WANDERING TRADER", "流浪商人", note, top - 130.0)
	# 藏品额度一行：原来在标题说明行下面 8 像素（top − 52），两行字压在一起（10-11）；挪到「货架 GOODS」同一行、GOODS 之后
	var gw: float = UI.en_width(g.font, "GOODS  ·  %d" % g.shop_items.size(), 12, 3.0)
	UI.text(g.panel_fg, g.font, Vector2(cx - 232 + gw + 18.0, top - 20.0), g.progression.relic_count_text() + ("" if g.progression.relic_cap() < 0 else "；满后仍可升级已有藏品"), 12, UI.SUB)
	var mr := Rect2(Vector2(cx - 580, top - 42.0), Vector2(280, CARD_H + 96.0))
	var mt := Color(0.125, 0.11, 0.094, 0.95)
	var mb := Color(0.055, 0.051, 0.047, 0.95)
	g.panel_fg.draw_polygon(PackedVector2Array([mr.position, Vector2(mr.end.x, mr.position.y), mr.end, Vector2(mr.position.x, mr.end.y)]), PackedColorArray([mt, mt, mb, mb]))
	# 立绘与名牌整体下移 20，框底留出和原来差不多的空
	var my := 20.0
	var gc := mr.position + Vector2(mr.size.x / 2.0, 236 + my)
	for k in 6:
		g.panel_fg.draw_circle(gc, 150.0 - k * 22.0, Color(1.0, 0.66, 0.31, 0.035))
	g.panel_fg.draw_set_transform(mr.position + Vector2(mr.size.x / 2.0, 330 + my), 0.0, Vector2(1.0, 0.16))
	g.panel_fg.draw_circle(Vector2.ZERO, 76.0, Color(0, 0, 0, 0.5))
	g.panel_fg.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var mtx: Texture2D = g.tex.get("merchant")
	if mtx != null:
		var fw := mtx.get_width() / 2
		var fh := mtx.get_height()
		var ks: float = 5.0 / A.hires_of(mtx)
		var sz := Vector2(fw, fh) * ks
		var fr := int(g.t * 2.0) % 2
		var mdst := Rect2((mr.position + Vector2(mr.size.x / 2.0 - sz.x / 2.0, 334 + my - sz.y)).round(), sz)
		g.panel_fg.draw_texture_rect_region(mtx, mdst, Rect2(fw * fr, 0, fw, fh))
		g.panel_ui.motion.draw_shop_lantern(g.panel_fg, mdst, fr)   # 货物暖光一明一暗、货架逐格亮起（docs/62 §3.15；10-21 新商人无提灯）
	g.panel_fg.draw_rect(mr, Color(1, 1, 1, 0.11), false, 1.0)
	g.panel_fg.draw_rect(Rect2(mr.position, Vector2(14, 2)), UI.GOLD)
	UI.strip(g.panel_fg, g.font, mr.position + Vector2(12, 12), "STAY", "还会停留 %d 秒" % int(g.merchant.get("life", 0.0)), UI.GOLD, Color(0.95, 0.87, 0.68))
	UI.tab(g.panel_fg, g.font, mr.position + Vector2(16, 340 + my), "流浪商人", UI.TAB_LAMP)
	UI.en(g.panel_fg, g.font, mr.position + Vector2(90, 353 + my), "WANDERING TRADER", 10, UI.SUB, 2.0)
	UI.text(g.panel_fg, g.font, mr.position + Vector2(16, 378 + my), "「%s」" % MERCHANT_LINES[maxi(0, g.merchant_idx - 1) % MERCHANT_LINES.size()], 13, Color(0.85, 0.87, 0.89))
	# 右上：货架 + 持有源石锭（明日方舟费用框）
	UI.text(g.panel_fg, g.font, Vector2(cx - 280, top - 18.0), "货架", 20, UI.TEXT)
	UI.en(g.panel_fg, g.font, Vector2(cx - 232, top - 20.0), "GOODS  ·  %d" % g.shop_items.size(), 12, UI.SUB, 3.0)
	var dp := Rect2(Vector2(cx + 460, top - 46.0), Vector2(128, 34))
	g.panel_fg.draw_rect(dp, Color(0.03, 0.035, 0.045, 0.86))
	g.panel_fg.draw_rect(Rect2(dp.position, Vector2(3, dp.size.y)), UI.GREEN)
	g.panel_fg.draw_texture_rect(g.tex.ingot, Rect2(dp.position + Vector2(12, 10), Vector2(18, 14)), false)
	UI.ctext(g.panel_fg, g.font, dp.position + Vector2(38, 27), str(g.ingots), 26, UI.TEXT)
	UI.text(g.panel_fg, g.font, dp.position + Vector2(84, 22), "源石锭", 10, UI.SUB)
	UI.text(g.panel_fg, g.font, Vector2(dp.position.x - 110, dp.position.y + 22), "持有", 12, Color(0.81, 0.84, 0.86), HORIZONTAL_ALIGNMENT_RIGHT, 100)
	# 按键提示：分两行放在按钮右边（再往右是底栏的技能图标，一行长字会压上去）
	var hints: Array = ["←→ 选择 · Ⓐ 购买", "Ⓨ 刷新 · Ⓑ 离开"] if Pad.using else (["点击卡片购买", "点「刷新货架」/「离开」"] if Pad.touch else ["点击或按 1–%d 购买" % g.shop_items.size(), "F 刷新  ·  ESC 离开"])
	var hfs := 12   # 桌面版（触屏在 draw_bg 开头已转去 _draw_bg_phone）
	UI.text(g.panel_fg, g.font, Vector2(cx + 116, top + CARD_H + 30.0), hints[0], hfs, UI.SUB)
	UI.text(g.panel_fg, g.font, Vector2(cx + 116, top + CARD_H + 49.0 if hfs > 12 else top + CARD_H + 47.0), hints[1], hfs, UI.SUB)
