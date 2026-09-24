extends Control
## 设置面板：标题界面与暂停菜单共用。键盘 ↑↓ 选择、←→ 调整、Esc 返回；也可用鼠标点击。

signal closed

const UI = preload("res://scripts/ui.gd")

const ROWS := [
	{"cn": "主音量", "en": "MASTER", "key": "master", "type": "vol"},
	{"cn": "音乐", "en": "MUSIC", "key": "music", "type": "vol"},
	{"cn": "音效", "en": "SFX", "key": "sfx", "type": "vol"},
	{"cn": "全屏", "en": "FULLSCREEN", "key": "fullscreen", "type": "bool"},
	{"cn": "窗口分辨率", "en": "RESOLUTION", "key": "res_index", "type": "res"},
	{"cn": "伤害数字", "en": "DAMAGE NUMBERS", "key": "dmg_numbers", "type": "bool"},
	{"cn": "震屏强度", "en": "SCREEN SHAKE", "key": "shake", "type": "shake"},
	{"cn": "命中顿帧", "en": "HIT STOP", "key": "hitstop", "type": "bool"},
	{"cn": "怪物轮廓光", "en": "ENEMY OUTLINE", "key": "outline", "type": "bool"},
	{"cn": "景深与前景", "en": "DEPTH OF FIELD", "key": "dof", "type": "bool"},
	{"cn": "返回", "en": "BACK", "key": "", "type": "back"},
]

var font: Font
var sel := 0
var st := 0.0
var row_rects: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = load("res://fonts/ui.ttf")
	visible = false


func open() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	position = Vector2.ZERO
	size = get_viewport_rect().size
	sel = 0
	visible = true
	queue_redraw()


func close() -> void:
	visible = false
	Cfg.save()
	Sfx.play("ui_ok")
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_UP, KEY_W:
				sel = (sel + ROWS.size() - 1) % ROWS.size()
				Sfx.play("ui_move")
			KEY_DOWN, KEY_S:
				sel = (sel + 1) % ROWS.size()
				Sfx.play("ui_move")
			KEY_LEFT, KEY_A:
				_adjust(sel, -1)
			KEY_RIGHT, KEY_D:
				_adjust(sel, 1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_adjust(sel, 1)
			KEY_ESCAPE:
				close()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		for i in row_rects.size():
			if row_rects[i].has_point(event.position):
				sel = i
	elif event is InputEventMouseButton and event.pressed:
		for i in row_rects.size():
			var r: Rect2 = row_rects[i]
			if r.has_point(event.position):
				var dir := 1 if event.position.x > r.position.x + r.size.x * 0.62 or ROWS[i].type != "vol" else -1
				if event.button_index == MOUSE_BUTTON_LEFT:
					_adjust(i, dir)
				elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
					_adjust(i, 1)
				elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
					_adjust(i, -1)
		get_viewport().set_input_as_handled()
	queue_redraw()


func _adjust(i: int, dir: int) -> void:
	var row: Dictionary = ROWS[i]
	match row.type:
		"vol":
			Cfg.set(row.key, clamp(snappedf(Cfg.get(row.key) + dir * 0.1, 0.1), 0.0, 1.0))
		"bool":
			Cfg.set(row.key, not Cfg.get(row.key))
		"shake":
			var v: float = Cfg.shake
			v = [0.0, 0.5, 1.0][(int(round(v * 2.0)) + (1 if dir > 0 else 2)) % 3]
			Cfg.shake = v
		"res":
			var n: int = Cfg.RESOLUTIONS.size()
			Cfg.res_index = (Cfg.res_index + (1 if dir > 0 else n - 1)) % n
		"back":
			close()
			return
	Cfg.apply()
	Sfx.play("ui_move")


func _process(delta: float) -> void:
	if visible:
		st += delta
		queue_redraw()


func _draw() -> void:
	var vs := size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.02, 0.04, 0.8))
	var r := Rect2(vs.x / 2 - 320, vs.y / 2 - 328, 640, 656)
	UI.panel(self, r, UI.BG2, UI.CYAN_DIM, 16.0, UI.CYAN, 81, st)
	UI.text(self, font, r.position + Vector2(40, 58), "设置", 28, UI.TEXT)
	UI.en(self, font, r.position + Vector2(112, 56), "SETTINGS", 13, UI.CYAN, 3.0)
	row_rects.clear()
	for i in ROWS.size():
		var row: Dictionary = ROWS[i]
		var rr := Rect2(r.position.x + 30, r.position.y + 84 + i * 45, r.size.x - 60, 39)
		row_rects.append(rr)
		var on := i == sel
		if on:
			draw_rect(rr, Color(0.05, 0.2, 0.24, 0.7))
			draw_rect(Rect2(rr.position, Vector2(3, rr.size.y)), UI.CYAN)
		UI.text(self, font, rr.position + Vector2(18, 27), row.cn, 18, UI.TEXT if on else UI.SUB)
		UI.en(self, font, rr.position + Vector2(130, 26), row.en, 10, UI.CYAN_DIM, 2.0)
		var vx := rr.position.x + rr.size.x - 230
		match row.type:
			"vol":
				var v: float = Cfg.get(row.key)
				UI.text(self, font, Vector2(vx - 10, rr.position.y + 27), "◀", 14, UI.CYAN if on else UI.SUB)
				for k in 10:
					var c := UI.CYAN if k < int(round(v * 10.0)) else Color(0.15, 0.22, 0.26)
					draw_rect(Rect2(vx + 16 + k * 16, rr.position.y + 13, 12, 14), c)
				UI.text(self, font, Vector2(vx + 180, rr.position.y + 27), "▶", 14, UI.CYAN if on else UI.SUB)
				UI.text(self, font, Vector2(vx + 200, rr.position.y + 27), "%d" % int(round(v * 100.0)), 14, UI.TEXT)
			"bool":
				var b: bool = Cfg.get(row.key)
				UI.text(self, font, Vector2(vx, rr.position.y + 27), "开" if b else "关", 18, UI.CYAN if b else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 200)
			"shake":
				var names := {0.0: "关", 0.5: "弱", 1.0: "标准"}
				UI.text(self, font, Vector2(vx, rr.position.y + 27), names.get(Cfg.shake, "标准"), 18, UI.CYAN, HORIZONTAL_ALIGNMENT_CENTER, 200)
			"res":
				var sz: Vector2i = Cfg.RESOLUTIONS[clampi(Cfg.res_index, 0, Cfg.RESOLUTIONS.size() - 1)]
				var label := "%d × %d" % [sz.x, sz.y]
				if Cfg.fullscreen:
					label += "（全屏时按屏幕）"
				UI.text(self, font, Vector2(vx - 10, rr.position.y + 27), "◀", 14, UI.CYAN if on else UI.SUB)
				UI.text(self, font, Vector2(vx, rr.position.y + 27), label, 15 if Cfg.fullscreen else 18, UI.CYAN if not Cfg.fullscreen else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 200)
				UI.text(self, font, Vector2(vx + 180, rr.position.y + 27), "▶", 14, UI.CYAN if on else UI.SUB)
	UI.text(self, font, Vector2(r.position.x, r.end.y - 18), "↑↓ 选择 · ←→ 调整 · Esc 返回", 13, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
