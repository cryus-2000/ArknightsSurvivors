extends Node
## 仅 --materialmovie：按实际绘制帧录制，避免逻辑子步截图重复。
var g
var tick := -20
var saving := false
const NAMES := ["fx_flam_hit", "fx_water_splash", "fx_corrode_hit"]
var names: Array = NAMES   # --materialnames=a,b,…：换成任意帧条（docs/138 §7 第 2 批对照）

func _process(_dt: float) -> void:
	Engine.max_fps = 20
	if saving:
		return
	tick += 1
	if tick < 0:
		return
	if Cfg.dev_args().has("--lapplandmovie"):
		_lappland_movie()
		return
	if Cfg.dev_args().has("--ignitemovie"):
		_ignite_movie()
		return
	if Cfg.dev_args().has("--eyjamovie"):
		_eyja_movie()
		return
	if Cfg.dev_args().has("--lasermovie"):
		_laser_movie()
		return
	var ob := false   # --obnames=a,b,…：干员数据帧条（ob_fx strip，帧条后半段换颗粒的对照，docs/138 §11）
	for a in Cfg.dev_args():
		if a.begins_with("--materialnames="):
			names = Array(a.substr(16).split(","))
		if a.begins_with("--obnames="):
			names = Array(a.substr(10).split(","))
			ob = true
	var group: int = tick / 32
	var frame: int = tick % 32
	if group >= (1 if Cfg.dev_args().has("--materialmovie-fire") else names.size()):
		print("MATERIAL_MOVIE_COMPLETE")
		get_tree().quit()
		return
	if frame == 0:
		var pool = g.optical.grains
		g.fx.clear()
		pool.step(2.0)
		var previous: bool = pool.off
		if ob:
			for k in 2:
				var nm: String = names[group]
				var spec: Array = g.V6_FRAMES[nm]
				g.ch.fx({"kind": "strip", "name": nm, "pos": g.ppos + Vector2(-110 if k == 0 else 110, -40), "life": float(spec[0]) / float(spec[1]), "sc": g.PX, "col": Color.WHITE,
					"ang": 0.0, "anc": Vector2(-1, -1), "no_fade": false, "fr": int(spec[0]), "fps": float(spec[1]), "loop": false, "ph": 0, "floor": false, "add": false, "mat_skip": k == 0})
		else:
			var msc: float = g.PX
			for a in Cfg.dev_args():
				if a.begins_with("--materialscale="):
					msc = float(a.substr(16))
			pool.off = true
			g.vfx.fx_sprite(names[group], g.ppos + Vector2(-90, -50), msc)
			if not g.fx.is_empty():
				g.fx[-1]["gb_skip"] = true   # 左边原版：形状颗粒化也不接
			pool.off = false
			g.vfx.fx_sprite(names[group], g.ppos + Vector2(90, -50), msc)
		pool.off = previous
		print("MATERIAL_MOVIE %s grains=%d" % [names[group], pool.pos.size()])
	if frame < 24:
		saving = true
		await RenderingServer.frame_post_draw
		var path: String = g.shot_dir + "/movie_%d_%02d.png" % [group, frame]
		var result: int = g.get_viewport().get_texture().get_image().save_png(path)
		if result != OK:
			push_error("Material movie capture failed: " + path)
			get_tree().quit(1)
		saving = false


func _eyja_movie() -> void:
	var group: int = tick / 48
	var frame: int = tick % 48
	if group >= 2:
		print("EYJA_MOVIE_COMPLETE")
		get_tree().quit()
		return
	var o = g.squad.get_op("eyjafjalla")
	if o == null or not o.hw.has("lobs"):
		push_error("Eyja preview requires initialized operator")
		get_tree().quit(1)
		return
	var target: Vector2 = g.ppos + Vector2(130, -35)
	if frame == 0:
		g.fx.clear()
		g.optical.grains.step(2.0)
		o.hw.lobs.clear()
		o.hw.pools.clear()
		o.hw.lobs.append({"b": {"look": {"weighted": true}}, "from": g.ppos + Vector2(-140, -35), "to": target,
			"t": 0.0, "dur": 0.65 if group == 0 else 0.85, "dmg": 0.0, "r": 35.0, "src": "preview",
			"h": 0.0 if group == 0 else 80.0, "sz": 1.0, "trail": 0.0, "fireball": group == 0, "spin": 1.0})
		print("EYJA_MOVIE group=%d" % group)
	if group == 1 and frame == 19:
		o.hw.pools.append({"b": {"weighted": true, "every": 0.5, "look": "lava"}, "pos": target,
			"r": 36.0, "t": 1.3, "dur": 1.3, "tick": 0.0, "dmg": 0.0, "bub": 0.0, "pat": 0})
	if frame < 44:
		saving = true
		await RenderingServer.frame_post_draw
		var result: int = g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/eyja_%d_%02d.png" % [group, frame])
		if result != OK:
			push_error("Eyja movie capture failed")
			get_tree().quit(1)
		saving = false


