extends Node
## 成长即时生效测试（docs/36）：godot --headless --path game res://tests/node_test.tscn -- --balance --seed=1 --op=<id>
## 把 game.tscn 当子节点跑起来，第 5 帧对主控干员逐个应用成长线节点，记录「选下这张卡的那一刻」干员身上有什么变了：
##   脚本变量（布尔 / 数值 / 字符串）、按本干员作用域取的全部属性值、三个技能是否解锁。
## 每个节点打印一行 NODE：imm = advance() 之后立刻变化的项，sync = 下一帧属性同步后才变化的项。
## 一个节点两边都是空的 = 选了卡当下没有任何效果（2026-09-26 用户反馈：乌尔比安 / 水月「选的天赋当下没效果、以后才有」）。
## 再对博士 / 全队被动卡（doctor.PASSIVES）逐个 apply_passive，看全队属性是否当场变化，打印 PASSIVE 行。
##
## --effecttest=K：主控推进 K 个节点后停在那里（不再升级、技力常满）跑约 40 秒，打印 EFFECT 行（各伤害来源的占比），
## 用来确认「这个节点选下之后当下就在打」——例如 K=5 时精二还没解锁，N5 的伤害来源必须出现。

const IGNORE := ["voice_t", "aura_t", "cd", "t"]
var game: Node
var frames := 0
var done := false


func _ready() -> void:
	game = load("res://game.tscn").instantiate()
	add_child(game)


var effect_k := -1


func _process(_d: float) -> void:
	frames += 1
	if effect_k < 0:
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--effecttest="):
				effect_k = int(a.substr(13))
		if effect_k < 0:
			effect_k = 999
	if effect_k != 999:
		_effect_step()
		return
	if frames == 5 and not done:
		done = true
		_run()
		get_tree().quit()


func _effect_step() -> void:
	var o = game.squad.leader()
	if frames == 5:
		for k in effect_k:
			o.advance("")
		game.dmg_out.clear()
	if frames < 5:
		return
	# 停在这一阶段：不升级、不招募；技力常满（只充已解锁的）
	game.xp = 0.0
	game.pending_levelups = 0
	if frames % 6 == 0:
		o.fill_sp()
	if frames == 85:
		var tot := 0.0
		for k in game.dmg_out:
			tot += game.dmg_out[k]
		var parts: Array = []
		for k in game.dmg_out:
			parts.append("%s %d%%" % [k, int(round(100.0 * game.dmg_out[k] / maxf(tot, 1.0)))])
		print("EFFECT %s k=%d elite=%d prog=%d | %s" % [o.id, effect_k, o.elite, o.prog, "  ".join(parts)])
		get_tree().quit()


func _snap(o) -> Dictionary:
	var s := {}
	for p in o.get_property_list():
		if not (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or p.name in IGNORE:
			continue
		var v = o.get(p.name)
		match typeof(v):
			TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
				s["var:" + p.name] = v
	for st in game.stats.stats():
		s["stat:" + str(st)] = snappedf(game.stats.value_for(st, o.scopes()), 0.0001)
	for i in 3:
		s["skill%d" % (i + 1)] = o.skill_unlocked(i)
		s["sp%d" % (i + 1)] = snappedf(o.sp[i], 0.01)
	# 博士 / 全局同步变量
	for k in ["max_hp", "regen", "armor", "dodge", "speed", "pickup", "lamp_decay", "sp_mult", "shield_max"]:
		s["g:" + k] = snappedf(float(game.get(k)), 0.0001)
	return s


func _diff(a: Dictionary, b: Dictionary) -> Array:
	var out: Array = []
	for k in b:
		if not a.has(k) or a[k] != b[k]:
			out.append("%s %s→%s" % [k, str(a.get(k, "-")), str(b[k])])
	return out


func _run() -> void:
	var o = game.squad.leader()
	print("NODETEST op=%s prog=%d elite=%d" % [o.id, o.prog, o.elite])
	var k := 0
	while not o.next_node().is_empty() and k < 12:
		k += 1
		var n: Dictionary = o.next_node()
		var s0 := _snap(o)
		o.advance("")
		var s1 := _snap(o)
		game._sync_stats()
		var s2 := _snap(o)
		var imm := _diff(s0, s1).filter(func(x): return not x.begins_with("var:prog") and not x.begins_with("var:node_lv") and not x.begins_with("stat:op_atk"))
		var syn := _diff(s1, s2)
		print("NODE %s %d %s %s | imm: %s | sync: %s" % [o.id, o.prog, n.get("type", ""), str(n.get("id", n.get("level", ""))), "; ".join(imm), "; ".join(syn)])
	# 博士 / 全队被动卡
	for pid in game.doctor.PASSIVES:
		var s0 := _snap(o)
		game.doctor.apply_passive(pid)
		var s1 := _snap(o)
		game._sync_stats()
		var s2 := _snap(o)
		print("PASSIVE %s | imm: %s | sync: %s" % [pid, "; ".join(_diff(s0, s1)), "; ".join(_diff(s1, s2))])
