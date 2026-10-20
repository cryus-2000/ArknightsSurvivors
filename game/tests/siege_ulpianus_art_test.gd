extends Node
var fails := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", label)

func _ready() -> void:
	var g = load("res://game.tscn").instantiate()
	add_child(g)
	for i in 5: await get_tree().process_frame
	g.set_process(false)
	for id in ["siege", "ulpianus"]:
		var o = g.squad.get_op(id)
		check(o != null, id + " loaded")
		if o == null: continue
		for slot in ["idle", "run", "attack", "death"]:
			var spec: Dictionary = o.sprite_spec(slot)
			check(int(spec.get("frames", 0)) == 8, id + " " + slot + " eight poses")
			var tx: Texture2D = o.anim_tex(slot)
			check(tx != null and tx.get_width() == 8 * tx.get_height(), id + " " + slot + " strip loaded")
		var rng: Array = g.rng_states()
		o.start_attack(o.pos + Vector2(120, 0))
		var duration: float = 4.0 / 14.0 if id == "siege" else 5.0 / 12.0
		var fire: float = 2.5 / 14.0 if id == "siege" else 3.5 / 12.0
		check(absf(o.attack_dur - duration) < 0.000000001 and absf(o.fire_t - fire) < 0.000000001, id + " gameplay window and release unchanged")
		check(rng == g.rng_states(), id + " animation consumes no gameplay RNG")
		o.native_motion.t = fire
		check(int(o.anim_state().frame) == (2 if id == "siege" else 3), id + " visual event pose matches actual hit time")
		o.native_motion.t = duration + 0.01
		o.attack_t = 0.0
		o.anim_kind = "idle"
		check(o.anim_state().kind == "attack", id + " visual recovery can finish without extending gameplay window")
		o.start_attack(o.pos + Vector2(120, 0))
		check(o.anim_state().frame == 0, id + " new attack restarts its own motion")
		o.face = -1.0
		check(o.anim_state().flip, id + " left facing mirrors native motion")
		o.face = 1.0
		o.attack_t = 0.0
		o.fire_t = -1.0
		if id == "siege":
			check(not o.def.sprites.has("command"), "handoff command removed")
			o.start_skill(o.pos, 0)
			check(o.anim_state().kind == "idle", "S1 retains normal holding pose")
			check(absf(o.fire_t - 2.5 / 12.0) < 0.000000001, "S1 command event unchanged")
			o.hw.sg = {"leap_t": 0.2, "leap_b": {"t": 0.42}}
			check(o.anim_state().kind == "leap_native", "leap body follows actual leap phase")
			check(not o.SegSiege.h4_draw_body(o), "legacy whole-body flip is disabled for native leap")
		else:
			for phase in ["throw", "reel", "hold", "zip"]:
				o.hw.anchor = {"phase": phase, "t": 0.05, "dur": 0.2, "b": {"mode": "reel"}}
				var st: Dictionary = o.anim_state()
				check(st.kind == ("zip_native" if phase == "zip" else "tether_native"), "Ulpianus phase " + phase + " body")
				check(int(st.frame) in range(1, 6), "detached phase never returns to holding idle")
				check(o.sprite_point("hand") != Vector2.INF, "chain has native hand socket")
			o.hw.anchor = {}
			for phase in ["fly", "taut", "drag"]:
				o.hw.hooks = [{"phase": phase, "t": 0.05, "dur": 0.2}]
				check(o.anim_state().kind == "tether_native", "elite hook " + phase + " uses native body")
			o.hw.hooks = []
			o.perm[1] = true
			o.start_attack(o.pos + Vector2(120, 0))
			check(o.anim_state().kind == "attack_s2", "permanent S2 uses its native strike")
	print("SIEGE ULPIANUS ART failures=", fails)
	for o in g.squad.ops:
		o.hw.clear()
		o.native_motion.clear()
		o.lifecycle.clear()
		o.phases.clear()
		o.pfx.clear()
	g.world._gc_sink = null
	var hud = g.hud_view
	for section in [hud.bars, hud.relics, hud.squad, hud.banners]: section.h = null
	g.queue_free()
	await get_tree().process_frame
	hud._layers.clear()
	Sfx.set_process(false)
	for player in Sfx.get_children():
		if player is AudioStreamPlayer:
			player.stop()
			player.stream = null
			player.queue_free()
	await get_tree().create_timer(0.1).timeout
	get_tree().quit(1 if fails else 0)
