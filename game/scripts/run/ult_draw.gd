## 终结技画面层的绘制细节：舞台暗场、冲击帧（整屏白 + 黑剪影）、像素形（多边形 / 圆盘 / 碎片 / 粗线）、定格白（sf）、连携闪、收尾吸气、起手条。
## docs/286 §4 第三批从 run/ult.gd 原样拆出，行为不变：全部 static func，第一个参数 uv = ult 实例（成员经 uv.、常量 / 静态函数经 U.）；draw_world / draw_world_back 的分派与状态仍在 ult.gd。只画，不碰随机数与玩法。
extends RefCounted

const U = preload("res://scripts/run/ult.gd")
const Bal = preload("res://scripts/core/balance.gd")
const UPX = preload("res://scripts/run/ult_px_exusiai.gd")   # 转平面终结技画面（docs/262 §11，ult/px_plane）：kind = "pxfn" 的图形交给它画
const UM = preload("res://scripts/ui_motion.gd")
const A = preload("res://scripts/art.gd")
const IRP = preload("res://scripts/run/ult_px_ir.gd")   # 艾丽妮「宣判」转平面画面（docs/275，ult/px_plane_irene；只画）
const SDP = preload("res://scripts/run/ult_px_sd.gd")   # 斯卡蒂「斩浪」转平面画面（docs/246 §16，同开关；只画）
const MZP = preload("res://scripts/run/ult_px_mz.gd")   # 水月「水母群」转平面画面（docs/261 §8，ult/px_plane_mizuki；只画）


