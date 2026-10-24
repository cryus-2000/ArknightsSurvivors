extends RefCounted
## 「围猎」强制交战（2026-09-27 用户选定：设计稿 b 的机制 + 海嗣包装 + 方案 ① 真挡人；10-24 改「从屏幕外压过来」）：
## 约 1:30 在屏幕外（约 1.3 倍屏幕半径）刷出一整圈现有海嗣（凿石者 / 骨海漂流体，原地不动、只有接触伤害），不画凭空出现的光圈，
## 只有一条横幅 + 一声音效；整圈 4–6 秒（hunt/approach，缺省 5）同速往队长收，收到半径 260 就停住钉住，之后照旧规则：
## 主控从里往外走时，那个方位的海嗣还活着就被夹回圈内（冲刺也一样），打死它就成了缺口；停住后 20 秒整圈散去。
## 合拢途中可以迎着一侧打出去：圈心从出生点逐渐挪到主控身上，往一侧走会提前碰到那一侧；打穿一只、从缺口走出圈外算提前突围，照给补给，
## 突围（含合拢途中提前冲出）之后包围圈立即结束：圈上海嗣就地散去，圈内小怪变回普通敌人，圈体 / 夹回 / 地面调子都停（10-24 用户）。
## 奖励：从缺口突围 → 补给（回复 20% 最大生命 + 灯火 20）；圈内的海嗣全部肃清 → 一圈经验结晶。没有额外惩罚。
## 防秒杀：圈上海嗣每 0.8 秒最多接触一次、每次最大生命的 4%；所有围猎敌人单次掉血 ≤ 最大生命 12%（e.hit_cap，前期伤害旋钮之后）；
## 圈内小怪是骨海漂流体，停住时刷在圈里、离主控 ≥ 150。
## 旋钮在 balance.json hunt 段（缺省值见各处 Bal.v）；hunt/enabled = 0 关闭。

const UI = preload("res://scripts/ui.gd")
const Bal = preload("res://scripts/core/balance.gd")

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game

var state := 0               # 0 未开始 / 2 进行中（合拢 + 钉住）/ 3 结束（1 预告已取消，保留编号）
var start_at := 0.0          # 实际开始时刻（场上敌人太多时顺延）；这一刻整圈在屏幕外刷出
var settle_at := 0.0         # 合拢完成（停住）时刻 = start_at + 合拢时长；散去计时、第二波圈内小怪从这里算
var settled := false         # 已收到最终半径并钉住
var c := Vector2.ZERO        # 当前圆心（合拢时从出生点逐渐挪向主控，钉住后固定）
var c0 := Vector2.ZERO       # 出生时的圆心
var spawn_r := 0.0           # 出生半径
var cur_r := 0.0             # 当前半径
var frozen := false          # 主控已冲出圈外：圈心不再跟着主控
var ring: Array = []         # 圈上的海嗣（下标 = 方位序号）
var anchors: Array = []      # 各自当前位置（合拢中每帧更新，钉住后固定）
var inner: Array = []        # 圈内刷出的小怪
var inside := true           # 主控还在圈内（出圈后不再夹）
var broke := false           # 已突围
var cleared := false         # 已肃清
var touch_t := 0.0           # 接触伤害间隔


func _init(game: Game) -> void:
	g = game
	start_at = Bal.v("hunt/at", 90.0)


## 钉住后的圈半径（合拢的终点）
func radius() -> float:
	return Bal.v("hunt/radius", 260.0)


func active() -> bool:
	return state == 2


## 合拢时长（秒）
func approach_t() -> float:
	return Bal.v("hunt/approach", 5.0)


## 画面用（render/world.gd 地面调子、screens/hud_banners.gd 圈体）：钉住之后的圈心 / 半径 / 不透明度；
## 合拢途中不画圈（圈体就是那一圈海嗣本身，从屏幕外压过来）。进行中最后 3 秒渐隐。只读、只用 g.t，不改对局；其余时候返回空字典
func vis() -> Dictionary:
	if state != 2 or not settled:
		return {}
	var dur: float = Bal.v("hunt/dur", 20.0) * float(g.dmod.get("hunt_dur", 1.0))
	var alpha := clampf((dur - (g.t - settle_at)) / 3.0, 0.0, 1.0)
	return {"c": c, "r": cur_r, "alpha": alpha, "tick": 0.0, "closing": false}


