extends "res://scripts/screens/title_diff_pick.gd"
## 标题界面：「方舟幸存者」Logo + 地图副标题 + 菜单；背景按地图（现为蓝眼泪银河沙滩 title_bg.gd，博士与水月站在浪边）
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 触屏：标题页（含图鉴 / 设置 / Boss 演练子面板）整体放大 Cfg.ui_k（手机 1.3）；背景 / 转场在各自的 CanvasLayer 不受影响
	Cfg.ui_k = Cfg.ui_scale()
	if Cfg.ui_k != 1.0:
		scale = Vector2(Cfg.ui_k, Cfg.ui_k)
		Cfg.ui_fill(self)
	# 视口变了（竖屏进页面再转横屏、浏览器栏收起）或设置里改了「界面大小」：放大倍数重算，不然一直用旧倍数
	get_viewport().size_changed.connect(_ui_refit)
	Cfg.view_changed.connect(_ui_refit)
	font = load("res://fonts/ui.ttf")
	Cloud.flush("title")   # B站云存档：回到标题时上传待上传的进度（只在 B站环境生效，docs/89）
	# 菜单项门槛（同旧版）：对外包没有 Boss 演练（Cfg.can_boss_trial；调试版可用 --audience=public 模拟），网页没有退出（--simweb 模拟）
	menu_boss = Cfg.can_boss_trial()
	menu_exit = not (OS.has_feature("web") or Cfg.dev_args().has("--simweb"))
	tex_player = A.tex("player")
	if A.tex("player_idle") != null:
		tex_player = A.tex("player_idle")
		player_frames = max(1, tex_player.get_width() / tex_player.get_height())
	tex_light = A.tex("light")
	tex_tiles = A.tex("tiles")
	tex_bg = A.tex("title_bg")
	tex_logo = A.tex("logo")
	_prewarm()   # 标题页自己的几张图先取，预热名单里就不用再算
	var mf := FileAccess.open("res://data/maps/%s.json" % Cfg.map_id, FileAccess.READ)
	if mf != null:
		var md = JSON.parse_string(mf.get_as_text())
		if md is Dictionary:
			map_title = str(md.get("title", md.get("name", "")))
			map_title_en = str(md.get("title_en", ""))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260923
	_grow(rng, Vector2(900, 700), -PI / 2, 150.0, 14.0, 0)
	for i in 90:
		motes.append([Vector2(rng.randf_range(0, 1280), rng.randf_range(0, 720)), rng.randf_range(6, 22), rng.randf() * TAU])
	# 封面背景：蓝眼泪银河沙滩（放在更底层的 CanvasLayer，菜单画在它上面）
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -1
	add_child(bg_layer)
	title_bg = preload("res://scripts/title_bg.gd").new()
	bg_layer.add_child(title_bg)
	var cf := FileAccess.open("res://data/credits.json", FileAccess.READ)
	if cf != null:
		var cd = JSON.parse_string(cf.get_as_text())
		if cd is Dictionary:
			credits_data = cd
	_op_layers()   # 选人页的信息面板 / 正文 / 浪幕子层（画在标题页自己的 _draw 之上）
	cr_view = Control.new()
	cr_view.clip_contents = true
	cr_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cr_view.visible = false
	cr_view.draw.connect(_draw_credits_body)
	add_child(cr_view)
	post_fx = preload("res://scripts/post_fx.gd").new()
	add_child(post_fx)
	gallery = preload("res://scripts/gallery.gd").new()
	add_child(gallery)
	settings = preload("res://scripts/settings_panel.gd").new()
	add_child(settings)
	boss_trial = preload("res://scripts/screens/boss_trial_menu.gd").new()
	add_child(boss_trial)
	meta_ui = preload("res://scripts/screens/meta_tree_ui.gd").new()
	add_child(meta_ui)
	var transition_layer := CanvasLayer.new()
	transition_layer.layer = 90
	add_child(transition_layer)
	transition = preload("res://scripts/screens/scene_transition.gd").new()
	transition_layer.add_child(transition)
	for a in Cfg.dev_args():
		if a.begins_with("--compareshot="):
			_compare_shot(a.substr(14))
		if a.begins_with("--demoset="):
			# 截图自测：图鉴演示的阶段 / 动作（同 gallery.gd demo_stage / demo_mode）
			var dp := a.substr(10).split(",")
			gallery.demo_stage = int(dp[0])
			gallery.demo_mode = int(dp[1]) if dp.size() > 1 else -1
		if a.begins_with("--infotab="):
			gallery.info_tab = int(a.substr(10))   # 截图自测：干员详情的信息页（0 档案 / 1 属性 / 2 技能 / 3 成长）
		if a.begins_with("--galleryshot="):
			var parts := a.substr(14).split(",")
			gallery.open()
			gallery.tab = int(parts[0])
			gallery._build()
			if parts.size() > 1:
				gallery.sel = int(parts[1])
			for a2 in Cfg.dev_args():
				if a2.begins_with("--galleryid="):
					gallery.select_id(a2.substr(12))   # 按干员 / 条目 id 选（新干员加进来下标会变）
				if a2.begins_with("--galleryfilter="):
					gallery._set_filter(a2.substr(16))
				if a2.begins_with("--galleryrow="):
					gallery.row_sel = int(a2.substr(13))   # 手机：技能 / 成长页展开第几行
				if a2 == "--reducemotion":
					Cfg.reduce_motion = true
				if a2.begins_with("--codexglass="):
					gallery.glass.a = float(a2.substr(13))   # 截图对照：磨砂关掉时平涂底的透明度
				if a2 == "--noglassfx":
					gallery.glass_fx = false   # 截图对照：磨砂玻璃关掉（平涂 UI.C_L_GLASS）
			if parts.size() > 2:
				gallery.form = int(parts[2])
			gallery._follow()
			# 第 4 项：截图前等待秒数（攻击演示需要几秒才有画面）；第 5 / 6 项：连拍张数 / 间隔秒（特效逐帧检查用）
			var wait: float = float(parts[3]) if parts.size() > 3 else 1.2
			var burst: int = int(parts[4]) if parts.size() > 4 else 1
			var gap: float = float(parts[5]) if parts.size() > 5 else 0.05
			for bi in burst:
				get_tree().create_timer(wait + bi * gap).timeout.connect(func():
					get_viewport().get_texture().get_image().save_png(_shot_dir() + ("/shot_gallery_ui.png" if burst == 1 else "/shot_gallery_%02d.png" % bi))
					if bi == burst - 1:
						get_tree().quit())
	Sfx.cut_target = 20000.0
	Sfx.vol_target = -6.0
	Sfx.play_music("title")
	# 截图 / 自动测试 / 从对局返回标题：不播开场动画
	var args := Cfg.dev_args()
	if (not args.is_empty() and not args.has("--introshot") and not args.has("--introshort") and not args.has("--titlemotion")) or Cfg.title_seen:
		intro = INTRO_LEN
	elif Cfg.opening_seen or args.has("--introshort"):
		intro = INTRO_SHORT   # 看过完整版：只播 Logo 扫光和菜单滑入
	Cfg.title_seen = true
	if not Cfg.opening_seen and intro < INTRO_LEN:
		Cfg.opening_seen = true
		Cfg.save()
	if args.has("--introshot"):
		# 开场动画分镜截图：/tmp/claude-0/shot_intro_<n>.png
		for i in [0.4, 1.0, 1.6, 2.2, 2.45, 2.9, 3.3, 4.2]:
			get_tree().create_timer(i).timeout.connect(func():
				get_viewport().get_texture().get_image().save_png(_shot_dir() + "/shot_intro_%d.png" % int(i * 10)))
		get_tree().create_timer(5.0).timeout.connect(func(): get_tree().quit())
	if Cfg.dev_args().has("--metashot"):
		# 认知塑造页截图（docs/109 §4）：配 --metacells=<累计生机细胞>；--metabuy=<n> 先按推荐点法点 n 个
		meta_ui.open()
		for a in Cfg.dev_args():
			if a.begins_with("--metabuy="):
				var M = preload("res://scripts/core/meta.gd")
				Cfg.meta_shape = M.shape_for(int(a.substr(10)))
			if a.begins_with("--metasel="):
				var ps := a.substr(10).split(",")
				meta_ui.sel = Vector2i(int(ps[0]), int(ps[1]) if ps.size() > 1 else 0)
		get_tree().create_timer(1.0).timeout.connect(func():
			get_viewport().get_texture().get_image().save_png(_shot_dir() + "/shot_meta.png")
			get_tree().quit())
	if Cfg.dev_args().has("--settingsshot"):
		settings.open()
		for a in Cfg.dev_args():
			if a.begins_with("--settingstab="):
				settings._set_tab(int(a.substr(14)))   # 截图自测：设置面板的分类页
		for a in Cfg.dev_args():
			if a.begins_with("--settingssel="):
				settings.sel = int(a.substr(14))   # 截图自测：选中第几行（触屏会自动滚到可见）
				settings._follow()
			if a.begins_with("--settingsscroll="):
				settings.set_scroll(float(a.substr(17)))   # 截图自测：触屏列表滚动量（像素，超出自动截到底）
		var frames := 0   # --shotframe=N：等 N 帧再截（配 --fixed-fps 做逐像素对照）；缺省等 1 秒
		for a in Cfg.dev_args():
			if a.begins_with("--shotframe="):
				frames = int(a.substr(12))
		var snap := func():
			get_viewport().get_texture().get_image().save_png(_shot_dir() + "/shot_settings.png")
			get_tree().quit()
		if frames > 0:
			for k in frames:
				await get_tree().process_frame
			snap.call()
		else:
			get_tree().create_timer(1.0).timeout.connect(snap)
	if Cfg.dev_args().has("--creditsshot"):
		# 致谢与声明页截图（10-11 改滚动条验收）：可选 --creditsscroll=<像素>（超出自动截到底）
		_open_credits()
		for a in Cfg.dev_args():
			if a.begins_with("--creditsscroll="):
				cr_scroll = float(a.substr(16))
				cr_scroll_f = cr_scroll
		get_tree().create_timer(1.0).timeout.connect(func():
			get_viewport().get_texture().get_image().save_png(_shot_dir() + "/shot_credits.png")
			get_tree().quit())
	if Cfg.dev_args().has("--guideshot"):
		# 操作说明页截图（手机设置页改版 10-06 验收用）
		guide = true
		get_tree().create_timer(1.0).timeout.connect(func():
			get_viewport().get_texture().get_image().save_png(_shot_dir() + "/shot_guide.png")
			get_tree().quit())
	if Cfg.dev_args().has("--glassperf"):
		# 图鉴磨砂玻璃开销（同局轮换）：开图鉴（维什戴尔），关垂直同步、不限帧，每 90 帧切换一次磨砂开 / 关，各丢掉切换后 10 帧，共 1800 帧后打印 GLASSPERF
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
		_codex_motion_open()
		glass_perf = 0
	if Cfg.dev_args().has("--codexmotion"):
		# 图鉴 C4' 动效录制（docs/58 §11.2 验收）：配 --fixed-fps 30 每帧存图到 <shotdir>/codexmotion/；
		# 脚本：标题 → 斜切转场打开图鉴（维什戴尔）→ 换干员 ×2 → 换页签 ×2 → 敌人页（标本柜启辉）→ 换条目 → 回干员页 → 退出
		DirAccess.make_dir_recursive_absolute(_shot_dir() + "/codexmotion")
		codex_motion = 0
	if Cfg.dev_args().has("--titlemotion"):
		# 标题 T5s 动效录制（docs/67 §12 验收）：配 --fixed-fps 30 每帧存图到 <shotdir>/titlemotion/；
		# 脚本：完整开场 → 磁贴浮出 → 二维导航换选中（涨潮 / 涟漪）→ 集结出发 → 选人 → 出击浪幕 → 难度页涨潮 → 换档
		for a in Cfg.dev_args():
			if a == "--reducemotion":
				Cfg.reduce_motion = true
		Cfg.diff_unlocked = D.DIFF_PRESETS.size() - 1   # 只改内存（测试模式不写存档），录到能出发的档
		DirAccess.make_dir_recursive_absolute(_shot_dir() + "/titlemotion")
		title_motion = 0
	if Cfg.dev_args().has("--opmotion"):
		# 选人页动效录制（docs/58 §11 验收）：配 --fixed-fps 30 每帧存图到 <shotdir>/opmotion/；脚本：换人 ×2 → 换页签 → 换技能行 → 职业筛选 → 出击浪幕 → 难度页
		_open_op_pick()
		for a in Cfg.dev_args():
			if a == "--reducemotion":
				Cfg.reduce_motion = true
			if a.begins_with("--opartk="):
				op_art_k = float(a.substr(9))
		DirAccess.make_dir_recursive_absolute(_shot_dir() + "/opmotion")
		op_motion = t
	if Cfg.dev_args().has("--opshot"):
		# 选人页截图（可选 --opsel=<n>）
		_open_op_pick()
		for a in Cfg.dev_args():
			if a.begins_with("--opsel="):
				op_sel = clampi(int(a.substr(8)), 0, op_defs.size() - 1)
				op_skill = _op_default_skill()
				_op_follow(true)
			if a.begins_with("--opid="):
				# 按干员 id 选（新干员加进来下标会变）
				for i in op_defs.size():
					if op_defs[i].id == a.substr(7):
						op_sel = i
				op_skill = _op_default_skill()
				_op_follow(true)
			if a.begins_with("--optab="):
				op_tab = clampi(int(a.substr(8)), 0, 2)
			if a.begins_with("--opartk="):
				op_art_k = float(a.substr(9))
			if a.begins_with("--opskill="):
				op_skill = clampi(int(a.substr(10)), 0, 2)
			if a.begins_with("--opfilter="):
				_op_set_filter(a.substr(11))
			if a.begins_with("--opscroll="):
				op_scroll = clampf(float(a.substr(11)), 0.0, _op_scroll_max())
				op_scroll_f = op_scroll
			if a == "--reducemotion":
				Cfg.reduce_motion = true
		if Cfg.dev_args().has("--opburst"):
			# 平滑滚动自测：开页后 0.05–0.4 秒连拍 8 张（选中项在可视区外时能看到滚动过程）
			for bi in 8:
				get_tree().create_timer(0.05 + bi * 0.05).timeout.connect(func():
					get_viewport().get_texture().get_image().save_png(_shot_dir() + "/shot_oppick_%d.png" % bi))
		get_tree().create_timer(1.2).timeout.connect(func():
			get_viewport().get_texture().get_image().save_png(_shot_dir() + "/shot_oppick.png")
			get_tree().quit())
	for a in Cfg.dev_args():
		if a.begins_with("--diffshot="):
			# 选难度页截图：--diffshot=<选中档>,<已解锁到第几档>（只改内存，测试模式不写存档）
			var dp := a.substr(11).split(",")
			Cfg.diff_unlocked = clampi(int(dp[1]) if dp.size() > 1 else 0, 0, D.DIFF_PRESETS.size() - 1)
			diff_pick = true
			diff_sel = clampi(int(dp[0]), 0, D.DIFF_PRESETS.size() - 1)
			get_tree().create_timer(1.2).timeout.connect(func():
				get_viewport().get_texture().get_image().save_png(_shot_dir() + "/shot_diff_%d_%d.png" % [diff_sel, Cfg.diff_unlocked])
				get_tree().quit())
	if Cfg.dev_args().has("--loadingshot"):
		# 出发后「载入中…」面板的截图（预热通常不到 1 秒就完成，截图时强制画出来）
		leaving = 0.0
		get_tree().create_timer(1.3).timeout.connect(func():
			get_viewport().get_texture().get_image().save_png(_shot_dir() + "/shot_loading.png")
			get_tree().quit())
	if Cfg.dev_args().has("--titleshot"):
		# 可选 --titlesel=<菜单项 0–5>（截选中别的磁贴）
		for a in Cfg.dev_args():
			if a.begins_with("--titlesel="):
				sel = clampi(int(a.substr(11)), 0, 5)
				if not _menu_ids().has(sel):
					sel = 0
			if a == "--reducemotion":
				Cfg.reduce_motion = true
		get_tree().create_timer(2.0).timeout.connect(func():
			get_viewport().get_texture().get_image().save_png(_shot_dir() + "/shot_title.png")
			get_tree().quit())
	if Cfg.dev_args().has("--autotest") or Cfg.dev_args().has("--balance"):
		if A.prewarm_busy():
			auto_go = true   # 开窗口的自测：等法线图预热完（同玩家路径），黑屏时长才有可比性
		else:
			A.mark("title_leave")
			get_tree().change_scene_to_file.call_deferred("res://game.tscn")


