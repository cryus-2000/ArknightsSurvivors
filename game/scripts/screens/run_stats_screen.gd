extends RefCounted
## 界面 · 作战记录（局终统计，docs/77，2026-10-12）：胜利 / 结局结算与失败结算上的「作战记录」按钮（Tab / C）打开，
## 不替换结局演出与结算面板；Esc / Ⓑ / 「返回结算」回到结算。
## - 总览：结果标签 + 六格要点（时间 / 难度 / 击杀 / 等级 / 藏品 / 最高单次）+ 全队伤害分段条 + 干员卡（含被替换离队的）
##   +「藏品与支援」卡 + 全队每秒伤害时间线（Boss 登场 / 击破标记）+ 探索记录（Boss 击破时刻、灯标、熔铸）。
## - 详情（在卡上 Enter / 点卡）：身份卡 + 伤害来源逐条；主控另有「生存」栏（承伤来源、回复来源、灯火四档时长、闪避 / 冲刺 / 护盾）。
## 风格：局外 T5s（docs/37 §8：阶梯切角、藏青抖动、S4 近白选中、像素字数字）。
## 动效（docs/62 §3.24）：主动作「分段拼合」——全队伤害条按干员一段段从右端滑入落位（out_cubic，错开 90 ms），
##   每段落位后对应卡片的伤害条注满、数字计数（次要）；时间线随后从左扫出。减少动态：直接终态，只留 T1 淡入。
## 数据只读 run/run_stats.gd 的 model（不碰 g.rng、不改对局状态）。

const UI = preload("res://scripts/ui.gd")
const UM = preload("res://scripts/ui_motion.gd")
const TUI = preload("res://scripts/screens/tide_ui.gd")
const RunStats = preload("res://scripts/run/run_stats.gd")
const Game = preload("res://scripts/game.gd")

const SEG0 := 0.10      # 第一段开始滑入
const SEG_S := 0.09     # 段间错开
const SEG := UM.T2      # 每段滑入时长
const TL0 := 0.45       # 时间线开始扫出
const TL := UM.T3
const LAMP_COL := [Color8(150, 220, 236), Color8(96, 160, 190), Color8(52, 84, 118), Color8(40, 46, 64)]
const KIND_COL := {"普攻": Color8(120, 150, 180), "技能": Color8(60, 200, 228), "天赋": Color8(124, 107, 255), "分支": Color8(47, 211, 160),
	"支援": Color8(126, 152, 184), "藏品": Color8(150, 160, 200), "其他": Color8(110, 120, 140)}

var g: Game
var open := false
var model: Dictionary = {}
var page := 0           # 0 总览 / 1 详情
var sel := 0            # 选中的行（干员卡）
var scroll := 0         # 详情：伤害来源滚动
var sub_tab := 0        # 手机详情（主控）：0 伤害来源 / 1 生存
var t_open := 0.0
var t_page := 0.0
var skipped := false
var cells: Array = []   # [Rect2, 动作, 参数]：命中区（终态位置）
var _last_mouse := Vector2(-1, -1)
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
	scroll = 0
	sub_tab = 0
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
	return _mt(t_open) < TL0 + TL if page == 0 else _mt(t_page) < 0.5


# ================================================================== 输入
## 按键（含手柄翻译过来的键）；返回是否处理
func key(k: int) -> bool:
	if not open:
		return false
	if motion_running() and k in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		skipped = true   # docs/62 §2.5：确认键先跳到终态
		return true
	var n: int = rows().size()
	if page == 0:
		match k:
			KEY_LEFT, KEY_A, KEY_UP, KEY_W, KEY_PAGEUP:
				_move(-1, n)
			KEY_RIGHT, KEY_D, KEY_DOWN, KEY_S, KEY_PAGEDOWN:
				_move(1, n)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_detail(sel)
			KEY_ESCAPE, KEY_TAB, KEY_C, KEY_BACKSPACE:
				Sfx.play("ui_ok", -6.0)
				close()
			_:
				return false
		return true
	match k:
		KEY_LEFT, KEY_A, KEY_PAGEUP:
			if sel > 0:
				_detail(sel - 1)
		KEY_RIGHT, KEY_D, KEY_PAGEDOWN:
			if sel < n - 1:
				_detail(sel + 1)
		KEY_UP, KEY_W:
			scroll = maxi(0, scroll - 1)
		KEY_DOWN, KEY_S:
			scroll += 1   # 绘制时按可见行数夹住
		KEY_TAB:
			if _ph and _is_leader(sel):
				sub_tab = 1 - sub_tab
				scroll = 0
				Sfx.play("ui_move")
		KEY_ESCAPE, KEY_BACKSPACE, KEY_C:
			page = 0
			t_page = UM.now()
			Sfx.play("ui_ok", -6.0)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			page = 0
			t_page = UM.now()
		_:
			return false
	return true


func _move(dx: int, n: int) -> void:
	var ns := clampi(sel + dx, 0, maxi(0, n - 1))   # 不循环（docs/67 §12 导航规则）
	if ns != sel:
		sel = ns
		g.kb_nav = true
		Sfx.play("ui_move")


func _detail(i: int) -> void:
	sel = i
	page = 1
	scroll = 0
	sub_tab = 0
	t_page = UM.now()
	Sfx.play("ui_ok", -4.0)


func _is_leader(i: int) -> bool:
	return i >= 0 and i < rows().size() and bool(rows()[i].leader)


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
	if open and page == 1:
		scroll = maxi(0, scroll + dy)


