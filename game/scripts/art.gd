extends RefCounted
## 美术资源加载：优先读取项目外的 art/incoming/（美术新交付的图），没有再用游戏内置的占位图。
## 这样新图放进文件夹后，重新打开游戏就能看到，不需要重新导出。

static var _cache := {}

## 美术交付用旧文件名时的对应关系（新名 -> incoming 里的文件名）
const ALIAS := {
	"e_bone": "drifter", "e_slider": "dart", "e_stone": "crawler", "e_pocket": "shell",
	"e_paranoia2": "e_paranoia_phase2", "e_paranoia2_move": "e_paranoia_phase2_move",
	# 藏品图标按原作编号命名（docs/11）；代码里仍用旧 id 的护盾藏品先做对照
	"relic_sh_base": "relic_118", "relic_sh_count": "relic_199", "relic_sh_fast": "relic_15",
	"relic_sh_burst": "relic_100", "relic_sh_plate": "relic_200", "relic_sh_ring": "relic_202",
}


static func _incoming_path(name: String) -> String:
	var p := incoming_dir().path_join(name + ".png")
	if FileAccess.file_exists(p):
		return p
	if ALIAS.has(name):
		var a := incoming_dir().path_join(ALIAS[name] + ".png")
		if FileAccess.file_exists(a):
			return a
	return ""


static func incoming_dir() -> String:
	if OS.has_feature("web"):
		return "res://art/incoming"  # 网页版：导出时把 art/incoming 打进包里（export_presets 的 include_filter）
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://").path_join("../art/incoming").simplify_path()
	return OS.get_executable_path().get_base_dir().path_join("../art/incoming").simplify_path()


static func has_override(name: String) -> bool:
	return _incoming_path(name) != ""


## 是否为贴图生成法线图（2D 法线光照）；由 game.gd 按 Cfg.normal_maps 在加载前设置
static var normal_maps := false
## 高清贴图：art/incoming/<name>@2x.png 存在时优先使用，像素密度 2 倍（96px 画 48px 的内容），
## 绘制时倍率减半，锚点 / 判定 / 帧数都不变。_hires 按名字记倍数，_hires_rid 按贴图记倍数。
static var _hires := {}
static var _hires_rid := {}
## 不做法线的贴图前缀（地面 / 特效 / UI 图标：做了反而奇怪）
const NO_NORMAL_PREFIX := ["tiles", "terrain_", "fx_", "proj_", "relic_", "growth_", "skill_", "evo_", "weapon_", "light", "shadow", "slash", "title_", "ebullet", "drone_bullet", "drone_laser"]


## 取贴图；找不到返回 null
static func tex(name: String) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
	var t: Texture2D = null
	var density := 1.0
	var p2 := _incoming_path(name + "@2x")
	if p2 != "":
		var img2 := Image.load_from_file(p2)
		if img2 != null and not img2.is_empty():
			t = ImageTexture.create_from_image(img2)
			density = 2.0
	if t == null:
		var p := _incoming_path(name)
		if p != "":
			var img := Image.load_from_file(p)
			if img != null and not img.is_empty():
				t = ImageTexture.create_from_image(img)
	if t == null and ResourceLoader.exists("res://art/px/%s.png" % name):
		t = load("res://art/px/%s.png" % name)
	if t != null and normal_maps and _wants_normal(name):
		t = _with_normal(t)
	if t != null:
		_hires[name] = density
		_hires_rid[t.get_rid()] = density
	_cache[name] = t
	return t


## 贴图的像素密度（1 = 普通，2 = @2x 高清），绘制倍率应除以它
static func hires(name: String) -> float:
	return float(_hires.get(name, 1.0))


static func hires_of(t: Texture2D) -> float:
	if t == null:
		return 1.0
	return float(_hires_rid.get(t.get_rid(), 1.0))


static func _wants_normal(name: String) -> bool:
	for pre in NO_NORMAL_PREFIX:
		if name.begins_with(pre):
			return false
	return true


## 用 alpha 轮廓生成粗糙的法线图（边缘向外倾斜、中间朝向镜头），再打包成 CanvasTexture 供 Light2D 使用
static func _with_normal(src: Texture2D) -> Texture2D:
	var img := src.get_image()
	if img == null:
		return src
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	if w * h > 400000:
		return src
	# 高度场：alpha 的 3×3 均值再取两次，得到圆润的"充气"高度
	var hgt := PackedFloat32Array()
	hgt.resize(w * h)
	for y in h:
		for x in w:
			hgt[y * w + x] = 1.0 if img.get_pixel(x, y).a > 0.5 else 0.0
	for _pass in 2:
		var nh := PackedFloat32Array()
		nh.resize(w * h)
		for y in h:
			for x in w:
				var acc := 0.0
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var xx := clampi(x + dx, 0, w - 1)
						var yy := clampi(y + dy, 0, h - 1)
						acc += hgt[yy * w + xx]
				nh[y * w + x] = acc / 9.0
		hgt = nh
	var nimg := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var l: float = hgt[y * w + maxi(x - 1, 0)]
			var r: float = hgt[y * w + mini(x + 1, w - 1)]
			var u: float = hgt[maxi(y - 1, 0) * w + x]
			var d: float = hgt[mini(y + 1, h - 1) * w + x]
			var n := Vector3((l - r) * 2.0, (d - u) * 2.0, 1.0).normalized()
			nimg.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5, 1.0))
	var ct := CanvasTexture.new()
	ct.diffuse_texture = src
	ct.normal_texture = ImageTexture.create_from_image(nimg)
	ct.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return ct


## 由任意贴图生成白色剪影（受击闪白用）
static func white_of(src: Texture2D) -> Texture2D:
	if src == null:
		return null
	var img := src.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.0:
				img.set_pixel(x, y, Color(1, 1, 1, c.a))
	return ImageTexture.create_from_image(img)
