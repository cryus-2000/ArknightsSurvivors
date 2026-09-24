extends RefCounted
## 标题远景：深蓝之树（程序生成，一次性栅格化成像素图）
## 结构：海平线上铺开的根系 → 多股缠绕的主干 → 从树冠向两侧伸展并下垂的巨枝 → 细密的枝梢
## 质感：半透明冰蓝，圆柱明暗，主干内部透出白光；另外生成一张模糊的发光图用于加法叠加。

var img: Image                 # 树本体（与画布同尺寸，透明底）
var glow: Image                # 模糊发光图（同尺寸）
var strands: Array = []        # 主干 / 巨枝的路径（PackedVector2Array），用于能量脉冲
var tips: Array = []           # 枝梢端点 [pos, phase]
var crown := Vector2.ZERO      # 树冠中心（光环圆心）
var rng := RandomNumberGenerator.new()
var _w := 0
var _h := 0

const DARK := Color(0.08, 0.12, 0.2)
const MID := Color(0.32, 0.45, 0.58)
const PALE := Color(0.8, 0.91, 0.97)


func build(w: int, h: int, base: Vector2, height: float, seed_v: int) -> void:
	_w = w
	_h = h
	rng.seed = seed_v
	img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var waist := base + Vector2(0, -height * 0.4)
	crown = base + Vector2(0, -height * 0.66)
	# ---- 主干：10 股，从根部散开处汇到腰部，再在树冠处分开，股与股之间缠绕
	# 主干暗芯：让股与股之间不透出天空，树干显得厚重
	var core := PackedVector2Array()
	for s in 41:
		var q := float(s) / 40.0
		core.append(base.lerp(crown, q) + Vector2(sin(q * 5.0) * 2.0, 0))
	_fill(core, 40.0, 20.0)
	var n := 14
	for k in n:
		var u := float(k) / (n - 1) - 0.5
		var root := base + Vector2(u * 150.0 + rng.randf_range(-6, 6), rng.randf_range(0, 5))
		var pw := waist + Vector2(u * 30.0, 0)
		var pc := crown + Vector2(u * 44.0, rng.randf_range(-4, 4))
		var path := PackedVector2Array()
		var steps := 90
		for s in steps + 1:
			var q := float(s) / steps
			var p: Vector2
			if q < 0.45:
				var e := q / 0.45
				p = root.lerp(pw, 1.0 - pow(1.0 - e, 2.0))
			else:
				var e := (q - 0.45) / 0.55
				p = pw.lerp(pc, e)
			# 缠绕：沿横向做相位不同的正弦摆动
			p.x += sin(q * 9.0 + k * 1.3) * (3.0 + 4.0 * q)
			path.append(p)
		strands.append(path)
		var sw := rng.randf_range(3.6, 6.4)
		_stroke(path, sw, sw * 0.7, rng.randf_range(0.5, 1.1))
		# 从树冠继续伸出巨枝：向两侧斜上方展开，末端才缓缓下垂
		var ang := lerpf(-PI * 0.93, -PI * 0.07, float(k) / (n - 1)) + rng.randf_range(-0.15, 0.15)
		_limb(pc, ang, rng.randf_range(90.0, 150.0), 3.6, 0.006 + absf(u) * 0.012, 2)
	# 向上的几根，撑起树冠高度
	for k in 5:
		_limb(crown + Vector2(rng.randf_range(-14, 14), 0), -PI / 2 + rng.randf_range(-0.5, 0.5), rng.randf_range(45, 70), 2.6, 0.0, 1)
	# ---- 根系：沿海平线向两侧铺开，部分探入水面
	for k in 12:
		var side := -1.0 if k % 2 == 0 else 1.0
		var start := base + Vector2(side * rng.randf_range(10, 55), rng.randf_range(0, 3))
		_root(start, side, rng.randf_range(60, 150))
	# ---- 发光图：树的亮度模糊后上色
	glow = img.duplicate()
	glow.resize(maxi(1, w / 6), maxi(1, h / 6), Image.INTERPOLATE_BILINEAR)
	glow.resize(w, h, Image.INTERPOLATE_BILINEAR)
	for y in h:
		for x in w:
			var c := glow.get_pixel(x, y)
			var l: float = c.a * (0.4 + 0.6 * c.b)
			glow.set_pixel(x, y, Color(0.16 * l, 0.36 * l, 0.62 * l, 1.0))


