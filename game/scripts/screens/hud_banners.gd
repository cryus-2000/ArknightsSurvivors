extends RefCounted
## 界面 · HUD 提示与指示（2026-10-10 从 hud.gd 拆出，docs/55 §6）：主控身边的僵直 / 挣脱提示、商人 / 祭坛 / Boss / 灯标的屏外指示、
## 全场地波、黑潮警告与方向提示、横幅通知与小字通知、开局提示、冲刺提示。触屏分支原样保留。
const Bars = preload("res://scripts/screens/hud_bars.gd")   # Bars.BOSS_BARS_MAX
const D = preload("res://scripts/data.gd")
const Bal = preload("res://scripts/core/balance.gd")
const UI = preload("res://scripts/ui.gd")
const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game
var h   # screens/hud.gd：合批段（batch_begin / _hb）、共用助手（edge_glow / corrode_seg / draw_tooltip）与兄弟模块都从这里取


func _init(hud) -> void:
	h = hud
	g = hud.g


## 主控身边：僵直字样、冻结 / 束缚「冲刺挣脱」提示
func draw_leader_hints(ct: Transform2D) -> void:
	if g.pstun > 0.0:
		UI.text(g.hud, g.font, ct * g.ppos + Vector2(-40, -110), "僵直", 16, Color(1.0, 0.5, 0.9), HORIZONTAL_ALIGNMENT_CENTER, 80, 3)
	if g.root_t > 0.0 and g.state == Game.S.PLAY:
		# 冻结 / 束缚：脚下提示「冲刺挣脱」（键位随输入设备），跳动吸引注意
		var fz: bool = g.world.leader_frozen()
		var bp: float = absf(sin(g.t * 8.0)) * 4.0
		var key: String = "冲刺键" if g.touch.active else Pad.hint("空格", "Ⓑ")
		UI.text(g.hud, g.font, ct * g.ppos + Vector2(-90, 58 + bp), "%s！按 %s 冲刺挣脱" % [g.world.root_label(), key], 15, Color(0.7, 0.92, 1.0) if fz else Color(0.85, 0.6, 1.0), HORIZONTAL_ALIGNMENT_CENTER, 180, 4)


## 商人方向指示：屏外时边缘圆圈 + 头像 + 箭头 + 距离；屏内时头顶跳动箭头
func draw_merchant_pointer(vs: Vector2, ct: Transform2D) -> void:
	# 商人方向指示
	if not g.merchant.is_empty():
		var sp: Vector2 = ct * g.merchant.pos
		var bounce := absf(sin(g.t * 5.0)) * 8.0
		var mf := int(g.t * 2.0) % 2
		if not Rect2(Vector2(60, 60), vs - Vector2(120, 120)).has_point(sp):
			var c := vs / 2.0
			var d := (sp - c).normalized()
			var edge: Vector2 = c + d * min(abs((vs.x / 2 - 64) / max(abs(d.x), 0.01)), abs((vs.y / 2 - 64) / max(abs(d.y), 0.01)))
			var pulse := 0.5 + 0.5 * sin(g.t * 6.0)
			g.hud.draw_circle(edge, 30.0 + 4.0 * pulse, Color(1.0, 0.7, 0.3, 0.12))
			g.hud.draw_circle(edge, 24.0, Color(0.06, 0.05, 0.03, 0.85))
			g.hud.draw_arc(edge, 24.0, 0.0, TAU, 28, UI.GOLD, 2.0)
			var mt: Texture2D = g.tex.merchant
			var fw := mt.get_width() / 2
			# 头像整体缩放到直径 40 的圆圈里居中（高清 48px 图缩到 0.8，像素 20px 图放大 2 倍）
			var msc: float = minf(40.0 / float(fw), 40.0 / float(mt.get_height()))
			msc = floorf(msc) if msc >= 1.0 else msc
			var msz := Vector2(fw, mt.get_height()) * msc
			g.hud.draw_texture_rect_region(mt, Rect2((edge - msz * 0.5).round(), msz), Rect2(fw * mf, 0, fw, mt.get_height()))
			# 指向商人的箭头
			var tip: Vector2 = edge + d * (40.0 + 5.0 * pulse)
			var base: Vector2 = edge + d * 28.0
			var sd := d.orthogonal() * 10.0
			g.hud.draw_colored_polygon(PackedVector2Array([tip, base + sd, base - sd]), UI.GOLD)
			var dist := int(g.merchant.pos.distance_to(g.ppos) / 32.0)
			# 文字放在圆圈（半径 24 + 光晕）之外：下半屏放上方，上半屏放下方
			var lab_y := -40.0 if edge.y > vs.y / 2 else 54.0
			UI.text(g.hud, g.font, edge + Vector2(-60, lab_y), "商人  %dm · %ds" % [dist, int(g.merchant.life)], 13, g.shop_sys.merchant_col(), HORIZONTAL_ALIGNMENT_CENTER, 120, 3)
		else:
			# 在画面内：头顶跳动的箭头
			var big_m: bool = g.tex.merchant != null and g.tex.merchant.get_height() >= 40
			var head: float = (84.0 if big_m else 36.0) * ct.get_scale().y
			var hp2 := sp + Vector2(0, -head - 12.0 - bounce)
			g.hud.draw_colored_polygon(PackedVector2Array([hp2 + Vector2(0, 12), hp2 + Vector2(-10, -2), hp2 + Vector2(10, -2)]), UI.GOLD)
			UI.text(g.hud, g.font, hp2 + Vector2(-60, -8), ("商人 %ds" if g.merchant.life > 15.0 else "商人即将离开 %ds") % int(g.merchant.life), 13, g.shop_sys.merchant_col(), HORIZONTAL_ALIGNMENT_CENTER, 140, 3)


