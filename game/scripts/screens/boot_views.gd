extends RefCounted
const Loc = preload("res://scripts/core/loc.gd")   # 本地化（docs/276 §10）
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
var last_cp := Vector2.ZERO   # 方向 3 最后一个接触点（「开始游戏」出现时从这里拉引线，draw_start）
var has_cp := false


func _init(ctl: Control, f: Font) -> void:
	c = ctl
	font = f


# ================================================================ 共用小件

func _rm() -> bool:
	return Cfg.reduce_motion


## 等宽字：拉丁 / 数字按 0.6 字宽、中文按 1 字宽逐字画（项目只有一套 UI 字体）
func mono(pos: Vector2, s: String, sz: int, col: Color) -> float:
	s = Loc.s(s)   # 本地化（docs/276 §10）：逐字画之前整串查表
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
	s = Loc.s(s)   # 本地化（docs/276 §10）：逐字画之前整串查表
	var w := 0.0
	for ch in s:
		w += sz * (1.0 if ch.unicode_at(0) > 0x2E80 else 0.6)
	return w


func en(pos: Vector2, s: String, sz: int, col: Color, sp := 3.0) -> float:
	s = Loc.s(s)   # 本地化（docs/276 §10）：逐字画之前整串查表
	var x := pos.x
	for ch in s:
		c.draw_string(font, Vector2(x, pos.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x + sp
	return x - pos.x - sp


func txt(pos: Vector2, s: String, sz: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	c.draw_string(font, pos, Loc.s(s), align, w, sz, col)


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
	c.draw_multiline_string(font, r.position + Vector2(0, 30), Loc.s(tip), HORIZONTAL_ALIGNMENT_LEFT, r.size.x, sz, -1, Color(0.7, 0.78, 0.8, ta), brk)


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
## 终端版式（参考图的浅灰底墨黑线，10-31 改成深海底浅色线）——只在「正在进行」处点一点青；圈心是本作徽记（菱形 + 一道浪，不用官方标志）里写百分比。
## 同日用户「PRTS 不用放在后面，可以增加一点几何的动效」：去掉盘后的空心大字，加几何动效（_net 右上网格按进度连线、_geo 反向慢转的菱形框与绕圈小三角）。
## 声呐接触点 = 真实加载项：系统日志里的每一项（编译类别 / 阶段）一个点（按行的 key 定方位与距离），读到时出现、扫描扇面扫过时闪亮，读满变实心；
## 外圈 72 刻度仍是总进度。右上一片低多边形网格，左下系统日志、右侧读数，底部字距拉开的 RHODES ISLAND 与版本行。
## 读到最后（进度 > 93%）整屏再压暗一点，接深海水母标题页
## 10-31 用户「不要用浅色的，这样的话和后面的差距太大了」：版式不变，配色反过来——深海底、浅色线条与字、青色只点在进行中
const PBG := Color(0.024, 0.043, 0.063)
const INK := Color(0.87, 0.92, 0.94)
const GRAY := Color(0.44, 0.53, 0.58)
const PALE := Color(0.15, 0.22, 0.27)
const ACC := Color(0.369, 0.902, 0.902)
const DEEP := Color(0.02, 0.05, 0.08)


func _h1(s: String, k: int) -> float:
	return fposmod(sin(float(s.hash() % 100000) * 0.731 + k * 12.9898) * 43758.5453, 1.0)


## 打字机：新行在出现后 0.35 秒内逐字打出（减少动态效果时整行直接出）
func _typed(s: String, age: float) -> String:
	if _rm() or age >= 0.35:
		return s
	return s.substr(0, int(ceil(s.length() * age / 0.35)))


func _mono_c(pos: Vector2, s: String, sz: int, col: Color) -> void:
	s = Loc.s(s)   # 本地化（docs/276 §10）：逐字画之前整串查表
	mono(pos - Vector2(mono_w(s, sz) / 2.0, 0), s, sz, col)


## 字距拉开的英文（居中）
func _spaced(cx: float, y: float, s: String, sz: int, col: Color, sp: float) -> void:
	s = Loc.s(s)   # 本地化（docs/276 §10）：逐字画之前整串查表
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
		c.draw_line(a, a.lerp(b, f), Color(PALE.lightened(0.12), 0.95), 1.0, true)
		if f < 1.0:
			c.draw_rect(Rect2(a.lerp(b, f) - Vector2(2, 2), Vector2(4, 4)), ACC)   # 正在连的那一端
	for q2 in pts:
		c.draw_rect(Rect2(q2 - Vector2(2, 2), Vector2(4, 4)), PALE.lightened(0.25))


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
		if nm == "done":   # 「接入完成」钉在 180 方位：「开始游戏」的引线从它竖直落到按钮上（draw_start）
			a = PI / 2.0
			rr = R * 0.8
		var cp: Vector2 = cen + Vector2.from_angle(a) * rr
		# 扇面扫过就亮（10-31 用户「声呐上面不应该随着转的时候闪烁吗」）：扫到的一刻最亮 + 光晕，之后大半圈里渐暗到 0.25，等下一圈再亮
		var since: float = fposmod(ang - a, TAU) / TAU   # 扇面扫过后 0 → 1
		var hi: float = 1.0 if _rm() else pow(clampf(1.0 - since * 1.4, 0.0, 1.0), 2.0)
		var lv: float = 1.0 if _rm() else 0.25 + 0.75 * hi
		var kc: Color = INK if ct.done else ACC
		if hi > 0.02 and not _rm():
			c.draw_circle(cp, 4.0 + 7.0 * hi, Color(kc, 0.18 * hi))   # 光晕
			c.draw_arc(cp, 6.0 + 10.0 * (1.0 - hi), 0, TAU, 16, Color(kc, 0.6 * hi), 1.0, true)
		var sz2: float = 3.0 + 1.5 * hi
		if ct.done:
			c.draw_rect(Rect2(cp - Vector2(sz2, sz2), Vector2(sz2, sz2) * 2.0), Color(INK, lv))
		else:
			c.draw_rect(Rect2(cp - Vector2(sz2 + 1, sz2 + 1), Vector2(sz2 + 1, sz2 + 1) * 2.0), Color(ACC, lv), false, 1.5)
			c.draw_rect(Rect2(cp - Vector2(1.5, 1.5), Vector2(3, 3)), Color(ACC, maxf(lv, 0.6)))
		mono(cp + Vector2(8, -5), "%02d" % int(ct.i), 9, Color(GRAY, 0.4 + 0.6 * lv))
		last_cp = cp
	has_cp = not contacts.is_empty()
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
	# 字放进菱形里（11-01 UI 巡检二轮：「100.0%」原先压到菱形两侧边）：按最宽的「100.0%」量，字高处菱形宽度留 8% 余量
	while big > 10 and mono_w("100.0%", big) > 2.0 * (er - big * 0.45) * 0.92:
		big -= 1
	var pct := "%.1f%%" % (floorf(p * 1000.0) / 10.0)
	_mono_c(cen + Vector2(0, big * 0.3), pct, big, INK)
	# 盘下：字距拉开的 RHODES ISLAND（读完等玩家开始时，这里让给「开始游戏」）
	if not st.get("ready", false) or port:
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
		c.draw_multiline_string(font, Vector2(rx, yy + 34), Loc.s(st.tip), HORIZONTAL_ALIGNMENT_LEFT, rw, sz - 1, -1, Color(0.66, 0.74, 0.77, st.tip_a), brk)
	else:
		var lr3 := Rect2(m + 10, cen.y + R + 84, vs.x - 2 * m - 20, vs.y * 0.24)
		c.draw_line(lr3.position + Vector2(0, -22), lr3.position + Vector2(lr3.size.x, -22), INK, 1.5)
		en(lr3.position + Vector2(0, -28), "SYSTEM LOG", 10, INK, 3.0)
		_log_light(lr3, tlines, t, sz, sz + 7.0)
	txt(Vector2(0, vs.y - (12.0 if not compact else 6.0)), "明日方舟同人作品 · 非商业 · 与鹰角网络无关", 11, GRAY, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	# 读到最后：整屏渐暗成深海色，接深海水母标题页
	var dk: float = clampf((p - 0.93) / 0.07, 0.0, 1.0)
	if dk > 0.0:
		c.draw_rect(Rect2(Vector2.ZERO, vs), Color(DEEP, 0.6 * dk))


## 读完后的「开始游戏」放在哪（11-01：读完不自动进标题页，等玩家点 / 按任意键）。方向 0 在声呐圈下的说明行，方向 3 横屏占盘下 RHODES ISLAND 的位置，竖屏与方向 1 / 2 放底部
func start_rect(v: int, vs: Vector2) -> Rect2:
	var compact: bool = vs.y <= 520.0
	var bw: float = 232.0 if not compact else 200.0
	var bh: float = 50.0 if not compact else 42.0
	var cy: float = vs.y - (96.0 if not compact else 64.0)
	if v == 0:
		var w0: float = minf(400.0, minf(vs.y * 0.52, vs.x * 0.6))
		cy = vs.y * 0.45 + 210.0 * w0 / 420.0 + 36.0
	elif v == 4:
		cy = minf(vs.y * 0.80, vs.y - 60.0 - bh * 0.5)   # PRTS 认证终端：读完后占进度条的位置
	elif v == 3 and vs.y <= vs.x:
		var R: float = minf(vs.y * 0.27, vs.x * 0.2)
		cy = vs.y * 0.5 + R + 62.0 + bh * 0.5   # 让开 180 方位读数
		cy = minf(cy, vs.y - 26.0 - bh * 0.5)   # 不压页脚声明
	return Rect2(vs.x * 0.5 - bw * 0.5, cy - bh * 0.5, bw, bh)


## 「开始游戏」动效（11-01 用户「加载页开始游戏的动效也做一下」，网页同款在 loader.js / loader.css .sy-go）：
##   出现（约 1.25 秒）：从最后一个接触点（「接入完成」）拉一条青色引线到按钮上沿 → 四角饰角从外收拢锁定 → 竖扫描线左到右揭开底色
##     → 边框从上沿正中向两边描出 → 四个字先乱码再逐个解出 → 下一行英文打字机出现；
##   待机：框线慢呼吸 + 一小段青光沿边框慢转一圈 5.5 秒，左右两枚小方框反向慢转；
##   悬停 / 手柄聚焦（h 0–1）：边框收紧 3 像素、饰角外扩并伸出 L 形短臂、外圈青色微光；
##   按下（press 秒）：瞬间反白（墨色底深色字）+ 整屏一下压暗 + 三圈声呐脉冲从按钮扩散到整屏，0.28 秒后交叉淡出揭开标题页。
## 减少动态效果：只淡入、不乱码、不转、不发脉冲（反白保留）。
## st：u = 读完后的秒数（出现时间轴）、t、h、press（-1 = 没按）、touch
func draw_start(r: Rect2, st: Dictionary) -> void:
	var u: float = st.u
	var t: float = st.t
	var h: float = st.h
	var pv: float = st.press
	var rm := _rm()
	var vs: Vector2 = c.size
	var e: float = clampf(u / 0.25, 0.0, 1.0) if rm else 1.0
	var pf := 0.0   # 反白 1 → 0
	if pv >= 0.0:
		pf = 1.0 if pv < 0.08 else clampf(1.0 - (pv - 0.08) / 0.16, 0.0, 1.0)
	var rr := r.grow(-3.0 * maxf(h, pf))
	var cen := rr.get_center()
	# ---- 按下：整屏压暗 + 声呐脉冲（画在按钮下面）
	if pv >= 0.0:
		c.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.0, 0.01, 0.02, 0.42 * clampf(1.0 - pv / 0.5, 0.0, 1.0)))
		if not rm:
			var diag: float = vs.length()
			for j in 3:
				var q: float = (pv - j * 0.1) / 0.85
				if q <= 0.0 or q >= 1.0:
					continue
				var rad: float = lerpf(rr.size.y * 0.5, diag, _ease(q))
				var al: float = pow(1.0 - q, 1.6) * (1.0 if j == 0 else 0.5)
				if j == 0:
					c.draw_arc(cen, rad - 7.0, 0.0, TAU, 160, Color(ACC, 0.1 * al), 12.0, true)
				c.draw_arc(cen, rad, 0.0, TAU, 160, Color(ACC, 0.6 * al), 2.0 if j == 0 else 1.0, true)
	# ---- 出现：从最后一个接触点引线过来（方向 3），接触点上一个收拢的锁定框
	if has_cp and not rm and u < 1.4 and vs.x >= vs.y:   # 竖屏盘下是系统日志，不拉引线
		var top := Vector2(cen.x, rr.position.y)
		var f := _ph(u, 0.0, 0.25)
		var fa: float = 1.0 - _ph(u, 0.75, 1.4)
		var hd: Vector2 = last_cp.lerp(top, _ease(f))
		c.draw_line(last_cp, hd, Color(ACC, 0.6 * fa), 1.0, true)
		c.draw_rect(Rect2(hd - Vector2(2, 2), Vector2(4, 4)), Color(ACC, fa))
		var lk: float = 6.0 + 10.0 * (1.0 - _ease(_ph(u, 0.0, 0.2)))
		c.draw_rect(Rect2(last_cp - Vector2(lk, lk), Vector2(lk, lk) * 2.0), Color(ACC, 0.85 * fa), false, 1.0)
	# ---- 悬停微光
	if h > 0.0:
		for i in 3:
			c.draw_rect(rr.grow(2.0 + i * 3.0), Color(ACC, 0.09 * h * (1.0 - i / 3.0)), false, 3.0)
	# ---- 底色：竖扫描线左 → 右揭开
	var sf := _ph(u, 0.3, 0.6)
	if rm:
		sf = 1.0
	if sf > 0.0:
		var fr := Rect2(rr.position, Vector2(rr.size.x * sf, rr.size.y))
		c.draw_rect(fr, Color(0.02, 0.05, 0.07, 0.86 * e))
		if h > 0.0:
			c.draw_rect(fr, Color(ACC, 0.12 * h))
		if sf < 1.0:
			c.draw_rect(Rect2(Vector2(fr.end.x - 16.0, rr.position.y), Vector2(16.0, rr.size.y)), Color(ACC, 0.12))
			c.draw_line(Vector2(fr.end.x, rr.position.y - 7.0), Vector2(fr.end.x, rr.end.y + 7.0), Color(ACC, 0.9), 1.5)
	if pf > 0.0:
		c.draw_rect(rr, Color(INK, 0.94 * pf))
	# ---- 边框：从上沿正中向两边描出；描完后待机呼吸 + 一段青光沿边慢转
	var P: float = 2.0 * (rr.size.x + rr.size.y)
	var bf := _ph(u, 0.35, 0.8)
	var br: float = 1.0 if rm else 0.62 + 0.38 * (0.5 + 0.5 * sin(t * 2.6))
	if rm or bf >= 1.0:
		c.draw_rect(rr, Color(ACC, lerpf(0.55 * br + 0.2, 0.95, h) * e), false, 1.5)
		if not rm:
			var s0: float = fposmod(t * P / 5.5, P)
			var fl := Color(ACC, 0.9 * (1.0 - pf))
			var seg := _perim(rr, s0, minf(s0 + 44.0, P))
			if seg.size() >= 2:
				c.draw_polyline(seg, fl, 2.0, true)
			if s0 + 44.0 > P:
				var seg2 := _perim(rr, 0.0, s0 + 44.0 - P)
				if seg2.size() >= 2:
					c.draw_polyline(seg2, fl, 2.0, true)
	elif bf > 0.0:
		var half: float = P * 0.5 * _ease(bf)
		var a1 := _perim(rr, 0.0, half)
		var a2 := _perim(rr, P - half, P)
		for pl in [a1, a2]:
			if (pl as PackedVector2Array).size() >= 2:
				c.draw_polyline(pl, Color(INK, 0.85), 1.5, true)
		for hp in [a1[a1.size() - 1] if a1.size() > 0 else cen, a2[0] if a2.size() > 0 else cen]:
			c.draw_rect(Rect2(hp - Vector2(2, 2), Vector2(4, 4)), ACC)
	# ---- 四角饰角：从外收拢锁定；悬停外扩 + L 形短臂；锁定那一下外框闪一圈
	var cf := _ph(u, 0.1, 0.45)
	if rm:
		cf = 1.0
	var off: float = 16.0 * (1.0 - _ease(cf)) + 5.0 * h
	if not rm and u >= 0.45 and u < 0.7:
		var lf: float = (u - 0.45) / 0.25
		c.draw_rect(rr.grow(2.0 + 8.0 * lf), Color(ACC, 0.4 * (1.0 - lf)), false, 1.0)
	for k in 4:
		var sx: float = -1.0 if k == 0 or k == 3 else 1.0
		var sy: float = -1.0 if k < 2 else 1.0
		var p: Vector2 = [rr.position, Vector2(rr.end.x, rr.position.y), rr.end, Vector2(rr.position.x, rr.end.y)][k] + Vector2(sx, sy) * off
		var d: float = 4.0 + 1.5 * h
		var cc := Color(ACC, cf * e)
		c.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0)]), cc)
		if h > 0.0:
			c.draw_line(p + Vector2(-sx * 6.0, 0), p + Vector2(-sx * (6.0 + 12.0 * h), 0), cc, 1.5)
			c.draw_line(p + Vector2(0, -sy * 6.0), p + Vector2(0, -sy * (6.0 + 9.0 * h)), cc, 1.5)
	# ---- 左右两枚小方框（待机反向慢转）
	var ia: float = _ph(u, 0.75, 1.0) * e
	if rm:
		ia = e
	for side in [-1.0, 1.0]:
		var pc := Vector2(cen.x + side * (rr.size.x * 0.5 - 20.0), cen.y)
		var an: float = PI / 4.0 + (0.0 if rm else t * 0.9 * side)
		var sq := PackedVector2Array()
		for q in 5:
			sq.append(pc + Vector2.from_angle(an + q * PI / 2.0) * 5.0)
		var ic := Color(ACC, 0.8 * ia).lerp(Color(PBG, ia), pf)
		c.draw_polyline(sq, ic, 1.2, true)
		c.draw_rect(Rect2(pc - Vector2(1, 1), Vector2(2, 2)), ic)
	# ---- 字：先乱码、再逐个解出（反白时字变深色）
	var fs: int = 20 if r.size.y >= 46.0 else 18
	var lab := "开始游戏"
	var lw: float = font.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x: float = cen.x - lw * 0.5
	var base_y: float = cen.y + fs * 0.36
	var tc: Color = Color(TEXT, e).lerp(Color(PBG, 1.0), pf)
	for i in lab.length():
		var ch: String = lab[i]
		var cw: float = font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if rm or u >= 0.62 + 0.08 * i:
			c.draw_string(font, Vector2(x, base_y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tc)
		elif u >= 0.45:
			var g: String = SCR[int(_h1(ch, int(u * 24.0)) * SCR.length()) % SCR.length()]
			var gs: int = int(fs * 0.8)
			var gw: float = font.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, gs).x
			c.draw_string(font, Vector2(x + (cw - gw) * 0.5, base_y - 1.0), g, HORIZONTAL_ALIGNMENT_LEFT, -1, gs, Color(ACC, 0.85))
		x += cw
	# ---- 下一行英文：打字机（矮屏放不下就不写，别压页脚声明）
	var hint := "TAP TO START" if st.touch else "PRESS ANY KEY"
	if rr.end.y + 24.0 < vs.y - 22.0:
		var hf: float = 1.0 if rm else _ph(u, 0.9, 1.25)
		if hf > 0.0:
			var hw := 0.0
			for ch in hint:
				hw += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 4.0
			en(Vector2(cen.x - (hw - 4.0) * 0.5, r.end.y + 20.0), hint.substr(0, int(ceil(hint.length() * hf))), 10, Color(GRAY, e * (0.55 + 0.45 * br) * (1.0 - pf)), 4.0)


