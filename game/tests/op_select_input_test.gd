extends Node
## 选人页 B+（docs/58 §11）输入回归：键盘 / 手柄（经 Pad 翻译）/ 鼠标 / 触屏（模拟触点 → 鼠标）都能换人、换页签、职业筛选、出击、返回；
## 名册按 data/characters 自动生成；「减少动态效果」直接到终态；整页动效不碰 g.rng（标题页没有 g，这里只查全局 RNG 状态不被读）。
const Character = preload("res://scripts/characters/character.gd")
var failures := 0
var title: Control


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("OP SELECT: " + what)


func _ready() -> void:
	call_deferred("run")


func key(k: int) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = true
	Input.parse_input_event(e)
	var u := InputEventKey.new()
	u.keycode = k
	u.pressed = false
	Input.parse_input_event(u)
	await get_tree().process_frame
	await get_tree().process_frame


func pad(b: int) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	var u := InputEventJoypadButton.new()
	u.button_index = b
	u.pressed = false
	Input.parse_input_event(u)
	await get_tree().process_frame
	await get_tree().process_frame


## 点设计坐标里某个命中区的中心。用 Viewport.push_input(本地坐标)：无头模式窗口很小，Input.parse_input_event 按窗口坐标再做拉伸换算会偏。
## 触屏（Cfg.touch_device）下引擎把触点模拟成同样的鼠标左键按下 / 松开，这里直接发模拟后的鼠标事件（touch = true 时中间加一段 2 像素拖动，验证小抖动仍算点按）
func click(r: Rect2, touch := false) -> void:
	var p: Vector2 = title.get_global_transform() * (title.op_off + r.get_center() * title.op_k)
	var seq: Array = [[true, p]]
	if touch:
		seq.append([null, p + Vector2(2, 1)])
	seq.append([false, p + (Vector2(2, 1) if touch else Vector2.ZERO)])
	for st in seq:
		var e: InputEvent
		if st[0] == null:
			var mm := InputEventMouseMotion.new()
			mm.position = st[1]
			mm.relative = Vector2(2, 1)
			mm.button_mask = MOUSE_BUTTON_MASK_LEFT
			e = mm
		else:
			var mb := InputEventMouseButton.new()
			mb.button_index = MOUSE_BUTTON_LEFT
			mb.position = st[1]
			mb.pressed = st[0]
			e = mb
		get_viewport().push_input(e, true)
		await get_tree().process_frame
	await get_tree().process_frame


func settle() -> void:
	for i in 4:
		await get_tree().process_frame


func wait_for(cond: Callable, max_s := 4.0) -> void:
	var t0 := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - t0 < max_s * 1000.0:
		await get_tree().process_frame


func cur_id() -> String:
	return title.op_defs[title.op_sel].id


