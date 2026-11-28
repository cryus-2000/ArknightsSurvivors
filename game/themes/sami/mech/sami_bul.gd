extends RefCounted
## 萨米 Boss 弹体贴图（用户 11-26 通过样板 v3，docs/401 §19）：白芯 + 原作意象形状 + 「霜气」（外缘棋盘冷白霜点 + 身后雪尘 / 沙尘），
## 不用圆形柔光（那是水月弹型）。运行时按美术像素逐格生成（2×2 超采样落格），有朝向的按 16 向各生成一张，对称的一张；
## 结果缓存，Boss 登场后每帧预生成 2 张，缺图当帧补。只画面：不碰判定、不取玩法随机数（尘点位置按种子哈希）。

const SS := 2
const FROST := Color8(232, 244, 255)
const SNOW := [Color8(240, 248, 255), Color8(214, 232, 248), Color8(255, 255, 255)]
const SAND := [Color8(196, 164, 110), Color8(160, 124, 76), Color8(222, 196, 146)]

## 5 阶色带：白 → 淡 → 亮 → 主 → 深（深 = 本色暗一档，不是黑）
static func _ramp(main: Color, deep: Color, light: Color) -> Array:
	return [Color.WHITE, Color.WHITE.lerp(light, 0.55), light, main, deep]

var RAMP := {
	"blade": _ramp(Color8(150, 18, 24), Color8(82, 6, 12), Color8(235, 70, 60)),
	"will": _ramp(Color8(64, 150, 206), Color8(24, 84, 142), Color8(150, 214, 242)),   # 冰棱比样板深一档（用户 11-26：亮雪地上更跳）
	"lead": _ramp(Color8(28, 132, 104), Color8(10, 78, 60), Color8(104, 208, 170)),
	"cresson": _ramp(Color8(176, 120, 236), Color8(104, 60, 166), Color8(226, 196, 255)),
	"khan": _ramp(Color8(196, 40, 30), Color8(110, 14, 10), Color8(250, 120, 92)),
	"lion": _ramp(Color8(244, 172, 36), Color8(164, 98, 12), Color8(255, 230, 124)),
	"shaman": _ramp(Color8(150, 172, 250), Color8(64, 86, 196), Color8(214, 226, 255)),   # 11-28 冰屑：冰白 + 浅靛
	"vine": _ramp(Color8(120, 84, 52), Color8(62, 40, 26), Color8(176, 132, 86)),          # 11-28 土块 / 木屑：土褐
}
## 敌人种类 → [配色, 形状, 是否对称, 尘]
const KIND := {
	"blade": ["blade", "crescent", false, "smoke"], "wanderer": ["blade", "crescent", false, "smoke"],
	"will": ["will", "snow", true, "snow"], "lead": ["lead", "leaf", false, "snow"], "cresson": ["cresson", "petal", false, "snow"],
	"khan": ["khan", "lance", false, "sand"], "lion": ["lion", "sun", true, "sand"],
	"shaman": ["shaman", "shard", false, "snow"], "shaman2": ["shaman", "shard", false, "snow"],   # 11-28：水滴形 → 不规则棱角碎冰
	"vine": ["vine", "shard", false, "snow"], "vine2": ["vine", "shard", false, "snow"],           # 11-28：绿叶片 → 土块
}

var cache := {}
var queue: Array = []
var _bud: ImageTexture
var _bud_sil: ImageTexture


func has_type(t: String) -> bool:
	return KIND.has(t)


## Boss 登场时登记：把这只的两档尺寸 × 16 向排进预生成队列
func warm(t: String) -> void:
	if not KIND.has(t):
		return
	var k: Array = KIND[t]
	for sz in ([22, 32] if k[1] == "crescent" else [24, 19]):
		for d in (1 if k[2] else 16):
			var key := "%s|%d|%d" % [t, sz, d]
			if not cache.has(key) and not queue.has(key):
				queue.append(key)


func tick() -> void:
	for i in 2:
		if queue.is_empty():
			return
		var key: String = queue.pop_front()
		if not cache.has(key):
			var p := key.split("|")
			cache[key] = _make(p[0], int(p[1]), int(p[2]))


