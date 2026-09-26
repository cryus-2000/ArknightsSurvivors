extends RefCounted
## 界面 · 局内 HUD（hud 画布节点的 draw 信号）：生命 / 灯火 / 等级、计时与击杀、状态条、编队栏与技能充能、藏品栏与悬停说明、
## 声呐小地图、屏幕边缘提示、冲刺提示；并按 state 分派到各界面（intro / elite_show / stats_panel / result）。
## 界面层约定（docs/39 §3）。2026-09-26 从 game.gd 拆出。

const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
const A = preload("res://scripts/art.gd")

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game
## 右下编队栏（2026-09-26 方案 A）：明日方舟部署卡——每名干员一张立绘卡（左上职业、右上精英阶段、底部名字），
## 卡上方三枚方形技能格（底部充能条 / 生效时白框 + 倒计时；未解锁灰显；永久型小菱形；海嗣化紫点；手动技能标 Q）。
## 队长卡顶上紫色「队长」标签（紫 = 当前）；技能生效中的干员卡加青色外晕。卡组上方右侧是源石锭费用框 + 编队人数。
## 干员没有等级，卡上不画经验类进度（等级是整局共享的，画在左上角）。开局干员在最左，第 4 位在最右。
const SQ_COL_W := 94.0
const SQ_CARD := Vector2(84, 96)
const SQ_SK := 24.0


func _init(game: Game) -> void:
	g = game


