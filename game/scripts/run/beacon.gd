extends RefCounted
## 引航灯标（名字文案暂定；docs/49d §13.5 方案 C，用户 9/29 定）：溟痕的主动清理手段，只靠走位。
## 自然溟痕出现后，每 60–75 秒在主控 250–400 外、溟痕最密的点（缩圈后只刷在圈内）立一座熄灭的灯标，场上最多 1 座未点燃（Boss 在场也刷）；
## 主控站进半径 70 的光圈累计 2.5 秒点燃（离开时进度缓慢回退，不清零）。
## 点燃：清除半径 260 内的自然 / 小怪溟痕（Boss 溟痕只把剩余寿命缩到 ≤ 2 秒，不删），这片区域 30 秒内不再生成自然溟痕
## （map.mire_new 落点检查 blocks()），灯标亮着当安全区标记，+5 灯火；同时清空主控与光圈内队友的神经损伤。
## 联动：灯火 < 30 时点燃时间 ×1.5；流明灯塔区覆盖灯标时点燃速度 ×2；缩圈把灯标卷到圈外即熄灭消失。
## 定位（协调人 9/30）：灯标给的是「局部安全区」，不是清图——Ⅷ 常驻溟痕下存量 25–30 属预期；加强用的旋钮 clear_all_r / block_r 缺省关闭。
## 状态存在 g.beacons（world / hud 画面读）：{pos, lit, prog, need, lit_t, count_end, count_max, r, clear_r, safe_end, dead}；
## count_end / count_max 为点燃读条（界面与美术的通用倒计时环可直接吃）。旋钮 balance.json beacon 段，beacon/enabled = 0 关闭。

const UI = preload("res://scripts/ui.gd")
const Bal = preload("res://scripts/core/balance.gd")

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game

var next_at := -1.0      # 下一座灯标的刷新时刻（< 0：自然溟痕还没开始）
var charging = null      # 本帧主控正在读条的那座灯标（未点燃、主控在光圈内、进度在涨）；圈内安全读它（docs/49g）
var lit_n := 0           # 本局点燃数（平衡输出）
var spawned_n := 0


func _init(game: Game) -> void:
	g = game


func _k(key: String, d: float) -> float:
	return Bal.v("beacon/" + key, d)