## 取贴图：t = 敌人种类，sz = 美术像素尺寸，ang = 飞行方向
func tex(t: String, sz: int, ang: float) -> ImageTexture:
	var k: Array = KIND[t]
	var d: int = 0 if k[2] else int(posmod(roundi(ang / (TAU / 16.0)), 16))
	var key := "%s|%d|%d" % [t, sz, d]
	var tx = cache.get(key)
	if tx == null:
		tx = _make(t, sz, d)
		cache[key] = tx
	return tx


# ---- 形状：返回 t（0 = 白芯 → 1 = 外沿；< 0 = 外面）
func _shape(kind: String, sz: float, u: float, v: float) -> float:
	match kind:
		"crescent":
			var L: float = sz
			var R1: float = L * 0.62
			var d1: float = Vector2(u + R1 * 0.45, v).length()
			var d2: float = Vector2(u + R1 * 0.45 + L * 0.3, v).length()
			if d1 <= R1 and d2 >= R1 * 0.92 and absf(v) <= L * 0.5:
				var eo: float = R1 - d1
				var ei: float = d2 - R1 * 0.92
				if eo < 1.1: return 0.0
				if eo < 2.0: return 0.55
				if ei < 1.0: return 0.95
				return 0.75
			return -1.0
		"snow":
			var R: float = sz * 0.5
			var r: float = Vector2(u, v).length()
			if r < R * 0.22:
				return 0.1 * r / (R * 0.22)
			if r > R:
				return -1.0
			var a: float = atan2(v, u)
			var step: float = TAU / 6.0
			var da: float = a - roundf(a / step) * step
			var perp: float = absf(r * sin(da))
			var along: float = r * cos(da)
			var hw: float = maxf(1.1, R * 0.13) * (1.0 - 0.45 * along / R)
			if perp <= hw and along > 0.0:
				return (0.25 + 0.75 * perp / hw) if along > R * 0.35 else 0.35 * perp / hw
			if sz >= 22.0 and along > R * 0.45 and along < R * 0.8:
				var bx: float = along - R * 0.55
				if absf(perp - absf(bx) * 0.9) < 0.9 and perp < R * 0.28:
					return 0.8
			if r < R * 0.36:
				return 0.6
			return -1.0
		"lance":
			var L2: float = sz
			var W2: float = sz * 0.42
			var t2: float = (u / (L2 * 0.6) if u >= 0.0 else -u / (L2 * 0.4)) + absf(v) / (W2 * 0.5)
			if t2 <= 1.0:
				if absf(v) < W2 * 0.12 and u > -L2 * 0.25 and u < L2 * 0.45:
					return 0.0
				return 0.3 + 0.7 * t2
			var bu: float = u + L2 * 0.18
			if bu > -L2 * 0.14 and bu < 0.0 and absf(v) > W2 * 0.35 and absf(v) < W2 * 0.5 + (-bu) * 0.3:
				return 0.9
			return -1.0
		"sun":
			var R3: float = sz * 0.5
			var rays: int = 8 if sz >= 22.0 else 4
			var r3: float = Vector2(u, v).length()
			var rc: float = R3 * 0.45
			if r3 <= rc:
				return 0.85 * r3 / rc
			if r3 > R3:
				return -1.0
			var a3: float = atan2(v, u)
			var st3: float = TAU / float(rays)
			var da3: float = absf(a3 - roundf(a3 / st3) * st3)
			if da3 <= (1.0 - (r3 - rc) / (R3 - rc)) * 0.28:
				return 0.55 + 0.4 * (r3 - rc) / (R3 - rc)
			if r3 <= rc + 1.0:
				return 0.95
			return -1.0
		"leaf", "petal":
			var hl: float = sz * 0.5
			var W4: float = sz * 0.54
			if absf(u) >= hl:
				return -1.0
			var wmax: float = W4 * 0.5 * (1.0 - pow(u / hl, 2.0)) * (1.0 + 0.15 * u / hl)
			if absf(v) > wmax:
				return -1.0
			if absf(v) < 0.8 and absf(u) < hl * 0.8:
				return 0.0
			var t4: float = absf(v) / maxf(0.4, wmax)
			if kind == "petal" and v > 0.0 and t4 > 0.62:
				return 0.45 if t4 < 0.85 else 0.95   # 一侧卷边：亮一条
			return 0.3 + 0.7 * t4
		"cone":
			var L5: float = sz
			var W5: float = sz * 0.54
			if u > L5 * 0.5 or u < -L5 * 0.5:
				return -1.0
			if u < -L5 * 0.2:
				var d5: float = Vector2(u + L5 * 0.2, v).length()
				if d5 > W5 * 0.5:
					return -1.0
				if absf(v) < 1.2 and d5 < W5 * 0.35:
					return 0.0
				return 0.3 + 0.7 * d5 / (W5 * 0.5)
			var wm5: float = W5 * 0.5 * (1.0 - (u + L5 * 0.2) / (L5 * 0.7))
			if absf(v) > wm5:
				return -1.0
			if absf(v) < 1.0:
				return 0.0
			return 0.3 + 0.7 * absf(v) / maxf(0.5, wm5)
		"shard":
			# 不规则棱角碎块：五边形（各顶点半径不同），按面分明暗（一面亮一面暗），中心一点白芯
			var R7: float = sz * 0.48
			var r7: float = Vector2(u, v).length()
			var a7: float = fposmod(atan2(v, u), TAU)
			var vr: Array = [1.0, 0.6, 0.86, 0.52, 0.76]
			var fa: float = a7 / (TAU / 5.0)
			var i7: int = int(fa) % 5
			var rr7: float = R7 * lerpf(float(vr[i7]), float(vr[(i7 + 1) % 5]), fa - floorf(fa))
			if r7 > rr7:
				return -1.0
			if r7 < rr7 * 0.22:
				return 0.0
			var shade: Array = [0.4, 0.62, 0.92, 0.78, 0.5]
			return float(shade[i7]) * (0.75 + 0.25 * r7 / rr7)
		"pod":
			var hl6: float = sz * 0.5
			var W6: float = sz * 0.54
			if absf(u) >= hl6:
				return -1.0
			var wm6: float = W6 * 0.5 * pow(sin(PI * (u / hl6 + 1.0) * 0.5), 0.7)
			if absf(v) > wm6:
				return -1.0
			if absf(v) < 0.9 and absf(u) < hl6 * 0.75:
				return 0.0
			return 0.3 + 0.7 * absf(v) / maxf(0.4, wm6)
	return -1.0