## 法线图预热（art.gd）：标题页一打开就在后台线程把本局要用的法线图算好 / 读缓存；出发时再调一次（设置里刚打开法线光照的情况）
func _ui_refit() -> void:
	var k: float = Cfg.ui_scale()
	if k == 1.0 and scale == Vector2.ONE:
		Cfg.ui_k = 1.0
		return   # 桌面缺省：FULL_RECT 锚点照旧
	Cfg.ui_k = k
	scale = Vector2(k, k)
	Cfg.ui_fill(self)


func _exit_tree() -> void:
	A.prewarm_join()


## 递归生成巨树（像海嗣一样弯曲的枝干）
func _grow(rng: RandomNumberGenerator, p: Vector2, ang: float, length: float, width: float, depth: int) -> void:
	if depth > 6 or length < 10.0:
		nodes.append([p, rng.randf() * TAU])
		return
	var pts := [p]
	var a := ang
	var q := p
	for s in 6:
		a += rng.randf_range(-0.22, 0.22)
		q += Vector2.from_angle(a) * length / 6.0
		pts.append(q)
	for i in pts.size() - 1:
		branches.append([pts[i], pts[i + 1], width * (1.0 - i * 0.08), depth])
	var n := 2 if depth < 2 else rng.randi_range(1, 3)
	for k in n:
		_grow(rng, q, a + rng.randf_range(-0.9, 0.9), length * rng.randf_range(0.6, 0.8), width * 0.62, depth + 1)
	if depth >= 3 and rng.randf() < 0.5:
		nodes.append([q, rng.randf() * TAU])


