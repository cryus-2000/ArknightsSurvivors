extends RefCounted
## 新手引导提示卡里的实时小演示（docs/219 §3.5）：每张卡一段循环几秒的缩小版场景，画在 r 里，全由时间 t 算出（不碰随机数、不录视频）。
## 干员用真实待机帧条（choice_panel.op_idle + op_figure），怪 / 经验 / 灯油 / 灯标用局内同色的程序画法，指挥圆盘调真圆盘（command_wheel.draw_demo）。
## ctx：{g, font, touch, lead: 队长待机条, mates: [队友待机条 ×2]}；坐标一律按 r 的比例（0–1）给，换卡片大小自动跟着缩放。

const UI = preload("res://scripts/ui.gd")
const OpFigure = preload("res://scripts/screens/op_figure.gd")

const C_BG := Color(0.035, 0.055, 0.07)
const C_GRID := Color(0.4, 0.75, 0.8, 0.06)
const C_ENEMY := Color(0.36, 0.2, 0.48)
const C_ENEMY_HI := Color(0.55, 0.32, 0.7)
const C_EYE := Color(1.0, 0.42, 0.62)
const C_XP := Color(0.3, 0.95, 0.85)
const C_MIRE := Color(0.16, 0.05, 0.2)
const C_DEPLOY := Color(0.36, 0.78, 1.0)

## 每张卡一轮的秒数
const LOOP := {"move": 4.0, "xp": 4.8, "lamp": 5.2, "recruit": 5.0, "merchant": 5.0, "boss": 4.4, "squad": 4.0,
	"command": 8.0, "drill_end": 4.0, "ult": 4.4, "link": 4.2, "mire": 5.2, "nodes": 4.0}


static func draw(ci: CanvasItem, id: String, r: Rect2, t: float, ctx: Dictionary) -> void:
	var tl: float = fmod(t, float(LOOP.get(id, 4.0)))
	ci.draw_rect(r, C_BG)
	_grid(ci, r)
	match id:
		"move":
			_move(ci, r, tl, ctx)
		"xp":
			_xp(ci, r, tl, ctx)
		"lamp":
			_lamp(ci, r, tl, ctx)
		"recruit":
			_recruit(ci, r, tl, ctx)
		"merchant":
			_merchant(ci, r, tl, ctx)
		"boss":
			_boss(ci, r, tl, ctx)
		"squad", "drill_end":
			_squad(ci, r, tl, ctx)
		"command":
			_command(ci, r, tl, ctx)
		"ult":
			_ult(ci, r, tl, ctx)
		"link":
			_link(ci, r, tl, ctx)
		"mire":
			_mire(ci, r, tl, ctx)
		"nodes":
			_nodes(ci, r, tl, ctx)
	ci.draw_rect(r, Color(1, 1, 1, 0.14), false, 1.0)


# ---------------------------------------------------------------- 小工具

static func P(r: Rect2, x: float, y: float) -> Vector2:
	return r.position + Vector2(x * r.size.x, y * r.size.y)


static func ph(t: float, a: float, b: float) -> float:
	return clampf((t - a) / maxf(0.001, b - a), 0.0, 1.0)


static func _e(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)


static func _ca(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)


static func _grid(ci: CanvasItem, r: Rect2) -> void:
	var step: float = maxf(12.0, r.size.y / 6.0)
	var x: float = r.position.x + step
	while x < r.end.x:
		ci.draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), C_GRID, 1.0)
		x += step
	var y: float = r.position.y + step
	while y < r.end.y:
		ci.draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), C_GRID, 1.0)
		y += step


## 人物高度（屏幕像素）：场景高的 0.36
static func _h(r: Rect2) -> float:
	return r.size.y * 0.36


## 干员小人：脚底在 foot；没有帧条时画一个胶囊占位
static func fig(ci: CanvasItem, idle: Dictionary, foot: Vector2, r: Rect2, t: float, a := 1.0) -> void:
	var h: float = _h(r)
	ci.draw_circle(foot, h * 0.16, Color(0, 0, 0, 0.35 * a))
	if idle.is_empty():
		ci.draw_rect(Rect2(foot - Vector2(h * 0.15, h * 0.8), Vector2(h * 0.3, h * 0.8)), _ca(UI.CYAN, a))
		return
	var fr: int = int(t * 7.0) % maxi(1, int(idle.get("frames", 1)))
	OpFigure.draw(ci, idle, Rect2(foot - Vector2(h * 0.7, h), Vector2(h * 1.4, h)), fr, Color(1, 1, 1, a), -1.0, r)


static func blob(ci: CanvasItem, p: Vector2, s: float, a := 1.0, flash := 0.0) -> void:
	if a <= 0.01:
		return
	ci.draw_circle(p + Vector2(0, s * 0.55), s * 0.8, Color(0, 0, 0, 0.3 * a))
	ci.draw_circle(p, s, _ca(C_ENEMY.lerp(Color.WHITE, flash), a))
	ci.draw_circle(p + Vector2(-s * 0.15, -s * 0.2), s * 0.62, _ca(C_ENEMY_HI.lerp(Color.WHITE, flash), a))
	ci.draw_circle(p + Vector2(s * 0.3, -s * 0.25), s * 0.2, _ca(C_EYE, a))


