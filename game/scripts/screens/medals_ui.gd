extends Control
## 局外 · 蚀刻章页「深蓝之下」（10-25 Codex 交付 art/incoming/achievement_ui_1024/，判定 core/medals.gd，章表 data/medals.json）。
## 用户：「改成我们的像素风格并且保持一致，背景设置成动态效果，字体也是需要修改」；「蚀刻章按照 codex 提交的排列来，那是设计」（10-25 晚，撤掉 v2 陈列柜）。
## - 版式：严格照 Codex 设计稿 packed_layout_v16.svg——九枚章的坐标 / 尺寸 / 分组 / 顺序照 approved_layout_1025.json（= data/medals_layout.json），
##   左栏文字位置量自设计稿（见下方「版式」段）；整幅等比放进安全区，手机同一幅。
## - 像素：章图与背景都按标题页「青光航标」的精度（1280×720 下 3 逻辑像素一格，docs/67 §13.3）重新量化，见 bake_pixel.py；未获得用暗钢蓝版。
## - 背景：原图低频形变（shaders/medal_sea.gdshader，SubViewport 428×240，≤ 30 Hz，24 秒一周期）；减少动态效果只画静帧；页面关着不更新。
## - 字：中文 ui.ttf，套组大标题 serif.ttf；拉丁 / 数字一律 5×7 像素字（tide_ui.ptext）。青只给可操作 / 选中。
## 操作：点章 / 方向键选中（按几何方向找最近的一枚）；左上「‹ 行动履历」/ Esc / 退格返回。
signal closed

const Medals = preload("res://scripts/core/medals.gd")
const TUI = preload("res://scripts/screens/tide_ui.gd")
const Tiles = preload("res://scripts/screens/title_jelly_menu.gd")
const UI = preload("res://scripts/ui.gd")

const CANVAS := Vector2(1672, 941)
const LAYOUT := "res://data/medals_layout.json"
const DIR := "res://art/ui/medals/"
const GRID := 1672.0 / 1280.0 * 3.0     # 一个美术像素 = 布局单位（标题页 3 逻辑像素）
const BG_GRID := Vector2i(428, 240)
const BG_PAD := 6
const HZ := 30.0
const C := Tiles.C
const T := Tiles.T
const M := Tiles.M
const L := Tiles.L

var font: Font
var serif: Font
var items: Array = []          # [{def, c: 布局中心, r, tex, off, ring}]
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


func _load_items() -> void:
	var lay = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var pos := {}
	if lay is Dictionary:
		for m in lay.get("medals", []):
			pos[int(m.id)] = [Vector2(float(m.center[0]), float(m.center[1])), float(m.radius)]
	for d in Medals.defs():
		var id := int(d.id)
		if not pos.has(id):
			continue
		var tex: Texture2D = load(DIR + "medal_%d.png" % id)
		items.append({"def": d, "c": pos[id][0], "r": pos[id][1], "tex": tex, "off": load(DIR + "medal_%d_off.png" % id),
			"ring": _ring(tex.get_width())})


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


# ---------------------------------------------------------------- 版式（照 Codex 设计稿 packed_layout_v16.svg，画布 1672×941）
## 整幅等比放进安全区（contain），手机也是同一幅、不裁切不重排；只有字在手机上放大一点（_tk）。
## 左栏各元素的位置量自设计稿（composition_v14.png 左栏）：返回箭头 45–59 × 31–60、「行动履历」104–207 × 36–56、
## 标题 97–445 × 377–461、英文 100–449 × 486–496、「蚀刻章套组」198–346 × 539–562、细线 232–313 @ 588、计数 228–316 × 609–623。
## 设计稿里没有的只有一处：计数下方空白里写选中章的记录（居中，同左栏中线）。
const COL_X := 272.0     # 左栏中线


func _fit() -> void:
	var ins: Array = Cfg.safe_insets()
	var avail := Rect2(Vector2(ins[0], ins[1]), size - Vector2(ins[0] + ins[2], ins[1] + ins[3]))
	k = minf(avail.size.x / CANVAS.x, avail.size.y / CANVAS.y)
	off = avail.position + (avail.size - CANVAS * k) / 2.0


func _P(x: float, y: float) -> Vector2:
	return off + Vector2(x, y) * k


## 字号：布局单位 → 实际（手机上字太小时放大一点，最低 11）
func _F(fs: float) -> int:
	return maxi(11, int(round(fs * k * _tk())))


