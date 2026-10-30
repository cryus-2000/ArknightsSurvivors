extends RefCounted
## 界面 · 弹窗面板与选卡（state CHOICE）：弹窗框架（面板节点、布局、背景、标题、按钮）、升级 / 藏品 / 招募 / 事件的卡片绘制与入场动画、
## 事件插画与底栏。商店界面（screens/shop_screen.gd）也用这里的面板框架与按钮。界面层约定（docs/39 §3）。2026-09-26 从 game.gd 拆出。

const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
const A = preload("res://scripts/art.gd")
const Character = preload("res://scripts/characters/character.gd")
const Affects = preload("res://scripts/run/affects.gd")
const CardMotion = preload("res://scripts/screens/card_motion.gd")   # 各种面板的入场动效分派（docs/62 第一批）
const NodeIcons = preload("res://scripts/screens/node_icons.gd")   # 节点卡图标（docs/154）
const NodeCardsUI = preload("res://scripts/screens/node_cards_ui.gd")   # 翻节点卡卡面与演出（docs/154）
const UM = preload("res://scripts/ui_motion.gd")

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game
var _bb_cache := {}   # 干员待机帧并集区（界面立绘统一按脚底对齐用），按帧条名缓存
var motion: CardMotion          # 选卡 / 商人 / 事件面板的入场动效（按种类分派，screens/card_motion.gd）
var panel_band: ColorRect      # 选卡 / 商人 / 事件背后的灰阶压暗带（ui_band.gdshader）
var panel_sub_text := ""       # 面板标题下的一行说明（事件：剧情一句）
var ev_bars_h := 0.0           # 事件选项条的总高度（选项条按说明行数加高，提示文字跟在后面）
var serif: Font                # 事件标题用的衬线粗体（fonts/serif.ttf，缺失时退回 UI 字体）
## 事件（C 版式，原作「不期而遇」）：左边撕纸边灰阶墨色插画——画面里唯一的彩色物件是「不期而遇」节点图标（docs/154，原为海嗣祭坛）；
## 下方事件名（衬线粗体）+ 剧情一句；右边竖排选项条在 panel_col。插画的随机形状按事件名缓存
var ev_art := {}
var ink_tex: GradientTexture2D
## 事件插画（docs/156，Codex 母稿 art/archive/incoming_1028/event_cg_1026 离线缩成运行时用图）：按事件 id 打开面板时才 load，
## 换成别的面板 / 面板关掉就放掉引用（显存随之释放）。桌面读 art/event_cg/hi（1120×1000，2× 插画框），网页读 web（560×500）
var ev_cg: Texture2D = null
var ev_cg_key := ""
## 选卡卡片（A3，仿原作「选择支援」）：炭灰卡 + 左上节点标签条（英文分类 + 中文）+ 右上序号 + 图标光环 + 名称 + 说明 +
## 作用对象标签（影响当前编队里的哪些干员，run/affects.gd）+ 底部操作条。悬停 / 焦点：青色细边与外晕，标签条与操作条变青
const CARD_W := 272.0
const CARD_H := 382.0
const CARDS_TOP := 190.0       # 卡片顶边；标题从它上方 92 处开始，底边（572）不压到底栏的技能图标
## 手机（触屏，界面层放大后逻辑约 1044×481，手机端 UI 优化 r2）：卡片顶边 80（标题压在顶栏上，压暗带遮住），
## 卡片高按剩余高度算（≤ 382），不画底部提示；事件选项列顶边 70、左右各留 24
const CARDS_TOP_PHONE := 80.0
const EV_COL_TOP_PHONE := 70.0


## 手机横屏（Cfg.phone_ui）三选一整排卡片的缩放：卡片按原排版画，整排（panel_box）等比缩到 CARD_SCALE_PHONE；
## 图标、名字、说明、「影响」标签、选择条、卡间距一起按比例缩。标题 + 卡片整块在画面里上下居中。
## 10-26 用户 iPhone 实机「挤得太满」（Safari 横屏可视区约 2.18:1，长说明把卡撑到快顶满）：手机上卡片只写一句核心效果（brief()，
## 不再按最长说明加高），字从 24 号起、最小 19（× 0.9 ≈ 17 界面像素），整排放大到 0.9；完整说明点卡片右上「详情」再看（detail_i）。
## 「界面大小」照常生效（整层再乘）；平板 / 16:9 触屏 / 电脑不缩、照旧写完整说明
const CARD_SCALE_PHONE := 0.9
const BRIEF_SIZES_PHONE := [24, 23, 22, 21, 20, 19]
## 手机：正在看完整说明的那张卡（-1 = 没有）；点「详情」开 / 关，换一批卡、选中时清掉
var detail_i := -1
## 选中余光（10-26 用户「优化动效」：以前一选卡片就凭空消失）：选中那一刻记下这张卡的屏幕矩形，
## 面板照旧马上关、游戏马上继续，HUD 上在原位置画 PICK_GLOW 秒的「亮一下 → 青框外扩散开」。只有两三个矩形，手机 30 帧无负担
const PICK_GLOW := 0.3
var picked_r := Rect2()
var picked_t := -10.0
const HEADER_H := 80.0         # 标题块（英文小标 + 大标题 + 说明行）到卡片顶边的高度
## 三档布局参数（docs/126 C6）：下标 = Cfg.ui_form()（0 桌面 / 1 触屏 / 2 手机横屏）。正文只读 lay()，不再各自判断平台。
## touch：触屏版式（事件条横跨整屏、卡片紧凑排版、面板压暗带从顶到底）；phone：手机横屏（整排缩 card_scale、按说明加高、上下居中）；
## cards_top：卡片顶边；title_up：标题块在卡片顶边上方多少；ev_col_top：事件选项列顶边；ev_title_dy / ev_hint_fs：事件右侧标题下移、提示字号
const LAY := [
	{"touch": false, "phone": false, "card_scale": 1.0, "cards_top": CARDS_TOP, "title_up": 92.0, "ev_col_top": 196.0, "ev_title_dy": 0.0, "ev_hint_fs": 12},
	{"touch": true, "phone": false, "card_scale": 1.0, "cards_top": CARDS_TOP_PHONE, "title_up": 76.0, "ev_col_top": EV_COL_TOP_PHONE, "ev_title_dy": 12.0, "ev_hint_fs": 14},
	{"touch": true, "phone": true, "card_scale": CARD_SCALE_PHONE, "cards_top": CARDS_TOP_PHONE, "title_up": 76.0, "ev_col_top": EV_COL_TOP_PHONE, "ev_title_dy": 12.0, "ev_hint_fs": 14},
]


static var _re_op: RegEx

func lay() -> Dictionary:
	return LAY[Cfg.ui_form()]


## 手机横屏卡片内边距（用户 10-13「卡片和字体之间可以留点空隙」，设计像素，整排再缩 0.8）：
## 左右 PAD_X_PHONE 26（卡宽 272 的 9.6%，缩放后约 21 UI 像素；原 20）；名字基线 162、说明从 186 起（原 160 / 176，名字与说明间多留 10）；
## 「影响 / 特性」标签行中线在卡底上方 66（原 53，原来下沿贴着选择条）；选择条左右内缩 20、底边离卡底 16。
## 说明区 = 卡高 − DESC_PAD_PHONE：186 起，到标签行顶边（卡底上方约 77）再留 20
## 10-30 用户「字体不符合设计理念，重新设计字号和间距」：手机卡字号四级（实际像素，UI.fs 放大后）——
##   名字 24（唯一的最大字）> 选择 19 > 说明 17 > 标签 / 流派 14；说明固定行高（字体自身约 1.5 倍），不再为塞下或撑满改行距。
##   名字 / 说明各上移 2–4、说明区多 8（标签行与选择条不动）：17 号四行放得下
const PAD_X_PHONE := 26.0
const NAME_Y_PHONE := 160.0
const DESC_Y_PHONE := 182.0
const CHIP_UP_PHONE := 66.0
const DESC_PAD_PHONE := 275.0
const BTN_FS_PHONE := 16      # 选择（× phone_font_mult 1.18 ≈ 19）
const CHIP_FS_PHONE := 12     # 流派 / 影响标签（≈ 14）
const DESC_SIZES_PHONE := [20, 19, 18, 17, 16, 15]
## 手机招募卡的整段简介（10-30 用户「手机版本的字体需要缩小点」）：单独一档，不用一句话的 24–19；
## 写的是放大前的字号（UI.fs 乘 ui/phone_font_mult 1.18）：17 号，整组放不下降 15、再 14；行距固定（RECRUIT_GAPS_PHONE 只一档）
const RECRUIT_SIZES_PHONE := [14, 13, 12]
const RECRUIT_GAPS_PHONE := [0.0]
## 本次三选一的卡片高（未缩放的设计像素）：手机横屏按最长说明加高，0 = 用 card_h()
var row_h := 0.0
## 一排卡片按张数自适应宽度（用户 10-13 截图：5 选 1 藏品最右一张出框）。视口按 1280×720 拉伸（canvas_items + expand），
## 16:9 桌面逻辑宽恒为 1280，272 × 5 + 36 × 4 = 1504 放不下。可用宽 = 面板宽 − 两侧 ROW_MARGIN − 手机安全区（再除以手机 0.8 缩放），
## 放不下时依次：间距 36 → 最小 ROW_SEP_MIN；卡宽 272 → 最小 CARD_W_MIN；还放不下（6 张以上）整排再等比缩 row_k。3 / 4 张不变
const ROW_MARGIN := 32.0
const ROW_SEP := 36.0
const ROW_SEP_MIN := 16.0
const CARD_W_MIN := 220.0
var card_w := CARD_W           # 本次卡宽（设计像素）
var row_sep := ROW_SEP         # 本次卡间距（设计像素）
var row_k := 1.0               # 本次整排额外缩放（≤ 1）


