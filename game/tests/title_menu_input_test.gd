extends Node
## 标题页 T5s 磁贴群与难度页（docs/67 §12）输入回归：
## - 四种菜单组（内部 / 对外 × 桌面 / 网页）：没有空格子（每行铺满整宽、编号连号）、方向键能走到每一块；
## - 二维导航邻接（docs/67 §10.3：01↓02、02↓04、03↓06、04↑02、05↑02、06↑03，记住列：03↑01↓03）；
## - 键盘 ↑↓←→ / WASD、Tab / Shift+Tab、手柄十字键（经 Pad 翻译）、Esc 跳到退出、鼠标悬停 / 点击、选中涨潮；
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
	var Tiles = title.Tiles
	var s := from
	var mem: float = (title.menu_lay.rects[from] as Rect2).get_center().x
	for d in dirs:
		var r: Array = Tiles.nav(title.menu_lay, s, d, mem)
		s = r[0]
		mem = r[1]
	return s


func menu_set(tag: String, boss: bool, ex: bool) -> void:
	title.menu_boss = boss
	title.menu_exit = ex
	title.sel = 0
	title.menu_mem_x = -1.0
	await frames(3)
	var ids: Array = title._menu_ids()
	var lay: Dictionary = title.menu_lay
	check(lay.rects.size() == ids.size(), tag + ": one tile per visible item (%d / %d)" % [lay.rects.size(), ids.size()])
	check(lay.rows.size() == 3, tag + ": three rows")
	# 没有空格子：每行左端齐、右端齐（铺满整宽）
	var w: float = lay.w
	var x0: float = (lay.rects[0] as Rect2).position.x
	for row in lay.rows:
		var l: Rect2 = lay.rects[row[0]]
		var r: Rect2 = lay.rects[row[row.size() - 1]]
		check(absf(l.position.x - x0) < 0.5 and absf(r.end.x - (x0 + w)) < 0.5, tag + ": row %s spans full width" % str(row))
		for k in row.size() - 1:
			check((lay.rects[row[k]] as Rect2).end.x < (lay.rects[row[k + 1]] as Rect2).position.x, tag + ": tiles don't overlap")
	# 编号连号 01…n（按可见顺序）
	for k in ids.size():
		check(int(lay.num[ids[k]]) == k + 1, tag + ": item %d numbered %d" % [ids[k], k + 1])
	# 方向键能走到每一块（BFS）
	var seen := {0: true}
	var q: Array = [0]
	while not q.is_empty():
		var s: int = q.pop_front()
		for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
			for mem in [center(s).x, x0, x0 + w]:
				var n: int = title.Tiles.nav(lay, s, d, mem)[0]
				if not seen.has(n):
					seen[n] = true
					q.append(n)
	for i in ids:
		check(seen.has(i), tag + ": tile %d reachable by arrows" % i)
	# Tab 走一圈回到起点
	var s2 := 0
	for k in ids.size():
		s2 = title.Tiles.linear(ids, s2, 1)
	check(s2 == 0, tag + ": tab cycles through all")
	# 命中区在可视区内、触屏时小号磁贴至少 44 高
	for i in ids:
		var rr: Rect2 = lay.rects[i]
		check(Rect2(Vector2.ZERO, title.size).encloses(rr), tag + ": tile %d inside screen" % i)
		if Pad.touch_ui():
			check(rr.size.y >= 44.0, tag + ": tile %d tall enough to tap (%.0f)" % [i, rr.size.y])


