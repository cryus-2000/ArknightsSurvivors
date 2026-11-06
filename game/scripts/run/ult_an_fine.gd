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
	return mode() > 0


## 0 旧版帧条 / 1 细螺旋 / 2 引力黑洞（缺省；11-07 用户「做成那种引力黑洞的感觉是不是更加华丽一点」）
static func mode() -> int:
	return int(Bal.v("ult/an_fine", 2.0))


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
		if mode() >= 2:
			_paint_bh(u, img, s, n, G, float(beat) / FPS)
		else:
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


## ── 引力黑洞版（ult/an_fine = 2，11-07 用户「做成那种引力黑洞的感觉是不是更加华丽一点」）──
## 元素三种：① 吸积盘（压扁成椭圆的细光流，开普勒转速：越靠里越快；迎面一侧（左）近白、背离一侧退成暗紫——多普勒增亮）；
## ② 视界（纯黑影 + 1 格光子环 + 越过黑影顶上的透镜弧，即盘背面被引力弯上来的像）；③ 往里落的细碎片。
## 另外后期层引力透镜（post.gdshader lens）：视界外一圈地面 / 敌人被往里挤、拖着转。视界以内不扭。
## 画法：盘背面 → 黑影 → 光子环 / 透镜弧 → 盘前面（挡住黑影下沿）→ 碎片。全是 1 格线，调色板 5 级
const BH_P := [Color("#f6eeff"), Color("#dcc8fb"), Color("#b280f2"), Color("#7a58bf"), Color("#45307a")]
const BH_SQ := 0.38      # 盘的倾角（椭圆短轴 / 长轴）
const BH_NR := 26        # 盘的轨道圈数


static func bh_rh(R: float, k: float) -> float:
	return R * lerpf(0.075, 0.12, clampf(k, 0.0, 1.0))   # 视界半径（世界）


static func _bh_col(u, v: float) -> Color:
	if v > 0.8:
		return u._pc(BH_P[0], 1.0)
	if v > 0.62:
		return u._pc(BH_P[1], 1.0)
	if v > 0.42:
		return u._pc(BH_P[2], 1.0)
	if v > 0.25:
		return u._pc(BH_P[3], 0.95)
	return u._pc(BH_P[4], 0.85)


static func _bh_disk(u, img: Image, n: int, h0: float, sd: float, k: float, tq: float, rin: float, rout: float, front: bool) -> void:
	for i in BH_NR:
		var hr: float = _h(sd + float(i) * 2.3)
		var f: float = pow((float(i) + hr) / float(BH_NR), 1.4)
		var r: float = rin + (rout - rin) * f
		var w: float = pow(rin / r, 1.5)
		var ph: float = (2.2 * tq + 1.6 * tq * tq) * w * 2.0            # 越吸越快、越靠里越快
		var heat: float = 1.0 - f
		var m: int = 4 + int(6.0 * (1.0 - f))
		for j in m:
			var hj: float = _h(sd * 0.7 + float(i) * 7.1 + float(j) * 3.3)
			if hj > 0.25 + 0.75 * k:
				continue   # 盘慢慢聚起来
			var a0: float = TAU * (float(j) + hj) / float(m) + ph
			var la: float = (0.3 + 0.45 * hj) * (0.6 + 0.6 * heat)
			var steps: int = int(la * r) + 1
			for st in steps:
				var qs: float = float(st) / float(steps)
				var th: float = a0 - la * qs   # 头在前、尾巴拖在后
				if (sin(th) > 0.0) != front:
					continue
				var dop: float = 0.5 * (1.0 - cos(th))
				var v: float = (0.5 * heat + 0.5 * dop) * (1.0 - 0.65 * qs) * (0.55 + 0.45 * k)
				if v < 0.12:
					continue
				_put(img, n, int(floorf(h0 + cos(th) * r)), int(floorf(h0 + sin(th) * r * BH_SQ)), _bh_col(u, v))


