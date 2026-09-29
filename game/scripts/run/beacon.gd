extends RefCounted
## 引航灯标（名字文案暂定；docs/49d §13.5 方案 C，用户 9/29 定）：溟痕的主动清理手段，只靠走位。
## 自然溟痕出现后，每 60–75 秒在主控 250–400 外（缩圈后只刷在圈内）立一座熄灭的灯标，场上最多 1 座未点燃；
## 主控站进半径 70 的光圈累计 2.5 秒点燃（离开时进度缓慢回退，不清零）。
## 点燃：清除半径 260 内的自然 / 小怪溟痕（Boss 溟痕只把剩余寿命缩到 ≤ 2 秒，不删），这片区域 30 秒内不再生成自然溟痕
## （map.mire_new 落点检查 blocks()），灯标亮着当安全区标记，+5 灯火；同时清空主控与光圈内队友的神经损伤。
## 联动：灯火 < 30 时点燃时间 ×1.5；流明灯塔区覆盖灯标时点燃速度 ×2；缩圈把灯标卷到圈外即熄灭消失。
## 状态存在 g.beacons（world / hud 画面读）：{pos, lit, prog, need, lit_t, count_end, count_max, r, clear_r, safe_end, dead}；
## count_end / count_max 为点燃读条（界面与美术的通用倒计时环可直接吃）。旋钮 balance.json beacon 段，beacon/enabled = 0 关闭。

const UI = preload("res://scripts/ui.gd")
const Bal = preload("res://scripts/core/balance.gd")

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game

var next_at := -1.0      # 下一座灯标的刷新时刻（< 0：自然溟痕还没开始）
var lit_n := 0           # 本局点燃数（平衡输出）
var spawned_n := 0


func _init(game: Game) -> void:
	g = game


func _k(key: String, d: float) -> float:
	return Bal.v("beacon/" + key, d)


func update(dt: float) -> void:
	if _k("enabled", 1.0) <= 0.0 or g.demo_op != "" or g.trial.active:
		return
	# 自动测试：每 60 秒记一次场上溟痕数（溟痕存量）
	if g.autotest and int(g.t / 60.0) != int((g.t - dt) / 60.0):
		_log("mires")
	if next_at < 0.0:
		var first: float = float(g.map.mire_cfg().get("first_at", 100.0))
		if g.t < first:
			return
		next_at = g.t + g.rng.randf_range(_k("every_min", 60.0), _k("every_max", 75.0))
	# 刷新：场上最多 1 座未点燃；Boss 在场时不刷（和围猎、祭坛一样不叠在 Boss 战里）
	if g.t >= next_at:
		next_at = g.t + g.rng.randf_range(_k("every_min", 60.0), _k("every_max", 75.0))
		if not g.beacons.any(func(b): return not b.lit) and not g.spawner.boss_alive():
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
			continue
		var rate := 1.0
		if g.lamp < 30.0:
			rate /= _k("low_lamp_mult", 1.5)
		if g.squad.in_sanctuary(b.pos):
			rate *= _k("lumen_mult", 2.0)
		if b.pos.distance_to(g.ppos) < r and g.state == g.S.PLAY:
			b.prog = minf(b.need, b.prog + rate * dt)
			b.count_max = b.need
			b.count_end = g.t + (b.need - b.prog) / rate
			if b.prog >= b.need:
				_light(b)
		else:
			b.prog = maxf(0.0, b.prog - _k("decay", 0.5) * dt)   # 离开时缓慢回退，不清零
			b.count_end = 0.0
	g.beacons = g.beacons.filter(func(b): return not b.dead)


func _spawn() -> void:
	var ang := g.rng.randf() * TAU
	var p: Vector2 = g.ppos + Vector2.from_angle(ang) * g.rng.randf_range(_k("dist_min", 250.0), _k("dist_max", 400.0))
	p = g.spawner.safe_event_pos(p, 110.0)
	g.beacons.append({"pos": p, "lit": false, "prog": 0.0, "need": _k("need", 2.5), "lit_t": -1.0, "count_end": 0.0, "count_max": 0.0, "dead": false,
		"r": _k("r", 70.0), "clear_r": _k("clear_r", 260.0), "safe_end": 0.0})
	spawned_n += 1
	g.vfx.show_banner("引航灯标出现了 —— 站进光圈点燃它，驱散溟痕")
	_log("spawn")


func _light(b: Dictionary) -> void:
	b.lit = true
	b.lit_t = g.t
	b.safe_end = g.t + _k("block_t", 30.0)
	b.count_end = 0.0
	lit_n += 1
	var cr: float = _k("clear_r", 260.0)
	var cleared := 0
	for m in g.mires:
		if m.pos.distance_to(b.pos) > cr:
			continue
		if m.get("boss", false):
			m.life = minf(m.life, _k("boss_life", 2.0))   # Boss 溟痕属于招式：只缩短剩余寿命，不删
		else:
			m.life = 0.0
			cleared += 1
	g.lamp = minf(g.lamp_cap, g.lamp + _k("lamp", 5.0))
	clear_nerve(b.pos, _k("r", 70.0))
	# 点燃光爆（爆闪、扩到 clear_r 的光环、放射光、火花）由界面与美术画（lit 由 false 变 true 那一帧），这里只留飘字
	g.vfx.add_text(b.pos + Vector2(0, -70), "引航灯标已点亮 · 灯火 +%d" % int(_k("lamp", 5.0)), UI.GOLD, 16)
	Sfx.play("relic", -4.0, 1.2, 0.0)
	_log("lit cleared=%d" % cleared)


## 点燃时清空神经损伤：主控，以及站在光圈内、自己带神经损伤字段的队友（Boss与怪物 加回神经损伤后按它的字段接）
func clear_nerve(at: Vector2, r: float) -> void:
	g.nerve = 0.0
	for o in g.squad.ops:
		if o.get("nerve") != null and o.pos != Vector2.INF and o.pos.distance_to(at) < r:
			o.set("nerve", 0.0)


## map.mire_new 落点检查：点燃的灯标周围禁刷期内不生成自然溟痕
func blocks(p: Vector2) -> bool:
	var cr: float = _k("clear_r", 260.0)
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
	if g.autotest:
		print("BEACON %s t=%.1f mires=%d" % [what, g.t, g.mires.size()])