static func _draw_stage(uv: U, w) -> void:
	var g = uv.g
	var k: float = uv.stage_k()
	if k <= 0.0:
		return
	var c: Vector2 = g.ppos
	var R := Vector2(2400.0, 1600.0)
	w.tb_quad(c - R, c + Vector2(R.x, -R.y), c + R, c + Vector2(-R.x, R.y), Color(0.0, 0.0, 0.02, Bal.v("ult/stage_dim", 0.25) * k))
	w.tb_flush()
	if uv._stage_op == null or uv._stage_op.pos == Vector2.INF:
		return
	var pr: Dictionary = uv._stage_op.portrait()
	var t: Texture2D = g.tex.get(str(pr.get("tex", "")))
	if t == null:
		return
	var n: int = maxi(1, int(pr.get("frames", 1)))
	var fw: float = t.get_width() / float(n)
	var fh: float = float(t.get_height())
	var hi: float = A.hires_of(t)
	var s: float = g.PX / hi * lerpf(1.0, Bal.v("ult/stage_pop", 1.25), k)
	var flip: float = -1.0 if float(uv._stage_op.face) < 0.0 else 1.0
	var col: Color = U._col(uv._stage_op)
	for j in 2:   # 残影：往出手来的方向拖两层干员色
		var off: Vector2 = (g.ppos - uv._stage_op.pos).normalized() * (26.0 * (j + 1)) * k
		g.draw_set_transform(uv._stage_op.pos + off, 0.0, Vector2(s * flip, s))
		g.draw_texture_rect_region(t, Rect2(-fw * 0.5, -fh * 0.92, fw, fh), Rect2(0, 0, fw, fh), Color(col.r, col.g, col.b, 0.35 * k / (j + 1)))
	g.draw_set_transform(uv._stage_op.pos, 0.0, Vector2(s * flip, s))
	g.draw_texture_rect_region(t, Rect2(-fw * 0.5, -fh * 0.92, fw, fh), Rect2(0, 0, fw, fh), Color(1, 1, 1, k))
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _draw_hit_frame(uv: U, w) -> void:
	var g = uv.g
	if not uv._hf_on():
		return
	if uv._hf_serial != uv.serial and uv._imp_serial != uv.serial and uv._fin_on():
		uv.impact(uv.caster.pos if uv.caster != null else g.ppos)   # 高潮伤害全标了 pre 的招式（水月水母齐爆）：冲击帧起算这一刻补上 impact，收尾加强 / 冲击慢放才落得到这一下
	if uv._hf_serial != uv.serial and uv._fin_wait():
		return   # 收尾加强：吸气还没完，冲击帧两拍从「爆」那一刻起算
	var ha: Dictionary = uv.act if uv.act.get("hf", false) else uv._hf_tail
	# 每拍按真实时间 ult/hit_frame_t，且至少画满 2 帧（卡顿 / 录像时一帧超过一拍，按时间会把黑底那拍整个跳过）；
	# 按这次终结技（serial）只起算一次：反震 / 炮击会连着 impact 好几次，按 impact 重置会再闪一轮
	var ht: float = Bal.v("ult/hit_frame_t", 0.067)
	if uv._hf_serial != uv.serial:
		uv._hf_serial = uv.serial
		uv._hf_n = [0, 0]
		uv._hf_t0 = UM.now()
		var sx: Node = g.get_node_or_null("/root/Sfx") if g.is_inside_tree() else null
		if sx != null and sx.trace_on:   # 录屏对时间线：冲击帧第一拍（高潮音效要落在这一刻，docs/205 §4.2）
			sx.trace.append([Engine.get_process_frames(), "ultev:HF", 0.0, 1.0])
		if uv.caster != null and str(uv._aud(str(uv.caster.id)).get("hf_slot", "")) != "":   # 高潮音效直接挂冲击帧第一拍（ult_audio.json hf_slot）
			uv._ua(str(uv._aud(str(uv.caster.id)).hf_slot))
	var t: float = UM.now() - uv._hf_t0
	var inv: bool = t < ht or uv._hf_n[0] < 2   # 第 1 拍：白底黑剪影
	if not inv and uv._hf_n[1] >= 2 and t >= ht * 2.0:
		ha["hf"] = false   # 一次终结技只闪一次（维什戴尔后几排落地也会 impact）
		ha["hf_done"] = true
		return
	uv._hf_n[0 if inv else 1] += 1
	var bg := Color(0.92, 0.9, 0.86) if inv else Color(0.02, 0.02, 0.03)
	var hc: Array = ha.get("hf_cols", [])   # 招式自定两拍配色 [底 1, 剪影 1, 底 2, 剪影 2]（流明：冷暖反差，用户 10-31 不要纯白）
	if hc.size() == 4:
		bg = hc[0] if inv else hc[2]
	var c: Vector2 = g.ppos
	var R := Vector2(2600.0, 1700.0)
	w.tb_quad(c - R, c + Vector2(R.x, -R.y), c + R, c + Vector2(-R.x, R.y), bg)
	w.tb_flush()
	var fg := Color(0.0, 0.0, 0.0) if inv else Color(1.6, 1.6, 1.6)   # 黑底那拍：贴图保持本色提亮（乘 8 会把红压成粉）；程序斩线照样纯白
	if hc.size() == 4:
		fg = hc[1] if inv else hc[3]
	for s in uv.shapes:
		if s.age < 0.0 or not s.get("hf", false):
			continue
		if str(s.kind) == "pxfn":   # 转平面终结技画面（docs/262 §11）：按剪影色画
			w.tb_flush()
			UPX.draw(g, s, 1.0, Color(fg, 1.0))
			continue
		if str(s.kind) == "strip":
			var s2: Dictionary = s.duplicate()
			s2["col"] = Color(fg, 1.0)
			s2.erase("col1")
			s2.erase("fade")
			uv._draw_strip(w, s2, 1.0)
		else:
			var s3: Dictionary = s.duplicate()
			s3["glow"] = Color(fg, 1.0)
			_px_shape(uv, w, s3, 1.0, Color(fg.r, fg.g, fg.b) if (inv or hc.size() == 4) else Color.WHITE, 1.0)
	w.tb_flush()
	if IRP.on():
		IRP.of(g).draw_hf(uv, w, Color(fg.r, fg.g, fg.b) if (inv or hc.size() == 4) else Color.WHITE)   # 转平面（docs/275）：收尾斩击 + 主裂缝的剪影
	if SDP.on():
		SDP.of(g).draw_hf(uv, w, Color(fg.r, fg.g, fg.b) if (inv or hc.size() == 4) else Color.WHITE)   # 斯卡蒂：劈浪那一拍的立起层剪影
	if MZP.on():
		MZP.of(g).draw_hf(uv, w, Color(fg.r, fg.g, fg.b) if (inv or hc.size() == 4) else Color.WHITE)   # 转平面（docs/261 §8）：9 只海月水母剪影


