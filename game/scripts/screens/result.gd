extends RefCounted
## 界面 · 结算（state DEAD / WIN）：存活时间、击杀、结局、伤害与编队总结。
## 界面层约定（docs/39 §3）。2026-09-26 从 game.gd 拆出。

const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
const UM = preload("res://scripts/ui_motion.gd")
const HudView = preload("res://scripts/screens/hud.gd")

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game


func _init(game: Game) -> void:
	g = game


# ----------------------------------------------------------------- 动效（docs/62 §3.18 暂停 · 秒针停摆、§3.20 失败结算 · 打捞记录）
# 计时用 g.state_age（进入当前状态后累计的真实帧间隔：暂停照走、不受对局倍速影响）；g.ui_skip = 本状态的动效已被输入跳过。
# 只改「怎么画」：按钮命中区（g.result_btns）始终是终态位置。胜利 / 结局结算本批不动（第二批「盖章」）。
const PAUSE_DIM := 0.22       # 世界压暗 T2（不去色：去色留给最终 Boss 击破）
const DIAL_DRAW := 0.26       # 表盘描出
const HAND0 := 0.10           # 秒针开始飞转
const HAND := 0.85            # 秒针减速、越过 12 点一点再弹回停住（out_back 1.6）
const MENU0 := 0.12           # 菜单逐项「嘀嗒」跳入：错开 60 ms，每项 240 ms 三格硬步进
const ROW_S := 0.09           # 失败结算：每行错开 90 ms
const ROW := 0.30             # 每行 300 ms 由晃动到对焦
const BTN0 := 0.66            # 两个按钮在各行之后 T2 淡入


## 动效时间（秒）：暂停从进入暂停算，失败结算从倒下过渡结束算；跳过 / 无头 = 终态
func _mt() -> float:
	if g.ui_skip or UM.skip_all():
		return 99.0
	if g.state == Game.S.DEAD:
		return g.state_age - HudView.DEATH_T
	return g.state_age


## 动效是否还在可跳过的阶段（game.gd _input：这时的点击 / 确认键只跳到终态）
func motion_running() -> bool:
	if g.settlement.active():
		return false   # New result module owns its own skip and input.
	if UM.rm() or g.ui_skip or UM.skip_all():
		return false
	if g.state == Game.S.PAUSE:
		return g.state_age < HAND0 + HAND
	if g.state == Game.S.DEAD:
		return g.state_age >= HudView.DEATH_T and _mt() < BTN0 + UM.T2
	return false


## 第 k 行的 [横向偏移, 透明度, 虚影偏移]：失败结算 = 水平正弦晃动（6 px → 0）+ 半透明逐行对焦；其余状态不动
func _row(k: int) -> Array:
	if g.state != Game.S.DEAD:
		return [0.0, 1.0, 0.0]
	var t := _mt()
	if UM.rm():
		return [0.0, UM.prog(0.0, UM.T1, t), 0.0]
	var e := UM.out_cubic((t - k * ROW_S) / ROW)
	if e >= 1.0:
		return [0.0, 1.0, 0.0]
	return [roundf(6.0 * (1.0 - e) * sin(t * TAU * 2.6 + k * 1.3)), 0.2 + 0.8 * e, roundf(4.0 * (1.0 - e))]


## 第 i 个按钮的 [横向偏移, 透明度]：暂停 = 嘀嗒步进跳入；失败 = 各行之后 T2 淡入
func _btn(i: int) -> Array:
	var t := _mt()
	if g.state == Game.S.PAUSE:
		if UM.rm():
			return [0.0, UM.prog(0.0, UM.T1, t)]
		var s := UM.steps((t - MENU0 - UM.stagger(i, 0.06)) / 0.24, 3)
		return [roundf(24.0 * (1.0 - s)), s]
	if g.state == Game.S.DEAD:
		return [0.0, UM.prog(0.0, UM.T1, t) if UM.rm() else UM.out_cubic((t - BTN0) / UM.T2)]
	return [0.0, 1.0]


## 暂停表盘：一圈细表盘描出、12 道刻度依次出现；洋红秒针飞转减速，越过 12 点一点再弹回停住，停住时外扩一圈细环
func _draw_dial(c: Vector2, rad: float) -> void:
	var t := _mt()
	var ci: CanvasItem = g.hud
	if UM.rm():
		var fa := UM.prog(0.0, UM.T1, t)
		_dial_face(ci, c, rad, 1.0, fa)
		_dial_hand(ci, c, rad, 0.0, fa)
		return
	var ak := UM.out_cubic(t / DIAL_DRAW)
	_dial_face(ci, c, rad, ak, 1.0)
	var hk := (t - HAND0) / HAND
	if hk > 0.0:
		_dial_hand(ci, c, rad, -720.0 * (1.0 - UM.out_back(hk, 1.6)), 1.0)
	var st := (t - HAND0 - HAND) / 0.3
	if st > 0.0 and st < 1.0:
		ci.draw_arc(c, rad + 26.0 * UM.out_cubic(st), 0.0, TAU, 48, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.6 * (1.0 - st)), 1.5)