const SCR := "0123456789ABCDEF#/<>+="

func _ph(u: float, a0: float, a1: float) -> float:
	return clampf((u - a0) / (a1 - a0), 0.0, 1.0)


func _ease(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)


## 按钮边框上弧长 s0–s1 的一段（从上沿正中起顺时针）
func _perim(r: Rect2, s0: float, s1: float) -> PackedVector2Array:
	var tc := Vector2(r.get_center().x, r.position.y)
	var cs: Array = [tc, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position, tc]
	var out := PackedVector2Array()
	var acc := 0.0
	for k in 5:
		var a: Vector2 = cs[k]
		var b: Vector2 = cs[k + 1]
		var L: float = a.distance_to(b)
		var lo: float = clampf((s0 - acc) / L, 0.0, 1.0)
		var hi: float = clampf((s1 - acc) / L, 0.0, 1.0)
		if hi > lo:
			var p0: Vector2 = a.lerp(b, lo)
			if out.is_empty() or out[out.size() - 1] != p0:
				out.append(p0)
			out.append(a.lerp(b, hi))
		acc += L
	return out



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


# ================================================================ 方向 4：PRTS 认证终端（11-05 用户「codex 的加载页可以替换我们目前的加载页」）
## 起点是 Codex 演示 docs/reference/prts-entry-1105；同日用户「多余的几何标志可以去掉，图标改成呼吸，要跟局内 PRTS 的感觉对齐」，
## 改成局内指挥台的语言：白细线 + 刻度环 + 青色只表示「在走 / 完成」。删掉阶梯三角、环绕碎线、两侧流线、上下游标刻度、扫描线。
## 罗德岛标志淡入后慢呼吸（2.6 秒一次）；外圈 60 格刻度环 = 进度（同指挥台头像的终结技环，st.p 亮到哪格就是哪格，当前格青色）；
## 读完（st.ready）整圈转青、一道细圈外扩一次，「认证通过」，下面出「开始游戏」（draw_start）。没有任何定时推进度。
## 同日三改（用户「有点素了，没有那种科技感和几何感还有呼吸感」）：几何全部围着刻度环成套、不散落——外圈细环 + 两组反向慢转弧段、
## 四方位菱形节点 + 方位读数、标志后一个大淡三角（呼应标志）、贯穿环两侧的水平细线 + 一道青光往外走；淡点阵 + 扫描纹；
## 呼吸统一 2.6 秒：标志、背后光晕、大三角、未亮刻度同相起伏。减少动态时全部静止。
const P_BG := Color(0.059, 0.063, 0.075)      # #0F1013
const P_TXT := Color(0.925, 0.933, 0.941)     # #ECEEF0（同指挥台 WHITE）
const P_SUB := Color(0.573, 0.592, 0.627)     # #9297A0
const P_ACC := Color(0.212, 0.886, 0.863)     # #36E2DC
const P_RULE := Color(0.208, 0.224, 0.263)    # #353943
const RhodesLogo = preload("res://scripts/screens/rhodes_logo.gd")
const UIMo = preload("res://scripts/ui_motion.gd")


