extends Node
## 全局音频（自动加载为 Sfx）：背景音乐 + 音效池。标题界面与游戏共用，切换场景时音乐不中断。

const NAMES := ["heartbeat", "swing", "swing_heavy", "hit", "kill", "tentacle", "hurt", "dodge", "pickup", "oil",
	"levelup", "relic", "skill", "roar", "boom", "ui_move", "ui_ok", "start", "lamp_out",
	"knight_charge", "knight_stab", "knight_frost", "hunt_warn", "hunt_close", "hunt_break", "enemy_screech", "enemy_spit", "enemy_bite", "enemy_nerve", "mire_clear", "enemy_acid", "enemy_elite", "crit_tick", "break_open", "break_hit", "lamp_empty", "heartbeat_hi", "beacon_tick", "beacon_lit", "beacon_end", "nerve_burst", "mire_splat",
	"cocoon_form", "shell_break", "cocoon_revive", "izu_lamp_lit", "izu_absorb", "izu_wave_count", "apop_pause", "apop_resume", "stake_hit", "stake_shatter", "carmen_sword", "ishar_land_break", "paranoia_land_break", "bishop_panic",
	"ulp_charge_loop", "ulp_release", "atk_gate", "beacon_fizzle", "kill_big", "kill_shell", "hurt_heavy",
	"boss_archon", "boss_bishop", "boss_carmen", "boss_iberia", "boss_immortal", "boss_ishar", "boss_izumik", "boss_knight_boss", "boss_paranoia", "boss_path", "cue_beam_hit", "cue_beam_start", "cue_charge_hit", "cue_charge_start", "cue_global_hit", "cue_global_start", "cue_land_hit", "cue_land_start", "cue_melee_hit", "cue_melee_start", "cue_phase_start"]
## 倒下过渡的「灯灭」（music_director 触发）：-8 dB 时比同时段的 lose 乐句低约 3 dB（全频段），不盖过配乐
const LAMP_OUT_DB := -8.0
## 同一音效的最短间隔（秒），避免大量敌人同时被击中时声音糊成一片
const LIMIT := {"crit_tick": 0.08, "break_hit": 0.12, "enemy_acid": 0.25, "enemy_elite": 0.25, "enemy_nerve": 0.25, "atk_gate": 0.1, "mire_splat": 0.12, "enemy_screech": 1.2, "enemy_spit": 0.22, "enemy_bite": 0.18, "op_wisadel_atk": 0.12, "op_wisadel_hit": 0.16, "op_wisadel_big": 0.25, "op_wisadel_quake": 0.25, "op_kaltsit_big": 0.3, "knight_charge": 0.15, "knight_stab": 0.08, "hit": 0.035, "kill": 0.045, "kill_big": 0.045, "kill_shell": 0.045, "hurt_heavy": 0.1, "pickup": 0.04, "tentacle": 0.07, "swing": 0.05, "dodge": 0.1, "hurt": 0.1}

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
	"wisadel": ["atk", "hit", "s1", "s2", "s3", "quake", "big"],
	# 第二批（docs/28 §第二批）
	"irene": ["atk", "hit", "s1", "s2", "s3", "big"],
	"logos": ["atk", "hit", "s1", "s2", "s3", "big"],
	"lumen": ["atk", "hit", "s1", "s2", "s3", "big"],
	"specter_unchained": ["atk", "s1", "s2", "s3"],
	"ulpianus": ["atk", "s1", "s2", "s3", "big"],
	# 网上 CC0 录音截取（docs/113 §8，tools/import_sfx_cc0.py）：能天使枪声 / 命中 / 弹匣倾泻、德克萨斯刀划、星熊格挡；其余类别仍走 OP_ALT 借用
	"exusiai": ["atk", "atk_b", "atk_c", "hit", "s1", "s2", "s3", "big"],   # 10-25 用户「能天使的音效没有替换」：三条枪声轮换 + 技能连射全换（docs/113 §17）
	"texas": ["atk", "hit"],
	"hoshiguma": ["hit"],
}
## 各类别的默认音量（dB）：普攻 / 命中最频繁，压低；技能发动是一局里少数几次的"高光"，放开
const OP_VOL := {"atk": -11.0, "hit": -10.0, "s1": -4.0, "s2": -4.0, "s3": -2.0, "big": -6.0, "heal": -9.0, "quake": -13.0}
## 各类别的最短间隔（秒，按单个干员计）：三四名干员同时开火时不糊成一片
const OP_LIMIT := {"atk": 0.06, "hit": 0.06, "quake": 0.08, "big": 0.1, "heal": 0.3}
## 音效盘点（docs/113，10-21 用户「枪击、锁链等各种音效都需要优化」）按请求名（op_<干员>_<类别>）的三张旋钮表：
## OP_DB 音量偏移（dB，叠在 OP_VOL 与调用处偏移上）；OP_GAP 最短间隔（秒，按请求名算，借用同一文件的干员各算各的）；
## OP_PVAR 音高随机（±，取它与调用处的较大值）。数字来自 docs/113 §2 实测：混音里最响的是长尾低频重击的高频连发
const OP_DB := {"op_eyjafjalla_big": -3.0, "op_kaltsit_big": -2.0, "op_wisadel_quake": -3.0, "op_wisadel_hit": -1.5, "op_exusiai_hit": -5.0,
	"op_exusiai_s1": -4.0, "op_exusiai_s2": -5.0, "op_exusiai_s3": -6.0, "op_exusiai_big": -3.0, "op_texas_hit": -3.0}
const OP_GAP := {"op_exusiai_atk": 0.085, "op_exusiai_hit": 0.14, "op_exusiai_big": 0.5, "op_eyjafjalla_big": 0.2}
const OP_PVAR := {"op_exusiai_atk": 0.09, "op_exusiai_hit": 0.1, "op_irene_atk": 0.08, "op_texas_atk": 0.08, "op_eyjafjalla_atk": 0.08, "op_lumen_atk": 0.07, "op_wisadel_quake": 0.12}
var op_last := {}          # 请求名 -> 上次放行的墙钟秒（OP_GAP）
## 轮换：同一请求名有多个录音时按次序轮着放（连射不像同一声复读）；次序只用于声音，不碰玩法随机
const OP_ROT := {"op_exusiai_atk": ["op_exusiai_atk_b", "op_exusiai_atk_c"]}
var op_rot := {}           # 请求名 -> 已放次数
## 缺文件时退回的通用音效（新干员还没配音时也有声音）
const OP_FALLBACK := {"atk": "swing", "hit": "hit", "s1": "skill", "s2": "skill", "s3": "skill", "big": "boom", "heal": "oil", "quake": "boom"}
## 缺专属文件时优先借用的近似音（docs/53，比通用 hit 更贴角色；[音名, 音高倍率, 音量偏移 dB]）。正式音色见 docs/53 §5 的制作清单
const OP_ALT := {"op_logos_hit": ["op_mizuki_hit", 0.8, -4.0],
	# 浊心斯卡蒂（docs/61，数据干员，暂无专属音）：普攻借铃兰低八度的吟唱，技能借流明 / 铃兰 / 凯尔希的发动音（docs/28 加新干员前的借用）
	"op_skalter_atk": ["op_suzuran_atk", 0.75, -3.0], "op_skalter_s1": ["op_lumen_s1", 0.85, 0.0],
	"op_skalter_s2": ["op_suzuran_s2", 0.8, 0.0], "op_skalter_s3": ["op_kaltsit_s3", 0.85, 0.0],
	# 星熊（docs/61「星熊」节，数据干员）：盾沿横扫借塞雷娅普攻降调，技能借塞雷娅 / 推进之王 / 斯卡蒂；格挡「铛」已换 CC0 录音 op_hoshiguma_hit（docs/113 §8）
	"op_hoshiguma_atk": ["op_saria_atk", 0.85, 0.0], "op_hoshiguma_big": ["op_siege_big", 1.25, -2.0],
	"op_hoshiguma_s1": ["op_saria_s1", 0.9, 0.0], "op_hoshiguma_s2": ["op_siege_s2", 0.85, 0.0], "op_hoshiguma_s3": ["op_skadi_s3", 0.85, 0.0],
	# 安洁莉娜（docs/61 §12，数据干员，暂无专属音）：普攻借 Logos 低沉的法术起手（「嗡」），落点借铃兰命中压低（内收短鸣），技能借 Logos / 铃兰 / 流明
	"op_angelina_atk": ["op_logos_atk", 0.7, -2.0], "op_angelina_hit": ["op_suzuran_hit", 0.7, -2.0], "op_angelina_s1": ["op_logos_s1", 0.85, 0.0],
	"op_angelina_s2": ["op_suzuran_s2", 0.6, 0.0], "op_angelina_s3": ["op_lumen_s3", 0.9, -1.0],
	# 德克萨斯（docs/61 §13，数据干员）：技能借艾丽妮 / 推进之王；冲刺起冲 op_texas_atk、收势 op_texas_hit 是合成版专属音（docs/113 §15，10-24 用户定）
	"op_texas_s1": ["op_irene_s1", 1.05, 0.0],
	"op_texas_s2": ["op_siege_s2", 1.15, 0.0], "op_texas_s3": ["op_irene_s3", 1.1, 0.0],
	# 能天使（docs/61 §14，数据干员）：技能借艾丽妮 / 维什戴尔；枪声 / 命中 / 弹匣倾泻已换 CC0 录音 op_exusiai_atk / hit / big（docs/113 §8）
	# 技能 s1 / s2 / s3 也已换成枪声连射拼的专属音（docs/113 §17），借用表里不再有能天使
	}
