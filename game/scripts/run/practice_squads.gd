extends RefCounted
## Boss 演练 · 成品分队（用户 10-28「boss 演练里面干员数值得提高，或者干脆给我一个成品分队」）。
## 数据 data/practice_squads.json 由 tools/practice_squads.py 从 Boss 单场测试台的到场快照（docs/170）挑出：
##   squads.<开局>_m<认知>.slots.<登场位> = 那一档、那个登场位、中位强度的一份快照（成长事件日志 + 等级 / 藏品运行期变量 + 队长）；
##   avg.<登场位> = 该登场位全部无认知快照的中位数值（等级、最大生命、伤害倍率…），自选队长按它补到「打到这只 Boss 时的平均水平」。
## 只给 Boss 演练用：正常局、测试台都不读它。
const D = preload("res://scripts/data.gd")
const PATH := "res://data/practice_squads.json"
static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f != null:
			var v = JSON.parse_string(f.get_as_text())
			if v is Dictionary:
				_data = v
	return _data


## 菜单用：[{id, label}]，按数据里的顺序
static func list() -> Array:
	var out: Array = []
	for id in data().get("order", []):
		var s: Dictionary = data().get("squads", {}).get(id, {})
		if not s.is_empty():
			out.append({"id": str(id), "label": str(s.get("label", id))})
	return out


## Boss 一组对应的登场位：最终 Boss = 3（10:00）；第一只中期 Boss 只从 mid_first 里抽 = 1（3:30），其余中期 = 2（7:00）
static func slot_of(group: Array) -> int:
	if group.is_empty():
		return 3
	for k in D.ENDINGS:
		if str(D.ENDINGS[k].boss) == str(group[0]):
			return 3
	var idx := D.MID_POOL.find(group)
	if idx >= 0 and D.MID_FIRST.has(idx):
		return 1
	return 2


## 某支分队打这组 Boss 用的快照；这个登场位没有就取最接近的那一位
static func snap_for(id: String, group: Array) -> Dictionary:
	var slots: Dictionary = data().get("squads", {}).get(id, {}).get("slots", {})
	if slots.is_empty():
		return {}
	var want := slot_of(group)
	var best := ""
	for k in slots:
		if best == "" or absi(int(k) - want) < absi(int(best) - want):
			best = str(k)
	return slots[best]


static func squad(id: String) -> Dictionary:
	return data().get("squads", {}).get(id, {})


## 自选队长：等级与主要属性补到该登场位快照的中位数（只往上补，已经更高的不动）。在成长推进、sync_stats 之后调
static func lift(g, group: Array) -> void:
	var av: Dictionary = data().get("avg", {}).get(str(slot_of(group)), {})
	if av.is_empty():
		return
	g.level = maxi(g.level, int(av.get("level", g.level)))
	g.pickups.sync_level_pickup()
	# [快照里的属性名, 属性块里的修正名, 加法 / 乘法]
	for row in [["max_hp", &"max_hp", "mult"], ["dmg_mult", &"dmg", "mult"], ["sp_mult", &"sp_gain", "mult"],
			["armor", &"armor", "flat"], ["regen", &"regen", "flat"]]:
		var want: float = float(av.get(row[0], 0.0))
		var cur: float = float(g.get(row[0]))
		if want <= cur or not g.stats.has_stat(row[1]):
			continue
		if row[2] == "mult" and cur > 0.0:
			g.stats.add(row[1], "mult", want / cur, "practice_avg")
		elif row[2] == "flat":
			g.stats.add(row[1], "flat", want - cur, "practice_avg")
	var taken: float = float(av.get("dmg_taken_mult", 1.0))
	if taken < g.dmg_taken_mult and g.dmg_taken_mult > 0.0 and g.stats.has_stat(&"dmg_taken"):
		g.stats.add(&"dmg_taken", "mult", taken / g.dmg_taken_mult, "practice_avg")
	g.sync_stats()