func _dial_face(ci: CanvasItem, c: Vector2, rad: float, ak: float, a: float) -> void:
	if ak <= 0.0:
		return
	ci.draw_circle(c, rad, Color(0.02, 0.05, 0.07, 0.55 * a))
	ci.draw_arc(c, rad, -PI / 2.0, -PI / 2.0 + TAU * ak, 48, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.8 * a), 1.5)
	for i in 12:
		if float(i) / 12.0 > ak:
			break
		var d := Vector2.from_angle(deg_to_rad(i * 30.0 - 90.0))
		var r0 := rad - (11.0 if i % 3 == 0 else 6.0)
		ci.draw_line(c + d * r0, c + d * (rad - 2.0), Color(1, 1, 1, (0.75 if i % 3 == 0 else 0.45) * a), 2.0 if i % 3 == 0 else 1.0)


## deg：秒针相对 12 点的角度（顺时针为正）
func _dial_hand(ci: CanvasItem, c: Vector2, rad: float, deg: float, a: float) -> void:
	var d := Vector2.from_angle(deg_to_rad(deg - 90.0))
	var red := Color(UI.RED.r, UI.RED.g, UI.RED.b, a)
	ci.draw_line(c - d * rad * 0.2, c + d * (rad - 14.0), red, 2.0)
	ci.draw_circle(c, 3.5, Color(1, 1, 1, a))