## 通用音缺文件时的借用（docs/53 §5 的三个材质 / 重击层，正式文件已由 tools/gen_sfx_hitfeel.py 合成；[音名, 音高倍率, 音量偏移 dB]，
## 偏移按调用处的音量算成和原顶替一样：kill_big −8 → mire_splat −9 ×0.85，kill_shell −6 → hit −6 ×0.6，hurt_heavy −8 → boom −10 ×0.7）
const ALT := {"kill_big": ["mire_splat", 0.85, -1.0], "kill_shell": ["hit", 0.6, 0.0], "hurt_heavy": ["boom", 0.7, -2.0]}

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
## 图鉴曲目文件（docs/21「局外配乐」）：用户 10-12 定 V2「卫戍」战术律动电子，编制与标题曲区分开（无钢琴 / 竖琴 / 人声 / 弦乐 / 鲸歌）。
## V0《潮汐档案》、V1「本舰」的文件已删（省包体），要试回去先 `python gen_music.py archive` / `archive_v1` 重新生成再改这一行；
## 曲目名仍叫 archive（title.gd 选曲、menu_bgm_test 都不用动）
const ARCHIVE_FILE := "archive_v2"
const MUSIC := {
	"title": ["title"],
	"archive": [ARCHIVE_FILE],
	"deploy": ["deploy"],
	"opening": ["opening"],
	"shop": ["shop"],
	"win_loop": ["win_loop"],
	"lose_loop": ["lose_loop"],
	"final": ["final_suno"],   # 10-27 最终 Boss 换 Suno《The Deep Sea Awakens》整首循环（暂无分轨，二阶段不叠层）
}
const SEQ := {
	"battle1": {"bpm": 144.0, "layers": ["base", "pulse", "drive"], "danger": true, "kind": "battle"},
	"battle2": {"bpm": 144.0, "layers": ["base", "pulse", "drive"], "danger": true, "kind": "battle"},
	"battle3": {"bpm": 150.0, "layers": ["base", "pulse", "drive"], "danger": true, "kind": "battle"},
	"boss": {"bpm": 150.0, "layers": ["full"], "danger": false, "kind": "boss"},
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
## 局外配乐（docs/21「局外配乐」，用户 10-12）：标题 / 设置 / 操作说明 / 致谢 = title，图鉴 = archive，选人 / 难度 / Boss 演练 = deploy。
## 局外曲目之间约 1 秒交叉淡化；离开时记住播到第几秒，回来接着放（不从头）；两个界面共用一首时 play_music 同名无副作用，不会重开。
## 进局（任何不是局外曲目的曲目开播）清空记忆：打完一局回标题，标题曲从头放
const MENU_TRACKS := ["title", "archive", "deploy"]
const MENU_FADE := 1.0       # 局外曲目互切的淡入 / 淡出速度（每秒）= 1 秒
var menu_pos := {}           # 局外曲目 -> 淡出停下时播到的秒数
var track_t0 := {}           # 整首曲目 -> 「第 0 秒」对应的墙钟（算播放位置，不依赖音频驱动：网页样本播放位置滞后、无界面哑驱动偏慢）
var groups := {}          # 整首曲目 -> Array[AudioStreamPlayer]
var seq := {}             # 乐句式曲目 -> {segs 句 -> [各层流], danger, decks [两组播放器], cur 当前组, seg 当前句, hist 最近两句, t0, len 句长, bpm, kind}
var group_vol := {}       # 曲目 -> 当前整体音量（0~1）
var group_rate := {}      # 曲目 -> [淡入, 淡出] 速度（每秒）
var stem_on := {}         # 乐句式曲目 -> 各层当前开关（小节线上才从游戏请求同步过来；战斗最后一层是危险层）
var stem_vol := {}        # 乐句式曲目 -> 各层实际音量
## Suno 整首分层循环（docs/164，10-27）：曲目 -> {players 各层播放器, bpm, offset 首拍偏移秒, len 时长秒}；各层同长度、同时开播、各层单独控音量（stem_on / stem_vol 复用）、
## 小节线上切层。开关 balance.json music/suno_layers（缺省 1；0 = 回到旧的 SEQ 乐句拼接 / MUSIC 整首，旧文件与代码都还在）
var lay := {}
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
	for a in (OS.get_cmdline_user_args() if OS.is_debug_build() else PackedStringArray()):
		if a.begins_with("--"):
			return true
	return false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("web") and (OS.get_cmdline_user_args() if OS.is_debug_build() else PackedStringArray()).has("--audiofree"):
		_audio_free_test.call_deferred()
	if OS.has_feature("web") and (OS.get_cmdline_user_args() if OS.is_debug_build() else PackedStringArray()).has("--musictour"):
		_music_tour.call_deferred()
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
	voice_fader = AudioStreamPlayer.new()
	voice_fader.bus = "Voice"
	add_child(voice_fader)
	var cfg: Node = get_node_or_null("/root/Cfg")
	if cfg != null and "voice" in cfg:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Voice"), linear_to_db(maxf(float(cfg.voice), 0.0001)))
	voice_log = cfg != null and cfg.has_method("dev_args") and cfg.dev_args().has("--voicelog")
	for n in NAMES:
		streams[n] = _load_wav("res://audio/sfx/%s.wav" % n)
	for oid in OP_SFX:
		for kind in OP_SFX[oid]:
			var sn := "op_%s_%s" % [oid, kind]
			streams[sn] = _load_wav("res://audio/sfx/%s.wav" % sn)
			var lk: String = "atk" if kind.begins_with("atk_") else kind   # atk_b / atk_c 是普攻的轮换录音，限流同普攻
			if OP_LIMIT.has(lk):
				op_limit[sn] = OP_LIMIT[lk]
	op_limit["op_siege_s1"] = SIEGE_S1_GAP   # 冲锋号令（见 VOICE_CAP 上方的实测）
	for i in 32:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		players.append(p)
	for tname in MUSIC:
		var arr: Array = []
		var files: Array = MUSIC[tname]
		if tname == "archive" and _suno_on() and ResourceLoader.exists("res://audio/music/suno_archive_full.ogg"):
			files = ["suno_archive_full"]   # 图鉴：Suno 分轨相加成整曲（docs/164）；关开关 music/suno_layers = 0 回到 archive_v2
		for f in files:
			var st: AudioStreamOggVorbis = _load_ogg("res://audio/music/%s.ogg" % f)
			if st == null:
				continue
			st.loop = not ONESHOT.has(tname)
			if tname == "shop":
				st.loop_offset = 972797.0 / 44100.0   # 用户提供的前奏只播一次，之后循环正文（docs/21）
			var pl := AudioStreamPlayer.new()
			pl.stream = st
			pl.bus = "Music"
			pl.volume_db = -80.0
			add_child(pl)
			arr.append(pl)
		groups[tname] = arr
		group_vol[tname] = 0.0
		group_rate[tname] = [0.8, 0.6]
	_suno_init()
	for tname in SEQ:
		if not lay.has(tname):
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
	_mobile_audio.call_deferred()   # Cfg 比本节点后加载：下一帧再判手机网页，标题曲也挪到那时开（先定播放方式再放）


## 手机网页的配乐改「流式」播放（10-26 用户「不崩溃优先」，docs/50 §30）：网页缺省按样本播放，每条曲子第一次放就整段解码成 PCM 留在 JS 里，
## 一首三四分钟的 Boss 曲就六十多 MB、而且没法从脚本注销；流式边解码边放，不留整段（代价：没有线程时在主线程混音，卡帧时可能断续）。音效照旧按样本
func _mobile_audio() -> void:
	var cfg = get_node_or_null("/root/Cfg")
	if cfg != null and cfg.mobile_web() and cfg.mobile_knob("mobile_music_stream", 0.0):   # 缺省关：polish-fx 实测手机流式配乐几乎无声（标题页电平 0.0009，桌面 0.022），改回样本 + 少放几首（MOBILE_MUSIC_MAP）
		for n in find_children("*", "AudioStreamPlayer", true, false):
			var pl := n as AudioStreamPlayer
			if pl.bus == "Music":
				pl.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	play_music("title")


## 网页音频样本预热（10-22 网页开局掉帧）：网页版按「样本」播放，每条流第一次 play 时才整段解码、建 Web Audio 缓冲，
## 当帧卡 50–130 ms。战斗乐 battle1 按乐句随机接续（A–E × 三层 + 危险层，每句约 13 秒），开局前一两分钟每换一句卡一下；
## 音效同理（每种第一次响时）。标题页点出发后的「载入中」等待里把这些流逐条注册成样本（AudioServer.register_stream_as_sample），
## 进局后就不再现解码。只在网页版做；声音本身、播放时机都不变
var _warm_q: Array = []
var _warm_total := 0

func warm_begin() -> void:
	if not OS.has_feature("web"):
		return
	var list: Array = _track_streams("battle1")
	var cfg = get_node_or_null("/root/Cfg")   # sfx 比 Cfg 先加载，不能直接写 Cfg
	if cfg != null and cfg.mobile_web() and not cfg.mobile_knob("mobile_warm_music", 1.0):   # 10-27 起缺省开（docs/50 §40）：24 kHz + 切曲释放后内存够，局内首段解码改在载入页做
		list.clear()
	if not list.is_empty():
		_next["battle1"] = true   # 载入页预热后保留到第一首开播；不预解码后续整首分层曲
		_freed.erase("battle1")
	for n in streams:
		list.append(streams[n])
	var seen := {}
	for st in list:
		if st is AudioStream and not seen.has(st) and not _warm_q.has(st) and not AudioServer.is_stream_registered_as_sample(st):
			seen[st] = true
			_warm_q.append(st)
	_warm_total = _warm_q.size()


## 每帧调一次：budget_usec 微秒内尽量多注册（至少一条）；返回是否还有剩
func warm_step(budget_usec: int) -> bool:
	var t0 := Time.get_ticks_usec()
	while not _warm_q.is_empty():
		var st: AudioStream = _warm_q.pop_front()
		if not AudioServer.is_stream_registered_as_sample(st):
			AudioServer.register_stream_as_sample(st)
		if Time.get_ticks_usec() - t0 > budget_usec:
			break
	return not _warm_q.is_empty()


## 已注册成网页样本的音频解码后大约占多少 MB（float32 × 声道 × 混音采样率 × 时长；--memlog / 内存护栏 / 性能报告用）。
## 发布包打了引擎补丁时直接读引擎样本表的实际字节（window.__syAudioMB，docs/50 §40：切曲释放后估算会偏高）
func sample_mem_mb() -> float:
	if not OS.has_feature("web"):
		return 0.0
	var js = JavaScriptBridge.eval("window.__syAudioMB?window.__syAudioMB():-1", true)
	if js != null and float(js) >= 0.0:
		return float(js)
	var seen := {}
	var total := 0.0
	var lists: Array = streams.values()
	for tn in seq.keys() + lay.keys() + groups.keys():
		lists.append_array(_track_streams(tn))
	for child in get_children():
		if child is AudioStreamPlayer:
			lists.append(child.stream)
	for st in lists:
		if st is AudioStream and not seen.has(st) and AudioServer.is_stream_registered_as_sample(st):
			seen[st] = true
			total += st.get_length() * AudioServer.get_mix_rate() * 2.0 * 4.0
	return total / 1048576.0


func warm_busy() -> bool:
	return not _warm_q.is_empty()


func warm_progress() -> Vector2i:
	return Vector2i(_warm_total - _warm_q.size(), _warm_total)


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


var WEB := OS.has_feature("web")


func _now() -> float:
	return Time.get_ticks_usec() / 1000000.0


## 手机网页的战斗乐只放底层（不放加层 / 危险层），省下网页样本解码后的内存；sfx 比 Cfg 先加载，按节点取
var _lite := -1
func _music_lite() -> bool:
	if _lite < 0:
		var cfg = get_node_or_null("/root/Cfg")
		_lite = 1 if cfg != null and cfg.mobile_web() and cfg.mobile_knob("mobile_music_lite", 0.0) else 0   # 10-27 起缺省关（docs/50 §40）：手机也放完整曲目、全部分层，内存靠切曲释放 + 24 kHz 上下文
	return _lite == 1


func _music_cap_hit() -> bool:
	if not _music_lite():
		return false
	var cfg = get_node_or_null("/root/Cfg")
	var cap: float = load("res://scripts/core/balance.gd").v("web/mobile_music_cap_mb", 64.0)
	return cfg != null and cap > 0.0 and sample_mem_mb() > cap


## Suno 整首分层循环的曲目表（文件由 tools/suno_layers.py 生成，bpm / 首拍偏移 / 时长在 suno_layers.json）。
## 层的含义：battle 三段 = [底层 平静, 打击乐 交战, 驱动 激战]；boss = [全曲]；final = [p1 一阶段, p2 二阶段叠加]
const SUNO_TRACKS := ["battle1", "battle2", "battle3", "boss", "final"]
const SUNO_META := "res://audio/music/suno_layers.json"


func _suno_on() -> bool:
	return load("res://scripts/core/balance.gd").v("music/suno_layers", 1.0) > 0.0


func _suno_init() -> void:
	if not _suno_on() or not FileAccess.file_exists(SUNO_META):
		return
	var meta = JSON.parse_string(FileAccess.get_file_as_string(SUNO_META))
	if not meta is Dictionary:
		return
	for tname in SUNO_TRACKS:
		var m = meta.get(tname, null)
		if not m is Dictionary:
			continue
		var pls: Array = []
		var ok := true
		for i in m.files.size():
			var st: AudioStreamOggVorbis = _load_ogg("res://audio/music/%s.ogg" % m.files[i])
			if st == null:
				ok = false
				break
			st.loop = true
			var pl := AudioStreamPlayer.new()
			pl.stream = st
			pl.bus = "Music"
			pl.volume_db = -80.0
			add_child(pl)
			pls.append(pl)
		if not ok:
			for pl in pls:
				pl.queue_free()
			continue
		lay[tname] = {"players": pls, "bpm": float(m.bpm), "offset": float(m.offset), "len": float(m.len)}
		for old_pl in groups.get(tname, []):
			old_pl.queue_free()   # 释放被分层版取代的整曲播放器及资源引用
		groups.erase(tname)   # MUSIC 里同名的整首（final_suno）让位
		group_vol[tname] = 0.0
		group_rate[tname] = [0.8, 0.6]
		stem_on[tname] = []
		stem_vol[tname] = []
		for i in pls.size():
			stem_on[tname].append(0.0)
			stem_vol[tname].append(0.0)


## 整首分层曲目当前播到第几秒（按开播时记的墙钟算，对时长取模；网页样本播放的 get_playback_position 滞后约 1 秒，所以一律用墙钟）
func _lay_pos(tname: String) -> float:
	return fposmod(_now() - float(track_t0.get(tname, _now())), float(lay[tname].len))


## 下一条小节线（墙钟）：战斗段之间切换时等它再换曲，换曲点永远落在上一首的小节线上
func _lay_next_bar_at(tname: String) -> float:
	var q: Dictionary = lay[tname]
	var bar: float = 4.0 * 60.0 / float(q.bpm)
	var pos: float = _lay_pos(tname) - float(q.offset)
	var nxt: float = ceilf(pos / bar + 0.0001) * bar - pos
	return _now() + maxf(nxt, 0.05)


## 整首分层曲目每帧：小节线上把游戏请求的分层同步过来（进层提前 BAR_AHEAD 淡入，保证重拍满音量）
func _lay_tick(tname: String) -> void:
	var q: Dictionary = lay[tname]
	var pos: float = _lay_pos(tname)
	var beat := int(floor((pos - float(q.offset) + BAR_AHEAD) * float(q.bpm) / 60.0))
	if beat != clock_beat:
		clock_beat = beat
		var on: Array = stem_on[tname]
		for i in on.size():
			var w := _stem_want(tname, i)
			if w != on[i] and beat % 4 == 0:
				on[i] = w


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
	var lite: bool = _music_lite()
	var fresh := 0   # 这一句里还没解码的层（开播当帧在主线程整段解码，网页仿真一层 100–250 ms）：记进性能报告
	for st in sts + [q.danger]:
		if st is AudioStream and not AudioServer.is_stream_registered_as_sample(st):
			fresh += 1
	if fresh > 0 and OS.has_feature("web"):
		var sc = get_tree().current_scene
		if sc != null and "perf_rep" in sc and sc.perf_rep != null:
			sc.perf_rep.tag("解码配乐 %d 层" % fresh)
	for i in pls.size():
		var pl: AudioStreamPlayer = pls[i]
		pl.stream = sts[i] if i < sts.size() else q.danger
		if lite and i > 0:
			pl.stream = null   # 手机网页只放底层（docs/50 §30）：每层一句约 4–5 MB 解码后的 PCM，播过就一直留在 JS 里，九分钟能攒到两百多 MB
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
	if _music_cap_hit():
		# 手机网页音频封顶（docs/50 §34）：网页样本注册了就释放不掉，后期每句新乐句约 5.5 MB；超过 web/mobile_music_cap_mb 后只在已经响过的句里挑
		var reg := {}
		var rt := 0.0
		for sname in w:
			var sts: Array = q.segs.get(sname, [])
			if not sts.is_empty() and sts[0] != null and AudioServer.is_stream_registered_as_sample(sts[0]):
				reg[sname] = w[sname]
				rt += float(w[sname])
		if rt > 0.0:
			w = reg
			total = rt
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
	# 网页版（样本播放）：get_playback_position() 比实际声音滞后约 1 秒，按它排下一句会在每句之间空出约 1 秒（2026-09-27 浏览器实测）。
	# 网页的样本在 play() 当帧就开始出声，墙钟和音频时钟在一句 15 秒里几乎不漂，所以网页一律按墙钟算
	if WEB:
		return _now() - float(q.t0) + SEG_PRE
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
	var at_mix := pos + (0.0 if WEB else AudioServer.get_time_to_next_mix())   # 网页的样本 play() 当帧就开播，不用等下次混音
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
## 手机与桌面使用相同曲目与分层；网页用共享样本、切曲释放及 24 kHz 上下文控制内存。

func play_music(tname: String) -> void:
	if not MENU_TRACKS.has(tname):
		driven_t = 0.0
	if not seq.has(tname) and not lay.has(tname) and (not groups.has(tname) or groups[tname].is_empty()):
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
	if lay.has(old) and old.begins_with("battle") and lay.has(tname) and tname.begins_with("battle"):
		# 战斗换段：当前曲照常放到下一条小节线，新曲在小节线上从头开（淡入 / 淡出速度 6 / 秒 ≈ 0.17 秒，近乎硬切）
		pending = {"track": tname, "at": _lay_next_bar_at(old), "fade_in": 6.0, "out": 6.0}
	elif seq.has(old) and old.begins_with("battle") and tname.begins_with("battle"):
		pending = {"track": tname, "boundary": true}
	elif (tname == "boss" or tname == "final") and now - float(overlay_t.get("boss_in", -99.0)) < BOSS_HIT:
		pending = {"track": tname, "at": float(overlay_t["boss_in"]) + BOSS_HIT, "fade_in": 8.0, "out": 1.5}
		_release(1.5)
	elif (old == "boss" or old == "final") and tname.begins_with("battle"):
		pending = {"track": tname, "at": now + 1.2, "fade_in": 0.5, "out": 0.8}
		_release(0.8)
	elif MENU_TRACKS.has(tname) and MENU_TRACKS.has(old):
		pending = {}
		_start(tname, MENU_FADE, MENU_FADE)
	else:
		pending = {}
		_start(tname, 0.8, 0.6)


## 开播一首（乐句式从第一句开始；各层同一时刻开，保证同步）；旧曲按 old_out 淡出
func _start(tname: String, fade_in: float, old_out: float, from := 0.0) -> void:
	_freed.erase(tname)
	_queue_next(tname)
	if cur_track != "" and cur_track != tname:
		group_rate[cur_track][1] = old_out
	cur_track = tname
	clock_beat = -1
	group_rate[tname] = [fade_in, 0.6]
	if not MENU_TRACKS.has(tname):
		menu_pos.clear()
	if lay.has(tname):
		if OS.has_feature("web"):
			# 先注册全部层再一起 play，避免逐层解码把三层的起点拉开。
			for st in _track_streams(tname):
				if not AudioServer.is_stream_registered_as_sample(st):
					AudioServer.register_stream_as_sample(st)
		for i in stem_on[tname].size():
			stem_on[tname][i] = _stem_want(tname, i)
			stem_vol[tname][i] = stem_on[tname][i]
		for pl in lay[tname].players:
			pl.play(from)
		track_t0[tname] = _now() - from
		music = lay[tname].players[0]
	elif seq.has(tname):
		for i in stem_on[tname].size():
			stem_on[tname][i] = _stem_want(tname, i)
			stem_vol[tname][i] = stem_on[tname][i]
		seq[tname].hist = []
		_seq_stop(tname)
		_seq_play(tname, _seq_first(tname), 0, SEG_PRE + from)
	else:
		var menu := MENU_TRACKS.has(tname)
		if menu and group_vol[tname] > 0.0 and (groups[tname][0] as AudioStreamPlayer).playing:
			pass   # 局外曲目还没淡完就切回来：接着淡入，不重开
		else:
			if menu and from == 0.0:
				from = float(menu_pos.get(tname, 0.0))
			for pl in groups[tname]:
				pl.play(from)
			track_t0[tname] = _now() - from
		music = groups[tname][0]


## 整首曲目当前播到第几秒（按开播时记的墙钟算，循环取模；没在播时给离开时记下的位置）
func track_pos(tname: String) -> float:
	if not groups.has(tname) or groups[tname].is_empty():
		return 0.0
	var pl: AudioStreamPlayer = groups[tname][0]
	if not pl.playing or not track_t0.has(tname):
		return float(menu_pos.get(tname, 0.0))
	var t := _now() - float(track_t0[tname])
	var ln := pl.stream.get_length() if pl.stream != null else 0.0
	return fposmod(t, ln) if ln > 0.0 else t


## 当前曲目提前放手（淡出），等 pending 里的下一首
func _release(out: float) -> void:
	if cur_track != "":
		group_rate[cur_track][1] = out
	cur_track = ""


## 游戏请求的分层 -> 某曲目第 i 层该不该开
func _stem_want(tname: String, i: int) -> float:
	if lay.has(tname) and tname.begins_with("battle"):
		# 整首分层没有单独的危险层：危险时把驱动层（吉他 / 铜管）拉出来代替（原先危险层 = 高频紧张音）
		return 1.0 if [true, battle_lv >= 1, battle_lv >= 2 or battle_danger][i] else 0.0
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
	if lay.has(tname):
		return (lay[tname].players[0] as AudioStreamPlayer).playing
	return not groups[tname].is_empty() and (groups[tname][0] as AudioStreamPlayer).playing


var driven_t := 0.0      # 距离游戏上一次主动选曲的时间


# ---------------------------------------------------------------- 干员语音（Codex 交付 game/audio/voice，README 事件映射）
## 用户定（2026-09-26 第二版）：语音要全（不再按时长筛掉），但**不打断正在播的语音**、整体频率要低。
## 规则：同一时刻只有一条，占线时新语音直接放弃（部署语音排队）；两条之间至少隔 VOICE_GAP 秒；
## 每名干员自己的任意语音之间至少隔 VOICE_OP_GAP 秒；同一句另有冷却（一技能最长，因为它放得最频繁）。缺文件静默跳过。
## 例外（用户 2026-10-12「语音用1」，方案 A）：技能语音（skill_1/2/3）可以打断**正在播的战斗台词**（battle / W 笑声，
## VOICE_CHATTER）——台词 0.1 秒淡出，技能语音立即开播，全队间隔从打断时刻起算。部署语音、技能语音之间仍互不打断，
## 战斗台词不打断任何语音；台词播完后的 VOICE_GAP 静默期里技能语音照旧放弃（只打断「正在说的台词」，不抢间隔）。
const VOICE_MAX_LEN := 8.0             # 只防意外的超长文件；Codex 交付最长 6.4 秒，全部可用
const VOICE_GAP := 3.0                 # 两条语音之间至少间隔（全队）
const VOICE_OP_GAP := 15.0             # 同一名干员两条语音之间至少间隔
const VOICE_CD := {"entry": 0.0, "command": 6.0, "skill_1": 45.0, "skill_2": 30.0, "skill_3": 20.0, "battle": 60.0, "w_laugh": 75.0}
const VOICE_PRIO := {"skill_3": 4, "skill_2": 3, "skill_1": 3, "entry": 2, "command": 1, "battle": 1, "w_laugh": 1}
const VOICE_CHATTER := ["battle", "w_laugh"]   # 可被技能语音打断的战斗台词
const VOICE_CUT_FADE := 0.1            # 被打断的台词淡出秒数
## 响度归一（Codex 交付的各段 RMS 相差约 7 dB）：按各干员实测平均 RMS 拉到 -17 dB 附近（2026-09-26 测量）
## 第五批（10-12 量母带）：能天使平均 -13.2 dB → -4；德克萨斯 -17.7 → +0.5；星熊 / 安洁莉娜 / 浊心 -16.2～-16.4，与斯卡蒂、艾琳同档不调
## 第六批（10-22）：拉普兰德五条标准母带平均 -13.52 dB → -3.5；歌蕾蒂娅 -18.23 dB → +1。
const VOICE_TRIM := {"eyjafjalla": -4.0, "saria": 1.0, "wisadel": 1.0, "logos": 0.5, "exusiai": -4.0, "texas": 0.5, "lappland": -3.5, "gladiia": 1.0}
var voice_player: AudioStreamPlayer
var voice_fader: AudioStreamPlayer     # 被打断的台词换到这里淡出（与 voice_player 轮换）
var voice_fade_tw: Tween
var voice_key := ""                    # 正在播（或刚播完）的事件
var voice_cid := ""
var voice_play_end := 0.0              # 当前这条播完的时刻（不含 VOICE_GAP）
var voice_now := -1.0                  # 测试用时钟（≥ 0 时代替墙钟，test_core.test_voice_interrupt）
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


func _vnow() -> float:
	return voice_now if voice_now >= 0.0 else Time.get_ticks_msec() / 1000.0


## 技能语音能否打断现在这条：只打断正在说的战斗台词（10-12 方案 A）
func voice_can_cut(key: String, now: float) -> bool:
	return key.begins_with("skill") and voice_key in VOICE_CHATTER and now < voice_play_end


## 播一条干员语音；queue = true 时占线则排队（部署语音用），否则直接放弃。
## urgent = true（指挥模式突击 / 归队回应，玩家按键触发，10-23 用户实测「听不到」）：不受同人 15 秒间隔、不受全队静默间隔，
## 能打断正在说的战斗闲聊（同技能语音口径）；只有正在播技能 / 部署 / 指挥语音时才放弃
var voice_urgent: Array = []          # [干员, 事件, 截止时刻]：等当前这条播完立即补播的指挥回应
var voice_log := false                 # --voicelog（测试）：真正开播时打印 VOICEPLAY <干员> <事件>

## 这名干员有没有这条语音素材（指挥喊话缺素材时退到通用音效）
func has_voice(cid: String, key: String) -> bool:
	return _voice_stream(cid, key) != null


func voice(cid: String, key: String, queue := false, urgent := false) -> void:
	var st := _voice_stream(cid, key)
	if st == null:
		return
	var now := _vnow()
	var lk := cid + ":" + key
	if not urgent and now - float(voice_last.get(lk, -999.0)) < float(VOICE_CD.get(key, 8.0)):
		return
	if key != "entry" and not urgent and now - float(voice_op_last.get(cid, -999.0)) < VOICE_OP_GAP:
		return
	var prio: int = VOICE_PRIO.get(key, 1)
	# 占线：不打断（用户要求）；部署语音排队，其余放弃。例外：技能语音打断正在说的战斗台词（10-12）
	var busy: bool = voice_player.playing or now < voice_end
	if urgent:
		busy = voice_player.playing and now < voice_play_end   # 静默间隔里照播
		if busy and (voice_key in VOICE_CHATTER or voice_key == "entry"):
			_voice_fade_out()   # 战斗闲聊 / 部署语音让路给玩家指挥回应
			busy = false
		elif busy:
			voice_urgent = [cid, key, now + 1.5]   # 技能 / 指挥语音正在播：等它播完补播，1.5 秒内没轮到就算了
			return
	if busy and voice_can_cut(key, now):
		_voice_fade_out()
		busy = false
	if busy:
		if voice_log:
			print("VOICESKIP %s %s busy(%s %s)" % [cid, key, voice_cid, voice_key])
		if queue and voice_queue.size() < 4:
			voice_queue.append([cid, key])
		return
	voice_last[lk] = now
	voice_op_last[cid] = now
	voice_prio = prio
	voice_key = key
	voice_cid = cid
	voice_player.stream = st
	voice_player.volume_db = float(VOICE_TRIM.get(cid, 0.0))
	if voice_player.is_inside_tree():   # test_core 里不在场景树中，只验证调度
		voice_player.play()
	voice_play_end = now + st.get_length()
	voice_end = voice_play_end + VOICE_GAP
	if voice_log:
		print("VOICEPLAY %s %s" % [cid, key])


## 把正在播的那条换到 voice_fader 上淡出停掉，voice_player 腾出来给新语音
func _voice_fade_out() -> void:
	if voice_fade_tw != null and voice_fade_tw.is_valid():
		voice_fade_tw.kill()
	voice_fader.stop()
	var p := voice_fader
	voice_fader = voice_player
	voice_player = p
	if voice_fader.playing and is_inside_tree():
		voice_fade_tw = create_tween()
		voice_fade_tw.tween_property(voice_fader, "volume_db", voice_fader.volume_db - 40.0, VOICE_CUT_FADE)
		voice_fade_tw.tween_callback(voice_fader.stop)
	else:
		voice_fader.stop()


func _voice_tick() -> void:
	if not voice_urgent.is_empty() and not voice_player.playing:
		var u: Array = voice_urgent
		voice_urgent = []
		if _vnow() <= float(u[2]):
			voice(u[0], u[1], false, true)
	if voice_queue.is_empty() or voice_player.playing:
		return
	if _vnow() < voice_end:
		return
	var q: Array = voice_queue.pop_front()
	voice_prio = 0
	voice(q[0], q[1], false)


## 场景切换 / 回标题时清空（避免上一局的部署语音串到下一局）
func voice_reset() -> void:
	for lp in loops.values():
		lp.stop()
	voice_queue.clear()
	voice_player.stop()
	if voice_fade_tw != null and voice_fade_tw.is_valid():
		voice_fade_tw.kill()
	voice_fader.stop()
	voice_prio = 0
	voice_key = ""
	voice_play_end = 0.0


func _process(delta: float) -> void:
	_voice_tick()
	music_lp.cutoff_hz = lerp(music_lp.cutoff_hz, cut_target, clamp(delta * 3.0, 0.0, 1.0))
	# 兜底：若游戏场景没有主动选曲（未接入分层逻辑的版本），进入战斗时自动播放战斗曲
	driven_t += delta
	var sc := get_tree().current_scene
	if driven_t > 1.0 and sc != null and sc.get_script() != null and str(sc.get_script().resource_path).ends_with("game.gd") and MENU_TRACKS.has(cur_track):
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
	elif lay.has(cur_track):
		_lay_tick(cur_track)
	for tname in lay:
		var want := 1.0 if tname == cur_track else 0.0
		var rate: Array = group_rate[tname]
		var gv: float = move_toward(group_vol[tname], want, delta * (rate[0] if want > group_vol[tname] else rate[1]))
		group_vol[tname] = gv
		var on: Array = stem_on[tname]
		var sv: Array = stem_vol[tname]
		var pls: Array = lay[tname].players
		for i in pls.size():
			sv[i] = move_toward(sv[i], on[i], delta * (STEM_IN if on[i] > sv[i] else STEM_OUT))
			var pl: AudioStreamPlayer = pls[i]
			if pl.playing:
				var sdb: float = linear_to_db(maxf(gv * sv[i], 0.0001)) + vol_target
				if absf(pl.volume_db - sdb) > 0.0001:
					pl.volume_db = sdb
				if gv <= 0.0:
					pl.stop()
		if gv <= 0.0:
			_maybe_free(tname)
		else:
			_last_on[tname] = now
	for tname in groups:
		var want := 1.0 if tname == cur_track else 0.0
		var rate: Array = group_rate[tname]
		var gv: float = move_toward(group_vol[tname], want, delta * (rate[0] if want > group_vol[tname] else rate[1]))
		group_vol[tname] = gv
		if gv <= 0.0 and MENU_TRACKS.has(tname) and MENU_TRACKS.has(cur_track) and not groups[tname].is_empty() 				and (groups[tname][0] as AudioStreamPlayer).playing:
			menu_pos[tname] = track_pos(tname)   # 局外曲目淡完：记住位置，回到这个界面时接着放
		var gdb: float = linear_to_db(maxf(gv, 0.0001)) + vol_target
		for pl in groups[tname]:
			if absf(pl.volume_db - gdb) > 0.0001:   # 只在变了时设（性能 docs/50 §21：网页样本播放每设一次就是一次 JS 调用，稳态时每帧十几次）；属性按 32 位存，留一点容差
				pl.volume_db = gdb
			if gv <= 0.0 and pl.playing:
				pl.stop()
		if gv <= 0.0:
			_maybe_free(tname)
		else:
			_last_on[tname] = _now()
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
					var sdb: float = linear_to_db(maxf(gv * sv[i], 0.0001)) + vol_target
					if absf(pl.volume_db - sdb) > 0.0001:   # 同上
						pl.volume_db = sdb
					if gv <= 0.0:
						pl.stop()
		if gv <= 0.0:
			_maybe_free(tname)
		else:
			_last_on[tname] = _now()
	if stinger.playing:
		if absf(stinger.volume_db - (vol_target + 4.0)) > 0.0001:
			stinger.volume_db = vol_target + 4.0
	elif after_stinger != "":
		# 结算短乐句播完：接续对应的循环（胜利变奏 / 沉底氛围）
		var nxt := after_stinger
		after_stinger = ""
		play_music(nxt)


## 网页切曲释放（docs/50 §40）：引擎把每段配乐整段解码成样本、脚本没有注销接口，播过的曲子会一直占着（48 kHz 时 15 秒一句 5.5 MB）。
## 发布包 / 测量副本给引擎 JS 打了 window.__syAudioFree（tools/web/engine_patch.py）：一首曲子完全淡出、不是当前也不是下一首时，
## 把它所有句 / 层的样本按流的 instance id 释放；再播时引擎重新解码注册。局外也释放，保留 menu_pos 供返回时续播。
## 当前、待播、预热中的曲目不释放，JS 还会保护仍在播放或暂停的样本。不是网页或没打补丁时什么也不做。
var _freed := {}
var _next := {}
var _free_ok := -1


## 仅旧乐句曲预解码下一段；整首分层曲只在载入页预热第一首，避免提前驻留两三首完整 PCM。
func _queue_next(tname: String) -> void:
	if tname == "opening" and _next.has("battle1"):
		return   # 第一首已在载入页预热，开场引子期间继续保留
	for old in _next:
		for st in _track_streams(old):
			_warm_q.erase(st)   # 换曲 / 退出后，取消尚未执行的旧音乐预热，音效队列保留
	_next.clear()
	if not OS.has_feature("web") or not tname.begins_with("battle") or lay.has(tname):
		return
	var k := int(tname.substr(6))
	var nxt: Array = ["boss"]
	if seq.has("battle%d" % (k + 1)):
		nxt.push_front("battle%d" % (k + 1))
	if k >= 3:
		nxt.append("final")
	for t2 in nxt:
		if not seq.has(t2):
			continue
		var q = seq[t2]
		for sname in q.segs:
			for st in q.segs[sname]:
				if st is AudioStream and not AudioServer.is_stream_registered_as_sample(st) and not _warm_q.has(st):
					_warm_q.append(st)
		if q.danger is AudioStream and not _warm_q.has(q.danger) and not AudioServer.is_stream_registered_as_sample(q.danger):
			_warm_q.append(q.danger)
		_freed.erase(t2)
		_next[t2] = true   # 提前解码的曲目不被「切曲释放」放掉（直到下一首战斗乐开播重排）


func warm_pending() -> bool:
	return not _warm_q.is_empty()

var _last_on := {}   # 曲目最后一次是当前曲目的时刻（墙钟）：离开满 FREE_AFTER 秒才放，刚点播还没开起来的不放
const FREE_AFTER := 3.0

## 三种音乐容器共用的流清单：预热、释放与内存统计必须覆盖同一批资源。
func _track_streams(tname: String) -> Array:
	var sts: Array = []
	if lay.has(tname):
		for pl in lay[tname].players:
			sts.append(pl.stream)
	elif seq.has(tname):
		for sname in seq[tname].segs:
			sts.append_array(seq[tname].segs[sname])
		if seq[tname].danger is AudioStream:
			sts.append(seq[tname].danger)
	elif groups.has(tname):
		for pl in groups[tname]:
			sts.append(pl.stream)
	return sts

func _maybe_free(tname: String) -> void:
	if tname == cur_track or tname == str(pending.get("track", "")):
		_last_on[tname] = _now()
		return
	if _freed.has(tname) or _next.has(tname) or tname == after_stinger or cur_track == "" or _now() - float(_last_on.get(tname, -99.0)) < FREE_AFTER:
		return
	if _free_ok < 0:
		_free_ok = 1 if OS.has_feature("web") and str(JavaScriptBridge.eval("typeof window.__syAudioFree", true)) == "function" else 0
	if _free_ok == 0:
		return
	var sts: Array = _track_streams(tname)
	var released := true
	var n := 0
	for st in sts:
		if st is AudioStream and AudioServer.is_stream_registered_as_sample(st):
			var result = JavaScriptBridge.eval("window.__syAudioFree('%d')" % st.get_instance_id(), true)
			if result != null and not bool(result):   # JS Boolean 经 eval 返回 int 0 / 1
				released = false   # 尚有播放引用：下一帧重试，不能提前标记已释放
			else:
				n += 1
	if released:
		_freed[tname] = true
	if n > 0 and not (OS.get_cmdline_user_args() if OS.is_debug_build() else PackedStringArray()).is_empty():
		print("PF AUDIOFREE track=%s n=%d mb=%s" % [tname, n, str(JavaScriptBridge.eval("window.__syAudioMB?window.__syAudioMB().toFixed(1):-1", true))])


func toggle_music() -> bool:
	music_muted = not music_muted
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), music_muted)
	return music_muted


