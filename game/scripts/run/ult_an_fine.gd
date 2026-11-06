## 安洁莉娜终结技「奇点坠落」精细版（ult/an_fine，缺省 1；11-06 用户「安洁莉娜必杀技的这个太粗了，能不能精细点」）。
## 原来的旋臂是小帧条 fx_angelina_well_back 放大 3.2 倍（一个美术像素 ≈ 10 屏幕像素，几大片宽色带）、奇点是暗紫圆 30 → 90 + 粗光环，糊成一团。
## 改成代码按美术像素格（ult/px_grid）画：
##   ① 旋臂：5 条主螺旋（3 格宽：近白芯 1 格 + 两侧安洁莉娜紫各 1 格，外梢收成 1 格暗紫）+ 5 条 1 格细螺旋，按弧长切成断续碎段，碎段顺着螺旋往里流；
##   ② 奇点：暗核 + 一圈 1 格亮环 + 往里吸的细碎片（2 格短段，近白头 + 紫尾）。
## 同一招元素只有「螺旋线 / 奇点」两种（被吸的碎石、砸地冲击帧照旧）。15 fps 换帧：格子算进一张小图（一格 = 一个像素），每拍更新一次，平时只画一张贴图。
## 只画：不碰判定 / 时序 / 伤害 / 随机数（散布全按种子哈希）
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const FPS := 15.0
const NA := 5            # 主螺旋
const NB := 5            # 细螺旋
const WIND := 2.7        # 外梢到奇点绕的弧度
const COL_CORE := Color("#e8d9fb")
const COL_SIDE := Color("#b280f2")
const COL_TAIL := Color("#8765c0")
const COL_THIN := Color("#5c4a8e")
const COL_DARK := Color("#140c24")


static func on() -> bool:
	return Bal.v("ult/an_fine", 1.0) > 0.0


static func _h(x: float) -> float:
	return fposmod(sin(x * 12.9898) * 43758.5453, 1.0)


## 新建图形（挂在地面层，step 里写 k 进度 0..1、tt 时刻）
static func make(c: Vector2, R: float, seed: float) -> Dictionary:
	return {"kind": "an_fine", "c": c, "R": R, "seed": seed, "k": 0.0, "tt": 0.0, "layer": "back", "life": 3.0}


static func draw(u, s: Dictionary, dim: float) -> void:
	var G: float = u._pxg()
	var R: float = float(s.R)
	var n: int = int(ceil(R * 2.0 / G)) + 4
	var beat: int = int(floor(float(s.tt) * FPS))
	if not s.has("img") or int(s.get("beat", -1)) != beat:
		var img: Image = s.get("img")
		if img == null:
			img = Image.create(n, n, false, Image.FORMAT_RGBA8)
			s["img"] = img
		img.fill(Color(0, 0, 0, 0))
		_paint(u, img, s, n, G, float(beat) / FPS)
		if s.has("tex"):
			(s.tex as ImageTexture).update(img)
		else:
			s["tex"] = ImageTexture.create_from_image(img)
		s["beat"] = beat
	var c: Vector2 = s.c
	var o := Vector2(floorf(c.x / G) * G, floorf(c.y / G) * G) - Vector2(n / 2, n / 2) * G
	u.g.draw_texture_rect(s.tex, Rect2(o, Vector2(n, n) * G), false, Color(1, 1, 1, dim))


static func _put(img: Image, n: int, x: int, y: int, col: Color) -> void:
	if x >= 0 and y >= 0 and x < n and y < n:
		img.set_pixel(x, y, col)


