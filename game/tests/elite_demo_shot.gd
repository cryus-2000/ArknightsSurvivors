extends Node
## 图鉴演示连拍（精英化形态验收用，docs/91 §23 / §24）：把 game.tscn 以图鉴演示模式（demo_op）放进 SubViewport，
## 按图鉴的阶段 / 模式跑，隔几帧存一张 PNG；tools/elite_demo_shots.py 再拼成拼图与短 GIF。
##   godot --path game --fixed-fps 30 res://tests/elite_demo_shot.tscn -- --shot_op=<id> --shot_stage=0|1|2 [--shot_mode=-1|0|1|2|3]
##         --shot_dir=<目录> [--shot_start=秒 --shot_every=帧 --shot_n=张 --shot_w=640 --shot_h=360]
## 不进玩法、不改存档；所有 --xxx 用户参数的启动都静音（sfx.gd）。

var vp: SubViewport
var game: Node
var frames := 0
var saved := 0
var dir := ""
var start := 2.0
var every := 3
var n := 60


func _ready() -> void:
	var op := "skadi"
	var stage := 2
	var mode := -1
	var w := 640
	var h := 360
	var nodes := -1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot_op="):
			op = a.substr(10)
		elif a.begins_with("--shot_stage="):
			stage = int(a.substr(13))
		elif a.begins_with("--shot_mode="):
			mode = int(a.substr(12))
		elif a.begins_with("--shot_dir="):
			dir = a.substr(11)
		elif a.begins_with("--shot_start="):
			start = float(a.substr(13))
		elif a.begins_with("--shot_every="):
			every = maxi(1, int(a.substr(13)))
		elif a.begins_with("--shot_n="):
			n = int(a.substr(9))
		elif a.begins_with("--shot_nodes="):
			nodes = int(a.substr(13))
		elif a.begins_with("--shot_w="):
			w = int(a.substr(9))
		elif a.begins_with("--shot_h="):
			h = int(a.substr(9))
	DirAccess.make_dir_recursive_absolute(dir)
	vp = SubViewport.new()
	vp.size = Vector2i(w, h)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.handle_input_locally = false
	add_child(vp)
	game = load("res://game.tscn").instantiate()
	game.demo_op = op
	game.demo_nodes = nodes   # >= 0：成长节点验收，按节点数推进（路线 --route=<干员>:<路线> 另传）
	game.demo_sys.configure(stage, mode)
	vp.add_child(game)


func _process(_dt: float) -> void:
	frames += 1
	if frames < int(start * 30.0):
		return
	if (frames - int(start * 30.0)) % every != 0:
		return
	if dir != "":
		vp.get_texture().get_image().save_png(dir + "/f_%04d.png" % saved)
	saved += 1
	if saved >= n:
		get_tree().quit()
