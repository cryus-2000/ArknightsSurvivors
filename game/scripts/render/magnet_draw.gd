extends RefCounted
## 磁铁在地图上的画法（docs/284 §2 画法 A「磁场铁屑」，11-06 用户「磁铁在地图上要能看见」）。只画，不读写对局状态、不抽随机数。
## 开关 balance.json render/magnet_v2：1 = 新画法（缺省），0 = 旧的 14 像素粉红贴图 + 细环。
## - 本体：20×20 美术像素的马蹄形，左臂红、右臂钢蓝、两极白色磁极（运行时按像素表生成一次贴图，不新增素材文件）；
## - 磁极：两颗 HDR 亮像素（光学观感下自然泛光）；
## - 铁屑：4 簇灰蓝小点朝磁铁聚拢、到了被弹开，循环；
## - 脉冲：每 1.2 秒一圈红 / 蓝相间的像素点向外扩到约 90 像素后消失（不是实线圆，Noita 口径）；
## - 落地 0.9 秒的光柱改成左红右蓝的双色细柱。
## 屏外指针在 screens/hud_banners.gd draw_magnet_pointers。
const Bal = preload("res://scripts/core/balance.gd")

const W := 20
const RED := Color(0.88, 0.2, 0.24)
const RED_D := Color(0.55, 0.09, 0.14)
const RED_L := Color(1.0, 0.52, 0.5)
const BLUE := Color(0.32, 0.52, 0.92)
const BLUE_D := Color(0.15, 0.27, 0.6)
const BLUE_L := Color(0.62, 0.8, 1.0)
const TIP := Color(0.93, 0.94, 0.97)
const TIP_D := Color(0.66, 0.69, 0.76)
const OUT := Color(0.07, 0.05, 0.08)
const FILING := Color(0.62, 0.68, 0.8)

static var _tex: Texture2D = null
static var _on := -1


static func on() -> bool:
	if _on < 0:
		_on = 1 if Bal.vi("render/magnet_v2", 1) > 0 else 0
	return _on == 1


## 像素表：两条竖臂（x 2–7 / 12–17，y 1–10）+ 下半圆环（圆心 (10, 10)，外半径 8、内半径 2）；臂顶 3 行是磁极；外面一圈描边
static func _shape(x: int, y: int) -> int:
	var cx: float = x + 0.5
	var cy: float = y + 0.5
	if cy < 10.0:
		if cy >= 1.0 and ((cx >= 2.0 and cx < 8.0) or (cx >= 12.0 and cx < 18.0)):
			return 2 if cy < 4.0 else 1
		return 0
	var d: float = Vector2(cx - 10.0, cy - 10.0).length()
	return 1 if d < 8.0 and d >= 2.0 else 0


