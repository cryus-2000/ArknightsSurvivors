extends Control
## 标题界面：「方舟幸存者」Logo + 地图副标题 + 菜单；背景按地图（现为蓝眼泪银河沙滩 title_bg.gd，博士与水月站在浪边）

const UI = preload("res://scripts/ui.gd")
const A = preload("res://scripts/art.gd")
const D = preload("res://scripts/data.gd")
const Character = preload("res://scripts/characters/character.gd")
## 选人页的职业顺序（docs/23 §11.1）
const CLASS_ORDER := ["先锋", "近卫", "重装", "狙击", "术师", "医疗", "辅助", "特种"]

const ITEMS := [
	{"cn": "集结出发", "en": "DEPLOY"},
	{"cn": "图鉴", "en": "GALLERY"},
	{"cn": "操作说明", "en": "GUIDE"},
	{"cn": "设置", "en": "SETTINGS"},
	{"cn": "退出", "en": "EXIT"},
]
## 菜单当前项下方的一行说明（方案 A 纵向时间轴菜单）
const ITEM_SUB := ["选择干员与难度，走进深海", "干员、敌人、藏品与结局档案", "键盘、手柄与触屏操作", "画面、声音与操作设置", "离开游戏"]

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
var branches: Array = []   # [a, b, width, depth]
var nodes: Array = []      # 发光节点 [pos, phase]
var motes: Array = []
var guide := false
var credits := false
var credits_rect := Rect2()
var deploy_rect := Rect2()   # 右下「选择干员 》」主按钮
var credits_data: Dictionary = {}
var leaving := -1.0
var settings: Control
var gallery: Control
var diff_pick := false
var diff_sel := 0
var diff_rects := {}
## 选开局干员（docs/23 §14 P4）：开始探索 → 选人 → 选难度
var op_pick := false
var op_sel := 0
var op_rects := {}
var op_defs: Array = []        # [{id, def, tex, frames, lore}]
var op_scroll := 0             # 干员格滚动到第几行（干员多于可视行数时）
var op_rows_vis := 2           # 可视行数（_draw_op_pick 按面板高度算）
## 平滑滚动（2026-09-26 用户要求）：op_scroll 是目标行，op_scroll_f 每帧指数逼近它，格子按小数行偏移绘制，出入边缘时淡出
var op_scroll_f := 0.0
var op_seen_sel := -1          # 上一帧绘制时的选中项：变化时把它滚进可视区（键盘 / 手柄 / --opsel 都走这里）
var op_lore: Dictionary = {}
## 开场动画：从黑暗中浮出海滩 → 标题浮现 → 菜单依次滑入；任意按键 / 点击跳过
const INTRO_LEN := 3.4
var intro := 0.0
var title_bg: Control
var map_title := ""        # 地图副标题（data/maps/<id>.json 的 title / title_en）
var map_title_en := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	font = load("res://fonts/ui.ttf")
	tex_player = A.tex("player")
	if A.tex("player_idle") != null:
		tex_player = A.tex("player_idle")
		player_frames = max(1, tex_player.get_width() / tex_player.get_height())
	tex_light = A.tex("light")
	tex_tiles = A.tex("tiles")
	tex_bg = A.tex("title_bg")
	tex_logo = A.tex("logo")
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
	add_child(preload("res://scripts/post_fx.gd").new())
	gallery = preload("res://scripts/gallery.gd").new()
	add_child(gallery)
	settings = preload("res://scripts/settings_panel.gd").new()
	add_child(settings)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--compareshot="):
			_compare_shot(a.substr(14))
		if a.begins_with("--demoset="):
			# 截图自测：图鉴演示的阶段 / 动作（同 gallery.gd demo_stage / demo_mode）
			var dp := a.substr(10).split(",")
			gallery.demo_stage = int(dp[0])
			gallery.demo_mode = int(dp[1]) if dp.size() > 1 else -1
		if a.begins_with("--infotab="):
			gallery.info_tab = int(a.substr(10))   # 截图自测：干员详情的信息页（档案 / 技能 / 数值）
		if a.begins_with("--galleryshot="):
			var parts := a.substr(14).split(",")
			gallery.open()
			gallery.tab = int(parts[0])
			gallery._build()
			if parts.size() > 1:
				gallery.sel = int(parts[1])
			if parts.size() > 2:
				gallery.form = int(parts[2])
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
	var args := OS.get_cmdline_user_args()
	if (not args.is_empty() and not args.has("--introshot")) or Cfg.title_seen:
		intro = INTRO_LEN
	Cfg.title_seen = true
	if args.has("--introshot"):
		# 开场动画分镜截图：/tmp/claude-0/shot_intro_<n>.png
		for i in [0.5, 1.2, 1.8, 2.3, 2.8, 3.6]:
			get_tree().create_timer(i).timeout.connect(func():
				get_viewport().get_texture().get_image().save_png(_shot_dir() + "/shot_intro_%d.png" % int(i * 10)))
		get_tree().create_timer(4.0).timeout.connect(func(): get_tree().quit())
	if OS.get_cmdline_user_args().has("--settingsshot"):
		settings.open()
		get_tree().create_timer(1.0).timeout.connect(func():
			get_viewport().get_texture().get_image().save_png(_shot_dir() + "/shot_settings.png")
			get_tree().quit())
	if OS.get_cmdline_user_args().has("--opshot"):
		# 选人页截图（可选 --opsel=<n>）
		_open_op_pick()
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--opsel="):
				op_sel = clampi(int(a.substr(8)), 0, op_defs.size() - 1)
		if OS.get_cmdline_user_args().has("--opburst"):
			# 平滑滚动自测：开页后 0.05–0.4 秒连拍 8 张（选中项在可视区外时能看到滚动过程）
			for bi in 8:
				get_tree().create_timer(0.05 + bi * 0.05).timeout.connect(func():
					get_viewport().get_texture().get_image().save_png(_shot_dir() + "/shot_oppick_%d.png" % bi))
		get_tree().create_timer(1.2).timeout.connect(func():
			get_viewport().get_texture().get_image().save_png(_shot_dir() + "/shot_oppick.png")
			get_tree().quit())
	if OS.get_cmdline_user_args().has("--titleshot"):
		get_tree().create_timer(2.0).timeout.connect(func():
			get_viewport().get_texture().get_image().save_png(_shot_dir() + "/shot_title.png")
			get_tree().quit())
	if OS.get_cmdline_user_args().has("--autotest") or OS.get_cmdline_user_args().has("--balance"):
		get_tree().change_scene_to_file.call_deferred("res://game.tscn")


