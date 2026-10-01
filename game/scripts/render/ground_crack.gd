extends RefCounted
## 地裂（共用）：中心不规则碎坑 + n 条从坑边最宽、不规则收细到 1 像素的实心楔形主裂缝，途中随机分叉；贴地透视（y × gy）、
## 中心线对齐 2 像素网格；前 grow_t 秒从中心裂开，暗色裂缝前半程不透明、后半程淡出，颜色亮芯先消失。
## 原是干员的 character.gd _draw_crack / _crack_build（2026-09-26 重做的那版），2026-10-01 抽成共用（界面与美术，协调人派）：
## 干员（fx kind "crack"）和敌人 / Boss（world 的 fx kind "gcrack"）都走这里。build 的随机数调用顺序和原版完全一致，
## 缺省参数下干员画面逐像素不变。
##
## 画法不直接调 CanvasItem：传一个 sink（有 poly(pts, col) 和 line(a, b, col, w) 两个方法），
## 干员用 CvSink（写进编队合批画布 cv）、world 用 TbSink（写进 world 的 tb_* 无贴图批）——都不新增绘制调用。


## opts（都可省）：
##   n           主裂缝条数（缺省 8）
##   w0          起点半宽范围 Vector2(min, max)（缺省 4–6，即坑边最宽 8–12 像素）
##   length      长度范围（× r）Vector2(min, max)（缺省 0.5–1.0）
##   steps       每条主裂缝的折点数范围 Vector2i（缺省 5–7）
##   wobble      每段转角抖动（弧度，缺省 0.55）
##   branch      每个中段折点分叉的概率（缺省 0.4）
##   crater      是否画中心碎坑（缺省 true；false 时裂缝从中心附近直接长出，适合连成线的裂地）
##   spread      主裂缝的角度范围（弧度，缺省 TAU = 一圈；给小值就是朝 ang 方向的一束）
##   gy          贴地纵向压缩（缺省 0.55）
static func build(pos: Vector2, r: float, ang, opts := {}) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(int(pos.x), int(pos.y))) + int((ang if ang != null else 0.0) * 1000.0)
	var R: float = r
	var o: Vector2 = pos
	var gy: float = float(opts.get("gy", 0.55))
	var snap := func(v: Vector2) -> Vector2: return ((o + Vector2(v.x, v.y * gy)) / 2.0).round() * 2.0   # 贴地透视 + 对齐 2 像素网格
	var crater: bool = opts.get("crater", true)
	# 中心碎坑（不规则多边形，凸的，保证能三角化）——不画坑也照样抽随机数，保证同参数下裂缝形状一致
	var ring := PackedVector2Array()
	var nv: int = rng.randi_range(8, 11)
	var cr: float = R * rng.randf_range(0.22, 0.3)
	for i in nv:
		var an: float = TAU * float(i) / nv + rng.randf_range(-0.12, 0.12)
		ring.append(o + Vector2.from_angle(an) * cr * rng.randf_range(0.8, 1.15) * Vector2(1.0, gy))
	var inner: Array = []
	for i in 3:
		var an2: float = rng.randf() * TAU
		inner.append([o + Vector2.from_angle(an2) * cr * 0.15 * Vector2(1.0, gy), o + Vector2.from_angle(an2 + rng.randf_range(-0.4, 0.4)) * cr * 0.85 * Vector2(1.0, gy)])
	if not crater:
		ring = PackedVector2Array()
		inner = []
	var segs: Array = []
	var n: int = int(opts.get("n", 8))
	var w0r: Vector2 = opts.get("w0", Vector2(4.0, 6.0))
	var lr: Vector2 = opts.get("length", Vector2(0.5, 1.0))
	var sr: Vector2i = opts.get("steps", Vector2i(5, 7))
	var wob: float = float(opts.get("wobble", 0.55))
	var bch: float = float(opts.get("branch", 0.4))
	var spread: float = float(opts.get("spread", TAU))
	var rnd_ang: float = rng.randf() * TAU   # 原版 f.get("ang", rng.randf() * TAU) 的缺省值总会求值、总会抽一次随机数，这里照样抽，保证序列一致
	var base_ang: float = ang if ang != null else rnd_ang
	for q in n:
		var a0: float = base_ang + (spread * q / n if spread >= TAU - 0.001 else (spread * (float(q) / maxf(1.0, n - 1) - 0.5)))
		var dang: float = a0 + rng.randf_range(-0.35, 0.35)
		var L: float = R * rng.randf_range(lr.x, lr.y)
		var steps: int = rng.randi_range(sr.x, sr.y)
		var w0: float = rng.randf_range(w0r.x, w0r.y)
		var p: Vector2 = Vector2.from_angle(dang) * cr * (0.8 if crater else 0.15)
		var pts := PackedVector2Array([snap.call(p)])
		var ws := PackedFloat32Array([w0])
		for st in steps:
			dang += rng.randf_range(-wob, wob)
			p += Vector2.from_angle(dang) * (L - cr) / steps * rng.randf_range(0.7, 1.3)
			pts.append(snap.call(p))
			var t: float = float(st + 1) / steps
			# 不规则收细：整体按 (1-t)^0.9 由宽到细，每个点再乘 0.65–1.25 的起伏，末端 0.5px
			ws.append(maxf(0.5, w0 * pow(1.0 - t, 0.9) * rng.randf_range(0.65, 1.25)))
			if st >= 1 and st < steps - 1 and rng.randf() < bch:
				var ba: float = dang + rng.randf_range(0.6, 1.1) * (1.0 if rng.randf() < 0.5 else -1.0)
				var bp: Vector2 = p
				var bw: float = ws[ws.size() - 1] * 0.6
				var bpts := PackedVector2Array([snap.call(bp)])
				var bws := PackedFloat32Array([bw])
				var bn: int = rng.randi_range(2, 3)
				for bs in bn:
					ba += rng.randf_range(-0.4, 0.4)
					bp += Vector2.from_angle(ba) * (L - cr) / steps * rng.randf_range(0.5, 0.9)
					bpts.append(snap.call(bp))
					bws.append(maxf(0.5, bw * (1.0 - float(bs + 1) / bn) * rng.randf_range(0.7, 1.2)))
				segs.append({"pts": bpts, "ws": bws})
		segs.append({"pts": pts, "ws": ws})
	return {"ring": ring, "inner": inner, "segs": segs, "center": o}