static func _span(uv: U, w, y: float, x0: float, x1: float, G: float, col: Color) -> void:
	var a: float = floorf(x0 / G) * G
	var b: float = ceilf(x1 / G) * G
	if b - a < G * 0.5:
		return
	w.tb_quad(Vector2(a, y), Vector2(b, y), Vector2(b, y + G), Vector2(a, y + G), col)


## 任意多边形（奇偶填充）：逐行求与各边的交点，两两成段
static func _px_poly(uv: U, w, pts: PackedVector2Array, col: Color) -> void:
	if pts.size() < 3 or col.a <= 0.003:
		return
	var G: float = uv._pxg()
	var y0: float = INF
	var y1: float = -INF
	for p in pts:
		y0 = minf(y0, p.y)
		y1 = maxf(y1, p.y)
	var y: float = floorf(y0 / G) * G
	var n: int = pts.size()
	while y < y1:
		var yc: float = y + G * 0.5
		var xs: Array = []
		for i in n:
			var p: Vector2 = pts[i]
			var q: Vector2 = pts[(i + 1) % n]
			if (p.y <= yc and q.y > yc) or (q.y <= yc and p.y > yc):
				xs.append(p.x + (yc - p.y) * (q.x - p.x) / (q.y - p.y))
		xs.sort()
		var j := 0
		while j + 1 < xs.size():
			_span(uv, w, y, xs[j], xs[j + 1], G, col)
			j += 2
		y += G


static func _px_disc(uv: U, w, c: Vector2, ro: float, ri: float, col: Color) -> void:
	if ro <= 0.0 or col.a <= 0.003:
		return
	var G: float = uv._pxg()
	var y: float = floorf((c.y - ro) / G) * G
	while y < c.y + ro:
		var dy: float = y + G * 0.5 - c.y
		if absf(dy) < ro:
			var ho: float = sqrt(ro * ro - dy * dy)
			if ri > 0.0 and absf(dy) < ri:
				var hi: float = sqrt(ri * ri - dy * dy)
				_span(uv, w, y, c.x - ho, c.x - hi, G, col)
				_span(uv, w, y, c.x + hi, c.x + ho, G, col)
			else:
				_span(uv, w, y, c.x - ho, c.x + ho, G, col)
		y += G


## 碎裂冲击波（不画整圆环）：沿圆周撒像素块，块大小 / 半径按序号确定性抖动、约三成留空，越往后块越碎小
static func _px_frag(uv: U, w, c: Vector2, r: float, wd: float, col: Color, k: float) -> void:
	var G: float = uv._pxg()
	var n: int = clampi(int(TAU * r / (G * 5.0)), 8, 220)
	for i in n:
		var h: float = fposmod(sin(float(i) * 12.9898) * 43758.5453, 1.0)
		if h < 0.3:
			continue
		var p: Vector2 = c + Vector2.from_angle(TAU * (float(i) + h * 0.6) / n) * (r + (h - 0.65) * wd * 2.0)
		var sz: float = maxf(G, roundf(wd * (0.4 + 0.6 * h) * (0.5 + 0.5 * k) / G) * G)
		var q := Vector2(floorf(p.x / G) * G, floorf(p.y / G) * G)
		w.tb_quad(q, q + Vector2(sz, 0), q + Vector2(sz, sz), q + Vector2(0, sz), col)


static func _px_thick(uv: U, w, a: Vector2, b: Vector2, wd: float, col: Color) -> void:
	var d: Vector2 = (b - a).normalized().orthogonal() * maxf(uv._pxg(), wd) * 0.5
	_px_poly(uv, w, PackedVector2Array([a + d, b + d, b - d, a - d]), col)


