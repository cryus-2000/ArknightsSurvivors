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
##   on_spawn_tick()         spawner._horde_tail_rest：补给箱之后、商人之前（自然溟痕刷新）
##   on_world_tick(dt)       game 杂项段：结局箱之后、骑士之前（引航灯标）
##   on_arena_freeze(fresh)  run/arena.gd 最终 Boss 场地冻结末尾（缩圈重置阶段、溟痕清掉场地里的）
##   draw_ground(w)          render/world 溟痕层之后（萨米国度 / Boss 地面件的占位画法；w = world 渲染器，画到 w.g.wcv）
## 机器人挂钩（docs/364 §6；批跑的机器人按主题机制走位，不认具体机制）：
##   bot_return_dir(p, margin) -> Vector2  手残机器人：要不要先往回走（ZERO = 不用）
##   bot_score(q, s) -> float              高手：候选落点打分，传入当前分、返回改后的分（照原来的加减顺序做，浮点结果不变）
##   bot_goal(bot, p) -> Vector2           高手：目标方向（INF = 没意见；可写 bot.beacon_hold / beacon_w）
##   bot_outside_dir(p) -> Vector2         高手 / master 冲刺：在边界外时指回去的方向（ZERO = 在界内）
##   bot_land_bad(land, p) -> bool         高手 / master 冲刺：落点不可取
##   bot_pull(pull) -> Vector2             普通机器人：改拉力（缺省原样返回）
##   bot_steer(at, mv) -> Vector2          普通机器人：拉力合成后改移动向量（at = autotest 实例，存计时状态）
## 子类自己声明 `var g: Game` 与 `_init(game)`（带类型的 g 让 := 推断照常生效）；没实现的挂钩是空操作。
## 约束：挂钩里抽随机数的次数、顺序必须和搬家前完全一样；纯画面的东西照旧走 g.vrng。

var id := ""


func on_player_tick(_dt: float) -> void:
	pass


func on_player_hit(_dmg: float, _src: Dictionary) -> void:
	pass


func on_status_tick(_dt: float) -> bool:
	return false


func on_spawn_tick() -> void:
	pass


func on_world_tick(_dt: float) -> void:
	pass


## 最终 Boss 场地冻结那一刻（run/arena.gd freeze 末尾；fresh = 冻结前圈还没开始）
func on_arena_freeze(_fresh: bool) -> void:
	pass


func draw_ground(_w) -> void:
	pass


func bot_return_dir(_p: Vector2, _margin: float) -> Vector2:
	return Vector2.ZERO


func bot_score(_q: Vector2, s: float) -> float:
	return s


func bot_goal(_bot, _p: Vector2) -> Vector2:
	return Vector2.INF


func bot_outside_dir(_p: Vector2) -> Vector2:
	return Vector2.ZERO


func bot_land_bad(_land: Vector2, _p: Vector2) -> bool:
	return false


func bot_pull(pull: Vector2) -> Vector2:
	return pull


func bot_steer(_at, mv: Vector2) -> Vector2:
	return mv
