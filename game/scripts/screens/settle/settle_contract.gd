extends "res://scripts/screens/settle/settle_base.gd"
## 方向「合约结算」（10-28 用户「设计能不能学习一下危机合约的结算界面」）：借原作危机合约结算的版式语言——
## 暗灰底 + 一道斜向浅光、左栏「徽记 → 作战名 → 三角数字章 + 两行标签 → 细分隔线 → 方格图标阵」、正中一张大立绘压在两栏之间、
## 右侧一面斜排的编队卡格（空位写 NO INFO/ 并画十字准星）。整体只用白 / 灰 + 一种强调色（取本局队长代表色，settle_base.lead_theme）。
## 层级：结果 + 评级章 ≫ 队长立绘 ≫ 编队卡 ≫ 获得 / 数据。
## 动效：斜光从右扫入 → 左栏逐行从左滑入 → 立绘由剪影显色并左移落位 → 卡格逐格落下、有人的卡闪白显出立绘 → 评级章放大落定 → 获得方格依次落下。
## 失败：同色降饱和、整体放慢；队长立绘去色盖「击倒」，队长卡挂洋红条。

const OTHER := "_other"
const COLS := 4
const ROWS := 3
const CW := 118.0
const CH := 150.0
const GAP := 10.0
const GX := 742.0
const GY := 66.0
const TILT := 26.0      # 每往下一行左移（仿原作卡格的斜排）


func end_win() -> float:
	return 2.9


func end_loss() -> float:
	return 3.5


func buttons() -> Array:
	return footer(664.0, 42.0)


func draw(canvas: CanvasItem) -> void:
	begin(canvas)
	var r := leader_row()
	var acc := lead_theme(r.get("col", HH.CYB) if not r.is_empty() else HH.CYB, won)
	ci.draw_rect(Rect2(-400, -400, 2080, 1520), HH.DARK)
	# 斜向浅光（原作是虚化的场景照片，这里用两道半透明斜面）
	var sp := ek(0.0, 0.45)
	var ox := 700.0 * (1.0 - sp)
	fa = 1.0
	poly(PackedVector2Array([Vector2(560 + ox, 0), Vector2(1280 + ox, 0), Vector2(1280 + ox, 652), Vector2(400 + ox, 652)]), Color(1, 1, 1, 0.035))
	poly(PackedVector2Array([Vector2(820 + ox, 0), Vector2(900 + ox, 0), Vector2(700 + ox, 652), Vector2(620 + ox, 652)]), Color(1, 1, 1, 0.03))
	_grid(acc)
	_leader(r, acc)
	_left(acc)
	fa = ek(2.2, 0.3)
	rect(Rect2(-400, 652, 2080, 500), HH.INK)
	s._draw_buttons(ci, fa)
	fa = 1.0


func _slide(i: int) -> float:
	var p := ek(0.1 + 0.06 * i, 0.35)
	fa = p
	return -30.0 * (1.0 - p)


