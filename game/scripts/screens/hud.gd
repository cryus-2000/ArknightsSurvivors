extends RefCounted
## 界面 · 局内 HUD（hud 画布节点的 draw 信号）：按 state 分派到各界面（intro / elite_show / stats_panel / result），HUD 本体按块分派到
## hud_bars（左上 / 顶栏 / Boss 血条 / 状态栏 / 声呐）、hud_relics（右上）、hud_squad（右下编队与手动技能）、hud_banners（提示 / 指示 / 横幅）；
## 本文件留：合批段与分层缓存、底层子画布（飘字 / 暗角）、倒下过渡、共用助手。界面层约定（docs/39 §3）。2026-09-26 从 game.gd 拆出，2026-10-10 拆分（docs/55 §6）。

const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game
var _dbg_nonum: bool = preload("res://scripts/render/declutter.gd").dbg("nonum")   # --clutterdbg=nonum：不画伤害数字（量测，tools/late_clutter.py）
const Tris = preload("res://scripts/screens/hud_tris.gd")   # 无贴图图元批（原内部类）
const HudBars = preload("res://scripts/screens/hud_bars.gd")
const HudRelics = preload("res://scripts/screens/hud_relics.gd")
const HudSquad = preload("res://scripts/screens/hud_squad.gd")
const HudBanners = preload("res://scripts/screens/hud_banners.gd")
const HudAllyHp = preload("res://scripts/screens/hud_allyhp.gd")   # 队友血条原型（docs/114 §19）
const HudIcons = preload("res://scripts/screens/hud_icons.gd")
const HudUlt = preload("res://scripts/screens/hud_ult.gd")   # 终结技 / 连携技 HUD 与立绘切入（docs/198；g.ult 为 null 时不调）
const TextQ = preload("res://scripts/screens/hud_textq.gd")
const TriBatch = preload("res://scripts/render/tri_batch.gd")
var icons := HudIcons.new()   # HUD 图标图集（藏品 / 立绘 / 技能图标 / 源石锭，docs/50 §13）
var bars: HudBars
var relics: HudRelics
var squad: HudSquad
var banners: HudBanners
var allyhp: HudAllyHp
var ult: HudUlt


func _init(game: Game) -> void:
	g = game
	bars = HudBars.new(self)
	relics = HudRelics.new(self)
	squad = HudSquad.new(self)
	banners = HudBanners.new(self)
	allyhp = HudAllyHp.new(self)
	ult = HudUlt.new(self)


## HUD 合批段：段内 UI 助手的色块进 Tris 批、文字延后，batch_end 时先一次提交色块再画字（段内各块互不重叠才能这样用）
var _hb: Tris = null

func batch_begin() -> void:
	_hb = Tris.new()
	UI.sink = _hb
	UI.tq = _tq_get()


## HUD 合批（docs/50 §13，OPT_HUDB）：字按字体字号成组、图标走图集、飘字分组。旧写法（逐个直接画）已定案删除（docs/101 S2，10-15），
## OPT_HUDB 位保留但不再选路


## 一组按原顺序画字的 Callable（各自调 UI.text / ctext / en……）：合批时按字体字号归组后再画（各行字互不重叠时用）
func text_flush(fs: Array) -> void:
	if fs.is_empty():
		return
	var keep = UI.tq
	var q: TextQ = _tq_get()
	UI.tq = q
	for f in fs:
		f.call()
	UI.tq = keep
	q.flush()
	_tqs.append(q)


var _tqs: Array = []   # 用过的 TextQ（flush 后是空的），重复用，省得每段新建

func _tq_get() -> TextQ:
	return _tqs.pop_back() if not _tqs.is_empty() else TextQ.new()


## 画一组图标 [贴图, 目标矩形(, 源矩形, 调制色)]：合批时从图标图集取区域连着画（放不下的照旧画原贴图，按原顺序）
func icons_draw(list: Array) -> void:
	if list.is_empty():
		return
	var regs: Array = []
	for it in list:
		var t: Texture2D = it[0]
		var full := Rect2(Vector2.ZERO, t.get_size())
		var src: Rect2 = it[2] if it.size() > 2 else full
		regs.append(icons.region(t, src, "" if src == full else str(src)))
	icons.commit()
	for i in list.size():
		var it: Array = list[i]
		var mod: Color = it[3] if it.size() > 3 else Color.WHITE
		if regs[i].has_area() and icons.tex != null:
			g.hud.draw_texture_rect_region(icons.tex, it[1], regs[i], mod)
		else:
			_icon_raw(it)


func _icon_raw(it: Array) -> void:
	var t: Texture2D = it[0]
	var mod: Color = it[3] if it.size() > 3 else Color.WHITE
	if it.size() > 2 and it[2] != Rect2(Vector2.ZERO, t.get_size()):
		g.hud.draw_texture_rect_region(t, it[1], it[2], mod)
	else:
		g.hud.draw_texture_rect(t, it[1], false, mod)


## mid：色块之后、文字之前要画的贴图（同贴图连续画才合批）
func batch_end(mid: Array = []) -> void:
	var q = UI.tq
	UI.sink = null
	UI.tq = null
	_hb.flush(g.hud)
	_hb = null
	for f in mid:
		f.call()
	if q is Array:
		for f in q:
			f.call()
	else:
		q.flush()
		_tqs.append(q)


## HUD 块（性能 docs/50 §9.10；10-22 起整个局内 HUD 按块拆，docs/126 §9.2）：局内 HUD 是一串有序的兄弟画布——g.hud 下的全屏子 Control
## （show_behind_parent，画在父画布之下），上下次序固定按 LAYER_ORDER 建（后建的在上），与拆分前的实际层次逐像素相同。
## 父画布（g.hud 本身）只画整屏状态界面（暂停 / 结算 / 精英化演出 / 开场 / 寻访），压在所有块之上。
## 每块 _layer(key, 签名, 绘制函数)：签名为 null = 每帧画；否则签名变了才重画，平时 Godot 保留上次的绘制命令、不跑 GDScript。
## 重画时把 g.hud 临时指向子画布，原来的绘制函数不用改。本帧走到调用点的块才显示。
## 加一块：在 LAYER_ORDER 里按层次插一个键，在 _draw_body 里调 _layer；缺省（签名 null）最安全。要缓存时签名必须写全这块读到的状态，
## 连续量按像素量化（qpx），动画进行中把 g.t 放进签名；绘制时顺手写的状态（点击区域等）要挪到登记时算（例：relics.update_buttons）。
## --hudnocache：所有块每帧画（验收新界面时对照用：开 / 关画面应当一样）
const LAYER_ORDER := ["under", "top_left", "minimap", "relics", "squad",
	"pointers", "mid", "top", "boss", "squad_fr", "ult", "front", "status", "tail", "ult_cut"]