func _process(delta: float) -> void:
	Pad.context = "title"
	var overlay_open: bool = _overlay_open()
	if post_fx != null:
		post_fx.crisp = gallery.visible   # 图鉴 C4' 是浅色终端：不叠辉光 / 水下色差
	if overlay_was_open and not overlay_open and not transition.busy:
		transition.reveal_page()
	overlay_was_open = overlay_open
	if leaving < 0.0 and not auto_go:
		Sfx.play_music(menu_track())   # 出发后（载入中）不换曲，开场引子由对局接手
	t += delta
	_menu_tick(delta)
	if not diff_pick:
		diff_was = false
	if op_panel != null:
		_op_tick(delta)
	if op_motion >= 0.0:
		_op_motion_tick()
	_credits_tick(delta)
	if codex_motion >= 0:
		_codex_motion_tick()
	if title_motion >= 0:
		_title_motion_tick()
	if glass_perf >= 0:
		var on := (glass_perf / 90) % 2 == 0
		gallery.glass_fx = on
		if glass_perf % 90 >= 10 and glass_perf > 60:
			glass_acc[0 if on else 1] += delta
			glass_acc[2 if on else 3] += 1
			glass_acc[4 if on else 5] += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
		glass_perf += 1
		if glass_perf >= 1860:
			print("GLASSPERF on=%.3f ms off=%.3f ms diff=%.3f ms (frames %d / %d) gpu on=%.3f off=%.3f ms" % [glass_acc[0] / glass_acc[2] * 1000.0, glass_acc[1] / glass_acc[3] * 1000.0, (glass_acc[0] / glass_acc[2] - glass_acc[1] / glass_acc[3]) * 1000.0, glass_acc[2], glass_acc[3], glass_acc[4] / glass_acc[2], glass_acc[5] / glass_acc[3]])
			get_tree().quit()
	if intro < INTRO_LEN:
		intro = minf(intro + delta, INTRO_LEN)
	# 背景：开场镜头下摇（整像素平移，不缩放）、脚印依次亮起、海嗣睁眼一瞬
	if title_bg != null:
		title_bg.pan = 40.0 * (1.0 - _ease((intro - 0.4) / 1.8))
		title_bg.reveal = clampf((intro - 1.6) / 0.9, 0.0, 1.0)
		title_bg.eye_flash = maxf(0.0, 1.0 - absf(intro - 2.45) / 0.3) if intro < INTRO_LEN else 0.0
	for m in motes:
		m[0].y -= m[1] * delta
		if m[0].y < -10:
			m[0].y = size.y + 10
	A.prewarm_tick()
	if leaving >= 0.0:
		leaving += delta
		if leaving > 0.7:
			# 法线图预热没完就画「载入中…」等它（以前这里直接切场景，game.gd _ready 同步算 10 秒法线图 = 黑屏），最多等 30 秒
			if (A.prewarm_busy() or Cfg.dev_args().has("--loadingshot")) and wait_t < 30.0:
				wait_t += delta
			else:
				A.mark("title_leave")
				get_tree().change_scene_to_file("res://game.tscn")
	elif auto_go and not A.prewarm_busy():
		auto_go = false
		A.mark("title_leave")
		get_tree().change_scene_to_file("res://game.tscn")
	queue_redraw()


## 当前界面该放哪首局外配乐（docs/21「局外配乐」）：图鉴 archive；选人（出发前，不含换封面）/ 难度 / Boss 演练 deploy；
## 其余（标题、设置、操作说明、致谢、换封面干员）title。每帧请求，同名无副作用
func menu_track() -> String:
	if gallery.visible:
		return "archive"
	if boss_trial.visible or diff_pick or (op_pick and not cover_pick):
		return "deploy"
	return "title"


func _input(event: InputEvent) -> void:
	if leaving >= 0.0 or transition.busy or _overlay_open():
		return
	if intro < INTRO_LEN:
		# 开场动画中：按键 / 点击直接跳到完成态，本次输入不再传给菜单
		if (event is InputEventKey and event.pressed and not event.echo) \
				or (event is InputEventMouseButton and event.pressed):
			intro = INTRO_LEN
		return
	if credits:
		_credits_input(event)
		return
	if diff_pick:
		_diff_input(event)
		return
	if op_pick:
		_op_input(event)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if guide:
			_close_info()
			Sfx.play("ui_ok")
			return
		match Pad.kc(event):
			KEY_UP, KEY_W:
				_menu_nav(Vector2i(0, -1))
			KEY_DOWN, KEY_S:
				_menu_nav(Vector2i(0, 1))
			KEY_LEFT, KEY_A:
				_menu_nav(Vector2i(-1, 0))
			KEY_RIGHT, KEY_D:
				_menu_nav(Vector2i(1, 0))
			KEY_TAB:
				# Tab / Shift+Tab：按可见顺序线性走（兜底，不用想格子也能到所有项）
				_menu_set(Tiles.linear(_menu_ids(), sel, -1 if event.shift_pressed else 1), true)
			KEY_ESCAPE:
				# 首页 Esc / 手柄 Ⓑ：焦点跳到「退出」，不直接退（网页 / 手机没有退出时不动）
				if _menu_ids().has(5):
					_menu_set(5, true)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_activate(sel)
			KEY_C, KEY_X:
				# 致谢与声明：键盘 C、手柄 Ⓨ（标题页 Ⓨ 映射为 X）也能打开（原来只能鼠标点页脚）
				transition.switch_page(_open_credits)
				Sfx.play("ui_ok")
			KEY_V:
				transition.switch_page(_open_op_pick.bind(true))
	elif event is InputEventMouseMotion:
		for i in item_rects.size():
			if item_rects[i].has_point(make_input_local(event).position) and sel != i:
				_menu_set(i, true)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if guide:
			_close_info()
			return
		if credits_rect.has_point(make_input_local(event).position):
			transition.switch_page(_open_credits)
			Sfx.play("ui_ok")
			return
		if deploy_rect.has_point(make_input_local(event).position):
			Sfx.play("ui_ok")
			transition.switch_page(_open_op_pick.bind(true))
			return
		for i in item_rects.size():
			if item_rects[i].has_point(make_input_local(event).position):
				_activate(i)


