extends "res://scripts/screens/settle/settle_base.gd"
## 方向 A「作战报告」：海报式（docs/125 §4.4 S1 / S2 / S5）。巨型描边英文结果横贯上缘，左侧暗斜板放队长立绘，
## 右侧是数据格 + 编队输出条，下缘一条「本局获得」。层级：结果 + 评级 ≫ 队长 ≫ 数据。
## 动效：斜板扫入 → 巨型英文从右侧带速度线滑入 → 中文结果块展开 → 队长剪影显色 → 数据格右滑入 + 计数 → 输出条拉长 → 评级描边落定 → 奖励逐个落下。
## 失败：英文从左慢慢拖入、主题色降饱和；队长保持去色并盖洋红「击倒」；数据格下沉落位，不弹。
## 配色跟随本局队长（10-28 用户定）：主色 / 描边 / 斜板 / 输出条高亮取队长干员 col（data/characters/*.json，选人 / 图鉴同一张）。


func end_win() -> float:
	return 3.2


func end_loss() -> float:
	return 3.9


func buttons() -> Array:
	return footer(664.0, 42.0)


func theme() -> Color:
	var r := leader_row()
	return lead_theme(r.get("col", HH.CYB) if not r.is_empty() else HH.CYB, won)


func draw(canvas: CanvasItem) -> void:
	begin(canvas)
	var acc := theme()
	ci.draw_rect(Rect2(-400, -400, 2080, 1520), HH.DARK)
	# 速度线（斜向细条，入场时快速掠过，之后很淡）
	var sp := ek(0.1, 0.6)
	for i in 9:
		var y := 30.0 + i * 23.0
		var len := 200.0 + float((i * 137) % 260)
		var x := lerpf(1400.0, 120.0 + float((i * 211) % 700), sp) if won else lerpf(-600.0, 80.0 + float((i * 211) % 700), sp)
		fa = 0.10 + 0.25 * (1.0 - sp)
		rect(Rect2(x, y, len, 2), acc)
	fa = 1.0
	# ① 左侧暗斜板扫入
	var wp := ek(0.0, 0.4)
	if wp > 0.0:
		poly(PackedVector2Array([Vector2(0, 236), Vector2(470 * wp, 236), Vector2(410 * wp, 640), Vector2(0, 640)]), HH.DARK2.lerp(acc, 0.1))
		poly(PackedVector2Array([Vector2(470 * wp, 236), Vector2(470 * wp + 8, 236), Vector2(410 * wp + 8, 640), Vector2(410 * wp, 640)]), acc)
	# ② 巨型英文结果
	var word := "COMPLETE" if won else "FAILED"
	fa = ek(0.1, 0.25)
	px(Vector2(40, 26), "OPERATION REPORT  //  RHODES ISLAND", 2.0, HH.MUTE, 0, 2)
	var ex := lerpf(420.0, 0.0, sp) if won else lerpf(-260.0, 0.0, ek(0.1, 0.9))
	px_line(Vector2(36 + ex, 94), word, 13.0, acc, HH.DARK)
	fa = 1.0
	# ③ 中文结果块（实色块里黑字）
	var bp := ek(0.45, 0.25)
	if bp > 0.0:
		para(Rect2(40, 150, 300 * bp, 62), acc.lerp(HH.LIGHT, 0.6))
		fa = k(0.55, 0.2)
		txt(64, 156, "探索完成" if won else "探索终止", 40, HH.INK)
		txt(358, 158, sub_line(), 16, HH.LIGHT, 0, 360)
		txt(358, 186, "探索用时 %s  ·  %s" % [mmss(float(m().t)), diff_name()], 14, HH.MUTE)
		fa = 1.0
	# ④ 评级：右上，描边字放大落定（失败直接淡入）
	_grade(acc)
	# ⑤ 队长立绘：剪影 → 显色（失败保持去色 + 击倒章）
	_leader(acc)
	# ⑥ 数据格
	_cells(acc)
	# ⑦ 编队输出
	_squad(acc)
	# ⑧ 本局获得
	_gains(acc)
	# ⑨ 底栏
	fa = ek(2.8, 0.35)
	rect(Rect2(-400, 652, 2080, 500), HH.INK)
	s._draw_buttons(ci, fa)
	fa = 1.0


