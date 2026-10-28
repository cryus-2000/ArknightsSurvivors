extends RefCounted
## 失败退场演出（docs/62 §3.21c，10-28 用户「干员被击败以后是不是可以加一个退场动画，再跳转到结算」）：
## 倒下过渡（hud.DEATH_T）期间只推进画面——最后一击定格 HIT_FREEZE 秒 + 重击特效，之后特效慢放、再回到原速；
## 队友提亮后化成光尘上升消散（character.gd 按 fade 画），队长播本人倒地条。怪物不动（模拟已停）。
## 不碰模拟与对局随机数：特效只用 vrng，局终数据在进入倒下的第一帧已定（game._process → RunEnd.settle / settlement.tick）
## 10-28 用户「被击败的瞬间慢动作，然后屏幕变暗接上结算画面」：定格后整个画面慢放（敌人按自身速度朝倒下处挪、
## 走路帧跟 g.vis_t 走，敌我弹幕沿原方向飘，特效同倍率），慢放结束后 0.4 秒缓到静止；同时整屏逐渐压暗、
## 边缘收暗角（hud.draw_death_transition 读 DIM_T），末尾压到结算底色，结算从暗处入场。
## 这些只改画面用的字段（pos / 弹幕 life / 抛物 t / vis_t），不调模拟步、不取 g.rng；无头批跑不走这里。
const Game = preload("res://scripts/game.gd")
const Bal = preload("res://scripts/core/balance.gd")
const HIT_FREEZE := 0.1    # 最后一击定格
## 旋钮（data/balance.json 的 outro/*，没写用缺省）：慢放倍率 / 慢放时长（秒，定格之后起算）/ 压暗时长（秒，从倒下起算）
var SLOW: float = Bal.v("outro/slow", 0.25)
var SLOW_T: float = Bal.v("outro/slow_t", 1.2)
var DIM_T: float = Bal.v("outro/dim_t", 1.6)
const SETTLE := 0.4        # 慢放结束后缓到静止
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


## 画面步长倍率：定格 → 慢放 SLOW_T 秒 → SETTLE 秒缓到静止（之后画面已压暗，接结算）
func time_scale(age: float) -> float:
	if age < HIT_FREEZE:
		return 0.0
	return SLOW * (1.0 - clampf((age - HIT_FREEZE - SLOW_T) / SETTLE, 0.0, 1.0))


## 每渲染帧（game._process）：delta 为真实帧间隔
func step(delta: float) -> void:
	if g.state != Game.S.DEAD:
		_hit = false
		g.vis_t = 0.0
		return
	if g.state_age >= Game.HudView.DEATH_T or g.headless_batch:
		return
	if not _hit:
		_hit = true
		_last_hit()
	var sc := time_scale(g.state_age)
	if sc > 0.0:
		g.vfx.update(delta * sc)
		_drift(delta * sc)
	var k := fade(g.state_age)
	if k <= 0.0 or k >= 1.0 or g.fx.size() > 400:
		return
	for o in g.squad.ops:
		if o.is_leader or o.pos == Vector2.INF:
			continue
		for i in 2:
			g.fx.append({"kind": "mote", "pos": o.pos + Vector2(g.vrng.randf_range(-11, 11), g.vrng.randf_range(-38, -2)),
				"vel": Vector2(g.vrng.randf_range(-12, 12), g.vrng.randf_range(-70, -35)), "life": 0.7, "max": 0.7, "col": DUST, "grav": -20.0, "drag": 0.8, "em": false, "sz": 2.0 if i == 0 else 3.0})


## 慢放中的画面推进：敌人朝倒下处挪（停在贴身前、晕眩 / Boss 不挪），弹幕沿原方向飘、到寿命就不画，抛物沿弧线走到落点为止
func _drift(dt: float) -> void:
	g.vis_t += dt
	for e in g.enemies:
		if e.dead or e.boss or e.stun > 0.0 or e.get("friendly", false):
			continue
		var to: Vector2 = g.ppos - e.pos
		var d := to.length()
		var stop: float = float(e.r) + 14.0
		if d > stop:
			e.pos += to / d * minf(d - stop, float(e.spd) * dt)
	for b in g.ebullets:
		if b.life > 0.0:
			b.pos += b.vel * dt
			b.life -= dt
	for b in g.bullets:
		if b.get("vel") is Vector2 and float(b.get("life", 1.0)) > 0.0:
			b.pos += b.vel * dt
			if b.has("life"):
				b.life -= dt
	for l in g.lobs:
		l.t = minf(float(l.t) + dt, float(l.dur) - 0.001)


## 最后一击加重：红白冲击环 + 光芒 + 火花、低沉重击声、镜头后坐、全屏一闪
func _last_hit() -> void:
	var p: Vector2 = g.ppos + Vector2(0, -16)
	g.fx.append({"kind": "ring", "pos": p, "r": 120.0, "life": 0.45, "max": 0.45, "col": Color(1.7, 0.55, 0.5)})
	g.fx.append({"kind": "rays", "pos": p, "life": 0.6, "max": 0.6, "col": Color(1.6, 0.85, 0.8)})
	g.vfx.sparks(p, Vector2.ZERO, Color(1.6, 0.7, 0.55), 22, 280.0)
	g.world.kick(Vector2.RIGHT.rotated(g.vrng.randf() * TAU), 5, 0.3)
	Sfx.play("hurt_heavy", -1.0, 0.72, 0.0)
	Sfx.play("boom", -7.0, 0.55, 0.0)
