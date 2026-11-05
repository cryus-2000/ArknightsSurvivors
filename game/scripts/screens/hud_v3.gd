extends RefCounted
## 界面 · 局内指挥台（docs/222 §18，11-05 用户定稿「指挥台定稿了，先这样做吧」；示意图 Claude outputs/hud_console_1105/r6）。
## 用户 11-05：「玩的时候视觉基本上能注意到的只有正下的区域」——把队长生命 / 灯火 / 终结技 / 冲刺、队友头像与血量、小队指令
## 收进正下方一台，左右对称、头像在屏幕正中；左上生命块、右下编队卡、底部「左键 瞄准 / SPACE 冲刺」提示条在 on() 时不画。
## 造型（终末地 × NieR 减法版）：不画底板，只垫一道底部渐变；常态黑白灰，青只表示「能按」（终结技满、冲刺格可用），
## 洋红只表示危险，金只给灯火；装饰只留一对直角刻度。闲时整台降到 ui/console_idle 不透明，有变化时提亮。
## 总开关 balance.json ui/hud_v3：1 = 指挥台（缺省），0 = 回到 HUD v2（编辑式四角）。
const UI = preload("res://scripts/ui.gd")
const Bal = preload("res://scripts/core/balance.gd")
const Game = preload("res://scripts/game.gd")
const PlayKeys = preload("res://scripts/core/play_keys.gd")
const Squad = preload("res://scripts/characters/squad.gd")
const LANTERN: Texture2D = preload("res://art/ui/hud/console_lantern.png")   # 马灯四档帧条（tools/probes/hud_hurricane_rows.py + pixelfx fire/hud-hurricane）
const LANT_FW := 56.0
const LANT_FH := 72.0
const LANT_N := 30
const LANT_FPS := 15.0
const LANT_PIVOT := Vector2(28, 66)

var g: Game
var h   # screens/hud.gd

const WHITE := Color(0.925, 0.933, 0.941)
const GREY := Color(0.588, 0.612, 0.643)
const DIM := Color(1, 1, 1, 0.18)
const MODE_EN := ["ESCORT", "ASSAULT", "DEPLOY", "FOCUS"]

# 提亮 / 闪一下用的状态
var _hp_last := -1.0
var _hit_t := -99.0
var _down_seen := {}
var _down_t := -99.0
var _dash_last := -1
var _dash_t := -99.0
var _mode_last := -1
var _mode_t := -99.0
var _active_t := -99.0
var _alpha := 1.0
var _top := 0.0   # 本帧整台上沿（界面坐标），开局提示等底部中央的字往上让


func _init(hud) -> void:
	h = hud
	g = hud.g


static func on() -> bool:
	return Bal.vi("ui/hud_v3", 1) > 0


func k() -> float:
	return 1.0 if g.touch.active else 1.25


## 整台占的高度（界面像素，从屏幕底边量）：开局提示、终结技就绪提示等底部中央的东西按它往上让
func lift(vs: Vector2) -> float:
	return vs.y - _top if _top > 0.0 else 72.0 * k()


func _mates() -> Array:
	var ld = g.squad.leader()
	return g.squad.ops.filter(func(o): return o != ld)


func _mode() -> int:
	return h.v2.seg_index()


func _key(action: String) -> String:
	if g.touch.active:
		return ""
	return Pad.hint(PlayKeys.hint(action, true, false), PlayKeys.hint(action, true, true))


# ================================================================ 状态：闪一下 / 提亮