func update(dt: float) -> void:
	charging = null
	if _k("enabled", 1.0) <= 0.0 or g.demo_op != "" or g.trial.active:
		return
	# 自动测试：每 60 秒记一次场上溟痕数（溟痕存量）
	if g.mode != g.Mode.PLAY and int(g.t / 60.0) != int((g.t - dt) / 60.0):
		_log("mires")
	if next_at < 0.0:
		var first: float = float(g.map.mire_cfg().get("first_at", 100.0))
		if g.t < first:
			return
		next_at = g.t + g.rng.randf_range(_k("every_min", 60.0), _k("every_max", 75.0)) * float(g.dmod.get("beacon_every", 1.0))
	# 刷新：场上最多 1 座未点燃；Boss 在场时照样刷（协调人 9/29：Boss 战正是溟痕最多、最需要安全区的时候）
	if g.t >= next_at:
		next_at = g.t + g.rng.randf_range(_k("every_min", 60.0), _k("every_max", 75.0)) * float(g.dmod.get("beacon_every", 1.0))
		if not g.beacons.any(func(b): return not b.lit):
			_spawn()
	var r: float = _k("r", 70.0)
	for b in g.beacons:
		# 缩圈把灯标卷到圈外：熄灭消失
		if g.zone_state != 0 and b.pos.distance_to(g.zone_c) > g.zone_r:
			b.dead = true
			g.vfx.sparks(b.pos, Vector2.UP, Color(0.6, 0.7, 0.8), 8, 90.0)
			continue
		if b.lit:
			if g.t - b.lit_t > _k("block_t", 30.0):
				b.dead = true   # 禁刷期结束，灯标完成使命
				Sfx.play("beacon_end", -11.7, 1.0, 0.0)   # 安全区结束（tools/gen_sfx_events.py）
			continue
		# 没点燃的灯标 unlit_life 秒后熄灭，放行下一座（协调人 9/30 定 A：原来没人点的那座一直占位，普通机器人整局只刷 1–3 座）
		b.age = float(b.get("age", 0.0)) + dt
		if b.age > _k("unlit_life", 45.0):
			b.dead = true
			g.vfx.sparks(b.pos, Vector2.UP, Color(0.6, 0.7, 0.8), 8, 90.0)
			Sfx.play("beacon_fizzle", -4.3 if b.pos.distance_to(g.ppos) < 560.0 else -10.3, 1.0, 0.0)   # 没点燃熄灭：噗噗几下 + 嘶声，无音调（和安全区结束的两音下行区分）
			# 熄灭提示（别让玩家以为是 bug）：在屏内就在灯标上飘字，在屏外弹一句横幅
			if b.pos.distance_to(g.ppos) < 560.0:
				g.vfx.add_text(b.pos + Vector2(0, -70), "引航灯标熄灭了", Color(0.7, 0.78, 0.85), 15)
			else:
				g.vfx.show_banner("远处的引航灯标熄灭了 —— 稍后会有新的一座")
			_log("expire")
			continue
		var rate := 1.0
		if g.lamp < 30.0:
			rate /= _k("low_lamp_mult", 1.5)
		if g.squad.in_sanctuary(b.pos):
			rate *= _k("lumen_mult", 2.0)
		if b.pos.distance_to(g.ppos) < r and g.state == g.S.PLAY:
			charging = b
			b.out_t = 0.0
			b.prog = minf(b.need, b.prog + rate * dt)
			b.count_max = b.need
			b.count_end = g.t + (b.need - b.prog) / rate
			# 进度嘀嗒：每 0.5 秒进度一声，音高随进度升高（回退后重新充能会再响）
			var tk := int(b.prog / 0.5)
			if tk > int(b.get("tick", 0)) and b.prog < b.need:
				Sfx.play("beacon_tick", -12.0, 0.85 + 0.5 * b.prog / b.need, 0.0)
			b["tick"] = tk
			if b.prog >= b.need:
				_light(b)
		else:
			# 离开时不清零：先保持 beacon/decay_delay 秒，之后每秒回退需要量的 beacon/decay_pct（缺省 0 / 0.2 = 离开就按 0.5 秒/秒退，docs/49f ①）
			b.out_t = float(b.get("out_t", 0.0)) + dt
			if b.out_t >= _k("decay_delay", 0.0):
				b.prog = maxf(0.0, b.prog - b.need * _k("decay_pct", 0.2) * dt)
			b.count_end = 0.0
			b["tick"] = int(b.prog / 0.5)
	g.beacons = g.beacons.filter(func(b): return not b.dead)


## 选址：主控 250–400 的环上取 16 方向 × 3 半径的候选点（圈内），挑 clear_r 内非 Boss 溟痕最多的那个
## （协调人 9/29：灯标同时是「溟痕在哪」的指路标）；一块都罩不到时退回随机方向。随机数先取、次数固定，保证同 seed 可复现
func _spawn() -> void:
	var ang := g.rng.randf() * TAU
	var p: Vector2 = g.ppos + Vector2.from_angle(ang) * g.rng.randf_range(_k("dist_min", 250.0), _k("dist_max", 400.0))
	var cr: float = _k("clear_r", 260.0)
	var best_n := 0
	for k in 16:
		for rr in [_k("dist_min", 250.0), (_k("dist_min", 250.0) + _k("dist_max", 400.0)) * 0.5, _k("dist_max", 400.0)]:
			var q: Vector2 = g.spawner.safe_event_pos(g.ppos + Vector2.from_angle(ang + TAU * k / 16.0) * rr, 110.0)
			var n := 0
			for m in g.mires:
				if not m.get("boss", false) and m.life > 0.0 and m.pos.distance_to(q) < cr:
					n += 1
			if n > best_n:
				best_n = n
				p = q
	p = g.spawner.safe_event_pos(p, 110.0)
	g.beacons.append({"pos": p, "lit": false, "prog": 0.0, "need": _k("need", 2.5), "lit_t": -1.0, "count_end": 0.0, "count_max": 0.0, "dead": false,
		"r": _k("r", 70.0), "clear_r": _k("clear_r", 260.0), "safe_end": 0.0, "age": 0.0, "out_t": 0.0})
	spawned_n += 1
	g.vfx.show_banner("引航灯标出现了 —— 站进光圈点燃它，驱散溟痕")
	_log("spawn")