func card_scale() -> float:
	return float(lay().card_scale)


## 按张数和可用宽度定 card_w / row_sep / row_k（n = 0：事件 / 商店，复位）
func fit_row(n: int) -> void:
	card_w = CARD_W
	row_sep = ROW_SEP
	row_k = 1.0
	if n <= 0:
		return
	var ins: Array = Cfg.safe_insets()
	var avail: float = (g.panel.size.x - float(ins[0]) - float(ins[2]) - 2.0 * ROW_MARGIN) / card_scale()
	var gaps := float(n - 1)
	if gaps > 0.0:
		row_sep = clampf((avail - n * CARD_W) / gaps, ROW_SEP_MIN, ROW_SEP)
	card_w = floorf(clampf((avail - gaps * row_sep) / n, CARD_W_MIN, CARD_W))
	row_k = minf(1.0, avail / (n * card_w + gaps * row_sep))


func cards_top() -> float:
	var L: Dictionary = lay()
	if L.phone and g.panel != null:
		# 标题块 + 缩小后的卡片整体上下居中，卡片顶边不早于原来的 80
		var block: float = HEADER_H + (row_h if row_h > 0.0 else card_h()) * CARD_SCALE_PHONE * row_k
		return maxf(CARDS_TOP_PHONE, round((g.panel.size.y - block) / 2.0) + HEADER_H)
	return float(L.cards_top)


func card_h() -> float:
	return minf(CARD_H, g.panel.size.y - CARDS_TOP_PHONE - 12.0) if lay().touch else CARD_H


func _init(game: Game) -> void:
	g = game
	motion = CardMotion.new(game)


## 卡片是否"被选中"：用手柄 / 方向键时看焦点，否则看鼠标悬停
func card_hot(card: Button, i: int) -> bool:
	if Pad.using or g.kb_nav:
		return i == g.nav_sel
	return card.is_hovered()


## 面板底部的按钮（商店：刷新 / 离开）：A 风格暗底细边；可带线性图标、源石锭价格、备注、按键牌。鼠标与触屏都能点
func button(text: String, r: Rect2, cb: Callable, enabled: bool, icon := "", note := "", price := -1, key := "") -> void:
	var b := Button.new()
	b.set_meta("shopbtn", true)
	# 触屏：控件上下各扩 20、左右各扩 6 当点击区（40 高 → 80），图形仍画在原来的 r 里
	var pad := Vector2(6, 20) if Pad.touch_ui() else Vector2.ZERO
	b.position = r.position - pad
	b.size = r.size + pad * 2.0
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not enabled
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(st, empty)
	b.draw.connect(func():
		var hov: bool = b.is_hovered() and enabled
		var br := Rect2(pad, r.size)
		var fg: Color = UI.TEXT if enabled else UI.SUB
		b.draw_rect(br, Color(0.03, 0.035, 0.045, 0.82))
		b.draw_rect(br, Color(1, 1, 1, 0.6 if hov else (0.3 if enabled else 0.12)), false, 1.0)
		if hov:
			b.draw_rect(br.grow(2.0), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.35), false, 1.0)
		var x := pad.x + 16.0
		if icon != "":
			UI.icon(b, icon, Vector2(x + 9, b.size.y / 2.0), 18.0, fg)
			x += 26.0
		UI.text(b, g.font, Vector2(x, b.size.y / 2.0 + 5), text, 14, fg)
		x += g.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.fs(14)).x + 10.0
		if price >= 0:
			b.draw_texture_rect(g.tex.ingot, Rect2(Vector2(x, b.size.y / 2.0 - 7), Vector2(18, 14)), false, Color(1, 1, 1, 1.0 if enabled else 0.5))
			UI.ctext(b, g.font, Vector2(x + 22, b.size.y / 2.0 + 7), str(price), 18, fg)
			x += 22.0 + UI.cwidth(g.font, str(price), 18) + 8.0
		if note != "":
			UI.text(b, g.font, Vector2(x, b.size.y / 2.0 + 5), note, 11, UI.SUB)
		if key != "" and not Pad.touch_ui():
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
	_warm_band(parent, sm.shader)
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
	var L: Dictionary = lay()
	g.panel_col.offset_top = float(L.ev_col_top)   # 手机：选项列顶边 70（见 CARDS_TOP_PHONE 注释）
	g.panel_col.offset_bottom = 560
	if L.touch:
		# 手机：选项条横跨整屏（左右各留 24），条间距 10
		g.panel_col.anchor_left = 0.0
		g.panel_col.anchor_right = 1.0
		g.panel_col.offset_left = 24
		g.panel_col.offset_right = -24
		g.panel_col.add_theme_constant_override("separation", 10)
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


## 压暗带着色器预热（10-22 网页开局掉帧：第一次升级弹出选卡时当帧编译这支读屏着色器 + 拷屏，网页上卡约 200 ms）：
## 进局后在界面层左上角放一个 1×1 的同款材质，参数设成原样输出（不去色、不压暗、无渐隐），渲染约 0.2 秒后删掉——
## 着色器在进局时就编译好，那个像素输出的就是它底下原来的颜色，画面不变。不能中途读屏的设备（Cfg.screen_copy_ok）不做
func _warm_band(parent: Node, shader: Shader) -> void:
	if g.demo_op != "" or not Cfg.screen_copy_ok() or DisplayServer.get_name() == "headless":
		return
	var w := ColorRect.new()
	var wm := ShaderMaterial.new()
	wm.shader = shader
	wm.set_shader_parameter("desat", 0.0)
	wm.set_shader_parameter("dim", 1.0)
	wm.set_shader_parameter("fade_px", 0.0)
	wm.set_shader_parameter("rect_size", Vector2.ONE)
	w.material = wm
	w.mouse_filter = Control.MOUSE_FILTER_IGNORE
	w.position = Vector2.ZERO
	w.size = Vector2.ONE
	parent.add_child(w)
	g.get_tree().create_timer(0.2, true, false, true).timeout.connect(w.queue_free)


