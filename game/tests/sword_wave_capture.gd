extends Node
## 剑气非线性速度改前 / 改后对照（用户 10-27，sword_ease.gd）：tools/sword_wave_rec.py 调。
##   --sw_case=lap | qi   --sw_out=<目录>（不给 = 不截图，只计数）   --sw_frames=N   另带 --bal=sword_ease/on=0|1 切改前 / 改后
## lap = 拉普兰德本人（敌人站在横扫触及外，走「领主」远掷剑气）；qi = 德克萨斯 + 锈蚀刀片 + 老近卫军之锋（可见成长近战剑气）。
## 同 seed、同一组敌人、同帧数，两次的第 k 帧可直接左右拼；结束时打印命中次数与总伤害（判定不变的对照）。

const DT := 1.0 / 60.0
const CASES := {
	"lap": {"op": "lappland", "relics": [], "d": [190.0, 250.0]},
	"qi": {"op": "texas", "relics": ["63", "56"], "d": [120.0, 210.0]},
}


func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + k + "="):
			return a.substr(k.length() + 3)
	return d


func _ready() -> void:
	var cs: String = _arg("sw_case", "lap")
	var out: String = _arg("sw_out", "")
	var frames: int = int(_arg("sw_frames", "120"))
	if out != "":
		DirAccess.make_dir_recursive_absolute(out)
	var g = load("res://game.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	g.state = g.S.PLAY
	g.t = 60.0
	g.invuln = 1.0e9
	g.xp_need = 1.0e12
	var c: Dictionary = CASES[cs]
	var o = g.squad.get_op(str(c.op))
	o.sp = [-1.0e9, -1.0e9, -1.0e9]
	for e in g.enemies:
		e.dead = true
	g.enemies.clear()
	var ctr: Vector2 = g.ppos
	o.pos = ctr
	var es: Array = []
	var n_e: int = int(_arg("sw_n", "9"))   # --sw_n=100：同屏 100 只的帧时对照（多出的按圈排开）
	for k in n_e:
		var ang: float = -0.9 + 0.45 * (k % 5) + (0.2 if k >= 5 else 0.0) if k < 9 else float(k) * 0.61
		var d: float = (float(c.d[0]) if k < 5 else float(c.d[1])) if k < 9 else 120.0 + float(k % 7) * 30.0
		var e: Dictionary = g.spawner.spawn_enemy("stone", ctr + Vector2.from_angle(ang) * d)
		e.hp = 1.0e9
		e.max_hp = 1.0e9
		es.append(e)
	var p0: Array = es.map(func(e): return e.pos)
	g.enemies_sys.build_grid()
	for id in c.relics:
		g.progression.gain_relic(id)
	var hits := 0
	var dmg := 0.0
	var first := -1
	var us := 0
	for f in frames:
		for i in es.size():
			es[i].pos = p0[i]   # 钉住不动：两次同一组落点
		g.ppos = ctr   # 队长不走、不刷别的怪
		o.pos = ctr
		for e in g.enemies:
			if not es.has(e):
				e.dead = true
		var t0 := Time.get_ticks_usec()
		g._update(DT)
		us += Time.get_ticks_usec() - t0
		if _arg("sw_dbg", "") == "2" and o.hw is Dictionary and not o.hw.get("waves", []).is_empty():
			print("W f=%d %s" % [f, o.hw.waves.map(func(w): return "%.0f" % w.dist)])
		if _arg("sw_dbg", "") == "3" and o.vg is Dictionary and not o.vg.get("qi", []).is_empty():
			print("Q f=%d %s" % [f, o.vg.qi.map(func(q): return "%.0f" % q.p.distance_to(q.o0))])
		if f % 120 == 0 and _arg("sw_dbg", "") == "1":
			print("DBG f=%d n=%d alive=%d waves=%d pos=%s e0=%s hp=%.0f dead=%s" % [f, g.enemies.size(), es.filter(func(e): return not e.dead).size(), o.hw.get("waves", []).size() if o.hw is Dictionary else -1, o.pos, es[0].pos, es[0].hp, es[0].dead])
		for e in es:
			if e.hp < 1.0e9:
				hits += 1
				dmg += 1.0e9 - e.hp
				if first < 0:
					first = f
			e.hp = 1.0e9
			e.dead = false
		if out != "":
			g.world.update_visuals(DT)
			g.world.present_step()
			g.queue_redraw()
			g.fx_add.queue_redraw()
			g.fg.queue_redraw()
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out.path_join("%s_%03d.png" % [cs, f]))
	print("SW COUNT %s frames=%d hit_frames=%d dmg=%.1f first=%d update_ms=%.3f" % [cs, frames, hits, dmg, first, us / 1000.0 / frames])
	print("SW CAPTURE done %s" % cs)
	get_tree().quit(0)
