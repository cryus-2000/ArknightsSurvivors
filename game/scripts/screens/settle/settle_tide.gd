extends "res://scripts/screens/settle/settle_base.gd"
## 方向 B「潮汐航迹」：以一局的时间线为主体。中间一张全队每秒伤害的堆叠潮位图（各干员一层、干员色），
## Boss 段落成竖带、击破处一枚菱形；下方是干员入队泳道（头像落在入队时刻）；上缘结果与用时，下缘几项总数和获得。
## 层级：这一局怎么打下来的（曲线 + 事件）≫ 结果 ≫ 总数。
## 动效：一根航迹扫描线从左到右走完整局（约 2.2 秒），潮位图跟着线头长出，用时计数和线头同步，Boss 带 / 干员头像在线头经过时点亮；
## 胜利走到尽头一道白闪 + 评级落定；失败线头变洋红，尾段信号撕裂、「信号中断」。

const CH := Rect2(60, 176, 1160, 292)   # 潮位图
const HEAD0 := 0.45
const HEAD := 2.2


func end_win() -> float:
	return 3.4


func end_loss() -> float:
	return 4.0


func buttons() -> Array:
	return footer(664.0, 42.0)


func _x(tt: float) -> float:
	return CH.position.x + CH.size.x * clampf(tt / maxf(1.0, float(m().t)), 0.0, 1.0)


func draw(canvas: CanvasItem) -> void:
	begin(canvas)
	var acc: Color = HH.CYB if won else MAG
	var T: float = maxf(1.0, float(m().t))
	ci.draw_rect(Rect2(-400, -400, 2080, 1520), HH.DARK)
	# 细网格（像声呐屏）
	fa = ek(0.0, 0.3) * 0.5
	for i in 7:
		rect(Rect2(CH.position.x, CH.position.y + CH.size.y * i / 6.0, CH.size.x, 1), HH.DARK3)
	fa = 1.0
	var hp := UM.in_out_cubic(k(HEAD0, HEAD))   # 线头进度 0..1
	var hx := CH.position.x + CH.size.x * hp
	# ① 上缘：结果、用时计数、难度、评级
	fa = ek(0.0, 0.3)
	px(Vector2(40, 30), "VOYAGE LOG  //  TIDE RECORD", 2.0, HH.MUTE, 0, 2)
	txt(40, 46, "探索完成" if won else "探索终止", 36, HH.LIGHT if won else MAG)
	txt(40, 98, sub_line(), 15, HH.MUTE, 0, 420)
	txt(560, 40, "探索用时", 12, HH.MUTE)
	px(Vector2(560, 92), mmss(T * hp), 6.0, HH.LIGHT)
	txt(800, 40, "难度档", 12, HH.MUTE)
	txt(800, 62, diff_name(), 18, HH.LIGHT)
	_grade(acc)
	# ② Boss 段：竖带 + 名字，线头经过时点亮
	var bosses: Array = m().get("bosses", [])
	for b in bosses:
		var t0 := float(b.t0)
		var t1 := float(b.t1) if float(b.t1) >= 0.0 else T
		if t0 / T > hp:
			continue
		var x0 := _x(t0)
		var x1 := minf(_x(t1), hx)
		fa = ek(HEAD0 + HEAD * t0 / T, 0.25)
		rect(Rect2(x0, CH.position.y - 22, maxf(1.0, x1 - x0), CH.size.y + 22), Color(1, 1, 1, 0.05))
		rect(Rect2(x0, CH.position.y - 22, 2, CH.size.y + 22), Color(HH.LIGHT, 0.35))
		txt(x0 + 6, CH.position.y - 22, str(b.name), 12, HH.LIGHT, 0, maxf(60.0, _x(t1) - x0 + 60.0))
	fa = 1.0
	# ③ 潮位图（堆叠，每格一段梯形）
	_area(hp)
	# 击破菱形（盖在图上）
	for b in bosses:
		if float(b.t1) < 0.0 or bool(b.get("retreat", false)) or float(b.t1) / T > hp:
			continue
		var q := k(HEAD0 + HEAD * float(b.t1) / T, 0.3)
		fa = 1.0
		var x := _x(float(b.t1))
		var rr := lerpf(16.0, 6.0, UM.out_cubic(q))
		HH.fill(ci, PackedVector2Array([Vector2(x, CH.end.y - rr), Vector2(x + rr, CH.end.y), Vector2(x, CH.end.y + rr), Vector2(x - rr, CH.end.y)]), Color(HH.LIGHT, 0.5 + 0.5 * q))
		txt(x + 8, CH.end.y + 6, "击破", 11, HH.LIGHT)
	# ④ 时间轴刻度
	fa = ek(0.2, 0.3)
	rect(Rect2(CH.position.x, CH.end.y, CH.size.x, 1), HH.MUTE)
	var step := 120.0 if T > 480.0 else 60.0
	var tt := 0.0
	while tt <= T + 0.5:
		rect(Rect2(_x(tt), CH.end.y, 1, 5), HH.MUTE)
		txt(_x(tt), CH.end.y + 22, mmss(tt), 11, HH.MUTE, 1)
		tt += step
	fa = 1.0
	# ⑤ 线头
	if hp < 1.0 or not won:
		var hc: Color = HH.CYB if (won or hp < 0.92) else MAG
		fa = 1.0 if hp < 1.0 else maxf(0.0, 1.0 - k(HEAD0 + HEAD + 0.5, 0.4))
		rect(Rect2(hx - 1, CH.position.y - 30, 2, CH.size.y + 30), hc)
		rect(Rect2(hx - 5, CH.position.y - 34, 10, 4), hc)
		fa = 1.0
	_end_mark(hp)
	# ⑥ 干员泳道
	_lanes(hp)
	# ⑦ 下缘总数 + 获得
	_totals(hp)
	fa = ek(HEAD0 + HEAD + 0.5, 0.35)
	rect(Rect2(-400, 652, 2080, 500), HH.INK)
	s._draw_buttons(ci, fa)
	fa = 1.0