static func tex() -> Texture2D:
	if _tex != null:
		return _tex
	var img := Image.create(W, W, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in W:
		for x in W:
			var k: int = _shape(x, y)
			if k == 0:
				var edge := false
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q: Vector2i = Vector2i(x, y) + d
					if q.x >= 0 and q.y >= 0 and q.x < W and q.y < W and _shape(q.x, q.y) > 0:
						edge = true
				if edge:
					img.set_pixel(x, y, OUT)
				continue
			var left: bool = x < 10
			var c: Color
			if k == 2:
				c = TIP if (x == 3 or x == 13) else TIP_D
			else:
				# 左上受光：每条臂最左一列亮、最右一列暗；下半环按左右分色
				var lx: int = x - (2 if left else 12)
				if y >= 10:
					lx = 1 if y < 14 else 3
				c = (RED if left else BLUE)
				if lx == 0 or (y >= 10 and Vector2(x + 0.5 - 10.0, y + 0.5 - 10.0).length() < 3.2):
					c = RED_L if left else BLUE_L
				elif lx == 5 or (y >= 10 and Vector2(x + 0.5 - 10.0, y + 0.5 - 10.0).length() > 7.0):
					c = RED_D if left else BLUE_D
			img.set_pixel(x, y, c)
	_tex = ImageTexture.create_from_image(img)
	return _tex


## 画一个磁铁（w = render/world.gd；pos 已是落地点，gz 是离地高度，t = g.t）。走 world 的掉落批（_pb / _pq_spr），前后顺序与其他掉落一致
static func draw(w, g_item: Dictionary, pos: Vector2, gz: float, t: float, px: float) -> void:
	var ground: bool = gz <= 1.0
	var age: float = g_item.age
	var sd: float = float(g_item.get("seed", 0.0))
	# 落地光柱（双色）
	if age < 0.9:
		var ba := (1.0 - age / 0.9) * 0.6
		w._pq_guard(Rect2(pos + Vector2(-6, -141), Vector2(12, 142)))
		w._pb.rect(Rect2(pos + Vector2(-4, -140), Vector2(4, 140)), Color(RED.r * 2.2, RED.g * 2.2, RED.b * 2.2, ba))
		w._pb.rect(Rect2(pos + Vector2(0, -140), Vector2(4, 140)), Color(BLUE.r * 2.2, BLUE.g * 2.2, BLUE.b * 2.2, ba))
	var bob: float = sin(t * 3.5) * 2.0 if ground else 0.0
	var c: Vector2 = pos + Vector2(0, -gz - 4.0 + bob)
	if ground:
		# 脉冲：像素点圈，红 / 蓝相间
		var k: float = fmod(t + sd, 1.2) / 1.2
		var rr: float = 22.0 + 68.0 * k
		var a: float = (1.0 - k) * 0.85
		w._pq_guard(Rect2(c - Vector2(rr + 3.0, rr + 3.0), Vector2(rr + 3.0, rr + 3.0) * 2.0))
		for i in 16:
			var p: Vector2 = (c + Vector2.from_angle(TAU * i / 16.0 + sd) * rr).snapped(Vector2(px, px))
			var pc: Color = RED_L if i % 2 == 0 else BLUE_L
			w._pb.rect(Rect2(p - Vector2(px, px), Vector2(px, px) * 2.0), Color(pc.r * 2.2, pc.g * 2.2, pc.b * 2.2, a))
		# 铁屑：4 簇朝磁铁聚拢，到了弹开
		for q in 4:
			var ph: float = fmod(t / 2.4 + q * 0.25 + sd * 0.1, 1.0)
			var dist: float = 44.0 - 26.0 * (ph / 0.75) if ph < 0.75 else 18.0 + 26.0 * ((ph - 0.75) / 0.25)
			var ang: float = sd + q * TAU / 4.0 + 0.4
			var base: Vector2 = c + Vector2.from_angle(ang) * dist
			var tn: Vector2 = Vector2.from_angle(ang + PI / 2.0)
			var fa: float = 0.9 if ph < 0.75 else 0.9 * (1.0 - (ph - 0.75) / 0.25)
			for j in 4:
				var o: Vector2 = tn * float(j - 1.5) * 5.0 + Vector2.from_angle(ang) * float((j * 5) % 3 - 1) * 3.0
				w._pb.rect(Rect2((base + o).snapped(Vector2(px, px)), Vector2(px * 2.0, px * (2.0 if j % 2 == 0 else 3.0))), Color(FILING.r * 1.5, FILING.g * 1.5, FILING.b * 1.5, fa))
	# 本体
	var tx: Texture2D = tex()
	var size := Vector2(W, W) * px
	var dst := Rect2((c - size / 2.0).snapped(Vector2(px, px)), size)
	w._pq_guard(dst)
	w._pq_spr.append([tx, dst, Rect2(0, 0, W, W)])
	w._pq_rects.append(dst)
	# 磁极亮像素（画在贴图之上：先交贴图批）
	w._pq_flush()
	var gl: float = 2.4 + 0.6 * sin(t * 6.0 + sd)
	w._pb.rect(Rect2(dst.position + Vector2(3, 1) * px, Vector2(px, px)), Color(RED_L.r * gl, RED_L.g * gl, RED_L.b * gl))
	w._pb.rect(Rect2(dst.position + Vector2(13, 1) * px, Vector2(px, px)), Color(BLUE_L.r * gl, BLUE_L.g * gl, BLUE_L.b * gl))
