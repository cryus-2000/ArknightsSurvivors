extends Node
## 全局音频（自动加载为 Sfx）：背景音乐 + 音效池。标题界面与游戏共用，切换场景时音乐不中断。

const NAMES := ["heartbeat", "swing", "swing_heavy", "hit", "kill", "tentacle", "hurt", "dodge", "pickup", "oil",
	"levelup", "relic", "skill", "roar", "boom", "ui_move", "ui_ok", "start", "lamp_out"]
## 倒下过渡的「灯灭」（music_director 触发）：-8 dB 时比同时段的 lose 乐句低约 3 dB（全频段），不盖过配乐
const LAMP_OUT_DB := -8.0
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
## 音乐（docs/21 v3）。两种曲目：
## - 整首循环（MUSIC）：标题 / 开场 / 商人 / 结算循环，一首一个文件
## - 乐句式（SEQ）：战斗三段 / 中期 Boss / 最终 Boss。8 小节一句，每句结束时按局势挑下一句（不紧挨着重复），无限不重样；
##   每句若干层同步开播（战斗：base 平静 / pulse 交战 / drive 激战 + danger 危险；最终 Boss：p1 / p2 二阶段）。
##   两组播放器轮流：下一句在另一组里开播，正文按音频时钟精确接在上一句末尾，上一句的余音在原来那组里响完
const MUSIC := {
	"title": ["title"],
	"opening": ["opening"],
	"shop": ["shop"],
	"win_loop": ["win_loop"],
	"lose_loop": ["lose_loop"],
}
const SEQ := {
	"battle1": {"bpm": 144.0, "layers": ["base", "pulse", "drive"], "danger": true, "kind": "battle"},
	"battle2": {"bpm": 144.0, "layers": ["base", "pulse", "drive"], "danger": true, "kind": "battle"},
	"battle3": {"bpm": 150.0, "layers": ["base", "pulse", "drive"], "danger": true, "kind": "battle"},
	"boss": {"bpm": 150.0, "layers": ["full"], "danger": false, "kind": "boss"},
	"final": {"bpm": 150.0, "layers": ["p1", "p2"], "danger": false, "kind": "final"},
}
## 句与句的衔接权重（没写的不接，自己不接自己）。战斗：A 和弦墙 / B 标题主旋律 / C 灯火动机 / D 半速间奏 / E B 主题；
## Boss：A riff / B 主题 / D 半速间奏 / C 高潮；最终 Boss：A 灯火动机 / B 标题主旋律 / C Boss 主题对峙 / D 主旋律高潮
const SEQ_NEXT := {
	"battle": {"A": {"B": 3.0, "C": 2.0, "D": 1.0, "E": 2.0}, "B": {"A": 3.0, "C": 1.0, "D": 2.0, "E": 2.0},
		"C": {"A": 2.0, "B": 3.0, "E": 1.0}, "D": {"A": 2.0, "B": 1.0, "E": 3.0}, "E": {"A": 3.0, "C": 2.0, "D": 1.0}},
	"boss": {"A": {"B": 3.0, "C": 1.0}, "B": {"D": 2.0, "C": 2.0, "A": 1.0}, "D": {"C": 3.0, "B": 1.0},
		"C": {"A": 2.0, "B": 2.0, "D": 1.0}},
	"final": {"A": {"B": 3.0, "C": 1.0}, "B": {"C": 2.0, "D": 2.0}, "C": {"D": 3.0, "A": 1.0},
		"D": {"A": 2.0, "B": 1.0, "C": 1.0}},
}
## 战斗强度再乘一遍：平静多给灯火动机，激战多给副歌 / 间奏 / B 主题
const SEQ_BIAS := [{"C": 3.0, "A": 1.5, "D": 0.3, "E": 0.6}, {}, {"B": 1.5, "D": 1.5, "E": 1.8, "C": 0.4}]
const SEG_PRE := 0.1         # 乐句文件开头的静音预留（与 tools/gen_music_battle.py 的 PRE 一致）
const SEG_BARS := 8
## 不循环的曲目（播完即停，之后由游戏选下一首）
const ONESHOT := ["opening"]
## 叠加短乐句，叠在当前音乐之上、不打断曲目：Boss 登场 / 击破
const OVERLAYS := ["boss_in", "boss_down"]
const BOSS_HIT := 0.75       # boss_in 里太鼓重击的时刻：Boss 曲从这里进
const BAR_AHEAD := 0.1       # 分层提前这么多秒开始淡入，保证小节线上的重拍是满音量
const STEM_IN := 10.0        # 分层淡入 / 淡出速度（每秒）：进层干脆，退层用两秒慢慢收
const STEM_OUT := 0.5
var groups := {}          # 整首曲目 -> Array[AudioStreamPlayer]
var seq := {}             # 乐句式曲目 -> {segs 句 -> [各层流], danger, decks [两组播放器], cur 当前组, seg 当前句, hist 最近两句, t0, len 句长, bpm, kind}
var group_vol := {}       # 曲目 -> 当前整体音量（0~1）
var group_rate := {}      # 曲目 -> [淡入, 淡出] 速度（每秒）
var stem_on := {}         # 乐句式曲目 -> 各层当前开关（小节线上才从游戏请求同步过来；战斗最后一层是危险层）
var stem_vol := {}        # 乐句式曲目 -> 各层实际音量
var cur_track := ""
var battle_lv := 0        # 游戏请求：0 平静 / 1 交战 / 2 激战
var battle_danger := false
var final_p2 := false     # 游戏请求：最终 Boss 二阶段
var clock_beat := -1      # 当前句已处理到的拍号
var pending := {}         # 等着开播的曲目：{track, boundary}（战斗换段：当前句结束时接新段第一句）/ {track, at, fade_in, out}（Boss 进出，墙钟）
var music_rng := RandomNumberGenerator.new()   # 挑下一句用，不碰全局随机流
var stinger: AudioStreamPlayer
var after_stinger := ""      # 结算短乐句播完后接续的循环曲目
var overlay_pl: Array = []   # 叠加短乐句播放器（两个，Boss 登场与击破可以同时响）
var overlays := {}
var overlay_t := {}          # 叠加短乐句 -> 本次开播时它第 0 秒对应的时刻
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
		group_rate[tname] = [0.8, 0.6]
	for tname in SEQ:
		_seq_init(tname)
	music_rng.randomize()
	stinger = AudioStreamPlayer.new()
	stinger.bus = "Music"
	add_child(stinger)
	for i in 2:
		var op := AudioStreamPlayer.new()
		op.bus = "Music"
		add_child(op)
		overlay_pl.append(op)
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


