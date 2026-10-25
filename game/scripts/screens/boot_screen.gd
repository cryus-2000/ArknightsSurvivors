extends Control
## 启动页「声呐测绘」（用户 10-25 定：对照图方向 C 第一张；10-25 追加「启动中要有百分比，并说明在读什么」）。
## 主场景是 boot.tscn（本脚本），只依赖字体、标志与提示表，几十毫秒就能画出来；然后按 data/boot_order.json
## （tools/gen_boot_order.py 生成，叶子在前）逐个 load() 标题页带出的脚本与资源——每个只编译它自己，进度是真实的，
## 同时显示正在读哪一类（干员积木 / 海嗣 / 战场渲染 …）和文件名。全部读完再读 main.tscn（此时都在缓存里），淡到黑后切到标题页。
## 以前这一段（桌面调试版 8–12 秒、网页十几秒）全在 Godot 静态启动图下面，没有进度。
## 引擎初始化与自动加载（Sfx / Cfg …）在本页之前，仍由静态启动图（art/ui/boot_splash.png，同一版式）盖着。
## 网页：前面还有 HTML 加载页（tools/web/loader.js，下载占 0–60%、引擎启动 60–80%），这里接着它的百分比走、不倒退；
## 本页第一帧画完就通知它淡出（__syBootUp），不再等引擎自带的 #status 撤掉（那要到标题页出来以后）。
## 测试（带命令行参数、无界面）直接切标题页，不走本页；--bootshot / --loadprof 才走（--bootshot 在读到一半时截图退出）。

const Tips = preload("res://scripts/screens/loading_tips.gd")
const FR = preload("res://scripts/core/frame_rec.gd")
const ORDER := "res://data/boot_order.json"
const MAIN := "res://main.tscn"
const BUDGET_USEC := 30000   # 每帧最多读多久（单个脚本超过也只读这一个）
const CYAN := Color(0.369, 0.902, 0.902)
const TEXT := Color(0.949, 0.957, 0.961)
const DIM := Color(0.5, 0.6, 0.65)
const OUT_LEN := 0.3

var font: Font
var tex_logo: Texture2D
var bg: GradientTexture2D
var items: Array = []         # [[路径, 类别], …]
var idx := 0
var cur_label := "启动引擎"
var cur_file := ""
var main_scene: PackedScene
var base := 0.0               # 网页从 HTML 加载页的 80% 接着走
var t := 0.0
var out_t := -1.0
var tip_i := 0
var tip_t := 0.0
var shot := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var args := Cfg.dev_args()
	shot = args.has("--bootshot")
	if DisplayServer.get_name() == "headless" or (not args.is_empty() and not shot and not args.has("--loadprof") and not args.has("--ftrec")):
		get_tree().change_scene_to_file.call_deferred(MAIN)   # 测试直接进标题页
		set_process(false)
		return
	if args.has("--loadprof"):
		print("BOOTPROF boot_ready=%d" % Time.get_ticks_msec())
	FR.mark("boot")
	font = load("res://fonts/ui.ttf")
	var img: Image = load("res://art/ui/title_deep/logo_mark.png").get_image()
	img.generate_mipmaps()
	tex_logo = ImageTexture.create_from_image(img)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # 标志缩小显示；其余都是矢量图形
	bg = GradientTexture2D.new()
	bg.fill = GradientTexture2D.FILL_RADIAL
	bg.fill_from = Vector2(0.5, 0.5)
	bg.fill_to = Vector2(1.1, 1.1)
	var g := Gradient.new()
	g.set_color(0, Color8(13, 24, 32))
	g.set_color(1, Color8(4, 7, 10))
	g.add_point(0.7, Color8(7, 12, 17))
	bg.gradient = g
	if OS.has_feature("web"):
		# 接着 HTML 加载页的进度走（loader.js 的 __syPct，缺省 80%），第一帧画完后让它淡出，露出这一页
		var v = JavaScriptBridge.eval("window.__syPct || 0.8", true)
		base = clampf(float(v) if v != null else 0.8, 0.0, 0.95)
		RenderingServer.frame_post_draw.connect(func(): JavaScriptBridge.eval("window.__syBootUp && window.__syBootUp()", true), CONNECT_ONE_SHOT)
	var f := FileAccess.open(ORDER, FileAccess.READ)
	if f != null:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			items = d.get("items", [])
	tip_i = randi() % Tips.TIPS.size()