static func _px_shape(uv: U, w, s: Dictionary, k: float, col: Color, dim: float) -> void:
	var G: float = uv._pxg()
	match str(s.kind):
		"circle":
			_px_disc(uv, w, s.c, float(s.r), 0.0, uv._pc(col, float(s.get("fill", 0.3)) * k * dim))
		"ring":
			var r: float = lerpf(float(s.get("r1", s.r)), float(s.r), clampf(s.age / maxf(0.001, s.max * 0.5), 0.0, 1.0))
			var wd: float = maxf(G, float(s.get("w", 3.0)))
			if s.get("frag", Bal.vi("ult/px_ring_frag", 1) > 0 and not s.get("solid", false)):   # 缺省碎裂（10-30「不用纯几何圆环当主体」）；solid = true 保留整环
				_px_frag(uv, w, s.c, r, wd, uv._pc(col, 0.85 * k * dim), k)
			else:
				_px_disc(uv, w, s.c, r + wd * 0.5, maxf(0.0, r - wd * 0.5), uv._pc(col, 0.85 * k * dim))
		"sector":
			var pts := PackedVector2Array([s.c])
			var a0: float = float(s.a) - float(s.half)
			for i in 21:
				pts.append(s.c + Vector2.from_angle(a0 + float(s.half) * 2.0 * i / 20.0) * float(s.r))
			_px_poly(uv, w, pts, uv._pc(col, float(s.get("fill", 0.3)) * k * dim))
		"band":
			_px_thick(uv, w, s.a, s.b, float(s.w), uv._pc(col, float(s.get("fill", 0.3)) * k * dim))
		"line":
			_px_thick(uv, w, s.a, s.b, float(s.get("w", 3.0)), uv._pc(col, 0.9 * k * dim))
		"blade":
			var gr: float = float(s.get("grow", 0.0))
			var gk: float = clampf(s.age / gr, 0.0, 1.0) if gr > 0.0 else 1.0
			var m: Vector2 = (s.a + s.b) * 0.5
			var ha: Vector2 = (s.a - m) * gk
			var nrm: Vector2 = (s.b - s.a).normalized().orthogonal()
			var fo: float = float(s.get("fo", 0.08))
			var fa: float = 1.0 if s.age < s.max - fo else maxf(0.0, (s.max - s.age) / fo)
			var bw: float = maxf(G, float(s.get("w", 8.0)))
			var gc: Color = s.get("glow", Color(0.45, 0.85, 1.0))
			_px_poly(uv, w, PackedVector2Array([m + ha, m + nrm * bw * 1.5, m - ha, m - nrm * bw * 1.5]), uv._pc(gc, 0.45 * fa * dim))
			_px_poly(uv, w, PackedVector2Array([m + ha, m + nrm * bw * 0.5, m - ha, m - nrm * bw * 0.5]), uv._pc(col, fa * dim))
		"rock":   # 熔岩块 / 碎岩：不规则多边形外壳 + 裂缝透光 + 芯（c、r、rot，col 外壳、glow 裂缝、core 芯；seed 定形状）
			var sd: float = float(s.get("seed", 1.0))
			var rot: float = float(s.get("rot", 0.0)) + float(s.get("spin", 0.0)) * s.age
			var rr: float = float(s.r)
			var fa: float = float(s.get("fill", 1.0)) * (1.0 if s.get("hold", true) else k) * dim
			var pts := PackedVector2Array()
			for i in 9:
				var h: float = fposmod(sin(sd * 7.13 + float(i) * 12.9898) * 43758.5453, 1.0)
				pts.append(s.c + Vector2.from_angle(rot + TAU * float(i) / 9.0) * rr * (0.72 + 0.28 * h))
			_px_poly(uv, w, pts, uv._pc(col, fa))
			if s.has("glow"):
				var gl: Color = uv._pc(s.glow, fa)
				for i in 3:
					var h2: float = fposmod(sin(sd * 3.7 + float(i) * 78.233) * 43758.5453, 1.0)
					var dd: Vector2 = Vector2.from_angle(rot + TAU * (float(i) + h2 * 0.5) / 3.0)
					_px_thick(uv, w, s.c + dd * rr * 0.15, s.c + dd * rr * (0.55 + 0.25 * h2), G * (2.0 if rr >= 24.0 else 1.0), gl)
				_px_disc(uv, w, s.c, rr * 0.3, 0.0, gl)
			if s.has("core"):
				_px_disc(uv, w, s.c, maxf(G, rr * 0.15), 0.0, uv._pc(s.core, fa))
		"ellipse":   # 地面影子 / 灼地：c、rx、ry
			var pe := PackedVector2Array()
			for i in 16:
				pe.append(s.c + Vector2(cos(TAU * i / 16.0) * float(s.rx), sin(TAU * i / 16.0) * float(s.ry)))
			_px_poly(uv, w, pe, uv._pc(col, float(s.get("fill", 0.3)) * (1.0 if s.get("hold", false) else k) * dim))
		"dots":
			var n: int = int(s.get("n", 12))
			var cc: Color = uv._pc(col, 0.9 * k * dim)
			for i in n:
				var ang: float = i * 2.39996
				var rr: float = float(s.r) * sqrt(float(i + 1) / n) * (0.6 + 0.4 * (1.0 - k))
				var p: Vector2 = s.c + Vector2.from_angle(ang) * rr
				var q: Vector2 = Vector2(floorf(p.x / G) * G, floorf(p.y / G) * G)
				w.tb_quad(q, q + Vector2(G * 2.0, 0), q + Vector2(G * 2.0, G * 2.0), q + Vector2(0, G * 2.0), cc)