# ---------------------------------------------------------------- 左栏
func _left(acc: Color) -> void:
	# 徽记：两层菱形 + 竖线（罗德岛式的简化标记）
	var dx := _slide(0)
	var c := Vector2(70 + dx, 64)
	poly(PackedVector2Array([c + Vector2(0, -30), c + Vector2(30, 0), c + Vector2(0, 30), c + Vector2(-30, 0)]), HH.LIGHT)
	poly(PackedVector2Array([c + Vector2(0, -21), c + Vector2(21, 0), c + Vector2(0, 21), c + Vector2(-21, 0)]), HH.DARK)
	poly(PackedVector2Array([c + Vector2(0, -12), c + Vector2(12, 0), c + Vector2(0, 12), c + Vector2(-12, 0)]), acc)
	px(Vector2(112 + dx, 52), "RHODES ISLAND", 1.5, HH.MUTE, 0, 2)
	px(Vector2(112 + dx, 72), "OPERATION REPORT", 1.5, HH.MUTE, 0, 2)
	# 作战名：结果 + 结局 / 击倒者 + 用时难度
	dx = _slide(1)
	txt(40 + dx, 108, "探索完成" if won else "探索终止", 34, HH.LIGHT)
	px(Vector2(44 + dx, 160), "OPERATION COMPLETE" if won else "OPERATION FAILED", 1.5, acc, 0, 2)
	dx = _slide(2)
	txt(40 + dx, 174, sub_line(), 15, HH.LIGHT2, 0, 360)
	txt(40 + dx, 196, "探索用时 %s  ·  %s" % [mmss(float(m().t)), diff_name()], 13, HH.MUTE, 0, 360)
	# 三角数字章：评级（放大落定）+ 两行标签；右边一项 Boss 击破
	dx = _slide(3)
	var q := k(1.2, 0.25)
	var tc := Vector2(84 + dx, 262)
	var sc := lerpf(1.45, 1.0, UM.out_cubic(q)) if won else 1.0
	if q > 0.0 or not won:
		var keep := fa
		fa = minf(keep, q * 3.0) if won else keep * ek(1.2, 0.5)
		xf(tc, 0.0, Vector2.ONE * sc)
		poly(PackedVector2Array([tc + Vector2(0, -44), tc + Vector2(46, 34), tc + Vector2(-46, 34)]), acc)
		poly(PackedVector2Array([tc + Vector2(0, -32), tc + Vector2(35, 27), tc + Vector2(-35, 27)]), HH.DARK)
		var g := grade()
		px(tc + Vector2(0, 10), g, [5.0, 4.0, 3.0][clampi(g.length() - 1, 0, 2)], HH.LIGHT, 1)
		reset_xf()
		fa = keep
	txt(146 + dx, 236, "作战评级", 18, HH.LIGHT)
	px(Vector2(148 + dx, 272), "OPERATION RATING", 1.5, HH.MUTE, 0, 2)
	rect(Rect2(292 + dx, 236, 1, 50), Color(1, 1, 1, 0.2))
	txt(306 + dx, 236, "Boss 击破", 12, HH.MUTE)
	txt(306 + dx, 252, str(boss_kills()), 28, HH.LIGHT)
	# 分隔线 + 本局获得方格
	dx = _slide(4)
	rect(Rect2(40 + dx, 306, 380, 1), Color(1, 1, 1, 0.25))
	txt(40 + dx, 316, "本局获得", 15, HH.LIGHT)
	var tiles: Array = [["cells", "+%d" % s.cells, "生机细胞"], ["vouchers", "×%d" % s.vouchers, "寻访凭证"]]
	for rl in key_relics(6):
		tiles.append(["relic", rl, str(rl.name)])
	for i in tiles.size():
		var p := k(1.4 + 0.05 * i, 0.35)
		if p <= 0.0:
			continue
		var e := UM.out_back(p, 1.5) if won else UM.out_cubic(p)
		fa = minf(1.0, p * 2.0)
		var rc := Rect2(40 + (i % 4) * 92, 346 + (i / 4) * 92 - 18.0 * (1.0 - e), 70, 70)
		_tile(rc, tiles[i], acc)
	fa = 1.0
	if bool(s.g.roster_new.get("short", false)):
		fa = ek(1.5, 0.3)
		txt(40, 532, "探索不足 %d 分钟，不发放凭证" % int(Roster.RUN_MIN_T / 60.0), 11, HH.MUTE)
	# 数据三列
	var best: Dictionary = m().get("best", {})
	var st: Array = [["总伤害", num(float(m().total))], ["击败敌人", num(float(m().kills))], ["最高单次", num(float(best.get("v", 0.0)))]]
	for i in st.size():
		fa = ek(1.7 + 0.06 * i, 0.3)
		rect(Rect2(40 + i * 128, 556, 2, 46), acc if i == 0 else HH.DARK3)
		txt(50 + i * 128, 556, str(st[i][0]), 12, HH.MUTE)
		txt(50 + i * 128, 574, str(st[i][1]), 22, HH.LIGHT, 0, 118)
	fa = 1.0


