extends RefCounted
## 界面 · 作战记录（局终统计，docs/77，2026-10-12）：胜利 / 结局结算与失败结算上的「作战记录」按钮（Tab / C）打开，
## 不替换结局演出与结算面板；Esc / Ⓑ / 「返回结算」回到结算。
## 结构参考雨中冒险 2 的结算「Run Report」（10-12 用户），版式按版式三案选定的「左档案右数据」（v3b，docs/77 §3）：
## 左 40%：结果横幅（探索完成 / 探索终止 + 结局名或击倒者）、主控 / 击倒者卡、竖排编队（行高撑满）；
## 右 60%：藏品格（拾取顺序，按件数定高；选中 / 悬停时说明贴着图标弹出）+ 数据（标签左、数值右，行高撑满剩余高度）。
## 编队行上 Enter / 点击进干员详情（前 5 个伤害来源 + 主控生存）。手机：结果横幅 | 主控卡常驻，下面三页 编队 / 藏品 / 数据。
## 干员 / 敌人像一律按不透明包围盒缩放放进像框（_fit），不出框。风格：局外 T5s（docs/37 §8）。
## 动效（docs/62 §3.24）：主动作「藏品依次弹出」（每格 T2 out_back(1.4)，0.6 → 1 倍，间隔 ≤ 35 ms，整组 ≤ 0.6 秒）；
##   编队输出条逐条依次增长（0.6–0.9 秒一条、数字跟着滚、队长最后出，BAR_* 常量）、统计数值计数（次要）。减少动态：直接终态，只留 T1 淡入。
## 数据只读 run/run_stats.gd 的 model（不碰 g.rng、不改对局状态）。
## 10-29 用户：视觉改成结算 A「作战报告」的语言——暗底 + 斜向浅光 + 左上徽记、配色跟本局队长（SB.lead_theme）、
##   描边英文小标题、数据做成数据格、编队输出条同结算（细槽 + 干员色、队长行底色）；版式与键位不变。
##   数字一律直接显示终值（只淡入 / 滑入、输出条照常增长）：原来数值从 0 滚动、队长那条最后才出，
##   开页约 1 秒内截图会看到「队长 0%」「藏品 0」「探索用时 01:57 ≠ 02:42」这类中间值。
## 从对局记录（run_log_screen）进来时返回键写「返回对局记录」，关掉回到列表。

const UI = preload("res://scripts/ui.gd")
const UM = preload("res://scripts/ui_motion.gd")
const TUI = preload("res://scripts/screens/tide_ui.gd")
const A = preload("res://scripts/art.gd")
const D = preload("res://scripts/data.gd")
const RunStats = preload("res://scripts/run/run_stats.gd")
const Game = preload("res://scripts/game.gd")
const HH = preload("res://scripts/screens/hh_style.gd")
const SB = preload("res://scripts/screens/settle/settle_base.gd")
const OpFig = preload("res://scripts/screens/op_figure.gd")

const SEG0 := 0.08      # 第一格 / 第一段开始
const SEG_S := 0.07     # 占比条段间错开
const SEG := UM.T2      # 每段滑入时长
const TOP_SRC := 5      # 详情里列出的伤害来源条数（其余并成「其他」）
## 输出条节奏（10-25 用户「干员的输出条出来的太短」，docs/62 §3.24）：逐条依次增长，单条 BAR_D0～BAR_D0+BAR_D1 秒（越长的条越久，按数值缓动），
## 百分比数字跟着条滚；队长那条最后出、多等一拍、多长一点，落位后条加粗一格。条的起点：藏品弹出（SEG0 起）之后
const BAR0 := 0.30      # 第一条开始
const BAR_SPAN := 1.2   # 非队长各条的开始时刻最多铺开这么久（人多时间隔收紧）
const BAR_GAP := 0.24   # 相邻两条的开始间隔上限
const BAR_D0 := 0.60    # 单条最短时长（占比最小的）
const BAR_D1 := 0.30    # 占比最大的比最短的多的时长
const CAP_HOLD := 0.14  # 队长比最后一名队友多等的一拍
const CAP_EXTRA := 0.15 # 队长这条再长的时长
const STAT0 := 0.45     # 右侧数据行的数字开始滚动

var g: Game
var open := false
var back_label := "返回结算"   # 从对局记录进来时是「返回对局记录」
var _acc := HH.CYB            # 本页主题色（队长设定色，失败降饱和）
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
var _rel_row0 := 0      # 藏品格滚动：最上面画第几行（藏品不设上限，压到 30 像素格仍放不下时才滚，10-12）
var _bar_t0: Array = []   # 每个干员行的输出条开始时刻 / 时长（show_model 里按占比算好，不在每帧新建）
var _bar_dur: Array = []
var _bar_end := 0.0       # 最后一条落位的时刻
var _rel_seen := -1     # 上一帧的选中藏品：选中变了才把它滚进视野，滚轮滚动不被拉回
var _relic_rect := Rect2()   # 藏品格所在区域（滚轮落在这里滚藏品，否则滚数据）
# 每帧绘制用
var _c: Dictionary
var _ps := 2
var _ph := false


func _init(game: Game) -> void:
	g = game


## 打开：拍一份当前对局的记录
func open_for_run() -> void:
	show_model(RunStats.model(RunStats.snapshot(g)))
	back_label = "返回结算"


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
	_rel_row0 = 0
	_rel_seen = -1
	skipped = false
	t_open = UM.now()
	t_page = t_open
	_calc_bars()
	_last_mouse = Vector2(-1, -1)
	g.ui_skip = true   # 结算面板自己的动效此时已经不需要了