var _layers := {}
static var _nocache: int = -1


static func nocache() -> bool:
	if _nocache < 0:
		_nocache = 1 if Cfg.dev_args().has("--hudnocache") else 0
	return _nocache == 1


## 连续量的签名：x（逻辑像素）按 1/8 像素量化——没跨过量化格不重画；画面上最多差 1/8 逻辑像素，到跨格那一帧补上
static func qpx(x: float) -> int:
	return floori(x * 8.0)


func _layer_node(key: String) -> Dictionary:
	if _layers.is_empty():
		for k in LAYER_ORDER:   # 第一次用到任何一层时按固定次序一次建好（后建的画在上面），不随哪一块先被调用而变
			_layers[k] = _new_layer(k)
	if not _layers.has(key):
		_layers[key] = _new_layer(key)
	return _layers[key]


func _new_layer(key: String) -> Dictionary:
	var node := Control.new()
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.show_behind_parent = true
	node.visible = false
	g.hud.add_child(node)
	node.draw.connect(func(): _layer_draw(key))
	return {"node": node, "sig": null, "fn": Callable(), "used": false}


func _layer(key: String, sig, fn: Callable) -> void:
	var L: Dictionary = _layer_node(key)
	L.used = true
	L.fn = fn
	if sig == null or nocache() or (g.opt_old & Game.OPT_HUDNC) or L.sig != sig:
		L.sig = sig
		L.node.queue_redraw()


func _layer_draw(key: String) -> void:
	var L: Dictionary = _layers[key]
	if not L.fn.is_valid():
		return
	var keep: Control = g.hud
	g.hud = L.node
	var t0 := Time.get_ticks_usec() if g.prof_on else 0
	g._timed("draw_hud", L.fn)   # --prof：各块的绘制也计进 draw_hud（与拆块前口径相同：整个局内 HUD 的脚本时间）
	if g.prof_on:
		g.prof_add("hud_" + key, t0)   # 每块分开计（docs/50 §37）
	g.hud = keep


func draw() -> void:
	if not _glyphs_warm and g.demo_op == "" and not Cfg.mobile_fonts_slim():   # 图鉴演示不预热；手机网页不预热（每个字号一份字形缓存，这批约 150 个字号、60 MB，docs/50 §30）
		_warm_glyphs()
	for k in _layers:
		_layers[k].used = false
	_draw_body()
	for k in _layers:
		_layers[k].node.visible = _layers[k].used

## 字形预热（网页开局掉帧，10-22）：动态字体按「字号 + 描边」各自建字形缓存，飘字 / 大群横幅 / LEVEL UP 带弹出放大，
## 字号逐帧变，局内每遇到一个新字号就要当帧栅格化一批字形、重传字体贴图（网页实测开局 0–15 秒几次 150–390 ms 的卡顿，
## 当帧几十到两百多次 texImage2D）。进局第一帧在屏幕外按局内同样的调用把这些字号各画一遍，缓存提前建好。只画在屏幕外，画面不变
var _glyphs_warm := false
var _qs_on := -1

## 弹出放大的字号（飘字 / LEVEL UP / 大群横幅）：手机网页按 4 号一档取整，每个字号都要一份字形缓存，逐号放大会建出几十份（docs/50 §30）；其余平台原样
func _qs(sz: int) -> int:
	if _qs_on < 0:
		_qs_on = 1 if Cfg.mobile_fonts_slim() else 0
	if _qs_on == 0 or sz <= 16:
		return sz
	return 16 + int(round((sz - 16) / 4.0)) * 4
const WARM_NUM := "0123456789弱点破绽 "

func _warm_glyphs() -> void:
	_glyphs_warm = true
	var keep = UI.tq
	UI.tq = null
	var ci: CanvasItem = g.hud
	var fnt: Font = g.font
	var far := Vector2(-20000, -20000)
	# 飘字（_dmg_numbers）：基准字号 8–20（合并后最多 +6），弹出放大到 ×1.7；按 UI._ks 换算后的字号，描边 4 与本体各一遍
	var sizes := {}
	for s0 in range(6, 41):
		sizes[UI._ks(ci, s0)] = true
	for ks in sizes:
		ci.draw_string_outline(fnt, far, WARM_NUM, HORIZONTAL_ALIGNMENT_LEFT, -1, ks, 4, Color(0, 0, 0, 1))
		ci.draw_string(fnt, far, WARM_NUM, HORIZONTAL_ALIGNMENT_LEFT, -1, ks, Color.WHITE)
	# 大群横幅（_draw_under）：int(38 × pop)，pop 1.0–1.8，描边 6
	var horde := "海嗣注意到了你的存在……自四方合围而来大 群 来 袭海嗣大群 已抵达"
	for sz in range(38, 69):
		UI.text(ci, fnt, far, horde, sz, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, 6)
	# 升级字样：LEVEL UP! int(30 × pop)（描边 6）、Lv.n int(18 × pop)（描边 4），pop 0.9–1.6
	for sz in range(27, 49):
		UI.text(ci, fnt, far, "LEVEL UP!", sz, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, 6)
	for sz in range(16, 30):
		UI.text(ci, fnt, far, "Lv.0123456789", sz, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, 4)
	# 左上等级数字（hud_bars.draw_top_left）：int(20 × (1 + 0.3 × 闪光))
	for sz in range(20, 27):
		UI.ctext(ci, fnt, far, "0123456789", sz, Color.WHITE)
	UI.tq = keep
	# 界面层「无光照 + 图元」着色器变体（选卡卡片的细线等第一次画时当帧编译，网页实测约 200 ms）：画一条透明度 0 的细线让它进局就编译；
	# 透明度 0 混合后像素不变（必须画在屏幕内，屏幕外会被剔除）
	ci.draw_line(Vector2(0, 0), Vector2(1, 0), Color(1, 1, 1, 0), -1.0)
	ci.draw_primitive(PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]), PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 0)]), PackedVector2Array())



