extends "res://scripts/screens/settle/settle_base.gd"
## 方向 C「编队合影」：以编队为主体（接选人 / 图鉴的卡片语言）。全宽一排干员卡，输出最高的一张更宽、抬高、标「最高输出」；
## 每张卡：立绘（夹在像框里）、名字、伤害占比大字、占比条、伤害 / 参与击杀 / 技能。上缘一条结果栏，下缘总数 + 获得。
## 层级：每名干员打了多少 ≫ 结果 ≫ 总数。
## 动效：卡背整排升起 → 从左到右逐张翻面（错开 0.16 秒）→ 最高输出最后翻、抬高并扫过一道光 → 占比计数。
## 失败：卡背自上方歪斜落下再摆正，翻得慢；队长卡去色并挂「击倒」条，不扫光。

const Y0 := 172.0
const H := 376.0
const GAP := 14.0
const MVP_W := 1.32


func end_win() -> float:
	return 3.3


func end_loss() -> float:
	return 3.9


func buttons() -> Array:
	return footer(664.0, 42.0)


## 每张卡的 [x, 宽, 是否最高输出]
func _layout() -> Array:
	var rows: Array = s.rows
	var n := rows.size()
	if n == 0:
		return []
	var mvp := mvp_row()
	var unit := (1224.0 - GAP * (n - 1)) / (n - 1 + MVP_W)
	unit = minf(unit, 200.0)
	var total := unit * (n - 1 + MVP_W) + GAP * (n - 1)
	var x := 28.0 + (1224.0 - total) * 0.5
	var out: Array = []
	for r in rows:
		var is_m: bool = r.key == mvp.key
		var w := unit * (MVP_W if is_m else 1.0)
		out.append([x, w, is_m])
		x += w + GAP
	return out


func _flip_t(i: int, n: int, is_m: bool) -> float:
	return (0.85 + 0.16 * n + 0.2) if is_m else (0.85 + 0.16 * i)


func draw(canvas: CanvasItem) -> void:
	begin(canvas)
	var acc: Color = HH.CYB if won else MAG
	ci.draw_rect(Rect2(-400, -400, 2080, 1520), HH.DARK)
	HH.backdrop(ci, Vector2(1280, 720))
	_header(acc)
	var lay := _layout()
	var rows: Array = s.rows
	for i in rows.size():
		_card(i, rows[i], lay[i], rows.size(), acc)
	_totals(acc)
	fa = ek(3.0, 0.3)
	rect(Rect2(-400, 652, 2080, 500), HH.INK)
	s._draw_buttons(ci, fa)
	fa = 1.0


func _header(acc: Color) -> void:
	fa = 1.0
	var bp := ek(0.0, 0.35)
	rect(Rect2(0, 0, 1280 * bp, 40), HH.INK)
	fa = ek(0.1, 0.3)
	txt(28, 10, "|  01 / 作战结算", 15, HH.LIGHT)
	px(Vector2(1252, 20), "RHODES ISLAND  //  SQUAD RECORD", 2.0, HH.MUTE, 2, 2)
	# 结果
	var rp := ek(0.2, 0.35)
	fa = rp
	var dx := -20.0 * (1.0 - rp)
	rect(Rect2(28 + dx, 62, 5, 70), acc)
	txt(46 + dx, 56, "探索完成" if won else "探索终止", 44, HH.LIGHT)
	px(Vector2(48 + dx, 124), "OPERATION COMPLETE" if won else "OPERATION FAILED", 2.0, acc, 0, 2)
	# 用时 / 难度 / 结局或击倒者
	var info: Array = [["探索用时", mmss(float(m().t))], ["难度档", diff_name()], ["结局" if won else "击倒者", sub_line()]]
	var x := 330.0
	for i in info.size():
		fa = ek(0.35 + 0.08 * i, 0.3)
		rect(Rect2(x, 66, 1, 58), HH.DARK3)
		txt(x + 14, 66, str(info[i][0]), 12, HH.MUTE)
		txt(x + 14, 88, str(info[i][1]), 20 if i < 2 else 16, HH.LIGHT, 0, 330 if i == 2 else -1.0)
		x += 160.0 if i < 1 else 190.0
	# 评级
	var g := grade()
	var q := k(2.75, 0.22)
	fa = ek(0.5, 0.3)
	para(Rect2(1090, 56, 162, 80), Color(0, 0, 0, 0), HH.DARK3, 1.5)
	txt(1112, 60, "评级", 12, HH.MUTE)
	if q > 0.0:
		var kk: float = [8.0, 6.5, 5.0][clampi(g.length() - 1, 0, 2)]
		var sc := lerpf(1.6, 1.0, UM.out_cubic(q)) if won else 1.0
		fa = minf(1.0, q * 3.0) if won else ek(2.75, 0.6)
		var c := Vector2(1178, 100)
		xf(c, 0.0, Vector2.ONE * sc)
		px(c, g, kk, HH.LIGHT if won else MAG, 1)
		reset_xf()
	fa = 1.0


func _card(i: int, r: Dictionary, l: Array, n: int, acc: Color) -> void:
	var x: float = l[0]
	var w: float = l[1]
	var is_m: bool = l[2]
	var lift := 0.0
	# 卡背升起 / 落下
	var ap := k(0.3 + 0.05 * i, 0.45)
	if ap <= 0.0:
		return
	var ae := UM.out_cubic(ap)
	var ft := _flip_t(i, n, is_m)
	var fd := 0.26
	var fp := k(ft, fd)   # 翻面进度
	if is_m:
		lift = -14.0 * ek(ft + fd, 0.3)
	var y := Y0 + (0.0 if is_m else 22.0) + lift
	var h := H - (0.0 if is_m else 22.0)
	var c := Vector2(x + w * 0.5, y + h * 0.5)
	var rot := 0.0
	var off := Vector2(0, 60.0 * (1.0 - ae)) if won else Vector2(0, -90.0 * (1.0 - ae))
	if not won:
		rot = (0.1 if i % 2 == 0 else -0.08) * (1.0 - UM.out_back(ap, 1.6))
	var sx := absf(cos(fp * PI))
	fa = minf(1.0, ap * 2.0)
	xf(c, rot, Vector2(maxf(0.02, sx), 1.0), off)
	var face := fp >= 0.5
	if not face:
		_back(Rect2(x, y, w, h), r)
	else:
		_front(Rect2(x, y, w, h), r, is_m, ft + fd, acc)
	reset_xf()
	fa = 1.0


