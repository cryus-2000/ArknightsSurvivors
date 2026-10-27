extends Node
## 结算入场动效录帧（docs/62 §3.21b，10-28 用户「结算的动效再重新设计一下，出现的太快了」；不进快检）：开窗口、--fixed-fps 30 逐帧存 rec_<帧>.png。
##   godot --fixed-fps 30 --path game res://tests/settle_motion_rec.tscn -- --shotdir=<目录> [--touch]
## 三段：胜利完整出场 → 失败完整出场 → 胜利出场中途点一下跳到终态（再点才是按钮）。

const RunStats = preload("res://scripts/run/run_stats.gd")
const Game = preload("res://scripts/game.gd")
const Screen = preload("res://scripts/screens/settlement_screen.gd")

class Probe extends Screen:
	func _run(_id: String) -> void:
		pass   # 录像里不真的跳转

var game: Node
var frames := 0
var shot_dir := ""
var rec_i := 0
var s
var seg := -1
var seg_f := 0
## [结果, 段长（帧）, 跳过帧（-1 = 不跳）]
const SEGS := [["win", 140, -1], ["dead", 156, -1], ["win", 66, 18]]


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			shot_dir = a.substr(10)
	game = load("res://game.tscn").instantiate()
	add_child(game)


func _raw(result: String) -> Dictionary:
	var raw: Dictionary = RunStats.fake_raw()
	for id in ["texas", "lumen", "exusiai"]:
		raw.ops.append({"id": id, "name": id, "en": id, "col": [0.5, 0.7, 0.9], "leader": false, "t": 500.0, "left": 600.0})
	raw.result = result
	if result != "win":
		raw.killer = {"type": "", "env": "", "name": "被「溺亡的忏悔者」击倒", "cause": ""}
	return raw


func _start(i: int) -> void:
	seg = i
	seg_f = 0
	var res: String = SEGS[i][0]
	game.state = Game.S.WIN if res == "win" else Game.S.DEAD
	game.state_age = 99.0
	if s != null and is_instance_valid(s.squad_canvas):
		s.squad_canvas.queue_free()
	s = Probe.new(game)
	game.settlement = s
	s.set_model(RunStats.model(_raw(res)))


func _process(d: float) -> void:
	frames += 1
	if frames == 4:
		game.set_process(false)
		game.hud.size = get_viewport().get_visible_rect().size
		_start(0)
	if s == null:
		return
	s.tick(d)
	if seg_f == int(SEGS[seg][2]):
		var c := InputEventMouseButton.new()
		c.button_index = MOUSE_BUTTON_LEFT
		c.pressed = true
		c.position = Vector2(640, 400) * Cfg.ui_k
		s.input(c)
	game.hud.queue_redraw()
	get_viewport().get_texture().get_image().save_png(shot_dir + "/rec_%03d.png" % rec_i)
	rec_i += 1
	seg_f += 1
	if seg_f >= int(SEGS[seg][1]):
		if seg + 1 >= SEGS.size():
			get_tree().quit(0)
		else:
			_start(seg + 1)