## 方格：深底 + 细白框 + 左下角强调色三角；藏品画图标，细胞 / 凭证写数
func _tile(rc: Rect2, t: Array, acc: Color) -> void:
	rect(rc, HH.DARK2)
	rect(rc.grow(-3), Color(1, 1, 1, 0.55), false, 1.5)
	var corner := acc
	if str(t[0]) == "relic":
		var tx: Texture2D = relic_tex(str(t[1].id))
		if tx != null:
			ci.draw_texture_rect(tx, rc.grow(-12), false, Color(1, 1, 1, fa))
		else:   # 没有图标：写名字首字
			txt(rc.get_center().x, rc.position.y + 20, str(t[1].name).substr(0, 1), 24, HH.LIGHT, 1)
		var rar := str(t[1].rarity)
		corner = MAG if rar == "遭诅古物" else (Color8(170, 120, 255) if rar == "升华" else acc)
	else:
		txt(rc.get_center().x, rc.position.y + 14, str(t[1]), 22, HH.CYB if str(t[0]) == "vouchers" else HH.LIGHT, 1)
		txt(rc.get_center().x, rc.position.y + 46, str(t[2]), 11, HH.MUTE, 1)
	poly(PackedVector2Array([Vector2(rc.position.x, rc.end.y - 20), Vector2(rc.position.x + 20, rc.end.y), Vector2(rc.position.x, rc.end.y)]), corner)


# ---------------------------------------------------------------- 正中立绘
func _leader(r: Dictionary, acc: Color) -> void:
	if r.is_empty():
		return
	var p := ek(0.25, 0.6)
	fa = minf(1.0, p * 1.5)
	var dx := 40.0 * (1.0 - p)
	# 背后一道竖排淡英文名
	var en := str(r.en).get_slice(" ", 0)
	for j in mini(en.length(), 10):
		px(Vector2(560 + dx, 90 + j * 52), en[j], 6.0, Color(r.col, 0.1))
	var col: Color = Color(0, 0, 0).lerp(Color.WHITE, p) if won else Color(0.08, 0.08, 0.1).lerp(Color(0.52, 0.52, 0.58), p)
	art(str(r.key), Rect2(420 + dx, 90, 310, 512), col, 6.0)   # 帧条立绘放大到 6 倍为止，再大像素块太粗
	# 名牌
	fa = ek(0.7, 0.3)
	para(Rect2(392, 606, 250, 34), HH.LIGHT)
	rect(Rect2(392, 640, 250, 3), acc)
	txt(410, 611, str(r.name), 20, HH.INK)
	txt(410 + tw(str(r.name), 20) + 10, 617, "队长  Lv.%d" % int(m().get("level", 1)), 12, HH.INK2)
	if not won:
		var q := k(1.1, 0.35)
		if q > 0.0:
			fa = minf(1.0, q * 2.0)
			var c := Vector2(620, 220)
			xf(c, -0.12, Vector2.ONE * lerpf(1.6, 1.0, UM.out_cubic(q)))
			rect(Rect2(c - Vector2(62, 24), Vector2(124, 48)), MAG, false, 3.0)
			txt(c.x, c.y - 20, "击倒", 32, MAG, 1)
			reset_xf()
	fa = 1.0


# ---------------------------------------------------------------- 右侧编队卡格
func _grid(acc: Color) -> void:
	var ops: Array = []
	for r in s.rows:
		if str(r.key) != OTHER:
			ops.append(r)
	var mvp := mvp_row()
	var n := COLS * maxi(ROWS, int(ceil(ops.size() / float(COLS))))
	var rows := n / COLS
	var ch := minf(CH, (586.0 - GAP * (rows - 1)) / rows)
	fa = ek(0.35, 0.3)
	px(Vector2(GX + 4, GY - 14), "SQUAD  //  %d" % ops.size(), 1.5, HH.MUTE, 0, 2)
	for i in n:
		var col := i % COLS
		var row := i / COLS
		var rc := Rect2(GX + col * (CW + GAP) - row * TILT, GY + row * (ch + GAP), CW, ch)
		var p := k(0.45 + 0.045 * i, 0.3)
		if p <= 0.0:
			continue
		fa = minf(1.0, p * 2.0)
		rc.position.y -= 16.0 * (1.0 - UM.out_cubic(p))
		if i < ops.size():
			_card(rc, ops[i], ops[i].key == mvp.key, 0.45 + 0.045 * i + 0.3, acc)
		else:
			_empty(rc)
	fa = 1.0


