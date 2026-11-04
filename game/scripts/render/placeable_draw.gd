extends RefCounted
## 支援藏品放置物第二版画法（docs/245，render/placeable_v2，缺省 0 = 旧的暗圆 / 矩形）：
##   地雷（210，原作干扰地雷造型）/ 轰隆隆（211，原作轰隆隆先生造型）/ 防暴桩（213，原作防暴桩造型）。
## 运行时用代码逐像素画（1 美术像素 = 2 世界像素，Game.PX），开局第一次用到时生成贴图缓存，不读任何美术文件。
## 分两遍：draw_ground（敌人之下：警示虚线圈、影子、焦痕）与 draw_upper（敌人之上：装置本体、呼吸亮点、爆炸）。
## 只画不改玩法：不碰 g.rng 等玩法随机流；爆炸的散布用位置哈希。往 mines / bombs / stakes 字典里写的键都以 _v 开头，只有这里读


const PX := 2.0
const OUTLINE := Color8(0xdc, 0xec, 0xf2)   # 冷白描边
const MINE_CORE := Color8(0xff, 0x6a, 0x2e)
const BOMB_LAMP := Color8(0x3f, 0xe0, 0xa0)
const STAKE_LAMP := Color8(0xff, 0x9a, 0x2a)
## 防暴桩警示纹色板（render/placeable_stake_pal）：0 现状黄 / 1 偏橙 / 2 偏白（警示黄与经验结晶暖金同色系，备选两套）
const STAKE_HAZ := [Color8(0xf0, 0xc0, 0x20), Color8(0xff, 0x7a, 0x1e), Color8(0xee, 0xf2, 0xf4)]

static var _tex := {}   # 名字 → ImageTexture

var g
var booms: Array = []      # {k: "mine" / "bomb", p, t0, h}
var scorches: Array = []   # {p, t0, h}


func _init(game) -> void:
	g = game


static func on() -> bool:
	return Bal.v("render/placeable_v2", 0.0) > 0.0


const Bal = preload("res://scripts/core/balance.gd")
static var _look = null   # render/look.gd，用到时再载（它依赖自动加载 Cfg；展示脚本里不开本色就不载）


## 装置按本色显示（render/placeable_unlit，缺省 1）：同干员的「不吃灯火」（look.op_unlit_mod 抵消环境暗色与灯火），
## 离灯远时也不发暗发褐；0 = 和地面一样受光
var _unlit := 1.0
func _mod(pos: Vector2, col := Color.WHITE) -> Color:
	if _unlit <= 0.0:
		return col
	if _look == null:
		_look = load("res://scripts/render/look.gd")
	var m: Color = _look.op_unlit_mod(g, pos)
	m = Color.WHITE.lerp(m, _unlit)
	return Color(col.r * m.r, col.g * m.g, col.b * m.b, col.a)


# ---------------- 贴图生成（美术像素坐标） ----------------

static func _img(w: int, h: int) -> Image:
	return Image.create(w, h, false, Image.FORMAT_RGBA8)


static func _px(im: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < im.get_width() and y < im.get_height():
		im.set_pixel(x, y, c)


static func _rect(im: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_px(im, x, y, c)


## 凸 / 凹多边形填充：像素中心落在多边形里就涂
static func _poly(im: Image, pts: PackedVector2Array, c: Color) -> void:
	var bb := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		bb = bb.expand(p)
	for y in range(int(floor(bb.position.y)), int(ceil(bb.end.y)) + 1):
		for x in range(int(floor(bb.position.x)), int(ceil(bb.end.x)) + 1):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), pts):
				_px(im, x, y, c)


## 四邻接描边：透明且挨着不透明像素的格子涂描边色；落在 keep_out 多边形里的不描（地雷四臂之间的空隙）
static func _outline(im: Image, c: Color, keep_out := PackedVector2Array(), allow := Rect2i()) -> void:
	var w := im.get_width()
	var h := im.get_height()
	var add: Array = []
	for y in h:
		for x in w:
			if im.get_pixel(x, y).a > 0.0:
				continue
			if not keep_out.is_empty() and Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), keep_out) and not allow.has_point(Vector2i(x, y)):
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + d
				if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and im.get_pixel(q.x, q.y).a > 0.0 and im.get_pixel(q.x, q.y) != c:
					add.append(Vector2i(x, y))
					break
	for p in add:
		im.set_pixel(p.x, p.y, c)


