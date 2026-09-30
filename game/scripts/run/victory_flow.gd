extends RefCounted
## 留出完整 Boss 击败演出。战斗已结束，只推进画面，不再受击/刷怪/发牌。
const Game = preload("res://scripts/game.gd")
const D = preload("res://scripts/data.gd")
const DURATION := 1.7
var g: Game
var active := false
var elapsed := 0.0
var recorded := false

func _init(game: Game) -> void:
	g = game

func begin() -> void:
	if active:
		return
	active = true
	elapsed = 0.0
	g.hitstop = 0.0
	g.moving = false
	g.pvel = Vector2.ZERO
	g.warns.clear()
	g.ebullets.clear()
	g.vfx.show_banner("演练目标击破" if g.trial.active else "深海中的威胁已消散")
	record_win()
	if g.balance:
		finish()

func step(dt: float) -> void:
	elapsed += dt
	g.t += dt
	g.vfx.update(dt)
	if elapsed >= DURATION:
		finish()

func finish() -> void:
	active = false
	g.state = g.S.WIN

func record_win() -> void:
	if recorded or g.trial.active:
		return
	recorded = true
	g.endg.on_win()
	if not g.balance and g.tier >= Cfg.diff_unlocked and Cfg.diff_unlocked < D.DIFFICULTY_TIERS.size() - 1:
		Cfg.diff_unlocked = g.tier + 1
		Cfg.save()
		g.diff_new = true
	g.telemetry.on_state(g.S.WIN)
