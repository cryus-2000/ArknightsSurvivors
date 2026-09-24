## 博士（docs/23 §3）：场上唯一的受击体。生命 / 位置 / 移动 / 拾取 / 灯火 / 等级这些通用状态仍由 game.gd 持有（ppos / hp / …），
## 本文件放博士层的专属逻辑：指挥技能（唯一的手动技能）、排异反应、局外成长接入。
extends RefCounted

var g
var def: Dictionary = {}
var rej_count := 0             # 排异反应次数（结局线用）
var rej_log: Array = []        # 每次排异的说明文字


func _init(game) -> void:
	g = game
	var f := FileAccess.open("res://data/doctor.json", FileAccess.READ)
	if f != null:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			def = d


func name() -> String:
	return def.get("name", "博士")


## 唯一的手动技能入口（Space / J）。P1 阶段博士还没有指挥技能：返回 false
func try_manual_skill() -> bool:
	return false


## 排异反应：博士承受，效果落在编队里随机一名能被海嗣化的干员身上（干员实现 apply_rejection）；
## 没有可承受的干员时改为直接削减博士生命上限
func apply_rejection() -> String:
	rej_count += 1
	var cands: Array = []
	for o in g.squad.ops:
		if o.has_method("apply_rejection"):
			cands.append(o)
	var what := ""
	if not cands.is_empty():
		what = cands[g.rng.randi() % cands.size()].apply_rejection()
	else:
		g.stats.add(&"max_hp", "flat", -20.0, "rejection")
		g._sync_stats()
		g.hp = minf(g.hp, g.max_hp)
		what = "生命上限 -20"
	rej_log.append(what)
	return what


## 排异记录（结算 / Tab 面板）：合并各干员的 rej 字典
func rej() -> Dictionary:
	var out: Dictionary = {}
	for o in g.squad.ops:
		if "rej" in o:
			for k in o.rej:
				out[k] = true
	return out
