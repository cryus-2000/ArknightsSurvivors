extends RefCounted
## 界面 · 选卡 / 商人面板的入场动效（docs/62 §3.11–3.15，第一批）：按面板种类分派，各种类一个主动作、不再共用同一条上浮。
## - level   升级选卡：卡背从牌堆发到卡位（−14° → 0°、0.6 → 1 倍）→ 依次横向翻成正面 → 描边青光闪一下（整段约 0.6 秒）
## - relic   藏品选择：卡位底边冲起竖直光柱（基础青白 / 稀有及以上金色 / 遭诅洋红），卡片从光里自下而上显出并上移 40 px；稀有及以上再脉冲一次
## - recruit 招募干员：卡框先出现 → 头像处画出部署格 → 待机帧从上方 70 px 加速落下、落地压扁、卡片轻抖 2 px → 落地环 → 名字说明淡入
## - shop    流浪商人：货架先全暗，商人灯笼每「一明」点亮一格（180 ms / 格），暖光从灯笼扫到这格；亮完灯笼缓慢呼吸。从第一帧起就能买
## - event   事件：仍是旧的「从右侧滑入」（第二批再换），只是改走这里的分派
## 约定（docs/62 §2）：计时用界面时钟 UM.now()（真实时间、暂停照走、不受对局倍速影响），不碰 g.rng；无头批跑直接终态；
## 卡片控件的位置 / 尺寸始终是终态（命中区按终态算），动画只在卡片自己的绘制里用 draw_set_transform 偏移；
## 动画进行中任意按键 / 点击 / 触屏 = 跳到终态（game.gd _input → skip()），不算选择。商人不拦输入。
## 减少动态效果（Cfg.reduce_motion）：卡片 120 ms 淡入，没有发牌 / 光柱 / 落下 / 灯笼闪；稀有藏品卡边框金色常亮；货架直接全亮。

const UI = preload("res://scripts/ui.gd")
const UM = preload("res://scripts/ui_motion.gd")
const Game = preload("res://scripts/game.gd")
var g: Game

var kind := ""        # 当前选卡面板的动效种类：level / relic / recruit / event
var t0 := 0.0         # 面板出现的界面时刻
var n := 0            # 卡片数
var skipped := false
var shop_t0 := -100.0 # 货架开始逐格点亮的时刻（打开商店 / 刷新货架时重置；买东西重建卡片不重置）

# 升级选卡：发牌 3 张错开 60 ms、每张 240 ms；翻面从 240 ms 起错开 70 ms、每张 180 ms（用户 10-11：整段约 0.6 秒，点一下跳过）
const DEAL_S := 0.06
const DEAL := 0.24
const FLIP0 := 0.24
const FLIP_S := 0.07
const FLIP := 0.18
# 藏品：错开 120 ms；光柱 180 ms 冲顶；卡片晚 60 ms 起 340 ms 显出；光柱 0.40 秒起 250 ms 退去；稀有及以上 0.80 秒处再脉冲 300 ms
const RL_S := 0.12
const RL_RISE := 0.18
const RL_CARD0 := 0.06
const RL_CARD := 0.34
const RL_OUT0 := 0.40
const RL_PULSE0 := 0.80
# 招募：错开 90 ms；卡框 120 ms；部署格 60 ms 起；落下 120 ms 起 180 ms；300 ms 落地（压扁 100、抖 80、落地环 280、文字 200）
const RC_S := 0.09
const RC_DROP0 := 0.12
const RC_LAND := 0.30
# 商人：灯笼先暗 150 ms，之后每 180 ms 点亮一格（用户 10-11），每格亮 110 ms
const SH_0 := 0.15
const SH_STEP := 0.18
const SH_ON := 0.11

## 光柱上升的光点（固定表，不碰随机数）：[横向位置 −1..1, 速度 px/s, 相位 0..1, 大小]
const MOTES := [[-0.62, 210.0, 0.05, 2.0], [0.35, 260.0, 0.41, 3.0], [-0.18, 190.0, 0.73, 2.0], [0.71, 240.0, 0.22, 2.0],
	[0.05, 300.0, 0.58, 3.0], [-0.44, 230.0, 0.9, 2.0], [0.52, 180.0, 0.33, 2.0], [-0.83, 280.0, 0.66, 2.0]]

