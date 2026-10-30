extends Node
## 10-23 手动普攻探针，10-31 改为按住瞄准（按住瞄准时不要求有目标，方向由玩家指向，不吸附最近敌人）：
## 以 PLAY 模式起一局（无机器人），清空敌人，模拟按住瞄准、指向右；在队长左侧 220 处放一只不动的木桩。
## 跑 probe 秒后打印：普攻出手次数 atk_n、队长子弹 / 弹体数、木桩掉血（应为 0 = 没吸附到背后的敌人）。
## 用法：tools/probes/manual_aim_probe.py [--ops a,b] [--t 6]

var _keys := {}
func _key(code: int, down: bool) -> void:
	if _keys.get(code, false) == down:
		return
	_keys[code] = down
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = down
	Input.parse_input_event(ev)


func _mouse(g, down: bool, world_off: Vector2) -> void:
	var vp: Viewport = g.get_viewport()
	var scr: Vector2 = vp.get_canvas_transform() * (g.ppos + world_off)
	var mm := InputEventMouseMotion.new()
	mm.position = scr
	mm.global_position = scr
	Input.parse_input_event(mm)
	if _keys.get("mouse", false) != down:
		_keys["mouse"] = down
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.position = scr
		mb.global_position = scr
		mb.pressed = down
		Input.parse_input_event(mb)


## 真实输入路径：kb = WASD 移动；mouse = 左键 + 光标在队长右边 200；touch = 触屏瞄准键（touch_atk，拖向右）
func _drive_input(g, inp: String, mode: String, move: Vector2, k: int) -> void:
	var press: bool = mode == "hold" or (k % 90 >= 10 and k % 90 < 14)
	_key(KEY_D, move.x > 0.5)
	_key(KEY_A, move.x < -0.5)
	_key(KEY_S, move.y > 0.5)
	_key(KEY_W, move.y < -0.5)
	match inp:
		"kb":
			pass   # 10-31 起没有攻击键：键盘只走位，普攻自动
		"mouse":
			_mouse(g, press, Vector2(200, 0))
		"touch":
			g.doctor.touch_atk = press
			g.doctor.touch_atk_dir = Vector2(60, 0) if press else Vector2.ZERO


