extends Node
## 自由更改键位回归（11-16 用户「自由更改键位」，core/play_keys.gd + screens/keybind_view.gd）：
## - 绑定表：缺省、改绑、冲突返回占用者、交换、Esc / START 锁定、网页保留键（F5 等）拦下、恢复默认；
## - 存档：ConfigFile 往返（旧存档没有这项 = 缺省）、云存档正文带 keybinds（没改过不写）、cloud_apply 读回；
## - 局内生效：改绑后新键冲刺、旧键不冲；暂停备用键；鼠标侧键倍速；手柄（Pad 按绑定注入虚拟键）冲刺；移动改键；
## - 键名提示：PlayKeys.cur / fill、指南「操作」页与 HUD 读当前绑定；
## - 键位页：点格子等新键、冲突弹框交换、恢复默认、Esc 关闭；
## - --kbshot=<目录>：窗口模式下截键鼠页 / 手柄页 / 冲突框 / 改键后的操作说明页（tools 另跑，不进快检）。
const PlayKeys = preload("res://scripts/core/play_keys.gd")

var failures := 0
var checks := 0
var shot_dir := ""


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("KEYBIND: " + what)
		print("FAIL KEYBIND: " + what)


func _ready() -> void:
	for a in Cfg.dev_args():
		if a.begins_with("--kbshot="):
			shot_dir = a.substr(9)
	call_deferred("run")


func frames(n := 2) -> void:
	for i in n:
		await get_tree().process_frame