func draw() -> void:
	var vs := g.hud.size
	var ct := g.get_viewport().get_canvas_transform()
	if g.state == Game.S.OPENING:
		g.intro_screen.draw_opening_hud(vs)
		return
	# 伤害数字
	for f in g.texts:
		var a: float = clamp(f.life / f.max, 0.0, 1.0)
		var sp: Vector2 = ct * f.pos
		var pop: float = 1.0 + 0.7 * clamp((f.life - f.max + 0.12) / 0.12, 0.0, 1.0)
		var sz := int(f.size * pop)
		UI.text(g.hud, g.font, sp - Vector2(60, 0), f.text, sz, Color(f.col.r, f.col.g, f.col.b, a), HORIZONTAL_ALIGNMENT_CENTER, 120, 4)

	if g.demo_op != "":
		return   # 图鉴演示：只要伤害数字，不画其余 HUD
	# 升级字样：弹出放大 -> 轻微上浮 -> 淡出
	if g.lvup_show > 0.0 and g.state == Game.S.PLAY:
		var age := 1.3 - g.lvup_show
		var pop := 1.0 + 0.6 * clampf(1.0 - age / 0.15, 0.0, 1.0)
		if age > 0.15 and age < 0.3:
			pop = 1.0 - 0.1 * sin((age - 0.15) / 0.15 * PI)
		var la := clampf(g.lvup_show / 0.35, 0.0, 1.0)
		var lp: Vector2 = ct * (g.ppos + Vector2(0, -92 - age * 14.0))
		var gold := Color(1.0, 0.86, 0.42, la)
		UI.text(g.hud, g.font, lp - Vector2(150, 0), "LEVEL UP!", int(30 * pop), gold, HORIZONTAL_ALIGNMENT_CENTER, 300, 6)
		UI.text(g.hud, g.font, lp + Vector2(-150, 26), "Lv.%d" % g.level, int(18 * pop), Color(0.85, 1.0, 0.98, la), HORIZONTAL_ALIGNMENT_CENTER, 300, 4)

	if g.flash > 0.0:
		g.hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(1.0, 0.97, 0.9, g.flash * 0.5))
	# 大群预警与到达演出
	if g.horde_warn > 0.0 or g.horde_hit > 0.0:
		var hw := g.horde_warn > 0.0
		var pulse := 0.5 + 0.5 * sin(g.t * (10.0 if hw else 4.0))
		var ea := (0.25 + 0.3 * pulse) if hw else g.horde_hit / 1.2 * 0.6
		edge_glow(vs, Color(0.55, 0.15, 0.85, ea), 120.0)
		var age := (3.0 - g.horde_warn) if hw else 3.0 + (1.2 - g.horde_hit)
		var pop := 1.0 + 0.8 * clampf(1.0 - age / 0.2, 0.0, 1.0)
		var ta := 1.0 if hw else clampf(g.horde_hit / 0.6, 0.0, 1.0)
		var cy := vs.y * 0.3
		var jit := Vector2(sin(g.t * 53.0), cos(g.t * 47.0)) * (2.0 if hw else 0.0)
		g.hud.draw_rect(Rect2(0, cy - 62, vs.x, 92), Color(0.05, 0.0, 0.08, 0.55 * ta))
		g.hud.draw_rect(Rect2(0, cy - 62, vs.x, 2), Color(0.8, 0.4, 1.0, 0.8 * ta))
		g.hud.draw_rect(Rect2(0, cy + 28, vs.x, 2), Color(0.8, 0.4, 1.0, 0.8 * ta))
		UI.text(g.hud, g.font, Vector2(0, cy + 14) + jit, "大 群 来 袭" if hw else "海嗣大群 已抵达", int(38 * pop), Color(1.0, 0.75, 1.0, ta), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 6)
		if hw:
			UI.en(g.hud, g.font, Vector2(vs.x / 2 - 130, cy - 40), "THE  SWARM  APPROACHES  ·  %d" % int(ceil(g.horde_warn)), 12, Color(0.85, 0.6, 1.0, ta), 3.0)
			# 四周方向警示箭头（向内）
			for j in 12:
				var ang := TAU * j / 12.0
				if absf(angle_difference(ang, g.horde_gap)) < deg_to_rad(40.0):
					continue  # 缺口方向不画箭头：那边没有敌人
				var dir := Vector2.from_angle(ang)
				var c := vs / 2.0
				var ed: Vector2 = c + dir * min(abs((vs.x / 2 - 40) / max(abs(dir.x), 0.01)), abs((vs.y / 2 - 40) / max(abs(dir.y), 0.01)))
				var tip: Vector2 = ed - dir * (10.0 + 8.0 * pulse)
				var sd := dir.orthogonal() * 12.0
				g.hud.draw_colored_polygon(PackedVector2Array([tip, ed + sd, ed - sd]), Color(0.9, 0.5, 1.0, 0.5 + 0.4 * pulse))

	# 溟痕：屏幕压暗 + 紫色边缘
	if g.in_mire > 0.0:
		g.hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.03, 0.0, 0.06, 0.18 * g.in_mire))
		edge_glow(vs, Color(0.45, 0.1, 0.7, 0.8 * g.in_mire), 130.0)
		if g.in_mire > 0.5 and g.state == Game.S.PLAY:
			UI.text(g.hud, g.font, Vector2(0, vs.y * 0.5 + 84), "陷入溟痕：减速、侵蚀", 16, Color(0.85, 0.55, 1.0, g.in_mire), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 4)
	# 受击时屏幕边缘泛红
	if g.red_flash > 0.0:
		g.hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.8, 0.05, 0.1, g.red_flash * 0.16))
		edge_glow(vs, Color(0.9, 0.08, 0.12, g.red_flash * 0.9), 70.0)
	g.post.hurt = g.hurt_vignette
	if g.state == Game.S.PLAY and g.hp < g.max_hp * 0.3 and g.hp > 0.0:
		var beat := pow(maxf(0.0, sin(g.t * (5.0 + 5.0 * (1.0 - g.hp / (g.max_hp * 0.3))))), 4.0)
		edge_glow(vs, Color(0.85, 0.05, 0.12, 0.3 + 0.35 * beat), 110.0)
		UI.text(g.hud, g.font, Vector2(0, vs.y * 0.5 + 110), "生命垂危", 18, Color(1.0, 0.4, 0.45, 0.5 + 0.5 * beat), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 4)
	# 头顶血条：受伤后或低血量时显示
	if g.state == Game.S.PLAY and (g.head_bar_t > 0.0 or g.hp < g.max_hp * 0.3):
		var hpos: Vector2 = ct * g.ppos + Vector2(-24, -104)
		var ha := clampf(g.head_bar_t / 0.5, 0.0, 1.0) if g.hp >= g.max_hp * 0.3 else 1.0
		g.hud.draw_rect(Rect2(hpos - Vector2(1, 1), Vector2(50, 7)), Color(0, 0, 0, 0.7 * ha))
		g.hud.draw_rect(Rect2(hpos, Vector2(48 * clampf(g.hp_trail / g.max_hp, 0.0, 1.0), 5)), Color(1, 0.95, 0.9, 0.9 * ha))
		g.hud.draw_rect(Rect2(hpos, Vector2(48 * clampf(g.hp / g.max_hp, 0.0, 1.0), 5)), Color(1.0, 0.3, 0.35, ha) if g.hp < g.max_hp * 0.3 else Color(0.35, 0.95, 0.75, ha))
	if g.lamp < 30.0 and g.state == Game.S.PLAY:
		edge_glow(vs, Color(0.3, 0.0, 0.2, 0.25 + 0.1 * sin(g.t * 3.0)), 140.0)

	# 左上（方案 A · 原作顶栏）：等级圆（外圈 = 经验）+「生命值」「灯火」彩色小标签头 + 数值 + 细条；
	# 名字与编队人数移到右下编队卡；下面一条灯火状态标签条在后面画（和状态效果一起）
	var o := Vector2(16, 12)
	var lf := g.hud_lv_flash
	var bc := UI.CYAN.lerp(UI.GOLD, lf).lerp(Color(0.8, 1.6, 1.8), g.xp_flash * 0.7)
	var lc0 := o + Vector2(26, 30)
	UI.ring(g.hud, lc0, 22.0 + 3.0 * lf, g.xp / g.xp_need, bc, lf > 0.2)
	UI.ctext(g.hud, g.font, lc0 + Vector2(-20, -6), "LV", 9, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 40)
	UI.ctext(g.hud, g.font, lc0 + Vector2(-26, 13), str(g.level), int(20 * (1.0 + 0.3 * lf)), Color(1, 1, 1).lerp(UI.GOLD, lf), HORIZONTAL_ALIGNMENT_CENTER, 52)
	# 生命值
	var hs := Vector2(sin(g.t * 90.0), cos(g.t * 70.0)) * 3.0 * g.hp_shake / 0.35
	var low := g.hp / g.max_hp < 0.3
	var hx := o.x + 64.0
	var tw0 := UI.tab(g.hud, g.font, Vector2(hx, o.y), "生命值", UI.RED if low else UI.TAB_HP)
	# 护盾层：小标签头右边一排小菱形
	for q in g.shield_max:
		UI.diamond(g.hud, Vector2(hx + tw0 + 10 + q * 11, o.y + 8.5), 4.0, Color(0.5, 0.85, 1.0) if q < g.shield else Color(1, 1, 1, 0.12), Color(0.6, 0.9, 1.0, 0.8))
	var hpc: Color = UI.RED.lerp(Color(1, 0.8, 0.85), 0.5 + 0.5 * sin(g.t * 10.0)) if low else UI.CYAN
	var hps := "%d" % int(g.hp)
	UI.ctext(g.hud, g.font, Vector2(hx, o.y + 40) + hs, hps, 21, UI.RED if low else UI.TEXT)
	UI.ctext(g.hud, g.font, Vector2(hx + UI.cwidth(g.font, hps, 21) + 4, o.y + 40) + hs, "/ %d" % int(g.max_hp), 13, UI.SUB)
	UI.gbar(g.hud, Rect2(Vector2(hx, o.y + 47) + hs, Vector2(150, 4)), g.hp / g.max_hp, hpc, 0, g.hp_trail / g.max_hp)
	# 灯火：30 / 70 两道刻度
	var lx := hx + 172.0
	var lamp_low := g.lamp < 30.0
	var lc := UI.GOLD if not lamp_low else UI.RED.lerp(UI.GOLD, 0.5 + 0.5 * sin(g.t * 8.0))
	UI.tab(g.hud, g.font, Vector2(lx, o.y), "灯火", UI.TAB_LAMP if not lamp_low else UI.RED)
	var lps := "%d" % int(g.lamp)
	UI.ctext(g.hud, g.font, Vector2(lx, o.y + 40), lps, 21, lc if lamp_low else UI.TEXT)
	UI.ctext(g.hud, g.font, Vector2(lx + UI.cwidth(g.font, lps, 21) + 4, o.y + 40), "/ %d" % int(g.lamp_cap), 13, UI.SUB)
	var lbr := Rect2(Vector2(lx, o.y + 47), Vector2(120, 4))
	UI.gbar(g.hud, lbr, g.lamp / 100.0, lc)
	for tv in [30.0, 70.0]:
		var tx: float = lbr.position.x + lbr.size.x * tv / 100.0
		g.hud.draw_rect(Rect2(tx, lbr.position.y - 2, 1, lbr.size.y + 4), Color(1, 1, 1, 0.7))
	# 神经损伤 / 侵蚀：生命条下方一道洋红细条
	if g.nerve > 1.0:
		UI.gbar(g.hud, Rect2(Vector2(hx, o.y + 54), Vector2(150, 2)), g.nerve / 100.0, Color(1.0, 0.45, 0.85))
		UI.en(g.hud, g.font, Vector2(hx + 156, o.y + 58), "NERVE", 8, Color(1.0, 0.5, 0.9), 1.0)
	if g.corrode_pool > 0.5:
		UI.text(g.hud, g.font, Vector2(hx + 190, o.y + 60), "蚀", 11, Color(0.8, 0.5, 1.0))
	if g.pstun > 0.0:
		UI.text(g.hud, g.font, ct * g.ppos + Vector2(-40, -110), "僵直", 16, Color(1.0, 0.5, 0.9), HORIZONTAL_ALIGNMENT_CENTER, 80, 3)
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
	# 海嗣祭坛方位指示（屏幕外）
	for e in g.enemies:
		if not e.chest or e.dead or e.get("event", "") == "":
			continue
		var spb: Vector2 = ct * e.pos
		if Rect2(Vector2(60, 60), vs - Vector2(120, 120)).has_point(spb):
			var hb := spb + Vector2(0, -60 - absf(sin(g.t * 5.0)) * 8.0)
			g.hud.draw_colored_polygon(PackedVector2Array([hb + Vector2(0, 12), hb + Vector2(-10, -2), hb + Vector2(10, -2)]), Color(0.55, 0.8, 1.0))
			UI.text(g.hud, g.font, hb + Vector2(-60, -8), "海嗣祭坛", 13, Color(0.55, 0.8, 1.0), HORIZONTAL_ALIGNMENT_CENTER, 120, 3)
		else:
			var cc := vs / 2.0
			var dd := (spb - cc).normalized()
			var edge2: Vector2 = cc + dd * min(abs((vs.x / 2 - 64) / max(abs(dd.x), 0.01)), abs((vs.y / 2 - 64) / max(abs(dd.y), 0.01)))
			var pl := 0.5 + 0.5 * sin(g.t * 6.0)
			g.hud.draw_circle(edge2, 24.0, Color(0.03, 0.05, 0.1, 0.85))
			g.hud.draw_arc(edge2, 24.0, 0.0, TAU, 28, Color(0.55, 0.8, 1.0), 2.0)
			var et2: Texture2D = g.tex.e_event
			g.hud.draw_texture_rect_region(et2, Rect2(edge2 - Vector2(13, 15), Vector2(26, 30)), Rect2(0, 0, 26, 30))
			var tip2: Vector2 = edge2 + dd * (40.0 + 5.0 * pl)
			var base2: Vector2 = edge2 + dd * 28.0
			var sd2 := dd.orthogonal() * 10.0
			g.hud.draw_colored_polygon(PackedVector2Array([tip2, base2 + sd2, base2 - sd2]), Color(0.55, 0.8, 1.0))
			UI.text(g.hud, g.font, edge2 + Vector2(-60, -34.0 if edge2.y > vs.y / 2 else 44.0), "海嗣祭坛 %dm" % int(e.pos.distance_to(g.ppos) / 32.0), 13, Color(0.55, 0.8, 1.0), HORIZONTAL_ALIGNMENT_CENTER, 120, 3)
	if not overlay_left():
		draw_minimap(vs)
	var st_txt := ""
	var st_en := "LIGHT"
	var st_col := UI.GOLD
	if g.lamp <= 0.0:
		st_txt = "灯火熄灭 · 持续受伤"
		st_en = "OUT"
		st_col = UI.RED
	elif g.lamp < 30.0:
		st_txt = "暗潮涌动 · 敌人更快更凶更多 · 拾取 -30%"
		st_en = "DARK"
		st_col = Color(1, 0.5, 0.5)
	elif g.lamp >= 70.0:
		st_txt = "灯火充盈 · 技力 +30% · 拾取 +20%"
	else:
		st_txt = "灯火照亮 · 光中敌人受伤 +25%"
		st_en = "LIT"
		st_col = Color(1.0, 0.85, 0.6)
	UI.strip(g.hud, g.font, o + Vector2(2, 66), st_en, st_txt, st_col, st_col.lerp(UI.TEXT, 0.45))
	# 黑潮：圈外警告 + 指向安全区
	if g.zone_state != 0 and g.state == Game.S.PLAY:
		var out := g.ppos.distance_to(g.zone_c) - g.zone_r
		if out > 0.0:
			var pz := 0.5 + 0.5 * sin(g.t * 8.0)
			edge_glow(vs, Color(0.55, 0.1, 0.8, 0.4 + 0.3 * pz), 140.0)
			var dirz := (g.zone_c - g.ppos).normalized()
			var cp: Vector2 = ct * g.ppos + Vector2(0, -30) + dirz * 80.0
			var sd := dirz.orthogonal() * 12.0
			g.hud.draw_colored_polygon(PackedVector2Array([cp + dirz * 22.0, cp + sd, cp - sd]), Color(1.0, 0.8, 1.0, 0.7 + 0.3 * pz))
			UI.text(g.hud, g.font, Vector2(0, vs.y * 0.5 - 130), "身处黑潮！返回安全区", 20, Color(1.0, 0.7, 1.0, 0.7 + 0.3 * pz), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 5)
		else:
			# 顶栏楼层条下方；有 Boss 血条时再往下让出位置
			var zy := 116.0 + 54.0 * g.bosses.filter(func(b): return not b.dead).size()
			if g.zone_state == 1:
				UI.text(g.hud, g.font, Vector2(0, zy), "黑潮将至  %d" % int(ceil(20.0 - g.zone_t)), 15, Color(0.9, 0.6, 1.0), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 3)
			elif g.zone_state == 2:
				UI.text(g.hud, g.font, Vector2(0, zy), "安全区收缩中", 15, Color(0.9, 0.6, 1.0, 0.6 + 0.4 * sin(g.t * 6.0)), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 3)

	# 顶部中央（方案 A · 明日方舟战斗顶栏）：[敌人] 击杀 | [时钟] 时间；
	# 下面一行「◆ 楼层 + 英文」（背后淡金四叶环，原作地图顶部楼层名的样子）、威胁进度细线、威胁 / 难度
	var mm := int(g.t) / 60
	var ss := int(g.t) % 60
	var cx0 := vs.x / 2.0
	UI.fade_band(g.hud, Rect2(cx0 - 160, 8, 320, 40), Color(0.03, 0.035, 0.045, 0.8), 56.0)
	var ks := str(g.kills)
	var kw := UI.cwidth(g.font, ks, 23)
	var lx0 := cx0 - 16.0 - (20.0 + 6.0 + kw + 4.0 + 24.0)
	UI.icon(g.hud, "enemy", Vector2(lx0 + 10, 28), 20.0, Color.WHITE)
	UI.ctext(g.hud, g.font, Vector2(lx0 + 26, 37), ks, 23, UI.TEXT)
	UI.text(g.hud, g.font, Vector2(lx0 + 30 + kw, 36), "击杀", 11, UI.SUB)
	g.hud.draw_rect(Rect2(cx0 - 0.5, 18, 1, 20), Color(1, 1, 1, 0.28))
	UI.icon(g.hud, "clock", Vector2(cx0 + 25, 28), 18.0, Color.WHITE)
	UI.ctext(g.hud, g.font, Vector2(cx0 + 38, 38), "%02d:%02d" % [mm, ss], 25, UI.TEXT)
	var tr: Dictionary = D.THREAT[g.threat]
	var tfrac: float = 1.0
	if g.threat < D.THREAT.size() - 1:
		tfrac = clampf((g.t - tr.t) / (D.THREAT[g.threat + 1].t - tr.t), 0.0, 1.0)
	var tcol := Color(0.9, 0.45, 1.0).lerp(UI.RED, float(g.threat) / (D.THREAT.size() - 1))
	UI.quatrefoil(g.hud, Vector2(cx0, 64), 34.0, Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.28), 1.6)
	var fname: String = tr.name
	var fen: String = String(tr.get("en", ""))
	var fw0 := g.font.get_string_size(fname, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var few := UI.en_width(g.font, fen, 10, 3.0)
	var fx0 := cx0 - (14.0 + fw0 + 10.0 + few) / 2.0
	UI.diamond(g.hud, Vector2(fx0 + 4, 61), 3.5, UI.GOLD)
	UI.text(g.hud, g.font, Vector2(fx0 + 14, 66), fname, 14, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, 2)
	UI.en(g.hud, g.font, Vector2(fx0 + 24 + fw0, 65), fen, 10, UI.SUB, 3.0)
	UI.gbar(g.hud, Rect2(cx0 - 70, 73, 140, 2), tfrac, tcol)
	UI.text(g.hud, g.font, Vector2(cx0 - 150, 90), ("威胁 %s" % ["Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ", "Ⅴ", "Ⅵ"][g.threat]) + (("  ·  难度 %d" % g.diff) if g.diff > 0 else ""), 11, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 300, 2)

	# 右上：暂停按钮（鼠标可点；触屏有自己的按钮）+ 收藏品栏 + 当前结局走向
	var tray_x := vs.x - 16.0
	g.pause_btn = Rect2()
	if not g.touch.active:
		var pr := Rect2(vs.x - 56, 12, 40, 40)
		var ph: bool = g.state == Game.S.PLAY and pr.has_point(g.hud.get_local_mouse_position())
		g.hud.draw_rect(pr, Color(0.03, 0.035, 0.045, 0.78))
		g.hud.draw_rect(pr, UI.CYAN if g.state == Game.S.PAUSE else Color(1, 1, 1, 0.55 if ph else 0.22), false, 1.0)
		UI.icon(g.hud, "pause", pr.get_center(), 20.0, UI.TEXT)
		UI.ctext(g.hud, g.font, pr.position + Vector2(0, 52), "ESC", 9, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 40)
		if g.state == Game.S.PLAY:
			g.pause_btn = pr
		tray_x -= 50.0
	draw_relic_tray(Vector2(tray_x, 12))
	if g.ending != "standard" or Cfg.endings_cleared.size() > 0:
		UI.text(g.hud, g.font, Vector2(tray_x - 220, 60 + 38 * maxi(1, int(ceil(g.relics.size() / 8.0)))), g.endg.cur_name(), 12, g.endg.cur_col(), HORIZONTAL_ALIGNMENT_RIGHT, 220, 2)

	# Boss 血条
	var bby := 0.0
	for shown in g.bosses:
		if shown.dead:
			continue
		var bw := 620.0
		var bx := vs.x / 2 - bw / 2
		g.hud.draw_set_transform(Vector2(0, bby), 0.0, Vector2.ONE)
		bby += 54.0
		# 洋红 = 危险（原作「险路恶敌」）：暗底 + 顶部洋红细线 + BOSS 节点标签条
		var bbr := Rect2(bx - 12, 100, bw + 24, 46)
		g.hud.draw_rect(bbr, Color(0.03, 0.035, 0.045, 0.8))
		g.hud.draw_rect(Rect2(bbr.position, Vector2(bbr.size.x, 1)), Color(UI.RED.r, UI.RED.g, UI.RED.b, 0.7))
		UI.strip(g.hud, g.font, Vector2(bx, 106), "BOSS", shown.name, UI.RED, Color(1, 0.82, 0.88), 12)
		var sub := ""
		if shown.type == "izumik":
			sub = "学习阶段 · 无敌（击杀子代阻止它成长）" if shown.phase == 1 else "解读阶段"
		elif shown.type == "ishar":
			sub = "转化进度 %d%%（清除伊莎玛拉之泪）" % int(shown.charge) if shown.phase == 1 else "已完成转化"
		elif shown.has("ammo"):
			sub = "装填中 —— 攻击以打断！" if shown.channel > 0.0 else ("弹药 %d / 3" % shown.ammo if shown.ammo > 0 else "近战中")
		elif shown.get("coma", false):
			sub = "假死中 —— 趁现在击倒另一体！"
		elif D.ENEMIES[shown.type].get("pair", false):
			sub = "两体需同时击倒"
		elif shown.type == "paranoia":
			sub = "悬浮形态（控制它以击落）" if shown.phase == 1 else "第二形态"
		UI.text(g.hud, g.font, Vector2(bx + bw - 400, 122), sub, 12, UI.SUB, HORIZONTAL_ALIGNMENT_RIGHT, 400)
		UI.gbar(g.hud, Rect2(bx, 131, bw, 6), shown.hp / shown.maxhp, Color(0.45, 0.6, 0.7) if shown.invuln else UI.RED, 20)
		if shown.type == "ishar" and shown.phase == 1:
			g.hud.draw_rect(Rect2(bx, 139, bw * shown.charge / 100.0, 2), UI.PURPLE)
		g.hud.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 右下：技能与援护干员
	draw_squad_hud(Vector2(vs.x - 16, vs.y - 16))

	# 横幅通知
	if g.banner_t > 0.0 and not g.panel.visible:
		var a: float = clamp(g.banner_t, 0.0, 1.0)
		var by := vs.y * 0.24
		# 两端渐隐的暗带 + 上下从中间向两边淡出的细线（原作提示横幅）
		UI.fade_band(g.hud, Rect2(vs.x * 0.12, by - 30, vs.x * 0.76, 46), Color(0.03, 0.035, 0.045, 0.84 * a), 160.0)
		for yy in [by - 30.0, by + 16.0]:
			UI.hairline(g.hud, Vector2(vs.x / 2.0, yy), Vector2(vs.x * 0.16, yy), Color(1, 1, 1), 0.4 * a, 0.0)
			UI.hairline(g.hud, Vector2(vs.x / 2.0, yy), Vector2(vs.x * 0.84, yy), Color(1, 1, 1), 0.4 * a, 0.0)
		UI.text(g.hud, g.font, Vector2(0, by), g.banner, 21, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 3)
	# 开局提示：先移动，再提醒 Tab 属性面板；首次升级后再提醒一次
	if g.state == Game.S.PLAY:
		if g.t < 6.0:
			UI.text(g.hud, g.font, Vector2(0, vs.y - 60), ("按住左半屏拖动移动 · 攻击全自动" if g.touch.active else Pad.hint("WASD 移动 · 攻击全自动 · Esc 暂停", "左摇杆移动 · 攻击全自动 · START 暂停")), 16, Color(0.7, 0.85, 0.9, 0.8), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 3)
		elif (g.t < 16.0 and not g.tab_used) or g.tab_hint > 0.0:
			var ha := clampf(minf(g.t - 6.0, 16.0 - g.t) / 0.5, 0.0, 1.0) if g.tab_hint <= 0.0 else clampf(g.tab_hint / 0.5, 0.0, 1.0)
			var pulse := 0.5 + 0.5 * sin(g.t * 5.0)
			var cx := vs.x / 2.0
			var y := vs.y - 78.0
			var box := Rect2(cx - 150, y - 22, 300, 40)
			g.hud.draw_rect(box, Color(0.03, 0.035, 0.045, 0.82 * ha))
			g.hud.draw_rect(box, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, (0.3 + 0.5 * pulse) * ha), false, 1.0)
			UI.keycap(g.hud, g.font, Vector2(cx - 134, y - 12), Pad.hint("TAB", "SELECT"), Color(1, 1, 1, ha), 12)
			UI.text(g.hud, g.font, Vector2(cx - 72, y + 4), "查看主控与编队的属性", 15, Color(0.85, 0.95, 0.95, ha))

	draw_relic_tooltip(vs)
	g.touch.draw_hud(vs)
	if not overlay_left():
		draw_status_bar(vs)
	draw_dash_hint(vs)
	draw_manual_aim()
	draw_manual_hint()
	match g.state:
		Game.S.SHOW:
			g.show_screen.draw(vs)
		Game.S.INTRO:
			g.intro_screen.draw(vs)
		Game.S.STATS:
			g.stats_screen.draw(vs)
		Game.S.PAUSE:
			g.result_screen.draw(vs, "暂停", "PAUSED", UI.CYAN, [["继续", "Esc", "resume"], ["指南", "G", "guide"], ["设置", "O", "settings"], ["重新开始", "R", "restart"], ["回到标题", "T", "title"]])
		Game.S.DEAD:
			g.result_screen.draw(vs, "探索终止", "OPERATION FAILED", UI.RED, [["再次探索", "R", "restart"], ["回到标题", "T", "title"]])
		Game.S.WIN:
			g.result_screen.draw(vs, "%s · 探索完成" % D.ENDINGS[g.ending].name, D.ENDINGS[g.ending].en, g.endg.cur_col().lerp(UI.GOLD, 0.35), [["再次探索", "R", "restart"], ["回到标题", "T", "title"]], true)


