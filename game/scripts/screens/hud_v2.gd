extends RefCounted
## 界面 · 局内 HUD 编辑式（docs/222，11-02 用户定：PRTS 终端 × 莱茵生命「编辑式」，少框多留白）。
## 总开关 balance.json ui/hud_v2：1 = 编辑式（缺省），0 = 回到旧 HUD（各块原画法一行不动，只在入口按开关分流）。
## 语言：几何粗体大字（Montserrat，UI.latin）+ 极小的字距拉开的大写标签；条一律是一根细线 + 线头一颗点；面板只留一片很淡的暗带托字。
## 本文件只放画法与各块的编辑式版本；各块入口（hud_bars / hud_relics / hud_squad / hud_allyhp / touch）开头判 on() 后转过来。
## 等级牌（B′ 徽记顶上的「LV n」）照旧不改（用户 11-02「等级框先保持现状」）。
const UI = preload("res://scripts/ui.gd")
const Bal = preload("res://scripts/core/balance.gd")
const Game = preload("res://scripts/game.gd")
const PlayClock = preload("res://scripts/run/play_clock.gd")
const D = preload("res://scripts/data.gd")
const LinkBond = preload("res://scripts/run/link_bond.gd")
const Character = preload("res://scripts/characters/character.gd")
var g: Game
var h   # screens/hud.gd

const HP_COL := Color(0.275, 0.882, 0.941)      # 生命细线（青，同旧条）
const LINE := Color(1, 1, 1, 0.28)
const LINE_DIM := Color(1, 1, 1, 0.14)
const SHADOW := Color(0.0, 0.024, 0.047, 0.55)
const SEG_NAMES := ["随行", "突击", "部署", "集火"]


func _init(hud) -> void:
	h = hud
	g = hud.g


static func on() -> bool:
	return Bal.vi("ui/hud_v2", 1) > 0


# ================================================================ 画法

## 字距拉开的大写小标签（Montserrat SemiBold）；返回宽度。align：0 左、1 中、2 右
func cap(pos: Vector2, s: String, size: float, col: Color = UI.SUB, sp := 1.6, align := 0) -> float:
	var f: Font = UI.latin(true)
	var ks: int = int(round(size))
	var w := 0.0
	for ch in s:
		w += f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, ks).x + sp
	w -= sp
	var x: float = pos.x - (w if align == 2 else (w / 2.0 if align == 1 else 0.0))
	for ch in s:
		g.hud.draw_string(f, Vector2(x + 1, pos.y + 1), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, ks, SHADOW)
		g.hud.draw_string(f, Vector2(x, pos.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, ks, col)
		x += f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, ks).x + sp
	return w


## 几何粗体大字（数字 / 模式名），带一层柔和投影；返回宽度
func big(pos: Vector2, s: String, size: float, col: Color = UI.TEXT, align := 0) -> float:
	var f: Font = UI.latin()
	var ks: int = int(round(size))
	var w: float = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, ks).x
	var x: float = pos.x - (w if align == 2 else (w / 2.0 if align == 1 else 0.0))
	g.hud.draw_string(f, Vector2(x + 1, pos.y + 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, ks, SHADOW)
	g.hud.draw_string(f, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, ks, col)
	return w


## 中文正文（ui.ttf），带投影
func txt(pos: Vector2, s: String, size: int, col: Color = UI.TEXT, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, font: Font = null) -> void:
	var ks: int = UI._ks(g.hud, size)
	var f: Font = g.font if font == null else font
	g.hud.draw_string(f, pos + Vector2(1, 1), s, align, width, ks, SHADOW)
	g.hud.draw_string(f, pos, s, align, width, ks, col)


func twidth(s: String, size: int) -> float:
	return g.font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, UI._ks(g.hud, size)).x


