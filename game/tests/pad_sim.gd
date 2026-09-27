extends Node
## 手柄模拟（--padsim，仅测试）：按时间线注入手柄事件，从标题一路走进对局，在关键画面截图到 --shotdir=<目录>（缺省 user://padsim）/pad_*.png。

var t := 0.0
var step := 0
var shots := 0
var stage_t := 0.0
var last_stage := ""


func _btn(b: int) -> void:
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = b
	e.pressed = true
	Input.parse_input_event(e)
	var u := e.duplicate()
	u.pressed = false
	Input.parse_input_event(u)


func _axis(a: int, v: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = a
	e.axis_value = v
	Input.parse_input_event(e)


func _shot_dir() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			return a.substr(10)
	DirAccess.make_dir_recursive_absolute("user://padsim")
	return "user://padsim"


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png(_shot_dir() + "/pad_%s.png" % name)
	print("PADSIM shot ", name)


func _stage() -> String:
	var sc = get_tree().current_scene
	if sc == null:
		return ""
	if "state" in sc and "S" in sc:
		return "game:%s" % sc.S.keys()[sc.state]
	return "title"


func _process(dt: float) -> void:
	t += dt
	var st := _stage()
	if st != last_stage:
		print("PADSIM stage ", st, " t=", snappedf(t, 0.1))
		last_stage = st
		stage_t = 0.0
	else:
		stage_t += dt
	match st:
		"title":
			# 带命令行参数时标题开场自动跳过（2026-09-27 起），所以不再先按一次 Ⓐ 跳开场：
			# 1s 选「集结出发」→ 进选人 → 右移一格 → Ⓐ → 难度页（停在第一档，不右移，避免选到未解锁档）Ⓐ
			var seq := [[1.0, JOY_BUTTON_A], [2.0, "shot_op"], [2.2, JOY_BUTTON_DPAD_RIGHT], [2.6, "shot_op2"], [3.0, JOY_BUTTON_A], [3.8, "shot_diff"], [4.1, JOY_BUTTON_A]]
			_run(seq)
		"game:OPENING":
			if stage_t > 0.6 and step < 100:
				step = 100
				_btn(JOY_BUTTON_A)
		"game:INTRO":
			if stage_t > 0.8 and step < 110:
				step = 110
				_shot("intro")
				_btn(JOY_BUTTON_B)
		"game:PLAY":
			if step < 200:
				step = 200
				_axis(JOY_AXIS_LEFT_X, 1.0)
				_axis(JOY_AXIS_LEFT_Y, -0.4)
			elif step == 200 and stage_t > 2.5:
				step = 201
				_shot("play")
				_axis(JOY_AXIS_LEFT_X, 0.0)
				_axis(JOY_AXIS_LEFT_Y, 0.0)
				_btn(JOY_BUTTON_START)
			elif step == 203 and stage_t > 0.5:
				step = 204
				_btn(JOY_BUTTON_BACK)
			elif step == 205 and stage_t > 0.5:
				step = 206
				_axis(JOY_AXIS_LEFT_X, -0.7)   # 继续走，等升级
			elif step == 206 and stage_t > 1.5:
				step = 2061
				var sc = get_tree().current_scene
				sc.pickups.gain_xp(sc.xp_need + 0.1)   # 强制升级，测选卡
		"game:PAUSE":
			if step == 201 and stage_t > 0.6:
				step = 202
				_btn(JOY_BUTTON_DPAD_RIGHT)
				_btn(JOY_BUTTON_DPAD_RIGHT)
			elif step == 202 and stage_t > 1.0:
				step = 2025
				_shot("pause")
				_btn(JOY_BUTTON_A)        # 焦点在「设置」→ 打开设置面板
			elif step == 2025 and stage_t > 1.8:
				step = 2026
				_btn(JOY_BUTTON_DPAD_DOWN)
				_btn(JOY_BUTTON_DPAD_DOWN)
			elif step == 2026 and stage_t > 2.4:
				step = 2027
				_shot("settings")
				_btn(JOY_BUTTON_B)
			elif step == 2027 and stage_t > 3.0:
				step = 203
				_btn(JOY_BUTTON_B)
		"game:STATS":
			if step == 204 and stage_t > 0.6:
				step = 205
				_shot("stats")
				_btn(JOY_BUTTON_B)
		"game:CHOICE":
			if (step == 206 or step == 2061) and stage_t > 0.8:
				step = 207
				_axis(JOY_AXIS_LEFT_X, 0.0)
				_btn(JOY_BUTTON_DPAD_RIGHT)
			elif step == 207 and stage_t > 1.3:
				step = 208
				_shot("choice")
				_btn(JOY_BUTTON_A)
		"game:SHOW":
			if stage_t > 1.0:
				_btn(JOY_BUTTON_A)
	if step == 208 and st == "game:PLAY" and stage_t > 1.0:
		step = 999
		print("PADSIM done")
		get_tree().quit()
	if t > 120.0:
		print("PADSIM timeout at ", st, " step ", step)
		get_tree().quit()


func _run(seq: Array) -> void:
	for i in seq.size():
		if i < step:
			continue
		if t >= seq[i][0]:
			step = i + 1
			var a = seq[i][1]
			if a is String:
				_shot(a.substr(5))
			else:
				_btn(a)
		break
