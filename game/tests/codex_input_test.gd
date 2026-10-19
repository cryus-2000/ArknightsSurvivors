extends Node
## 图鉴 C4'（docs/58 §11）输入与版式回归：键盘 / 手柄（经 Pad 翻译）/ 鼠标 / 触屏（模拟触点 → 鼠标）都能换分类、换条目、换页签、
## 换动作、职业筛选、返回；干员名册按 data/characters 自动生成；每名干员的立绘按选人页同一规则（UI.art_fit）放进舞台框（桌面 / 手机）；
## 七个分类都能建表并画出来；「减少动态效果」直接到终态；图鉴脚本不用任何随机数。
const Character = preload("res://scripts/characters/character.gd")
var failures := 0
var title: Control
var gal: Control


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("CODEX: " + what)


func _ready() -> void:
	call_deferred("run")


func key(k: int) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.pressed = down
		Input.parse_input_event(e)
	await get_tree().process_frame
	await get_tree().process_frame


func pad(b: int) -> void:
	for down in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = b
		e.pressed = down
		Input.parse_input_event(e)
		await get_tree().process_frame
	await get_tree().process_frame


func settle() -> void:
	for i in 4:
		await get_tree().process_frame


## 关图鉴后标题页有 0.18 秒退暗（转场锁输入），等它结束
func idle() -> void:
	var t0 := Time.get_ticks_msec()
	await settle()
	while title.transition.busy and Time.get_ticks_msec() - t0 < 3000:
		await get_tree().process_frame


## 图鉴上一帧画出的命中区（设计坐标）
func hit(kind: String, v) -> Rect2:
	for h in gal.hits:
		if h[1] == kind and (v == null or h[2] == v):
			return h[0]
	return Rect2()


## 点设计坐标里某个命中区的中心（Viewport.push_input 本地坐标）；touch = 触屏模拟（中间加一段 2 像素拖动）
func click(r: Rect2, touch := false) -> void:
	var p: Vector2 = gal.get_global_transform() * (gal.doff + r.get_center() * gal.dk)
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


