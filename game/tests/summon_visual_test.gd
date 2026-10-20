extends Node

var fails := 0

class FakeOperator extends RefCounted:
	var g := {"t": 10.0, "perf_alt": false}
	var sm := {"list": []}
	var B := {"summons": {"sea": {"anim": {"attack": "cast"}}}}
	var specs := {}
	var executions: Array = []
	var texture: Texture2D = ImageTexture.create_from_image(Image.create(4, 1, false, Image.FORMAT_RGBA8))
	func sprite_spec(key: String) -> Dictionary:
		return specs.get(key, {})
	func anim_tex(_key: String) -> Texture2D:
		return texture
	func anim_hframes(_tx: Texture2D, _key: String) -> int:
		return 4
	func _exec_list(items: Array, _pos: Vector2) -> void:
		executions.append([items.duplicate(), g.t, sm.list[0].get("visual", {}).duplicate(true)])

func ok(value: bool, label: String) -> void:
	if not value:
		fails += 1
		print("FAIL ", label)

func _ready() -> void:
	for _i in 5:
		await get_tree().process_frame
	var path := "res://scripts/characters/summon_visual.gd"
	if not ResourceLoader.exists(path):
		ok(false, "independent native visual sampler is available")
	else:
		var v = load(path)
		var meta := {"anim": "native", "times": [0.0, 0.2, 0.5, 0.8], "duration": 1.0, "event": 0.5}
		var state := {}
		v.start(state, meta, 10.0, 0.18)
		ok(v.frame(meta, v.time(state, 10.1), false) == 1, "windup scales independently of gameplay duration")
		v.hit(state, 10.21)
		ok(is_equal_approx(v.time(state, 10.21), 0.5), "quantized actual hit reaches exact source event")
		ok(is_equal_approx(v.time(state, 10.51), 0.8), "recovery survives legacy action ending")
		var ghost: Dictionary = state.duplicate(true)
		v.start(state, meta, 10.6, 0.18)
		ok(is_equal_approx(v.time(ghost, 10.51), 0.8), "snapshot does not read new attack record")
		v.cancel(state)
		ok(not state.has("visual"), "dash or patch can interrupt visual recovery")
		v.start(state, {}, 11.0)
		ok(not state.has("visual"), "legacy specs do not allocate native visual records")
		ok(v.frame(meta, 1.2, true) == 1, "idle uses source duration and sample timestamps")
		var sprites := {"base": {"visual": meta}, "native": {"frames": 4, "tex": "test"}}
		ok(v.errors(sprites, ["native"]).is_empty(), "valid opt in metadata")
		for bad_frames in [{}, [], "4", 1.5, 0, -1, null]:
			var invalid: Dictionary = sprites.duplicate(true)
			invalid.native.frames = bad_frames
			var reported = v.errors(invalid, ["native"])
			ok(reported is Array and not reported.is_empty(), "malformed native frame count rejected: " + str(bad_frames))
		for bad_target in ["native", [], null]:
			var invalid: Dictionary = sprites.duplicate(true)
			invalid.native = bad_target
			var reported = v.errors(invalid, ["native"])
			ok(reported is Array and not reported.is_empty(), "non-dictionary native slot rejected: " + str(bad_target))
		for bad in [{"anim": "missing"}, {"times": []}, {"times": [0.0, 0.2, 0.2, 0.8]}, {"duration": 0.7}, {"event": 1.1}, {"times": [0.0, 0.2]}]:
			var invalid: Dictionary = sprites.duplicate(true)
			invalid.base.visual.merge(bad, true)
			ok(not v.errors(invalid, ["native"]).is_empty(), "invalid timeline rejected: " + str(bad))
		test_integration(v, meta)
	print("SUMMON VISUAL failures=%d" % fails)
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null:
		sfx.set_process(false)
		for player in sfx.get_children():
			if player is AudioStreamPlayer:
				player.stop()
				player.stream = null
	await get_tree().process_frame
	get_tree().quit(1 if fails else 0)

func test_integration(v, meta: Dictionary) -> void:
	var ob = load("res://scripts/characters/op_blocks.gd")
	var o := FakeOperator.new()
	o.specs = {"cast": {"frames": 4, "fps": 10, "fire": 2, "visual": meta}}
	var s := {"e5": true, "gone": false, "kind": "sea", "ak": "idle", "at": 0.0, "act": 0.0, "fire": -1.0, "pos": Vector2.ZERO, "e5_then": []}
	o.sm.list = [s]
	ob.e5_cast(o, {"kind": "sea", "then": ["old"]})
	ok(is_equal_approx(s.act, 0.4) and is_equal_approx(s.fire, 0.25), "legacy cast action and release are unchanged")
	o.g.t = 10.27
	ob.e5_cast(o, {"kind": "sea", "then": ["new"]})
	ok(o.executions.size() == 1 and o.executions[0][0] == ["old"], "new cast flushes previous pending gameplay once")
	ok(is_equal_approx(o.executions[0][2].hit, 10.27), "pending flush stamps actual hit before new visual record")
	ok(float(s.visual.hit) < 0.0 and is_equal_approx(s.visual.start, 10.27), "new cast interrupts old recovery after flush")
	o.g.t = 10.54
	ob.e5_cast_fire(o, s)
	s.ak = "run"
	o.g.t = 10.84
	ok(ob.mf_visual_frame(o, s, "cast", 0.0)[1] == 3, "native recovery displays after controller returns to run")
	var frozen: Array = ob.mf_visual_frame(o, s, "cast", 0.0)
	ob.e5_cast(o, {"kind": "sea", "then": []})
	ok(frozen[1] == 3 and ob.mf_visual_frame(o, s, "cast", 0.0)[1] == 0, "resolved ghost frame stays frozen across new cast")
	s.merge({"pidx": 0, "pt": 0.0, "pout": 0.0, "pold": -1}, true)
	ob._mf_patch_tick(o, s, {}, 0.01)
	ok(not s.has("visual"), "real patch transition clears recovery")
	s.ak = "spawn"
	var old_act: float = s.act
	ob.e5_cast(o, {"kind": "sea", "then": ["immediate"]})
	ok(o.executions.back()[0] == ["immediate"] and is_equal_approx(s.act, old_act), "spawn cast remains immediate with unchanged controller")
	ok(is_equal_approx(v.time(s, o.g.t), 0.5), "immediate spawn cast interrupts spawn at its actual release pose")
	o.sm.list.clear()
