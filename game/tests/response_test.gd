extends Node
## 干员响应动作（docs/118）：第一批 德克萨斯（队长冲刺）/ 星熊、艾雅法拉（队长站定）/ 铃兰（队长开技能）；
## 第二批一组 能天使 / 斯卡蒂 / 推进之王（队长冲刺）/ 维什戴尔 / 流明（队长站定）/ 逻各斯 / 浊心斯卡蒂（队长开技能）。
##   godot --headless --path game res://tests/response_test.tscn -- --regression --balance --seed=1 --op=hoshiguma --squad=texas,eyjafjalla
##   godot --headless --path game res://tests/response_test.tscn -- --regression --balance --seed=1 --op=suzuran --squad=texas
##   godot --headless --path game res://tests/response_test.tscn -- --regression --balance --seed=1 --op=wisadel --squad=exusiai,skadi
##   godot --headless --path game res://tests/response_test.tscn -- --regression --balance --seed=1 --op=texas --squad=siege
##   godot --headless --path game res://tests/response_test.tscn -- --regression --balance --seed=1 --op=lumen --squad=logos,skalter
## 编队里有谁就测谁；冻结主循环，手动改队长状态后推一帧 update，只看响应有没有按条件生效。
## 全部通过时打印 "RESPONSE failures=0"。

const R = preload("res://scripts/characters/blocks/responses.gd")
const DT := 1.0 / 60.0
var game: Node
var frames := 0
var n := 0
var fails := 0


func _ready() -> void:
	game = load("res://game.tscn").instantiate()
	add_child(game)


