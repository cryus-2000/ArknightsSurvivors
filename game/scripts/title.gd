extends "res://scripts/screens/title_diff_pick.gd"
## 标题界面：「方舟幸存者」Logo + 菜单；背景是深海沉船与水母（title_deep.gd，10-24 用户定，docs/67 §13）
const HS = preload("res://scripts/screens/hh_style.gd")
const FR = preload("res://scripts/core/frame_rec.gd")
func _ready() -> void:
	if Cfg.dev_args().has("--loadprof"):
		# 启动计时（docs/36 §5）：引擎启动 → 标题页 _ready → 标题页首帧画完（毫秒，从引擎启动算）
		print("BOOTPROF title_ready=%d" % Time.get_ticks_msec())
		RenderingServer.frame_post_draw.connect(func(): print("BOOTPROF title_first_frame=%d" % Time.get_ticks_msec()), CONNECT_ONE_SHOT)
	if FR.enabled():
		FR.mark("title_ready")
		RenderingServer.frame_post_draw.connect(func(): FR.mark("title"), CONNECT_ONE_SHOT)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_idle_fps = preload("res://scripts/core/idle_fps.gd").new()   # 手机网页闲置降帧（docs/50 §33）：boot_reveal 后才开
	add_child(_idle_fps)
	_bg_game.call_deferred()
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
	# Logo 主体（像素徽记 + 像素中文；拉丁小字由菜单模块矢量画）：缩小显示，用带多级纹理的线性取样，免得最近邻缩小丢像素
	var lg_img: Image = preload("res://art/ui/title_deep/logo_mark.png").get_image()
	lg_img.generate_mipmaps()
	tex_logo = ImageTexture.create_from_image(lg_img)
	_prewarm()   # 标题页自己的几张图先取，预热名单里就不用再算
	# 封面背景：深海沉船与水母（放在更底层的 CanvasLayer，菜单画在它上面）
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -1
	add_child(bg_layer)
	title_bg = preload("res://scripts/title_deep.gd").new()
	bg_layer.add_child(title_bg)
	logo_ci = Control.new()   # Logo 单独一层：线性 + 多级纹理取样（标题页其余贴图沿用项目缺省的最近邻）
	logo_ci.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo_ci.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	logo_ci.draw.connect(_draw_logo_layer)
	add_child(logo_ci)
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
	hunt_ui = preload("res://scripts/screens/hunt_host.gd").new()
	add_child(hunt_ui)
	if preload("res://scripts/core/roster.gd").needs_first():
		sel = 7   # 新手开局（名册为空）：缺省选中寻访，Enter 直接去做新手十连
	medals_ui = preload("res://scripts/screens/medals_ui.gd").new()
	add_child(medals_ui)
	if get_tree().has_meta("settlement_open_meta"):
		get_tree().remove_meta("settlement_open_meta")
		meta_ui.open.call_deferred()
	var transition_layer := CanvasLayer.new()
	transition_layer.layer = 90
	add_child(transition_layer)
	transition = preload("res://scripts/screens/scene_transition.gd").new()
	transition_layer.add_child(transition)
	var loading_layer := CanvasLayer.new()
	loading_layer.layer = 80   # 盖住标题 Logo 层、选人 / 难度页与后期层；转场遮罩（90）仍在它上面
	add_child(loading_layer)
	loading = preload("res://scripts/screens/loading_screen.gd").new()
	loading_layer.add_child(loading)
	_add_title_tour.call_deferred()   # 主界面引导（新手十连之后）：要盖在图鉴等所有叠层之上，等 _ready 里的子节点都建完再作为最后一个子节点加
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
				if a2 == "--gallerygroup":
					gallery._set_group(true)   # 截图自测：干员页按职业分组（10-26）
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
	if (not args.is_empty() and not args.has("--introshot") and not args.has("--introshort") and not args.has("--titlemotion") and not args.has("--ftrec")) or Cfg.title_seen:
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
		if Cfg.dev_args().has("--metahide"):   # 详情卡收起时的截图（10-27）
			meta_ui.card_hide = true
		if Cfg.dev_args().has("--metalit"):   # 解锁演出截图：0.6 秒时塑造选中节点，演出进行到 0.35 秒时截
			get_tree().create_timer(0.6).timeout.connect(func(): meta_ui._buy(meta_ui._sel_id()))
		get_tree().create_timer(0.95 if Cfg.dev_args().has("--metalit") else 1.0).timeout.connect(func():
			get_viewport().get_texture().get_image().save_png(_shot_dir() + "/shot_meta.png")
			get_tree().quit())
	if Cfg.dev_args().has("--medalshot"):
		# 蚀刻章页截图（10-25）：--medalsel=<key> 选中哪枚；--medalgif=<张数>,<间隔秒> 连拍（背景动态做 gif）；
		# 已得章用 --medals=all / key,key 预置（settings.gd，只在内存）
		medals_ui.open()
		var shots := [1, 0.0]
		for a in Cfg.dev_args():
			if a.begins_with("--medalsel="):
				medals_ui.sel = maxi(0, medals_ui._index_of(a.substr(11)))
			if a.begins_with("--medalgif="):
				var gp := a.substr(11).split(",")
				shots = [int(gp[0]), float(gp[1]) if gp.size() > 1 else 0.5]
		for i in int(shots[0]):
			get_tree().create_timer(1.0 + i * float(shots[1])).timeout.connect(func():
				print("MEDALSHOT size=%s k=%.3f" % [medals_ui.size, medals_ui.k])
				var path: String = _shot_dir() + ("/shot_medals.png" if int(shots[0]) == 1 else "/shot_medals_%03d.png" % i)
				get_viewport().get_texture().get_image().save_png(path)
				if i == int(shots[0]) - 1:
					get_tree().quit())
	if Cfg.dev_args().has("--medalvideo"):
		# 蚀刻章演示录像（10-25 用户要视频；配 Godot --write-movie + --fixed-fps 30）：标题页 1.2 秒 → 点「蚀刻章」→
		# 依次选几枚章（每 1.3 秒一枚）→ 停在背景动态上，共 15 秒后退出
		intro = INTRO_LEN
		sel = 8
		get_tree().create_timer(1.2).timeout.connect(func(): _activate(8))
		var keys := ["ending_knight", "ending_standard", "elite_three", "cognition_complete", "cognition_first", "relic_fifty", "set_complete"]
		for i in keys.size():
			get_tree().create_timer(2.8 + 0.9 * i).timeout.connect(func(): medals_ui._pick(medals_ui._index_of(keys[i])))
		get_tree().create_timer(15.0).timeout.connect(func(): get_tree().quit())
	if Cfg.dev_args().has("--medalperf"):
		intro = INTRO_LEN
		medals_ui.open()
		medals_ui.perf_t = 0.0   # 帧时测量（tools/perf_web.py run … -- --medalperf）：背景动 / 静轮换 24 秒
	if Cfg.dev_args().has("--metademo"):
		# 认知塑造演示录像（10-25）：配 --write-movie <文件.avi> --fixed-fps 30 与 --metacells / --metabuy；可选 --metastyle=tree|sea。
		# 0.5 秒从标题进入 → 按 --metademokeys（R/L/U/D 方向、E 塑造、W 停一拍；缺省见下）每 0.75 秒一个键（塑造后停 1.6 秒）→ 10 秒退出
		intro = INTRO_LEN
		for a in Cfg.dev_args():
			if a.begins_with("--metabuy="):
				Cfg.meta_shape = preload("res://scripts/core/meta.gd").shape_for(int(a.substr(10)))
		var keys := "D,D,D,R,D,E,U,U,L"
		for a in Cfg.dev_args():
			if a.begins_with("--metademokeys="):
				keys = a.substr(15)
		get_tree().create_timer(0.5).timeout.connect(func(): _activate(6))
		var kmap := {"R": KEY_RIGHT, "L": KEY_LEFT, "U": KEY_UP, "D": KEY_DOWN, "E": KEY_ENTER}
		var at := 1.9
		for kname in keys.split(","):
			var kc: int = kmap.get(kname, 0)
			if kc != 0:
				get_tree().create_timer(at).timeout.connect(func():
					for down in [true, false]:
						var e := InputEventKey.new()
						e.keycode = kc
						e.pressed = down
						Input.parse_input_event(e))
			at += 1.6 if kname == "E" else 0.75
		get_tree().create_timer(10.0).timeout.connect(func(): get_tree().quit())
	if Cfg.dev_args().has("--titlehunt"):
		# 标题页寻访入口截图（10-22）：配 --rostertickets=<n>；打开寻访入口 1.2 秒后截
		intro = INTRO_LEN
		_activate(7)
		get_tree().create_timer(1.2).timeout.connect(func():
			print("TITLEHUNT open=%s" % hunt_ui.visible)
			get_viewport().get_texture().get_image().save_png(_shot_dir() + "/shot_titlehunt.png")
			get_tree().quit())
	if Cfg.dev_args().has("--settingsshot"):
		settings.open()
		if Cfg.dev_args().has("--perfview"):
			settings.open_perf()   # 截图自测：性能报告页（数据读 user://perf_reports_test.json，先跑一局带 --perfreport 的测试写进去）
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
		# 出发后载入页的截图（预读完也停在载入页，截图时强制画出来）；带 --reducemotion 截静态版
		leaving = 0.0
		if Cfg.dev_args().has("--reducemotion"):
			Cfg.reduce_motion = true
		get_tree().create_timer(1.3).timeout.connect(func():
			get_viewport().get_texture().get_image().save_png(_shot_dir() + "/shot_loading.png")
			get_tree().quit())
	if Cfg.dev_args().has("--titleshot"):
		# 可选 --titlesel=<菜单项 id 0–7>（截选中别的入口）
		for a in Cfg.dev_args():
			if a.begins_with("--titlesel="):
				sel = clampi(int(a.substr(11)), 0, ITEMS.size() - 1)
				if not _menu_ids().has(sel):
					sel = 0
			if a == "--reducemotion":
				Cfg.reduce_motion = true
		get_tree().create_timer(2.0).timeout.connect(func():
			get_viewport().get_texture().get_image().save_png(_shot_dir() + "/shot_title.png")
			get_tree().quit())
	var tour_demo := false   # --tourdemo / --tipdemo=<id>：真人局（不带机器人）直接进对局演引导 / 小提示（screens/tour.gd）
	for a in Cfg.dev_args():
		if a == "--tourdemo" or a.begins_with("--tipdemo="):
			tour_demo = true
	if Cfg.dev_args().has("--autotest") or Cfg.dev_args().has("--balance") or tour_demo:
		if A.prewarm_busy() or Sfx.warm_busy() or Cfg.dev_args().has("--loadprof"):
			auto_go = true   # 开窗口的自测：等法线图预热完（同玩家路径），黑屏时长才有可比性；--loadprof 一律走载入页（量玩家路径）
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


