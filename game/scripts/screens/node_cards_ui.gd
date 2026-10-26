extends RefCounted
## 翻节点卡界面（docs/154，10-26 用户「多结局翻卡的 UI 能不能再好好设计一下」）：
## - 卡背：像素阶梯切角，按节点类型各自的底色 + 纹样（不期而遇菱形涟漪 / 得偿所愿星屑 / 诡意行商货架 / 安全的角落炊烟 / 紧急作战警示斜阶 / 迷雾重重雾带），
##   四角像素角饰；结局入口描达成结局的色边（跑动的高光段 + 顶部罗马数字徽记，两色左右各半）
## - 演出：发牌（自中心扇出升起）→ 悬停抬起 → 起手（选中卡再抬起放大，其余下沉）→ 翻转（横向压扁 + 中线闪光）→ 揭示（像素颗粒迸散、正文自上而下显出）→ 未选卡退场
## - 背景：战场压暗但保留，上方航点向三张卡分出虚线航路（「路口」）
## 计时用界面时钟 UM.now()（--fixed-fps 录屏按帧走）；颗粒位置按卡序号与格子算，不碰随机数。

const UI = preload("res://scripts/ui.gd")
const UM = preload("res://scripts/ui_motion.gd")
const NodeIcons = preload("res://scripts/screens/node_icons.gd")

const P := 3.0            # 卡面像素格（设计像素）
const STEPS := 3          # 切角阶数
const LIFT_T := 0.16      # 起手
const FLIP_T := 0.30      # 翻转
const REVEAL_T := 0.45    # 揭示
## 节点类型的卡背底色（上 / 下）与纹样色
const TINT := {
	"incident": [Color(0.055, 0.12, 0.22), Color(0.02, 0.045, 0.09)],
	"wish": [Color(0.17, 0.12, 0.05), Color(0.06, 0.04, 0.02)],
	"shop": [Color(0.17, 0.09, 0.05), Color(0.06, 0.03, 0.02)],
	"rest": [Color(0.04, 0.15, 0.13), Color(0.015, 0.055, 0.05)],
	"elite": [Color(0.19, 0.04, 0.08), Color(0.07, 0.01, 0.03)],
	"fog": [Color(0.11, 0.12, 0.15), Color(0.04, 0.045, 0.06)],
}
const ROMAN := {"standard": "Ⅰ", "knight": "Ⅱ", "deep": "Ⅲ", "resolve": "Ⅳ"}
## C 版信物提示（Codex 交付 art/incoming/node_route_c_delivery_1026，用户 10-26 定稿）：结局入口卡底放该路线的现有信物图标（32×32，原色）+ 信物名，
## 中心距 80；只画已达成过的结局（未知路线不泄露）；图标只是路线提示，不是奖励承诺也不是持有状态
const ROUTE_RELIC := {"knight": "222", "deep": "220", "resolve": "242"}
const TOKEN_NAME := {"knight": "海潮的气息", "deep": "主教的研究", "resolve": "深蓝回忆"}
const ROUTE_NAME := {"knight": "静谧时代", "deep": "息潮的代价", "resolve": "如星空般深蓝"}
const INCIDENT_BACK := preload("res://art/ui/node_cards/incident.png")   # 不期而遇精修底纹（272×408，Codex）


static func _h(i: float, j: float) -> float:
	return fposmod(sin(i * 12.9898 + j * 78.233) * 43758.5453, 1.0)


## 像素阶梯切角矩形的轮廓点（顺时针）
static func step_poly(r: Rect2, n := STEPS, p := P) -> PackedVector2Array:
	var c: Array = []
	for k in n:
		c.append(Vector2(k * p, (n - k) * p))
		c.append(Vector2(k * p, (n - k - 1) * p))
	c.append(Vector2(n * p, 0))
	var w := r.size.x
	var h := r.size.y
	var o := PackedVector2Array()
	for q in c:
		o.append(r.position + q)
	for k in range(c.size() - 1, -1, -1):
		o.append(r.position + Vector2(w - c[k].x, c[k].y))
	for q in c:
		o.append(r.position + Vector2(w - q.x, h - q.y))
	for k in range(c.size() - 1, -1, -1):
		o.append(r.position + Vector2(c[k].x, h - c[k].y))
	return o