func _series() -> Array:
	var tl: Dictionary = m().get("timeline", {})
	var src: Array = tl.get("series", [])
	# 三格平滑，曲线像潮位而不是锯齿
	var out: Array = []
	for i in src.size():
		var col: Array = []
		for j in (src[i] as Array).size():
			var a := float(src[maxi(0, i - 1)][j])
			var b := float(src[i][j])
			var c := float(src[mini(src.size() - 1, i + 1)][j])
			col.append((a + 2.0 * b + c) / 4.0)
		out.append(col)
	return out


func _area(hp: float) -> void:
	var ser := _series()
	var rows: Array = m().get("rows", [])
	if ser.is_empty() or rows.is_empty():
		return
	var peak := 1.0
	for col in ser:
		var sm := 0.0
		for v in col:
			sm += float(v)
		peak = maxf(peak, sm)
	var n := ser.size()
	var bw := CH.size.x / n
	var hx := CH.position.x + CH.size.x * hp
	var dim := 1.0 if won else 0.72
	var tops: PackedVector2Array = []
	for i in n:
		var x0 := CH.position.x + bw * i
		if x0 >= hx:
			break
		var x1 := minf(x0 + bw, hx)
		var i1 := mini(n - 1, i + 1)
		var f := (x1 - x0) / bw
		var acc0 := 0.0
		var acc1 := 0.0
		for j in rows.size():
			var v0 := float(ser[i][j])
			var v1 := lerpf(v0, float(ser[i1][j]), f)
			var y0a := CH.end.y - CH.size.y * acc0 / peak
			var y1a := CH.end.y - CH.size.y * acc1 / peak
			acc0 += v0
			acc1 += v1
			var y0b := CH.end.y - CH.size.y * acc0 / peak
			var y1b := CH.end.y - CH.size.y * acc1 / peak
			if y0a - y0b < 0.3 and y1a - y1b < 0.3:
				continue
			var c: Color = rows[j].col
			c = Color(c.r * dim, c.g * dim, c.b * dim, 0.82)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(x0, y0a), Vector2(x0, y0b), Vector2(x1, y1b), Vector2(x1, y1a)]), c)
		if tops.is_empty():
			tops.append(Vector2(x0, CH.end.y - CH.size.y * acc0 / peak))
		tops.append(Vector2(x1, CH.end.y - CH.size.y * acc1 / peak))
	if tops.size() >= 2:
		ci.draw_polyline(tops, Color(HH.LIGHT, 0.9), 2.0)


## 走到尽头：胜利白闪 + 一道竖光；失败尾段撕裂 + 「信号中断」
func _end_mark(hp: float) -> void:
	if hp < 1.0:
		return
	var q := k(HEAD0 + HEAD, 0.5)
	var x := CH.end.x
	if won:
		fa = 1.0 - q
		rect(Rect2(x - 40 * q - 2, CH.position.y - 30, 4 + 80 * q, CH.size.y + 30), Color(1, 1, 1, 0.5))
		fa = 1.0
		rect(Rect2(x - 1, CH.position.y - 30, 2, CH.size.y + 30), HH.CYB)
		txt(x - 8, CH.position.y + 26, "探索完成", 13, HH.CYB, 2)
	else:
		# 尾段几条横向撕裂条（固定花样，不用随机数）
		for i in 6:
			var y := CH.position.y + 30 + i * 44
			var w := 30.0 + float((i * 53) % 70)
			fa = 0.6 * (1.0 - 0.6 * q)
			rect(Rect2(x - w - 6 + sin(t * 9.0 + i) * 6.0 * (1.0 - q), y, w, 3 + i % 3), MAG)
		fa = 1.0
		rect(Rect2(x - 1, CH.position.y - 30, 2, CH.size.y + 30), MAG)
		fa = minf(1.0, q * 2.0)
		txt(x - 8, CH.position.y + 26, "信号中断", 13, MAG, 2)
	fa = 1.0