func _band(rp: Array, t: float):
	if t < 0.0 or t > 1.0:
		return null
	if t < 0.3: return rp[0]
	if t < 0.48: return rp[1]
	if t < 0.66: return rp[2]
	if t < 0.84: return rp[3]
	return rp[4]


func _make(t: String, sz: int, d: int) -> ImageTexture:
	var k: Array = KIND[t]
	var rp: Array = RAMP[k[0]]
	var kind: String = k[1]
	var ang: float = TAU * float(d) / 16.0
	var S: int = int(float(sz) * 2.2) + 8
	S += S % 2
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	var mask := PackedByteArray()
	mask.resize(S * S)
	var ca: float = cos(ang)
	var sa: float = sin(ang)
	var half: float = float(S) * 0.5
	for j in S:
		for i in S:
			var votes := {}
			var cnt := 0
			for sy in SS:
				for sx in SS:
					var x: float = float(i) - half + (float(sx) + 0.5) / float(SS)
					var y: float = float(j) - half + (float(sy) + 0.5) / float(SS)
					var u: float = x * ca + y * sa
					var v: float = -x * sa + y * ca
					var c = _band(rp, _shape(kind, float(sz), u, v))
					if c == null:
						continue
					votes[c] = int(votes.get(c, 0)) + 1
					cnt += 1
			if cnt * 2 >= SS * SS:
				var best = null
				var bn := -1
				for c2 in votes:
					if int(votes[c2]) > bn:
						bn = int(votes[c2])
						best = c2
				img.set_pixel(i, j, best)
				mask[j * S + i] = 1
	# 霜点：外缘 1 格棋盘抖动、2 格稀疏
	for j in S:
		for i in S:
			if mask[j * S + i] == 1:
				continue
			var n1 := false
			var n2 := false
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var xx: int = i + dx
					var yy: int = j + dy
					if xx < 0 or yy < 0 or xx >= S or yy >= S or mask[yy * S + xx] == 0:
						continue
					if absi(dx) <= 1 and absi(dy) <= 1:
						n1 = true
					else:
						n2 = true
			if n1 and (i + j) % 2 == 0:
				img.set_pixel(i, j, Color(FROST, 0.86))
			elif n2 and not n1 and (i + j) % 4 == 0:
				img.set_pixel(i, j, Color(FROST, 0.55))
	# 身后：国度两团黑烟；3–4 粒飘散雪尘 / 沙尘（位置按种子哈希定）
	var bx: float = -ca
	var by: float = -sa
	if k[3] == "smoke":
		for blob in [[0.55, 0.2, 0.6], [0.8, 0.15, 0.4]]:
			var cx: float = half + bx * float(sz) * float(blob[0])
			var cy: float = half + by * float(sz) * float(blob[0])
			var rr: float = float(sz) * float(blob[1])
			for j in S:
				for i in S:
					if mask[j * S + i] == 0 and Vector2(float(i) + 0.5 - cx, float(j) + 0.5 - cy).length() < rr and img.get_pixel(i, j).a < 0.8:
						img.set_pixel(i, j, Color(0.11, 0.07, 0.1, float(blob[2])))
	var pal: Array = SAND if k[3] == "sand" else SNOW
	for n in 4:
		var hj: int = absi(hash(Vector2i(sz * 31 + d, n)))
		var dist: float = float(sz) * (0.55 + 0.22 * float(n)) + float(hj % 3) - 1.0
		var off: float = (float((hj >> 3) % 100) / 100.0 - 0.5) * float(sz) * 0.5
		var x2: int = int(half + bx * dist - by * off)
		var y2: int = int(half + by * dist + bx * off)
		if x2 >= 0 and y2 >= 0 and x2 < S and y2 < S and mask[y2 * S + x2] == 0:
			img.set_pixel(x2, y2, Color(pal[n % 3], 0.9 - 0.18 * float(n)))
			if n == 0 and x2 + 1 < S:
				img.set_pixel(x2 + 1, y2, Color(pal[0], 0.7))
	return ImageTexture.create_from_image(img)