func _tick() -> void:
	if _hp_last >= 0.0 and g.hp < _hp_last - 0.01:
		_hit_t = g.t
	_hp_last = g.hp
	for o in _mates():
		var dn: bool = o.cmd_down > 0.0
		if dn and not _down_seen.get(o.id, false):
			_down_t = g.t
		_down_seen[o.id] = dn
	var dl: int = g.dash_left()
	if _dash_last >= 0 and dl < _dash_last:
		_dash_t = g.t
	_dash_last = dl
	var md: int = _mode()
	if _mode_last >= 0 and md != _mode_last:
		_mode_t = g.t
	_mode_last = md
	var hot: bool = g.hp < g.max_hp * 0.3 or g.lamp < 30.0 or (g.ult != null and g.ult.full()) \
		or _mates().any(func(o): return o.cmd_down > 0.0) or g.state != Game.S.PLAY
	var last: float = maxf(maxf(_hit_t, _down_t), maxf(_dash_t, _mode_t))
	if hot or g.t - last < Bal.v("ui/console_hold", 2.5):
		_active_t = g.t
	var want: float = 1.0 if g.t - _active_t < 0.05 else Bal.v("ui/console_idle", 0.45)
	_alpha = move_toward(_alpha, want, 0.05 if want < _alpha else 0.25)   # 变淡慢（约 1 秒）、提亮快


# ================================================================ 入口（hud._draw_body 在 on() 时调）

func draw(vs: Vector2) -> void:
	if g.state == Game.S.OPENING or g.state == Game.S.INTRO or g.state == Game.S.SHOW:
		return
	_tick()
	var L: Dictionary = h._layer_node("top_left")
	L.node.modulate.a = _alpha
	h._layer("top_left", null, func(): _console(vs))


# ================================================================ 指挥台

func _console(vs: Vector2) -> void:
	var s: float = k()
	var cx: float = vs.x / 2.0
	var base: float = vs.y - 14.0 * s
	var r: float = 25.0 * s
	var RR: float = r + 5.0 * s
	var by: float = base - r - 7.0 * s
	var md: int = _mode()
	# 右翼宽度先算（左翼按它对称）
	var sq: float = 34.0 * s
	var gap: float = 12.0 * s
	var tile: float = 26.0 * s
	var rush: String = _rush_text()
	var blockw: float = tile + 8.0 * s + maxf(h.v2.twidth(rush, int(round(7.2 * s))), 60.0 * s)
	var slots: int = maxi(maxi(1, g.squad.cap() - 1), _mates().size())   # 队友格数 = 编队上限 − 队长（常规 2 格，解锁第 4 位后 3 格）
	var right_ext: float = RR + 16.0 * s + slots * (sq + gap) + 2.0 * s + blockw
	var lw: float = maxf(128.0 * s, right_ext - (RR + 16.0 * s + 56.0 * s))
	var ext: float = maxf(right_ext, RR + 16.0 * s + lw + 56.0 * s)
	_top = base - 50.0 * s   # 先给个缺省，_left 按实际字高覆盖
	# 底部渐变：只托字，不是底板
	var gh: float = 66.0 * s
	var cols := PackedColorArray([Color(0.016, 0.024, 0.031, 0.0), Color(0.016, 0.024, 0.031, 0.0), Color(0.016, 0.024, 0.031, 0.62), Color(0.016, 0.024, 0.031, 0.62)])
	g.hud.draw_polygon(PackedVector2Array([Vector2(cx - ext - 60.0, vs.y - gh), Vector2(cx + ext + 60.0, vs.y - gh), Vector2(cx + ext + 60.0, vs.y), Vector2(cx - ext - 60.0, vs.y)]), cols)
	_leader(Vector2(cx, by), r, RR, base, s)
	_left(cx - RR - 16.0 * s, base, lw, s)
	_right(cx + RR + 16.0 * s, base, sq, gap, tile, rush, md, s, slots)
	# 一对直角刻度
	var tl := Vector2(cx - ext, _top)   # _left 按实际字高排完后更新 _top
	var br := Vector2(cx + ext, base + 8.0 * s)
	var tc := Color(1, 1, 1, 0.45)
	g.hud.draw_polyline(PackedVector2Array([tl + Vector2(0, 7.0 * s), tl, tl + Vector2(7.0 * s, 0)]), tc, 1.0)
	g.hud.draw_polyline(PackedVector2Array([br - Vector2(0, 7.0 * s), br, br - Vector2(7.0 * s, 0)]), tc, 1.0)


