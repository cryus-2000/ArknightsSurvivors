extends "res://scripts/core/theme_mechanic.gd"
## 水月主题机制 · 灯火（docs/147、docs/364 §2）：受击熄灭、熄灭后持续掉血、照亮范围与技力加成。
## 灯火值本身仍存在 g.lamp / g.lamp_cap（三十多处干员 / 藏品 / 事件直接加减，读的地方更多），本步只把「谁来结算」收进来。

const Bal = preload("res://scripts/core/balance.gd")
const Game = preload("res://scripts/game.gd")
var g: Game


func _init(game: Game) -> void:
	g = game


## 灯火熄灭：每秒 3 点「dark」掉血（原 game._update_player）
func on_player_tick(dt: float) -> void:
	if g.lamp <= 0.0:
		g.combat.lose_hp(3.0 * dt, "dark")
		g.hurt_flash = max(g.hurt_flash, 0.05)


## 灯火只在受击时熄灭：基础 + 伤害占最大生命的比例，受「灯火消耗」修正（原 combat.enemy_hit）
func on_player_hit(dmg: float, _src: Dictionary) -> void:
	var lamp_loss: float = (Bal.v("lamp/hit_base", 2.0) + Bal.v("lamp/hit_scale", 18.0) * dmg / g.max_hp) * g.lamp_decay * g.lamp_loss_mult
	var l0: float = g.lamp
	g.lamp = maxf(0.0, g.lamp - lamp_loss)
	g.telemetry.lamp_note("受击", g.lamp - l0)
	if lamp_loss >= 6.0:
		g.vfx.add_text(g.ppos + Vector2(20, -60), "灯火 -%d" % int(lamp_loss), Color(1.0, 0.6, 0.4), 13)


## 灯光照亮范围（游戏判定用，原 game.lamp_r）
func light_radius() -> float:
	return lerpf(110.0, 360.0, g.lamp / 100.0) * g.squad.light_radius_mult()


## 灯火高（≥ 70）技力 ×1.3（原 game._lamp_sp 的灯火部分）
func sp_mult() -> float:
	return 1.3 if g.lamp >= 70.0 else 1.0