## 克雷松稳定设施：晶簇花苞（三枚淡紫晶瓣合拢 + 白芯 + 暗石底座 + 霜点），34×44 美术像素，原点在底座中心
func bud() -> ImageTexture:
	if _bud != null:
		return _bud
	var rp: Array = RAMP.cresson
	var img := Image.create(34, 44, false, Image.FORMAT_RGBA8)
	var polys := [
		[[Vector2(5, 41), Vector2(9, 36), Vector2(25, 36), Vector2(29, 41)], Color8(58, 54, 72)],
		[[Vector2(9, 36), Vector2(12, 34), Vector2(22, 34), Vector2(25, 36)], Color8(96, 92, 116)],
		[[Vector2(17, 34), Vector2(8, 22), Vector2(12, 10), Vector2(17, 4)], rp[4]],
		[[Vector2(17, 34), Vector2(26, 22), Vector2(22, 10), Vector2(17, 4)], rp[2]],
		[[Vector2(17, 33), Vector2(13, 20), Vector2(17, 8), Vector2(21, 20)], rp[1]],
		[[Vector2(17, 26), Vector2(15, 18), Vector2(17, 12), Vector2(19, 18)], Color.WHITE],
		[[Vector2(8, 22), Vector2(3, 18), Vector2(6, 12), Vector2(12, 16)], rp[3]],
		[[Vector2(26, 22), Vector2(31, 18), Vector2(28, 12), Vector2(22, 16)], rp[2]],
	]
	for j in 44:
		for i in 34:
			var q := Vector2(float(i) + 0.5, float(j) + 0.5)
			for pp in polys:
				if Geometry2D.is_point_in_polygon(q, PackedVector2Array(pp[0])):
					img.set_pixel(i, j, pp[1])
	var img2: Image = img.duplicate()
	for j in 34:
		for i in 34:
			if img.get_pixel(i, j).a > 0.0 or (i + j) % 2 != 0:
				continue
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var xx: int = clampi(i + dx, 0, 33)
					var yy: int = clampi(j + dy, 0, 43)
					if img.get_pixel(xx, yy).a > 0.99:
						img2.set_pixel(i, j, Color(FROST, 0.8))
	_bud = ImageTexture.create_from_image(img2)
	return _bud


## 花苞白剪影（金色描边垫底用：染成金色、放大一圈画在花苞下面）
func bud_sil() -> ImageTexture:
	if _bud_sil != null:
		return _bud_sil
	var img: Image = bud().get_image()
	for j in img.get_height():
		for i in img.get_width():
			if img.get_pixel(i, j).a > 0.9:
				img.set_pixel(i, j, Color.WHITE)
			else:
				img.set_pixel(i, j, Color(0, 0, 0, 0))
	_bud_sil = ImageTexture.create_from_image(img)
	return _bud_sil