## 启动页盖着时（screens/boot_screen.gd 把标题页建在它下面）：先按开场播完的样子画（Logo、入口、水母背景都画到，
## 着色器 / 贴图 / 字形都在盖层下面备好），揭开时开场从头播
var _intro0 := -1.0

func boot_cover() -> void:
	_intro0 = intro
	intro = INTRO_LEN


var _idle_fps: Node = null

func boot_reveal() -> void:
	if _idle_fps != null:
		_idle_fps.set("armed", true)
	if _pw_on and not _pw_rev:
		_pw_rev = true
		print("PF POWER reveal t=%.1f" % (Time.get_ticks_msec() / 1000.0))
	if _intro0 >= 0.0:
		intro = _intro0
		_intro0 = -1.0
	_bg_game()


## 桌面：标题页一建好（启动页还盖着时就开始）就在后台线程把对局场景（game.gd 那一圈 41 个脚本）编译好，出发 / 图鉴演示时直接命中缓存；
## 出发时还没编完，载入页照常动着等（_wl_pending）。
## 网页没有线程，照旧在第一次用到时编译（载入页 / 第一次开图鉴）。启动页不再读这一圈（docs/50 §29）
var _bg_game_started := false

func _bg_game() -> void:
	if _bg_game_started or OS.has_feature("web") or not OS.has_feature("threads") or DisplayServer.get_name() == "headless":
		return
	var args := Cfg.dev_args()
	if not args.is_empty() and not args.has("--ftrec") and not args.has("--loadprof"):
		return   # 截图 / 测试局常在一两秒内退出：后台还在编译时退出会报「Could not preload」，算快检失败；只在玩家路径和帧时测量里做
	_bg_game_started = true
	if not ResourceLoader.has_cached("res://game.tscn"):
		ResourceLoader.load_threaded_request("res://game.tscn")


