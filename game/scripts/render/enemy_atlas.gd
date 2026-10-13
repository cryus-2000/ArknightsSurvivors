extends RefCounted
## 普通怪 / 精英帧条图集（性能 docs/50 §12，用户 10-13「稳定 60 帧」）：
## 每只敌人原来各用自己的帧条贴图（本体是带法线的 CanvasTexture，受击白闪是另一张白剪影），y 排序后几乎每次绘制都换贴图、不能合批。
## 开局把普通怪 / 精英（Boss、骑士除外）的全部帧条拼进一张图集：
##   tex_body  —— 本体：漫反射图集 + 同排布的法线图集（法线光照关着时只有漫反射），和原来的 CanvasTexture 同样的纹理过滤
##   tex_white —— 受击白闪：白剪影图集，排布与本体完全相同（同一个原点），和原来一样不带法线（白闪的受光不变）
## 每条帧条整条原样拷进去（帧之间的相邻关系不变），四周留 PAD 像素透明边（原帧条边缘外是夹边取样，边缘本来就透明），
## 所以取同一帧的区域画出来与原贴图逐像素相同；绘制几何（锚点 / 缩放 / 翻转变换 / 取整）照 vfx.spr。
## 读不到像素（无头空驱动）或缺法线 / 白剪影的帧条不进图集，照旧走原贴图。

const PAD := 2
## 翻转的画法。缺省（true）照旧 draw_set_transform(-1, 1)（变换不断批，只多两次调用）。
## 负宽矩形（--atlasflip=neg，仅调试对照）省掉那两次调用，但引擎会把法线 x 一起翻（变换翻转时法线不翻），
## 朝左的敌人受灯光的明暗左右对调——10-13 逐像素对照每帧差 5–16 千像素，画面变了，所以缺省不用（docs/50 §12）
static var xform_flip := true
const WIDTH := 1024

var tex_body: Texture2D = null
var tex_white: Texture2D = null
## 名字 -> [贴图, 原点 Vector2i, 帧条宽, 帧条高]；本体名和「名字_white」都登记（白剪影指向 tex_white、同一原点）
var reg := {}
var n_strips := 0
var px_used := 0


static func _rgba(t: Texture2D) -> Image:
	if t == null:
		return null
	var img: Image = t.get_image()
	if img == null or img.is_empty():
		return null
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


## names：候选帧条名（本体名）；g.tex 里要同时有本体和「名字_white」
func build(tex: Dictionary, names: Array) -> void:
	var items: Array = []   # [名字, 漫反射, 法线 or null, 白剪影]
	var with_nm := 0
	for n in names:
		var t: Texture2D = tex.get(n)
		var w: Texture2D = tex.get(n + "_white")
		if t == null or w == null:
			continue
		var d: Texture2D = t.diffuse_texture if t is CanvasTexture else t
		var nm: Texture2D = t.normal_texture if t is CanvasTexture else null
		var di := _rgba(d)
		var wi := _rgba(w)
		if di == null or wi == null or di.get_size() != wi.get_size():
			continue
		var ni: Image = null
		if nm != null:
			ni = _rgba(nm)
			if ni == null or ni.get_size() != di.get_size():
				continue
			with_nm += 1
		items.append([n, di, ni, wi])
	if items.is_empty():
		return
	# 法线：要么全有、要么全无（有法线的进图集时，缺法线的不进，免得它在图集里吃到法线光照）
	var use_nm := with_nm > 0
	items = items.filter(func(it): return (it[2] != null) == use_nm)
	# 货架装箱：按高度从高到低，一行放满换行
	items.sort_custom(func(a, b): return a[1].get_height() > b[1].get_height() or (a[1].get_height() == b[1].get_height() and a[0] < b[0]))
	var pos := {}
	var x := PAD
	var y := PAD
	var row_h := 0
	for it in items:
		var s: Vector2i = it[1].get_size()
		if s.x + PAD * 2 > WIDTH:
			continue
		if x + s.x + PAD > WIDTH:
			x = PAD
			y += row_h + PAD
			row_h = 0
		pos[it[0]] = Vector2i(x, y)
		x += s.x + PAD
		row_h = maxi(row_h, s.y)
	var h: int = y + row_h + PAD
	var bd := Image.create(WIDTH, h, false, Image.FORMAT_RGBA8)
	var bw := Image.create(WIDTH, h, false, Image.FORMAT_RGBA8)
	var bn: Image = null
	if use_nm:
		bn = Image.create(WIDTH, h, false, Image.FORMAT_RGBA8)
		bn.fill(Color8(127, 127, 255, 255))   # 透明边的法线：平面（和法线图里 alpha 外的像素同值；透明处不出像素，只是保险）
	for it in items:
		if not pos.has(it[0]):
			continue
		var o: Vector2i = pos[it[0]]
		var s: Vector2i = it[1].get_size()
		bd.blit_rect(it[1], Rect2i(Vector2i.ZERO, s), o)
		bw.blit_rect(it[3], Rect2i(Vector2i.ZERO, s), o)
		if bn != null:
			bn.blit_rect(it[2], Rect2i(Vector2i.ZERO, s), o)
		n_strips += 1
		px_used += s.x * s.y
	var dt := ImageTexture.create_from_image(bd)
	tex_white = ImageTexture.create_from_image(bw)
	if bn != null:
		var ct := CanvasTexture.new()
		ct.diffuse_texture = dt
		ct.normal_texture = ImageTexture.create_from_image(bn)
		ct.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # 同 art.gd _with_normal
		tex_body = ct
	else:
		tex_body = dt
	for it in items:
		if not pos.has(it[0]):
			continue
		var s2: Vector2i = it[1].get_size()
		reg[it[0]] = [tex_body, pos[it[0]], s2.x, s2.y]
		reg[it[0] + "_white"] = [tex_white, pos[it[0]], s2.x, s2.y]


## 照 vfx.spr 画一帧（pos 已含 draw_off）；r = reg[名字]
static func spr(ci: CanvasItem, r: Array, frames: int, frame: int, pos: Vector2, scale: float, flip: bool, col: Color, anchor: Vector2, sq: Vector2) -> void:
	var o: Vector2i = r[1]
	var fw: int = r[2] / frames
	var fh: int = r[3]
	var src := Rect2(o.x + fw * (frame % frames), o.y, fw, fh)
	var size := Vector2(fw, fh) * scale * sq
	if flip:
		if xform_flip:
			ci.draw_set_transform(pos.round(), 0.0, Vector2(-1, 1))
			ci.draw_texture_rect_region(r[0], Rect2(-size * anchor, size), src, col)
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			return
		# 负宽矩形 = 引擎记水平翻转（UV 与法线一起翻），省掉成对的 draw_set_transform；
		# 落点与「在 pos.round() 处 scale(-1, 1) 画 Rect2(-size × anchor, size)」相同：右边界 = round(pos).x + size.x × anchor.x
		var rp: Vector2 = pos.round()
		ci.draw_texture_rect_region(r[0], Rect2(rp.x + size.x * anchor.x, rp.y - size.y * anchor.y, -size.x, size.y), src, col)
	else:
		ci.draw_texture_rect_region(r[0], Rect2((pos - size * anchor).round(), size), src, col)
