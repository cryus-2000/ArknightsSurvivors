extends RefCounted
## 主题包清单与数据路径门面（docs/357 §6.1 阶段 0、docs/359 §2）。
## 主题相关的数据文件一律经这里取路径：ThemePack.path("waves") → "res://themes/deep_sea/data/waves.json"（11-18 起主题自己的数据在主题包里，共享 / 混合的仍在 res://data/，docs/367 §2）。
## 清单：res://themes/<id>/theme.json 的 data 段（键 → res:// 路径）、maps 段（地图目录 / 缺省地图）、assets 段（标题 / 配乐 / 地面 / 光照引用，阶段 2 才接线）。
## 干员、通用 UI、balance.json 等通用数据不走这里。用法：const ThemePack = preload("res://scripts/core/theme_pack.gd")（不做自动加载：-s 契约测试里也要能用）。
## 只读文件、不抽随机数、结果缓存在静态变量里；同种子玩法逐帧不变（tools/theme_parity.py）。

const DEFAULT_ID := "deep_sea"
const ROOT := "res://themes/"

static var _id := ""
static var _man: Dictionary = {}


## 当前主题 id（docs/391 T-R1）：开发版读命令行 --theme=<id>，否则读 res://data/build.json 的 theme（export_web.py / export_build.py --theme 写入，
## 一个 Toy 包只带一个主题）；都没有 = deep_sea。要求 res://themes/<id>/theme.json 存在，不存在报错退回 deep_sea。第一次调用后缓存，局中不切
static func id() -> String:
	if _id == "":
		_id = _resolve()
	return _id


static func _resolve() -> String:
	var want := ""
	var args: PackedStringArray = OS.get_cmdline_user_args() if OS.is_debug_build() else PackedStringArray()
	for a in args:
		if a.begins_with("--theme="):
			want = a.substr(8).strip_edges()
	if want == "":
		var b = _read_json("res://data/build.json")
		want = str(b.get("theme", ""))
	if want == "" or want == DEFAULT_ID:
		return DEFAULT_ID
	if not FileAccess.file_exists(ROOT + want + "/theme.json"):
		push_error("theme not found: %s（退回 %s）" % [want, DEFAULT_ID])
		return DEFAULT_ID
	return want


## 本主题清单里有没有这个机制（lamp / beacon / …）。game 未建好时（-s 契约测试、界面）也能问
static func has_mechanic(mid: String) -> bool:
	for it in manifest().get("mechanics", []):
		if str(it.get("id", "")) == mid:
			return true
	return false


static func manifest() -> Dictionary:
	if _man.is_empty():
		var p := ROOT + id() + "/theme.json"
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
	push_error("theme %s: data key missing: %s" % [id(), key])
	return "res://data/%s.json" % key


## 主题机制（docs/364）：按清单 mechanics 段的顺序实例化 → {id: 实例}（字典按插入顺序 = 清单顺序，game.mechs 取 values()）。
## 每项 {"id": "lamp", "script": "res://themes/deep_sea/mech/mech_lamp.gd"}；脚本继承 scripts/core/theme_mechanic.gd、_init(game)。
static func make_mechanics(game) -> Dictionary:
	var out: Dictionary = {}
	for it in manifest().get("mechanics", []):
		var sc = load(str(it.script))
		if sc == null:
			push_error("theme %s: mechanic script missing: %s" % [id(), it.script])
			continue
		var m = sc.new(game)
		m.id = str(it.id)
		out[m.id] = m
	return out


## 主题专属玩法模块（docs/368 §3）：清单 modules 段 {键: 脚本}，脚本 _init(game)；本主题没有这个模块时用 fallback（res:// 脚本路径，空 = 返回 null）
## knight 的 fallback 是 scripts/core/knight_none.gd（核心多处直接读 g.knight，docs/369 §5）
static func make_module(game, key: String, fallback := ""):
	var path = manifest().get("modules", {}).get(key)
	if path == null:
		path = fallback
	if str(path) == "":
		return null
	var sc = load(str(path))
	if sc == null:
		push_error("theme %s: module script missing: %s" % [id(), path])
		return null
	return sc.new(game)


## 共享 + 主题两份合并读（docs/368 §4，lore / guide / onboard 这类混合文件）：先读 res://data/<键>.json（共享部分），
## 再把清单 data 段指向的主题部分叠上去——两边都是字典的键合并（主题优先）、pages_insert 按 at 插回 pages、其余主题覆盖；_doc 不合并。
## 主题部分和共享路径相同（没拆）时就是那一份。tools/theme_paths.load_json 是同一条规则
static func load_merged(key: String) -> Dictionary:
	var shared_p := "res://data/%s.json" % key
	var out := _read_json(shared_p)
	var tp := path(key)
	if tp == shared_p:
		return out
	var th := _read_json(tp)
	for k in th:
		if str(k) == "_doc":
			continue
		if str(k) == "pages_insert":
			var ins: Array = (th[k] as Array).duplicate()
			ins.sort_custom(func(a, b): return int(a.at) < int(b.at))
			if not out.has("pages"):
				out["pages"] = []
			for it in ins:
				(out.pages as Array).insert(int(it.at), it.page)
		elif th[k] is Dictionary and out.get(k) is Dictionary:
			(out[k] as Dictionary).merge(th[k], true)
		else:
			out[k] = th[k]
	return out


static func _read_json(p: String) -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(p)) if FileAccess.file_exists(p) else null
	return d if d is Dictionary else {}


## 地图目录（Map.list_ids 列这个目录下的 *.json）
static func maps_dir() -> String:
	return str(manifest().get("maps", {}).get("dir", "res://data/maps"))


## 某张地图的 json 路径
static func map_path(map_id: String) -> String:
	return "%s/%s.json" % [maps_dir(), map_id]
