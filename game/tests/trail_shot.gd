extends Node
## 跑动拖尾代表色对照截图（docs/146；不进快检）：逐个干员当队长，按住 D 向右跑 80 帧，截主控附近一块（每人一张）。
##   godot --fixed-fps 60 --resolution 1280x720 --path game res://tests/trail_shot.tscn -- --shotdir=<目录> [--old] [--ids=a,b,c]
## --old：render/trail_col = 0（余烬回到灯火色，旧版）。

const Bal = preload("res://scripts/core/balance.gd")
const IDS := ["mizuki", "texas", "exusiai", "skadi", "eyjafjalla", "hoshiguma", "irene", "kaltsit", "lappland", "logos", "lumen", "saria", "siege", "suzuran", "skalter", "specter_unchained", "ulpianus", "wisadel", "angelina", "gladiia"]
var shot_dir := ""
var old := false
var ids: Array = IDS.duplicate()
var game: Node


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			shot_dir = a.substr(10)
		elif a == "--old":
			old = true
		elif a.begins_with("--ids="):
			ids = a.substr(6).split(",")
	Bal.v("render/trail_col", 1.0)
	if not (Bal._data.get("render") is Dictionary):
		Bal._data["render"] = {}
	Bal._data.render["trail_col"] = 0.0 if old else 1.0
	call_deferred("run")


func key(k: int, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)


func run() -> void:
	for id in ids:
		Cfg.character_id = id
		game = load("res://game.tscn").instantiate()
		add_child(game)
		for i in 8:
			await get_tree().process_frame
		game.sandbox = true
		game.fx.clear()
		for e in game.enemies:
			e.dead = true
		game.enemies = []
		game.max_hp = 99999.0
		game.hp = 99999.0
		key(KEY_D, true)
		for i in 330:
			game.state = game.S.PLAY
			game.pending_levelups = 0
			game.pending_chests = 0
			game.invuln = 1.0
			await get_tree().process_frame
		var img: Image = get_viewport().get_texture().get_image()
		var c := Vector2i(img.get_width() / 2, img.get_height() / 2)
		img.get_region(Rect2i(c.x - 200, c.y - 120, 400, 240)).save_png("%s/%s.png" % [shot_dir, id])
		key(KEY_D, false)
		game.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	print("TRAIL SHOT done")
	get_tree().quit(0)
