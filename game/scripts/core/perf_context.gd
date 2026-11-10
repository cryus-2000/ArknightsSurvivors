extends RefCounted
## 每局独立，只记实际出生的 Boss。种子以十进制文本入 JSON，保留全部 64 位。
signal changed
const MAX_BOSSES := 16
var _seed := ""
var _settings := {}
var _bosses: Array[Dictionary] = []


func seeded(value: int) -> void:
	_seed = str(value)
	changed.emit()


func configured(difficulty: String, tide: int, diff: int, cells: int) -> void:
	_settings = {"difficulty": difficulty, "tide": tide, "diff": diff, "meta_cells": cells}
	changed.emit()


func admitted(enemy: Dictionary, definition: Dictionary, at: float) -> void:
	if definition.get("role", "") != "boss" or not enemy.get("boss", false) or enemy.get("part", false):
		return
	var id := str(enemy.get("type", ""))
	if id.is_empty() or _bosses.size() >= MAX_BOSSES:
		return
	for boss in _bosses:
		if boss.id == id:
			return
	_bosses.append({"id": id, "name": str(definition.get("name", id)), "t": maxi(0, floori(at))})
	changed.emit()


func snapshot(g) -> Dictionary:
	if _seed.is_empty():
		return {}   # 崩溃记录可能先于随机流初始化，不能把默认值当本局种子。
	var result := _settings.duplicate()
	result.seed = _seed
	result.bosses = _bosses.duplicate(true)
	var team: Array[Dictionary] = []
	if g.squad != null:
		for op in g.squad.ops:
			team.append({"id": str(op.id), "name": op.display_name()})
	result.squad = team
	return result


static func lines(raw: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if not raw is Dictionary or raw.is_empty():
		return out
	var details := PackedStringArray()
	if raw.has("seed"):
		details.append("种子 %s" % raw.seed)
	if raw.has("tide"):
		var difficulty := str(raw.get("difficulty", ""))
		details.append(("难度 %s · " % difficulty if not difficulty.is_empty() else "") + "潮位 %d" % int(raw.tide))
		if int(raw.get("diff", raw.tide)) != int(raw.tide):
			details.append("难度等级 %d" % int(raw.diff))
	if raw.has("meta_cells"):
		details.append("认知塑造 %d 生机细胞" % int(raw.meta_cells))
	if not details.is_empty():
		out.append(" · ".join(details))
	var team := PackedStringArray()
	for member in raw.get("squad", []):
		if member is Dictionary:
			team.append(str(member.get("name", member.get("id", ""))))
	if not team.is_empty():
		out.append("编队 " + " / ".join(team))
	if raw.has("bosses"):
		var names := PackedStringArray()
		for boss in raw.bosses:
			if boss is Dictionary:
				var sec := maxi(0, int(boss.get("t", 0)))
				names.append("%d:%02d %s" % [sec / 60, sec % 60, str(boss.get("name", boss.get("id", "")))])
		out.append("登场 Boss " + (" / ".join(names) if not names.is_empty() else "尚未登场"))
	return out