func _close_info() -> void:
	transition.switch_page(func():
		guide = false
		credits = false)


## 盖在标题上的界面（各自处理 Esc、关掉时 visible = false）：开着时标题不收输入，关掉那一帧 reveal_page。新的局外界面登记在这里
func _overlays() -> Array:
	return [settings, gallery, boss_trial, meta_ui]


func _overlay_open() -> bool:
	for o in _overlays():
		if o != null and o.visible:
			return true
	return false


func _menu_ids() -> Array:
	var ids: Array = Tiles.order()
	if not menu_boss:
		ids.erase(2)
	# 网页版没有「退出」：quit() 只会把引擎停在最后一帧，玩家只能刷新页面（架构 10-01 实测）
	if not menu_exit:
		ids.erase(5)
	return ids


## 磁贴群二维导航（title_tiles.nav）：↑↓ 换行落到最近的列（记住列），← → 行内，不循环
func _menu_nav(d: Vector2i) -> void:
	if menu_lay.is_empty():
		menu_lay = Tiles.layout(_menu_ids(), 90.0, 304.0, 400.0, 354.0, false)
	if menu_mem_x < 0.0 and menu_lay.rects.has(sel):
		menu_mem_x = (menu_lay.rects[sel] as Rect2).get_center().x
	var r: Array = Tiles.nav(menu_lay, sel, d, menu_mem_x)
	menu_mem_x = r[1]
	_menu_set(r[0], false)


## 换选中：涨潮 + 涟漪从此刻开始；remember = 同时把记住的列改成新磁贴（悬停 / 点击 / Tab / 横移）
func _menu_set(i: int, remember: bool) -> void:
	if not _menu_ids().has(i):
		return
	if remember and menu_lay.has("rects") and menu_lay.rects.has(i):
		menu_mem_x = (menu_lay.rects[i] as Rect2).get_center().x
	if i == sel:
		return
	sel = i
	menu_rip_t = t
	Sfx.play("ui_move")


func _activate(i: int) -> void:
	if transition.busy:
		return
	Sfx.play("ui_ok")
	match i:
		0:
			transition.switch_page(_open_op_pick.bind(false))
		1:
			transition.switch_slash(gallery.open)   # 图鉴 C4'：斜切黑带（黄前缘）转场，docs/58 §11.2
		2:
			if Cfg.can_boss_trial():
				transition.switch_page(boss_trial.open)
		3:
			transition.switch_page(func(): guide = true)
		4:
			transition.switch_page(settings.open)
		5:
			get_tree().quit()
		6:
			transition.switch_page(meta_ui.open)


## 磁贴入场（docs/62「每屏一个主动作」：标题菜单 = 磁贴从潮线下浮出）：开场 3.3 秒起按行错开 0.09 秒，每行 0.38 秒（T3）露出；
## 减少动态效果：不浮出，整块 T1 淡入（_tile_text_a 管文字）
const TILE_T0 := 3.3
func _tile_row(i: int) -> int:
	if menu_lay.has("rows"):
		for r in menu_lay.rows.size():
			if menu_lay.rows[r].has(i):
				return r
	return 0


func _tile_rise(i: int) -> float:
	var t0 := TILE_T0 + _tile_row(i) * 0.09
	if Cfg.reduce_motion:
		return 1.0 if intro >= t0 else 0.0
	return _ease((intro - t0) / 0.38)


func _tile_text_a(i: int) -> float:
	var t0 := TILE_T0 + _tile_row(i) * 0.09 + (0.0 if Cfg.reduce_motion else 0.38)
	return clampf((intro - t0) / 0.12, 0.0, 1.0)


## 水位：选中块涨潮、其余退潮（T2 0.22 秒）；磁贴还没浮出水面时不涨；减少动态效果直接到位
func _menu_tick(delta: float) -> void:
	for i in ITEMS.size():
		var target := 1.0 if i == sel and _tile_rise(i) >= 1.0 else 0.0
		if Cfg.reduce_motion:
			menu_water[i] = target
		else:
			menu_water[i] = move_toward(menu_water[i], target, delta / 0.22)


## 开场动画进度：seg 段在 [t0, t0+dur] 内从 0 缓动到 1
func _seg(t0: float, dur: float) -> float:
	return _ease((intro - t0) / dur)


func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)