## 算每行输出条的开始 / 时长：非队长按行序依次出，队长最后；时长随占比（长的条走得久）
func _calc_bars() -> void:
	var rws: Array = rows()
	var n := rws.size()
	_bar_t0.resize(n)
	_bar_dur.resize(n)
	var vmax := 0.001
	for rw in rws:
		vmax = maxf(vmax, float(rw.share))
	var others: Array = []
	var lead := -1
	for i in n:
		if bool(rws[i].leader) and lead < 0:
			lead = i
		else:
			others.append(i)
	var gap: float = minf(BAR_GAP, BAR_SPAN / maxf(1.0, float(others.size())))
	_bar_end = 0.0
	for k in others.size():
		var i: int = others[k]
		_bar_t0[i] = BAR0 + k * gap
		_bar_dur[i] = BAR_D0 + BAR_D1 * float(rws[i].share) / vmax
		_bar_end = maxf(_bar_end, float(_bar_t0[i]) + float(_bar_dur[i]))
	if lead >= 0:
		_bar_t0[lead] = BAR0 + others.size() * gap + (CAP_HOLD if not others.is_empty() else 0.0)
		_bar_dur[lead] = BAR_D0 + BAR_D1 + CAP_EXTRA
		_bar_end = maxf(_bar_end, float(_bar_t0[lead]) + float(_bar_dur[lead]))


## 第 i 行输出条的进度 0–1（out_cubic）；减少动态 / 终态 = 1
func _bar_k(t: float, i: int) -> float:
	if UM.rm() or t >= 90.0 or i >= _bar_t0.size():
		return 1.0
	return UM.out_cubic((t - float(_bar_t0[i])) / float(_bar_dur[i]))


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
	return _mt(t_open) < maxf(0.75, _bar_end + 0.05) if page == 0 else _mt(t_page) < 0.7


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
		if _relic_rect.has_point(_mouse()):
			_rel_row0 = maxi(0, _rel_row0 + signi(dy))   # 上限在 _relic_grid 里按行数夹
		else:
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
	size = UI.fs(size)   # 手机局内正文放大（UI.fk）；下面量字与画字都用放大后的字号
	var w: float = g.font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if max_w > 0.0 and w > max_w:
		while size > 10 and g.font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_w:
			size -= 1
		w = g.font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := pos.x - (w * 0.5 if align == 1 else (w if align == 2 else 0.0))
	_ci().draw_string(g.font, Vector2(roundf(x), roundf(pos.y + size * 0.36)), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	return w


## 像素字（数字 / 英文）：k = 逻辑倍数
func _p(pos: Vector2, s: String, k: float, col: Color, align := 0, track := 1) -> float:
	return TUI.ptext(_ci(), _c, pos, s, k * (0.7 if _ph else 1.0), col, track, align)


func _grid(r: Rect2) -> Dictionary:
	return TUI.grid(_c, r, _ps)


## 格子：暗卡底；选中 = 主题色淡底 + 细描边 + 左缘色条（同结算编队的队长行）
func _tile(r: Rect2, _n: int, on: bool, a := 1.0) -> Rect2:
	var ci := _ci()
	ci.draw_rect(r, _fa(HH.DARK2.lerp(_acc, 0.14) if on else HH.DARK2, a))
	if on:
		ci.draw_rect(r, _fa(_acc, 0.85 * a), false, 1.0)
		ci.draw_rect(Rect2(r.position, Vector2(4, r.size.y)), _fa(_acc, a))
	return r


## 面板：暗卡底 + 上缘一道主题色细线
func _panel(r: Rect2, _n: int, a := 0.92, fade := 1.0) -> Rect2:
	var ci := _ci()
	ci.draw_rect(r, _fa(HH.DARK2, minf(1.0, a + 0.05) * fade))
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), _fa(_acc, 0.7 * fade))
	return r


static func _fa(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)


## 输出条（同结算编队输出）：暗槽 + 实色段；segs = [[占比, 颜色]]；frac = 整条展开到多少
func _bar(r: Rect2, segs: Array, frac := 1.0, track := true, a := 1.0) -> void:
	var ci := _ci()
	var y0 := roundf(r.position.y)
	var h := maxf(2.0, roundf(r.size.y))
	if track:
		ci.draw_rect(Rect2(r.position.x, y0, r.size.x, h), _fa(HH.DARK3, a))
	var cx := r.position.x
	var lim := r.position.x + r.size.x * clampf(frac, 0.0, 1.0)
	for sg in segs:
		var x1 := minf(cx + r.size.x * float(sg[0]), lim)
		if x1 > cx:
			ci.draw_rect(Rect2(cx, y0, x1 - cx, h), _fa(sg[1], a))
		cx += r.size.x * float(sg[0])


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
## by_height：只按高度定倍数（编队行：每人按自己的包围盒放到同一高度，角色看起来一样大）；
## 宽出像框的部分左右对称裁掉（武器 / Mon3tr 这类横向宽的帧条），画出的矩形仍在框内
func _fit(tx: Texture2D, frame: Rect2, bb: Rect2, art: float, box: Rect2, kmax: float, a := 1.0, by_height := false) -> Rect2:
	if bb.size.x <= 0.0 or box.size.x <= 2.0 or box.size.y <= 2.0:
		return Rect2()
	var k_art: float = minf(kmax, box.size.y / (bb.size.y / art)) if by_height else minf(kmax, minf(box.size.x / (bb.size.x / art), box.size.y / (bb.size.y / art)))
	if k_art >= 1.0:
		# 按高度时：差一点就够下一个整数倍（≥ 0.75）就取下一倍、把头顶多出的几格裁掉——高帧条（法杖 / 帽子）和别人一样大
		k_art = (floorf(k_art) + 1.0) if (by_height and k_art - floorf(k_art) >= 0.75 and floorf(k_art) + 1.0 <= kmax) else floorf(k_art)
	var sc: float = k_art / art
	var src := Rect2(frame.position + bb.position, bb.size)
	if bb.size.y * sc > box.size.y:
		var keep_h: float = box.size.y / sc
		src.position.y += bb.size.y - keep_h
		src.size.y = keep_h
	if bb.size.x * sc > box.size.x:
		var keep: float = box.size.x / sc
		src.position.x += (bb.size.x - keep) * 0.5
		src.size.x = keep
	var sz := src.size * sc
	var pos := TUI.snap(_c, Vector2(box.get_center().x - sz.x * 0.5, box.end.y - sz.y))
	pos.x = clampf(pos.x, box.position.x, box.end.x - sz.x)
	pos.y = clampf(pos.y, box.position.y, box.end.y - sz.y)
	var dst := Rect2(pos, sz)
	_ci().draw_texture_rect_region(tx, dst, src, Color(1, 1, 1, a))
	portraits.append([dst, box])
	return dst


