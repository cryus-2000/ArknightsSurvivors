extends Control
## 局外 · 蚀刻章页「深蓝之下」（10-25 Codex 交付 art/incoming/achievement_ui_1024/，判定 core/medals.gd，章表 data/medals.json）。
## 用户：「改成我们的像素风格并且保持一致，背景设置成动态效果，字体也是需要修改」；之后「把这一页再重新排版一下，相信你自己的审美」。
## 版式 v2「陈列柜」（设计坐标 1280×720，data/medals_layout.json；整幅按窗口等比缩放居中，让开安全区）：
## - 顶栏：左「‹ 蚀刻章 MEDALS」返回，右一行操作提示。
## - 左栏 = 套组：套组章「深蓝之下」作徽记（最大）→ 衬线大标题 → 像素英文 → 已获得数 + 九格进度。左右栏之间一条细竖线。
## - 右侧 = 两层陈列：「结局 ENDINGS」四枚（大）、「探索 EXPLORATION」四枚（中），同列对齐；每层一个组小标题（同标题菜单：青短竖条 + 中文 + 英文）+ 渐隐细线；
##   章下写名称，多步的章没拿到时再写像素进度。
## - 底栏 = 选中章的记录：名称 + 状态、条件；右侧像素格进度条、当前 / 目标、获得日期。
## 像素：章图与背景都按标题页「青光航标」的精度（1280×720 下 3 逻辑像素一格，docs/67 §13.3），bake_pixel.py 烘焙；未获得用暗钢蓝版。
## 背景：原图低频形变（shaders/medal_sea.gdshader，SubViewport 428×240，≤ 30 Hz，24 秒一周期）；减少动态效果只画静帧；页面关着不更新。
## 字：中文 ui.ttf，套组大标题 serif.ttf；拉丁 / 数字一律 5×7 像素字（tide_ui.ptext）。颜色沿用标题菜单（青只给可操作 / 选中）。
## 入场（docs/62）：徽记 → 结局层 → 探索层依次淡入（每枚错开 0.04 秒），不位移；减少动态效果一起 0.12 秒淡入。
## 操作：点章 / 方向键选中（按几何方向找最近的一枚）；左上返回 / Esc / 退格返回。
signal closed

const Medals = preload("res://scripts/core/medals.gd")
const TUI = preload("res://scripts/screens/tide_ui.gd")
const Tiles = preload("res://scripts/screens/title_jelly_menu.gd")
const UI = preload("res://scripts/ui.gd")

const CANVAS := Vector2(1280, 720)
const LAYOUT := "res://data/medals_layout.json"
const DIR := "res://art/ui/medals/"
const BG_GRID := Vector2i(428, 240)
const BG_PAD := 6
const HZ := 30.0
const RX0 := 506.0          # 右侧陈列区左右边（设计坐标）
const RX1 := 1184.0
const STRIP_Y := 612.0      # 底栏分隔线
const C := Tiles.C
const T := Tiles.T
const M := Tiles.M
const L := Tiles.L

var font: Font
var serif: Font
var grid := 3.0
var rows: Array = []
var items: Array = []          # [{def, c: 设计坐标中心, r, row（-1 = 徽记）, tex, off, ring}]
var sel := 0
var hover := -1
var k := 1.0
var off := Vector2.ZERO
var back_rect := Rect2()
var back_hot := false           # 鼠标停在返回上（只跟鼠标移动走：截图 / 触屏不显示悬停）
var open_t := 0.0
var bg_paused := false          # 测试 / 截图用：背景停在当前帧
var _vp: SubViewport
var _mat: ShaderMaterial
var _bg: TextureRect
var _clock := 0.0
var _acc := 0.0
var _still := -1.0
var _rings := {}               # 美术像素边长 → 六边形描边贴图
## 帧时测量（--medalperf，tools/perf_web.py 网页口径）：同一会话里背景动 / 静每 2 秒轮换（各段丢掉开头 10 帧），24 秒后打一行 PERF 退出
var perf_t := -1.0
var _perf := {"medal_bg": [], "medal_still": []}
var _perf_dc := {"medal_bg": [], "medal_still": []}
var _perf_us := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = load("res://fonts/ui.ttf")
	serif = load("res://fonts/serif.ttf")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_make_bg()
	_load_items()
	hide()