func _draw() -> void:
	var vs := size
	var tx := 90.0
	if diff_pick and not op_pick and not guide and not credits:
		# 难度页（T5s）：整屏是它自己的版式，标题的 Logo / 磁贴 / 页脚都不画
		_draw_diff(vs)
		_draw_leaving(vs)
		return
	# 左侧柔和暗角：让标题与菜单浮在星空上，不与银河抢
	var vg := _ease(intro / 1.6)
	for i in 14:
		var a := 0.42 * pow(1.0 - i / 14.0, 1.6) * vg
		draw_rect(Rect2(i * 46.0, 0, 46.0, vs.y), Color(0.0, 0.01, 0.03, a))
	# 顶部小标（方案 A）：本作徽记 + 英文
	var hf0 := _seg(2.9, 0.4) * (0.0 if Pad.touch_ui() and (size.y < 520.0 or Cfg.phone_ui()) else 1.0)   # 手机：Logo 上移后会压住这行小标，不画
	_draw_emblem(Vector2(tx + 8, 44), 8.0, _fa(Color(0.76, 0.79, 0.81), hf0))
	UI.en(self, font, Vector2(tx + 24, 49), "ARKNIGHTS FAN GAME  ·  ROGUELIKE SURVIVORS", 11, _fa(Color(0.55, 0.59, 0.63), hf0), 2.5)
	if Cfg.unlock_all:
		# 暗底衬板：右上角是明亮的巨树枝，金字直接压在上面看不清
		var tbw: float = font.get_string_size("测试版 · 已全部解锁（不写入存档）", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_rect(Rect2(vs.x - 30 - tbw - 12, 13, tbw + 24, 24), Color(0.02, 0.03, 0.05, 0.85))
		draw_rect(Rect2(vs.x - 30 - tbw - 12, 13, 3, 24), UI.GOLD)
		UI.text(self, font, Vector2(vs.x - 330, 30), "测试版 · 已全部解锁（不写入存档）", 12, UI.GOLD, HORIZONTAL_ALIGNMENT_RIGHT, 300)
	# 标题（像素 Logo）：2.6s 起青色扫光从左往右「刷」出来（Logo 按扫光位置裁切），扫完右上菱形闪一下
	var lg := _seg(2.6, 0.6)
	var ly := 6.0 * (1.0 - lg)
	# 手机（界面层放大后逻辑高约 481，手机端 UI 优化 r2）：Logo 缩到 420×104，副标题 / 分隔线上移 28，菜单行距 40
	var ph: bool = Pad.touch_ui() and (size.y < 520.0 or Cfg.phone_ui())
	if ph:
		ly -= 50.0
	if tex_logo != null:
		var ls := Vector2(tex_logo.get_width(), tex_logo.get_height())
		var k: float = min((360.0 if ph else 520.0) / ls.x, (90.0 if ph else 130.0) / ls.y)
		if lg > 0.0:
			draw_texture_rect_region(tex_logo, Rect2(Vector2(tx, 84 + ly), Vector2(ls.x * k * lg, ls.y * k)), Rect2(0, 0, ls.x * lg, ls.y))
		if lg > 0.0 and lg < 1.0:
			var sx := tx + ls.x * k * lg
			draw_rect(Rect2(sx - 10, 80, 10, ls.y * k + 8), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.25))
			draw_rect(Rect2(sx - 2, 78, 3, ls.y * k + 12), Color(0.85, 1.0, 1.0, 0.9))
		var sp: float = maxf(0.0, 1.0 - absf(intro - 3.25) / 0.2)
		if sp > 0.0 and intro < INTRO_LEN:
			var dp := Vector2(tx + 262 * k * ls.x / 520.0, 84 + 14)
			draw_line(dp + Vector2(-9, 0) * sp, dp + Vector2(9, 0) * sp, Color(1, 1, 1, sp), 2.0)
			draw_line(dp + Vector2(0, -9) * sp, dp + Vector2(0, 9) * sp, Color(1, 1, 1, sp), 2.0)
	else:
		UI.text(self, font, Vector2(tx, 182 + ly), "方舟", 96, _fa(UI.TEXT, lg))
		UI.text(self, font, Vector2(tx + 210, 180 + ly), "幸存者", 40, _fa(UI.CYAN, lg))
	UI.en(self, font, Vector2(tx + 6, 242 + ly), "ARKNIGHTS  SURVIVORS", 15, _fa(Color(0.76, 0.79, 0.81), _seg(3.0, 0.4)), 5.0)
	# 地图副标题：随地图变化，英文副标题下一行（菱形 + 中文名 + 英文名），和 Logo 组成一块
	if map_title != "":
		var mf2 := _seg(3.1, 0.4)
		UI.diamond(self, Vector2(tx + 11, 257 + ly), 4.0, _fa(UI.CYAN, mf2))
		UI.text(self, font, Vector2(tx + 22, 263 + ly), map_title, 15, _fa(UI.TEXT, mf2))
		if map_title_en != "":
			var mw: float = font.get_string_size(map_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			UI.en(self, font, Vector2(tx + 34 + mw, 262 + ly), map_title_en, 10, _fa(Color(0.5, 0.54, 0.58), mf2), 2.5)
	# 分隔线：1.6s 起从左向右划出，右端一个小方块
	var rl := _seg(3.1, 0.5)
	var ry := 282.0 + (ly if ph else 0.0)
	if rl > 0.0:
		UI.hairline(self, Vector2(tx, ry), Vector2(tx + 420 * rl, ry), Color(1, 1, 1), 0.32, 0.14)
		draw_rect(Rect2(Vector2(tx + 420 * rl - 2, ry - 2), Vector2(5, 5)), Color(1, 1, 1, 0.55 * rl))

	# 菜单：T5s 磁贴群（docs/67 §12）——Logo 下方、原纵向菜单的位置；keyart 与人物不动
	item_rects.clear()
	item_rects.resize(ITEMS.size())
	item_rects.fill(Rect2())
	var menu_ids := _menu_ids()
	var touch := Pad.touch_ui()
	var my := ry + 22.0
	var foot_h := 12.0 if ph else 40.0
	var hint_h := 0.0 if touch else 24.0
	menu_lay = Tiles.layout(menu_ids, tx, my, 400.0, vs.y - my - foot_h - hint_h, touch or Cfg.touch_device())
	for i in menu_ids:
		item_rects[i] = menu_lay.rects[i]
	if menu_mem_x < 0.0 and menu_lay.rects.has(sel):
		menu_mem_x = (menu_lay.rects[sel] as Rect2).get_center().x
	var rise := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var text_a := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	for i in menu_ids:
		rise[i] = _tile_rise(i)
		text_a[i] = _tile_text_a(i)
	if not diff_pick and not op_pick:
		Tiles.draw(self, menu_lay, {"sel": sel, "water": menu_water, "rip_t": menu_rip_t, "now": t, "rise": rise, "text_a": text_a,
			"phase": 0.0 if Cfg.reduce_motion else t * 0.9, "font": font, "rm": Cfg.reduce_motion})
	var tc := TUI.ctx(self)
	# 操作提示：一行暗色像素字（键鼠 / 手柄；触屏不画）
	var hf := _seg(4.0, 0.4)
	if hf > 0.0 and not diff_pick and not op_pick and not touch:
		var hs: String = Pad.hint("WASD / ↑↓←→ SELECT   ENTER CONFIRM   TAB NEXT", "D-PAD SELECT   PAD A CONFIRM   PAD B EXIT", "")
		TUI.ptext(self, tc, Vector2(tx + 2, menu_lay.bottom + 16), hs, 1.0, Color(0.35, 0.41, 0.47, hf))
	# 右下「更换封面干员」（小号）：像素菱形 + 中文 + 像素键名 V；悬停下划线变长变青
	var df := _seg(3.9, 0.4)
	deploy_rect = Rect2()
	if df > 0.0 and not diff_pick and not op_pick:
		var cs := 16 if ph else 15
		var x1 := vs.x - (24.0 if ph else 44.0)
		var cy := vs.y - (44.0 if ph else 54.0)
		var kw := 0.0 if touch else TUI.ptext_w(tc, "V", 1.0) + 10.0
		var tw: float = font.get_string_size("更换封面干员", HORIZONTAL_ALIGNMENT_LEFT, -1, cs).x
		var ix := x1 - kw - tw - 18.0
		deploy_rect = Rect2(ix - 14.0, cy - 22.0, x1 - ix + 20.0, 44.0)
		cover_hover = deploy_rect.has_point(get_local_mouse_position()) and intro >= INTRO_LEN and not touch
		var cc := Color(TUI.CY.r, TUI.CY.g, TUI.CY.b, df) if cover_hover else Color(TUI.TXT.r, TUI.TXT.g, TUI.TXT.b, df)
		TUI.pdiamond(self, tc, Vector2(ix, cy), 3, TUI.cell(tc, 2.0 if not ph else 1.5), cc)
		UI.text(self, font, Vector2(ix + 14.0, cy + cs * 0.36), "更换封面干员", cs, cc)
		if not touch:
			TUI.ptext(self, tc, Vector2(x1, cy), "V", 1.0, Color(TUI.CY.r, TUI.CY.g, TUI.CY.b, df), 1, 2)
		var uy := cy + 15.0
		draw_rect(Rect2(ix - 8.0, uy, x1 - ix + 8.0, 1.0), Color(1, 1, 1, 0.22 * df))
		draw_rect(Rect2(ix - 8.0, uy - 1.0, 22.0 + (40.0 if cover_hover else 0.0), 2.0), Color(TUI.CY.r, TUI.CY.g, TUI.CY.b, df))

	# 页脚：一行（同人声明 · 与鹰角网络无关 · 致谢与声明 · 版本），最后淡入；手机挪到右下（左下是磁贴群）
	var ff := _seg(4.1, 0.4)
	var ftxt: String = ("明日方舟同人作品 · 非商业 · 与鹰角网络无关 · 致谢与声明 %s" % Pad.hint("C", "Ⓨ", "")).strip_edges() if not ph else "同人作品 · 非商业 · 与鹰角网络无关 · 致谢与声明"
	var fs := 12
	var fw: float = font.get_string_size(ftxt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var vk := 1.4 if ph else 1.0
	var vw := TUI.ptext_w(tc, "V2.0", vk)
	var fx: float = (vs.x - 24.0 - fw - 12.0 - vw) if ph else tx
	var fy := vs.y - (12.0 if ph else 20.0)
	credits_rect = Rect2(fx - 6, fy - 18, fw + 12, 26)
	var cr_hover := credits_rect.has_point(get_local_mouse_position()) and intro >= INTRO_LEN
	UI.text(self, font, Vector2(fx, fy), ftxt, fs, _fa(TUI.CY if cr_hover else Color(0.5, 0.54, 0.58), ff))
	TUI.ptext(self, tc, Vector2(fx + fw + 12.0, fy - 4.0), "V2.0", vk, _fa(Color(0.5, 0.54, 0.58), ff))
	# 对内包页脚提示（docs/40，用户 10-10）：右下；手机页脚已占满，手机只在设置页提示
	if not ph and not OS.is_debug_build() and Cfg.runs_log_enabled():
		UI.text(self, font, Vector2(vs.x - 440, vs.y - 20), "测试版：本地记录对局摘要（不上传）", 12, _fa(UI.GOLD, ff), HORIZONTAL_ALIGNMENT_RIGHT, 310)

	# 开场：黑幕淡出 + 上下黑边收起
	if intro < INTRO_LEN:
		var dark := 1.0 - _ease((intro - 0.5) / 0.9)
		if dark > 0.0:
			draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.005, 0.015, dark))
		var bar := 90.0 * (1.0 - _seg(0.5, 1.2))
		if bar > 0.5:
			draw_rect(Rect2(0, 0, vs.x, bar), Color(0, 0.005, 0.015))
			draw_rect(Rect2(0, vs.y - bar, vs.x, bar), Color(0, 0.005, 0.015))
		# 黑场里的一粒蓝眼泪：沙滩上亮起，荡开三圈涟漪（黑幕退去时一起淡掉）
		if intro < 1.6 and title_bg != null:
			var tp: Vector2 = Vector2(vs.x * 0.58, vs.y * 0.66).round()   # 固定在画面中下（不跟下摇的背景走，免得被下方黑边盖住）
			var ta: float = clampf(intro / 0.25, 0.0, 1.0) * clampf((1.6 - intro) / 0.5, 0.0, 1.0)
			draw_circle(tp, 3.0, Color(0.7, 1.0, 1.0, ta))
			draw_circle(tp, 8.0, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.25 * ta))
			for q in 3:
				var rk: float = clampf((intro - 0.15 - q * 0.22) / 0.9, 0.0, 1.0)
				if rk > 0.0:
					draw_set_transform(tp, 0.0, Vector2(1.0, 0.4))
					draw_arc(Vector2.ZERO, 12.0 + 90.0 * rk, 0.0, TAU, 40, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, (1.0 - rk) * 0.7 * ta), 1.5)
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if guide:
		_draw_guide(vs)
	if credits:
		_draw_credits(vs)
	if op_pick:
		_draw_op_pick(vs)
	_draw_leaving(vs)