func one_layout(tag: String) -> void:
	# 四种菜单组
	await menu_set(tag + " internal desktop", true, true)
	await menu_set(tag + " public desktop", false, true)
	await menu_set(tag + " internal web", true, false)
	await menu_set(tag + " public web", false, false)
	# 全组：邻接表（docs/67 §10.3）
	title.menu_boss = true
	title.menu_exit = true
	title.sel = 0
	await frames(3)
	var D := Vector2i(0, 1)
	var U := Vector2i(0, -1)
	var R := Vector2i(1, 0)
	var L := Vector2i(-1, 0)
	# 10-22 第二行加「认知塑造」（id 6，docs/109 §4）：第二行三块、第三行三块，上下同列
	check(walk(0, [D]) == 2, tag + ": 01 down -> 03（正中）")
	check(walk(1, [D]) == 3, tag + ": 02 down -> 05")
	check(walk(2, [D]) == 4, tag + ": 03 down -> 06")
	check(walk(6, [D]) == 5, tag + ": 04 down -> 07")
	check(walk(3, [U]) == 1, tag + ": 05 up -> 02")
	check(walk(4, [U]) == 2, tag + ": 06 up -> 03")
	check(walk(5, [U]) == 6, tag + ": 07 up -> 04")
	check(walk(2, [U, D]) == 2, tag + ": 03 up down returns to 03 (column memory)")
	check(walk(4, [U, D]) == 4, tag + ": 05 up down returns to 05")
	check(walk(0, [U]) == 0 and walk(5, [D]) == 5 and walk(3, [L]) == 3 and walk(5, [R]) == 5, tag + ": no wrap at edges")
	# 键盘
	title.sel = 0
	title.menu_mem_x = -1.0
	await key(KEY_DOWN)
	check(title.sel == 2, tag + ": key down 01 -> 03 (got %d)" % title.sel)
	await key(KEY_D)
	check(title.sel == 6, tag + ": key D 03 -> 04")
	await key(KEY_S)
	check(title.sel == 5, tag + ": key S 04 -> 07")
	await key(KEY_LEFT)
	check(title.sel == 4, tag + ": key left 07 -> 06")
	await key(KEY_W)
	await key(KEY_W)
	check(title.sel == 0, tag + ": key W twice -> 01")
	await key(KEY_TAB)
	check(title.sel == 1, tag + ": tab -> 02")
	await key(KEY_TAB, true)
	check(title.sel == 0, tag + ": shift+tab -> 01")
	await key(KEY_ESCAPE)
	check(title.sel == 5, tag + ": esc jumps to exit (doesn't quit)")
	# 手柄十字键（Pad 翻译成方向键）
	title.sel = 0
	title.menu_mem_x = -1.0
	await pad(JOY_BUTTON_DPAD_DOWN)
	check(title.sel == 2, tag + ": dpad down 01 -> 03")
	await pad(JOY_BUTTON_DPAD_RIGHT)
	check(title.sel == 6, tag + ": dpad right 03 -> 04")
	# 选中涨潮：一会儿后新选中块水位满、其余退潮
	var t0 := Time.get_ticks_msec()
	while title.menu_water[6] < 0.99 and Time.get_ticks_msec() - t0 < 2000:
		await get_tree().process_frame
	check(title.menu_water[6] >= 0.99, tag + ": selected tile water rises")
	t0 = Time.get_ticks_msec()
	while title.menu_water[2] > 0.0 and Time.get_ticks_msec() - t0 < 2000:
		await get_tree().process_frame
	check(title.menu_water[2] == 0.0, tag + ": previous tile drains")
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
	await key(KEY_UP)
	check(title.diff_sel == 1, tag + ": up raises tier")
	for i in 20:
		await key(KEY_UP)
	check(title.diff_sel == 15, tag + ": up clamps at top tide (15)")
	title.diff_sel = 2
	await key(KEY_DOWN)
	check(title.diff_sel == 1, tag + ": down lowers tier")
	await frames(2)
	await click((title.diff_rects["tier0"] as Rect2).get_center())
	check(title.diff_sel == 0, tag + ": click tier card selects it")
	await pad(JOY_BUTTON_DPAD_UP)
	check(title.diff_sel == 1, tag + ": dpad up raises tier")
	for r in title.diff_rects.values():
		check(Rect2(Vector2.ZERO, title.size).encloses(r), tag + ": difficulty rect inside screen %s" % str(r))
	# 未解锁档：出发无效
	title.diff_sel = 2
	await frames(2)
	await key(KEY_ENTER)
	check(title.diff_pick and title.leaving < 0.0, tag + ": locked tier can't deploy")
	await key(KEY_ESCAPE)
	await wait_idle()
	check(not title.diff_pick, tag + ": esc leaves difficulty")
	title.op_pick = false
	await frames(2)


func run() -> void:
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
