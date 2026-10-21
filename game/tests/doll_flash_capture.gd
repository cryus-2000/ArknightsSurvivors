extends Node
## 归溟替身闪现录像（10-21 法术脉冲版）：队长归溟、精二，右侧刷一团木桩怪，第 10 帧直接触发一次替身闪现，逐帧截图并打印替身位置。
##   godot --path game --fixed-fps 30 --resolution 960x540 res://tests/doll_flash_capture.tscn -- --op=specter_unchained --shot_dir=<目录>
## 不改存档；替身闪现参数取 json 精二段（$ 变量按 base 解析）。

const DT := 1.0 / 30.0
var dir := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot_dir="):
			dir = a.substr(11)
	DirAccess.make_dir_recursive_absolute(dir)
	var g = load("res://game.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	g.state = g.S.PLAY
	g.t = 20.0
	g.invuln = 999.0
	g.xp_need = 1000000000.0
	var o = g.squad.get_op("specter_unchained")
	o.elite = 2
	o.refresh_stats()
	var center: Vector2 = g.ppos + Vector2(150, 10)
	for k in 9:
		var e: Dictionary = g.spawner.spawn_enemy("stone", center + Vector2((k % 3 - 1) * 26, (k / 3 - 1) * 20))
		e.hp = 1000000.0
		e.max_hp = 1000000.0
	g.enemies_sys.build_grid()
	var base: Dictionary = o.def.get("base", {})
	var b := {"range": float(base.flash_range), "r": float(base.flash_r), "basis": "attack", "mult": float(base.flash_mult), "appear": 0.25,
		"spin": 0.45, "burst": 0.3, "anim": "doll_spin", "src": "替身闪现", "spins": int(base.flash_spins), "spin_gap": float(base.flash_gap), "max_n": int(base.get("flash_n", 0))}
	for f in 50:
		if f == 10:
			o.SegSkalter.h3_doll_flash(o, b)
		for e in g.enemies:
			e.pos = e.get("pos0", e.pos)
			e["pos0"] = e.pos
		g._update(DT)
		g.world.update_visuals(DT)
		g.world.present_step()
		g.queue_redraw()
		g.fx_add.queue_redraw()
		g.fg.queue_redraw()
		g.hud.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var fl: Dictionary = o.hw.sp.get("flash", {})
		if not fl.is_empty() and f % 5 == 0:
			print("FLASH t=%.2f pos=%s screen=%s" % [fl.t, fl.pos, g.get_viewport().get_canvas_transform() * fl.pos])
		if dir != "":
			get_viewport().get_texture().get_image().save_png(dir.path_join("f_%03d.png" % f))
	get_tree().quit()
