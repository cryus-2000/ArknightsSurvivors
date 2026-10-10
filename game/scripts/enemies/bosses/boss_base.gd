## Boss 行为脚本基类（docs/55 §6，10-10）：每只 Boss 一个 scripts/enemies/bosses/<type>.gd，继承本类、覆写 step()；
## 多个 type 共用一份脚本时在 boss_ai.gd 的 SCRIPTS 注册表里指到同一个文件（圣徒 iberia / carmen → saint.gd）。
## 状态全部还在敌人字典 e 上（docs/39：敌人用字典），脚本本身无状态，所以同一只 Boss 的多个实例共用一个脚本对象。
## 预警管线（_warn / _update_warns / _warn_resolve）、招式冷却 _cd、远程迫近 _close_in、招式令牌都留在 boss_ai.gd，这里只转发。
extends RefCounted

const D = preload("res://scripts/data.gd")
const Bal = preload("res://scripts/core/balance.gd")

var g  # Game (Node2D)


func _init(game) -> void:
	g = game


## 每帧：boss_ai._boss_ai 跑完公共段（卡点、冲刺计时、假死、骑士追击、接潮共鸣、令牌、招式轮换）后调用。
## ready = 本帧可以出招；mate = 接潮搭档（没有则 null）
func step(_e: Dictionary, _dt: float, _dir: Vector2, _dist: float, _ready: bool, _mate) -> void:
	pass


## 图鉴 / Boss 演练：直接进入二阶段的完整状态（没有二阶段的 Boss 不用覆写）
func setup_preview_phase2(_e: Dictionary) -> void:
	pass


## ---- 转发到 boss_ai.gd（docs/38 §1.17：包装方法放基类，各 Boss 脚本只调基类）
## boss_ai.gd 按 type 运行时 load() 这些脚本，所以这里 preload 它不构成循环
const SKILL_COOLDOWN_SCALE: float = preload("res://scripts/boss_ai.gd").SKILL_COOLDOWN_SCALE


func _warn(e: Dictionary, shape: String, dur: float, d: Dictionary) -> Dictionary:
	return g.bai._warn(e, shape, dur, d)


func _cd(e: Dictionary, key: String, dur: float) -> bool:
	return g.bai._cd(e, key, dur)


func _close_in(e: Dictionary, dir: Vector2, dist: float, key: String, title: String, col: Color) -> float:
	return g.bai._close_in(e, dir, dist, key, title, col)