## 小地图（左下）：以水月为中心，显示约 1100 范围内的敌人、精英、Boss、宝箱、道具与商人
func draw_minimap(vs: Vector2) -> void:
	var rad := 78.0
	var c := Vector2(16 + rad + 8, vs.y - rad - 24)
	UI.porthole(g.hud, c, rad, UI.GLOW)
	var slr := Rect2(Vector2(c.x - rad + 2, c.y - rad - 8), Vector2(UI.en_width(g.font, "SONAR", 9, 2.0) + 10.0, 14))
	g.hud.draw_rect(slr, Color(1, 1, 1, 0.14))
	UI.en(g.hud, g.font, slr.position + Vector2(5, 11), "SONAR", 9, Color(0.81, 0.84, 0.86), 2.0)
	var world := 1100.0
	var k := (rad - 8.0) / world
	var lim := rad - 6.0
	# 声呐扫描线
	var sweep := fmod(g.t * 0.9, TAU)
	g.hud.draw_line(c, c + Vector2.from_angle(sweep) * lim, Color(UI.GLOW.r, UI.GLOW.g, UI.GLOW.b, 0.35), 1.0)
	for q in 6:
		var a := sweep - q * 0.06
		g.hud.draw_line(c, c + Vector2.from_angle(a) * lim, Color(UI.GLOW.r, UI.GLOW.g, UI.GLOW.b, 0.06 * (6 - q) / 6.0), 3.0)
	g.hud.draw_arc(c, lim * 0.5, 0.0, TAU, 40, Color(UI.GLOW.r, UI.GLOW.g, UI.GLOW.b, 0.12), 1.0)
	# 视野框
	var view := g.get_viewport_rect().size
	g.hud.draw_rect(Rect2(c - view * 0.5 * k, view * k), Color(1, 1, 1, 0.2), false, 1.0)
	for e in g.enemies:
		if e.dead:
			continue
		var p: Vector2 = (e.pos - g.ppos) * k
		if p.length() > lim:
			if e.boss:
				p = p.limit_length(lim)
			else:
				continue
		if e.boss:
			var bp := 0.5 + 0.5 * sin(g.t * 6.0)
			g.hud.draw_circle(c + p, 5.0 + bp, Color(0.8, 0.3, 1.0))
		elif e.chest:
			g.hud.draw_rect(Rect2(c + p - Vector2(2, 2), Vector2(4, 4)), Color(0.55, 0.8, 1.0) if e.get("event", "") != "" else UI.GOLD)
		elif e.elite:
			g.hud.draw_rect(Rect2(c + p - Vector2(2, 2), Vector2(4, 4)), Color(1.0, 0.6, 0.25))
		else:
			g.hud.draw_rect(Rect2(c + p - Vector2(1, 1), Vector2(2, 2)), Color(UI.RED.r, UI.RED.g, UI.RED.b, 0.85))
	for g_item in g.gems:
		if g_item.dead or not (g_item.kind == "magnet" or g_item.kind == "heal" or g_item.kind == "chest"):
			continue
		var p: Vector2 = ((g_item.pos - g.ppos) * k).limit_length(lim)
		g.hud.draw_circle(c + p, 3.0, g.pickups.item_col(g_item.kind))
	if not g.merchant.is_empty():
		var mp: Vector2 = ((g.merchant.pos - g.ppos) * k)
		var clipped := mp.length() > lim
		mp = mp.limit_length(lim)
		UI.diamond(g.hud, c + mp, 5.0 + (1.5 * sin(g.t * 6.0) if clipped else 0.0), UI.GOLD)
	for o in g.squad.ops:
		if o.pos != Vector2.INF:
			g.hud.draw_circle(c + (o.pos - g.ppos) * k, 2.0, Color(0.5, 0.9, 1.0))
	if g.zone_state != 0:
		mini_circle(c + (g.zone_c - g.ppos) * k, g.zone_r * k, lim, Color(0.85, 0.4, 1.0, 0.9), c)
		if g.zone_state == 1:
			mini_circle(c + (g.zone_next_c - g.ppos) * k, g.zone_next_r * k, lim, Color(1, 1, 1, 0.6), c)
	UI.diamond(g.hud, c, 4.0, Color(1, 1, 1))


