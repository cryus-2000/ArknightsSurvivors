extends Node
var g
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAIL ", label)
func _ready() -> void:
	g = load("res://game.tscn").instantiate()
	g.demo_op = "mizuki"
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	# 本测试验旧版轮转 AI（招式数 / 同步预警）；偏执泡影 / 伊莎玛拉的连段版（boss/paranoia_combos、ishar_combos，10-27）各有 paranoia_combos / ishar_combo 测试，这里关掉
	var Bal = preload("res://scripts/core/balance.gd")
	Bal.v("boss/paranoia_combos", 1.0)
	Bal._data["boss"]["paranoia_combos"] = 0
	Bal._data["boss"]["ishar_combos"] = 0
	g.zone_frozen = false
	_check_pattern_cadence()
	for kind in ["carmen", "iberia", "path", "bishop", "archon", "immortal", "paranoia", "knight_boss", "ishar", "izumik"]:
		g.t = 100.0
		g.enemies.clear()
		g.warns.clear()
		g.ebullets.clear()
		var e: Dictionary = g.spawner.new_enemy(kind, Vector2.ZERO)
		e.age = 3.0
		g.enemies.append(e)
		g.bosses = [e]
		if kind in ["ishar", "izumik"]:
			g.bai.setup_preview_phase2(e)
		g.ppos = Vector2(220, 0)
		var seen := {}
		var pending: Dictionary = {}
		for tick in 900:
			g.t += 0.1
			e.age += 0.1
			e.wind = maxf(0.0, e.wind - 0.1)
			e.cdt = maxf(0.0, e.cdt - 0.1)
			g.invuln = 100.0
			g.bai._boss_ai(e, 0.1, Vector2.RIGHT, 220.0)
			# 偏执泡影连携攻势（docs/170）：弹幕段不出预警，按出招名数（收招 / 力竭 / 漂近不算招）
			if kind == "paranoia" and not str(e.get("move_name", "")) in ["", "收招", "力竭", "泡影漂近"]:
				seen[str(e.move_name)] = true
			for w in g.warns:
				if w.has("pattern_id") or (w.name != "" and w.t == 0.0):
					# docs/95（10-14）：4 招 = 数据招式 + 手写招式，按招式名 / pattern_id 数「不同的招」
					seen[w.get("pattern_id", w.name)] = true
					if w.has("pattern_id"):
						pending = w.duplicate()
					check(w.dur >= 0.6 and w.dur - w.track >= 0.399, kind + " readable warning " + str(w.name))
			g.bai._update_warns(0.1)
			g.enemies_sys.update_ebullets(0.1)
			g.ebullets = g.ebullets.filter(func(b): return b.life > 0.0)
			g.fx.clear()
		check(seen.size() >= 2, kind + " executes two distinct new attacks in real AI")
		if not pending.is_empty():
			g.warns.clear()
			pending.owner = e
			pending.done = false
			pending.t = 0.0
			g.warns.append(pending)
			e.dead = true
			var n: int = g.ebullets.size()
			g.bai._update_warns(10.0)
			check(g.ebullets.size() == n, kind + " death cancels queued attack")
	# Actual ring resolution: density, traversable gap, caps and feign cancellation.
	var ring_boss: Dictionary = g.spawner.new_enemy("paranoia", Vector2.ZERO)
	ring_boss.age = 20.0
	g.bai.setup_preview_phase2(ring_boss)
	ring_boss.pattern_next = g.t
	g.ppos = Vector2(400, 0)
	g.warns.clear()
	g.ebullets.clear()
	g.bai._boss_ai(ring_boss, 0.01, Vector2.RIGHT, 400.0)
	var rings: Array = g.warns.filter(func(w): return w.get("act", "") == "pattern_ring")
	if rings.is_empty():
		# docs/95 §1：轮转第 1 位是叠影、泡影环二阶段每两轮一次（p2_every 2）；点名放一次
		ring_boss.pattern_force = "泡影环"
		ring_boss.wind = 0.0
		ring_boss.cdt = 0.0
		g.warns.clear()
		g.bai._boss_ai(ring_boss, 0.01, Vector2.RIGHT, 400.0)
		rings = g.warns.filter(func(w): return w.get("act", "") == "pattern_ring")
	check(rings.size() == 3, "final boss landed ring is three staggered waves (docs/142b §8.2; 10-25 加密 +1 圈)")
	if not rings.is_empty():
		var w: Dictionary = rings[0]
		g.bai._warn_resolve(w)
		check(g.ebullets.size() >= 30, "enhanced ring actually emits dense bullets")
		for b in g.ebullets:
			check(absf(angle_difference(b.vel.angle(), w.gap_ang)) >= w.gap_half - 0.001, "gap remains empty")
			check(b.vel.length() >= 300 and b.boss, "fast bullets retain boss protections")
		var n: int = g.ebullets.size()
		ring_boss.coma = true
		g.bai._warn_resolve(w)
		check(g.ebullets.size() == n, "feigning boss cannot resolve another wave")
		ring_boss.coma = false
		g.combat.start_break(ring_boss, 3.0)
		g.bai._warn_resolve(w)
		check(g.ebullets.size() == n, "stagger break cancels queued wave")
		ring_boss.break_t = 0.0
		for repeat in 20:
			g.bai._warn_resolve(w)
		check(g.ebullets.size() <= 160, "one boss projectile cap")   # 10-25 弹幕加密：OWNER_CAP 120 → 160
		for source in 5:
			var next_boss: Dictionary = g.spawner.new_enemy("paranoia", Vector2.ZERO)
			w.owner = next_boss
			for repeat in 10:
				g.bai._warn_resolve(w)
		check(g.ebullets.size() <= 320, "total live projectile cap")   # TOTAL_CAP 240 → 320
	# A distant melee Boss closes in instead of stalling（docs/95 §9：蔑死体的裂潮刃波删了，远距离由跃击贴上来）.
	var melee: Dictionary = g.spawner.new_enemy("archon", Vector2.ZERO)
	melee.age = 20.0
	melee.pattern_next = g.t
	g.warns.clear()
	g.ebullets.clear()
	g.ppos = Vector2(500, 0)
	g.bai._boss_ai(melee, 0.01, Vector2.RIGHT, 500.0)
	check(g.warns.any(func(w): return w.get("act", "") == "leap"), "far melee closes in with a leap")
	# Blade volley（斥亡体第二幕掠海飞刃，docs/95 §10.2 D）has actual distinct blade projectiles.
	var blader: Dictionary = g.spawner.new_enemy("immortal", Vector2.ZERO)
	blader.age = 20.0
	blader.gates_passed = 1
	g.warns.clear()
	g.ebullets.clear()
	g.ppos = Vector2(300, 0)
	blader.pattern_force = "掠海飞刃"
	g.bai.patterns.try_attack(blader, Vector2.RIGHT, 300.0)
	check(g.warns.any(func(w): return w.get("act", "") == "pattern_fan"), "blade volley is scheduled")
	if not g.warns.is_empty():
		g.bai._warn_resolve(g.warns[0])
		check(g.ebullets.size() == 10 and g.ebullets[0].kind == "boss_blade", "blade volley has actual distinct projectiles")   # 掠海飞刃 7 → 10（10-25 加密）
	# Every grouped laser / column uses one common resolve time, including legacy attacks.
	for spec in [["bishop", "pillar", 0], ["izumik", "pattern_rain", 0], ["ishar", "ishar_line", 1]]:   # 泡影爆裂已删（docs/95 §1）；伊祖米克潮汐坠落改为第 0 条；伊莎玛拉三点落击删（泪落依次落，docs/142b §3.6）
		var caster: Dictionary = g.spawner.new_enemy(spec[0], Vector2.ZERO)
		caster.age = 20.0
		if caster.type == "paranoia":
			caster.phase = 2
			caster.cds = {"gaze": g.t + 100.0}
		if caster.type in ["ishar", "izumik"]:
			g.bai.setup_preview_phase2(caster)
			g.t += 2.0
			caster.wind = 0.0
		caster.pattern_next = g.t if spec[1] == "pattern_rain" else INF
		caster.pattern_cycle = spec[2]
		caster.ishar_cycle = spec[2]
		caster.ishar_next_at = g.t
		g.warns.clear()
		g.fx.clear()
		g.bai._boss_ai(caster, 0.01, Vector2.RIGHT, 220.0)
		var group: Array = g.warns.filter(func(w): return w.act == spec[1])
		check(group.size() >= 3, str(spec) + " actual grouped attack")
		if not group.is_empty():
			var time: float = group[0].dur
			var staged: bool = group[0].get("pattern", {}).has("wave_interval")
			if spec[1] == "ishar_line":
				continue   # 伊莎玛拉三线扫射改为四条依次发射（docs/173 §15，10-28）：不再同时结算
			if not staged:
				check(group.all(func(w): return is_equal_approx(w.dur, time)), str(spec) + " synchronized warnings")
			g.invuln = 100.0
			g.bai._update_warns(time - 0.01)
			check(group.all(func(w): return not w.done), "none fire before shared warning")
			g.bai._update_warns(0.02)
			if staged:
				check(group[0].done and not group[1].done, "only first beat fires at first deadline")
			else:
				check(group.all(func(w): return w.done), "all fire together at shared deadline")
	# The protected human / learning phases must never schedule new hostile patterns.
	for kind in ["ishar", "izumik"]:
		var e: Dictionary = g.spawner.new_enemy(kind, Vector2.ZERO)
		e.age = 20.0
		g.warns.clear()
		g.bai._boss_ai(e, 0.01, Vector2.RIGHT, 200.0)
		check(not g.warns.any(func(w): return w.has("pattern_id")), kind + " phase one stays unchanged")
	# 原作机制转译：骑士冰线追击、接潮双体生命连接、伊莎玛拉之泪共鸣。
	g.t = 300.0
	g.warns.clear()
	g.fx.clear()
	var hunter: Dictionary = g.spawner.new_enemy("knight_boss", Vector2.ZERO)
	hunter.age = 20.0
	hunter.pattern_next = INF
	# This test isolates the frost-track chain after initial planting.
	hunter.stakes=[{"pos":Vector2(-300,0),"until":INF,"born":0.0}]
	hunter.stakes_seeded=true
	g.ppos = Vector2(260, 0)
	g.bai._boss_ai(hunter, 0.01, Vector2.RIGHT, 260.0)
	var ice_marks: Array = g.warns.filter(func(w): return w.act == "frost_track")
	check(ice_marks.size() == 1 and ice_marks[0].dur >= 0.6, "knight announces frost-track pursuit")
	if not ice_marks.is_empty():
		g.t += ice_marks[0].dur # Advance the real windup before resolving its release.
		g.bai._warn_resolve(ice_marks[0])
		check(g.fx.any(func(f): return f.kind == "final_impact" and f.get("skin", "") == "ice") and g.fx.any(func(f): return f.kind == "frost_step"), "knight frost track has ice art")
		g.t = maxf(float(hunter.knight_combo_next),float(hunter.get("hunt_follow_at",0.0))) + 0.01
		hunter.wind = 0.0
		g.warns.clear()
		g.bai._boss_ai(hunter, 0.01, Vector2.RIGHT, 260.0)
		check(g.warns.any(func(w): return w.act == "dash" and w.name == "寒冷追击"), "knight follows marked track with charge")
	g.t = 400.0
	g.warns.clear()
	var priest: Dictionary = g.spawner.new_enemy("bishop", Vector2.ZERO)
	var fallen: Dictionary = g.spawner.new_enemy("archon", Vector2(240, 0))
	priest.age = 20.0
	priest.pattern_next = INF
	priest.partner = fallen
	fallen.partner = priest
	fallen.coma = true
	fallen.invuln = true
	g.ppos = Vector2(120, 0)
	g.bai._boss_ai(priest, 0.01, Vector2.RIGHT, 120.0)
	var links: Array = g.warns.filter(func(w): return w.act == "tide_link")
	check(links.size() == 1 and links[0].len > 200.0, "surviving tide boss counters along life link")
	if not links.is_empty():
		g.fx.clear()
		g.bai._warn_resolve(links[0])
		check(g.fx.any(func(f): return f.kind == "tide_link"), "life-link counter has dedicated tide art")
	g.t = 500.0
	g.warns.clear()
	var sea: Dictionary = g.spawner.new_enemy("ishar", Vector2.ZERO)
	var active_tear: Dictionary = g.spawner.new_enemy("tear", Vector2(110, 45))
	var quiet_tear: Dictionary = g.spawner.new_enemy("tear", Vector2(250, 0))
	active_tear.owner = sea
	quiet_tear.owner = sea
	quiet_tear.purified = true
	g.enemies = [active_tear, quiet_tear]
	g.ppos = quiet_tear.pos
	g.bai.transform_ishar(sea)
	check(sea.get("tear_echoes", []).size() == 1 and not active_tear.dead and active_tear.get("song_eye", false) and quiet_tear.dead, "only unpurified tears survive as hostile song eyes")
	check(g.fx.any(func(f): return f.kind == "tide_link" and f.a == active_tear.pos), "unsuppressed tear visibly links at transformation")
	g.t += 2.0
	sea.wind = 0.0
	sea.ishar_next_at = g.t
	g.bai._ishar_phase2(sea, Vector2.RIGHT, 250.0)
	var echoes: Array = g.warns.filter(func(w): return w.act == "ishar_echo")
	check(echoes.size() == 1 and echoes[0].get("true", false), "hostile Ishar fires true-damage tear resonance")
	if not echoes.is_empty():
		g.fx.clear()
		g.bai._warn_resolve(echoes[0])
		echoes[0].done = true
		g.bai.boss("ishar").cards()._beam_fades(sea)   # 10-31 起伊莎玛拉光束统一由 ishar_tell_draw 画（render/ishar_laser），结算帧写 ishar_beam_fade
		check(g.fx.any(func(f): return f.kind in ["tide_link", "kp_beam", "ishar_beam_fade"]), "tear resonance draws linked wave (unified Ishar beam, 10-31)")
	# Codex 第 1 批帧条挂点（docs/95 §13、art/incoming/boss_moves_1_handoff.md）：预警中播蓄力帧 f0 / f1，结算后 0.2 秒内播出手帧 f2（回旋 f2–f4、前刺 f1）
	g.t = 600.0
	g.warns.clear()
	# [type, 招, 帧条, 结算后出手帧, 是否二阶段]
	var strips := [
		["knight_boss", "长枪回旋", "e_knight_spin", 2, true],
		["knight_boss", "长枪连刺", "e_knight_thrust", 1, false],
		["paranoia", "凝视", "e_paranoia_gaze", 2, false],
		["paranoia", "呼号", "e_paranoia_phase2_howl", 2, true],
		["izumik", "分享", "e_izumik_share", 2, true],
		["ishar", "大群之歌", "e_ishar_t_sing", 2, true],
	]
	for st in strips:
		var b: Dictionary = g.spawner.new_enemy(st[0], Vector2(-130, 0))
		b.age = 20.0
		if st[4]:
			g.bai.setup_preview_phase2(b)
			b.invuln = false
			b.channel = 0.0
		g.t += 1.0   # 过了伊莎玛拉的变身帧 / 骑士重生无敌
		g.ppos = Vector2(60, 0)
		g.warns.clear()
		check(g.bai.boss(st[0]).force_move(b, st[1], Vector2.RIGHT, 190.0), "%s force_move %s" % [st[0], st[1]])
		var mine: Array = g.warns.filter(func(w): return is_same(w.owner, b))
		if mine.is_empty():
			continue
		for w in mine:
			w.t = w.dur * 0.7   # 预警后段（前刺第 3 段过 60% 才换帧）
		var release_frame: int = int(st[3])
		if st[0]=="knight_boss":
			var rd: Dictionary = preload("res://scripts/art.gd").enemy_redraw(st[2])
			release_frame=int(rd.event_frames[0]) if not rd.event_frames.is_empty() else int(rd.release_frame if rd.release_frame!=null else rd.frames/2)
		var anim: Dictionary = g.world.final_boss_animation(b) if st[0] == "knight_boss" else (g.world.ishar_animation(b) if st[0] == "ishar" else g.world.boss_strip_animation(b))
		check(anim.get("name", "") == st[2] and int(anim.get("frame", -1)) < release_frame, "%s 预警中播 %s 蓄力帧（得 %s）" % [st[1], st[2], str(anim)])
		for w in mine:
			w.t = w.dur
		g.invuln = 100.0
		g.bai._update_warns(0.0)
		g.t += 0.05
		anim = g.world.final_boss_animation(b) if st[0] == "knight_boss" else (g.world.ishar_animation(b) if st[0] == "ishar" else g.world.boss_strip_animation(b))
		check(anim.get("name", "") == st[2] and (int(anim.get("frame", -1)) >= release_frame if st[0]=="knight_boss" else int(anim.get("frame", -1)) == int(st[3])), "%s 结算后播 %s 出手帧 f%d（得 %s）" % [st[1], st[2], int(st[3]), str(anim)])
		b.dead = true
		g.warns.clear()
	# docs/95 §8.2 C「统一」：两体之间的直线；幽灵线段终点跟随搭档、锁定后冻结并让两体停步、搭档死了作废
	g.enemies.clear()
	g.warns.clear()
	g.invuln = 100.0
	var bi: Dictionary = g.spawner.new_enemy("bishop", Vector2.ZERO)
	var ar: Dictionary = g.spawner.new_enemy("archon", Vector2(300, 0))
	bi.age = 20.0
	ar.age = 20.0
	bi.partner = ar
	ar.partner = bi
	g.enemies.append(bi)
	g.enemies.append(ar)
	var uw: Dictionary = g.bai.unite(bi, ar)
	check(uw.shape == "line" and is_same(uw.get("b_owner"), ar) and uw.name == "统一", "统一 是主教到搭档的直线")
	ar.pos = Vector2(300, 120)
	g.bai._update_warns(0.5)
	check(absf(float(uw.len) - bi.pos.distance_to(ar.pos)) < 0.5, "统一 幽灵线段终点跟着搭档走")
	g.bai._update_warns(0.5)
	var locked_len: float = uw.len
	ar.pos = Vector2(500, 400)
	g.bai._update_warns(0.1)
	check(is_equal_approx(float(uw.len), locked_len) and ar.wind > 0.0 and bi.wind > 0.0, "统一 锁定后线冻结、两体停步")
	ar.dead = true
	var n_fx: int = g.fx.size()
	g.bai._warn_resolve(uw)
	check(g.fx.size() == n_fx, "统一 搭档死了不结算")
	g.warns.clear()
	if DisplayServer.get_name() != "headless" and Cfg.dev_args().has("--capture-ui"):
		await capture_patterns()
	print("BOSS VARIETY failures=", failures)
	g.warns.clear()
	g.enemies.clear()
	g.bosses.clear()
	g.queue_free()
	g = null
	Sfx.set_process(false)
	await get_tree().create_timer(0.25, true, false, true).timeout
	for player in Sfx.get_children():
		if player is AudioStreamPlayer:
			player.stop()
			player.stream = null
			player.queue_free()
	await get_tree().create_timer(0.2, true, false, true).timeout
	get_tree().quit(0 if failures == 0 else 1)


