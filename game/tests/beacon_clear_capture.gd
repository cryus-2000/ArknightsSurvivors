extends Node
## 灯标驱散溟痕对照录像（10-26 用户「灯塔范围内的溟痕全部消失」）：队长站在灯标上，周围铺一圈自然溟痕（含压在清除圈边上的大片）、
## 一片怪物溟痕、一片 Boss 溟痕；第 0.5 秒点燃；1.4 秒在圈内补一片怪物死亡溟痕，并把灯火压到 10 让圈外溟痕向队长逼近（docs/147），
## 看生效期间圈内是否还会出现溟痕。逐帧存 PNG（每 2 帧一张）→ build/<--capture-out>/f_####.png，log.json 记圈内溟痕数。

var g


func _ready() -> void:
	var out_dir := "beacon_clear"
	var secs := 4.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-out="):
			out_dir = arg.get_slice("=", 1)
	var output := ProjectSettings.globalize_path("res://../build/" + out_dir)
	DirAccess.make_dir_recursive_absolute(output)
	g = load("res://game.tscn").instantiate()
	add_child(g)
	for i in 5:
		await get_tree().process_frame
	g.set_process(false)
	g.state = g.S.PLAY
	g.sandbox = true
	g.t = 200.0
	g.xp_need = 1000000000.0
	for e in g.enemies:
		e.dead = true
	g.enemies.clear()
	g.mires.clear()
	g.beacons.clear()
	var c: Vector2 = g.ppos
	var cr: float = float(g.beacon_sys._k("clear_r", 260.0))
	# 自然溟痕：四圈，最外一圈中心在清除圈外、边压进圈里
	var k := 0
	for ring in [[110.0, 5, 70.0], [210.0, 7, 80.0], [300.0, 9, 75.0], [cr + 50.0, 10, 90.0], [cr + 170.0, 8, 85.0]]:
		for j in int(ring[1]):
			var p: Vector2 = c + Vector2.from_angle(TAU * j / float(ring[1]) + k * 0.4) * float(ring[0])
			g.mires.append({"pos": p, "r": float(ring[2]), "maxr": float(ring[2]), "life": 9999.0, "seed": 3.1 + j + k * 7.0})
		k += 1
	g.combat.add_enemy_mire({"pos": c + Vector2(150, -60), "r": 50.0, "maxr": 50.0, "life": 12.0, "seed": 5.5, "boss": false}, "death")
	g.mires.append({"pos": c + Vector2(-190, 90), "r": 60.0, "maxr": 60.0, "life": 9.0, "seed": 8.8, "boss": true})
	var b := {"pos": c, "lit": false, "prog": 0.0, "need": 2.5, "lit_t": -1.0, "count_end": 0.0, "count_max": 0.0, "dead": false,
		"r": 70.0, "clear_r": cr, "safe_end": 0.0, "age": 0.0, "out_t": 0.0, "min_d": INF, "hold_s": 0.0, "guide_r": 0.0, "guide_life": 45.0,
		"in_s": 0.0, "maxp": 0.0}
	g.beacons.append(b)
	var dt := 1.0 / 60.0
	var log := []
	for frame in int(secs / dt):
		var t := frame * dt
		g.hp = g.max_hp
		g.move_in = Vector2.ZERO
		if frame == 30:
			g.beacon_sys._light(b)
		if frame == 84:
			g.combat.add_enemy_mire({"pos": c + Vector2(-80, -120), "r": 40.0, "maxr": 60.0, "life": 12.0, "seed": 9.9, "boss": false}, "death")
			g.lamp = 10.0   # 灯火低：圈外溟痕向队长逼近（docs/147）
		g.enemies_sys.build_grid()
		g._update(dt)
		g.world.update_visuals(dt)
		g.world.present_step()
		var inside := 0
		for m in g.mires:
			if m.life > 0.0 and not m.has("fade") and m.pos.distance_to(c) - float(m.r) < cr and not m.get("boss", false):
				inside += 1
		log.append({"f": frame, "t": snappedf(t, 0.01), "inside": inside, "n": g.mires.size()})
		if frame % 2 != 0:
			continue
		g.queue_redraw()
		g.fx_add.queue_redraw()
		g.fg.queue_redraw()
		g.hud.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output.path_join("f_%04d.png" % frame))
	var file := FileAccess.open(output.path_join("log.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(log))
	file.close()
	print("BEACON CLEAR CAPTURE done")
	get_tree().quit(0)
