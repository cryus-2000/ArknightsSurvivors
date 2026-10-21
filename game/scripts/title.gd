extends Control
## 标题界面：「方舟幸存者」Logo + 地图副标题 + 菜单；背景按地图（现为蓝眼泪银河沙滩 title_bg.gd，博士与水月站在浪边）

const UI = preload("res://scripts/ui.gd")
const Affects = preload("res://scripts/run/affects.gd")
const A = preload("res://scripts/art.gd")
const D = preload("res://scripts/data.gd")
const Character = preload("res://scripts/characters/character.gd")
const Roster = preload("res://scripts/core/roster.gd")   # 干员解锁（docs/109 §12）：选人页只列已解锁的干员（选封面干员时列全部）
const Game = preload("res://scripts/game.gd")
const InitialStats = preload("res://scripts/screens/initial_stats.gd")
const TUI = preload("res://scripts/screens/tide_ui.gd")
const Tiles = preload("res://scripts/screens/title_tiles.gd")
## 选人页的职业顺序（docs/23 §11.1）
const CLASS_ORDER := ["先锋", "近卫", "重装", "狙击", "术师", "医疗", "辅助", "特种"]

## 菜单项（T5s 磁贴群，docs/67 §12）：0 集结出发 / 1 图鉴 / 2 Boss 演练 / 3 操作说明 / 4 设置 / 5 退出；文字与图标在 screens/title_tiles.gd
const ITEMS := [
	{"cn": "集结出发", "en": "DEPLOY"},
	{"cn": "图鉴", "en": "GALLERY"},
	{"cn": "Boss 演练", "en": "BOSS TRIAL"},
	{"cn": "操作说明", "en": "GUIDE"},
	{"cn": "设置", "en": "SETTINGS"},
	{"cn": "退出", "en": "EXIT"},
	{"cn": "认知塑造", "en": "SHAPING"},
]

var font: Font
var tex_player: Texture2D
var tex_light: Texture2D
var tex_tiles: Texture2D
var tex_bg: Texture2D
var tex_logo: Texture2D
var player_frames := 1
var t := 0.0
var sel := 0
var item_rects: Array = []
var menu_lay := {}            # 磁贴群排版（title_tiles.layout，_draw 里按当前尺寸算）
var menu_boss := true         # 有没有「Boss 演练」（_ready 按 Cfg.can_boss_trial()；测试可改）
var menu_exit := true         # 有没有「退出」（网页 / --simweb 没有；测试可改）
var menu_water := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]   # 各磁贴水位 0–1（选中涨潮、离开退潮，T2）
var menu_rip_t := -10.0       # 选中变化的时刻（标题页时间 t）：涟漪扩散
var menu_mem_x := -1.0        # 二维导航记住的列（磁贴中心 x）
var cover_hover := false
var branches: Array = []   # [a, b, width, depth]
var nodes: Array = []      # 发光节点 [pos, phase]
var motes: Array = []
var guide := false
var credits := false
var credits_rect := Rect2()
var deploy_rect := Rect2()   # 右下「更换封面干员」
var credits_data: Dictionary = {}
var cr_scroll := 0.0         # 致谢与声明：正文滚动（目标，像素）
var cr_scroll_f := 0.0       # 显示用，逐帧逼近（拖动时相等）
var cr_max := 0.0            # 可滚动的最大量（排版时算）
var cr_view: Control         # 正文裁剪子控件：条目画在它里面，按 cr_scroll_f 平移
var cr_vr := Rect2()         # 正文可视区（标题页坐标）
var cr_bar := Rect2()        # 滚动条轨道（命中区左右各放宽）
var cr_back := Rect2()       # 钉在底部的「返回」按钮
var cr_panel := Rect2()
var cr_lay: Dictionary = {}  # 排版缓存（按正文列宽）
var cr_lay_w := -1.0
var cr_drag := 0             # 0 没按 / 1 按在正文（拖动滚动）/ 2 按在滚动条
var cr_moved := false        # 本次按下已拖过 CR_SLOP
var cr_vel := 0.0            # 松手惯性（像素 / 秒）
var cr_press := Vector2.ZERO
var leaving := -1.0
var auto_go := false        # --autotest 开窗口：等法线预热完再进局
var wait_t := 0.0           # 出发后等预热的时间（载入中…）
var settings: Control
var gallery: Control
var boss_trial: Control
var meta_ui: Control             # 认知塑造页（局外成长 P2，docs/109 §4）
var transition: Control
var overlay_was_open := false
var cover_pick := false
var diff_pick := false
var diff_sel := 0
var diff_rects := {}
## 选开局干员（docs/23 §14 P4）：开始探索 → 选人 → 选难度；B+ 版式的其余状态在文件后部「选开局干员」一节
var op_pick := false
var op_sel := 0
var op_defs: Array = []        # [{id, def, tex, frames, lore, numbers, name, en, cls, col, vals, …}]
var op_lore: Dictionary = {}
## 开场动画：从黑暗中浮出海滩 → 标题浮现 → 菜单依次滑入；任意按键 / 点击跳过
## 标题开场（2026-09-27 用户选方案 A「潮声点灯」，要求节奏快一点，约 5 秒）：
## 0–1.2 黑场里沙滩上一粒蓝眼泪亮起、荡开涟漪；0.5 起黑幕退去、上下黑边收起，镜头从高处整像素下摇到海滩（不再非整数放大）；
## 1.6–2.5 发光脚印一枚枚亮到博士脚边，2.4 远方海嗣齐齐睁眼一瞬；2.6–3.2 青色扫光从左往右「刷」出 Logo；3.0 起副标题、菜单、页脚依次滑入。
## 第一次完整播放；看过以后（Cfg.opening_seen 写入存档）从 INTRO_SHORT 起播简短版；对局返回标题不播；任意键 / 点击 / 触屏跳过
const INTRO_LEN := 4.8
const INTRO_SHORT := 2.5
var intro := 0.0
var title_bg: Control
var map_title := ""        # 地图副标题（data/maps/<id>.json 的 title / title_en）
var map_title_en := ""


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
		Cfg.diff_unlocked = D.DIFFICULTY_TIERS.size() - 1   # 只改内存（测试模式不写存档），录到能出发的档
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
			Cfg.diff_unlocked = clampi(int(dp[1]) if dp.size() > 1 else 0, 0, D.DIFFICULTY_TIERS.size() - 1)
			diff_pick = true
			diff_sel = clampi(int(dp[0]), 0, D.DIFFICULTY_TIERS.size() - 1)
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


func _prewarm() -> void:
	A.normal_maps = Cfg.normal_maps and DisplayServer.get_name() != "headless"
	A.prewarm_start(Game.preload_tex_names())


func _exit_tree() -> void:
	A.prewarm_join()


