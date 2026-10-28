extends Node
## Export with Sfx + this scene and tools/web/engine_patch.py; run silently in a browser.
## Exercises real registration / playback / pause / release / re-registration, not estimates.
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: " + label)

func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func _ready() -> void:
	AudioServer.set_bus_mute(0, true)
	run.call_deferred()

func run() -> void:
	check(OS.has_feature("web"), "web sample driver required")
	for tn in {"battle1": 3, "battle2": 3, "battle3": 3, "boss": 1, "final": 2, "final_knight": 2, "final_ishar": 2, "final_izumik": 2}:
		var count := 3 if tn.begins_with("battle") else (2 if tn.begins_with("final") else 1)
		check(Sfx.lay.has(tn) and Sfx._track_streams(tn).size() == count, tn + " full layers")
	if failures:
		finish()
		return
	# 与真实 title.gd 一致：先浏览标题 / 选人菜单，出发时才开始预热。
	Sfx.play_music("title")
	await wait(0.2)
	Sfx.play_music("deploy")
	Sfx.warm_begin()
	while Sfx.warm_busy():
		Sfx.warm_step(1000)
		await get_tree().process_frame
	for st in Sfx._track_streams("battle1"):
		check(AudioServer.is_stream_registered_as_sample(st), "first battle prewarmed")
	Sfx.play_music("opening")
	await wait(5.0)
	for st in Sfx._track_streams("battle1"):
		check(AudioServer.is_stream_registered_as_sample(st), "intro preserves prewarm")
	for tn in ["battle1", "battle2", "battle3", "boss", "final", "final_knight", "final_ishar", "final_izumik", "shop", "title", "archive", "deploy", "title", "battle1", "shop"]:
		Sfx.set_battle(2, false)
		Sfx.play_music(tn)
		await wait(8.0)   # pending bar + fade + 3 s grace
		check(Sfx.cur_track == tn, tn + " actually selected")
		for st in Sfx._track_streams(tn):
			check(AudioServer.is_stream_registered_as_sample(st), tn + " sample registered")
		for old in Sfx.lay.keys() + Sfx.groups.keys():
			if old == tn:
				continue
			for st in Sfx._track_streams(old):
				check(not AudioServer.is_stream_registered_as_sample(st), old + " released after " + tn)
		var mb: float = Sfx.sample_mem_mb()
		print("BGM MEMORY track=%s mb=%.3f" % [tn, mb])
		if tn == "battle1":
			var pl: AudioStreamPlayer = Sfx.lay[tn].players[0]
			pl.stream_paused = true
			await wait(0.2)
			check(not bool(JavaScriptBridge.eval("window.__syAudioFree('%d')" % pl.stream.get_instance_id(), true)), "paused sample protected")
			pl.stream_paused = false
			await wait(0.3)
			check(pl.playing and absf(Sfx.sample_mem_mb() - mb) < 0.1, "resume does not copy PCM")
		if tn.begins_with("final"):
			Sfx.set_final_phase(true)
			await wait(2.2)
			check(Sfx.stem_on[tn] == [1.0, 1.0], "final second layer retained")
			Sfx.set_final_phase(false)
	finish()

func finish() -> void:
	print("BGM MEMORY: %d failures" % failures)
	JavaScriptBridge.eval("window.__bgmTestDone=%d" % failures, true)