func _draw_body() -> void:
	var vs := g.hud.size
	g.speed_btn = Rect2()
	var ct := g.hud_ct()
	if g.state == Game.S.OPENING:
		g.intro_screen.draw_opening_hud(vs)
		return
	# 底层（每帧画，最下层）：精英标记、飘字、全屏色调与暗角
	_layer("under", null, func(): _draw_under(vs, ct))
	if g.demo_op != "":
		return   # 图鉴演示：只要伤害数字，不画其余 HUD
	if g.state == Game.S.SHOW:
		# 精英化演出：不画其余 HUD（遮罩只有 86% 不透明，顶栏、编队卡的文字会隐约透出来），只画演出本身
		g.show_screen.draw(vs)
		return
	# 各块的层次见 LAYER_ORDER（与 10-22 拆块前的实际层次相同：原缓存层在下，原主画布各段按原顺序在上）；块内的先后照旧，别调换。
	# 绘制回调按登记先后执行：boss 块写的 bars.boss_bottom 在 front / tail 读之前更新
	if not (panel_over_top() and g.choice_kind == "event"):
		# 触屏事件（节点卡的不期而遇）的标题与剧情行占左上角，生命 / 灯火条不画（10-13 手机实测压字）
		_layer("top_left", bars.top_left_sig(vs), func(): bars.draw_top_left(vs))
	_layer("pointers", null, func():
		banners.draw_leader_hints(ct)
		banners.draw_merchant_pointer(vs, ct)
		banners.draw_boss_pointers(vs, ct)
		banners.draw_offscreen_edges(vs, ct)   # 镜头拉近（战斗画面缩放 > 100%）时屏外近处敌人的边缘红边
		banners.draw_field_wave(vs)
		banners.draw_beacon_pointers(vs, ct))
	var pq := phone_quiet()
	if not overlay_left() and not pq:
		# 小地图每 3 帧重画一次（20 次 / 秒；红点 300 个时逐个画是 HUD 里最贵的一块）
		_layer("minimap", [Engine.get_process_frames() / 3, vs], func(): bars.draw_minimap(vs))
	_layer("mid", null, func():
		bars.draw_lamp_strip(vs)
		banners.draw_zone_warning(vs))
	relics.update_buttons(vs)   # 暂停 / 倍速键的点击区域：每帧算（顶部块缓存时不重画）
	_layer("top", bars.top_sig(vs), func():
		bars.draw_top_center(vs)   # 开合批段（顶部中央 + 右上暂停键共用一批）
		relics.draw_right_top(vs))   # 收合批段：这两行必须相邻
	if not pq:
		relics.register_tray(vs)   # 藏品栏缓存层（藏品 / 等级 / 悬停格变了才重画）
	_layer("boss", null, func(): bars.draw_boss_bars(vs))
	if not pq:
		squad.draw(vs)   # 登记编队栏静态层（squad）与每帧层（squad_fr）
	if g.ult != null:
		_layer("ult", null, func(): ult.draw(vs))   # 终结技能量 / 协同 / 连携排队（触屏：终结技键与连携键）
	_layer("front", null, func():
		bars.draw_xp_top(vs)   # 经验通栏细条（屏幕最上沿）
		allyhp.draw(vs)   # 队友血条原型（command/hpbar_style 1 / 3；0 = 编队卡缓存层里的原版）
		banners.draw_command(vs, ct)   # 指挥模式：屏外队友方向标记 + 当前模式（docs/114）；压在顶栏 / 编队栏之上
		banners.draw_banner(vs)
		banners.draw_notices(vs)
		banners.draw_open_hints(vs)
		relics.draw_relic_tooltip(vs)
		g.panel_ui.draw_pick_glow(g.hud)   # 选卡后的选中余光
		g.touch.draw_hud(vs))
	if not overlay_left() and not pq:
		var sitems: Array = bars.status_items()
		_layer("status", bars.status_sig(vs, sitems), func(): bars.draw_status(vs, sitems))
	_layer("tail", null, func():
		banners.draw_dash_hint(vs)
		banners.draw_zone_hint(vs)
		squad.draw_manual_aim()
		squad.draw_manual_hint()
		g.boss_intro.draw_hud(vs)
		g.victory.draw_hud(vs))   # 胜利收尾：暖金光环 + 「探索完成」（run/victory_flow.gd，docs/62 §3.21c）   # Boss 登场 / 击破演出：黑边、暗角、名片，压在全部 HUD 之上（screens/boss_intro.gd）
	if g.ult != null:
		_layer("ult_cut", null, func(): ult.draw_cutins(vs))   # 终结技立绘切入条带（压在各块之上、整屏状态界面之下）
	g.pick.draw(vs)   # 指点（示意原型）：已下达指令的标记 + 选点阶段的准星
	g.wheel.draw(vs)   # 指挥圆盘（docs/114 §12）：打开时盖在 HUD 上，直接画在 hud 画布（缓存层之上）
	match g.state:
		Game.S.SHOW:
			g.show_screen.draw(vs)
		Game.S.INTRO:
			g.intro_screen.draw(vs)
		Game.S.STATS:
			g.stats_screen.draw(vs)
		Game.S.PAUSE:
			g.result_screen.draw(vs, "暂停", "PAUSED", UI.CYAN, [["继续", "Esc", "resume"], ["指南", "G", "guide"], ["设置", "O", "settings"], ["重新开始", "R", "restart"], ["回到标题", "T", "title"]])
		Game.S.DEAD:
			if g.state_age < DEATH_T:
				draw_death_transition(vs)
			else:
				if g.trial.active:
					draw_trial_result(vs, false)
				elif g.run_stats.open:
					g.result_btns.clear()
					g.run_stats.draw(vs)   # 作战记录（docs/77）
				elif g.run_log.open:
					g.result_btns.clear()
					g.run_log.draw(vs)   # 对局记录
				else:
					g.result_screen.draw(vs, "探索终止", "OPERATION FAILED", UI.RED, [["再次探索", "R", "restart"], ["作战记录", "Tab", "stats"], ["回到标题", "T", "title"]])
				# 结算面板淡入：盖一层和过渡末尾同色的暗幕，0.35 秒退去
				var fa: float = 1.0 - clampf((g.state_age - DEATH_T) / 0.35, 0.0, 1.0)
				if fa > 0.0:
					g.hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.01, 0.03, 0.05, 0.85 * fa))
		Game.S.WIN:
			if g.trial.active:
				draw_trial_result(vs, true)
			elif g.run_stats.open:
				g.result_btns.clear()
				g.run_stats.draw(vs)   # 作战记录（docs/77）
			elif g.run_log.open:
				g.result_btns.clear()
				g.run_log.draw(vs)   # 对局记录
			else:
				g.result_screen.draw(vs, "%s · 探索完成" % D.ENDINGS[g.ending].name, D.ENDINGS[g.ending].en, g.endg.cur_col().lerp(UI.GOLD, 0.35), [["再次探索", "R", "restart"], ["作战记录", "Tab", "stats"], ["回到标题", "T", "title"]], true)
	g.tour.draw_tip(vs)   # 到点小提示（screens/tour.gd）：压在所有界面之上，不拦输入
	# 寻访（docs/109 §12）：打不打开由 headhunt.tick 在主循环里定（docs/126 R4），这里只画
	if g.headhunt.open and (g.state == Game.S.WIN or g.state == Game.S.DEAD) and not g.run_stats.open and not g.run_log.open:
		g.result_btns.clear()
		g.headhunt.draw(vs)


