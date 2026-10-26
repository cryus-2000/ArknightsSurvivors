## 地图（从 game.gd 拆出）：读 data/maps/<id>.json 主题，负责铺地、道具、大型景物、碰撞、氛围层与溟痕参数。
## 状态全在本模块；绘制通过 g（Game 节点）的 draw_* 进行。新地图 = 新增一份主题 JSON（+ 贴图）。
extends RefCounted

const A = preload("res://scripts/art.gd")
const Look = preload("res://scripts/render/look.gd")
const Dc = preload("res://scripts/render/declutter.gd")   # 后期降噪预设（render/declutter）
const Bal = preload("res://scripts/core/balance.gd")
const FD = preload("res://scripts/render/frame_dst.gd")   # 精灵取帧 + 落点（docs/101 B4 ②）

var g                              # Game (Node2D)
var id := ""
var theme := {}
var tex := {}                      # 主题用到的贴图
var sort_props: Array = []         # 2.5D：需要与人物前后遮挡的道具 [tex_name, pos, hash]
var big_cache := {}
var fg_tex: Array = []             # 前景虚化剪影
var fg_px: Array = []              # 前景像素剪影（光学观感下用，docs/130 A3）：原图第一帧的硬边剪影，整数倍放大、最近邻
var snow: Array = []
var ambient := Color(0.16, 0.22, 0.32)
var tile_size := 32.0
var px := 2.0
## 地面区块缓存（性能，协调人 9/30：地面每帧逐格 draw 约 2000 次 + 逐格 hash，约 2 毫秒）：
## 按 CHUNK 世界像素一块，把地砖 + 地形区域块（patches）在贴图原分辨率上合成一张 Image 缓存成贴图，每帧只画可见的几块；
## 道具列表也按块缓存，逐格结果与原来逐格画完全一致（同一 hash、同一变体 / 翻转 / 叠放顺序）
const CHUNK := 512.0
var ground_cache := {}             # Vector2i -> [Texture2D, props]
var _tile_img: Image = null
var _patch_img: Image = null


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
	ground_cache.clear()
	_tile_img = null
	_patch_img = null
	var amb: Array = theme.get("ambient", [0.16, 0.22, 0.32])
	# render/ambient_mult：灯火圈外的环境光（CanvasModulate）整体倍率，角色受光同一份（Look 读 map.ambient）；1 = 主题原值（用户 10-21 定亮度 B：缺省 1.3，见 balance render/_bright_b_doc）
	var am: float = Bal.v("render/ambient_mult", 1.0)
	ambient = Color(amb[0] * am, amb[1] * am, amb[2] * am)
	# docs/139 试验旋钮 render/ambient_desat（缺省 0）：环境光往同亮度的灰拉（0–1），暗部不再一片高饱和青蓝
	var ad: float = Bal.v("render/ambient_desat", 0.0)
	if ad > 0.0:
		var lu: float = ambient.r * 0.2126 + ambient.g * 0.7152 + ambient.b * 0.0722
		ambient = ambient.lerp(Color(lu, lu, lu), clampf(ad, 0.0, 1.0))
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
	_mire_v2_load()
	fg_tex.clear()
	fg_px.clear()
	for n in theme.get("foreground", {}).get("tex", []):
		_load(n)
		if tex[n] != null:
			fg_tex.append(_blur_silhouette(tex[n], _frames_of(n)))
			fg_px.append(_px_silhouette(tex[n], _frames_of(n)))
	snow.clear()
	var sn: Dictionary = theme.get("snow", {})
	for i in int(sn.get("count", 0)):
		snow.append({"p": Vector2(g.rng.randf_range(-700, 700), g.rng.randf_range(-400, 400)), "v": g.rng.randf_range(4, 14), "s": g.rng.randf_range(0.0, TAU)})
	big_cache.clear()
	_po_reach = -1.0


func _load(n: String) -> void:
	if not tex.has(n):
		# docs/139 §6.6 试验旋钮 render/env_sat / render/env_bright（缺省 1 / 1）：只给地图贴图（地砖 / 斑块 / 道具 / 大道具）降饱和，干员 / 怪物 / 特效颜色不变
		tex[n] = A.desat_of(A.tex(n), Bal.v("render/env_sat", 1.0), Bal.v("render/env_bright", 1.0))


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
	var ppos: Vector2 = g.cam_center()   # 镜头看着的位置（图鉴演示里镜头不跟博士；镜头一瞥时跟着镜头铺满）
	var x0 := floori((ppos.x - vs.x / 2.0) / T) - 1
	var y0 := floori((ppos.y - vs.y / 2.0) / T) - 1
	var nx := int(vs.x / T) + 3
	var ny := int(vs.y / T) + 3
	var tpc: int = int(CHUNK / T)   # 每块的格数
	var props: Array = []
	for kx in range(floori(float(x0) / tpc), floori(float(x0 + nx - 1) / tpc) + 1):
		for ky in range(floori(float(y0) / tpc), floori(float(y0 + ny - 1) / tpc) + 1):
			var ch: Array = _ground_chunk(Vector2i(kx, ky))
			if ch[0] != null:
				g.draw_texture_rect(ch[0], Rect2(Vector2(kx, ky) * CHUNK, Vector2(CHUNK, CHUNK)), false)
			for pr in ch[1]:
				# 只收原来逐格范围内的道具（和原来画出的集合一样）
				if pr[3] >= x0 and pr[3] < x0 + nx and pr[4] >= y0 and pr[4] < y0 + ny:
					props.append(pr)
	# 地形区域块已合成进区块贴图；区块贴图缺失（没有地砖图）时退回逐块画
	if tex.get(theme.tiles.tex) == null:
		_draw_patches(vs)
	if g.optical_on and Bal.v("render/optical_ground", 1.0) > 0.0:
		_draw_ground_noise(vs, ppos)
	sort_props.clear()
	collect_big_props(vs)
	# 平铺在地上的小道具互不遮挡：按贴图（再按翻转）排序后连续画，同贴图才能合批（性能 9/30：原来按格子顺序画，贴图几乎每次都换）
	props.sort_custom(func(x, y): return x[0] < y[0] if x[0] != y[0] else (x[2] % 2) < (y[2] % 2))
	for pr in props:
		var d := _prop_def(pr[0])
		if d.get("sort", false):
			sort_props.append([pr[0], pr[1], pr[2]])
		else:
			_spr(pr[0], 1, 0, pr[1], pr[2] % 2 == 0, Color.WHITE)


