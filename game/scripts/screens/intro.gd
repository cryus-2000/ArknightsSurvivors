extends RefCounted
## 界面 · 开场与教程：开局镜头演出（state OPENING）与其 HUD、新手教程分页（state INTRO）的打开 / 翻页 / 关闭 / 绘制。
## 界面层约定（docs/39 §3）：只读 game.gd 状态、只画自己的界面；改状态走 game.gd / run/ 的函数。2026-09-26 从 game.gd 拆出。

const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
const A = preload("res://scripts/art.gd")
const Character = preload("res://scripts/characters/character.gd")
const NodeIcons = preload("res://scripts/screens/node_icons.gd")   # 节点卡图标（docs/154）

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game
var opening_t := 0.0             # 开场动画时间
const OPENING_DUR := 3.6


func _init(game: Game) -> void:
	g = game


func prev_page() -> void:
	if g.intro_page > 0:
		g.intro_page -= 1
		g.intro_t = 0.0
		Sfx.play("ui_move")


## 开场动画：水月自海面沉降落地 → 灯火点亮 → 标题卡；任意键跳过，之后进入指南
func start_opening() -> void:
	g.state = Game.S.OPENING
	opening_t = 0.0
	g.p_off = Vector2(0, -320)
	g.lamp_light.energy = 0.0
	Sfx.play("start", -14.0)   # 音量巡检：开场引子开头近乎无声，-4 dB 时比音乐响 29 dB；现在只托住开头，和 1.7 秒后的引子齐平


func update_opening(dt: float) -> void:
	opening_t += dt
	var k1 := clampf(opening_t / 1.7, 0.0, 1.0)
	var ease_in := 1.0 - pow(1.0 - k1, 2.2)
	g.p_off = Vector2(sin(opening_t * 3.0) * 6.0 * (1.0 - k1), -320.0 * (1.0 - ease_in))
	g.p_lean = sin(opening_t * 2.0) * 0.08 * (1.0 - k1)
	g.p_sq = Vector2(1.0 - 0.06 * (1.0 - k1), 1.0 + 0.1 * (1.0 - k1))
	# 上升的气泡
	if k1 < 1.0 and randf() < 0.6:
		g.fx.append({"kind": "spark", "pos": g.ppos + g.p_off + Vector2(randf_range(-22, 22), randf_range(-40, 10)), "vel": Vector2(randf_range(-8, 8), -randf_range(40, 90)), "sz": randf_range(2.0, 3.5), "life": 1.1, "max": 1.1, "col": Color(0.8, 0.95, 1.0, 0.7)})
	# 落地
	if opening_t >= 1.7 and opening_t - dt < 1.7:
		g.p_sq = Vector2(1.3, 0.72)
		g.world.feet_dust(14, 150.0)
		g.fx.append({"kind": "ring", "pos": g.ppos + Vector2(0, 6), "r": 60.0, "life": 0.45, "max": 0.45, "col": Color(0.6, 0.85, 1.0)})
		g.vfx.shake_screen(0.7)
		Sfx.play("boom", -14.0, 1.4, 0.0)
		for o in g.squad.ops:
			o.play_entry()   # 编队着地接入场条（10-22）
		g.release_entry_voices()   # 登场语音在编队着地、黑场已褪时才播（以前在建局时就响，画面还没出来，用户 10-25）
	if opening_t >= 1.7:
		for o in g.squad.ops:
			if o.vis_anim == "entry":
				o.anim_t += dt   # 开场期间干员不走 update：入场条在这里推进（end_opening 后由 update 接着走）
		g.p_sq = g.p_sq.lerp(Vector2.ONE, 1.0 - exp(-dt * 10.0))
		g.p_lean = lerpf(g.p_lean, 0.0, 1.0 - exp(-dt * 10.0))
	# 灯火点亮：2.1s 起，先闪两下再稳定
	if opening_t >= 2.1:
		var k2 := clampf((opening_t - 2.1) / 0.8, 0.0, 1.0)
		var fl := 1.0 if k2 > 0.5 else (1.0 if fmod(k2, 0.2) < 0.1 else 0.25)
		g.lamp_light.energy = 1.15 * k2 * fl
		if opening_t - dt < 2.1:
			Sfx.play("oil", -8.0, 1.2, 0.0)
			g.fx.append({"kind": "rays", "pos": g.ppos + Vector2(0, -20), "life": 0.8, "max": 0.8, "col": Color(1.0, 0.85, 0.5)})
	g.vfx.update(dt)
	if opening_t >= OPENING_DUR:
		end_opening()


