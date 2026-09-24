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
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://").path_join("../art/incoming").simplify_path()
	return OS.get_executable_path().get_base_dir().path_join("../art/incoming").simplify_path()


static func has_override(name: String) -> bool:
	return _incoming_path(name) != ""


## 取贴图；找不到返回 null
static func tex(name: String) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
	var t: Texture2D = null
	var p := _incoming_path(name)
	if p != "":
		var img := Image.load_from_file(p)
		if img != null and not img.is_empty():
			t = ImageTexture.create_from_image(img)
	if t == null and ResourceLoader.exists("res://art/px/%s.png" % name):
		t = load("res://art/px/%s.png" % name)
	_cache[name] = t
	return t


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
