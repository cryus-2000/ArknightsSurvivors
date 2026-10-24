extends SceneTree
## 战斗镜头拉远候选（docs/112，tools/probes/cam_zoom_probe.py 调用；不改游戏代码）：
## 跑确定性批跑（--balance + 机器人 + --fixed-fps 60 --realtime），每帧把 Camera2D.zoom 强制成 --cz=<浮点>（可给 2/3 这种设置里存不下的精确值），
## 并按需：
##   --cz_shots=60,240,480   到这些游戏秒存一张整屏 PNG（shot_t0240.png）
##   --cz_rec=起@时长        这段每帧存一张（rec/f0000.png，python 端拼 mp4）
##   --cz_ab=1,0.85,0.75 --cz_ab_n=60   同局轮换：每 n 帧换下一档镜头，按「上一帧画的是哪档」分桶记帧时间 / 渲染 CPU / GPU / 屏内敌人数
##                                     （镜头只改画面，模拟逐帧相同；轮换对照不受机器负载起伏影响）
##   --cz_maxt=秒            到点退出
## 每秒记一次屏内敌人数（视口内、不含边距），结束打印 CZ {json}
var g: Node = null
var z := 1.0
var cz_force := false
var out := "."
var shots: Array = []
var rec_t0 := -1.0
var rec_dur := 0.0
var rec_n := 0
var maxt := 300.0
var ons: Array = []
var last_s := -1
var ab: Array = []
var ab_n := 60
var ab_i := 0
var frames := 0
var last_us := 0
var drawn_z := -1.0   # 上一帧画面用的镜头档
var buckets := {}
var multi: Array = []     # --cz_multi=100,115,150 --cz_multi_t=180：到点冻结模拟，逐档改设置里的缩放存同一帧
var multi_t := 180.0
var multi_i := -1
var multi_w := 0     # "z|分钟" -> {ft, rcpu, gpu, on}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cz="):
			z = float(a.substr(5))
			cz_force = true
		elif a.begins_with("--cz_out="):
			out = a.substr(9)
		elif a.begins_with("--cz_shots="):
			for s in a.substr(11).split(","):
				shots.append(float(s))
		elif a.begins_with("--cz_rec="):
			var sp := a.substr(9).split("@")
			rec_t0 = float(sp[0])
			rec_dur = float(sp[1])
		elif a.begins_with("--cz_ab="):
			for s in a.substr(8).split(","):
				ab.append(float(s))
		elif a.begins_with("--cz_ab_n="):
			ab_n = int(a.substr(10))
		elif a.begins_with("--cz_multi="):
			for v in a.substr(11).split(","):
				multi.append(int(v))
		elif a.begins_with("--cz_multi_t="):
			multi_t = float(a.substr(13))
		elif a.begins_with("--cz_maxt="):
			maxt = float(a.substr(10))
	DirAccess.make_dir_recursive_absolute(out + "/rec")
	change_scene_to_file.call_deferred("res://game.tscn")


func _on_screen() -> int:
	var inv: Transform2D = g.get_viewport().get_canvas_transform().affine_inverse()
	var r: Rect2 = inv * Rect2(Vector2.ZERO, g.get_viewport_rect().size)
	var k := 0
	for e in g.enemies:
		if not e.dead and r.has_point(e.pos):
			k += 1
	return k


func _sample() -> void:
	var rid: RID = g.get_viewport().get_viewport_rid()
	var now := Time.get_ticks_usec()
	if last_us > 0 and drawn_z > 0.0:
		var key := "%.4f|m%02d" % [drawn_z, int(g.t / 60.0)]
		if not buckets.has(key):
			buckets[key] = {"ft": PackedFloat32Array(), "rcpu": PackedFloat32Array(), "gpu": PackedFloat32Array(), "on": PackedInt32Array()}
		var b: Dictionary = buckets[key]
		b.ft.append((now - last_us) / 1000.0)
		b.rcpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
		b.gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		b.on.append(_on_screen())
	else:
		RenderingServer.viewport_set_measure_render_time(rid, true)
	last_us = now


func _stats(a: PackedFloat32Array) -> Array:
	var s := a.duplicate()
	s.sort()
	var sum := 0.0
	for v in s:
		sum += v
	return [snappedf(sum / maxf(1, s.size()), 0.01), snappedf(s[int(s.size() * 0.5)], 0.01), snappedf(s[mini(s.size() - 1, int(s.size() * 0.95))], 0.01)]


func _process(_dt: float) -> bool:
	if g == null:
		g = current_scene
		if g == null or not ("autotest" in g):
			g = null
			return false
	if g.state != g.S.PLAY:
		if g.cam != null:
			g.cam.zoom = Vector2(z, z)
		last_us = 0
		return false
	frames += 1
	if not ab.is_empty():
		_sample()
		z = float(ab[(frames / ab_n) % ab.size()])
		# 换档后头 5 帧不计（新露出的地面区块首次烘焙）
		drawn_z = -1.0 if frames % ab_n < 5 else z
	if not multi.is_empty():
		if multi_i < 0 and g.t >= multi_t:
			multi_i = 0
			Engine.time_scale = 0.0001   # 冻结模拟（固定帧步长 × 比例），画面照常渲染
			multi_w = 0
		if multi_i >= 0:
			var cfg: Node = get_root().get_node("Cfg")
			if multi_w == 0:
				cfg.cam_zoom_pct = int(multi[multi_i])
				cfg.view_changed.emit()
			multi_w += 1
			if multi_w >= 12:
				var fn2 := "%s/multi_%d.png" % [out, int(multi[multi_i])]
				g.get_viewport().get_texture().get_image().save_png(fn2)
				print("CZSHOT ", fn2, " zoom=", g.cam.zoom.x, " view_k=", g.optical.view_k if "optical" in g else -1, " t=", g.t)
				multi_i += 1
				multi_w = 0
				if multi_i >= multi.size():
					Engine.time_scale = 1.0
					print("CZ ", JSON.stringify({"multi": multi}))
					quit()
		return false
	if cz_force:
		g.cam.zoom = Vector2(z, z)
	if not shots.is_empty() and g.t >= float(shots[0]):
		var fn := "%s/shot_t%04d.png" % [out, int(shots[0])]
		shots.pop_front()
		g.get_viewport().get_texture().get_image().save_png(fn)
		print("CZSHOT ", fn, " on=", _on_screen(), " all=", g.enemies.size(), " boss=", g.bosses.filter(func(b): return not b.dead).size(), " zone=", g.zone_state, " zr=", int(g.zone_r), " lamp=", int(g.lamp))
	if rec_t0 >= 0.0 and g.t >= rec_t0 and g.t < rec_t0 + rec_dur:
		g.get_viewport().get_texture().get_image().save_png("%s/rec/f%04d.png" % [out, rec_n])
		rec_n += 1
	var s := int(g.t)
	if s != last_s and ab.is_empty():
		last_s = s
		ons.append([s, _on_screen(), g.enemies.size()])
	if g.t > maxt:
		var perf := {}
		for k in buckets:
			var b: Dictionary = buckets[k]
			var on := 0
			for v in b.on:
				on += v
			perf[k] = {"n": b.ft.size(), "ft": _stats(b.ft), "rcpu": _stats(b.rcpu), "gpu": _stats(b.gpu), "on": snappedf(float(on) / maxf(1, b.on.size()), 0.1)}
		print("CZ ", JSON.stringify({"z": z, "on": ons, "perf": perf, "vs": str(g.get_viewport_rect().size), "win": str(DisplayServer.window_get_size()), "rec": rec_n}))
		quit()
	return false
