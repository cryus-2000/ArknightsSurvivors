extends Node
## 全局音频（自动加载为 Sfx）：背景音乐 + 音效池。标题界面与游戏共用，切换场景时音乐不中断。

const NAMES := ["heartbeat", "swing", "swing_heavy", "hit", "kill", "tentacle", "hurt", "dodge", "pickup", "oil",
	"levelup", "relic", "skill", "roar", "boom", "ui_move", "ui_ok", "start"]
## 同一音效的最短间隔（秒），避免大量敌人同时被击中时声音糊成一片
const LIMIT := {"hit": 0.035, "kill": 0.045, "pickup": 0.04, "tentacle": 0.07, "swing": 0.05, "dodge": 0.1, "hurt": 0.1}

var streams := {}
var players: Array = []
var next := 0
var last := {}
var music: AudioStreamPlayer
var music_lp: AudioEffectLowPassFilter
var cut_target := 20000.0
var vol_target := -4.0
var music_muted := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var mbus := _ensure_bus("Music")
	if AudioServer.get_bus_effect_count(mbus) == 0:
		music_lp = AudioEffectLowPassFilter.new()
		music_lp.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(mbus, music_lp)
	else:
		music_lp = AudioServer.get_bus_effect(mbus, 0)
	_ensure_bus("SFX")
	for n in NAMES:
		streams[n] = load("res://audio/sfx/%s.wav" % n)
	for i in 24:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		players.append(p)
	var stream: AudioStreamOggVorbis = load("res://audio/bgm_tide_lamp.ogg")
	stream.loop = true
	music = AudioStreamPlayer.new()
	music.stream = stream
	music.bus = "Music"
	music.volume_db = -30.0
	add_child(music)
	music.play()


func _ensure_bus(name: String) -> int:
	var b := AudioServer.get_bus_index(name)
	if b == -1:
		AudioServer.add_bus()
		b = AudioServer.bus_count - 1
		AudioServer.set_bus_name(b, name)
		AudioServer.set_bus_send(b, "Master")
	return b


func _process(delta: float) -> void:
	music_lp.cutoff_hz = lerp(music_lp.cutoff_hz, cut_target, clamp(delta * 3.0, 0.0, 1.0))
	music.volume_db = lerp(music.volume_db, vol_target, clamp(delta * 1.5, 0.0, 1.0))


func toggle_music() -> bool:
	music_muted = not music_muted
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), music_muted)
	return music_muted


func play(name: String, vol := 0.0, pitch := 1.0, pitch_var := 0.08) -> void:
	if not streams.has(name):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if LIMIT.has(name) and now - float(last.get(name, -1.0)) < LIMIT[name]:
		return
	last[name] = now
	var p: AudioStreamPlayer = null
	for i in players.size():
		var c: AudioStreamPlayer = players[(next + i) % players.size()]
		if not c.playing:
			p = c
			next = (next + i + 1) % players.size()
			break
	if p == null:
		p = players[next]
		next = (next + 1) % players.size()
	p.stream = streams[name]
	p.volume_db = vol
	p.pitch_scale = pitch * randf_range(1.0 - pitch_var, 1.0 + pitch_var)
	p.play()
