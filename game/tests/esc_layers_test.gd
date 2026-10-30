extends Node
## 各层 ESC 与设置页键盘输入回归（界面与美术 10-14，协调人派「ESC 不起作用、键盘输入有问题」）：
## - 标题页：设置 / 图鉴 / 操作说明 / 致谢各自按 Esc 关掉当前这一层，回到标题菜单（docs/37 §导航）；
## - 设置页：↑↓ 换行、←→ 调数值、Q / E 换页、Enter 切开关；右上角「×」点一下关闭；滚轮滚列表；
## - 输入法 / 网页：只带物理键码（keycode = 0）的按键事件也要认（中文输入法开着时浏览器常这样发）；
## - 按住 Esc 不连锁：关掉设置那一下之后的自动重复（echo）不能再落到下一层（暂停被解除 / 焦点跳走）；
## - 局内：Esc 暂停 / 继续；暂停里 O 开设置、Esc 只关设置（仍在暂停）。
var failures := 0
var title: Control


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("ESC LAYERS: " + what)


func _ready() -> void:
	call_deferred("run")


func frames(n := 2) -> void:
	for i in n:
		await get_tree().process_frame


## phys_only：只给物理键码（keycode = 0），模拟输入法 / 部分网页键盘事件
func key(k: int, phys_only := false, echo_n := 0) -> void:
	var e := InputEventKey.new()
	if phys_only:
		e.physical_keycode = k
	else:
		e.keycode = k
		e.physical_keycode = k
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	for j in echo_n:
		var r := e.duplicate()
		r.echo = true
		Input.parse_input_event(r)
		await get_tree().process_frame
	var u := e.duplicate()
	u.pressed = false
	u.echo = false
	Input.parse_input_event(u)
	await frames()


func vp(c: Control, local: Vector2) -> Vector2:
	return c.get_global_transform() * local


func click(c: Control, local: Vector2) -> void:
	for pressed in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.position = vp(c, local)
		mb.pressed = pressed
		get_viewport().push_input(mb, true)
		await get_tree().process_frame
	await frames()


func wheel(c: Control, local: Vector2, down: bool) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP
	mb.position = vp(c, local)
	mb.pressed = true
	get_viewport().push_input(mb, true)
	await frames()


func wait_idle() -> void:
	var t0 := Time.get_ticks_msec()
	while title.transition.busy and Time.get_ticks_msec() - t0 < 4000:
		await get_tree().process_frame
	await frames(3)


func open_settings() -> void:
	title._activate(4)
	await wait_idle()


func title_part(tag: String) -> void:
	var st: Control = title.settings
	# ---- 设置：Esc 关
	await open_settings()
	check(st.visible, tag + ": settings opens")
	await key(KEY_ESCAPE)
	check(not st.visible, tag + ": Esc closes settings")
	await wait_idle()
	# ---- 设置：键盘调数值 / 换页 / 换行
	await open_settings()
	st._set_tab(0)   # Sound assertions are independent of the approved display-first landing page.
	Cfg.master = 0.5   # 测试用户目录里主音量是 0：降不下去，先放到中间
	var m0: float = Cfg.master
	await key(KEY_LEFT)
	check(Cfg.master < m0, tag + ": Left lowers master volume (%s → %s)" % [m0, Cfg.master])
	await key(KEY_RIGHT)
	check(is_equal_approx(Cfg.master, m0), tag + ": Right restores master volume")
	await key(KEY_DOWN)
	check(st.sel == 1, tag + ": Down moves to next row (sel=%d)" % st.sel)
	# 按住 Enter 不连发：音乐行切开关不适用（是音量），换到「游戏」页的开关行测
	await key(KEY_E)
	st.sel = 0
	var b0 = Cfg.auto_combo
	await key(KEY_ENTER, false, 3)
	check(Cfg.auto_combo != b0, tag + ": held Enter toggles exactly once")
	await key(KEY_ENTER)
	await key(KEY_Q)
	st.sel = 1
	await key(KEY_E)
	check(st.tab == 2, tag + ": E follows visible category order")
	await key(KEY_Q)
	check(st.tab == 0, tag + ": Q switches back")
	# 输入法：只带物理键码的 ← / Esc 也认
	await key(KEY_LEFT, true)
	check(Cfg.master < m0, tag + ": physical-only Left adjusts")
	await key(KEY_RIGHT, true)
	# 滚轮：滚列表，不改数值
	await key(KEY_Q)   # 画面页：按可见分类顺序回到画面
	await frames(2)
	var m1: float = Cfg.master
	var lr: Rect2 = st.view
	if st.scroll_max > 0.0:
		await wheel(st, lr.get_center(), true)
		await frames(20)
		check(st.scroll > 0.0, tag + ": wheel scrolls the list")
	check(is_equal_approx(Cfg.master, m1), tag + ": wheel does not change values")
	await key(KEY_ESCAPE, true)
	check(not st.visible, tag + ": physical-only Esc closes settings")
	await wait_idle()
	# ---- 右上角 ×
	await open_settings()
	check(st.close_rect.size.x >= 44.0 and st.close_rect.size.y >= 44.0, tag + ": close button hit area >= 44 (%s)" % st.close_rect.size)
	await click(st, st.close_rect.get_center())
	check(not st.visible, tag + ": close button closes settings")
	await wait_idle()
	# ---- 标题设置使用完整页面
	await open_settings()
	await frames(2)
	var pr: Rect2 = st.panel_rect
	var fw: float = pr.size.x / st.size.x
	check(pr.is_equal_approx(Cfg.touch_safe_rect(st.size)), tag + ": title settings fills safe page (%.2f)" % fw)
	check(pr.position.y >= 0.0 and pr.end.y <= st.size.y, tag + ": panel inside page")
	# 按住 Esc：关设置那一下之后的自动重复不再落到标题（焦点不跳走）
	var sel0: int = title.sel
	await key(KEY_ESCAPE, false, 3)
	check(not st.visible, tag + ": held Esc closes settings")
	check(title.sel == sel0, tag + ": held Esc echo does not reach the title menu (sel %d → %d)" % [sel0, title.sel])
	await wait_idle()
	# ---- 图鉴
	title._activate(1)
	await wait_idle()
	check(title.gallery.visible, tag + ": gallery opens")
	await key(KEY_ESCAPE)
	await wait_idle()
	await frames(10)
	check(not title.gallery.visible, tag + ": Esc closes gallery")
	# ---- 操作说明
	title._activate(3)
	await wait_idle()
	check(title.guide, tag + ": guide opens")
	await key(KEY_ESCAPE)
	await wait_idle()
	check(not title.guide, tag + ": Esc closes guide")
	# ---- 致谢
	await key(KEY_C)
	await wait_idle()
	check(title.credits, tag + ": credits open on C")
	await key(KEY_ESCAPE)
	await wait_idle()
	check(not title.credits, tag + ": Esc closes credits")


