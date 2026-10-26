extends Node
## 新手开局全流程录屏 + 断言（10-26）：新存档（--roster=new：名册为空 + 10 张）→ 主界面引导（寻访高亮、集结出发压暗）→ 点集结出发被带去寻访
## → 十连寻访 → 拉包 → 逐个揭示（每人点一下）→ 十人总览 → 完成回主界面（集结出发可用）。
## 用法：tools/godot_runner.py 静音离屏启动，--fixed-fps 60 --roster=new --shotdir=<已存在目录> [--touch]；每 2 帧存一张 rec_NNNN.jpg（30 fps），
## tools/probes/first_tenpull_rec.py 转 mp4。断言失败打印 FIRSTREC FAIL，全过打印 FIRSTREC PASS

const Headhunt = preload("res://scripts/screens/headhunt.gd")
const Roster = preload("res://scripts/core/roster.gd")
var title
var out := ""
var n := 0
var frame := 0
var fails := 0
var frame0 := -1


## 设计坐标的一个点 → 视口里的鼠标事件
func _mouse(hh, design: Vector2, pressed := true, motion := false) -> InputEvent:
	var pos: Vector2 = (design * hh._k + hh._off) * Cfg.ui_k
	if motion:
		var m := InputEventMouseMotion.new()
		m.position = pos
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		return m
	var b := InputEventMouseButton.new()
	b.button_index = MOUSE_BUTTON_LEFT
	b.pressed = pressed
	b.position = pos
	return b


## 按住从 a 拖到 b，用时 sec（每帧一个移动事件）
func _drag_to(hh, a: Vector2, b: Vector2, sec: float) -> void:
	var nn := int(sec * 60.0)
	for i in nn:
		hh.input(_mouse(hh, a.lerp(b, float(i + 1) / nn), true, true))
		await _grab()


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FIRSTREC FAIL ", what)


func _grab() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	frame += 1
	if frame0 < 0:
		frame0 = Engine.get_process_frames()
	if frame % 2 == 0:
		get_viewport().get_texture().get_image().save_jpg("%s/rec_%04d.jpg" % [out, n], 0.92)
		n += 1


func _wait(sec: float) -> void:
	for i in int(sec * 60.0):
		await _grab()


func _ready() -> void:
	Headhunt.clock_frames = true
	Sfx.trace_on = true   # 只记录放了哪些音效（测试局主线照样静音），录屏脚本据此离线混音
	Sfx.trace.clear()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shotdir="):
			out = arg.substr(10)
	assert(out != "")
	check(Roster.needs_first() and Roster.tickets() == Roster.FIRST_TICKETS and Cfg.roster_unlocked.is_empty(), "新存档：名册为空、%d 张" % Roster.tickets())
	title = load("res://main.tscn").instantiate()
	add_child(title)
	await _grab()
	title.intro = 0.4   # 重放菜单入场
	check(title.sel == 7, "新手开局缺省选中寻访（sel=%d）" % title.sel)
	await _wait(3.4)
	title._activate(0)   # 点集结出发：十连之前带去寻访
	await _wait(0.2)
	check(title.hunt_ui.visible and title.hunt_ui.hh.open, "集结出发被转去寻访")
	var hh = title.hunt_ui.hh
	await _wait(1.8)
	hh._act(1)   # 定向：新手十连期间不响应
	check(hh.mode == "entry" and Roster.tickets() == 10, "十连之前不能定向 / 单抽")
	hh._act(0)   # 十连寻访
	check(hh.ten and hh.results.size() == Roster.TEN and Roster.tickets() == 0, "十连：%d 名、剩 %d 张" % [hh.results.size(), Roster.tickets()])
	var ids := {}
	var cls := {}
	for r in hh.results:
		ids[r.id] = true
		cls[Roster.class_of(r.id)] = true
	check(ids.size() == Roster.TEN, "十连不重复（%d 名 / %d 职业，纯随机不限定职业）" % [ids.size(), cls.size()])
	# 开包（10-26 用户）：按住往左拖到一半 → 停一下 → 往回拖合上（光收回）→ 再往左拖到底，拉开触发光炸
	await _wait(0.8)
	check(hh.mode == "bag" and hh._open == 0.0, "落包后等玩家拉开（mode=%s open=%.2f）" % [hh.mode, hh._open])
	var c0 := Vector2(800, hh.D.y - 200)
	hh.input(_mouse(hh, c0))
	await _drag_to(hh, c0, c0 - Vector2(hh.DRAG_W * 0.45, 0), 0.9)
	check(absf(hh._open - 0.45) < 0.05, "拖到一半：进度 %.2f" % hh._open)
	await _wait(0.5)
	await _drag_to(hh, c0 - Vector2(hh.DRAG_W * 0.45, 0), c0, 0.8)
	check(hh._open < 0.02 and hh.mode == "bag", "往回拖：合上、光收回（%.2f）" % hh._open)
	await _wait(0.4)
	await _drag_to(hh, c0, c0 - Vector2(hh.DRAG_W * 0.3, 0), 0.5)
	hh.input(_mouse(hh, c0 - Vector2(hh.DRAG_W * 0.3, 0), false))
	await _wait(0.5)
	check(hh._open < 0.02, "不到一半松手：弹回合上（%.2f）" % hh._open)
	hh.input(_mouse(hh, c0))
	await _drag_to(hh, c0, c0 - Vector2(hh.DRAG_W * 0.7, 0), 0.9)
	hh.input(_mouse(hh, c0 - Vector2(hh.DRAG_W * 0.7, 0), false))
	await _wait(0.1)
	check(hh._open_to == 1.0, "过一半松手：自动拉开")
	await _wait(0.9)
	for i in Roster.TEN:
		check(hh.mode == "op" and hh.idx == i, "揭示第 %d 名（mode=%s idx=%d）" % [i + 1, hh.mode, hh.idx])
		await _wait(1.85)
		hh._act("ok")
		if hh.mode == "op" and hh.idx == i:
			hh._act("ok")
	check(hh.mode == "summary", "最后一屏十人总览")
	await _wait(4.5)
	hh._act("ok")
	check(not hh.open and not Roster.needs_first(), "完成：回主界面、新手引导结束")
	await _wait(0.4)
	title._activate(0)   # 现在集结出发进选人页
	await _wait(1.6)
	check(title.op_pick, "十连后集结出发进选人页")
	print("FIRSTREC frames=%d unlocked=%d" % [n, Cfg.roster_unlocked.size()])
	print("SFXTRACE " + JSON.stringify({"frame0": frame0, "trace": Sfx.trace}))
	print("FIRSTREC PASS" if fails == 0 else "FIRSTREC failures=%d" % fails)
	get_tree().quit(0 if fails == 0 else 1)
