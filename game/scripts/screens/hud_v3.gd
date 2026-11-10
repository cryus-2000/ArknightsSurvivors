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
const M3 = preload("res://scripts/characters/blocks/m3_hp.gd")   # Mon3tr 小牌（docs/298）
const LANTERN: Texture2D = preload("res://art/ui/hud/console_lantern.png")   # 马灯四档帧条（tools/probes/hud_hurricane_rows.py + pixelfx fire/hud-hurricane）
const LANT_FW := 56.0
const LANT_FH := 72.0
const LANT_N := 30
const LANT_FPS := 15.0
const LANT_PIVOT := Vector2(28, 66)

var g: Game
## The HUD owns its sections; the return link must not retain it after a run.
var _owner_ref: WeakRef
var h:
	get:
		return _owner_ref.get_ref() if _owner_ref != null else null
	set(value):
		_owner_ref = weakref(value) if value != null else null

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
	for a in Cfg.dev_args():
		if a.begins_with("--hoverop="):
			_hover_op = int(a.substr(10))


static func on() -> bool:
	return Bal.vi("ui/hud_v3", 1) > 0


## 技能细格（docs/290，用户 11-06 定 A 常驻、队长那行放等级旁）：头像下一个技能一段。2 = 队长细格在等级牌右边（缺省，不抬高）；
## 1 = 队长细格在终结技环下方（环整体上抬一行，备选）；0 = 不画。队友都画在头像血量线下方
static func skills_mode() -> int:
	return Bal.vi("ui/console_skills", 2)


## 悬停提示（桌面）：鼠标停在队长头像 / 队友头像上，浮出三招的名字与状态。本帧各头像的区域：[矩形, 干员]
var _hov: Array = []
var _hover_op := -1


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
	if g.touch.active:   # 手机字号有下限：最下一行（「终结技 64%」「冲刺」）按实际字高留底，不被屏幕下沿裁掉
		base -= maxf(0.0, 0.3 * float(UI._ks(g.hud, int(round(8.5 * s)))) - 2.0)
	var r: float = 25.0 * s
	var RR: float = r + 5.0 * s
	var by: float = base - r - 7.0 * s - _ring_lift(s)   # 布局一：环上抬一行，给环下的技能细格让位
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
	_hov = []
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
	_hover_tip(vs, s)


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
	if ld != null:
		_hov.append([Rect2(c - Vector2(RR, RR + 10.0 * s), Vector2(RR * 2.0, RR * 2.0 + 10.0 * s)), ld])
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
	if skills_mode() == 1 and ld != null:   # 布局一：环与「终结技 64%」之间一行
		var w1: float = 2.0 * r * 0.9
		var hh1: float = maxf(2.0, 2.4 * s)
		var y1: float = _ult_label_top(base, s) - 2.0 - hh1   # 贴着「终结技 64%」字顶往上（手机字号有下限，字比 s 算的高）
		var act1: Array = _skill_segs(ld, c.x - w1 / 2.0, y1, w1, hh1, s)
		_skill_secs(act1, Vector2(c.x + w1 / 2.0 + 4.0 * s, y1 + hh1 + 3.0 * s), s)
	# 等级：头像顶上一枚小牌（同 B′ 徽记的等级牌，缩小）
	var lf: float = g.hud_lv_flash
	var lvs: String = "LV %d" % g.level
	var lfs: int = int(round(7.0 * s))
	var lw: float = UI.cwidth(g.font, lvs, lfs) + 10.0
	var lr := Rect2(c.x - lw / 2.0, c.y - RR - 10.0 * s, lw, lfs + 5.0)
	g.hud.draw_rect(lr, Color(0.02, 0.03, 0.05, 0.9))
	g.hud.draw_rect(lr, Color(1, 1, 1, 0.35).lerp(UI.GOLD, lf), false, 1.0)
	UI.ctext(g.hud, g.font, Vector2(lr.position.x, lr.end.y - 3.0), lvs, lfs, WHITE.lerp(UI.GOLD, lf), HORIZONTAL_ALIGNMENT_CENTER, lw)
	if skills_mode() == 2 and ld != null:   # 布局二：等级牌右边一行，不抬高
		var w2: float = 30.0 * s
		var hh2: float = maxf(2.0, 2.4 * s)
		var act2: Array = _skill_segs(ld, lr.end.x + 4.0 * s, lr.get_center().y - hh2 / 2.0, w2, hh2, s)
		_skill_secs(act2, Vector2(lr.end.x + 4.0 * s + w2 + 4.0 * s, lr.get_center().y + 3.0 * s), s)
	if ld != null:   # 凯尔希当队长：Mon3tr 小牌挂在环外——桌面左下（150°，环下「终结技 64%」一行较宽）；触屏右下（30°，环下只写「64%」，左边紧挨灯火数字）
		_m3_badge(ld, c + Vector2.from_angle(PI / 6.0 if g.touch.active else PI * 5.0 / 6.0) * (RR + 11.0 * s), 18.0 * s, s)


