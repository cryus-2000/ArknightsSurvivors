extends RefCounted
## 启动页三个新方向的画法（10-30 用户「声纳加载界面得重新设计一下，更加有 PRTS 的感觉，但是保留点深海的特色」）。
## 开关 balance.json ui/boot_v：0 = 现行「声呐测绘」（boot_screen._draw）；1 / 2 / 3 = 下面三个方向，挑定后再精修。网页同名方向在 tools/web/loader.js。
##   1 终端开机：深色底 + 等宽系统日志逐行滚出（真实阶段 / 正在编译的类别）+ 分段进度条与百分比 + 角标编号；深海 = 上浮的海雪微粒、日志窗右上的小声呐
##   2 深潜：右侧深度计（刻度随进度下潜，读数 -m）+ 左侧终端日志；背景随深度变暗、海雪上浮；读到最后水母剪影浮上来，接标题页
##   3 声呐终端：中央声呐盘，进度 = 外圈 72 枚刻度逐个点亮 + 扫描扇面；左右两块终端读数用引线接到盘上；四角取景角标（10-31 第二版加强科技感，见 draw_v3）
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
		var room: float = r.end.x - x - mono_w("OK", sz) - sz * 1.2   # 放不下就截断加「…」，不压到右边的 OK / 框外
		if mono_w(body, sz) > room:
			while body.length() > 1 and mono_w(body + "…", sz) > room:
				body = body.substr(0, body.length() - 1)
			body += "…"
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

## 10-31 第二版（用户「3 的感觉不错，可以更加有科技感一点，更有 PRTS 的那种感觉」）：
## 盘 = 外圈 72 刻度（进度）+ 方位读数 000 / 090 / 180 / 270 + 两层反向慢转的分段环 + 准星；圈心百分比带一位小数、下写 SYNC RATE。
## 四周是终端语汇：点阵底、页眉标尺 + 在线灯、日志新行打字机逐字出、读数带小条、信号波形、条码 + 十六进制数据流页脚、引线接点小方块。
## 装饰（波形 / 数据流 / 转环）只是氛围，进度与日志仍按真实加载
const HEX := "0123456789ABCDEF"

func _hexs(seed_i: int, n: int) -> String:
	var s := ""
	for i in n:
		var h: int = int(absf(sin((seed_i + i) * 12.9898) * 43758.5453)) % 256
		s += HEX[h >> 4] + HEX[h & 15] + " "
	return s


## 打字机：新行在出现后 0.35 秒内逐字打出（减少动态效果时整行直接出）
func _typed(s: String, age: float) -> String:
	if _rm() or age >= 0.35:
		return s
	return s.substr(0, int(ceil(s.length() * age / 0.35)))


