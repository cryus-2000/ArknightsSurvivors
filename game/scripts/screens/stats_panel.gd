extends RefCounted
## 界面 · 属性面板（Tab，state STATS）：主控属性、编队干员、伤害构成与藏品。
## 界面层约定（docs/37）。2026-09-26 从 game.gd 拆出。

const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
const A = preload("res://scripts/art.gd")

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game


func _init(game: Game) -> void:
	g = game


## 本局造成伤害的构成（按来源前三，占比），Tab 面板与结算用
func dmg_mix_text() -> String:
	var total := 0.0
	for k in g.dmg_out:
		total += g.dmg_out[k]
	if total <= 0.0:
		return "—"
	var ks: Array = g.dmg_out.keys()
	ks.sort_custom(func(a, b): return g.dmg_out[a] > g.dmg_out[b])
	var parts: Array = []
	for i in mini(3, ks.size()):
		parts.append("%s %d%%" % [ks[i], int(round(g.dmg_out[ks[i]] / total * 100.0))])
	return " · ".join(parts)


## 属性面板（Tab / C 打开，游戏暂停）
func draw(vs: Vector2) -> void:
	g.hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.02, 0.05, 0.82))
	var r := Rect2(60, 44, vs.x - 120, vs.y - 88)
	UI.frame(g.hud, r, UI.GLOW, {"t": g.t, "vines": true, "seed": 31, "cut": 14.0, "bracket": 14.0, "glow": 0.3})
	UI.caustic(g.hud, Rect2(r.position + Vector2(20, 8), Vector2(r.size.x - 40, 22)), g.t, UI.GLOW)
	# 标题行
	var pt: Texture2D = g.tex.get("doctor", g.tex.get("player_idle"))
	if pt != null:
		var fh := pt.get_height()
		var fr := int(g.t * 2.0) % maxi(1, pt.get_width() / fh)
		g.hud.draw_texture_rect_region(pt, Rect2(r.position + Vector2(26, 14), Vector2(fh, fh) * 1.5 / A.hires_of(pt)), Rect2(fr * fh, 0, fh, fh))
	UI.text(g.hud, g.font, r.position + Vector2(108, 50), g.doctor.name(), 28, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
	var dn_w := g.font.get_string_size(g.doctor.name(), HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
	var en_w := UI.en(g.hud, g.font, r.position + Vector2(118 + dn_w, 48), g.doctor.def.get("en", "DOCTOR") + "  ·  STATUS", 12, UI.CYAN, 3.0)
	var cx0 := maxf(r.position.x + 350, r.position.x + 118 + dn_w + en_w + 18)
	cx0 += UI.chip(g.hud, g.font, Vector2(cx0, r.position.y + 32), "Lv.%d" % g.level, UI.GLOW, 12) + 8
	cx0 += UI.chip(g.hud, g.font, Vector2(cx0, r.position.y + 32), "编队 %d/%d" % [g.squad.size(), g.squad.cap()], UI.CYAN_DIM, 12) + 8
	cx0 += UI.chip(g.hud, g.font, Vector2(cx0, r.position.y + 32), "难度 %d「%s」" % [g.diff, D.DIFFICULTY[g.diff].name], UI.CYAN_DIM, 12) + 14
	cx0 += UI.chip(g.hud, g.font, Vector2(cx0, r.position.y + 32), g.endg.cur_name(), g.endg.cur_col(), 11) + 14
	# 角色能力标签（来自角色 JSON）
	for tg in g.ch.display_tags():
		cx0 += UI.chip(g.hud, g.font, Vector2(cx0, r.position.y + 32), tg, UI.PURPLE, 11) + 6
	UI.rule(g.hud, r.position + Vector2(24, 82), Vector2(r.end.x - 24, r.position.y + 82), UI.EDGE_DIM)
	# 三个子面板
	g.stats_cells.clear()
	var top := r.position.y + 98
	var h := r.end.y - 44 - top
	var boxes: Array = [Rect2(r.position.x + 22, top, 330, h), Rect2(r.position.x + 366, top, 330, h), Rect2(r.position.x + 710, top, r.size.x - 732, h)]
	for b in boxes:
		UI.frame(g.hud, b, UI.EDGE, {"cut": 8.0, "bracket": 8.0, "alpha": 0.6})
	# ---- 生存
	var b0: Rect2 = boxes[0]
	UI.text(g.hud, g.font, b0.position + Vector2(16, 26), "生存", 16, UI.CYAN)
	UI.en(g.hud, g.font, b0.position + Vector2(60, 25), "SURVIVAL", 10, UI.CYAN_DIM, 3.0)
	var y: float = b0.position.y + 48
	UI.text(g.hud, g.font, b0.position + Vector2(16, y - b0.position.y + 12), "生命", 13, UI.SUB)
	UI.gbar(g.hud, Rect2(b0.position.x + 70, y, 180, 10), g.hp / g.max_hp, UI.CYAN, 10)
	UI.text(g.hud, g.font, Vector2(b0.position.x + 258, y + 11), "%d / %d" % [int(g.hp), int(g.max_hp)], 13, UI.TEXT)
	y += 26
	UI.text(g.hud, g.font, Vector2(b0.position.x + 16, y + 12), "灯火", 13, UI.SUB)
	UI.gbar(g.hud, Rect2(b0.position.x + 70, y, 180, 10), g.lamp / 100.0, UI.GOLD, 10)
	UI.text(g.hud, g.font, Vector2(b0.position.x + 258, y + 11), "%d" % int(g.lamp), 13, UI.TEXT)
	y += 30
	var rows0 := [
		["生命回复", "%.1f / 秒" % (g.regen + g.regen_pct * g.max_hp)], ["物理减伤 / 法抗", "%d / %d%%" % [int(g.armor), int(g.arts_res * 100.0)]], ["闪避 物 / 法", "%d%% / %d%%" % [int(minf(g.dodge + g.dodge_phys, 0.6) * 100.0), int(minf(g.dodge + g.dodge_arts, 0.6) * 100.0)]],
		["移动速度", "%d" % int(g.speed)], ["拾取范围", "%d" % int(g.pickup)], ["受击灯火损失", "×%.2f" % g.lamp_decay],
		["照亮范围", "%d" % int(g._lamp_r())],
		["护盾", ("%d / %d · 每 %.1f 秒" % [g.shield, g.shield_max, g.shield_every]) if g.shield_max > 0 else "无"],
	]
	for row in rows0:
		UI.text(g.hud, g.font, Vector2(b0.position.x + 16, y + 12), row[0], 14, UI.SUB)
		UI.text_fit(g.hud, g.font, Vector2(b0.position.x + 130, y + 12), row[1], 14, UI.TEXT, b0.size.x - 146.0, 10)
		g.hud.draw_rect(Rect2(b0.position.x + 16, y + 19, b0.size.x - 32, 1), Color(1, 1, 1, 0.05))
		y += 25
	# ---- 攻击
	var b1: Rect2 = boxes[1]
	UI.text(g.hud, g.font, b1.position + Vector2(16, 26), "攻击", 16, UI.CYAN)
	UI.en(g.hud, g.font, b1.position + Vector2(60, 25), "OFFENSE", 10, UI.CYAN_DIM, 3.0)
	var rows1: Array = g.ch.stats_rows()
	rows1.append_array([
		["近战 / 远程", "×%.2f / ×%.2f" % [g.melee_mult, g.ranged_mult]], ["物理 / 法术", "×%.2f / ×%.2f" % [g.phys_mult, g.arts_mult]],
		["本局构成", dmg_mix_text()],
	])
	y = b1.position.y + 48
	# 属性行的行高按剩余空间收：下半的技能列表每条至少要「名字 + 一行说明」的高度（干员属性行多时不再挤出面板）
	var skill_rows: Array = g._skill_rows_data()
	var need_sk: float = skill_rows.size() * maxf(42.0, 30.0 + g.font.get_height(11) + 1.0) + 18.0
	var rh1: float = clampf((b1.end.y - 6.0 - y - need_sk) / maxf(1.0, rows1.size()), 19.0, 25.0)
	var rfs := 14 if rh1 >= 23.0 else 13
	for row in rows1:
		UI.text(g.hud, g.font, Vector2(b1.position.x + 16, y + 12), row[0], rfs, UI.SUB)
		UI.text_fit(g.hud, g.font, Vector2(b1.position.x + 130, y + 12), row[1], rfs, UI.TEXT, b1.size.x - 146.0, 10)
		g.hud.draw_rect(Rect2(b1.position.x + 16, y + rh1 - 6, b1.size.x - 32, 1), Color(1, 1, 1, 0.05))
		y += rh1
	# 技能（攻击面板下半）
	y += 8
	UI.rule(g.hud, Vector2(b1.position.x + 16, y), Vector2(b1.end.x - 16, y), UI.EDGE_DIM)
	y += 10
	y = g.result_screen.draw_generic_skill_rows(b1, y, skill_rows)
	# ---- 队伍与成长
	var b2: Rect2 = boxes[2]
	UI.text(g.hud, g.font, b2.position + Vector2(16, 26), "队伍与成长", 16, UI.CYAN)
	UI.en(g.hud, g.font, b2.position + Vector2(110, 25), "BUILD", 10, UI.CYAN_DIM, 3.0)
	y = b2.position.y + 44
	UI.text(g.hud, g.font, Vector2(b2.position.x + 16, y + 12), "编队 %d/%d" % [g.squad.size(), g.squad.cap()], 13, UI.SUB)
	y += 22
	for o in g.squad.ops:
		var ax2: float = b2.position.x + 16
		var opt: Dictionary = o.portrait()
		var at: Texture2D = g.tex.get(opt.tex)
		if at != null:
			var fw := at.get_width() / int(opt.frames)
			var ks := 26.0 / at.get_height()
			g.hud.draw_texture_rect_region(at, Rect2(Vector2(ax2, y - 6), Vector2(fw, at.get_height()) * ks), Rect2(0, 0, fw, at.get_height()))
			ax2 += fw * ks + 6
		UI.text(g.hud, g.font, Vector2(ax2, y + 12), "%s · %s" % [o.display_name(), o.cls], 13, UI.TEXT)
		ax2 += 116
		ax2 += UI.chip(g.hud, g.font, Vector2(ax2, y), ["精零", "精一", "精二"][o.elite], UI.GOLD if o.elite > 0 else UI.SUB, 10) + 6
		# 成长线进度点
		var pg: Array = o.progression()
		for k in pg.size():
			var dc := Vector2(ax2 + k * 12, y + 8)
			var done: bool = k < o.prog
			var is_elite: bool = pg[k].get("type", "") == "elite"
			if is_elite:
				UI.diamond(g.hud, dc, 4.0, UI.GOLD if done else Color(0.08, 0.14, 0.18), Color(1.0, 0.85, 0.5, 0.8))
			else:
				g.hud.draw_circle(dc, 3.0, Color(0.55, 0.9, 0.55) if done else Color(0.1, 0.18, 0.22))
		ax2 += pg.size() * 12 + 8
		var nn: Dictionary = o.next_node()
		if not nn.is_empty():
			var rq: String = o.node_requires_text(nn)
			var ok_rq: bool = o.node_available(nn)
			UI.text(g.hud, g.font, Vector2(ax2, y + 12), ("下一步：%s" % nn.get("name", "")) + (("（需%s）" % rq) if rq != "" and not ok_rq else ""), 11, UI.SUB if ok_rq else Color(1.0, 0.7, 0.5), HORIZONTAL_ALIGNMENT_LEFT, b2.end.x - ax2 - 12)
		else:
			UI.text(g.hud, g.font, Vector2(ax2, y + 12), "已满", 11, UI.GOLD)
		y += 30
	y += 6
	UI.text(g.hud, g.font, Vector2(b2.position.x + 16, y + 12), "支援", 13, UI.SUB)
	var ax2: float = b2.position.x + 90
	if g.weapons.is_empty():
		UI.text(g.hud, g.font, Vector2(ax2, y + 12), "暂无", 13, UI.SUB)
	for wid in g.weapons:
		var wt: Texture2D = g.tex.get("weapon_" + wid)
		if wt != null:
			g.hud.draw_texture_rect(wt, Rect2(Vector2(ax2, y - 6), Vector2(32, 32)), false)
		UI.text(g.hud, g.font, Vector2(ax2 + 36, y + 14), "%s  Lv.%d" % [D.WEAPONS[wid].name, g.weapons[wid]], 13, D.WEAPONS[wid].col)
		ax2 += 150
	y += 36
	UI.rule(g.hud, Vector2(b2.position.x + 16, y), Vector2(b2.end.x - 16, y), UI.EDGE_DIM)
	y += 8
	UI.text(g.hud, g.font, Vector2(b2.position.x + 16, y + 12), "成长", 13, UI.SUB)
	y += 22
	# 成长 + 藏品：两块图标网格共用剩余高度，格子取「全部放得下」的最大尺寸（46 → 26 像素），
	# 不再出现数量多了后面的图标被藏起来的情况；悬停看效果
	var gx: float = b2.position.x + 16
	var gy: float = y
	var ng: int = g.growth.size()
	var nr: int = g.relics.size()
	var room: float = b2.end.y - 8.0 - gy - 36.0
	var pitch := 46.0
	var per := 1
	for pc in [46.0, 40.0, 34.0, 30.0, 26.0]:
		pitch = pc
		per = maxi(1, int((b2.size.x - 32) / pitch))
		if (maxi(1, int(ceil(ng / float(per)))) + maxi(1, int(ceil(nr / float(per))))) * pitch <= room:
			break
	var cs := pitch - 6.0
	var isz := cs - 6.0
	var gi := 0
	for gid in g.growth:
		var gc := Vector2(gx + (gi % per) * pitch, gy + (gi / per) * pitch)
		if gc.y + cs > b2.end.y - 2:
			break
		g.hud.draw_rect(Rect2(gc, Vector2(cs, cs)), Color(0.03, 0.035, 0.045, 0.9))
		g.hud.draw_rect(Rect2(gc, Vector2(cs, cs)), UI.EDGE_DIM, false, 1.0)
		var gt: Texture2D = g.tex.get("growth_" + gid)
		if gt != null:
			g.hud.draw_texture_rect(gt, Rect2(gc + Vector2(3, 3), Vector2(isz, isz)), false)
		else:
			UI.text(g.hud, g.font, gc + Vector2(0, cs * 0.68), g.progression.growth_def(gid).name.substr(0, 1), int(cs * 0.42), UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, cs)
		UI.text(g.hud, g.font, gc + Vector2(cs - 18, cs - 1), "×%d" % g.growth[gid], 10, UI.GOLD, HORIZONTAL_ALIGNMENT_RIGHT, 18, 2)
		g.stats_cells.append([Rect2(gc, Vector2(cs, cs)), "growth", gid])
		gi += 1
	y = gy + maxi(1, int(ceil(ng / float(per)))) * pitch + 6
	UI.rule(g.hud, Vector2(b2.position.x + 16, y), Vector2(b2.end.x - 16, y), UI.EDGE_DIM)
	y += 8
	UI.text(g.hud, g.font, Vector2(b2.position.x + 16, y + 12), "藏品  %d 件" % g.relics.size(), 13, UI.SUB)
	UI.text(g.hud, g.font, Vector2(b2.position.x + 120, y + 12), "鼠标移到图标上查看效果", 11, UI.CYAN_DIM)
	y += 22
	var mouse2 := g.hud.get_local_mouse_position()
	for i in nr:
		var rc := Vector2(gx + (i % per) * pitch, y + (i / per) * pitch)
		if rc.y + cs > b2.end.y - 2:
			break
		var rd: Dictionary = g.RL[g.relics[i]]
		var rcol: Color = UI.CAT_COL.get(rd.cat, UI.GOLD)
		var cr := Rect2(rc, Vector2(cs, cs))
		var hov: bool = cr.has_point(mouse2)
		g.hud.draw_rect(cr, Color(0.03, 0.035, 0.045, 0.9) if not hov else Color(rcol.r * 0.25, rcol.g * 0.25, rcol.b * 0.25, 0.95))
		g.hud.draw_rect(cr, Color(1, 1, 1, 0.13) if not hov else rcol, false, 1.0)
		g.hud.draw_rect(Rect2(rc, Vector2(8, 2)), Color(rcol.r, rcol.g, rcol.b, 0.85))
		var rt: Texture2D = g.tex.get("relic_" + g.relics[i])
		if rt != null:
			g.hud.draw_texture_rect(rt, Rect2(rc + Vector2(3, 3), Vector2(isz, isz)), false)
		else:
			UI.text(g.hud, g.font, rc + Vector2(0, cs * 0.68), rd.name.substr(0, 1), int(cs * 0.42), rcol, HORIZONTAL_ALIGNMENT_CENTER, cs)
		var rl: int = g.rfx.lv.get(g.relics[i], 1)
		if rl > 1:
			UI.text(g.hud, g.font, rc + Vector2(cs - 18, cs - 1), "L%d" % rl, 10, UI.GOLD, HORIZONTAL_ALIGNMENT_RIGHT, 18, 2)
		g.stats_cells.append([cr, "relic", g.relics[i]])
	UI.text(g.hud, g.font, Vector2(r.position.x, r.end.y - 18), ("藏品 %d 件  ·  击杀 %d  ·  源石锭 %d  ·  " % [g.relics.size(), g.kills, g.ingots]) + Pad.hint("按 Tab / C / Esc 返回", "按 SELECT / Ⓑ 返回"), 13, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	# 悬停提示（藏品 / 成长）
	for cellinfo in g.stats_cells:
		var cr2: Rect2 = cellinfo[0]
		if not cr2.has_point(mouse2):
			continue
		if cellinfo[1] == "skill":
			var srow: Array = cellinfo[2]
			g._draw_tooltip(vs, cr2, srow[1], "天赋" if srow[0] == "赋" else "技能 %s" % srow[0], srow[2], "", g.ch.col())
		elif cellinfo[1] == "relic":
			var rd2: Dictionary = g.RL[cellinfo[2]]
			g._draw_tooltip(vs, cr2, rd2.name + ((" Lv.%d/%d" % [g.rfx.lv.get(cellinfo[2], 1), g.rfx.max_lv(cellinfo[2])]) if g.rfx.max_lv(cellinfo[2]) > 1 else ""), "%s · %s" % [rd2.cat, rd2.rarity], rd2.desc, "relic_" + cellinfo[2], UI.CAT_COL.get(rd2.cat, UI.GOLD))
		else:
			var gd: Dictionary = g.progression.growth_def(cellinfo[2])
			g._draw_tooltip(vs, cr2, "%s  ×%d" % [gd.name, g.growth[cellinfo[2]]], "成长 · 上限 %d" % gd.max, gd.desc, "growth_" + cellinfo[2], UI.GLOW)
		break
