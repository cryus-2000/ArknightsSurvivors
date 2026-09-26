extends Node
## 全局设置（自动加载为 Cfg），保存在 user://settings.cfg

const PATH := "user://settings.cfg"
const D = preload("res://scripts/data.gd")
## 存档里难度字段的含义：1 = 旧版累计档位 0–10；2 = 1.1 起的难度档下标（D.DIFFICULTY_TIERS）
const DIFF_VER := 2

var master := 1.0
var music := 0.8
var sfx := 0.9
var voice := 0.8        # 干员语音（Voice 总线）
var fullscreen := false
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]   # 都是 1280×720 的整数倍，像素对齐
var res_index := 0        # 窗口分辨率（RESOLUTIONS 下标；全屏时按屏幕）
var dmg_numbers := true
var shake := 1.0          # 0 / 0.5 / 1
var hitstop := true
var outline := true      # 怪物轮廓光
var dof := true          # 2.5D 景深与前景
var bloom := true        # 辉光
var water_filter := true # 水下滤镜：色差 + 暗角 + 焦散
var normal_maps := true  # 2D 法线光照（贴图加载时生成，改动下局生效）
var brightness := 1.1    # 画面亮度 0.8 ~ 1.4
var pad_rumble := true   # 手柄震动
var difficulty := 0      # 本局难度档（D.DIFFICULTY_TIERS 下标）
var character_id := "mizuki"  # 本局角色（data/characters/<id>.json）
var map_id := "deep_sea"  # 本局地图主题（data/maps/<id>.json）
var diff_unlocked := 0   # 已解锁的最高难度档（D.DIFFICULTY_TIERS 下标）
var seen_shows: Array = []   # 已看过的解锁演出
var seen_relics: Array = []  # 获得过的藏品 id（图鉴用）
var seen_intro := false      # 已看过开局指南
var endings_cleared: Array = []   # 已达成的结局 id（通关结局一后才出现其余结局的事件）
var title_seen := false      # 本次运行已播过标题开场动画（仅内存，不存档；对局返回标题不重播）


func _ready() -> void:
	# 触屏设备：整体放大 1.15（逻辑分辨率 1113×626），字和按钮在手机上更好点；各面板按 vs.y < 680 做紧凑排版
	if DisplayServer.is_touchscreen_available() or OS.has_feature("web_android") or OS.has_feature("web_ios") or OS.get_cmdline_user_args().has("--touch"):
		get_tree().root.content_scale_factor = 1.15
	# 网页版 / 移动端：默认关掉最吃性能的后期（玩家仍可在设置里打开）
	if OS.has_feature("web"):
		bloom = false
		water_filter = false
		normal_maps = false
		dof = DisplayServer.is_touchscreen_available() == false
	var c := ConfigFile.new()
	if c.load(PATH) == OK:
		master = c.get_value("audio", "master", master)
		music = c.get_value("audio", "music", music)
		sfx = c.get_value("audio", "sfx", sfx)
		voice = c.get_value("audio", "voice", voice)
		fullscreen = c.get_value("video", "fullscreen", fullscreen)
		res_index = clampi(int(c.get_value("video", "res_index", res_index)), 0, RESOLUTIONS.size() - 1)
		dmg_numbers = c.get_value("game", "dmg_numbers", dmg_numbers)
		shake = c.get_value("game", "shake", shake)
		hitstop = c.get_value("game", "hitstop", hitstop)
		outline = c.get_value("game", "outline", outline)
		dof = c.get_value("video", "dof", dof)
		bloom = c.get_value("video", "bloom", bloom)
		water_filter = c.get_value("video", "water_filter", water_filter)
		normal_maps = c.get_value("video", "normal_maps", normal_maps)
		brightness = clampf(float(c.get_value("video", "brightness", brightness)), 0.8, 1.4)
		pad_rumble = c.get_value("input", "pad_rumble", pad_rumble)
		difficulty = c.get_value("progress", "difficulty", difficulty)
		diff_unlocked = c.get_value("progress", "diff_unlocked", diff_unlocked)
		seen_shows = c.get_value("progress", "seen_shows", seen_shows)
		seen_relics = c.get_value("progress", "seen_relics", seen_relics)
		seen_intro = c.get_value("progress", "seen_intro", seen_intro)
		endings_cleared = c.get_value("progress", "endings_cleared", endings_cleared)
		if int(c.get_value("progress", "diff_ver", 1)) < DIFF_VER:
			_migrate_diff()
	apply.call_deferred()