## 帧时记录的脚本动作（--ftdo=<标记>:<秒>:<动作>，core/frame_rec.gd）：打开寻访 / 图鉴、图鉴换条目 / 换页签、关掉
func _ft_action(what: String) -> void:
	match what:
		"hunt":
			FR.mark("hunt")
			hunt_ui.open()
		"gallery":
			FR.mark("gallery")
			gallery.open()
		"gal_next":
			FR.mark("gal_next")
			gallery._step(1)
		"gal_tab":
			FR.mark("gal_tab")
			gallery._set_tab((gallery.tab + 1) % 3)
		"close":
			FR.mark("close")
			if gallery.visible:
				gallery.close()
			if hunt_ui.visible:
				hunt_ui.hh.open = false


func _process(delta: float) -> void:
	var ft := FR.tic()
	_process_main(delta)
	FR.toc("title_proc", ft)
	if _pw_on:
		_power_title()


## --powerseq 停在标题页（tools/probes/power_web.py --title，docs/50 §33）：启动页揭开（boot_reveal）6 秒后记 20 秒「title」段（闲置降帧 4 秒后才开）；
## 另打 PF POWER reveal（揭开时刻），看降帧有没有拖慢启动
var _pw_on: bool = Cfg.dev_args().has("--powerseq") and not Cfg.dev_args().has("--balance")
var _pw_t := 0.0
var _pw_fr := 0
var _pw_rev := false
func _power_title() -> void:
	if not _pw_rev:
		return
	_pw_t += get_process_delta_time()
	if _pw_t >= 6.0 and _pw_fr == 0:
		_pw_fr = Engine.get_frames_drawn()
		FR.mark("pw_title")
		if OS.has_feature("web"):
			JavaScriptBridge.eval("window.__phase='title'", true)
	elif _pw_t >= 26.0:
		_pw_on = false
		print("PF POWER title secs=20.0 fps=%.1f max_fps=%d" % [(Engine.get_frames_drawn() - _pw_fr) / 20.0, Engine.max_fps])
		FR.mark("pw_end")
		if OS.has_feature("web"):
			JavaScriptBridge.eval("window.__phase='end'", true)
		print("PF FTDONE")