func draw_v3(vs: Vector2, st: Dictionary) -> void:
	var t: float = st.t
	var p: float = st.p
	var tt: float = 0.0 if _rm() else t
	var compact: bool = vs.y <= 520.0
	var port: bool = vs.y > vs.x
	c.draw_rect(Rect2(Vector2.ZERO, vs), BG)
	# 点阵底
	var gx := 12.0
	while gx < vs.x:
		var gy := 12.0
		while gy < vs.y:
			c.draw_rect(Rect2(gx, gy, 1, 1), Color(CYAN, 0.06))
			gy += 24.0
		gx += 24.0
	snow(vs, t, 30, 0.7, 0.6)
	var m: float = 16.0 if compact or port else 28.0
	brackets(Rect2(Vector2(m, m), vs - Vector2(m, m) * 2.0), Color(CYAN, 0.5), 18.0, 1.5)
	# 页眉：PRTS + 标题 + 在线灯 + 编号；下面一条标尺
	var hy: float = m + 24.0
	en(Vector2(m + 16, hy), "PRTS", 14, CYAN, 4.0)
	txt(Vector2(m + 76, hy), "声呐终端 · 链路建立", 12, TEXT)
	var on: bool = _rm() or fmod(t, 1.2) < 0.8
	if not port:
		var code := "RI-SONAR 07 · T+%05.1f" % t
		var cw: float = mono_w(code, 11)
		mono(Vector2(vs.x - m - 16 - cw, hy), code, 11, DIM)
		c.draw_rect(Rect2(vs.x - m - 16 - cw - 70, hy - 8, 7, 7), Color(CYAN, 1.0 if on else 0.25))
		en(Vector2(vs.x - m - 16 - cw - 58, hy), "ONLINE", 10, CYAN, 2.0)
	var ry: float = hy + 10.0
	c.draw_line(Vector2(m + 16, ry), Vector2(vs.x - m - 16, ry), LINE, 1.0)
	var rx: float = m + 16.0
	var k := 0
	while rx < vs.x - m - 16:
		c.draw_line(Vector2(rx, ry), Vector2(rx, ry + (5.0 if k % 5 == 0 else 2.0)), Color(CYAN, 0.35 if k % 5 == 0 else 0.15), 1.0)
		rx += 12.0
		k += 1
	# ---- 声呐盘
	var R: float = minf(vs.y * (0.27 if not port else 0.19), vs.x * (0.2 if not port else 0.36))
	var cen := Vector2(vs.x * 0.5, vs.y * (0.49 if not port else 0.34))
	c.draw_arc(cen, R, 0, TAU, 96, Color(CYAN, 0.2), 1.0, true)
	c.draw_arc(cen, R * 0.33, 0, TAU, 48, Color(CYAN, 0.1), 1.0, true)
	# 两层反向慢转的分段环
	for ring in [[0.78, 12, 0.18, 1.0], [0.56, 24, 0.35, -1.6]]:
		var rr: float = R * float(ring[0])
		var nseg: int = int(ring[1])
		var sp: float = float(ring[3]) * 0.25
		for i in nseg:
			if i % 4 == 3:
				continue   # 缺口
			var a0: float = TAU * i / nseg + tt * sp
			c.draw_arc(cen, rr, a0, a0 + TAU / nseg * 0.78, 6, Color(CYAN, float(ring[2])), 2.0 if nseg == 12 else 1.0, true)
	# 准星
	for d4 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		c.draw_line(cen + d4 * R * 0.12, cen + d4 * R * 0.26, Color(CYAN, 0.35), 1.0)
	# 扫描扇面
	var ang: float = -0.4 if _rm() else fmod(t / 3.2, 1.0) * TAU
	var pts := PackedVector2Array([cen])
	var cols := PackedColorArray([Color(CYAN, 0.0)])
	for i in 13:
		pts.append(cen + Vector2.from_angle(ang - PI / 4.0 + (PI / 4.0) * i / 12.0) * R)
		cols.append(Color(CYAN, 0.2 * i / 12.0))
	c.draw_polygon(pts, cols)
	c.draw_line(cen, cen + Vector2.from_angle(ang) * R, Color(CYAN, 0.6), 1.0, true)
	# 外圈 72 刻度 = 进度；方位读数
	var n := 72
	var lit: int = int(floor(p * n))
	for i in n:
		var d := Vector2.from_angle(-PI / 2.0 + TAU * i / n)
		var major: bool = i % 6 == 0
		var col: Color = Color(CYAN, 0.95) if i < lit else Color(CYAN, 0.14)
		if i == lit and not _rm() and fmod(t, 0.5) < 0.25:
			col = Color(1, 1, 1, 0.9)   # 正在点亮的那一格闪
		c.draw_line(cen + d * (R + 8.0), cen + d * (R + (20.0 if major else 14.0)), col, 2.0 if major else 1.5, true)
	for q in 4:
		var dq := Vector2.from_angle(-PI / 2.0 + q * PI / 2.0)
		var lab := "%03d" % (q * 90)
		var lp: Vector2 = cen + dq * (R + 34.0) - Vector2(mono_w(lab, 10) / 2.0, -4.0)
		mono(lp, lab, 10, DIM)
	# 圈心：百分比一位小数 + SYNC RATE
	var big: int = int(clampf(R * 0.3, 22.0, 50.0))
	var pct := "%.1f" % (floorf(p * 1000.0) / 10.0)
	var pw: float = mono_w(pct, big)
	var px: float = cen.x - (pw + big * 0.3) / 2.0
	mono(Vector2(px, cen.y + big * 0.34), pct, big, TEXT)
	mono(Vector2(px + pw, cen.y + big * 0.34), "%", int(big * 0.42), CYAN)
	var sr := "SYNC RATE"
	en(Vector2(cen.x - 30, cen.y + big * 0.34 + 18), sr, 9, CYAN, 2.5)
	var ja: float = clampf((p - 0.8) / 0.2, 0.0, 1.0)   # 读到最后：水母回波在盘里亮起
	if ja > 0.0:
		jelly(cen + Vector2(R * 0.45, -R * 0.42), R / 120.0, t, ja * 0.85)
		mono(cen + Vector2(R * 0.45 + 30, -R * 0.42 - 20), "CONTACT", 9, Color(CYAN, ja))
	# ---- 两侧面板
	var sz: int = 12 if compact else 13
	var tlines: Array = []
	for ln in st.lines:   # 打字机：每行按出现时刻逐字出
		var l2: Dictionary = ln.duplicate()
		l2.s = _typed(str(ln.s), t - float(ln.t))
		tlines.append(l2)
	if not port:
		var lw: float = minf(340.0, cen.x - R - 80.0 - m)
		var lr := Rect2(m + 24, cen.y - 80, lw, 160)
		var ly: float = cen.y - 86.0
		_leader(Vector2(lr.end.x + 8, ly), Vector2(cen.x - R - 40, ly), cen + Vector2.from_angle(PI + 0.55) * (R + 26.0))
		_panel_cap(lr.position + Vector2(0, -14), "SYSTEM LOG", "01")
		log_lines(lr, tlines, t, sz, sz + 7.0)
		var rw: float = minf(310.0, vs.x - cen.x - R - 80 - m - 24)
		var rr2 := Rect2(cen.x + R + 80, cen.y - 80, rw, 160)
		_leader(Vector2(rr2.position.x - 8, ly), Vector2(cen.x + R + 40, ly), cen + Vector2.from_angle(-0.55) * (R + 26.0))
		_panel_cap(rr2.position + Vector2(0, -14), "TELEMETRY", "02")
		var yy: float = rr2.position.y + sz + 4
		yy = _tele_row(rr2, yy, sz, "深度", "-%04d m" % int(DEPTH_MAX * p), p)
		yy = _tele_row(rr2, yy, sz, "模块", "%d / %d" % [st.n, st.total], float(st.n) / maxf(1.0, float(st.total)))
		yy = _tele_row(rr2, yy, sz, "阶段", str(st.label), -1.0)
		# 信号波形
		mono(Vector2(rr2.position.x, yy + 4), "信号", sz, DIM)
		var wv := PackedVector2Array()
		var wx0: float = rr2.position.x + sz * 3.4
		var ww: float = rr2.size.x - sz * 3.4
		for i in 48:
			var x: float = wx0 + ww * i / 47.0
			var a: float = sin(i * 0.7 + tt * 6.0) * 0.5 + sin(i * 1.9 - tt * 9.0) * 0.3
			wv.append(Vector2(x, yy - 1 + a * 5.0))
		c.draw_polyline(wv, Color(CYAN, 0.7), 1.0, true)
		tip_block(Rect2(rr2.position.x, yy + 16, rr2.size.x, 70), st.tip, st.tip_a, sz - 1)
	else:
		var lr3 := Rect2(m + 16, cen.y + R + 56, vs.x - 2 * m - 32, vs.y * 0.24)
		_panel_cap(lr3.position + Vector2(0, -14), "SYSTEM LOG", "01")
		log_lines(lr3, tlines, t, sz, sz + 7.0)
		tip_block(Rect2(m + 16, lr3.end.y + 12, vs.x - 2 * m - 32, 70), st.tip, st.tip_a, sz - 1)
	# ---- 页脚：条码 + 十六进制数据流
	var fy: float = vs.y - m - (30.0 if not compact else 22.0)
	var bx: float = m + 16.0
	for i in 34:
		var bw: float = 1.0 + float(int(absf(sin(i * 7.31) * 100.0)) % 3)
		c.draw_rect(Rect2(bx, fy - 12, bw, 12), Color(CYAN, 0.5))
		bx += bw + 2.0
	if not port:
		var hs: String = _hexs(int(tt * 6.0), 40)
		var hx: float = bx + 14.0
		mono(Vector2(hx, fy - 2), hs.substr(0, int((vs.x * 0.5 - hx) / 6.6)), 11, Color(CYAN, 0.32))
	foot(vs, compact)