## 头像下「终结技 64%」一行的字顶 y
func _ult_label_top(base: float, s: float) -> float:
	return base + 9.0 * s - 0.85 * float(UI._ks(g.hud, int(round(8.5 * s))))


## 布局一环上抬多少：细格一行 + 上下空隙，按实际字高算（手机字号有下限时多抬一点）
func _ring_lift(s: float) -> float:
	if skills_mode() != 1:
		return 0.0
	var ring_bottom: float = 3.2 * s   # 原来环外圈刻度底（相对 base）：base - r - 7s + RR + 5.2s
	var need: float = maxf(2.0, 2.4 * s) + 4.0   # 细格 + 上下各 2
	return maxf(0.0, ring_bottom + need - (_ult_label_top(0.0, s)))


## 一名干员的三段技能细格（x, y 左上，w 三段总宽）：没解锁 = 空框；充能中 = 灰色随技力填满；生效中 = 白色，剩余时长从满往下退；
## 永久型生效后整段白；充满待放（自动技能等敌人进范围时会停在这里）= 亮青。返回生效中各段 [矩形, 剩余秒]
func _skill_segs(o, x: float, y: float, w: float, hh: float, s: float) -> Array:
	var items: Array = o.skill_hud()
	var gp: float = maxf(2.0, 2.0 * s)
	var sw: float = (w - gp * 2.0) / 3.0
	var act: Array = []
	for k in 3:
		var it: Array = items[k]
		var r := Rect2(x + k * (sw + gp), y, sw, hh)
		var left: float = it[3]
		var frac: float = clampf(it[5], 0.0, 1.0)
		g.hud.draw_rect(r.grow(1.0), Color(0, 0, 0, 0.45))
		if not it[2]:
			g.hud.draw_rect(Rect2(r.position + Vector2(0.5, 0.5), r.size - Vector2(1, 1)), Color(1, 1, 1, 0.3), false, 1.0)
		elif o.perm[k] or left > 0.0:
			var f: float = 1.0 if o.perm[k] else clampf(left / maxf(0.01, float(it[4])), 0.0, 1.0)
			g.hud.draw_rect(r, Color(1, 1, 1, 0.16))
			g.hud.draw_rect(Rect2(r.position, Vector2(sw * f, hh)), WHITE)
			if left > 0.0 and not o.perm[k]:
				act.append([r, left])
		elif frac >= 1.0:
			g.hud.draw_rect(r, UI.CYAN)
		else:
			g.hud.draw_rect(r, Color(1, 1, 1, 0.12))
			g.hud.draw_rect(Rect2(r.position, Vector2(sw * frac, hh)), GREY)
	return act


