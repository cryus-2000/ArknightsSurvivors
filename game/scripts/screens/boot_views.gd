extends RefCounted
## 启动页三个新方向的画法（10-30 用户「声纳加载界面得重新设计一下，更加有 PRTS 的感觉，但是保留点深海的特色」）。
## 开关 balance.json ui/boot_v：0 = 现行「声呐测绘」（boot_screen._draw）；1 / 2 / 3 = 下面三个方向，挑定后再精修。网页同名方向在 tools/web/loader.js。
##   1 终端开机：深色底 + 等宽系统日志逐行滚出（真实阶段 / 正在编译的类别）+ 分段进度条与百分比 + 角标编号；深海 = 上浮的海雪微粒、日志窗右上的小声呐
##   2 深潜：右侧深度计（刻度随进度下潜，读数 -m）+ 左侧终端日志；背景随深度变暗、海雪上浮；读到最后水母剪影浮上来，接标题页
##   3 声呐终端：中央声呐盘，进度 = 外圈 72 枚刻度逐个点亮 + 扫描扇面；左右两块终端读数用引线接到盘上；四角取景角标（10-31 第三版：照用户给的 PRTS 参考改成浅色终端版式、去掉水母、声呐上是真实加载项的接触点，见 draw_v3）
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

## 10-31 第三版（用户给 PRTS 风格参考图：浅灰底、黑色几何线条、巨大的空心字、字距拉开的英文小字、低多边形网格；「水母不要，就算要有声呐，声呐上也得显示点」）：
## 浅色终端版式——底色浅灰、墨黑线条与字、只在「正在进行」处点一点青；圈心是本作徽记（菱形 + 一道浪，不用官方标志）里写百分比。
## 同日用户「PRTS 不用放在后面，可以增加一点几何的动效」：去掉盘后的空心大字，加几何动效（_net 右上网格按进度连线、_geo 反向慢转的菱形框与绕圈小三角）。
## 声呐接触点 = 真实加载项：系统日志里的每一项（编译类别 / 阶段）一个点（按行的 key 定方位与距离），读到时出现、扫描扇面扫过时闪亮，读满变实心；
## 外圈 72 刻度仍是总进度。右上一片低多边形网格，左下系统日志、右侧读数，底部字距拉开的 RHODES ISLAND 与版本行。
## 读到最后（进度 > 93%）整屏渐暗成深海色，接深海水母标题页
const PBG := Color(0.905, 0.914, 0.925)
const INK := Color(0.07, 0.08, 0.09)
const GRAY := Color(0.5, 0.53, 0.56)
const PALE := Color(0.76, 0.78, 0.8)
const ACC := Color(0.0, 0.6, 0.64)
const DEEP := Color(0.02, 0.05, 0.08)


func _h1(s: String, k: int) -> float:
	return fposmod(sin(float(s.hash() % 100000) * 0.731 + k * 12.9898) * 43758.5453, 1.0)


## 打字机：新行在出现后 0.35 秒内逐字打出（减少动态效果时整行直接出）
func _typed(s: String, age: float) -> String:
	if _rm() or age >= 0.35:
		return s
	return s.substr(0, int(ceil(s.length() * age / 0.35)))


func _mono_c(pos: Vector2, s: String, sz: int, col: Color) -> void:
	mono(pos - Vector2(mono_w(s, sz) / 2.0, 0), s, sz, col)


## 字距拉开的英文（居中）
func _spaced(cx: float, y: float, s: String, sz: int, col: Color, sp: float) -> void:
	var w := 0.0
	for ch in s:
		w += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x + sp
	en(Vector2(cx - (w - sp) / 2.0, y), s, sz, col, sp)