func _make_bg() -> void:
	_vp = SubViewport.new()
	_vp.size = BG_GRID
	_vp.disable_3d = true
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var rect := ColorRect.new()
	rect.size = Vector2(BG_GRID)
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/medal_sea.gdshader")
	_mat.set_shader_parameter("src", load(DIR + "bg_src.png"))
	var pal: Texture2D = load(DIR + "bg_pal.png")
	_mat.set_shader_parameter("pal", pal)
	_mat.set_shader_parameter("pal_n", pal.get_width())
	_mat.set_shader_parameter("grid", Vector2(BG_GRID))
	_mat.set_shader_parameter("pad", float(BG_PAD))
	rect.material = _mat
	_vp.add_child(rect)
	_bg = TextureRect.new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_bg.texture = _vp.get_texture()
	_bg.show_behind_parent = true
	add_child(_bg)


## 版式按 data/medals_layout.json 的顺序（徽记 → 结局层 → 探索层），入场错开也按这个顺序
func _load_items() -> void:
	var lay = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	if not (lay is Dictionary):
		return
	grid = float(lay.get("grid", 3))
	rows = lay.get("rows", [])
	for m in lay.get("medals", []):
		var d := Medals.def_by_id(int(m.id))
		if d.is_empty():
			continue
		var tex: Texture2D = load(DIR + "medal_%d.png" % int(m.id))
		items.append({"def": d, "c": Vector2(float(m.center[0]), float(m.center[1])), "r": float(m.radius), "row": int(m.get("row", -1)),
			"tex": tex, "off": load(DIR + "medal_%d_off.png" % int(m.id)), "ring": _ring(tex.get_width())})


## 选中描边：比章大 2 格的六边形外圈，1 格宽（按章的美术像素网格，与章图同一套像素）
func _ring(n: int) -> Texture2D:
	if _rings.has(n):
		return _rings[n]
	var w := n + 4
	var im := Image.create(w, w, false, Image.FORMAT_RGBA8)
	for y in w:
		for x in w:
			var p := Vector2(x + 0.5 - w / 2.0, y + 0.5 - w / 2.0)
			if _in_hex(p, n / 2.0 + 2.0) and not _in_hex(p, n / 2.0 + 1.0):
				im.set_pixel(x, y, Color.WHITE)
	var t := ImageTexture.create_from_image(im)
	_rings[n] = t
	return t


## 尖顶六边形（与 bake_pixel.py 的遮罩同一判定）
static func _in_hex(p: Vector2, r: float) -> bool:
	var dx := absf(p.x)
	var dy := absf(p.y)
	return dx <= r * cos(PI / 6.0) and dy + dx * tan(PI / 6.0) <= r


func open() -> void:
	Medals.sync()   # 打开时按当前记录补判一次（旧存档补录也在读档时做过）
	sel = maxi(0, _index_of("set_complete"))
	hover = -1
	open_t = 0.0
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	show()


func close() -> void:
	hide()
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	closed.emit()


func _index_of(key: String) -> int:
	for i in items.size():
		if items[i].def.key == key:
			return i
	return -1


func _process(delta: float) -> void:
	if not visible:
		return
	if perf_t >= 0.0:
		_perf_tick(delta)
	open_t += delta
	var still := 1.0 if Cfg.reduce_motion else 0.0
	if still != _still:
		_still = still
		_mat.set_shader_parameter("still", still)
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	if still < 0.5 and not bg_paused:
		_clock += delta
		_acc += delta
		if _acc >= 1.0 / HZ - 0.002:
			_acc = 0.0
			_mat.set_shader_parameter("time", fmod(_clock, 24.0 * 300.0))   # 24 秒的整数倍取模：周期不断、长挂机浮点精度不变差
			_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	queue_redraw()