func mini_circle(cc: Vector2, r: float, lim: float, col: Color, c: Vector2) -> void:
	var n := 48
	for i in n:
		var p0 := cc + Vector2.from_angle(TAU * i / n) * r
		var p1 := cc + Vector2.from_angle(TAU * (i + 1) / n) * r
		if (p0 - c).length() > lim or (p1 - c).length() > lim:
			continue
		g.hud.draw_line(p0, p1, col, 1.5)


func edge_glow(vs: Vector2, col: Color, w: float) -> void:
	var c0 := col
	var c1 := Color(col.r, col.g, col.b, 0.0)
	g.hud.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(vs.x, 0), Vector2(vs.x, w), Vector2(0, w)]), PackedColorArray([c0, c0, c1, c1]))
	g.hud.draw_polygon(PackedVector2Array([Vector2(0, vs.y - w), Vector2(vs.x, vs.y - w), vs, Vector2(0, vs.y)]), PackedColorArray([c1, c1, c0, c0]))
	g.hud.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(w, 0), Vector2(w, vs.y), Vector2(0, vs.y)]), PackedColorArray([c0, c1, c1, c0]))
	g.hud.draw_polygon(PackedVector2Array([Vector2(vs.x - w, 0), Vector2(vs.x, 0), vs, Vector2(vs.x - w, vs.y)]), PackedColorArray([c1, c0, c0, c1]))


