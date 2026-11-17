extends RefCounted
## 主题机制接口（docs/357 §6.2、docs/364）：灯火、溟痕、灯标、黑潮缩圈这类「主题玩法」各写一个子类，放在主题包里
## （res://themes/<id>/mech/），主题清单 theme.json 的 mechanics 段按顺序列出要用哪些；ThemePack.make_mechanics 实例化，
## 挂在 game.mechs（数组，清单顺序）/ game.mech(id)。核心循环只在固定的挂钩点按清单顺序逐个调用，不认具体机制。
##
## 挂钩点（调用位置与改造前写死的调用逐帧同一处，同种子玩法不变——tools/theme_parity.py）：
##   on_player_tick(dt)      game._update_player：队长回复之后、护盾之前（灯火熄灭掉血、黑潮缩圈）
##   on_player_hit(dmg, src) combat.enemy_hit：控制 / 凋亡结算之后、侵蚀之前（受击掉灯火）
##   on_status_tick(dt)      enemies.update_status：侵蚀之后（溟痕：减速 / 掉血 / 神经损伤）；返回 true = 已经结算了
##                           巢涌光环与神经损伤，核心不再做缺省结算
##   on_spawn_tick(dt)       spawner.update：补给箱之后、商人之前（自然溟痕刷新）
##   on_world_tick(dt)       game 杂项段：结局箱之后、骑士之前（引航灯标）
## 子类自己声明 `var g: Game` 与 `_init(game)`（带类型的 g 让 := 推断照常生效）；没实现的挂钩是空操作。
## 约束：挂钩里抽随机数的次数、顺序必须和搬家前完全一样；纯画面的东西照旧走 g.vrng。

var id := ""


func on_player_tick(_dt: float) -> void:
	pass


func on_player_hit(_dmg: float, _src: Dictionary) -> void:
	pass


func on_status_tick(_dt: float) -> bool:
	return false


func on_spawn_tick(_dt: float) -> void:
	pass


func on_world_tick(_dt: float) -> void:
	pass
