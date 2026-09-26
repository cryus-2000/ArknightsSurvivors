extends Node
## 全局音频（自动加载为 Sfx）：背景音乐 + 音效池。标题界面与游戏共用，切换场景时音乐不中断。

const NAMES := ["heartbeat", "swing", "swing_heavy", "hit", "kill", "tentacle", "hurt", "dodge", "pickup", "oil",
	"levelup", "relic", "skill", "roar", "boom", "ui_move", "ui_ok", "start"]
## 同一音效的最短间隔（秒），避免大量敌人同时被击中时声音糊成一片
const LIMIT := {"hit": 0.035, "kill": 0.045, "pickup": 0.04, "tentacle": 0.07, "swing": 0.05, "dodge": 0.1, "hurt": 0.1}

## 干员专属音效（docs/28，tools/gen_sfx_ops.py 合成）：audio/sfx/op_<干员>_<类别>.wav
## 类别：atk 普攻出手 / hit 命中 / s1 s2 s3 技能发动（character.spend_sp 统一播放）/ big 大招落点 / heal 治疗 / quake 余震
const OP_SFX := {
	"mizuki": ["atk", "hit", "s1", "s2", "s3"],
	"skadi": ["atk", "hit", "s1", "s2", "s3", "big"],
	"siege": ["atk", "hit", "s1", "s2", "s3", "big"],
	"saria": ["atk", "hit", "s1", "s2", "s3"],
	"suzuran": ["atk", "hit", "s1", "s2", "s3"],
	"eyjafjalla": ["atk", "hit", "s1", "s2", "s3", "big"],
	"kaltsit": ["atk", "s1", "s2", "s3", "big", "heal"],
	"wisadel": ["atk", "hit", "s1", "s2", "s3", "quake"],
	# 第二批（docs/28 §第二批）
	"irene": ["atk", "hit", "s1", "s2", "s3", "big"],
	"logos": ["atk", "s1", "s2", "s3", "big"],
	"lumen": ["atk", "hit", "s1", "s2", "s3", "big"],
	"specter_unchained": ["atk", "s1", "s2", "s3"],
	"ulpianus": ["atk", "s1", "s2", "s3", "big"],
}
## 各类别的默认音量（dB）：普攻 / 命中最频繁，压低；技能发动是一局里少数几次的"高光"，放开
const OP_VOL := {"atk": -11.0, "hit": -10.0, "s1": -4.0, "s2": -4.0, "s3": -2.0, "big": -6.0, "heal": -9.0, "quake": -13.0}
## 各类别的最短间隔（秒，按单个干员计）：三四名干员同时开火时不糊成一片
const OP_LIMIT := {"atk": 0.06, "hit": 0.06, "quake": 0.08, "big": 0.1, "heal": 0.3}
## 缺文件时退回的通用音效（新干员还没配音时也有声音）
const OP_FALLBACK := {"atk": "swing", "hit": "hit", "s1": "skill", "s2": "skill", "s3": "skill", "big": "boom", "heal": "oil", "quake": "boom"}

var streams := {}
var players: Array = []
var next := 0
var last := {}
var op_limit := {}         # op_<干员>_<类别> -> 最短间隔（由 OP_LIMIT 展开）
var prng := RandomNumberGenerator.new()   # 音高抖动专用：限流按墙钟时间，不能碰全局随机流（否则 --seed 不可复现）
## 音乐：多曲目 + 战斗曲分层（同长同步的四层，按局势调各层音量）
const MUSIC := {
	"title": ["title"],
	"opening": ["opening"],
	"explore": ["explore_base", "explore_pulse", "explore_drive", "explore_danger"],
	"explore2": ["explore2_base", "explore2_pulse", "explore2_drive", "explore2_danger"],
	"explore3": ["explore3_base", "explore3_pulse", "explore3_drive", "explore3_danger"],
	"boss": ["boss"],
	"final": ["final"],
	"shop": ["shop"],
	"win_loop": ["win_loop"],
	"lose_loop": ["lose_loop"],
}
## 不循环的曲目（播完即停，之后由游戏选下一首）
const ONESHOT := ["opening"]
## 叠加短乐句（Boss 登场/击破），叠在当前音乐之上，不打断曲目
const OVERLAYS := ["boss_in", "boss_down"]
var groups := {}          # 曲目 -> Array[AudioStreamPlayer]
var group_vol := {}       # 曲目 -> 当前音量（0~1）
var cur_track := ""
var layers := [1.0, 0.0, 0.0, 0.0]        # 战斗曲各层目标音量
var layer_vol := [1.0, 0.0, 0.0, 0.0]
var stinger: AudioStreamPlayer
var after_stinger := ""      # 结算短乐句播完后接续的循环曲目
var overlay: AudioStreamPlayer
var overlays := {}
var music: AudioStreamPlayer               # 兼容旧引用：指向当前曲目的第一层
var music_lp: AudioEffectLowPassFilter
var cut_target := 20000.0
var vol_target := -4.0
var music_muted := false