## 干员待机帧放进 box（编队行 / 队长卡 / 详情身份卡 / 对局记录的像框）：screens/op_figure.gd 统一比例、脚底对齐框底、超出裁掉。
## 10-30 起不再按各自帧条包围盒取倍数（水月 192 画布会被压成德克萨斯的一半高）；_kmax / _by_height 保留参数位，不再用
func _portrait(id: String, box: Rect2, _kmax := 0.0, _by_height := false) -> Rect2:
	if id == RunStats.OTHER or id == "":
		return Rect2()
	var idle: Dictionary = g.panel_ui.op_idle(id)
	if idle.is_empty():
		return Rect2()
	var nfr: int = maxi(1, int(idle.get("frames", 1)))
	var fr := 0 if (UM.rm() or UM.skip_all()) else int(UM.now() * 4.0) % nfr
	var dst := OpFig.draw(_ci(), idle, box, fr)
	if dst.has_area():
		portraits.append([dst, box])
	return dst


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
		x += _p(Vector2(x, pos.y), str(pr[0]), 1.0, HH.MUTE) + 6.0
		x += _t(Vector2(x, pos.y), str(pr[1]), 12, HH.MUTE) + 18.0


## 返回按钮：作战报告的幽灵按钮；焦点 / 悬停 = 主题色描边
func _button(r: Rect2, label: String, keyname: String, act: String, hov: bool) -> void:
	var ci := _ci()
	var kn := "" if (Pad.touch and not Pad.using) else keyname
	HH.ghost_btn(ci, g.font, r, label, kn)
	if hov:
		ci.draw_rect(r, _acc, false, 2.0)
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
		jt = "队长 · 开局"
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
	var won: bool = str(model.get("result", "")) == "win"
	var lr: Dictionary = {}
	for rw in rows():
		if rw.leader:
			lr = rw
	_acc = SB.lead_theme(lr.col if not lr.is_empty() else HH.CYB, won)
	var ci := _ci()
	ci.draw_rect(Rect2(Vector2.ZERO, vs), HH.DARK)
	# 斜向浅光 + 几道很淡的速度线（同结算 A）
	HH.fill(ci, PackedVector2Array([Vector2(vs.x * 0.48, 0), Vector2(vs.x, 0), Vector2(vs.x, vs.y), Vector2(vs.x * 0.36, vs.y)]), Color(1, 1, 1, 0.03))
	for i in 6:
		ci.draw_rect(Rect2(vs.x * 0.42 + float((i * 211) % 600), 18.0 + i * 19.0, 160.0 + float((i * 137) % 220), 2), Color(_acc, 0.08))
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


## 详情页标题行：徽记 + 小英文 + 中文标题 + 结果（胜利：结局名 · 探索完成；失败：探索终止，洋红）。返回下一块的 y
func _header(vs: Vector2, title: String, en: String) -> float:
	var x := 40.0 if not _ph else 24.0
	var y_en := 30.0 if not _ph else 22.0
	var y_t := 62.0 if not _ph else 46.0
	_emblem(Vector2(x + 12.0, y_en), _acc)
	_p(Vector2(x + 34, y_en), en, 1.0, HH.MUTE, 0, 2)
	var tw := _t(Vector2(x, y_t), title, 28 if not _ph else 22, HH.LIGHT)
	var won: bool = str(model.get("result", "")) == "win"
	var trial: bool = bool(model.get("trial", false))
	var rn: String = ("Boss 演练" if trial else str(model.get("ending_name", ""))) if won else ("中途退出" if bool(model.get("quit", false)) else "探索终止")
	var rs := ("完成" if trial else "探索完成") if won else ""
	var rc: Color = _acc if won else SB.MAG
	var x2 := x + tw + 22.0
	_ci().draw_rect(Rect2(x2, y_t - 10, 4, 20), rc)
	var w1 := _t(Vector2(x2 + 12, y_t), rn, 16 if not _ph else 14, HH.LIGHT)
	if rs != "":
		_t(Vector2(x2 + 22 + w1, y_t), rs, 14 if not _ph else 13, rc)
	return y_t + (36.0 if not _ph else 26.0)


## 徽记：三层菱形（浅 / 暗 / 主题色），同结算 A
func _emblem(c: Vector2, acc: Color, r0 := 13.0) -> void:
	for q in [[r0, HH.LIGHT], [r0 * 0.66, HH.DARK], [r0 * 0.33, acc]]:
		var r: float = q[0]
		HH.fill(_ci(), PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), q[1])


