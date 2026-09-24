## 可操作角色的基类：定义 game.gd 调用的接口，默认实现为空。
## 每个角色 = data/characters/<id>.json（名字、贴图集、技能表、成长池、精英化树）+ scripts/characters/<id>.gd（行为）。
## 通用玩家状态（位置 / 生命 / 等级 / 成长计数 / 技能等级）由 game.gd 持有，角色通过 g 读写。
extends RefCounted

var g                      # Game (Node2D)
var def: Dictionary = {}   # 角色定义（JSON）
var id := ""


func _init(game, def_: Dictionary) -> void:
	g = game
	def = def_
	id = def.get("id", "")


static func list_ids() -> Array:
	var out: Array = []
	var d := DirAccess.open("res://data/characters")
	if d != null:
		for f in d.get_files():
			if f.ends_with(".json"):
				out.append(f.get_basename())
	return out


static func load_def(cid: String) -> Dictionary:
	var f := FileAccess.open("res://data/characters/%s.json" % cid, FileAccess.READ)
	if f == null:
		push_error("character def missing: " + cid)
		return {"id": cid}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {"id": cid}


## 按 id 实例化角色（脚本路径来自定义里的 script 字段，默认 scripts/characters/<id>.gd）
static func create(game, cid: String) -> RefCounted:
	var d := load_def(cid)
	var path: String = d.get("script", "res://scripts/characters/%s.gd" % cid)
	var scr = load(path)
	if scr == null:
		push_error("character script missing: " + path)
		return null
	return scr.new(game, d)


# ---------------------------------------------------------------- 每帧

## 普攻节奏、技能计时、专属实体（在敌人更新之后、援护之前调用）
func update(_dt: float) -> void:
	pass


# ---------------------------------------------------------------- 数值

## 角色 JSON 的 base 段：专属基础数值（如伞击伤害、挥砍半径），缺项用默认
func base(key: String, default: float) -> float:
	return float(def.get("base", {}).get(key, default))


## 角色专属属性定义（stat 名 -> {base, min, max, name}），带角色前缀
func stat_defs() -> Dictionary:
	return {}


## 属性块有变化时由 game.gd 调用：把 g.stats 里的专属属性同步到角色缓存变量
func sync_stats(_st) -> void:
	pass


## 普攻半径（自动索敌 / 机器人走位用）
func _swing_radius() -> float:
	return 90.0


## 伤害通用倍率（天赋等）
func _dmg_bonus() -> float:
	return g.dmg_mult


# ---------------------------------------------------------------- 成长 / 技能 / 精英化

## 成长项生效
func _apply_growth(_gid: String) -> void:
	pass


## 升级卡上的数值预览
func _growth_preview(_gid: String) -> String:
	return ""


## 技能发动演出（技能自动触发时由角色内部调用）
func _skill_cast(_sid: String) -> void:
	pass


## 精英化一：可选路线 id 列表
func evo_paths() -> Array:
	return def.get("evo", {}).get("paths", [])


## 精英化二：某路线下的质变 id 列表
func evo_mutations(path: String) -> Array:
	return def.get("evo", {}).get("mutations", {}).get(path, [])


# ---------------------------------------------------------------- 绘制（世界坐标，用 g.draw_*）

## 角色脚下的技能表现
func _draw_skill_floor() -> void:
	pass


## 角色身上的技能表现
func _draw_skill_over() -> void:
	pass


## 专属实体：地面层（触手桩 / 符阵等）
func draw_entities_floor() -> void:
	pass


## 专属实体：角色之上（巨触等）
func draw_entities_over() -> void:
	pass
