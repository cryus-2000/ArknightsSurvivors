extends Node
## 终结技 / 连携并进左上的原型截图与录帧（10-30；不进快检）：
##   godot --fixed-fps 30 --path game --resolution 1280x720 res://tests/hud_ult_rec.tscn -- --op=<队长> --squad=<队友,…> --shotdir=<目录> [--shot] [--touch] --bal=ui/hud_ult_v=<0-3>
## 开局后冻结对局（game 的 _process 停，g.t 与界面时钟由本场景推），只改 HUD 读到的 g.ult 显示值：
##   --shot：能量满 + 协同 4 格 + 连携亮起 3 人排队（队首剩 1.6 秒），存 shot.png 后退出
##   否则录 10 秒（rec_<帧>.png）：0–5 秒能量 0 → 满（协同 0 → 4）→ 5–7 秒满条 → 7 秒连携亮起（队首倒计时 2.5 秒）→ 9.5 秒下一人顶上

const Game = preload("res://scripts/game.gd")
const UM = preload("res://scripts/ui_motion.gd")

var game: Node
var frames := 0
var dir := ""
var shot := false
var f := 0
var started := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			dir = a.substr(10)
		elif a == "--shot":
			shot = true
	DirAccess.make_dir_recursive_absolute(dir)
	game = load("res://game.tscn").instantiate()
	add_child(game)


func _mates() -> Array:
	return game.squad.ops.filter(func(o): return not o.is_leader and o.pos != Vector2.INF)


func _process(d: float) -> void:
	frames += 1
	if not started:
		if frames < 90 or game.state != Game.S.PLAY:
			if frames > 600:
				print("HUDULT never PLAY state=", game.state)
				get_tree().quit(1)
			return
		started = true
		game.set_process(false)
		game.hud.size = get_viewport().get_visible_rect().size / Cfg.ui_k
		game.tab_used = true
		game.t = 30.0
	var dt := 1.0 / 30.0
	UM.advance(dt)
	game.t += dt
	var u = game.ult
	var ms: Array = _mates()
	var now := f / 30.0
	u.queue.clear()
	if shot:
		u.energy = 100.0
		u.cells = 4
		for i in mini(3, ms.size()):
			u.queue.append({"o": ms[i], "info": {}, "t0": 0.0, "left": 1.6 if i == 0 else 2.5})
	else:
		u.energy = clampf(now / 5.0, 0.0, 1.0) * 100.0
		u.cells = mini(4, int(now / 1.2))
		if now >= 7.0:
			var k: int = 0 if now < 9.5 else 1
			for i in range(k, mini(3, ms.size())):
				var left: float = 2.5 - (now - 7.0) if i == 0 and k == 0 else (2.5 - (now - 9.5) if i == 1 and k == 1 else 2.5)
				u.queue.append({"o": ms[i], "info": {}, "t0": 0.0, "left": clampf(left, 0.0, 2.5)})
	for c in game.hud.get_children():
		if c is CanvasItem:
			c.queue_redraw()
	game.hud.queue_redraw()
	if shot:
		if f == 20:
			get_viewport().get_texture().get_image().save_png(dir + "/shot.png")
			get_tree().quit(0)
	else:
		get_viewport().get_texture().get_image().save_png(dir + "/rec_%04d.png" % f)
		if f >= 300:
			get_tree().quit(0)
	f += 1
