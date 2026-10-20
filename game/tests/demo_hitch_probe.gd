extends Node
## 演示首点耗时探针（10-21）：模拟标题页预热完成后，在 SubViewport 里建演示局（同 gallery._demo_start），
## 量「建场景同步耗时」与之后几帧的帧间隔（含着色器编译），连点三个干员。有界面跑（着色器只在真渲染里编译）：
##   godot --path game res://tests/demo_hitch_probe.tscn -- --loadprof
## 打印 DEMOHITCH <干员> build=<ms> frames=<ms,...>
const Game = preload("res://scripts/game.gd")
const A = preload("res://scripts/art.gd")
var phase := 0
var vp: SubViewport
var t_last := 0
var frame_ms: Array = []
var ops := ["mizuki", "irene", "lumen"]
var cur := 0
var wait := 0
var build_ms := 0.0
var gal = null
var warm_t0 := 0
var warm_ms := -1.0
var warm_max := 0.0


func _ready() -> void:
	A.normal_maps = Cfg.normal_maps and DisplayServer.get_name() != "headless"   # 同标题页 _prewarm
	A.prewarm_start(Game.preload_tex_names())


func _process(_d: float) -> void:
	var now := Time.get_ticks_usec()
	match phase:
		0:
			if A.prewarm_busy():
				return
			if OS.get_cmdline_user_args().has("--warm"):   # 同图鉴 open()：后台编译脚本 + 分帧预载，量预载期间最长一帧
				if gal == null:
					gal = load("res://scripts/gallery.gd").new()
					A.late_log = OS.get_cmdline_user_args().has("--slow")
					if OS.get_cmdline_user_args().has("--slow"):
						var G = load("res://scripts/game.gd")
						var b0 := Time.get_ticks_usec()
						G.preload_tex_names()
						var b1 := Time.get_ticks_usec()
						G.demo_warm_names()
						var b2 := Time.get_ticks_usec()
						ResourceLoader.load_threaded_request("res://scripts/characters/data_operator.gd")
						var b3 := Time.get_ticks_usec()
						print("WARMSLOW names=%.1f extra=%.1f threadreq=%.1f" % [(b1 - b0) / 1000.0, (b2 - b1) / 1000.0, (b3 - b2) / 1000.0])
					gal._warm_demo()
					warm_t0 = now
					t_last = now
				var more := A.warm_step(4000)
				if (now - t_last) / 1000.0 > 60.0:
					print("WARMSPIKE %.1fms q=%d" % [(now - t_last) / 1000.0, A._warm_q.size()])
				warm_max = maxf(warm_max, (now - t_last) / 1000.0)
				t_last = now
				if more:
					return
				if warm_ms < 0.0:
					warm_ms = (now - warm_t0) / 1000.0
					print("DEMOWARM total=%.0f max_frame=%.1f" % [warm_ms, warm_max])
					A.late_log = true   # 之后建局时还在读的贴图逐张打印 TEXLATE
					var s0 := Time.get_ticks_usec()
					var st := ResourceLoader.load_threaded_get_status("res://scripts/characters/data_operator.gd")
					load("res://scripts/characters/data_operator.gd")
					print("DEMOSPLIT after_warm data_operator status=%d load=%.1f" % [st, (Time.get_ticks_usec() - s0) / 1000.0])
			wait += 1
			if wait > 30:
				if OS.get_cmdline_user_args().has("--split"):   # 分段：先单独量脚本 / 场景载入
					var a0 := Time.get_ticks_usec()
					load("res://game.tscn")
					var a1 := Time.get_ticks_usec()
					load("res://scripts/characters/data_operator.gd")
					var a2 := Time.get_ticks_usec()
					print("DEMOSPLIT scene_load=%.1f data_operator=%.1f" % [(a1 - a0) / 1000.0, (a2 - a1) / 1000.0])
				phase = 1
		1:
			if vp != null:
				vp.queue_free()
			vp = SubViewport.new()
			vp.size = Vector2i(640, 360)
			vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			add_child(vp)
			var t0 := Time.get_ticks_usec()
			var gm: Node = load("res://game.tscn").instantiate()
			gm.demo_op = ops[cur]
			vp.add_child(gm)
			build_ms = (Time.get_ticks_usec() - t0) / 1000.0
			A.late_log = false
			frame_ms = []
			t_last = Time.get_ticks_usec()
			phase = 2
		2:
			frame_ms.append(snappedf((now - t_last) / 1000.0, 0.1))
			t_last = now
			if frame_ms.size() >= 8:
				print("DEMOHITCH %s build=%.1f frames=%s" % [ops[cur], build_ms, str(frame_ms)])
				cur += 1
				wait = 0
				phase = 3 if cur < ops.size() else 4
		3:
			wait += 1
			if wait > 20:
				phase = 1
		4:
			if OS.get_cmdline_user_args().has("--loadprof"):
				var prev := 0
				var s := ""
				for m in A.marks:
					s += "%s=%d " % [m[0], m[1] - prev if prev else 0]
					prev = m[1]
				print("MARKS " + s)
			get_tree().quit()