func _box(x: float, y: float, w: float, h: float, col: Color, a := 1.0) -> void:
	c.draw_rect(Rect2(roundf(x), roundf(y), ceilf(w), ceilf(h)), Color(col.r, col.g, col.b, col.a * a))


## 栏目标题：左边一道 18×2 白短杠 + 白字（同属性栏 v3 的栏目头）+ 下面一条细线
func _p4_head(x: float, y: float, s: String, k: float, rw: float) -> void:
	_box(x, y - 6.0 * k, 18.0 * k, 2.0, P_TXT)
	txt(Vector2(x + 26.0 * k, y), s, int(round(13.0 * k)), P_TXT)
	_box(x, y + 12.0 * k, rw, 1, P_RULE)


func draw_v4(vs: Vector2, st: Dictionary) -> void:
	var t: float = st.t
	var rm: bool = _rm() or UIMo.skip_all()   # 减少动态 / 无头截图：直接终态
	var p: float = st.p
	var ready: bool = st.ready
	var u: float = float(st.get("u", -1.0))   # 读完后的秒数（-1 = 没读完）
	var w: float = vs.x
	var h: float = vs.y
	var k: float = clampf(h / 540.0, 0.8, 2.4)   # 以 960×540 为基准的缩放
	var cx: float = w / 2.0
	var cy: float = h * 0.42
	_box(0, 0, w, h, P_BG)
	var tt: float = 0.0 if rm else t
	var br: float = 1.0 if rm else 0.5 + 0.5 * cos(t * TAU / 2.6)   # 呼吸相位（1 = 最亮）
	var gx := 0.0
	while gx < w:   # 淡点阵
		var gy := 0.0
		while gy < h:
			_box(gx, gy, 1, 1, P_SUB, 0.12)
			gy += 24.0 * k
		gx += 24.0 * k
	var sy := 0.0
	while sy < h:   # 扫描纹
		_box(0, sy, w, 1, Color.BLACK, 0.12)
		sy += 3.0
	var m: float = 22.0 * k
	# 页眉：同局内的克制版式（白字 + 灰字 + 一条细线）
	mono(Vector2(m, 28.0 * k), "PRTS", int(round(12.0 * k)), P_TXT)
	mono(Vector2(m + mono_w("PRTS  ", int(round(12.0 * k))), 28.0 * k), "/ 启动校验", int(round(12.0 * k)), P_SUB)
	var fan := "ARKNIGHTS FAN GAME"
	mono(Vector2(w - m - mono_w(fan, int(round(11.0 * k))), 28.0 * k), fan, int(round(11.0 * k)), P_SUB)
	_box(m, 40.0 * k, w - 2.0 * m, 1, P_RULE)
	var tclk := "SYS 1105 · T+%05.1f" % t
	mono(Vector2(cx - mono_w(tclk, int(round(10.0 * k))) / 2.0, 28.0 * k), tclk, int(round(10.0 * k)), Color(P_SUB, 0.8))
	# 标志：淡入 0.4 秒，之后慢呼吸；读完停在最亮
	var s: float = maxf(1.0, floorf(h * 0.34 / 120.0))
	var span: float = 120.0 * s
	var fade: float = 1.0 if rm else _ease(t / 0.4)
	var R0: float = span * 0.66
	var C := Vector2(cx, cy)
	# 背后：光晕（同心淡圆叠出来）+ 大淡三角（外接圆 = 1.5 倍环），都随呼吸
	var gl: float = (0.6 + 0.4 * br) * fade
	var hs: float = 0.94 + 0.1 * br   # 大光晕随呼吸缩放（11-05 用户「整个界面缺少一点呼吸感」）
	for j in 6:
		c.draw_circle(C, R0 * (1.25 - j * 0.17) * hs, Color(P_ACC, 0.016 * gl))
	var rb: float = 1.0 if ready else 0.8 + 0.2 * br   # 刻度环 / 外圈整体明暗
	var tri := PackedVector2Array()
	for a3 in [-90.0, 30.0, 150.0, -90.0]:
		tri.append(C + Vector2.from_angle(deg_to_rad(a3)) * R0 * 1.5)
	c.draw_polyline(tri, Color(P_TXT, (0.05 + 0.05 * br) * fade), 1.0, true)
	# 水平细线贯穿环两侧（让开侧栏），一道青光往外走
	var hx0: float = cx - R0 - 46.0 * k
	var hx1: float = cx + R0 + 46.0 * k
	var hl: float = (w * 0.5 - 200.0 * k) if w > 760.0 else (w * 0.5 - 10.0)
	_box(cx - hl, cy, hx0 - (cx - hl), 1, P_RULE)
	_box(hx1, cy, cx + hl - hx1, 1, P_RULE)
	for e in [cx - hl, cx + hl]:
		_box(e - 1.5, cy - 1.0, 3, 3, P_SUB)
	if not ready or rm:
		# 青光从环边淡入 → 往外走 → 到头淡出 → 停一拍（11-05 用户「两侧加载的那个直接跳回原点显得很奇怪」）
		var ph: float = fposmod(tt / 2.6, 1.0)
		var mv: float = clampf(ph / 0.8, 0.0, 1.0)
		var ra: float = clampf(mv / 0.15, 0.0, 1.0) * clampf((1.0 - mv) / 0.25, 0.0, 1.0) * (1.0 if ph < 0.8 else 0.0)
		if rm:
			ra = 0.0
		var run: float = _ease(mv) * (hl - (hx1 - cx) - 26.0 * k)
		_box(hx1 + run, cy, 26.0 * k, 1, P_ACC, 0.8 * ra)
		_box(hx0 - run - 26.0 * k, cy, 26.0 * k, 1, P_ACC, 0.8 * ra)
	var breath: float = 1.0 if (rm or ready) else 0.72 + 0.28 * (0.5 + 0.5 * cos(t * TAU / 2.6))
	RhodesLogo.draw_bands(c, Vector2(roundf(cx - span / 2.0), roundf(cy - span / 2.0)), s, 120, func(_b): return 0.0, Color(1, 1, 1, fade * breath))
	# 刻度环 = 进度（60 格，每 5 格一根长的；亮到 st.p，当前格青色；读完整圈青）
	var R: float = span * 0.66
	var lit: int = int(floor(p * 60.0))
	for i in 60:
		var a: float = -PI / 2.0 + TAU * i / 60.0
		var major: bool = i % 5 == 0
		var l: float = (9.0 if major else 5.0) * k
		var col: Color
		if ready:
			col = Color(P_ACC, 0.9)
		elif i < lit:
			col = Color(P_TXT, 0.85)
		elif i == lit:
			col = Color(P_ACC, 0.55 + 0.45 * br)   # 当前格随呼吸闪
		else:
			col = Color(P_SUB, 0.2 + 0.14 * br)
		var dir := Vector2.from_angle(a)
		c.draw_line(Vector2(cx, cy) + dir * R, Vector2(cx, cy) + dir * (R + l), Color(col, col.a * fade * (1.0 if i == lit else rb)), 2.0 if major else 1.5, true)
	c.draw_arc(Vector2(cx, cy), R - 6.0 * k, 0.0, TAU, 96, Color(P_SUB, 0.18 * fade), 1.0, true)
	# 外圈：细环 + 三段白弧顺转、两段青弧反转（慢）；四方位菱形节点 + 读数（下方让给状态字，只写上 / 左 / 右）
	var R2: float = R + 22.0 * k
	c.draw_arc(C, R2, 0.0, TAU, 128, Color(P_SUB, (0.1 + 0.12 * br) * fade), 1.0, true)
	for j in 3:
		var a0: float = tt * 0.16 + j * TAU / 3.0
		c.draw_arc(C, R2, a0, a0 + deg_to_rad(34.0), 24, Color(P_TXT, 0.5 * fade), 1.5, true)
	for j in 2:
		var a1: float = -tt * 0.28 + j * PI
		c.draw_arc(C, R2 + 7.0 * k, a1, a1 + deg_to_rad(14.0), 12, Color(P_ACC if not ready else P_TXT, 0.55 * fade), 2.0, true)
	var nd: float = 4.0 * k
	for j in 4:
		var np: Vector2 = C + Vector2.from_angle(-PI / 2.0 + j * PI / 2.0) * R2
		c.draw_colored_polygon(PackedVector2Array([np + Vector2(0, -nd), np + Vector2(nd, 0), np + Vector2(0, nd), np + Vector2(-nd, 0)]), Color(P_TXT if j != 2 else P_SUB, 0.7 * fade))
	var fs9: int = int(round(9.0 * k))
	mono(Vector2(cx - mono_w("000", fs9) / 2.0, cy - R2 - 10.0 * k), "000", fs9, Color(P_SUB, fade))
	mono(Vector2(cx + R2 + 10.0 * k, cy - 6.0 * k), "090", fs9, Color(P_SUB, fade))
	mono(Vector2(cx - R2 - 10.0 * k - mono_w("270", fs9), cy - 6.0 * k), "270", fs9, Color(P_SUB, fade))
	if ready and not rm and u >= 0.0 and u < 0.5:
		var q: float = _ease(u / 0.5)
		c.draw_arc(Vector2(cx, cy), R + 14.0 * k + q * 40.0 * k, 0.0, TAU, 128, Color(P_ACC, 0.6 * (1.0 - q)), 1.5, true)
	# 环下：阶段 + 百分比（真实）；读完后换「认证通过」，再下面是「开始游戏」
	var ly: float = cy + R + 48.0 * k
	if not ready:
		txt(Vector2(0, ly), str(st.label), int(round(16.0 * k)), P_TXT, HORIZONTAL_ALIGNMENT_CENTER, w)
		var pct := "ARCHIVE INDEX  %03d%%" % int(floor(p * 100.0))
		txt(Vector2(0, ly + 20.0 * k), pct, int(round(10.0 * k)), P_SUB, HORIZONTAL_ALIGNMENT_CENTER, w)
		var file: String = str(st.get("file", ""))
		if file != "":
			txt(Vector2(0, ly + 36.0 * k), file, int(round(10.0 * k)), Color(P_SUB, 0.6), HORIZONTAL_ALIGNMENT_CENTER, w)
	else:
		txt(Vector2(0, minf(ly, start_rect(4, vs).position.y - 18.0)), "认证通过", int(round(16.0 * k)), P_ACC, HORIZONTAL_ALIGNMENT_CENTER, w)
	# 两侧栏（宽屏）：左 = 真实阶段日志（最近 4 行），右 = 真实进度分项（白细线，同指挥台生命线）
	if w > 760.0:
		var lx: float = m
		var rx: float = w - m - 150.0 * k
		var py: float = 104.0 * k
		_p4_head(lx, py, "启动校验", k, 170.0 * k)
		var lines: Array = st.get("lines", [])
		var shown: Array = lines.slice(maxi(0, lines.size() - 4))
		for i in shown.size():
			var ln: Dictionary = shown[i]
			var yy: float = py + 35.0 * k + i * 24.0 * k
			var ok: bool = ln.ok
			_box(lx, yy - 4.0 * k, 3.0 * k, 3.0 * k, P_TXT if ok else (Color(P_ACC, 0.45 + 0.55 * br) if ln.get("cur", false) else P_RULE))
			txt(Vector2(lx + 12.0 * k, yy + 1.0 * k), str(ln.s), int(round(11.0 * k)), P_TXT if ok else P_SUB)
		_p4_head(rx, py, "资源索引", k, 150.0 * k)
		var n: int = int(st.get("n", 0))
		var total: int = maxi(1, int(st.get("total", 1)))
		var parts := [["SCRIPTS", float(n) / float(total)], ["SCENE", clampf((p - 0.88) / 0.04, 0.0, 1.0) if not ready else 1.0], ["WARMUP", clampf((p - 0.92) / 0.08, 0.0, 1.0) if not ready else 1.0]]
		for i in 3:
			var q2: float = parts[i][1]
			var yb: float = py + 38.0 * k + i * 32.0 * k
			mono(Vector2(rx, yb), str(parts[i][0]), int(round(10.0 * k)), P_SUB)
			_box(rx, yb + 8.0 * k, 150.0 * k, 1, P_RULE)
			_box(rx, yb + 7.5 * k, floorf(q2 * 150.0 * k), 2, P_TXT if q2 < 1.0 else P_ACC)
	mono(Vector2(m, h - 20.0 * k), "RHODES ISLAND", int(round(11.0 * k)), P_SUB)
	var acc := "ACCESS / GRANTED" if ready else "ACCESS / PENDING"
	mono(Vector2(w - m - mono_w(acc, int(round(11.0 * k))), h - 20.0 * k), acc, int(round(11.0 * k)), P_ACC if ready else Color(P_SUB, 0.6 + 0.4 * br))
	txt(Vector2(0, h - 20.0 * k), "明日方舟同人作品 · 非商业 · 与鹰角网络无关", int(round(10.0 * k)), Color(P_SUB.r, P_SUB.g, P_SUB.b, 0.7), HORIZONTAL_ALIGNMENT_CENTER, w)
