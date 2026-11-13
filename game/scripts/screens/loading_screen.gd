extends Control
## 选人出发 → 进局的载入页「潮汐航标」（用户 10-25 定：对照图方向 A 的第一张）。
## 深海底图 + 水母随呼吸浮沉 + 标志；进度是一道涨潮浪线：进度每涨一截就有一道浪头推过去，先冲过头一点再退回真实进度（docs/62 §3.7）；
## 下方提示（loading_tips.gd）每 3.5 秒换一句（T2 淡入淡出）。「减少动态效果」：水母不动、浪线平直、提示直接替换。
## 只管画面：进度、阶段文字由 title.gd 每帧 set_progress 喂进来；finish() 后压暗到 OUT_DIM 并显示「展开战场」，title.gd 等 done() 再切场景。
## 切场景时对局 _ready 还要同步建局几秒（画面停在最后一帧），所以不淡到全黑——停在压暗的载入页上，对局开场从黑里亮起。素材全用标题页已有的 art/ui/title_deep（不加包体）。

const UI = preload("res://scripts/ui.gd")
const UM = preload("res://scripts/ui_motion.gd")
const Tips = preload("res://scripts/screens/loading_tips.gd")
const DIR := "res://art/ui/title_deep/"

var font: Font
var tex_bg: Texture2D
var tex_jelly: Array = []
var tex_glow: Array = []
var tex_logo: Texture2D
var glow_ci: Control          # 水母辉光：叠加混合单独一层
var vignette: GradientTexture2D

var t := 0.0                  # 显示了多久
var fade_in := 0.35           # 淡入时长（从选人 / 难度页上盖过来）
var out_t := -1.0             # finish() 后的淡出计时；< 0 = 没在淡出
const OUT_LEN := 0.28
const OUT_DIM := 0.45         # 切场景前压暗到多少（建局期间停住的那一帧）
var target := 0.0             # 真实进度 0–1
var shown := 0.0              # 浪头位置
var wave_from := 0.0          # 当前这道浪的起点
var wave_to := 0.0
var wave_t := -1.0            # 当前这道浪走了多久；< 0 = 没有浪
const WAVE_LEN := 0.5
var stage := ""
var count := Vector2i.ZERO
var tip_i := 0
var tip_t := 0.0
const TIP_EVERY := 3.5


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = load("res://fonts/ui.ttf")
	tex_bg = load(DIR + "bg.png")
	for i in 3:
		tex_jelly.append(load(DIR + "jelly_%d.png" % i))
		tex_glow.append(load(DIR + "jglow_%d.png" % i))
	tex_logo = load(DIR + "logo_mark.png")
	vignette = GradientTexture2D.new()
	vignette.fill = GradientTexture2D.FILL_RADIAL
	vignette.fill_from = Vector2(0.5, 0.42)
	vignette.fill_to = Vector2(1.05, 1.0)
	var g := Gradient.new()
	g.set_color(0, Color(0, 0.04, 0.08, 0.0))
	g.set_color(1, Color(0, 0.01, 0.03, 0.92))
	g.add_point(0.6, Color(0, 0.02, 0.05, 0.55))
	vignette.gradient = g
	glow_ci = Control.new()
	glow_ci.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow_ci.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow_ci.material = m
	glow_ci.draw.connect(_draw_glow)
	add_child(glow_ci)   # 一建好就挂上（在 _draw 之后画：辉光叠在底图与水母上）。以前到 begin() 才挂：没出发就退出时它是孤儿节点，
	                     # 连同叠加材质的着色器一起泄漏，打包校验报 RID leaked（10-25）
	tip_i = randi() % Tips.TIPS.size()
	visible = false


func begin() -> void:
	preload("res://scripts/core/frame_rec.gd").mark("loading")   # 帧时记录（--ftrec）：进局载入页开始
	visible = true
	t = 0.0
	out_t = -1.0
	target = 0.0
	shown = 0.0
	wave_t = -1.0
	tip_t = 0.0