## Boss 大招固定音效（docs/38 §8.11，tools/gen_sfx_cues.py）：同一类招式同一组音，听音就知道怎么躲；
## 起手音上再叠这只 Boss 的专属音色。CUE_VOL 把各文件拉到同一实际电平（外放口径）：起手 / 命中约 -18、专属层 -22、
## 光束改用中低频脉冲，最响 100 ms 约 -24（起手）/ -23（命中），给配乐留空间。
## 全场警报最响（-11）。类别可用中文或英文键；缺文件时 play() 本来就静默
const CUE_CAT := {"落地": "land", "冲锋": "charge", "光束": "beam", "近身": "melee", "全场": "global", "阶段": "phase"}
const CUE_VOL := {"boss_archon": -10.2, "boss_bishop": -11.0, "boss_carmen": -11.5, "boss_iberia": -11.5, "boss_immortal": -11.2, "boss_ishar": -5.1, "boss_izumik": -6.1, "boss_knight_boss": -7.9, "boss_paranoia": -7.5, "boss_path": -7.1, "cue_beam_hit": -4.1, "cue_beam_start": -8.6, "cue_charge_hit": -0.6, "cue_charge_start": -3.6, "cue_global_hit": -1.8, "cue_global_start": -6.5, "cue_land_hit": -2.0, "cue_land_start": -1.3, "cue_melee_hit": 0.9, "cue_melee_start": -2.6, "cue_phase_start": -3.1}