func _light(b: Dictionary) -> void:
	b.lit = true
	b.lit_t = g.t
	b.safe_end = g.t + _k("block_t", 30.0)
	b.count_end = 0.0
	lit_n += 1
	# beacon/clear_all_r（缺省 0 = 关）：> 0 时点燃清痕半径改用它（取两者较大者），留给真人反馈后加强用（协调人 9/30 ①）
	var cr: float = maxf(_k("clear_r", 260.0), _k("clear_all_r", 0.0))
	var cleared := 0
	var cleared_pts: Array = []   # 被清掉的溟痕 [pos, r]：只给画面用（world.beacon_burst 的退散动画，docs/54），不影响模拟
	for m in g.mires:
		if m.pos.distance_to(b.pos) > cr:
			continue
		if m.get("boss", false):
			m.life = minf(m.life, _k("boss_life", 2.0))   # Boss 溟痕属于招式：只缩短剩余寿命，不删
		else:
			m.life = 0.0
			cleared += 1
			cleared_pts.append([m.pos, float(m.r)])
	b["cleared"] = cleared_pts
	if cleared > 0:
		Sfx.play("mire_clear", -10.2, 1.0, 0.0)   # 清掉溟痕：溶解嘶声，叠在点亮光爆下（tools/gen_sfx_events.py）
	g.lamp = minf(g.lamp_cap, g.lamp + _k("lamp", 5.0))
	clear_nerve(b.pos, _k("r", 70.0))
	# 点燃光爆（爆闪、扩到 clear_r 的光环、放射光、火花）由界面与美术画（lit 由 false 变 true 那一帧），这里只留飘字
	g.vfx.add_text(b.pos + Vector2(0, -70), "引航灯标已点亮 · 灯火 +%d" % int(_k("lamp", 5.0)), UI.GOLD, 16)
	Sfx.play("beacon_lit", 1.4, 1.0, 0.0)   # 点燃光爆
	_log("lit cleared=%d" % cleared)


## ---- 圈内安全（docs/49g，协调人 10-01 定候选 e；三个旋钮缺省 0 = 关，可按档开：difficulty/<档>/beacon_safe_* ≥ 0 时优先）
## 只在读条期间（charging）生效，只作用于非 Boss 的敌人与子弹；Boss 的预警、子弹、冲锋照常
func _sk(key: String) -> float:
	var v := float(g.dmod.get("beacon_" + key, -1.0))
	return v if v >= 0.0 else _k(key, 0.0)


## 非 Boss 子弹 / 抛石进入正在读条的光圈：被灯光吞掉（beacon/safe_bullet）
func bullet_eaten(pos: Vector2) -> bool:
	return charging != null and _sk("safe_bullet") > 0.0 and g.combat.ground_d(pos, charging.pos) < float(charging.r)


## 远程杂兵不对正在读条的主控发起新的远程出招（beacon/safe_ranged）；调用方不推进冷却，出圈即恢复
func ranged_held(e: Dictionary) -> bool:
	return charging != null and not e.get("boss", false) and _sk("safe_ranged") > 0.0