func _diff_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match Pad.kc(event):
			# 潮位尺是竖的：↑ 涨潮（更高档）/ ↓ 退潮；← → 保留（旧习惯与手柄横推）
			KEY_UP, KEY_W, KEY_RIGHT, KEY_D:
				_diff_step(1)
			KEY_DOWN, KEY_S, KEY_LEFT, KEY_A:
				_diff_step(-1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_diff_go()
			KEY_ESCAPE, KEY_BACKSPACE:
				_diff_back()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = make_input_local(event).position
		for k in diff_rects:
			if diff_rects[k].has_point(p):
				match k:
					"go":
						_diff_go()
					"back":
						_diff_back()
					_:
						if str(k).begins_with("tier"):
							_diff_step(int(str(k).substr(4)) - diff_sel)
				return


func _diff_back() -> void:
	transition.switch_page(func():
		diff_pick = false
		_op_reenter())
	Sfx.play("ui_move")


func _diff_step(d: int) -> void:
	# 未解锁的档也能翻过去看效果，只是不能出发（_diff_go）
	var n := clampi(diff_sel + d, 0, D.DIFFICULTY_TIERS.size() - 1)
	if n != diff_sel:
		_diff_level_to(n, absi(n - diff_sel))
		diff_sel = n
		Sfx.play("ui_move")


func _diff_go() -> void:
	if transition.busy:
		return
	if diff_sel > Cfg.diff_unlocked:
		Sfx.play("ui_move", -4.0, 0.6)
		return
	Cfg.difficulty = diff_sel
	Cfg.save()
	diff_pick = false
	_prewarm()
	Sfx.play("start", -8.0)   # 音量巡检（2026-09-27）：原 0 dB 比标题曲响 18 dB，且开场一开始还会再播一次
	leaving = 0.0


## 难度页（T5s，docs/67 §12）：左边竖的潮位尺就是选档器（三档卡贴在刻度上，尺内水位停在所选档；↑↓ 换档 = 水位升降，
## docs/62 §3.3「潮位上涨」out_back(1.2)，跨两档 0.6 秒），右边「档位文件」列修正项，下面 出发 / 返回。
## 选中档 = 反白 + 细青边（与标题选中块同一处理）；档名用 DIFFICULTY_TIERS 的真实名字，Ⅳ / Ⅷ 换成像素字 IV / VIII（ui.ttf 没有 Ⅷ）。
var diff_lv_from := -1.0      # 水位动画：起点 / 终点（0 = 尺底，1 = 尺顶；按档位刻度换算）、开始时刻、时长
var diff_lv_to := -1.0
var diff_lv_t0 := -10.0
var diff_lv_dur := 0.38
var diff_was := false         # 上一帧难度页是否开着（打开那一帧水位从尺底涨上来）
var diff_mod_t := -10.0       # 换档时修正项淡入（T2）
const DIFF_PAD := 0.15        # 三档刻度离尺两端的留白（占尺高）
var _mod_re: RegEx


func _diff_frac(i: int) -> float:
	return DIFF_PAD + (1.0 - DIFF_PAD * 2.0) * float(i) / float(maxi(1, D.DIFFICULTY_TIERS.size() - 1))


func _diff_level_to(n: int, steps: int) -> void:
	diff_lv_from = _diff_level_now()
	diff_lv_to = _diff_frac(n)
	diff_lv_t0 = t
	diff_lv_dur = 0.6 if steps > 1 else 0.38
	diff_mod_t = t


func _diff_level_now() -> float:
	if diff_lv_to < 0.0:
		return _diff_frac(diff_sel)
	if Cfg.reduce_motion or diff_lv_dur <= 0.0:
		return diff_lv_to
	var x := clampf((t - diff_lv_t0) / diff_lv_dur, 0.0, 1.0)
	var e := 1.0 + 2.2 * pow(x - 1.0, 3.0) + 1.2 * pow(x - 1.0, 2.0)   # out_back(1.2)
	return lerpf(diff_lv_from, diff_lv_to, e)


func _diff_layout(vs: Vector2, ph: bool) -> Dictionary:
	var L := {}
	if not ph:
		L.gauge = Rect2(40, 112, 92, vs.y - 192)
		L.card_x = 156.0
		L.card_w = 400.0
		L.card_h = 88.0
		L.panel = Rect2(612, 100, vs.x - 28 - 612, vs.y - 220)
		L.go = Rect2(612, vs.y - 100, 300, 60)
		L.back = Rect2(932, vs.y - 92, 150, 44)
	else:
		L.gauge = Rect2(20, 64, 64, vs.y - 80)
		L.card_x = 100.0
		L.card_w = 300.0
		L.card_h = 74.0
		L.panel = Rect2(420, 56, vs.x - 16 - 420, vs.y - 56 - 76)
		L.go = Rect2(420, vs.y - 64, 260, 52)
		L.back = Rect2(696, vs.y - 60, 150, 44)
	var g: Rect2 = L.gauge
	L.cards = []
	for i in D.DIFFICULTY_TIERS.size():
		var cy: float = g.end.y - g.size.y * _diff_frac(i)
		L.cards.append(Rect2(L.card_x, cy - L.card_h / 2.0, L.card_w, L.card_h))
	return L


func _draw_diff(vs: Vector2) -> void:
	if not diff_was:
		# 打开难度页：水位从尺底涨到所选档（docs/62 §3.3）
		diff_was = true
		diff_lv_from = 0.0
		diff_lv_to = _diff_frac(diff_sel)
		diff_lv_t0 = t
		diff_lv_dur = 0.6
		diff_mod_t = t
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.008, 0.024, 0.063, 0.5))
	var ph: bool = vs.y < 520.0 or Cfg.phone_ui()   # 界面高度小或手机横屏：手机接手柄时（Pad.using）也得用紧凑版式，否则按钮出界
	var touch := Pad.touch_ui()
	var c := TUI.ctx(self)
	var L := _diff_layout(vs, ph)
	var ps := TUI.cell(c, 2.0 if not ph else 1.4)
	var k1 := 1.0 if not ph else 1.4   # 小号像素字：手机按屏幕至少 2 像素一格
	var hx := 28.0 if not ph else 20.0
	# 顶栏
	TUI.ptext(self, c, Vector2(hx, 34 if not ph else 18), "OPERATION // DIFFICULTY", k1, TUI.CY)
	var hs := 26 if not ph else 22
	UI.text(self, font, Vector2(hx, (62 if not ph else 40) + hs * 0.36), "选择难度", hs, TUI.TXT)
	var hw: float = font.get_string_size("选择难度", HORIZONTAL_ALIGNMENT_LEFT, -1, hs).x
	TUI.ptext(self, c, Vector2(hx + hw + 16, (64 if not ph else 42)), "TIDE LEVEL", 2.0 if not ph else 1.4, TUI.TXT2, 2)
	diff_rects.clear()
	# 潮位尺：抖动藏青竖条 + 水 + 刻度 + 涟漪
	var gg := TUI.grid(c, L.gauge, ps)
	TUI.panel(self, gg, 3)
	var lv := _diff_level_now()
	var base := int(round(gg.ch - 1 - (gg.ch - 2) * lv))
	TUI.water_rows(self, gg, 3, base, gg.ch + 6, 0.0 if Cfg.reduce_motion else t * 1.2, "edge_rest")
	var cl: float = gg.cl
	var yy := 8
	while yy < gg.ch - 4:
		var long := yy % 16 == 0
		draw_rect(Rect2(gg.pos + Vector2(3, yy) * cl, Vector2(7 if long else 3, 1) * cl), TUI.CY_DIM)
		yy += 4
	var rip := clampf((t - diff_lv_t0 - diff_lv_dur * 0.6) / 0.6, 0.0, 1.0) if not Cfg.reduce_motion else 1.0
	TUI.ripple(self, gg, 3, gg.rect.get_center().x, base, gg.rect.size.x * 0.42, 1.0 - pow(1.0 - rip, 3.0))
	if not ph:
		TUI.ptext(self, c, Vector2(gg.rect.get_center().x, gg.rect.end.y + 16), "TIDE", k1, TUI.TXT2, 1, 1)
	# 三档卡（刻度旁）
	for i in D.DIFFICULTY_TIERS.size():
		var tdef: Dictionary = D.DIFFICULTY_TIERS[i]
		var on := i == diff_sel
		var locked := i > Cfg.diff_unlocked
		var r: Rect2 = L.cards[i]
		diff_rects["tier%d" % i] = r
		var g := TUI.grid(c, r, ps)
		var cy := r.get_center().y
		if on:
			TUI.halo(self, g, 3)
			# 指针：从尺的右缘指到卡片
			var px0: float = gg.rect.end.x + 2.0
			var px1: float = g.rect.position.x - 4.0
			draw_colored_polygon(PackedVector2Array([Vector2(px0, cy), Vector2(px1, cy - 8), Vector2(px1, cy + 8)]), TUI.SEL_EDGE)
		else:
			draw_rect(Rect2(gg.rect.end.x + 4.0, cy - 1.0, g.rect.position.x - gg.rect.end.x - 10.0, 2.0), TUI.CY_DIM)
		TUI.tile(self, g, 3, on)
		var ink := TUI.SEL_INK if on else TUI.TXT
		var sub := TUI.SEL_SUB if on else TUI.TXT2
		var num_c := TUI.SEL_IDX if on else ink
		if locked and not on:
			ink = TUI.TXT2
			num_c = TUI.TXT2
		var x0: float = g.rect.position.x
		var y0: float = g.rect.position.y
		var parts: PackedStringArray = str(tdef.name).split("·")
		var nm: String = parts[0].strip_edges()
		var num: String = TUI.roman_ascii(parts[1].strip_edges()) if parts.size() > 1 else "0"
		var kbig := 4.0 if not ph else 3.0
		TUI.ptext(self, c, Vector2(x0 + (22 if not ph else 14), cy), num, kbig, num_c)
		var tx0 := x0 + (140.0 if not ph else 104.0)
		var ns := 22 if not ph else 19
		UI.text(self, font, Vector2(tx0, y0 + (30 if not ph else 24) + ns * 0.36), nm, ns, ink)
		var nw: float = font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, ns).x
		if num != "0":
			TUI.ptext(self, c, Vector2(tx0 + nw + 10, y0 + (30 if not ph else 24)), num, 2.0 if not ph else 1.4, ink)
		TUI.ptext(self, c, Vector2(tx0 + 2, y0 + (54 if not ph else 44)), TUI.roman_ascii(str(tdef.en)), k1, ink, 2)
		var desc: String = str(tdef.get("desc", ""))
		if locked and i > 0:
			desc = "通关「%s」后解锁" % TUI.roman_ascii(str(D.DIFFICULTY_TIERS[i - 1].name))
		UI.text_fit(self, font, Vector2(tx0, y0 + (72 if not ph else 60) + 5), desc, 13, sub, g.rect.end.x - tx0 - 10, 11)
		TUI.ptext(self, c, Vector2(g.rect.end.x - 14, y0 + 16), "LV %d" % int(tdef.get("level", 0)), k1, sub, 1, 2)
	# 右：档位文件（修正项）
	var pr: Rect2 = L.panel
	var pg := TUI.grid(c, pr, ps)
	TUI.panel(self, pg, 3, 0.93)
	var pp: Vector2 = pg.rect.position
	var tdef2: Dictionary = D.DIFFICULTY_TIERS[diff_sel]
	var locked2 := diff_sel > Cfg.diff_unlocked
	var ma := clampf((t - diff_mod_t) / (0.12 if Cfg.reduce_motion else 0.22), 0.0, 1.0)
	TUI.ptext(self, c, pp + Vector2(24 if not ph else 16, 24 if not ph else 18), "TIER FILE // MODIFIERS", k1, TUI.CY)
	var lines: Array = D.dmod_lines(D.dmod_for_tier(diff_sel))
	var head: String = str(tdef2.get("desc", ""))
	if locked2:
		head = "通关「%s」后解锁 · 可以先看效果" % TUI.roman_ascii(str(D.DIFFICULTY_TIERS[diff_sel - 1].name))
	var hs2 := 18 if not ph else 16
	UI.text_fit(self, font, pp + Vector2(24 if not ph else 16, (54 if not ph else 42) + hs2 * 0.36), head, hs2, _fa(TUI.TXT, ma), pg.rect.size.x - 48, 12)
	var gx := pp.x + (24.0 if not ph else 16.0)
	var gy := pp.y + (84.0 if not ph else 64.0)
	var gw: float = pg.rect.size.x - (48.0 if not ph else 32.0)
	var gh: float = pg.rect.end.y - (20.0 if not ph else 14.0) - gy
	if lines.is_empty():
		UI.text(self, font, Vector2(gx, gy + 24), "没有额外修正。", 15, _fa(TUI.TXT2, ma))
	else:
		if _mod_re == null:
			_mod_re = RegEx.new()
			_mod_re.compile("^(.+?)\\s+([+\\-]?\\d+%|\\d+:\\d\\d)$")
		var per := ceili(lines.size() / 2.0)
		var colw := (gw - 16.0) / 2.0
		var rh := minf(80.0, gh / per)
		var chh := rh - (12.0 if not ph else 8.0)
		for k in lines.size():
			var col := k / per
			var row := k % per
			var cr := Rect2(gx + col * (colw + 16.0), gy + row * rh, colw, chh)
			var cg := TUI.grid(c, cr, ps)
			TUI.panel(self, cg, 2, 0.85 * ma)
			var cp: Vector2 = cg.rect.position
			var ln: String = lines[k]
			var lab := ln
			var val := ""
			var m := _mod_re.search(ln)
			if m != null:
				lab = m.get_string(1)
				val = m.get_string(2)
			var tc := TUI.TXT2 if locked2 else TUI.TXT
			var big := chh >= 52.0
			if big:
				TUI.ptext(self, c, cp + Vector2(14, 16), "MOD %02d" % (k + 1), k1, _fa(TUI.CY_DIM, ma))
			var vw := 0.0
			if val != "":
				vw = TUI.ptext(self, c, Vector2(cg.rect.end.x - 14, cg.rect.get_center().y + (6 if big else 0)), val, 2.0 if not ph else 1.4, _fa(tc, ma), 1, 2)
			var ls := 15 if not ph else 14
			UI.text_fit(self, font, Vector2(cp.x + 14, cg.rect.get_center().y + (8 if big else 0) + ls * 0.36), lab, ls, _fa(tc, ma), cg.rect.size.x - 28 - vw - 10, 11)
	# 出发 / 返回
	var mp := get_local_mouse_position()
	var gog := TUI.grid(c, L.go, ps)
	diff_rects["go"] = gog.rect
	TUI.panel(self, gog, 3)
	var go_h: bool = gog.rect.has_point(mp) and not touch
	var gcy: float = gog.rect.get_center().y
	if locked2:
		TUI.outline(self, gog, 3, TUI.EDGE)
		UI.text(self, font, Vector2(gog.rect.position.x + 72, gcy + 22 * 0.36), "未解锁", 22, TUI.TXT2)
	else:
		TUI.outline(self, gog, 3, TUI.FOAM if go_h else TUI.SEL_EDGE)
		TUI.icon(self, c, "deploy", Vector2(gog.rect.position.x + 36, gcy), 2.0 if not ph else 1.5, TUI.SEL_EDGE, TUI.FOAM)
		UI.text(self, font, Vector2(gog.rect.position.x + 72, gcy + 24 * 0.36), "出发", 24, TUI.TXT)
	if not touch:
		TUI.ptext(self, c, Vector2(gog.rect.end.x - 16, gcy), Pad.hint("ENTER", "PAD A", ""), k1, TUI.TXT2, 1, 2)
	var bg := TUI.grid(c, L.back, ps)
	diff_rects["back"] = bg.rect
	TUI.panel(self, bg, 2)
	if bg.rect.has_point(mp) and not touch:
		TUI.outline(self, bg, 2, TUI.CY)
	var bcy: float = bg.rect.get_center().y
	UI.text(self, font, Vector2(bg.rect.position.x + 20, bcy + 15 * 0.36), "返回", 15, TUI.TXT)
	if not touch:
		TUI.ptext(self, c, Vector2(bg.rect.end.x - 14, bcy), Pad.hint("ESC", "PAD B", ""), k1, TUI.TXT2, 1, 2)
		TUI.ptext(self, c, Vector2(vs.x - 28, vs.y - 20), Pad.hint("↑↓ CHANGE TIDE", "D-PAD CHANGE TIDE", ""), k1, TUI.TXT2, 1, 2)


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
	var overlay_open: bool = settings.visible or gallery.visible or boss_trial.visible or meta_ui.visible
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
	if leaving >= 0.0 or transition.busy or settings.visible or gallery.visible or boss_trial.visible or meta_ui.visible:
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


func _menu_ids() -> Array:
	var ids: Array = [0, 1, 2, 6, 3, 4, 5]
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


func _fa(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)


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


func _shot_dir() -> String:
	for a in Cfg.dev_args():
		if a.begins_with("--shotdir="):
			return a.substr(10)
	return "/tmp/claude-0"