static func key(ci: CanvasItem, font: Font, c: Vector2, s: float, label: String, lit: float) -> void:
	var w: float = maxf(s, font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(s * 0.55)).x + s * 0.5)
	var kr := Rect2(c - Vector2(w, s) / 2.0, Vector2(w, s))
	ci.draw_rect(kr, Color(0.06, 0.09, 0.11, 0.9).lerp(Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.95), lit))
	ci.draw_rect(kr, Color(1, 1, 1, 0.35 + 0.5 * lit), false, 1.0)
	var fsz := int(s * 0.55)
	var tw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
	ci.draw_string(font, Vector2(c.x - tw / 2.0, c.y + fsz * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, Color(0.04, 0.07, 0.09) if lit > 0.5 else UI.TEXT)


## 触屏圆按钮（冲刺 / 指挥 / 终结技）：按下时缩一下、亮起
static func tbtn(ci: CanvasItem, font: Font, c: Vector2, rad: float, label: String, lit: float, col := UI.CYAN) -> void:
	var rr: float = rad * (1.0 - 0.08 * lit)
	ci.draw_circle(c, rr, Color(0.05, 0.08, 0.1, 0.75).lerp(_ca(col, 0.85), lit))
	ci.draw_arc(c, rr, 0.0, TAU, 32, _ca(col, 0.5 + 0.5 * lit), 1.5)
	var fsz := int(rad * 0.62)
	var tw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
	ci.draw_string(font, Vector2(c.x - tw / 2.0, c.y + fsz * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, Color(0.04, 0.07, 0.09) if lit > 0.5 else UI.TEXT)
	if lit > 0.0:
		ci.draw_arc(c, rr + 3.0 + 6.0 * lit, 0.0, TAU, 32, _ca(col, 0.4 * (1.0 - lit)), 1.0)


## 手指（触屏点按）：半透明圆 + 按下时的波纹
static func finger(ci: CanvasItem, p: Vector2, s: float, press: float) -> void:
	ci.draw_circle(p, s * (1.0 - 0.15 * press), Color(1, 1, 1, 0.28 + 0.2 * press))
	ci.draw_arc(p, s, 0.0, TAU, 24, Color(1, 1, 1, 0.7), 1.5)
	if press > 0.0:
		ci.draw_arc(p, s * (1.2 + press), 0.0, TAU, 24, Color(1, 1, 1, 0.5 * (1.0 - press)), 1.0)


## 鼠标指针
static func cursor(ci: CanvasItem, p: Vector2, s: float) -> void:
	var pts := PackedVector2Array([p, p + Vector2(0, s), p + Vector2(s * 0.28, s * 0.74), p + Vector2(s * 0.68, s * 0.7)])
	ci.draw_colored_polygon(pts, Color(1, 1, 1, 0.95))
	ci.draw_polyline(pts + PackedVector2Array([p]), Color(0, 0, 0, 0.8), 1.0)


static func tag(ci: CanvasItem, font: Font, p: Vector2, s: String, col: Color, fsz: int, a := 1.0) -> void:
	if a <= 0.01:
		return
	var w: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x + 10.0
	ci.draw_rect(Rect2(p, Vector2(w, fsz + 8)), Color(0.02, 0.03, 0.04, 0.8 * a))
	ci.draw_rect(Rect2(p, Vector2(3, fsz + 8)), _ca(col, a))
	ci.draw_string(font, p + Vector2(7, fsz + 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, _ca(UI.TEXT, a))


static func _fsz(r: Rect2) -> int:
	return clampi(int(r.size.y * 0.085), 9, 20)


## 子弹：from → to，frac 0–1
static func bullet(ci: CanvasItem, a: Vector2, b: Vector2, frac: float, col := UI.CYAN) -> void:
	if frac <= 0.0 or frac >= 1.0:
		return
	var p: Vector2 = a.lerp(b, frac)
	var d: Vector2 = (b - a).normalized()
	ci.draw_line(p - d * 7.0, p, _ca(col, 0.6), 2.0)
	ci.draw_circle(p, 2.2, col)


static func light(ci: CanvasItem, c: Vector2, rad: float, a: float) -> void:
	for i in 4:
		ci.draw_circle(c, rad * (1.0 - i * 0.2), Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.035 * a))


# ---------------------------------------------------------------- 各卡

## 移动：队长走「8」字，键帽按方向亮（触屏：左下摇杆）；怪从右边过来，子弹自动打出去
static func _move(ci: CanvasItem, r: Rect2, t: float, ctx: Dictionary) -> void:
	var w: float = TAU * t / 4.0
	var lp := P(r, 0.4 + 0.16 * sin(w), 0.66 + 0.09 * sin(2.0 * w))
	var dir := Vector2(cos(w) * 0.16, cos(2.0 * w) * 0.18)
	light(ci, lp, r.size.y * 0.42, 1.0)
	# 怪：三只轮流从右边进场，走到一半被打掉
	var best := Vector2.INF
	var best_ph := -1.0
	for i in 3:
		var p: float = fmod(t / 4.0 + i / 3.0, 1.0)
		var ep := P(r, lerpf(0.95, 0.7, p), 0.22 + 0.14 * i)
		var dead: float = ph(p, 0.78, 0.9)
		blob(ci, ep, r.size.y * 0.065, (1.0 - dead) * ph(p, 0.0, 0.12), dead)   # 框内淡入，不画出演示框
		if dead <= 0.0 and p > best_ph:
			best_ph = p
			best = ep
	if best != Vector2.INF:
		for k in 2:
			bullet(ci, lp + Vector2(0, -_h(r) * 0.5), best, fmod(t * 2.5 + k * 0.5, 1.0))
	fig(ci, ctx.lead, lp, r, t)
	var font: Font = ctx.font
	var ks: float = r.size.y * 0.15
	if ctx.touch:
		var c := P(r, 0.14, 0.74)
		var rad: float = r.size.y * 0.15
		ci.draw_circle(c, rad, Color(1, 1, 1, 0.08))
		ci.draw_arc(c, rad, 0.0, TAU, 32, Color(1, 1, 1, 0.35), 1.5)
		var kn: Vector2 = c + dir.normalized() * rad * 0.55 * clampf(dir.length() * 6.0, 0.0, 1.0)
		ci.draw_circle(kn, rad * 0.45, Color(1, 1, 1, 0.4))
		finger(ci, kn, rad * 0.32, 0.0)
	else:
		var c := P(r, 0.86, 0.76)
		key(ci, font, c + Vector2(0, -ks * 1.1), ks, "W", 1.0 if dir.y < -0.05 else 0.0)
		key(ci, font, c + Vector2(-ks * 1.1, 0), ks, "A", 1.0 if dir.x < -0.05 else 0.0)
		key(ci, font, c, ks, "S", 1.0 if dir.y > 0.05 else 0.0)
		key(ci, font, c + Vector2(ks * 1.1, 0), ks, "D", 1.0 if dir.x > 0.05 else 0.0)
	tag(ci, font, P(r, 0.03, 0.05), "自动攻击", UI.CYAN, _fsz(r), 0.9)


## 经验与升级：走过结晶被吸过来 → 经验条涨满 → 三张卡弹出，选中中间一张
static func _xp(ci: CanvasItem, r: Rect2, t: float, ctx: Dictionary) -> void:
	var lx: float = lerpf(0.12, 0.82, _e(ph(t, 0.1, 2.7)))
	var lp := P(r, lx, 0.66)
	light(ci, lp, r.size.y * 0.42, 1.0)
	var got := 0
	for i in 7:
		var cx: float = 0.24 + i * 0.09
		var cy: float = 0.5 + 0.16 * sin(i * 2.1)
		var q: float = clampf((cx - 0.24) / 0.7, 0.0, 1.0)
		var hit_t: float = 0.1 + 2.6 * (1.0 - pow(1.0 - q, 1.0 / 3.0))   # 队长走到 cx - 0.12（磁吸半径）的时刻：反解 _e
		var f: float = ph(t, hit_t, hit_t + 0.25)
		if f >= 1.0:
			got += 1
			continue
		var cp: Vector2 = P(r, cx, cy).lerp(lp + Vector2(0, -_h(r) * 0.4), _e(f))
		var s: float = r.size.y * 0.035
		ci.draw_colored_polygon(PackedVector2Array([cp + Vector2(0, -s * 1.4), cp + Vector2(s, 0), cp + Vector2(0, s * 1.4), cp + Vector2(-s, 0)]), C_XP)
	fig(ci, ctx.lead, lp, r, t)
	# 经验条（场景顶部）
	var full: float = got / 7.0
	var br := Rect2(r.position + Vector2(6, 6), Vector2(r.size.x - 12, 4))
	ci.draw_rect(br, Color(1, 1, 1, 0.1))
	ci.draw_rect(Rect2(br.position, Vector2(br.size.x * full, br.size.y)), C_XP.lerp(Color.WHITE, ph(t, 2.7, 2.9) * (1.0 - ph(t, 2.9, 3.3))))
	# 三选一
	var ca: float = ph(t, 2.9, 3.2) * (1.0 - ph(t, 4.5, 4.8))
	if ca > 0.0:
		ci.draw_rect(r, Color(0, 0, 0, 0.45 * ca))
		var cw: float = r.size.x * 0.22
		var chh: float = r.size.y * 0.52
		var sel: float = ph(t, 3.7, 3.85)
		for i in 3:
			var rise: float = (1.0 - _e(ph(t, 2.95 + i * 0.08, 3.3 + i * 0.08))) * r.size.y * 0.3
			var lift: float = (sel * r.size.y * 0.05) if i == 1 else 0.0
			var cr := Rect2(P(r, 0.5, 0.5) + Vector2((i - 1) * cw * 1.15 - cw / 2.0, -chh / 2.0 + rise - lift), Vector2(cw, chh))
			var dim: float = (ph(t, 4.0, 4.3) * 0.6) if i != 1 else 0.0
			ci.draw_rect(cr, Color(0.09, 0.11, 0.13, 0.95 * ca * (1.0 - dim)))
			ci.draw_rect(Rect2(cr.position, Vector2(cr.size.x, 3)), _ca([UI.GOLD, UI.CYAN, UI.RED][i], ca * (1.0 - dim)))
			ci.draw_circle(cr.position + Vector2(cw / 2.0, chh * 0.36), cw * 0.18, _ca([UI.GOLD, UI.CYAN, UI.RED][i], 0.7 * ca * (1.0 - dim)))
			for k in 2:
				ci.draw_rect(Rect2(cr.position + Vector2(cw * 0.18, chh * (0.62 + k * 0.13)), Vector2(cw * (0.64 - k * 0.2), 2.0)), Color(1, 1, 1, 0.3 * ca * (1.0 - dim)))
			if i == 1 and sel > 0.0:
				ci.draw_rect(cr.grow(2.0), _ca(UI.CYAN, sel * ca), false, 2.0)
		if ctx.touch:
			finger(ci, P(r, 0.5, 0.55), r.size.y * 0.07, ph(t, 3.6, 3.85))
		else:
			cursor(ci, P(r, 0.5, 0.5) + Vector2(4, 6) * (1.0 - ph(t, 3.3, 3.6)) * 6.0, r.size.y * 0.12)
		tag(ci, ctx.font, P(r, 0.03, 0.08), "升级！三选一", UI.CYAN, _fsz(r), ca)


## 灯火：怪撞上来，灯火掉一截、光圈缩小、画面变暗 → 拾取灯油，灯火回满
static func _lamp(ci: CanvasItem, r: Rect2, t: float, ctx: Dictionary) -> void:
	var hit: float = ph(t, 0.9, 1.05)
	var refill: float = ph(t, 3.4, 3.8)
	var lamp: float = lerpf(lerpf(0.85, 0.32, hit), 1.0, refill)
	var lx: float = lerpf(0.36, 0.74, _e(ph(t, 1.7, 3.35)))
	var lp := P(r, lx, 0.66)
	ci.draw_rect(r, Color(0, 0, 0, 0.35 * (1.0 - lamp)))
	light(ci, lp, r.size.y * (0.22 + 0.32 * lamp), 0.6 + lamp)
	# 灯油
	if refill <= 0.0:
		var op := P(r, 0.78, 0.66)
		var s: float = r.size.y * 0.05
		ci.draw_circle(op, s * 2.2, Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.12 + 0.08 * sin(t * 6.0)))
		ci.draw_rect(Rect2(op - Vector2(s * 0.7, s * 1.6), Vector2(s * 1.4, s * 1.8)), UI.GOLD)
		ci.draw_rect(Rect2(op - Vector2(s * 0.35, s * 2.0), Vector2(s * 0.7, s * 0.45)), UI.GOLD.darkened(0.3))
	else:
		ci.draw_arc(lp + Vector2(0, -_h(r) * 0.4), r.size.y * (0.08 + 0.3 * refill), 0.0, TAU, 32, _ca(UI.GOLD, 1.0 - refill), 2.0)
		if refill < 1.0:
			ci.draw_string(ctx.font, lp + Vector2(10, -_h(r) - 6.0 - 12.0 * refill), "灯火 +50", HORIZONTAL_ALIGNMENT_LEFT, -1, _fsz(r), _ca(UI.GOLD, 1.0 - refill * 0.6))
	# 怪：撞上来再被弹开
	var ep: Vector2 = P(r, lerpf(0.95, 0.42, _e(ph(t, 0.2, 0.9))), 0.62).lerp(P(r, 0.7, 0.4), ph(t, 0.95, 1.4))
	blob(ci, ep, r.size.y * 0.07, 1.0 - ph(t, 1.2, 1.5), ph(t, 0.9, 1.0) * (1.0 - ph(t, 1.0, 1.2)))
	fig(ci, ctx.lead, lp, r, t, 1.0)
	if hit > 0.0 and hit < 1.0:
		ci.draw_rect(r, Color(1.0, 0.24, 0.4, 0.18 * (1.0 - hit)))
	# 灯火条
	var br := Rect2(r.position + Vector2(8, 8), Vector2(r.size.x * 0.4, 7))
	ci.draw_rect(br, Color(0, 0, 0, 0.6))
	ci.draw_rect(Rect2(br.position, Vector2(br.size.x * lamp, br.size.y)), UI.GOLD.lerp(UI.RED, clampf((0.4 - lamp) * 4.0, 0.0, 1.0)))
	ci.draw_rect(br, Color(1, 1, 1, 0.3), false, 1.0)
	ci.draw_string(ctx.font, br.position + Vector2(br.size.x + 6, 8), "灯火", HORIZONTAL_ALIGNMENT_LEFT, -1, _fsz(r), UI.GOLD)


## 招募：三选一里出现干员卡 → 选中 → 干员落到队长身边，一起开火
static func _recruit(ci: CanvasItem, r: Rect2, t: float, ctx: Dictionary) -> void:
	var lp := P(r, 0.4, 0.68)
	var mp := P(r, 0.24, 0.6)
	light(ci, lp, r.size.y * 0.42, 1.0)
	var mate: Dictionary = ctx.mates[0] if not (ctx.mates as Array).is_empty() else {}
	var drop: float = ph(t, 2.0, 2.4)
	if drop > 0.0:
		var p: Vector2 = mp + Vector2(0, -r.size.y * 0.8 * (1.0 - _e(drop)))
		fig(ci, mate, p, r, t)
		if drop >= 1.0:
			ci.draw_arc(mp, r.size.y * (0.05 + 0.2 * ph(t, 2.4, 2.8)), 0.0, TAU, 24, _ca(UI.CYAN, 1.0 - ph(t, 2.4, 2.8)), 1.5)
			var ep := P(r, 0.86, 0.45)
			blob(ci, ep, r.size.y * 0.065, 1.0)
			for k in 2:
				bullet(ci, mp + Vector2(0, -_h(r) * 0.5), ep, fmod((t - 2.6) * 2.0 + k * 0.5, 1.0) if t > 2.6 else 0.0)
	fig(ci, ctx.lead, lp, r, t)
	var ca: float = ph(t, 0.2, 0.5) * (1.0 - ph(t, 1.8, 2.0))
	if ca > 0.0:
		ci.draw_rect(r, Color(0, 0, 0, 0.5 * ca))
		var cw: float = r.size.x * 0.22
		var chh: float = r.size.y * 0.6
		var sel: float = ph(t, 1.1, 1.25)
		for i in 3:
			var cr := Rect2(P(r, 0.5, 0.5) + Vector2((i - 1) * cw * 1.15 - cw / 2.0, -chh / 2.0 - ((sel * r.size.y * 0.05) if i == 1 else 0.0)), Vector2(cw, chh))
			ci.draw_rect(cr, Color(0.09, 0.11, 0.13, 0.95 * ca))
			ci.draw_rect(Rect2(cr.position, Vector2(cr.size.x, 3)), _ca(UI.CYAN if i == 1 else UI.GOLD, ca))
			if i == 1:
				fig(ci, mate, cr.position + Vector2(cw / 2.0, chh * 0.78), Rect2(cr.position, Vector2(cw, chh)).grow(-2.0), t, ca)
				ci.draw_string(ctx.font, cr.position + Vector2(4, chh - 4), "招募", HORIZONTAL_ALIGNMENT_LEFT, -1, _fsz(r), _ca(UI.CYAN, ca))
				if sel > 0.0:
					ci.draw_rect(cr.grow(2.0), _ca(UI.CYAN, sel * ca), false, 2.0)
			else:
				ci.draw_circle(cr.position + Vector2(cw / 2.0, chh * 0.4), cw * 0.18, _ca(UI.GOLD, 0.6 * ca))
		if ctx.touch:
			finger(ci, P(r, 0.5, 0.55), r.size.y * 0.07, ph(t, 1.0, 1.25))
		else:
			cursor(ci, P(r, 0.5, 0.5) + Vector2(1, 1) * (1.0 - ph(t, 0.6, 1.0)) * r.size.y * 0.25, r.size.y * 0.12)


## 商人：边缘的金色箭头 → 顺着走 → 商人和 60 秒倒计时
static func _merchant(ci: CanvasItem, r: Rect2, t: float, ctx: Dictionary) -> void:
	var lx: float = lerpf(0.18, 0.55, _e(ph(t, 0.3, 2.8)))
	var lp := P(r, lx, 0.66)
	var mx: float = lerpf(1.12, 0.76, _e(ph(t, 1.2, 2.6)))
	var mpos := P(r, mx, 0.62)
	light(ci, lp, r.size.y * 0.42, 1.0)
	# 商人：暖光 + 斗篷剪影 + 货箱
	ci.draw_circle(mpos + Vector2(0, -_h(r) * 0.4), r.size.y * 0.22, Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.1))
	var h: float = _h(r)
	ci.draw_colored_polygon(PackedVector2Array([mpos + Vector2(-h * 0.28, 0), mpos + Vector2(h * 0.28, 0), mpos + Vector2(h * 0.14, -h * 0.75), mpos + Vector2(0, -h * 0.95), mpos + Vector2(-h * 0.14, -h * 0.75)]), Color(0.32, 0.22, 0.16))
	ci.draw_rect(Rect2(mpos + Vector2(-h * 0.62, -h * 0.3), Vector2(h * 0.34, h * 0.3)), Color(0.55, 0.38, 0.2))
	ci.draw_circle(mpos + Vector2(h * 0.3, -h * 0.45), h * 0.07, UI.GOLD)
	var secs: int = 60 - int(ph(t, 2.6, 5.0) * 3.0)
	if t > 2.0:
		ci.draw_string(ctx.font, mpos + Vector2(-h * 0.2, -h * 1.08), "%d 秒" % secs, HORIZONTAL_ALIGNMENT_LEFT, -1, _fsz(r), _ca(UI.GOLD, ph(t, 2.0, 2.3)))
	fig(ci, ctx.lead, lp, r, t)
	# 金色箭头：商人在画外时贴右边缘
	var aa: float = 1.0 - ph(t, 1.9, 2.3)
	if aa > 0.0:
		var ac := P(r, 0.93, 0.62) + Vector2(sin(t * 8.0) * 3.0, 0)
		var s: float = r.size.y * 0.08
		ci.draw_colored_polygon(PackedVector2Array([ac + Vector2(s, 0), ac + Vector2(-s * 0.6, -s * 0.8), ac + Vector2(-s * 0.6, s * 0.8)]), _ca(UI.GOLD, aa))
	# 货架
	var sa: float = ph(t, 3.2, 3.5)
	if sa > 0.0:
		var sr := Rect2(P(r, 0.22, 0.12), Vector2(r.size.x * 0.5, r.size.y * 0.3))
		ci.draw_rect(sr, Color(0.06, 0.07, 0.09, 0.92 * sa))
		ci.draw_rect(Rect2(sr.position, Vector2(3, sr.size.y)), _ca(UI.GOLD, sa))
		for i in 3:
			var cr := Rect2(sr.position + Vector2(10 + i * sr.size.x * 0.3, 8), Vector2(sr.size.x * 0.25, sr.size.y - 16))
			ci.draw_rect(cr, Color(1, 1, 1, 0.08 * sa))
			ci.draw_circle(cr.get_center() + Vector2(0, -cr.size.y * 0.12), cr.size.y * 0.18, _ca(UI.GOLD, 0.6 * sa))