func _lanes(hp: float) -> void:
	var rows: Array = s.rows
	var T: float = maxf(1.0, float(m().t))
	# 头像按入队时刻排，重叠就往右推（细线连回真实时刻）
	var xs: Array = []
	var last := -999.0
	for r in rows:
		var x := maxf(_x(float(r.join_t)), last + 66.0)
		xs.append(x)
		last = x
	var over: float = last - (CH.end.x - 28.0)
	if over > 0.0:
		for i in xs.size():
			xs[i] = float(xs[i]) - over * (float(i) / maxf(1.0, xs.size() - 1))
	for i in rows.size():
		var r: Dictionary = rows[i]
		var tj := float(r.join_t)
		if tj / T > hp + 0.001:
			continue
		var q := k(HEAD0 + HEAD * tj / T, 0.35)
		var e := UM.out_back(q, 1.8) if won else UM.out_cubic(q)
		fa = minf(1.0, q * 3.0)
		var ax := _x(tj)
		var x := float(xs[i])
		ci.draw_line(Vector2(ax, CH.end.y + 2), Vector2(x, 506), Color(r.col, 0.6 * fa), 1.0)
		var box := Rect2(x - 28, 506 + 10.0 * (1.0 - e), 56, 56)
		rect(box, HH.DARK2)
		rect(Rect2(box.position.x, box.position.y, box.size.x, 3), r.col)
		var mod := Color.WHITE if won or not r.leader else Color(0.55, 0.55, 0.6)
		art(str(r.key), box.grow(-4), mod)
		txt(x, 566 + 10.0 * (1.0 - e), str(r.name), 12, HH.LIGHT, 1, 64)
		if float(r.left_t) >= 0.0 and float(r.left_t) / T <= hp:
			txt(_x(float(r.left_t)), CH.end.y - 18, "离队", 10, HH.MUTE, 1)
			rect(Rect2(_x(float(r.left_t)), CH.end.y - 4, 1, 4), HH.MUTE)
	fa = 1.0


func _totals(hp: float) -> void:
	var p := ek(HEAD0 + 0.2, 0.3)
	fa = p
	var items: Array = [["总伤害", num(float(m().total) * hp), HH.LIGHT], ["击败敌人", num(float(m().kills) * hp), HH.LIGHT],
		["Boss 击破", str(boss_kills()), HH.LIGHT], ["藏品", str(int(m().get("relics", 0))), HH.LIGHT]]
	var gq := ek(HEAD0 + HEAD + 0.2, 0.4)
	items.append(["生机细胞", "+%d" % int(s.cells * gq), HH.LIGHT])
	items.append(["寻访凭证", "×%d" % int(s.vouchers * gq), HH.CYB])
	for i in items.size():
		var x := 60.0 + i * 196.0
		fa = p if i < 4 else gq
		rect(Rect2(x, 604, 2, 40), HH.CYB if i >= 4 else HH.DARK3)
		txt(x + 12, 602, str(items[i][0]), 12, HH.MUTE)
		txt(x + 12, 618, str(items[i][1]), 24, items[i][2])
	fa = 1.0


func _grade(acc: Color) -> void:
	var g := grade()
	var r := Rect2(1130, 28, 110, 110)
	fa = ek(0.1, 0.3)
	rect(r, HH.DARK3, false, 1.0)
	px(Vector2(r.get_center().x, r.position.y + 14), "RATING", 2.0, HH.MUTE, 1, 2)
	var q := k(HEAD0 + HEAD + 0.15, 0.25)
	if q <= 0.0:
		fa = 1.0
		return
	fa = minf(1.0, q * 2.5) if won else ek(HEAD0 + HEAD + 0.15, 0.6)
	var kk: float = [8.0, 6.0, 4.5][clampi(g.length() - 1, 0, 2)]
	var dy := -14.0 * (1.0 - UM.out_cubic(q)) if won else 0.0
	px(Vector2(r.get_center().x, r.get_center().y + 10 + dy), g, kk, acc if not won else HH.LIGHT, 1)
	fa = 1.0
