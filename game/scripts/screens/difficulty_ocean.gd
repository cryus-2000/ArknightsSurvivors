extends RefCounted
## Survey-only scenery. Coordinates are a 282 × 160 pixel grid; no gameplay RNG.
const A = preload("res://scripts/art.gd")
var shadows: Dictionary = {}

func _init() -> void:
	for id in ["e_skimmer", "e_path", "e_mother"]:
		var tex: Texture2D = A.tex(id)
		if tex == null:
			continue
		if tex is CanvasTexture:
			tex = tex.diffuse_texture
		if tex == null:
			continue
		var im := tex.get_image()
		if im == null:
			continue
		if im.is_compressed():
			im.decompress()
		im.convert(Image.FORMAT_RGBA8)
		# Runtime assets can be strips: take their first square frame before cropping.
		im = im.get_region(Rect2i(0, 0, mini(im.get_width(), im.get_height()), im.get_height()))
		im = im.get_region(im.get_used_rect())
		for y in im.get_height():
			for x in im.get_width():
				var alpha := im.get_pixel(x, y).a
				im.set_pixel(x, y, Color(0.031, 0.059, 0.102, alpha))
		shadows[id] = ImageTexture.create_from_image(im)

## 海底六层轮廓与等高线是常量：第一次画时算好（10-25 帧率审计：原来每帧 6 × 283 + 282 次 exp / sin）
static var _edges: Array = []
static var _fills: Array = []
static var _contour := PackedVector2Array()

static func _build_terrain() -> void:
	for k in 6:
		var edge := PackedVector2Array()
		for x in 283:
			edge.append(Vector2(x, terrain(x, k)))
		var fill := edge.duplicate()
		fill.append(Vector2(282, 160))
		fill.append(Vector2(0, 160))
		_edges.append(edge)
		_fills.append(fill)
	for x in 282:
		_contour.append(Vector2(x, terrain(x)))

static func terrain(x: float, layer := 0) -> float:
	var u := x / 282.0
	return roundf(25.0 + 90.0 / (1.0 + exp(-(u - 0.46) * 10.0)) + sin(u * 19.0) * 4.0 + layer * 7.0)

static func rect(c: CanvasItem, x: float, y: float, w: float, h: float, col: Color) -> void:
	c.draw_rect(Rect2(roundf(x), roundf(y), w, h), col)

static func poly(c: CanvasItem, coords: Array, col: Color, offset := Vector2.ZERO) -> void:
	var pts := PackedVector2Array()
	for p in coords:
		pts.append((Vector2(p[0], p[1]) + offset).round())
	c.draw_colored_polygon(pts, col)

static func line(c: CanvasItem, coords: Array, col: Color) -> void:
	var pts := PackedVector2Array()
	for p in coords:
		pts.append(Vector2(p[0], p[1]).round())
	c.draw_polyline(pts, col, 1.0, false)

func shadow(c: CanvasItem, id: String, x: float, y: float, width: float) -> void:
	if shadows.has(id):
		var tex: Texture2D = shadows[id]
		c.draw_texture_rect(tex, Rect2(roundf(x), roundf(y), width, roundf(tex.get_height() * width / tex.get_width())), false)

static func fish(c: CanvasItem, x: float, y: float, length: float, dir: int, col: Color, tm: float, kind: int) -> void:
	var h := maxf(2.0, roundf(length * 0.65)) if kind == 1 else (1.0 if kind == 2 else maxf(1.0, roundf(length / 3.0)))
	poly(c, [[0, 0], [length * dir, -h], [(length + 3) * dir, 0], [length * dir, h]], col, Vector2(x, y))
	if kind == 1:
		line(c, [[x + (length - 1) * dir, y - h], [x + (length - 3) * dir, y - h - 2], [x + (length - 3) * dir, y + h + 2]], col)
	if kind == 2:
		rect(c, x + (length + 2) * dir, y, 3, 1, col)
	var wag := int(tm * 3.0 + x) % 2
	rect(c, x - 2, y - 1 - wag, 2, 3 + wag, col)

static func octopus(c: CanvasItem, x: float, y: float, tm: float) -> void:
	var col := Color("526578")
	rect(c, x + 3, y - 12, 6, 2, col)
	rect(c, x + 1, y - 10, 10, 7, col)
	rect(c, x + 3, y - 3, 6, 3, col)
	for j in 4:
		var sway := roundf(sin(tm * 0.7 + j))
		line(c, [[x + 3 + j, y - 1], [x - 3 + j * 4, y + 3], [x - 4 + j * 4 + sway, y + 5], [x - 6 + j * 5 + sway, y + 4]], col)

