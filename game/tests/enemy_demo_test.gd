extends Node
const D = preload("res://scripts/data.gd")
const A = preload("res://scripts/art.gd")
var g
var failures := 0


func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAIL ", label)


func _ready() -> void:
	g = load("res://game.tscn").instantiate()
	g.demo_op = "mizuki"
	g.demo_enemy = "ishar"
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	g.t = 100.0
	g.enemy_demo.reset()
	var e: Dictionary = g.enemy_demo.subject
	check(is_equal_approx(g.world.enemy_scale(e), 1.36), "Ishar human is slightly taller than operator")
	var state0: int = g.state
	check(e.friendly and e.invuln, "Ishar first phase is neutral and not targetable")
	var targets: Array = g.enemies.filter(func(x): return x.get("heal_demo_target", false))
	check(targets.size() == 3, "first phase has three real enemy targets")
	var initial_hp: Array = targets.map(func(x): return x.hp)
	var healed_target := false
	for frame in 150:
		g.t += 1.0 / 30.0
		g.enemy_demo.step(1.0 / 30.0)
		for i in targets.size():
			healed_target = healed_target or targets[i].hp > initial_hp[i]
	check(healed_target, "human Ishar actually heals injured sea monsters")
	check(targets.all(func(x): return not x.dead), "human Ishar never kills sea monsters")
	check(g.ebullets.is_empty(), "friendly Ishar does not shoot the player")
	check(g.enemy_demo.cycle_period() == 50.0 and e.friendly, "automatic showcase leaves time for full transformation")
	check("治疗海嗣" in g.demo_label and "充能" in g.demo_label, "demo explains human healing and charge")
	check(g.hud_view.hostile_boss_bars().is_empty(), "neutral phase has no dangerous Boss pointer")
	# 完整轮播通过真实充能跨入敌对，不提前跳过人形治疗。
	for frame in 1100:
		if e.phase == 2:
			break
		g.t += 1.0 / 30.0
		g.enemy_demo.step(1.0 / 30.0)
	check(e.phase == 2 and g.enemy_demo.cycle == 0, "automatic gallery reaches true transformation before reset")
	for i in 6:
		g.t = float(e.transform_started) + i * 0.15 + 0.001
		var a: Dictionary = g.world.ishar_animation(e)
		check(a.name == "e_ishar_transform" and a.frame == i, "transform frame %d" % i)
	g.t = e.transform_until + 0.01
	e.pose = 0.0
	e.atk_until = 0.0
	e.mv_until = g.t + 1.0
	check(g.world.ishar_animation(e).name == "e_ishar_t_move", "transformed move")
	check(is_equal_approx(g.world.enemy_scale(e), 2.0), "transformed body keeps sea monster volume")
	g.eai.shoot(e, Vector2.RIGHT)
	check(g.world.ishar_animation(e).name == "e_ishar_t_attack", "transformed ranged shot plays body attack")
	check(not e.friendly and g.ebullets.size() == 3 and g.ebullets[0].vel.length() >= 335.0, "transformed enemy fires actual fast triple projectiles")
	check(g.hud_view.hostile_boss_bars().size() == 1, "hostile phase regains dangerous Boss pointer")
	for name in ["e_stone_attack", "e_mother_attack", "e_ishar", "e_ishar_attack", "e_ishar_transform", "e_ishar_t", "e_ishar_t_move", "e_ishar_t_attack"]:
		check(A.tex(name) != null, "existing sprite available: " + name)
	for id in ["paranoia", "knight_boss", "izumik"]:
		var b: Dictionary = g.spawner.new_enemy(id, Vector2.ZERO)
		var original_speed: float = b.spd
		var original_damage: float = b.dmg
		g.bai.setup_preview_phase2(b)
		if id == "paranoia":
			check(b.phase == 2 and b.ai == "melee" and b.hover_lost and b.spd == 70.0 and b.range == 400.0 and b.weak == "物理" and is_equal_approx(b.dmg, original_damage * 1.2), "paranoia preview uses actual grounded second phase")
		elif id == "knight_boss":
			check(b.phase == 2 and is_equal_approx(b.hp, b.maxhp * 0.5) and is_equal_approx(b.spd, original_speed * 1.2) and b.channel == 1.5, "knight preview uses actual rebirth state")
		else:
			check(b.phase == 2 and b.hp == b.maxhp and not b.invuln, "izumik preview uses actual interpreted state")
		var damage_after: float = b.dmg
		var speed_after: float = b.spd
		g.bai.setup_preview_phase2(b)
		check(b.dmg == damage_after and b.spd == speed_after, id + " phase setup is idempotent")
	# 固定人形可以反复看治疗，固定敌对保留原来 18 秒多招展示。
	g.enemy_demo.configure(1)
	g.enemy_demo.reset()
	check(g.enemy_demo.cycle_period() == 10.0 and g.enemy_demo.subject.friendly, "fixed human view uses 10 second cycle")
	g.enemy_demo.elapsed = 9.99
	g.enemy_demo.step(0.02)
	check(g.enemy_demo.cycle == 1 and g.enemy_demo.subject.friendly, "fixed human view replays without leaving neutral phase")
	g.enemy_demo.configure(2)
	g.enemy_demo.reset()
	check(g.enemy_demo.cycle_period() == 35.0 and not g.enemy_demo.subject.friendly, "fixed hostile view uses 18 second cycle")
	# Real AI updates for every gallery enemy, including scripted death / summons / both boss phases.
	for id in D.ENEMIES:
		g.demo_enemy = id
		g.enemy_demo.configure(2 if id in ["ishar", "paranoia", "izumik", "knight_boss"] else 0)
		var seen_action := false
		for frame in 360:
			g.t += 1.0 / 30.0
			g.enemy_demo.step(1.0 / 30.0)
			if not g.warns.is_empty() or not g.ebullets.is_empty() or not g.lobs.is_empty() or not g.shocks.is_empty() or g.hurt_flash > 0.0 or g.t < float(g.enemy_demo.subject.get("atk_until", 0.0)) or float(g.enemy_demo.subject.get("dash_t", 0.0)) > 0.0:
				seen_action = true
		check(g.hp > 0.0 and g.state == state0, id + " stays alive in demo")
		check(g.gems.is_empty() and g.xp == 0.0, id + " no progression rewards")
		if id not in ["tear", "offspring", "izumik", "brood"]:  # mechanic-only entries also use real AI
			check(seen_action, id + " shows a real attack")
	g.demo_enemy = "tear"
	g.enemy_demo.configure(0)
	g.enemy_demo.step(0.01)
	check(g.enemy_demo.subject.friendly and g.enemy_demo.subject.get("blocked", false), "tear gallery uses genuine neutral suppressible tear")
	check("压制" in g.demo_label, "tear gallery explains changed non-damaging behavior")
	# Reduced HP and exit mode cannot carry into a fresh gallery preview.
	g.demo_enemy = "mimic"
	g.enemy_demo.configure(0)
	g.enemy_demo.step(0.01)
	check(g.enemy_demo.subject.type == "mimic" and g.enemies.size() == 1, "switch clears previous boss and projectiles")
	check(g.warns.is_empty() and g.ebullets.is_empty(), "switch clears prior attacks")
	var gal = load("res://scripts/gallery.gd").new()
	add_child(gal)
	for tab in [1, 2, 3]:
		gal.tab = tab
		gal._build()
		for entry in gal.entries:
			check(entry.forms.any(func(f): return f.has("enemy_demo")), "gallery entry offers attack demo " + entry.id)
			var cfg: Dictionary = D.ENEMIES[entry.id]
			if cfg.has("extra"):
				check(str(cfg.extra.name) in entry.desc, "gallery lists secondary attack " + entry.id)
				if float(cfg.extra.get("frost", 0.0)) > 0.0:
					check("寒冷" in entry.desc, "gallery explains freezing special " + entry.id)
				if float(cfg.extra.get("stun", 0.0)) > 0.0:
					check("僵直" in entry.desc, "gallery explains short stagger " + entry.id)
			if cfg.has("patterns"):
				for move in cfg.patterns:
					check(str(move.name) in entry.desc, "gallery lists boss pattern " + entry.id + ":" + str(move.name))
	for detail in [["knight_boss", "寒冷追击"], ["bishop", "接潮共鸣"], ["ishar", "泪滴共鸣"]]:
		gal.tab = 3
		gal._build()
		check(gal.entries.any(func(entry): return entry.id == detail[0] and detail[1] in entry.desc), "gallery explains original-mechanic attack " + detail[0])
	gal._enemy_demo_start("stone", Vector2i(520, 290))
	var old = gal.demo_vp
	gal.close()
	await get_tree().process_frame
	check(not is_instance_valid(old) and gal.demo_game == null, "close releases simulation viewport")
	if OS.get_cmdline_user_args().has("--capture-enemy-demo"):
		g.demo_enemy = "ishar"
		g.enemy_demo.configure(2)
		g.enemy_demo.step(0.01)
		g.t += 0.95
		g.enemy_demo.step(0.01)
		g.queue_redraw()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("../build/enemy_demo_ishar.png")
	print("ENEMY DEMO failures=", failures)
	gal.queue_free()
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
