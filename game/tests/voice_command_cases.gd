extends RefCounted

const Squad = preload("res://scripts/characters/squad.gd")
const Character = preload("res://scripts/characters/character.gd")

class VoiceSpy extends Node:
	var calls: Array = []
	var urgents: Array = []
	func voice(cid: String, key: String, queued := false, urgent := false) -> void:
		calls.append([cid, key, queued])
		urgents.append(urgent)   # 指挥回应一律 urgent（10-23）

class VoiceGame extends RefCounted:
	var sfx: Node
	var panel_ui = null
	var t := 100.0
	var demo_op := ""
	var trace_every := 0.0
	var ppos := Vector2.ZERO
	var in_tree := true
	var entry_voice_hold := false
	var rng := RandomNumberGenerator.new()
	var vrng := RandomNumberGenerator.new()
	var stats = preload("res://scripts/core/stat_block.gd").new()
	var hit_src := {}
	func get_node_or_null(_path: String):
		return sfx
	func is_inside_tree() -> bool:
		return in_tree

func run(check: Callable) -> void:
	var game := VoiceGame.new()
	var spy := VoiceSpy.new()
	game.sfx = spy
	game.rng.seed = 123
	var before := game.rng.state
	var squad := Squad.new(game)
	var leader := Character.new(game, {"id": "skadi"})
	leader.is_leader = true
	var medic := Character.new(game, {"id": "lumen", "command": {"roam": false}})
	var fighter := Character.new(game, {"id": "texas"})
	var down := Character.new(game, {"id": "hoshiguma"})
	down.cmd_down = 5.0
	squad.ops = [medic, fighter, leader, down]
	squad.set_stance(Squad.ROAM)
	check.call(spy.calls == [["texas", "command", false]], "assault requests the sortieing teammate's own command voice, not the leader's")
	var called := spy.calls.size()
	squad.set_stance(Squad.ROAM)
	check.call(spy.calls.size() == called, "same stance does not request another voice")
	game.t += 7.0
	squad.set_stance(Squad.RECALL)
	check.call(spy.calls.size() == 2 and spy.calls[-1] == ["texas", "entry", false], "recall retains entry; non-roaming and downed followers do not speak")
	game.t += 1.0
	squad.set_stance(Squad.ROAM)
	check.call(spy.calls.size() == 2, "rapid command change is throttled")
	game.t += 7.0
	squad._stance_voice(Squad.ROAM)
	check.call(spy.calls[-1] == ["texas", "command", false], "assault rotation stays on the sortieing teammates")
	squad.set_stance(Squad.GUARD)
	squad.stamina = 0.0
	squad.exhausted = true
	called = spy.calls.size()
	game.t += 20.0
	check.call(not squad.cycle_stance() and spy.calls.size() == called, "rejected assault has no voice")
	game.demo_op = "skadi"
	squad._stance_voice(Squad.ROAM)
	check.call(spy.calls.size() == called, "gallery demo suppresses command voices")
	game.demo_op = ""
	medic.is_leader = true
	leader.is_leader = false
	squad.ops = [medic]
	squad._vo_i = 0
	squad._stance_voice(Squad.ROAM)
	check.call(spy.calls[-1] == ["lumen", "command", false], "non-roaming operator may speak when leading")
	check.call(game.rng.state == before, "voice selection consumes no gameplay RNG")

	spy.calls.clear()
	var entrant := Character.new(game, {"id": "gladiia"})
	check.call(entrant.has_method("entry_started"), "character exposes entry-start hook")
	if entrant.has_method("entry_started"):
		entrant.entry_started()
		entrant.entry_started()
		check.call(spy.calls == [["gladiia", "entry", true]], "entry-start requests queued entry only once")
	var demo := Character.new(game, {"id": "lappland"})
	if demo.has_method("entry_started"):
		spy.calls.clear()
		game.demo_op = "lappland"
		demo.entry_started()
		check.call(spy.calls.is_empty(), "gallery demo suppresses entry hook")
		game.demo_op = ""
		game.in_tree = false
		demo.entry_started()
		check.call(spy.calls.is_empty(), "detached character does not request entry")
		game.in_tree = true
		demo.entry_started()
		check.call(spy.calls == [["lappland", "entry", true]], "suppressed entry does not consume the once-only hook")
	spy.calls.clear()
	var joined = Squad.new(game).add("gladiia", false)
	check.call(joined != null and spy.calls == [["gladiia", "entry", true]], "Squad.add immediate entry fallback is wired")
	if joined != null and joined.has_method("entry_started"):
		joined.entry_started()
		check.call(spy.calls.size() == 1, "later entry-start notification does not repeat join voice")
	# 开局编队：建局时（画面还没出来）不播登场语音，game.release_entry_voices 放开后才播（用户 10-25）
	spy.calls.clear()
	game.entry_voice_hold = true
	var held = Squad.new(game).add("texas", false)
	check.call(held != null and spy.calls.is_empty(), "opening squad entry voice waits while held")
	game.entry_voice_hold = false
	if held != null:
		held.entry_started()
		check.call(spy.calls == [["texas", "entry", true]], "held entry voice plays once released")
	spy.free()
	_asset_coverage(check)
	_channel_rules(check)