## 地雷 28×18（含 1 格描边余量）：黑色方底座 + X 形四臂装甲板（橄榄绿、深色接缝、下沿厚度）+ 中心橙红芯
const MINE_W := 28
const MINE_H := 18
const MINE_C := Vector2(14, 9)   # 中心（贴图坐标），对准地雷位置
const MINE_TIPS := [Vector2(2, 2.5), Vector2(26, 2.5), Vector2(26, 15.5), Vector2(2, 15.5)]
const MINE_CORE_RECT := Rect2i(12, 7, 4, 3)

static func mine_image() -> Image:
	var im := _img(MINE_W, MINE_H)
	var c := MINE_C
	# 四臂装甲板：从底座四角斜伸到四个臂尖。先画下沿厚度（下移一格深色），再画板面（朝上半边亮一档），一道深色横缝，端面压暗
	var arms: Array = []
	for tip in MINE_TIPS:
		var d: Vector2 = (tip - c).normalized()
		var n := Vector2(-d.y, d.x)
		var a: Vector2 = c + d * 4.0
		arms.append([a, tip, n, 2.1, d])
	for arm in arms:
		var a: Vector2 = arm[0]; var b: Vector2 = arm[1]; var n: Vector2 = arm[2]; var hw: float = arm[3]
		var sh := Vector2(0, 1.5)
		_poly(im, PackedVector2Array([a + n * hw + sh, b + n * hw + sh, b - n * hw + sh, a - n * hw + sh]), Color8(0x2c, 0x33, 0x18))
	for arm in arms:
		var a: Vector2 = arm[0]; var b: Vector2 = arm[1]; var n: Vector2 = arm[2]; var hw: float = arm[3]; var d: Vector2 = arm[4]
		_poly(im, PackedVector2Array([a + n * hw, b + n * hw, b - n * hw, a - n * hw]), Color8(0x6b, 0x7a, 0x3a))
		var up: Vector2 = n if n.y < 0.0 else -n
		_poly(im, PackedVector2Array([a + up * hw, b + up * hw, b + up * 0.3, a + up * 0.3]), Color8(0x8c, 0x9c, 0x4c))
		# 横缝：板长 55% 处，垂直于板
		var m: Vector2 = a.lerp(b, 0.55)
		_poly(im, PackedVector2Array([m + n * (hw + 0.2) - d * 0.55, m + n * (hw + 0.2) + d * 0.55, m - n * (hw + 0.2) + d * 0.55, m - n * (hw + 0.2) - d * 0.55]), Color8(0x2f, 0x36, 0x1c))
		# 端面
		_poly(im, PackedVector2Array([b + n * hw, b - n * hw, b - n * hw - d * 1.3, b + n * hw - d * 1.3]), Color8(0x4c, 0x58, 0x28))
	# 黑色方底座（俯视顶面 10×6 + 前侧面 2 格），压在四臂根部上
	_rect(im, 9, 5, 18, 11, Color8(0x1c, 0x1f, 0x24))
	_rect(im, 9, 5, 18, 5, Color8(0x3a, 0x40, 0x48))
	_rect(im, 9, 5, 9, 11, Color8(0x2a, 0x2e, 0x34))
	_rect(im, 9, 12, 18, 13, Color8(0x0b, 0x0c, 0x0e))
	# 中心芯：橙红 4×3、下沿暗红、左上高光，外围一圈凹槽
	var cr := MINE_CORE_RECT
	_rect(im, cr.position.x - 1, cr.position.y - 1, cr.end.x, cr.end.y, Color8(0x0e, 0x10, 0x13))
	_rect(im, cr.position.x, cr.position.y, cr.end.x - 1, cr.end.y - 1, MINE_CORE)
	_rect(im, cr.position.x, cr.end.y - 1, cr.end.x - 1, cr.end.y - 1, Color8(0xa8, 0x34, 0x14))
	_px(im, cr.position.x, cr.position.y, Color8(0xff, 0xc8, 0x9c))
	# 描边只描外轮廓：四臂尖连成的外框里（臂间空隙）一律不描，空隙透出地面与影子
	_outline(im, OUTLINE, PackedVector2Array(MINE_TIPS))
	return im


## 轰隆隆 23×20（正面视角；含描边余量）：宽而扁的弧面装甲板（像阔剑地雷：正面略内凹、两端向后收成圆角），
## 正面中央白色菱形徽记（菱形里套小菱形）、下方深色横槽、两侧散热横纹；底下三条细长支脚向外张开；天线从顶部一侧伸出（薄荷绿灯）
const BOMB_W := 23
const BOMB_H := 20
const BOMB_FOOT := Vector2(11.5, 19)   # 脚底中点（贴图坐标）
const BOMB_LAMP_P := Vector2i(17, 1)   # 天线灯 2×2 左上角
const BOMB_GEM := Vector2i(11, 7)      # 菱形徽记中心（呼吸亮点）
const BOMB_TILT_ROW := 11              # 倾斜时这一行以上整体朝移动方向错 1 格