func run() -> void:
	Cfg.reduce_motion = false
	Cfg._touch = 0
	title = load("res://main.tscn").instantiate()
	add_child(title)
	await get_tree().process_frame
	title.intro = title.INTRO_LEN
	gal = title.gallery
	gal.open()
	await settle()
	check(gal.visible and gal.tab == 0, "opens on operator page")
	# 名册：data/characters 里每名干员都在（新干员自动出现）+ 博士
	var ids: Array = Character.list_ids()
	var op_ids: Array = []
	for e in gal.entries:
		if e.has("op"):
			op_ids.append(e.id)
	for cid in ids:
		check(op_ids.has(cid), "operator %s listed" % cid)
	check(op_ids.size() == ids.size(), "operator count %d == %d" % [op_ids.size(), ids.size()])
	check(gal.entries[0].id == "mizuki", "cover operator first")
	check(gal.entries[gal.entries.size() - 1].id == "doctor", "doctor last")
	check(gal.INFO_TABS == ["档案", "属性", "技能", "成长"], "info tabs are 档案 / 属性 / 技能 / 成长 only")
	var ui = load("res://scripts/ui.gd")
	check(ui.fit_h(Rect2(0, 0, 90, 96), 192.0, 2.0) == 96.0, "native canvas fits full visible height")
	check(ui.fit_h(Rect2(0, 0, 90, 96), 128.0, 2.0) == 74.0, "legacy 64 canvas retains body cap")
	# 立绘适配：每名干员（桌面 / 手机）待机帧并集区按整数倍放进舞台框（四边至少留 2），倍数不超过选人页上限
	for ph in [false, true]:
		Cfg._touch = 1 if ph else 0
		var sr: Rect2 = gal._stage()
		for e in gal.entries:
			if not e.has("op"):
				continue
			var fit: Array = gal._art_fit(e, ph)
			var od: Dictionary = gal._od(e)
			var bb: Rect2 = od.bb
			check(bb.size.x > 0.0 and bb.size.y > 0.0, "%s has idle frame" % e.id)
			var sz: Vector2 = bb.size * 2.0 / float(od.hires) * float(fit[0])
			var box := Rect2(fit[1].x - sz.x / 2.0, fit[1].y - sz.y, sz.x, sz.y)
			check(float(fit[0]) == floorf(float(fit[0])) and float(fit[0]) >= 1.0, "integer art scale for %s" % e.id)
			check(float(fit[0]) <= (2.0 if ph else 4.0), "art scale capped like operator select for %s" % e.id)
			check(sr.grow(-2.0).encloses(box), "%s art fits stage %s on %s: %s" % [e.id, str(sr), "phone" if ph else "desktop", str(box)])
	Cfg._touch = 0
	await settle()
	# 键盘
	var v: Array = gal.vlist
	gal._set_sel(v[0])
	await settle()
	await key(KEY_RIGHT)
	check(gal.sel == v[1], "keyboard right selects next")
	await key(KEY_DOWN)
	check(gal.sel == v[1 + gal.cols()], "keyboard down moves one row")
	await key(KEY_UP)
	await key(KEY_LEFT)
	check(gal.sel == v[0], "keyboard up / left back to first")
	gal.info_tab = 0
	await key(KEY_ENTER)
	check(gal.info_tab == 1, "enter cycles info tab")
	await key(KEY_3)
	check(gal.info_tab == 2, "number key picks info tab")
	await key(KEY_X)
	check(gal.form == 1, "X next form")
	await key(KEY_Z)
	check(gal.form == 0, "Z previous form")
	# 职业轨：最左一列再 ← 进轨，↓ 筛选，→ 回网格
	await key(KEY_LEFT)
	check(gal.rail_focus, "left at first column focuses class rail")
	await key(KEY_DOWN)
	check(gal.filter != "", "rail down applies class filter")
	var all_in := true
	for i in gal.vlist:
		all_in = all_in and gal.entries[i].get("cls", "") == gal.filter
	check(all_in and not gal.vlist.is_empty(), "filtered grid only shows that class")
	check(gal.vlist.has(gal.sel), "selection moves into filtered class")
	await key(KEY_UP)
	check(gal.filter == "", "rail up back to ALL")
	await key(KEY_RIGHT)
	check(not gal.rail_focus, "right leaves rail")
	await key(KEY_E)
	check(gal.tab == 1, "E next category")
	await key(KEY_Q)
	check(gal.tab == 0, "Q previous category")
	# 手柄（Pad 在标题页把十字键 / LB RB / A / X / B 翻译成按键）
	var s1: int = gal.sel
	await pad(JOY_BUTTON_DPAD_RIGHT)
	check(gal.sel != s1, "gamepad dpad right switches operator")
	var it: int = gal.info_tab
	await pad(JOY_BUTTON_A)
	check(gal.info_tab == (it + 1) % gal.INFO_TABS.size(), "gamepad A cycles info tab")
	await pad(JOY_BUTTON_X)
	check(gal.form != 0, "gamepad X changes form")
	await pad(JOY_BUTTON_RIGHT_SHOULDER)
	check(gal.tab == 1, "gamepad RB next category")
	await pad(JOY_BUTTON_LEFT_SHOULDER)
	check(gal.tab == 0, "gamepad LB previous category")
	# 鼠标
	await settle()
	var r := hit("card", gal.vlist[2])
	check(r.size.x > 0.0, "card hit rects present")
	await click(r)
	check(gal.sel == gal.vlist[2], "mouse click selects card")
	await settle()
	r = hit("itab", 0)
	check(r.size.x > 0.0, "info tab hit rects present")
	await click(r)
	check(gal.info_tab == 0, "mouse click changes info tab")
	await settle()
	r = hit("form", 1)
	if r.size.x > 0.0:
		await click(r)
		check(gal.form == 1, "mouse click changes form")
	else:
		check(false, "form hit rects present")
	await settle()
	await click(hit("cls", "近卫"))
	check(gal.filter == "近卫", "mouse click filters class")
	await settle()
	await click(hit("cls", ""))
	check(gal.filter == "", "mouse click clears filter")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = gal.get_global_transform() * (gal.doff + Vector2(200, 300) * gal.dk)
	get_viewport().push_input(wheel, true)
	await settle()
	check(gal.scroll == mini(1, gal._max_scroll()), "mouse wheel scrolls grid")
	# 七个分类都能建表、画出来（有格子命中区）
	for ti in gal.TABS.size():
		await settle()
		await click(hit("cat", ti))
		check(gal.tab == ti, "mouse click category %d" % ti)
		await settle()
		check(hit("card", null).size.x > 0.0, "category %d draws cards" % ti)
		check(hit("back", null).size.x > 0.0, "category %d has back button" % ti)
	await click(hit("cat", 0))
	# 减少动态效果：换人后位移类动效当帧到终态
	Cfg.reduce_motion = true
	await key(KEY_RIGHT)
	check(gal._p(gal.sw_t0, 0.06, 0.3) == 1.0 and gal._lift(gal.sel) == 1.0, "reduce motion snaps to end state")
	check(gal._row(0).x == 0.0 and gal._open_dx() == 0.0, "reduce motion: no panel slide")
	Cfg.reduce_motion = false
	# 返回：点返回 / Esc
	await settle()
	await click(hit("back", null))
	check(not gal.visible, "back button closes codex")
	await idle()
	gal.open()
	await settle()
	await key(KEY_ESCAPE)
	check(not gal.visible, "escape closes codex")
	await idle()
	# 触屏（手机版式 740×360）：点卡、点页签、点开技能行、点分类、点返回
	Cfg._touch = 1
	gal.open()
	await settle()
	await settle()
	check(gal._dsz() == gal.PHONE, "touch uses phone layout")
	r = hit("card", gal.vlist[1])
	check(r.size.x > 0.0, "phone card rects present")
	await click(r, true)
	check(gal.sel == gal.vlist[1], "touch tap selects card")
	await settle()
	await click(hit("itab", 2), true)
	check(gal.info_tab == 2, "touch tap changes info tab (skills)")
	await settle()
	r = hit("row", 2)
	check(r.size.x > 0.0, "phone skill rows tappable")
	await click(r, true)
	check(gal.row_sel == 2, "touch tap expands skill row")
	await settle()
	await click(hit("cat", 2), true)
	check(gal.tab == 2, "touch tap changes category")
	await settle()
	await click(hit("back", null), true)
	check(not gal.visible, "touch back closes codex")
	Cfg._touch = -1
	# 图鉴脚本不用随机数（界面动效只用固定曲线，不碰 g.rng）
	var src := FileAccess.get_file_as_string("res://scripts/gallery.gd")
	for bad in ["randf", "randi", "rng", "randomize"]:
		check(not bad in src, "gallery.gd uses no randomness (%s)" % bad)
	title.queue_free()
	await get_tree().process_frame
	print("CODEX INPUT: %d failures" % failures)
	get_tree().quit.call_deferred(1 if failures else 0)