## 低多边形网格（几何动效，10-31 用户「可以增加一点几何的动效」）：一组点各连最近的三个，节点缓慢漂移；
## 连线按加载进度逐条画出（p = 0 时一条没有，读完全部连上），正在画的那条从一端延伸过去。corner 0 = 右上、1 = 左下（镜像）
func _net(vs: Vector2, tt: float, p: float, corner: int) -> void:
	var pts: Array = []
	for i in 16:
		var hx: float = fposmod(sin((i + corner * 31) * 91.7) * 4375.85, 1.0)
		var hy: float = fposmod(sin((i + corner * 31) * 47.3) * 2937.11, 1.0)
		var q := Vector2(vs.x * 0.34 * hx, vs.y * 0.34 * hy * hy)
		q = Vector2(vs.x - q.x, q.y) if corner == 0 else Vector2(q.x, vs.y - q.y)
		pts.append(q + Vector2(sin(tt * 0.5 + i), cos(tt * 0.4 + i * 1.3)) * 6.0)
	var edges: Array = []
	for i in pts.size():
		var ds: Array = []
		for j in pts.size():
			if j != i:
				ds.append([pts[i].distance_to(pts[j]), j])
		ds.sort_custom(func(a, b): return a[0] < b[0])
		for k in 3:
			edges.append([i, ds[k][1]])
	var shown: float = edges.size() * clampf(p * 1.05, 0.0, 1.0)
	for e in edges.size():
		var f: float = clampf(shown - e, 0.0, 1.0)
		if f <= 0.0:
			break
		var a: Vector2 = pts[edges[e][0]]
		var b: Vector2 = pts[edges[e][1]]
		c.draw_line(a, a.lerp(b, f), Color(PALE.darkened(0.05), 0.95), 1.0, true)
		if f < 1.0:
			c.draw_rect(Rect2(a.lerp(b, f) - Vector2(2, 2), Vector2(4, 4)), ACC)   # 正在连的那一端
	for q2 in pts:
		c.draw_rect(Rect2(q2 - Vector2(2, 2), Vector2(4, 4)), PALE.darkened(0.2))


## 圈心外的几何动效：两层反向慢转的菱形框 + 外圈三枚沿圈转的小三角（减少动态效果时停在原位）
func _geo(cen: Vector2, R: float, er: float, tt: float) -> void:
	for ring in [[1.45, 0.35, 0.55], [1.85, -0.22, 0.32]]:
		var rr: float = er * float(ring[0])
		var a0: float = tt * float(ring[1])
		var pts := PackedVector2Array()
		for k in 5:
			pts.append(cen + Vector2.from_angle(a0 + k * PI / 2.0) * rr)
		c.draw_polyline(pts, Color(INK, float(ring[2])), 1.0, true)
		for k in 4:
			c.draw_rect(Rect2(pts[k] - Vector2(2, 2), Vector2(4, 4)), Color(INK, float(ring[2])))
	for k in 3:
		var a: float = tt * 0.6 + k * TAU / 3.0
		var d := Vector2.from_angle(a)
		var tip: Vector2 = cen + d * (R + 26.0)
		var nrm := Vector2(-d.y, d.x)
		c.draw_colored_polygon(PackedVector2Array([tip, tip + d * 8.0 + nrm * 5.0, tip + d * 8.0 - nrm * 5.0]), INK)


## 本作徽记：菱形 + 一道浪（docs/37；不用官方标志）
func _emblem(cen: Vector2, r: float, col: Color, w: float) -> void:
	var d := PackedVector2Array([cen + Vector2(0, -r), cen + Vector2(r, 0), cen + Vector2(0, r), cen + Vector2(-r, 0), cen + Vector2(0, -r)])
	c.draw_polyline(d, col, w, true)
	var wv := PackedVector2Array()
	for i in 21:
		var x: float = -r * 0.62 + r * 1.24 * i / 20.0
		wv.append(cen + Vector2(x, r * 0.5 + sin(i / 20.0 * TAU) * r * 0.06))
	c.draw_polyline(wv, col, maxf(1.0, w * 0.5), true)