func draw_relic_tray(tr: Vector2) -> void:
	var n := g.relics.size()
	var per_row := 8
	var cell := 38.0
	var w: float = max(min(n, per_row) * cell + 12.0, 132.0)
	var rows: int = max(1, int(ceil(n / float(per_row))))
	var o := tr + Vector2(-w, 0)
	var r := Rect2(o, Vector2(w, rows * cell + 30))
	# 原作底栏「收藏品 N」：暗底 + 图标 + 数量，下面一排藏品格（左上角一小段分类色）
	g.hud.draw_rect(r, Color(0.03, 0.035, 0.045, 0.74))
	g.hud.draw_rect(Rect2(o, Vector2(w, 1)), Color(1, 1, 1, 0.14))
	UI.icon(g.hud, "box", o + Vector2(15, 14), 14.0, Color(0.81, 0.84, 0.86))
	UI.text(g.hud, g.font, o + Vector2(28, 19), "收藏品", 12, Color(0.81, 0.84, 0.86))
	if w >= 180.0:
		UI.en(g.hud, g.font, o + Vector2(70, 18), "RELICS", 9, UI.SUB, 2.0)
	UI.ctext(g.hud, g.font, o + Vector2(w - 34, 20), "%d" % n, 17, UI.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, 24)
	g.tray_cells.clear()
	var mouse := g.hud.get_local_mouse_position()
	for i in n:
		var rd: Dictionary = g.RL[g.relics[i]]
		var col: Color = UI.CAT_COL.get(rd.cat, UI.GOLD)
		var c := o + Vector2(6 + (i % per_row) * cell + cell / 2, 26 + (i / per_row) * cell + cell / 2)
		var cellr := Rect2(c - Vector2(17, 17), Vector2(34, 34))
		g.tray_cells.append([cellr, g.relics[i]])
		var hov: bool = cellr.has_point(mouse)
		g.hud.draw_rect(cellr, Color(1, 1, 1, 0.05) if not hov else Color(col.r, col.g, col.b, 0.22))
		g.hud.draw_rect(cellr, Color(1, 1, 1, 0.13) if not hov else col, false, 1.0)
		g.hud.draw_rect(Rect2(cellr.position, Vector2(8, 2)), Color(col.r, col.g, col.b, 0.85))
		var ic: Texture2D = g.tex.get("relic_" + g.relics[i])
		if ic != null:
			g.hud.draw_texture_rect(ic, Rect2(c - Vector2(16, 16), Vector2(32, 32)), false)
		else:
			UI.diamond(g.hud, c, 11.0, Color(0.03, 0.08, 0.1), col)
			UI.text(g.hud, g.font, c + Vector2(-15, 5), rd.name.substr(0, 1), 12, col, HORIZONTAL_ALIGNMENT_CENTER, 30)
		var rl: int = g.rfx.lv.get(g.relics[i], 1)
		if rl > 1:
			for q in rl:
				g.hud.draw_rect(Rect2(c + Vector2(-16 + q * 6, 12), Vector2(4, 3)), Color(col.r * 1.5, col.g * 1.5, col.b * 1.5))
	var cy := r.end.y + 16


