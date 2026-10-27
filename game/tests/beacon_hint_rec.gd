extends Node
## 引航灯标提醒录帧（10-28 用户「灯塔还没被激活时加提醒」；不进快检）：开窗口、--fixed-fps 30 逐帧存 rec_<帧>.png。
##   godot --fixed-fps 30 --path game res://tests/beacon_hint_rec.tscn -- --shotdir=<目录> --nodeath
## 脚本：灯标在屏外出现（出现横幅 + 屏边指示）→ 队长走近（画面内头顶小箭头 + 灯室琥珀呼吸光）→ 站进光圈点燃 →
## 另一座远处灯标没人点、到期熄灭（横幅「远处的引航灯标熄灭了」）。队长位置由脚本直接写（不读输入），只为录像。

var game: Node
var frames := 0
var shot_dir := ""
var rec_i := 0
var t0 := -1
var target := Vector2.ZERO
var start := Vector2.ZERO


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			shot_dir = a.substr(10)
	game = load("res://game.tscn").instantiate()
	add_child(game)


func _spawn_at(p: Vector2) -> Dictionary:
	game.beacon_sys._spawn()
	var b: Dictionary = game.beacons[game.beacons.size() - 1]
	b.pos = p
	return b


func _process(_d: float) -> void:
	frames += 1
	if frames > 900 and t0 < 0:
		get_tree().quit(1)
	if game.state == game.S.INTRO and frames % 10 == 0:
		if game.tour.active and game.tour.has_method("finish"):
			game.tour.finish()
		game.intro_screen.close()   # 跳过开局指南
	if game.state != game.S.PLAY:
		return
	if t0 < 0:
		t0 = frames
		game.beacon_sys.next_at = 1e9   # 不自然刷，只用脚本刷的
		game.enemies.clear()
	var f := frames - t0
	game.enemies.clear()   # 录像只看灯标：清掉杂兵
	if f == 20:
		start = game.ppos
		target = game.ppos + Vector2(760, -120)
		_spawn_at(target)
	if f >= 110 and f < 230:
		game.ppos = start.lerp(target + Vector2(-10, 20), clampf((f - 110) / 120.0, 0.0, 1.0))
	if f >= 230 and f < 330:
		game.ppos = target + Vector2(-10, 20)
	if f == 340:
		var b := _spawn_at(game.ppos + Vector2(-1100, 420))
		b.age = 45.0 - 1.2   # 快到期：没人点，熄灭横幅
	if f > 2 and f <= 540:
		get_viewport().get_texture().get_image().save_png(shot_dir + "/rec_%03d.png" % rec_i)
		rec_i += 1
	if f > 540:
		get_tree().quit(0)
