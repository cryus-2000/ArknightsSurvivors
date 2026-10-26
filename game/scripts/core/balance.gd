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
	# 测试探针（数值 close7 9c509e3 原样搬入 main，协调人 9/30）：--bal=段/键=值 覆盖旋钮，一个分支跑多组数值；
	# 唯一改动：只在 debug 构建读命令行（发布版无效，check_release 要求；Bal 可能早于 Cfg 加载，所以就地判断）
	for a in (OS.get_cmdline_user_args() if OS.is_debug_build() else PackedStringArray()):
		if a.begins_with("--bal=") and a.count("=") == 2:
			var kv: PackedStringArray = a.substr(6).split("=")
			var keys: PackedStringArray = kv[0].split("/")
			var cur: Dictionary = _data
			for i in keys.size() - 1:
				if not (cur.get(keys[i]) is Dictionary):
					cur[keys[i]] = {}
				cur = cur[keys[i]]
			cur[keys[keys.size() - 1]] = float(kv[1])
	_preset("nausea_safe", NAUSEA_SAFE)
	_preset("palette_trial", PALETTE_TRIAL)
	_preset("foe_calm", FOE_CALM)


## docs/139 画面眩晕排查的「推荐组合」试验开关 render/nausea_safe（缺省 0 = 不动）：1 时把 NAUSEA_SAFE 里的旋钮一次套上，
## 命令行 --bal= 单独写过的键优先。给用户同局对照用，缺省值等用户看过对照再定
const NAUSEA_SAFE := {
	"render/cam_round": 0.0,
	"render/optical_int_zoom": 1.0,
	"fx/leader_kick": 0.0,
	"fx/recoil_px1": 0.0, "fx/recoil_px2": 1.0, "fx/recoil_px3": 2.0, "fx/recoil_px": 1.0,
	"fx/squash_basic": 0.0, "fx/squash_dot": 0.0, "fx/squash_skill": 0.06,
	"fx/hitstop_gap": 1.5, "fx/hit_pause_m": 0.0,
	"render/optical_sea": 0.3,
}


## docs/139 §6 水月肉鸽配色对照的「调色方案」试验开关 render/palette_trial（缺省 0）：同上，只管颜色
const PALETTE_TRIAL := {
	"render/optical_sat": 0.5,
	"render/optical_sea": 0.2,
	"render/ambient_gain": 1.35,
	"render/mire_alpha": 0.6,
	"render/mire_anim": 0.0,
	"render/optical_mire_emit": 0.2,
	"render/mire_tint_r": 0.5, "render/mire_tint_g": 0.95, "render/mire_tint_b": 0.8,
	"render/zone_dark_r": 0.03, "render/zone_dark_g": 0.08, "render/zone_dark_b": 0.12,
}


## docs/139 §8 怪物攻击圈环「重做版」试验开关 render/foe_calm（缺省 0）：玩法提示的形状 / 时机不变，只去掉流动、转动、脉动、整片白闪和结算后的装饰环
const FOE_CALM := {
	"render/warn_flash_fill": 0.0,
	"render/warn_hatch_flow": 0.0,
	"render/nest_aura_lite": 1.0,
	"render/tell_circle_calm": 1.0,
	"render/foe_ring_fx": 0.0,
}


static func _preset(key: String, table: Dictionary) -> void:
	var r = _data.get("render")
	if not (r is Dictionary) or float(r.get(key, 0.0)) <= 0.0:
		return
	var given := {}
	for a in (OS.get_cmdline_user_args() if OS.is_debug_build() else PackedStringArray()):
		if a.begins_with("--bal=") and a.count("=") == 2:
			given[a.substr(6).split("=")[0]] = true
	for path in table:
		if given.has(path):
			continue
		var keys: PackedStringArray = str(path).split("/")
		if not (_data.get(keys[0]) is Dictionary):
			_data[keys[0]] = {}
		_data[keys[0]][keys[1]] = table[path]


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
