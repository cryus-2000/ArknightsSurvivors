extends RefCounted
## 界面 · 属性面板（Tab，state STATS）：主控属性、编队干员、伤害构成与藏品。
## 界面层约定（docs/39 §3）。2026-09-26 从 game.gd 拆出。

const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
const A = preload("res://scripts/art.gd")
const LinkBond = preload("res://scripts/run/link_bond.gd")   # 「羁绊」一节（docs/221 B1）
const Bal = preload("res://scripts/core/balance.gd")
const UM = preload("res://scripts/ui_motion.gd")

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game


func _init(game: Game) -> void:
	g = game


## 本局造成伤害的构成（按来源前三，占比），Tab 面板与结算用
## 生命回复一行：实际每秒回复（combat.regen_per_sec，与回血逻辑同一个式子）；有入队加成时括号里写出其中多少来自入队（docs/83）
func regen_text() -> String:
	var Sq = preload("res://scripts/characters/squad.gd")
	var sq: float = Sq.regen_bonus(Sq.member_steps(g.squad.size())) * g.heal_mult
	var s := "%.1f / 秒" % g.combat.regen_per_sec()
	return s + ("（入队 +%.1f）" % sq if sq > 0.0 else "")


## 物理减伤一行：固定减伤（armor）；有「硬化」时再写受到的物理伤害比例（docs/83），斜杠后是法抗
func armor_text() -> String:
	var s := "%.1f" % g.armor
	if g.phys_taken_mult < 0.999:
		s += "，物理伤害 -%d%%" % int(round((1.0 - g.phys_taken_mult) * 100.0))
	return s + " / %d%%" % int(round(g.arts_res * 100.0))


