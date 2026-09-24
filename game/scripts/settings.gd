extends Node
## 全局设置（自动加载为 Cfg），保存在 user://settings.cfg

const PATH := "user://settings.cfg"

var master := 1.0
var music := 0.8
var sfx := 0.9
var fullscreen := false
var dmg_numbers := true
var shake := 1.0          # 0 / 0.5 / 1
var hitstop := true
var outline := true      # 怪物轮廓光
var dof := true          # 2.5D 景深与前景
var difficulty := 0      # 本局难度
var character_id := "mizuki"  # 本局角色（data/characters/<id>.json）
var map_id := "deep_sea"  # 本局地图主题（data/maps/<id>.json）
var diff_unlocked := 0   # 已解锁的最高难度
var seen_shows: Array = []   # 已看过的解锁演出
var seen_relics: Array = []  # 获得过的藏品 id（图鉴用）
var seen_intro := false      # 已看过开局指南


func _ready() -> void:
	var c := ConfigFile.new()
	if c.load(PATH) == OK:
		master = c.get_value("audio", "master", master)
		music = c.get_value("audio", "music", music)
		sfx = c.get_value("audio", "sfx", sfx)
		fullscreen = c.get_value("video", "fullscreen", fullscreen)
		dmg_numbers = c.get_value("game", "dmg_numbers", dmg_numbers)
		shake = c.get_value("game", "shake", shake)
		hitstop = c.get_value("game", "hitstop", hitstop)
		outline = c.get_value("game", "outline", outline)
		dof = c.get_value("video", "dof", dof)
		difficulty = c.get_value("progress", "difficulty", difficulty)
		diff_unlocked = c.get_value("progress", "diff_unlocked", diff_unlocked)
		seen_shows = c.get_value("progress", "seen_shows", seen_shows)
		seen_relics = c.get_value("progress", "seen_relics", seen_relics)
		seen_intro = c.get_value("progress", "seen_intro", seen_intro)
	apply.call_deferred()


func apply() -> void:
	_bus("Master", master)
	_bus("Music", music)
	_bus("SFX", sfx)
	if DisplayServer.get_name() != "headless":
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want:
			DisplayServer.window_set_mode(want)


func _bus(name: String, v: float) -> void:
	var b := AudioServer.get_bus_index(name)
	if b != -1:
		AudioServer.set_bus_volume_db(b, linear_to_db(max(v, 0.0001)))


func save() -> void:
	var c := ConfigFile.new()
	c.set_value("audio", "master", master)
	c.set_value("audio", "music", music)
	c.set_value("audio", "sfx", sfx)
	c.set_value("video", "fullscreen", fullscreen)
	c.set_value("game", "dmg_numbers", dmg_numbers)
	c.set_value("game", "shake", shake)
	c.set_value("game", "hitstop", hitstop)
	c.set_value("game", "outline", outline)
	c.set_value("video", "dof", dof)
	c.set_value("progress", "difficulty", difficulty)
	c.set_value("progress", "diff_unlocked", diff_unlocked)
	c.set_value("progress", "seen_shows", seen_shows)
	c.set_value("progress", "seen_relics", seen_relics)
	c.set_value("progress", "seen_intro", seen_intro)
	c.save(PATH)