# =====================================================================
# 选开局干员（B+，docs/58 §11，用户 10-11 定稿）：水月底 + 职业色斜带 + 巨型描边英文名 + 微型代码；
# 左职业轨、底部横向名册（触屏：左侧两列竖滚）、待机帧整数倍放大当立绘、右侧 属性 / 技能 / 编队 页签、编队条、青色出击 + 深海浪幕转场。
# 名册来自 data/characters/*.json（recruitable），新干员自动出现。排版按两张设计稿画：桌面 1280×720、触屏 740×360（概念图同尺寸），
# 再整体缩放进当前界面（op_k / op_off）；命中区都记在设计坐标里。
# 动效全是界面层：用标题页自己的真实时间 t（不是 g.t）、不碰任何随机数；「减少动态效果」（Cfg.reduce_motion）开启时
# 位移 / 缩放 / 扫入 / 浪幕直接到终态，只留 ≤ 120 ms 淡入淡出（OP_FADE），呼吸光不动
# =====================================================================
const OP_TABS := ["属性", "技能", "编队"]
const OP_TAB_EN := ["STATUS", "SKILL", "SQUAD"]
const OP_STAGE := ["招募", "精英一", "精英二"]
const OP_FADE := 0.12
## 立绘倍数（相对 @2x 像素的整数倍，最近邻）：桌面设计稿用它，手机按 0.6 倍；原定稿 5（10-11 用户：「干员大小可以缩小点」→ 4）。
## 描边英文名、外晕、脚底位置都按它和 5 的比例联动；--opartk=<k> 截图时临时覆盖（比较方案用）
const OP_ART_K := 4.0
var op_art_k := OP_ART_K
const OP_DESK := Vector2(1280, 720)
const OP_PHONE := Vector2(740, 360)
var op_filter := ""              # 职业筛选（"" = 全部）
var op_tab := 1                  # 信息页签：0 属性 / 1 技能 / 2 编队
var op_skill := 2                # 技能页展开说明的那一行
var op_rects := {}               # 命中区（设计坐标）：卡 = op_defs 下标（int），其余 "go" / "back" / "cls:<职业>" / "more_l" / "more_r"
var op_prects := {}              # 信息面板里的命中区："tab0".. / "sk0"..（面板子控件画的时候填）
var op_k := 1.0                  # 界面坐标 = op_off + 设计坐标 × op_k
var op_off := Vector2.ZERO
var op_vis := 10                 # 桌面名册一屏几张
var op_scroll := 0.0             # 名册滚动（设计像素，目标）
var op_scroll_f := 0.0           # 显示用，逐帧逼近（拖动时相等）
var op_drag_on := false          # 触屏：在名册里按下（松手时没拖动才算点选）
var op_dragging := false
var op_press_pos := Vector2.ZERO
var op_last_pos := Vector2.ZERO
var op_hover := {}               # 卡下标 → 悬停 0–1
var op_max := {}                 # 属性页量条的满值（全体干员各项上限）
var op_sw_t := -10.0             # 换干员的时刻（标题页时间 t）
var op_prev_sel := -1            # 换干员前的选中（旧卡落回 / 旧色带）
var op_open_t := -10.0           # 打开选人页（面板从右滑入）
var op_tab_t := -10.0
var op_tab_from := 1
var op_press_t := -1.0           # 按下出击
var op_wipe_t := -1.0            # 浪幕开始
var op_wipe_swapped := false
var op_go_id := ""
var op_panel: Control            # 右侧信息面板（打开时整体滑入）
var op_body: Control             # 面板正文（换干员滑入、换页签淡出）
var op_wipe_layer: Control       # 浪幕：最上层子控件，盖住选人页与难度页
var op_bg := {}                  # 背景固定几何（浪纹、触须、灯火光点；固定种子的本地 RNG，只算一次）
var op_glow_tex: Texture2D
var op_motion := -1.0            # --opmotion：动效录制开始时刻
var codex_motion := -1           # --codexmotion：已录帧数
var glass_perf := -1             # --glassperf：已跑帧数
var glass_acc := [0.0, 0.0, 0, 0, 0.0, 0.0]   # 开 / 关 累计秒数与帧数、GPU 渲染毫秒
var post_fx: CanvasLayer


func _op_layers() -> void:
	op_panel = Control.new()
	op_body = Control.new()
	op_wipe_layer = Control.new()
	for c in [op_panel, op_body, op_wipe_layer]:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.visible = false
	add_child(op_panel)
	op_panel.add_child(op_body)
	add_child(op_wipe_layer)
	op_panel.draw.connect(_draw_op_panel)
	op_body.draw.connect(_draw_op_body)
	op_wipe_layer.draw.connect(_draw_op_wipe)
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1))
	gr.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = gr
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 128
	op_glow_tex = gt


func _open_op_pick(for_cover := false) -> void:
	cover_pick = for_cover
	if op_defs.is_empty():
		var lf := FileAccess.open("res://data/lore.json", FileAccess.READ)
		if lf != null:
			var ld = JSON.parse_string(lf.get_as_text())
			if ld is Dictionary:
				op_lore = ld
		for cid in Character.list_ids():
			var d: Dictionary = Character.load_def(cid)
			if not d.get("recruitable", true):
				continue
			var sp: Dictionary = d.get("sprites", {})
			var idle = sp.get("idle", "")
			var tn: String = idle if idle is String else idle.get("tex", "")
			var tx: Texture2D = A.tex(tn) if tn != "" else null
			var frames: int = 1
			if idle is Dictionary and idle.has("frames"):
				frames = int(idle.frames)
			elif tx != null:
				frames = max(1, tx.get_width() / tx.get_height())
			if Character.strip_mirror(d, "idle"):
				tx = A.mirror_strip(tx, frames)   # 待机条画反了（docs/84）：立绘 / 编队小像用镜像副本
			var cls: String = d.get("class", "")
			var col: Color = Character.CLASS_COL.get(cls, UI.CYAN)
			var cc = d.get("col", null)
			if cc is Array and cc.size() >= 3:
				col = Color(float(cc[0]), float(cc[1]), float(cc[2]))
			var sh: Dictionary = InitialStats.sheet(cid, d)   # 选人「属性」页与图鉴「属性」页同一张表
			var elite := 0
			for n in d.get("progression", []):
				if n is Dictionary and n.get("type", "") == "elite":
					elite += 1
			op_defs.append({"id": cid, "def": d, "tex": tx, "frames": frames, "hires": A.hires_of(tx), "ds": UI.op_scale(d), "lore": op_lore.get(cid, {}).get("lore", ""),
				"sheet": sh, "name": d.get("name", cid), "en": str(d.get("en", cid.to_upper())), "cls": cls, "col": col,
				"elite": elite if elite > 0 else 2, "melee": _op_is_melee(d),
				"vals": {"hp": InitialStats.row(sh, "hp").val, "atk": InitialStats.row(sh, "atk").val, "cd": InitialStats.row(sh, "cd").val,
					"reach": InitialStats.row(sh, "reach").val, "speed": InitialStats.row(sh, "speed").val, "dps": InitialStats.row(sh, "dps").val}})
		# 原作按稀有度排；本作没有稀有度：封面干员水月在前，其余按职业顺序（docs/58 §11 概念图同序）
		op_defs.sort_custom(func(a, b):
			var ka: int = 0 if a.id == "mizuki" else 1
			var kb: int = 0 if b.id == "mizuki" else 1
			if ka != kb:
				return ka < kb
			var ca: int = CLASS_ORDER.find(a.cls)
			var cb: int = CLASS_ORDER.find(b.cls)
			return ca < cb if ca != cb else a.id < b.id)
		for key in ["hp", "atk", "cd", "reach", "speed", "dps"]:
			var mx := 0.001
			for od in op_defs:
				mx = maxf(mx, float(od.vals[key]))
			op_max[key] = mx
	op_sel = 0
	var lst0 := _op_list()
	if not lst0.is_empty():
		op_sel = lst0[0]
	for i in lst0:
		if op_defs[i].id == (Cfg.cover_character_id if cover_pick else Cfg.character_id):
			op_sel = i
	op_filter = ""
	op_tab = 1
	op_tab_from = 1
	op_skill = _op_default_skill()
	op_hover.clear()
	op_press_t = -1.0
	op_wipe_t = -1.0
	op_scroll = 0.0
	op_pick = true
	_op_reenter()
	_op_follow(true)


## 打开 / 从难度页返回：面板滑入、色带扫入、立绘与名字重新进场
func _op_reenter() -> void:
	op_pick = true
	op_open_t = t
	op_sw_t = t
	op_tab_t = -10.0
	op_prev_sel = -1
	op_press_t = -1.0


## 技能页默认展开：有手动技能就展开它（主控的 Q），否则 S3
func _op_default_skill() -> int:
	if op_defs.is_empty():
		return 2
	var sks: Array = op_defs[op_sel].def.get("skills", [])
	for i in sks.size():
		if sks[i] is Dictionary and sks[i].get("mode", "auto") == "manual":
			return i
	return mini(2, maxi(0, sks.size() - 1))


## 触屏模式（同 touch.gd 的开启条件）：选人页用 740×360 手机版式、名册竖滑、不认悬停
func _touch_mode() -> bool:
	return Cfg.touch_device()


func _op_list() -> Array:
	var out: Array = []
	for i in op_defs.size():
		if (op_filter == "" or op_defs[i].cls == op_filter) and _op_ok(i):
			out.append(i)
	return out


## 名册里能不能选：选封面干员时全部可选；选开局干员时只有已解锁的（docs/109 §12）
func _op_ok(i: int) -> bool:
	return cover_pick or Roster.is_unlocked(op_defs[i].id)


func _op_classes() -> Array:
	var out: Array = [""]
	out.append_array(CLASS_ORDER)
	return out


func _op_class_count(c: String) -> int:
	var n := 0
	for i in op_defs.size():
		if (c == "" or op_defs[i].cls == c) and _op_ok(i):
			n += 1
	return n


## 界面坐标 → 设计坐标
func _op_design(p: Vector2) -> Vector2:
	return (p - op_off) / op_k


## 位移类动效进度（减少动态效果：直接 1）
func _op_p(t0: float, delay: float, dur: float) -> float:
	if Cfg.reduce_motion:
		return 1.0
	return clampf((t - t0 - delay) / dur, 0.0, 1.0)


## 透明度类动效进度（减少动态效果：从 t0 起 ≤ 120 ms 淡入）
func _op_a(t0: float, delay: float, dur: float) -> float:
	if Cfg.reduce_motion:
		return clampf((t - t0) / OP_FADE, 0.0, 1.0)
	return clampf((t - t0 - delay) / dur, 0.0, 1.0)


