extends Node
## Targeted enemy status regression; launch only via tools/godot_runner.py.
const Bal = preload("res://scripts/core/balance.gd")
var game: Node
var frames := 0
var failures := 0
func _ready() -> void:
	game = load("res://game.tscn").instantiate()
	add_child(game)
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: ", label)
func reset() -> void:
	game.t += 10.0
	game.hp = game.max_hp
	game.invuln = 0.0
	game.shield = 0
	game.frost = 0.0
	game.corrode_pool = 0.0
	game.nerve = 0.0
	game.lamp = 100.0
	game.dodge = 0.0
	game.dodge_phys = 0.0
	game.dodge_arts = 0.0
	game.ebullets.clear()
	game.lobs.clear()
	game.combat.corrode_boss = 0.0
	game.combat.boss_log.clear()
	game.combat.loss_log.clear()
	game.combat.any_log.clear()
func contact_hit(e: Dictionary) -> void:
	e.pos = game.ppos
	e.dash_t = 0.2
	e.dash_dir = Vector2.RIGHT
	game.enemies_sys.update(0.0)
	e.pos = game.ppos + Vector2(500, 0)
func lob_hit(e: Dictionary) -> void:
	game.eai.lob(e)
	game.lobs[-1].to = game.ppos
	game.enemies_sys.update_lobs(1.0)
func shot_hit(e: Dictionary) -> void:
	game.eai.shoot(e, Vector2.RIGHT)
	for b in game.ebullets:
		b.pos = game.ppos + Vector2(0, -14)
		b.vel = Vector2.ZERO
	game.enemies_sys.update_ebullets(0.0)
func _process(_dt: float) -> void:
	frames += 1
	if frames != 5:
		return
	set_process(false)
	game.set_process(false)
	reset()
	var knight: Dictionary = game.spawner.spawn_enemy("knight", game.ppos + Vector2(500, 0))
	game.in_type = ["近战", "物理"]
	contact_hit(knight)
	check(game.hp < game.max_hp and is_equal_approx(game.frost, 1.5), "knight accepted hit applies frost")
	reset()
	game.shield = 1
	contact_hit(knight)
	check(game.hp == game.max_hp and game.frost == 0.0, "shield blocks knight frost")
	reset()
	game.invuln = 1.0
	contact_hit(knight)
	check(game.hp == game.max_hp and game.frost == 0.0, "invulnerable knight contact adds no frost")
	reset()
	var acid: Dictionary = game.spawner.spawn_enemy("spitter", game.ppos + Vector2(500, 0))
	lob_hit(acid)
	check(game.hp < game.max_hp and game.corrode_pool > 0.0, "spitter actual lob applies corrosion")
	reset()
	game.invuln = 1.0
	lob_hit(acid)
	check(game.hp == game.max_hp and game.corrode_pool == 0.0, "invulnerable lob adds no corrosion")
	reset()
	game.shield = 1
	lob_hit(acid)
	check(game.hp == game.max_hp and game.corrode_pool == 0.0, "shielded lob adds no corrosion")
	reset()
	var mother: Dictionary = game.spawner.spawn_enemy("mother", game.ppos + Vector2(500, 0))
	shot_hit(mother)
	check(game.corrode_pool > 0.0, "mother projectile inherits corrosion")
	reset()
	var brood: Dictionary = game.spawner.spawn_enemy("brood", game.ppos + Vector2(100, 0))
	brood.cdt = 0.0
	game.eai.pattern(brood, Vector2.LEFT, 100.0, 0.01, 0.0)
	check(is_equal_approx(game.ebullets[-1].corrode, 0.35), "brood acid inherits tuned coefficient")
	reset()
	var offspring: Dictionary = game.spawner.spawn_enemy("offspring", game.ppos + Vector2(100, 0))
	offspring.nova_w = 0.01
	game.eai.pattern(offspring, Vector2.LEFT, 100.0, 0.02, 0.0)
	check(is_equal_approx(game.ebullets[-1].corrode, 0.15), "offspring nova inherits mild corrosion")
	reset()
	var cap: float = Bal.v("enemy/corrode_pool_cap", 0.0)
	if cap > 0.0:
		game.corrode_pool = game.max_hp * cap
		lob_hit(acid)
		check(game.corrode_pool <= game.max_hp * cap + 0.0001, "acid obeys existing nonboss corrosion pool cap")
	# 控制遥测（用户 10-01，combat.ctrl_src）：奠基者叠满寒霜 → 冻结次数 +1、冻结秒数按帧累计、寒霜减速记到奠基者；冲刺挣脱 +1
	reset()
	var dmod_old: Dictionary = game.dmod.duplicate()
	var state_old = game.state
	game.state = game.S.PLAY
	game.dmod["ctrl_start"] = 0.0
	game.dmod["frost_max"] = 2.0
	game.cold = 0
	game.cold_immune = 0.0
	game.root_t = 0.0
	game.root_immune = 0.0
	var founder: Dictionary = game.spawner.spawn_enemy("founder", game.ppos + Vector2(500, 0))
	game.combat.enemy_hit(10.0, founder, false, true)
	game.invuln = 0.0
	game.combat.enemy_hit(10.0, founder, false, true)
	var fs: Dictionary = game.combat.ctrl_src_report()
	check(game.root_t > 0.0 and fs.founder.freeze_n == 1 and fs.skimmer.freeze_n == 0, "founder full frost counts one freeze for founder")
	game.combat.update_ctrl(0.1)
	fs = game.combat.ctrl_src_report()
	check(is_equal_approx(fs.founder.freeze_t, 0.1) and is_equal_approx(fs.founder.slow_t, 0.1) and is_equal_approx(fs.slow_any_t, 0.1), "freeze and frost slow seconds tallied to founder")
	game.dash_cd = 0.0
	game.dash_t = 0.0
	game._try_dash()
	fs = game.combat.ctrl_src_report()
	check(game.root_t == 0.0 and fs.founder.dash_break_n == 1, "dash out of freeze counts one break")
	game.cold = 0
	game.cold_immune = 0.0
	game.root_immune = 0.0
	game.dash_t = 0.0
	game.dmod = dmod_old
	game.state = state_old
	reset()
	var bone: Dictionary = game.spawner.spawn_enemy("bone", game.ppos + Vector2(500, 0))
	game.combat.enemy_hit(10.0, bone, false, true)
	check(game.frost == 0.0, "ordinary sea mob does not freeze")
	reset()
	var boss: Dictionary = game.spawner.spawn_enemy("knight_boss", game.ppos + Vector2(500, 0))
	game.bosses.append(boss)
	game.combat.enemy_hit(10.0, boss, false, true)
	check(is_equal_approx(game.frost, 2.0), "boss knight accepted hit applies frost")
	check(game.combat.move_mult(0.1) >= Bal.v("boss/move_floor", 0.7), "frost preserves boss movement floor")
	reset()
	game.combat.boss_log.append([game.t, game.max_hp])
	game.combat.loss_log.append([game.t, game.max_hp])
	game.combat.enemy_hit(10.0, boss, false, true)
	check(game.hp == game.max_hp and game.frost == 0.0, "boss capped hit adds no frost")
	print("ENEMY STATUS TEST: ", failures, " failures")
	game.queue_free()
	game = null
	Sfx.set_process(false)
	await get_tree().create_timer(0.25, true, false, true).timeout
	for player in Sfx.get_children():
		if player is AudioStreamPlayer:
			player.stop()
			player.stream = null
			player.queue_free()
	await get_tree().create_timer(0.2, true, false, true).timeout
	get_tree().quit.call_deferred(failures)
