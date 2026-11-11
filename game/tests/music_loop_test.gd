extends Node
## 配乐循环验收（11-12 用户「一般肉鸽大部分时候的配乐是循环的，我们现在满足吗」）：每首会循环的曲子走 Sfx.play_music 的真实路径开播，
## 把各层一起 seek 到「曲尾前 PRE 秒」，看播放位置回绕（回到 0，商人曲回到前奏后的 SHOP_LOOP）、播放器一直在播、各层回绕后仍对齐；
## 连做两次 = 每首至少循环两次。Music 总线挂 AudioEffectCapture，把第一次回环前后各约 2 秒的实际混音写成 wav（build/music_loop/），
## 由 tools/music_loop_check.py 对照原曲算回环处有没有空档 / 跳接。开场引子《沉降》不循环：确认播完自己停。
## 另测商人来回：战斗曲放到中段进商店、出来后应接着放（不从头）。
## 跑法：godot --headless --audio-driver Dummy --path game res://tests/music_loop_test.tscn [-- --mloop=<曲名,…>] [--mloop_real=shop]
##   --mloop_real=<曲名>：不 seek，按真实时间放满两轮（商人曲正文约 78 秒 × 2）
const PRE := 2.0
const POST := 2.0
var OUT := ""
var S: Node
var cap: AudioEffectCapture
var queue: Array = []
var cur := ""
var phase := ""
var t_phase := 0.0
var wraps := 0
var last_pos: Array = []
var rec := PackedVector2Array()
var recording := false
var results := {}
var real := ""
var fails: Array = []
var stopped_any := false
var max_skew := 0.0
var wrap_to: Array = []


func _ready() -> void:
	AudioServer.set_bus_mute(0, true)
	S = get_node("/root/Sfx")
	S.set_battle(2, true)        # 各层全开（最响、层最多的情况；录音与原曲全部层之和对照）
	S.set_final_phase(true)
	var mb := AudioServer.get_bus_index("Music")
	cap = AudioEffectCapture.new()
	cap.buffer_length = 10.0
	AudioServer.add_bus_effect(mb, cap)
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mloop="):
			only = a.substr(8)
		if a.begins_with("--mloop_real="):
			real = a.substr(13)
	OUT = ProjectSettings.globalize_path("res://").path_join("../build/music_loop").simplify_path()
	DirAccess.make_dir_recursive_absolute(OUT)
	var all: Array = ["title", "archive", "deploy", "shop"]
	for tn in S.SUNO_TRACKS:
		if S.lay.has(tn):
			all.append(tn)
	if real != "":
		all = [real]
	elif only != "":
		all = Array(only.split(","))
	queue = all.duplicate()
	if real == "" and only == "":
		queue.append("@opening")
		queue.append("@shop_resume")
	await get_tree().process_frame   # Sfx._mobile_audio 延后一帧开标题曲：等它开完再选曲，免得第一首被标题曲顶掉
	await get_tree().process_frame
	_next()


func _players(tn: String) -> Array:
	return S.lay[tn].players if S.lay.has(tn) else S.groups.get(tn, [])


func _len(tn: String) -> float:
	var pl: AudioStreamPlayer = _players(tn)[0]
	return pl.stream.get_length()


func _loop_start(tn: String) -> float:
	var st = _players(tn)[0].stream
	return float(st.loop_offset) if st is AudioStreamOggVorbis else 0.0


func _next() -> void:
	if queue.is_empty():
		_finish()
		return
	cur = queue.pop_front()
	wraps = 0
	stopped_any = false
	max_skew = 0.0
	wrap_to = []
	t_phase = 0.0
	if cur == "@opening":
		S.play_music("opening")
		phase = "opening"
		return
	if cur == "@shop_resume":
		S.play_music("battle1")
		phase = "sr_play"
		return
	S.play_music(cur)
	phase = "fadein"


func _seek_end() -> void:
	var ln := _len(cur)
	for pl in _players(cur):
		(pl as AudioStreamPlayer).seek(ln - PRE)
	S.track_t0[cur] = S._now() - (ln - PRE)
	last_pos = []
	for pl in _players(cur):
		last_pos.append(ln - PRE)


