extends Control
## 标题界面：深海背景 + 荧光巨树剪影 + 光束 + 菜单

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
var leaving := -1.0
var settings: Control
var gallery: Control
var diff_pick := false
var diff_sel := 0
var diff_rects := {}


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
	if diff_pick:
		_diff_input(event)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if guide:
			guide = false
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
		if guide:
			guide = false
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


func _draw() -> void:
	var vs := size
	# 背景渐变
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(vs.x, 0), vs, Vector2(0, vs.y)]),
		PackedColorArray([Color(0.01, 0.04, 0.07), Color(0.01, 0.05, 0.08), Color(0.04, 0.16, 0.2), Color(0.03, 0.12, 0.16)]))
	if tex_bg != null:
		draw_texture_rect(tex_bg, Rect2(Vector2.ZERO, vs), false)
	# 光束
	for i in 5:
		var x := 200.0 + i * 230.0 + sin(t * 0.3 + i) * 40.0
		var w := 60.0 + 30.0 * sin(t * 0.5 + i * 1.7)
		draw_colored_polygon(PackedVector2Array([Vector2(x, 0), Vector2(x + w, 0), Vector2(x + w * 3.0 - 200, vs.y), Vector2(x - 200, vs.y)]),
			Color(0.4, 0.9, 0.95, 0.025 + 0.012 * sin(t * 0.7 + i)))
	# 巨树
	for b in branches:
		var sway: float = sin(t * 0.6 + b[3] * 0.8) * b[3] * 0.8
		draw_line(b[0] + Vector2(sway * 0.5, 0), b[1] + Vector2(sway, 0), Color(0.05, 0.22, 0.27, 0.9), max(1.0, b[2]))
	for n in nodes:
		var a: float = 0.5 + 0.5 * sin(t * 1.5 + n[1])
		var p: Vector2 = n[0] + Vector2(sin(t * 0.6 + 5.0) * 4.0, 0)
		draw_circle(p, 7.0 + a * 4.0, Color(0.3, 0.9, 0.9, 0.08 * a))
		draw_rect(Rect2(p.round() - Vector2(2, 2), Vector2(4, 4)), Color(0.5, 1.0, 0.95, 0.5 + 0.5 * a))
	# 海床
	var ty := vs.y - 64.0
	for x in range(0, int(vs.x) + 32, 32):
		for y in range(int(ty), int(vs.y) + 32, 32):
			draw_texture_rect_region(tex_tiles, Rect2(x, y, 32, 32), Rect2((x / 32 + y / 32) % 4 * 16, 0, 16, 16), Color(0.35, 0.45, 0.55))
	draw_polygon(PackedVector2Array([Vector2(0, ty - 40), Vector2(vs.x, ty - 40), Vector2(vs.x, ty + 10), Vector2(0, ty + 10)]),
		PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0.02, 0.06, 0.08, 0.7), Color(0.02, 0.06, 0.08, 0.7)]))
	# 主角与灯火
	var pp := Vector2(600, ty + 6)
	var flick := 1.0 + sin(t * 9.0) * 0.03
	draw_texture_rect(tex_light, Rect2(pp - Vector2(170, 210) * flick, Vector2(340, 340) * flick), false, Color(1.0, 0.8, 0.5, 0.35))
	var fw := tex_player.get_width() / player_frames
	var ps := Vector2(fw, tex_player.get_height()) * 3.0
	var pf := int(t * 6.0) % player_frames
	draw_texture_rect_region(tex_player, Rect2((pp - Vector2(ps.x / 2, ps.y)).round(), ps), Rect2(pf * fw, 0, fw, tex_player.get_height()))
	# 漂浮颗粒
	for m in motes:
		draw_rect(Rect2((m[0] + Vector2(sin(t + m[2]) * 8.0, 0)).round(), Vector2(2, 2)), Color(0.7, 0.95, 1.0, 0.25 + 0.2 * sin(t * 2.0 + m[2])))

	# 标题
	var tx := 90.0
	UI.en(self, font, Vector2(tx + 4, 128), "ARKNIGHTS  FAN  GAME", 13, UI.CYAN_DIM, 4.0)
	if tex_logo != null:
		var ls := Vector2(tex_logo.get_width(), tex_logo.get_height())
		var k: float = min(520.0 / ls.x, 130.0 / ls.y)
		draw_texture_rect(tex_logo, Rect2(Vector2(tx, 140), ls * k), false)
	else:
		UI.text(self, font, Vector2(tx, 230), "水月", 96, UI.TEXT)
		UI.text(self, font, Vector2(tx + 210, 228), "深海幸存者", 40, UI.CYAN)
	UI.en(self, font, Vector2(tx + 6, 268), "MIZUKI  :  ABYSSAL  SURVIVORS", 15, UI.SUB, 3.0)
	UI.rule(self, Vector2(tx, 290), Vector2(tx + 500, 290), UI.CYAN_DIM)

	# 菜单
	item_rects.clear()
	var my := 340.0
	for i in ITEMS.size():
		var r := Rect2(tx, my + i * 64, 300, 50)
		item_rects.append(r)
		var on := i == sel
		if on:
			UI.panel(self, r, Color(0.05, 0.2, 0.24, 0.85), UI.CYAN, 10.0, UI.CYAN)
			UI.diamond(self, r.position + Vector2(-18, 25), 6.0, UI.CYAN)
		else:
			UI.panel(self, r, Color(0.02, 0.06, 0.09, 0.55), Color(0.2, 0.4, 0.45, 0.5), 10.0)
		UI.text(self, font, r.position + Vector2(24, 34), ITEMS[i].cn, 24, UI.TEXT if on else UI.SUB)
		UI.en(self, font, r.position + Vector2(170, 32), ITEMS[i].en, 13, UI.CYAN if on else Color(0.3, 0.45, 0.5), 3.0)

	UI.text(self, font, Vector2(tx, vs.y - 20), "明日方舟同人作品 · 非商业", 13, Color(0.4, 0.55, 0.6))
	UI.en(self, font, Vector2(vs.x - 110, vs.y - 20), "v0.8", 13, Color(0.4, 0.55, 0.6))

	if guide:
		_draw_guide(vs)
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
