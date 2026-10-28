extends Node
## 归溟幽灵鲨二技能「操作替身」录帧（10-29 用户「二技能改成操作替身」；不进快检）：开窗口、--fixed-fps 30 逐帧存 rec_<帧>.png。
##   godot --fixed-fps 30 --path game res://tests/specter_s2_rec.tscn -- --shotdir=<目录> --op=specter_unchained
## 她当队长：放二技能 → 技能剩余压到 2 秒（录像省时）→ 倒下 → 替身现身，队长位置由脚本绕圈移动（= 玩家在操控替身）→ 替身 12 秒到期 → 本体归位。

var game: Node
var frames := 0
var shot_dir := ""
var rec_i := 0
var t0 := -1
var o
var c0 := Vector2.ZERO
var doll_end := -1


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			shot_dir = a.substr(10)
	game = load("res://game.tscn").instantiate()
	add_child(game)


func _process(_d: float) -> void:
	frames += 1
	if frames > 3000:
		get_tree().quit(1)
	if game.state == game.S.INTRO and frames % 10 == 0:
		if game.tour.active and game.tour.has_method("finish"):
			game.tour.finish()
		game.intro_screen.close()
	if game.state != game.S.PLAY:
		return
	if t0 < 0:
		t0 = frames
		o = game.ch   # 用 --op=specter_unchained 启动：她就是队长
		o.elite = 2
		c0 = game.ppos
	var f := frames - t0
	game.hp = maxf(game.hp, game.max_hp * 0.6)
	if f == 60:
		o.sp[1] = 999.0
		print("REC cast=", o.cast_manual(1))
	if f == 75:
		o.s_t[1] = minf(o.s_t[1], 2.0)
	var away: bool = o != null and o.away()
	if away:
		var a: float = float(f) * 0.035   # 玩家操控替身：绕一个大圈走
		game.ppos = c0 + Vector2(cos(a) * 180.0 - 180.0, sin(a) * 110.0)
	elif doll_end < 0 and f > 120 and o != null and o.hw.has("sp") and float(o.hw.sp.doll_t) <= 0.0 and float(o.hw.sp.fall_t) <= 0.0 and f > 200:
		doll_end = f
	if f >= 40:
		get_viewport().get_texture().get_image().save_png(shot_dir + "/rec_%03d.png" % rec_i)
		rec_i += 1
	if doll_end > 0 and f > doll_end + 75:
		print("REC frames=", rec_i, " t=", game.t)
		get_tree().quit(0)
