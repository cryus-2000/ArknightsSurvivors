extends RefCounted
## 界面 · 终结技 / 连携并进左上生命块的三个原型（10-30 用户「终结技和连携的 UI 能不能和血条之类的合并一下，出三个设计稿」）。
## 开关 balance.json ui/hud_ult_v：0 = 现行（底部中央长条 + 底部弹出队友头像，本文件不画）；1 / 2 / 3 = 下面三个方向，挑定后再精修。
##   （10-30 第二版，用户「UI 再想想怎么设计更加有设计感」：三个方向都改用 docs/37 水月版式的现成语汇，跟生命值 / 灯火一套语法）
##   1 A′ 第三栏：「生命值」「灯火」右边并排「终结技」——代表色小标签头 + 大号百分比（满了换「就绪」+ 按键牌）+ 4 段刻度细条，协同格是细条下一排小菱形
##   2 B′ 徽记环：等级圆换成队长头像，外一圈 300° 能量弧（底部缺口嵌按键牌）+ 渐隐细线（满了光点绕行），协同格是外圈左上一排小菱形
##   3 C′ 节点标签条：生命 / 灯火块下方一条「ULT | 终结技」标签条（满了 READY | 终结技 · Q）+ 4 枚斜切能量格 + 协同小方格
## 三个方向共用：桌面底部中央的终结技条与弹出头像不再画；「可以放了」不放角落，挂在队长身上——能量满时队长脚下亮一圈代表色光（_draw_ready）。
## 触屏（10-30 协调人与用户商定）：能量不并进血条，直接做成右下 Q 键本身的填充（从下往上涨），连携键只在亮起时出现。
## 连携提示挂在场上两名干员之间（ui/link_cue；三个方向下 link_cue = 0 时按 1 灯火引线画），左上不再画连携徽章：
##   1 A 灯火引线：队长与亮起的队友之间一条灯火色细引线（3 像素格），光点从队友流向队长；引线全长常驻不缩短（10-30 用户），
##     倒计时 = 火头从队友端烧向队长端，烧过的一段变成暗红余烬，烧到队长窗口关闭；按 E（队首提前离队）整线爆亮、化成火星散掉；
##     减少动态效果时光点不流动、火头照走。手机上 E 键跟线同步发光
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
const HX := 80.0
const LX := 252.0
const LV := Vector2(42.0, 42.0)

var _was_full := false
var _full_rt := -9.0   # 能量刚满的时刻（界面时钟）：扫光 / 扩散圈 0.45 秒


func _init(hud_ult) -> void:
	u = hud_ult
	g = hud_ult.g


static func ver() -> int:
	return clampi(Bal.vi("ui/hud_ult_v", 2), 0, 3)   # 10-31 用户选定 B′ 徽记环（2）为缺省


static func link_cue() -> int:
	var c: int = clampi(Bal.vi("ui/link_cue", 0), 0, 3)
	return 1 if c == 0 and ver() > 0 else c   # 三个方向左上不再画连携徽章：没选提示时按灯火引线


## 左上灯火行 / 队友血条行 / 神经细条要多让出的像素（A、C 在生命条下多一层；触屏能量在 Q 键上，左上不加层）
static func top_add(touch: bool) -> float:
	if touch:
		return 0.0
	return 26.0 if ver() == 3 else 0.0


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


func _left_k(q: Dictionary) -> float:
	return clampf(float(q.left) / u._lit_t(), 0.0, 1.0)


func _head_q() -> Array:
	return u._q().filter(func(q): return q.o != null)


# ================================================================ 入口

func draw(vs: Vector2) -> void:
	_track_full()
	_track_link()
	if ver() > 0:
		if g.touch.active:
			_draw_touch_min(vs)   # 触屏：能量只在 Q 键上
			if ver() == 2:
				_draw_b(true)   # B′ 徽记（头像 + 等级）触屏也画，不画能量弧
		else:
			match ver():
				1:
					_draw_a()
				2:
					_draw_b()
				3:
					_draw_c()
		_draw_ready()
		if ver() == 2:
			_draw_ready_toast(vs)
	if link_cue() > 0:
		_draw_cue()