func kev(k: int, down: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	return e


func key(k: int) -> void:
	Input.parse_input_event(kev(k, true))
	await get_tree().process_frame
	Input.parse_input_event(kev(k, false))
	await frames()


func shot(name: String) -> void:
	if shot_dir == "":
		return
	await frames(3)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(shot_dir)
	img.save_png(shot_dir.path_join(name + ".png"))
	print("KEYBIND SHOT " + name)


func table_part() -> void:
	PlayKeys.reset_all()
	check(PlayKeys.act(kev(KEY_SPACE, true)) == "dash" and PlayKeys.act(kev(KEY_Q, true)) == "ult", "缺省：空格冲刺、Q 终结技")
	check(PlayKeys.pad_action(JOY_BUTTON_B) == "dash" and PlayKeys.pad_action(PlayKeys.PAD_RT) == "dash" and PlayKeys.pad_action(JOY_BUTTON_A) == "ult", "缺省手柄：Ⓑ / RT 冲刺、Ⓐ 终结技")
	check(PlayKeys.pad_action(JOY_BUTTON_Y) == "" and PlayKeys.action_of(KEY_E) == "", "E / Ⓨ 没有绑定")
	check(PlayKeys.forbidden(KEY_ESCAPE, false) != "", "Esc 不能绑")
	check(PlayKeys.forbidden(KEY_F5, false, true) != "" and PlayKeys.forbidden(KEY_F11, false, true) != "" and PlayKeys.forbidden(KEY_CTRL, false, true) != "", "网页：F5 / F11 / Ctrl 不能绑")
	check(PlayKeys.forbidden(KEY_F5, false, false) == "", "桌面：F5 可以绑")
	check(PlayKeys.forbidden(JOY_BUTTON_START, true) != "", "手柄 START 固定暂停")
	check(PlayKeys.bind("pause", false, 0, KEY_L).is_empty() and int(PlayKeys.get_slots("pause", false)[0]) == KEY_ESCAPE, "暂停主键（Esc）锁定，改不动")
	check(PlayKeys.bind("dash", false, 0, KEY_L).is_empty(), "冲刺主键改 L")
	check(PlayKeys.act(kev(KEY_L, true)) == "dash" and PlayKeys.act(kev(KEY_SPACE, true)) == "", "改后 L 冲刺、空格无动作")
	var who: Array = PlayKeys.bind("dash", false, 0, KEY_Q)
	check(who == ["ult", 0], "冲突：Q 被终结技占用（%s）" % [who])
	check(PlayKeys.act(kev(KEY_L, true)) == "dash", "冲突未确认时不改")
	PlayKeys.bind("dash", false, 0, KEY_Q, true)
	check(PlayKeys.act(kev(KEY_Q, true)) == "dash" and PlayKeys.act(kev(KEY_L, true)) == "ult", "交换：Q 冲刺、L 终结技")
	check(PlayKeys.bind("pause", false, 1, KEY_ESCAPE) == ["pause", 0], "Esc 占用者是锁定格")
	PlayKeys.bind("speed", false, 0, PlayKeys.M_X1)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_XBUTTON1
	mb.pressed = true
	check(PlayKeys.act(mb) == "speed", "鼠标侧键可绑（倍速）")
	PlayKeys.bind("dash", true, 0, JOY_BUTTON_X)
	check(PlayKeys.pad_action(JOY_BUTTON_X) == "dash" and PlayKeys.pad_action(JOY_BUTTON_B) == "", "手柄冲刺改 Ⓧ")
	# 存档往返
	var ov: Dictionary = PlayKeys.overrides()
	check(ov.has("kb") and ov.has("pad") and not (ov.kb as Dictionary).has("up"), "只存改过的动作（%s）" % [ov])
	var c := ConfigFile.new()
	Cfg.keybinds_set = true
	Cfg.save_keybinds(c)
	var p := "user://keybind_test.cfg"
	c.save(p)
	PlayKeys.reset_all()
	var c2 := ConfigFile.new()
	c2.load(p)
	Cfg.load_keybinds(c2)
	check(PlayKeys.act(kev(KEY_Q, true)) == "dash" and PlayKeys.pad_action(JOY_BUTTON_X) == "dash" and PlayKeys.act(mb) == "speed", "存档重载后保留")
	var c3 := ConfigFile.new()
	Cfg.load_keybinds(c3)
	check(PlayKeys.act(kev(KEY_SPACE, true)) == "dash", "旧存档没有这项 = 缺省")
	Cfg.load_keybinds(c2)
	# 坏数据：重复 / 类型不对 / 锁定格被改
	PlayKeys.apply({"kb": {"dash": [KEY_Q, "x"], "ult": [KEY_Q, KEY_Q], "pause": [KEY_L, KEY_P]}})
	check(int(PlayKeys.get_slots("pause", false)[0]) == KEY_ESCAPE and int(PlayKeys.get_slots("ult", false)[0]) == 0 and int(PlayKeys.get_slots("dash", false)[1]) == 0, "坏存档清洗（%s / %s）" % [PlayKeys.get_slots("ult", false), PlayKeys.get_slots("dash", false)])
	Cfg.load_keybinds(c2)
	# 云存档
	var body: Dictionary = Cfg.cloud_body()
	check((body.set.d as Dictionary).has("keybinds"), "云存档正文带 keybinds")
	PlayKeys.reset_all()
	Cfg.cloud_apply(body)
	check(PlayKeys.act(kev(KEY_Q, true)) == "dash", "云存档读回键位")
	var body2: Dictionary = body.duplicate(true)
	(body2.set.d as Dictionary).erase("keybinds")
	Cfg.cloud_apply(body2)
	check(PlayKeys.act(kev(KEY_Q, true)) == "dash", "云端没有 keybinds 时保持本机")
	Cfg.keybinds_set = false
	PlayKeys.reset_all()
	check(not (Cfg.cloud_body().set.d as Dictionary).has("keybinds"), "没改过：云存档不写 keybinds（旧档往返不变）")
	# 恢复默认（分页）
	PlayKeys.bind("dash", false, 0, KEY_L)
	PlayKeys.bind("dash", true, 0, JOY_BUTTON_X)
	PlayKeys.reset_page(false)
	check(PlayKeys.act(kev(KEY_SPACE, true)) == "dash" and PlayKeys.pad_action(JOY_BUTTON_X) == "dash", "键鼠页恢复默认不动手柄页")
	PlayKeys.reset_page(true)
	check(PlayKeys.pad_action(JOY_BUTTON_B) == "dash", "手柄页恢复默认")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func game_part() -> void:
	PlayKeys.reset_all()
	var g: Node = load("res://game.tscn").instantiate()
	add_child(g)
	await frames(10)
	if g.intro_screen != null:
		g.intro_screen.close()
	g.state = g.S.PLAY
	await frames(5)
	# 冲刺改 L：L 冲、空格不冲
	PlayKeys.bind("dash", false, 0, KEY_L)
	PlayKeys.set_slot("dash", false, 1, 0)
	g.dash_cd = 0.0
	g.dash_t = 0.0
	await key(KEY_SPACE)
	check(g.dash_cd <= 0.0, "改键后空格不再冲刺（dash_cd=%.2f）" % g.dash_cd)
	await key(KEY_L)
	check(g.dash_cd > 0.0, "改键后 L 冲刺（dash_cd=%.2f）" % g.dash_cd)
	# 手柄：冲刺改 Ⓧ，Pad 按绑定注入虚拟键
	PlayKeys.bind("dash", true, 0, JOY_BUTTON_X)
	g.dash_cd = 0.0
	g.dash_t = 0.0
	Pad.context = "play"
	Pad._play_btn(JOY_BUTTON_B, true)
	Pad._play_btn(JOY_BUTTON_B, false)
	await frames(3)
	check(g.dash_cd <= 0.0, "手柄 Ⓑ 改走后不冲刺")
	Pad._play_btn(JOY_BUTTON_X, true)
	Pad._play_btn(JOY_BUTTON_X, false)
	await frames(3)
	check(g.dash_cd > 0.0, "手柄 Ⓧ 冲刺（dash_cd=%.2f）" % g.dash_cd)
	# 移动：向上改 I
	PlayKeys.bind("up", false, 0, KEY_I)
	Input.parse_input_event(kev(KEY_I, true))
	await frames(4)
	check(PlayKeys.held("up") and g.move_in.y < 0.0, "向上改 I 后按 I 往上走（move_in=%s）" % g.move_in)
	Input.parse_input_event(kev(KEY_I, false))
	Input.parse_input_event(kev(KEY_W, true))
	await frames(4)
	check(g.move_in.y >= 0.0, "W 不再往上（move_in=%s）" % g.move_in)
	Input.parse_input_event(kev(KEY_W, false))
	await frames(2)
	# 倍速绑鼠标侧键
	PlayKeys.bind("speed", false, 0, PlayKeys.M_X1)
	var sp0: float = Cfg.play_speed
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_XBUTTON1
	mb.pressed = true
	mb.position = Vector2(640, 360)
	get_viewport().push_input(mb, true)
	await frames(2)
	mb = mb.duplicate()
	mb.pressed = false
	get_viewport().push_input(mb, true)
	await frames(2)
	check(Cfg.play_speed != sp0, "鼠标侧键切倍速（%.1f → %.1f）" % [sp0, Cfg.play_speed])
	Cfg.play_speed = sp0
	# 暂停备用键改 Y；Esc 照样暂停
	PlayKeys.bind("pause", false, 1, KEY_Y)
	await key(KEY_Y)
	check(g.state == g.S.PAUSE, "备用暂停键 Y 暂停（state=%d）" % g.state)
	await key(KEY_Y)
	check(g.state == g.S.PLAY, "Y 继续")
	await key(KEY_ESCAPE)
	check(g.state == g.S.PAUSE, "Esc 仍是暂停")
	await key(KEY_ESCAPE)
	# 属性面板改 J
	PlayKeys.bind("stats", false, 0, KEY_J)
	await key(KEY_J)
	check(g.state == g.S.STATS, "属性面板改 J")
	await key(KEY_J)
	check(g.state == g.S.PLAY, "J 关属性面板")
	# 键名提示
	check(PlayKeys.cur("dash") == "L" and PlayKeys.cur("stats") == "J", "按键提示读当前绑定（%s / %s）" % [PlayKeys.cur("dash"), PlayKeys.cur("stats")])
	check(PlayKeys.fill("{dash}·{move}·{stats2}") == "L·I A S D·J / C", "文案占位填当前绑定（%s）" % PlayKeys.fill("{dash}·{move}·{stats2}"))
	var last: int = g.intro_screen.pages().size() - 1
	var txt := ""
	for r in g.intro_screen._rows_of(last):
		txt += str(r.text) + "\n"
	check(not txt.contains("{") and txt.contains("J / C"), "指南「操作」页读当前绑定：\n" + txt)
	# 截图：改键后的操作说明页
	if shot_dir != "":
		g.state = g.S.PAUSE
		await frames(2)
		g.intro_screen.open(g.S.PAUSE)
		g.intro_page = g.intro_screen.views().size() - 1   # 指南按视图翻页：最后一张是「操作」页
		g.intro_t = 0.0
		await get_tree().create_timer(1.5).timeout   # 等翻页淡入走完
		await shot("guide_controls_rebound_" + UI_lang())
		g.intro_screen.close()
		g.state = g.S.PLAY
	await settings_part(g)
	g.queue_free()
	await frames(3)
	PlayKeys.reset_all()


func UI_lang() -> String:
	return preload("res://scripts/core/loc.gd").lang


func settings_part(g: Node) -> void:
	g.state = g.S.PAUSE
	await frames(2)
	var st: Control = g.settings
	st.open()
	await frames(3)
	st.open_keybinds(false)
	var kv: Control = st.keybind_view
	await frames(3)
	check(kv != null and kv.visible, "键位页打开")
	var rs: Array = kv.rows()
	check(rs.size() == PlayKeys.ACTIONS.size(), "键鼠页列出全部 %d 个动作" % PlayKeys.ACTIONS.size())
	var di := -1
	for i in rs.size():
		if str(rs[i].id) == "dash":
			di = i
	await shot("keybind_kb_" + UI_lang())
	# 点格子 → 按 K
	kv.begin_listen(di, 0)
	check(kv.listen, "进入等待新按键")
	await key(KEY_K)
	check(not kv.listen and int(PlayKeys.get_slots("dash", false)[0]) == KEY_K, "按 K 绑到冲刺主键")
	# 冲突：备用格按 Q（终结技占用）
	kv.begin_listen(di, 1)
	await key(KEY_Q)
	check(not kv.conflict.is_empty(), "冲突弹框")
	await shot("keybind_conflict_" + UI_lang())
	await key(KEY_ENTER)
	check(kv.conflict.is_empty() and int(PlayKeys.get_slots("dash", false)[1]) == KEY_Q and int(PlayKeys.get_slots("ult", false)[0]) == 0, "Enter 交换（终结技拿到冲刺备用格原来的键）")
	# 等新按键时 Esc 只取消
	kv.begin_listen(di, 0)
	await key(KEY_ESCAPE)
	check(kv.visible and not kv.listen, "等待中 Esc 只取消")
	# Esc 键不能绑
	check(PlayKeys.bind("dash", false, 0, KEY_ESCAPE) == ["pause", 0], "Esc 已被暂停锁定")
	# 恢复默认
	kv.reset_page()
	check(int(PlayKeys.get_slots("dash", false)[0]) == KEY_SPACE and int(PlayKeys.get_slots("ult", false)[0]) == KEY_Q, "恢复默认")
	# 手柄页
	await key(KEY_E)
	check(kv.pad_page, "E 切到手柄页")
	check(kv.rows().size() == PlayKeys.pad_ids().size() + PlayKeys.PAD_FIXED.size(), "手柄页：可改动作 + 摇杆固定项")
	await shot("keybind_pad_" + UI_lang())
	await key(KEY_ESCAPE)
	check(not kv.visible and st.visible, "Esc 关键位页、回到设置")
	st.close()
	await frames(2)
	g.state = g.S.PLAY


func run() -> void:
	if shot_dir != "":
		await get_tree().create_timer(7.0).timeout   # 测试窗口前 6 秒最小化（godot_runner ARK_NO_FOCUS），等它恢复再截
	table_part()
	await game_part()
	print("KEYBIND checks=%d failures=%d" % [checks, failures])
	get_tree().quit.call_deferred(1 if failures else 0)
