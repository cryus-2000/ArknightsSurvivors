## 连携技（docs/198 §5 / §6.2）：20 人触发条件 + 冲到目标出招再回队 + 原作关系组合升级。框架（亮起、排队、E、冷却、能量与协同）在 run/ult.gd（u）。
extends RefCounted


static func cd_of(_id: String) -> float:
	return 14.0


## 触发判定：满足返回 info（目标等），不满足返回 {}
static func check(_u, _o) -> Dictionary:
	return {}


## 亮起那一刻（安洁莉娜「另一名队友的连携亮起时」读）
static func on_lit(_u, _o, _info: Dictionary) -> void:
	pass


static func fire(_u, _o, _info: Dictionary, _dir: Vector2) -> Dictionary:
	return {}


static func step(_u, _a: Dictionary, _dt: float) -> bool:
	return true