# ================================================================ A′ 第三栏（同生命值 / 灯火的版式）

## 「生命值」「灯火」之后并排第三栏「终结技」：同一套语法——彩色小标签头（队长代表色压暗）+ 细条下一排小菱形（协同格，同护盾菱形）
## + 大号数字（充能百分比；满了换成「就绪」+ 按键牌）+ 细条（4 段刻度 = 一局 3–4 次的节奏）。升级态（能量满 + 协同满）标签头换金、写「连携终结技」
const A_X := 394.0   # 灯火栏（252 起、宽 120）右边留 22，同生命值与灯火的间距
const A_W := 120.0

func _draw_a() -> void:
	var full: bool = g.ult.full()
	var up: bool = u._up()
	var ec: Color = _ecol()
	var ek: float = _ek()
	var pu: float = _pulse()
	var x: float = A_X
	var y: float = 12.0
	var tcol: Color = UI.GOLD.darkened(0.3) if up else ec.darkened(0.45)
	UI.tab(g.hud, g.font, Vector2(x, y), "连携终结技" if up else "终结技", tcol)
	# 协同格：细条下面一排小菱形（同护盾菱形的画法；放标签头右边会挤到顶部中央的击杀框）
	for i in u._n():
		UI.diamond(g.hud, Vector2(x + 3.5 + i * 9.0, y + 58.0), 3.0, UI.GOLD if i < u._cells() else Color(1, 1, 1, 0.12), Color(1.0, 0.85, 0.5, 0.7))
	# 数字：充能百分比 / 就绪 + 按键牌
	if full:
		var rc: Color = ec.lerp(Color.WHITE, 0.25 * pu)
		UI.ctext(g.hud, g.font, Vector2(x, y + 40.0), "就绪", 21, rc)
		var key: String = _key("ult")
		if key != "":
			UI.keycap(g.hud, g.font, Vector2(x + UI.cwidth(g.font, "就绪", 21) + 8.0, y + 25.0), key, UI.TEXT, 11)
	else:
		var ps: String = "%d" % int(ek * 100.0)
		UI.ctext(g.hud, g.font, Vector2(x, y + 40.0), ps, 21, UI.TEXT)
		UI.ctext(g.hud, g.font, Vector2(x + UI.cwidth(g.font, ps, 21) + 4.0, y + 40.0), "%", 13, UI.SUB)
	# 细条：4 段刻度
	var br := Rect2(x, y + 47.0, A_W, 4.0)
	UI.gbar(g.hud, br, ek, Color(ec.r, ec.g, ec.b, 1.0 if full else 0.85), 4)
	if full:
		g.hud.draw_rect(br.grow(2.0), Color(ec.r, ec.g, ec.b, 0.15 + 0.35 * pu), false, 1.5)
		var fk: float = _flash_k()
		if fk > 0.0:   # 刚满：一道亮光从左扫到右
			var sx: float = br.position.x + br.size.x * (1.0 - fk)
			g.hud.draw_rect(Rect2(sx - 12.0, br.position.y - 1.0, 24.0, br.size.y + 2.0), Color(1, 1, 1, 0.8 * fk))


# ================================================================ B′ 徽记环（队长头像 + 能量弧）

## 左上等级圆换成队长头像徽记：内圈头像、外一圈 300° 能量弧（底部 60° 缺口里嵌按键牌）、再外一圈渐隐细线；
## 协同格 = 外圈左上一排小菱形；等级挪到头像右下一行小字。满了：能量弧换亮、细线上一粒光点绕行（减少动态效果时不转）
const B_R := 19.0
const B_GAP := PI / 3.0   # 底部缺口

