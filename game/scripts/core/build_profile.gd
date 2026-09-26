extends RefCounted
## Build Profile（框架第 31、35 节）：实时记录当前玩家的 Build，用于
##   1) 商店 Soft Steering、Boss 奖励三选一（只做轻微倾向，不强制）
##   2) 统计：伤害来源占比、Tag 权重、流派得分、灯火均值、死亡原因
## 通过 attach(bus) 自动监听事件；藏品 / 分支 / 援护变化由游戏调用 add_source()。

const E = preload("res://scripts/core/events.gd")

## 八条流派：由 Tag 权重算流派得分（框架第 7、8 节；docs/35 藏品流派重做）
const LANES := {
	"A": {"name": "前锋·近战", "tags": {"melee": 1.0, "basic_attack": 0.5, "attack_speed": 0.4, "physical": 0.4, "on_dodge": 0.3}},
	"B": {"name": "追击·召唤", "tags": {"follow_up": 1.0, "summon": 0.8, "arts": 0.3, "on_hit": 0.3}},
	"C": {"name": "控制·技能循环", "tags": {"control": 1.0, "skill": 0.8}},
	"D": {"name": "收割·弱点", "tags": {"execute": 1.0, "on_kill": 0.6}},
	"E": {"name": "远程·火力", "tags": {"ranged": 1.0, "arts": 0.3}},
	"F": {"name": "深蓝·低灯火", "tags": {"low_light": 1.0, "curse": 0.4}},
	"G": {"name": "编队·协同", "tags": {"squad": 1.0}},
	"H": {"name": "守护·续航", "tags": {"survival": 1.0, "shield": 0.6, "heal": 0.6}},
}

var tag_w := {}          # tag -> 权重
var sources := {}        # source_id -> {tags, weight}
var relics: Array = []
var branches := {}       # skill -> branch
var allies := {}         # kind -> lv
var dmg_by_src := {}     # 伤害来源 -> 总伤害
var kills_by_src := {}
var dmg_taken_by := {}   # 敌人类型 / 环境 -> 承受伤害
var light_sum := 0.0
var light_time := 0.0
var build_time := {}     # 流派 -> 首次成为主流派的时间（成型时间）
var death_cause := ""


func attach(bus) -> void:
	bus.on(E.DAMAGE_DEALT, _on_dealt, self, -100)
	bus.on(E.ENEMY_KILLED, _on_killed, self, -100)
	bus.on(E.DAMAGE_TAKEN, _on_taken, self, -100)


## 登记一个带 Tag 的来源（藏品、技能分支、援护、武器）
func add_source(id: String, tags: Array, weight: float = 1.0) -> void:
	remove_source(id)
	sources[id] = {"tags": tags, "weight": weight}
	for tg in tags:
		tag_w[tg] = tag_w.get(tg, 0.0) + weight
	if id.begins_with("relic:"):
		relics.append(id.substr(6))


func remove_source(id: String) -> void:
	if not sources.has(id):
		return
	for tg in sources[id].tags:
		tag_w[tg] = tag_w.get(tg, 0.0) - sources[id].weight
		if tag_w[tg] <= 0.0001:
			tag_w.erase(tg)
	sources.erase(id)
	if id.begins_with("relic:"):
		relics.erase(id.substr(6))


func tag_weight(tag: String) -> float:
	return tag_w.get(tag, 0.0)


func top_tags(n: int = 5) -> Array:
	var ks: Array = tag_w.keys()
	ks.sort_custom(func(a, b): return tag_w[a] > tag_w[b])
	return ks.slice(0, n)


func lane_scores() -> Dictionary:
	var out := {}
	for k in LANES:
		var s := 0.0
		for tg in LANES[k].tags:
			s += tag_w.get(tg, 0.0) * LANES[k].tags[tg]
		out[k] = s
	return out


## 当前主流派（得分最高且领先第二名一定比例才算成型）
func main_lane(min_score: float = 3.0) -> String:
	var sc := lane_scores()
	var best := ""
	var bv := 0.0
	var second := 0.0
	for k in sc:
		if sc[k] > bv:
			second = bv
			bv = sc[k]
			best = k
		elif sc[k] > second:
			second = sc[k]
	if bv < min_score or bv < second * 1.2:
		return ""
	return best


## 与一组 Tag 的相关度 0..1（商店 / Boss 奖励倾向用）
func affinity(tags: Array) -> float:
	if tags.is_empty() or tag_w.is_empty():
		return 0.0
	var total := 0.0
	for v in tag_w.values():
		total += v
	var s := 0.0
	for tg in tags:
		s += tag_w.get(tg, 0.0)
	return clampf(s / maxf(total, 1.0) * 2.0, 0.0, 1.0)


## 每帧：灯火均值、成型时间
func sample(dt: float, light: float, t: float) -> void:
	light_sum += light * dt
	light_time += dt
	var ml := main_lane()
	if ml != "" and not build_time.has(ml):
		build_time[ml] = t


func dmg_share() -> Dictionary:
	var total := 0.0
	for v in dmg_by_src.values():
		total += v
	var out := {}
	for k in dmg_by_src:
		out[k] = dmg_by_src[k] / maxf(total, 1.0)
	return out


func snapshot() -> Dictionary:
	return {"tags": tag_w.duplicate(), "top_tags": top_tags(), "lanes": lane_scores(), "main_lane": main_lane(),
		"relics": relics.duplicate(), "branches": branches.duplicate(), "allies": allies.duplicate(),
		"dmg_share": dmg_share(), "kills": kills_by_src.duplicate(), "avg_light": light_sum / maxf(light_time, 0.001),
		"build_time": build_time.duplicate(), "death_cause": death_cause, "dmg_taken_by": dmg_taken_by.duplicate()}


func _on_dealt(ev: Dictionary) -> void:
	var s: String = ev.get("src", "?")
	dmg_by_src[s] = dmg_by_src.get(s, 0.0) + float(ev.get("amount", 0.0))


func _on_killed(ev: Dictionary) -> void:
	var s: String = ev.get("src", "?")
	kills_by_src[s] = kills_by_src.get(s, 0) + 1


func _on_taken(ev: Dictionary) -> void:
	if ev.get("blocked", false):
		return
	var s: String = ev.get("by", "?")
	dmg_taken_by[s] = dmg_taken_by.get(s, 0.0) + float(ev.get("amount", 0.0))