## 自动测试 / 截图 / 平衡批跑（任何 `--xxx` 命令行用户参数）一律静音：开发者在跑测试时还要工作
static func is_automated() -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			return true
	return false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if is_automated():
		AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	var mbus := _ensure_bus("Music")
	if AudioServer.get_bus_effect_count(mbus) == 0:
		music_lp = AudioEffectLowPassFilter.new()
		music_lp.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(mbus, music_lp)
	else:
		music_lp = AudioServer.get_bus_effect(mbus, 0)
	_ensure_bus("SFX")
	_ensure_bus("Voice")
	voice_player = AudioStreamPlayer.new()
	voice_player.bus = "Voice"
	add_child(voice_player)
	var cfg: Node = get_node_or_null("/root/Cfg")
	if cfg != null and "voice" in cfg:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Voice"), linear_to_db(maxf(float(cfg.voice), 0.0001)))
	for n in NAMES:
		streams[n] = _load_wav("res://audio/sfx/%s.wav" % n)
	for oid in OP_SFX:
		for kind in OP_SFX[oid]:
			var sn := "op_%s_%s" % [oid, kind]
			streams[sn] = _load_wav("res://audio/sfx/%s.wav" % sn)
			if OP_LIMIT.has(kind):
				op_limit[sn] = OP_LIMIT[kind]
	for i in 32:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		players.append(p)
	for tname in MUSIC:
		var arr: Array = []
		for f in MUSIC[tname]:
			var st: AudioStreamOggVorbis = _load_ogg("res://audio/music/%s.ogg" % f)
			if st == null:
				continue
			st.loop = not ONESHOT.has(tname)
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
	overlay = AudioStreamPlayer.new()
	overlay.bus = "Music"
	add_child(overlay)
	for o in OVERLAYS:
		var ost: AudioStreamOggVorbis = _load_ogg("res://audio/music/%s.ogg" % o)
		if ost != null:
			ost.loop = false
			overlays[o] = ost
	play_music("title")


## 加载音频：优先用编辑器导入好的资源；直接用源码运行而没有导入记录时（.godot/imported 缺失），
## 退回到从原始文件解码，这样不打开编辑器也有声音
func _load_ogg(path: String) -> AudioStreamOggVorbis:
	if ResourceLoader.exists(path):
		var r = load(path)
		if r is AudioStreamOggVorbis:
			return r
	if FileAccess.file_exists(path):
		return AudioStreamOggVorbis.load_from_file(path)
	return null


