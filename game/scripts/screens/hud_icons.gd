extends RefCounted
## HUD 图标图集（docs/50 §13，用户 10-13「稳定 60 帧」）：藏品栏的藏品图标、编队栏的立绘 / 技能图标 / 源石锭原来各是一张贴图，
## 一格换一次贴图就断一次批（藏品 20 件 = 20 次绘制调用）。用到哪张就把它（立绘只拷要画的那一帧）拷进一张图集，之后从图集取区域画。
## 区域四周留 PAD 像素透明边，源矩形相对原点的偏移照旧（含小数），HUD 是最近点取样，取到的像素与原贴图相同。
## 拷贝要读回贴图像素（网页版较慢），只在第一次用到某张图时做一次（藏品栏 / 编队栏都是签名变了才重画的缓存层）；
## 图集放不下或读不到像素时返回空矩形，调用方照旧画原贴图

const W := 1024
const H := 512
const PAD := 2

var img: Image = null
var tex: ImageTexture = null
var reg := {}         # 键 -> [图集里的原点 Vector2, 拷贝区域在原贴图里的原点 Vector2]
var _x := PAD
var _y := PAD
var _row := 0
var _dirty := false
var full := false     # 放不下了（之后的新图都退回原贴图）


static func _rgba(t: Texture2D) -> Image:
	if t is CanvasTexture:
		t = (t as CanvasTexture).diffuse_texture
	if t == null:
		return null
	var im: Image = t.get_image()
	if im == null or im.is_empty():
		return null
	im = im.duplicate()
	if im.is_compressed():
		im.decompress()
	if im.get_format() != Image.FORMAT_RGBA8:
		im.convert(Image.FORMAT_RGBA8)
	return im


## 原贴图 t 的 src 区域在图集里的源矩形；Rect2() = 不可用（画原贴图）。key 区分同一张贴图的不同帧（立绘）
func region(t: Texture2D, src: Rect2, key := "") -> Rect2:
	if t == null:
		return Rect2()
	var k: String = "%d|%s" % [t.get_instance_id(), key]
	var hit = reg.get(k)
	if hit == null:
		hit = _add(t, src, k)
	if hit == null or hit.is_empty():
		return Rect2()
	# 拷贝时按 src 外扩取整（_add）；取的时候保持 src 相对拷贝原点的偏移，取样位置与原贴图一致
	var o: Vector2 = hit[0]
	var c0: Vector2 = hit[1]
	var cs: Vector2 = hit[2]
	if src.position.x < c0.x or src.position.y < c0.y or src.end.x > c0.x + cs.x or src.end.y > c0.y + cs.y:
		return Rect2()   # 同一个键这次要的区域超出了当初拷的范围（不该发生）：退回原贴图
	return Rect2(o + (src.position - c0), src.size)


func _add(t: Texture2D, src: Rect2, k: String):
	reg[k] = []
	if full:
		return null
	var im := _rgba(t)
	if im == null:
		return null
	var c0 := Vector2i(floori(src.position.x), floori(src.position.y))
	var c1 := Vector2i(ceili(src.end.x), ceili(src.end.y))
	c0 = c0.clamp(Vector2i.ZERO, im.get_size())
	c1 = c1.clamp(Vector2i.ZERO, im.get_size())
	var sz: Vector2i = c1 - c0
	if sz.x <= 0 or sz.y <= 0:
		return null
	if _x + sz.x + PAD > W:
		_x = PAD
		_y += _row + PAD
		_row = 0
	if _y + sz.y + PAD > H or sz.x + PAD * 2 > W:
		full = true
		return null
	if img == null:
		img = Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.blit_rect(im, Rect2i(c0, sz), Vector2i(_x, _y))
	var e := [Vector2(_x, _y), Vector2(c0), Vector2(sz)]
	reg[k] = e
	_x += sz.x + PAD
	_row = maxi(_row, sz.y)
	_dirty = true
	return e


## 拷完一批后上传（画之前调用）
func commit() -> void:
	if not _dirty:
		return
	_dirty = false
	if tex == null:
		tex = ImageTexture.create_from_image(img)
	else:
		tex.update(img)
