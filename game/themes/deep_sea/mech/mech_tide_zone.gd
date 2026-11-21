extends "res://scripts/core/theme_mechanic.gd"
## 水月主题机制 · 黑潮缩圈（docs/38 §1.7、docs/364 §2）：150 秒起预告 20 秒 → 收缩 25 秒 → 稳定，Boss 在场暂停；圈外掉血 + 灯火流失；
## 最终 Boss 登场时 freeze_zone 把圈冻结成场地。圈的状态仍存在 g.zone_c / zone_r / zone_next_* / zone_state / zone_frozen / zone_t
## （机器人、干员技能、画面读）。本文件从 run/combat.gd 原样搬来（update_zone、_zone_schedule、zone_dir 与计时状态）；
## 最终 Boss 场地（冻结 / 插值 / 约束 / 禁生成）是通用的 run/arena.gd（docs/364 §7）。

const Game = preload("res://scripts/game.gd")
var g: Game
var zone_from_c := Vector2.ZERO
var zone_from_r := 99999.0
var zone_phase := 0
var zone_hurt_t := 0.0
var zone_out_t := 0.0     # 本次出圈了几秒（圈内为 0）：前 ZONE_GRACE 秒不掉血；界面据此画回圈方向提示
var zone_paused := false  # Boss 在场，缩圈计时暂停
const ZONE_START := 150.0
const ZONE_GRACE := 2.0   # 1.1 用户决定：出圈后 2 秒内不掉血
const ZONE_RADII := [1300.0, 1000.0, 780.0, 600.0, 480.0]


func _init(game: Game) -> void:
	g = game


## 主题机制挂钩：game._update_player 每帧（原 combat.update_zone 的调用处）
func on_player_tick(dt: float) -> void:
	update_zone(dt)


## 缩圈：预告 20 秒 → 收缩 25 秒 → 稳定，直到下一轮；圈外为「黑潮」。
## 1.1（用户决定）：Boss 在场时缩圈计时整体暂停（预告 / 收缩停在原处，Boss 倒下后接着走）；出圈后前 2 秒不掉血
func update_zone(dt: float) -> void:
	# 最终 Boss 场地冻结后不再走缩圈日程（也不弹「黑潮停滞」横幅）；圈外判定照常走下面那段（docs/38 §1.7）
	# 场地插值由核心的 g.arena.step 在本挂钩之前做完（docs/364 §7）
	if not g.zone_frozen and not _zone_schedule(dt):
		return
	# 圈外：黑潮伤害 + 灯火流失 + 神经损伤
	var out := g.ppos.distance_to(g.zone_c) - g.zone_r
	if out > 0.0 and g.state == g.S.PLAY and not g.squad.in_sanctuary(g.ppos):
		zone_out_t += dt
		var lz: float = g.lamp
		g.lamp = maxf(0.0, g.lamp - 6.0 * dt * g.lamp_loss_mult)
		g.telemetry.lamp_note("圈外", g.lamp - lz)
		if zone_out_t < ZONE_GRACE:
			return
		var dps: float = (2.5 + 1.5 * max(zone_phase, 0)) * (1.0 + minf(out / 300.0, 1.0))
		g.combat.lose_hp(dps * dt, "zone")
		zone_hurt_t -= dt
		if zone_hurt_t <= 0.0:
			zone_hurt_t = 0.8
			g.hurt_flash = maxf(g.hurt_flash, 0.08)
			g.head_bar_t = 2.0
			g.vfx.add_text(g.ppos + Vector2(0, -84), "黑潮", Color(0.8, 0.4, 1.0), 16)
	elif g.state == g.S.PLAY:
		zone_out_t = 0.0   # 回到圈内（或庇护所）：缓冲重置


## 缩圈日程（原 update_zone 前半段，逻辑不变）：返回 false = 黑潮还没开始，本帧不做圈外判定
func _zone_schedule(dt: float) -> bool:
	if g.zone_state == 0:
		if g.t < ZONE_START:
			return false
		g.zone_c = g.ppos
		g.zone_r = ZONE_RADII[0] + 400.0
		zone_phase = -1
		g.zone_state = 3
		g.zone_t = 0.0
	var paused: bool = g.spawner.boss_alive()
	if paused != zone_paused:
		zone_paused = paused
		if g.zone_state != 3 or zone_phase >= 0:
			g.vfx.show_banner("Boss 在场：黑潮停滞" if paused else "黑潮再度涌动")
	if not paused:
		g.zone_t += dt
	match g.zone_state:
		3:
			if g.zone_t >= (0.0 if zone_phase < 0 else 45.0) and zone_phase < ZONE_RADII.size() - (2 if g.ending == "resolve" else 1):
				zone_phase += 1
				g.zone_next_r = ZONE_RADII[zone_phase]
				var off := Vector2.from_angle(g.rng.randf() * TAU) * g.rng.randf_range(0.0, (g.zone_r - g.zone_next_r) * 0.7)
				g.zone_next_c = g.zone_c + off
				g.zone_state = 1
				g.zone_t = 0.0
				g.vfx.show_banner("黑潮将至：%d 秒后安全区缩小" % 20)
				Sfx.play("roar", -6.0, 0.5, 0.0)
		1:
			if g.zone_t >= 20.0:
				g.zone_state = 2
				g.zone_t = 0.0
				zone_from_c = g.zone_c
				zone_from_r = g.zone_r
				g.vfx.show_banner("黑潮正在逼近！")
		2:
			var k := clampf(g.zone_t / 25.0, 0.0, 1.0)
			g.zone_c = zone_from_c.lerp(g.zone_next_c, k)
			g.zone_r = lerpf(zone_from_r, g.zone_next_r, k)
			if k >= 1.0:
				g.zone_state = 3
				g.zone_t = 0.0
	return true
