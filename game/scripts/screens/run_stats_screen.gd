extends RefCounted
## 界面 · 作战记录（局终统计，docs/77，2026-10-12）：胜利 / 结局结算与失败结算上的「作战记录」按钮（Tab / C）打开，
## 不替换结局演出与结算面板；Esc / Ⓑ / 「返回结算」回到结算。
## 结构参考雨中冒险 2 的结算「Run Report」（10-12 用户），版式按版式三案选定的「左档案右数据」（v3b，docs/77 §3）：
## 左 40%：结果横幅（探索完成 / 探索终止 + 结局名或击倒者）、主控 / 击倒者卡、竖排编队（行高撑满）；
## 右 60%：藏品格（拾取顺序，按件数定高；选中 / 悬停时说明贴着图标弹出）+ 数据（标签左、数值右，行高撑满剩余高度）。
## 编队行上 Enter / 点击进干员详情（前 5 个伤害来源 + 主控生存）。手机：结果横幅 | 主控卡常驻，下面三页 编队 / 藏品 / 数据。
## 干员 / 敌人像一律按不透明包围盒缩放放进像框（_fit），不出框。风格：局外 T5s（docs/37 §8）。
## 动效（docs/62 §3.24）：主动作「藏品依次弹出」（每格 T2 out_back(1.4)，0.6 → 1 倍，间隔 ≤ 35 ms，整组 ≤ 0.6 秒）；
##   统计数值计数、编队占比条注满（次要）。减少动态：直接终态，只留 T1 淡入。
## 数据只读 run/run_stats.gd 的 model（不碰 g.rng、不改对局状态）。

const UI = preload("res://scripts/ui.gd")
const UM = preload("res://scripts/ui_motion.gd")
const TUI = preload("res://scripts/screens/tide_ui.gd")
const A = preload("res://scripts/art.gd")
const D = preload("res://scripts/data.gd")
const RunStats = preload("res://scripts/run/run_stats.gd")
const Game = preload("res://scripts/game.gd")

const SEG0 := 0.08      # 第一格 / 第一段开始
const SEG_S := 0.07     # 占比条段间错开
const SEG := UM.T2      # 每段滑入时长
const TOP_SRC := 5      # 详情里列出的伤害来源条数（其余并成「其他」）

var g: Game
var open := false
var model: Dictionary = {}
var page := 0           # 0 总览 / 1 详情
var sel := 0            # 选中的干员行
var zone := 1           # 总览焦点：0 藏品格 / 1 编队列表
var rel := 0            # 选中的藏品
var tab := 0            # 手机总览页：0 编队 / 1 藏品 / 2 数据
var stat_scroll := 0    # 统计表滚动
var t_open := 0.0
var t_page := 0.0
var skipped := false
var cells: Array = []   # [Rect2, 动作, 参数]：命中区（终态位置）
var portraits: Array = []   # [画出的矩形, 允许的框]：干员 / 敌人像（快检检查不出框）
var _bbox_cache := {}
var _gen_tex := {}
var _last_mouse := Vector2(-1, -1)
var _per_row := 1       # 藏品格每行几个（方向键上下用）
var _tex_miss := {}
var _id_big := true
var _pop_anchor := Rect2()   # 选中藏品格的位置（说明弹窗贴着它）
# 每帧绘制用
var _c: Dictionary
var _ps := 2
var _ph := false


func _init(game: Game) -> void:
	g = game


## 打开：拍一份当前对局的记录
func open_for_run() -> void:
	show_model(RunStats.model(RunStats.snapshot(g)))


## 打开指定模型（快检用假记录）
func show_model(m: Dictionary) -> void:
	model = m
	open = true
	page = 0
	sel = 0
	zone = 1
	rel = 0
	tab = 0
	stat_scroll = 0
	skipped = false
	t_open = UM.now()
	t_page = t_open
	_last_mouse = Vector2(-1, -1)
	g.ui_skip = true   # 结算面板自己的动效此时已经不需要了


func close() -> void:
	open = false
	cells.clear()


func rows() -> Array:
	return model.get("rows", [])


## 动效时间（秒）；跳过 / 无头 = 终态
func _mt(t0: float) -> float:
	if skipped or UM.skip_all():
		return 99.0
	return UM.now() - t0


func motion_running() -> bool:
	if not open or skipped or UM.rm() or UM.skip_all():
		return false
	return _mt(t_open) < 0.75 if page == 0 else _mt(t_page) < 0.4


# ================================================================== 输入
## 总览焦点：zone 0 = 藏品格（rel 为下标），zone 1 = 编队条（sel 为干员行）。手机另有三页（tab：概况 / 藏品 / 数据）
## 按键（含手柄翻译过来的键）；返回是否处理
func key(k: int) -> bool:
	if not open:
		return false
	if motion_running() and k in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		skipped = true   # docs/62 §2.5：确认键先跳到终态
		return true
	var n: int = rows().size()
	var nr: int = relics().size()
	if page == 0:
		match k:
			KEY_LEFT, KEY_A:
				_nav(-1, 0)
			KEY_RIGHT, KEY_D:
				_nav(1, 0)
			KEY_UP, KEY_W:
				_nav(0, -1)
			KEY_DOWN, KEY_S:
				_nav(0, 1)
			KEY_PAGEUP:
				stat_scroll = maxi(0, stat_scroll - 3)
			KEY_PAGEDOWN:
				stat_scroll += 3
			KEY_TAB:
				if _ph:
					tab = (tab + 1) % 3
					Sfx.play("ui_move")
				else:
					Sfx.play("ui_ok", -6.0)
					close()
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				if zone == 1 and n > 0:
					_detail(sel)
			KEY_ESCAPE, KEY_C, KEY_BACKSPACE:
				Sfx.play("ui_ok", -6.0)
				close()
			_:
				return false
		if nr == 0:
			zone = 1
		return true
	match k:
		KEY_LEFT, KEY_A, KEY_UP, KEY_W, KEY_PAGEUP:
			if sel > 0:
				_detail(sel - 1)
		KEY_RIGHT, KEY_D, KEY_DOWN, KEY_S, KEY_PAGEDOWN:
			if sel < n - 1:
				_detail(sel + 1)
		KEY_ESCAPE, KEY_BACKSPACE, KEY_C, KEY_TAB, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			page = 0
			t_page = UM.now()
			Sfx.play("ui_ok", -6.0)
		_:
			return false
	return true