## 读条期间光圈附近的杂兵减速（beacon/safe_slow = 减少量，如 0.4 = −40%）并且不起冲刺；对照组用
func slow_mult(e: Dictionary) -> float:
	if charging == null or e.get("boss", false):
		return 1.0   # 每只敌人每帧都调：没有灯标在读条就不查旋钮（docs/50 §9.11 ①）
	var k: float = _sk("safe_slow")
	if k <= 0.0:
		return 1.0
	return 1.0 - k if g.combat.ground_d(e.pos, charging.pos) < float(charging.r) + float(e.r) + 30.0 else 1.0


## 子弹被吞的画面：暖色小光环 + 几点光屑（走 g.fx / sparks 现有合批，标 enemy 不被降噪），真人才看得出「圈里没中弹」是灯的作用
func eat_fx(pos: Vector2) -> void:
	g.fx.append({"kind": "ring", "pos": pos, "r": 9.0, "life": 0.22, "max": 0.22, "col": Color(1.8, 1.45, 0.7), "enemy": true})
	g.vfx.sparks(pos, Vector2.UP, Color(1.9, 1.5, 0.8), 3, 70.0)


## 点燃时清空神经损伤：主控，以及站在光圈内、自己带神经损伤字段的队友（Boss与怪物 加回神经损伤后按它的字段接）
func clear_nerve(at: Vector2, r: float) -> void:
	g.nerve = 0.0
	for o in g.squad.ops:
		if o.get("nerve") != null and o.pos != Vector2.INF and o.pos.distance_to(at) < r:
			o.set("nerve", 0.0)


## map.mire_new 落点检查：点燃的灯标周围禁刷期内不生成自然溟痕
func blocks(p: Vector2) -> bool:
	# beacon/block_r（缺省 0 = 关）：> 0 时禁刷半径改用它（取与清痕半径的较大者），同上留作旋钮
	var cr: float = maxf(maxf(_k("clear_r", 260.0), _k("clear_all_r", 0.0)), _k("block_r", 0.0))
	for b in g.beacons:
		if b.lit and g.t - b.lit_t <= _k("block_t", 30.0) and b.pos.distance_to(p) < cr:
			return true
	return false


## 占位画面（地面层，world.draw_world 在溟痕之后调用）：熄灭 = 灰圈 + 进度环；点燃 = 暖光圈 + 清净区边界。正式贴图由界面与美术出
func draw() -> void:
	var r: float = _k("r", 70.0)
	for b in g.beacons:
		g.draw_set_transform(b.pos, 0.0, Vector2(1.0, 0.5))
		if b.lit:
			var a: float = 0.35 + 0.1 * sin(g.t * 3.0)
			g.draw_circle(Vector2.ZERO, r, Color(1.0, 0.85, 0.5, 0.18))
			g.draw_arc(Vector2.ZERO, _k("clear_r", 260.0), 0.0, TAU, 64, Color(1.0, 0.85, 0.5, a * 0.6), 2.0)
		else:
			g.draw_circle(Vector2.ZERO, r, Color(0.5, 0.6, 0.7, 0.12))
			g.draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(0.7, 0.8, 0.9, 0.5), 2.0)
			if b.prog > 0.0:
				g.draw_arc(Vector2.ZERO, r, -PI / 2.0, -PI / 2.0 + TAU * b.prog / b.need, 48, Color(1.0, 0.85, 0.5, 0.95), 5.0)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# 灯柱本体（占位）：一根竖条 + 顶端灯
		var top: Vector2 = b.pos + Vector2(0, -46)
		g.draw_rect(Rect2(b.pos + Vector2(-4, -44), Vector2(8, 44)), Color(0.25, 0.28, 0.32))
		g.draw_circle(top, 9.0, Color(1.0, 0.85, 0.5) if b.lit else Color(0.35, 0.4, 0.45))


func _log(what: String) -> void:
	if g.mode != g.Mode.PLAY:
		print("BEACON %s t=%.1f mires=%d" % [what, g.t, g.mires.size()])