## Boss：预警圈慢慢扩大 → 冲刺（残影）躲出圈外 → 圈里爆开
static func _boss(ci: CanvasItem, r: Rect2, t: float, ctx: Dictionary) -> void:
	var c0 := P(r, 0.42, 0.68)
	var dash: float = _e(ph(t, 1.6, 1.85))
	var lp: Vector2 = c0.lerp(P(r, 0.13, 0.7), dash)
	var bp := P(r, 0.8, 0.36)
	var bs: float = r.size.y * 0.14
	blob(ci, bp, bs, 1.0, 0.0)
	for i in 3:
		var a: float = -PI / 2.0 + (i - 1) * 0.5
		ci.draw_colored_polygon(PackedVector2Array([bp + Vector2.from_angle(a - 0.15) * bs * 0.8, bp + Vector2.from_angle(a) * bs * 1.45, bp + Vector2.from_angle(a + 0.15) * bs * 0.8]), UI.RED)
	var grow: float = ph(t, 0.3, 1.9)
	var rad: float = r.size.y * 0.26 * _e(grow)
	var boom: float = ph(t, 2.0, 2.4)
	if grow > 0.0 and boom < 1.0:
		ci.draw_circle(c0, rad, Color(UI.RED.r, UI.RED.g, UI.RED.b, 0.12 + 0.1 * grow) if boom <= 0.0 else Color(1, 0.9, 0.9, 0.6 * (1.0 - boom)))
		ci.draw_arc(c0, r.size.y * 0.26, 0.0, TAU, 40, _ca(UI.RED, 0.8 * (1.0 - boom)), 1.5)
	light(ci, lp, r.size.y * 0.34, 1.0)
	if dash > 0.0 and dash < 1.0:
		for k in 3:
			fig(ci, ctx.lead, c0.lerp(lp, k / 3.0), r, t, 0.25)
	fig(ci, ctx.lead, lp, r, t)
	var lit: float = 1.0 if t > 1.5 and t < 1.9 else 0.0
	if ctx.touch:
		tbtn(ci, ctx.font, P(r, 0.86, 0.76), r.size.y * 0.11, "冲刺", lit)
	else:
		key(ci, ctx.font, P(r, 0.84, 0.82), r.size.y * 0.15, "空格", lit)