## 一根细线做条：暗线打底，亮线填到 frac，线头一颗点；marks = 刻度位置（0..1）
func line_bar(x: float, y: float, w: float, frac: float, col: Color, hh := 2.0, marks: Array = [], trail := -1.0) -> void:
	var f: float = clampf(frac, 0.0, 1.0)
	g.hud.draw_rect(Rect2(x, y, w, hh), Color(1, 1, 1, 0.16))
	if trail > f:
		g.hud.draw_rect(Rect2(x + w * f, y, w * (clampf(trail, 0.0, 1.0) - f), hh), Color(1, 1, 1, 0.55))
	if f > 0.0:
		g.hud.draw_rect(Rect2(x, y, w * f, hh), col)
		g.hud.draw_circle(Vector2(x + w * f, y + hh / 2.0), hh + 0.6, col)
	for t in marks:
		g.hud.draw_rect(Rect2(x + w * float(t) - 0.5, y - 3.0, 1.0, hh + 6.0), col)


## 一片很淡的暗带（不是面板）：只为在亮特效上托住浮字
func shade(r: Rect2, a := 0.32) -> void:
	UI.fade_band(g.hud, r, Color(0.008, 0.03, 0.055, a), minf(40.0, r.size.x * 0.25))


func plate(r: Rect2, col: Color) -> void:
	g.hud.draw_rect(r, col)


# ================================================================ 左上：队长读数

const HX := 80.0   # 读数列左边（B′ 徽记在 16..68）

func top_left() -> void:
	var o := Vector2(16, 12)
	var low: bool = g.hp / g.max_hp < 0.3
	var hs := Vector2(sin(g.t * 90.0), cos(g.t * 70.0)) * 3.0 * g.hp_shake / 0.35
	shade(Rect2(8, 4, 260, 78))
	var x := HX
	# HP：小标签 + 粗体大数字 + 小字上限；护盾菱形跟在小标签后
	var cw: float = cap(Vector2(x, o.y + 9), "HP", 7, UI.RED if low else UI.SUB)
	for q in g.shield_max:
		UI.diamond(g.hud, Vector2(x + cw + 9 + q * 9, o.y + 6), 3.0, Color(0.5, 0.85, 1.0) if q < g.shield else Color(1, 1, 1, 0.14), Color(0.6, 0.9, 1.0, 0.8))
	var hpc: Color = UI.RED.lerp(Color(1, 0.8, 0.85), 0.5 + 0.5 * sin(g.t * 10.0)) if low else UI.TEXT
	var w: float = big(Vector2(x, o.y + 36) + hs, "%d" % int(g.hp), 26, hpc)
	cap(Vector2(x + w + 5, o.y + 35) + hs, "/ %d" % int(g.max_hp), 8)
	line_bar(x, o.y + 43 + hs.y, 150, g.hp / g.max_hp, UI.RED if low else HP_COL, 2.0, [], g.hp_trail / g.max_hp)
	h.corrode_seg(Rect2(Vector2(x, o.y + 43) + hs, Vector2(150, 2)), 1.0)
	# LAMP：小标签 + 数字 + 金线（30 / 70 刻度）
	var lamp_low: bool = g.lamp < 30.0
	var lc: Color = UI.GOLD if not lamp_low else UI.RED.lerp(UI.GOLD, 0.5 + 0.5 * sin(g.t * 8.0))
	cap(Vector2(x, o.y + 59), "LAMP", 7, lc)
	big(Vector2(x + 34, o.y + 60), "%d" % int(g.lamp), 11, lc)
	line_bar(x + 60, o.y + 55, 90, g.lamp / 100.0, lc, 2.0, [0.3, 0.7])
	# 神经损伤 / 侵蚀：生命线下方一道洋红细线
	if g.nerve > 1.0:
		line_bar(x + 160, o.y + 43, 46, g.nerve / 100.0, Color(1.0, 0.45, 0.85), 2.0)
		cap(Vector2(x + 160, o.y + 38), "NERVE", 6, Color(1.0, 0.5, 0.9))
	if g.corrode_pool > 0.5:
		txt(Vector2(x + 160, o.y + 62), "蚀", 11, Color(0.8, 0.5, 1.0))
	h.bars.draw_recall(o + Vector2(26, 30))