## 10-31 用户选定 B′，四点修改（协调人转）：① 头像用高清待机帧（图鉴 / 选人同款 @2x，A.tex_hi）裁头部，不用小像素头；
## ② 等级放大、提高对比，挂在徽记顶上一块深底亮边小牌，手机横屏也画；③ 能量刚满：头像闪两下 + 屏幕中上一次「终结技就绪」提示（约 1.8 秒淡出，不常驻）；
## ④ 缺省 B′（ui/hud_ult_v 2），A′ / C′ 留开关。触屏：徽记照画（头像 + 等级），能量仍做在 Q 键上，徽记上不画能量弧和协同格
func _draw_b(phone := false) -> void:
	var ld = g.squad.leader()
	var full: bool = g.ult.full()
	var ec: Color = _ecol()
	var ek: float = _ek()
	var pu: float = _pulse()
	var c: Vector2 = LV
	var tb := Tris.new()
	var txt: Array[Callable] = []
	tb.circle(c, B_R + 2.0, DARK, 32)
	tb.flush(g.hud)
	var fl: float = _flash_b()
	if ld != null:
		var tint: Color = Color.WHITE if (full or phone) else Color(0.62, 0.65, 0.7)
		_avatar_hi(ld, c, B_R, tint)
		if fl > 0.0:
			g.hud.draw_circle(c, B_R, Color(1, 1, 1, 0.55 * fl))   # 刚满：头像闪
	tb = Tris.new()
	if not phone:
		var a0: float = PI / 2.0 + B_GAP / 2.0   # 缺口右沿往顺时针走
		var span: float = TAU - B_GAP
		tb.arc(c, B_R + 4.5, a0, a0 + span, 3.5, Color(0.1, 0.12, 0.14, 0.95), 40)
		tb.arc(c, B_R + 4.5, a0, a0 + span * ek, 3.5, Color(ec.r, ec.g, ec.b, 1.0 if full else 0.85), 40)
		tb.arc(c, B_R + 9.0, a0, a0 + span, 1.0, Color(1, 1, 1, 0.16), 48)
		if full:
			tb.arc(c, B_R + 9.0, a0, a0 + span, 1.5, Color(ec.r, ec.g, ec.b, 0.2 + 0.45 * pu), 48)
			if not _rm():
				var sa: float = a0 + fposmod(g.t * 1.6, 1.0) * span
				tb.circle(c + Vector2.from_angle(sa) * (B_R + 9.0), 2.2, Color(1, 1, 1, 0.95), 8)
			var fk: float = _flash_k()
			if fk > 0.0:
				tb.arc(c, B_R + 5.0 + 14.0 * (1.0 - fk), 0.0, TAU, 2.0, Color(ec.r, ec.g, ec.b, 0.8 * fk), 40)
		# 协同格：外圈左下一排小菱形（顶上让给等级牌）
		var n: int = u._n()
		for i in n:
			var a: float = PI * 0.62 + (PI * 0.5) * i / maxf(1.0, n - 1.0)
			tb.diamond(c + Vector2.from_angle(a) * (B_R + 13.0), 3.0, UI.GOLD if i < u._cells() else Color(1, 1, 1, 0.14))
	else:
		tb.arc(c, B_R + 2.0, 0.0, TAU, 1.5, Color(ec.r, ec.g, ec.b, 0.9 if full else 0.4), 40)
	tb.flush(g.hud)
	# 缺口里的按键牌（桌面）
	var key: String = _key("ult")
	if key != "" and not phone:
		var kw: float = UI.cwidth(g.font, key, 10) + 12.0
		UI.keycap(g.hud, g.font, c + Vector2(-kw / 2.0, B_R + 0.0), key, UI.TEXT if full else UI.SUB, 10)
	# 等级牌：徽记顶上，深底 + 青边（升级时闪金），白色大字
	var lf: float = g.hud_lv_flash
	var lvs: String = "LV %d" % g.level
	var lw: float = UI.cwidth(g.font, lvs, 13) + 14.0
	var lr := Rect2(c.x - lw / 2.0, c.y - B_R - 17.0, lw, 18.0)   # 头像露出头顶后上移 4，少压耳朵 / 帽檐
	g.hud.draw_rect(lr, Color(0.02, 0.03, 0.05, 0.95))
	var bc: Color = UI.CYAN.lerp(UI.GOLD, lf)
	g.hud.draw_rect(lr, bc, false, 1.5)
	UI.ctext(g.hud, g.font, Vector2(lr.position.x, lr.position.y + 15.0), lvs, 13, Color.WHITE.lerp(UI.GOLD, lf), HORIZONTAL_ALIGNMENT_CENTER, lw)
	u.h.text_flush(txt)


