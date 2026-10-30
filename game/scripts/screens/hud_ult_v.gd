extends RefCounted
## 界面 · 终结技 / 连携并进左上生命块的三个原型（10-30 用户「终结技和连携的 UI 能不能和血条之类的合并一下，出三个设计稿」）。
## 开关 balance.json ui/hud_ult_v：0 = 现行（底部中央长条 + 底部弹出队友头像，本文件不画）；1 / 2 / 3 = 下面三个方向，挑定后再精修。
##   1 A 血条下嵌：生命条正下方一道细能量条（队长代表色），灯火条下同位置是协同格；满了扫一道亮光 + 呼吸光、条尾「Q」小标；
##     连携 = 生命块右端一枚圆头像徽章 + 倒计时弧 + 「E」小标，后面排队的小头像跟在右边
##   2 B 环形头像：左上等级圆换成队长头像，外圈 = 终结技能量环（满了亮点绕环转 + 呼吸光），左上弧 = 协同格，等级挪到右上小牌；
##     连携 = 队友头像从环的右下边弹出、自带倒计时环，排队的再沿环往下排
##   3 C 分段刻度：生命条 / 灯火条各加一层下层——生命条下 = 终结技能量（4 段刻度），灯火条下 = 协同格；
##     连携 = 生命条上方一枚菱形头像（闪烁），菱形描边按剩余时间退
## 三个方向共用：桌面底部中央的终结技条与弹出头像不再画；「可以放了」不放角落，挂在队长身上——能量满时队长脚下亮一圈代表色光（_draw_ready）。
## 触屏（10-30 协调人与用户商定）：能量不并进血条，直接做成右下 Q 键本身的填充（从下往上涨），连携键只在亮起时出现。
## 上面写的连携徽章只在 ui/link_cue = 0 时画；link_cue 1–3 是连携提示的另一组原型（挂在场上两名干员之间，见下）：
##   1 A 灯火引线：队长与亮起的队友之间一条灯火色细引线（3 像素格），光点从队友流向队长；像导火索一样从队友端往队长端烧短 = 倒计时，
##     烧到头窗口关闭；按 E（队首提前离队）整线爆亮、化成火星散掉；减少动态效果时线不流动、只均匀缩短。手机上 E 键跟线同步发光
##   2 C 战术终端标记：队友四周罗德岛终端风四角框 + 黑底白字「LINK」小标签，标签下一条倒计时刻度
##   3 A + C：引线 + 引线中点挂「LINK · E」小标签（触屏只写 LINK）
## 只换提示画面，连携演出的伤害 / 时序不动。减少动态效果（Cfg.reduce_motion）时不扫光、不转、不呼吸、不闪，只换颜色与描边。
## 坐标与 hud_bars.draw_top_left 同一套（o = (16, 12)：等级圆心 (42, 42)、生命条 (80, 59) 宽 150、灯火条 (252, 59) 宽 120）
const UI = preload("res://scripts/ui.gd")
const Bal = preload("res://scripts/core/balance.gd")
const Tris = preload("res://scripts/screens/hud_tris.gd")
const PlayKeys = preload("res://scripts/core/play_keys.gd")
const UM = preload("res://scripts/ui_motion.gd")
var g
var u   # screens/hud_ult.gd

const DARK := Color(0.03, 0.035, 0.045, 0.85)
const TRACK := Color(0.1, 0.12, 0.14, 0.95)
const HX := 80.0
const LX := 252.0
const LV := Vector2(42.0, 42.0)

var _was_full := false
var _full_rt := -9.0   # 能量刚满的时刻（界面时钟）：扫光 / 扩散圈 0.45 秒


func _init(hud_ult) -> void:
	u = hud_ult
	g = hud_ult.g


static func ver() -> int:
	return clampi(Bal.vi("ui/hud_ult_v", 0), 0, 3)


static func link_cue() -> int:
	return clampi(Bal.vi("ui/link_cue", 0), 0, 3)


## 左上灯火行 / 队友血条行 / 神经细条要多让出的像素（A、C 在生命条下多一层；触屏能量在 Q 键上，左上不加层）
static func top_add(touch: bool) -> float:
	if touch:
		return 0.0
	match ver():
		1:
			return 8.0
		3:
			return 6.0
	return 0.0


func _rm() -> bool:
	return Cfg.reduce_motion


func _pulse() -> float:
	return 0.5 if _rm() else 0.5 + 0.5 * sin(g.t * 4.0)


func _ek() -> float:
	return clampf(g.ult.energy / 100.0, 0.0, 1.0)


## 能量色：队长代表色（亮一档，深色干员在暗底上也看得见）；升级态（能量满 + 协同满）金色
func _ecol() -> Color:
	if u._up():
		return UI.GOLD
	var ld = g.squad.leader()
	var c: Color = ld.col() if ld != null else UI.CYAN
	return c.lerp(Color.WHITE, 0.25)