# ================================================================ 左上：队友生命（突击时常显，其余模式有人受伤 / 倒地才显示）

const MATE_Y := 82.0
const MATE_ROW := 15.0


## 手机局内正文放大（UI.fk），队友行往下让、行距加大，免得压灯火行
func _my() -> float:
	return MATE_Y + (14.0 if Cfg.phone_ui() else 0.0)


func _mrow() -> float:
	return MATE_ROW + (4.0 if Cfg.phone_ui() else 0.0)

func mates_shown(ms: Array) -> bool:
	if ms.is_empty():
		return false
	if g.squad.stance == g.squad.ROAM:
		return true
	return ms.any(func(o): return o.cmd_down > 0.0 or o.cmd_hp < 0.999)


## 队友生命占的高度（状态行跟着下移）；不显示时 0
func mates_h(ms: Array) -> float:
	return (_my() - MATE_Y) + 12.0 + ms.size() * _mrow() + 4.0 if mates_shown(ms) else 0.0


func mates(ms: Array) -> void:
	if not mates_shown(ms):
		return
	var roam: bool = g.squad.stance == g.squad.ROAM
	var x := HX
	var y: float = _my()
	var row: float = _mrow()
	g.hud.draw_rect(Rect2(x - 8, y - 4, 1, ms.size() * row + 12), LINE_DIM)
	var lw: float = cap(Vector2(x, y + 4), "SQUAD HP", 5.5, UI.CYAN if roam else UI.SUB, 1.2)
	if roam:
		txt(Vector2(x + lw + 6, y + 5), "突击中", 8, UI.CYAN)
	var bm: Dictionary = LinkBond.members(LinkBond.formed_now(g))
	var bx: float = x + (70.0 if Cfg.phone_ui() else 52.0)   # 手机名字放大，条往右让
	var bw: float = 74.0 if not Cfg.phone_ui() else 60.0
	for i in ms.size():
		var o = ms[i]
		var yy: float = y + 16.0 + i * row
		var down: bool = o.cmd_down > 0.0
		var hp: float = clampf(o.cmd_hp, 0.0, 1.0)
		var col: Color = HP_COL if hp > 0.5 else (UI.GOLD if hp > 0.25 else UI.RED)
		var oc: Color = Character.CLASS_COL.get(o.cls, UI.CYAN)
		g.hud.draw_rect(Rect2(x, yy - 8, 2, 9), oc)
		if bm.has(str(o.id)):
			UI.diamond(g.hud, Vector2(x - 4, yy - 4), 2.4, UI.GOLD)
		txt(Vector2(x + 6, yy), o.display_name().substr(0, 4), 9, Color(0.85, 0.88, 0.89) if not down else Color(0.6, 0.62, 0.65))
		if down:
			var k: float = 1.0 - clampf(o.cmd_down / maxf(0.1, Bal.v("command/revive_secs", 25.0)), 0.0, 1.0)
			line_bar(bx, yy - 4, bw, k, Color(0.55, 0.57, 0.6), 2.0)
			txt(Vector2(bx + bw + 6, yy), "倒地 %d" % int(ceil(o.cmd_down)), 9, UI.GOLD if h.allyhp.boosted(o) else UI.RED)
		else:
			var lag: float = h.allyhp.lag_of(o)
			line_bar(bx, yy - 4, bw, hp, col, 2.0, [], lag)
			big(Vector2(bx + bw + 6, yy), "%d" % int(round(hp * 100.0)), 8.5, col)
			if h.allyhp.low(o):
				g.hud.draw_rect(Rect2(bx - 2, yy - 7, bw + 4, 8), Color(UI.RED.r, UI.RED.g, UI.RED.b, 0.25 * h.allyhp.pulse()), false, 1.0)


# ================================================================ 左上：状态行

