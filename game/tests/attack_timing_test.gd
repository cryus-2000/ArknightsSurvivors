extends Node
const Ch = preload("res://scripts/characters/character.gd")
var game: Node
var ticks := 0
var fails := 0
var checks := 0

class Probe:
	extends "res://scripts/characters/character.gd"
	var releases := 0
	var release_frames: Array = []
	func _release() -> void:
		releases += 1
		release_frames.append(anim_state().frame)
	func _release_skill() -> void:
		releases += 1
		release_frames.append(anim_state().frame)
	func _notify_attack() -> void:
		pass

func ok(value: bool, message: String) -> void:
	checks += 1
	if not value:
		fails += 1
		printerr("FAIL: ", message)

func _ready() -> void:
	game = load("res://game.tscn").instantiate()
	add_child(game)

func _process(_dt: float) -> void:
	ticks += 1
	if ticks != 5:
		return
	set_process(false)
	game.set_process(false)
	for id in ["wisadel", "saria", "suzuran"]:
		var o = game.squad.get_op(id)
		ok(o != null, id + " loaded")
		if o == null:
			continue
		var expected: Array = {"wisadel": [1.4, 0.95, 2.5/12], "saria": [0.9, 0.65, 2.5/14], "suzuran": [1.0, 0.72, 2.5/14]}[id]
		ok(o.sprite_spec("attack").get("frames", 0) == 8, id + " eight frames")
		# Fail before integration on the existing short, uniform action window.
		o.start_attack(Vector2.INF)
		ok(absf(o.attack_dur - expected[1]) < 0.00001, id + " full recovery duration")
		if not o.sprite_spec("attack").has("attack_timing"):
			continue
		for key in ["duration", "fire_time", "active_ratio", "windup_ratio"]:
			var bad: Dictionary = o.sprite_spec("attack").duplicate(true)
			bad.attack_timing[key] = 0
			ok(not Ch.valid_attack_timing(bad), id + " rejects invalid " + key)
		for rate in [1.0, 1.5, 2.0, 3.0, 4.0]:
			var interval: float = expected[0] / rate
			o.start_attack(Vector2.INF, 0.5, 0.25, "", interval)
			var dur: float = minf(expected[1], interval * 0.9)
			var fire: float = minf(expected[2], dur * 0.45)
			ok(absf(o.attack_dur-dur)<0.00001 and absf(o.fire_t-fire)<0.00001, id + " timing " + str(rate))
			var seen := {}
			var release_entries := 0
			var previous := -1
			for ms in range(int(ceil(dur*1000))):
				o.anim_t = ms/1000.0
				o.attack_t = dur - o.anim_t
				var frame: int = o.anim_state().frame
				seen[frame] = true
				if frame == 3 and previous != 3:
					release_entries += 1
				previous = frame
			ok(seen.size() == 8 and release_entries == 1, id + " eight poses, one release")
			o.attack_t = 0.001
			ok(o.acting(), id + " recovery remains locked")
			o.attack_t = 0.0
			ok(not o.acting(), id + " unlock after full action")
			o.fire_t = -1.0
			var probe := Probe.new(game, o.def)
			probe.g = game
			probe.def = o.def
			probe.id = id
			probe.op_key = o.op_key
			probe.pos = game.ppos
			probe.is_leader = true
			probe.start_attack(Vector2.INF, 0.5, 0.25, "", interval)
			for tick in range(int(ceil(interval * 60)) + 2):
				probe.follow(1.0/60, probe.pos)
			ok(probe.releases == 1 and probe.release_frames == [3], id + " real follow fires once at pose 3")
			ok(not probe.acting(), id + " real follow completes before next attack")
		for slot in o.def.sprites:
			var spec = o.def.sprites[slot]
			if not spec is Dictionary or not spec.has("frame_durations"):
				continue
			ok(Ch.valid_frame_durations(spec), id + " valid durations " + slot)
			if not spec.has("fire_time"):
				continue   # 纯画面帧条（entry 入场 / death 倒下）：只验时长，不当技能事件测
			var invalid: Dictionary = spec.duplicate(true)
			invalid.frame_durations[0] = -0.1
			ok(not Ch.valid_frame_durations(invalid), id + " reject negative duration")
			var skill_probe := Probe.new(game, o.def)
			skill_probe.is_leader = true
			skill_probe.pos = game.ppos
			skill_probe.start_skill(Vector2.INF, 0, 0.6, 0.3, slot)
			ok(absf(skill_probe.fire_t - float(spec.fire_time)) < 0.000001, id + " exact skill event " + slot)
			for tick in 120:
				skill_probe.follow(1.0/60, skill_probe.pos)
			ok(skill_probe.releases == 1 and skill_probe.release_frames == [int(spec.fire)], id + " skill release pose " + slot)
		for idx in range(3):
			# Each case probes a different skill; cancel the prior sustained owner explicitly.
			if not o.phases.is_empty():
				ok(o.skills_occupied(), id + " prior sustained skill retains ownership")
				o.AttackPhases.cancel(o)
			o._sq_clear()
			o.attack_t = 0.0
			o.start_skill(Vector2.INF, idx)
			ok(o.act_kind == "skill" and o.attack_t > 0.0, id + " skill starts " + str(idx))
			for tick in 90:
				o.follow(1.0/60, o.pos)
			ok(o.attack_t <= 0.0, id + " skill unlocks " + str(idx))
		ok(o.sq_ph == 2, id + " S3 enters live loop")
		if id == "wisadel":
			o.start_attack(Vector2.INF, 0.5, 0.25, "", 0.84)
			o.follow(0.22, o.pos)
			ok(o.anim_state().kind == "skill_s3_attack" and o.anim_state().frame == 3, "Wisadel assembled cannon release")
			o.follow(0.7, o.pos)
			o.hw.wd.ammo = 0
		elif id == "saria":
			o.hw.sa.calc = 0.0
		else:
			o.hw.sz.haze_t = 0.0
		o.follow(1.0/60, o.pos)
		ok(o.sq_ph == 3, id + " S3 enters recovery")
		for tick in 45:
			o.follow(1.0/60, o.pos)
		ok(o.sq_ph == 0, id + " S3 recovery completes")
		var gallery = load("res://scripts/gallery.gd").new()
		var form: Dictionary = gallery._sprite_form("attack", o.sprite_spec("attack"), 8.0, true)
		gallery.form_t = float(o.sprite_spec("attack").attack_timing.fire_time) + 0.000001
		ok(gallery._form_frame(form) == 3, id + " gallery release matches game")
		gallery.free()
	print("ATTACK TIMING checks=%d failures=%d" % [checks, fails])
	get_tree().quit(1 if fails else 0)