func _now() -> float:
	return Time.get_ticks_usec() / 1000000.0


## 乐句式曲目：载入每句每层的流（不循环），建两组播放器（各层 + 危险层）
func _seq_init(tname: String) -> void:
	var cfg: Dictionary = SEQ[tname]
	var q := {"segs": {}, "danger": null, "decks": [], "cur": 0, "seg": "", "hist": [], "t0": 0.0,
		"bpm": float(cfg.bpm), "len": SEG_BARS * 240.0 / float(cfg.bpm), "kind": cfg.kind}
	for sname in SEQ_NEXT[cfg.kind]:
		var arr: Array = []
		for layer in cfg.layers:
			var st: AudioStreamOggVorbis = _load_ogg("res://audio/music/%s_%s_%s.ogg" % [tname, sname, layer])
			if st != null:
				st.loop = false
			arr.append(st)
		q.segs[sname] = arr
	if cfg.danger:
		var dz: AudioStreamOggVorbis = _load_ogg("res://audio/music/%s_danger.ogg" % tname)
		if dz != null:
			dz.loop = false
		q.danger = dz
	var n: int = cfg.layers.size() + (1 if cfg.danger else 0)
	for d in 2:
		var deck: Array = []
		for i in n:
			var pl := AudioStreamPlayer.new()
			pl.bus = "Music"
			pl.volume_db = -80.0
			add_child(pl)
			deck.append(pl)
		q.decks.append(deck)
	seq[tname] = q
	group_vol[tname] = 0.0
	group_rate[tname] = [0.8, 0.6]
	stem_on[tname] = []
	stem_vol[tname] = []
	for i in n:
		stem_on[tname].append(0.0)
		stem_vol[tname].append(0.0)


