extends RefCounted
## 鸭爵（稀有敌人，用户 11-03 批，docs/216 §11）：每局两次，从画面边缘附近出现，一出现就背着队长跑；
## 每次被攻击加速一段（可叠，有上限，保证队长走路追得上），duck/flee_t 秒内没被打倒就溜走消失（不掉落）。
## 打倒必掉 1 件藏品（chest，走现有藏品池与 core_gate）+ 少量源石锭。
## 原作（PRTS 敌人「鸭爵」）：不攻击、无法被阻挡、受到伤害后开始奔跑移动速度大幅提升、被击倒后掉落 1 件收藏品。
## 提示只有出现音效、声呐亮点（hud_bars.draw_minimap）和屏外箭头（hud_banners.draw_duck_pointer），不弹横幅。
## 出现时刻 / 位置用自己的随机流；生成敌人字典时 rng_spawn 状态存回，所以 duck/on = 0 与关掉前逐帧相同，开着也不打乱刷怪序列。
const Game = preload("res://scripts/game.gd")
const Bal = preload("res://scripts/core/balance.gd")
const A = preload("res://scripts/art.gd")
const Look = preload("res://scripts/render/look.gd")
const DUST_COL := Color(0.62, 0.58, 0.5, 0.85)
var g: Game
var rng := RandomNumberGenerator.new()
var plan: Array = []        # 本局两次出现的时刻（秒），第一次 update 时按对局种子定
var idx := 0
var log := {"spawned": 0, "killed": 0, "fled": 0, "kill_t": []}   # 遥测 / 测试用


func _init(game: Game) -> void:
	g = game


func on() -> bool:
	return Bal.v("duck/on", 1.0) > 0.0


func _plan() -> void:
	rng.seed = hash([g.rng_spawn.seed, "duck"])
	plan = [rng.randf_range(Bal.v("duck/t1_lo", 180.0), Bal.v("duck/t1_hi", 360.0)),
		rng.randf_range(Bal.v("duck/t2_lo", 480.0), Bal.v("duck/t2_hi", 720.0))]
	for a in Cfg.dev_args():
		if a.begins_with("--duckat="):   # 测试开关（仅开发版）：--duckat=<秒>[,<秒>] 指定出现时刻（录像 / 回归用）
			plan = []
			for s in a.substr(9).split(","):
				plan.append(float(s))


## 每帧（game.gd，与 spawner.update 同一处：演示 / 试炼 / 沙盒不跑）
func update(_dt: float) -> void:
	if not on():
		return
	if plan.is_empty():
		_plan()
	if idx < plan.size() and g.t >= float(plan[idx]):
		idx += 1
		spawn()


## 位置：以队长为中心、画面半宽 / 半高 × duck/spawn_edge 的矩形边上（画面内靠边一圈），缩圈时收进圈内
func spawn() -> Dictionary:
	var half: Vector2 = g.view_size() * 0.5 * Bal.v("duck/spawn_edge", 0.85)
	var d := Vector2.from_angle(rng.randf() * TAU)
	var k: float = minf(half.x / maxf(absf(d.x), 0.001), half.y / maxf(absf(d.y), 0.001))
	var p: Vector2 = g.spawner.safe_event_pos(g.ppos + d * k, 110.0)
	var st: int = g.rng_spawn.state
	var e: Dictionary = g.spawner.new_enemy("duck", p)
	g.rng_spawn.state = st
	e.pos = g.map.push_out(p, e.r)
	e.hp *= Bal.v("duck/hp_mult", 1.0)
	e.maxhp = e.hp
	e.spd = Bal.v("duck/spd", 105.0)
	e["duck_t0"] = g.t
	e["duck_hits"] = []     # 每段加速的到期时刻（受击时追加，过期剔除）
	e["duck_last_hit"] = -INF
	e["duck_dust"] = 0.0
	e["duck_ph"] = rng.randf() * TAU
	g.enemies_sys.admit(e)
	g.spawner.check_enemy(e, "duck")
	log.spawned += 1
	if not Cfg.dev_args().is_empty():
		print("DUCK spawn t=%.2f d=%.0f" % [g.t, e.pos.distance_to(g.ppos)])
	Sfx.play("hh_reveal", -2.0, 1.35, 0.0)   # 出现音效（借现有录音，音高上调）
	return e


## 当前移速：基础 + 每段加速 × 段数，封顶 duck/spd_max（低于队长基础移速，追得上）
func speed(e: Dictionary) -> float:
	var n: int = 0
	for t in e.duck_hits:
		if float(t) > g.t:
			n += 1
	return minf(Bal.v("duck/spd", 105.0) + Bal.v("duck/hit_spd", 10.0) * n, Bal.v("duck/spd_max", 140.0))


