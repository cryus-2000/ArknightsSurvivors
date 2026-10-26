extends Node
## docs/154 翻卡界面截图（自审用）：首通后、已达成结局二 / 三 / 四（入口卡描色边）的一局，直接发路口一的牌，
## 按界面时钟在 发牌中 / 摊开 / 悬停 / 起手 / 翻转 / 揭示 / 事件面板 各截一张 → build/<--shots-out>/s_<名>.png。
## 用法：godot --path game --fixed-fps 60 --resolution 1280x720 res://tests/node_cards_shots.tscn -- --shots-out=node_shots [--touch]

var g
var out := ""


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("s_%s.png" % name))


var rec := false
var fresh := false
var rec_n := 0


## 等若干秒；--rec 时每 2 帧存一张 r_#####.png（30 fps 录像）
func _wait(sec: float) -> void:
	for k in int(sec * 60.0):
		await get_tree().process_frame
		if rec and Engine.get_process_frames() % 2 == 0:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out.path_join("r_%05d.png" % rec_n))
			rec_n += 1


func _ready() -> void:
	var od := "node_shots"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots-out="):
			od = arg.get_slice("=", 1)
		if arg == "--rec":
			rec = true
		if arg == "--fresh":
			fresh = true   # 首次未通关：一个结局都没达成过，卡底不出信物提示
		if arg == "--rm":
			Cfg.reduce_motion = true   # 减少动态效果（只在内存里）
	out = ProjectSettings.globalize_path("res://../build/" + od)
	DirAccess.make_dir_recursive_absolute(out)
	Cfg.endings_cleared.clear()
	for e in (["standard"] if fresh else ["standard", "knight", "deep", "resolve"]):
		Cfg.endings_cleared.append(e)   # 只在内存里：全部达成 = 入口卡带信物提示；--fresh 只有结局一
	g = load("res://game.tscn").instantiate()
	add_child(g)
	await _wait(1.5)
	g.state = g.S.PLAY
	g.show_queue.clear()
	g.pending_levelups = 0
	g.pending_chests = 0
	g.t = 214.0
	g.endg.enabled = true
	g.endg._checked = true
	g.rng.seed = 11
	g.endg._deal(1)
	await _wait(0.18)
	await _shot("1_deal")
	await _wait(0.8)
	await _shot("2_spread")
	# 其余卡种的卡背纹样（只为截图换卡组，不是真实发牌）
	var keep: Array = g.endg.deck
	for set_i in 2:
		var types: Array = [["rest", "elite", "shop"], ["fog", "wish", "incident"]][set_i]
		g.endg.deck = types.map(func(tt): return {"type": tt, "must": false, "ends": []})
		g.panel_ui.show_choices("深入海洋 · 路口二", g.endg.deck.map(func(c): return {"kind": "node", "id": "x", "name": "", "desc": "", "node": c}), "cross", "选一张翻开，翻开即生效")
		await _wait(0.9)
		await _shot("2%s_types" % ["b", "c"][set_i])
	g.endg.deck = keep
	g.panel_ui.show_choices("深入海洋 · 路口一", keep.map(func(c): return {"kind": "node", "id": "x", "name": "", "desc": "", "node": c}), "cross", "选一张翻开，翻开即生效")
	await _wait(0.9)
	g.kb_nav = true
	var want := 0
	for i in g.endg.deck.size():
		if str(g.endg.deck[i].get("event", "")) == "opening":
			want = i
	# 逐张悬停：带路线的卡下方出结局名，普通卡不出；切卡中途截一张看淡入淡出
	for k in g.endg.deck.size():
		g.nav_sel = k
		await _wait(0.08)
		await _shot("3_switch_%d" % k)
		await _wait(0.35)
		await _shot("3_hover_%d" % k)
	g.nav_sel = want
	await _wait(0.4)
	await _shot("3_hover")
	g.progression.pick(want)
	await _wait(0.1)
	await _shot("4_lift")
	await _wait(0.2)
	await _shot("5_flip")
	await _wait(0.25)
	await _shot("6_reveal")
	await _wait(0.4)
	await _shot("7_face")
	await _wait(0.8)
	await _shot("8_event")
	if rec:
		await _wait(1.0)
		for i in g.choices.size():
			if str(g.choices[i].id) == "opening:1":
				g.progression.pick(i)
		await _wait(1.5)
	print("NODE SHOTS done")
	get_tree().quit(0)