## 小队与队长：队长头顶「队长」标，队友跟在身后自动开火
static func _squad(ci: CanvasItem, r: Rect2, t: float, ctx: Dictionary) -> void:
	var sway: float = sin(TAU * t / 4.0) * 0.04
	var lp := P(r, 0.42 + sway, 0.66)
	light(ci, lp, r.size.y * 0.45, 1.0)
	var ep := P(r, 0.86, 0.42)
	blob(ci, ep, r.size.y * 0.07, 1.0)
	var mates: Array = ctx.mates
	var offs := [Vector2(-0.16, -0.12), Vector2(-0.18, 0.1)]
	for i in mini(2, mates.size()):
		var mp: Vector2 = lp + Vector2(offs[i].x * r.size.x, offs[i].y * r.size.y) + Vector2(0, sin(t * 3.0 + i) * 2.0)
		fig(ci, mates[i], mp, r, t + i * 0.3)
		bullet(ci, mp + Vector2(0, -_h(r) * 0.5), ep, fmod(t * 2.0 + i * 0.5, 1.0))
	fig(ci, ctx.lead, lp, r, t)
	UI.ctag(ci, ctx.font, lp + Vector2(-_h(r) * 0.4, -_h(r) - 20.0), "队长", _fsz(r), true, 1.0)