## 板面上下沿：两端高、中间低 1 格（正面略内凹的弧）
static func _bomb_top(x: int) -> int:
	return 5 if x >= 6 and x <= 16 else 4


static func bomb_image(step: int) -> Image:
	var im := _img(BOMB_W, BOMB_H)
	# 三脚架：左右两条向外张开、中间一条在后（暗）；step 0 抬左脚、1 抬右脚
	var dark := Color8(0x26, 0x29, 0x2e)
	var leg := Color8(0x4a, 0x50, 0x58)
	var foot := Color8(0x6a, 0x72, 0x7b)
	_rect(im, 11, 13, 11, 17, dark)
	_px(im, 11, 18, Color8(0x1a, 0x1c, 0x20))
	for side in [-1, 1]:
		var lift: int = 1 if (side < 0) == (step == 0) else 0
		var x0: int = 11 + side * 5
		for k in 5:   # 斜向外张开的细长支脚：每两行外移一格
			var yy: int = 13 + k
			if yy <= 17 - lift:
				_px(im, x0 + side * ((k + 1) / 2), yy, leg)
		_rect(im, mini(x0 + side * 2, x0 + side * 3), 18 - lift, maxi(x0 + side * 2, x0 + side * 3), 18 - lift, foot)
	# 装甲板：x 2–20，上沿 4/5、下沿 12/13（内凹弧），两端各收 2 格成圆角
	for x in range(2, 21):
		var top: int = _bomb_top(x)
		var bot: int = top + 8
		var y0: int = top + (1 if x == 2 or x == 20 else 0)
		var y1: int = bot - (1 if x == 2 or x == 20 else 0)
		for y in range(y0, y1 + 1):
			var c := Color8(0x8b, 0x91, 0x99)
			if y == y0:
				c = Color8(0xcc, 0xd2, 0xd8)
			elif y <= top + 2:
				c = Color8(0xae, 0xb4, 0xbb)
			elif y >= bot - 1:
				c = Color8(0x5d, 0x63, 0x6b)
			if x <= 3 or x >= 19:
				c = c.darkened(0.22)   # 两端向后收：暗一档
			elif (x >= 6 and x <= 16) and y > top + 2 and y < bot - 1:
				c = Color8(0x80, 0x86, 0x8e)   # 中段内凹：比两侧略暗
			im.set_pixel(x, y, c)
	# 两侧散热横纹（各 3 道）
	for y in [7, 9, 11]:
		_rect(im, 4, y, 6, y, Color8(0x55, 0x5b, 0x63))
		_rect(im, 16, y, 18, y, Color8(0x55, 0x5b, 0x63))
	# 菱形徽记：外菱形白，里面套一个灰蓝小菱形（呼吸亮点在小菱形上）
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var d: int = absi(dx) + absi(dy)
			if d <= 3:
				_px(im, BOMB_GEM.x + dx, BOMB_GEM.y + dy + 1, Color8(0xf4, 0xf6, 0xf8) if d >= 2 else Color8(0x86, 0x96, 0x9e))
	# 下方深色横槽
	_rect(im, 8, 12, 14, 12, Color8(0x22, 0x26, 0x2c))
	# 天线：顶部右侧伸出，顶端薄荷绿灯
	_px(im, 17, 4, Color8(0x3a, 0x3e, 0x44))
	_px(im, 17, 3, Color8(0x3a, 0x3e, 0x44))
	_rect(im, BOMB_LAMP_P.x, BOMB_LAMP_P.y, BOMB_LAMP_P.x + 1, BOMB_LAMP_P.y + 1, BOMB_LAMP)
	_outline(im, OUTLINE)
	return im


## 防暴桩 18×30（含描边余量）：顶上琥珀灯、金属框、方箱、白色标牌、黄黑警示纹底座
const STAKE_W := 18
const STAKE_H := 30
const STAKE_FOOT := Vector2(9, 29)
const STAKE_LAMP_R := Rect2i(7, 1, 4, 3)