## 方向键（v3b 版式「左档案右数据」）：编队列表（左）↑ ↓ 换干员，→ 进藏品格；藏品格（右上）按行列走，最左一格再 ← 回编队列表。不循环（docs/67 §12）
func _nav(dx: int, dy: int) -> void:
	var nr: int = relics().size()
	var n: int = rows().size()
	var per: int = maxi(1, _per_row)
	var before := [zone, rel, sel]
	if _ph:
		zone = 0 if tab == 1 else 1
	if zone == 0 and nr > 0:
		if dx < 0 and rel % per == 0:
			if not _ph:
				zone = 1
		elif dx != 0:
			rel = clampi(rel + dx, 0, nr - 1)
		elif dy < 0 and rel >= per:
			rel -= per
		elif dy > 0 and rel + per < nr:
			rel += per
	else:
		if dy != 0:
			sel = clampi(sel + dy, 0, maxi(0, n - 1))
		elif dx > 0 and nr > 0 and not _ph:
			zone = 0
	if [zone, rel, sel] != before:
		g.kb_nav = true
		Sfx.play("ui_move")


func _detail(i: int) -> void:
	sel = i
	page = 1
	t_page = UM.now()
	Sfx.play("ui_ok", -4.0)


## 鼠标 / 触屏（触屏由引擎模拟成鼠标）：mp 为 UI 逻辑坐标
func click(mp: Vector2) -> bool:
	if not open:
		return false
	if motion_running():
		skipped = true
		return true
	for c in cells:
		if c[0].has_point(mp):
			_act(c[1], c[2])
			return true
	return true   # 全屏界面：点空白处不落到下面的结算按钮


func wheel(dy: int) -> void:
	if open and page == 0:
		stat_scroll = maxi(0, stat_scroll + dy)


func _act(a: String, arg) -> void:
	match a:
		"card":
			zone = 1
			_detail(int(arg))
		"relic":
			zone = 0
			rel = int(arg)
		"tab":
			if tab != int(arg):
				tab = int(arg)
				Sfx.play("ui_move")
		"back":
			Sfx.play("ui_ok", -6.0)
			if page == 1:
				page = 0
				t_page = UM.now()
			else:
				close()
		"prev":
			if sel > 0:
				_detail(sel - 1)
		"next":
			if sel < rows().size() - 1:
				_detail(sel + 1)


# ================================================================== 绘制公共件
static func fmt_n(v: float) -> String:
	var s := str(int(round(v)))
	var neg := s.begins_with("-")
	if neg:
		s = s.substr(1)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if neg else "") + s + out


static func fmt_t(t: float) -> String:
	var it := int(maxf(0.0, t))
	return "%02d:%02d" % [it / 60, it % 60]


## 伤害来源：前 n 条，其余并成「其他」
static func top_sources(srcs: Array, n: int) -> Array:
	if srcs.size() <= n + 1:
		return srcs
	var out: Array = srcs.slice(0, n)
	var v := 0.0
	var sh := 0.0
	var pc := 0
	for s in srcs.slice(n):
		v += float(s.v)
		sh += float(s.share)
		pc += int(s.pct)
	out.append({"name": "其他", "v": v, "share": sh, "pct": pc, "kind": "其他"})
	return out


func _ci() -> CanvasItem:
	return g.hud


## 中文：pos.y 是字的竖直中线；align 0 左 / 1 中 / 2 右。返回宽度
func _t(pos: Vector2, s: String, size: int, col: Color, align := 0, max_w := -1.0) -> float:
	var w: float = g.font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if max_w > 0.0 and w > max_w:
		while size > 10 and g.font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_w:
			size -= 1
		w = g.font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := pos.x - (w * 0.5 if align == 1 else (w if align == 2 else 0.0))
	UI.text(_ci(), g.font, Vector2(roundf(x), roundf(pos.y + size * 0.36)), s, size, col)
	return w


## 像素字（数字 / 英文）：k = 逻辑倍数
func _p(pos: Vector2, s: String, k: float, col: Color, align := 0, track := 1) -> float:
	return TUI.ptext(_ci(), _c, pos, s, k * (0.7 if _ph else 1.0), col, track, align)


func _grid(r: Rect2) -> Dictionary:
	return TUI.grid(_c, r, _ps)


func _tile(r: Rect2, n: int, on: bool, a := 1.0) -> Rect2:
	var gg := _grid(r)
	if on:
		TUI.halo(_ci(), gg, n, a)
	TUI.tile(_ci(), gg, n, on, a)
	return gg.rect


func _panel(r: Rect2, n: int, a := 0.92) -> Rect2:
	var gg := _grid(r)
	TUI.panel(_ci(), gg, n, a)
	return gg.rect


static func _fa(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)


## 像素条：槽 + 段（段间 1 格暗缝）；segs = [[占比, 颜色]]；frac = 整条展开到多少
func _bar(r: Rect2, segs: Array, frac := 1.0, track := true, a := 1.0) -> void:
	var cl: float = _ps / _c.k
	var x0: float = TUI.snap(_c, r.position).x
	var y0: float = TUI.snap(_c, r.position).y
	var w: float = roundf(r.size.x / cl) * cl
	var h: float = maxf(cl * 2.0, roundf(r.size.y / cl) * cl)
	var ci := _ci()
	if track:
		ci.draw_rect(Rect2(x0, y0, w, h), Color(0.024, 0.055, 0.118, 0.95 * a))
		ci.draw_rect(Rect2(x0, y0 + h - cl, w, cl), Color(0.08, 0.17, 0.27, a))
	var cx := x0
	var lim := x0 + w * clampf(frac, 0.0, 1.0)
	for i in segs.size():
		var sw: float = roundf(w * float(segs[i][0]) / cl) * cl
		if i == segs.size() - 1 and frac >= 1.0 and float(segs[i][0]) > 0.0:
			sw = x0 + w - cx
		var x1 := minf(cx + sw, lim)
		if x1 - cx > cl * 1.5:
			var col: Color = segs[i][1]
			ci.draw_rect(Rect2(cx, y0, x1 - cx - cl, h), _fa(col, a))
			ci.draw_rect(Rect2(cx, y0, x1 - cx - cl, cl), _fa(col.lightened(0.35), a))
		cx += sw


## 帧条里所有帧不透明像素的并集包围盒（帧内坐标）；拿不到图像数据（无头渲染器）时用整帧
func _bbox(tx: Texture2D, fw: int, fh: int, nfr: int) -> Rect2:
	var key := "%d|%d|%d" % [tx.get_rid().get_id(), fw, fh]
	if _bbox_cache.has(key):
		return _bbox_cache[key]
	var bb := Rect2(0, 0, fw, fh)
	var im: Image = tx.get_image()
	if im != null and not im.is_empty():
		if im.is_compressed():
			im.decompress()
		var u := Rect2i()
		for f in nfr:
			var r: Rect2i = im.get_region(Rect2i(f * fw, 0, fw, fh)).get_used_rect()
			if r.size.x > 0:
				u = r if u.size.x == 0 else u.merge(r)
		if u.size.x > 0:
			bb = Rect2(u)
	_bbox_cache[key] = bb
	return bb