## 突击爆发窗口的队友加成（来源 command，squad._tick_rush_buff）：突击中才有这一行
func rush_rows() -> Array:
	var t: String = g.squad.rush_text()
	return [] if t == "" else [["突击加成（队友）", t]]


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
	if Bal.vi("ui/stats_v3", 1) > 0:
		draw_v3(vs)   # 按指挥台统一（docs/222 §19）
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
		var wn: Rect2 = idle.win   # 64 画布取脚底为准的 48 范围（UI.op_win）
		var k: float = 72.0 / wn.size.y if wn.size.y > 0 else 1.0
		g.hud.draw_texture_rect_region(pt, Rect2(r.position + Vector2(26, 6), wn.size * k), Rect2(fr * fw + wn.position.x, wn.position.y, wn.size.x, wn.size.y))
	var ln: String = ld.display_name()
	UI.text(g.hud, g.font, r.position + Vector2(108, 50), ln, 28, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
	var dn_w := g.font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
	var en_w := UI.en(g.hud, g.font, r.position + Vector2(118 + dn_w, 48), str(ld.def.get("en", ld.id.to_upper())) + "  ·  LEADER  ·  STATUS", 12, UI.CYAN, 3.0)
	var cx0 := maxf(r.position.x + 350, r.position.x + 118 + dn_w + en_w + 18)
	cx0 += UI.chip(g.hud, g.font, Vector2(cx0, r.position.y + 32), "Lv.%d" % g.level, UI.GLOW, 12) + 8
	cx0 += UI.chip(g.hud, g.font, Vector2(cx0, r.position.y + 32), "编队 %d/%d" % [g.squad.size(), g.squad.cap()], UI.CYAN_DIM, 12) + 8
	cx0 += UI.chip(g.hud, g.font, Vector2(cx0, r.position.y + 32), D.tier_name(g.tier), UI.CYAN_DIM, 12) + 14   # 档名本身已经能认出是难度（「波涛迭起·Ⅷ」），不再套「难度「」」，免得标签行过长
	cx0 += UI.chip(g.hud, g.font, Vector2(cx0, r.position.y + 32), g.endg.cur_name(), g.endg.cur_col(), 11) + 14
	# 角色能力标签（来自角色 JSON）
	for tg in g.ch.display_tags():
		cx0 += UI.chip(g.hud, g.font, Vector2(cx0, r.position.y + 32), tg, UI.PURPLE, 11) + 6
	UI.rule(g.hud, r.position + Vector2(24, 82), Vector2(r.end.x - 24, r.position.y + 82), UI.EDGE_DIM)
	# 三个子面板
	g.stats_cells.clear()
	# 桌面三栏（触屏在开头已转去 draw_phone；docs/126 C6 删掉了这里走不到的旧「三页」触屏分支）
	var top := r.position.y + (90.0 if compact else 98.0)
	var h := r.end.y - 44 - top
	var boxes: Array = [Rect2(r.position.x + 22, top, 330, h), Rect2(r.position.x + 366, top, 330, h), Rect2(r.position.x + 710, top, r.size.x - 732, h)]
	# 字号 / 行距
	var fs_sub := 13      # 小标题 / 标签（「生命」「编队 1/3」）
	var fs_row := 14      # 属性行
	var fs_min := 11      # 次要小字（下一步 / 提示）
	var fs_tag := 10      # 标签片 / 角标
	var row_h := 25.0     # 生存行距
	var sq_h := 30.0      # 编队每人行距
	for bi in boxes.size():
		UI.frame(g.hud, boxes[bi], UI.EDGE, {"cut": 8.0, "bracket": 8.0, "alpha": 0.6})
	var y: float = 0.0
	# ---- 生存
	var b0: Rect2 = boxes[0]
	UI.text(g.hud, g.font, b0.position + Vector2(16, 26), "生存", 16, UI.CYAN)
	UI.en(g.hud, g.font, b0.position + Vector2(60, 25), "SURVIVAL", 10, UI.CYAN_DIM, 3.0)
	y = b0.position.y + 48
	var barw: float = 180.0
	UI.text(g.hud, g.font, b0.position + Vector2(16, y - b0.position.y + 12), "生命", fs_sub, UI.SUB)
	UI.gbar(g.hud, Rect2(b0.position.x + 70, y, barw, 10), g.hp / g.max_hp, UI.CYAN, 10)
	UI.text(g.hud, g.font, Vector2(b0.position.x + 78 + barw, y + 11), "%d / %d" % [int(g.hp), int(g.max_hp)], fs_sub, UI.TEXT)
	y += 26
	UI.text(g.hud, g.font, Vector2(b0.position.x + 16, y + 12), "灯火", fs_sub, UI.SUB)
	UI.gbar(g.hud, Rect2(b0.position.x + 70, y, barw, 10), g.lamp / 100.0, UI.GOLD, 10)
	UI.text(g.hud, g.font, Vector2(b0.position.x + 78 + barw, y + 11), "%d" % int(g.lamp), fs_sub, UI.TEXT)
	y += 30
	var rows0 := [
		["生命回复", regen_text()], ["物理减伤 / 法抗", armor_text()], ["闪避 物 / 法", "%d%% / %d%%" % [int(minf(g.dodge + g.dodge_phys, 0.6) * 100.0), int(minf(g.dodge + g.dodge_arts, 0.6) * 100.0)]],
		["移动速度", "%d" % int(g.speed)], ["拾取范围", "%d" % int(g.pickup)], ["受击灯火损失", "×%.2f" % g.lamp_decay],
		["照亮范围", "%d" % int(g.lamp_r())],
		["护盾", ("%d / %d · 每 %.1f 秒" % [g.shield, g.shield_max, g.shield_every]) if g.shield_max > 0 else "无"],
	]
	var vx0: float = 130.0   # 数值列的 x
	for row in rows0:
		UI.text(g.hud, g.font, Vector2(b0.position.x + 16, y + 12), row[0], fs_row, UI.SUB)
		UI.text_fit(g.hud, g.font, Vector2(b0.position.x + vx0, y + 12), row[1], fs_row, UI.TEXT, b0.size.x - vx0 - 16.0, 10)
		g.hud.draw_rect(Rect2(b0.position.x + 16, y + row_h - 6, b0.size.x - 32, 1), Color(1, 1, 1, 0.05))
		y += row_h
	# ---- 攻击
	var b1: Rect2 = boxes[1]
	var skill_rows: Array = skill_rows_data()
	UI.text(g.hud, g.font, b1.position + Vector2(16, 26), "攻击", 16, UI.CYAN)
	UI.en(g.hud, g.font, b1.position + Vector2(60, 25), "OFFENSE", 10, UI.CYAN_DIM, 3.0)
	var rows1: Array = g.ch.stats_rows()
	rows1.append_array([
		["近战 / 远程", "×%.2f / ×%.2f" % [g.melee_mult, g.ranged_mult]], ["物理 / 法术", "×%.2f / ×%.2f" % [g.phys_mult, g.arts_mult]],
		["本局构成", dmg_mix_text()],
	])
	rows1.append_array(rush_rows())
	y = b1.position.y + 48
	# 属性行的行高按剩余空间收：下半的技能列表每条至少要「名字 + 一行说明」的高度（干员属性行多时不再挤出面板）
	var need_sk: float = skill_rows.size() * maxf(42.0, 30.0 + g.font.get_height(UI.fs(11)) + 1.0) + 18.0
	var rh1: float = clampf((b1.end.y - 6.0 - y - need_sk) / maxf(1.0, rows1.size()), 17.0 if compact else 19.0, 25.0)
	var rfs := 14 if rh1 >= 23.0 else 13
	for row in rows1:
		UI.text(g.hud, g.font, Vector2(b1.position.x + 16, y + 12), row[0], rfs, UI.SUB)
		UI.text_fit(g.hud, g.font, Vector2(b1.position.x + vx0, y + 12), row[1], rfs, UI.TEXT, b1.size.x - vx0 - 16.0, 10)
		g.hud.draw_rect(Rect2(b1.position.x + 16, y + rh1 - 6, b1.size.x - 32, 1), Color(1, 1, 1, 0.05))
		y += rh1
	# 技能（攻击面板下半）
	y += 8
	UI.rule(g.hud, Vector2(b1.position.x + 16, y), Vector2(b1.end.x - 16, y), UI.EDGE_DIM)
	y += 10
	y = g.result_screen.draw_generic_skill_rows(b1, y, skill_rows)
	# ---- 队伍与成长
	var b2: Rect2 = boxes[2]
	UI.text(g.hud, g.font, b2.position + Vector2(16, 26), "编队与成长", 16, UI.CYAN)
	UI.en(g.hud, g.font, b2.position + Vector2(110, 25), "BUILD", 10, UI.CYAN_DIM, 3.0)
	y = b2.position.y + 44
	UI.text(g.hud, g.font, Vector2(b2.position.x + 16, y + 12), "编队 %d/%d" % [g.squad.size(), g.squad.cap()], fs_sub, UI.SUB)
	y += 22
	for o in g.squad.ops:
		var ax2: float = b2.position.x + 16
		var opt: Dictionary = o.portrait()
		var at: Texture2D = g.tex.get(opt.tex)
		if at != null:
			var fw := at.get_width() / int(opt.frames)
			var wn := UI.op_win(fw, at.get_height(), A.hires_of(at), o.sprite_spec("idle").get("foot", o.def.get("sprites", {}).get("foot", null)))
			var ks := 26.0 / wn.size.y
			g.hud.draw_texture_rect_region(at, Rect2(Vector2(ax2, y - 6), wn.size * ks), wn)
			ax2 += wn.size.x * ks + 6
		UI.text(g.hud, g.font, Vector2(ax2, y + 12), "%s · %s" % [o.display_name(), o.cls], fs_sub, UI.TEXT)
		ax2 += 116
		ax2 += UI.chip(g.hud, g.font, Vector2(ax2, y), ["精零", "精一", "精二"][o.elite], UI.GOLD if o.elite > 0 else UI.SUB, fs_tag) + 6
		# 成长线进度点
		var pg: Array = o.prog_view()
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
		ax2 += 150
	y += 36
	# 羁绊（docs/221 B1）：当前编队成立的每条一行——羁绊名 · 常驻加成 · 合击名
	var fm: Array = LinkBond.formed_now(g)
	if not fm.is_empty():
		UI.text(g.hud, g.font, Vector2(b2.position.x + 16, y + 12), "羁绊", fs_sub, UI.SUB)
		for b in fm:
			UI.diamond(g.hud, Vector2(b2.position.x + 96, y + 8), 3.5, UI.GOLD)
			UI.text_fit(g.hud, g.font, Vector2(b2.position.x + 106, y + 12), LinkBond.row_text(b), fs_min + 1, UI.TEXT, b2.end.x - b2.position.x - 122, 10)
			y += 20
		y += 6
	UI.rule(g.hud, Vector2(b2.position.x + 16, y), Vector2(b2.end.x - 16, y), UI.EDGE_DIM)
	y += 8
	UI.text(g.hud, g.font, Vector2(b2.position.x + 16, y + 12), "成长", fs_sub, UI.SUB)
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
	for pc in [46.0, 40.0, 34.0, 30.0, 26.0, 22.0]:
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
		UI.text(g.hud, g.font, gc + Vector2(cs - 18, cs - 1), "×%d" % g.growth[gid], fs_tag, UI.GOLD, HORIZONTAL_ALIGNMENT_RIGHT, 18, 2)
		g.stats_cells.append([Rect2(gc, Vector2(cs, cs)), "growth", gid])
		gi += 1
	y = gy + maxi(1, int(ceil(ng / float(per)))) * pitch + 6
	UI.rule(g.hud, Vector2(b2.position.x + 16, y), Vector2(b2.end.x - 16, y), UI.EDGE_DIM)
	y += 8
	UI.text(g.hud, g.font, Vector2(b2.position.x + 16, y + 12), "藏品  %d 件" % g.relics.size(), fs_sub, UI.SUB)
	UI.text(g.hud, g.font, Vector2(b2.position.x + 120, y + 12), "点图标查看效果" if Pad.touch_ui() else "鼠标移到图标上查看效果", fs_min, UI.CYAN_DIM)
	y += 22
	var mouse2 := g.hud.get_local_mouse_position()
	var skip: int = _relic_skip(nr, per, pitch, cs, y, b2.end.y - 2.0)
	var slot := 0
	if skip > 0:
		_draw_more_cell(Vector2(gx, y), cs, skip, 13)
		slot = 1
	for i in range(skip, nr):
		var rc := Vector2(gx + (slot % per) * pitch, y + (slot / per) * pitch)
		slot += 1
		if rc.y + cs > b2.end.y - 2:
			break
		var rd: Dictionary = g.RL[g.relics[i]]
		var rcol: Color = UI.CAT_COL.get(rd.lane_name, UI.GOLD)
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
			UI.text(g.hud, g.font, rc + Vector2(cs - 18, cs - 1), "L%d" % rl, fs_tag, UI.GOLD, HORIZONTAL_ALIGNMENT_RIGHT, 18, 2)
		g.stats_cells.append([cr, "relic", g.relics[i]])
	_draw_footer(vs, r)


## 藏品格放不下时省略的件数（较早获得的先省略，第一格让给「+N」）；放得下返回 0
func _relic_skip(nr: int, per: int, pitch: float, cs: float, y0: float, bottom: float) -> int:
	var fit: int = per * maxi(1, int((bottom - y0 - cs) / pitch) + 1)
	return 0 if nr <= fit else nr - (fit - 1)


func _draw_more_cell(p: Vector2, cs: float, n: int, fs: int) -> void:
	var cr := Rect2(p, Vector2(cs, cs))
	g.hud.draw_rect(cr, Color(1, 1, 1, 0.08))
	g.hud.draw_rect(cr, Color(1, 1, 1, 0.22), false, 1.0)
	UI.text(g.hud, g.font, p + Vector2(0, cs * 0.5 + fs * 0.35), "+%d" % n, fs, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, cs)


## 底栏汇总 + 悬停提示（藏品 / 成长 / 技能行）
func _draw_footer(vs: Vector2, r: Rect2) -> void:
	UI.text(g.hud, g.font, Vector2(r.position.x, r.end.y - 18), ("藏品 %d 件  ·  击杀 %d  ·  源石锭 %d  ·  " % [g.relics.size(), g.kills, g.ingots]) + Pad.hint("按 TAB / C / ESC 返回", "按 SELECT / Ⓑ 返回", "点空白处返回"), 16 if Cfg.touch_device() else 13, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	_draw_footer_tips(vs)


## 悬停提示（藏品 / 成长 / 技能行）
func _draw_footer_tips(vs: Vector2) -> void:
	var mouse2 := g.hud.get_local_mouse_position()
	for cellinfo in g.stats_cells:
		var cr2: Rect2 = cellinfo[0]
		if not cr2.has_point(mouse2):
			continue
		if cellinfo[1] == "tab" or cellinfo[1] == "prog":
			continue
		if cellinfo[1] == "skill":
			var srow: Array = cellinfo[2]
			g.hud_view.draw_tooltip(vs, cr2, srow[1], "天赋" if srow[0] == "赋" else ("普攻" if srow[0] == "攻" else "技能 %s" % srow[0]), srow[2], "", g.ch.col())
		elif cellinfo[1] == "relic":
			var rd2: Dictionary = g.RL[cellinfo[2]]
			g.hud_view.draw_tooltip(vs, cr2, rd2.name + ((" Lv.%d/%d" % [g.rfx.lv.get(cellinfo[2], 1), g.rfx.max_lv(cellinfo[2])]) if g.rfx.max_lv(cellinfo[2]) > 1 else ""), "%s · %s" % [rd2.lane_name, rd2.rarity], rd2.desc, "relic_" + cellinfo[2], UI.CAT_COL.get(rd2.lane_name, UI.GOLD))
		else:
			var gd: Dictionary = g.progression.growth_def(cellinfo[2])
			g.hud_view.draw_tooltip(vs, cr2, "%s  ×%d" % [gd.name, g.growth[cellinfo[2]]], "成长 · 上限 %d" % gd.max, g.doctor.passive_desc(cellinfo[2]), "growth_" + cellinfo[2], UI.GLOW)
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
		var wn: Rect2 = idle.win   # 64 画布取脚底为准的 48 范围（UI.op_win）
		var k: float = 60.0 / wn.size.y if wn.size.y > 0 else 1.0
		g.hud.draw_texture_rect_region(pt, Rect2(r.position + Vector2(22, 8), wn.size * k), Rect2(fr * fw + wn.position.x, wn.position.y, wn.size.x, wn.size.y))
	var ln: String = ld.display_name()
	UI.text(g.hud, g.font, r.position + Vector2(96, 46), ln, 26, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
	var dn_w := g.font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	var cx0 := r.position.x + 112 + dn_w
	cx0 += UI.chip(g.hud, g.font, Vector2(cx0, r.position.y + 28), "Lv.%d" % g.level, UI.GLOW, 13) + 8
	cx0 += UI.chip(g.hud, g.font, Vector2(cx0, r.position.y + 28), "编队 %d/%d" % [g.squad.size(), g.squad.cap()], UI.CYAN_DIM, 13) + 8
	cx0 += UI.chip(g.hud, g.font, Vector2(cx0, r.position.y + 28), D.tier_name(g.tier), UI.CYAN_DIM, 13) + 8
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
		UI.en(g.hud, g.font, tr.position + Vector2(28 + _cnw(tabs[i], 20), 28), tabs_en[i], 9, UI.CYAN if on else UI.CYAN_DIM, 2.0)
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
			UI.en(g.hud, g.font, b.position + Vector2(26 + _cnw("生存", 18), 27), "SURVIVAL", 10, UI.CYAN_DIM, 3.0)
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
				["生命回复", regen_text()], ["物理减伤 / 法抗", armor_text()], ["闪避 物 / 法", "%d%% / %d%%" % [int(minf(g.dodge + g.dodge_phys, 0.6) * 100.0), int(minf(g.dodge + g.dodge_arts, 0.6) * 100.0)]],
				["移动速度", "%d" % int(g.speed)], ["拾取范围", "%d" % int(g.pickup)], ["受击灯火损失", "×%.2f" % g.lamp_decay],
				["照亮范围", "%d" % int(g.lamp_r())],
				["护盾", ("%d / %d · 每 %.1f 秒" % [g.shield, g.shield_max, g.shield_every]) if g.shield_max > 0 else "无"],
			]
			_phone_rows(b, y, rows0, fs, half)
		1:
			UI.text(g.hud, g.font, b.position + Vector2(16, 28), "攻击", 18, UI.CYAN)
			UI.en(g.hud, g.font, b.position + Vector2(26 + _cnw("攻击", 18), 27), "OFFENSE", 10, UI.CYAN_DIM, 3.0)
			var rows1: Array = g.ch.stats_rows()
			rows1.append_array([
				["近战 / 远程", "×%.2f / ×%.2f" % [g.melee_mult, g.ranged_mult]], ["物理 / 法术", "×%.2f / ×%.2f" % [g.phys_mult, g.arts_mult]],
				["本局构成", dmg_mix_text()],
			])
			rows1.append_array(rush_rows())
			_phone_rows(b, y, rows1, fs, half)
		2:
			UI.text(g.hud, g.font, b.position + Vector2(16, 28), "技能与天赋", 18, UI.CYAN)
			UI.en(g.hud, g.font, b.position + Vector2(28 + _cnw("技能与天赋", 18), 27), "SKILLS", 10, UI.CYAN_DIM, 3.0)
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
	UI.en(g.hud, g.font, b2.position + Vector2(26 + _cnw("编队 %d/%d" % [g.squad.size(), g.squad.cap()], 18), 27), "SQUAD", 10, UI.CYAN_DIM, 3.0)
	var y: float = b2.position.y + 50
	var sq_h: float = clampf((b2.end.y - 100.0 - y) / maxf(1.0, g.squad.ops.size()), 34.0, 44.0)
	for o in g.squad.ops:
		var ax2: float = b2.position.x + 16
		var opt: Dictionary = o.portrait()
		var at: Texture2D = g.tex.get(opt.tex)
		if at != null:
			var fw := at.get_width() / int(opt.frames)
			var wn := UI.op_win(fw, at.get_height(), A.hires_of(at), o.sprite_spec("idle").get("foot", o.def.get("sprites", {}).get("foot", null)))
			var ks := 34.0 / wn.size.y
			g.hud.draw_texture_rect_region(at, Rect2(Vector2(ax2, y - 8), wn.size * ks), wn)
			ax2 += wn.size.x * ks + 8
		UI.text(g.hud, g.font, Vector2(ax2, y + 12), "%s · %s" % [o.display_name(), o.cls], 19, UI.TEXT)
		ax2 += 170
		ax2 += UI.chip(g.hud, g.font, Vector2(ax2, y - 2), ["精零", "精一", "精二"][o.elite], UI.GOLD if o.elite > 0 else UI.SUB, 13) + 8
		var pg: Array = o.prog_view()
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
	# 羁绊（docs/221 B1）
	var fm: Array = LinkBond.formed_now(g)
	if not fm.is_empty():
		y += 40
		UI.text(g.hud, g.font, Vector2(b2.position.x + 16, y + 12), "羁绊", 18, UI.SUB)
		for b in fm:
			UI.diamond(g.hud, Vector2(b2.position.x + 96, y + 6), 4.5, UI.GOLD)
			UI.text_fit(g.hud, g.font, Vector2(b2.position.x + 110, y + 12), LinkBond.row_text(b), 16, UI.TEXT, b2.end.x - b2.position.x - 126, 12)
			y += 28


## 手机第五页：成长 + 藏品两块图标格（格子取全部放得下的最大尺寸，62 → 34），点图标看效果（stats_cells）
func _phone_relics(b2: Rect2) -> void:
	var y: float = b2.position.y
	var gx: float = b2.position.x + 16
	var ng: int = g.growth.size()
	var nr: int = g.relics.size()
	var room: float = b2.end.y - 8.0 - (y + 36.0) - 36.0 - 14.0
	var pitch := 62.0
	var per := 1
	for pc in [62.0, 54.0, 46.0, 40.0, 34.0, 30.0]:
		pitch = pc
		per = maxi(1, int((b2.size.x - 32) / pitch))
		if (maxi(1, int(ceil(ng / float(per)))) + maxi(1, int(ceil(nr / float(per))))) * pitch <= room:
			break
	var cs := pitch - 6.0
	var isz := cs - 6.0
	UI.text(g.hud, g.font, Vector2(b2.position.x + 16, y + 28), "成长", 18, UI.CYAN)
	UI.en(g.hud, g.font, Vector2(b2.position.x + 26 + _cnw("成长", 18), y + 27), "GROWTH", 10, UI.CYAN_DIM, 3.0)
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
	var skip: int = _relic_skip(nr, per, pitch, cs, y, b2.end.y - 2.0)
	var slot := 0
	if skip > 0:
		_draw_more_cell(Vector2(gx, y), cs, skip, 16)
		slot = 1
	for i in range(skip, nr):
		var rc := Vector2(gx + (slot % per) * pitch, y + (slot / per) * pitch)
		slot += 1
		if rc.y + cs > b2.end.y - 2:
			break
		var rd: Dictionary = g.RL[g.relics[i]]
		var rcol: Color = UI.CAT_COL.get(rd.lane_name, UI.GOLD)
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


## Tab 面板攻击栏下半：开局干员的三个技能（招募 / 精一 / 精二解锁）+ 天赋 + 已获得的普攻形态
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
			extra = "（所需技力 %d · %d%%）" % [int(need), int(100.0 * g.ch.sp[i] / need)]
		elif not on:
			extra = "（%s解锁）" % ["招募", "精英一", "精英二"][i]
		rows.append(["%d" % (i + 1), sd.get("name", "技能 %d" % (i + 1)) + extra, sd.get("desc", ""), on, g.ch.rej.has(i), sd.get("icon", "")])
	var td: Dictionary = g.ch.talent_def()
	if not td.is_empty():
		rows.append(["赋", td.get("name", "天赋") + ("" if g.ch.elite >= 1 else "（精英一解锁）"), td.get("desc", ""), g.ch.elite >= 1, false, ""])
	# 普攻形态（docs/91 §0.5）：已达成的精英化节点写了 attack {name, desc} 的，接在天赋后面（除精英化演出外，局内只有这里看得到）
	for n in g.ch.progression():
		if n is Dictionary and n.get("type", "") == "elite" and n.get("attack", null) is Dictionary and g.ch.elite >= int(n.get("level", 0)):
			rows.append(["攻", "%s（精英%s）" % [str(n.attack.get("name", "普攻")), ["", "一", "二"][clampi(int(n.get("level", 1)), 0, 2)]], str(n.attack.get("desc", "")), true, false, ""])
	return rows


## 手机版小标题后面接英文小标签的位置：按中文实际字宽（含手机放大字号 UI.fs）排，不写死偏移
func _cnw(s: String, size: int) -> float:
	return g.font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.fs(size)).x



# ================================================================ v3：按指挥台统一（docs/222 §19，11-05 用户认可示意图 Claude outputs/stats_panel_1105）
## 不画框、不用彩色标签片，只留一对直角刻度；三栏顺序同指挥台（左 生存 / 中 攻击与技能 / 右 编队、指令、羁绊、成长、藏品）；
## 共用指挥台部件（头像刻度环、马灯、细线、方头像、指令牌）；常态黑白灰，青 = 当前 / 可操作，金 = 灯火 / 羁绊，洋红 = 危险。
## 编队每行的成长进度点：鼠标移上去弹出这名干员的成长节点（已选 / 下一步 / 未选）。只管桌面，手机仍是五页版（draw_phone）。
const V3_WHITE := Color(0.925, 0.933, 0.941)
const V3_GREY := Color(0.588, 0.612, 0.643)
var _hv   # screens/hud.gd

## 入场 / 退场动效（用户 11-05「属性图出来的时候可以增加动效」）：整套 ≤ 0.5 秒，打开当帧就能操作（格子照常登记）；
## 减少动态效果时直接终态。三栏依次入场（错开 0.06 秒，暗幕从栏上退去 + 上移 10 像素）；头像刻度环一格格亮、生命 / 灯火细线
## 从 0 长到当前值、数字从 0 滚上来；编队成长进度点逐个点亮。关闭：一层暗幕 0.15 秒淡出
const ANIM_GAP := 0.06
const ANIM_DUR := 0.3
const CLOSE_T := 0.15
var _last_frame := -10
var _open_rt := 0.0
var _close_rt := -9.0
var _at := 9.0   # 本帧距打开的真实秒数


func _anim_tick() -> void:
	var f: int = Engine.get_process_frames()
	if f - _last_frame > 2:
		_open_rt = UM.now()
	_last_frame = f
	_at = UM.now() - _open_rt


## 第 delay 秒起、dur 秒内 0 → 1（缓出）；减少动态效果时恒为 1
func _ak(delay: float, dur := ANIM_DUR) -> float:
	if UM.rm():
		return 1.0
	return UM.out_cubic(clampf((_at - delay) / dur, 0.0, 1.0))


## 一栏的入场：画完后在栏上盖一层随时间退去的暗幕
func _curtain(r: Rect2, k: float) -> void:
	if k < 1.0:
		g.hud.draw_rect(r, Color(0.008, 0.012, 0.018, 0.97 * (1.0 - k)))


## 关闭后的淡出（hud 每帧调）：上一帧还画着属性栏、这一帧不在 STATS 了，就盖一层 0.15 秒退去的暗幕
func draw_close_fade(vs: Vector2) -> void:
	var f: int = Engine.get_process_frames()
	if g.state != Game.S.STATS and f - _last_frame == 1 and Bal.vi("ui/stats_v3", 1) > 0 and not Cfg.touch_device():
		_close_rt = UM.now()
	if UM.rm():
		return
	var k: float = (UM.now() - _close_rt) / CLOSE_T
	if k >= 0.0 and k < 1.0 and g.state != Game.S.STATS:
		g.hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.008, 0.012, 0.018, 0.9 * (1.0 - k)))


