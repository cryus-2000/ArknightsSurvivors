extends Node
## docs/154 翻节点卡演示录像（首通后的一局）：路口一翻卡 → 事件 → 路口二 → 9:00 终局预告。
## 队长站定、生命锁满、中 Boss 被快速削血（只为快进到路口）；录像窗口之外每帧多跑 40 步模拟快进，窗口内正常一帧一步、每 2 帧存一张 PNG。
## 选卡：路口卡 / 事件按 endings.bot_choice（--route=）停 1.3 秒再选；升级 / 宝箱等其他面板立即选第一项（不录）。
## 用法见 tools/probes/node_cards_capture.py；输出 build/<--capture-out>/f_#####.png + log.json

const UM = preload("res://scripts/ui_motion.gd")
var g
var out := ""
var n := 0
var log: Array = []
var wait := 0
var post_t := -1.0
var done := false


func _ready() -> void:
	var out_dir := "node_cards_rec"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-out="):
			out_dir = arg.get_slice("=", 1)
	out = ProjectSettings.globalize_path("res://../build/" + out_dir)
	DirAccess.make_dir_recursive_absolute(out)
	if not Cfg.endings_cleared.has("standard"):
		Cfg.endings_cleared.append("standard")   # 只在内存里：演示「首通后」的一局，不存档
	g = load("res://game.tscn").instantiate()
	add_child(g)
	for i in 5:
		await get_tree().process_frame
	g.state = g.S.PLAY
	g.show_queue.clear()
	g.endg.enabled = true
	g.endg._checked = true


func _window() -> bool:
	var E = g.endg
	if g.state == g.S.CHOICE and (g.choice_kind == "cross" or g.choice_kind == "event"):
		return true
	if E.cross_due > 0 or (E.clear_t >= 0.0 and E.cross_done < 2):
		return true   # 中 Boss 刚倒下、路口卡还没弹的那 2 秒
	if g.t <= post_t:
		return true
	return g.t >= 535.0 and g.t <= 546.0


func _keep_alive() -> void:
	g.hp = g.max_hp
	for b in g.bosses:
		if not b.dead and not b.invuln and g.final_boss == null:
			b.hp -= 60.0
			if b.hp <= 0.0:
				g.combat.kill(b)


func _process(_dt: float) -> void:
	if g == null or done or g.state == g.S.INTRO:
		if g != null and g.state == g.S.INTRO:
			g.state = g.S.PLAY
		return
	_keep_alive()
	if g.state == g.S.SHOW:
		g.state = g.S.PLAY   # 精英化 / 入队演出：直接回到战斗
	if g.state == g.S.CHOICE:
		if g.choice_kind == "cross" or g.choice_kind == "event":
			post_t = g.t + 2.5
			if g.choice_kind == "cross" and g.endg.flipped >= 0:
				wait = 0   # 翻面中：等计时器兑现
			else:
				wait += 1
				if wait > 80:
					wait = 0
					g.progression.pick(g.endg.bot_choice())
		else:
			g.progression.pick(0)
	elif not _window():
		# 快进：多跑几步模拟，进窗口或弹面板就停
		for k in 40:
			if g.state != g.S.PLAY or _window():
				break
			_keep_alive()
			g._update(1.0 / 60.0)
	if g.t > 546.0:
		done = true
		var f := FileAccess.open(out.path_join("log.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify(log))
		f.close()
		print("NODE CARDS CAPTURE done frames=%d" % n)
		get_tree().quit(0)
		return
	if _window() and Engine.get_process_frames() % 2 == 0:
		await RenderingServer.frame_post_draw
		var im := get_viewport().get_texture().get_image()
		im.save_png(out.path_join("f_%05d.png" % n))
		var panel: bool = g.state == g.S.CHOICE
		log.append({"n": n, "t": snappedf(g.t, 0.01), "kind": g.choice_kind if panel else "", "title": g.panel_title_text if panel else "",
			"cross": g.endg.cross_done, "ending": g.endg.cur})
		n += 1