static func _draw_sf(uv: U, w) -> void:
	var g = uv.g
	if uv._sf_rt <= 0.0 or uv._sf_ld == null or uv._sf_ld.pos == Vector2.INF:
		return
	var T: float = Bal.v("ult/sf_t", 0.35)
	var out: float = Bal.v("ult/sf_out", 0.2)
	var t: float = uv.sf_age()
	if t < 0.0 or t > T + out:
		return
	var rm: bool = Cfg.reduce_motion
	var k: float = 1.0 if t < T else 1.0 - (t - T) / out
	if rm:   # 减少动态效果：压暗淡入淡出
		k = minf(k, clampf(t / 0.12, 0.0, 1.0))
	var col: Color = U._col(uv._sf_ld)
	var c: Vector2 = uv._sf_ld.pos
	var R := Vector2(2400.0, 1600.0)
	var gc: Vector2 = g.ppos
	w.tb_quad(gc - R, gc + Vector2(R.x, -R.y), gc + R, gc + Vector2(-R.x, R.y), Color(0.0, 0.0, 0.02, Bal.v("ult/sf_dim", 0.7) * k))
	# 干员色放射速度线（往外流）：位置按序号哈希定，不抽随机数
	if not rm:
		var n: int = Bal.vi("ult/sf_lines", 28)
		if Cfg.mobile_web():
			n = maxi(4, n / 2)
		var G: float = uv._pxg()
		for i in n:   # 每条长短 / 粗细 / 速度 / 角度都打散（10-30 预审：等间距同长的线像重复矩形拼出来的）；尖头细尾
			var h1: float = fposmod(sin(float(i) * 12.9898) * 43758.5453, 1.0)
			var h2: float = fposmod(sin(float(i) * 78.233) * 12345.678, 1.0)
			var h3: float = fposmod(sin(float(i) * 39.425) * 24634.633, 1.0)
			var d: Vector2 = Vector2.from_angle(TAU * h3 + 0.35 * (h1 - 0.5))
			var spd: float = 900.0 + 1400.0 * h2
			var r0: float = 50.0 + fposmod(t * spd + h1 * 900.0, 860.0)
			var ln: float = 50.0 + 320.0 * h1 * h1
			var wd: float = G * (1.0 + floorf(h2 * 2.99))
			var lc: Color = col.lerp(Color.WHITE, 0.4 * h3)
			var a0: float = (0.25 + 0.5 * h2) * k
			var p0: Vector2 = c + d * r0
			_px_thick(uv, w, p0, p0 + d * ln * 0.35, wd, uv._pc(lc, a0))                         # 亮头
			_px_thick(uv, w, p0 + d * ln * 0.35, p0 + d * ln, maxf(G, wd - G), uv._pc(col, a0 * 0.55))   # 细尾
	w.tb_flush()
	# 队长：原亮度 + 一圈干员色轮廓光（画在压暗层之上）
	var pr: Dictionary = uv._sf_ld.portrait()
	var tx: Texture2D = g.tex.get(str(pr.get("tex", "")))
	if tx != null:
		var nf: int = maxi(1, int(pr.get("frames", 1)))
		var fw: float = tx.get_width() / float(nf)
		var fh: float = float(tx.get_height())
		var hi: float = A.hires_of(tx)
		var sc: float = g.PX / hi
		var flip: float = -1.0 if float(uv._sf_ld.face) < 0.0 else 1.0
		var G2: float = uv._pxg()
		var wt: Texture2D = _sf_white(uv, tx)
		for ring in [[2.0, uv._pc(col, 0.55 * k)], [1.0, uv._pc(col.lerp(Color.WHITE, 0.35), k)]]:   # 外圈 2 格淡、内圈 1 格亮（10-30 用户嫌读不出）
			var d: float = G2 * float(ring[0])
			for off in [Vector2(-d, 0), Vector2(d, 0), Vector2(0, -d), Vector2(0, d), Vector2(-d, -d), Vector2(d, -d), Vector2(-d, d), Vector2(d, d)]:
				g.draw_set_transform(c + off, 0.0, Vector2(sc * flip, sc))
				g.draw_texture_rect_region(wt, Rect2(-fw * 0.5, -fh * 0.92, fw, fh), Rect2(0, 0, fw, fh), ring[1])
		g.draw_set_transform(c, 0.0, Vector2(sc * flip, sc))
		g.draw_texture_rect_region(tx, Rect2(-fw * 0.5, -fh * 0.92, fw, fh), Rect2(0, 0, fw, fh), Color(1, 1, 1, k))
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 手 / 武器位置一道像素闪光：十字 + 斜十字，暂停前段长出、后段收回
	if t < T:
		var hp: Vector2 = c + Vector2(14.0 * (1.0 if float(uv._sf_ld.face) >= 0.0 else -1.0), -34.0)
		var ph: float = t / T
		var L: float = 46.0 * sin(PI * minf(1.0, ph * 1.4))
		var fc: Color = uv._pc(col.lerp(Color.WHITE, 0.6), 1.0)
		var G3: float = uv._pxg()
		_px_thick(uv, w, hp - Vector2(L, 0), hp + Vector2(L, 0), G3 * 2.0, fc)
		_px_thick(uv, w, hp - Vector2(0, L * 0.8), hp + Vector2(0, L * 0.8), G3 * 2.0, fc)
		_px_thick(uv, w, hp - Vector2(L, L) * 0.4, hp + Vector2(L, L) * 0.4, G3, uv._pc(col, 0.85))
		_px_thick(uv, w, hp - Vector2(L, -L) * 0.4, hp + Vector2(L, -L) * 0.4, G3, uv._pc(col, 0.85))
		_px_disc(uv, w, hp, maxf(G3, L * 0.18), 0.0, uv._pc(Color.WHITE, 0.9))
		w.tb_flush()


