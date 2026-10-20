extends Node

const Blocks = preload("res://scripts/characters/op_blocks.gd")
var failures := 0

class PulseOwner extends RefCounted:
	var hw := {"on": true, "pools": [], "burns": [], "lobs": [], "shells": [], "erupts": [], "pulse": {}}
	var g := {"bullets": [], "rng_op": RandomNumberGenerator.new()}
	var pos := Vector2(10, 20)
	var face := 1.0
	var s_dur := [0.0, 0.0, 0.0]
	var events: Array = []
	func stat(_key) -> float: return 1.0
	func densest_point(_r, _p) -> Vector2: return Vector2(220, 20)
	func _exec_list(actions: Array, at: Vector2) -> void: events.append({"actions": actions, "at": at})
	func fx(_f: Dictionary) -> void: pass

func check(ok: bool, why: String) -> void:
	if not ok:
		failures += 1
		push_error(why)

func _ready() -> void:
	var lob := {"from": Vector2(10, -20), "to": Vector2(210, -20), "dur": 0.6, "h": 60.0,
		"b": {"look": {"weighted": true, "apex_k": 1.0, "arc_pow": 0.55}}}
	check(Blocks._hw_lob_pos_at(lob, 0.0).is_equal_approx(lob.from), "launch remains at its actual source")
	check(Blocks._hw_lob_pos_at(lob, lob.dur).is_equal_approx(lob.to), "landing remains at actual damage position")
	var last: Vector2 = lob.from
	var peak := 0
	var top := 0.0
	for i in 21:
		var p: Vector2 = Blocks._hw_lob_pos_at(lob, lob.dur * i / 20.0)
		check(p.x >= last.x, "flight never reverses horizontally")
		if p.y < top:
			top = p.y
			peak = i
		last = p
	check(peak < 10, "rock crests before half flight and commits to descent")
	check(Blocks._hw_lob_pos_at(lob, lob.dur * 0.001).distance_to(lob.from) < 2.0,
		"finite launch velocity avoids the initial visual hop")
	check(Blocks._hw_lob_pos_at(lob, lob.dur * 0.999).distance_to(lob.to) < 2.0,
		"finite landing velocity avoids a final position snap")
	lob.b.look = {"arc_pow": 0.55, "apex_k": 1.0}
	check(Blocks._hw_lob_pos_at(lob, 0.3).is_equal_approx(Vector2(110, -80)), "unweighted legacy appearance remains available")
	check_pulse()
	await check_runtime()
	print("EYJA VOLCANIC WEIGHT failures=", failures)
	get_tree().quit(1 if failures else 0)

func check_pulse() -> void:
	var o := PulseOwner.new()
	o.g.rng_op.seed = 1
	var sb := {"dur": {"pulses": 3, "every": 0.2}, "pulse": {"r": 300.0, "recovery": 0.28,
		"projectile": {"tip": [0, -54], "speed": 300.0, "min_flight": 0.3, "max_flight": 0.8, "apex": 24.0, "size": 1.2},
		"launch": [{"test": "launch"}], "do": [{"test": "impact"}]}}
	Blocks.hw_pulse_start(o, 2, sb)
	Blocks._hw2_tick(o, 1.0 / 60.0)
	check(o.hw.erupts.size() == 1 and o.hw.erupts[0].has("shot"), "S3 sends a visible body projectile for each pulse")
	if o.hw.erupts.size() == 1 and o.hw.erupts[0].has("shot"):
		check(o.hw.erupts[0].shot.from == o.pos + Vector2(0, -54), "S3 starts at the airborne body socket")
	for i in 10: Blocks._hw2_tick(o, 1.0 / 60.0)
	check(not o.events.any(func(e): return e.actions[0].test == "impact"), "S3 cannot damage before projectile arrival")
	for i in 90: Blocks._hw2_tick(o, 1.0 / 60.0)
	check(o.events.filter(func(e): return e.actions[0].test == "launch").size() == 3, "every airborne pulse launches its payload once")
	check(o.events.filter(func(e): return e.actions[0].test == "impact").size() == 3, "each pulse resolves one landing without duplicate damage")
	check(o.hw.erupts.is_empty() and o.hw.pulse.is_empty(), "projectiles and channel clear after their last event")
	o.hw.pulse = {"i": 2, "n": 0, "t": 0.0, "every": 0.2, "sp": {"recovery": 0.28}}
	check(Blocks.hw_active_left(o, 2) == 0.0, "last launch ends floating loop immediately")
	check(Blocks._hw2_tick(o, 0.05), "short descent completes before another attack can interrupt it")
	for i in 6: Blocks._hw2_tick(o, 0.05)
	check(o.hw.pulse.is_empty(), "descent does not leave the operator busy")

