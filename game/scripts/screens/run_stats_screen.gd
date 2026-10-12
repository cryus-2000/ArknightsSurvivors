extends RefCounted
## 界面 · 作战记录（局终统计，docs/77，2026-10-12）：胜利 / 结局结算与失败结算上的「作战记录」按钮（Tab / C）打开，
## 不替换结局演出与结算面板；Esc / Ⓑ / 「返回结算」回到结算。
## v3（10-12 用户「是不是太精简了，学习一下类似于雨中冒险这种是怎么做统计的」）：结构参考雨中冒险 2 的结算「Run Report」，
## 一屏三栏——左：难度 / 时间、主控、击倒者（失败）或击破的最终 Boss（胜利）；中：藏品格（拾取顺序，选中看名字与效果）+ 编队条
## （待机帧、入队、全队占比）；右：统计表（标签左、数值右、细分隔线，可滚动）。编队条上 Enter / 点击进干员详情（v2 的简化详情）。
## 手机：三页（概况 / 藏品 / 数据）。风格：局外 T5s（docs/37 §8）。
## 动效（docs/62 §3.24）：主动作「藏品依次弹出」（每格 T2 out_back(1.4)，0.6 → 1 倍，间隔 ≤ 35 ms，整组 ≤ 0.6 秒）；
##   统计数值计数到终值、全队占比条分段落位（次要）。减少动态：直接终态，只留 T1 淡入。
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
var zone := 1           # 总览焦点：0 藏品格 / 1 编队条
var rel := 0            # 选中的藏品
var tab := 0            # 手机总览页：0 概况 / 1 藏品 / 2 数据
var stat_scroll := 0    # 统计表滚动
var t_open := 0.0
var t_page := 0.0
var skipped := false
var cells: Array = []   # [Rect2, 动作, 参数]：命中区（终态位置）
var _last_mouse := Vector2(-1, -1)
var _per_row := 1       # 藏品格每行几个（方向键上下用）
var _rel_row0 := 0      # 藏品格滚动：最上面画第几行（藏品不设上限后，压到 30 像素格仍放不下时才滚，10-12）
var _rel_seen := -1     # 上一帧的选中藏品：选中变了才把它滚进视野，滚轮滚动不被拉回
var _relic_rect := Rect2()   # 藏品格所在区域（滚轮落在这里滚藏品，否则滚统计表）
var _tex_miss := {}
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
	_rel_row0 = 0
	_rel_seen = -1
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


## 方向键：藏品格内按行列走，最下一行再往下进编队条；编队条往上回到藏品格（不循环，docs/67 §12）
func _nav(dx: int, dy: int) -> void:
	var nr: int = relics().size()
	var n: int = rows().size()
	var per: int = maxi(1, _per_row)
	var before := [zone, rel, sel]
	if _ph and tab != 1:
		zone = 1
	if _ph and tab == 1:
		zone = 0
	if zone == 0 and nr > 0:
		if dx != 0:
			rel = clampi(rel + dx, 0, nr - 1)
		elif dy < 0:
			rel = maxi(0, rel - per) if rel >= per else rel
		elif dy > 0:
			if rel + per < nr:
				rel += per
			elif not _ph:
				zone = 1
	else:
		if dx != 0:
			sel = clampi(sel + dx, 0, maxi(0, n - 1))
		elif dy < 0 and nr > 0 and not _ph:
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
			_rel_row0 = maxi(0, _rel_row0 + signi(dy))   # 上限在 _relic_zone 里按行数夹
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