func capture_patterns() -> void:
	g.demo_op = ""
	g.state = g.S.PLAY
	g.t = 600.0
	g.trial.active = true
	g.trial.started_at = g.t
	g.trial.saved_progress = {}
	g.ppos = Vector2(260, 100)
	g.ch.pos = g.ppos
	g.doc_pos = g.ppos + Vector2(40, 30)
	g.warns.clear()
	g.ebullets.clear()
	g.fx.clear()
	g.enemies.clear()
	var boss: Dictionary = g.spawner.new_enemy("ishar", Vector2(-130, 0))
	boss.age = 20.0
	g.enemies.append(boss)
	g.bosses = [boss]
	g.boss = boss
	g.final_boss = boss
	g.bai.setup_preview_phase2(boss)
	g.t += 2.0
	boss.wind = 0.0
	boss.pattern_next = g.t
	g.bai._boss_ai(boss, 0.01, Vector2.RIGHT, 390.0)
	var rings: Array = g.warns.duplicate()
	for i in rings.size():
		g.bai._warn_resolve(rings[i])
		g.enemies_sys.update_ebullets(0.3)
	g.world.update_visuals(0.0)
	g.cam.position = Vector2(50, 0)
	g.queue_redraw()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../build/ea_boss_dense_ring.png")
	g.warns.clear()
	g.ebullets.clear()
	g.fx.clear()
	boss.pattern_next = g.t
	boss.wind = 0.0
	g.bai._boss_ai(boss, 0.01, Vector2.RIGHT, 390.0)
	var blades: Array = g.warns.duplicate()
	for w in blades:
		g.bai._warn_resolve(w)
		g.enemies_sys.update_ebullets(0.25)
	g.queue_redraw()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../build/ea_boss_blade_volley.png")
	# 美术验收截图：真实 Boss 实体与新特效同屏。
	g.warns.clear()
	g.fx.clear()
	g.ebullets.clear()
	g.shocks.clear()
	g.lobs.clear()
	g.enemies.clear()
	var hunter: Dictionary = g.spawner.new_enemy("knight_boss", Vector2(-130, 0))
	hunter.age = 20.0
	hunter.pattern_next = INF
	g.enemies.append(hunter)
	g.bosses = [hunter]
	g.boss = hunter
	g.final_boss = hunter
	g.ppos = Vector2(230, 0)
	g.bai._boss_ai(hunter, 0.01, Vector2.RIGHT, 360.0)
	for w in g.warns.duplicate():
		if w.act == "frost_track":
			g.bai._warn_resolve(w)
	g.warns.clear()
	g.queue_redraw()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../build/ea_knight_frost_hunt.png")
	g.fx.clear()
	g.ebullets.clear()
	g.shocks.clear()
	g.lobs.clear()
	g.enemies.clear()
	var priest: Dictionary = g.spawner.new_enemy("bishop", Vector2(-130, 0))
	var fallen: Dictionary = g.spawner.new_enemy("archon", Vector2(180, 0))
	priest.age = 20.0
	priest.pattern_next = INF
	priest.partner = fallen
	fallen.partner = priest
	fallen.coma = true
	fallen.invuln = true
	g.enemies.append_array([priest, fallen])
	g.bosses = [priest, fallen]
	g.boss = priest
	g.final_boss = null
	g.ppos = Vector2(100, 0)
	g.bai._boss_ai(priest, 0.01, Vector2.RIGHT, 230.0)
	for w in g.warns.duplicate():
		if w.act == "tide_link":
			g.bai._warn_resolve(w)
	g.warns.clear()
	g.queue_redraw()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../build/ea_bishop_life_link.png")
	g.fx.clear()
	g.ebullets.clear()
	g.shocks.clear()
	g.lobs.clear()
	g.enemies.clear()
	var sea: Dictionary = g.spawner.new_enemy("ishar", Vector2(-130, 0))
	var tear: Dictionary = g.spawner.new_enemy("tear", Vector2(100, -80))
	tear.owner = sea
	g.enemies.append_array([sea, tear])
	g.bosses = [sea]
	g.boss = sea
	g.final_boss = sea
	g.ppos = Vector2(250, 0)
	g.bai.transform_ishar(sea)
	g.t += 2.0
	sea.wind = 0.0
	sea.ishar_next_at = g.t
	g.bai._ishar_phase2(sea, Vector2.RIGHT, 380.0)
	for w in g.warns.duplicate():
		if w.act == "ishar_echo":
			g.bai._warn_resolve(w)
	g.warns.clear()
	g.queue_redraw()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../build/ea_ishar_tear_echo.png")