## 压暗带与卡片容器的布局：选卡在顶栏与底栏之间；商人压暗到底部；事件整屏灰阶（C 版式）
func layout(kind: String) -> void:
	var vs: Vector2 = g.panel.size   # 触屏界面层放大后 = UI 逻辑尺寸（桌面就是视口尺寸）
	var sm: ShaderMaterial = panel_band.material
	var top := 64.0
	var bot := vs.y - 108.0
	var fade := 34.0
	var desat := 0.85
	var dim := 0.5
	if kind == "shop":
		bot = vs.y - 56.0
	elif kind == "cross":
		desat = 0.6   # 翻节点卡（docs/154）：压暗但保留战场氛围
		dim = 0.42
	elif kind == "event":
		top = 0.0
		bot = vs.y
		fade = 0.0
		desat = 1.0
		dim = 0.46
	if lay().touch:
		# 手机：面板标题压在顶栏上（逻辑高只有约 481），压暗带从顶到底，顶栏一起变灰变暗
		top = 0.0
		bot = vs.y
		fade = 0.0
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
		g.panel_box.offset_top = cards_top()
	# 手机横屏三选一：整排卡片以顶边中点为轴等比缩小（商店 / 事件不缩）
	var sc: float = card_scale() * row_k if kind != "shop" and kind != "event" else 1.0
	g.panel_box.scale = Vector2(sc, sc)
	g.panel_box.pivot_offset = Vector2(vs.x / 2.0, 0.0)
	if kind != "shop" and kind != "event":
		# 缩放前整排比面板宽（手机 5 张：设计宽 1224 > 界面宽 1044）时，HBox 会从左锚点往右撑开、缩放轴心就偏了：
		# 按整排实际宽度左右对称撑开，轴心放在整排中点
		var n: int = g.choices.size()
		var bw: float = maxf(vs.x, n * card_w + maxf(0.0, n - 1.0) * row_sep)
		g.panel_box.offset_left = (vs.x - bw) / 2.0
		g.panel_box.offset_right = (bw - vs.x) / 2.0
		g.panel_box.pivot_offset = Vector2(bw / 2.0, 0.0)
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
			var en_label := "RELIC" if g.choice_kind == "relic" else ("NODE" if g.choice_kind == "cross" else ("SQUAD SWAP" if g.choice_kind == "swap" else ("GROWTH PATH" if g.choice_kind == "branch" else "LEVEL UP")))
			if g.choices.size() > 0 and g.choices.all(func(o): return o.get("kind", "") == "recruit"):
				en_label = "RECRUIT"
			var L: Dictionary = lay()
			var ph: bool = L.touch
			# 手机：标题整体下移 4（英文小标原来基线 12，顶边贴着画面上沿被切掉一截）；顶栏中央的计时器在选卡时不画（hud.panel_over_top）
			header(vs, en_label + "  ·  CHOOSE ONE", g.panel_title_text, panel_sub_text, cards_top() - float(L.title_up))
			if not ph:   # 手机：卡片顶到底，没有提示行的位置（点卡片本身就是操作）
				var hint := "←→ 选择 · Ⓐ 确认" if Pad.using else ("点击卡片选择" if Pad.touch else "点击卡片，或按 1–%d 选择" % g.choices.size())
				if g.choice_kind == "cross":
					hint = "←→ 选择 · Ⓐ 翻开" if Pad.using else ("点击卡片翻开" if Pad.touch else "点击卡片翻开，或按 1–%d" % g.choices.size())
				UI.text(g.panel_fg, g.font, Vector2(0, CARDS_TOP + CARD_H * row_k + 26), hint, 12, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
			motion.draw_under(g.panel_fg)   # 藏品光柱（压暗带之上、卡片之下）
			if g.choice_kind == "cross":
				var inv: Transform2D = g.panel_fg.get_global_transform().affine_inverse()
				var rects: Array = []
				for cd in g.panel_box.get_children():
					if cd is Button:
						rects.append(inv * (cd as Control).get_global_rect())
				NodeCardsUI.draw_bg(g.panel_fg, vs, rects, g.endg.flipped, UM.now(), cards_top())
				# 卡外结局名：只给悬停 / 选中且真带路线的那张；切卡淡入淡出；翻开后消失。电脑压在操作说明下面，手机贴卡底、不出画面
				var bi := 0
				for cd in g.panel_box.get_children():
					if not (cd is Button) or bi >= rects.size() or bi >= g.choices.size():
						continue
					var nc: Dictionary = g.choices[bi].get("node", {})
					var ne: Array = (nc.get("ends", []) as Array).filter(func(e): return Cfg.endings_cleared.has(e))
					var on: bool = g.endg.flipped < 0 and not ne.is_empty() and card_hot(cd as Button, bi)
					var al: float = _ease_meta(cd, "names_a", 1.0 if on else 0.0, 0.16)
					var y_min: float = (CARDS_TOP + CARD_H * row_k + 34.0) if not lay().touch else 0.0
					NodeCardsUI.draw_route_names(g.panel_fg, rects[bi], ne, al, g.font, y_min, vs.y - 6.0, 16 if lay().touch else 14)
					bi += 1


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


var ev_shown_t := 0.0   # 事件面板这一屏弹出的界面时刻（check_event_panel 防抖）


## 事件面板兜底（10-29 用户卡死：标题和叙述在、选项一条都没有）：弹出 0.6 秒后选项列不可见或没有可见的选项条，
## 交给 endings.recover_panel 重建成「离开」一屏。每帧画事件底时查（draw_event_bg）；now = true 时立即查（测试用）
func check_event_panel(now := false) -> bool:
	if g.state != Game.S.CHOICE or g.choice_kind != "event" or not g.panel.visible:
		return true
	var ok: bool = g.panel_col.visible and g.panel_col.get_children().any(func(c): return c is Control and c.visible and not c.is_queued_for_deletion())
	if ok or (not now and UM.now() - ev_shown_t < 0.6):
		return ok
	ev_shown_t = UM.now()
	if now:
		g.endg.recover_panel()
	else:
		g.endg.recover_panel.call_deferred()
	return false


func draw_event_bg(vs: Vector2) -> void:
	check_event_panel()
	if lay().touch:
		_draw_event_bg_phone(vs)
		return
	var art := event_art(g.panel_title_text)
	var cx := vs.x / 2.0
	var p0 := Vector2(cx - 576.0, 120.0)
	var pts: PackedVector2Array = art.panel
	var tp := PackedVector2Array()
	var uv := PackedVector2Array()
	for q in pts:
		tp.append(p0 + q)
		uv.append(Vector2(clampf(q.x / 560.0, 0.0, 1.0), clampf(q.y / 500.0, 0.0, 1.0)))
	var cg := event_cg()
	if cg != null:
		UI.fill_poly(g.panel_fg, tp, Color.WHITE, uv, cg)
	else:
		_draw_ink_art(art, p0, tp)
	# 底部压暗，放事件名与剧情
	_event_caption(art, p0)


## 没有插画时的墨色底：灰阶渐变 + 墨点笔触 + 彩色节点图标（C 版式）
func _draw_ink_art(art: Dictionary, p0: Vector2, tp: PackedVector2Array) -> void:
	var uv := PackedVector2Array()
	for q in art.panel:
		uv.append(Vector2(clampf(q.x / 560.0, 0.0, 1.0), clampf(q.y / 500.0, 0.0, 1.0)))
	UI.fill_poly(g.panel_fg, tp, Color.WHITE, uv, ink_grad())
	for b in art.blobs:
		UI.fill_poly(g.panel_fg, offset_poly(b, p0, tp), Color(0.047, 0.047, 0.05, 0.5))
	for s in art.streaks:
		UI.fill_poly(g.panel_fg, offset_poly(s, p0, tp), Color(0.08, 0.08, 0.085, 0.35))
	for d in art.dots:
		g.panel_fg.draw_circle(p0 + d[0], d[1], Color(0.047, 0.047, 0.05, 0.55))
	# 蓝色微光 + 节点图标（彩色；安全屋用休整图标，其余是「不期而遇」）
	var ac := p0 + Vector2(280, 158)
	for k in 5:
		g.panel_fg.draw_circle(ac, 120.0 - k * 20.0, Color(0.18, 0.72, 1.0, 0.05))
	var nk := event_node_kind()
	NodeIcons.draw(g.panel_fg, nk, ac + Vector2(0, roundf(2.0 * sin(g.t * 2.0))), 8.0, NodeIcons.COLS[nk])


## 插画框底部压暗带 + 事件名 / 剧情 + 右侧「选择一项」标题与提示
func _event_caption(art: Dictionary, p0: Vector2) -> void:
	var vs := g.panel_fg.size
	var cx := vs.x / 2.0
	var g0 := Color(0.04, 0.04, 0.043, 0.0)
	var g1 := Color(0.04, 0.04, 0.043, 0.95)
	g.panel_fg.draw_polygon(PackedVector2Array([p0 + Vector2(6, 300), p0 + Vector2(554, 300), p0 + Vector2(554, 492), p0 + Vector2(6, 492)]), PackedColorArray([g0, g0, g1, g1]))
	var ew0 := UI.en(g.panel_fg, g.font, p0 + Vector2(92, 366), "EVENT", 12, Color(0.6, 0.59, 0.56), 3.0)
	UI.text(g.panel_fg, g.font, p0 + Vector2(92 + ew0 + 6, 366), "·  " + NodeIcons.NAMES[event_node_kind()], 12, Color(0.6, 0.59, 0.56))
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
	var col_top: float = g.panel_col.offset_top   # 触屏 150 / 桌面 196，标题跟着上移
	var L: Dictionary = lay()
	var tt: float = float(L.ev_title_dy)   # 触屏标题再贴近选项列 12，不压到顶栏的威胁等级行
	UI.en(g.panel_fg, g.font, Vector2(cx + 20, col_top - 54.0 + tt), "EVENT  ·  CHOOSE ONE", 12, Color(0.6, 0.59, 0.56), 4.0)
	g.panel_fg.draw_string(serif, Vector2(cx + 20, col_top - 18.0 + tt), "选择一项", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.925, 0.91, 0.882))
	var hint := "←→ 选择 · Ⓐ 确认" if Pad.using else ("点击选项" if Pad.touch else "点击选项，或按 1–%d" % g.choices.size())
	UI.text(g.panel_fg, g.font, Vector2(cx + 20, col_top + ev_bars_h + 6), hint, int(L.ev_hint_fs), Color(0.55, 0.54, 0.52))


