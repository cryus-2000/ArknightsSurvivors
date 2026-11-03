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
const RUN_FRAMES := 6          # e_duck_run@2x 帧数（pixgen 出图 + tools/imagegen/duck_run_cut.py）
const RUN_PER_PX := 0.075      # 跑步帧相位：每跑 1 像素前进的帧数（130 速度约 10 帧 / 秒）
const RUN_FPS_MAX := 26.0      # 爆发冲刺时帧率封顶，免得腿糊成一片
const SWEAT_COL := Color(0.55, 0.85, 1.0)
const MARK_COL := Color(1.0, 0.92, 0.35)
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
	e.spd = Bal.v("duck/spd", 130.0)
	e["duck_t0"] = g.t
	e["duck_hits"] = []     # 每段加速的到期时刻（受击时追加，过期剔除）
	e["duck_last_hit"] = -INF
	e["duck_dust"] = 0.0
	e["duck_ph"] = rng.randf() * TAU
	e["duck_burst"] = -INF
	e["duck_last_dir"] = Vector2.RIGHT   # 最近一次受击爆发冲刺的时刻
	e["duck_anim"] = 0.0     # 跑步帧相位（按当前速度累加）
	g.enemies_sys.admit(e)
	g.spawner.check_enemy(e, "duck")
	log.spawned += 1
	if not Cfg.dev_args().is_empty():
		print("DUCK spawn t=%.2f d=%.0f" % [g.t, e.pos.distance_to(g.ppos)])
	Sfx.play("hh_reveal", -2.0, 1.35, 0.0)   # 出现音效（借现有录音，音高上调）
	return e


## 档位速度：基础 + 每段加速 × 段数，封顶 duck/spd_max（高于队长走路、低于冲刺追速 chase_speed：要冲刺才追得上）
func tier_speed(e: Dictionary) -> float:
	var n: int = 0
	for t in e.duck_hits:
		if float(t) > g.t:
			n += 1
	return minf(Bal.v("duck/spd", 130.0) + Bal.v("duck/hit_spd", 25.0) * n, Bal.v("duck/spd_max", 190.0))


## 爆发冲刺余量（用户 11-04「被攻击后快速逃跑看不出来」）：受击瞬间 +duck/burst_spd，duck/burst_t 秒内按二次缓出回落到档位速度。
## 爆发段不受 spd_max 限制，但很短（缺省 0.5 秒、多跑约 45 像素），整体仍是冲刺追得上
func burst(e: Dictionary) -> float:
	var k: float = 1.0 - (g.t - float(e.duck_burst)) / maxf(0.01, Bal.v("duck/burst_t", 0.5))
	return Bal.v("duck/burst_spd", 260.0) * k * k if k > 0.0 else 0.0


## 当前移速 = 档位 + 爆发
func speed(e: Dictionary) -> float:
	return tier_speed(e) + burst(e)


## 0–1：画面「有多快」（档位 + 爆发），驱动帧率、尘土、速度线
func fastness(e: Dictionary) -> float:
	var base: float = Bal.v("duck/spd", 130.0)
	return clampf((speed(e) - base) / maxf(1.0, Bal.v("duck/spd_max", 190.0) - base), 0.0, 1.5)