func _diff_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_LEFT, KEY_A:
				_diff_step(-1)
			KEY_RIGHT, KEY_D:
				_diff_step(1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_diff_go()
			KEY_ESCAPE, KEY_BACKSPACE:
				diff_pick = false
				Sfx.play("ui_move")
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for k in diff_rects:
			if diff_rects[k].has_point(event.position):
				match k:
					"left":
						_diff_step(-1)
					"right":
						_diff_step(1)
					"go":
						_diff_go()
					"back":
						diff_pick = false
				return


func _diff_step(d: int) -> void:
	var n := clampi(diff_sel + d, 0, D.DIFFICULTY.size() - 1)
	if n > Cfg.diff_unlocked:
		Sfx.play("ui_move", -4.0, 0.6)
		return
	if n != diff_sel:
		diff_sel = n
		Sfx.play("ui_move")


func _diff_go() -> void:
	Cfg.difficulty = diff_sel
	Cfg.save()
	diff_pick = false
	Sfx.play("start")
	leaving = 0.0


## 难度选择：左右切换，列出所有逐级叠加的效果
func _draw_diff(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.02, 0.04, 0.82))
	var r := Rect2(vs.x / 2 - 380, 60, 760, vs.y - 120)
	var col := UI.CYAN.lerp(UI.RED, float(diff_sel) / (D.DIFFICULTY.size() - 1))
	UI.panel(self, r, UI.BG2, Color(col.r, col.g, col.b, 0.6), 16.0, col)
	UI.en(self, font, r.position + Vector2(36, 42), "DIFFICULTY", 13, col, 4.0)
	UI.text(self, font, r.position + Vector2(36, 80), "选择难度", 26, UI.TEXT)
	# 当前难度
	var c := Vector2(r.get_center().x, r.position.y + 150)
	diff_rects.clear()
	diff_rects["left"] = Rect2(c + Vector2(-200, -30), Vector2(50, 60))
	diff_rects["right"] = Rect2(c + Vector2(150, -30), Vector2(50, 60))
	UI.text(self, font, c + Vector2(-200, 12), "◀", 30, UI.TEXT if diff_sel > 0 else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 50)
	UI.text(self, font, c + Vector2(150, 12), "▶", 30, UI.TEXT if diff_sel < Cfg.diff_unlocked else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 50)
	UI.diamond(self, c + Vector2(0, -2), 44.0, Color(col.r, col.g, col.b, 0.15))
	UI.diamond(self, c + Vector2(0, -2), 36.0, Color(0.02, 0.06, 0.08), col)
	UI.text(self, font, c + Vector2(-40, 14), str(diff_sel), 34, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 80)
	UI.text(self, font, c + Vector2(-150, 68), D.DIFFICULTY[diff_sel].name, 20, col, HORIZONTAL_ALIGNMENT_CENTER, 300)
	# 效果列表
	var y := r.position.y + 262
	for i in range(1, D.DIFFICULTY.size()):
		var on := i <= diff_sel
		var locked := i > Cfg.diff_unlocked
		var x := r.position.x + 60 + ((i - 1) / 5) * 340
		var yy := y + ((i - 1) % 5) * 34
		var ic := col if on else (Color(0.3, 0.36, 0.4) if locked else UI.SUB)
		UI.diamond(self, Vector2(x, yy - 6), 5.0, ic if on else Color(0, 0, 0, 0), ic)
		UI.text(self, font, Vector2(x + 16, yy), "%d  %s" % [i, D.DIFFICULTY[i].desc] if not locked else "%d  通关难度 %d 后解锁" % [i, i - 1], 14, UI.TEXT if on else ic)
	# 按钮
	var go := Rect2(r.get_center().x - 170, r.end.y - 70, 160, 44)
	var back := Rect2(r.get_center().x + 10, r.end.y - 70, 160, 44)
	diff_rects["go"] = go
	diff_rects["back"] = back
	UI.panel(self, go, Color(0.05, 0.2, 0.24, 0.9), col, 8.0, col)
	UI.text(self, font, go.position + Vector2(0, 29), Pad.hint("出发  Enter", "出发  Ⓐ"), 17, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, go.size.x)
	UI.panel(self, back, Color(0.02, 0.06, 0.09, 0.8), UI.LINE, 8.0)
	UI.text(self, font, back.position + Vector2(0, 29), Pad.hint("返回  Esc", "返回  Ⓑ"), 17, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, back.size.x)


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
	t += delta
	op_scroll_f = lerpf(op_scroll_f, float(op_scroll), 1.0 - exp(-14.0 * delta))
	if absf(op_scroll_f - op_scroll) < 0.002:
		op_scroll_f = float(op_scroll)
	if intro < INTRO_LEN:
		intro = minf(intro + delta, INTRO_LEN)
	# 背景：开场时从 1.12 倍缓缓拉远到 1.0
	if title_bg != null:
		title_bg.zoom = 1.0 + 0.12 * (1.0 - _ease(intro / 2.2))
	for m in motes:
		m[0].y -= m[1] * delta
		if m[0].y < -10:
			m[0].y = size.y + 10
	if leaving >= 0.0:
		leaving += delta
		if leaving > 0.7:
			get_tree().change_scene_to_file("res://game.tscn")
	queue_redraw()


