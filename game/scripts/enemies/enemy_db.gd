## 敌人 / 刷怪表加载：data/enemies.json、data/waves.json → 字典（tint 转成 Color）。
extends RefCounted

static var _waves: Dictionary = {}


static func _read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("missing: " + path)
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


static func load_enemies() -> Dictionary:
	var out: Dictionary = {}
	var src: Dictionary = _read("res://data/enemies.json").get("enemies", {})
	for k in src:
		var e: Dictionary = src[k].duplicate()
		if e.has("tint") and e.tint is Array:
			var c: Array = e.tint
			e.tint = Color(c[0], c[1], c[2])
		# JSON 里的整数会读成 float，这几项在代码里按 int 用
		for ik in ["ammo", "ingots"]:
			if e.has(ik):
				e[ik] = int(e[ik])
		out[k] = e
	return out


static func load_waves() -> Dictionary:
	if _waves.is_empty():
		_waves = _read("res://data/waves.json")
		if not _waves.has("threat"):
			_waves = {"threat": [], "boss_times": [], "mid_pool": [], "endings": {}}
	return _waves