static func stake_image(pal: int) -> Image:
	var im := _img(STAKE_W, STAKE_H)
	var hz: Color = STAKE_HAZ[clampi(pal, 0, STAKE_HAZ.size() - 1)]
	# 灯：灯座 + 琥珀灯罩 + 顶部高光 + 中间一道护栏
	_rect(im, 6, 4, 11, 5, Color8(0x3a, 0x3f, 0x45))
	_rect(im, STAKE_LAMP_R.position.x, STAKE_LAMP_R.position.y, STAKE_LAMP_R.end.x - 1, STAKE_LAMP_R.end.y - 1, STAKE_LAMP)
	_rect(im, 8, 1, 9, 1, Color8(0xff, 0xd8, 0xa0))
	_rect(im, 7, 3, 10, 3, Color8(0xc0, 0x64, 0x14))
	# 金属框：顶梁 + 两根立柱
	_rect(im, 2, 6, 15, 7, Color8(0x9a, 0xa4, 0xad))
	_rect(im, 2, 6, 15, 6, Color8(0xc8, 0xd0, 0xd6))
	_rect(im, 2, 6, 2, 21, Color8(0x8a, 0x94, 0x9d))
	_rect(im, 15, 6, 15, 21, Color8(0x6a, 0x74, 0x7d))
	# 方箱
	_rect(im, 3, 8, 14, 20, Color8(0x3c, 0x46, 0x50))
	_rect(im, 13, 8, 14, 20, Color8(0x2c, 0x34, 0x3c))
	_rect(im, 3, 8, 12, 8, Color8(0x4e, 0x5a, 0x66))
	# 白色标牌 + 警示图形（感叹号）
	_rect(im, 5, 10, 12, 16, Color8(0xe9, 0xed, 0xf0))
	_rect(im, 5, 16, 12, 16, Color8(0xb9, 0xc0, 0xc6))
	_rect(im, 8, 11, 9, 13, Color8(0x1a, 0x1d, 0x20))
	_rect(im, 8, 15, 9, 15, Color8(0x1a, 0x1d, 0x20))
	# 底座：上沿金属、斜向警示纹、下沿暗面
	_rect(im, 1, 21, 16, 21, Color8(0x70, 0x7a, 0x83))
	for y in range(22, 28):
		for x in range(1, 17):
			var stripe: bool = ((x + y) / 3) % 2 == 0
			im.set_pixel(x, y, hz if stripe else Color8(0x17, 0x18, 0x1a))
	_rect(im, 1, 27, 16, 28, Color8(0x0e, 0x0f, 0x10))
	_rect(im, 1, 27, 16, 27, hz.darkened(0.55))
	_outline(im, OUTLINE)
	return im


static func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		var im: Image
		match name:
			"mine":
				im = mine_image()
			"bomb0":
				im = bomb_image(0)
			"bomb1":
				im = bomb_image(1)
			_:
				im = stake_image(int(name.substr(5)))   # "stake0" / "stake1" / "stake2"
		_tex[name] = ImageTexture.create_from_image(im)
	return _tex[name]


# ---------------- 绘制辅助（世界坐标，对齐 2 像素网格） ----------------

static func _snap(v: float) -> float:
	return floorf(v / PX) * PX


## 像素化实心椭圆：逐行（2 像素一行）画横条
var _bm := Color.WHITE   # 爆炸绘制的本色倍率（_draw_booms 里按爆点取，地面那遍为白）
func _qdisc(cv: CanvasItem, c: Vector2, r: float, sy: float, col: Color) -> void:
	if r < 1.0 or col.a <= 0.0:
		return
	col = Color(col.r * _bm.r, col.g * _bm.g, col.b * _bm.b, col.a)
	var ry: float = maxf(PX, r * sy)
	var y := -ry
	while y < ry:
		var k: float = (y + PX * 0.5) / ry
		var hw: float = _snap(r * sqrt(maxf(0.0, 1.0 - k * k)) + PX * 0.5)
		if hw > 0.0:
			cv.draw_rect(Rect2(_snap(c.x) - hw, _snap(c.y + y), hw * 2.0, PX), col)
		y += PX


## 像素化椭圆环（内外两个半径之间）
func _qring(cv: CanvasItem, c: Vector2, r0: float, r1: float, sy: float, col: Color) -> void:
	if r1 < 1.0 or col.a <= 0.0:
		return
	col = Color(col.r * _bm.r, col.g * _bm.g, col.b * _bm.b, col.a)
	var ry: float = maxf(PX, r1 * sy)
	var y := -ry
	while y < ry:
		var k: float = (y + PX * 0.5) / ry
		var ho: float = _snap(r1 * sqrt(maxf(0.0, 1.0 - k * k)) + PX * 0.5)
		var ki: float = (y + PX * 0.5) / maxf(PX, r0 * sy)
		var hi: float = _snap(r0 * sqrt(maxf(0.0, 1.0 - ki * ki)) + PX * 0.5) if absf(ki) < 1.0 else 0.0
		var x0: float = _snap(c.x)
		var yy: float = _snap(c.y + y)
		if hi <= 0.0:
			cv.draw_rect(Rect2(x0 - ho, yy, ho * 2.0, PX), col)
		elif ho > hi:
			cv.draw_rect(Rect2(x0 - ho, yy, ho - hi, PX), col)
			cv.draw_rect(Rect2(x0 + hi, yy, ho - hi, PX), col)
		y += PX