## 真实进度（0–1）、阶段文字、阶段计数（done / total；total 0 = 不显示计数）
func set_progress(f: float, what: String, n: Vector2i) -> void:
	target = maxf(target, clampf(f, 0.0, 1.0))
	stage = what
	count = n


## 进度满后压暗、阶段改「展开战场」；done() 为真时再切场景
func finish() -> void:
	if out_t < 0.0:
		out_t = 0.0
		target = 1.0
		stage = "展开战场"
		count = Vector2i.ZERO


## 进局后的接续层（game.gd cover_begin）：直接显示压暗的「展开战场 100%」，不淡入、浪头不动
func hold() -> void:
	begin()
	fade_in = 0.0
	target = 1.0
	shown = 1.0
	stage = "展开战场"
	out_t = OUT_LEN
	set_process(false)
	queue_redraw()


func done() -> bool:
	return out_t >= OUT_LEN and (wave_t < 0.0 or out_t > 1.0)   # 等浪头推到满格


func _process(delta: float) -> void:
	if not visible:
		return
	t += delta
	if out_t >= 0.0:
		out_t += delta
	var rm: bool = Cfg.reduce_motion
	if rm:
		shown = target
	else:
		# 浪：进度涨过一截（或上一道浪推完还落后）就起一道新浪，从当前位置 out_back 推到真实进度
		if wave_t < 0.0 and target - shown > 0.004:
			wave_from = shown
			wave_to = target
			wave_t = 0.0
		if wave_t >= 0.0:
			wave_t += delta
			var k := wave_t / WAVE_LEN
			shown = lerpf(wave_from, wave_to, UM.out_back(k, 1.2))
			if k >= 1.0:
				shown = wave_to
				wave_t = -1.0
	tip_t += delta
	if tip_t >= TIP_EVERY:
		tip_t = 0.0
		tip_i = (tip_i + 1) % Tips.TIPS.size()
	queue_redraw()
	glow_ci.queue_redraw()


## 整体透明度：淡入 × 淡出（淡出是往黑里压，见 _draw 末尾）
func _alpha() -> float:
	return clampf(t / fade_in, 0.0, 1.0) if fade_in > 0.0 else 1.0


## 版式缩放：以 1280×720 为基准
func _k(vs: Vector2) -> float:
	return minf(vs.x / 1280.0, vs.y / 720.0)


func _jelly_rects(vs: Vector2) -> Array:
	var k := _k(vs)
	var rm: bool = Cfg.reduce_motion
	var bob := 0.0 if rm else sin(t * 1.15) * 7.0 * k
	var pulse := 0.0 if rm else sin(t * 1.15 + 0.6) * 0.025
	var c := Vector2(vs.x * 0.5, vs.y * 0.3)
	var s0 := Vector2(129, 139) * 1.6 * k
	var s0p := Vector2(s0.x * (1.0 + pulse), s0.y * (1.0 - pulse))
	var b1 := 0.0 if rm else sin(t * 0.9 + 2.0) * 5.0 * k
	var b2 := 0.0 if rm else sin(t * 1.3 + 4.0) * 4.0 * k
	return [
		Rect2(c - s0p / 2.0 + Vector2(0, bob), s0p),
		Rect2(Vector2(vs.x * 0.715, vs.y * 0.305 + b1), Vector2(34, 52) * 1.6 * k),
		Rect2(Vector2(vs.x * 0.267, vs.y * 0.365 + b2), Vector2(24, 36) * 2.0 * k),
	]