## 中：队长头像 + 终结技（外圈 40 格刻度 + 3 像素环）；头像下一行「Q 终结技 64%」，满了整环转青、外圈光环、「终结技 就绪」
func _leader(c: Vector2, r: float, RR: float, base: float, s: float) -> void:
	var ld = g.squad.leader()
	var has_ult: bool = g.ult != null
	var ek: float = clampf(g.ult.energy / 100.0, 0.0, 1.0) if has_ult else 0.0
	var full: bool = has_ult and g.ult.full()
	var pu: float = 0.5 if Cfg.reduce_motion else 0.5 + 0.5 * sin(g.t * 4.0)
	if full:
		g.hud.draw_circle(c, RR + 10.0 * s, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.10 + 0.12 * pu))
		g.hud.draw_arc(c, RR + 6.0 * s + 3.0 * pu, 0.0, TAU, 48, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.5), 1.0, true)
	g.hud.draw_circle(c, r + 1.0, Color(0, 0, 0, 0.62))
	if ld != null and h.ult != null and h.ult.v != null:
		h.ult.v._avatar_hi(ld, c, r)
	if has_ult:
		var n := 40
		for i in n:
			var a: float = -PI / 2.0 + TAU * i / n
			var lit: bool = i < int(round(n * ek))
			var r0: float = RR + 2.6 * s
			var r1: float = RR + (5.2 if i % 10 == 0 else 3.8) * s
			var col: Color = (UI.CYAN if full else WHITE) if lit else Color(1, 1, 1, 0.16)
			g.hud.draw_line(c + Vector2.from_angle(a) * r0, c + Vector2.from_angle(a) * r1, col, 1.0)
		g.hud.draw_arc(c, RR, 0.0, TAU, 56, Color(1, 1, 1, 0.2), 3.0, true)
		if ek > 0.0:
			g.hud.draw_arc(c, RR, -PI / 2.0, -PI / 2.0 + TAU * ek, 56, UI.CYAN if full else WHITE, 3.0, true)
		if not full:
			g.hud.draw_circle(c + Vector2.from_angle(-PI / 2.0 + TAU * ek) * RR, 2.6, WHITE)
		# 头像下：Q 键 + 终结技 + 百分比
		var ly: float = base + 9.0 * s
		var lab: String = ("就绪" if full else "%d%%" % int(ek * 100.0)) if g.touch.active else ("终结技 就绪" if full else "终结技 %d%%" % int(ek * 100.0))   # 触屏：「终结技」写在右手按键上，这里只写数
		var fs: int = int(round(8.5 * s))
		var tw: float = h.v2.twidth(lab, fs)
		var key: String = _key("ult")
		var kw: float = (UI.cwidth(g.font, key, int(round(6.5 * s))) + 8.0) if key != "" else 0.0
		var x0: float = c.x - (tw + kw + (4.0 if key != "" else 0.0)) / 2.0
		if key != "":
			var kr := Rect2(x0, ly - 9.0 * s, kw, 10.0 * s)
			g.hud.draw_rect(kr, UI.CYAN if full else Color(0, 0, 0, 0.5))
			g.hud.draw_rect(kr, UI.CYAN if full else Color(1, 1, 1, 0.55), false, 1.0)
			UI.text(g.hud, g.font, Vector2(kr.position.x, ly - 1.0 * s), key, int(round(6.5 * s)), Color(0.04, 0.06, 0.07) if full else WHITE, HORIZONTAL_ALIGNMENT_CENTER, kw)
			x0 += kw + 4.0
		h.v2.txt(Vector2(x0, ly), lab, fs, UI.CYAN if full else Color(WHITE.r, WHITE.g, WHITE.b, 0.88))
	# 等级：头像顶上一枚小牌（同 B′ 徽记的等级牌，缩小）
	var lf: float = g.hud_lv_flash
	var lvs: String = "LV %d" % g.level
	var lfs: int = int(round(7.0 * s))
	var lw: float = UI.cwidth(g.font, lvs, lfs) + 10.0
	var lr := Rect2(c.x - lw / 2.0, c.y - RR - 10.0 * s, lw, lfs + 5.0)
	g.hud.draw_rect(lr, Color(0.02, 0.03, 0.05, 0.9))
	g.hud.draw_rect(lr, Color(1, 1, 1, 0.35).lerp(UI.GOLD, lf), false, 1.0)
	UI.ctext(g.hud, g.font, Vector2(lr.position.x, lr.end.y - 3.0), lvs, lfs, WHITE.lerp(UI.GOLD, lf), HORIZONTAL_ALIGNMENT_CENTER, lw)


