extends Node
## 10-24 手动普攻全员验收（用户「星熊这种手动的时候攻击打不出来」）：当前 --op 干员当队长、打开手动普攻，走**真实输入事件**
## （J 键 / WASD / 鼠标左键 + 光标，不直接写 doctor 的内部量），逐场景断言「每次按攻击都出招」：
##   A 空按（场上没有敌人）按住 1.5 秒：至少出 1 次招 + 播攻击动作
##   B 有敌人（正前方）按住 1.5 秒：出招 + 动作 + 敌人掉血
##   C 边向敌人移动边按（D 键）：出招 + 动作 + 敌人掉血
##   D 轻点 3 次（间隔 1.5 秒，有敌人在身前）：每一次都出招（atk_n +1）+ 播动作
##   E 空场轻点 3 次：每一次都出招 + 动作（手动不要求有目标）
##   F 触屏：攻击键按住（不拖），出招 + 敌人掉血（点按 / 不拖 = 取移动方向，没动取朝向）
## 凯尔希（普攻是命令 Mon3tr，不出刀）只断言 B / C / F 有敌人时敌人掉血、其余不要求出招事件。
## 用法：godot --headless --path game res://tests/manual_all_test.tscn -- --regression --balance --seed=1 --op=<id> --manualatk
## 全部通过时打印 "MANUAL ALL <id> failures=0"。

const DT := 1.0 / 60.0
var g
var o
var n := 0
var fails := 0
var _keys := {}
var id := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--op="): id = arg.get_slice("=", 1)
	g = load("res://game.tscn").instantiate()
	add_child(g)
	for i in 5: await get_tree().process_frame
	g.set_process(false)
	g.mode = g.Mode.PLAY
	g.state = g.S.PLAY
	g.sandbox = true
	g.t = 60.0
	g.xp_need = 1000000000.0
	o = g.squad.get_op(id)
	assert(o != null)
	g.doctor.manual_attack = true
	g.doctor.sim_atk = false
	var is_support: bool = str(o.def.blocks.attack.get("shape", "")) == "support"
	var r: Dictionary = await run_case(false, "hold", Vector2.ZERO, 90, false)
	if not is_support:
		ok(r.events >= 1, "%s A 空按（没有敌人）按住 1.5 秒出招（%d 次）" % [id, r.events])
		ok(r.anim >= 3, "%s A 空按播攻击动作（%d 帧）" % [id, r.anim])
	r = await run_case(true, "hold", Vector2.ZERO, 90, false)
	if not is_support:
		ok(r.events >= 1 and r.anim >= 3, "%s B 有敌人按住出招 + 动作（%d 次 / %d 帧）" % [id, r.events, r.anim])
	ok(r.dmg > 0.0, "%s B 有敌人按住，敌人掉血（%.0f）" % [id, r.dmg])
	r = await run_case(true, "hold", Vector2.RIGHT, 90, false)
	if not is_support:
		ok(r.events >= 1 and r.anim >= 3, "%s C 边向敌人移动边按：出招 + 动作（%d 次 / %d 帧）" % [id, r.events, r.anim])
	ok(r.dmg > 0.0, "%s C 边向敌人移动边按，敌人掉血（%.0f）" % [id, r.dmg])
	if not is_support:
		r = await run_case(true, "tap", Vector2.ZERO, 270, false)
		ok(r.events >= 3, "%s D 轻点 3 次（有敌人）：3 次都出招（%d 次）" % [id, r.events])
		ok(r.anim_events >= 3, "%s D 轻点 3 次：每次都播动作（%d 次有动作）" % [id, r.anim_events])
		r = await run_case(false, "tap", Vector2.ZERO, 270, false)
		ok(r.events >= 3, "%s E 空场轻点 3 次：3 次都出招（%d 次）" % [id, r.events])
		ok(r.anim_events >= 3, "%s E 空场轻点 3 次：每次都播动作（%d 次有动作）" % [id, r.anim_events])
	r = await run_case(true, "hold", Vector2.ZERO, 90, true)
	if not is_support:
		ok(r.events >= 1 and r.anim >= 3, "%s F 触屏攻击键（不拖）：出招 + 动作（%d 次 / %d 帧）" % [id, r.events, r.anim])
	ok(r.dmg > 0.0, "%s F 触屏攻击键（不拖），敌人掉血（%.0f）" % [id, r.dmg])
	release_all()
	print("%d checks, %d failed" % [n, fails])
	print("MANUAL ALL %s failures=%d" % [id, fails])
	get_tree().quit(1 if fails > 0 else 0)


func ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		fails += 1
		printerr("FAIL: ", what)


func _key(code: int, down: bool) -> void:
	if _keys.get(code, false) == down:
		return
	_keys[code] = down
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = down
	Input.parse_input_event(ev)


func release_all() -> void:
	for k in [KEY_J, KEY_D, KEY_A, KEY_W, KEY_S]:
		_key(k, false)
	g.doctor.touch_atk = false


## 跑一个场景 steps 步（每步 1/60 秒 + 一帧让输入事件生效）：enemy = 正前方放一只不动的木桩；mode hold / tap；move = 移动输入；mouse = 用鼠标
func run_case(enemy: bool, mode: String, move: Vector2, steps: int, mouse: bool) -> Dictionary:
	release_all()
	await get_tree().process_frame
	for e in g.enemies:
		e.dead = true
	g.enemies.clear()
	o.s_t = [0.0, 0.0, 0.0]
	o.no_attack = false
	o.attack_t = 0.0
	o.fire_t = -1.0
	o.cd = 0.0
	o.pending.clear()
	if o.tx.has("dash"):
		o.tx.erase("dash")
	g.facing = 1.0
	g.doctor._atk_prev = false
	g.doctor.atk_buf = 0.0
	g.touch.active = mouse
	var dm: Dictionary = {}
	var reach := 150.0 if str(o.def.get("class", "")) in ["狙击", "术师", "辅助", "医疗"] else 70.0
	if enemy:
		dm = g.spawner.spawn_enemy("stone", g.ppos + Vector2(reach, 0))
		dm.hp = 1000000.0
		dm.max_hp = dm.hp
		dm.spd = 0.0
		g.enemies_sys.build_grid()
	var hp0: float = float(dm.get("hp", 0.0))
	var events := 0
	var anim := 0
	var anim_events := 0
	var last_n: int = o.atk_n
	var pending_anim := 0
	var steps_total: int = steps + 60
	for k in steps_total:
		o.sp = [-100000.0, -100000.0, -100000.0]
		var press: bool = k < steps if mode == "hold" else (k % 90 >= 10 and k % 90 < 14 and k < steps)
		_key(KEY_D, move.x > 0.5)
		if mouse:   # 触屏攻击键（touch_atk），不拖 = 方向取移动方向 / 朝向
			g.doctor.touch_atk = press
			g.doctor.touch_atk_dir = Vector2.ZERO
		else:
			_key(KEY_J, press)
		if enemy:
			dm.pos = g.ppos + Vector2(reach, 0)
			dm.kb = Vector2.ZERO
			dm.hp = maxf(dm.hp, 1.0)
			g.enemies_sys.build_grid()
		g._update(DT)
		if enemy and k % 15 == 0 and k < 60 and OS.get_environment("MA_DEBUG") != "":
			print("DBG k=%d attack_dir=%s mouse_aim=%s mouse_world=%s ppos=%s held=%s want=%s ext_bul=%s" % [k, g.doctor.attack_dir(), g.doctor.mouse_aim(), g.doctor.mouse_world(), g.ppos, g.doctor.attack_held(), g.doctor.attack_want(), str(o.ext.get("bul", []).map(func(b): return [b.p, b.v]))])
		var st: Dictionary = o.anim_state()
		var kind := str(st.get("kind", ""))
		if float(o.attack_t) > 0.0 and kind != "idle" and kind != "run" and kind != "":
			anim += 1
			pending_anim += 1
		if o.atk_n != last_n:
			events += o.atk_n - last_n
			if pending_anim >= 3:
				anim_events += 1
			last_n = o.atk_n
			pending_anim = 0
		if float(o.attack_t) <= 0.0:
			pending_anim = 0
		await get_tree().process_frame
	release_all()
	await get_tree().process_frame
	g.touch.active = false
	var dmg: float = hp0 - float(dm.get("hp", hp0)) if enemy else 0.0
	print("CASE enemy=%s mode=%s move=%s mouse=%s -> events=%d anim=%d anim_events=%d dmg=%.0f face=%d bullets=%d" % [enemy, mode, move, mouse, events, anim, anim_events, dmg, int(o.face), g.bullets.size()])
	return {"events": events, "anim": anim, "anim_events": anim_events, "dmg": dmg}
