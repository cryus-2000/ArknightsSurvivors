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
## 音乐：多曲目 + 战斗曲分层（同长同步的四层，按局势调各层音量）
const MUSIC := {
	"title": ["title"],
	"explore": ["explore_base", "explore_pulse", "explore_drive", "explore_danger"],
	"boss": ["boss"],
	"final": ["final"],
	"shop": ["shop"],
}
var groups := {}          # 曲目 -> Array[AudioStreamPlayer]
var group_vol := {}       # 曲目 -> 当前音量（0~1）
var cur_track := ""
var layers := [1.0, 0.0, 0.0, 0.0]        # 战斗曲各层目标音量
var layer_vol := [1.0, 0.0, 0.0, 0.0]
var stinger: AudioStreamPlayer
var music: AudioStreamPlayer               # 兼容旧引用：指向当前曲目的第一层
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
	for tname in MUSIC:
		var arr: Array = []
		for f in MUSIC[tname]:
			var st: AudioStreamOggVorbis = load("res://audio/music/%s.ogg" % f)
			st.loop = true
			var pl := AudioStreamPlayer.new()
			pl.stream = st
			pl.bus = "Music"
			pl.volume_db = -80.0
			add_child(pl)
			arr.append(pl)
		groups[tname] = arr
		group_vol[tname] = 0.0
	stinger = AudioStreamPlayer.new()
	stinger.bus = "Music"
	add_child(stinger)
	play_music("title")


func _ensure_bus(name: String) -> int:
	var b := AudioServer.get_bus_index(name)
	if b == -1:
		AudioServer.add_bus()
		b = AudioServer.bus_count - 1
		AudioServer.set_bus_name(b, name)
		AudioServer.set_bus_send(b, "Master")
	return b


## 切换曲目：新曲从头淡入，旧曲淡出后停止；同一曲目重复调用不会重新开始
func play_music(tname: String) -> void:
	if tname != "title":
		driven_t = 0.0
	if tname == cur_track or not groups.has(tname):
		return
	cur_track = tname
	stinger.stop()
	for pl in groups[tname]:
		pl.play(0.0)
	music = groups[tname][0]


## 结算短乐句：当前曲目淡出
func play_stinger(sname: String) -> void:
	var st: AudioStreamOggVorbis = load("res://audio/music/%s.ogg" % sname)
	if st == null:
		return
	st.loop = false
	cur_track = ""
	stinger.stream = st
	stinger.volume_db = vol_target
	stinger.play()


## 战斗曲分层：base / pulse / drive / danger 的目标音量（0~1）
func set_layers(l: Array) -> void:
	driven_t = 0.0
	layers = l


var driven_t := 0.0      # 距离游戏上一次主动选曲的时间


func _process(delta: float) -> void:
	music_lp.cutoff_hz = lerp(music_lp.cutoff_hz, cut_target, clamp(delta * 3.0, 0.0, 1.0))
	# 兜底：若游戏场景没有主动选曲（未接入分层逻辑的版本），进入战斗时自动播放战斗曲
	driven_t += delta
	var sc := get_tree().current_scene
	if driven_t > 1.0 and sc != null and sc.get_script() != null and str(sc.get_script().resource_path).ends_with("game.gd") and cur_track == "title":
		play_music("explore")
		layers = [1.0, 1.0, 0.0, 0.0]
	for i in 4:
		# 加层快、减层慢，避免战斗中音乐忽大忽小
		var sp: float = 2.5 if layers[i] > layer_vol[i] else 0.5
		layer_vol[i] = move_toward(layer_vol[i], layers[i], delta * sp)
	for tname in groups:
		var want := 1.0 if tname == cur_track else 0.0
		var gv: float = move_toward(group_vol[tname], want, delta * (0.8 if want > 0.0 else 0.6))
		group_vol[tname] = gv
		var arr: Array = groups[tname]
		for i in arr.size():
			var pl: AudioStreamPlayer = arr[i]
			var lv: float = layer_vol[i] if tname == "explore" else 1.0
			var v := gv * lv
			pl.volume_db = linear_to_db(maxf(v, 0.0001)) + vol_target
			if gv <= 0.0 and pl.playing:
				pl.stop()
	if stinger.playing:
		stinger.volume_db = vol_target + 4.0


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