# 本张卡在 draw_card 里要用的参数（begin() 设好，draw_card 读）
var icon_off := Vector2.ZERO
var icon_scale := Vector2.ONE
var icon_a := 1.0
var text_a := 1.0


func _init(game: Game) -> void:
	g = game


## 选卡面板出现（choice_panel.show_choices）：按选项定种类
func start(panel_kind: String, opts: Array) -> void:
	n = opts.size()
	t0 = UM.now()
	skipped = false
	if panel_kind == "event":
		kind = "event"
	elif panel_kind == "relic":
		kind = "relic"
	elif panel_kind == "cross":
		kind = "cross"   # 翻节点卡（docs/154）：背面朝上从下方依次升起，翻面由 choice_panel.draw_node_card 画
	elif not opts.is_empty() and opts.all(func(o): return o.get("kind", "") == "recruit"):
		kind = "recruit"
	else:
		kind = "level"


## 商店打开 / 刷新货架：货架从第一格重新点亮（买东西重建卡片时不调用）
func start_shop() -> void:
	shop_t0 = UM.now()


func _t() -> float:
	if skipped or UM.skip_all():
		return 99.0
	return UM.now() - t0


## 招牌动效的可交互部分是否还在进行（进行中输入 = 跳过）：只算升级 / 藏品 / 招募，减少动态时没有可跳的
func running() -> bool:
	if g.state != Game.S.CHOICE or not g.panel.visible or UM.rm() or skipped or UM.skip_all():
		return false
	if kind not in ["level", "relic", "recruit"]:
		return false
	return _t() < end_time()


func end_time() -> float:
	var last := maxi(0, n - 1)
	match kind:
		"level":
			return FLIP0 + UM.stagger(last, FLIP_S) + FLIP
		"relic":
			return UM.stagger(last, RL_S) + RL_CARD0 + RL_CARD
		"recruit":
			return UM.stagger(last, RC_S) + RC_LAND + 0.2
	return 0.0


func skip() -> void:
	skipped = true
	for c in g.panel_box.get_children():
		(c as CanvasItem).queue_redraw()
	g.panel_fg.queue_redraw()


# ----------------------------------------------------------------- 每帧（choice_panel.animate_cards）

func update(dt: float) -> void:
	var ev: bool = g.choice_kind == "event" and g.state == Game.S.CHOICE
	var box: BoxContainer = g.panel_col if ev else g.panel_box
	var shop: bool = g.state == Game.S.SHOP
	var t := _t()
	for card in box.get_children():
		if not card.has_meta("born"):
			continue
		var i: int = card.get_index()
		var sold: bool = card.has_meta("item") and card.get_meta("item").get("sold", false)
		var hot: bool = g.panel_ui.card_hot(card as Button, i) and not sold
		var lift: float = lerpf(card.get_meta("lift"), (-8.0 if ev else -10.0) if hot else 0.0, clampf(dt * 18.0, 0.0, 1.0))
		card.set_meta("lift", lift)
		if ev:
			# 事件选项条（第二批前保留旧动效）：从右侧 80 px 滑入（easeOutBack），悬停时向左探出一点
			var age := (Time.get_ticks_msec() - int(card.get_meta("born"))) / 1000.0
			var k := clampf(age / 0.32, 0.0, 1.0)
			var c1 := 1.7
			var e := 1.0 + (c1 + 1.0) * pow(k - 1.0, 3) + c1 * pow(k - 1.0, 2)
			card.modulate.a = clampf(age / 0.2, 0.0, 1.0)
			card.set_meta("ox", (1.0 - e) * 80.0 + lift)
		elif shop:
			card.modulate.a = 1.0
			card.set_meta("oy", lift)
		else:
			var a := 1.0
			var oy := 0.0
			if UM.rm():
				a = UM.rm_fade(t0)
			else:
				match kind:
					"level":
						a = clampf((t - UM.stagger(i, DEAL_S)) / 0.06, 0.0, 1.0)
					"relic":
						var s := UM.stagger(i, RL_S) + RL_CARD0
						a = 1.0 if t >= s else 0.0
						oy = roundf(40.0 * (1.0 - UM.out_cubic((t - s) / RL_CARD)))
					"recruit":
						a = clampf((t - UM.stagger(i, RC_S)) / UM.T1, 0.0, 1.0)
					"cross":
						a = 1.0   # 发牌 / 悬停 / 翻牌由 node_cards_ui.draw_card 自己画（docs/154）
						lift = 0.0
						card.set_meta("lift", 0.0)
			card.modulate.a = a
			card.set_meta("oy", oy + lift)
		card.queue_redraw()