func run() -> void:
	Cfg.character_id = "mizuki"
	Cfg.cover_character_id = "mizuki"
	Cfg.reduce_motion = false
	title = load("res://main.tscn").instantiate()
	add_child(title)
	await get_tree().process_frame
	title.intro = title.INTRO_LEN
	title._open_op_pick(false)
	await settle()
	# 名册：data/characters 里所有 recruitable 的干员（新干员自动出现）
	var n := 0
	for cid in Character.list_ids():
		if Character.load_def(cid).get("recruitable", true):
			n += 1
	check(title.op_defs.size() == n, "roster has all %d recruitable operators (got %d)" % [n, title.op_defs.size()])
	check(cur_id() == "mizuki", "opens on configured operator")
	# 立绘适配：每名干员（桌面 / 手机两套版式）待机帧并集区按选定整数倍放进舞台框（四边至少留 2）
	for ph in [false, true]:
		Cfg._touch = 1 if ph else 0
		var sr: Rect2 = title._op_stage_rect()
		for od in title.op_defs:
			var fit: Array = title._op_fit(od, ph)
			var bb: Rect2 = od.bb
			var sz: Vector2 = bb.size * 2.0 / float(od.hires) * float(fit[0])
			var box := Rect2(fit[1].x - sz.x / 2.0, fit[1].y - sz.y, sz.x, sz.y)
			check(float(fit[0]) == floorf(float(fit[0])) and float(fit[0]) >= 1.0, "integer art scale for %s" % od.id)
			check(sr.grow(-2.0).encloses(box), "%s art fits stage (%s) on %s: %s" % [od.id, str(sr), "phone" if ph else "desktop", str(box)])
	Cfg._touch = -1
	# 键盘：→ 换人、↓ 换页签、E 职业筛选、Q 回到全部、Tab 换技能行
	var s0: int = title.op_sel
	await key(KEY_RIGHT)
	check(title.op_sel != s0, "keyboard right switches operator")
	await key(KEY_LEFT)
	check(title.op_sel == s0, "keyboard left switches back")
	await key(KEY_DOWN)
	check(title.op_tab == 2, "keyboard down changes tab (1 -> 2)")
	await key(KEY_UP)
	await key(KEY_UP)
	check(title.op_tab == 0, "keyboard up changes tab")
	await key(KEY_E)
	check(title.op_filter == "先锋", "keyboard E filters first class")
	check(title.op_defs[title.op_sel].cls == "先锋", "filter moves selection into class")
	await key(KEY_Q)
	check(title.op_filter == "", "keyboard Q back to all")
	await key(KEY_TAB)
	check(title.op_tab == 1, "tab key jumps to skill page")
	var sk: int = title.op_skill
	await key(KEY_TAB)
	check(title.op_skill == posmod(sk + 1, 3), "tab key cycles skill row")
	# 手柄（Pad 在标题页把十字键 / LB RB / A / B 翻译成按键）
	var s1: int = title.op_sel
	await pad(JOY_BUTTON_DPAD_RIGHT)
	check(title.op_sel != s1, "gamepad dpad right switches operator")
	await pad(JOY_BUTTON_DPAD_DOWN)
	check(title.op_tab == 2, "gamepad dpad down changes tab")
	await pad(JOY_BUTTON_RIGHT_SHOULDER)
	check(title.op_filter == "先锋", "gamepad RB filters class")
	await pad(JOY_BUTTON_LEFT_SHOULDER)
	check(title.op_filter == "", "gamepad LB back to all")
	# 鼠标：点卡、点页签、点职业轨
	await settle()
	var target := -1
	for k in title.op_rects:
		if k is int and k != title.op_sel:
			target = k
			break
	check(target >= 0, "card hit rects present")
	if target >= 0:
		await click(title.op_rects[target])
		check(title.op_sel == target, "mouse click selects card")
	await settle()
	if title.op_prects.has("tab0"):
		await click(title.op_prects["tab0"])
		check(title.op_tab == 0, "mouse click changes tab")
	else:
		check(false, "tab hit rects present")
	if title.op_rects.has("cls:近卫"):
		await click(title.op_rects["cls:近卫"])
		check(title.op_filter == "近卫", "mouse click filters class")
		await settle()
		await click(title.op_rects["cls:"])
		check(title.op_filter == "", "mouse click clears filter")
	else:
		check(false, "class rail hit rects present")
	var before: int = title.op_sel
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	get_viewport().push_input(wheel, true)
	await settle()
	check(title.op_sel != before or title.op_sel == title.op_defs.size() - 1, "mouse wheel switches operator")
	# 减少动态效果：换人后一帧内位移类动效到终态
	Cfg.reduce_motion = true
	await key(KEY_RIGHT)
	check(title._op_p(title.op_sw_t, 0.06, 0.3) == 1.0 and title._op_lift(title.op_sel) == 1.0, "reduce motion snaps to end state")
	var m: Dictionary = title._op_body_motion()
	check(m.dx == 0.0, "reduce motion: no panel slide")
	Cfg.reduce_motion = false
	# 返回：Esc
	await key(KEY_ESCAPE)
	await wait_for(func(): return not title.op_pick and not title.transition.busy)
	check(not title.op_pick, "escape leaves operator select")
	# 出击（Enter）→ 深海浪幕 → 难度页；浪幕期间锁输入
	title._open_op_pick(false)
	await settle()
	var go_id := cur_id()
	await key(KEY_ENTER)
	check(title.transition.busy, "deploy locks input during wave wipe")
	await wait_for(func(): return title.diff_pick and not title.transition.busy)
	check(title.diff_pick and not title.op_pick, "enter deploys into difficulty select")
	check(Cfg.character_id == go_id, "deploy stores operator")
	title._diff_back()
	await wait_for(func(): return title.op_pick and not title.transition.busy)
	check(title.op_pick, "difficulty back returns to operator select")
	# 触屏（手机版式）：触点选卡、点页签、点出击
	Cfg._touch = 1
	await settle()
	await settle()
	var tgt := -1
	for k in title.op_rects:
		if k is int and k != title.op_sel:
			tgt = k
			break
	check(tgt >= 0, "touch layout card rects present")
	if tgt >= 0:
		await click(title.op_rects[tgt], true)
		check(title.op_sel == tgt, "touch tap selects card")
	await settle()
	if title.op_prects.has("tab2"):
		await click(title.op_prects["tab2"], true)
		check(title.op_tab == 2, "touch tap changes tab")
	if title.op_rects.has("cls:近卫"):
		await click(title.op_rects["cls:近卫"], true)
		check(title.op_filter == "近卫", "touch tap filters class")
	await settle()
	check(title.op_rects.has("go"), "touch layout has deploy button")
	if title.op_rects.has("go"):
		await click(title.op_rects["go"], true)
		await wait_for(func(): return title.diff_pick and not title.transition.busy)
		check(title.diff_pick, "touch deploy reaches difficulty")
	Cfg._touch = -1
	title.queue_free()
	await get_tree().process_frame
	print("OP SELECT INPUT: %d failures" % failures)
	get_tree().quit.call_deferred(1 if failures else 0)
