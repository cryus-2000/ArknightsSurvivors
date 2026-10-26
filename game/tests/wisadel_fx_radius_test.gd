extends Node
## 维什戴尔爆炸特效跟着判定半径走（用户 10-26：普攻爆炸半径 78 → 66 之后，帧条 / 冲击环 / 焦痕的大小要跟着变，视觉边缘和伤害边缘对齐）：
##   实心边（帧条缩放 × H4_BOOM_CORE）= 判定半径 × fill（普通 1.0 / 轻型 0.82）±3%；半径更小的更小；旧取整档下 66 和 78 同大（对照）
## godot --headless --path game res://tests/wisadel_fx_radius_test.tscn -- --balance --seed=1 --op=wisadel
## 全部通过时打印 "WISADEL FX RADIUS checks=N failures=0"；--capture 时存对比图 build/wisadel_fx_radius/<配置>.png 和 log.json（叠判定圈由 tools/probes/wisadel_fx_radius.py 做）
const Seg = preload("res://scripts/characters/blocks/seg_wisadel.gd")
const Bal = preload("res://scripts/core/balance.gd")
var g
var checks := 0
var failures := 0


func ok(v: bool, what: String) -> void:
	checks += 1
	if not v:
		failures += 1
		printerr("FAIL: ", what)


func sprites() -> Array:
	return g.fx.filter(func(f): return f.get("name", "") == "fx_wisadel_cannon")


func solid(r: float, light: bool) -> float:
	var o = g.squad.get_op("wisadel")
	g.fx.clear()
	Seg.h4_impact_fx(o, g.ppos + Vector2(200.0, 0.0), r, light)
	var sp: Array = sprites()
	if sp.is_empty():
		return -1.0
	return float(sp[0].scale) * Seg.H4_BOOM_CORE


func _ready() -> void:
	g = load("res://game.tscn").instantiate()
	add_child(g)
	for i in 5: await get_tree().process_frame
	g.set_process(false)
	g.mode = g.Mode.PLAY
	g.state = g.S.PLAY
	g.sandbox = true
	g.t = 60.0
	var cap_px: float = floorf(g.vfx.FX_SCALE_MAX) * Seg.H4_BOOM_CORE
	for r in [54.0, 66.0, 78.0, 90.0]:
		var s: float = solid(r, false)
		ok(s > 0.0 and absf(s - r) <= r * 0.03, "r=%.0f：实心边 %.1f 对齐判定圈（±3%%）" % [r, s])
	var sl: float = solid(66.0, true)
	ok(absf(sl - 66.0 * 0.82) <= 66.0 * 0.82 * 0.03, "轻型（魂炮 / 礼尚往来）按 0.82 × r：%.1f" % sl)
	ok(solid(66.0, false) < solid(78.0, false), "半径变小，特效跟着变小（66 < 78）")
	# 旧取整档：66 和 78 一样大（这就是用户看到的「特效没变」）
	Bal._data["fx"]["boom_scale_exact"] = 0.0
	ok(is_equal_approx(solid(66.0, false), solid(78.0, false)), "旧取整档下 66 和 78 同大（对照）")
	Bal._data["fx"]["boom_scale_exact"] = 1.0
	# 大半径（巨炮 S3 = 165）超过缩放上限：中心一团封顶，外圈补团，不报错
	var big: float = solid(165.0, false)
	ok(big > 0.0 and big <= cap_px + 0.1, "巨炮半径超过上限：中心一团封顶 %.1f" % big)
	var capture: bool = OS.get_cmdline_user_args().has("--capture")
	if capture:
		await capture_shots()
	print("WISADEL FX RADIUS checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func capture_shots() -> void:
	var out_dir := ProjectSettings.globalize_path("res://../build/wisadel_fx_radius")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var o = g.squad.get_op("wisadel")
	g.cam.zoom = Vector2(3.0, 3.0)
	var c: Vector2 = g.ppos + Vector2(0.0, -40.0)
	g.glance_pos = c
	var log := {"cfgs": []}
	# 旧 78（改半径前的样子）/ 旧取整 66（只改了判定，画面没变）/ 新 66（画面跟着判定走）
	for cfg in [["old78", 78.0, 0.0], ["old66", 66.0, 0.0], ["new66", 66.0, 1.0]]:
		Bal._data["fx"]["boom_scale_exact"] = float(cfg[2])
		g.fx.clear()
		o.pfx.clear()
		Seg.h4_impact_fx(o, c, float(cfg[1]), false)
		for f in sprites():
			f.life = f.max * (1.0 - 2.2 / 4.0)   # 最亮那一帧
		for k in 3:
			g.glance_pos = c
			g.glance_t = g.glance_ease
			g.queue_redraw()
			g.fx_add.queue_redraw()
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var tf: Transform2D = get_viewport().get_canvas_transform() * get_viewport().get_final_transform().affine_inverse()
		var p0: Vector2 = tf * c
		var p1: Vector2 = tf * (c + Vector2(float(cfg[1]), 0.0))
		log.cfgs.append({"name": cfg[0], "r": cfg[1], "centre": [p0.x, p0.y], "r_screen": p1.x - p0.x, "solid": float(sprites()[0].scale) * Seg.H4_BOOM_CORE})
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("%s.png" % cfg[0]))
	Bal._data["fx"]["boom_scale_exact"] = 1.0
	log["size"] = [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]
	var f := FileAccess.open(out_dir.path_join("log.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(log))
	f.close()
