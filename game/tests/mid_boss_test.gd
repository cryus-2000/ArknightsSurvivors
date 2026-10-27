extends Node
## 塑路者 / 接潮组弹幕与连段回归（docs/170）：两幕各自的两套图案逐拍交替、连段 ≤4 段且以破绽收尾、打断清队列、
## 镜像弹关于两体中垂线对称、二幕冲撞留弹、同 seed 两次逐值一致。走正式 enemies_sys.update + shots + telegraph，队长无敌、绕圈跑
var g
var failures := 0
const DT := 1.0 / 30.0
var chase := false   # 输出窗口探针：队长追着 Boss 打，tick 不改队长位置


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
	path_acts()
	path_interrupt()
	for partner in ["archon", "immortal"]:
		tide_acts(partner)
	tide_mirror()
	output_windows()
	var a: Array = path_digest()
	var b: Array = path_digest()
	check(a == b, "path same seed reproduces bullets and combos")
	var c: Array = tide_digest()
	var d: Array = tide_digest()
	check(c == d, "tide same seed reproduces bullets and combos")
	print("MID BOSS failures=", failures)
	g.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if failures else 0)


func reset() -> void:
	g.t = 200.0
	g.warns.clear()
	g.enemies.clear()
	g.fx.clear()
	g.ebullets.clear()
	g.shocks.clear()
	g.lobs.clear()
	g.bai.token_owner = null
	g.rng_enemy.seed = 1027
	g.rng.seed = 1028
	g.ppos = Vector2(260, 0)
	g.invuln = 999.0


func spawn(kind: String, at: Vector2) -> Dictionary:
	var e: Dictionary = g.spawner.new_enemy(kind, at)
	e.age = 3.0
	e.invuln = false
	e.wind = 0.0
	g.enemies.append(e)
	return e


## 一帧正式模拟；队长绕 (0,0) 半径 260 以 120 px/s 跑
func tick(stats: Dictionary) -> void:
	g.t += DT
	g.invuln = 999.0
	if not chase:
		var a: float = (g.t - 200.0) * 120.0 / 260.0
		g.ppos = Vector2(cos(a), sin(a) * 0.8) * 260.0
	g.doc_pos = g.ppos + Vector2(10, 35)
	g.enemies_sys.build_grid()
	g.enemies_sys.update(DT)
	g.shots.step(DT)
	g.tele.update_warns(DT)
	g.enemies_sys.update_status(DT)
	g.enemies = g.enemies.filter(func(o): return not o.dead or g.bosses.has(o))
	var alive := 0
	for b in g.ebullets:
		if b.life > 0.0 and b.get("mc", false):
			alive += 1
	stats.peak = maxi(int(stats.get("peak", 0)), alive)
	for e in g.bosses:
		stats.q_max = maxi(int(stats.get("q_max", 0)), int(e.get("mc_q_n", 0)))
		if str(e.get("brk_label", "")) == "收招 · 破绽" and float(e.get("break_t", 0.0)) > 0.0 and not stats.get("brk_on", false):
			stats.brk = int(stats.get("brk", 0)) + 1
		stats.brk_on = float(e.get("break_t", 0.0)) > 0.0
		var mv: String = str(e.get("move_name", ""))
		if mv != "":
			var seen: Dictionary = stats.get("moves", {})
			seen[mv] = true
			stats.moves = seen


func path_boss(p2: bool) -> Dictionary:
	reset()
	var e := spawn("path", Vector2.ZERO)
	if p2:
		g.bai.setup_preview_phase2(e)
		e.gates = []
	g.bosses = [e]
	g.boss = e
	return e