func _ready() -> void:
	var id := "exusiai"
	var probe_t := 6.0
	var dx := -220.0      # 木桩相对队长的 x（负 = 背后，指向为右）
	var line := 1         # 沿 +x 每 60 px 放几只木桩（穿透验收用）
	var dy := 0.0         # 木桩线每只的 y 递增（让木桩排在枪口到第一只的弹道上：能天使约 17、流明约 22）
	var card := 0         # 先选几次「贯穿」卡
	var relic := ""       # 先给的藏品编号（穿甲弹 265）
	var mode := "hold"    # hold = 一直按住瞄准；tap = 每 1.5 秒按一下瞄准
	var inp := "sim"      # sim = 直接写 doctor.sim_atk / sim_dir；kb = 真实键盘事件（只走位，普攻自动）；mouse = 真实鼠标左键 + 光标位置；touch = 触屏瞄准键模拟（拖向右）
	var move := Vector2.ZERO   # 移动输入（手动攻击方向取它）
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--probe-op="): id = arg.get_slice("=", 1)
		if arg.begins_with("--probe-t="): probe_t = float(arg.get_slice("=", 1))
		if arg.begins_with("--probe-dx="): dx = float(arg.get_slice("=", 1))
		if arg.begins_with("--probe-line="): line = int(arg.get_slice("=", 1))
		if arg.begins_with("--probe-dy="): dy = float(arg.get_slice("=", 1))
		if arg.begins_with("--probe-card="): card = int(arg.get_slice("=", 1))
		if arg.begins_with("--probe-relic="): relic = arg.get_slice("=", 1)
		if arg.begins_with("--probe-mode="): mode = arg.get_slice("=", 1)
		if arg.begins_with("--probe-input="): inp = arg.get_slice("=", 1)
		if arg.begins_with("--probe-move="):
			var mv := arg.get_slice("=", 1).split(",")
			move = Vector2(float(mv[0]), float(mv[1]))
	var g = load("res://game.tscn").instantiate()
	add_child(g)
	for i in 5: await get_tree().process_frame
	g.set_process(false)
	g.mode = g.Mode.PLAY
	g.state = g.S.PLAY
	g.sandbox = true
	g.t = 60.0
	g.xp_need = 1000000000.0
	var o = g.squad.get_op(id)
	assert(o != null)
	for e in g.enemies: e.dead = true
	g.enemies.clear()
	var dummies: Array = []
	for i in line:
		var dm: Dictionary = g.spawner.spawn_enemy("stone", g.ppos + Vector2(dx + 60.0 * i, dy * i))
		dm.hp = 100000.0
		dm.max_hp = dm.hp
		dm.spd = 0.0
		dummies.append(dm)
	g.enemies_sys.build_grid()
	for i in card:
		g.doctor.apply_passive("pierce")
	if relic != "":
		g.progression.gain_relic(relic)
	g.doctor.sim_atk = mode == "hold" and inp == "sim"
	g.doctor.sim_dir = Vector2.RIGHT
	g.move_in = move
	g.facing = 1.0
	var hp0: float = dummies[0].hp
	var steps := int(probe_t * 60.0)
	var bul_max := 0
	var anim_frames := 0
	var ppos0: Vector2 = g.ppos
	var atk0: int = int(o.get("atk_n")) if o.get("atk_n") != null else 0
	for k in steps:
		o.sp = [-100000.0, -100000.0, -100000.0]   # 不放技能，只看普攻
		if inp == "sim":
			g.move_in = move
			if mode == "tap":
				g.doctor.sim_atk = k % 90 >= 10 and k % 90 < 14
		else:
			_drive_input(g, inp, mode, move, k)
			await get_tree().process_frame   # 真实输入事件要过一帧才生效（按下和松开不能挤在同一帧里）
		for i in dummies.size():
			dummies[i].pos = g.ppos + Vector2(dx + 60.0 * i, dy * i)
			dummies[i].kb = Vector2.ZERO
			dummies[i].hp = maxf(dummies[i].hp, 1.0)
			dummies[i].dead = false
		g.enemies_sys.build_grid()
		g._update(1.0 / 60.0)
		var n_b := 0
		for b in g.bullets:
			if str(b.get("op", "")) == id: n_b += 1
		var st = o.get("hw")
		if st is Dictionary:
			for key in ["waves", "bolts", "lobs", "shells"]:
				if st.has(key) and st[key] is Array: n_b += st[key].size()
		var ex = o.get("ext")
		if ex is Dictionary and ex.has("bul"): n_b += ex.bul.size()
		var lm = st.lm if st is Dictionary and st.has("lm") else null
		if lm is Dictionary and lm.has("bolts"): n_b += lm.bolts.size()
		bul_max = maxi(bul_max, n_b)
		var ast: Dictionary = o.anim_state()
		if float(o.attack_t) > 0.0 and str(ast.get("kind", "")) != "idle" and str(ast.get("kind", "")) != "run":
			anim_frames += 1
		if k % 120 == 0:
			await get_tree().process_frame
	var atk_n: int = (int(o.get("atk_n")) if o.get("atk_n") != null else 0) - atk0
	var dmgs := []
	for dm in dummies:
		dmgs.append(snappedf(hp0 - float(dm.hp), 0.1))
	print("MANUALPROBE op=%s atk_n=%d anim=%d bullets_max=%d dummy_dmg=%s face=%d moved=%d" % [id, atk_n, anim_frames, bul_max, str(dmgs), int(o.face), int(g.ppos.distance_to(ppos0))])
	get_tree().quit()
