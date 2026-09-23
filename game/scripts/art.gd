extends RefCounted
## 美术资源加载：优先读取项目外的 art/incoming/（美术新交付的图），没有再用游戏内置的占位图。
## 这样新图放进文件夹后，重新打开游戏就能看到，不需要重新导出。

static var _cache := {}

## 美术交付用旧文件名时的对应关系（新名 -> incoming 里的文件名）
const ALIAS := {
	"e_bone": "drifter", "e_slider": "dart", "e_stone": "crawler", "e_pocket": "shell",
	# Boss 首轮美术（art/incoming/bosses/，2 帧待机）
	"e_path": "bosses/boss_pathshaper_idle", "e_fractal": "bosses/pathshaper_fractal_idle",
	"e_carmen": "bosses/boss_carmen_idle", "e_iberia": "bosses/boss_iberia_idle",
	"e_bishop": "bosses/boss_tide_bishop_idle", "e_bishop_feign": "bosses/boss_tide_bishop_feign",
	"e_archon": "bosses/boss_tide_defier_idle", "e_archon_feign": "bosses/boss_tide_defier_feign",
	"e_immortal": "bosses/boss_tide_rebuker_idle", "e_immortal_feign": "bosses/boss_tide_rebuker_feign",
	"e_paranoia": "bosses/boss_paranoia_phase1_idle", "e_paranoia2": "bosses/boss_paranoia_phase2_idle",
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