## 海嗣祭坛方位指示（屏内头顶箭头 / 屏外边缘圈）；最终 Boss 前 10 秒未开的祭坛金红快闪
func draw_altar_pointers(vs: Vector2, ct: Transform2D) -> void:
	# 海嗣祭坛方位指示（屏幕外）；最终 Boss 登场前 10 秒还有没开的祭坛（g.endg.urgent）：指示变金红快闪、写「即将沉没」
	var urgent: bool = g.endg != null and g.endg.get("urgent") == true
	var uk: float = absf(sin(g.t * 9.0)) if urgent else 0.0
	var acol: Color = Color(0.55, 0.8, 1.0).lerp(Color(1.0, 0.45, 0.3), uk) if urgent else Color(0.55, 0.8, 1.0)
	for e in g.enemies:
		if not e.chest or e.dead or e.get("event", "") == "":
			continue
		var spb: Vector2 = ct * e.pos
		if Rect2(Vector2(60, 60), vs - Vector2(120, 120)).has_point(spb):
			var hb := spb + Vector2(0, -60 - absf(sin(g.t * 5.0)) * 8.0)
			g.hud.draw_colored_polygon(PackedVector2Array([hb + Vector2(0, 12), hb + Vector2(-10, -2), hb + Vector2(10, -2)]), acol)
			UI.text(g.hud, g.font, hb + Vector2(-90, -8), "海嗣祭坛" if not urgent else "海嗣祭坛 · 即将沉没", 13, acol, HORIZONTAL_ALIGNMENT_CENTER, 180, 3)
		else:
			var cc := vs / 2.0
			var dd := (spb - cc).normalized()
			var edge2: Vector2 = cc + dd * min(abs((vs.x / 2 - 64) / max(abs(dd.x), 0.01)), abs((vs.y / 2 - 64) / max(abs(dd.y), 0.01)))
			var pl := 0.5 + 0.5 * sin(g.t * 6.0)
			if urgent:
				g.hud.draw_circle(edge2, 32.0 + 8.0 * uk, Color(1.0, 0.45, 0.3, 0.25 * uk))
			g.hud.draw_circle(edge2, 24.0, Color(0.03, 0.05, 0.1, 0.85))
			g.hud.draw_arc(edge2, 24.0, 0.0, TAU, 28, acol, 2.0)
			var et2: Texture2D = g.tex.e_event
			g.hud.draw_texture_rect_region(et2, Rect2(edge2 - Vector2(13, 15), Vector2(26, 30)), Rect2(0, 0, 26, 30))
			var tip2: Vector2 = edge2 + dd * (40.0 + 5.0 * pl)
			var base2: Vector2 = edge2 + dd * 28.0
			var sd2 := dd.orthogonal() * 10.0
			g.hud.draw_colored_polygon(PackedVector2Array([tip2, base2 + sd2, base2 - sd2]), acol)
			UI.text(g.hud, g.font, edge2 + Vector2(-60, -34.0 if edge2.y > vs.y / 2 else 44.0), ("海嗣祭坛 %dm" if not urgent else "即将沉没 %dm") % int(e.pos.distance_to(g.ppos) / 32.0), 13, acol, HORIZONTAL_ALIGNMENT_CENTER, 120, 3)