## 灯火档一句短话（原「灯火状态条」并进状态行最前面）
func lamp_item() -> Array:
	if g.lamp <= 0.0:
		return ["灯火寂灭", UI.RED, -1.0]
	if g.lamp < 30.0:
		return ["灯火暗淡", Color(1, 0.5, 0.5), -1.0]
	if g.lamp >= 70.0:
		return ["灯火通明", UI.GOLD, -1.0]
	return ["灯火摇曳", Color(1.0, 0.85, 0.6), -1.0]


## 状态行：「STATUS」小标签 + 用「/」隔开的一行字（状态色压淡），最多两行，放不下收成「+N」
func status(vs: Vector2, items: Array, y0: float) -> float:
	var all: Array = [lamp_item()] + items
	if Cfg.phone_ui() and all.size() > 3:
		all = all.slice(0, 2) + [["+%d" % (all.size() - 2), UI.SUB, -1.0]]
	var x0 := 18.0
	var wrap_x: float = 380.0
	if not h.bars.boss_bars().is_empty():
		wrap_x = minf(380.0, vs.x / 2.0 - minf(h.bars.BB_W_MAX, vs.x * 0.5) / 2.0 - 8.0)
	var y: float = y0 + 10.0
	shade(Rect2(6, y0 - 4, wrap_x, 22))
	var x: float = x0 + cap(Vector2(x0, y), "STATUS", 6, UI.SUB, 1.3) + 14.0
	var row := 0
	for i in all.size():
		var it: Array = all[i]
		var s: String = it[0]
		var col: Color = (it[1] as Color).lerp(UI.TEXT, 0.45)
		var w: float = twidth(s, 10)
		if x + w > wrap_x and x > x0 + 60.0:
			if row >= 1:
				txt(Vector2(x, y), "+%d" % (all.size() - i), 10, UI.SUB)
				break
			row += 1
			x = x0 + 52.0
			y += 17.0
		txt(Vector2(x, y), s, 10, col)
		if float(it[2]) >= 0.0:
			g.hud.draw_rect(Rect2(x, y + 3, w * float(it[2]), 1), Color(it[1].r, it[1].g, it[1].b, 0.8))
		x += w
		if i < all.size() - 1:
			txt(Vector2(x + 4, y), "/", 10, Color(1, 1, 1, 0.3))
			x += 14.0
	return y + 10.0


# ================================================================ 顶部中央

func top_center(vs: Vector2) -> void:
	var display_time: float = maxf(0.0, g.t - g.trial.started_at) if g.trial.active else g.t
	var mm := int(display_time) / 60
	var ss := int(display_time) % 60
	var cx := vs.x / 2.0
	var ph: bool = Cfg.phone_ui()
	var bs: float = 20.0 if ph else 26.0
	var nb: float = 36.0 if ph else 40.0
	shade(Rect2(cx - 170, 4, 340, 74 if not ph else 52), 0.26)
	cap(Vector2(cx - 18, 15), "KILLS", 6.5, UI.SUB, 1.6, 2)
	big(Vector2(cx - 18, nb), str(g.kills), bs, UI.TEXT, 2)
	g.hud.draw_rect(Rect2(cx - 0.5, 8, 1, nb - 6), LINE)
	cap(Vector2(cx + 18, 15), "TIME", 6.5)
	big(Vector2(cx + 18, nb), "%02d:%02d" % [mm, ss], bs)
	var tr: Dictionary = D.THREAT[g.threat]
	var fname: String = "Boss 演练" if g.trial.active else tr.name
	var fen: String = "TRIAL" if g.trial.active else String(tr.get("en", ""))
	var thr: String = "不记录通关进度" if g.trial.active else ("威胁 %s" % ["Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ", "Ⅴ", "Ⅵ"][g.threat]) + (("  ·  %s" % D.tier_name(g.tier)) if g.tier > 0 else "")
	if ph:
		txt(Vector2(cx - 150, nb + 21), fname + "  ·  " + thr, 10, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 300)
		return
	txt(Vector2(cx - 150, 58), fname, 11, Color(0.82, 0.85, 0.87), HORIZONTAL_ALIGNMENT_CENTER, 300)
	cap(Vector2(cx, 70), fen.to_upper() + ("  ·  THREAT " + ["I", "II", "III", "IV", "V", "VI"][g.threat] if not g.trial.active else ""), 6, UI.SUB, 2.0, 1)
	var tfrac: float = 1.0
	if g.threat < D.THREAT.size() - 1:
		tfrac = clampf((g.t - tr.t) / (D.THREAT[g.threat + 1].t - tr.t), 0.0, 1.0)
	var tcol := Color(0.9, 0.45, 1.0).lerp(UI.RED, float(g.threat) / (D.THREAT.size() - 1))
	line_bar(cx - 60, 76, 120, tfrac, tcol, 1.0)
	if g.tier > 0 or g.trial.active:   # 难度档 / 演练说明：一行小字（威胁已并进上面的英文行）
		txt(Vector2(cx - 150, 88), D.tier_name(g.tier) if not g.trial.active else thr, 9, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 300)