func _draw() -> void:
	var vs := size
	var a := _alpha()
	var k := _k(vs)
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.01, 0.03))
	# 深海底图（428×240 像素图，铺满后压暗）
	var bk := maxf(vs.x / 428.0, vs.y / 240.0)
	var bs := Vector2(428, 240) * bk
	draw_texture_rect(tex_bg, Rect2((vs - bs) / 2.0, bs), false, Color(0.55, 0.55, 0.58, a))
	draw_texture_rect(vignette, Rect2(Vector2.ZERO, vs), false, Color(1, 1, 1, a))
	# 水母（远处两只淡一些）
	var jr := _jelly_rects(vs)
	draw_texture_rect(tex_jelly[1], jr[1], false, Color(1, 1, 1, 0.55 * a))
	draw_texture_rect(tex_jelly[2], jr[2], false, Color(1, 1, 1, 0.6 * a))
	draw_texture_rect(tex_jelly[0], jr[0], false, Color(1, 1, 1, 0.95 * a))
	# 标志
	var ls := Vector2(482, 86) * k
	draw_texture_rect(tex_logo, Rect2(Vector2(vs.x / 2.0 - ls.x / 2.0, vs.y * 0.628), ls), false, Color(1, 1, 1, a))
	var lx: float = 24 * k + Cfg.edge_l()   # 触屏让开左侧灵动岛 / 圆角（桌面 0）
	var ew := UI.en(self, font, Vector2(lx, 32 * k), "ARKNIGHTS FAN GAME", 11, Color(0.5, 0.64, 0.69, a), 4.0)
	UI.text(self, font, Vector2(lx + ew + 14.0, 33 * k), "明日方舟同人作品 · 非商业", 11, Color(0.5, 0.64, 0.69, a))
	_draw_tide(vs, k, a)
	# 提示（T2 淡入淡出；减少动态时直接替换）
	var ta := a
	if not Cfg.reduce_motion:
		ta *= clampf(tip_t / UM.T2, 0.0, 1.0) * clampf((TIP_EVERY - tip_t) / UM.T2, 0.0, 1.0)
	var tip: String = Tips.TIPS[tip_i]
	var tw: float = font.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 52.0
	var tx := vs.x / 2.0 - tw / 2.0
	var ty := vs.y * 0.935
	UI.en(self, font, Vector2(tx, ty), "TIPS", 12, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, ta), 2.0)
	UI.text(self, font, Vector2(tx + 52.0, ty), tip, 14, Color(0.66, 0.76, 0.79, ta))
	if out_t >= 0.0:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.01, 0.03, OUT_DIM * clampf(out_t / OUT_LEN, 0.0, 1.0)))


## 潮线（11-07 用户「进入游戏加载页的海洋可以改一下」：原来一条平直青线 + 一小段鼓包，简陋）：改成像素海面，同标题页深海水母的 3 像素格——
## 三层起伏的波线（后浅前深：后层淡青细浪、中层、前层深青实水面），每层波峰一格亮像素、下面填水体；进度 = 一盏航标灯随前层浪浮沉、
## 从左往右走，走过的海面点亮（波峰转青、偶有白沫，水下透青光走 glow 层），没走到的灰蓝暗着；百分比 / 阶段照旧在下面一行。
## 只用 draw_rect（不加图）；「减少动态效果」：浪不动、灯不晃
const TIDE_LAYERS := [
	# [层顶偏移（格）, 振幅（格）, 每格相位, 速度, 亮色, 暗色, 水体色, 水体透明度]
	[-8, 2.5, 0.2, 0.9, Color(0.62, 0.9, 0.94), Color(0.32, 0.43, 0.52), Color(0.1, 0.3, 0.4), 0.16],
	[-4, 3.0, 0.13, -1.3, Color(0.36, 0.88, 0.9), Color(0.25, 0.35, 0.44), Color(0.05, 0.2, 0.28), 0.4],
	[0, 2.0, 0.09, 1.7, Color(0.18, 0.72, 0.78), Color(0.18, 0.27, 0.35), Color(0.02, 0.09, 0.14), 0.92],
]
const TIDE_DEPTH := 8   # 水面以下画几格（前层水体到这儿）
var tide_m := 1.0      # 矮屏缩放（_tide_geom 设）