func _back(rc: Rect2, r: Dictionary) -> void:
	rect(rc, HH.DARK2)
	rect(rc, Color(1, 1, 1, 0.12), false, 1.0)
	rect(Rect2(rc.position.x, rc.position.y, rc.size.x, 6), Color(r.col, 0.5))
	# 中间罗德岛菱形与竖排英文
	var c := rc.get_center()
	poly(PackedVector2Array([c + Vector2(0, -26), c + Vector2(22, 0), c + Vector2(0, 26), c + Vector2(-22, 0)]), HH.DARK3)
	px(c + Vector2(0, 50), "R.I.", 2.0, HH.MUTE, 1, 2)


func _front(rc: Rect2, r: Dictionary, is_m: bool, t_done: float, acc: Color) -> void:
	var x := rc.position.x
	var y := rc.position.y
	var w := rc.size.x
	var h := rc.size.y
	var down: bool = (not won) and r.leader
	rect(rc, HH.LIGHT if is_m and won else HH.DARK2)
	var ink: Color = HH.INK if is_m and won else HH.LIGHT
	var mute: Color = HH.INK2 if is_m and won else HH.MUTE
	rect(Rect2(x, y, w, 6), r.col)
	# 切角
	poly(PackedVector2Array([Vector2(rc.end.x - 18, rc.end.y), Vector2(rc.end.x, rc.end.y - 18), Vector2(rc.end.x, rc.end.y)]), HH.DARK)
	# 竖排淡英文 + 立绘（夹在像框里）
	var en := str(r.en)
	var kk := 3.0
	for j in mini(en.length(), 9):
		px(Vector2(x + 14, y + 26 + j * 24), en[j], kk, Color(r.col, 0.2))
	var pb := Rect2(x + 8, y + 14, w - 16, h * 0.46)
	art(str(r.key), pb, Color(0.5, 0.5, 0.55) if down else Color.WHITE)
	var ny := y + h * 0.46 + 18
	txt(x + 12, ny, str(r.name), 20, ink, 0, w - 24)
	var tag := "队长" if r.leader else ("已离队" if float(r.left_t) >= 0.0 else "")
	if is_m:
		tag = "最高输出" + ("  ·  队长" if r.leader else "")
	txt(x + 12, ny + 28, tag, 12, HH.CYB if not (is_m and won) else HH.RIB)
	# 占比大字（翻面后计数）
	var cnt := ek(t_done, 0.6)
	var pk := 5.0 if is_m else 4.0
	px(Vector2(x + 12, ny + 62), "%d%%" % int(round(float(r.pct) * cnt)), pk, ink)
	rect(Rect2(x + 12, ny + 84, w - 24, 5), HH.DARK3 if not (is_m and won) else HH.LIGHT2)
	rect(Rect2(x + 12, ny + 84, (w - 24) * float(r.share) * cnt, 5), r.col)
	var lines: Array = [["伤害", num(float(r.dmg))], ["参与击杀", str(int(r.kills))], ["技能", str(int(r.casts))]]
	for j in lines.size():
		var ly := ny + 96 + j * 21
		if ly + 20 > rc.end.y - 4:
			break
		txt(x + 12, ly, str(lines[j][0]), 12, mute)
		txt(rc.end.x - 14, ly - 2, str(lines[j][1]), 15, ink, 2)
	if down:
		rect(Rect2(x, y + h * 0.36, w, 30), Color(MAG, 0.88))
		txt(x + w * 0.5, y + h * 0.36 + 4, "击倒", 18, HH.LIGHT, 1)
	# 最高输出：翻好后扫过一道斜光
	if is_m and won:
		var sp := k(t_done + 0.05, 0.45)
		if sp > 0.0 and sp < 1.0:
			var sx := lerpf(x - 80, x + w + 40, sp)
			var keep := fa
			fa = 0.55 * sin(sp * PI)
			poly(PackedVector2Array([Vector2(sx + 40, y), Vector2(sx + 80, y), Vector2(sx + 40, y + h), Vector2(sx, y + h)]), Color.WHITE)
			fa = keep


func _totals(acc: Color) -> void:
	var p := ek(2.5, 0.35)
	fa = p
	rect(Rect2(28, 574, 1224, 1), HH.DARK3)
	var items: Array = [["总伤害", num(float(m().total) * p), HH.LIGHT], ["击败敌人", num(float(m().kills) * p), HH.LIGHT],
		["Boss 击破", str(boss_kills()), HH.LIGHT], ["藏品", str(int(m().get("relics", 0))), HH.LIGHT],
		["生机细胞", "+%d" % int(s.cells * p), HH.LIGHT], ["寻访凭证", "×%d" % int(s.vouchers * p), HH.CYB]]
	for i in items.size():
		var x := 28.0 + i * 170.0 + (120.0 if i >= 4 else 0.0)
		fa = ek(2.5 + 0.05 * i, 0.3)
		txt(x, 586, str(items[i][0]), 12, HH.MUTE)
		txt(x, 604, str(items[i][1]), 24, items[i][2])
	fa = 1.0