func _v3_head(x: float, y: float, w: float, cn: String, en: String) -> void:
	_hv.v2.txt(Vector2(x, y), cn, 16, V3_WHITE)
	var cw: float = _hv.v2.twidth(cn, 16)
	_hv.v2.cap(Vector2(x + cw + 8, y - 1), en, 6.0, V3_GREY, 1.6)
	g.hud.draw_rect(Rect2(x, y + 8, w, 1), Color(1, 1, 1, 0.2))
	g.hud.draw_rect(Rect2(x, y + 7.5, 18, 2), V3_WHITE)


func _v3_row(x: float, y: float, w: float, lab: String, val: String, fs := 14) -> void:
	_hv.v2.txt(Vector2(x, y), lab, fs, V3_GREY)
	var vw: float = minf(_hv.v2.twidth(val, fs), w * 0.62)
	UI.text_fit(g.hud, g.font, Vector2(x + w - vw, y), val, fs, V3_WHITE, w * 0.62, 10)
	g.hud.draw_rect(Rect2(x, y + 7, w, 1), Color(1, 1, 1, 0.07))


func _v3_hair(x: float, y: float, w: float, frac: float, col: Color, ticks: Array = []) -> void:
	g.hud.draw_rect(Rect2(x, y, w, 1.6), Color(1, 1, 1, 0.16))
	g.hud.draw_rect(Rect2(x, y - 0.8, w * clampf(frac, 0.0, 1.0), 3.2), col)
	for t in ticks:
		g.hud.draw_rect(Rect2(x + w * float(t) - 0.5, y - 3, 1, 7.6), Color(1, 1, 1, 0.45))


