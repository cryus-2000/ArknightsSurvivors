extends RefCounted
## 启动页三个新方向的画法（10-30 用户「声纳加载界面得重新设计一下，更加有 PRTS 的感觉，但是保留点深海的特色」）。
## 开关 balance.json ui/boot_v：0 = 现行「声呐测绘」（boot_screen._draw）；1 / 2 / 3 = 下面三个方向，挑定后再精修。网页同名方向在 tools/web/loader.js。
##   1 终端开机：深色底 + 等宽系统日志逐行滚出（真实阶段 / 正在编译的类别）+ 分段进度条与百分比 + 角标编号；深海 = 上浮的海雪微粒、日志窗右上的小声呐
##   2 深潜：右侧深度计（刻度随进度下潜，读数 -m）+ 左侧终端日志；背景随深度变暗、海雪上浮；读到最后水母剪影浮上来，接标题页
##   3 声呐终端：中央声呐盘，进度 = 外圈 72 枚刻度逐个点亮 + 扫描扇面；左右两块终端读数用引线接到盘上；四角取景角标
## 全部程序绘制（不加图）；进度、日志都来自 boot_screen 的真实加载状态（不做假动画）。减少动态效果时微粒不动、扫描停住、光标不闪
const CYAN := Color(0.369, 0.902, 0.902)
const TEXT := Color(0.93, 0.95, 0.96)
const DIM := Color(0.47, 0.56, 0.6)
const FAINT := Color(0.22, 0.29, 0.33)
const LINE := Color(0.16, 0.23, 0.27)
const BG := Color(0.02, 0.035, 0.05)
const DEPTH_MAX := 1200.0   # 方向 2 / 3：读完 = 下潜到 -1200 m

var c: Control   # boot_screen
var font: Font


func _init(ctl: Control, f: Font) -> void:
	c = ctl
	font = f


# ================================================================ 共用小件

func _rm() -> bool:
	return Cfg.reduce_motion


