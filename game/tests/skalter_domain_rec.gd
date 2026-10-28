extends Node
## 浊心斯卡蒂领域录帧（10-29 用户「领域换色 + 粒子表现、去刀光、歌声命中」；不进快检）：开窗口、--fixed-fps 30 逐帧存 rec_<帧>.png。
##   队长：godot --fixed-fps 30 --path game res://tests/skalter_domain_rec.tscn -- --shotdir=<目录> --op=skalter
##   队友：godot ... -- --shotdir=<目录> --ally（队长水月，浊心入队）
## 精二，大群怪从四周围上来；第 2 秒起放一技能（领域扩大），录 9 秒。队长位置不动、只清不进领域的远处怪（保持场面）。

var game: Node
var frames := 0
var shot_dir := ""
var ally := false
var rec_i := 0
var t0 := -1
var o
const MOBS := ["runner", "bone", "stone"]


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			shot_dir = a.substr(10)
		elif a == "--ally":
			ally = true
	game = load("res://game.tscn").instantiate()
	add_child(game)


func _process(_d: float) -> void:
	frames += 1
	if frames > 2400:
		get_tree().quit(1)
	if game.state == game.S.INTRO and frames % 10 == 0:
		if game.tour.active and game.tour.has_method("finish"):
			game.tour.finish()
		game.intro_screen.close()
	if game.state != game.S.PLAY:
		return
	if t0 < 0:
		t0 = frames
		o = game.squad.add("skalter", false) if ally else game.ch
		o.elite = 2
	var f := frames - t0
	game.hp = maxf(game.hp, game.max_hp * 0.6)
	game.xp_need = 1e9   # 别升级弹选卡
	if f % 12 == 0 and f < 240 and game.enemies.size() < 70:   # 大群：从四周一圈圈刷进来
		for k in 8:
			var a: float = TAU * (k + 0.5 * (f / 12 % 2)) / 8.0
			game.spawner.spawn_enemy(MOBS[(k + f / 12) % MOBS.size()], game.ppos + Vector2.from_angle(a) * game.vrng.randf_range(330.0, 420.0))
	if f == 60:
		o.sp[0] = 999.0
		if o.is_leader:
			o.cast_manual(0)
		else:
			o.sp[0] = 999.0   # 队友：充满等自动放
	if f >= 30:
		get_viewport().get_texture().get_image().save_png(shot_dir + "/rec_%03d.png" % rec_i)
		rec_i += 1
	if f >= 30 + 270:
		print("REC frames=", rec_i, " t=", game.t)
		get_tree().quit(0)