static func _hash(p: Vector2, k: int) -> float:
	var h: int = int(p.x * 7.13 + p.y * 3.71) * 73856093 ^ (k * 19349663)
	return float(absi(h) % 10007) / 10007.0


func _blit(cv: CanvasItem, tx: Texture2D, pos: Vector2, anchor: Vector2, flip: bool, col := Color.WHITE) -> void:
	var size: Vector2 = tx.get_size() * PX
	var p: Vector2 = Vector2(_snap(pos.x), _snap(pos.y))
	if flip:
		cv.draw_set_transform(p, 0.0, Vector2(-1, 1))
		cv.draw_texture_rect(tx, Rect2(-anchor * PX, size), false, col)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		cv.draw_texture_rect(tx, Rect2(p - anchor * PX, size), false, col)


## 呼吸亮点：贴图里的灯格按 bl 提亮（保持本色）、左上一格高光，外面一圈很淡的像素化光晕（加在原像素上面）
func _breath(cv: CanvasItem, tl: Vector2, cells: Vector2, base: Color, bl: float, m: Color) -> void:
	var c: Vector2 = tl + cells * PX * 0.5
	var gc: Color = base * m
	_bm = Color.WHITE
	_qdisc(cv, c, cells.x * PX * 0.5 + PX * (1.0 + bl), 0.9, Color(gc.r, gc.g, gc.b, (0.06 + 0.16 * bl) * m.a))
	var lc: Color = Color(base.r * (0.85 + 0.35 * bl), base.g * (0.85 + 0.35 * bl), base.b * (0.85 + 0.35 * bl)) * m
	cv.draw_rect(Rect2(tl, cells * PX), Color(lc.r, lc.g, lc.b, m.a))
	var hc: Color = base.lerp(Color(1, 0.97, 0.9), 0.35 + 0.5 * bl) * m
	cv.draw_rect(Rect2(tl, Vector2(PX, PX)), Color(hc.r, hc.g, hc.b, m.a))


func _born(d: Dictionary) -> float:
	if not d.has("_v0"):
		d["_v0"] = g.t
	return g.t - float(d["_v0"])


func _sy() -> float:
	return g.world.ground_y() if g.world != null and g.world.has_method("ground_y") else 0.55


# ---------------- 敌人之下 ----------------

func draw_ground(rfx) -> void:
	var cv: CanvasItem = g.wcv
	var off: Vector2 = g.draw_off
	var sy := _sy()
	# 焦痕（地雷爆点留 4 秒）
	var keep: Array = []
	for s in scorches:
		var t: float = g.t - float(s.t0)
		if t > 4.0 or t < 0.0:
			continue
		keep.append(s)
		var a: float = 0.55 * clampf((4.0 - t) / 1.5, 0.0, 1.0)
		var p: Vector2 = s.p + off
		_qdisc(cv, p, 30.0, sy, Color(0.07, 0.05, 0.04, a))
		for k in 5:
			var ang: float = _hash(s.p, k) * TAU
			var q: Vector2 = p + Vector2(cos(ang) * 30.0, sin(ang) * 30.0 * sy)
			_qdisc(cv, q, 6.0 + 6.0 * _hash(s.p, k + 9), sy, Color(0.07, 0.05, 0.04, a * 0.8))
		_qdisc(cv, p, 14.0, sy, Color(0.02, 0.015, 0.01, a))
	scorches = keep
	# 地雷：影子 + 黄色虚线警示圈（虚线慢慢转）
	for mn in rfx.mines:
		var p: Vector2 = mn.pos + off
		_qdisc(cv, p + Vector2(0, 3), 26.0, sy, Color(0, 0, 0, 0.35))
		var rx := 36.0
		var dash_n := 12
		var rot: float = g.t * 0.6
		var ca := Color8(0xf2, 0xc2, 0x30, 0xd0)
		var blink: float = 1.0 if float(mn.life) > 2.0 or fmod(g.t, 0.3) < 0.18 else 0.25
		for k in dash_n:
			var a0: float = rot + k * TAU / dash_n
			for s in 4:
				var ang: float = a0 + s * 0.07
				var q: Vector2 = p + Vector2(cos(ang) * rx, sin(ang) * rx * sy)
				cv.draw_rect(Rect2(_snap(q.x), _snap(q.y), PX, PX), Color(ca.r, ca.g, ca.b, ca.a * blink))
	for b in rfx.bombs:
		_qdisc(cv, b.pos + off + Vector2(0, 10), 18.0, sy, Color(0, 0, 0, 0.35))
	for s in rfx.stakes:
		_qdisc(cv, s.pos + off + Vector2(0, 4), 18.0, sy, Color(0, 0, 0, 0.4))