func update(dt: float) -> void:
	if Bal.v("hunt/enabled", 1.0) <= 0.0 or state == 3 or g.demo_op != "":
		return
	match state:
		0:
			if g.t >= start_at:
				# 场上敌人太多（刚过的大群没清完）就顺延 10 秒，最多顺延到 hunt/latest
				if g.enemies.size() > int(Bal.v("hunt/max_enemies", 150.0)) and start_at + 10.0 <= Bal.v("hunt/latest", 110.0):
					start_at += 10.0
					return
				_begin()
		2:
			_tick(dt)


func _log(what: String) -> void:
	if g.mode != g.Mode.PLAY:
		print("HUNT %s t=%.1f ring_dead=%d/%d inner_dead=%d/%d" % [what, g.t, ring.filter(func(e): return e.dead).size(), ring.size(), inner.filter(func(e): return e.dead).size(), inner.size()])


## 出生半径：画面对角线一半的 1.3 倍（hunt/spawn_mul），夹在 [700, 1250]——比「离主控 1300 外的静止敌人被清掉」（enemies.gd）小，保证整圈在屏幕外
func _spawn_radius() -> float:
	var vs: Vector2 = g.get_viewport_rect().size
	var world: Vector2 = g.get_viewport().get_canvas_transform().affine_inverse().basis_xform(vs)
	return clampf(world.length() * 0.5 * Bal.v("hunt/spawn_mul", 1.3), 700.0, 1250.0)


func _begin() -> void:
	state = 2
	c0 = g.ppos
	c = c0
	spawn_r = _spawn_radius()
	cur_r = spawn_r
	var n := int(Bal.v("hunt/n", 18.0))
	for i in n:
		var ang := TAU * i / n
		var p := c + Vector2.from_angle(ang) * spawn_r
		var e: Dictionary = g.spawner.spawn_enemy("stone" if i % 2 == 0 else "bone", p)
		e.ai = "static"
		e.enc = true
		e.hit_cap = Bal.v("hunt/hit_cap", 0.12)   # 单次掉血上限（最大生命比例，combat.enemy_hit 读）
		e.fx = -1.0 if cos(ang) > 0.0 else 1.0   # 面朝圆心
		# 生命统一按凿石者算再乘 hunt/ring_hp：全队集火约 3–5 秒打穿一个
		e.hp = 26.0 * g.combat.enemy_hp_time_mult() * float(g.dmod.enemy_hp) * g.enemy_hp_mult * Bal.v("hunt/ring_hp", 5.0) * float(g.dmod.get("hunt_ring_hp", 1.0))
		e.maxhp = e.hp
		ring.append(e)
		anchors.append(p)
	settle_at = g.t + approach_t()
	g.vfx.show_banner("围猎 —— 海嗣从四面压了过来，从缺口突围！")
	Sfx.play("hunt_warn", -2.0, 1.0, 0.0)
	_log("begin")


## 圈内小怪：钉住时与 10 秒后各一波
func _spawn_inner() -> void:
	var k := int(Bal.v("hunt/inner", 12.0))
	var r := radius()
	for j in k:
		var p := c + Vector2.from_angle(g.rng.randf() * TAU) * g.rng.randf_range(150.0, r - 40.0)
		var e: Dictionary = g.spawner.spawn_enemy("bone", p)
		e.enc = true
		e.hit_cap = Bal.v("hunt/hit_cap", 0.12)
		inner.append(e)


## 合拢：整圈同速（线性）从出生半径收到 radius()；圈心从出生点逐渐（平方）挪到主控身上，这样途中往一侧走会提前碰到那一侧；
## 到点后钉住，刷第一波圈内小怪
func _approach(dt: float) -> void:
	var k := clampf((g.t - start_at) / maxf(0.1, approach_t()), 0.0, 1.0)
	cur_r = lerpf(spawn_r, radius(), k)
	if not frozen:
		c = c0.lerp(g.ppos, k * k)
	var n := ring.size()
	for i in n:
		var p := c + Vector2.from_angle(TAU * i / n) * cur_r
		anchors[i] = p
		if not ring[i].dead:
			ring[i].pos = p
			ring[i].kb = Vector2.ZERO
	if k >= 1.0:
		settled = true
		settle_at = g.t
		_spawn_inner()
		g.vfx.shake_screen(0.3)
		_log("settled")