func _input(event: InputEvent) -> void:
	if leaving >= 0.0 or settings.visible or gallery.visible:
		return
	if intro < INTRO_LEN:
		# 开场动画中：按键 / 点击直接跳到完成态，本次输入不再传给菜单
		if (event is InputEventKey and event.pressed and not event.echo) \
				or (event is InputEventMouseButton and event.pressed):
			intro = INTRO_LEN
		return
	if diff_pick:
		_diff_input(event)
		return
	if op_pick:
		_op_input(event)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if guide or credits:
			guide = false
			credits = false
			Sfx.play("ui_ok")
			return
		match event.keycode:
			KEY_UP, KEY_W:
				sel = (sel + ITEMS.size() - 1) % ITEMS.size()
				Sfx.play("ui_move")
			KEY_DOWN, KEY_S:
				sel = (sel + 1) % ITEMS.size()
				Sfx.play("ui_move")
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_activate(sel)
	elif event is InputEventMouseMotion:
		for i in item_rects.size():
			if item_rects[i].has_point(event.position) and sel != i:
				sel = i
				Sfx.play("ui_move")
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if guide or credits:
			guide = false
			credits = false
			return
		if credits_rect.has_point(event.position):
			credits = true
			Sfx.play("ui_ok")
			return
		if deploy_rect.has_point(event.position):
			_activate(0)
			return
		for i in item_rects.size():
			if item_rects[i].has_point(event.position):
				_activate(i)