## 受击（combat._damage 过了无敌判定后调）：加一段加速；同一 duck/hit_gap 秒内的多次命中只算一段（范围持续伤害不会一帧叠满）
func on_hit(e: Dictionary) -> void:
	if g.t - float(e.duck_last_hit) < Bal.v("duck/hit_gap", 0.2):
		return
	e.duck_last_hit = g.t
	e.duck_burst = g.t
	_burst_fx(e)
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
	# 左右摇摆跑：方向按正弦摆，跑得越快摆得越勤；爆发冲刺时摆幅收小（直着窜出去）
	var fast: float = fastness(e)
	var wob: float = 0.3 * (1.0 - clampf(burst(e) / 60.0, 0.0, 0.8))
	dir = dir.rotated(wob * sin(g.t * lerpf(3.0, 6.0, minf(fast, 1.0)) + float(e.duck_ph)))
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
	e.duck_last_dir = (e.pos - old).normalized() if e.pos.distance_squared_to(old) > 0.0001 else Vector2(e.fx, 0.0)
	# 跑步帧相位：每像素 RUN_PER_PX 帧，帧率跟着当前速度走（130 ≈ 10 帧 / 秒，封顶 RUN_FPS_MAX）
	var a0: float = float(e.duck_anim)
	e.duck_anim = fmod(a0 + minf(sp * RUN_PER_PX, RUN_FPS_MAX) * dt, float(RUN_FRAMES))
	# 每一步（一圈两步：帧 0、3 落脚）脚下往后踢一小团尘土（纯画面）
	if int(a0 / 3.0) != int(float(e.duck_anim) / 3.0) and g.fx.size() < 390:
		var kb: Vector2 = -e.duck_last_dir
		for i in 5:
			g.fx.append({"kind": "spark", "pos": e.pos + Vector2(-e.fx * 6.0, e.r * 0.8) + Vector2(g.vrng.randf_range(-3, 3), g.vrng.randf_range(-2, 2)),
				"vel": kb.rotated(g.vrng.randf_range(-0.6, 0.6)) * g.vrng.randf_range(40, 110) + Vector2(0, -g.vrng.randf_range(20, 60)),
				"sz": 4.0 if g.vrng.randf() < 0.5 else 2.0, "life": 0.35, "max": 0.35, "col": DUST_COL})
	# 尘土（纯画面，g.vrng）：脚下往后扬，加速时更密、更大
	e.duck_dust -= dt * lerpf(1.0, 4.0, minf(fast, 1.5) / 1.5)
	if e.duck_dust <= 0.0 and g.fx.size() < 400:
		e.duck_dust = 0.08
		var back: Vector2 = -e.duck_last_dir
		for i in (3 if fast > 0.8 else (2 if fast > 0.3 else 1)):
			g.fx.append({"kind": "spark", "pos": e.pos + Vector2(g.vrng.randf_range(-6, 6), e.r * 0.8), "vel": back * g.vrng.randf_range(30, 70 + 60 * fast) + Vector2(0, -g.vrng.randf_range(15, 40)),
				"sz": 2.0 if g.vrng.randf() < 0.5 - 0.2 * fast else 4.0, "life": 0.4, "max": 0.4, "col": DUST_COL})


## 受击爆发的一团尘土（脚下往后炸开的一圈，纯画面）；惊叹号 / 汗滴在 draw 里按 duck_burst 画
func _burst_fx(e: Dictionary) -> void:
	if g.fx.size() > 380:
		return
	var back: Vector2 = -Vector2(e.get("duck_last_dir", Vector2(e.fx, 0.0)))
	var foot: Vector2 = e.pos + Vector2(0, e.r * 0.8)
	for i in 12:
		var a: float = back.angle() + g.vrng.randf_range(-1.2, 1.2)
		g.fx.append({"kind": "spark", "pos": foot + Vector2(g.vrng.randf_range(-5, 5), g.vrng.randf_range(-3, 3)),
			"vel": Vector2.from_angle(a) * g.vrng.randf_range(60, 170) + Vector2(0, -g.vrng.randf_range(10, 50)),
			"sz": 4.0 if g.vrng.randf() < 0.6 else 6.0, "life": 0.5, "max": 0.5, "col": DUST_COL})


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


## 「冲刺追得上」的口径：队长走路 + 冷却一到就冲刺的平均速度（每 dash_cd 秒多走 dash_dist − 冲刺 0.18 秒里本来能走的距离）。
## 缺省 150 + (107 − 27) / 1.2 ≈ 217；duck/spd_max 要低于它（11-04 用户：平时走路追不上没关系，冲刺能追上就行）
func chase_speed() -> float:
	return g.speed + maxf(0.0, g.dash_dist() - g.speed * 0.18) / maxf(0.3, g.dash_cd_full())


## 机器人用冲刺追：在追、离它超过 bot/duck_dash_r、冲刺好了 → 朝它冲（core/bot.move 先问这个）
func bot_dash(p: Vector2) -> Vector2:
	var d: Vector2 = chase_dir(p)
	if d == Vector2.ZERO or not g.dash_ready() or g.dash_t > 0.0:
		return Vector2.ZERO
	var e: Dictionary = alive()
	return d if e.pos.distance_to(p) > Bal.v("bot/duck_dash_r", 140.0) else Vector2.ZERO


