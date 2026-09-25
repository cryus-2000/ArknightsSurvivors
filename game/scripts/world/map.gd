## 地图（从 game.gd 拆出）：读 data/maps/<id>.json 主题，负责铺地、道具、大型景物、碰撞、氛围层与溟痕参数。
## 状态全在本模块；绘制通过 g（Game 节点）的 draw_* 进行。新地图 = 新增一份主题 JSON（+ 贴图）。
extends RefCounted

const A = preload("res://scripts/art.gd")

var g                              # Game (Node2D)
var id := ""
var theme := {}
var tex := {}                      # 主题用到的贴图
var sort_props: Array = []         # 2.5D：需要与人物前后遮挡的道具 [tex_name, pos, hash]
var big_cache := {}
var fg_tex: Array = []             # 前景虚化剪影
var snow: Array = []
var ambient := Color(0.16, 0.22, 0.32)
var tile_size := 32.0
var px := 2.0


func _init(game, theme_id := "deep_sea") -> void:
	g = game
	px = g.PX
	load_theme(theme_id)


static func list_ids() -> Array:
	var out: Array = []
	var d := DirAccess.open("res://data/maps")
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".json"):
			out.append(f.get_basename())
	return out


func load_theme(theme_id: String) -> void:
	id = theme_id
	var path := "res://data/maps/%s.json" % theme_id
	var f := FileAccess.open(path, FileAccess.READ)
	theme = JSON.parse_string(f.get_as_text()) if f != null else {}
	if theme.is_empty():
		push_error("map theme missing: " + path)
		theme = {"tiles": {"tex": "tiles", "size": 32, "variants": 4, "src_px": 16}, "props": [], "big_props": {"list": []}}
	tile_size = float(theme.tiles.get("size", 32))
	var amb: Array = theme.get("ambient", [0.16, 0.22, 0.32])
	ambient = Color(amb[0], amb[1], amb[2])
	tex.clear()
	_load(theme.tiles.tex)
	if theme.has("patches"):
		_load(theme.patches.tex)
	for pr in theme.get("props", []):
		_load(pr.tex)
	for n in theme.get("big_props", {}).get("list", []):
		_load(n)
	if theme.has("mire"):
		_load(theme.mire.tex)
	fg_tex.clear()
	for n in theme.get("foreground", {}).get("tex", []):
		_load(n)
		if tex[n] != null:
			fg_tex.append(_blur_silhouette(tex[n], _frames_of(n)))
	snow.clear()
	var sn: Dictionary = theme.get("snow", {})
	for i in int(sn.get("count", 0)):
		snow.append({"p": Vector2(g.rng.randf_range(-700, 700), g.rng.randf_range(-400, 400)), "v": g.rng.randf_range(4, 14), "s": g.rng.randf_range(0.0, TAU)})
	big_cache.clear()


func _load(n: String) -> void:
	if not tex.has(n):
		tex[n] = A.tex(n)


func _frames_of(n: String) -> int:
	for pr in theme.get("props", []):
		if pr.tex == n:
			return int(pr.get("frames", 1))
	return 1


func _prop_def(n: String) -> Dictionary:
	for pr in theme.get("props", []):
		if pr.tex == n:
			return pr
	return {}


# ------------------------------------------------------------------ 地面