func _check_pattern_cadence() -> void:
	for kind in ["paranoia", "izumik"]:
		var e: Dictionary = g.spawner.new_enemy(kind, Vector2.ZERO)
		e.phase = 2
		e.age = 20.0
		e.invuln = false
		e.pattern_force = "泡影环" if kind == "paranoia" else "解读旋涡"
		g.ppos = Vector2(760, 0)
		g.warns.clear()
		check(g.bai.patterns.try_attack(e, Vector2.RIGHT, 760.0), kind + " rotating ring starts")
		var rings: Array = g.warns.filter(func(w): return w.get("act", "") == "pattern_ring")
		check(rings.size() == 3, kind + " keeps original three waves")
		if rings.size() != 3:
			continue
		check(absf(angle_difference(rings[0].gap_ang, rings[2].gap_ang)) > 2.0 * rings[0].gap_half, kind + " no common stationary gap")
		# Construct a continuous route inside every gap, allowing the 12px player + 7px bullet radius.
		# Even at 70% of the base 150px/s speed this route needs no dash, at near and far ranges.
		for radius in [120.0, 200.0, 400.0, 760.0]:
			var safe_half: float = rings[0].gap_half - asin(19.0 / radius) - 0.02
			var first: float = rings[0].gap_ang + safe_half
			var last: float = rings[2].gap_ang - safe_half
			check(radius * absf(first) <= 105.0 * (rings[0].dur + radius / float(rings[0].pattern.speed)), kind + " first gap reachable from initial aim")
			for k in 3:
				var aim: float = lerpf(first, last, float(k) / 2.0)
				check(absf(angle_difference(aim, rings[k].gap_ang)) <= safe_half + 0.001, kind + " route clears collision margin")
				if k > 0:
					var dt: float = rings[k].dur - rings[k - 1].dur
					check(radius * absf(last - first) / 2.0 <= 105.0 * dt, kind + " gap route reachable while slowed")
		for k in 3:
			check(rings[k].dur - rings[k].track >= 0.4, kind + " warning lock retained")
			g.ebullets.clear()
			g.bai.patterns.resolve(rings[k])
			for b in g.ebullets:
				check(not g.tele.in_gap(rings[k], b.vel.angle()), kind + " actual bullets preserve moving gap")
		check(e.pattern_next - g.t - rings[2].dur >= 2.799, kind + " explicit respite retained")
	var tide: Dictionary = g.spawner.new_enemy("izumik", Vector2.ZERO)
	tide.phase = 2
	tide.invuln = false
	tide.pattern_force = "潮汐坠落"
	g.warns.clear()
	g.bai.patterns.try_attack(tide, Vector2.RIGHT, 400.0)
	check(g.warns.size() == 7, "tide keeps seven distinct warnings")
	for k in range(1, g.warns.size()):
		check(is_equal_approx(g.warns[k].dur - g.warns[k - 1].dur, 0.24), "tide resolves on successive beats")
	g.warns.clear()
	g.ebullets.clear()