func _load_wav(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		var r = load(path)
		if r is AudioStream:
			return r
	if FileAccess.file_exists(path):
		return AudioStreamWAV.load_from_file(path)
	return null


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
	if tname == cur_track or not groups.has(tname) or groups[tname].is_empty():
		return
	cur_track = tname
	after_stinger = ""
	stinger.stop()
	for pl in groups[tname]:
		pl.play(0.0)
	music = groups[tname][0]


## 结算短乐句：当前曲目淡出
func play_stinger(sname: String) -> void:
	var st: AudioStreamOggVorbis = _load_ogg("res://audio/music/%s.ogg" % sname)
	if st == null:
		return
	st.loop = false
	cur_track = ""
	after_stinger = sname + "_loop" if groups.has(sname + "_loop") else ""
	stinger.stream = st
	stinger.volume_db = vol_target
	stinger.play()


## 叠加短乐句：不改变当前曲目，直接叠在音乐之上（Boss 登场 / 击破）
func play_overlay(oname: String, gain_db := 2.0) -> void:
	if not overlays.has(oname):
		return
	overlay.stream = overlays[oname]
	overlay.volume_db = vol_target + gain_db
	overlay.play()


## 某曲目是否正是当前曲目且仍在播放（用于等待不循环曲目播完）
func track_playing(tname: String) -> bool:
	if cur_track != tname or not groups.has(tname) or groups[tname].is_empty():
		return false
	return (groups[tname][0] as AudioStreamPlayer).playing


## 当前曲目是否为战斗曲（三段之一）
func is_explore(tname: String) -> bool:
	return tname.begins_with("explore")


## 战斗曲分层：base / pulse / drive / danger 的目标音量（0~1）
func set_layers(l: Array) -> void:
	driven_t = 0.0
	layers = l


var driven_t := 0.0      # 距离游戏上一次主动选曲的时间


# ---------------------------------------------------------------- 干员语音（Codex 交付 game/audio/voice，README 事件映射）
## 用户定（2026-09-26 第二版）：语音要全（不再按时长筛掉），但**绝不打断正在播的语音**、整体频率要低。
## 规则：同一时刻只有一条，占线时新语音直接放弃（部署语音排队）；两条之间至少隔 VOICE_GAP 秒；
## 每名干员自己的任意语音之间至少隔 VOICE_OP_GAP 秒；同一句另有冷却（一技能最长，因为它放得最频繁）。缺文件静默跳过。
const VOICE_MAX_LEN := 8.0             # 只防意外的超长文件；Codex 交付最长 6.4 秒，全部可用
const VOICE_GAP := 3.0                 # 两条语音之间至少间隔（全队）
const VOICE_OP_GAP := 15.0             # 同一名干员两条语音之间至少间隔
const VOICE_CD := {"entry": 0.0, "skill_1": 45.0, "skill_2": 30.0, "skill_3": 20.0, "battle": 60.0, "w_laugh": 75.0}
const VOICE_PRIO := {"skill_3": 4, "skill_2": 3, "skill_1": 3, "entry": 2, "battle": 1, "w_laugh": 1}
## 响度归一（Codex 交付的各段 RMS 相差约 7 dB）：按各干员实测平均 RMS 拉到 -17 dB 附近（2026-09-26 测量）
const VOICE_TRIM := {"eyjafjalla": -4.0, "saria": 1.0, "wisadel": 1.0, "logos": 0.5}
var voice_player: AudioStreamPlayer
var voice_streams := {}                # 路径 -> AudioStream（null = 缺文件或超长）
var voice_last := {}                   # "cid:key" -> 上次播放时间
var voice_op_last := {}                # cid -> 该干员上次开口时间
var voice_prio := 0
var voice_end := 0.0
var voice_queue: Array = []            # [cid, key]


func _voice_stream(cid: String, key: String) -> AudioStream:
	var path := "res://audio/voice/%s_%s.wav" % [cid, key]
	if not voice_streams.has(path):
		var st: AudioStream = _load_wav(path)
		if st != null and st.get_length() > VOICE_MAX_LEN:
			st = null
		voice_streams[path] = st
	return voice_streams[path]


## 播一条干员语音；queue = true 时占线则排队（部署语音用），否则直接放弃
func voice(cid: String, key: String, queue := false) -> void:
	var st := _voice_stream(cid, key)
	if st == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var lk := cid + ":" + key
	if now - float(voice_last.get(lk, -999.0)) < float(VOICE_CD.get(key, 8.0)):
		return
	if key != "entry" and now - float(voice_op_last.get(cid, -999.0)) < VOICE_OP_GAP:
		return
	var prio: int = VOICE_PRIO.get(key, 1)
	# 占线：一律不打断（用户要求）；部署语音排队，其余放弃
	var busy: bool = voice_player.playing or now < voice_end
	if busy:
		if queue and voice_queue.size() < 4:
			voice_queue.append([cid, key])
		return
	voice_last[lk] = now
	voice_op_last[cid] = now
	voice_prio = prio
	voice_player.stream = st
	voice_player.volume_db = float(VOICE_TRIM.get(cid, 0.0))
	voice_player.play()
	voice_end = now + st.get_length() + VOICE_GAP


func _voice_tick() -> void:
	if voice_queue.is_empty() or voice_player.playing:
		return
	if Time.get_ticks_msec() / 1000.0 < voice_end:
		return
	var q: Array = voice_queue.pop_front()
	voice_prio = 0
	voice(q[0], q[1], false)


## 场景切换 / 回标题时清空（避免上一局的部署语音串到下一局）
func voice_reset() -> void:
	voice_queue.clear()
	voice_player.stop()
	voice_prio = 0


func _process(delta: float) -> void:
	_voice_tick()
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
			var lv: float = layer_vol[i] if is_explore(tname) else 1.0
			var v := gv * lv
			pl.volume_db = linear_to_db(maxf(v, 0.0001)) + vol_target
			if gv <= 0.0 and pl.playing:
				pl.stop()
	if stinger.playing:
		stinger.volume_db = vol_target + 4.0
	elif after_stinger != "":
		# 结算短乐句播完：接续对应的循环（胜利变奏 / 沉底氛围）
		var nxt := after_stinger
		after_stinger = ""
		play_music(nxt)


func toggle_music() -> bool:
	music_muted = not music_muted
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), music_muted)
	return music_muted


func play(name: String, vol := 0.0, pitch := 1.0, pitch_var := 0.08) -> void:
	if not streams.has(name):
		return
	var now := Time.get_ticks_msec() / 1000.0
	var lim: float = LIMIT.get(name, op_limit.get(name, 0.0))
	if lim > 0.0 and now - float(last.get(name, -1.0)) < lim:
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
	if streams[name] == null:
		return
	p.stream = streams[name]
	p.volume_db = vol
	p.pitch_scale = pitch * prng.randf_range(1.0 - pitch_var, 1.0 + pitch_var)
	p.play()


## 干员音效：op("skadi", "atk")；vol 为相对该类别默认音量的偏移。没有专属文件时退回通用音效
func op(oid: String, kind: String, vol := 0.0, pitch := 1.0, pitch_var := 0.05) -> void:
	var sn := "op_%s_%s" % [oid, kind]
	var v: float = float(OP_VOL.get(kind, -8.0)) + vol
	if streams.get(sn) != null:
		play(sn, v, pitch, pitch_var)
	elif OP_FALLBACK.has(kind):
		play(OP_FALLBACK[kind], v, pitch, pitch_var)
