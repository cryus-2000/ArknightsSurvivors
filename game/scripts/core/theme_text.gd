extends RefCounted
## 主题文案覆盖表（docs/412，用户 11-25 定）：公用代码里写死的玩家可见文案按主题改写。
## TT.t("键", "代码原文")：当前主题有 res://themes/<id>/data/strings.json 且含这个键 → 用主题的；否则原样返回代码原文。
## 水月不写覆盖表 = 全部原文（theme_parity 零差异）。值为空串 = 这个主题不显示这句（调用方按空串跳过）。
## 只读文件、结果缓存；不碰随机数，同种子玩法不变。

const ThemePack = preload("res://scripts/core/theme_pack.gd")

static var _d = null


static func _load() -> void:
	if _d != null:
		return
	_d = {}
	var p := "res://themes/%s/data/strings.json" % ThemePack.id()
	if FileAccess.file_exists(p):
		var j = JSON.parse_string(FileAccess.get_file_as_string(p))
		if j is Dictionary:
			_d = j


static func t(key: String, dflt: String) -> String:
	_load()
	return str(_d.get(key, dflt))


static func has(key: String) -> bool:
	_load()
	return _d.has(key)