func check_runtime() -> void:
	var game = load("res://game.tscn").instantiate()
	add_child(game)
	for i in 5: await get_tree().process_frame
	game.set_process(false)
	game.mode = game.Mode.PLAY
	game.state = game.S.PLAY
	game.sandbox = true
	game.invuln = 999.0
	var op = game.squad.get_op("eyjafjalla")
	check(op != null, "runtime loads Eyjafjalla")
	if op == null:
		game.queue_free()
		return
	for e in game.enemies: e.dead = true
	game.enemies.clear()
	var target: Dictionary = game.spawner.spawn_enemy("stone", game.ppos + Vector2(180, 0))
	target.hp = 10000000.0
	target.max_hp = target.hp
	target.spd = 0.0
	var second: Dictionary = game.spawner.spawn_enemy("stone", game.ppos + Vector2(220, 30))
	second.hp = 10000000.0
	second.max_hp = second.hp
	second.spd = 0.0
	game.enemies_sys.build_grid()
	check_growth(game, op, target.pos)
	op._sq_clear()
	op.attack_t = 0.0
	op.fire_t = -1.0
	op.cd = 10000.0
	op.hw.erupts.clear()
	op.hw.lobs.clear()
	op.hw.pulse = {}
	op.start_skill(target.pos, 2)
	var total := int(op.base("s3_count", 10))
	var left := total
	var launches := 0
	var last_launch := -1.0
	var bonus := 0
	var resumed := false
	var evidence: Array = []
	for frame in 240:
		op.sp = [-100000.0, -100000.0, -100000.0]
		op.cd = 0.0 if launches == total else 10000.0
		var end_left: float = op._seq_len(op.sq.get("end")) - float(op.sq_t) if op.sq_ph == 3 else 0.0
		game._update(1.0 / 60.0)
		if launches == total and op.act_kind == "attack" and op.attack_t > 0.0 and not resumed:
			check(end_left <= 1.0 / 60.0 + 0.00001, "next ordinary attack cannot cut the last descent frame")
			resumed = true
		var remaining: int = int(op.hw.get("pulse", {}).get("n", 0))
		if op.fire_t >= 0.0 and launches == 0: remaining = total
		if remaining < left:
			var time: float = float(frame) / 60.0
			var state: Dictionary = op.anim_state()
			check(state.kind in ["skill_s3", "skill_s3_loop"], "each S3 launch occurs in airborne body animation")
			if state.kind == "skill_s3": check(int(state.frame) >= 4, "S3 does not throw while still on ground")
			if last_launch >= 0.0: check(time - last_launch <= 0.23, "airborne volleys have no empty pause")
			last_launch = time
			launches += left - remaining
			evidence.append({"time": time, "kind": state.kind, "frame": state.frame, "remaining": remaining})
		left = remaining
		for lob in op.hw.lobs:
			if float(lob.t) == 0.0 and str(lob.src) == "熔岩天降":
				bonus += 1
				check((lob.from as Vector2).distance_to(op.pos + Vector2(8, -54)) < 1.0, "bonus fireballs launch from body during volley")
		if last_launch >= 0.0 and left == 0 and float(frame) / 60.0 - last_launch > 0.35:
			check(op.anim_state().kind != "skill_s3_loop", "last launch never leaves an empty hovering loop")
	check(launches == total, "runtime preserves S3 volley count")
	check(resumed, "ordinary attacks resume after the short descent")
	check(bonus == total * int(op.base("meteor_n", 2)), "runtime preserves bonus fireball count")
	check(target.hp < target.max_hp, "slower projectiles still resolve actual damage")
	op.face = -1.0
	Blocks.hw_lob(op, op.B.skills[2].pulse.launch[0], target.pos)
	check(not op.hw.lobs.is_empty() and (op.hw.lobs[-1].from as Vector2).distance_to(op.pos + Vector2(-8, -54)) < 1.0,
		"left-facing body launches mirror their socket")
	check_impact(game, op, target)
	var record := FileAccess.open("res://../build/eyja_volcanic_weight/airborne_launches.json", FileAccess.WRITE)
	if record:
		record.store_string(JSON.stringify({"launches": evidence, "bonus_count": bonus}))
		record.close()
	for operator in game.squad.ops:
		operator.hw.clear()
		operator.lifecycle.clear()
		operator.phases.clear()
		operator.pfx.clear()
	game.world._gc_sink = null
	var hud = game.hud_view
	for section in [hud.bars, hud.relics, hud.squad, hud.banners]: section.h = null
	game.queue_free()
	await get_tree().process_frame
	hud._layers.clear()
	Sfx.set_process(false)
	for player in Sfx.get_children():
		if player is AudioStreamPlayer:
			player.stop()
			player.stream = null
			player.queue_free()
	await get_tree().process_frame

