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
	ok(u.phase == "windup" or u.phase == "cast" or u.phase == "", "释放后进入起手 / 出招（%s）" % u.phase)
	# 起手慢放（11-01 用户，ult/windup_slow）：看得见的局里确认后先 0.5 真实秒慢速起手（0.15 游戏秒），再正式出招
	ok(u.phase == "windup", "看得见的局：确认后先进起手（%s）" % u.phase)
	ok(absf(u.time_scale() - Bal.v("ult/windup_s", 0.3)) < 0.001, "起手中世界 0.3 倍（%.2f）" % u.time_scale())
	ok(u.cam_punch() >= Bal.v("ult/cam_aim", 1.08) - 0.001, "起手中镜头不往回拉（%.3f）" % u.cam_punch())
	var wn := 0
	while u.phase == "windup" and wn < 60:
		step.call(1)
		wn += 1
	ok(u.phase == "cast" or u.phase == "", "起手到点正式出招（%d 帧 = %.2f 游戏秒）" % [wn, wn * dt])
	ok(wn >= 6 and wn <= 12, "起手 0.15 游戏秒左右（%d 帧）" % wn)
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
	# 4. 自身周围类（11-01 用户「原地放的终结技也要先显示范围再确认」，ult/aim_self）：也停在瞄准里看范围；开关 0 = 旧的不停留
	u.aim_kind = "none"
	var mm: Array = Aim.begin(u)
	ok(float(mm[1]) > float(mm[0]) + 0.1, "自身周围类也停在瞄准里（上限 %.2f）" % float(mm[1]))
	ok(Aim.shape_of(u).kind == "disc" and Vector2(Aim.shape_of(u).c) == u.caster.pos, "自身周围类范围 = 以队长为中心的圆（跟着人走）")
	ok(Aim._tip(u).begins_with("按住看范围"), "自身周围类提示「按住看范围」（%s）" % Aim._tip(u))
	Bal.sec("ult")["aim_self"] = 0
	mm = Aim.begin(u)
	ok(absf(float(mm[0]) - float(mm[1])) < 0.0001, "ult/aim_self 0：上限 = 下限（旧的不停留）")
	Bal.sec("ult")["aim_self"] = 1
	# 6. 触屏拖动（docs/209 §3）：走 Input.parse_input_event 整条链（含 Godot 从 0 号触点模拟出的鼠标左键 → game._unhandled_input → ult.aim_click），
	#    按下终结技键进瞄准、拖动写落点、松手按拖到的落点放
	if kind == "point":
		var tc = g.touch
		var was_active: bool = tc.active
		tc.active = true
		var ub: Dictionary = tc.ult_btn(g.hud.size)
		tc.ult_rect = Rect2(ub.c - Vector2(ub.r, ub.r), Vector2(ub.r, ub.r) * 2.0)
		var c0: Vector2 = tc.ult_rect.get_center() * Cfg.ui_k
		u.energy = u.FULL
		_touch(true, c0)
		step.call(1)
		ok(u.phase == "aim" and u.aim_v2, "触屏按下终结技键进入 v2 瞄准（phase=%s）" % u.phase)
		u._sf_rt = -99.0
		var drag := Vector2(80.0, -40.0)   # 界面像素；touch.ULT_AIM_REACH 90 = 最远 520
		for k in 6:
			_drag(c0 + drag * float(k + 1) / 6.0)
			await _frames(1)
			step.call(1)
		ok(u.phase == "aim", "拖动中仍在瞄准（模拟鼠标左键没有提前释放）：%s" % u.phase)
		ok(u.aim_src == "touch", "输入源 = 触屏（%s）" % u.aim_src)
		var want: Vector2 = ld.pos + drag.normalized() * minf(520.0, drag.length() / 90.0 * 520.0)
		ok(u.aim.distance_to(want) < 30.0, "落点 = 队长 + 拖动方向 × 距离（离预期 %.0f）" % u.aim.distance_to(want))
		_touch(false, c0 + drag)
		step.call(2)
		ok(u.phase == "windup" or u.phase == "cast" or u.phase == "", "松手释放（%s）" % u.phase)
		step.call(12)   # 走完起手慢放（0.15 游戏秒）才正式出招、定作用中心
		ok(u._ult_at.distance_to(want) < 40.0, "按拖到的落点放（离预期 %.0f）" % u._ult_at.distance_to(want))
		step.call(600)
		# 轻点终结技键（不拖）：保持瞄准，再点一次放
		u.energy = u.FULL
		_touch(true, c0)
		step.call(1)
		_touch(false, c0)
		step.call(4)
		ok(u.phase == "aim" and u.aim_latched, "触屏轻点后保持瞄准（phase=%s latched=%s）" % [u.phase, u.aim_latched])
		ok(Aim._tip(u).begins_with("拖动选择") and not Aim._tip(u).contains("Q"), "触屏保持瞄准的提示不写鼠标 / Q（%s）" % Aim._tip(u))
		_touch(true, c0)
		_touch(false, c0)
		step.call(2)
		ok(u.phase == "windup" or u.phase == "cast" or u.phase == "", "再点一次终结技键释放（%s）" % u.phase)
		step.call(600)
		tc.active = was_active
		# 7. 手柄右摇杆：推到底 = 最远 520，方向跟摇杆
		u.energy = u.FULL
		u.press_q()
		u._sf_rt = -99.0
		var dev: int = Pad.device
		Pad.device = 0
		_axis(JOY_AXIS_RIGHT_X, 0.0)
		_axis(JOY_AXIS_RIGHT_Y, 1.0)
		await _frames(1)
		step.call(2)
		ok(u.aim_src == "pad", "输入源 = 手柄（%s）" % u.aim_src)
		ok(u.aim.distance_to(ld.pos + Vector2(0, 520)) < 30.0, "右摇杆推到底 → 落点在队长正下方 520（离预期 %.0f）" % u.aim.distance_to(ld.pos + Vector2(0, 520)))
		_axis(JOY_AXIS_RIGHT_Y, 0.0)
		_axis(JOY_AXIS_RIGHT_X, 0.0)
		await _frames(1)
		Pad.device = dev
		u.release_q()
		u.press_q()
		step.call(600)
	# 8. 指挥圆盘与终结技瞄准互斥（11-01 终结技审查）：瞄准中开不了圆盘；圆盘开着时按不出终结技
	if g.squad.cmd_on():
		u.energy = u.FULL
		u.press_q()
		ok(u.phase == "aim", "进入瞄准（圆盘互斥前置）")
		g.wheel.open()
		ok(not g.wheel.is_open, "瞄准中不开指挥圆盘")
		u.release_q()
		u.confirm_aim()
		step.call(600)
		g.wheel.open()
		ok(g.wheel.is_open, "平时能开指挥圆盘")
		u.energy = u.FULL
		ok(not u.press_q() and u.phase == "", "圆盘开着时按不出终结技（phase=%s）" % u.phase)
		g.wheel.cancel()
	# 5. 开关 0：旧路径
	Bal.sec("ult")["aim"] = 0
	ok(not Aim.on(u), "ult/aim 0 不走 v2")
	Bal.sec("ult")["windup_slow"] = 0
	u.energy = u.FULL
	u.press_q()
	u._sf_rt = -99.0
	var on := 0
	while u.phase == "aim" and on < 200:
		step.call(1)
		on += 1
	ok(u.phase != "windup", "ult/windup_slow 0：确认即出招（%s）" % u.phase)
	step.call(600)
	Bal.sec("ult")["windup_slow"] = 1
	u.energy = u.FULL
	u.press_q()
	ok(not u.aim_v2, "开关 0 时按 Q 走旧瞄准")
	u.release_q()
	step.call(600)
	Bal.sec("ult")["aim"] = 1
	_done()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## 触屏事件：按 Godot Input 的顺序先发 0 号触点模拟出的鼠标事件（emulate_mouse_from_touch 缺省开，真机 / 网页都有），再发触摸本身。
## headless 下 Input.parse_input_event / viewport.push_input 都到不了场景，直接按视口的派发顺序调 game._input → _unhandled_input
func _send(ev: InputEvent, unhandled: bool) -> void:
	g._input(ev)
	if unhandled:
		g._unhandled_input(ev)


func _touch(down: bool, p: Vector2) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.position = p
	mb.global_position = p
	mb.pressed = down
	_send(mb, true)
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.position = p
	ev.pressed = down
	_send(ev, false)


func _drag(p: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = p
	mm.global_position = p
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	_send(mm, true)
	var ev := InputEventScreenDrag.new()
	ev.index = 0
	ev.position = p
	_send(ev, false)


func _axis(a: JoyAxis, v: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.device = 0
	ev.axis = a
	ev.axis_value = v
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _done() -> void:
	print("ULT AIM checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