func _process(delta: float) -> void:
	t_phase += delta
	match phase:
		"fadein":
			if t_phase > 1.5:
				if real != "":
					phase = "real"
					last_pos = []
					for pl in _players(cur):
						last_pos.append((pl as AudioStreamPlayer).get_playback_position())
				else:
					_seek_end()
					cap.clear_buffer()
					rec = PackedVector2Array()
					recording = wraps == 0
					phase = "watch"
				t_phase = 0.0
		"watch", "real":
			_watch()
			if recording:
				var n := cap.get_frames_available()
				if n > 0:
					rec.append_array(cap.get_buffer(n))
			if phase == "watch" and t_phase > PRE + POST:
				if recording:
					recording = false
					_save_wav(cur, rec)
				if wraps >= 2 or t_phase > PRE + POST + 3.0:
					_report()
					_next()
				else:
					_seek_end()
					t_phase = 0.0
			if phase == "real" and int(t_phase / 5.0) != int((t_phase - delta) / 5.0):
				var p0: AudioStreamPlayer = _players(cur)[0]
				print("MLOOP real t=%.0f pos=%.2f playing=%s wraps=%d" % [t_phase, p0.get_playback_position(), str(p0.playing), wraps])
			elif phase == "real" and (wraps >= 2 or t_phase > 2.0 * _len(cur) + 10.0):
				_report()
				_next()
		"opening":
			var pl: AudioStreamPlayer = _players("opening")[0]
			if t_phase > 0.5 and not pl.playing:
				results["opening"] = {"loops": false, "ended_at": snappedf(t_phase, 0.01), "len": snappedf(_len("opening"), 0.01), "ok": true}
				print("MLOOP opening oneshot ended after %.2f s (len %.2f)" % [t_phase, _len("opening")])
				_next()
			elif t_phase > _len("opening") + 5.0:
				fails.append("opening 没停")
				_next()
		"sr_play":
			if t_phase > 1.5:
				var mid := 60.0
				for pl in _players("battle1"):
					(pl as AudioStreamPlayer).seek(mid)
				S.track_t0["battle1"] = S._now() - mid
				phase = "sr_battle"
				t_phase = 0.0
		"sr_battle":
			if t_phase > 3.0:
				results["shop_resume"] = {"before_shop": snappedf(_players("battle1")[0].get_playback_position(), 0.01)}
				S.play_music("shop")
				phase = "sr_shop"
				t_phase = 0.0
		"sr_shop":
			S.play_music("shop")
			if t_phase > 8.0:
				S.play_music("battle1")
				phase = "sr_back"
				t_phase = 0.0
		"sr_back":
			S.play_music("battle1")
			if t_phase > 1.0:
				var p: float = _players("battle1")[0].get_playback_position()
				var r: Dictionary = results["shop_resume"]
				r["after_shop"] = snappedf(p, 0.01)
				r["resumed"] = p > float(r.before_shop) - 0.5
				var lp: Array = []
				for pl in _players("battle1"):
					lp.append(snappedf((pl as AudioStreamPlayer).get_playback_position(), 0.01))
				r["layers"] = lp
				print("MLOOP shop_resume battle1 before=%.2f after=%.2f resumed=%s layers=%s" % [r.before_shop, p, str(r.resumed), str(lp)])
				if not r.resumed:
					fails.append("商人出来后战斗曲从头放")
				_next()


func _watch() -> void:
	var pls := _players(cur)
	var ps: Array = []
	for i in pls.size():
		var pl: AudioStreamPlayer = pls[i]
		if not pl.playing:
			stopped_any = true
		ps.append(pl.get_playback_position())
	if ps.size() > 1:
		max_skew = maxf(max_skew, float(ps.max()) - float(ps.min()))
	if last_pos.size() == ps.size() and float(ps[0]) < float(last_pos[0]) - 1.0:
		wraps += 1
		wrap_to.append(snappedf(float(ps[0]), 0.01))
	last_pos = ps


func _report() -> void:
	var ls := _loop_start(cur)
	var ok := wraps >= 2 and not stopped_any and max_skew < 0.05
	for w in wrap_to:
		if absf(float(w) - ls) > 0.6:
			ok = false
	results[cur] = {"len": snappedf(_len(cur), 0.001), "loop_start": snappedf(ls, 0.001), "wraps": wraps, "wrap_to": wrap_to, "stopped": stopped_any,
		"layers": _players(cur).size(), "layer_skew": snappedf(max_skew, 0.001), "ok": ok, "real": real != ""}
	print("MLOOP %s len=%.2f loop_start=%.2f wraps=%d wrap_to=%s stopped=%s layers=%d skew=%.3f ok=%s" % [cur, _len(cur), ls, wraps, str(wrap_to), str(stopped_any), _players(cur).size(), max_skew, str(ok)])
	if not ok:
		fails.append(cur)


func _save_wav(tn: String, buf: PackedVector2Array) -> void:
	var sr := int(AudioServer.get_mix_rate())
	var data := PackedByteArray()
	data.resize(buf.size() * 4)
	for i in buf.size():
		data.encode_s16(i * 4, int(clampf(buf[i].x, -1.0, 1.0) * 32767.0))
		data.encode_s16(i * 4 + 2, int(clampf(buf[i].y, -1.0, 1.0) * 32767.0))
	var f := FileAccess.open(OUT.path_join("cap_%s.wav" % tn), FileAccess.WRITE)
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + data.size())
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)
	f.store_16(2)
	f.store_32(sr)
	f.store_32(sr * 4)
	f.store_16(4)
	f.store_16(16)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(data.size())
	f.store_buffer(data)
	f.close()


func _finish() -> void:
	var f := FileAccess.open(OUT.path_join("result%s.json" % ("_real_" + real if real != "" else "")), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, " "))
	f.close()
	print("MLOOP done fails=%s" % str(fails))
	get_tree().quit(1 if not fails.is_empty() else 0)
