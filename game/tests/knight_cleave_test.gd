extends Node
## 骑士弧斩 v2（断潮劈击，11-01 用户「现在也打不到人，前摇太长」）：同一招在旧版 / v2 下，对站桩、横移、后撤、横移 + 冲刺躲四种队长，
## 各在离骑士 120 / 260 / 420 处起步，数弧刃真正扫中（冲刺无敌窗口外）的次数。
## 要求：v2 总命中明显多于旧版；会冲刺的队长在 v2 下仍能全部躲开（冲刺冷却 0.6、无敌 0.2，弧刃贴近 70 内才冲）。
## godot --headless --path game res://tests/knight_cleave_test.tscn
## 全部通过时打印 "KNIGHT CLEAVE failures=0"
const Bal = preload("res://scripts/core/balance.gd")

var g
var failures := 0


func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func _ready() -> void:
	g = load("res://game.tscn").instantiate()
	g.demo_op = "mizuki"
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	var total := {0: 0, 1: 0}
	var dash_hits := {0: 0, 1: 0}
	var stand_hits := {0: 0, 1: 0}
	for v in [0, 1]:
		Bal.sec("boss")["knight_cleave_v2"] = v
		for dist in [120.0, 260.0, 420.0]:
			for mode in ["stand", "strafe", "kite", "dash"]:
				var r: Array = run(dist, mode)
				print("CLEAVE v2=%d D=%d %s hits=%d/%d" % [v, int(dist), mode, r[0], r[1]])
				total[v] += r[0]
				if mode == "dash":
					dash_hits[v] += r[0]
				if mode == "stand":
					stand_hits[v] += r[0]
	Bal.sec("boss")["knight_cleave_v2"] = 1
	print("CLEAVE total old=%d v2=%d  dash old=%d v2=%d" % [total[0], total[1], dash_hits[0], dash_hits[1]])
	check(total[1] >= total[0] + 4, "v2 命中明显多于旧版（%d vs %d）" % [total[1], total[0]])
	check(stand_hits[1] >= 3, "v2 站在 260 / 420 会被扫中（贴身 120 是安全空心）（%d）" % stand_hits[1])
	check(dash_hits[1] == 0, "v2 会冲刺的队长仍能全部躲开（%d）" % dash_hits[1])
	print("KNIGHT CLEAVE failures=", failures)
	g.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if failures else 0)


func fresh() -> Dictionary:
	g.warns.clear()
	g.bai.finals.hazards.clear()
	g.enemies.clear()
	g.fx.clear()
	g.ebullets.clear()
	g.bai.token_owner = null
	var e: Dictionary = g.spawner.new_enemy("knight_boss", Vector2.ZERO)
	e.phase = 1
	e.age = 20.0
	e.invuln = false
	e.channel = 0.0
	e.stakes = [{"pos": Vector2(2000, 2000), "born": 0.0, "until": INF}]
	g.bosses = [e]
	g.boss = e
	g.final_boss = e
	g.enemies.append(e)
	return e


## 返回 [冲刺无敌窗口外扫中的弧刃数, 弧刃总数]
func run(dist: float, mode: String) -> Array:
	var e: Dictionary = fresh()
	g.t = 100.0
	g.ppos = Vector2(dist, 0)
	g.pvel = Vector2.ZERO
	var dt := 1.0 / 60.0
	g.bai.boss("knight_boss").force_move(e, "断潮劈击", Vector2.RIGHT, dist)
	var seen: Array = []
	var hit_ids: Array = []
	var hits := 0
	var dash_cd := 0.0
	var iframe := 0.0
	var side := Vector2.DOWN
	for i in int(3.6 / dt):
		g.t += dt
		g.invuln = 999.0
		e.wind = maxf(0.0, e.wind - dt)
		e.stun = maxf(0.0, e.stun - dt)
		e.kb = Vector2.ZERO
		e.pos = Vector2.ZERO   # 只看弧刃：别让连段里的冲锋把骑士带走
		dash_cd = maxf(0.0, dash_cd - dt)
		iframe = maxf(0.0, iframe - dt)
		var mv := Vector2.ZERO
		match mode:
			"strafe", "dash":
				mv = side
			"kite":
				mv = (g.ppos - e.pos).normalized()
		if absf(g.ppos.y) > 260.0:
			side = Vector2(0, -signf(g.ppos.y))
		g.pvel = mv * g.speed
		g.ppos += g.pvel * dt
		if mode == "dash" and dash_cd <= 0.0:
			for h in g.bai.finals.hazards:
				if h.get("motion", "") == "crescent" and not h.hit and _arc_gap(h) < 70.0:
					iframe = 0.2
					dash_cd = 0.6
					break
		g.bai.boss_step(e, dt, (g.ppos - e.pos).normalized(), g.ppos.distance_to(e.pos))
		g.tele.update_warns(dt)
		for h in g.bai.finals.hazards:
			if h.get("motion", "") != "crescent":
				continue
			if not seen.any(func(o): return is_same(o, h)):
				seen.append(h)
			if h.hit and not hit_ids.any(func(o): return is_same(o, h)):
				hit_ids.append(h)
				if iframe <= 0.0:
					hits += 1
	return [hits, seen.size()]


## 队长到弧刃的距离（同 telegraph.hits_leader 的弧形最近点）
func _arc_gap(h: Dictionary) -> float:
	var pp: Vector2 = g.ppos + Vector2(0, -14)
	var center: Vector2 = h.pos - Vector2.from_angle(h.ang) * float(h.get("arc_back", 0.0))
	var off := clampf(angle_difference(h.ang, (pp - center).angle()), -float(h.half), float(h.half))
	return (center + Vector2.from_angle(h.ang + off) * h.r).distance_to(pp) - float(h.wid)