func _process_main(delta: float) -> void:
	Pad.context = "title"
	var overlay_open: bool = _overlay_open()
	if post_fx != null:
		post_fx.crisp = gallery.visible or diff_pick or settings.visible or medals_ui.visible   # 局外终端 / 蚀刻章像素页：不叠辉光 / 水下色差
	if overlay_was_open and not overlay_open and not transition.busy:
		transition.reveal_page()
	overlay_was_open = overlay_open
	if leaving < 0.0 and not auto_go:
		Sfx.play_music(menu_track())   # 出发后（载入中）不换曲，开场引子由对局接手
	t += delta
	_menu_tick(delta)
	if diff_pick:
		difficulty_screen.tick(delta, diff_sel, Cfg.reduce_motion)
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
	# 背景：开场黑幕；被整屏界面盖住时停更（省网页帧时）；手机版式右下压暗（集结出发在那儿）
	if title_bg != null:
		title_bg.fade = (1.0 - _ease((intro - 0.1) / 1.1)) if intro < INTRO_LEN else 0.0
		title_bg.paused = gallery.visible or meta_ui.visible or hunt_ui.visible or medals_ui.visible or diff_pick or op_pick or guide or credits or leaving >= 0.0
		title_bg.corner = 1.0 if menu_lay.get("compact", false) else 0.0
	if logo_ci != null:
		logo_ci.size = size
		logo_ci.queue_redraw()
	A.prewarm_tick()
	if leaving >= 0.0 or auto_go:
		if not _op_warm_begun:
			_op_warm_begun = true
			Sfx.warm_begin()   # 选人 / 难度菜单切曲后，在实际载入页排队，避免菜单取消首段预热
			A.warm_begin(_op_fx_names(), [])
			_wl_pending = true   # 对局贴图名单要 game.gd：桌面后台还在编译就先等（载入页照常动），编完再取（下面）
			for cid in _op_ids():
				var sp: String = Character.script_path(cid)
				if not _op_scripts.has(sp) and ResourceLoader.load_threaded_request(sp) == OK:
					_op_scripts.append(sp)   # 干员脚本后台编译（data_operator.gd 首次加载约 1.4 秒，原来算在建局里）
			loading.begin()
			if DisplayServer.get_name() != "headless" and Cfg.quality != "low" and preload("res://scripts/core/balance.gd").v("render/optical", 1.0) > 0.0:   # 同 optical.wanted()：低画质不开粒子，不用编译
				_game_warm = preload("res://scripts/render/shader_warm.gd").new()
				_game_warm.parts = 1   # 光学 GPU 粒子的处理材质（render/shader_warm.gd PARTS_GAME，网页才有；桌面启动页已画过就是空的）：在载入页编译，不留到进局后
				add_child(_game_warm)
		if _wl_pending and not (_bg_game_started and ResourceLoader.load_threaded_get_status("res://game.tscn") == ResourceLoader.THREAD_LOAD_IN_PROGRESS):
			_wl_pending = false
			var wl: Array = _game().loading_warm_lists()   # 网页（无后台编译）：game.gd 那一圈在这一帧编译，载入页停一下（以前在启动页）
			A.warm_begin(wl[0], wl[1])   # 对局 _ready 要读的整批贴图也在这里分帧读完（以前在 _ready 里一口气读，网页冻住 ~32 秒，10-25）
		var wt0 := Time.get_ticks_usec()
		_op_warm_more = A.warm_step(LOAD_BUDGET_USEC) or _wl_pending   # 开局干员的技能 / 特效帧条先读进贴图缓存（10-22 网页开局掉帧：第一次放技能时现读）
		for sp in _op_scripts.duplicate():
			if ResourceLoader.load_threaded_get_status(sp) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				_op_warm_more = true
			else:
				if ResourceLoader.load_threaded_get_status(sp) == ResourceLoader.THREAD_LOAD_LOADED:
					get_tree().set_meta("op_script_" + sp.get_file().get_basename(), ResourceLoader.load_threaded_get(sp))   # 挂在场景树上留住缓存，切场景后对局 load() 直接命中
				_op_scripts.erase(sp)
		if not _op_warm_more and not _grow_strips.is_empty():
			# 扩散帧条的每帧半径（ob_fx.warm_frame_r，同一张贴图、同一算式）：一帧算一张
			var sn: String = _grow_strips.pop_back()
			var v6: Dictionary = load("res://scripts/game.gd").V6_FRAMES
			if v6.has(sn):
				load("res://scripts/characters/blocks/ob_fx.gd").warm_frame_r(sn, A.tex(sn), maxi(1, int(v6[sn][0])))
			_op_warm_more = not _grow_strips.is_empty()
		Sfx.warm_step(maxi(1000, LOAD_BUDGET_USEC - (Time.get_ticks_usec() - wt0)))   # 出发后的等待里逐条注册音频样本（网页；桌面队列为空）：和读图共用一帧预算
		_loading_progress()
	if leaving >= 0.0:
		leaving += delta
		if leaving > 0.7:
			# 预热 / 预读没完就停在载入页等它（以前这里直接切场景，game.gd _ready 同步算 10 秒法线图 = 黑屏），最多等 60 秒
			if (A.prewarm_busy() or Sfx.warm_busy() or _op_warm_more or is_instance_valid(_game_warm) or Cfg.dev_args().has("--loadingshot")) and wait_t < 60.0:
				wait_t += delta
			else:
				loading.finish()   # 淡到黑，开场演出从同一片黑里亮起
				if loading.done():
					A.mark("title_leave")
					get_tree().change_scene_to_file("res://game.tscn")
	elif auto_go and not A.prewarm_busy() and not Sfx.warm_busy() and not _op_warm_more and _op_warm_begun and not is_instance_valid(_game_warm):
		loading.finish()
		if loading.done():
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
	if leaving >= 0.0 or transition.busy or _overlay_open() or _intro0 >= 0.0:   # _intro0 ≥ 0：启动页还盖着，不收输入
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
		for i in item_rects.size():
			if item_rects[i].has_point(make_input_local(event).position):
				_activate(i)


## 主界面引导（screens/title_tour.gd）：作为最后一个子节点，_input 先于图鉴 / 标题，盖在所有叠层之上
func _add_title_tour() -> void:
	var tt: Control = preload("res://scripts/screens/title_tour.gd").new()
	add_child(tt)
	tt.setup(self)


func _close_info() -> void:
	transition.switch_page(func():
		guide = false
		credits = false)


## 盖在标题上的界面（各自处理 Esc、关掉时 visible = false）：开着时标题不收输入，关掉那一帧 reveal_page。新的局外界面登记在这里
func _overlays() -> Array:
	return [settings, gallery, boss_trial, meta_ui, hunt_ui, medals_ui]


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


## 菜单导航（title_jelly_menu.nav）：按几何方向找最近的一项，不循环
func _menu_nav(d: Vector2i) -> void:
	if menu_lay.is_empty():
		menu_lay = _menu_layout()
	_menu_set(Tiles.nav(menu_lay, sel, d), false)