## 描边英文小标题（主题色描边、暗芯，同结算 A 的巨型结果字缩小版）+ 后面的中文；返回整段宽
func _sect(pos: Vector2, en: String, cn: String, k := 2.0) -> float:
	var kk := k * (0.7 if _ph else 1.0)
	var d := maxf(1.0, kk / 2.0)
	for o in [Vector2(-d, 0), Vector2(d, 0), Vector2(0, -d), Vector2(0, d)]:
		TUI.ptext(_ci(), _c, pos + o, en, kk, _acc, 2, 0)
	var w := TUI.ptext(_ci(), _c, pos, en, kk, HH.DARK, 2, 0)
	return w + 10.0 + _t(Vector2(pos.x + w + 10.0, pos.y), cn, 14 if not _ph else 13, HH.MUTE)


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
	var fw: int = tx.get_width() / 2   # 敌人常态帧条固定 2 帧（同 world 画敌人；帧不是正方形，不能按宽高比推帧数）
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
			_t(rr.get_center(), names[i], 15, HH.LIGHT if tab == i else HH.MUTE, 1)
			cells.append([trr.grow_individual(0, 6, 0, 6), "tab", i])
		var body := Rect2(M, ty + 46.0, vs.x - M * 2.0, bot - ty - 46.0)
		match tab:
			0:
				zone = 1
				_squad_list(body, t, false)
			1:
				zone = 0
				var gb := _relic_grid(body, t, true)
				_relic_popup(body.end.x, gb)
			2:
				_stats(body, t, 2)
	else:
		var lw := (vs.x - M * 2.0) * 0.4
		_banner(Rect2(M, top, lw, 112.0))
		_leader_card(Rect2(M, top + 124.0, lw, 150.0))
		_squad_list(Rect2(M, top + 286.0, lw, bot - top - 286.0), t, true)
		var rx := M + lw + 24.0
		var rr2 := Rect2(rx, top, vs.x - M - rx, bot - top)
		var gb2 := _relic_grid(Rect2(rx, top, rr2.size.x, (bot - top) * 0.45), t, true)
		_stats(Rect2(rx, gb2 + 14.0, rr2.size.x, bot - gb2 - 14.0), t, 0)
		_relic_popup(rr2.end.x, gb2)
	var br := Rect2(vs.x - M - (190.0 if not _ph else 170.0), vs.y - (52.0 if not _ph else 56.0), 190.0 if not _ph else 170.0, 34.0 if not _ph else 44.0)
	_button(br, back_label, "ESC" if not Pad.using else "B", "back", _hovered(br))
	if not _ph:
		_hints(Vector2(M, br.get_center().y), [["↑ ↓", "选干员"], ["← →", "编队 / 藏品"], ["ENTER" if not Pad.using else "A", "干员详情"]])


## 结果横幅（同结算 A）：徽记 + 两行小英文，描边英文结果字 + 中文结果色块，下面一行结局名 / 击倒者
func _banner(r: Rect2) -> void:
	var won: bool = str(model.get("result", "")) == "win"
	var trial: bool = bool(model.get("trial", false))
	var quit: bool = bool(model.get("quit", false))
	var ci := _ci()
	var x0 := r.position.x
	var y := r.position.y
	_emblem(Vector2(x0 + 12.0, y + 12.0), _acc)
	_p(Vector2(x0 + 34, y + 6), "RHODES ISLAND", 1.0, HH.MUTE, 0, 2)
	_p(Vector2(x0 + 34, y + 18), "RUN RECORD", 1.0, HH.MUTE, 0, 2)
	var word := "COMPLETE" if won else ("ABORTED" if quit else "FAILED")
	var kw := 5.0 if not _ph else 3.4
	var wy := y + (r.size.y * 0.5) + 2.0
	var d := maxf(1.0, kw / 3.0)
	for o in [Vector2(-d, 0), Vector2(d, 0), Vector2(0, -d), Vector2(0, d), Vector2(-d, -d), Vector2(d, d), Vector2(-d, d), Vector2(d, -d)]:
		TUI.ptext(ci, _c, Vector2(x0, wy) + o, word, kw, _acc if won else _acc.darkened(0.1), 1, 0)
	var ww := TUI.ptext(ci, _c, Vector2(x0, wy), word, kw, HH.DARK, 1, 0)
	var big := ("演练完成" if won else "演练结束") if trial else ("探索完成" if won else ("中途退出" if quit else "探索终止"))
	var bx := x0 + ww + 18.0
	var bw := minf(r.end.x - bx, 150.0 if not _ph else 112.0)
	var bh := 38.0 if not _ph else 30.0
	HH.para(ci, Rect2(bx, wy - bh * 0.5, bw, bh), (_acc if won else SB.MAG).lerp(HH.LIGHT, 0.6))
	_t(Vector2(bx + bw * 0.5 + 2.0, wy), big, 22 if not _ph else 17, HH.INK, 1, bw - 16.0)
	var sub := ""
	if won and not trial:
		sub = str(model.get("ending_name", ""))
	elif not won and not quit:
		var kd: Dictionary = model.get("killer", {})
		if not kd.is_empty():
			sub = "击倒者：" + str(kd.get("name", "")) + ((" · " + str(kd.cause)) if str(kd.get("cause", "")) != "" else "")
	sub += ("  ·  " if sub != "" else "") + "探索用时 " + fmt_t(float(model.get("t", 0.0))) + "  ·  " + str(model.get("tier_name", ""))
	_t(Vector2(x0, r.end.y - (10.0 if not _ph else 8.0)), sub, 14 if not _ph else 12, HH.LIGHT2, 0, r.size.x)