static func _paint(u, img: Image, s: Dictionary, n: int, G: float, tq: float) -> void:
	var k: float = clampf(float(s.k), 0.0, 1.0)
	var sd: float = float(s.seed)
	var R: float = float(s.R)
	var h0: float = float(n / 2)
	var rc: float = lerpf(16.0, 26.0, k) / G                   # 暗核半径（格）
	var ro: float = R * 0.94 * (1.0 - 0.2 * k) / G               # 外梢（越吸越往里收）
	var ri: float = rc + 2.0
	var rot: float = -tq * lerpf(1.4, 3.6, k)                     # 越转越快
	var flow: float = tq * lerpf(26.0, 60.0, k)                  # 碎段往里流（格 / 秒）
	var cs: Color = u._pc(COL_SIDE, 1.0)
	var cc: Color = u._pc(COL_CORE, 1.0)
	var ct: Color = u._pc(COL_TAIL, 0.85)
	var cn: Color = u._pc(COL_THIN, 0.8)
	var cn2: Color = u._pc(COL_TAIL, 0.9)
	var cores: Array = []   # 芯最后画，不被相邻样点的侧边盖住
	for arm in NA + NB:
		var main: bool = arm < NA
		var ha: float = _h(sd + float(arm) * 3.1)
		var a0: float = TAU * (float(arm % NA) + (0.0 if main else 0.5) + 0.15 * (ha - 0.5)) / float(NA)
		var r_out: float = ro * (1.0 if main else 0.72 + 0.12 * ha)
		var L: float = (r_out - ri) + WIND * (r_out + ri) * 0.5        # 弧长近似（格）
		var m: int = int(L)
		var seg: float = 7.0 if main else 5.0
		var gap: float = 0.28 if main else 0.5
		for i in m:
			var q: float = float(i) / float(maxi(1, m - 1))             # 0 外梢 → 1 奇点
			var sa: float = float(i) - flow
			var si: float = floorf(sa / seg)
			if _h(sd * 0.37 + si * 1.71 + float(arm) * 9.3) < gap or fposmod(sa, seg) > seg - 1.5:
				continue   # 断续：整段空掉 + 每段末尾留 1–2 格缝
			var r: float = lerpf(r_out, ri, q)
			var th: float = a0 + rot + WIND * pow(q, 0.85)
			var dirv := Vector2.from_angle(th)
			var p: Vector2 = dirv * r
			var x: int = int(floorf(h0 + p.x))
			var y: int = int(floorf(h0 + p.y))
			if main and q > 0.18:
				var nv: Vector2 = Vector2(-dirv.y, dirv.x)   # 侧边按半径方向两侧各 1 格
				var ax: int = 1 if absf(dirv.x) >= absf(dirv.y) else 0
				var ay: int = 1 - ax
				_put(img, n, x + ax, y + ay, cs)
				_put(img, n, x - ax, y - ay, cs)
				cores.append(Vector3(x, y, 0))
			elif main:
				_put(img, n, x, y, ct)   # 外梢：1 格暗紫
			else:
				_put(img, n, x, y, cn if q < 0.6 else cn2)
	for v in cores:
		_put(img, n, int(v.x), int(v.y), cc)
	# 奇点：暗核 + 1 格亮环
	var rr: int = int(ceil(rc)) + 1
	var cd: Color = Color(COL_DARK, 0.95)
	for yy in range(-rr, rr + 1):
		for xx in range(-rr, rr + 1):
			var d: float = sqrt(float(xx * xx + yy * yy))
			if d <= rc:
				_put(img, n, int(h0) + xx, int(h0) + yy, cd)
			elif d <= rc + 1.0:
				var ang: float = atan2(float(yy), float(xx))
				var fl: float = _h(sd + floorf((ang + PI) * 4.0) + tq * 7.0)   # 亮环轻微闪动：按弧段换亮度
				_put(img, n, int(h0) + xx, int(h0) + yy, u._pc(COL_CORE, 0.75 + 0.25 * fl))
	# 往里吸的细碎片：14 段 2 格短线，近白头 + 紫尾，顺螺旋落向亮环
	for j in 14:
		var hj: float = _h(sd * 1.3 + float(j) * 5.7)
		var ph: float = fposmod(tq * (1.2 + 0.8 * k) + hj, 1.0)
		var r2: float = lerpf(rc + 1.5 + rc * 1.6 + 6.0, rc + 1.5, ph * ph)
		var th2: float = TAU * (float(j) + hj) / 14.0 + rot * 1.5 + 2.0 * ph
		var d2 := Vector2.from_angle(th2)
		var p2: Vector2 = d2 * r2
		var p3: Vector2 = d2 * (r2 + 1.0) + Vector2(-d2.y, d2.x) * 0.6
		_put(img, n, int(floorf(h0 + p3.x)), int(floorf(h0 + p3.y)), cs)
		_put(img, n, int(floorf(h0 + p2.x)), int(floorf(h0 + p2.y)), cc)