## 光学观感原型 ⑨ 地面程序噪点材质：可平铺的值噪声（两层八度）按 4×4 Bayer 抖动量化到 4 档深海色（围绕地面原平均色），
## 每 1 美术像素 = 2 世界像素，盖在地砖区块上（半透明，地形块与道具的形状仍看得见）。开局后第一次用到时生成一次
const NOISE_N := 128
var _noise_tex: ImageTexture = null

func _ground_noise() -> ImageTexture:
	if _noise_tex != null:
		return _noise_tex
	var m: Color = ground_mean()
	# 4 档围绕地面原平均色上下浮动（10-23 用户：画面不要变暗），平均下来和原地面一样亮；暗处由光照本身压
	var pal := [m.darkened(0.3), m.darkened(0.1), m.lightened(0.08), m.lightened(0.2).lerp(Color(0.3, 0.6, 0.65), 0.2)]
	var bayer := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
	var img := Image.create(NOISE_N, NOISE_N, false, Image.FORMAT_RGBA8)
	var lat := {}
	for oc in [8, 32]:
		for y in range(0, NOISE_N, oc):
			for x in range(0, NOISE_N, oc):
				lat[Vector3i(x, y, oc)] = float(abs(hash(Vector3i(x, y, oc * 7))) % 1000) / 1000.0   # 固定散列，不碰随机数
	for y in NOISE_N:
		for x in NOISE_N:
			var v := 0.0
			var wsum := 0.0
			for oc in [8, 32]:
				var x0: int = (x / oc) * oc
				var y0: int = (y / oc) * oc
				var x1: int = (x0 + oc) % NOISE_N
				var y1: int = (y0 + oc) % NOISE_N
				var fx: float = smoothstep(0.0, 1.0, float(x - x0) / oc)
				var fy: float = smoothstep(0.0, 1.0, float(y - y0) / oc)
				var a: float = lerpf(lat[Vector3i(x0, y0, oc)], lat[Vector3i(x1, y0, oc)], fx)
				var b: float = lerpf(lat[Vector3i(x0, y1, oc)], lat[Vector3i(x1, y1, oc)], fx)
				var w: float = 1.0 if oc == 32 else 0.5
				v += lerpf(a, b, fy) * w
				wsum += w
			v /= wsum
			var th: float = (bayer[(y % 4) * 4 + (x % 4)] + 0.5) / 16.0
			var lv: int = clampi(int(v * 3.0 + th - 0.5), 0, 3)
			var c: Color = pal[lv]
			img.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
	_noise_tex = ImageTexture.create_from_image(img)
	return _noise_tex


func _draw_ground_noise(vs: Vector2, cp: Vector2) -> void:
	var nt := _ground_noise()
	var S: float = NOISE_N * px
	var a: float = Bal.v("render/optical_ground", 1.0) * 0.55
	var x0 := floori((cp.x - vs.x / 2.0) / S) - 1
	var y0 := floori((cp.y - vs.y / 2.0) / S) - 1
	for ix in range(x0, x0 + int(vs.x / S) + 3):
		for iy in range(y0, y0 + int(vs.y / S) + 3):
			g.draw_texture_rect(nt, Rect2(Vector2(ix, iy) * S, Vector2(S, S)), false, Color(1, 1, 1, a))


## 地面的平均色（后期降噪 render/declutter ground_veil 用：拥挤时在地面上盖一层同色薄纱，压地砖 / 小道具的纹理对比，不改明暗）。
## 取第一块地面缓存贴图缩到 1×1；没有贴图时用深灰蓝
var _gmean := Color(-1, 0, 0)

func ground_mean() -> Color:
	if _gmean.r >= 0.0:
		return _gmean
	_gmean = Color(0.14, 0.16, 0.19)
	for k in ground_cache:
		var tx = ground_cache[k][0]
		if tx is Texture2D:
			var img: Image = tx.get_image()
			if img != null:
				if img.is_compressed():
					img.decompress()
				img.resize(1, 1, Image.INTERPOLATE_BILINEAR)
				_gmean = img.get_pixel(0, 0)
				_gmean.a = 1.0
		break
	return _gmean