## 藏品栏悬停提示（游戏中 / 暂停）
func draw_relic_tooltip(vs: Vector2) -> void:
	if g.state != Game.S.PLAY and g.state != Game.S.PAUSE:
		return
	var mouse := g.hud.get_local_mouse_position()
	for cellinfo in g.tray_cells:
		var cr: Rect2 = cellinfo[0]
		if not cr.has_point(mouse):
			continue
		var id: String = cellinfo[1]
		var rd: Dictionary = g.RL[id]
		var mx: int = g.rfx.max_lv(id)
		draw_tooltip(vs, cr, rd.name + ((" Lv.%d/%d" % [g.rfx.lv.get(id, 1), mx]) if mx > 1 else ""), "%s · %s" % [rd.cat, rd.rarity], rd.desc, "relic_" + id, UI.CAT_COL.get(rd.cat, UI.GOLD))
		return


## 通用提示卡：贴在格子下方（越界时贴上方 / 左移），图标 + 标题 + 副标题 + 折行说明
func draw_tooltip(vs: Vector2, cr: Rect2, title: String, sub: String, desc: String, icon: String, col: Color, on: CanvasItem = null) -> void:
	var ci: CanvasItem = g.hud if on == null else on
	var w := 340.0
	# 说明按像素宽度折行（旧版按 26 个字硬切，13 号字会超出框）；太长先缩字号，整屏都放不下才截断
	var fd := UI.fit(g.font, desc, w - 28.0, vs.y - 24.0 - 74.0, [13, 12, 11], 3.0)
	var h := 66.0 + float(fd.h) + 12.0
	var pos := Vector2(clampf(cr.position.x, 12.0, vs.x - w - 12.0), cr.end.y + 8)
	if pos.y + h > vs.y - 12.0:
		pos.y = cr.position.y - h - 8
	pos.y = clampf(pos.y, 12.0, maxf(12.0, vs.y - h - 12.0))
	var r := Rect2(pos, Vector2(w, h))
	ci.draw_rect(Rect2(pos + Vector2(2, 2), Vector2(w - 4, h - 4)), Color(0.03, 0.035, 0.045, 0.96))
	UI.frame(ci, r, col)
	var tx0 := 14.0
	var ic: Texture2D = g.tex.get(icon) if icon != "" else null
	if ic != null:
		ci.draw_texture_rect(ic, Rect2(pos + Vector2(12, 12), Vector2(40, 40)), false)
		tx0 = 62.0
	UI.text_fit(ci, g.font, pos + Vector2(tx0, 28), title, 16, Color.WHITE, w - tx0 - 12.0, 12)
	UI.text_fit(ci, g.font, pos + Vector2(tx0, 48), sub, 12, col, w - tx0 - 12.0, 10)
	UI.draw_fit(ci, g.font, pos + Vector2(14, 62), fd, Color(0.85, 0.92, 0.95))


func draw_dash_hint(vs: Vector2) -> void:
	if g.state != Game.S.PLAY or g.touch.active or g.demo_op != "":
		return
	var key: String = Pad.hint("空格", "Ⓑ")
	var ready: bool = g.dash_cd <= 0.0
	# 暗底 + 按键牌 + 「冲刺」，底边一道青色冷却条（满 = 可冲）
	var cap_s: String = Pad.hint("SPACE", "Ⓑ")
	var kw := UI.cwidth(g.font, cap_s, 11) + 12.0
	var w := 8.0 + kw + 8.0 + 28.0 + 12.0
	var r := Rect2(Vector2(vs.x / 2.0 - w / 2.0, vs.y - 44), Vector2(w, 28))
	g.hud.draw_rect(r, Color(0.03, 0.035, 0.045, 0.74))
	var k: float = 1.0 - g.dash_cd / Game.DASH_CD
	UI.keycap(g.hud, g.font, r.position + Vector2(8, 5), cap_s, UI.CYAN if ready else UI.SUB, 11)
	UI.text(g.hud, g.font, r.position + Vector2(16 + kw, 19), "冲刺", 13, UI.TEXT if ready else UI.SUB)
	g.hud.draw_rect(Rect2(r.position + Vector2(0, r.size.y - 2), Vector2(r.size.x * k, 2)), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.95 if ready else 0.5))
	if not g.dash_used and g.t < 25.0:
		var a: float = 0.6 + 0.4 * sin(g.t * 4.0)
		var sp: Vector2 = g.get_viewport().get_canvas_transform() * (g.ppos + Vector2(0, -92))
		UI.text(g.hud, g.font, sp - Vector2(100, 0), "按 %s 冲刺（无敌）" % key, 15, Color(0.85, 1.0, 1.0, a), HORIZONTAL_ALIGNMENT_CENTER, 200, 4)


## 手动技能首次就绪提示：每局主控的手动技能第一次充满时，在主控头顶显示 3.5 秒「按 Q 释放「技能名」」
## （手柄写 Ⓐ，触屏写「点技能键释放」），之后只留技能格的呼吸框。位置在冲刺提示上方，两者不重叠
var manual_hinted := false
var manual_hint_t := 0.0
var manual_hint_text := ""


func draw_manual_hint() -> void:
	if g.state != Game.S.PLAY or g.demo_op != "":
		return
	if not manual_hinted:
		var ld = g.squad.leader()
		var i: int = ld.manual_index() if ld != null else -1
		if i >= 0 and manual_castable(ld, i):
			manual_hinted = true
			manual_hint_t = 3.5
			var nm: String = ld.skill_def(i).get("name", "技能")
			manual_hint_text = ("点技能键释放「%s」" % nm) if g.touch.active else ("按 %s 释放「%s」" % [Pad.hint("Q", "Ⓐ"), nm])
	if manual_hint_t <= 0.0:
		return
	manual_hint_t -= g.get_process_delta_time()
	var a: float = clampf(manual_hint_t / 0.5, 0.0, 1.0) * (0.65 + 0.35 * sin(g.t * 5.0))
	var sp: Vector2 = g.get_viewport().get_canvas_transform() * (g.ppos + Vector2(0, -118))
	UI.text(g.hud, g.font, sp - Vector2(140, 0), manual_hint_text, 15, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, a), HORIZONTAL_ALIGNMENT_CENTER, 280, 4)


## 手动技能此刻「能放」（技能格呼吸框、触屏技能键、首次提示共用）：带方向的技能（JSON "aim": true）只要朝某个方向能放就算，
## 这样附近没敌人时乌尔比安 S3 也亮——给方向就能掷向空地当位移；键鼠站着不动按 Q 仍是自动瞄准，没目标时角色自己飘字说原因
func manual_castable(o, k: int) -> bool:
	return o.manual_ready(k, Vector2.RIGHT if o.manual_aims(k) else Vector2.ZERO)


## 手动技能瞄准指示（契约 v2.4）：主控带方向的手动技能能放时，在预计落点画圈（半径 = 技能作用半径），从主控拉一条引导线。
## 触屏：按住技能键拖动时画拖出的方向（拖回中心 = 自动瞄准，圈落在自动目标上）；没按住不画。
## 键鼠 / 手柄：跟 g.doctor.manual_input_dir()（移动方向 / 右摇杆），站着不动时画自动目标，淡一些。
## 瞄准圈是按技能半径精确画的几何指示，不是特效，所以不走素材库（docs/37 §7）
const AIM_COL := Color(0.45, 0.95, 1.0)