func _act(a: String, arg) -> void:
	match a:
		"card":
			_detail(int(arg))
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
		"tab":
			if sub_tab != int(arg):
				sub_tab = int(arg)
				scroll = 0
				Sfx.play("ui_move")


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


func _sprite(id: String, foot: Vector2, k: float, a := 1.0) -> void:
	if id == RunStats.OTHER or id == "":
		return
	var idle: Dictionary = g.panel_ui.op_idle(id)
	if idle.is_empty():
		return
	var tx: Texture2D = idle.tex
	var fw: int = idle.fw
	var fh: int = idle.fh
	var nfr: int = maxi(1, tx.get_width() / maxi(1, fw))
	var fr := 0 if (UM.rm() or UM.skip_all()) else int(UM.now() * 4.0) % nfr
	# k = 每个美术像素占几个逻辑像素；高清帧条（@2x，帧高 > 64）一格美术像素 = 2 个贴图像素
	var art_h: float = fh / 2.0 if fh > 64 else float(fh)
	var sz := Vector2(fw, fh) * (k * art_h / fh)
	var p := TUI.snap(_c, foot - Vector2(sz.x * 0.5, sz.y))
	_ci().draw_texture_rect_region(tx, Rect2(p, sz), Rect2(fr * fw, 0, fw, fh), Color(1, 1, 1, a))


## 操作提示：像素字键名 + 中文说明（触屏不画）
func _hints(pos: Vector2, pairs: Array) -> void:
	if Pad.touch and not Pad.using:
		return
	var x := pos.x
	for pr in pairs:
		x += _p(Vector2(x, pos.y), str(pr[0]), 1.0, TUI.CY) + 6.0
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


# ================================================================== 绘制
func draw(vs: Vector2) -> void:
	if not open:
		return
	_c = TUI.ctx(_ci())
	_ph = Cfg.touch_device() or vs.y < 560.0
	_ps = TUI.cell(_c, 1.4 if _ph else 2.0)
	cells.clear()
	var a0: float = UM.prog(t_open, UM.T1) if not skipped else 1.0
	_ci().draw_rect(Rect2(Vector2.ZERO, vs), Color(0.008, 0.03, 0.07, 0.86 * a0))
	var m := 14.0 if not _ph else 8.0
	_panel(Rect2(m, m, vs.x - m * 2.0, vs.y - m * 2.0), 3, 0.6 * a0)
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