# ----------------------------------------------------------------- 卡片绘制钩子（choice_panel.draw_card 开头 / 结尾）

## draw_card 开头调用：设好本卡的绘制变换与 icon_* / text_a；返回 true = 这一帧画卡背（draw_card 直接返回）
func begin(card: Button, i: int) -> bool:
	icon_off = Vector2.ZERO
	icon_scale = Vector2.ONE
	icon_a = 1.0
	text_a = 1.0
	if g.state != Game.S.CHOICE or UM.rm():
		return false
	var t := _t()
	var c: Vector2 = card.size / 2.0
	match kind:
		"level":
			var dp := UM.out_cubic((t - UM.stagger(i, DEAL_S)) / DEAL)
			var fe := UM.in_out_cubic((t - FLIP0 - UM.stagger(i, FLIP_S)) / FLIP)
			if dp >= 1.0 and fe >= 1.0:
				return false
			var deck := _panel_to_card(card, Vector2(g.panel.size.x / 2.0, g.panel.size.y + 80.0))
			var off := ((deck - c) * (1.0 - dp)).round()
			var rot := deg_to_rad(-14.0) * (1.0 - dp)
			var s := lerpf(0.6, 1.0, dp)
			var sx := maxf(0.02, absf(1.0 - 2.0 * fe))
			card.draw_set_transform_matrix(Transform2D(rot, Vector2(s * sx, s), 0.0, c + off) * Transform2D(0.0, Vector2.ONE, 0.0, -c))
			if fe < 0.5:
				_draw_back(card)
				card.draw_set_transform_matrix(Transform2D.IDENTITY)
				return true
		"recruit":
			var s0 := UM.stagger(i, RC_S)
			var dk := (t - s0 - RC_DROP0) / 0.18
			icon_a = 1.0 if dk > 0.0 else 0.0
			icon_off = Vector2(0.0, roundf(-70.0 * (1.0 - UM.in_quad(dk))))
			var sq := (t - s0 - RC_LAND) / 0.10
			if sq > 0.0 and sq < 1.0:
				var e := UM.out_cubic(sq)
				icon_scale = Vector2(lerpf(1.18, 1.0, e), lerpf(0.8, 1.0, e))
			text_a = clampf((t - s0 - RC_LAND) / 0.2, 0.0, 1.0)
			var sh := (t - s0 - RC_LAND) / 0.08
			if sh > 0.0 and sh < 1.0:
				card.draw_set_transform(Vector2(roundf(2.0 * sin(sh * PI * 3.0) * (1.0 - sh)), 0.0))
	return false


