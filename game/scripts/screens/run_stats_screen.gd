extends RefCounted
## 界面 · 作战记录（局终统计，docs/77，2026-10-12）：胜利 / 结局结算与失败结算上的「作战记录」按钮（Tab / C）打开，
## 不替换结局演出与结算面板；Esc / Ⓑ / 「返回结算」回到结算。
## 10-12 用户「UI 简洁一点，数据统计展示也简洁一点」后的 v2：
## - 总览：结果标签 + 一行要点（时间 · 难度 · 击杀 · 等级）+ 全队伤害分段条 + 干员卡（待机帧、名字、入队、占比大字、伤害 · 每秒）
##   + 一行 Boss 击破时刻。
## - 详情（在卡上 Enter / 点卡）：身份卡（伤害 / 占比 / 每秒 / 击杀 / 技能 / 治疗）+ 前 5 个伤害来源（其余并成「其他」）；
##   主控另有一小块「生存」：受到伤害、生命回复（前 3 个来源）、灯火通明占比、源石锭熔铸。
## 风格：局外 T5s（docs/37 §8：阶梯切角、藏青抖动、S4 近白选中、像素字数字）。
## 动效（docs/62 §3.24）：主动作「分段拼合」——全队伤害条按干员一段段从右端滑入落位（out_cubic，错开 70 ms），
##   每段落位后对应卡片的占比数字计数到终值（次要）。减少动态：直接终态，只留 T1 淡入。
## 数据只读 run/run_stats.gd 的 model（不碰 g.rng、不改对局状态）。

const UI = preload("res://scripts/ui.gd")
const UM = preload("res://scripts/ui_motion.gd")
const TUI = preload("res://scripts/screens/tide_ui.gd")
const RunStats = preload("res://scripts/run/run_stats.gd")
const Game = preload("res://scripts/game.gd")

const SEG0 := 0.08      # 第一段开始滑入
const SEG_S := 0.07     # 段间错开
const SEG := UM.T2      # 每段滑入时长
const TOP_SRC := 5      # 详情里列出的伤害来源条数（其余并成「其他」）

var g: Game
var open := false
var model: Dictionary = {}
var page := 0           # 0 总览 / 1 详情
var sel := 0            # 选中的行（干员卡）
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


func _seg_end() -> float:
	return SEG0 + UM.stagger(maxi(0, rows().size() - 1), SEG_S) + SEG + UM.T2


func motion_running() -> bool:
	if not open or skipped or UM.rm() or UM.skip_all():
		return false
	return _mt(t_open) < _seg_end() if page == 0 else _mt(t_page) < 0.4


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


func _move(dx: int, n: int) -> void:
	var ns := clampi(sel + dx, 0, maxi(0, n - 1))   # 不循环（docs/67 §12 导航规则）
	if ns != sel:
		sel = ns
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


func wheel(_dy: int) -> void:
	pass   # v2 详情最多 6 行，不用滚动


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


## 待机帧：k = 每个美术像素占几个逻辑像素（高清帧条 @2x 帧高 > 64，一格美术像素 = 2 个贴图像素）
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


# ------------------------------------------------------------------ 总览
func _draw_overview(vs: Vector2) -> void:
	var t := _mt(t_open)
	var M := 40.0 if not _ph else 24.0
	var y := _header(vs, "作战记录", "RUN RECORD")
	var rws: Array = rows()
	# 一行要点：时间 · 难度 · 击杀 · 等级
	var facts: Array = [["演练用时" if bool(model.get("trial", false)) else "探索时间", fmt_t(float(model.get("t", 0.0)))],
		["难度", str(model.get("tier_name", ""))], ["击杀", fmt_n(float(model.get("kills", 0)))],
		["等级", "Lv.%d %s" % [int(model.get("level", 1)), ["精零", "精英一", "精英二"][clampi(int(model.get("elite", 0)), 0, 2)]]]]
	var x := M
	var fs := 15 if not _ph else 13
	for i in facts.size():
		if i > 0:
			x += _t(Vector2(x, y), "·", fs, TUI.CY_DIM) + 12.0
		x += _t(Vector2(x, y), facts[i][0], fs, TUI.TXT2) + 8.0
		x += _t(Vector2(x, y), facts[i][1], fs, TUI.TXT) + 12.0
	# 全队伤害 + 分段条（招牌：分段拼合）
	y += 40.0 if not _ph else 28.0
	var total: float = float(model.get("total", 0.0))
	var lw := _t(Vector2(M, y), "全队伤害", 14 if not _ph else 13, TUI.TXT2) + 10.0
	var nw := _p(Vector2(M + lw, y), fmt_n(total), 2.0, TUI.TXT)
	_t(Vector2(M + lw + nw + 14, y), "每秒 %s" % fmt_n(float(model.get("dps", 0.0))), 14 if not _ph else 13, TUI.TXT2)
	var bar := Rect2(M, y + (16 if not _ph else 12), vs.x - M * 2.0, 24.0 if not _ph else 16.0)
	_squad_bar(bar, rws, t)
	# 干员卡
	var cy0 := bar.end.y + (28.0 if not _ph else 16.0)
	var foot_h := 92.0 if not _ph else 66.0
	var ch := minf(vs.y - cy0 - foot_h, 280.0 if not _ph else 250.0)
	var n := rws.size()
	var cg := 14.0 if not _ph else 8.0
	var cw: float = minf(250.0 if not _ph else 220.0, (vs.x - M * 2.0 - cg * maxf(0.0, n - 1)) / maxi(1, n))
	var cx := M + ((vs.x - M * 2.0) - (cw * n + cg * maxf(0.0, n - 1))) * 0.5
	for i in n:
		var cr := Rect2(cx, cy0, cw, ch)
		if _hovered(cr) and sel != i:
			sel = i
		_card(cr, rws[i], i, t)
		cells.append([cr, "card", i])
		cx += cw + cg
	# Boss 击破时刻（一行）
	var parts: Array = []
	for b in model.get("bosses", []):
		if float(b.t1) >= 0.0:
			parts.append("%s %s" % [str(b.name), fmt_t(float(b.t1))])
	var by := cy0 + ch + (28.0 if not _ph else 18.0)
	if not parts.is_empty():
		var bx := M + _t(Vector2(M, by), "Boss 击破", 13 if not _ph else 12, TUI.TXT2) + 12.0
		_t(Vector2(bx, by), "   ".join(parts), 13 if not _ph else 12, TUI.TXT, 0, vs.x - bx - M - (0.0 if not _ph else 180.0))
	# 返回与提示
	var br := Rect2(vs.x - M - (160.0 if not _ph else 150.0), vs.y - (52.0 if not _ph else 56.0), 160.0 if not _ph else 150.0, 34.0 if not _ph else 44.0)
	_button(br, "返回结算", "ESC" if not Pad.using else "B", "back", _hovered(br))
	if not _ph:
		_hints(Vector2(M, br.get_center().y), [["← →", "选择干员"], ["ENTER" if not Pad.using else "A", "详情"]])