## 区块缓存满了：丢掉离 k 最远的一半（原来整表清空，下一帧可见的几块要一起重新合成，卡一下）
func _ground_evict(k: Vector2i, cap: int) -> void:
	var keys: Array = ground_cache.keys()
	keys.sort_custom(func(a, b): return (a - k).length_squared() > (b - k).length_squared())
	for i in maxi(1, keys.size() - cap / 2):
		ground_cache.erase(keys[i])


## 生成 / 取一块地面缓存：[贴图, 道具列表 [tex, pos, hash, cx, cy]]
func _ground_chunk(k: Vector2i) -> Array:
	if ground_cache.has(k):
		return ground_cache[k]
	var cap: int = 20 if Cfg.mobile_web() else 96   # 手机网页少留（docs/50 §30：走得越远区块越多，一块按地砖原分辨率合成，九分钟能攒几十到上百 MB）
	if ground_cache.size() >= cap:
		_ground_evict(k, cap)
	var T := tile_size
	var tt: Dictionary = theme.tiles
	var src: int = int(tt.get("src_px", 16))
	var nvar: int = int(tt.get("variants", 4))
	var tpc: int = int(CHUNK / T)
	var sc: float = float(src) / T            # 世界像素 → 贴图像素
	var defs: Array = theme.get("props", [])
	var props: Array = []
	var img: Image = null
	var tx: Texture2D = tex.get(tt.tex)
	if tx != null:
		if _tile_img == null:
			_tile_img = _rgba(tx)
		img = Image.create(int(CHUNK * sc), int(CHUNK * sc), false, Image.FORMAT_RGBA8)
	for ix in tpc:
		for iy in tpc:
			var cx: int = k.x * tpc + ix
			var cy: int = k.y * tpc + iy
			var h: int = abs(hash(Vector2i(cx, cy)))
			var v := h % nvar
			if img != null:
				img.blit_rect(_tile_img, Rect2i(v * src, 0, src, src), Vector2i(ix * src, iy * src))
			var hh := h / 7
			for pr in defs:
				if hh % int(pr.every) == 0:
					var off: Array = pr.get("offset", [16, 20])
					props.append([pr.tex, Vector2(cx * T, cy * T) + Vector2(off[0], off[1]), h, cx, cy])
					break
	if img != null and theme.has("patches"):
		_bake_patches(img, k, sc)
	var t2: Texture2D = ImageTexture.create_from_image(img) if img != null else null
	ground_cache[k] = [t2, props]
	return ground_cache[k]


## 地形区域块合成进区块：规则同 _draw_patches（聚簇、跳簇、密度、种类、随机镜像），在贴图分辨率上 alpha 叠放
func _bake_patches(img: Image, k: Vector2i, sc: float) -> void:
	var pd: Dictionary = theme.patches
	var pt: Texture2D = tex.get(pd.tex)
	if pt == null:
		return
	if _patch_img == null:
		_patch_img = _rgba(pt)
	var PATCH: float = float(pd.get("size", 256))
	var src: int = int(pd.get("src_px", 128))
	var kinds: int = int(pd.get("kinds", 4))
	var cl_n: float = float(pd.get("cluster", 3))
	var skip_mod: int = int(pd.get("skip_cluster_mod", 3))
	var density: int = int(pd.get("density", 78))
	var ppc: int = int(CHUNK / PATCH)
	for ix in ppc:
		for iy in ppc:
			var cx: int = k.x * ppc + ix
			var cy: int = k.y * ppc + iy
			var cl: int = abs(hash(Vector2i(floori(cx / cl_n), floori(cy / cl_n)) + Vector2i(77, 13)))
			if cl % skip_mod == skip_mod - 1:
				continue
			var h: int = abs(hash(Vector2i(cx, cy) + Vector2i(5, 91)))
			if h % 100 > density:
				continue
			var kind: int = (cl / 3) % kinds
			var reg: Image = _patch_img.get_region(Rect2i(kind * src, 0, src, src))
			if h % 2 == 0:
				reg.flip_x()
			if (h / 2) % 2 == 0:
				reg.flip_y()
			img.blend_rect(reg, Rect2i(0, 0, src, src), Vector2i(int(ix * PATCH * sc), int(iy * PATCH * sc)))


func _rgba(t: Texture2D) -> Image:
	var im: Image = t.get_image()
	if im.is_compressed():
		im.decompress()
	if im.get_format() != Image.FORMAT_RGBA8:
		im.convert(Image.FORMAT_RGBA8)
	return im


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
	var ppos: Vector2 = g.cam_center()   # 镜头看着的位置（图鉴演示里镜头不跟博士；镜头一瞥时跟着镜头铺满）
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
	FD.blit(g, tx, FD.src(fw, fh, frames, frame), pos + g.draw_off, Vector2(fw, fh) * px, Vector2(0.5, 1.0), flip, col)   # 脚底锚点


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
	var ppos: Vector2 = g.cam_center()   # 镜头看着的位置（图鉴演示里镜头不跟博士；镜头一瞥时跟着镜头铺满）
	var x0 := floori((ppos.x - vs.x / 2.0 - 260.0) / cell)
	var y0 := floori((ppos.y - vs.y / 2.0 - 60.0) / cell)
	for cx in range(x0, x0 + int(vs.x / cell) + 3):
		for cy in range(y0, y0 + int(vs.y / cell) + 3):
			var bp := _big_prop(cx, cy)
			if not bp.is_empty():
				sort_props.append([bp[0], bp[1], bp[2]])


