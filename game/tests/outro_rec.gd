extends Node
## 退场演出录帧（docs/62 §3.21c，10-28 用户「干员被击败以后加一个退场动画，再跳转到结算」；不进快检）：开窗口、--fixed-fps 30 逐帧存 rec_<帧>.png。
##   godot --fixed-fps 30 --path game res://tests/outro_rec.tscn -- --shotdir=<目录> [--win] [--touch]
## 缺省：编三人队打 2 秒后队长倒下 → 最后一击定格 + 队友化光尘 → 「探索终止」→ 结算失败入场。
## --win：把终局 Boss 刷在队长旁，登场演完 1 秒击杀 → 慢动作 + 收尾「探索完成」→ 结算胜利入场。
## --crowd：失败前 2.5 秒在四周刷一圈怪、倒下前一刻放一圈敌弹，看全画面慢放（敌人 / 弹幕 / 特效）是否跟着慢下来。

var game: Node
var frames := 0
var shot_dir := ""
var win := false
var rec_i := 0
var t0 := -1
var kill_at := -1
var end_f := 0
var crowd := false
var kill_f := 60


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			shot_dir = a.substr(10)
		elif a == "--win":
			win = true
		elif a == "--crowd":
			crowd = true
			kill_f = 150
	game = load("res://game.tscn").instantiate()
	add_child(game)


func _process(_d: float) -> void:
	frames += 1
	if frames > 2400:
		get_tree().quit(1)
	if game.state == game.S.INTRO and frames % 10 == 0:
		if game.tour.active and game.tour.has_method("finish"):
			game.tour.finish()
		game.intro_screen.close()   # 跳过开局指南
	if t0 < 0:
		if game.state != game.S.PLAY:
			return
		t0 = frames
		game.squad.add("texas", false)
		game.squad.add("lumen", false)
	var f := frames - t0
	if game.state == game.S.PLAY:
		if win or f < kill_f:
			game.hp = maxf(game.hp, game.max_hp * 0.5)   # 演出前别被打死
		if crowd and f == kill_f - 30:
			for i in 30:
				var ty: String = ["slider", "runner", "bone"][i % 3] if i < 26 else "spitter"
				game.spawner.spawn_enemy(ty, game.ppos + Vector2.from_angle(TAU * i / 30.0 + 0.2) * (300.0 + 50.0 * (i % 2)))
		if crowd and f == kill_f - 8:
			for i in 12:   # 一圈朝队长飞的敌弹（伤害 0，只为看慢放）
				var dv := Vector2.from_angle(TAU * i / 12.0)
				game.ebullets.append({"pos": game.ppos + dv * 170.0, "vel": -dv * 170.0, "dmg": 0.0, "slow": false, "r": 5.0, "life": 2.6,
					"corrode": 0.0, "nerve": 0.0, "true": false, "kind": "acid", "home": false, "src_type": "spitter"})
		if not win and f >= kill_f:
			game.meta_once_heal = []
			game.invuln = 0.0
			game.combat.hurt(game.max_hp * 10.0, true)   # 致命一击
		if win:
			if f == 20:
				var b: Dictionary = game.spawner.spawn_enemy(str(game.D.ENDINGS[game.ending].boss), game.ppos + Vector2(230, -40))
				b.age = 5.0
				game.bosses.append(b)
				game.boss = b
				game.final_boss = b
				game.boss_intro.on_spawn([b], true)
			if f > 40 and kill_at < 0 and not game.boss_intro.active():
				kill_at = f + 30
			if f == kill_at and game.final_boss != null and not game.final_boss.dead:
				game.combat.kill(game.final_boss)
	if f >= (kill_at - 15 if win else kill_f - 30) and (not win or kill_at > 0):
		get_viewport().get_texture().get_image().save_png(shot_dir + "/rec_%03d.png" % rec_i)
		rec_i += 1
	if game.state == game.S.DEAD or game.state == game.S.WIN:
		end_f += 1   # 自己计帧：切状态那一帧 state_age 还是对局里的旧值
	if end_f > (int((game.HudView.DEATH_T + 4.2) * 30.0) if game.state == game.S.DEAD else 120):
		print("OUTRO_REC frames=%d state_age=%.2f fps_eff=%.1f" % [end_f, game.state_age, end_f / maxf(0.01, game.state_age)])   # 原速核对：≈ 30
		get_tree().quit(0)
