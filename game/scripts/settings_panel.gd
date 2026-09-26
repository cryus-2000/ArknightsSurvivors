extends Control
## 设置面板：标题界面与暂停菜单共用。键盘 ↑↓ 选择、←→ 调整、Esc 返回；也可用鼠标点击；手柄经 Pad 翻译成同样的按键。
## 分类页（2026-09-27 用户要求）：声音 / 画面 / 游戏，Q / E（手柄 LB / RB → PageUp / PageDown）或点标签切换；
## 每页末尾一行「返回」。选项本身（ROWS 的键名、类型、存档键）不变，TABS 只按键名分组

signal closed

const UI = preload("res://scripts/ui.gd")

const ROWS := [
	{"cn": "主音量", "en": "MASTER", "key": "master", "type": "vol"},
	{"cn": "音乐", "en": "MUSIC", "key": "music", "type": "vol"},
	{"cn": "音效", "en": "SFX", "key": "sfx", "type": "vol"},
	{"cn": "语音", "en": "VOICE", "key": "voice", "type": "vol"},
	{"cn": "全屏", "en": "FULLSCREEN", "key": "fullscreen", "type": "bool"},
	{"cn": "窗口分辨率", "en": "RESOLUTION", "key": "res_index", "type": "res"},
	{"cn": "伤害数字", "en": "DAMAGE NUMBERS", "key": "dmg_numbers", "type": "bool"},
	{"cn": "震屏强度", "en": "SCREEN SHAKE", "key": "shake", "type": "shake"},
	{"cn": "命中顿帧", "en": "HIT STOP", "key": "hitstop", "type": "bool"},
	{"cn": "怪物轮廓光", "en": "ENEMY OUTLINE", "key": "outline", "type": "bool"},
	{"cn": "景深与前景", "en": "DEPTH OF FIELD", "key": "dof", "type": "bool"},
	{"cn": "辉光", "en": "BLOOM", "key": "bloom", "type": "bool"},
	{"cn": "水下滤镜", "en": "UNDERWATER FILTER", "key": "water_filter", "type": "bool"},
	{"cn": "法线光照", "en": "NORMAL LIGHTING", "key": "normal_maps", "type": "bool", "note": "下局生效"},
	{"cn": "亮度", "en": "BRIGHTNESS", "key": "brightness", "type": "bright"},
	{"cn": "手柄震动", "en": "CONTROLLER RUMBLE", "key": "pad_rumble", "type": "bool"},
	{"cn": "返回", "en": "BACK", "key": "", "type": "back"},
]
## 分类：[中文, 英文, 该页的选项键名]；ROWS 里每个选项恰好出现在一页（返回行每页都有）
const TABS := [
	["声音", "SOUND", ["master", "music", "sfx", "voice"]],
	["画面", "DISPLAY", ["fullscreen", "res_index", "brightness", "bloom", "water_filter", "dof", "normal_maps"]],
	["游戏", "GAMEPLAY", ["dmg_numbers", "outline", "hitstop", "shake", "pad_rumble"]],
]

var font: Font
var tab := 0
var cur: Array = []          # 当前页的 ROWS 下标（最后一个是返回）
var tab_rects: Array = []
var sel := 0
var st := 0.0
var row_rects: Array = []
var pending_res := -1        # 分辨率：←→ 只选择，Enter / 点击「应用」才生效


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
	_set_tab(0)
	pending_res = Cfg.res_index
	visible = true
	queue_redraw()


