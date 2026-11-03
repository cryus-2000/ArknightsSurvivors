extends Node
## 图鉴演示录像（pixelfx 放开版验收，协调人 11-03：「按图鉴里的演示来录」）：同 elite_demo_shot，把 game.tscn 以图鉴演示模式（demo_op）放进 SubViewport，
## 按图鉴的阶段 / 模式跑，从 --rec_start 秒起每帧存一张 PNG（--fixed-fps 30 = 原速 30 帧）；--sfxtrace 时记下放出的音效 / 语音 / 配乐，结束打印 SFXTRACE / MUSTRACE，
## tools/px_demo_rec.py 离线混音后合进 mp4。镜头与图鉴一致：视口 = 图鉴舞台框 × k、gallery/demo_zoom × k（由脚本传 --bal）。
##   godot --path game --fixed-fps 30 res://tests/px_demo_rec.tscn -- --rec_op=<id> --rec_stage=0|1|2 --rec_mode=-1|0|1|2|3|4 --rec_dir=<目录> [--rec_start=秒 --rec_n=帧 --rec_w --rec_h --sfxtrace]

var vp: SubViewport
var game: Node
var frames := 0
var saved := 0
var dir := ""
var start := 1.0
var n := 180
var f0 := 0
var mus: Array = []
var rec_op := ""


func _ready() -> void:
	var op := "hoshiguma"
	var stage := 2
	var mode := -1
	var w := 888
	var h := 776
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rec_op="):
			op = a.substr(9)
		elif a.begins_with("--rec_stage="):
			stage = int(a.substr(12))
		elif a.begins_with("--rec_mode="):
			mode = int(a.substr(11))
		elif a.begins_with("--rec_dir="):
			dir = a.substr(10)
		elif a.begins_with("--rec_start="):
			start = float(a.substr(12))
		elif a.begins_with("--rec_n="):
			n = int(a.substr(8))
		elif a.begins_with("--rec_secs="):   # 德克萨斯版写法：按秒
			n = int(float(a.substr(11)) * 30.0)
		elif a.begins_with("--rec_w="):
			w = int(a.substr(8))
		elif a.begins_with("--rec_h="):
			h = int(a.substr(8))
	DirAccess.make_dir_recursive_absolute(dir)
	vp = SubViewport.new()
	vp.size = Vector2i(w, h)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.handle_input_locally = false
	add_child(vp)
	rec_op = op
	game = load("res://game.tscn").instantiate()
	game.demo_op = op
	game.demo_sys.configure(stage, mode)
	vp.add_child(game)


func _process(_dt: float) -> void:
	frames += 1
	if frames < int(start * 30.0):
		return
	var trace: bool = OS.get_cmdline_user_args().has("--sfxtrace")
	if saved == 0 and trace:
		Sfx.trace_on = true
		f0 = Engine.get_process_frames()
	if Sfx.trace_on:   # 配乐采样（同 autotest._rec_step）
		var ms: Array = []
		for c in Sfx.get_children():
			if c is AudioStreamPlayer and c.bus == "Music" and c.playing and c.stream != null:
				ms.append([c.stream.resource_path, c.volume_db, c.get_playback_position()])
		mus.append([Engine.get_process_frames(), Sfx.music_lp.cutoff_hz, ms])
	if dir != "":
		vp.get_texture().get_image().save_png(dir + "/rec_%05d.png" % saved)
	saved += 1
	if saved >= n:
		if Sfx.trace_on:
			print("SFXTRACE " + JSON.stringify({"frame0": f0, "trace": Sfx.trace}))
			print("MUSTRACE " + JSON.stringify({"buses": {}, "frames": mus}))
		var ld: Array = []   # 录像门禁（tools/px_prerecord.py）：这名干员实际加载的放开版帧条 + 演示期间取用 / 兜底计数
		var pres: Array = game.vfx.px_ul_prefixes(rec_op) if game.get("vfx") != null else ["fx_%s_ul_" % rec_op]   # 前缀按注册表取（归溟 id ≠ 前缀，11-04）
		if game.get("tex") is Dictionary:
			for k in game.tex:
				if game.tex[k] == null:
					continue
				for pre in pres:
					if str(k).begins_with(pre):
						ld.append(str(k))
						break
		print("PXSTATS " + JSON.stringify({"op": rec_op, "prefixes": pres, "loaded": ld.size(), "stats": game.vfx.px_stats if game.get("vfx") != null else {}}))
		get_tree().quit()
