extends Node
## Shared beam salvos keep one warning and one impact voice, independently.
var failures := 0


func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		print("FAIL: " + label)


func voices(name: String) -> int:
	return Sfx.players.filter(func(p): return p.playing and p.get_meta("sname", "") == name).size()


func _ready() -> void:
	run.call_deferred()


func run() -> void:
	AudioServer.set_bus_mute(0, true)
	for p in Sfx.players:
		p.stop()
	Sfx.last.clear()
	Sfx.play_cue("beam", "paranoia", "start")
	await get_tree().create_timer(0.08).timeout
	Sfx.play_cue("光束", "ishar", "start")
	check(voices("cue_beam_start") == 1, "salvo warning does not stack")
	Sfx.play_cue("beam", "paranoia", "hit")
	await get_tree().create_timer(0.08).timeout
	Sfx.play_cue("beam", "ishar", "hit")
	check(voices("cue_beam_hit") == 1, "salvo impact does not stack")
	check(voices("cue_beam_start") == 1, "impact does not cut warning")
	check(Sfx.sfx_prio("cue_beam_start") == 5 and Sfx.sfx_prio("cue_beam_hit") == 5, "beam cues retain Boss priority")
	await get_tree().create_timer(1.0).timeout
	Sfx.play_cue("beam", "paranoia", "start")
	Sfx.play_cue("beam", "paranoia", "hit")
	check(voices("cue_beam_start") == 1 and voices("cue_beam_hit") == 1, "next attack remains audible")
	for p in Sfx.find_children("*", "AudioStreamPlayer", true, false):
		p.stop()
	await get_tree().create_timer(0.1).timeout
	print("BEAM AUDIO: %d failures" % failures)
	get_tree().quit(1 if failures else 0)