func play_cue(cat: String, boss: String, stage := "start") -> void:
	var c: String = CUE_CAT.get(cat, cat)
	var n := "cue_%s_%s" % [c, stage]
	play(n, float(CUE_VOL.get(n, -18.0)), 1.0, 0.03)
	if stage == "start":
		var b := "boss_" + boss
		play(b, float(CUE_VOL.get(b, -22.0)), 1.0, 0.0)


## 手动操作的音量（tools/gen_sfx_events.py；外放口径）：蓄距离循环 -24、释放 -17、被闸门拦住的「咔」-28
const ULP_LOOP_DB := -18.0
const ULP_RELEASE_DB := -2.1
const ATK_GATE_DB := -10.6

## 循环音效（乌尔比安 S3 手动蓄距离等）：loop_start 开始（已在播只改音量 / 音高），loop_pitch 每帧改音高，loop_stop 停。
## 各名字一个独立播放器，不占一次性音效的 32 个；新一局（voice_reset）时全部停掉
var loops := {}


func loop_start(name: String, vol := 0.0, pitch := 1.0) -> void:
	if streams.get(name) == null:
		return
	var p: AudioStreamPlayer = loops.get(name)
	if p == null:
		p = AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		var st: AudioStream = streams[name]
		if st is AudioStreamWAV:
			st = st.duplicate()
			st.loop_mode = AudioStreamWAV.LOOP_FORWARD
			st.loop_begin = 0
			st.loop_end = int(st.get_length() * st.mix_rate)
		p.stream = st
		loops[name] = p
	p.volume_db = vol
	p.pitch_scale = clampf(pitch, 0.25, 4.0)
	if not p.playing:
		p.play()