func path_acts() -> void:
	for p2 in [false, true]:
		var e := path_boss(p2)
		var st := {}
		var walls := 0
		for i in int(40.0 / DT):
			tick(st)
			for b in g.ebullets:
				if b.get("mc", false) and float(b.get("acc", 0.0)) == 90.0 and not b.get("_w", false):
					b._w = true
					walls += 1
		var mv: Dictionary = st.get("moves", {})
		var want: Array = ["回流"] if p2 else ["错误路线"]
		for m in want:
			check(mv.has(m), "path act %d shows %s" % [2 if p2 else 1, m])
		check(int(e.get("beat_n", 0)) >= 6, "path act beats alternate (%d beats)" % int(e.get("beat_n", 0)))
		check(int(st.get("q_max", 0)) >= 2 and int(st.get("q_max", 0)) <= 4, "path combo length within 2..4 (%d)" % int(st.get("q_max", 0)))
		check(int(st.get("brk", 0)) >= 1, "path combo ends in recovery")
		check(int(st.get("peak", 0)) <= 120, "path bullet peak bounded (%d)" % int(st.get("peak", 0)))
		if p2:
			check(walls >= 6, "path act 2 dash lays bullet wall (%d)" % walls)
		print("PATH act=%d peak=%d combos=%d moves=%s" % [2 if p2 else 1, int(st.get("peak", 0)), int(st.get("brk", 0)), str(mv.keys())])


func path_interrupt() -> void:
	var e := path_boss(false)
	var st := {}
	g.bai.boss("path").MC.q_start(g, e, [{"actor": e, "move": "震地"}, {"actor": e, "move": "冲撞"}], 1.2)
	tick(st)
	check(g.bai.boss("path").MC.q_active(e), "combo active after start")
	e.stun = 1.0
	tick(st)
	check(not g.bai.boss("path").MC.q_active(e), "stun clears combo queue")
	check(not g.warns.any(func(w): return is_same(w.owner, e) and not w.done and w.get("mc_combo", false)), "stun removes pending combo warnings")


func tide_pair(partner: String, p2 := false) -> Array:
	reset()
	var a := spawn("bishop", Vector2(-200, 0))
	var b := spawn(partner, Vector2(200, 0))
	a.partner = b
	b.partner = a
	if p2:
		g.bai.setup_preview_phase2(a)
		a.gates = []
	g.bosses = [a, b]
	g.boss = a
	return [a, b]


func tide_acts(partner: String) -> void:
	for p2 in [false, true]:
		var ab := tide_pair(partner, p2)
		var st := {}
		var mate_moves := 0
		for i in int(40.0 / DT):
			tick(st)
			if ab[1].get("move_t", -9.0) == g.t - DT or float(ab[1].get("move_t", -9.0)) > g.t - DT * 0.5:
				mate_moves += 1
		var mv: Dictionary = st.get("moves", {})
		for m in (["换位潮墙"] if p2 else ["镜潮", "交错潮环"]):
			check(mv.has(m), "%s act %d shows %s" % [partner, 2 if p2 else 1, m])
		check(int(st.get("q_max", 0)) >= 2 and int(st.get("q_max", 0)) <= 4, "%s pair combo length within 2..4 (%d)" % [partner, int(st.get("q_max", 0))])
		check(int(st.get("brk", 0)) >= 1, "%s pair combo ends in recovery" % partner)
		check(int(st.get("peak", 0)) <= 150, "%s bullet peak bounded (%d)" % [partner, int(st.get("peak", 0))])
		print("TIDE %s act=%d peak=%d combos=%d moves=%s" % [partner, 2 if p2 else 1, int(st.get("peak", 0)), int(st.get("brk", 0)), str(mv.keys())])


func tide_mirror() -> void:
	var ab := tide_pair("archon")
	var a: Dictionary = ab[0]
	var b: Dictionary = ab[1]
	b.pos = Vector2(200, 60)
	g.ppos = Vector2(-60, 220)
	g.bai.boss("bishop")._mirror_fan(a, b, (g.ppos - a.pos).normalized())
	g.t += 0.7
	g.bai.boss("bishop")._mirror_step(a, b)
	var la: Array = []
	var lb: Array = []
	for s in g.ebullets:
		if not s.get("mc", false):
			continue
		if int(s.source_id) == int(a.id):
			la.append(s)
		elif int(s.source_id) == int(b.id):
			lb.append(s)
	check(la.size() == 5 and lb.size() == 5, "mirror fan: 5 + 5 bullets")
	if la.size() == 5 and lb.size() == 5:
		var mid: Vector2 = (a.pos + b.pos) * 0.5
		var axis: Vector2 = (b.pos - a.pos).normalized()
		for i in 5:
			var pa: Vector2 = la[i].pos - mid
			var reflected: Vector2 = pa - 2.0 * pa.dot(axis) * axis + mid
			check(reflected.distance_to(lb[i].pos) < 1.0, "mirror fan bullet %d spawns at reflected point" % i)


