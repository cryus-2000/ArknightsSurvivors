extends Node
const A = preload("res://scripts/art.gd")
var fails := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", label)

func _ready() -> void:
	var g = load("res://game.tscn").instantiate()
	add_child(g)
	for i in 5:
		await get_tree().process_frame
	g.set_process(false)
	var approved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/data_ops/approved_attack_rhythm.json"))
	for id in ["exusiai", "eyjafjalla", "logos"]:
		var o = g.squad.get_op(id)
		check(o != null, id + " is loaded")
		if o == null:
			continue
		for slot in ["idle", "run", "attack", "skill", "death"]:
			var spec: Dictionary = o.sprite_spec(slot)
			var tx: Texture2D = o.anim_tex(slot)
			check(int(spec.get("frames", 0)) == 8, id + " " + slot + " uses eight native poses")
			var foot: Array = spec.get("foot", [])
			check(foot.size() == 2 and float(foot[0]) == (48.0 if id == "eyjafjalla" and slot == "death" else 32.0) and float(foot[1]) == (76.0 if id == "eyjafjalla" and slot == "death" else 60.0), id + " " + slot + " shares the runtime foot anchor")
			var hk: float = A.hires_of(tx) / 2.0 if tx != null else 1.0   # render/op_1x（docs/128）开着时读 1 倍条：画布减半、帧数 / 脚底不变
			check(tx != null and tx.get_height() == int((192 if id == "eyjafjalla" and slot == "death" else 128) * hk) and tx.get_width() == tx.get_height() * 8, id + " " + slot + " loads the packaged strip (@2x or op_1x)")
		var before: Array = g.rng_states()
		o.cd=approved[id].cycle
		o.start_attack(o.pos + Vector2(200, 0))
		var expected: Array = [approved[id].duration,approved[id].fire]
		check(absf(o.attack_dur-expected[0])<1e-9 and absf(o.fire_t - expected[1]) < 1e-9, id + " approved recovery and original release time")
		o.anim_t = float(expected[1]) + 0.000001
		o.attack_t = o.attack_dur - o.anim_t
		check(int(o.anim_state().frame) == int(o.sprite_spec("attack").get("fire", -1)), id + " releases on its native attack-event pose")
		check(before == g.rng_states(), id + " art scheduling consumes no gameplay RNG")
		o.attack_t = 0.0
		o.fire_t = -1.0
		o._sq_clear()
		o.anim_kind = "idle"
		o.vis_anim = ""
		var idle: Array = o.sprite_spec("idle").frame_durations
		var last_start: float = o.frames_seconds("idle", range(7))
		var total: float = o.frames_seconds("idle", range(8))
		for sample in [[float(idle[0]) - 0.000001, 0], [float(idle[0]) + 0.000001, 1], [last_start + 0.000001, 7], [total + 0.000001, 0]]:
			o.anim_t = float(sample[0])
			check(int(o.anim_state().frame) == int(sample[1]), id + " idle follows its nonuniform frame boundaries at " + str(sample[0]))
		for skill in ([2] if id == "eyjafjalla" else ([0, 2] if id == "logos" else [])):
			check(o._start_skill_seq(o.pos + Vector2(200, 0), int(skill)), id + " starts native skill sequence " + str(skill))
			check(o.attack_dur == 8.0 / 12.0, id + " sequence exactly retains the previous skill window " + str(skill))
			o.attack_t = 0.0
			o.fire_t = -1.0
			o._sq_clear()
	check(g.tex.get("proj_logos_ink_a") != null and g.tex.get("proj_logos_ink_b") != null and g.tex.get("fx_logos_s1_chain") != null, "Logos keeps both new projectiles and connected runes")
	var logos = g.squad.get_op("logos")
	logos.hw.bolt_variant = 1
	logos.start_attack(logos.pos + Vector2(200, 0))
	check(logos.anim_state().kind == "attack_b", "Logos second bolt uses its matching native body pose")
	logos.fire_t = -1.0
	logos.hw.bolt_variant = 0
	check(logos.anim_state().kind == "attack_b", "Logos body does not switch when its bolt fires")
	logos.hw.bolt_variant = 1
	logos.start_attack(logos.pos + Vector2(200, 0))
	logos.fire_t = -1.0
	check(logos.anim_state().kind == "attack_b", "a target lost during windup cannot flip the body pose during recovery")
	logos.perm[1] = true
	check(logos.anim_state().kind == "attack_s2", "permanent S2 uses its native upgraded attack")
	logos.anim_kind = "idle"
	logos.attack_t = 0.0
	check(logos.anim_state().kind == "idle_s2", "permanent S2 retains its native upgraded idle")
	logos.perm[1] = false
	logos.sq = logos.def.sprites.skills.s3
	logos.sq_i = 2
	logos.sq_ph = 2
	logos.sq_own = false
	logos.sq_atk = "skill_s3_attack"
	logos.sq_atk_t = 2.5 / 12.0 + 0.000001
	check(absf(logos._sq_atk_off()) < 0.000001, "S3 body variant aligns to explicit release seconds rather than uniform frame centres")
	check(logos._sq_atk_frame(8) == int(logos.sprite_spec("skill_s3_attack").fire), "S3 body variant samples its nonuniform native event pose")
	logos.act_anim = "attack"
	logos.act_kind = "attack"
	logos.attack_dur = 4.0 / 12.0
	logos.attack_t = 0.01
	logos.sq_atk = ""
	logos.sq_atk_t = 0.32
	logos._tick_sq_atk(0.001)
	check(logos.sq_atk == "", "finished short variants stay off during the remainder of the same attack")
	logos._sq_clear()
	print("THREE OPERATOR ART failures=", fails)
	g.world._gc_sink = null
	var hud = g.hud_view
	for section in [hud.bars, hud.relics, hud.squad, hud.banners]:
		section.h = null
	g.queue_free()
	await get_tree().process_frame
	hud._layers.clear()
	get_tree().quit(1 if fails else 0)