## push_out 的粗筛（docs/50 §9.11 ③）：景物中心落在本格 [90, 469] 像素内（_big_prop），最大底座半宽 _po_rx；
## 某个邻格的景物再大也够不着当前位置，就不查这一格（不建 Vector2i、不查字典）。结果与逐格全查相同
var _po_reach := -1.0       # < 0 = 未算；开局 / 换主题时重算
var _po_cell := 560.0
var _po_rx := 0.0           # 底座椭圆最大横半径
var _po_ry := 0.0           # 最大纵半径
## 地形阻挡（10-13 用户批准）：直线子弹撞景物底座即消失、冲刺撞底座即停、直线弹干员优先选视线内目标。旋钮 balance terrain/*
var tb_bul := true          # 我方直线弹
var tb_ebul := true         # 敌方直线弹（非 Boss）
var tb_boss := false        # Boss 直线弹（缺省不挡：Boss 弹幕按预警设计）
var tb_aim := true          # 自动瞄准优先视线内目标
var tb_dash := true         # 冲刺撞停
var tb_dash_px := 3.0       # 冲刺这一帧被推出超过此像素算撞上
var tb_log := {"bul": 0, "ebul": 0, "dash": 0}   # 遥测（只记录）：本局挡下的我方 / 敌方直线弹、撞停的冲刺次数（telemetry.record 的 terrain）


func _po_setup() -> void:
	var bd := _big()
	var lst: Array = bd.get("list", [])
	_po_cell = float(bd.get("cell", 560))
	var rxk: Dictionary = bd.get("base_rx", {"default": 0.3, "terrain": 0.36})
	_po_rx = 0.0
	for name in lst:
		var tx: Texture2D = tex.get(name)
		if tx != null:
			_po_rx = maxf(_po_rx, tx.get_width() * px * float(rxk.get("terrain", 0.36) if String(name).begins_with("terrain") else rxk.get("default", 0.3)))
	_po_ry = _po_rx * float(bd.get("base_ry", 0.38))
	_po_reach = 0.0 if lst.is_empty() or _po_rx <= 0.0 else 1.0
	# 地形阻挡旋钮（balance terrain/*，开局 / 换主题时读一次；逐弹逐帧不查 Bal）
	tb_bul = Bal.v("terrain/block_bullets", 1.0) > 0.0
	tb_ebul = Bal.v("terrain/block_enemy_bullets", 1.0) > 0.0
	tb_boss = Bal.v("terrain/block_boss_bullets", 0.0) > 0.0
	tb_aim = Bal.v("terrain/aim_los", 1.0) > 0.0
	tb_dash = Bal.v("terrain/dash_stop", 1.0) > 0.0
	tb_dash_px = Bal.v("terrain/dash_stop_px", 3.0)


## 原生核心（docs/101 §4.7）要的景物推出参数：[有没有会挡的景物, 格子边长, 最大半轴 rx, ry]
func push_params() -> Array:
	if _po_reach < 0.0:
		_po_setup()
	return [_po_reach != 0.0, _po_cell, _po_rx, _po_ry]


## 原生核心要的景物底座表：格子范围 [x0..x1] × [y0..y1] 里有景物的格。
## 返回 [格子坐标 PackedInt32Array（cx, cy 交替）, 中心 PackedVector2Array（= bp[1] + Vector2(0, -bp[4] * 0.6)，与 push_out 同一算式）, 半轴 PackedFloat64Array（rx, ry 交替）]
func push_table(x0: int, x1: int, y0: int, y1: int) -> Array:
	var cells := PackedInt32Array()
	var cs := PackedVector2Array()
	var rs := PackedFloat64Array()
	for cx in range(x0, x1 + 1):
		for cy in range(y0, y1 + 1):
			var bp := _big_prop(cx, cy)
			if bp.is_empty():
				continue
			cells.append(cx)
			cells.append(cy)
			cs.append(bp[1] + Vector2(0, -bp[4] * 0.6))
			rs.append(bp[3])
			rs.append(bp[4])
	return [cells, cs, rs]


## 把圆形实体推出景物底座（椭圆）
func push_out(pos: Vector2, r: float) -> Vector2:
	if _po_reach < 0.0:
		_po_setup()
	if _po_reach == 0.0:
		return pos
	var cell: float = _po_cell
	var cx := floori(pos.x / cell)
	var cy := floori(pos.y / cell)
	var mx: float = _po_rx + r + 1.0
	var my: float = _po_ry + r * 0.6 + _po_ry * 0.6 + 1.0
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			# 邻格景物中心 x ∈ [(cx+dx)·cell + 90, + 469]，y 再上移至多 0.6·ry；推挤会改 pos，所以每格用当前 pos 判
			if dx == -1 and pos.x - ((cx - 1) * cell + 469.0) >= mx:
				continue
			if dx == 1 and ((cx + 1) * cell + 90.0) - pos.x >= mx:
				continue
			if dy == -1 and pos.y - ((cy - 1) * cell + 469.0) >= my:
				continue
			if dy == 1 and ((cy + 1) * cell + 90.0) - pos.y >= my:
				continue
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