## 手机 / 矮窗口：文字放大（缩放后布局单位 1 < 0.62 实际像素时，最多 1.25 倍）
func _tk() -> float:
	return clampf(0.62 / k, 1.0, 1.25)


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


## 等字距一行，p.y 是基线；align 0 左对齐 / 1 居中
func _spaced(p: Vector2, s: String, fs: int, col: Color, sp: float, f: Font, align := 1) -> void:
	var x := p.x - (_spaced_w(s, fs, sp, f) / 2.0 if align == 1 else 0.0)
	for ch in s:
		draw_string(f, Vector2(x, p.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		x += f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + sp


## 中文字墨的竖直中线 → 基线（CJK 字墨约在基线上 0.8 em 到下 0.07 em）
func _base(cy: float, fs: int) -> float:
	return cy + fs * 0.365


func _a() -> float:
	var dur := 0.12 if Cfg.reduce_motion else 0.25
	return clampf(open_t / dur, 0.0, 1.0)


func _fa(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)


func _draw() -> void:
	_fit()
	var a := _a()
	var tc := TUI.ctx(self)
	_draw_medals(a)
	_draw_head(a)
	_draw_title(tc, a)
	_draw_detail(tc, a)


func _draw_medals(a: float) -> void:
	for i in items.size():
		var it: Dictionary = items[i]
		var got := Medals.has(it.def.key)
		var tex: Texture2D = it.tex if got else it.off
		var n := float(tex.get_width())
		var s := n * GRID * k
		var c: Vector2 = _P(it.c.x, it.c.y)
		draw_texture_rect(tex, Rect2(c - Vector2(s, s) / 2.0, Vector2(s, s)), false, Color(1, 1, 1, a))
		if i == sel or i == hover:
			var rs := (n + 4.0) * GRID * k
			var col := C if i == sel else Color(M, 0.7)
			draw_texture_rect(it.ring, Rect2(c - Vector2(rs, rs) / 2.0, Vector2(rs, rs)), false, _fa(col, a))


## 左上返回：箭头 + 「行动履历」（设计稿原文，等字距）
func _draw_head(a: float) -> void:
	var col := C if back_hot else T
	var w := maxf(2.0, 2.4 * k)
	draw_polyline(PackedVector2Array([_P(59, 31), _P(46, 45.5), _P(59, 60)]), _fa(col, a), w)
	var fs := _F(22)
	var x := _P(104, 0).x
	var y := _base(_P(0, 46).y, fs)
	_spaced(Vector2(x, y), "行动履历", fs, _fa(col, a), 5.0 * k, font, 0)
	var tw := _spaced_w("行动履历", fs, 5.0 * k, font)
	back_rect = Rect2(_P(30, 18), Vector2(x + tw - _P(30, 0).x + 16.0 * k, 56.0 * k))
	if back_rect.size.y < 44.0 and Cfg.touch_device():
		back_rect = back_rect.grow_individual(0, (44.0 - back_rect.size.y) / 2.0, 0, (44.0 - back_rect.size.y) / 2.0)


## 左栏套组：深蓝之下（衬线）+ 波纹细线 / BENEATH THE BLUE（像素字）/ 蚀刻章套组 / 细线 / 已获得数（像素字）
func _draw_title(tc: Dictionary, a: float) -> void:
	var white := Color(0.94, 0.965, 0.98)
	var tfs := _F(86)
	_spaced(Vector2(_P(271, 0).x, _base(_P(0, 419).y, tfs)), str(Medals.data().get("set_name", "深蓝之下")), tfs, _fa(white, a), 1.0 * k, serif)
	# 标题下的波纹细线（设计稿里一道从左下穿过字脚的浪线）
	var pts := PackedVector2Array()
	for i in 41:
		var u := i / 40.0
		pts.append(_P(72.0 + 404.0 * u, 452.0 - 10.0 * sin(u * PI) * u + 4.0 * sin(u * TAU * 1.5)))
	draw_polyline(pts, _fa(Color(T, 0.45), a), maxf(1.0, k))
	# 英文：5×7 像素字，量得 100–449 × 486–496。格边长向上取整到整屏幕像素（不然 1672 宽时取整成 1 像素、字太小），再反算字距铺满稿上的宽度
	var en := str(Medals.data().get("set_en", ""))
	var cell := maxf(1.0, ceilf(1.43 * k * float(tc.k)))
	var span := 349.0 * k * float(tc.k) / cell   # 目标宽度（格）
	var letters := 0
	for ch in en:
		letters += 1 if ch != " " else 0
	var spaces := en.length() - letters
	var track := maxi(1, int(round((span - 6.0 * letters - 4.0 * spaces + 1.0) / float(en.length() - 1))))
	TUI.ptext(self, tc, _P(274.5, 491), en, cell / float(tc.k), _fa(Color(T, 0.85), a), track, 1)
	var sfs := _F(24)
	_spaced(Vector2(_P(272, 0).x, _base(_P(0, 550.5).y, sfs)), "蚀刻章套组", sfs, _fa(T, a), 7.0 * k, font)
	draw_line(_P(232, 588), _P(313, 588), _fa(Color(T, 0.55), a), maxf(1.0, k))
	# 已获得数（设计稿里是演示数据 04 / 09，这里是真实存档）
	var n := Medals.earned_count()
	var tot := Medals.defs().size()
	var ks := 2.0 * k * _tk()
	var s1 := "%02d" % n
	var s2 := " / %02d" % tot
	var w1 := TUI.ptext_w(tc, s1, ks)
	var w2 := TUI.ptext_w(tc, s2, ks)
	var x: float = _P(272, 0).x - (w1 + w2) / 2.0
	TUI.ptext(self, tc, Vector2(x, _P(0, 616).y), s1, ks, _fa(C if n > 0 else T, a))
	TUI.ptext(self, tc, Vector2(x + w1, _P(0, 616).y), s2, ks, _fa(T, a))


## 选中章的记录（计数下方空白，居中）：名称 + 状态 / 条件 / 像素格进度 / 当前 / 目标 · 获得日期
func _draw_detail(tc: Dictionary, a: float) -> void:
	if items.is_empty():
		return
	var it: Dictionary = items[clampi(sel, 0, items.size() - 1)]
	var d: Dictionary = it.def
	var got := Medals.has(d.key)
	var tk := _tk()
	var cx := _P(COL_X, 0).x
	var y := _P(0, 702).y
	var nfs := _F(24)
	var st := "已获得" if got else "未获得"
	var sfs := _F(13)
	var nw := _tw(str(d.name), nfs)
	var sw := _tw(st, sfs) + 12.0 * k
	var x0 := cx - (nw + 12.0 * k + sw) / 2.0
	_txt(Vector2(x0, y), str(d.name), nfs, _fa(T, a))
	var sr := Rect2(Vector2(x0 + nw + 12.0 * k, y - sfs - 5.0 * k), Vector2(sw, sfs + 8.0 * k))
	if got:
		draw_rect(sr, _fa(Color(0.055, 0.157, 0.204, 0.9), a))
		draw_rect(Rect2(sr.position, Vector2(maxf(2.0, 3.0 * k), sr.size.y)), _fa(C, a))
	else:
		draw_rect(sr, _fa(Color(L, 0.9), a), false, 1.0)
	_txt(Vector2(sr.position.x + 6.0 * k, sr.end.y - 5.0 * k), st, sfs, _fa(C if got else M, a))
	var dfs := _F(16)
	var ly := y + 34.0 * k * tk
	var lw := 400.0 * k * tk
	for ln in UI.wrap_lines(font, str(d.desc), dfs, lw):
		_txt(Vector2(cx - lw / 2.0, ly), ln, dfs, _fa(M, a), null, HORIZONTAL_ALIGNMENT_CENTER, lw)
		ly += dfs * 1.45
	var pr := Medals.progress(d)
	var cur := int(pr[0])
	var mx := int(pr[1])
	var cells := clampi(mx, 1, 25)
	var bw := 240.0 * k * tk
	var gap := maxf(1.0, round(GRID * k * 0.5))
	var cw := (bw - gap * (cells - 1)) / cells
	var bh := maxf(3.0, round(GRID * k * 1.5))
	var by := ly + 4.0 * k * tk
	var filled := int(floor(float(cur) / mx * cells + 0.0001))
	for i in cells:
		var r := Rect2(Vector2(round(cx - bw / 2.0 + i * (cw + gap)), round(by)), Vector2(maxf(1.0, round(cw)), bh))
		draw_rect(r, _fa(C if i < filled else Color(L, 0.8), a))
	var ks := 1.6 * k * tk
	var py := by + bh + 18.0 * k * tk
	if got:
		TUI.ptext(self, tc, Vector2(cx, py), "%d / %d  ·  %s" % [cur, mx, _date(int(Cfg.medals[d.key]))], ks, _fa(C, a), 1, 1)
	else:
		TUI.ptext(self, tc, Vector2(cx, py), "%d / %d" % [cur, mx], ks, _fa(T, a), 1, 1)


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