func game_part() -> void:
	var g: Node = load("res://game.tscn").instantiate()
	add_child(g)
	await frames(10)
	g.state = g.S.PLAY
	if g.intro_screen != null:
		g.intro_screen.close()
	g.state = g.S.PLAY
	await frames(5)
	await key(KEY_ESCAPE)
	check(g.state == g.S.PAUSE, "game: Esc pauses (state=%d)" % g.state)
	await key(KEY_O)
	await frames(3)
	check(g.settings.visible, "game: O opens settings from pause")
	await key(KEY_ESCAPE, false, 3)
	check(not g.settings.visible, "game: Esc closes settings")
	check(g.state == g.S.PAUSE, "game: still paused after closing settings (state=%d)" % g.state)
	await key(KEY_ESCAPE)
	check(g.state == g.S.PLAY, "game: Esc resumes (state=%d)" % g.state)
	await key(KEY_ESCAPE, true)
	check(g.state == g.S.PAUSE, "game: physical-only Esc pauses (state=%d)" % g.state)
	await paused_cloud_layout(g)
	g.queue_free()
	await frames(3)


## Narrow paused layout with all four categories and asymmetric phone safe insets.
func paused_cloud_layout(g: Node) -> void:
	var saved_support: bool = Cloud.supported
	var saved_touch: int = Cfg._touch
	var saved_pad: bool = Pad.touch
	var saved_ins: Array = Cfg._ins.duplicate()
	var saved_key: Vector3 = Cfg._ins_key
	Cloud.supported = true
	Cfg._touch = 1
	Pad.touch = true
	var st: Control = g.settings
	st.open()
	st.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	st.size = Vector2(1044, 540)
	var vis: Vector2 = get_viewport().get_visible_rect().size
	Cfg._ins_key = Vector3(vis.x, vis.y, Cfg.ui_k)
	Cfg._ins = [24.0, 60.0, 32.0, 20.0]
	st._set_tab(3)
	await frames(3)
	check(st.tab_rects.size() == 4, "paused cloud: all four categories")
	var footer_top: float = st.panel_rect.end.y - 56
	for i in st.tab_rects.size():
		var r: Rect2 = st.tab_rects[i]
		check(r.end.y <= footer_top, "paused cloud: category fits above footer")
		for j in range(i + 1, st.tab_rects.size()):
			check(not r.intersects(st.tab_rects[j]), "paused cloud: categories do not overlap")
	check(st.view.size.y >= st._rowh(), "paused cloud: at least one complete option visible")
	check(st.panel_rect.encloses(st.footer_rect), "paused cloud: footer hit area inside panel")
	if Cfg.dev_args().has("--settingscloudshot"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://../build/ui-shell-qa/settings_paused_cloud_phone.png")
	# No cloud request in this layout test: restore platform support before close.
	Cloud.supported = saved_support
	st._tap(st.footer_rect.get_center(), MOUSE_BUTTON_LEFT)
	check(not st.visible, "paused cloud: footer closes settings")
	check(g.state == g.S.PAUSE, "paused cloud: footer keeps battle paused")
	Cfg._touch = saved_touch
	Pad.touch = saved_pad
	Cfg._ins = saved_ins
	Cfg._ins_key = saved_key


func run() -> void:
	if Cfg.dev_args().has("--settingscloudshot"):
		await game_part()
		print("SETTINGS PAUSED CLOUD: %d failures" % failures)
		get_tree().quit.call_deferred(1 if failures else 0)
		return
	title = load("res://main.tscn").instantiate()
	add_child(title)
	await get_tree().process_frame
	title.intro = title.INTRO_LEN
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	title.position = Vector2.ZERO
	title.size = Vector2(1280, 720)
	await frames(3)
	await title_part("desktop")
	Cfg._touch = 1
	Pad.touch = true
	title.size = Vector2(1044, 481)
	await frames(2)
	await title_part("touch")
	Cfg._touch = -1
	Pad.touch = false
	title.queue_free()
	await frames(3)
	await game_part()
	print("ESC LAYERS: %d failures" % failures)
	get_tree().quit.call_deferred(1 if failures else 0)