## 悬停提示：头像正上方一块小牌，一招一行「名字 · 状态」。状态：就绪 / 生效中 剩余秒 / 充能中 约 N 秒 / 精英一（二）解锁。
## 充能秒数按当前自然充能速度估（命中回技力的招会更快），所以写「约」
func _hover_tip(vs: Vector2, s: float) -> void:
	if g.touch.active or g.state != Game.S.PLAY:
		return
	var mp: Vector2 = g.hud.get_local_mouse_position()
	if _hover_op >= 0 and _hover_op < _hov.size():
		mp = (_hov[_hover_op][0] as Rect2).get_center()   # 截图：--hoverop=N 当作鼠标停在第 N 个头像上（0 = 队长）
	for hv in _hov:
		var hr: Rect2 = hv[0]
		if not hr.has_point(mp):
			continue
		_active_t = g.t   # 看提示时整台保持全亮
		skill_tip(hv[1], hr.get_center().x, _top - 8.0 * s, vs, s)
		return


## 一名干员三招的提示牌（指挥台悬停与 Tab 编队栏共用）：底边在 bottom_y、水平居中在 cx（夹进屏幕）
func skill_tip(o, cx: float, bottom_y: float, vs: Vector2, s: float) -> void:
	var items: Array = o.skill_hud()
	var fs: int = int(round(8.0 * s))
	var lines: Array = []
	var tw := 0.0
	for k in 3:
		var it: Array = items[k]
		var st: String
		var col: Color = GREY
		if not it[2]:
			st = ["招募", "精英一", "精英二"][k] + "解锁"
		elif o.perm[k]:
			st = "永久生效"
			col = WHITE
		elif float(it[3]) > 0.0:
			st = "生效中 %d 秒" % int(ceil(float(it[3])))
			col = WHITE
		elif float(it[5]) >= 1.0:
			st = "就绪"
			col = UI.CYAN
		else:
			var need: float = o.sp_need(k)
			var rate: float = g.sp_mult * o.stat(&"op_skill_sp") * o.lamp_sp()
			st = ("充能中 约 %d 秒" % int(ceil((need - float(o.sp[k])) / rate))) if rate > 0.001 else "充能暂停"
		var nm: String = str(o.skill_def(k).get("name", "技能 %d" % (k + 1)))
		lines.append([nm, st, col])
		tw = maxf(tw, h.v2.twidth(nm, fs) + 14.0 * s + h.v2.twidth(st, fs))
	var lh: float = float(UI._ks(g.hud, fs)) + 5.0
	var pad: float = 7.0 * s
	var tsz := Vector2(tw + pad * 2.0, lh * 3.0 + pad * 2.0 - 4.0)
	var tp := Vector2(clampf(cx - tsz.x / 2.0, 8.0, vs.x - tsz.x - 8.0), maxf(8.0, bottom_y - tsz.y))
	g.hud.draw_rect(Rect2(tp, tsz), Color(0.016, 0.024, 0.031, 0.88))
	g.hud.draw_rect(Rect2(tp, tsz), Color(1, 1, 1, 0.22), false, 1.0)
	g.hud.draw_rect(Rect2(tp, Vector2(14.0 * s, 1.6)), WHITE)
	for i in 3:
		var ln: Array = lines[i]
		var ly: float = tp.y + pad + lh * (i + 1) - 5.0
		h.v2.txt(Vector2(tp.x + pad, ly), ln[0], fs, Color(WHITE.r, WHITE.g, WHITE.b, 0.9) if items[i][2] else GREY)
		h.v2.txt(Vector2(tp.x + tsz.x - pad - h.v2.twidth(ln[1], fs), ly), ln[1], fs, ln[2])


## 队长细格的剩余秒数：写在细格行右边，几段同时生效就按顺序排（一般只有一段）
func _skill_secs(act: Array, p: Vector2, s: float) -> void:
	var x: float = p.x
	for a in act:
		x += h.v2.big(Vector2(x, p.y), "%d" % int(ceil(a[1])), maxf(7.0, 7.0 * s), WHITE) + 4.0 * s


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
			if j == n and nxt < 1.0:
				if dash_trace():   # 沿图标轮廓走一圈（docs/290，用户 11-06「沿着图标加载而不是笔直往上」）：同终结技环，从正上方起、顺时针
					_trace(pts, nxt, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.9), maxf(1.0, 1.2 * s))
				else:   # 正在充能的那格：底下一截青色回填
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


