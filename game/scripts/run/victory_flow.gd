extends RefCounted
## 留出完整 Boss 击败演出。战斗已结束，只推进画面，不再受击/刷怪/发牌。
## 最终 Boss 击破演出（docs/38 §1.8，10-11）：真实时间约 2 秒的慢动作——画面步长 = 真实帧 × time_scale，
## 0.3 秒内 1.0 → 0.15，末 0.4 秒回到 1.0；只缩放画面推进（vfx / 世界视觉 / g.t），模拟 _update 在这里本来就不跑，
## 所以同 seed 对局逐字段不变；无头批跑 / 设置关 / 演练不演（boss_intro.finale_ok），平衡批跑仍然立即结算。
const Game = preload("res://scripts/game.gd")
const D = preload("res://scripts/data.gd")
const DURATION := 1.7
const FIN_DUR := 2.0        # 最终 Boss 击破演出总长（真实秒）
const FIN_IN := 0.3         # 1.0 → FIN_SCALE 的用时
const FIN_OUT := 0.4        # 末尾回到 1.0 的用时
const FIN_SCALE := 0.15
var g: Game
var active := false
var elapsed := 0.0          # 画面时间（缩放后）
var real := 0.0             # 真实时间
var finale := false         # 本次是最终 Boss 击破演出
var recorded := false

func _init(game: Game) -> void:
	g = game

func begin() -> void:
	if active:
		return
	active = true
	elapsed = 0.0
	real = 0.0
	g.hitstop = 0.0
	g.moving = false
	g.pvel = Vector2.ZERO
	g.warns.clear()
	g.ebullets.clear()
	finale = not g.trial.active and g.final_boss != null and g.boss_intro.finale_ok()
	if finale:
		g.boss_intro.on_finale(g.final_boss)
	else:
		g.vfx.show_banner("演练目标击破" if g.trial.active else "深海中的威胁已消散")
	record_win()
	if g.mode == g.Mode.BALANCE and not finale:
		finish()

## 慢动作系数（真实时间 → 画面步长倍率）
func time_scale(rt: float) -> float:
	if not finale:
		return 1.0
	if rt < FIN_IN:
		return lerpf(1.0, FIN_SCALE, smoothstep(0.0, FIN_IN, rt))
	if rt > FIN_DUR - FIN_OUT:
		return lerpf(FIN_SCALE, 1.0, smoothstep(FIN_DUR - FIN_OUT, FIN_DUR, rt))
	return FIN_SCALE

## 每渲染帧：delta 为真实帧间隔；返回这一帧的画面步长（game._process 交给 world.update_visuals）
func step(delta: float) -> float:
	real += delta
	var dt: float = delta * time_scale(real)
	elapsed += dt
	g.t += dt
	g.vfx.update(dt)
	if (real >= FIN_DUR) if finale else (elapsed >= DURATION):
		finish()
	return dt

func finish() -> void:
	active = false
	finale = false
	g.state = g.S.WIN

func record_win() -> void:
	if recorded or g.trial.active:
		return
	recorded = true
	g.endg.on_win()
	if g.mode != g.Mode.BALANCE and g.tier >= Cfg.diff_unlocked and Cfg.diff_unlocked < D.DIFFICULTY_TIERS.size() - 1:
		Cfg.diff_unlocked = g.tier + 1
		Cfg.save()
		g.diff_new = true
	g.telemetry.on_state(g.S.WIN)