func draw_v3(vs: Vector2, st: Dictionary) -> void:
	var t: float = st.t
	var p: float = st.p
	var tt: float = 0.0 if _rm() else t
	var compact: bool = vs.y <= 520.0
	var port: bool = vs.y > vs.x
	c.draw_rect(Rect2(Vector2.ZERO, vs), PBG)
	_net(vs, tt, p, 0)   # 只放右上（左下会压到系统日志）
	var m: float = 16.0 if compact or port else 30.0
	# 左上：PRTS 粗字 + 两行小字
	var tsz: int = 30 if not compact else 22
	c.draw_string(font, Vector2(m + 10, m + tsz + 4), "PRTS", HORIZONTAL_ALIGNMENT_LEFT, -1, tsz, INK)
	en(Vector2(m + 11, m + tsz + 18), "SONAR TERMINAL", 9, INK, 2.0)
	txt(Vector2(m + 11, m + tsz + 34), "声呐终端 · 链路建立", 11, GRAY)
	if not port:
		var code := "BUILD 1031 · T+%05.1f" % t
		mono(Vector2(vs.x - m - 10 - mono_w(code, 11), vs.y - m - 34), code, 11, GRAY)
	# ---- 盘
	var R: float = minf(vs.y * (0.27 if not port else 0.19), vs.x * (0.2 if not port else 0.36))
	var cen := Vector2(vs.x * 0.5, vs.y * (0.5 if not port else 0.36))
	c.draw_circle(cen, R, Color(PBG, 0.82))
	c.draw_arc(cen, R, 0, TAU, 96, INK, 1.5, true)
	c.draw_arc(cen, R * 0.66, 0, TAU, 72, Color(GRAY, 0.5), 1.0, true)
	c.draw_arc(cen, R * 0.33, 0, TAU, 48, Color(GRAY, 0.4), 1.0, true)
	c.draw_line(cen - Vector2(R, 0), cen + Vector2(R, 0), Color(GRAY, 0.3), 1.0)
	c.draw_line(cen - Vector2(0, R), cen + Vector2(0, R), Color(GRAY, 0.3), 1.0)
	var ang: float = -0.4 if _rm() else fmod(t / 3.2, 1.0) * TAU
	var pts := PackedVector2Array([cen])
	var cols := PackedColorArray([Color(INK, 0.0)])
	for i in 13:
		pts.append(cen + Vector2.from_angle(ang - PI / 4.0 + (PI / 4.0) * i / 12.0) * R)
		cols.append(Color(INK, 0.16 * i / 12.0))
	c.draw_polygon(pts, cols)
	c.draw_line(cen, cen + Vector2.from_angle(ang) * R, Color(INK, 0.55), 1.0, true)
	# 接触点 = 日志里的每一项（编译类别 / 阶段；第一行「终端唤醒」除外），按行的 key 定方位与距离
	var contacts: Array = []
	for li in range(1, st.lines.size()):
		contacts.append({"name": str(st.lines[li].get("k", st.lines[li].s)), "done": st.lines[li].ok, "i": li})
	for ct in contacts:
		var nm: String = str(ct.name)
		var a: float = _h1(nm, 1) * TAU
		var rr: float = R * (0.3 + 0.6 * _h1(nm, 2))
		var cp: Vector2 = cen + Vector2.from_angle(a) * rr
		var since: float = fposmod(ang - a, TAU) / TAU   # 扇面扫过后 0 → 1
		var hi: float = 0.0 if _rm() else clampf(1.0 - since * 3.0, 0.0, 1.0)
		if ct.done:
			c.draw_rect(Rect2(cp - Vector2(3, 3), Vector2(6, 6)), INK)
		else:
			var bl: bool = _rm() or fmod(t, 0.8) < 0.5
			c.draw_rect(Rect2(cp - Vector2(4, 4), Vector2(8, 8)), Color(ACC, 1.0 if bl else 0.35), false, 1.5)
			c.draw_rect(Rect2(cp - Vector2(1.5, 1.5), Vector2(3, 3)), ACC)
		if hi > 0.0:
			c.draw_arc(cp, 6.0 + 8.0 * (1.0 - hi), 0, TAU, 16, Color(INK if ct.done else ACC, 0.5 * hi), 1.0, true)
		mono(cp + Vector2(7, -5), "%02d" % int(ct.i), 9, GRAY)
	# 外圈 72 刻度 = 总进度；方位读数
	var n := 72
	var lit: int = int(floor(p * n))
	for i in n:
		var d := Vector2.from_angle(-PI / 2.0 + TAU * i / n)
		var major: bool = i % 6 == 0
		var col: Color = INK if i < lit else Color(PALE, 0.9)
		if i == lit and not _rm() and fmod(t, 0.5) < 0.25:
			col = ACC
		c.draw_line(cen + d * (R + 8.0), cen + d * (R + (20.0 if major else 14.0)), col, 2.0 if major else 1.5, true)
	for q in 4:
		var lab := "%03d" % (q * 90)
		_mono_c(cen + Vector2.from_angle(-PI / 2.0 + q * PI / 2.0) * (R + 34.0) + Vector2(0, 4), lab, 10, GRAY)
	# 圈心：徽记里写百分比
	var er: float = R * 0.3
	_geo(cen, R, er, tt)
	c.draw_colored_polygon(PackedVector2Array([cen + Vector2(0, -er), cen + Vector2(er, 0), cen + Vector2(0, er), cen + Vector2(-er, 0)]), PBG)
	_emblem(cen, er, INK, 3.0 if not compact else 2.0)
	var big: int = int(clampf(R * 0.17, 14.0, 30.0))
	var pct := "%.1f%%" % (floorf(p * 1000.0) / 10.0)
	_mono_c(cen + Vector2(0, big * 0.3), pct, big, INK)
	# 盘下：字距拉开的 RHODES ISLAND
	_spaced(cen.x, cen.y + R + 58.0, "RHODES ISLAND", 10, INK, 9.0)
	# ---- 两侧
	var sz: int = 12 if compact else 13
	var tlines: Array = []
	for ln in st.lines:
		var l2: Dictionary = ln.duplicate()
		l2.s = _typed(str(ln.s), t - float(ln.t))
		tlines.append(l2)
	if not port:
		var lw: float = minf(330.0, cen.x - R - 80.0 - m)
		var lr := Rect2(m + 10, vs.y - m - 40 - 170, lw, 160)
		c.draw_line(lr.position + Vector2(0, -22), lr.position + Vector2(lw, -22), INK, 1.5)
		en(lr.position + Vector2(0, -28), "SYSTEM LOG", 10, INK, 3.0)
		_log_light(lr, tlines, t, sz, sz + 7.0)
		var rw: float = minf(300.0, vs.x - cen.x - R - 80 - m)
		var rx: float = vs.x - m - 10 - rw
		var ry: float = cen.y - 40
		c.draw_line(Vector2(rx, ry - 22), Vector2(rx + rw, ry - 22), INK, 1.5)
		en(Vector2(rx, ry - 28), "TELEMETRY", 10, INK, 3.0)
		var yy: float = ry
		for row in [["同步", "%.1f%%" % (floorf(p * 1000.0) / 10.0)], ["模块", "%d / %d" % [st.n, st.total]], ["接触", "%d" % contacts.size()], ["阶段", str(st.label)]]:
			mono(Vector2(rx, yy), str(row[0]), sz, GRAY)
			mono(Vector2(rx + sz * 3.4, yy), str(row[1]), sz, INK)
			yy += sz + 12.0
		var brk := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_GRAPHEME_BOUND | TextServer.BREAK_ADAPTIVE
		en(Vector2(rx, yy + 14), "NOTE", 10, GRAY, 3.0)
		c.draw_multiline_string(font, Vector2(rx, yy + 34), st.tip, HORIZONTAL_ALIGNMENT_LEFT, rw, sz - 1, -1, Color(0.25, 0.27, 0.3, st.tip_a), brk)
	else:
		var lr3 := Rect2(m + 10, cen.y + R + 84, vs.x - 2 * m - 20, vs.y * 0.24)
		c.draw_line(lr3.position + Vector2(0, -22), lr3.position + Vector2(lr3.size.x, -22), INK, 1.5)
		en(lr3.position + Vector2(0, -28), "SYSTEM LOG", 10, INK, 3.0)
		_log_light(lr3, tlines, t, sz, sz + 7.0)
	txt(Vector2(0, vs.y - (12.0 if not compact else 6.0)), "明日方舟同人作品 · 非商业 · 与鹰角网络无关", 11, GRAY, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	# 读到最后：整屏渐暗成深海色，接深海水母标题页
	var dk: float = clampf((p - 0.93) / 0.07, 0.0, 1.0)
	if dk > 0.0:
		c.draw_rect(Rect2(Vector2.ZERO, vs), Color(DEEP, 0.92 * dk))


## 浅色版日志：墨黑字、灰时间戳、完成 OK 墨黑、在读的一行青色光标
func _log_light(r: Rect2, lines: Array, t: float, sz: int, lh: float) -> void:
	var nmax: int = maxi(1, int(r.size.y / lh))
	var start: int = maxi(0, lines.size() - nmax)
	var y: float = r.position.y + sz
	for i in range(start, lines.size()):
		var ln: Dictionary = lines[i]
		var cur: bool = ln.get("cur", false) and not ln.ok
		var x: float = r.position.x
		x += mono(Vector2(x, y), "%06.2f" % float(ln.t), sz, GRAY) + sz * 0.9
		var body: String = str(ln.s)
		var room: float = r.end.x - x - mono_w("OK", sz) - sz * 1.2
		if mono_w(body, sz) > room:
			while body.length() > 1 and mono_w(body + "…", sz) > room:
				body = body.substr(0, body.length() - 1)
			body += "…"
		var bw: float = mono(Vector2(x, y), body, sz, INK if (cur or ln.ok) else GRAY)
		var dx0: float = x + bw + sz * 0.6
		var dx1: float = r.end.x - mono_w("OK", sz) - sz * 0.6
		if dx1 > dx0:
			mono(Vector2(dx0, y), ".".repeat(int((dx1 - dx0) / (sz * 0.6))), sz, PALE)
		var tag: String = "OK" if ln.ok else (("_" if cursor_on(t) else "") if cur else "..")
		mono(Vector2(r.end.x - mono_w("OK", sz), y), tag, sz, ACC if cur else (INK if ln.ok else GRAY))
		y += lh