## 菜单排版每帧都要（命中区 = 终态位置），但只随尺寸 / 入口 / 安全区 / 触屏变：按这几样记住上一份（10-25 帧率审计，排版里有一串字宽测量）
var _lay_key := ""
var _lay_cache := {}

func _menu_layout() -> Dictionary:
	var ids := _menu_ids()
	var ins := Cfg.safe_insets()
	var touch: bool = Pad.touch_ui() or Cfg.touch_device()
	var key := "%s|%s|%s|%s|%s" % [size, ids, ins, touch, UI.fk]   # UI.fk：设置里的字号倍率
	if key != _lay_key or _lay_cache.is_empty():
		_lay_key = key
		_lay_cache = Tiles.layout(size, ids, ins, touch, font)
	return _lay_cache


## 换选中：选中底条从此刻开始展开（remember 沿用旧接口，深海水母版不用）
func _menu_set(i: int, _remember: bool) -> void:
	if not _menu_ids().has(i):
		return
	if i == sel:
		return
	sel = i
	Sfx.play("ui_move")


func _activate(i: int) -> void:
	if transition.busy:
		return
	Sfx.play("ui_ok")
	match i:
		0:
			if preload("res://scripts/core/roster.gd").needs_first():
				sel = 7   # 新手十连之前名册为空、出发不了：点「集结出发」先带去寻访（10-26 用户）
				_activate(7)
				return
			transition.switch_page(_open_op_pick.bind(false))
		1:
			gallery.open()   # 10-22 用户：进图鉴不要入场动效，直接出现
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
		8:
			transition.switch_page(medals_ui.open)   # 蚀刻章「深蓝之下」（10-25）
		7:
			if not hunt_ui.open():
				Sfx.play("ui_move", -4.0, 0.6)   # 名册未启用：点了只响一声（10-24 起没有凭证也能进去看）


## 入口入场（docs/62「每屏一个主动作」）：1.25 秒起四个入口依次从左滑入（间隔 0.08 秒，每个 0.4 秒）、1.6 集结出发、2.0 底部一行；
## 减少动态效果：不滑动，只淡入（滑动量在 _draw 里按 Cfg.reduce_motion 置 0）
func _item_a(i: int) -> float:
	var it: Dictionary = Tiles.item(i)
	if it.is_empty():
		return 0.0
	if it.slot == "list":
		var lst: Array = menu_lay.get("list", {}).get("ids", [])
		return _seg(1.25 + 0.08 * maxi(0, lst.find(i)), 0.4)
	return _seg(1.6, 0.5) if it.slot == "deploy" else _seg(2.0, 0.4)


## 选中底条：选中项展开、其余收起（0.22 秒）；入口还没出现时不展开；减少动态效果直接到位
func _menu_tick(delta: float) -> void:
	for i in ITEMS.size():
		var target := 1.0 if i == sel and _item_a(i) >= 1.0 else 0.0
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
	var ft := FR.tic()
	_draw_main()
	FR.toc("title_draw", ft)