func _draw_leaving(vs: Vector2) -> void:
	if leaving >= 0.0:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.01, 0.02, clamp(leaving / 0.6, 0.0, 1.0)))
		if wait_t > 0.0:
			_draw_loading(vs)


## 出发后等法线图预热：潮汐航线风格的小面板 + 进度条（docs/37）
func _draw_loading(vs: Vector2) -> void:
	var pr := A.prewarm_progress()
	var r := Rect2(vs.x / 2 - 170, vs.y / 2 - 44, 340, 88)
	UI.frame(self, r, UI.CYAN)
	UI.en(self, font, Vector2(r.position.x + 18, r.position.y + 24), "LOADING", 11, Color(0.55, 0.59, 0.63), 2.5)
	UI.text(self, font, Vector2(r.position.x + 18, r.position.y + 46), "载入中…  准备光照贴图 %d / %d" % [pr.x, pr.y], 15, UI.TEXT)
	UI.gbar(self, Rect2(r.position.x + 18, r.position.y + 62, r.size.x - 36, 6), float(pr.x) / maxf(1.0, float(pr.y)), UI.CYAN)


## 本作徽记（菱形 + 一道浪）：标题页小标与主按钮用（不用原作的集成战略标志）
func _draw_emblem(c: Vector2, r: float, col: Color) -> void:
	draw_polyline(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0), c + Vector2(0, -r)]), col, 1.4)
	var w := PackedVector2Array()
	for k in 13:
		var u := k / 12.0
		w.append(c + Vector2(-r * 0.55 + u * r * 1.1, sin(u * TAU) * r * 0.16 + r * 0.06))
	draw_polyline(w, col, 1.4)


## 操作说明页的触屏版（触屏验收 10-01）
const TOUCH_GUIDE := [
	["移动", "按住屏幕左半边任意处拖动：手指落下的地方就是摇杆中心"],
	["冲刺", "右下「冲刺」键（冲刺中无敌，冷却 1.2 秒）"],
	["技能", "干员的技能自动释放；队长有手动技能时，冲刺键左上方出现技能键：点一下自动瞄准，按住拖动选方向 / 落点"],
	["手动普攻", "设置 · 游戏里可改为手动：冲刺键左侧出现攻击键，按住攻击，拖动选方向"],
	["选卡", "点击卡片"],
	["暂停 / 属性", "右侧「暂停」「属性」键；属性面板点任意处关闭"],
	["", "编队、灯火、藏品、商人、结局等说明在开局指南里，暂停菜单的「指南」可以随时重看"],
]