## 面板标题：英文 + 编号小框
func _panel_cap(p: Vector2, s: String, no: String) -> void:
	c.draw_rect(Rect2(p + Vector2(0, -9), Vector2(18, 12)), Color(CYAN, 0.85))
	mono(p + Vector2(2, 1), no, 10, BG)
	en(p + Vector2(24, 1), s, 10, DIM, 3.0)


## 引线：横 → 斜到盘边，两头各一个小方块接点
func _leader(a: Vector2, b: Vector2, e: Vector2) -> void:
	c.draw_line(a, b, Color(CYAN, 0.4), 1.0)
	c.draw_line(b, e, Color(CYAN, 0.4), 1.0)
	c.draw_rect(Rect2(a - Vector2(2, 2), Vector2(4, 4)), Color(CYAN, 0.8))
	c.draw_rect(Rect2(e - Vector2(2, 2), Vector2(4, 4)), Color(CYAN, 0.8))


## 读数行：标签 + 值 + 下面一道细条（frac < 0 不画条）；返回下一行 y
func _tele_row(r: Rect2, y: float, sz: int, k: String, v: String, frac: float) -> float:
	mono(Vector2(r.position.x, y), k, sz, DIM)
	mono(Vector2(r.position.x + sz * 3.4, y), v, sz, TEXT)
	if frac >= 0.0:
		var br := Rect2(r.position.x + sz * 3.4, y + 5, r.size.x - sz * 3.4, 2)
		c.draw_rect(br, Color(0.1, 0.15, 0.18))
		c.draw_rect(Rect2(br.position, Vector2(br.size.x * clampf(frac, 0.0, 1.0), 2)), Color(CYAN, 0.8))
	return y + sz + 14.0
