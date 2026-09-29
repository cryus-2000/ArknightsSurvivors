## 数值平衡旋钮（docs/27）：data/balance.json 的静态读取器。
## 用法：Bal.v("enemy/hp_div", 120.0)、Bal.op("wisadel")、Bal.sec("bot")。找不到的键一律返回默认值，JSON 缺失也不影响运行。
extends RefCounted

static var _data: Dictionary = {}
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open("res://data/balance.json", FileAccess.READ)
	if f == null:
		push_warning("data/balance.json 缺失，全部使用代码默认值")
		return
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		_data = d
	# 测试探针（numbers-probe，不合入 main）：--bal=段/键=值 覆盖旋钮，一个分支跑多组数值
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--bal=") and a.count("=") == 2:
			var kv: PackedStringArray = a.substr(6).split("=")
			var keys: PackedStringArray = kv[0].split("/")
			var cur: Dictionary = _data
			for i in keys.size() - 1:
				if not (cur.get(keys[i]) is Dictionary):
					cur[keys[i]] = {}
				cur = cur[keys[i]]
			cur[keys[keys.size() - 1]] = float(kv[1])


## 按「段/键」路径取数值
static func v(path: String, default: float) -> float:
	_load()
	var cur: Variant = _data
	for k in path.split("/"):
		if cur is Dictionary and cur.has(k):
			cur = cur[k]
		else:
			return default
	return float(cur) if (cur is float or cur is int) else default


static func vi(path: String, default: int) -> int:
	return int(v(path, float(default)))


## 整段（字典）；没有返回空字典
static func sec(path: String) -> Dictionary:
	_load()
	var cur: Variant = _data
	for k in path.split("/"):
		if cur is Dictionary and cur.has(k):
			cur = cur[k]
		else:
			return {}
	return cur if cur is Dictionary else {}


## 干员档位系数：{tier, atk, aspd, range, skill_power}
static func op(cid: String) -> Dictionary:
	return sec("operators/" + cid)


## 测试用：重新读取
static func reload() -> void:
	_loaded = false
	_data = {}
	_load()
