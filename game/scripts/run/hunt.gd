extends RefCounted
## 「围猎」强制交战（2026-09-27 用户选定：设计稿 b 的机制 + 海嗣包装 + 方案 ① 真挡人）：
## 约 1:30 以主控为圆心，一圈现有海嗣（凿石者 / 骨海漂流体，原地不动、只有接触伤害）合拢成半径 300 的包围圈；
## 主控从里往外走时，那个方位的海嗣还活着就被夹回圈内（冲刺也一样），打死它就成了缺口；20 秒后整圈散去。
## 奖励：从缺口突围 → 补给（回复 20% 最大生命 + 灯火 20）；圈内的海嗣全部肃清 → 一圈经验结晶。没有额外惩罚。
## 防秒杀：圈上海嗣每 0.8 秒最多接触一次、每次最大生命的 4%；所有围猎敌人单次掉血 ≤ 最大生命 12%（e.hit_cap，前期伤害旋钮之后）；
## 圈内小怪是骨海漂流体，刷在圈里、离主控 ≥ 150。
## 旋钮在 balance.json hunt 段（缺省值见各处 Bal.v）；hunt/enabled = 0 关闭。

const UI = preload("res://scripts/ui.gd")
const Bal = preload("res://scripts/core/balance.gd")

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game

var state := 0               # 0 未开始 / 1 已预告 / 2 进行中 / 3 结束
var start_at := 0.0          # 实际开始时刻（场上敌人太多时顺延）
var c := Vector2.ZERO        # 圆心
var ring: Array = []         # 圈上的海嗣（下标 = 方位序号）
var anchors: Array = []      # 各自钉住的位置
var inner: Array = []        # 圈内刷出的小怪
var inside := true           # 主控还在圈内（出圈后不再夹）
var broke := false           # 已突围
var cleared := false         # 已肃清
var touch_t := 0.0           # 接触伤害间隔


func _init(game: Game) -> void:
	g = game
	start_at = Bal.v("hunt/at", 90.0)


func radius() -> float:
	return Bal.v("hunt/radius", 300.0)


func active() -> bool:
	return state == 2


func update(dt: float) -> void:
	if Bal.v("hunt/enabled", 1.0) <= 0.0 or state == 3 or g.demo_op != "":
		return
	match state:
		0:
			if g.t >= start_at - 3.0:
				# 场上敌人太多（刚过的大群没清完）就顺延 10 秒，最多顺延到 hunt/latest
				if g.enemies.size() > int(Bal.v("hunt/max_enemies", 150.0)) and start_at + 10.0 <= Bal.v("hunt/latest", 110.0):
					start_at += 10.0
					return
				state = 1
				g.vfx.show_banner("围猎 —— 海嗣合拢了包围，撕开一道缺口！")
				Sfx.play("roar", 0.0, 0.6, 0.0)
		1:
			if g.t >= start_at:
				_begin()
		2:
			_tick(dt)


func _log(what: String) -> void:
	if g.autotest:
		print("HUNT %s t=%.1f ring_dead=%d/%d inner_dead=%d/%d" % [what, g.t, ring.filter(func(e): return e.dead).size(), ring.size(), inner.filter(func(e): return e.dead).size(), inner.size()])


func _begin() -> void:
	state = 2
	c = g.ppos
	var n := int(Bal.v("hunt/n", 18.0))
	var r := radius()
	for i in n:
		var ang := TAU * i / n
		var p := c + Vector2.from_angle(ang) * r
		var e: Dictionary = g.spawner.spawn_enemy("stone" if i % 2 == 0 else "bone", p)
		e.ai = "static"
		e.enc = true
		e.hit_cap = Bal.v("hunt/hit_cap", 0.12)   # 单次掉血上限（最大生命比例，combat.enemy_hit 读）
		e.fx = -1.0 if cos(ang) > 0.0 else 1.0   # 面朝圆心
		# 生命统一按凿石者算再乘 hunt/ring_hp：全队集火约 3–5 秒打穿一个
		e.hp = 26.0 * g.combat.enemy_hp_time_mult() * float(g.dmod.enemy_hp) * g.enemy_hp_mult * Bal.v("hunt/ring_hp", 5.0)
		e.maxhp = e.hp
		ring.append(e)
		anchors.append(p)
	_spawn_inner()
	g.fx.append({"kind": "ring", "pos": c, "r": r, "life": 0.8, "max": 0.8, "col": Color(0.75, 0.5, 1.0)})
	g.vfx.shake_screen(0.5)
	_log("begin")