## draw_card 结尾调用：翻完的描边闪光、藏品卡的光幕、复位绘制变换
func end(card: Button, i: int, o: Dictionary) -> void:
	if g.state != Game.S.CHOICE:
		return
	var r := Rect2(Vector2(0, card.get_meta("oy", 0.0)), card.size)
	if UM.rm():
		if kind == "relic" and _rare(o) > 0:
			card.draw_rect(r, UI.GOLD, false, 1.0)   # 减少动态：稀有及以上的藏品卡边框金色常亮
		return
	var t := _t()
	match kind:
		"level":
			var fl := 1.0 - clampf((t - FLIP0 - UM.stagger(i, FLIP_S) - FLIP) / UM.T1, 0.0, 1.0)
			if fl > 0.0 and fl < 1.0:
				card.draw_rect(r.grow(1.0), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, fl), false, 2.0)
				card.draw_rect(r.grow(4.0), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.35 * fl), false, 3.0)
		"relic":
			# 卡片自下而上从光里显出：显出线以上还盖着光幕（柱色），线处 24 px 软边
			var e := UM.out_cubic((t - UM.stagger(i, RL_S) - RL_CARD0) / RL_CARD)
			if e < 1.0:
				var col := _pillar_col(o)
				var yl := r.position.y + r.size.y * (1.0 - e)
				var y0 := r.position.y - 2.0
				# 光幕上淡下浓（光从底下托上来），显出线处 24 px 软边；整体随显出逐渐变薄
				var thin := 1.0 - 0.35 * e
				var ct := Color(col.r, col.g, col.b, 0.5 * thin)
				var c0 := Color(col.r, col.g, col.b, 0.86 * thin)
				var c1 := Color(col.r, col.g, col.b, 0.0)
				var ya := maxf(y0, yl - 24.0)
				if ya > y0 + 1.0:
					card.draw_polygon(PackedVector2Array([Vector2(r.position.x - 2.0, y0), Vector2(r.end.x + 2.0, y0), Vector2(r.end.x + 2.0, ya), Vector2(r.position.x - 2.0, ya)]),
						PackedColorArray([ct, ct, c0, c0]))
				if yl > ya + 1.0:
					card.draw_polygon(PackedVector2Array([Vector2(r.position.x - 2.0, ya), Vector2(r.end.x + 2.0, ya), Vector2(r.end.x + 2.0, yl), Vector2(r.position.x - 2.0, yl)]),
						PackedColorArray([c0, c0, c1, c1]))
	card.draw_set_transform_matrix(Transform2D.IDENTITY)


## 招募卡：头像处的部署格（菱形）与落地环，画在待机帧之前；feet = 待机帧脚底（卡片坐标）
func draw_deploy(card: Button, i: int, feet: Vector2) -> void:
	if g.state != Game.S.CHOICE or kind != "recruit":
		return
	var t := 99.0 if UM.rm() else _t()
	var s0 := UM.stagger(i, RC_S)
	var ta := clampf((t - s0 - 0.06) / UM.T1, 0.0, 1.0)
	if ta <= 0.0:
		return
	var land := clampf((t - s0 - RC_LAND) / 0.3, 0.0, 1.0)
	var col := Color(0.55, 0.9, 0.55)
	var a: float = ta * lerpf(0.75, 0.35, land)   # 落地后部署格退成淡淡一层（终态也留着）
	var w := 46.0
	var h := 14.0
	var dm := PackedVector2Array([feet + Vector2(-w, 0), feet + Vector2(0, -h), feet + Vector2(w, 0), feet + Vector2(0, h)])
	card.draw_colored_polygon(dm, Color(col.r, col.g, col.b, 0.16 * a))
	card.draw_polyline(dm + PackedVector2Array([dm[0]]), Color(col.r, col.g, col.b, a), 1.0)
	var rg := (t - s0 - RC_LAND) / 0.28
	if rg > 0.0 and rg < 1.0:
		var e := UM.out_cubic(rg)
		card.draw_set_transform(feet, 0.0, Vector2(1.0, 0.32))
		card.draw_arc(Vector2.ZERO, lerpf(22.0, 84.0, e), 0.0, TAU, 40, Color(col.r, col.g, col.b, 0.9 * (1.0 - rg)), 2.0)
		card.draw_set_transform(Vector2.ZERO)


## 升级卡背：深色底 + 青色菱形徽 + LEVEL UP 小字
func _draw_back(card: Button) -> void:
	var r := Rect2(Vector2.ZERO, card.size)
	var top := Color(0.07, 0.1, 0.13, 0.98)
	var bot := Color(0.03, 0.045, 0.06, 0.98)
	card.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), PackedColorArray([top, top, bot, bot]))
	card.draw_rect(r, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.55), false, 1.0)
	card.draw_rect(r.grow(-8.0), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.18), false, 1.0)
	var c := r.get_center()
	for k in 4:
		var d := 70.0 - k * 16.0
		UI.diamond(card, c, d, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.04 + k * 0.03), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.25 + k * 0.15))
	UI.diamond(card, c, 9.0, UI.CYAN)
	var lw := UI.en_width(g.font, "LEVEL UP", 12, 4.0)
	UI.en(card, g.font, Vector2(c.x - lw / 2.0, c.y + 108.0), "LEVEL UP", 12, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.85), 4.0)