## 等宽字：拉丁 / 数字按 0.6 字宽、中文按 1 字宽逐字画（项目只有一套 UI 字体）
func mono(pos: Vector2, s: String, sz: int, col: Color) -> float:
	var x := pos.x
	for ch in s:
		var wide: bool = ch.unicode_at(0) > 0x2E80
		var adv: float = sz * (1.0 if wide else 0.6)
		if ch != " ":
			var gw: float = font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
			c.draw_string(font, Vector2(x + (adv - gw) * 0.5, pos.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
		x += adv
	return x - pos.x


func mono_w(s: String, sz: int) -> float:
	var w := 0.0
	for ch in s:
		w += sz * (1.0 if ch.unicode_at(0) > 0x2E80 else 0.6)
	return w


func en(pos: Vector2, s: String, sz: int, col: Color, sp := 3.0) -> float:
	var x := pos.x
	for ch in s:
		c.draw_string(font, Vector2(x, pos.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x + sp
	return x - pos.x - sp


func txt(pos: Vector2, s: String, sz: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	c.draw_string(font, pos, s, align, w, sz, col)


## 取景角标：矩形四角各一个 L
func brackets(r: Rect2, col: Color, L := 10.0, w := 1.5) -> void:
	for cx in [0, 1]:
		for cy in [0, 1]:
			var p := Vector2(r.position.x + r.size.x * cx, r.position.y + r.size.y * cy)
			var sx: float = 1.0 if cx == 0 else -1.0
			var sy: float = 1.0 if cy == 0 else -1.0
			c.draw_line(p, p + Vector2(sx * L, 0), col, w)
			c.draw_line(p, p + Vector2(0, sy * L), col, w)


## 海雪：n 粒微光慢慢上浮（位置由序号与时间算，不存状态）；speed 随深度可调
func snow(vs: Vector2, t: float, n: int, speed := 1.0, a := 1.0) -> void:
	var tt: float = 0.0 if _rm() else t
	for i in n:
		var h1: float = fposmod(sin(i * 12.9898) * 43758.5453, 1.0)
		var h2: float = fposmod(sin(i * 78.233) * 12543.123, 1.0)
		var h3: float = fposmod(sin(i * 3.71) * 9123.77, 1.0)
		var sp: float = (8.0 + 22.0 * h2) * speed
		var x: float = h1 * vs.x + sin(tt * 0.6 + i) * 6.0
		var y: float = vs.y - fposmod(h3 * (vs.y + 40.0) + tt * sp, vs.y + 40.0) + 20.0
		var al: float = (0.12 + 0.35 * h2) * a
		var s: float = 1.0 + floorf(h3 * 2.0)
		c.draw_rect(Rect2(Vector2(floorf(x), floorf(y)), Vector2(s, s)), Color(0.6, 0.9, 0.95, al))


## 分段进度条：n 段，点亮 floor(p·n) 段，正在填的那段半亮
func seg_bar(r: Rect2, p: float, n: int, col: Color) -> void:
	var gap := 2.0
	var sw: float = (r.size.x - gap * (n - 1)) / n
	var lit: float = p * n
	for i in n:
		var sr := Rect2(r.position.x + i * (sw + gap), r.position.y, sw, r.size.y)
		var f: float = clampf(lit - i, 0.0, 1.0)
		c.draw_rect(sr, Color(0.09, 0.13, 0.16))
		if f > 0.0:
			c.draw_rect(Rect2(sr.position, Vector2(sw * f, sr.size.y)), Color(col.r, col.g, col.b, 1.0 if f >= 1.0 else 0.55))


func cursor_on(t: float) -> bool:
	return _rm() or fmod(t, 1.0) < 0.55


## 水母剪影（程序绘制）：伞盖半椭圆 + 波浪伞缘 + 几条摆动的触须
func jelly(cen: Vector2, s: float, t: float, a: float) -> void:
	if a <= 0.01:
		return
	var tt: float = 0.0 if _rm() else t
	var pulse: float = 1.0 + 0.05 * sin(tt * 2.2)
	var pts := PackedVector2Array()
	var w: float = 34.0 * s * pulse
	var h: float = 26.0 * s / pulse
	for i in 25:
		var an: float = PI + PI * i / 24.0
		pts.append(cen + Vector2(cos(an) * w, sin(an) * h))
	for i in 13:   # 波浪伞缘（右 → 左）
		var x: float = w - 2.0 * w * i / 12.0
		pts.append(cen + Vector2(x, 3.0 * s * sin(i * 1.6 + tt * 3.0)))
	c.draw_colored_polygon(pts, Color(0.55, 0.92, 0.95, 0.16 * a))
	var outline := pts.duplicate()
	outline.append(pts[0])
	c.draw_polyline(outline, Color(0.6, 0.95, 1.0, 0.45 * a), 1.2, true)
	for k in 5:
		var x0: float = -w * 0.7 + w * 1.4 * k / 4.0
		var tp := PackedVector2Array()
		for j in 12:
			var yy: float = 3.0 * s + j * 5.5 * s
			tp.append(cen + Vector2(x0 + sin(tt * 1.8 + j * 0.5 + k) * 3.0 * s * (j / 11.0), yy))
		c.draw_polyline(tp, Color(0.6, 0.95, 1.0, 0.28 * a * (1.0 - 0.1 * k)), 1.0, true)


## 日志行：[时间] 文本 ……… OK（正在读的一行 cur：光标闪；其余没读完的写「..」）
func log_lines(r: Rect2, lines: Array, t: float, sz: int, lh: float) -> void:
	var nmax: int = maxi(1, int(r.size.y / lh))
	var start: int = maxi(0, lines.size() - nmax)
	var y: float = r.position.y + sz
	for i in range(start, lines.size()):
		var ln: Dictionary = lines[i]
		var cur: bool = ln.get("cur", false) and not ln.ok
		var x: float = r.position.x
		x += mono(Vector2(x, y), "[%06.2f]" % float(ln.t), sz, DIM if cur else FAINT) + sz * 0.6
		var body: String = str(ln.s)
		var bw: float = mono(Vector2(x, y), body, sz, DIM if ln.ok else (TEXT if cur else Color(0.72, 0.78, 0.8)))
		var tag: String = "OK" if ln.ok else (("_" if cursor_on(t) else "") if cur else "..")
		var tw: float = mono_w("OK", sz)
		var dx0: float = x + bw + sz * 0.6
		var dx1: float = r.end.x - tw - sz * 0.6
		if dx1 > dx0:
			mono(Vector2(dx0, y), ".".repeat(int((dx1 - dx0) / (sz * 0.6))), sz, Color(FAINT, 0.7))
		mono(Vector2(r.end.x - tw, y), tag, sz, CYAN if ln.ok else TEXT)
		y += lh


## 页脚声明（三个方向共用；与现行同句）
func foot(vs: Vector2, compact: bool) -> void:
	txt(Vector2(0, vs.y - (14.0 if not compact else 7.0)), "明日方舟同人作品 · 非商业 · 与鹰角网络无关", 11, Color(0.4, 0.48, 0.52), HORIZONTAL_ALIGNMENT_CENTER, vs.x)


func tip_block(r: Rect2, tip: String, ta: float, sz: int) -> void:
	en(r.position + Vector2(0, 10), "NOTE", 10, DIM, 3.0)
	var brk := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_GRAPHEME_BOUND | TextServer.BREAK_ADAPTIVE
	c.draw_multiline_string(font, r.position + Vector2(0, 30), tip, HORIZONTAL_ALIGNMENT_LEFT, r.size.x, sz, -1, Color(0.7, 0.78, 0.8, ta), brk)


func header(vs: Vector2, m: float, title: String, code: String, show_code: bool, rule_w := -1.0) -> float:
	var hy: float = m + 12.0
	en(Vector2(m, hy), "PRTS", 16, CYAN, 4.0)
	txt(Vector2(m + 70, hy), title, 13, TEXT)
	if show_code:
		mono(Vector2(vs.x - m - mono_w(code, 12), hy), code, 12, DIM)
	c.draw_line(Vector2(m, hy + 10), Vector2((vs.x - m) if rule_w < 0.0 else m + rule_w, hy + 10), LINE, 1.0)
	return hy


# ================================================================ 1 终端开机

## st：{p, label, file, n, total, lines, t, tip, tip_a}
func draw_v1(vs: Vector2, st: Dictionary) -> void:
	var t: float = st.t
	var compact: bool = vs.y <= 520.0
	var port: bool = vs.y > vs.x
	c.draw_rect(Rect2(Vector2.ZERO, vs), BG)
	var y := 0.0
	while y < vs.y:   # 扫描线
		c.draw_rect(Rect2(0, y, vs.x, 1), Color(1, 1, 1, 0.018))
		y += 3.0
	snow(vs, t, 46, 0.8, 0.8)
	var m: float = 18.0 if compact or port else 36.0
	var hy: float = header(vs, m, "罗德岛作战终端 · 启动程序", "NODE AS-07 · T+%05.1f" % t, not port)
	var lr: Rect2
	var tr: Rect2
	if port:
		lr = Rect2(m, hy + 34, vs.x - 2 * m, vs.y * 0.46)
		tr = Rect2(m, lr.end.y + 24, vs.x - 2 * m, 80)
	else:
		var lw: float = vs.x * 0.62
		lr = Rect2(m, hy + 34, lw - m, vs.y - hy - 34 - (110.0 if not compact else 78.0))
		tr = Rect2(lw + 30, hy + 44, vs.x - lw - 30 - m, 160)
	brackets(lr.grow(8.0), Color(CYAN, 0.55), 12.0, 1.5)
	en(lr.position + Vector2(0, -14), "SYSTEM LOG", 10, DIM, 3.0)
	var sz: int = 12 if compact else 14
	log_lines(lr.grow_individual(0, -6, 0, 0), st.lines, t, sz, sz + 8.0)
	if not port:   # 日志窗右上的小声呐（深海）
		var sc := Vector2(lr.end.x - 18, lr.position.y - 22)
		c.draw_arc(sc, 12, 0, TAU, 40, Color(CYAN, 0.3), 1.0, true)
		c.draw_arc(sc, 6, 0, TAU, 24, Color(CYAN, 0.2), 1.0, true)
		var an: float = -0.6 if _rm() else fmod(t / 2.4, 1.0) * TAU
		c.draw_line(sc, sc + Vector2.from_angle(an) * 12.0, Color(CYAN, 0.75), 1.2, true)
	tip_block(tr, st.tip, st.tip_a, 12 if compact else 13)
	var by: float = vs.y - (64.0 if not compact else 44.0)
	var pw: float = vs.x - 2 * m - (130.0 if not port else 0.0)
	seg_bar(Rect2(m, by, pw, 8.0 if not compact else 6.0), st.p, 50 if pw > 600 else 30, CYAN)
	var pct := "%03d%%" % int(floor(st.p * 100.0))
	var big: int = 34 if not compact else 24
	if port:
		mono(Vector2(m, by - 14), pct, big, TEXT)
	else:
		mono(Vector2(vs.x - m - mono_w(pct, big), by + 12), pct, big, TEXT)
	var what: String = str(st.label) + ("　%s" % st.file if str(st.file) != "" else "")
	mono(Vector2(m, by + 26), what.substr(0, 60), 11, DIM)
	foot(vs, compact)


# ================================================================ 2 深潜

func draw_v2(vs: Vector2, st: Dictionary) -> void:
	var t: float = st.t
	var p: float = st.p
	var compact: bool = vs.y <= 520.0
	var port: bool = vs.y > vs.x
	var top: Color = Color(0.05, 0.16, 0.2).lerp(Color(0.015, 0.03, 0.045), p)
	var bot: Color = Color(0.02, 0.06, 0.08).lerp(Color(0.005, 0.01, 0.018), p)
	c.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(vs.x, 0), vs, Vector2(0, vs.y)]), PackedColorArray([top, top, bot, bot]))
	snow(vs, t, 60, 0.6 + 1.6 * p, 0.6 + 0.6 * p)
	var m: float = 18.0 if compact or port else 36.0
	var hy: float = header(vs, m, "深潜观测 · 终端接入", "", false, (vs.x * 0.62 - 2 * m) if not port else -1.0)
	var depth: float = DEPTH_MAX * p
	if not port:
		var gx: float = vs.x - m - 150.0
		var gt: float = hy + 20.0
		var gb: float = vs.y - 50.0
		var mid: float = (gt + gb) * 0.5
		var ppm := 1.2   # 每米多少像素：读数在中线，尺子随深度往上走
		c.draw_line(Vector2(gx, gt), Vector2(gx, gb), Color(CYAN, 0.35), 1.0)
		var d: float = maxf(0.0, floorf((depth - (mid - gt) / ppm) / 10.0) * 10.0)
		while d <= depth + (gb - mid) / ppm:
			var yy: float = mid + (d - depth) * ppm
			if yy >= gt and yy <= gb:
				var major: bool = int(d) % 100 == 0
				c.draw_line(Vector2(gx, yy), Vector2(gx + (16.0 if major else 7.0), yy), Color(CYAN, 0.6 if major else 0.25), 1.0)
				if major:
					mono(Vector2(gx + 22, yy + 4), "-%d" % int(d), 11, DIM)
			d += 10.0
		c.draw_colored_polygon(PackedVector2Array([Vector2(gx - 4, mid), Vector2(gx - 14, mid - 6), Vector2(gx - 14, mid + 6)]), CYAN)
		var dr := "-%04d" % int(depth)
		var big: int = 40 if not compact else 28
		var dw: float = mono_w(dr, big)
		var x0: float = gx - 40 - dw
		en(Vector2(x0, mid - big * 0.7), "DEPTH", 10, DIM, 3.0)
		mono(Vector2(x0, mid + big * 0.36), dr, big, TEXT)
		mono(Vector2(x0 + dw + 4, mid + big * 0.36), "m", 16, CYAN)
		mono(Vector2(x0, mid + big * 0.36 + 24), "同步 %d%%" % int(floor(p * 100.0)), 12, CYAN)
	var lr: Rect2
	if port:
		lr = Rect2(m, hy + 34, vs.x - 2 * m, vs.y * 0.42)
	else:
		lr = Rect2(m, hy + 34, vs.x * 0.62 - 2 * m, vs.y - hy - 34 - (120.0 if not compact else 84.0))
	brackets(lr.grow(8.0), Color(CYAN, 0.5), 12.0, 1.5)
	en(lr.position + Vector2(0, -14), "SYSTEM LOG", 10, DIM, 3.0)
	var sz: int = 12 if compact else 14
	log_lines(lr.grow_individual(0, -6, 0, 0), st.lines, t, sz, sz + 8.0)
	if port:
		var yy2: float = lr.end.y + 50.0
		mono(Vector2(m, yy2), "-%04d m" % int(depth), 32, TEXT)
		seg_bar(Rect2(m, yy2 + 16, vs.x - 2 * m, 6), p, 24, CYAN)
		mono(Vector2(m, yy2 + 40), "同步 %d%%" % int(floor(p * 100.0)), 12, CYAN)
	var ty: float = vs.y - (96.0 if not compact else 70.0) if not port else vs.y - 150.0
	tip_block(Rect2(m, ty, (vs.x * 0.62 - 2 * m) if not port else vs.x - 2 * m, 60), st.tip, st.tip_a, 12 if compact else 13)
	var ja: float = clampf((p - 0.82) / 0.18, 0.0, 1.0)   # 读到最后：水母剪影从深处浮上来（接标题页的水母）
	if ja > 0.0:
		jelly(Vector2(vs.x * (0.5 if port else 0.64), vs.y * (0.66 - 0.12 * ja)), 1.6 if not compact else 1.1, t, ja)
	foot(vs, compact)


# ================================================================ 3 声呐终端

func draw_v3(vs: Vector2, st: Dictionary) -> void:
	var t: float = st.t
	var p: float = st.p
	var compact: bool = vs.y <= 520.0
	var port: bool = vs.y > vs.x
	c.draw_rect(Rect2(Vector2.ZERO, vs), BG)
	snow(vs, t, 40, 0.7, 0.7)
	var m: float = 16.0 if compact or port else 28.0
	brackets(Rect2(Vector2(m, m), vs - Vector2(m, m) * 2.0), Color(CYAN, 0.45), 18.0, 1.5)
	var hy: float = m + 24.0
	en(Vector2(m + 16, hy), "PRTS", 14, CYAN, 4.0)
	txt(Vector2(m + 76, hy), "声呐终端 · 链路建立", 12, TEXT)
	if not port:
		var code := "RI-SONAR 07 · T+%05.1f" % t
		mono(Vector2(vs.x - m - 16 - mono_w(code, 11), hy), code, 11, DIM)
	var R: float = minf(vs.y * (0.28 if not port else 0.2), vs.x * (0.2 if not port else 0.38))
	var cen := Vector2(vs.x * 0.5, vs.y * (0.47 if not port else 0.34))
	for k in [1.0, 0.66, 0.33]:
		c.draw_arc(cen, R * k, 0, TAU, 96, Color(CYAN, 0.16 if k == 1.0 else 0.09), 1.0, true)
	c.draw_line(cen - Vector2(R, 0), cen + Vector2(R, 0), Color(CYAN, 0.07), 1.0)
	c.draw_line(cen - Vector2(0, R), cen + Vector2(0, R), Color(CYAN, 0.07), 1.0)
	var ang: float = -0.4 if _rm() else fmod(t / 3.2, 1.0) * TAU
	var pts := PackedVector2Array([cen])
	var cols := PackedColorArray([Color(CYAN, 0.0)])
	for i in 13:
		pts.append(cen + Vector2.from_angle(ang - PI / 4.0 + (PI / 4.0) * i / 12.0) * R)
		cols.append(Color(CYAN, 0.22 * i / 12.0))
	c.draw_polygon(pts, cols)
	var n := 72   # 外圈刻度：进度逐个点亮
	var lit: int = int(floor(p * n))
	for i in n:
		var d := Vector2.from_angle(-PI / 2.0 + TAU * i / n)
		var major: bool = i % 6 == 0
		c.draw_line(cen + d * (R + 8.0), cen + d * (R + (20.0 if major else 14.0)), Color(CYAN, 0.95) if i < lit else Color(CYAN, 0.14), 2.0 if major else 1.5, true)
	var big: int = int(clampf(R * 0.34, 24.0, 56.0))
	var pct := "%d" % int(floor(p * 100.0))
	var pw: float = mono_w(pct, big)
	var px: float = cen.x - (pw + big * 0.3) / 2.0
	mono(Vector2(px, cen.y + big * 0.34), pct, big, TEXT)
	mono(Vector2(px + pw, cen.y + big * 0.34), "%", int(big * 0.42), CYAN)
	en(Vector2(cen.x - 16, cen.y + big * 0.34 + 18), "LINK", 10, CYAN, 3.0)
	var ja: float = clampf((p - 0.8) / 0.2, 0.0, 1.0)   # 读到最后：水母回波在盘里亮起
	if ja > 0.0:
		jelly(cen + Vector2(R * 0.45, -R * 0.4), R / 120.0, t, ja * 0.85)
	var sz: int = 12 if compact else 13
	if not port:
		var lw: float = minf(330.0, cen.x - R - 70.0 - m)
		var lr := Rect2(m + 24, cen.y - 70, lw, 150)
		var ly: float = cen.y - 76.0
		c.draw_line(Vector2(lr.end.x + 8, ly), Vector2(cen.x - R - 34, ly), Color(CYAN, 0.35), 1.0)
		c.draw_line(Vector2(cen.x - R - 34, ly), cen + Vector2.from_angle(PI + 0.5) * (R + 24.0), Color(CYAN, 0.35), 1.0)
		en(lr.position + Vector2(0, -12), "SYSTEM LOG", 10, DIM, 3.0)
		log_lines(lr, st.lines, t, sz, sz + 7.0)
		var rr := Rect2(cen.x + R + 70, cen.y - 70, minf(300.0, vs.x - cen.x - R - 70 - m - 24), 150)
		c.draw_line(Vector2(rr.position.x - 8, ly), Vector2(cen.x + R + 34, ly), Color(CYAN, 0.35), 1.0)
		c.draw_line(Vector2(cen.x + R + 34, ly), cen + Vector2.from_angle(-0.5) * (R + 24.0), Color(CYAN, 0.35), 1.0)
		en(rr.position + Vector2(0, -12), "TELEMETRY", 10, DIM, 3.0)
		var rows: Array = [["深度", "-%04d m" % int(DEPTH_MAX * p)], ["模块", "%d / %d" % [st.n, st.total]], ["阶段", str(st.label)]]
		var yy: float = rr.position.y + sz + 4
		for row in rows:
			mono(Vector2(rr.position.x, yy), str(row[0]), sz, DIM)
			mono(Vector2(rr.position.x + sz * 3.4, yy), str(row[1]), sz, TEXT)
			yy += sz + 10.0
		tip_block(Rect2(rr.position.x, yy + 6, rr.size.x, 70), st.tip, st.tip_a, sz - 1)
	else:
		var lr2 := Rect2(m + 16, cen.y + R + 50, vs.x - 2 * m - 32, vs.y * 0.24)
		en(lr2.position + Vector2(0, -12), "SYSTEM LOG", 10, DIM, 3.0)
		log_lines(lr2, st.lines, t, sz, sz + 7.0)
		tip_block(Rect2(m + 16, lr2.end.y + 12, vs.x - 2 * m - 32, 70), st.tip, st.tip_a, sz - 1)
	foot(vs, compact)