func loop_pitch(name: String, pitch: float) -> void:
	var p: AudioStreamPlayer = loops.get(name)
	if p != null:
		p.pitch_scale = clampf(pitch, 0.25, 4.0)


func loop_stop(name: String) -> void:
	var p: AudioStreamPlayer = loops.get(name)
	if p != null:
		p.stop()


## ---- 混音优先级（协调人 9/30：后期 200+ 敌人时同时发声会糊）
## 一次性音效共 32 个播放器。同名音 MERGE_T 秒内合并（取 LIMIT 与它的较大者）；满槽时抢占正在播的最低优先级音，
## 自己优先级不高于它就丢弃；已有 DUCK_AT 个在响时，优先级 ≤2 的音降 6 dB。统计计数给 --perf 测量用（sfx_stat）
const MERGE_T := 0.05
const LOW_CAP := 16   # 低画质档（Cfg.quality == "low"）：同时发声上限 16，拥挤时优先级 ≤2 直接丢弃而不是降音量
const DUCK_AT := 12   # 标准局 99% 的帧 ≤15 个同时发声：只在最密的几成帧里压低优先级 ≤2 的音
## 5 Boss 大招 / 阶段 / Boss 事件；4 主控状态与操作反馈；3 灯标、技能发动；2 一般攻击 / 敌人（缺省）；1 拾取、击杀、命中
const PRIO_NAME := {
	"lamp_out": 5, "roar": 5, "hunt_warn": 5, "hunt_close": 5, "hunt_break": 4, "izu_wave_count": 5, "cocoon_form": 5, "shell_break": 5,
	"cocoon_revive": 5, "izu_lamp_lit": 5, "izu_absorb": 5, "stake_hit": 5, "stake_shatter": 4, "carmen_sword": 5, "ishar_land_break": 5, "paranoia_land_break": 5, "bishop_panic": 5, "knight_frost": 4,
	"nerve_burst": 4, "apop_pause": 4, "apop_resume": 4, "hurt": 4, "dodge": 4, "levelup": 4, "relic": 4, "heartbeat": 4, "ulp_release": 4,
	"atk_gate": 4, "ui_move": 4, "ui_ok": 4, "start": 4, "skill": 3, "hurt_heavy": 4, "kill_big": 3, "kill_shell": 3,
	"beacon_tick": 3, "beacon_lit": 3, "beacon_end": 3, "beacon_fizzle": 3, "mire_clear": 3, "crit_tick": 3, "break_hit": 3, "break_open": 5, "lamp_empty": 4, "heartbeat_hi": 4,
	"pickup": 1, "kill": 1, "hit": 1,
	# Repeated gunfire yields to telegraphs and can be attenuated in a dense mix.
	"op_exusiai_atk": 2, "op_exusiai_atk_b": 2, "op_exusiai_atk_c": 2, "op_exusiai_hit": 1,
}
## ---- 连发节流（用户 10-13「冲锋的音效触发太频繁了有点吵闹」）：在 LIMIT（同名最短间隔）之外再加两道旋钮——
## VOICE_CAP：同名音同时在响的上限（到上限就丢弃这次，不抢占）；带位置的音（play_at）按离画面多远降音量：
## 画面内照常，出画面边缘后 OFF_FADE 像素内线性降到 −OFF_DB，再远（> OFF_FADE）不播。view 由 music_director 每帧写（空 = 不按距离处理）
## 实测（安洁莉娜 + 德克萨斯 + 推进之王，8–12 分钟）：用户说的「冲锋」是推进之王 S1「冲锋号令」的发动音 op_siege_s1——
## 技能类音量（OP_VOL s1 = −4 dB），S1 回技力快，每秒 0.4–0.53 次（约 2 秒一下）；敌方冲锋预警 cue_charge_* 只在 Boss 战 0.03–0.13 次 / 秒，
## 骑士 knight_charge 没出现。节流：冲锋号令全局至少隔 SIEGE_S1_GAP 秒（技能照常放，只是不每次都响），同名音同时只响 1 个；
## 冲锋类预警同时最多 1 个；骑士冲锋按位置降音量（world.gd 用 play_at）
const SIEGE_S1_GAP := 4.5
const VOICE_CAP := {"op_siege_s1": 1, "cue_charge_start": 1, "cue_charge_hit": 1, "knight_charge": 2,
	"cue_beam_start": 1, "cue_beam_hit": 1, # 后续轮次重启同名音，起手与命中各保留一个
	"op_wisadel_quake": 2, "op_wisadel_hit": 3, "op_wisadel_big": 2, "op_kaltsit_big": 2, "op_eyjafjalla_big": 3,
	"exusiai_gun": 2, "exusiai_burst": 1, "op_exusiai_hit": 1}
