extends Node
## 干员连携技（docs/160）：真实对局里直接让施放者 spend_sp，看搭档的合击动作、冷却、上限、总开关、队长不位移、集群狩猎。
## godot --headless --path game res://tests/synergy_test.tscn -- --regression --balance --seed=1 --op=texas --squad=exusiai,lappland
##                                                              --op=skadi --squad=ulpianus,gladiia   （集群狩猎，编队上限 3）
##                                                              --op=ulpianus --squad=skadi                            （两人：手段应当有效）
##                                                              --op=gladiia --squad=ulpianus                          （战争设计：控场 → 收割）
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
	elif ids.has("gladiia") and ids.has("ulpianus"):
		await scene_cast()
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
	# 控场 → 收割：德克萨斯剑雨（S1）后，能天使技能就绪就放，没就绪才打弹
	g.squad.syn.cd.clear()
	step(0.2)
	ex.sp = [0.0, 0.0, 0.0]
	var ec0: int = int(g.telemetry.op_casts.get("exusiai", 0))
	var ehp0: float = e.hp
	e.stun = 3.0
	tx.spend_sp(0)
	step(1.6)
	ok(int(g.telemetry.op_casts.get("exusiai", 0)) == ec0 and e.hp < ehp0, "能天使技能没就绪：打了一轮弹、没放技能（casts %d）" % ec0)
	g.squad.syn.cd.clear()
	step(0.3)
	ex.ammo[0] = 0   # S1 之前被「能天使放技能」那一段点过、还在装填状态：清掉强力弹，技力满格
	ex.sp = [ex.sp_need(0), 0.0, 0.0]
	ex.pos = g.ppos + Vector2(90.0, 10.0)   # 站到敌人的技能门槛（攻击射程）以内：门槛不够的搭档本来就不放
	tx.spend_sp(0)
	step(1.6)
	ok(int(g.telemetry.op_casts.get("exusiai", 0)) > ec0, "能天使技能就绪：对被晕的怪放了技能（casts %d → %d）" % [ec0, int(g.telemetry.op_casts.get("exusiai", 0))])
	# 没有目标不触发、不进冷却
	e.dead = true
	g.enemies_sys.build_grid()
	n1 = int(g.squad.syn.n)
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
	# 控场 → 收割：乌尔比安 S1 后，斯卡蒂技能就绪才放
	g.squad.syn.cd.clear()
	step(0.3)
	sk.sp = [sk.sp_need(0), 0.0, 0.0]
	var kc0: int = int(g.telemetry.op_casts.get("skadi", 0))
	ul.spend_sp(0)
	step(1.8)
	ok(int(g.telemetry.op_casts.get("skadi", 0)) > kc0, "斯卡蒂技能就绪：冲向聚怪中心放了技能（casts %d → %d）" % [kc0, int(g.telemetry.op_casts.get("skadi", 0))])
	step(3.0)
	# 反方向：斯卡蒂放技能 → 乌尔比安是队长，dash_strike 跳过
	g.squad.syn.cd.clear()
	var n0: int = int(g.squad.syn.n)
	sk.spend_sp(0)
	step(0.3)
	ok(int(g.squad.syn.n) == n0 and ul.syn_mv.is_empty(), "队长当搭档时不位移：不触发")


## R6 战争设计（控场 → 收割）：歌蕾蒂娅 S3 聚怪 → 乌尔比安冲向聚怪中心；技能就绪就放，没就绪打一次冲锋重击（不回技力、不白送技能）
func scene_cast() -> void:
	var gl = g.squad.get_op("gladiia")
	var ul = g.squad.get_op("ulpianus")
	ok(gl.is_leader and not ul.is_leader, "歌蕾蒂娅是队长、乌尔比安是队友")
	for k in 3:
		foe(g.ppos + Vector2(230.0 + 18.0 * k, -20.0 + 20.0 * k))
	await get_tree().process_frame
	var sp0: Array = [ul.sp[0], ul.sp[1], ul.sp[2]]
	var hp_sum0 := 0.0
	for e in g.enemies:
		hp_sum0 += float(e.hp)
	# ① 乌尔比安技能没就绪：冲锋重击
	ul.sp = [0.0, 0.0, 0.0]
	var casts0: int = int(g.telemetry.op_casts.get("ulpianus", 0))
	gl.spend_sp(2)
	var moved: Dictionary = step(1.6, [ul])
	ok(g.squad.syn.cd.has("zhansheji"), "歌蕾蒂娅放 S3 → 战争设计触发")
	ok(float(moved[ul.id]) > 60.0, "乌尔比安冲向聚怪中心（%.0f）" % float(moved[ul.id]))
	var hp_sum1 := 0.0
	for e in g.enemies:
		hp_sum1 += float(e.hp)
	ok(hp_sum1 < hp_sum0, "冲锋重击伤到了敌人")
	ok(int(g.telemetry.op_casts.get("ulpianus", 0)) == casts0 and ul.sp[0] < ul.sp_need(0) * 0.5, "技能没就绪：乌尔比安没放技能、也没被送技力（casts %d，S1 技力 %.1f / %.1f）" % [casts0, ul.sp[0], ul.sp_need(0)])
	step(3.0)
	# ② 乌尔比安 S1 就绪：冲过去后对准这群怪放出去
	g.squad.syn.cd.clear()
	ul.sp = [ul.sp_need(0), 0.0, 0.0]
	casts0 = int(g.telemetry.op_casts.get("ulpianus", 0))
	gl.spend_sp(2)
	step(1.6, [ul])
	ok(int(g.telemetry.op_casts.get("ulpianus", 0)) > casts0, "技能就绪：乌尔比安真的放了技能（casts %d → %d）" % [casts0, int(g.telemetry.op_casts.get("ulpianus", 0))])
	step(3.0)
	ok(ul.syn_mv.is_empty() and g.squad.syn.acts.is_empty(), "收势后位移解除")
	# ③ 乌尔比安是队长：不位移、不替玩家放技能
	ul.is_leader = true
	gl.is_leader = false
	g.squad.syn.cd.clear()
	var n0: int = int(g.squad.syn.n)
	ul.sp = [ul.sp_need(0), 0.0, 0.0]
	gl.spend_sp(2)
	step(0.5)
	ok(int(g.squad.syn.n) == n0 and ul.syn_mv.is_empty(), "乌尔比安是队长：不触发、不位移（技能由玩家 / 他自己的自动规则放，连携不替放）")