func draw_manual_aim() -> void:
	if g.state != Game.S.PLAY or g.demo_op != "" or g.autotest:
		return
	var ld = g.squad.leader()
	var i: int = ld.manual_index() if ld != null else -1
	if i < 0 or not ld.manual_aims(i):
		return
	var dir := Vector2.ZERO
	var strong := false
	if g.touch.active:
		if g.touch.skill_id < 0:
			return
		dir = g.touch.aim_dir()
		strong = true
	else:
		dir = g.doctor.manual_input_dir()
		strong = dir != Vector2.ZERO
	var xf: Transform2D = g.get_viewport().get_canvas_transform()
	var pt: Vector2 = ld.manual_aim_point(i, dir) if ld.manual_ready(i, dir) else Vector2.INF
	if pt == Vector2.INF:
		# 触屏按住没拖、自动瞄准又没目标（乌尔比安：400 内没敌人）：提示拖出方向，免得松手只飘一句「附近没有敌人」
		if g.touch.active and dir == Vector2.ZERO and manual_castable(ld, i):
			UI.text(g.hud, g.font, xf * (ld.pos + Vector2(0, -90)) - Vector2(100, 0), "附近没有敌人 · 拖动选方向", 13, Color(AIM_COL.r, AIM_COL.g, AIM_COL.b, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 200)
		return
	var sc: float = xf.get_scale().x
	var a: float = (0.85 if strong else 0.4) * (0.8 + 0.2 * sin(g.t * 6.0))
	var from: Vector2 = xf * ld.pos
	var to: Vector2 = xf * pt
	var rad: float = ld.base("s3_r", 140.0) * ld.stat(&"op_range") * sc
	# 引导线：虚线，到圈边为止
	var seg: Vector2 = to - from
	var ln: float = seg.length()
	if ln > rad + 8.0:
		var u: Vector2 = seg / ln
		var t := 18.0
		while t < ln - rad:
			g.hud.draw_line(from + u * t, from + u * minf(t + 10.0, ln - rad), Color(AIM_COL.r, AIM_COL.g, AIM_COL.b, a * 0.7), 2.0)
			t += 18.0
	g.hud.draw_circle(to, rad, Color(AIM_COL.r, AIM_COL.g, AIM_COL.b, a * 0.1))
	g.hud.draw_arc(to, rad, 0.0, TAU, 48, Color(AIM_COL.r, AIM_COL.g, AIM_COL.b, a), 2.0)
	# 圈内四个刻度 + 中心点：一眼看出落点
	for q in 4:
		var d: Vector2 = Vector2.from_angle(q * PI / 2.0 + g.t * 0.8)
		g.hud.draw_line(to + d * (rad - 10.0), to + d * (rad - 2.0), Color(AIM_COL.r, AIM_COL.g, AIM_COL.b, a), 2.0)
	g.hud.draw_circle(to, 3.0, Color(1, 1, 1, a))
	if g.touch.active and dir == Vector2.ZERO:
		UI.text(g.hud, g.font, to + Vector2(-40, -rad - 8.0), "自动瞄准", 12, Color(AIM_COL.r, AIM_COL.g, AIM_COL.b, a), HORIZONTAL_ALIGNMENT_CENTER, 80)


## 商人 / 事件界面把左半屏占满：这时不画声呐和状态小牌，免得从面板边上露出来
func overlay_left() -> bool:
	return g.state == Game.S.SHOP or (g.state == Game.S.CHOICE and g.choice_kind == "event")


func draw_status_bar(vs: Vector2) -> void:
	if g.state == Game.S.OPENING or g.state == Game.S.INTRO or g.state == Game.S.SHOW:
		return
	var items: Array = []   # [文字, 颜色, 进度 0..1 或 -1]
	for it in g.ch.status_items():
		items.append(it if it.size() >= 3 else [it[0], it[1], -1.0])
	if g.shield > 0:
		items.append(["护盾 ×%d" % g.shield, Color(0.6, 0.9, 1.0), -1.0])
	for x in g.rfx.temps:
		if x.stat == "dmg":
			items.append(["增伤 +%d%%" % int(x.value * 100.0), Color(1.0, 0.75, 0.4), clampf((x.until - g.t) / 6.0, 0.0, 1.0)])
	if g.rfx.rule("black_tulip") > 0 and g.rfx.tulip_t > 1.0:
		items.append(["郁金香 +%d%%" % int(60.0 * g.rfx.tulip_t / 60.0), Color(1.0, 0.6, 0.7), g.rfx.tulip_t / 60.0])
	if g.rfx.perm_dmg > 0.0:
		items.append(["刻勋 +%.1f%%" % (g.rfx.perm_dmg * 100.0), Color(1.0, 0.85, 0.5), -1.0])
	if g.hp < g.max_hp * 0.3 and (g.rfx.rule("king_crown") + g.rfx.rule("king_gun") + g.rfx.rule("king_cake") + g.rfx.rule("king_branch")) > 0:
		items.append(["国王之势", Color(1.0, 0.8, 0.3), -1.0])
	if g.corrode_pool > 0.5:
		items.append(["侵蚀 %d" % int(g.corrode_pool), Color(0.8, 0.5, 1.0), -1.0])
	if g.nerve > 5.0:
		items.append(["神经损伤", Color(1.0, 0.5, 0.9), g.nerve / 100.0])
	if g.atk_slow > 0.0:
		items.append(["攻速减缓", Color(0.6, 0.7, 0.9), clampf(g.atk_slow / 3.0, 0.0, 1.0)])
	if g.pstun > 0.0:
		items.append(["定身", UI.RED, -1.0])
	if g.in_mire > 0.5:
		items.append(["溟痕 · 减速", Color(0.85, 0.45, 1.0), -1.0])
	if g.zone_state != 0 and g.ppos.distance_to(g.zone_c) > g.zone_r:
		items.append(["黑潮", Color(0.9, 0.4, 1.0), -1.0])
	if g.lamp < 30.0:
		items.append(["灯火低微", Color(1.0, 0.55, 0.45), -1.0])
	if items.is_empty():
		return
	var x := 18.0
	var y := 104.0
	for it in items:
		var w: float = UI.chip(g.hud, g.font, Vector2(x, y), it[0], it[1], 12)
		if it[2] >= 0.0:
			g.hud.draw_rect(Rect2(x, y + 20, w * it[2], 2), it[1])
		x += w + 6.0
		if x > 360.0:
			x = 18.0
			y += 26.0


func draw_squad_hud(br: Vector2) -> void:
	var n: int = g.squad.size()
	var x_left: float = br.x - n * SQ_COL_W + (SQ_COL_W - SQ_CARD.x)
	if g.knight.alive:
		g.knight.draw_hud(g.hud, Vector2(x_left - 130, br.y - 30))
	var card_y: float = br.y - SQ_CARD.y
	var sk_y: float = card_y - SQ_SK - 14.0
	# 源石锭费用框（明日方舟部署费用的位置与样子）+ 编队人数
	var dp := Rect2(Vector2(br.x - 116, sk_y - 46), Vector2(116, 34))
	g.hud.draw_rect(dp, Color(0.03, 0.035, 0.045, 0.82))
	g.hud.draw_rect(Rect2(dp.position, Vector2(3, dp.size.y)), UI.GREEN)
	g.hud.draw_texture_rect(g.tex.ingot, Rect2(dp.position + Vector2(12, 10), Vector2(18, 14)), false)
	UI.ctext(g.hud, g.font, dp.position + Vector2(38, 27), str(g.ingots), 26, UI.TEXT)
	UI.text(g.hud, g.font, dp.position + Vector2(76, 22), "源石锭", 10, UI.SUB)
	UI.text(g.hud, g.font, Vector2(dp.position.x - 160, dp.position.y + 22), "编队 %d / %d" % [n, g.squad.cap()], 12, Color(0.81, 0.84, 0.86), HORIZONTAL_ALIGNMENT_RIGHT, 150)
	var mp := g.hud.get_local_mouse_position()
	for i in n:
		var o = g.squad.ops[i]
		var x: float = br.x - (n - i) * SQ_COL_W + (SQ_COL_W - SQ_CARD.x)
		var cr := Rect2(Vector2(x, card_y), SQ_CARD)
		var ocol: Color = o.col()
		var act: bool = o.skill_active()
		# ---- 立绘卡：上亮下暗的底 + 待机帧上半身（48 帧放大 2 倍、96 高清帧原样，都画成 96 像素）
		var ctop := Color(0.17, 0.2, 0.23, 0.95)
		var cbot := Color(0.07, 0.08, 0.1, 0.95)
		g.hud.draw_polygon(PackedVector2Array([cr.position, Vector2(cr.end.x, cr.position.y), cr.end, Vector2(cr.position.x, cr.end.y)]), PackedColorArray([ctop, ctop, cbot, cbot]))
		var pt: Dictionary = o.portrait()
		var at: Texture2D = g.tex.get(pt.tex)
		if at != null:
			var fw := float(at.get_width()) / int(pt.frames)
			var fh := float(at.get_height())
			var ks: float = 2.0 / A.hires_of(at)
			var dst_h := minf(fh * ks - 8.0, cr.size.y - 8.0)
			var src := Rect2(maxf(0.0, (fw * ks - cr.size.x) / 2.0) / ks, 8.0 / ks, minf(cr.size.x / ks, fw), dst_h / ks)
			g.hud.draw_texture_rect_region(at, Rect2(cr.position, Vector2(minf(cr.size.x, fw * ks), dst_h)), src)
		var clear := Color(0, 0, 0, 0)
		var shade := Color(0, 0, 0, 0.88)
		g.hud.draw_polygon(PackedVector2Array([Vector2(cr.position.x, cr.end.y - 28), Vector2(cr.end.x, cr.end.y - 28), cr.end, Vector2(cr.position.x, cr.end.y)]), PackedColorArray([clear, clear, shade, shade]))
		UI.text(g.hud, g.font, Vector2(cr.position.x, cr.end.y - 8), o.display_name().substr(0, 5), 11, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, 2)
		var cls: String = String(o.cls).substr(0, 1)
		if cls != "":
			g.hud.draw_rect(Rect2(cr.position, Vector2(18, 18)), Color(0, 0, 0, 0.72))
			UI.text(g.hud, g.font, cr.position + Vector2(0, 14), cls, 12, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 18)
		var el: String = ["精零", "精一", "精二"][o.elite]
		var ew := g.font.get_string_size(el, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 8.0
		g.hud.draw_rect(Rect2(Vector2(cr.end.x - ew, cr.position.y), Vector2(ew, 16)), Color(0, 0, 0, 0.66))
		UI.text(g.hud, g.font, Vector2(cr.end.x - ew + 4, cr.position.y + 12), el, 10, ocol.lerp(UI.TEXT, 0.4))
		if act:
			for k in 3:
				g.hud.draw_rect(cr.grow(2.0 + k * 2.5), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.16 - k * 0.045), false, 2.0)
			g.hud.draw_rect(cr, UI.CYAN, false, 1.0)
		else:
			g.hud.draw_rect(cr, Color(1, 1, 1, 0.16), false, 1.0)
		g.hud.draw_rect(Rect2(cr.position + Vector2(0, cr.size.y - 2), Vector2(cr.size.x, 2)), Color(ocol.r, ocol.g, ocol.b, 0.9))
		if o == g.ch:
			var lt := Rect2(Vector2(cr.position.x + 18, card_y - 11), Vector2(cr.size.x - 36, 14))
			g.hud.draw_rect(lt, UI.VIOLET)
			UI.text(g.hud, g.font, lt.position + Vector2(0, 11), "队长", 10, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, lt.size.x)
		# ---- 三枚技能格
		var items: Array = o.skill_hud()
		for k in 3:
			var it: Array = items[k]
			var sr := Rect2(Vector2(x + k * (SQ_SK + 6.0), sk_y), Vector2(SQ_SK, SQ_SK))
			var col: Color = it[6]
			var unlocked: bool = it[2]
			var active: float = it[3]
			var frac: float = clamp(it[5], 0.0, 1.0)
			if active > 0.0:
				frac = active / it[4]
			g.hud.draw_rect(sr, Color(0.04, 0.047, 0.059, 0.9))
			var icon: Texture2D = g.tex.get(it[9]) if it.size() > 9 and it[9] != "" else null
			var c := sr.get_center()
			if icon != null:
				# 方形技能图标（仿原作）铺满格子；充能中没充满的上半截压暗，充满后整块亮起
				g.hud.draw_texture_rect(icon, sr, false, Color.WHITE if unlocked else Color(0.3, 0.3, 0.35))
				if unlocked and active <= 0.0 and frac < 1.0:
					g.hud.draw_rect(Rect2(sr.position, Vector2(sr.size.x, sr.size.y * (1.0 - frac))), Color(0.02, 0.025, 0.035, 0.62))
			else:
				if unlocked and frac > 0.0:
					g.hud.draw_rect(Rect2(Vector2(sr.position.x, sr.end.y - sr.size.y * frac), Vector2(sr.size.x, sr.size.y * frac)), Color(col.r, col.g, col.b, 0.22 if active <= 0.0 else 0.35))
				var gcol: Color = (Color(1, 1, 1) if active > 0.0 else col) if unlocked else Color(0.3, 0.35, 0.4)
				UI.text(g.hud, g.font, Vector2(sr.position.x, c.y + 5), it[0], 12, gcol, HORIZONTAL_ALIGNMENT_CENTER, sr.size.x, 2)
			if unlocked:
				g.hud.draw_rect(Rect2(Vector2(sr.position.x, sr.end.y - 2), Vector2(sr.size.x * frac, 2)), col if active <= 0.0 else Color.WHITE)
			# 边框：生效中白；充满待放用干员色（有图标时格子本身亮起，边框再提示一下）；其余淡白
			var ready: bool = icon != null and unlocked and active <= 0.0 and frac >= 1.0 and not o.perm[k]
			g.hud.draw_rect(sr, Color.WHITE if active > 0.0 else (Color(col.r, col.g, col.b, 0.95) if ready else Color(1, 1, 1, 0.14 if unlocked else 0.06)), false, 1.0)
			if active > 0.0:
				UI.ctext(g.hud, g.font, Vector2(sr.end.x - 12, sr.position.y + 10), "%d" % int(ceil(active)), 10, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 12)
			if o.perm[k]:
				UI.diamond(g.hud, sr.end - Vector2(3, 3), 3.0, col, Color(1, 1, 1, 0.6))
			if o.rej.has(k):
				UI.diamond(g.hud, Vector2(c.x, sr.position.y - 2), 3.0, Color(0.85, 0.55, 1.0))
			# 手动技能（契约 v2.2）：格子上方标按键；充满可放时青色呼吸框
			if o.is_manual(k) and unlocked:
				var rdy: bool = manual_castable(o, k)
				if rdy:
					var pulse: float = 0.5 + 0.5 * sin(g.t * 6.0)
					g.hud.draw_rect(sr.grow(2.0 + 1.5 * pulse), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.45 + 0.4 * pulse), false, 2.0)
				UI.ctext(g.hud, g.font, Vector2(sr.position.x - 8, sr.position.y - 4), Pad.hint("Q", "Ⓐ"), 10, UI.TEXT if rdy else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, sr.size.x + 16)
			# 悬停：技能名 + 解锁阶段
			if sr.has_point(mp):
				var sd: Dictionary = o.skill_def(k)
				var tip := "%s  ·  %s" % [sd.get("name", ""), ["招募", "精英一", "精英二"][k] + ("" if o.skill_unlocked(k) else "解锁")]
				var tw: float = g.font.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 24.0
				var tipr := Rect2(Vector2(minf(c.x - tw / 2.0, g.hud.size.x - tw - 8.0), sk_y - 70), Vector2(tw, 28))
				UI.panel(g.hud, tipr, UI.BG2, o.col(), 6.0)
				UI.text(g.hud, g.font, tipr.position + Vector2(12, 19), tip, 12, UI.TEXT)