static func step_line(ci: CanvasItem, r: Rect2, col: Color, wdt := 2.0, n := STEPS) -> void:
	var pts := step_poly(r, n)
	pts.append(pts[0])
	ci.draw_polyline(pts, col, wdt)


## ---------- 背景：压暗战场之上的航路 ----------
## cards：每张卡在 ci 坐标里的矩形；flipped：已翻开的下标（-1 = 未翻）
static func draw_bg(ci: CanvasItem, vs: Vector2, cards: Array, flipped: int, t: float, top_y: float) -> void:
	# 横向海流细线（很淡、缓慢平移），四角压暗
	for k in 9:
		var y := top_y - 40.0 + k * 58.0
		var x0 := fposmod(t * 18.0 + k * 97.0, 160.0) - 160.0
		var x := x0
		while x < vs.x:
			ci.draw_rect(Rect2(roundf(x), roundf(y), 72.0, 2.0), Color(0.45, 0.75, 0.9, 0.035))
			x += 160.0
	if cards.is_empty():
		return
	# 航线：一条横穿各卡中线的虚线海流（卡与卡之间、两侧露出），流向右；每张卡左右各一个小节点，翻开后选中卡两侧变亮、其余熄灭
	var y: float = roundf((cards[0] as Rect2).get_center().y)
	var seg := 10.0
	var s := fposmod(t * 30.0, seg * 2.0) + 40.0
	while s < vs.x - 40.0:
		ci.draw_rect(Rect2(roundf(s), y - 1.0, seg, 3.0), Color(0.38, 0.88, 0.91, 0.32))
		s += seg * 2.0
	# 两端航点
	for x in [40.0, vs.x - 40.0]:
		UI.diamond(ci, Vector2(x, y), 7.0, Color(0.05, 0.12, 0.18, 0.95), Color(0.38, 0.88, 0.91, 0.75))
	for i in cards.size():
		var cr: Rect2 = cards[i]
		var on: bool = flipped < 0 or flipped == i
		var col := Color(0.38, 0.88, 0.91, 0.95 if flipped == i else (0.6 if on else 0.12))
		for x in [cr.position.x - 12.0, cr.end.x + 12.0]:
			ci.draw_rect(Rect2(Vector2(x - 4.0, y - 4.0), Vector2(8.0, 8.0)), col)