static func _sf_white(uv: U, tx: Texture2D) -> Texture2D:
	var key := tx.get_rid()
	if not uv._sf_wcache.has(key):
		var img: Image = tx.get_image()
		if img == null or img.is_empty():
			uv._sf_wcache[key] = tx
		else:
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			for y in img.get_height():
				for x in img.get_width():
					var a: float = img.get_pixel(x, y).a
					img.set_pixel(x, y, Color(1, 1, 1, 1.0 if a > 0.3 else 0.0))
			uv._sf_wcache[key] = ImageTexture.create_from_image(img)
	return uv._sf_wcache[key]


static func _draw_lf(uv: U, w) -> void:
	var g = uv.g
	var k: float = uv.lf_dim_k()
	if k <= 0.0:
		return
	var c: Vector2 = g.ppos
	var R := Vector2(2400.0, 1600.0)
	w.tb_quad(c - R, c + Vector2(R.x, -R.y), c + R, c + Vector2(-R.x, R.y), Color(0.0, 0.0, 0.02, Bal.v("link/dim", 0.4) * k))
	w.tb_flush()
	if uv.lf_op == null or uv.lf_op.pos == Vector2.INF:
		return
	var pr: Dictionary = uv.lf_op.portrait()
	var t: Texture2D = g.tex.get(str(pr.get("tex", "")))
	if t == null:
		return
	var n: int = maxi(1, int(pr.get("frames", 1)))
	var fw: float = t.get_width() / float(n)
	var fh: float = float(t.get_height())
	var s: float = g.PX / A.hires_of(t)
	var flip: float = -1.0 if float(uv.lf_op.face) < 0.0 else 1.0
	g.draw_set_transform(uv.lf_op.pos, 0.0, Vector2(s * flip, s))   # 接手队友原大小原亮度压在暗层之上
	g.draw_texture_rect_region(t, Rect2(-fw * 0.5, -fh * 0.92, fw, fh), Rect2(0, 0, fw, fh), Color(1, 1, 1, k))
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _draw_inhale(uv: U, w) -> void:
	var g = uv.g
	if not uv._fin_wait() or Cfg.reduce_motion:
		return
	var k: float = clampf(uv._imp_age() / maxf(0.01, uv._fin_in() * 0.5), 0.0, 1.0)
	var c: Vector2 = g.ppos
	var R := Vector2(2600.0, 1700.0)
	w.tb_quad(c - R, c + Vector2(R.x, -R.y), c + R, c + Vector2(-R.x, R.y), Color(0.0, 0.0, 0.02, Bal.v("ult/finish_dim", 0.4) * k))
	w.tb_flush()