func _draw_overview(vs: Vector2) -> void:
	var t := _mt(t_open)
	var M := 32.0 if not _ph else 20.0
	var top := _header(vs, "作战记录", "RUN REPORT") + (4.0 if not _ph else 0.0)
	var bot := vs.y - (68.0 if not _ph else 64.0)
	if _ph:
		# 手机：三页（概况 / 藏品 / 数据），页签在标题行右边
		var names := ["概况", "藏品", "数据"]
		for i in 3:
			var trr := Rect2(vs.x - M - (3 - i) * 96.0 + 8.0, 22.0, 88.0, 36.0)
			var rr := _tile(trr, 2, tab == i)
			_t(rr.get_center(), names[i], 15, TUI.SEL_INK if tab == i else TUI.TXT2, 1)
			cells.append([trr.grow_individual(0, 8, 0, 6), "tab", i])
		match tab:
			0:
				_left(Rect2(M, top, 300.0, bot - top), t)
				_squad_zone(Rect2(M + 316.0, top, vs.x - M * 2.0 - 316.0, bot - top), t)
			1:
				_relic_zone(Rect2(M, top, vs.x - M * 2.0, bot - top), t)
			2:
				_stats(Rect2(M, top, vs.x - M * 2.0, bot - top), t)
	else:
		var lw := 300.0
		var rw := 356.0
		var gap := 24.0
		var cx0 := M + lw + gap
		var cx1 := vs.x - M - rw - gap
		_left(Rect2(M, top, lw, bot - top), t)
		var sq_h := 188.0
		_relic_zone(Rect2(cx0, top, cx1 - cx0, bot - top - sq_h - 16.0), t)
		_squad_zone(Rect2(cx0, bot - sq_h, cx1 - cx0, sq_h), t)
		_stats(Rect2(vs.x - M - rw, top, rw, bot - top), t)
	var br := Rect2(vs.x - M - (160.0 if not _ph else 150.0), vs.y - (52.0 if not _ph else 56.0), 160.0 if not _ph else 150.0, 34.0 if not _ph else 44.0)
	_button(br, "返回结算", "ESC" if not Pad.using else "B", "back", _hovered(br))
	if not _ph:
		_hints(Vector2(M, br.get_center().y), [["↑ ↓ ← →", "藏品 / 编队"], ["ENTER" if not Pad.using else "A", "干员详情"], ["PGUP PGDN" if not Pad.using else "LB RB", "滚动数据"]])


## 左栏：难度与时间、主控、击倒者（失败）/ 击破的最终 Boss（胜利）
func _left(r: Rect2, t: float) -> void:
	var x0 := r.position.x
	var y := r.position.y + 12.0
	_t(Vector2(x0, y), "难度", 13, TUI.TXT2)
	_t(Vector2(x0 + 44, y), str(model.get("tier_name", "")), 15, TUI.TXT, 0, r.size.x - 50.0)
	y += 34.0
	_t(Vector2(x0, y), "演练用时" if bool(model.get("trial", false)) else "探索时间", 13, TUI.TXT2)
	_p(Vector2(x0 + 72, y), fmt_t(float(model.get("t", 0.0))), 3.0, TUI.TXT)
	y += 26.0
	# 主控
	var ld: Dictionary = {}
	for rw in rows():
		if rw.leader:
			ld = rw
	var ch_h := 170.0 if not _ph else 150.0
	var cr := _panel(Rect2(x0, y, r.size.x, ch_h), 2, 0.9)
	if not ld.is_empty():
		_sprite(str(ld.key), Vector2(cr.position.x + 64.0, cr.position.y + ch_h * 0.5 + 50.0), 3.0 if not _ph else 2.0)
		var tx := cr.position.x + (132.0 if not _ph else 110.0)
		_t(Vector2(tx, cr.position.y + 48), str(ld.name), 20 if not _ph else 17, TUI.TXT, 0, cr.end.x - tx - 10.0)
		_p(Vector2(tx + 2, cr.position.y + 74), str(ld.en), 1.0, TUI.CY_DIM, 0, 2)
		_t(Vector2(tx, cr.position.y + 104), "Lv.%d · %s" % [int(model.get("level", 1)), ["精零", "精英一", "精英二"][clampi(int(model.get("elite", 0)), 0, 2)]], 14, TUI.TXT2)
		_t(Vector2(tx, cr.position.y + 128), "主控", 13, TUI.CY_DIM)
		_ci().draw_rect(Rect2(cr.position.x + 3.0 * _ps / _c.k, cr.position.y + 2.0 * _ps / _c.k, 2.0 * _ps / _c.k, ch_h - 4.0 * _ps / _c.k), ld.col)
	y += ch_h + 14.0
	# 击倒者 / 最终 Boss
	var kr := _panel(Rect2(x0, y, r.size.x, r.end.y - y), 2, 0.9)
	var won: bool = str(model.get("result", "")) == "win"
	var kd: Dictionary = model.get("final_boss", {}) if won else model.get("killer", {})
	var lab := "击破最终 Boss" if won else "击倒者"
	if won and kd.is_empty():
		lab = "演练完成"
	var lc: Color = TUI.CY if won else UI.RED
	_t(Vector2(kr.position.x + 16, kr.position.y + 22), lab, 14, lc)
	if kd.is_empty():
		return
	var box := Rect2(kr.position.x + 16, kr.position.y + 40, 88, minf(88.0, kr.size.y - 52.0))
	var fr: Array = _enemy_frame(str(kd.get("type", "")))
	if not fr.is_empty() and box.size.y > 20.0:
		var src: Rect2 = fr[1]
		var k: float = minf(box.size.x / src.size.x, box.size.y / src.size.y)
		k = floorf(k) if k >= 1.0 else k
		var sz := src.size * k
		_ci().draw_texture_rect_region(fr[0], Rect2(TUI.snap(_c, box.get_center() - sz * 0.5), sz), src)
	else:
		TUI.pdiamond(_ci(), _c, box.get_center(), 9, _ps, lc)
	var tx2 := box.end.x + 14.0
	_t(Vector2(tx2, kr.position.y + 64), str(kd.get("name", "")), 16, TUI.TXT, 0, kr.end.x - tx2 - 10.0)
	var when := float(model.get("t", 0.0))
	if won:
		for b in model.get("bosses", []):
			if str(b.name) == str(kd.get("name", "")) and float(b.t1) >= 0.0:
				when = float(b.t1)
	_t(Vector2(tx2, kr.position.y + 90), "击破于" if won else "倒下于", 12, TUI.TXT2)
	_p(Vector2(tx2 + 46, kr.position.y + 90), fmt_t(when), 1.0, TUI.TXT)