## 最终 Boss 场地冻结（docs/38 §1.7）已拆到通用的 run/arena.gd（docs/364 §7）；冻结那一刻这里只重置缩圈阶段
func on_arena_freeze(fresh: bool) -> void:
	if fresh:
		zone_phase = -1


## 主控指向安全区圆心的单位向量（圈外方向提示用）
func zone_dir() -> Vector2:
	return (g.zone_c - g.ppos).normalized() if g.zone_state != 0 else Vector2.ZERO


## ---- 机器人挂钩（docs/364 §6；原 core/bot.gd / autotest.bot_move 的缩圈段，原样搬来）
## 手残：快出圈了就往圈心走
func bot_return_dir(p: Vector2, margin: float) -> Vector2:
	if g.zone_state != 0 and p.distance_to(g.zone_c) > g.zone_r - margin:
		return (g.zone_c - p).normalized()
	return Vector2.ZERO


## 高手候选点：离（下一）圈边 120 内按超出量扣分，圈外再 −30
func bot_score(q: Vector2, s: float) -> float:
	if g.zone_state != 0:
		var tc: Vector2 = g.zone_next_c if g.zone_state == 1 else g.zone_c
		var tr: float = g.zone_next_r if g.zone_state == 1 else g.zone_r
		var over: float = q.distance_to(tc) - (tr - 120.0)
		if over > 0.0:
			s -= over * 0.12
		if q.distance_to(g.zone_c) > g.zone_r:
			s -= 30.0
	return s


## 高手 / master 冲刺：在圈外时指向圈心
func bot_outside_dir(p: Vector2) -> Vector2:
	if g.zone_state != 0 and p.distance_to(g.zone_c) > g.zone_r:
		return (g.zone_c - p).normalized()
	return Vector2.ZERO


## 冲刺落点在圈外、而且比现在离圈心更远：不冲
func bot_land_bad(land: Vector2, p: Vector2) -> bool:
	return g.zone_state != 0 and land.distance_to(g.zone_c) > g.zone_r and land.distance_to(g.zone_c) > p.distance_to(g.zone_c)


## 普通机器人：拉力合成后贴圈边 / 出圈时回圈（计时状态存在 autotest：zone_out_since、want_dash）
func bot_steer(at, mv: Vector2) -> Vector2:
	# 缩圈：靠近圈边时往圈内走
	if g.zone_state != 0:
		var zc: float = g.ppos.distance_to(g.zone_c)
		var target_c: Vector2 = g.zone_next_c if g.zone_state == 1 else g.zone_c
		var target_r: float = g.zone_next_r if g.zone_state == 1 else g.zone_r
		var od: float = zc - g.zone_r
		if od > -30.0:
			# 已贴圈边 / 出圈：真人会先回圈。敌群的「往外推」只留侧向分量（侧身绕过去；溟痕在后面单独加，照样绕开），经验 / 商人等拉力朝外的不跟，
			# 回圈拉力随出圈距离加大；出圈超过 0.5 秒且冲刺好了就朝圈心冲（2026-09-27：v11-ab 黑潮死亡多是普通机器人被怪群推在圈外，
			# 实测圈外 165–196 像素、怪群推力 −2.6…−4.8 压过固定的 3.0 回圈拉力）
			var toc: Vector2 = (g.zone_c - g.ppos).normalized()
			var rad: float = mv.dot(toc)
			if rad < 0.0:
				mv -= toc * rad
			mv += toc * (3.0 + clampf(od / 50.0, 0.0, 4.0))
			if od > 0.0:
				if at.zone_out_since < 0.0:
					at.zone_out_since = g.t
				elif g.t - at.zone_out_since > 0.5 and g.dash_ready():
					at.want_dash = true
			else:
				at.zone_out_since = -1.0
		else:
			at.zone_out_since = -1.0
			if g.ppos.distance_to(target_c) > target_r - 160.0 or zc > g.zone_r - 160.0:
				mv += (target_c - g.ppos).normalized() * 3.0
	return mv