func _op_input(event: InputEvent) -> void:
	if op_press_t >= 0.0:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match Pad.kc(event):
			KEY_LEFT, KEY_A:
				_op_step(-1)
			KEY_RIGHT, KEY_D:
				_op_step(1)
			KEY_UP, KEY_W:
				_op_set_tab(op_tab - 1)
			KEY_DOWN, KEY_S:
				_op_set_tab(op_tab + 1)
			KEY_PAGEUP, KEY_Q:
				_op_filter_step(-1)
			KEY_PAGEDOWN, KEY_E:
				_op_filter_step(1)
			KEY_TAB, KEY_Z:
				_op_skill_step(1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_op_go()
			KEY_ESCAPE, KEY_BACKSPACE:
				_op_back()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_op_step(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var p := _op_design(make_input_local(event).position)
		if event.pressed:
			op_press_pos = p
			op_last_pos = p
			op_dragging = false
			op_drag_on = _touch_mode() and _op_in_roster(p)
			if not op_drag_on:
				_op_tap(p)
		else:
			if op_drag_on and not op_dragging:
				_op_tap(op_press_pos)
			op_drag_on = false
			op_dragging = false
	elif event is InputEventMouseMotion and op_drag_on and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		# 触屏拖动名册：1:1 跟手（手机竖滑、桌面触屏横滑），拖过 12 像素不再算点选
		var p := _op_design(make_input_local(event).position)
		var d := p - op_last_pos
		op_last_pos = p
		if (p - op_press_pos).length() > 12.0:
			op_dragging = true
		op_scroll = clampf(op_scroll - d.y, 0.0, _op_scroll_max())
		op_scroll_f = op_scroll


## 名册区（设计坐标）：手机是左侧两列，触屏宽屏同桌面是底部一排
func _op_in_roster(p: Vector2) -> bool:
	return Rect2(0, 34, 146, 326).has_point(p)


func _op_tap(p: Vector2) -> void:
	for k in op_prects:
		if op_prects[k].has_point(p):
			if k.begins_with("tab"):
				_op_set_tab(int(k.substr(3)))
			elif k.begins_with("sk"):
				if op_skill != int(k.substr(2)):
					op_skill = int(k.substr(2))
					Sfx.play("ui_move")
			return
	for k in op_rects:
		if op_rects[k].has_point(p):
			if k is int:
				if op_sel == k:
					_op_go()
				else:
					_op_select(k)
			elif k == "go":
				_op_go()
			elif k == "back":
				_op_back()
			elif k.begins_with("cls:"):
				_op_set_filter(k.substr(4))
			elif k == "more_r" or k == "more_l":
				_op_page(1 if k == "more_r" else -1)
			return


func _op_step(d: int) -> void:
	var lst := _op_list()
	if lst.is_empty():
		return
	var j := lst.find(op_sel)
	_op_select(lst[clampi(j + d, 0, lst.size() - 1)] if j >= 0 else lst[0])


func _op_select(n: int) -> void:
	if n == op_sel or n < 0 or n >= op_defs.size():
		return
	op_prev_sel = op_sel
	op_sel = n
	op_sw_t = t
	op_skill = _op_default_skill()
	Sfx.play("ui_move")
	_op_follow()


func _op_set_tab(i: int) -> void:
	i = posmod(i, OP_TABS.size())
	if i == op_tab:
		return
	op_tab_from = op_tab
	op_tab = i
	op_tab_t = t
	Sfx.play("ui_move")


func _op_skill_step(d: int) -> void:
	if op_tab != 1:
		_op_set_tab(1)
		return
	op_skill = posmod(op_skill + d, 3)
	Sfx.play("ui_move")


func _op_set_filter(c: String) -> void:
	if c == op_filter or _op_class_count(c) == 0:
		return
	op_filter = c
	Sfx.play("ui_move")
	var lst := _op_list()
	if not lst.has(op_sel) and not lst.is_empty():
		op_prev_sel = op_sel
		op_sel = lst[0]
		op_sw_t = t
		op_skill = _op_default_skill()
	op_scroll = 0.0
	_op_follow()


## 职业筛选前后切（跳过没有干员的职业）
func _op_filter_step(d: int) -> void:
	var cs := _op_classes()
	var i := cs.find(op_filter)
	for k in cs.size():
		i = posmod(i + d, cs.size())
		if _op_class_count(cs[i]) > 0:
			_op_set_filter(cs[i])
			return


## 名册滚动上限（设计像素）
func _op_scroll_max() -> float:
	var n := _op_list().size()
	if _touch_mode():
		return maxf(0.0, (ceili(n / 2.0) - 3) * 100.0)
	return maxf(0.0, (n - op_vis) * 90.0)


## 选中项滚进可视区
func _op_follow(instant := false) -> void:
	var lst := _op_list()
	var j := maxi(0, lst.find(op_sel))
	var ph := _touch_mode()
	var step := 100.0 if ph else 90.0
	var pos: float = float(j / 2) if ph else float(j)
	var vis: int = 3 if ph else op_vis
	var s := op_scroll / step
	if pos < s:
		s = pos
	elif pos > s + vis - 1:
		s = pos - vis + 1
	op_scroll = clampf(s * step, 0.0, _op_scroll_max())
	if instant:
		op_scroll_f = op_scroll


func _op_page(d: int) -> void:
	var ph := _touch_mode()
	op_scroll = clampf(op_scroll + d * (2.0 * 100.0 if ph else (op_vis - 1) * 90.0), 0.0, _op_scroll_max())
	Sfx.play("ui_move")


func _op_back() -> void:
	if transition.busy:
		return
	transition.switch_page(func(): op_pick = false)
	Sfx.play("ui_move")


func _op_go() -> void:
	if transition.busy or op_defs.is_empty() or op_press_t >= 0.0:
		return
	var cid: String = op_defs[op_sel].id
	Sfx.play("ui_ok")
	if cover_pick:
		transition.switch_page(func():
			Cfg.cover_character_id = cid
			Cfg.save()
			title_bg.reload_guest()
			op_pick = false)
	else:
		# 出击：按钮下沉 + 闪白 160 ms，140 ms 起深海浪幕 700 ms，过半换到难度页（浪幕期间锁输入，同页面切换）
		op_go_id = cid
		op_press_t = t
		op_wipe_t = t + (0.0 if Cfg.reduce_motion else 0.14)
		op_wipe_swapped = false
		transition._lock()


## 每帧：排版缩放、悬停、平滑滚动、子层位置 / 透明度、浪幕进度（_process 调）
func _op_tick(delta: float) -> void:
	var vs := size
	var ph := _touch_mode()
	var dsz := OP_PHONE if ph else OP_DESK
	op_k = minf(vs.x / dsz.x, vs.y / dsz.y)
	op_off = ((vs - dsz * op_k) / 2.0).round()
	if not op_dragging:
		op_scroll_f = op_scroll if Cfg.reduce_motion else lerpf(op_scroll_f, op_scroll, 1.0 - exp(-14.0 * delta))
		if absf(op_scroll_f - op_scroll) < 0.2:
			op_scroll_f = op_scroll
	# 悬停：120 ms 抬 4 px（触屏不认悬停）
	var hov := -1
	if op_pick and not ph and op_press_t < 0.0:
		var mp := _op_design(get_local_mouse_position())
		for k in op_rects:
			if k is int and op_rects[k].has_point(mp):
				hov = k
	for i in op_defs.size():
		var target := 1.0 if (i == hov and i != op_sel) else 0.0
		var cur: float = op_hover.get(i, 0.0)
		if cur != target:
			op_hover[i] = target if Cfg.reduce_motion else move_toward(cur, target, delta / 0.12)
	# 子层：信息面板（打开时从右 340 px 滑入）+ 正文（换干员 60 px 滑入、换页签淡出）
	op_panel.visible = op_pick
	op_body.visible = op_pick
	if op_pick:
		var op_open := UI.ease_out(_op_p(op_open_t, 0.0, 0.3))
		op_panel.position = op_off + Vector2(340.0 * (1.0 - op_open) * op_k, 0.0)
		op_panel.scale = Vector2(op_k, op_k)
		op_panel.modulate.a = _op_a(op_open_t, 0.0, OP_FADE) if Cfg.reduce_motion else minf(1.0, op_open * 2.0)
		var m := _op_body_motion()
		op_body.position = Vector2(m.dx, 0.0)
		op_body.modulate.a = m.alpha
		op_panel.queue_redraw()
		op_body.queue_redraw()
	# 浪幕：过半换到难度页，结束解锁
	op_wipe_layer.visible = op_wipe_t >= 0.0 and t >= op_wipe_t
	if op_wipe_t >= 0.0 and t >= op_wipe_t:
		var e := (t - op_wipe_t) / _op_wipe_len()
		if e >= 0.5 and not op_wipe_swapped:
			op_wipe_swapped = true
			Cfg.character_id = op_go_id
			Cfg.save()
			op_pick = false
			diff_pick = true
			diff_sel = clampi(Cfg.difficulty, 0, Cfg.diff_unlocked)
		if e >= 1.0:
			op_wipe_t = -1.0
			op_press_t = -1.0
			op_wipe_layer.visible = false
			transition._unlock()
		op_wipe_layer.queue_redraw()


func _op_wipe_len() -> float:
	return OP_FADE * 2.0 if Cfg.reduce_motion else 0.7


func _draw_op_wipe() -> void:
	if op_wipe_t < 0.0:
		return
	var e := clampf((t - op_wipe_t) / _op_wipe_len(), 0.0, 1.0)
	if Cfg.reduce_motion:
		# 减少动态效果：不画浪，只做 120 ms 压暗 → 换页 → 120 ms 亮回
		op_wipe_layer.draw_rect(Rect2(Vector2.ZERO, size), Color(0.039, 0.102, 0.173, 1.0 - absf(e - 0.5) * 2.0))
		return
	UI.wave_wipe(op_wipe_layer, size, UI.ease_io(e))


## 面板正文的动效状态：最近一次是换页签 → 旧页 100 ms 淡出、新页三行错开 60 ms 从右 40 px 滑入；否则按换干员（120 ms 后 260 ms 滑入 60 px）
func _op_body_motion() -> Dictionary:
	var m := {"tab": op_tab, "tabpos": float(op_tab), "dx": 0.0, "alpha": 1.0, "rows": [1.0, 1.0, 1.0], "cnt": 1.0}
	if op_tab_t > op_sw_t:
		var q := op_tab_t
		m.tabpos = lerpf(float(op_tab_from), float(op_tab), UI.ease_out(_op_p(q, 0.0, 0.2)))
		if not Cfg.reduce_motion and t - q < 0.1:
			m.tab = op_tab_from
			m.alpha = 1.0 - (t - q) / 0.1
		else:
			m.alpha = _op_a(q, 0.0, 0.0) if Cfg.reduce_motion else 1.0
			m.rows = [_op_p(q, 0.1, 0.25), _op_p(q, 0.16, 0.25), _op_p(q, 0.22, 0.25)]
			m.cnt = UI.ease_out(_op_p(q, 0.1, 0.4))
	else:
		var s := op_sw_t
		var pp := _op_p(s, 0.12, 0.26)
		m.dx = 60.0 * (1.0 - UI.ease_out(pp))
		m.alpha = _op_a(s, 0.0, 0.0) if Cfg.reduce_motion else minf(1.0, pp * 1.5)
		m.rows = [_op_p(s, 0.12, 0.26), _op_p(s, 0.18, 0.26), _op_p(s, 0.24, 0.26)]
		m.cnt = UI.ease_out(_op_p(s, 0.12, 0.45))
	return m


## 名册卡抬起：选中 220 ms ease-out back，旧选中 160 ms 落回
func _op_lift(i: int) -> float:
	if i == op_sel:
		return 1.0 if Cfg.reduce_motion else UI.ease_back((t - op_sw_t) / 0.22)
	if i == op_prev_sel:
		return 0.0 if Cfg.reduce_motion else 1.0 - UI.ease_out((t - op_sw_t) / 0.16)
	return 0.0


## 帧内非透明区（各待机帧的并集，立绘按它对齐、不抖）+ 白色剪影（立绘外晕用）；第一次画到时算，读不到图（无头）就用整帧
func _op_art(od: Dictionary) -> void:
	if od.has("bb"):
		return
	var tx: Texture2D = od.tex
	od.sil = null
	if tx == null:
		od.bb = Rect2()
		return
	var fw: int = tx.get_width() / int(od.frames)
	od.bb = Rect2(0, 0, fw, tx.get_height())
	var img := tx.get_image()
	if img == null or img.is_empty():
		return
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var u := Rect2i()
	for f in int(od.frames):
		var r := img.get_region(Rect2i(f * fw, 0, fw, img.get_height())).get_used_rect()
		if r.size.x > 0:
			u = r if u.size.x == 0 else u.merge(r)
	if u.size.x > 0:
		od.bb = Rect2(u)
	var white := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	var sil := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	sil.blit_rect_mask(white, img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
	od.sil = ImageTexture.create_from_image(sil)


## 选人页（B+）：背景铺满界面，其余按设计稿坐标画（draw_set_transform 缩放）
func _draw_op_pick(vs: Vector2) -> void:
	if op_defs.is_empty():
		return
	_op_backdrop(vs)
	draw_set_transform(op_off, 0.0, Vector2(op_k, op_k))
	op_rects.clear()
	var od: Dictionary = op_defs[op_sel]
	_op_art(od)
	if _touch_mode():
		_op_draw_phone(od)
	else:
		_op_draw_desk(od)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 背景：深海青 → 深紫斜向渐变 + 青色柔光 + 下方浪纹 + 两侧触须剪影 + 灯火暖光点（docs/58 §7 B）
func _op_backdrop(vs: Vector2) -> void:
	if op_bg.get("vs", Vector2.ZERO) != vs:
		_op_bg_build(vs)
	var c0 := Color(6 / 255.0, 30 / 255.0, 40 / 255.0)
	var c1 := Color(30 / 255.0, 14 / 255.0, 52 / 255.0)
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(vs.x, 0), vs, Vector2(0, vs.y)]),
		PackedColorArray([c0.lerp(c1, 0.45), c1, c0.lerp(c1, 0.55), c0]))
	var gc := Vector2(vs.x * 0.62, vs.y * 0.45)
	var gr := vs.y * 0.7
	draw_texture_rect(op_glow_tex, Rect2(gc - Vector2(gr, gr), Vector2(gr, gr) * 2.0), false, Color(90 / 255.0, 200 / 255.0, 220 / 255.0, 0.3))
	var ph := 0.0 if Cfg.reduce_motion else t * 0.4
	for k in 9:
		var yb := vs.y * 0.55 + k * 26.0
		var pts := PackedVector2Array()
		var x := 0.0
		while x <= vs.x + 10.0:
			pts.append(Vector2(x, yb + 6.0 * sin(x / 70.0 + k * 1.3 + ph)))
			x += 10.0
		draw_polyline(pts, Color(140 / 255.0, 230 / 255.0, 240 / 255.0, (14.0 + k) / 255.0), 1.0, true)
	for sg in op_bg.tent:
		draw_line(sg[0], sg[1], Color(120 / 255.0, 80 / 255.0, 200 / 255.0, 0.1), sg[2])
	var drift := 0.0 if Cfg.reduce_motion else t * 6.0
	for mo in op_bg.motes:
		var p: Vector2 = mo[0]
		p.y = fposmod(p.y - drift * mo[3], vs.y + 20.0) - 10.0
		draw_circle(p, mo[1], Color(1.0, 220 / 255.0, 150 / 255.0, mo[2]))