func _header(vs: Vector2, title: String, en: String, right: String) -> float:
	var x := 32.0 if not _ph else 20.0
	var y_en := 34.0 if not _ph else 22.0
	var y_t := 60.0 if not _ph else 42.0
	_p(Vector2(x + 2, y_en), en, 1.0, TUI.CY, 0, 2)
	var tw := _t(Vector2(x, y_t), title, 28 if not _ph else 22, TUI.TXT)
	# 结果标签：胜利 = 结局名 + 探索完成（青），失败 = 探索终止（洋红）
	var won: bool = str(model.get("result", "")) == "win"
	var rn: String = str(model.get("ending_name", "")) if won else "探索终止"
	if bool(model.get("trial", false)):
		rn = "Boss 演练"
	var rs := "探索完成" if won and not bool(model.get("trial", false)) else ("完成" if won else "")
	var rc: Color = TUI.CY if won else UI.RED
	var fs := 15 if not _ph else 13
	var w1: float = g.font.get_string_size(rn, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var w2: float = g.font.get_string_size(rs, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x if rs != "" else 0.0
	var rx := x + tw + 20.0
	var rr := _panel(Rect2(rx, y_t - 16, w1 + w2 + 40.0, 32), 2, 0.95)
	_ci().draw_rect(Rect2(rr.position.x + _ps * 2.0 / _c.k, rr.position.y + 6, 2.0 * _ps / _c.k, rr.size.y - 12), rc)
	_t(Vector2(rr.position.x + 14, rr.get_center().y), rn, fs, TUI.TXT)
	if rs != "":
		_t(Vector2(rr.position.x + 22 + w1, rr.get_center().y), rs, 13, rc)
	if right != "":
		_p(Vector2(vs.x - (32.0 if not _ph else 20.0), y_en + 4), right, 1.0, TUI.TXT2, 2)
	return y_t + 30.0


# ------------------------------------------------------------------ 总览
func _draw_overview(vs: Vector2) -> void:
	var t := _mt(t_open)
	var rm: bool = UM.rm()
	var M := 32.0 if not _ph else 20.0
	var top := _header(vs, "作战记录", "RUN RECORD", "")
	var rws: Array = rows()
	# ---- 要点六格
	var kh := 58.0 if not _ph else 44.0
	var items: Array = [["探索时间" if not bool(model.get("trial", false)) else "演练用时", fmt_t(float(model.get("t", 0.0))), ""],
		["难度", _tier_short(), _tier_sub()], ["击杀", fmt_n(float(model.get("kills", 0))), ""],
		["等级", "LV %d" % int(model.get("level", 1)), ["精零", "精英一", "精英二"][clampi(int(model.get("elite", 0)), 0, 2)]],
		["藏品", str(int(model.get("relics", 0))), ""], ["最高单次", fmt_n(float(model.best.v)), str(model.best.src)]]
	if _ph:
		items.remove_at(4)
	var gap := 8.0 if not _ph else 6.0
	var kw: float = (vs.x - M * 2.0 - gap * (items.size() - 1)) / items.size()
	for i in items.size():
		var ka: float = 1.0 if rm else UM.steps((t - UM.stagger(i, 0.06)) / UM.T2, 3)
		if ka <= 0.0:
			continue
		var r := _panel(Rect2(M + i * (kw + gap), top, kw, kh), 2, 0.95 * ka)
		_t(Vector2(r.position.x + 12, r.position.y + (16 if not _ph else 13)), items[i][0], 13 if not _ph else 12, _fa(TUI.TXT2, ka))
		if items[i][2] != "" and items[i][1] != "" and not _ph:
			_t(Vector2(r.end.x - 10, r.position.y + 16), items[i][2], 11, _fa(TUI.CY_DIM, ka), 2, kw * 0.55)
		if items[i][1] == "":
			_t(Vector2(r.position.x + 12, r.position.y + kh * 0.64), items[i][2], 22 if not _ph else 17, _fa(TUI.TXT, ka), 0, kw - 20.0)
		else:
			_p(Vector2(r.position.x + 12, r.position.y + kh * 0.64), items[i][1], 3.0 if not _ph else 2.0, _fa(TUI.TXT, ka))
	# ---- 全队伤害分段条（招牌：分段拼合）
	var by := top + kh + (14.0 if not _ph else 10.0)
	var total: float = float(model.get("total", 0.0))
	_t(Vector2(M, by + 8), "全队伤害", 14 if not _ph else 13, TUI.TXT2)
	var nw := _p(Vector2(M + (70 if not _ph else 64), by + 8), fmt_n(total * _count_k(t, -1)), 2.0, TUI.TXT)
	_t(Vector2(M + (70 if not _ph else 64) + nw + 12, by + 8), "平均 %s / 秒" % fmt_n(float(model.get("dps", 0.0))), 13 if not _ph else 12, TUI.TXT2)
	if not _ph:
		_p(Vector2(vs.x - M, by + 8), "SQUAD DAMAGE SHARE", 1.0, TUI.CY_DIM, 2, 2)
	var bar := Rect2(M, by + (22 if not _ph else 18), vs.x - M * 2.0, 20.0 if not _ph else 14.0)
	_squad_bar(bar, rws, t)
	# ---- 干员卡
	var cy0 := bar.end.y + (14.0 if not _ph else 10.0)
	var ch := 260.0 if not _ph else maxf(120.0, vs.y - cy0 - 64.0)
	if not _ph and vs.y > 760.0:
		ch += minf(80.0, (vs.y - 720.0) * 0.5)
	var n := rws.size()
	var cg := 10.0 if not _ph else 8.0
	var ws: Array = []
	var wsum := 0.0
	for r in rws:
		var wv := 0.82 if r.key == RunStats.OTHER else 1.0
		ws.append(wv)
		wsum += wv
	var cx := M
	var avail: float = vs.x - M * 2.0 - cg * maxf(0.0, n - 1)
	for i in n:
		var cw: float = avail * ws[i] / maxf(0.01, wsum)
		var cr := Rect2(cx, cy0, cw, ch)
		if _hovered(cr) and sel != i:
			sel = i
		_card(cr, rws[i], i, t)
		cells.append([cr, "card", i])
		cx += cw + cg
	# ---- 底部：时间线 + 探索记录（桌面）；手机只有一行 Boss 记录
	var bot := vs.y - (58.0 if not _ph else 52.0)
	if not _ph:
		var by0 := cy0 + ch + 12.0
		var split: float = (vs.x - M * 2.0) * 0.64
		_timeline(Rect2(M, by0, split, bot - by0), t)
		_summary(Rect2(M + split + 10.0, by0, vs.x - M * 2.0 - split - 10.0, bot - by0))
	else:
		_phone_log(Vector2(M, vs.y - 34.0), vs.x - M * 2.0 - 190.0)
	# ---- 按钮与提示
	var br := Rect2(vs.x - M - (168.0 if not _ph else 160.0), vs.y - (46.0 if not _ph else 52.0), 168.0 if not _ph else 160.0, 34.0 if not _ph else 44.0)
	_button(br, "返回结算", "ESC" if not Pad.using else "B", "back", _hovered(br))
	if not _ph:
		_hints(Vector2(M, vs.y - 29.0), [["← →", "选择干员"], ["ENTER" if not Pad.using else "A", "详情"], ["ESC" if not Pad.using else "B", "返回结算"]])


func _tier_short() -> String:
	var nm := str(model.get("tier_name", ""))
	var parts := nm.split("·")
	return TUI.roman_ascii(parts[1].strip_edges()) if parts.size() > 1 else ""


func _tier_sub() -> String:
	return str(model.get("tier_name", "")).split("·")[0].strip_edges()


## 计数动画系数：第 i 段落位前 0.1 秒开始，T3 线性数到终值（i = -1：全队合计，跟最后一段）
func _count_k(t: float, i: int) -> float:
	if UM.rm() or t >= 90.0:
		return 1.0
	var n: int = rows().size()
	var land := SEG0 + UM.stagger(n - 1 if i < 0 else i, SEG_S) + SEG
	return UM.linear((t - land + 0.1) / UM.T3)


## 全队伤害分段条：第 i 段从条的右端滑入落位（out_cubic），落定时 1 格亮边闪一下（T1）
func _squad_bar(r: Rect2, rws: Array, t: float) -> void:
	var total: float = float(model.get("total", 0.0))
	_bar(r, [], 1.0, true)
	if total <= 0.0:
		_t(Vector2(r.position.x + 8, r.get_center().y), "这次探索没有造成伤害", 12, TUI.TXT2)
		return
	var cl: float = _ps / _c.k
	var x := 0.0
	for i in rws.size():
		var sh: float = float(rws[i].share)
		var w := r.size.x * sh
		if i == rws.size() - 1:
			w = r.size.x - x
		var e := 1.0 if UM.rm() else UM.out_cubic((t - SEG0 - UM.stagger(i, SEG_S)) / SEG)
		if e > 0.0:
			var fx: float = r.position.x + x
			var sx := fx + (r.end.x - fx) * (1.0 - e)
			var sr := Rect2(sx, r.position.y, w * (0.4 + 0.6 * e), r.size.y)
			sr.size.x = minf(sr.size.x, r.end.x - sx)
			_bar(sr, [[1.0, rws[i].col]], 1.0, false, clampf(e * 3.0, 0.0, 1.0))
			var fl: float = (t - SEG0 - UM.stagger(i, SEG_S) - SEG) / UM.T1
			if fl >= 0.0 and fl < 1.0 and not UM.rm():
				_ci().draw_rect(Rect2(TUI.snap(_c, sr.position), Vector2(sr.size.x - cl, sr.size.y)), _fa(TUI.SEL, 0.7 * (1.0 - fl)), false, cl)
			if e >= 1.0 and w > (44.0 if not _ph else 36.0):
				_p(Vector2(fx + 6, r.get_center().y), "%d%%" % int(rws[i].pct), 1.0, TUI.SEL_INK)
		x += w


func _card(r: Rect2, row: Dictionary, i: int, t: float) -> void:
	var on := i == sel
	var rr := _tile(r, 3, on)
	var ink: Color = TUI.SEL_INK if on else TUI.TXT
	var sub: Color = TUI.SEL_SUB if on else TUI.TXT2
	var acc: Color = TUI.SEL_IDX if on else TUI.CY
	var oc: Color = row.col
	var x0 := rr.position.x
	var y0 := rr.position.y
	var w := rr.size.x
	var ci := _ci()
	var cl: float = _ps / _c.k
	var s := 1.0 if not _ph else 0.82
	ci.draw_rect(Rect2(x0 + cl * 2.0, y0 + 14 * s, cl * 2.0, 32 * s), oc)
	_t(Vector2(x0 + 16, y0 + 22 * s), str(row.name), 17 if not _ph else 15, ink, 0, w - 70.0)
	var jt: String
	if row.key == RunStats.OTHER:
		jt = "全程"
	elif row.leader:
		jt = "主控 · 开局"
	elif float(row.join_t) < 1.0:
		jt = "开局"
	else:
		jt = fmt_t(float(row.join_t)) + " 加入"
	if float(row.left_t) >= 0.0:
		jt += " · %s 离队" % fmt_t(float(row.left_t))
	_t(Vector2(x0 + 16, y0 + 42 * s), jt, 12 if not _ph else 11, sub, 0, w - 24.0)
	_sprite(str(row.key), Vector2(rr.end.x - 54.0 * s, y0 + 126 * s), 2.0 if not _ph else 1.4)
	var ck := _count_k(t, i)
	_p(Vector2(x0 + 16, y0 + 88 * s), "%d%%" % int(round(float(row.pct) * ck)), 4.0 if not _ph else 3.4, ink)
	_p(Vector2(x0 + 16, y0 + 118 * s), fmt_n(float(row.dmg) * ck), 2.0, ink)
	var vmax := 1.0
	for rw in rows():
		vmax = maxf(vmax, float(rw.dmg))
	var land := SEG0 + UM.stagger(i, SEG_S) + SEG
	var fill := 1.0 if UM.rm() else UM.out_cubic((t - land) / UM.T2)
	_bar(Rect2(x0 + 16, y0 + 132 * s, w - 32, 8 * s), [[1.0, oc]], fill * float(row.dmg) / vmax)
	var lines: Array = [["每秒", fmt_n(float(row.dps))], ["击杀", fmt_n(float(row.kills))]]
	if int(row.casts) > 0:
		lines.append(["技能", "%d 次" % int(row.casts)])
	if float(row.heal) >= 1.0:
		lines.append(["治疗", fmt_n(float(row.heal))])
	var ly := y0 + 158 * s
	var lh := 19.0 if not _ph else 17.0
	var bottom := rr.end.y - (34.0 if not _ph else 8.0)
	for ln in lines:
		if ly + 8.0 > bottom:
			break
		_t(Vector2(x0 + 16, ly), ln[0], 12, sub)
		_t(Vector2(rr.end.x - 14, ly), ln[1], 13, ink, 2)
		ly += lh
	if (not _ph or rr.size.y > 230.0) and not (row.sources as Array).is_empty():
		var top0: Dictionary = row.sources[0]
		ci.draw_rect(Rect2(x0 + 16, rr.end.y - 33, w - 32, 1), TUI.SEL_SUB if on else TUI.EDGE)
		_t(Vector2(x0 + 16, rr.end.y - 18), "主要  " + str(top0.name), 12, sub, 0, w - 70.0)
		_t(Vector2(rr.end.x - 14, rr.end.y - 18), "%d%%" % int(top0.pct), 12, acc, 2)


func _timeline(r: Rect2, t: float) -> void:
	var rr := _panel(r, 2, 0.95)
	_t(Vector2(rr.position.x + 14, rr.position.y + 18), "全队每秒伤害", 14, TUI.TXT)
	_p(Vector2(rr.position.x + 120, rr.position.y + 18), "DPS / %dS" % int(model.timeline.bin_s), 1.0, TUI.CY_DIM, 0, 2)
	var gx0 := rr.position.x + 44.0
	var gy0 := rr.position.y + 40.0
	var gx1 := rr.end.x - 16.0
	var gy1 := rr.end.y - 26.0
	var ci := _ci()
	var tl: Dictionary = model.timeline
	var series: Array = tl.series
	var peak: float = maxf(1.0, float(tl.peak))
	var step := _nice(peak / 2.0)
	var topv := step * ceilf(peak / step)
	var k := 0.0
	while k <= topv + 0.5:
		var yy := gy1 - (gy1 - gy0) * k / topv
		ci.draw_rect(Rect2(gx0, roundf(yy), gx1 - gx0, 1), Color(0.094, 0.204, 0.314, 0.9))
		_p(Vector2(gx0 - 6, yy), _short(k), 1.0, TUI.TXT2, 2)
		k += step
	var t_end: float = float(model.get("t", 1.0))
	var mstep := 2 if t_end > 360.0 else 1
	var mi := 0
	while mi * 60.0 <= t_end:
		var xx := gx0 + (gx1 - gx0) * mi * 60.0 / t_end
		_p(Vector2(xx, gy1 + 12), "%d:00" % mi, 1.0, TUI.TXT2, 1)
		mi += mstep
	var nb: int = series.size()
	var cl: float = _ps / _c.k
	var bw: float = maxf(cl, floorf((gx1 - gx0) / maxi(1, nb) / cl) * cl)
	var reveal := 1.0 if UM.rm() else UM.linear((t - TL0) / TL)
	var rws: Array = rows()
	for bi in int(ceil(nb * reveal)):
		var y := gy1
		var xx: float = TUI.snap(_c, Vector2(gx0 + (gx1 - gx0) * bi / maxi(1, nb), 0)).x
		var col: Array = series[bi]
		for ri in col.size():
			var hgt: float = roundf((gy1 - gy0) * float(col[ri]) / topv / cl) * cl
			if hgt <= 0.0:
				continue
			ci.draw_rect(Rect2(xx, y - hgt, maxf(cl, bw - cl), hgt), rws[ri].col if ri < rws.size() else TUI.CY_DIM)
			y -= hgt
	for b in model.get("bosses", []):
		var x0b := gx0 + (gx1 - gx0) * clampf(float(b.t0) / t_end, 0.0, 1.0)
		_dash_v(x0b, gy0, gy1, Color(0.6, 0.24, 0.4, 0.9))
		if float(b.t1) >= 0.0:
			var x1b := gx0 + (gx1 - gx0) * clampf(float(b.t1) / t_end, 0.0, 1.0)
			_dash_v(x1b, gy0, gy1, UI.RED)
			TUI.pdiamond(ci, _c, Vector2(x1b, gy0 - 4), 3, _ps, UI.RED)
			_t(Vector2(x1b - 8, gy0 - 4), str(b.name), 11, Color(0.94, 0.67, 0.78), 2)


func _dash_v(x: float, y0: float, y1: float, col: Color) -> void:
	var y := y0
	var cl: float = _ps / _c.k
	while y < y1:
		_ci().draw_rect(Rect2(roundf(x), y, cl * 0.5, minf(3.0, y1 - y)), col)
		y += 6.0


static func _nice(v: float) -> float:
	var p := pow(10.0, floorf(log(maxf(v, 1.0)) / log(10.0)))
	for m in [1.0, 2.0, 2.5, 5.0, 10.0]:
		if v <= m * p:
			return m * p
	return 10.0 * p


static func _short(v: float) -> String:
	if v >= 1000000.0:
		return "%sM" % str(snappedf(v / 1000000.0, 0.1)).trim_suffix(".0")
	if v >= 1000.0:
		return "%sK" % str(snappedf(v / 1000.0, 0.1)).trim_suffix(".0")
	return str(int(v))


func _summary(r: Rect2) -> void:
	var rr := _panel(r, 2, 0.95)
	_t(Vector2(rr.position.x + 14, rr.position.y + 18), "探索记录", 14, TUI.TXT)
	_p(Vector2(rr.position.x + 86, rr.position.y + 18), "LOG", 1.0, TUI.CY_DIM, 0, 2)
	var y := rr.position.y + 46.0
	var bosses: Array = model.get("bosses", [])
	if bosses.is_empty():
		_t(Vector2(rr.position.x + 14, y), "没有遇到 Boss", 13, TUI.TXT2)
		y += 22.0
	for b in bosses.slice(0, 4):
		var done: bool = float(b.t1) >= 0.0
		TUI.pdiamond(_ci(), _c, Vector2(rr.position.x + 18, y), 3, _ps, UI.RED if done else TUI.CY_DIM)
		_t(Vector2(rr.position.x + 30, y), str(b.name), 13, TUI.TXT if done else TUI.TXT2, 0, rr.size.x - 170.0)
		var rt := ("%s  +%s" % [fmt_t(float(b.t1)), fmt_t(float(b.t1) - float(b.t0))]) if done else ("撤离" if b.retreat else "未击破")
		if done:
			_p(Vector2(rr.end.x - 16, y), rt, 1.0, TUI.TXT2, 2)
		else:
			_t(Vector2(rr.end.x - 16, y), rt, 12, TUI.TXT2, 2)
		y += 22.0
	y += 4.0
	var rows2: Array = []
	var bc: Array = model.get("beacons", [0, 0])
	if int(bc[1]) > 0:
		rows2.append(["引航灯标", "点燃 %d / %d" % [int(bc[0]), int(bc[1])]])
	var fu: Dictionary = model.get("fuse", {})
	if bool(fu.get("on", false)):
		rows2.append(["源石锭熔铸", "全队伤害 +%s%%" % str(snappedf(float(fu.pct) * 100.0, 0.1)).trim_suffix(".0")])
	var ls: Array = model.get("lamp_s", [0, 0, 0, 0])
	var lt := 0.0
	for v in ls:
		lt += float(v)
	if lt > 0.0:
		rows2.append(["灯火通明", "%d%% 的时间" % int(round(float(ls[0]) / lt * 100.0))])
	rows2.append(["精英击杀", str(int(model.get("elites", 0)))])
	for ln in rows2:
		if y > rr.end.y - 10.0:
			break
		_t(Vector2(rr.position.x + 14, y), ln[0], 13, TUI.TXT2)
		_t(Vector2(rr.end.x - 16, y), ln[1], 13, TUI.TXT, 2)
		y += 21.0


## 手机：底部一行探索记录（Boss 击破时刻）
func _phone_log(pos: Vector2, w: float) -> void:
	var parts: Array = []
	for b in model.get("bosses", []):
		if float(b.t1) >= 0.0:
			parts.append("%s %s" % [str(b.name), fmt_t(float(b.t1))])
	var bc: Array = model.get("beacons", [0, 0])
	if int(bc[1]) > 0:
		parts.append("灯标 %d / %d" % [int(bc[0]), int(bc[1])])
	if not parts.is_empty():
		_t(pos, " · ".join(parts), 12, TUI.TXT2, 0, w)


# ------------------------------------------------------------------ 详情
func _draw_detail(vs: Vector2) -> void:
	var rws: Array = rows()
	if rws.is_empty():
		page = 0
		return
	sel = clampi(sel, 0, rws.size() - 1)
	var row: Dictionary = rws[sel]
	var t := _mt(t_page)
	var M := 32.0 if not _ph else 20.0
	var top := _header(vs, "作战记录 · " + str(row.name), "RUN RECORD // " + str(row.en), "")
	# 换干员：‹ 01 / 05 ›（可点）
	var nx := vs.x - M
	var ny := (34.0 if not _ph else 22.0) + 4.0
	var lab := "%02d / %02d" % [sel + 1, rws.size()]
	var lw := _p(Vector2(nx - 22, ny), lab, 1.0, TUI.TXT2, 2)
	var pr := Rect2(nx - 22 - lw - 30, ny - 14, 26, 28)
	var nr := Rect2(nx - 18, ny - 14, 22, 28)
	_p(Vector2(pr.get_center().x, ny), "<", 1.0, TUI.CY if sel > 0 else TUI.CY_DIM, 1)
	_p(Vector2(nr.get_center().x, ny), ">", 1.0, TUI.CY if sel < rws.size() - 1 else TUI.CY_DIM, 1)
	cells.append([pr.grow(8.0), "prev", null])
	cells.append([nr.grow(8.0), "next", null])
	var bot := vs.y - (58.0 if not _ph else 60.0)
	# 左：身份卡（从总览带过来的焦点，S4 反白）
	var lw2 := 300.0 if not _ph else 236.0
	var lr := _tile(Rect2(M, top, lw2, bot - top), 3, true)
	_identity(lr, row)
	# 中 / 右
	var leader: bool = bool(row.leader)
	var mx0 := M + lw2 + 12.0
	if _ph:
		var mr := Rect2(mx0, top, vs.x - M - mx0, bot - top)
		if leader:
			var tabs := ["伤害来源", "生存"]
			for i in 2:
				var trr := Rect2(mr.position.x + i * 128.0, mr.position.y, 120, 34)
				var on := sub_tab == i
				var rr := _tile(trr, 2, on)
				_t(Vector2(rr.get_center().x, rr.get_center().y), tabs[i], 14, TUI.SEL_INK if on else TUI.TXT2, 1)
				cells.append([trr.grow_individual(0, 6, 0, 6), "tab", i])
			mr = Rect2(mr.position.x, mr.position.y + 42, mr.size.x, mr.size.y - 42)
		if leader and sub_tab == 1:
			_survival(mr, t)
		else:
			_sources(mr, row, t)
	else:
		var mx1: float = (vs.x - M) if not leader else (vs.x - M) * 0.672
		_sources(Rect2(mx0, top, mx1 - mx0, bot - top), row, t)
		if leader:
			_survival(Rect2(mx1 + 12.0, top, vs.x - M - mx1 - 12.0, bot - top), t)
	var br := Rect2(vs.x - M - (168.0 if not _ph else 160.0), vs.y - (46.0 if not _ph else 52.0), 168.0 if not _ph else 160.0, 34.0 if not _ph else 44.0)
	_button(br, "返回总览", "ESC" if not Pad.using else "B", "back", _hovered(br))
	if not _ph:
		var hp: Array = [["← →", "换干员"], ["↑ ↓", "滚动来源"], ["ESC" if not Pad.using else "B", "返回总览"]]
		if Pad.using:
			hp[0] = ["LB RB", "换干员"]
		_hints(Vector2(M, vs.y - 29.0), hp)


func _identity(lr: Rect2, row: Dictionary) -> void:
	var ci := _ci()
	var cl: float = _ps / _c.k
	var x0 := lr.position.x
	var x1 := lr.end.x
	var y := lr.position.y
	var big := lr.size.y > 420.0
	if row.key != RunStats.OTHER:
		_sprite(str(row.key), Vector2(lr.get_center().x, y + (168.0 if big else 112.0)), 3.0 if big else 2.0)
		y += 184.0 if big else 124.0
	else:
		y += 24.0
	ci.draw_rect(Rect2(x0 + 14, y, lr.size.x - 28, cl * 2.0), row.col)
	y += 26.0
	_t(Vector2(x0 + 20, y), str(row.name), 24 if not _ph else 20, TUI.SEL_INK)
	var jt: String
	if row.key == RunStats.OTHER:
		jt = "全程"
	elif row.leader:
		jt = "主控 · 开局"
	else:
		jt = (fmt_t(float(row.join_t)) + " 加入编队") if float(row.join_t) >= 1.0 else "开局"
	_t(Vector2(x1 - 18, y), jt, 13, TUI.SEL_SUB, 2)
	y += 24.0
	_p(Vector2(x0 + 22, y), str(row.en), 1.0, TUI.SEL_SUB, 0, 2)
	y += 32.0
	var lines: Array = [["造成伤害", fmt_n(float(row.dmg))], ["全队占比", "%d%%" % int(row.pct)], ["在队每秒", fmt_n(float(row.dps))],
		["在队时长", fmt_t(float(row.in_s))], ["击杀", fmt_n(float(row.kills))]]
	if int(row.casts) > 0:
		lines.append(["技能发动", "%d" % int(row.casts)])
	if float(row.heal) >= 1.0:
		lines.append(["治疗主控", fmt_n(float(row.heal))])
	if float(row.left_t) >= 0.0:
		lines.append(["离队", fmt_t(float(row.left_t))])
	var lh := 30.0 if not _ph else 24.0
	for ln in lines:
		if y > lr.end.y - 14.0:
			break
		_t(Vector2(x0 + 20, y), ln[0], 14 if not _ph else 13, TUI.SEL_SUB)
		_p(Vector2(x1 - 18, y), ln[1], 2.0, TUI.SEL_INK, 2)
		y += lh


func _sources(r: Rect2, row: Dictionary, t: float) -> void:
	var rr := _panel(r, 2, 0.95)
	_t(Vector2(rr.position.x + 16, rr.position.y + 22), "伤害来源", 16, TUI.TXT)
	if not _ph:
		_p(Vector2(rr.position.x + 96, rr.position.y + 22), "DAMAGE BY SOURCE", 1.0, TUI.CY_DIM, 0, 2)
	var srcs: Array = row.sources
	if srcs.is_empty():
		_t(Vector2(rr.position.x + 16, rr.position.y + 62), "没有造成伤害", 14, TUI.TXT2)
		return
	var rh := 50.0 if not _ph else 38.0
	var y0 := rr.position.y + (62.0 if not _ph else 52.0)
	var vis := maxi(1, int((rr.end.y - 14.0 - y0 + rh * 0.4) / rh))
	scroll = clampi(scroll, 0, maxi(0, srcs.size() - vis))
	var vmax: float = maxf(1.0, float(srcs[0].v))
	var x0 := rr.position.x + 16
	var x1 := rr.end.x - 18
	for k in mini(vis, srcs.size() - scroll):
		var s: Dictionary = srcs[scroll + k]
		var y := y0 + k * rh
		var kind := str(s.kind)
		var kc: Color = KIND_COL.get(kind, TUI.CY_DIM)
		var kw: float = g.font.get_string_size(kind, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 8.0
		_ci().draw_rect(Rect2(x0, y - 9, kw, 18), kc)
		_t(Vector2(x0 + 4, y), kind, 11, TUI.SEL_INK)
		_t(Vector2(x0 + kw + 10, y), str(s.name), 15 if not _ph else 14, TUI.TXT, 0, x1 - x0 - kw - 160.0)
		_p(Vector2(x1, y), "%d%%" % int(s.pct), 2.0, TUI.CY, 2)
		_p(Vector2(x1 - (62.0 if not _ph else 46.0), y), fmt_n(float(s.v)), 1.0, TUI.TXT2, 2)
		var e := 1.0 if UM.rm() else UM.out_cubic((t - UM.stagger(k, 0.06)) / UM.T2)
		_bar(Rect2(x0, y + 13, x1 - x0, 8 if not _ph else 6), [[1.0, row.col]], e * float(s.v) / vmax)
	if srcs.size() > vis:
		_p(Vector2(x1, rr.end.y - 10), "%d-%d / %d" % [scroll + 1, mini(scroll + vis, srcs.size()), srcs.size()], 1.0, TUI.CY_DIM, 2)
	# 来源不多、下面还空着（桌面）：画这名干员自己的每秒伤害时间线
	var used_y := y0 + mini(vis, srcs.size()) * rh
	if not _ph and rr.end.y - used_y > 150.0:
		var h := minf(190.0, rr.end.y - used_y - 16.0)
		_op_timeline(Rect2(x0, rr.end.y - h - 8.0, x1 - x0, h), sel, row.col, t)


## 详情：单名干员的每秒伤害（同总览时间线的分箱），Boss 击破处一道洋红虚线
func _op_timeline(r: Rect2, idx: int, col: Color, t: float) -> void:
	var ci := _ci()
	_t(Vector2(r.position.x, r.position.y + 8), "每秒伤害", 13, TUI.TXT2)
	_p(Vector2(r.position.x + 64, r.position.y + 8), "DPS / %dS" % int(model.timeline.bin_s), 1.0, TUI.CY_DIM, 0, 2)
	var series: Array = model.timeline.series
	var peak := 1.0
	for c in series:
		if idx < (c as Array).size():
			peak = maxf(peak, float(c[idx]))
	var gx0 := r.position.x + 36.0
	var gx1 := r.end.x
	var gy0 := r.position.y + 26.0
	var gy1 := r.end.y - 18.0
	var topv := _nice(peak)
	for k in 2:
		var yy := gy1 - (gy1 - gy0) * k
		ci.draw_rect(Rect2(gx0, roundf(yy), gx1 - gx0, 1), Color(0.094, 0.204, 0.314, 0.9))
		_p(Vector2(gx0 - 6, yy), _short(topv * k), 1.0, TUI.TXT2, 2)
	var t_end: float = float(model.get("t", 1.0))
	var nb: int = series.size()
	var cl: float = _ps / _c.k
	var bw: float = maxf(cl, floorf((gx1 - gx0) / maxi(1, nb) / cl) * cl)
	var reveal := 1.0 if UM.rm() else UM.linear((t - 0.1) / UM.T3)
	for bi in int(ceil(nb * reveal)):
		var v: float = float(series[bi][idx]) if idx < (series[bi] as Array).size() else 0.0
		var hgt: float = roundf((gy1 - gy0) * v / topv / cl) * cl
		if hgt > 0.0:
			var xx: float = TUI.snap(_c, Vector2(gx0 + (gx1 - gx0) * bi / maxi(1, nb), 0)).x
			ci.draw_rect(Rect2(xx, gy1 - hgt, maxf(cl, bw - cl), hgt), col)
	for b in model.get("bosses", []):
		if float(b.t1) >= 0.0:
			_dash_v(gx0 + (gx1 - gx0) * clampf(float(b.t1) / t_end, 0.0, 1.0), gy0, gy1, UI.RED)
	var mstep := 2 if t_end > 360.0 else 1
	var mi := 0
	while mi * 60.0 <= t_end:
		_p(Vector2(gx0 + (gx1 - gx0) * mi * 60.0 / t_end, gy1 + 10), "%d:00" % mi, 1.0, TUI.TXT2, 1)
		mi += mstep


func _survival(r: Rect2, t: float) -> void:
	var rr := _panel(r, 2, 0.95)
	var ld: Dictionary = model.get("leader", {})
	var x0 := rr.position.x + 16
	var x1 := rr.end.x - 16
	var y := rr.position.y + 22.0
	_t(Vector2(x0, y), "生存", 16, TUI.TXT)
	if not _ph:
		_p(Vector2(x0 + 40, y), "SURVIVAL", 1.0, TUI.CY_DIM, 0, 2)
	y += 30.0
	var e := 1.0 if UM.rm() else UM.out_cubic(t / UM.T3)
	var lw := 104.0
	# 承伤
	_t(Vector2(x0, y), "受到伤害", 13, TUI.TXT2)
	_p(Vector2(x1, y), "%s / %d HITS" % [fmt_n(float(ld.get("taken", 0.0))), int(ld.get("hits", 0))], 1.0, TUI.TXT, 2)
	y += 20.0
	var tk: Array = ld.get("taken_src", [])
	var tmax: float = float(tk[0].v) if not tk.is_empty() else 1.0
	var nrows := 4 if rr.size.y > 400.0 else 3
	for s in tk.slice(0, nrows):
		_t(Vector2(x0, y + 4), str(s.name), 12, TUI.TXT2, 0, lw - 6.0)
		_bar(Rect2(x0 + lw, y, x1 - x0 - lw - 64, 8), [[1.0, UI.RED]], e * float(s.v) / tmax)
		_p(Vector2(x1, y + 4), fmt_n(float(s.v)), 1.0, TUI.TXT2, 2)
		y += 18.0
	y += 12.0
	# 回复
	_t(Vector2(x0, y), "生命回复", 13, TUI.TXT2)
	_p(Vector2(x1, y), fmt_n(float(ld.get("heal", 0.0))), 1.0, TUI.TXT, 2)
	y += 20.0
	var hl: Array = ld.get("heal_src", [])
	if hl.is_empty():
		_t(Vector2(x0, y + 4), "没有回复记录", 12, TUI.TXT2)
		y += 18.0
	var hmax: float = float(hl[0].v) if not hl.is_empty() else 1.0
	for s in hl.slice(0, nrows + 2 if rr.size.y > 400.0 else nrows):
		_t(Vector2(x0, y + 4), str(s.name), 12, TUI.TXT2, 0, lw - 6.0)
		_bar(Rect2(x0 + lw, y, x1 - x0 - lw - 64, 8), [[1.0, UI.GREEN]], e * float(s.v) / hmax)
		_p(Vector2(x1, y + 4), fmt_n(float(s.v)), 1.0, TUI.TXT2, 2)
		y += 18.0
	y += 14.0
	# 灯火四档
	var ls: Array = model.get("lamp_s", [0, 0, 0, 0])
	var lt := 0.0
	for v in ls:
		lt += float(v)
	_t(Vector2(x0, y), "灯火", 13, TUI.TXT2)
	y += 18.0
	var segs: Array = []
	for i in 4:
		segs.append([float(ls[i]) / maxf(1.0, lt), LAMP_COL[i]])
	_bar(Rect2(x0, y, x1 - x0, 12), segs, e)
	y += 26.0
	var cw: float = (x1 - x0) / 4.0
	for i in 4:
		var xx := x0 + i * cw
		_ci().draw_rect(Rect2(xx, y - 4, 8, 8), LAMP_COL[i])
		_t(Vector2(xx + 12, y), RunStats.LAMP_NAMES[i], 12, TUI.TXT2)
		_p(Vector2(xx + 12, y + 16), fmt_t(float(ls[i])), 1.0, TUI.TXT)
	y += 40.0
	for ln in [["闪避", str(int(ld.get("dodges", 0)))], ["冲刺", str(int(ld.get("dashes", 0)))], ["护盾抵挡", str(int(ld.get("blocks", 0)))],
			["生命低于 35%", fmt_t(float(ld.get("low_hp_s", 0.0)))]]:
		if y > rr.end.y - 10.0:
			break
		_t(Vector2(x0, y), ln[0], 13, TUI.TXT2)
		_p(Vector2(x1, y), ln[1], 1.0, TUI.TXT, 2)
		y += 19.0