## 刚满时头像闪两下（0.8 秒，减少动态效果时不闪）
func _flash_b() -> float:
	if _rm():
		return 0.0
	var t: float = UM.now() - _full_rt
	if t < 0.0 or t > 0.8:
		return 0.0
	return maxf(0.0, sin(t / 0.8 * TAU * 2.0)) * (1.0 - t / 0.8)


## 「终结技就绪」提示：能量刚满时屏幕中上出一次，约 1.8 秒（0.2 秒淡入、停留、最后 0.5 秒淡出），不常驻
const READY_T := 1.8

func _draw_ready_toast(vs: Vector2) -> void:
	var t: float = UM.now() - _full_rt
	if t < 0.0 or t > READY_T or not g.ult.full():
		return
	var a: float = clampf(t / 0.2, 0.0, 1.0) * clampf((READY_T - t) / 0.5, 0.0, 1.0)
	var ec: Color = _ecol()
	var y: float = vs.y * 0.3
	var s := "终结技就绪"
	var fsz := 22
	var tw: float = g.font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.fs(fsz)).x
	var key: String = _key("ult")
	var kw: float = (UI.cwidth(g.font, key, 13) + 12.0 + 12.0) if key != "" else 0.0
	var w: float = tw + kw + 64.0
	var rise: float = 0.0 if _rm() else 8.0 * (1.0 - clampf(t / 0.25, 0.0, 1.0))
	var r := Rect2(vs.x / 2.0 - w / 2.0, y - 22.0 + rise, w, 40.0)
	g.hud.draw_rect(r, Color(0.02, 0.03, 0.05, 0.82 * a))
	g.hud.draw_rect(Rect2(r.position, Vector2(4, r.size.y)), Color(ec.r, ec.g, ec.b, a))
	g.hud.draw_rect(Rect2(r.end.x - 4.0, r.position.y, 4, r.size.y), Color(ec.r, ec.g, ec.b, a))
	var x: float = r.position.x + 32.0
	UI.text(g.hud, g.font, Vector2(x, r.position.y + 28.0), s, fsz, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
	if key != "":
		UI.keycap(g.hud, g.font, Vector2(x + tw + 12.0, r.position.y + 10.0), key, Color(ec.r, ec.g, ec.b, a), 13)


## 高清头像（A.tex_hi 的 @2x 待机帧，图鉴 / 选人同款）：有双眼中点表按眼睛裁；没有的按不透明像素找头部（帧顶往下约 40% 高度内的横向范围），取正方形、圆形裁切；
## 每名干员只扫描一次图像并缓存。没有高清帧时退回 hud_ult._avatar（小像素头）
var _hh := {}
## 双眼中点表（10-31 用户「20 人加 Mon3tr 都要按眼睛位置对齐」，art/operators/avatar_eyes.json，人工标定）：
## 有表的人按眼睛裁——双眼中点落在圆心上方 EYE_UP 半径处，眼距统一缩放到半径 × EYE_D，脸在圈里一样大；没表的退回下面按轮廓找头
const EYES_PATH := "res://art/operators/avatar_eyes.json"
const EYE_UP := 0.02   # 10-31 用户「露出头多一点，下一点点」：原 0.09 / 0.55
const EYE_D := 0.42
static var _eyes: Dictionary = {}

static func eyes_table() -> Dictionary:
	if _eyes.is_empty():
		var f := FileAccess.open(EYES_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		_eyes = d.get("ops", {}) if d is Dictionary else {"_none": true}
	return _eyes


func _hi_head(o) -> Array:
	var oid := str(o.id)
	if _hh.has(oid):
		return _hh[oid]
	var out: Array = []
	var art: Dictionary = u._art_of(o)
	var ey: Dictionary = eyes_table().get(oid, {})
	if not art.is_empty() and not ey.is_empty():
		var k: float = float((art.tex as Texture2D).get_height()) / float(ey.get("fh", 0.0)) if float(ey.get("fh", 0.0)) > 0.0 else 1.0   # 表按 @2x 帧量，按帧高换算（1 倍帧 / 镜像副本都对）
		var side: float = float(ey.d) * k * 2.0 / EYE_D
		var c := Vector2(float(ey.eye[0]), float(ey.eye[1])) * k + Vector2(0.0, EYE_UP * side * 0.5)
		out = [art.tex, Rect2(c - Vector2(side, side) * 0.5, Vector2(side, side))]
		_hh[oid] = out
		return out
	if not art.is_empty() and art.bb.size.y > 0.0:
		var tex: Texture2D = art.tex
		var bb: Rect2 = art.bb
		var img: Image = tex.get_image()
		if img != null:
			if img.is_compressed():
				img.decompress()
			var hh: int = int(bb.size.y * 0.4)
			var x0 := int(bb.end.x)
			var x1 := int(bb.position.x)
			for yy in range(int(bb.position.y), int(bb.position.y) + hh):
				for xx in range(int(bb.position.x), int(bb.end.x)):
					if img.get_pixel(xx, yy).a > 0.5:
						x0 = mini(x0, xx)
						x1 = maxi(x1, xx)
			if x1 > x0:
				var side: float = clampf(float(x1 - x0), float(hh) * 0.8, float(hh) * 1.15)
				var cx: float = (x0 + x1) * 0.5
				out = [tex, Rect2(cx - side * 0.5, bb.position.y - side * 0.02, side, side)]
	_hh[oid] = out
	return out


func _avatar_hi(o, c: Vector2, r: float, tint := Color.WHITE) -> void:
	var hd: Array = _hi_head(o)
	if hd.is_empty():
		u._avatar(o, c, r, tint)
		return
	var t: Texture2D = hd[0]
	var src: Rect2 = hd[1]
	var ts: Vector2 = t.get_size()
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in 24:
		var d := Vector2.from_angle(TAU * i / 24.0)
		pts.append(c + d * r)
		uvs.append((src.get_center() + d * src.size.x * 0.5) / ts)
	g.hud.draw_colored_polygon(pts, tint, uvs, t)


# ================================================================ C′ 节点标签条

## 生命 / 灯火块下方一条节点标签条（同原作地图标签与下面的灯火状态条）：左段队长代表色底 + 压缩斜体英文 ULT，
## 右段暗底中文「终结技」，再接 4 枚斜切能量格 + 协同小方格；满了英文换 READY、中文换「终结技 · 按键」，能量格整排亮、呼吸。
## 灯火状态条与队友血条行往下让 top_add
const C_SEGS := 4

func _draw_c() -> void:
	var full: bool = g.ult.full()
	var up: bool = u._up()
	var ec: Color = _ecol()
	var ek: float = _ek()
	var pu: float = _pulse()
	var p := Vector2(HX - 62.0, 70.0)   # 与左上面板左缘（16 + 2）对齐
	var key: String = _key("ult")
	var en_s: String = "READY" if full else "ULT"
	var cn: String = ("连携终结技" if up else "终结技") + (" · %s" % key if full and key != "" else "")
	var sc: Color = UI.GOLD if up else ec
	var w: float = UI.strip(g.hud, g.font, p, en_s, cn, Color(sc.r, sc.g, sc.b, 1.0 if full else 0.8), UI.TEXT, 12)
	var tb := Tris.new()
	var x: float = p.x + w + 6.0
	var hh: float = 20.0
	var sw := 20.0
	for i in C_SEGS:
		var f: float = clampf(ek * C_SEGS - i, 0.0, 1.0)
		var x0: float = x + i * (sw + 3.0)
		var q := PackedVector2Array([Vector2(x0 + 5.0, p.y), Vector2(x0 + sw + 5.0, p.y), Vector2(x0 + sw, p.y + hh), Vector2(x0, p.y + hh)])
		tb.poly(q, Color(0, 0, 0, 0.6))
		if f > 0.0:
			var fx: float = sw * f
			var fq := PackedVector2Array([Vector2(x0 + 5.0, p.y + 3.0), Vector2(x0 + 5.0 + fx - 1.0, p.y + 3.0), Vector2(x0 + fx - 1.0 + 0.5, p.y + hh - 3.0), Vector2(x0 + 0.5, p.y + hh - 3.0)])
			var a: float = (0.75 + 0.25 * pu) if full else (0.9 if f >= 1.0 else 0.5)
			tb.poly(fq, Color(sc.r, sc.g, sc.b, a))
	var fk: float = _flash_k()
	if fk > 0.0:
		tb.rect(Rect2(p.x, p.y, (x + C_SEGS * (sw + 3.0) - p.x) * (1.0 - fk), hh), Color(1, 1, 1, 0.25 * fk))
	# 协同格：能量格右边两行小方格
	var cx: float = x + C_SEGS * (sw + 3.0) + 6.0
	for i in u._n():
		var r := Rect2(cx + (i / 2) * 6.0, p.y + 3.0 + (i % 2) * 8.0, 4.0, 5.0)
		tb.rect(r, UI.GOLD if i < u._cells() else Color(1, 1, 1, 0.14))
	tb.flush(g.hud)


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


## 引线：a = 队长端，b = 队友端；全长常驻不缩短。火头在 a + (b − a)·k（k 从 1 = 队友端走到 0 = 队长端）：
## 火头到队长之间是没烧到的一段（灯火金，光点往队长流），火头到队友之间是烧过的余烬（暗红、微微闪）
func _fuse(tb: Tris, a: Vector2, b: Vector2, k: float) -> void:
	var d: Vector2 = b - a
	var L: float = d.length()
	if L < 8.0:
		return
	var dir: Vector2 = d / L
	var head: float = L * k
	var n: int = int(L / FUSE_PX)
	var col: Color = UI.GOLD
	var ember := Color(0.78, 0.3, 0.16)
	var flow: float = 0.0 if _rm() else g.t * FUSE_FLOW
	for i in n:
		var x: float = i * FUSE_PX
		var p: Vector2 = _snap(a + dir * x)
		if x <= head:
			var ph: float = fposmod(x + flow, FUSE_GAP) / FUSE_GAP   # 光点往 a（队长）流
			var hi: float = 0.0 if _rm() else clampf(1.0 - absf(ph - 0.5) * 6.0, 0.0, 1.0)
			var c: Color = col.lerp(Color(1.0, 0.97, 0.85), hi)
			tb.rect(Rect2(p, Vector2(FUSE_PX, FUSE_PX)), Color(c.r, c.g, c.b, 0.6 + 0.35 * hi))
		else:
			var fl: float = 0.0 if _rm() else 0.5 + 0.5 * sin(g.t * 7.0 + i * 1.7)
			tb.rect(Rect2(p, Vector2(FUSE_PX, FUSE_PX)), Color(ember.r, ember.g, ember.b, 0.35 + 0.2 * fl))
	# 火头：亮核 + 几粒火星（按时间换位，不用随机数）
	var tip: Vector2 = _snap(a + dir * head)
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