## Boss 屏外指示（docs/48 P1：Boss 在屏幕外登场，商人和祭坛都有指示，Boss 没有）：
## 屏幕边缘一个洋红红圈（比商人 / 祭坛大一号、双圈、脉动），里面是 Boss 常态帧头像，外侧箭头指向 Boss，旁边写名字和距离
const BOSS_PTR_COL := Color(1.0, 0.28, 0.42)

func draw_boss_pointers(vs: Vector2, ct: Transform2D) -> void:
	if g.state != Game.S.PLAY:
		return
	var placed: Array = []   # 同一方向的两只 Boss（接潮双体）：后画的沿屏幕边挪开，不叠在一起
	for b in h.bars.hostile_boss_bars():
		var sp: Vector2 = ct * b.pos
		if Rect2(Vector2(40, 40), vs - Vector2(80, 80)).has_point(sp):
			continue
		var c := vs / 2.0
		var d := (sp - c).normalized()
		var edge: Vector2 = c + d * minf(absf((vs.x / 2 - 72) / maxf(absf(d.x), 0.01)), absf((vs.y / 2 - 72) / maxf(absf(d.y), 0.01)))
		var tries := 0
		while tries < 4 and placed.any(func(p): return p.distance_to(edge) < 76.0):
			var tn: Vector2 = Vector2(0, 1) if absf(edge.x - vs.x / 2.0) > absf(edge.y - vs.y / 2.0) * vs.x / vs.y else Vector2(1, 0)
			edge = (edge + tn * 80.0).clamp(Vector2(72, 72), vs - Vector2(72, 72))
			tries += 1
		placed.append(edge)
		var pulse := 0.5 + 0.5 * sin(g.t * 7.0)
		g.hud.draw_circle(edge, 36.0 + 5.0 * pulse, Color(BOSS_PTR_COL.r, BOSS_PTR_COL.g, BOSS_PTR_COL.b, 0.14))
		g.hud.draw_circle(edge, 28.0, Color(0.07, 0.02, 0.04, 0.88))
		g.hud.draw_arc(edge, 28.0, 0.0, TAU, 32, BOSS_PTR_COL, 2.0)
		g.hud.draw_arc(edge, 32.0, 0.0, TAU, 32, Color(BOSS_PTR_COL.r, BOSS_PTR_COL.g, BOSS_PTR_COL.b, 0.35 + 0.4 * pulse), 1.0)
		var bt: Texture2D = g.tex.get(b.tex)
		if bt != null:
			var fw: int = bt.get_width() / 2   # 敌人常态帧条固定 2 帧（同 world 画敌人）
			var k: float = minf(44.0 / float(fw), 44.0 / float(bt.get_height()))
			k = floorf(k) if k >= 1.0 else k
			var sz := Vector2(fw, bt.get_height()) * k
			g.hud.draw_texture_rect_region(bt, Rect2((edge - sz * 0.5).round(), sz), Rect2(0, 0, fw, bt.get_height()))
		var tip: Vector2 = edge + d * (46.0 + 6.0 * pulse)
		var base: Vector2 = edge + d * 33.0
		var sd := d.orthogonal() * 12.0
		g.hud.draw_colored_polygon(PackedVector2Array([tip, base + sd, base - sd]), BOSS_PTR_COL)
		var nm: String = D.ENEMIES.get(b.type, {}).get("name", "Boss")
		var lab_y := -46.0 if edge.y > vs.y / 2 else 62.0
		UI.text(g.hud, g.font, edge + Vector2(-80, lab_y), "%s  %dm" % [nm, int(b.pos.distance_to(g.ppos) / 32.0)], 13, BOSS_PTR_COL, HORIZONTAL_ALIGNMENT_CENTER, 160, 3)


