extends Node
## 作战记录入场动效录帧（docs/62 §3.24；不进快检）：开窗口、--fixed-fps 30 逐帧存 rec_<帧>.png。
##   godot --fixed-fps 30 --path game res://tests/run_stats_rec.tscn -- --shotdir=<目录> [--ops=6] [--old] [--rm]
## --ops=N：假记录补到 N 名干员（缺省 5：4 名 + 1 个队长之外的补位）；--old：用 tests/_old_run_stats_screen.gd（改前版，临时拷贝）；--rm：减少动态效果。

const RunStats = preload("res://scripts/run/run_stats.gd")
const Game = preload("res://scripts/game.gd")
const UM = preload("res://scripts/ui_motion.gd")

var game: Node
var frames := 0
var shot_dir := ""
var old := false
var n_ops := 4
var rm := false
var t_open := -1
var rec_i := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			shot_dir = a.substr(10)
		elif a == "--old":
			old = true
		elif a == "--rm":
			rm = true
		elif a.begins_with("--ops="):
			n_ops = int(a.substr(6))
	game = load("res://game.tscn").instantiate()
	add_child(game)


func _raw() -> Dictionary:
	var raw: Dictionary = RunStats.fake_raw()
	var ids := ["lappland", "texas", "exusiai", "irene", "logos", "wisadel", "angelina", "hoshiguma"]
	var cols := [[0.8, 0.3, 0.35], [0.9, 0.55, 0.3], [1.0, 0.8, 0.3], [0.7, 0.4, 0.8], [0.4, 0.4, 0.9], [0.9, 0.4, 0.4], [0.5, 0.5, 1.0], [0.9, 0.7, 0.4]]
	var extra: int = n_ops - (raw.ops as Array).size()
	for i in extra:
		var id: String = ids[i % ids.size()]
		raw.ops.append({"id": id, "name": id.capitalize(), "en": id.to_upper(), "col": cols[i % cols.size()], "leader": false, "t": 120.0 + 40.0 * i, "left": -1.0, "elite": 1})
		raw.op_out[id] = {"普攻": 60000.0 - 7000.0 * i, "技能": 30000.0 - 3000.0 * i}
		raw.op_kills[id] = 200
		raw.op_casts[id] = 5
	return raw


func _process(d: float) -> void:
	frames += 1
	if t_open > 0:
		UM.advance(d)   # game 的 _process 停了，界面时钟自己推
	if frames == 4:
		game.set_process(false)
		game.hud.size = Vector2(1280, 720)
		game.state = Game.S.WIN
		game.state_age = 99.0
		Cfg.reduce_motion = rm
		if old:
			var S = load("res://tests/_old_run_stats_screen.gd")
			game.run_stats = S.new(game)
		game.run_stats.show_model(RunStats.model(_raw()))
		t_open = frames
	if t_open > 0:
		game.hud.queue_redraw()
		if frames > t_open + 1:
			get_viewport().get_texture().get_image().save_png(shot_dir + "/rec_%03d.png" % rec_i)
			rec_i += 1
		if frames - t_open > 120:
			get_tree().quit(0)