## 面板坐标 → 卡片本地坐标（界面层放大时也对）
func _panel_to_card(card: Control, p: Vector2) -> Vector2:
	return card.get_global_transform().affine_inverse() * (g.panel.get_global_transform() * p)


## 藏品稀有度档：0 基础 / 1 稀有及以上 / 2 遭诅古物
func _rare(o: Dictionary) -> int:
	if o.get("kind", "") != "relic" or not g.RL.has(o.get("id", "")):
		return 0
	var rar: String = g.RL[o.id].get("rarity", "")
	if rar == "遭诅古物":
		return 2
	return 0 if rar in ["基础", "—", ""] else 1


func _pillar_col(o: Dictionary) -> Color:
	match _rare(o):
		1:
			return Color(1.0, 0.82, 0.42)
		2:
			return Color(1.0, 0.36, 0.62)
	return Color(0.78, 0.97, 1.0)


# ----------------------------------------------------------------- 压暗带之上、卡片之下（choice_panel.draw_bg 末尾）

## 藏品光柱：每个卡位底边冲起一道竖直光柱（三层渐变 + 上升光点），稀有及以上 0.8 秒处再脉冲一次
func draw_under(ci: Control) -> void:
	if g.state != Game.S.CHOICE or kind != "relic" or UM.rm():
		return
	var t := _t()
	if t >= 99.0:
		return
	var inv := ci.get_global_transform().affine_inverse()
	for card in g.panel_box.get_children():
		if not (card is Button) or card.is_queued_for_deletion():
			continue
		var i: int = card.get_index()
		if i >= g.choices.size():
			continue
		var o: Dictionary = g.choices[i]
		var s := UM.stagger(i, RL_S)
		var q := UM.out_cubic((t - s) / RL_RISE)
		if q <= 0.0:
			continue
		var fade := 1.0 - UM.out_cubic((t - s - RL_OUT0) / 0.25)
		var pk := (t - s - RL_PULSE0) / 0.3
		var pulse := sin(pk * PI) if (pk > 0.0 and pk < 1.0 and _rare(o) > 0) else 0.0
		var a := maxf(fade, 0.85 * pulse)
		if a <= 0.0:
			continue
		var gr: Rect2 = inv * (card as Control).get_global_rect()
		var col := _pillar_col(o)
		var bot := gr.end.y + 8.0
		var top := bot - (gr.size.y + 130.0) * q
		var cx := gr.get_center().x
		for L in [[1.15, 0.2], [0.6, 0.36], [0.22, 0.75]]:
			var hw: float = gr.size.x * 0.5 * float(L[0])
			var cb := Color(col.r, col.g, col.b, float(L[1]) * a)
			var ct := Color(col.r, col.g, col.b, 0.0)
			ci.draw_polygon(PackedVector2Array([Vector2(cx - hw, top), Vector2(cx + hw, top), Vector2(cx + hw, bot), Vector2(cx - hw, bot)]), PackedColorArray([ct, ct, cb, cb]))
		ci.draw_rect(Rect2(cx - gr.size.x * 0.5, bot - 2.0, gr.size.x, 2.0), Color(col.r, col.g, col.b, 0.9 * a))
		var hgt := bot - top
		for m in MOTES:
			var y := bot - fmod(float(m[1]) * maxf(0.0, t - s) + float(m[2]) * hgt, maxf(1.0, hgt))
			var mk := (y - top) / maxf(1.0, hgt)
			ci.draw_rect(Rect2(Vector2(cx + float(m[0]) * gr.size.x * 0.42, y).round(), Vector2(m[3], m[3])), Color(1, 1, 1, 0.8 * a * mk))