## 把一帧（frame 为帧在贴图里的位置，bb 为帧内包围盒）放进 box：底边居中，按美术像素整数倍缩放（不超过 kmax），永远不出框。
## art = 一个美术像素占几个贴图像素（高清帧条 2）。返回画出的矩形
func _fit(tx: Texture2D, frame: Rect2, bb: Rect2, art: float, box: Rect2, kmax: float, a := 1.0) -> Rect2:
	if bb.size.x <= 0.0 or box.size.x <= 2.0 or box.size.y <= 2.0:
		return Rect2()
	var k_art: float = minf(kmax, minf(box.size.x / (bb.size.x / art), box.size.y / (bb.size.y / art)))
	if k_art >= 1.0:
		k_art = floorf(k_art)
	var sz := bb.size * (k_art / art)
	var pos := TUI.snap(_c, Vector2(box.get_center().x - sz.x * 0.5, box.end.y - sz.y))
	pos.x = clampf(pos.x, box.position.x, box.end.x - sz.x)
	pos.y = clampf(pos.y, box.position.y, box.end.y - sz.y)
	var dst := Rect2(pos, sz)
	_ci().draw_texture_rect_region(tx, dst, Rect2(frame.position + bb.position, bb.size), Color(1, 1, 1, a))
	portraits.append([dst, box])
	return dst


## 干员待机帧放进 box（卡片 / 主控块 / 详情身份卡的像框）
func _portrait(id: String, box: Rect2, kmax: float) -> Rect2:
	if id == RunStats.OTHER or id == "":
		return Rect2()
	var idle: Dictionary = g.panel_ui.op_idle(id)
	if idle.is_empty():
		return Rect2()
	var tx: Texture2D = idle.tex
	var fw: int = idle.fw
	var fh: int = idle.fh
	var nfr: int = maxi(1, tx.get_width() / maxi(1, fw))
	var fr := 0 if (UM.rm() or UM.skip_all()) else int(UM.now() * 4.0) % nfr
	var bb := _bbox(tx, fw, fh, nfr)
	return _fit(tx, Rect2(fr * fw, 0, fw, fh), bb, 2.0 if fh > 64 else 1.0, box, kmax)


## 环境击倒者的图：溟痕用地面溟痕贴图，其余（黑潮 / 寂灭 / 围猎……）用生成的像素图
func _env_art(kind: String) -> Array:
	if kind == "mire":
		var mt: Texture2D = g.tex.get("terrain_mire")
		if mt == null:
			mt = A.tex("terrain_mire")
		if mt != null:
			var fh: int = mt.get_height()
			return [mt, Rect2(0, 0, fh, fh)]
	var gk := "lamp" if kind == "dark" else "tide"
	if not _gen_tex.has(gk):
		_gen_tex[gk] = _make_lamp() if gk == "lamp" else _make_tide()
	var gt: Texture2D = _gen_tex[gk]
	return [gt, Rect2(0, 0, gt.get_width(), gt.get_height())]


## 黑潮：上沿一道紫色浪头、下面越来越黑的有序抖动（24×24）
static func _make_tide() -> ImageTexture:
	var im := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	var tones := [Color8(74, 30, 104), Color8(40, 16, 64), Color8(16, 8, 30)]
	for y in 24:
		for x in 24:
			var crest := 7 + int(round(sin(x * 0.55) * 1.6))
			if y < crest:
				continue
			if y == crest:
				im.set_pixel(x, y, Color8(176, 110, 230))
				continue
			var v := clampf(float(y - crest) / 16.0 * 2.2, 0.0, 2.0)
			var lv := int(floor(v)) + (1 if (v - floor(v)) * 16.0 > TUI.BAYER[(y % 4) * 4 + (x % 4)] + 0.5 else 0)
			im.set_pixel(x, y, tones[mini(lv, 2)])
	return ImageTexture.create_from_image(im)


## 寂灭：熄灭的提灯（16×16，灰色灯罩、没有火苗）
static func _make_lamp() -> ImageTexture:
	var rows := ["......11........", ".....1..1.......", "....111111......", "...11111111.....", "....1....1......", "....1.22.1......",
		"....1.22.1......", "....1.22.1......", "....1....1......", "....1....1......", "...11111111.....", "....111111......", "................",
		"................", "................", "................"]
	var im := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var ch: String = rows[y][x]
			if ch == "1":
				im.set_pixel(x + 2, y + 2 if y < 14 else y, Color8(150, 160, 176))
			elif ch == "2":
				im.set_pixel(x + 2, y + 2 if y < 14 else y, Color8(52, 56, 70))
	return ImageTexture.create_from_image(im)


## 操作提示：像素字键名 + 中文说明（触屏不画）
func _hints(pos: Vector2, pairs: Array) -> void:
	if Pad.touch and not Pad.using:
		return
	var x := pos.x
	for pr in pairs:
		x += _p(Vector2(x, pos.y), str(pr[0]), 1.0, TUI.CY_DIM) + 6.0
		x += _t(Vector2(x, pos.y), str(pr[1]), 12, TUI.TXT2) + 18.0


## 按钮磁贴（返回）：焦点 / 悬停 = S4 反白
func _button(r: Rect2, label: String, keyname: String, act: String, hov: bool) -> void:
	var rr := _tile(r, 2, hov)
	_t(Vector2(rr.position.x + 14, rr.get_center().y), label, 16 if not _ph else 15, TUI.SEL_INK if hov else TUI.TXT)
	if keyname != "" and not (Pad.touch and not Pad.using):
		_p(Vector2(rr.end.x - 12, rr.get_center().y), keyname, 1.0, TUI.SEL_IDX if hov else TUI.CY, 2)
	cells.append([r.grow(6.0 if _ph else 0.0), act, null])


func _mouse() -> Vector2:
	return g.hud.get_local_mouse_position()


func _hovered(r: Rect2) -> bool:
	return not g.kb_nav and not Pad.using and r.has_point(_mouse())


func _join_text(row: Dictionary, long := false) -> String:
	var jt: String
	if row.key == RunStats.OTHER:
		jt = "全程"
	elif row.leader:
		jt = "主控 · 开局"
	elif float(row.join_t) < 1.0:
		jt = "开局"
	else:
		jt = fmt_t(float(row.join_t)) + (" 加入编队" if long else " 加入")
	if float(row.left_t) >= 0.0:
		jt += " · %s 离队" % fmt_t(float(row.left_t))
	return jt