func _flash_k() -> float:
	if _rm():
		return 0.0
	var t: float = UM.now() - _full_rt
	return clampf(1.0 - t / 0.45, 0.0, 1.0) if t >= 0.0 else 0.0


func _track_full() -> void:
	var f: bool = g.ult.full()
	if f and not _was_full:
		_full_rt = UM.now()
	_was_full = f


func _key(action: String) -> String:
	if g.touch.active:
		return ""
	return Pad.hint(PlayKeys.hint(action, true, false), PlayKeys.hint(action, true, true))


## 小键标（桌面）：深底 + 描边 + 键名
func _chip(fg: Tris, txt: Array[Callable], p: Vector2, key: String, col: Color, lit: bool) -> void:
	if key == "":
		return
	var w: float = maxf(13.0, g.font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.fs(10)).x + 6.0)
	var r := Rect2(p, Vector2(w, 12.0))
	fg.rect(r, DARK)
	fg.frame(r, Color(col.r, col.g, col.b, 0.9 if lit else 0.35), 1.0)
	txt.append(func(): UI.text(g.hud, g.font, Vector2(r.position.x, r.position.y + 10.0), key, 10, UI.TEXT if lit else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, w))


## 连携队首：亮起后 0.15 秒从 55% 弹到整（减少动态效果时直接整）
func _pop(q: Dictionary) -> float:
	if _rm():
		return 1.0
	var pk: float = clampf((u._lit_t() - float(q.left)) / 0.15, 0.0, 1.0)
	return 0.55 + 0.45 * (1.0 - (1.0 - pk) * (1.0 - pk))


func _left_k(q: Dictionary) -> float:
	return clampf(float(q.left) / u._lit_t(), 0.0, 1.0)


func _head_q() -> Array:
	return u._q().filter(func(q): return q.o != null)


## 「技能连携」小字（10-29 用户「根本看不出来」后加的：技能连携亮起时写明）
func _link_label(txt: Array[Callable], q: Dictionary, p: Vector2, align := HORIZONTAL_ALIGNMENT_LEFT, w := 80.0) -> void:
	if q.info.has("link"):
		txt.append(func(): UI.text(g.hud, g.font, p, "技能连携", 11, Color(1.0, 0.8, 0.45), align, w, 3))


# ================================================================ 入口

func draw(vs: Vector2) -> void:
	_track_full()
	_track_link()
	if ver() > 0:
		if g.touch.active:
			_draw_touch_min(vs)   # 触屏：能量只在 Q 键上，左上不画
		else:
			match ver():
				1:
					_draw_a()
				2:
					_draw_b()
				3:
					_draw_c()
		_draw_ready()
	if link_cue() > 0:
		_draw_cue()


# ================================================================ A 血条下嵌

func _draw_a() -> void:
	var bg := Tris.new()
	var fg := Tris.new()
	var txt: Array[Callable] = []
	var full: bool = g.ult.full()
	var ec: Color = _ecol()
	var ek: float = _ek()
	# 能量条：生命条正下方，同宽 150、高 3
	var eb := Rect2(HX, 66.0, 150.0, 3.0)
	bg.rect(eb.grow(1.0), DARK)
	bg.rect(eb, TRACK)
	bg.rect(Rect2(eb.position, Vector2(eb.size.x * ek, eb.size.y)), Color(ec.r, ec.g, ec.b, 1.0 if full else 0.75))
	if full:
		var pu: float = _pulse()
		for k in 2:
			fg.frame(eb.grow(1.5 + k * 2.0), Color(ec.r, ec.g, ec.b, (0.42 - k * 0.16) * (0.4 + 0.6 * pu)), 1.5)
		var fk: float = _flash_k()
		if fk > 0.0:   # 刚满：一道亮光从左扫到右
			var x: float = eb.position.x + eb.size.x * (1.0 - fk)
			fg.rect(Rect2(x - 14.0, eb.position.y - 1.0, 28.0, eb.size.y + 2.0), Color(1, 1, 1, 0.8 * fk))
	# 协同格：灯火条正下方同位置
	_cells_row(bg, Rect2(LX, 66.0, 120.0, 3.0))
	# 条尾「Q」
	_chip(fg, txt, Vector2(eb.end.x + 4.0, 61.0), _key("ult"), ec, full)
	# 连携徽章：生命块右端
	var qs: Array = _head_q() if link_cue() == 0 else []
	bg.flush(g.hud)
	if not qs.is_empty():
		var q: Dictionary = qs[0]
		var c := Vector2(LX + 120.0 + 30.0, 40.0)
		var r: float = 16.0 * _pop(q)
		var oc: Color = q.o.col()
		g.hud.draw_circle(c, r + 1.0, Color(oc.r * 0.3, oc.g * 0.3, oc.b * 0.3, 0.95))
		u._avatar(q.o, c, r - 1.5)
		var cc: Color = oc.lerp(Color.WHITE, 0.35)
		var k: float = _left_k(q)
		fg.arc(c, r + 3.0, 0.0, TAU, 3.0, Color(0.02, 0.03, 0.04, 0.75), 32)
		fg.arc(c, r + 3.0, -PI / 2.0, -PI / 2.0 + TAU * k, 3.0, Color(cc.r, cc.g, cc.b, 0.4 + 0.6 * k), 32)
		_chip(fg, txt, c + Vector2(-7.0, r + 6.0), _key("combo"), cc, true)
		# 后面排队的：右边一排小头像（整圈静止亮着）
		var x: float = c.x + r + 14.0
		for i in range(1, mini(qs.size(), 4)):
			var o = qs[i].o
			var p := Vector2(x, c.y + 6.0)
			g.hud.draw_circle(p, 8.0, Color(o.col().r * 0.3, o.col().g * 0.3, o.col().b * 0.3, 0.95))
			u._avatar(o, p, 6.5)
			fg.arc(p, 8.5, 0.0, TAU, 1.5, Color(o.col().lerp(Color.WHITE, 0.35), 0.85), 20)
			x += 19.0
		_link_label(txt, q, Vector2(c.x + r + 7.0, c.y - 6.0))
	fg.flush(g.hud)
	u.h.text_flush(txt)