func draw_v3(vs: Vector2) -> void:
	_hv = g.hud_view
	_anim_tick()
	g.hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.008, 0.012, 0.018, 0.95))
	g.stats_cells.clear()
	var L := 50.0
	var T := 40.0
	var R: float = vs.x - 50.0
	var B: float = vs.y - 40.0
	var tc := Color(1, 1, 1, 0.45)
	g.hud.draw_polyline(PackedVector2Array([Vector2(L, T + 12), Vector2(L, T), Vector2(L + 12, T)]), tc, 1.0)
	g.hud.draw_polyline(PackedVector2Array([Vector2(R, B - 12), Vector2(R, B), Vector2(R - 12, B)]), tc, 1.0)
	_v3_header(L, T, R)
	_curtain(Rect2(L, T - 20.0, R - L, 118.0), _ak(0.0, 0.2))
	var top: float = T + 118.0
	var gap := 34.0
	var cw: float = (R - L - 2.0 * gap) / 3.0
	var xs: Array = [L, L + cw + gap, L + 2.0 * (cw + gap)]
	for i in [1, 2]:
		g.hud.draw_rect(Rect2(float(xs[i]) - gap / 2.0, top - 4, 1, B - top - 24), Color(1, 1, 1, 0.08))
	for i in 3:
		var k: float = _ak(ANIM_GAP * (i + 1))
		var dy: float = 10.0 * (1.0 - k)
		g.hud.draw_set_transform(Vector2(0, dy))
		match i:
			0:
				_v3_survival(float(xs[0]), top, cw)
			1:
				_v3_offense(float(xs[1]), top, cw, B - 28.0)
			_:
				_v3_squad(float(xs[2]), top, cw, B - 28.0)
		g.hud.draw_set_transform(Vector2.ZERO)
		_curtain(Rect2(float(xs[i]) - 6.0, top - 8.0, cw + 12.0, B - top), k)
	var back: String = Pad.hint("TAB / C / ESC 返回", "SELECT / Ⓑ 返回", "点空白处返回")
	_hv.v2.txt(Vector2(R - _hv.v2.twidth(back, 11), B - 8), back, 11, V3_GREY)
	_v3_tips(vs)