# ----------------------------------------------------------------- 商人：灯笼明暗，货架逐格亮起

## 第 i 格的状态：[已亮 0/1, 亮起时的暖白闪光 0..1, 顶边金线 0..1]
func shop_cell(i: int) -> Array:
	if UM.rm() or UM.skip_all():
		return [1.0, 0.0, 0.0]
	var tl := UM.now() - shop_t0 - SH_0 - i * SH_STEP
	if tl < 0.0:
		return [0.0, 0.0, 0.0]
	return [1.0, 1.0 - clampf(tl / UM.T1, 0.0, 1.0), 1.0 - UM.out_cubic(tl / 0.45)]


## 货品卡结尾：未亮的格子压暗（价格条照常可见）、亮起一闪 + 顶边金线
func shop_card_post(card: Button, i: int) -> void:
	var st := shop_cell(i)
	var r := Rect2(Vector2(0, card.get_meta("oy", 0.0)), card.size)
	if st[0] < 1.0:
		card.draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y - 46.0)), Color(0.015, 0.018, 0.024, 0.78))
		card.draw_rect(r, Color(1, 1, 1, 0.16), false, 1.0)
		return
	if st[1] > 0.0:
		card.draw_rect(r, Color(1.0, 0.93, 0.78, 0.32 * st[1]))
	if st[2] > 0.0:
		card.draw_rect(Rect2(r.position, Vector2(r.size.x, 2.0)), Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, st[2]))


## 灯笼此刻是否「明」：每格点亮的那 110 ms 亮；亮完之后由呼吸接管
func shop_lantern() -> Dictionary:
	var n_items: int = g.shop_items.size()
	if UM.rm() or UM.skip_all():
		return {"bright": false, "glow": 0.5, "beam": -1, "beam_a": 0.0}
	var t := UM.now() - shop_t0 - SH_0
	if t < 0.0:
		return {"bright": false, "glow": 0.0, "beam": -1, "beam_a": 0.0}
	var i := int(floorf(t / SH_STEP))
	var ph := t - i * SH_STEP
	if i < n_items:
		var on := ph < SH_ON
		return {"bright": on, "glow": 0.9 if on else 0.25, "beam": i, "beam_a": 1.0 - clampf(ph / 0.16, 0.0, 1.0)}
	return {"bright": false, "glow": 0.5 + 0.3 * sin((t - n_items * SH_STEP) * 2.2), "beam": -1, "beam_a": 0.0}


## 商人身前货物上一圈暖光 + 扫向那一格的光（10-21 坎诺特重绘去掉提灯，覆盖帧停用）；
## dst = 商人立绘这一帧画在 ci 上的矩形，fr = 商人帧
func draw_shop_lantern(ci: Control, dst: Rect2, _fr: int) -> void:
	var st := shop_lantern()
	var lp := dst.position + Vector2(37.0, 30.0) / 48.0 * dst.size   # 货物在 48×48 商人帧里的位置
	var warm := Color(1.0, 0.72, 0.36)
	var glow: float = st.glow
	for k in 4:
		ci.draw_circle(lp, 34.0 - k * 7.0, Color(warm.r, warm.g, warm.b, (0.05 + 0.04 * k) * glow))
	var bi: int = st.beam
	if bi >= 0 and bi < g.panel_box.get_child_count() and float(st.beam_a) > 0.0:
		var card: Control = g.panel_box.get_child(bi)
		var gr: Rect2 = ci.get_global_transform().affine_inverse() * card.get_global_rect()
		var tp := Vector2(gr.get_center().x, gr.position.y + 4.0)
		var d := (tp - lp).normalized().orthogonal()
		var a: float = 0.4 * float(st.beam_a)
		ci.draw_polygon(PackedVector2Array([lp + d * 2.0, lp - d * 2.0, tp - d * 30.0, tp + d * 30.0]),
			PackedColorArray([Color(warm.r, warm.g, warm.b, a), Color(warm.r, warm.g, warm.b, a), Color(warm.r, warm.g, warm.b, 0.0), Color(warm.r, warm.g, warm.b, 0.0)]))