func _cells_row(bg: Tris, r: Rect2) -> void:
	var n: int = u._n()
	var cw: float = (r.size.x - float(n - 1) * 2.0) / float(n)
	bg.rect(r.grow(1.0), DARK)
	for i in n:
		bg.rect(Rect2(r.position.x + i * (cw + 2.0), r.position.y, cw, r.size.y), UI.GOLD if i < u._cells() else TRACK)


# ================================================================ B 环形头像

const B_R := 21.0   # 头像半径（原等级圆 22）

func _draw_b() -> void:
	var bg := Tris.new()
	var fg := Tris.new()
	var txt: Array[Callable] = []
	var ld = g.squad.leader()
	var full: bool = g.ult.full()
	var ec: Color = _ecol()
	var ek: float = _ek()
	var c: Vector2 = LV
	bg.circle(c, B_R + 5.0, DARK, 32)
	# 协同格：左上弧（正左 → 正上）
	var n: int = u._n()
	var a0: float = PI + 0.12
	var seg: float = (PI / 2.0 - 0.24) / float(n)
	bg.flush(g.hud)
	if ld != null:
		u._avatar(ld, c, B_R, Color.WHITE if full else Color(0.55, 0.58, 0.62))
	# 能量环
	fg.arc(c, B_R + 3.0, 0.0, TAU, 3.0, Color(0.1, 0.12, 0.14, 0.95), 40)
	fg.arc(c, B_R + 3.0, -PI / 2.0, -PI / 2.0 + TAU * ek, 3.0, Color(ec.r, ec.g, ec.b, 1.0 if full else 0.8), 40)
	for i in n:
		var sa: float = a0 + i * seg + 0.03
		fg.arc(c, B_R + 8.5, sa, sa + seg - 0.06, 2.5, UI.GOLD if i < u._cells() else Color(0.2, 0.22, 0.25, 0.85), 4)
	if full:
		var pu: float = _pulse()
		fg.arc(c, B_R + 6.0, 0.0, TAU, 2.0, Color(ec.r, ec.g, ec.b, 0.2 + 0.4 * pu), 40)
		if not _rm():
			# 三粒亮点绕环转
			for k in 3:
				var sa2: float = g.t * 2.4 + TAU * k / 3.0
				fg.arc(c, B_R + 3.0, sa2, sa2 + 0.55, 3.5, Color(1, 1, 1, 0.85), 8)
		else:
			fg.arc(c, B_R + 3.0, 0.0, TAU, 1.0, Color(1, 1, 1, 0.7), 40)
		var fk: float = _flash_k()
		if fk > 0.0:   # 刚满：一圈往外扩散
			fg.arc(c, B_R + 4.0 + 16.0 * (1.0 - fk), 0.0, TAU, 2.0, Color(ec.r, ec.g, ec.b, 0.8 * fk), 40)
	# 等级小牌：右上；Q 小标：左下
	var lvs: String = "LV%d" % g.level
	var lw: float = g.font.get_string_size(lvs, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.fs(9)).x + 8.0
	var lr := Rect2(c.x + 9.0, c.y - B_R - 8.0, lw, 12.0)
	fg.rect(lr, DARK)
	var lf: float = g.hud_lv_flash
	var lbc: Color = UI.CYAN.lerp(UI.GOLD, lf)
	fg.frame(lr, Color(lbc.r, lbc.g, lbc.b, 0.75), 1.0)
	txt.append(func(): UI.text(g.hud, g.font, Vector2(lr.position.x, lr.position.y + 10.0), lvs, 9, Color(1, 1, 1).lerp(UI.GOLD, lf), HORIZONTAL_ALIGNMENT_CENTER, lw))
	_chip(fg, txt, Vector2(c.x - B_R - 9.0, c.y + 9.0), _key("ult"), ec, full)
	fg.flush(g.hud)
	# 连携：从环的右下边（55°）弹出，自带倒计时环；排队的沿环往下（95°）
	var qs: Array = _head_q() if link_cue() == 0 else []
	var fg2 := Tris.new()
	if not qs.is_empty():
		var q: Dictionary = qs[0]
		var r: float = 12.0 * _pop(q)
		var p: Vector2 = c + Vector2.from_angle(deg_to_rad(55.0)) * (B_R + 9.0) * (0.7 + 0.3 * _pop(q))
		var oc: Color = q.o.col()
		g.hud.draw_circle(p, r + 1.5, Color(oc.r * 0.3, oc.g * 0.3, oc.b * 0.3, 0.95))
		u._avatar(q.o, p, r - 1.0)
		var cc: Color = oc.lerp(Color.WHITE, 0.35)
		var k: float = _left_k(q)
		fg2.arc(p, r + 3.0, 0.0, TAU, 2.5, Color(0.02, 0.03, 0.04, 0.8), 28)
		fg2.arc(p, r + 3.0, -PI / 2.0, -PI / 2.0 + TAU * k, 2.5, Color(cc.r, cc.g, cc.b, 0.4 + 0.6 * k), 28)
		_chip(fg2, txt, p + Vector2(-7.0, r + 5.0), _key("combo"), cc, true)
		if qs.size() > 1:
			var o = qs[1].o
			var p2: Vector2 = c + Vector2.from_angle(deg_to_rad(100.0)) * (B_R + 10.0)
			g.hud.draw_circle(p2, 7.5, Color(o.col().r * 0.3, o.col().g * 0.3, o.col().b * 0.3, 0.95))
			u._avatar(o, p2, 6.0)
			fg2.arc(p2, 8.0, 0.0, TAU, 1.5, Color(o.col().lerp(Color.WHITE, 0.35), 0.85), 20)
			if qs.size() > 2:
				txt.append(func(): UI.text(g.hud, g.font, p2 + Vector2(-26.0, 4.0), "+%d" % (qs.size() - 2), 10, UI.SUB, HORIZONTAL_ALIGNMENT_RIGHT, 16.0, 2))
		_link_label(txt, q, Vector2(p.x - 40.0, p.y + r + 31.0), HORIZONTAL_ALIGNMENT_CENTER, 80.0)
	fg2.flush(g.hud)
	u.h.text_flush(txt)


