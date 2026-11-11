extends RefCounted
## 罗德岛标志像素图（用户 11-05 明确允许这次使用原作 Logo；做法照 Codex 演示 docs/reference/prts-entry-1105/README.md）：
## 用户给的 240×240 原图运行时最近邻采样到 120×120，亮度 > 112 的点留下，> 168 冷白 #ECEEF0、其余次灰 #9297A0；
## 不要降到 64×64（用户嫌糊）。图鉴短版入场（gallery.gd）与桌面启动页（boot_views.draw_v4）共用。
## 11-12：贴图改在 240 原分辨率上做阈值（同网页加载页 docs/318 #3），排版格仍按 120 算（draw_bands 的 s、band 不变）。
## 原来 240 → 120 最近邻会把 4 像素高的「RHODES ISLAND」笔画采丢（显示成「RHODLS」）；min / 均值池化都会糊成块，故不降采样
const SRC := "res://art/ui/rhodes_logo_src.png"
const N := 120
const SN := 240   # 贴图实际分辨率（= 原图），1 个排版格 = 2 个贴图像素
const HI := Color(0.925, 0.933, 0.941)
const LO := Color(0.573, 0.592, 0.627)

static var _tex: ImageTexture = null


static func tex() -> ImageTexture:
	if _tex == null:
		var src: Texture2D = load(SRC)
		var img: Image = src.get_image() if src != null else null
		if img == null:
			return null
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		if img.get_width() != SN or img.get_height() != SN:
			img.resize(SN, SN, Image.INTERPOLATE_NEAREST)
		var out := Image.create(SN, SN, false, Image.FORMAT_RGBA8)
		for y in SN:
			for x in SN:
				var c: Color = img.get_pixel(x, y)
				var v: float = (c.r + c.g + c.b) / 3.0 * 255.0
				if v > 112.0:
					out.set_pixel(x, y, HI if v > 168.0 else LO)
		_tex = ImageTexture.create_from_image(out)
	return _tex


## 按横条画（每条 band 个标志像素行）；off.call(条号) 返回这一条的横向偏移（屏幕像素）；s = 每个标志像素画多大（最近邻，坐标取整）
static func draw_bands(ci: CanvasItem, pos: Vector2, s: float, band: int, off: Callable, mod: Color) -> void:
	var t: ImageTexture = tex()
	if t == null:
		return
	var b := 0
	while b < N:
		var h: int = mini(band, N - b)
		var dx: float = float(off.call(b / band))
		ci.draw_texture_rect_region(t, Rect2((pos + Vector2(dx, b * s)).round(), Vector2(N * s, h * s).round()), Rect2(0, b * 2, SN, h * 2), mod)
		b += band