## 指挥圆盘：① 开圆盘选「突击」→ ② 队友冲出去 → ③ 再开圆盘选「部署」、点落点 → ④ 队友落位挡住怪群（各约 2 秒）
static func _command(ci: CanvasItem, r: Rect2, t: float, ctx: Dictionary) -> void:
	var g = ctx.g
	var font: Font = ctx.font
	var lp := P(r, 0.24, 0.66)
	var home := [P(r, 0.14, 0.52), P(r, 0.12, 0.8)]
	var front := [P(r, 0.66, 0.44), P(r, 0.66, 0.74)]
	var dep := P(r, 0.52, 0.62)
	var deps := [P(r, 0.52, 0.48), P(r, 0.52, 0.76)]
	light(ci, lp, r.size.y * 0.42, 1.0)
	# 队友位置
	var mpos: Array = []
	for i in 2:
		var p: Vector2 = home[i]
		if t >= 2.0 and t < 4.4:
			p = home[i].lerp(front[i], _e(ph(t, 2.05, 2.5))).lerp(home[i], _e(ph(t, 4.0, 4.4)))
		elif t >= 5.8:
			p = home[i].lerp(deps[i], _e(ph(t, 5.8, 6.4)))
		mpos.append(p)
	# 怪：② 段在右边被打掉；④ 段从右边涌来，停在阻挡线前
	if t < 4.4:
		for i in 4:
			var ep := P(r, 0.78 + 0.08 * (i % 2), 0.38 + 0.14 * i)
			var dead: float = ph(t, 2.6 + i * 0.3, 2.85 + i * 0.3)
			blob(ci, ep, r.size.y * 0.06, 1.0 - dead, dead)
	else:
		var line_x: float = 0.6
		for i in 5:
			var p0: float = ph(t, 5.6 + i * 0.12, 7.0 + i * 0.12)
			var ex: float = maxf(lerpf(0.94, 0.45, p0), line_x + 0.03 * (i % 3))
			blob(ci, P(r, ex, 0.42 + 0.09 * i), r.size.y * 0.055, ph(t, 4.4, 4.8), 0.0)
		if t >= 6.2:
			var la: float = ph(t, 6.2, 6.5)
			ci.draw_line(P(r, line_x - 0.02, 0.36), P(r, line_x - 0.02, 0.86), _ca(C_DEPLOY, 0.55 * la), 2.0)
	# 部署落点标记
	if t >= 5.65:
		var ma: float = ph(t, 5.65, 5.85)
		ci.draw_arc(dep, r.size.y * (0.16 - 0.06 * ma), 0.0, TAU, 32, _ca(C_DEPLOY, ma), 2.0)
		ci.draw_circle(dep, 3.0, _ca(C_DEPLOY, ma))
	# 突击冲刺拖影 + 斩击
	for i in 2:
		if t > 2.05 and t < 2.5:
			ci.draw_line(home[i], mpos[i], _ca(UI.GOLD, 0.5), 3.0)
		if t > 2.6 and t < 4.0:
			var sl: float = fmod((t - 2.6) * 2.2 + i * 0.5, 1.0)
			ci.draw_arc(mpos[i] + Vector2(_h(r) * 0.35, -_h(r) * 0.4), _h(r) * 0.35, -1.2 + sl * 1.6, -0.4 + sl * 1.6, 10, _ca(UI.GOLD, 1.0 - sl), 2.0)
		fig(ci, ctx.mates[i] if i < (ctx.mates as Array).size() else {}, mpos[i], r, t + i * 0.3)
	fig(ci, ctx.lead, lp, r, t)
	# 圆盘（两次）
	var wc := r.get_center()
	var k: float = r.size.y / (2.0 * 196.0 + 90.0)
	var wheel_on := false
	if g != null and g.get("wheel") != null:
		var roam: int = g.wheel.item_index("roam")
		var point: int = g.wheel.item_index("point")
		if point < 0:
			point = g.wheel.item_index("recall")
		for seg in [[0.3, 0.95, 1.65, roam], [4.1, 4.65, 5.15, point]]:
			var t0: float = seg[0]
			if t >= t0 and t < seg[2] + 0.25:
				wheel_on = true
				ci.draw_rect(r, Color(0, 0, 0, 0.35 * (1.0 - ph(t, seg[2], seg[2] + 0.25))))
				var hov: int = int(seg[3]) if t >= seg[1] else -1
				g.wheel.draw_demo(wc, k, t - t0, hov, t - seg[1] if t >= seg[1] else 0.0, ph(t, seg[2], seg[2] + 0.25))
				# 指针 / 手指移向选项
				var ang: float = deg_to_rad(float(g.wheel.ANG[int(seg[3])])) if int(seg[3]) >= 0 else 0.0
				var tgt: Vector2 = wc + Vector2.from_angle(ang) * (70.0 + 196.0) * 0.5 * k
				var pp: Vector2 = wc.lerp(tgt, _e(ph(t, t0 + 0.25, seg[1])))
				if ctx.touch:
					finger(ci, pp, r.size.y * 0.06, ph(t, seg[2] - 0.2, seg[2]))
				else:
					cursor(ci, pp, r.size.y * 0.11)
	# 部署：选完后指针移到落点点一下
	if not wheel_on and t >= 5.3 and t < 6.0:
		var pp: Vector2 = wc.lerp(dep, _e(ph(t, 5.3, 5.6)))
		if ctx.touch:
			finger(ci, pp, r.size.y * 0.06, ph(t, 5.55, 5.7))
		else:
			cursor(ci, pp, r.size.y * 0.11)
	# 指挥键（每次开圆盘前按一下）
	var lit: float = 1.0 if (t >= 0.05 and t < 0.35) or (t >= 3.85 and t < 4.15) else 0.0
	if ctx.touch:
		tbtn(ci, font, P(r, 0.9, 0.8), r.size.y * 0.1, "指挥", lit)
	else:
		key(ci, font, P(r, 0.92, 0.84), r.size.y * 0.15, "F", lit)
	# 段落标签
	var labels := [["① 打开圆盘，选「突击」", 0.0, 2.0, UI.GOLD], ["② 突击：队友冲出去", 2.0, 4.0, UI.GOLD], ["③ 选「部署」，点落点", 4.0, 6.0, C_DEPLOY], ["④ 部署：队友挡住敌人", 6.0, 8.0, C_DEPLOY]]
	for lb in labels:
		if t >= lb[1] and t < lb[2]:
			tag(ci, font, P(r, 0.03, 0.05), lb[0], lb[3], _fsz(r), ph(t, lb[1], lb[1] + 0.15) * (1.0 - ph(t, lb[2] - 0.15, lb[2])))