## ---------- 卡片 ----------
## st：{i, hot, flipped, deal_t（发牌开始的界面时钟）, flip_t, n（张数）, center_x（整排中心，卡片坐标）, face_title, face_body, face_tag, fog, ends: [结局 id], ends_cols: [Color]}
static func draw_card(ci: CanvasItem, size: Vector2, c: Dictionary, st: Dictionary, font: Font, serif: Font) -> void:
	var now := UM.now()
	var i: int = st.i
	var fl: int = st.flipped
	var t: String = str(c.get("type", "incident"))
	var col: Color = NodeIcons.COLS.get(t, UI.CYAN)
	var r := Rect2(Vector2.ZERO, size)
	var ctr := r.get_center()
	# 发牌：从整排中心下方扇出升起
	var rm := UM.rm()
	var dp := UM.out_cubic(clampf((now - float(st.deal_t) - i * 0.09) / 0.42, 0.0, 1.0)) if not UM.skip_all() else 1.0
	var off := Vector2((float(st.center_x) - ctr.x) * (1.0 - dp), 120.0 * (1.0 - dp))
	var rot := deg_to_rad((i - (float(st.n) - 1.0) / 2.0) * 9.0) * (1.0 - dp)
	if rm:
		# 减少动态：发牌只做 0.12 秒淡入，不飞不转
		off = Vector2.ZERO
		rot = 0.0
		dp = clampf((now - float(st.deal_t)) / UM.T1, 0.0, 1.0)
	st.token_k = clampf((now - float(st.deal_t) - i * 0.09 - 0.36) / 0.22, 0.0, 1.0) if not rm else dp   # 信物提示在卡落定后浮现
	var sc := 1.0
	var sx := 1.0
	var a := clampf(dp * 1.6, 0.0, 1.0)
	var face := false
	var reveal := 1.0
	var flip_age := now - float(st.flip_t)
	if fl >= 0 and fl == i:
		# 起手 → 翻转 → 揭示
		var lift := UM.out_cubic(clampf(flip_age / LIFT_T, 0.0, 1.0)) if not rm else 0.0
		off.y -= 22.0 * lift
		sc = 1.0 + 0.06 * lift
		var fe := clampf((flip_age - LIFT_T) / FLIP_T, 0.0, 1.0)
		face = fe >= 0.5
		# 翻转同时滑到整排中央，揭示在正中
		if not rm:
			off.x += (float(st.center_x) - ctr.x) * UM.in_out_cubic(clampf((flip_age - LIFT_T * 0.5) / (FLIP_T + LIFT_T * 0.5), 0.0, 1.0))
			sx = maxf(0.04, absf(1.0 - 2.0 * UM.in_out_cubic(fe)))
		else:
			a *= absf(1.0 - 2.0 * fe)   # 减少动态：背面淡出、正面淡入
			reveal = 1.0
		reveal = clampf((flip_age - LIFT_T - FLIP_T * 0.5) / REVEAL_T, 0.0, 1.0)
	elif fl >= 0:
		# 未选卡退场：下沉淡出
		var ex := UM.out_cubic(clampf(flip_age / 0.35, 0.0, 1.0))
		off.y += 46.0 * ex
		a *= 1.0 - ex
		sc = 1.0 - 0.06 * ex
	else:
		var hk: float = float(st.get("hover_k", 1.0 if st.hot else 0.0))
		off.y -= (0.0 if rm else 12.0) * UM.out_cubic(hk)
		sc = 1.0 + (0.0 if rm else 0.02) * hk
	if a <= 0.01:
		return
	# 选中卡起手时脚下一道光（压在卡下）
	if fl == i and flip_age < LIFT_T + FLIP_T + REVEAL_T:
		var gk := clampf(flip_age / LIFT_T, 0.0, 1.0) * (1.0 - clampf((flip_age - LIFT_T - FLIP_T) / REVEAL_T, 0.0, 1.0))
		for k in 3:
			var gw := size.x * (0.9 - k * 0.2)
			ci.draw_rect(Rect2(ctr.x - gw / 2.0, size.y + 4.0 + k * 4.0 + off.y * 0.2, gw, 4.0), Color(col.r, col.g, col.b, 0.35 * gk * (1.0 - k * 0.3)))
	ci.draw_set_transform_matrix(Transform2D(rot, Vector2(sc * sx, sc), 0.0, ctr + off) * Transform2D(0.0, Vector2.ONE, 0.0, -ctr))
	ci.self_modulate.a = 1.0
	if face:
		_face(ci, r, c, st, font, serif, col, reveal, flip_age)
	else:
		_back(ci, r, c, st, font, serif, col, t, now, a)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	# 翻转中线闪光（不随卡片压扁）：竖亮线 + 两侧台阶光
	if fl == i and not rm and flip_age > LIFT_T and flip_age < LIFT_T + FLIP_T:
		var k := 1.0 - absf((flip_age - LIFT_T) / FLIP_T - 0.5) * 2.0
		var cx := ctr.x + off.x
		var y0 := off.y + (1.0 - sc) * ctr.y - 8.0
		var hh := size.y * sc + 16.0
		for q in 3:
			var ww := 4.0 + q * 8.0
			ci.draw_rect(Rect2(cx - ww / 2.0, y0 + q * 6.0, ww, hh - q * 12.0), Color(0.85, 1.0, 1.0, (0.9 - q * 0.3) * k))