static func _paint_bh(u, img: Image, s: Dictionary, n: int, G: float, tq: float) -> void:
	var k: float = clampf(float(s.k), 0.0, 1.0)
	var sd: float = float(s.seed)
	var R: float = float(s.R)
	var h0: float = float(n / 2)
	var rh: float = maxf(5.0, bh_rh(R, k) / G)
	var rin: float = rh * 1.55
	var rout: float = R * 0.66 * (1.0 - 0.15 * k) / G
	_bh_disk(u, img, n, h0, sd, k, tq, rin, rout, false)
	# 视界黑影 + 光子环（左亮右暗、按弧段轻闪）
	var rr: int = int(ceil(rh)) + 4
	var black := Color("#04020a")
	for yy in range(-rr, rr + 1):
		for xx in range(-rr, rr + 1):
			var d: float = sqrt(float(xx * xx + yy * yy))
			var x: int = int(h0) + xx
			var y: int = int(h0) + yy
			if d <= rh:
				_put(img, n, x, y, black)
				continue
			var ang: float = atan2(float(yy), float(xx))
			var dop: float = 0.5 * (1.0 - cos(ang))
			if d <= rh + 1.0:
				var fl: float = _h(sd + floorf((ang + PI) * 5.0) + floorf(tq * 15.0) * 0.37)
				_put(img, n, x, y, _bh_col(u, 0.55 + 0.3 * dop + 0.15 * fl))
			elif yy < 0 and d > rh + 1.6 and d <= rh + 3.4:
				# 透镜弧：盘背面被弯到黑影顶上，越靠正上方越亮；按角度切成流动的断续段
				var top: float = -float(yy) / d
				var sa: float = (ang + PI) * rh * 0.9 - tq * 18.0
				if fposmod(sa, 6.0) > 4.6:
					continue
				var v: float = (0.35 + 0.45 * top + 0.25 * dop) * (0.4 + 0.6 * k) * (1.0 if d <= rh + 2.5 else 0.7)
				if v > 0.2:
					_put(img, n, x, y, _bh_col(u, v))
			elif yy > 0 and d > rh + 1.4 and d <= rh + 2.4 and k > 0.3:
				_put(img, n, x, y, _bh_col(u, 0.28 + 0.2 * dop))   # 下方次像：细、暗
	_bh_disk(u, img, n, h0, sd, k, tq, rin, rout, true)
	# 往里落的碎片：在盘面上沿螺旋落向视界（头近白、尾紫）
	for j in 18:
		var hj: float = _h(sd * 1.3 + float(j) * 5.7)
		var ph: float = fposmod(tq * (0.9 + 0.7 * k) + hj, 1.0)
		var r2: float = lerpf(rout * (0.75 + 0.25 * hj), rin * 0.9, ph * ph)
		var th2: float = TAU * (float(j) + hj) / 18.0 + 2.6 * ph + tq * 2.0
		var p2 := Vector2(cos(th2) * r2, sin(th2) * r2 * BH_SQ)
		var th3: float = th2 - 1.6 / maxf(4.0, r2)
		var p3 := Vector2(cos(th3) * (r2 + 1.0), sin(th3) * (r2 + 1.0) * BH_SQ)
		_put(img, n, int(floorf(h0 + p3.x)), int(floorf(h0 + p3.y)), u._pc(BH_P[2], 1.0))
		_put(img, n, int(floorf(h0 + p2.x)), int(floorf(h0 + p2.y)), u._pc(BH_P[0], 1.0))


## 每帧写后期层的引力透镜（只黑洞版；没续上 0.15 秒后 post_fx 自动关）
static func lens_tick(u, s: Dictionary) -> void:
	if mode() < 2:
		return
	var g = u.g
	if g == null or g.post == null or not ("lens" in g.post):
		return
	var cfg = g.get_node_or_null("/root/Cfg") if g.is_inside_tree() else null
	if cfg != null and cfg.reduce_motion:
		return
	var vs: Vector2 = g.get_viewport().get_visible_rect().size
	var ct: Transform2D = g.hud_ct()
	var sp: Vector2 = ct * Vector2(s.c)
	var k: float = clampf(float(s.k), 0.0, 1.0)
	var rh: float = bh_rh(float(s.R), k) * ct.get_scale().x / maxf(1.0, vs.y)
	g.post.lens = Vector4(sp.x / maxf(1.0, vs.x), sp.y / maxf(1.0, vs.y), rh, smoothstep(0.0, 0.35, k))
	g.post.lens2 = Vector2(5.5, lerpf(0.6, 1.4, k))
	g.post.lens_ttl = 0.15
