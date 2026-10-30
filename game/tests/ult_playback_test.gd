extends Node
## 10-31 终结技播放形式（ult.playing）：按 Q 到演出结束队长不吃移动输入、不冲刺、不被移动输入带着走（突进招式由招式脚本写位置）、
## 播放期间无敌；期间攒下的升级不弹，播完按顺序逐个弹三选一；播完移动恢复。
## godot --headless --path game res://tests/ult_playback_test.tscn -- --regression --balance --seed=1 --op=texas [--touchmove]
## --touchmove：移动输入走触屏摇杆（touch.vec），缺省走键盘 D 键。全部通过时打印 "ULT PLAYBACK checks=N failures=0"

const Bal = preload("res://scripts/core/balance.gd")
const DISPLACE := ["ulpianus", "siege", "irene"]   # 招式脚本自己挪队长的几招（ult_moves._ul_step / ult_moves_c._lead_move）

var checks := 0
var failures := 0
var g
var touch_mv := false


func ok(v: bool, what: String) -> void:
	checks += 1
	if not v:
		failures += 1
		printerr("FAIL: ", what)


func _hold(on: bool) -> void:
	if touch_mv:
		g.touch.active = on or g.touch.active
		g.touch.stick_id = 0 if on else -1
		g.touch.vec = Vector2(1, 0) if on else Vector2.ZERO
		return
	var ev := InputEventKey.new()
	ev.keycode = KEY_D
	ev.physical_keycode = KEY_D
	ev.pressed = on
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _ready() -> void:
	touch_mv = Cfg.dev_args().has("--touchmove")
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
	ok(g.ult != null, "终结技框架开着")
	if g.ult == null:
		_done()
		return
	var ld = g.squad.leader()
	var op: String = str(ld.id)
	var foes: Array = []
	for k in 16:   # 一圈敌人（贴身 4 只 + 外圈 12 只），不动、打不死：终结技有目标，贴身的会打队长
		var r: float = 6.0 if k < 4 else 260.0
		var e: Dictionary = g.spawner.spawn_enemy("bone", g.ppos + Vector2.from_angle(TAU * k / (4.0 if k < 4 else 12.0)) * r)
		e.hp = 1.0e9
		e.maxhp = 1.0e9
		e.spd = 0.0
		foes.append(e)
	var dt := 1.0 / 60.0
	var step := func() -> void:
		for k in foes.size():
			foes[k].hp = 1.0e9
			if k < 4:   # 贴身 4 只每帧摆回队长脚边（终结技会把它们打飞）：接触伤害一直够得着
				foes[k].pos = g.ppos + Vector2.from_angle(TAU * k / 4.0) * 6.0
		g.enemies_sys.build_grid()
		g._update(dt)
	# 1. 播放前：移动输入能走
	_hold(true)
	var p0: Vector2 = g.ppos
	for f in 30:
		g.hp = g.max_hp
		step.call()
	ok(g.ppos.x - p0.x > 20.0, "%s 按 Q 前：移动输入能让队长走（%.1f）" % [op, g.ppos.x - p0.x])
	# 2. 按 Q，按住 10 帧（瞄准时移动输入挪落点），松开放出；全程按着移动键、中途按冲刺、攒 2 次升级
	g.hp = g.max_hp
	g.ult.energy = g.ult.FULL
	ok(g.ult.press_q(), "%s 能量满按 Q 进入终结技" % op)
	var start: Vector2 = g.ppos
	var t0: float = g.t
	var hp0: float = g.hp
	var hp_min: float = g.hp
	var moved_by_input := 0
	var not_play := 0
	var no_inv := 0
	var max_off := 0.0
	var frames := 0
	var dash_fired := false
	g.pending_levelups += 2
	while g.ult.phase != "" and frames < 60 * 12:
		frames += 1
		if frames == 10:
			g.ult.release_q()
		if frames == 20:
			g._try_dash()
			dash_fired = g.dash_t > 0.0
		step.call()
		if g.ult.phase == "":
			break
		if g.moving or (g.dash_t <= 0.0 and g.pvel != Vector2.ZERO):
			moved_by_input += 1
		if g.state != g.S.PLAY:
			not_play += 1
		if g.invuln <= 0.0:
			no_inv += 1
		hp_min = minf(hp_min, g.hp)
		max_off = maxf(max_off, g.ppos.distance_to(start))
	var dur: float = g.t - t0
	print("ULTPLAY op=%s dur=%.2f frames=%d max_off=%.1f hp_drop=%.1f/%.0f" % [op, dur, frames, max_off, hp0 - hp_min, g.max_hp])
	ok(g.ult.phase == "", "%s 终结技在 12 秒内收尾（%.2f 秒）" % [op, dur])
	ok(dur < Bal.v("ult/play_max", 6.0) - 0.05, "%s 演出在兜底上限 ult/play_max 之前自己结束（%.2f 秒）" % [op, dur])
	ok(moved_by_input == 0, "%s 播放期间移动输入不带动队长（%d 帧有输入位移）" % [op, moved_by_input])
	ok(frames < 20 or not dash_fired, "%s 播放期间按冲刺不出冲刺" % op)
	if not DISPLACE.has(op):
		ok(max_off < 1.0, "%s 无位移招式：队长原地不动（偏离 %.1f）" % [op, max_off])
	else:
		ok(max_off > 40.0, "%s 突进招式：位置由招式脚本移动（偏离 %.1f）" % [op, max_off])
	ok(not_play == 0, "%s 播放期间不弹升级三选一（%d 帧不在战斗状态）" % [op, not_play])
	ok(no_inv == 0, "%s 播放期间队长无敌（%d 帧没有无敌）" % [op, no_inv])
	ok(hp0 - hp_min < 0.03 * g.max_hp, "%s 播放期间贴身敌人打不掉血（%.1f，按 Q 前挨打留下的持续伤害照扣）" % [op, hp0 - hp_min])
	# 3. 播完：攒下的 2 次升级依次弹出
	for f in 3:
		step.call()
	ok(g.state == g.S.CHOICE and g.choice_kind == "level", "%s 播完弹出第 1 次升级三选一（state=%d）" % [op, g.state])
	if g.state == g.S.CHOICE:
		g.progression.pick(0)
		for f in 3:
			if g.state == g.S.PLAY:
				step.call()
		ok(g.state == g.S.CHOICE and g.choice_kind == "level", "%s 选完接着弹第 2 次升级" % op)
		if g.state == g.S.CHOICE:
			g.progression.pick(0)
		ok(g.pending_levelups == 0, "%s 两次升级都弹完（剩 %d）" % [op, g.pending_levelups])
	g.state = g.S.PLAY
	g.panel.visible = false
	# 4. 播完移动恢复（触屏：三选一弹出时摇杆触点被收掉，重新按住）
	_hold(true)
	var p1: Vector2 = g.ppos
	for f in 30:
		g.hp = g.max_hp
		step.call()
	ok(g.ppos.distance_to(p1) > 20.0, "%s 播完恢复操控（%.1f）" % [op, g.ppos.distance_to(p1)])
	_hold(false)
	_done()


func _done() -> void:
	print("ULT PLAYBACK checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
