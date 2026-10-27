extends Node
## 偏执泡影连携攻势（docs/170）：每幕两组、连段 ≤4 段且有限、收招后轮换、打落打断、转幕重起、被控作废弹幕段、同输入同结果
var g
var failures := 0
const Combos = preload("res://scripts/enemies/bosses/paranoia_combos.gd")


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
	check_table()
	check_loop()
	check_break()
	check_act_change()
	check_stun()
	check_repro()
	check_beam_hold()
	print("PARANOIA COMBOS failures=", failures)
	g.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if failures else 0)


func fresh(a := 0) -> Dictionary:
	g.t = 100.0
	g.warns.clear()
	g.ebullets.clear()
	g.bai.finals.hazards.clear()
	g.enemies.clear()
	g.fx.clear()
	g.bai.token_owner = null
	g.zone_frozen = false
	var e: Dictionary = g.spawner.new_enemy("paranoia", Vector2.ZERO)
	e.age = 20.0
	e.invuln = false
	g.bosses = [e]
	g.boss = e
	g.final_boss = e
	g.enemies.append(e)
	g.ppos = Vector2(220, 0)
	if a == 1:
		e.gates_passed = 1
	elif a >= 2:
		g.bai.setup_preview_phase2(e)
		e.cocoon_done = a == 3
	return e


func tick(e: Dictionary, dt := 0.05) -> void:
	g.t += dt
	e.wind = maxf(0.0, e.wind - dt)
	e.cdt = maxf(0.0, e.cdt - dt)
	e.stun = maxf(0.0, e.stun - dt)
	e.age += dt
	g.invuln = 999.0
	g.dash_t = 0.0
	# 玩家绕圈移动（固定轨迹，不用随机）
	g.ppos = Vector2.from_angle(g.t * 0.5) * 230.0
	g.bai.boss_step(e, dt, (g.ppos - e.pos).normalized(), g.ppos.distance_to(e.pos))
	g.tele.update_warns(dt)
	g.shots.step(dt)


func check_table() -> void:
	check(Combos.ACT_COMBOS.size() == 4, "four acts")
	for a in Combos.ACT_COMBOS.size():
		check((Combos.ACT_COMBOS[a] as Array).size() >= 2, "act %d has two combos" % a)
		for c in Combos.ACT_COMBOS[a]:
			var seq: Array = Combos.COMBOS[c].seq
			check(seq.size() >= 2 and seq.size() <= 4, c + " combo has 2..4 segments")
	var s = g.bai.boss("paranoia")
	check(s.demo_moves({}).size() >= 14, "fourteen distinct active moves exposed")


## 起手 → 依次出段 → 收招 → 换另一组；不会无限连下去
func check_loop() -> void:
	for a in 4:
		var e := fresh(a)
		var seen: Array = []
		var combos_seen: Array = []
		var rests := 0
		var was_rest := false
		for i in 900:
			tick(e)
			var mv: String = str(e.get("move_name", ""))
			if not seen.has(mv):
				seen.append(mv)
			var c: String = str(e.get("pc_combo", ""))
			if c != "" and not combos_seen.has(c):
				combos_seen.append(c)
			var r: bool = float(e.get("pc_rest_until", 0.0)) > g.t
			if r and not was_rest:
				rests += 1
			was_rest = r
			if rests >= 2 and combos_seen.size() >= 2:
				break
		check(combos_seen.size() >= 2 and combos_seen[0] == Combos.ACT_COMBOS[a][0], "act %d alternates its two combos %s" % [a, str(combos_seen)])
		check(rests >= 1, "act %d combo ends in a recovery window" % a)
		check(not seen.any(func(m): return "符卡" in m), "act %d shows no spell-card label" % a)
		var emit_seg: String = Combos.COMBOS[Combos.ACT_COMBOS[a][0]].seq[0]
		check(seen.has(emit_seg) or not Combos.EMITTERS.has(emit_seg), "act %d first segment cast (%s) %s" % [a, emit_seg, str(seen)])
		check(e.get("pc_buls", []).size() <= Combos.BUL_CAP, "act %d bullet cap" % a)