## 受击（combat._damage 过了无敌判定后调）：加一段加速；同一 duck/hit_gap 秒内的多次命中只算一段（范围持续伤害不会一帧叠满）
func on_hit(e: Dictionary) -> void:
	if g.t - float(e.duck_last_hit) < Bal.v("duck/hit_gap", 0.2):
		return
	e.duck_last_hit = g.t
	var arr: Array = e.duck_hits.filter(func(t): return float(t) > g.t)
	arr.append(g.t + Bal.v("duck/hit_t", 2.0))
	var cap: int = Bal.vi("duck/hit_stack", 4)
	while arr.size() > cap:
		arr.pop_front()   # 满层：顶掉最早的一段（等于刷新时长）
	e.duck_hits = arr


## 敌人更新 A 段（enemies.update）：自己移动，不走敌对 AI / 接触伤害 / 远距回收
func step(e: Dictionary, dt: float) -> void:
	if g.t - float(e.duck_t0) >= Bal.v("duck/flee_t", 30.0):
		flee(e)
		return
	if e.stun > 0.0 or e.get("coma", false):
		return
	var away: Vector2 = e.pos - g.ppos
	var dir: Vector2 = away.normalized() if away.length() > 1.0 else Vector2.RIGHT
	var sp: float = speed(e)
	# 左右摇摆跑：方向按正弦摆，跑得越快摆得越勤（画面另有身体左右摇）
	var fast: float = clampf((sp - Bal.v("duck/spd", 105.0)) / maxf(1.0, Bal.v("duck/spd_max", 140.0) - Bal.v("duck/spd", 105.0)), 0.0, 1.0)
	dir = dir.rotated(0.3 * sin(g.t * lerpf(3.0, 6.0, fast) + float(e.duck_ph)))
	if e.slow > 0.0:
		sp *= 0.65
	if float(e.get("lite_slow_t", 0.0)) > g.t:
		sp *= 1.0 - float(e.lite_slow)
	var old: Vector2 = e.pos
	var np: Vector2 = e.pos + dir * sp * dt + e.kb * dt * 0.3
	e.kb = e.kb.move_toward(Vector2.ZERO, 900.0 * dt)
	np = g.spawner.safe_event_pos(g.combat.arena_clamp(np, 90.0), 90.0)   # 缩圈：贴着圈边滑
	e.pos = g.map.push_out(np, e.r)
	e.mv_until = g.t + 0.12
	if absf(e.pos.x - old.x) > 0.01:
		e.fx = signf(e.pos.x - old.x)
	# 尘土（纯画面，g.vrng）：脚下往后扬，加速时更密
	e.duck_dust -= dt * lerpf(1.0, 3.0, fast)
	if e.duck_dust <= 0.0 and g.fx.size() < 400:
		e.duck_dust = 0.09
		var back: Vector2 = -(e.pos - old).normalized()
		for i in (2 if fast > 0.3 else 1):
			g.fx.append({"kind": "spark", "pos": e.pos + Vector2(g.vrng.randf_range(-6, 6), e.r * 0.8), "vel": back * g.vrng.randf_range(30, 70) + Vector2(0, -g.vrng.randf_range(15, 40)),
				"sz": 2.0 if g.vrng.randf() < 0.6 else 4.0, "life": 0.4, "max": 0.4, "col": DUST_COL})


## 时限到：溜走（不掉落、不计击杀）
func flee(e: Dictionary) -> void:
	e.dead = true
	log.fled += 1
	if not Cfg.dev_args().is_empty():
		print("DUCK fled t=%.2f d=%.0f hp=%.0f%%" % [g.t, e.pos.distance_to(g.ppos), 100.0 * e.hp / e.maxhp])
	g.vfx.sparks(e.pos, Vector2.ZERO, DUST_COL, 14, 160.0)
	if on_screen(e.pos):
		g.vfx.add_text(e.pos + Vector2(0, -34), "溜走了", Color(0.85, 0.85, 0.8), 14)


## 大致在画面内（镜头跟队长；以队长为中心的视野矩形）
func on_screen(p: Vector2) -> bool:
	var d: Vector2 = (p - g.ppos).abs()
	var half: Vector2 = g.view_size() * 0.5
	return d.x < half.x and d.y < half.y