## 计数动画系数：第 i 段落位前 0.1 秒开始，T3 线性数到终值
func _count_k(t: float, i: int) -> float:
	if UM.rm() or t >= 90.0:
		return 1.0
	return UM.linear((t - (SEG0 + UM.stagger(i, SEG_S) + SEG) + 0.1) / UM.T3)


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
		var w: float = r.size.x * float(rws[i].share)
		if i == rws.size() - 1:
			w = r.size.x - x
		var e := 1.0 if UM.rm() else UM.out_cubic((t - SEG0 - UM.stagger(i, SEG_S)) / SEG)
		if e > 0.0:
			var fx: float = r.position.x + x
			var sx := fx + (r.end.x - fx) * (1.0 - e)
			var sr := Rect2(sx, r.position.y, minf(w * (0.4 + 0.6 * e), r.end.x - sx), r.size.y)
			_bar(sr, [[1.0, rws[i].col]], 1.0, false, clampf(e * 3.0, 0.0, 1.0))
			var fl: float = (t - SEG0 - UM.stagger(i, SEG_S) - SEG) / UM.T1
			if fl >= 0.0 and fl < 1.0 and not UM.rm():
				_ci().draw_rect(Rect2(TUI.snap(_c, sr.position), Vector2(sr.size.x - cl, sr.size.y)), _fa(TUI.SEL, 0.7 * (1.0 - fl)), false, cl)
		x += w


func _card(r: Rect2, row: Dictionary, i: int, t: float) -> void:
	var on := i == sel
	var rr := _tile(r, 3, on)
	var ink: Color = TUI.SEL_INK if on else TUI.TXT
	var sub: Color = TUI.SEL_SUB if on else TUI.TXT2
	var x0 := rr.position.x + (18.0 if not _ph else 12.0)
	var y0 := rr.position.y
	var h := rr.size.y
	var cl: float = _ps / _c.k
	# 职业色：卡片顶边一道
	_ci().draw_rect(Rect2(rr.position.x + cl * 4.0, y0 + cl * 2.0, rr.size.x - cl * 8.0, cl * 2.0), row.col)
	var foot := y0 + h * 0.42
	_sprite(str(row.key), Vector2(rr.get_center().x, foot), 2.0 if not _ph else 1.4)
	var y := foot + (18.0 if not _ph else 12.0)
	_t(Vector2(x0, y), str(row.name), 17 if not _ph else 14, ink, 0, rr.size.x - 28.0)
	y += 20.0 if not _ph else 16.0
	_t(Vector2(x0, y), _join_text(row), 12 if not _ph else 11, sub, 0, rr.size.x - 28.0)
	y += 36.0 if not _ph else 24.0
	var ck := _count_k(t, i)
	_p(Vector2(x0, y), "%d%%" % int(round(float(row.pct) * ck)), 5.0 if not _ph else 4.0, ink)
	y += 34.0 if not _ph else 22.0
	var dw := _p(Vector2(x0, y), fmt_n(float(row.dmg)), 2.0, ink)
	_t(Vector2(x0 + dw + 10, y), "每秒 %s" % fmt_n(float(row.dps)), 12 if not _ph else 11, sub, 0, rr.end.x - x0 - dw - 18.0)


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
	var lr := _tile(Rect2(M, top, lw2, bot - top), 3, true)
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
	var big := lr.size.y > 420.0
	var cl: float = _ps / _c.k
	_ci().draw_rect(Rect2(lr.position.x + cl * 4.0, y + cl * 2.0, lr.size.x - cl * 8.0, cl * 2.0), row.col)
	if row.key != RunStats.OTHER:
		_sprite(str(row.key), Vector2(lr.get_center().x, y + (160.0 if big else 104.0)), 3.0 if big else 2.0)
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
	var rr := _panel(r, 2, 0.9)
	var ld: Dictionary = model.get("leader", {})
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