## 机器人追鸭爵（core/bot.gd 高手 / master、autotest 普通）：在 bot/duck_r 内、生命 > bot/duck_hp、
## 且「追得到」（它档位速度低于冲刺追速 chase_speed，或已在 bot/duck_reach 内、干员打得到）时返回朝它的方向，否则 ZERO
func chase_dir(p: Vector2) -> Vector2:
	var e: Dictionary = alive()
	if e.is_empty() or g.hp <= g.max_hp * Bal.v("bot/duck_hp", 0.4):
		return Vector2.ZERO
	var d: float = e.pos.distance_to(p)
	if d > Bal.v("bot/duck_r", 650.0):
		return Vector2.ZERO
	if tier_speed(e) >= chase_speed() and d > Bal.v("bot/duck_reach", 220.0):   # 爆发冲刺很短，按档位判断；走路追不上的靠冲刺（bot_dash）
		return Vector2.ZERO
	return (e.pos - p).normalized()


## 场上活着的鸭爵（机器人 / 屏外箭头用）
func alive() -> Dictionary:
	for e in g.enemies:
		if not e.dead and e.type == "duck":
			return e
	return {}


## 画法（world.draw_enemy 调）：跑步帧条 e_duck_run（6 帧，帧率跟当前速度，duck_anim 在 step 里累加）+ 每步一颠 + 按速度前倾；
## 加速时身后速度线，受击爆发后头顶惊叹号 + 甩出汗滴（duck/burst_t 的约 2 倍时长）。停住（晕眩）时画静态图
var _run_tried := false