## 画一帧。age = 已过时间、a = 剩余比例（life / max，调用方可再乘降噪系数）、c = 亮芯颜色、grow_t = 裂开用时。
## hot（0–1，缺省 0 = 干员原样）：敌方「刚被砸过 / 危险」标记用——裂缝加一道颜色外发光，亮芯整段寿命都在（随 a 淡出），
## 主线亮度不低于旧的放射线；碎坑中心照旧是暗的
static func draw(cd: Dictionary, age: float, a: float, c: Color, sink, grow_t := 0.06, hot := 0.0) -> void:
	var grow: float = clampf(age / grow_t, 0.0, 1.0)
	var al: float = minf(1.0, a * 2.0)             # 前半程保持不透明，后半程淡出
	var glow: float = clampf((a - 0.5) * 2.0, 0.0, 1.0)
	if hot > 0.0:
		glow = maxf(glow, a * hot)
	var dark := Color(0.045, 0.035, 0.04, 0.9 * al)
	# 裂缝：逐段画实心梯形（中心线两侧按该点半宽展开）
	for sg in cd.segs:
		var pts: PackedVector2Array = sg.pts
		var ws: PackedFloat32Array = sg.ws
		var m: int = mini(pts.size(), maxi(2, int(ceil(pts.size() * grow))))
		for i in m - 1:
			var p0: Vector2 = pts[i]
			var p1: Vector2 = pts[i + 1]
			var d: Vector2 = p1 - p0
			if d.length() < 1.0:
				continue
			var nrm: Vector2 = d.normalized().orthogonal()
			if hot > 0.0:
				# 外发光：比裂缝宽一圈的半透明颜色带（先画，压在暗色裂缝下面，裂缝边缘就是亮的）
				sink.line(p0, p1, Color(c.r * 1.3, c.g * 1.2, c.b * 1.2, 0.45 * a * hot), ws[i] * 2.0 + 4.0)
			if ws[i] + ws[i + 1] < 1.2:
				sink.line(p0, p1, dark, 1.0)
			else:
				sink.poly(PackedVector2Array([p0 + nrm * ws[i], p1 + nrm * ws[i + 1], p1 - nrm * ws[i + 1], p0 - nrm * ws[i]]), dark)
			if glow > 0.0 and (ws[i] > 1.4 or hot > 0.0):
				sink.line(p0, p1, Color(c.r * 1.6, c.g * 1.4, c.b * 1.2, (0.75 if hot <= 0.0 else 0.95) * glow), maxf(1.0, ws[i] * (0.6 if hot <= 0.0 else 0.8)))
	var ring: PackedVector2Array = cd.ring
	if ring.is_empty():
		return
	# 中心碎坑：实心深色 + 坑心再压一层更深的（凹陷感）+ 几道坑内裂纹
	var sc: float = 0.35 + 0.65 * grow
	var ctr: Vector2 = cd.center
	var rp := PackedVector2Array()
	for v in ring:
		rp.append(ctr + (v - ctr) * sc)
	sink.poly(rp, Color(0.06, 0.05, 0.05, al))
	var core := PackedVector2Array()
	for v in rp:
		core.append(ctr + (v - ctr) * 0.55)
	sink.poly(core, Color(0.02, 0.015, 0.02, al))
	for ln in cd.inner:
		sink.line(ctr + (ln[0] - ctr) * sc, ctr + (ln[1] - ctr) * sc, Color(0.16, 0.13, 0.13, 0.8 * al), 1.0)


## 写进干员的绘制入口 owner.cv（编队合批画布 characters/batch_canvas.gd，没有时是 g）；每次现取，不缓存画布对象
class CvSink:
	var owner
	func _init(o) -> void:
		owner = o
	func poly(pts: PackedVector2Array, col: Color) -> void:
		owner.cv.draw_colored_polygon(pts, col)
	func line(a: Vector2, b: Vector2, col: Color, w: float) -> void:
		owner.cv.draw_line(a, b, col, w)


## 写进 world 的 tb_* 无贴图批（调用方负责之后 tb_flush）
class TbSink:
	var w
	func _init(world) -> void:
		w = world
	func poly(pts: PackedVector2Array, col: Color) -> void:
		w.tb_poly(pts, col)
	func line(a: Vector2, b: Vector2, col: Color, wd: float) -> void:
		w.tb_line(a, b, col, wd)