## 左：马灯 + 状态行 + 生命（大数字、细线）+ 灯火一行（「灯火」标签 · 带深色底槽的粗条 · 金色数字，30 / 70 刻度）+ 冲刺行。gx = 左翼右端
## 11-06 用户「灯火条不够清楚，被生命值的界面挡住了」：原来灯火只有一道 3 像素细线紧贴生命线、数字挤在冲刺行左边。
## 现在从底往上按实际字高排（手机字号有下限，字比 s 算的高）：冲刺行 → 灯火行 → 生命细线 → 生命数字 → 状态行，行间都留空隙
func _left(gx: float, base: float, lw: float, s: float) -> void:
	var hit: bool = g.t - _hit_t < 0.4
	var low: bool = g.hp / g.max_hp < 0.3
	var hpc: Color = UI.RED if (hit or low) else WHITE
	var hs := Vector2(sin(g.t * 90.0), cos(g.t * 70.0)) * 3.0 * g.hp_shake / 0.35
	var x0: float = gx - lw
	var lab: int = int(round(7.5 * s))
	var lks: float = float(UI._ks(g.hud, lab))
	var dash_top: float = base + 9.0 * s - 0.85 * float(UI._ks(g.hud, int(round(8.5 * s))))   # 冲刺行（_dash_row 8.5 号字）的字顶
	var lrow: float = dash_top - 4.0 - lks * 0.5   # 灯火行中线
	var hy: float = lrow - lks * 0.5 - 5.0   # 生命细线
	var hb: float = hy - 6.0 * s   # 生命数字 / 「生命」底线
	var sw: float = h.v2.big(Vector2(gx, hb) + hs, "/ %d" % int(g.max_hp), 7.5 * s, GREY, 2)
	h.v2.big(Vector2(gx - sw - 3.0, hb) + hs, "%d" % int(g.hp), 20.0 * s, hpc, 2)
	h.v2.txt(Vector2(x0, hb), "生命", lab, GREY)
	var dx: float = x0 + h.v2.twidth("生命", lab) + 8.0
	# 护盾：「生命」后一排小菱形
	for q in g.shield_max:
		UI.diamond(g.hud, Vector2(dx + q * 9.0, hb - 4.0), 3.0, Color(0.5, 0.85, 1.0) if q < g.shield else Color(1, 1, 1, 0.14), Color(0.6, 0.9, 1.0, 0.8))
	var sy: float = minf(hb - 19.0 * s, hb - lks - 6.0)   # 状态行底线：在大数字之上
	_status_line(Vector2(x0, sy), lw)
	_top = sy - 0.85 * float(UI._ks(g.hud, int(round(8.0 * k())))) - 4.0   # 整台上沿（lift 用）
	# 生命细线（从右往左长：靠头像那端是满的）
	var f: float = clampf(g.hp / g.max_hp, 0.0, 1.0)
	var tr: float = clampf(g.hp_trail / g.max_hp, 0.0, 1.0)
	g.hud.draw_rect(Rect2(x0, hy, lw, 1.6), DIM)
	if tr > f:
		g.hud.draw_rect(Rect2(gx - lw * tr, hy - 0.8, lw * (tr - f), 3.2), Color(UI.RED.r, UI.RED.g, UI.RED.b, 0.6))
	g.hud.draw_rect(Rect2(gx - lw * f, hy - 0.8, lw * f, 3.2), hpc)
	if hit and not Cfg.reduce_motion:
		g.hud.draw_rect(Rect2(gx - lw * f - 2.0, hy - 3.0, lw * f + 4.0, 7.6), Color(UI.RED.r, UI.RED.g, UI.RED.b, 0.25 * (1.0 - (g.t - _hit_t) / 0.4)))
	h.corrode_seg(Rect2(Vector2(gx - lw * f, hy - 0.8), Vector2(lw * f, 3.2)), 1.0)
	# 灯火一行：标签（左）· 粗条（中，深色底槽 + 金色填充，同生命从右往左长）· 数字（右，金色）
	var lamp_low: bool = g.lamp < 30.0
	var lc: Color = UI.GOLD if not lamp_low else UI.RED.lerp(UI.GOLD, 0.5 + 0.5 * sin(g.t * 8.0))
	var lf: float = clampf(g.lamp / 100.0, 0.0, 1.0)
	var lt: float = lrow + lks * 0.36   # 字的底线（字身居中在 lrow）
	h.v2.txt(Vector2(x0, lt), "灯火", lab, Color(1.0, 0.86, 0.6).lerp(lc, 0.5))
	var nw: float = h.v2.big(Vector2(gx, lt), "%d" % int(g.lamp), maxf(10.0 * s, lks), lc, 2)
	var bx0: float = x0 + h.v2.twidth("灯火", lab) + 6.0
	var bx1: float = gx - nw - 6.0
	var bw: float = maxf(8.0, bx1 - bx0)
	var bh: float = maxf(4.0, 4.0 * s)
	var br := Rect2(bx0, lrow - bh / 2.0, bw, bh)
	g.hud.draw_rect(br.grow(1.0), Color(0.0, 0.0, 0.0, 0.55))
	g.hud.draw_rect(br, Color(1.0, 0.8, 0.5, 0.14))
	g.hud.draw_rect(Rect2(br.end.x - bw * lf, br.position.y, bw * lf, bh), lc)
	for t in [0.3, 0.7]:
		var tx: float = br.end.x - bw * t
		g.hud.draw_rect(Rect2(tx - 0.5, br.position.y - 2.0, 1.0, bh + 4.0), Color(1, 1, 1, 0.55) if lf < t else Color(0, 0, 0, 0.6))
	# 冲刺：和头像下「Q 终结技」同一条底线
	_dash_row(gx, base + 9.0 * s, s)
	# 马灯：左翼最外侧，底座落在底线上
	_lantern(Vector2(x0 - 30.0 * s, base + 4.0 * s), s)