func _tide_geom(vs: Vector2, k: float) -> Array:
	var c: float = maxf(3.0, roundf(3.0 * k))   # 一格的屏幕像素（同标题页 3 像素格；大屏按版式放大，手机竖屏也不小于 3）
	var x0: float = floorf(vs.x * 0.125 / c) * c
	var x1: float = floorf(vs.x * 0.875 / c) * c
	var y: float = floorf(vs.y * 0.8 / c) * c
	tide_m = clampf(vs.y / 720.0, 0.5, 1.0)   # 矮屏（手机横屏 390 高）层距 / 振幅 / 水深按比例收，不顶到标志、不压提示
	return [c, x0, x1, y]


func _depth() -> int:
	return int(roundf(float(TIDE_DEPTH) * tide_m))


## 第 L 层第 i 列的波峰高度（格，向上为负）
func _crest(L: int, i: int, rm: bool) -> int:
	var ly: Array = TIDE_LAYERS[L]
	var ph: float = float(i) * float(ly[2]) + (0.0 if rm else t * float(ly[3])) + float(L) * 1.7
	return int(roundf(float(ly[0]) * tide_m)) - int(roundf(float(ly[1]) * tide_m * (sin(ph) * 0.7 + sin(ph * 0.43 + 1.1) * 0.3)))


func _draw_tide(vs: Vector2, k: float, a: float) -> void:
	var gm := _tide_geom(vs, k)
	var c: float = gm[0]
	var x0: float = gm[1]
	var x1: float = gm[2]
	var y: float = gm[3]
	var rm: bool = Cfg.reduce_motion
	var n: int = int((x1 - x0) / c)
	var lit_n: int = int(roundf(clampf(shown, 0.0, 1.0) * float(n)))
	var fade_n := 10   # 两头淡出的列数
	for L in TIDE_LAYERS.size():
		var ly: Array = TIDE_LAYERS[L]
		for i in n:
			var e: float = clampf(minf(float(i + 1), float(n - i)) / float(fade_n), 0.0, 1.0)
			var cr: int = _crest(L, i, rm)
			var x: float = x0 + float(i) * c
			var lit: bool = i < lit_n
			var wc: Color = ly[6]
			wc.a = float(ly[7]) * e * a * (1.0 if L == 2 else (1.0 if lit else 0.7))
			draw_rect(Rect2(x, y + float(cr + 1) * c, c, float(_depth() - cr - 1) * c), wc)
			var cc: Color = ly[4] if lit else ly[5]
			cc.a = e * a * (0.55 + 0.15 * float(L) if lit else 0.35 + 0.1 * float(L))
			draw_rect(Rect2(x, y + float(cr) * c, c, c), cc)
			# 白沫：点亮的浪头，波峰最高处偶尔一格白（按列号与时间节拍，不取随机数）
			if lit and L > 0 and not rm and cr <= int(roundf(float(ly[0]) * tide_m)) - 1 and (i * 7 + int(t * 6.0) + L * 3) % 11 == 0:
				draw_rect(Rect2(x, y + float(cr - 1) * c, c, c), Color(0.9, 1.0, 1.0, 0.85 * e * a))
	# 航标灯：随前层浪浮沉，灯在顶上；进度 0 时停在起点
	var bi: int = clampi(lit_n, 0, n - 1)
	var bx: float = x0 + float(bi) * c
	var by: float = y + float(_crest(2, bi, rm) - 1) * c
	var post := Color(0.05, 0.09, 0.13, a)
	draw_rect(Rect2(bx - c * 2.0, by - c * 6.0, c * 5.0, c * 7.0), Color(0.02, 0.05, 0.08, 0.8 * a))   # 灯塔身（深色描边）
	draw_rect(Rect2(bx - c, by - c * 5.0, c * 3.0, c * 6.0), post.lightened(0.18))
	draw_rect(Rect2(bx, by - c * 5.0, c, c * 6.0), post.lightened(0.32))   # 迎光面
	draw_rect(Rect2(bx - c * 2.0, by, c * 5.0, c), post.lightened(0.15))   # 浮台
	draw_rect(Rect2(bx - c, by - c * 3.0, c * 3.0, c), Color(0.36, 0.88, 0.9, 0.5 * a))   # 腰带
	var blink: float = 1.0 if rm else 0.75 + 0.25 * sin(t * 5.0)
	draw_rect(Rect2(bx - c, by - c * 7.0, c * 3.0, c * 2.0), Color(0.03, 0.07, 0.1, a))   # 灯室
	draw_rect(Rect2(bx, by - c * 7.0, c, c * 2.0), Color(0.92, 1.0, 1.0, a * blink))   # 灯
	var cy := UI.CYAN
	cy.a = a
	var ly2 := y + float(_depth()) * c + 14.0 * k
	UI.en(self, font, Vector2(x0, ly2), "LOADING", 11, cy, 4.0)
	UI.text(self, font, Vector2(x0 + 84.0, ly2), stage, 13, Color(0.62, 0.72, 0.75, a))
	var rt := "%d%%" % int(round(clampf(target, 0.0, 1.0) * 100.0))
	if count.y > 0:
		rt += "　%d / %d" % [count.x, count.y]
	UI.text(self, font, Vector2(x1 - 300.0, ly2), rt, 13, Color(0.62, 0.72, 0.75, a), HORIZONTAL_ALIGNMENT_RIGHT, 300.0)


