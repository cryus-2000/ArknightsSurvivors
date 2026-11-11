extends Node
## 实际出手频率实测（docs/335）：单名干员（主控）打一只不动的木桩，关掉技能，统计 rate_secs 秒内普攻出手次数与动作起手次数，
## 用来对照「面板攻速」：攻速倍率 rate_mult（op_aspd 乘数）下，出手次数应 ≈ 倍率 × 1 倍次数，且动作不得把出手挡住。
##   godot --headless --path game res://tests/atk_rate_test.tscn -- --balance --bot=afk --nodeath --seed=1 --op=<干员> --rate_op=<干员> --rate_mult=2 [--rate_secs=30 --rate_warm=2]
## 结束打印一行 ATKRATE {json}：fires（出手次数）、starts（动作起手次数）、nominal（面板名义间隔 = attack.every ÷ op_aspd，非数值时 -1）、
## act_dur（动作窗口平均）、blocked（起手瞬间仍在上一动作里的次数）、gap_max（相邻出手最大间隔）。
const Ch = preload("res://scripts/characters/character.gd")
var game: Node
var frames := 0
var op_id := ""
var mult := 1.0
var secs := 30.0
var warm := 2.0
var op = null
var dummy: Dictionary = {}
var anchor := Vector2.ZERO
var measuring := false
var done := false
var t0 := 0.0
var n0 := 0
var act0 := 0
var last_act := 0
var last_n := 0
var last_fire_t := -1.0
var gap_max := 0.0
var fire_ts: Array = []
var dur_sum := 0.0
var dur_n := 0
var cd_peak := 0.0
var prev_cd := 0.0
var cds: Array = []
var blocked := 0
var skills_on := false
var by_anim: Dictionary = {}   # act_anim → {n, dur, cd, over}：每次普攻类动作起手时记窗口与出手间隔，窗口 > 间隔 = 会把下一击挡住


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rate_op="): op_id = a.substr(10)
		elif a.begins_with("--rate_mult="): mult = float(a.substr(12))
		elif a.begins_with("--rate_secs="): secs = float(a.substr(12))
		elif a.begins_with("--rate_warm="): warm = float(a.substr(12))
		elif a == "--rate_skills": skills_on = true
	game = load("res://game.tscn").instantiate()
	add_child(game)
	game.sandbox = true


func _fires() -> int:
	return int(op.atk_n) + int(op.far_n)


func _process(_d: float) -> void:
	frames += 1
	if done:
		return
	if frames == 2:
		for o in game.squad.ops:
			if o.id == op_id:
				op = o
		if op == null:
			print("ATKRATE_ERR 干员不在编队里：" + op_id)
			done = true
			get_tree().quit()
			return
		game.stats.add(&"op_aspd", "mult", mult, "atkrate", "op:" + op_id)
		game.sync_stats()
		anchor = game.ppos
		dummy = game.spawner.spawn_enemy("bone", anchor + Vector2(50, 0))
		dummy.xp = 0.0
	if op == null:
		return
	game.hp = game.max_hp * 0.6
	game.lamp = 100.0
	game.xp = 0.0
	game.pending_levelups = 0
	game.pending_chests = 0
	game.gems.clear()
	if not skills_on:
		for i in 3:
			if not op.perm[i]:
				op.sp[i] = 0.0
	dummy.dead = false
	dummy.maxhp = 1.0e9
	dummy.hp = 1.0e9
	dummy.spd = 0.0
	dummy.dmg = 0.0
	dummy.kb = Vector2.ZERO
	dummy.pos = anchor + Vector2(50, 0)
	if game.state != game.S.PLAY:
		return
	if not measuring and game.t >= warm:
		measuring = true
		t0 = game.t
		n0 = _fires()
		act0 = op.act_n
		last_act = op.act_n
		last_n = n0
	elif measuring:
		_sample()
		if game.t >= t0 + secs:
			_finish()


func _sample() -> void:
	if op.act_n != last_act:
		if op.act_kind == "attack":
			dur_sum += op.attack_dur
			dur_n += 1
			var k: String = str(op.act_anim)
			var r: Dictionary = by_anim.get(k, {"n": 0, "dur": 0.0, "cd": 0.0, "over": 0})
			var win: float = op.attack_dur if op.attack_phased else maxf(float(op.attack_dur), 0.0)
			r.n += 1
			r.dur += win
			r.cd += op.cd
			if win > op.cd + 1.0 / 30.0:
				r.over += 1
			by_anim[k] = r
		last_act = op.act_n
	if op.cd > prev_cd + 0.0001:
		cds.append(op.cd)   # 重置当帧的冷却 ≈ 出手间隔（少扣一帧以内）
	prev_cd = op.cd
	var n := _fires()
	if n != last_n:
		if last_fire_t >= 0.0:
			gap_max = maxf(gap_max, game.t - last_fire_t)
		last_fire_t = game.t
		last_n = n


func _finish() -> void:
	done = true
	var dur: float = game.t - t0
	var a: Dictionary = op.cur_attack()
	var every = a.get("every", null)
	var nominal := -1.0
	if every is float or every is int:
		nominal = float(every) / op.stat(&"op_aspd") * float(op.loc.interval)
	var cd_avg := 0.0
	for c in cds:
		cd_avg += float(c)
	if not cds.is_empty():
		cd_avg /= cds.size()
	var rec := {"op": op_id, "mult": mult, "secs": snappedf(dur, 0.01), "aspd": snappedf(op.stat(&"op_aspd"), 0.0001),
		"fires": _fires() - n0, "starts": op.act_n - act0, "nominal": snappedf(nominal, 0.0001),
		"cd_avg": snappedf(cd_avg, 0.0001), "cd_n": cds.size(),
		"act_dur": snappedf(dur_sum / float(maxi(1, dur_n)), 0.0001), "gap_max": snappedf(gap_max, 0.001),
		"skills": skills_on, "by_anim": by_anim}
	print("ATKRATE ", JSON.stringify(rec))
	get_tree().quit()