func end_opening() -> void:
	if g.state != Game.S.OPENING:
		return
	g.p_off = Vector2.ZERO
	g.p_sq = Vector2.ONE
	g.p_lean = 0.0
	g.lamp_light.energy = 1.15
	g.state = Game.S.PLAY
	g.release_entry_voices()   # 跳过开场：没等到着地也放
	# 首局改聚光框引导（协调人 10-26，screens/tour.gd）；翻页指南只在暂停菜单「指南」里重看
	if not Cfg.seen_intro:
		g.tour.start()


func draw_opening_hud(vs: Vector2) -> void:
	# 黑场渐亮 + 上下黑边 + 标题卡
	var dark: float = clampf(1.0 - opening_t / 1.2, 0.0, 1.0) * 0.9 + 0.1
	if opening_t > 2.9:
		dark = lerpf(0.1, 0.0, clampf((opening_t - 2.9) / 0.7, 0.0, 1.0))
	g.hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.0, 0.01, 0.03, dark))
	var bar: float = 70.0 * (1.0 - clampf((opening_t - 2.9) / 0.7, 0.0, 1.0))
	g.hud.draw_rect(Rect2(0, 0, vs.x, bar), Color(0, 0, 0, 0.95))
	g.hud.draw_rect(Rect2(0, vs.y - bar, vs.x, bar), Color(0, 0, 0, 0.95))
	if opening_t > 0.4 and opening_t < 3.3:
		var a: float = clampf((opening_t - 0.4) / 0.6, 0.0, 1.0) * clampf((3.3 - opening_t) / 0.5, 0.0, 1.0)
		# 英文行按开局干员（data/characters 的 en），按字宽 + 字距居中
		var ens: String = "OPERATION  %s" % String(g.ch.def.get("en", "MIZUKI")).to_upper()
		var enw := -5.0
		for ch in ens:
			enw += UI.cond(g.font).get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 5.0   # 同 UI.en 的逐字排法
		UI.en(g.hud, g.font, Vector2(vs.x / 2 - enw / 2.0, vs.y * 0.22), ens, 13, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, a), 5.0)
		UI.text(g.hud, g.font, Vector2(0, vs.y * 0.22 + 44), "%s  ·  深海探索" % g.ch.display_name(), 34, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 4)
		UI.text(g.hud, g.font, Vector2(0, vs.y * 0.22 + 74), "行动目标：维持作战至 10:00，击败最终 Boss", 14, Color(0.7, 0.85, 0.9, a * 0.9), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 3)
	UI.text(g.hud, g.font, Vector2(0, vs.y - 26), "点击跳过" if Pad.touch_ui() else "任意键跳过", 12, Color(0.5, 0.6, 0.65, 0.7), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 2)


## 指南文字在 data/guide.json（文案维护；10-15 从 game.gd INTRO_PAGES 与本文件的 TOUCH_SUBS / TOUCH_CONTROLS / MORE_HINT 原样搬去，docs/101 S5）：
## pages 8 页（title / en / icon / lines / more）；touch_subs 触屏版逐句替换 [键鼠说法, 触屏说法]；touch_controls 触屏版最后一页「操作」整页；
## more_hint 精简版（首次自动打开）最后一页末尾的提示
static var _guide: Dictionary = {}


static func _g() -> Dictionary:
	if _guide.is_empty():
		_guide = JSON.parse_string(FileAccess.get_file_as_string("res://data/guide.json"))
	return _guide


static func pages() -> Array:
	return _g().pages


static func touch_line(ln: String) -> String:
	if not Pad.touch_ui():
		return ln
	for p in _g().touch_subs:
		ln = ln.replace(p[0], p[1])
	return ln


## 完整版指南：从暂停菜单打开（G / 「指南」）时显示每页的 lines + more；首次进局自动打开的是精简版（只有 lines）
func full_guide() -> bool:
	return g.intro_back == Game.S.PAUSE


## 一页要显示的段落：精简版只有 lines，最后一页末尾加 more_hint；完整版接上 more
static func page_lines(pg: Dictionary, full: bool, last: bool) -> Array:
	var out: Array = pg.get("lines", []).duplicate()
	if full:
		out.append_array(pg.get("more", []))
	elif last:
		out.append(_g().more_hint)
	return out


func open(back: int) -> void:
	g.intro_back = back
	g.intro_page = 0
	g.intro_t = 0.0
	g.state = Game.S.INTRO


func next_page() -> void:
	Sfx.play("ui_move")
	if g.intro_page < pages().size() - 1:
		g.intro_page += 1
		g.intro_t = 0.0
	else:
		close()


func close() -> void:
	Cfg.seen_intro = true
	Cfg.save()
	g.state = g.intro_back
	Sfx.play("ui_ok", -4.0)