# ================================================================ C 分段刻度

const C_SEGS := 4   # 一局 3–4 次终结技的节奏：能量条分 4 段

func _draw_c() -> void:
	var bg := Tris.new()
	var fg := Tris.new()
	var txt: Array[Callable] = []
	var full: bool = g.ult.full()
	var ec: Color = _ecol()
	var ek: float = _ek()
	# 生命条下层：能量 4 段（紧贴生命条 59–63 之下）
	var er := Rect2(HX, 64.0, 150.0, 4.0)
	bg.rect(er.grow(1.0), DARK)
	var sw: float = (er.size.x - float(C_SEGS - 1) * 2.0) / float(C_SEGS)
	var fk: float = _flash_k()
	for i in C_SEGS:
		var sr := Rect2(er.position.x + i * (sw + 2.0), er.position.y, sw, er.size.y)
		bg.rect(sr, TRACK)
		var f: float = clampf(ek * C_SEGS - i, 0.0, 1.0)
		if f > 0.0:
			bg.rect(Rect2(sr.position, Vector2(sw * f, sr.size.y)), Color(ec.r, ec.g, ec.b, 1.0 if f >= 1.0 else 0.6))
		if fk > 0.0:   # 刚满：四段依次亮一下
			var sk: float = clampf(fk * 1.6 - (C_SEGS - 1 - i) * 0.2, 0.0, 1.0)
			fg.rect(sr, Color(1, 1, 1, 0.75 * sk))
	if full:
		var pu: float = _pulse()
		fg.frame(Rect2(HX - 2.0, 57.0, 154.0, 13.0), Color(ec.r, ec.g, ec.b, 0.35 + 0.45 * pu), 1.5)
	# 灯火条下层：协同格
	_cells_row(bg, Rect2(LX, 64.0, 120.0, 4.0))
	_chip(fg, txt, Vector2(er.end.x + 4.0, 59.0), _key("ult"), ec, full)
	bg.flush(g.hud)
	fg.flush(g.hud)
	# 连携：生命条上方右端一枚菱形头像
	var qs: Array = _head_q() if link_cue() == 0 else []
	var fg2 := Tris.new()
	if not qs.is_empty():
		var q: Dictionary = qs[0]
		var c := Vector2(HX + 136.0, 38.0)
		var r: float = 14.0 * _pop(q)
		var oc: Color = q.o.col()
		var cc: Color = oc.lerp(Color.WHITE, 0.35)
		if not _rm():   # 闪烁：外圈菱形光随呼吸亮暗
			var bl: float = 0.5 + 0.5 * sin(g.t * 9.0)
			fg2.diamond(c, r + 6.0, Color(cc.r, cc.g, cc.b, 0.22 * bl))
		fg2.diamond(c, r + 1.5, Color(oc.r * 0.3, oc.g * 0.3, oc.b * 0.3, 0.95))
		fg2.flush(g.hud)
		fg2 = Tris.new()
		_avatar_diamond(q.o, c, r - 1.0)
		# 倒计时：菱形描边从正上方顺时针退
		_diamond_outline(fg2, c, r + 3.0, 1.0, Color(0.02, 0.03, 0.04, 0.8), 3.0)
		_diamond_outline(fg2, c, r + 3.0, _left_k(q), Color(cc.r, cc.g, cc.b, 0.45 + 0.55 * _left_k(q)), 3.0)
		_chip(fg2, txt, c + Vector2(r + 6.0, -6.0), _key("combo"), cc, true)
		var x: float = c.x - r - 12.0
		for i in range(1, mini(qs.size(), 3)):
			var o = qs[i].o
			var p := Vector2(x, c.y + 4.0)
			fg2.diamond(p, 7.0, Color(o.col().lerp(Color.WHITE, 0.35), 0.9))
			fg2.diamond(p, 5.0, Color(o.col().r * 0.35, o.col().g * 0.35, o.col().b * 0.35, 1.0))
			x -= 16.0
		_link_label(txt, q, Vector2(c.x - 40.0, c.y - r - 7.0), HORIZONTAL_ALIGNMENT_CENTER, 80.0)
	fg2.flush(g.hud)
	u.h.text_flush(txt)