## UI.heading 的带透明度版（失败结算标题行对焦时用；终态仍调 UI.heading，像素不变）
func _heading_a(center: Vector2, s: String, size: int, half_w: float, a: float) -> void:
	var tw := g.font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var gap := tw / 2.0 + 24.0
	for sgn in [-1.0, 1.0]:
		var p0 := center + Vector2(sgn * gap, 0)
		UI.hairline(g.hud, p0, center + Vector2(sgn * half_w, 0), Color(1, 1, 1), 0.42 * a, 0.0)
		g.hud.draw_rect(Rect2(p0 + Vector2(0.0 if sgn > 0 else -14.0, -1.5), Vector2(14, 3)), Color(1, 1, 1, 0.95 * a))
	g.hud.draw_string_outline(g.font, center + Vector2(-tw / 2.0, size * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(0, 0, 0, 0.6 * a))
	g.hud.draw_string(g.font, center + Vector2(-tw / 2.0, size * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(UI.TEXT.r, UI.TEXT.g, UI.TEXT.b, a))


static func _fa(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)


func draw(vs: Vector2, title: String, en_title: String, col: Color, opts: Array, ending_panel := false, allow_unlocks := true) -> void:
	if g.settlement.active():
		g.settlement.draw(g.hud, vs)
		return
	var dim := 1.0
	if g.state == Game.S.PAUSE:
		dim = UM.prog(0.0, UM.T1, _mt()) if UM.rm() else UM.out_cubic(_mt() / PAUSE_DIM)
	g.hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.02, 0.04, 0.72 * dim))
	var pw := 600.0 if opts.size() <= 3 else 700.0   # 暂停菜单五个按钮：加宽，按键牌才放得下
	if Cfg.touch_device():
		# 手机（界面层放大后逻辑约 1044×481，手机端 UI 优化 r2）：面板占到约 90% 宽（结局结算给右侧剪影留 300）
		pw = minf(vs.x - 300.0 - 32.0, 700.0) if ending_panel else minf(vs.x - 80.0, 960.0)
	var r := Rect2(vs.x / 2 - pw / 2.0, vs.y / 2 - 190, pw, 380)
	if ending_panel:
		# 面板 + 右侧剪影（约 260 宽）整体居中，剪影和「结局 Ⅱ / 已达成」不再贴屏幕右边、压到编队 HUD（触屏紧凑版 1113 宽）
		r.position.x = maxf(16.0, (vs.x - (pw + 260.0)) / 2.0)
		# 结局结算：面板右侧浮现最终 Boss 剪影 + 结局色光晕 + 一句尾声
		var en: Dictionary = D.ENDINGS.get(g.ending, {})
		var bd: Dictionary = D.ENEMIES.get(en.get("boss", ""), {})
		var btx: Texture2D = g.tex.get(bd.get("tex", ""))
		var gc: Vector2 = Vector2(r.end.x + 120, r.get_center().y - 20)
		for k in 4:
			g.hud.draw_circle(gc, 150.0 - k * 28.0 + 6.0 * sin(g.t * 1.3 + k), Color(col.r, col.g, col.b, 0.05 + 0.03 * k))
		if btx != null:
			var fw: int = btx.get_width() / 2
			var fh: int = btx.get_height()
			var k2: float = minf(200.0 / fw, 200.0 / fh)
			k2 = floorf(k2) if k2 >= 1.0 else k2
			var sz := Vector2(fw, fh) * k2
			var fr: int = int(g.t * 2.0) % 2
			var bob: float = 4.0 * sin(g.t * 1.6)
			g.hud.draw_texture_rect_region(btx, Rect2((gc - sz / 2.0 + Vector2(0, bob)).round(), sz), Rect2(fw * fr, 0, fw, fh), Color(0.55, 0.6, 0.7, 0.9))
			g.hud.draw_texture_rect_region(btx, Rect2((gc - sz / 2.0 + Vector2(0, bob)).round(), sz), Rect2(fw * fr, 0, fw, fh), Color(col.r, col.g, col.b, 0.25 + 0.1 * sin(g.t * 2.0)))
		var idx: int = ["standard", "knight", "deep", "resolve"].find(g.ending)   # 显示编号，同 gallery.ENDING_ORDER
		UI.text(g.hud, g.font, Vector2(gc.x - 90, gc.y + 124), "结局 %s" % ["Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ"][maxi(idx, 0)], 14, Color(col.r, col.g, col.b, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 180)
		UI.text(g.hud, g.font, Vector2(gc.x - 110, gc.y + 144), "已达成 %d / 4" % Cfg.endings_cleared.size(), 12, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 220)
	UI.frame(g.hud, r, col, {"t": g.t})
	g.hud.draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), Color(col.r, col.g, col.b, 0.85))
	UI.caustic(g.hud, Rect2(r.position + Vector2(24, 10), Vector2(r.size.x - 48, 24)), g.t, col)
	var ew := g.font.get_string_size(en_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + en_title.length() * 4.0
	# 标题连两侧装饰线要在面板内：结局名长（「xx · 探索完成」36 号字）时缩字号，装饰线收到面板边内 24
	var tsz := 36
	while tsz > 22 and g.font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, tsz).x > pw - 124.0:
		tsz -= 2
	var rw0: Array = _row(0)
	if rw0[1] >= 1.0:
		UI.en(g.hud, g.font, Vector2(r.get_center().x - ew / 2.0, r.position.y + 50), en_title, 13, col, 4.0)
		UI.heading(g.hud, g.font, Vector2(r.get_center().x, r.position.y + 90), title, tsz, col, minf(250.0, pw / 2.0 - 24.0))
	else:
		for gh in ([rw0[2], -rw0[2]] if rw0[2] != 0.0 else []):   # 失焦虚影
			UI.en(g.hud, g.font, Vector2(r.get_center().x - ew / 2.0 + rw0[0] + gh, r.position.y + 50), en_title, 13, _fa(col, 0.25 * rw0[1]), 4.0)
			_heading_a(Vector2(r.get_center().x + rw0[0] + gh, r.position.y + 90), title, tsz, minf(250.0, pw / 2.0 - 24.0), 0.25 * rw0[1])
		UI.en(g.hud, g.font, Vector2(r.get_center().x - ew / 2.0 + rw0[0], r.position.y + 50), en_title, 13, _fa(col, rw0[1]), 4.0)
		_heading_a(Vector2(r.get_center().x + rw0[0], r.position.y + 90), title, tsz, minf(250.0, pw / 2.0 - 24.0), rw0[1])
	if g.state == Game.S.PAUSE:
		_draw_dial(Vector2(r.end.x - (190.0 if Cfg.touch_device() else 150.0), r.position.y + 205.0), 62.0)
	var touch: bool = Cfg.touch_device()   # 触屏（手机）：统计行字 +4、按钮本体 60 高、字 19；桌面不变
	var display_time: float = maxf(0.0, g.t - g.trial.started_at) if g.trial.active else g.t
	var mm := int(display_time) / 60
	var ss := int(display_time) % 60
	var stats := [["演练用时" if g.trial.active else "探索时间", "%02d:%02d" % [mm, ss]], ["等级", "Lv.%d  %s" % [g.level, ["精零", "精英一", "精英二"][g.ch.elite]]],
		["击杀", str(g.kills)], ["难度", D.tier_name(g.tier)]]
	if not g.meta_result.is_empty() and g.state != Game.S.PAUSE:
		# 局外成长（docs/109 §3.1）：本次探索获得的生机细胞
		var mr: Dictionary = g.meta_result
		var mtxt := "+%d（评分 %d × %.2f）" % [int(mr.cells), int(mr.base), float(mr.factor)]
		if g.ending_new and g.state == Game.S.WIN:   # 评分含新结局 +40（core/meta.gd run_reward），括号内的乘法算不出这部分，单独写明
			mtxt += "  新结局 +40"
		if int(mr.bounty) > 0:
			mtxt += "  首通 +%d" % int(mr.bounty)
		stats.append(["生机细胞", mtxt])
	if ending_panel:
		var ep: String = g.endg.epilogue()   # 结局四按升华选的信物分三版（docs/154 §4）
		UI.text(g.hud, g.font, Vector2(r.position.x + 40, r.position.y + 132), ep, 15 if touch else 14, Color(col.r * 0.9 + 0.1, col.g * 0.9 + 0.1, col.b * 0.9 + 0.1, 0.9), HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 80)
		if g.ending_new:
			UI.chip(g.hud, g.font, Vector2(r.position.x + 30, r.position.y + 30), "新结局达成", col, 12)
	if allow_unlocks and g.diff_new and g.state == Game.S.WIN:
		var ul: String = "解锁难度「%s」" % D.DIFF_PRESETS[mini(g.preset + 1, D.DIFF_PRESETS.size() - 1)].name
		var ulw: float = g.font.get_string_size(ul, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.fs(13)).x + 20.0
		# 结局结算下面有尾声和统计，放不下：挪到面板右上角（左上角是「新结局达成」）；普通结算按字宽居中在标题下
		var ulp := Vector2(r.end.x - 20.0 - ulw, r.position.y + 10) if ending_panel else Vector2(r.get_center().x - ulw / 2.0, r.position.y + 118)
		UI.chip(g.hud, g.font, ulp, ul, UI.GOLD, 13)
	# 行距：多了「生机细胞」一行（docs/109 §3.1）时收紧，最后一行不压到按钮（触屏按钮 60 高、桌面 40 高）
	var y0s: float = 166.0 if ending_panel else 156.0
	var btn_top: float = r.size.y - (84.0 if touch else 70.0) - (12.0 if touch else 10.0)
	var dy: float = minf(34.0 if touch else 32.0, (btn_top - y0s) / maxf(1.0, stats.size() - 0.4))
	for i in stats.size():
		var y := r.position.y + y0s + i * dy
		var rw: Array = _row(i + 1)
		for gh in ([rw[2], -rw[2]] if rw[2] != 0.0 else []):   # 失焦虚影（只在打捞对焦途中）
			UI.text(g.hud, g.font, Vector2(r.position.x + 62 + rw[0] + gh, y), stats[i][0], 20 if touch else 16, _fa(UI.SUB, 0.25 * rw[1]))
			UI.text(g.hud, g.font, Vector2(r.position.x + 200 + rw[0] + gh, y), stats[i][1], 22 if touch else 18, _fa(UI.TEXT, 0.25 * rw[1]))
		UI.diamond(g.hud, Vector2(r.position.x + 48 + rw[0], y - 6), 3.5, Color(col.r, col.g, col.b, 0.8 * rw[1]))
		UI.text(g.hud, g.font, Vector2(r.position.x + 62 + rw[0], y), stats[i][0], 20 if touch else 16, _fa(UI.SUB, rw[1]))
		UI.text(g.hud, g.font, Vector2(r.position.x + 200 + rw[0], y), stats[i][1], 22 if touch else 18, _fa(UI.TEXT, rw[1]))
	var bx := r.position.x + 40
	var bw := (r.size.x - 80 - 12 * (opts.size() - 1)) / opts.size()
	g.result_btns.clear()
	var mouse := g.hud.get_local_mouse_position()
	for op in opts:
		var br := Rect2(bx, r.end.y - 84, bw, 60) if touch else Rect2(bx, r.end.y - 70, bw, 40)
		var bi: int = g.result_btns.size()
		g.result_btns.append([br.grow_individual(6, 12, 6, 12) if Pad.touch_ui() else br, op[2]])   # 触屏点击区 80 高
		var hov: bool = (bi == g.res_sel) if (Pad.using or g.kb_nav) else br.has_point(mouse)
		var bm: Array = _btn(bi)   # 只偏移绘制，命中区（上面登记的 br）是终态
		bx += bw + 12
		if bm[1] <= 0.0:
			continue
		br.position.x += bm[0]
		g.hud.draw_rect(br, _fa(UI.CYAN if hov else Color(UI.STEEL.r, UI.STEEL.g, UI.STEEL.b, 0.4), bm[1]))
		var bink := _fa(Color(0.04, 0.07, 0.09) if hov else UI.TEXT, bm[1])
		UI.text(g.hud, g.font, br.position + Vector2(14, 38 if touch else 26), op[0], 19 if touch else 15, bink)
		var kst: String = ("Ⓐ" if hov else "") if Pad.using else ("" if Pad.touch else str(op[1]).to_upper())   # 10-31 TA H7：键名统一大写（ESC）
		if kst != "":
			UI.keycap(g.hud, g.font, Vector2(br.end.x - UI.cwidth(g.font, kst, 10) - 20, br.position.y + 11), kst, bink, 10)