func draw(vs: Vector2) -> void:
	if g.tour.active:
		g.tour.draw(vs)
		return
	g.hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.0, 0.02, 0.04, 0.88))
	var pg: Dictionary = pages()[g.intro_page]
	var rh: float = minf(570.0, vs.y - 16.0)
	var r := Rect2(vs.x / 2 - 450, vs.y / 2 - rh / 2.0, 900, rh)
	var ea := clampf(g.intro_t / 0.25, 0.0, 1.0)
	r.position.y += (1.0 - ea) * 20.0
	UI.panel(g.hud, r, UI.BG2, UI.LINE, 16.0, UI.CYAN)
	UI.en(g.hud, g.font, r.position + Vector2(40, 46), "GUIDE  %d / %d  ·  %s" % [g.intro_page + 1, pages().size(), pg.en], 12, UI.CYAN, 3.0)
	UI.text(g.hud, g.font, r.position + Vector2(40, 90), pg.title, 30, UI.TEXT)
	g.hud.draw_line(r.position + Vector2(40, 108), r.position + Vector2(r.size.x - 40, 108), UI.CYAN_DIM, 1.0)
	# 装饰：大号页码水印（右上，极淡）+ 插图区取景框四角（终末地的取景框角标）
	if not Cfg.touch_device():   # 手机上右上角是「跳过」，不叠水印
		UI.text(g.hud, g.font, Vector2(r.end.x - 230, r.position.y + 104), "%02d" % (g.intro_page + 1), 88, Color(0.6, 0.9, 0.95, 0.07 * ea), HORIZONTAL_ALIGNMENT_RIGHT, 190)
	var fr0 := Rect2(r.position + Vector2(36, 132), Vector2(292, r.size.y - 132.0 - 76.0))
	for sx in [0.0, 1.0]:
		for sy in [0.0, 1.0]:
			var q := Vector2(fr0.position.x + sx * fr0.size.x, fr0.position.y + sy * fr0.size.y)
			var dx := -16.0 if sx > 0.5 else 16.0
			var dy := -16.0 if sy > 0.5 else 16.0
			g.hud.draw_polyline(PackedVector2Array([q + Vector2(0, dy), q, q + Vector2(dx, 0)]), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.4 * ea), 1.5)
	# 插图区
	var ic := r.position + Vector2(170, 270)
	draw_icon(pg.icon, ic)
	# 文字：按实际折行高度一段接一段排（旧版每段固定 100 像素、最多 4 行，一页 4 段时会压到按钮）；
	# 整页放不下先缩字号（15 → 12）
	var tx := r.position.x + 356
	var tw := r.size.x - 392
	var top := r.position.y + 142
	var avail := r.end.y - 62.0 - top
	var touch: bool = Cfg.touch_device()
	var fsz := 19 if touch else 17   # 正文先试大字，放不下逐号缩小（手机 19 → 13，桌面 17 → 12；手机局内再乘 UI.fk，量字画字都用 UI.fs）
	var fsz_min := 13 if touch else 12
	var src: Dictionary = _g().touch_controls if Pad.touch_ui() and g.intro_page == pages().size() - 1 else pg
	var src_lines: Array = page_lines(src, full_guide(), g.intro_page == pages().size() - 1)
	# 每条 =「标签｜正文」：标签列（青色小字）+ 正文列，条与条之间一条淡分隔线；没有「｜」的整行通栏（精简版末页的提示）
	var rows: Array = []
	for ln in src_lines:
		var txt: String = touch_line(fill_numbers(ln))
		var cut: int = txt.find("｜")
		rows.append({"label": txt.substr(0, cut) if cut > 0 else "", "text": txt.substr(cut + 1) if cut > 0 else txt})
	var lbl_w := 92.0 if touch else 78.0
	var row_gap := 12.0 if touch else 16.0
	var lhh := 0.0
	var asc := 0.0
	while true:
		lhh = g.font.get_height(UI.fs(fsz)) + 2.0
		asc = g.font.get_ascent(UI.fs(fsz))
		var tot := 0.0
		for row in rows:
			row["lines"] = UI.wrap_lines(g.font, row.text, fsz, tw - (lbl_w if row.label != "" else 0.0))
			tot += maxf(row.lines.size() * lhh, lhh) + row_gap
		if tot - row_gap <= avail or fsz <= fsz_min:
			break
		fsz -= 1
	var lbl_sz := clampi(fsz - 3, 12, 15)
	var y := top
	for ri in rows.size():
		var row: Dictionary = rows[ri]
		if y + lhh > r.end.y - 58.0:
			break   # 整条放不下就不画（不让标签孤零零露出来）
		if ri > 0:
			g.hud.draw_line(Vector2(tx, y - row_gap / 2.0 - 1.0), Vector2(tx + tw, y - row_gap / 2.0 - 1.0), Color(0.45, 0.8, 0.85, 0.12 * ea), 1.0)
		if row.label != "":
			# 标签芯片：淡青底 + 左端一道青条，字居中（终末地的标签牌）
			var la: float = g.font.get_ascent(UI.fs(lbl_sz))
			var lh: float = g.font.get_height(UI.fs(lbl_sz))
			var chip := Rect2(tx, y + (lhh - lh - 8.0) / 2.0, lbl_w - 14.0, lh + 8.0)
			g.hud.draw_rect(chip, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.1 * ea))
			g.hud.draw_rect(Rect2(chip.position, Vector2(2.0, chip.size.y)), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, ea))
			g.hud.draw_string(g.font, Vector2(chip.position.x, chip.position.y + 4.0 + la), row.label, HORIZONTAL_ALIGNMENT_CENTER, chip.size.x, UI.fs(lbl_sz), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, ea))
		var y0 := y
		for ln2 in row.lines:
			if y + lhh > r.end.y - 58.0:
				break
			g.hud.draw_string(g.font, Vector2(tx + (lbl_w if row.label != "" else 0.0), y + asc), ln2, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.fs(fsz), Color(0.9, 0.96, 0.98, ea))
			y += lhh
		y = maxf(y, y0 + lhh) + row_gap
	# 页码点（可点击）
	g.intro_panel = r
	g.intro_dots.clear()
	var mp: Vector2 = g.hud.get_local_mouse_position()
	for i in pages().size():
		var dp := Vector2(vs.x / 2 - (pages().size() - 1) * 13 + i * 26, r.end.y - 30)
		var dr := Rect2(dp - Vector2(12, 12), Vector2(24, 24))
		g.intro_dots.append([dr, i])
		var hov: bool = dr.has_point(mp)
		UI.diamond(g.hud, dp, 6.0 if hov else 5.0, UI.CYAN if i == g.intro_page else (Color(0.3, 0.5, 0.55) if hov else Color(0.15, 0.25, 0.28)))
	# 上一页 / 跳过 / 下一页 按钮
	var btns: Array = [["‹ 上一页", "prev"], ["跳过", "skip"], ["下一页 ›", "next"]]   # 10-31 TA H7：键名不夹在按钮文字里
	for k in 3:
		var bw := 118.0 if not touch else 140.0
		var bx: float = [r.position.x + 40, vs.x / 2 - bw / 2.0, r.end.x - 40 - bw][k]
		var br := Rect2(bx, r.end.y - 52, bw, 34) if not touch else Rect2(bx, r.end.y - 60, bw, 44)   # 触屏按钮本体 44 高、字 16
		# 触屏：点击区上下各扩 22、左右各扩 12（34 高 → 78，≈ 43 pt），图形不变
		var hit: Rect2 = br.grow_individual(12, 22, 12, 22) if Pad.touch_ui() else br
		match k:
			0: g.intro_btn_prev = hit
			1: g.intro_btn_skip = hit
			2: g.intro_btn_next = hit
		var hov2: bool = br.has_point(mp)
		var dim: bool = k == 0 and g.intro_page == 0
		if k == 1:
			br.position.y = r.end.y + 16
			if br.end.y > vs.y - 4:
				# 紧凑排版（手机逻辑高 626）：面板下方放不下，「跳过」挪进面板右上角（触屏验收 10-01）
				br.position = Vector2(r.end.x - 40 - bw, r.position.y + 22)
			g.intro_btn_skip = br.grow_individual(12, 22, 12, 22) if Pad.touch_ui() else br
			UI.text(g.hud, g.font, br.position + Vector2(0, 22), btns[k][0], 13 if not touch else 15, UI.CYAN if hov2 else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, br.size.x)
			continue
		UI.frame(g.hud, br, UI.CYAN, {"cut": 6.0, "bracket": 6.0, "glow": 1.0 if hov2 else 0.0, "alpha": 0.3 if dim else (1.0 if hov2 else 0.7)})
		UI.text(g.hud, g.font, br.position + Vector2(0, 23 if not touch else 29), btns[k][0] if k != 2 or g.intro_page < pages().size() - 1 else "开始探索 ›", 14 if not touch else 16, UI.TEXT if not dim else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, br.size.x)
	if r.end.y + 66 < vs.y:
		UI.text(g.hud, g.font, Vector2(r.position.x, r.end.y + 60), Pad.hint("左键 / 任意键：下一页　　右键 / ←：上一页　　点面板左侧也可回退", "Ⓐ / → / RB：下一页　　← / LB：上一页　　Ⓑ：跳过", "点击：下一页　　点面板左侧：上一页"), 12, Color(0.45, 0.55, 0.6), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


## 触屏版「操作」页插图（手机设置页改版 10-06）：小手机框，左半屏虚拟摇杆（圆环 + 来回摆的旋钮）+ 右下冲刺键 / 技能键，
## 和局内 touch.gd 的画法同一套（圆底 + 青色环 + 字）
func _draw_touch_keys(c: Vector2) -> void:
	var fr := Rect2(c + Vector2(-150, -84), Vector2(300, 168))
	g.hud.draw_rect(fr, Color(0.03, 0.08, 0.11, 0.9))
	g.hud.draw_rect(fr, UI.CYAN_DIM, false, 1.5)
	g.hud.draw_line(Vector2(c.x, fr.position.y + 6), Vector2(c.x, fr.end.y - 6), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.15), 1.0)
	# 左半屏：摇杆（旋钮绕中心慢转，示意拖动）
	var so := c + Vector2(-78, 4)
	g.hud.draw_circle(so, 40.0, Color(0.05, 0.12, 0.16, 0.5))
	g.hud.draw_arc(so, 40.0, 0.0, TAU, 40, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.55), 2.0)
	var knob := so + Vector2(cos(g.intro_t * 1.6), sin(g.intro_t * 1.6)) * 22.0
	g.hud.draw_circle(knob, 14.0, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.35))
	g.hud.draw_arc(knob, 14.0, 0.0, TAU, 24, Color(0.8, 1.0, 1.0, 0.85), 2.0)
	UI.text(g.hud, g.font, so + Vector2(-60, 64), "左半屏拖动", 12, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 120)
	# 右下：冲刺键；左上斜方技能键
	var dc := c + Vector2(96, 36)
	g.hud.draw_circle(dc, 26.0, Color(0.05, 0.12, 0.16, 0.7))
	g.hud.draw_arc(dc, 26.0, 0.0, TAU, 40, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.9), 3.0)
	UI.text(g.hud, g.font, dc + Vector2(-30, 6), "冲刺", 14, Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_CENTER, 60)
	var sc := dc + Vector2(-58, -56)
	var pulse: float = 0.5 + 0.5 * sin(g.intro_t * 4.0)
	g.hud.draw_circle(sc, 22.0, Color(0.05, 0.12, 0.16, 0.75))
	g.hud.draw_arc(sc, 22.0, 0.0, TAU, 32, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.9), 2.0)
	g.hud.draw_arc(sc, 26.0 + 2.0 * pulse, 0.0, TAU, 32, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.3 + 0.5 * pulse), 2.0)
	UI.text(g.hud, g.font, sc + Vector2(-30, 5), "技能", 13, Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_CENTER, 60)
	UI.text(g.hud, g.font, c + Vector2(10, fr.end.y - c.y - 8), "轻点自动瞄准 · 按住拖方向", 11, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 140)