func _grade(acc: Color) -> void:
	var g := grade()
	var kk: float = [20.0, 15.0, 11.0][clampi(g.length() - 1, 0, 2)]
	var p := k(1.9, 0.22)
	fa = ek(1.75, 0.2)
	px(Vector2(1150, 22), "RATING", 2.0, HH.MUTE, 1, 2)
	if p <= 0.0 and won:
		return
	var sc := lerpf(1.5, 1.0, UM.out_cubic(p)) if won else 1.0
	fa = minf(1.0, p * 3.0) if won else ek(1.9, 0.6)
	var c := Vector2(1150, 124)
	xf(c, 0.0, Vector2.ONE * sc)
	px_line(c, g, kk, acc, HH.LIGHT if won else HH.DARK3, 1)
	reset_xf()
	fa = 1.0


func _leader(acc: Color) -> void:
	var r := leader_row()
	if r.is_empty():
		return
	var p := ek(0.6, 0.6)
	fa = ek(0.5, 0.2)
	px(Vector2(40, 254), "LEADER", 2.0, HH.MUTE, 0, 2)
	# 背后一枚淡色大英文名（压在立绘后面）
	fa *= 0.5
	var en := str(r.en)
	if px_w(en, 6.0) > 400.0:   # 长英文名（SKADI THE CORRUPTING HEART）只留首词，不压到数据格上
		en = en.get_slice(" ", 0)
	px(Vector2(40, 300), en, 6.0, Color(r.col, 0.22))
	fa = ek(0.5, 0.2)
	var col: Color
	if won:
		col = Color(0, 0, 0).lerp(Color.WHITE, p)
	else:
		col = Color(0.08, 0.08, 0.1).lerp(Color(0.52, 0.52, 0.58), p)
	art(str(r.key), Rect2(40, 262, 340, 320), col)
	# 名牌
	var np := ek(0.9, 0.3)
	if np > 0.0:
		fa = np
		para(Rect2(28, 592, 290 * np, 40), HH.LIGHT)
		rect(Rect2(28, 632, 290 * np, 3), acc)
		txt(50, 598, str(r.name), 22, HH.INK)
		txt(50 + tw(str(r.name), 22) + 12, 604, "队长  Lv.%d" % int(m().get("level", 1)), 13, HH.INK2)
	if not won:
		var q := k(1.4, 0.35)
		if q > 0.0:
			fa = minf(1.0, q * 2.0)
			var sc := lerpf(1.6, 1.0, UM.out_cubic(q))
			var c := Vector2(300, 300)
			xf(c, -0.12, Vector2.ONE * sc)
			rect(Rect2(c - Vector2(62, 24), Vector2(124, 48)), MAG, false, 3.0)
			txt(c.x, c.y - 20, "击倒", 32, MAG, 1)
			reset_xf()
	fa = 1.0


func _cells(acc: Color) -> void:
	fa = ek(0.85, 0.2)
	txt(500, 236, "|  02 / 作战数据", 14, HH.MUTE)
	var best: Dictionary = m().get("best", {})
	var cells: Array = [
		["总伤害", float(m().total), "每秒 %s" % num(float(m().get("dps", 0.0)))],
		["击败敌人", float(m().kills), "精英 %d" % int(m().get("elites", 0))],
		["最高单次", float(best.get("v", 0.0)), str(best.get("src", ""))],
		["Boss 击破", float(boss_kills()), ""],
		["受到伤害", float(m().get("leader", {}).get("taken", 0.0)), ""],
		["生命回复", float(m().get("leader", {}).get("heal", 0.0)), ""]]
	for i in cells.size():
		var c: Array = cells[i]
		var x := 500.0 + (i % 3) * 248.0
		var y := 264.0 + (i / 3) * 72.0
		var p := k(0.95 + 0.07 * i, 0.4)
		if p <= 0.0:
			continue
		var e := UM.out_cubic(p)
		var dx := 60.0 * (1.0 - e) if won else 0.0
		var dy := 0.0 if won else -18.0 * (1.0 - e)
		fa = e
		rect(Rect2(x + dx, y + dy, 3, 56), acc if i < 3 else HH.DARK3)
		txt(x + 14 + dx, y + dy, str(c[0]), 13, HH.MUTE)
		var cnt := ek(1.0 + 0.07 * i, 0.8)
		txt(x + 14 + dx, y + 16 + dy, num(float(c[1]) * cnt), 28, HH.LIGHT)
		txt(x + 14 + dx, y + 52 + dy, str(c[2]), 11, HH.MUTE, 0, 220)
	fa = 1.0


