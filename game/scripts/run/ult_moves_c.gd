## 终结技 第三组（塞雷娅 / 铃兰 / 逻各斯 / 星熊 / 推进之王 / 艾丽妮 / 拉普兰德 / 流明）（docs/198 §4，用户 10-29「20 个干员的都做好、先用粒子特效」）。接口同 run/ult_moves.gd：
## handles(id) 本文件管哪些人；aim_kind / aim_r 瞄准；start(u, o, aim, dir) 返回动作字典（ult_moves 会写入 a.k / a.o / a.t）；step(u, a, dt) true = 结束。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const IDS: Array = ["saria", "suzuran", "logos", "hoshiguma", "siege", "irene", "lappland", "lumen"]


static func handles(id: String) -> bool:
	return id in IDS


static func aim_kind(_id: String) -> String:
	return "none"


static func aim_r(_id: String) -> float:
	return 460.0


static func start(_u, _o, _aim: Vector2, _dir: Vector2) -> Dictionary:
	return {}


static func step(_u, _a: Dictionary, _dt: float) -> bool:
	return true