## 状态行：灯火档 + 状态效果，一行灰字，放不下收成「+N」
func _status_line(p: Vector2, w: float) -> void:
	var items: Array = [h.v2.lamp_item()] + h.bars.status_items()
	var fs: int = int(round(8.0 * k()))
	var x: float = p.x
	for i in items.size():
		var it: Array = items[i]
		var t: String = it[0]
		var tw: float = h.v2.twidth(t, fs)
		if (x + tw > p.x + w - 4.0 or (g.touch.active and Cfg.phone_ui())) and i > 0:   # 手机只留第一项（字号有下限，放不下两项）
			h.v2.txt(Vector2(x, p.y), "+%d" % (items.size() - i), fs, GREY)
			break
		h.v2.txt(Vector2(x, p.y), t, fs, (it[1] as Color).lerp(GREY, 0.45))
		x += tw
		if i < items.size() - 1:
			h.v2.txt(Vector2(x + 3.0, p.y), "/", fs, Color(1, 1, 1, 0.3))
			x += 12.0


func _dash_row(xr: float, ly: float, s: float) -> void:
	var n: int = g.dash_left()
	var mx: int = g.dash_max()
	var fs: int = int(round(8.5 * s))
	var tw: float = h.v2.twidth("冲刺", fs)
	h.v2.txt(Vector2(xr - tw, ly), "冲刺", fs, Color(WHITE.r, WHITE.g, WHITE.b, 0.88) if n > 0 else GREY)
	var x: float = xr - tw - 6.0 * s
	var cw: float = 7.0 * s
	var chh: float = 9.0 * s
	var cy: float = ly - 4.0 * s
	var nxt: float = g.dash_frac()
	for j in range(mx - 1, -1, -1):   # 从右往左：右边那格先用掉
		var x0: float = x - cw
		var pts := PackedVector2Array([Vector2(x0, cy - chh / 2.0), Vector2(x0 + cw * 0.45, cy - chh / 2.0), Vector2(x0 + cw, cy),
			Vector2(x0 + cw * 0.45, cy + chh / 2.0), Vector2(x0, cy + chh / 2.0), Vector2(x0 + cw * 0.55, cy)])
		if j < n:
			g.hud.draw_colored_polygon(pts, UI.CYAN)
		else:
			g.hud.draw_colored_polygon(pts, Color(1, 1, 1, 0.15))
			if j == n and nxt < 1.0:   # 正在充能的那格：底下一截青色回填
				var fh: float = chh * nxt
				g.hud.draw_rect(Rect2(x0 + cw * 0.15, cy + chh / 2.0 - fh, cw * 0.55, fh), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.55))
		x = x0 - 2.5 * s
	if g.t - _dash_t < 0.3 and not Cfg.reduce_motion:
		var a: float = 1.0 - (g.t - _dash_t) / 0.3
		g.hud.draw_rect(Rect2(x - 2.0, cy - chh / 2.0 - 2.0, xr - tw - 6.0 * s - x + 4.0, chh + 4.0), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.25 * a))
	var key: String = Pad.hint("SPACE", "Ⓑ", "") if not g.touch.active else ""
	if key != "":
		var ks: int = int(round(5.6 * s))
		var kw: float = UI.cwidth(g.font, key, ks) + 8.0
		var kr := Rect2(x - 3.0 * s - kw, ly - 9.0 * s, kw, 10.0 * s)
		g.hud.draw_rect(kr, Color(0, 0, 0, 0.5))
		g.hud.draw_rect(kr, Color(1, 1, 1, 0.6), false, 1.0)
		UI.text(g.hud, g.font, Vector2(kr.position.x, ly - 1.0 * s), key, ks, WHITE, HORIZONTAL_ALIGNMENT_CENTER, kw)


