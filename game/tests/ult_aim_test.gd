extends Node
## 终结技慢动作瞄准 v2（docs/209 §3，ult/aim）：按 Q 进入 0.3 倍慢动作、录片计划把落点挪过去、轻点后保持瞄准再按 Q 释放、
## 按住到 aim_max 自动释放、自身周围类不停留、开关 0 回旧路径。
## godot --headless --path game res://tests/ult_aim_test.tscn -- --regression --balance --seed=1 --op=texas --ultaim
## 全部通过时打印 "ULT AIM checks=N failures=0"

const Bal = preload("res://scripts/core/balance.gd")
const Aim = preload("res://scripts/run/ult_aim.gd")

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
	g.bot = null   # 机器人局不走 v2（同 seed 不变）；这里测玩家输入路径
	var u = g.ult
	ok(u != null, "终结技框架开着")
	if u == null:
		_done()
		return
	var ld = g.squad.leader()
	for k in 12:
		var e: Dictionary = g.spawner.spawn_enemy("bone", g.ppos + Vector2.from_angle(TAU * k / 12.0) * 300.0)
		e.hp = 1.0e9
		e.maxhp = 1.0e9
		e.spd = 0.0
	var dt := 1.0 / 60.0
	var step := func(n: int) -> void:
		for f in n:
			g.hp = g.max_hp
			g.enemies_sys.build_grid()
			g._update(dt)
	# 1. 进入瞄准：v2、0.3 倍、上限 1.5 × 0.3 游戏秒
	ok(Aim.on(u), "--ultaim 时 autotest 也走 v2")
	u.energy = u.FULL
	ok(u.press_q(), "能量满按 Q 进入瞄准")
	ok(u.phase == "aim" and u.aim_v2, "进入 v2 瞄准（phase=%s v2=%s）" % [u.phase, u.aim_v2])
	var kind: String = u.aim_kind
	if kind != "none":
		ok(absf(u._aim_max - Bal.v("ult/aim_max", 1.5) * Bal.v("ult/aim_slow", 0.3)) < 0.001, "瞄准上限 = aim_max × aim_slow（%.3f）" % u._aim_max)
	u._sf_rt = -99.0   # 跳过超必杀暂停（真实时间计时），直接看瞄准慢动作
	ok(absf(u.time_scale() - Bal.v("ult/aim_slow", 0.3)) < 0.001 or u.sf_active(), "瞄准中时间系数 0.3（%.2f）" % u.time_scale())
	# 2. 轻点：松开得快 → 保持瞄准；录片计划把落点挪到队长右上 300 / -120
	u.release_q()
	ok(u.aim_latched or kind == "none", "轻点 Q 后保持瞄准")
	u._aim_plan = [[0.0, "rel", 300.0, -120.0]]
	step.call(8)
	ok(u.phase == "aim" or kind == "none", "轻点后不释放（%s）" % u.phase)
	if kind == "point":
		ok(u.aim.distance_to(ld.pos + Vector2(300, -120)) < 200.0, "落点跟着计划挪过去（离目标 %.0f）" % u.aim.distance_to(ld.pos + Vector2(300, -120)))
		ok(u.aim.distance_to(ld.pos) <= Aim.REACH + 1.0, "落点不超出 520")
	ok(u.press_q() or kind == "none", "再按 Q 释放")
	ok(u.phase == "cast" or u.phase == "", "释放后进入出招（%s）" % u.phase)
	step.call(600)
	ok(u.phase == "", "招式放完")
	# 3. 按住不松：到上限自动释放
	u.energy = u.FULL
	u.press_q()
	var n := 0
	while u.phase == "aim" and n < 200:
		step.call(1)
		n += 1
	ok(u.phase != "aim" and n <= int(ceil(u._aim_max / dt)) + 2, "按住到上限自动释放（%d 帧）" % n)
	step.call(600)
	# 4. 自身周围类：不停留
	u.aim_kind = "none"
	var mm: Array = Aim.begin(u)
	ok(absf(float(mm[0]) - float(mm[1])) < 0.0001, "自身周围类不需要选：上限 = 下限")
	# 5. 开关 0：旧路径
	Bal.sec("ult")["aim"] = 0
	ok(not Aim.on(u), "ult/aim 0 不走 v2")
	u.energy = u.FULL
	u.press_q()
	ok(not u.aim_v2, "开关 0 时按 Q 走旧瞄准")
	u.release_q()
	step.call(600)
	Bal.sec("ult")["aim"] = 1
	_done()


func _done() -> void:
	print("ULT AIM checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