func draw_icon(kind: String, c: Vector2) -> void:
	match kind:
		"mizuki":
			# 开局干员的攻击动作（水月沿用 48px 挥伞条）
			var tx: Texture2D = g.tex.get("player_attack_48") if g.ch.id == "mizuki" else g.ch.anim_tex("attack")
			if tx != null:
				var fh0 := tx.get_height()
				var fr := int(g.intro_t * 8.0) % maxi(1, tx.get_width() / fh0)
				# 1 美术像素 = 4 屏幕像素，脚底落在 c + (0, 34)；画布 48 / 64 都按 json foot 对齐（48 画布 = 原来的 c − (96, 150)、192 见方）
				var fs1: float = fh0 / A.hires_of(tx)
				var ft0: Array = g.ch.sprite_spec("attack").get("foot", g.ch.def.get("sprites", {}).get("foot", [fs1 / 2.0, fs1 - 2.0]))
				g.hud.draw_texture_rect_region(tx, Rect2(c + Vector2(0, 34) - Vector2(float(ft0[0]), float(ft0[1])) * 4.0, Vector2(fs1, fs1) * 4.0), Rect2(fh0 * fr, 0, fh0, fh0))
			for k in 3:
				var et: Texture2D = g.tex.get(["e_bone", "e_slider", "e_stone"][k])
				if et != null:
					var fw := et.get_width() / 2
					# 1 美术像素 = 2 屏幕像素：@2x 帧条（docs/94 重画）按 A.hires_of 换算，和 1x 同尺寸
					g.hud.draw_texture_rect_region(et, Rect2(c + Vector2(-110 + k * 90, 70), Vector2(fw, et.get_height()) * 2.0 / A.hires_of(et)), Rect2(0, 0, fw, et.get_height()))
		"bars":
			UI.en(g.hud, g.font, c + Vector2(-110, -60), "HP", 12, UI.SUB, 2.0)
			UI.bar(g.hud, Rect2(c + Vector2(-80, -72), Vector2(180, 14)), 0.7, Color(0.35, 0.9, 0.75), 10)
			UI.en(g.hud, g.font, c + Vector2(-110, -10), "LIGHT", 12, UI.GOLD, 1.0)
			UI.bar(g.hud, Rect2(c + Vector2(-50, -22), Vector2(150, 14)), 0.55, UI.GOLD, 5)
			for tv in [30.0, 70.0]:
				var tx2: float = c.x - 50 + 150 * tv / 100.0
				g.hud.draw_line(Vector2(tx2, c.y - 26), Vector2(tx2, c.y - 4), Color(1, 1, 1, 0.8), 1.5)
			var ot: Texture2D = g.tex.get("oil")
			if ot != null:
				g.hud.draw_texture_rect(ot, Rect2(c + Vector2(-20, 30), Vector2(36, 48)), false)
			UI.text(g.hud, g.font, c + Vector2(26, 64), "灯油", 14, UI.GOLD)
		"mire":
			var mt: Texture2D = g.tex.get("terrain_mire")
			if mt != null:
				var fw := mt.get_width() / 2
				g.hud.draw_texture_rect_region(mt, Rect2(c - Vector2(80, 110), Vector2(160, 160)), Rect2(fw * (int(g.intro_t * 2.0) % 2), 0, fw, mt.get_height()))
			g.hud.draw_arc(c + Vector2(0, 40), 140.0, PI * 1.1, PI * 1.9, 32, Color(0.85, 0.4, 1.0), 3.0)
			UI.text(g.hud, g.font, c + Vector2(-60, 110), "黑潮边界", 14, Color(0.85, 0.5, 1.0))
		"cards":
			# 三张示意卡：开局干员的待机帧（成长）/ 另一名干员的待机帧（招募）/ 被动图标
			var other_id := ""
			for cid0 in Character.list_ids():
				if cid0 != g.ch.id and Character.load_def(cid0).get("recruitable", true):
					other_id = cid0
					break
			for k in 3:
				var rc := Rect2(c + Vector2(-130 + k * 88, -90), Vector2(76, 110))
				var cc: Color = [UI.CYAN, Color(0.55, 0.95, 1.0), UI.GOLD][k]
				UI.panel(g.hud, rc, Color(0.03, 0.08, 0.1), cc, 6.0)
				var cc0 := rc.position + Vector2(rc.size.x / 2.0, 48)
				if k < 2:
					var idl: Dictionary = g.panel_ui.op_idle(g.ch.id if k == 0 else other_id)
					if not idl.is_empty():
						var wn: Rect2 = idl.win   # 64 画布取脚底为准的 48 范围（UI.op_win）
						var ks: float = 1.5 if wn.size.y <= 48 else 72.0 / wn.size.y
						var asz := wn.size * ks
						g.hud.draw_texture_rect_region(idl.tex, Rect2(cc0 - asz / 2.0 + Vector2(0, 4), asz), wn)
				else:
					var gt: Texture2D = g.tex.get("growth_hp")
					if gt != null:
						g.hud.draw_texture_rect(gt, Rect2(cc0 - Vector2(24, 24), Vector2(48, 48)), false)
				UI.text(g.hud, g.font, rc.position + Vector2(0, 100), ["成长", "招募", "被动"][k], 12, cc, HORIZONTAL_ALIGNMENT_CENTER, rc.size.x)
			UI.text(g.hud, g.font, c + Vector2(-130, 60), "干员成长 / 招募 / 生存与机动", 14, UI.SUB)
		"loot":
			var items := ["ingot", "e_chest", "pickup_magnet", "pickup_heal", "merchant"]
			for k in items.size():
				var tx3: Texture2D = g.tex.get(items[k])
				if tx3 == null:
					continue
				var frames := 2 if items[k] == "e_chest" or items[k] == "merchant" else 1
				var fw := tx3.get_width() / frames
				var hi3: float = A.hires_of(tx3)
				var sc: float = (3.0 if tx3.get_height() / hi3 < 20 else 2.0) / hi3   # 按美术像素定倍数（@2x 不放大一倍）
				var sz := Vector2(fw, tx3.get_height()) * sc
				var p := c + Vector2(-120 + (k % 3) * 100, -70 + (k / 3) * 100)
				g.hud.draw_texture_rect_region(tx3, Rect2(p - sz / 2.0, sz), Rect2(0, 0, fw, tx3.get_height()))
		"threat":
			# 威胁等级条 Ⅰ–Ⅵ + 大群预警环
			var names := ["浅滩", "暗流", "深潜", "裂隙", "深渊", "深蓝之树"]
			var lit: int = int(g.intro_t * 1.2) % 7
			for k in 6:
				var rc := Rect2(c + Vector2(-138 + k * 46, -96), Vector2(40, 14))
				var on: bool = k < lit
				g.hud.draw_rect(rc, Color(0.6, 0.35, 1.0, 0.9) if on else Color(0.08, 0.12, 0.16))
				g.hud.draw_rect(rc, Color(0.7, 0.5, 1.0, 0.8), false, 1.0)
				UI.text(g.hud, g.font, rc.position + Vector2(0, -6), ["Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ", "Ⅴ", "Ⅵ"][k], 11, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, rc.size.x)
				UI.text(g.hud, g.font, rc.position + Vector2(-8, 30), names[k], 10, UI.TEXT if on else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, rc.size.x + 16)
			var hk: float = fmod(g.intro_t, 2.4) / 2.4
			g.hud.draw_arc(c + Vector2(0, 30), 30.0 + hk * 90.0, 0.0, TAU, 48, Color(0.75, 0.3, 1.0, 0.7 * (1.0 - hk)), 3.0)
			g.hud.draw_arc(c + Vector2(0, 30), 36.0, 0.0, TAU, 32, Color(0.75, 0.3, 1.0, 0.5), 2.0)
			var etx: Texture2D = g.tex.get("e_bone")
			if etx != null:
				for k in 8:
					var an: float = TAU * k / 8.0 + g.intro_t * 0.4
					var fw2: int = etx.get_width() / 2
					var pp: Vector2 = c + Vector2(0, 30) + Vector2.from_angle(an) * (78.0 - 30.0 * hk)
					var esz: Vector2 = Vector2(fw2, etx.get_height()) * 2.0 / A.hires_of(etx)   # @2x 按高清倍率换算
					g.hud.draw_texture_rect_region(etx, Rect2(pp - esz / 2.0, esz), Rect2(0, 0, fw2, etx.get_height()))
			UI.text(g.hud, g.font, c + Vector2(-60, 116), "大群来袭", 14, Color(0.85, 0.6, 1.0), HORIZONTAL_ALIGNMENT_CENTER, 120)
		"merchant":
			var mtx: Texture2D = g.tex.get("merchant")
			if mtx != null:
				var fw3: int = mtx.get_width() / 2
				var fr3: int = int(g.intro_t * 2.0) % 2
				var sz3 := Vector2(fw3, mtx.get_height()) * 3.0 / A.hires_of(mtx)   # @2x 按高清倍率换算
				g.hud.draw_texture_rect_region(mtx, Rect2(c - Vector2(sz3.x / 2.0, sz3.y - 40), sz3), Rect2(fw3 * fr3, 0, fw3, mtx.get_height()))
			var left: int = 60 - int(fmod(g.intro_t * 6.0, 60.0))
			var mc: Color = UI.GOLD if left > 15 else UI.GOLD.lerp(UI.RED, 0.5 + 0.5 * sin(g.intro_t * 8.0))
			UI.ring(g.hud, c + Vector2(0, -120), 22.0, left / 60.0, mc)
			UI.text(g.hud, g.font, c + Vector2(-30, -114), "%ds" % left, 15, mc, HORIZONTAL_ALIGNMENT_CENTER, 60)
			UI.text(g.hud, g.font, c + Vector2(-80, 74), "商人  ·  停留 60 秒", 14, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 160)
			for k in 3:
				UI.chip(g.hud, g.font, c + Vector2(-118 + k * 84, 90), ["2:00", "5:00", "8:00"][k], UI.GOLD, 12)
		"nodes":
			# 三张背面朝上的节点卡（docs/154）：中间那张「不期而遇」每 1.6 秒抬起一次；左右是随机填充的卡
			var kinds := ["wish", "incident", "rest"]
			for k in 3:
				var up: float = 10.0 * maxf(0.0, sin(g.intro_t * 3.9)) if k == 1 else 0.0
				var cr := Rect2(c + Vector2(-112 + k * 76 - 32, -64 - up), Vector2(64, 90))
				g.hud.draw_rect(cr, Color(0.06, 0.11, 0.15, 0.96))
				g.hud.draw_rect(cr, NodeIcons.COLS[kinds[k]] if k == 1 else Color(1, 1, 1, 0.16), false, 2.0 if k == 1 else 1.0)
				NodeIcons.draw(g.hud, kinds[k], cr.get_center(), 2.0, NodeIcons.COLS[kinds[k]])
			var ends := [["Ⅰ", g.endg.ending_col("standard")], ["Ⅱ", g.endg.ending_col("knight")], ["Ⅲ", g.endg.ending_col("deep")], ["Ⅳ", g.endg.ending_col("resolve")]]
			for k in 4:
				var ec: Color = ends[k][1]
				UI.diamond(g.hud, c + Vector2(-66 + k * 44, 92), 9.0, Color(ec.r, ec.g, ec.b, 0.35), ec)
				UI.text(g.hud, g.font, c + Vector2(-86 + k * 44, 122), ends[k][0], 13, ec, HORIZONTAL_ALIGNMENT_CENTER, 40)
		"command":
			# 指挥圆盘：直接缩小画当前的圆盘（终末地风格，command_wheel.gd 同一份画法），每 1.4 秒轮流悬停一项
			g.wheel.draw_preview(c + Vector2(0, 4), 0.56, g.intro_t)
		"keys":
			if Pad.touch_ui():
				_draw_touch_keys(c)
				return
			var keys := [["W", Vector2(0, -60)], ["A", Vector2(-48, -12)], ["S", Vector2(0, -12)], ["D", Vector2(48, -12)], ["Tab", Vector2(-40, 60)], ["Esc", Vector2(40, 60)]]
			for kk in keys:
				var kr := Rect2(c + kk[1] - Vector2(20, 20), Vector2(40 if kk[0].length() == 1 else 56, 40))
				g.hud.draw_rect(kr, Color(0.08, 0.2, 0.24))
				g.hud.draw_rect(kr, UI.CYAN, false, 1.5)
				UI.text(g.hud, g.font, kr.position + Vector2(0, 27), kk[0], 15, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, kr.size.x)