func _op_bg_build(vs: Vector2) -> void:
	var rng := RandomNumberGenerator.new()   # 界面装饰：固定种子的本地 RNG（不是 g.rng）
	rng.seed = 3
	var tent: Array = []
	for side in 2:
		for i in 4:
			var x: float = rng.randf_range(-40, 160) if side == 0 else vs.x - rng.randf_range(-40, 160)
			var ang: float = -PI / 2.0 + (0.35 if side == 0 else -0.35) + rng.randf_range(-0.3, 0.3)
			var wdt: float = rng.randf_range(14, 22)
			var length: float = rng.randf_range(260, 460)
			var phs: float = rng.randf_range(0, 6)
			var prev := Vector2(x, vs.y + 20.0)
			var s := 0.0
			while s < length:
				var a: float = ang + 0.5 * sin(s / 60.0 + phs) * (s / length)
				var nx := prev + Vector2.from_angle(a) * 6.0
				tent.append([prev, nx, maxf(1.0, wdt * (1.0 - s / length))])
				prev = nx
				s += 6.0
	var motes: Array = []
	for i in 60:
		motes.append([Vector2(rng.randf_range(0, vs.x), rng.randf_range(0, vs.y)), [1.0, 1.0, 2.0][rng.randi_range(0, 2)], rng.randf_range(30, 90) / 255.0, rng.randf_range(0.5, 1.5)])
	op_bg = {"vs": vs, "tent": tent, "motes": motes}


## 立绘：待机帧（帧内非透明区并集）整数倍最近邻放大，底部 28 % 渐隐；换干员 60 ms 后 300 ms 缩放 0.92 → 1、右移 24 → 0、淡入，青白外晕随透明度出现
## foot = 脚底中点（ci 的坐标），k2 = 相对 @2x 像素的整数倍（_op_fit 算）
## clip = 舞台框：每一次贴图都裁进框里（缩放进入 / 右移 24 px / 外晕都不会画出框，兜底）
func _op_char(ci: CanvasItem, od: Dictionary, foot: Vector2, k2: float, clip: Rect2) -> void:
	var tx: Texture2D = od.tex
	if tx == null:
		return
	var c := UI.ease_out(_op_p(op_sw_t, 0.06, 0.3))
	var a := _op_a(op_sw_t, 0.06, 0.3) if Cfg.reduce_motion else c
	if a <= 0.0:
		return
	var bb: Rect2 = od.bb
	var fw: float = tx.get_width() / float(od.frames)
	var fr: int = int(t * 4.0) % int(od.frames)
	var k: float = k2 * 2.0 / float(od.hires) * float(od.get("ds", 1.0)) * (0.92 + 0.08 * c)
	var sz := bb.size * k
	var pos := UI.foot_pos(foot, bb, fw, tx.get_height(), float(od.hires), k) + Vector2(24.0 * (1.0 - c), 0.0)   # 脚底点对齐（10-21 水月）
	var src := Rect2(fw * fr + bb.position.x, bb.position.y, bb.size.x, bb.size.y)
	var cut := floorf(bb.size.y * 0.72)
	if od.sil != null:
		var gsrc := Rect2(src.position, Vector2(src.size.x, cut))
		for ring in [4.0 * k2 / 5.0, 8.0 * k2 / 5.0, 12.0 * k2 / 5.0]:
			for d in 8:
				var dv: Vector2 = Vector2.from_angle(TAU * d / 8.0) * ring
				UI.blit_clipped(ci, od.sil, Rect2(pos + dv, Vector2(sz.x, cut * k)), gsrc, clip, Color(150 / 255.0, 220 / 255.0, 240 / 255.0, (0.03 if ring < 6.0 else 0.018) * a))
	UI.blit_clipped(ci, tx, Rect2(pos, Vector2(sz.x, cut * k)), Rect2(src.position, Vector2(src.size.x, cut)), clip, Color(1, 1, 1, a))
	var rows: int = int(bb.size.y - cut)
	for y in rows:
		var f := 1.0 - (y + 0.5) / float(rows)
		UI.blit_clipped(ci, tx, Rect2(pos + Vector2(0, (cut + y) * k), Vector2(sz.x, k)), Rect2(src.position + Vector2(0, cut + y), Vector2(src.size.x, 1)), clip, Color(1, 1, 1, a * f))


## 换干员：新色带从左扫入盖住旧色带（380 ms）；减少动态效果时两带 120 ms 交叉淡化
func _op_band(h: float, ox: float, sc: float, col: Color) -> void:
	var prev := Color(0, 0, 0, 0)
	if op_prev_sel >= 0 and op_prev_sel < op_defs.size():
		prev = op_defs[op_prev_sel].col
	if Cfg.reduce_motion:
		var f := _op_a(op_sw_t, 0.0, 0.0)
		if f < 1.0 and prev.a > 0.0:
			UI.class_band(self, h, ox, sc, prev, Color(0, 0, 0, 0), 1.0, 0.35, true, 1.0 - f)
		UI.class_band(self, h, ox, sc, col, Color(0, 0, 0, 0), 1.0, 0.35, true, f)
		return
	UI.class_band(self, h, ox, sc, col, prev, _op_p(op_sw_t, 0.0, 0.38))


## 英文名打字机（换干员 80 ms 后 420 ms 逐字）与中文名淡入
func _op_name_frac() -> float:
	return _op_p(op_sw_t, 0.08, 0.42)


func _op_name_alpha() -> float:
	return _op_a(op_sw_t, 0.0, 0.0) if Cfg.reduce_motion else minf(1.0, _op_name_frac() * 1.6)


## 渐隐的紫色横线（顶栏底、名册带顶）
func _op_hline(y: float, w: float) -> void:
	var cl := Color(UI.PURPLE.r, UI.PURPLE.g, UI.PURPLE.b, 0.0)
	draw_polyline_colors(PackedVector2Array([Vector2(0, y), Vector2(w / 2.0, y), Vector2(w, y)]), PackedColorArray([cl, Color(cl.r, cl.g, cl.b, 0.43), cl]), 1.0)


func _op_btn(r: Rect2, s: String, size := 12) -> void:
	var hot := r.has_point(_op_design(get_local_mouse_position())) and not _touch_mode()
	UI.bpanel(self, r, false, hot, 1.0, UI.CYAN)
	UI.text_at(self, font, r.get_center(), s, size, UI.TEXT, "mm")


func _op_deploy(r: Rect2, size: int, sub: String) -> void:
	var br := 0.5 if Cfg.reduce_motion else 0.5 + 0.5 * sin(t * TAU / 1.6)
	var p := 0.0
	if op_press_t >= 0.0:
		p = clampf((t - op_press_t) / (OP_FADE if Cfg.reduce_motion else 0.16), 0.0, 1.0)
	UI.deploy_button(self, font, r, "更换  ›" if cover_pick else "出击  ›", sub, br, p, size, 1.0, 0.0 if Cfg.reduce_motion else 3.0)
	op_rects["go"] = r.grow(6.0)