func _draw_guide(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.02, 0.04, 0.75))
	# 面板 880 宽：说明列 654px，最长一行（手柄）也放得下；再长就按宽度缩字号（text_fit），不会伸出面板
	var r := Rect2(vs.x / 2 - 440, vs.y / 2 - 230, 880, 460)
	UI.panel(self, r, UI.BG2, UI.CYAN_DIM, 16.0, UI.CYAN)
	UI.text(self, font, r.position + Vector2(36, 56), "操作说明", 28, UI.TEXT)
	UI.en(self, font, r.position + Vector2(36 + font.get_string_size("操作说明", HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x + 18, 54), "GUIDE", 13, UI.CYAN, 3.0)
	var lines: Array = TOUCH_GUIDE if Pad.touch_ui() else [
		["移动", "WASD / 方向键"],
		["冲刺", "空格（冲刺中无敌，冷却 1.2 秒）"],
		["技能", "干员的技能自动释放；队长的手动技能按 Q / E（乌尔比安三技能：鼠标指落点，或按住蓄距离）"],
		["手动普攻", "设置 · 游戏里可改为手动：左键 / J 攻击，朝光标方向"],
		["选卡", "数字键或鼠标点击"],
		["暂停 / 属性", "Esc 暂停　Tab / C 属性　M 开关音乐　R 重来　T 回标题"],
		["手柄", "左摇杆移动　Ⓑ / RB 冲刺　Ⓐ / Ⓨ 手动技能　Ⓧ / RT 手动攻击　右摇杆瞄准"],
		["", "START 暂停　SELECT 属性　菜单里 Ⓐ 确认、Ⓑ 返回　LB / RB 翻页"],
		["", "编队、灯火、藏品、商人、结局等说明在开局指南里，暂停时按 G 可以随时重看"],
	]
	# 触屏（手机，逻辑高约 481，面板 460）：行距 32 → 30，最后一行不再压到「点击任意处返回」；桌面不变
	var lstep: float = 30.0 if Pad.touch_ui() else 32.0
	for i in lines.size():
		var y := r.position.y + 98 + i * lstep   # 11 行：行距 35 → 32，最后一行仍在底部提示之上
		if lines[i][0] != "":
			UI.diamond(self, Vector2(r.position.x + 44, y - 7), 4.0, UI.CYAN)
		UI.text(self, font, Vector2(r.position.x + 60, y), lines[i][0], 18, UI.CYAN)
		UI.text_fit(self, font, Vector2(r.position.x + 190, y), lines[i][1], 17, UI.TEXT, r.size.x - 190 - 36, 13)
	UI.text(self, font, Vector2(r.position.x, r.end.y - 24), Pad.hint("按任意键返回", "按任意键返回（Ⓐ / Ⓑ）", "点击任意处返回"), 14, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


## 致谢与声明：内容来自 data/credits.json。左列条目名（长的折两行）、右列说明 + 链接。
## 10-11 用户：「字放大点，改成滚动条」——正文固定字号（说明 17、条目名 19、链接 14，不再按屏幕高度缩到 11），
## 标题与底部（声明 + 「返回」按钮）钉住，中间条目在裁剪子控件 cr_view 里滚动；右侧滚动条可拖，上下有内容时边缘渐隐。
## 滚动：滚轮、拖正文（触屏松手带惯性）、拖滚动条、↑↓ / W S、PgUp / PgDn（手柄 LB / RB）、Home / End、手柄十字键 / 左摇杆（Pad 翻译成 ↑↓ 连发）。
## 关闭：Esc / Enter / 空格 / C（手柄 Ⓐ Ⓑ Ⓨ）、点「返回」、点面板外。说明按像素宽度排版（docs/37，UI.fit 自带防孤字）
const CREDITS_W := 1040.0
const CREDITS_LX := 58.0       # 条目名左边（菱形在它左边）
const CREDITS_LW := 170.0      # 条目名列宽
const CREDITS_HEAD := 84.0     # 标题区高度
const CREDITS_FOOT := 70.0     # 底部声明 + 返回按钮
const CREDITS_FS := 17         # 说明字号（原来按高度 14 → 11）
const CREDITS_LINE := 52.0     # ↑↓ 一步滚动量
const CR_SLOP := 10.0          # 按下后移动超过这个距离算拖动


func _open_credits() -> void:
	credits = true
	cr_scroll = 0.0
	cr_scroll_f = 0.0
	cr_vel = 0.0
	cr_drag = 0


func _close_credits() -> void:
	cr_drag = 0
	cr_vel = 0.0
	_close_info()


func _credits_tick(delta: float) -> void:
	if cr_view == null:
		return
	cr_view.visible = credits
	if not credits:
		return
	if cr_drag == 0 and absf(cr_vel) > 1.0:
		# 松手惯性：按速度继续滚，指数衰减；碰到两端停下
		cr_scroll = clampf(cr_scroll + cr_vel * delta, 0.0, cr_max)
		cr_vel *= exp(-4.0 * delta)
		if cr_scroll <= 0.0 or cr_scroll >= cr_max:
			cr_vel = 0.0
		cr_scroll_f = cr_scroll
	elif cr_drag == 0:
		cr_scroll_f = lerpf(cr_scroll_f, cr_scroll, 1.0 - exp(-16.0 * delta))
		if absf(cr_scroll_f - cr_scroll) < 0.25:
			cr_scroll_f = cr_scroll
	cr_view.queue_redraw()


func _credits_scroll_by(d: float) -> void:
	cr_vel = 0.0
	cr_scroll = clampf(cr_scroll + d, 0.0, cr_max)


## 滚动条：按在轨道上 y 处 → 滑块中心对到 y
func _credits_bar_to(y: float) -> void:
	if cr_max <= 0.0:
		return
	var th: float = _credits_thumb_h()
	var k: float = clampf((y - cr_vr.position.y - th / 2.0) / maxf(1.0, cr_vr.size.y - th), 0.0, 1.0)
	cr_scroll = k * cr_max
	cr_scroll_f = cr_scroll
	cr_vel = 0.0


func _credits_thumb_h() -> float:
	return maxf(36.0, cr_vr.size.y * cr_vr.size.y / (cr_vr.size.y + cr_max))


func _credits_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var page: float = maxf(CREDITS_LINE, cr_vr.size.y - 60.0)
		match Pad.kc(event):
			KEY_UP, KEY_W:
				_credits_scroll_by(-CREDITS_LINE)
			KEY_DOWN, KEY_S:
				_credits_scroll_by(CREDITS_LINE)
			KEY_PAGEUP, KEY_Q:
				_credits_scroll_by(-page)
			KEY_PAGEDOWN, KEY_E:
				_credits_scroll_by(page)
			KEY_HOME:
				_credits_scroll_by(-cr_max - 1.0)
			KEY_END:
				_credits_scroll_by(cr_max + 1.0)
			KEY_ESCAPE, KEY_BACKSPACE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_C, KEY_X:
				if not event.echo:
					_close_credits()
					Sfx.play("ui_ok")
	elif event is InputEventMouseButton:
		var mp: Vector2 = make_input_local(event).position
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					var f: float = event.factor if event.factor > 0.0 else 1.0
					_credits_scroll_by((-1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0) * 60.0 * f)
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					cr_press = mp
					cr_moved = false
					cr_vel = 0.0
					if cr_max > 0.0 and cr_bar.has_point(mp):
						cr_drag = 2
						_credits_bar_to(mp.y)
					elif cr_vr.has_point(mp):
						cr_drag = 1
						cr_scroll_f = cr_scroll   # 按住就停（惯性 / 平滑都停在当前显示位置）
						cr_scroll = cr_scroll_f
					else:
						cr_drag = 3   # 面板外 / 返回按钮：松手时判定
				else:
					var was: int = cr_drag
					cr_drag = 0
					if was == 3 and not cr_moved and (cr_back.has_point(mp) or not cr_panel.has_point(mp)):
						_close_credits()
						Sfx.play("ui_ok")
	elif event is InputEventMouseMotion:
		var mp: Vector2 = make_input_local(event).position
		if cr_drag != 0 and not cr_moved and cr_press.distance_to(mp) > CR_SLOP:
			cr_moved = true
		if cr_drag == 2:
			_credits_bar_to(mp.y)
		elif cr_drag == 1 and cr_moved:
			# 1:1 跟手（标题页放大后 relative 也要换到本地比例）
			var dy: float = (make_input_local(event) as InputEventMouseMotion).relative.y
			cr_scroll = clampf(cr_scroll - dy, 0.0, cr_max)
			cr_scroll_f = cr_scroll
			var dt: float = maxf(get_process_delta_time(), 1.0 / 240.0)
			cr_vel = lerpf(cr_vel, -dy / dt, 0.5)


func _draw_credits(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.02, 0.04, 0.9))
	var secs: Array = credits_data.get("sections", [])
	var touch: bool = Pad.touch_ui()
	var pw: float = minf(CREDITS_W, vs.x - (24.0 if touch else 48.0))
	var tx: float = CREDITS_LX + CREDITS_LW + 18.0
	var tw: float = pw - tx - 56.0   # 右边留滚动条
	if tw != cr_lay_w or cr_lay.is_empty():
		cr_lay = _credits_layout(secs, CREDITS_FS, tw)
		cr_lay_w = tw
	var margin: float = 8.0 if touch else 16.0
	var h: float = minf(CREDITS_HEAD + cr_lay.h + 8.0 + CREDITS_FOOT, vs.y - 2.0 * margin)
	var r := Rect2(roundf(vs.x / 2 - pw / 2), roundf(maxf(margin, vs.y / 2 - h / 2)), pw, h)
	cr_panel = r
	UI.panel(self, r, UI.BG2, UI.CYAN_DIM, 16.0, UI.CYAN)
	var title: String = credits_data.get("title", "致谢与声明")
	UI.text(self, font, r.position + Vector2(36, 52), title, 26, UI.TEXT)
	UI.en(self, font, r.position + Vector2(36 + font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x + 18, 50), credits_data.get("en", "CREDITS"), 12, UI.CYAN, 3.0)
	UI.rule(self, r.position + Vector2(36, 68), r.position + Vector2(pw - 36, 68), UI.EDGE_DIM)
	# 正文可视区（钉住的标题与底部之间）
	cr_vr = Rect2(r.position.x + 20, r.position.y + CREDITS_HEAD - 8.0, pw - 40, h - CREDITS_HEAD + 8.0 - CREDITS_FOOT)
	cr_max = maxf(0.0, cr_lay.h + 16.0 - cr_vr.size.y)
	cr_scroll = clampf(cr_scroll, 0.0, cr_max)
	cr_scroll_f = clampf(cr_scroll_f, 0.0, cr_max)
	cr_view.position = cr_vr.position
	cr_view.size = cr_vr.size
	if cr_max > 0.0:
		# 滚动条：正文右侧 6 像素（触屏 8），轨道命中区左右各放宽到 28；上下有内容时边缘渐隐
		var bw: float = 8.0 if touch else 6.0
		var track := Rect2(cr_vr.end.x - bw - 6.0, cr_vr.position.y + 4.0, bw, cr_vr.size.y - 8.0)
		cr_bar = Rect2(track.position.x - 12.0, track.position.y, bw + 24.0, track.size.y)
		draw_rect(track, Color(1, 1, 1, 0.07))
		var th: float = maxf(36.0, track.size.y * cr_vr.size.y / (cr_vr.size.y + cr_max))
		var hot: bool = cr_drag == 2 or cr_bar.has_point(get_local_mouse_position())
		draw_rect(Rect2(track.position.x, track.position.y + (track.size.y - th) * clampf(cr_scroll_f / cr_max, 0.0, 1.0), bw, th), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.95 if hot else 0.7))
	else:
		cr_bar = Rect2()
	# 底部钉住：细线 + 声明 + 操作提示 + 「返回」
	var fy: float = r.end.y - CREDITS_FOOT
	UI.rule(self, Vector2(r.position.x + 36, fy + 4), Vector2(r.end.x - 36, fy + 4), UI.EDGE_DIM)
	var bw2: float = 132.0 if touch else 120.0
	cr_back = Rect2(r.end.x - 36 - bw2, fy + 16, bw2, 40.0 if touch else 36.0)
	var back_hot: bool = cr_back.has_point(get_local_mouse_position()) and not touch
	UI.button(self, font, cr_back, Pad.hint("返回  Esc", "返回  Ⓑ", "返回"), "normal", back_hot, 17 if touch else 16)
	var fw: float = cr_back.position.x - 24 - (r.position.x + 36)
	var ft := UI.fit_line(font, credits_data.get("footer", ""), 15, fw, 12)
	UI.text(self, font, Vector2(r.position.x + 36, fy + 32), ft[0], ft[1], UI.SUB)
	var hint := Pad.hint("滚轮 / ↑↓ / PgUp PgDn 滚动 · 拖动右侧滚动条", "十字键 / 左摇杆 滚动 · LB / RB 翻页", "上下滑动查看全部")
	UI.text_fit(self, font, Vector2(r.position.x + 36, fy + 54), hint, 13, Color(UI.SUB.r, UI.SUB.g, UI.SUB.b, 0.75), fw, 11)