## 地砖 + 地纹 + 小道具；需要 2.5D 排序的道具进 sort_props，其余直接画在地上
func draw_ground(vs: Vector2) -> void:
	var T := tile_size
	var tt: Dictionary = theme.tiles
	var tx: Texture2D = tex[tt.tex]
	var src: float = float(tt.get("src_px", 16))
	var nvar: int = int(tt.get("variants", 4))
	var ppos: Vector2 = g.view_center()   # 镜头看着的位置（图鉴演示里镜头不跟博士）
	var x0 := floori((ppos.x - vs.x / 2.0) / T) - 1
	var y0 := floori((ppos.y - vs.y / 2.0) / T) - 1
	var nx := int(vs.x / T) + 3
	var ny := int(vs.y / T) + 3
	var props: Array = []
	var defs: Array = theme.get("props", [])
	for cx in range(x0, x0 + nx):
		for cy in range(y0, y0 + ny):
			var h: int = abs(hash(Vector2i(cx, cy)))
			var v := h % nvar
			var p := Vector2(cx * T, cy * T)
			if tx != null:
				g.draw_texture_rect_region(tx, Rect2(p, Vector2(T, T)), Rect2(v * src, 0, src, src))
			var hh := h / 7
			for pr in defs:
				if hh % int(pr.every) == 0:
					var off: Array = pr.get("offset", [16, 20])
					props.append([pr.tex, p + Vector2(off[0], off[1]), h])
					break
	_draw_patches(vs)
	sort_props.clear()
	collect_big_props(vs)
	for pr in props:
		var d := _prop_def(pr[0])
		if d.get("sort", false):
			sort_props.append(pr)
		else:
			_spr(pr[0], 1, 0, pr[1], pr[2] % 2 == 0, Color.WHITE)


## 地形区域块：聚簇的同类区域，随机镜像
func _draw_patches(vs: Vector2) -> void:
	if not theme.has("patches"):
		return
	var pd: Dictionary = theme.patches
	var pt: Texture2D = tex.get(pd.tex)
	if pt == null:
		return
	var PATCH: float = float(pd.get("size", 256))
	var src: float = float(pd.get("src_px", 128))
	var kinds: int = int(pd.get("kinds", 4))
	var cl_n: float = float(pd.get("cluster", 3))
	var skip_mod: int = int(pd.get("skip_cluster_mod", 3))
	var density: int = int(pd.get("density", 78))
	var ppos: Vector2 = g.view_center()   # 镜头看着的位置（图鉴演示里镜头不跟博士）
	var x0 := floori((ppos.x - vs.x / 2.0) / PATCH) - 1
	var y0 := floori((ppos.y - vs.y / 2.0) / PATCH) - 1
	for cx in range(x0, x0 + int(vs.x / PATCH) + 3):
		for cy in range(y0, y0 + int(vs.y / PATCH) + 3):
			var cl: int = abs(hash(Vector2i(floori(cx / cl_n), floori(cy / cl_n)) + Vector2i(77, 13)))
			if cl % skip_mod == skip_mod - 1:
				continue
			var h: int = abs(hash(Vector2i(cx, cy) + Vector2i(5, 91)))
			if h % 100 > density:
				continue
			var kind: int = (cl / 3) % kinds
			var p := Vector2(cx * PATCH, cy * PATCH)
			var fx_: float = -1.0 if h % 2 == 0 else 1.0
			var fy_: float = -1.0 if (h / 2) % 2 == 0 else 1.0
			g.draw_set_transform(p + Vector2(PATCH, PATCH) / 2.0, 0.0, Vector2(fx_, fy_))
			g.draw_texture_rect_region(pt, Rect2(Vector2(-PATCH, -PATCH) / 2.0, Vector2(PATCH, PATCH)), Rect2(kind * src, 0, src, src))
			g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 2.5D 排序后绘制一个道具（由 game.gd 的深度排序循环调用）
func draw_sort_prop(pr: Array) -> void:
	var d := _prop_def(pr[0])
	var ptx: Texture2D = tex[pr[0]]
	var frames: int = int(d.get("frames", 1))
	var fade := 1.0
	var ppos: Vector2 = g.ppos
	var pw: float = ptx.get_width() / float(frames) * px * 0.5
	var ph: float = ptx.get_height() * px
	# 挡在人物身前的道具半透明
	if pr[1].y > ppos.y and absf(pr[1].x - ppos.x) < pw + 10.0 and pr[1].y - ppos.y < ph:
		fade = 0.4
	if frames > 1:
		_spr(pr[0], frames, int(g.t * float(d.get("fps", 2)) + pr[2]) % frames, pr[1], false, Color(1, 1, 1, fade))
	else:
		_spr(pr[0], 1, 0, pr[1], pr[2] % 2 == 0, Color(1, 1, 1, fade))