## 主控 / 击倒者卡：左边主控像（占整卡高）；右上 名字、探索时间、Lv. · 精英 · 难度；
## 右下单独一行 击倒者（失败）/ 击破的最终 Boss（胜利）：自己的像框（约 56 见方）+ 标签 + 名字 + 死因
func _leader_card(r: Rect2) -> void:
	var rr := _panel(r, 2, 0.92)
	var ld: Dictionary = {}
	for rw in rows():
		if rw.leader:
			ld = rw
	var pb := Rect2(rr.position.x + 10.0, rr.position.y + 8.0, (84.0 if not _ph else 64.0), rr.size.y - 16.0)
	if not ld.is_empty():
		_portrait(str(ld.key), pb, 3.0 if not _ph else 2.0)
	var tx := pb.end.x + 12.0
	var x1 := rr.end.x - 14.0
	var y := rr.position.y + (20.0 if not _ph else 16.0)
	_t(Vector2(tx, y), str(ld.get("name", "")), 16 if not _ph else 14, HH.LIGHT, 0, x1 - tx - 130.0)
	var tw0 := _p(Vector2(x1, y), fmt_t(float(model.get("t", 0.0))), 2.0, HH.LIGHT, 2)
	_t(Vector2(x1 - tw0 - 8.0, y), "用时", 11, HH.MUTE, 2)
	y += 20.0 if not _ph else 18.0
	_t(Vector2(tx, y), "Lv.%d · %s · %s" % [int(model.get("level", 1)), ["精零", "精英一", "精英二"][clampi(int(model.get("elite", 0)), 0, 2)], str(model.get("tier_name", ""))], 12, HH.MUTE, 0, x1 - tx - 70.0)
	y += 14.0 if not _ph else 12.0
	_ci().draw_rect(Rect2(tx, roundf(y), x1 - tx, 1), Color(1, 1, 1, 0.08))
	var won: bool = str(model.get("result", "")) == "win"
	var kd: Dictionary = model.get("final_boss", {}) if won else model.get("killer", {})
	var row_y := y + 4.0
	var row_h := rr.end.y - 6.0 - row_y
	if kd.is_empty():
		_t(Vector2(tx, row_y + row_h * 0.5), "演练完成" if won else "", 13, HH.MUTE)
		return
	var side := minf(56.0, row_h)
	var ab := Rect2(tx, row_y + (row_h - side) * 0.5, side, side)
	var fr: Array = _enemy_frame(str(kd.get("type", ""))) if str(kd.get("env", "")) == "" else _env_art(str(kd.env))
	if not fr.is_empty():
		var tx0: Texture2D = fr[0]
		var src: Rect2 = fr[1]
		var bb := _bbox(tx0, int(src.size.x), int(src.size.y), 1) if str(kd.get("env", "")) == "" else Rect2(Vector2.ZERO, src.size)
		_fit(tx0, src, bb, A.hires_of(tx0), ab, 3.0)   # 按美术像素取整数倍：@2x 敌人帧条（docs/94）和 1x 同尺寸
	var lx := ab.end.x + 10.0
	var cy := ab.get_center().y
	var two: bool = side >= 40.0
	_t(Vector2(lx, cy - (10.0 if two else 0.0)), "击破最终 Boss" if won else "击倒者", 12, HH.MUTE if won else SB.MAG)
	var nm_x := lx if two else lx + 52.0
	_t(Vector2(nm_x, cy + (10.0 if two else 0.0)), str(kd.get("name", "")), 15 if two else 13, HH.LIGHT, 0, x1 - nm_x - 60.0)
	if not won and str(kd.get("cause", "")) != "":
		_t(Vector2(x1, cy + (10.0 if two else 0.0)), str(kd.cause), 12, Color(0.85, 0.6, 1.0), 2)


## 编队：竖排行（像框、名字、入队、全队占比条、百分比），行高撑满给定高度；Enter / 点击进干员详情
func _squad_list(r: Rect2, t: float, title: bool) -> void:
	var rws: Array = rows()
	var y := r.position.y
	if title:
		var tw := _sect(Vector2(r.position.x, y + 10.0), "SQUAD", "编队")
		_t(Vector2(r.end.x, y + 10.0), "全队伤害 %s · 每秒 %s" % [fmt_n(float(model.get("total", 0.0))), fmt_n(float(model.get("dps", 0.0)))], 13, HH.MUTE, 2, r.size.x - tw - 20.0)
		y += 26.0
	var n := rws.size()
	if n == 0:
		return
	var gap := 6.0
	var rh: float = minf(140.0, (r.end.y - y + gap) / n)   # 人少时行变高，左栏底边和右栏对齐（10-12 版式反馈）
	var vmax := 0.0
	for rw in rws:
		vmax = maxf(vmax, float(rw.share))
	var kmax_l: float = 2.0 if rh - gap < 110.0 else 3.0
	for i in n:
		var row: Dictionary = rws[i]
		var cr := Rect2(r.position.x, y + i * rh, r.size.x, rh - gap)
		if _hovered(cr) and (sel != i or zone != 1):
			sel = i
			zone = 1
		cells.append([cr, "card", i])
		var on := zone == 1 and sel == i
		var rr := _tile(cr, 1 if rh < 48.0 else 2, on)
		if bool(row.leader) and not on:
			_ci().draw_rect(rr, Color(_acc, 0.10))
		var ink: Color = HH.LIGHT
		var sub: Color = HH.MUTE
		_ci().draw_rect(Rect2(rr.position.x + 8.0, rr.get_center().y - 6.0, 4, 12), row.col)
		var pb := Rect2(rr.position.x + 16.0, rr.position.y + 4.0, minf(180.0 if _ph else 130.0, rr.size.y * 1.6), rr.size.y - 8.0)   # 宽一点：横向宽的帧条（凯尔希带 Mon3tr）也能和别人同倍数
		_portrait(str(row.key), pb, kmax_l, true)   # 每人按自己的包围盒放到同一高度（10-12 制作人：共用倍数会被最宽的帧条拖小）
		var nx := pb.end.x + 8.0
		var cy := rr.get_center().y
		var two: bool = rr.size.y >= 40.0
		_t(Vector2(nx, cy - (9.0 if two else 0.0)), str(row.name), 14 if two else 13, ink, 0, 110.0)
		if two:
			_t(Vector2(nx, cy + 10.0), _join_text(row), 11, sub, 0, 110.0)
		var bx := nx + 120.0
		var bw := rr.end.x - 72.0 - bx
		var fill := _bar_k(t, i)
		if bw > 20.0:
			var bh := 6.0
			if bool(row.leader) and fill >= 1.0 and not UM.rm():
				bh = 6.0 + 2.0 * UM.out_back((t - float(_bar_t0[i]) - float(_bar_dur[i])) / UM.T2, 1.4)   # 队长落位后条加粗一点
			_bar(Rect2(bx, cy - bh * 0.5, bw, bh), [[1.0, row.col]], fill * float(row.share) / maxf(0.001, vmax))
		_p(Vector2(rr.end.x - 12.0, cy), "%d%%" % int(row.pct), 2.0, ink, 2)   # 终值（不跟着条滚：截图不会截到 0%）