func _v3_header(L: float, T: float, R: float) -> void:
	var ld = g.squad.leader() if g.squad.leader() != null else g.ch
	var c := Vector2(L + 46, T + 50)
	var r := 32.0
	var RR := r + 5.0
	g.hud.draw_circle(c, r + 1, Color(0, 0, 0, 0.6))
	if _hv.ult != null and _hv.ult.v != null:
		_hv.ult.v._avatar_hi(ld, c, r)
	if g.ult != null:
		var full: bool = g.ult.full()
		var ek: float = clampf(g.ult.energy / 100.0, 0.0, 1.0) * _ak(0.05, 0.4)   # 入场：刻度一格格亮到当前充能
		for i in 40:
			var a: float = -PI / 2.0 + TAU * i / 40.0
			var lit: bool = i < int(round(40 * ek))
			g.hud.draw_line(c + Vector2.from_angle(a) * (RR + 2.6), c + Vector2.from_angle(a) * (RR + (6.0 if i % 10 == 0 else 4.4)), (UI.CYAN if full else V3_WHITE) if lit else Color(1, 1, 1, 0.16), 1.0)
		g.hud.draw_arc(c, RR, 0.0, TAU, 56, Color(1, 1, 1, 0.2), 3.0, true)
		if ek > 0.0:
			g.hud.draw_arc(c, RR, -PI / 2.0, -PI / 2.0 + TAU * ek, 56, UI.CYAN if full else V3_WHITE, 3.0, true)
	var lvs: String = "LV %d" % g.level
	var lw: float = UI.cwidth(g.font, lvs, 10) + 12.0
	var lr := Rect2(c.x - lw / 2.0, c.y - RR - 13.0, lw, 15.0)
	g.hud.draw_rect(lr, Color(0.02, 0.03, 0.05, 0.92))
	g.hud.draw_rect(lr, Color(1, 1, 1, 0.35), false, 1.0)
	UI.ctext(g.hud, g.font, Vector2(lr.position.x, lr.end.y - 3.0), lvs, 10, V3_WHITE, HORIZONTAL_ALIGNMENT_CENTER, lw)
	var nx: float = L + 100.0
	var ln: String = ld.display_name()
	_hv.v2.txt(Vector2(nx, T + 46), ln, 28, V3_WHITE)
	_hv.v2.cap(Vector2(nx + _hv.v2.twidth(ln, 28) + 14, T + 44), str(ld.def.get("en", str(ld.id).to_upper())).to_upper() + "  ·  LEADER", 6.5, V3_GREY, 2.0)
	var meta: String = "%s  /  编队 %d/%d  /  %s  /  %s" % [str(ld.cls), g.squad.size(), g.squad.cap(), D.tier_name(g.tier), g.endg.cur_name()]
	_hv.v2.txt(Vector2(nx, T + 70), meta, 12, V3_GREY)
	var tags: Array = g.ch.display_tags()
	if not tags.is_empty():
		_hv.v2.txt(Vector2(nx, T + 90), "特性  " + " · ".join(tags), 12, Color(V3_GREY.r, V3_GREY.g, V3_GREY.b, 0.85))
	# 右：本局读数
	var dt: float = maxf(0.0, g.t - g.trial.started_at) if g.trial.active else g.t
	var rx: float = R - 4.0
	for it in [["源石锭", str(g.ingots)], ["藏品", str(g.relics.size())], ["击杀", str(g.kills)], ["时间", "%02d:%02d" % [int(dt) / 60, int(dt) % 60]]]:
		var vw: float = _hv.v2.big(Vector2(rx, T + 50), it[1], 22, V3_WHITE, 2)
		_hv.v2.txt(Vector2(rx - _hv.v2.twidth(it[0], 11), T + 68), it[0], 11, V3_GREY)
		rx -= maxf(vw, 40.0) + 32.0