## 马灯：四档帧条（通明 ≥ 70 / 摇曳 30–70 / 暗淡 < 30 / 寂灭 0），15 帧 / 秒循环；按整数倍像素画（桌面 4/3 逻辑像素 = 1080p 上 2 倍）
func _lantern(p: Vector2, s: float) -> void:
	var row: int = 0 if g.lamp >= 70.0 else (1 if g.lamp >= 30.0 else (2 if g.lamp > 0.0 else 3))
	var fi: int = 0 if Cfg.reduce_motion else int(g.t * LANT_FPS) % LANT_N
	var sc: float = 4.0 / 3.0 if not g.touch.active else 1.0
	var src := Rect2(fi * LANT_FW, row * LANT_FH, LANT_FW, LANT_FH)
	var dst := Rect2(p - LANT_PIVOT * sc, Vector2(LANT_FW, LANT_FH) * sc)
	g.hud.draw_texture_rect_region(LANTERN, dst, src)


## 右：队友头像（同一套头部取景，大小一致）+ 血量细线；倒地灰掉 + 洋红线 + 读秒。然后是小队指令牌
func _right(qx: float, base: float, sq: float, gap: float, tile: float, rush: String, md: int, s: float, slots: int) -> void:
	var ms: Array = _mates()
	for i in ms.size():
		var o = ms[i]
		var x: float = qx + i * (sq + gap)
		var y: float = base - sq - 5.0 * s
		var down: bool = o.cmd_down > 0.0
		g.hud.draw_rect(Rect2(x, y, sq, sq), Color(0, 0, 0, 0.5))
		var hd: Array = h.ult.v._hi_head(o) if h.ult != null and h.ult.v != null else []
		if not hd.is_empty():
			g.hud.draw_texture_rect_region(hd[0], Rect2(x, y, sq, sq), hd[1], Color(0.45, 0.45, 0.5, 0.75) if down else Color.WHITE)
		g.hud.draw_rect(Rect2(x, y, sq, sq), Color(1, 1, 1, 0.2), false, 1.0)
		var hp: float = clampf(o.cmd_hp, 0.0, 1.0)
		var low: bool = hp < 0.35 and not down
		g.hud.draw_rect(Rect2(x, base - 1.5 * s, sq, 1.6), DIM)
		if not down:
			g.hud.draw_rect(Rect2(x, base - 1.5 * s - 0.8, sq * hp, 3.2), UI.RED if low else WHITE)
		else:
			var kk: float = 1.0 - clampf(o.cmd_down / maxf(0.1, Bal.v("command/revive_secs", 25.0)), 0.0, 1.0)
			g.hud.draw_rect(Rect2(x, base - 1.5 * s - 0.8, sq * kk, 3.2), Color(0.55, 0.57, 0.6))
			g.hud.draw_rect(Rect2(x, y, sq, 1.6), UI.RED)
			var pk: float = 0.5 + 0.5 * sin(g.t * 6.0)
			g.hud.draw_rect(Rect2(x - 1, y - 1, sq + 2, sq + 2), Color(UI.RED.r, UI.RED.g, UI.RED.b, 0.35 + 0.35 * pk), false, 1.5)
			h.v2.big(Vector2(x + sq / 2.0, y + sq / 2.0 + 4.0 * s), "%02d" % int(ceil(o.cmd_down)), 10.0 * s, UI.GOLD if h.allyhp.boosted(o) else UI.RED, 1)
	for i in range(ms.size(), slots):   # 已解锁但还没人的格：淡框占位
		var x: float = qx + i * (sq + gap)
		var y: float = base - sq - 5.0 * s
		g.hud.draw_rect(Rect2(x, y, sq, sq), Color(1, 1, 1, 0.1), false, 1.0)
		g.hud.draw_line(Vector2(x + sq * 0.4, y + sq * 0.5), Vector2(x + sq * 0.6, y + sq * 0.5), Color(1, 1, 1, 0.18), 1.0)
	var mx: float = qx + maxi(slots, ms.size()) * (sq + gap) + 2.0 * s
	_cmd_block(mx, base, tile, rush, md, s)


