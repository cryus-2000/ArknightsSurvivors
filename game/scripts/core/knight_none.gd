extends RefCounted
## 空骑士（docs/391 T-R1、docs/369 §5）：主题清单 modules 段没有 knight 时 ThemePack.make_module 用这个。
## 核心有几十处直接读 g.knight（alive / submerged / pos …，结局二同伴线），这里只给同名成员和空函数：骑士永远不在队、不画、不出现。
## 字段 / 函数与 themes/deep_sea/mod/knight.gd 的公开部分一一对应；那边加了核心要读的新成员，这里要同步补。

var g
var alive := false
var pos := Vector2.ZERO
var hp := 0.0
var maxhp := 1.0
var state := "idle"
var st := 0.0
var submerged := false
var vanish_pos := Vector2.INF
var fallen := false


func _init(game) -> void:
	g = game


func spawn() -> void:
	pass


func leave() -> void:
	pass


func leaving() -> bool:
	return false


func die() -> void:
	pass


func tick_final() -> void:
	pass


func walk_to_center(_target: Vector2) -> void:
	pass


## 10:00 骑士 Boss 的出现位置：没有骑士的主题不会刷骑士 Boss；万一刷了就在玩家处
func take_over() -> Vector2:
	return g.ppos


func update(_dt: float) -> void:
	pass


func heal(_v: float) -> void:
	pass


func draw(_mask: CanvasItem = null) -> void:
	pass


func draw_hud(_hud: CanvasItem, _c: Vector2) -> void:
	pass