static func _back(ci: CanvasItem, r: Rect2, c: Dictionary, st: Dictionary, font: Font, serif: Font, col: Color, t: String, now: float, a: float) -> void:
	if t == "incident":
		_back_incident(ci, r, st, font, serif, now, a)
		return
	var tint: Array = TINT.get(t, TINT.incident)
	var hot: bool = st.hot
	var poly := step_poly(r)
	var top: Color = tint[0].lerp(col, 0.06 if hot else 0.0)
	var bot: Color = tint[1]
	var cols := PackedColorArray()
	for q in poly:
		cols.append(top.lerp(bot, clampf((q.y - r.position.y) / r.size.y, 0.0, 1.0)) * Color(1, 1, 1, a))
	ci.draw_polygon(poly, cols)
	var inner := r.grow(-12.0)
	_pattern(ci, inner, t, col, now, a * (1.0 if hot else 0.75))
	# 双层框：外框类型色（暗）、内框细线；四角像素角饰
	step_line(ci, r.grow(-1.0), Color(col.r, col.g, col.b, (0.95 if hot else 0.5) * a), 2.0)
	step_line(ci, inner, Color(col.r, col.g, col.b, 0.18 * a), 1.0, 2)
	for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var cp: Vector2 = inner.position + inner.size * corner
		var sxn: float = 1.0 if corner.x == 0 else -1.0
		var syn: float = 1.0 if corner.y == 0 else -1.0
		var cc := Color(col.r, col.g, col.b, 0.9 * a)
		ci.draw_rect(Rect2(cp + Vector2(0 if sxn > 0 else -4.0 * P, 0 if syn > 0 else -P), Vector2(4.0 * P, P)), cc)
		ci.draw_rect(Rect2(cp + Vector2(0 if sxn > 0 else -P, 0 if syn > 0 else -4.0 * P), Vector2(P, 4.0 * P)), cc)
	# 中央图标（悬停时轻浮动）+ 光晕台阶
	var ic := Vector2(r.get_center().x, r.position.y + r.size.y * 0.42 + (roundf(2.0 * sin(now * 4.0)) if hot else 0.0))
	for k in 3:
		var rr := 64.0 - k * 16.0
		ci.draw_rect(Rect2(ic - Vector2(rr, rr * 0.5), Vector2(rr * 2.0, rr)), Color(col.r, col.g, col.b, (0.035 + 0.02 * k + (0.03 if hot else 0.0)) * a))
	NodeIcons.draw(ci, t, ic, 6.0, Color(col.r, col.g, col.b, a))
	# 名字 + 英文
	var nm: String = NodeIcons.NAMES.get(t, "")
	ci.draw_string(serif, Vector2(r.position.x, r.end.y - 88.0), nm, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 26, Color(1, 1, 1, a) if hot else Color(UI.TEXT.r, UI.TEXT.g, UI.TEXT.b, a))
	var en: String = NodeIcons.EN.get(t, "")
	var ew := UI.en_width(font, en, 11, 3.0)
	UI.en(ci, font, Vector2(r.get_center().x - ew / 2.0, r.end.y - 60.0), en, 11, Color(col.r, col.g, col.b, 0.85 * a), 3.0)
	# 序号牌（左上）
	var tag := Rect2(r.position + Vector2(14, 14), Vector2(26, 22))
	ci.draw_rect(tag, Color(0, 0, 0, 0.45 * a))
	UI.ctext(ci, font, tag.position + Vector2(0, 16), str(int(st.i) + 1), 14, Color(col.r, col.g, col.b, a), HORIZONTAL_ALIGNMENT_CENTER, tag.size.x)
	if hot:
		step_line(ci, r.grow(4.0), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.55 * a), 2.0, 4)
		step_line(ci, r.grow(9.0), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.18 * a), 2.0, 5)