## 桌面版式（1280×720 设计稿 = final_select_Bplus.png）
func _op_draw_desk(od: Dictionary) -> void:
	var W := OP_DESK.x
	var H := OP_DESK.y
	var col: Color = od.col
	var d: Dictionary = od.def
	_op_band(H, 0.0, 1.0, col)
	# 立绘缩小时：脚底略上提、描边英文名同比缩小并下移，仍压在立绘上半身后面
	var ar := op_art_k / 5.0
	UI.ghost_name(self, font, Vector2(380 + (1.0 - ar) * 60.0, 78 + (1.0 - ar) * 150.0), od.en, _op_name_frac(), int(round(150 * (0.5 + 0.5 * ar))))
	_op_draw_art(od)
	# 顶栏：节点标签条式标题 + 说明 + 难度 / 封面标签 + 返回
	draw_rect(Rect2(0, 0, W, 54), Color(4 / 255.0, 8 / 255.0, 18 / 255.0, 0.55))
	_op_hline(54.5, W)
	UI.rbox(self, Rect2(16, 12, 150, 30), 3, UI.VIOLET)
	UI.en(self, font, Vector2(26, 19 + UI.cond(font, true).get_ascent(11)), "OPERATOR SELECT", 11, Color.WHITE, 2.0, true)
	UI.diamond(self, Vector2(16, 27), 5.0, UI.B_ACC)
	var tw := UI.text_at(self, font, Vector2(182, 27), "更换封面干员" if cover_pick else "选择开局干员", 20, UI.TEXT, "lm")
	var sx := 182.0 + tw + 20.0
	if cover_pick:
		UI.text_at(self, font, Vector2(sx, 14), "显示在标题页上的干员", 12, UI.B_SUB)
		UI.text_at(self, font, Vector2(sx, 30), "不改变开局编队", 11, UI.B_SUB)
	else:
		UI.text_at(self, font, Vector2(sx, 14), "队长 1 名；其余干员在探索中通过升级招募", 12, UI.B_SUB)
		UI.text_at(self, font, Vector2(sx, 30), "下一步：选择难度", 11, UI.B_SUB)
	var back := Rect2(W - 120, 14, 104, 28)
	_op_btn(back, Pad.hint("返回  Esc", "返回  Ⓑ", "返回"))
	op_rects["back"] = back.grow(4.0)
	var px := W - 136.0
	var cover_name: String = Character.load_def(Cfg.cover_character_id).get("name", Cfg.cover_character_id) if Cfg.cover_character_id != "" else ""
	for chip in [["封面干员 " + cover_name, UI.PURPLE], ["难度 " + str(D.DIFFICULTY_TIERS[clampi(Cfg.difficulty, 0, D.DIFFICULTY_TIERS.size() - 1)].name), UI.STEEL]]:
		if chip[0].ends_with(" "):
			continue
		px -= UI.pill_width(font, chip[0], 11)
		UI.pill(self, font, Vector2(px, 18), chip[0], chip[1], 11)
		px -= 6.0
	# 左：职业筛选轨（全部 + 8 职业；没有干员的职业变暗、不可选）
	var cs := _op_classes()
	var rx0 := 14.0
	var ry0 := 68.0
	var step := 46.0
	UI.rbox(self, Rect2(rx0, ry0, 44, cs.size() * step + 12), 22, UI.B_FILL, UI.B_LINE)
	for i in cs.size():
		var c: String = cs[i]
		var cy := ry0 + 28.0 + i * step
		var on := c == op_filter
		var n := _op_class_count(c)
		var dim := 1.0 if n > 0 else 0.35
		if on:
			UI.rbox(self, Rect2(rx0 + 4, cy - 19, 36, 38), 18, UI.VIOLET)
		var gc := Color.WHITE if on else UI.fa(Color(200 / 255.0, 205 / 255.0, 225 / 255.0), dim)
		if c == "":
			UI.text_at(self, font, Vector2(rx0 + 22, cy), "全", 13, UI.TEXT, "mm")
		else:
			UI.class_glyph(self, c, Vector2(rx0 + 22, cy - 4), 8.0, gc)
			UI.text_at(self, font, Vector2(rx0 + 22, cy + 12), c, 9, gc if on else UI.fa(UI.B_SUB, dim), "mm")
		if n > 0:
			op_rects["cls:" + c] = Rect2(rx0, cy - 22, 44, 44)
	# 名字块：微型代码 + 中文名 + 英文名（打字机）+ 圆角标签 + 一句定位
	var na := _op_name_alpha()
	UI.code(self, font, Vector2(92, 282), "No.%02d  //  %s  //  %s" % [op_sel + 1, od.cls, "近战" if od.melee else "远程"], 9)
	if na > 0.0:
		var nf := UI.fit_line(font, od.name, 44, 470.0, 28)
		UI.text_at(self, font, Vector2(90, 296), nf[0], nf[1], UI.fa(UI.TEXT, na), "la", true)
		var en_s: String = od.en
		en_s = en_s.substr(0, int(round(en_s.length() * clampf(_op_name_frac(), 0.0, 1.0))))
		UI.en(self, font, Vector2(94, 350 + UI.cond(font, true).get_ascent(14)), en_s, 14, UI.fa(col, na), 4.0, true)
	var cx := 92.0
	cx += UI.pill(self, font, Vector2(cx, 376), od.cls, col, 12)
	for tg in d.get("gallery", {}).get("tags", []):
		if cx + UI.pill_width(font, tg, 11) > 600.0:
			break
		cx += UI.pill(self, font, Vector2(cx, 376), tg, UI.PURPLE, 11)
	var desc: String = d.get("gallery", {}).get("desc", "")
	if desc != "":
		var fl := UI.fit_line(font, desc, 12, 500.0, 10)
		UI.text_at(self, font, Vector2(92, 406), fl[0], fl[1], UI.B_SUB)
	# 编队条：主控 + 两个队友位（封面模式只画封面位）
	UI.btab(self, font, Vector2(92, 440), "封面" if cover_pick else "编队", Color(90 / 255.0, 70 / 255.0, 190 / 255.0), 9)
	for i in (1 if cover_pick else 3):
		var r := Rect2(92 + i * 94, 460, 84, 56)
		if i == 0:
			UI.bpanel(self, r, true, true, 1.0, UI.VIOLET)
			_op_mini(od, Rect2(r.position.x + 2, r.position.y + 2, 46, r.size.y - 4))
			UI.rbox(self, Rect2(r.position.x + 2, r.position.y + 2, 32, 13), 3, UI.VIOLET)
			UI.text_at(self, font, Vector2(r.position.x + 18, r.position.y + 8.5), "封面" if cover_pick else "队长", 10, Color.WHITE, "mm")
			var mf := UI.fit_line(font, od.name, 10, 42.0, 8)
			UI.text_at(self, font, Vector2(r.position.x + 62, r.position.y + 34), mf[0], mf[1], UI.TEXT, "mm")
		else:
			UI.bpanel(self, r)
			UI.text_at(self, font, Vector2(r.position.x + 42, r.position.y + 22), "队友 %d" % i, 11, UI.B_SUB, "mm")
			UI.text_at(self, font, Vector2(r.position.x + 42, r.position.y + 40), "探索中招募", 9, UI.B_SUB, "mm")
	if cover_pick:
		UI.text_at(self, font, Vector2(190, 488), "封面不改变开局编队", 11, UI.B_SUB, "lm")
	# 名册带
	var rb := H - 170.0
	draw_rect(Rect2(0, rb - 6, W, H - rb + 6), Color(4 / 255.0, 8 / 255.0, 18 / 255.0, 0.63))
	_op_hline(rb - 6, W)
	var lst := _op_list()
	UI.code(self, font, Vector2(70, rb - 1), "ROSTER  %d / %d   //   %s" % [lst.size(), op_defs.size(), "SORT: CLASS" if op_filter == "" else "CLASS: " + op_filter], 8)
	UI.text_at(self, font, Vector2(1258, rb - 2), Pad.hint("◀ ▶ / 滚轮 切换    ↑↓ 页签    Q / E 职业    Enter 下一步", "◀ ▶ 切换    ↑↓ 页签    LB / RB 职业    Ⓐ 下一步", "点卡片切换 · 再点一次出击"), 10, UI.B_SUB, "ra")
	var gx := 70.0
	var go := Rect2(1036, rb + 40, W - 22 - 1036, 72)
	op_vis = maxi(1, int((go.position.x - 24.0 - gx) / 90.0))
	var lim := gx + (op_vis - 1) * 90.0
	var first := -1
	var last := -1
	for j in lst.size():
		var i: int = lst[j]
		var x := gx + j * 90.0 - op_scroll_f
		var over := maxf(gx - x, x - lim)
		var a := clampf(1.0 - over / 60.0, 0.0, 1.0)
		if a <= 0.01:
			continue
		var o: Dictionary = op_defs[i]
		var r := Rect2(x, rb + 22, 82, 112)
		if a > 0.6:
			op_rects[i] = r
			if first < 0:
				first = j
			last = j
		var lift := _op_lift(i)
		UI.roster_card(self, font, r, o, lift, op_hover.get(i, 0.0), o.elite if i == op_sel else 0, int(t * 4.0 + i) % int(o.frames), a)
	if last >= 0 and last < lst.size() - 1:
		var mx := lim + 90.0 + 6.0
		UI.text_at(self, font, Vector2(mx, rb + 70), "▶", 16, UI.B_SUB)
		UI.text_at(self, font, Vector2(mx, rb + 92), "还有 %d 名" % (lst.size() - 1 - last), 10, UI.B_SUB)
		op_rects["more_r"] = Rect2(mx - 6, rb + 50, 60, 70)
	if first > 0:
		UI.text_at(self, font, Vector2(40, rb + 70), "◀", 16, UI.B_SUB, "ma")
		UI.text_at(self, font, Vector2(40, rb + 92), "%d 名" % first, 10, UI.B_SUB, "ma")
		op_rects["more_l"] = Rect2(14, rb + 50, 54, 70)
	_op_deploy(go, 24, ("设为封面干员" if cover_pick else Pad.hint("ENTER  ·  下一步选择难度", "手柄 Ⓐ  ·  下一步选择难度", "下一步选择难度")))


## 手机版式（740×360 设计稿 = final_phone_select_Bplus.png）：左手拇指区两列名册（上滑翻页），右手拇指区页签 + 紧凑技能行 + 出击
func _op_draw_phone(od: Dictionary) -> void:
	var W := OP_PHONE.x
	var H := OP_PHONE.y
	var col: Color = od.col
	_op_band(H, -150.0, 0.6, col)
	var ar := op_art_k / 5.0
	UI.ghost_name(self, font, Vector2(150 + (1.0 - ar) * 40.0, 40 + (1.0 - ar) * 70.0), od.en, _op_name_frac(), int(round(90 * (0.5 + 0.5 * ar))), Color(0.745, 0.824, 1.0, 0.18), 2)
	_op_draw_art(od)
	UI.rbox(self, Rect2(8, 6, 142, 22), 3, UI.VIOLET)
	UI.text_at(self, font, Vector2(16, 17), "更换封面干员" if cover_pick else "选择开局干员", 13, Color.WHITE, "lm")
	var back := Rect2(W - 66, 6, 56, 22)
	_op_btn(back, "返回")
	op_rects["back"] = Rect2(W - 80, 0, 80, 40)
	# 职业筛选（顶栏中段一排小胶囊；点击区放大到 46×38）
	var cs := _op_classes()
	for i in cs.size():
		var c: String = cs[i]
		var x := 160.0 + i * 54.0
		var on := c == op_filter
		var n := _op_class_count(c)
		var dim := 1.0 if n > 0 else 0.35
		var r := Rect2(x, 6, 50, 22)
		UI.rbox(self, r, 11, UI.VIOLET if on else UI.B_FILL, Color(0, 0, 0, 0) if on else UI.fa(UI.B_LINE, dim))
		var gc := Color.WHITE if on else UI.fa(Color(200 / 255.0, 205 / 255.0, 225 / 255.0), dim)
		if c == "":
			UI.text_at(self, font, r.get_center(), "全部", 10, gc, "mm")
		else:
			UI.class_glyph(self, c, Vector2(x + 11, 17), 5.0, gc, 1.5)
			UI.text_at(self, font, Vector2(x + 33, 17), c, 10, gc, "mm")
		if n > 0:
			op_rects["cls:" + c] = Rect2(x - 2, 0, 54, 40)
	# 名册：两列竖排，上滑翻页
	var lst := _op_list()
	var top := 40.0
	var bot := 340.0
	var more := 0
	for j in lst.size():
		var i: int = lst[j]
		var x := 10.0 + (j % 2) * 68.0
		var y := top + (j / 2) * 100.0 - op_scroll_f
		var over := maxf(top - y, (y + 88.0) - bot)
		var a := clampf(1.0 - over / 40.0, 0.0, 1.0)
		if y + 88.0 > bot + 1.0:
			more += 1
		if a <= 0.01:
			continue
		var o: Dictionary = op_defs[i]
		var r := Rect2(x, y, 62, 88)
		if a > 0.6:
			op_rects[i] = r
		UI.roster_card(self, font, r, o, _op_lift(i), 0.0, o.elite if i == op_sel else 0, int(t * 4.0 + i) % int(o.frames), a, 12)
	if more > 0:
		UI.code(self, font, Vector2(74, H - 12), "SWIPE  +%d" % more, 7, UI.B_SUB, "ma")
	# 名字块（压在立绘左边）
	var na := _op_name_alpha()
	if na > 0.0:
		var nf := UI.fit_line(font, od.name, 30, 300.0, 20)
		UI.text_at(self, font, Vector2(152, 206), nf[0], nf[1], UI.fa(UI.TEXT, na), "la", true)
		var en_s: String = od.en
		en_s = en_s.substr(0, int(round(en_s.length() * clampf(_op_name_frac(), 0.0, 1.0))))
		UI.en(self, font, Vector2(154, 244 + UI.cond(font, true).get_ascent(10)), en_s, 10, UI.fa(col, na), 4.0, true)
	var cx := 152.0
	cx += UI.pill(self, font, Vector2(cx, 262), od.cls, col, 10)
	var tags: Array = od.def.get("gallery", {}).get("tags", [])
	if not tags.is_empty():
		UI.pill(self, font, Vector2(cx, 262), tags[0], UI.PURPLE, 10)
	_op_deploy(Rect2(W - 200, H - 62, 186, 48), 18, "")


