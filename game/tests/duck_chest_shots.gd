extends Node
## 11-09 截图：①鸭爵在画面外（屏外大指示）；②精英宝箱掉落（地上一只 + 画面外一只）；③队友自动归队的小字提示。存 build/<--shots-out>/duck.png、chest.png、regroup.png。
## 窗口尺寸用 --resolution；触屏加 --touch；--ins=l,t,r,b 模拟安全区
var g
var ins: Array = []


func _fake_ins() -> void:
	if ins.size() == 4:
		var vis: Vector2 = get_viewport().get_visible_rect().size
		Cfg._ins_key = Vector3(vis.x, vis.y, Cfg.ui_k)
		Cfg._ins = ins.duplicate()


func _wait(n: int) -> void:
	for k in n:
		_fake_ins()
		await get_tree().process_frame


func _shot(out: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name))
	print("DUCK CHEST SHOT ", name, " ins=", Cfg.safe_insets(), " form=", Cfg.ui_form())


func _ready() -> void:
	var od := "duck_chest_shots"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots-out="):
			od = arg.get_slice("=", 1)
		elif arg.begins_with("--ins="):
			ins = Array(arg.get_slice("=", 1).split(",")).map(func(x): return float(x))
	var out := ProjectSettings.globalize_path("res://../build/" + od)
	DirAccess.make_dir_recursive_absolute(out)
	g = load("res://game.tscn").instantiate()
	add_child(g)
	await _wait(120)
	g.state = g.S.PLAY
	g.pending_levelups = 0
	g.pending_chests = 0
	for e in g.enemies:
		e.dead = true
	var e: Dictionary = g.duck.spawn()
	e.pos = g.ppos + Vector2(900, -260)
	await _wait(10)
	e.pos = g.ppos + Vector2(900, -260)
	await _wait(2)
	await _shot(out, "duck.png")
	e.dead = true
	g.pickups.drop(g.ppos + Vector2(230, 60), "chest", 1.0, "elite")
	g.pickups.drop(g.ppos + Vector2(-1100, 400), "chest", 1.0, "elite")
	await _wait(90)
	await _shot(out, "chest.png")
	# ③ 归队小字提示：两名队友突击中作战时限耗尽 → 自动归队（需 --squad=… 带两名队友）
	var sq = g.squad
	sq.set_stance(sq.ROAM)
	await _wait(30)
	sq.stamina = 0.001
	await _wait(150)
	var ob = g.onboard
	print("REGROUP toast=", ob.toast, " q=", ob.toast_q.size(), " busy=", ob.busy(), " drill=", ob.drill, " cur=", ob.cur, " out=", ob.out_id, " ask=", ob.ask_on)
	await _shot(out, "regroup.png")
	get_tree().quit(0)