func _spr(name: String, frames: int, frame: int, pos: Vector2, flip: bool, col: Color) -> void:
	var tx: Texture2D = tex.get(name)
	if tx == null:
		return
	var fw: int = tx.get_width() / frames
	var fh: int = tx.get_height()
	var size := Vector2(fw, fh) * px
	var srcr := Rect2(fw * (frame % frames), 0, fw, fh)
	pos += g.draw_off
	if flip:
		g.draw_set_transform(pos.round(), 0.0, Vector2(-1, 1))
		g.draw_texture_rect_region(tx, Rect2(-size * Vector2(0.5, 1.0), size), srcr, col)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		g.draw_texture_rect_region(tx, Rect2((pos - size * Vector2(0.5, 1.0)).round(), size), srcr, col)


# ------------------------------------------------------------------ 大型景物与碰撞

func _big() -> Dictionary:
	return theme.get("big_props", {})


func _big_prop(cx: int, cy: int) -> Array:
	var key := Vector2i(cx, cy)
	if big_cache.has(key):
		return big_cache[key]
	var out: Array = []
	var bd := _big()
	var lst: Array = bd.get("list", [])
	if not lst.is_empty():
		var cell: float = float(bd.get("cell", 560))
		var h: int = abs(hash(key + Vector2i(313, 7)))
		if h % 100 <= int(bd.get("chance", 55)):
			var name: String = lst[(h / 100) % lst.size()]
			var tx: Texture2D = tex.get(name)
			if tx != null:
				var p := Vector2(cx * cell + float((h / 7) % 380) + 90.0, cy * cell + float((h / 3001) % 380) + 90.0)
				if p.length() > float(bd.get("clear_radius", 420)):
					var rxk: Dictionary = bd.get("base_rx", {"default": 0.3, "terrain": 0.36})
					var rx: float = tx.get_width() * px * float(rxk.get("terrain", 0.36) if name.begins_with("terrain") else rxk.get("default", 0.3))
					out = [name, p, h, rx, rx * float(bd.get("base_ry", 0.38))]
	big_cache[key] = out
	return out


func collect_big_props(vs: Vector2) -> void:
	var bd := _big()
	if bd.get("list", []).is_empty():
		return
	var cell: float = float(bd.get("cell", 560))
	var ppos: Vector2 = g.view_center()   # 镜头看着的位置（图鉴演示里镜头不跟博士）
	var x0 := floori((ppos.x - vs.x / 2.0 - 260.0) / cell)
	var y0 := floori((ppos.y - vs.y / 2.0 - 60.0) / cell)
	for cx in range(x0, x0 + int(vs.x / cell) + 3):
		for cy in range(y0, y0 + int(vs.y / cell) + 3):
			var bp := _big_prop(cx, cy)
			if not bp.is_empty():
				sort_props.append([bp[0], bp[1], bp[2]])


## 把圆形实体推出景物底座（椭圆）
func push_out(pos: Vector2, r: float) -> Vector2:
	var bd := _big()
	if bd.get("list", []).is_empty():
		return pos
	var cell: float = float(bd.get("cell", 560))
	var cx := floori(pos.x / cell)
	var cy := floori(pos.y / cell)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var bp := _big_prop(cx + dx, cy + dy)
			if bp.is_empty():
				continue
			var c: Vector2 = bp[1] + Vector2(0, -bp[4] * 0.6)
			var rx: float = bp[3] + r
			var ry: float = bp[4] + r * 0.6
			var d := pos - c
			var q := Vector2(d.x / rx, d.y / ry)
			var ql := q.length()
			if ql < 1.0:
				if ql < 0.001:
					q = Vector2.RIGHT
					ql = 1.0
				var qn := q / ql
				pos = c + Vector2(qn.x * rx, qn.y * ry)
	return pos


# ------------------------------------------------------------------ 氛围层

