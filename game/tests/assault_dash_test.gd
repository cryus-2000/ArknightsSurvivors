extends Node
## 10-26 突击模式低频自冲刺（docs/159）：随行时队友不自己冲；切「突击」后每名出击队友每 command/roam_dash_cd 秒冲一次（德克萨斯走自己的带伤害冲刺，更勤）；
## 切回随行后又不冲。godot --headless --path game res://tests/assault_dash_test.tscn -- --regression --balance --seed=1 --op=skadi --squad=texas,lappland
## 全部通过时打印 "ASSAULT DASH checks=N failures=0"

var checks := 0
var failures := 0


func ok(v: bool, what: String) -> void:
	checks += 1
	if not v:
		failures += 1
		printerr("FAIL: ", what)


func _ready() -> void:
	var g = load("res://game.tscn").instantiate()
	add_child(g)
	for i in 5: await get_tree().process_frame
	g.set_process(false)
	g.mode = g.Mode.PLAY
	g.state = g.S.PLAY
	g.sandbox = true
	g.t = 60.0
	g.xp_need = 1000000000.0
	for e in g.enemies: e.dead = true
	g.enemies.clear()
	var tx = g.squad.get_op("texas")
	var lap = g.squad.get_op("lappland")
	ok(tx != null and lap != null, "队友在编队里")
	var foes: Array = []
	for k in 8:
		var e: Dictionary = g.spawner.spawn_enemy("bone", g.ppos + Vector2(240.0 + 40.0 * (k % 4), -90.0 + 60.0 * (k / 2)))
		e.hp = 1.0e9
		e.maxhp = 1.0e9
		e.spd = 0.0
		foes.append(e)
	var dt := 1.0 / 60.0
	var tx_dash := 0
	var lap_rush := 0
	var tx_was := false
	var lap_was := false
	var phase_counts := {}
	for frame in int(46.0 / dt):
		var t := frame * dt
		var phase: int = 0 if t < 12.0 else (1 if t < 32.0 else 2)   # 0 随行 / 1 突击 / 2 随行
		if frame == int(12.0 / dt):
			g.squad.set_stance(g.squad.ROAM)
		if frame == int(32.0 / dt):
			g.squad.set_stance(g.squad.GUARD)
		g.hp = g.max_hp
		g.move_in = Vector2.ZERO
		for k in foes.size():
			foes[k].hp = 1.0e9
			if frame % 30 == 0:   # 每 0.5 秒把敌人挪回队长身前 260 的弧上（实机里敌人是不断涌来的）
				foes[k].pos = g.ppos + Vector2.from_angle(-0.9 + 1.8 * float(k) / 7.0) * 260.0
		if frame == int(22.0 / dt):   # 定点验证低频自冲刺：清场，只留一只离拉普兰德约 200–300 远、仍在队长活动圈内的敌人，把她的自冲刺计时拨到 0
			for e in foes:
				e.dead = true
			foes.clear()
			var lone: Dictionary = g.spawner.spawn_enemy("bone", g.ppos + Vector2(-60.0 if lap.pos.x > g.ppos.x + 100.0 else 330.0, 0.0))
			lone.hp = 1.0e9
			lone.maxhp = 1.0e9
			lone.spd = 0.0
			foes.append(lone)
			lap._roam_dash_t = 0.0
			lap.rush_t = 0.0
		g.enemies_sys.build_grid()
		g._update(dt)
		if frame == int(22.0 / dt) + 2:
			ok(lap.rush_t > 0.0 or lap_was, "到点且 200 外有敌人：突击中的队友自冲刺")
			ok(lap._roam_dash_t > 5.0, "自冲刺后计时重置为约 command/roam_dash_cd（7 秒）：%s" % lap._roam_dash_t)
		var txd: bool = tx.tx.has("dash")
		if txd and not tx_was:
			phase_counts[["tx", phase]] = int(phase_counts.get(["tx", phase], 0)) + 1
		tx_was = txd
		var lr: bool = lap.rush_t > 0.0
		if lr and not lap_was:
			phase_counts[["lap", phase]] = int(phase_counts.get(["lap", phase], 0)) + 1
		lap_was = lr
	var c := func(who: String, ph: int) -> int: return int(phase_counts.get([who, ph], 0))
	print("DASH COUNTS tx=", [c.call("tx", 0), c.call("tx", 1), c.call("tx", 2)], " lap=", [c.call("lap", 0), c.call("lap", 1), c.call("lap", 2)])
	ok(c.call("tx", 0) == 0 and c.call("lap", 0) == 0, "随行时队友不自己冲")
	ok(c.call("tx", 2) == 0 and c.call("lap", 2) == 0, "切回随行后不再自己冲")
	ok(c.call("tx", 1) >= 1, "突击中德克萨斯自己冲刺（带伤害，来源突进）")
	ok(c.call("lap", 1) >= 2, "突击中其他队友冲刺（切突击那一下 + 到点自冲刺）")
	ok(c.call("lap", 1) <= 4, "突击中其他队友冲刺是低频（20 秒内不超过 4 次）")
	ok(c.call("tx", 1) <= 6, "德克萨斯冲刺频率有上限（20 秒内不超过 6 次）")
	print("ASSAULT DASH checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