func _card(rc: Rect2, r: Dictionary, is_m: bool, t_in: float, acc: Color) -> void:
	var down: bool = (not won) and r.leader
	rect(rc, HH.DARK2)
	rect(Rect2(rc.position.x, rc.position.y, rc.size.x, 3), acc if r.leader else r.col)
	art(str(r.key), Rect2(rc.position.x + 6, rc.position.y + 8, rc.size.x - 12, rc.size.y - 48), Color(0.5, 0.5, 0.55) if down else Color.WHITE)
	# 底部信息条：精英化菱形 + 名字 + 占比
	rect(Rect2(rc.position.x, rc.end.y - 40, rc.size.x, 40), Color(HH.INK, 0.86))
	for e in int(r.get("elite", 0)):
		var c := Vector2(rc.position.x + 10 + e * 11, rc.end.y - 31)
		poly(PackedVector2Array([c + Vector2(0, -4), c + Vector2(4, 0), c + Vector2(0, 4), c + Vector2(-4, 0)]), HH.CYB)
	txt(rc.position.x + 6, rc.end.y - 22, str(r.name), 12, HH.LIGHT, 0, rc.size.x - 46)
	var cnt := ek(t_in, 0.5)
	px(Vector2(rc.end.x - 6, rc.end.y - 13), "%d%%" % int(round(float(r.pct) * cnt)), 2.0, HH.LIGHT, 2)
	if r.leader:
		txt(rc.end.x - 6, rc.position.y + 7, "队长", 11, acc, 2)
	elif is_m:
		txt(rc.end.x - 6, rc.position.y + 7, "最高输出", 11, HH.YEL, 2)
	if down:
		rect(Rect2(rc.position.x, rc.position.y + rc.size.y * 0.32, rc.size.x, 24), Color(MAG, 0.88))
		txt(rc.get_center().x, rc.position.y + rc.size.y * 0.32 + 3, "击倒", 15, HH.LIGHT, 1)
	# 显出：闪白一下
	var fl := k(t_in - 0.05, 0.25)
	if fl > 0.0 and fl < 1.0:
		var keep := fa
		fa = keep * (1.0 - fl) * 0.8
		rect(rc, Color.WHITE)
		fa = keep


## 空位：虚线框 + 十字准星 + NO INFO/
func _empty(rc: Rect2) -> void:
	var lc := Color(1, 1, 1, 0.14)
	rect(rc, Color(HH.DARK2, 0.55))
	var x := rc.position.x
	while x < rc.end.x:
		rect(Rect2(x, rc.position.y, minf(6, rc.end.x - x), 1), lc)
		rect(Rect2(x, rc.end.y - 1, minf(6, rc.end.x - x), 1), lc)
		x += 10.0
	var y := rc.position.y
	while y < rc.end.y:
		rect(Rect2(rc.position.x, y, 1, minf(6, rc.end.y - y)), lc)
		rect(Rect2(rc.end.x - 1, y, 1, minf(6, rc.end.y - y)), lc)
		y += 10.0
	var c := rc.get_center() - Vector2(0, 8)
	rect(Rect2(c.x - 14, c.y, 28, 1), lc)
	rect(Rect2(c.x, c.y - 8, 1, 17), lc)
	if fa > 0.0:
		ci.draw_arc(c, 6, 0, TAU, 16, Color(lc, lc.a * fa), 1.0)
	px(Vector2(rc.position.x + 8, rc.end.y - 22), "NO", 1.5, Color(HH.MUTE, 0.6), 0, 2)
	px(Vector2(rc.position.x + 8, rc.end.y - 10), "INFO/", 1.5, Color(HH.MUTE, 0.6), 0, 2)