const OFF_FADE := 480.0
const OFF_DB := 12.0
var view := Rect2()

func voice_group(name: String) -> String:
	if name in ["op_exusiai_atk", "op_exusiai_atk_b", "op_exusiai_atk_c"]:
		return "exusiai_gun"
	if name in ["op_exusiai_s1", "op_exusiai_s2", "op_exusiai_s3", "op_exusiai_big"]:
		return "exusiai_burst"
	return name


## 带世界坐标的音效：离画面越远越轻，太远不播（见 OFF_FADE / OFF_DB）
func play_at(name: String, pos: Vector2, vol := 0.0, pitch := 1.0, pitch_var := 0.08) -> void:
	if view.has_area() and not view.has_point(pos):
		var q: Vector2 = pos.clamp(view.position, view.end)
		var d: float = pos.distance_to(q)
		if d > OFF_FADE:
			_by(name, 0)
			_by(name, 3)
			return
		vol -= OFF_DB * d / OFF_FADE
	play(name, vol, pitch, pitch_var)


var sfx_stat := {"plays": 0, "merged": 0, "dropped": 0, "stolen": 0, "ducked": 0, "voices_max": 0, "us": 0}
## --sfxstat（仅测试，Cfg.dev_args）：按音名计数 [请求, 实播, 同名合并, 满槽丢弃, 降音量]；--perf 结束时按类别汇总打印（run/autotest.gd）
var sfx_by := {}
var sfx_by_on := -1   # -1 = 还没读开关