## 本局有没有会挡东西的景物（无景物主题 = false）。量帧开关 g.perf_alt 不再关阻挡：测量工具只许影响绘制，不改玩法（docs/101 S4，10-15）
func blocks() -> bool:
	if _po_reach < 0.0:
		_po_setup()
	return _po_reach > 0.0


## 邻格粗筛：景物中心 x ∈ [cx·cell + 90, + 469]，底座中心再上移 0.6·ry；[x0, x1] × [y0, y1] 够得着的格子范围
func _cells(x0: float, y0: float, x1: float, y1: float) -> Rect2i:
	var cell: float = _po_cell
	var ax := ceili((x0 - _po_rx - 469.0) / cell)
	var bx := floori((x1 + _po_rx - 90.0) / cell)
	var ay := ceili((y0 - _po_ry - 469.0) / cell)
	var by := floori((y1 + _po_ry * 1.6 - 90.0) / cell)
	return Rect2i(ax, ay, bx - ax, by - ay)


## 点是否在任一景物底座椭圆内（与 push_out 同一椭圆，r = 0）
func point_blocked(p: Vector2) -> bool:
	if not blocks():
		return false
	var rc := _cells(p.x, p.y, p.x, p.y)
	for cx in range(rc.position.x, rc.end.x + 1):
		for cy in range(rc.position.y, rc.end.y + 1):
			var bp := _big_prop(cx, cy)
			if bp.is_empty():
				continue
			var d: Vector2 = p - (bp[1] + Vector2(0, -bp[4] * 0.6))
			var qx: float = d.x / bp[3]
			var qy: float = d.y / bp[4]
			if qx * qx + qy * qy < 1.0:
				return true
	return false


## 线段 a→b 是否穿过任一景物底座椭圆（自动瞄准的视线判定）
func segment_blocked(a: Vector2, b: Vector2) -> bool:
	if not blocks():
		return false
	var rc := _cells(minf(a.x, b.x), minf(a.y, b.y), maxf(a.x, b.x), maxf(a.y, b.y))
	for cx in range(rc.position.x, rc.end.x + 1):
		for cy in range(rc.position.y, rc.end.y + 1):
			var bp := _big_prop(cx, cy)
			if bp.is_empty():
				continue
			# 缩放到单位圆：椭圆 → 圆，线段到圆心最近距离 < 1 即穿过
			var c: Vector2 = bp[1] + Vector2(0, -bp[4] * 0.6)
			var sc := Vector2(1.0 / bp[3], 1.0 / bp[4])
			var pa: Vector2 = (a - c) * sc
			var ab: Vector2 = (b - a) * sc
			var l2: float = ab.length_squared()
			var k: float = 0.0 if l2 < 0.0001 else clampf(-pa.dot(ab) / l2, 0.0, 1.0)
			if (pa + ab * k).length_squared() < 1.0:
				return true
	return false


## 直线弹撞岩：p = 弹体的地面判定点。只在「先在底座外、后进底座」时算撞上
##（出手点落在底座里的，例如站在岩石正下方抬手出手，先放行到它飞出底座）。撞上时播碎屑
func bullet_blocked(b: Dictionary, p: Vector2, enemy := false) -> bool:
	if not point_blocked(p):
		if not b.has("tbo"):
			b["tbo"] = true
		return false
	if not b.has("tbo"):
		return false
	g.vfx.rock_chip(p, b.get("vel", b.get("v", Vector2.ZERO)))
	tb_log["ebul" if enemy else "bul"] += 1
	return true


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
	# 后期降噪（render/declutter snow_k，缺省 1 = 不变）：拥挤时浮游颗粒变淡；--clutterdbg=noamb 量测时不显示
	var sk: float = 0.0 if g.world._dbg_amb else Dc.at("snow_k", g.world.dcrowd)
	for s in snow:
		var c := Color(sc[0], sc[1], sc[2], (0.25 + 0.15 * sin(s.s * 2.0)) * sk)
		g.draw_rect(Rect2((s.p + Vector2(sin(s.s) * 6.0, 0)).round(), Vector2(2, 2)), c)


