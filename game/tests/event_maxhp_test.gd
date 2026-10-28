extends Node
## 事件「狂徒妄念 · 愤怒」（队长最大生命 -10%，骑士入队）回归（10-28 用户：选完掉到只剩一滴血）。
## 1 选项面板打开期间局内暂停：贴身敌人、侵蚀池、计时都不动，选完生命 = min(选前生命, 新上限)；
## 2 非满血 / 带生命加成（成长、入队台阶）时选：上限按比例 × 0.9，当前生命只截到新上限，不按旧上限换算；
## 3 骑士入队与编队重算（refresh_squad / sync_stats）不改当前生命；
## 4 关面板后 protect/panel_grace（0.8）秒保护（10-28 用户定 A）：8 只贴身怪的接触伤害在保护内为 0、之后恢复；升级选卡不给保护。
##   --bal=protect/panel_grace=0 跑同一场景做改前对照（只打印 PANEL GRACE 行，不判保护项）
const Bal = preload("res://scripts/core/balance.gd")
var game: Node
var frames := 0
var fails := 0
var step := 0
var hp0 := 0.0
var max0 := 0.0
var t0 := 0.0
var pool0 := 0.0
var mob_pos: Array = []
var tpick := 0.0
var c0 := 0.0


func _ready() -> void:
	game = load("res://game.tscn").instantiate()
	add_child(game)


func check(v: bool, label: String) -> void:
	if not v:
		fails += 1
		push_error(label)
		print("FAIL ", label, " hp=%.2f max=%.2f" % [game.hp, game.max_hp])


func _prep() -> void:
	game.pending_levelups = 0
	game.pending_chests = 0
	game.show_queue.clear()
	game.endg.all_unlocked = true
	game.state = game.S.PLAY
	game.t = 250.0


func _open_madness() -> void:
	game.endg.open("madness")


func _pick_anger() -> void:
	for i in game.choices.size():
		if str(game.choices[i].id) == "madness:0":
			game.progression.pick(i)
			return
	check(false, "madness:0 offered")


## 情况 2 / 3：不跑帧，直接比较选前选后
func _case_ratio(frac: float, extra_hp: float, members: int, label: String) -> void:
	game.queue_free()
	game = load("res://game.tscn").instantiate()
	add_child(game)
	game.set_process(false)
	_prep()
	if extra_hp > 0.0:
		game.stats.add(&"max_hp", "add", extra_hp, "test_growth")
		game.sync_stats()
	for id in ["gladiia", "texas", "angelina"].slice(0, members):
		game.squad.add(id)
	game.rfx.refresh_squad()
	game.hp = game.max_hp * frac
	var h := float(game.hp)
	var m := float(game.max_hp)
	_open_madness()
	_pick_anger()
	check(absf(game.max_hp - m * 0.9) < 0.5, label + ": max hp × 0.9 (%.1f → %.1f)" % [m, game.max_hp])
	check(absf(game.hp - minf(h, game.max_hp)) < 0.01, label + ": hp only clamped to new max (%.1f → %.1f)" % [h, game.hp])
	check(game.knight.alive, label + ": knight joined")
	var h2 := float(game.hp)
	game.rfx.refresh_squad()
	game.sync_stats()
	check(absf(game.hp - h2) < 0.01, label + ": squad / stat recompute keeps hp")


func _contact() -> float:
	var s := 0.0
	for k in game.dmg_log:
		if str(k).begins_with("contact"):
			s += float(game.dmg_log[k])
	return s


func _grace() -> float:
	return Bal.v("protect/panel_grace", 0.8)


func _process(_dt: float) -> void:
	frames += 1
	if frames == 5:
		# 情况 1：面板期间暂停。60% 生命、8 只敌人贴身、侵蚀池里有量
		_prep()
		game.hp = game.max_hp * 0.6
		for k in 8:
			var e: Dictionary = game.spawner.spawn_enemy("slider", game.ppos + Vector2.from_angle(k * TAU / 8.0) * 6.0)
			e.dormant = false
		game.corrode_pool = game.max_hp * 0.2
		hp0 = game.hp
		max0 = game.max_hp
		_open_madness()
		check(game.state == game.S.CHOICE, "event panel pauses (state CHOICE)")
		t0 = game.t
		pool0 = game.corrode_pool
		mob_pos = game.enemies.map(func(e): return e.pos)
		step = 1
	elif step == 1 and frames == 95:
		check(absf(game.hp - hp0) < 0.01, "no hp loss while event panel is open (%.1f → %.1f)" % [hp0, game.hp])
		check(game.t == t0, "run clock frozen while panel open")
		check(absf(game.corrode_pool - pool0) < 0.01, "corrode pool does not drain while panel open")
		var moved := false
		for i in mini(mob_pos.size(), game.enemies.size()):
			moved = moved or (game.enemies[i].pos as Vector2).distance_to(mob_pos[i]) > 0.5
		check(not moved, "enemies frozen while panel open")
		_pick_anger()
		check(game.state == game.S.PLAY, "panel closes after pick")
		check(absf(game.max_hp - max0 * 0.9) < 0.5, "pause case: max hp × 0.9")
		check(absf(game.hp - minf(hp0, game.max_hp)) < 0.01, "pause case: hp = min(old hp, new max) (%.1f → %.1f)" % [hp0, game.hp])
		tpick = game.t
		c0 = _contact()
		step = 2
	elif step == 2 and game.t >= tpick + _grace() - 0.05:
		var cg := _contact() - c0
		if _grace() > 0.0:
			check(cg <= 0.0, "no contact damage during panel grace (%.1f)" % cg)
			check(game.panel_grace_until > game.t, "grace ring still showing")
		step = 3
	elif step == 3 and game.t >= tpick + 2.0:
		var c2 := _contact() - c0
		print("PANEL GRACE grace=%.2f contact_2s=%.1f hp_left=%.1f/%.1f" % [_grace(), c2, game.hp, game.max_hp])
		check(c2 > 0.0, "contact damage resumes after grace")
		# 升级选卡关闭不给保护
		game.pending_levelups = 1
		game.check_pending()
		if game.state == game.S.CHOICE:
			var g0: float = game.panel_grace_until
			game.progression.pick(0)
			check(game.panel_grace_until == g0, "level-up pick gives no panel grace")
		step = 4
	elif step == 4:
		game.set_process(false)
		_case_ratio(1.0, 0.0, 0, "full hp")
		_case_ratio(0.6, 0.0, 0, "60% hp")
		_case_ratio(0.3, 0.0, 0, "30% hp")
		_case_ratio(0.6, 0.3, 2, "60% hp + growth + 2 members")
		_case_ratio(0.3, 0.3, 3, "30% hp + growth + 3 members")
		print("EVENT MAXHP TEST: ", fails, " failures")
		get_tree().quit(fails)