## 菱形头像（贴图多边形，uv 取头部正方形的内接菱形）
func _avatar_diamond(o, c: Vector2, r: float) -> void:
	var hd: Array = u._head(o)
	if hd.is_empty():
		return
	var t: Texture2D = hd[0]
	var src: Rect2 = hd[1]
	var ts: Vector2 = t.get_size()
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for d in [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]:
		pts.append(c + d * r)
		uvs.append((src.get_center() + d * src.size.x * 0.5) / ts)
	g.hud.draw_colored_polygon(pts, Color.WHITE, uvs, t)


## 菱形描边的前 k（0–1）段：从正上方顺时针
func _diamond_outline(tb: Tris, c: Vector2, r: float, k: float, col: Color, w: float) -> void:
	var p: Array = [c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0), c + Vector2(0, -r)]
	var left: float = clampf(k, 0.0, 1.0) * 4.0
	for i in 4:
		if left <= 0.0:
			break
		var f: float = minf(1.0, left)
		tb.line(p[i], p[i].lerp(p[i + 1], f), col, w)
		left -= 1.0


# ================================================================ 触屏简版键

## 终结技键：底圆 + 队长头像（未满压暗、满了描边 + 呼吸光），不再画能量环与协同格；连携键只在亮起时出现
func _draw_touch_min(vs: Vector2) -> void:
	if not g.hud_live():
		return
	var ld = g.squad.leader()
	var ub: Dictionary = g.touch.ult_btn(vs)
	var c: Vector2 = ub.c
	var r: float = ub.r
	var full: bool = g.ult.full()
	var held: bool = g.touch.skill_id >= 0 or g.touch.flash.get("skill", 0.0) > 0.0
	var ec: Color = _ecol()
	var bg := Tris.new()
	var fg := Tris.new()
	var txt: Array[Callable] = []
	bg.circle(c, r, Color(0.05, 0.12, 0.16, 0.82 if full or held else 0.6), 32)
	# 能量 = 键本身的填充：代表色从下往上涨（水位线亮一道）
	var ek: float = _ek()
	if ek > 0.0:
		var hh: float = r - 2.0 * r * ek
		var a0: float = asin(clampf(hh / r, -1.0, 1.0))
		var pts := PackedVector2Array()
		for i in 25:
			var a: float = lerpf(a0, PI - a0, i / 24.0)
			pts.append(c + Vector2(cos(a), sin(a)) * (r - 1.0))
		if ek >= 0.999:
			pts = PackedVector2Array()
			for i in 32:
				pts.append(c + Vector2.from_angle(TAU * i / 32.0) * (r - 1.0))
		bg.poly(pts, Color(ec.r * 0.55, ec.g * 0.55, ec.b * 0.55, 0.9))
		if ek < 0.999:
			bg.line(pts[0], pts[pts.size() - 1], Color(ec.r, ec.g, ec.b, 0.95), 2.0)
	bg.flush(g.hud)
	if ld != null:
		u._avatar(ld, c, r - 5.0, Color.WHITE if full else Color(0.75, 0.78, 0.82, 0.55))
	if full:
		fg.arc(c, r, 0.0, TAU, 3.0, Color(ec.r, ec.g, ec.b, 0.95), 40)
		fg.arc(c, r + 6.0, 0.0, TAU, 2.0, Color(ec.r, ec.g, ec.b, 0.15 + 0.45 * _pulse()), 40)
	else:
		fg.arc(c, r, 0.0, TAU, 1.5, Color(1, 1, 1, 0.16), 40)
	if g.touch.skill_id >= 0 and g.ult.phase == "aim" and g.ult.aim_kind != "none":
		var reach: float = r + 30.0
		fg.arc(c, reach, 0.0, TAU, 1.5, Color(ec.r, ec.g, ec.b, 0.35), 40)
		var kn: Vector2 = g.touch.skill_aim.limit_length(reach)
		fg.circle(c + kn, 13.0, Color(ec.r, ec.g, ec.b, 0.45), 16)
		fg.arc(c + kn, 13.0, 0.0, TAU, 2.0, Color(1, 1, 1, 0.9), 20)
	var lab: String = "连携终结技" if u._up() else "终结技"
	txt.append(func(): UI.text(g.hud, g.font, c + Vector2(-50.0, r + 17.0), lab, 12, (UI.GOLD if u._up() else UI.TEXT) if full else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 100.0))
	var qs: Array = _head_q()
	var cb: Dictionary = g.touch.combo_btn(vs)
	if not qs.is_empty():
		var q: Dictionary = qs[0]
		var oc: Color = q.o.col().lerp(Color.WHITE, 0.35)
		fg.flush(g.hud)
		fg = Tris.new()
		g.hud.draw_circle(cb.c, cb.r, Color(0.05, 0.12, 0.16, 0.85))
		u._avatar(q.o, cb.c, cb.r - 3.0)
		fg.arc(cb.c, cb.r + 1.0, 0.0, TAU, 2.5, Color(oc.r, oc.g, oc.b, 0.95), 28)
		if link_cue() == 1 or link_cue() == 3:
			var gl: float = 0.6 if _rm() else 0.5 + 0.5 * sin(g.t * TAU * FUSE_FLOW / FUSE_GAP)   # 与引线光点同一节拍
			fg.arc(cb.c, cb.r + 5.0, 0.0, TAU, 3.0, Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.25 + 0.6 * gl), 28)
	if g.touch.flash.get("combo", 0.0) > 0.0:
		fg.arc(cb.c, cb.r + 6.0, 0.0, TAU, 2.0, Color(1, 1, 1, 0.6), 24)
	fg.flush(g.hud)
	u.h.text_flush(txt)


