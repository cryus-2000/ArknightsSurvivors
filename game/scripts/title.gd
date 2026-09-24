extends Control
## 标题界面：蓝眼泪银河沙滩背景（title_bg.gd）+ 菜单

const UI = preload("res://scripts/ui.gd")
const A = preload("res://scripts/art.gd")
const D = preload("res://scripts/data.gd")

const ITEMS := [
	{"cn": "开始探索", "en": "START"},
	{"cn": "图鉴", "en": "GALLERY"},
	{"cn": "操作说明", "en": "GUIDE"},
	{"cn": "设置", "en": "SETTINGS"},
	{"cn": "退出", "en": "EXIT"},
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
var branches: Array = []   # [a, b, width, depth]
var nodes: Array = []      # 发光节点 [pos, phase]
var motes: Array = []
var guide := false
var credits := false
var credits_rect := Rect2()
var credits_data: Dictionary = {}
var leaving := -1.0
var settings: Control
var gallery: Control
var diff_pick := false
var diff_sel := 0
var diff_rects := {}
## 开场动画：从黑暗中浮出海滩 → 标题浮现 → 菜单依次滑入；任意按键 / 点击跳过
const INTRO_LEN := 3.4
var intro := 0.0
var title_bg: Control


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
		if a.begins_with("--galleryshot="):
			var parts := a.substr(14).split(",")
			gallery.open()
			gallery.tab = int(parts[0])
			gallery._build()
			if parts.size() > 1:
				gallery.sel = int(parts[1])
			if parts.size() > 2:
				gallery.form = int(parts[2])
			get_tree().create_timer(1.2).timeout.connect(func():
				get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shot_gallery_ui.png")
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
				get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shot_intro_%d.png" % int(i * 10)))
		get_tree().create_timer(4.0).timeout.connect(func(): get_tree().quit())
	if OS.get_cmdline_user_args().has("--settingsshot"):
		settings.open()
		get_tree().create_timer(1.0).timeout.connect(func():
			get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shot_settings.png")
			get_tree().quit())
	if OS.get_cmdline_user_args().has("--titleshot"):
		get_tree().create_timer(2.0).timeout.connect(func():
			get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shot_title.png")
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
	UI.text(self, font, go.position + Vector2(0, 29), "出发  Enter", 17, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, go.size.x)
	UI.panel(self, back, Color(0.02, 0.06, 0.09, 0.8), UI.LINE, 8.0)
	UI.text(self, font, back.position + Vector2(0, 29), "返回  Esc", 17, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, back.size.x)


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
	t += delta
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
		for i in item_rects.size():
			if item_rects[i].has_point(event.position):
				_activate(i)


func _activate(i: int) -> void:
	match i:
		0:
			Sfx.play("ui_ok")
			diff_pick = true
			diff_sel = clampi(Cfg.difficulty, 0, Cfg.diff_unlocked)
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
	# 标题：1.0s 起浮现（上浮 + 淡入），副标题稍后跟上
	var lg := _seg(1.0, 0.8)
	var ly := 24.0 * (1.0 - lg)
	if tex_logo != null:
		var ls := Vector2(tex_logo.get_width(), tex_logo.get_height())
		var k: float = min(520.0 / ls.x, 130.0 / ls.y)
		draw_texture_rect(tex_logo, Rect2(Vector2(tx, 84 + ly), ls * k), false, Color(1, 1, 1, lg))
	else:
		UI.text(self, font, Vector2(tx, 182 + ly), "水月", 96, _fa(UI.TEXT, lg))
		UI.text(self, font, Vector2(tx + 210, 180 + ly), "深海幸存者", 40, _fa(UI.CYAN, lg))
	UI.en(self, font, Vector2(tx + 6, 242 + ly), "MIZUKI  :  ABYSSAL  SURVIVORS", 14, _fa(UI.SUB, _seg(1.5, 0.5)), 3.0)
	# 分隔线：1.6s 起从左向右划出，线头带一点亮光
	var rl := _seg(1.6, 0.6)
	if rl > 0.0:
		UI.rule(self, Vector2(tx, 266), Vector2(tx + 500 * rl, 266), UI.CYAN_DIM)
		if rl < 1.0:
			draw_circle(Vector2(tx + 500 * rl, 266), 3.0, UI.CYAN)
			draw_circle(Vector2(tx + 500 * rl, 266), 8.0, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.25))

	# 菜单：2.0s 起逐项从左滑入
	item_rects.clear()
	var my := 306.0
	for i in ITEMS.size():
		var r := Rect2(tx, my + i * 60, 300, 50)
		item_rects.append(r)
		var f := _seg(2.0 + i * 0.12, 0.35)
		if f <= 0.0:
			continue
		var rr := Rect2(r.position + Vector2(-40.0 * (1.0 - f), 0), r.size)
		var on := i == sel
		if on:
			var pulse := 0.5 + 0.5 * sin(t * 3.0)
			UI.panel(self, rr, _fa(Color(0.05, 0.2, 0.24, 0.85), f), _fa(UI.CYAN, f), 10.0, _fa(UI.CYAN, f * (0.75 + 0.25 * pulse)))
			UI.diamond(self, rr.position + Vector2(-18 - 3.0 * pulse, 25), 6.0, _fa(UI.CYAN, f))
		else:
			# 未选中：只留一条细竖线，文字压暗，整体更轻
			draw_rect(Rect2(rr.position + Vector2(0, 12), Vector2(2, 26)), _fa(Color(0.2, 0.42, 0.46, 0.7), f))
		UI.text(self, font, rr.position + Vector2(24, 34), ITEMS[i].cn, 24, _fa(UI.TEXT if on else Color(0.62, 0.76, 0.8), f))
		UI.en(self, font, rr.position + Vector2(170, 32), ITEMS[i].en, 13, _fa(UI.CYAN if on else Color(0.3, 0.45, 0.5), f), 3.0)
	# 操作提示
	var hf := _seg(2.7, 0.5)
	if hf > 0.0 and not diff_pick:
		var hy := my + ITEMS.size() * 60 + 6
		UI.en(self, font, Vector2(tx + 2, hy), "W / S  ·  ↑ ↓   SELECT        ENTER   CONFIRM", 11, _fa(Color(0.36, 0.5, 0.55), hf), 2.0)

	# 页脚：最后淡入
	var ff := _seg(2.8, 0.5)
	credits_rect = Rect2(tx - 6, vs.y - 38, 300, 26)
	var cr_hover := credits_rect.has_point(get_local_mouse_position()) and intro >= INTRO_LEN
	UI.text(self, font, Vector2(tx, vs.y - 20), "明日方舟同人作品 · 非商业  ·  致谢与声明 ›", 13, _fa(UI.CYAN if cr_hover else Color(0.4, 0.55, 0.6), ff))
	UI.en(self, font, Vector2(vs.x - 110, vs.y - 20), "v1.8", 13, _fa(Color(0.4, 0.55, 0.6), ff))

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
	if diff_pick:
		_draw_diff(vs)
	if leaving >= 0.0:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.01, 0.02, clamp(leaving / 0.6, 0.0, 1.0)))