## 冲刺格充能画法（docs/290，用户 11-06 定）：1 = 沿图标轮廓走一圈（缺省）；0 = 原来的竖直回填
static func dash_trace() -> bool:
	return Bal.vi("ui/console_dash_trace", 1) > 0


## 沿闭合多边形轮廓画一道亮边（frac = 已走比例）。起点是第一条边（图标上沿）的中点，按 pts 顺序走（冲刺图标的点序在屏幕上是顺时针）
func _trace(pts: PackedVector2Array, frac: float, col: Color, w: float) -> void:
	var ring: Array = [(pts[0] + pts[1]) / 2.0]
	for i in range(1, pts.size()):
		ring.append(pts[i])
	ring.append(pts[0])
	ring.append(ring[0])
	var total := 0.0
	for i in ring.size() - 1:
		total += (ring[i] as Vector2).distance_to(ring[i + 1])
	var left: float = total * clampf(frac, 0.0, 1.0)
	var line := PackedVector2Array([ring[0]])
	for i in ring.size() - 1:
		var a: Vector2 = ring[i]
		var b: Vector2 = ring[i + 1]
		var seg: float = a.distance_to(b)
		if left <= seg:
			line.append(a.lerp(b, left / maxf(0.001, seg)))
			break
		line.append(b)
		left -= seg
	if line.size() >= 2:
		g.hud.draw_polyline(line, col, w)


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
		_hov.append([Rect2(x, y, sq, base + 12.0 * s - y), o])
		g.hud.draw_rect(Rect2(x, y, sq, sq), Color(0, 0, 0, 0.5))
		var hd: Array = h.ult.v._hi_head(o) if h.ult != null and h.ult.v != null else []
		if not hd.is_empty():
			g.hud.draw_texture_rect_region(hd[0], Rect2(x, y, sq, sq), hd[1], Color(0.45, 0.45, 0.5, 0.75) if down else Color.WHITE)
		g.hud.draw_rect(Rect2(x, y, sq, sq), Color(1, 1, 1, 0.2), false, 1.0)
		var hp: float = clampf(o.cmd_hp, 0.0, 1.0)
		var low: bool = hp < 0.35 and not down
		if skills_mode() > 0:   # 技能细格：血量线下方一行；生效中的段下面写剩余秒数
			for a in _skill_segs(o, x, base + 2.0 * s, sq, maxf(2.0, 2.4 * s), s):
				var ar: Rect2 = a[0]
				h.v2.big(Vector2(ar.get_center().x, ar.end.y + maxf(8.0, 7.5 * s)), "%d" % int(ceil(a[1])), maxf(7.0, 6.5 * s), WHITE, 1)
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
		_m3_badge(o, Vector2(x + sq - 2.0 * s, y + 2.0 * s), 18.0 * s, s)   # 凯尔希当队友：Mon3tr 小牌压在头像格右上角
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
## Mon3tr 小牌（11-06 用户「凯尔希的 m3 死掉之后我觉得可以加一个复活的倒计时标志」，docs/298）：
## 活着 = 小头像 + 牌内底边血量细条（白，低于 35% 洋红）；倒下 = 头像变灰、洋红顶线 + 呼吸框、牌上红字复活秒数、底条走复活进度；
## 起身那一下青色闪 0.45 秒。只读召唤物状态（m3_hp.gd），不改玩法
var _m3_was := {}   # 召唤物 id → 上一帧是否倒下
var _m3_up := {}    # 召唤物 id → 起身时刻（g.t）
var _m3_tex: Texture2D = null
const M3_ICON_BOX := Rect2(39, 36, 49, 49)   # 1 倍帧（128 高）里 Mon3tr 身体的方框（op_mon3tr_native_idle 第 0 帧不透明区 40..87 × 37..85）