# ================================================================ 队长脚下的就绪光圈

## 能量满：队长脚下一圈代表色椭圆光（呼吸）；刚满时往外扩一圈。减少动态效果时只留静止的一圈
func _draw_ready() -> void:
	if not g.ult.full() or g.ult.phase != "":
		return
	var ld = g.squad.leader()
	if ld == null or ld.pos == Vector2.INF:
		return
	var ct: Transform2D = g.hud_ct()
	var s: float = ct.get_scale().x
	var p: Vector2 = ct * (ld.pos + Vector2(0, 3.0))
	var ec: Color = _ecol()
	var pu: float = _pulse()
	_ellipse(p, 27.0 * s, 10.0 * s, Color(ec.r, ec.g, ec.b, 0.6 + 0.35 * pu), 3.0)
	_ellipse(p, (31.0 + 3.0 * pu) * s, (12.0 + 1.2 * pu) * s, Color(ec.r, ec.g, ec.b, 0.15 + 0.25 * pu), 2.0)
	var fk: float = _flash_k()
	if fk > 0.0:
		var k: float = 1.0 + 0.9 * (1.0 - fk)
		_ellipse(p, 27.0 * s * k, 10.0 * s * k, Color(1, 1, 1, 0.7 * fk), 2.0)


func _ellipse(c: Vector2, rx: float, ry: float, col: Color, w: float) -> void:
	var pts := PackedVector2Array()
	for i in 41:
		var a: float = TAU * i / 40.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	g.hud.draw_polyline(pts, col, w, true)


# ================================================================ 连携提示（ui/link_cue）

const FUSE_PX := 3.0     # 引线像素格
const FUSE_GAP := 30.0   # 光点间距（屏幕像素）
const FUSE_FLOW := 90.0  # 光点流速（像素 / 秒，队友 → 队长）
const BURST_T := 0.45    # 按 E 后爆亮 + 火星散掉

