extends Node
## 寻访十连录屏 + 断言（10-28 用户：「寻访里面加入 10 连的选项」）：入口（11 张）→ 寻访一次 → 拉包 → 揭示 → 本次寻访 → 回入口
## → 十连寻访（10 张）→ 拉包 → 一屏十人总览（最高稀有度最后单独落入）→ 完成回入口（剩 0 张，十连灰显「还差 10 张」）。
## 用法：tools/probes/headhunt_ten_rec.py [desktop|phone]（godot_runner 静音离屏，--fixed-fps 60 --roster=start5 --shotdir=<目录> [--touch]）；
## 每 2 帧存一张 rec_NNNN.jpg（30 fps）。断言失败打印 TENREC FAIL，全过打印 TENREC PASS

const Headhunt = preload("res://scripts/screens/headhunt.gd")
const Roster = preload("res://scripts/core/roster.gd")
var host
var out := ""
var n := 0
var frame := 0
var fails := 0
var frame0 := -1


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("TENREC FAIL ", what)


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


func _mouse(design: Vector2, pressed := true) -> void:
	var hh = host.hh
	var b := InputEventMouseButton.new()
	b.button_index = MOUSE_BUTTON_LEFT
	b.pressed = pressed
	b.position = (design * hh._k + hh._off) * Cfg.ui_k
	hh.input(b)


func _click(act) -> void:
	for r in host.hh.rects:
		if typeof(r[1]) == typeof(act) and r[1] == act:
			_mouse(r[0].get_center())
			return
	check(false, "找不到按钮 %s" % str(act))


## 拉包段单点一下 = 自动拉开
func _tap_bag() -> void:
	var c := Vector2(800, host.hh.D.y - 200)
	_mouse(c)
	_mouse(c, false)


func _ready() -> void:
	Headhunt.clock_frames = true
	Sfx.trace_on = true
	Sfx.trace.clear()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shotdir="):
			out = arg.substr(10)
	assert(out != "")
	Cfg.roster_tickets = {"hunt": 11}
	host = preload("res://scripts/screens/hunt_host.gd").new()
	add_child(host)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.open()
	host.show()
	var hh = host.hh
	await _wait(1.6)
	check(Roster.can_ten(), "11 张：十连可用")
	_click(0)   # 寻访一次
	check(hh.results.size() == 1 and Roster.tickets() == 10 and not hh.ten, "单抽：1 名、剩 %d 张" % Roster.tickets())
	await _wait(0.9)
	_tap_bag()
	await _wait(2.6)
	check(hh.mode == "op", "单抽：逐个揭示（mode=%s）" % hh.mode)
	await _wait(4.2)
	check(hh.mode == "summary", "单抽：本次寻访（mode=%s）" % hh.mode)
	await _wait(1.6)
	_click("ok")
	await _wait(1.6)
	check(hh.mode == "entry" and Roster.can_ten(), "回入口、10 张：十连可用")
	_click(2)   # 十连寻访
	var ids := {}
	for r in hh.results:
		ids[r.id] = true
	check(hh.ten and not hh.ten_first and ids.size() == Roster.TEN and Roster.tickets() == 0, "十连：%d 名不同、剩 %d 张" % [ids.size(), Roster.tickets()])
	var rs: Array = hh.results.map(func(r): return Roster.rarity(r.id))
	check(rs.max() == rs[rs.size() - 1], "最高稀有度排最后（%s）" % [rs])
	await _wait(0.9)
	_tap_bag()
	await _wait(2.0)
	check(hh.mode == "summary", "十连：光炸后直接进十人总览（mode=%s）" % hh.mode)
	await _wait(4.2)
	_click("ok")
	await _wait(1.0)
	check(hh.mode == "entry" and hh.open and not Roster.can_ten() and Roster.ten_short() == 10, "完成回入口：十连灰显、还差 %d 张" % Roster.ten_short())
	await _wait(1.4)
	print("TENREC frames=%d unlocked=%d" % [n, Cfg.roster_unlocked.size()])
	print("SFXTRACE " + JSON.stringify({"frame0": frame0, "trace": Sfx.trace}))
	print("TENREC PASS" if fails == 0 else "TENREC failures=%d" % fails)
	get_tree().quit(0 if fails == 0 else 1)
