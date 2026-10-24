extends Node
var g
var failures := 0
func expect(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAIL ", label)
func _ready() -> void:
	g = load("res://game.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	# Boss 白闪限频（docs/137）：持续伤害不闪；密集命中不续时；间隔内不重启；淡出；过了间隔才能再闪
	var visual := {"flash": 0.0, "hp": 100.0}
	g.vfx.boss_hit_flash(visual, 10.0, true)
	expect(visual.flash == 0.0 and not visual.has("boss_flash_at"), "dot does not start boss flash")
	g.vfx.boss_hit_flash(visual, 10.0)
	var peak: float = g.vfx.boss_flash_alpha(visual, 0.5)
	expect(is_equal_approx(peak, 0.5), "boss flash starts at peak")
	visual.flash = 0.045
	g.vfx.boss_hit_flash(visual, 10.04)
	expect(is_equal_approx(visual.flash, 0.045), "dense hit cannot extend flash")
	expect(g.vfx.boss_flash_alpha(visual, 0.5) < peak, "boss flash fades")
	visual.flash = 0.0
	for i in range(5, 40):
		g.vfx.boss_hit_flash(visual, 10.0 + i * 0.01)
	expect(visual.flash == 0.0, "dark interval survives rapid hits")
	g.vfx.boss_hit_flash(visual, 10.41)
	expect(visual.flash > 0.0, "later hit can flash again")
	visual.flash = 0.0
	g.vfx.boss_hit_flash(visual, 11.0, true)
	expect(visual.flash == 0.0, "dot cannot restart flash after cooldown")
	var starts := 0
	visual.erase("boss_flash_at")
	for i in 600:   # 10 秒每帧都挨打（60 fps）：起闪次数 ≤ 每秒 2.5
		var before: float = visual.get("boss_flash_at", -1.0)
		g.vfx.boss_hit_flash(visual, 20.0 + i / 60.0)
		if visual.get("boss_flash_at", -1.0) != before:
			starts += 1
	expect(starts <= 26, "boss flash rate <= 2.5/s under constant hits (%d)" % starts)
	expect(visual.hp == 100.0, "flash budget does not change health")
	# 别名帧条（e_paranoia2 → 文件 e_paranoia_phase2）要读到真实帧数（docs/137 §7：原来按 2 帧切，一格里并排 3 只泡影）
	var art = preload("res://scripts/art.gd")
	for an in ["e_paranoia2", "e_paranoia2_move", "e_paranoia2_white"]:
		expect(art.enemy_frames(an, 2) == art.enemy_frames(an.replace("e_paranoia2", "e_paranoia_phase2"), 2) and art.enemy_frames(an, 2) > 2, "alias strip frames " + an)
	expect(art.enemy_pixel_anchor("e_paranoia2", Vector2.ZERO) == art.enemy_pixel_anchor("e_paranoia_phase2", Vector2.ONE), "alias strip anchor")
	# 常态 / 二阶段图鉴帧数同样按重画表
	expect(art.enemy_frames("e_paranoia", 2) == 6, "paranoia redraw frames")
	g.zone_state = 3
	g.zone_c = Vector2(100, 50)
	g.zone_r = 250.0
	g.zone_frozen = false
	g.ppos = Vector2(1000, 50)
	for mode in ["walk", "knockback", "charge", "transition"]:
		g.enemies.clear()
		var e: Dictionary = g.spawner.new_enemy("knight_boss", Vector2(320, 50))
		e.age = 5.0
		e.spd = 1000.0
		e.bt = -100.0
		e.cdt = 100.0
		e.kb = Vector2(1800, 0) if mode != "walk" else Vector2.ZERO
		e.kb_self = mode == "charge"
		g.zone_frozen = mode == "transition"
		g.zone_next_c = Vector2(700, 50)
		g.zone_next_r = 400.0
		g.enemies.append(e)
		g.enemies_sys.build_grid()
		g.enemies_sys.update(0.2)
		expect(e.pos.distance_to(g.zone_c) <= g.zone_r - e.r + 0.001, mode + " stays inside visible circle")
	g.enemies.clear()
	var charge: Dictionary = g.spawner.new_enemy("knight_boss", g.zone_c)
	charge.bt = -100.0
	charge.cdt = 100.0
	charge.spd = 0.0
	charge.kb = Vector2(200, 0)
	charge.kb_self = true
	g.enemies.append(charge)
	g.enemies_sys.build_grid()
	g.enemies_sys.update(0.1)
	expect(charge.pos.x > g.zone_c.x + 15.0, "legal charge retains full self propulsion")
	g.zone_state = 0
	g.enemies.clear()
	var free: Dictionary = g.spawner.new_enemy("knight_boss", Vector2(900, 50))
	free.bt = -100.0
	free.cdt = 100.0
	g.enemies.append(free)
	g.enemies_sys.build_grid()
	g.enemies_sys.update(0.01)
	expect(free.pos.x > 800.0, "no invisible constraint before tide")
	print("BOSS BOUNDARY failures=", failures)
	g.queue_free()
	g = null
	await get_tree().process_frame
	get_tree().quit.call_deferred(0 if failures == 0 else 1)