func _v3_survival(x: float, top: float, w: float) -> void:
	_v3_head(x, top + 10, w, "生存", "SURVIVAL")
	var y: float = top + 44
	_hv.v3._lantern(Vector2(x + 13, y + 46), 1.0)
	var gx: float = x + 40
	var bw: float = x + w - gx
	_hv.v2.txt(Vector2(gx, y + 6), "生命", 13, V3_GREY)
	for q in g.shield_max:
		UI.diamond(g.hud, Vector2(gx + 36 + q * 10, y + 1), 3.5, Color(0.5, 0.85, 1.0) if q < g.shield else Color(1, 1, 1, 0.14), Color(0.6, 0.9, 1.0, 0.8))
	var low: bool = g.hp / g.max_hp < 0.3
	var sw: float = _hv.v2.big(Vector2(x + w, y + 8), "/ %d" % int(g.max_hp), 10, V3_GREY, 2)
	var kv: float = _ak(ANIM_GAP, 0.4)   # 入场：数字从 0 滚到当前数、细线从 0 长到当前值
	_hv.v2.big(Vector2(x + w - sw - 4, y + 8), "%d" % int(round(g.hp * kv)), 24, UI.RED if low else V3_WHITE, 2)
	_v3_hair(gx, y + 16, bw, g.hp / g.max_hp * kv, UI.RED if low else V3_WHITE)
	var li: Array = _hv.v2.lamp_item()
	var lc: Color = UI.GOLD if g.lamp >= 30.0 else UI.RED
	_hv.v2.txt(Vector2(gx, y + 42), "灯火", 13, V3_GREY)
	_hv.v2.txt(Vector2(gx + 36, y + 42), str(li[0]).replace("灯火", ""), 13, lc)
	_hv.v2.big(Vector2(x + w, y + 44), "%d" % int(round(g.lamp * kv)), 18, lc, 2)
	_v3_hair(gx, y + 52, bw, g.lamp / 100.0 * kv, lc, [0.3, 0.7])
	y += 86
	var rows0 := [
		["生命回复", regen_text()], ["物理减伤 / 法抗", armor_text()], ["闪避 物 / 法", "%d%% / %d%%" % [int(minf(g.dodge + g.dodge_phys, 0.6) * 100.0), int(minf(g.dodge + g.dodge_arts, 0.6) * 100.0)]],
		["移动速度", "%d" % int(g.speed)], ["拾取范围", "%d" % int(g.pickup)], ["受击灯火损失", "×%.2f" % g.lamp_decay],
		["照亮范围", "%d" % int(g.lamp_r())],
		["护盾", ("%d / %d · 每 %.1f 秒" % [g.shield, g.shield_max, g.shield_every]) if g.shield_max > 0 else "无"],
	]
	for row in rows0:
		_v3_row(x, y, w, row[0], row[1])
		y += 30