## 在第 deck 组播放器里从 from 秒开播第 s 句（各层 + 危险层同一时刻开，保证同步）
func _seq_play(tname: String, s: String, deck: int, from: float) -> void:
	var q: Dictionary = seq[tname]
	var pls: Array = q.decks[deck]
	var sts: Array = q.segs[s]
	for i in pls.size():
		var pl: AudioStreamPlayer = pls[i]
		pl.stream = sts[i] if i < sts.size() else q.danger
		if pl.stream != null:
			pl.volume_db = linear_to_db(maxf(float(group_vol[tname]) * float(stem_vol[tname][i]), 0.0001)) + vol_target
			pl.play(from)
	q.cur = deck
	q.seg = s
	q.hist.push_front(s)
	if q.hist.size() > 2:
		q.hist.pop_back()
	q.t0 = _now() - (from - SEG_PRE)
	music = pls[0]


## 挑下一句：衔接权重 × 战斗强度偏好，上上句再打个折（避免 A B A B 来回）
func _seq_next(tname: String) -> String:
	var q: Dictionary = seq[tname]
	var table: Dictionary = SEQ_NEXT[q.kind].get(q.seg, {})
	var bias: Dictionary = SEQ_BIAS[clampi(battle_lv, 0, 2)] if q.kind == "battle" else {}
	var w := {}
	var total := 0.0
	for sname in table:
		var v: float = float(table[sname]) * float(bias.get(sname, 1.0))
		if q.hist.size() > 1 and q.hist[1] == sname:
			v *= 0.4
		w[sname] = v
		total += v
	var r := music_rng.randf() * total
	for sname in w:
		r -= float(w[sname])
		if r <= 0.0:
			return sname
	return q.seg if w.is_empty() else w.keys()[-1]


## 一段的第一句：平静时从灯火动机进，其余从 A 进
func _seq_first(tname: String) -> String:
	return "C" if (SEQ[tname].kind == "battle" and battle_lv == 0) else "A"


func _seq_stop(tname: String) -> void:
	for deck in seq[tname].decks:
		for pl in deck:
			pl.stop()


## 当前句的播放位置（秒，含开头预留）：取第一层的播放位置（音频时钟，掉帧也不会错拍）；
## 拿不到时（刚开播、网页版采样播放）退回墙钟
func _seq_pos(tname: String) -> float:
	var q: Dictionary = seq[tname]
	var pl: AudioStreamPlayer = q.decks[q.cur][0]
	var p := pl.get_playback_position()
	if p <= 0.0:
		return _now() - float(q.t0) + SEG_PRE
	return p + AudioServer.get_time_since_last_mix()


