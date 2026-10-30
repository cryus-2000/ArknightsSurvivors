extends Node
## 终结技并进左上（ui/hud_ult_v）+ 连携提示（ui/link_cue）原型的截图与录帧（10-30；不进快检）：
##   经 tools/godot_runner 启动（不弹窗）：godot --fixed-fps 30 --path game res://tests/hud_ult_rec.tscn -- --win=1280x720 --op=<队长> --squad=<队友,…> --shotdir=<目录> [--shot] [--touch]
##       --bal=ui/hud_ult_v=<0-3> --bal=ui/link_cue=<0-3>
## 开局后由本场景逐帧调 game._process（1/30 秒），队友每帧摆到队长两侧（引线拉得开），只改 HUD 读到的 g.ult 显示值：
##   --shot：能量满 + 协同 4 格 + 连携亮起 2 人排队（队首剩 1.6 秒），存 shot.png 后退出
##   否则录 10 秒（rec_<帧>.png）：0–4 秒能量 0 → 满（协同 0 → 4）→ 4–6 秒就绪 → 6 秒连携亮起（队首倒计时 2.5 秒）
##   → 7.6 秒按 E（队首提前离队，提示爆亮散掉）→ 下一人顶上亮起

const Game = preload("res://scripts/game.gd")
const UM = preload("res://scripts/ui_motion.gd")

var game: Node
var frames := 0
var dir := ""
var shot := false
var f := 0
var started := false
var win := Vector2i.ZERO
var win_f := -1   # 设好窗口尺寸的那一帧
const OFFS := [Vector2(120, -55), Vector2(-115, 45)]


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			dir = a.substr(10)
		elif a == "--shot":
			shot = true
		elif a.begins_with("--win="):   # 窗口实际像素（--resolution 会被游戏自己的窗口设置盖掉，开局后再设一次）
			var wh: PackedStringArray = a.substr(6).split("x")
			win = Vector2i(int(wh[0]), int(wh[1]))
	DirAccess.make_dir_recursive_absolute(dir)
	game = load("res://game.tscn").instantiate()
	add_child(game)


func _mates() -> Array:
	return game.squad.ops.filter(func(o): return not o.is_leader and o.pos != Vector2.INF)


func _redraw(n: Node) -> void:
	if n is CanvasItem:
		(n as CanvasItem).queue_redraw()
	for c in n.get_children():
		_redraw(c)


func _process(_d: float) -> void:
	frames += 1
	if not started:
		if game.state == Game.S.INTRO and frames % 10 == 0:   # 临时用户目录（godot_runner）首次进局会弹开局指南：跳过
			if game.tour.active and game.tour.has_method("finish"):
				game.tour.finish()
			game.intro_screen.close()
		# 经 tools/godot_runner 启动时窗口前 6 秒最小化（ARK_NO_FOCUS），之后在屏幕外：等它恢复再设尺寸（不改窗口模式，不弹到前台）
		if win_f < 0 and Time.get_ticks_msec() > 7000:
			if win != Vector2i.ZERO:
				get_window().content_scale_factor = 1.0
				get_window().size = win
			win_f = frames
		if win_f < 0 or frames < win_f + 30 or game.state != Game.S.PLAY:
			if frames > 3000:
				print("HUDULT never PLAY state=", game.state)
				get_tree().quit(1)
			return
		started = true
		game.set_process(false)
		game.hud.size = get_viewport().get_visible_rect().size / Cfg.ui_k
		game.tab_used = true
		game.t = 30.0
		var ms: Array = _mates()
		for i in mini(ms.size(), OFFS.size()):
			ms[i].pos = game.ppos + OFFS[i]
	var u = game.ult
	var ms: Array = _mates()
	var now := f / 30.0
	# 对局照常走一帧（1/30 秒，干员精灵按摆好的位置更新）；走之前把终结技的显示值清空：队列空 = 不会自动出连携，能量 0 = 不会自动放终结技
	u.queue.clear()
	u.energy = 0.0
	u.cells = 0
	for i in mini(ms.size(), OFFS.size()):
		ms[i].pos = game.ppos + OFFS[i]
	game._process(1.0 / 30.0)
	for i in mini(ms.size(), OFFS.size()):
		ms[i].pos = game.ppos + OFFS[i]
		ms[i].ghosts.clear()   # 每帧摆位算出的瞬时速度会留冲刺残影，清掉
	if shot:
		u.energy = 100.0
		u.cells = 4
		for i in mini(2, ms.size()):
			u.queue.append({"o": ms[i], "info": {}, "t0": 0.0, "left": 1.6 if i == 0 else 2.5})
	else:
		u.energy = clampf(now / 4.0, 0.0, 1.0) * 100.0
		u.cells = mini(4, int(now / 1.0))
		if now >= 6.0 and ms.size() > 0:
			if now < 7.6:
				u.queue.append({"o": ms[0], "info": {}, "t0": 0.0, "left": 2.5 - (now - 6.0)})
				if ms.size() > 1:
					u.queue.append({"o": ms[1], "info": {}, "t0": 0.0, "left": 2.5})
			elif ms.size() > 1:
				u.queue.append({"o": ms[1], "info": {}, "t0": 0.0, "left": maxf(0.0, 2.5 - (now - 7.6))})
	_redraw(game)
	if shot:
		if f == 20:
			get_viewport().get_texture().get_image().save_png(dir + "/shot.png")
			get_tree().quit(0)
	else:
		get_viewport().get_texture().get_image().save_png(dir + "/rec_%04d.png" % f)
		if f >= 300:
			get_tree().quit(0)
	f += 1