func _rush_text() -> String:
	var t: String = g.squad.rush_text()
	if t == "":
		t = "攻速 +%d%% · 技力回复 ×%s" % [roundi(Bal.v("command/rush_aspd", 0.25) * 100.0), str(Bal.v("command/rush_sp", 1.5))]
	return t


## 小队指令牌：图标牌（出击类指令外框是作战时限）+ 指令名 / 英文 + 第二行（随行「队友不受伤」，出击类共用出击加成）
## + 四种指令小图标（当前那个亮）+ 指令键；集火时牌子上方一行目标与剩余生命
func _cmd_block(x: float, base: float, tile: float, rush: String, md: int, s: float) -> void:
	var sqd = g.squad
	if not Squad.cmd_on():
		return
	var ty: float = base - tile - 2.0 * s
	g.hud.draw_rect(Rect2(x, ty, tile, tile), Color(0, 0, 0, 0.5))
	g.hud.draw_rect(Rect2(x, ty, tile, tile), Color(1, 1, 1, 0.24), false, 1.0)
	if md > 0 and Squad.stamina_on():
		_perimeter(Rect2(x, ty, tile, tile), clampf(sqd.stamina, 0.0, 1.0), WHITE, 1.6)
		h.v2.cap(Vector2(x + tile, ty + tile + 8.5 * s), "%ds" % int(round(sqd.stamina * Bal.v("command/stamina_secs", 25.0))), 4.6 * s, GREY, 1.0, 2)
	_icon(Vector2(x + tile / 2.0, ty + tile / 2.0), md, tile * 0.36, WHITE, 1.4)
	var tx: float = x + tile + 8.0 * s
	var nw: float = h.v2.twidth(h.v2.SEG_NAMES[md], int(round(12.0 * s)))
	h.v2.txt(Vector2(tx, ty + (10.0 if not (g.touch.active and Cfg.phone_ui()) else 18.0) * s), h.v2.SEG_NAMES[md], int(round(12.0 * s)), WHITE)
	h.v2.cap(Vector2(tx + nw + 5.0 * s, ty + 9.5 * s), MODE_EN[md], 4.6 * s, GREY, 1.4)
	var ph: bool = g.touch.active and Cfg.phone_ui()   # 手机字号有下限（docs/37）：只留指令名与作战时限，加成行和四个小图标不画
	if not ph:
		h.v2.txt(Vector2(tx, ty + 20.0 * s), rush if md > 0 else "队友不受伤", int(round(7.2 * s)), GREY)
	for j in (0 if ph else 4):
		_icon(Vector2(tx + 4.0 * s + j * 13.0 * s, base + 1.0 * s), j, 4.2 * s, WHITE if j == md else Color(1, 1, 1, 0.3), 1.0)
	var key: String = _key("command")
	if key != "":
		h.v2.cap(Vector2(tx + 4.0 * s + 4.0 * 13.0 * s + 2.0 * s, base + 3.0 * s), key, 5.0 * s, GREY, 1.2)
	if md == 3 and sqd.order_target != null and not sqd.order_target.dead:
		var e = sqd.order_target
		var nm: String = str(e.get("name")) if e.get("name") != null and str(e.get("name")) != "" else ("Boss" if e.boss else "精英")
		var hpk: float = clampf(e.hp / maxf(1.0, e.maxhp), 0.0, 1.0)
		var yy: float = ty - 6.0 * s
		var fs: int = int(round(7.6 * s))
		var w0: float = h.v2.twidth("目标 · " + nm, fs)
		h.v2.txt(Vector2(x, yy), "目标 · " + nm, fs, WHITE)
		h.v2.big(Vector2(x + w0 + 4.0 * s, yy), "%d%%" % int(round(hpk * 100.0)), 7.6 * s, UI.RED)
		var bw: float = w0 + 26.0 * s
		g.hud.draw_rect(Rect2(x, yy + 2.2 * s, bw, 1.2), DIM)
		g.hud.draw_rect(Rect2(x, yy + 2.2 * s, bw * hpk, 1.2), UI.RED)


