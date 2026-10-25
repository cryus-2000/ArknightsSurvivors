## 颗粒模板微基准（docs/50 §26，帧率会话 10-25）：同一窗口里几份 fx_grains 轮流跑满预算，量 step 与 _draw 的单帧耗时。
## 机器忙时绝对值会被放大，所以每份取多帧的 P10 / P50（低分位受抢占影响小），几份同时段每 30 帧轮换比较。
## 用法：godot --path game res://tests/grains_bench.tscn -- --bench=<脚本路径>,<脚本路径> [--frames=1200] [--level=2] [--off=0.0]
##   旧版对照：git show <提交>:game/scripts/render/fx_grains.gd > game/tests/_bench_old_fx_grains.gd（不入库），--bench=res://tests/_bench_old_fx_grains.gd,res://scripts/render/fx_grains.gd
##   --off：每帧发射点有多大比例落在镜头外（量屏外不发的收益）
extends Node2D

class FakeG:
	extends Node2D
	var vrng := RandomNumberGenerator.new()
	var optical_on := true
	var prof_on := true
	var prof := {}
	var cam: Camera2D


var g: FakeG
var nodes: Array = []
var names: Array = []
var stats := {}   # 名 → {"step": [], "draw": [], "n": []}
var frame := 0
var frames := 1200
var off_k := 0.0
var cur := 0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	var paths: PackedStringArray = ["res://scripts/render/fx_grains.gd"]
	var level := 2
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--bench="):
			paths = a.substr(8).split(",")
		if a.begins_with("--frames="):
			frames = int(a.substr(9))
		if a.begins_with("--level="):
			level = int(a.substr(8))
		if a.begins_with("--off="):
			off_k = float(a.substr(6))
	g = FakeG.new()
	g.vrng.seed = 7
	add_child(g)
	g.cam = Camera2D.new()
	g.cam.position = Vector2(640, 360)
	g.add_child(g.cam)
	g.cam.make_current()
	for i in paths.size():
		var n: Node2D = load(paths[i]).new()
		g.add_child(n)
		n.setup(g)
		n.level = level
		nodes.append(n)
		var nm: String = "%d:%s" % [i, paths[i].get_file()]
		names.append(nm)
		stats[nm] = {"step": PackedFloat32Array(), "draw": PackedFloat32Array(), "n": PackedInt32Array(), "rcpu": PackedFloat32Array(), "gpu": PackedFloat32Array()}
	rng.seed = 3
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _emit(n) -> void:
	# 每帧：一道刀光（140 颗上限）+ 两团材质（火 / 水各 30）+ 6 颗火星；落点按 off_k 比例放到镜头外
	for i in 140:
		var p := Vector2(rng.randf_range(200, 1080), rng.randf_range(120, 600))
		if rng.randf() < off_k:
			p.x += 1600.0
		n.push("slash", p, Vector2.from_angle(rng.randf() * TAU), Color(0.9, 0.8, 0.5))
	for kind in ["fire", "water"]:
		for i in 30:
			var p := Vector2(rng.randf_range(200, 1080), rng.randf_range(120, 600))
			if rng.randf() < off_k:
				p.x += 1600.0
			n.push(kind, p, Vector2.UP, Color(1, 0.7, 0.4))
	var sp := Vector2(rng.randf_range(200, 1080), rng.randf_range(120, 600))
	n.spark(sp, sp.y + 10.0, Color(1, 0.8, 0.5), 6)


func _process(dt: float) -> void:
	# 上一帧 _draw 的耗时（fx_grains._draw 自己记进 g.prof.op_grains_draw）
	var d: float = int(g.prof.get("op_grains_draw", 0)) / 1000.0
	if d > 0.0 and frame % 30 > 11:
		stats[names[cur]].draw.append(d)
		var rid: RID = get_viewport().get_viewport_rid()
		stats[names[cur]].rcpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
		stats[names[cur]].gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
	g.prof["op_grains_draw"] = 0
	frame += 1
	if frame % 30 == 0:
		cur = (cur + 1) % nodes.size()   # 每 30 帧换一份跑（其余清空不画）
		for i in nodes.size():
			if i != cur:
				nodes[i].kill = true
				nodes[i].step(dt)
				nodes[i].kill = false
	var n = nodes[cur]
	if "_last_us" in n:
		n._last_us = 0   # 微基准不走帧时自适应（上限固定满额）
	_emit(n)
	var t0 := Time.get_ticks_usec()
	n.step(1.0 / 60.0)
	var t1 := Time.get_ticks_usec()
	if frame % 30 > 10:   # 每段前 10 帧填满预算，不记
		stats[names[cur]].step.append((t1 - t0) / 1000.0)
		stats[names[cur]].n.append(n.pos.size() + n.sparks.size())
	if frame >= frames:
		_report()
		get_tree().quit()


func _pct(a: PackedFloat32Array, q: float) -> float:
	var b := Array(a)
	b.sort()
	return b[int(q * (b.size() - 1))] if b.size() > 0 else -1.0


func _report() -> void:
	for nm in names:
		var s: Dictionary = stats[nm]
		var na := Array(s.n)
		na.sort()
		print("GRAINBENCH %s alive_med=%d step_p10=%.3f step_p50=%.3f draw_p10=%.3f draw_p50=%.3f rcpu_p10=%.3f rcpu_p50=%.3f gpu_p50=%.3f frames=%d/%d" % [nm, na[na.size() / 2] if na.size() > 0 else 0,
			_pct(s.step, 0.1), _pct(s.step, 0.5), _pct(s.draw, 0.1), _pct(s.draw, 0.5), _pct(s.rcpu, 0.1), _pct(s.rcpu, 0.5), _pct(s.gpu, 0.5), s.step.size(), s.draw.size()])