## 原 _draw_body 开头那段：精英标记、伤害数字（图鉴演示 / 精英化演出时也画），以及之后的升级字样、全屏闪光 / 溟痕 / 受伤红 / 低血 / 低灯暗角、
## 头顶小血条（演示 / 演出时不画）。挪到底层子画布里画，藏品栏、编队栏缓存层才能照原来的层次压在它们上面（docs/50 §9.10）
func _draw_under(vs: Vector2, ct: Transform2D) -> void:
	draw_elite_marks(ct)
	# 伤害数字（精英化演出期间不画：遮罩只有 86% 不透明，飘字会透出来压在横幅上）
	var dn: Array = []   # 合批时先收集，_dmg_numbers 分层画（docs/50 §13）
	for f in (g.texts if ((g.state != Game.S.SHOW and g.state != Game.S.DEAD) or g.demo_op != "") and not _dbg_nonum else []):   # 倒下后不画定格的飘字（会压在「探索终止」上）；--clutterdbg=nonum 量测
		var a: float = clamp(f.life / f.max, 0.0, 1.0)
		# 图鉴演示：主控身上的飘字压淡（斯卡蒂潮汐时成串数字会整块盖住她）
		if g.demo_op != "" and g.ch != null and absf(f.pos.x - g.ch.pos.x) < 36.0 and f.pos.y > g.ch.pos.y - 80.0 and f.pos.y < g.ch.pos.y + 10.0:
			a *= 0.3
		var sp: Vector2 = ct * f.pos
		var pop: float = 1.0 + 0.7 * clamp((f.life - f.max + 0.12) / 0.12, 0.0, 1.0)
		var sz := _qs(int(f.size * pop))
		dn.append([sp - Vector2(60, 0), f.text, sz, Color(f.col.r, f.col.g, f.col.b, a)])
	if not dn.is_empty():
		_dmg_numbers(dn)

	if g.demo_op != "" or g.state == Game.S.SHOW:
		return
	# 升级字样：弹出放大 -> 轻微上浮 -> 淡出
	if g.lvup_show > 0.0 and g.state == Game.S.PLAY and (g.ult == null or not g.ult.show_busy()):
		var age := 1.3 - g.lvup_show
		var pop := 1.0 + 0.6 * clampf(1.0 - age / 0.15, 0.0, 1.0)
		if age > 0.15 and age < 0.3:
			pop = 1.0 - 0.1 * sin((age - 0.15) / 0.15 * PI)
		var la := clampf(g.lvup_show / 0.35, 0.0, 1.0)
		var lp: Vector2 = ct * (g.ppos + Vector2(0, -92 - age * 14.0))
		var gold := Color(1.0, 0.86, 0.42, la)
		UI.text(g.hud, g.font, lp - Vector2(150, 0), "LEVEL UP!", _qs(int(30 * pop)), gold, HORIZONTAL_ALIGNMENT_CENTER, 300, 6)
		UI.text(g.hud, g.font, lp + Vector2(-150, 26), "Lv.%d" % g.level, _qs(int(18 * pop)), Color(0.85, 1.0, 0.98, la), HORIZONTAL_ALIGNMENT_CENTER, 300, 4)

	if g.flash > 0.0:
		g.hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(1.0, 0.97, 0.9, g.flash * 0.5))
	# 大群预警与到达演出
	if (g.horde_warn > 0.0 or g.horde_hit > 0.0) and not g.panel.visible:   # 选卡 / 商人面板打开时不画（EA 1.1：升级面板压在「大群来袭」上）
		var hw := g.horde_warn > 0.0
		var pulse := 0.5 + 0.5 * sin(g.t * (10.0 if hw else 4.0))
		var streams: bool = not g.horde_streams.is_empty()
		# 10-22b 用户：两种横幅都去掉紫色横条，文字缓慢淡入 0.6 秒 / 停 2 秒 / 淡出 0.8 秒（预警 3 秒 + 到达 1.2 秒的时间线上从预警开始算）；
		# 分股合围（「海嗣注意到了你的存在……」）再去掉震动（文字抖动、入场镜头轻推）与紫色边光，只留文字；大群来袭保留文字抖动与边光
		var hunt_w: bool = g.horde_hunt
		if not streams and not hunt_w:
			var ea := (0.25 + 0.3 * pulse) if hw else g.horde_hit / 1.2 * 0.6
			edge_glow(vs, Color(0.55, 0.15, 0.85, ea), 120.0)
		var age := (3.0 - g.horde_warn) if hw else 3.0 + (1.2 - g.horde_hit)
		var ta := clampf(age / 0.6, 0.0, 1.0) * clampf((3.4 - age) / 0.8, 0.0, 1.0)
		var cy := vs.y * 0.3
		var jit := Vector2(sin(g.t * 53.0), cos(g.t * 47.0)) * (2.0 if hw and not streams else 0.0)
		var line := ("海嗣注意到了你的存在……" if g.t < 240.0 else "海嗣自四方合围而来……") if streams or hunt_w else "大 群 来 袭"
		if ta > 0.0:
			UI.text(g.hud, g.font, Vector2(0, cy + 14) + jit, line, 38, Color(1.0, 0.75, 1.0, ta), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 6)
		if hw and hunt_w:
			# 围猎型（docs/150）：不画圈、不画四周箭头，只在缺口方向屏边画一个朝外的小箭头（突围方向）
			var gd := Vector2.from_angle(g.horde_gap)
			var gc := vs / 2.0
			var ge: Vector2 = gc + gd * min(abs((vs.x / 2 - 46) / max(abs(gd.x), 0.01)), abs((vs.y / 2 - 46) / max(abs(gd.y), 0.01)))
			var gs := gd.orthogonal() * 9.0
			var gt: Vector2 = ge + gd * (6.0 + 4.0 * pulse)
			g.hud.draw_colored_polygon(PackedVector2Array([gt, ge - gd * 6.0 + gs, ge - gd * 6.0 - gs]), Color(1.0, 0.85, 0.55, 0.55 + 0.35 * pulse))
		elif hw:
			if not streams:
				UI.en(g.hud, g.font, Vector2(vs.x / 2 - 130, cy - 40), "THE  SWARM  APPROACHES  ·  %d" % int(ceil(g.horde_warn)), 12, Color(0.85, 0.6, 1.0, ta), 3.0)
			# 四周方向警示箭头（向内）
			for j in 12:
				var ang := TAU * j / 12.0
				if absf(angle_difference(ang, g.horde_gap)) < deg_to_rad(40.0):
					continue  # 缺口方向不画箭头：那边没有敌人
				if not g.horde_streams.is_empty() and g.horde_streams.all(func(sa): return absf(angle_difference(ang, float(sa))) > deg_to_rad(35.0)):
					continue  # 分股合围：只在各股来向画箭头
				var dir := Vector2.from_angle(ang)
				var c := vs / 2.0
				var ed: Vector2 = c + dir * min(abs((vs.x / 2 - 40) / max(abs(dir.x), 0.01)), abs((vs.y / 2 - 40) / max(abs(dir.y), 0.01)))
				var tip: Vector2 = ed - dir * (10.0 + 8.0 * pulse)
				var sd := dir.orthogonal() * 12.0
				g.hud.draw_colored_polygon(PackedVector2Array([tip, ed + sd, ed - sd]), Color(0.9, 0.5, 1.0, 0.5 + 0.4 * pulse))

	# 分股合围：后几股出发前 0.8 秒，在它的来向屏边亮一组箭头（docs/116 §7.3）
	if not g.horde_stream_rel.is_empty() and not g.panel.visible:
		for i in mini(g.horde_stream_rel.size(), g.horde_streams.size()):
			var lead: float = float(g.horde_stream_rel[i]) - g.t
			if i == 0 or lead < 0.0 or lead > 0.8:
				continue
			var dir := Vector2.from_angle(float(g.horde_streams[i]))
			var c := vs / 2.0
			var ed: Vector2 = c + dir * min(abs((vs.x / 2 - 40) / max(abs(dir.x), 0.01)), abs((vs.y / 2 - 40) / max(abs(dir.y), 0.01)))
			var pk := 0.5 + 0.5 * sin(g.t * 18.0)
			for j in 3:
				var tip: Vector2 = ed - dir * (12.0 + 16.0 * j + 6.0 * pk)
				var sd := dir.orthogonal() * 14.0
				g.hud.draw_colored_polygon(PackedVector2Array([tip, tip + dir * 14.0 + sd, tip + dir * 14.0 - sd]), Color(1.0, 0.45, 0.9, 0.85 - 0.2 * j))

	# 屏幕边缘光只留最要紧的一种（EA 1.1：低血红暗角和圈外紫光叠在一起分不清）：生命垂危 > 圈外 > 溟痕 > 灯火低
	var low_hp: bool = g.state == Game.S.PLAY and g.hp < g.max_hp * 0.3 and g.hp > 0.0
	var zone_out: bool = g.zone_state != 0 and g.state == Game.S.PLAY and g.ppos.distance_to(g.zone_c) > g.zone_r
	# 溟痕：屏幕压暗 + 紫色边缘
	if g.in_mire > 0.0:
		g.hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.03, 0.0, 0.06, 0.18 * g.in_mire))
		if not low_hp and not zone_out:
			edge_glow(vs, Color(0.45, 0.1, 0.7, 0.8 * g.in_mire), 130.0)
		if g.in_mire > 0.5 and g.state == Game.S.PLAY:
			UI.text(g.hud, g.font, Vector2(0, vs.y * 0.5 + 84), "陷入溟痕：减速、持续受伤、累积神经损伤", 16, Color(0.85, 0.55, 1.0, g.in_mire), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 4)
	# Boss 换幕 / 倒下的全屏闪（world.watch_bosses）
	if g.world.scr_flash > 0.0:
		var fk: float = g.world.scr_flash / g.world.scr_flash_max
		var fc: Color = g.world.scr_flash_col
		g.hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(fc.r, fc.g, fc.b, 0.28 * fk * fk))
		edge_glow(vs, Color(fc.r, fc.g, fc.b, 0.8 * fk), 120.0)
	# 受击时屏幕边缘泛红
	if g.red_flash > 0.0:
		g.hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.8, 0.05, 0.1, g.red_flash * 0.16))
		edge_glow(vs, Color(0.9, 0.08, 0.12, g.red_flash * 0.9), 70.0)
	g.post.hurt = g.hurt_vignette
	if g.state == Game.S.PLAY and g.hp < g.max_hp * 0.3 and g.hp > 0.0:
		var beat := pow(maxf(0.0, sin(g.t * (5.0 + 5.0 * (1.0 - g.hp / (g.max_hp * 0.3))))), 4.0)
		edge_glow(vs, Color(0.85, 0.05, 0.12, 0.3 + 0.35 * beat), 110.0)
		UI.text(g.hud, g.font, Vector2(0, vs.y * 0.5 + 110), "生命垂危", 18, Color(1.0, 0.4, 0.45, 0.5 + 0.5 * beat), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 4)
	# 头顶血条：受伤后或低血量时显示
	var pool: float = g.corrode_pool
	if g.state == Game.S.PLAY and (g.head_bar_t > 0.0 or g.hp < g.max_hp * 0.3 or pool > 0.5):
		var hpos: Vector2 = ct * g.ppos + Vector2(-24, -104)
		var ha := clampf(g.head_bar_t / 0.5, 0.0, 1.0) if g.hp >= g.max_hp * 0.3 and pool <= 0.5 else 1.0
		g.hud.draw_rect(Rect2(hpos - Vector2(1, 1), Vector2(50, 7)), Color(0, 0, 0, 0.7 * ha))
		g.hud.draw_rect(Rect2(hpos, Vector2(48 * clampf(g.hp_trail / g.max_hp, 0.0, 1.0), 5)), Color(1, 0.95, 0.9, 0.9 * ha))
		g.hud.draw_rect(Rect2(hpos, Vector2(48 * clampf(g.hp / g.max_hp, 0.0, 1.0), 5)), Color(1.0, 0.3, 0.35, ha) if g.hp < g.max_hp * 0.3 else Color(0.35, 0.95, 0.75, ha))
		corrode_seg(Rect2(hpos, Vector2(48, 5)), ha)
	if g.lamp < 30.0 and g.state == Game.S.PLAY and not low_hp and not zone_out and g.in_mire <= 0.0:
		edge_glow(vs, Color(0.3, 0.0, 0.2, 0.25 + 0.1 * sin(g.t * 3.0)), 140.0)


