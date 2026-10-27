extends Node
## 结算底栏按钮反馈录帧（10-28 用户「结算画面最下面点击按钮没有交互反馈」；不进快检）：开窗口、--fixed-fps 30 逐帧存 rec_<帧>.png。
##   godot --fixed-fps 30 --path game res://tests/settlement_btn_rec.tscn -- --shotdir=<目录>
## 按真实输入事件走一遍：鼠标悬停换按钮 → 点击 → 键盘 ↓ 进底栏、← → 换焦点、Enter 按下 → 触屏按下。
## 动作被换成空操作（不真的离开结算），屏幕右上角写当前步骤。

const RunStats = preload("res://scripts/run/run_stats.gd")
const Game = preload("res://scripts/game.gd")
const Screen = preload("res://scripts/screens/settlement_screen.gd")

class Probe extends Screen:
	var last := ""
	func _run(id: String) -> void:
		last = id   # 录像里不真的跳转（分享卡照常打开）
		if id == "share":
			super._run(id)

var game: Node
var frames := 0
var shot_dir := ""
var rec_i := 0
var s
var step := ""
const SEQ := [
	[10, "mouse", "title", "鼠标悬停"], [26, "mouse", "meta", "鼠标悬停"], [42, "mouse", "hunt", "鼠标悬停"],
	[58, "click", "hunt", "鼠标点击"], [74, "mouse", "", "移开"],
	[84, "key", KEY_DOWN, "键盘 / 手柄：↓ 进底栏"], [98, "key", KEY_LEFT, "键盘 / 手柄：← 换按钮"], [112, "key", KEY_LEFT, "键盘 / 手柄：← 换按钮"],
	[126, "key", KEY_ENTER, "键盘 / 手柄：确认"], [142, "key", KEY_UP, "键盘 / 手柄：↑ 回编队"],
	[156, "touch", "meta", "触屏按下"], [176, "end", "", ""],
]
## --share：分享卡（悬停 → 点「分享」→ 停 2.5 秒 → Enter 保存图片（写到 --shotdir 的 share_card/）→ 停 2 秒 → Esc 关）
const SEQ_SHARE := [
	[10, "mouse", "share", ""], [24, "click", "share", ""], [100, "key", KEY_ENTER, ""], [176, "key", KEY_ESCAPE, ""], [196, "end", "", ""],
]
var seq: Array = SEQ


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			shot_dir = a.substr(10)
		elif a == "--share":
			seq = SEQ_SHARE
	game = load("res://game.tscn").instantiate()
	add_child(game)


func _raw() -> Dictionary:
	var raw: Dictionary = RunStats.fake_raw()
	for id in ["texas", "lumen", "exusiai"]:
		raw.ops.append({"id": id, "name": id, "en": id, "col": [0.5, 0.7, 0.9], "leader": false, "t": 500.0, "left": 600.0})
	return raw


func _screen_pos(id: String) -> Vector2:
	for b in s._buttons():
		if str(b[0]) == id:
			var p: Vector2 = s._btn_rect(b).get_center()
			return (p * s.scale + s.origin) * Cfg.ui_k
	return Vector2(640, 300) * Cfg.ui_k


func _do(ev: Array) -> void:
	step = str(ev[3])
	match str(ev[1]):
		"mouse":
			var m := InputEventMouseMotion.new()
			m.position = _screen_pos(str(ev[2])) if str(ev[2]) != "" else Vector2(640, 400) * Cfg.ui_k
			s.input(m)
		"click":
			var c := InputEventMouseButton.new()
			c.button_index = MOUSE_BUTTON_LEFT
			c.pressed = true
			c.position = _screen_pos(str(ev[2]))
			s.input(c)
			var u: InputEventMouseButton = c.duplicate()
			u.pressed = false
			s.input(u)
		"key":
			if s.share_toy != null:
				s.share_toy.out_dir = shot_dir.get_base_dir().path_join("share_card")   # 别写进玩家的「图片」
			var k := InputEventKey.new()
			k.pressed = true
			k.keycode = int(ev[2])
			s.input(k)
		"touch":
			var t := InputEventScreenTouch.new()
			t.pressed = true
			t.position = _screen_pos(str(ev[2]))
			s.input(t)
		"end":
			get_tree().quit(0)


func _process(d: float) -> void:
	frames += 1
	if frames == 4:
		game.set_process(false)
		game.hud.size = Vector2(1280, 720)
		game.state = Game.S.WIN
		game.state_age = 3.0
		s = Probe.new(game)
		game.settlement = s
		s.set_model(RunStats.model(_raw()))
		s.tick(1.0)
		s.skip()
	if s == null:
		return
	s.tick(d)
	var f := frames - 4
	for ev in seq:
		if int(ev[0]) == f:
			_do(ev)
	game.hud.queue_redraw()
	if f > 2:
		get_viewport().get_texture().get_image().save_png(shot_dir + "/rec_%03d.png" % rec_i)
		rec_i += 1


func _input(_e: InputEvent) -> void:
	pass