func path_digest() -> Array:
	var e := path_boss(true)
	var st := {}
	for i in int(20.0 / DT):
		tick(st)
	var s := Vector2.ZERO
	for b in g.ebullets:
		if b.life > 0.0:
			s += b.pos
	return [snappedf(s.x, 0.01), snappedf(s.y, 0.01), snappedf(e.pos.x, 0.01), int(e.get("beat_n", 0)), int(st.get("brk", 0)), g.rng_enemy.state]


func tide_digest() -> Array:
	var ab := tide_pair("immortal", true)
	var st := {}
	for i in int(20.0 / DT):
		tick(st)
	var s := Vector2.ZERO
	for b in g.ebullets:
		if b.life > 0.0:
			s += b.pos
	return [snappedf(s.x, 0.01), snappedf(s.y, 0.01), snappedf(ab[0].pos.x, 0.01), int(ab[0].get("beat_n", 0)), int(st.get("brk", 0)), g.rng_enemy.state]


## 输出窗口（协调人 10-27）：队长贴着打（追最近一具 Boss，保持 100）时，「Boss 在近战射程 150 内且屏幕内（队长 ±320 × ±180）符卡弹 < 20」的时间占比；每次收招破绽时长
func window_run(kind: String, p2: bool, partner := "") -> Dictionary:
	var bosses: Array = []
	if partner == "":
		bosses = [path_boss(p2)]
	else:
		bosses = tide_pair(partner, p2)
	var ok := 0
	var n := 0
	var brks: Array = []
	var cur := 0.0
	var both := 0
	var st := {}
	chase = true
	for i in int(60.0 / DT):
		var near: Dictionary = bosses[0]
		for b in bosses:
			if b.pos.distance_to(g.ppos) < near.pos.distance_to(g.ppos):
				near = b
		var want: Vector2 = near.pos + (g.ppos - near.pos).normalized() * 100.0
		g.ppos = g.ppos.move_toward(want, 120.0 * DT)
		tick(st)
		var dense := 0
		for b in g.ebullets:
			if b.life > 0.0 and b.get("mc", false) and absf(b.pos.x - g.ppos.x) < 320.0 and absf(b.pos.y - g.ppos.y) < 180.0:
				dense += 1
		var reach := false
		for b in bosses:
			if b.pos.distance_to(g.ppos) < 150.0:
				reach = true
		n += 1
		if reach and dense < 20:
			ok += 1
		var bt: float = bosses[0].get("break_t", 0.0)
		if str(bosses[0].get("brk_label", "")) == "收招 · 破绽" and bt > cur + 0.05:
			brks.append(snappedf(bt, 0.1))
			if bosses.size() > 1 and float(bosses[1].get("break_t", 0.0)) > 0.0:
				both += 1
		cur = bt
	chase = false
	return {"kind": kind, "act": 2 if p2 else 1, "low_pressure": snappedf(float(ok) / n, 0.01), "breaks": brks, "pair_breaks_together": both}


func output_windows() -> void:
	var rows: Array = []
	for p2 in [false, true]:
		rows.append(window_run("path", p2))
		rows.append(window_run("bishop+archon", p2, "archon"))
		rows.append(window_run("bishop+immortal", p2, "immortal"))
	for r in rows:
		print("WINDOW ", JSON.stringify(r))
		check(float(r.low_pressure) >= 0.35, "%s act %d low-pressure share >= 35%% (%.2f)" % [r.kind, r.act, r.low_pressure])
		check(not r.breaks.is_empty(), "%s act %d has combo recoveries" % [r.kind, r.act])