# ---------------- 敌人之上 ----------------

func draw_upper(rfx) -> void:
	var cv: CanvasItem = g.wcv
	var off: Vector2 = g.draw_off
	var t: float = g.t
	_unlit = Bal.v("render/placeable_unlit", 1.0)
	for mn in rfx.mines:
		var age: float = _born(mn)
		var p: Vector2 = mn.pos + off
		var drop: float = 0.0
		if age < 0.22:
			var u: float = age / 0.22
			drop = -26.0 * (1.0 - u) * (1.0 - u)   # 抛落：从上方落下
		var col := Color.WHITE
		if float(mn.life) < 2.0 and fmod(t, 0.3) > 0.18:
			col = Color(1, 1, 1, 0.55)   # 将要失效：闪
		var tx := tex("mine")
		col = _mod(mn.pos, col)
		_blit(cv, tx, p + Vector2(0, drop), MINE_C, false, col)
		var tl: Vector2 = Vector2(_snap(p.x), _snap(p.y + drop)) - MINE_C * PX + Vector2(MINE_CORE_RECT.position) * PX
		var bl: float = 0.5 + 0.5 * sin(t * 3.2 + mn.pos.x * 0.01)
		_breath(cv, tl, Vector2(MINE_CORE_RECT.size), MINE_CORE, bl, col)
	for b in rfx.bombs:
		var age: float = _born(b)
		var prev: Vector2 = b.get("_vp", b.pos)
		var mv: Vector2 = b.pos - prev
		b["_vp"] = b.pos
		var moving: bool = mv.length() > 0.05
		var tilt := 0.0   # 正面视角不转身：上半身朝移动方向错 1 美术像素
		if moving and absf(mv.x) > 0.05:
			tilt = PX if mv.x > 0.0 else -PX
		b["_vw"] = float(b.get("_vw", 0.0)) + mv.length()
		var step: int = int(float(b["_vw"]) / 7.0) % 2
		var hop: float = 0.0
		var sway: float = 0.0
		if age < 0.25:
			hop = -18.0 * sin(age / 0.25 * PI)
		elif moving:
			sway = PX * (1.0 if step == 0 else -1.0) * 0.5   # 左右轻微晃动（半格，落到 2 像素网格上是 0 / 1 格交替）
		var foot: Vector2 = b.pos + off + Vector2(sway, 10 + hop)
		var col := Color.WHITE
		var lt: float = float(b.life)
		if lt < 1.2 and fmod(t, 0.16) < 0.08:
			col = Color(1.6, 1.8, 1.7)   # 蓄势：寿命将尽时急闪
		var tx := tex("bomb%d" % step)
		col = _mod(b.pos, col)
		var o: Vector2 = Vector2(_snap(foot.x), _snap(foot.y)) - BOMB_FOOT * PX
		o = Vector2(roundf(o.x / PX) * PX, o.y)
		var cut: float = float(BOMB_TILT_ROW)
		# 分两段画：上半（cut 行以上）错 tilt，下半（支脚）不动
		cv.draw_texture_rect_region(tx, Rect2(o + Vector2(tilt, 0), Vector2(BOMB_W, cut) * PX), Rect2(0, 0, BOMB_W, cut), col)
		cv.draw_texture_rect_region(tx, Rect2(o + Vector2(0, cut * PX), Vector2(BOMB_W, BOMB_H - cut) * PX), Rect2(0, cut, BOMB_W, BOMB_H - cut), col)
		# 呼吸亮点：菱形里的小菱形
		var bl: float = 0.5 + 0.5 * sin(t * (9.0 if lt < 1.2 else 3.4))
		var gc: Vector2 = o + Vector2(tilt, 0) + (Vector2(BOMB_GEM) + Vector2(0, 1)) * PX
		var hc: Color = Color8(0x86, 0x96, 0x9e).lerp(Color(0.86, 1.0, 0.94), 0.2 + 0.8 * bl) * col
		_bm = Color.WHITE
		_qdisc(cv, gc + Vector2(PX * 0.5, PX * 0.5), PX * (3.0 + bl), 0.9, Color(BOMB_LAMP.r * col.r, BOMB_LAMP.g * col.g, BOMB_LAMP.b * col.b, (0.05 + 0.13 * bl) * col.a))
		for q in [Vector2(0, 0), Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
			cv.draw_rect(Rect2(gc + q * PX, Vector2(PX, PX)), Color(hc.r, hc.g, hc.b, col.a))
	var pal: int = int(Bal.v("render/placeable_stake_pal", 0.0))
	for s in rfx.stakes:
		var age: float = _born(s)
		var p: Vector2 = s.pos + off + Vector2(0, 4)
		var drop: float = 0.0
		if age < 0.18:
			var u: float = age / 0.18
			drop = -30.0 * (1.0 - u * u)
		elif age < 0.5:
			var u2: float = (age - 0.18) / 0.32
			var dc := Color(0.55, 0.52, 0.48, 0.5 * (1.0 - u2))
			_qdisc(cv, p + Vector2(-16.0 - 10.0 * u2, -2.0 - 4.0 * u2), 6.0 + 4.0 * u2, 0.8, dc)
			_qdisc(cv, p + Vector2(16.0 + 10.0 * u2, -2.0 - 4.0 * u2), 6.0 + 4.0 * u2, 0.8, dc)
		var col := Color.WHITE
		if float(s.life) < 1.5 and fmod(t, 0.3) > 0.18:
			col = Color(1, 1, 1, 0.55)
		var tx := tex("stake%d" % clampi(pal, 0, 2))
		col = _mod(s.pos, col)
		_blit(cv, tx, p + Vector2(0, drop), STAKE_FOOT, false, col)
		var tl: Vector2 = Vector2(_snap(p.x), _snap(p.y + drop)) - STAKE_FOOT * PX + Vector2(STAKE_LAMP_R.position) * PX
		var bl: float = 0.5 + 0.5 * sin(t * 2.6 + s.pos.y * 0.02)
		_breath(cv, tl, Vector2(STAKE_LAMP_R.size), STAKE_LAMP, bl, col)
	_draw_booms(cv, off)


# ---------------- 爆炸：蓄势 → 爆亮 → 余韵 → 散尽 ----------------

func boom(kind: String, p: Vector2) -> void:
	booms.append({"k": kind, "p": p, "t0": g.t})
	if kind == "mine":
		scorches.append({"p": p, "t0": g.t})
	# 光学层短命点光：照亮地面（光学关时不加）
	var gr = g.optical.grains if g.optical != null else null
	if gr != null:
		if kind == "mine":
			gr.light(p, 190.0, Color(1.0, 0.55, 0.2), 0.5)
		else:
			gr.light(p, 160.0, Color(0.45, 1.0, 0.8), 0.4)


const MINE_DUR := 1.5
const BOMB_DUR := 0.9

func _draw_booms(cv: CanvasItem, off: Vector2) -> void:
	if booms.is_empty():
		return
	var keep: Array = []
	for bm in booms:
		var t: float = g.t - float(bm.t0)
		if t < 0.0 or t > (MINE_DUR if bm.k == "mine" else BOMB_DUR):
			continue
		keep.append(bm)
		_bm = _mod(bm.p)
		if bm.k == "mine":
			_mine_boom(cv, bm.p + off, t)
		else:
			_bomb_boom(cv, bm.p + off, t)
	booms = keep
	_bm = Color.WHITE


func _mine_boom(cv: CanvasItem, p: Vector2, t: float) -> void:
	var white := Color8(0xff, 0xf4, 0xd6)
	var mid := Color8(0xff, 0xb3, 0x47)
	var outer := MINE_CORE
	if t < 0.05:
		# 蓄势：一团白热往里收
		var u: float = t / 0.05
		_qdisc(cv, p, 12.0 - 6.0 * u, 0.8, Color(1.0, 0.85, 0.6, 0.9))
		_qdisc(cv, p, 6.0 - 2.0 * u, 0.8, white)
		return
	var fb_r := 0.0
	var fb_a := 1.0
	var lift := 0.0
	if t < 0.16:
		var u: float = (t - 0.05) / 0.11
		fb_r = lerpf(12.0, 48.0, 1.0 - (1.0 - u) * (1.0 - u))
	elif t < 0.7:
		var u: float = (t - 0.16) / 0.54
		fb_r = lerpf(48.0, 30.0, u)
		fb_a = 1.0 - u * u
		lift = -14.0 * u
		outer = MINE_CORE.lerp(Color8(0x9a, 0x2c, 0x14), u)
		mid = mid.lerp(Color8(0xd8, 0x50, 0x20), u)
		white = white.lerp(Color8(0xff, 0x9a, 0x40), u)
	# 烟：三团，0.18 秒起冒，往上飘、变大、变淡
	if t > 0.18:
		var u3: float = (t - 0.18) / (MINE_DUR - 0.18)
		var offs := [Vector2(-18, -4), Vector2(16, -10), Vector2(-2, -22)]
		for k in 3:
			var o: Vector2 = offs[k] * (1.0 + 0.4 * u3)
			var r: float = lerpf(9.0, 20.0, sqrt(u3)) * (0.85 + 0.15 * k)
			var a: float = 0.85 * (1.0 - u3 * u3)
			var c: Vector2 = p + o + Vector2(0, -36.0 * u3)
			_qdisc(cv, c + Vector2(0, 2), r, 0.85, Color(0.16, 0.14, 0.13, a))
			_qdisc(cv, c - Vector2(r * 0.15, r * 0.15), r * 0.75, 0.85, Color(0.34, 0.31, 0.29, a))
	if fb_r > 0.0 and fb_a > 0.01:
		var c2: Vector2 = p + Vector2(0, lift)
		_qdisc(cv, c2, fb_r, 0.82, Color(outer.r, outer.g, outer.b, fb_a))
		_qdisc(cv, c2 - Vector2(0, fb_r * 0.08), fb_r * 0.72, 0.82, Color(mid.r, mid.g, mid.b, fb_a))
		_qdisc(cv, c2 - Vector2(0, fb_r * 0.14), fb_r * 0.4, 0.82, Color(white.r, white.g, white.b, fb_a))


func _bomb_boom(cv: CanvasItem, p: Vector2, t: float) -> void:
	var mint := BOMB_LAMP
	var pale := Color8(0xc8, 0xff, 0xe8)
	var sy := _sy()
	if t < 0.05:
		var u: float = t / 0.05
		_qdisc(cv, p, 12.0 - 6.0 * u, 0.8, Color(pale.r, pale.g, pale.b, 0.9))
		_qdisc(cv, p, 6.0 - 2.0 * u, 0.8, Color.WHITE)
		return
	if t < 0.14:
		var u: float = (t - 0.05) / 0.09
		var r: float = lerpf(12.0, 40.0, 1.0 - (1.0 - u) * (1.0 - u))
		_qdisc(cv, p, r, 0.8, Color(mint.r, mint.g, mint.b, 0.9))
		_qdisc(cv, p, r * 0.7, 0.8, pale)
		_qdisc(cv, p, r * 0.4, 0.8, Color.WHITE)
	elif t < 0.5:
		# 震荡：原地抖动的冷色地面带，不往外扩
		var u: float = (t - 0.14) / 0.36
		var wob: float = 6.0 * sin(t * 70.0) * (1.0 - u)
		var r1: float = 40.0 + wob
		var a: float = 0.9 * (1.0 - u)
		_qdisc(cv, p, r1 * 0.55, 0.8, Color(pale.r, pale.g, pale.b, a * 0.6))
		_qring(cv, p, r1 - 8.0, r1, sy * 1.2, Color(mint.r, mint.g, mint.b, a))
		_qring(cv, p, r1 - 3.0, r1, sy * 1.2, Color(pale.r, pale.g, pale.b, a))
	else:
		var u2: float = (t - 0.5) / (BOMB_DUR - 0.5)
		_qdisc(cv, p, 28.0, sy * 1.2, Color(mint.r, mint.g, mint.b, 0.3 * (1.0 - u2)))
	# 两道静电折线（0.06–0.32 秒，隔帧闪）
	if t > 0.06 and t < 0.32 and fmod(t, 0.066) < 0.044:
		for k in 2:
			var ang: float = _hash(p, k + 3) * TAU
			var q: Vector2 = p
			var pts := PackedVector2Array([q])
			for s in 5:
				var a2: float = ang + (0.9 if s % 2 == 0 else -0.9) * (0.5 + _hash(p, k * 7 + s))
				q += Vector2(cos(a2), sin(a2)) * 11.0
				pts.append(Vector2(_snap(q.x), _snap(q.y)))
			cv.draw_polyline(pts, Color(mint.r * _bm.r, mint.g * _bm.g, mint.b * _bm.b, 0.8), 4.0)
			cv.draw_polyline(pts, Color(0.94 * _bm.r, _bm.g, 0.97 * _bm.b), 2.0)