## 藏品格（右上，按件数定高；放不下时缩格）：等级点、遭诅 / 升华角标；返回格子底边 y
func _relic_grid(r: Rect2, t: float, title: bool) -> float:
	var rl: Array = relics()
	var x0 := r.position.x
	var y := r.position.y
	if title:
		var tw := _sect(Vector2(x0, y + 10.0), "RELICS", "藏品")
		_p(Vector2(x0 + tw + 10.0, y + 10.0), "%d" % rl.size(), 2.0, HH.LIGHT)
		y += 26.0
	if rl.is_empty():
		_t(Vector2(x0, y + 12.0), "这次探索没有获得藏品", 13, HH.MUTE)
		_per_row = 1
		return y + 24.0
	var cell := 46.0
	var per := maxi(1, int(r.size.x / cell))
	var avail_h: float = r.end.y - y
	while ceili(rl.size() / float(per)) * cell > avail_h and cell > 30.0:
		cell -= 2.0
		per = maxi(1, int(r.size.x / cell))
	_per_row = per
	rel = clampi(rel, 0, rl.size() - 1)
	var n := rl.size()
	var total_rows: int = ceili(n / float(per))
	var vis_rows: int = maxi(1, mini(total_rows, int(avail_h / cell)))
	_relic_rect = Rect2(x0, y, r.size.x, vis_rows * cell)
	if total_rows > vis_rows:
		if rel != _rel_seen:
			_rel_row0 = clampi(_rel_row0, rel / per - vis_rows + 1, rel / per)
		_rel_row0 = clampi(_rel_row0, 0, total_rows - vis_rows)
		if title:
			_t(Vector2(r.end.x, y - 16.0), "第 %d–%d 行 / 共 %d 行" % [_rel_row0 + 1, _rel_row0 + vis_rows, total_rows], 12, HH.MUTE, 2)
	else:
		_rel_row0 = 0
	_rel_seen = rel
	var i0: int = _rel_row0 * per
	var i1: int = mini(n, (_rel_row0 + vis_rows) * per)
	var step := minf(0.035, 0.42 / maxf(1.0, i1 - i0))
	var cl: float = _ps / _c.k
	var mp := _mouse()
	_pop_anchor = Rect2()
	for i in range(i0, i1):
		var it: Dictionary = rl[i]
		var cr := Rect2(x0 + (i % per) * cell, y + (i / per - _rel_row0) * cell, cell - 6.0, cell - 6.0)
		cells.append([cr, "relic", i])
		if not g.kb_nav and not Pad.using and cr.has_point(mp):
			zone = 0
			rel = i
		var on := zone == 0 and rel == i
		if on:
			_pop_anchor = cr
		var d := SEG0 + (i - i0) * step
		var e := 1.0 if UM.rm() else clampf((t - d) / UM.T2, 0.0, 1.0)
		if e <= 0.0:
			continue
		var a := clampf((t - d) / UM.T1, 0.0, 1.0) if not UM.rm() else 1.0
		var col: Color = UI.CAT_COL.get(str(it.cat), UI.GOLD)
		var rr := cr
		_ci().draw_rect(rr, _fa(HH.DARK2, a))
		_ci().draw_rect(rr.grow(-2), _fa(Color(1, 1, 1, 0.5), a), false, 1.0)
		if on:
			_ci().draw_rect(rr.grow(1), _fa(_acc, a), false, 2.0)
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
		var mc: Color = SB.MAG if rar == "遭诅古物" else (Color8(170, 120, 255) if rar == "升华" else _acc)   # 左下角稀有度三角（同结算 A）
		var tz := 11.0 if cell >= 40.0 else 8.0
		_ci().draw_colored_polygon(PackedVector2Array([Vector2(rr.position.x, rr.end.y - tz), Vector2(rr.position.x + tz, rr.end.y), Vector2(rr.position.x, rr.end.y)]), _fa(mc, a))
	return y + vis_rows * cell - 6.0