func draw(c: CanvasItem, tier: int, depth: float, tm: float, change: float, color: Color) -> void:
	rect(c, 0, 0, 282, 160, [Color("17303d"), Color("132532"), Color("101b2a")][tier])
	var surface := 5.0 - roundf(depth * 3.0)
	for x in 282:
		rect(c, x, surface + roundf(sin(x / 15.0 + tm * 0.45)), 1, 1, Color("6999a7"))
	var bw := roundf(56.0 - depth * 18.0)
	var shift := roundf(sin(tm * 0.12) * 3.0)
	poly(c, [[176 + shift, surface], [176 + bw + shift, surface], [144 + bw, 91], [144, 91]], [Color("203d49"), Color("19303e"), Color("142533")][tier])
	var wx := 181.0 + roundf(sin(tm * 0.07) * 12.0)
	var wy := 16.0 + roundf(sin(tm * 0.16))
	var tail := roundf(sin(tm * 0.35) * 2.0)
	poly(c, [[0,3],[3,0],[10,-2],[22,-2],[33,1],[43,5],[51,6],[56,1+tail],[63,-1+tail],[60,6+tail],[55,9],[59,13+tail],[52,12+tail],[47,9],[37,10],[25,13],[11,12],[3,9]], Color("294150"), Vector2(wx, wy))
	poly(c, [[24,10],[35,19],[32,11]], Color("294150"), Vector2(wx, wy))
	var drift := roundf(sin(tm * 0.16) * 7.0)
	if tier == 0:
		shadow(c, "e_skimmer", 167 + drift, 53, 23)
	elif tier == 1:
		shadow(c, "e_skimmer", 157 + drift, 51, 31)
		shadow(c, "e_mother", 226 - drift, 87, 25)
	else:
		shadow(c, "e_path", 197 + drift, 67, 66)
		shadow(c, "e_mother", 143 - drift, 70, 26)
		shadow(c, "e_skimmer", 218 - drift, 45, 26)
	for group in 3:
		for j in 8 - tier * 2:
			var x: float = [58, 135, 217][group] + (j % 4) * 12 + roundf(sin(tm * 0.17 + group) * 14.0)
			var y := 12.0 + group * 17 + floorf(j / 4.0) * 7 + roundf(sin(tm * 0.6 + j))
			if y < terrain(x) - 8:
				fish(c, x, y, 4 if group == 1 else 2, -1 if group == 1 else 1, [Color("608b98"), Color("4c7586"), Color("365868")][group], tm, group)
	for spec in [[138,39,6,1],[246,65,7,2],[187,80,5,0]]:
		var x: float = spec[0] + roundf(sin(tm * 0.12 + spec[0]) * 9.0)
		if spec[1] < terrain(x) - 6:
			fish(c, x, spec[1], spec[2], -1, Color("36566a"), tm, spec[3])
	if _edges.is_empty():
		_build_terrain()
	for k in 6:
		c.draw_colored_polygon(_fills[k], [Color("263744"),Color("22303c"),Color("1e2a35"),Color("1a2530"),Color("17212b"),Color("141d26")][k])
		c.draw_polyline(_edges[k], Color("496372") if k == 0 else Color("2d404e"), 1.0, false)
	for spec in [[19,17],[58,20],[110,14],[206,23],[267,21]]:
		var x: float = spec[0]
		var y := terrain(x)
		var sway := roundf(sin(tm * 0.5 + x) * 2.0)
		for k in range(-1,2):
			line(c, [[x+k*3,y],[x+k*3+1,y-6],[x+k*4+sway,y-spec[1]+5],[x+k*4+sway+1,y-spec[1]]], Color("365c65") if k else Color("48747a"))
	for x in [83,179,242]:
		var y := terrain(x)
		line(c, [[x,y],[x,y-11],[x-5,y-16],[x-5,y-20]], Color("596278"))
		line(c, [[x,y-5],[x+6,y-10],[x+6,y-17]], Color("68758a"))
	for j in 13:
		var x := 12 + j * 21
		rect(c, x, terrain(x)-2, 4, 2, Color("536476") if j % 3 == 0 else Color("364b5b"))
	octopus(c, 92 + roundf(sin(tm*0.09)*2), terrain(92)-4, tm)
	octopus(c, 223 + roundf(sin(tm*0.08+1)*2), terrain(223)-3, tm+2)
	# Stable particles drift horizontally; no RNG, flashing, or luminance pulse.
	for j in (tier + 1) * 6:
		var x := 100 + (j * 37 + int(floorf(tm * (2 + tier)))) % 175
		var y := 12 + (j * 13) % 63
		if y < terrain(x) - 5:
			rect(c, x, y, 1, 1, Color("395967"))
	for spec in [[194,27],[248,75]]:
		var x: float = spec[0]
		var y: float = spec[1] + roundf(sin(tm*0.8+x)*2)
		rect(c,x+2,y,8,2,Color("628c9d"))
		rect(c,x,y+2,12,5,Color("456c80"))
		for j in 3:
			line(c,[[x+2+j*4,y+7],[x+2+j*4,y+10],[x+3+j*4,y+12]],Color("3a6178"))
	c.draw_polyline(_contour, color, 1.0, false)
	var px := roundf(66.0 + depth * 84.0)
	var py := terrain(px)
	rect(c, 0, py, 282, 1, color)
	rect(c, px-5, py-5, 11, 11, Color("101924"))
	c.draw_rect(Rect2(px-5,py-5,11,11), color, false, 1)
	rect(c, px-1,py-1,3,3,color)
	if change < 1.0:
		rect(c, floorf(change*282),0,1,160,Color("527686"))