## 飘字分层（docs/50 §13）：每个飘字是「4 像素描边 + 本体」两次画、字号还随弹出变，原来每个字至少两次绘制调用。
## 按原顺序给每个字分层：比它早、又和它外接框重叠的字里层号最大的那个 + 1。同层的字互不重叠，层内先画全部描边、再画全部本体，
## 同字号连着画；层按顺序画。所以重叠的两个字前后关系和原来一样，不重叠的谁先谁后都一样（画面不变）
func _dmg_numbers(dn: Array) -> void:
	var n: int = dn.size()
	var ci: CanvasItem = g.hud
	var fnt: Font = g.font
	var bbs: Array = []
	var lay := PackedInt32Array()
	lay.resize(n)
	var kss := PackedInt32Array()
	kss.resize(n)
	var maxl := 0
	for i in n:
		var it: Array = dn[i]
		var ks: int = UI._ks(ci, it[2])
		kss[i] = ks
		var wc = _numw.get(ks)
		if wc == null:
			wc = {}
			_numw[ks] = wc
			_numh[ks] = Vector2(fnt.get_ascent(ks), fnt.get_height(ks))
		var w = wc.get(it[1])
		if w == null:
			if wc.size() > 512:
				wc.clear()
			w = fnt.get_string_size(it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, ks).x
			wc[it[1]] = w
		var ah: Vector2 = _numh[ks]
		var p: Vector2 = it[0]
		var bb := Rect2(p.x + (120.0 - w) * 0.5 - 6.0, p.y - ah.x - 6.0, w + 12.0, ah.y + 12.0)
		var L := 0
		for j in i:
			if lay[j] >= L and (bbs[j] as Rect2).intersects(bb):
				L = lay[j] + 1
		lay[i] = L
		maxl = maxi(maxl, L)
		bbs.append(bb)
	# 同 UI.text(…, 描边 4)：描边色 = 黑、透明度 × 0.8。按 (层, 字号) 归组，一遍分好
	var order: Array = []   # 每层的组键（首次出现顺序）
	order.resize(maxl + 1)
	for L in maxl + 1:
		order[L] = []
	var grp := {}
	for i in n:
		var k: int = lay[i] * 1024 + kss[i]
		var a = grp.get(k)
		if a == null:
			a = []
			grp[k] = a
			order[lay[i]].append(k)
		a.append(dn[i])
	for L in maxl + 1:
		for k in order[L]:
			var ks: int = k % 1024
			for it in grp[k]:
				ci.draw_string_outline(fnt, it[0], it[1], HORIZONTAL_ALIGNMENT_CENTER, 120, ks, 4, Color(0, 0, 0, it[3].a * 0.8))
		for k in order[L]:
			var ks: int = k % 1024
			for it in grp[k]:
				ci.draw_string(fnt, it[0], it[1], HORIZONTAL_ALIGNMENT_CENTER, 120, ks, it[3])