## 各类型的卡背纹样（只画在内框里，像素格对齐）
static func _pattern(ci: CanvasItem, ir: Rect2, t: String, col: Color, now: float, a: float) -> void:
	var cx := ir.get_center().x
	var cy := ir.position.y + ir.size.y * 0.42 + 12.0
	match t:
		"incident":
			# 同心菱形涟漪（每 1.6 秒向外扩一圈）
			for k in 5:
				var rr := fposmod(k * 26.0 + now * 16.0, 130.0) + 30.0
				var al := (1.0 - rr / 160.0) * 0.22 * a
				var pts := PackedVector2Array([Vector2(cx, cy - rr), Vector2(cx + rr, cy), Vector2(cx, cy + rr), Vector2(cx - rr, cy), Vector2(cx, cy - rr)])
				for q in pts.size() - 1:
					_dash(ci, pts[q], pts[q + 1], Color(col.r, col.g, col.b, al), ir)
		"wish":
			# 星屑：格子上散落的十字小星，按格子哈希闪烁
			var gx := int(ir.size.x / (P * 6.0))
			var gy := int(ir.size.y / (P * 6.0))
			for x in gx:
				for y in gy:
					var hv := _h(x, y)
					if hv > 0.16:
						continue
					var tw := 0.5 + 0.5 * sin(now * 2.6 + hv * 40.0)
					var p := ir.position + Vector2(x, y) * P * 6.0 + Vector2(P * 3.0, P * 3.0)
					var cc := Color(col.r, col.g, col.b, (0.12 + 0.3 * tw) * a)
					ci.draw_rect(Rect2(p - Vector2(P, 0), Vector2(P * 3.0, P)), cc)
					ci.draw_rect(Rect2(p - Vector2(0, P), Vector2(P, P * 3.0)), cc)
		"shop":
			# 货架：横向层板 + 架上的钱币点
			var y := ir.position.y + 30.0
			var row := 0
			while y < ir.end.y - 20.0:
				ci.draw_rect(Rect2(ir.position.x + 10.0, y, ir.size.x - 20.0, P), Color(col.r, col.g, col.b, 0.14 * a))
				for k in 6:
					if _h(row, k) < 0.5:
						var px := ir.position.x + 22.0 + k * (ir.size.x - 44.0) / 5.0
						ci.draw_rect(Rect2(px - P, y - P * 2.0, P * 2.0, P * 2.0), Color(col.r, col.g, col.b, 0.22 * a))
				y += 46.0
				row += 1
		"rest":
			# 炊烟：自下而上缓慢飘的像素波线
			for k in 4:
				var x0 := ir.position.x + 30.0 + k * (ir.size.x - 60.0) / 3.0
				for s in 26:
					var yy := ir.end.y - fposmod(s * 12.0 + now * 20.0 + k * 31.0, ir.size.y)
					var xx := x0 + roundf(6.0 * sin(yy * 0.05 + k))
					var al := clampf((yy - ir.position.y) / ir.size.y, 0.0, 1.0) * 0.18 * a
					ci.draw_rect(Rect2(roundf(xx), roundf(yy), P, P), Color(col.r, col.g, col.b, al))
		"elite":
			# 警示斜阶：像素阶梯斜纹，缓慢向右移动
			var step := 28.0
			var sh := fposmod(now * 14.0, step)
			var x := ir.position.x - ir.size.y + sh
			while x < ir.end.x:
				var yy := ir.end.y
				var xx := x
				while yy > ir.position.y:
					if xx >= ir.position.x and xx < ir.end.x - P:
						ci.draw_rect(Rect2(xx, yy - P, P * 2.0, P), Color(col.r, col.g, col.b, 0.13 * a))
					xx += P
					yy -= P
				x += step
		"fog":
			# 雾带：几条横向的宽像素带，左右漂移
			for k in 6:
				var yy := ir.position.y + 24.0 + k * (ir.size.y - 48.0) / 5.0
				var w := ir.size.x * (0.4 + 0.3 * _h(k, 3.0))
				var xx := ir.position.x + fposmod(now * (8.0 + k * 3.0) + k * 47.0, ir.size.x + w) - w
				var l: float = maxf(ir.position.x, xx)
				var rgt: float = minf(ir.end.x, xx + w)
				if rgt > l:
					ci.draw_rect(Rect2(l, yy, rgt - l, P * 2.0), Color(col.r, col.g, col.b, 0.12 * a))


static func _dash(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, clip: Rect2) -> void:
	var n := int(a.distance_to(b) / (P * 2.0))
	for k in n:
		if k % 2 == 1:
			continue
		var p := a.lerp(b, float(k) / maxf(1.0, n))
		if clip.has_point(p):
			ci.draw_rect(Rect2(p.round(), Vector2(P, P)), col)