var _last := {}          # 上一帧的队首 {"o", "left"}：队首没到点就离开 = 按了 E（或自动连携出手）
var _burst: Array = []   # {"o", "t0"}（界面时钟）


func _track_link() -> void:
	var qs: Array = _head_q()
	var head = qs[0].o if not qs.is_empty() else null
	if not _last.is_empty() and _last.o != head and float(_last.left) > 0.12:
		_burst.append({"o": _last.o, "t0": UM.now()})
	_last = {"o": head, "left": float(qs[0].left)} if head != null else {}
	_burst = _burst.filter(func(b): return UM.now() - float(b.t0) < BURST_T)


func _scr(pos: Vector2) -> Vector2:
	return g.hud_ct() * pos


func _snap(p: Vector2) -> Vector2:
	return Vector2(floorf(p.x / FUSE_PX) * FUSE_PX, floorf(p.y / FUSE_PX) * FUSE_PX)


## 两名干员之间的引线端点（屏幕坐标，身体中段）
func _ends(o):
	var ld = g.squad.leader()
	if ld == null or ld.pos == Vector2.INF or o == null or o.pos == Vector2.INF:
		return null
	return [_scr(ld.pos + Vector2(0, -10.0)), _scr(o.pos + Vector2(0, -10.0))]


func _draw_cue() -> void:
	var cue: int = link_cue()
	var tb := Tris.new()
	var txt: Array[Callable] = []
	var qs: Array = _head_q()
	if not qs.is_empty():
		var q: Dictionary = qs[0]
		var k: float = _left_k(q)
		var e = _ends(q.o)
		if e != null:
			if cue == 1 or cue == 3:
				_fuse(tb, e[0], e[1], k)
			if cue == 2:
				_corners(tb, txt, q, k)
			if cue == 3:
				var mid: Vector2 = (e[0] + e[1]) * 0.5
				var key: String = _key("combo")
				_tag(tb, txt, mid + Vector2(0, -16.0), "LINK" if key == "" else "LINK · %s" % key, true)
	for b in _burst:
		var e2 = _ends(b.o)
		if e2 == null:
			continue
		var t: float = (UM.now() - float(b.t0)) / BURST_T
		if cue == 1 or cue == 3:
			_fuse_burst(tb, e2[0], e2[1], t)
		else:
			_corner_burst(tb, b.o, t)
	tb.flush(g.hud)
	u.h.text_flush(txt)


## 引线：a = 队长端，b = 队友端；剩下的是 a → a + (b − a)·k 这一段，烧点在末端
func _fuse(tb: Tris, a: Vector2, b: Vector2, k: float) -> void:
	var d: Vector2 = b - a
	var L: float = d.length()
	if L < 8.0:
		return
	var dir: Vector2 = d / L
	var end: float = L * k
	var n: int = int(end / FUSE_PX)
	var col: Color = UI.GOLD
	var flow: float = 0.0 if _rm() else g.t * FUSE_FLOW
	for i in n:
		var x: float = i * FUSE_PX
		var p: Vector2 = _snap(a + dir * x)
		var ph: float = fposmod(x + flow, FUSE_GAP) / FUSE_GAP   # 光点往 a（队长）流
		var hi: float = 0.0 if _rm() else clampf(1.0 - absf(ph - 0.5) * 6.0, 0.0, 1.0)
		var c: Color = col.lerp(Color(1.0, 0.97, 0.85), hi)
		tb.rect(Rect2(p, Vector2(FUSE_PX, FUSE_PX)), Color(c.r, c.g, c.b, 0.55 + 0.4 * hi))
	# 烧点：亮核 + 几粒火星（按时间换位，不用随机数）
	var tip: Vector2 = _snap(a + dir * end)
	tb.rect(Rect2(tip - Vector2(FUSE_PX, FUSE_PX), Vector2(FUSE_PX * 3.0, FUSE_PX * 3.0)), Color(1.0, 0.85, 0.5, 0.35))
	tb.rect(Rect2(tip, Vector2(FUSE_PX, FUSE_PX)), Color(1, 1, 0.92, 1.0))
	if not _rm():
		var nrm := Vector2(-dir.y, dir.x)
		for j in 3:
			var ph2: float = fposmod(g.t * 3.0 + j * 0.37, 1.0)
			var sp: Vector2 = tip + dir * (ph2 * 9.0) + nrm * sin(j * 2.1 + g.t * 11.0) * 7.0 * ph2 + Vector2(0, -6.0 * ph2)
			tb.rect(Rect2(_snap(sp), Vector2(FUSE_PX, FUSE_PX)), Color(1.0, 0.8, 0.4, 0.9 * (1.0 - ph2)))