## 2.5D 远景光束（画在加法层 ci 上）
func draw_god_rays(ci: CanvasItem, vs: Vector2, cp: Vector2) -> void:
	var gr: Dictionary = theme.get("god_rays", {})
	if gr.is_empty():
		return
	var span: float = float(gr.get("span", 1900))
	var col: Array = gr.get("color", [1.8, 2.4, 2.8])
	var a0: float = float(gr.get("alpha", 0.05))
	var gk: float = Look.p("god") * Dc.at("god_k", g.world.dcrowd)   # 观感预设 render/look ≥ 3 减淡远景光束（加法层叠出的乳白雾感）；后期降噪 render/declutter god_k
	if g.optical_on and g.optical.fx1:
		return   # 光学观感 · 防油腻 ④（10-23）：环境雾只压暗不加白，加法远景光束（乳白雾）不画
	var t: float = g.t
	for k in int(gr.get("count", 6)):
		var base := fposmod(k * 331.0 - cp.x * 0.5 + t * 6.0, span) - span / 2.0
		var x := cp.x + base
		var w := 50.0 + 40.0 * float(k % 3)
		var top := cp.y - vs.y / 2.0 - 40.0
		var bot := cp.y + vs.y / 2.0 + 40.0
		var sl := 260.0
		var a := (a0 + 0.03 * sin(t * 0.4 + k * 1.7)) * gk
		var c0 := Color(col[0], col[1], col[2], a)
		var c1 := Color(col[0], col[1], col[2], 0.0)
		ci.draw_polygon(PackedVector2Array([Vector2(x, top), Vector2(x + w, top), Vector2(x + w - sl, bot), Vector2(x - sl, bot)]),
			PackedColorArray([c0, c0, c1, c1]))


