extends RefCounted
## P0 底层的统一入口：game.gd 只需要持有一个 CombatCore。
##   var core := preload("res://scripts/core/combat_core.gd").new()
##   core.stats.value(&"max_hp")
##   core.bus.emit(E.HIT, {...})
##   core.gain_relic("54")
## 设计见 docs/09_p0_architecture.md。

const E = preload("res://scripts/core/events.gd")
const SB = preload("res://scripts/core/stat_block.gd")
const Bus = preload("res://scripts/core/event_bus.gd")
const Mods = preload("res://scripts/core/modifier_system.gd")
const Profile = preload("res://scripts/core/build_profile.gd")
const DB = preload("res://scripts/core/relic_db.gd")
const Defs = preload("res://scripts/core/stat_defs.gd")

## 游戏需要注册的动作（modifier_system 里 do 字段可用的名字）
const GAME_ACTIONS := ["light", "ingots", "heal", "sp", "stun_all", "damage_all", "damage_area", "execute",
	"bonus_current_hp", "scale_hit", "spawn"]

var bus = Bus.new()
var stats = SB.new()
var enemy = SB.new()
var mods
var profile = Profile.new()
var db = DB.new()
var relics: Array = []   # 已拥有藏品 id（String）


func _init() -> void:
	stats.define_all(Defs.PLAYER)
	enemy.define_all(Defs.ENEMY)
	mods = Mods.new(stats, enemy, bus)
	profile.attach(bus)


## 一局结束时调用：事件总线里的闭包会和各模块形成引用环，不清理会泄漏
func dispose() -> void:
	bus.clear()
	mods = null


func load_data() -> int:
	return db.load_files()


func gain_relic(id: String) -> bool:
	var r: Dictionary = db.get_relic(id)
	if r.is_empty() or relics.has(id):
		return false
	relics.append(id)
	mods.apply("relic:" + id, r.effects)
	profile.add_source("relic:" + id, r.tags)
	bus.emit(E.RELIC_GAINED, {"id": id})
	return true


func lose_relic(id: String) -> void:
	if not relics.has(id):
		return
	relics.erase(id)
	mods.remove("relic:" + id)
	profile.remove_source("relic:" + id)


## 技能分支、援护、武器、排异反应、难度等其他来源也走同一条路
func apply_source(owner_id: String, effects: Array, tags: Array = []) -> void:
	mods.apply(owner_id, effects)
	if not tags.is_empty():
		profile.add_source(owner_id, tags)


func remove_source(owner_id: String) -> void:
	mods.remove(owner_id)
	profile.remove_source(owner_id)


func tick(dt: float, light: float, t: float) -> void:
	mods.tick(dt)
	profile.sample(dt, light, t)
	if bus.has_listeners(E.TICK):
		bus.emit(E.TICK, {"dt": dt})


## 检查效果数据：属性名、事件名、动作名是否都存在。返回错误列表（启动时 / 测试时调用）
func validate() -> Array:
	var errs: Array = []
	var known_actions := GAME_ACTIONS + ["temp_stat", "add_stat"]
	for r in db.implemented():
		for ef in r.effects:
			var ty: String = ef.get("type", "stat")
			var where := "藏品 %s %s" % [r.id, r.name]
			match ty:
				"stat":
					if not (stats.has_stat(ef.stat) or enemy.has_stat(ef.stat)):
						errs.append("%s：未知属性 %s" % [where, ef.stat])
				"trigger":
					if not StringName(ef.event) in E.ALL:
						errs.append("%s：未知事件 %s" % [where, ef.event])
					if not ef.do in known_actions:
						errs.append("%s：未知动作 %s" % [where, ef.do])
					var a: Dictionary = ef.get("args", {})
					if a.has("stat") and not (stats.has_stat(a.stat) or enemy.has_stat(a.stat)):
						errs.append("%s：未知属性 %s" % [where, a.stat])
				"spawn", "on_gain":
					if not ef.do in known_actions:
						errs.append("%s：未知动作 %s" % [where, ef.do])
				"status", "rule":
					pass
				_:
					errs.append("%s：未知效果类型 %s" % [where, ty])
		for q in r.requirements:
			if db.get_relic(str(q)).is_empty():
				errs.append("藏品 %s：前置 %s 不存在" % [r.id, q])
	return errs