# ================================================================ 右上：源石锭 / 藏品 / 暂停 / 倍速（手机多一块属性）

const RT_Y := 14.0
const PLATE := Vector2(40.0, 24.0)
const PLATE_T := Vector2(54.0, 32.0)   # 触屏：11-06 用户「右上角的大小都有点小」，小牌放大约 1.35 倍（也是点击区）


func plate_size() -> Vector2:
	return PLATE_T if g.touch.active else PLATE

## 右上小牌的矩形（从右往左：倍速、暂停、手机再加属性）；点击区由 hud_relics.update_buttons / touch 用同一份
func plates(vs: Vector2) -> Dictionary:
	var out := {}
	var x: float = vs.x - 16.0
	var L: Dictionary = g.touch.layout(vs) if g.touch.active else {}
	var ps: Vector2 = plate_size()
	for k in (["speed", "pause", "stats"] if g.touch.active else ["speed", "pause"]):
		var e = L.get(k)
		if e != null and e.custom:
			# 玩家在「触屏按键布局」里挪过这个键：照他的位置（同一种小牌，大小跟缩放）
			var sz: Vector2 = ps * float(e.s)
			out[k] = Rect2(e.c - sz / 2.0, sz)
			continue
		x -= ps.x
		out[k] = Rect2(x, RT_Y + 12.0, ps.x, ps.y)
		x -= 4.0 if ps.x <= PLATE.x else 6.0
	out["left"] = x
	return out