func _set_tab(t: int) -> void:
	tab = (t + TABS.size()) % TABS.size()
	cur.clear()
	for key in TABS[tab][2]:
		for i in ROWS.size():
			if ROWS[i].key == key:
				cur.append(i)
	cur.append(ROWS.size() - 1)   # 返回
	sel = clampi(sel, 0, cur.size() - 1)


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
				sel = (sel + cur.size() - 1) % cur.size()
				Sfx.play("ui_move")
			KEY_DOWN, KEY_S:
				sel = (sel + 1) % cur.size()
				Sfx.play("ui_move")
			KEY_LEFT, KEY_A:
				_adjust(cur[sel], -1)
			KEY_RIGHT, KEY_D:
				_adjust(cur[sel], 1)
			KEY_Q, KEY_PAGEUP:
				_set_tab(tab - 1)
				sel = 0
				Sfx.play("ui_move")
			KEY_E, KEY_PAGEDOWN, KEY_TAB:
				_set_tab(tab + 1)
				sel = 0
				Sfx.play("ui_move")
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				if ROWS[cur[sel]].type == "res":
					_apply_res()
				else:
					_adjust(cur[sel], 1)
			KEY_ESCAPE:
				close()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		for i in row_rects.size():
			if row_rects[i].has_point(event.position):
				sel = i
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			for t in tab_rects.size():
				if tab_rects[t].has_point(event.position) and t != tab:
					_set_tab(t)
					sel = 0
					Sfx.play("ui_move")
		for si in row_rects.size():
			var r: Rect2 = row_rects[si]
			var i: int = cur[si]
			if r.has_point(event.position):
				var arrows: bool = ROWS[i].type in ["vol", "bright", "res"]
				var fx: float = (event.position.x - r.position.x) / r.size.x
				var dir := 1
				if arrows:
					dir = -1 if fx < 0.62 else 1
				if event.button_index == MOUSE_BUTTON_LEFT:
					if ROWS[i].type == "res" and fx >= 0.62 and fx <= 0.88:
						_apply_res()
					else:
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
		"bright":
			Cfg.brightness = clampf(snappedf(Cfg.brightness + dir * 0.05, 0.05), 0.8, 1.4)
		"res":
			var n: int = Cfg.RESOLUTIONS.size()
			pending_res = (pending_res + (1 if dir > 0 else n - 1)) % n
			Sfx.play("ui_move")
			return
		"back":
			close()
			return
	Cfg.apply()
	Sfx.play("ui_move")


func _apply_res() -> void:
	if pending_res == Cfg.res_index:
		return
	Cfg.res_index = pending_res
	Cfg.apply()
	pending_res = Cfg.res_index
	Sfx.play("ui_ok")


func _process(delta: float) -> void:
	if visible:
		st += delta
		queue_redraw()