## 中栏上：藏品格（拾取顺序；等级点、遭诅 / 升华角标）+ 选中藏品的名字与效果
func _relic_zone(r: Rect2, t: float) -> void:
	var rl: Array = relics()
	var x0 := r.position.x
	var y := r.position.y + 12.0
	var tw := _t(Vector2(x0, y), "藏品", 16, TUI.TXT)
	_p(Vector2(x0 + tw + 10, y), "%d" % rl.size(), 2.0, TUI.CY)
	if rl.is_empty():
		_t(Vector2(x0, y + 40), "这次探索没有获得藏品", 14, TUI.TXT2)
		_per_row = 1
		return
	var cell := 48.0 if not _ph else 46.0
	_per_row = maxi(1, int(r.size.x / cell))
	var gy := y + 24.0
	var info_h := 82.0
	var rows_fit := maxi(1, int((r.end.y - gy - info_h - 8.0) / cell))
	var per := _per_row
	if ceili(rl.size() / float(per)) > rows_fit:
		cell = maxf(30.0, floorf(r.size.x / ceilf(rl.size() / float(rows_fit))))
		per = maxi(1, int(r.size.x / cell))
		_per_row = per
	rel = clampi(rel, 0, rl.size() - 1)
	var n := rl.size()
	# 压到 30 像素格还放不下：只画放得下的行，选中项滚进视野；标题行右侧写「第 a–b 行 / 共 c 行」
	var total_rows: int = ceili(n / float(per))
	var vis_rows: int = maxi(1, int((r.end.y - gy - info_h - 8.0) / cell))
	_relic_rect = Rect2(x0, gy, r.size.x, minf(total_rows, vis_rows) * cell)
	if total_rows > vis_rows:
		if rel != _rel_seen:
			_rel_row0 = clampi(_rel_row0, rel / per - vis_rows + 1, rel / per)
		_rel_row0 = clampi(_rel_row0, 0, total_rows - vis_rows)
		_t(Vector2(r.end.x, y), "第 %d–%d 行 / 共 %d 行" % [_rel_row0 + 1, _rel_row0 + vis_rows, total_rows], 12, TUI.TXT2, 2)
	else:
		_rel_row0 = 0
	_rel_seen = rel
	var i0: int = _rel_row0 * per
	var i1: int = mini(n, (_rel_row0 + vis_rows) * per)
	var step := minf(0.035, 0.42 / maxf(1.0, n))
	var cl: float = _ps / _c.k
	var mp := _mouse()
	for i in range(i0, i1):
		var it: Dictionary = rl[i]
		var cr := Rect2(x0 + (i % per) * cell, gy + (i / per - _rel_row0) * cell, cell - 6.0, cell - 6.0)
		cells.append([cr, "relic", i])
		if not g.kb_nav and not Pad.using and cr.has_point(mp):
			zone = 0
			rel = i
		var on := zone == 0 and rel == i
		var d := SEG0 + (i - i0) * step
		var e := 1.0 if UM.rm() else clampf((t - d) / UM.T2, 0.0, 1.0)
		if e <= 0.0:
			continue
		var a := clampf((t - d) / UM.T1, 0.0, 1.0) if not UM.rm() else 1.0
		var col: Color = UI.CAT_COL.get(str(it.cat), UI.GOLD)
		var rr := _tile(cr, 1, on, a)
		_ci().draw_rect(Rect2(rr.position + Vector2(cl * 2.0, cl * 2.0), Vector2(cl * 4.0, cl)), _fa(col, a))
		var sc := 1.0 if UM.rm() else 0.6 + 0.4 * UM.out_back(e, 1.4)
		var isz := 32.0 * sc if cell >= 44.0 else 16.0 * sc
		var ic := _relic_tex(str(it.id))
		var c := rr.get_center()
		if ic != null:
			_ci().draw_texture_rect(ic, Rect2((c - Vector2(isz, isz) * 0.5).round(), Vector2(isz, isz)), false, Color(1, 1, 1, a))
		else:
			_t(c, str(it.name).substr(0, 1), 14, _fa(col, a), 1)
		# 等级点（左下）、遭诅 / 升华角标（右上）
		if int(it.lv) > 1:
			for q in mini(int(it.lv), 5):
				_ci().draw_rect(Rect2(rr.position.x + cl * 2.0 + q * cl * 3.0, rr.end.y - cl * 3.0, cl * 2.0, cl * 1.5), _fa(col.lightened(0.3), a))
		var rar := str(it.rarity)
		if rar == "遭诅古物" or rar == "升华":
			var mc: Color = UI.RED if rar == "遭诅古物" else UI.VIOLET
			var p0 := Vector2(rr.end.x - cl * 1.0, rr.position.y + cl * 1.0)
			_ci().draw_colored_polygon(PackedVector2Array([p0, p0 + Vector2(-cl * 6.0, 0), p0 + Vector2(0, cl * 6.0)]), _fa(mc, a))
	# 选中藏品的说明
	var it2: Dictionary = rl[rel]
	var iy := gy + minf(total_rows, vis_rows) * cell + 6.0
	var ir := _panel(Rect2(x0, iy, r.size.x, minf(info_h, r.end.y - iy)), 2, 0.9)
	var nm := str(it2.name)
	var nw := _t(Vector2(ir.position.x + 14, ir.position.y + 18), nm, 15, TUI.TXT, 0, ir.size.x * 0.6)
	var tag := str(it2.rarity)
	if int(it2.max) > 1:
		tag = "Lv.%d / %d · %s" % [int(it2.lv), int(it2.max), tag]
	var rc: Color = UI.RED if str(it2.rarity) == "遭诅古物" else (UI.VIOLET if str(it2.rarity) == "升华" else TUI.CY_DIM)
	_t(Vector2(ir.position.x + 24 + nw, ir.position.y + 18), tag + " · " + str(it2.cat), 12, rc, 0, ir.size.x - nw - 40.0)
	var lines: PackedStringArray = UI.wrap_lines(g.font, str(it2.desc), 12, ir.size.x - 28.0)
	for li in mini(lines.size(), 3):
		var ln := lines[li]
		if li == 2 and lines.size() > 3:
			ln = ln.substr(0, maxi(0, ln.length() - 1)) + "…"
		_t(Vector2(ir.position.x + 14, ir.position.y + 40 + li * 17), ln, 12, TUI.TXT2)


