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
const OUT_DUR := 1.1        # 慢动作之后的收尾（docs/62 §3.21c）：暖金光环扩开、四周压暗、「探索完成」浮出，再进结算
const UI = preload("res://scripts/ui.gd")
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
	g.lvup_delay -= dt   # 原在 vfx.update 里（docs/101 B3），顺序不变
	if (real >= FIN_DUR + OUT_DUR) if finale else (elapsed >= DURATION):
		finish()
	return dt

## 任意按键 / 点击 / 触屏跳过（game._input）：直接进结算
func skip() -> void:
	if active:
		g.boss_intro.finale = {}
		finish()

## 收尾画面（hud 尾层调）：慢动作结束后 OUT_DUR 秒
func draw_hud(vs: Vector2) -> void:
	if not active or not finale or real < FIN_DUR:
		return
	var k: float = clampf((real - FIN_DUR) / OUT_DUR, 0.0, 1.0)
	var e: float = 1.0 - pow(1.0 - k, 3.0)
	var ci: CanvasItem = g.hud
	ci.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.02, 0.03, 0.05, 0.5 * e))
	# 暖金光环：从队长处扩开、渐隐
	var c: Vector2 = g.hud_ct() * g.ppos
	var r: float = lerpf(30.0, maxf(vs.x, vs.y) * 0.75, e)
	ci.draw_arc(c, r, 0.0, TAU, 96, Color(UI.GOLD, 0.7 * (1.0 - k)), 3.0)
	ci.draw_arc(c, r * 0.82, 0.0, TAU, 96, Color(UI.GOLD, 0.3 * (1.0 - k)), 1.5)
	var ta: float = clampf((real - FIN_DUR - 0.25) / 0.45, 0.0, 1.0)
	if ta > 0.0:
		var cy: float = vs.y * 0.42
		var lw: float = 260.0 * (1.0 - pow(1.0 - ta, 3.0))
		ci.draw_rect(Rect2(vs.x / 2.0 - lw, cy + 14, lw * 2.0, 1), Color(UI.GOLD, 0.85 * ta))
		UI.text(ci, g.font, Vector2(0, cy - 4.0 + 8.0 * (1.0 - ta)), "探索完成", 40, Color(1, 1, 1, ta), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 6)
		var en := "OPERATION  COMPLETE"
		UI.en(ci, g.font, Vector2(vs.x / 2.0 - g.font.get_string_size(en, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x / 2.0 - 20.0, cy + 40), en, 13, Color(UI.GOLD, ta), 4.0)

func finish() -> void:
	active = false
	finale = false
	g.state = g.S.WIN

func record_win() -> void:
	if recorded or g.trial.active:
		return
	recorded = true
	g.endg.on_win()
	# 三档难度（D.DIFF_PRESETS）：通关第 i 档解锁第 i+1 档；各档最佳成绩记在 Cfg.diff_best（docs/109 §15）
	if g.mode != g.Mode.BALANCE and g.preset >= 0:
		Cfg.note_diff_best(g.preset, true, g.t)
	if g.mode != g.Mode.BALANCE and g.preset >= Cfg.diff_unlocked and Cfg.diff_unlocked < D.DIFF_PRESETS.size() - 1:
		Cfg.diff_unlocked = g.preset + 1
		Cfg.save()
		g.diff_new = true
	g.telemetry.on_state(g.S.WIN)