func apply() -> void:
	_bus("Master", master)
	_bus("Music", music)
	_bus("SFX", sfx)
	_bus("Voice", voice)
	if DisplayServer.get_name() != "headless":
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want:
			DisplayServer.window_set_mode(want)
		if not fullscreen:
			var sz: Vector2i = RESOLUTIONS[clampi(res_index, 0, RESOLUTIONS.size() - 1)]
			var scr: Vector2i = DisplayServer.screen_get_size()
			# 比屏幕还大的档位就退到能放下的最大一档
			while (sz.x > scr.x or sz.y > scr.y) and res_index > 0:
				res_index -= 1
				sz = RESOLUTIONS[res_index]
			if DisplayServer.window_get_size() != sz:
				DisplayServer.window_set_size(sz)
				DisplayServer.window_set_position((scr - sz) / 2 + DisplayServer.screen_get_position())


func _bus(name: String, v: float) -> void:
	var b := AudioServer.get_bus_index(name)
	if b != -1:
		AudioServer.set_bus_volume_db(b, linear_to_db(max(v, 0.0001)))


## 旧存档（11 级累计难度）→ 3 档：通关过某档对应的累计档位（旧 diff_unlocked = 通关的最高档 + 1）就解锁下一档，
## 只多不少——例如旧存档解锁到 5（通关过 4 = 困难的档位）→ 解锁「极难」；只解锁到 1–4（通关过标准）→ 解锁「困难」。
## 上次选的难度落到它所在的档，且不超过已解锁的档
func _migrate_diff() -> void:
	var old_unlocked := diff_unlocked
	var old_diff := difficulty
	diff_unlocked = 0
	for i in range(1, D.DIFFICULTY_TIERS.size()):
		if old_unlocked >= int(D.DIFFICULTY_TIERS[i - 1].level) + 1:
			diff_unlocked = i
	difficulty = mini(D.tier_of_level(old_diff), diff_unlocked)


## 开发用参数（--allend / --allrelics 这类解锁开关）：只在 debug 构建（编辑器、测试、debug 导出）里读命令行；
## 发布版（--export-release）一律返回空，玩家首次打开一定是未解锁的初始状态（tools/check_release.py 检查）
func dev_args() -> PackedStringArray:
	return OS.get_cmdline_user_args() if OS.is_debug_build() else PackedStringArray()


func save() -> void:
	# 自动测试（任何 --xxx 启动参数，与 sfx.gd 静音同一判定）不写玩家的存档：
	# 否则批跑 / 冒烟里机器人拿到的藏品、解锁的难度都会记进玩家的图鉴与进度（docs/36）
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			return
	var c := ConfigFile.new()
	c.set_value("audio", "master", master)
	c.set_value("audio", "music", music)
	c.set_value("audio", "sfx", sfx)
	c.set_value("audio", "voice", voice)
	c.set_value("video", "fullscreen", fullscreen)
	c.set_value("video", "res_index", res_index)
	c.set_value("game", "dmg_numbers", dmg_numbers)
	c.set_value("game", "shake", shake)
	c.set_value("game", "hitstop", hitstop)
	c.set_value("game", "outline", outline)
	c.set_value("video", "dof", dof)
	c.set_value("video", "bloom", bloom)
	c.set_value("video", "water_filter", water_filter)
	c.set_value("video", "normal_maps", normal_maps)
	c.set_value("video", "brightness", brightness)
	c.set_value("input", "pad_rumble", pad_rumble)
	c.set_value("progress", "difficulty", difficulty)
	c.set_value("progress", "diff_unlocked", diff_unlocked)
	c.set_value("progress", "diff_ver", DIFF_VER)
	c.set_value("progress", "seen_shows", seen_shows)
	c.set_value("progress", "seen_relics", seen_relics)
	c.set_value("progress", "seen_intro", seen_intro)
	c.set_value("progress", "endings_cleared", endings_cleared)
	c.save(PATH)