func _asset_coverage(check: Callable) -> void:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://audio/voice/voice_manifest.json"))
	check.call(manifest is Dictionary and manifest.get("clips", []).size() == 121, "runtime manifest retains91 old clips and adds30")
	if not manifest is Dictionary:
		return
	var have := {}
	for clip in manifest.clips:
		have[clip.operator + ":" + clip.event] = true
	check.call(have.size() == 121, "runtime event pairs are unique")
	var ids := Character.list_ids()
	check.call(manifest.operators.size() == 20 and ids.size() == 20, "runtime voice map covers20 operators")
	for cid in ids:
		check.call(have.has(cid + ":command"), "approved command registered: " + cid)
		var stream = load("res://audio/voice/%s_command.ogg" % cid) if have.has(cid + ":command") else null
		check.call(stream is AudioStreamOggVorbis and stream.get_length() <= 8.0, "command OGG loads within voice limit: " + cid)
	for cid in ["lappland", "gladiia"]:
		for event in ["entry", "skill_1", "skill_2", "skill_3", "battle"]:
			check.call(have.has(cid + ":" + event), "new operator event registered: " + cid + ":" + event)

func _channel_rules(check: Callable) -> void:
	var sfx = load("res://scripts/sfx.gd").new()
	sfx.voice_player = AudioStreamPlayer.new()
	sfx.voice_fader = AudioStreamPlayer.new()
	var clip = sfx._voice_stream("skadi", "command")
	check.call(clip != null, "real channel can load command voice")
	if clip != null:
		sfx.voice_now = 1000.0
		sfx.voice("skadi", "command")
		check.call(sfx.voice_cid == "skadi" and sfx.voice_key == "command", "real channel starts command")
		sfx.voice_now = 1000.1
		sfx.voice("texas", "command")
		check.call(sfx.voice_cid == "skadi" and sfx.voice_queue.is_empty(), "busy command is dropped without queueing")
		sfx.voice("texas", "skill_1")
		check.call(sfx.voice_cid == "skadi", "skill does not add a new interruption exception for command")
		sfx.voice_now = 1000.0 + clip.get_length() + 2.0
		sfx.voice("texas", "command")
		check.call(sfx.voice_cid == "skadi", "command observes existing team gap")
		sfx.voice_now = 1000.0 + clip.get_length() + 3.01
		sfx.voice("texas", "command")
		check.call(sfx.voice_cid == "texas", "different operator may respond after team gap")
		sfx.voice_now = 1014.0
		sfx.voice("skadi", "command")
		check.call(sfx.voice_cid == "texas", "command observes existing15-second operator gap")
		sfx.voice_now = 1015.01
		sfx.voice("skadi", "command")
		check.call(sfx.voice_cid == "skadi", "command may resume when operator gap expires")
	sfx.voice_player.free()
	sfx.voice_fader.free()
	sfx.free()
