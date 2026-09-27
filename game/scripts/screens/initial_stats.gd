extends RefCounted
## 标题选人预览：角色 JSON 的攻击键名统一映射，并纳入同一 balance 档位修正。
const Bal = preload("res://scripts/core/balance.gd")
const StatDefs = preload("res://scripts/core/stat_defs.gd")

static func _first(data: Dictionary, keys: Array, fallback := 0.0) -> float:
	for key in keys:
		if data.has(key):
			return float(data[key])
	return fallback

static func rows(cid: String, definition: Dictionary) -> Array:
	var b: Dictionary = definition.get("base", {})
	var lead: Dictionary = definition.get("leader", {})
	var doctor: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/doctor.json")).get("stats", {})
	var mod: Dictionary = Bal.op(cid)
	var hp: float = float(lead.get("max_hp", doctor.get("max_hp", StatDefs.PLAYER[&"max_hp"].base)))
	var atk: float = _first(b, ["atk", "m_atk", "umbrella_dmg", "bolt_atk"]) * (1.0 + float(mod.get("atk", 0.0)))
	var interval: float = _first(b, ["cd", "m_cd", "swing_interval", "bolt_cd"]) / maxf(0.2, 1.0 + float(mod.get("aspd", 0.0)))
	var reach: float = _first(b, ["range", "bolt_range", "reach", "m_reach", "swing_radius", "len"]) * (1.0 + float(mod.get("range", 0.0)))
	var speed: float = float(doctor.get("move_speed", StatDefs.PLAYER[&"move_speed"].base))
	return [["初始生命", "%.0f" % hp], ["Mon3tr 攻击" if b.has("m_atk") else "初始攻击", "%.1f" % atk],
		["攻击间隔", "%.2f 秒" % interval], ["攻击范围", "%.0f" % reach], ["移动速度", "%.0f" % speed],
		["初始阶段", "未精英化"]]