func _draw_main() -> void:
	var vs := size
	if diff_pick and not op_pick and not guide and not credits:
		# 难度页（T5s）：整屏是它自己的版式，标题的 Logo / 磁贴 / 页脚都不画
		_draw_diff(vs)
		_draw_leaving(vs)
		return
	# 测试版提示（右上，暗底衬板）
	if Cfg.unlock_all:
		# 对内发布包名册按新玩家走（测寻访），只有图鉴 / 难度 / 结局全开
		var tb_txt: String = "测试版 · 图鉴与难度全开（不写入存档）" if Cfg.internal_roster() else "测试版 · 已全部解锁（不写入存档）"
		var tbw: float = font.get_string_size(tb_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var tr: float = vs.x - 30 - Cfg.safe_insets()[2]
		draw_rect(Rect2(tr - tbw - 12, 13, tbw + 24, 24), Color(0.02, 0.03, 0.05, 0.85))
		draw_rect(Rect2(tr - tbw - 12, 13, 3, 24), UI.GOLD)
		UI.text(self, font, Vector2(tr - 300, 30), tb_txt, 12, UI.GOLD, HORIZONTAL_ALIGNMENT_RIGHT, 300)
	# 菜单（深海水母版，docs/67 §13）：版式按当前尺寸 / 安全区算，命中区就是终态位置（docs/62 §2.5）
	item_rects.clear()
	item_rects.resize(ITEMS.size())
	item_rects.fill(Rect2())
	menu_lay = _menu_layout()
	for i in menu_lay.rects:
		item_rects[i] = menu_lay.rects[i]
	if not op_pick:
		_draw_menu(vs)
	if guide:
		_draw_guide(vs)
	if credits:
		_draw_credits(vs)
	if op_pick:
		_draw_op_pick(vs)
	_draw_leaving(vs)


func _draw_menu(vs: Vector2) -> void:
	var a_list: Array = []
	for i in menu_lay.list.ids:
		a_list.append(_item_a(i))
	const R = preload("res://scripts/core/roster.gd")
	var first := R.needs_first()
	Tiles.draw(self, menu_lay, {"font": font, "sel": sel, "water": menu_water, "now": t, "rm": Cfg.reduce_motion,
		"a_logo": 0.0, "logo_tex": null, "a_list": a_list, "a_deploy": _item_a(0) * (0.35 if first else 1.0), "a_foot": _seg(2.0, 0.4),
		"slide": 0.0 if Cfg.reduce_motion else 16.0, "dim": [] if R.active() else [7], "tickets": R.tickets() if R.active() else -1})   # 10-24 用户：没有凭证也能点进寻访看卡池
	if first and not (guide or credits):
		_draw_first_guide()
	# 声明（同人 · 非商业 · 与鹰角网络无关 · 致谢与声明）+ 版本：桌面右下，手机跟在底部一行后面
	var ff := _seg(2.0, 0.4)
	var lg: Dictionary = menu_lay.legal
	var ph: bool = menu_lay.compact
	var tc := TUI.ctx(self)
	var ftxt: String = ("明日方舟同人作品 · 非商业 · 与鹰角网络无关 · 致谢与声明 %s" % Pad.hint("C", "Ⓨ", "")).strip_edges() if not ph else "同人作品 · 与鹰角网络无关 · 致谢与声明"
	var fs := 12 if not ph else 11
	var fw: float = font.get_string_size(ftxt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var vw := TUI.ptext_w(tc, "V2.0", 1.0)
	var fx: float = lg.pos.x - fw - 12.0 - vw if lg.align == "r" else lg.pos.x
	var fy: float = lg.pos.y
	credits_rect = Rect2(fx - 6, fy - 18, fw + 12, 26)
	if fx + fw + 12.0 + vw > lg.max_x:
		credits_rect = Rect2()   # 窄屏放不下：只留键盘 C / 手柄 Ⓨ 入口（设置页也能进）
	elif ff > 0.0:
		var cr_hover := credits_rect.has_point(get_local_mouse_position()) and intro >= INTRO_LEN
		UI.text(self, font, Vector2(fx, fy), ftxt, fs, _fa(Color(0.616, 0.898, 0.937) if cr_hover else Color(0.45, 0.53, 0.58), ff))
		TUI.ptext(self, tc, Vector2(fx + fw + 12.0, fy - 4.0), "V2.0", 1.0, _fa(Color(0.45, 0.53, 0.58), ff))
	# 对内包页脚提示（docs/40，用户 10-10）：声明上面一行；手机只在设置页提示
	if not ph and not OS.is_debug_build() and Cfg.runs_log_enabled():
		UI.text(self, font, Vector2(lg.pos.x - 310, fy - 20), "测试版：本地记录对局摘要（不上传）", 12, _fa(UI.GOLD, ff), HORIZONTAL_ALIGNMENT_RIGHT, 310)


## 新手引导（10-26 用户：开局名册为空，第一次进主界面引去寻访做新手十连）：寻访一行外圈青色角框呼吸 + 右侧箭头左右轻摆 + 一句提示；
## 「集结出发」压暗并写开放条件。命中区不变（点集结出发由 _activate 转去寻访）
func _draw_first_guide() -> void:
	var a := _item_a(7)
	var r: Rect2 = item_rects[7] if item_rects.size() > 7 else Rect2()
	if a <= 0.0 or r.size.x <= 0.0:
		return
	const C := Color(0.616, 0.898, 0.937)
	var p := 0.5 + 0.5 * sin(t * 4.0) if not Cfg.reduce_motion else 1.0
	var g := r.grow(6.0)
	var l := 14.0
	for cn in [[g.position, 1, 1], [Vector2(g.end.x, g.position.y), -1, 1], [Vector2(g.position.x, g.end.y), 1, -1], [g.end, -1, -1]]:
		var q: Vector2 = cn[0]
		draw_rect(Rect2(q + Vector2(0.0 if cn[1] > 0 else -l, 0.0 if cn[2] > 0 else -2.0), Vector2(l, 2.0)), _fa(C, a * (0.55 + 0.45 * p)))
		draw_rect(Rect2(q + Vector2(0.0 if cn[1] > 0 else -2.0, 0.0 if cn[2] > 0 else -l), Vector2(2.0, l)), _fa(C, a * (0.55 + 0.45 * p)))
	draw_rect(g, _fa(C, a * 0.08 * p))
	var ax := g.end.x + 14.0 + (0.0 if Cfg.reduce_motion else sin(t * 5.0) * 5.0)
	var ay := g.get_center().y
	draw_colored_polygon(PackedVector2Array([Vector2(ax, ay), Vector2(ax + 14.0, ay - 9.0), Vector2(ax + 14.0, ay + 9.0)]), _fa(C, a))
	var tx := ax + 22.0
	var fs := 15 if not menu_lay.compact else 13
	var tip := "新手寻访：十连招募 10 名干员"
	var tw: float = font.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_rect(Rect2(tx - 6.0, ay - 15.0, tw + 14.0, 30.0), Color(0.02, 0.05, 0.07, 0.82 * a))
	draw_rect(Rect2(tx - 6.0, ay - 15.0, 3.0, 30.0), _fa(C, a))
	UI.text(self, font, Vector2(tx + 2.0, ay + fs * 0.36), tip, fs, _fa(Color(0.914, 0.941, 0.953), a))
	var d: Rect2 = item_rects[0] if item_rects.size() > 0 else Rect2()
	if d.size.x > 0.0:
		var lock := "完成新手寻访后开放"
		var lw: float = font.get_string_size(lock, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var ly: float = d.position.y - 8.0 if menu_lay.compact else d.end.y + 16.0   # 紧凑版式集结出发贴底：提示写在上方
		UI.text(self, font, Vector2(d.get_center().x - lw / 2.0, ly), lock, 12, _fa(Color(0.635, 0.725, 0.784), _item_a(0)))


## Logo 层（logo_ci 的 draw）：难度页、选人页不画
func _draw_logo_layer() -> void:
	if (diff_pick or op_pick) or menu_lay.is_empty():
		return
	var ft := FR.tic()
	var a := _seg(1.0, 0.5)
	if guide or credits:
		a *= 0.25
	Tiles._draw_logo(logo_ci, menu_lay.logo.o, menu_lay.logo.k, font, a, tex_logo)
	FR.toc("logo_draw", ft)


func _draw_leaving(vs: Vector2) -> void:
	if leaving >= 0.0:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.01, 0.02, clamp(leaving / 0.6, 0.0, 1.0)))


## 开局干员（选人 / --op；测试的 --squad 一并）JSON 里写到的帧条名（"tex" / "strip"）：出发后的等待里先读进 A.tex 缓存
var _op_warm_begun := false
var _game_warm: Node   # 载入页里的着色器预热视口（光学粒子）
var _wl_pending := false   # 对局贴图名单还没取（等 game.gd 编译完）
## 载入页每帧预读预算（读图 + 注册音频合计）：原来 24 + 12 毫秒，载入页动画只有 20–25 帧；10-25「帧率稳定优先」压到 12 毫秒（加一帧渲染不超 16.7），
## 总读取时间约长两成（单张超预算的照样一帧读一张）
const LOAD_BUDGET_USEC := 12000
var _op_warm_more := false
var loading: Control   # 进局载入页（screens/loading_screen.gd，CanvasLayer 80）
var _grow_strips: Array = []

var _op_scripts: Array = []   # 后台编译中的干员脚本路径


func _op_fx_names() -> Array:
	var ids := _op_ids()
	var out: Array = []
	for cid in ids:
		if Character.exists(cid):
			_collect_tex(Character.load_def(cid), out)
	return out


## 开局干员 id（选人 / --op；测试的 --squad 一并）
func _op_ids() -> Array:
	var ids: Array = [Cfg.character_id]
	for a in Cfg.dev_args():
		if a.begins_with("--op="):
			ids = [a.substr(5)]
	for a in Cfg.dev_args():
		if a.begins_with("--squad="):
			ids.append_array(a.substr(8).split(","))
	return ids.filter(func(c): return Character.exists(str(c)))


func _collect_tex(x, out: Array, key := "") -> void:
	if x is Dictionary:
		if x.get("strip", "") is String and str(x.get("ease", "")) != "" and not _grow_strips.has(x.strip):
			_grow_strips.append(x.strip)   # 扩散缓动的帧条（ob_fx.fx_draw_grow）：首用时要逐像素量每帧半径，预热里先算
		for k in x:
			_collect_tex(x[k], out, str(k))
	elif x is Array:
		for v in x:
			_collect_tex(v, out, key)
	elif x is String and (key == "tex" or key == "strip") and x != "" and not out.has(x):
		out.append(x)


## 载入页进度：法线图预热 + 贴图分帧预读 + 音频样本注册，按条数合计（三者都是单调的，合计也不会倒退）
func _loading_progress() -> void:
	var nm := A.prewarm_progress()
	var tx := A.warm_progress()
	var au: Vector2i = Sfx.warm_progress()
	var done := nm.x + tx.x + au.x
	var total := nm.y + tx.y + au.y
	var what := "展开战场"
	var n := Vector2i.ZERO
	if A.prewarm_busy():
		what = "准备光照贴图"
		n = nm
	elif _op_warm_more:
		what = "读取干员与海嗣资料"   # 10-31 TA L8：原「帧条」是开发口吻
		n = tx
	elif Sfx.warm_busy():
		what = "准备作战音频"
		n = au
	loading.set_progress(float(done) / float(total) if total > 0 else 1.0, what, n)


## 本作徽记（菱形 + 一道浪）：标题页小标与主按钮用（不用原作的集成战略标志）
func _draw_emblem(c: Vector2, r: float, col: Color) -> void:
	draw_polyline(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0), c + Vector2(0, -r)]), col, 1.4)
	var w := PackedVector2Array()
	for k in 13:
		var u := k / 12.0
		w.append(c + Vector2(-r * 0.55 + u * r * 1.1, sin(u * TAU) * r * 0.16 + r * 0.06))
	draw_polyline(w, col, 1.4)