## 冲刺打落：打断连段（队列、弹幕段清空），已在飞的弹保留；破绽结束后从下一组重新起手
func check_break() -> void:
	var e := fresh(0)
	for i in 60:
		tick(e)
	e.pc_queue = ["凝视"]
	g.ebullets.clear()
	combos_emit(e, "千目注视")
	check((e.get("pc_eyes", []) as Array).size() == 7, "gaze opens seven eyes around the leader")
	for i in 40:
		tick(e)
	var live_before: int = g.ebullets.filter(func(b): return b.life > 0.0 and (e.pc_eyes as Array).any(func(ey): return b.pos.distance_to(ey.pos) < 400.0)).size()
	check(live_before > 0, "eyes fired at the leader")
	g.ppos = e.pos
	g.dash_t = 0.3
	g.bai.boss("paranoia")._drop_step(e)
	g.dash_t = 0.0
	check(e.get("pc_queue", []).is_empty(), "drop clears the combo queue")
	check(e.get("pc_emit", []).is_empty(), "drop cancels emitters")
	check(g.ebullets.filter(func(b): return b.life > 0.0).size() > 0, "bullets already in flight are kept")
	var idx: int = int(e.get("pc_idx", 0))
	for i in 160:
		tick(e)
	check(not e.get("pc_queue", []).is_empty() or not e.get("pc_emit", []).is_empty() or g.warns.any(func(w): return is_same(w.owner, e)) or int(e.get("pc_idx", 0)) > idx, "combos resume after the drop")


func combos_emit(e: Dictionary, n: String) -> void:
	g.bai.boss("paranoia").combos()._emit(e, n, Vector2.RIGHT)


## 转幕：清队列，宣言新幕第一张
func check_act_change() -> void:
	var e := fresh(0)
	for i in 40:
		tick(e)
	e.gates_passed = 1
	tick(e)
	check(int(e.get("pc_act", -1)) == 1 and int(e.get("pc_idx", -1)) == 0, "gate restarts at act two first combo")
	check(e.get("pc_queue", []).is_empty(), "gate clears queue")


## 被控：没放完的弹幕段作废
func check_stun() -> void:
	var e := fresh(0)
	for i in 30:
		tick(e)
	combos_emit(e, "偏执双旋")
	tick(e)
	e.stun = 0.5
	tick(e)
	check(e.get("pc_emit", []).is_empty(), "stun cancels pending emitter")


## 同输入跑两遍，弹幕位置一致（玩法不用随机数）
func check_repro() -> void:
	var sig: Array = []
	for r in 2:
		var e := fresh(2)
		for i in 300:
			tick(e)
		var acc := Vector2.ZERO
		for b in e.get("pc_buls", []):
			acc += b.pos
		sig.append([e.get("pc_buls", []).size(), snappedf(acc.x, 0.01), snappedf(acc.y, 0.01), str(e.get("move_name", ""))])
	check(sig[0] == sig[1], "same input reproduces the same bullets %s" % str(sig))


## 凝视持续光束：结算时不在线上，保持段内走进光束 → 结算一次（离开保持段 / 收拢段不再算）
func check_beam_hold() -> void:
	var e := fresh(2)
	e.pc_act = 2   # 不让连段接管，单独测凝视
	var s = g.bai.boss("paranoia")
	g.ppos = Vector2(0, 300)
	s._gaze(e, Vector2.RIGHT)
	var gw: Array = g.warns.filter(func(w): return is_same(w.owner, e) and str(w.get("skin", "")) == "gaze")
	check(not gw.is_empty() and float(gw[0].get("hold", 0.0)) > 0.0 and float(gw[0].get("kp_life", 0.0)) > 0.5, "gaze is a sustained beam")
	if gw.is_empty():
		return
	var w: Dictionary = gw[0]
	w.track = 0.0
	w.ang = 0.0
	w.pos = Vector2.ZERO
	w.len = 800.0
	while not w.done:
		g.t += 0.05
		g.tele.update_warns(0.05)
	s._beam_hold(e)
	check((e.get("gaze_beams", []) as Array).has(w), "missed beam enters hold window")
	g.ppos = Vector2(300, 14)   # 走进光束
	g.t += 0.1
	s._beam_hold(e)
	check(not (e.get("gaze_beams", []) as Array).has(w), "stepping into the held beam resolves it once")