# ================================================================== 绘制
func draw(vs: Vector2) -> void:
	if not open:
		return
	_c = TUI.ctx(_ci())
	_ph = Cfg.touch_device() or vs.y < 560.0
	_ps = TUI.cell(_c, 1.4 if _ph else 2.0)
	cells.clear()
	portraits.clear()
	var a0: float = UM.prog(t_open, UM.T1) if not skipped else 1.0
	_ci().draw_rect(Rect2(Vector2.ZERO, vs), Color(0.008, 0.03, 0.07, 0.88 * a0))
	var m := 14.0 if not _ph else 8.0
	_panel(Rect2(m, m, vs.x - m * 2.0, vs.y - m * 2.0), 3, 0.55 * a0)
	# 鼠标移动过才让悬停接管焦点（键盘 / 手柄操作后不被静止的鼠标抢回去）
	var mp := _mouse()
	if mp.distance_to(_last_mouse) > 2.0:
		if _last_mouse.x >= 0.0:
			g.kb_nav = false
		_last_mouse = mp
	if page == 0:
		_draw_overview(vs)
	else:
		_draw_detail(vs)


## 标题行：RUN RECORD 小字 + 中文标题 + 结果（胜利：结局名 · 探索完成，青；失败：探索终止，洋红）。返回下一块的 y
func _header(vs: Vector2, title: String, en: String) -> float:
	var x := 40.0 if not _ph else 24.0
	var y_en := 36.0 if not _ph else 24.0
	var y_t := 62.0 if not _ph else 44.0
	_p(Vector2(x + 2, y_en), en, 1.0, TUI.CY_DIM, 0, 2)
	var tw := _t(Vector2(x, y_t), title, 28 if not _ph else 22, TUI.TXT)
	var won: bool = str(model.get("result", "")) == "win"
	var trial: bool = bool(model.get("trial", false))
	var rn: String = ("Boss 演练" if trial else str(model.get("ending_name", ""))) if won else "探索终止"
	var rs := ("完成" if trial else "探索完成") if won else ""
	var rc: Color = TUI.CY if won else UI.RED
	var x2 := x + tw + 22.0
	var cl: float = _ps / _c.k
	_ci().draw_rect(Rect2(TUI.snap(_c, Vector2(x2, y_t - 10)), Vector2(cl * 2.0, 20)), rc)
	var w1 := _t(Vector2(x2 + 12, y_t), rn, 16 if not _ph else 14, TUI.TXT)
	if rs != "":
		_t(Vector2(x2 + 22 + w1, y_t), rs, 14 if not _ph else 13, rc)
	return y_t + (36.0 if not _ph else 26.0)


# ------------------------------------------------------------------ 总览（v3：雨中冒险 2 结算的三栏结构）
func relics() -> Array:
	return model.get("relic_list", [])


func _relic_tex(id: String) -> Texture2D:
	var k := "relic_" + id
	var tx: Texture2D = g.tex.get(k)
	if tx == null and not _tex_miss.has(k):
		tx = A.tex(k)
		if tx == null:
			_tex_miss[k] = true
		else:
			g.tex[k] = tx
	return tx


## 敌人第一帧：[贴图, 源矩形]（没有贴图返回 []）
func _enemy_frame(ty: String) -> Array:
	var tn := str(D.ENEMIES.get(ty, {}).get("tex", ""))
	if tn == "":
		return []
	var tx: Texture2D = g.tex.get(tn)
	if tx == null and not _tex_miss.has(tn):
		tx = A.tex(tn)
		if tx == null:
			_tex_miss[tn] = true
		else:
			g.tex[tn] = tx
	if tx == null:
		return []
	var fh: int = tx.get_height()
	var nf: int = maxi(1, tx.get_width() / maxi(1, fh))
	var fw: int = tx.get_width() / nf
	return [tx, Rect2(0, 0, fw, fh)]


## 总览（v3b，10-12 用户「现在的结算布局也有点奇怪」→ 版式三案选 V2「左档案右数据」，docs/77 §3）：
## 左 40%：结果横幅 + 主控 / 击倒者卡 + 竖排编队（行高撑满）；右 60%：藏品格（按件数定高）+ 数据（行高撑满剩余高度）。两栏同顶同底。
## 手机：上面一排 结果横幅 | 主控卡 常驻，下面三页 编队 / 藏品 / 数据
func _draw_overview(vs: Vector2) -> void:
	var t := _mt(t_open)
	var M := 32.0 if not _ph else 20.0
	var top := 28.0 if not _ph else 18.0
	var bot := vs.y - (64.0 if not _ph else 62.0)
	if _ph:
		var half := (vs.x - M * 2.0 - 12.0) * 0.48
		_banner(Rect2(M, top, half, 96.0))
		_leader_card(Rect2(M + half + 12.0, top, vs.x - M * 2.0 - half - 12.0, 96.0))
		var names := ["编队", "藏品", "数据"]
		var ty := top + 108.0
		for i in 3:
			var trr := Rect2(M + i * 100.0, ty, 92.0, 36.0)
			var rr := _tile(trr, 2, tab == i)
			_t(rr.get_center(), names[i], 15, TUI.SEL_INK if tab == i else TUI.TXT2, 1)
			cells.append([trr.grow_individual(0, 6, 0, 6), "tab", i])
		var body := Rect2(M, ty + 46.0, vs.x - M * 2.0, bot - ty - 46.0)
		match tab:
			0:
				zone = 1
				_squad_list(body, t, false)
			1:
				zone = 0
				var gb := _relic_grid(body, t, false)
				_relic_popup(body.end.x, gb)
			2:
				_stats(body, t, 2)
	else:
		var lw := (vs.x - M * 2.0) * 0.4
		_banner(Rect2(M, top, lw, 112.0))
		_leader_card(Rect2(M, top + 124.0, lw, 100.0))
		_squad_list(Rect2(M, top + 236.0, lw, bot - top - 236.0), t, true)
		var rx := M + lw + 24.0
		var rr2 := Rect2(rx, top, vs.x - M - rx, bot - top)
		var gb2 := _relic_grid(rr2, t, true)
		_stats(Rect2(rx, gb2 + 14.0, rr2.size.x, bot - gb2 - 14.0), t, 0)
		_relic_popup(rr2.end.x, gb2)
	var br := Rect2(vs.x - M - (160.0 if not _ph else 150.0), vs.y - (52.0 if not _ph else 56.0), 160.0 if not _ph else 150.0, 34.0 if not _ph else 44.0)
	_button(br, "返回结算", "ESC" if not Pad.using else "B", "back", _hovered(br))
	if not _ph:
		_hints(Vector2(M, br.get_center().y), [["↑ ↓", "选干员"], ["← →", "编队 / 藏品"], ["ENTER" if not Pad.using else "A", "干员详情"]])


