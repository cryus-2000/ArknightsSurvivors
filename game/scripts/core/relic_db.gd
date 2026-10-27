extends RefCounted
## 藏品数据库（框架第 32 节 RelicData）
## 数据来源：
##   res://data/relics.json         —— 262 件藏品的名称、等级、流派、Tag、商店可否（由 docs/08 生成）
##   res://data/relic_effects.json  —— 已实装藏品的效果数据（modifier_system 的 effects 数组）+ 价格档
## 只有在 relic_effects.json 里有效果的藏品才会进入随机池。

const RARITY_WEIGHT := {"基础": 60.0, "稀有": 26.0, "核心": 12.0, "升华": 0.0, "遭诅古物": 0.0, "结局": 0.0}
const PRICE := {"基础": 10, "稀有": 14, "核心": 20, "升华": 30, "遭诅古物": 6, "结局": 0}
## Soft Steering 强度（框架第 13 节：只轻微提高相关 Tag 出现率）
const STEER := 0.6
const VBal = preload("res://scripts/core/balance.gd")

var items := {}       # id(String) -> RelicData Dictionary
var effect_category_names := {}  # 实装效果主分类；独立于构筑流派和抽取 Tag
var lane_names := {}  # 流派代号 -> 名称（relics.json 顶层 lanes，docs/35）


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
	effect_category_names.clear()
	var meta = _read_json(meta_path)
	var fx = _read_json(fx_path)
	if meta == null:
		push_error("读取藏品表失败: " + meta_path)
		return 0
	var effects: Dictionary = fx.get("relics", {}) if fx is Dictionary else {}
	lane_names = meta.get("lanes", {})
	effect_category_names = fx.get("effect_categories", {}) if fx is Dictionary else {}
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
			"id": id, "name": r.name, "cat": r.get("cat", ""), "desc": fill_desc(str(e.get("desc", r.adapt))), "rarity": rarity,
			"effect_category": e.get("effect_category", ""),
			"tags": e.get("tags", r.tags), "lanes": e.get("lanes", r.lanes), "tier": r.tier,
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
			"shield_layer": (e.get("effects", []) as Array).any(func(x): return x is Dictionary and x.get("type") == "stat" and x.get("stat") == "shield_max" and float(x.get("value", 0)) > 0.0),   # 给护盾层数（relic/shield_weight）
		}
	return items.size()


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


## 加权抽取 n 件（不重复）。weight_fn(r) 返回权重
func pick(candidates: Array, n: int, weight_fn: Callable, rng: RandomNumberGenerator) -> Array:
	var c := candidates.duplicate()
	var out: Array = []
	while out.size() < n and not c.is_empty():
		var total := 0.0
		var ws: Array = []
		for r in c:
			var w: float = maxf(0.0, weight_fn.call(r))
			ws.append(w)
			total += w
		if total <= 0.0:
			break
		var x := rng.randf() * total
		var idx := 0
		while idx < ws.size() - 1 and x >= ws[idx]:
			x -= ws[idx]
			idx += 1
		out.append(c[idx])
		c.remove_at(idx)
	return out


## 商店（框架第 13 节）。stage: 0 第一商店 Discovery / 1 第二商店 Fixing / 2 第三商店 Finalisation
func roll_shop(stage: int, owned: Array, profile, rng: RandomNumberGenerator, n: int = 3) -> Array:
	var cand := pool(owned, func(r): return r.shop_allowed and r.source != "boss")
	var stage_mul: Dictionary = [
		{"基础": 1.4, "稀有": 1.0, "核心": 0.4},
		{"基础": 0.9, "稀有": 1.2, "核心": 1.0},
		{"基础": 0.5, "稀有": 1.1, "核心": 1.8},
	][clampi(stage, 0, 2)]
	var steer: float = [0.0, STEER, STEER * 0.8][clampi(stage, 0, 2)]
	var wf := func(r):
		var w: float = RARITY_WEIGHT.get(r.rarity, 0.0) * stage_mul.get(r.rarity, 1.0)
		if profile != null:
			w *= 1.0 + steer * profile.affinity(r.tags)
		return w
	return pick(cand, n, wf, rng)


## 精英 / 宝箱藏品箱：普通随机 + 轻微倾向
func roll_chest(owned: Array, profile, rng: RandomNumberGenerator, n: int = 3) -> Array:
	var cand := pool(owned, func(r): return r.source != "boss" and r.rarity in ["基础", "稀有", "核心"])
	var wf := func(r):
		var w: float = RARITY_WEIGHT.get(r.rarity, 0.0)
		if profile != null:
			w *= 1.0 + STEER * 0.5 * profile.affinity(r.tags)
		return w
	return pick(cand, n, wf, rng)


## Boss 奖励（框架第 17 节）
## 第一个 Boss：当前 Build 相关 + 其他 Build + 通用（核心 / 稀有）
## 第二个 Boss：升华藏品三选一（优先相关）
func roll_boss(index: int, owned: Array, profile, rng: RandomNumberGenerator) -> Array:
	if index >= 1:
		var subl := pool(owned, func(r): return r.rarity == "升华")
		var got := pick(subl, 3, func(r): return 1.0 + 2.0 * (profile.affinity(r.tags) if profile != null else 0.0), rng)
		if got.size() < 3:
			got += pick(pool(owned, func(r): return r.rarity == "核心" and not got.has(r)), 3 - got.size(), func(_r): return 1.0, rng)
		return got
	var cand := pool(owned, func(r): return r.rarity in ["核心", "稀有"])
	var main: String = profile.main_lane(0.5) if profile != null else ""
	var out: Array = []
	var related := cand.filter(func(r): return main != "" and main in r.lanes)
	if related.is_empty() and profile != null:
		related = cand.filter(func(r): return profile.affinity(r.tags) > 0.2)
	out += pick(related, 1, func(r): return 2.0 if r.rarity == "核心" else 1.0, rng)
	var other := cand.filter(func(r): return not out.has(r) and not r.lanes.is_empty() and not (main in r.lanes))
	out += pick(other, 1, func(r): return 2.0 if r.rarity == "核心" else 1.0, rng)
	var general := cand.filter(func(r): return not out.has(r) and r.lanes.is_empty())
	out += pick(general, 1, func(_r): return 1.0, rng)
	if out.size() < 3:
		out += pick(cand.filter(func(r): return not out.has(r)), 3 - out.size(), func(_r): return 1.0, rng)
	return out


func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))