## 伊祖米克全场地波（act izu_wave，r 2400 圈在屏幕外看不到）：屏幕边缘白 / 洋红光脉动收紧 + 中央提示和倒计时 + 冲刺图标
func draw_field_wave(vs: Vector2) -> void:
	if g.state != Game.S.PLAY:
		return
	for w in g.warns:
		if w.done or w.get("act", "") != "izu_wave":
			continue
		var k: float = clampf(w.t / w.dur, 0.0, 1.0)
		var pk: float = 0.5 + 0.5 * sin(g.t * (8.0 + 10.0 * k))
		h.edge_glow(vs, Color(1.0, 0.35, 0.75, 0.35 + 0.45 * k * pk), 90.0 + 90.0 * k)
		var left: float = maxf(0.0, w.dur - w.t)
		var y: float = vs.y * 0.3
		UI.text(g.hud, g.font, Vector2(0, y), "全场地波  %.1f" % left, 22, Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 5)
		UI.text(g.hud, g.font, Vector2(0, y + 26), "躲进点亮的灯柱光圈，或者冲刺", 15, Color(1.0, 0.85, 0.55), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 4)
		var ic := Vector2(vs.x / 2.0, y - 34)
		for q in 3:
			var ox: float = -9.0 + q * 7.0
			g.hud.draw_line(ic + Vector2(ox, 6), ic + Vector2(ox + 6, -6), Color(0, 0, 0, 0.7), 5.0)
			g.hud.draw_line(ic + Vector2(ox, 6), ic + Vector2(ox + 6, -6), Color(1, 1, 1, 0.95), 2.5)
		break


## 未点燃的灯标在屏幕外：边缘暖金小圈 + 箭头 +「灯标 Nm」（同商人 / 祭坛指示）
func draw_beacon_pointers(vs: Vector2, ct: Transform2D) -> void:
	var bs = g.get("beacons")
	if g.state != Game.S.PLAY or not (bs is Array):
		return
	h.batch_begin()   # 圆底 / 圈 / 箭头一批 → 灯标小图 → 字（性能 9/30：原来每个指示 6 次绘制调用）
	var mid: Array = []
	for b in bs:
		if b.get("lit", false):
			continue
		var sp: Vector2 = ct * b.get("pos", Vector2.ZERO)
		if Rect2(Vector2(40, 40), vs - Vector2(80, 80)).has_point(sp):
			continue
		var c := vs / 2.0
		var d := (sp - c).normalized()
		var edge: Vector2 = c + d * minf(absf((vs.x / 2 - 64) / maxf(absf(d.x), 0.01)), absf((vs.y / 2 - 64) / maxf(absf(d.y), 0.01)))
		var col := Color(1.0, 0.78, 0.42)
		h._hb.circle(edge, 20.0, Color(0.06, 0.05, 0.03, 0.85), 24)
		h._hb.arc(edge, 20.0, 0.0, TAU, 2.0, col, 24)
		var tx: Texture2D = g.tex.get("prop_beacon")
		if tx != null:
			var fw: int = tx.get_width() / 2
			var k: float = 32.0 / float(tx.get_height())
			var dst := Rect2(edge - Vector2(fw, tx.get_height()) * k / 2.0, Vector2(fw, tx.get_height()) * k)
			mid.append(func(): g.hud.draw_texture_rect_region(tx, dst, Rect2(0, 0, fw, tx.get_height())))
		var tip: Vector2 = edge + d * 34.0
		var base: Vector2 = edge + d * 24.0
		var sd := d.orthogonal() * 8.0
		h._hb.poly(PackedVector2Array([tip, base + sd, base - sd]), col)
		UI.text(g.hud, g.font, edge + Vector2(-60, -30.0 if edge.y > vs.y / 2 else 42.0), "灯标 %dm" % int(b.get("pos", Vector2.ZERO).distance_to(g.ppos) / 32.0), 13, col, HORIZONTAL_ALIGNMENT_CENTER, 120, 3)
	h.batch_end(mid)


