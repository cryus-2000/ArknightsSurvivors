extends Node
## 标题页菜单（深海水母版，docs/67 §13）与难度页输入回归：
## - 四种菜单组（内部 / 对外 × 桌面 / 网页）：每项一个命中区、互不重叠、都在屏幕里（触屏至少 44 高）、方向键能走到每一项；
## - 分组导航（左侧 寻访 / 认知塑造 / 图鉴 / 蚀刻章 / 试炼 → 集结出发 → 底部 设置 / 操作说明 / 退出；紧凑版式集结出发在右下）；
## - 键盘 ↑↓←→ / WASD、Tab / Shift+Tab、手柄十字键（经 Pad 翻译）、Esc 跳到退出、鼠标悬停 / 点击、选中底条展开；
## - 难度页：↑↓ 换档（不越界）、点档位卡换档、未解锁档不能出发、Esc 返回；桌面与触屏版式都查一遍。
var failures := 0
var title: Control


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("TITLE MENU INPUT: " + what)


func _ready() -> void:
	call_deferred("run")


func frames(n := 2) -> void:
	for i in n:
		await get_tree().process_frame


func key(k: int, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = true
	e.shift_pressed = shift
	Input.parse_input_event(e)
	var u := InputEventKey.new()
	u.keycode = k
	u.pressed = false
	Input.parse_input_event(u)
	await frames()


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
	await frames()


func vp(local: Vector2) -> Vector2:
	return title.get_global_transform() * local


func hover(local: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = vp(local)
	get_viewport().push_input(mm, true)
	await frames()


func click(local: Vector2) -> void:
	for pressed in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.position = vp(local)
		mb.pressed = pressed
		get_viewport().push_input(mb, true)
		await get_tree().process_frame
	await frames()


func wait_idle() -> void:
	var t0 := Time.get_ticks_msec()
	while title.transition.busy and Time.get_ticks_msec() - t0 < 4000:
		await get_tree().process_frame
	await frames(2)


func center(i: int) -> Vector2:
	return (title.menu_lay.rects[i] as Rect2).get_center()


## 只走导航表（不经输入）：从 a 出发按方向序列，返回落点
func walk(from: int, dirs: Array) -> int:
	var s := from
	for d in dirs:
		s = title.Tiles.nav(title.menu_lay, s, d)
	return s


func menu_set(tag: String, boss: bool, ex: bool) -> void:
	title.menu_boss = boss
	title.menu_exit = ex
	title.sel = 0
	await frames(3)
	var ids: Array = title._menu_ids()
	var lay: Dictionary = title.menu_lay
	check(lay.rects.size() == ids.size(), tag + ": one hit area per visible item (%d / %d)" % [lay.rects.size(), ids.size()])
	check(lay.list.ids.size() == (5 if boss else 4), tag + ": %d side entries" % (5 if boss else 4))
	check(lay.foot.ids.size() == (3 if ex else 2), tag + ": %d footer entries" % (3 if ex else 2))
	for i in ids:
		for j in ids:
			if i < j:
				check(not (lay.rects[i] as Rect2).intersects(lay.rects[j]), tag + ": items %d / %d don't overlap" % [i, j])
	# 方向键能走到每一项（BFS）
	var seen := {0: true}
	var q: Array = [0]
	while not q.is_empty():
		var s: int = q.pop_front()
		for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
			var n: int = title.Tiles.nav(lay, s, d)
			if not seen.has(n):
				seen[n] = true
				q.append(n)
	for i in ids:
		check(seen.has(i), tag + ": item %d reachable by arrows" % i)
	# Tab 走一圈回到起点
	var s2 := 0
	for k in ids.size():
		s2 = title.Tiles.linear(ids, s2, 1)
	check(s2 == 0, tag + ": tab cycles through all")
	# 命中区在可视区内、触屏时至少 44 高
	for i in ids:
		var rr: Rect2 = lay.rects[i]
		check(Rect2(Vector2.ZERO, title.size).encloses(rr), tag + ": item %d inside screen" % i)
		if Pad.touch_ui():
			check(rr.size.y >= 44.0, tag + ": item %d tall enough to tap (%.0f)" % [i, rr.size.y])


func one_layout(tag: String) -> void:
	# 四种菜单组
	await menu_set(tag + " internal desktop", true, true)
	await menu_set(tag + " public desktop", false, true)
	await menu_set(tag + " internal web", true, false)
	await menu_set(tag + " public web", false, false)
	# 全组：分组导航
	title.menu_boss = true
	title.menu_exit = true
	title.sel = 0
	await frames(3)
	var cp: bool = title.menu_lay.compact
	var D := Vector2i(0, 1)
	var U := Vector2i(0, -1)
	var R := Vector2i(1, 0)
	var L := Vector2i(-1, 0)
	check(walk(7, [D]) == 6 and walk(6, [D]) == 1 and walk(1, [D]) == 8 and walk(8, [D]) == 2, tag + ": side entries go down in order")
	check(walk(2, [U, U, U, U]) == 7 and walk(7, [U]) == 7, tag + ": side entries go up, no wrap")
	check(walk(0, [U]) == 2, tag + ": deploy up -> trial")
	check(walk(4, [R]) == 3 and walk(3, [R]) == 5 and walk(5, [L, L]) == 4 and walk(4, [L]) == 4, tag + ": footer left / right")
	if cp:
		check(walk(2, [D]) == 4 and walk(4, [U]) == 2, tag + ": compact trial <-> footer")
		check(walk(6, [R]) == 0 and walk(5, [R]) == 0 and walk(0, [L]) == 5 and walk(0, [D]) == 0, tag + ": compact deploy sits bottom-right")
	else:
		check(walk(2, [D]) == 0 and walk(0, [D]) == 4 and walk(3, [U]) == 0 and walk(5, [D]) == 5, tag + ": desktop list -> deploy -> footer")
	# 键盘
	title.sel = 0
	await key(KEY_UP)
	check(title.sel == 2, tag + ": key up deploy -> trial (got %d)" % title.sel)
	await key(KEY_W)
	check(title.sel == 8, tag + ": key W trial -> medals")
	await key(KEY_S)
	await key(KEY_DOWN)
	check(title.sel == (4 if cp else 0), tag + ": key down past trial")
	title.sel = 4
	await key(KEY_D)
	check(title.sel == 3, tag + ": key D settings -> guide")
	await key(KEY_LEFT)
	check(title.sel == 4, tag + ": key left guide -> settings")
	title.sel = 0
	await key(KEY_TAB)
	check(title.sel == 4, tag + ": tab deploy -> settings")
	await key(KEY_TAB, true)
	check(title.sel == 0, tag + ": shift+tab -> deploy")
	await key(KEY_ESCAPE)
	check(title.sel == 5, tag + ": esc jumps to exit (doesn't quit)")
	# 手柄十字键（Pad 翻译成方向键）
	title.sel = 0
	await pad(JOY_BUTTON_DPAD_UP)
	check(title.sel == 2, tag + ": dpad up deploy -> trial")
	await pad(JOY_BUTTON_DPAD_UP)
	check(title.sel == 8, tag + ": dpad up trial -> medals")
	# 选中底条：一会儿后新选中项展开、其余收起
	var t0 := Time.get_ticks_msec()
	while title.menu_water[8] < 0.99 and Time.get_ticks_msec() - t0 < 2000:
		await get_tree().process_frame
	check(title.menu_water[8] >= 0.99, tag + ": selected strip opens")
	t0 = Time.get_ticks_msec()
	while title.menu_water[2] > 0.0 and Time.get_ticks_msec() - t0 < 2000:
		await get_tree().process_frame
	check(title.menu_water[2] == 0.0, tag + ": previous strip closes")
	# 网页组：Esc 不动（没有退出）
	title.menu_exit = false
	title.sel = 1
	await frames(2)
	await key(KEY_ESCAPE)
	check(title.sel == 1, tag + ": esc without exit tile keeps selection")
	title.menu_exit = true
	await frames(2)
	# 鼠标：悬停换选中，点「操作说明」打开说明页
	Pad.using = false
	await hover(center(4))
	check(title.sel == 4, tag + ": hover selects tile")
	await click(center(3))
	await wait_idle()
	check(title.guide, tag + ": click opens guide")
	await key(KEY_ENTER)
	await wait_idle()
	check(not title.guide, tag + ": any key closes guide")
	# 难度页
	Cfg.diff_unlocked = 1
	title.diff_sel = 0
	title.diff_pick = true
	await frames(3)
	check(title.diff_rects.has("tier0") and title.diff_rects.has("go") and title.diff_rects.has("back"), tag + ": difficulty hit rects")
	await key(KEY_DOWN)
	check(title.diff_sel == 1, tag + ": down increases depth")
	for i in 4:
		await key(KEY_DOWN)
	check(title.diff_sel == 2, tag + ": down clamps at extreme（三档）")
	title.diff_sel = 2
	await key(KEY_UP)
	check(title.diff_sel == 1, tag + ": up reduces depth")
	await frames(2)
	await click((title.diff_rects["tier0"] as Rect2).get_center())
	check(title.diff_sel == 0, tag + ": click tier card selects it")
	await pad(JOY_BUTTON_DPAD_DOWN)
	check(title.diff_sel == 1, tag + ": dpad down increases depth")
	for r in title.diff_rects.values():
		check(Rect2(Vector2.ZERO, title.size).encloses(r), tag + ": difficulty rect inside screen %s" % str(r))
	# Native touch uses the same transformed hit areas as mouse, including UI scale.
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = title.get_global_transform_with_canvas() * (title.diff_rects["tier0"] as Rect2).get_center()
	title._diff_input(touch)
	check(title.diff_sel == 0, tag + ": direct touch selects standard")
	# 未解锁档：出发无效
	title.diff_sel = 2
	await frames(2)
	await key(KEY_ENTER)
	check(title.diff_pick and title.leaving < 0.0, tag + ": locked tier can't deploy")
	# Growth is available from the controller/keyboard without losing difficulty.
	await key(KEY_X)
	await wait_idle()
	check(title.meta_ui.visible, tag + ": difficulty X opens cognitive growth")
	await key(KEY_ESCAPE)
	await wait_idle()
	check(not title.meta_ui.visible and title.diff_pick and title.diff_sel == 2, tag + ": growth closes back to same difficulty")
	await key(KEY_ESCAPE)
	await wait_idle()
	check(not title.diff_pick, tag + ": esc leaves difficulty")
	title.op_pick = false
	await frames(2)


func run() -> void:
	var screen = preload("res://scripts/screens/difficulty_screen.gd")
	var data = preload("res://scripts/data.gd")
	for tier in 3:
		var mods: Dictionary = data.dmod_for_preset(tier)   # 难度页显示该档实际修正（深潮档带 enemy_scale）
		var lines: Array = screen.condition_lines(tier)
		for line in data.dmod_lines(mods):
			check(lines.has(line), "difficulty preserves real modifier: " + str(line))
		if tier > 0:
			for label in ["灯标刷新间隔"]:   # 围猎两项 10-29 随独立围猎删除
				check("\n".join(lines).contains(label), "difficulty includes benefit: " + label)
	var survey = screen.new()
	survey.tick(0.0, 0, false)
	survey.tick(0.1, 2, false)
	check(survey.depth > 0.0 and survey.depth < 2.0, "difficulty locator moves along depth contour")
	var visual_time: float = survey.clock
	survey.tick(1.0, 2, true)
	check(survey.depth == 2.0 and survey.clock == visual_time and survey.change == 1.0, "reduce motion snaps depth and freezes scenery")
	survey = null
	title = load("res://main.tscn").instantiate()
	add_child(title)
	await get_tree().process_frame
	title.intro = title.INTRO_LEN
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	title.position = Vector2.ZERO
	title.size = Vector2(1280, 720)
	await frames(3)
	await one_layout("desktop")
	Cfg._touch = 1
	Pad.touch = true
	title.size = Vector2(1044, 481)
	await frames(2)
	await one_layout("touch")
	Cfg._touch = -1
	Pad.touch = false
	title.queue_free()
	await get_tree().process_frame
	print("TITLE MENU INPUT: %d failures" % failures)
	get_tree().quit.call_deferred(1 if failures else 0)