## 操作说明页的触屏版（触屏验收 10-01）
## 操作说明（10-22 用户：每条一行，只写键位 + 动作；页面换寻访 hh_style 模板）：[动作, 键鼠, 手柄]；触屏只用前两列
const GUIDE_ROWS := [
	["移动", "WASD / 方向键", "左摇杆"],
	["冲刺", "空格", "Ⓑ / RB"],
	["队长技能", "Q / E", "Ⓐ / Ⓨ"],
	["指挥圆盘", "F（按住选，松开确认）", "LB"],
	["手动普攻", "左键 / J", "Ⓧ / RT"],
	["瞄准", "鼠标", "右摇杆"],
	["选卡", "数字键 / 点击", "Ⓐ"],
	["暂停", "Esc", "START"],
	["属性", "Tab / C", "SELECT"],
	["重看指南", "暂停时 G", "暂停菜单"],
	["倍速", "V", ""],
	["音乐开关", "M", ""],
	["重来 / 回标题", "R / T", ""],
]
const TOUCH_GUIDE := [
	["移动", "左半屏拖动"],
	["冲刺", "冲刺键"],
	["队长技能", "技能键 · 按住拖动瞄准"],
	["手动普攻", "攻击键 · 按住拖动瞄准"],
	["指挥圆盘", "指挥键 · 点选"],
	["选卡", "点卡片"],
	["暂停 / 属性", "暂停键 / 属性键"],
	["重看指南", "暂停菜单 · 指南"],
]