## 围猎（run/hunt.gd；用户 10-11「没有看到一个圈」）：顶栏下方「围猎 · 包围圈收缩  N」倒计时（预告期「围猎将至  N」）；
## 围猎紫边缘光（圈在画面外时更亮）；包围圈离主控最近的一段不在画面里时，画面边缘圆圈 + 箭头指向它并标距离。
## 生命垂危的红暗角优先。只读状态、只用 g.t
const HUNT_COL := Color(0.75, 0.5, 1.0)
func draw_hunt_pointer(vs: Vector2, ct: Transform2D) -> void:
	var hu = g.hunt
	if g.state != Game.S.PLAY or hu == null or (hu.state != 1 and hu.state != 2):
		return
	var pz := 0.5 + 0.5 * sin(g.t * 6.0)
	var zy := (126.0 if g.touch.active else 116.0) + 54.0 * mini(h.bars.boss_bars().size(), Bars.BOSS_BARS_MAX)   # 触屏的威胁字号大一号，再往下让 10
	if g.zone_state != 0:
		zy += 22.0   # 黑潮提示在场时让到它下面
	if hu.state == 1:
		UI.text(g.hud, g.font, Vector2(0, zy), "围猎将至  %d" % int(ceil(maxf(0.0, hu.start_at - g.t))), 15, Color(HUNT_COL.r, HUNT_COL.g, HUNT_COL.b, 0.7 + 0.3 * pz), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 3)
		return
	var dur: float = Bal.v("hunt/dur", 20.0) * float(g.dmod.get("hunt_dur", 1.0))
	var rem: int = int(ceil(maxf(0.0, dur - (g.t - hu.start_at))))
	UI.text(g.hud, g.font, Vector2(0, zy), "围猎 · 包围圈收缩  %d" % rem, 15, Color(HUNT_COL.r, HUNT_COL.g, HUNT_COL.b, 0.7 + 0.3 * pz), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 3)
	# 离主控最近的圈上一点
	var v: Vector2 = g.ppos - hu.c
	var d: Vector2 = v.normalized() if v.length() > 1.0 else Vector2.RIGHT
	var near: Vector2 = hu.c + d * hu.radius()
	var sp: Vector2 = ct * near
	var seen: bool = Rect2(Vector2(40, 40), vs - Vector2(80, 80)).has_point(sp)
	if not (g.hp < g.max_hp * 0.3 and g.hp > 0.0):
		h.edge_glow(vs, Color(HUNT_COL.r, HUNT_COL.g, HUNT_COL.b, (0.10 if seen else 0.28) + 0.12 * pz), 120.0)
	if seen:
		return
	var cc := vs / 2.0
	var dd := (sp - cc).normalized()
	var edge: Vector2 = cc + dd * minf(absf((vs.x / 2 - 64) / maxf(absf(dd.x), 0.01)), absf((vs.y / 2 - 64) / maxf(absf(dd.y), 0.01)))
	h.batch_begin()
	h._hb.circle(edge, 20.0, Color(0.05, 0.02, 0.08, 0.85), 24)
	h._hb.arc(edge, 20.0, 0.0, TAU, 2.0, HUNT_COL, 24)
	h._hb.arc(edge, 11.0, 0.0, TAU, 2.0, Color(HUNT_COL.r, HUNT_COL.g, HUNT_COL.b, 0.6 + 0.4 * pz), 16)
	var tip: Vector2 = edge + dd * (34.0 + 4.0 * pz)
	var base: Vector2 = edge + dd * 24.0
	var sd := dd.orthogonal() * 8.0
	h._hb.poly(PackedVector2Array([tip, base + sd, base - sd]), HUNT_COL)
	UI.text(g.hud, g.font, edge + Vector2(-60, -30.0 if edge.y > vs.y / 2 else 42.0), "包围圈 %dm" % int(near.distance_to(g.ppos) / 32.0), 13, HUNT_COL, HORIZONTAL_ALIGNMENT_CENTER, 120, 3)
	h.batch_end()


## 黑潮：圈外警告大字 + 紫色边缘光（生命垂危的红暗角优先）；圈内时顶栏下方倒计时 / 收缩提示
func draw_zone_warning(vs: Vector2) -> void:
	# 黑潮：圈外警告 + 指向安全区
	if g.zone_state != 0 and g.state == Game.S.PLAY:
		var out := g.ppos.distance_to(g.zone_c) - g.zone_r
		if out > 0.0:
			var pz := 0.5 + 0.5 * sin(g.t * 8.0)
			if not (g.hp < g.max_hp * 0.3 and g.hp > 0.0):   # 生命垂危的红暗角优先
				h.edge_glow(vs, Color(0.55, 0.1, 0.8, 0.4 + 0.3 * pz), 140.0)
			# 指向安全区的箭头与掉血倒计时见 draw_zone_hint
			UI.text(g.hud, g.font, Vector2(0, vs.y * 0.5 - 130), "身处黑潮！返回安全区", 20, Color(1.0, 0.7, 1.0, 0.7 + 0.3 * pz), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 5)
		else:
			# 顶栏楼层条下方；有 Boss 血条时再往下让出位置
			var zy := 116.0 + 54.0 * mini(h.bars.boss_bars().size(), Bars.BOSS_BARS_MAX)
			if g.zone_state == 1:
				UI.text(g.hud, g.font, Vector2(0, zy), "黑潮将至  %d" % int(ceil(20.0 - g.zone_t)), 15, Color(0.9, 0.6, 1.0), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 3)
			elif g.zone_state == 2:
				UI.text(g.hud, g.font, Vector2(0, zy), "安全区收缩中", 15, Color(0.9, 0.6, 1.0, 0.6 + 0.4 * sin(g.t * 6.0)), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 3)