## 结局色边：2 格粗的色框（两色时左右各半）+ 一段沿框跑动的亮白高光 + 顶边中央罗马数字徽记
## 不期而遇卡背（C 版）：精修底纹 + 细银边（左上受光、右下回暗）+ 白色节点图标 + 名字；结局入口在卡底放信物提示
static func _back_incident(ci: CanvasItem, r: Rect2, st: Dictionary, font: Font, serif: Font, now: float, a: float) -> void:
	var hot: bool = st.hot
	ci.draw_rect(r, Color(0.025, 0.04, 0.06, a))
	ci.draw_texture_rect(INCIDENT_BACK, r.grow(-2.0), false, Color(1, 1, 1, a))
	ci.draw_rect(r.grow(-1.0), Color(0.24, 0.30, 0.35, a), false, 2.0)
	var tl := r.position + Vector2(2, 2)
	var br := r.end - Vector2(3, 3)
	ci.draw_line(tl, Vector2(br.x, tl.y), Color(0.67, 0.73, 0.76, a), 1.0)
	ci.draw_line(tl, Vector2(tl.x, br.y), Color(0.49, 0.57, 0.63, a), 1.0)
	ci.draw_line(Vector2(br.x, tl.y), br, Color(0.19, 0.25, 0.30, a), 1.0)
	ci.draw_line(Vector2(tl.x, br.y), br, Color(0.35, 0.43, 0.48, a), 1.0)
	ci.draw_line(tl + Vector2(0, 1), tl + Vector2(34, 1), Color(0.87, 0.91, 0.92, a), 1.0)
	if hot:
		ci.draw_line(tl + Vector2(35, 0), tl + Vector2(r.size.x * 0.64, 0), Color(0.79, 0.86, 0.91, a), 2.0)
		step_line(ci, r.grow(5.0), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.4 * a * float(st.get("hover_k", 1.0))), 2.0, 4)
	var ic := Vector2(r.get_center().x, roundf(r.position.y + r.size.y * 0.40))
	NodeIcons.draw(ci, "incident", ic, 7.0, Color(0.89, 0.93, 0.95, a))
	ci.draw_string(serif, Vector2(r.position.x, roundf(ic.y + 104.0)), "不期而遇", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 28, Color(0.89, 0.92, 0.94, a))
	route_tokens(ci, r, st, font, a)


## 卡底信物提示：分隔细线 + 每条路线一枚现有信物图标（32×32 原色）+ 结局色短线 + 信物名，中心距 80；卡落定后浮现（token_k）
static func route_tokens(ci: CanvasItem, r: Rect2, st: Dictionary, font: Font, a: float) -> void:
	var ends: Array = st.get("ends", [])
	if ends.is_empty():
		return
	var k: float = float(st.get("token_k", 1.0))
	if k <= 0.0:
		return
	var ta := a * UM.out_cubic(k)
	var cols: Array = st.get("ends_cols", [])
	var texs: Dictionary = st.get("relic_tex", {})
	var center := r.get_center().x
	var span := ends.size() * 80.0
	var y := roundf(r.end.y - 67.0 + 6.0 * (1.0 - UM.out_cubic(k)))
	ci.draw_line(Vector2(center - span * 0.5 - 20.0, y - 8.0), Vector2(center + span * 0.5 + 20.0, y - 8.0), Color(0.38, 0.49, 0.59, ta * 0.35), 1.0)
	for q in ends.size():
		var e: String = str(ends[q])
		var x := roundf(center - span * 0.5 + q * 80.0 + 24.0)
		var tx: Texture2D = texs.get(ROUTE_RELIC.get(e, ""), null)
		if tx != null:
			ci.draw_texture_rect(tx, Rect2(Vector2(x, y), Vector2(32, 32)), false, Color(1, 1, 1, ta))
		var cc: Color = cols[mini(q, cols.size() - 1)] if not cols.is_empty() else UI.CYAN
		ci.draw_line(Vector2(x + 8.0, y + 38.0), Vector2(x + 24.0, y + 38.0), Color(cc.r, cc.g, cc.b, ta * 0.7), 2.0)
		ci.draw_string(font, Vector2(x - 24.0, y + 55.0), TOKEN_NAME.get(e, ""), HORIZONTAL_ALIGNMENT_CENTER, 80.0, 12, Color(0.70, 0.77, 0.82, ta))


