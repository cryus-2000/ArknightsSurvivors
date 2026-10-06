extends RefCounted
## 界面 · 属性面板（Tab，state STATS）：主控属性、编队干员、伤害构成与藏品。
## 界面层约定（docs/39 §3）。2026-09-26 从 game.gd 拆出。

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
	if Cfg.touch_device():
		draw_phone(vs)
		return
	g.hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.02, 0.05, 0.82))
	# 紧凑（逻辑高 < 680，手机触屏 626）：边距收窄、标题行压低，攻击栏下半的技能列表才放得下（原来挤出面板压到底栏）
	var compact: bool = vs.y < 680.0
	var r := Rect2(36, 14, vs.x - 72, vs.y - 28) if compact else Rect2(60, 44, vs.x - 120, vs.y - 88)
	UI.frame(g.hud, r, UI.GLOW, {"t": g.t, "vines": true, "seed": 31, "cut": 14.0, "bracket": 14.0, "glow": 0.3})
	UI.caustic(g.hud, Rect2(r.position + Vector2(20, 8), Vector2(r.size.x - 40, 22)), g.t, UI.GLOW)
	# 标题行
	# 标题是主控干员（v0.7：受击、属性都在主控身上），头像取其待机帧
	var ld = g.squad.leader() if g.squad.leader() != null else g.ch
	var idle: Dictionary = g.panel_ui.op_idle(ld.id)
	if not idle.is_empty():
		var pt: Texture2D = idle.tex
		var fw: int = idle.fw
		var fh: int = idle.fh
		var fr := int(g.t * 2.0) % maxi(1, pt.get_width() / fw)
		var k: float = 72.0 / float(fh) if fh > 0 else 1.0
		g.hud.draw_texture_rect_region(pt, Rect2(r.position + Vector2(26, 6), Vector2(fw, fh) * k), Rect2(fr * fw, 0, fw, fh))
	var ln: String = ld.display_name()
	UI.text(g.hud, g.font, r.position + Vector2(108, 50), ln, 28, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
	var dn_w := g.font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
	var en_w := UI.en(g.hud, g.font, r.position + Vector2(118 + dn_w, 48), str(ld.def.get("en", ld.id.to_upper())) + "  ·  LEADER  ·  STATUS", 12, UI.CYAN, 3.0)
	var cx0 := maxf(r.position.x + 350, r.position.x + 118 + dn_w + en_w + 18)
	cx0 += UI.chip(g.hud, g.font, Vector2(cx0, r.position.y + 32), "Lv.%d" % g.level, UI.GLOW, 12) + 8
	cx0 += UI.chip(g.hud, g.font, Vector2(cx0, r.position.y + 32), "编队 %d/%d" % [g.squad.size(), g.squad.cap()], UI.CYAN_DIM, 12) + 8
	cx0 += UI.chip(g.hud, g.font, Vector2(cx0, r.position.y + 32), str(D.DIFFICULTY_TIERS[g.tier].name), UI.CYAN_DIM, 12) + 14   # 档名本身已经能认出是难度（「波涛迭起·Ⅷ」），不再套「难度「」」，免得标签行过长
	cx0 += UI.chip(g.hud, g.font, Vector2(cx0, r.position.y + 32), g.endg.cur_name(), g.endg.cur_col(), 11) + 14
	# 角色能力标签（来自角色 JSON）
	for tg in g.ch.display_tags():
		cx0 += UI.chip(g.hud, g.font, Vector2(cx0, r.position.y + 32), tg, UI.PURPLE, 11) + 6
	UI.rule(g.hud, r.position + Vector2(24, 82), Vector2(r.end.x - 24, r.position.y + 82), UI.EDGE_DIM)
	# 三个子面板
	g.stats_cells.clear()
	# 触屏（手机，逻辑高 626）：三栏并排字只有 6–7 pt 看不清，改成三页（属性 / 技能 / 编队）轮流占整个面板，字号放大；
	# 页签放在标题行下面，点击区按 touch.gd HIT 外扩。桌面排版不变（page = -1 走原来的三栏）
	var touch: bool = Cfg.touch_device()
	var page: int = clampi(g.stats_page, 0, 2) if touch else -1
	var top := r.position.y + (90.0 if compact else 98.0)
	if touch:
		var tabs := ["属性", "技能", "编队"]
		var tabs_en := ["STATS", "SKILLS", "SQUAD"]
		for i in tabs.size():
			var tr := Rect2(r.position.x + 22 + i * 164.0, r.position.y + 90, 152, 36)
			var on: bool = i == page
			g.hud.draw_rect(tr, Color(0.05, 0.2, 0.24, 0.8) if on else Color(1, 1, 1, 0.04))
			g.hud.draw_rect(Rect2(tr.position.x, tr.end.y - 3, tr.size.x, 3), UI.CYAN if on else Color(1, 1, 1, 0.12))
			UI.text(g.hud, g.font, tr.position + Vector2(14, 25), tabs[i], 17, UI.TEXT if on else UI.SUB)
			UI.en(g.hud, g.font, tr.position + Vector2(66, 24), tabs_en[i], 9, UI.CYAN if on else UI.CYAN_DIM, 2.0)
			g.stats_cells.append([tr, "tab", i])
		top = r.position.y + 136.0
	var h := r.end.y - 44 - top
	var boxes: Array = [Rect2(r.position.x + 22, top, 330, h), Rect2(r.position.x + 366, top, 330, h), Rect2(r.position.x + 710, top, r.size.x - 732, h)]
	if touch:
		var bw2: float = (r.size.x - 44.0 - 14.0) / 2.0
		boxes = [Rect2(r.position.x + 22, top, bw2, h), Rect2(r.position.x + 22 + bw2 + 14.0, top, bw2, h), Rect2(r.position.x + 22, top, r.size.x - 44.0, h)]
	# 字号 / 行距：触屏放大（桌面值不变）
	var fs_sub := 16 if touch else 13      # 小标题 / 标签（「生命」「编队 1/3」）
	var fs_row := 17 if touch else 14      # 属性行
	var fs_min := 14 if touch else 11      # 次要小字（下一步 / 提示）
	var fs_tag := 12 if touch else 10      # 标签片 / 角标
	var row_h := 30.0 if touch else 25.0   # 生存行距
	var sq_h := 38.0 if touch else 30.0    # 编队每人行距
	for bi in boxes.size():
		if page < 0 or (page == 0 and bi < 2) or (page > 0 and bi == 2):
			UI.frame(g.hud, boxes[bi], UI.EDGE, {"cut": 8.0, "bracket": 8.0, "alpha": 0.6})
	var y: float = 0.0
	# ---- 生存
	var b0: Rect2 = boxes[0]
	if page <= 0:
		UI.text(g.hud, g.font, b0.position + Vector2(16, 26), "生存", 16, UI.CYAN)
		UI.en(g.hud, g.font, b0.position + Vector2(60, 25), "SURVIVAL", 10, UI.CYAN_DIM, 3.0)
		y = b0.position.y + 48
		var barw: float = 180.0 if not touch else b0.size.x - 190.0
		UI.text(g.hud, g.font, b0.position + Vector2(16, y - b0.position.y + 12), "生命", fs_sub, UI.SUB)
		UI.gbar(g.hud, Rect2(b0.position.x + 70, y, barw, 10), g.hp / g.max_hp, UI.CYAN, 10)
		UI.text(g.hud, g.font, Vector2(b0.position.x + 78 + barw, y + 11), "%d / %d" % [int(g.hp), int(g.max_hp)], fs_sub, UI.TEXT)
		y += 26 if not touch else 30
		UI.text(g.hud, g.font, Vector2(b0.position.x + 16, y + 12), "灯火", fs_sub, UI.SUB)
		UI.gbar(g.hud, Rect2(b0.position.x + 70, y, barw, 10), g.lamp / 100.0, UI.GOLD, 10)
		UI.text(g.hud, g.font, Vector2(b0.position.x + 78 + barw, y + 11), "%d" % int(g.lamp), fs_sub, UI.TEXT)
		y += 30
	var rows0 := [
		["生命回复", "%.1f / 秒" % (g.regen + g.regen_pct * g.max_hp)], ["物理减伤 / 法抗", "%d / %d%%" % [int(g.armor), int(g.arts_res * 100.0)]], ["闪避 物 / 法", "%d%% / %d%%" % [int(minf(g.dodge + g.dodge_phys, 0.6) * 100.0), int(minf(g.dodge + g.dodge_arts, 0.6) * 100.0)]],
		["移动速度", "%d" % int(g.speed)], ["拾取范围", "%d" % int(g.pickup)], ["受击灯火损失", "×%.2f" % g.lamp_decay],
		["照亮范围", "%d" % int(g._lamp_r())],
		["护盾", ("%d / %d · 每 %.1f 秒" % [g.shield, g.shield_max, g.shield_every]) if g.shield_max > 0 else "无"],
	]
	var vx0: float = 130.0 if not touch else 170.0   # 数值列的 x
	if page <= 0:
		for row in rows0:
			UI.text(g.hud, g.font, Vector2(b0.position.x + 16, y + 12), row[0], fs_row, UI.SUB)
			UI.text_fit(g.hud, g.font, Vector2(b0.position.x + vx0, y + 12), row[1], fs_row, UI.TEXT, b0.size.x - vx0 - 16.0, 10)
			g.hud.draw_rect(Rect2(b0.position.x + 16, y + row_h - 6, b0.size.x - 32, 1), Color(1, 1, 1, 0.05))
			y += row_h
	# ---- 攻击
	var b1: Rect2 = boxes[1]
	var skill_rows: Array = skill_rows_data()
	if page <= 0:
		UI.text(g.hud, g.font, b1.position + Vector2(16, 26), "攻击", 16, UI.CYAN)
		UI.en(g.hud, g.font, b1.position + Vector2(60, 25), "OFFENSE", 10, UI.CYAN_DIM, 3.0)
		var rows1: Array = g.ch.stats_rows()
		rows1.append_array([
			["近战 / 远程", "×%.2f / ×%.2f" % [g.melee_mult, g.ranged_mult]], ["物理 / 法术", "×%.2f / ×%.2f" % [g.phys_mult, g.arts_mult]],
			["本局构成", dmg_mix_text()],
		])
		y = b1.position.y + 48
		# 属性行的行高按剩余空间收：下半的技能列表每条至少要「名字 + 一行说明」的高度（干员属性行多时不再挤出面板）
		var need_sk: float = skill_rows.size() * maxf(42.0, 30.0 + g.font.get_height(11) + 1.0) + 18.0
		var rh1: float = clampf((b1.end.y - 6.0 - y - need_sk) / maxf(1.0, rows1.size()), 17.0 if compact else 19.0, 25.0)
		var rfs := 14 if rh1 >= 23.0 else 13
		if touch:
			# 触屏：技能在第二页，这页只有属性行，行距按剩余高度放到 30
			rh1 = clampf((b1.end.y - 6.0 - y) / maxf(1.0, rows1.size()), 22.0, row_h)
			rfs = fs_row if rh1 >= 27.0 else 15
		for row in rows1:
			UI.text(g.hud, g.font, Vector2(b1.position.x + 16, y + 12), row[0], rfs, UI.SUB)
			UI.text_fit(g.hud, g.font, Vector2(b1.position.x + vx0, y + 12), row[1], rfs, UI.TEXT, b1.size.x - vx0 - 16.0, 10)
			g.hud.draw_rect(Rect2(b1.position.x + 16, y + rh1 - 6, b1.size.x - 32, 1), Color(1, 1, 1, 0.05))
			y += rh1
	if page < 0:
		# 技能（攻击面板下半）
		y += 8
		UI.rule(g.hud, Vector2(b1.position.x + 16, y), Vector2(b1.end.x - 16, y), UI.EDGE_DIM)
		y += 10
		y = g.result_screen.draw_generic_skill_rows(b1, y, skill_rows)
	elif page == 1:
		# 触屏第二页：技能 + 天赋占整个面板，说明 15 号字
		var bs: Rect2 = boxes[2]
		UI.text(g.hud, g.font, bs.position + Vector2(16, 26), "技能与天赋", 16, UI.CYAN)
		UI.en(g.hud, g.font, bs.position + Vector2(110, 25), "SKILLS", 10, UI.CYAN_DIM, 3.0)
		g.result_screen.draw_generic_skill_rows(bs, bs.position.y + 44, skill_rows, 15, 18)
	# ---- 队伍与成长
	if page == 0 or page == 1:
		_draw_footer(vs, r)   # 触屏第一 / 二页没有编队栏
		return
	var b2: Rect2 = boxes[2]
	UI.text(g.hud, g.font, b2.position + Vector2(16, 26), "队伍与成长", 16, UI.CYAN)
	UI.en(g.hud, g.font, b2.position + Vector2(110, 25), "BUILD", 10, UI.CYAN_DIM, 3.0)
	y = b2.position.y + 44
	UI.text(g.hud, g.font, Vector2(b2.position.x + 16, y + 12), "编队 %d/%d" % [g.squad.size(), g.squad.cap()], fs_sub, UI.SUB)
	y += 22 if not touch else 28
	for o in g.squad.ops:
		var ax2: float = b2.position.x + 16
		var opt: Dictionary = o.portrait()
		var at: Texture2D = g.tex.get(opt.tex)
		if at != null:
			var fw := at.get_width() / int(opt.frames)
			var ks := (26.0 if not touch else 32.0) / at.get_height()
			g.hud.draw_texture_rect_region(at, Rect2(Vector2(ax2, y - 6), Vector2(fw, at.get_height()) * ks), Rect2(0, 0, fw, at.get_height()))
			ax2 += fw * ks + 6
		UI.text(g.hud, g.font, Vector2(ax2, y + 12), "%s · %s" % [o.display_name(), o.cls], fs_sub, UI.TEXT)
		ax2 += 116 if not touch else 150
		ax2 += UI.chip(g.hud, g.font, Vector2(ax2, y), ["精零", "精一", "精二"][o.elite], UI.GOLD if o.elite > 0 else UI.SUB, fs_tag) + 6
		# 成长线进度点
		var pg: Array = o.progression()
		for k in pg.size():
			var dc := Vector2(ax2 + k * 12, y + 8)   # 成长点（桌面 / 触屏同尺寸：点本身不是点击区）
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
			UI.text(g.hud, g.font, Vector2(ax2, y + 12), ("下一步：%s" % nn.get("name", "")) + (("（需%s）" % rq) if rq != "" and not ok_rq else ""), fs_min, UI.SUB if ok_rq else Color(1.0, 0.7, 0.5), HORIZONTAL_ALIGNMENT_LEFT, b2.end.x - ax2 - 12)
		else:
			UI.text(g.hud, g.font, Vector2(ax2, y + 12), "已满", fs_min, UI.GOLD)
		y += sq_h
	y += 6
	UI.text(g.hud, g.font, Vector2(b2.position.x + 16, y + 12), "支援", fs_sub, UI.SUB)
	var ax2: float = b2.position.x + 90
	if g.weapons.is_empty():
		UI.text(g.hud, g.font, Vector2(ax2, y + 12), "暂无", fs_sub, UI.SUB)
	for wid in g.weapons:
		var wt: Texture2D = g.tex.get("weapon_" + wid)
		if wt != null:
			g.hud.draw_texture_rect(wt, Rect2(Vector2(ax2, y - 6), Vector2(32, 32)), false)
		UI.text(g.hud, g.font, Vector2(ax2 + 36, y + 14), "%s  Lv.%d" % [D.WEAPONS[wid].name, g.weapons[wid]], fs_sub, D.WEAPONS[wid].col)
		ax2 += 150 if not touch else 190
	y += 36
	UI.rule(g.hud, Vector2(b2.position.x + 16, y), Vector2(b2.end.x - 16, y), UI.EDGE_DIM)
	y += 8
	UI.text(g.hud, g.font, Vector2(b2.position.x + 16, y + 12), "成长", fs_sub, UI.SUB)
	y += 22 if not touch else 26
	# 成长 + 藏品：两块图标网格共用剩余高度，格子取「全部放得下」的最大尺寸（46 → 26 像素），
	# 不再出现数量多了后面的图标被藏起来的情况；悬停看效果
	var gx: float = b2.position.x + 16
	var gy: float = y
	var ng: int = g.growth.size()
	var nr: int = g.relics.size()
	var room: float = b2.end.y - 8.0 - gy - 36.0
	var pitch := 46.0
	var per := 1
	for pc in ([62.0, 54.0, 46.0, 40.0, 34.0] if touch else [46.0, 40.0, 34.0, 30.0, 26.0]):   # 触屏格子大一号（图标 ≥ 28，手指点得准）
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
		UI.text(g.hud, g.font, gc + Vector2(cs - 18 - (6 if touch else 0), cs - 1), "×%d" % g.growth[gid], fs_tag, UI.GOLD, HORIZONTAL_ALIGNMENT_RIGHT, 18 + (6 if touch else 0), 2)
		g.stats_cells.append([Rect2(gc, Vector2(cs, cs)), "growth", gid])
		gi += 1
	y = gy + maxi(1, int(ceil(ng / float(per)))) * pitch + 6
	UI.rule(g.hud, Vector2(b2.position.x + 16, y), Vector2(b2.end.x - 16, y), UI.EDGE_DIM)
	y += 8
	UI.text(g.hud, g.font, Vector2(b2.position.x + 16, y + 12), "藏品  %d 件" % g.relics.size(), fs_sub, UI.SUB)
	UI.text(g.hud, g.font, Vector2(b2.position.x + (120 if not touch else 150), y + 12), "点图标查看效果" if Pad.touch_ui() else "鼠标移到图标上查看效果", fs_min, UI.CYAN_DIM)
	y += 22 if not touch else 26
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
			UI.text(g.hud, g.font, rc + Vector2(cs - 18 - (6 if touch else 0), cs - 1), "L%d" % rl, fs_tag, UI.GOLD, HORIZONTAL_ALIGNMENT_RIGHT, 18 + (6 if touch else 0), 2)
		g.stats_cells.append([cr, "relic", g.relics[i]])
	_draw_footer(vs, r)


## 底栏汇总 + 悬停提示（藏品 / 成长 / 技能行）
func _draw_footer(vs: Vector2, r: Rect2) -> void:
	var mouse2 := g.hud.get_local_mouse_position()
	UI.text(g.hud, g.font, Vector2(r.position.x, r.end.y - 18), ("藏品 %d 件  ·  击杀 %d  ·  源石锭 %d  ·  " % [g.relics.size(), g.kills, g.ingots]) + Pad.hint("按 Tab / C / Esc 返回", "按 SELECT / Ⓑ 返回", "点空白处返回"), 16 if Cfg.touch_device() else 13, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	# 悬停提示（藏品 / 成长）
	for cellinfo in g.stats_cells:
		var cr2: Rect2 = cellinfo[0]
		if not cr2.has_point(mouse2):
			continue
		if cellinfo[1] == "tab":
			continue
		if cellinfo[1] == "skill":
			var srow: Array = cellinfo[2]
			g.hud_view.draw_tooltip(vs, cr2, srow[1], "天赋" if srow[0] == "赋" else "技能 %s" % srow[0], srow[2], "", g.ch.col())
		elif cellinfo[1] == "relic":
			var rd2: Dictionary = g.RL[cellinfo[2]]
			g.hud_view.draw_tooltip(vs, cr2, rd2.name + ((" Lv.%d/%d" % [g.rfx.lv.get(cellinfo[2], 1), g.rfx.max_lv(cellinfo[2])]) if g.rfx.max_lv(cellinfo[2]) > 1 else ""), "%s · %s" % [rd2.cat, rd2.rarity], rd2.desc, "relic_" + cellinfo[2], UI.CAT_COL.get(rd2.cat, UI.GOLD))
		else:
			var gd: Dictionary = g.progression.growth_def(cellinfo[2])
			g.hud_view.draw_tooltip(vs, cr2, "%s  ×%d" % [gd.name, g.growth[cellinfo[2]]], "成长 · 上限 %d" % gd.max, gd.desc, "growth_" + cellinfo[2], UI.GLOW)
		break


## 手机版（触屏，界面层放大后逻辑约 1044×481，手机端 UI 优化 r2）：五页「属性 / 攻击 / 技能 / 编队 / 藏品」轮流占整个面板，
## 一页只放一类信息：属性行 19 号字、行距 32、两栏；页签 42 高（点击区按 touch.gd HIT 外扩）。桌面排版见 draw()
func draw_phone(vs: Vector2) -> void:
	g.hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.02, 0.05, 0.82))
	var r := Rect2(24, 10, vs.x - 48, vs.y - 20)
	UI.frame(g.hud, r, UI.GLOW, {"t": g.t, "vines": true, "seed": 31, "cut": 14.0, "bracket": 14.0, "glow": 0.3})
	UI.caustic(g.hud, Rect2(r.position + Vector2(20, 8), Vector2(r.size.x - 40, 22)), g.t, UI.GLOW)
	var ld = g.squad.leader() if g.squad.leader() != null else g.ch
	var idle: Dictionary = g.panel_ui.op_idle(ld.id)
	if not idle.is_empty():
		var pt: Texture2D = idle.tex
		var fw: int = idle.fw
		var fh: int = idle.fh
		var fr := int(g.t * 2.0) % maxi(1, pt.get_width() / fw)
		var k: float = 60.0 / float(fh) if fh > 0 else 1.0
		g.hud.draw_texture_rect_region(pt, Rect2(r.position + Vector2(22, 8), Vector2(fw, fh) * k), Rect2(fr * fw, 0, fw, fh))
	var ln: String = ld.display_name()
	UI.text(g.hud, g.font, r.position + Vector2(96, 46), ln, 26, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
	var dn_w := g.font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	var cx0 := r.position.x + 112 + dn_w
	cx0 += UI.chip(g.hud, g.font, Vector2(cx0, r.position.y + 28), "Lv.%d" % g.level, UI.GLOW, 13) + 8
	cx0 += UI.chip(g.hud, g.font, Vector2(cx0, r.position.y + 28), "编队 %d/%d" % [g.squad.size(), g.squad.cap()], UI.CYAN_DIM, 13) + 8
	cx0 += UI.chip(g.hud, g.font, Vector2(cx0, r.position.y + 28), str(D.DIFFICULTY_TIERS[g.tier].name), UI.CYAN_DIM, 13) + 8
	cx0 += UI.chip(g.hud, g.font, Vector2(cx0, r.position.y + 28), g.endg.cur_name(), g.endg.cur_col(), 13) + 8
	for tg in g.ch.display_tags():
		cx0 += UI.chip(g.hud, g.font, Vector2(cx0, r.position.y + 28), tg, UI.PURPLE, 13) + 6
	# 页签
	g.stats_cells.clear()
	var page: int = clampi(g.stats_page, 0, 4)
	var tabs := ["属性", "攻击", "技能", "编队", "藏品"]
	var tabs_en := ["STATS", "OFFENSE", "SKILLS", "SQUAD", "RELICS"]
	var tw: float = (r.size.x - 44.0 - 8.0 * (tabs.size() - 1)) / float(tabs.size())
	for i in tabs.size():
		var tr := Rect2(r.position.x + 22 + i * (tw + 8.0), r.position.y + 72, tw, 42)
		var on: bool = i == page
		g.hud.draw_rect(tr, Color(0.05, 0.2, 0.24, 0.8) if on else Color(1, 1, 1, 0.04))
		g.hud.draw_rect(Rect2(tr.position.x, tr.end.y - 3, tr.size.x, 3), UI.CYAN if on else Color(1, 1, 1, 0.12))
		UI.text(g.hud, g.font, tr.position + Vector2(16, 29), tabs[i], 20, UI.TEXT if on else UI.SUB)
		UI.en(g.hud, g.font, tr.position + Vector2(68, 28), tabs_en[i], 9, UI.CYAN if on else UI.CYAN_DIM, 2.0)
		g.stats_cells.append([tr, "tab", i])
	var top := r.position.y + 126.0
	var b := Rect2(r.position.x + 22, top, r.size.x - 44.0, r.end.y - 34.0 - top)
	UI.frame(g.hud, b, UI.EDGE, {"cut": 8.0, "bracket": 8.0, "alpha": 0.6})
	var fs := 19
	var half: float = (b.size.x - 32.0) / 2.0
	var y: float = b.position.y + 46
	match page:
		0:
			UI.text(g.hud, g.font, b.position + Vector2(16, 28), "生存", 18, UI.CYAN)
			UI.en(g.hud, g.font, b.position + Vector2(62, 27), "SURVIVAL", 10, UI.CYAN_DIM, 3.0)
			var barw := 320.0
			UI.text(g.hud, g.font, Vector2(b.position.x + 16, y + 12), "生命", 18, UI.SUB)
			UI.gbar(g.hud, Rect2(b.position.x + 80, y, barw, 12), g.hp / g.max_hp, UI.CYAN, 12)
			UI.text(g.hud, g.font, Vector2(b.position.x + 92 + barw, y + 12), "%d / %d" % [int(g.hp), int(g.max_hp)], 18, UI.TEXT)
			y += 32
			UI.text(g.hud, g.font, Vector2(b.position.x + 16, y + 12), "灯火", 18, UI.SUB)
			UI.gbar(g.hud, Rect2(b.position.x + 80, y, barw, 12), g.lamp / 100.0, UI.GOLD, 12)
			UI.text(g.hud, g.font, Vector2(b.position.x + 92 + barw, y + 12), "%d" % int(g.lamp), 18, UI.TEXT)
			y += 38
			var rows0 := [
				["生命回复", "%.1f / 秒" % (g.regen + g.regen_pct * g.max_hp)], ["物理减伤 / 法抗", "%d / %d%%" % [int(g.armor), int(g.arts_res * 100.0)]], ["闪避 物 / 法", "%d%% / %d%%" % [int(minf(g.dodge + g.dodge_phys, 0.6) * 100.0), int(minf(g.dodge + g.dodge_arts, 0.6) * 100.0)]],
				["移动速度", "%d" % int(g.speed)], ["拾取范围", "%d" % int(g.pickup)], ["受击灯火损失", "×%.2f" % g.lamp_decay],
				["照亮范围", "%d" % int(g._lamp_r())],
				["护盾", ("%d / %d · 每 %.1f 秒" % [g.shield, g.shield_max, g.shield_every]) if g.shield_max > 0 else "无"],
			]
			_phone_rows(b, y, rows0, fs, half)
		1:
			UI.text(g.hud, g.font, b.position + Vector2(16, 28), "攻击", 18, UI.CYAN)
			UI.en(g.hud, g.font, b.position + Vector2(62, 27), "OFFENSE", 10, UI.CYAN_DIM, 3.0)
			var rows1: Array = g.ch.stats_rows()
			rows1.append_array([
				["近战 / 远程", "×%.2f / ×%.2f" % [g.melee_mult, g.ranged_mult]], ["物理 / 法术", "×%.2f / ×%.2f" % [g.phys_mult, g.arts_mult]],
				["本局构成", dmg_mix_text()],
			])
			_phone_rows(b, y, rows1, fs, half)
		2:
			UI.text(g.hud, g.font, b.position + Vector2(16, 28), "技能与天赋", 18, UI.CYAN)
			UI.en(g.hud, g.font, b.position + Vector2(118, 27), "SKILLS", 10, UI.CYAN_DIM, 3.0)
			g.result_screen.draw_generic_skill_rows(b, b.position.y + 46, skill_rows_data(), 17, 20)
		3:
			_phone_squad(b)
		4:
			_phone_relics(b)
	_draw_footer(vs, r)


## 手机属性行：两栏（左右各一半），每栏 ceil(n/2) 行，行距按剩余高度在 24–32 之间；值列在标签右 190
func _phone_rows(b: Rect2, y: float, rows: Array, fs: int, half: float) -> void:
	var per: int = maxi(1, int(ceil(rows.size() / 2.0)))
	var row_h: float = clampf((b.end.y - 10.0 - y) / float(per), 24.0, 32.0)
	var rfs: int = fs if row_h >= 29.0 else 17
	for i in rows.size():
		var x: float = b.position.x + 16 + (i / per) * (half + 16.0)
		var yy: float = y + (i % per) * row_h
		UI.text(g.hud, g.font, Vector2(x, yy + 12), rows[i][0], rfs, UI.SUB)
		UI.text_fit(g.hud, g.font, Vector2(x + 190, yy + 12), rows[i][1], rfs, UI.TEXT, half - 200.0, 12)
		g.hud.draw_rect(Rect2(x, yy + row_h - 6, half - 8.0, 1), Color(1, 1, 1, 0.05))


## 手机第四页：编队各人（立绘 + 名字 · 职业 + 精英化 + 成长点 + 下一步）与支援装置
func _phone_squad(b2: Rect2) -> void:
	UI.text(g.hud, g.font, b2.position + Vector2(16, 28), "编队 %d/%d" % [g.squad.size(), g.squad.cap()], 18, UI.CYAN)
	UI.en(g.hud, g.font, b2.position + Vector2(100, 27), "SQUAD", 10, UI.CYAN_DIM, 3.0)
	var y: float = b2.position.y + 50
	var sq_h: float = clampf((b2.end.y - 100.0 - y) / maxf(1.0, g.squad.ops.size()), 34.0, 44.0)
	for o in g.squad.ops:
		var ax2: float = b2.position.x + 16
		var opt: Dictionary = o.portrait()
		var at: Texture2D = g.tex.get(opt.tex)
		if at != null:
			var fw := at.get_width() / int(opt.frames)
			var ks := 34.0 / at.get_height()
			g.hud.draw_texture_rect_region(at, Rect2(Vector2(ax2, y - 8), Vector2(fw, at.get_height()) * ks), Rect2(0, 0, fw, at.get_height()))
			ax2 += fw * ks + 8
		UI.text(g.hud, g.font, Vector2(ax2, y + 12), "%s · %s" % [o.display_name(), o.cls], 19, UI.TEXT)
		ax2 += 170
		ax2 += UI.chip(g.hud, g.font, Vector2(ax2, y - 2), ["精零", "精一", "精二"][o.elite], UI.GOLD if o.elite > 0 else UI.SUB, 13) + 8
		var pg: Array = o.progression()
		for k in pg.size():
			var dc := Vector2(ax2 + k * 14, y + 7)
			var done: bool = k < o.prog
			if pg[k].get("type", "") == "elite":
				UI.diamond(g.hud, dc, 5.0, UI.GOLD if done else Color(0.08, 0.14, 0.18), Color(1.0, 0.85, 0.5, 0.8))
			else:
				g.hud.draw_circle(dc, 3.5, Color(0.55, 0.9, 0.55) if done else Color(0.1, 0.18, 0.22))
		ax2 += pg.size() * 14 + 10
		var nn: Dictionary = o.next_node()
		if not nn.is_empty():
			var rq: String = o.node_requires_text(nn)
			var ok_rq: bool = o.node_available(nn)
			UI.text_fit(g.hud, g.font, Vector2(ax2, y + 12), ("下一步：%s" % nn.get("name", "")) + (("（需%s）" % rq) if rq != "" and not ok_rq else ""), 16, UI.SUB if ok_rq else Color(1.0, 0.7, 0.5), b2.end.x - ax2 - 12, 12)
		else:
			UI.text(g.hud, g.font, Vector2(ax2, y + 12), "已满", 16, UI.GOLD)
		y += sq_h
	y += 8
	UI.rule(g.hud, Vector2(b2.position.x + 16, y), Vector2(b2.end.x - 16, y), UI.EDGE_DIM)
	y += 14
	UI.text(g.hud, g.font, Vector2(b2.position.x + 16, y + 12), "支援", 18, UI.SUB)
	var ax3: float = b2.position.x + 90
	if g.weapons.is_empty():
		UI.text(g.hud, g.font, Vector2(ax3, y + 12), "暂无", 18, UI.SUB)
	for wid in g.weapons:
		var wt: Texture2D = g.tex.get("weapon_" + wid)
		if wt != null:
			g.hud.draw_texture_rect(wt, Rect2(Vector2(ax3, y - 8), Vector2(34, 34)), false)
		UI.text(g.hud, g.font, Vector2(ax3 + 40, y + 14), "%s  Lv.%d" % [D.WEAPONS[wid].name, g.weapons[wid]], 18, D.WEAPONS[wid].col)
		ax3 += 210


## 手机第五页：成长 + 藏品两块图标格（格子取全部放得下的最大尺寸，62 → 34），点图标看效果（stats_cells）
func _phone_relics(b2: Rect2) -> void:
	var y: float = b2.position.y
	var gx: float = b2.position.x + 16
	var ng: int = g.growth.size()
	var nr: int = g.relics.size()
	var room: float = b2.end.y - 8.0 - (y + 36.0) - 36.0 - 14.0
	var pitch := 62.0
	var per := 1
	for pc in [62.0, 54.0, 46.0, 40.0, 34.0]:
		pitch = pc
		per = maxi(1, int((b2.size.x - 32) / pitch))
		if (maxi(1, int(ceil(ng / float(per)))) + maxi(1, int(ceil(nr / float(per))))) * pitch <= room:
			break
	var cs := pitch - 6.0
	var isz := cs - 6.0
	UI.text(g.hud, g.font, Vector2(b2.position.x + 16, y + 28), "成长", 18, UI.CYAN)
	UI.en(g.hud, g.font, Vector2(b2.position.x + 62, y + 27), "GROWTH", 10, UI.CYAN_DIM, 3.0)
	var gy: float = y + 40
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
		UI.text(g.hud, g.font, gc + Vector2(cs - 26, cs - 1), "×%d" % g.growth[gid], 13, UI.GOLD, HORIZONTAL_ALIGNMENT_RIGHT, 26, 2)
		g.stats_cells.append([Rect2(gc, Vector2(cs, cs)), "growth", gid])
		gi += 1
	y = gy + maxi(1, int(ceil(ng / float(per)))) * pitch + 6
	UI.rule(g.hud, Vector2(b2.position.x + 16, y), Vector2(b2.end.x - 16, y), UI.EDGE_DIM)
	y += 8
	UI.text(g.hud, g.font, Vector2(b2.position.x + 16, y + 20), "藏品  %d 件" % g.relics.size(), 18, UI.CYAN)
	UI.text(g.hud, g.font, Vector2(b2.position.x + 150, y + 20), "点图标查看效果", 15, UI.CYAN_DIM)
	y += 32
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
			UI.text(g.hud, g.font, rc + Vector2(cs - 26, cs - 1), "L%d" % rl, 13, UI.GOLD, HORIZONTAL_ALIGNMENT_RIGHT, 26, 2)
		g.stats_cells.append([cr, "relic", g.relics[i]])


## Tab 面板攻击栏下半：开局干员的三个技能（招募 / 精一 / 精二解锁）+ 天赋
func skill_rows_data() -> Array:
	var rows: Array = []
	for i in 3:
		var sd: Dictionary = g.ch.skill_def(i)
		var on: bool = g.ch.skill_unlocked(i)
		var need: float = g.ch.sp_need(i)
		var extra: String = ""
		if on and g.ch.perm[i]:
			extra = "（已永久生效）"
		elif on and need > 0.0:
			extra = "（充能 %d · %d%%）" % [int(need), int(100.0 * g.ch.sp[i] / need)]
		elif not on:
			extra = "（%s解锁）" % ["招募", "精英一", "精英二"][i]
		rows.append(["%d" % (i + 1), sd.get("name", "技能 %d" % (i + 1)) + extra, sd.get("desc", ""), on, g.ch.rej.has(i), sd.get("icon", "")])
	var td: Dictionary = g.ch.talent_def()
	if not td.is_empty():
		rows.append(["赋", td.get("name", "天赋") + ("" if g.ch.elite >= 1 else "（精英一解锁）"), td.get("desc", ""), g.ch.elite >= 1, false, ""])
	return rows