## 圈内小怪：开始时与 10 秒后各一波
func _spawn_inner() -> void:
	var k := int(Bal.v("hunt/inner", 12.0))
	var r := radius()
	for j in k:
		var p := c + Vector2.from_angle(g.rng.randf() * TAU) * g.rng.randf_range(150.0, r - 40.0)
		var e: Dictionary = g.spawner.spawn_enemy("bone", p)
		e.enc = true
		e.hit_cap = Bal.v("hunt/hit_cap", 0.12)
		inner.append(e)


func _tick(dt: float) -> void:
	var el := g.t - start_at
	if el >= 10.0 and el - dt < 10.0:
		_spawn_inner()
	# 圈上的海嗣钉在原位（击退、牵引都不动它们）
	for i in ring.size():
		if not ring[i].dead:
			ring[i].pos = anchors[i]
			ring[i].kb = Vector2.ZERO
	# 接触伤害：贴着活着的圈上海嗣，每 0.8 秒最多一次、每次最大生命的 4%
	touch_t = maxf(0.0, touch_t - dt)
	if touch_t <= 0.0 and g.invuln <= 0.0 and g.state == g.S.PLAY:
		for e in ring:
			if not e.dead and e.pos.distance_to(g.ppos) < e.r + 16.0:
				touch_t = 0.8
				g.dmg_src = "hunt_ring"
				g.in_type = ["近战", "物理"]
				g.combat.enemy_hit(g.max_hp * Bal.v("hunt/touch_pct", 0.04), e)
				break
	# 突围：从缺口走出圈外
	var d := g.ppos.distance_to(c)
	if inside and d > radius() + 12.0:
		inside = false
		if not broke:
			broke = true
			g.combat.heal(g.max_hp * 0.2, "事件")
			g.lamp = minf(g.lamp_cap, g.lamp + 20.0)
			g.vfx.show_banner("突围成功 —— 获得补给")
			_log("broke")
			g.fx.append({"kind": "ring", "pos": g.ppos, "r": 90.0, "life": 0.5, "max": 0.5, "col": Color(0.5, 1.0, 0.65)})
			Sfx.play("relic", -4.0, 1.4, 0.0)
	elif not inside and d < radius() - 40.0:
		inside = true
	# 肃清：圈上与圈内的海嗣全部倒下（第二波刷出之后才算）
	if not cleared and el >= 10.0 and ring.all(func(e): return e.dead) and inner.all(func(e): return e.dead):
		cleared = true
		_xp_burst()
		g.vfx.show_banner("围猎者尽数肃清 —— 获得经验")
		_log("cleared")
	if el >= Bal.v("hunt/dur", 20.0):
		_end()


func _xp_burst() -> void:
	var total: float = g.xp_need * Bal.v("hunt/xp_frac", 0.5)
	for j in 10:
		g.pickups.drop(g.ppos + Vector2.from_angle(TAU * j / 10.0) * 40.0, "xp", total / 10.0)


func _end() -> void:
	_log("end")
	state = 3
	for e in ring + inner:
		if not e.dead:
			e.dead = true   # 散去：不走 kill，不掉落
			g.vfx.sparks(e.pos, Vector2.UP, Color(0.75, 0.5, 1.0), 4, 90.0)
	if not broke and not cleared:
		g.vfx.show_banner("海嗣散入深处 —— 围猎结束")


## 主控移动后调用：从圈内往外走、那个方位的海嗣还活着 → 夹回圈内（冲刺也一样）
func clamp_player() -> void:
	if state != 2 or not inside:
		return
	var r := radius() - 20.0
	var v: Vector2 = g.ppos - c
	if v.length() <= r:
		return
	var n := ring.size()
	var idx := posmod(roundi(v.angle() / (TAU / n)), n)
	if ring[idx].dead:
		return   # 缺口
	g.ppos = c + v.normalized() * r