## 横幅通知（Boss 登场名片 / 大群横幅在场时让位或下移）
func draw_banner(vs: Vector2) -> void:
	# 横幅通知
	var horde_band: bool = g.vfx.horde_band_on() and not g.panel.visible
	if g.banner_t > 0.0 and not g.panel.visible and g.state != Game.S.SHOW and g.state != Game.S.DEAD and (not horde_band or g.vfx.banner_prio >= 3) and not g.boss_intro.active():   # 精英化演出的遮罩只有 86%，横幅会透出来；Boss 登场名片在场时横幅让位（只是不画，计时照走）
		var a: float = clamp(g.banner_t, 0.0, 1.0)
		var by := banner_y(vs) if not horde_band else vs.y * 0.3 + 70.0   # 大群横幅在场时 Boss 横幅让到它下面
		if g.vfx.banner_small:
			# 同一句第二次起（反复放的技能名）：窄暗带 + 小字，不压满屏宽（EA 1.1 后期降噪）
			UI.fade_band(g.hud, Rect2(vs.x * 0.36, by - 22, vs.x * 0.28, 30), Color(0.03, 0.035, 0.045, 0.7 * a), 60.0)
			UI.text(g.hud, g.font, Vector2(0, by - 2), g.banner, 15, Color(1, 1, 1, 0.85 * a), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 3)
		else:
			# 两端渐隐的暗带 + 上下从中间向两边淡出的细线（原作提示横幅）
			UI.fade_band(g.hud, Rect2(vs.x * 0.12, by - 30, vs.x * 0.76, 46), Color(0.03, 0.035, 0.045, 0.84 * a), 160.0)
			for yy in [by - 30.0, by + 16.0]:
				UI.hairline(g.hud, Vector2(vs.x / 2.0, yy), Vector2(vs.x * 0.16, yy), Color(1, 1, 1), 0.4 * a, 0.0)
				UI.hairline(g.hud, Vector2(vs.x / 2.0, yy), Vector2(vs.x * 0.84, yy), Color(1, 1, 1), 0.4 * a, 0.0)
			UI.text(g.hud, g.font, Vector2(0, by), g.banner, 21, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 3)


## Boss 战期间的次要横幅改成左侧小字通知（vfx.notices）：横幅暗带下方、左对齐一行一条，4 秒淡出
func draw_notices(vs: Vector2) -> void:
	if g.state != Game.S.PLAY or g.vfx.notices.is_empty():
		return
	var y: float = banner_y(vs) + 44.0   # 横幅暗带下方，不和它叠
	for n in g.vfx.notices:
		var a: float = clampf(n.t / 0.6, 0.0, 1.0) * clampf((g.vfx.NOTICE_LIFE - n.t) / 0.2, 0.0, 1.0)
		var tw: float = minf(g.font.get_string_size(n.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 22.0, vs.x * 0.4)
		g.hud.draw_rect(Rect2(16, y - 15, tw, 22), Color(0.03, 0.035, 0.045, 0.7 * a))
		g.hud.draw_rect(Rect2(16, y - 15, 3, 22), Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, a))
		UI.text_fit(g.hud, g.font, Vector2(26, y + 1), n.text, 13, Color(1, 1, 1, 0.9 * a), tw - 14.0)
		y += 26.0


## 横幅高度：默认屏幕 24% 处；有 Boss 血条时从血条块底部往下让（docs/38：横幅高度从 Boss 块实际底部 +16 起算）
func banner_y(vs: Vector2) -> float:
	return maxf(vs.y * 0.24, h.bars.boss_bottom + 16.0 + 30.0) if h.bars.boss_bottom > 0.0 else vs.y * 0.24