## 选中 / 悬停藏品的说明：贴着图标下方弹出（画在数据之上，不占版面）；没选中藏品时不画
func _relic_popup(x_max: float, _grid_bottom: float) -> void:
	if zone != 0 or _pop_anchor.size.x <= 0.0 or relics().is_empty():
		return
	var it: Dictionary = relics()[rel]
	var w := 340.0 if not _ph else 380.0
	var lines: PackedStringArray = UI.wrap_lines(g.font, str(it.desc), 12, w - 28.0)
	var nl := mini(lines.size(), 3)
	var plh: float = UI.fs(12) + 5.0   # 说明行距（手机放大字号时跟着加）
	var h := 40.0 + nl * plh
	var x := clampf(_pop_anchor.position.x, 16.0, x_max - w)
	var y := _pop_anchor.end.y + 8.0
	var pr := _panel(Rect2(x, y, w, h), 2, 0.98)
	var ax := clampf(_pop_anchor.get_center().x, pr.position.x + 12.0, pr.end.x - 12.0)
	_ci().draw_colored_polygon(PackedVector2Array([Vector2(ax - 6, pr.position.y), Vector2(ax, pr.position.y - 6), Vector2(ax + 6, pr.position.y)]), _acc)
	var nw := _t(Vector2(pr.position.x + 14, pr.position.y + 18), str(it.name), 15, HH.LIGHT, 0, w * 0.55)
	var tag := str(it.rarity)
	if int(it.max) > 1:
		tag = "Lv.%d / %d · %s" % [int(it.lv), int(it.max), tag]
	var rc: Color = SB.MAG if str(it.rarity) == "遭诅古物" else (UI.VIOLET if str(it.rarity) == "升华" else HH.MUTE)
	_t(Vector2(pr.position.x + 24 + nw, pr.position.y + 18), tag + " · " + str(it.cat), 11, rc, 0, w - nw - 40.0)
	for li in nl:
		var ln := lines[li]
		if li == 2 and lines.size() > 3:
			ln = ln.substr(0, maxi(0, ln.length() - 1)) + "…"
		_t(Vector2(pr.position.x + 14, pr.position.y + 40 + li * plh), ln, 12, HH.MUTE)


## 数据：数据格（同结算 A：左缘色条 + 小标签 + 大数值 + 小注），按宽排 3–4 列、行高撑满（44–64）；还放不下才滚动。
## 数值直接是终值、只做淡入 + 右滑（10-29：滚动计数在截图里像错数）。cols_in 0 = 自动
func _stats(r: Rect2, t: float, cols_in: int) -> void:
	var st: Array = model.get("stats", [])
	var x0 := r.position.x
	var y := r.position.y + 10.0
	var tw := _sect(Vector2(x0, y), "STATS", "数据")
	if bool(model.get("log", false)):
		_t(Vector2(x0 + tw + 12.0, y), "（对局记录还原：只存了每名干员的合计）", 11, HH.MUTE)
	var y0 := y + 18.0
	var avail := r.end.y - y0
	var cols := cols_in if cols_in > 0 else (4 if r.size.x >= 600.0 else 3)
	if cols_in == 2:
		cols = 3 if r.size.x >= 560.0 else 2
	var gap := 10.0
	var cw: float = (r.size.x - gap * (cols - 1)) / cols
	var nrow := ceili(st.size() / float(cols))
	var rh := clampf(avail / maxf(1.0, nrow), 44.0, 64.0)
	var rows_fit := maxi(1, int(avail / rh))
	var vis_rows := mini(nrow, rows_fit)
	var max_scroll := maxi(0, nrow - vis_rows)
	stat_scroll = clampi(stat_scroll, 0, max_scroll)
	var big := 22 if rh >= 54.0 else 18
	if _ph:
		big = 17
	for k in vis_rows * cols:
		var i := (stat_scroll * cols) + k
		if i >= st.size():
			break
		var s: Dictionary = st[i]
		var cx := x0 + (k % cols) * (cw + gap)
		var cy := y0 + (k / cols) * rh
		var e := 1.0 if UM.rm() else UM.out_cubic((t - STAT0 - mini(i, 12) * 0.025) / UM.T2)
		if e <= 0.0:
			continue
		var dx := 18.0 * (1.0 - e)
		var a := e
		_ci().draw_rect(Rect2(cx + dx, cy + 4.0, 3, rh - 10.0), _fa(_acc if i < 4 else HH.DARK3, a))
		_t(Vector2(cx + 12 + dx, cy + 12.0), str(s.label), 12, _fa(HH.MUTE, a), 0, cw - 16.0)
		var v: float = float(s.v)
		var txt: String
		match str(s.fmt):
			"t":
				txt = fmt_t(v)
			"pct":
				txt = "%d%%" % int(round(v))
			"txt":
				txt = str(s.get("txt", ""))
			_:
				txt = fmt_n(v)
		var vw := _t(Vector2(cx + 12 + dx, cy + 12.0 + (rh - 18.0) * 0.5 + 2.0), txt, big if str(s.fmt) != "txt" else 14, _fa(HH.LIGHT, a), 0, cw - 16.0)
		if s.has("sub") and str(s.sub) != "":
			var sub := str(s.sub)
			var sw := cw - vw - 30.0
			while sub.length() > 1 and g.font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.fs(11)).x > sw:
				sub = sub.substr(0, sub.length() - 2) + "…"   # 放不下就截断，不压到右边一格
			_t(Vector2(cx + 18 + dx + vw, cy + 12.0 + (rh - 18.0) * 0.5 + 4.0), sub, 11, _fa(HH.MUTE, a))
	if max_scroll > 0:
		_p(Vector2(x0 + r.size.x, y), "%d-%d / %d" % [stat_scroll * cols + 1, mini((stat_scroll + vis_rows) * cols, st.size()), st.size()], 1.0, HH.MUTE, 2)


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
	var top := _header(vs, "作战记录 · " + str(row.name), "RHODES ISLAND  //  RUN RECORD  //  " + str(row.en)) + (6.0 if not _ph else 0.0)
	# 换干员：‹ 01 / 05 ›（可点）
	var nx := vs.x - M
	var ny := (36.0 if not _ph else 24.0)
	var lab := "%02d / %02d" % [sel + 1, rws.size()]
	var lw := _p(Vector2(nx - 22, ny), lab, 1.0, HH.MUTE, 2)
	var pr := Rect2(nx - 22 - lw - 30, ny - 14, 26, 28)
	var nr := Rect2(nx - 18, ny - 14, 22, 28)
	_p(Vector2(pr.get_center().x, ny), "<", 1.0, _acc if sel > 0 else HH.MUTE, 1)
	_p(Vector2(nr.get_center().x, ny), ">", 1.0, _acc if sel < rws.size() - 1 else HH.MUTE, 1)
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
	_t(Vector2(x0, y), str(row.name), 24 if not _ph else 19, HH.LIGHT, 0, lr.size.x - 30.0)
	y += 24.0 if not _ph else 20.0
	_t(Vector2(x0, y), _join_text(row, true), 13 if not _ph else 11, HH.MUTE, 0, lr.size.x - 30.0)
	y += 36.0 if not _ph else 26.0
	var lines: Array = [["造成伤害", fmt_n(float(row.dmg))], ["全队占比", "%d%%" % int(row.pct)], ["每秒", fmt_n(float(row.dps))],
		["击杀", fmt_n(float(row.kills))]]
	if int(row.casts) > 0:
		lines.append(["技能", "%d" % int(row.casts)])
	if float(row.heal) >= 1.0:
		lines.append(["治疗队长", fmt_n(float(row.heal))])
	var best: Dictionary = model.get("best", {})
	if str(best.get("op", "")) == str(row.name) and float(best.get("v", 0.0)) > 0.0:
		lines.append(["最高单次", fmt_n(float(best.v))])
	var lh := 30.0 if not _ph else 22.0
	for ln in lines:
		if y > lr.end.y - 12.0:
			break
		_t(Vector2(x0, y), ln[0], 14 if not _ph else 12, HH.MUTE)
		_p(Vector2(x1, y), ln[1], 2.0, HH.LIGHT, 2)
		y += lh