func _v3_offense(x: float, top: float, w: float, bottom: float) -> void:
	_v3_head(x, top + 10, w, "攻击", "OFFENSE")
	var y: float = top + 44
	var rows1: Array = g.ch.stats_rows()
	rows1.append_array([["近战 / 远程", "×%.2f / ×%.2f" % [g.melee_mult, g.ranged_mult]], ["物理 / 法术", "×%.2f / ×%.2f" % [g.phys_mult, g.arts_mult]]])
	rows1.append_array(rush_rows())
	for row in rows1:
		_v3_row(x, y, w, row[0], row[1])
		y += 28
	# 本局伤害构成：一根分段细条 + 前三名图例
	_hv.v2.txt(Vector2(x, y), "本局伤害构成", 14, V3_GREY)
	y += 12
	var total := 0.0
	for kk in g.dmg_out:
		total += g.dmg_out[kk]
	if total > 0.0:
		var ks: Array = g.dmg_out.keys()
		ks.sort_custom(func(a, b): return g.dmg_out[a] > g.dmg_out[b])
		var cols := [V3_WHITE, Color(0.75, 0.77, 0.8), Color(0.5, 0.54, 0.58)]
		var xx := x
		var lx := x
		for i in ks.size():
			var f: float = g.dmg_out[ks[i]] / total
			var col: Color = cols[i] if i < 3 else Color(0.28, 0.3, 0.33)
			g.hud.draw_rect(Rect2(xx, y, maxf(0.0, w * f - 1.0), 3), col)
			xx += w * f
			if i < 3:
				g.hud.draw_rect(Rect2(lx, y + 11, 6, 6), col)
				var lab: String = "%s %d%%" % [ks[i], int(round(f * 100.0))]
				_hv.v2.txt(Vector2(lx + 10, y + 18), lab, 11, Color(V3_WHITE.r, V3_WHITE.g, V3_WHITE.b, 0.85))
				lx += _hv.v2.twidth(lab, 11) + 24.0
		y += 34
	else:
		_hv.v2.txt(Vector2(x, y + 10), "—", 12, V3_GREY)
		y += 26
	_v3_head(x, y + 4, w, "技能", "SKILLS")
	y += 20
	g.result_screen.draw_generic_skill_rows(Rect2(x - 14, y, w + 28, bottom - y), y, skill_rows_data(), 11, 14, true)