## 沿方框顺时针走的一道亮边（frac = 剩余比例），用掉的那段只留暗边
func _perimeter(r: Rect2, frac: float, col: Color, w: float) -> void:
	var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
	var left: float = 4.0 * r.size.x * frac
	var acc := 0.0
	for i in 4:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var seg: float = a.distance_to(b)
		if left <= acc:
			break
		var t: float = minf(1.0, (left - acc) / seg)
		g.hud.draw_line(a, a.lerp(b, t), col, w)
		acc += seg


## 四种指令的线性小图标：随行 = 队长点 + 三名队友围成弧；突击 = 双箭头；部署 = 落点菱形 + 地面线；集火 = 准星
func _icon(c: Vector2, i: int, r: float, col: Color, w: float) -> void:
	match i:
		0:
			g.hud.draw_circle(c + Vector2(0, r * 0.25), r * 0.22, col)
			for a in [-150.0, -90.0, -30.0]:
				g.hud.draw_circle(c + Vector2(0, r * 0.25) + Vector2.from_angle(deg_to_rad(a)) * r * 0.75, r * 0.16, col)
		1:
			for dx in [-0.35, 0.2]:
				g.hud.draw_polyline(PackedVector2Array([c + Vector2((dx - 0.25) * r, -0.55 * r), c + Vector2((dx + 0.25) * r, 0), c + Vector2((dx - 0.25) * r, 0.55 * r)]), col, w * 1.3)
		2:
			g.hud.draw_polyline(PackedVector2Array([c + Vector2(0, -0.75 * r), c + Vector2(0.45 * r, -0.2 * r), c + Vector2(0, 0.35 * r), c + Vector2(-0.45 * r, -0.2 * r), c + Vector2(0, -0.75 * r)]), col, w)
			g.hud.draw_line(c + Vector2(-0.7 * r, 0.7 * r), c + Vector2(0.7 * r, 0.7 * r), col, w)
		_:
			g.hud.draw_arc(c, r * 0.55, 0.0, TAU, 20, col, w, true)
			for a in 4:
				var d := Vector2.from_angle(a * PI / 2.0)
				g.hud.draw_line(c + d * r * 0.35, c + d * r * 0.9, col, w)
			g.hud.draw_circle(c, r * 0.1, col)


## 点击判定（hud.blocks_click）：整台的外框
func rect(vs: Vector2) -> Rect2:
	var t: float = _top if _top > 0.0 else vs.y - 72.0 * k()
	return Rect2(0.0, t - 12.0, vs.x, vs.y - t + 12.0).grow_individual(-vs.x * 0.2, 0, -vs.x * 0.2, 0)