## 伤害来源：前 5 条 + 其他；不加框，留白
func _sources(r: Rect2, row: Dictionary, t: float) -> void:
	var x0 := r.position.x
	var x1 := r.end.x
	var y := r.position.y + 14.0
	_sect(Vector2(x0, y), "SOURCES", "伤害来源")
	var srcs: Array = top_sources(row.sources, TOP_SRC)
	if bool(model.get("log", false)):
		_t(Vector2(x0, y + 30), "对局记录只存了每名干员的合计与主要来源，没有分来源明细。", 13, HH.MUTE, 0, x1 - x0)
		y += 24.0
	if srcs.is_empty():
		_t(Vector2(x0, y + 40), "没有造成伤害", 14, HH.MUTE)
		return
	var rh: float = minf(64.0 if not _ph else 48.0, (r.end.y - y - 24.0) / maxi(1, srcs.size()))
	y += rh * 0.75 + 6.0
	var vmax: float = maxf(1.0, float(srcs[0].v))
	for k in srcs.size():
		var s: Dictionary = srcs[k]
		var other: bool = str(s.kind) == "其他" and str(s.name) == "其他"
		_t(Vector2(x0, y), str(s.name), 15 if not _ph else 13, HH.MUTE if other else HH.LIGHT, 0, x1 - x0 - 150.0)
		_p(Vector2(x1, y), "%d%%" % int(s.pct), 2.0, _acc, 2)
		_p(Vector2(x1 - (64.0 if not _ph else 44.0), y), fmt_n(float(s.v)), 1.0, HH.MUTE, 2)
		var e := 1.0 if UM.rm() else UM.out_cubic((t - k * 0.1) / 0.55)   # 来源条依次长出，单条 0.55 秒
		_bar(Rect2(x0, y + (14.0 if not _ph else 11.0), x1 - x0, 6.0 if not _ph else 4.0), [[1.0, HH.MUTE if other else row.col]], e * float(s.v) / vmax)
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
	_sect(Vector2(x0, y), "SURVIVAL", "生存", 1.5)
	y += lh + 8.0
	_t(Vector2(x0, y), "受到的伤害", fs, HH.MUTE)
	_p(Vector2(x1, y), fmt_n(float(ld.get("taken", 0.0))), 2.0, HH.LIGHT, 2)
	y += lh + 6.0
	_t(Vector2(x0, y), "生命回复", fs, HH.MUTE)
	_p(Vector2(x1, y), fmt_n(float(ld.get("heal", 0.0))), 2.0, HH.LIGHT, 2)
	y += lh
	var hl: Array = ld.get("heal_src", [])
	var hmax: float = float(hl[0].v) if not hl.is_empty() else 1.0
	var e := 1.0 if UM.rm() else UM.out_cubic(t / UM.T3)
	for s in hl.slice(0, 3):
		_t(Vector2(x0 + 10, y), str(s.name), 12 if not _ph else 11, HH.MUTE, 0, 90.0)
		_bar(Rect2(x0 + 100, y - 3, x1 - x0 - 160, 6), [[1.0, UI.GREEN]], e * float(s.v) / hmax)
		_p(Vector2(x1, y), fmt_n(float(s.v)), 1.0, HH.MUTE, 2)
		y += lh - 4.0
	y += 10.0
	var ls: Array = model.get("lamp_s", [0, 0, 0, 0])
	var lt := 0.0
	for v in ls:
		lt += float(v)
	if lt > 0.0:
		_t(Vector2(x0, y), "通明时长", fs, HH.MUTE)
		_p(Vector2(x1, y), "%d%%" % int(round(float(ls[0]) / lt * 100.0)), 2.0, HH.LIGHT, 2)
		y += lh + 6.0
	var fu: Dictionary = model.get("fuse", {})
	if bool(fu.get("on", false)) and y < rr.end.y - 16.0:
		_t(Vector2(x0, y), "源石锭熔铸", fs, HH.MUTE)
		_t(Vector2(x1, y), "全队伤害 +%s%%" % str(snappedf(float(fu.pct) * 100.0, 0.1)).trim_suffix(".0"), fs, HH.LIGHT, 2)