func _process(_d: float) -> void:
	frames += 1
	if frames != 5:
		return
	set_process(false)
	game.set_process(false)
	var g = game
	g.state = g.S.PLAY
	g.invuln = 999.0
	ok(R.on(), "总开关缺省开（balance.json response.on = 1）")
	for o in g.squad.ops:
		o.elite = maxi(o.elite, 1)
		o.refresh_stats()
		o.sp = [-10000.0, -10000.0, -10000.0]
	for k in 6:
		var e: Dictionary = g.spawner.spawn_enemy("stone", g.ppos + Vector2.from_angle(TAU * k / 6.0) * 60.0)
		e.hp = 1000000.0
		e.maxhp = 1000000.0
	g.enemies_sys.build_grid()
	var tx = g.squad.get_op("texas")
	var hs = g.squad.get_op("hoshiguma")
	var ey = g.squad.get_op("eyjafjalla")
	var sz = g.squad.get_op("suzuran")
	if tx != null:
		test_texas(g, tx)
	if hs != null:
		test_hoshiguma(g, hs)
	if ey != null:
		test_eyja(g, ey)
	if sz != null:
		test_suzuran(g, sz)
	if hs != null and tx != null:
		test_stance(g, hs, tx)
	for id in ["exusiai", "skadi", "siege", "wisadel", "lumen", "logos", "skalter"]:
		var op = g.squad.get_op(id)
		if op != null:
			call("test_" + id, g, op)
	print("%d checks, %d failed" % [n, fails])
	print("RESPONSE failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		fails += 1
		printerr("FAIL: ", what)


func tick(o) -> void:
	o.update(DT)


func test_texas(g, o) -> void:
	if o.is_leader:
		return
	o.cd = 100.0
	o.tx.erase("dash")
	g.dash_t = 0.0
	tick(o)
	ok(not o.tx.has("dash"), "德克萨斯：队长没冲刺时不冲")
	g.dash_dir = Vector2.UP
	g.dash_t = 0.18
	tick(o)
	ok(o.tx.has("dash") and Vector2(o.tx.dash.dir).distance_to(Vector2.UP) < 0.01, "德克萨斯：队长冲刺起步 → 她沿同一方向（上）冲刺")
	o.tx.erase("dash")
	tick(o)
	ok(not o.tx.has("dash"), "德克萨斯：冲刺中（不是上升沿）不重复触发")
	g.dash_t = 0.0
	o.elite = 0
	o.refresh_stats()
	tick(o)
	g.dash_t = 0.18
	tick(o)
	ok(not o.tx.has("dash"), "德克萨斯：精英零不响应（同天赋解锁）")
	g.dash_t = 0.0
	o.elite = 1
	o.refresh_stats()
	# 兜底：响应刚触发过，天赋定时冲刺不该成立；距上次触发超过 talent_cd 才成立
	var C = o.ObCore
	var cond0 = o.B.talent[0].cond
	o.rsp["last"] = g.t
	ok(not C.cond_true(o, cond0), "德克萨斯：队长刚冲刺过，天赋定时冲刺不触发（resp_idle 未到）")
	o.rsp["last"] = g.t - 100.0
	ok(C.cond_true(o, cond0), "德克萨斯：队长很久没冲刺，天赋定时冲刺照旧（不触发不吃亏）")


func test_hoshiguma(g, o) -> void:
	g.leader_still_t = 0.0
	o._sustain(DT)
	var base_add: float = o.neg_add
	g.leader_still_t = 0.7
	o._sustain(DT)
	var bc: float = float(o.def.base.block_chance)
	ok(absf(o.neg_add - base_add - bc * 0.5) < 0.0001, "星熊：队长站定 0.6 秒后格挡概率 +基础值一半（%.3f → %.3f）" % [base_add, o.neg_add])
	g.leader_still_t = 0.0
	o._sustain(DT)
	ok(absf(o.neg_add - base_add) < 0.0001, "星熊：队长一移动就收盾")


func test_eyja(g, o) -> void:
	var a: Dictionary = o.B.attack
	g.leader_still_t = 0.0
	var r0: float = o.SegEyjafjalla.hw_aoe(o, a)
	g.leader_still_t = 0.7
	var r1: float = o.SegEyjafjalla.hw_aoe(o, a)
	g.leader_still_t = 3.0
	var r3: float = o.SegEyjafjalla.hw_aoe(o, a)
	ok(absf(r1 / r0 - 1.15) < 0.001 and absf(r3 / r0 - 1.15 * 1.15 * 1.15) < 0.001, "艾雅法拉：站定 0.6 / 2.6 秒爆炸范围 ×1.15 / ×1.15³（%.1f → %.1f → %.1f）" % [r0, r1, r3])
	g.leader_still_t = 0.0


func test_suzuran(g, o) -> void:
	var mate = null
	for m in g.squad.ops:
		if m != o:
			mate = m
	var sp0: float = float(mate.sp[0]) if mate != null else 0.0
	for e in g.enemies:
		e.slow = 0.0
	tick(o)
	g.leader_skill_n += 1
	g.leader_skill_i = 0
	tick(o)
	var slowed := 0
	for e in g.enemies:
		if not e.dead and float(e.slow) > 0.0:
			slowed += 1
	ok(slowed > 0, "铃兰：队长开技能 → 光域内敌人减速（%d 名）" % slowed)
	ok(mate == null or float(mate.sp[0]) > sp0 + 0.5, "铃兰：队长开技能 → 其他干员技力 +1 秒")
	tick(o)
	var slowed2: Array = g.enemies.filter(func(e): return float(e.slow) > 1.5)
	ok(slowed2.size() == slowed or slowed == 0, "铃兰：同一次开技能只触发一次")


## 指挥切换（本批没有干员用，合成一条验证共用触发器）：切到突击 → 其他干员技力 +1 秒；切回随行不触发
func test_stance(g, o, mate) -> void:
	o.B["response"] = o.B.get("response", []) + [{"_tag": "trig.on_stance", "to": "roam", "_uid": 99001, "do": [{"_tag": "verb.sp_secs", "seconds": 1.0, "_uid": 99002}]}]
	tick(o)
	var sp0: float = float(mate.sp[0])
	g.squad.set_stance(1)
	tick(o)
	ok(float(mate.sp[0]) > sp0 + 0.5, "指挥：切到突击 → 触发 on_stance(roam)")
	var sp1: float = float(mate.sp[0])
	g.squad.set_stance(0)
	tick(o)
	ok(float(mate.sp[0]) < sp1 + 0.5, "指挥：切回随行不触发 roam 那条")
	o.B.response.pop_back()


func dash(g, on: bool, o) -> void:
	g.dash_dir = Vector2.RIGHT
	g.dash_t = 0.18 if on else 0.0
	tick(o)


func hp_sum(g) -> float:
	var s := 0.0
	for e in g.enemies:
		if not e.dead:
			s += float(e.hp)
	return s


## 能天使：队长冲刺起步 → 朝队长身后（冲刺向右 = 左边）的敌人补射
func test_exusiai(g, o) -> void:
	dash(g, false, o)
	o.ext.bul = []
	dash(g, true, o)
	var n: int = o.ext.bul.size()
	var ts: Array = o.SegExusiai._exu_behind(o, 1, 300.0)
	ok(n >= 1 and not ts.is_empty() and (ts[0].pos - g.ppos).x < 0.0, "能天使：队长冲刺（向右）起步 → 补射 %d 发，目标在队长身后（左）" % n)
	o.ext.bul = []
	tick(o)
	ok(o.ext.bul.is_empty(), "能天使：冲刺中不重复补射")
	dash(g, false, o)


## 斯卡蒂：队长冲刺结束（下降沿）→ 以队长为中心横扫一周
func test_skadi(g, o) -> void:
	dash(g, true, o)
	var h0 := hp_sum(g)
	dash(g, false, o)
	ok(hp_sum(g) < h0 - 1.0, "斯卡蒂：队长冲刺结束 → 落点横扫命中（%.0f → %.0f）" % [h0, hp_sum(g)])


## 推进之王：队长冲刺结束 → 跃向队长身边最近的敌人；落地砸中 → 其他干员技力 +1 秒
func test_siege(g, o) -> void:
	if o.is_leader:
		return
	var mate = null
	for m in g.squad.ops:
		if m != o and m.skill_unlocked(0) and m.sp_need(0) > 0.0:
			mate = m
	dash(g, true, o)
	dash(g, false, o)
	var sg: Dictionary = o.hw.get("sg", {})
	ok(float(sg.get("leap_t", -1.0)) >= 0.0, "推进之王：队长冲刺结束 → 起跳")
	if mate != null:
		mate.sp[0] = 0.0
	for k in 40:
		tick(o)
	ok(float(sg.get("leap_t", 0.0)) < 0.0, "推进之王：落地")
	ok(mate == null or float(mate.sp[0]) >= 0.9, "推进之王：补锤砸中 → 其他干员技力 +1 秒（%.2f）" % (float(mate.sp[0]) if mate != null else -1.0))


## 维什戴尔：队长站定 → 攻击速度 +18%
func test_wisadel(g, o) -> void:
	g.leader_still_t = 0.0
	o._sustain(DT)
	var a0: float = o.stat(&"op_aspd")
	g.leader_still_t = 0.7
	o._sustain(DT)
	var a1: float = o.stat(&"op_aspd")
	g.leader_still_t = 0.0
	o._sustain(DT)
	ok(absf(a1 - a0 - 0.18) < 0.001 and absf(o.stat(&"op_aspd") - a0) < 0.001, "维什戴尔：站定攻速 +0.18、移动收回（%.3f → %.3f）" % [a0, a1])


## 流明：队长站定 → 荧光回复 ×1.5、灯火另 +3
func test_lumen(g, o) -> void:
	var a: Dictionary = o.B.attack
	var res := []
	for still in [0.0, 0.7]:
		g.leader_still_t = still
		g.hp = g.max_hp * 0.5
		g.corrode_pool = 0.0
		g.nerve = 0.0
		g.lamp = 10.0
		o.SegLumen._h3lm(o).heal_t = 99.0
		o.SegLumen._h3_lantern_release(o, a)
		res.append([g.hp - g.max_hp * 0.5, g.lamp - 10.0])
	g.leader_still_t = 0.0
	ok(res[0][0] > 0.0 and absf(res[1][0] / res[0][0] - 1.5) < 0.01 and absf(res[1][1] - res[0][1] - 3.0) < 0.01,
		"流明：站定时荧光回复 ×1.5（%.2f → %.2f）、灯火另 +3（%.1f → %.1f）" % [res[0][0], res[1][0], res[0][1], res[1][1]])


## 逻各斯：队长开技能 → 追加 2 枚「言」
func test_logos(g, o) -> void:
	tick(o)
	var q0: int = o.hw.word_q.size() + o.hw.bolts.size()
	g.leader_skill_n += 1
	g.leader_skill_i = 0
	tick(o)
	var q1: int = o.hw.word_q.size() + o.hw.bolts.size()
	ok(q1 - q0 >= 2, "逻各斯：队长开技能 → 追加 2 枚「言」（%d → %d）" % [q0, q1])


## 浊心斯卡蒂：队长开技能 → 歌域一圈声浪；3 秒内歌域内干员攻速 +0.1
func test_skalter(g, o) -> void:
	tick(o)   # 前面的用例改过 leader_skill_n：先吃掉这次上升沿，再清掉触发时刻
	o.rsp["last"] = g.t - 10.0
	o._sustain(DT)
	var a0: float = o.stat(&"op_aspd")
	var h0 := hp_sum(g)
	g.leader_skill_n += 1
	g.leader_skill_i = 0
	tick(o)
	o._sustain(DT)
	ok(hp_sum(g) < h0 - 1.0, "浊心斯卡蒂：队长开技能 → 声浪命中（%.0f → %.0f）" % [h0, hp_sum(g)])
	ok(absf(o.stat(&"op_aspd") - a0 - 0.1) < 0.001, "浊心斯卡蒂：之后歌域内攻速 +0.1（%.3f → %.3f）" % [a0, o.stat(&"op_aspd")])
	o.rsp["last"] = g.t - 3.5
	o._sustain(DT)
	ok(absf(o.stat(&"op_aspd") - a0) < 0.001, "浊心斯卡蒂：3 秒后攻速收回")