## 正文条目（cr_view 子控件里画，坐标原点 = 可视区左上，按 cr_scroll_f 平移，超出的被裁掉）
func _draw_credits_body() -> void:
	if not credits or cr_lay.is_empty():
		return
	var ox: float = -20.0   # 子控件原点在面板左边 + 20
	var tx: float = CREDITS_LX + CREDITS_LW + 18.0
	var y: float = 8.0 - cr_scroll_f
	for row in cr_lay.rows:
		if y + row.h >= 0.0 and y <= cr_vr.size.y:
			UI.diamond(cr_view, Vector2(ox + 44, y + 12), 4.0, UI.CYAN)
			UI.draw_fit(cr_view, font, Vector2(ox + CREDITS_LX, y), row.label, UI.CYAN)
			var th: float = UI.draw_fit(cr_view, font, Vector2(ox + tx, y + 2), row.text, UI.TEXT)
			if row.link != "":
				UI.text_fit(cr_view, font, Vector2(ox + tx, y + 2 + th + 4 + font.get_ascent(14)), row.link, 14, Color(0.5, 0.75, 0.85), cr_vr.size.x - tx - 40.0, 11)
		y += row.h
	# 上下边缘渐隐：提示那头还有内容
	if cr_scroll_f > 0.5:
		_credits_vfade(true)
	if cr_scroll_f < cr_max - 0.5:
		_credits_vfade(false)


func _credits_vfade(top: bool) -> void:
	var n := 8
	var hh: float = 26.0 / n
	var w: float = cr_vr.size.x - 28.0
	for k in n:
		var a: float = 0.8 * (1.0 - (k + 0.5) / n)
		var yy: float = (k * hh) if top else (cr_vr.size.y - (k + 1) * hh)
		cr_view.draw_rect(Rect2(0, yy, w, hh + 0.5), Color(0.06, 0.08, 0.1, a))


## 致谢页排版：每条 {label: 条目名 fit, text: 说明 fit, link, h}；返回 {rows, h}
func _credits_layout(secs: Array, fs: int, tw: float) -> Dictionary:
	var rows: Array = []
	var total := 0.0
	var gap: float = 16.0
	for sec in secs:
		# 条目名：先试一行（19 → 17 号），放不下再折成两行，按半长折开（「第三方开放许可 / 特效素材」）
		var lab := UI.fit(font, sec[0], CREDITS_LW, font.get_height(19), [19, 18, 17])
		if not lab.fit:
			var half: float = font.get_string_size(sec[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x / 2.0 + 18.0
			lab = UI.fit(font, sec[0], minf(CREDITS_LW, half), 2.0 * font.get_height(18), [18, 17])
		var txt := UI.fit(font, sec[1], tw, 9999.0, [fs], 3.0)   # UI.fit 自带防孤字；行距加 3
		var link: String = sec[2] if sec.size() > 2 else ""
		var rh: float = maxf(float(lab.h), float(txt.h) + (6.0 + font.get_height(14) if link != "" else 0.0)) + gap
		rows.append({"label": lab, "text": txt, "link": link, "h": rh})
		total += rh
	return {"rows": rows, "h": total}


## 自测截图目录：默认 /tmp/claude-0，--shotdir= 覆盖（Windows 本地用）
## 三联对照截图（docs/25 §5 验收：精一前 / 精二前 / 全部三个阶段并排，只看普攻）
## 用法：--compareshot=<干员 id>[,等待秒数]；输出 shot_compare_<id>.png 后退出
func _compare_shot(spec: String) -> void:
	var parts := spec.split(",")
	var cid: String = parts[0]
	var wait: float = float(parts[1]) if parts.size() > 1 else 6.0
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.03, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var w: int = 520
	var h: int = 420
	var labels := ["精零 · N1 N2", "精一 · N4 N5", "精二"]
	for k in 3:
		var box := SubViewportContainer.new()
		box.stretch = false
		layer.add_child(box)
		var vp := SubViewport.new()
		vp.handle_input_locally = false
		box.add_child(vp)
		vp.size = Vector2i(w, h)
		box.position = Vector2(10 + k * (w + 10), 70)
		box.size = Vector2(w, h)
		var gm: Node = load("res://game.tscn").instantiate()
		gm.demo_op = cid
		gm.demo_stage = k
		gm.demo_basic = true
		vp.add_child(gm)
		var lb := Label.new()
		lb.text = labels[k]
		lb.position = Vector2(10 + k * (w + 10) + 12, 30)
		lb.add_theme_font_size_override("font_size", 22)
		layer.add_child(lb)
	# 直接取三个 SubViewport 的像素横向拼接（不受界面缩放影响）；从左到右 = 精零 N1 N2 / 精一 N4 N5 / 精二
	get_tree().create_timer(wait).timeout.connect(func():
		var imgs: Array = []
		for ch0 in layer.get_children():
			if ch0 is SubViewportContainer:
				imgs.append((ch0.get_child(0) as SubViewport).get_texture().get_image())
		var iw: int = imgs[0].get_width()
		var ih: int = imgs[0].get_height()
		var out := Image.create(iw * imgs.size() + 8 * (imgs.size() - 1), ih, false, imgs[0].get_format())
		out.fill(Color(0.9, 0.9, 0.9))
		for k in imgs.size():
			out.blit_rect(imgs[k], Rect2i(0, 0, iw, ih), Vector2i(k * (iw + 8), 0))
		out.save_png(_shot_dir() + "/shot_compare_%s.png" % cid)
		get_tree().quit())