var _numw := {}   # 字号 -> {字串: 宽}（飘字外接框用；数字常重复，省掉重复量字）
var _numh := {}   # 字号 -> Vector2(上沿高, 行高)


func draw_trial_result(vs: Vector2, won: bool) -> void:
	g.result_screen.draw(vs, "演练完成" if won else "演练结束", "BOSS TRIAL COMPLETE" if won else "BOSS TRIAL ENDED", UI.CYAN if won else UI.RED,
		[["重新演练", "R", "restart"], ["返回主页", "T", "title"]], false, false)


func edge_glow(vs: Vector2, col: Color, w: float) -> void:
	var c0 := col
	var c1 := Color(col.r, col.g, col.b, 0.0)
	# 合批（docs/50 §13）：四条渐变带一次提交（同样的三角化与顶点色）
	var tb := TriBatch.new()
	tb.polygon_colors(PackedVector2Array([Vector2.ZERO, Vector2(vs.x, 0), Vector2(vs.x, w), Vector2(0, w)]), PackedColorArray([c0, c0, c1, c1]))
	tb.polygon_colors(PackedVector2Array([Vector2(0, vs.y - w), Vector2(vs.x, vs.y - w), vs, Vector2(0, vs.y)]), PackedColorArray([c1, c1, c0, c0]))
	tb.polygon_colors(PackedVector2Array([Vector2.ZERO, Vector2(w, 0), Vector2(w, vs.y), Vector2(0, vs.y)]), PackedColorArray([c0, c1, c1, c0]))
	tb.polygon_colors(PackedVector2Array([Vector2(vs.x - w, 0), Vector2(vs.x, 0), vs, Vector2(vs.x - w, vs.y)]), PackedColorArray([c1, c0, c0, c1]))
	tb.flush(g.hud)


## 通用提示卡：贴在格子下方（越界时贴上方 / 左移），图标 + 标题 + 副标题 + 折行说明
func draw_tooltip(vs: Vector2, cr: Rect2, title: String, sub: String, desc: String, icon: String, col: Color, on: CanvasItem = null) -> void:
	var ci: CanvasItem = g.hud if on == null else on
	# 手机横屏（10-26 实机反馈）：框加宽、字放大到可读下限以上（正文 18 起，最小 16）
	var ph: bool = Cfg.phone_ui()
	var w := 460.0 if ph else 340.0
	# 说明按像素宽度折行（旧版按 26 个字硬切，13 号字会超出框）；太长先缩字号，整屏都放不下才截断
	var fd := UI.fit(g.font, desc, w - 28.0, vs.y - 24.0 - 74.0, [18, 17, 16] if ph else [13, 12, 11], 3.0)
	var h := (76.0 if ph else 66.0) + float(fd.h) + 12.0
	var pos := Vector2(clampf(cr.position.x, 12.0, vs.x - w - 12.0), cr.end.y + 8)
	if pos.y + h > vs.y - 12.0:
		pos.y = cr.position.y - h - 8
	pos.y = clampf(pos.y, 12.0, maxf(12.0, vs.y - h - 12.0))
	var r := Rect2(pos, Vector2(w, h))
	ci.draw_rect(Rect2(pos + Vector2(2, 2), Vector2(w - 4, h - 4)), Color(0.03, 0.035, 0.045, 0.96))
	UI.frame(ci, r, col)
	var tx0 := 14.0
	var ic: Texture2D = g.tex.get(icon) if icon != "" else null
	if ic != null:
		ci.draw_texture_rect(ic, Rect2(pos + Vector2(12, 12), Vector2(40, 40)), false)
		tx0 = 62.0
	UI.text_fit(ci, g.font, pos + Vector2(tx0, 30 if ph else 28), title, 20 if ph else 16, Color.WHITE, w - tx0 - 12.0, 12)
	UI.text_fit(ci, g.font, pos + Vector2(tx0, 54 if ph else 48), sub, 15 if ph else 12, col, w - tx0 - 12.0, 10)
	UI.draw_fit(ci, g.font, pos + Vector2(14, 72 if ph else 62), fd, Color(0.85, 0.92, 0.95))