## 中栏下：编队条（待机帧、入队、全队占比条 + 百分比），Enter / 点击进干员详情
func _squad_zone(r: Rect2, t: float) -> void:
	var rws: Array = rows()
	var x0 := r.position.x
	var y := r.position.y + 12.0
	var tw := _t(Vector2(x0, y), "编队", 16, TUI.TXT)
	var total: float = float(model.get("total", 0.0))
	_t(Vector2(x0 + tw + 14, y), "全队伤害 %s · 每秒 %s" % [fmt_n(total), fmt_n(float(model.get("dps", 0.0)))], 13, TUI.TXT2, 0, r.size.x - tw - 20.0)
	var bar := Rect2(x0, y + 16.0, r.size.x, 10.0 if not _ph else 8.0)
	_squad_bar(bar, rws, t)
	var cy0 := bar.end.y + 12.0
	var n := rws.size()
	var cg := 8.0
	var cw: float = minf(130.0, (r.size.x - cg * maxf(0.0, n - 1)) / maxi(1, n))
	var ch: float = minf(r.end.y - cy0, 210.0)
	for i in n:
		var row: Dictionary = rws[i]
		var cr := Rect2(x0 + i * (cw + cg), cy0, cw, ch)
		if _hovered(cr) and (sel != i or zone != 1):
			sel = i
			zone = 1
		cells.append([cr, "card", i])
		var on := zone == 1 and sel == i
		var rr := _tile(cr, 2, on)
		var ink: Color = TUI.SEL_INK if on else TUI.TXT
		var sub: Color = TUI.SEL_SUB if on else TUI.TXT2
		var cl: float = _ps / _c.k
		_ci().draw_rect(Rect2(rr.position.x + cl * 3.0, rr.position.y + cl * 2.0, rr.size.x - cl * 6.0, cl * 2.0), row.col)
		var foot := rr.position.y + minf(ch * 0.5, 80.0)
		_sprite(str(row.key), Vector2(rr.get_center().x, foot), 2.0 if (not _ph and cw >= 96.0) else 1.4)
		var yy := foot + 14.0
		_t(Vector2(rr.position.x + 10, yy), str(row.name), 13, ink, 0, cw - 16.0)
		yy += 17.0
		_t(Vector2(rr.position.x + 10, yy), _join_text(row), 11, sub, 0, cw - 16.0)
		yy += 24.0
		if yy < rr.end.y - 6.0:
			var ck := _count_k(t, i)
			_p(Vector2(rr.position.x + 10, yy), "%d%%" % int(round(float(row.pct) * ck)), 2.0, ink)
			_t(Vector2(rr.end.x - 8, yy), fmt_n(float(row.dmg)), 11, sub, 2, cw * 0.55)