## 枝：level 2 巨枝 / 1 中枝，沿途分出下一级；带轻微下垂与虬曲
func _limb(p: Vector2, ang: float, length: float, width: float, droop: float, level: int) -> void:
	var path := PackedVector2Array([p])
	var dir := Vector2.from_angle(ang)
	var step := 2.0
	var travelled := 0.0
	var bend := rng.randf_range(-0.03, 0.03)
	while travelled < length:
		bend = clampf(bend + rng.randf_range(-0.015, 0.015), -0.05, 0.05)
		dir = dir.rotated(bend)
		dir = (dir + Vector2(0, droop * (travelled / length) * 3.0)).normalized()
		p += dir * step
		travelled += step
		path.append(p)
		var q := travelled / length
		if level == 2 and travelled > 16.0 and rng.randf() < 0.07:
			_limb(p, dir.angle() + rng.randf_range(-0.9, 0.9), length * rng.randf_range(0.35, 0.55) * (1.0 - q * 0.5), width * 0.55, droop * 1.5, 1)
		elif travelled > 8.0 and rng.randf() < (0.13 if level == 2 else 0.2):
			_twig(p, dir.angle() + rng.randf_range(-1.1, 1.1), rng.randf_range(10, 30) * (1.0 - q * 0.5), 2)
	if level >= 1:
		strands.append(path)
	_stroke(path, width, 1.0, 0.5 if level == 2 else 0.3)
	tips.append([p, rng.randf() * TAU])


## 细枝：递归分叉、轻微下垂，末端记为发光点
func _twig(p: Vector2, ang: float, length: float, depth: int) -> void:
	var path := PackedVector2Array([p])
	var dir := Vector2.from_angle(ang)
	var travelled := 0.0
	while travelled < length:
		dir = (dir + Vector2(rng.randf_range(-0.12, 0.12), 0.05)).normalized()
		p += dir * 1.5
		travelled += 1.5
		path.append(p)
		if depth > 0 and travelled > 6.0 and rng.randf() < 0.09:
			_twig(p, dir.angle() + rng.randf_range(-0.9, 0.9), length * rng.randf_range(0.4, 0.65), depth - 1)
	_stroke(path, 1.0, 0.8, 0.2)
	if rng.randf() < 0.6:
		tips.append([p, rng.randf() * TAU])


## 根：贴着海平线蜿蜒，越远越细
func _root(p: Vector2, side: float, length: float) -> void:
	var path := PackedVector2Array([p])
	var dir := Vector2(side, rng.randf_range(-0.05, 0.25)).normalized()
	var travelled := 0.0
	var base_y := p.y
	while travelled < length:
		dir = (dir + Vector2(0, rng.randf_range(-0.12, 0.12))).normalized()
		p += dir * 2.0
		p.y = clampf(p.y, base_y - 3.0, base_y + 12.0)
		travelled += 2.0
		path.append(p)
	_stroke(path, 2.2, 0.6, 0.4)


## 暗色填充（主干芯），宽度从 w0 渐变到 w1，不参与高光
func _fill(path: PackedVector2Array, w0: float, w1: float) -> void:
	for i in path.size():
		var q := float(i) / (path.size() - 1)
		var r: float = lerpf(w0, w1, q) * 0.5
		var p: Vector2 = path[i]
		for dy in range(-3, 4):
			for dx in range(-int(r), int(r) + 1):
				var x := int(p.x) + dx
				var y := int(p.y) + dy
				if x >= 0 and y >= 0 and x < _w and y < _h:
					var e := absf(dx) / r
					img.set_pixel(x, y, DARK.lerp(Color(0.03, 0.05, 0.1), 0.6 - 0.3 * e))


## 沿路径栅格化：宽度从 w0 渐细到 w0*taper；圆柱明暗；inner 控制内部透光强度
func _stroke(raw: PackedVector2Array, w0: float, taper_to: float, inner: float) -> void:
	var path := PackedVector2Array()
	for i in raw.size() - 1:
		var seg: float = raw[i].distance_to(raw[i + 1])
		var m := maxi(1, int(ceil(seg / 0.6)))
		for j in m:
			path.append(raw[i].lerp(raw[i + 1], float(j) / m))
	if raw.size() > 0:
		path.append(raw[raw.size() - 1])
	var cnt := path.size()
	for i in cnt:
		var q := float(i) / maxf(1.0, cnt - 1)
		var r: float = lerpf(w0, taper_to, q) * 0.5
		var p: Vector2 = path[i]
		var tng: Vector2 = (path[mini(i + 1, cnt - 1)] - path[maxi(i - 1, 0)]).normalized()
		var nrm := tng.orthogonal()
		var ri := int(ceil(r))
		for dy in range(-ri, ri + 1):
			for dx in range(-ri, ri + 1):
				var off := Vector2(dx, dy)
				if off.length() > r + 0.35:
					continue
				var x := int(round(p.x)) + dx
				var y := int(round(p.y)) + dy
				if x < 0 or y < 0 or x >= _w or y >= _h:
					continue
				# 圆柱明暗：法线方向一侧亮（光从右上方打来）
				var side: float = off.dot(nrm) / maxf(r, 0.5)
				var shade := clampf(0.5 + 0.5 * side, 0.0, 1.0)
				var c := DARK.lerp(MID, shade)
				if shade > 0.78:
					c = c.lerp(PALE, 0.75)
				elif rng.randf() < 0.015:
					c = c.lerp(PALE, 0.5)
				# 主干下部内部透出白光
				c = c.lerp(Color(0.85, 0.95, 1.0), clampf(inner * (1.0 - absf(side)) * 0.45, 0.0, 0.6))
				var old := img.get_pixel(x, y)
				if old.a < 0.5 or c.v > old.v:
					img.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