func _by(name: String, idx: int) -> void:
	if sfx_by_on < 0:
		var cfg: Node = get_node_or_null("/root/Cfg")
		sfx_by_on = 1 if (cfg != null and cfg.dev_args().has("--sfxstat")) else 0
	if sfx_by_on == 0:
		return
	if not sfx_by.has(name):
		sfx_by[name] = [0, 0, 0, 0, 0]
	sfx_by[name][idx] += 1


func sfx_prio(name: String) -> int:
	if PRIO_NAME.has(name):
		return PRIO_NAME[name]
	if name.begins_with("cue_") or name.begins_with("boss_"):
		return 5
	if name.begins_with("op_"):
		return 3 if (name.ends_with("_s1") or name.ends_with("_s2") or name.ends_with("_s3") or name.ends_with("_big")) else 2
	return 2


## 寻访 / 十连音效（tools/gen_hh_sfx.py 程序合成，10-26）：不进开局预载表，第一次打开寻访时才读（网页包按需、不预解码）
const HH_SFX := ["hh_drop", "hh_zip", "hh_hum", "hh_burst", "hh_star6", "hh_reveal", "hh_card", "hh_done"]
## 录屏配音用（测试局主线照样静音）：trace_on 时把每次真正放出的音效记成 [渲染帧号, 名字, 音量 dB, 音高]，
## 录屏脚本按记录离线混音再合进视频（tools/probes/first_tenpull_rec.py）；不改变任何播放行为
var trace_on := false
var trace: Array = []


func ensure(names: Array) -> void:
	for n in names:
		if not streams.has(n):
			streams[n] = _load_wav("res://audio/sfx/%s.wav" % n)


func play(name: String, vol := 0.0, pitch := 1.0, pitch_var := 0.08) -> void:
	if not streams.has(name) and name.begins_with("hh_"):
		ensure([name])
	if not streams.has(name) or streams[name] == null:
		if ALT.has(name) and streams.get(ALT[name][0]) != null:   # 缺文件：借近似音（docs/53）
			var alt: Array = ALT[name]
			play(alt[0], vol + float(alt[2]), pitch * float(alt[1]), pitch_var)
		return
	var t0 := Time.get_ticks_usec()
	var now := t0 / 1000000.0
	_by(name, 0)
	var lim: float = maxf(MERGE_T, float(LIMIT.get(name, op_limit.get(name, 0.0))))
	if now - float(last.get(name, -1.0)) < lim:
		sfx_stat.merged += 1
		_by(name, 2)
		return
	# 同轮已在 MERGE_T 内合并；新一轮替换旧尾音，不能因上一轮仍在响而吞掉。
	if name in ["cue_beam_start", "cue_beam_hit"]:
		for c in players:
			if c.playing and c.get_meta("sname", "") == name:
				c.stop()
	var prio := sfx_prio(name)
	var cfg: Node = get_node_or_null("/root/Cfg")
	var low: bool = cfg != null and str(cfg.get("quality")) == "low"
	var busy := 0
	var p: AudioStreamPlayer = null
	var lowest: AudioStreamPlayer = null
	var low_prio := 99
	var same := 0
	var group := voice_group(name)
	var burst_playing := false
	for i in players.size():
		var c: AudioStreamPlayer = players[(next + i) % players.size()]
		if not c.playing:
			if p == null:
				p = c
				next = (next + i + 1) % players.size()
			continue
		busy += 1
		var cg := voice_group(str(c.get_meta("sname", "")))
		if cg == "exusiai_burst":
			burst_playing = true
		if cg == group:
			same += 1
		var cp: int = c.get_meta("prio", 2)
		if cp < low_prio:
			low_prio = cp
			lowest = c
	if VOICE_CAP.has(group) and same >= int(VOICE_CAP[group]):
		sfx_stat.dropped += 1
		_by(name, 3)
		return
	if low and busy >= LOW_CAP:
		p = null   # 低画质：按 16 个算满槽
	if low and busy >= DUCK_AT and prio <= 2:
		sfx_stat.dropped += 1
		_by(name, 3)
		return
	if p == null:
		if lowest == null or low_prio >= prio:   # 满槽且没有比自己低的：丢弃
			sfx_stat.dropped += 1
			_by(name, 3)
			return
		p = lowest
		p.stop()
		sfx_stat.stolen += 1
		busy -= 1
	last[name] = now
	if group == "exusiai_gun" and burst_playing:
		vol -= 5.0 # Skill recordings already contain gunfire; avoid doubling every shot.
	if busy >= DUCK_AT and prio <= 2:
		vol -= 6.0
		sfx_stat.ducked += 1
		_by(name, 4)
	p.stream = streams[name]
	p.volume_db = vol
	p.pitch_scale = pitch * prng.randf_range(1.0 - pitch_var, 1.0 + pitch_var)
	p.set_meta("prio", prio)
	p.set_meta("sname", name)
	p.play()
	if trace_on:
		trace.append([Engine.get_process_frames(), name, p.volume_db, p.pitch_scale])
	sfx_stat.plays += 1
	_by(name, 1)
	sfx_stat.voices_max = maxi(int(sfx_stat.voices_max), busy + 1)
	sfx_stat.us += Time.get_ticks_usec() - t0