## 2.5D 前景：镜头前的虚化剪影，靠近画面中央时变淡
func draw_foreground(ci: CanvasItem, vs: Vector2, cp: Vector2) -> void:
	var fd: Dictionary = theme.get("foreground", {})
	if fd.is_empty() or fg_tex.is_empty():
		return
	# 光学观感下的前景（render/optical_fg_px，docs/130 A3）：1 = 像素剪影、0 = 不画（缺省，用户 10-24「看不出来区别」）、-1 = 原虚化剪影；光学关（低档）照旧虚化
	var fg_mode: float = Bal.v("render/optical_fg_px", 0.0)
	if g.optical_on and fg_mode == 0.0:
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
			var big := 0.8 + 0.25 * float(h % 3)
			var sway := sin(g.t * 0.7 + float(h % 10)) * 0.06
			if g.optical_on and not fg_px.is_empty() and fg_mode > 0.0:
				# 像素风（docs/130 A3，用户 10-24）：硬边剪影、整数倍放大（每个原图像素 = PX_FG 档里最近的偶数世界像素，落在低分辨率层 2 px 格上），
				# 不旋转（转了像素会歪），摆动改成按 2 px 步进的横向平移；大小档与虚化版同一套（约 0.8 / 1.05 / 1.3 倍）
				var pt: Texture2D = fg_px[(0 if h % 3 != 0 else 1) % fg_px.size()]
				var k: float = 2.0 * roundf(4.0 * big)
				var ps := Vector2(pt.get_width(), pt.get_height()) * k
				var sx: float = 2.0 * roundf(sway * ps.y * 0.25)
				var o := (wp + Vector2(sx - ps.x / 2.0, -ps.y)).snapped(Vector2(2.0, 2.0))
				if h % 2 == 0:
					ci.draw_set_transform(o + Vector2(ps.x, 0.0), 0.0, Vector2(-1.0, 1.0))
					ci.draw_texture_rect(pt, Rect2(Vector2.ZERO, ps), false, Color(col[0], col[1], col[2], a))
					ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				else:
					ci.draw_texture_rect(pt, Rect2(o, ps), false, Color(col[0], col[1], col[2], a))
				continue
			var tx: Texture2D = fg_tex[(0 if h % 3 != 0 else 1) % fg_tex.size()]
			var size := Vector2(tx.get_width(), tx.get_height()) * big
			ci.draw_set_transform(wp, sway, Vector2(-1.0 if h % 2 == 0 else 1.0, 1.0))
			ci.draw_texture_rect(tx, Rect2(Vector2(-size.x / 2.0, -size.y), size), false, Color(col[0], col[1], col[2], a))
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 像素剪影（光学观感用）：取第一帧，alpha > 0.5 的像素填白、其余透明，原尺寸（放大交给绘制时整数倍 + 最近邻）
static func _px_silhouette(src: Texture2D, frames: int) -> Texture2D:
	var img := src.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var fw := img.get_width() / frames
	var fh := img.get_height()
	var out := Image.create(fw, fh, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	for y in fh:
		for x in fw:
			if img.get_pixel(x, y).a > 0.5:
				out.set_pixel(x, y, Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(out)


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
	var d := {"pos": pos, "r": 16.0, "maxr": g.rng.randf_range(float(rr[0]), float(rr[1])) * grow,
		"life": (float(m.get("life_base", 45)) + t / 20.0) if not endless else 9999.0, "seed": g.rng.randf() * 100.0}
	# 点燃的引航灯标周围禁刷期内不生成自然溟痕（run/beacon.gd）：随机数照常消耗，只把寿命置 0，下一帧被滤掉
	if g.beacon_sys.blocks(pos):
		d.life = 0.0
	return d


## ---- 溟痕 v2（Codex art/incoming/world_spec_1024，用户 10-24 验收；tools/install_world_spec.py 装成两张图集）：
## 底图 mire_tile_ab（A / B 变体 × 2 帧，各 64×64 美术像素）按全局美术像素格 1:1 平铺，不再按 r × 2.3 拉伸；
## 判定圆按 MIRE_CELL（16 美术像素 = 32 世界单位）一格栅格化（格心在圆内 = 内区），圈外紧邻的格按邻接画 12 片围边
## （mire_edge_atlas：边片遮罩 × 同相位底图，任意格位与内区脉络连续）；每 64 格块按坐标哈希取 A / B。
## _emit 层排进光学发光层（g.glow_tex_next，光学观感开时）。纯画面；栅格按半径 4 单位一档缓存在溟痕字典的 _mc 里
const MIRE_CELL := 16
var mire_v2 := false
var _mire_ab: Texture2D
var _mire_ab_e: Texture2D
var _mire_edge: Texture2D
var _mire_edge_e: Texture2D


func _mire_v2_load() -> void:
	mire_v2 = A.has_override("mire_tile_ab") and A.has_override("mire_edge_atlas")
	if mire_v2:
		_mire_ab = A.tex("mire_tile_ab")
		_mire_edge = A.tex("mire_edge_atlas")
		_mire_ab_e = A.tex("mire_tile_ab_emit") if A.has_override("mire_tile_ab_emit") else null
		_mire_edge_e = A.tex("mire_edge_atlas_emit") if A.has_override("mire_edge_atlas_emit") else null


## 一组内区格（Dictionary Vector2i → true）补洞后求围边：[内区格 Array, 围边 Array[Vector3i(格 x, 格 y, 片号)]]。
## 补洞：圈外格四邻有对边一对或三面以上在内区的并进内区（否则没有对应边片）。片号同 HANDOFF：0 N 1 E 2 S 3 W、4–7 外角 NW NE SE SW、8–11 内角 NW NE SE SW
func mire_cells(ins: Dictionary) -> Array:
	for _pass in 3:
		var add: Array = []
		for c in ins:
			for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
				var q: Vector2i = c + d
				if ins.has(q):
					continue
				var n: bool = ins.has(q + Vector2i(0, -1))
				var s: bool = ins.has(q + Vector2i(0, 1))
				var e: bool = ins.has(q + Vector2i(1, 0))
				var w: bool = ins.has(q + Vector2i(-1, 0))
				if (n and s) or (e and w) or int(n) + int(s) + int(e) + int(w) >= 3:
					add.append(q)
		if add.is_empty():
			break
		for q in add:
			ins[q] = true
	var border: Array = []
	var seen := {}
	for c in ins:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var q: Vector2i = c + Vector2i(dx, dy)
				if ins.has(q) or seen.has(q):
					continue
				seen[q] = true
				var n: bool = ins.has(q + Vector2i(0, -1))
				var s: bool = ins.has(q + Vector2i(0, 1))
				var e: bool = ins.has(q + Vector2i(1, 0))
				var w: bool = ins.has(q + Vector2i(-1, 0))
				var t := -1
				if s and e:
					t = 8
				elif s and w:
					t = 9
				elif n and w:
					t = 10
				elif n and e:
					t = 11
				elif s:
					t = 0
				elif w:
					t = 1
				elif n:
					t = 2
				elif e:
					t = 3
				if t >= 0:
					border.append(Vector3i(q.x, q.y, t))
					continue
				if ins.has(q + Vector2i(1, 1)):
					border.append(Vector3i(q.x, q.y, 4))
				if ins.has(q + Vector2i(-1, 1)):
					border.append(Vector3i(q.x, q.y, 5))
				if ins.has(q + Vector2i(-1, -1)):
					border.append(Vector3i(q.x, q.y, 6))
				if ins.has(q + Vector2i(1, -1)):
					border.append(Vector3i(q.x, q.y, 7))
	return [ins.keys(), border]


## 按格画一组溟痕（内区先画、围边后画，各自同一张图集连续合批）；col 的 alpha = 淡入淡出
func draw_mire_cells(cells: Array, f: int, col: Color) -> void:
	# docs/139 §6 试验旋钮：render/mire_anim（1 = 两帧每 0.5 秒交替，缺省；0 = 定格第 1 帧）、render/mire_alpha（溟痕本体不透明度倍率，缺省 1）
	_mire_knobs()
	if _mk_anim <= 0.0:
		f = 0
	col.a *= _mk_alpha
	col *= _mk_tint
	var cw: float = MIRE_CELL * g.PX
	var glow: bool = g.optical_on and _mire_ab_e != null
	var gc := Color(col.r, col.g, col.b, col.a * _mk_emit)   # 发光层强度（全亮会盖掉紫色底）
	for c in cells[0]:
		var gx: int = c.x * MIRE_CELL
		var gy: int = c.y * MIRE_CELL
		var src := Rect2((_mire_var(gx, gy) * 2 + f) * 64 + posmod(gx, 64), posmod(gy, 64), MIRE_CELL, MIRE_CELL)
		var dst := Rect2(Vector2(c) * cw, Vector2(cw, cw))
		g.draw_texture_rect_region(_mire_ab, dst, src, col)
		if glow:
			g.glow_tex_next.append([_mire_ab_e, dst, src, gc])
	for b in cells[1]:
		var gx: int = b.x * MIRE_CELL
		var gy: int = b.y * MIRE_CELL
		var ph: int = (posmod(gx, 64) / MIRE_CELL) * 4 + posmod(gy, 64) / MIRE_CELL
		var src := Rect2(ph * MIRE_CELL, ((_mire_var(gx, gy) * 12 + b.z) * 2 + f) * MIRE_CELL, MIRE_CELL, MIRE_CELL)
		var dst := Rect2(Vector2(b.x, b.y) * cw, Vector2(cw, cw))
		g.draw_texture_rect_region(_mire_edge, dst, src, col)
		if glow and _mire_edge_e != null:
			g.glow_tex_next.append([_mire_edge_e, dst, src, gc])


## docs/139 §6 试验旋钮 render/mire_tint_r / _g / _b（缺省 1, 1, 1）：溟痕本体与判定圈乘色，靛紫往深海青灰移（保留蓝调）
func mire_tint() -> Color:
	_mire_knobs()
	return _mk_tint


## 溟痕旋钮每帧读一次（每片溟痕、每格都要用；docs/50 §26：Bal.v 每次拆路径约 1.4 µs）
var _mk_frame := -1
var _mk_tint := Color.WHITE
var _mk_anim := 1.0
var _mk_alpha := 1.0
var _mk_emit := 0.35
func _mire_knobs() -> void:
	var fr: int = Engine.get_process_frames()
	if fr == _mk_frame:
		return
	_mk_frame = fr
	_mk_tint = Color(Bal.v("render/mire_tint_r", 1.0), Bal.v("render/mire_tint_g", 1.0), Bal.v("render/mire_tint_b", 1.0), 1.0)
	_mk_anim = Bal.v("render/mire_anim", 1.0)
	_mk_alpha = Bal.v("render/mire_alpha", 1.0)
	_mk_emit = Bal.v("render/optical_mire_emit", 0.35)


## 64 格块取 A / B 变体（约三分之一 B，减轻 64 像素周期感）
func _mire_var(gx: int, gy: int) -> int:
	return 1 if posmod(hash(Vector2i(floori(gx / 64.0), floori(gy / 64.0))), 3) == 0 else 0


func _mire_disc(m: Dictionary) -> Array:
	var key := Vector3i(int(m.r * 0.25), floori(m.pos.x * 0.125), floori(m.pos.y * 0.125))   # 位置也进键：灯火低时溟痕会挪（docs/147）
	var c = m.get("_mc")
	if c != null and c[0] == key:
		return c[1]
	var cw: float = MIRE_CELL * g.PX
	var r: float = m.r
	var ins := {}
	for cy in range(floori((m.pos.y - r) / cw), floori((m.pos.y + r) / cw) + 1):
		for cx in range(floori((m.pos.x - r) / cw), floori((m.pos.x + r) / cw) + 1):
			if (Vector2(cx + 0.5, cy + 0.5) * cw).distance_to(m.pos) <= r:
				ins[Vector2i(cx, cy)] = true
	var cells := mire_cells(ins)
	m["_mc"] = [key, cells]
	return cells


func draw_mire(m: Dictionary) -> void:
	var a: float = clamp(m.life / 3.0, 0.0, 1.0) if m.get("boss", false) else (1.0 if m.life > 0.0 else 0.0)   # 常驻溟痕不淡出；Boss 溟痕到期前 3 秒淡出
	if m.has("fade"):
		a *= clampf(float(m.fade) / maxf(0.01, float(m.get("fade_len", Bal.v("enemy/mire_fade", 1.5)))), 0.0, 1.0)   # 被挤掉的溟痕慢慢淡出（docs/155）；灯标驱散用 fade_len（扫到前满不透明、到点 0.25 秒碎散）
	var t: float = g.t
	if mire_v2:
		draw_mire_cells(_mire_disc(m), int(t * 2.0 + m.seed) % 2, Color(1, 1, 1, a))
		g.world.tb_ring(m.pos, m.r, 1.5, Color(0.7, 0.4, 1.2, 0.35 * a) * mire_tint(), 36)
		return
	var mt: Texture2D = tex.get(mire_cfg().get("tex", "terrain_mire"))
	if mt != null:
		# 溟痕贴图（2 帧脉动）：按判定半径缩放，外圈画判定提示
		var fw := mt.get_width() / 2
		var sz := Vector2(m.r * 2.3, m.r * 2.3)
		g.draw_texture_rect_region(mt, Rect2(m.pos - sz / 2.0, sz), Rect2(fw * (int(t * 2.0 + m.seed) % 2), 0, fw, mt.get_height()), Color(1, 1, 1, a) * mire_tint())
		g.world.tb_ring(m.pos, m.r, 1.5, Color(0.7, 0.4, 1.2, 0.35 * a) * mire_tint(), 36)   # 判定圈进 world 的无贴图合批，调用方画完所有溟痕后一次提交（性能 9/30）
		return
	for k in 7:
		var off: Vector2 = Vector2.from_angle(k * 0.9 + m.seed) * m.r * 0.45
		g.draw_circle(m.pos + off, m.r * (0.55 + 0.1 * sin(t + k)), Color(0.08, 0.03, 0.12, 0.55 * a))
	g.draw_circle(m.pos, m.r * 0.7, Color(0.12, 0.04, 0.16, 0.6 * a))
	for k in 10:
		var p: Vector2 = m.pos + Vector2.from_angle(k * 2.39 + m.seed) * m.r * (0.3 + 0.07 * k)
		var gl := 0.5 + 0.5 * sin(t * 2.0 + k)
		g.draw_rect(Rect2(p.round(), Vector2(2, 2)), Color(0.5, 0.9, 0.9, 0.6 * gl * a))