## 编队位里的小像：@2x 像素 1:1（整数倍、不糊），头顶对齐框顶 + 2，画成半身像——超出框的下半身 / 左右裁掉，不出框
func _op_mini(od: Dictionary, box: Rect2) -> void:
	var tx: Texture2D = od.tex
	if tx == null:
		return
	_op_art(od)
	var bb: Rect2 = od.bb
	var fw: float = tx.get_width() / float(od.frames)
	var s: float = 2.0 / float(od.hires)
	var fr: int = int(t * 4.0) % int(od.frames)
	var dst := Rect2(box.get_center().x - bb.size.x * s / 2.0, box.position.y + 2.0, bb.size.x * s, bb.size.y * s)
	UI.blit_clipped(self, tx, dst, Rect2(fw * fr + bb.position.x, bb.position.y, bb.size.x, bb.size.y), box)


## 立绘舞台（设计坐标）：顶栏以下、名册带以上、信息面板以左；手机：名册列以右、信息面板以左
func _op_stage_rect() -> Rect2:
	if _touch_mode():
		return Rect2(146, 34, 462 - 146, OP_PHONE.y - 4 - 34)
	return Rect2(600, 56, 962 - 600, 544 - 56)


## 立绘适配：在舞台里（四边留 margin）取 ≤ 上限的最大整数倍，使待机帧并集区整个放得下；返回 [倍数（@2x 像素）, 脚底中点]
## 上限：桌面 op_art_k（4），手机 op_art_k × 0.6 取整（2）；中心先放在设计稿位置，放不下再往舞台里挪
func _op_fit(od: Dictionary, ph: bool) -> Array:
	_op_art(od)
	var sr := _op_stage_rect()
	var m := 8.0
	var bb: Rect2 = od.bb
	var hi: float = float(od.get("hires", 1.0))
	var w2: float = maxf(bb.size.x * 2.0 / hi, UI.CARD_REF.x)   # 全员统一参考尺寸取倍数（10-21 用户：每人一样大）；整幅仍须在舞台内（full2）
	var h2: float = UI.CARD_REF.y
	var foot_y: float = (312.0 if ph else sr.end.y - m)
	return UI.art_fit(w2, h2, sr, op_art_k * (0.6 if ph else 1.0), 380.0 if ph else 780.0, foot_y, m, bb.size.y * 2.0 / hi)   # 图鉴 C4' 同一规则


## 立绘：适配倍数 + 裁进舞台框（画在描边英文名之后、名字块之前，层次同定稿）
func _op_draw_art(od: Dictionary) -> void:
	var fit := _op_fit(od, _touch_mode())
	_op_char(self, od, fit[1], fit[0], _op_stage_rect())


## 信息面板框 + 页签（子控件 op_panel 画，设计坐标）
func _op_panel_rect() -> Rect2:
	if _touch_mode():
		return Rect2(470, 38, OP_PHONE.x - 10 - 470, OP_PHONE.y - 80 - 38)
	return Rect2(968, 68, OP_DESK.x - 16 - 968, 530 - 68)


func _draw_op_panel() -> void:
	op_prects.clear()
	if not op_pick or op_defs.is_empty():
		return
	var ci := op_panel
	var pr := _op_panel_rect()
	var m := _op_body_motion()
	UI.bpanel(ci, pr, true)
	var trs: Array
	if _touch_mode():
		trs = UI.btabs(ci, font, Rect2(pr.position.x + 2, pr.position.y + 2, pr.size.x - 4, 26), OP_TABS, m.tabpos, 12)
		for i in trs.size():
			op_prects["tab%d" % i] = Rect2(trs[i].position.x, pr.position.y - 8, trs[i].size.x, 44)
	else:
		UI.code(ci, font, pr.position + Vector2(14, 8), "OPERATOR DATA // " + OP_TAB_EN[int(m.tab)], 8)
		trs = UI.btabs(ci, font, Rect2(pr.position.x + 4, pr.position.y + 22, pr.size.x - 8, 32), OP_TABS, m.tabpos, 14)
		for i in trs.size():
			op_prects["tab%d" % i] = trs[i]


## 面板正文（子控件 op_body 画；整体位移 / 透明度由 _op_tick 设）
func _draw_op_body() -> void:
	if not op_pick or op_defs.is_empty():
		return
	var ci := op_body
	var pr := _op_panel_rect()
	var ph := _touch_mode()
	var box := Rect2(pr.position.x + 8, pr.position.y + 34, pr.size.x - 16, pr.size.y - 40) if ph else Rect2(pr.position.x + 12, pr.position.y + 66, pr.size.x - 24, pr.size.y - 76)
	var od: Dictionary = op_defs[op_sel]
	var m := _op_body_motion()
	match int(m.tab):
		0:
			_op_status(ci, box, od, m, ph)
		1:
			_op_skills(ci, box, od, m, ph)
		_:
			_op_squad(ci, box, od, m, ph)


func _op_fmt(v: float, key: String, real := 1.0) -> String:
	if real <= 0.0:
		return "—"
	if key == "cd":
		return "%.2f 秒" % v
	if key == "dps":
		return "%.1f" % v
	if key == "atk" and absf(v - roundf(v)) > 0.05:
		return "%.1f" % v
	return "%d" % int(round(v))


## 属性页（数值表与图鉴「属性」页同源：InitialStats.sheet）：桌面 = 五项大数字 + 量条（满值 = 全体干员该项上限）+ 两列小表 + 定位；
## 手机 = 只有两列小表（版面放不下量条）；底部一行口径说明
func _op_status(ci: CanvasItem, box: Rect2, od: Dictionary, m: Dictionary, ph: bool) -> void:
	var cnt: float = m.cnt
	var v: Dictionary = od.vals
	var sh: Dictionary = od.sheet
	var y := box.position.y
	var small: Array = []
	if ph:
		for r in sh.rows:
			small.append(r)
	else:
		var step := 46.0
		for key in ["atk", "dps", "cd", "reach", "hp"]:
			var r: Dictionary = InitialStats.row(sh, key)
			var val: float = v[key]
			var shown := val * (2.0 - cnt) if key == "cd" else val * cnt
			var lw := UI.btab(ci, font, Vector2(box.position.x, y), r.label, UI.STEEL if key == "hp" else UI.TAB_HP, 9)
			UI.code(ci, font, Vector2(box.position.x + lw + 8, y + 2), r.en, 8)
			var vw := UI.text_at(ci, font, Vector2(box.end.x, y - 4), _op_fmt(shown, key, val), 22, UI.TEXT, "ra", true)
			if str(r.sub) != "":
				UI.text_at(ci, font, Vector2(box.end.x - vw - 6, y + 4), r.sub, 10, UI.B_SUB, "ra")
			UI.gauge(ci, Rect2(box.position.x, y + 25, box.size.x - 110.0, 8), val / float(op_max[key]) * cnt, UI.TEXT if key == "hp" else UI.CYAN)
			y += step
		for r in sh.rows:
			if not r.key in ["atk", "dps", "cd", "reach", "hp"]:
				small.append(r)
		y += 2.0
	small.append_array(sh.extra)
	ci.draw_line(Vector2(box.position.x, y), Vector2(box.end.x, y), UI.B_LINE, 1.0)
	y += 6.0 if ph else 8.0
	var lh := 21.0 if ph else 22.0
	var cw := (box.size.x - 10.0) / 2.0
	for i in small.size():
		var r: Dictionary = small[i]
		var cx := box.position.x + (i % 2) * (cw + 10.0)
		var cy := y + (i / 2) * lh
		var lbl: String = r.label
		var lsz := 10 if ph else 11
		var lwid := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, lsz).x
		UI.text_at(ci, font, Vector2(cx, cy + 2), lbl, lsz, UI.B_SUB)
		var txt: String = r.text
		if ph and str(r.sub) != "" and r.key == "atk":
			txt += " " + str(r.sub)
		var fl := UI.fit_line(font, txt, 12 if ph else 13, cw - lwid - 6.0, 9)
		UI.text_at(ci, font, Vector2(cx + cw, cy), fl[0], fl[1], UI.TEXT, "ra")
		ci.draw_line(Vector2(cx, cy + lh - 3), Vector2(cx + cw, cy + lh - 3), Color(UI.B_LINE.r, UI.B_LINE.g, UI.B_LINE.b, 0.35), 1.0)
	y += ceili(small.size() / 2.0) * lh + 4.0
	var tags: Array = sh.tags
	if not tags.is_empty() and y + 22.0 < box.end.y - 12.0:
		var tx := box.position.x + UI.btab(ci, font, Vector2(box.position.x, y + 3), "定位", UI.TAB_HP, 9) + 8.0
		for c in tags:
			var pw := UI.pill_width(font, str(c), 10)
			if tx + pw > box.end.x + 6.0:
				break
			tx += UI.pill(ci, font, Vector2(tx, y), str(c), UI.PURPLE, 10)
		y += 24.0
	var desc: String = od.def.get("attack", {}).get("desc", "")
	if not ph and desc != "" and y + 42.0 < box.end.y - 12.0:
		UI.code(ci, font, Vector2(box.position.x, y), "TRAIT // 特性", 8)
		var f := UI.fit(font, desc, box.size.x, box.end.y - y - 28.0, [11, 10])
		UI.draw_fit(ci, font, Vector2(box.position.x, y + 14), f, UI.B_SUB)
	UI.text_at(ci, font, Vector2(box.position.x, box.end.y - 12), sh.note, 9, UI.B_SUB)


## 技能页：攻击 / 间隔 / 范围 / 生命小标签头 + 三行技能卡（图标 + 名字 / 英文 + SP 环 + 解锁阶段 + 手动 Q / 自动）+ 展开说明 + 天赋
func _op_skills(ci: CanvasItem, box: Rect2, od: Dictionary, m: Dictionary, ph: bool) -> void:
	var d: Dictionary = od.def
	var cnt: float = m.cnt
	var y := box.position.y
	var col: Color = od.col
	if not ph:
		var v: Dictionary = od.vals
		var stats := [[InitialStats.row(od.sheet, "atk").label, _op_fmt(v.atk * cnt, "atk", v.atk)], ["间隔", _op_fmt(v.cd * (2.0 - cnt), "cd", v.cd)],
			[InitialStats.row(od.sheet, "reach").label, _op_fmt(v.reach * cnt, "reach", v.reach)], ["生命", "队长 %d" % int(round(v.hp * cnt))]]
		var cw := box.size.x / 4.0
		for i in stats.size():
			var sx := box.position.x + 2 + i * cw
			UI.btab(ci, font, Vector2(sx, y), stats[i][0], UI.TAB_HP if i < 3 else UI.STEEL, 9)
			var fl := UI.fit_line(font, stats[i][1], 15, cw - 4.0, 11)
			UI.text_at(ci, font, Vector2(sx, y + 18), fl[0], fl[1], UI.TEXT)
		y += 46.0
		ci.draw_line(Vector2(box.position.x, y), Vector2(box.end.x, y), UI.B_LINE, 1.0)
		y += 10.0
	var sks: Array = d.get("skills", [])
	var rh := 46.0 if ph else 58.0
	var rs := 52.0 if ph else 66.0
	for i in mini(3, sks.size()):
		var rt: float = m.rows[i]
		var ra := UI.ease_out(rt)
		if ra > 0.0:
			_op_skill_row(ci, Rect2(box.position.x + 40.0 * (1.0 - ra), y, box.size.x, rh), od, i, ph, ra)
		op_prects["sk%d" % i] = Rect2(box.position.x, y, box.size.x, rh)
		y += rs
	if sks.size() > op_skill and m.rows[2] >= 1.0:
		var sk: Dictionary = sks[op_skill]
		var txt: String = ("队长按 Q 释放；作为队友自动。" if sk.get("mode", "auto") == "manual" else "") + str(sk.get("desc", ""))
		var room := (box.end.y - y) if ph else maxf(52.0, box.end.y - y - (34.0 if d.has("talent") else 4.0))
		var f := UI.fit(font, txt, box.size.x - 8.0, room, [11, 10] if not ph else [10, 9])
		UI.draw_fit(ci, font, Vector2(box.position.x + 2, y - 2), f, UI.B_SUB)
		y += maxf(54.0, f.h + 10.0)
		if not ph and d.has("talent") and y + 20.0 <= box.end.y:
			var w := UI.pill(ci, font, Vector2(box.position.x + 2, y), "天赋", col, 10)
			var tf := UI.fit_line(font, str(d.talent.get("name", "")) + "  精英一解锁", 12, box.size.x - w - 8.0, 10)
			UI.text_at(ci, font, Vector2(box.position.x + 2 + w, y + 9), tf[0], tf[1], UI.TEXT, "lm")