## 乐句式曲目每帧：句尾接下一句（或换段），小节线上同步分层
func _seq_tick(tname: String) -> void:
	var q: Dictionary = seq[tname]
	var pos := _seq_pos(tname)
	# 现在调 play() 会从下一次混音开播，那时本句在 pos + 距下次混音；一旦够到句长就开播下一句，
	# 从「那一刻 - 句长」秒开始——前面是 0.1 秒预留，正文正好接在本句末尾
	var at_mix := pos + AudioServer.get_time_to_next_mix()
	if at_mix >= float(q.len):
		var from := at_mix - float(q.len)
		if pending.get("boundary", false) and seq.has(pending.track):
			var nt: String = pending.track
			pending = {}
			group_rate[tname][1] = 0.6
			cur_track = nt
			group_rate[nt] = [0.8, 0.6]
			group_vol[nt] = 1.0
			for i in stem_on[nt].size():
				stem_on[nt][i] = _stem_want(nt, i)
				stem_vol[nt][i] = stem_on[nt][i]
			seq[nt].hist = []
			_seq_stop(nt)
			_seq_play(nt, _seq_first(nt), 0, from)
		else:
			_seq_play(tname, _seq_next(tname), 1 - int(q.cur), from)
		clock_beat = -1
		return
	# 小节线：把游戏请求的分层同步过来（进层落在小节线上、危险层可以按拍进；退层也等小节线）
	var beat := int(floor((pos - SEG_PRE + BAR_AHEAD) * float(q.bpm) / 60.0))
	if beat != clock_beat:
		clock_beat = beat
		var on: Array = stem_on[tname]
		for i in on.size():
			var w := _stem_want(tname, i)
			if w != on[i] and (beat % 4 == 0 or (i == 3 and w > on[i])):
				on[i] = w


## 切换曲目（游戏每帧都会调用，同一曲目重复调用没有副作用）：
## - 战斗换段：当前句唱完、下一句的位置直接接新段的第一句（新段句首的镲就是段落感，不另加提示音）
## - Boss 登场：旧曲马上淡出，Boss 曲落在 boss_in 的太鼓重击上
## - Boss 倒下回到战斗：先让击破乐句响 1.2 秒，战斗曲再从头缓缓回来
## - 其余：新曲从头淡入，旧曲淡出后停止
func play_music(tname: String) -> void:
	if tname != "title":
		driven_t = 0.0
	if not seq.has(tname) and (not groups.has(tname) or groups[tname].is_empty()):
		return
	if tname == cur_track:
		pending = {}
		return
	if pending.get("track", "") == tname:
		return
	after_stinger = ""
	stinger.stop()
	var now := _now()
	var old := cur_track
	if seq.has(old) and old.begins_with("battle") and tname.begins_with("battle"):
		pending = {"track": tname, "boundary": true}
	elif (tname == "boss" or tname == "final") and now - float(overlay_t.get("boss_in", -99.0)) < BOSS_HIT:
		pending = {"track": tname, "at": float(overlay_t["boss_in"]) + BOSS_HIT, "fade_in": 8.0, "out": 1.5}
		_release(1.5)
	elif (old == "boss" or old == "final") and tname.begins_with("battle"):
		pending = {"track": tname, "at": now + 1.2, "fade_in": 0.5, "out": 0.8}
		_release(0.8)
	else:
		pending = {}
		_start(tname, 0.8, 0.6)


## 开播一首（乐句式从第一句开始；各层同一时刻开，保证同步）；旧曲按 old_out 淡出
func _start(tname: String, fade_in: float, old_out: float, from := 0.0) -> void:
	if cur_track != "" and cur_track != tname:
		group_rate[cur_track][1] = old_out
	cur_track = tname
	clock_beat = -1
	group_rate[tname] = [fade_in, 0.6]
	if seq.has(tname):
		for i in stem_on[tname].size():
			stem_on[tname][i] = _stem_want(tname, i)
			stem_vol[tname][i] = stem_on[tname][i]
		seq[tname].hist = []
		_seq_stop(tname)
		_seq_play(tname, _seq_first(tname), 0, SEG_PRE + from)
	else:
		for pl in groups[tname]:
			pl.play(from)
		music = groups[tname][0]


## 当前曲目提前放手（淡出），等 pending 里的下一首
func _release(out: float) -> void:
	if cur_track != "":
		group_rate[cur_track][1] = out
	cur_track = ""


## 游戏请求的分层 -> 某曲目第 i 层该不该开
func _stem_want(tname: String, i: int) -> float:
	if tname.begins_with("battle"):
		return 1.0 if [true, battle_lv >= 1, battle_lv >= 2, battle_danger][i] else 0.0
	if tname == "final":
		return 1.0 if i == 0 or final_p2 else 0.0
	return 1.0