## combat.kill 掉落段调：必掉 1 件藏品 + duck/ingots 个源石锭（kill 照常给经验 / 磁铁回复掷骰）
func on_kill(e: Dictionary) -> void:
	log.killed += 1
	log.kill_t.append(snappedf(g.t - float(e.duck_t0), 0.1))
	if not Cfg.dev_args().is_empty():
		print("DUCK kill t=%.2f after=%.1f" % [g.t, g.t - float(e.duck_t0)])
	g.pickups.drop(e.pos, "chest", 1.0, "duck")
	for k in Bal.vi("duck/ingots", 6):
		g.pickups.drop(e.pos + Vector2.from_angle(g.rng_drop.randf() * TAU) * g.rng_drop.randf_range(6.0, 26.0), "ingot", 1.0)
	Sfx.play("relic", -4.0, 1.2)


## 机器人追鸭爵（core/bot.gd 高手 / master、autotest 普通）：在 bot/duck_r 内、生命 > bot/duck_hp、
## 且「追得到」（它现速低于队长移速，或已在 bot/duck_reach 内、干员打得到）时返回朝它的方向，否则 ZERO
func chase_dir(p: Vector2) -> Vector2:
	var e: Dictionary = alive()
	if e.is_empty() or g.hp <= g.max_hp * Bal.v("bot/duck_hp", 0.4):
		return Vector2.ZERO
	var d: float = e.pos.distance_to(p)
	if d > Bal.v("bot/duck_r", 650.0):
		return Vector2.ZERO
	if speed(e) >= g.speed and d > Bal.v("bot/duck_reach", 220.0):
		return Vector2.ZERO
	return (e.pos - p).normalized()


## 场上活着的鸭爵（机器人 / 屏外箭头用）
func alive() -> Dictionary:
	for e in g.enemies:
		if not e.dead and e.type == "duck":
			return e
	return {}


## 画法（world.draw_enemy 调）：一张静态图，代码做跑动——上下颠（每步一颠）、左右摇（绕脚底转），加速时步频更快、摇幅更大
func draw(e: Dictionary, ci: CanvasItem) -> void:
	var tx: Texture2D = g.tex.get("e_duck")
	if tx == null:
		return
	var sp: float = speed(e)
	var fast: float = clampf((sp - Bal.v("duck/spd", 105.0)) / maxf(1.0, Bal.v("duck/spd_max", 140.0) - Bal.v("duck/spd", 105.0)), 0.0, 1.0)
	var moving: bool = g.t < float(e.mv_until) and e.stun <= 0.0
	var ph: float = (g.t + g.vis_t) * lerpf(9.0, 16.0, fast) + float(e.duck_ph)
	var bob: float = -absf(sin(ph)) * lerpf(3.0, 5.0, fast) if moving else 0.0
	var rot: float = sin(ph) * lerpf(0.10, 0.20, fast) if moving else 0.0
	var pk: float = Game.PX / A.hires_of(tx) * float(e.get("sc", 1.0))
	var fw: float = tx.get_width()
	var fh: float = tx.get_height()
	var foot: Vector2 = e.pos + Vector2(0, e.r * 0.8 + 3.0 * Game.PX) + g.draw_off
	# 影子
	ci.draw_set_transform(foot.round(), 0.0, Vector2(1.0, 0.35))
	ci.draw_circle(Vector2.ZERO, e.r * 1.1 * (1.0 + bob * 0.03), Color(0, 0, 0, 0.28))
	var flip: bool = e.fx < 0.0
	ci.draw_set_transform((foot + Vector2(0, bob)).round(), rot * (-1.0 if flip else 1.0), Vector2(-pk if flip else pk, pk))
	var col: Color = Look.op_mod(g, e.pos, Color.WHITE)
	ci.draw_texture_rect(tx, Rect2(Vector2(-fw / 2.0, -fh), Vector2(fw, fh)), false, col)
	if e.flash > 0.0 and g.tex.get("e_duck_white") != null:
		ci.draw_texture_rect(g.tex["e_duck_white"], Rect2(Vector2(-fw / 2.0, -fh), Vector2(fw, fh)), false, Color(1, 1, 1, clampf(e.flash / 0.1, 0.0, 1.0)))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 头顶细血条（受过伤才画）
	if e.hp < e.maxhp:
		var w := 34.0
		var top: Vector2 = foot + Vector2(-w / 2.0, -fh * pk - 8.0)
		ci.draw_rect(Rect2(top, Vector2(w, 3)), Color(0, 0, 0, 0.6))
		ci.draw_rect(Rect2(top, Vector2(w * clampf(e.hp / e.maxhp, 0.0, 1.0), 3)), Color(1.0, 0.82, 0.35))