func check_growth(game, op, at: Vector2) -> void:
	var initial: Dictionary = {}
	for node_index in 7:
		if node_index > 0:
			var node: Dictionary = op.next_node()
			var choices: Dictionary = op.elite_choices(node) if node.get("type", "") == "elite" else {}
			op.advance(choices.keys()[0] if not choices.is_empty() else "")
		game.bullets.clear()
		op.hw["shells"] = []
		op.hw["lobvol"] = []
		op.atk_aim = at
		op._sq_clear()
		op.sp = [-100000.0, -100000.0, -100000.0]
		op.cd = 10000.0
		op.act_kind = "attack"
		op.attack_t = 0.1
		op.fire_t = 0.0
		var raw: float = op.base("atk", 0.0) * op._dmg_bonus()
		op.follow(1.0 / 60.0, op.pos)
		if op.elite == 0:
			check(game.bullets.size() == 1 and op.hw.shells.is_empty(), "E0 stays one main fireball after every E0 growth node")
			var expected: float = 1.0 if node_index == 0 else 1.6
			check(game.bullets.size() == 1 and is_equal_approx(float(game.bullets[0].dmg), raw * expected), "E0 twin-cast damage node=%d actual=%s raw=%f atk=%s" % [node_index, str(game.bullets.map(func(b): return b.dmg)), raw, str(op.loc.atk)])
			check(game.bullets.size() == 1 and game.bullets[0].get("hw_fireball", false), "E0 snapshots its fireball presentation when launched")
			if node_index == 0 and game.bullets.size() == 1: initial = game.bullets[0].duplicate()
		elif op.elite == 1:
			check(is_equal_approx(float(op.loc.atk), 1.0), "E1 removes E0-only single-shot multiplier")
			check(game.bullets.size() == 1 and op.hw.shells.size() == 1, "E1 retains the second magma projectile")
			check(game.bullets.size() == 1 and is_equal_approx(float(game.bullets[0].dmg), raw), "E1 first shot keeps its original damage")
			Blocks._hw2_tick(op, 0.13)
			check(game.bullets.size() == 2 and is_equal_approx(float(game.bullets[-1].dmg), raw * 0.6), "E1 delayed second shot keeps 0.6 damage")
		else:
			check(game.bullets.is_empty() and op.hw.lobvol.size() == 1 and op.hw.lobvol[0].shots.size() == 3, "E2 retains three low-arc projectiles")
			if op.hw.lobvol.size() == 1:
				Blocks._hw5_lobs(op, 0.25)
				for i in 3:
					check(is_equal_approx(float(op.hw.lobvol[0].shots[i].dmg), raw * (1.0 if i == 0 else 1.4)), "E2 keeps original per-shot damage")
		op.update(0.0)
	if not initial.is_empty():
		op.pfx.clear()
		initial.hw_oe = []
		Blocks.hw_shell_boom(op, initial)
		check(op.pfx.any(func(f): return f.kind == "fireball_burst") and not op.pfx.any(func(f): return f.get("mass", false)), "E0 projectile landing after promotion keeps its fire burst, not rock debris")
	game.bullets.clear()
	op.hw.shells.clear()
	op.hw.lobvol.clear()

func check_impact(game, op, target: Dictionary) -> void:
	game.fx.clear()
	op.pfx.clear()
	game.vfx.impact_at = -99.0
	var pauses := int(game.vfx.stop_stat.get("impact", [0])[0])
	var hp: float = target.hp
	var shell := {"kind": "fire", "pos": target.pos, "aoe": 58.0, "dmg": 10.0, "life": 1.0,
		"src": "点燃弹", "op": "eyjafjalla", "fx_col": Color.ORANGE,
		"hw_b": op.B.skills[1].do[0], "hw_oe": [], "on_hit": op}
	game.weapons_sys.bullet_hit(shell, target)
	check(target.hp < hp and shell.life == 0.0, "unified impact preserves direct shell damage and cleanup")
	# Normal target contact sparks remain; the generic fire blast scatters for 0.45 s.
	check(not game.fx.any(func(f): return f.kind == "explode" or (f.kind == "spark" and is_equal_approx(float(f.max), 0.45))), "weighted shell does not stack the generic explosion and long scatter sparks")
	check(not op.pfx.any(func(f): return f.kind in ["ring", "mote"]), "weighted shell replaces legacy rings and scattered debris")
	check(op.pfx.filter(func(f): return f.get("mass", false)).size() == 1, "weighted shell has one shared ground impact")
	check(int(game.vfx.stop_stat.get("impact", [0])[0]) == pauses + 1, "unified impact retains the original heavy shell hitstop cue")
	game.fx.clear()
	shell.erase("on_hit")
	shell.erase("hw_b")
	shell.life = 1.0
	game.weapons_sys.bullet_hit(shell, target)
	check(game.fx.any(func(f): return f.kind == "explode"), "legacy unweighted fire keeps its original explosion")