func _process(delta: float) -> void:
	t += delta
	tip_t += delta
	if tip_t >= 4.0:
		tip_t = 0.0
		tip_i = (tip_i + 1) % Tips.TIPS.size()
	if out_t >= 0.0:
		out_t += delta
		if out_t >= OUT_LEN:
			if Cfg.dev_args().has("--loadprof"):
				print("BOOTPROF boot_done=%d" % Time.get_ticks_msec())
			set_process(false)
			get_tree().change_scene_to_packed(main_scene)
		queue_redraw()
		return
	if t > 0.05:   # 先让第一帧画出来
		if idx < items.size():
			var t0 := Time.get_ticks_usec()
			while idx < items.size() and (idx == 0 or Time.get_ticks_usec() - t0 < BUDGET_USEC):
				var it: Array = items[idx]
				cur_file = str(it[0]).get_file()
				cur_label = str(it[1])
				if ResourceLoader.exists(str(it[0])):
					var l0 := Time.get_ticks_usec()
					load(str(it[0]))
					if FR.enabled() and Time.get_ticks_usec() - l0 > 40000:
						print("PF FTLOAD %s %.0f ms" % [str(it[0]), (Time.get_ticks_usec() - l0) / 1000.0])
				idx += 1
				if shot and idx == items.size() / 2:
					break
			if shot and idx == items.size() / 2:
				_shot()
		elif main_scene == null:
			cur_label = "标题页"
			cur_file = MAIN.get_file()
			main_scene = load(MAIN)
		else:
			out_t = 0.0
	queue_redraw()


func _shot() -> void:
	var dir := "/tmp/claude-0"
	for a in Cfg.dev_args():
		if a.begins_with("--shotdir="):
			dir = a.substr(10)
	set_process(false)
	queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir + "/shot_boot.png")
	get_tree().quit()


## 进度 0–1：脚本占 95%，最后读标题页场景 5%
func _progress() -> float:
	var f := 0.0
	if not items.is_empty():
		f = 0.95 * float(idx) / float(items.size())
	if main_scene != null:
		f = 1.0
	return base + (1.0 - base) * f