## 海中浮游颗粒：跟随视口循环
func update_snow(dt: float, vs: Vector2) -> void:
	var ppos: Vector2 = g.ppos
	for s in snow:
		s.p.y -= s.v * dt
		s.s += dt
		var rel: Vector2 = s.p - ppos
		if rel.y < -vs.y * 0.6:
			s.p.y += vs.y * 1.2
		elif rel.y > vs.y * 0.6:
			s.p.y -= vs.y * 1.2
		if rel.x < -vs.x * 0.6:
			s.p.x += vs.x * 1.2
		elif rel.x > vs.x * 0.6:
			s.p.x -= vs.x * 1.2


func draw_snow() -> void:
	var sc: Array = theme.get("snow", {}).get("color", [0.8, 0.9, 1.0])
	for s in snow:
		var c := Color(sc[0], sc[1], sc[2], 0.25 + 0.15 * sin(s.s * 2.0))
		g.draw_rect(Rect2((s.p + Vector2(sin(s.s) * 6.0, 0)).round(), Vector2(2, 2)), c)


## 2.5D 远景光束（画在加法层 ci 上）
func draw_god_rays(ci: CanvasItem, vs: Vector2, cp: Vector2) -> void:
	var gr: Dictionary = theme.get("god_rays", {})
	if gr.is_empty():
		return
	var span: float = float(gr.get("span", 1900))
	var col: Array = gr.get("color", [1.8, 2.4, 2.8])
	var a0: float = float(gr.get("alpha", 0.05))
	var t: float = g.t
	for k in int(gr.get("count", 6)):
		var base := fposmod(k * 331.0 - cp.x * 0.5 + t * 6.0, span) - span / 2.0
		var x := cp.x + base
		var w := 50.0 + 40.0 * float(k % 3)
		var top := cp.y - vs.y / 2.0 - 40.0
		var bot := cp.y + vs.y / 2.0 + 40.0
		var sl := 260.0
		var a := a0 + 0.03 * sin(t * 0.4 + k * 1.7)
		var c0 := Color(col[0], col[1], col[2], a)
		var c1 := Color(col[0], col[1], col[2], 0.0)
		ci.draw_polygon(PackedVector2Array([Vector2(x, top), Vector2(x + w, top), Vector2(x + w - sl, bot), Vector2(x - sl, bot)]),
			PackedColorArray([c0, c0, c1, c1]))