## 寻访同款版式：暗场 + 左侧浅灰斜切栏（大号中文 + 像素描边英文）+ 右侧键位表 + 底栏返回
func _draw_guide(vs: Vector2) -> void:
	HS.backdrop(self, vs)
	var wt: float = clampf(vs.x * 0.3, 300.0, 420.0)
	HS.left_panel(self, vs, wt, wt - 70.0, 0.0)
	HS.title_block(self, font, Vector2(48, vs.y * 0.2), "01", "操 作", "操作说明", "GUIDE", 1.0, 64)
	HS.hr_mark(self, font, Vector2(48, vs.y - 120), 1.0, HS.INK2, ["RHODES ISLAND", "OPERATION", "MANUAL"])
	var touch: bool = Pad.touch_ui()
	var rows: Array = TOUCH_GUIDE if touch else GUIDE_ROWS
	var x0: float = wt + 60.0
	var x1: float = vs.x - 48.0
	var top: float = maxf(40.0, vs.y / 2.0 - rows.size() * 22.0 - 30.0)
	var step: float = minf(44.0, (vs.y - top - 110.0) / rows.size())
	var kx: float = x0 + 200.0
	var px: float = x0 + 200.0 + (x1 - x0 - 200.0) * 0.5
	HS.spaced(self, font, Vector2(x0, top), "ACTION", 10, HS.MUTE, 3.0)
	HS.spaced(self, font, Vector2(kx, top), "触屏" if touch else "键鼠", 12, HS.MUTE, 3.0)
	if not touch:
		HS.spaced(self, font, Vector2(px, top), "手柄", 12, HS.MUTE, 3.0)
	for i in rows.size():
		var y: float = top + 22.0 + i * step
		draw_line(Vector2(x0, y + step - 6.0), Vector2(x1, y + step - 6.0), Color(1, 1, 1, 0.08), 1.0)
		UI.diamond(self, Vector2(x0 + 4, y + step / 2.0 - 3.0), 3.5, HS.CYB)
		UI.text_at(self, font, Vector2(x0 + 18, y + step / 2.0 - 3.0), rows[i][0], 19, UI.TEXT, "lm", true)
		UI.text_at(self, font, Vector2(kx, y + step / 2.0 - 3.0), rows[i][1], 18, HS.CYB, "lm")
		if not touch and rows[i][2] != "":
			UI.text_at(self, font, Vector2(px, y + step / 2.0 - 3.0), rows[i][2], 18, Color8(200, 210, 222), "lm")
	HS.bottom_bar(self, vs, 52.0)
	UI.text_at(self, font, Vector2(x0, vs.y - 26.0), "编队、灯火、溟痕、指挥、藏品、商人：见开局指南", 14, HS.MUTE, "lm")
	HS.ghost_btn(self, font, Rect2(vs.x - 196, vs.y - 44, 168, 36), "返回", Pad.hint("Esc", "Ⓑ", ""))


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


## 10-22 用户：换寻访 hh_style 模板——暗场 + 左侧浅灰斜切栏（大号中文 + 像素描边英文），右侧正文（滚动逻辑不变）
func _draw_credits(vs: Vector2) -> void:
	HS.backdrop(self, vs)
	var wt: float = clampf(vs.x * 0.3, 300.0, 420.0)
	HS.left_panel(self, vs, wt, wt - 70.0, 0.0)
	var title: String = credits_data.get("title", "致谢与声明")
	HS.title_block(self, font, Vector2(48, vs.y * 0.2), "02", "致 谢", title, "CREDITS", 1.0, 56)
	HS.hr_mark(self, font, Vector2(48, vs.y - 120), 1.0, HS.INK2, ["ARKNIGHTS", "FAN GAME", "NON-COMMERCIAL"])
	var secs: Array = credits_data.get("sections", [])
	var touch: bool = Pad.touch_ui()
	var px0: float = wt + 24.0
	var pw: float = minf(CREDITS_W, vs.x - px0 - (12.0 if touch else 24.0))
	var tx: float = CREDITS_LX + CREDITS_LW + 18.0
	var tw: float = pw - tx - 56.0   # 右边留滚动条
	if tw != cr_lay_w or cr_lay.is_empty():
		cr_lay = _credits_layout(secs, CREDITS_FS, tw)
		cr_lay_w = tw
	var h: float = vs.y
	var r := Rect2(roundf(px0), 0.0, pw, h)
	cr_panel = Rect2(Vector2.ZERO, vs)   # 整屏都算面板：只有「返回」/ 按键关
	HS.spaced(self, font, r.position + Vector2(36, 44), credits_data.get("en", "CREDITS"), 11, HS.MUTE, 3.0)
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
	HS.ghost_btn(self, font, cr_back, "返回", Pad.hint("Esc", "Ⓑ", ""))
	if back_hot:
		HS.para(self, cr_back, Color(1, 1, 1, 0.12))
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
			UI.diamond(cr_view, Vector2(ox + 44, y + 12), 4.0, HS.CYB)
			UI.draw_fit(cr_view, font, Vector2(ox + CREDITS_LX, y), row.label, HS.CYB)
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
		cr_view.draw_rect(Rect2(0, yy, w, hh + 0.5), Color(HS.DARK, a))


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


## 寻访入口：有凭证且还有没招募的干员才能进（没有就灰显，不隐藏）
func _hunt_ready() -> bool:
	const R = preload("res://scripts/core/roster.gd")
	return R.active() and R.tickets() >= R.COST_RANDOM and not R.locked_ids().is_empty()