## 终结技：按住 Q，地面出现范围 → 松开，闪白冲击，圈里的怪倒下
static func _ult(ci: CanvasItem, r: Rect2, t: float, ctx: Dictionary) -> void:
	var lp := P(r, 0.24, 0.68)
	var c := P(r, 0.62, 0.56)
	light(ci, lp, r.size.y * 0.4, 1.0)
	var hold: float = ph(t, 0.4, 1.2)
	var rel: float = ph(t, 2.0, 2.6)
	for i in 6:
		var a: float = i * TAU / 6.0 + 0.3
		var ep: Vector2 = c + Vector2.from_angle(a) * r.size.y * (0.1 + 0.08 * (i % 2))
		blob(ci, ep, r.size.y * 0.05, 1.0 - ph(t, 2.05, 2.3), ph(t, 2.0, 2.1))
	if t >= 0.4 and t < 2.0:
		var rad: float = r.size.y * 0.3 * _e(hold)
		ci.draw_circle(c, rad, Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.12))
		ci.draw_arc(c, rad, t * 1.5, t * 1.5 + TAU, 40, _ca(UI.GOLD, 0.9), 2.0)
		ci.draw_line(lp + Vector2(0, -_h(r) * 0.4), c, _ca(UI.GOLD, 0.35), 1.0)
	if rel > 0.0 and rel < 1.0:
		ci.draw_arc(c, r.size.y * (0.3 + 0.4 * rel), 0.0, TAU, 40, _ca(Color.WHITE, 1.0 - rel), 3.0)
	fig(ci, ctx.lead, lp, r, t)
	if rel > 0.0 and rel < 1.0:
		ci.draw_rect(r, Color(1, 1, 1, 0.55 * (1.0 - _e(rel))))
	var lit: float = 1.0 if t >= 0.4 and t < 2.0 else 0.0
	if ctx.touch:
		tbtn(ci, ctx.font, P(r, 0.88, 0.78), r.size.y * 0.12, "终结", lit, UI.GOLD)
	else:
		key(ci, ctx.font, P(r, 0.9, 0.84), r.size.y * 0.15, "Q", lit)
	tag(ci, ctx.font, P(r, 0.03, 0.05), "按住：看范围" if t < 2.0 else "松开：释放", UI.GOLD, _fsz(r), 0.9)


