extends RefCounted
## 主题包清单与数据路径门面（docs/357 §6.1 阶段 0、docs/359 §2）。
## 主题相关的数据文件一律经这里取路径：ThemePack.path("waves") → "res://data/waves.json"（水月 / 深海主题当前就指向原路径，数据文件还没搬家）。
## 清单：res://themes/<id>/theme.json 的 data 段（键 → res:// 路径）、maps 段（地图目录 / 缺省地图）、assets 段（标题 / 配乐 / 地面 / 光照引用，阶段 2 才接线）。
## 干员、通用 UI、balance.json 等通用数据不走这里。用法：const ThemePack = preload("res://scripts/core/theme_pack.gd")（不做自动加载：-s 契约测试里也要能用）。
## 只读文件、不抽随机数、结果缓存在静态变量里；同种子玩法逐帧不变（tools/theme_parity.py）。

const DEFAULT_ID := "deep_sea"
const ROOT := "res://themes/"

static var _id := DEFAULT_ID
static var _man: Dictionary = {}


## 当前主题 id（阶段 0 只有 deep_sea；选主题界面 / 存档主题层级在后续阶段）
static func id() -> String:
	return _id


static func manifest() -> Dictionary:
	if _man.is_empty():
		var p := ROOT + _id + "/theme.json"
		var d = JSON.parse_string(FileAccess.get_file_as_string(p)) if FileAccess.file_exists(p) else null
		if not (d is Dictionary):
			push_error("theme manifest missing: " + p)
			d = {}
		_man = d
	return _man


## 主题数据文件路径。key 是清单 data 段的键（waves / enemies / events_v2 / relics / …）。
## 清单里没有这个键时报错并退回 res://data/<key>.json（与改造前的写死路径相同），不让游戏因清单漏项起不来。
static func path(key: String) -> String:
	var data: Dictionary = manifest().get("data", {})
	if data.has(key):
		return str(data[key])
	push_error("theme %s: data key missing: %s" % [_id, key])
	return "res://data/%s.json" % key


## 地图目录（Map.list_ids 列这个目录下的 *.json）
static func maps_dir() -> String:
	return str(manifest().get("maps", {}).get("dir", "res://data/maps"))


## 某张地图的 json 路径
static func map_path(map_id: String) -> String:
	return "%s/%s.json" % [maps_dir(), map_id]