func _ignite_movie() -> void:
	if tick >= 36:
		print("IGNITE_MOVIE_COMPLETE")
		get_tree().quit()
		return
	if tick == 0:
		var o = g.squad.get_op("eyjafjalla")
		var magma = load("res://scripts/characters/magma_projectile.gd")
		g.fx.clear()
		var pool = g.optical.grains
		pool.step(2.0)
		var previous: bool = pool.off
		pool.off = true
		magma.ignite_hit(o, g.ppos + Vector2(-110, -65), 65.0, 1.0)
		pool.off = false
		magma.ignite_hit(o, g.ppos + Vector2(110, -65), 65.0, 1.0)
		pool.off = previous
		print("IGNITE_MOVIE grains=%d" % pool.pos.size())
		assert(pool.pos.size() > 0)
	saving = true
	await RenderingServer.frame_post_draw
	var result: int = g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/ignite_%02d.png" % tick)
	if result != OK:
		push_error("Ignite movie capture failed")
		get_tree().quit(1)
	saving = false


func _lappland_strip(o, at: Vector2, old: bool) -> void:
	var name := "fx_lappland_slash"
	assert(o._fx_tex(name) != null)
	var spec: Array = g.V6_FRAMES[name]
	o.fx({"kind": "strip", "name": name, "pos": at, "life": float(spec[0]) / float(spec[1]),
		"sc": 2.0, "col": Color.WHITE, "ang": 0.0, "anc": Vector2(-1, -1), "no_fade": false,
		"fr": int(spec[0]), "fps": float(spec[1]), "loop": false, "ph": 0, "floor": false, "add": false,
		"material_preview_old": old})


func _lappland_movie() -> void:
	if tick >= 42:
		print("LAPPLAND_MOVIE_COMPLETE")
		get_tree().quit()
		return
	var o = g.squad.get_op("lappland")
	assert(o != null)
	if tick == 0:
		o.pfx.clear()
		g.optical.grains.step(2.0)
	if tick in [0, 14, 28]:
		for side in 2:
			_lappland_strip(o, g.ppos + Vector2(-110 if side == 0 else 110, -40), side == 0)
	if tick == 5:
		print("LAPPLAND_MOVIE grains=%d" % g.optical.grains.pos.size())
	saving = true
	await RenderingServer.frame_post_draw
	assert(g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/lappland_%02d.png" % tick) == OK)
	saving = false


## --lasermovie（docs/138 §12 激光两个方向对照）：每 32 帧同时放三种光束（Boss 粗光束 / 治疗连线 / 狙击弹道），录 24 帧；
## （fx/laser_style 已删，10-29 起只录 A 像素光束）
func _laser_movie() -> void:
	var group: int = tick / 32
	var frame: int = tick % 32
	if group >= 2:
		print("LASER_MOVIE_COMPLETE")
		get_tree().quit()
		return
	if frame == 0:
		g.fx.clear()
		g.optical.grains.step(2.0)
		var o: Vector2 = g.ppos
		g.fx.append({"kind": "bbeam", "a": o + Vector2(-230, -120), "b": o + Vector2(230, -150), "wid": 22.0, "col": Color(1.0, 0.35, 0.75), "life": 0.5, "max": 0.5, "enemy": true})
		g.fx.append({"kind": "beam", "a": o + Vector2(-200, -40), "b": o + Vector2(-20, -24), "w": 3.0, "col": Color(0.55, 1.0, 0.5), "life": 0.3, "max": 0.3})
		g.fx.append({"kind": "tracer", "a": o + Vector2(40, 60), "b": o + Vector2(240, -10), "wid": 10.0, "col": Color(1.0, 0.6, 0.3), "life": 0.35, "max": 0.35, "enemy": true})
	if frame < 24:
		saving = true
		await RenderingServer.frame_post_draw
		g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/laser_%d_%02d.png" % [group, frame])
		saving = false