## 连携：队长放技能（光环）→ 队友头像亮起 → 队友接一招
static func _link(ci: CanvasItem, r: Rect2, t: float, ctx: Dictionary) -> void:
	var lp := P(r, 0.3, 0.68)
	var mp0 := P(r, 0.16, 0.55)
	var ep := P(r, 0.74, 0.5)
	light(ci, lp, r.size.y * 0.42, 1.0)
	var cast: float = ph(t, 0.5, 1.0)
	if cast > 0.0 and cast < 1.0:
		ci.draw_arc(lp + Vector2(0, -_h(r) * 0.3), r.size.y * (0.08 + 0.25 * cast), 0.0, TAU, 32, _ca(UI.PURPLE, 1.0 - cast), 2.5)
	var go: float = _e(ph(t, 1.2, 1.5))
	var back: float = _e(ph(t, 2.4, 2.9))
	var mp: Vector2 = mp0.lerp(ep + Vector2(-r.size.y * 0.16, r.size.y * 0.12), go).lerp(mp0, back)
	blob(ci, ep, r.size.y * 0.09, 1.0 - ph(t, 1.9, 2.2), ph(t, 1.5, 1.6))
	if go > 0.0 and back < 1.0:
		var sl: float = ph(t, 1.5, 1.9)
		if sl > 0.0 and sl < 1.0:
			ci.draw_arc(ep, r.size.y * 0.14, -2.0 + sl * 2.5, -0.8 + sl * 2.5, 12, _ca(UI.CYAN, 1.0 - sl), 3.0)
	var mate: Dictionary = ctx.mates[0] if not (ctx.mates as Array).is_empty() else {}
	fig(ci, mate, mp, r, t)
	fig(ci, ctx.lead, lp, r, t)
	# 队友头像（右上角）：亮起 → 出手
	var hc := P(r, 0.9, 0.18)
	var lit: float = ph(t, 0.9, 1.1) * (1.0 - ph(t, 1.6, 2.0))
	ci.draw_circle(hc, r.size.y * 0.09, Color(0.06, 0.09, 0.11, 0.9))
	ci.draw_arc(hc, r.size.y * 0.09, 0.0, TAU, 28, _ca(UI.CYAN, 0.35 + 0.65 * lit), 2.0)
	if lit > 0.0:
		ci.draw_arc(hc, r.size.y * (0.1 + 0.04 * lit), 0.0, TAU, 28, _ca(UI.CYAN, 0.6 * lit), 1.0)
	fig(ci, mate, hc + Vector2(0, r.size.y * 0.08), Rect2(hc - Vector2.ONE * r.size.y * 0.085, Vector2.ONE * r.size.y * 0.17), t)
	tag(ci, ctx.font, P(r, 0.03, 0.05), "连携", UI.CYAN, _fsz(r), ph(t, 1.2, 1.4) * (1.0 - ph(t, 3.4, 3.8)))