func _op_skill_row(ci: CanvasItem, r: Rect2, od: Dictionary, i: int, compact: bool, a: float) -> void:
	var sk: Dictionary = od.def.skills[i]
	var manual: bool = sk.get("mode", "auto") == "manual"
	var sel := i == op_skill
	var h := r.size.y
	UI.bpanel(ci, r, false, sel, a, UI.VIOLET)
	var side := 28.0 if compact else 32.0
	var ix := r.position.x + 10.0
	var ic: Texture2D = A.tex(str(sk.get("icon", ""))) if str(sk.get("icon", "")) != "" else null
	if ic != null:
		ci.draw_texture_rect(ic, Rect2(ix, r.position.y + (h - side) / 2.0, side, side), false, Color(1, 1, 1, a))
	ci.draw_rect(Rect2(ix, r.end.y - 12, 14, 10), Color(0, 0, 0, 0.78 * a))
	UI.text_at(ci, font, Vector2(ix + 7, r.end.y - 7), "S%d" % (i + 1), 9, UI.fa(UI.TEXT, a), "mm")
	var tx := ix + side + 10.0
	var rx := r.end.x - 30.0
	var tag_x := rx - (100.0 if manual else 82.0)
	var nf := UI.fit_line(font, str(sk.get("name", "")), 13 if compact else 15, tag_x - tx - 6.0, 10)
	UI.text_at(ci, font, Vector2(tx, r.position.y + 7), nf[0], nf[1], UI.fa(UI.TEXT, a))
	var es: String = str(sk.get("en", ""))
	var esz := 9
	while esz > 6 and UI.en_width(font, es, esz, 1.0) > rx - 24.0 - 64.0 - tx:
		esz -= 1
	UI.en(ci, font, Vector2(tx + 2, r.position.y + (24 if compact else 28) + UI.cond(font, true).get_ascent(esz)), es, esz, UI.fa(UI.B_SUB, a), 1.0, true)
	UI.sp_ring(ci, font, Vector2(rx, r.position.y + h / 2.0 - 2.0), 13.0, 0.72, UI.CYAN if manual else UI.TEXT, "%d" % int(sk.get("sp", 0)), a)
	if manual:
		UI.pill(ci, font, Vector2(tag_x, r.position.y + 6), Pad.hint("手动 Q", "手动 Ⓐ", "手动"), UI.CYAN, 10, true, a)
		UI.text_at(ci, font, Vector2(rx - 24, r.end.y - 16), "队友时自动", 9, UI.fa(UI.B_SUB, a), "ra")
	else:
		UI.pill(ci, font, Vector2(tag_x, r.position.y + 6), "自动", UI.B_SUB, 10, false, a)
		UI.text_at(ci, font, Vector2(rx - 24, r.end.y - 16), OP_STAGE[i], 9, UI.fa(od.col, a), "ra")


## 编队页：主控受击属性 + 编队位（主控 + 两名探索中招募的队友）+ 定位标签 + 精英二条件 + 档案摘录
func _op_squad(ci: CanvasItem, box: Rect2, od: Dictionary, m: Dictionary, ph: bool) -> void:
	var d: Dictionary = od.def
	var y := box.position.y
	var stats: Array = []
	for key in ["hp", "armor", "arts", "regen"]:
		var sr: Dictionary = InitialStats.row(od.sheet, key)
		stats.append([sr.label, sr.text])
	var cw := box.size.x / 4.0
	for i in stats.size():
		var sx := box.position.x + 2 + i * cw
		UI.btab(ci, font, Vector2(sx, y), stats[i][0], UI.VIOLET if i == 0 else UI.TAB_HP, 9)
		var fl := UI.fit_line(font, stats[i][1], 13 if ph else 15, cw - 4.0, 10)
		UI.text_at(ci, font, Vector2(sx, y + 18), fl[0], fl[1], UI.TEXT)
	y += 40.0 if ph else 46.0
	ci.draw_line(Vector2(box.position.x, y), Vector2(box.end.x, y), UI.B_LINE, 1.0)
	y += 8.0 if ph else 10.0
	var sh := 34.0 if ph else 44.0
	for i in (1 if cover_pick else 3):
		var r := Rect2(box.position.x, y, box.size.x, sh)
		var a := UI.ease_out(m.rows[i])
		if a > 0.0:
			r.position.x += 40.0 * (1.0 - a)
			UI.bpanel(ci, r, false, i == 0, a, UI.VIOLET)
			if i == 0:
				var w := UI.btab(ci, font, r.position + Vector2(8, (sh - 14.0) / 2.0), "封面" if cover_pick else "队长", UI.VIOLET, 9, a)
				var nx := r.position.x + 16 + w
				UI.text_at(ci, font, Vector2(nx, r.get_center().y), od.name, 13 if ph else 15, UI.fa(UI.TEXT, a), "lm")
				UI.text_at(ci, font, Vector2(r.end.x - 10, r.get_center().y), "与博士同行" if cover_pick else "唯一受击体", 10, UI.fa(UI.B_SUB, a), "rm")
			else:
				UI.text_at(ci, font, Vector2(r.position.x + 10, r.get_center().y), "队友 %d" % i, 13, UI.fa(UI.B_SUB, a), "lm")
				UI.text_at(ci, font, Vector2(r.end.x - 10, r.get_center().y), "探索中通过升级招募", 10, UI.fa(UI.B_SUB, a), "rm")
		y += sh + 6.0
	y += 4.0
	var care: Array = Affects.care_labels(d)
	if not care.is_empty() and y + 20.0 < box.end.y:
		var cx := box.position.x + UI.btab(ci, font, Vector2(box.position.x, y + 3), "定位", UI.TAB_HP, 9) + 8.0
		for c in care:
			cx += UI.pill(ci, font, Vector2(cx, y), c, UI.PURPLE, 10)
		y += 26.0
	for n in d.get("progression", []):
		if n is Dictionary and n.get("type", "") == "elite" and int(n.get("level", 0)) == 2 and n.has("requires"):
			var req: Dictionary = n.requires
			var parts: Array = []
			if req.has("class_in_squad"):
				parts.append("编队中有%s干员" % req.class_in_squad)
			if req.has("doctor_passive"):
				var DocS = preload("res://scripts/characters/doctor.gd")
				parts.append("%s卡「%s」" % [DocS.cat_name(req.doctor_passive), DocS.PASSIVES.get(req.doctor_passive, {"name": req.doctor_passive}).name])
			for rid in req.get("relic", []):
				parts.append("藏品 #%s" % str(rid))
			if not parts.is_empty() and y + 18.0 < box.end.y:
				var f := UI.fit(font, "精英二条件：" + "、".join(parts), box.size.x, minf(36.0, box.end.y - y), [11, 10])
				y += UI.draw_fit(ci, font, Vector2(box.position.x, y), f, Color(0.8, 0.55, 1.0)) + 6.0
	var lore: String = od.lore
	if lore != "" and not ph and y + 40.0 < box.end.y:
		UI.code(ci, font, Vector2(box.position.x, y), "ARCHIVE // 档案", 8)
		var f := UI.fit(font, lore, box.size.x, box.end.y - y - 14.0, [11])
		UI.draw_fit(ci, font, Vector2(box.position.x, y + 14), f, UI.B_SUB)


## 近战 / 远程：先看图鉴标签（凯尔希是医疗但标「近战」），没有再按职业
func _op_is_melee(d: Dictionary) -> bool:
	var tags: Array = d.get("gallery", {}).get("tags", [])
	if tags.has("近战"):
		return true
	if tags.has("远程"):
		return false
	return d.get("class", "") in Character.MELEE_CLASSES


## --opmotion：按时间表驱动选人页并逐帧存图（--fixed-fps 30 时每帧 1/30 秒，录出来是真实节奏）
const OP_MOTION_SCRIPT := [[0.9, "step"], [1.9, "step"], [2.9, "tab_status"], [3.7, "tab_skill"], [4.4, "skill_row"], [5.3, "filter"], [6.2, "all"], [6.9, "go"]]
var op_motion_frame := 0
var op_motion_done := {}


func _op_motion_tick() -> void:
	var rt := t - op_motion
	for ev in OP_MOTION_SCRIPT:
		if rt >= ev[0] and not op_motion_done.has(ev[0]):
			op_motion_done[ev[0]] = true
			match ev[1]:
				"step":
					_op_step(1)
				"tab_status":
					_op_set_tab(0)
				"tab_skill":
					_op_set_tab(1)
				"skill_row":
					_op_skill_step(1)
				"filter":
					_op_filter_step(1)
				"all":
					_op_set_filter("")
				"go":
					_op_go()
	get_viewport().get_texture().get_image().save_png(_shot_dir() + "/opmotion/f_%04d.png" % op_motion_frame)
	op_motion_frame += 1
	if rt > 8.6:
		get_tree().quit()


## --titlemotion：按帧号驱动（--fixed-fps 30），[秒, 动作]
const TITLE_MOTION_SCRIPT := [[5.6, "down"], [6.3, "right"], [7.0, "down"], [7.7, "left"], [8.4, "left"], [9.1, "up"], [9.8, "up"],
	[10.6, "enter"], [12.2, "go"], [14.4, "up"], [15.3, "up"], [16.2, "down"], [17.0, "down"], [17.8, "click1"], [18.8, "end"]]
var title_motion := -1


func _title_motion_tick() -> void:
	var rt := title_motion / 30.0
	for ev in TITLE_MOTION_SCRIPT:
		if absf(rt - ev[0]) < 0.5 / 30.0:
			match ev[1]:
				"down", "up", "left", "right", "enter":
					var e := InputEventKey.new()
					e.keycode = {"down": KEY_DOWN, "up": KEY_UP, "left": KEY_LEFT, "right": KEY_RIGHT, "enter": KEY_ENTER}[ev[1]]
					e.pressed = true
					Input.parse_input_event(e)
				"go":
					_op_go()
				"click1":
					if diff_rects.has("tier1"):
						_diff_step(1 - diff_sel)
				"end":
					get_tree().quit()
	get_viewport().get_texture().get_image().save_png(_shot_dir() + "/titlemotion/f_%04d.png" % title_motion)
	title_motion += 1


## --codexmotion：按帧号驱动（--fixed-fps 30 下一帧 = 1/30 秒），每帧存一张图
func _codex_motion_tick() -> void:
	var f := codex_motion
	var steps := {15: func(): transition.switch_slash(_codex_motion_open), 75: func(): gallery._step(1), 112: func(): gallery._step(1),
		150: func(): gallery._set_info(3), 186: func(): gallery._set_info(1), 222: func(): gallery._set_info(0),
		260: func(): gallery._set_tab(1), 305: func(): gallery._step(1), 340: func(): gallery._step(1),
		378: func(): gallery._set_tab(0)}
	if steps.has(f):
		steps[f].call()
	if f > 0:
		get_viewport().get_texture().get_image().save_png(_shot_dir() + "/codexmotion/%04d.png" % f)
	codex_motion += 1
	if codex_motion > 430:
		get_tree().quit()


func _codex_motion_open() -> void:
	gallery.open()
	gallery.select_id("wisadel")   # 打开时选维什戴尔（概念图同一位干员）
	gallery._restart_open()
