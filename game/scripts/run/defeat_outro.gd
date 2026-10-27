extends RefCounted
## 失败退场演出（docs/62 §3.21c，10-28 用户「干员被击败以后是不是可以加一个退场动画，再跳转到结算」）：
## 倒下过渡（hud.DEATH_T）期间只推进画面——最后一击定格 HIT_FREEZE 秒 + 重击特效，之后特效慢放、再回到原速；
## 队友提亮后化成光尘上升消散（character.gd 按 fade 画），队长播本人倒地条。怪物不动（模拟已停）。
## 不碰模拟与对局随机数：特效只用 vrng，局终数据在进入倒下的第一帧已定（game._process → RunEnd.settle / settlement.tick）
const Game = preload("res://scripts/game.gd")
const HIT_FREEZE := 0.1    # 最后一击定格
const SLOW := 0.25         # 定格后特效慢放倍率
const SLOW_END := 0.45     # 慢放到这里开始回原速
const FADE0 := 0.25        # 队友开始消散
const FADE1 := 1.1         # 队友散尽
const DUST := Color(0.75, 1.35, 1.55)
var g
var _hit := false


func _init(game) -> void:
	g = game


## 队友消散进度（0 = 还在，1 = 散尽）
func fade(age: float) -> float:
	return clampf((age - FADE0) / (FADE1 - FADE0), 0.0, 1.0)


## 特效步长倍率：定格 → 慢放 → 0.3 秒回到原速
func time_scale(age: float) -> float:
	if age < HIT_FREEZE:
		return 0.0
	return lerpf(SLOW, 1.0, clampf((age - SLOW_END) / 0.3, 0.0, 1.0))


## 每渲染帧（game._process）：delta 为真实帧间隔
func step(delta: float) -> void:
	if g.state != Game.S.DEAD:
		_hit = false
		return
	if g.state_age >= Game.HudView.DEATH_T or g.headless_batch:
		return
	if not _hit:
		_hit = true
		_last_hit()
	var sc := time_scale(g.state_age)
	if sc > 0.0:
		g.vfx.update(delta * sc)
	var k := fade(g.state_age)
	if k <= 0.0 or k >= 1.0 or g.fx.size() > 400:
		return
	for o in g.squad.ops:
		if o.is_leader or o.pos == Vector2.INF:
			continue
		for i in 2:
			g.fx.append({"kind": "mote", "pos": o.pos + Vector2(g.vrng.randf_range(-11, 11), g.vrng.randf_range(-38, -2)),
				"vel": Vector2(g.vrng.randf_range(-12, 12), g.vrng.randf_range(-70, -35)), "life": 0.7, "max": 0.7, "col": DUST, "grav": -20.0, "drag": 0.8, "em": false, "sz": 2.0 if i == 0 else 3.0})


## 最后一击加重：红白冲击环 + 光芒 + 火花、低沉重击声、镜头后坐、全屏一闪
func _last_hit() -> void:
	var p: Vector2 = g.ppos + Vector2(0, -16)
	g.fx.append({"kind": "ring", "pos": p, "r": 120.0, "life": 0.45, "max": 0.45, "col": Color(1.7, 0.55, 0.5)})
	g.fx.append({"kind": "rays", "pos": p, "life": 0.6, "max": 0.6, "col": Color(1.6, 0.85, 0.8)})
	g.vfx.sparks(p, Vector2.ZERO, Color(1.6, 0.7, 0.55), 22, 280.0)
	g.world.kick(Vector2.RIGHT.rotated(g.vrng.randf() * TAU), 5, 0.3)
	Sfx.play("hurt_heavy", -1.0, 0.72, 0.0)
	Sfx.play("boom", -7.0, 0.55, 0.0)