## 开局提示：先移动，再提醒 Tab 属性面板；首次升级后再提醒一次
func draw_open_hints(vs: Vector2) -> void:
	# 开局提示：先移动，再提醒 Tab 属性面板；首次升级后再提醒一次
	if g.state == Game.S.PLAY:
		if g.t < 6.0:
			var ohint: String
			if g.doctor.manual_attack:
				ohint = "按住左半屏拖动移动 · 按攻击键出手（拖动选方向）" if g.touch.active else Pad.hint("WASD 移动 · 按住左键 / J 攻击，朝光标（或移动）方向", "左摇杆移动 · Ⓧ / RT 攻击 · 右摇杆瞄准")
			else:
				ohint = "按住左半屏拖动移动 · 攻击全自动" if g.touch.active else Pad.hint("WASD 移动 · 攻击全自动 · Esc 暂停", "左摇杆移动 · 攻击全自动 · START 暂停")
			UI.text(g.hud, g.font, Vector2(0, vs.y - 60), ohint, 16, Color(0.7, 0.85, 0.9, 0.8), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 3)
		elif (g.t < 16.0 and not g.tab_used) or g.tab_hint > 0.0:
			var ha := clampf(minf(g.t - 6.0, 16.0 - g.t) / 0.5, 0.0, 1.0) if g.tab_hint <= 0.0 else clampf(g.tab_hint / 0.5, 0.0, 1.0)
			var pulse := 0.5 + 0.5 * sin(g.t * 5.0)
			var cx := vs.x / 2.0
			var y := vs.y - 78.0
			var box := Rect2(cx - 150, y - 22, 300, 40)
			g.hud.draw_rect(box, Color(0.03, 0.035, 0.045, 0.82 * ha))
			g.hud.draw_rect(box, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, (0.3 + 0.5 * pulse) * ha), false, 1.0)
			# 触屏没有 Tab：写成点右侧「属性」按钮（按钮本身也跟着呼吸，见 touch.draw_hud）
			var tkey: String = "点「属性」" if g.touch.active else Pad.hint("TAB", "SELECT")
			var tkw: float = UI.keycap(g.hud, g.font, Vector2(cx - 134, y - 12), tkey, Color(1, 1, 1, ha), 12)
			UI.text(g.hud, g.font, Vector2(cx - 134 + tkw + 12.0, y + 4), "查看主控与编队的属性", 15, Color(0.85, 0.95, 0.95, ha))


func draw_dash_hint(vs: Vector2) -> void:
	if g.state != Game.S.PLAY or g.touch.active or g.demo_op != "":
		return
	var key: String = Pad.hint("空格", "Ⓑ")
	var ready: bool = g.dash_cd <= 0.0
	h.batch_begin()   # 色块一批、字最后（性能 9/30）
	# 暗底 + 按键牌 + 「冲刺」，底边一道青色冷却条（满 = 可冲）
	if g.doctor.manual_attack:
		# 手动普攻：冲刺牌左边一枚攻击牌（键鼠 左键 / J，手柄 RT / Ⓧ）
		var acap: String = Pad.hint("左键 / J", "RT / Ⓧ")
		var akw := UI.cwidth(g.font, acap, 11) + 12.0
		var aw := 8.0 + akw + 8.0 + 28.0 + 12.0
		var ar := Rect2(Vector2(vs.x / 2.0 - aw - 70.0 - 8.0, vs.y - 44), Vector2(aw, 28))
		h._hb.rect(ar, Color(0.03, 0.035, 0.045, 0.74))
		UI.keycap(g.hud, g.font, ar.position + Vector2(8, 5), acap, Color(1.0, 0.75, 0.45), 11)
		UI.text(g.hud, g.font, ar.position + Vector2(16 + akw, 19), "攻击", 13, UI.TEXT)
	var cap_s: String = Pad.hint("SPACE", "Ⓑ")
	var kw := UI.cwidth(g.font, cap_s, 11) + 12.0
	var w := 8.0 + kw + 8.0 + 28.0 + 12.0
	var r := Rect2(Vector2(vs.x / 2.0 - w / 2.0, vs.y - 44), Vector2(w, 28))
	h._hb.rect(r, Color(0.03, 0.035, 0.045, 0.74))
	var k: float = 1.0 - g.dash_cd / Game.DASH_CD
	UI.keycap(g.hud, g.font, r.position + Vector2(8, 5), cap_s, UI.CYAN if ready else UI.SUB, 11)
	UI.text(g.hud, g.font, r.position + Vector2(16 + kw, 19), "冲刺", 13, UI.TEXT if ready else UI.SUB)
	h._hb.rect(Rect2(r.position + Vector2(0, r.size.y - 2), Vector2(r.size.x * k, 2)), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.95 if ready else 0.5))
	h.batch_end()
	if not g.dash_used and g.t < 25.0:
		var a: float = 0.6 + 0.4 * sin(g.t * 4.0)
		var sp: Vector2 = g.hud_ct() * (g.ppos + Vector2(0, -92))
		UI.text(g.hud, g.font, sp - Vector2(100, 0), "按 %s 冲刺（无敌）" % key, 15, Color(0.85, 1.0, 1.0, a), HORIZONTAL_ALIGNMENT_CENTER, 200, 4)