## 结果横幅：探索完成（青）/ 探索终止（洋红）大字 + 结局名或「击倒者：…」
func _banner(r: Rect2) -> void:
	var rr := _panel(r, 3, 0.94)
	var won: bool = str(model.get("result", "")) == "win"
	var trial: bool = bool(model.get("trial", false))
	var col: Color = TUI.CY if won else UI.RED
	var cl: float = _ps / _c.k
	_ci().draw_rect(Rect2(rr.position.x + cl * 2.0, rr.position.y + 10.0, cl * 2.0, rr.size.y - 20.0), col)
	var x0 := rr.position.x + (22.0 if not _ph else 16.0)
	_p(Vector2(x0 + 2, rr.position.y + (20.0 if not _ph else 16.0)), "RUN REPORT", 1.0, TUI.CY_DIM, 0, 2)
	var big := ("演练完成" if won else "演练结束") if trial else ("探索完成" if won else "探索终止")
	_t(Vector2(x0, rr.position.y + rr.size.y * 0.5), big, 34 if not _ph else 24, col)
	var sub := ""
	if won and not trial:
		sub = str(model.get("ending_name", ""))
	elif not won:
		var kd: Dictionary = model.get("killer", {})
		if not kd.is_empty():
			sub = "击倒者：" + str(kd.get("name", "")) + ((" · " + str(kd.cause)) if str(kd.get("cause", "")) != "" else "")
	if sub != "":
		_t(Vector2(x0, rr.end.y - (22.0 if not _ph else 16.0)), sub, 16 if not _ph else 13, TUI.TXT, 0, rr.size.x - 40.0)


## 主控 / 击倒者卡：像框（不出框）、名字、Lv. · 精英 · 难度、探索时间；下半一行 击倒者（敌人或环境图 + 名字 + 死因）/ 击破最终 Boss
func _leader_card(r: Rect2) -> void:
	var rr := _panel(r, 2, 0.92)
	var ld: Dictionary = {}
	for rw in rows():
		if rw.leader:
			ld = rw
	var pb := Rect2(rr.position.x + 10.0, rr.position.y + 8.0, (76.0 if not _ph else 64.0), rr.size.y - 16.0)
	if not ld.is_empty():
		_portrait(str(ld.key), pb, 2.0)
	var tx := pb.end.x + 12.0
	var x1 := rr.end.x - 14.0
	var y := rr.position.y + 22.0
	_t(Vector2(tx, y), str(ld.get("name", "")), 16 if not _ph else 14, TUI.TXT, 0, x1 - tx - 90.0)
	_p(Vector2(x1, y), fmt_t(float(model.get("t", 0.0))), 2.0, TUI.TXT, 2)
	y += 22.0
	_t(Vector2(tx, y), "Lv.%d · %s · %s" % [int(model.get("level", 1)), ["精零", "精英一", "精英二"][clampi(int(model.get("elite", 0)), 0, 2)], str(model.get("tier_name", ""))], 12, TUI.TXT2, 0, x1 - tx)
	y += 16.0
	_ci().draw_rect(Rect2(tx, roundf(y), x1 - tx, 1), Color(1, 1, 1, 0.08))
	y += 18.0
	var won: bool = str(model.get("result", "")) == "win"
	var kd: Dictionary = model.get("final_boss", {}) if won else model.get("killer", {})
	if kd.is_empty():
		_t(Vector2(tx, y), "演练完成" if won else "", 13, TUI.TXT2)
		return
	var ab := Rect2(tx, y - 15.0, 30.0, 30.0)
	var fr: Array = _enemy_frame(str(kd.get("type", ""))) if str(kd.get("env", "")) == "" else _env_art(str(kd.env))
	if not fr.is_empty():
		var tx0: Texture2D = fr[0]
		var src: Rect2 = fr[1]
		var bb := _bbox(tx0, int(src.size.x), int(src.size.y), 1) if str(kd.get("env", "")) == "" else Rect2(Vector2.ZERO, src.size)
		_fit(tx0, src, bb, 1.0, ab, 2.0)
	var lab := "击破最终 Boss" if won else "击倒者"
	var lw := _t(Vector2(ab.end.x + 8.0, y), lab, 12, TUI.CY_DIM if won else UI.RED)
	_t(Vector2(ab.end.x + 16.0 + lw, y), str(kd.get("name", "")), 13, TUI.TXT, 0, x1 - ab.end.x - lw - 70.0)
	if not won and str(kd.get("cause", "")) != "":
		_t(Vector2(x1, y), str(kd.cause), 12, Color(0.85, 0.6, 1.0), 2)


## 编队：竖排行（像框、名字、入队、全队占比条、百分比），行高撑满给定高度；Enter / 点击进干员详情
func _squad_list(r: Rect2, t: float, title: bool) -> void:
	var rws: Array = rows()
	var y := r.position.y
	if title:
		var tw := _t(Vector2(r.position.x, y + 10.0), "编队", 16, TUI.TXT)
		_t(Vector2(r.position.x + tw + 14.0, y + 10.0), "全队伤害 %s · 每秒 %s" % [fmt_n(float(model.get("total", 0.0))), fmt_n(float(model.get("dps", 0.0)))], 13, TUI.TXT2, 0, r.size.x - tw - 20.0)
		y += 26.0
	var n := rws.size()
	if n == 0:
		return
	var gap := 6.0
	var rh: float = minf(84.0, (r.end.y - y + gap) / n)
	var vmax := 0.0
	for rw in rws:
		vmax = maxf(vmax, float(rw.share))
	for i in n:
		var row: Dictionary = rws[i]
		var cr := Rect2(r.position.x, y + i * rh, r.size.x, rh - gap)
		if _hovered(cr) and (sel != i or zone != 1):
			sel = i
			zone = 1
		cells.append([cr, "card", i])
		var on := zone == 1 and sel == i
		var rr := _tile(cr, 1 if rh < 48.0 else 2, on)
		var ink: Color = TUI.SEL_INK if on else TUI.TXT
		var sub: Color = TUI.SEL_SUB if on else TUI.TXT2
		var cl: float = _ps / _c.k
		_ci().draw_rect(Rect2(rr.position.x + cl * 2.0, rr.position.y + cl * 3.0, cl * 2.0, rr.size.y - cl * 6.0), row.col)
		var pb := Rect2(rr.position.x + 10.0, rr.position.y + 3.0, minf(52.0, rr.size.y * 1.1), rr.size.y - 6.0)
		_portrait(str(row.key), pb, 1.0 if rr.size.y < 60.0 else 2.0)
		var nx := pb.end.x + 8.0
		var cy := rr.get_center().y
		var two: bool = rr.size.y >= 40.0
		_t(Vector2(nx, cy - (9.0 if two else 0.0)), str(row.name), 14 if two else 13, ink, 0, 110.0)
		if two:
			_t(Vector2(nx, cy + 10.0), _join_text(row), 11, sub, 0, 110.0)
		var bx := nx + 120.0
		var bw := rr.end.x - 72.0 - bx
		var fill := 1.0 if UM.rm() else UM.out_cubic((t - SEG0 - UM.stagger(i, SEG_S)) / UM.T2)
		if bw > 20.0:
			_bar(Rect2(bx, cy - 4.0, bw, 8.0), [[1.0, row.col]], fill * float(row.share) / maxf(0.001, vmax))
		_p(Vector2(rr.end.x - 12.0, cy), "%d%%" % int(round(float(row.pct) * _count_k(t, i))), 2.0, ink, 2)