func draw(e: Dictionary, ci: CanvasItem) -> void:
	if not _run_tried:
		_run_tried = true
		if g.tex.get("e_duck_run") == null:
			g.tex["e_duck_run"] = A.tex("e_duck_run")
			if g.tex["e_duck_run"] != null:
				g.tex["e_duck_run_white"] = A.white_of(g.tex["e_duck_run"])
	var moving: bool = g.t < float(e.mv_until) and e.stun <= 0.0
	var tx: Texture2D = g.tex.get("e_duck_run") if moving else null
	var nf: int = RUN_FRAMES if tx != null else 1
	var frame: int = int(e.duck_anim) % RUN_FRAMES if tx != null else 0
	var wname: String = "e_duck_run_white" if tx != null else "e_duck_white"
	if tx == null:
		tx = g.tex.get("e_duck")
	if tx == null:
		return
	var fast: float = fastness(e)
	var pk: float = Game.PX / A.hires_of(tx) * float(e.get("sc", 1.0)) * Bal.v("duck/draw_scale", 1.25)   # 画大一点（判定 e.r 不变）
	var fw: float = tx.get_width() / float(nf)
	var fh: float = tx.get_height()
	var foot: Vector2 = e.pos + Vector2(0, e.r * 0.8 + 3.0 * Game.PX) + g.draw_off
	var flip: bool = e.fx < 0.0
	var sgn: float = -1.0 if flip else 1.0
	# 每步一颠（一圈 6 帧两步）、按速度前倾
	var bob: float = -absf(sin(PI * float(e.duck_anim) / 3.0)) * lerpf(4.0, 8.0, minf(fast, 1.0)) if moving else 0.0
	var lean: float = (0.12 + 0.18 * minf(fast, 1.2)) * sgn if moving else 0.0
	# 影子
	ci.draw_set_transform(foot.round(), 0.0, Vector2(1.0, 0.35))
	ci.draw_circle(Vector2.ZERO, e.r * 1.1 * Bal.v("duck/draw_scale", 1.25) * (1.0 + bob * 0.02), Color(0, 0, 0, 0.28))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 速度线（身后三道，越快越长越实）
	if moving and fast > 0.15:
		var a: float = clampf(fast, 0.0, 1.0) * 0.75
		for k in 3:
			var h: float = fh * pk * (0.25 + 0.25 * k)
			var j: float = fmod((g.t + g.vis_t) * 40.0 + k * 13.0, 12.0)
			var x0: float = -sgn * (fw * pk * 0.42 + j)
			var ln: float = (12.0 + 34.0 * minf(fast, 1.5)) * (1.0 - 0.2 * k)
			ci.draw_line((foot + Vector2(x0, -h + bob)).round(), (foot + Vector2(x0 - sgn * ln, -h + bob)).round(), Color(1, 1, 1, a * (1.0 - 0.25 * k)), 2.0)
	ci.draw_set_transform((foot + Vector2(0, bob)).round(), lean, Vector2(-pk if flip else pk, pk))
	var col: Color = Look.op_mod(g, e.pos, Color.WHITE)
	var src := Rect2(fw * frame, 0, fw, fh)
	var dst := Rect2(Vector2(-fw / 2.0, -fh), Vector2(fw, fh))
	ci.draw_texture_rect_region(tx, dst, src, col)
	if e.flash > 0.0 and g.tex.get(wname) != null:
		ci.draw_texture_rect_region(g.tex[wname], dst, src, Color(1, 1, 1, clampf(e.flash / 0.1, 0.0, 1.0)))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var head: Vector2 = foot + Vector2(sgn * fw * pk * 0.12, -fh * pk + bob)
	# 受击后：惊叹号（弹出再缩回）+ 两滴汗往后甩
	var since: float = g.t - float(e.duck_burst)
	var life: float = Bal.v("duck/burst_t", 0.5) * 2.0
	if since >= 0.0 and since < life:
		var u: float = since / life
		var pop: float = 1.0 + 0.6 * maxf(0.0, 1.0 - since / 0.12)
		var mp: Vector2 = (head + Vector2(sgn * 10.0, -12.0 - 6.0 * minf(1.0, since / 0.12))).round()
		var al: float = 1.0 if u < 0.7 else (1.0 - u) / 0.3
		_bang(ci, mp, pop, Color(MARK_COL.r, MARK_COL.g, MARK_COL.b, al))
		for k in 2:
			var v := Vector2(-sgn * (50.0 + 30.0 * k), -70.0 + 25.0 * k)
			var dp: Vector2 = head + Vector2(-sgn * 4.0, 6.0) + v * since + Vector2(0, 220.0) * since * since
			_drop(ci, dp.round(), Color(SWEAT_COL.r, SWEAT_COL.g, SWEAT_COL.b, al))
	# 头顶细血条（受过伤才画）
	if e.hp < e.maxhp:
		var w := 34.0
		var top: Vector2 = foot + Vector2(-w / 2.0, -fh * pk - 8.0)
		ci.draw_rect(Rect2(top, Vector2(w, 3)), Color(0, 0, 0, 0.6))
		ci.draw_rect(Rect2(top, Vector2(w * clampf(e.hp / e.maxhp, 0.0, 1.0), 3)), Color(1.0, 0.82, 0.35))


## 像素惊叹号：深色描边 + 黄色本体（竖条 + 点），c = 底部中心
func _bang(ci: CanvasItem, c: Vector2, sc: float, col: Color) -> void:
	var w: float = roundf(4.0 * sc)
	var h: float = roundf(12.0 * sc)
	var o := Color(0.03, 0.05, 0.09, col.a)
	ci.draw_rect(Rect2(c + Vector2(-w / 2.0 - 2.0, -h - w - 4.0), Vector2(w + 4.0, h + 2.0)), o)
	ci.draw_rect(Rect2(c + Vector2(-w / 2.0 - 2.0, -w - 2.0), Vector2(w + 4.0, w + 4.0)), o)
	ci.draw_rect(Rect2(c + Vector2(-w / 2.0, -h - w - 2.0), Vector2(w, h - 2.0)), col)
	ci.draw_rect(Rect2(c + Vector2(-w / 2.0, -w), Vector2(w, w)), col)


## 像素汗滴：上尖下圆，深色描边
func _drop(ci: CanvasItem, c: Vector2, col: Color) -> void:
	var o := Color(0.03, 0.05, 0.09, col.a)
	ci.draw_rect(Rect2(c + Vector2(-3, -3), Vector2(6, 6)), o)
	ci.draw_rect(Rect2(c + Vector2(-1, -6), Vector2(2, 3)), o)
	ci.draw_rect(Rect2(c + Vector2(-2, -2), Vector2(4, 4)), col)
	ci.draw_rect(Rect2(c + Vector2(0, -4), Vector2(1, 2)), col)