## 精英标识（docs/48 P1 / 全局 ⑤）：原来只靠金色描边和脚下 alpha 0.12 的光晕，被灯光压暗、和友方金色撞色，
## 关掉「怪物轮廓光」就完全认不出。改在 HUD 层（不受光照）画：头顶一个橙红下箭头 + 3px 血条，不受轮廓光开关影响
const ELITE_COL := Color(1.0, 0.42, 0.25)

func draw_elite_marks(ct: Transform2D) -> void:
	if g.demo_op != "" or g.state == Game.S.SHOW:
		return
	var vs := g.hud.size
	var tb := Tris.new()   # 血条 + 三角一批提交（原来每只 4 次绘制调用）
	for e in g.enemies:
		if e.dead or not e.elite or e.boss or e.get("under", false):
			continue
		var sp: Vector2 = ct * (e.pos + Vector2(0, -e.r - 14.0))
		if sp.x < -40 or sp.y < -40 or sp.x > vs.x + 40 or sp.y > vs.y + 40:
			continue
		var w: float = maxf(24.0, e.r * 1.4)
		tb.rect(Rect2(sp + Vector2(-w / 2.0 - 1.0, -1.0), Vector2(w + 2.0, 5)), Color(0, 0, 0, 0.7))
		tb.rect(Rect2(sp + Vector2(-w / 2.0, 0), Vector2(w * clampf(e.hp / e.maxhp, 0.0, 1.0), 3)), ELITE_COL)
		var tip: Vector2 = sp + Vector2(0, -4)
		var bob: float = 2.0 * sin(g.t * 5.0 + e.id)
		var tri := PackedVector2Array([tip + Vector2(-6, -10 + bob), tip + Vector2(6, -10 + bob), tip + Vector2(0, -3 + bob)])
		tb.poly(PackedVector2Array([tri[0] + Vector2(-2, -1), tri[1] + Vector2(2, -1), tri[2] + Vector2(0, 2)]), Color(0, 0, 0, 0.7))
		tb.poly(tri, ELITE_COL)
	# Boss 头顶短血条（10-27 Boss 细血条改版：顶部细条之外，战场里一眼看出哪只是哪只、各剩多少；离屏不画）
	for b in g.bosses:
		if b.dead or b.get("friendly", false) or not D.ENEMIES[b.type].get("role", "") == "boss":
			continue
		var bp: Vector2 = ct * (b.pos + Vector2(0, -b.r - 22.0))
		if bp.x < -40 or bp.y < -40 or bp.x > vs.x + 40 or bp.y > vs.y + 40:
			continue
		var bw: float = 64.0
		tb.rect(Rect2(bp + Vector2(-bw / 2.0 - 1.0, -1.0), Vector2(bw + 2.0, 5)), Color(0, 0, 0, 0.7))
		tb.rect(Rect2(bp + Vector2(-bw / 2.0, 0), Vector2(bw * clampf(b.hp / maxf(1.0, b.maxhp), 0.0, 1.0), 3)), UI.RED)
	tb.flush(g.hud)


## 主控倒下后的过渡（2026-09-27 用户：结算弹得太快）：画面定格在倒下那一刻，约 2.4 秒（10-28 起，加最后一击定格 + 队友化光尘，docs/62 §3.21c）——
## 0–1.6 秒灯火熄灭（world 里灯光半径收到 0）、画面沉进深海色（整屏压暗 + 海水青黑暗角从四周合拢）；
## 1.3 秒起「探索终止」浮出（中文大字 + 英文 + 洋红细线从中间向两边展开）；2.4 秒后结算面板淡入。任意键 / 点击跳过（game.gd）
const DEATH_T := 2.4   # 10-28 退场演出（docs/62 §3.21c）：1.7 → 2.4

func draw_death_transition(vs: Vector2) -> void:
	# 最后一击：全屏红白一闪（run/defeat_outro.gd 同时放冲击环 + 火花）
	if g.state_age < 0.22:
		g.hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(1.0, 0.82, 0.78, 0.42 * (1.0 - g.state_age / 0.22)))
	var k: float = clampf(g.state_age / g.defeat_outro.DIM_T, 0.0, 1.0)
	var e: float = 1.0 - pow(1.0 - k, 2.0)
	g.hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.01, 0.03, 0.05, 0.62 * e))
	# 海水色暗角：四条边往里渐隐的青黑带，越来越厚
	var band: float = lerpf(0.0, minf(vs.x, vs.y) * 0.42, e)
	for i in 10:
		var f: float = float(i) / 10.0
		var w: float = band * (1.0 - f)
		var c := Color(0.0, 0.07, 0.09, 0.09 * e)
		g.hud.draw_rect(Rect2(0, 0, vs.x, w), c)
		g.hud.draw_rect(Rect2(0, vs.y - w, vs.x, w), c)
		g.hud.draw_rect(Rect2(0, 0, w, vs.y), c)
		g.hud.draw_rect(Rect2(vs.x - w, 0, w, vs.y), c)
	# 标题
	var ta: float = clampf((g.state_age - 1.3) / 0.5, 0.0, 1.0)
	if ta > 0.0:
		var cy: float = vs.y * 0.42
		var lw: float = 260.0 * (1.0 - pow(1.0 - ta, 3.0))
		g.hud.draw_rect(Rect2(vs.x / 2.0 - lw, cy + 14, lw * 2.0, 1), Color(UI.RED.r, UI.RED.g, UI.RED.b, 0.8 * ta))
		UI.text(g.hud, g.font, Vector2(0, cy - 4.0 + 8.0 * (1.0 - ta)), "探索终止", 40, Color(1, 1, 1, ta), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 6)
		var en := "OPERATION  FAILED"
		UI.en(g.hud, g.font, Vector2(vs.x / 2.0 - g.font.get_string_size(en, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x / 2.0 - 20.0, cy + 40), en, 13, Color(UI.RED.r, UI.RED.g, UI.RED.b, ta), 4.0)
	# 黑场：最后 0.5 秒压到结算底色（HH.DARK），结算从同一片暗处入场，不再闪亮一下
	var bk: float = clampf((g.state_age - (DEATH_T - 0.5)) / 0.5, 0.0, 1.0)
	if bk > 0.0:
		g.hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(Color8(19, 23, 30), bk * bk))
	# 右下角小字：可跳过
	if g.state_age > 0.3:
		UI.text(g.hud, g.font, Vector2(vs.x - 240, vs.y - 24), "点击跳过" if Pad.touch_ui() else "点击或按任意键跳过", 12, Color(1, 1, 1, 0.45), HORIZONTAL_ALIGNMENT_RIGHT, 220)