func _activate(i: int) -> void:
	match i:
		0:
			Sfx.play("ui_ok")
			_open_op_pick()
		1:
			Sfx.play("ui_ok")
			gallery.open()
		2:
			Sfx.play("ui_ok")
			guide = true
		3:
			Sfx.play("ui_ok")
			settings.open()
		4:
			get_tree().quit()


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
	# 左侧柔和暗角：让标题与菜单浮在星空上，不与银河抢
	var vg := _ease(intro / 1.6)
	for i in 14:
		var a := 0.42 * pow(1.0 - i / 14.0, 1.6) * vg
		draw_rect(Rect2(i * 46.0, 0, 46.0, vs.y), Color(0.0, 0.01, 0.03, a))
	# 顶部小标（方案 A）：本作徽记 + 英文
	var hf0 := _seg(0.9, 0.5)
	_draw_emblem(Vector2(tx + 8, 44), 8.0, _fa(Color(0.76, 0.79, 0.81), hf0))
	UI.en(self, font, Vector2(tx + 24, 49), "ARKNIGHTS FAN GAME  ·  ROGUELIKE SURVIVORS", 11, _fa(Color(0.55, 0.59, 0.63), hf0), 2.5)
	# 标题（像素 Logo）：1.0s 起浮现（上浮 + 淡入），副标题稍后跟上
	var lg := _seg(1.0, 0.8)
	var ly := 24.0 * (1.0 - lg)
	if tex_logo != null:
		var ls := Vector2(tex_logo.get_width(), tex_logo.get_height())
		var k: float = min(520.0 / ls.x, 130.0 / ls.y)
		draw_texture_rect(tex_logo, Rect2(Vector2(tx, 84 + ly), ls * k), false, Color(1, 1, 1, lg))
	else:
		UI.text(self, font, Vector2(tx, 182 + ly), "方舟", 96, _fa(UI.TEXT, lg))
		UI.text(self, font, Vector2(tx + 210, 180 + ly), "幸存者", 40, _fa(UI.CYAN, lg))
	UI.en(self, font, Vector2(tx + 6, 242 + ly), "ARKNIGHTS  SURVIVORS", 15, _fa(Color(0.76, 0.79, 0.81), _seg(1.5, 0.5)), 5.0)
	# 地图副标题：随地图变化，英文副标题下一行（菱形 + 中文名 + 英文名），和 Logo 组成一块
	if map_title != "":
		var mf2 := _seg(1.7, 0.5)
		UI.diamond(self, Vector2(tx + 11, 257 + ly), 4.0, _fa(UI.CYAN, mf2))
		UI.text(self, font, Vector2(tx + 22, 263 + ly), map_title, 15, _fa(UI.TEXT, mf2))
		if map_title_en != "":
			var mw: float = font.get_string_size(map_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			UI.en(self, font, Vector2(tx + 34 + mw, 262 + ly), map_title_en, 10, _fa(Color(0.5, 0.54, 0.58), mf2), 2.5)
	# 分隔线：1.6s 起从左向右划出，右端一个小方块
	var rl := _seg(1.6, 0.6)
	var ry := 282.0
	if rl > 0.0:
		UI.hairline(self, Vector2(tx, ry), Vector2(tx + 420 * rl, ry), Color(1, 1, 1), 0.32, 0.14)
		draw_rect(Rect2(Vector2(tx + 420 * rl - 2, ry - 2), Vector2(5, 5)), Color(1, 1, 1, 0.55 * rl))

	# 菜单（原作「主题选择」左侧的纵向时间轴）：一条竖细线串起各项；当前项实心圆点 + 外圈、白字 + 青色英文 + 一行说明
	item_rects.clear()
	var compact: bool = vs.y < 680.0   # 触屏放大后的紧凑排版
	var my := 300.0 if compact else 318.0
	var step := 52.0 if compact else 58.0
	var lx := tx + 4.0
	var mf0 := _seg(1.9, 0.5)
	if mf0 > 0.0:
		var y0 := my - 8.0
		var y1 := my + (ITEMS.size() - 1) * step + 46.0
		draw_rect(Rect2(Vector2(lx, y0), Vector2(1, (y1 - y0) * mf0)), Color(1, 1, 1, 0.22))
		draw_rect(Rect2(Vector2(lx - 2, y0 - 4), Vector2(5, 5)), Color(1, 1, 1, 0.55 * mf0))
		if mf0 >= 1.0:
			draw_rect(Rect2(Vector2(lx - 2, y1), Vector2(5, 5)), Color(1, 1, 1, 0.55))
	for i in ITEMS.size():
		var r := Rect2(tx - 10, my + i * step, 330, 48)
		item_rects.append(r)
		var f := _seg(2.0 + i * 0.12, 0.35)
		if f <= 0.0:
			continue
		var dx := -30.0 * (1.0 - f)
		var on := i == sel
		var cy := r.position.y + 20.0
		if on:
			var b0 := Color(0.03, 0.035, 0.045, 0.72 * f)
			var b1 := Color(0.03, 0.035, 0.045, 0.0)
			draw_polygon(PackedVector2Array([Vector2(lx + 8 + dx, r.position.y - 4), Vector2(lx + 340 + dx, r.position.y - 4), Vector2(lx + 340 + dx, r.end.y + 8), Vector2(lx + 8 + dx, r.end.y + 8)]), PackedColorArray([b0, b1, b1, b0]))
			draw_circle(Vector2(lx + 0.5, cy), 5.5, _fa(UI.TEXT, f))
			draw_arc(Vector2(lx + 0.5, cy), 10.0, 0.0, TAU, 28, _fa(Color(1, 1, 1, 0.4), f), 1.0)
		else:
			draw_circle(Vector2(lx + 0.5, cy), 4.0, _fa(Color(0.04, 0.05, 0.06), f))
			draw_arc(Vector2(lx + 0.5, cy), 4.0, 0.0, TAU, 16, _fa(Color(1, 1, 1, 0.5), f), 1.2)
			draw_line(Vector2(lx + 7, cy), Vector2(lx + 13, cy), _fa(Color(1, 1, 1, 0.3), f), 1.0)
		var tx2 := lx + 26.0 + dx
		var cn: String = ITEMS[i].cn
		var fs := 24 if on else 20
		UI.text(self, font, Vector2(tx2, cy + (9 if on else 7)), cn, fs, _fa(UI.TEXT if on else Color(0.76, 0.79, 0.81), f))
		var cw: float = font.get_string_size(cn, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		UI.en(self, font, Vector2(tx2 + cw + 14, cy + 6), ITEMS[i].en, 12, _fa(UI.CYAN if on else Color(0.41, 0.45, 0.49), f), 3.5)
		if on:
			UI.text(self, font, Vector2(tx2, cy + 30), ITEM_SUB[i], 12, _fa(UI.SUB, f))
	# 操作提示
	var hf := _seg(2.7, 0.5)
	if hf > 0.0 and not diff_pick and not op_pick:
		var hy := my + ITEMS.size() * step + 12
		UI.en(self, font, Vector2(tx + 2, hy), Pad.hint("W / S  ·  ↑ ↓   SELECT        ENTER   CONFIRM", "STICK  ·  D-PAD   SELECT        Ⓐ   CONFIRM"), 11, _fa(Color(0.4, 0.44, 0.48), hf), 2.0)
	# 右下主按钮（原作主题页的「进入主题 》」）：READY TO DEPLOY / 选择干员 》
	var df := _seg(2.6, 0.5)
	deploy_rect = Rect2()
	if df > 0.0 and not diff_pick and not op_pick:
		var bx := vs.x - 240.0
		var by := vs.y - 98.0
		deploy_rect = Rect2(Vector2(bx - 8, by + 8), Vector2(214, 50))
		var dh := deploy_rect.has_point(get_local_mouse_position()) and intro >= INTRO_LEN
		UI.en(self, font, Vector2(bx, by), "READY TO DEPLOY", 11, _fa(UI.CYAN, df), 3.5)
		_draw_emblem(Vector2(bx + 14, by + 33), 14.0, _fa(UI.TEXT, df))
		UI.text(self, font, Vector2(bx + 40, by + 42), "选择干员", 22, _fa(UI.TEXT, df))
		UI.text(self, font, Vector2(bx + 138, by + 41), "》", 22, _fa(UI.CYAN if dh else Color(0.81, 0.84, 0.85), df))
		draw_rect(Rect2(Vector2(bx, by + 56), Vector2(192, 1)), _fa(Color(1, 1, 1, 0.3), df))
		draw_rect(Rect2(Vector2(bx, by + 55), Vector2(28.0 + (44.0 if dh else 0.0), 3)), _fa(UI.CYAN, df))

	# 页脚：最后淡入
	var ff := _seg(2.8, 0.5)
	credits_rect = Rect2(tx - 6, vs.y - 38, 300, 26)
	var cr_hover := credits_rect.has_point(get_local_mouse_position()) and intro >= INTRO_LEN
	UI.text(self, font, Vector2(tx, vs.y - 20), "明日方舟同人作品 · 非商业  ·  致谢与声明 ›", 13, _fa(UI.CYAN if cr_hover else Color(0.5, 0.54, 0.58), ff))
	UI.en(self, font, Vector2(vs.x - 110, vs.y - 20), "v2.0", 13, _fa(Color(0.5, 0.54, 0.58), ff), 2.0)

	# 开场：黑幕淡出 + 上下黑边收起
	if intro < INTRO_LEN:
		var dark := 1.0 - _ease(intro / 1.6)
		if dark > 0.0:
			draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.005, 0.015, dark))
		var bar := 90.0 * (1.0 - _seg(0.3, 1.5))
		if bar > 0.5:
			draw_rect(Rect2(0, 0, vs.x, bar), Color(0, 0.005, 0.015))
			draw_rect(Rect2(0, vs.y - bar, vs.x, bar), Color(0, 0.005, 0.015))

	if guide:
		_draw_guide(vs)
	if credits:
		_draw_credits(vs)
	if op_pick:
		_draw_op_pick(vs)
	if diff_pick:
		_draw_diff(vs)
	if leaving >= 0.0:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.01, 0.02, clamp(leaving / 0.6, 0.0, 1.0)))