## 干员音效：op("skadi", "atk")；vol 为相对该类别默认音量的偏移。没有专属文件时退回通用音效
func op(oid: String, kind: String, vol := 0.0, pitch := 1.0, pitch_var := 0.05) -> void:
	var sn := "op_%s_%s" % [oid, kind]
	if OP_GAP.has(sn):
		var now := Time.get_ticks_usec() / 1000000.0
		if now - float(op_last.get(sn, -99.0)) < float(OP_GAP[sn]):
			sfx_stat.merged += 1
			return
		op_last[sn] = now
	var v: float = float(OP_VOL.get(kind, -8.0)) + vol + float(OP_DB.get(sn, 0.0))
	pitch_var = maxf(pitch_var, float(OP_PVAR.get(sn, 0.0)))
	var pn := sn
	if OP_ROT.has(sn) and streams.get(OP_ROT[sn][0]) != null:
		var vs: Array = OP_ROT[sn]
		var k: int = int(op_rot.get(sn, 0))
		op_rot[sn] = k + 1
		k %= vs.size() + 1
		pn = sn if k == 0 else str(vs[k - 1])
	if streams.get(pn) != null:
		_op_log(sn, pn, v, pitch, pitch_var)
		play(pn, v, pitch, pitch_var)
	elif OP_ALT.has(sn) and streams.get(OP_ALT[sn][0]) != null:
		var alt: Array = OP_ALT[sn]
		_op_log(sn, alt[0], v + float(alt[2]), pitch * float(alt[1]), pitch_var)
		play(alt[0], v + float(alt[2]), pitch * float(alt[1]), pitch_var)
	elif OP_FALLBACK.has(kind):
		_op_log(sn, OP_FALLBACK[kind], v, pitch, pitch_var)
		play(OP_FALLBACK[kind], v, pitch, pitch_var)


## --sfxstat：干员动作 -> 实际文件、音量、音高（docs/113 音效盘点用）。sfx_op[op_<id>_<类别>] = {n, file, v0, v1, vsum, p0, p1, var}
var sfx_op := {}


func _op_log(sn: String, file: String, v: float, p: float, pv: float) -> void:
	if sfx_by_on < 0:
		var cfg: Node = get_node_or_null("/root/Cfg")
		sfx_by_on = 1 if (cfg != null and cfg.dev_args().has("--sfxstat")) else 0
	if sfx_by_on != 1:
		return
	var r: Dictionary = sfx_op.get(sn, {"n": 0, "file": {}, "v0": 99.0, "v1": -99.0, "vsum": 0.0, "p0": 99.0, "p1": 0.0, "var": pv})
	r.n += 1
	r.file[file] = int(r.file.get(file, 0)) + 1
	r.v0 = minf(r.v0, v)
	r.v1 = maxf(r.v1, v)
	r.vsum += v
	r.p0 = minf(r.p0, p)
	r.p1 = maxf(r.p1, p)
	r["var"] = maxf(float(r["var"]), pv)
	sfx_op[sn] = r


## 重击闷音（combat.hurt，docs/53）：配乐低通立刻压到 hz，之后由 cut_target（music_director 每帧设）按 _process 的速率回升
func duck_music(hz: float) -> void:
	if music_lp != null:
		music_lp.cutoff_hz = minf(music_lp.cutoff_hz, hz)


## Enemy attack cues: distance attenuation and shared per-kind throttling.
## Called once when the attack begins, never per animation frame.
func enemy(kind: String, distance := 0.0) -> void:
	if kind not in ["screech", "spit", "bite", "nerve", "acid", "elite"] or distance > 800.0:
		return
	var attenuation := clampf(distance / 800.0, 0.0, 1.0) * 18.0
	play("enemy_" + kind, -13.0 - attenuation, 1.0, 0.07)


## --audiofree（仅测试，网页，docs/50 §40）：量网页样本解码后的实际字节、以及丢掉流 / 播放器后样本是否真释放。
## 要配合 tools/probes/audio_web.py（测量副本里把引擎的 GodotAudio.samples 挂到 window.__GAS 才读得到）
func _js_samples() -> String:
	var r = JavaScriptBridge.eval("(()=>{const m=window.__GAS;if(!m)return 'nomap';let n=0,live=0,b=0;for(const [k,s] of m){n++;const a=s._audioBuffer;if(a){live++;b+=a.length*a.numberOfChannels*4;}}return n+' live='+live+' MB='+(b/1048576).toFixed(1)+' sr='+(window.__GACTX?window.__GACTX.sampleRate:0);})()", true)
	return str(r)


func _audio_free_test() -> void:
	await get_tree().create_timer(2.0).timeout
	print("PF AUDIOFREE start " + _js_samples())
	var path := "res://audio/music/battle1_A_base.ogg"
	var st: AudioStream = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	print("PF AUDIOFREE len=%.2fs" % st.get_length())
	AudioServer.register_stream_as_sample(st)
	await get_tree().create_timer(1.0).timeout
	print("PF AUDIOFREE registered " + _js_samples())
	var pl := AudioStreamPlayer.new()
	pl.stream = st
	pl.bus = "Music"
	add_child(pl)
	pl.play()
	await get_tree().create_timer(2.0).timeout
	print("PF AUDIOFREE playing " + _js_samples())
	pl.stop()
	pl.queue_free()
	pl = null
	await get_tree().create_timer(1.0).timeout
	print("PF AUDIOFREE player_freed " + _js_samples())
	print("PF AUDIOFREE ids keys=%s mine=%d" % [str(JavaScriptBridge.eval("Array.from(window.__GAS.keys()).join(',')", true)), st.get_instance_id()])
	JavaScriptBridge.eval("(()=>{const s=window.__GAS.get('%d');if(s)s.clear();})()" % st.get_instance_id(), true)
	await get_tree().create_timer(1.0).timeout
	print("PF AUDIOFREE js_cleared %s registered=%s" % [_js_samples(), str(AudioServer.is_stream_registered_as_sample(st))])
	AudioServer.register_stream_as_sample(st)
	var pl2 := AudioStreamPlayer.new()
	pl2.stream = st
	pl2.bus = "Music"
	add_child(pl2)
	pl2.play()
	await get_tree().create_timer(1.5).timeout
	print("PF AUDIOFREE reregistered_playing %s playing=%s pos=%.2f" % [_js_samples(), str(pl2.playing), pl2.get_playback_position()])
	pl2.queue_free()
	st = null
	await get_tree().create_timer(2.0).timeout
	print("PF AUDIOFREE stream_dropped " + _js_samples())
	# 再试：一次读 15 句底层、全注册，再全部丢掉
	var arr: Array = []
	for sname in ["A", "B", "C", "D", "E"]:
		for layer in ["base", "pulse", "drive"]:
			var s2: AudioStream = ResourceLoader.load("res://audio/music/battle2_%s_%s.ogg" % [sname, layer], "", ResourceLoader.CACHE_MODE_IGNORE)
			if s2 != null:
				AudioServer.register_stream_as_sample(s2)
				arr.append(s2)
	await get_tree().create_timer(2.0).timeout
	print("PF AUDIOFREE battle2_all_registered n=%d %s" % [arr.size(), _js_samples()])
	arr.clear()
	await get_tree().create_timer(2.0).timeout
	print("PF AUDIOFREE battle2_dropped " + _js_samples())
	print("PF FTDONE")


## --musictour（仅测试，网页，docs/50 §40）：停在标题页，按 标题 → 战斗一 → 中期 Boss → 战斗二 → 战斗三 → 最终 Boss → 标题 依次切曲，
## 战斗强度拉满（各层都响），每 5 秒打一行 PF AUDIOMEM（引擎样本表实际 MB），看切曲释放后音频内存的曲线
func _music_tour() -> void:
	var plan := [["title", 8.0], ["battle1", 40.0], ["boss", 35.0], ["battle2", 40.0], ["battle3", 40.0], ["final", 45.0], ["title", 12.0]]
	var t0 := _now()
	for st in plan:
		battle_lv = 2
		play_music(str(st[0]))
		var end := _now() + float(st[1])
		while _now() < end:
			await get_tree().create_timer(5.0).timeout
			print("PF AUDIOMEM t=%.0f want=%s cur=%s mb=%.1f" % [_now() - t0, str(st[0]), cur_track, sample_mem_mb()])
	print("PF FTDONE")