## 侵蚀待扣段（2026-09-27 协调人 / 数值）：侵蚀池 g.corrode_pool 里还没流出的量，画在血条当前值的末端往左、
## 长度 = min(侵蚀池, 当前生命)——这一截血「已经注定要掉」；暗紫底 + 洋红斜纹，斜纹缓缓右移、微微呼吸，随流出缩短，净化后消失
const CORRODE_COL := Color(0.62, 0.16, 0.72)
const CORRODE_HI := Color(1.0, 0.36, 0.86)

func corrode_seg(r: Rect2, a: float) -> void:
	var pool: float = minf(g.corrode_pool, g.hp)
	if pool <= 0.0 or g.max_hp <= 0.0:
		return
	var x1: float = r.position.x + r.size.x * clampf(g.hp / g.max_hp, 0.0, 1.0)
	var x0: float = maxf(r.position.x, x1 - r.size.x * pool / g.max_hp)
	if x1 - x0 < 1.0:
		x0 = x1 - 1.0   # 太少也留 1 像素，看得出「有」
	var y0: float = r.position.y
	var h: float = r.size.y
	var br: float = 0.8 + 0.2 * sin(g.t * 6.0)
	var tb: Tris = _hb if _hb != null else Tris.new()   # 左上面板里画时并进面板的批；头顶小条自己一批
	tb.rect(Rect2(x0, y0, x1 - x0, h), Color(CORRODE_COL.r, CORRODE_COL.g, CORRODE_COL.b, 0.95 * a))
	# 斜纹：每 4 像素一道，左下到右上；两端按段落裁切
	var ph: float = fmod(g.t * 6.0, 4.0)
	var sx: float = x0 - h - 4.0 + ph
	var hc := Color(CORRODE_HI.r, CORRODE_HI.g, CORRODE_HI.b, br * a)
	while sx < x1:
		var ax: float = sx
		var ay: float = y0 + h
		var bx: float = sx + h
		var by: float = y0
		if ax < x0:
			ay -= x0 - ax
			ax = x0
		if bx > x1:
			by += bx - x1
			bx = x1
		if bx > ax:
			tb.line(Vector2(ax, ay), Vector2(bx, by), hc, 1.2)
		sx += 4.0
	# 左端一道亮边：流失到这里为止
	tb.rect(Rect2(x0, y0 - 1, 1, h + 2), Color(CORRODE_HI.r, CORRODE_HI.g, CORRODE_HI.b, 0.9 * a))
	if tb != _hb:
		tb.flush(g.hud)


## 倒下过渡里灯火熄灭的时刻（灯光半径收到 0；音频 music_director 在这一刻播「灯灭」，引用本常量）
const DEATH_LAMP_T := 1.6


## 商人 / 事件界面把左半屏占满：这时不画声呐和状态小牌，免得从面板边上露出来
## 触屏选卡 / 商店 / 事件：面板标题压在顶栏位置（逻辑高只有约 481），顶部中央计时器、灯火状态行、Boss 血条不画，
## 免得从标题背后透出来（10-13 用户反馈「获得藏品」标题与计时器重叠）
func panel_over_top() -> bool:
	return g.touch.active and (g.state == Game.S.CHOICE or g.state == Game.S.SHOP)


## 手机横屏（10-26 用户 iPhone 实机「挤得太满」）：选卡 / 商店开着时，四周的声呐、藏品栏、编队栏、状态小牌都不画——
## 面板已经压暗了战斗，这些从卡片四周露出来只会挤。生命 / 灯火条照常（选卡时也要看血量）
func phone_quiet() -> bool:
	return Cfg.phone_ui() and panel_over_top()


func overlay_left() -> bool:
	return g.state == Game.S.SHOP or (g.state == Game.S.CHOICE and g.choice_kind == "event")


## 鼠标左键落在对局 HUD 上（mp 为界面坐标）：顶栏三块、藏品栏、暂停 / 倍速键、右下编队栏（含上方指挥模式与作战时限）、左下声呐。
## 点在这些地方不算点场地（doctor.click_skill：乌尔比安 S3 左键点击释放，10-26）。各块是缓存层、没有逐帧登记，这里按布局常量算外框，宁大勿小
func blocks_click(mp: Vector2) -> bool:
	var vs: Vector2 = g.hud.size
	for r in [g.speed_btn, g.pause_btn]:
		if (r as Rect2).has_area() and (r as Rect2).grow(6.0).has_point(mp):
			return true
	for c in g.tray_cells:
		if (c[0] as Rect2).grow(4.0).has_point(mp):
			return true
	if mp.y < 104.0 and (mp.x < 400.0 or mp.x > vs.x - 260.0 or absf(mp.x - vs.x * 0.5) < 190.0):
		return true
	var sw: float = maxf(maxi(1, g.squad.size()) * HudSquad.SQ_COL_W, 250.0) + 16.0
	if mp.x > vs.x - sw and mp.y > squad.squad_top(vs) - 44.0:
		return true
	var rad: float = 58.0 if Cfg.phone_ui() else 78.0   # 同 hud_bars.draw_minimap
	return mp.distance_to(Vector2(16.0 + rad + 8.0, vs.y - rad - 24.0)) < rad + 14.0