## 卡外结局名（用户 10-26）：只在悬停 / 选中的那张卡真带路线时，在它下方写对应结局名（双路线两行）；切卡淡入淡出（alpha 由 choice_panel 平滑）
## cr：卡片在 ci 坐标里的矩形；y_min：不得高于此（避开操作说明行）；y_max：底边不超出画面
static func draw_route_names(ci: CanvasItem, cr: Rect2, ends: Array, alpha: float, font: Font, y_min: float, y_max: float, fs := 14) -> void:
	if alpha <= 0.01 or ends.is_empty():
		return
	var lh := float(fs) + 8.0
	var y: float = maxf(cr.end.y + 22.0, y_min)
	y = minf(y, y_max - lh * float(ends.size()))
	for q in ends.size():
		var e: String = str(ends[q])
		ci.draw_string(font, Vector2(cr.get_center().x - 170.0, y + lh * (q + 1) - 6.0), ROUTE_NAME.get(e, ""), HORIZONTAL_ALIGNMENT_CENTER, 340.0, fs, Color(0.80, 0.86, 0.90, alpha))


static func _ending_edge(ci: CanvasItem, r: Rect2, cols: Array, ends: Array, now: float, a: float, font: Font) -> void:
	var w := r.size.x
	var bw := P * 2.0
	if cols.size() == 1:
		step_line(ci, r.grow(-bw * 0.5), Color(cols[0].r, cols[0].g, cols[0].b, a), bw)
	else:
		var hw := w / 2.0
		for side in 2:
			var cc: Color = cols[side]
			var x0 := r.position.x + side * hw
			ci.draw_rect(Rect2(x0 + (P * STEPS if side == 0 else 0.0), r.position.y, hw - P * STEPS, bw), Color(cc.r, cc.g, cc.b, a))
			ci.draw_rect(Rect2(x0 + (P * STEPS if side == 0 else 0.0), r.end.y - bw, hw - P * STEPS, bw), Color(cc.r, cc.g, cc.b, a))
			ci.draw_rect(Rect2(r.position.x + side * (w - bw), r.position.y + P * STEPS, bw, r.size.y - 2.0 * P * STEPS), Color(cc.r, cc.g, cc.b, a))
	# 跑动高光：周长上一段 40 像素的亮段
	var per := 2.0 * (r.size.x + r.size.y)
	var s := fposmod(now * 160.0, per)
	for k in 10:
		var d := fposmod(s + k * 4.0, per)
		var p := Vector2.ZERO
		if d < w:
			p = Vector2(r.position.x + d, r.position.y)
		elif d < w + r.size.y:
			p = Vector2(r.end.x - bw, r.position.y + d - w)
		elif d < 2.0 * w + r.size.y:
			p = Vector2(r.end.x - (d - w - r.size.y), r.end.y - bw)
		else:
			p = Vector2(r.position.x, r.end.y - (d - 2.0 * w - r.size.y))
		ci.draw_rect(Rect2(p, Vector2(bw, bw)), Color(1, 1, 1, 0.08 * k * a))
	# 徽记：顶边中央暗底小牌，写通向的结局罗马数字
	var txt := " ".join(ends.map(func(e): return ROMAN.get(e, "")))
	var tw := float(maxi(1, ends.size())) * 30.0 + 18.0
	var tr := Rect2(Vector2(r.get_center().x - tw / 2.0, r.position.y + 8.0), Vector2(tw, 30.0))   # 放在卡内顶边：手机上卡片紧贴标题，跨边会压字
	ci.draw_colored_polygon(step_poly(tr, 2, 3.0), Color(0.02, 0.04, 0.07, 0.97 * a))
	for k in ends.size():
		var cc: Color = cols[mini(k, cols.size() - 1)]
		ci.draw_rect(Rect2(tr.position.x + 9.0 + k * 30.0, tr.end.y - 6.0, 30.0, 3.0), Color(cc.r, cc.g, cc.b, a))
		UI.ctext(ci, font, Vector2(tr.position.x + 9.0 + k * 30.0, tr.position.y + 21.0), ROMAN.get(ends[k], ""), 19, Color(cc.r, cc.g, cc.b, a), HORIZONTAL_ALIGNMENT_CENTER, 30.0)


