extends RefCounted
## 藏品数据库（框架第 32 节 RelicData）
## 数据来源：
##   res://data/relics.json         —— 265 件藏品的名称、等级、分类 lane（docs/197）、商店可否（由 docs/08 生成）
##   res://data/relic_effects.json  —— 已实装藏品的效果数据（modifier_system 的 effects 数组）+ 价格档
## 只有在 relic_effects.json 里有效果的藏品才会进入随机池。

const PRICE := {"基础": 10, "稀有": 14, "核心": 20, "升华": 30, "遭诅古物": 6, "结局": 0}
const VBal = preload("res://scripts/core/balance.gd")

var items := {}       # id(String) -> RelicData Dictionary
## 藏品分类（docs/197，只此一套）：7 条流派（docs/181，与干员 lanes 同一组键）+ 4 个非流派组
const LANES7 := ["melee", "multi", "summon", "control", "weak", "shield", "heal"]
const WEIGHT_LANES := ["melee", "multi", "summon", "control", "weak", "shield", "heal", "class"]   # 参与流派加权 / 主流派的分类（docs/197 §4）
var lane_names := {}  # 分类键 -> 名称（relics.json 顶层 lane_names）


## 藏品说明里的数值占位（docs/61 §1.4 同一套写法，复用 character.gd 的 fill_line）：
## 「随时间成长」的说明写成 {$键} 表达式，按 balance.json 现值填，曲线改了文字自动跟着变（docs/76 §6）。
## 可用的键：pm = 8:00 前每分钟增加的倍数（60 / hp_div）；m10 = 10:00 时的倍数；
## 以及藏品伤害旋钮 mine_dmg / wrath_dmg / dust_dmg / scavenge_mult（balance.json relic 段）。例：伤害 {$mine_dmg}，每分钟 +{$mine_dmg*$pm:0}（10:00 约 {$mine_dmg*$m10:0}）
static func text_base() -> Dictionary:
	var Bal = preload("res://scripts/core/balance.gd")
	var knee: float = Bal.v("enemy/hp_knee", 480.0)
	var div: float = maxf(1.0, Bal.v("enemy/hp_div", 120.0))
	var late: float = maxf(1.0, Bal.v("enemy/hp_late_div", 300.0))
	return {"pm": 60.0 / div, "m10": 1.0 + minf(600.0, knee) / div + maxf(600.0 - knee, 0.0) / late,
		"mine_dmg": Bal.v("relic/mine_dmg", 42.0), "wrath_dmg": Bal.v("relic/wrath_dmg", 30.0),
		"dust_dmg": Bal.v("relic/dust_dmg", 10.0), "scavenge_mult": Bal.v("relic/scavenge_mult", 8.0)}


static func fill_desc(s: String) -> String:
	if not s.contains("{$") and not s.contains("$"):
		return s
	return preload("res://scripts/characters/character.gd").fill_line(s, text_base())


func load_files(meta_path: String = "res://data/relics.json", fx_path: String = "res://data/relic_effects.json") -> int:
	items.clear()
	var meta = _read_json(meta_path)
	var fx = _read_json(fx_path)
	if meta == null:
		push_error("读取藏品表失败: " + meta_path)
		return 0
	var effects: Dictionary = fx.get("relics", {}) if fx is Dictionary else {}
	lane_names = meta.get("lane_names", {})
	for r in meta.items:
		var id := str(int(r.id))
		var e: Dictionary = effects.get(id, {})
		if e.has("legacy") and VBal.v("relic/visible_growth", 1.0) <= 0.0:   # 可见成长（docs/163）：旋钮 0 = 退回改造前的纯数值版（effects / desc / 等级上限）
			e = e.duplicate()
			e.effects = e.legacy
			e.desc = e.legacy_desc
			e.erase("max_lv")
		var rarity: String = str(e.get("rarity", r.rarity))
		items[id] = {
			"id": id, "name": r.name, "desc": fill_desc(str(e.get("desc", r.adapt))), "rarity": rarity,
			"desc_squad": e.get("desc_squad", {}),
			"lane": str(r.get("lane", "general")), "lane_name": str(lane_names.get(str(r.get("lane", "general")), "通用")), "set": str(e.get("set", "")), "tier": r.tier,
			"source": e.get("source", "boss" if r.get("boss_only", false) else "any"),
			"shop_allowed": e.get("shop_allowed", r.shop_allowed),
			"requirements": e.get("requires", []), "conflicts": e.get("conflicts", []),
			"requires_class": e.get("requires_class", []),
			"price_class": e.get("price_class", rarity), "effects": e.get("effects", []),
			"max_lv": int(e.get("max_lv", 0)),
			"late_weight": float(e.get("late_weight", 1.0)),
			"late_fuse": int(e.get("late_fuse", 0)),   # docs/74：源石锭熔铸后获得时，折算成这么多枚源石锭熔铸（锈蚀的铁锤）
			"new_pool": bool(e.get("new", false)),   # docs/57 第二批实装：balance.json relic/new_pool = 0 时不进池（A/B 用）
			"implemented": e.has("effects"), "first_batch": r.get("first_batch", false),
			"pool": bool(e.get("pool", true)),       # 藏品精简（docs/203）：false = 不进任何来源，已持有的照常生效
			"filler": bool(e.get("filler", false)),  # 填充件：出现权重 × relic/filler_weight（relic_pool_ids）
			"shield_layer": (e.get("effects", []) as Array).any(func(x): return x is Dictionary and x.get("type") == "stat" and x.get("stat") == "shield_max" and float(x.get("value", 0)) > 0.0),   # 给护盾层数（relic/shield_weight）
		}
	return items.size()


## 分类显示名（流派名或「通用 / 职业 / 生存 / 经济」）
func lane_name(id: String) -> String:
	return str(items.get(id, {}).get("lane_name", "通用"))


func get_relic(id: String) -> Dictionary:
	return items.get(id, {})


func implemented() -> Array:
	return items.values().filter(func(r): return r.implemented)


func price(id: String, mult: float = 1.0) -> int:
	return maxi(1, int(round(PRICE.get(items[id].price_class, 14) * mult)))


## 候选池：已实装、未拥有、满足前置、不冲突
func pool(owned: Array, filter: Callable = Callable()) -> Array:
	var out: Array = []
	for r in items.values():
		if not r.implemented or owned.has(r.id):
			continue
		var ok := true
		for q in r.requirements:
			if not owned.has(str(q)):
				ok = false
		for c in r.conflicts:
			if owned.has(str(c)):
				ok = false
		if ok and (not filter.is_valid() or filter.call(r)):
			out.append(r)
	return out


func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))