## 溟痕与引航灯标：溟痕铺地 → 站到灯标旁读条 → 灯标亮起，溟痕退散
static func _mire(ci: CanvasItem, r: Rect2, t: float, ctx: Dictionary) -> void:
	var clear: float = _e(ph(t, 3.0, 4.2))
	var spots := [[0.3, 0.5, 0.2], [0.7, 0.72, 0.22], [0.82, 0.4, 0.16], [0.18, 0.82, 0.15], [0.55, 0.85, 0.14]]
	for s in spots:
		var rad: float = r.size.y * float(s[2]) * (1.0 - clear)
		if rad > 1.0:
			ci.draw_circle(P(r, s[0], s[1]), rad, Color(C_MIRE.r, C_MIRE.g, C_MIRE.b, 0.85))
			ci.draw_arc(P(r, s[0], s[1]), rad, 0.0, TAU, 28, Color(0.55, 0.25, 0.7, 0.35), 1.0)
	var bc := P(r, 0.58, 0.58)
	var lit: float = ph(t, 3.0, 3.3)
	if lit > 0.0:
		ci.draw_circle(bc + Vector2(0, -_h(r) * 0.8), r.size.y * (0.1 + 0.5 * clear), Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.12 * lit))
	# 灯标：柱 + 灯头
	ci.draw_rect(Rect2(bc + Vector2(-2, -_h(r) * 0.8), Vector2(4, _h(r) * 0.8)), Color(0.5, 0.55, 0.6))
	ci.draw_circle(bc + Vector2(0, -_h(r) * 0.85), r.size.y * 0.05, Color(0.3, 0.32, 0.35).lerp(UI.GOLD, lit))
	var lp: Vector2 = P(r, 0.16, 0.7).lerp(P(r, 0.47, 0.66), _e(ph(t, 0.1, 1.2)))
	var prog: float = ph(t, 1.2, 3.0)
	if prog > 0.0 and lit < 1.0:
		ci.draw_arc(bc + Vector2(0, -_h(r) * 0.85), r.size.y * 0.1, -PI / 2.0, -PI / 2.0 + TAU * prog, 32, UI.GOLD, 2.5)
	light(ci, lp, r.size.y * 0.3, 0.8)
	fig(ci, ctx.lead, lp, r, t)
	tag(ci, ctx.font, P(r, 0.03, 0.05), "点燃引航灯标" if lit < 1.0 else "溟痕退散", UI.GOLD, _fsz(r), 0.9)


## 节点卡：三张卡背 → 选中一张抬起 → 翻开
static func _nodes(ci: CanvasItem, r: Rect2, t: float, ctx: Dictionary) -> void:
	ci.draw_rect(r, Color(0, 0, 0, 0.3))
	var cw: float = r.size.x * 0.2
	var chh: float = r.size.y * 0.62
	var sel: float = ph(t, 1.0, 1.2)
	var flip: float = ph(t, 1.5, 1.9)
	for i in 3:
		var deal: float = _e(ph(t, 0.05 + i * 0.1, 0.5 + i * 0.1))
		var lift: float = (sel * r.size.y * 0.06) if i == 1 else 0.0
		var sink: float = (ph(t, 2.0, 2.4) * r.size.y * 0.1) if i != 1 else 0.0
		var a: float = deal * (1.0 - ((ph(t, 2.0, 2.4) * 0.7) if i != 1 else 0.0))
		var cx: float = r.get_center().x + (i - 1) * cw * 1.25
		var sx: float = absf(cos(flip * PI)) if i == 1 else 1.0
		var cr := Rect2(Vector2(cx - cw * sx / 2.0, r.get_center().y - chh / 2.0 - lift + sink + (1.0 - deal) * r.size.y * 0.3), Vector2(cw * sx, chh))
		var face: bool = i == 1 and flip > 0.5
		ci.draw_rect(cr, (Color(0.1, 0.12, 0.14) if face else Color(0.2, 0.12, 0.3)) * Color(1, 1, 1, a))
		ci.draw_rect(cr, _ca(UI.GOLD if face else UI.PURPLE, a), false, 1.5)
		if face:
			ci.draw_circle(cr.get_center() + Vector2(0, -chh * 0.15), cw * 0.2 * sx, _ca(UI.GOLD, a))
			for k in 2:
				ci.draw_rect(Rect2(cr.position + Vector2(cr.size.x * 0.18, chh * (0.62 + k * 0.12)), Vector2(cr.size.x * (0.64 - k * 0.2), 2.0)), Color(1, 1, 1, 0.35 * a))
		else:
			ci.draw_colored_polygon(PackedVector2Array([cr.get_center() + Vector2(0, -chh * 0.18), cr.get_center() + Vector2(cr.size.x * 0.22, 0), cr.get_center() + Vector2(0, chh * 0.18), cr.get_center() + Vector2(-cr.size.x * 0.22, 0)]), _ca(UI.PURPLE, 0.6 * a))
	if ctx.touch:
		finger(ci, r.get_center() + Vector2(0, chh * 0.2), r.size.y * 0.07, ph(t, 0.9, 1.15))
	else:
		cursor(ci, r.get_center() + Vector2(0, chh * 0.1) + Vector2(1, 1) * (1.0 - ph(t, 0.5, 0.9)) * r.size.y * 0.2, r.size.y * 0.12)