## 右栏：统计表（标签左、数值右、细分隔线；放不下时 PgUp / PgDn / 滚轮滚动）。数值计数到终值
func _stats(r: Rect2, t: float) -> void:
	var st: Array = model.get("stats", [])
	var x0 := r.position.x
	var y := r.position.y + 12.0
	_t(Vector2(x0, y), "数据", 16, TUI.TXT)
	_p(Vector2(x0 + 44, y), "STATS", 1.0, TUI.CY_DIM, 0, 2)
	var cols := 2 if _ph else 1
	var gap := 24.0
	var cw: float = (r.size.x - gap * (cols - 1)) / cols
	var rh := 25.0 if not _ph else 26.0
	var y0 := y + 22.0
	var vis := maxi(1, int((r.end.y - y0) / rh)) * cols
	stat_scroll = clampi(stat_scroll, 0, maxi(0, st.size() - vis))
	for k in mini(vis, st.size() - stat_scroll):
		var i := stat_scroll + k
		var s: Dictionary = st[i]
		var cx := x0 + (k / (vis / cols)) * (cw + gap) if cols > 1 else x0
		var ry := y0 + (k % (vis / cols)) * rh + rh * 0.5
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


## 全队伤害分段条：第 i 段从条的右端滑入落位（out_cubic）
func _squad_bar(r: Rect2, rws: Array, t: float) -> void:
	var total: float = float(model.get("total", 0.0))
	_bar(r, [], 1.0, true)
	if total <= 0.0:
		return
	var x := 0.0
	for i in rws.size():
		var w: float = r.size.x * float(rws[i].share)
		if i == rws.size() - 1:
			w = r.size.x - x
		var e := 1.0 if UM.rm() else UM.out_cubic((t - SEG0 - UM.stagger(i, SEG_S)) / SEG)
		if e > 0.0:
			var fx: float = r.position.x + x
			var sx := fx + (r.end.x - fx) * (1.0 - e)
			_bar(Rect2(sx, r.position.y, minf(w * (0.4 + 0.6 * e), r.end.x - sx), r.size.y), [[1.0, rws[i].col]], 1.0, false, clampf(e * 3.0, 0.0, 1.0))
		x += w


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