## 2.5D 前景：镜头前的虚化剪影，靠近画面中央时变淡
func draw_foreground(ci: CanvasItem, vs: Vector2, cp: Vector2) -> void:
	var fd: Dictionary = theme.get("foreground", {})
	if fd.is_empty() or fg_tex.is_empty():
		return
	var par: float = float(fd.get("parallax", 1.35))
	var cell: float = float(fd.get("cell", 520))
	var col: Array = fd.get("color", [0.10, 0.30, 0.34])
	var fc := cp * par
	var x0 := floori((fc.x - vs.x) / cell)
	var y0 := floori((fc.y - vs.y) / cell)
	for cx in range(x0, x0 + int(vs.x * 2.0 / cell) + 2):
		for cy in range(y0, y0 + int(vs.y * 2.0 / cell) + 2):
			var h: int = abs(hash(Vector2i(cx, cy) * 7 + Vector2i(3, 11)))
			if h % 5 > 1:
				continue
			var fp := Vector2(cx * cell + float(h % 300), cy * cell + float((h / 300) % 300))
			var wp := fp - fc + cp
			var sp := wp - cp
			var dc := Vector2(sp.x / (vs.x * 0.5), sp.y / (vs.y * 0.5)).length()
			var a := clampf((dc - 0.45) / 0.5, 0.0, 1.0) * 0.8
			if a <= 0.01:
				continue
			var tx: Texture2D = fg_tex[(0 if h % 3 != 0 else 1) % fg_tex.size()]
			var big := 0.8 + 0.25 * float(h % 3)
			var sway := sin(g.t * 0.7 + float(h % 10)) * 0.06
			var size := Vector2(tx.get_width(), tx.get_height()) * big
			ci.draw_set_transform(wp, sway, Vector2(-1.0 if h % 2 == 0 else 1.0, 1.0))
			ci.draw_texture_rect(tx, Rect2(Vector2(-size.x / 2.0, -size.y), size), false, Color(col[0], col[1], col[2], a))
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 把像素图变成柔和的剪影（取第一帧 -> 放大 -> 缩小再放大模拟高斯模糊）
static func _blur_silhouette(src: Texture2D, frames: int) -> Texture2D:
	var img := src.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var fw := img.get_width() / frames
	var fh := img.get_height()
	var pad := 4
	var out := Image.create(fw + pad * 2, fh + pad * 2, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	for y in fh:
		for x in fw:
			var a := img.get_pixel(x, y).a
			if a > 0.0:
				out.set_pixel(x + pad, y + pad, Color(1, 1, 1, a))
	var w := out.get_width()
	var h := out.get_height()
	out.resize(w * 8, h * 8, Image.INTERPOLATE_BILINEAR)
	out.resize(w * 3, h * 3, Image.INTERPOLATE_BILINEAR)
	out.resize(w * 8, h * 8, Image.INTERPOLATE_CUBIC)
	return ImageTexture.create_from_image(out)


# ------------------------------------------------------------------ 溟痕（地形危害）：参数来自主题，生成 / 结算仍在 game.gd

func mire_cfg() -> Dictionary:
	return theme.get("mire", {})


## 下一次自然生成溟痕的间隔（秒）
func mire_next_interval(t: float) -> float:
	var m := mire_cfg()
	var iv: Array = m.get("interval", [16, 24])
	return maxf(float(m.get("interval_min", 5)), g.rng.randf_range(float(iv[0]), float(iv[1])) - t / 30.0)


## 一块新的自然溟痕
func mire_new(pos: Vector2, t: float, endless: bool) -> Dictionary:
	var m := mire_cfg()
	var rr: Array = m.get("radius", [70, 110])
	var grow := 1.0 + t / 600.0
	return {"pos": pos, "r": 16.0, "maxr": g.rng.randf_range(float(rr[0]), float(rr[1])) * grow,
		"life": (float(m.get("life_base", 45)) + t / 20.0) if not endless else 9999.0, "seed": g.rng.randf() * 100.0}


func draw_mire(m: Dictionary) -> void:
	var a: float = clamp(m.life / 3.0, 0.0, 1.0)
	var t: float = g.t
	var mt: Texture2D = tex.get(mire_cfg().get("tex", "terrain_mire"))
	if mt != null:
		# 溟痕贴图（2 帧脉动）：按判定半径缩放，外圈画判定提示
		var fw := mt.get_width() / 2
		var sz := Vector2(m.r * 2.3, m.r * 2.3)
		g.draw_texture_rect_region(mt, Rect2(m.pos - sz / 2.0, sz), Rect2(fw * (int(t * 2.0 + m.seed) % 2), 0, fw, mt.get_height()), Color(1, 1, 1, a))
		g.draw_arc(m.pos, m.r, 0.0, TAU, 36, Color(0.7, 0.4, 1.2, 0.35 * a), 1.5)
		return
	for k in 7:
		var off: Vector2 = Vector2.from_angle(k * 0.9 + m.seed) * m.r * 0.45
		g.draw_circle(m.pos + off, m.r * (0.55 + 0.1 * sin(t + k)), Color(0.08, 0.03, 0.12, 0.55 * a))
	g.draw_circle(m.pos, m.r * 0.7, Color(0.12, 0.04, 0.16, 0.6 * a))
	for k in 10:
		var p: Vector2 = m.pos + Vector2.from_angle(k * 2.39 + m.seed) * m.r * (0.3 + 0.07 * k)
		var gl := 0.5 + 0.5 * sin(t * 2.0 + k)
		g.draw_rect(Rect2(p.round(), Vector2(2, 2)), Color(0.5, 0.9, 0.9, 0.6 * gl * a))