static func _draw_windup(uv: U, w) -> void:
	var g = uv.g
	if uv.phase != "windup" or uv.caster == null or uv.caster.pos == Vector2.INF:
		return
	var wk: float = uv._wu_k()
	if IRP.on() and str(uv.caster.id) == "irene":   # 转平面（docs/275）：光点螺旋收进举起的提灯 + 脚下细光圈收紧
		IRP.of(g).draw_windup(uv, w, uv.caster, wk)
		return
	if SDP.on() and str(uv.caster.id) == "skadi":   # 转平面（docs/246 §16）：头顶冰蓝细光长到星芒、水珠往里收
		SDP.of(g).draw_windup(uv, w, uv.caster, wk)
		return
	var col: Color = U._col(uv.caster)
	var c: Vector2 = uv.caster.pos
	var body: Vector2 = c + Vector2(0, -22.0)
	# 脚下光圈：72 → 22 收紧，越收越亮（3 像素格的椭圆点环）
	var r: float = lerpf(72.0, 22.0, 1.0 - pow(1.0 - wk, 2.0))
	var a: float = 0.35 + 0.55 * wk
	var n := 40
	for i in n:
		var t: float = TAU * float(i) / n
		var p: Vector2 = (c + Vector2(cos(t) * r, sin(t) * r * 0.38)).snapped(Vector2(3, 3))
		w.tb_quad(p, p + Vector2(3, 0), p + Vector2(3, 3), p + Vector2(0, 3), Color(col.r, col.g, col.b, a))
	# 蓄力粒子：22 颗从 70–150 外往身上收（各自错开起点与速度，按 serial 定，不抽随机数），越近越亮越小
	if not Cfg.reduce_motion:
		var cw: Color = col.lerp(Color.WHITE, 0.45)
		for i in 22:
			var h1: float = fposmod(sin(float(i) * 12.9898 + float(uv.serial) * 78.233) * 43758.5453, 1.0)
			var h2: float = fposmod(sin(float(i) * 39.346 + float(uv.serial) * 11.135) * 24634.6345, 1.0)
			var k: float = clampf(wk * (1.2 + 0.6 * h2) - 0.25 * h1, 0.0, 1.0)
			if k <= 0.0 or k >= 1.0:
				continue
			var ang: float = TAU * (float(i) + h1) / 22.0
			var d: float = lerpf(70.0 + 80.0 * h2, 6.0, k * k)
			var p: Vector2 = (body + Vector2.from_angle(ang) * Vector2(d, d * 0.7)).snapped(Vector2(3, 3))
			var sz: float = 6.0 if k < 0.6 else 3.0
			w.tb_quad(p, p + Vector2(sz, 0), p + Vector2(sz, sz), p + Vector2(0, sz), Color(cw.r, cw.g, cw.b, 0.4 + 0.5 * k))
	w.tb_flush()