func right_top(vs: Vector2) -> void:
	var P: Dictionary = plates(vs)
	var right: float = P.left - 12.0
	# 藏品：最近 3 件（手机只留数字）+「RELICS」+ 粗体数
	g.tray_cells.clear()
	var n: int = g.relics.size()
	var icons: int = 0 if Cfg.phone_ui() else mini(3, n)
	var x: float = right - icons * 28.0
	var mouse := g.hud.get_local_mouse_position()
	for k in icons:
		var id: String = g.relics[n - icons + k]
		var r := Rect2(x + k * 28.0, RT_Y + 12.0, 24.0, 24.0)
		var ic: Texture2D = g.tex.get("relic_" + id)
		if ic != null:
			g.hud.draw_texture_rect(ic, r, false)
		if r.has_point(mouse):
			g.hud.draw_rect(r.grow(1.0), UI.CYAN, false, 1.0)
		g.tray_cells.append([r, id])
	var tch: bool = g.touch.active   # 触屏（11-06 用户「右上角的属性没标出来，大小都有点小」）：数字 22 → 28，标签换中文 11 号
	var bf: int = 28 if tch else 22
	var nw: float = UI.latin().get_string_size(str(n), HORIZONTAL_ALIGNMENT_LEFT, -1, bf).x
	var rx: float = x - 8.0 - maxf(nw, 26.0 if tch else 0.0)
	shade(Rect2(rx - 70, 4, vs.x - rx + 66, 58 if tch else 44), 0.26)
	if tch:
		txt(Vector2(rx, RT_Y + 8), "藏品", 11, UI.SUB)
	else:
		cap(Vector2(rx, RT_Y + 9), "RELICS", 6.5)
	big(Vector2(rx, RT_Y + (40 if tch else 34)), str(n), bf)
	# 源石锭
	var iw: float = UI.latin().get_string_size(str(g.ingots), HORIZONTAL_ALIGNMENT_LEFT, -1, bf).x
	var ix: float = rx - 20.0 - maxf(iw, 40.0)
	if tch:
		txt(Vector2(ix, RT_Y + 8), "源石锭", 11, UI.GREEN)
	else:
		cap(Vector2(ix, RT_Y + 9), "INGOT", 6.5, UI.GREEN)
	big(Vector2(ix, RT_Y + (40 if tch else 34)), str(g.ingots), bf)
	# 小牌：深底细边；倍速 ≠ 1 时反白（纸白）提醒「现在是快进」
	var lab: String = PlayClock.current_label()
	var fast: bool = PlayClock.current_speed() != 1.0
	for k in P:
		if k == "left":
			continue
		var r: Rect2 = P[k]
		var paper: bool = k == "speed" and fast
		var lit: bool = (k == "pause" and g.state == Game.S.PAUSE) or (k == "stats" and g.state == Game.S.STATS)
		g.hud.draw_rect(r, UI.PAPER if paper else Color(0.047, 0.055, 0.063, 0.9))
		g.hud.draw_rect(r, UI.CYAN if lit else Color(1, 1, 1, 0.24), false, 1.0)
		var inkc: Color = Color(0.06, 0.07, 0.08) if paper else UI.TEXT
		if tch:   # 触屏：牌里直接写中文（属性键原来只有一个「≡」+ 5.5 号 INFO，看不出是什么）
			var cn: String = {"speed": lab, "pause": "暂停", "stats": "属性"}[k]
			var cf: Font = UI.latin() if k == "speed" else g.font
			var cs: int = int(round(15.0 * r.size.y / PLATE_T.y)) if k == "speed" else UI._ks(g.hud, int(round(13.0 * r.size.y / PLATE_T.y)))
			var cw: float = cf.get_string_size(cn, HORIZONTAL_ALIGNMENT_LEFT, -1, cs).x
			g.hud.draw_string(cf, Vector2(r.get_center().x - cw / 2.0, r.get_center().y + cs * 0.36), cn, HORIZONTAL_ALIGNMENT_LEFT, -1, cs, inkc)
			continue
		cap(Vector2(r.position.x, r.position.y - 5), {"speed": "SPEED", "pause": "PAUSE", "stats": "INFO"}[k], 5.5)
		var s: String = {"speed": lab, "pause": "II", "stats": "≡"}[k]
		var f: Font = UI.latin() if k != "stats" else g.font
		var fs: int = 12 if k == "speed" else 13
		var sw: float = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		g.hud.draw_string(f, Vector2(r.get_center().x - sw / 2.0, r.position.y + 17), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, inkc)
	if not g.touch.active:
		cap(Vector2(vs.x - 16, RT_Y + 46), "ESC  ·  V", 5.5, UI.SUB, 1.4, 2)
	if not g.trial.active and (g.ending != "standard" or Cfg.endings_cleared.size() > 0):
		txt(Vector2(vs.x - 236, RT_Y + (72 if g.touch.active else 62)), g.endg.cur_name(), 11, g.endg.cur_col(), HORIZONTAL_ALIGNMENT_RIGHT, 220)


# ================================================================ 右下：编队（四格指挥 + 全身立绘卡）

const CARD := Vector2(55.0, 68.0)   # 立绘窗（@2x 待机帧裁 79×102 → 设计单位 ×2/3）
const NAME_H := 11.0
const GAP := 6.0
const SEG_H := 22.0   # 11-04 18 → 22：四格字号 10 → 13（用户「看不清指挥模式」）

