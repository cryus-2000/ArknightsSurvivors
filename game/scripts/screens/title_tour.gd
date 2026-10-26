extends Control
## 主界面引导（协调人 10-26，复用 screens/spotlight.gd 的聚光框）：新手十连做完回到主界面后，依次指引 ① 点「图鉴」看抽到的干员
## ② 点「返回」关闭图鉴 ③ 点「集结出发」。只引导一次：存档 Cfg.title_tour（0 没有 / 1 待引导 / 2 已引导）在新手十连成功时置 1
## （Roster.redeem_ten），走完或跳过置 2；老存档没做过新手十连，恒为 0，不会弹。
## 玩家真的点了高亮处才算：点击落在高亮外会被吞掉，落在高亮内原样交给标题 / 图鉴处理（本节点是标题最后一个子节点，_input 先于它们）。
## 第 ② 步不压暗（玩家要看图鉴），只在「返回」键上画框 + 说明；没有「跳过」键（Esc 自然关图鉴）。
## 演示：--titletour（配 --roster=full，新玩家名册已有干员）自动走完三步并存帧 rec_%05d.png 到 --shotdir（配 --fixed-fps 30）。

const Spotlight = preload("res://scripts/screens/spotlight.gd")
const Roster = preload("res://scripts/core/roster.gd")

const STEPS := [
	{"en": "ARCHIVE", "title": "图鉴", "text": "点击「图鉴」。"},
	{"en": "RETURN", "title": "返回", "text": "", "panel": false},   # 只框不说明
	{"en": "DEPLOY", "title": "集结出发", "text": "开始探索。"},
]

var tl: Control            # 标题页（screens/title.gd）
var active := false
var step := 0
var t := 0.0
var skip_rect := Rect2()
var _wait := 0.0
var _demo := false
var _demo_n := 0
var _rec_i := 0
var _step_t := 0.0
var _probed := false
var _clicked := false


func setup(title_node: Control) -> void:
	tl = title_node
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_demo = Cfg.dev_args().has("--titletour")
	if _demo:
		Cfg.title_tour = 1


func _ready_to_start() -> bool:
	if Cfg.title_tour != 1 or Roster.needs_first() or not Roster.active():
		return false
	if tl.intro < tl.INTRO_LEN or tl._intro0 >= 0.0 or tl._overlay_open() or tl.transition.busy or tl.leaving >= 0.0:
		return false
	if tl.guide or tl.credits or tl.diff_pick or tl.op_pick:
		return false
	return tl.item_rects.size() > 1 and tl.item_rects[0].size.x > 0.0 and tl.item_rects[1].size.x > 0.0


func _process(dt: float) -> void:
	if tl == null:
		return
	if not active:
		if _ready_to_start():
			_wait += dt
			if _wait > 0.7:
				_start()
		else:
			_wait = 0.0
		return
	t += dt
	_step_t += dt
	match step:
		0:
			tl.sel = 1
			if tl.gallery.visible:
				_go(1)
		1:
			if not tl.gallery.visible:
				_go(2)
		2:
			tl.sel = 0
			# 点了「集结出发」：选人页打开 / 开始转场；刚关图鉴时标题自己的翻页转场也会 busy，所以给本步 0.8 秒的宽限
			if tl.op_pick or tl.leaving >= 0.0 or (tl.transition.busy and _step_t > 0.8):
				_finish()
	_demo_step()
	queue_redraw()


func _start() -> void:
	active = true
	step = 0
	t = 0.0
	_step_t = 0.0
	tl.sel = 1


func _go(i: int) -> void:
	step = i
	t = 0.0
	_step_t = 0.0


func _finish() -> void:
	active = false
	Cfg.title_tour = 2
	Cfg.save()
	queue_redraw()
	if _demo:
		get_tree().create_timer(0.3).timeout.connect(func(): get_tree().quit())


## 当前步要框的矩形（标题页 / 图鉴的局部坐标）
func _hole() -> Rect2:
	match step:
		0:
			return tl.item_rects[1]
		1:
			return tl.gallery.back_screen_rect()
		_:
			return tl.item_rects[0]


func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if step == 1:
			return   # 图鉴里按键照常（Esc 关图鉴）
		match Pad.kc(event):
			KEY_ESCAPE:
				_finish()
				get_viewport().set_input_as_handled()
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				pass   # 交给标题：选中项就是被框的那一项
			_:
				get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed:
		if step == 1:
			return
		var p: Vector2 = make_input_local(event).position
		if event.button_index == MOUSE_BUTTON_LEFT and skip_rect.has_point(p):
			_finish()
		elif event.button_index == MOUSE_BUTTON_LEFT and _hole().grow(5.0).has_point(p):
			return   # 点在高亮处：交给标题
		get_viewport().set_input_as_handled()


func _draw() -> void:
	if not active or tl == null:
		return
	var h: Rect2 = _hole()
	if h.size.x <= 0.0:
		return
	var st: Dictionary = STEPS[step]
	skip_rect = Spotlight.draw(self, tl.font, size, [h], {"idx": step, "n": STEPS.size(), "tag": "TOUR", "en": st.en, "title": st.title, "text": st.text,
		"hint": Pad.hint("点击高亮处　Esc：跳过", "Ⓐ：确认　Ⓑ：跳过", "点击高亮处"), "e": 1.0 - pow(1.0 - clampf(t / 0.28, 0.0, 1.0), 3.0), "t": t,
		"dim": 0.0 if step == 1 else 0.68, "skip": step != 1, "panel": st.get("panel", true), "touch": Cfg.touch_device()})


# ---------------------------------------------------------------- 演示 / 录片（--titletour）

func _demo_step() -> void:
	if not _demo:
		return
	_demo_n += 1
	if DisplayServer.get_name() != "headless":
		get_viewport().get_texture().get_image().save_png(_shot_dir() + "/rec_%05d.png" % _rec_i)
		_rec_i += 1
	match step:
		0:
			if _step_t > 1.0 and not _probed:
				# 真实输入通路：先点高亮外（应被吞掉，图鉴不开），再点高亮内（应交给标题，图鉴打开）
				_probed = true
				_click(Vector2(size.x * 0.6, size.y * 0.3))
				print("TTOUR outside_click_swallowed=%s" % (not tl.gallery.visible))
			if _step_t > 1.6 and not _clicked:
				_clicked = true
				if Cfg.touch_device():
					tl._activate(1)   # 触屏演示：标题页整体按 ui_k 放大，合成事件的坐标换算对不上，直接激活（桌面走真实输入通路）
				else:
					_click(_hole().get_center())
		1:
			if _step_t > 2.6:
				tl.gallery.close()
		2:
			if _step_t > 2.4:
				print("TTOUR reached_deploy=true")
				_finish()


func _click(p: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = get_global_transform_with_canvas() * p
	ev.global_position = ev.position
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)


func _shot_dir() -> String:
	for a in Cfg.dev_args():
		if a.begins_with("--shotdir="):
			return a.substr(10)
	return "/tmp/claude-0"
