extends Node
## 10-24 近战队长诊断探针（德克萨斯攻击模式问题，协调人 / 用户）：和批跑同一套驱动（autotest.step + _update，高手机器人、队长单开），
## 每个 _update 采样，打到 --diag-t 秒或局终，最后打印一行 MELEEDIAG {json}：
##   win / t / lv：结果、时长、等级
##   act_frac：动作窗口（attack_t > 0，起手到收势）占时间比；atk_per_min：每分钟出手次数
##   move_frac：队长在移动（速度 > 40）占时间比；still_frac：站定（速度 < 10）占时间比
##   near_at_atk：出手那一刻攻击半径（形状半径 + 30）内的敌人数均值；zero_target_frac：出手时范围内一个敌人都没有的比例（挥空）
##   sur3_frac：120 内有 ≥3 只敌人的时间比（被围）；sur3_dmg_frac：被围时受到的伤害占总受伤比例；contact_avg：120 内敌人数均值
##   dmg_taken / dmg_taken_pm：队长总受伤（掉血量，不含回复）与每分钟
##   kills：击杀数；kills_pm
## 用法：tools/probes/melee_diag.py --op texas --seeds 8 --t 300 [--game <game 目录>]

func _ready() -> void:
	var diag_t := 300.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--diag-t="): diag_t = float(arg.get_slice("=", 1))
	var g = load("res://game.tscn").instantiate()
	add_child(g)
	for i in 5: await get_tree().process_frame
	g.set_process(false)
	var o = g.ch
	var frames := 0
	var act := 0
	var mov := 0
	var still := 0
	var sur := 0
	var contact_sum := 0
	var near_sum := 0
	var atk_ev := 0
	var zero_t := 0
	var last_atk: int = o.atk_n
	var prev_pos: Vector2 = g.ppos
	var last_hp: float = g.hp
	var taken := 0.0
	var taken_sur := 0.0
	var bal_dt: float = g.bal_dt
	while g.state == g.S.PLAY or g.state == g.S.CHOICE or g.state == g.S.LEVELUP:
		g.autotest_sys.step()
		if g.state != g.S.PLAY:
			if g.state == g.S.DEAD or g.state == g.S.WIN:
				break
			continue
		g._update(bal_dt)
		o = g.ch
		frames += 1
		if o == null:
			break
		var sp: float = g.ppos.distance_to(prev_pos) / bal_dt
		prev_pos = g.ppos
		if sp > 40.0: mov += 1
		if sp < 10.0: still += 1
		if float(o.attack_t) > 0.0: act += 1
		var n120 := 0
		for e in g.enemies:
			if not e.dead and e.pos.distance_to(g.ppos) <= 120.0:
				n120 += 1
		contact_sum += n120
		var surrounded: bool = n120 >= 3
		if surrounded: sur += 1
		if o.atk_n != last_atk:
			atk_ev += o.atk_n - last_atk
			last_atk = o.atk_n
			var r: float = 130.0
			var near: int = 0
			for e in g.enemies:
				if not e.dead and e.pos.distance_to(o.pos) <= r:
					near += 1
			near_sum += near
			if near == 0: zero_t += 1
		if g.hp < last_hp:
			taken += last_hp - g.hp
			if surrounded: taken_sur += last_hp - g.hp
		last_hp = g.hp
		if g.t >= diag_t:
			break
	var secs: float = maxf(1.0, frames * bal_dt)
	var res := {
		"op": str(o.id) if o != null else "", "win": g.state == g.S.WIN, "dead": g.state == g.S.DEAD, "t": snappedf(g.t, 0.1), "lv": g.level,
		"act_frac": snappedf(act / float(maxi(1, frames)), 0.001), "atk_per_min": snappedf(atk_ev * 60.0 / secs, 0.1),
		"move_frac": snappedf(mov / float(maxi(1, frames)), 0.001), "still_frac": snappedf(still / float(maxi(1, frames)), 0.001),
		"near_at_atk": snappedf(near_sum / float(maxi(1, atk_ev)), 0.01), "zero_target_frac": snappedf(zero_t / float(maxi(1, atk_ev)), 0.001),
		"sur3_frac": snappedf(sur / float(maxi(1, frames)), 0.001), "sur3_dmg_frac": snappedf(taken_sur / maxf(1.0, taken), 0.001),
		"contact_avg": snappedf(contact_sum / float(maxi(1, frames)), 0.01),
		"dmg_taken": snappedf(taken, 1.0), "dmg_taken_pm": snappedf(taken * 60.0 / secs, 0.1),
		"kills": g.kills, "kills_pm": snappedf(g.kills * 60.0 / secs, 0.1),
	}
	print("MELEEDIAG ", JSON.stringify(res))
	get_tree().quit()