## 本作徽记（菱形 + 一道浪）：标题页小标与主按钮用（不用原作的集成战略标志）
func _draw_emblem(c: Vector2, r: float, col: Color) -> void:
	draw_polyline(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0), c + Vector2(0, -r)]), col, 1.4)
	var w := PackedVector2Array()
	for k in 13:
		var u := k / 12.0
		w.append(c + Vector2(-r * 0.55 + u * r * 1.1, sin(u * TAU) * r * 0.16 + r * 0.06))
	draw_polyline(w, col, 1.4)


func _draw_guide(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.02, 0.04, 0.75))
	# 面板 880 宽：说明列 654px，最长一行（手柄）也放得下；再长就按宽度缩字号（text_fit），不会伸出面板
	var r := Rect2(vs.x / 2 - 440, vs.y / 2 - 230, 880, 460)
	UI.panel(self, r, UI.BG2, UI.CYAN_DIM, 16.0, UI.CYAN)
	UI.text(self, font, r.position + Vector2(36, 56), "操作说明", 28, UI.TEXT)
	UI.en(self, font, r.position + Vector2(36 + font.get_string_size("操作说明", HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x + 18, 54), "GUIDE", 13, UI.CYAN, 3.0)
	var lines := [
		["移动", "WASD / 方向键；空格冲刺（无敌，冷却 1.2 秒）；Q 放手动技能"],
		["攻击", "全自动：编队干员跟在主控身边普攻，三个技能各自充能后自动释放"],
		["编队", "升级时选干员深度卡成长、精英化解锁新技能；Lv5 起可招募，最多 3 人"],
		["灯火", "受击时熄灭一截，拾取灯油补充；过低时敌人变强"],
		["升级 / 藏品", "按 1 / 2 / 3 或点击选择"],
		["属性 / 暂停", "Tab 或 C 查看属性　　Esc 暂停　　M 静音　　R 重来　　T 回标题"],
		["手柄", "左摇杆移动　Ⓐ 确认　Ⓑ 返回　START 暂停　SELECT 属性　LB / RB 翻页"],
	]
	for i in lines.size():
		var y := r.position.y + 106 + i * 46
		UI.diamond(self, Vector2(r.position.x + 44, y - 7), 4.0, UI.CYAN)
		UI.text(self, font, Vector2(r.position.x + 60, y), lines[i][0], 18, UI.CYAN)
		UI.text_fit(self, font, Vector2(r.position.x + 190, y), lines[i][1], 17, UI.TEXT, r.size.x - 190 - 36, 13)
	UI.text(self, font, Vector2(r.position.x, r.end.y - 24), Pad.hint("按任意键返回", "按任意键返回（Ⓐ / Ⓑ）"), 14, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


## 致谢与声明：内容来自 data/credits.json。左列条目名（长的折两行，不再压到右列）、右列说明 + 链接；
## 面板 960 宽，整页按屏幕高度挑字号（14 → 13 → 12，间距跟着收），16:9 下也能整页放下、标题和底部提示不被裁掉。
## 说明按像素宽度排版（docs/37，UI.fit 自带防孤字，「成。」这样的单字不会单独掉一行）
const CREDITS_W := 960.0
const CREDITS_LX := 58.0       # 条目名左边（菱形在它左边）
const CREDITS_LW := 150.0      # 条目名列宽
const CREDITS_HEAD := 84.0     # 标题区高度
const CREDITS_FOOT := 58.0     # 底部声明 + 返回提示


func _draw_credits(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.02, 0.04, 0.9))
	var secs: Array = credits_data.get("sections", [])
	var pw: float = minf(CREDITS_W, vs.x - 48.0)
	var tx: float = CREDITS_LX + CREDITS_LW + 16.0
	var tw: float = pw - tx - 36.0
	var lay: Dictionary = {}
	for fs in [14, 13, 12]:
		lay = _credits_layout(secs, fs, tw)
		if CREDITS_HEAD + lay.h + CREDITS_FOOT <= vs.y - 32.0:
			break
	var h: float = CREDITS_HEAD + lay.h + CREDITS_FOOT
	var r := Rect2(roundf(vs.x / 2 - pw / 2), roundf(maxf(16.0, vs.y / 2 - h / 2)), pw, h)
	UI.panel(self, r, UI.BG2, UI.CYAN_DIM, 16.0, UI.CYAN)
	var title: String = credits_data.get("title", "致谢与声明")
	UI.text(self, font, r.position + Vector2(36, 52), title, 26, UI.TEXT)
	UI.en(self, font, r.position + Vector2(36 + font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x + 18, 50), credits_data.get("en", "CREDITS"), 12, UI.CYAN, 3.0)
	UI.rule(self, r.position + Vector2(36, 68), r.position + Vector2(pw - 36, 68), UI.EDGE_DIM)
	var y: float = r.position.y + CREDITS_HEAD
	for row in lay.rows:
		UI.diamond(self, Vector2(r.position.x + 44, y + 9), 4.0, UI.CYAN)
		UI.draw_fit(self, font, Vector2(r.position.x + CREDITS_LX, y), row.label, UI.CYAN)
		var th: float = UI.draw_fit(self, font, Vector2(r.position.x + tx, y + 1), row.text, UI.TEXT)
		if row.link != "":
			UI.text_fit(self, font, Vector2(r.position.x + tx, y + 1 + th + 4 + font.get_ascent(12)), row.link, 12, Color(0.5, 0.75, 0.85), tw, 10)
		y += row.h
	var ft := UI.fit_line(font, credits_data.get("footer", ""), 13, pw - 72, 11)
	UI.text(self, font, Vector2(r.position.x, r.end.y - 34), ft[0], ft[1], UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	UI.text(self, font, Vector2(r.position.x, r.end.y - 14), Pad.hint("按任意键返回", "按任意键返回（Ⓐ / Ⓑ）"), 12, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


## 致谢页排版：每条 {label: 条目名 fit, text: 说明 fit, link, h}；返回 {rows, h}
func _credits_layout(secs: Array, fs: int, tw: float) -> Dictionary:
	var rows: Array = []
	var total := 0.0
	var gap: float = fs - 1.0
	for sec in secs:
		# 条目名：先试一行（最小 13 号），放不下再折成两行，按半长折开（「第三方开放许可 / 特效素材」）
		var lab := UI.fit(font, sec[0], CREDITS_LW, font.get_height(15), [15, 14, 13])
		if not lab.fit:
			var half: float = font.get_string_size(sec[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x / 2.0 + 14.0
			lab = UI.fit(font, sec[0], minf(CREDITS_LW, half), 2.0 * font.get_height(14), [14, 13])
		var txt := UI.fit(font, sec[1], tw, 9999.0, [fs])   # UI.fit 自带防孤字
		var link: String = sec[2] if sec.size() > 2 else ""
		var rh: float = maxf(float(lab.h), float(txt.h) + (4.0 + font.get_height(12) if link != "" else 0.0)) + gap
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
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			return a.substr(10)
	return "/tmp/claude-0"


# =====================================================================
# 选开局干员：data/characters/*.json 里 recruitable 的干员按职业排列；选中后进入选难度
# =====================================================================
func _open_op_pick() -> void:
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
			op_defs.append({"id": cid, "def": d, "tex": tx, "frames": frames, "lore": op_lore.get(cid, {}).get("lore", "")})
		op_defs.sort_custom(func(a, b):
			var ca: int = CLASS_ORDER.find(a.def.get("class", ""))
			var cb: int = CLASS_ORDER.find(b.def.get("class", ""))
			return ca < cb if ca != cb else a.id < b.id)
	op_sel = 0
	for i in op_defs.size():
		if op_defs[i].id == Cfg.character_id:
			op_sel = i
	op_scroll = 0
	op_scroll_f = 0.0
	op_seen_sel = -1
	op_pick = true


func _op_input(event: InputEvent) -> void:
	var cols := 4
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_LEFT, KEY_A:
				_op_step(-1)
			KEY_RIGHT, KEY_D:
				_op_step(1)
			KEY_UP, KEY_W:
				_op_step(-cols)
			KEY_DOWN, KEY_S:
				_op_step(cols)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_op_go()
			KEY_ESCAPE, KEY_BACKSPACE:
				op_pick = false
				Sfx.play("ui_move")
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_op_scroll_by(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for k in op_rects:
			if op_rects[k].has_point(event.position):
				if k is int:
					if op_sel == k:
						_op_go()
					else:
						op_sel = k
						Sfx.play("ui_move")
				elif k == "go":
					_op_go()
				elif k == "back":
					op_pick = false
					Sfx.play("ui_move")
				return


func _op_step(d: int) -> void:
	var n := clampi(op_sel + d, 0, op_defs.size() - 1)
	if n != op_sel:
		op_sel = n
		Sfx.play("ui_move")


## 选中项滚进可视区
func _op_follow() -> void:
	var row: int = op_sel / 4
	if row < op_scroll:
		op_scroll = row
	elif row >= op_scroll + op_rows_vis:
		op_scroll = row - op_rows_vis + 1


func _op_scroll_by(d: int) -> void:
	var rows: int = ceili(op_defs.size() / 4.0)
	var n := clampi(op_scroll + d, 0, maxi(0, rows - op_rows_vis))
	if n != op_scroll:
		op_scroll = n
		Sfx.play("ui_move")


func _op_go() -> void:
	Cfg.character_id = op_defs[op_sel].id
	Cfg.save()
	Sfx.play("ui_ok")
	op_pick = false
	diff_pick = true
	diff_sel = clampi(Cfg.difficulty, 0, Cfg.diff_unlocked)


## 选人页：左侧 4×2 干员格（待机动画 + 名字 + 职业），右侧详情（普攻 / 技能 / 天赋 / 档案）
func _draw_op_pick(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.02, 0.04, 0.82))
	var r := Rect2(vs.x / 2 - 560, 40, 1120, vs.y - 80)
	var cur: Dictionary = op_defs[op_sel]
	var d: Dictionary = cur.def
	var col: Color = Character.CLASS_COL.get(d.get("class", ""), UI.CYAN)
	UI.panel(self, r, UI.BG2, Color(col.r, col.g, col.b, 0.6), 16.0, col)
	UI.en(self, font, r.position + Vector2(36, 42), "OPERATOR", 13, col, 4.0)
	UI.text(self, font, r.position + Vector2(36, 80), "选择开局干员", 26, UI.TEXT)
	UI.text(self, font, r.position + Vector2(220, 80), "其余干员在探索中通过升级招募", 13, UI.SUB)
	op_rects.clear()
	# ---- 左：干员格
	var cols := 4
	var cw := 128.0
	var chh := 134.0
	var gx := r.position.x + 36
	var gy := r.position.y + 110
	# 可视行数 = 格区高度（到按钮上沿）能放下的整行；干员更多时按行滚动（滚轮 / 方向键跟随选中）
	var grid_bottom := r.end.y - 96
	op_rows_vis = maxi(1, int((grid_bottom - gy + 10) / (chh + 10)))
	var rows: int = ceili(op_defs.size() / float(cols))
	if op_sel != op_seen_sel:
		op_seen_sel = op_sel
		_op_follow()
	op_scroll = clampi(op_scroll, 0, maxi(0, rows - op_rows_vis))
	if rows > op_rows_vis:
		# 滚动条：格区右侧细条
		var sx := gx + cols * (cw + 10) - 4
		var track := Rect2(sx, gy, 4, op_rows_vis * (chh + 10) - 10)
		draw_rect(track, Color(1, 1, 1, 0.06))
		var th: float = track.size.y * op_rows_vis / rows
		draw_rect(Rect2(sx, gy + (track.size.y - th) * clampf(op_scroll_f / float(rows - op_rows_vis), 0.0, 1.0), 4, th), Color(col.r, col.g, col.b, 0.7))
		if op_scroll > 0:
			UI.text(self, font, Vector2(gx, gy - 8), "▲ 滚轮查看更多", 11, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, cols * (cw + 10) - 10)
		if op_scroll < rows - op_rows_vis:
			UI.text(self, font, Vector2(gx, gy + op_rows_vis * (chh + 10) + 6), "▼ 还有 %d 名干员" % (op_defs.size() - (op_scroll + op_rows_vis) * cols), 11, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, cols * (cw + 10) - 10)
	for i in op_defs.size():
		var od: Dictionary = op_defs[i]
		# 小数行位置：滚动中的格子按 op_scroll_f 平移；超出可视区的部分按越界程度淡出，完全出界不画
		var row: float = i / cols - op_scroll_f
		var fa: float = 1.0
		if row < 0.0:
			fa = clampf(1.0 + row * 1.6, 0.0, 1.0)
		elif row > op_rows_vis - 1:
			fa = clampf(1.0 - (row - (op_rows_vis - 1)) * 1.6, 0.0, 1.0)
		if fa <= 0.01:
			continue
		var cr := Rect2(gx + (i % cols) * (cw + 10), gy + row * (chh + 10), cw, chh)
		if fa > 0.6:
			op_rects[i] = cr
		var on := i == op_sel
		var oc: Color = Character.CLASS_COL.get(od.def.get("class", ""), UI.CYAN)
		var hov := cr.has_point(get_local_mouse_position()) and fa > 0.6
		UI.panel(self, cr, _fa(Color(0.03, 0.09, 0.12, 0.9) if on else Color(0.02, 0.05, 0.08, 0.8), fa), _fa(oc if on else (Color(oc.r, oc.g, oc.b, 0.5) if hov else UI.LINE), fa), 10.0, _fa(oc, fa) if on else Color(0, 0, 0, 0))
		var tx: Texture2D = od.tex
		if tx != null:
			var fh := tx.get_height()
			var fw := tx.get_width() / int(od.frames)
			var fr := int(t * 4.0 + i) % int(od.frames)
			var sc := 2.0 / A.hires_of(tx)
			var pos := Vector2(cr.get_center().x - fw * sc / 2.0, cr.position.y + 84 - fh * sc + 6.0 * sc)
			if on:
				draw_set_transform(pos + Vector2(fw * sc / 2.0, fh * sc - 4.0 * sc), 0.0, Vector2(1.0, 0.4))
				draw_circle(Vector2.ZERO, 26.0, Color(oc.r, oc.g, oc.b, 0.18 * fa))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			draw_texture_rect_region(tx, Rect2(pos, Vector2(fw, fh) * sc), Rect2(fw * fr, 0, fw, fh), _fa(Color.WHITE if on or hov else Color(0.75, 0.8, 0.85), fa))
		UI.text(self, font, cr.position + Vector2(0, 104), od.def.get("name", od.id), 15, _fa(UI.TEXT if on else Color(0.7, 0.8, 0.85), fa), HORIZONTAL_ALIGNMENT_CENTER, cw)
		UI.text(self, font, cr.position + Vector2(0, 122), od.def.get("class", ""), 12, _fa(oc if on else UI.SUB, fa), HORIZONTAL_ALIGNMENT_CENTER, cw)
	# ---- 右：详情
	var dx := r.position.x + 36 + cols * (cw + 10) + 24
	var dr := Rect2(dx, gy, r.end.x - 36 - dx, r.end.y - 96 - gy)
	UI.panel(self, dr, Color(0.02, 0.05, 0.08, 0.7), Color(col.r, col.g, col.b, 0.35), 12.0)
	var px := dr.position.x + 24
	var py := dr.position.y + 34
	UI.en(self, font, Vector2(px, py), d.get("en", ""), 12, col, 3.0)
	UI.text(self, font, Vector2(px, py + 40), d.get("name", cur.id), 30, UI.TEXT)
	var cx := px + 150
	cx += UI.chip(self, font, Vector2(cx, py + 18), d.get("class", ""), col, 12) + 8
	for tg in d.get("gallery", {}).get("tags", []):
		cx += UI.chip(self, font, Vector2(cx, py + 18), tg, UI.PURPLE, 11) + 6
	# 当主控时的受击属性（JSON leader 段，按原作精二满级换算）：标签下面一行
	var ld: Dictionary = d.get("leader", {})
	if not ld.is_empty():
		UI.text_fit(self, font, Vector2(px + 150, py + 58), "主控　生命 %d · 回复 %.1f/秒 · 减伤 %s · 法抗 %d%%" % [int(ld.get("max_hp", 120)), float(ld.get("regen", 1.0)), str(snappedf(float(ld.get("armor", 0.0)), 0.5)), int(round(float(ld.get("arts_res", 0.0)) * 100.0))], 13, Color(col.r, col.g, col.b, 0.95), dr.end.x - 24.0 - (px + 150))
	py += 74
	UI.rule(self, Vector2(px, py), Vector2(dr.end.x - 24, py), UI.EDGE_DIM)
	py += 18
	var lines: Array = []
	if d.has("attack"):
		lines.append(["普攻", d.attack.get("name", ""), d.attack.get("desc", "")])
	var sks: Array = d.get("skills", [])
	for si in sks.size():
		lines.append(["S%d" % (si + 1), "%s%s" % [sks[si].get("name", ""), ("（充能 %d · %s）" % [int(sks[si].sp), ["招募", "精一", "精二"][si]]) if sks[si].has("sp") else ""], sks[si].get("desc", ""), sks[si].get("icon", "")])
	if d.has("talent"):
		lines.append(["天赋", d.talent.get("name", ""), d.talent.get("desc", "")])
	for ln in lines:
		# 技能行：左边画技能图标（32px 原尺寸），名字与说明右移；普攻 / 天赋仍是小标签
		var itx: Texture2D = A.tex(ln[3]) if ln.size() > 3 and ln[3] != "" else null
		var ix := 0.0
		if itx != null:
			draw_texture_rect(itx, Rect2(Vector2(px, py - 3), Vector2(32, 32)), false)
			ix = 44.0
			UI.text(self, font, Vector2(px + ix, py + 15), ln[1], 15, UI.TEXT)
		else:
			UI.chip(self, font, Vector2(px, py), ln[0], col, 11)
			UI.text(self, font, Vector2(px + 52, py + 15), ln[1], 15, UI.TEXT)
		py += 22
		py += maxf(_wrap_text(Vector2(px + ix, py + 12), ln[2], 12, UI.SUB, dr.size.x - 48 - ix, 2), 12.0 if itx != null else 0.0) + 8
	# 精二条件
	for n in d.get("progression", []):
		if n.get("type", "") == "elite" and int(n.get("level", 0)) == 2 and n.has("requires"):
			var req: Dictionary = n.requires
			var parts: Array = []
			if req.has("class_in_squad"):
				parts.append("编队中有%s干员" % req.class_in_squad)
			if req.has("doctor_passive"):
				parts.append("博士被动「%s」" % preload("res://scripts/characters/doctor.gd").PASSIVES.get(req.doctor_passive, {"name": req.doctor_passive}).name)
			for rid in req.get("relic", []):
				parts.append("藏品 #%s" % str(rid))
			if not parts.is_empty():
				UI.text(self, font, Vector2(px, py + 12), "精英化二条件：" + "、".join(parts), 12, Color(0.8, 0.55, 1.0))
				py += 26
	# 档案：只画面板剩余高度放得下的行数
	if cur.lore != "":
		py += 6
		UI.rule(self, Vector2(px, py), Vector2(dr.end.x - 24, py), UI.EDGE_DIM)
		py += 10
		var max_lines: int = int((dr.end.y - 16 - py) / 19.0)
		if max_lines >= 1:
			_wrap_text(Vector2(px, py + 14), cur.lore, 13, Color(0.7, 0.8, 0.85), dr.size.x - 48, max_lines)
	# ---- 按钮
	var go := Rect2(r.get_center().x - 170, r.end.y - 70, 160, 44)
	var back := Rect2(r.get_center().x + 10, r.end.y - 70, 160, 44)
	op_rects["go"] = go
	op_rects["back"] = back
	# 方案 A：主操作青底深字，返回为暗底细边
	var mp := get_local_mouse_position()
	UI.button(self, font, go, Pad.hint("下一步  Enter", "下一步  Ⓐ"), "primary", go.has_point(mp), 17)
	UI.button(self, font, back, Pad.hint("返回  Esc", "返回  Ⓑ"), "outline", back.has_point(mp), 17)
	UI.en(self, font, Vector2(r.position.x + 36, r.end.y - 43), "WASD / ARROWS  SELECT     ENTER  NEXT", 11, Color(0.45, 0.49, 0.53), 1.5)


## 按像素宽度折行绘制，返回占用高度
func _wrap_text(pos: Vector2, s: String, size: int, col: Color, width: float, max_lines: int = 99) -> float:
	var lines: Array = []
	var cur := ""
	for ch in s:
		if ch == "\n" or font.get_string_size(cur + ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
			lines.append(cur)
			cur = "" if ch == "\n" else ch
		else:
			cur += ch
	if cur != "":
		lines.append(cur)
	if lines.size() > max_lines:
		lines = lines.slice(0, max_lines)
		lines[max_lines - 1] = lines[max_lines - 1].substr(0, maxi(0, lines[max_lines - 1].length() - 1)) + "…"
	var lh := size + 6.0
	for i in lines.size():
		UI.text(self, font, pos + Vector2(0, i * lh), lines[i], size, col)
	return lines.size() * lh