func _txt(pos: Vector2, s: String, sz: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	draw_string(font, pos, s, align, w, sz, col)


func _en_w(s: String, sz: int, sp: float) -> float:
	var w := 0.0
	for ch in s:
		w += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x + sp
	return w - sp


## 拉丁小字加字距（同标题页英文标签的写法）
func _en(pos: Vector2, s: String, sz: int, col: Color, sp := 3.0, center := false) -> void:
	var w := _en_w(s, sz, sp)
	var x := pos.x - (w / 2.0 if center else 0.0)
	for ch in s:
		draw_string(font, Vector2(x, pos.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x + sp


func _draw() -> void:
	if font == null:
		return
	var vs := size
	draw_texture_rect(bg, Rect2(Vector2.ZERO, vs), false)
	var gc := Color(0.47, 0.67, 0.75, 0.05)
	var gx := 0.0
	while gx < vs.x:
		draw_line(Vector2(gx, 0), Vector2(gx, vs.y), gc, 1.0)
		gx += 24.0
	var gy := 0.0
	while gy < vs.y:
		draw_line(Vector2(0, gy), Vector2(vs.x, gy), gc, 1.0)
		gy += 24.0
	var compact := vs.y <= 520.0
	# 标志、页眉
	var lw := minf(300.0 if not compact else 200.0, vs.x * 0.38)
	draw_texture_rect(tex_logo, Rect2(Vector2(40, 36) if not compact else Vector2(20, 16), Vector2(lw, lw * 86.0 / 482.0)), false)
	if vs.x > 700:
		var fan := "ARKNIGHTS FAN GAME"
		var fw := _en_w(fan, 11, 4.0)
		_en(Vector2(vs.x - (40 if not compact else 20) - fw, 54 if not compact else 30), fan, 11, Color(0.5, 0.6, 0.64), 4.0)
	_draw_sonar(vs)
	_draw_panels(vs, compact)
	_txt(Vector2(0, vs.y - (16 if not compact else 8)), "明日方舟同人作品 · 非商业 · 与鹰角网络无关", 11, Color(0.44, 0.52, 0.56), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	if out_t >= 0.0:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, clampf(out_t / OUT_LEN, 0.0, 1.0)))


func _draw_sonar(vs: Vector2) -> void:
	var w := minf(400.0, minf(vs.y * 0.52, vs.x * 0.6))
	var u := w / 420.0
	var c := Vector2(vs.x / 2.0, vs.y * 0.45)
	for r in [180.0, 120.0, 60.0]:
		draw_arc(c, r * u, 0.0, TAU, 96, Color8(42, 60, 70) if r == 180.0 else Color8(31, 46, 54), 1.0, true)
	draw_line(c + Vector2(-190, 0) * u, c + Vector2(190, 0) * u, Color8(26, 39, 46), 1.0)
	draw_line(c + Vector2(0, -190) * u, c + Vector2(0, 190) * u, Color8(26, 39, 46), 1.0)
	# 扫描扇面：3.2 秒一圈，前沿亮、往后淡（减少动态：停在固定角度）
	var ang := -0.35 if Cfg.reduce_motion else fmod(t / 3.2, 1.0) * TAU
	var pts := PackedVector2Array([c])
	var cols := PackedColorArray([Color(CYAN, 0.0)])
	for i in 13:
		var a := ang - PI / 4.0 + (PI / 4.0) * i / 12.0
		pts.append(c + Vector2(cos(a), sin(a)) * 180.0 * u)
		cols.append(Color(CYAN, 0.32 * i / 12.0))
	draw_polygon(pts, cols)
	# 回波点：扇面扫过时亮起再淡出
	for b in [Vector2(70, -96), Vector2(-110, 40), Vector2(30, 130), Vector2(-60, -120)]:
		var ba := atan2(b.y, b.x)
		var since := fposmod(ang - ba, TAU) / TAU
		var al := 0.6 if Cfg.reduce_motion else clampf(1.0 - since * 1.6, 0.0, 1.0)
		draw_circle(c + b * u, 3.0 * u, Color(CYAN, al))
	# 进度环
	var p := _progress()
	draw_arc(c, 192.0 * u, 0.0, TAU, 128, Color8(29, 42, 50), 6.0 * u, true)
	if p > 0.0:
		draw_arc(c, 192.0 * u, -PI / 2.0, -PI / 2.0 + TAU * p, maxi(8, int(128 * p)), CYAN, 6.0 * u, true)
	for k in 4:
		var d := Vector2.from_angle(k * PI / 2.0)
		draw_line(c + d * 200.0 * u, c + d * 210.0 * u, Color8(59, 79, 90), 1.5)
	# 圈心：百分比 + SONAR · BOOT
	var big := int(maxf(28.0, 64.0 * u))
	var num := str(int(floor(p * 100.0)))
	var nw := font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
	var pw := font.get_string_size("%", HORIZONTAL_ALIGNMENT_LEFT, -1, int(big * 0.38)).x
	var nx := c.x - (nw + pw + 2.0) / 2.0
	_txt(Vector2(nx, c.y + big * 0.32), num, big, TEXT)
	_txt(Vector2(nx + nw + 2.0, c.y + big * 0.32), "%", int(big * 0.38), CYAN)
	_en(Vector2(c.x, c.y + big * 0.32 + 26.0 * u + 6.0), "SONAR · BOOT", 11, CYAN, 3.0, true)
	# 圈下：正在读什么
	var ty := c.y + 210.0 * u + 30.0
	var what := "读取 · " + cur_label if out_t < 0.0 else "打开标题页"
	_txt(Vector2(0, ty), what, 15, TEXT, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	if out_t < 0.0 and not items.is_empty():
		_txt(Vector2(0, ty + 20.0), "%s　%d / %d" % [cur_file, mini(idx + 1, items.size()), items.size()], 11, DIM, HORIZONTAL_ALIGNMENT_CENTER, vs.x)


func _draw_panels(vs: Vector2, compact: bool) -> void:
	var pw := minf(330.0 if not compact else 260.0, vs.x * (0.3 if not compact else 0.27))
	var ph := 190.0 if not compact else 120.0
	var by := vs.y - (50.0 if not compact else 30.0) - ph
	var mx := 40.0 if not compact else 20.0
	var lh := 22.0 if not compact else 17.0
	var fs := 13 if not compact else 11
	for r in [Rect2(mx, by, pw, ph), Rect2(vs.x - mx - pw, by, pw, ph)]:
		draw_rect(r, Color(0.055, 0.086, 0.11, 0.82))
		draw_rect(r, Color8(38, 53, 64), false, 1.0)
		draw_line(r.position + Vector2(0, 26), r.position + Vector2(r.size.x, 26), Color8(38, 53, 64), 1.0)
	_en(Vector2(mx + 12, by + 18), "TERMINAL LOG", 11, Color(0.56, 0.65, 0.69), 3.0)
	_en(Vector2(vs.x - mx - pw + 12, by + 18), "TIPS", 11, Color(0.56, 0.65, 0.69), 3.0)
	# 日志：网页先列 HTML 加载页做完的三步
	var lines: Array = []
	if OS.has_feature("web"):
		lines.append([1, "下载资源"])
		lines.append([1, "解压校验"])
	lines.append([1, "启动引擎"])
	var scripts_done := idx >= items.size()
	lines.append([1 if scripts_done else 0, "编译脚本　%d / %d" % [mini(idx, items.size()), items.size()]])
	lines.append([1 if out_t >= 0.0 else (0 if scripts_done else -1), "打开标题页"])
	var y := by + 26 + lh
	for ln in lines:
		var st: int = ln[0]
		var tag: String = "[ OK ]" if st == 1 else ("[ .. ]" if st == 0 else "[ -- ]")
		var col: Color = Color(0.62, 0.7, 0.73) if st == 1 else (TEXT if st == 0 else Color(0.27, 0.33, 0.36))
		_txt(Vector2(mx + 12, y), tag, fs, CYAN if st == 1 else col)
		_txt(Vector2(mx + 12 + (48 if not compact else 40), y), str(ln[1]), fs, col)
		y += lh
	# 提示：自动换行
	var ta := 1.0 if Cfg.reduce_motion else clampf(tip_t / 0.22, 0.0, 1.0) * clampf((4.0 - tip_t) / 0.22, 0.0, 1.0)
	# 网页包没有中文断词数据（只按空格断，整句不换行冲出面板）：允许按字断（ADAPTIVE：放得下的词不拆）
	var brk := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_GRAPHEME_BOUND | TextServer.BREAK_ADAPTIVE
	draw_multiline_string(font, Vector2(vs.x - mx - pw + 12, by + 26 + lh), Tips.TIPS[tip_i], HORIZONTAL_ALIGNMENT_LEFT, pw - 24, fs, -1, Color(0.71, 0.78, 0.8, ta), brk)