func _draw_guide(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.02, 0.04, 0.75))
	var r := Rect2(vs.x / 2 - 330, vs.y / 2 - 220, 660, 440)
	UI.panel(self, r, UI.BG2, UI.CYAN_DIM, 16.0, UI.CYAN)
	UI.text(self, font, r.position + Vector2(36, 56), "操作说明", 28, UI.TEXT)
	UI.en(self, font, r.position + Vector2(170, 54), "GUIDE", 13, UI.CYAN, 3.0)
	var lines := [
		["移动", "WASD / 方向键"],
		["攻击", "全自动：挥伞横扫，触手追击血量最低的敌人"],
		["技能", "Lv3 唤醒 → Lv10 囚徒困境 → Lv20 镜花水月，自动释放；升级时可能出现技能进阶"],
		["灯火", "随时间熄灭，拾取灯油补充；过低时敌人变强"],
		["升级 / 藏品", "按 1 / 2 / 3 或点击选择"],
		["属性 / 暂停", "Tab 或 C 查看属性　　Esc 暂停　　M 静音　　R 重来　　T 回标题"],
	]
	for i in lines.size():
		var y := r.position.y + 110 + i * 48
		UI.diamond(self, Vector2(r.position.x + 44, y - 7), 4.0, UI.CYAN)
		UI.text(self, font, Vector2(r.position.x + 60, y), lines[i][0], 18, UI.CYAN)
		UI.text(self, font, Vector2(r.position.x + 190, y), lines[i][1], 17, UI.TEXT)
	UI.text(self, font, Vector2(r.position.x, r.end.y - 24), "按任意键返回", 14, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


## 致谢与声明：内容来自 data/credits.json
func _draw_credits(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.02, 0.04, 0.8))
	var secs: Array = credits_data.get("sections", [])
	var tw := 760.0 - 230.0
	var heights: Array = []
	var total := 0.0
	for sec in secs:
		var hh: float = font.get_multiline_string_size(sec[1], HORIZONTAL_ALIGNMENT_LEFT, tw, 14, -1, UI.BRK).y
		if sec.size() > 2 and sec[2] != "":
			hh += 18.0
		hh = maxf(hh, 24.0) + 22.0
		heights.append(hh)
		total += hh
	var h: float = 150.0 + total
	var r := Rect2(vs.x / 2 - 380, vs.y / 2 - h / 2, 760, h)
	UI.panel(self, r, UI.BG2, UI.CYAN_DIM, 16.0, UI.CYAN)
	UI.text(self, font, r.position + Vector2(36, 52), credits_data.get("title", "致谢与声明"), 26, UI.TEXT)
	UI.en(self, font, r.position + Vector2(190, 50), credits_data.get("en", "CREDITS"), 12, UI.CYAN, 3.0)
	var y := r.position.y + 90
	for i in secs.size():
		var sec: Array = secs[i]
		UI.diamond(self, Vector2(r.position.x + 44, y + 8), 4.0, UI.CYAN)
		UI.text(self, font, Vector2(r.position.x + 58, y + 14), sec[0], 16, UI.CYAN)
		draw_multiline_string(font, Vector2(r.position.x + 190, y + 12), sec[1], HORIZONTAL_ALIGNMENT_LEFT, tw, 14, -1, UI.TEXT, UI.BRK)
		if sec.size() > 2 and sec[2] != "":
			var th: float = font.get_multiline_string_size(sec[1], HORIZONTAL_ALIGNMENT_LEFT, tw, 14, -1, UI.BRK).y
			UI.text(self, font, Vector2(r.position.x + 190, y + 12 + th + 6), sec[2], 12, Color(0.5, 0.75, 0.85))
		y += heights[i]
	UI.text(self, font, Vector2(r.position.x, r.end.y - 44), credits_data.get("footer", ""), 13, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	UI.text(self, font, Vector2(r.position.x, r.end.y - 22), "按任意键返回", 13, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