## Mon3tr 小头像贴图：有 @2x 用 @2x（桌面），网页包去掉了 @2x 回退就用 @1x
func _m3_icon() -> Texture2D:
	if _m3_tex == null:
		for pth in ["res://art/operators/kaltsit/op_mon3tr_native_idle@2x.png", "res://art/operators/kaltsit/op_mon3tr_native_idle@1x.png"]:
			if ResourceLoader.exists(pth):
				_m3_tex = load(pth)
				break
	return _m3_tex


func _m3_badge(o, c: Vector2, sz: float, s: float) -> void:
	var st = M3.present(o)
	if st == null:
		return
	var sid: int = int(st.get("id", 0))
	var down: bool = M3.is_down(st)
	if bool(_m3_was.get(sid, down)) and not down:
		_m3_up[sid] = g.t
	_m3_was[sid] = down
	var r := Rect2((c - Vector2(sz, sz) / 2.0).round(), Vector2(sz, sz).round())
	g.hud.draw_rect(r.grow(1.0), Color(0.016, 0.024, 0.031, 0.92))
	var ic: Texture2D = _m3_icon()
	if ic != null:   # 小头像：原生待机第 0 帧的身体框（11-07 用户「M3 的也做个头像小图标」）；身体偏黑，垫一层浅灰底
		g.hud.draw_rect(r, Color(0.24, 0.255, 0.29, 1.0) if not down else Color(0.12, 0.13, 0.15, 1.0))
		var kk: float = float(ic.get_height()) / 128.0
		g.hud.draw_texture_rect_region(ic, r, Rect2(M3_ICON_BOX.position * kk, M3_ICON_BOX.size * kk), Color(0.5, 0.5, 0.55, 0.75) if down else Color.WHITE)
	var f: float = clampf(float(st.hp) / maxf(1.0, float(st.max_hp)), 0.0, 1.0)
	var bh: float = maxf(1.6, 1.8 * s)
	var bar := Rect2(r.position.x, r.end.y - bh, r.size.x, bh)
	g.hud.draw_rect(bar, Color(0, 0, 0, 0.75))
	if down:
		var total: float = maxf(0.1, M3.k(o, "m3_revive_secs", 18.0))
		g.hud.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(1.0 - float(st.down) / total, 0.0, 1.0), bh)), Color(0.55, 0.57, 0.6))
		g.hud.draw_rect(Rect2(r.position, Vector2(r.size.x, 1.4)), UI.RED)
		var pk: float = 0.5 if Cfg.reduce_motion else 0.5 + 0.5 * sin(g.t * 6.0)
		g.hud.draw_rect(r.grow(1.0), Color(UI.RED.r, UI.RED.g, UI.RED.b, 0.35 + 0.35 * pk), false, 1.0)
		h.v2.big(r.get_center() + Vector2(0, 3.0 * s), "%d" % int(ceil(float(st.down))), maxf(9.0, 7.5 * s), UI.RED, 1)
	else:
		g.hud.draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bh)), UI.RED if f < 0.35 else WHITE)
		g.hud.draw_rect(r.grow(1.0), Color(1, 1, 1, 0.3), false, 1.0)
	var up: float = g.t - float(_m3_up.get(sid, -100.0))
	if up >= 0.0 and up < 0.45:
		var a: float = 1.0 - up / 0.45
		g.hud.draw_rect(r, Color(1, 1, 1, 0.35 * a))
		g.hud.draw_rect(r.grow(1.0 + 3.0 * (1.0 - a)), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, a), false, 1.5)


func rect(vs: Vector2) -> Rect2:
	var t: float = _top if _top > 0.0 else vs.y - 72.0 * k()
	return Rect2(0.0, t - 12.0, vs.x, vs.y - t + 12.0).grow_individual(-vs.x * 0.2, 0, -vs.x * 0.2, 0)