## 叠加层：点亮的海面下透青光（三层渐淡的格带）+ 航标灯的光晕（十字 + 方块，像素格）
func _draw_tide_glow(a: float) -> void:
	var vs := size
	var k := _k(vs)
	var gm := _tide_geom(vs, k)
	var c: float = gm[0]
	var x0: float = gm[1]
	var x1: float = gm[2]
	var y: float = gm[3]
	var rm: bool = Cfg.reduce_motion
	var n: int = int((x1 - x0) / c)
	var lit_n: int = int(roundf(clampf(shown, 0.0, 1.0) * float(n)))
	if lit_n > 0:
		var w: float = float(lit_n) * c
		for r in 3:
			draw_glow_rect(Rect2(x0, y + float(1 + r) * c, w, c), Color(0.1, 0.42, 0.48) * (a * (0.55 - 0.17 * float(r))))
	var bi: int = clampi(lit_n, 0, n - 1)
	var bx: float = x0 + float(bi) * c
	var by: float = y + float(_crest(2, bi, rm) - 8) * c
	var blink: float = 1.0 if rm else 0.75 + 0.25 * sin(t * 5.0)
	var gc := Color(0.25, 0.75, 0.8) * (a * blink)
	draw_glow_rect(Rect2(bx - c, by - c, c * 3.0, c * 3.0), gc * 0.8)
	draw_glow_rect(Rect2(bx - c * 3.0, by, c * 7.0, c), gc * 0.45)
	draw_glow_rect(Rect2(bx, by - c * 3.0, c, c * 7.0), gc * 0.45)
	draw_glow_rect(Rect2(bx - c * 2.0, by - c * 2.0, c * 5.0, c * 5.0), gc * 0.18)


func draw_glow_rect(r: Rect2, col: Color) -> void:
	col.a = 1.0
	glow_ci.draw_rect(r, col)


func _draw_glow() -> void:
	var vs := size
	var a := _alpha()
	if out_t >= 0.0:
		a *= 1.0 - OUT_DIM * clampf(out_t / OUT_LEN, 0.0, 1.0)
	var jr := _jelly_rects(vs)
	var breathe := 1.0 if Cfg.reduce_motion else 0.85 + 0.15 * sin(t * 1.15 + 0.6)
	var cols := [Color(0.25, 0.55, 0.75), Color(0.18, 0.4, 0.55), Color(0.18, 0.4, 0.55)]
	for i in 3:
		var r: Rect2 = jr[i]
		var g: Texture2D = tex_glow[i]
		var gs := Vector2(g.get_width(), g.get_height()) * (r.size.x / float(tex_jelly[i].get_width()))
		var c: Color = cols[i] * (a * breathe)
		c.a = 1.0
		glow_ci.draw_texture_rect(g, Rect2(r.get_center() - gs / 2.0, gs), false, c)
	_draw_tide_glow(a)