## 按 E：前 30% 整线爆亮，之后化成火星往四周散、淡出
func _fuse_burst(tb: Tris, a: Vector2, b: Vector2, t: float) -> void:
	var d: Vector2 = b - a
	var L: float = d.length()
	if L < 8.0:
		return
	var dir: Vector2 = d / L
	var nrm := Vector2(-dir.y, dir.x)
	var n: int = int(L / FUSE_PX)
	if t < 0.3 or _rm():
		var a1: float = 1.0 - t if _rm() else 1.0
		for i in n:
			tb.rect(Rect2(_snap(a + dir * i * FUSE_PX) - Vector2(1, 1), Vector2(FUSE_PX + 2.0, FUSE_PX + 2.0)), Color(1, 0.95, 0.75, 0.95 * a1))
		return
	var k: float = (t - 0.3) / 0.7
	for i in range(0, n, 2):
		var hsh: float = sin(i * 12.9898) * 43758.5453
		var rnd: float = hsh - floorf(hsh)
		var off: Vector2 = nrm * (rnd - 0.5) * 2.0 * 26.0 * k + Vector2(0, -14.0 * k * rnd)
		tb.rect(Rect2(_snap(a + dir * i * FUSE_PX + off), Vector2(FUSE_PX, FUSE_PX)), Color(1.0, 0.75 + 0.2 * rnd, 0.35, 0.9 * (1.0 - k)))


## 终端风四角框 + LINK 标签 + 倒计时刻度（框亮起时从 1.4 倍收到 1 倍，减少动态效果时直接到位）
func _corners(tb: Tris, txt: Array[Callable], q: Dictionary, k: float) -> void:
	var o = q.o
	var ct: Transform2D = g.hud_ct()
	var s: float = ct.get_scale().x
	var c: Vector2 = _scr(o.pos + Vector2(0, -14.0))
	var lock: float = 1.0 if _rm() else 1.0 + 0.4 * (1.0 - clampf((u._lit_t() - float(q.left)) / 0.15, 0.0, 1.0))
	var hw: float = 20.0 * s * lock
	var hh: float = 24.0 * s * lock
	var box := Rect2(c - Vector2(hw, hh), Vector2(hw, hh) * 2.0)
	_brackets(tb, box, Color(0.93, 0.95, 0.97, 0.95), 2.0)
	var lw: float = _tag(tb, txt, Vector2(box.position.x, box.position.y - 20.0), "LINK", false)
	# 倒计时刻度：10 格，按剩余时间从右往左熄
	var n := 10
	var tw: float = maxf(lw, 34.0)
	var cw: float = (tw - (n - 1) * 1.0) / n
	for i in n:
		var on: bool = float(i) < ceil(k * n)
		tb.rect(Rect2(box.position.x + i * (cw + 1.0), box.position.y - 9.0, cw, 3.0), Color(0.93, 0.95, 0.97, 0.9) if on else Color(0.2, 0.22, 0.25, 0.7))


func _brackets(tb: Tris, r: Rect2, col: Color, w: float) -> void:
	var L: float = minf(9.0, r.size.x * 0.3)
	for cx in [0, 1]:
		for cy in [0, 1]:
			var p := Vector2(r.position.x + r.size.x * cx, r.position.y + r.size.y * cy)
			var sx: float = 1.0 if cx == 0 else -1.0
			var sy: float = 1.0 if cy == 0 else -1.0
			tb.rect(Rect2(Vector2(minf(p.x, p.x + sx * L), p.y - (0.0 if cy == 0 else w)), Vector2(L, w)), col)
			tb.rect(Rect2(Vector2(p.x - (0.0 if cx == 0 else w), minf(p.y, p.y + sy * L)), Vector2(w, L)), col)


## 黑底白字英文小标签（同卡面 SQUAD 标签那套：黑底、白字、字距）；center = true 时 p 是中心。返回宽
func _tag(tb: Tris, txt: Array[Callable], p: Vector2, s: String, center: bool) -> float:
	var w: float = g.font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.fs(10)).x + s.length() * 2.0 + 10.0
	var r := Rect2(p - Vector2(w * 0.5 if center else 0.0, 7.0), Vector2(w, 14.0))
	tb.rect(r, Color(0, 0, 0, 0.88))
	txt.append(func(): UI.en(g.hud, g.font, Vector2(r.position.x + 5.0, r.position.y + 11.0), s, 10, Color(1, 1, 1), 2.0))
	return w


## C 按 E：四角框往外弹开、淡出
func _corner_burst(tb: Tris, o, t: float) -> void:
	if o == null or o.pos == Vector2.INF:
		return
	var s: float = g.hud_ct().get_scale().x
	var c: Vector2 = _scr(o.pos + Vector2(0, -14.0))
	var k: float = 1.0 if _rm() else 1.0 + 0.6 * t
	_brackets(tb, Rect2(c - Vector2(20.0, 24.0) * s * k, Vector2(40.0, 48.0) * s * k), Color(1, 1, 1, 0.9 * (1.0 - t)), 2.0)