func _tick(dt: float) -> void:
	if not settled:
		_approach(dt)
	else:
		# 钉住后：圈上的海嗣钉在原位（击退、牵引都不动它们）
		for i in ring.size():
			if not ring[i].dead:
				ring[i].pos = anchors[i]
				ring[i].kb = Vector2.ZERO
	var el := g.t - settle_at   # 钉住后的时间（没钉住前为负）
	if settled and el >= 10.0 and el - dt < 10.0:
		_spawn_inner()
	# 接触伤害：贴着活着的圈上海嗣，每 0.8 秒最多一次、每次最大生命的 4%
	touch_t = maxf(0.0, touch_t - dt)
	if touch_t <= 0.0 and g.invuln <= 0.0 and g.state == g.S.PLAY:
		for e in ring:
			if not e.dead and e.pos.distance_to(g.ppos) < e.r + 16.0:
				touch_t = 0.8
				g.combat.enemy_hit(g.max_hp * Bal.v("hunt/touch_pct", 0.04), e, false, false, ["近战", "物理"], "hunt_ring")
				break
	# 突围：从缺口走出圈外（合拢途中冲出去也算提前突围）
	var d := g.ppos.distance_to(c)
	if inside and d > cur_r + 12.0:
		inside = false
		frozen = true   # 人已经在圈外：圈心不再跟着主控
		if not broke:
			broke = true
			g.combat.heal(g.max_hp * 0.2, "事件")
			g.lamp = minf(g.lamp_cap, g.lamp + 20.0)
			g.vfx.show_banner("突围成功 —— 队长回复 20% 最大生命，灯火 +20")
			_log("broke" if settled else "broke_early")
			g.fx.append({"kind": "ring", "pos": g.ppos, "r": 90.0, "life": 0.5, "max": 0.5, "col": Color(0.5, 1.0, 0.65)})
			Sfx.play("hunt_break", -6.0, 1.0, 0.0)
			_end(true)   # 突围后包围圈立即结束（10-24 用户）：圈上海嗣就地散去，圈体 / 夹回 / 地面调子都停；奖励已发
			return
	# 肃清：圈上与圈内的海嗣全部倒下（钉住后第二波刷出之后才算）
	if not cleared and settled and el >= 10.0 and ring.all(func(e): return e.dead) and inner.all(func(e): return e.dead):
		cleared = true
		_xp_burst()
		g.vfx.show_banner("围猎者尽数肃清 —— 获得半级经验")
		_log("cleared")
	if settled and el >= Bal.v("hunt/dur", 20.0) * float(g.dmod.get("hunt_dur", 1.0)):
		_end()


func _xp_burst() -> void:
	var total: float = g.xp_need * Bal.v("hunt/xp_frac", 0.5)
	for j in 10:
		g.pickups.drop(g.ppos + Vector2.from_angle(TAU * j / 10.0) * 40.0, "xp", total / 10.0)


## 结束围猎。after_break：突围后立即结束——只散圈上的海嗣，圈内的小怪放回普通敌人（不再算围猎、不散）
func _end(after_break := false) -> void:
	_log("end_break" if after_break else "end")
	state = 3
	for e in ring + (inner if not after_break else []):
		if not e.dead:
			e.dead = true   # 散去：不走 kill，不掉落
			g.vfx.sparks(e.pos, Vector2.UP, Color(0.75, 0.5, 1.0), 4, 90.0)
	if after_break:
		for e in inner:
			e.erase("enc")
	if not broke and not cleared:
		g.vfx.show_banner("海嗣散入深处 —— 围猎结束")


## 离 p 最近的活着的圈上海嗣有多远（没有返回 INF）；机器人合拢途中据此决定要不要迎上去
func nearest_ring_dist(p: Vector2) -> float:
	var best := INF
	for e in ring:
		if not e.dead:
			best = minf(best, p.distance_to(e.pos))
	return best


## 主控移动后调用：从圈内往外走、那个方位的海嗣还活着 → 夹回圈内（冲刺也一样；合拢途中同样）
func clamp_player() -> void:
	if state != 2 or not inside:
		return
	var r := cur_r - 20.0
	var v: Vector2 = g.ppos - c
	if v.length() <= r:
		return
	var n := ring.size()
	var idx := posmod(roundi(v.angle() / (TAU / n)), n)
	if ring[idx].dead:
		return   # 缺口
	g.ppos = c + v.normalized() * r