## 藏品格（右上，按件数定高；放不下时缩格）：等级点、遭诅 / 升华角标；返回格子底边 y
func _relic_grid(r: Rect2, t: float, title: bool) -> float:
	var rl: Array = relics()
	var x0 := r.position.x
	var y := r.position.y
	if title:
		var tw := _t(Vector2(x0, y + 10.0), "藏品", 16, TUI.TXT)
		_p(Vector2(x0 + tw + 10.0, y + 10.0), "%d" % rl.size(), 2.0, TUI.CY)
		y += 26.0
	if rl.is_empty():
		_t(Vector2(x0, y + 12.0), "这次探索没有获得藏品", 13, TUI.TXT2)
		_per_row = 1
		return y + 24.0
	var cell := 46.0
	var per := maxi(1, int(r.size.x / cell))
	var max_rows := 3 if not _ph else 5
	while ceili(rl.size() / float(per)) > max_rows and cell > 30.0:
		cell -= 2.0
		per = maxi(1, int(r.size.x / cell))
	_per_row = per
	rel = clampi(rel, 0, rl.size() - 1)
	var n := rl.size()
	var step := minf(0.035, 0.42 / maxf(1.0, n))
	var cl: float = _ps / _c.k
	var mp := _mouse()
	_pop_anchor = Rect2()
	for i in n:
		var it: Dictionary = rl[i]
		var cr := Rect2(x0 + (i % per) * cell, y + (i / per) * cell, cell - 6.0, cell - 6.0)
		cells.append([cr, "relic", i])
		if not g.kb_nav and not Pad.using and cr.has_point(mp):
			zone = 0
			rel = i
		var on := zone == 0 and rel == i
		if on:
			_pop_anchor = cr
		var d := SEG0 + i * step
		var e := 1.0 if UM.rm() else clampf((t - d) / UM.T2, 0.0, 1.0)
		if e <= 0.0:
			continue
		var a := clampf((t - d) / UM.T1, 0.0, 1.0) if not UM.rm() else 1.0
		var col: Color = UI.CAT_COL.get(str(it.cat), UI.GOLD)
		var rr := _tile(cr, 1, on, a)
		_ci().draw_rect(Rect2(rr.position + Vector2(cl * 2.0, cl * 2.0), Vector2(cl * 4.0, cl)), _fa(col, a))
		var sc := 1.0 if UM.rm() else 0.6 + 0.4 * UM.out_back(e, 1.4)
		var isz := (32.0 if cell >= 40.0 else 16.0) * sc
		var ic := _relic_tex(str(it.id))
		var c := rr.get_center()
		if ic != null:
			_ci().draw_texture_rect(ic, Rect2((c - Vector2(isz, isz) * 0.5).round(), Vector2(isz, isz)), false, Color(1, 1, 1, a))
		else:
			_t(c, str(it.name).substr(0, 1), 14, _fa(col, a), 1)
		if int(it.lv) > 1:
			for q in mini(int(it.lv), 5):
				_ci().draw_rect(Rect2(rr.position.x + cl * 2.0 + q * cl * 3.0, rr.end.y - cl * 3.0, cl * 2.0, cl * 1.5), _fa(col.lightened(0.3), a))
		var rar := str(it.rarity)
		if rar == "遭诅古物" or rar == "升华":
			var mc: Color = UI.RED if rar == "遭诅古物" else UI.VIOLET
			var p0 := Vector2(rr.end.x - cl * 1.0, rr.position.y + cl * 1.0)
			_ci().draw_colored_polygon(PackedVector2Array([p0, p0 + Vector2(-cl * 6.0, 0), p0 + Vector2(0, cl * 6.0)]), _fa(mc, a))
	return y + ceilf(n / float(per)) * cell - 6.0


## 选中 / 悬停藏品的说明：贴着图标下方弹出（画在数据之上，不占版面）；没选中藏品时不画
func _relic_popup(x_max: float, _grid_bottom: float) -> void:
	if zone != 0 or _pop_anchor.size.x <= 0.0 or relics().is_empty():
		return
	var it: Dictionary = relics()[rel]
	var w := 340.0 if not _ph else 380.0
	var lines: PackedStringArray = UI.wrap_lines(g.font, str(it.desc), 12, w - 28.0)
	var nl := mini(lines.size(), 3)
	var h := 40.0 + nl * 17.0
	var x := clampf(_pop_anchor.position.x, 16.0, x_max - w)
	var y := _pop_anchor.end.y + 8.0
	var pr := _panel(Rect2(x, y, w, h), 2, 0.98)
	var ax := clampf(_pop_anchor.get_center().x, pr.position.x + 12.0, pr.end.x - 12.0)
	_ci().draw_colored_polygon(PackedVector2Array([Vector2(ax - 6, pr.position.y), Vector2(ax, pr.position.y - 6), Vector2(ax + 6, pr.position.y)]), TUI.EDGE)
	var nw := _t(Vector2(pr.position.x + 14, pr.position.y + 18), str(it.name), 15, TUI.TXT, 0, w * 0.55)
	var tag := str(it.rarity)
	if int(it.max) > 1:
		tag = "Lv.%d / %d · %s" % [int(it.lv), int(it.max), tag]
	var rc: Color = UI.RED if str(it.rarity) == "遭诅古物" else (UI.VIOLET if str(it.rarity) == "升华" else TUI.CY_DIM)
	_t(Vector2(pr.position.x + 24 + nw, pr.position.y + 18), tag + " · " + str(it.cat), 11, rc, 0, w - nw - 40.0)
	for li in nl:
		var ln := lines[li]
		if li == 2 and lines.size() > 3:
			ln = ln.substr(0, maxi(0, ln.length() - 1)) + "…"
		_t(Vector2(pr.position.x + 14, pr.position.y + 40 + li * 17), ln, 12, TUI.TXT2)


