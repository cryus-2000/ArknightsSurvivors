extends Node
## 干员连携技（docs/160）：真实对局里直接让施放者 spend_sp，看搭档的合击动作、冷却、上限、总开关、队长不位移、集群狩猎。
## godot --headless --path game res://tests/synergy_test.tscn -- --regression --balance --seed=1 --op=texas --squad=exusiai,lappland
##                                                              --op=skadi --squad=ulpianus,gladiia   （集群狩猎，编队上限 3）
##                                                              --op=ulpianus --squad=skadi                            （两人：手段应当有效）
## 全部通过时打印 "SYNERGY checks=N failures=0"

const Bal = preload("res://scripts/core/balance.gd")
var checks := 0
var failures := 0
var g


func ok(v: bool, what: String) -> void:
	checks += 1
	if not v:
		failures += 1
		printerr("FAIL: ", what)


func _ready() -> void:
	g = load("res://game.tscn").instantiate()
	add_child(g)
	for i in 5: await get_tree().process_frame
	g.set_process(false)
	g.mode = g.Mode.PLAY
	g.state = g.S.PLAY
	g.sandbox = true
	g.t = 60.0
	g.xp_need = 1000000000.0
	for e in g.enemies: e.dead = true
	g.enemies.clear()
	ok(Bal.vi("synergy/on", 0) == 1, "synergy/on 缺省 1")
	var ids: Array = g.squad.ids()
	if ids.has("texas") and ids.has("exusiai") and ids.has("lappland"):
		await scene_texas()
	elif ids.has("gladiia") and ids.has("ulpianus") and ids.has("skadi"):
		await scene_hunters()
	elif ids.has("skadi") and ids.has("ulpianus"):
		await scene_pair()
	else:
		ok(false, "测试编队不对：%s" % [ids])
	print("SYNERGY checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func foe(at: Vector2) -> Dictionary:
	var e: Dictionary = g.spawner.spawn_enemy("bone", at)
	e.hp = 1.0e7
	e.maxhp = 1.0e7
	e.spd = 0.0
	g.enemies_sys.build_grid()   # 先建网格：nearest_enemies 查的是网格
	return e


func step(secs: float, track: Array = []) -> Dictionary:
	var out := {}
	for k in track:
		out[k.id] = 0.0
	for i in int(secs * 60.0):
		g.hp = g.max_hp
		g.enemies_sys.build_grid()
		g._update(1.0 / 60.0)
		for k in track:
			var slot: Vector2 = g.ppos + g.squad._slot_offset(k.slot)
			out[k.id] = maxf(out[k.id], k.pos.distance_to(slot))
	return out


func scene_texas() -> void:
	var tx = g.squad.get_op("texas")
	var ex = g.squad.get_op("exusiai")
	var lap = g.squad.get_op("lappland")
	ok(tx.is_leader, "德克萨斯是队长")
	var e := foe(g.ppos + Vector2(230.0, 0.0))
	await get_tree().process_frame
	var hp0: float = e.hp
	tx.spend_sp(0)
	var moved: Dictionary = step(1.0, [lap, ex])
	ok(g.squad.syn.cd.has("moqi") and g.squad.syn.cd.has("enyuan"), "默契 / 恩怨 都进入冷却")
	ok(e.hp < hp0, "合击伤害落在目标上（hp %.0f → %.0f）" % [hp0, e.hp])
	ok(float(moved[lap.id]) > 60.0, "拉普兰德真的冲出去了（离编队位最远 %.0f）" % float(moved[lap.id]))
	ok(float(moved[ex.id]) < 30.0, "能天使原地打弹，不位移（%.0f）" % float(moved[ex.id]))
	var tr: Dictionary = step(2.5, [lap])
	ok(g.squad.syn.acts.is_empty(), "合击做完，进行中的清空")
	var slot: Vector2 = g.ppos + g.squad._slot_offset(lap.slot)
	ok(lap.syn_mv.is_empty() and lap.pos.distance_to(slot) < 80.0, "拉普兰德回到编队位附近（%.0f）" % lap.pos.distance_to(slot))
	# 冷却：马上再放一次不触发
	var n0: int = int(g.squad.syn.n)
	tx.spend_sp(0)
	step(0.2)
	ok(int(g.squad.syn.n) == n0, "冷却内不再触发")
	# 总开关
	Bal._data["synergy"]["on"] = 0
	g.squad.syn.cd.clear()
	tx.spend_sp(0)
	step(0.3)
	ok(int(g.squad.syn.n) == n0 and g.squad.syn.acts.is_empty(), "synergy/on = 0 完全不触发")
	Bal._data["synergy"]["on"] = 1
	# 反方向：能天使放技能 → 德克萨斯（队长）不位移，所以 dash_strike 跳过；R2 反方向要拉普兰德放技能 → 德克萨斯是队长，同样跳过
	g.squad.syn.cd.clear()
	var n1: int = int(g.squad.syn.n)
	ex.spend_sp(0)
	step(0.3)
	ok(int(g.squad.syn.n) == n1 and tx.syn_mv.is_empty(), "队长当搭档时不位移：能天使放技能不触发德克萨斯的冲刺")
	# 没有目标不触发、不进冷却
	e.dead = true
	g.enemies_sys.build_grid()
	g.squad.syn.cd.clear()
	tx.spend_sp(0)
	step(0.2)
	ok(int(g.squad.syn.n) == n1 and g.squad.syn.cd.is_empty(), "没有敌人不触发、不进冷却")


func scene_hunters() -> void:
	var sk = g.squad.get_op("skadi")
	var ul = g.squad.get_op("ulpianus")
	var gl = g.squad.get_op("gladiia")
	ok(sk.is_leader, "斯卡蒂是队长")
	var e := foe(g.ppos + Vector2(240.0, 20.0))
	await get_tree().process_frame
	var hp0: float = e.hp
	sk.spend_sp(0)
	var moved: Dictionary = step(1.0, [ul, gl])
	ok(g.squad.syn.cd.has("jiqun") and not g.squad.syn.cd.has("chaoxi") and not g.squad.syn.cd.has("shouduan"), "猎人 ≥ 3 人：集群狩猎取代两人连携")
	ok(float(moved[ul.id]) > 50.0 and float(moved[gl.id]) > 50.0, "两名队友猎人都冲向同一个目标（%s）" % [moved])
	ok(e.hp < hp0, "合击伤害落在目标上")
	ok(float(e.get("frag_v", 0.0)) >= 0.06 and float(e.get("frag_t", 0.0)) > g.t, "目标被集群狩猎标记（受伤加成）")
	step(3.0)
	ok(g.squad.syn.acts.is_empty() and ul.syn_mv.is_empty() and gl.syn_mv.is_empty(), "全部收势、位移解除")
	ok(sk.pos.distance_to(g.ppos) < 1.0, "队长没被推着走")


func scene_pair() -> void:
	var sk = g.squad.get_op("skadi")
	var ul = g.squad.get_op("ulpianus")
	ok(ul.is_leader, "乌尔比安是队长")
	var e := foe(g.ppos + Vector2(230.0, 0.0))
	await get_tree().process_frame
	var hp0: float = e.hp
	ul.spend_sp(0)
	var moved: Dictionary = step(1.0, [sk])
	ok(g.squad.syn.cd.has("shouduan"), "乌尔比安放技能 → 手段应当有效触发")
	ok(float(moved[sk.id]) > 60.0, "斯卡蒂真的冲出去了（%.0f）" % float(moved[sk.id]))
	ok(e.hp < hp0, "合击伤害落在目标上")
	step(3.0)
	ok(g.squad.syn.acts.is_empty() and sk.syn_mv.is_empty(), "收势后位移解除")
	# 反方向：斯卡蒂放技能 → 乌尔比安是队长，dash_strike 跳过
	g.squad.syn.cd.clear()
	var n0: int = int(g.squad.syn.n)
	sk.spend_sp(0)
	step(0.3)
	ok(int(g.squad.syn.n) == n0 and ul.syn_mv.is_empty(), "队长当搭档时不位移：不触发")