## 正面：顶部类型色带（图标 + 节点名）、标题（衬线）、说明；正文自上而下显出，开头迸一圈像素颗粒
static func _face(ci: CanvasItem, r: Rect2, c: Dictionary, st: Dictionary, font: Font, serif: Font, col: Color, reveal: float, age: float) -> void:
	var poly := step_poly(r)
	ci.draw_colored_polygon(poly, Color(0.07, 0.085, 0.11, 0.98))
	var band := Rect2(r.position, Vector2(r.size.x, 92.0))
	ci.draw_rect(Rect2(band.position + Vector2(P * STEPS, 0), Vector2(band.size.x - 2.0 * P * STEPS, P * STEPS)), Color(col.r, col.g, col.b, 0.28))
	ci.draw_rect(Rect2(band.position + Vector2(0, P * STEPS), Vector2(band.size.x, band.size.y - P * STEPS)), Color(col.r, col.g, col.b, 0.16))
	ci.draw_rect(Rect2(band.position.x + 12.0, band.end.y - P, band.size.x - 24.0, P), Color(col.r, col.g, col.b, 0.8))
	step_line(ci, r.grow(-1.0), col, 2.0)
	NodeIcons.draw(ci, str(c.get("type", "")), Vector2(r.get_center().x, r.position.y + 38.0), 3.0, col)
	var sub: String = ("迷雾散去 · " if c.get("fog", false) else "") + str(NodeIcons.NAMES.get(str(c.get("type", "")), ""))
	var ph: bool = Cfg.phone_ui()   # 手机：小标 16、说明 18（整排缩 0.9，10-26 iPhone 实机可读下限，docs/37）
	UI.text(ci, font, Vector2(r.position.x, r.position.y + 78.0), sub, 16 if ph else 13, col, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	ci.draw_string(serif, Vector2(r.position.x, r.position.y + 136.0), str(st.get("face_title", "")), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 28, Color.WHITE)
	var tag: String = str(st.get("face_tag", ""))
	if tag != "":
		var ecs: Array = st.get("ends_cols", [])
		var tc: Color = ecs[0] if not ecs.is_empty() else UI.CYAN
		UI.text(ci, font, Vector2(r.position.x, r.position.y + 162.0), tag, 15 if ph else 12, tc, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	ci.draw_multiline_string(font, Vector2(r.position.x + (16.0 if ph else 24.0), r.position.y + 196.0), UI.soft(str(st.get("face_body", ""))), HORIZONTAL_ALIGNMENT_CENTER, r.size.x - (32.0 if ph else 48.0), 18 if ph else 14, 6, Color(0.81, 0.79, 0.76), UI.BRK)
	# 揭示遮罩：还没显出的部分盖回卡底色（按像素行）
	if reveal < 1.0:
		var y0 := r.position.y + 96.0 + (r.size.y - 110.0) * UM.out_cubic(reveal)
		ci.draw_rect(Rect2(r.position.x + 6.0, roundf(y0 / P) * P, r.size.x - 12.0, r.end.y - 8.0 - y0), Color(0.07, 0.085, 0.11, 1.0))
		ci.draw_rect(Rect2(r.position.x + 6.0, roundf(y0 / P) * P, r.size.x - 12.0, P), Color(col.r, col.g, col.b, 0.9))
	# 生效进度条（底部）
	var k := clampf((age - LIFT_T - FLIP_T) / 0.5, 0.0, 1.0)
	ci.draw_rect(Rect2(r.position.x + 20.0, r.end.y - 22.0, r.size.x - 40.0, P), Color(1, 1, 1, 0.08))
	ci.draw_rect(Rect2(r.position.x + 20.0, r.end.y - 22.0, (r.size.x - 40.0) * k, P), Color(col.r, col.g, col.b, 0.9))
	# 颗粒迸散（翻到正面后 0.5 秒内）
	var pa := age - LIFT_T - FLIP_T * 0.5
	if pa > 0.0 and pa < 0.6 and not UM.rm():
		var ctr := r.get_center() + Vector2(0, -60)
		for q in 28:
			var ang := _h(q, 1.0) * TAU
			var sp := 90.0 + 160.0 * _h(q, 2.0)
			var p := ctr + Vector2.from_angle(ang) * sp * UM.out_cubic(pa / 0.6)
			var s := P * (1.0 + float(int(_h(q, 3.0) * 2.0)))
			ci.draw_rect(Rect2(p.round(), Vector2(s, s)), Color(col.r, col.g, col.b, 1.0 - pa / 0.6))