func squad_size(n: int) -> Vector2:
	return Vector2(maxf(4, n) * (CARD.x + GAP) - GAP, 12.0 + SEG_H + 8.0 + CARD.y + NAME_H)


## 编队块左上角（右下对齐 br）
func squad_origin(br: Vector2) -> Vector2:
	var s: Vector2 = squad_size(g.squad.size())
	return br - s


func card_rect(br: Vector2, i: int) -> Rect2:
	var o: Vector2 = squad_origin(br)
	var n: int = g.squad.size()
	var x0: float = br.x - n * (CARD.x + GAP) + GAP
	return Rect2(Vector2(x0 + i * (CARD.x + GAP), o.y + 12.0 + SEG_H + 8.0), CARD)


func seg_index() -> int:
	var sq = g.squad
	if sq.Tactics.on() and sq.order_kind == "point":
		return 2
	if sq.order_kind == "focus":
		return 3
	return 1 if sq.stance == sq.ROAM else 0


func squad(br: Vector2) -> void:
	var n: int = g.squad.size()
	if n <= 0:
		return
	var sz: Vector2 = squad_size(n)
	var o: Vector2 = br - sz
	shade(Rect2(o - Vector2(10, 8), sz + Vector2(20, 14)), 0.34)
	var cmd: bool = g.squad.cmd_on()
	# 小标签行：COMMAND · F / BOND n / SQUAD n/m
	if cmd:
		cap(o + Vector2(0, 8), "COMMAND" + ("" if g.touch.active else "  ·  " + (Pad.GLYPH.LB if Pad.using else "F")), 6.5)
	var sq_s := "SQUAD %d/%d" % [n, g.squad.cap()]
	var sw: float = cap(Vector2(br.x, o.y + 8), sq_s, 6.5, UI.SUB, 1.6, 2)
	var nb: int = LinkBond.formed_now(g).size()
	if nb > 0:
		cap(Vector2(br.x - sw - 12, o.y + 8), "BOND %d" % nb, 6.5, UI.GOLD, 1.6, 2)
	# 四格分段：只显示当前模式（切换照旧用 F 圆盘 / 触屏指挥键；用户 11-02「不要点格子」）
	var sr := Rect2(o + Vector2(0, 12), Vector2(sz.x, SEG_H))
	if cmd:
		g.hud.draw_rect(sr, Color(0.04, 0.047, 0.055, 0.86))
		g.hud.draw_rect(sr, Color(1, 1, 1, 0.24), false, 1.0)
		var cur: int = seg_index()
		var cw: float = sr.size.x / 4.0
		for k in 4:
			var cr := Rect2(sr.position + Vector2(k * cw, 0), Vector2(cw, SEG_H))
			# 11-04 用户「看不清指挥模式」：当前格青底 + 白框 + 左侧三角标记、字加大；其余三格字用正文色（原来是暗灰 SUB）
			if k == cur:
				g.hud.draw_rect(cr, UI.CYAN)
				g.hud.draw_rect(cr.grow(1.0), Color(1, 1, 1, 0.9), false, 1.5)
				var ty: float = cr.get_center().y
				g.hud.draw_colored_polygon(PackedVector2Array([Vector2(cr.position.x + 5, ty - 4), Vector2(cr.position.x + 10, ty), Vector2(cr.position.x + 5, ty + 4)]), Color(0.055, 0.063, 0.07))
			elif k > 0 and k != cur + 1:
				g.hud.draw_rect(Rect2(cr.position.x, cr.position.y + 4, 1, SEG_H - 8), Color(1, 1, 1, 0.28))
			var c: Color = Color(0.055, 0.063, 0.07) if k == cur else Color(UI.TEXT.r, UI.TEXT.g, UI.TEXT.b, 0.82)
			g.hud.draw_string(g.font, Vector2(cr.position.x, cr.position.y + SEG_H - 6), SEG_NAMES[k], HORIZONTAL_ALIGNMENT_CENTER, cw, UI._ks(g.hud, 13), c)
		# 突击耐力（全队共用）：分段下沿一根细线
		var sqd = g.squad
		if sqd.stamina_on():
			var fc: Color = UI.GOLD if sqd.stance == sqd.ROAM else (Color(0.5, 0.52, 0.55) if sqd.exhausted else UI.CYAN)
			g.hud.draw_rect(Rect2(sr.position.x, sr.end.y + 2, sr.size.x * clampf(sqd.stamina, 0.0, 1.0), 1.5), fc)
	# 卡
	var bm: Dictionary = LinkBond.members(LinkBond.formed_now(g))
	for i in n:
		var op = g.squad.ops[i]
		var r: Rect2 = card_rect(br, i)
		g.hud.draw_rect(r, Color(0.04, 0.047, 0.055, 0.82))
		_portrait(op, r)
		var oc: Color = Character.CLASS_COL.get(op.cls, UI.CYAN)
		g.hud.draw_rect(Rect2(r.position, Vector2(r.size.x, 1.5)), oc)   # 职业色顶线
		if bm.has(str(op.id)):
			UI.diamond(g.hud, r.position + Vector2(r.size.x - 5, 6), 2.6, UI.GOLD)
		var lead: bool = op == g.ch
		var nr := Rect2(Vector2(r.position.x, r.end.y), Vector2(r.size.x, NAME_H))
		g.hud.draw_rect(nr, UI.PAPER if lead else Color(0.055, 0.063, 0.07, 0.95))
		if not Cfg.phone_ui():
			g.hud.draw_string(g.font, Vector2(nr.position.x, nr.end.y - 2), op.display_name().substr(0, 5), HORIZONTAL_ALIGNMENT_CENTER, nr.size.x, UI._ks(g.hud, 8), Color(0.06, 0.07, 0.08) if lead else UI.TEXT)
		if lead:
			var sub_on: bool = op.has_method("away") and op.away()
			var tr := Rect2(r.position + Vector2(0, -10), Vector2(30, 10))
			g.hud.draw_rect(tr, Color(0.055, 0.063, 0.07, 0.95))
			cap(tr.position + Vector2(3, 7.5), "SUB" if sub_on else "LEADER", 4.8, UI.TEXT, 0.8)
		# 倒地：暗幕 + 读秒；残血：红框慢闪；技能生效：青色细框
		if not op.is_leader and op.cmd_down > 0.0:
			g.hud.draw_rect(r, Color(0, 0, 0, 0.55))
			g.hud.draw_string(g.font, Vector2(r.position.x, r.get_center().y), "倒地", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, UI._ks(g.hud, 10), UI.RED)
			big(Vector2(r.get_center().x, r.get_center().y + 16), str(int(ceil(op.cmd_down))), 14, UI.TEXT, 1)
		elif not op.is_leader and h.allyhp.low(op):
			var p: float = h.allyhp.pulse()
			g.hud.draw_rect(r.grow(1.0), Color(UI.RED.r, UI.RED.g, UI.RED.b, 0.35 + 0.6 * p), false, 1.5)
		elif op.skill_active():
			g.hud.draw_rect(r, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.8), false, 1.0)


## @2x 待机帧全身（四人同一裁切窗：帧内第 24–126 行 × 79 宽，按身体中心取；docs/222 §15.3），整数比例最近邻，裁在卡里
func _portrait(op, r: Rect2) -> void:
	var art: Dictionary = h.ult._art_of(op)
	if art.is_empty():
		return
	var t: Texture2D = art.tex
	var bb: Rect2 = art.bb
	var fh: float = float(t.get_height())
	var k: float = fh / 128.0
	var src := Rect2(bb.get_center().x - 39.5 * k, 24.0 * k, 79.0 * k, 102.0 * k)
	src.position.x = clampf(src.position.x, 0.0, maxf(0.0, fh - src.size.x))   # 帧是 fh×fh 的正方形，帧 0 在最左
	g.hud.draw_texture_rect_region(t, r, src)
