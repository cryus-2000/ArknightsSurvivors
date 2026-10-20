extends Node
## 维什戴尔「魂灵之影」原生身体时间线（docs/108 §3、docs/107）：
##   godot --headless --path game res://tests/wisadel_soul_test.tscn -- --regression --balance --seed=1 --op=wisadel
## 出场 native_soul_start → 常驻 soul_idle 循环；魂炮开火不换攻击动作（10-21 用户：直接发射），身体时间线照常 → 离场在原地播 native_soul_die。
## 画面状态只写 wd.vis，不影响伤害时刻。加 --capture 时开窗口逐帧截图到 build/wisadel_soul_capture/（evidence.json 记每帧状态）。
## 全部通过时打印 "WISADEL SOUL failures=0"。

const DT := 1.0 / 60.0
var fails := 0
var n := 0


func ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		fails += 1
		printerr("FAIL: ", what)


func _ready() -> void:
	var capture := OS.get_cmdline_user_args().has("--capture")
	var output := ProjectSettings.globalize_path("res://../build/wisadel_soul_capture")
	if capture:
		DirAccess.make_dir_recursive_absolute(output)
	var g = load("res://game.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	g.state = g.S.PLAY
	g.t = 60.0
	g.invuln = 999.0
	g.xp_need = 1000000000.0
	var o = g.squad.get_op("wisadel")
	ok(o != null, "维什戴尔在编队里（--op=wisadel）")
	if o == null:
		get_tree().quit(1)
		return
	var center: Vector2 = g.ppos
	o.pos = center
	o.is_leader = true
	o.elite = 2
	o.refresh_stats()
	o.sp = [-10000.0, -10000.0, -10000.0]
	for k in 6:
		var enemy: Dictionary = g.spawner.spawn_enemy("stone", center + Vector2(160 + k * 10, (k % 3 - 1) * 18))
		enemy.hp = 1000000.0
		enemy.max_hp = 1000000.0
	g.enemies_sys.build_grid()
	var S = o.SegSkalter
	var evidence := []
	var seen := {}
	var fired_at := -1.0
	var slot_at_hit := ""
	var idle_after_start := false
	for frame in 300:
		g._update(DT)
		if capture:
			g.world.update_visuals(DT)
			g.world.present_step()
			g.queue_redraw()
			g.fx_add.queue_redraw()
			g.fg.queue_redraw()
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
		var souls: Array = o.hw.get("wd", {}).get("souls", [])
		if souls.is_empty():
			continue
		var s: Dictionary = souls[0]
		var native: Array = S._h4_soul_native(o, 0, s)
		var key: String = str(native[3]) if not native.is_empty() else ""
		seen[key] = true
		var st: Dictionary = o.hw.wd.vis[0]
		if key == "native_soul_idle" and seen.has("native_soul_start"):
			idle_after_start = true
		if s.get("fired", false) and float(s.get("ft", -1.0)) >= 0.0 and fired_at < 0.0:
			fired_at = g.t
			slot_at_hit = key
		evidence.append({"frame": frame, "t": snappedf(g.t, 0.001), "slot": key, "pose": native[1] if not native.is_empty() else -1, "ft": snappedf(float(s.get("ft", -1.0)), 0.001)})
		if capture:
			var image := get_viewport().get_texture().get_image()
			image.save_png(output.path_join("f_%03d.png" % frame))
	ok(seen.has("native_soul_start"), "出场播 native_soul_start")
	ok(idle_after_start, "出场播完进入 soul_idle 循环")
	ok(fired_at > 0.0, "魂炮照常出膛")
	ok(not seen.has("native_soul_attack") and o.sprite_spec("native_soul_attack").is_empty(), "不再有攻击帧条（native_soul_attack 已删）")
	ok(slot_at_hit in ["native_soul_idle", "native_soul_start"], "出膛那一刻身体仍是待机 / 出场时间线（%s）" % slot_at_hit)
	var fx_before: int = g.fx.size()
	o.on_leave()
	var dies: int = g.fx.slice(fx_before).filter(func(f): return str(f.get("name", "")) == "op_wisadel_soul_native_die").size()
	ok(dies == o.hw.wd.souls.size() and dies > 0 and not o.hw.wd.has("vis"), "离场：每个魂灵之影原地播 native_soul_die，画面状态清空")
	if capture:
		var file := FileAccess.open(output.path_join("evidence.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(evidence))
		file.close()
	print("%d checks, %d failed" % [n, fails])
	print("WISADEL SOUL failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