## 指南正文里的数值占位（docs/83 入队加成读 balance.json squad 段；docs/88 灯火暗淡 / 受击灯火读 lamp 段、暗淡刷新读 enemy 段；不写死）。
## 缺省值与读取处一致：combat.gd（lamp/dark_taken、hit_base、hit_scale）、enemies.gd（lamp/dark_enemy）、spawner.gd（enemy/spawn_dark_mult）
## 10-24 增补：灯标（run/beacon.gd）、宝箱 / 补给箱（combat.gd、docs/133）、指挥与切换队长（docs/114、135）
static func fill_numbers(ln: String) -> String:
	if not ln.contains("{"):
		return ln
	var Bal = preload("res://scripts/core/balance.gd")
	var Sq = preload("res://scripts/characters/squad.gd")
	var pct := func(mult: float) -> String: return str(int(round((mult - 1.0) * 100.0)))
	var pc100 := func(key: String, dflt: float) -> String: return str(int(round(Bal.v(key, dflt) * 100.0)))
	var vals := {
		"{hp_per_member}": str(int(round(Bal.v("squad/hp_per_member", 0.15) * 100.0))), "{regen_per_member}": Sq.regen_steps_text(),
		"{dark_taken}": pct.call(Bal.v("lamp/dark_taken", 1.05)), "{dark_enemy}": pct.call(Bal.v("lamp/dark_enemy", 1.1)),
		"{dark_spawn}": pct.call(Bal.v("enemy/spawn_dark_mult", 1.15)),
		"{lamp_hit_10}": Sq._num(Bal.v("lamp/hit_scale", 18.0) * 0.1), "{lamp_hit}": Sq._num(Bal.v("lamp/hit_base", 2.0)),
		"{beacon_need}": Sq._num(Bal.v("beacon/need", 2.5)), "{beacon_lamp}": Sq._num(Bal.v("beacon/lamp", 20.0)), "{beacon_block}": Sq._num(Bal.v("beacon/block_t", 30.0)),
		"{elite_chest}": pc100.call("relic/elite_drop_chance", 0.3),
		"{pack_p}": pc100.call("crate/pack_p", 0.9), "{pack_pct}": pc100.call("crate/pack_pct", 0.3), "{pack_below}": pc100.call("crate/pick_below", 0.9),
		"{crate_magnet}": pc100.call("crate/magnet_p", 0.1), "{crate_shield}": pc100.call("crate/shield_p", 0.1),
		"{cmd_stamina}": Sq._num(Bal.v("command/stamina_secs", 25.0)), "{cmd_min}": pc100.call("command/min_start", 0.3),
		"{cmd_revive}": Sq._num(Bal.v("command/revive_secs", 25.0)),
	}
	for k in vals:
		ln = ln.replace(k, vals[k])
	return ln