## 战斗曲分层：lv 0 平静（base）/ 1 交战（+ 打击乐）/ 2 激战（+ 全奏）；danger 叠危险层。落在小节线上生效
func set_battle(lv: int, danger: bool) -> void:
	driven_t = 0.0
	battle_lv = lv
	battle_danger = danger


## 最终 Boss 二阶段加强层（落在小节线上）
func set_final_phase(p2: bool) -> void:
	final_p2 = p2


## 结算短乐句：当前曲目淡出
func play_stinger(sname: String) -> void:
	var st: AudioStreamOggVorbis = _load_ogg("res://audio/music/%s.ogg" % sname)
	if st == null:
		return
	st.loop = false
	cur_track = ""
	pending = {}
	after_stinger = sname + "_loop" if groups.has(sname + "_loop") else ""
	stinger.stream = st
	stinger.volume_db = vol_target
	stinger.play()


## 叠加短乐句：不改变当前曲目，直接叠在音乐之上（Boss 登场 / 击破）；from 为从第几秒开始
func play_overlay(oname: String, gain_db := 2.0, from := 0.0) -> void:
	if not overlays.has(oname):
		return
	var op: AudioStreamPlayer = overlay_pl[0]
	for p in overlay_pl:
		if not p.playing:
			op = p
			break
	op.stream = overlays[oname]
	op.volume_db = vol_target + gain_db
	op.play(from)
	overlay_t[oname] = _now() - from


## 某曲目是否正是当前曲目且仍在播放（用于等待不循环曲目播完）
func track_playing(tname: String) -> bool:
	if cur_track != tname:
		return false
	if seq.has(tname):
		return true
	return not groups[tname].is_empty() and (groups[tname][0] as AudioStreamPlayer).playing


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
	var path := "res://audio/voice/%s_%s.ogg" % [cid, key]   # WAV 母带在 audio/voice/masters（不导入），见 tools/voice_ogg.py
	if not voice_streams.has(path):
		var st: AudioStreamOggVorbis = _load_ogg(path)
		if st != null:
			st.loop = false
			if st.get_length() > VOICE_MAX_LEN:
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
		battle_lv = 1
		play_music("battle1")
	var now := _now()
	# 等着开播的曲目（Boss 进出，按墙钟）；迟到的那几毫秒从曲中补上
	if pending.has("at") and now >= float(pending.at):
		var p := pending
		pending = {}
		_start(p.track, float(p.fade_in), float(p.out), now - float(p.at))
	if seq.has(cur_track):
		_seq_tick(cur_track)
	for tname in groups:
		var want := 1.0 if tname == cur_track else 0.0
		var rate: Array = group_rate[tname]
		var gv: float = move_toward(group_vol[tname], want, delta * (rate[0] if want > group_vol[tname] else rate[1]))
		group_vol[tname] = gv
		for pl in groups[tname]:
			pl.volume_db = linear_to_db(maxf(gv, 0.0001)) + vol_target
			if gv <= 0.0 and pl.playing:
				pl.stop()
	for tname in seq:
		var want := 1.0 if tname == cur_track else 0.0
		var rate: Array = group_rate[tname]
		var gv: float = move_toward(group_vol[tname], want, delta * (rate[0] if want > group_vol[tname] else rate[1]))
		group_vol[tname] = gv
		var on: Array = stem_on[tname]
		var sv: Array = stem_vol[tname]
		for i in sv.size():
			sv[i] = move_toward(sv[i], on[i], delta * (STEM_IN if on[i] > sv[i] else STEM_OUT))
		for deck in seq[tname].decks:
			for i in deck.size():
				var pl: AudioStreamPlayer = deck[i]
				if pl.playing:
					pl.volume_db = linear_to_db(maxf(gv * sv[i], 0.0001)) + vol_target
					if gv <= 0.0:
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