func _v3_squad(x: float, top: float, w: float, bottom: float) -> void:
	_v3_head(x, top + 10, w, "编队", "SQUAD  %d / %d" % [g.squad.size(), g.squad.cap()])
	var y: float = top + 34
	var sq := 30.0
	var mouse2 := g.hud.get_local_mouse_position()
	for o in g.squad.ops:
		var hd: Array = _hv.ult.v._hi_head(o) if _hv.ult != null and _hv.ult.v != null else []
		g.hud.draw_rect(Rect2(x, y, sq, sq), Color(0, 0, 0, 0.5))
		if not hd.is_empty():
			g.hud.draw_texture_rect_region(hd[0], Rect2(x, y, sq, sq), hd[1])
		g.hud.draw_rect(Rect2(x, y, sq, sq), Color(1, 1, 1, 0.2), false, 1.0)
		var nm: String = o.display_name()
		_hv.v2.txt(Vector2(x + 40, y + 13), nm, 14, V3_WHITE)
		if o.is_leader:
			_hv.v2.cap(Vector2(x + 46 + _hv.v2.twidth(nm, 14), y + 12), "LEADER", 5.5, UI.CYAN, 1.4)
		_hv.v2.txt(Vector2(x + 40, y + 29), "%s · %s" % [o.cls, ["精零", "精一", "精二"][clampi(o.elite, 0, 2)]], 11, V3_GREY)
		# 成长进度：普通节点圆点、精英化菱形；选过的亮。整块是悬停区（弹出节点表）
		var pg: Array = o.prog_view()
		var dx0: float = x + w - pg.size() * 12.0 - 2.0
		var kd: float = _ak(ANIM_GAP * 3.0 + 0.04 * float(g.squad.ops.find(o)), 0.3)   # 入场：已选的点按顺序逐个亮
		for k in pg.size():
			var dc := Vector2(dx0 + k * 12.0 + 4.0, y + 9)
			var done: bool = k < o.prog and float(k) < kd * float(maxi(1, o.prog))
			var cc: Color = V3_WHITE if done else Color(1, 1, 1, 0.25)
			if str(pg[k].get("type", "")) == "elite":
				UI.diamond(g.hud, dc, 4.0, cc if done else Color(0, 0, 0, 0), cc)
			else:
				g.hud.draw_circle(dc, 2.6, cc)
		var pr := Rect2(dx0 - 4.0, y, pg.size() * 12.0 + 8.0, 18.0)
		g.stats_cells.append([pr, "prog", o])
		if pr.has_point(mouse2):
			g.hud.draw_rect(pr, Color(1, 1, 1, 0.5), false, 1.0)
		var nn: Dictionary = o.next_node()
		var nxt: String = ("下一步 " + str(nn.get("name", ""))) if not nn.is_empty() else "已满"
		_hv.v2.txt(Vector2(x + w - _hv.v2.twidth(nxt, 11), y + 29), nxt, 11, Color(V3_WHITE.r, V3_WHITE.g, V3_WHITE.b, 0.7) if not nn.is_empty() else UI.GOLD)
		y += sq + 12.0
	g.hud.draw_rect(Rect2(x, y, w, 1), Color(1, 1, 1, 0.1))
	y += 12
	# 小队指令牌（同指挥台）
	var tile := 32.0
	_hv.v3._cmd_block(x, y + tile + 2.0, tile, _hv.v3._rush_text(), _hv.v2.seg_index(), 1.3)
	y += tile + 34.0
	if not g.weapons.is_empty():
		_hv.v2.txt(Vector2(x, y), "支援", 13, V3_GREY)
		var ax: float = x + 48
		for wid in g.weapons:
			var ws: String = "%s Lv.%d" % [D.WEAPONS[wid].name, g.weapons[wid]]
			_hv.v2.txt(Vector2(ax, y), ws, 12, V3_WHITE)
			ax += _hv.v2.twidth(ws, 12) + 18
		y += 24
	var fm: Array = LinkBond.formed_now(g)
	if not fm.is_empty():
		_hv.v2.txt(Vector2(x, y), "羁绊", 13, V3_GREY)
		for b in fm:
			UI.diamond(g.hud, Vector2(x + 50, y - 4), 3.5, UI.GOLD)
			UI.text_fit(g.hud, g.font, Vector2(x + 60, y), LinkBond.row_text(b), 12, Color(V3_WHITE.r, V3_WHITE.g, V3_WHITE.b, 0.85), w - 60, 10)
			y += 20
		y += 6
	# 成长 + 藏品：图标格（悬停看效果）
	var cs := 30.0
	var pitch := 35.0
	var per: int = maxi(1, int(w / pitch))
	if not g.growth.is_empty():
		_hv.v2.txt(Vector2(x, y + 4), "成长", 13, V3_GREY)
		y += 12
		var gi := 0
		for gid in g.growth:
			var gc := Vector2(x + (gi % per) * pitch, y + (gi / per) * pitch)
			if gc.y + cs > bottom:
				break
			g.hud.draw_rect(Rect2(gc, Vector2(cs, cs)), Color(0, 0, 0, 0.4))
			g.hud.draw_rect(Rect2(gc, Vector2(cs, cs)), Color(1, 1, 1, 0.16), false, 1.0)
			var gt: Texture2D = g.tex.get("growth_" + gid)
			if gt != null:
				g.hud.draw_texture_rect(gt, Rect2(gc + Vector2(3, 3), Vector2(cs - 6, cs - 6)), false)
			UI.text(g.hud, g.font, gc + Vector2(cs - 18, cs - 1), "×%d" % g.growth[gid], 10, V3_WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 18, 2)
			g.stats_cells.append([Rect2(gc, Vector2(cs, cs)), "growth", gid])
			gi += 1
		y += maxi(1, int(ceil(g.growth.size() / float(per)))) * pitch + 4
	_hv.v2.txt(Vector2(x, y + 4), "藏品", 13, V3_GREY)
	_hv.v2.big(Vector2(x + 34, y + 5), str(g.relics.size()), 13, V3_WHITE)
	var hint: String = "点图标查看效果" if Pad.touch_ui() else "悬停看效果"
	_hv.v2.txt(Vector2(x + w - _hv.v2.twidth(hint, 11), y + 4), hint, 11, V3_GREY)
	y += 12
	var nr: int = g.relics.size()
	var skip: int = _relic_skip(nr, per, pitch, cs, y, bottom)
	var slot := 0
	if skip > 0:
		_draw_more_cell(Vector2(x, y), cs, skip, 12)
		slot = 1
	for i in range(skip, nr):
		var rc := Vector2(x + (slot % per) * pitch, y + (slot / per) * pitch)
		slot += 1
		if rc.y + cs > bottom:
			break
		var rd: Dictionary = g.RL[g.relics[i]]
		var cr := Rect2(rc, Vector2(cs, cs))
		var hov: bool = cr.has_point(mouse2)
		g.hud.draw_rect(cr, Color(0, 0, 0, 0.4) if not hov else Color(1, 1, 1, 0.12))
		g.hud.draw_rect(cr, Color(1, 1, 1, 0.16) if not hov else V3_WHITE, false, 1.0)
		var rt: Texture2D = g.tex.get("relic_" + g.relics[i])
		if rt != null:
			g.hud.draw_texture_rect(rt, Rect2(rc + Vector2(3, 3), Vector2(cs - 6, cs - 6)), false)
		else:
			UI.text(g.hud, g.font, rc + Vector2(0, cs * 0.68), rd.name.substr(0, 1), int(cs * 0.42), V3_WHITE, HORIZONTAL_ALIGNMENT_CENTER, cs)
		var rl: int = g.rfx.lv.get(g.relics[i], 1)
		if rl > 1:
			UI.text(g.hud, g.font, rc + Vector2(cs - 18, cs - 1), "L%d" % rl, 10, UI.GOLD, HORIZONTAL_ALIGNMENT_RIGHT, 18, 2)
		g.stats_cells.append([cr, "relic", g.relics[i]])


## 悬停提示：藏品 / 成长 / 技能沿用原来的提示框；成长进度点弹出节点表
func _v3_tips(vs: Vector2) -> void:
	var mouse2 := g.hud.get_local_mouse_position()
	for cellinfo in g.stats_cells:
		var cr2: Rect2 = cellinfo[0]
		if cellinfo[1] == "prog" and cr2.has_point(mouse2):
			_v3_prog_pop(vs, cr2, cellinfo[2])
			return
	_draw_footer_tips(vs)


func _v3_prog_pop(vs: Vector2, at: Rect2, o) -> void:
	var pg: Array = o.prog_view()
	var w := 230.0
	var h: float = 40.0 + pg.size() * 20.0
	var p := Vector2(clampf(at.end.x - w, 8.0, vs.x - w - 8.0), at.end.y + 8.0)
	if p.y + h > vs.y - 8.0:
		p.y = at.position.y - h - 8.0
	g.hud.draw_rect(Rect2(p, Vector2(w, h)), Color(0.03, 0.04, 0.05, 0.97))
	g.hud.draw_rect(Rect2(p, Vector2(w, h)), Color(1, 1, 1, 0.35), false, 1.0)
	_hv.v2.txt(p + Vector2(12, 20), "%s · 成长" % o.display_name(), 13, V3_WHITE)
	_hv.v2.cap(p + Vector2(w - 12, 19), "%d / %d" % [mini(o.prog, pg.size()), pg.size()], 6.0, V3_GREY, 1.4, 2)
	for k in pg.size():
		var n: Dictionary = pg[k]
		var yy: float = p.y + 42.0 + k * 20.0
		var done: bool = k < o.prog
		var cc: Color = V3_WHITE if done else Color(1, 1, 1, 0.35)
		var dc := Vector2(p.x + 16, yy - 5)
		if str(n.get("type", "")) == "elite":
			UI.diamond(g.hud, dc, 4.0, cc if done else Color(0, 0, 0, 0), cc)
		else:
			g.hud.draw_circle(dc, 2.6, cc)
		_hv.v2.txt(Vector2(p.x + 28, yy), str(n.get("name", "")), 12, V3_WHITE if done else Color(1, 1, 1, 0.6))
		var st: String = "已选" if done else ("下一步" if k == o.prog else "")
		if st != "":
			_hv.v2.txt(Vector2(p.x + w - 12 - _hv.v2.twidth(st, 11), yy), st, 11, UI.CYAN if st == "下一步" else V3_GREY)