## 缩圈：主控在安全区外时的方向提示（EA 1.1，玩法系统的缩圈改动配套；「身处黑潮」大字和紫色边缘光在状态栏那段）。
## 主控身边朝安全区圆心方向画三道逐个亮起的人字纹 + 大箭头，主控脚下写掉血倒计时。
## 前 Combat.ZONE_GRACE 秒不掉血（琥珀色，倒计时「x.x 秒后开始掉血」），之后洋红色「安全区外 · 持续掉血」。
## 数据：g.combat.zone_out_t（本次出圈秒数，圈内 / 庇护所为 0）与 zone_dir()（指向安全区圆心），玩法系统 d941889
const Combat = preload("res://scripts/run/combat.gd")

func draw_zone_hint(vs: Vector2) -> void:
	if g.state != Game.S.PLAY or g.demo_op != "" or g.zone_state == 0:
		return
	var out_t: float = g.combat.zone_out_t
	if out_t <= 0.0:
		return
	var dir: Vector2 = g.combat.zone_dir()
	if dir == Vector2.ZERO:
		return
	var hurting: bool = out_t >= Combat.ZONE_GRACE
	var col: Color = UI.RED if hurting else UI.GOLD
	var pulse: float = 0.5 + 0.5 * sin(g.t * (9.0 if hurting else 5.0))
	var ct := g.hud_ct()
	var sp: Vector2 = ct * (g.ppos + Vector2(0, -24))
	# 人字纹：从主控往外三道，依次点亮
	var side: Vector2 = dir.orthogonal()
	for q in 3:
		var d0: float = 58.0 + q * 18.0
		var lit: float = clampf(1.0 - absf(fmod(g.t * 3.0, 3.0) - q), 0.25, 1.0)
		var tip: Vector2 = sp + dir * (d0 + 8.0)
		var c2 := Color(col.r, col.g, col.b, 0.9 * lit)
		g.hud.draw_polyline(PackedVector2Array([tip - dir * 9.0 + side * 9.0, tip, tip - dir * 9.0 - side * 9.0]), Color(0, 0, 0, 0.6 * lit), 5.0)
		g.hud.draw_polyline(PackedVector2Array([tip - dir * 9.0 + side * 9.0, tip, tip - dir * 9.0 - side * 9.0]), c2, 3.0)
	# 大箭头
	var ap: Vector2 = sp + dir * (120.0 + 6.0 * pulse)
	var head := PackedVector2Array([ap + dir * 28.0, ap - dir * 4.0 + side * 20.0, ap - dir * 4.0 - side * 20.0])
	g.hud.draw_colored_polygon(PackedVector2Array([ap + dir * 32.0, ap - dir * 7.0 + side * 24.0, ap - dir * 7.0 - side * 24.0]), Color(0, 0, 0, 0.6))
	g.hud.draw_colored_polygon(head, Color(col.r, col.g, col.b, 0.75 + 0.25 * pulse))
	g.hud.draw_line(ap - dir * 4.0, ap - dir * 26.0, Color(col.r, col.g, col.b, 0.8), 7.0)
	# 文字：主控下方（不跟箭头转，免得倒着读）
	var tp: Vector2 = ct * (g.ppos + Vector2(0, 30))
	var line2: String = ("%.1f 秒后开始掉血" % maxf(0.0, Combat.ZONE_GRACE - out_t)) if not hurting else "安全区外 · 持续掉血"
	UI.text(g.hud, g.font, tp - Vector2(120, 0), line2, 15, Color(col.r, col.g, col.b, 0.95), HORIZONTAL_ALIGNMENT_CENTER, 240, 4)