func _perf_tick(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var seg := int(perf_t / 2.0)
	var key := "medal_still" if seg % 2 == 1 else "medal_bg"
	bg_paused = seg % 2 == 1
	if _perf_us > 0 and perf_t >= 2.0 and fmod(perf_t, 2.0) > 10.0 / 60.0:
		_perf[key].append((now - _perf_us) / 1000.0)
		_perf_dc[key].append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	_perf_us = now
	perf_t += delta
	if perf_t >= 26.0:
		var out := {}
		for k2 in _perf:
			var a: Array = _perf[k2].duplicate()
			a.sort()
			var dc: Array = _perf_dc[k2].duplicate()
			dc.sort()
			var n := a.size()
			if n == 0:
				continue
			var sum := 0.0
			var over := 0
			for v in a:
				sum += v
				if v > 16.7:
					over += 1
			out[k2] = {"n": n, "ft_mean": sum / n, "ft_med": a[n / 2], "ft_p95": a[mini(n - 1, int(n * 0.95))], "ft_p99": a[mini(n - 1, int(n * 0.99))],
				"over16_pct": 100.0 * over / n, "en_med": 0, "dc_med": dc[dc.size() / 2]}
		print("PERF " + JSON.stringify(out))
		get_tree().quit()


# ---------------------------------------------------------------- 版式
func _fit() -> void:
	var ins: Array = Cfg.safe_insets()
	var avail := Rect2(Vector2(ins[0], ins[1]), size - Vector2(ins[0] + ins[2], ins[1] + ins[3]))
	k = minf(avail.size.x / CANVAS.x, avail.size.y / CANVAS.y)
	off = avail.position + (avail.size - CANVAS * k) / 2.0


func _P(x: float, y: float) -> Vector2:
	return off + Vector2(x, y) * k


## 字号：设计字号 → 实际（手机上字太小时放大一档，最低 11）
func _F(fs: float) -> int:
	return maxi(11, int(round(fs * k * _tk())))


## 手机 / 小窗口：文字放大（设计 1 像素 < 0.95 实际像素时，最多 1.35 倍）
func _tk() -> float:
	return clampf(0.95 / k, 1.0, 1.35)


func _txt(p: Vector2, s: String, fs: int, col: Color, f: Font = null, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> float:
	var ff: Font = f if f != null else font
	draw_string(ff, p, s, align, w, fs, col)
	return ff.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


func _tw(s: String, fs: int, f: Font = null) -> float:
	return (f if f != null else font).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


func _spaced_w(s: String, fs: int, sp: float, f: Font) -> float:
	var w := 0.0
	for ch in s:
		w += f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + sp
	return w - sp


## 等字距一行（中心对齐），p.y 是基线
func _spaced(p: Vector2, s: String, fs: int, col: Color, sp: float, f: Font) -> void:
	var x := p.x - _spaced_w(s, fs, sp, f) / 2.0
	for ch in s:
		draw_string(f, Vector2(x, p.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		x += f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + sp


## 整页淡入（减少动态效果 0.12 秒）
func _a() -> float:
	return clampf(open_t / (0.12 if Cfg.reduce_motion else 0.25), 0.0, 1.0)


## 第 i 枚章的入场淡入：按版式顺序错开 0.04 秒，每枚 0.25 秒
func _ia(i: int) -> float:
	if Cfg.reduce_motion:
		return _a()
	return clampf((open_t - 0.06 - 0.04 * i) / 0.25, 0.0, 1.0)


func _fa(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)


func _draw() -> void:
	_fit()
	var a := _a()
	var tc := TUI.ctx(self)
	_draw_bar(tc, a)
	_draw_set(tc, a)
	_draw_rows(tc, a)
	_draw_medals(tc)
	_draw_detail(tc, a)


func _draw_medals(tc: Dictionary) -> void:
	for i in items.size():
		var it: Dictionary = items[i]
		var ia := _ia(i)
		if ia <= 0.0:
			continue
		var got := Medals.has(it.def.key)
		var tex: Texture2D = it.tex if got else it.off
		var n := float(tex.get_width())
		var s := n * grid * k
		var c: Vector2 = _P(it.c.x, it.c.y)
		draw_texture_rect(tex, Rect2(c - Vector2(s, s) / 2.0, Vector2(s, s)), false, Color(1, 1, 1, ia))
		if i == sel or i == hover:
			var rs := (n + 4.0) * grid * k
			draw_texture_rect(it.ring, Rect2(c - Vector2(rs, rs) / 2.0, Vector2(rs, rs)), false, _fa(C if i == sel else Color(M, 0.7), ia))
		if int(it.row) < 0:
			continue
		# 陈列层的章：下方名称；多步的章没拿到时再写一行像素进度
		var nc: Color = C if i == sel else (T if got else M)
		var ny: float = it.c.y + it.r + 28.0
		var nfs := _F(15)
		_txt(_P(it.c.x, ny) - Vector2(_tw(str(it.def.name), nfs) / 2.0, 0), str(it.def.name), nfs, _fa(nc, ia))
		var pr := Medals.progress(it.def)
		if not got and int(pr[1]) > 1:
			TUI.ptext(self, tc, _P(it.c.x, ny + 17.0 * _tk()), "%d / %d" % [pr[0], pr[1]], 1.2 * k * _tk(), _fa(Color(M, 0.85), ia), 1, 1)


## 顶栏：左返回（像素「<」+ 蚀刻章 + MEDALS），右操作提示（像素小菱形 + 一句话）
func _draw_bar(tc: Dictionary, a: float) -> void:
	var fs := _F(20)
	var y := _P(0, 46).y
	var x0 := _P(48, 0).x
	var col := C if back_hot else T
	TUI.ptext(self, tc, Vector2(x0, y - fs * 0.34), "<", 2.4 * k * _tk(), _fa(col, a))
	var tx := x0 + 18.0 * k * _tk()
	var w := _txt(Vector2(tx, y), "蚀刻章", fs, _fa(col, a))
	var ew := TUI.ptext(self, tc, Vector2(tx + w + 12.0 * k, y - fs * 0.34), "MEDALS", 1.3 * k * _tk(), _fa(M, a), 2)
	back_rect = Rect2(Vector2(x0 - 14.0 * k, y - fs - 12.0 * k), Vector2(tx - x0 + w + ew + 40.0 * k, fs + 26.0 * k))
	if back_rect.size.y < 44.0 and Cfg.touch_device():
		back_rect = back_rect.grow_individual(0, (44.0 - back_rect.size.y) / 2.0, 0, (44.0 - back_rect.size.y) / 2.0)
	var s: String = Pad.hint("选择蚀刻章查看记录 · ESC 返回", "选择蚀刻章查看记录 · Ⓑ 返回", "点按蚀刻章查看记录")
	var hfs := _F(13)
	var hx := _P(1232, 0).x
	var hw := _tw(s, hfs)
	_txt(Vector2(hx - hw, y), s, hfs, _fa(M, a * 0.9))
	TUI.pdiamond(self, tc, Vector2(hx - hw - 14.0 * k, y - hfs * 0.36), 3, TUI.cell(tc, maxf(1.0, k)), _fa(C, a))


## 左栏套组：徽记（章本身在 _draw_medals 画）→ 深蓝之下 → BENEATH THE BLUE → 蚀刻章套组 → 已获得数 → 九格
func _draw_set(tc: Dictionary, a: float) -> void:
	var tk := _tk()
	var cx := 240.0
	# 左右栏之间的细竖线（上下渐隐成两段短线）
	var lx := _P(426, 0).x
	draw_line(Vector2(lx, _P(0, 150).y), Vector2(lx, _P(0, 610).y), _fa(Color(L, 0.45), a), 1.0)
	var top := _P(cx, 448)
	_spaced(top, str(Medals.data().get("set_name", "深蓝之下")), _F(54), _fa(Color(0.94, 0.965, 0.98), a), 6.0 * k, serif)
	var ly := top.y + 20.0 * k * tk
	var lw := 236.0 * k
	draw_line(Vector2(top.x - lw / 2.0, ly), Vector2(top.x + lw / 2.0, ly), _fa(L, a), maxf(1.0, k))
	draw_rect(Rect2(Vector2(top.x - lw / 2.0, ly - maxf(1.0, k)), Vector2(22.0 * k, maxf(2.0, 2.0 * k))), _fa(C, a))
	TUI.ptext(self, tc, Vector2(top.x, ly + 20.0 * k * tk), str(Medals.data().get("set_en", "")), 1.6 * k * minf(tk, 1.1), _fa(M, a), 3, 1)
	var sy := ly + 62.0 * k * tk
	_spaced(Vector2(top.x, sy), "蚀刻章套组", _F(15), _fa(T, a), 5.0 * k, font)
	# 已获得数（像素大数字）+ 九格
	var n := Medals.earned_count()
	var tot := Medals.defs().size()
	var cy := sy + 34.0 * k * tk
	var ks := 2.6 * k * tk
	var s1 := "%02d" % n
	var s2 := " / %02d" % tot
	var w1 := TUI.ptext_w(tc, s1, ks)
	var w2 := TUI.ptext_w(tc, s2, ks)
	var gapw: float = TUI.cell(tc, ks) * 2.0 / float(tc.k)
	var x: float = top.x - (w1 + w2 + gapw) / 2.0
	TUI.ptext(self, tc, Vector2(x, cy), s1, ks, _fa(C if n > 0 else M, a))
	TUI.ptext(self, tc, Vector2(x + w1 + gapw, cy), s2, ks, _fa(M, a))
	var cw := 18.0 * k
	var gap := maxf(2.0, round(4.0 * k))
	var bw := cw * tot + gap * (tot - 1)
	var by := cy + 24.0 * k * tk
	for i in tot:
		var r := Rect2(Vector2(round(top.x - bw / 2.0 + i * (cw + gap)), round(by)), Vector2(round(cw), maxf(3.0, round(grid * k))))
		draw_rect(r, _fa(C if i < n else Color(L, 0.8), a))


## 陈列层的组小标题：青短竖条 + 中文 + 像素英文，后面一条渐隐细线到右边
func _draw_rows(tc: Dictionary, a: float) -> void:
	for rw in rows:
		var y: float = float(rw.y) - float(rw.r) - 34.0
		var p := _P(RX0, y)
		var fs := _F(13)
		draw_rect(Rect2(p + Vector2(0, -fs * 0.85), Vector2(maxf(2.0, 3.0 * k), fs * 0.9)), _fa(C, a))
		var w := _txt(p + Vector2(10.0 * k, 0), str(rw.cn), fs, _fa(C, a))
		var ew := TUI.ptext(self, tc, p + Vector2(10.0 * k + w + 10.0 * k, -fs * 0.34), str(rw.en), 1.2 * k * _tk(), _fa(M, a), 2)
		var x0 := p.x + 10.0 * k + w + ew + 24.0 * k
		var x1 := _P(RX1, 0).x
		var seg := 8
		for j in seg:   # 渐隐：分段降低透明度（实线，不是渐变贴图）
			var u0 := x0 + (x1 - x0) * j / seg
			var u1 := x0 + (x1 - x0) * (j + 1) / seg
			draw_line(Vector2(u0, p.y - fs * 0.34), Vector2(u1, p.y - fs * 0.34), _fa(Color(L, 0.6 * (1.0 - float(j) / seg)), a), 1.0)


## 底栏：选中章的记录（左：名称 + 状态、条件；右：像素格进度、当前 / 目标、获得日期）
func _draw_detail(tc: Dictionary, a: float) -> void:
	if items.is_empty():
		return
	var it: Dictionary = items[clampi(sel, 0, items.size() - 1)]
	var d: Dictionary = it.def
	var got := Medals.has(d.key)
	var tk := (1.0 + _tk()) / 2.0   # 底栏贴着页面下边：间距只跟一半的放大
	var x0 := _P(RX0, 0).x
	var x1 := _P(RX1, 0).x
	var ry := _P(0, STRIP_Y).y
	draw_line(Vector2(x0, ry), Vector2(x1, ry), _fa(Color(L, 0.6), a), 1.0)
	var y := ry + 36.0 * k * tk
	var nfs := _F(22)
	var nw := _txt(Vector2(x0, y), str(d.name), nfs, _fa(T, a))
	var st := "已获得" if got else "未获得"
	var sfs := _F(12)
	var sw := _tw(st, sfs)
	var sr := Rect2(Vector2(x0 + nw + 12.0 * k, y - sfs - 5.0 * k), Vector2(sw + 12.0 * k, sfs + 8.0 * k))
	if got:
		draw_rect(sr, _fa(Color(0.055, 0.157, 0.204, 0.9), a))
		draw_rect(Rect2(sr.position, Vector2(maxf(2.0, 3.0 * k), sr.size.y)), _fa(C, a))
	else:
		draw_rect(sr, _fa(Color(L, 0.9), a), false, 1.0)
	_txt(Vector2(sr.position.x + 7.0 * k, sr.end.y - 5.0 * k), st, sfs, _fa(C if got else M, a))
	var dfs := _F(14)
	var lines := UI.wrap_lines(font, str(d.desc), dfs, (x1 - x0) * 0.6)
	var ly := y + 28.0 * k * tk
	for ln in lines:
		_txt(Vector2(x0, ly), ln, dfs, _fa(M, a))
		ly += dfs * 1.4
	# 右侧：进度格（一枚章最多 25 格）+ 当前 / 目标；已获得再写日期
	var pr := Medals.progress(d)
	var cur := int(pr[0])
	var mx := int(pr[1])
	var cells := clampi(mx, 1, 25)
	var bw := 200.0 * k * tk
	var gap := maxf(1.0, round(grid * k * 0.5))
	var cw := (bw - gap * (cells - 1)) / cells
	var bh := maxf(3.0, round(grid * k * 1.5))
	var by := ry + 24.0 * k * tk
	var filled := int(floor(float(cur) / mx * cells + 0.0001))
	for i in cells:
		var r := Rect2(Vector2(round(x1 - bw + i * (cw + gap)), round(by)), Vector2(maxf(1.0, round(cw)), bh))
		draw_rect(r, _fa(C if i < filled else Color(L, 0.8), a))
	var ks := 1.6 * k * minf(_tk(), 1.1)
	TUI.ptext(self, tc, Vector2(x1, by + bh + 16.0 * k * tk), "%d / %d" % [cur, mx], ks, _fa(C if got else T, a), 1, 2)
	if got:
		var gy := by + bh + 42.0 * k * tk
		var ds := _date(int(Cfg.medals[d.key]))
		var dw := TUI.ptext(self, tc, Vector2(x1, gy), ds, ks, _fa(T, a), 1, 2)
		var lfs := _F(12)
		_txt(Vector2(x1 - dw - 10.0 * k - _tw("获得时间", lfs), gy + lfs * 0.36), "获得时间", lfs, _fa(M, a))


static func _date(t: int) -> String:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var dd := Time.get_date_dict_from_unix_time(t + bias)
	return "%04d-%02d-%02d" % [dd.year, dd.month, dd.day]


# ---------------------------------------------------------------- 输入
func _hit(lp: Vector2) -> int:
	var q := (lp - off) / k
	for i in items.size():
		if _in_hex(q - items[i].c, items[i].r):
			return i
	return -1


func _pick(i: int) -> void:
	if i < 0 or i == sel:
		return
	sel = i
	Sfx.play("ui_move", -6.0)


## 按几何方向找最近的一枚（不循环）：沿方向的距离 + 2 倍横向偏离
func nav(dir: Vector2) -> void:
	if items.is_empty():
		return
	var c0: Vector2 = items[sel].c
	var best := -1
	var bs := INF
	for i in items.size():
		if i == sel:
			continue
		var v: Vector2 = items[i].c - c0
		var along := v.dot(dir)
		if along <= 1.0:
			continue
		var s := along + 2.0 * absf(v.cross(dir))
		if s < bs:
			bs = s
			best = i
	_pick(best)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion:
		var lp := get_local_mouse_position()
		hover = _hit(lp)
		back_hot = back_rect.has_point(lp)
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var lp := get_local_mouse_position()
		if back_rect.has_point(lp):
			Sfx.play("ui_ok")
			close()
		else:
			_pick(_hit(lp))
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match Pad.kc(event):
			KEY_ESCAPE, KEY_BACKSPACE:
				Sfx.play("ui_ok")
				close()
			KEY_UP, KEY_W:
				nav(Vector2.UP)
			KEY_DOWN, KEY_S:
				nav(Vector2.DOWN)
			KEY_LEFT, KEY_A:
				nav(Vector2.LEFT)
			KEY_RIGHT, KEY_D:
				nav(Vector2.RIGHT)
		get_viewport().set_input_as_handled()