## 数据：标签左、数值右、细分隔线。行高撑满给定高度（20–30）；单列放不下改两列，还放不下才滚动。cols 0 = 自动
func _stats(r: Rect2, t: float, cols_in: int) -> void:
	var st: Array = model.get("stats", [])
	var x0 := r.position.x
	var y := r.position.y + 10.0
	_t(Vector2(x0, y), "数据", 16, TUI.TXT)
	_p(Vector2(x0 + 44, y), "STATS", 1.0, TUI.CY_DIM, 0, 2)
	var y0 := y + 16.0
	var avail := r.end.y - y0
	var cols := cols_in
	if cols == 0:
		cols = 1 if avail / maxf(1.0, st.size()) >= 20.0 else 2
	var per_col := ceili(st.size() / float(cols))
	var rh := clampf(avail / maxf(1.0, per_col), 20.0, 30.0)
	var gap := 28.0
	var cw: float = (r.size.x - gap * (cols - 1)) / cols
	var rows_fit := maxi(1, int(avail / rh))
	var vis := mini(st.size(), rows_fit * cols)
	stat_scroll = clampi(stat_scroll, 0, maxi(0, st.size() - vis))
	for k in mini(vis, st.size() - stat_scroll):
		var i := stat_scroll + k
		var s: Dictionary = st[i]
		var c := k / rows_fit
		var cx := x0 + c * (cw + gap)
		var ry := y0 + (k % rows_fit) * rh + rh * 0.5
		_ci().draw_rect(Rect2(cx, roundf(ry + rh * 0.5 - 1.0), cw, 1), Color(1, 1, 1, 0.07))
		_t(Vector2(cx, ry), str(s.label), 13, TUI.TXT2)
		var ck := 1.0 if UM.rm() else UM.linear((t - SEG0 - mini(i, 12) * 0.02) / UM.T3)
		var v: float = float(s.v) * ck
		var txt: String
		match str(s.fmt):
			"t":
				txt = fmt_t(v)
			"pct":
				txt = "%d%%" % int(round(v))
			"txt":
				txt = str(s.get("txt", "")) if ck >= 1.0 else fmt_n(v)
			_:
				txt = fmt_n(v)
		var vw := _t(Vector2(cx + cw, ry), txt, 14, TUI.TXT, 2)
		if s.has("sub") and str(s.sub) != "":
			var lw0: float = g.font.get_string_size(str(s.label), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			_t(Vector2(cx + cw - vw - 10, ry), str(s.sub), 11, TUI.CY_DIM, 2, cw - vw - lw0 - 24.0)
	if st.size() > vis:
		_p(Vector2(x0 + r.size.x, y), "%d-%d / %d" % [stat_scroll + 1, mini(stat_scroll + vis, st.size()), st.size()], 1.0, TUI.CY_DIM, 2)


## 计数动画系数：第 i 段落位前 0.1 秒开始，T3 线性数到终值
func _count_k(t: float, i: int) -> float:
	if UM.rm() or t >= 90.0:
		return 1.0
	return UM.linear((t - (SEG0 + UM.stagger(i, SEG_S) + SEG) + 0.1) / UM.T3)


# ------------------------------------------------------------------ 详情
func _draw_detail(vs: Vector2) -> void:
	var rws: Array = rows()
	if rws.is_empty():
		page = 0
		return
	sel = clampi(sel, 0, rws.size() - 1)
	var row: Dictionary = rws[sel]
	var t := _mt(t_page)
	var M := 40.0 if not _ph else 24.0
	var top := _header(vs, "作战记录 · " + str(row.name), "RUN RECORD // " + str(row.en)) + (6.0 if not _ph else 0.0)
	# 换干员：‹ 01 / 05 ›（可点）
	var nx := vs.x - M
	var ny := (36.0 if not _ph else 24.0)
	var lab := "%02d / %02d" % [sel + 1, rws.size()]
	var lw := _p(Vector2(nx - 22, ny), lab, 1.0, TUI.TXT2, 2)
	var pr := Rect2(nx - 22 - lw - 30, ny - 14, 26, 28)
	var nr := Rect2(nx - 18, ny - 14, 22, 28)
	_p(Vector2(pr.get_center().x, ny), "<", 1.0, TUI.CY if sel > 0 else TUI.CY_DIM, 1)
	_p(Vector2(nr.get_center().x, ny), ">", 1.0, TUI.CY if sel < rws.size() - 1 else TUI.CY_DIM, 1)
	cells.append([pr.grow(8.0), "prev", null])
	cells.append([nr.grow(8.0), "next", null])
	var bot := vs.y - (72.0 if not _ph else 66.0)
	var lw2 := 280.0 if not _ph else 210.0
	# 身份卡按内容定高（10-12 版式反馈：不留大空面板）
	var nl := 4 + (1 if int(row.casts) > 0 else 0) + (1 if float(row.heal) >= 1.0 else 0) + (1 if float(row.left_t) >= 0.0 else 0)
	if str(model.get("best", {}).get("op", "")) == str(row.name):
		nl += 1
	var big_id: bool = bot - top > 420.0
	var id_h: float = (186.0 if big_id else 120.0) + (60.0 if not _ph else 46.0) + nl * (30.0 if not _ph else 22.0) + 10.0
	_id_big = big_id
	var lr := _tile(Rect2(M, top, lw2, minf(bot - top, id_h)), 3, true)
	_identity(lr, row)
	var leader: bool = bool(row.leader)
	var x1 := vs.x - M
	var mx0 := M + lw2 + (28.0 if not _ph else 16.0)
	var sw: float = 300.0 if not _ph else 250.0
	var mx1 := (x1 - sw - (28.0 if not _ph else 16.0)) if leader else x1
	_sources(Rect2(mx0, top, mx1 - mx0, bot - top), row, t)
	if leader:
		_survival(Rect2(x1 - sw, top, sw, bot - top), t)
	var br := Rect2(vs.x - M - (160.0 if not _ph else 150.0), vs.y - (52.0 if not _ph else 56.0), 160.0 if not _ph else 150.0, 34.0 if not _ph else 44.0)
	_button(br, "返回总览", "ESC" if not Pad.using else "B", "back", _hovered(br))
	if not _ph:
		_hints(Vector2(M, br.get_center().y), [["← →" if not Pad.using else "LB RB", "换干员"]])


func _identity(lr: Rect2, row: Dictionary) -> void:
	var x0 := lr.position.x + (20.0 if not _ph else 14.0)
	var x1 := lr.end.x - (18.0 if not _ph else 12.0)
	var y := lr.position.y
	var big := _id_big
	var cl: float = _ps / _c.k
	_ci().draw_rect(Rect2(lr.position.x + cl * 4.0, y + cl * 2.0, lr.size.x - cl * 8.0, cl * 2.0), row.col)
	if row.key != RunStats.OTHER:
		_portrait(str(row.key), Rect2(lr.position.x + 16.0, y + 14.0, lr.size.x - 32.0, 150.0 if big else 98.0), 3.0 if big else 2.0)
		y += 186.0 if big else 120.0
	else:
		y += 40.0
	_t(Vector2(x0, y), str(row.name), 24 if not _ph else 19, TUI.SEL_INK, 0, lr.size.x - 30.0)
	y += 24.0 if not _ph else 20.0
	_t(Vector2(x0, y), _join_text(row, true), 13 if not _ph else 11, TUI.SEL_SUB, 0, lr.size.x - 30.0)
	y += 36.0 if not _ph else 26.0
	var lines: Array = [["造成伤害", fmt_n(float(row.dmg))], ["全队占比", "%d%%" % int(row.pct)], ["每秒", fmt_n(float(row.dps))],
		["击杀", fmt_n(float(row.kills))]]
	if int(row.casts) > 0:
		lines.append(["技能", "%d" % int(row.casts)])
	if float(row.heal) >= 1.0:
		lines.append(["治疗主控", fmt_n(float(row.heal))])
	var best: Dictionary = model.get("best", {})
	if str(best.get("op", "")) == str(row.name) and float(best.get("v", 0.0)) > 0.0:
		lines.append(["最高单次", fmt_n(float(best.v))])
	var lh := 30.0 if not _ph else 22.0
	for ln in lines:
		if y > lr.end.y - 12.0:
			break
		_t(Vector2(x0, y), ln[0], 14 if not _ph else 12, TUI.SEL_SUB)
		_p(Vector2(x1, y), ln[1], 2.0, TUI.SEL_INK, 2)
		y += lh


## 伤害来源：前 5 条 + 其他；不加框，留白
func _sources(r: Rect2, row: Dictionary, t: float) -> void:
	var x0 := r.position.x
	var x1 := r.end.x
	var y := r.position.y + 14.0
	_t(Vector2(x0, y), "伤害来源", 16 if not _ph else 14, TUI.TXT)
	var srcs: Array = top_sources(row.sources, TOP_SRC)
	if srcs.is_empty():
		_t(Vector2(x0, y + 40), "没有造成伤害", 14, TUI.TXT2)
		return
	var rh: float = minf(64.0 if not _ph else 48.0, (r.end.y - y - 24.0) / maxi(1, srcs.size()))
	y += rh * 0.75 + 6.0
	var vmax: float = maxf(1.0, float(srcs[0].v))
	for k in srcs.size():
		var s: Dictionary = srcs[k]
		var other: bool = str(s.kind) == "其他" and str(s.name) == "其他"
		_t(Vector2(x0, y), str(s.name), 15 if not _ph else 13, TUI.TXT2 if other else TUI.TXT, 0, x1 - x0 - 150.0)
		_p(Vector2(x1, y), "%d%%" % int(s.pct), 2.0, TUI.CY, 2)
		_p(Vector2(x1 - (64.0 if not _ph else 44.0), y), fmt_n(float(s.v)), 1.0, TUI.TXT2, 2)
		var e := 1.0 if UM.rm() else UM.out_cubic((t - UM.stagger(k, 0.06)) / UM.T2)
		_bar(Rect2(x0, y + (14.0 if not _ph else 11.0), x1 - x0, 6.0 if not _ph else 4.0), [[1.0, TUI.CY_DIM if other else row.col]], e * float(s.v) / vmax)
		y += rh


## 主控「生存」：受到伤害、生命回复（前 3 个来源）、灯火通明占比、源石锭熔铸
func _survival(r: Rect2, t: float) -> void:
	var ld: Dictionary = model.get("leader", {})
	# 面板按内容定高（不留大空面板，10-12 版式反馈）
	var lh0 := 26.0 if not _ph else 20.0
	var nh: int = mini(3, (ld.get("heal_src", []) as Array).size())
	var h := 26.0 + lh0 + 8.0 + (lh0 + 6.0) + lh0 + nh * (lh0 - 4.0) + 10.0 + lh0 + 6.0 + 14.0
	if bool(model.get("fuse", {}).get("on", false)):
		h += lh0
	var rr := _panel(Rect2(r.position, Vector2(r.size.x, minf(r.size.y, h))), 2, 0.9)
	var x0 := rr.position.x + (18.0 if not _ph else 12.0)
	var x1 := rr.end.x - (18.0 if not _ph else 12.0)
	var y := rr.position.y + 26.0
	var fs := 14 if not _ph else 12
	var lh := 26.0 if not _ph else 20.0
	_t(Vector2(x0, y), "生存", 16 if not _ph else 14, TUI.TXT)
	y += lh + 8.0
	_t(Vector2(x0, y), "受到伤害", fs, TUI.TXT2)
	_p(Vector2(x1, y), fmt_n(float(ld.get("taken", 0.0))), 2.0, TUI.TXT, 2)
	y += lh + 6.0
	_t(Vector2(x0, y), "生命回复", fs, TUI.TXT2)
	_p(Vector2(x1, y), fmt_n(float(ld.get("heal", 0.0))), 2.0, TUI.TXT, 2)
	y += lh
	var hl: Array = ld.get("heal_src", [])
	var hmax: float = float(hl[0].v) if not hl.is_empty() else 1.0
	var e := 1.0 if UM.rm() else UM.out_cubic(t / UM.T3)
	for s in hl.slice(0, 3):
		_t(Vector2(x0 + 10, y), str(s.name), 12 if not _ph else 11, TUI.TXT2, 0, 90.0)
		_bar(Rect2(x0 + 100, y - 3, x1 - x0 - 160, 6), [[1.0, UI.GREEN]], e * float(s.v) / hmax)
		_p(Vector2(x1, y), fmt_n(float(s.v)), 1.0, TUI.TXT2, 2)
		y += lh - 4.0
	y += 10.0
	var ls: Array = model.get("lamp_s", [0, 0, 0, 0])
	var lt := 0.0
	for v in ls:
		lt += float(v)
	if lt > 0.0:
		_t(Vector2(x0, y), "灯火通明", fs, TUI.TXT2)
		_p(Vector2(x1, y), "%d%%" % int(round(float(ls[0]) / lt * 100.0)), 2.0, TUI.TXT, 2)
		y += lh + 6.0
	var fu: Dictionary = model.get("fuse", {})
	if bool(fu.get("on", false)) and y < rr.end.y - 16.0:
		_t(Vector2(x0, y), "源石锭熔铸", fs, TUI.TXT2)
		_t(Vector2(x1, y), "全队伤害 +%s%%" % str(snappedf(float(fu.pct) * 100.0, 0.1)).trim_suffix(".0"), fs, TUI.TXT, 2)