## Tab 面板攻击栏下半：开局干员的三个技能 + 天赋。说明按栏宽折行；先每条给 1 行，再轮流给还没排完的加行，
## 直到把剩余高度用完。排不完的末行加「…」，鼠标移到这一行上看完整说明（stats_cells 的 skill 项）
func draw_generic_skill_rows(b1: Rect2, y: float, rows: Array, dfs := 11, nfs := 14) -> float:
	var c: Color = g.ch.col()
	var x0 := b1.position.x + 62.0
	var dw := b1.end.x - 14.0 - x0
	var lh: float = g.font.get_height(UI.fs(dfs)) + 1.0
	var avail: float = b1.end.y - 6.0 - y
	var rh := func(n: int) -> float: return maxf(42.0, 30.0 + n * lh)
	var wrapped: Array = []
	var give: Array = []
	var used := 0.0
	for row in rows:
		var wl: PackedStringArray = UI.wrap_lines(g.font, row[2], dfs, dw)
		wrapped.append(wl)
		give.append(mini(1, wl.size()))
		used += rh.call(give[give.size() - 1])
	var grew := true
	while grew:
		grew = false
		for k in rows.size():
			if give[k] < wrapped[k].size():
				var add: float = rh.call(give[k] + 1) - rh.call(give[k])
				if used + add <= avail:
					give[k] += 1
					used += add
					grew = true
	for k in rows.size():
		var row: Array = rows[k]
		var on: bool = row[3]
		var col: Color = (Color(0.85, 0.55, 1.0) if row[4] else c) if on else Color(0.35, 0.42, 0.46)
		var sc := Vector2(b1.position.x + 34, y + 20)
		var itx: Texture2D = g.tex.get(row[5]) if row.size() > 5 and row[5] != "" else null
		if itx != null:
			# 技能图标（32px 原尺寸），未解锁压暗；左下角小牌标技能序号
			g.hud.draw_texture_rect(itx, Rect2(sc - Vector2(16, 16), Vector2(32, 32)), false, Color.WHITE if on else Color(0.34, 0.37, 0.41))
			g.hud.draw_rect(Rect2(sc + Vector2(-17, 5), Vector2(11, 12)), Color(0.03, 0.035, 0.045, 0.92))
			UI.ctext(g.hud, g.font, sc + Vector2(-16, 15), row[0], 10, col, HORIZONTAL_ALIGNMENT_CENTER, 9)
		else:
			UI.ring(g.hud, sc, 17.0, 1.0 if on else 0.0, col, false, not on)
			UI.text(g.hud, g.font, sc + Vector2(-12, 7), row[0], 15, col, HORIZONTAL_ALIGNMENT_CENTER, 24)
		UI.text_fit(g.hud, g.font, Vector2(x0, y + 16), row[1] + ("  ·排异" if row[4] else ""), nfs, UI.TEXT if on else UI.SUB, dw, 11)
		var lines: PackedStringArray = wrapped[k]
		var dcol: Color = col if on else Color(0.42, 0.48, 0.52)
		for j in give[k]:
			var ln: String = lines[j]
			if j == give[k] - 1 and give[k] < lines.size():
				while ln.length() > 0 and g.font.get_string_size(ln + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, UI.fs(dfs)).x > dw:
					ln = ln.substr(0, ln.length() - 1)
				ln += "…"
			UI.text(g.hud, g.font, Vector2(x0, y + 33 + j * lh), ln, dfs, dcol)
		var row_h: float = rh.call(give[k])
		g.stats_cells.append([Rect2(Vector2(b1.position.x + 14, y), Vector2(b1.size.x - 28, row_h)), "skill", row])
		y += row_h
	return y