func _squad(acc: Color) -> void:
	var rows: Array = s.rows
	fa = ek(1.4, 0.2)
	txt(500, 412, "|  03 / 编队输出", 14, HH.MUTE)
	txt(1240, 414, "%d 名" % rows.size(), 12, HH.MUTE, 2)
	var n := maxi(1, rows.size())
	var h := minf(28.0, 124.0 / n)
	for i in rows.size():
		var r: Dictionary = rows[i]
		var y := 438.0 + i * h
		var p := ek(1.5 + 0.08 * i, 0.5)
		fa = minf(1.0, p * 2.0)
		if r.leader:
			rect(Rect2(496, y + 1, 748 * p, h - 2), Color(acc, 0.13))
		rect(Rect2(500, y + h * 0.5 - 5, 4, 10), r.col)
		txt(512, y + h * 0.5 - 10, str(r.name), mini(15, int(h * 0.6)), HH.LIGHT if r.leader else HH.LIGHT2, 0, 100)
		rect(Rect2(620, y + h * 0.5 - 3, 560, 6), HH.DARK3)
		rect(Rect2(620, y + h * 0.5 - 3, 560 * float(r.share) * p, 6), r.col)
		txt(1240, y + h * 0.5 - 10, "%d%%" % int(round(float(r.pct) * p)), mini(15, int(h * 0.6)), HH.LIGHT, 2)
	fa = 1.0


func _gains(acc: Color) -> void:
	var p0 := ek(2.2, 0.25)
	fa = p0
	rect(Rect2(470, 574, 790, 66), Color(HH.DARK2, 0.9))
	txt(486, 580, "本局获得", 12, HH.MUTE)
	var items: Array = [["生机细胞", "+%d" % s.cells, HH.LIGHT], ["寻访凭证", "×%d" % s.vouchers, HH.CYB]]
	for i in items.size():
		var q := k(2.3 + 0.08 * i, 0.4)
		if q <= 0.0:
			continue
		fa = minf(1.0, q * 2.0)
		var dy := -26.0 * (1.0 - UM.out_back(q, 1.6)) if won else -12.0 * (1.0 - UM.out_cubic(q))
		txt(596 + i * 130, 580 + dy, str(items[i][0]), 12, HH.MUTE)
		txt(596 + i * 130, 598 + dy, str(items[i][1]), 26, items[i][2])
	if bool(s.g.roster_new.get("short", false)):
		fa = p0
		txt(486, 624, "探索不足 %d 分钟，不发放凭证" % int(Roster.RUN_MIN_T / 60.0), 11, HH.MUTE)
	var rel := key_relics(7)
	for i in rel.size():
		var q := k(2.45 + 0.06 * i, 0.4)
		if q <= 0.0:
			continue
		fa = minf(1.0, q * 2.5)
		var dy := -30.0 * (1.0 - UM.out_back(q, 1.6)) if won else -10.0 * (1.0 - UM.out_cubic(q))
		var r := Rect2(870 + i * 50, 584 + dy, 46, 46)
		rect(r, HH.DARK3)
		var tx: Texture2D = relic_tex(str(rel[i].id))
		if tx != null:
			ci.draw_texture_rect(tx, r.grow(-4), false, Color(1, 1, 1, fa))
		var rc: Color = MAG if str(rel[i].rarity) == "遭诅古物" else (Color8(170, 120, 255) if str(rel[i].rarity) == "升华" else Color(0, 0, 0, 0))
		if rc.a > 0.0:
			rect(Rect2(r.end.x - 8, r.position.y, 8, 8), rc)
	fa = 1.0