## 手机版事件背景（手机端 UI 优化 r2）：逻辑高只有约 481，左侧 560×500 的插画放不下——顶部一行放节点小图标 + 事件名（衬线）+
## 剧情一句（限宽缩字），选项条横跨整屏（panel_col 见 build）；底部提示在选项列下方
func _draw_event_bg_phone(vs: Vector2) -> void:
	var x0 := 28.0
	var nk := event_node_kind()
	var cg := event_cg()
	if cg != null:
		# 有插画：压暗铺满整屏当底（选项条横跨整屏，插画放不下左栏），左上再放一张小图
		var ts := Vector2(cg.get_size())
		var sz: Vector2 = ts * maxf(vs.x / ts.x, vs.y / ts.y)
		g.panel_fg.draw_texture_rect(cg, Rect2(((vs - sz) / 2.0).round(), sz.round()), false, Color(0.36, 0.36, 0.38))
		g.panel_fg.draw_texture_rect(cg, Rect2(x0, 6.0, 62.0, 55.0), false)
		g.panel_fg.draw_rect(Rect2(x0, 6.0, 62.0, 55.0), Color(0.6, 0.85, 1.0, 0.6), false, 1.0)
		x0 += 76.0
	else:
		for k in 3:
			g.panel_fg.draw_circle(Vector2(x0 + 24.0, 32.0), 40.0 - k * 10.0, Color(0.18, 0.72, 1.0, 0.05))
		NodeIcons.draw(g.panel_fg, nk, Vector2(x0 + 24.0, 32.0), 3.0, NodeIcons.COLS[nk])
		x0 += 62.0
	var ew0 := UI.en(g.panel_fg, g.font, Vector2(x0, 22), "EVENT", 11, Color(0.6, 0.59, 0.56), 3.0)
	UI.text(g.panel_fg, g.font, Vector2(x0 + ew0 + 6, 22), "·  %s  ·  选择一项" % NodeIcons.NAMES[nk], 11, Color(0.6, 0.59, 0.56))
	g.panel_fg.draw_string(serif, Vector2(x0, 52), g.panel_title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
	var tw := serif.get_string_size(g.panel_title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	if panel_sub_text != "":
		UI.text_fit(g.panel_fg, g.font, Vector2(x0 + tw + 18, 50), UI.soft(panel_sub_text), 15, Color(0.81, 0.79, 0.76), vs.x - x0 - tw - 46.0, 12)
	var hint := "←→ 选择 · Ⓐ 确认" if Pad.using else ("点击选项" if Pad.touch else "点击选项，或按 1–%d" % g.choices.size())
	UI.text(g.panel_fg, g.font, Vector2(24, g.panel_col.offset_top + ev_bars_h + 6), hint, 14, Color(0.55, 0.54, 0.52))


## 当前事件的插画（没有对应图返回 null，退回墨色底 + 节点图标）
func event_cg() -> Texture2D:
	var key: String = g.endg.cg_key() if g.endg != null else ""
	if key != ev_cg_key:
		ev_cg_key = key
		ev_cg = null
		var path := "res://art/event_cg/%s/%s.webp" % ["web" if OS.has_feature("web") else "hi", key]
		if key != "" and ResourceLoader.exists(path):
			ev_cg = load(path)
	return ev_cg


func release_event_cg() -> void:
	ev_cg = null
	ev_cg_key = ""


## 事件插画里的节点图标：安全屋是「安全的角落」，其余都是「不期而遇」
func event_node_kind() -> String:
	return "rest" if g.endg != null and g.endg.opened_id == "rest" else "incident"


## 墨点 / 笔触多边形平移到插画框里；超出框的部分交给撕纸边外的暗底盖住（这里只做平移）
func offset_poly(p: PackedVector2Array, o: Vector2, _clip: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in p:
		out.append(o + Vector2(clampf(q.x, 2.0, 558.0), clampf(q.y, 2.0, 498.0)))
	return out


## quiet：不播升级音效（「更换队友」画面进出，progression.open_swap / cancel_swap）
func show_choices(title: String, opts: Array, kind: String, sub := "", quiet := false) -> void:
	g.choices = opts
	g.choice_kind = kind
	if kind == "event":
		ev_shown_t = UM.now()
	g.nav_sel = 0
	if kind != "event":
		release_event_cg()
	g.state = Game.S.CHOICE
	g.panel_title_text = title
	panel_sub_text = sub
	if sub == "":
		if kind == "relic":
			panel_sub_text = "从发现的藏品中挑选一件带走"
		elif opts.size() > 0 and opts.all(func(o): return o.get("kind", "") == "recruit"):
			panel_sub_text = "挑选一名干员加入编队"   # 纯招募；升级界面混一张招募卡仍写「选择一项强化」
		elif kind != "event":
			panel_sub_text = "选择一项强化"
		# 入队加成（docs/83）：用户 10-13 定不再逐张写在招募卡上，三选一里有招募卡时在标题说明行写一次（数字读 balance.json squad 段；
		# 台阶已封顶不再加成时不写）。混有单张招募卡的升级界面也写在这里：带实际数字、不占卡片空间，比给卡片加角标更清楚
		if kind != "event" and opts.any(func(o): return o.get("kind", "") == "recruit" and not o.get("swap", false)):   # 满员换人卡不加台阶
			var jb: String = g.squad.join_bonus_text()
			if jb != "":
				panel_sub_text += " · " + jb
	if not quiet:
		Sfx.play("relic" if kind == "relic" else "levelup", -2.0, 1.0, 0.0)
	for c in g.panel_box.get_children():
		c.queue_free()
	for c in g.panel_col.get_children():
		c.queue_free()
	row_h = 0.0
	fit_row(0 if kind == "event" else opts.size())
	g.panel_box.add_theme_constant_override("separation", int(row_sep))   # 商店会改间距，这里每次按本次张数重设
	var L: Dictionary = lay()
	detail_i = -1
	for a in Cfg.dev_args():   # --carddetail=<n>（截图验收）：打开时直接展开第 n 张卡的详情
		if a.begins_with("--carddetail="):
			detail_i = int(a.substr(13))
	var briefs: bool = L.phone and kind != "event" and kind != "cross"   # 手机：卡上只写一句核心效果
	var row_cards: bool = kind != "event" and kind != "cross"
	if L.phone and kind != "event":
		# 手机横屏：卡高固定（不再按最长说明加高，10-26 实机挤满），只是缩放后整块放不下时按画面高收一点
		var max_h: float = (g.panel.size.y - HEADER_H - 12.0) / (CARD_SCALE_PHONE * row_k)
		row_h = minf(card_h(), maxf(DESC_PAD_PHONE + 90.0, max_h))
	layout(kind)
	motion.start(kind, opts)
	var ev := kind == "event"
	ev_bars_h = 0.0
	# 触屏事件条：说明字号在 17 → 13 里取「全部选项条加起来放得进屏幕」的最大一档（桌面 13 → 12 不变）
	var ev_sizes: Array = [13, 12]
	# 手机事件条：横跨整屏（宽 = 面板宽 − 48），本体 74 高、说明一行起；说明字号在 19 → 14 里取全部选项条放得下的最大档
	var ph: bool = ev and L.touch
	var ev_w: float = (g.panel.size.x - 48.0) if ph else 596.0
	var ev_dw: float = (ev_w - 100.0 - 70.0) if ph else 420.0
	var ev_h0: float = 74.0 if ph else 100.0
	var ev_base_lines: int = 1 if ph else 2
	if ph:
		var avail: float = g.panel.size.y - float(g.panel_col.offset_top) - 24.0
		for s in [19, 18, 17, 16, 15, 14]:
			var tot := -10.0
			for o in opts:
				var fe0 := UI.fit(g.font, option_description(o), ev_dw, 4.0 * g.font.get_height(UI.fs(s)), [s])
				tot += ev_h0 + maxf(0.0, fe0.lines.size() - 1) * float(fe0.lh) + 10.0
			ev_sizes = [s]
			if tot <= avail:
				break
	for i in opts.size():
		var o: Dictionary = opts[i]
		var display_desc := option_description(o)
		var card := Button.new()
		card.set_meta("full_desc", display_desc)
		if str(o.get("full", o.get("desc", ""))) != str(o.get("desc", "")):
			# 卡面只写本编队相关的部分（relic_fx.squad_desc，10-28）：完整规则进悬停 / 详情
			var of := o.duplicate()
			of.desc = o.full
			card.set_meta("full_desc", option_description(of))
			card.set_meta("squad_cut", true)
			card.set_meta("face_desc", display_desc)   # 统一紧凑版式重排时用卡面这段，不用完整规则
		if briefs or (row_cards and is_op_card(o)):
			# 一句话（手机全部卡；电脑 / 平板只有干员卡，10-26 用户「干员相关卡别再细说技能」）。完整说明：手机 / 平板点「详情」，电脑悬停
			var hl := headline(o)
			var bf := hl if hl != "" else brief(display_desc)
			card.set_meta("brief", bf)
			card.set_meta("more", bf != display_desc.strip_edges() or card.has_meta("squad_cut"))
			display_desc = bf
		card.custom_minimum_size = Vector2(ev_w, ev_h0) if ev else Vector2(card_w, row_h if row_h > 0.0 else card_h())
		if L.touch:
			card.set_meta("phone", true)
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
		card.draw.connect((draw_event_bar if ev else (draw_node_card if kind == "cross" else draw_card)).bind(card, o, i))
		card.mouse_entered.connect(func(): Sfx.play("ui_move", -6.0); card.queue_redraw())
		card.mouse_exited.connect(card.queue_redraw)
		if L.touch:
			# 点「详情」看完整说明，点别处照常选；more 在下面排版后才定（手机招募卡缩到 15 还放不下才给详情），按下时再看
			card.pressed.connect(func(): _phone_press(card, i) if card.get_meta("more", false) else g.progression.pick(i))
		else:
			card.pressed.connect(g.progression.pick.bind(i))
		# 说明文字：创建时按宽度排好版（放不下先缩字号）。选卡卡片三行还放不下就切紧凑布局——
		# 图标缩小、名字上移，把位置让给说明；事件选项条则按行数加高
		if ev:
			var fe := UI.fit(g.font, display_desc, ev_dw, 4.0 * g.font.get_height(UI.fs(13 if not ph else int(ev_sizes[0]))), ev_sizes)
			card.set_meta("fit", fe)
			card.custom_minimum_size.y = ev_h0 + maxf(0.0, fe.lines.size() - ev_base_lines) * float(fe.lh)
			ev_bars_h += card.custom_minimum_size.y + (10.0 if ph else 14.0)
		else:
			# 触屏说明字先试大 2 号，放不下再退回原字号（紧凑布局同理）
			var f0 := UI.fit(g.font, display_desc, card_w - 40.0, 60.0, [15, 14, 13, 12] if Pad.touch_ui() else [13, 12])
			var compact: bool = not f0.fit
			if L.touch:
				# 手机：说明字比图标要紧——一律紧凑布局（图标 64 在 84、名字 160、说明 176 起到标签行上方），字 20 起、最小 15
				compact = true
				if row_h > 0.0:
					var dh := row_h - DESC_PAD_PHONE
					var dw := card_w - 2.0 * PAD_X_PHONE
					if o.kind == "recruit":
						# 招募卡整段简介：先按这张自己排（下面整组统一字号 / 行距时重排，_even_recruit_phone）
						f0 = _recruit_fit(display_desc, dw, dh)
						card.set_meta("intro_box", [display_desc, dw, dh])
					else:
						f0 = UI.fit(g.font, display_desc, dw, dh, BRIEF_SIZES_PHONE if briefs else DESC_SIZES_PHONE)
					card.set_meta("roomy", true)
					if not f0.fit:
						card.set_meta("more", true)   # 缩到 15 还放不下：给「详情」键，点开看全文
				else:
					f0 = UI.fit(g.font, display_desc, card_w - 40.0, card_h() - 176.0 - 53.0 - 4.0, [20, 19, 18, 17, 16, 15])
			elif compact:
				f0 = UI.fit(g.font, display_desc, card_w - 40.0, 108.0, [15, 14, 13, 12, 11] if Pad.touch_ui() else [13, 12, 11])
			card.set_meta("fit", f0)
			card.set_meta("compact", compact)
			# 作用对象标签（影响编队里的哪些干员）；一行放不下会收成「+N」，悬停提示里列全
			var chips: Array = [] if kind == "cross" else Affects.chips(g, o)
			if o.kind == "recruit" and not o.get("swap", false):
				var nl: int = g.progression.affinity.recruit_link_count(str(o.id))
				if nl > 0:
					chips = [["联动 %d" % nl, UI.GOLD]] + chips   # 和已持有藏品 / 在队干员的联动，详情在悬停提示
					card.set_meta("links", g.progression.affinity.recruit_lines(str(o.id)))
			card.set_meta("affects", chips)
			card.set_meta("chips_cut", not UI.chip_fits(g.font, chips, card_w - (2.0 * PAD_X_PHONE if row_h > 0.0 else 32.0)))
		(g.panel_col if ev else g.panel_box).add_child(card)
	# 同一组卡统一版式（10-23 用户：三张招募卡并排时小人同高）：有一张要紧凑，全组都用紧凑，图标 / 脚底在同一高度
	if not ev and not L.touch:
		var cards: Array = g.panel_box.get_children().filter(func(c): return c is Button and c.has_meta("compact"))
		if cards.any(func(c): return c.get_meta("compact")):
			for c in cards:
				if not c.get_meta("compact"):
					c.set_meta("compact", true)
					c.set_meta("fit", UI.fit(g.font, c.get_meta("face_desc", c.get_meta("full_desc", "")), card_w - 40.0, 108.0, [15, 14, 13, 12, 11] if Pad.touch_ui() else [13, 12, 11]))
	if not ev and L.touch:
		_even_recruit_phone()
	g.panel.visible = true
	g.panel_fg.queue_redraw()


## 手机招募卡的整段简介（10-30 用户写定，最长 40 字）：从大到小试 RECRUIT_SIZES_PHONE，others（同屏各卡）全部放得下就用这一档。
## 都放不下返回最小一档的排版（截断，调用方给「详情」）
func _recruit_fit(text: String, dw: float, dh: float, others: Array = []) -> Dictionary:
	var last := {}
	for sz in RECRUIT_SIZES_PHONE:
		for gp in RECRUIT_GAPS_PHONE:
			last = UI.fit(g.font, text, dw, dh, [sz], gp)
			if last.fit and others.all(func(b): return UI.fit(g.font, str(b[0]), float(b[1]), float(b[2]), [sz], gp).fit):
				return last
	return last


## 同一屏的手机招募卡用同一字号（并排时说明不一会儿大一会儿小）：取全组都放得下的最大一档
func _even_recruit_phone() -> void:
	var cards: Array = g.panel_box.get_children().filter(func(c): return c is Button and c.has_meta("intro_box"))
	if cards.size() < 2:
		return
	var boxes: Array = cards.map(func(c): return c.get_meta("intro_box"))
	for c in cards:
		var b: Array = c.get_meta("intro_box")
		var f := _recruit_fit(str(b[0]), float(b[1]), float(b[2]), boxes)
		c.set_meta("fit", f)
		c.set_meta("more", c.get_meta("more", false) or not f.fit)


## 手机卡片上的一句核心效果：说明第一行的第一句（到「；」「。」为止），去掉括号里的补充说明；还长于 BRIEF_MAX 字
## 就在冒号 / 逗号处取一个完整的前半句（brief_whole）。招募卡第一句是干员概述，特性看标签行
const BRIEF_MAX := 24
static var _re_paren: RegEx

static func brief(desc: String) -> String:
	if _re_paren == null:
		_re_paren = RegEx.create_from_string("（[^）]*）|\\([^)]*\\)")
		_re_digit = RegEx.create_from_string("[0-9]")
		_re_numparen = RegEx.create_from_string("（([^）]*[0-9][^）]*)）")
	var raw: String = desc.strip_edges().split("\n")[0]
	var sent: String = _re_paren.sub(raw, "", true)
	for sep in ["；", "。"]:
		var k := sent.find(sep)
		if k > 0:
			sent = sent.substr(0, k)
	sent = sent.strip_edges()
	# 括号外没有数字、数值全在括号里（「…再落第三波（40% 伤害）」）：留括号里第一个带数字的短语，别把数值整个丢掉
	if _re_digit.search(sent) == null:
		# 只在第一句（括号外第一个「；」/「。」之前）里找：10-28 乌尔比安的一句话拼进了后半句「（最多 10 层）」
		var depth := 0
		var end := raw.length()
		for ci in raw.length():
			var chr := raw[ci]
			if chr == "（" or chr == "(":
				depth += 1
			elif chr == "）" or chr == ")":
				depth = maxi(0, depth - 1)
			elif depth == 0 and (chr == "；" or chr == "。"):
				end = ci
				break
		var m := _re_numparen.search(raw.substr(0, end))
		if m != null:
			for piece in m.get_string(1).split("，"):
				var pc: String = piece.get_slice("；", 0).strip_edges()
				if _re_digit.search(pc) != null:
					sent += "（%s）" % pc
					break
	if sent.length() <= BRIEF_MAX:
		return sent
	# 整句太长：在冒号 / 逗号处找一个完整的前半句——不以「每秒 / 期间 / 的」这类半截词结尾，原句有数字时前半句也要有数字
	# （10-26：水月「病理性依恋·缠缚」以前切成「「囚徒困境」期间每秒」）。都不行就整句（字号由 fit 往下缩）
	var has_num := _re_digit.search(sent) != null
	for sep in ["：", "，"]:
		var k := sent.find(sep)
		while k >= 4:
			var head := sent.substr(0, k).strip_edges()
			if head.length() > BRIEF_MAX + 8:
				break
			if brief_whole(head) and (not has_num or _re_digit.search(head) != null):
				return head
			k = sent.find(sep, k + 1)
	return sent


## 一句话是不是完整的：不以半截词结尾（card_desc 回归同一规则）
const BRIEF_WEAK_TAIL := ["每秒", "期间", "的", "时", "中", "内", "与", "和", "并", "对", "在", "被", "将", "使", "及", "或", "把", "向", "从", "为", "让", "且"]
static var _re_digit: RegEx
static var _re_numparen: RegEx


static func brief_whole(t: String) -> bool:
	t = t.strip_edges()
	if t.length() < 4:
		return false
	for w in BRIEF_WEAK_TAIL:
		if t.ends_with(w):
			return false
	return true


## 记下选中卡的屏幕矩形（progression.pick 调用；事件选项条、翻节点卡同样适用）
func mark_pick(i: int) -> void:
	var box: BoxContainer = g.panel_col if g.choice_kind == "event" else g.panel_box
	if i < 0 or i >= box.get_child_count() or UM.rm():
		return
	var c := box.get_child(i) as Control
	picked_r = c.get_global_rect()
	picked_t = UM.now()


## 选中余光：前 1/3 整卡一层白光淡出，青框从卡边外扩 18 px 并淡出（画在 HUD 最上层的 front 块里）
func draw_pick_glow(ci: CanvasItem) -> void:
	var e := (UM.now() - picked_t) / PICK_GLOW
	if e < 0.0 or e >= 1.0:
		return
	var r := picked_r
	r.position -= (ci as Control).get_global_rect().position
	var k := 1.0 - e
	if e < 0.33:
		ci.draw_rect(r, Color(1, 1, 1, 0.28 * (1.0 - e / 0.33)))
	var gr := r.grow(4.0 + 18.0 * UI.ease_out(e))
	ci.draw_rect(gr, Color(UI.CYAN, 0.9 * k), false, 2.0)
	ci.draw_rect(gr.grow(3.0), Color(UI.CYAN, 0.25 * k), false, 3.0)


## 干员相关卡（招募 / 干员培养 / 精英化 / 技能进阶）
static func is_op_card(o: Dictionary) -> bool:
	var k: String = str(o.get("kind", ""))
	return k == "recruit" or k == "prog" or (k == "growth" and o.has("op"))


## 干员卡的一句话（10-26 用户：只写「解锁二技能 · <原作技能名>」这样一句）：精英化卡 = 这一阶解锁的技能（精一二技能、精二三技能）；
## 招募卡去掉讲技能的后半句；其余返回空，由 brief() 取说明第一句
const CN_NUM := ["一", "二", "三", "四"]


func headline(o: Dictionary) -> String:
	if str(o.get("kind", "")) == "recruit":
		# 招募卡写的是干员简介（gallery.intro，用户 10-30 逐条写定）：整段照写，不截第一句、不去括号，换行保留
		return option_description(o).strip_edges()
	if str(o.get("kind", "")) != "prog" or int(o.get("elite", 0)) <= 0 or o.get("branch", false):
		return ""
	var op = g.squad.get_op(str(o.get("op", ""))) if g.squad != null else null
	if op == null:
		return ""
	var lv: int = int(o.elite)
	var sk: Dictionary = op.skill_def(lv)
	var nm: String = str(sk.get("name", ""))
	if nm == "" or lv >= CN_NUM.size():
		return ""
	return "解锁%s技能 · %s" % [CN_NUM[lv], nm]


## 手机卡片点击：点在右上「详情」上 = 开 / 关这张卡的完整说明；点在别处 = 选这张（详情开着时也照常选）
func _phone_press(card: Button, i: int) -> void:
	if detail_tap(card, i):
		return
	detail_i = -1
	g.progression.pick(i)


## 手机卡片（选卡 / 商店）：这次点击落在「详情」键上（触控区比画出来的大一圈）就开 / 关完整说明并返回 true
func detail_tap(card: Button, i: int) -> bool:
	var dr: Rect2 = card.get_meta("detail_r", Rect2())
	if card.get_meta("more", false) and dr.has_area() and dr.grow(10.0).has_point(card.get_local_mouse_position()):
		detail_i = -1 if detail_i == i else i
		Sfx.play("ui_move", -6.0)
		g.panel_tip.queue_redraw()
		return true
	return false


## 手机卡片右上的「详情」键（开着时青底、箭头朝下）；small = 商店窄卡用小一号
func draw_detail_chip(card: Button, r: Rect2, i: int, small := false) -> void:
	var on: bool = detail_i == i
	var fs := 15 if small else 17
	var dw := UI.cwidth(g.font, "详情", fs) + (28.0 if small else 34.0)
	var dh := 28.0 if small else 32.0
	var dr := Rect2(r.position + Vector2(r.size.x - dw - (6.0 if small else 10.0), 6.0 if small else 8.0), Vector2(dw, dh))
	card.set_meta("detail_r", dr)
	card.draw_rect(dr, UI.CYAN if on else Color(UI.STEEL.r, UI.STEEL.g, UI.STEEL.b, 0.45))
	card.draw_rect(dr, Color(UI.CYAN, 0.9 if on else 0.5), false, 1.0)
	var ink := Color(0.04, 0.07, 0.09) if on else Color.WHITE
	UI.text(card, g.font, dr.position + Vector2(8 if small else 10, dh / 2.0 + fs * 0.4), "详情", fs, ink)
	var ax := dr.end.x - (11.0 if small else 14.0)
	var ay := dr.get_center().y
	var tri := PackedVector2Array([Vector2(ax - 5, ay - 5), Vector2(ax + 1, ay), Vector2(ax - 5, ay + 5)]) if not on else PackedVector2Array([Vector2(ax - 6, ay - 3), Vector2(ax + 2, ay - 3), Vector2(ax - 2, ay + 3)])
	card.draw_colored_polygon(tri, ink)


## 按技能的真实手动属性和当前身份提示；队友不会出现按 Q 的误导。
func option_description(option: Dictionary) -> String:
	var description: String = str(option.get("desc", ""))
	var kind: String = str(option.get("kind", ""))
	# 构筑可读性（docs/119 §4.3 / §4.4，build_affinity）：招募卡写与已持有藏品的互动（入队即生效 / 培养后生效）；
	# 藏品卡写当前受益干员、触发条件、与已持有相近藏品的关系。换人卡的在 progression.open_swap 里。开关关时为空
	var extra := ""
	if kind == "recruit":
		# 10-23 用户「前面重复的介绍就不需要了」：卡头已写「招募 · 职业」，正文去掉开头的「X干员，」
		if _re_op == null:
			_re_op = RegEx.create_from_string("^[^，,]{1,3}干员[，,]\\s*")   # 只编译一次
		var re := _re_op
		description = re.sub(description, "")
	if kind == "recruit" and not option.get("swap", false):
		extra = ""   # 10-23 用户：招募卡正文不写联动，改为标签行「联动 N」+ 悬停提示（draw_panel_tip）
	elif kind == "relic":
		extra = g.progression.affinity.relic_lines(str(option.get("id", "")))
	if extra != "":
		description += "\n" + extra
	# 手动技能提示只属于干员卡：成长节点卡（prog）和带 op 的干员成长卡。公共成长卡（生存 / 机动 / 协同，doctor.passive_cards，
	# 没有 op）以前落到队长身上，队长有手动技能时（乌尔比安 S3）会把「按 Q 释放」拼进「协同·广」这类卡（用户 10-22 截图）
	if kind != "prog" and not (kind == "growth" and option.has("op")):
		return description
	var op = g.squad.get_op(str(option.get("op", g.ch.id)))
	if op == null:
		return description
	var stage: int = maxi(op.elite, int(option.get("elite", 0)))
	for i in 3:
		var sk: Dictionary = op.skill_def(i)
		if i > stage or sk.get("mode", "auto") != "manual":
			continue
		var use: String = (("队长点技能键释放" if Pad.touch_ui() else "队长按 Q 释放") if op.is_leader else "作为队友自动释放")
		var timing: String = "解锁后" if not op.skill_unlocked(i) else "技力满后"
		return "%s%s「%s」。\n%s" % [timing, use, sk.get("name", "技能"), description]
	return description


## 每帧：按面板种类推进入场动效（card_motion.update）；悬停抬起各种类共用
func animate_cards(dt: float) -> void:
	if not g.panel.visible:
		if ev_cg != null:
			release_event_cg()   # 面板关了：放掉事件插画
		return
	g.panel_fg.queue_redraw()
	g.panel_tip.queue_redraw()
	motion.update(dt)


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
			return UI.CAT_COL.get(g.RL[o.id].lane_name, UI.GOLD)
		"recruit":
			return Color(0.55, 0.9, 0.55)
		"prog":
			if o.get("col", null) != null:
				return o.col
			return Color(0.8, 0.55, 1.0) if o.get("elite", 0) > 0 else Color(0.55, 0.85, 1.0)
		"branch_pick":
			return Color(0.55, 0.85, 1.0)   # 培养路线卡：同干员深度卡
		"weapon":
			return D.WEAPONS[o.id].col
	return UI.CYAN


func draw_card(card: Button, o: Dictionary, i: int) -> void:
	if motion.begin(card, i):
		return   # 升级选卡翻面前：这一帧画的是卡背
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
	if card.get_meta("more", false) and card.get_meta("phone", false):
		draw_detail_chip(card, r, i)
	elif not Pad.touch_ui():   # 右上序号 = 数字键，触屏不画（10-31 TA H7）
		UI.ctext(card, g.font, r.position + Vector2(r.size.x - 40, 32), str(i + 1), 17, UI.TEXT if hov else Color(0.43, 0.47, 0.51), HORIZONTAL_ALIGNMENT_RIGHT, 24)
	if tag[2] != "":
		var rw := UI.cwidth(g.font, tag[2], 10) + 10.0
		card.draw_rect(Rect2(r.position + Vector2(14, 40), Vector2(rw, 15)), tag[3])
		UI.ctext(card, g.font, r.position + Vector2(19, 52), tag[2], 10, Color(0.08, 0.06, 0.02))
	# 图标 + 光环
	var compact: bool = card.get_meta("compact", false)
	var ph: bool = card.get_meta("phone", false)   # 手机：图标 / 名字上移，说明区更高、字更大
	var c := r.position + Vector2(r.size.x / 2.0, (84.0 if ph else 100.0) if compact else 124.0)
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
		# 统一规则（10-23 用户：三张卡里乌尔比安很小、斯卡蒂很大）：@2x 精细版，所有人同一倍率（1 屏幕像素 = 1 个 @2x 像素，
		# 不按画布 / 取景窗缩放），脚底对齐到同一条线；身高差只来自人物本身（同一 Spine 尺度，约 70–80 像素）
		var hi: float = A.hires_of(idle.tex)
		var ks: float = 2.0 / hi   # 1 美术像素 = 2 屏幕像素（@2x 帧 1:1，1 倍帧 ×2）
		var bb: Rect2 = idle.bb
		var ft = idle.foot
		var foot2 := Vector2(float(ft[0]), float(ft[1])) * hi if ft is Array and ft.size() >= 2 else Vector2(idle.fw / 2.0, UI.foot_row(idle.fh, hi))
		var feet := c + Vector2(0, (40.0 if compact else 44.0) + bob)
		if o.kind == "recruit":
			motion.draw_deploy(card, i, feet.round())
		if motion.icon_a > 0.0:
			var sc = motion.icon_scale * ks
			var dst := Rect2(feet - (foot2 - bb.position) * sc + motion.icon_off, bb.size * sc)
			dst.position = dst.position.round()
			card.draw_texture_rect_region(idle.tex, dst, bb)
	elif o.kind == "swap_keep" or o.kind == "branch_back":
		UI.icon(card, "exit", c + Vector2(0, bob), 40.0 if compact else 56.0, Color(0.8, 0.83, 0.86))   # 不替换 / 返回上一步
	elif ic != null:
		draw_icon_fit(card, ic, c + Vector2(0, bob), 64.0 if compact else 96.0)
	else:
		UI.text(card, g.font, c + Vector2(-40, 13 + bob), glyph, 34, card_color(o), HORIZONTAL_ALIGNMENT_CENTER, 80, 3)
	var nm := name
	if o.kind == "relic":
		nm = g.RL[o.id].name
	var ta: float = motion.text_a   # 招募：落地后名字 / 说明 / 标签再淡入
	var roomy: bool = card.get_meta("roomy", false)   # 手机横屏缩小后的卡：加大内边距（PAD_X_PHONE 等）
	var px: float = PAD_X_PHONE if roomy else 20.0
	var ny: float = NAME_Y_PHONE if roomy else ((160.0 if ph else 184.0) if compact else 230.0)
	var nx: float = px if roomy else 0.0
	UI.text(card, g.font, r.position + Vector2(nx, ny), nm, (24 if card.has_meta("brief") else 22) if ph else 20, Color(UI.TEXT.r, UI.TEXT.g, UI.TEXT.b, ta), HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 2.0 * nx, 3)
	var fd: Dictionary = card.get_meta("fit", {})
	if not fd.is_empty():
		var dy: float = DESC_Y_PHONE if roomy else ((176.0 if ph else 198.0) if compact else 244.0)
		var dc := Color(0.86, 0.9, 0.93, ta) if card.has_meta("brief") and card.get_meta("phone", false) else Color(0.655, 0.69, 0.725, ta)   # 电脑：各类卡说明同字号同色（用户 10-30）；phone = 建卡时的 lay().touch
		UI.draw_fit(card, g.font, r.position + Vector2(px, dy), fd, dc, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 2.0 * px)
	# 作用对象：这张卡影响编队里的哪些干员（招募卡列这名干员的伤害特征）；说明区最多到 306，标签行在 310
	var chips: Array = card.get_meta("affects", [])
	if not chips.is_empty():
		UI.chip_row(card, g.font, r.position + Vector2(r.size.x / 2.0, r.size.y - (CHIP_UP_PHONE if roomy else 53.0)), chips, r.size.x - (2.0 * px if roomy else 32.0), 1, "流派" if o.kind in ["recruit", "swap_out"] else "影响", CHIP_FS_PHONE if (ph and card.has_meta("brief")) else 11, ta)
	# 底部操作条：普通钢蓝；悬停青底深字
	var ab := Rect2(r.position + Vector2(20, r.size.y - 46), Vector2(r.size.x - 40, 30)) if roomy else Rect2(r.position + Vector2(16, r.size.y - 44), Vector2(r.size.x - 32, 30))
	if ph and card.has_meta("brief"):
		ab = Rect2(r.position + Vector2(16, r.size.y - 54), Vector2(r.size.x - 32, 42))   # 手机：选择条 42 高（× 0.9 ≈ 38 界面像素）
	card.draw_rect(ab, UI.CYAN if hov else Color(UI.STEEL.r, UI.STEEL.g, UI.STEEL.b, 0.4))
	var ink := Color(0.04, 0.07, 0.09) if hov else Color.WHITE
	var sfs := 17 if ph else 14   # 10-31 TA H7：操作条只写「选择」，序号只在右上角（桌面）
	var w1 := g.font.get_string_size("选择", HORIZONTAL_ALIGNMENT_LEFT, -1, UI.fs(sfs)).x
	var sx := ab.get_center().x - w1 / 2.0
	if ph and card.has_meta("brief"):
		sfs = BTN_FS_PHONE
		sx = ab.get_center().x - g.font.get_string_size("选择", HORIZONTAL_ALIGNMENT_LEFT, -1, UI.fs(sfs)).x / 2.0
	UI.text(card, g.font, Vector2(sx, ab.position.y + (ab.size.y / 2.0 + 6.0 if (ph and card.has_meta("brief")) else (21.0 if ph else 20.0))), "选择", sfs, ink)
	motion.end(card, i, o)


## 卡片左上角标签：[英文, 中文, 稀有度小牌, 小牌底色]
func card_tag(o: Dictionary) -> Array:
	if o.kind == "relic" and not o.has("cat"):
		var rd: Dictionary = g.RL[o.id]
		var rar: String = rd.rarity
		var chip: Array = {"稀有": ["RARE", Color(0.62, 0.72, 0.85)], "核心": ["CORE", UI.GOLD], "升华": ["ASCEND", Color(0.72, 0.64, 1.0)], "遭诅古物": ["CURSED", UI.RED]}.get(rar, ["", Color.WHITE])
		return [UI.CAT_EN.get(rd.lane_name, "RELIC"), "%s · %s" % [rd.lane_name, rar], chip[0], chip[1]]
	var cat := "成长  GROWTH"
	if o.has("cat"):
		cat = o.cat
	elif o.kind == "recruit":
		cat = "招募 · " + o.get("cls", "") + "  RECRUIT"
	elif o.kind == "prog":
		cat = ("精英化  ELITE" if o.get("elite", 0) > 0 else "干员培养  OPERATOR")
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
	var hov: bool = card_hot(card, i) and not o.get("disabled", false)
	card.self_modulate.a = 0.45 if o.get("disabled", false) else 1.0   # 买不起的选项（深蓝之心的房间）整条压暗
	var art := event_art(g.panel_title_text)
	var ox: float = card.get_meta("ox", 0.0)
	var w := card.size.x
	var base := Vector2(ox, 0)
	var ph: bool = card.get_meta("phone", false)   # 手机：条本体 74 高，图标 48、标题 30、说明 40 起
	var tx0: float = 100.0 if ph else 112.0
	var shape: PackedVector2Array = art.bars[i % art.bars.size()]
	var sp := PackedVector2Array()
	for q in shape:
		sp.append(base + Vector2(q.x * w / 596.0, q.y * card.size.y / 100.0))
	UI.fill_poly(card, sp, Color(0.925, 0.91, 0.882, 0.14) if hov else Color(0.07, 0.07, 0.075, 0.9))
	var en_ring: PackedVector2Array = art.ensos[i % art.ensos.size()]
	var er := PackedVector2Array()
	for q in en_ring:
		er.append(base + q + Vector2(-6.0 if ph else 0.0, card.size.y / 2.0 - 50.0))
	UI.fill_poly(card, er, Color(0.925, 0.91, 0.882, 0.55 if hov else 0.22))
	var ink := Color(0.925, 0.91, 0.882)
	var icn: String = o.get("icon", "")
	var itx: Texture2D = g.tex.get(icn) if icn != "" and icn != "exit" else null
	if itx != null:
		draw_icon_fit(card, itx, base + Vector2(50.0 if ph else 56.0, card.size.y / 2.0), 48.0 if ph else 64.0)
	else:
		UI.icon(card, "exit", base + Vector2(50.0 if ph else 56.0, card.size.y / 2.0), 28.0 if ph else 32.0, ink)
	card.draw_string(serif, base + Vector2(tx0, 30.0 if ph else 38.0), o.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE if hov else ink)
	var x := tx0 + serif.get_string_size(o.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 14.0
	for chp in o.get("chips", []):
		var cw := g.font.get_string_size(chp[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 12.0
		var cr := Rect2(base + Vector2(x, 12.0 if ph else 20.0), Vector2(cw, 18))
		card.draw_rect(cr, Color(chp[1].r, chp[1].g, chp[1].b, 0.9), false, 1.0)
		card.draw_string(g.font, cr.position + Vector2(6, 13), chp[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, chp[1])
		x += cw + 6.0
	var fb: Dictionary = card.get_meta("fit", {})
	if not fb.is_empty():
		UI.draw_fit(card, g.font, base + Vector2(tx0, 40.0 if ph else 50.0), fb, Color(0.81, 0.79, 0.76))
	UI.ctext(card, g.font, base + Vector2(w - 46, card.size.y / 2.0 + 10.0), str(i + 1), 24, Color(0.18, 0.72, 1.0) if hov else Color(0.37, 0.36, 0.35), HORIZONTAL_ALIGNMENT_CENTER, 24)
	if hov:
		card.draw_rect(Rect2(base + Vector2(8, 20), Vector2(8, card.size.y - 40.0)), Color(0.18, 0.72, 1.0, 0.25))
		card.draw_rect(Rect2(base + Vector2(10, 22), Vector2(4, card.size.y - 44.0)), Color(0.18, 0.72, 1.0))


## 翻节点卡（docs/154）：卡面与演出在 screens/node_cards_ui.gd（卡背纹样、结局色边、发牌 → 起手 → 翻转 → 揭示 → 退场）；
## 这里只把卡片数据整理成绘制参数
func draw_node_card(card: Button, o: Dictionary, i: int) -> void:
	var c: Dictionary = o.get("node", {})
	var ends: Array = (c.get("ends", []) as Array).filter(func(e): return Cfg.endings_cleared.has(e))
	var hot: bool = card_hot(card, i) and g.endg.flipped < 0
	var st := {
		"i": i, "n": g.choices.size(), "hot": hot, "flipped": g.endg.flipped,
		"deal_t": motion.t0, "flip_t": g.endg.flip_t, "ends": ends, "ends_cols": ends.map(func(e): return g.endg.ending_col(e)),
		"center_x": (card.get_global_transform().affine_inverse() * g.panel_box.get_global_rect().get_center()).x,
		"hover_k": _ease_meta(card, "hover_k", 1.0 if hot else 0.0, 0.14),
		"relic_tex": {"222": g.tex.get("relic_222"), "220": g.tex.get("relic_220"), "242": g.tex.get("relic_242")},
	}
	if g.endg.flipped == i:
		var t: String = str(c.get("type", ""))
		match t:
			"incident":
				var ev: Dictionary = g.endg.ev_by_id.get(str(c.get("event", "")), {})
				st.face_title = str(ev.get("name", "不期而遇"))
				st.face_body = str(ev.get("text", ""))
				if c.get("must", false) and not ends.is_empty():   # 只写已达成过的结局（未知路线不泄露）
					st.face_tag = " / ".join(ends.map(func(e): return NodeCardsUI.ROUTE_NAME.get(e, "")))
			"wish":
				st.face_title = "消失的习俗"
				st.face_body = "亮出三件藏品，选一件带走；也可以付生命多拿一件。"
			"rest":
				st.face_title = "安全屋"
				st.face_body = "休整、添加燃料，或重整编制。"
			"shop":
				st.face_title = "诡意行商"
				st.face_body = "行商就地摆开货摊，进一次商店。"
			"elite":
				st.face_title = "紧急作战"
				st.face_body = "一支精英小队从边缘压上来。全部击败，得宝箱与源石锭。"
	card.self_modulate.a = 1.0
	NodeCardsUI.draw_card(card, card.size, c, st, g.font, serif)


## 卡片上的平滑量（悬停抬起、卡外文字淡入淡出）：按界面时钟朝 target 线性逼近，dur 秒走完 0→1；减少动态 / 无头时直接到位
func _ease_meta(node: Object, key: String, target: float, dur: float) -> float:
	var now := UM.now()
	var v: float = float(node.get_meta(key, target))
	var last: float = float(node.get_meta(key + "_t", now))
	if UM.rm() or UM.skip_all():
		v = target
	else:
		v = move_toward(v, target, (now - last) / maxf(0.01, dur))
	node.set_meta(key, v)
	node.set_meta(key + "_t", now)
	return v


## 干员待机条的第一帧：{tex, fw, fh}（按 data/characters/<id>.json 的 sprites.idle；没有返回空）
func op_idle(cid: String) -> Dictionary:
	if _idle_cache.has(cid):
		return _idle_cache[cid]
	var out := _op_idle(cid)
	_idle_cache[cid] = out
	return out


## 选卡 / 属性面板 / 作战记录每帧每张卡都调 op_idle：以前每次都读盘解析干员 JSON（load_def）+ 扫目录，10-25 帧率审计改成按干员缓存（纯画面数据）
var _idle_cache := {}

func _op_idle(cid: String) -> Dictionary:
	if cid == "" or not Character.list_ids().has(cid):
		return {}
	var cdef: Dictionary = Character.load_def(cid)
	var sp = cdef.get("sprites", {}).get("idle", null)
	if sp == null:
		return {}
	var tn: String = sp if sp is String else sp.get("tex", "")
	var tx: Texture2D = A.tex_hi(tn)   # 界面位用 @2x 精细版（10-23 用户「选人和图鉴放精细版」；局内 g.tex 是 1 倍，不共用）
	if tx == null:
		return {}
	var frames: int = int(sp.get("frames", 0)) if sp is Dictionary else 0
	if frames <= 0:
		frames = maxi(1, tx.get_width() / tx.get_height())
	if Character.strip_mirror(cdef, "idle"):
		tx = A.mirror_strip(tx, frames)   # 待机条画反了（docs/84）：用镜像副本
	var fw0: int = tx.get_width() / frames
	var ft = (sp.get("foot") if sp is Dictionary else null)
	if ft == null:
		ft = cdef.get("sprites", {}).get("foot", null)
	var out := {"tex": tx, "fw": fw0, "fh": tx.get_height(), "win": UI.op_win(fw0, tx.get_height(), A.hires_of(tx), ft), "foot": ft, "frames": frames}
	if not _bb_cache.has(tn):
		_bb_cache[tn] = UI.idle_bb(tx, frames)
	out["bb"] = _bb_cache[tn]
	return out


## 干员贴图集（运行中招募 / 测试编入时补加载）
func load_op_tex(cid: String) -> void:
	var cdef: Dictionary = Character.load_def(cid)
	var csp: Dictionary = cdef.get("sprites", {})
	for kind in ["idle", "run", "attack", "skill", "move_attack"] + cdef.get("extra_sprites", []):
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
		var links: String = card.get_meta("links", "")
		if card.has_meta("brief") and card.get_meta("phone", false):
			# 手机 / 平板：只有点开「详情」的那张画完整说明（含联动 / 被收起的影响对象）
			if card.get_index() != detail_i or not card.get_meta("more", false):
				continue
		elif card.has_meta("brief"):
			# 电脑：干员卡只写了一句，悬停时给完整说明
			if not (card.get_meta("more", false) or cut or links != "") or not g.panel_ui.card_hot(card, card.get_index()):
				continue
		elif ((fd.is_empty() or fd.get("fit", true)) and not cut and links == "" and not card.has_meta("squad_cut")) or not g.panel_ui.card_hot(card, card.get_index()):
			continue
		var gr: Rect2 = card.get_global_rect()
		var it: Dictionary = card.get_meta("item", {})
		var title: String = it.get("name", "") if not it.is_empty() else (g.choices[card.get_index()].get("name", "") if card.get_index() < g.choices.size() else "")
		var fallback: String = it.get("desc", "") if not it.is_empty() else (g.choices[card.get_index()].get("desc", "") if card.get_index() < g.choices.size() else "")
		var desc: String = card.get_meta("full_desc", fallback)
		if cut:
			desc += "\n影响：" + "、".join(PackedStringArray(card.get_meta("affects", []).map(func(c): return c[0])))
		if card.has_meta("brief") and card.get_meta("phone", false):
			_draw_phone_detail(card, title, desc + ("\n联动：" + links if links != "" else ""))
			return
		if card.has_meta("brief"):
			g.hud_view.draw_tooltip(vs, Rect2(gr.position - g.panel_tip.get_global_rect().position, gr.size), title, "完整说明",
				desc + ("\n联动：" + links if links != "" else ""), "", UI.CYAN, g.panel_tip)
			return
		var sub := "完整说明"
		if links != "" and not card.has_meta("brief"):
			desc = links   # 10-23 用户：招募卡提示框只列生效的藏品 / 联动，不重复干员介绍
			sub = "联动"
		g.hud_view.draw_tooltip(vs, Rect2(gr.position - g.panel_tip.get_global_rect().position, gr.size), title, sub, desc, "", UI.CYAN, g.panel_tip)
		return


## 手机「详情」：完整说明直接盖在这张卡上（卡头标签和「详情」键、底部选择条露在外面，点「详情」收起、点选择条照常选），
## 不另外弹框挡住别的卡。正文 18 号起、最小 15（× 0.9 缩放），放不下才截断
func _draw_phone_detail(card: Button, title: String, desc: String) -> void:
	var tip: Control = g.panel_tip
	var sc: float = g.panel_box.scale.x
	var gr: Rect2 = card.get_global_rect()
	var o: Vector2 = gr.position - tip.get_global_rect().position + Vector2(0, card.get_meta("oy", 0.0) * sc)
	var r := Rect2(o + Vector2(6.0, 42.0) * sc, Vector2(card.size.x - 12.0, card.size.y - 42.0 - 60.0) * sc)
	var pad := 14.0 * sc
	var sizes := [17, 16, 15, 14]
	var fd := UI.fit(g.font, desc, r.size.x - 2.0 * pad, r.size.y - 48.0 * sc - pad, sizes, 3.0)
	if not fd.fit:
		# 详情就是完整说明，不截断（10-28 用户截图「已持有…」）：最小字号仍放不下就把框加高，先向下盖住操作条，再整体上移，以面板为界
		var need: float = UI.fit(g.font, desc, r.size.x - 2.0 * pad, 1e6, [sizes[-1]], 3.0).h + 48.0 * sc + pad
		r.size.y = minf(need, tip.size.y - 12.0)
		r.position.y = clampf(r.position.y, 6.0, maxf(6.0, tip.size.y - 6.0 - r.size.y))
		fd = UI.fit(g.font, desc, r.size.x - 2.0 * pad, r.size.y - 48.0 * sc - pad, sizes, 3.0)
	tip.draw_rect(r, Color(0.035, 0.045, 0.06, 0.97))
	tip.draw_rect(r, Color(UI.CYAN, 0.7), false, 1.0)
	tip.draw_rect(Rect2(r.position, Vector2(3.0, r.size.y)), UI.CYAN)
	UI.text_fit(tip, g.font, r.position + Vector2(pad, 28.0 * sc), title, 19, Color.WHITE, r.size.x - 2.0 * pad, 14)
	UI.draw_fit(tip, g.font, r.position + Vector2(pad, 46.0 * sc), fd, Color(0.86, 0.92, 0.95))