func _draw() -> void:
	var vs := size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.02, 0.04, 0.8))
	var compact: bool = vs.y < 680.0
	# 面板高度按最长的一页定（各页高度一致，切页不跳）：标题 + 标签 146 + 行 46 × (n - 1) + 返回行 + 底部提示
	var most := 0
	for tb in TABS:
		most = maxi(most, tb[2].size())
	var rh: float = minf(146.0 + most * 46.0 + 44.0 + 56.0, vs.y - 8.0)
	var r := Rect2(vs.x / 2 - 320, vs.y / 2 - rh / 2.0, 640, rh)
	UI.panel(self, r, UI.BG2, UI.CYAN_DIM, 16.0, UI.CYAN, 81, st)
	UI.text(self, font, r.position + Vector2(40, 58), "设置", 28, UI.TEXT)
	UI.en(self, font, r.position + Vector2(112, 56), "SETTINGS", 13, UI.CYAN, 3.0)
	# 分类标签：中文 + 英文小字，当前页青色底线；两侧写切换键
	tab_rects.clear()
	var tx := r.position.x + 40.0
	var ty := r.position.y + 84.0
	var mp := get_local_mouse_position()
	for t in TABS.size():
		var tw: float = 112.0
		var tbr := Rect2(tx + t * (tw + 8.0), ty, tw, 40)
		tab_rects.append(tbr)
		var ton := t == tab
		var hov := tbr.has_point(mp)
		draw_rect(tbr, Color(0.05, 0.2, 0.24, 0.8) if ton else Color(1, 1, 1, 0.06 if hov else 0.03))
		draw_rect(Rect2(tbr.position.x, tbr.end.y - 3, tbr.size.x, 3), UI.CYAN if ton else Color(1, 1, 1, 0.12))
		UI.text(self, font, tbr.position + Vector2(0, 25), TABS[t][0], 17, UI.TEXT if ton else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, tw * 0.55)
		UI.en(self, font, tbr.position + Vector2(tw * 0.52, 24), TABS[t][1], 8, UI.CYAN if ton else UI.CYAN_DIM, 1.5)
	UI.keycap(self, font, Vector2(r.end.x - 118, ty + 11), Pad.hint("Q", "LB"), UI.SUB, 11)
	UI.keycap(self, font, Vector2(r.end.x - 70, ty + 11), Pad.hint("E", "RB"), UI.SUB, 11)
	UI.rule(self, Vector2(r.position.x + 30, ty + 50), Vector2(r.end.x - 30, ty + 50), UI.EDGE_DIM)
	row_rects.clear()
	# 行距按面板高度自适应：标题 + 标签 140 + 行 + 底部提示 40 都要放得下
	var top := r.position.y + 146.0
	var step: float = minf(40.0 if compact else 46.0, (r.end.y - 46.0 - top - 34.0) / float(maxi(1, cur.size() - 1)))
	for si in cur.size():
		var i: int = cur[si]
		var row: Dictionary = ROWS[i]
		var back: bool = row.type == "back"
		var rr := Rect2(r.position.x + 30, top + si * step + (10.0 if back else 0.0), r.size.x - 60, minf(34.0, step))
		row_rects.append(rr)
		var on := si == sel
		if on:
			draw_rect(rr, Color(0.05, 0.2, 0.24, 0.7))
			draw_rect(Rect2(rr.position, Vector2(3, rr.size.y)), UI.CYAN)
		UI.text(self, font, rr.position + Vector2(18, 24), row.cn, 17, UI.TEXT if on else UI.SUB)
		UI.en(self, font, rr.position + Vector2(130, 23), row.en, 9, UI.CYAN_DIM, 2.0)
		if row.has("note"):
			UI.text(self, font, rr.position + Vector2(rr.size.x - 70, 24), row.note, 11, UI.SUB)
		var vx := rr.position.x + rr.size.x - 230
		match row.type:
			"vol":
				var v: float = Cfg.get(row.key)
				UI.text(self, font, Vector2(vx - 10, rr.position.y + 24), "◀", 14, UI.CYAN if on else UI.SUB)
				for k in 10:
					var c := UI.CYAN if k < int(round(v * 10.0)) else Color(0.15, 0.22, 0.26)
					draw_rect(Rect2(vx + 16 + k * 16, rr.position.y + 11, 12, 13), c)
				UI.text(self, font, Vector2(vx + 180, rr.position.y + 24), "▶", 14, UI.CYAN if on else UI.SUB)
				UI.text(self, font, Vector2(vx + 200, rr.position.y + 24), "%d" % int(round(v * 100.0)), 14, UI.TEXT)
			"bool":
				var b: bool = Cfg.get(row.key)
				UI.text(self, font, Vector2(vx, rr.position.y + 24), "开" if b else "关", 18, UI.CYAN if b else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 200)
			"shake":
				var names := {0.0: "关", 0.5: "弱", 1.0: "标准"}
				UI.text(self, font, Vector2(vx, rr.position.y + 24), names.get(Cfg.shake, "标准"), 18, UI.CYAN, HORIZONTAL_ALIGNMENT_CENTER, 200)
			"bright":
				UI.text(self, font, Vector2(vx - 10, rr.position.y + 24), "◀", 14, UI.CYAN if on else UI.SUB)
				UI.text(self, font, Vector2(vx, rr.position.y + 24), "%d%%" % int(round(Cfg.brightness * 100.0)), 18, UI.CYAN, HORIZONTAL_ALIGNMENT_CENTER, 200)
				UI.text(self, font, Vector2(vx + 180, rr.position.y + 24), "▶", 14, UI.CYAN if on else UI.SUB)
			"res":
				var pi: int = clampi(pending_res, 0, Cfg.RESOLUTIONS.size() - 1)
				var sz: Vector2i = Cfg.RESOLUTIONS[pi]
				var changed: bool = pi != Cfg.res_index
				var label := "%d × %d" % [sz.x, sz.y]
				if Cfg.fullscreen:
					label += "（全屏按屏幕）"
				UI.text(self, font, Vector2(vx - 10, rr.position.y + 24), "◀", 14, UI.CYAN if on else UI.SUB)
				UI.text(self, font, Vector2(vx, rr.position.y + 24), label, 15 if Cfg.fullscreen else 17, (UI.GOLD if changed else UI.CYAN) if not Cfg.fullscreen else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 140)
				if changed:
					var br := Rect2(vx + 142, rr.position.y + 6, 42, 22)
					UI.panel(self, br, Color(0.2, 0.15, 0.05, 0.9), UI.GOLD, 4.0)
					UI.text(self, font, br.position + Vector2(0, 16), "应用", 12, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER, br.size.x)
				UI.text(self, font, Vector2(vx + 190, rr.position.y + 24), "▶", 14, UI.CYAN if on else UI.SUB)
	UI.text(self, font, Vector2(r.position.x, r.end.y - 18), Pad.hint("Q / E 切换分类 · ↑↓ 选择 · ←→ 调整 · Esc 返回", "LB / RB 切换分类 · 摇杆 ↑↓ 选择 · ←→ 调整 · Ⓐ 切换 · Ⓑ 返回"), 13, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
